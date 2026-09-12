extends RefCounted
## Pure raw↔human unit transform for EMITTER parameter authoring (ADR-0089) — the
## CameraUnits pattern applied to the particle domain. Only conversions PROVEN by
## the runtime/parser get a descriptor: positions, spreads and offsets in tiles
## (28 raw/tile, the parser's POSITION_DIVISOR — camera's POS_TILES convention),
## angles in degrees (4096 raw = 360°), and inertia as a × multiplier (raw 4096 =
## ×1.0 neutral, the physics formula's fixed-point one). Lifetimes / intervals /
## counts author as raw frames/counts (no descriptor — raw IS the human unit), and
## every unproven field stays a raw int with an honest tooltip (no speculative
## conversions). Storage, the byte writer and the runtime stay strictly RAW.
##
## Descriptor shape + affine are identical to CameraUnits (`{scale, suffix,
## decimals, bias, scrub}`), so the inspector's ONE `_int_cell` path serves both.
## No `class_name` (ADR-0004); pure static, no runtime deps.

## ADR-0212 dec. 1 — `addons/exmateria_platform` publishes one global,
## `ExMateriaPlatform`; aliasing a member back keeps every use site below
## spelled the way it was (ADR-0211 dec. 4). The PSX trio arrived at
## extraction #7 (#1220) and lost its three bare `class_name`s on the way.
const PsxMagnitude = ExMateriaPlatform.PsxMagnitude


const CameraUnits = preload("res://src/effects/studio/CameraUnits.gd")

# Position / spread / target-offset: 28 raw units per tile.
const POS_TILES := {"scale": 28.0, "suffix": " tiles", "decimals": 2, "bias": 0, "scrub": 0.1}
# Velocity angles: one full turn raw = 360° (full-turn base shared via PsxMagnitude, ADR-0091).
const ANGLE_DEG := {"scale": float(PsxMagnitude.FULL_TURN) / 360.0, "suffix": "°", "decimals": 1, "bias": 0, "scrub": 1.0}
# Inertia: 4096 raw = ×1.0 (keep velocity).
const INERTIA_X := {"scale": 4096.0, "suffix": "×", "decimals": 2, "bias": 0, "scrub": 0.02}


## Human display value → raw storage int (round to the nearest raw unit).
static func to_raw(display: float, unit: Dictionary) -> int:
	return CameraUnits.to_raw(display, unit)


## Raw storage int → human display value.
static func to_display(raw: int, unit: Dictionary) -> float:
	return CameraUnits.to_display(raw, unit)


## Round-trip a typed value through the raw encoding; the tell fires only when the
## achieved value differs at the author's own display precision.
static func quantize(display: float, unit: Dictionary) -> Dictionary:
	return CameraUnits.quantize(display, unit)
