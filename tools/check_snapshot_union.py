#!/usr/bin/env python3
"""Guard: every unit-snapshot field the PER-FRAME combat path reads is declared in
`GPUCombatPacker.SNAPSHOT_HOT_UNION`.

    uv run python tools/check_snapshot_union.py [--list]

WHY THIS EXISTS. `CombatLoop._check_state_changes()` and the visual bridge used to
share a snapshot carrying all 101 `SNAPSHOT_FIELDS` for all 16 units, rebuilt every
ticking frame — for dead units and empty roster slots too. Measured ~1.8 ms/frame,
and it was the one combat cost that never decayed as units died
(`docs/GPU-ARENA-PERF.md`, F22/W1). Both per-frame callers now take
`get_battle_unit_states_hot()`, which builds only the 31 fields anything on that
path actually reads.

**The failure mode of that trade is SILENT.** A consumer reading a field the union
omits gets `state.get("x", default)` — the default, quietly, with no error and no
crash; the battle simply behaves a little differently forever. `state["x"]` at
least raises, but only four bracket reads exist and every other read is `.get()`.
Nothing else in the suite can see this: the values that ARE present are correct, so
the fidelity arms in `GPULeanColumnReadTest` pass, and a battle with a subtly wrong
`damage_frame` still completes and still prints `[PASS]`.

WHY IT WALKS THE CALL GRAPH INSTEAD OF GREPPING. This is the exact mistake round 20
of that investigation made: it sized the union by grepping the two files the
snapshot is handed to *by name* (`GPUCombatInterpreter`, `GPUVisualBridge`) and got
15 fields. A per-frame dictionary spreads by being **passed**, not by being fetched
— grepping `get_all_unit_states` finds the fetch sites, and every real consumer is
one call-graph hop further out, sharing no spelling with it. The three it missed:

    CombatLoop's own `_apply_*` pump   21 fields   _apply_combat_event(i, state, ev)
    ProjectileManager                   7 fields   spawn_from_gpu / update
    CinematicDebugProbe                 8 fields   probe / on_cinematic_began|ended

True union: 31 of 101. So this guard starts at `_check_state_changes()` and
`_handle_revives()`, walks `CombatLoop.gd`'s intra-file call graph to fixpoint, and
unions the field reads it finds with those of the four files that receive the
dictionary.

COMPUTED KEYS ARE REFUSED, NOT IGNORED. `state.get(key)` where `key` is a variable
names a field no grep can see. That is not hypothetical: `GPUCombatInterpreter`
reads its five break-affected stats as `state.get(sf[0], 0)` over a `STAT_FIELDS`
const, and leaving those out of the union did not read a wrong number — it read the
DEFAULT, so every unit PA/MA/Speed/WP fell to 0 on tick 1 and `_sync_stat_to_unit`
wrote it into `unit_stats`. So this guard does not skip a computed read: it FAILS on
one unless the site is registered in `COMPUTED_KEY_SITES` below with the keys it can
produce. An invisible read becomes a visible, reviewed one.

TESTS READ `_all_states` TOO, AND THAT IS THE SECOND SWEEP. `_all_states` is a field
on `CombatHost`, so any test subclassing it can index the per-frame snapshot — and
three did. `GambitScenarioRunner` read `current_gambit` off it; that field is not in
the union, so it silently became `.get()`'s default of `-1` and **62 of 82 gambit
fixtures went red** with `gambit_fired_at_slot ... slot -1 (expected 0)`. Nothing in
the first sweep could see it: the file is not a production consumer. So this guard
also walks every `.gd` under `src/` and `tests/` for `_all_states[...]` reads and
requires those fields to be in the union as well. The fix for a hit is usually NOT to
widen the union — a diagnostic observer should ask for the full snapshot via
`gpu_state_reader.get_all_unit_states()`, the same move production makes through
`refresh_all_states_now()`.

WHAT IT STILL CANNOT SEE. A read reached through a `Callable`, and a consumer file
that is not in `RECEIVER_FILES` — including one a *receiver* hands the dictionary on
to, which is how `prev_move_pos` / `move_step_id` escaped: `GPUVisualBridge` passes
`state` into `GPUMovementInterpreter.classify()`, and that file was not listed, so
the union never covered the two fields that decide whether a unit interpolates or
teleports. If you add either, add it here too — a guard that silently stops covering
a path is worse than no guard. The runtime half
of the defence is `tests/GPUSnapshotUnionTest.tscn`, which replays a seeded battle
with every non-union field poisoned.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

PACKER = ROOT / "src/gpu/GPUCombatPacker.gd"
HOST = ROOT / "src/gpu/CombatLoop.gd"

# Entry points: the two per-frame functions that take the lean snapshot.
ROOTS = ("_check_state_changes", "_handle_revives")

# Files that RECEIVE a unit-state dictionary as a parameter from the host. These
# are consumers, not fetchers — grepping for the accessor never finds them.
#
# `CinematicManager.gd` is deliberately NOT here, and the reason is worth keeping:
# it reads field-heavy state (`casting_ability_id`, `cast_target`, `flags`) off
# `_base._all_states`, but every one of its three read sites calls
# `refresh_all_states_now()` first, which re-fills `_all_states` with the FULL
# 101-field form. It is a cold caller wearing a hot caller's clothes. If that
# refresh is ever dropped, add the file here — the reads it makes would instantly
# become union business.
#
# `GPUMovementInterpreter.gd` is here because a receiver can hand the dictionary
# ON. `GPUVisualBridge.update_visual_positions` passes `state` straight into
# `_interp.classify(i, state)`, one hop past where this list originally stopped —
# and that hop is where `prev_move_pos` / `move_step_id` are read. Leaving them
# out of the union did not read a wrong number: `prev_move_pos` fell to its
# default of -1, `from_packed >= 0` went false, and classify() returned NO_MOVE
# for every unit on every frame, so units teleported between tiles instead of
# walking. That is the fifth miss of this union and the first one visible to a
# player. When a receiver passes the snapshot to a new file, add the file here.
RECEIVER_FILES = (
    "src/gpu/GPUCombatInterpreter.gd",
    "src/gpu/GPUVisualBridge.gd",
    "src/gpu/GPUMovementInterpreter.gd",
    "src/projectiles/ProjectileManager.gd",
    "src/debug/CinematicDebugProbe.gd",
)

# Receiver-side identifiers that hold a unit-state dictionary. A read off anything
# else in these files (a spawn record, a job dict, an sfx table) is not our field.
SNAPSHOT_RECEIVERS = (
    "state", "s", "st", "us", "unit_state", "snapshot",
    "attacker_state", "caster_state", "target_state",
    "caster_state_dc", "target_state_dc",
    "all_states", "_all_states", "states", "vis_states",
)

_RECV = "|".join(
    sorted((re.escape(r) for r in SNAPSHOT_RECEIVERS), key=len, reverse=True)
)
# `<receiver>[…]?` then `.get("field"` or `["field"]`
FIELD_RE = re.compile(
    rf'\b(?:{_RECV})(?:\[[^\]\n]*\])?\s*(?:\.get\(\s*"([a-z_0-9]+)"|\[\s*"([a-z_0-9]+)"\s*\])'
)
# A `.get(` on a snapshot receiver whose first argument is NOT a quoted literal.
COMPUTED_RE = re.compile(rf'\b(?:{_RECV})(?:\[[^\]\n]*\])?\s*\.get\(\s*([^"\s)][^,)\n]*)')

# Registered computed-key reads: (file, the keys that site can produce, why).
# A computed read NOT listed here is a hard failure — see the module docstring.
COMPUTED_KEY_SITES = {
    "GPUCombatInterpreter.gd": (
        ("pa", "ma", "speed", "wp", "s_ev"),
        "STAT_FIELDS break detection: `state.get(sf[0], 0)` / `state.get(key, 0)`",
    ),
}

FUNC_RE = re.compile(r"^func\s+([A-Za-z_0-9]+)\s*\(", re.M)
CALL_RE = re.compile(r"\b([_A-Za-z][A-Za-z_0-9]*)\s*\(")


def _read(rel: str | Path) -> str:
    """File text with whole-line comments dropped — a field name quoted inside a
    comment is prose, not a read, and counting it makes the guard lie both ways."""
    p = rel if isinstance(rel, Path) else ROOT / rel
    return "\n".join(
        "" if line.lstrip().startswith("#") else line
        for line in p.read_text(encoding="utf-8").split("\n")
    )


def declared_union() -> list[str]:
    src = _read(PACKER)
    m = re.search(r"SNAPSHOT_HOT_UNION[^=]*=\s*\[(.*?)\n\]", src, re.S)
    if not m:
        sys.exit("check_snapshot_union: SNAPSHOT_HOT_UNION not found in GPUCombatPacker.gd")
    return re.findall(r'"([a-z_0-9]+)"', m.group(1))


def snapshot_fields() -> list[str]:
    src = _read(PACKER)
    m = re.search(r"SNAPSHOT_FIELDS\s*:?=\s*\{(.*?)\n\}", src, re.S)
    if not m:
        sys.exit("check_snapshot_union: SNAPSHOT_FIELDS not found in GPUCombatPacker.gd")
    return re.findall(r'"([a-z_0-9]+)"\s*:', m.group(1))


def host_function_bodies() -> dict[str, str]:
    """Split CombatLoop.gd into `func name -> body`, body running to the next `func`."""
    src = _read(HOST).split("\n")
    starts = [(i, m.group(1)) for i, line in enumerate(src)
              if (m := FUNC_RE.match(line + "\n"))]
    bodies: dict[str, str] = {}
    for idx, (line_no, name) in enumerate(starts):
        end = starts[idx + 1][0] if idx + 1 < len(starts) else len(src)
        bodies[name] = "\n".join(src[line_no:end])
    return bodies


def reachable_from(bodies: dict[str, str], roots) -> set[str]:
    seen: set[str] = set()
    stack = [r for r in roots]
    while stack:
        name = stack.pop()
        if name in seen or name not in bodies:
            continue
        seen.add(name)
        stack.extend(c for c in CALL_RE.findall(bodies[name])
                     if c in bodies and c not in seen)
    return seen


def fields_in(text: str) -> set[str]:
    return {a or b for a, b in FIELD_RE.findall(text)}


def computed_reads_in(text: str) -> list[str]:
    """Snapshot `.get()` calls whose key is an expression rather than a literal."""
    return [m.strip() for m in COMPUTED_RE.findall(text)]


ALL_STATES_RE = re.compile(
    r'_all_states\[[^\]\n]*\]\s*(?:\.get\(\s*"([a-z_0-9]+)"|\[\s*"([a-z_0-9]+)"\s*\])'
)


def all_states_readers(known: set[str]) -> dict[str, set[str]]:
    """Every `.gd` under src/ and tests/ that indexes `_all_states` and reads a
    snapshot field off it, mapped file -> fields. `_all_states` is the LEAN
    snapshot since W1, so anything read here must be in the union."""
    out: dict[str, set[str]] = {}
    for base in ("src", "tests"):
        for path in sorted((ROOT / base).rglob("*.gd")):
            fields = {a or b for a, b in ALL_STATES_RE.findall(_read(path))} & known
            if fields:
                out[str(path.relative_to(ROOT))] = fields
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true",
                    help="print the derived union and where each field comes from")
    args = ap.parse_args()

    union = declared_union()
    known = set(snapshot_fields())

    # A typo in the union reads offset 0 forever — catch it here, not at runtime.
    bogus = [k for k in union if k not in known]
    if bogus:
        print("check_snapshot_union: FAIL — SNAPSHOT_HOT_UNION names "
              f"{len(bogus)} key(s) that are not SNAPSHOT_FIELDS: {', '.join(sorted(bogus))}")
        return 1
    dupes = sorted({k for k in union if union.count(k) > 1})
    if dupes:
        print(f"check_snapshot_union: FAIL — SNAPSHOT_HOT_UNION repeats: {', '.join(dupes)}")
        return 1

    bodies = host_function_bodies()
    missing_roots = [r for r in ROOTS if r not in bodies]
    if missing_roots:
        print("check_snapshot_union: FAIL — entry point(s) "
              f"{', '.join(missing_roots)} no longer exist in CombatLoop.gd. "
              "The per-frame path was renamed; re-point ROOTS or this guard covers nothing.")
        return 1

    reached = reachable_from(bodies, ROOTS)
    origin: dict[str, set[str]] = {}
    unregistered: list[tuple[str, str]] = []

    def absorb(label: str, text: str) -> None:
        for f in fields_in(text) & known:
            origin.setdefault(f, set()).add(label)
        base = label.split(".")[0] + ".gd" if label.startswith("CombatLoop") else label
        registered = COMPUTED_KEY_SITES.get(base)
        for expr in computed_reads_in(text):
            if registered is None:
                unregistered.append((label, expr))
            else:
                for f in registered[0]:
                    origin.setdefault(f, set()).add(f"{label} (computed)")

    for name in sorted(reached):
        absorb(f"CombatLoop.{name}", bodies[name])
    for rel in RECEIVER_FILES:
        path = ROOT / rel
        if not path.exists():
            print(f"check_snapshot_union: FAIL — consumer {rel} no longer exists. "
                  "Re-point RECEIVER_FILES; a dropped entry silently narrows this guard.")
            return 1
        absorb(Path(rel).name, _read(path))

    # A registered site still has to be honoured even if its file grew no new reads.
    for fname, (keys, _why) in COMPUTED_KEY_SITES.items():
        for f in keys:
            if f in known:
                origin.setdefault(f, set()).add(f"{fname} (computed)")

    if unregistered:
        print(f"check_snapshot_union: FAIL — {len(unregistered)} computed-key read(s) on a "
              "snapshot, at sites this guard has not been told how to resolve:")
        for label, expr in unregistered:
            print(f"    {label}: state.get({expr}…)")
        print("\n  A computed key names a field no grep can see, and omitting it from the")
        print("  union returns `.get()`'s DEFAULT rather than a wrong number — that is how")
        print("  every unit's PA/MA/Speed/WP fell to 0 on tick 1. Register the site in")
        print("  COMPUTED_KEY_SITES with the keys it can produce, and add them to the union.")
        return 1

    required = set(origin)
    missing = sorted(required - set(union))

    if args.list:
        print(f"check_snapshot_union: {len(reached)} functions reachable from "
              f"{'/'.join(ROOTS)} in CombatLoop.gd; {len(RECEIVER_FILES)} receiver files")
        for f in sorted(required):
            mark = " " if f in union else "!"
            print(f"  {mark} {f:<24} {', '.join(sorted(origin[f]))}")
        unused = sorted(set(union) - required)
        if unused:
            print(f"\n  declared but no read found ({len(unused)}): {', '.join(unused)}")
            print("  (not an error — a field may be read through a form this guard cannot see)")

    # --- second sweep: `_all_states` readers anywhere, tests included -----------
    host_readers = all_states_readers(known)
    host_missing: list[tuple[str, str]] = []
    for rel, fields in host_readers.items():
        for f in sorted(fields - set(union)):
            host_missing.append((rel, f))
    if args.list and host_readers:
        print(f"\n  `_all_states` readers ({len(host_readers)} files):")
        for rel, fields in host_readers.items():
            print(f"    {rel}: {', '.join(sorted(fields))}")
    if host_missing:
        print(f"check_snapshot_union: FAIL — {len(host_missing)} field(s) read off "
              "`_all_states` are NOT in GPUCombatPacker.SNAPSHOT_HOT_UNION:")
        for rel, f in host_missing:
            print(f"    {f:<24} read by {rel}")
        print("\n  `_all_states` is the LEAN snapshot — these silently return `.get()`'s")
        print("  DEFAULT. This is how 62 of 82 gambit fixtures went red on `slot -1`.")
        print("  Usually the fix is NOT to widen the union: a diagnostic observer should")
        print("  read gpu_state_reader.get_all_unit_states() (the full form, served off")
        print("  the same per-version cache) instead of indexing _all_states.")
        return 1

    if missing:
        print(f"check_snapshot_union: FAIL — {len(missing)} field(s) are read on the "
              "per-frame path but are NOT in GPUCombatPacker.SNAPSHOT_HOT_UNION:")
        for f in missing:
            print(f"    {f:<24} read by {', '.join(sorted(origin[f]))}")
        print("\n  Each one silently returns `.get()`'s DEFAULT at runtime — no error, no")
        print("  crash, just a battle that behaves slightly wrong forever. Add it to the")
        print("  union in src/gpu/GPUCombatPacker.gd, or move the read off the per-frame")
        print("  path onto the full get_all_unit_states().")
        return 1

    print(f"check_snapshot_union: OK — {len(required)} fields read on the per-frame path, "
          f"all {len(union)} union keys valid ({len(reached)} functions reachable from "
          f"{'/'.join(ROOTS)}, {len(RECEIVER_FILES)} receiver files, "
          f"{len(host_readers)} `_all_states` readers)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
