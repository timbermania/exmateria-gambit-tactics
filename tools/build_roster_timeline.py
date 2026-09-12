#!/usr/bin/env python3
"""Derive the story ROSTER TIMELINE from ROM data: who joins the player's roster,
at which scenario group, in what story order.

This is the generator ADR-0201 dec.10 anticipated -- "the SAME shape a future ROM
generator will emit (from RE'd ENTD join-flags + event opcodes)". It replaces the
hand-authored Ch1MutationScript/GarilandMutationScript tables, which were guesses
and measurably wrong (they seeded 4 generics at Gariland; the ROM grants 6 one
group earlier, at the Military Academy).

SOURCES (all committed):
  assets/scenarios/entd.json            unit deployment tables; `flags1` bit 4 is
                                        `join_after_event` -- "recruits into the
                                        formation roster after this scenario"
                                        (research/key_documents/ENTD_FORMAT.md)
  addons/exmateria_catalogue/identity/unit_names.json
                                        special_name -> canonical name; a slot that
                                        resolves here is CANONICAL, else generic
  assets/scenarios/scenario_groups.json group root -> entd_idx + members
  assets/scenarios/transition_graph.json scenario -> scenario edges (chaining)
  assets/world_map/events.json          world-map `enter` scripts; a `var[110]==k`
                                        condition dates the group in story time

TWO TABLES come out of the ENTD, and they answer different questions:
  * `joins`       -- who RECRUITS here (`flags1` bit 4), i.e. who enters the player's
                     roster. Folded at the group's END.
  * `appearances` -- who this battle's ENTD SPAWNS at all, named units only, so their
                     slots bind to catalogue identities instead of falling back to
                     raw-ENTD construction (ADR-0201 dec.6/7). Folded at the group's
                     START, and only at a slug's FIRST battle -- re-binding a unit the
                     player has been levelling would clobber it.

COVERAGE, stated rather than implied:
  * Every recruit the ROM grants through `join_after_event` is derived, on EITHER team.
    An earlier version of this file kept Blue slots only, and that one line was the
    whole of what ADR-0216 called "event-opcode recruitment": Worker 8 carries the flag
    at ENTD 291 slot 3 ("Worker 8 Activated", Besrodio's House, position 94), Red, in a
    cinematic record where this generator already documents team_color as noise. Byblos
    was never missing at all -- he is the `create:entd402_10` delta at the Elidibs group.
    No event opcode is involved in either, and none of the 176 parsed opcodes is
    roster-shaped. What IS still missing is a NAME for special_name 115..127; see
    `_coverage.known_gap`.
  * Story order is derived for the groups reachable from a world-map `enter` emit or
    by chaining from one. The rest fall back to group-root-id order (monotone with
    the derived order everywhere both are known), with ORDER_OVERRIDES for the few
    that fallback demonstrably misplaces.
  * `appearances` are derived for BATTLE groups only. `team_color` is meaningless in a
    cinematic record -- Ramza reads Red in 17 of them -- and a cinematic group has no
    cast-composition seam to bind against. It also has no plan action that lands at its
    START: every one of the 72 battle groups carries an opener beat, and no linear
    group carries anything but its own end-keyed action.

Run:  uv run python tools/build_roster_timeline.py            # write
      uv run python tools/build_roster_timeline.py --check     # verify committed file
"""
import json
import sys
from collections import defaultdict, deque
from pathlib import Path

from _repo_paths import catalogue_dir

HERE = Path(__file__).resolve().parent
ASSETS = HERE.parent / "assets"
OUT = ASSETS / "scenarios" / "roster_timeline.json"

# ENTD flags1 bit 4 (MSB-first) -- "Recruits into the formation roster after this
# scenario." The single fact this whole generator turns on.
JOIN_AFTER_EVENT = 0x10
LOAD_FORMATION = 0x08       # "Pull stats from saved Formation Slot N" -- ALREADY a member
SAVE_FORMATION = 0x01       # "Persist back to Formation Slot N at scenario end"
FEMALE = 0x40
CONTROL = 0x08              # flags2 bit 3 -- player-controllable in THIS battle
MASK_ENTER = 0x008          # Campaign.MASK_ENTER -- the world-map hand-off emit
COND_VAR_EQ = 0x01          # Campaign.COND_VAR_EQ -- `var[a] == b`
STORY_COUNTER = 110         # var[110], the world-map story counter
# GameNavigator._battle_beats reads the opener off the BC edge whose predicate mentions
# var 509. It is the FIRST action a battle group contributes, so it is the only key whose
# deltas land before the fight -- which is what an APPEARANCE needs (a recruit lands at
# the group's end instead). All 72 battle groups have one.
BC_OPENER_MARKER = "509"

