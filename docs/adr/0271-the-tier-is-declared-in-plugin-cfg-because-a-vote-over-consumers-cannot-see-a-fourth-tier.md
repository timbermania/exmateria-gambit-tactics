# The tier is declared in plugin.cfg, because a vote over consumers cannot see a fourth tier

`check_addon_portability.py` decided four questions — is this addon arm 1's subject, may it
name a host autoload by node path, may it declare a `global uniform`, and may every sibling
name its symbols for free — by asking one thing: `system_of[addon] is None`. That value was
a **majority vote over the `classify()` buckets of the addon's own files**, and the code's
own comment said what it was meant to mean:

> `system_of[addon] is None` is true for the kernel and the platform port and false for
> every system.

That is a **tier membership test written as a proxy**, and the proxy held for as long as the
only non-system addons were the two free ones. `exmateria_almanac` is where it broke.
`classify()` books a file to the system that *consumes* it
([ADR-0243](0243-the-src-data-tier-is-a-third-addon-and-the-split-the-selection-assumed-does-not-exist.md)
dec. 3), so a package of tables inherits the names of its readers — and the guard reported
the almanac as **the Battle system's addon** while seven of the eleven reach it.

This ADR replaces the inference with a declaration in the package's own `plugin.cfg`, beside
`engine=` and `deps=`, and **re-prices nothing**: the shipped report is byte-identical across
the change — 354 free rows, 53 debt rows, rc=0. What moves is that the answer is now a claim
a reader can check, and that the fourth tier is *stated* to be outside the free set rather
than accidentally inside one of the other three.

Status: accepted (2026-09-09). This is **#1059 phase 1**; phases 2 and 3 are not decided
here and dec. 5 says what phase 2 is worth. Split out of
[ADR-0262](0262-the-alias-route-hid-forty-nine-lines-and-the-almanac-reads-as-a-system-only-because-classify-books-by-consumer.md)
soft spot S2, which found the defect during
[ADR-0267](0267-the-catalogue-lands-and-the-ninth-published-name-was-a-symbol-census-that-could-not-see-a-path.md)'s
audit pass and deliberately did not fix it — widening an enforcing guard's free set
re-prices three shipped extractions, which an audit cannot do to its own subject mid-pass.
Reads
[ADR-0115](0115-a-system-is-a-bundle-that-ships.md) dec. 4 and dec. 6 for what a content
shadow is and what a feature threading two systems looks like,
[ADR-0202](0202-installable-is-the-fork-plus-the-kernel-and-the-port.md) dec. 2 for the rule
that naming the kernel and the port is free and dec. 4 for the shape of a claim that had
nowhere to live,
[ADR-0194](0194-a-test-belongs-to-the-addon-it-can-run-without-the-game.md) dec. 7 for
`engine=`, the declaration this one is modelled on,
[ADR-0243](0243-the-src-data-tier-is-a-third-addon-and-the-split-the-selection-assumed-does-not-exist.md)
dec. 3 for the classifier rule that makes the vote wrong,
[ADR-0262](0262-the-alias-route-hid-forty-nine-lines-and-the-almanac-reads-as-a-system-only-because-classify-books-by-consumer.md)
dec. 5 for the accepted debt lines (which it prices at 55; the tree reads 53 since #1071
paid the `exmateria_sprite_rig` row — see ADR-0272's consequences), and
[ADR-0131](0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md)
dec. 6 for why every reach count here is a floor.
**Supersedes nothing.** ADR-0262 stays accepted; its S2 is discharged by decisions 1 and 5.

## Context

The four call sites are in `walk_addons()`, and they had drifted apart from the value they
read without any of them changing:

| arm | question it asks | what `system_of[a] is None` meant there |
|---|---|---|
| 1 | is this addon's outbound cross-system reach scored? | not one of the eleven → skip |
| 2b | may it name a host autoload as a node-path string? | not one of the eleven → free |
| 4b | may it declare a `global uniform`? | not one of the eleven → free |
| 5 | may a sibling name its `class_name` for free? | not one of the eleven → free |

Three of the four are asking *"is this one of the two free tiers"*. The first is asking
something else — *"does this package have a cross-system budget"* — and the two answers
coincided only because every package in the tree was either free or one of the eleven.

**The vote is wrong in two directions, and a count of the almanac's buckets sees only one.**

1. It is **confident and wrong** for `exmateria_almanac`. Measured at `c6549fd4c` over the
   addon's own files: `Battle` 14 / `content` 11 / `UI` 5 / `infrastructure` 2 /
   `generated` 2.
2. It is **blind** for both `EXTRACTED` roots. `exmateria_sound` and `exmateria_spu` sit
   outside `classify_blueprint`'s walk (#326 — the host's copy is a deployment copy and
   walking it would double-count), so `classify()` returns `None` for **all 163 of their
   source files** and the modal-bucket vote returns `None` — which is the FREE set. The
   only thing between that and a free verdict is `_walk_roots.EXTRACTED` naming two paths
   by hand. The vote has never once answered this question for a package it was not told
   about.

