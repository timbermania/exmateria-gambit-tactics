class_name ScenarioMotion
extends RefCounted
## One scripted unit motion — Sprite Move ({3B}/{6E}) or Walk To ({28}) — as a
## pure, scene-free value object (ADR-0055). A positional lerp from `start` to
## `target` over `dur_s` seconds, shaped by the event-script easing curve.
##
## Holds NO node reference: `position()` is pure decode; the VM resolves the node
## via `units_by_id` and writes `global_position` at apply time. Rotate is NOT one
## of these — it stays Unit-owned (a 16-notch stepper, not a lerp) and only answers
## the shared `motion_done(uid)` predicate.
##
## Curve is a bit-exact port of ScenarioVM._sprite_move_curve, ROM-verified
## per-frame against hardware (SPRITE_MOVE_INVESTIGATION.md) — do not "clean it up".
## Pure and stateless apart from `elapsed_s`; tested with no scene (ScenarioMotionTest).

var start: Vector3
var target: Vector3
var dur_s: float
var elapsed_s: float
var easing: int
var weight: int


func advance(dt: float) -> void:
	elapsed_s += dt


func frac() -> float:
	return clampf(elapsed_s / dur_s, 0.0, 1.0)


func position() -> Vector3:
	return start.lerp(target, curve(easing, frac(), weight))


func is_done() -> bool:
	return frac() >= 1.0


func snap_to_end() -> void:
	elapsed_s = dur_s


## Bit-exact port of ScenarioVM._sprite_move_curve. `w = clampi(weight, 0, 16)`,
## `cw = 16 - w`. See ScenarioVM.gd for the per-easing rationale.
static func curve(easing: int, f: float, weight: int) -> float:
	var w := float(clampi(weight, 0, 16))
	var cw := 16.0 - w
	match easing:
		1:
			return f + w * f * (1.0 - f) / 16.0
		2:
			if f < 0.5:
				return w * f * f / 8.0 + cw * f / 16.0
			var g := 2.0 * f - 1.0
			return 0.5 + (cw * g + w * g * (2.0 - g)) / 32.0
		3:
			return (w * f * f + cw * f) / 16.0
		_:
			return f
