class_name EmitterFieldRelevance
extends RefCounted
## The emitter field-relevance ORACLE (ADR-0089 salience amendment), generated
## from the Field Dependency Inventory below. It answers, per parameter group and
## per gated field, "is this field actually doing anything?" — one of three states:
##
##   LIVE     — read by the sim AND its value changes the output. Rendered normally.
##   INACTIVE — read every frame, but its value is the group's NEUTRAL so its term
##              drops out of the simulation. Fully wired; an author edits it to wake
##              it. Neutral is 0 for the additive terms, the identity divisor 4096
##              for inertia (empirically checked — see the sim guard). Shown
##              collapsed + marked, never hidden.
##   DEAD     — a gate provably deads it given its siblings' current values, so
##              editing it does nothing. Hidden behind a per-section reveal.
##
## The inventory's *gated-by* / *gates* columns are the edges of a directed
## annihilation graph; every DEAD edge is backed by a real-sim guard
## (EmitterFieldRelevanceSimGuardTest) that sets the gate in the actual engine and
## asserts the gated field cannot move output. This supersedes ADR-0089 decision
## 3's ad-hoc "dim all-zero groups" heuristic (which conflated Dead/Inactive and
## missed inertia = 4096).
##
## Pure model: it reads the live emitter through EmitterChannel.read_raw (the ONE
## field→storage map, so the oracle can never desync from what the editor writes)
## and returns display-agnostic verdicts. The projector attaches them to rows; the
## inspector renders them.

const EmitterChannel = preload("res://src/effects/studio/EmitterChannel.gd")

const LIVE := "live"
const INACTIVE := "inactive"
const DEAD := "dead"

# ── The Field Dependency Inventory ────────────────────────────────────────────
# One row per two-axis parameter group. Columns:
#   kind     — storage shape (drives which raw fields the group reads).
#   curve    — the curve-assignment nibble field key (read_raw "curve_<curve>");
#              curve == 0 (none) deads the group's END axis (interpolate_* returns
#              `start` unread when curve == null — ParticlePhysics.gd).
#   neutral  — the value at which the group is INACTIVE (its term drops out):
#              0 for the additive terms; 4096 for inertia (the identity divisor);
#              a NAMED sentinel for the groups that are never merely Inactive.
# The named neutrals encode the model's asymmetries:
#   "spatial"  — Position / Target offset: offset 0 = spawn/aim AT the anchor, a
#                real place, so never Inactive.
#   "count"    — Particles per burst: 0 is the louder "this emitter emits nothing".
#   "cadence"  — Spawn interval: always Live (it gates the spawn clock).
#   "lifetime" — Lifetime: −1 is the animation-driven sentinel; never merely Inactive.
#   "momentum" — Inertia: the ADR's guessed 4096 neutral is REFUTED (its identity
#                depends on the particle-header inertia_threshold, which the oracle
#                does not model — at the default 512, inertia 4096 decays velocity
#                ×0.875). No header-independent neutral ⇒ inertia is never Inactive.
const _INV := {
	"position": {"kind": "vec3", "curve": "position", "neutral": "spatial"},
	"spread": {"kind": "vec3", "curve": "spread", "neutral": 0},
	"velocity_base_angle": {"kind": "vec3", "curve": "velocity_base_angle", "neutral": 0},
	"velocity_direction_spread": {"kind": "vec3", "curve": "velocity_dir_spread", "neutral": 0},
	"inertia": {"kind": "range", "curve": "inertia", "neutral": "momentum"},
	"weight": {"kind": "range", "curve": "weight", "neutral": 0},
	"radial_velocity": {"kind": "range", "curve": "radial_velocity", "neutral": 0},
	"acceleration": {"kind": "vec3_range", "curve": "acceleration", "neutral": 0},
	"drag": {"kind": "vec3_range", "curve": "drag", "neutral": 0},
	"lifetime": {"kind": "range", "curve": "lifetime", "neutral": "lifetime"},
	"target_offset": {"kind": "vec3", "curve": "target_offset", "neutral": "spatial"},
	"particle_count": {"kind": "pair", "curve": "particle_count", "neutral": "count"},
	"spawn_interval": {"kind": "pair", "curve": "spawn_interval", "neutral": "cadence"},
	"homing_strength": {"kind": "range", "curve": "homing_strength", "neutral": 0},
}


