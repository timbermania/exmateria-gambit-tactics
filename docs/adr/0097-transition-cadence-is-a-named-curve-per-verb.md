# ADR-0097 — A transition's cadence is a NAMED CURVE, declared per verb, owned by its beat

**Status:** Accepted — **Stage 1 implemented 2026-08-19** (see Staging). · **Date:** 2026-08-19
**Amends:** ADR-0182 (which this generalizes: its `fast: bool` becomes a named curve)
**Relates to:** ADR-0084 (beats/recipes; invariant 1), ADR-0088 (criteria are spec fields;
Amendment 2 §4 = the `place_at` WHERE verb), ADR-0068 (tunable homes)

## Context

ADR-0182 gave the box-open a per-direction cadence via a boolean spec field, `fast`. Three
things about that are wrong once you look past the immediate need.

**"Fast" is not a speed.** It is the ROM's own line — `if (DAT_8015326c == 2) param_3 <<= 1;`
— an index stride over the same easing table. Naming it a speed mislabels a sampling policy,
and it does not extend: a third cadence costs a second boolean.

**Cadence was attached to the element, not to the verb.** An element has up to three verbs
(`open()`, `close()`, `place_at()`) and they do not want the same cadence — that is the whole
content of ADR-0182.

**Only two of the three verbs can animate at all.** `place_at` — documented in `UI3Element`
as *"the WHERE verb, orchestrator-invoked like open()/close()"* — snaps. Where a move
genuinely needed to animate, it was hand-rolled beside the snapping verb:
`UnitInfoCluster` — *"`place_at()` snaps to a layout; `begin_slide()`/`set_slide_frame()`
walk…"*. That is exactly the state the box-open was in before ADR-0088 collapsed *"the three
copy-pasted per-class accumulators (DetailScene / StartActionMenu / EquipPickerMenu)"* into
one beat. Move is one refactor behind.

## Decision

**Three verbs, all owned by the element. Two beats. Cadence is a named curve, declared per
verb, validated by the beat that owns it.**

### 1. Cadence names a CURVE, not a speed

Each beat owns its own curve vocabulary and validates it, the same way `precondition()`
already lets a beat state a requirement it does not itself set. There is deliberately **no
global curve enum**: the units are not interchangeable — the aperture's curve is percent of a
derived rect, `VitalsSlideAnimator`'s is absolute pixels `[144,139,67,31,13,4,0]`,
`SpriteSlideAnimator`'s is parameterised positions. A flat vocabulary would let
`transition: SLIDE, curve: APERTURE_FAST` type-check and mean nothing.

### 2. Declared per VERB, and `DEFAULT` is a legal answer

An element with a beat must name a cadence for each verb that beat serves. Cadence joins
`id`/`rect`/`transition`/`frame`/`clip` in the explicit-required spec audit — **only when a
beat is declared**, so the 22 `NONE`/`RIDE_PARENT` elements are untouched.

`DEFAULT` is a first-class authored value meaning "use the house rule." This is the point: it
makes *"I considered this and chose the default"* and *"I never thought about this"* different
states in the source, without a warning anyone has to live with. Rejected explicitly: a
sentinel that resolves to a fixed cadence (e.g. always slow) — that silently reverts ADR-0182's
close rule for every un-migrated element, for exactly as long as the migration takes.

The house rule `DEFAULT` resolves to is ADR-0182's, unchanged: **opens normal, closes fast.**

### 3. "Immediate" is a curve, not a special case

The identity curve — already finished at frame 0. For the aperture that is `[100]`, and the
integer math is exact (`w·100/100 = w`; `x + w/2 − w·100/200 = x`). Note there is no universal
immediate constant: it is `[100]` for a percent curve, `[0]` for an offset curve, `settle` for
a position curve — which is itself an argument for §1, since only the beat knows its identity.

