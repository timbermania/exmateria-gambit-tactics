extends RefCounted
## Pure raw↔human unit transform for the Effect Studio camera inspector. The E###.BIN
## stores camera angle / position / zoom as raw PSX s16 (4096 = 360° for angles, ~28
## units per tile, 4096 = 1.0× zoom); those leaked implementation details are exactly
## what an author should NOT have to type. This module is the authoring-boundary affine
## that lets the inspector show DEGREES / TILES / ZOOM-× while storage, the byte writer
## (write_effect_camera.py), and the runtime (CameraSubsystem) stay strictly RAW.
##
## A `unit` is a small descriptor `{scale, suffix, decimals}`:
##   * scale    — raw units per human unit (deg → raw = deg · scale; raw → deg = raw / scale)
##   * suffix   — the widget suffix ("°", " tiles", "×")
##   * decimals — the author's display precision (0.1° etc.)
##
## The transform is the same affine the inspector's `bias` already applies, with a scale
## term added: raw = round(display · scale) + bias, display = (raw − bias) / scale. Camera
## units carry bias 0 (angle/position/zoom are not bipolar-stored); the bias term stays so
## the ONE `_int_cell` affine serves both the camera units and the screen signed-byte lesson.
##
## No `class_name` (ADR-0004); pure static, no runtime deps — testable in isolation.

## ADR-0212 dec. 1 — `addons/exmateria_platform` publishes one global,
## `ExMateriaPlatform`; aliasing a member back keeps every use site below
## spelled the way it was (ADR-0211 dec. 4). The PSX trio arrived at
## extraction #7 (#1220) and lost its three bare `class_name`s on the way.
const PsxMagnitude = ExMateriaPlatform.PsxMagnitude


# `scrub` = drag speed in HUMAN units per pixel (decoupled from `decimals`, which sets typing
# precision), tuned so a normal drag covers a useful range without racing.
# Angles: full turn raw = 360° → 11.377…/degree (full-turn base shared via PsxMagnitude,
# ADR-0091). 90°=1024, 180°=2048, 45°=512 (exact).
const ANGLE_DEG := {"scale": float(PsxMagnitude.FULL_TURN) / 360.0, "suffix": "°", "decimals": 1, "bias": 0, "scrub": 1.0}
# Position: ~28 raw per tile (CameraData position comment).
const POS_TILES := {"scale": 28.0, "suffix": " tiles", "decimals": 2, "bias": 0, "scrub": 0.1}
# Zoom: 4096 raw = 1.0× baseline (CameraSubsystem.current_zoom).
const ZOOM_X := {"scale": 4096.0, "suffix": "×", "decimals": 2, "bias": 0, "scrub": 0.02}


## Human display value → raw storage int. Affine units round to the nearest raw
## unit; a LOOKUP-MAP unit (`{"map": PackedFloat32Array}` — nonlinear encodings
## like the SPU ADSR rate→milliseconds tables, FedsParamSemantics) snaps to the
## raw index whose table value is nearest the typed display (the raw IS the index).
static func to_raw(display: float, unit: Dictionary) -> int:
	if unit.has("map"):
		var map: PackedFloat32Array = unit["map"]
		var best := 0
		var best_d := INF
		for i in range(map.size()):
			var d := absf(map[i] - display)
			if d < best_d:
				best_d = d
				best = i
		return best
	var scale: float = float(unit.get("scale", 1.0))
	var bias: int = int(unit.get("bias", 0))
	return int(round(display * scale)) + bias


## Raw storage int → human display value. Map units index the table (clamped —
## an out-of-range raw shows the nearest real value rather than inventing one).
static func to_display(raw: int, unit: Dictionary) -> float:
	if unit.has("map"):
		var map: PackedFloat32Array = unit["map"]
		if map.is_empty():
			return 0.0
		return map[clampi(raw, 0, map.size() - 1)]
	var scale: float = float(unit.get("scale", 1.0))
	var bias: int = int(unit.get("bias", 0))
	return float(raw - bias) / scale


## Round-trip a typed display value through the raw encoding and report what the author
## will ACTUALLY get. The tell (`ok`) is honest: it fires only when the achieved value,
## shown at the author's own precision, differs from what they typed — so a unit finer
## than the display (angles at 0.1°) stays silent, and a coarse one (tiles at 0.01) warns.
static func quantize(display: float, unit: Dictionary) -> Dictionary:
	var decimals: int = int(unit.get("decimals", 0))
	var raw: int = to_raw(display, unit)
	var achieved: float = to_display(raw, unit)
	var ok: bool = _round_to(achieved, decimals) == _round_to(display, decimals)
	var reason: String = ""
	if not ok:
		reason = "rounds to %s%s" % [String.num(achieved, decimals), str(unit.get("suffix", ""))]
	return {"raw": raw, "achieved_display": achieved, "ok": ok, "reason": reason}


static func _round_to(v: float, decimals: int) -> float:
	var f: float = pow(10.0, decimals)
	return round(v * f) / f