## The oracle: verdicts for every parameter group + gated field of `em`.
## Returns {"groups": {<id>: Verdict}, "fields": {<field>: Verdict}} where a
## Verdict is {state, why, gated_by, end_dead, end_why, gates}. `groups` holds the
## two-axis parameter groups; `fields` holds lone gated fields (over-life curves,
## child-emitter indices) and — via `gates` — the config switches that dead them.
static func verdicts(em) -> Dictionary:
	var groups: Dictionary = {}
	for id in _INV:
		groups[id] = _group_verdict(em, id)
	var fields: Dictionary = {}

	# Homing gate: when homing strength is provably always zero, the spawn never
	# reads target offset (ActiveEmitter) and the physics never samples the homing
	# blend curve (ParticlePhysics). The gate is `!= 0` — negative repels, still Live.
	var homing_off := _all_read_values_equal(em, "homing_strength", 0)
	if homing_off:
		groups["target_offset"] = _dead(_verdict(), "homing_strength",
			"target offset unused — homing strength is 0")
		fields["homing_blend"] = _dead(_verdict(), "homing_strength",
			"homing blend unused — homing strength is 0")
	else:
		fields["homing_blend"] = _verdict()

	# Colour-enable gate: with flags_lo bit 6 off, EffectParticleRenderer caches
	# null colour curves and the modulate stays white — the three colour curves
	# are Dead, gated by the enable switch.
	var color_on := EmitterChannel.read_raw(em, "color_curve_enable") != 0
	for ch in ["r", "g", "b"]:
		if color_on:
			fields["color_curve_" + ch] = _verdict()
		else:
			fields["color_curve_" + ch] = _dead(_verdict(), "color_curve_enable",
				"colour (%s) unused — colour curves are disabled" % ch.to_upper())

	# Child-mode gate: ParticleSubsystem spawns a child only when the parent's
	# child mode is enabled (flags_lo bits 0-1 / 2-3 non-zero). A disabled (zero)
	# mode deads that child-emitter index — editing it wires nothing.
	for edge in [["child_emitter_on_death", "child_death_mode", "on-death"],
			["child_emitter_mid_life", "child_midlife_mode", "mid-life"]]:
		if EmitterChannel.read_raw(em, edge[1]) == 0:
			fields[edge[0]] = _dead(_verdict(), edge[1],
				"%s child unused — its spawn mode is disabled" % edge[2])
		else:
			fields[edge[0]] = _verdict()

	# Gate switches are never hidden (they are the knob the author throws), so give
	# each a verdict slot to carry its reverse edges even when it suppresses nothing.
	# The velocity-family flags join the slot loop so _link_reverse_edges hangs their
	# "Suppressing: …" markers on the "Pull velocity inward" / "Align to unit facing"
	# config rows (radial_velocity is already a group and carries its edge like homing).
	for gate in ["color_curve_enable", "child_death_mode", "child_midlife_mode",
			"velocity_inward", "align_to_facing"]:
		if not fields.has(gate):
			fields[gate] = _verdict()

	_apply_velocity_gates(em, groups, fields)
	_apply_velocity_consumer_gate(em, groups)
	_link_reverse_edges(groups, fields)
	return {"groups": groups, "fields": fields}


