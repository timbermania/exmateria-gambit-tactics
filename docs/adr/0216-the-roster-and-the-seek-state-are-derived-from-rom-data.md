# The story roster and a Seek's world state are DERIVED from ROM data, not hand-authored

**Status:** accepted — built. `tools/build_roster_timeline.py` +
`assets/scenarios/roster_timeline.json` + `RosterTimeline` +
`NavigatorMain._install_world_state` + `StoryMutationScript`, guarded by
`RosterTimelineTest` and `StoryMutationScriptTest` (headful) and
`tools/test_build_roster_timeline.py` (49 cases). All three run in the suite's
pre-flight, and `build_roster_timeline.py --check` gates the committed artifact
against its sources there too — a guard this ADR named before anything invoked it. Ask C (the Seek runaway) and Ask D
(the roster fold) are both closed: the navigator builds its `MutationScript` from the
derived timeline, `Ch1MutationScript` is deleted, `GarilandMutationScript` is a
forwarder, and `_prologue_before` is gone. The APPEARANCE table is derived too (dec.12) —
no hand-typed roster or cast data survives anywhere in the navigator.

**Builds on [ADR-0201](0201-battle-cast-is-a-replay-derived-view-of-the-catalog.md):**
that ADR made the catalogue a fold of a beat-keyed `MutationScript` and deferred
"ROM-generated mutation data" as an edge. Its dec.10 named the generator exactly —
"the SAME shape a future ROM generator will emit (from RE'd ENTD join-flags + event
opcodes)". This ADR builds the ENTD half of that generator and, in doing so, discovers
that the seek defect it was meant to serve had a **second, unrelated half**.

## Context

A navigator Seek was reported as "sends the run back to Orbonne Monastery and speeds
through the entire game". Two independent defects sat behind that one symptom.

**The world state was never re-rooted.** `var[110]`, the world-map story counter, is
written only by the scenarios' own `Zero(110); Add(110,k)` as they play. A Seek
re-roots the *plan* and nothing else, so the walk arrived at story counter 1 wherever
it was aimed. Its first `world_map` action asked Campaign what was live, got node 6 →
scenario 13 → Beoulve Residence, and with auto-advance on chained forward hop by hop.

**The cast had no data behind it.** `_prologue_before` replans from the story root to
recover history, which reaches nothing for 151 of 155 group roots. But repairing that
chain was never going to help: the entire authored mutation table is **four keys**
(`scenario:1`, `opener:4`, `scenario:7`, `opener:10`) and stops at group 9. A
perfectly re-rooted prologue folds nothing past Gariland because nothing is authored
past Gariland. Two of the four keys were also measurably **wrong** — they seed four
generics at Gariland, whose ENTD record grants nobody, while the ROM grants six at
root 7 (Military Academy).

A "capture a checkpoint from live state" design was considered first and rejected:
capture can only ever record what the game can already produce, and the game cannot
produce a Chapter 3 party, so it would have shipped a button that stays unpressed for
154 of 155 roots.

## Decisions

1. **Both halves are derived from committed ROM data, not captured and not authored.**
   The roster comes from ENTD `flags1` bit 4 (`join_after_event`) resolved through
   `unit_names.json`; the seek state comes from each group's own world-map `enter`
   script conditions. Neither requires anyone to play the game.

2. **The derivation is a build-time artifact, not a runtime computation.** `entd.json`
   is 15 MB and would otherwise be parsed on every navigator boot. More importantly the
   story ORDER is approximate (dec.5), so the derived result must be reviewable as a
   diff rather than discovered in a seek.

3. **One artifact answers both questions.** `roster_timeline.json` gives each group its
   `enter` state and its `roster_before`. These are one concept — *what must be true
   when you arrive at group R* — which is the "checkpoint" the original design wanted,
   materialized by derivation instead of capture.

4. **A Seek resets exactly the 20 gating variables, never the whole store.** Var 528
   sits inside `WorldMapProgress.NODE_KNOWN_BASE`, so a blanket zero would un-reveal
   unrelated map nodes.

5. **Story order is derived where it can be and falls back to group-root id where it
   cannot, with an authored override table.** Seeding from all 55 world-map `enter`
   emits — not only the 46 carrying a `var[110]` condition — and walking
   `transition_graph.json` outward orders 87 of 155 groups. Root-id order is monotone
   with the derived order everywhere both are defined, so it is a sound tiebreak rather
   than a guess; `ORDER_OVERRIDES` carries the two it misplaces.

