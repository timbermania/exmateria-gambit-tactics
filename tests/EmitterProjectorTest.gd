extends Node
## TDD guard for EmitterProjector (ADR-0071) — projects a particle span into the
## keyframe inspector's `[Section]` list. Asserts the two-level split: an "Event"
## section of what the span OWNS (referenced emitter id + action flags) first, then
## the SHARED emitter's four characterizing groups (as sections), in emitter_view
## order. Pure model, no scene/widgets. See CONTEXT.md "Effect Studio" + ADR-0071.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EmitterProjectorTest.tscn

const EffectEmitter = ExMateriaEffects.EffectEmitter

const Projector = preload("res://src/effects/studio/EmitterProjector.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const TimelineDataClass = ExMateriaEffects.TimelineData
const ParticleUnits = preload("res://src/effects/studio/ParticleUnits.gd")
const Rows = preload("res://src/effects/studio/EmitterParamRows.gd")
const Channel = preload("res://src/effects/studio/EmitterChannel.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_event_section_first_then_emitter_groups()
	_test_event_section_owns_only_emitter_id_and_flags()
	_test_emitter_sections_note_the_shared_reference_count()
	_test_vec3_group_projects_two_axis_edit_rows()
	_test_range_group_never_collapses_min_max()
	_test_curve_assignment_row_picks_a_shape_by_copy()
	_test_semantic_names_with_raw_tooltips()
	_test_color_curves_and_homing_blend_editable()
	_test_config_anim_ints_editable()
	_test_config_packed_flags_decompose_to_enums()
	_test_child_wiring_pickers()
	_test_advanced_raw_section_callback_params_and_reserved()
	_test_rows_carry_explicit_group_identity()
	_test_group_stamp_carries_summary_and_inert()
	_test_summary_shows_spread_only_where_it_exists()
	_test_curve_row_sparkline_dims_by_this_firings_window()
	_test_over_life_rows_dim_by_the_lifetime_window()
	_test_group_stamps_carry_relevance_verdicts()
	_test_target_offset_group_dead_when_homing_zero()
	_test_config_gate_row_carries_reverse_edges()
	_test_over_life_and_child_rows_carry_field_relevance()
	_test_is_directional_y_predicate()
	_test_directional_y_cells_author_game_up()
	_test_directional_predicate_agrees_with_convert()

	print("\n=== EmitterProjectorTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EmitterProjectorTest")
		get_tree().quit(1)
	else:
		print("[PASS] EmitterProjectorTest")
		get_tree().quit(0)


## A particle span projects to [Event] + the emitter's four groups, in that order
## (the two-level split): the event's own fields first, the SHARED emitter's
## characterizing groups after. The emitter groups mirror emitter_view titles/order,
## and every section exposes its rows under the uniform "fields" key.
func _test_event_section_first_then_emitter_groups() -> void:
	var ed = _effect()
	var span := _span(ed)
	var secs := Projector.sections(span, ed)

	_assert_eq(secs.size(), 6, "Event section + 5 emitter groups (incl. Advanced (raw))")
	_assert_eq(secs[0].get("title", ""), "Event", "first section is the event's own fields")

	var titles: Array = []
	for i in range(1, secs.size()):
		titles.append(secs[i].get("title", ""))
	var want: Array = []
	for g in Model.emitter_view(ed, 0):
		want.append(g.get("title", ""))
	_assert_eq(titles, want, "emitter groups mirror emitter_view titles/order")

	for s in secs:
		_assert_true(s.has("fields"), "section '%s' exposes rows under 'fields'" % s.get("title", ""))


## The Event section holds ONLY what the span owns — the referenced emitter id and
## the action flags — NOT the emitter's params (those live a level deeper, in the
## emitter sections).
func _test_event_section_owns_only_emitter_id_and_flags() -> void:
	var ed = _effect()
	var span := _span(ed)
	var ev = Projector.sections(span, ed)[0]

	var names: Array = []
	for f in ev.get("fields", []):
		names.append(f.get("name", ""))
	_assert_true("Emitter" in names, "Event section names the referenced emitter")
	_assert_true("Action flags" in names, "Event section carries the action flags the event owns")
	_assert_true(not ("Position" in names), "Event section does NOT leak emitter params")


## The SHARED emitter's sections carry a "shared by N events" note — the honest
## signal that editing there fans out — where N counts every span referencing that
## emitter across all channels/phases. The Event section (span-local) carries NO
## such note. Here emitter 1 is spawned by two keyframes → "shared by 2 events".
func _test_emitter_sections_note_the_shared_reference_count() -> void:
	var ed = _effect_emitter_used_twice()
	var span := _span(ed)
	var secs := Projector.sections(span, ed)

	_assert_true(not secs[0].has("note"), "the Event section carries no shared-by note")
	for i in range(1, secs.size()):
		_assert_eq(secs[i].get("note", ""), "shared by 2 events",
			"emitter section '%s' notes the reference count" % secs[i].get("title", ""))


## ADR-0089 two-axis presentation: Position is a vec3 with no randomness axis —
## it projects "At start" / "At end" edit rows of three X/Y/Z int cells, each cell
## carrying an emitter field_ref and the proven tiles unit descriptor, seeded with
## the RAW value.
func _test_vec3_group_projects_two_axis_edit_rows() -> void:
	var ed = _effect_editable()
	var fields := _emitter_section_fields(ed, "Emitter")
	var start := _row(fields, "Position · at start")
	var end_ := _row(fields, "Position · at end")
	_assert_true(not start.is_empty() and not end_.is_empty(), "Position projects both axis rows")
	_assert_eq(start.get("shape", ""), "edit", "axis row is an edit row")
	_assert_eq(start.get("editor", ""), "cells", "axis row renders as a cell strip")
	var cells: Array = start.get("cells", [])
	_assert_eq(cells.size(), 3, "vec3 row has X/Y/Z cells")
	_assert_eq(cells[0].get("field_ref", {}).get("field", ""), "position_start_x", "cell 0 edits x")
	_assert_eq(cells[0].get("field_ref", {}).get("channel", ""), "emitter", "ref routes the emitter channel")
	_assert_eq(cells[0].get("field_ref", {}).get("emitter_index", -1), 0, "ref addresses the shared emitter")
	_assert_eq(int(cells[0].get("value", -1)), 28, "cell seeds the RAW value")
	_assert_eq(cells[0].get("unit", {}), ParticleUnits.POS_TILES, "position authors in tiles")
	_assert_eq(cells[0].get("label", ""), "X", "component cells are labeled")


## A randomness-axis parameter (Gravity scale) shows min AND max cells on each axis
## row even when min == max — collapsing would hide the randomness axis.
func _test_range_group_never_collapses_min_max() -> void:
	var ed = _effect_editable()
	var fields := _emitter_section_fields(ed, "Particle · born-with")
	var start := _row(fields, "Gravity scale · at start")
	var cells: Array = start.get("cells", [])
	_assert_eq(cells.size(), 2, "range row keeps min AND max cells (min == max here)")
	_assert_eq(cells[0].get("label", ""), "min", "first cell is min")
	_assert_eq(cells[1].get("label", ""), "max", "second cell is max")
	_assert_eq(cells[0].get("field_ref", {}).get("field", ""), "weight_min_start", "min cell ref")
	_assert_eq(cells[1].get("field_ref", {}).get("field", ""), "weight_max_start", "max cell ref")


## Each group carries a Curve assignment row — a `[curve_pick, sparkline]` cells strip
## whose ASSIGNMENT cell is a thumbnail picker over the effect's DISTINCT SHAPE SET.
##
## Its verb is COPY, not reference (ADR-0089 curve-ownership amendment, decision 3), so the
## field_ref addresses a USE SITE — (emitter, slot) on the `curve_assign` channel — instead
## of naming an emitter nibble field, and each choice carries the shape's SAMPLES rather
## than a table index. `none` is a real choice and no longer claims to be a linear ramp:
## with no curve the sim holds the START values.
func _test_curve_assignment_row_picks_a_shape_by_copy() -> void:
	var ed = _effect_editable()
	var fields := _emitter_section_fields(ed, "Emitter")
	var row := _row(fields, "Position · curve")
	_assert_eq(row.get("editor", ""), "cells", "curve row is a [curve_pick, sparkline] strip")
	var e: Dictionary = row.get("cells", [{}])[0]
	_assert_eq(e.get("editor", ""), "curve_pick", "first strip cell is the thumbnail assignment picker")
	var ref: Dictionary = e.get("field_ref", {})
	_assert_eq(str(ref.get("channel", "")), "curve_assign", "the pick is a shape assignment")
	_assert_eq(str(ref.get("slot", "")), "position", "…addressed by the use site's slot")
	_assert_eq(str(ref.get("kind", "")), "param", "…and its kind")
	var choices: Array = e.get("choices", [])
	_assert_eq(choices.size(), 2, "none + the effect's 1 distinct shape")
	_assert_eq(choices[0].get("label", ""), "none", "choice 0 is none, with no linear-ramp claim")
	_assert_eq(int(choices[0].get("value", -1)), 0, "none is value 0")
	_assert_eq(Array(choices[0].get("samples", [1])).size(), 0, "…and carries no samples")
	_assert_eq(int(choices[1].get("value", -1)), 1, "a shape is value ordinal+1")
	_assert_eq(Array(choices[1].get("samples", [])).size(), ed.curves[0].samples.size(),
		"…carrying the whole shape, because a pick COPIES it")


## Display names come from the ADR-0089 vocabulary table; the raw RE name + byte
## offset survive in the tooltip so cross-referencing works after the rename.
func _test_semantic_names_with_raw_tooltips() -> void:
	var ed = _effect_editable()
	var emitter_fields := _emitter_section_fields(ed, "Emitter")
	var scatter := _row(emitter_fields, "Spawn scatter · at start")
	_assert_true(not scatter.is_empty(), "spread renames to Spawn scatter")
	var cell_tip: String = str(scatter.get("cells", [{}])[0].get("tooltip", ""))
	_assert_true("spread_start" in cell_tip, "cell tooltip keeps the raw RE name")
	_assert_true("@0x20" in cell_tip, "cell tooltip keeps the byte offset")
	var born := _emitter_section_fields(ed, "Particle · born-with")
	_assert_true(not _row(born, "Outward speed · at start").is_empty(), "radial_velocity renames")
	_assert_true(not _row(born, "Launch direction · at start").is_empty(), "velocity_base_angle renames")


## Over-life colour curves and the homing blend are pickable use sites too. The homing
## blend's 2-bit ROM field no longer caps the OFFER: that is a PSX packing rule, and
## ADR-0089's curve-ownership amendment moved packing to the compiler, so every use site
## browses the same shape set and export is what refuses.
func _test_color_curves_and_homing_blend_editable() -> void:
	var ed = _effect_editable()
	var fields := _emitter_section_fields(ed, "Particle · over-life")
	var red: Dictionary = _row(fields, "Color (R) · curve").get("cells", [{}])[0]
	_assert_eq(red.get("editor", ""), "curve_pick", "colour curve row leads with the thumbnail picker")
	_assert_eq(str(red.get("field_ref", {}).get("channel", "")), "curve_assign", "colour pick verb")
	_assert_eq(str(red.get("field_ref", {}).get("slot", "")), "r", "colour ref names the channel")
	_assert_eq(str(red.get("field_ref", {}).get("kind", "")), "colour", "…as a colour use site")
	var blend := _row(fields, "Homing blend · curve")
	_assert_true(not blend.is_empty(), "homing blend row exists")
	var shown: int = _row(fields, "Color (R) · curve").get("cells", [{}])[0].get("choices", []).size()
	_assert_eq(blend.get("cells", [{}])[0].get("choices", []).size(), shown,
		"the 2-bit ROM field does not cap the offer — the compiler enforces packing")


func _test_config_anim_ints_editable() -> void:
	var ed = _effect_editable()
	var fields := _emitter_section_fields(ed, "Config")
	var anim := _row(fields, "Animation set")
	_assert_eq(anim.get("editor", ""), "int", "Animation set is an editable int")
	_assert_eq(anim.get("field_ref", {}).get("field", ""), "anim_index", "ref edits anim_index")
	_assert_eq(anim.get("type", ""), "u8", "u8 range")


## Understood packed bytes decompose camera-command-word style: named enum rows per
## sub-field. Fixture motion_type_flag = 0x42 → target anchor mode 2 (CAMERA), align
## bit on.
func _test_config_packed_flags_decompose_to_enums() -> void:
	var ed = _effect_editable()
	var fields := _emitter_section_fields(ed, "Config")
	var anchor := _row(fields, "Target anchor")
	_assert_eq(anchor.get("editor", ""), "enum", "Target anchor is an editable enum")
	_assert_eq(anchor.get("field_ref", {}).get("field", ""), "target_anchor_mode", "anchor ref")
	_assert_eq(int(anchor.get("value", -1)), 2, "seeded with the sub-field value (CAMERA)")
	var labels: Array = []
	for c in anchor.get("choices", []):
		labels.append(c.get("label", ""))
	_assert_true("CAMERA" in labels and "PARENT" in labels, "choices carry the decoded mode names")
	var align := _row(fields, "Sprite faces its velocity")
	_assert_eq(align.get("editor", ""), "enum", "align toggle is an editable row")
	_assert_eq(int(align.get("value", -1)), 1, "align bit seeded on")
	_assert_true(not _row(fields, "Spread mode").is_empty(), "spread mode row present")
	_assert_true(not _row(fields, "Emitter anchor").is_empty(), "emitter anchor row present")


## Child wiring edits as emitter pickers: none (255) + one choice per emitter.
func _test_child_wiring_pickers() -> void:
	var ed = _effect_editable()
	var fields := _emitter_section_fields(ed, "Config")
	var death := _row(fields, "Spawn on death")
	_assert_eq(death.get("editor", ""), "enum", "Spawn on death is a picker")
	_assert_eq(death.get("field_ref", {}).get("field", ""), "child_emitter_on_death", "picker ref")
	var choices: Array = death.get("choices", [])
	_assert_eq(choices.size(), 2, "none + the effect's 1 emitter")
	_assert_eq(int(choices[0].get("value", -1)), 255, "none is raw 255")
	_assert_eq(int(death.get("value", -1)), 255, "unwired seeds none")
	_assert_true(not _row(fields, "Spawn mid-life").is_empty(), "mid-life picker present")


## The Advanced (raw) section: callback params are REAL raw ints (editable, honest
## tooltip), projected only for keys the parser surfaced; reserved bytes are const.
func _test_advanced_raw_section_callback_params_and_reserved() -> void:
	var ed = _effect_editable()
	var fields := _emitter_section_fields(ed, "Advanced (raw)")
	_assert_true(not fields.is_empty(), "Advanced (raw) section exists")
	var cb := _row(fields, "Callback param @0x4C")
	_assert_eq(cb.get("editor", ""), "int", "callback param is an editable int")
	_assert_eq(cb.get("field_ref", {}).get("field", ""), "callback_param_4C", "callback ref")
	_assert_true("callback" in str(cb.get("tooltip", "")).to_lower(), "honest callback tooltip")
	_assert_true(_row(fields, "Callback param @0xAA").is_empty(),
		"a param the parser did not surface projects NO row (bytes preserved)")
	var reserved := _row(fields, "byte_00")
	_assert_eq(reserved.get("shape", ""), "const", "reserved byte is a const row")
	# …and it arrives SHUT, under a fold id. The hint is written in `EffectScoreModel`
	# but the inspector only ever sees THIS projector's re-wrapped dict — a re-wrap that
	# listed its keys and forgot these two would drop the hint silently, with the section
	# opening as before and nothing to read it off. Asserted here, at the seam.
	var adv := _emitter_section(ed, "Advanced (raw)")
	_assert_true(bool(adv.get("collapsed", false)), "Advanced (raw) opens collapsed")
	_assert_eq(str(adv.get("fold_id", "")), "emitter-advanced",
		"…under a stable fold id, so the author's toggle outlives the rebuild")


## ADR-0089 inspector presentation (decision 7): every row of a parameter group
## carries EXPLICIT group identity — the fold boundary both surfaces (span
## inspector + emitter browser) hang on — replacing the "Position · …"
## name-prefix convention. Axis rows and the group's Curve row share ONE stamp;
## rows that are not parameter groups (Config, over-life colour) carry none.
func _test_rows_carry_explicit_group_identity() -> void:
	var ed = _effect_editable()
	var fields := _emitter_section_fields(ed, "Emitter")
	var start := _row(fields, "Position · at start")
	var end_ := _row(fields, "Position · at end")
	var curve := _row(fields, "Position · curve")
	var g: Dictionary = start.get("group", {})
	_assert_eq(g.get("id", ""), "position", "axis row carries the group id")
	_assert_eq(g.get("label", ""), "Position", "group label is the ADR display name")
	_assert_eq(int(g.get("emitter_index", -1)), 0, "group stamps the emitter it belongs to")
	_assert_eq(end_.get("group", {}).get("id", ""), "position", "both axis rows share the group")
	_assert_eq(curve.get("group", {}).get("id", ""), "position", "the Curve row shares the group")
	var born := _emitter_section_fields(ed, "Particle · born-with")
	_assert_eq(_row(born, "Gravity scale · at start").get("group", {}).get("id", ""),
		"weight", "range groups stamp too (id = the raw key)")
	var config := _emitter_section_fields(ed, "Config")
	_assert_true(not _row(config, "Animation set").has("group"), "config rows carry no group stamp")
	var over := _emitter_section_fields(ed, "Particle · over-life")
	_assert_true(not _row(over, "Color (R) · curve").has("group"),
		"a lone over-life curve row is not a parameter group")


## Decision 3: the group stamp carries a collapsed-header summary — start → end
## values in the same human units as the cells — and an `inert` flag (all fields
## zero AND no curve) the view dims. A read-only summary MAY collapse min == max
## (the never-collapse law binds the editing cells only); the full uncollapsed
## values ride the summary tooltip.
func _test_group_stamp_carries_summary_and_inert() -> void:
	var ed = _effect_editable()
	var fields := _emitter_section_fields(ed, "Emitter")
	var g: Dictionary = _row(fields, "Position · at start").get("group", {})
	_assert_eq(str(g.get("summary", "")), "(1, -1, 0) → (0, 0, 0)",
		"vec3 summary reads start → end in human units (raw 28 = 1 tile)")
	_assert_eq(bool(g.get("inert", true)), false, "a curve-assigned group is never inert")
	var born := _emitter_section_fields(ed, "Particle · born-with")
	var w: Dictionary = _row(born, "Gravity scale · at start").get("group", {})
	# No curve ⇒ constant at start (end inert): the summary is start-only, NOT a
	# "0 → 0" glide (showing a glide that never happens was the #291 defect).
	_assert_eq(str(w.get("summary", "")), "0", "a curve-less group summarises as its constant start")
	_assert_true(bool(w.get("inert", false)), "all-zero, curve-less group is inert")
	_assert_true("0–0 → 0–0" in str(w.get("summary_tooltip", "")),
		"the tooltip keeps the full uncollapsed min–max values")
	_assert_true("inert" in str(w.get("summary_tooltip", "")),
		"…and notes the end is inert without a curve")


## min != max keeps the spread visible in the summary ("0–40"), collapsing only
## the side that has none.
func _test_summary_shows_spread_only_where_it_exists() -> void:
	var ed = _effect_editable()
	ed.emitters[0].weight_max_start = 40
	var born := _emitter_section_fields(ed, "Particle · born-with")
	var w: Dictionary = _row(born, "Gravity scale · at start").get("group", {})
	# No curve ⇒ constant at start: the summary shows the start spread only (the end
	# is inert and does not appear).
	_assert_eq(str(w.get("summary", "")), "0–40", "curve-less summary shows the start spread only")
	_assert_eq(bool(w.get("inert", true)), false, "a non-zero group is not inert")
	# Its header trajectory is FLAT (constant) — a curve-less group does not glide, so
	# start and end magnitudes are equal (no slope). A slope would be a lie.
	var traj: Array = w.get("traj", [])
	_assert_eq(traj.size(), 2, "the stamp carries a 2-point trajectory for the header glyph")
	if traj.size() == 2:
		_assert_true(is_equal_approx(float(traj[0]), float(traj[1])),
			"a curve-less group's trajectory is flat (constant, no glide)")


## Decision 5, evolution clock: the 14 parameter groups sample their curve by
## EMITTER-ELAPSED frame, so the span surface dims the sparkline past this
## firing's duration. The window (and the assigned curve) also ride the group
## stamp so the collapsed header can draw its mini sparkline.
func _test_curve_row_sparkline_dims_by_this_firings_window() -> void:
	var ed = _effect_editable()
	var span := _span(ed)
	var n := int(span["end"]) - int(span["start"])
	_assert_true(n > 0, "fixture span has a real duration")
	var row := _row(_emitter_section_fields(ed, "Emitter"), "Position · curve")
	var spark: Dictionary = row.get("cells", [{}, {}])[1]
	_assert_eq(spark.get("editor", ""), "curve", "second strip cell is the sparkline")
	_assert_eq(int(spark.get("curve_index", -9)), 0, "raw nibble 1 = curve 0")
	_assert_eq(int(spark.get("used_n", -9)), n, "evolution clock: N = this firing's duration")
	_assert_true(("0–%d" % n) in str(spark.get("tooltip", "")), "tooltip states the window in frames")
	_assert_true("firing" in str(spark.get("tooltip", "")), "…and whose firing it is")
	var g: Dictionary = row.get("group", {})
	_assert_eq(int(g.get("curve_index", -9)), 0, "stamp carries the curve for the header spark")
	_assert_eq(int(g.get("used_n", -9)), n, "stamp carries the window for the header spark")


## Decision 5, particle-age clock: over-life rows (colour, homing blend) sample
## by particle age → N = the max authored lifetime; lifetime −1 is the
## animation-driven sentinel → fully bright with an honest tooltip.
##
## The fixture's numbers moved on 2026-08-20 with `EmitterLifeWindow`'s correction, and the
## SHAPE of the move is the point: this emitter has no lifetime curve, so the spawner reads
## only its START pair (8, 12) and the 24 in the end pair is inert. It used to read 24 — a
## window twice the particle's real life, every frame of the second half dead zone drawn as
## live.
func _test_over_life_rows_dim_by_the_lifetime_window() -> void:
	var ed = _effect_editable()
	var em = ed.emitters[0]
	em.lifetime_min_start = 8
	em.lifetime_max_start = 12
	em.lifetime_min_end = 8
	em.lifetime_max_end = 24
	var red := _row(_emitter_section_fields(ed, "Particle · over-life"), "Color (R) · curve")
	var spark: Dictionary = red.get("cells", [{}, {}])[1]
	_assert_eq(int(spark.get("used_n", -9)), 12,
		"particle-age clock: N = the max lifetime the spawner can DRAW (the start pair)")
	_assert_true("lifetime" in str(spark.get("tooltip", "")), "tooltip names the clock")
	var blend := _row(_emitter_section_fields(ed, "Particle · over-life"), "Homing blend · curve")
	_assert_eq(int(blend.get("cells", [{}, {}])[1].get("used_n", -9)), 12,
		"homing blend shares the particle-age window")
	# Animation-driven (lifetime −1): the window is the particle's ACTUAL lifespan = the
	# animation's baked display length. With no resolvable animation, fall back to the
	# whole curve (−1) rather than invent a length.
	#
	# BOTH START FIELDS, not just `min_start`. A −1 in one half of the pair no longer makes
	# an emitter animation-driven: `_srange(-1, 12)` draws in [−1, 12] and only an exact
	# −1.0 survives `int()`, so such a particle is not animation-driven in any useful sense.
	# The corpus agrees — the start pair is all-or-nothing in 2621 of 2622 colour emitters.
	em.lifetime_min_start = -1
	em.lifetime_max_start = -1
	red = _row(_emitter_section_fields(ed, "Particle · over-life"), "Color (R) · curve")
	spark = red.get("cells", [{}, {}])[1]
	_assert_eq(int(spark.get("used_n", -9)), -1, "lifetime −1, no resolvable animation → whole curve")
	_assert_true("animation" in str(spark.get("tooltip", "")).to_lower(),
		"honest animation-driven tooltip")

	# Give the emitter's anim_index (3) a real animation: 20→10, 2→1, 0(terminal)→1 = 12
	# baked frames. The over-life window now tracks THAT, not 160.
	ed.animations = [{}, {}, {}, {"opcodes": [
		{"type": "FRAME", "duration": 20}, {"type": "FRAME", "duration": 2},
		{"type": "FRAME", "duration": 0}]}]
	red = _row(_emitter_section_fields(ed, "Particle · over-life"), "Color (R) · curve")
	spark = red.get("cells", [{}, {}])[1]
	_assert_eq(int(spark.get("used_n", -9)), 12, "lifetime −1 → the animation's display length (12)")
	_assert_true("12" in str(spark.get("tooltip", "")), "tooltip names the animation frame count")
	var blend2 := _row(_emitter_section_fields(ed, "Particle · over-life"), "Homing blend · curve")
	_assert_eq(int(blend2.get("cells", [{}, {}])[1].get("used_n", -9)), 12,
		"homing blend shares the animation-driven window")


## Field-relevance salience (ADR-0089 amendment): the projector attaches the
## oracle's per-group verdict to each group stamp. In _effect_editable, Position
## has a value + a curve (Live, end not collapsed) while Gravity scale is all-zero
## and curve-less (Inactive).
func _test_group_stamps_carry_relevance_verdicts() -> void:
	var ed = _effect_editable()
	var pos: Dictionary = _row(_emitter_section_fields(ed, "Emitter"),
		"Position · at start").get("group", {}).get("relevance", {})
	_assert_eq(str(pos.get("state", "")), "live", "Position is Live (has a value)")
	_assert_eq(bool(pos.get("end_dead", true)), false, "Position has a curve — end axis not collapsed")
	var w: Dictionary = _row(_emitter_section_fields(ed, "Particle · born-with"),
		"Gravity scale · at start").get("group", {}).get("relevance", {})
	_assert_eq(str(w.get("state", "")), "inactive", "all-zero Gravity scale is Inactive")
	_assert_true(bool(w.get("end_dead", false)), "a curve-less group's end axis is Dead")
	_assert_true("curve" in str(w.get("end_why", "")).to_lower(), "…with an end-unused note")


## Target offset's group stamp reads Dead when homing strength is zero (the homing
## gate), carrying the gate id for the marker hover.
func _test_target_offset_group_dead_when_homing_zero() -> void:
	var ed = _effect_editable()  # homing all zero
	var tgt: Dictionary = _row(_emitter_section_fields(ed, "Particle · born-with"),
		"Target offset · at start").get("group", {}).get("relevance", {})
	_assert_eq(str(tgt.get("state", "")), "dead", "target offset is Dead when homing is zero")
	_assert_eq(str(tgt.get("gated_by", "")), "homing_strength", "…gated by homing strength")


## A Config gate switch carries the reverse edges it suppresses (bidirectional
## marker). In _effect_editable both child modes are disabled, so the Child death
## mode row lists the on-death child index it deads.
func _test_config_gate_row_carries_reverse_edges() -> void:
	var ed = _effect_editable()
	var config := _emitter_section_fields(ed, "Config")
	var mode: Dictionary = _row(config, "Child death mode").get("relevance", {})
	var targets: Array = []
	for e in mode.get("gates", []):
		targets.append(str(e.get("target", "")))
	_assert_true("child_emitter_on_death" in targets,
		"the disabled death mode lists the child index it suppresses")
	# …and the gated child-index picker itself reads Dead.
	var picker: Dictionary = _row(config, "Spawn on death").get("relevance", {})
	_assert_eq(str(picker.get("state", "")), "dead", "the on-death picker is Dead (mode disabled)")


## Per-field verdicts reach the lone over-life / child rows too. Colour is enabled
## in _effect_editable (flags_lo 0x40) so the colour curves are Live; the homing
## blend curve is Dead (homing zero).
func _test_over_life_and_child_rows_carry_field_relevance() -> void:
	var ed = _effect_editable()
	var over := _emitter_section_fields(ed, "Particle · over-life")
	_assert_eq(str(_row(over, "Color (R) · curve").get("relevance", {}).get("state", "")),
		"live", "colour R curve is Live (colour enabled)")
	_assert_eq(str(_row(over, "Homing blend · curve").get("relevance", {}).get("state", "")),
		"dead", "homing blend curve is Dead (homing zero)")


# --- fixtures -------------------------------------------------------------

## An effect with one particle channel whose second keyframe spawns emitter 1
## (→ emitter_index 0), and a matching emitter with a curve-driven position.
## ADR-0089 amendment "directional Y authors game-up" — the author-side chirality
## predicate. True ONLY for the Y component (comp 1) of a DIRECTIONAL placement
## field (position/target-offset start&end, acceleration, drag), whose Y sign is
## visible on screen. Spread is an extent (Y sign inert) and every X/Z is excluded.
func _test_is_directional_y_predicate() -> void:
	_assert_true(Rows.is_directional_y("position_start_y", 1), "position start Y is directional")
	_assert_true(Rows.is_directional_y("position_end_y", 1), "position end Y is directional")
	_assert_true(Rows.is_directional_y("target_offset_start_y", 1), "target offset Y is directional")
	_assert_true(Rows.is_directional_y("acceleration_min_start_y", 1), "acceleration Y is directional")
	_assert_true(Rows.is_directional_y("drag_max_end_y", 1), "drag Y is directional")
	# Spread is an extent — its Y sign is inert (never flipped on the authoring path).
	_assert_true(not Rows.is_directional_y("spread_start_y", 1), "spread Y is an extent, NOT directional")
	# Only the Y component flips; X and Z never do.
	_assert_true(not Rows.is_directional_y("position_start_x", 0), "position X never flips")
	_assert_true(not Rows.is_directional_y("position_start_z", 2), "position Z never flips")
	# Scalar / non-placement fields have no directional Y.
	_assert_true(not Rows.is_directional_y("weight_min_start", -1), "a scalar field has no directional Y")
	_assert_true(not Rows.is_directional_y("velocity_base_angle_start_y", 1), "angles are not directional placement")


## A directional Y edit cell authors game-up: it carries a `flip_sign` marker (the
## inspector negates raw↔display around it) and its tooltip surfaces the signed raw
## + a "shown game-up" note, so a cell reading +1 against a -28 byte reconciles.
## The X/Z cells and the spread group carry NO flip.
func _test_directional_y_cells_author_game_up() -> void:
	var ed = _effect_editable()
	var fields := _emitter_section_fields(ed, "Emitter")
	var pos_cells: Array = _row(fields, "Position · at start").get("cells", [])
	_assert_eq(pos_cells.size(), 3, "position row has X/Y/Z cells")
	if pos_cells.size() < 3:
		return
	_assert_true(not pos_cells[0].get("flip_sign", false), "the X cell does NOT flip")
	_assert_true(bool(pos_cells[1].get("flip_sign", false)), "the Y cell flips (authors game-up)")
	_assert_true(not pos_cells[2].get("flip_sign", false), "the Z cell does NOT flip")
	# raw position_start_y is -28 in the fixture; the tooltip states it + the note.
	var tip: String = str(pos_cells[1].get("tooltip", ""))
	_assert_true("position_start_y" in tip, "Y tooltip keeps the raw RE name")
	_assert_true("= -28" in tip, "Y tooltip surfaces the signed raw value")
	_assert_true("game-up" in tip, "Y tooltip flags that the cell is shown game-up")
	# Spread — an extent — never flips on any component.
	var spread_cells: Array = _row(fields, "Spawn scatter · at start").get("cells", [])
	_assert_true(not spread_cells[1].get("flip_sign", false), "spread Y does NOT flip (inert extent)")


## The guard that keeps the two `-Y` sites from drifting: the author-side
## `directional` predicate agrees with EmitterChannel._convert's sim-cache sign on
## EVERY directional field, and they differ ONLY on spread (which _convert flips
## inertly but the author path leaves alone).
func _test_directional_predicate_agrees_with_convert() -> void:
	# _convert negates comp 1 for kinds "pos" and "accel"; the directional predicate
	# is the same set minus spread. Enumerate the vec3 families by a representative field.
	var cases := {
		"position_start_y": true, "position_end_y": true,
		"target_offset_start_y": true, "target_offset_end_y": true,
		"acceleration_min_start_y": true, "drag_max_end_y": true,
		"spread_start_y": false, "spread_end_y": false,  # _convert flips, author does NOT
	}
	for field in cases:
		var kind := "accel" if (field.begins_with("acceleration") or field.begins_with("drag")) else "pos"
		# _convert negates comp 1 for pos/accel: sign of a +100 raw comes out negative.
		var convert_negates := Channel._convert(kind, 100, 1) < 0.0
		_assert_true(convert_negates, "_convert flips comp 1 for %s" % field)
		_assert_eq(Rows.is_directional_y(field, 1), cases[field],
			"author predicate matches expectation for %s" % field)


func _effect():
	var ed = ExMateriaEffects.EffectData.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8},
		"particle_channels": [
			{"context": "for_each", "channel_index": 0, "max_keyframe": 1, "keyframes": [
				{"time": 0, "emitter_id": 0}, {"time": 10, "emitter_id": 1}]},
		],
	})
	var em = EffectEmitter.new()
	em.curves = {"position": 0}
	em.color_curves = {"r": 0}
	ed.emitters.append(em)
	ed.curves.append(ExMateriaEffects.EffectCurve.from_array([0.0, 0.5, 1.0], 0))
	return ed