## The velocity-family annihilation gate (ADR-0089 velocity amendment). Spawn velocity
## is direction × magnitude in a mode selected by velocity_inward (flags_lo bit 4) and
## align_to_facing (flags_hi bit 2) — the 4-mode dispatch in
## ActiveEmitter._initialize_particle (lines 95-145). A field that provably cannot move
## the spawned velocity is DEAD, OVERWRITING its own Live/Inactive (Dead wins). Three
## branches (Outward and Unit-oriented share one rule — both compute direction × speed):
##   Skip   (facing only)     — velocity = 0: direction AND outward speed Dead, gated by
##                              align_to_facing.
##   Inward (inward only)     — (toward center) × speed: direction omitted from the
##                              formula ⇒ Dead ALWAYS, gated by velocity_inward. Speed
##                              stays Live (it scales the inward vector).
##   Outward / Unit-oriented  — direction × speed: direction Dead IFF speed provably 0,
##                              gated by radial_velocity (curve-aware — a radial that
##                              ramps 0→nonzero keeps direction Live, conservatively).
##                              Speed itself is only Inactive at 0, never Dead.
## Each guarded in EmitterFieldRelevanceSimGuardTest against the real ActiveEmitter.
static func _apply_velocity_gates(em, groups: Dictionary, _fields: Dictionary) -> void:
	var inward := EmitterChannel.read_raw(em, "velocity_inward") != 0
	var facing := EmitterChannel.read_raw(em, "align_to_facing") != 0
	var dir := ["velocity_base_angle", "velocity_direction_spread"]
	if facing and not inward:
		# Skip: velocity is a constant zero — nothing in the family moves output.
		for id in dir:
			_dead(groups[id], "align_to_facing",
				"%s unused — \"Align to unit facing\" zeroes velocity" % _label(id))
		_dead(groups["radial_velocity"], "align_to_facing",
			"Outward speed unused — \"Align to unit facing\" zeroes velocity")
	elif inward and not facing:
		# Inward: the launch angle is omitted from the (toward center) × speed formula.
		for id in dir:
			_dead(groups[id], "velocity_inward",
				"%s unused — velocity aims inward, not by launch angle" % _label(id))
	elif _all_read_values_equal(em, "radial_velocity", 0):
		# Outward / Unit-oriented with speed provably 0: direction × 0 = 0.
		for id in dir:
			_dead(groups[id], "radial_velocity",
				"%s unused — outward speed is 0, so direction × 0 = 0" % _label(id))


## THE VELOCITY-CONSUMER GATE (ADR-0089 velocity amendment 2). Inertia only DECAYS an existing
## velocity — ParticlePhysics.update_particle_fixed computes new_v = (inertia_factor·old_v +
## accel·4096) / inertia, then position += old_v. So when the particle's velocity is provably
## ZERO for all time, the inertia divisor can never move any output: it is Dead. Velocity is
## always zero iff EVERY source is zero:
##   • spawn velocity 0  — Skip mode, or radial (outward speed) provably 0 (all modes launch at
##                         direction/toward × radial);
##   • acceleration 0    — the initial spawn acceleration;
##   • drag 0            — drag is a constant FORCE here (`accel += drag` each frame), a velocity
##                         SOURCE, not a consumer, so a non-zero drag creates motion from rest;
##   • weight (gravity) 0 — gravity·weight/4096 is added to velocity every frame;
##   • homing_strength 0  — homing steers acceleration toward the target.
## Guarded in EmitterFieldRelevanceSimGuardTest: inertia is moot at rest, and each non-zero
## source (drag / weight / spawn speed) revives it. Drag is NOT itself Dead-gated here — it is a
## source, proven to move output from rest. Compound condition ⇒ no single reverse gate host.
static func _apply_velocity_consumer_gate(em, groups: Dictionary) -> void:
	var inward := EmitterChannel.read_raw(em, "velocity_inward") != 0
	var facing := EmitterChannel.read_raw(em, "align_to_facing") != 0
	var skip_mode := facing and not inward
	var spawn_velocity_zero := skip_mode or _all_read_values_equal(em, "radial_velocity", 0)
	if spawn_velocity_zero \
			and _all_read_values_equal(em, "acceleration", 0) \
			and _all_read_values_equal(em, "drag", 0) \
			and _all_read_values_equal(em, "weight", 0) \
			and _all_read_values_equal(em, "homing_strength", 0):
		_dead(groups["inertia"], "",
			"inertia unused — the particle never moves (no launch speed, acceleration, drag, gravity, or homing to create velocity)")