6. **Guest-versus-permanent-join is authored, because it is not derivable.** Six units
   carry `join_after_event` more than once. `save_formation` is already set on the
   earliest occurrence for all six, so it discriminates nothing, and `load_formation`
   is refuted as a roster marker by Ramza — definitionally a party member, and he
   carries it on none of his 64 slots. `RECRUIT_AT` names the known cases
   (`mustadio → 166`, `agrias → 175`); everything else recruits at first appearance.

   One more discriminator was tried and **refuted**: "recruit at the first group carrying
   the unit's SECOND `special_name`". It reproduces both authored entries exactly
   (Mustadio 34 -> 22 at root 166, Agrias 52 -> 30 at root 175) and would hand Rafa root
   295, the group immediately after her contradiction -- which is precisely why it is
   tempting. Reis kills it: she goes 72 -> 15, so the rule would move her from her
   dragon-form join at Golland to her human form at Nelveska. That is dec.12's FORM
   re-bind, not a recruitment, and the rule cannot tell the two apart. Authored stands.

7. **A Seek is never refused.** A group with no world-map entry, or whose variables do
   not isolate it, warns and proceeds. Ruled by the user: "just go with whatever the
   current cast is."

8. **Deployability is not asserted by the generator, and `control` is why.** Every one
   of the 36 join slots has `flags2 control` clear — and the flag is no richer anywhere
   else: across the 72 battle groups exactly ONE always-present slot sets it, Orbonne's
   baked-in Ramza, the game's sole predetermined cast. That is not a hole in the data,
   it is the shape of the game. In every other battle the player's units come from the
   ROSTER and are not in the ENTD at all, so a Blue ENTD slot is a guest *at that battle*
   by construction, and `control` has nothing left to mark. What it can never say is
   whether a unit is EVER owned: Agrias is a Blue-and-not-yours slot at Orbonne and a
   party member from Bariaus Valley on. So the generator emits the raw flags and dec.11
   puts the call on the consumer.

   Two neighbouring colour facts, measured on the same pass and load-bearing for dec.12.
   **The ENTD has no green:** all 8,192 slots are Blue(0) or Red(1), though
   `tools/parse_entd.py` models four (`0x30 >> 4`) — the guest colour is applied at
   runtime, not stored. And **`team_color` is meaningless in a CINEMATIC record**: Ramza,
   definitionally the player, reads Red in 17 of them. Any derivation that reads a team
   is therefore scoped to battle groups.

9. **The protagonist is seeded at the story's first group, not recruited.** Ramza's only
   `join_after_event` is at root 116, whose scenario is named *"Chapter 2 Start"* — that
   is the chapter-FORM re-bind (`special_name` 1 → 2), not a recruitment, and reading it
   as one left him out of the roster for the whole of Chapter 1. The ROM states his
   requirement directly: **283 of the 305 scenarios that deploy a squad set
   `ramza_mandatory`**. So he is seeded at position 0, sourced from his first ENTD slot
   so the delta carries real data like every other one. Which chapter form is
   materialized stays the deploy seam's job (ADR-0079), not a durable byte at mint.

   The rule that separates a chapter form from a role variant is **consecutive
   `special_name` ids**: Ramza (1,2,3) and Delita (4,5,6) are the only units whose ids
   form a run. Agrias 30/52, Mustadio 22/34, Rafa 25/41 and the rest are non-consecutive
   and are role/state variants — which is why dec.6 treats them separately.

10. **A group's joins attach to its own root-keyed action, which puts them at its END.**
    You do not have Orlandu when you *arrive* at Bethla, and `roster_before` already
    encodes that. `NavigatorRunner` applies an action's deltas as it LEAVES the action, so
    keying a group's recruits on that action lands them at the group's end by
    construction — no beat-scenario-id lookup, and no second ordering to keep in step. A
    group is linear (one `scenario:<root>` action) or a battle (`combat:<root>` is its
    last root-keyed action) and never both, so `StoryMutationScript` carries the same
    deltas under both keys and exactly one is ever looked up. That keeps the builder free
    of `GameNavigator`'s kind table.