## Emitter 1 spawned by two keyframes in the same channel → two spans reference it.
func _effect_emitter_used_twice():
	var ed = ExMateriaEffects.EffectData.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8},
		"particle_channels": [
			{"context": "for_each", "channel_index": 0, "max_keyframe": 2, "keyframes": [
				{"time": 0, "emitter_id": 0}, {"time": 10, "emitter_id": 1}, {"time": 20, "emitter_id": 1}]},
		],
	})
	var em = EffectEmitter.new()
	em.curves = {"position": 0}
	em.color_curves = {"r": 0}
	ed.emitters.append(em)
	ed.curves.append(ExMateriaEffects.EffectCurve.from_array([0.0, 0.5, 1.0], 0))
	return ed


## The _effect() fixture with parser-shaped raw storage on emitter 0 (position raw
## (28, -28, 0), everything else 0) — what the editable projection reads.
func _effect_editable():
	var ed = _effect()
	var em = ed.emitters[0]
	em.anim_index = 3
	em.raw_data = {
		"position_start": [28, -28, 0], "position_end": [0, 0, 0],
		"spread_start": [0, 0, 0], "spread_end": [0, 0, 0],
		"angle_start": [0, 0, 0], "angle_end": [0, 0, 0],
		"vel_spread_start": [0, 0, 0], "vel_spread_end": [0, 0, 0],
		"radial_min_start": 0, "radial_max_start": 0, "radial_min_end": 0, "radial_max_end": 0,
		"accel_min_start": [0, 0, 0], "accel_max_start": [0, 0, 0],
		"accel_min_end": [0, 0, 0], "accel_max_end": [0, 0, 0],
		"drag_min_start": [0, 0, 0], "drag_max_start": [0, 0, 0],
		"drag_min_end": [0, 0, 0], "drag_max_end": [0, 0, 0],
		"target_start": [0, 0, 0], "target_end": [0, 0, 0],
		"homing_min_start": 0, "homing_max_start": 0, "homing_min_end": 0, "homing_max_end": 0,
		"curve_indices_raw": [1, 0, 0, 0, 0, 0, 0, 0],
		"motion_type_flag": 0x42, "animation_target_flag": 0x00,
		"emitter_flags_lo": 0x40, "emitter_flags_hi": 0x01,
		"byte_00": 0, "byte_05": 0,
	}
	em.callback_params = {"param_4C": 0, "param_A8": 7}
	return ed


## The emitter-group section titled `title` from the projected span sections.
func _emitter_section_fields(ed, title: String) -> Array:
	return _emitter_section(ed, title).get("fields", [])


## The whole section dict, for the cases that assert on the ENVELOPE (fold id, opening
## state) rather than on the rows inside it.
func _emitter_section(ed, title: String) -> Dictionary:
	for s in Projector.sections(_span(ed), ed):
		if s.get("title", "") == title:
			return s
	return {}


## The first row named `name`, or {}.
func _row(fields: Array, name: String) -> Dictionary:
	for f in fields:
		if f.get("name", "") == name:
			return f
	return {}


func _span(ed) -> Dictionary:
	return Model.build(ed)["lanes"][0]["spans"][0]


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