## Decision

**1. The tier is DECLARED in the package's own `plugin.cfg`, and nothing infers it.**
`tier="kernel" | "port" | "system" | "rules"`, one key at column 0, the same spelling
`tests/stranger/shared/rig.sh` already reads `engine=` and `deps=` with. It goes there and
not into a table under `tools/` for `engine=`'s reason
([ADR-0194](0194-a-test-belongs-to-the-addon-it-can-run-without-the-game.md) dec. 7): it is
a fact about the package, a rig that *stages* the package can read it, and a Python table in
the host does not travel. It is
[ADR-0202](0202-installable-is-the-fork-plus-the-kernel-and-the-port.md) dec. 4's shape —
`plugin.cfg` could not express a dependency, so the README and the register carried the
claim — arriving at the one key that had nowhere to live. Nine roots, nine declarations:
kernel `exmateria_schema`; port `exmateria_platform`; rules `exmateria_almanac`; system
`exmateria_render`, `exmateria_battlefield`, `exmateria_sprite_rig`, `exmateria_catalogue`,
`exmateria_sound`, `exmateria_spu`. The reader is `_walk_roots.declared_tier()`, beside
`EXTRACTED` and `RIGS`, because that module already owns the doctrine that a root fact is
declared once rather than derived per consumer.

**2. #1059's body says nine of the eleven systems reach the almanac. It is SEVEN, and the
correction matters more than the number.** Nine is the count of *buckets* in that table, and
`assembler` and `content` are not systems. Re-measured on this tree, non-test, `src/` plus
every sibling addon root, resolved through the façade exactly the way arm 5 resolves it
(`sibling_class_reaches`): **698 lines over 140 rows** —

> Battle 274 · UI 265 · assembler 69 · Character Catalogue 56 · content 11 · Cutscene 8 ·
> Audio 6 · Effects 6 · Campaign 3

Seven of the eleven, and the top two are **3.4% apart** (#1059 says 1%, taken before
[ADR-0267](0267-the-catalogue-lands-and-the-ninth-published-name-was-a-symbol-census-that-could-not-see-a-path.md)
moved `src/characters/` into `exmateria_catalogue`, which is why `Character Catalogue` is 56
lines of it). Both corrections make the argument *weaker* and are recorded anyway; a
selection argument that only ever gets restated with its own numbers is
[ADR-0267](0267-the-catalogue-lands-and-the-ninth-published-name-was-a-symbol-census-that-could-not-see-a-path.md)
dec. 1's census wearing a different hat. The conclusion is untouched: this is
[ADR-0115](0115-a-system-is-a-bundle-that-ships.md) dec. 4's content shadow — *"Every system
casts a shadow of FFT-specific data"* — except it is the union of seven shadows plus two
non-system buckets, which is nobody's shadow in particular.

