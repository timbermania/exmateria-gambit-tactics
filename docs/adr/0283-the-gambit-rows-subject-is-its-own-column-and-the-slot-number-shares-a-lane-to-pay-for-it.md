# The gambit row's SUBJECT is its own column, and the slot number shares a lane to pay for it

[#1125](https://github.com/timbermania/fft-monorepo/issues/1125) (c) asked for the
`If` column to be **two levels deep** — subject, then test — reusing ADR-0268
dec. 9's `drill` for "zero row budget". The player then specified a different
shape in conversation, and it is the shape this ADR builds: **four columns**,
`Action · Target · Subject · Condition`, with the subject a **two-way switch**
rather than a pool selector.

Their three worked examples, verbatim, are the acceptance set:

```
1. Heal      myself          when my hp    < 90%
2. Heal      nearest ally    when their hp < 50%
3. Attack    nearest enemy   —            —
```

Status: accepted (2026-09-11). **Supersedes
[ADR-0268](0268-the-gambit-row-is-a-sentence-read-across-the-screen-and-a-screen-that-owns-the-pad-re-means-the-action.md)
dec. 2** (the fold) and its "four columns / two lines per gambit" rejected
options; narrows dec. 13 (the slot number survives, in a shared lane); reads
dec. 1 for the row, dec. 3 for the `+N`, dec. 8 for the encoder gate and
[ADR-0244](0244-a-turn-queue-entry-is-a-turn-and-not-a-unit.md) for why the
gap width was photographed instead of computed. Re-derives the readout
[ADR-0270](0270-the-safety-net-is-the-last-row-on-the-gambit-surface-dim-and-inert.md)
**dec. 1** states. (The handoff that opened this work cited that string as "ADR-0273 dec. 4";
0273 is about the rules tier and carries no such decision. Checked before anything was
edited.)

## Context

**The fold did not merely hide the subject — it made a sentence the kernel can
run unsayable, and nothing recorded that.** This is the finding the whole change
turns on, and it was in no ADR and no ticket before this one.

`evaluate_gambits_up_to` (`src/gpu/shaders/stage_compute.glsl`) is **two-pass**.
Pass 1 tests each slot's condition against rank 0. Pass 2 then walks
`find_nth_nearest` at rank 1, 2, 3… **retesting the condition at each rank**, so
a slot whose nearest candidate fails can still fire on the second-nearest. It
does that for exactly three condition targets:

```glsl
if (target_type != TARGET_NEAREST_ENEMY && target_type != TARGET_NEAREST_ALLY
        && target_type != TARGET_NEAREST_ALLY_OR_KO) {
    write_verdict_pass2(global_unit_id, slot, VERDICT_NOT_RETRYABLE, 0, 0, 0);
    continue;
}
```

**Every folded `Ally HP<X%` row bound its subject to MOST_CRITICAL friendlies**
(`GambitOptions._weakest_ally`), which `GambitEncoder._target_selector_to_gpu`
maps to `TARGET_LOWEST_HP_ALLY` — one of the types that guard rejects. So the
screen's only ally-HP subject was the one that switches the rank walk **off**,
and *"the nearest ally whose HP is below half"* could not be authored from it.
The kernel has always been able to run that rule.

It is not an E1 skip, which is why no existing guard saw it: the folded subject
encodes perfectly cleanly. It is a legal encoding of the **wrong pool**, and the
row reads back correctly while the unit only ever tests the single most-hurt
ally on the map.

**dec. 2 rejected a fourth column, and it priced a different one.** Its
arithmetic was *"a fourth `When` column would add 48 more plus a fourth 10-px
cursor gap… four columns do not fit, by roughly 58 px"*. That `When` held a full
subject selector — widest string `Most Critical Ally`, 68 px. It also never
credited the saving on the other side: with the subject gone, the `If` column's
cap drops from 60 (`Self HP<25%`) to 40 (`HP<25%`). Re-derived against a **20-px**
switch, the real overrun is **12 px**, not 58 — and dec. 2's own
`Considered options` entry still quotes the 80-px and 70-px numbers that dec. 2's
body explicitly corrects as a glyph-table misread.

**The row has no slack at all, and that is what makes this a measurement
problem.** The row runs `22..240` and spent every one of those px before this
change. There is no reserve to spend and no place to borrow from that is not
itself load-bearing.

## Decision

1. **The row is `Slot · Do · To · Subject · If`, and `Subject` is a two-way
   switch — `My` / `Their`.**

   Two rows and deliberately not six. The ally/foe and nearest/weakest axes are
   **already on the screen**, one column to the left: `To` offers `Nearest Ally`
   / `Weakest Ally` / `Nearest Foe` / `Weakest Foe`, so "test the weakest ally"
   is `To = Weakest Ally` with `Subject = Their`. A full selector here would be
   two spellings of one axis, and it is the spelling dec. 2 correctly priced out.

   Expressiveness was checked before the pixels: the **13** folded
   `(subject, test)` rows collapse to **5 predicates + blank** — `HP<25%`,
   `HP<50%`, `HP>50%`, `MP<50%`, `In Range` — and nothing today becomes
   unsayable. `Ally In Range` and `Foe In Range` become one row, because the two
   differed only in their subject (dec. 11 already drained them of their ranges).

   🔴 **`Their` MIRRORS the `To` column — it has no pool of its own.** It builds
   a **copy** of the gambit's `action_target`, so
   `cond_target_type == action_target_type`, and that equality is the whole point
   of this ADR: `Nearest Ally` is in the kernel's retryable set, so `To = Nearest
   Ally` + `Subject = Their` + `HP<50%` is the rank walk, reached from the screen
   for the first time. The two fields agreeing is also what makes the retried
   rank the unit the slot **acts** on — Pass 2 passes its own `candidate` through
   as the final target.

   A copy and not a reference. A shared selector would make a later edit of `To`
   silently rewrite the subject of a condition the player is not looking at;
   `GambitSurface` re-derives it on the `To` press instead, which is a write the
   row can show. A `To` edit re-aims a **mirrored** subject and leaves `My`
   alone, because `My` names the actor and not the aim.

2. **`Always` leaves the screen's vocabulary. Blank is the ABSENCE of a
   condition, not a sixth one.**

   `check_gambit_conditions` loops `for c in 0..cond_count` and returns `true` at
   zero, so a zero-length `conditions` array already fires every time. A named
   `Always` row was a second spelling of that, and it was the spelling the column
   had to print in a slot whose entire job is to say what the rule **tests**.

   So `Gambit._init` writes `conditions = []`, the `If` list's head row writes
   the same, and `GambitCondition.Type.ALWAYS` **stays on the enum** — #895's
   mutation operators write it and every save from before this ADR carries it.
   `GambitOptions.condition_label` reads either spelling back as `—`.

   **`—` and not the empty string.** An empty column is a column the focus
   chevron points at nothing beside, and on an unconditional row that is two
   thirds of the sentence rendered as a gap the player cannot tell from a draw
   failure. It stays distinct from `---`, which is the **whole row** being empty:
   two marks, because they are two states.

3. **A blank condition leaves `condition_target` MIRRORING the aim — and the
   Subject column PRINTS it. The two columns do not blank together.**

   `cond_target_type` **gates the slot** whatever the conditions array holds:
   `evaluate_gambits_up_to` runs `select_target` on it and writes
   `VERDICT_NO_CANDIDATE` at `candidate < 0` **before** `check_gambit_conditions`
   is consulted at all — and that check returns `true` at zero conditions. So on
   a conditionless row the subject is not a spare field, it is the row's **only**
   gate.

   Cleared to `SELF` instead, `Attack / Nearest Foe / — / —` would gate on the
   *actor* existing, which is always true, and the row would fire at a pool it
   never checked was there. So blank **mirrors**, which is exactly what
   `GPUCombatTestBase.make_attack_gambit()` has always written.

   🔴 **AND BECAUSE IT MIRRORS, IT RENDERS.** This decision originally read
   *"subject and condition are blank together"* — `subject_label` returned `—`
   whenever `condition_label` did, on the grounds that a subject is who a
   *question* is about and printing `Their` over a row with no test *"would name
   a field the player cannot act on"*. Both halves of that were false, and the
   paragraph above is why the second one was: the field decides whether the row
   fires. The first was false too — `GambitSurface`'s `Part.SUBJ` offers the list
   on a conditionless row **deliberately**, because the subject is what makes a
   condition mean something and refusing it until a test is set is a part the
   player has to author out of order.

   Blanking it therefore hid a live switch, and the player reported the
   consequence twice: *"when I enter gambits left-to-right I can't choose 'my' or
   'their'"*, then *"I can't select 'my' or 'their' until AFTER I have selected a
   condition."* `a8e001303` fixed the **write** half (the `If` press called
   `_seed_subject` and overwrote the choice one column later) and left the
   **display** half standing, which is why the same complaint returned: the
   column was never unselectable, it was **mute**, and from the player's seat
   those are one symptom.

   ⚠️ **This changes worked example 3 in the acceptance set above**, which the
   player sketched as `Attack | nearest enemy | — | —`. It now reads `Attack |
   Nearest Foe | Their | —`. The sketch is kept as written because it is the
   player's, and it is overruled by the same player's later report: the sketch
   was made before the column existed to be pressed, and `Their` on that row is
   true — it names the pool the row is gated on, which is the one thing the
   sketch could not say.

   Landing a test on a row that had none therefore has to name a subject too: the
   surface seeds `Their` when the aim names somebody other than the actor and
   `My` when it does not, and one ○ on the column overrides it.

4. **The chevron gap is 13 px, because 11 was photographed and reads as a
   connector rather than a cursor.**

   The chevron mounts at `column_x - CHEVRON_W`, so what matters is the **blank
   pixels** between the preceding value's last ink and the arrow's first, which
   is `gap - 9`: FONT.BIN's `→` carries one empty column on its own left (ink
   pattern `.#########`, read off `font_atlas.tga`) and **every other glyph in
   this row inks its full advance** — `A`, `H`, `S`, `M` and `-` all ink 6 of 6,
   `y` inks 4 of 4, so two letters *inside a word* already touch.

   13 px gives 4 blank px, which is a word space (`DialogueBox.SPACE_WIDTH_PX`).
   11 gives 2, and at 2 the capture reads

   ```
   1 DragonPo⋯   Weakest Ally➡Their   HP<25%
   ```

   — an arrow **between** two values. That is a wrong meaning and not a tight
   fit, ADR-0244 is why it was looked at, and no layout assertion could have
   caught it.

5. **The slot NUMBER and `Do`'s chevron share one lane, and that is what pays
   for the fourth column.** (Narrows dec. 13; the number survives.)

   At 13-px gaps the row wants `6 + 4×13 + 50 + 48 + 20 + 40 + 12 = 228` px
   against 218. The 10 px is available nowhere else:

   | candidate | why not |
   |---|---|
   | `COL_DO_CAP` | the elision count is **not linear in the cap** — it has a cliff between 48 px and 46, where 25 of 228 action-ability names become **102** (`VerticalJump5` and every `* Magic` land in those 2 px). 50 is already 4 below dec. 13's 54. |
   | the window | ADR-0255 Amendment 1 pinned it to the ROM lower panel's own margins, matched **on ink** against the stats panel above; the 256-px mask is the ROM's. |
   | the `+N` | `+1` measures 12 px, and dec. 3 says the one-condition cap is only defensible with the affordance attached. |
   | starting further left | the glove's ink stops at **x=18** (measured on a capture, not derived from `CURSOR_X_BIAS`), and x=18 was tried and photographed with the glove's fingers over the `1`. |

   So both take the same 10 px at x=22. They can, because the number is a
   **per-row readout** and the chevron appears on exactly one part of exactly one
   row — the two are never wanted at the same x at the same time. The cost is the
   focused row's number while its `Do` is the focused part, which is the one row
   the glove is already resting on.

6. **`Gambit.is_empty()` is rewritten, and it is direction-tested both ways.**

   `GambitEncoder.authored_gambits` filters on this predicate **before**
   encoding, so it decides whether a slot reaches the GPU at all, and it fails
   two ways:

   * too **permissive** → a rule the player authored is dropped from the buffer.
     The row reads back correctly and the unit is not under it.
   * too **strict** → a blank slot encodes as a real rule and occupies a
     priority (rule A1), which the slots beneath it then never get.

   A gambit is empty when **four things are true at once**, each the absence of a
   decision: the verb is `WAIT`, the aim is the actor, the subject is the actor,
   and **nothing is tested** — where "nothing is tested" means no condition with
   a type other than `ALWAYS`, so both spellings of blank read as blank.

   ⚠️ **A condition is what saves a non-WAIT row, not what makes a row real.**
   `Attack / Nearest Foe / Their / —` is example 3 above, and a predicate rewritten
   as "blank conditions means blank slot" **deletes it**, silently, while the row
   keeps reading it back. It survives on `action_kind`, checked first and alone.
   That arm and its opposite (`Wait / Self / My / HP<50%` is **not** empty — it
   deliberately blocks the slots beneath it) are both asserted; a one-arm guard
   passes a predicate that answers `true` for everything.

7. **The safety net's row reads `Attack / Nearest Foe / Their / —`.** This
   corrects the string ADR-0270 dec. 1 states. It is not a literal either way:
   the row is read off `GambitEncoder.safety_net_gambit()`, whose one `ALWAYS`
   condition reads back as blank through the same label function every other row
   uses. Its `Their` and its `Foe` are the SAME field — both cells read
   `condition_target`, because the net's `action_target` is `triggering()` and
   names no pool — so the two can never drift into disagreeing about one
   selector. On this row above all, naming the gate is the point: being gated on
   a foe existing is what makes the net a net.

## Considered alternatives

**Two levels deep on `If` — subject, then test — reusing dec. 9's `drill`**, at
zero row budget. This is what #1125 (c) literally asked for and it would have
been cheaper. Rejected because the player specified the four-column shape
directly afterwards, and because the drill hides the subject in exactly the place
the ticket complains it is hidden: *"the row never says which foe."* A row that
reads `Heal / Nearest Ally / Their / HP<50%` answers that on the row; a drill
answers it one press in.

**Two lines per gambit, the second shown only for the focused row.** ADR-0268's
own recorded fallback, written down there so it would not have to be
rediscovered. Not needed: the row fits at 13-px gaps. It also costs the
one-line-per-gambit property that makes the list comparable at a glance, and a
focused row that grows to two lines shifts every row beneath it.

**Dropping the slot number outright** (−6 px). Tiled and **captured** — it works,
and with `Do` at cap 52 it lands at exactly 240 with 4 px of chevron clearance to
spare. Rejected because dec. 5 above gets the same px for free: the number and
the chevron are never simultaneously wanted. The capture also showed
`⟨glove⟩➡DragonPo⋯` — two right-pointing cursors adjacent — which is legible but
says less than `1 DragonPo⋯` does.

**Shortening the `To` vocabulary** to `Near Ally` / `Weak Ally` (−12 px, which
alone closes the gap). Rejected: it is a player-facing vocabulary change bought
for pixels, and ADR-0268 dec. 1 already chose these words.

**`Self` / `Them` as the subject words**, reusing the `To` column's own
vocabulary (16/20 px — no narrower than `My`/`Their` at 10/20). Rejected because
`Them` already means something else one column left — "the unit that triggered
this" — and the subject is a **possessive**: the row reads *"when **their** hp is
below half"*, which is not the same word as the pool called `Them`.

**A THIRD DISPLAY STATE for the subject while the condition is blank** — a dim
or parenthesised `(My)` — so the press gets feedback without the column
asserting a subject for a question that does not exist. The obvious compromise
between dec. 3's original blanking and the player's left-to-right report, and it
was the leading candidate before the kernel was read. Rejected on truth, not on
cost: dimming says *provisional, does not count yet* about a field that fully
counts — `select_target` on `cond_target_type` gates the slot before any
condition is consulted, so `My` versus `Their` on a conditionless row decides
whether the row fires at all. A softer lie is still a lie, and this screen has
ruled against readouts that lie about the rule the unit is under (dec. 8,
ADR-0270). It also prices a per-CELL dim state into the row widget, where
`inert` today is per-ROW.

**Reordering the columns so `If` precedes `Subject`**, which would make the
dependency match the entry order and need no display change at all. Rejected:
ADR-0268 dec. 1 makes the row a **sentence**, and `Do · To · Subject · If` is its
reading order — *"Heal / Nearest Ally / Their / HP<50%"*. Re-ordering to suit an
authoring dependency inverts that ADR's whole argument, and the dependency it
was working around is the one dec. 3 above removed.

**Widening the window to recover the 4 px of left pad and 2 px at the right.**
Half-taken: `PLUS_RIGHT_X` does move 238 → 240, which is the window's own right
ink column, and the capture shows the `+1` sitting 2 px clear of the border. The
left 4 px are **not** available — the glove is there.

## Consequences

* **`Do` elides 21 of 228 action-ability names** where it elided 14, and the
  full name is one ○ away in that part's own list. (The prose ADR-0268 dec. 2 and
  `GambitSurfaceMenu` carried — *"17 of 265"* — mixed two sets: 265 is the count
  of names in `assets/abilities/abilities.json`, and the screen renders the
  almanac's ROM spellings, of which **228** are reachable through a skillset.
  Both files now quote the 228.)
