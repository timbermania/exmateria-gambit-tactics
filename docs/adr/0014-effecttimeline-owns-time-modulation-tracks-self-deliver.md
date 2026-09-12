# EffectTimeline owns time-modulation outright; subsystems self-deliver their output (amends ADR-0012)

## Status

Accepted (2026-06-03)

Amends [ADR-0012](0012-effecttimeline-capstone.md): supersedes its **coupling #1**
("split it — particle computes `time_scale_factor`, timeline applies") and its
**"`EffectInstance` wires every output"** rule. Preserves ADR-0012's
output-agnostic-timeline stance and the no-clock invariant unchanged.

Verified 2026-08-28 — dec. 1–3 built (`src/effects/EffectTimeline.gd`,
`ScreenSubsystem.gd`, `PaletteSubsystem.gd`, `EffectInstance._process`). Dec. 1's
*derivation* is stated below as it shipped — a phase-local cursor, not the
subtraction this ADR first named — and three stale symbol claims are corrected;
see `AUDIT.tsv` and `audit-notes/0014.md`.

## Context (before this decision)

ADR-0012 made `EffectTimeline` own the clock, the phase, and time-modulation, and
pump an opaque ordered subsystem list. Two of its implementing-pass resolutions
left `EffectInstance` and the particle subsystem doing work the capstone's own
logic says belongs elsewhere:

1. **Time-modulation was only half-relocated.** Coupling #1 kept the *computation*
   of `time_scale_factor` in the particle subsystem
   (`EmitterManager._update_time_scale_for_frame`) and had `EffectTimeline.tick()`
   reach **back into it**: `var factor = _particle.time_scale_factor`. The stated
   justification was *"it has the controllers"* — the pacing curve was indexed by
   `phase1_controller.current_frame` / `timeline_controller.current_frame`. But the
   capstone is *what* relocated the clock: post-capstone the timeline owns
   `effect_frame` and the phase boundaries, and the cursors the curve is indexed by
   are derivable from them. So the clock owner reaching into a subsystem for a
   global clock quantity is a residual coupling, not a necessity. It also left a gap
   with ADR-0011's stated intent that the timeline owns *"the frame clock, the phase
   state, **and time modulation**."*

2. **Color output was couriered by `EffectInstance`, alone among the subsystems.**
   Sound self-delivered (key-on inside `advance()`), camera self-delivered (the
   `PlayerCamera` pulls its pose), particle self-rendered. Only **screen** and
   **palette** had their output read back out by concrete type in
   `EffectInstance._process` and pushed to
   `ScreenEffectOverlay`/`MapTintOverlay`/`UnitTintOverlay`. The overlays are
   owner-keyed retained sinks that recomposite *on write*, so that per-render-frame
   push re-asserted an unchanged value between ticks.

## Decision

**1. `EffectTimeline` owns time-modulation outright — computes *and* applies.**
The pacing curve (`effect_data.time_scale`, loaded from `time_scale.json`) and the
`_update_time_scale_for_frame` logic move from the particle subsystem to
`EffectTimeline` (where the method is `_update_time_scale`). The timeline computes
the factor from state **it already owns**: the open-phase set (for
`phase1_finished`) and two **phase-local cursors**, `_p1_local_frame` and
`_for_each_local_frame`. Each cursor steps once per frame its phase is open, and
steps *inside* the frame step so the factor reads the stepped value — which is what
the pre-capstone particle phase-controllers' `current_frame` supplied. (Deriving
the for-each cursor as a bare `effect_frame − phase1_duration` instead, as this ADR
first proposed, lands one frame off that faithful order.) The
`_particle.time_scale_factor` reach-back is **deleted**; the particle subsystem
sheds its last clock role. The one-frame lag is preserved (factor computed in the
frame step, applied to the next accumulation), as is the
`_phase1_was_finished_last_frame` "reset to base on the phase-1→for-each edge"
transition, now timeline state.

