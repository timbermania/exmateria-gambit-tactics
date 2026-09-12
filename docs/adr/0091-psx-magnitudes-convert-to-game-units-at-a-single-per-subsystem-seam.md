# PSX magnitudes convert to game units at a single per-subsystem seam (`PsxUnits`)

Game-side code must speak the **game's** units and coordinate system; the PSX
fixed-point *magnitude* conventions (`4096` = one full turn / full-scale, `28`
world units per tile, the velocity/accel divisors, angle→radians) convert to
game units at **one named seam per subsystem, routed through a single shared
home (`PsxUnits`)** — never re-declared per file, never re-derived ad-hoc
downstream of the seam. Faithful reimplementations of ROM per-frame arithmetic
are carved out and stay in PSX fixed-point; a build guard stops the duplication
from regrowing.

Status: accepted (2026-08-12).

## Context

The PSX→game unit conversion is not missing and not wrong — it is **proven**
(`tools/parse_effect.py`'s `convert_position`/`velocity`/`accel`/`angle` is the
byte-validated mapping, and `EmitterChannel` even calls itself "the ONE ROM
mapping shared by parser, runtime and studio"). The problem is that the *same*
constants are **copy-pasted across five-plus files** — `parse_effect.py`,
`parse_trap_effect.py`, `PSXCameraConvert` (`ANGLE_FULL`/`TILE_SPACING`),
`EmitterChannel` (`_POS_DIVISOR`/`_VEL_DIVISOR`/`_ACCEL_DIVISOR`/`_ANGLE_TO_RAD`),
`TrapConstants` (`PSX_SCALE`/`FULL_CIRCLE_PSX`), `EffectCallback`
(`PSX_SCALE`/`ANGLE_SCALE`/`BRIGHTNESS_SCALE`) — and that some sites skip the
seam entirely: `CameraData` stores raw PSX angles and `ScenarioCameraDirector`
fixes them up inline (`yaw_u / 4096.0 * TAU`), `ParticlePhysics.angle_to_direction`
reasons in PSX axis signs (`# Use DOWN because PSX -Y=UP`). Duplication is the
disease; the stray `4096`s and the `-Y=UP` comment are symptoms. The junk
**regrew** during the effect-studio authoring work precisely because there was
no single home to point at and no guard to stop a sixth copy.

This is the **units** analogue of the coordinate rule that
[ADR-0057](0057-psx-spatial-transforms-sort-into-three-classes-placement-orientation-render.md)
already pinned — and the [`PsxNum`](../../src/scenarios/PsxNum.gd) consolidation
*pattern* (one named, pure, tested home for a subsystem's PSX conventions) is
already blessed, just scoped to the scenario VM's **discrete opcode encodings**.

## Decision

**1. Magnitude is a separate axis from chirality.** ADR-0057 governs
*sign/chirality/mirroring* (Placement / Orientation / Render). This ADR governs
*magnitude/scale* (the fixed-point unit conventions). The two are **orthogonal**:
a quantity is classified on **both** axes independently. A particle velocity is a
relative-Placement (ADR-0057 → linear sign-flips) **and** a fixed-point magnitude
(this ADR → divide by the velocity scale) — each converts at the boundary, each
by its own rule. Conflating scale with chirality is the same category error
ADR-0057 warns against, one axis over.

**2. One home: `PsxUnits`.** A new **repo-wide, pure, stateless** GDScript module
(`PsxUnits`), sibling to `PsxNum`, owns the **continuous magnitude↔game**
conversions in **both directions** (raw→game for reads, game→raw for the studio
round-trip and byte-exact writes). The universal base constants — `4096` = one
full turn (identical to `PsxNum.TURN_12BIT`), `28` = units per tile — live
**once**; `PsxNum` references the shared base rather than re-declaring it. The
split of responsibility:

- **`PsxNum`** — *discrete* opcode encodings: the 12-bit facing wheel, byte
  packing, sign-extension, depth-row mirror. Unchanged charter.
- **`PsxUnits`** — *continuous* magnitude↔game: full-turn angle→deg/rad,
  tiles, the velocity/accel divisors. Pure; no calibration, no node state.
- **`CameraCalib`** — a thin render/camera layer *atop* `PsxUnits` holding the
  *calibrated* mappings (`GODOT_CAMERA_SIZE = 12.6`, zoom→ortho-size). Kept
  separate so `PsxUnits` stays pure (`PsxNum`'s "no calibration" charter, one
  module over).

**3. The boundary is a seam, not a language.** "Convert at the boundary" does
**not** mean "always in `parse_effect.py`." The boundary is **the single named
seam per subsystem, routed through `PsxUnits`**. For effects that seam is the
Python parser (`parse_effect.py`). For the scenario camera the seam is the
**GDScript consume-boundary** (`ScenarioCameraDirector`), because `CameraData`
deliberately stores the raw angle as reverse-engineering byte-fidelity data —
so the director converts, but via `PsxUnits.angle_to_rad`, not inline `/4096.0`.
The invariant is **one seam + routed through `PsxUnits` + no ad-hoc
re-derivation downstream of it**, regardless of which side of the language
boundary the seam sits on.

**4. Faithful-sim internals are carved out.** A bit-exact reimplementation of
the ROM's per-frame arithmetic is the effects analogue of the SPU emulation
(CLAUDE.md → "Audio: use the C++ SPU hardware"): its `4096`/`>>12` **is the
algorithm**, load-bearing, and is *not* a unit leaking into game space. These
stay in PSX fixed-point:

- `ParticlePhysics` — the velocity/gravity integrator (`(accel·4096)/inertia`,
  `gravity·weight>>12`), a faithful port of `integrate_particle_motion`.
- `CameraChainSpline` — the bit-exact port of `FUN_8013dfb0` (PSX camera
  interpolator).
- `src/effects/callbacks/*` — the GTE fixed-point callback microcode (`>>12` UV
  counters, `radius<<12`).

They opt out with a top-of-file `# psx-faithful-sim: <reason>` header. The line
between "faithful sim" and "leak" is **who reads the value**: a `4096` inside a
faithful integrator is fine; a `4096` a converter, authoring surface, or
gameplay glue has to know about is the leak.

**5. The cross-language mirror is a named, accepted seam.** Python
(`parse_effect.py`) and GDScript (`PsxUnits`) remain **two copies** of the
mapping — GDScript cannot import Python. This is unavoidable and is the same
pattern as `fft-sound-driver` mirroring the gold GDScript sound driver. The ADR
names it rather than pretending it away; the two are kept in lock-step by a
golden-value parity test, not by wishing them into one file.

**6. A build guard stops re-duplication.** `tools/check_no_raw_psx_units.py`
(sibling to `check_no_env_vars.py`, ADR-0051) fails the build on bare PSX
magnitude literals (`4096`, `>>12`, `-Y=UP` reasoning, the `/28`-family
divisors) in `src/` and game-side tools. Exemptions: the `# psx-faithful-sim:`
file header (§4), a per-line `# psx-units-exempt: <reason>` marker for genuine
one-offs, and `PsxUnits.gd`/`PsxNum.gd`/`CameraCalib.gd` themselves (the homes).
Without the guard the junk regrows — it already did once.

## Considered alternatives

- **Grow `PsxNum` to hold units too.** Rejected: breaks its pure/stateless,
  scenario-scoped, "no calibration" charter and couples scenarios↔effects. The
  discrete-encoding vs continuous-magnitude split is a real seam, not ceremony.
- **Effects-scoped `PsxUnits` only.** Rejected: leaves the *universal* `4096`
  and `28` duplicated between `PsxNum` and the effects module — the very
  duplication this ADR exists to kill.
- **No guard, ADR + review discipline only.** Rejected: this exact junk regrew
  once without a guard. The conversion was never the problem — the duplication
  was — and only a mechanized check stops duplication from returning.

## Consequences

- **This is consolidation, not invention.** Every conversion `PsxUnits` holds
  already exists and is byte-validated; nothing new is computed. Parity risk is
  low *by construction* — the numbers don't change, they stop being copy-pasted.
  Each repoint lands as its own tiny commit with a parity guard (byte-identical
  saves / identical particle cloud) proving behaviour is unchanged.
- **The `-Y=UP` emission-direction fix (`ParticlePhysics.angle_to_direction`)
  is the one move that also crosses into ADR-0057** — it is a relative-Placement
  sign that belongs at the parse seam so the runtime reads `+Y=UP`. It is
  guarded by an identical-cloud parity test and classified on *both* axes.
- **The studio game-unit authoring flip rests on this.** Making the effect
  studio's unit-bearing cells accept game-unit *input* (game→raw on commit) — the
  [ADR-0089](0089-emitter-parameters-author-as-semantic-two-axis-groups-edited-at-the-reference.md)
  amendment — depends on `PsxUnits` existing as the both-directions home. This
  ADR is its prerequisite.
