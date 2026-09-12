#!/usr/bin/env python3
"""Build the FFT game-state transition graph from already-parsed data.

This is pure offline analysis — NO ROM capture needed. It folds three parsed
artifacts into one directed story graph:

  * scenarios.json          — the ATTACK.OUT record per scenario_id. Carries the
                              deterministic exit: successor_raw
                              (0x81 GoToNextScenario / 0x80 GoToWorldMap /
                              0x82 ResetGame) + next_scenario_id.
  * battle_conditionals.json — per battle_conditionals_id, the guarded
                              `Run Scenario N` edges (predicates + target).
  * scenario_groups.json    — the root/member grouping (a battle group = its
                              setup node + the cinematic beats woven into it).

Each scenario becomes a NODE with a derived `kind`, and outgoing EDGES tagged
`ATTACK` (deterministic) or `BC` (guarded by battle-state predicates). The
world map / reset are terminal sink nodes.

The point: the set of game "states" is not hand-authored — it falls out of the
edges. Every id an edge points at, plus the sinks, is a state. This artifact is
the static spec the in-game state navigator loads to drive
scenario -> battle -> scenario -> world map end-to-end.

Regenerate: `python3 tools/build_transition_graph.py`
Output:     assets/scenarios/transition_graph.json (+ a printed inventory)

See research/working_documents/GAME_STATE_TRANSITIONS.md for the write-up and
the RE/Godot status of each edge kind.
"""
from __future__ import annotations

import argparse
import collections
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.join(HERE, "..")
# ADR-0251 dec. 2 — `scenarios.json` and `battle_conditionals.json` moved into
# the almanac addon with the databases that read them. `scenario_groups.json`
# did NOT move: `src/scenarios/ScenarioGroupDatabase.gd` still reads it from
# `assets/scenarios/`, and so does `build_roster_timeline.py`. Neither did our
# own output — `src/scenarios/GameNavigator.gd` loads
# `res://assets/scenarios/transition_graph.json`. So this tool straddles two
# directories; reading everything from the almanac made it crash on import.
ALMANAC_DIR = os.path.normpath(os.path.join(
    PKG, "addons", "exmateria_almanac", "encounters"))
SCN_DIR = os.path.normpath(os.path.join(PKG, "assets", "scenarios"))

# Which directory owns each input, so a future move is one edit here.
_HOME = {
    "scenarios.json": ALMANAC_DIR,
    "battle_conditionals.json": ALMANAC_DIR,
    "scenario_groups.json": SCN_DIR,
}

# Sink node ids that are not scenarios (targets of 0x80 / 0x82).
WORLD_MAP = "WORLD_MAP"
RESET = "RESET"


def _load(name: str):
    with open(os.path.join(_HOME[name], name)) as fh:
        return json.load(fh)


def _guard_summary(requirements: list) -> str:
    """One-line human summary of a BC condition's predicate guards."""
    if not requirements:
        return "(unconditional)"
    parts = []
    for p in requirements:
        vals = ",".join(str(x.get("value")) for x in p.get("params", []))
        parts.append(f"{p.get('name')}({vals})")
    return "; ".join(parts)


def _bc_edges(bc_sets: dict, bcid: int) -> list:
    """Resolved `Run Scenario` edges for a battle_conditionals_id."""
    s = bc_sets.get(str(bcid))
    if not s:
        return []
    edges = []
    for cond in s.get("conditions", []):
        tgt = cond.get("run_scenario")
        if tgt is None:
            continue
        edges.append(
            {
                "target": tgt,
                "guard": _guard_summary(cond.get("requirements", [])),
            }
        )
    return edges


# The Var509 opener latch every BC-owning group uses to launch its first member.
# A BC set with ONLY this predicate is a latch cinematic (auto-chain, no combat);
# any predicate BEYOND it (Victory / HP / Active Turn / Unit Present / ...) marks a
# real winnable or scripted battle. See GAME_STATE_TRANSITIONS.md §2.5.
_LAUNCH_LATCH_PREDICATE = "Variable ="


def _bc_has_combat(bc_sets: dict, bcid: int) -> bool:
    """True iff the BC set contains a predicate beyond the launch latch — i.e. an
    actual battle, not a latch-only cinematic. (owns-BC != is-a-battle.)"""
    s = bc_sets.get(str(bcid))
    if not s:
        return False
    names = set()
    for cond in s.get("conditions", []):
        for p in cond.get("requirements", []):
            names.add(p.get("name"))
    return bool(names - {_LAUNCH_LATCH_PREDICATE})