# Which occurrence of a repeat-joining unit is the PERMANENT recruit, as `slug -> root`.
#
# Not derivable. `join_after_event` fires at every appearance; `save_formation` is already
# set on the earliest one for all six units, so it cannot discriminate; and `load_formation`
# is refuted as a "roster form" marker by Ramza, who is definitionally a party member and
# never carries it on any of his 64 slots (Agrias inverts it too -- her loaded form is her
# Chapter 1 GUEST appearance). So these are authored, like ORDER_OVERRIDES.
#
# Absent here, a unit is recruited at its FIRST flagged appearance.
RECRUIT_AT: dict[str, int] = {
    # Guest from the Zaland rescue; permanent after the Goug events. The special_name
    # changes 34 -> 22 at exactly this group, which is consistent but not proof.
    "mustadio": 166,
    # Guest from Orbonne through Chapter 2 (special_name 52); joins as 30 at Bariaus Valley.
    "agrias": 175,
    # Rafa / Malak / Reis are NOT listed: their appearances carry no discriminating flag
    # and no special_name change that lines up with a join, so they fall through to first.
}

ORDER_OVERRIDES: dict[int, object] = {
    # "END" sorts near the top by id but is the terminal group.
    111: "last",
    # Zarghidas/Cloud. His enter script is gated on var[156]/[161]/[163]/[528] and
    # carries no story counter, so the derivation can only place him by chain depth
    # and lands him at Chapter 3. Cloud is a late Chapter 4 recruit -- after Bethla.
    218: 373,
}


def _load(rel: str):
    with (ASSETS / rel).open() as f:
        return json.load(f)


def _load_catalogue(rel: str):
    """A payload that travelled into `addons/exmateria_catalogue/` (#1025 pass 3).

    Kept as a SECOND loader rather than a base-path argument to `_load`: every
    other caller reads a host asset, and a default-argument base is the shape that
    silently keeps resolving after the next move.
    """
    with catalogue_dir(rel).open() as f:
        return json.load(f)


def _story_seeds(events):
    """Every world-map `enter` emit as an ordering seed: `{scenario_id: counter|None}`.

    Seeding from ALL enter emits, not only the 46 carrying a `var[110]` condition,
    is what reaches the chained Chapter 3-4 groups (Malak, Rafa, Orlandu, Meliadoul)
    and the three side-quest recruits (Cloud, Beowulf, Reis).
    """
    seeds: dict[int, object] = {}
    for node in events["by_node"]:
        for script in node.get("scripts", []):
            emit = script.get("emit", {})
            if not int(emit.get("mask", 0)) & MASK_ENTER:
                continue
            sid = int(emit["operands"][0])
            counter = None
            for cond in script.get("conditions", []):
                if cond.get("op") == COND_VAR_EQ and cond["operands"][0] == STORY_COUNTER:
                    counter = cond["operands"][1]
            if seeds.get(sid) is None:
                seeds[sid] = counter
    seeds.setdefault(1, 0)      # the pre-map prologue: Orbonne -> ... -> Gariland
    seeds.setdefault(2, 0)
    return seeds


def _derive_order(transition, events):
    """(root -> rank) for every group reachable from a seed, by walking the
    scenario transition graph outward from each world-map entry."""
    adjacency = defaultdict(list)
    for sid, node in transition["nodes"].items():
        for edge in node.get("edges", []):
            if isinstance(edge.get("target"), int):
                adjacency[int(sid)].append(edge["target"])

    seeds = _story_seeds(events)
    unranked = 10 ** 6          # sorts after every real story counter
    best: dict[int, tuple] = {}
    ordered_seeds = sorted(seeds.items(), key=lambda kv: (kv[1] if kv[1] is not None else unranked, kv[0]))
    for sid, counter in ordered_seeds:
        rank = counter if counter is not None else unranked
        queue = deque([(sid, 0)])
        while queue:
            cur, depth = queue.popleft()
            key = (rank, depth)
            if cur in best and best[cur] <= key:
                continue
            best[cur] = key
            for nxt in adjacency.get(cur, []):
                queue.append((nxt, depth + 1))

    by_root: dict[int, tuple] = {}
    for sid, key in best.items():
        node = transition["nodes"].get(str(sid))
        root = node.get("group_root") if node else None
        if root is None:
            continue
        if root not in by_root or key < by_root[root]:
            by_root[root] = key
    return by_root


