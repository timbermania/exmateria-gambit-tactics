# Effect replay is deterministic within an instance via a per-instance seeded RNG

**Status:** accepted (implemented, TDD; on-screen verified 2026-07-13).
**Enables:** frame-exact scrubbing in the [Effect Studio](0069-effect-studio-is-a-standalone-development-window-not-a-debug-panel.md).

## Context

The Effect Studio scrubs playback: dragging the playhead seeks the live
`EffectInstance` to an arbitrary frame. The score is a pure projection of
keyframe data and is already deterministic, but the *rendered* effect is not.
`EffectTimeline.reset()` zeroes the clock and every subsystem, and seeking
backward is implemented as `reset()` + re-pump to frame N — yet
`ParticleSubsystem`, `ActiveEmitter`, `ParticlePhysics`, and `CameraSubsystem`
draw their spread directions, spawn offsets, and camera shake from the **global
`randf()`**. So each replay re-rolls the cloud: dragging the playhead back and
forth would make particles and shake *shimmer*, which breaks the audio-editor
feel the tool is built around.

## Decision

### Decision 1 — each `EffectInstance` carries its own seeded RNG, re-seeded on `reset()`

Each `EffectInstance` carries its **own `RandomNumberGenerator`**, seeded once
at spawn (from a fresh random seed) and **re-seeded to that same value on
`reset()`**.

### Decision 2 — every stochastic draw in the effect sim routes through the instance RNG

Every stochastic draw in the effect sim
(`ParticleSubsystem`/`ActiveEmitter`/`ParticlePhysics`/`CameraSubsystem`) routes
through the instance RNG instead of the global one.

### Decision 3 — seek-to-N is a fixed-frame pump, never wall-clock `tick(delta)`

Seek-to-N pumps the clock
**exactly N fixed frames** (a dedicated seek pump, not wall-clock `tick(delta)`,
so the accumulator's one-frame time-modulation lag can't drift the result).

The consequence is the intended split:

- **Within one instance**, replay is bit-for-bit identical — scrubbing back and
  forth reproduces the exact same frame-N picture.
- **Across casts**, gameplay still varies — every new `EffectInstance` gets a
  fresh seed, so the same spell looks different cast-to-cast as before.

## Considered options

- **Accept the shimmer** (replay with global `randf()`) — rejected: emitters,
  colors, and phase would be correct at frame N but the fine cloud would re-roll
  on every backward scrub; the tool would feel broken for close study.
- **Forward-only seek** (never reset; only pump forward) — rejected: it dodges
  the determinism problem but kills "drag anywhere," which is the whole point.
- **A single fixed global seed for all effects** — rejected: it makes scrubbing
  stable but also makes every gameplay cast identical, removing the per-cast
  variety the global RNG currently provides.

## Consequences

- Randomness sourcing changes across the effect runtime, not just in the Studio:
  the instance RNG must be threaded through the previously-static particle/camera
  helpers. This is the reversal cost that makes it worth an ADR.
- Effects become reproducible for testing generally, not only for scrubbing — a
  seed can be pinned in a test to assert exact particle state.
- The no-clock invariant (`CONTEXT.md` → effect orchestration) is unaffected: the
  RNG is instance state, not a clock; subsystems still own no time.

## Implementation notes (2026-07-13)

- **Ownership + threading.** `EffectInstance` creates one
  `RandomNumberGenerator`, `randomize()`s it at `initialize()`, and captures the
  resulting seed. It sets `manager.rng` (before `ParticleSubsystem.initialize()`,
  which forwards it to `ParticlePhysics`) and `camera_controller.rng`, and
  registers `(rng, seed)` with the timeline via `EffectTimeline.set_rng()`.
- **Re-seed lives in `EffectTimeline.reset()`**, not `EffectInstance.reset()` —
  because a backward seek calls `timeline.reset()` directly, so that is the one
  choke point every restart funnels through. `reset()` re-applies the stored seed
  before resetting the subsystems.