## THE FORMULA VIEW (ADR-0089 velocity amendment, decision 2). A pure descriptor for
## the velocity Dead-reveal section, rendered ONCE and ONLY when something in the
## family is Dead — returns {} for a fully-Live Outward emitter. It exposes the active
## mode-selected formula with its annihilating factor(s) marked, the labels of the Dead
## fields, and an imperative fix line naming flag LABELS (never mode-name jargon).
##
## Marked factors obey the guard-rail: mark a zero factor as annihilating a field only
## when that field is a LIVE FACTOR in the active formula. When the mode instead OMITS
## the field (direction under Inward, everything under Skip), the mode switch is the
## culprit — no zero sibling is marked (marked_factors stays empty). In the velocity
## family only Outward's `direction × speed(0)` has a marked factor; the set machinery
## is kept for honesty and later compound expressions (pos = pos0 + v·t + ½a·t²).
static func velocity_formula(em) -> Dictionary:
	var inward := EmitterChannel.read_raw(em, "velocity_inward") != 0
	var facing := EmitterChannel.read_raw(em, "align_to_facing") != 0
	var dir_labels := [_label("velocity_base_angle"), _label("velocity_direction_spread")]
	if facing and not inward:
		# Skip: velocity is a constant zero — direction AND speed are omitted, no factor.
		return {
			"mode": "skip",
			"formula": "velocity = 0",
			"marked_factors": [],
			"unused_labels": dir_labels + [_label("radial_velocity")],
			"reason": "no motion",
			"fix": "turn off \"Align to unit facing\"",
		}
	if inward and not facing:
		# Inward: direction is omitted from (toward center) × speed — mode, not a zero factor.
		return {
			"mode": "inward",
			"formula": "velocity = (toward center) × speed",
			"marked_factors": [],
			"unused_labels": dir_labels,
			"reason": "not in this formula",
			"fix": "turn off \"Pull velocity inward\" to aim them",
		}
	# Outward / Unit-oriented: direction × speed — direction Dead iff speed provably 0,
	# and speed IS the marked annihilator (direction is a live factor forced to zero).
	if _all_read_values_equal(em, "radial_velocity", 0):
		return {
			"mode": "outward",
			"formula": "velocity = direction × speed",
			"marked_factors": ["speed"],
			"unused_labels": dir_labels,
			"reason": "speed annihilates them",
			"fix": "set Outward speed > 0",
		}
	return {}


## A stable string of the RENDER-AFFECTING relevance facts — every group's state +
## end-axis-dead flag and every field's state. Two emitters with the same signature
## project the same salience markers (the `!` glyphs, the dimming, the hidden-Dead
## reveal membership), so the page compares this across a plain value edit to decide
## whether the inspector must reproject (a verdict flipped — a woken Inactive field,
## a numeric homing gate crossing 0) or can leave the live spinbox untouched (an
## ordinary in-range nudge moved nothing). Gate `!` markers are downstream of the
## Dead states already captured, so they need no separate term. Keys are sorted so
## the string is order-independent.
static func render_signature(em) -> String:
	var v := verdicts(em)
	var parts: Array = []
	var groups: Dictionary = v.get("groups", {})
	var gkeys: Array = groups.keys()
	gkeys.sort()
	for id in gkeys:
		var g: Dictionary = groups[id]
		parts.append("g:%s=%s/%s" % [id, str(g.get("state", "")), str(g.get("end_dead", false))])
	var fields: Dictionary = v.get("fields", {})
	var fkeys: Array = fields.keys()
	fkeys.sort()
	for k in fkeys:
		parts.append("f:%s=%s" % [k, str(fields[k].get("state", ""))])
	return "|".join(parts)


## Bidirectional markers: invert every Dead edge so each gate carries a `gates`
## list of what it is currently suppressing (hover = "what I'm suppressing"). The
## dependency is then navigable from the switch, where the author acts. A gate
## lives in `groups` (homing_strength) or `fields` (the config switches).
static func _link_reverse_edges(groups: Dictionary, fields: Dictionary) -> void:
	for scope in [groups, fields]:
		for id in scope:
			var v: Dictionary = scope[id]
			var gate: String = str(v.get("gated_by", ""))
			if gate == "" or v.get("state", "") != DEAD:
				continue
			var host: Dictionary = groups[gate] if groups.has(gate) else fields.get(gate, {})
			if host.is_empty():
				continue
			host["gates"].append({"target": id, "why": str(v.get("why", ""))})