def _total_order(groups, derived):
    """A total order over all 155 roots.

    Derived groups sort by (story counter, chain depth). A group the derivation
    cannot place is interpolated by group-root id -- it follows the last derived
    group whose id is lower, which keeps the two orderings consistent wherever both
    are defined. ORDER_OVERRIDES then moves the few this misplaces.
    """
    roots = sorted(g["group_root_id"] for g in groups)
    ranked = sorted(derived.items(), key=lambda kv: (kv[1], kv[0]))
    index_of = {root: i for i, (root, _) in enumerate(ranked)}

    def sort_key(root):
        if root in index_of:
            return (index_of[root], 0, root)
        prior = [index_of[r] for r in index_of if r < root]
        return (max(prior) if prior else -1, 1, root)

    order = sorted(roots, key=sort_key)

    for root, target in ORDER_OVERRIDES.items():
        if root not in order:
            continue
        order.remove(root)
        if target == "last":
            order.append(root)
        else:
            order.insert(order.index(int(target)) + 1, root)
    return order


# The protagonist's `special_name` forms. Ramza (1,2,3) and Delita (4,5,6) are the only
# units whose ids form a CONSECUTIVE run in unit_names.json -- that run is the three
# CHAPTER forms, not three different people. Every other repeat-named unit (Agrias 30/52,
# Mustadio 22/34, ...) has non-consecutive ids and is a role/state variant instead.
RAMZA_SPECIALS = (1, 2, 3)
RAMZA_SLUG = "ramza"


def _protagonist_seed(order, by_root, entd):
    """Ramza enters the roster at the FIRST group of the story, not by a join flag.

    He is never recruited -- he is the player. `join_after_event` fires for him exactly
    once, at root 116, whose scenario is literally named "Chapter 2 Start": that is the
    CHAPTER-FORM re-bind (special_name 1 -> 2), not a recruitment, and treating it as one
    left the protagonist absent from the roster for the whole of Chapter 1.

    The ROM states his requirement directly: 283 of the 305 scenarios that deploy a squad
    set `ramza_mandatory`. So he is seeded at story position 0, sourced from his first
    ENTD slot so the delta carries real data like every other one. Which chapter FORM is
    materialized is the deploy seam's job, not a durable byte at mint (ADR-0079).

    Returns `(root, delta)` or None.
    """
    for root in order:
        record = entd["records"].get(str(by_root[root]["entd_idx"]))
        if record is None:
            continue
        for index, slot in enumerate(record["slots"]):
            if int(slot.get("special_name", 0xFF)) in RAMZA_SPECIALS:
                # `female` reads False off his slot's flags anyway; the shared source is
                # used so a future flag change reaches the protagonist too.
                return root, {
                    "op": "join",
                    "slug": RAMZA_SLUG,
                    "canonical": True,
                    "display_name": "Ramza",
                    **_slot_source(by_root[root]["entd_idx"], index, slot),
                    "load_formation": bool(int(slot.get("flags1", 0)) & LOAD_FORMATION),
                    "save_formation": bool(int(slot.get("flags1", 0)) & SAVE_FORMATION),
                    "control": bool(int(slot.get("flags2", 0)) & CONTROL),
                    "protagonist": True,
                    "slot": slot,
                }
    return None


def _enter_scripts(events):
    """Every world-map `enter` script as `(node_index, scenario_id, conditions)`."""
    out = []
    for node_index, node in enumerate(events["by_node"]):
        for script in node.get("scripts", []):
            emit = script.get("emit", {})
            if int(emit.get("mask", 0)) & MASK_ENTER:
                out.append((node_index, int(emit["operands"][0]), script.get("conditions", [])))
    return out


def _live_nodes(store, scripts):
    """Which nodes offer an `enter` against `store` -- the port of Campaign._conditions_pass.
    A `party has job` condition (op 0x04) reads as FAILING there, so it does here."""
    live = []
    for node_index, sid, conditions in scripts:
        if all(c.get("op") == COND_VAR_EQ and store.get(c["operands"][0], 0) == c["operands"][1]
               for c in conditions):
            live.append(sid)
    return live


