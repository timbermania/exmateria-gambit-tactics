# The gambit row is a sentence read across the screen, and a screen that owns the pad re-means the action

[ADR-0255](0255-the-gambit-surface-is-three-levels-of-one-list-and-the-action-menu-dispatches-by-name.md)
built the first reachable gambit screen as a **drill-down**: `GambitSurface` is a
two-integer stack over one `GambitSurfaceMenu`, and you descend SLOT → PART → CHOICE,
one column at a time, to change one thing. It works, and its dec. 3 — *every choice is
a whole value built by a domain constructor, never a raw enum* — is the decision that
keeps the screen honest.

But a drill-down shows **one gambit's one part** at a time, and a gambit list is read
by comparing rows: slot order **is** priority (rule A1), so "what does this unit do
first, and when does it stop doing that" is a question about the *list*, not about a
slot. The player asked for the list back: one row per gambit, read across the screen,
with the parts side by side.

That ask collides with ADR-0255 dec. 3 on its face, and the collision is narrower than
it looks. Dec. 3 rejected **a five-dropdown form over a cross-product most of whose
cells are nonsense** — "Self, filtered to enemies, resolved by lowest stat" is
reachable and means nothing. That objection is to **raw enum fields**, not to width.
A row whose every cell offers whole domain-constructed values is a *sentence with its
parts visible*, and dec. 3's actual safeguard survives it untouched.

The second half of this ADR is input. The row has a horizontal axis and the shipped
surface has none — it routes exactly four actions (`ui_up`, `ui_down`, `ui_accept`,
`ui_cancel`) and `_refuse()`s the rest. Reaching for new bindings ran straight into
[ADR-0137](0137-the-formation-screen-re-hosts-over-the-map-as-a-camera-child-scene-entered-through-a-paused-camera-takeover.md)
Amendment 4's mechanized "one intent per button" table, and into Amendment 6's ruling
that □ **stays unbound**. Both are right about the hazard they were written for and
neither says what this screen needs, so the rule gets restated rather than dodged.

## Status

accepted, with **dec. 2 SUPERSEDED by
[ADR-0283](0283-the-gambit-rows-subject-is-its-own-column-and-the-slot-number-shares-a-lane-to-pay-for-it.md)**
— the condition's subject is a column again. Dec. 2's arithmetic priced a `When` holding a
full subject selector (widest `Most Critical Ally`, 68 px) and never credited the `If`
column's own saving; against a **two-word switch** the real overrun is 12 px, not 58, and
ADR-0283 dec. 5 finds them. Its rejected "two lines per gambit" fallback stays unused. Dec. 13
is NARROWED, not superseded: the slot number survives, sharing a lane with `Do`'s chevron.

Everything else here stands: dec. 1 (the row), dec. 3 (the `+N`), dec. 8 (the encoder gate),
dec. 9–12 and the pad re-meaning.

Supersedes [ADR-0255](0255-the-gambit-surface-is-three-levels-of-one-list-and-the-action-menu-dispatches-by-name.md)
**dec. 2 and dec. 4**, and corrects its `enabled` consequence. ADR-0255 dec. 3, dec. 5
and dec. 6–12 stand unchanged. Restates
[ADR-0137](0137-the-formation-screen-re-hosts-over-the-map-as-a-camera-child-scene-entered-through-a-paused-camera-takeover.md)
Amendment 4's rule; preserves its Amendment 6 verdict on □.

## Decision