* **A CELL THAT ONLY THIS ADR'S SHAPE CAN REACH, found by re-reading and closed.**
  `Their` is a copy of the aim, so `To = Them` would make the subject `TRIGGERING`
  too — encoding `cond_target_type = TARGET_THEM`, which `select_target` answers
  `case TARGET_THEM: return -1;  // Set by caller`. Pass 1 then writes
  `VERDICT_NO_CANDIDATE` and skips the slot **every tick, forever**, while the row
  reads back perfectly. It encodes cleanly, so rule E1 cannot see it: the same
  shape as the fold's own defect, one column over.

  **The reachable outcome is HONEST, and that is why the `Them` row is kept rather
  than withheld.** Driven through the real applies:
  `Heal / Nearest Ally / Their / HP<50%` re-aimed to `Them` lands
  `Heal / Them / My / HP<50%` — the subject falls back to the ACTOR, the slot
  resolves (`Them` forwards to `condition_target`), and the row **says** `My`.
  #1125 opens by complaining that *"`Attack / Them / Always` names its pool nowhere
  at all"*; the fourth column is what names it. The cell grades `AIM_UNNAMED` — the
  `Self` row under another name — and not `AIM_NEVER_RESOLVES`.

  So `AIM_NEVER_RESOLVES` is a BELT for a state the first cut prevents, and its
  reachability is proved by mutation rather than assumed: with `mirror_of` allowed to
  copy a `TRIGGERING` aim, the guard reports `got=never_resolves want=unnamed` and
  three assertions red across two tests. A grade with no reachable input would be a
  register nobody reads.

  Cut in two places, because either alone leaves a route open.
  `GambitOptions.mirror_of` refuses to copy a `TRIGGERING` aim and falls back to the
  actor (so no path can build the pair — there are four mirroring sites), and
  `aim_verdict` grades the pair `AIM_NEVER_RESOLVES` so `targets_for` withholds the
  `Them` row. `Them` stays in `targets()` — the NAMING catalogue — because a save
  holding it must read back as itself rather than through `_target_text`'s `Self`
  fallback. The mirror-image grade `AIM_UNNAMED` (`Them` under `My`: resolves to the
  actor, says so badly) is kept distinct, because the two fail differently.

  `aim_class`'s docstring asserted the opposite — *"a subject is never itself
  TRIGGERING (no `conditions()` entry builds one), so there is no chain to walk and
  no cycle to guard against"* — true of the folded catalogue and false the moment
  `Their` became a copy.