def _enter_for(group, scripts, sid_to_root):
    """The world-map state a Seek to this group must install: the variables its own
    `enter` script tests. Zeroing the store and writing these makes the map offer this
    node -- the fix for a Seek re-rooting the PLAN but not the WORLD STATE.

    `exclusive` records whether that yields exactly this node and no other; a Seek to a
    non-exclusive group is still allowed, but the walk cannot trust the map to be
    unambiguous there.
    """
    for node_index, sid, conditions in scripts:
        if sid_to_root.get(sid) != group["group_root_id"]:
            continue
        modelled = [c for c in conditions if c.get("op") == COND_VAR_EQ]
        store = {c["operands"][0]: c["operands"][1] for c in modelled}
        live = _live_nodes(store, scripts)
        return {
            "node_index": node_index,
            "scenario_id": sid,
            # var index (as a string key, so it survives JSON) -> value
            "vars": {str(k): v for k, v in sorted(store.items())},
            "story_counter": store.get(STORY_COUNTER),
            "exclusive": live == [sid],
            # A condition this port cannot model (`party has job`) reads as failing, so
            # the node can never go live on its own -- Goug's Worker-8 beats, Nelveska.
            "unmodelled_conditions": len(conditions) - len(modelled),
            "live_with_these_vars": live,
        }
    return None


def _slot_source(entd_idx, index, slot):
    """The ENTD provenance every delta carries: WHERE the row is and what it says about
    the unit. Shared by all three delta builders (the protagonist seed, the joins, the
    appearances) so a field cannot be spelled one way in one of them and another way in
    the next -- they are read by the same `Character.from_entd_slot` consumer.

    Each builder adds its own head (`op`/`slug`/`canonical`/`display_name`), its own
    flag readings, and the raw `slot`; only this middle run is common.
    """
    return {
        "special_name": int(slot.get("special_name", 0xFF)),
        "entd_idx": entd_idx,
        "slot_index": index,
        "female": bool(int(slot.get("flags1", 0)) & FEMALE),
        "job": int(slot.get("job", 0)),
        "level": int(slot.get("level", 0)),
    }


def _node_kind(root, transition) -> str:
    """The transition-graph node kind for a group root ("battle"/"quiet"/..)."""
    return str(transition["nodes"].get(str(root), {}).get("kind", ""))


def _opener_scenario_id(root, transition):
    """The scenario id of this battle group's OPENER beat, or None.

    Mirrors `GameNavigator._bc_target(node, "509")`. The consumer keys its appearance
    deltas on `opener:<id>`, so this is what lets StoryMutationScript build the table
    without loading the navigator's graph a second time.
    """
    for edge in transition["nodes"].get(str(root), {}).get("edges", []):
        if str(edge.get("via", "")) != "BC":
            continue
        if BC_OPENER_MARKER not in str(edge.get("why", "")):
            continue
        target = edge.get("target")
        if isinstance(target, int) and target > 0:
            return target
    return None


def _named_present_slots(group, entd, names):
    """Every slot of this group's ENTD record that is ALWAYS PRESENT and resolves to a
    canonical name, deduped by slug (first slot wins).

    `always_present` is the filter that separates the cast from the record's dormant
    rows: Orbonne's ENTD 387 carries a Red Delita and a lv1 Ramza/Delita pair that the
    battle never spawns, and binding those would be binding units that are not there.
    """
    record = entd["records"].get(str(group["entd_idx"]))
    if record is None:
        return []
    out = []
    seen = set()
    for index, slot in enumerate(record["slots"]):
        if not slot.get("flags2_decoded", {}).get("always_present", False):
            continue
        special = int(slot.get("special_name", 0xFF))
        name = names["names"].get(str(special))
        if name is None:
            continue
        slug = name.lower()
        if slug in seen:
            continue
        seen.add(slug)
        out.append((index, slug, name, special, slot))
    return out


def _appearances_for(group, entd, names):
    """This battle's named cast as CatalogueReplay deltas -- an APPEARANCE, not a
    recruitment (ADR-0078: catalogue membership is not owned membership).

    Always `op: "join"` and never `own`: a named unit the ENTD spawns exists, which is
    what makes its slot resolve to a Character (a SlugBinding HIT) rather than being
    rebuilt from the raw slot. Enemies included -- the catalogue is the one population.
    """
    out = []
    for index, slug, name, special, slot in _named_present_slots(group, entd, names):
        out.append({
            "op": "join",
            "slug": slug,
            "canonical": True,
            "display_name": name,
            **_slot_source(group["entd_idx"], index, slot),
            # The battle-local role this slot plays. NOT a claim about `own` -- Agrias is
            # Blue-and-not-yours at Orbonne and yours from Bariaus Valley on.
            "team_color_name": str(slot.get("team_color_name", "")),
            "control": bool(int(slot.get("flags2", 0)) & CONTROL),
            "slot": slot,
        })
    return out


