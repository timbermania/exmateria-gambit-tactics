extends RefCounted
## Issue #281 — the honest LABEL for a camera keyframe value. A value is stored the same way
## in every mode, but the runtime (CameraSubsystem._execute_{angle,position,zoom}_command)
## treats it as one of four things depending on source_mode × interpolation:
##   * absolute  — the value IS the target ("Yaw")
##   * offset    — added to an EXTERNAL anchor: a unit's facing, a saved slot ("Yaw offset")
##   * delta (Δ) — added to the CURRENT camera value, a relative nudge ("Yaw Δ")
##   * amplitude — a SHAKE_* magnitude, not an angle-to ("Yaw amplitude")
## The unit stays degrees/tiles/× in every case; only the suffix changes, so the author never
## mistakes an offset for a world heading.
##
## This mirrors the runtime match statements (cited above) — it is the ONE place that reads
## them for labels, so if the engine's mode handling changes, this table changes with it. Pure
## static, no runtime deps (testable in isolation, no `class_name` per ADR-0004).

const _ABSOLUTE := ""
const _OFFSET := " offset"
const _DELTA := " Δ"
const _AMPLITUDE := " amplitude"
const _INERT := " (inert)"

# SHAKE interpolations store an amplitude regardless of source (CameraSubsystem shake branch).
const _SHAKE := ["SHAKE_DAMPED", "SHAKE_DAMPED_B", "SHAKE_DIRECT"]

# Zoom is a NO-OP under these source modes: _execute_zoom_command (CameraSubsystem.gd:493-495,
# the 0x801… camera path) early-returns for OFFSET/CURSOR before setting up any tween — even a
# SHAKE interp does nothing. Angle/position have no such dead mode; only zoom does.
const _ZOOM_INERT := ["OFFSET", "CURSOR"]

# Anchor-relative angle modes: yaw = facing+kf (offset), pitch/roll = current+kf (Δ).
const _ANGLE_ANCHOR := ["TARGET", "CASTER", "CURSOR", "EFFECT_CTR", "ALL_TARGETS"]


## Human label for a value row = base name + a mode-derived suffix. `comp` is the vector
## component (0/1/2 = pitch/yaw/roll or x/y/z); zoom ignores it.
static func label(base: String, channel: String, comp: int, source_mode: String, interpolation: String) -> String:
	return base + _suffix(channel, comp, source_mode, interpolation)


## True when a SHAKE_* interpolation makes the value a symmetric ± amplitude rather than a
## target/offset/Δ — the same predicate that drives the "amplitude" suffix, exposed so the
## projector can decorate the value display (± prefix) without re-listing the SHAKE set.
static func is_amplitude(interpolation: String) -> bool:
	return interpolation in _SHAKE


## True when the value is stored but the runtime never applies it — the "(inert)" suffix.
## Only zoom under OFFSET/CURSOR today (the runtime early-returns for those). Exposed so the
## projector can drop the "±" amplitude decoration on an inert row (a no-op is neither a
## target nor a shake peak).
static func is_inert(channel: String, source_mode: String) -> bool:
	return channel == "zoom" and source_mode in _ZOOM_INERT


## True when the event OWNS ITS SPAN AND MOVES NOTHING — a SPACER (ADR-0086 `MAP`-delta
## amendment), which the score timeline renders as empty space.
##
## The predicate is `MAP` + a zero value, and it is decidable LOCALLY. `MAP` is the one source
## mode that resolves against the camera's OWN current value (`_execute_*_command`:
## `to = current + kf`), so a zero gives `to == from` and every interpolation branch holds the
## pose — a lerp from/to the same point, a zero ADDITIVE step, a zero SHAKE amplitude. Every
## other mode resolves against something external (an anchor, the saved slot) or writes
## absolutely, so a zero there is a real move — under `DIRECT`, zoom `0` means zoom TO zero.
##
## No fold is needed (unlike the colour lanes' `SpacerVerdicts`): `CameraSubsystem.advance`
## searches for a keyframe only on an IDLE channel, so a camera event never preempts a running
## tween and carries no stream context.
##
## `value` is the sub-channel's own vector — ZOOM READS `.x` ALONE, mirroring
## `_execute_zoom_command`'s `float(kf.zoom.x)`; its y/z are storage padding the runtime ignores.
static func is_spacer(channel: String, source_mode: String, value: Vector3i) -> bool:
	if source_mode != "MAP":
		return false
	if channel == "zoom":
		return value.x == 0
	return value == Vector3i.ZERO


static func _suffix(channel: String, comp: int, source_mode: String, interpolation: String) -> String:
	# Inert takes precedence over every other role — the runtime early-returns for these modes
	# BEFORE the shake branch, so an inert zoom never shakes despite a SHAKE_* interp.
	if is_inert(channel, source_mode):
		return _INERT
	if is_amplitude(interpolation):
		return _AMPLITUDE
	match channel:
		"angle": return _angle_role(comp, source_mode)
		"position": return _position_role(source_mode)
		"zoom": return _zoom_role(source_mode)
	return _ABSOLUTE


## Mirrors _execute_angle_command: the yaw component (1) anchors to facing/saved while
## pitch(0)/roll(2) track current — so the role is per-component, not per-mode.
static func _angle_role(comp: int, source_mode: String) -> String:
	match source_mode:
		"DIRECT":
			return _ABSOLUTE  # pitch/yaw/roll = kf
		"OFFSET":
			return _ABSOLUTE if comp == 0 else _DELTA  # pitch = kf; yaw/roll = current+kf
		"MAP":
			return _DELTA  # all = current+kf
		"SLOT_COPY":
			return _OFFSET  # all = saved+kf
		"ORIGIN":
			return _OFFSET if comp == 0 else _DELTA  # pitch = saved+kf; yaw/roll = current+kf
		_:
			# Anchor modes (TARGET/CASTER/CURSOR/EFFECT_CTR/ALL_TARGETS): yaw = facing+kf.
			if source_mode in _ANGLE_ANCHOR:
				return _OFFSET if comp == 1 else _DELTA
			return _ABSOLUTE


## Mirrors _execute_position_command — uniform across x/y/z within a mode.
static func _position_role(source_mode: String) -> String:
	match source_mode:
		"DIRECT": return _ABSOLUTE       # = kf
		"MAP": return _DELTA             # = current+kf
		"SLOT_COPY", "ORIGIN": return _OFFSET  # = saved+kf
		_:
			# TARGET/CASTER/CURSOR/EFFECT_CTR/ALL_TARGETS: anchor+kf.
			return _OFFSET if source_mode in _ANGLE_ANCHOR else _ABSOLUTE


## Mirrors _execute_zoom_command — MAP adds to current, SLOT_COPY to saved, else absolute.
## OFFSET/CURSOR never reach here: they are intercepted as inert (is_inert) since the runtime
## no-ops them.
static func _zoom_role(source_mode: String) -> String:
	match source_mode:
		"MAP": return _DELTA
		"SLOT_COPY": return _OFFSET
		_: return _ABSOLUTE