1. **The surface is one row per gambit, read across: `Enable · Do · To · If`.**
   ADR-0255 dec. 2's three-levels-of-one-list is superseded, and so is dec. 4's "the
   part rows ARE the readout" — the *row* is the readout and the editor at once, which
   is the property dec. 4 was reaching for with a column. ←/→ walk the parts of the
   focused row, ○ opens that part's list, and the list opens **under its own column**
   as a formation box-open with the row still legible behind it. Every entry in every
   list is a whole `TargetSelector` / `GambitCondition` / action built by a domain
   constructor, so **ADR-0255 dec. 3 is preserved verbatim**: the nonsense
   cross-product is never reachable because it is never offered.

   The row window behind the list is left standing, but it is **not left focused**. It goes to
   the §15.21 BACKGROUND — the discrete foreground→background CLUT swap, frame and row glyphs and
   title together, never an alpha tint — and its glove is **removed**, so exactly one cursor is
   live on screen and it is the one the pad is reaching. `set_backgrounded` / `set_cursor_visible`
   on `GambitSurfaceMenu` are ports of `StartActionMenu`'s, which is the RE-grounded original and
   is what every other menu in this family already does. Legible is the requirement; focused is
   not, and two tan windows each bobbing a glove is a screen that names neither as the live one.
   The backgrounded twins are CLUT reads rather than colour choices: `LIT_INKS` is `0x7C3C`
   indices 1/2/3 and `DIM_INKS` the same clut's 5/6/7 — the glyph blitter's `bVar1 += shade * 4`
   shade-band shift — so each twin is `UIWindowPalettes.BG_FOR_7C3C` at the same index, which
   `GambitSurfaceTest` asserts rather than trusts.

   The row carries **three states in three channels**, and that is not decoration —
   collapsing any two of them loses one. `○` / `×` says ENABLED; the LIT/DIM shade band
   (the one `LearnAbilityMenu` already uses for live-vs-dim rows) says WHICH ROW, with
   the glove agreeing at its left edge; a `→` says WHICH PART. Marking the focused PART
   by shade instead was built first and photographed: a *disabled* row and an *unfocused*
   row then render identically, because "dim" is carrying both. Moving the glove itself
   to the focused column was built too, and it covers the column to its left. The three
   10-px chevron gaps are the whole cost, and dec. 8 is what pays for them.

   **The glove was re-tried on the current layout and photographed again** (2026-09-10), because
   the player asked for it and ADR-0244 says a marker is only decidable on a capture. The picture
   is worse than the prototype's record of it: the glove does not merely cover the column to its
   LEFT, it covers the column it NAMES. It hangs at `anchor − CURSOR_X_BIAS(12)` and is 13 px
   wide, so anchored on `Do` at x=40 it inks 28..41 and eats that row's own first glyph —
   `1 ⟨glove⟩--` against the chevron's `1 → ---`. Making it fit costs 4 px off `COL_DO_CAP` and 4
   off `COL_TO_CAP`, paid by the one column that already elides 17 of 265 ability names, to buy a
   marker worse than the 10-px one that sits in a gap which is otherwise empty. The answer is
   still the chevron, and now it has a second picture behind it.

   `Clear this slot` moves to the **head of the `Do` list**. It had no home left once
   the part level went, and emptying a slot IS choosing what it does — `GambitList`'s
   empty gambit is `Wait on Self / Always`. It is not a fifth part: a destructive verb
   reachable by ←/→ alone sits one press from the row the player is reading.

