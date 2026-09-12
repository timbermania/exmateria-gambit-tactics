extends Node
## TDD guard for EmitterFieldRelevance (ADR-0089 field-relevance salience amendment)
## — the relevance ORACLE, generated from the Field Dependency Inventory. Given a
## shared emitter it returns a per-group / per-field verdict: Live (read + value
## changes output), Inactive (read but at the group's NEUTRAL so its term drops
## out — wake-able, never hidden), or Dead (a gate provably deads it — hidden).
##
## This file is the pure-oracle seam. Each DEAD edge additionally carries a
## real-sim guard (EmitterFieldRelevanceSimGuardTest) that sets the gate in the
## actual sim and asserts the gated field cannot move output — the static-rooted /
## dynamically-validated rule, so the inventory can never drift from the engine.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EmitterFieldRelevanceTest.tscn

const Oracle = preload("res://src/effects/studio/EmitterFieldRelevance.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_additive_group_inactive_when_all_zero()
	_test_additive_group_live_when_nonzero()
	_test_additive_terms_are_neutral_zero()
	_test_velocity_direction_dead_outward_radial_zero()
	_test_velocity_direction_live_outward_radial_nonzero()
	_test_velocity_direction_dead_inward_regardless_of_radial()
	_test_velocity_whole_family_dead_skip_mode()
	_test_velocity_unit_oriented_follows_outward_radial_rule()
	_test_velocity_gate_carries_reverse_edges()
	_test_signature_changes_when_radial_undeads_launch_direction()
	_test_velocity_formula_empty_when_family_live()
	_test_velocity_formula_outward_marks_speed()
	_test_velocity_formula_inward_marks_mode_not_zero_sibling()
	_test_velocity_formula_skip_lists_whole_family()
	_test_position_is_never_inactive()
	_test_end_axis_dead_when_group_has_no_curve()
	_test_end_axis_live_when_curve_assigned()
	_test_target_offset_dead_when_homing_zero()
	_test_target_offset_live_when_homing_nonzero()
	_test_homing_gate_is_nonzero_not_positive()
	_test_homing_blend_dead_when_homing_zero()
	_test_color_curves_dead_when_color_disabled()
	_test_color_curves_live_when_color_enabled()
	_test_child_index_dead_when_mode_disabled()
	_test_child_index_live_when_mode_enabled()
	_test_inertia_is_never_inactive_4096_refuted()
	_test_inertia_dead_when_velocity_provably_zero()
	_test_inertia_live_when_drag_creates_velocity()
	_test_inertia_live_when_gravity_creates_velocity()
	_test_inertia_live_when_spawn_velocity_nonzero()
	_test_gate_switch_carries_reverse_edges()
	_test_gate_clears_reverse_edges_when_open()
	_test_signature_changes_when_inactive_group_wakes()
	_test_signature_stable_when_live_value_nudged()
	_test_signature_changes_when_homing_gate_deads_target_offset()

	print("\n=== EmitterFieldRelevanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EmitterFieldRelevanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EmitterFieldRelevanceTest")
		get_tree().quit(0)


## An additive term (Acceleration) sitting at its neutral (all zero) is Inactive —
## read every frame but adding nothing, so the term drops out. Shown collapsed +
## marked, never hidden: its why-string explains it is at neutral.
func _test_additive_group_inactive_when_all_zero() -> void:
	var em = _emitter()  # fresh: every additive term at zero
	var g: Dictionary = Oracle.verdicts(em)["groups"]["acceleration"]
	_assert_eq(g.get("state", ""), Oracle.INACTIVE, "all-zero Acceleration is Inactive")
	_assert_true(str(g.get("why", "")) != "", "an Inactive group carries a why-string")


## Author a non-zero value into an additive term and it wakes to Live.
func _test_additive_group_live_when_nonzero() -> void:
	var em = _emitter()
	em.raw_data["accel_min_start"] = [1, 0, 0]
	var g: Dictionary = Oracle.verdicts(em)["groups"]["acceleration"]
	_assert_eq(g.get("state", ""), Oracle.LIVE, "a non-zero Acceleration is Live")


## The additive terms that take neutral zero — at rest (all zero, Outward mode) they
## are Inactive: read every frame but adding nothing. The velocity DIRECTION fields
## are the exception: at radial 0 they are Dead (annihilated), not Inactive — see the
## velocity-annihilation tests below. Outward speed at 0 is the annihilating zero
## factor but is itself only Inactive (a real knob the author wakes).
func _test_additive_terms_are_neutral_zero() -> void:
	var em = _emitter()
	var groups: Dictionary = Oracle.verdicts(em)["groups"]
	for id in ["radial_velocity", "weight", "drag", "acceleration"]:
		_assert_eq(groups[id].get("state", ""), Oracle.INACTIVE,
			"%s is Inactive at zero" % id)


## VELOCITY-FAMILY ANNIHILATION GATE (ADR-0089 velocity amendment). Spawn velocity is
## direction × magnitude in a mode selected by velocity_inward + align_to_facing; a
## field that provably cannot move it is Dead (proven in EmitterFieldRelevanceSimGuardTest,
## the source of truth). The oracle mirrors the three sim branches.

## Outward (neither flag), radial provably 0: direction × 0 = 0, so launch direction
## and direction scatter are Dead, gated by radial_velocity — the zero factor that is
## itself only Inactive (a wake-able knob), not Dead.
func _test_velocity_direction_dead_outward_radial_zero() -> void:
	var em = _emitter()  # no flags → Outward; radial 0
	var groups: Dictionary = Oracle.verdicts(em)["groups"]
	for id in ["velocity_base_angle", "velocity_direction_spread"]:
		_assert_eq(groups[id].get("state", ""), Oracle.DEAD, "%s is Dead in Outward radial 0" % id)
		_assert_eq(str(groups[id].get("gated_by", "")), "radial_velocity",
			"…gated by outward speed (%s)" % id)
	_assert_eq(groups["radial_velocity"].get("state", ""), Oracle.INACTIVE,
		"outward speed is Inactive at 0 (the annihilating zero factor, not itself Dead)")


## Outward with radial > 0: the direction fields wake — direction × speed is Live.
func _test_velocity_direction_live_outward_radial_nonzero() -> void:
	var em = _emitter()
	em.raw_data["radial_min_start"] = 100
	var groups: Dictionary = Oracle.verdicts(em)["groups"]
	_assert_true(groups["velocity_base_angle"].get("state", "") != Oracle.DEAD,
		"launch direction is not Dead when outward speed is non-zero")


## Inward (velocity_inward only): direction is omitted from (toward center) × speed,
## so launch direction + scatter are Dead ALWAYS (even at radial > 0), gated by the
## inward flag. Outward speed stays Live (it scales the inward vector).
func _test_velocity_direction_dead_inward_regardless_of_radial() -> void:
	var em = _emitter()
	em.raw_data["emitter_flags_lo"] = 0x10  # velocity_inward = flags_lo bit 4
	em.raw_data["radial_min_start"] = 100    # radial > 0 — still Dead (mode omits direction)
	var groups: Dictionary = Oracle.verdicts(em)["groups"]
	for id in ["velocity_base_angle", "velocity_direction_spread"]:
		_assert_eq(groups[id].get("state", ""), Oracle.DEAD, "%s is Dead in Inward mode" % id)
		_assert_eq(str(groups[id].get("gated_by", "")), "velocity_inward",
			"…gated by the inward flag (%s)" % id)
	_assert_true(groups["radial_velocity"].get("state", "") != Oracle.DEAD,
		"outward speed stays Live in Inward mode (it scales the inward vector)")


## Skip (align_to_facing only, inward off): velocity = 0, so the WHOLE family — launch
## direction, direction scatter, AND outward speed — is Dead, gated by the facing flag.
func _test_velocity_whole_family_dead_skip_mode() -> void:
	var em = _emitter()
	em.raw_data["emitter_flags_hi"] = 0x04  # align_to_facing = flags_hi bit 2
	em.raw_data["radial_min_start"] = 100    # even a non-zero speed is Dead (velocity = 0)
	var groups: Dictionary = Oracle.verdicts(em)["groups"]
	for id in ["velocity_base_angle", "velocity_direction_spread", "radial_velocity"]:
		_assert_eq(groups[id].get("state", ""), Oracle.DEAD, "%s is Dead in Skip mode" % id)
		_assert_eq(str(groups[id].get("gated_by", "")), "align_to_facing",
			"…gated by the facing flag (%s)" % id)


## Unit-oriented (both flags) collapses to the Outward rule: direction × speed rotated
## by facing, so direction is Dead iff radial provably 0 (NOT always, unlike Inward/Skip).
func _test_velocity_unit_oriented_follows_outward_radial_rule() -> void:
	var em = _emitter()
	em.raw_data["emitter_flags_lo"] = 0x10  # inward
	em.raw_data["emitter_flags_hi"] = 0x04  # facing → both = Unit-oriented
	em.raw_data["radial_min_start"] = 100    # radial > 0 → direction Live
	var groups: Dictionary = Oracle.verdicts(em)["groups"]
	_assert_true(groups["velocity_base_angle"].get("state", "") != Oracle.DEAD,
		"Unit-oriented radial > 0: launch direction is Live (dir × speed, like Outward)")


## Bidirectional markers on the velocity gate: in Outward radial-0 the outward-speed
## group (the annihilating zero factor) lists the two direction groups it suppresses;
## in Inward mode the inward config switch carries the reverse edges.
func _test_velocity_gate_carries_reverse_edges() -> void:
	var radial_gate: Array = Oracle.verdicts(_emitter())["groups"]["radial_velocity"].get("gates", [])
	_assert_eq(_targets(radial_gate), ["velocity_base_angle", "velocity_direction_spread"],
		"outward speed lists the direction groups it annihilates")

	var em2 = _emitter()
	em2.raw_data["emitter_flags_lo"] = 0x10  # Inward
	var inward_gate: Array = Oracle.verdicts(em2)["fields"]["velocity_inward"].get("gates", [])
	_assert_eq(_targets(inward_gate), ["velocity_base_angle", "velocity_direction_spread"],
		"the inward flag lists the direction groups it suppresses")


## render_signature: radial 0 → nonzero un-deads the direction fields, so the signature
## MUST change (the page reprojects; the Dead fold moves back to a Live inline group).
func _test_signature_changes_when_radial_undeads_launch_direction() -> void:
	var em = _emitter()  # Outward radial 0 → direction Dead
	var before := Oracle.render_signature(em)
	em.raw_data["radial_min_start"] = 100  # radial > 0 → direction wakes
	_assert_true(Oracle.render_signature(em) != before,
		"radial 0→nonzero un-deads launch direction → render signature changes")


## THE FORMULA VIEW (ADR-0089 velocity amendment, decision 2). A pure descriptor
## rendered once under the velocity Dead-reveal, only when something in the family is
## Dead. It marks all-applicable annihilators under the guard-rail: a zero factor is
## marked ONLY when the Dead field is a live factor in the active formula; when the
## mode omits the field, the mode switch is the culprit, not the zero sibling. Flag
## LABELS, never mode-name jargon.

## No formula view when the whole velocity family is Live (a fully-Live Outward emitter).
func _test_velocity_formula_empty_when_family_live() -> void:
	var em = _emitter()
	em.raw_data["radial_min_start"] = 100  # Outward radial > 0 → direction Live
	_assert_true(Oracle.velocity_formula(em).is_empty(),
		"no formula view when the whole velocity family is Live")


## Outward radial 0: velocity = direction × speed, speed is the marked annihilator
## (direction IS a live factor here, forced to zero by speed).
func _test_velocity_formula_outward_marks_speed() -> void:
	var d: Dictionary = Oracle.velocity_formula(_emitter())  # Outward radial 0
	_assert_eq(str(d.get("mode", "")), "outward", "Outward radial 0 → outward formula")
	_assert_true("direction" in str(d.get("formula", "")) and "speed" in str(d.get("formula", "")),
		"formula reads direction × speed")
	_assert_eq(d.get("marked_factors", []), ["speed"],
		"speed is marked as the annihilator (a live factor forced to zero)")
	_assert_true("Launch direction" in d.get("unused_labels", []) \
			and "Direction scatter" in d.get("unused_labels", []),
		"the Dead direction fields are named by their labels, not mode jargon")
	_assert_true("Outward speed" in str(d.get("fix", "")),
		"the fix line is imperative — set Outward speed > 0")


## Inward, radial still 0: GUARD-RAIL — direction is omitted by the mode, so speed
## (even at 0) is NOT marked as annihilating it; the mode switch is the culprit.
func _test_velocity_formula_inward_marks_mode_not_zero_sibling() -> void:
	var em = _emitter()
	em.raw_data["emitter_flags_lo"] = 0x10  # Inward, radial still 0
	var d: Dictionary = Oracle.velocity_formula(em)
	_assert_eq(str(d.get("mode", "")), "inward", "Inward → inward formula")
	_assert_eq(d.get("marked_factors", []), [],
		"Inward marks no zero factor — direction isn't a factor of (toward center) × speed")
	_assert_true("Pull velocity inward" in str(d.get("fix", "")),
		"the fix names the flag label to turn off, not the mode name")


## Skip: velocity = 0 (constant), no factor to mark; the whole family is listed unused.
func _test_velocity_formula_skip_lists_whole_family() -> void:
	var em = _emitter()
	em.raw_data["emitter_flags_hi"] = 0x04  # Skip
	var d: Dictionary = Oracle.velocity_formula(em)
	_assert_eq(str(d.get("mode", "")), "skip", "Skip → skip formula")
	_assert_eq(str(d.get("formula", "")), "velocity = 0", "Skip formula is the constant zero")
	_assert_eq(d.get("marked_factors", []), [], "constant zero has no annihilating factor to mark")
	for lbl in ["Launch direction", "Direction scatter", "Outward speed"]:
		_assert_true(lbl in d.get("unused_labels", []), "Skip lists %s as unused" % lbl)
	_assert_true("Align to unit facing" in str(d.get("fix", "")), "the fix names the facing flag")


## Asymmetry: Position at offset zero means "spawn AT the anchor" — a real place,
## not nothing. Position is NEVER Inactive.
func _test_position_is_never_inactive() -> void:
	var em = _emitter()  # position all zero
	var g: Dictionary = Oracle.verdicts(em)["groups"]["position"]
	_assert_eq(g.get("state", ""), Oracle.LIVE, "Position is Live even at offset zero")


## Proven DEAD edge (guarded in EmitterFieldRelevanceSimGuardTest): with no curve
## assigned, interpolate_* returns `start` and never reads the end axis. So a
## curve-less group's END axis is Dead — the oracle flags it for the inspector to
## collapse the end column in place, with an "end unused — no curve" note.
func _test_end_axis_dead_when_group_has_no_curve() -> void:
	var em = _emitter()  # curve_indices_raw all zero → no curve on any group
	var g: Dictionary = Oracle.verdicts(em)["groups"]["position"]
	_assert_true(bool(g.get("end_dead", false)), "no-curve group's end axis is Dead")
	_assert_true("curve" in str(g.get("end_why", "")).to_lower(), "end_why names the missing curve")


## Assign a curve and the end axis wakes — interpolate_* now reads it. The assignment is the
## DECODED index (ADR-0089 curve-ownership amendment): every use site owns a private curve at
## an unbounded index, so `curve_indices_raw` is ROM provenance the compiler packs from, not
## the authoring truth the sim reads.
func _test_end_axis_live_when_curve_assigned() -> void:
	var em = _emitter()
	em.curves["position"] = 0
	var g: Dictionary = Oracle.verdicts(em)["groups"]["position"]
	_assert_true(not bool(g.get("end_dead", true)), "a curve-assigned group's end axis is Live")


## Proven DEAD edge (guarded): when homing strength is provably always zero, the
## spawn never reads target offset and the physics never samples the homing blend
## curve. Target offset is a "spatial" (never-Inactive) group, but the homing gate
## can still kill it outright — Dead, gated by homing_strength.
func _test_target_offset_dead_when_homing_zero() -> void:
	var em = _emitter()  # homing all zero
	var g: Dictionary = Oracle.verdicts(em)["groups"]["target_offset"]
	_assert_eq(g.get("state", ""), Oracle.DEAD, "target offset is Dead when homing is zero")
	_assert_eq(str(g.get("gated_by", "")), "homing_strength", "…gated by homing_strength")
	_assert_true("homing" in str(g.get("why", "")).to_lower(), "why names the homing gate")


## Non-zero homing wakes target offset (it is read at spawn).
func _test_target_offset_live_when_homing_nonzero() -> void:
	var em = _emitter()
	em.raw_data["homing_min_start"] = 100
	var g: Dictionary = Oracle.verdicts(em)["groups"]["target_offset"]
	_assert_true(g.get("state", "") != Oracle.DEAD, "target offset is not Dead when homing is set")


## The gate is `!= 0`, never `> 0`: negative homing repels (flee/dispersal) and is
## just as Live. A `> 0` gate would strand the target for repulsion effects.
func _test_homing_gate_is_nonzero_not_positive() -> void:
	var em = _emitter()
	em.raw_data["homing_min_start"] = -100  # repel
	var g: Dictionary = Oracle.verdicts(em)["groups"]["target_offset"]
	_assert_true(g.get("state", "") != Oracle.DEAD, "negative homing keeps target offset Live")


## The over-life homing-blend curve is only sampled inside the homing path, which
## the physics skips when homing strength is zero — so it too is Dead. It is a
## per-field verdict (a lone over-life curve, not a two-axis group).
func _test_homing_blend_dead_when_homing_zero() -> void:
	var em = _emitter()
	var f: Dictionary = Oracle.verdicts(em)["fields"]["homing_blend"]
	_assert_eq(f.get("state", ""), Oracle.DEAD, "homing blend curve is Dead when homing is zero")
	_assert_eq(str(f.get("gated_by", "")), "homing_strength", "…gated by homing_strength")


## Proven DEAD edge (guarded): with the colour-curve enable bit (flags_lo bit 6)
## off, EffectParticleRenderer caches null colour curves and the modulate stays
## white — so the three colour curves are Dead, gated by the enable switch.
func _test_color_curves_dead_when_color_disabled() -> void:
	var em = _emitter()  # emitter_flags_lo absent → enable bit off
	var fields: Dictionary = Oracle.verdicts(em)["fields"]
	for ch in ["r", "g", "b"]:
		var f: Dictionary = fields["color_curve_" + ch]
		_assert_eq(f.get("state", ""), Oracle.DEAD, "colour %s is Dead when colour is disabled" % ch)
		_assert_eq(str(f.get("gated_by", "")), "color_curve_enable", "…gated by the enable bit")


## Flip the colour enable bit and the three colour curves wake.
func _test_color_curves_live_when_color_enabled() -> void:
	var em = _emitter()
	em.raw_data["emitter_flags_lo"] = 0x40  # bit 6 set
	var fields: Dictionary = Oracle.verdicts(em)["fields"]
	for ch in ["r", "g", "b"]:
		_assert_true(fields["color_curve_" + ch].get("state", "") != Oracle.DEAD,
			"colour %s is not Dead when colour is enabled" % ch)


## Proven DEAD edge (guarded): ParticleSubsystem spawns a child only when the
## parent's child mode is enabled (flags_lo bits 0-1 / 2-3 non-zero). A disabled
## mode deads that child-emitter index — editing it wires nothing.
func _test_child_index_dead_when_mode_disabled() -> void:
	var em = _emitter()  # both child modes zero
	var fields: Dictionary = Oracle.verdicts(em)["fields"]
	_assert_eq(fields["child_emitter_on_death"].get("state", ""), Oracle.DEAD,
		"on-death child index is Dead when the death mode is disabled")
	_assert_eq(str(fields["child_emitter_on_death"].get("gated_by", "")), "child_death_mode",
		"…gated by the death mode")
	_assert_eq(fields["child_emitter_mid_life"].get("state", ""), Oracle.DEAD,
		"mid-life child index is Dead when the mid-life mode is disabled")


## An enabled child mode wakes its index.
func _test_child_index_live_when_mode_enabled() -> void:
	var em = _emitter()
	em.raw_data["emitter_flags_lo"] = 0x01 | 0x04  # death mode 1 (bit0), mid-life mode 1 (bit2)
	var fields: Dictionary = Oracle.verdicts(em)["fields"]
	_assert_true(fields["child_emitter_on_death"].get("state", "") != Oracle.DEAD,
		"on-death child index wakes when the death mode is enabled")
	_assert_true(fields["child_emitter_mid_life"].get("state", "") != Oracle.DEAD,
		"mid-life child index wakes when the mid-life mode is enabled")


## REFUTED edge (guarded in the sim guard): the ADR guessed inertia's neutral is
## 4096 (the ×1.0 identity divisor). The real formula
## new_vel = (max(0, inertia − threshold)·old + accel·4096) / inertia shows 4096
## is identity ONLY when the particle-header threshold is 0 — at the default 512 it
## decays velocity ×0.875. Since neutrality depends on a header field the oracle
## does not model, inertia has no clean neutral → it is never merely Inactive.
func _test_inertia_is_never_inactive_4096_refuted() -> void:
	var em = _emitter()  # inertia defaults to 4096 on a fresh emitter
	em.raw_data["radial_min_start"] = 100  # give it spawn velocity so the velocity-consumer gate stays off
	var g: Dictionary = Oracle.verdicts(em)["groups"]["inertia"]
	_assert_true(g.get("state", "") != Oracle.INACTIVE,
		"inertia at 4096 is NOT Inactive (the 4096-neutral claim is refuted)")
	_assert_eq(g.get("state", ""), Oracle.LIVE, "with real velocity, inertia at 4096 is Live")


## THE VELOCITY-CONSUMER GATE (ADR-0089 velocity amendment 2). Inertia only DECAYS an
## existing velocity (ParticlePhysics.update_particle_fixed), so when the particle's velocity
## is provably zero for all time — no spawn speed (radial 0 / skip mode), no acceleration, no
## drag (drag is a constant FORCE, `accel += drag`), no gravity (weight), and no homing — the
## inertia divisor can never move output. A bare emitter (every source at zero) is that case.
func _test_inertia_dead_when_velocity_provably_zero() -> void:
	var g: Dictionary = Oracle.verdicts(_emitter())["groups"]["inertia"]
	_assert_eq(g.get("state", ""), Oracle.DEAD, "inertia is Dead when velocity is provably always 0")
	_assert_true(str(g.get("why", "")) != "", "the Dead inertia carries a why-string")


## Drag is a velocity SOURCE (`accel += drag` each frame), NOT a consumer — a non-zero drag
## creates motion from rest, so it revives inertia. The gate must be conjunctive.
func _test_inertia_live_when_drag_creates_velocity() -> void:
	var em = _emitter()
	em.raw_data["drag_min_start"] = [1, 0, 0]
	_assert_eq(Oracle.verdicts(em)["groups"]["inertia"].get("state", ""), Oracle.LIVE,
		"a non-zero drag creates velocity, so inertia stays Live")


## Gravity (weight) accelerates the particle from rest, so inertia matters again.
func _test_inertia_live_when_gravity_creates_velocity() -> void:
	var em = _emitter()
	em.weight_min_start = 100.0  # weight is a direct emitter property (read via em.get), not raw_data
	_assert_eq(Oracle.verdicts(em)["groups"]["inertia"].get("state", ""), Oracle.LIVE,
		"a non-zero weight (gravity) creates velocity, so inertia stays Live")


## A non-zero spawn speed (radial velocity, Outward mode) gives the particle velocity to
## decay, so inertia is Live.
func _test_inertia_live_when_spawn_velocity_nonzero() -> void:
	var em = _emitter()
	em.raw_data["radial_min_start"] = 100
	_assert_eq(Oracle.verdicts(em)["groups"]["inertia"].get("state", ""), Oracle.LIVE,
		"a non-zero spawn speed gives inertia a velocity to act on, so it is Live")


## Bidirectional markers: a gate switch carries a `gates` list of the edges it is
## currently suppressing (hover = "what I'm suppressing"), so the dependency is
## navigable from the switch where the author acts. A fresh emitter has colour off,
## homing zero and both child modes disabled — every gate is suppressing.
func _test_gate_switch_carries_reverse_edges() -> void:
	var v: Dictionary = Oracle.verdicts(_emitter())
	var color_gate: Array = v["fields"]["color_curve_enable"].get("gates", [])
	_assert_eq(_targets(color_gate), ["color_curve_r", "color_curve_g", "color_curve_b"],
		"colour enable lists the three colour curves it suppresses")

	var homing_gate: Array = v["groups"]["homing_strength"].get("gates", [])
	var ht := _targets(homing_gate)
	_assert_true("target_offset" in ht and "homing_blend" in ht,
		"homing strength lists target offset + homing blend as what it suppresses")

	var death_gate: Array = v["fields"]["child_death_mode"].get("gates", [])
	_assert_eq(_targets(death_gate), ["child_emitter_on_death"],
		"the death mode lists the on-death child index it suppresses")
	# Each reverse edge carries the why-string for the hover.
	if not color_gate.is_empty():
		_assert_true(str(color_gate[0].get("why", "")) != "", "a reverse edge carries a why-string")


## When a gate is opened, it suppresses nothing — its reverse-edge list is empty
## (no marker at the switch).
func _test_gate_clears_reverse_edges_when_open() -> void:
	var em = _emitter()
	em.raw_data["emitter_flags_lo"] = 0x40  # colour enable on
	var v: Dictionary = Oracle.verdicts(em)
	_assert_true(v["fields"]["color_curve_enable"].get("gates", []).is_empty(),
		"an open colour gate suppresses nothing (no reverse edges)")


## The target ids of a reverse-edge list, in order.
func _targets(edges: Array) -> Array:
	var out: Array = []
	for e in edges:
		out.append(str(e.get("target", "")))
	return out


# --- fixtures -------------------------------------------------------------

## A minimal shared emitter with the parser-shaped storage the oracle reads
## through EmitterChannel.read_raw. Fresh = every field at its storage default
## (vec3/scalar rawss absent → 0, curves none, flags off), inertia at its 4096
## engine default.
## render_signature is the page's reproject trigger: waking an Inactive group (all-zero
## Acceleration → non-zero) MUST change the signature, so the inspector reprojects and the
## `!` marker clears.
func _test_signature_changes_when_inactive_group_wakes() -> void:
	var em = _emitter()
	var before := Oracle.render_signature(em)
	em.raw_data["accel_min_start"] = [1, 0, 0]
	_assert_true(Oracle.render_signature(em) != before,
		"waking an Inactive group changes the render signature")


## An in-range nudge of an already-Live value moves NO verdict, so the signature is stable —
## the page must NOT reproject (the live spinbox survives mid-scrub).
func _test_signature_stable_when_live_value_nudged() -> void:
	var em = _emitter()
	em.raw_data["accel_min_start"] = [1, 0, 0]   # wake it (Live)
	var before := Oracle.render_signature(em)
	em.raw_data["accel_min_start"] = [2, 0, 0]   # nudge within Live
	_assert_eq(Oracle.render_signature(em), before,
		"nudging an already-Live value leaves the render signature unchanged")


## A numeric gate crossing (homing strength → 0) deads target_offset — a plain value edit that
## restructures the Dead membership, so the signature MUST change and the page reproject.
func _test_signature_changes_when_homing_gate_deads_target_offset() -> void:
	var em = _emitter()
	em.raw_data["homing_min_start"] = 5   # homing Live → target_offset Live
	var before := Oracle.render_signature(em)
	em.raw_data["homing_min_start"] = 0   # homing off → target_offset Dead
	_assert_true(Oracle.render_signature(em) != before,
		"a homing-gate crossing that deads target_offset changes the render signature")


func _emitter():
	var em = ExMateriaEffects.EffectEmitter.new()
	em.raw_data = {"curve_indices_raw": [0, 0, 0, 0, 0, 0, 0, 0]}
	return em


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
