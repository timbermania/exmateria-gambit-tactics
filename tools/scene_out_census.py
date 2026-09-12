"""Census every scenario's SUCCESSOR and its SCENE-OUT — the two halves `exit` conflated.

    uv run python tools/scene_out_census.py            # the summary
    uv run python tools/scene_out_census.py --json OUT # machine-readable, per scenario
    uv run python tools/scene_out_census.py --lies     # only where the two disagree

WHY THIS EXISTS
  `ATTACK.OUT`'s `+0x14` byte names **which source supplies the next scenario id** —
  `0x81` the record's own `next_scenario_id`, `0x80` a world-map node script, `0x82`
  reset. That is the **successor** (CONTEXT.md → Campaign spine). It says nothing about
  what the scene does on its way out, and it is structurally incapable of saying so.

  What a scene does on its way out is the **scene-out**, and it lives in the CHUNK. The
  known one is the save prompt: `{43} 06` -> `event_graphics_cmd_mailbox_post(0x0E)`,
  which stops event tasks 2..14 and blocks until dismissed
  (`GAME_STATE_TRANSITIONS.md` §2.8, confirmed live 2026-08-24).

  Because `transition_graph.json` models edges only, it reports every one of these as a
  bare hand-off. For 20 of the 24 that is harmless — they exit to the world map anyway,
  where a screen is expected. For **four** it is a real hole: the graph says "chains
  straight to N" and the game stops and asks you a question first. Scenario 8, *Military
  Academy* -> 9 *Gariland Fight (Setup)*, is one, and it is on the navigator's own walk.

WHAT IT READS (both already committed, both ROM-derived)
  assets/scenarios/scenarios.json        the record: successor_raw, next_scenario_id
  assets/scenarios/chunks/scenario_*_chunk.json   the decoded event bytecode

  A scenario is only reported when BOTH exist (480 of them do).

SCOPE — the scene-out vocabulary is `{43}` ONLY, and only operand 6 is a screen
  The `0x43` dispatcher (an if-chain inside `event_scenario_interpreter` @ 0x80143BD8)
  was read arm by arm; the full operand table is on issue #155. Of its eighteen operands
  exactly one raises a screen. `0xB` blocks on a handshake flag, `0xD`/`0x11` block on
  unit spawn, `4` is the dead-unit fade, the rest are flag writes. So "does this scene
  raise a blocking screen" is decidable from `{43} 06` alone **for the `{43}` family**.
  It is NOT a claim that no other opcode can ever raise one — no such sweep has been
  done. `--json` therefore carries every `{43}` operand each scene uses, not just 6, so
  a later finding can be joined against this without re-deriving it.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path

ASSETS = Path(__file__).resolve().parent.parent / "assets" / "scenarios"
# `scenarios.json` travelled into the almanac addon with `ScenarioDatabase`
# (ADR-0251 dec. 2); the decoded chunks under `chunks/` did not.
SCENARIOS_JSON = (Path(__file__).resolve().parent.parent
                  / "addons" / "exmateria_almanac" / "encounters" / "scenarios.json")

# `ATTACK.OUT` +0x14 -> the successor's SOURCE. Deliberately not the generated
# `GoToWorldMap` spelling: "GoTo" claims a destination the byte does not name.
SUCCESSOR = {0x00: "none", 0x80: "world-map", 0x81: "next-scenario", 0x82: "reset"}

# The one `{43}` operand that raises a blocking screen (the save prompt).
CALL_FUNCTION = "Call Function"
SAVE_PROMPT_FN = 6


def load() -> list[dict]:
    records = json.loads(SCENARIOS_JSON.read_text())["scenarios"]
    rows = []
    for path in sorted((ASSETS / "chunks").glob("scenario_*_chunk.json")):
        if ".raw." in path.name:
            continue
        sid = int(re.search(r"scenario_(\d+)_", path.name).group(1))
        rec = records.get(str(sid))
        if rec is None:
            continue  # a chunk with no record: not a scenario the table knows
        fns = sorted({
            i["params"][0]["value"]
            for i in json.loads(path.read_text())["instructions"]
            if i.get("name") == CALL_FUNCTION and i.get("params")
        })
        step = rec["successor_raw"]
        rows.append({
            "scenario_id": sid,
            "name": rec["scenario_name"],
            "successor": SUCCESSOR.get(step, f"unknown_0x{step:02X}"),
            "next_scenario_id": rec["next_scenario_id"],
            "raises_save_prompt": SAVE_PROMPT_FN in fns,
            "call_function_operands": fns,
        })
    return rows


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--json", metavar="OUT", help="write the per-scenario rows here")
    ap.add_argument("--lies", action="store_true",
                    help="only the scenarios transition_graph.json reports as a bare chain "
                         "edge while the scene blocks on a screen first")
    args = ap.parse_args()

    rows = load()
    if args.json:
        Path(args.json).write_text(json.dumps({"scenarios": rows}, indent=1))
        print(f"wrote {args.json} ({len(rows)} scenarios)")
        return 0

    # The four that matter: a non-world-map successor whose scene-out still blocks.
    lies = [r for r in rows
            if r["raises_save_prompt"] and r["successor"] != "world-map"]

    if not args.lies:
        print(f"{len(rows)} scenarios with both a record and a decoded chunk\n")
        tally = Counter((r["successor"], r["raises_save_prompt"]) for r in rows)
        print(f"{'successor':<16}{'save prompt':<14}count")
        for (succ, save), n in sorted(tally.items()):
            print(f"{succ:<16}{str(save):<14}{n}")
        print()

    print(f"{len(lies)} scenario(s) the edge model reports as a bare hand-off "
          f"while the scene blocks first:")
    for r in lies:
        print(f"  {r['scenario_id']:>3}  next={r['next_scenario_id']:<4} {r['name']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