2. **`When` does not get a column, because the 256-px frame says so.** *(SUPERSEDED by
   [ADR-0283](0283-the-gambit-rows-subject-is-its-own-column-and-the-slot-number-shares-a-lane-to-pay-for-it.md)
   dec. 1–2 — it does get one, 20 px wide. What survives here is the MEASURE-THROUGH-THE-RENDERER
   rule below, which is the paragraph ADR-0283's own numbers are taken with, and the `If`
   column's dropped comparator spaces. What does NOT survive is the fold: binding every
   `Ally HP<X%` row to a MOST_CRITICAL subject encoded `TARGET_LOWEST_HP_ALLY`, which the
   kernel's Pass 2 answers `VERDICT_NOT_RETRYABLE` for — so the fold made "the nearest ally
   whose HP is below half" unsayable, and that cost is not priced anywhere below.)* The virtual
   screen is 256×240 (`FormationScene.SCREEN`) and the ROM font is proportional
   (lowercase ≈ 4 px, uppercase ≈ 6 px). **Measure through the RENDERER, never off the
   glyph table**: `assets/fonts/font_meta.json` records a SPACE as 10 px wide, and
   `UIUnitNameplate.glyph_advance` — the only advance any of this text is laid out with
   — returns `DialogueBox.SPACE_WIDTH_PX`, which is **4**. The first cut of this decision
   read the table and over-counted every string by 6 px per space: `"Most Critical Ally"`
   is 68 px and not 80, `"In Range melee"` 58 and not 70, `"Secret Fist"` 46 and not 52.

   Re-derived: the widest **Do** is an action-ability name at 60 px (`DragonPowerUp`;
   the median is 34 and 17 of 265 exceed the cap the row settles on), the widest
   **To** is 48 (`Weakest Ally`), and the widest **If** is **60** (`Self HP<25%`) —
   which is where `COL_IF_CAP` comes from. Every one of those is measured through
   `UIMenuText.measure`, the renderer's own advance, and not off the glyph table. A fourth `When` column would add 48 more plus
   a fourth 10-px cursor gap, against a window whose inner span is **220 px** — and the
   three parts plus their gaps plus the `+N` already spend 220 of it. So four columns do
   not fit, by roughly 58 px, and the conclusion is: the condition's *subject* folds
   into the condition's own named value.
   `If` reads `Ally HP<50%` rather than `When: Nearest Ally` plus `If: HP < 50%`. The
   subject vocabulary is **`Self` / `Ally` / `Foe`**, resolving MOST_CRITICAL for the
   "below" tests and NEAREST for the "above" one — a *healthy* foe has no critical
   member to pick out. Comparator spaces are dropped (`Self HP<25%` is 60 px against
   `Self HP < 25%`'s 68), and those 8 px are the difference between capping ability
   names at 52 px and at 48.

   This is arithmetic, not taste, and it happens to be the same simplification the
   player asked for. The ortho camera does span virtual x ≈ [−32, 288] behind a mask
   clipping to [0, 256]; the mask is deliberate and the 256 frame is the ROM's, so that
   slack is not available. Where the window itself sits is
   [ADR-0255 Amendment 1](0255-the-gambit-surface-is-three-levels-of-one-list-and-the-action-menu-dispatches-by-name.md)'s
   question, not this one's: it takes the ROM-pinned lower panel's own margins. What
   this decision owns is the 220-px inner span, which those margins leave unchanged.

3. **The screen edits condition index 0 and never destroys the rest.**
   `Gambit.conditions` stays `Array[GambitCondition]`, so rules **A3** and **D5** stay
   true and #895's mutation operators keep writing multi-condition gambits that never
   pass through here (ADR-0255 dec. 5). One condition per row is a property of the
   *authoring surface*, not of the domain. A slot carrying more than one condition
   renders a `+N` and **saving preserves indices 1+** — a screen that silently drops
   data the player cannot see is worse than a screen that cannot author it, and the cap
   is only defensible with the affordance attached. The mark is **right-aligned to the
   row's right edge**, not trailed after the `If` value: trailing it, it collides with a
   long condition and floats free of a short one, and both of those read as something
   other than "this row has more". Preserving the rest is one character of code and the
   whole of the promise — `conditions[0] = x`, never `conditions = [x]`.

4. **The enable flag is a PART of the row, not a button — and ADR-0255 was wrong that
   nothing reads it.** *(SUPERSEDED by dec. 13: the flag is no longer on the row at all. The
   half of this decision that still stands is the correction to ADR-0255 — `Gambit.enabled` IS
   read end to end, and it stays in the domain.)* ADR-0255's consequences say the flag is unexposed because
   *"nothing in the tree reads it, and a toggle for a field the kernel ignores would be
   a lie the player can press."* It is wired end to end: `Gambit.enabled` →
   `GambitEncoder.gd:223` → `GPUCombatPacker.gd:1014`'s schema row
   `{"key": "enabled", "field": GambitField.ENABLED}` → `stage_compute.glsl:37`
   `gambit_enabled()`, which `continue`s past a disabled slot at `:652` and `:668`.
   It is also **specified**: `docs/gambit-rules.md` rule **A2** — *"a disabled slot is
   skipped entirely (no condition eval, no target select)."* So the toggle is real
   behaviour for zero kernel work. It becomes the row's **leftmost part**: ←/→ reach
   it like any other, and ○ on it toggles instead of opening a list. That costs no
   button at all, which is what makes dec. 7 possible. The mark is FONT.BIN's own `○`
   and `×`. There is no baked checkbox cell and this screen is game-original, so a glyph
   is what it can honestly wear; `·` was tried and is invisible at 4 px on tan, reading
   as dirt on the window rather than as a state. An EMPTY slot is left alone by the
   toggle — disabling a rule the player has not written yet would render `× --- / --- /
   ---`, a disabled nothing.

5. **The rule is ONE ACTION PER BINDING, and a screen that owns the pad re-means the
   action.** ADR-0137 Amendment 4 states it as *"one intent per button"* and mechanizes
   it in `FormationMapHostTest._test_one_intent_per_button`. The guard is right and
   stays; the prose is a decision the tree has already outgrown. `ui_left`/`ui_right`
   carry **two genuinely different intents today** — walking the tile cursor on the map,
   and rotating the job ring on the Change-Job screen
   (`FormationDetailTransition.gd:1399`) — and the guard is green, because what it
   actually asserts is that no two *actions* share a binding. Amendment 4's hazard was
   never "a button means different things on different screens"; it was **a second
   action squatting a binding at the same depth, where the loser silently stops
   working** and a wrong key is indistinguishable from a broken feature. Re-meaning by
   an open screen that consumes the whole pad cannot produce that failure, because
   there is no loser: the screen is the only reader. So the gambit surface re-means
   actions it does not own, and adds no action to do it.

6. **L1/R1 join the camera rotate they already are on the PSX, and the surface re-means
   them as raise/lower slot.** `rotate_camera_cw` / `rotate_camera_ccw` are bound to
   Q/E and to **no pad button at all** — an omission, since L1/R1 rotate the camera on
   the real hardware. Pad 9/10 are added to those two existing actions. This is the
   **only** InputMap change in this decision: one action, one intent on the map, and no
   new row in Amendment 4's table to collide with. Inside the surface the same action
   raises and lowers the focused slot, which is a real verb because slot order **is**
   priority (rule A1) and the row number is therefore not decoration.

7. **□ stays unbound.** ADR-0137 Amendment 6 §2 decided that *"□ is the button with
   nothing to do, and it stays that way rather than being given a job to justify
   itself"*, after the player's verdict on Amendment 4's □/M menu key: *"M is crazy."*
   Dec. 4 made the enable toggle a part rather than a button precisely so that ruling did not
   have to be re-opened; dec. 13 retires the toggle outright, which leaves the ruling standing
   for the stronger reason that this screen now asks for no button at all.

8. **The option lists are DERIVED from encoder support, not hand-listed.** Rule **E1**
   (ADR-0023) says a gambit authored with an UNSUPPORTED feature — `ENEMY_IN_RANGE`
   condition, `SPECIFIC_UNITS` pool, `HIGHEST_STAT` resolution — is skipped at encode
   time: the slot goes null, `GambitEncoder` calls `push_error`, and evaluation falls
   through. A screen that *offers* such a choice is a screen that silently bricks the
   row the player just authored, and the row would read back correctly while doing
   nothing. Every choice this surface offers must round-trip through `GambitEncoder`
   without a skip, and that is a test that can be written before the screen exists.

   The rule cuts **both ways**, which is what dec. 11 is: a type leaves
   `UNSUPPORTED_CONDITION_TYPES` the moment the kernel can answer it, and the row it
   enables is then offered.

9. **The `Do` list is TWO deep: skillset, then ability.** `Do` reads `Attack · Move ·
   Wait`, then one row per skillset the unit can act out of, and the clear LAST
   (Amendment 3 — it read `--- (clear)` at the HEAD when this was written) — its primary
   job's, then its sub-job's. ○ on a skillset row lands **nothing**; it opens that
   skillset's ability names, in the ROM's own table order, under the same column.

   A flat list was the first shape and it does not scale: `AdjustmentTurn.usable_ability_ids`
   is the union of two skillsets, so a unit with a full primary and a full sub offers
   thirty-odd abilities in one id-sorted run under three verbs, five visible at a time, with
   no landmark in it. The ROM answers exactly this question with its own two-level action menu
   — *White Magic* → *Cure* — and a player who has opened that menu once already knows the
   shape.

   It **partitions** rather than filters, and that is checkable rather than hoped for:
   `usable_ability_ids` is *built* as the union of the primary's and the sub's `actions`, so no
   usable ability can fall outside a skillset row and there is no "Other" bucket to keep
   honest. Three rows are dropped, each of which would otherwise open onto nothing — a job
   whose `skill_set_id` is 0 (24 of the ROM's 160), a skillset the two jobs share (deduped by
   id), and a skillset whose every action this unit cannot use.

   The ability list **REPLACES** the `Do` list; it does not stack on it. Both hang off the `Do`
   column and both rise from the row window's top edge (`choice_container_for`), so a second
   box would land exactly on the first — dec. 1's "under its own column" leaves room for one
   box per column and no more. What stays legible behind is the **row**, which is what dec. 1
   asked for. ✕ off the ability list returns to the `Do` list, one level for the one press that
   opened it.

   ABILITY is a **level**, not a flag on CHOICE. `GambitSurface.level()` is the seam this
   screen answers *where am I* with, for the guards and for `_on_cancelled` alike; a second
   list hiding inside CHOICE's answer would be a screen whose own report could not tell the
   player's two positions apart.

10. **No choice list wears a title.** The list opens under the very column whose part it
    edits, and that column is already the part's name — the row reads `○ Attack  Nearest Foe
    Always` with the list hanging off `Attack`. A title spends the window's whole 8-px top
    band restating what the player is looking at, and for the ability level the honest title
    would be the skillset just picked, whose result the column below is already showing.
    (`_title_for` used to fall through to a `PART_LABELS` lookup; that constant is gone with
    its only reader.) The ROW list keeps its `Gambit` title and the imperative keeps
    `Imperative` — those are windows with no column above them to name them.
    **[ADR-0255 Amendment 1 took the ROW list's title too](0255-the-gambit-surface-is-three-levels-of-one-list-and-the-action-menu-dispatches-by-name.md):**
    the adjustment-menu row that opens it already says "Gambit", so it had a *press*
    above it naming it even though it had no column. The imperative is the one level
    that still wears a title, and this decision's argument is why.

11. **The `If` list offers `Ally In Range` and `Foe In Range`, and the reach is the
    ACTION's own.** `GambitCondition.Type.TARGET_IN_RANGE` is NOT in
    `UNSUPPORTED_CONDITION_TYPES` — it is the one range type dec. 8 lets through.
    `ENEMY_IN_RANGE`, `ALLY_IN_RANGE` and `IN_RANGE_OF` stay declared and stay
    unreachable from this screen: the first two fold a POOL into the condition, which
    the row expresses with `condition_target` instead (dec. 2's folded subject), and
    the third names an ability by string with no id to encode.

    **The two rows differ in their SUBJECT and never in the range.** A row that named
    its own range would ask the player to restate what the `Do` column already says,
    and would be wrong the moment they changed `Do` — which is what `In Melee Range`
    and `In Spell Range` did before they were removed. The reach is read off the
    gambit's own action: an ability answers with its own `range` and, where it carries
    `vertical_tolerance` / `vertical_fixed`, its own vertical bound; `Attack` / `Move`
    / `Wait` carry no ability and answer with the **equipped weapon's** reach, the same
    fallback `get_effective_ability_range` already applies to an ability whose `range`
    is 0. So there is no `Do` for which the row means nothing, and the row never has to
    be re-picked when `Do` changes. `effect_area` does not enter — the ROM measures an
    AoE to its CENTRE tile.

    **`COND_IN_RANGE` (13) carries NO value word.** A range baked in at encode time
    would be a second answer to a question the action already answers, and a stale one:
    throw range is `speed / 2 + 1`, which moves with a Speed Break in the middle of the
    battle the gambit was encoded for.

    **ONE predicate, two callers.** `ability_in_reach` in `combat_combat.glslinc` is
    the range-and-vertical test; `start_spell` gates on it to choose between casting and
    repositioning, and `COND_IN_RANGE` asks it on the screen's behalf. A second copy of
    that arithmetic for the condition is exactly how an authoring surface and the kernel
    it authors for stop agreeing — and dec. 8's failure mode is what that produces, a
    row that reads back correctly and does nothing.

    **Line-of-sight is asked of an ATTACK and not of an ability, and that asymmetry is
    the ROM's.** `can_attack_target` already includes LOS because LOS is part of an
    attack's own gate. `start_spell` treats a projectile with range but no sight as
    *walk until you can see it*, not as out of range — so folding LOS into
    `ability_in_reach` would send that case down the reposition branch and change what
    the kernel does. **Each action's condition asks that action's own reach test**,
    which is the only rule under which the screen's answer and the kernel's cannot
    differ.

    **The condition stays a predicate over VALUES.** `evaluate_condition` is handed the
    slot's `action_type` / `action_id`; it does not fetch them. They are read once per
    slot in `check_gambit_conditions`, which keeps the gambit-buffer walk in one place —
    a condition that reached into the buffer for itself would be a second walk to keep
    in step with the first.

12. **The empty gambit is the DEFAULT-CONSTRUCTED one, and a verb landed on an empty slot
    brings its aim.** `Gambit.new().is_empty()` is true. It was not: `Gambit._init` set
    `action_target` to `triggering()` while `Gambit.is_empty` requires SELF, so the constructor
    could not build the object its own predicate describes — and `GambitList._create_empty_gambit`
    carried a SECOND, disagreeing definition of the same object to paper over it. Two definitions
    welded to one predicate is a pair nobody could correct one half of. There is one now, in the
    constructor, and `_create_empty_gambit` defers to it.

    `self_()` and not `triggering()` for that one field, because with `condition_target` also SELF
    the two spell one behaviour and only one of them says so. `triggering()` — "act on whoever the
    condition picked out" — is the right action target for a gambit whose condition HAS a subject,
    which is a property of a configured gambit and not of an empty slot.

    **`Attack` on an empty slot seeds `Nearest Foe`.** Landing a verb used to write `action_kind`
    and `ability_id` and nothing else, so a fresh slot's first press produced
    `Attack / Self / Always`: a rule that reads back correctly, encodes cleanly, and attacks the
    unit that owns it. The seeded aim is ADR-0048's safety net's own — the sentence this screen is
    already showing one row below, dim, as what the unit does anyway — and it is built from
    `GambitOptions.nearest_foe()`, the very value the `To` list's `Nearest Foe` row builds, so the
    column can NAME it. `_target_text` probes that catalogue and falls back to "Self" for anything
    it cannot name, so an aim built from a second literal would store correctly and render as the
    default it was meant to replace.

    **Only on an empty slot, and only for `Attack`**, and both halves of that restraint are the
    decision. A slot the player has already aimed is one they have decided about; re-aiming it
    because they changed the verb is the screen overruling them. And `Attack` is the one verb that
    is unconditionally offensive — `Move` and `Wait` mean Self, and whether `Cure` wants an ally
    pool while `Fire` wants a foe pool is a question about the ABILITY, which this screen has no
    classifier for. Guessing it would author an aim the player did not choose and cannot see is a
    guess, which is what ADR-0023's faithful-or-explicit rule forbids. That gate is
    **#1125**'s — gate the `To` list on the verb and the `If` subject, and make `If` two levels
    deep — which is also where dec. 2's fold gets revisited, and which #33 / #34 state from the
    kernel side.

    > 🔴 **SUPERSEDED, and TWO of the sentences above are FALSE.** See
    > [ADR-0276](0276-a-sensible-default-is-the-aim-the-rom-cannot-fault-and-the-preference-is-still-open.md)
    > dec. 11 and dec. 12.
    >
    > **"this screen has no classifier for it" — there is one, and it is ROM-grounded.** The
    > `dont_hit_caster` / `dont_hit_allies` / `dont_hit_enemies` triple is extracted per ability
    > (`AbilityView`), encoded to `ABFLAG_HIT_NO_*` (`GPUAbilityLoader`) and read by the kernel
    > (`hit_policy_allows`) — ADR-0049, landed long before this decision. It is a **hit policy**
    > and not an effect family: it answers *may this aim* and never *should it*, which is why the
    > restraint above was under-justified rather than wrong. `Self` is an illegal aim for
    > **186 of the 368** ability records, and `Self` is exactly what this decision left an
    > ABILITY slot pointing at.
    >
    > **"`Move` and `Wait` mean Self" — `Wait` does; `Move` does not.** MOVE inherits
    > `action_target` as its DESTINATION, so `Move / Self` means "walk to the tile I am standing
    > on": `execute_move_to_unit_gambit`'s adjacency check passes immediately, the slot COMMITS
    > and blocks every lower-priority slot, and the unit does not move. It is this ADR's own
    > dec. 8 failure mode — a row that reads back correctly and does nothing — reached through
    > the default instead of through an unsupported feature.
    >
    > ADR-0276 keeps the empty-slot restraint and keeps `Attack`'s explicit `Nearest Foe`. What
    > changes: every verb now seeds the HEAD of a `To` list gated by the hit policy, and a
    > CONFIGURED slot is re-aimed when a press makes its aim forbidden rather than merely
    > different.

13. **The leftmost column is the SLOT NUMBER, and the enable toggle is retired.** Supersedes
    dec. 4's part. The row reads `1 · Do · To · If`, counting 1-4, and the cursor does not stop
    there — a readout is not somewhere ←/→ can land, so there are **three** parts, not four.

    Slot order **is** priority (rule A1), which makes the number the one thing on the row that
    was true and unwritten: it names what dec. 6's L1/R1 change. The `○`/`×` it replaces was
    painting a state most rows do not have — an EMPTY slot rendered `○`, claiming four enabled
    rules where there were none, which is what every scenario-booted cast opens onto (#892).

    **`Gambit.enabled` stays in the domain and the kernel keeps honouring it.** It is wired end
    to end — `GambitEncoder` → `GPUCombatPacker` → `stage_compute.glsl`'s `gambit_enabled()`,
    which `continue`s past a disabled slot — and rule **A2** specifies it. Dec. 4 was right about
    that and this does not touch it; #895's mutation operators author the field without passing
    through this screen. What goes is the *toggle*: the off-switch a player reaches is `---`,
    which empties the row, and a slot that does nothing is better expressed as a slot with
    nothing in it than as a rule wearing a cross.

    **ADR-0137 Amendment 6's "□ stays unbound" is left in a stronger position, not a weaker
    one.** Dec. 4 rested that ruling on the toggle costing no button; retiring the toggle means
    there is no press to find a home for at all.

    **A digit is ~6 px where the `○` was 10**, which is where `Do`'s cap recovers the 2 px
    ADR-0255 Amendment 1's margin fix took: the number ends at x=28, `Do` starts at 40 with its
    12-px chevron gap intact, and `COL_DO_CAP` is 54 — wider than the 52 it shipped at.

    The safety net's cell stays BLANK (ADR-0270): it is not a slot, so it has no number, and a
    blank where 1-4 go reads as "not one of these".

## Considered options

**Four columns, `Do / To / When / If`.** Rejected on dec. 2's arithmetic: 306 px against
a 256-px frame, a 50-px overflow. The widest real strings are `"Secret Fist"` (52 px),
`"Most Critical Ally"` (80 px) and `"In Range melee"` (70 px); nothing about the option
vocabulary makes them narrower.

⚠️ **This entry is STALE TWICE OVER.** Its three widths are the glyph-table misread dec. 2's
own body corrects (52/80/70 are really 46/68/58 through `UIMenuText.measure`) — so it quotes
the numbers it exists downstream of. And the last sentence is wrong: **the option vocabulary
is exactly what made them narrower.** `When` holding a two-way switch is 20 px, not 80, and
[ADR-0283](0283-the-gambit-rows-subject-is-its-own-column-and-the-slot-number-shares-a-lane-to-pay-for-it.md)
builds the four columns this entry rejects. Left in place because the *reasoning* is the thing
worth reading: a rejection that prices one shape does not price every shape with the same
column count.

**Two lines per gambit, the second indented and shown only for the focused row**, so
`When` survives as its own part. Rejected for now — it costs the one-line-per-gambit
property that makes the list comparable at a glance, which is the whole reason for the
row shape. It is the fallback if playtesting says the folded condition subject is
genuinely ambiguous, and it is written down here so it does not have to be rediscovered.

*(Written down, reached for, and NOT NEEDED.
[ADR-0283](0283-the-gambit-rows-subject-is-its-own-column-and-the-slot-number-shares-a-lane-to-pay-for-it.md)
put `When` back as a one-line column, so this stays unused — and stays here, because it is
still the fallback if a fifth part is ever asked for.)*

**Tab and Shift+Tab as the column cycle**, which is what the ask literally named.
Rejected twice. Tab is **△**, triple-bound to `unit_inspect`, `formation_start_menu` and
`world_map_start_menu` — and by ADR-0255's own consequences it is *this surface's front
door*, so a navigation verb on it overloads the key that opens the screen. Separately,
`ui_focus_next` / `ui_focus_prev` are deliberately **empty** (Amendment 2 cleared them),
and `is_action_pressed(action, allow_echo = false, exact_match = false)` defaults to
`exact_match = false` — `InputEventKey::action_match` compares `get_modifiers_mask()`
only under `p_exact_match`, so **Shift+Tab matches a plain-Tab action**. Binding it would
have required threading `exact_match = true` through every Tab call site, to buy an axis
←/→ already provides.

**New actions on Q/E for the L1/R1 verbs.** Rejected: it reds
`_test_one_intent_per_button`, and Amendment 4 §4 records this exact mistake being made
once already — *"The first draft of this amendment put MENU on Q, which is already
`rotate_camera_cw`. While writing the decision that removes double-bindings."* Q/E are
genuinely free at runtime inside a menu, because `PlayerCamera._input` returns early on
`camera_mode != CURSOR`, but the guard is static over the `InputMap` and does not care.
Dec. 6 reaches the same keys through the action that already owns them.

**□ plus a fresh key for the enable toggle.** Rejected on dec. 7 — it re-opens a ruling
the player already made by name, and dec. 4 removes the need.

**Collapsing `Gambit.conditions` to a single `condition`** so the domain matches the
screen. Rejected on dec. 3: it makes rules A3 and D5 vacuous, requires
`docs/gambit-rules.md` edited and the gambit scenario suite re-run, and it bounds #895's
generator by what a screen chose to show. The array is not the problem; an editor that
destroys what it cannot display is.

**←/→ cycling a part's value in place, with no list at all.** Rejected as the primary
grammar: it is fewer presses for a two-value part and a slog for a twelve-entry target
list, and it removes the "read the whole set before choosing" property that makes whole
domain values legible. It stays available as a later shortcut on top of dec. 1 without
changing anything here.

**Mounting `LearnAbilityMenu` as dec. 9's ability picker.** An earlier instruction said to,
and that instruction predates this ADR: it was given while the surface was still ADR-0255's
full-window drill-down, where a full-screen two-panel picker fit the idiom. Dec. 1 made every
list a small box under its own column, and a near-full-screen window would cover the row the
choice is supposed to be read against. The rich Ref./MP/CT picker is a separate job.

**Re-hosting `UIGambitEditor.gd` / `UIGambitDisplay.gd`** now that the shape is wide
again. Rejected on ADR-0255 dec. 1, which is untouched by this: those are mouse-clicked
`UIClickableField` rows in a `UIModalWindow` whose only keybind is ESC, on a screen with
no `UIWindowHost`. The width was never the reason they were rejected — the input model
was, and that reason is unchanged. They stay compiled by `UICompileTest` and stay the
record of what the full sentence builder looked like, and their curated option lists are
still the right thing to mine.

## Consequences

**One InputMap change lands in the whole job**: pad 9/10 onto `rotate_camera_cw` /
`rotate_camera_ccw`. Everything else the surface needs, it re-means while it owns the
pad. `_test_one_intent_per_button`'s `_OWNED_ACTIONS` and its pinned binding literals
need updating for those two pad buttons, and nothing else.

**`FormationDetailTransition.gd:1354` grows two actions.** The gambit block forwards
exactly `["ui_up", "ui_down", "ui_accept", "ui_cancel"]` today; it becomes six with
`ui_left` / `ui_right`, plus the two rotate actions. The `_refuse()` fallthrough stays —
an open screen owns the whole pad, but a refusal is not silence.

**A binding invisible to the guard was found and is not fixed here.**
`PlayerCamera._input` tests `event.keycode == KEY_F` raw, toggling the camera angle
through no `InputMap` action at all, so `_test_one_intent_per_button` is structurally
blind to it and F reads as free to anyone who audits the action table. It cost nothing
here only because dec. 4 and dec. 7 removed the need for a spare key. Giving it an
action is a one-line change and its own ticket.

**Dec. 8's gate cost the screen two conditions on arrival, and paid for the part
cursor.** `In Melee Range` and `In Spell Range` are `GambitCondition.Type.TARGET_IN_RANGE`,
which is in `GambitEncoder.UNSUPPORTED_CONDITION_TYPES` — every slot authored with either
has been a null encode since the screen shipped, reading back correctly and never firing.
They are removed from `GambitOptions.conditions()`, which takes the widest `If` string
from 58 px to 48, which is what the three chevron gaps are spent on. They return when #32
bridges range→distance in the kernel, and `GambitEncoderTest`'s round-trip arm is what
makes that ordering enforceable rather than remembered.

**ADR-0255's `enabled` consequence is retired, and rule A2 is why.** Anything citing
that paragraph for "the kernel ignores `enabled`" is citing a claim the shader
contradicts at `stage_compute.glsl:652`.

**`docs/gambit-rules.md` gains a pointer, not a rule change.** A2, A3 and D5 are
untouched by dec. 3 — the note under D exists so a reader of D5 does not read the
one-condition row as a contradiction of it.

**The prototype answered its question and dec. 1 survived it.**
`tools/proto_gambit_row.gd` built one pad-driven row in the real frame, in the real font,
inside the real UI3 window, before any of `src/` moved. ←/→ between the parts with ○
opening the focused part's list under its own column reads, and the row stays legible
behind the open list. The three corrections above are what it found; the grammar is not
one of them.

**Dec. 1's list idiom covers a SECOND list under one column, and the two need distinct
`UI3Element` id namespaces** — `gambitsurface.choice` and `gambitsurface.ability`. Not
cosmetic: `queue_free()` defers to the end of the frame, so for the rest of the frame in which
one list replaces the other **both** are in the tree and both register their ids, and two
windows answering to one id is one element reading the other's stored rect. It renders as a
perfectly drawn frame with no text in it — photographed in `GambitSurfaceMenu`'s own
`id_prefix` doc, the first time this screen mounted two windows at once.

**`GambitSurfaceTest` arm 16 guards dec. 9, and asserts the partition AS a partition**: every
top-level `Do` row is the clear, a verb, or a drill. A list offering both shapes would pass
every "the drill works" assertion while still burying the abilities it duplicated. 122/0 →
146/0. `tools/capture_gambit_surface.gd --level=ability` captures the second box, because
whether it lands on the row it was opened from is not a predicate question — the same reason
dec. 1's three layout corrections came off captures.

**Dec. 2's `Do` cap is untouched by dec. 9.** The skillset names (`Yin Yang Magic` is the
longest) go in the choice list, which auto-sizes to its widest entry; nothing new is drawn in
the 52-px `Do` column of the row itself.

**Rule D6 in `docs/gambit-rules.md` carries four scenarios, in two PAIRS** — dec. 11's
answer has two halves and each has to be shown to move on its own: weapon reach in/out,
and ability vertical within/beyond. The vertical pair could not have been written under
the old condition, which encoded to `COND_DISTANCE_LESS`, a flat manhattan that never
reads a height — "beyond vertical" would have fired and been wrong while looking right.
Its partner is the positive control: without a scenario in which WaveFist DOES fire,
"slot 0 never fired" is equally well explained by WaveFist never being castable on that
map at all.

**There is no `E1/unsupported_target_in_range_skips_to_next_slot` scenario, and its
absence is dec. 11.** Its subject is drained — a scenario asserting that skip would be
asserting the defect. The other four E1 range scenarios stand, because their types are
still unsupported.

**What is NOT here.** §5's
imperative gambits (#1006) remain out of scope by ADR-0255's own rule, and seeding the
lists so the screen opens onto something is still #886's fog — on a scenario-booted cast
every slot still reads `---`, which `GambitSurfaceTest` asserts rather than assumes.

## Amendment 3 (2026-09-10) — the clear reads `---` and it trails the list

*Restates one string in dec. 9 and moves one row. Dec. 9's SHAPE — the `Do` list is
two deep, skillset then ability — is untouched.*

Dec. 9 wrote the `Do` list as `--- (clear) · Attack · Move · Wait`, then the
skillsets. The parenthetical is gone: **the entry reads `---`.**

The row a clear produces reads `--- / --- / ---`, so the list entry that produces it
should read as that row and not as a sentence *about* that row. Every other entry in
this list is the literal text that will appear in the column — `Attack` puts `Attack`
in the `Do` cell — and `--- (clear)` was the one entry that named its own effect
instead.

**The parenthetical was doing a second job, so the row moved rather than simply
losing it.** `(clear)` was the only warning on screen that this entry is
destructive, and dec. 9 put it at the HEAD of the list — which is where the cursor
already rests the instant the list opens, one ○ from emptying the row the player was
reading. It is now the LAST entry. A destructive verb the player has to walk past
every verb and every skillset to reach needs no parenthetical; the position is the
warning, and it is a stronger one than a word was.

**What does not change.** It is still in the `Do` list rather than a part of its own
(emptying a slot IS choosing what it does), it is still NAMED rather than reachable
only by setting three parts back one at a time, and `order_choices_for` still omits
it entirely — an imperative occupies no slot, so a clear offered there would empty
whichever slot the cursor last touched. `GambitSurfaceTest` asserts it by NAME on
both paths, which is the only channel that can see a row moving from one end of a
list to the other.
