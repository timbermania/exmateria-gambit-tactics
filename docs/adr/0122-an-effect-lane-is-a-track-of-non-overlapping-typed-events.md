# An effect lane is a track of non-overlapping typed events

`Effects` publishes a **fixed list of lanes**. A lane is a track of events that
do not overlap; two verbs that can be active at the same time get separate lanes.
Each event declares its own **extent** (span or trigger) and its own **payload
kind** (typed or opaque) — the lane does not.

Status: accepted (2026-08-20).

## Context

[ADR-0117](0117-the-blueprints-ten-systems.md) dec. 4 keeps `Effect System` as a
single system on the grounds that `E###.BIN`'s shape is right *as a published
language*, and predicted six channels: `sound`, `camera`, `pose`, `screen`,
`palette`, `landmark`. That prediction came from the domain model and had never
been checked against `src/effects/`.

Checking it found six things.

**There is no `pose` channel.** Nothing in the runtime drives a unit's pose from
an effect. `CombatLoop._on_ability_react` picks the SEQ id from
`AbilityDatabase`; the effect supplies only the *moment*. The predicted channel
was a fabrication of the model.

**The six lanes do not share a crossing shape.** Particle output is Effects' own
drawables; colour crosses via a layer registry keyed by `owner_id`; camera
crosses by the consumer *pulling* `EffectInstance.camera_controller` every host
frame; only landmarks are event-shaped. The blueprint's own rule — *"events are
the expensive shape and should be rare"* — was being applied to a model that
assumed one shape for all six.

**Six separate storage slots each carry several unrelated things**, and in most
cases both the runtime below and the authoring above have already pulled them
apart by hand:

| slot | carries | already demuxed by |
|---|---|---|
| `action_flags` (u16) | bits 0-2 a **callback slot** (particle machinery, `0x801A40F0`), bits 4-6 three **landmarks** | two different code paths in `PhaseBlock` |
| `channel_mask` | angle, position and zoom in one camera keyframe | `CameraSubsystem`'s three independent states; `CameraLowering`'s three authoring lanes |
| `ctrl` bit 7 | *blend-vs-gradient* on screen, *enabled* on palette | `ScreenData` / `PaletteData`, the latter carrying a warning comment |
| keyframe slot 0 | not a keyframe — the origin of the first span | hardcoded as `0` at `PhaseBlock.initialize` |
| `time_value` (colour) | a x8 **multiplier**, *and* `0` as a **snap sentinel**, *and* `600` as an **end-of-time marker** | `duration_frames` is already derived at parse; the runtime never sees the x8 |
| `duration` (FRAME opcode) | a **60 Hz vblank countdown** (the ROM's `frame_timer` decrements by 2 per game frame), *and* `0` as a **terminal marker** | `ParticleAnimator` bakes `maxi(1, duration >> 1)` |

**Concurrency is already supported downstream and blocked upstream.**
`ColorStack` ([ADR-0067](0067-color-modes-are-one-model.md)) is an ordered list
of up to 8 layers with independent `start_frame`/`duration_frames`, re-derived
every frame. Nothing in the colour engine prevents a blend and a gradient running
together. The single-keyframe lane cursor does — a limitation of the ROM's
storage walk, not of the model it feeds.

**The lane caps are storage artifacts.** 25 keyframes per particle channel (24
usable — slot 24 is a phantom, byte `0x31` being shared with `emitter_id[0]`), 5
channels per context, 33 screen keyframes, 33 palette keyframes, 3 sound channels
per phase. All are consequences of fixed-size preallocated structs.

## Decision

**1. A lane is a track of non-overlapping events.** If two verbs can be active at
the same time, they are separate lanes. This is what decides lane count, not the
file layout.

**2. Events are typed; lanes are not.** Each event type declares its **extent** —
a *span* has a start and an end, a *trigger* is a moment — and its **payload
kind**: *typed* (the payload is subject-shaped, e.g. pitch/yaw/roll) or *opaque*
(a code whose meaning lives entirely in the subscriber). A lane may carry more
than one event type. Both axes are independent, and all four combinations occur.

**3. The lane list is fixed:**

| lane | events | extent · payload |
|---|---|---|
| `particle` | emitter span | span · typed |
| `camera.angle`, `camera.position`, `camera.zoom` | move | span · typed |
| `screen` | `gradient`, `blend` | span · typed |
| `palette.affected_units`, `palette.caster`, `palette.target` | tint | span · typed |
| `sound` | coded trigger | trigger · **opaque** |
| `landmark` | `reaction`, `hit` | span + trigger · **opaque** |

Camera becomes three lanes because angle, position and zoom are three
resources. Screen becomes two because `gradient` **sets** the backdrop absolutely
and `blend` **folds** over the baseline — they can run together, and their
composition order follows from the verbs (absolute establishes, relative
modifies) rather than from a tie-break. Palette is already three lanes for three
resources.

**4. Above the importer, every lane is a list of spans with phase-local absolute
`start`/`end`.** Below it, each lane keeps whatever the ROM stores — particle and
camera store an end, screen and palette store a duration. Cumulative and
incremental are the same model differing in which of the two is written down.

**5. Phase continuity is a declared lane property, not folklore.** `particle` and
`camera` are **phase-scoped** (`PhaseBlock`: *"no cross-phase continuity"*);
`screen` and `palette` are **phase-continuous** (`build_stream` folds one op
stream across seams, because the PSX colour engine has no phase concept).
Unifying the time model must not unify this.

**6. A duration field carries durations and nothing else.** Anything that is not
a length of time is a **property** of the event — resolved by the importer, never
a value a consumer has to recognise. The corpus packs a non-duration into a
duration field three separate ways:

| field | magic value | actually means | becomes |
|---|---|---|---|
| `time_value` (colour) | `0` | snap — change in one frame, not zero | `snap` |
| `time_value` (colour) | `600` | run past the end of the effect | `open_ended` |
| `duration` (FRAME opcode) | `0` | display one frame, then **stop the animation** | `terminal` |

`0` is the sharp case, because it means two different non-zero things in two
lanes and a literal zero in neither. **Above the importer, `0` frames is `0`
frames.**

The `600` marker is cross-format: **339 of 401 effects** have a particle max time
of exactly 600 (the rest cluster at 591-599), and the colour lanes reuse 600 as a
multiplier, giving a 4,800-frame ramp that never completes. `terminal` is heavily
used — **2,291 of 27,568 FRAME opcodes (8.3%)**. Note it is the odd one out: it
changes *control flow*, not timing, which is exactly why it does not belong in a
timing field.

**7. Durations publish in effect frames.** Both duration fields are stored in
something other than frames, and both conversions are inlined as bare arithmetic
rather than declared:

- **colour** — `time_value << 3`, so the grid is 8 frames wide. Widening is
  lossless: every stored value maps to `value * 8`, and nothing in the corpus
  needs sub-8 precision because nothing can express it.
- **animation** — `maxi(1, duration >> 1)`, because the ROM's `frame_timer`
  decrements by **2 per game frame**. The field is a **60 Hz vblank countdown**
  while the effect clock runs at 30 Hz (`PHYSICS_TIMESTEP = 1.0/30.0`), so the
  `>> 1` is a **clock-rate conversion wearing a bit-shift's clothes**. Also
  lossless in practice: **11 of 27,568 durations are odd (0.04%)**, and **76% are
  exactly `2`** — one frame — so the finer unit buys no expressiveness at all.

This is the temporal half of the units rule; dec. 8 is the spatial half. Same
defect, different axis: a ROM unit on a published interface.

**8. A typed payload is published in game units. The ROM carve-out is an
implementation, never a surface.** For a typed payload, **units are part of the
published shape** — a *camera* vocabulary (degrees, tiles, orthographic size) is
something a stranger can satisfy; a *PSX* vocabulary (4096 = a full turn, 28
units per tile, Y-down) is content wearing an interface's clothes.

[ADR-0091](0091-psx-magnitudes-convert-to-game-units-at-a-single-per-subsystem-seam.md)
already requires game-side code to speak the game's units, and already names this
offender in its Context. It also carves out *"faithful reimplementations of ROM
per-frame arithmetic"*, which stay in fixed-point — and `CameraSubsystem`, which
mirrors `0x801AD198`, is a legitimate carve-out. What 0091 does not say, and this
adds: **the carve-out's internals must not be the interface.** Today they are.
`current_position`, `current_angles`, `current_zoom` and `saved_*` are public
fields the consumer reads every host frame *and writes back into* — so the
coupling is a shared mutable struct in the ROM's number system, in both
directions.

**`SLOT_COPY` becomes a declared input.** The one camera source mode that needs
the consumer's *current* pose is why `CinematicManager` pokes those fields. It is
a legitimate need and belongs on the interface — *"here is the camera's current
pose"* — not as a field write.

Role resolution is already in the right place and does not change: `EffectInstance`
maps `CASTER` / `TARGET` / `CURSOR` / `ORIGIN` to anchors before the subsystem
sees them, which is the blueprint's role binding working as intended.

**9. `max_keyframe` does not survive.** A list knows its own length. The field
exists only because the storage preallocates a fixed slot count and needs to say
how many are real — and it is not merely redundant, it **disagrees with its own
array**: of 6,015 particle channels, **1,644 (27%) carry non-zero keyframe data
beyond `max_keyframe`**, bytes the runtime never reads. So the array alone cannot
tell you what is real, and a reader that forgets to consult the field gets
garbage a quarter of the time. Both failure modes were demonstrated while writing
this ADR: an off-by-one from `max_keyframe + 1` counting the skipped slot 0, and
`0x6E6E` read past the end and briefly reported as a duration.

**10. Byte-exact round-trip is a parity-rig requirement, not a runtime one.** It
belongs to `fft-iso-patcher` / `effect-editor` / the parity workspace, which
verify an edit against the PSX. The game's effect model is not bound by it. The
one artifact that must survive regardless is byte `0x31`, which is real data in
five channels and is preserved opaquely rather than as a keyframe.

## Consequences

**The caps disappear for free.** A span lane is a list; lists have no slot count.
25, 5, 33, 33 and 3 all cease to exist the moment the importer reads spans out of
the preallocated structs.

**Only `screen` publishes cleanly today.** `screen` hands out `Color` deltas in
0-1 floats. `palette` hands out a `ColorStack` folded by `psx_color_apply` — a
leak of the PSX *colour model*, not of units, so dec. 8 does not fix it.
`particle` mostly converts through `PsxUnits` but leaves `inertia_*` at raw
`4096.0`. `camera` leaks fully and bidirectionally. The units decision above is
narrow on purpose; the full survey of what `Effects` requires of its host is its
own question and is ticketed, not settled here.

**Dropping the beyond-the-end bytes is deliberate, not a bug.** An importer that
reads only live spans discards whatever sits past `max_keyframe` in those 1,644
channels. The runtime never read it, and byte-exact round-trip is not a goal of
the game model (dec. 10) — but the drop is **declared here** so nobody later
diagnoses it as data loss. The parity rig, which does need byte-exactness, reads
the ROM directly and is unaffected.

**One cap remains, and it is not a PSX artifact.**
`assets/shaders/psx_color_stack.gdshaderinc` declares `MAX_COLOR_LAYERS = 8` — a
fixed-size uniform array, 8 *per consumer*. It is the real ceiling once the
storage caps go, and lifting it costs shader work rather than importer work. Do
not assume every cap is a ROM cap.

**Both 1-based encodings die with slot 0.** `current_keyframe = 1` (slot base)
and `emitter_id - 1` (emitter base) are unrelated and look alike. Measured across
2,629 live channels, `kf[0].time` and `kf[0].action_flags` are **0 in 100%** of
them; only `emitter_id[0]` varies, and only because it *is* the shared byte.

**`refresh_tile` does not survive into the vocabulary.** The name describes
neither cause nor effect; `_on_refresh_tile` does exactly one thing —
`end_reaction()`. See [ADR-0123](0123-the-landmark-lane.md).

**The call graph stays greppable where it can.** Only the two opaque lanes are
genuinely pub/sub. The typed lanes name a subject in their payload and are
delivered by the cheapest legal shape — colour through the `owner_id` layer
registry, camera through the takeover capability. Events are not the uniform
egress.

**Effect Studio reaches into what this changes.** `EffectScoreTimeline`,
`ParticleTimelineChannel`, `CameraLowering` and `EffectScoreModel` are written
against today's muxed slots. `CameraLowering` already lowers the camera mask into
three lanes and calls them *"the authoring lanes and the runtime's own search
grain"* — so for camera the studio is ahead of the storage, not behind it. The
disruption is scheduled, not discovered: it is gated on
[#299](https://github.com/timbermania/fft-monorepo/issues/299).