## A fresh Live verdict.
static func _verdict() -> Dictionary:
	return {"state": LIVE, "why": "", "gated_by": "", "end_dead": false, "end_why": "", "gates": []}


## Stamp a verdict Dead, gated by `gate`, with the why-string.
static func _dead(v: Dictionary, gate: String, why: String) -> Dictionary:
	v["state"] = DEAD
	v["gated_by"] = gate
	v["why"] = why
	return v


## The whole-group + end-axis verdict for one parameter group.
static func _group_verdict(em, id: String) -> Dictionary:
	var spec: Dictionary = _INV[id]
	var v := _verdict()

	# End-axis Dead edge (guarded): curve == none ⇒ interpolate_* returns `start`
	# and never reads the end axis, so the end column is Dead — collapse it in place.
	if EmitterChannel.read_raw(em, "curve_" + str(spec["curve"])) == 0:
		v["end_dead"] = true
		v["end_why"] = "end unused — no curve"

	var neutral = spec["neutral"]
	# Only the numeric-neutral groups can be Inactive; the named sentinels
	# ("spatial"/"count"/"cadence"/"lifetime") are never merely Inactive.
	if neutral is int or neutral is float:
		if _all_read_values_equal(em, id, int(neutral)):
			v["state"] = INACTIVE
			v["why"] = _inactive_why(id, int(neutral))
	return v


## Every raw value the sim READS for this group, at the current curve assignment.
## With no curve the END axis is unread (interpolate_* returns `start`), so it is
## excluded — an Inactive verdict must reflect what the engine actually consumes.
static func _all_read_values_equal(em, id: String, neutral: int) -> bool:
	var has_curve := EmitterChannel.read_raw(em, "curve_" + str(_INV[id]["curve"])) != 0
	for field in _read_fields(em, id, has_curve):
		if EmitterChannel.read_raw(em, field) != neutral:
			return false
	return true


## The read_raw field names for a group by storage kind. `include_end` adds the
## end-axis fields (dropped when the group has no curve — end is unread).
static func _read_fields(_em, id: String, include_end: bool) -> Array:
	var kind: String = str(_INV[id]["kind"])
	var out: Array = []
	match kind:
		"vec3":
			for c in ["x", "y", "z"]:
				out.append("%s_start_%s" % [id, c])
			if include_end:
				for c in ["x", "y", "z"]:
					out.append("%s_end_%s" % [id, c])
		"range":
			out += ["%s_min_start" % id, "%s_max_start" % id]
			if include_end:
				out += ["%s_min_end" % id, "%s_max_end" % id]
		"pair":
			out.append("%s_start" % id)
			if include_end:
				out.append("%s_end" % id)
		"vec3_range":
			for side in ["min_start", "max_start"]:
				for c in ["x", "y", "z"]:
					out.append("%s_%s_%s" % [id, side, c])
			if include_end:
				for side in ["min_end", "max_end"]:
					for c in ["x", "y", "z"]:
						out.append("%s_%s_%s" % [id, side, c])
	return out


## The human why-string for an Inactive group.
static func _inactive_why(id: String, neutral: int) -> String:
	if neutral == 4096:
		return "%s is at neutral (×1.0) — its term drops out." % _label(id)
	return "%s is zero — its term drops out." % _label(id)


const _LABELS := {
	"spread": "Spawn scatter", "velocity_base_angle": "Launch direction",
	"velocity_direction_spread": "Direction scatter", "inertia": "Inertia",
	"weight": "Gravity scale", "radial_velocity": "Outward speed",
	"acceleration": "Acceleration", "drag": "Drag", "position": "Position",
	"lifetime": "Lifetime", "target_offset": "Target offset",
	"particle_count": "Particles per burst", "spawn_interval": "Spawn every N frames",
	"homing_strength": "Homing strength",
}


static func _label(id: String) -> String:
	return str(_LABELS.get(id, id))