`UI3TransitionEngine.play()` must settle **synchronously** when the beat is already done at
frame 0. Otherwise `IMMEDIATE` costs one rendered frame at full size (`play()` drives frame 0
and returns; nothing tests "done" until `_step`), and the system has two instant-close
behaviours differing by a frame.

**Invariant, load-bearing:** an immediate close still emits `closed`. The teardown pattern
`p.closed.connect(p.queue_free, CONNECT_ONE_SHOT); p.play_close()` is standard in
`_close_equip_picker` and `_close_job_picker`; a close that skips the signal leaks the node
permanently.

### 4. The call site may override the cadence for one invocation

Same type as the authored value, so there is no second concept. This exists because the need
is situational, not a standing element property: when a whole screen unwinds, an open picker
should snap rather than play its private close over a screen that is sliding away — while △ on
that same picker still animates.

### 5. `place_at` gets a beat

A second, optional beat field. **Absent means snap**, which is what `place_at` does today, so
every existing caller is unchanged on day one and animating a move is opt-in.

Move needs **no reverse**: the reverse of `place_at("centre")` is `place_at("docked")`. It is
self-inverse by argument, not a polarity — which is why it is a second beat rather than a third
direction. `open`/`close` are one motion and its sign (ADR-0084 invariant 1, mechanised as
`reverse_drive(settle − n)` and a single `reversed: bool`); a move is a different motion with a
destination parameter.

**Ownership, restated because it is the reason this shape is right:** the element owns *how* it
opens, closes and moves. The orchestrator owns *what* and *where to* — it picks the destination
slug and the ordering. `FormationTransitionEngine` is not a rival owner of "move"; it is a
*sequencer* of moves (recipes, concurrent groups, barriers, role-selected targets).

## Staging

**Stage 1 — the vocabulary, in UI3 only.** §1–§5 above, across 8 authoring sites in 6 classes
(`JobPickerMenu:218`, `AbilityPickerMenu:127`, `EquipPickerMenu:270`, `StartActionMenu:375`,
`ChangeJobScreen:132`, `DetailScene:844/877/1557`), behind the existing guard set.

**Built** 2026-08-19, one commit per numbered section, guards extended with each:
`UI3BoxOpenBeat.Cadence` + the per-beat audit (`UI3TransitionEngine.cadence_errors`) · the
explicit-required per-verb cadences in `validate_spec` · `IMMEDIATE` + the synchronous settle
in `play()` · the call-site override on `open`/`close`/`place_at` and the widgets'
`play_open`/`play_close` · `UI3MoveSlideBeat` behind the new `move` criterion. Guard: cases
F–J of `UI3TransitionEngineTest`, plus the cadence cases in `UI3ElementSpecTest`.

Three things the build turned up that the design did not anticipate:

- **`settle_frame`/`reverse_frames` had to take the ELEMENT, not the spec.** Cadence must be
  read through `element.cadence_for()` for §4's override to reach the length hooks as well as
  `drive()`; a beat reading `spec()` for a cadence silently ignores overrides.
- **§3's "audit every `closed` handler" found a real defect,** not just handlers to clear.
  `_close_job_picker` nulled its handle *after* playing the close, so a synchronous `closed`
  hit `_restore_after_job_picker`'s abandoned-mid-close guard and left the screen torn down.
  Both pickers now drop the handle before the play.
- **§4's parameter broke a signature.** `UIModalWindow.close()` overrides `UI3Element.close()`
  (via UIWindow → UIComponent), so widening the base signature made it a compile error that
  cascaded through seven popup classes. The picker guards never load that hierarchy — a
  headful scene boot is what caught it, and is worth doing before calling a Stage done.