**3. An undeclared tier RAISES, and a commented one is not a declaration.**
`extracted_roots()`'s rule verbatim, for its reason: a consumer that reads a missing
declaration as a default reads it as **one of the four answers**, and three of the four move
an enforcing verdict. There is no fallback to the old vote — a fallback is the defect with a
longer half-life, because the day it fires is the day a new addon is scored by the thing this
ADR removed. `; tier="port"` in a comment raises too; every tier in this corpus ships under
six to forty lines of `;` prose that *name* the four tiers, so a reader that matched its own
documentation would be green on all nine.

**4. `rules` is a fourth tier and `exmateria_almanac` is its only member.** The corpus named
all four before this ADR — the kernel
([ADR-0139](0139-the-shared-kernel-is-enumerated-by-the-schema-list.md) dec. 9), the port
([ADR-0169](0169-platform-ships-to-its-own-address-and-shipping-a-file-is-not-shipping-a-shader.md)
dec. 1), the eleven
systems, and *"the game's rules"*, which is the almanac's README's own predicate. What it
had no way to say was that a package could be **none of a system, the kernel or the port**.

**5. `rules` is NOT in the free set, and that is a decision rather than a deferral.**
`_walk_roots.PORTABLE_TIERS` is `{kernel, port}`, so a sibling naming a symbol the almanac
publishes is still printed: 53 arm-5 debt lines, all `exmateria_catalogue`'s, which
[ADR-0262](0262-the-alias-route-hid-forty-nine-lines-and-the-almanac-reads-as-a-system-only-because-classify-books-by-consumer.md)
dec. 5 accepted. **Priced, not asserted:** adding `rules` to the free set takes arm 5 from
354 free / 53 debt to **407 free / 0 debt** — the block does not shrink, it stops existing,
heading and all. That is what phase 2 is worth, and it is a test
(`test_freeing_the_rules_tier_takes_the_debt_block_to_ZERO`) rather than a paragraph.

🔴 **Both halves of that price moved after this ADR was drafted, and the remainder moved to
zero.** It was written as 55 debt leaving 2, the 2 being the `exmateria_sprite_rig` row named
as #1071's. #1071 landed first and paid that row by DELETING the key it produced
([ADR-0272](0272-the-palette-row-edge-is-paid-by-deleting-the-key-because-no-consumer-read-it.md)),
and its two arm-5 lines *were* arm 1's row — the alias and the call it fed — so they were
never an independent remainder. Every surviving row is the almanac's, which is what makes
freeing the `rules` tier a clean zero rather than a smaller number. The assertion is now
`assertNotIn` on the heading, because a count assertion passes for a block that merely got
quieter, and the free block's own 354 -> 407 is carried as the second reading of the same 53.

The reason not to take it today is measured, not stylistic. Of those 698 consumed lines,
**581 (83%) sit on members that two or more of the eleven reach**, and only **40%** of the
total is a `*Database` at all:

| member | lines | who reaches it |
|---|---:|---|
| `GambitCondition` | 74 | UI 44 · Battle 30 |
| `Gambit` | 57 | Battle 35 · UI 22 |
| `TargetSelector` | 81 | Battle 43 · UI 34 · assembler 4 |
| `UnitRole` | 24 | UI 14 · Battle 10 |

Battle and UI sharing *behaviour* through a package of tables is
[ADR-0115](0115-a-system-is-a-bundle-that-ships.md) dec. 6's warning that a feature threads
systems — and dec. 6 names **gambits** as its example, which is the same four rows. Freeing
the package wholesale would stop arm 5 printing that, which is worse than today's wrong
bucket: a wrong bucket is a claim someone can falsify, and silence is not.

