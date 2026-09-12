"""Parse EVENT/BTLEVT.BIN into a structured BattleConditionals artifact + story graph.

**BattleConditionals are FFT's battle "director".** Each battle scenario's record
carries a ``battle_conditionals_id`` (ATTACK.OUT field 0x16); that id selects one
*set* of conditions from BTLEVT.BIN. During combat the engine evaluates the set every
tick: each *condition* is a run of *predicate* commands (``Unit Present``, ``HP >=``,
``Active Turn``, ``Variable`` checks) followed by *action* commands (``Variable =``,
``Victory``, and crucially ``Run Scenario N``). When a condition's predicates all hold,
its actions fire — and ``Run Scenario N`` is what advances the story to the next
scenario (writing N to RAM ``0x8016A014``). This is the mechanism that chains
setup → deploy → mid-battle cutscene → victory across a battle group.

See ``research/working_documents/SCENARIO_LOADING.md`` §3.2.5/§3.2.6.

BTLEVT.BIN is a two-level pointer structure (reverse-engineered 2026-07-02, validated
byte-for-byte against the live BC[1] RAM dump at ``0x80049A18``):

    [0x0000 .. H)          header: H/2 u16-LE pointers, one per battle_conditionals_id.
                           H = value of the first pointer (== where the set records begin).
    [ptr[i] .. ptr[i+1])   SET RECORD i: a 0x0000-terminated list of u16-LE pointers,
                           one per condition, each pointing into the bytecode region.
    [ ... .. EOF)          bytecode region: contiguous 2-byte-opcode command stream.
                           A condition spans [cptr .. next-cptr) (or to the next set's
                           first condition / EOF for the last condition in the file).

Emits ``assets/scenarios/battle_conditionals.json``:
    { bc_id: { conditions: [ { predicates:[...], actions:[...], run_scenarios:[...],
                               commands:[<disasm>] } ] } }

and folds a compact ``story`` edge-list into it per bc_id for the graph view.

Usage:
    uv run python tools/export_battle_conditionals.py            # write artifact
    uv run python tools/export_battle_conditionals.py --graph    # also print story graph
    uv run python tools/export_battle_conditionals.py --check    # validate vs groups; no write
"""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path

from _fft_bytecode import BC_CATALOG, disasm, format_json, load_opcodes
from _repo_paths import almanac_dir, assets_dir, fft_extract_root

RUN_SCENARIO_OP = 0x0019
# In BattleConditionals EVERY opcode except Run Scenario is a *requirement* (a check
# against combat / variable / party state — including "Variable =" which is an equality
# test, not an assignment, and "Victory" which tests the battle-won state). There is no
# assign-variable opcode: the director only reads state. A condition is therefore a list
# of requirements terminated by exactly one Run Scenario result (verified: 0 violations
# across all 146 sets). All requirements true => fire that edge.


def _u16(buf: bytes, off: int) -> int:
    return struct.unpack_from("<H", buf, off)[0]


def parse_btlevt(path: Path, table) -> dict[int, dict]:
    """Return {bc_id: {"conditions": [...]}} for every set in BTLEVT.BIN."""
    data = path.read_bytes()
    header_len = _u16(data, 0)
    n_ptrs = header_len // 2
    set_ptrs = [_u16(data, i * 2) for i in range(n_ptrs)]
    bytecode_start = set_ptrs[-1]  # last header entry == start of bytecode region

    # Gather every condition pointer across all sets, in file order, so we can bound
    # each condition's command span by the *next* condition pointer anywhere in the file.
    def read_condition_ptrs(set_start: int, set_end: int) -> list[int]:
        ptrs = []
        o = set_start
        while o + 2 <= set_end:
            v = _u16(data, o)
            o += 2
            if v == 0:
                break
            ptrs.append(v)
        return ptrs

    # set record i spans [set_ptrs[i], set_ptrs[i+1]). The last set (i = n_ptrs-1) has
    # no following header entry; its record runs to the start of the bytecode region.
    # The bytecode region begins at the smallest condition pointer (all header entries
    # sit below it, all condition pointers at/above it), so we discover that boundary
    # from the records themselves. bc_id == set index (set[0] is the unused stub).
    sets_conditions: dict[int, list[int]] = {}
    for i in range(n_ptrs - 1):
        sets_conditions[i] = read_condition_ptrs(set_ptrs[i], set_ptrs[i + 1])
    region_start = min(
        (c for cps in sets_conditions.values() for c in cps), default=bytecode_start
    )
    sets_conditions[n_ptrs - 1] = read_condition_ptrs(set_ptrs[-1], region_start)

    all_cptrs = sorted({c for cps in sets_conditions.values() for c in cps})

    def next_boundary(cptr: int) -> int:
        for c in all_cptrs:
            if c > cptr:
                return c
        return len(data)

    result: dict[int, dict] = {}
    for bc_id, cptrs in sets_conditions.items():
        conditions = []
        for cptr in cptrs:
            end = next_boundary(cptr)
            insts = disasm(data, table, chunk_base=0, start=cptr, end=end)
            # requirements = every command except the terminal Run Scenario result.
            requirements = [format_json(i) for i in insts if i.opcode != RUN_SCENARIO_OP]
            run = [i.params[0]["value"] for i in insts if i.opcode == RUN_SCENARIO_OP]
            conditions.append(
                {
                    "offset": cptr,
                    "requirements": requirements,
                    "run_scenario": run[0] if run else None,
                    "commands": [format_json(i) for i in insts],
                }
            )
        result[bc_id] = {"conditions": conditions, "bytecode_start": bytecode_start}
    return result