def _joins_for(group, entd, names):
    """The `join_after_event` blue slots of this group's ENTD record, as
    CatalogueReplay deltas (op/slug/own + the raw `slot` the Character is built from)."""
    record = entd["records"].get(str(group["entd_idx"]))
    if record is None:
        return []
    out = []
    for index, slot in enumerate(record["slots"]):
        if not int(slot.get("flags1", 0)) & JOIN_AFTER_EVENT:
            continue
        # NOT filtered by `team_color`. An earlier version kept Blue slots only, and that
        # single line WAS the "event-opcode recruitment" gap: `join_after_event` is a
        # ROSTER fact and `team_color` is a battle-local one, and this generator already
        # says elsewhere that team_color is noise in a cinematic record (Ramza reads Red
        # in 17 of them, none a fight). Game-wide only ten flagged slots are Red, eight of
        # them in ENTD 366, which no scenario references; the two that reach a group are
        # both cinematics -- ENTD 291 slot 3 (Worker 8) and ENTD 434 slot 1 (Rafa, a
        # repeat). The raw team travels on the delta so a consumer can still see it.
        special = int(slot.get("special_name", 0xFF))
        name = names["names"].get(str(special))
        canonical = name is not None
        out.append({
            # A canonical unit is PROMOTED into the Catalog ("join"); a generic has no
            # prior identity and is MINTED ("create") -- the same split the authored
            # Ch1/Gariland scripts used by hand.
            "op": "join" if canonical else "create",
            # Canonical slug is UnitNames.slug_of (the lower-cased name). A generic is
            # keyed by where it LIVES -- stable under regeneration, collision-free, and
            # the same (record, slot) shape SlugBinding.bind() already uses.
            "slug": name.lower() if canonical else "entd%d_%d" % (group["entd_idx"], index),
            # NOT asserted as owned/deployable here. `join_after_event` is documented as
            # "recruits into the formation roster", but every one of these slots also has
            # `control` clear (AI-guest in this battle), and several units carry the flag
            # more than once with a CHANGING special_name (Mustadio 34 -> 22). Whether an
            # occurrence is a guest appearance or the permanent join is not decidable from
            # these flags alone -- see `_coverage.open_questions`. The raw flags travel on
            # the delta so the consumer can decide rather than inherit a guess.
            "canonical": canonical,
            "load_formation": bool(int(slot.get("flags1", 0)) & LOAD_FORMATION),
            "save_formation": bool(int(slot.get("flags1", 0)) & SAVE_FORMATION),
            "control": bool(int(slot.get("flags2", 0)) & CONTROL),
            # Battle-local, NOT a roster claim -- carried so a consumer can see that this
            # occurrence was flagged on the Red side rather than have to re-derive it.
            "team_color_name": str(slot.get("team_color_name", "")),
            "display_name": name or "",
            **_slot_source(group["entd_idx"], index, slot),
            "slot": slot,
        })
    return out


def _recruited_red_conflicts(order, out_groups, by_root, entd, names, transition):
    """Units already RECRUITED who stand on the Red team at a later battle.

    A contradiction the derivation cannot resolve on its own: the unit is in
    `roster_before`, so a Seek there arrives with it deployable, while the same battle's
    ENTD spawns it as an enemy. The true recruit point is the guest-versus-join call of
    RECRUIT_AT, which the flags cannot make -- NOT the Worker 8 gap, which was a
    team_color filter in `_joins_for` and is closed. So the honest move is to REGISTER the
    contradiction rather than author a guess around it.

    Deliberately unfiltered by `own`: this generator asserts no deployability (dec.8), so
    the register carries every recruited-and-Red row and the consumer -- which is the only
    thing that knows the never-owned set -- narrows it. Three rows here; exactly one
    survives that narrowing (Rafa), so the consumer's guard is a burn-down of 1.

    BATTLE groups only. `team_color` is noise in a cinematic record: Ramza alone reads
    Red in 17 of them, none of which is a fight.
    """
    out = []
    for root in order:
        if _node_kind(root, transition) != "battle":
            continue
        group = out_groups[str(root)]
        before = set(group["roster_before"])
        record = entd["records"].get(str(by_root[root]["entd_idx"]))
        if record is None:
            continue
        # Deliberately NOT `_named_present_slots`: that dedupes by slug and keeps the
        # first row, which drops the very thing this register is for. ENTD 433 spawns
        # Rafa TWICE and both are always-present -- Blue at slot 0, Red at slot 1 -- so
        # the dedup would keep the Blue one and report zero conflicts.
        for index, slot in enumerate(record["slots"]):
            if not slot.get("flags2_decoded", {}).get("always_present", False):
                continue
            if slot.get("team_color_name") != "Red":
                continue
            name = names["names"].get(str(int(slot.get("special_name", 0xFF))))
            if name is None or name.lower() not in before:
                continue
            out.append({
                "slug": name.lower(),
                "position": group["position"],
                "root": root,
                "entd_idx": by_root[root]["entd_idx"],
                "slot_index": index,
                "special_name": int(slot.get("special_name", 0xFF)),
            })
    return out


