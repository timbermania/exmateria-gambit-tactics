# Units convention (magnitude vs. chirality)

Where ADR-0057's spatial cluster governs a quantity's *sign/chirality*, this
cluster governs its *magnitude/scale* — the PSX fixed-point unit conventions
and where they convert to game units. The two axes are **orthogonal**: a
velocity carries a relative-Placement sign (spatial cluster) **and** a
fixed-point magnitude (this cluster), classified independently. See
[ADR-0091](../adr/0091-psx-magnitudes-convert-to-game-units-at-a-single-per-subsystem-seam.md).

**Game-unit boundary** (a.k.a. the units seam):
The single named seam per subsystem where PSX fixed-point magnitudes (`4096` =
one full turn / full-scale, `28` world units per tile, the velocity/accel
divisors, angle→radians) become game units — **routed through `ExMateriaPlatform.PsxMagnitude`**, so
runtime, authoring, and gameplay code downstream read game units and never
re-derive the conversion. The seam is a *place*, not a *language*: for effects
it is the Python parser (`parse_effect.py`); for the scenario camera it is the
GDScript consume-boundary (`ScenarioCameraDirector`), because `CameraData`
stores the raw angle as RE byte-fidelity data. The invariant is **one seam +
routed through `PsxMagnitude` + no ad-hoc re-derivation downstream**.
_Avoid_: re-declaring the scale constants per file (`ANGLE_FULL`, `TILE_SPACING`,
`_POS_DIVISOR`… were five-plus copies — the junk); fixing up a raw value inline
downstream of the seam (`yaw_u / 4096.0 * TAU` in a director, `# PSX -Y=UP` in
physics); assuming "the boundary" always means the Python parser.

**`PsxMagnitude`** (`ExMateriaPlatform.PsxMagnitude`):
The single, repo-wide, pure/stateless home for **continuous magnitude↔game**
conversions, in **both directions** (raw→game for reads, game→raw for the studio
round-trip and byte-exact writes). Sibling to `PsxNum`, which owns the
**discrete opcode encodings** (facing wheel, byte-pack, sign-extend); the
universal base constants (`4096` full-turn, `28`/tile) live once and `PsxNum`
references them. Calibrated mappings (`GODOT_CAMERA_SIZE = 12.6`, zoom→ortho)
live in a thin `CameraCalibration` layer *atop* `PsxMagnitude`, keeping the core pure.
_Avoid_: putting units conversions in `PsxNum` (breaks its scenario-scoped,
no-calibration charter); calibration in `PsxMagnitude` (belongs in `CameraCalibration`);
forgetting the Python↔GDScript copies are a deliberate, parity-tested mirror
(like `fft-sound-driver`), not a bug to merge away.

**`PsxChirality`** (`ExMateriaPlatform.PsxChirality`):
The *third* axis, and the one that had no address until #1220: the PSX Y-down ↔
Godot Y-up 180°-about-X and the camera `-pitch`. The first paragraph of this file
calls magnitude and chirality orthogonal; `PsxMagnitude`'s charter says the Y-flip
is *"a separate axis applied by the caller"* and `CameraCalibration`'s says it holds
only the dialled-in mapping — so before this file existed the sign was applied inline
at every caller, or routed through a façade (`PSXCameraConvert`) that described itself
as pure delegation and was not.
_Avoid_: re-deriving a Y-negate inline beside a `PsxMagnitude` call (that pairing IS
`PsxChirality.psx_position_to_godot`); reading the word *chirality* as ADR-0057's
relative-Placement sign — ADR-0052's handedness is a different sign, and this file
holds that one.

**Where the three live** (#1220, gl-ADR-0295 dec. 3/4): all three are
`addons/exmateria_platform/` members published on `ExMateriaPlatform` —
`fixed_point/PsxMagnitude.gd`, `fixed_point/PsxChirality.gd`,
`display_port/CameraCalibration.gd`. They were `src/effects/{PsxUnits,
PSXCameraConvert,CameraCalib}.gd`, a closed 219-line triangle that reached nothing in
`Effects` at all, so the effects runtime was only ever their address of convenience.
Alias a member back where a bare spelling reads better (ADR-0211 dec. 4):
`const PsxMagnitude = ExMateriaPlatform.PsxMagnitude`.

**Faithful-sim internals**:
A bit-exact reimplementation of the ROM's *per-frame arithmetic* — the effects
analogue of the SPU emulation. Its `4096`/`>>12` **is the algorithm**,
load-bearing, and is **not** a units leak: the `ParticlePhysics` velocity/gravity
integrator, `CameraChainSpline`'s port of `FUN_8013dfb0`, the
`src/effects/callbacks/*` GTE microcode. Carved out of the units boundary; opts
out with a top-of-file `# psx-faithful-sim: <reason>` header. The line between
"faithful sim" and "leak" is **who reads the value**: a `4096` inside a faithful
integrator is fine; a `4096` a converter, authoring surface, or gameplay glue
must know about is the leak — and the `tools/check_no_raw_psx_units.py` guard
enforces exactly that line.
_Avoid_: "purging" a faithful integrator's fixed-point math to game units (that
is a rewrite, not a cleanup — it breaks ROM parity); treating every string
`4096`/`>>12` in `src/` as junk (the guard's allowlist exists for this reason).