* **The `(verb × aim)` audit walks 6,744 cells** where it walked 5,058, and the extra
  axis value is one the screen *cannot* produce: a raw `Them` subject. Carried on
  purpose — it is the only input that reaches `never_resolves`, and a grade that only
  ever reads zero is indistinguishable from a grade nothing examined. The census now
  prints every grade plus anything its list does not name, and asserts its rows sum
  to the cell count; `never_resolves` was counted-and-unprinted for exactly one run,
  and the only symptom was five rows that no longer summed.
* **The offered-choice round-trip is a four-axis product** —
  `(If × Subject + blank) × To × Do` — and it asserts its own cell count, because
  a miscounted product is a product with a hole in it.
* **`_part` is renumbered.** `Part.IF` moved 2 → 3 and `GambitSurfaceMenu`
  mirrors the enum rather than importing it, so the mirror equality that
  `GambitSurfaceTest` asserts is what keeps the chevron on the column it names.
* **Pre-ADR-0283 saves read as sentences, not as gaps.** `subject_label` reads
  the **pool** (SELF → `My`, anything else → `Their`) rather than probing a
  catalogue, so the MOST_CRITICAL subjects the fold wrote still name themselves.
  They keep their old, non-retryable behaviour until re-authored — this ADR does
  not migrate them, and #1125's own comment thread is where a migration would be
  argued.