def build() -> dict:
    groups = _load("scenarios/scenario_groups.json")["groups"]
    entd = _load("scenarios/entd.json")
    names = _load_catalogue("identity/unit_names.json")   # ADR-0251 dec. 2, #1025 pass 3
    transition = _load("scenarios/transition_graph.json")
    events = _load("world_map/events.json")

    sid_to_root = {}
    for g in groups:
        for m in g.get("members", []):
            sid_to_root[m["scenario_id"]] = g["group_root_id"]
        sid_to_root[g["group_root_id"]] = g["group_root_id"]
    scripts = _enter_scripts(events)

    derived = _derive_order(transition, events)
    order = _total_order(groups, derived)
    by_root = {g["group_root_id"]: g for g in groups}

    seed = _protagonist_seed(order, by_root, entd)
    seed_root = seed[0] if seed else None

    out_groups = {}
    cumulative: list[str] = []
    # Every slug the CATALOGUE already holds at this point in the story -- recruits plus
    # units already bound by an earlier battle's appearance. Wider than `cumulative`,
    # which is the ROSTER (ADR-0078: catalogue membership is not owned membership), and
    # the reason an appearance fires only at a slug's FIRST battle: a second bind would
    # re-register over a Character the player has been levelling.
    catalogued: set[str] = set()
    appearance_slots_scanned = 0
    for position, root in enumerate(order):
        group = by_root[root]
        kind = _node_kind(root, transition)
        opener = _opener_scenario_id(root, transition) if kind == "battle" else None
        appearances = []
        if kind == "battle":
            for delta in _appearances_for(group, entd, names):
                appearance_slots_scanned += 1
                if delta["slug"] in catalogued:
                    continue
                catalogued.add(delta["slug"])
                appearances.append(delta)
        joins = _joins_for(group, entd, names)
        # The protagonist is seeded at the story's first group, ahead of its own joins.
        if seed and root == seed_root:
            joins = [seed[1]] + joins
        # SNAPSHOT before folding, never "cumulative minus this group's joins": a unit
        # can be granted by more than one group (Mustadio joins at three), and
        # subtracting would retroactively remove one an EARLIER group already granted.
        roster_before = list(cumulative)
        for delta in joins:
            # A unit can carry the flag at several groups. Exactly one occurrence is the
            # permanent recruit -- RECRUIT_AT names it where the ROM cannot; otherwise the
            # first flagged appearance wins. Every other occurrence is a guest appearance
            # and is marked `repeat` rather than collapsed away.
            slug = delta["slug"]
            recruits_here = (root == RECRUIT_AT[slug]) if slug in RECRUIT_AT else (slug not in cumulative)
            delta["recruit"] = recruits_here
            delta["repeat"] = not recruits_here
            if recruits_here and slug not in cumulative:
                cumulative.append(slug)
            if recruits_here:
                catalogued.add(slug)
        out_groups[str(root)] = {
            "position": position,
            "order_source": "derived" if root in derived else "root_id_fallback",
            "node_kind": kind,
            "map_name": group.get("map_name", ""),
            "entd_idx": group["entd_idx"],
            # The scenario id of this group's OPENER beat -- the one plan action whose
            # deltas land BEFORE the fight. null for a linear group (it has no such key).
            "opener_scenario_id": opener,
            # The world-map state a Seek here must install (null when this group is never
            # entered from the map -- it is only ever reached by chaining).
            "enter": _enter_for(group, scripts, sid_to_root),
            "joins": joins,
            # The named units this battle SPAWNS, bound at the opener so their slots
            # resolve to catalogue Characters. First bind only -- see `catalogued`.
            "appearances": appearances,
            # The roster a Seek to this group should arrive with: everything granted
            # by the groups BEFORE it. This group's own joins land at its end.
            "roster_before": roster_before,
        }

    joiners = [r for r in order if out_groups[str(r)]["joins"]]
    appearing = [r for r in order if out_groups[str(r)]["appearances"]]
    conflicts = _recruited_red_conflicts(order, out_groups, by_root, entd, names, transition)
    # The flagged-but-Red slots this generator deliberately KEEPS (see `_joins_for`).
    red_joins = [
        {
            "slug": d["slug"],
            "display_name": d["display_name"],
            "position": out_groups[str(r)]["position"],
            "root": r,
            "node_kind": out_groups[str(r)]["node_kind"],
            "entd_idx": d["entd_idx"],
            "slot_index": d["slot_index"],
            "recruit": d["recruit"],
        }
        for r in order
        for d in out_groups[str(r)]["joins"]
        if d.get("team_color_name") == "Red"
    ]
    return {
        "_comment": (
            "Derived by tools/build_roster_timeline.py from ENTD join-flags + the world-map "
            "story counter. Regenerate; do not hand-edit. ADR-0201 dec.10. Every recruit "
            "the ROM grants through `join_after_event` is here, including the ones on Red "
            "slots -- Worker 8 at ENTD 291 (position 94). What is NOT here is a NAME for "
            "special_name 115..127; see `_coverage.known_gap`."
        ),
        "_coverage": {
            "groups": len(order),
            "groups_ordered_by_derivation": len(derived),
            "groups_ordered_by_root_id_fallback": len(order) - len(derived),
            "groups_granting_joins": len(joiners),
            "join_deltas": sum(len(out_groups[str(r)]["joins"]) for r in joiners),
            "canonical_recruits": sorted({
                d["display_name"]
                for r in joiners for d in out_groups[str(r)]["joins"] if d["canonical"]
            }),
            # Was "event-opcode recruitment (Worker 8) is not derived". REFUTED: Worker 8
            # carries `join_after_event` at ENTD 291 slot 3 ("Worker 8 Activated",
            # Besrodio's House, position 94) and was dropped by a team_color filter, not
            # by any missing opcode. Byblos was never missing either -- he is the
            # `create:entd402_10` delta at the Elidibs group. What remains is an IDENTITY
            # gap, not a recruitment one.
            "known_gap": (
                "special_name above 72 cannot be NAMED: tools/data/UnitNames.xml stops at "
                "0x48, so unit_names.json covers 0..72 only. FIVE flagged slots use that "
                "range -- 117 (Steel Giant, the Worker 8 recruit), 118 (Chocobo, Araguay "
                "Woods) and 120/121/127 (two Knights and a Squire at Chapter 2 Start) -- "
                "and mint as generic `entd<record>_<slot>` instead of by name. 115, the "
                "Nelveska Steel Giant, is in the same range but carries no join flag."
            ),
            # The flagged slots that read Red. Two reach a group; the other eight are all
            # ENTD 366, which no scenario references. Emitted so the team_color decision
            # in `_joins_for` is auditable from the artifact rather than only from source.
            "red_join_slots": red_joins,
            # Every variable any `enter` script tests. A Seek resets EXACTLY these before
            # installing the target's, so the map's gating state is deterministic without
            # wiping the rest of the store -- note 528 sits inside WorldMapProgress's
            # NODE_KNOWN_BASE range, so a blanket zero would un-reveal unrelated map nodes.
            "enter_gating_vars": sorted({
                c["operands"][0]
                for _, _, conditions in scripts for c in conditions
                if c.get("op") == COND_VAR_EQ
            }),
            "groups_enterable_from_world_map": sum(
                1 for r in order if out_groups[str(r)]["enter"] is not None),
            "groups_with_exclusive_enter": sum(
                1 for r in order
                if (out_groups[str(r)]["enter"] or {}).get("exclusive")),
            "repeat_join_units": sorted({
                d["display_name"] for r in joiners
                for d in out_groups[str(r)]["joins"] if d["canonical"] and d["repeat"]
            }),
            # --- the APPEARANCE half: who each battle's ENTD spawns (ADR-0201 dec.6/7) ---
            "battle_groups": sum(1 for r in order if _node_kind(r, transition) == "battle"),
            "groups_with_appearances": len(appearing),
            "appearance_binds": sum(len(out_groups[str(r)]["appearances"]) for r in appearing),
            # Every named+present slot a battle ENTD carries. The difference against
            # `appearance_binds` is the re-binds SUPPRESSED because the slug was already
            # catalogued -- re-registering would clobber a levelled Character.
            "appearance_slots_scanned": appearance_slots_scanned,
            "appearance_units": sorted({
                d["display_name"] for r in appearing for d in out_groups[str(r)]["appearances"]
            }),
            # Recruited-and-Red at the same battle -- see `_recruited_red_conflicts`.
            # The consumer narrows this by its never-owned set; exactly one row survives.
            "recruited_red_conflicts": conflicts,
            "open_questions": [
                "join_after_event fires more than once for Agrias, Mustadio, Rafa, Malak, "
                "Beowulf and Reis, sometimes with a different special_name (Mustadio 34 -> 22). "
                "`repeat_join_units` lists SEVEN, not six: Ramza carries the flag at one group "
                "only, but he is seeded at position 0, so that single occurrence reads as a "
                "repeat. The field counts repeat DELTAS; this sentence counts units that carry "
                "the flag twice. "
                "GUEST-then-join is not decidable from the ENTD flags alone -- save_formation "
                "is already set on the earliest occurrence for all six, and load_formation is "
                "refuted as a roster marker by Ramza, who never carries it. RECRUIT_AT authors "
                "the ones that are known; the rest recruit at their first flagged appearance.",
                "Every join slot has flags2 `control` clear, so none of them says the unit is "
                "player-controlled at that battle. Deployability (`own`) is therefore NOT "
                "asserted here and must be decided by the consumer.",
                "No LEAVE is derived. A guest who departs the party stays in `roster_before`.",
                "Three units are RECRUITED and then stand on the Red team at a later "
                "battle -- see `recruited_red_conflicts`. Algus and Gafgarion are canon "
                "(they turn on you) and are never owned, so only Rafa is a real "
                "contradiction: derived as a recruit at story position 72, then an enemy "
                "in Malak's battles at 107/108. It is NOT the Worker 8 gap -- that one was "
                "a team_color filter and is closed. Rafa carries `join_after_event` again "
                "at position 108 (ENTD 434, now visible), but her FIRST flagged occurrence "
                "is still 72, so `roster_before` at 107 is unchanged and the contradiction "
                "stands. Closing it means authoring RECRUIT_AT['rafa'], which needs a "
                "guest-vs-join discriminator this generator does not have: 'recruit at the "
                "first group carrying the SECOND special_name' reproduces both authored "
                "entries (Mustadio 34->22 at root 166, Agrias 52->30 at root 175) and would "
                "give Rafa root 295, but it is refuted by Reis, whom it would move from her "
                "dragon-form join at Golland to her human form at Nelveska -- a FORM change, "
                "not a recruit. Declared, not guessed around.",
            ],
        },
        "order": order,
        "groups": out_groups,
    }