**6. Two questions, two maps: the tier is about the PACKAGE, the system name is about the
FILES.** `tier_of[addon]` is declared; `system_of[addon]` keeps the vote and returns `None`
for every tier that is not `system`. The vote survives here because a name is exactly what it
*can* see, and it is unambiguous for all four in-walk system addons — `Battlefield` 55/16/1,
`Sprite Rig` 34/1/1, `Character Catalogue` 12/1, `Render` 5/1. `free[addon]` is spelled once,
next to both, and the four arms read it. That the free set used to be spelled four times in
four different arms is why widening it looked like a one-line fix and was not.

**7. 🔴 ARM 1'S GATE MOVES TO THE TIER, AND LEAVING IT ON THE NAME WOULD HAVE SILENCED THE
ARM OVER A WHOLE ADDON.** `system_of[exmateria_almanac]` was `Battle` and is now `None`,
because `rules` is not one of the eleven. Arm 1's gate read `if system is None: continue`.
Left alone, this change would have taken the almanac **out of arm 1's subject entirely** —
and an arm going quiet over a package reads exactly like a package with nothing to report,
which is this guard's own founding defect (*"WHY THIS GUARD WAS GREEN WHILE BOTH WERE
TRUE"*). Only the two FREE tiers are outside arm 1's subject; `rules` is inside it, and
`cross_system()` filters on the reach's DESTINATION regardless. Guarded by a seed:
`test_the_almanac_has_no_system_NAME_and_is_still_arm_1s_SUBJECT` writes a file naming
`Unit` into the real addon and requires arm 1 to still report `Battle.Unit`. Reverting the
gate reddens that arm and nothing else; reverting arm 5's free test reddens dec. 5's pricing
arm and nothing else. Both were run.

**8. The verdict does not move, and that is the claim.** Declaring what was inferred
re-prices nothing: `check_addon_portability.py`'s output is **byte-identical** before and
after (354 / 53 / rc=0), diffed rather than eyeballed and **re-taken on the rebased tree**
against a fresh `origin/main` worktree: identical but for the absolute path in a
`SyntaxWarning` line, which is a property of where the file sits and not of the change. A
phase-1 that also moved the numbers
would make the pricing change and the meaning change indistinguishable, which is
[ADR-0223](0223-a-reach-has-a-bucket-and-an-address-and-goal-5-only-ever-read-the-bucket.md)
dec. 3's NOTHING-MOVES gate: *"A scanner change that moves a burn-down is indistinguishable
from debt being paid."* Its own attribution is the second instance of dec. 10 — see there.

**9. `--root X --system Y` declares `tier="system"` by hand.** It is the only path that
reaches a root the walk has never seen, naming one of the eleven *is* the tier claim, and it
is what keeps every scratch-package arm in the test register working without a `plugin.cfg`.

**10. 🔴 FOUND WHILE VERIFYING THE CITATIONS: `ADR-0139 dec. 9, dec. 12` DOES NOT CONTAIN
THE RULE FOUR COMMENTS ATTRIBUTE TO IT.** dec. 9 is *"Name and place:
`godot-learning/addons/exmateria_schema/`"* and dec. 12 is *"Tunable declarations is a schema
whose realisation is a port's signature, so it has no kernel member and never will."*
Neither says that naming the kernel and the port is permitted, and none of ADR-0139's
fourteen decisions does. The rule is stated in
[ADR-0202](0202-installable-is-the-fork-plus-the-kernel-and-the-port.md) dec. 2 — *"Naming
the kernel and the port is what ADR-0139 dec. 9 and dec. 12 **permit**"* — which is where
the guard's comments got the attribution, so the paraphrase is faithful to its source and
its source is the mis-citation. ADR-0139 *does* say **"The kernel is not a system"**, in
dec. 8's body. The comment blocks this change touches now name ADR-0202 dec. 2 as the rule's
home; the untouched ones in the same file still carry the old pair and are left for a sweep
rather than widened into this diff. **It is not a one-off.** Verifying the citations this ADR
itself makes turned up a second, independent instance: dec. 8's NOTHING-MOVES rule is cited
as `ADR-0205 dec. 7` by **both**
[ADR-0223](0223-a-reach-has-a-bucket-and-an-address-and-goal-5-only-ever-read-the-bucket.md)
dec. 3 and
[ADR-0232](0232-goal-5-is-a-conjunction-and-neither-instrument-may-claim-the-word-alone.md)
item 1, and ADR-0205 dec. 7 is *"This pass rules and builds the register. It does NOT
collapse `MapComposer`."* None of ADR-0205's eight decisions states the rule. The rule is
real and is ADR-0223 dec. 3's own sentence; the attribution is borrowed prose that nobody
could have checked. Two independent instances found by opening two cited files is a **rate**,
not an anecdote — and it is exactly the class `check_adr_anchors` cannot see. That guard
checks that a cited ADR **names a file**; whether the decision NUMBER exists, and whether it
says what is claimed, is checked by nobody, and `docs/adr/` is excluded from its citation
scan besides. Both corrections are recorded here rather than swept (S5).

