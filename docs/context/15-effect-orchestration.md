# Effect orchestration

How a single spell/ability **effect cast** plays back over time. The runtime
hierarchy is **Subsystem → Phase block → Channel → Keyframe**, pumped by an
**Effect timeline** that owns clock + phase state. "Track" is **not** a runtime
concept — it survives only in ROM `.BIN` files and in code comments that
reference the ROM (e.g. `Keyframe.track_enable`, a ROM-faithful bitmask field
name). Everywhere else, the runtime word is **subsystem**.

The easy mistakes are (a) treating the per-subsystem processors as unrelated,
and (b) colliding the words "channel" / "subsystem" with the *music* audio
path, which uses overlapping vocabulary for a different timeline. This cluster
keeps both straight.

**Canonical FFT terms** for the effect-script model live in
`research/NOMENCLATURE_UPDATE_PLAN.md` (the authority) — defer to it. In short:
the phases are **phase-1 / for-each / phase-2**; effects are one of two script
patterns — **3-phase** (phase-1 + for-each + phase-2; opcode 41 outer + opcode
40 for-each) or **1-phase** (for-each only; opcode 40) — and *both* have a
for-each timeline (so a 1-phase effect is the *reduced* timeline set, not a
timeline-less one). Distinct from these phases: a **child emitter**
(`child_emitter_on_death` / `_mid_life`) is *particle hierarchy* — a particle
spawning another emitter's particles — and keeps the "child" name (plan
Part 1.7).

#### Extraction #7 translation table (`Effects`)

