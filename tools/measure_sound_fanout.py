#!/usr/bin/env python3
"""Measure the event -> SoundContainer -> FEDS pair fan-out across the effect corpus.

Every figure in the ADR-0085 "chain inspection" amendment (2026-08-21) comes from this
script. Re-run it rather than re-quoting the numbers -- several handoffs in a row have
carried a sound figure that did not survive checking.

The mode table below MIRRORS `addons/exmateria_sound/runtime/effect_sound_resolver.gd`
(itself a port of `lookup_sound_effect`, 0x801A32E8). It answers "which DISTINCT pairs
can this container ever emit", which is the resolver driven forward over a full cycle --
not a re-derivation of per-fire semantics. If the resolver's modes change, change this.

    python3 tools/measure_sound_fanout.py [--assets assets/effects]
"""

import argparse
import collections
import glob
import json
import os
import statistics

# mode -> the id slots it ever reads, in fire order (resolver 4.3; 5+ passes through).
MODE_SLOTS = {0: ("a",), 1: ("a", "b"), 2: ("a", "b"),
              3: ("a", "b", "c"), 4: ("a", "b", "c")}


def emitted_ids(container, timeline_sound_id):
    """The sound_ids a container can emit. Mode 5+ passes the timeline id through."""
    slots = MODE_SLOTS.get(int(container.get("mode", 0)))
    if slots is None:
        return [timeline_sound_id]
    return [int(container.get("id_%s" % s, 0)) for s in slots]


def firing_events(sound_doc):
    """{container_idx: count} for every real firing keyframe.

    A keyframe fires when sound_id >= 2 (0/1 are the skip sentinels) and its index is
    within max_keyframe -- the slots past that are padding the runtime never reaches.
    """
    out = collections.Counter()
    for channels in sound_doc.values():
        if not isinstance(channels, list):
            continue
        for ch in channels:
            last = int(ch.get("max_keyframe", -1))
            for i, kf in enumerate(ch.get("keyframes", [])):
                if i <= last and int(kf.get("sound_id", 0)) >= 2:
                    out[int(kf["sound_id"]) - 2] += 1
    return out


def main():
    ap = argparse.ArgumentParser()
    here = os.path.dirname(os.path.abspath(__file__))
    ap.add_argument("--assets", default=os.path.join(here, "..", "assets", "effects"))
    args = ap.parse_args()

    events_per_container = collections.Counter()
    pairs_per_container = collections.Counter()
    modes = collections.Counter()
    pair_containers = collections.defaultdict(set)
    multi_pair = collections.Counter()   # (distinct pairs, referencing events) -> count
    per_effect = []
    dangling = []
    totals = collections.Counter()

    for effect_dir in sorted(glob.glob(os.path.join(args.assets, "E*"))):
        name = os.path.basename(effect_dir)
        sound_path = os.path.join(effect_dir, "sound.json")
        if not os.path.exists(sound_path):
            continue
        events = firing_events(json.load(open(sound_path)))
        if not events:
            continue

        containers_path = os.path.join(effect_dir, "sound_containers.json")
        containers = (json.load(open(containers_path)).get("containers", [])
                      if os.path.exists(containers_path) else [])
        feds_path = os.path.join(effect_dir, "feds.json")
        bank_pairs = (json.load(open(feds_path)).get("pair_count", 0)
                      if os.path.exists(feds_path) else 0)

        totals["effects"] += 1
        totals["events"] += sum(events.values())
        every_chain_11 = True

        for cidx, n in events.items():
            events_per_container[n] += 1
            if not 0 <= cidx < len(containers):
                dangling.append((name, cidx, n))
                totals["dangling_events"] += n
                every_chain_11 = False
                continue
            container = containers[cidx]
            modes[int(container.get("mode", 0))] += 1
            pairs = {i - 1 for i in set(emitted_ids(container, cidx + 2)) if i >= 1}
            pairs_per_container[len(pairs)] += 1
            for p in pairs:
                pair_containers[(name, p)].add(cidx)
            if len(pairs) > 1:
                multi_pair[(len(pairs), n)] += 1
                totals["events_multi_pair"] += n
            if n > 1:
                totals["events_shared_container"] += n
            if n == 1 and len(pairs) == 1:
                totals["events_1to1to1"] += n
            else:
                every_chain_11 = False

        if every_chain_11:
            totals["effects_all_1to1to1"] += 1
        per_effect.append((sum(events.values()), len(events), bank_pairs))

    def pct(part, whole):
        return "%d/%d = %.1f%%" % (part, whole, 100.0 * part / whole) if whole else "n/a"

    ev, eff = totals["events"], totals["effects"]
    print("effects with >=1 firing event: %d" % eff)
    print("total firing events:          %d" % ev)
    print()
    print("-- events per referenced container (fan-in to the config level)")
    for n in sorted(events_per_container):
        print("   %d event(s): %d containers" % (n, events_per_container[n]))
    print("   exactly one: %s" % pct(events_per_container[1], sum(events_per_container.values())))
    print()
    print("-- distinct pairs a container can emit (fan-out to the FEDS level)")
    for n in sorted(pairs_per_container):
        print("   %d pair(s): %d containers" % (n, pairs_per_container[n]))
    print("   exactly one: %s" % pct(pairs_per_container[1], sum(pairs_per_container.values())))
    print()
    print("-- container modes actually referenced")
    for m in sorted(modes):
        print("   mode %d: %d" % (m, modes[m]))
    print()
    print("-- reverse links (the ADR-0092 concern)")
    rev = collections.Counter(len(v) for v in pair_containers.values())
    for n in sorted(rev):
        print("   %d container(s) reach one pair: %d pairs" % (n, rev[n]))
    print()
    print("-- the whole chain")
    print("   events on a fully 1:1:1 chain:      %s" % pct(totals["events_1to1to1"], ev))
    print("   effects where EVERY chain is 1:1:1: %s" % pct(totals["effects_all_1to1to1"], eff))
    print("   events whose container emits >1 pair:      %s" % pct(totals["events_multi_pair"], ev))
    print("   events sharing a container with another:   %s" % pct(totals["events_shared_container"], ev))
    print()
    print("-- multi-pair containers: (distinct pairs, referencing events) -> count")
    unreachable = 0
    for key in sorted(multi_pair):
        npairs, nevents = key
        print("   %d pairs, %d event(s): %d" % (npairs, nevents, multi_pair[key]))
        if nevents < npairs:
            unreachable += multi_pair[key]
    print("   with FEWER events than pairs: %s" % pct(unreachable, sum(multi_pair.values())))
    print("   (our runtime resets the per-container counter each cast, so those later")
    print("    fires never happen here -- see the ADR-0085 2026-08-21 amendment's")
    print("    'out of scope, but found' note before treating that as correct)")
    print()
    print("-- events naming a container that does not exist")
    print("   %s in %d effects: %s" % (pct(totals["dangling_events"], ev),
                                       len({d[0] for d in dangling}),
                                       ", ".join(sorted({d[0] for d in dangling}))))
    print()
    events_n = [p[0] for p in per_effect]
    containers_n = [p[1] for p in per_effect]
    bank_n = [p[2] for p in per_effect]
    print("-- per effect (median / max)")
    print("   events:                   %g / %d" % (statistics.median(events_n), max(events_n)))
    print("   distinct containers used: %g / %d" % (statistics.median(containers_n), max(containers_n)))
    print("   pairs in bank:            %g / %d" % (statistics.median(bank_n), max(bank_n)))


if __name__ == "__main__":
    main()
