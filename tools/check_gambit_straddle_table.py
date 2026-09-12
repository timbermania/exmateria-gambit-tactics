#!/usr/bin/env python3
"""Guard: every `COND_*` the kernel declares has a hand-authored STRADDLE ROW.

    uv run python tools/check_gambit_straddle_table.py [--list] [--selftest]

ADR-0275 dec. 8 / issue #1129. The gambit lab's synthesizer straddles each condition's
boundary from a HAND-AUTHORED table, one row per opcode, because a generic "perturb the
operand by ±1" manufactures false negatives silently -- the worst failure mode available to a
debugging instrument. `COND_IN_RANGE` alone has four boundaries depending on the actor's
weapon, two of them with a NEAR edge as well as a far one, and a blind ±1 gets `ATTACK_ARCING`
wrong on both sides at once.

A table is only a table while it is COMPLETE, and the kernel's opcode list moves: #1114 added
`COND_DISTANCE_LESS`, `COND_DISTANCE_GREATER`, `COND_IS_DEAD` and `COND_IS_ALIVE` in one
afternoon. So this is the guard the ADR asks for in the words it asks for it: a new opcode with
no row REDS, rather than producing a cell that quietly tests nothing.

This is a `static-guard`: it parses two text files and runs no Godot process, which is the
charter's cheapest kind of check (TEST-CHARTER clause 3). It is registered in
`tests/run_all_tests.sh`'s pre-flight, because a guard the suite does not list is a guard
nobody runs -- `tools/check_guard_registry.py` carries the three times that has already cost
this tree.

ARMS.

  arm 1  Every `const int COND_* = N;` in `combat_common.glslinc` has a row in
         `STRADDLE_TABLE`. This is the arm the ADR names.
  arm 2  The other direction. A row naming an opcode the kernel no longer declares is STALE.
         Without this arm the table would only ever grow, and a renamed opcode would leave a
         row that looks like coverage and is not.
  arm 3  Every row carries every required field. A row missing `predicate` is a row nobody can
         check against the kernel; a row missing `measures` cannot say what int B will hold.
  arm 4  THE HONEST-REFUSAL INVARIANT (dec. 9). A row with an empty `negative` must carry a
         non-empty `refusal`, and a row WITH a negative must not carry one. "No negative case
         available" has to say why, or it is indistinguishable from an unfinished row -- and
         dec. 9's whole argument is that the refusal is worth more than a quiet substitution.
  arm 5  Every row's `knob` is in the synthesizer's own `KNOBS` list. A typo'd knob name
         contributes NOTHING to the board (`_knob_set` drops anything not in `KNOBS`), so the
         cell would boot with the default state and still carry the label of a straddle.
  arm 6  Every declared opcode has an arm in `_straddle`'s `match`, and every arm names a
         declared opcode. The table says a boundary EXISTS; the match is what computes it, and
         a row without an arm refuses at run time with "no straddle arm for X" -- discovered
         by whoever runs a cell, months later, instead of here.

WHAT THIS GUARD CANNOT SEE, stated because this tree's blind spots have all eventually scored:

  - **Whether a row is RIGHT.** It checks that a row exists, is complete, and is wired to an
    arm. That the `positive` side is the side the kernel's comparison actually passes is
    checked by running the cell and watching the pair FLIP (dec. 2) -- which is the reason
    mirrors are generated rather than trusted.
  - **`TARGET_*` coverage.** The selector half of dec. 22's gap is MEASURED at run time by
    `GambitCellSynth.encoder_coverage()`, because the answer depends on what the encoder emits
    and not on what any file says. A grep cannot tell an emitted constant from a mentioned one.

`--selftest` proves each arm can fail: it mutates the parsed inputs in memory, one arm at a
time, and asserts the arm reds. A guard nobody has seen fail is a guard nobody should believe.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
KERNEL = ROOT / "src" / "gpu" / "shaders" / "combat_common.glslinc"
SYNTH = ROOT / "src" / "gpu" / "GambitCellSynth.gd"

REQUIRED_FIELDS = ("predicate", "knob", "subject", "measures", "positive", "negative", "refusal")


def declared_opcodes(src: str) -> dict[str, int]:
    """Every `const int COND_NAME = N;` the kernel header declares."""
    return {
        m.group(1): int(m.group(2))
        for m in re.finditer(r"^const int (COND_[A-Z0-9_]+)\s*=\s*(\d+)\s*;", src, re.M)
    }


def table_rows(src: str) -> dict[str, dict[str, str]]:
    """Parse `STRADDLE_TABLE`'s rows out of the GDScript source.

    Deliberately a text parse rather than a Godot load: the whole point of a static guard is
    that it runs without a ~2.3 s engine boot. The shape it relies on is the one the file
    documents -- `"COND_NAME": { "field": <string expr>, ... },` -- and a row that does not
    match it is reported as unparsed rather than skipped, because a silently skipped row is
    coverage this guard would be claiming falsely.
    """
    block = _const_block(src, "STRADDLE_TABLE")
    rows: dict[str, dict[str, str]] = {}
    # Split on the row keys; each row runs to the next key or the end of the block.
    keys = list(re.finditer(r'^\t"(COND_[A-Z0-9_]+)":\s*\{', block, re.M))
    for i, m in enumerate(keys):
        start = m.end()
        end = keys[i + 1].start() if i + 1 < len(keys) else len(block)
        rows[m.group(1)] = _parse_fields(block[start:end])
    return rows


def _parse_fields(body: str) -> dict[str, str]:
    """`"key": "a" + "b", "key2": "c",` -> `{key: "ab", key2: "c"}`.

    A character-level tokenizer rather than a regex, and the reason is a measurement: the rows
    pack several fields onto one line AND continue single values across lines with `+`, so every
    regex that looked right slurped three fields into one and reported a `knob` of
    `subjectmeasures0 — cannot fail`. A guard that mis-parses its own subject is worse than no
    guard -- it scored all fourteen rows as REFUSES, including the ten that straddle fine.
    """
    tokens: list[tuple[str, str]] = []
    i = 0
    while i < len(body):
        c = body[i]
        if c == '"':
            j = i + 1
            buf: list[str] = []
            while j < len(body) and body[j] != '"':
                if body[j] == "\\" and j + 1 < len(body):
                    buf.append(body[j + 1])
                    j += 2
                    continue
                buf.append(body[j])
                j += 1
            tokens.append(("str", "".join(buf)))
            i = j + 1
        elif c in ":,+":
            tokens.append(("punct", c))
            i += 1
        elif c == "#":                      # a trailing comment: skip to end of line
            i = body.find("\n", i)
            if i < 0:
                break
        else:
            i += 1

    fields: dict[str, str] = {}
    k = 0
    while k < len(tokens):
        if tokens[k][0] == "str" and k + 1 < len(tokens) and tokens[k + 1] == ("punct", ":"):
            key = tokens[k][1]
            k += 2
            parts: list[str] = []
            while k < len(tokens) and tokens[k][0] == "str":
                parts.append(tokens[k][1])
                k += 1
                if k < len(tokens) and tokens[k] == ("punct", "+"):
                    k += 1
                    continue
                break
            fields[key] = "".join(parts)
            continue
        k += 1
    return fields


def knob_names(src: str) -> list[str]:
    """The `KNOBS` list -- every knob name `_knob_set` will actually honour."""
    block = _const_block(src, "KNOBS")
    return re.findall(r'"([^"]*)"', block)


def straddle_arms(src: str) -> set[str]:
    """Every opcode named by a `match` arm inside `_straddle`."""
    start = src.index("static func _straddle(")
    end = src.index("static func _in_range_straddle(")
    body = src[start:end]
    arms: set[str] = set()
    for m in re.finditer(r'^\t\t((?:"COND_[A-Z0-9_]+"(?:,\s*)?)+):\s*$', body, re.M):
        arms.update(re.findall(r'"(COND_[A-Z0-9_]+)"', m.group(1)))
    return arms


def _const_block(src: str, name: str) -> str:
    """The text of `const NAME := {...}` / `[...]`, brace-matched."""
    m = re.search(rf"^const {name} :?= ([\{{\[])", src, re.M)
    if not m:
        raise SystemExit(f"FAIL: {SYNTH.name} has no `const {name}`")
    open_ch = m.group(1)
    close_ch = "}" if open_ch == "{" else "]"
    depth = 0
    i = m.end() - 1
    in_str = False
    while i < len(src):
        c = src[i]
        if in_str:
            if c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c == open_ch:
            depth += 1
        elif c == close_ch:
            depth -= 1
            if depth == 0:
                return src[m.end() : i]
        i += 1
    raise SystemExit(f"FAIL: `const {name}` in {SYNTH.name} is unterminated")


def check(opcodes: dict[str, int], rows: dict[str, dict[str, str]],
          knobs: list[str], arms: set[str]) -> list[str]:
    problems: list[str] = []

    # arm 1 -- the arm ADR-0275 dec. 8 names.
    for name in sorted(opcodes):
        if name not in rows:
            problems.append(
                f"arm 1: the kernel declares {name} = {opcodes[name]} and STRADDLE_TABLE has "
                f"no row for it. Author one in {SYNTH.name} (ADR-0275 dec. 8): name the "
                f"kernel's own predicate, which knob moves the boundary, whose state that knob "
                f"is, what int B measures, and which side is positive. If the opcode cannot be "
                f"straddled, say so in `refusal` and leave `negative` empty -- dec. 9 makes "
                f'"no negative case available" a first-class answer.'
            )

    # arm 2 -- the other direction; a ratchet needs both.
    for name in sorted(rows):
        if name not in opcodes:
            problems.append(
                f"arm 2: STRADDLE_TABLE has a row for {name}, which the kernel no longer "
                f"declares. A stale row reads as coverage. Delete it, or fix the rename."
            )

    for name in sorted(rows):
        row = rows[name]
        # arm 3
        missing = [f for f in REQUIRED_FIELDS if f not in row]
        if missing:
            problems.append(f"arm 3: {name}'s row is missing {', '.join(missing)}")
            continue
        # arm 4 -- the honest-refusal invariant.
        has_neg = row["negative"].strip() != ""
        has_refusal = row["refusal"].strip() != ""
        if not has_neg and not has_refusal:
            problems.append(
                f"arm 4: {name} declares no negative case and gives no reason. dec. 9 requires "
                f'the refusal to SAY WHY -- "no negative case available" with no cause is '
                f"indistinguishable from an unfinished row, and the refusal count is meant to "
                f"be a to-do list."
            )
        if has_neg and has_refusal:
            problems.append(
                f"arm 4: {name} carries BOTH a negative case and a refusal. One of them is "
                f"wrong, and a reader cannot tell which."
            )
        # arm 5
        if row["knob"] not in knobs:
            problems.append(
                f"arm 5: {name}'s knob `{row['knob']}` is not in KNOBS. `_knob_set` drops any "
                f"knob not listed there, so the cell would boot with the DEFAULT board while "
                f"still carrying the label of a straddle -- dec. 10's productive failure."
            )

    # arm 6 -- the table says a boundary exists; the match is what computes it.
    for name in sorted(opcodes):
        if name not in arms:
            problems.append(
                f"arm 6: {name} has no arm in `_straddle`'s match. A row without an arm refuses "
                f'at RUN time with "no straddle arm for {name}" -- found by whoever runs a '
                f"cell, not here."
            )
    for name in sorted(arms):
        if name not in opcodes:
            problems.append(
                f"arm 6: `_straddle` has an arm for {name}, which the kernel does not declare."
            )
    return problems


def _selftest(opcodes, rows, knobs, arms) -> int:
    """Each arm, provoked. A guard nobody has seen fail is a guard nobody should believe."""
    import copy

    cases = []

    o = dict(opcodes); o["COND_INVENTED"] = 99
    cases.append(("arm 1", (o, rows, knobs, arms)))

    r = copy.deepcopy(rows); r["COND_RETIRED"] = dict(next(iter(rows.values())))
    cases.append(("arm 2", (opcodes, r, knobs, arms)))

    r = copy.deepcopy(rows); first = sorted(r)[0]; r[first].pop("measures")
    cases.append(("arm 3", (opcodes, r, knobs, arms)))

    r = copy.deepcopy(rows); r["COND_ALWAYS"]["refusal"] = ""
    cases.append(("arm 4 (no negative, no reason)", (opcodes, r, knobs, arms)))

    r = copy.deepcopy(rows); r["COND_HP_BELOW"]["refusal"] = "because"
    cases.append(("arm 4 (both)", (opcodes, r, knobs, arms)))

    r = copy.deepcopy(rows); r["COND_HP_BELOW"]["knob"] = "dummy_hp_percnet"
    cases.append(("arm 5", (opcodes, r, knobs, arms)))

    a = set(arms); a.discard("COND_HP_BELOW")
    cases.append(("arm 6 (missing arm)", (opcodes, rows, knobs, a)))

    a = set(arms); a.add("COND_NOT_A_THING")
    cases.append(("arm 6 (stale arm)", (opcodes, rows, knobs, a)))

    failures = 0
    for label, args in cases:
        if check(*args):
            print(f"  selftest OK   {label} reds when provoked")
        else:
            print(f"  selftest FAIL {label} stayed green under a seeded break")
            failures += 1
    if check(opcodes, rows, knobs, arms):
        print("  selftest FAIL the UNMUTATED tree is already red — fix that first")
        failures += 1
    else:
        print("  selftest OK   the unmutated tree is green (the positive control)")
    return failures


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true", help="print the table and exit 0")
    ap.add_argument("--selftest", action="store_true", help="prove each arm can fail")
    args = ap.parse_args()

    kernel_src = KERNEL.read_text()
    synth_src = SYNTH.read_text()
    opcodes = declared_opcodes(kernel_src)
    rows = table_rows(synth_src)
    knobs = knob_names(synth_src)
    arms = straddle_arms(synth_src)

    if not opcodes:
        print(f"FAIL: parsed zero COND_* out of {KERNEL}. The instrument, not the tree.")
        return 1
    if not rows:
        print(f"FAIL: parsed zero STRADDLE_TABLE rows out of {SYNTH}. The instrument.")
        return 1

    if args.list:
        print(f"{len(opcodes)} COND_* declared, {len(rows)} straddle rows, {len(arms)} arms\n")
        for name in sorted(opcodes, key=lambda n: opcodes[n]):
            row = rows.get(name, {})
            side = "REFUSES" if not row.get("negative", "").strip() else "straddles"
            print(f"  {opcodes[name]:>2}  {name:<22} {side:<10} knob={row.get('knob', '?')}")
        return 0

    if args.selftest:
        print("Straddle-table guard selftest (ADR-0275 dec. 8):")
        return 1 if _selftest(opcodes, rows, knobs, arms) else 0

    problems = check(opcodes, rows, knobs, arms)
    if problems:
        print(f"FAIL: {len(problems)} straddle-table problem(s).\n")
        for p in problems:
            print(f"  - {p}\n")
        return 1
    refusing = [n for n in rows if not rows[n].get("negative", "").strip()]
    print(
        f"OK: {len(opcodes)} COND_* declared, all {len(rows)} rows present, complete and "
        f"wired to a `_straddle` arm. {len(refusing)} row(s) honestly refuse a negative case "
        f"({', '.join(sorted(refusing))})."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