Loop passes 4–5 of extraction #7 ([ADR-0290](../adr/0290-an-addon-was-never-a-system-and-the-arm-4b-blocker-is-four-throwaway-probe-shaders.md),
[#1191](https://github.com/timbermania/fft-monorepo/issues/1191)); selection
[ADR-0286](../adr/0286-extraction-7-is-the-effects-runtime-and-the-studio-that-is-seventy-percent-of-the-bucket-is-a-root-set-that-stays.md),
crossings [ADR-0288](../adr/0288-the-sixty-one-debug-lines-are-four-booleans-and-the-seam-is-three-addresses-once-the-psx-trio-goes-home.md), plan
[ADR-0295](../adr/0295-the-forty-five-class-names-collapse-to-twenty-one-and-forty-eight-vault-notes-are-held-by-two-anchors.md).
Old term → new, kept for a reader who knows the old vocabulary. **Written before the move,
so every row is a plan until pass 9 re-measures it** — the row says which. Extraction #4's
table is the shape this follows: at pass 9 each row states what the tree does, and where
the tree and the plan disagree the row says so rather than restating the plan.

⚠️ **This table coins as little as possible, on purpose.** ADR-0288's first draft invented
*"colour recipe"* for a payload the blueprint already names — **colour op**
([`37-the-blueprint.md:349`](37-the-blueprint.md), ADR-0128), spelled
`ExMateriaSchema.ColorRecipe` in code — and PR #1197 corrected it with the slip recorded
rather than swapped. Three spellings for one payload is this system's live vocabulary
hazard, and it caught the ADR that existed to prevent it. Every row below either reuses a
word already in the repo or says openly that it has none yet.

| you may have read | say now | why |
|---|---|---|
| 45 global `class_name`s — `EffectData`, `EffectPhase`, `ScreenData`, `Particle`… | **one global name, `ExMateriaEffects`** — the other 44 are reached as `ExMateriaEffects.X` or not at all | [ADR-0212](../adr/0212-a-count-of-one-was-never-the-invariant-the-addons-one-global-is-the-folder-named-facade.md) dec. 1, priced at [ADR-0295](../adr/0295-the-forty-five-class-names-collapse-to-twenty-one-and-forty-eight-vault-notes-are-held-by-two-anchors.md) dec. 1. Godot has no package scope, so every `class_name` an addon declares lands in a consumer's global scope — and on a collision it is the **addon's** file that fails to parse. `exmateria_battlefield` was seeded at 30 and drained in one pass; this is 45. **The façade publishes 21**: that is how many members anything outside the addon reaches from *production*, minus the three that leave to `ExMateriaPlatform`. Fifteen more are reached only from `tests/`/`tools/` and are deliberately **not** published; 28 are reached from nowhere outside and simply drop the declaration |
| *`Effects` is `src/effects/`, 191 files and 58,124 lines* | **`addons/exmateria_effects/`** — 67 files / 14,441 lines — **plus the studio, which stays in the host** | ADR-0286 dec. 4, ADR-0290 dec. 1/2. The addon is **24.8%** of the `classify_blueprint.py` bucket and **100% of what the blueprint says `Effects` is**: the timeline, the particle simulation, the channel vocabulary (`37-the-blueprint.md:35-38`). The bucket is a *consumer census* (ADR-0243 dec. 3), not a capability |
| *an addon is a system* | **an addon is a shipping unit; a system is a capability** | ADR-0290 dec. 1. They coincide in three of six extractions and not in the other three: `Audio` is two addons in a package outside the walk, `Character Catalogue` leaves 23% (three `src/debug/` panels) in the host, and `exmateria_almanac` holds 795 `UI` lines and 2,745 `Battle` lines while being named for neither (ADR-0262 dec. 4). **ADR-0134 dec. 4 is not amended by this** — it rules that the studio and the runtime are one *system*, which stays true while the addon holds one of them |
| `UnitTintOverlay` · `register_unit(unit_id, material)` | **`TintedSurfaces`** · **`register_surface(surface_id, material)`** | ADR-0288 dec. 7, split by ADR-0290 dec. 7. **LANDED at #1223** (2026-09-12), with the whole `unit`→`surface` vocabulary rather than the two names the ticket listed: `unregister_surface`, `is_surface_registered`, `get_surface_count`, `_surface_materials`. The class **never dereferences the id it is keyed by** — `src/units/Unit.gd:730` calls it *with the material* — so it is a registry of tinted **surfaces** and `surface_id` is an opaque token. **No code reach from any shipped addon**, confirmed: exactly **one** addon reference named it and it is a comment (`exmateria_schema/colour_model/ColorStack.gd:325`), updated with the rename. ⚠️ The ticket's other two addon references (`exmateria_battlefield/terrain/DynamicGeometryBuilder.gd:33`/`:561`) name **`MapTintOverlay`**, which #1223 leaves alone — so they were not stale at this rename and become so only at the merge below |
| `MapTintOverlay` | **the `SURFACE_MAP` case of `TintedSurfaces`** | ADR-0288 dec. 7. **LANDED at #1224** (2026-09-12) — the class is deleted and the map is the reserved `SURFACE_MAP` token. ⚠️ **It was the key plus FOUR differences, not the key alone**, and all four are preserved rather than flattened: a surface holds MANY materials (`MapComposer` emits one per chunk); `SURFACE_MAP` is reserved at `_ready` so the map keeps its no-registration-guard behaviour; `update_layer` packs `MASK_SURFACE0` for the map and `MASK_WHOLE` for a unit; and the 8-bit additive `map_illum_add` sink carried over whole, because its own docstring records it as RETAINED-BUT-UNWIRED for a future untextured-terrain scope. `is_active()` was deleted (zero callers). The host's `[autoload]` count went **4 → 3, not 4 → 2** — see `plugin.gd`'s header for the measurement that refuted the fourth |
| `PsxUnits` · `CameraCalib` · `PSXCameraConvert`, in `src/effects/` | **`addons/exmateria_platform/`** — `PsxUnits` → **`PsxMagnitude`**, `CameraCalib` → **`CameraCalibration`**, `PSXCameraConvert` → **`PsxChirality`** | ADR-0288 dec. 4 (the home), ADR-0290 dec. 5 (two of the three names), [ADR-0295](../adr/0295-the-forty-five-class-names-collapse-to-twenty-one-and-forty-eight-vault-notes-are-held-by-two-anchors.md) dec. 3/4 (the third, and the correction). A closed **219**-line triangle (216 before #1215 anchored three vault notes into it) whose only outside dependency is `ExMateriaPlatform.PsxNum`, and **not one of the three mentions an effect**. The move must carry the rename: `PLATFORM_EXEMPT` in `score_goals.py` is `{"Render"}` and goal #7 is scored per *system*, so a `Psx`-named file arriving in a tier is **unscored, not paid** — which is what [#583](https://github.com/timbermania/fft-monorepo/issues/583) already says for `PSXDisplay` → `DisplayCalibration`. **`Magnitude` is ADR-0091's own filename word**, not a coinage, and it is the *continuous* half of that ADR's discrete/continuous charter split — so the pair reads `PsxNum` / `PsxMagnitude`. ⚠️ **ADR-0290 dec. 5 folded `PSXCameraConvert` into `CameraCalibration` because *"it publishes no arithmetic of its own"*; it does.** Measured when the move landed (#1220), excluding the definition: **85** call sites — **42** pure delegation (`psx_angle_to_deg` 3, `deg_to_psx_angle` 18, `psx_zoom_to_ortho_size` 11, `ortho_size_to_psx_zoom` 10) and **43 its own** (`psx_position_to_godot` 11, `godot_position_to_psx` 17, `psx_angles_to_godot_rotation` 15) — the Y-negate and the `-pitch`, which both siblings refuse by charter in their own docstrings. ⚠️ ADR-0295 dec. 4 priced those as 70 / 21 / 21 / 38, whose own parts sum to 80 rather than 70; the pass-through half reproduces exactly and the own-axis half is **five higher**, so the correction strengthens dec. 4 rather than weakening it. The 42 were deleted with the pass-throughs and now name `PsxMagnitude` / `CameraCalibration` directly. `chirality` is ADR-0052/0057's word and all three files already use it |
| `base_yaw_psx` · `pitch_psx` · `yaw_psx` (`CinematicFacingResolver.gd`) | **`base_yaw_12bit`** · **`pitch_12bit`** · **`yaw_12bit`** | ADR-0290 dec. 5, reusing [ADR-0234](../adr/0234-a-port-half-is-not-shipped-until-both-directions-of-the-value-are-on-it.md)'s **executed** spelling (`camera_angle_12bit`, #848) rather than coining a rival. The finding there applies verbatim here: the port does not spell it `psx`, so the prefix was echoing nothing |
| `EffectInstance.audition_container()` · `audition_sound()` | **`studio_audition_container()`** · **`studio_audition_sound()`** | ADR-0288 dec. 6 books them to the studio without moving them; ADR-0290 dec. 6 makes the booking checkable. The host wrappers at `src/scenes/EffectViewerScene.gd:768/777` **already carry the prefix** — the studio half was marked and the runtime half was not. After the rename `grep -rn studio_audition` returns the whole chain: projector → page → assembler → runtime. The action *kind* strings (`"audition_container"`) are the projector's vocabulary and do **not** change, which is why no test moves |
| `DebugConfig.particle_debug_enabled` · `.iteration_…` · `.timeline_…` · `.camera_…` | **`EffectsDebug.particle()`** · **`.iteration()`** · **`.timeline()`** · **`.camera()`** | ADR-0288 dec. 1/2. Sixty-one sites, four booleans, read and never written, every one gating a `print`. The slug literals stay `debug.*` so the two owners cannot disagree, and the severance is **test-transparent** because both spellings reach one `Tune` registry. `addons/exmateria_sprite_rig/install/RigDebug.gd` is the template and is *transcribed*, not adapted |
| `ExMateriaEffectSfx.…` · `preload("res://addons/exmateria_sound/runtime/…")` | **`ExMateriaSound.EffectSoundController` · `.EffectJSONLoader` · `.EffectSoundResolver` · `.FedsBank`** | ADR-0288 dec. 5. Fifteen lines over two files, eleven of them one port whose real verb surface is **four** — `begin_effect() -> int`, `play_pair(token, bank, pair_idx, sound_id)`, `end_effect(token)`, `orphan_effect(token)` — which is [ADR-0124](../adr/0124-effects-tells-audio-a-code-and-a-time.md)'s *code and a time* with a cast token. ⚠️ Three of the fifteen were a raw `preload` into another addon's `runtime/`, **invisible to all nine portability arms** because the target is inside *an* addon root |
| *"colour recipe"* (ADR-0288 first draft) | **colour op** — `{scale, bias, duration, mode_token}`, `ExMateriaSchema.ColorRecipe` in code | ADR-0128, `37-the-blueprint.md:349`. **A spent row, kept as the warning.** The word already existed; the ADR that was supposed to prevent rival coinages coined one, and PR #1197 recorded the slip rather than swapping it out |

**Addon (shipping unit) vs system (capability)**:
Two different objects, and `ls addons/` answers only the first. A **system** is one of the
blueprint's eleven — a capability, admitted by [ADR-0115](../adr/0115-a-system-is-a-bundle-that-ships.md)
dec. 3's asymmetry test (*would anyone use this without that?*). An **addon** is a Godot
install unit. [ADR-0121](../adr/0121-systems-land-in-addons-src-only-shrinks.md) dec. 1
gives a system's code an address — `godot-learning/addons/<system>/` — and that is an
address rule, not an identity: dec. 1's own example, `exmateria_sound` as *"`Audio`,
landed"*, is today **two** addons in a package the walk deliberately does not enter
([ADR-0153](../adr/0153-audio-extracts-into-a-package-the-walk-reports-rather-than-enters.md) dec. 1).
Three of the six extractions so far ship an addon that is not coextensive with its system,
and one of them — `exmateria_almanac` — is named for no system at all
([ADR-0262](../adr/0262-the-alias-route-hid-forty-nine-lines-and-the-almanac-reads-as-a-system-only-because-classify-books-by-consumer.md) dec. 4).
**Where this bites:** `check_addon_portability.py`'s `_system_of` is a majority vote over
`classify()` buckets among an addon's own files, so an addon that holds several systems'
files is *priced* as whichever one wins the vote. `exmateria_effects` is not exposed to
that — all 67 of its files book `Effects` — but the reading has to be checked per addon,
not assumed from the name.

**Subsystem**:
A **subsystem** is the runtime that reads parsed keyframe data and turns
frames into output. There are four — Color, Camera, Particle, Sound. The
runtime hierarchy lives entirely inside a subsystem: each holds per-phase
[phase blocks](15-effect-orchestration.md), each phase block holds parallel
[channels](15-effect-orchestration.md), each channel holds keyframes. The
duck-typed `Subsystem` contract is `advance(frame, phase)` / `reset()` /
`is_done()` (`addons/exmateria_effects/subsystem/Subsystem.gd`); see [ADR-0014](../adr/0014-effecttimeline-owns-time-modulation-tracks-self-deliver.md)
for the conformer list. The contract is satisfied entirely duck-style — no file
extends `Subsystem` (issue #675). Each subsystem
**self-delivers** its own output during `advance()` — a color subsystem pushes
`update_layer_gradient` / `update_stack` to its overlay sink, sound fires its
key-on, camera exposes its
pose for `PlayerCamera` to pull, particle spawns into its pool. `EffectInstance`
is **not an output courier**: outputs stay type-specific, owned by the
producing subsystem, and never cross the orchestration interface (ADR-0014;
the timeline stays output-agnostic).
_Avoid_: calling a subsystem "a track" or "a track controller" — those names
are retired (#31); calling a subsystem "a manager" — every subsystem owns its
own state, but "manager" suggests external coordination the subsystem doesn't
do; reading a subsystem's output back out by concrete type in `EffectInstance`
(the historical screen/palette courier the self-delivery retired); a uniform
`apply()` / output verb on the `Subsystem` contract (false uniformity — sound
is an event, camera a pull, color a material-uniform push); treating the
`EffectViewer`'s per-emitter mute checkbox as a runtime control surface — it is
debug-time observability owned by the viewer panel + the particle renderer's
`disabled_emitters` field, and `EffectInstance.set_debug_emitter_filter` is the
named-as-debug forwarder; `EffectInstance` and `ParticleSubsystem` carry no
runtime filter API (the dual-store shape this retired silently leaked pool
slots — the subsystem kept spawning particles the renderer then hid).

**Effect timeline**:
An effect cast's authored playback schedule — the per-frame, phase-organized
program one cast runs. **One** effect timeline drives every
[subsystem](15-effect-orchestration.md) of that cast together (color, camera,
particle, sound) off a shared frame clock and a shared phase state
(`phase1` → `for_each` → `phase2`, where `phase2` overlaps `for_each`). It is
the orchestrator: it owns the clock, the phase, **and time-modulation**, and
pumps each subsystem one frame at a time via `advance(frame, phase)`. It
computes the time-scale (pacing) factor from state **it owns** — its own
`effect_frame` + phase boundaries (`for_each`-local frame
`= effect_frame − phase1_duration`), **never by reading the particle
subsystem** — and applies it to its accumulator (see ADR-0014, which finishes
ADR-0012's half-relocated time-mod). It stays **output-agnostic**: it pumps
*time* only and never learns what a subsystem produces. A foreign subsystem
(the exmateria-sound addon's sound subsystem) participates by consuming the
timeline's tick + phase, never by owning a clock of its own. (The `for_each`
phase — "runs once per target" — is `EffectPhase.PHASE_FOR_EACH`, value
`"for_each"`. Previously the value was kept as the Ghidra-annotated label
`"animate_tick"` for "ROM linkage"; we corrected this — the ROM has no inherent
names, Ghidra labels are our annotation, so the value is now plain `for_each`.)
_Avoid_: conflating with the **SMD music sequence** (a song's timeline) —
that is a separate timeline for music, not for an effect cast.

**Pacing curve**:
The per-frame integer sequence the [effect timeline](15-effect-orchestration.md)
reads to compute its time-modulation (see time-scale above). An effect carries
**two** pacing curves, each gated by its own enable bit in the effect flags
byte:
- **Phase 1 pacing** (`outer_phases`, gated by flag bit 5 — decoded as
  `time_scale_pattern1`): sampled by the phase-1-local frame while phase 1
  plays.
- **For-each pacing** (`for_each`, gated by bit 6 — `time_scale_pattern2`):
  sampled by the for-each-local frame while the for-each phase plays.

Each curve is 600 values on disk but only its playing phase's worth of frames
is ever read; the rest is never-sampled tail. **Value semantics** (base pacing
= 2): **1–2** leave the clock at real speed, **3–9** slow it progressively
(factor `2 / value`, so 9 is the deepest slow), and **0 or 10–15 "hold"** the
previous pacing unchanged. Across the whole effect corpus the values seen are
only **2–10** (10 = a deliberate "hold at max slow" marker right after a 9);
0, 1, and 11–15 never occur. In the [Effect Studio](16-effect-studio-authoring-tool.md)
the two curves are shown as a **slowness band** on a global "Time scale" lane at
the bottom of the timeline (height = `value − 2`, so normal stretches read flat
and slow-mo swells stand out against the rest of the effect), mirroring the
sound triggers' energy ghost band. The curve is **painted directly on the band**:
left-clicking a band **expands the lane row** to a paintable height (the other
band dims to read-only), you freehand-paint on the slowness scale (value `2` at
the floor → `10` at the top, WYSIWYG with the collapsed render), and **Esc /
click-away collapses it** back. Each curve's enable bit is a gutter toggle in the
lane's Solo/Mute slot (ADR-0093 + its "paint on the band" amendment; the earlier
centered pop-up editor was removed). _Caveat_: the flag-bit *names* `TIME_SCALE_3PHASE`
(bit 5) / `TIME_SCALE_1PHASE` (bit 6) describe **which script pattern arms the
bit**, not what the curve does — for authoring, the honest names are **Phase 1
pacing** and **For-each pacing**. _Avoid_: the "3-phase / 1-phase" labels in
authoring UI copy (they read as the curve's identity but mean the arming
pattern).

**No-clock invariant** (the rule that keeps the pieces separable): a
subsystem **owns no clock** — no `Timer`, no `_process`, no scene-tree handle.
It is *driven* by whatever pump calls `advance()`: the [effect
timeline](15-effect-orchestration.md) in gameplay, or a standalone harness (a
`Timer`, a test rig) when a subsystem is used **a la carte**. The same
subsystem can be driven by either; it cannot tell which. The sound subsystem
already proves this — its processor is clock-free and the `Timer` lives in a
separate wrapper. Because no subsystem owns time, extracting a clean
orchestrator later is just *gathering the scattered `advance()` calls into one
pump*, never a redesign of any subsystem. (Pump *granularity* — frame vs FFT
sub-tick — is the one open question this leaves to the orchestrator; see
ADR-0011.)
_Avoid_: calling a *parallel lane within a subsystem* a "subsystem" — that is
a [channel](15-effect-orchestration.md); SMD music "tracks" — that is the music
path's term, not the effect path's.

**Phase block**:
One phase's worth of cursor + channel state within a subsystem
(`PhaseBlock.gd`, renamed from `TimelineController` — ADR-0014).
A subsystem owns one phase block per phase it has data for: the
[ParticleSubsystem](15-effect-orchestration.md) holds three (`phase1_block`,
`phase2_block`, `for_each_block`). Each phase block carries the single
**phase cursor** (the current frame *within* this phase) and its
per-channel keyframe state, pumped from outside by the subsystem's
`advance(frame, phase)`. The data layer keys the underlying channels by
phase (`TimelineData.channels_by_context: Dictionary[phase, Array[Channel]]`),
so phase blocks are *encapsulated*: there is no cross-phase continuity,
and different phases could (theoretically) have different channel counts.
The other subsystems (`ColorSubsystem`, `CameraSubsystem`, `PaletteSubsystem`,
`ScreenSubsystem`) hold the equivalent state in a single instance that branches
on phase internally; same data model, flatter implementation.
_Avoid_: thinking of channels as "continuous across phases" — a channel in
`phase1` and a channel in `phase2` with the same `channel_index` are
*independent* collections sharing a labeling integer, not the same lane;
collapsing the three phase blocks into one cursor-with-branching (it would
flatten the per-phase encapsulation the data layer already names).

**Channel**:
A parallel keyframe lane **within a single phase block** of a subsystem —
one cursor advancing its own keyframes over frames within that phase. The
**same** concept everywhere in the effect timeline: the particle subsystem's
emitter lanes (a 0-4 index identifying *which* lane spawned this particle),
the FEDS effect-sound lanes, and the palette subsystem's `affected_units` /
`caster` / `target` lanes are **all** channels. Channels are *per-phase*
entities (the data layer stores them keyed by phase); a channel in `phase1`
and a channel in `phase2` of the same subsystem are independent collections,
even when they share a `channel_index`. (The palette processor historically
misnamed its three lanes "tracks"; they are channels like the rest.)
`channel_index` is a **lane identifier, not a Z-order key** — FFT's particle
draw order is [`depth_mode`](25-rendering-depth.md) at the OT bucket, then
OT-insertion-order within a bucket as a side effect of emitter iteration; no
ROM mechanism designates channel as a sort key, and intra-bucket ordering by
channel is not authored data.
_Avoid_: the **SMD / SPU sequencer channels** and hardware voices of the
*music* path — same word, a different (music) timeline; not to be confused;
treating `channel_index` as a deliberate Z-order key in render code (the
historical CPU-side `channel * 1000` sort term was inventing a designated
key FFT doesn't have); thinking of a `channel_index` as a structural link
across phases — it is shared labeling, not shared identity.

**Cinematic facing resolution** (a.k.a. **facing resolver**):
How the effect camera picks its base **yaw** when an angle keyframe uses a
unit-anchored source (`TARGET` / `CASTER` / `CURSOR`) — the Godot heir to the
ROM's `calc_facing_angles` (`0x801aac28`). It chooses among the **4 fixed
yaws** (±45°, ±135°) only; **pitch and zoom stay whatever the effect authored**
(the effect owns those, the resolver owns yaw). Keyframe angle offsets still add
on top of the chosen base. Resolution is layered:
- **Terrain-visibility gate** — a yaw is *eligible* only if the **focused
  unit** (the keyframe's source unit) is not hidden behind map geometry. This
  is the one behavior the ROM models — via a precomputed per-tile, per-quadrant
  bit (tile-characteristics byte 7 low nibble). We compute the equivalent
  **live**, but **analytically, not by physics raycast**: the map's only
  terrain colliders are the flat tile-top quads (the vertical cliff faces have
  none), so a low-angle camera ray threads *between* the tops and never hits
  the cliff that blocks the view. Instead we march the sightline from the
  unit's **silhouette** samples toward the camera and compare each column's
  tile-top world-Y (`TerrainIndex`/`get_tile`) against the ray height. Unit
  occlusion (the tie-break) *does* raycast — units are Area3D volumes.
- **Foreground-composition tie-break** *(our addition — not in the ROM)* —
  among eligible yaws, prefer the one with the **fewest other units occluding**
  the focused unit (`collision_mask = 4`, units), then the one putting the
  focused unit **most in the foreground** (nearest camera-depth among
  neighbours), then the ROM's **minimal-rotation-from-current** (prefer current
  → +90 → −90 → 180) for stability.
- **All-blocked fallback** — if **no** yaw clears the terrain gate, **keep the
  current yaw** (ROM-faithful: the `0xf` branch). We deliberately do *not*
  best-effort here.
Resolution is computed **once per focused subject and cached** (the cinematic
freeze pins all positions, so the only recompute trigger is the
caster→target→cursor subject change, never movement). The **focused unit** is
the unit the current angle keyframe's source resolves to; `ALL_TARGETS` /
`EFFECT_CTR` are *not* unit-anchored and get no facing resolution (matching the
ROM's no-op there). Lives in `CameraSubsystem._get_facing_yaw`
(`addons/exmateria_effects/subsystem/CameraSubsystem.gd:630`), today a stub that snaps to 45° and
skips the gate "(we lack tile data)". See ADR-0039.
_Avoid_: calling the gate a raycast — terrain visibility is **analytic** (tile
heights), because flat-top-only colliders make a physics terrain ray thread
between the quads. The gate (terrain, analytic) and the tie-break (units,
physics raycast) are **two** mechanisms for **two** purposes; a single
nearest-hit ray conflates "cliff hiding the unit" with "ally in front" and
chases "big items". Don't say the ROM picks the "best"
angle — it has no scoring; it keeps the current yaw unless that quadrant's bit
is set, then rotates the minimum amount. "Camera facing" the unit is **yaw**
only; pitch is never moved to dodge occlusion.