## Considered alternatives

- **A `TIERS` table in `tools/_walk_roots.py`, beside `EXTRACTED` and `RIGS`.** The obvious
  shape, and rejected on `engine=`'s own argument: the two existing per-package declarations
  live in `plugin.cfg` because a **rig that stages the package reads them**, and a table in
  the host does not travel with the addon it describes. The counter-argument — that
  `EXTRACTED` already declares the system *name* for two roots, so a second site invites
  drift — is real and is answered rather than dismissed: `tiers()` reads the union of both
  root populations through one map, and `exmateria_spu`'s declaration was chosen to agree
  with `EXTRACTED`'s (dec. 4 of this ADR's soft spots asks whether it should).
- **Declaring the system NAME in `plugin.cfg` too, and retiring the vote entirely.**
  Rejected: it is a second, unchecked home for a fact `EXTRACTED` already declares for the
  two roots that need it, and the vote answers the name question unambiguously for the four
  that do not (dec. 6). A declaration whose only job is to agree with a derivation is a
  register nobody reconciles.
- **Adding `rules` to the free set now, as #1059's phase-1 sketch reads.** Rejected on the
  83% measurement in dec. 5. It would make the guard green over 53 lines of Battle-and-UI
  shared behaviour, and the number would look like debt being paid.
- **Splitting `exmateria_almanac` into a tables package and a behaviour package.** The
  honest fix for the thing dec. 5 measures, and out of scope twice over: it is a membership
  change, and
  [ADR-0167](0167-the-mount-inverts-to-the-host-and-the-fix-was-booked-into-the-bucket-it-drains.md)'s
  rule is that a behavioural change does not ride inside an address move. It is #1060's
  subject.
- **Keeping the vote and special-casing the almanac by name.** Rejected: a name list *is*
  the inference, wearing a list. The next package with a content shadow gets the same wrong
  answer and no one is told.
- **Falling back to the vote where no tier is declared.** Rejected by dec. 3. A fallback
  fires exactly when a new addon joins the walk, which is the case this exists to catch.

## Consequences

- **Adding an addon root now requires a tier or the whole guard raises.** That is the
  intended direction — loud, at the first read, in the same class as `EXTRACTED`'s missing
  path — but it is a new way for the pre-flight to stop, and the message has to be the fix.
- `plugin.cfg` grows a third non-standard key. `tests/stranger/shared/rig.sh` reads its two
  keys with anchored `sed` expressions and is inert to this one, verified by reading the
  three call sites rather than by running the rigs.
- **`tools/score_goals.py:668` still holds a copy of the vote**, answering "which system is
  this addon's scorecard for". It is unreached for the almanac today — `docs/GOALS.tsv`
  carries rows for `Render`, `Battlefield`, `Sprite Rig` and `Audio` only — so it is a second
  inference site that is currently correct and structurally able to be wrong. Named here
  rather than fixed, because the two ask different questions and merging them without saying
  so is how one answer becomes two.