11. **The consumer decides `own`, and the split it decides is ADR-0078's.**
    [ADR-0078](0078-owned-is-a-catalogue-overlay-and-class-is-derived-per-battle.md)
    already rules this and names the canonical case: *"Catalogue membership ≠ owned
    membership: Delita is catalogue-yes / owned-no."* This ADR does not re-derive it. It
    only says who fills the overlay now that the roster is derived: dec.8 refuses to
    assert deployability, and nothing else mints `_owned_order`, so `StoryMutationScript`
    marks a recruit `own: true` except for the units in `NEVER_OWNED` (Delita, Algus,
    Ovelia, Gafgarion, Alma). The name says what the constant decides — `own`. It is not a
    third role beside ADR-0078's **Class**: `classify` still derives `player`/`guest`/
    `enemy` per battle from owned-membership × `team_color`, and this list is one of its
    two inputs.

    The split is load-bearing rather than cosmetic: Gariland's ENTD 388 spawns Delita as
    the free blue unit, so owning him would deploy a **second** one beside it. The set is
    authored on the same footing as dec.6's `RECRUIT_AT` — dec.8 shows the flags cannot
    decide it, and saying so is cheaper than pretending they do.

    Two smaller consumer rulings ride with it. A **`repeat` join is not folded at all**: it
    re-registers a slug from a different ENTD slot, which would clobber a Character the
    player has been levelling. And the **protagonist's new-game progression is authored**,
    not sourced: his position-0 seed points at ENTD 256, a cinematic slot whose
    `special_name` is 2 — his *Chapter 2* form — and folding it would stamp a durable
    `special_name` at mint, which ADR-0079 forbids. He is minted as a lv1 Squire carrying
    his Ch1 Form set instead; the identity is still derived, only the progression is not.

12. **An APPEARANCE is not a recruitment, and it is DERIVED — the second table.** The
    Orbonne trio (Agrias, Gafgarion, Ovelia) are spawned by ENTD 387 and carry
    `join_after_event` *nowhere*, so no amount of derivation over the JOIN flags reaches
    them — yet binding them is what makes their slots resolve to catalogue Characters
    (HIT) instead of raw-ENTD fallback, which is ADR-0201 dec.6/7's whole point. The
    answer is a second scan over the same records rather than a hand-typed table: **every
    always-present, canonically-named slot of a battle group's ENTD enters the Catalog**,
    at that group's `opener` — the one plan action whose deltas land BEFORE the fight (a
    recruit lands at the group's END, which is too late to bind its own battle). 23 of the
    72 battle groups bind 28 units, out of 77 named present slots scanned.

    Four rulings ride with it.

    - **Named ENEMIES are catalogued too.** The Catalog is the one population (ADR-0078);
      it holds guests and per-battle enemies, and `classify` derives the role. Wiegraf and
      Elmdor are in it, owned by nobody.
    - **`always_present` is the filter, not the slot count.** ENTD 387 also carries a Red
      Delita and a lv1 Ramza/Delita pair the battle never spawns; binding those would bind
      units that are not there.
    - **A slug binds ONCE, at its first battle.** A second bind would re-register from a
      different ENTD slot and clobber a Character the player has been levelling — the same
      hazard dec.11's `repeat` rule guards. Already-recruited units are suppressed too, so
      Gariland's own Delita slot does not fold over the one the Academy granted.
    - **Battle groups only.** A cinematic group has no cast-composition seam to bind
      against, its `team_color` is noise (dec.8), and its plan contributes no action that
      lands at its START — every one of the 72 battle groups carries an opener beat, and no
      linear group carries anything but its own end-keyed action.