**Stage 2 — merge the two engines.** Deliberately separate, and not to be started inside
Stage 1. The two engines have independently converged (`drive(element, frame)` vs
`forward: Callable(frame)`; `reverse_frames(settle, spec)` vs `reverse_duration`; both have a
catch-up clamp and a boot-time reversibility audit). What UI3 lacks is Formation's *composition*
layer — recipes, concurrent groups, barriers, and role-selected targets chosen inside the driver
so element-flow stays gap-proof (ADR-0084 invariant 3). The beat layer is nearly free; the
recipe layer is the project.

**Stage 2's real justification is the clock, not tidiness.** `UI3Beat.tick()` is 1/60 and
`FormationTransitionEngine.TICK` is 2/60, and **both are correct** — they are two encodings of
the same ~30 Hz visual cadence. The aperture curve is pre-repeated
(`[10,10,60,60,90,90,95,95,100,…]`) and stepped every vsync; the §15.1 slide keyframes are not
pre-repeated and are stepped every other vsync. That ambiguity has already produced one shipped
bug — *"the port's open ran 2× too slow… ~18 vsync to settle against the ROM's ~9"* — which was
found and reverted. Unification therefore means **one clock at 1/60 (the real vsync), with each
curve declaring its own hold**, not "everything moves to 30." Then the two constants collapse
into data and that class of bug becomes unrepresentable.

## Consequences

- Adding a cadence costs an enum member on one beat, not a boolean on every element.
- Per-beat cadence validity is a **new audit surface**: a beat that forgets to validate lets
  nonsense authoring through silently. The audit should be part of Stage 1, not after it.
- `close()` becomes sometimes-synchronous (§3). The two known `queue_free`-on-`closed` handlers
  are safe because `queue_free` is deferred, but **every** `closed` handler needs auditing
  rather than assuming.
- `DEFAULT` is an AUTHORED value, so it mints a tunable slug like any other literal — ~8 more
  rows in the F3 tree, and per-element cadence becomes scrubbable.

## Open, deliberately not decided here

- ~~**Which enum fills the move slot.**~~ **Decided 2026-08-19: a separate `Move` enum.** One
  `Transition` enum in two slots would have given the dead `SLIDE` member a job, but it makes
  `transition: SLIDE` and `move: BOX_OPEN` both authorable and meaningless — catchable only by
  a runtime precondition, where two enums make each state unrepresentable. `Transition.SLIDE`
  stays dead; the animated move is `Move.SLIDE`.
- **Emulator re-verification of the pre-repeat finding.** It is documented in
  FORMATION_SCREEN.md but has not been re-checked against the save states, and Stage 2's
  justification rests on it. `pcsx-agent` plus `reference-assets/learn_picker_ss{0..4}.sstate`
  would close it.

## Alternatives rejected

- **Enumerate speeds (`fast`/`slow`/`immediate`).** Mislabels a table stride as a rate, and
  `immediate` is not a speed at all.
- **A global curve enum with the beat inferred or validated against it.** One flat vocabulary
  is a nicer authoring surface — one uniform "pick a curve" control in the F3 page — but the
  units are not interchangeable and it needs a per-beat validity matrix anyway.
- **`start`, `end`, `curve` as the universal shape.** It fits exactly one of the three existing
  animators. `BoxOpenAnimator`'s endpoints are derived, not authorable; `VitalsSlideAnimator`
  bakes its endpoints into the table in absolute pixels, and normalising them would trade exact
  ROM integers for floats against a byte-exactness guard. More fundamentally,
  `drive(element, frame)` is *more* general: start/end/curve assumes a lerp between two
  endpoints, and neither the centre-out scissor (with its matching UV inset) nor the Change-Job
  fling is one.
- **`move` as a third direction beside open/close.** Would make `reversed: bool` a tri-state and
  `reverse_drive` meaningless over a third of its domain.
- **Per-element per-direction explicit with no house rule.** Only 16 declarations, so cost is
  not the objection — drift is. A global rule makes "closes are fast" a property of the system;
  explicit-everywhere makes it a convention that holds while everyone remembers. `fast_open`
  being per-element is precisely why nobody had ever considered closes.