- `check_adr_anchors.py` scans `plugin.cfg`, so the eight `ADR-0271` citations in the nine
  declarations red it until this file exists. `docs/adr/AUDIT.md` and `INDEX.md` regenerate
  by one cell for the same reason.
- The test register grows from 69 arms to 80. The eleven new ones are the reader in both
  directions (four), the tree's coverage and free set (two), the vote-versus-declaration
  divergence (one), arm 1's subject in both directions (two), and dec. 5's pricing (one),
  plus the comment control.

## Soft spots

- **S1. `exmateria_spu` is declared `system` because that is what the tree measures, and its
  own description reads like a port** — *"A PlayStation 1 SPU for Godot … Bring your own
  samples."* `EXTRACTED` books it `Audio`; today's free rows out of
  `exmateria_sound` are free on arm 5's **same-package** ground — `package_project(home) ==
  own`, i.e. both ends ship under one `project.godot`, which is the only kind that parses
  standalone — and not on a tier ground, so
  re-declaring it `port` would change no count and would change what the count *means*. A
  tier declaration must not smuggle in a re-pricing, so it is declared as measured and asked
  here.
- **S2. The system NAME is still a vote**, and it is the same mechanism this ADR removed one
  use of. It agrees today with four clean majorities, and nothing red goes off the day one of
  them stops being clean — `test_the_vote_and_the_declaration_diverge_for_the_ALMANAC_and
  _agree_elsewhere` asserts the *agreement*, which is one bit, not the margin.
- **S3. The 698-line consumer measurement is a FLOOR**
  ([ADR-0131](0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md)
  dec. 6). It resolves through the façade and counts `.gd` only; a duck-typed reach carries
  no type name and is invisible to every arm. The 83%/40% split is a split of what the
  scanner can see.
- **S4. The tier is declared but its MEMBERSHIP is not checked.** #1059 phase 3 promotes the
  almanac README's own predicate — *"every one of them answers a question about the game's
  rules without touching a node, a scene, a shader or a frame"* — to a guard, and the ticket
  already names three members that pass its letter and fail its intent
  (`progression/UnitProgression.gd`, `gambits/GambitList.gd`, `abilities/AbilityLoadout.gd`
  hold per-playthrough state, not rules). Until that lands, `tier="rules"` is a claim about
  the package that nothing tests against its contents.
- **S5. Dec. 10's two mis-citations are corrected only where this diff already reads.** The
  `ADR-0139 dec. 9, dec. 12` pair appears in several untouched comments in
  `check_addon_portability.py` and in `tools/score_goals.py`'s `cross_system()` docstring, and
  in ADR-0202 dec. 2 itself, which is upstream of all of them; the `ADR-0205 dec. 7` pair sits
  in two ACCEPTED ADRs, which this ADR may not edit at all. A sweep is its own change. **And
  the instrument is half-built, not absent** — `tools/check_adr_quotes.py` (ADR-0154, #403)
  substring-matches every `*"…"*` span against the ADR cited **on the same line**, and it is
  live on this file: a seeded fabrication at `0271:312` was flagged, so its zero here is a
  measured zero. It is structurally blind to **both** findings, because neither carries a
  quoted span at all — a bare `(ADR-0139 dec. 9, dec. 12)` is an attribution with nothing to
  match. Measured on this ADR: **1 of its 38 `ADR-NNNN` mentions sits on a line that also
  carries a quotable span**, and all **48** of its `dec. N` references are unchecked by
  anything. The missing half is a resolver from `ADR-NNNN dec. K` to a heading in the cited
  file — cheap, because every decision in this corpus is a `**K. …**` line. Not filed; worth
  a ticket.

## Not decided

#1059 phase 2 (free-ness by member kind), #1059 phase 3 (the membership predicate as a
guard), #1060 (whether `gambits/` belongs in the almanac at all), #1071 (the sprite-rig
palette edge, which is the 2 debt lines dec. 5's pricing leaves standing), and the
`encounters/EntdPositionDatabase` un-publish that #1059 records as trivially separable.