The for-each cursor is deliberately **B-shaped**: today, single-target, it counts
frames since `phase1_duration`. Under the ROM-faithful multi-target model (op41
all-targets + op40 per-target — issue #26) it becomes the per-target **for-each
pass cursor**, computed per pass by the timeline, which owns the eventual target
loop. So this move is the first brick of that model, not throwaway, and it removes
the time-mod dependency on particle-subsystem cursors the ROM model would otherwise
have to untangle.

**2. Every subsystem self-delivers its output; `EffectInstance` is not an output
courier.** The screen and palette subsystems hold their own overlay autoload
references and push **inside their own `advance()`** — `ColorSubsystem.advance`
calls `_deliver_output()`, which `ScreenSubsystem` overrides to reach
`ScreenEffectOverlay.update_layer_gradient` and `PaletteSubsystem` overrides to
reach `MapTintOverlay.update_stack` / `UnitTintOverlay.update_stack` — exactly as
sound fires its key-on and camera
exposes its pose for `PlayerCamera` to pull. The reach-in block in
`EffectInstance._process` is deleted. Screen/palette **absorb the push directly**
rather than taking a `SoundSubsystem`-style adapter: the adapter exists only
because the sound controller is the untouchable released addon;
screen/palette/camera/particle are godot-learning's own and are registered directly
in the subsystem list.

This **does not** change ADR-0012's output-agnostic timeline: the timeline still
never learns what a subsystem produces. It changes only *who performs the I/O* —
the producing subsystem, not `EffectInstance`. Outputs stay type-specific and never
cross the `Subsystem` interface.

**3. `EffectTimeline` is the single source of truth for phase-boundary state.**
`EffectTimeline.phase1_finished()` and `phase2_started()` are the only readers of
the boundary; no subsystem mirrors them locally. `ParticleSubsystem` reads through
the timeline via property getters rather than carrying its own flags.

### Cadence note

Moving the screen/palette push from `EffectInstance._process` (render cadence) into
`advance()` (fixed 30 Hz frame cadence) is behavior-equivalent: the overlays retain
their owner-keyed layer until `remove_layer`/`clear` and recomposite on write, so
re-asserting an unchanged held value every render frame was redundant. The held
value only changes on a tick; pushing on the tick reflects it the same logic frame.
This drops the redundant per-render-frame recomposite.

## Considered options

- **Leave coupling #1's split as-is** (particle computes, timeline applies).
  Rejected: the justification (*"it has the controllers"*) is a pre-capstone
  artifact — the timeline now owns the clock and phases the curve is indexed by, so
  the split has the clock owner reaching into a subsystem for a global clock
  quantity. Completing the relocation matches ADR-0011's stated intent and de-risks
  the ROM multi-target model.
- **A uniform `apply()` / output hook on the `Subsystem` interface, pumped by the
  timeline.** Rejected: it would make the timeline drive output, re-fusing the pump
  with I/O — the exact fusion ADR-0012 rejected ("`EffectTimeline` knows outputs —
  rejected"). It is also false uniformity: output is heterogeneous (sound =
  event/key-on, camera = pulled pose, screen/palette = pushed material uniforms), so
  one verb across all five registered subsystems invents a shape the system doesn't
  have.
- **Wrap screen/palette in `SoundSubsystem`-style adapters.** Rejected: the adapter
  is warranted only for the released addon's untouchable controller. Screen/palette
  are owned here and registered directly, so absorbing the push into the subsystem
  is the whole job and keeps the direct-registration pattern uniform.
- **Keep the render-cadence push for screen/palette** (move only the reach-in to a
  generic loop). Rejected: it keeps `EffectInstance` as output dispatcher for two
  subsystems and adds an interface method the other three don't need, for a push
  that is redundant between ticks anyway.

## Vocabulary: "track" is retired as a runtime word

The two follow-on renames (#30, #31) finished the cleanup these decisions implied.
The runtime hierarchy is **Subsystem → Phase block → Channel → Keyframe**:

- The pump registers **five** subsystem objects over four kinds — particle, sound,
  screen, palette, camera (color splits into screen and palette). The duck-typed
  contract is `advance(frame, phase)` / `reset()` / `is_done()`
  (`src/effects/Subsystem.gd`). It is **documented, not enforced, and satisfied
  entirely duck-style**: no file extends `Subsystem` — `ParticleSubsystem`,
  `CameraSubsystem`, `SoundSubsystem` and `ColorSubsystem` are all `RefCounted`, and
  `PaletteSubsystem` / `ScreenSubsystem` extend `ColorSubsystem` by path per the
  ADR-0004 cache-safety pattern. (`Subsystem.gd`'s own docstring still describes an
  inheritance split that does not exist — issue #675.)
- One phase's worth of cursor + channel state is a `PhaseBlock`;
  `ParticleSubsystem` holds `phase1_block` / `for_each_block` / `phase2_block`.
- Data classes are `CameraData` / `PaletteData` / `ScreenData`, their inner
  containers are `class Channel` (`channel_name`, held per phase in
  `channels_by_context`), and `EffectData`'s fields are `camera` / `palette`
  / `screen` / `sound`, parsed from `camera.json` / `palette.json` / `screen.json` /
  `sound.json` (the static texture palette is `texture_palette.json`).
  `tools/parse_effect.py` deletes the pre-rename `*_tracks.json` outputs on reparse
  (`STALE_OUTPUTS`), so the asset tree cannot carry both spellings.
- "Track" survives only on the data side: ROM `.BIN` filenames, and the FFT engine's
  own `track_enable` bitmask in the on-disc camera keyframe
  (`research/key_documents/STRUCTURE_DEFINITIONS.md`), which this codebase parses
  into `CameraData.Keyframe.flags`. It is also live and unrelated in the **audio**
  sense (one opcode stream — ADR-0006).

Each renamed file records its own pre-#31 name in its own docstring, so an old name
met in an old branch resolves without this ADR carrying the rename map.

## Consequences

- `EffectTimeline` owns frame + phase + time-modulation end-to-end and is still
  unit-testable with stub subsystems; time-modulation is exercised at the timeline
  with a stub pacing curve and no particle subsystem
  (`tests/EffectTimelineTest.gd`).
- `ParticleSubsystem` sheds `time_scale_data`, `_update_time_scale_for_frame`,
  `time_scale_factor` and `_phase1_was_finished_last_frame`. The
  `set_tracks(tracks, particle_track)` `particle_track` argument — whose only
  purpose was supplying `time_scale_factor` — is gone; registration is
  `set_subsystems(subsystems)`.
- `EffectInstance._process` loses the screen/palette reach-in block;
  `EffectInstance` is no longer a clock-param source or an output courier. It
  constructs subsystems, sets anchors before `tick()`, and owns the node lifecycle.
- `EffectInstance` subscribes **once per signal type** to `ParticleSubsystem`'s
  unified emitter surface (`emitter_started` / `emitter_stopped` /
  `action_flags_triggered`), which re-emits from its internal phase blocks — not
  nine subscriptions across three per-phase blocks.
- Screen/palette subsystems hold a reference to their overlay sink and push in
  `advance()`. That write moves to 30 Hz frame cadence (equivalent; drops the
  redundant per-render-frame recomposite).
- Behavior-preserving under steady framerate. Verify headful: CB91
  (`tests/CB91TimingTest.gd` — color + palette value sequence + the time-scale
  pacing of a slow effect), `tests/CameraSpinTest.gd`, and a sound-bearing effect —
  the same oracle set ADR-0012 used.
- **Does not** fix the multi-target fidelity bug (cast-scoped screen/camera still
  replay per `EffectInstance` because multi-target is still N instances). That is
  the ROM-faithful model of issue #26; this ADR is forward-compatible with it and is
  its first brick.
- Not part of `bootstrap_assets.sh` — hand-authored runtime code.
