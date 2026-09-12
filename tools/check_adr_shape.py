#!/usr/bin/env python3
"""An ADR states the NOW — so it carries at most ONE dated section.

An ADR exists so a reader can learn how things should be, why, and what was
rejected. Amend-in-place-dated is a good pattern with a CAP: at one update you
read a decision and one dated note and you have the now. At twenty-seven you
cannot. ADR-0085 is a 39-line decision under 2,947 lines of successive positions,
one of which reverses decision 3.

Nothing was enforcing the cap, so it was blown through silently. This is the
ratchet. A second dated section is a violation; the fix is to FOLD the standing
one into the decision body first (see `.claude/skills/adr-states-the-now`).

BURN_DOWN carries the ADRs that already violate. It may only SHRINK — an entry
that no longer violates is itself reported, so the list cannot rot into a
permanent exemption. Run from the package root.  Exit 0 = clean.
"""
import io
import pathlib
import re
import sys

ADR_DIR = pathlib.Path("docs/adr")

# The corpus spells a dated section three ways. `## Amendment 4`, `## Addendum`
# and the go-forward `## Update, 2026-08-05` all mean the same thing: a position
# recorded beside the decision instead of folded into it.
DATED = re.compile(r"^#{2,4}\s*(?:\w+\s+)?(?:Amendment|Addendum|Update)\b", re.I)

# Seeded 2026-08-28, after origin/main merged, at 30 ADRs / 16,212 lines. Ordered
# by count so the burn-down reads as the work queue it is; 0085 and 0089 are worked
# interactively (their forks are unbuilt-design calls a loop cannot make).
# Folded and removed so far: 0012, 0014, 0018, 0041, 0047, 0051, 0069, 0073, 0077, 0101, 0189, 0197, 0009, 0035, 0037, 0074, 0090, 0188, 0068, 0081, 0191, 0052, 0086, 0087.
# Held for the author, not takeable unattended. 0085/0089 fork on unbuilt design.
# 0092 and 0093 blocked on 2026-08-28 under the skill's "a question blocks the file"
# rule, both on the SAME product call: which surface owns the two time-scale enable
# bits (flags_byte bits 5/6), and whether ADR-0093's Amendment 1 still binds. 0088
# blocked the same day on its decision 7 item 2: the registration-audit allowlist has
# two carriers in the tree (a tracked, empty config/ui3_registration_allowlist.json and
# per-test consts), and which one the folded document states is a product call. Both
# readings are recorded in AUDIT.tsv and docs/adr/audit-notes/0088.md and 009{2,3}.md;
# no file was rewritten. An unattended pass takes the next target instead.
HELD_INTERACTIVE = {
    "0085-effect-sfx-authoring-is-three-projected-surfaces-not-one-flattened-ruler.md",
    "0088-ui3-elements-register-a-criteria-spec-shared-engines-implement-it.md",
    "0089-emitter-parameters-author-as-semantic-two-axis-groups-edited-at-the-reference.md",
    "0092-effect-flags-author-on-the-effect-settings-surface-sound-channels-stay-in-their-container-view.md",
    "0093-time-scale-pacing-curves-are-freehand-painted-not-keyframed.md",
}

# Arrived on the 2026-08-28 merge of origin/main, which authored them without this
# ratchet: 0192 carries two dated sections and 0194 five. They join the queue rather
# than being folded inside a merge — a fold is a rewrite, not a conflict resolution.
BURN_DOWN = {
    "0194-a-test-belongs-to-the-addon-it-can-run-without-the-game.md",
    "0192-the-register-goes-first-because-the-port-erases-its-own-baseline.md",
    "0092-effect-flags-author-on-the-effect-settings-surface-sound-channels-stay-in-their-container-view.md",
    "0093-time-scale-pacing-curves-are-freehand-painted-not-keyframed.md",
    "0088-ui3-elements-register-a-criteria-spec-shared-engines-implement-it.md",
    "0137-the-formation-screen-re-hosts-over-the-map-as-a-camera-child-scene-entered-through-a-paused-camera-takeover.md",
    "0089-emitter-parameters-author-as-semantic-two-axis-groups-edited-at-the-reference.md",
    "0085-effect-sfx-authoring-is-three-projected-surfaces-not-one-flattened-ruler.md",
}


def dated_sections(path):
    return [l.rstrip() for l in io.open(path, encoding="utf-8", errors="replace")
            if DATED.match(l)]


def main() -> int:
    if not ADR_DIR.is_dir():
        print(f"ERROR: ADR dir not found: {ADR_DIR} (run from the package root)",
              file=sys.stderr)
        return 2

    walked, violations, listed = 0, {}, set()
    for path in sorted(ADR_DIR.glob("[0-9][0-9][0-9][0-9]-*.md")):
        walked += 1
        found = dated_sections(path)
        if len(found) < 2:
            continue
        listed.add(path.name)
        if path.name in BURN_DOWN:
            continue
        violations[path.name] = found

    # The other arm: an entry that stopped violating, or a file the walk no longer
    # reaches. Without this the list becomes a permanent exemption nobody rechecks.
    for name in sorted(BURN_DOWN - listed):
        violations[name] = ["STALE BURN_DOWN entry — it no longer carries two dated "
                            "sections, or the walk no longer reaches it. Remove it "
                            "from BURN_DOWN."]

    if violations:
        print("check_adr_shape: FAILED\n", file=sys.stderr)
        for name in sorted(violations):
            print(f"  {name}", file=sys.stderr)
            for line in violations[name][:6]:
                print(f"      {line}", file=sys.stderr)
            if len(violations[name]) > 6:
                print(f"      … and {len(violations[name]) - 6} more", file=sys.stderr)
        print("\nAn ADR carries at most ONE dated section. Fold the standing one into "
              "the decision body\nbefore adding another — see "
              ".claude/skills/adr-states-the-now.", file=sys.stderr)
        return 1

    print(f"check_adr_shape: OK — {walked} ADRs walked, "
          f"{len(BURN_DOWN)} on the BURN_DOWN list.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
