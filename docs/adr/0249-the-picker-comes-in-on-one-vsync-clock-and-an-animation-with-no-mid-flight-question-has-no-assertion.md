# The picker comes in on one vsync clock, and an animation with no mid-flight question has no assertion

ADR-0247 built the deployment picker and, with it, the subtractive **dim** that
pushes the battlefield back so the roster grid reads over it. It landed the dim
and stopped there: the dim **snapped** on at its authored strength and the grid
**appeared** in its cells. The user had asked for both halves in one sentence —
*"we would need to darken the background with some kind of subtractive mesh to
darken it so it moves into the foreground. it would look cleaner than fading to
the formation screen — especially if the units slide in from the side."* This
file is the other half (#941 follow-up).

The interesting part is not the ramp. It is that **neither half changes any value
the picker's rig could read at rest**: an animation that never runs and one that
completes instantly end in the same place. `GambitDeploymentPickerTest` was 45/45
before this work and would have stayed 45/45 with the fade and the slide
implemented, half-implemented, or reverted. That is the same shape of hole
ADR-0247 already fell into twice — `has_roster_grid()` and `has_pick_dim()` both
exist because a seeded defect PASSED — and it is the reason this ADR is about
observables at least as much as about motion.

## Status

accepted

## Decision

1. **The dim's fade and the units' slide are ONE gesture on ONE vsync clock**
   (`FormationPickIn`), not two animations that happen to start together. The user
   asked for one thing seen from two sides: the background receding *is* the cast
   arriving. Two independent accumulators drift apart under a frame stall and
   leave the grid docked over an un-dimmed map, which is the single frame the
   gesture exists to remove.

2. **It is counted in vsyncs, never tweened on `delta`.** ADR-0161's rule, quoted
   in `FormationScreenIn`: *"a delta-driven tween would run the ramp at the
   display's rate and finish the open in a third of the time on a 144 Hz panel."*
   Not hypothetical here — the map host runs **uncapped** (~1,100 fps measured,
   which is why the picker's rig budgets its waits in frames rather than menu
   ticks), so a delta tween would finish this gesture in roughly one frame and be
   indistinguishable from the snap it replaces. `FormationPickIn.advance(delta)`
   carries the vsync debt itself, exactly as `FormationScreenIn.advance` does.

3. **Every value is a PURE function of the tick** — `dim_fraction_at(tick)`,
   `slide_frame_at(tick, row)`, `total_ticks(rows)`. This is `FormationScreenIn.value_at`'s
   shape and `WorldMapTownPage.set_open_frame`'s, and it is what lets a rig assert
   the ramp's **shape** without a screen: that it starts at nothing, that it passes
   *through* intermediate values, that it steps every `STEP_TICKS` vsyncs and not
   every frame. A screenshot cannot answer any of those.

4. **The lengths are borrowed from measurements, and the borrow is named.**
   `DIM_TICKS = 30` is `FormationScreenIn.RAMP_TICKS`, i.e. `WorldMapTownPage.OPEN_VSYNCS`
   (`@0x801533B8`, §38.7) — measured, for a `WORLD.BIN`-era screen element coming
   up. `STEP_TICKS = 2` is the quantisation three console tables agree on **and**
   this screen's own slide rate (`FormationDetailTransition._EQUIP_TICK` is
   `2.0/60.0`). Nothing in the repo has observed FFT's own deployment picker
   opening; these are analogies, but to measurements and to the right category,
   which is the bar `FormationScreenIn` set for the same borrow. **Replacement
   condition:** capture the picker opening on the console and log its per-vsync
   descriptors; two integers here change and nothing else does.

5. **The units enter from the RIGHT, decelerating, staggered by ROW.** Each choice
   reuses a number this tree already has a reason for:
   - *Right* is `FormationScene.EQUIP_EXIT_X` — the one off-screen X with a
     measurement behind it (§15.23: clut 14741 ramped 186→248 and exited past the
     right edge). Entering from the side the Equip slide exits to makes the
     arrival that measured run backwards.
   - *Decelerating* is `SpriteSlideAnimator.position_at_frame` read at
     `dur - frame`, the same time-reversal `play_equip_unslide` uses. §15.24's
     "undo the slide" already settled that the natural inverse of an accelerating
     exit is a decelerating arrival; an accelerating entry slams the grid into place.
   - *By row* because the ROW is the unit of motion this screen already splits on
     (`begin_changejob_slide` sends the top row one way and the bottom row the
     other — a FIXED row split, RE29), and because a per-cell cascade across a
     4-wide row reads as a ripple rather than a slide.

6. **The picker slide carries its OWN latch, unlike the Change-Job slide.**
   `begin_changejob_slide` deliberately reuses the `_equip_*` dicts; this does not.
   Those dicts are live property of the Item→Equip / Change-Job transition, and ○
   on a picker cell still opens a Status overlay through the roster's own path — a
   picker holding the Equip latches would have two gestures writing one set of
   starts. The **body-holder carry** is copied verbatim, though: bodies are
   detached scene-ROOT siblings of their anchors, so moving an anchor alone slides
   the orb and the shadow and leaves the unit standing where it was (the bug
   `aa65e2952` fixed for the Equip slide, re-seeded here and caught).