def load_groups() -> dict[int, dict]:
    """bc_id -> group dict from scenario_groups.json (0 = no group)."""
    p = assets_dir("scenarios") / "scenario_groups.json"
    groups = json.loads(p.read_text())["groups"]
    return {g["battle_conditionals_id"]: g for g in groups if g["battle_conditionals_id"]}


def check(sets: dict[int, dict], groups: dict[int, dict]) -> int:
    """Validate the parse. A set is well-formed when every Run Scenario target is a
    real scenario id. Targets that land outside the set's own group are legal
    *cross-group edges* (shared victory scenes, late add-ins) — reported, not failed."""
    scen = json.loads(almanac_dir("encounters/scenarios.json").read_text())
    scen = scen.get("scenarios", scen)
    valid_ids = {int(k) for k in scen}

    ok = fail = 0
    cross = []
    for bc_id, g in sorted(groups.items()):
        s = sets.get(bc_id)
        if not s:
            print(f"  [FAIL] bc_id {bc_id}: no set parsed (group root {g['group_root_id']})")
            fail += 1
            continue
        members = {m["scenario_id"] for m in g["members"]}
        targets = {c["run_scenario"] for c in s["conditions"] if c["run_scenario"] is not None}
        bad = sorted(t for t in targets if t not in valid_ids)
        if bad:
            print(f"  [FAIL] bc_id {bc_id} (root {g['group_root_id']}): invalid targets {bad}")
            fail += 1
            continue
        ok += 1
        ext = sorted(targets - members)
        if ext:
            cross.append((bc_id, g["group_root_id"], ext))

    print(f"\nsets parsed: {len(sets)}; groups with bc: {len(groups)}; OK: {ok}, FAIL: {fail}")
    print(f"cross-group edges (findings, not errors): {len(cross)}")
    for bc_id, root, ext in cross:
        print(f"    bc[{bc_id}] (root {root}) → {ext}")
    return 0 if fail == 0 else 1


def print_graph(sets: dict[int, dict], groups: dict[int, dict], limit: int | None) -> None:
    scen = json.loads(almanac_dir("encounters/scenarios.json").read_text())
    scen = scen.get("scenarios", scen)

    def nm(sid: int) -> str:
        return scen.get(str(sid), {}).get("scenario_name", "?")

    shown = 0
    for bc_id, g in sorted(groups.items()):
        if limit is not None and shown >= limit:
            break
        s = sets.get(bc_id)
        if not s:
            continue
        shown += 1
        print(f"\nbc[{bc_id}]  group root {g['group_root_id']}  {g['map_name']}")
        for m in g["members"]:
            print(f"     · {m['scenario_id']:>3} {m['name']}")
        for ci, c in enumerate(s["conditions"]):
            if c["run_scenario"] is None:
                continue
            guard = ", ".join(
                f"{p['name']}({', '.join(str(pp['value']) for pp in p['params'])})"
                for p in c["requirements"]
            ) or "(unconditional)"
            tgt = c["run_scenario"]
            print(f"       cond{ci}: [{guard}]  ── Run Scenario {tgt} → {nm(tgt)}")


def main() -> int:
    ap = argparse.ArgumentParser(description="Parse BTLEVT.BIN → battle_conditionals.json")
    ap.add_argument("--btlevt", type=Path, default=None, help="path to BTLEVT.BIN")
    ap.add_argument("--graph", action="store_true", help="print the story graph")
    ap.add_argument("--check", action="store_true", help="validate vs groups; no write")
    ap.add_argument("--limit", type=int, default=None, help="graph: only first N groups")
    args = ap.parse_args()

    btlevt = args.btlevt or (fft_extract_root() / "EVENT" / "BTLEVT.BIN")
    table = load_opcodes(BC_CATALOG)
    sets = parse_btlevt(btlevt, table)
    groups = load_groups()

    if args.check:
        return check(sets, groups)
    if args.graph:
        print_graph(sets, groups, args.limit)

    out = almanac_dir("encounters/battle_conditionals.json")
    doc = {
        "_comment": (
            "Parsed by tools/export_battle_conditionals.py from EVENT/BTLEVT.BIN. "
            "Keyed by battle_conditionals_id. Each condition: predicates (guards) + "
            "actions; run_scenarios are the story-graph edges (Run Scenario N). "
            "Regenerate; do not hand-edit."
        ),
        "set_count": len(sets),
        "sets": {str(k): v for k, v in sets.items()},
    }
    out.write_text(json.dumps(doc, indent=2))
    print(f"wrote {len(sets)} BC sets to {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