## The word, and the three guards that had an opinion about it

The player-facing column is headed **`Subject`** — their word, and it stays. The
DOMAIN term is two words, **condition subject**, and that is not fussiness:
`check_context_index` refused the one-word entry because **`Subject` is already
defined**, in [port-vs-oracle diffing](../context/35-port-vs-oracle-diffing.md),
where it means *the unit + equipment shown on a screen* and *"the diff neutralizes
the subject by masking"*. Two domains, one word, and the repo's own vocabulary guard
is what said so. `docs/context/07-ability-hit-policy.md` — the entry that exists to
keep **target** from drifting — now carries the distinction from its side too.

The pre-flight also found two things this ADR got wrong on its way in, and both are
worth recording because neither is visible to a reader:

* **A link to an ADR filename that does not exist.** `ADR-0244` is the right ADR for
  *"a marker is only decidable on a capture"* — its own text calls a screenshot "the
  acceptance instrument" — but its filename is
  `0244-a-turn-queue-entry-is-a-turn-and-not-a-unit.md`, not the title the rule reads
  under. `check_adr_classification` catches a broken *link*; it cannot see the bare
  `ADR-0244` prose that ADR-0268 dec. 1 already carries.
* **A stale citation that a LINE WRAP had been hiding.** `docs/gambit-rules.md` cited
  *"ADR-0268 Amendment 2"* for D6's `In Range` rows, and ADR-0268 has no Amendment 2
  — dec. 11 is what brought them back drained. It sat on `main` unflagged because the
  citation spanned a line break, and reflowing the paragraph is what exposed it to
  `check_adr_anchors`.