7. **An animation gets a MID-FLIGHT question, not a rest-state one.** Four new
   observables, and each exists because nothing else in the picker's behaviour
   changes without it: `pick_animating()`, `pick_in_ticks()`,
   `pick_dim_strength()` (which reads the pushed uniform BACK off the material,
   so a ramp that computes correctly and pushes nowhere fails), and
   `FormationScene.pick_sliding()` / `pick_slide_offset_px()` (which reads the
   **body** holder, so an anchor-only slide fails). The rig then catches the
   gesture between `begin_pick` and its landing rather than only asserting where
   it ends up.

8. **`FormationPickIn` is not a `UI3Beat` and not an ADR-0084 recipe.** ADR-0161
   §5's reason, unchanged: a beat must declare a forward AND a reverse driver or
   the boot-time audit refuses to start, and this gesture has no reverse —
   `end_pick` frees the dim outright (ADR-0162: a screen-covering quad is freed,
   never parked at strength 0). The pick also lives at `State.IDLE` and is not a
   coordinator `State` at all. It is stepped from `FormationMapHost._process`,
   beside `_advance_hover`.

## Rejected

**Tweening on `delta`, or on a `Tween`.** The whole of decision 2. On this host
it is not a fidelity argument, it is a functional one: at ~1,100 fps the gesture
would be over before the second frame and the ticket would ship unfixed while
appearing fixed.

**Reusing `FormationScreenIn` for the dim.** Same shape, opposite direction:
that ramp starts at a black cover and clears to reveal a screen; this one starts
at an undimmed battlefield and darkens it. It is also a `Node` that builds and
frees its own NDC overlay quad, and the pick's dim quad is a `UIVitalsBand`
already built and owned by the host. Sharing would have meant a rewrite wearing
a shared name — the same trade `FormationScreenIn` itself rejected for
`WorldMapScreenIn`.

**Reusing the `_equip_*` latches (decision 6).** Cheaper by one pair of
dictionaries, and it is what `begin_changejob_slide` does; but the Change-Job
slide and the Equip slide are two phases of one transition that cannot be open at
once, while the picker and the Status→Equip route CAN overlap.

**Keeping a snap-home in `end_pick_slide`.** It was written, and a seeded defect
that deleted it reddened **nothing**. At the landing tick `slide_frame_at` returns
`SLIDE_DURATION`, `play_pick_slide` reads `position_at_frame` at
`dur - SLIDE_DURATION == 0`, and frame 0 is documented to return `start` exactly —
the last eased sample already IS the authored origin. Code with no observable
consequence is the same defect as an assertion with no observable behind it, read
from the other end, so it is gone. What survives is the **ordering**: the landing
push must run before the latch is dropped, and swapping the two reds exactly one
arm (`4 want 7` — the three staggered row-1 units left one sample short).

**A per-cell (row-major) cascade instead of a per-row stagger.** Considered and
not taken for the reason in decision 5; it is a two-integer change if the user
prefers it on screen.

**Ramping the dim back down on `end_pick`.** That is the reverse driver decision 8
says this gesture does not have. `end_pick` is a teardown — the grid, the band,
the cluster and the camera all go at once — and holding a screen-covering quad
alive to fade it is ADR-0162's bug with a nicer motivation.

## Consequences

`GambitDeploymentPickerTest` is **70 assertions**, up from 45. Seven seeded
defects were run against it and six reddened only their own arms: discarding the
returned `ShaderMaterial` (the original defect — 2 arms), an instant
`dim_fraction_at` (4), dropping the `STEP_TICKS` quantisation (1), never calling
`begin_pick_slide` (3), an anchor-only slide with the bodies left docked (1), and
`ROW_STAGGER_TICKS = 0` (1). The seventh found dead code instead of a missing
assertion, and is written up under Rejected.

**`UIVitalsBand.build` returns its `ShaderMaterial` for exactly this** — its own
docstring says *"so the caller can keep pushing per-frame uniforms"* — and
ADR-0247's `_raise_pick_dim` discarded it. That is the entire mechanism behind
"the dim snaps": there was nothing left to push to. The quad is now built at
`full_sub: 0.0` and ramped up from there, so no frame ever shows the authored
strength before the ramp starts.

**`formation.map.pick_dim` is still an unscrubbed guess.** It defaults to 0.35
against the roster stripe's oracle 0.47, and ADR-0247 flagged it as a number no
agent has seen on screen. The fade does not settle it — it now ramps *to* the same
unscrubbed value. ADR-0068 keeps it a `static var` in the production owner with
the F3 panel as a pure view, so scrubbing it live is still the way to settle it.

**The gesture's two halves do not finish together, on purpose.** The dim lands at
tick 30 and the last row docks at 36, so the stage darkens and then the cast
finishes arriving on it. `total_ticks()` is the max of the two, and the host stops
pushing the moment it is reached — a finished ramp that kept writing `full_sub`
every frame would be a per-frame uniform push for a value that cannot change.

**The picker's rig now takes measurably longer**, because arm 8 waits for a real
0.77 s gesture twice through and `_wait_until` counts frames. It is still inside
`MAX_WAIT_FRAMES` by an order of magnitude on an uncapped host; on a vsync-capped
one the margin is ~250×.

**A visual change still needs the user's eyes.** No rig in this tree can judge
whether the fade reads well or whether the slide comes from the right side. The
constants in decision 5 are named and adjacent so that answer is a two-line edit.