- **Seek is a frame pump, not wall-clock.** The per-frame body of `tick()` was
  extracted to `EffectTimeline._advance_one_frame()`; `seek(target)` forward-pumps
  the delta (or `reset()`+re-pumps from 0 when going backward). `tick(delta)` and
  `seek()` therefore share one frame-quantum, so seek(N) reproduces exactly what N
  ticks produce. `EffectInstance.seek()` / `set_paused()` expose it; the Studio
  parks the preview (`playback_paused`) and moves it only via seek.
- **RNG routing.** The stochastic `ParticlePhysics` statics
  (`random_cone_direction` / `interpolate_range` / `interpolate_vec3_range`) took
  an optional trailing `rng` param (null → global fallback, preserving the trap
  callback path); `ParticlePhysics.rand()/rand_range()` and
  `CameraSubsystem._rr()` carry the same fallback for the direct draws.
- **Scope boundary:** trap effects and the trail-projectile callback still draw
  from the global RNG — they are not on the Studio-scrubbed particle path.
- **Guards:** `EffectSeekTest` (seek pump + reset re-seed, pure stub tracks) and
  `EffectRngDeterminismTest` (physics helpers, a real full particle cloud, camera
  shake, and a back-and-forth **scrub** reproducing the exact frame-N cloud).
  On-screen: `tools/StudioPreviewProbe.tscn` (scrub back-and-forth = pixel-identical).

## Amendment 1 (2026-08-28) — all three decisions hold in code, both guards survive, and the one witness that is gone was never tracked in git

*Audited against the tree at `docs/adr-consolidation`. The Decision paragraph
was split into three `### Decision N` subsections in the same pass — every word
preserved, only the sentence boundaries promoted — so `ADR-0070 dec. N`
citations resolve. The paragraph held three separately citable rules and was
unciteable as one block.*

### What is current, per decision

| Dec. | Rule as written | Holds? | What the tree says |
| --- | --- | --- | --- |
| 1 | Per-instance RNG, seeded at spawn, **re-seeded to the same value on `reset()`** | **holds**, at the choke point the ADR names | `EffectInstance.gd:250` `_rng.randomize()`; `:375` `effect_timeline.set_rng(_rng, _rng_seed)`. `EffectTimeline.reset()` (`:227-233`) re-applies `_rng.seed = _rng_seed` **first**, before the subsystem resets, and its docstring cites ADR-0070 for why. |
| 2 | Every stochastic draw in the sim routes through the instance RNG | **holds**, with the documented fallback | `EffectInstance.gd:266` sets `manager.rng` *before* initialize (the ordering the ADR calls out), `ParticleSubsystem.gd:111` forwards it to physics, `:335` sets `camera_controller.rng`. `ParticlePhysics.rand()` / `rand_range()` / the static `_srange(a, b, rng)` all read `rng.randf*()` with a `null → global` fallback (`ParticlePhysics.gd:18-38`), and `CameraSubsystem.gd:112` carries the same shape. |
| 3 | Seek-to-N pumps exactly N fixed frames, never wall-clock | **holds**, and the shared quantum is real | `EffectTimeline._advance_one_frame()` (`:102`) is the single frame body; `tick(delta)` (`:85`) calls it from the accumulator loop and `seek(target)` (`:132`) calls it directly — backward seeks `reset()` then re-pump from 0. The docstring on `seek()` names the exact failure the ADR reasoned about: "NEVER wall-clock `tick(delta)` — the accumulator's one-frame time-mod lag would drift the landing frame." |

The Implementation-notes section is accurate line for line, including the parts
easiest to get wrong: the re-seed does live in `EffectTimeline.reset()` rather
than `EffectInstance.reset()`, `manager.rng` is assigned before
`ParticleSubsystem.initialize()`, and `EffectInstance.set_paused()` (`:779`) +
`playback_paused` (`:70`) are the parking mechanism described.

### The scope boundary is still accurate, and the one draw it does not name is inert

