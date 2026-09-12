# ADR-0182 — An aperture OPENS at the normal cadence and CLOSES at the fast one

**Status:** Accepted · **Date:** 2026-08-19 · **Supersedes:** nothing
**Amended by:** ADR-0097 — the `fast: bool` spec field below generalizes into a NAMED CURVE
declared per verb and owned by its beat, and the house rule stated here becomes what the
authored token `DEFAULT` resolves to. The decision recorded here (opens normal, closes fast)
is unchanged; only its expression moves.
**Relates to:** ADR-0084 (invariant 1, leave = the beat reversed), ADR-0088 (beat params
are spec fields), ADR-0068 (tunable homes)

## Context

`UI3BoxOpenBeat` drives the FFT center-out scissor from `BoxOpenAnimator`'s ROM-decoded
easing table (`world_menu_open_curve` `0x801533B8`, percent of full size). The table has
two cadences: **normal** walks one index per frame (~9 frames) and **fast** steps by two
(~5 frames), selected in the ROM by the global flag `DAT_8015326C == 2`.

Until now the port exposed one per-element spec field, `fast_open`, that chose the cadence
for the OPEN, and derived the close as `reverse_frames(settle) = settle + 1` — the same
curve, the same length, played backwards. Closes were therefore always exactly as long as
their opens.

**The ROM does not settle this question, because the ROM does not animate closes at all:**

- `DAT_8015326C` is read by exactly two functions — `world_menu_window_open_scale`
  `@0x800ec9a0` and `world_menu_element_open_scale` `@0x800ec7d0` — and these are the only
  two readers of the curve. Both are OPENS. There is no close-side counterpart.
- The one close anyone has observed is instant. The Learn press is two vsyncs
  (LEARN_PICKER.md §4): beat 1 runs `FUN_8012AAF4(0xf)` to tear the 0xf panel down, and
  beat 2 — the very next vsync, captured as ss1 — already shows the picker opening. A
  multi-frame close cannot fit in one vsync.
- The picker's own cancel decompiles to a mode set plus a substate flip
  (`FUN_80126374(0)`, `bacc = 2`, `bae3 = 0`, return −1; LEARN_PICKER.md §10) — no stage
  counter, no curve read.

So the port's animated close is already an invention: it exists because ADR-0084
invariant 1 makes leave the entry beat reversed. Its *speed* was never a ROM fact either,
and "as long as the open" is simply the least considered of the available choices.

## Decision

**The cadence is a property of the DIRECTION, globally. An aperture OPEN walks the normal
curve; an aperture CLOSE walks the fast one.** This is a deliberate divergence from the
ROM, taken on feel: a box that shuts faster than it opened reads as responsive, and a
symmetric close reads as sluggish.

The two per-element knobs that would have encoded this (`fast_open` plus a hypothetical
`fast_close`) collapse into **one** spec field, `fast` — "this element walks the doubled-step
curve" — applied to whichever direction is playing. The curve is one curve; the element
should not have to name a direction to pick a speed.

The global rule lives on the beat, in ADR-0068 shape:

```gdscript
# UI3BoxOpenBeat
static var OPEN_FAST := false
static var CLOSE_FAST := true
```

Effective cadence is `global-for-this-direction OR element.spec().fast`. A per-element
`fast` therefore *escalates* — it can make an open fast, it can never make a close slow.

`UI3Beat.reverse_frames` gains the element's `spec` alongside the forward `settle`, mirroring
`settle_frame(spec)`, because a beat may now run its close on a different cadence than its
open. The default implementation is unchanged (`settle + 1`), so every other beat keeps the
symmetric derivation.

## Consequences

- **Ownership is unchanged and worth restating:** the cadence is read off the element's OWN
  criteria spec by the beat. It is not supplied by the orchestrator (`UI3TransitionEngine`
  owns only the clock — accumulator, tick, catch-up) and it is not inherited from a parent
  element. In practice the *window* element carries it and its payload rides the aperture,
  since only a `clip = OWN_APERTURE` element plays BOX_OPEN at all.
- Every box-open close in the game gets ~1.8× faster: detail screen, START menu, equip /
  ability / job pickers, change-job plate.
- **Anything that recomputes an aperture clock off `settle_frame()` must ask for the
  direction it is in.** `JobPickerMenu` drives the detail vitals band off its own aperture
  counter and had to be taught this (`_ap_cadence_fast()`); asking the open's settle during
  a close strands the band mid-ramp when the shorter walk runs out of frames.
- **A close is now materially shorter than the open, which widens the window in which a
  re-open lands on a still-closing element.** Handles that null at close-start (the
  `_close_equip_picker` pattern) must ensure the abandoned element's `closed` handler cannot
  undo what its replacement has just done. `FormationDetailTransition._restore_after_job_picker`
  gates on nobody owning the screen for exactly this reason.
- Measured live on the job picker (aperture widths per driven beat frame):
  - OPEN, 8 driven frames: `20, 20, 121, 121, 182, 182, 192, 192, 203`
  - CLOSE, 5 driven frames: `203, 192, 182, 121, 20, 0`

## Alternatives rejected

- **Keep closes symmetric (status quo).** Faithful to nothing — the ROM has no close
  animation to be faithful to — and the least responsive of the options.
- **Make closes instant, matching the ROM.** This is the genuinely faithful option, and it
  is what the code did before the close was wired up at all. Rejected on feel: the user
  asked for a visible close, having judged the instant one wrong.
- **Add `fast_close` beside `fast_open`.** Two knobs for one curve, and it makes the common
  case (every close is fast) something each element must remember to opt into.
