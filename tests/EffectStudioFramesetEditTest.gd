extends Node
## TDD guard for Effect Studio FRAMESET editing (#278) — individual frame fields
## (UV rect, vertices, palette_id, blend mode) made editable through the same
## #255 choke point, reusing the F1 shared kit (#264). Frames are plain
## JSON-shaped Dictionaries on `EffectData.framesets[i]["frames"][j]` (no
## wrapper class, unlike palette/screen's typed Keyframe) — the encoder mutates
## the live dict in place and is READ-LIVE (EffectParticleRenderer re-reads
## `effect_data.framesets` every draw), so `invalidates_sim = false`.
##
## v1 SCOPE (locked via /grill-with-docs 2026-08-17, see #278): in-place field
## edits only — no adding/removing/reordering frames, framesets, or frameset-
## group membership. This file guards seam (1) only: FramesetChannel.apply_raw,
## the pure encoder. Dispatch wiring / projector / writer / manifest are later
## slices with their own guards.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectStudioFramesetEditTest.tscn

const Channel = preload("res://src/effects/studio/FramesetChannel.gd")
const Session = preload("res://src/effects/studio/EffectEditSession.gd")
const Registry = preload("res://src/effects/studio/InspectorProjectorRegistry.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const Canvas = preload("res://src/effects/studio/FramesetCanvas.gd")
const Projector = preload("res://src/effects/studio/FramesetProjector.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_encoder_writes_palette_id_and_undoes()
	_test_encoder_writes_semi_trans_mode_and_recomputes_blend_mode_cache()
	_test_encoder_writes_uv_rect_field()
	_test_encoder_writes_vertex_field()
	_test_encoder_reports_unfaithful_out_of_range_palette_id()
	_test_encoder_faithful_bound_for_uv_x_is_plain_unsigned_byte()
	_test_session_dispatches_frameset_channel_and_undoes()
	_test_frame_target_is_registered_and_built()
	_test_frame_header_identifies_the_frame_and_links_back_to_its_frameset()
	_test_frame_sections_emit_editable_rows_for_the_v1_field_set()
	_test_the_frame_rows_are_grouped_into_folded_sections()
	_test_the_quad_facts_are_derived_from_the_rows_beneath_them()
	_test_the_header_flags_row_is_not_a_float()
	_test_frameset_target_header_links_to_each_child_frame()
	_test_the_base_view_is_one_to_one_centered()
	_test_canvas_uv_rect_maps_into_the_texture_draw_rect()
	_test_canvas_point_to_texture_pixel_is_the_inverse_mapping()
	_test_canvas_hit_test_finds_corner_handles_and_body()
	_test_every_pixel_of_the_drawn_handle_is_grabbable()
	_test_the_grab_target_is_bigger_than_the_square_it_is_drawn_as()
	_test_the_body_keeps_the_middle_third_however_small_the_box()
	_test_a_press_beside_an_edge_is_not_a_corner()
	_test_the_press_path_takes_the_handles_outer_corner()
	_test_canvas_move_uv_shifts_x_y_only()
	_test_canvas_move_uv_clamps_to_non_negative()
	_test_canvas_resize_uv_from_br_pins_top_left()
	_test_canvas_resize_uv_from_tl_pins_bottom_right()
	_test_normalised_block_folds_the_flip_out()
	_test_block_to_uv_writes_from_the_members_own_signs()
	_test_canvas_resize_uv_preserves_a_mirrored_frames_flip()
	_test_canvas_coverage_counts_a_mirrored_frames_texels()
	_test_canvas_uv_rect_of_a_mirrored_frame_is_a_positive_rect()
	_test_canvas_hit_test_grabs_a_mirrored_frames_body()
	_test_region_membership_is_exact_equality_of_the_block()
	_test_region_index_reproduces_the_measured_e019_sheet()
	_test_region_members_carry_the_facets_the_scope_control_filters_on()
	_test_anchor_corner_follows_the_measured_sign_table()
	_test_a_region_move_writes_every_member_through_its_own_signs()
	_test_a_region_edit_that_changes_nothing_produces_no_edit()
	_test_a_resize_onto_a_neighbouring_block_announces_who_would_join()
	_test_the_encodable_range_is_inferred_from_the_extracted_value()
	_test_a_region_resize_refuses_a_block_a_member_cannot_store()
	_test_a_faithful_uv_bound_reads_the_frames_own_extracted_sign()
	_test_fit_scale_is_the_rung_at_which_the_whole_sheet_is_visible()
	_test_zoom_out_stops_once_the_whole_sheet_is_visible()
	_test_zoom_out_is_refused_when_the_sheet_already_fits()
	_test_canvas_view_rect_scales_around_center()
	_test_canvas_zoom_at_cursor_keeps_that_texture_pixel_fixed()
	_test_pixel_ladder_snaps_a_fractional_fit_down_to_a_rung()
	_test_pixel_ladder_shrinks_an_oversized_sheet_through_reciprocal_integers()
	_test_pixel_ladder_step_walks_rungs_in_both_directions()
	_test_view_rect_is_a_whole_number_of_screen_pixels_per_texel()
	_test_pan_is_clamped_per_axis()
	_test_pan_moves_off_right_drag_to_middle_and_shift_left()
	_test_right_drag_no_longer_pans_so_right_click_is_free()
	_test_shift_is_tested_before_the_uv_box_hit_test()
	_test_reset_view_has_a_key()
	_test_the_overlay_colours_the_anchor_corner_apart()
	_test_texel_class_partitions_by_colour_not_by_palette_word()
	_test_texel_class_counts_reproduce_the_measured_e019_sheet()
	_test_display_image_erases_the_transparent_class_and_unwashes_stp()
	_test_checkerboard_can_never_be_mistaken_for_content()
	_test_coverage_is_the_union_of_the_uv_rects_not_their_sum()
	_test_coverage_clips_a_uv_rect_that_runs_off_the_sheet()
	_test_coverage_reproduces_the_measured_e019_and_e317_sheets()
	_test_coverage_image_dims_only_what_no_frame_addresses()
	_test_palette_word_round_trips_the_documented_bgr555_values()
	_test_swatch_matching_compares_in_five_bit_space()
	_test_swatch_matching_highlights_every_slot_that_matches()
	_test_the_readout_names_a_clut_line_the_export_did_not_decode()

	print("\n=== EffectStudioFramesetEditTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioFramesetEditTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioFramesetEditTest")
		get_tree().quit(0)


func _test_encoder_writes_palette_id_and_undoes() -> void:
	var data := _fake_data()
	var frame: Dictionary = data.framesets[0]["frames"][0]
	var ref := {"channel": "frameset", "frameset_index": 0, "frame_index": 0, "field": "palette_id"}

	var res: Dictionary = Channel.apply_raw(data, ref, 7)

	_assert_eq(res.get("before_raw", -1), 3, "records the pre-edit palette_id")
	_assert_eq(res.get("after_raw", -1), 7, "records the written palette_id")
	_assert_eq(res.get("invalidates_sim", true), false, "a frame field edit is read-live (no re-seek)")
	_assert_true(res.get("faithful", {}).get("ok", false), "an in-range palette_id is faithfully encodable")
	_assert_eq(frame["palette_id"], 7, "the encoder writes the raw value onto the live frame dict")

	# Undo replay is the same scalar path EffectEditSession.undo() uses for every other channel.
	var undo_res: Dictionary = Channel.apply_raw(data, ref, res["before_raw"])
	_assert_eq(frame["palette_id"], 3, "undo replay restores the original palette_id")
	_assert_eq(undo_res.get("invalidates_sim", true), false, "undo replay is also read-live")


func _test_encoder_writes_semi_trans_mode_and_recomputes_blend_mode_cache() -> void:
	var data := _fake_data()
	var frame: Dictionary = data.framesets[0]["frames"][0]
	var ref := {"channel": "frameset", "frameset_index": 0, "frame_index": 0, "field": "semi_trans_mode"}

	_assert_eq(frame["blend_mode"], "BLEND_50", "fixture starts at semi_trans_mode 0 = BLEND_50")
	var res: Dictionary = Channel.apply_raw(data, ref, 1)

	_assert_eq(res.get("before_raw", -1), 0, "records the pre-edit semi_trans_mode")
	_assert_eq(res.get("after_raw", -1), 1, "records the written semi_trans_mode")
	_assert_eq(frame["semi_trans_mode"], 1, "the encoder writes the raw 2-bit mode")
	_assert_eq(frame["blend_mode"], "ADD", "the derived blend_mode name cache re-derives with the raw write")
	_assert_true(res.get("faithful", {}).get("ok", false), "mode 1 fits the 2-bit encoding")


func _test_encoder_writes_uv_rect_field() -> void:
	var data := _fake_data()
	var frame: Dictionary = data.framesets[0]["frames"][0]
	var ref := {"channel": "frameset", "frameset_index": 0, "frame_index": 0, "field": "uv_width"}

	var res: Dictionary = Channel.apply_raw(data, ref, 40)

	_assert_eq(res.get("before_raw", -1), 32, "records the pre-edit uv.width")
	_assert_eq(res.get("after_raw", -1), 40, "records the written uv.width")
	_assert_eq(frame["uv"]["width"], 40, "the encoder writes into the nested uv dict")
	_assert_eq(frame["uv"]["x"], 8, "a sibling uv field (x) is untouched by a width edit")


func _test_encoder_writes_vertex_field() -> void:
	var data := _fake_data()
	var frame: Dictionary = data.framesets[0]["frames"][0]
	var ref := {"channel": "frameset", "frameset_index": 0, "frame_index": 0, "field": "vertex_br_y"}

	var res: Dictionary = Channel.apply_raw(data, ref, 99)

	_assert_eq(res.get("before_raw", -1), 16, "records the pre-edit bottom_right.y vertex")
	_assert_eq(res.get("after_raw", -1), 99, "records the written bottom_right.y vertex")
	_assert_eq(frame["vertices"]["bottom_right"][1], 99, "the encoder writes into the nested vertices dict")
	_assert_eq(frame["vertices"]["bottom_right"][0], 32, "a sibling vertex component (x) is untouched")
	_assert_eq(frame["vertices"]["top_left"], [0, 0], "a sibling corner is untouched by a bottom_right edit")


func _test_encoder_faithful_bound_for_uv_x_is_plain_unsigned_byte() -> void:
	var data := _fake_data()
	var ref := {"channel": "frameset", "frameset_index": 0, "frame_index": 0, "field": "uv_x"}

	# uv_x/uv_y get NO sign correction in parse_frame (unlike width/height) — the full
	# unsigned byte range 0-255 is faithful, and a negative value is not.
	var res_hi: Dictionary = Channel.apply_raw(data, ref, 200)
	_assert_true(res_hi.get("faithful", {}).get("ok", false), "uv_x = 200 fits the plain unsigned byte range")
	var res_neg: Dictionary = Channel.apply_raw(data, ref, -1)
	_assert_true(not res_neg.get("faithful", {}).get("ok", true), "uv_x = -1 does not fit an unsigned byte")


func _test_encoder_reports_unfaithful_out_of_range_palette_id() -> void:
	var data := _fake_data()
	var ref := {"channel": "frameset", "frameset_index": 0, "frame_index": 0, "field": "palette_id"}

	var res: Dictionary = Channel.apply_raw(data, ref, 99)

	_assert_true(not res.get("faithful", {}).get("ok", true),
		"palette_id only fits 4 bits (0-15) — 99 is not faithfully encodable")
	_assert_eq(data.framesets[0]["frames"][0]["palette_id"], 99,
		"Free always accepts the write even when the byte encoding can't hold it (non-destructive advisory)")


func _test_session_dispatches_frameset_channel_and_undoes() -> void:
	var data := _fake_data()
	var frame: Dictionary = data.framesets[0]["frames"][0]
	var session = Session.new(data)
	var ref := {"channel": "frameset", "frameset_index": 0, "frame_index": 0, "field": "palette_id"}

	var res: Dictionary = session.apply_edit(ref, 9)

	_assert_eq(frame["palette_id"], 9, "EffectEditSession.apply_edit routes 'frameset' through FramesetChannel")
	_assert_eq(res.get("invalidates_sim", true), false, "the routed edit is read-live")

	_assert_true(session.undo(), "the session records an undo entry for a frameset edit")
	_assert_eq(frame["palette_id"], 3, "session.undo() replays the scalar undo path back through FramesetChannel")


func _test_frame_target_is_registered_and_built() -> void:
	_assert_true(Registry.has_kind("frame"), "'frame' is a recognized inspector kind")
	_assert_true(Registry.is_built("frame"), "'frame' now has a projector wired (was a declared seam)")
	_assert_true(Registry.has_kind("frameset"), "'frameset' is a recognized inspector kind")
	_assert_true(Registry.is_built("frameset"), "'frameset' now has a projector wired (was a declared seam)")


func _test_frame_header_identifies_the_frame_and_links_back_to_its_frameset() -> void:
	var data := _fake_data()
	var target := Target.frame(0, 0)
	var header: Array = Registry.header(target, data, {})

	_assert_true(header.size() > 0, "the frame header is non-empty")
	var linked_back := false
	for row in header:
		if row.get("link", {}).get("target", {}) == Target.frameset(0):
			linked_back = true
	_assert_true(linked_back, "the frame header links back to its owning frameset (ADR-0073 drill-in)")


func _test_frame_sections_emit_editable_rows_for_the_v1_field_set() -> void:
	var data := _fake_data()
	var target := Target.frame(0, 0)
	var sections: Array = Registry.sections(target, data, {})

	var fields: Array = []
	for section in sections:
		fields.append_array(section.get("fields", []))

	var by_name: Dictionary = {}
	for f in fields:
		by_name[f.get("name", "")] = f

	var expected_editable := [
		"Palette ID", "Blend mode", "Semi-trans on", "8bpp",
		"UV X", "UV Y", "UV Width", "UV Height",
		# Renamed 2026-08-21 from `Vertex TL X` … `Vertex BR Y`, which the author read as
		# esoteric. The corner is named on the SHEET REGION, not on the screen — see
		# `FramesetProjector._vertex_fields`.
		"Top-left X", "Top-left Y", "Top-right X", "Top-right Y",
		"Bottom-left X", "Bottom-left Y", "Bottom-right X", "Bottom-right Y",
	]
	for name in expected_editable:
		_assert_true(by_name.has(name), "sections include a '%s' row" % name)
		if by_name.has(name):
			_assert_eq(by_name[name].get("shape", ""), "edit", "'%s' is editable in v1" % name)

	var palette_ref: Dictionary = by_name.get("Palette ID", {}).get("field_ref", {})
	_assert_eq(palette_ref.get("channel", ""), "frameset", "Palette ID field_ref addresses the frameset channel")
	_assert_eq(palette_ref.get("frameset_index", -1), 0, "Palette ID field_ref carries the frameset index")
	_assert_eq(palette_ref.get("frame_index", -1), 0, "Palette ID field_ref carries the frame index")
	_assert_eq(palette_ref.get("field", ""), "palette_id", "Palette ID field_ref names the raw field")


func _test_frameset_target_header_links_to_each_child_frame() -> void:
	var data := _fake_data()
	var target := Target.frameset(0)
	var header: Array = Registry.header(target, data, {})

	var linked_frames: Array = []
	for row in header:
		var link: Dictionary = row.get("link", {})
		if link.get("target", {}).get("kind", "") == "frame":
			linked_frames.append(link["target"])
	_assert_eq(linked_frames.size(), 1, "the frameset header links to each of its child frames (1 in the fixture)")
	if linked_frames.size() == 1:
		_assert_eq(linked_frames[0], Target.frame(0, 0), "the child link addresses frameset 0 / frame 0")


func _test_the_base_view_is_one_to_one_centered() -> void:
	# The viewport OPENS at 100% — one texel, one screen pixel — and never at a "fit",
	# whatever size the panel is. Measured at the real panel (297x270) with E019's real
	# sheet (128x256): fitting would have opened at the 1/2 rung, drawing the sheet at
	# 64x128 in a 297x270 canvas with three-quarters of the panel empty, because the
	# raw fit (0.992) sits a hair under 1:1 and the ladder snaps DOWN. Opening at 1:1
	# instead overflows the port by a sliver; the author pans, or zooms out deliberately.
	var r: Rect2 = Canvas.texture_rect(Vector2(297, 270), Vector2(128, 256), Canvas.MARGIN)
	_assert_eq(r.size, Vector2(128, 256), "the sheet opens at its own pixel size")
	_assert_eq(r.get_center(), Vector2(148.5, 135.0), "centered in the port")
	var small: Rect2 = Canvas.texture_rect(Vector2(100, 100), Vector2(50, 25), 0.0)
	_assert_eq(small, Rect2(25, 37.5, 50, 25),
		"a sheet the port could magnify still opens at 1:1, centered")


func _test_canvas_uv_rect_maps_into_the_texture_draw_rect() -> void:
	var texture_size := Vector2(50, 25)
	var texture_draw_rect := Rect2(0, 25, 100, 50)  # scale = (2, 2)
	var uv := {"x": 10, "y": 5, "width": 20, "height": 10}

	var r: Rect2 = Canvas.uv_to_canvas_rect(uv, texture_size, texture_draw_rect)

	_assert_eq(r, Rect2(20, 35, 40, 20), "UV rect scales+offsets into the texture draw rect")


func _test_canvas_point_to_texture_pixel_is_the_inverse_mapping() -> void:
	var texture_size := Vector2(50, 25)
	var texture_draw_rect := Rect2(0, 25, 100, 50)

	var tex_pixel: Vector2 = Canvas.canvas_point_to_texture_pixel(
		Vector2(20, 35), texture_size, texture_draw_rect)

	_assert_eq(tex_pixel, Vector2(10, 5), "the inverse of uv_to_canvas_rect's top-left mapping")


func _test_canvas_hit_test_finds_corner_handles_and_body() -> void:
	var texture_size := Vector2(50, 25)
	var texture_draw_rect := Rect2(0, 25, 100, 50)   # uv rect canvas-space = Rect2(20,35,40,20)
	var uv := {"x": 10, "y": 5, "width": 20, "height": 10}

	_assert_eq(Canvas.hit_test(Vector2(21, 36), uv, texture_size, texture_draw_rect, 8.0), "tl",
		"a point near the top-left corner hits the tl handle")
	_assert_eq(Canvas.hit_test(Vector2(59, 54), uv, texture_size, texture_draw_rect, 8.0), "br",
		"a point near the bottom-right corner hits the br handle")
	_assert_eq(Canvas.hit_test(Vector2(40, 45), uv, texture_size, texture_draw_rect, 8.0), "body",
		"a point in the middle of the rect (away from any handle) hits the body")
	_assert_eq(Canvas.hit_test(Vector2(0, 0), uv, texture_size, texture_draw_rect, 8.0), "",
		"a point outside the rect and every handle misses")


## THE HANDLES ARE HARD TO GRAB, and the reason was measurable: `_draw_uv_overlay` drew an
## 8x8 SQUARE and `hit_test` was handed `HANDLE_SIZE` and tested a radius-4 CIRCLE with it.
## The square's own corner sits 5.66px out along the diagonal, the circle stopped at 4.00px,
## and swept at 0.25px over the drawn square **26.8% of the pixels the author can see did
## not grab** — the diagonal-outward ones, which is exactly where a hand aims.
##
## Swept rather than sampled at three points, because a target's defect is a MAP and not a
## point: the same lesson `timeline-grip-swallows-short-spans` records for the score
## timeline's edge grip, arriving on the surface next door.
func _test_every_pixel_of_the_drawn_handle_is_grabbable() -> void:
	var texture_size := Vector2(256, 256)
	var draw_rect := Rect2(Vector2.ZERO, texture_size)   # 1 texel = 1 px, the opening zoom
	var uv := {"x": 64, "y": 64, "width": 96, "height": 96}
	var r: Rect2 = Canvas.uv_to_canvas_rect(uv, texture_size, draw_rect)
	var half: float = Canvas.HANDLE_SIZE * 0.5

	var misses := 0
	var sampled := 0
	for corner in ["tl", "tr", "bl", "br"]:
		var p: Vector2 = Canvas.uv_to_canvas_rect(uv, texture_size, draw_rect).position
		match corner:
			"tr": p += Vector2(r.size.x, 0)
			"bl": p += Vector2(0, r.size.y)
			"br": p += r.size
		# The drawn square, swept at quarter-pixel steps and INCLUSIVE of its own corners —
		# the corners are the whole point, since they are the pixels the circle stranded.
		var dx := -half
		while dx <= half:
			var dy := -half
			while dy <= half:
				sampled += 1
				if Canvas.hit_test(p + Vector2(dx, dy), uv, texture_size, draw_rect,
						Canvas.HANDLE_GRAB) != corner:
					misses += 1
				dy += 0.25
			dx += 0.25
	_assert_eq(misses, 0,
		"every one of the %d sampled pixels inside the drawn handle grabs its corner" % sampled)
	_assert_true(sampled > 4000, "and the sweep is dense enough to mean it (%d points)" % sampled)


## The relationship that cannot strand a visible pixel: the grab target is a rect, it is
## LARGER than the square drawn inside it, and it reaches its full half OUTWARD.
func _test_the_grab_target_is_bigger_than_the_square_it_is_drawn_as() -> void:
	_assert_true(Canvas.HANDLE_GRAB > Canvas.HANDLE_SIZE,
		"the grab size (%.1f) exceeds the drawn size (%.1f)" % [Canvas.HANDLE_GRAB, Canvas.HANDLE_SIZE])
	# A box big enough that the inward bound never binds, so this reads the raw reach.
	var box := Rect2(Vector2(100, 100), Vector2(96, 96))
	var g: Rect2 = Canvas.corner_grab_rect(box, "tl", Canvas.HANDLE_GRAB)
	_assert_eq(g.position, Vector2(100.0 - Canvas.HANDLE_GRAB * 0.5, 100.0 - Canvas.HANDLE_GRAB * 0.5),
		"the tl target starts a full half OUTWARD of the corner")
	_assert_eq(g.size, Vector2(Canvas.HANDLE_GRAB, Canvas.HANDLE_GRAB),
		"and is the full grab square where the box has room for it")
	# 196px2 against the circle's 50.3px2 — a 3.9x target for the same picture.
	_assert_true(g.get_area() > 3.5 * PI * pow(Canvas.HANDLE_SIZE * 0.5, 2.0),
		"which is 3.9x the radius-%0.1f circle it replaced (%.0fpx2 against %.1fpx2)"
			% [Canvas.HANDLE_SIZE * 0.5, g.get_area(), PI * pow(Canvas.HANDLE_SIZE * 0.5, 2.0)])


## THE MIDDLE THIRD OF EACH AXIS IS THE BODY'S, and that bound is why a 14px target is
## safe on a surface where the box scales with zoom and the handle does not. `FramesetCanvas`
## already records the case in its own header: a fit that snaps down a rung draws a 12px UV
## box at 6px, "smaller than its own 8px corner handles".
##
## The bound is not a concession — it is a REPAIR. Under the old radius-4 circles that same
## 6px box had 0.3px2 of body left, so the MOVE gesture was already gone; under the bound it
## has 17.9px2 back.
func _test_the_body_keeps_the_middle_third_however_small_the_box() -> void:
	for side in [6.0, 12.0, 23.0, 96.0]:
		var box := Rect2(Vector2(50, 50), Vector2(side, side))
		var third: float = side / 3.0
		for corner in ["tl", "tr", "bl", "br"]:
			var g: Rect2 = Canvas.corner_grab_rect(box, corner, Canvas.HANDLE_GRAB)
			var inward_x: float = (g.end.x - box.position.x) if corner in ["tl", "bl"] \
				else (box.end.x - g.position.x)
			var inward_y: float = (g.end.y - box.position.y) if corner in ["tl", "tr"] \
				else (box.end.y - g.position.y)
			_assert_true(inward_x <= third + 0.001 and inward_y <= third + 0.001,
				"a %.0fpx box keeps its middle third for the body: %s reaches %.2f/%.2f in, third is %.2f"
					% [side, corner, inward_x, inward_y, third])
		# And the centre is genuinely still a body press, which is the gesture that matters.
		var uv := {"x": 50, "y": 50, "width": int(side), "height": int(side)}
		_assert_eq(Canvas.hit_test(box.get_center(), uv, Vector2(256, 256),
			Rect2(Vector2.ZERO, Vector2(256, 256)), Canvas.HANDLE_GRAB), "body",
			"the centre of a %.0fpx box still starts a MOVE, not a resize" % side)


## The one thing the old circle did that the rect does not, and it was never right: a press
## OUTSIDE the box, beside the middle of an edge, used to grab whichever corner's circle
## bulged that far. Swept over the corpus this is 5,614 of 21.2M sampled points (0.03%) and
## **100% of them are outside the box they used to grab** — so it is a refusal gained, not a
## target lost.
func _test_a_press_beside_an_edge_is_not_a_corner() -> void:
	var texture_size := Vector2(256, 256)
	var draw_rect := Rect2(Vector2.ZERO, texture_size)
	# E004 frameset 38's smaller region, which is where the corpus sweep found this shape.
	var uv := {"x": 216, "y": 0, "width": 8, "height": 8}
	_assert_eq(Canvas.hit_test(Vector2(215.5, 3.5), uv, texture_size, draw_rect,
		Canvas.HANDLE_GRAB), "",
		"a press beside the middle of the left edge, outside the box, resizes nothing")
	_assert_eq(Canvas.hit_test(Vector2(215.5, 0.5), uv, texture_size, draw_rect,
		Canvas.HANDLE_GRAB), "tl",
		"beside the TOP-left of that same edge it is still the tl handle")


func _test_canvas_move_uv_shifts_x_y_only() -> void:
	var uv := {"x": 10, "y": 5, "width": 20, "height": 10}
	var moved: Dictionary = Canvas.move_uv(uv, Vector2(3, -2))
	_assert_eq(moved, {"x": 13, "y": 3, "width": 20, "height": 10},
		"moving shifts x/y by the delta and leaves width/height untouched")


func _test_canvas_move_uv_clamps_to_non_negative() -> void:
	var uv := {"x": 2, "y": 1, "width": 20, "height": 10}
	var moved: Dictionary = Canvas.move_uv(uv, Vector2(-5, -10))
	_assert_eq(moved, {"x": 0, "y": 0, "width": 20, "height": 10},
		"moving off the top-left edge clamps x/y to 0 (unsigned bytes)")


func _test_canvas_resize_uv_from_br_pins_top_left() -> void:
	var uv := {"x": 10, "y": 5, "width": 20, "height": 10}
	var resized: Dictionary = Canvas.resize_uv(uv, "br", Vector2(35, 20))
	_assert_eq(resized, {"x": 10, "y": 5, "width": 25, "height": 15},
		"dragging the br handle keeps the tl corner (x,y) fixed and grows width/height")


func _test_canvas_resize_uv_from_tl_pins_bottom_right() -> void:
	var uv := {"x": 10, "y": 5, "width": 20, "height": 10}
	var resized: Dictionary = Canvas.resize_uv(uv, "tl", Vector2(12, 8))
	_assert_eq(resized, {"x": 12, "y": 8, "width": 18, "height": 7},
		"dragging the tl handle keeps the br corner (x+width, y+height) fixed")


## ---- ADR-0099 step 0: the three flip-blind defects -------------------------
## 2,628 frames across 179 effects carry a negative uv.width/height. A negative
## width means the stored `x` is the block's LAST column (E005 stores the same
## 32x32 block as (8,40,32,32) and as (39,40,-32,32), 39 - 32 + 1 = 8) — the
## convention pinned by folding 847 raw corpus tuples onto blocks that already
## exist, against 0 for the off-by-one reading. Three functions here predate
## that measurement and are blind to it.


func _test_normalised_block_folds_the_flip_out() -> void:
	# The region key of ADR-0099 dec. 1 — and the fold the three fixes below share.
	_assert_eq(Canvas.normalised_block({"x": 8, "y": 40, "width": 32, "height": 32}),
		Rect2i(8, 40, 32, 32), "an upright rect is already its own block")
	_assert_eq(Canvas.normalised_block({"x": 39, "y": 40, "width": -32, "height": 32}),
		Rect2i(8, 40, 32, 32), "E005's mirrored twin folds onto the identical block")
	_assert_eq(Canvas.normalised_block({"x": 8, "y": 71, "width": 32, "height": -32}),
		Rect2i(8, 40, 32, 32), "a vertical flip folds the same way on y")
	_assert_eq(Canvas.normalised_block({"x": 39, "y": 71, "width": -32, "height": -32}),
		Rect2i(8, 40, 32, 32), "and both flips together still name one block")


func _test_block_to_uv_writes_from_the_members_own_signs() -> void:
	# ADR-0099 dec. 4: a region write computes the block ONCE, then each member
	# stores it through its own flip. A mirrored member stays mirrored.
	var block := Rect2i(8, 40, 32, 32)
	_assert_eq(Canvas.block_to_uv({"x": 0, "y": 0, "width": 20, "height": 20}, block),
		{"x": 8, "y": 40, "width": 32, "height": 32}, "an upright member stores the block corner")
	_assert_eq(Canvas.block_to_uv({"x": 0, "y": 0, "width": -20, "height": 20}, block),
		{"x": 39, "y": 40, "width": -32, "height": 32}, "a mirrored member stores the LAST column")
	_assert_eq(Canvas.block_to_uv({"x": 0, "y": 0, "width": 20, "height": -20}, block),
		{"x": 8, "y": 71, "width": 32, "height": -32}, "a v-flipped member stores the last ROW")
	# The round trip is exact for all 22,920 corpus frames (oracle, decoded in Python).
	for uv in [{"x": 104, "y": 176, "width": 23, "height": 23},
			{"x": 39, "y": 40, "width": -32, "height": 32},
			{"x": 8, "y": 71, "width": 32, "height": -32},
			{"x": 39, "y": 71, "width": -32, "height": -32}]:
		_assert_eq(Canvas.block_to_uv(uv, Canvas.normalised_block(uv)), uv,
			"block_to_uv(normalised_block(uv)) is the identity on %s" % [uv])


func _test_canvas_resize_uv_preserves_a_mirrored_frames_flip() -> void:
	# THE defect: `resize_uv` normalised through min/max and wrote a positive
	# width back, so the first corner drag on any of those 2,628 frames silently
	# unflipped it — the sprite mirrors, with no diagnostic anywhere.
	var uv := {"x": 39, "y": 40, "width": -32, "height": 32}
	var grown: Dictionary = Canvas.resize_uv(uv, "br", Vector2(48, 72))
	_assert_eq(Canvas.normalised_block(grown), Rect2i(8, 40, 40, 32),
		"dragging br out grows the block rightward, tl pinned")
	_assert_eq(grown, {"x": 47, "y": 40, "width": -40, "height": 32},
		"and the member stores it mirrored still (8 + 40 - 1 = 47)")

	var pulled: Dictionary = Canvas.resize_uv(uv, "tl", Vector2(16, 48))
	_assert_eq(Canvas.normalised_block(pulled), Rect2i(16, 48, 24, 24),
		"dragging tl in shrinks the block, br pinned")
	_assert_eq(pulled["width"], -24, "the flip survives a tl drag too")

	var v := {"x": 8, "y": 71, "width": 32, "height": -32}
	_assert_eq(Canvas.resize_uv(v, "br", Vector2(40, 80))["height"], -40,
		"a vertical flip survives its own resize")


func _test_canvas_coverage_counts_a_mirrored_frames_texels() -> void:
	# `coverage_mask` computed x1 = x + width, so a negative width gave an EMPTY
	# range and the frame contributed zero coverage. The E019/E317 oracles below
	# survived it only because every flipped rect there has an unflipped twin.
	var mirrored := [{"frames": [{"uv": {"x": 39, "y": 40, "width": -32, "height": 32}}]}]
	_assert_eq(Canvas.covered_texel_count(mirrored, Vector2i(128, 128)), 32 * 32,
		"a mirrored frame addresses its 32x32 block, not nothing")
	var mask: PackedByteArray = Canvas.coverage_mask(mirrored, Vector2i(128, 128))
	_assert_eq(mask[40 * 128 + 8], 1, "the block's left column is covered")
	_assert_eq(mask[40 * 128 + 39], 1, "and its right column (the stored x) is too")
	_assert_eq(mask[40 * 128 + 40], 0, "one past the block is not")

	var flipped_both := [{"frames": [{"uv": {"x": 39, "y": 71, "width": -32, "height": -32}}]}]
	_assert_eq(Canvas.covered_texel_count(flipped_both, Vector2i(128, 128)), 32 * 32,
		"a doubly-flipped frame covers the same block")


func _test_canvas_uv_rect_of_a_mirrored_frame_is_a_positive_rect() -> void:
	# `uv_to_canvas_rect` multiplied the signed width through, so a flipped frame
	# drew (and hit-tested) as a NEGATIVE-size Rect2. Every member of a region has
	# the identical block, so there is exactly one rectangle to draw (dec. 8).
	var uv := {"x": 39, "y": 40, "width": -32, "height": 32}
	var r: Rect2 = Canvas.uv_to_canvas_rect(uv, Vector2(128, 128), Rect2(0, 0, 128, 128))
	_assert_eq(r, Rect2(8, 40, 32, 32), "the mirrored frame draws as its block, positively")


func _test_canvas_hit_test_grabs_a_mirrored_frames_body() -> void:
	# The consequence of the above: `has_point` is false for every point of a
	# negative-size Rect2, so a flipped frame's box could not be grabbed by its
	# BODY at all — only by a corner handle, which routed the author straight
	# into the silent-unflip above.
	var uv := {"x": 39, "y": 40, "width": -32, "height": 32}
	var ts := Vector2(128, 128)
	var dr := Rect2(0, 0, 128, 128)
	_assert_eq(Canvas.hit_test(Vector2(20, 50), uv, ts, dr, Canvas.HANDLE_SIZE), "body",
		"a point inside the mirrored frame's block grabs the body")
	_assert_eq(Canvas.hit_test(Vector2(8, 40), uv, ts, dr, Canvas.HANDLE_SIZE), "tl",
		"the block's visual top-left is the tl handle, whatever the signs say")
	_assert_eq(Canvas.hit_test(Vector2(40, 72), uv, ts, dr, Canvas.HANDLE_SIZE), "br",
		"and its visual bottom-right is br")
	_assert_eq(Canvas.hit_test(Vector2(100, 100), uv, ts, dr, Canvas.HANDLE_SIZE), "",
		"a point outside it still grabs nothing")


## ---- ADR-0099 step 1: the region query ------------------------------------
## A frame does not own its UV rect; it shares it. Membership is EXACT equality
## of the normalised block (dec. 2) — never overlap, never containment. Every
## number asserted below was decoded outside this codebase, straight off
## `frames.json` in Python, so the oracle can genuinely disagree with the code.


func _test_region_membership_is_exact_equality_of_the_block() -> void:
	# Overlap is not sameness (dec. 2). E173 holds five rects at ONE origin —
	# a beam drawn at five lengths — plus a sprite nested inside their footprint;
	# no single rect can represent them, so nothing but equality will do.
	var framesets := [{"frames": [
		{"uv": {"x": 8, "y": 40, "width": 32, "height": 32}},      # 0: the block
		{"uv": {"x": 39, "y": 40, "width": -32, "height": 32}},    # 1: same block, mirrored
		{"uv": {"x": 8, "y": 40, "width": 40, "height": 32}},      # 2: same origin, longer
		{"uv": {"x": 16, "y": 48, "width": 8, "height": 8}},       # 3: nested inside
		{"uv": {"x": 8, "y": 41, "width": 32, "height": 32}},      # 4: one texel down
	]}]
	var members: Array = Canvas.region_members(framesets, Rect2i(8, 40, 32, 32))
	_assert_eq(members.size(), 2, "only the two frames whose BLOCK is equal are members")
	_assert_eq([members[0]["frame_index"], members[1]["frame_index"]], [0, 1],
		"and the mirrored twin is one of them")
	_assert_eq(Canvas.region_members(framesets, Rect2i(8, 40, 40, 32)).size(), 1,
		"sharing an origin at a different length is a DIFFERENT region")
	_assert_eq(Canvas.region_members(framesets, Rect2i(16, 48, 8, 8)).size(), 1,
		"being nested inside another region's footprint is not membership")
	_assert_eq(Canvas.region_of(framesets, 0, 1), Rect2i(8, 40, 32, 32),
		"a mirrored frame reports the block it shares, not its stored tuple")


func _test_region_index_reproduces_the_measured_e019_sheet() -> void:
	# E019: 100 framesets, 184 frames — and FOURTEEN distinct regions. Editing a
	# sprite there one frame at a time is 30 identical drags.
	var framesets = _load_framesets("E019")
	if framesets == null:
		print("[SKIP] E019 frames.json not present in this worktree")
		return
	var index: Dictionary = Canvas.region_index(framesets)
	_assert_eq(index.size(), 14, "E019's 184 frames address exactly 14 sheet regions")
	var biggest := Rect2i(104, 176, 23, 23)
	_assert_eq(index.get(biggest, 0), 30, "its largest region carries 30 frames")
	var members: Array = Canvas.region_members(framesets, biggest)
	var framesets_touched := {}
	for m in members:
		framesets_touched[m["frameset_index"]] = true
	_assert_eq(framesets_touched.size(), 15, "spread across 15 framesets")
	var total := 0
	for count in index.values():
		total += int(count)
	_assert_eq(total, 184, "and every frame belongs to exactly one region")


func _test_region_members_carry_the_facets_the_scope_control_filters_on() -> void:
	# dec. 5's member list: the count is stated BEFORE the drag, and each member
	# is nameable — because 330+ corpus groups mix orientations and 62% of them
	# draw at more than one size, so "30 frames" alone is not enough to consent to.
	var framesets = _load_framesets("E005")
	if framesets == null:
		print("[SKIP] E005 frames.json not present in this worktree")
		return
	# E005 stores this one 32x32 block twice: frameset 17 upright, frameset 26
	# mirrored. The identical texels, one drawn flipped.
	var members: Array = Canvas.region_members(framesets, Rect2i(8, 40, 32, 32))
	_assert_eq(members.size(), 2, "E005's (8,40,32x32) region has two members")
	_assert_eq([members[0]["frameset_index"], members[1]["frameset_index"]], [17, 26],
		"framesets 17 and 26")
	_assert_eq(members[0]["mirrored"], false, "the first is drawn upright")
	_assert_eq(members[1]["mirrored"], true, "the second is drawn mirrored")
	_assert_eq(members[0]["anchor"], "tl", "so its stored (x,y) is the block's top-left")
	_assert_eq(members[1]["anchor"], "tr", "and the mirrored one's is the top-RIGHT (dec. 8)")
	for m in members:
		_assert_true(m.has("orientation") and m.has("palette_id") and m.has("quad_size"),
			"every member names its orientation, palette and drawn size")


func _test_anchor_corner_follows_the_measured_sign_table() -> void:
	# dec. 8: for 2,628 corpus frames the stored (x,y) is NOT the top-left, so the
	# canvas must colour the corner the fields actually refer to or it contradicts
	# the box on screen. Corpus census: TL 20,292 / TR 1,498 / BL 633 / BR 497.
	_assert_eq(Canvas.anchor_corner({"width": 32, "height": 32}), "tl", "+/+ names the top-left")
	_assert_eq(Canvas.anchor_corner({"width": -32, "height": 32}), "tr", "-/+ names the top-right")
	_assert_eq(Canvas.anchor_corner({"width": 32, "height": -32}), "bl", "+/- names the bottom-left")
	_assert_eq(Canvas.anchor_corner({"width": -32, "height": -32}), "br", "-/- names the bottom-right")


func _test_a_region_move_writes_every_member_through_its_own_signs() -> void:
	# dec. 4, the number most likely to be wrong: the new block is computed ONCE,
	# then each member stores it through ITS OWN flip. A mirrored member stays
	# mirrored. An off-by-one here shifts every mirrored member by one column.
	var framesets := [{"frames": [
		{"uv": {"x": 8, "y": 40, "width": 32, "height": 32}, "palette_id": 3},
		{"uv": {"x": 39, "y": 40, "width": -32, "height": 32}, "palette_id": 5},
	]}]
	var members: Array = Canvas.region_members(framesets, Rect2i(8, 40, 32, 32))
	var edits: Array = Canvas.region_edits(framesets, members, Rect2i(16, 48, 32, 32))

	# dec. 9: this lowers to apply_compound over members x their CHANGED uv fields.
	# Only x and y moved, so only x and y are written — a move never rewrites size.
	_assert_eq(edits.size(), 4, "two members x two changed fields (x, y) — not four fields each")
	var by_ref := {}
	for e in edits:
		var r: Dictionary = e["field_ref"]
		by_ref["%d/%d/%s" % [r["frameset_index"], r["frame_index"], r["field"]]] = e["new_raw"]
	_assert_eq(by_ref.get("0/0/uv_x"), 16, "the upright member stores the block's left column")
	_assert_eq(by_ref.get("0/1/uv_x"), 47, "the mirrored member stores its LAST column (16 + 32 - 1)")
	_assert_eq(by_ref.get("0/0/uv_y"), 48, "both store the same top row")
	_assert_eq(by_ref.get("0/1/uv_y"), 48, "since only the width is flipped")
	for e in edits:
		_assert_true(String(e["field_ref"]["field"]).begins_with("uv_"),
			"a region edit writes UV fields and nothing else (dec. 3)")


func _test_a_region_edit_that_changes_nothing_produces_no_edit() -> void:
	# Only CHANGED fields are emitted, so a drag that lands where it started is not
	# an undo entry the author has to press ctrl-Z through.
	var framesets := [{"frames": [{"uv": {"x": 8, "y": 40, "width": 32, "height": 32}}]}]
	var members: Array = Canvas.region_members(framesets, Rect2i(8, 40, 32, 32))
	_assert_eq(Canvas.region_edits(framesets, members, Rect2i(8, 40, 32, 32)).size(), 0,
		"landing on the block it started on is a no-op, not a compound edit")


func _test_a_resize_onto_a_neighbouring_block_announces_who_would_join() -> void:
	# Blocks frequently share an origin (E173's five beam lengths), so dragging a
	# corner lands on a neighbour's block ROUTINELY. The merge is silent otherwise
	# and only visible three framesets later, so the chrome must say it before
	# release.
	var framesets := [{"frames": [
		{"uv": {"x": 56, "y": 48, "width": 40, "height": 32}},
		{"uv": {"x": 56, "y": 48, "width": 40, "height": 56}},
		{"uv": {"x": 56, "y": 48, "width": 40, "height": 56}},
		{"uv": {"x": 95, "y": 48, "width": -40, "height": 56}},
	]}]
	var members: Array = Canvas.region_members(framesets, Rect2i(56, 48, 40, 32))
	var quiet: Dictionary = Canvas.region_merge_preview(framesets, members, Rect2i(56, 48, 40, 40))
	_assert_eq(quiet["joining"], 0, "an unoccupied block merges with nobody")
	_assert_true(not quiet["merges"], "so there is nothing to announce")

	var collide: Dictionary = Canvas.region_merge_preview(framesets, members, Rect2i(56, 48, 40, 56))
	_assert_true(collide["merges"], "landing on the 40x56 beam is a merge")
	_assert_eq(collide["joining"], 3, "three more frames would join this group — mirrored ones too")
	_assert_true(collide["message"].contains("(56, 48)") and collide["message"].contains("40")
		and collide["message"].contains("56") and collide["message"].contains("3"),
		"and the announcement names the block and the count: %s" % collide["message"])


## ---- ADR-0099 step 2: can the member actually STORE the block? -------------
## The sign of uv.width/height is NOT in the value — it is a per-frame, per-axis
## flag bit (byte1 bits 4/5) that `parse_frame` applies on read and the writer
## deliberately never authors. frames.json does not carry it, so the Godot side
## can only INFER it from the value the extractor produced. Measured over the
## real E###.BIN corpus: 13,614 frames flag-clear/positive, 996 flag-set/negative,
## and 16 flag-SET but POSITIVE — so "negative" and "flag set" are not the same
## question.


func _test_the_encodable_range_is_inferred_from_the_extracted_value() -> void:
	# flag clear -> the byte is plain unsigned, 0..255 (219 corpus frames carry a
	# dimension above 127 — E022 stores height 176 — and they round-trip fine).
	# flag set -> the byte is read as two's complement, -128..127.
	# A value in 0..127 cannot distinguish the two, so the honest answer is the
	# INTERSECTION, and the canvas says so rather than guessing.
	_assert_eq(Canvas.encodable_uv_range(-32), Vector2i(-128, 127),
		"a negative value proves the sign flag is set")
	_assert_eq(Canvas.encodable_uv_range(176), Vector2i(0, 255),
		"a value above 127 proves it is clear — the parser would have negated it otherwise")
	_assert_eq(Canvas.encodable_uv_range(32), Vector2i(0, 127),
		"0..127 cannot tell, so the safe range is the intersection")


func _test_a_region_resize_refuses_a_block_a_member_cannot_store() -> void:
	# The round trip, run for real over every flip-bearing region of all 401
	# E###.BIN files (extractor -> region move -> write_effect_frames -> re-parse):
	# 5,420 of 5,444 member writes reproduced the block exactly, confirming dec. 4.
	# The 24 that did not are ONE E027 region stored at width -128 — the extreme of
	# the signed byte — grown by 8. The writer masks -136 to byte 120; the sign flag
	# is still set but 120 <= 127, so the parser reads +120. The block is lost AND
	# the flip is lost, silently. It is a representability overflow, not an
	# off-by-one: dec. 4's `x_left + w - 1` was right on all 5,420 others.
	var framesets := [{"frames": [
		{"uv": {"x": 247, "y": 8, "width": -128, "height": 56}},
	]}]
	var members: Array = Canvas.region_members(framesets, Rect2i(120, 8, 128, 56))
	_assert_eq(members.size(), 1, "E027's region is found at its folded block")

	var ok: Dictionary = Canvas.region_write_verdict(framesets, members, Rect2i(120, 8, 120, 56))
	_assert_true(ok["ok"], "shrinking it to 120 wide is storable")

	var over: Dictionary = Canvas.region_write_verdict(framesets, members, Rect2i(120, 8, 136, 56))
	_assert_true(not over["ok"], "growing it to 136 wide is NOT — the byte cannot hold -136")
	_assert_eq(over["blocked"].size(), 1, "and the member that cannot store it is named")
	_assert_true(over["message"].contains("136"),
		"the chrome can say so before release: %s" % over["message"])

	# An UPRIGHT member of the same width has a whole byte to spend, so the same
	# block is fine for it — the bound is per-member, not per-region.
	var upright := [{"frames": [{"uv": {"x": 120, "y": 8, "width": 128, "height": 56}}]}]
	var um: Array = Canvas.region_members(upright, Rect2i(120, 8, 128, 56))
	_assert_true(Canvas.region_write_verdict(upright, um, Rect2i(120, 8, 136, 56))["ok"],
		"an upright member can store 136 — its byte is unsigned")


func _test_a_faithful_uv_bound_reads_the_frames_own_extracted_sign() -> void:
	# The flat -128..127 advisory falsely flagged the 219 corpus frames whose
	# dimension exceeds 127 (E022's height 176 among them), while its comment
	# claimed the imprecision was "advisory-only, not a round-trip bug". The E027
	# measurement above falsifies that: outside the frame's real encodable range
	# the writer's mask silently ALIASES rather than merely being Free-only.
	var data := _fake_data()
	var frame: Dictionary = data.framesets[0]["frames"][0]
	frame["uv"] = {"x": 8, "y": 8, "width": 56, "height": 176}
	var ref := {"channel": "frameset", "frameset_index": 0, "frame_index": 0, "field": "uv_height"}

	var res: Dictionary = Channel.apply_raw(data, ref, 180)
	_assert_true(res.get("faithful", {}).get("ok", false),
		"height 180 on a frame the extractor gave 176 is faithful — its flag is clear")

	frame["uv"] = {"x": 247, "y": 8, "width": -128, "height": 56}
	var wref := {"channel": "frameset", "frameset_index": 0, "frame_index": 0, "field": "uv_width"}
	var bad: Dictionary = Channel.apply_raw(data, wref, -136)
	_assert_true(not bad.get("faithful", {}).get("ok", true),
		"but -136 on E027's flag-set frame is not — the byte aliases to +120")


func _test_fit_scale_is_the_rung_at_which_the_whole_sheet_is_visible() -> void:
	# `fit_scale` is no longer where the view OPENS — it is the floor zooming out stops
	# at, since shrinking past "the whole sheet is visible" only adds margin.
	var canvas_size := Vector2(100, 100)
	var texture_size := Vector2(44, 44)
	_assert_eq(Canvas.fit_scale(canvas_size, texture_size, 0.0), 2.0,
		"a 44x44 sheet in a 100x100 port is wholly visible at rung 2")
	_assert_eq(Canvas.view_rect(canvas_size, texture_size, 0.0, 2.0, Vector2.ZERO),
		Rect2(6, 6, 88, 88), "and lands letterboxed 6px on every side")
	_assert_eq(Canvas.fit_scale(Vector2(297, 270), Vector2(128, 256), Canvas.MARGIN), 0.5,
		"E019's sheet in the real panel is wholly visible only at the 1/2 rung")


func _test_zoom_out_stops_once_the_whole_sheet_is_visible() -> void:
	# E019 at the real panel: opens at 1:1 (overflowing), one wheel-down shows the whole
	# sheet at 1/2, and there it stops — smaller would be margin, not information.
	var canvas = Canvas.new()
	canvas.size = Vector2(297, 270)
	canvas._texture = ImageTexture.create_from_image(
		Image.create(128, 256, false, Image.FORMAT_RGBA8))
	_assert_eq(canvas.current_scale(), 1.0, "it opens at 100%")

	canvas._zoom_at(Vector2(148, 135), -1)
	_assert_eq(canvas.current_scale(), 0.5, "one step out shows the whole sheet")
	canvas._zoom_at(Vector2(148, 135), -1)
	_assert_eq(canvas.current_scale(), 0.5, "and it will not shrink past that")
	canvas.free()


func _test_zoom_out_is_refused_when_the_sheet_already_fits() -> void:
	# A small sheet is wholly visible at 1:1 already, so there is nothing to zoom out to.
	var canvas = Canvas.new()
	canvas.size = Vector2(297, 270)
	canvas._texture = ImageTexture.create_from_image(
		Image.create(44, 44, false, Image.FORMAT_RGBA8))
	_assert_eq(canvas.current_scale(), 1.0, "it opens at 100%, not at the 5x that would fit")
	canvas._zoom_at(Vector2(148, 135), -1)
	_assert_eq(canvas.current_scale(), 1.0, "zooming out below 1:1 is refused")
	canvas._zoom_at(Vector2(148, 135), 1)
	_assert_eq(canvas.current_scale(), 2.0, "zooming in still walks the ladder")
	canvas.free()


func _test_canvas_view_rect_scales_around_center() -> void:
	var canvas_size := Vector2(100, 100)
	var texture_size := Vector2(44, 44)
	var fit: Rect2 = Canvas.view_rect(canvas_size, texture_size, 0.0, 2.0, Vector2.ZERO)
	var zoomed: Rect2 = Canvas.view_rect(canvas_size, texture_size, 0.0, 4.0, Vector2.ZERO)
	_assert_eq(zoomed.size, fit.size * 2.0, "rung 2 -> rung 4 doubles the draw size")
	_assert_eq(zoomed.get_center(), fit.get_center(), "zoom keeps the same center when pan is zero")


func _test_canvas_zoom_at_cursor_keeps_that_texture_pixel_fixed() -> void:
	# A 300x300 sheet in a 200x200 widget: bigger than the port at 100%, so there is
	# real pan slack and the held texel is genuinely reachable rather than trivially
	# center-locked. The cursor is off-center on both axes for the same reason.
	var canvas = Canvas.new()
	canvas.size = Vector2(200, 200)
	canvas._texture = ImageTexture.create_from_image(
		Image.create(300, 300, false, Image.FORMAT_RGBA8))
	canvas._frame = {"uv": {"x": 0, "y": 0, "width": 10, "height": 10}}
	var texture_size := Vector2(300, 300)
	var cursor := Vector2(120, 90)

	var tex_px_before: Vector2 = Canvas.canvas_point_to_texture_pixel(
		cursor, texture_size, canvas.current_draw_rect())
	_assert_eq(canvas.current_scale(), 1.0, "a fresh bind is at 100%")

	canvas._zoom_at(cursor, 1)

	var tex_px_after: Vector2 = Canvas.canvas_point_to_texture_pixel(
		cursor, texture_size, canvas.current_draw_rect())
	_assert_true(tex_px_before.distance_to(tex_px_after) < 0.01,
		"zooming toward the cursor keeps that texture pixel under the cursor")
	_assert_eq(canvas._zoom_steps, 1, "_zoom_at walked exactly one rung up")
	_assert_eq(canvas.current_scale(), 2.0, "one rung above 1:1 is 2x")
	canvas.free()


func _test_pixel_ladder_snaps_a_fractional_fit_down_to_a_rung() -> void:
	# The two measurements ADR-0098 dec. 2 costs out by name.
	_assert_eq(Canvas.ladder_snap(1.098), 1.0, "E019's 1.098x fit snaps down to 1:1")
	_assert_eq(Canvas.ladder_snap(2.195), 2.0, "E317's 2.195x fit snaps down to 2x")
	_assert_eq(Canvas.ladder_snap(3.999), 3.0, "snapping is DOWN, never to-nearest")
	_assert_eq(Canvas.ladder_snap(2.0), 2.0, "an exact rung is left alone")
	_assert_eq(Canvas.ladder_snap(99.0), Canvas.ZOOM_MAX, "the ladder tops out at ZOOM_MAX")


func _test_pixel_ladder_shrinks_an_oversized_sheet_through_reciprocal_integers() -> void:
	# Below 1:1 the rungs are 1/2, 1/3, ... — one texel is still a whole number of
	# screen pixels' worth of sheet, just the other way round.
	_assert_eq(Canvas.ladder_snap(0.7), 0.5, "0.7 shrinks to 1/2")
	_assert_eq(Canvas.ladder_snap(0.5), 0.5, "1/2 is itself a rung")
	_assert_eq(Canvas.ladder_snap(0.4), 1.0 / 3.0, "0.4 shrinks to 1/3, not to 1/2")
	# A 256x256 sheet in a 100x100 port: raw 0.39 -> 1/3 (1/2 would overflow).
	_assert_eq(Canvas.fit_scale(Vector2(100, 100), Vector2(256, 256), 0.0), 1.0 / 3.0,
		"a sheet larger than the port fits at a reciprocal-integer rung")


func _test_pixel_ladder_step_walks_rungs_in_both_directions() -> void:
	# The ladder is not a constant ratio, so stepping is a rung WALK: 1->2 doubles,
	# 2->3 does not, and the two halves meet at 1:1 without a gap.
	_assert_eq(Canvas.ladder_step(1.0, true), 2.0, "up from 1:1 is 2x")
	_assert_eq(Canvas.ladder_step(2.0, true), 3.0, "up from 2x is 3x, not 4x")
	_assert_eq(Canvas.ladder_step(Canvas.ZOOM_MAX, true), Canvas.ZOOM_MAX, "the top rung is a stop")
	_assert_eq(Canvas.ladder_step(1.0, false), 0.5, "down from 1:1 crosses into 1/2")
	_assert_eq(Canvas.ladder_step(0.5, false), 1.0 / 3.0, "down from 1/2 is 1/3")
	_assert_eq(Canvas.ladder_step(0.5, true), 1.0, "up from 1/2 crosses back to 1:1")
	_assert_eq(Canvas.ladder_advance(1.0, 3), 4.0, "three rungs above 1:1 is 4x")
	_assert_eq(Canvas.ladder_advance(1.0, -2), 1.0 / 3.0, "two rungs below 1:1 is 1/3")
	_assert_eq(Canvas.ladder_advance(3.0, 0), 3.0, "zero steps is the identity")


func _test_view_rect_is_a_whole_number_of_screen_pixels_per_texel() -> void:
	# The property the per-texel readout (dec. 6) depends on, asserted across the
	# whole range of widths the inspector row can hand the canvas — not just the
	# one size that happens to divide evenly.
	var texture_size := Vector2(44, 256)
	var offenders := 0
	for w in range(90, 400, 7):
		var canvas_size := Vector2(float(w), float(w))
		var scale: float = Canvas.fit_scale(canvas_size, texture_size, Canvas.MARGIN)
		var on_a_rung: bool = (
			absf(scale - roundf(scale)) < 1e-6 if scale >= 1.0
			else absf(1.0 / scale - roundf(1.0 / scale)) < 1e-6)
		var r: Rect2 = Canvas.view_rect(canvas_size, texture_size, Canvas.MARGIN, scale, Vector2.ZERO)
		if not on_a_rung or r.size != texture_size * scale:
			offenders += 1
	_assert_eq(offenders, 0, "every panel width draws the sheet at an exact ladder rung")


func _test_pan_is_clamped_per_axis() -> void:
	# ADR-0098 dec. 8 AMENDED. Both its original sentences were false in practice:
	# slack of (sheet - available)/2 keeps the PORT inside the SHEET, which means no
	# corner of the sheet can ever be brought to the middle of the port — exactly where
	# an author zoomed to rung 16 wants to work, and where the region chrome has room.
	# And it center-locked any letterboxed axis outright, so a tall sheet in a wide port
	# could not be nudged at all. The rule is now slack (available + sheet)/2 on BOTH
	# axes, which lets any texel reach the port centre and does not special-case
	# letterboxing. It stays a CLAMP, so the sheet is always draggable back — the
	# unrecoverable-view failure dec. 8 was written against was the UNBOUNDED pan, not
	# a generous one (and `reset_view` now has a key, below).
	var canvas_size := Vector2(100, 100)
	var texture_size := Vector2(50, 25)
	# rung 4: a 200x100 sheet in a 100x100 port. slack = (100 + 200)/2 = 150 on x,
	# (100 + 100)/2 = 100 on y.
	_assert_eq(Canvas.clamp_pan(canvas_size, texture_size, 0.0, 4.0, Vector2(999, 999)),
		Vector2(150, 100), "each axis pans by (available + sheet)/2")
	_assert_eq(Canvas.clamp_pan(canvas_size, texture_size, 0.0, 4.0, Vector2(-999, -999)),
		Vector2(-150, -100), "the clamp is symmetric")
	_assert_eq(Canvas.clamp_pan(canvas_size, texture_size, 0.0, 4.0, Vector2(10, 0)),
		Vector2(10, 0), "a pan already inside the slack is untouched")

	# The property that motivated the amendment: the sheet's far CORNER can be brought
	# to the centre of the port, on both axes, at any rung.
	var corner := Vector2(texture_size.x, texture_size.y)      # the bottom-right texel
	var centre := canvas_size * 0.5
	for scale in [1.0, 4.0, 16.0]:
		var want: Vector2 = Canvas.pan_to_hold(canvas_size, texture_size, 0.0, scale, corner, centre)
		_assert_eq(Canvas.clamp_pan(canvas_size, texture_size, 0.0, scale, want), want,
			"at rung %s the far corner reaches the port centre unclamped" % scale)

	# A letterboxed axis is no longer centre-locked.
	var fit: float = Canvas.fit_scale(canvas_size, texture_size, 0.0)
	_assert_true(Canvas.clamp_pan(canvas_size, texture_size, 0.0, fit, Vector2(999, 999)) != Vector2.ZERO,
		"a letterboxed sheet can still be nudged off centre")
	# But it is still a clamp — never unbounded, so the sheet is always draggable back.
	var far: Vector2 = Canvas.clamp_pan(canvas_size, texture_size, 0.0, 16.0, Vector2(1e9, 1e9))
	_assert_true(far.x < 1e8 and far.y < 1e8, "the pan is still bounded, so the view is recoverable")


## ---- ADR-0099 step 3: input rebinding (dec. 6) -----------------------------
## Scope is a visible control, never a modifier — so the chords must be the ones
## the rest of the studio already uses. FramesetCanvas was the outlier that bound
## PAN to right-drag; EffectScoreTimeline:1051, EffectFramesBar:103/116 and
## FedsPairLanePanel:917/921 all pan on middle-drag + Shift+left-drag, and both
## EffectScoreTimeline and ColourKeyframeTrack open a context menu on right-click.


func _test_pan_moves_off_right_drag_to_middle_and_shift_left() -> void:
	var canvas = _panning_canvas()
	canvas._gui_input(_button(MOUSE_BUTTON_MIDDLE, true, Vector2(100, 100)))
	canvas._gui_input(_motion(Vector2(120, 130)))
	_assert_eq(canvas._pan, Vector2(20, 30), "middle-drag pans")
	canvas._gui_input(_button(MOUSE_BUTTON_MIDDLE, false, Vector2(120, 130)))

	canvas._pan = Vector2.ZERO
	var shift_press := _button(MOUSE_BUTTON_LEFT, true, Vector2(100, 100))
	shift_press.shift_pressed = true
	canvas._gui_input(shift_press)
	canvas._gui_input(_motion(Vector2(90, 80)))
	_assert_eq(canvas._pan, Vector2(-10, -20), "Shift+left-drag pans the same way")
	canvas.free()


func _test_right_drag_no_longer_pans_so_right_click_is_free() -> void:
	# Right-click is the studio's context-menu button everywhere else; dec. 6 frees it
	# here for the region's menu.
	var canvas = _panning_canvas()
	canvas._gui_input(_button(MOUSE_BUTTON_RIGHT, true, Vector2(100, 100)))
	canvas._gui_input(_motion(Vector2(160, 160)))
	_assert_eq(canvas._pan, Vector2.ZERO, "right-drag does not pan any more")
	canvas.free()


func _test_shift_is_tested_before_the_uv_box_hit_test() -> void:
	# The ordering hazard EffectFramesBar:111 already documents for its own Alt branch:
	# a Shift-drag STARTING INSIDE the box must pan, not move the box. The press below
	# is dead centre of the UV rect, where the body hit-test would otherwise win.
	var canvas = _panning_canvas()
	canvas._frame = {"uv": {"x": 10, "y": 10, "width": 40, "height": 40}}
	# The sheet is 400x400 (`_panning_canvas`), not the 200x200 port — passing the port
	# size here silently puts `inside` outside the box.
	var inside: Vector2 = Canvas.uv_to_canvas_rect(canvas._frame["uv"],
		Vector2(400, 400), canvas.current_draw_rect()).get_center()

	var press := _button(MOUSE_BUTTON_LEFT, true, inside)
	press.shift_pressed = true
	canvas._gui_input(press)
	_assert_eq(canvas._drag_mode, "", "a Shift+left press inside the box starts no box drag")
	canvas._gui_input(_motion(inside + Vector2(15, 15)))
	_assert_eq(canvas._pan, Vector2(15, 15), "it pans instead")
	_assert_eq(canvas._frame["uv"]["x"], 10, "and the box did not move")

	# Plain left inside the box still moves it — the Shift branch stole nothing.
	canvas._gui_input(_button(MOUSE_BUTTON_LEFT, false, inside))
	canvas._pan = Vector2.ZERO
	canvas._gui_input(_button(MOUSE_BUTTON_LEFT, true, inside))
	_assert_eq(canvas._drag_mode, "body", "plain left-drag still grabs the box body")
	canvas.free()


## The rule reaching the PRESS PATH, not only `hit_test`. `effect-studio-predicate-tested-
## not-behaviour` is this file's own lesson: one predicate, two consumers, only one guarded.
## `_gui_input` has to be handed `HANDLE_GRAB` for any of the above to be true of a mouse.
func _test_the_press_path_takes_the_handles_outer_corner() -> void:
	var canvas = _panning_canvas()
	canvas._frame = {"uv": {"x": 10, "y": 10, "width": 40, "height": 40}}
	var box: Rect2 = Canvas.uv_to_canvas_rect(canvas._frame["uv"],
		Vector2(400, 400), canvas.current_draw_rect())
	# The DRAWN square's own outer corner: 5.66px out along the diagonal, and the exact
	# pixel the radius-4 circle refused while painting it yellow.
	var outer: Vector2 = box.position - Vector2(1, 1) * (Canvas.HANDLE_SIZE * 0.5)
	canvas._gui_input(_button(MOUSE_BUTTON_LEFT, true, outer))
	_assert_eq(canvas._drag_mode, "tl",
		"a press on the drawn handle's outer corner starts the tl resize it looks like")
	canvas._gui_input(_button(MOUSE_BUTTON_LEFT, false, outer))

	# And the centre still moves — the wider target stole nothing from the body.
	canvas._gui_input(_button(MOUSE_BUTTON_LEFT, true, box.get_center()))
	_assert_eq(canvas._drag_mode, "body", "the box centre still starts a MOVE")
	canvas.free()


func _test_reset_view_has_a_key() -> void:
	# ADR-0098 dec. 8 required a way back to the opening view; `reset_view` was built
	# and left with no key and no button. With the amended (more generous) pan clamp
	# above it is load-bearing, not a convenience.
	var canvas = _panning_canvas()
	canvas._zoom_steps = 3
	canvas._pan = Vector2(40, 40)
	var key := InputEventKey.new()
	key.keycode = KEY_HOME
	key.pressed = true
	canvas._gui_input(key)
	_assert_eq(canvas._pan, Vector2.ZERO, "Home restores the opening pan")
	_assert_eq(canvas._zoom_steps, 0, "and the opening 100% zoom")
	canvas.free()


func _panning_canvas():
	# 400x400 sheet in a 200x200 port: real slack on both axes at 100%, so a pan is
	# never trivially clamped to zero.
	var canvas = Canvas.new()
	canvas.size = Vector2(200, 200)
	canvas._texture = ImageTexture.create_from_image(
		Image.create(400, 400, false, Image.FORMAT_RGBA8))
	return canvas


func _button(index: int, pressed: bool, at: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = index
	e.pressed = pressed
	e.position = at
	return e


func _motion(at: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = at
	return e


func _test_the_overlay_colours_the_anchor_corner_apart() -> void:
	# ADR-0099 dec. 8's other half. Every member of a region has the IDENTICAL block,
	# so there is exactly one rectangle to draw and the anchor colour is the only
	# per-member difference there is. For a mirrored frame the stored (x,y) is the
	# top-RIGHT, and painting the top-left as the anchor would contradict the
	# spinboxes sitting next to the canvas.
	var upright := {"x": 8, "y": 40, "width": 32, "height": 32}
	var mirrored := {"x": 39, "y": 40, "width": -32, "height": 32}
	_assert_eq(Canvas.handle_color("tl", upright, ""), Canvas.ANCHOR_COLOR,
		"an upright frame anchors at the top-left")
	_assert_eq(Canvas.handle_color("tr", upright, ""), Canvas.HANDLE_COLOR,
		"its other corners are plain handles")
	_assert_eq(Canvas.handle_color("tr", mirrored, ""), Canvas.ANCHOR_COLOR,
		"a mirrored frame anchors at the top-RIGHT")
	_assert_eq(Canvas.handle_color("tl", mirrored, ""), Canvas.HANDLE_COLOR,
		"and its top-left is just a handle")
	# The corner actually being dragged still wins — it is transient feedback, and
	# losing it would make the anchor colour ambiguous mid-gesture.
	_assert_eq(Canvas.handle_color("tl", mirrored, "tl"), Canvas.DRAGGING_COLOR,
		"the grabbed corner outranks both")
	_assert_eq(Canvas.handle_color("tr", mirrored, "tr"), Canvas.DRAGGING_COLOR,
		"even when it IS the anchor")


func _test_texel_class_partitions_by_colour_not_by_palette_word() -> void:
	# ADR-0098 dec. 3. The viewport classifies a texel exactly as the particle shaders
	# route it, and both passes discard on COLOUR (`r,g,b < 0.01`, unconditionally:
	# effect_particle_opaque.gdshader:22, effect_particle_stp.gdshaderinc:147) before
	# they ever look at alpha. So 0x8000 — "opaque black" in the format doc, a name
	# that describes the PSX convention rather than what this engine draws — lands in
	# transparent, not in the visible art. Getting that wrong would put 158,778 corpus
	# texels in with the art, and read E001/E509/E510 as 88.1% art the game never draws.
	_assert_eq(Canvas.texel_class(Color8(0, 0, 0, 255)), "transparent",
		"0x0000 as the extractor carries it (opaque black) is the transparent class")
	_assert_eq(Canvas.texel_class(Color8(0, 0, 0, 128)), "transparent",
		"0x8000 (black, STP set) is discarded by both passes, so it is transparent too")
	_assert_eq(Canvas.texel_class(Color8(2, 0, 0, 255)), "transparent",
		"the boundary is the shaders' < 0.01, not exact zero")
	_assert_eq(Canvas.texel_class(Color8(200, 30, 40, 128)), "stp",
		"a real colour with STP set is the blend-pass class")
	_assert_eq(Canvas.texel_class(Color8(200, 30, 40, 255)), "opaque",
		"a real colour with STP clear is the opaque class")
	_assert_eq(Canvas.texel_class(Color8(0, 0, 8, 255)), "opaque",
		"one channel above the threshold is enough to be a colour")


func _test_texel_class_counts_reproduce_the_measured_e019_sheet() -> void:
	# The E019 column of ADR-0098's corpus table, which was measured OUTSIDE this
	# codebase (a direct TGA decode): 15,547 texels of 0x0000 + 2,776 of 0x8000 =
	# 18,323 transparent, 14,445 STP, 0 opaque, over a 128x256 sheet.
	var tex: Texture2D = load("res://assets/effects/E019/texture.tga")
	if tex == null:
		print("[SKIP] E019 texture.tga not present in this worktree")
		return
	var img: Image = tex.get_image()
	_assert_eq(Vector2i(img.get_width(), img.get_height()), Vector2i(128, 256),
		"E019's sheet is 128x256")
	_assert_eq(Canvas.class_counts(img),
		{"transparent": 18323, "stp": 14445, "opaque": 0},
		"the three-way partition reproduces the independently measured E019 counts")


func _test_display_image_erases_the_transparent_class_and_unwashes_stp() -> void:
	# What the canvas actually hands `draw_texture_rect`. Two fixes in one image:
	# transparent texels go fully clear so the checkerboard shows through (dec. 4 —
	# they were painting as solid black over 73.20% of the corpus), and STP texels go
	# to alpha 255 so they stop drawing at half opacity (defect 3 — alpha is a
	# blend-mode flag, ADR-0096, not an opacity, so rendering it as one is a lie).
	# Colour is never altered: tinting a class would be a different lie.
	var src := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	src.set_pixel(0, 0, Color8(0, 0, 0, 255))       # 0x0000
	src.set_pixel(1, 0, Color8(0, 0, 0, 128))       # 0x8000
	src.set_pixel(0, 1, Color8(200, 30, 40, 128))   # STP art
	src.set_pixel(1, 1, Color8(200, 30, 40, 255))   # opaque art

	var out: Image = Canvas.display_image(src)

	_assert_eq(out.get_pixel(0, 0).a, 0.0, "0x0000 is erased, not painted black")
	_assert_eq(out.get_pixel(1, 0).a, 0.0, "0x8000 is erased too")
	_assert_eq(out.get_pixel(0, 1), Color8(200, 30, 40, 255),
		"an STP texel draws at full opacity in its true colour")
	_assert_eq(out.get_pixel(1, 1), Color8(200, 30, 40, 255),
		"an opaque texel is unchanged")
	_assert_eq(src.get_pixel(0, 0), Color8(0, 0, 0, 255),
		"the source image is not mutated")


func _test_checkerboard_can_never_be_mistaken_for_content() -> void:
	# dec. 4: the checkerboard is the only backdrop that cannot be read as art —
	# which matters precisely BECAUSE the never-drawn texels are black. A flat
	# backdrop of any colour would be ambiguous with a texel of that colour.
	var a: Color = Canvas.checker_color_at(0, 0)
	var b: Color = Canvas.checker_color_at(1, 0)
	_assert_true(a != b, "adjacent cells differ along x")
	_assert_eq(Canvas.checker_color_at(0, 1), b, "adjacent cells differ along y")
	_assert_eq(Canvas.checker_color_at(1, 1), a, "diagonal cells match — it is a checker")
	_assert_true(minf(minf(a.r, a.g), a.b) > 0.1 and minf(minf(b.r, b.g), b.b) > 0.1,
		"neither cell colour is black, so the backdrop can never read as a black texel")


func _test_coverage_is_the_union_of_the_uv_rects_not_their_sum() -> void:
	# ADR-0098 dec. 5. Frames overlap constantly (E019: 184 frames over a 128x256
	# sheet), so counting rect areas would report well over 100%. Coverage is the
	# UNION — "which texels does anything address", not "how much do the frames add up
	# to". Two 2x2 frames sharing one texel cover 7, not 8.
	var framesets := [{"frames": [
		{"uv": {"x": 0, "y": 0, "width": 2, "height": 2}},
		{"uv": {"x": 1, "y": 1, "width": 2, "height": 2}}]}]
	_assert_eq(Canvas.covered_texel_count(framesets, Vector2i(4, 4)), 7,
		"overlapping frames are counted once")
	_assert_eq(Canvas.covered_texel_count([], Vector2i(4, 4)), 0,
		"an effect with no framesets covers nothing")


func _test_coverage_clips_a_uv_rect_that_runs_off_the_sheet() -> void:
	# A uv rect is authored bytes, so nothing stops it addressing past the sheet edge.
	# The mask has to clip rather than run off the end of its own buffer.
	var framesets := [{"frames": [{"uv": {"x": 3, "y": 3, "width": 8, "height": 8}}]}]
	_assert_eq(Canvas.covered_texel_count(framesets, Vector2i(4, 4)), 1,
		"a rect overhanging the sheet contributes only the texels actually on it")
	var negative := [{"frames": [{"uv": {"x": -2, "y": -2, "width": 4, "height": 4}}]}]
	_assert_eq(Canvas.covered_texel_count(negative, Vector2i(4, 4)), 4,
		"and it clips at the top-left edge too")


func _test_coverage_reproduces_the_measured_e019_and_e317_sheets() -> void:
	# ADR-0098 dec. 5's two named sheets, measured outside this codebase (a direct
	# frames.json + TGA decode): E019 26,652 of 32,768 texels = 81.3%, E317 4,480 of
	# 16,384 = 27.3% — three-quarters of that sheet is never drawn by anything.
	for probe in [["E019", Vector2i(128, 256), 26652], ["E317", Vector2i(128, 128), 4480]]:
		var eff: String = probe[0]
		var framesets = _load_framesets(eff)
		if framesets == null:
			print("[SKIP] %s frames.json not present in this worktree" % eff)
			continue
		_assert_eq(Canvas.covered_texel_count(framesets, probe[1]), probe[2],
			"%s's frame coverage matches the independently measured count" % eff)


func _test_coverage_image_dims_only_what_no_frame_addresses() -> void:
	# The overlay is drawn OVER the sheet, so it must be clear where a frame reaches
	# and only translucent elsewhere — dead sheet has to stay readable (it is where an
	# author can paint freely), so this dims rather than blanks.
	var framesets := [{"frames": [{"uv": {"x": 0, "y": 0, "width": 2, "height": 2}}]}]
	var img: Image = Canvas.coverage_image(framesets, Vector2i(4, 4))
	_assert_eq(Vector2i(img.get_width(), img.get_height()), Vector2i(4, 4),
		"the overlay is sheet-sized, so it maps 1:1 onto the draw rect")
	_assert_eq(img.get_pixel(0, 0).a, 0.0, "a covered texel is not dimmed at all")
	_assert_eq(img.get_pixel(1, 1).a, 0.0, "the whole covered rect is clear")
	_assert_true(img.get_pixel(3, 3).a > 0.0, "an unaddressed texel is dimmed")
	_assert_true(img.get_pixel(3, 3).a < 0.75,
		"but only dimmed — dead sheet is where an author can paint, so it stays readable")


func _test_palette_word_round_trips_the_documented_bgr555_values() -> void:
	# TEXTURE_AND_PALETTE_FORMAT.md: bit 15 STP, 14-10 Blue, 9-5 Green, 4-0 Red, and it
	# names three words outright — 0x0000 transparent, 0x8000 black+STP, 0xFFFF white+STP.
	# The readout shows the word because a colour alone cannot answer "is this the
	# transparent one or the one the format doc calls opaque black".
	_assert_eq(Canvas.palette_word(Color8(0, 0, 0, 255)), 0x0000, "transparent black")
	_assert_eq(Canvas.palette_word(Color8(0, 0, 0, 128)), 0x8000, "black with STP set")
	_assert_eq(Canvas.palette_word(Color8(255, 255, 255, 128)), 0xFFFF, "white with STP set")
	# E019 palette entry 1, [198, 115, 90, stp=1]: r5=24, g5=14, b5=11.
	_assert_eq(Canvas.palette_word(Color8(198, 115, 90, 128)), 0xADD8,
		"a real palette entry packs to its BGR555 word")
	_assert_eq(Canvas.format_palette_word(0x8000), "0x8000", "shown as a 4-digit hex word")


func _test_swatch_matching_compares_in_five_bit_space() -> void:
	# ADR-0098's sharpest build trap. `parse_effect.extract_palette` bit-replicates
	# ((v<<3)|(v>>2)) while the TGA path truncates (v*8), so the SAME palette word is 198
	# in texture_palette.json and 192 in texture.tga. Measured on E019: 6 of 66 colours
	# match exactly, 66 of 66 after >>3. Naive equality would highlight nothing at all.
	var palette := [[0, 0, 0, 0], [198, 115, 90, 1], [192, 112, 88, 1], [8, 8, 8, 1]]
	var hits: Array = Canvas.matching_palette_indices(palette, Color8(192, 112, 88, 128))
	_assert_eq(hits, [1, 2],
		"the bit-replicated entry and the truncated one are the same colour at 5 bits")


func _test_swatch_matching_highlights_every_slot_that_matches() -> void:
	# For most sheets several slots hold the same colour (E019: 67 distinct colours over
	# 256 slots), and a colour does not identify a CLUT index — ADR-0199. Highlighting a
	# single index would be a fabrication, so every match lights up.
	var palette := [[8, 8, 8, 1], [200, 0, 0, 1], [8, 8, 8, 1], [8, 8, 8, 0]]
	_assert_eq(Canvas.matching_palette_indices(palette, Color8(8, 8, 8, 255)), [0, 2, 3],
		"every slot holding that colour is named, whatever its STP bit")
	_assert_eq(Canvas.matching_palette_indices(palette, Color8(64, 64, 64, 255)), [],
		"a colour on no slot names none")


func _test_the_readout_names_a_clut_line_the_export_did_not_decode() -> void:
	# ADR-0098 dec. 6: where the frame reads a CLUT line the flat export did not decode,
	# say which line each side used — not a generic "colours approximate", and never
	# silently. `uses_palette_2` is the per-frame CLUT-line select (flags_byte0 & 0x10).
	_assert_eq(Canvas.clut_caveat({"is_8bpp": true, "uses_palette_2": false, "palette_id": 0}), "",
		"an 8bpp frame reading line 1 is exactly what the export decoded — no caveat")
	var wrong_line: String = Canvas.clut_caveat(
		{"is_8bpp": true, "uses_palette_2": true, "palette_id": 0})
	_assert_true(wrong_line.contains("line 2") and wrong_line.contains("line 1"),
		"a frame reading line 2 names both its line and the exported one (got: %s)" % wrong_line)
	var four_bpp: String = Canvas.clut_caveat(
		{"is_8bpp": false, "uses_palette_2": false, "palette_id": 5})
	_assert_true(four_bpp.contains("4bpp") and four_bpp.contains("5"),
		"a 4bpp frame names its sub-palette (got: %s)" % four_bpp)
	_assert_true(four_bpp.contains("#297"),
		"and points at the ticket that would actually fix it")


# --- fixtures -------------------------------------------------------------

## The real framesets of a ROM-derived effect, or null when the (gitignored) assets
## are absent from this worktree.
func _load_framesets(eff: String):
	var path := "res://assets/effects/%s/frames.json" % eff
	if not FileAccess.file_exists(path):
		return null
	var parsed = JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())
	return parsed if parsed is Array else null


## THE FLAT LIST IS SPLIT (2026-08-21). Reported as *"this stuff is kind of esoteric. the
## names aren't good. I think they should be organized better."* — sixteen editable rows in
## one run, ending in eight called `Vertex TL X` … `Vertex BR Y`.
##
## The split is asserted by `fold_id` and not by title because that is what the rest of the
## studio addresses these sections by: `SequenceFocusBlock` drops the TPAGE section and
## swaps the region one, and it used to do that by matching the title `"Frame"` — which
## this split would have turned into a silent graft of nothing.
func _test_the_frame_rows_are_grouped_into_folded_sections() -> void:
	var data := _fake_data()
	var sections: Array = Registry.sections(Target.frame(0, 0), data, {})

	var by_fold: Dictionary = {}
	for sec in sections:
		var fid := str(sec.get("fold_id", ""))
		_assert_true(fid != "", "every frame section carries a fold_id (title '%s' does not)"
			% str(sec.get("title", "")))
		_assert_true(not by_fold.has(fid), "…and the ids are distinct ('%s' repeats)" % fid)
		by_fold[fid] = sec

	for fid in [Projector.FOLD_APPEARANCE, Projector.FOLD_REGION, Projector.FOLD_QUAD,
			Projector.FOLD_CORNERS, Projector.FOLD_TPAGE]:
		_assert_true(by_fold.has(fid), "the frame target emits the '%s' section" % fid)
	_assert_eq(sections.size(), 5, "and emits exactly those five")

	var names := func(fid: String) -> Array:
		var out: Array = []
		for f in by_fold.get(fid, {}).get("fields", []):
			out.append(str(f.get("name", "")))
		return out

	# The ADR-0099 boundary is the one the split is FOR: the sheet region is shared by up
	# to 107 frames and a region edit reaches all of them, while every number under the
	# quad belongs to this frame alone. One flat list said they were the same kind of thing.
	for n in ["UV X", "UV Y", "UV Width", "UV Height"]:
		_assert_true(names.call(Projector.FOLD_REGION).has(n),
			"'%s' sits under Sheet region (SHARED)" % n)
	for n in ["Top-left X", "Top-left Y", "Top-right X", "Top-right Y",
			"Bottom-left X", "Bottom-left Y", "Bottom-right X", "Bottom-right Y"]:
		_assert_true(names.call(Projector.FOLD_CORNERS).has(n),
			"'%s' sits under Raw corners — what is actually stored" % n)
	for n in ["Base", "Width", "Height", "Rotation", "Shear", "Position X", "Position Y"]:
		_assert_true(names.call(Projector.FOLD_QUAD).has(n),
			"'%s' sits under Drawn quad — the transform over the region (PER-FRAME)" % n)
	for n in ["Palette ID", "Blend mode", "Semi-trans on", "8bpp"]:
		_assert_true(names.call(Projector.FOLD_APPEARANCE).has(n),
			"'%s' sits under Appearance" % n)

	# No row named `Vertex …` survives anywhere — the rename is the report's second
	# complaint and a half-applied rename would leave both vocabularies on one screen.
	for sec in sections:
		for f in sec.get("fields", []):
			_assert_true(not str(f.get("name", "")).begins_with("Vertex"),
				"no row still uses the old `Vertex` vocabulary (found '%s')" % str(f.get("name", "")))

	for fid in [Projector.FOLD_TPAGE, Projector.FOLD_CORNERS]:
		_assert_true(bool(by_fold[fid].get("collapsed", false)),
			"'%s' opens SHUT — the transform rows above say the same thing in fewer terms" % fid)
	for fid in [Projector.FOLD_APPEARANCE, Projector.FOLD_REGION, Projector.FOLD_QUAD]:
		_assert_true(not bool(by_fold[fid].get("collapsed", false)),
			"'%s' opens OPEN — it is why the screen was opened" % fid)


## THE TRANSFORM IS DERIVED, never cached: `FrameQuadTransform` reads the same four corner
## pairs the Raw corners section edits. Asserted by editing a corner through the channel and
## reprojecting — a transform row that cached would state a size the sprite is not drawn at,
## with nothing on the screen to contradict it.
##
## The row-level maths (round-trip fidelity, precision, the residual) is guarded against the
## real corpus in EffectStudioFrameQuadTransformTest. What is guarded HERE is only that the
## projector reads it live and spells it the way the author asked for.
func _test_the_quad_facts_are_derived_from_the_rows_beneath_them() -> void:
	var data := _fake_data()
	var quad_rows := func() -> Dictionary:
		var out: Dictionary = {}
		for sec in Registry.sections(Target.frame(0, 0), data, {}):
			if str(sec.get("fold_id", "")) != Projector.FOLD_QUAD:
				continue
			for f in sec.get("fields", []):
				out[str(f.get("name", ""))] = f
		return out

	var before: Dictionary = quad_rows.call()
	# The fixture's quad is TL(0,0) TR(32,0) BL(0,16) BR(32,16) against a 32x32 sheet
	# region: 32 wide by 16 tall, upright, centred at (16,8).
	_assert_eq(str(before.get("Base", {}).get("value", "")), "32×32 from the sheet",
		"the base is the sheet region, centred on the sprite origin")
	_assert_eq(float(before.get("Width", {}).get("value", 0.0)), 32.0,
		"Width is the drawn width in PSX units")
	_assert_eq(float(before.get("Height", {}).get("value", 0.0)), 16.0, "Height likewise")
	_assert_eq(float(before.get("Rotation", {}).get("value", -1.0)), 0.0, "an upright quad is at 0 degrees")
	_assert_eq(float(before.get("Shear", {}).get("value", -1.0)), 0.0, "…with no shear")
	_assert_eq(before.get("Position X", {}).get("value", null), 16.0, "its centre is 16 right of the origin")
	_assert_eq(before.get("Position Y", {}).get("value", null), 8.0, "…and 8 below it")
	_assert_true(not before.has("Residual"),
		"a parallelogram shows NO residual row — the row's absence is the signal")
	_assert_eq(str(before.get("Base", {}).get("shape", "")), "const",
		"the base is read-only here — the region is SHARED and is edited under a scope control")
	for n in ["Width", "Height", "Rotation", "Shear", "Position X", "Position Y"]:
		_assert_eq(str(before.get(n, {}).get("shape", "")), "edit", "'%s' is editable" % n)
		_assert_eq(str(before.get(n, {}).get("editor", "")), "float",
			"'%s' is a FLOAT cell — a ratio, an angle and a lean are not bytes" % n)
		_assert_eq(str(before.get(n, {}).get("field_ref", {}).get("channel", "")), "frameset_quad",
			"'%s' addresses the derived-term channel, not a stored field" % n)

	# Pull the right-hand corners out; the transform must follow.
	Channel.apply_raw(data, {"channel": "frameset", "frameset_index": 0, "frame_index": 0,
		"field": "vertex_br_x"}, 64)
	Channel.apply_raw(data, {"channel": "frameset", "frameset_index": 0, "frame_index": 0,
		"field": "vertex_tr_x"}, 64)
	var after: Dictionary = quad_rows.call()
	_assert_eq(float(after.get("Width", {}).get("value", 0.0)), 64.0,
		"widening the right-hand corners restates the drawn width")
	_assert_eq(after.get("Position X", {}).get("value", null), 32.0,
		"…and moves the centre with it")
	_assert_eq(float(after.get("Rotation", {}).get("value", -1.0)), 0.0, "…leaving the angle alone")


## `frames.json` is parsed by Godot's JSON, which types every number as a float — so the
## frameset's bit field rendered as "672.0", which reads as a measurement rather than a
## mask. Reported in the same screenshot as the vertex rows.
func _test_the_header_flags_row_is_not_a_float() -> void:
	var data := _fake_data()
	data.framesets[0]["header_flags"] = 672.0
	var value := ""
	for sec in Registry.sections(Target.frameset(0), data, {}):
		for f in sec.get("fields", []):
			if str(f.get("name", "")) == "Header flags":
				value = str(f.get("value", ""))
	_assert_eq(value, "672", "the header flags bit field prints as an integer, not '672.0'")


func _fake_data() -> RefCounted:
	var data := _FakeData.new()
	data.framesets = [
		{
			"index": 0,
			"header_flags": 0,
			"frames": [
				{
					"index": 0,
					"palette_id": 3,
					"semi_trans_mode": 0,
					"semi_trans_on": false,
					"is_8bpp": true,
					"blend_mode": "BLEND_50",
					"uv": {"x": 8, "y": 0, "width": 32, "height": 32},
					"vertices": {
						"top_left": [0, 0],
						"top_right": [32, 0],
						"bottom_left": [0, 16],
						"bottom_right": [32, 16],
					},
					"texture_page": {"x_base": 0, "y_base": 0, "blend": 0, "color_depth": 0},
				},
			],
		},
	]
	data.frameset_group_offsets = [0]
	return data


class _FakeData extends RefCounted:
	var framesets: Array = []
	var frameset_group_offsets: Array = [0]


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