"Trap effects and the trail-projectile callback still draw from the global RNG"
is true: `TrapEffect.gd:605-686`, `TrapChargeLineEffect.gd:112/249/270`, and
`TrailProjectileCallback.gd:108` are the global-RNG sites in the effect runtime.

One global draw exists that the boundary does not name —
`ColorSubsystem._setup_channels()` does `owner_id = randi()`
(`ColorSubsystem.gd:86`). It is not a shimmer source and does not need routing:
`owner_id` is an identity token used only as a dictionary key into
`MapTintOverlay.active_layers` / `active_illum`, its value never reaches a
pixel, and it is assigned from `initialize()` rather than `reset()` — so a
backward seek does not re-roll it. Recorded so the next audit does not re-open
it.

### Two verbs and one consumer the ADR does not mention

- **`EffectTimeline.rescrub()`** — reset + re-pump back to the *current* frame,
  so an authoring edit to a folded channel (camera framing) shows without
  moving the playhead. `seek(effect_frame)` is a no-op that folds nothing, so
  this is a distinct verb. It is dec. 3's mechanism serving ADR-0069's authoring
  interface, which did not exist when this ADR was written.
- **`EffectInstance.seek_silent()`** (`:739`) — the same pump without the
  side-effects, used by the Studio's backward loop
  (`EffectStudioPage.gd:4026-4027`).
- **`EffectEndModel.derived_end_frame()`** discharges the Consequence "effects
  become reproducible for testing generally, not only for scrubbing." It builds
  a throwaway `ParticleSubsystem` + `EffectTimeline`, sets `mgr.rng` and
  `tl.set_rng(rng, seed_value)` — the comment reads "so the harness re-seeds
  identically to the live cast" — and single-steps until the cast settles. Its
  default `MARKER_SEED = 0` is deliberately *not* a per-cast seed, and that does
  not conflict with "across casts, gameplay still varies": the number is drawn
  as the end marker on the Studio's score timeline
  (`EffectScoreTimeline.gd:404`, `EffectStudioPage.gd:7374`), an authoring
  display value, never gameplay.

### The on-screen witness in the Status line no longer exists

Status claims "on-screen verified 2026-07-13" and the guards list ends with
"`tools/StudioPreviewProbe.tscn` (scrub back-and-forth = pixel-identical)".
`StudioPreviewProbe` has **zero files in the tree**, and `git log --all` over
the path finds no add and no delete: it was **never tracked**, so it was a local
scratch scene at the time of writing rather than a casualty of ADR-0069's rehost
(corrected 2026-08-28 while folding ADR-0069, whose own Amendment 1 made the same
claim). The on-screen check is not reproducible as written; the two automated
guards it also names both survive: `tests/EffectSeekTest.gd` and
`tests/EffectRngDeterminismTest.gd`.

Verdict recorded as **complete** on that basis: every decision is built as
specified, the invariant is guarded by the tests the ADR names, and the only
stale reference is a deleted probe belonging to a neighbouring ADR.

### On mechanizing this ADR

Already mechanized, and well: `EffectRngDeterminismTest` asserts the physics
helpers, a full particle cloud, camera shake, and a back-and-forth scrub
reproducing the exact frame-N cloud — that is dec. 1 and dec. 2 end to end —
while `EffectSeekTest` covers the seek pump and the reset re-seed for dec. 3.

The one arm not covered is dec. 2's *completeness*: nothing stops a new
stochastic draw in the sim from reaching for the global `randf()`. A grep-shaped
guard is possible — no bare `randf()` / `randf_range()` / `randi()` in
`src/effects/`, with an allowlist for the four documented boundary files
(`TrapEffect`, `TrapChargeLineEffect`, `TrailProjectileCallback`, and
`ColorSubsystem`'s `owner_id`) — and it would be the arm that keeps the scope
boundary above honest as the runtime grows. Its cost is the allowlist, which is
the same burn-down shape `check_par_shaders.py` already carries.