13. **A contradiction the flags cannot resolve is REGISTERED, not authored around.**
    `_coverage.recruited_red_conflicts` lists every unit that is already recruited and
    then stands on the Red team at a battle. Three rows. Algus and Gafgarion are
    canon — they turn on you, and dec.11 never owned them — so exactly one survives the
    consumer's narrowing: **Rafa**, derived as a recruit at story position 72 and Red at
    107 (root 291, ENTD 433), which would make her deployable AND hostile in the same
    fight. She reads Red again at 108, but that group is a cinematic and the scope
    excludes it for the reason dec.8 gives.

    ENTD 433 is sharper than "she is an enemy there": it spawns Rafa **twice**, both
    always-present — Blue at slot 0 and Red at slot 1. Which one the battle uses therefore
    cannot be an ENTD fact at all. It is also why the register scans slots directly
    instead of reusing dec.12's scan, which dedupes by slug and would keep the Blue row
    and report nothing.

    This is **not** the Worker 8 gap, and saying it was sent one session hunting event
    opcodes for a mechanism that does not exist (dec.14). Rafa carries `join_after_event`
    again at position 108, on the Red side of ENTD 434, and dec.14 now emits that
    occurrence -- but her FIRST flagged occurrence is still position 72, so `roster_before`
    at 107 is unchanged and the contradiction survives the fix intact. Closing it needs
    the guest-versus-join call of dec.6, which the flags cannot make and dec.6's refuted
    rule cannot supply. So this ADR still declares it rather than inventing a `RECRUIT_AT`
    entry for her. `StoryMutationScriptTest` guards it as a **burn-down of exactly 1**: it
    shrinks when `RECRUIT_AT` gains her and fires if any new unit develops the same shape.

    The register is deliberately emitted UNFILTERED by `own` — dec.8 asserts no
    deployability, so the generator carries all three rows and the consumer, the only
    thing that knows `NEVER_OWNED`, does the narrowing.