def main() -> int:
    data = build()
    text = json.dumps(data, indent=2, sort_keys=False) + "\n"
    if "--check" in sys.argv:
        if not OUT.exists():
            print("[FAIL] %s missing -- run tools/build_roster_timeline.py" % OUT)
            return 1
        if OUT.read_text() != text:
            print("[FAIL] %s is stale -- regenerate" % OUT)
            return 1
        print("[OK] %s matches its sources" % OUT.name)
        return 0
    OUT.write_text(text)
    cov = data["_coverage"]
    print("[OK] wrote %s" % OUT)
    print("  %d groups (%d derived order, %d root-id fallback)" % (
        cov["groups"], cov["groups_ordered_by_derivation"],
        cov["groups_ordered_by_root_id_fallback"]))
    print("  %d groups grant %d joins; %d canonical recruits" % (
        cov["groups_granting_joins"], cov["join_deltas"], len(cov["canonical_recruits"])))
    print("  recruits: %s" % ", ".join(cov["canonical_recruits"]))
    print("  %d of %d battle groups bind %d appearances (%d named slots scanned)" % (
        cov["groups_with_appearances"], cov["battle_groups"],
        cov["appearance_binds"], cov["appearance_slots_scanned"]))
    print("  recruited-and-Red conflicts: %d (%s)" % (
        len(cov["recruited_red_conflicts"]),
        ", ".join(sorted({c["slug"] for c in cov["recruited_red_conflicts"]})) or "none"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