def _kind(rec: dict, bc_sets: dict) -> str:
    """Derived node kind from the record's transition fields + its BC content."""
    if rec["battle_conditionals_id"]:
        # BC-owner: a real battle only if the set has a combat predicate; otherwise
        # it is a latch cinematic (BC is only the Var509 opener that chains the scene).
        return "battle" if _bc_has_combat(bc_sets, rec["battle_conditionals_id"]) else "cinematic_latch"
    ps = rec["successor"]
    if ps == "next-scenario":
        return "cinematic_linear"
    if ps == "world-map":
        return "exit_worldmap"
    if ps == "reset":
        return "reset"
    return "quiet"  # 0x00, no BC: interlude/setup beat, advanced by BC-target/event-end


def build_graph() -> dict:
    scn = _load("scenarios.json")["scenarios"]
    bc_sets = _load("battle_conditionals.json")["sets"]
    groups = _load("scenario_groups.json")["groups"]

    by_id = {int(k): v for k, v in scn.items()}

    # scenario_id -> its group root (for quick "which battle owns this beat")
    root_of = {}
    for grp in groups:
        for m in grp["members"]:
            root_of[m["scenario_id"]] = grp["group_root_id"]

    nodes = {}
    for sid, rec in sorted(by_id.items()):
        edges = []
        ps = rec["successor"]
        if ps == "next-scenario":
            edges.append({"via": "successor", "target": rec["next_scenario_id"], "why": "successor=0x81 next-scenario"})
        elif ps == "world-map":
            edges.append({"via": "successor", "target": WORLD_MAP, "why": "successor=0x80 world-map"})
        elif ps == "reset":
            edges.append({"via": "successor", "target": RESET, "why": "successor=0x82 reset"})
        if rec["battle_conditionals_id"]:
            for e in _bc_edges(bc_sets, rec["battle_conditionals_id"]):
                edges.append({"via": "BC", "target": e["target"], "why": e["guard"]})

        nodes[sid] = {
            "scenario_id": sid,
            "name": rec["scenario_name"],
            "kind": _kind(rec, bc_sets),
            "map_id": rec["map_id"],
            "map_name": rec["map_name"],
            "entd_idx": rec["entd_idx"],
            "battle_conditionals_id": rec["battle_conditionals_id"],
            "group_root": root_of.get(sid),
            "edges": edges,
        }

    return {
        "_comment": (
            "Derived by tools/build_transition_graph.py from scenarios.json + "
            "battle_conditionals.json + scenario_groups.json. Nodes = scenarios; "
            "edges tagged ATTACK (deterministic successor_raw) or BC (guarded "
            "Run Scenario). WORLD_MAP / RESET are terminal sinks. Regenerate; do "
            "not hand-edit. See research/working_documents/GAME_STATE_TRANSITIONS.md."
        ),
        "sinks": [WORLD_MAP, RESET],
        "node_count": len(nodes),
        "nodes": {str(k): v for k, v in nodes.items()},
    }


def print_inventory(graph: dict) -> None:
    nodes = {int(k): v for k, v in graph["nodes"].items()}
    kinds = collections.Counter(n["kind"] for n in nodes.values())
    print(f"nodes: {len(nodes)}")
    print("kind distribution:")
    for k, v in kinds.most_common():
        print(f"  {v:4d}  {k}")

    # edge-kind tally + unresolved sinks
    edge_kinds = collections.Counter()
    worldmap_exits = 0
    for n in nodes.values():
        for e in n["edges"]:
            edge_kinds[e["via"]] += 1
            if e["target"] == WORLD_MAP:
                worldmap_exits += 1
    print("edges:")
    for k, v in edge_kinds.most_common():
        print(f"  {v:4d}  {k}")
    print(f"world-map exits (0x80 sink, RE OPEN): {worldmap_exits}")


def trace(graph: dict, start: int, limit: int = 20) -> None:
    """Follow ATTACK edges (and list BC branches) from a start scenario."""
    nodes = {int(k): v for k, v in graph["nodes"].items()}
    print(f"\n=== trace from scenario {start} ===")
    sid = start
    seen = set()
    for _ in range(limit):
        n = nodes.get(sid)
        if not n or sid in seen:
            break
        seen.add(sid)
        print(f"scn {sid:>3} [{n['kind']:>16}] root={n['group_root']} {n['name'][:40]}")
        nxt = None
        for e in n["edges"]:
            print(f"        --{e['via']:>6}--> {e['target']}   ({e['why'][:56]})")
            if e["via"] == "ATTACK" and isinstance(e["target"], int):
                nxt = e["target"]
        if nxt is None:
            break
        sid = nxt


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--trace", type=int, metavar="SCN", help="trace ATTACK spine from a scenario id")
    ap.add_argument("--no-write", action="store_true", help="print inventory only, do not write the artifact")
    args = ap.parse_args()

    graph = build_graph()
    print_inventory(graph)
    if args.trace is not None:
        trace(graph, args.trace)

    if not args.no_write:
        out = os.path.join(SCN_DIR, "transition_graph.json")
        with open(out, "w") as fh:
            json.dump(graph, fh, indent=1)
        print(f"\nwrote {os.path.relpath(out, PKG)}")


if __name__ == "__main__":
    main()
