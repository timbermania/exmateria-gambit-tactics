# The Target column names a POOL and a DEPTH, and `Nearest` was the word that was lying

The player asked for three rows per team, in their own words:

> *"I want all 3 options. Ally, Nearest, Weakest"*

The ask exists because of an objection they made first, and the objection is correct:

> *"it can't be nearest and any"*

It could not, and it was. Today's `Nearest Ally` row encodes `TARGET_NEAREST_ALLY`, and
`evaluate_gambits_up_to`'s **second pass retries that type at ranks 1, 2, 3…** — so the row has
always meant *"an ally, nearest first"* while the label on it said *"the nearest ally"*. The
label was describing rank 0 of a walk that never stopped there.

Status: accepted (2026-09-11). **Amends
[ADR-0278](0278-the-seed-is-the-familys-pool-and-the-family-is-ours-because-the-rom-records-a-hit-policy-and-not-a-purpose.md)
dec. 2** (the seed follows the behaviour those words described, not the words); narrows
[ADR-0268](0268-the-gambit-row-is-a-sentence-read-across-the-screen-and-a-screen-that-owns-the-pad-re-means-the-action.md)
dec. 8 (the offer list grew two rows and both round-trip); reads
[ADR-0283](0283-the-gambit-rows-subject-is-its-own-column-and-the-slot-number-shares-a-lane-to-pay-for-it.md)
dec. 1 for `Their` and [ADR-0023](0023-gambit-gpu-projection-stays-in-encoder-faithful-or-explicit.md) for why an
unmappable selector is a skip and never a substitution. Supersedes nothing.

## Context

**This is a new capability wearing a rename's clothes, and getting that backwards is the way to
ship a silent behaviour change.** Three facts, each verified against the kernel rather than
inferred from the screen:

1. **`Nearest Ally`-as-strictly-one did not exist.** Pass 2's retry decision reads
   `cond_target_type` **and nothing else** — there is no per-slot flag anywhere in
   `GambitField`, and no spare int to put one in (offsets 0–13 are host-written and
   `RESERVED_14/15` are the kernel's own per-slot verdict and payload, ADR-0275).
2. **`Ally` did.** It is today's `TARGET_NEAREST_ALLY`, byte for byte.
3. **`Weakest Ally` did.** `TARGET_LOWEST_HP_ALLY`, and Pass 2 never retried it.

So of the three rows asked for, two are renames of things that already work and one is a
capability the kernel has to grow. The renames are the dangerous half: every existing save
carries a selector, and a save that reads back under a re-meant word is a rule the player never
wrote.

## Decisions

**dec. 1 — Depth is a RESOLUTION, not a new field, and that is what keeps this cheap.**
`TargetSelector.ResolutionStrategy` already distinguishes *how one unit is picked out of a
pool*, and `_target_selector_to_gpu` already switches on it. So `NEAREST_ONLY` is one **appended**
enum member — appended and never inserted, because `to_dict`/`from_dict` serialise the int — and
the whole change lands with **no new almanac member, no new schema row, no save migration, and
no ADR-0118 / ADR-0139 schema-admission gate.** The rejected route is below; it was the one
recommended to the player first.

**dec. 2 — `NEAREST` is renamed `NEAREST_FIRST`, or the defect is rebuilt one layer down.**
After this change the member called `NEAREST` is the one that is **not** "the nearest" — it is
the pool search that merely starts there. Leaving the name would re-create, in the domain, the
exact label-vs-behaviour defect the ticket exists to remove, in a layer no screen test looks at.
Renaming is free: the int position does not move, so nothing serialised changes.

**dec. 3 — Two GPU target types, and their value is their ABSENCE from Pass 2's guard.**
`TARGET_NEAREST_ALLY_ONLY = 9` and `TARGET_NEAREST_ENEMY_ONLY = 10` call the **same**
`find_unit_by_criteria(..., mode=0, ...)` the non-strict types call — identical search, identical
path metric, identical self-skip. Pass 2's `target_type !=` guard simply does not list them, so
they fall into the existing `VERDICT_NOT_RETRYABLE` branch: **no new verdict code, no new clause,
no new branch to test.** `GPUConstants` is generated from the shader so it follows;
`SHADER_VERSION` 34 → 35.

**dec. 4 — The family seed takes the POOL row, which AMENDS ADR-0278 dec. 2 rather than
following its words.** That decision records the player saying *"healing defaults to nearest
friendly, buffs default to nearest friendly"* — and when they said it, the only ally row on the
screen **was** the pool search. Seeding the NAME `Nearest Ally` would have narrowed every healing
and buff ability to a single candidate on the tick the rename landed: a behaviour change riding
inside a relabel, which is the shape of defect this whole ticket removes. So
`family_aim_name` returns `Ally` / `Foe`, every seeded slot behaves exactly as it did yesterday,
and a player who wants strict depth picks the row — which is the point of it being a row.

**dec. 5 — `Nearest` moves off `NEAREST_FIRST` in PROSE too, and lands on nothing.**
`GambitProse.resolution_word` answered "Nearest" for the pool search, so the sentence
*"Cure Nearest Ally Unit when Nearest Ally Unit HP < 50%"* claimed a depth the rule did not have.
A resolution that narrows the pool by nothing contributes **no word** — the line reads
"Ally Unit" — and both sentence builders already drop an empty resolution rather than leaving a
gap. "Nearest" now appears exactly where one unit really is the whole pool.

**dec. 6 — Foes split too, and the `To` list now scrolls.** They said "Ally, Nearest, Weakest";
asymmetry between the teams would be the surprising choice, and `Foe` is needed anyway as the
honest name for the aim `Attack` seeds and ADR-0048's safety net carries. Eight rows —
`Self`, `Them`, `Foe`, `Nearest Foe`, `Weakest Foe`, `Ally`, `Nearest Ally`, `Weakest Ally` —
against `VISIBLE_ROWS = 5`, so it scrolls. Order is load-bearing: the cursor rests on the head,
`Self` keeps it, and each team's pool row leads its own group. **Pixels cost nothing:** `Ally`
and `Foe` measure 14 px against a 48 px cap the existing widest rows already fill.

**dec. 7 — `GambitOptions.nearest_foe()` is renamed `foe_pool()`.** It builds `NEAREST_FIRST`,
and a constructor named after a depth it does not have is how a reviewer confirms the wrong thing
in one glance. Same value, same three callers (the `In Range` subject, the `Attack` seed, the
`Foe` row), which have to stay one object so the `To` column can NAME the seeded aim.

**dec. 8 — The witness is WHICH SLOT COMMITTED, on one unit in one battle.** The two selectors
differ in one field and produce the SAME rank-0 candidate, the same ability, the same target and
the same reach — so no observable outside the slot can tell them apart. Scenario **B10** puts the
strict row at slot 0 and the pool row at slot 1 on one Healer whose rank-0 ally is healthy: the
strict row must find nothing and the pool row must retry past it, and `first_commit.slot` says
which happened. Not two fixtures compared across two runs, which is a provenance error dressed as
an A/B. **B10c is its positive control** — the same fixture with the 80 HP moved onto rank 0, so
the strict slot fires — because "the strict slot never fired" is otherwise satisfied by a type
that cannot fire at all.

**dec. 9 — `Them` LEAVES THE `To` LIST, and the grade is what removes it.** ADR-0283 kept the
row on the reasoning that the fourth column NAMES what `Them` forwards to, so it could stay and
say so. *That reasoning does not survive the press.* Landing `Them` re-mirrors the subject,
`mirror_of` refuses to copy a `TRIGGERING` aim and falls back to the ACTOR — and the other
branch is no different, because with a two-row subject catalogue "not a copy of the aim" can
only mean `My`, which is the actor already. **Both paths end with the subject on the caster**, so
the row the gate called SENSIBLE produced `Self` under a word that says otherwise: #1125's own
opening complaint, manufactured by the row that was kept to answer it.

So `aim_verdict` grades EVERY `Them` aim `AIM_UNNAMED` (the circular pair still grades the
graver `AIM_NEVER_RESOLVES` first), and `targets_for` withholds it as a consequence rather than
as a special case — the offer list and the grader stay ONE decision, which is ADR-0276's rule and
the guard that caught the first attempt at this. `Them` STAYS in `targets()`, because that
catalogue is also the READBACK and `_target_text` prints the literal "Self" for any selector it
cannot name: the safety net, the imperative and #895's operators all build `TRIGGERING` aims, and
withholding a row says what can be AUTHORED, never that a row already holding one may lie.

⚠️ **The imperative grades its rows differently now, and it had to.** `_order_target_choices`
asked `aim_verdict(verb, ability, Them, row)` — with `Them` as the AIM — so the new rule emptied
the order's `To` list outright. The two were never the same question: a slot asks *"may this verb
be aimed at a pool it forwards to"*, an order asks *"may this verb be aimed at this pool"*. The
verb-and-ROM half is identical either way (`aim_class(Them, row)` forwards to `aim_class(row)`);
only the slot-specific tail differed, and an order has no subject column for that tail to be
about. It now grades the row directly, with the caster skip restated explicitly — an order that
locked onto the issuer is the `Self` row under the word "lock-on".

**dec. 10 — THE `If` PRESS MUST NOT TOUCH THE SUBJECT.** Reported from play: *"when I enter
gambits left-to-right I can't choose `my` or `their`."* Correct, and worse than it sounds. The
`If` apply called `_seed_subject`, which re-derives the subject from the aim — so a player
authoring the row in READING ORDER (`Do`, `To`, `Subject`, `If`) had their `Subject` press
overwritten one column later, and **both** choices came out `Their`. The column was inert in
exactly the order the four-column layout asks the row to be read, and it worked only if the
player authored `If` BEFORE `Subject`. It was invisible as well as discarded: with a blank
condition `subject_label` returned BLANK, so the press showed no change to confirm or deny.

⚠️ **THIS DEC. FIXED THE DISCARDING AND LEFT THE INVISIBILITY**, and the player reported it a
second time — *"I can't select 'my' or 'their' until AFTER I have selected a condition"* — because
from their seat a press with no readout and a press that is thrown away are one symptom. The
display half is ADR-0283 dec. 3, since amended: the subject no longer blanks with the condition,
so the press shows the moment it is made. Nothing here changes; the arm this dec. added reads the
column only AFTER the `If` press, which is why it could not catch the other half.

Nothing needs seeding there. The subject is already right by the mirror invariant ADR-0283 dec. 3
maintains everywhere else — `_clear_condition` mirrors, the `To` press re-mirrors when it was
mirrored, `_seed_aim` re-mirrors on a verb press — so an untouched row arrives already reading
`Their` and a row set to `My` arrives holding the actor. Seeding could only ever overwrite one of
those two, and only the player's, because the default is what seeding recomputes. `_seed_subject`
is deleted rather than left unused; its own docstring claimed *"the subject is its own part, so
one press of ○ on it overrides this"*, which was the opposite of what it did.

## Rejected

- **Packing a STRICT bit into `COND_TARGET_TYPE`.** This was recommended to the player first and
  it is worse: it grows the encoded field's meaning, needs the packing and unpacking mirrored on
  both sides of the GPU boundary, and buys nothing that two dense offsets in a range that was
  already `0..8` do not. Measured after the recommendation, not before.
- **A per-slot flag in `GambitField`.** There is no spare int. `RESERVED_14/15` are kernel-written
  (ADR-0275's per-slot verdict and payload) and taking either blinds `GambitVerdictReader` and
  `GambitVerdictCellsTest` — a debugging instrument traded for a feature that needs no buffer.
- **Offering the free fourth combination.** `Weakest Ally` + non-strict is *"the weakest ally who
  is under 50%"* and falls out of the design for nothing. They asked for three; a list that grew a
  row nobody asked for is a list that scrolls further for a sentence nobody has needed yet.
- **Seeding `Nearest Ally` because ADR-0278 dec. 2 says "nearest friendly".** See dec. 4 — those
  words named a row that has since split in three, and following them literally is the one reading
  that changes behaviour.
- **Keeping `NEAREST` and documenting the discrepancy.** A comment does not survive the next
  reader; the name is what the encoder, the prose layer and twelve string literals actually read.

## Consequences

- **Existing saves are untouched by construction.** They carry `NEAREST_FIRST` (int 0, unmoved)
  and encode to `TARGET_NEAREST_ALLY` exactly as before. Only the WORD on the row changes — from a
  wrong one to a right one — and the `To` column reads it out of the same catalogue it offers.
- **`Nearest Ally` still excludes the caster, and a LONE unit's row resolves to nobody.**
  `find_unit_by_criteria` skips `u == unit_id` on the nearest metric unconditionally, so with no
  other friendly standing the strict row has no rank 0 and Pass 1 writes `VERDICT_NO_CANDIDATE`.
  That is what today's row already does in the same spot — strict depth changes what happens
  AFTER rank 0 fails, never whether rank 0 exists — so it is recorded here and not fixed here.
- **The (verb × aim) census walks 8,992 cells where it walked 6,744**, the aim axis going 6 → 8.
  The grade distribution moves with it: sensible 7,249 / no_op 5 / forbidden 1,247 / ignored 27 /
  unnamed 184 / never_resolves 280.
- **`GambitEncoderTest`'s rank-walk arm now grades BOTH directions off one table** — the pool rows
  must be retryable and the depth rows must not. Either arm alone is satisfied by a build that has
  collapsed the distinction in one direction, which is how the label started lying.
- **`GambitProseTest`'s resolution table is exhaustive over the enum and asserts it**, so a
  seventh strategy is a red rather than a string nobody has ever read.
- **`KO`-inclusive strict is UNSUPPORTED, not approximated.** There is no
  `TARGET_NEAREST_ALLY_OR_KO_ONLY`; the encoder refuses `NEAREST_ONLY` + `include_ko` under
  ADR-0023 rather than dropping half of what the author asked for.

## Verification

**The seeded control is the argument, and it is one line.** `TARGET_NEAREST_ALLY_ONLY` was added
back to Pass 2's `target_type !=` guard — the single edit that would re-mean the row — and the
scenario suite re-run. **Exactly one verdict went red**, B10, and inside it exactly the two
assertions designed to:

```
gambit_fired_at_slot(unit='Healer', slot=1)  first commit at tick 61 slot 0 (expected 1)
no_commit_at_slot(unit='Healer', slot=0)     committed from slot 0 at tick 182
```

B10c stayed green, and so did the other 91 scenarios. The healing assertions **also stayed
green under the seed**, which is the half that proves the comment above them: a heal landing on
rank 1 is produced by both readings, so it is not the discriminator and the fixture does not
pretend it is.

Clean-tree runs: `GambitScenarioRunnerTest` **93 scenarios green** (85 PASS / 5 XFAIL / 1
pre-existing XPASS — the same set ADR-0283 recorded, two more scenarios, no new reds);
`GambitEncoderTest` PASS at 8,992 census cells; `GambitProseTest` PASS, 63 strings pinned;
`GambitSurfaceTest` PASS; `GambitCellSynthTest` PASS with **no undeclared coverage gap**, which
is where the two new GPU types prove they are REACHED and not merely declared;
`GambitVerdictCellsTest` 80/0; `GambitSafetyNetTest`, `GambitEncodeSchemaTest`,
`AdjustmentTurnTest` PASS; project-wide parse sweep clean.

**A fixture was moved for a reason worth recording.** B10 first put rank 1 two tiles from the
Healer. It failed — and not in the shape the rank walk would fail in: the Healer committed
ONCE, at tick 61, and **no heal landed on anyone**, rank 0 included (asserted, so it was not
B7's target-hijack). Every distance-1 cast in the suite lands (B10c at 249, I2 at 246–253) and
both distance-2 attempts produced a lone commit and no cast, which points at the cast-position
search rather than at anything this ADR touches. The two allies are now equidistant and
separated by rule C1's stable unit-id tie-break, which takes that pathway out of a fixture whose
subject is the CONDITION pass.

**dec. 9 and dec. 10 are each direction-tested.** Putting the `If` press's re-seed back reds
**exactly one** assertion — the `My` case — while the `Their` case and the never-pressed default
stay green, which is the asymmetry the defect has by construction: it always produced `Their`, so
an arm pinning `Their` alone passes ON the bug. That is why the guard asserts the two choices
DIFFER and carries the default as a third row. Reproduced before the fix and confirmed after it
through `capture_gambit_surface --author='Attack|Foe|My|HP<50%'`, which is the instrument that
lands each choice through the part's own apply in reading order: `Their` before, `My` after, and
`--then=Subject:My` correct in both, which is what named the PRESS rather than the value.

`Them`'s removal was caught by ADR-0276's own guard on the first attempt — withholding it in
`targets_for` alone reds `GambitEncoderTest` with *"grades 'sensible' but the `To` list WITHHOLDS
it — the offer list and the grader must be one decision"*, which is the guard doing its job and
the reason the rule moved into `aim_verdict`. The `To` list was then PHOTOGRAPHED, not merely
asserted: it reads `Self / Foe / Nearest Foe / Weakest Foe / Ally`.

After both: `GambitSurfaceTest` 266/0, `GambitEncoderTest` PASS, `GambitProseTest`,
`GambitCellSynthTest`, `GambitSafetyNetTest` PASS, parse sweep clean.

## Soft spots

- **S1 — B10's ranks come from a TIE-BREAK, not from distance.** Both allies sit one tile out
  and rank order is declaration order (rule C1). Deterministic and documented, but a change to
  the tie-break would red B10 for a reason that has nothing to do with depth.
- **S2 — the distance-2 cast failure above is UNDIAGNOSED.** Two fixtures showed it, the
  hijack reading is ruled out, and nothing further was done: it is outside this change and
  inside B6/B7's open territory. It is written down here because the next person to place a
  scenario target two tiles from a caster will otherwise spend the same hour.
- **S3 — nobody has played a battle with a strict row in it.** The kernel is witnessed, the
  encoder is witnessed and the screen is witnessed; what "strict depth feels like to play" is
  unmeasured, and dec. 4's whole argument is that it should not arrive unasked.
- **S4 — the `To` list SCROLLS now.** Seven rows after dec. 9 removed `Them`, against
  `VISIBLE_ROWS = 5`. Photographed at the `to` level (`Self / Foe / Nearest Foe / Weakest Foe /
  Ally` visible), so the list is no longer unwitnessed — but no capture was taken of it SCROLLED,
  and the two rows below the fold are reasoned rather than seen.
- **S5 — dec. 10 removes a seed and leans on an invariant instead.** "A blank condition leaves
  `condition_target` mirroring the aim" now has to hold on every path that writes either field,
  where before the `If` press papered over any path that broke it. Three writers maintain it
  (`_clear_condition`, the `To` apply, `_seed_aim`) and the never-pressed default arm is what
  guards it, but a fourth writer added later would fail quietly rather than be corrected.