⚠️ **The pre-flight exits at its FIRST red guard**, so each of these appeared only
once the one before it was fixed: four aborts in sequence, not one.

## Verification

* `GambitSurfaceTest` — **260 passed, 0 failed**. Carries the four-part walk, the
  `PART_SUBJ` mirror equality, the four choice lists each under its own column,
  the safety net's `— / —`, and dec. 6's both-arms `is_empty` block including the
  `authored_gambits` filter agreeing with the predicate — plus the two-press SEQUENCE
  above, driven by calling each part's own `apply` rather than by re-implementing it.
  Its order is the assertion: a build that asked `_subject_mirrors_aim` AFTER the
  write cannot tell a mirrored subject from an unmirrored one, because by then the old
  aim is gone.
* `GambitEncoderTest` — **PASS**, with two new arms. One asserts dec. 1's whole point:
  `To = Nearest Ally` + `Subject = Their` encodes a cond target in the kernel's
  retryable set, and `cond_target_type == action_target_type`. Its **negative
  control** is the fold's own subject, which still encodes cleanly and is still
  not retryable — so the defect was never a skip. The other asserts the circular
  `Them`/`Their` cell is unreachable, through **both** cuts, and that `Them` is still
  NAMEABLE while being unofferable.
* **Captures** (ADR-0244), via `tools/capture_gambit_surface.gd --worst`, which
  overwrites the visible rows with the widest string every column can hold. The
  11-px and 13-px gaps, the x=18 glove collision and the no-slot-number variant
  were each photographed and compared, and the arithmetic replica of
  `UIMenuText.measure` used to price them reproduces five independently recorded
  widths (60, 68, 48, 48, 58 px) before it was trusted for a new one.

## Soft spots

* **`+N` is still flush against a max-width condition.** `MP<50%` ends at 228 and
  the mark starts there, so a row carrying `conditions[1..]` renders `MP<50%+1`.
  That geometry is dec. 3's and is unchanged in kind — the folded `Self MP<50%`
  ended at 226 with the mark at 226 — but it is now reachable with a 6-character
  condition rather than an 11-character one.
* **`Their` over a `Self` aim is `My` under another name.** It encodes to SELF
  and is harmless. Left offered rather than gated, because a subject list that
  changed length with the aim is a list whose row indices move under the cursor —
  and unlike the `Them` pair above, this one resolves.
* **The 4-blank-px requirement is a reading of two captures, not a threshold.**
  2 px was judged wrong and 4 right; 3 was never photographed, because 13 px fit
  and there was nothing to buy with the third.
