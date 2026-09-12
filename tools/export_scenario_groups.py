"""Derive FFT "battle groups" from the scenario table and emit scenario_groups.json.

FFT's unit of loading is **not the scenario — it's the "battle group": a run of
consecutive scenarios that share the same ``(map_id, entd_idx)``.** The map, the
ENTD roster, and the EVTCHR sprite/anim data load **once** at the top of the group
(the "(Setup)" scenario); continuation scenarios run against that persistent runtime
state and deliberately omit the setup opcodes (``Load EVTCHR`` 0x58, ``Warp Unit``
0x5F, etc.). To *view* a continuation scenario (e.g. scenario 5, "Orbonne Battle —
Gafgarion and Agrias chat") we therefore have to boot the environment from its
group's root, then run the target scenario's bytecode on top.

Groups are 100% ROM-derivable from three native fields of each scenario record
(parsed from ``EVENT/ATTACK.OUT`` into ``assets/scenarios/scenarios.json``):

1. **Membership** = maximal contiguous run of equal ``(map_id, entd_idx)`` over the
   scenarios sorted by ``scenario_id``. (Contiguity guards against a later,
   unrelated reuse of the same map+entd being wrongly merged into an earlier group.)
2. **Group root / setup** = the member with ``battle_conditionals_id != 0`` — always
   the first member; interior members carry ``bc == 0``. A couple of early groups
   (e.g. the Orbonne Prayer intro, id 1-2) have no ``bc`` at all; there the first
   member is the root.
3. **Group successor** = ``successor`` on the last member
   (``GoToWorldMap`` / ``GoToNextScenario`` / ``ResetGame`` / ...).

**Roles.** Only ``setup`` (the root) vs ``member`` is emitted, because
battle-vs-cutscene is *not* ROM-derivable: the battle scenario's bytecode is just a
short cutscene intro (the fight itself is gameplay, not script), and some groups have
no battle at all (e.g. "Family Meeting"). The raw ``scenario_name`` — which already
encodes the human-readable role in its parenthetical — is carried through so a human
(or the F3 picker) can judge.

This is a **regenerable artifact** derived from the ISO-sourced scenario table, so it
satisfies the "assets come from the ISO" rule (see ``feedback_assets_from_iso.md``):
it is a generator, not a hand-edited file.

Usage:
    uv run python tools/export_scenario_groups.py            # write the artifact
    uv run python tools/export_scenario_groups.py --print    # also dump the table
    uv run python tools/export_scenario_groups.py --check    # verify known groups, no write
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from _repo_paths import almanac_dir, assets_dir

# Known-good groups asserted by --check (from the handoff, hand-verified against the
# in-game story flow). If a re-parse of scenarios.json ever breaks one of these, the
# derivation (or the upstream table parse) has regressed.
KNOWN_GROUPS: dict[int, list[int]] = {
    1: [1, 2],  # Orbonne Prayer intro (no battle_conditionals — first member is root)
    3: [3, 4, 5, 6],  # Orbonne Battle: setup, battle, Gafgarion/Agrias chat, abduction
    9: [9, 10, 11, 12],  # Gariland Fight: setup, battle, chat, honest-lives chat
    15: [15, 16, 17, 18, 19, 20, 21, 22, 23],  # Mandalia Plains branch cutscenes
}


def _load_scenarios(path: Path) -> dict[int, dict]:
    doc = json.loads(path.read_text())
    scen = doc.get("scenarios", doc)
    return {int(k): v for k, v in scen.items()}


def derive_groups(scenarios: dict[int, dict]) -> list[dict]:
    """Return the ordered list of battle groups. Pure function of the table."""
    groups: list[dict] = []
    cur: dict | None = None
    for sid in sorted(scenarios):
        rec = scenarios[sid]
        key = (rec.get("map_id"), rec.get("entd_idx"))
        if cur is None or key != cur["_key"]:
            cur = {"_key": key, "_members": []}
            groups.append(cur)
        cur["_members"].append(sid)

    out: list[dict] = []
    for grp in groups:
        members = grp["_members"]
        map_id, entd_idx = grp["_key"]

        # Root = the member with a non-zero battle_conditionals_id; fall back to the
        # first member for the handful of groups that carry no BC (e.g. 1-2).
        bc_roots = [
            m for m in members if scenarios[m].get("battle_conditionals_id")
        ]
        root = bc_roots[0] if bc_roots else members[0]

        last = members[-1]
        successor_kind = scenarios[last].get("successor")
        successor_next = scenarios[last].get("next_scenario_id") or None

        out.append(
            {
                "group_root_id": root,
                "map_id": map_id,
                "map_name": scenarios[root].get("map_name"),
                "entd_idx": entd_idx,
                "battle_conditionals_id": scenarios[root].get(
                    "battle_conditionals_id", 0
                ),
                "members": [
                    {
                        "scenario_id": m,
                        "role": "setup" if m == root else "member",
                        "name": scenarios[m].get("scenario_name"),
                    }
                    for m in members
                ],
                "successor": successor_kind,
                "successor_scenario_id": successor_next,
            }
        )
    return out


def check(groups: list[dict]) -> int:
    by_root = {g["group_root_id"]: [m["scenario_id"] for m in g["members"]] for g in groups}
    # Build a root->members lookup that also handles bc-less groups keyed by first id.
    all_ok = True
    for expected_root, expected_members in KNOWN_GROUPS.items():
        got = by_root.get(expected_root)
        ok = got == expected_members
        all_ok = all_ok and ok
        flag = "OK " if ok else "FAIL"
        print(f"  [{flag}] root {expected_root}: expected {expected_members}, got {got}")
    print(f"groups total: {len(groups)}, multi-member: {sum(1 for g in groups if len(g['members']) > 1)}")
    return 0 if all_ok else 1


def print_table(groups: list[dict]) -> None:
    for g in groups:
        head = (
            f"[root {g['group_root_id']:>3}] MAP{g['map_id']:03d}/entd={g['entd_idx']} "
            f"bc={g['battle_conditionals_id']} exit={g['exit']}"
        )
        if g["successor_scenario_id"]:
            head += f"->{g['successor_scenario_id']}"
        print(head)
        for m in g["members"]:
            tag = "S" if m["role"] == "setup" else " "
            print(f"     {tag} {m['scenario_id']:>3}  {m['name']}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--print", action="store_true", dest="do_print", help="dump the group table to stdout")
    ap.add_argument("--check", action="store_true", help="verify known groups; no write")
    args = ap.parse_args()

    scen_dir = assets_dir("scenarios")
    scenarios = _load_scenarios(almanac_dir("encounters/scenarios.json"))
    groups = derive_groups(scenarios)

    if args.check:
        return check(groups)

    if args.do_print:
        print_table(groups)

    out_path = scen_dir / "scenario_groups.json"
    doc = {
        "_comment": (
            "Derived by tools/export_scenario_groups.py from scenarios.json "
            "(ISO-sourced ATTACK.OUT scenario table). A battle group is a maximal "
            "contiguous run of scenarios sharing (map_id, entd_idx); the setup/root "
            "is the member with battle_conditionals_id != 0. Regenerate; do not hand-edit."
        ),
        "group_count": len(groups),
        "groups": groups,
    }
    out_path.write_text(json.dumps(doc, indent=2))
    print(f"wrote {len(groups)} groups to {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