14. **A join is read off `join_after_event` alone. `team_color` does not filter it, and
    "event-opcode recruitment" never existed.** This decision replaces a claim earlier
    versions of this ADR made as fact: *"Worker 8 carries no ENTD join flag anywhere; he
    arrives through the Goug side quest's script."* Both halves are false, and the second
    half sent a session looking for a mechanism that is not there.

    Worker 8 carries the flag at **ENTD 291 slot 3** — `special_name` 117, job 0x91
    (Steel Giant) — in the group whose scenarios are literally named *"Worker 8
    Activated"* (Besrodio's House, story position 94). The three Besrodio's House
    cinematics are an A/B/A control the RE could not have asked to be cleaner: same slot,
    same Steel Giant, same tile (5,5), and the flag set in exactly one of them.

    | position | ENTD | scenario | slot 3 | `join_after_event` |
    |---|---|---|---|---|
    | 93 | 290 | Steel Ball Found! | Steel Giant, Red | — |
    | 94 | 291 | **Worker 8 Activated** | Steel Giant, Red | **set** |
    | 95 | 292 | Summoning Machine Found! | Steel Giant, Red | — |

    What hid him was one undocumented line in `_joins_for` — `if team_color_name !=
    "Blue": continue` — in a **cinematic** record, where this same ADR's dec.12 already
    rules that `team_color` is noise ("Ramza alone reads Red in 17 of them, none of which
    is a fight"). The filter is deleted. `join_after_event` is a ROSTER fact and
    `team_color` is a battle-local one; the join table has no business reading the second.
    The raw team travels on the delta instead, and `_coverage.red_join_slots` names every
    kept row so the ruling is auditable from the artifact.

    The blast radius is two slots, and they were counted before the line was cut. Of the
    83 flagged slots game-wide, ten are Red; eight of those are ENTD 366, which no
    scenario references at all. The two that reach a group are ENTD 291 slot 3 (Worker 8,
    a new recruit) and ENTD 434 slot 1 (Rafa, a repeat of a unit already in the roster
    since position 72, so it changes no `roster_before`). One new member, from position 95
    on.

    **Byblos was never missing either.** "Byblos is likely the same shape" was wrong in a
    different way: he has been derived since the first build, as the `create:entd402_10`
    delta at the Elidibs group (position 154). He is anonymous, not absent — his
    `special_name` is 255, so he mints as a generic. That is the identity gap, not a
    recruitment one.

    **And no opcode was ever a candidate.** All 176 opcodes in
    `event_instructions.json` are catalogued; none is roster-shaped. The two dozen
    `*Unit*` opcodes (`Add Unit`, `Remove Unit`, `Dismiss Unit`, `Blue Remove Unit`) are
    scene placement. `tools/test_build_roster_timeline.py` asserts that emptiness, so the
    claim cannot quietly return.

    The regression guard is deliberately **not** "Worker 8 is present". Two tests read
    the ENTD directly rather than the generator's output — the A/B/A table above, and a
    census asserting that every flagged slot in every group reaches the timeline — so a
    filter of *any* kind, on any field, fails here rather than silently shrinking the
    roster again.

## Consequences

**Four gaps are declared in the artifact's own `_coverage`, not left implicit.**

- *No name exists for `special_name` above 72.* `tools/data/UnitNames.xml` stops at
  0x48, so `unit_names.json` can never resolve five real recruits: 117 (Worker 8), 118
  (the Araguay Woods chocobo) and 120/121/127 (the two Knights and the Squire granted at
  Chapter 2 Start). They are derived, folded and carried in `roster_before`; they are
  just anonymous, minting as `entd<record>_<slot>`. Naming them needs a ROM name table
  nothing in this repo carries, which is `fft-ghidra` work, not generator work —
  filed as #762, with the burn-down pinned in `_coverage.known_gap` and in
  `test_the_identity_gap_is_declared_not_hidden`.
- *No LEAVE is derived.* A guest who departs the party stays in `roster_before`.
- *68 of 155 groups are ordered by root-id fallback,* including seven that grant
  recruits.
- *Three units are recruited and then stand Red at a later battle* (dec.13). One of them,
  Rafa, is a real contradiction rather than canon.

**The binding gap shrinks everywhere, not just at Orbonne.** dec.12's scan puts 28 named
units into the Catalog across 23 battles where the authored table reached three at one.
ADR-0201 dec.7 wanted that gap "visible and shrinking"; this is the shrink. What it does
NOT do is bind generics — an unnamed slot has no prior identity to resolve to, and
`SlugBinding`'s raw-ENTD fallback remains the right answer for those.

**A Seek folds the appearances too.** `StoryMutationScript.prologue_deltas_before` is what
the re-rooted walk folds, and it carries each earlier group's appearances *and* its
recruits, in that order. `seed_deltas_before` stays recruits-only, because its fold IS
`roster_before` by construction and that equality is the thing keeping the script and the
derived table from drifting.

**The hand-authored scripts are gone.** `Ch1MutationScript` is deleted with its test;
`GarilandMutationScript` is a forwarder holding `RAMZA_SLUG` and
`owned_seed_deltas()` for the three consumers that walk no plan (`GPUArena`,
`CombatUITestScene`, `CharacterRosterParityTest`). `GarilandMutationScriptTest` became
`StoryMutationScriptTest`, which asserts the *corrected* facts: Gariland grants nobody,
the Academy grants Delita plus six cadets, and the fold equals `roster_before` for five
roots including two the story chain never reaches.

**The owned roster at Gariland changed size, and the deployment clamp absorbs it.**
Seven owned (Ramza + six cadets) where the authored table said five. Gariland's zone caps
`max_squad_size` at 5, so `DeploymentPlan.assign` still fields Ramza + four cadets — the
same squad, now sourced rather than invented. The clamp is no longer an identity no-op,
which is a real behavioural difference for anything reading `owned_units()` **without**
one: `GPUArena` and `CombatUITestScene` now boot a 7-unit player side.

**ADR-0201's fold invariant is untouched.** A derived roster is still a
`MutationScript` consumed by `CatalogueReplay.fold` — this changes where the table
comes from, not what it is.

**`_prologue_before` is deleted, and the seek prologue got STRICTLY wider.** It
replanned from the story root to recover history, so it could only fold groups reachable
by chaining — nothing for 151 of 155 roots. `StoryMutationScript.seed_deltas_before` is
defined for every group in the timeline, so a Seek to Orlandu's group now arrives with
the 21 units the ROM says precede it instead of an empty catalogue.

**A read-only F3 panel ships with the derivation, and it is not scope creep.**
`StoryTimelineDebugPanel` (a new `Category.STORY`) shows, for any of the 155 group roots,
the two answers this ADR made derivable side by side with what the live catalogue holds:
the `enter` state a Seek installs and whether it leaves that group's node alone live, and
`roster_before` plus the joins the group grants. It is the instrument for the reported
defect — "a Seek landed somewhere surprising" is answerable as *data or walk?* only if
you can read both. Seeking itself stays in `NavigatorDebugPanel`, one cell over; this
panel writes nothing.

**The 5 groups gated on `party has job` can never go live** under the current model
(`Campaign._conditions_pass` reads that opcode as failing, deliberately). Seeking to
Nelveska or Goug's Worker-8 beats warns and proceeds with no map node offered.
