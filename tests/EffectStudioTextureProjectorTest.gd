extends Node
## TDD guard for the TEXTURE inspection target (#280, ADR-0199 dec. 6).
##
## The texture sheet becomes its own inspection kind — exactly one per effect, so
## the ref is degenerate like `effect_settings`. It carries the sheet's metadata
## and the two round-trip actions (Export / Import).
##
## A sheet outside v1 scope shows its REFUSAL REASON and offers NO actions —
## including no Export, because for a 4bpp sheet the exported flat RGBA is
## precisely the untruthful artifact (58 of 60 render through 3-7 sub-palettes).
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectStudioTextureProjectorTest.tscn

const EffectData = ExMateriaEffects.EffectData

const Registry = preload("res://src/effects/studio/InspectorProjectorRegistry.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const FramesetProjector = preload("res://src/effects/studio/FramesetProjector.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_the_registry_knows_the_texture_kind()
	_test_header_states_the_sheets_identity()
	_test_header_rows_match_what_the_inspector_actually_renders()
	_test_sections_carry_the_sheet_metadata()
	_test_an_authorable_sheet_offers_export_and_import()
	_test_a_refused_sheet_shows_the_reason_and_offers_no_actions()
	_test_it_surfaces_dual_palette_use_from_the_frames()
	_test_it_surfaces_the_real_vram_upload_rect_and_invents_no_y()
	_test_the_texture_target_is_reachable_from_a_frameset_and_a_frame()

	const EXPECTED_ASSERTIONS := 30
	if _passed + _failed != EXPECTED_ASSERTIONS:
		print("[FAIL] EffectStudioTextureProjectorTest — ran %d assertions, expected %d (a test aborted)"
			% [_passed + _failed, EXPECTED_ASSERTIONS])
		get_tree().quit(1)
		return

	print("\n=== EffectStudioTextureProjectorTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioTextureProjectorTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioTextureProjectorTest")
		get_tree().quit(0)


func _test_the_registry_knows_the_texture_kind() -> void:
	_assert_true(Registry.has_kind("texture"), "registry recognizes the texture kind")
	_assert_true(Registry.is_built("texture"), "and it is built, not a declared seam")
	_assert_true(Registry.projector_for("texture") != null, "a projector is returned")
	_assert_eq(Target.title(Target.texture()), "Texture", "inspector panel title")


func _test_header_states_the_sheets_identity() -> void:
	var rows: Array = Registry.header(Target.texture(), _data(true, [0]), {})
	var text := _flatten(rows)
	_assert_true(text.contains("128"), "header states the sheet's width")
	_assert_true(text.contains("256"), "header states the sheet's height")
	_assert_true(text.contains("8bpp"), "header states the render depth")


func _test_header_rows_match_what_the_inspector_actually_renders() -> void:
	# EffectKeyframeInspector._render_header_rows indexes row["label"] HARD (not
	# .get()) and then row["value"] unless the row carries a "link". A row of any
	# other shape crashes the inspector at click time — which a projector test
	# that only stringifies the rows will happily miss. Encode the contract.
	var rows: Array = Registry.header(Target.texture(), _data(true, [0]), {})
	var conformant := true
	for row in rows:
		if not (row is Dictionary) or not row.has("label"):
			conformant = false
		elif not (row.has("value") or row.has("link")):
			conformant = false
	_assert_true(rows.size() > 0, "the texture header emits rows")
	_assert_true(conformant, "every header row is {label, value} or {label, link}")

	# And the same contract on a refused sheet, which takes a different path.
	var refused: Array = Registry.header(Target.texture(), _data(false, [0, 1]), {})
	var refused_ok := true
	for row in refused:
		if not (row is Dictionary) or not row.has("label") \
				or not (row.has("value") or row.has("link")):
			refused_ok = false
	_assert_true(refused_ok, "…including a refused sheet's header")


func _test_sections_carry_the_sheet_metadata() -> void:
	var sections: Array = Registry.sections(Target.texture(), _data(true, [0]), {})
	_assert_true(sections.size() > 0, "the texture target emits sections")
	var names := _field_names(sections)
	_assert_true(names.has("Dimensions"), "a Dimensions row")
	_assert_true(names.has("Colour depth"), "a Colour depth row")
	_assert_true(names.has("Sub-palette"), "a Sub-palette row")


func _test_an_authorable_sheet_offers_export_and_import() -> void:
	var sections: Array = Registry.sections(Target.texture(), _data(true, [0]), {})
	var kinds := _action_kinds(sections)
	_assert_true(kinds.has("texture_export"), "an Export action")
	_assert_true(kinds.has("texture_import"), "an Import action")


func _test_a_refused_sheet_shows_the_reason_and_offers_no_actions() -> void:
	var sections: Array = Registry.sections(Target.texture(), _data(false, [0, 1, 2]), {})
	var text := _flatten(sections)
	_assert_true(text.contains("4bpp"), "the refusal reason is shown")
	_assert_eq(_action_kinds(sections).size(), 0,
		"no actions — the flat export would itself be untruthful")

	var authorable: Array = Registry.sections(Target.texture(), _data(true, [0]), {})
	_assert_true(_action_kinds(authorable).size() > 0,
		"…while an in-scope sheet still offers its actions")


func _test_it_surfaces_dual_palette_use_from_the_frames() -> void:
	# "dual-palette-in-use" was named in #262 but no Godot-side asset carried it
	# until parse_frame started emitting `uses_palette_2` (flags_byte0 & 0x10,
	# the CLUT-line select verified at 0x801a5664).
	var single: Array = Registry.sections(Target.texture(), _data(true, [0]), {})
	var names := _field_names(single)
	_assert_true(names.has("Dual palette"), "a Dual palette row exists")
	_assert_true(JSON.stringify(single).contains("palette 1"),
		"a sheet whose frames all clear bit 4 reads as palette 1 only")

	var dual_data := _data(true, [0])
	dual_data.framesets[0]["frames"][0]["uses_palette_2"] = true
	var dual: Array = Registry.sections(Target.texture(), dual_data, {})
	_assert_true(JSON.stringify(dual).contains("palette 2"),
		"a frame with bit 4 set reports palette 2 in use")


func _test_it_surfaces_the_real_vram_upload_rect_and_invents_no_y() -> void:
	# The 24-bit value at texture +0x400 is the PIXEL DATA SIZE, not a Y
	# coordinate — measured equal to the plane's byte count in all 401 effects.
	# Upload X is a fixed 0x180 and the Y is not encoded anywhere in the file,
	# so the inspector must not display one.
	var data := _data(true, [0])
	data.texture_meta = {
		"pixel_data_size": 32768, "stride_flag": 0, "row_bytes": 128,
		"height": 256, "vram_x": 384, "vram_y": null,
		"palette_1_nonzero": true, "palette_2_nonzero": false,
	}
	var sections: Array = Registry.sections(Target.texture(), data, {})
	var names := _field_names(sections)
	var text := JSON.stringify(sections)

	_assert_true(names.has("VRAM upload"), "a VRAM upload row exists")
	_assert_true(text.contains("384"), "it states the fixed upload X")
	_assert_true(text.contains("32,768") or text.contains("32768"),
		"…and the pixel-data size the header really encodes")
	_assert_true(not text.contains("VRAM Y"),
		"it must NOT claim a VRAM Y — the file does not encode one")


func _test_the_texture_target_is_reachable_from_a_frameset_and_a_frame() -> void:
	# Registering an inspection kind does NOT make it reachable — something must
	# MINT the target. The frameset canvas drives the frameset/frame inspector,
	# so the sheet those frames UV into is one link away from both.
	var data := _data(true, [0])

	var fs_sections: Array = FramesetProjector.sections(Target.frameset(0), data, {})
	_assert_true(_links_to_texture(fs_sections), "a frameset links to its sheet")

	var fr_sections: Array = FramesetProjector.sections(Target.frame(0, 0), data, {})
	_assert_true(_links_to_texture(fr_sections), "a frame links to its sheet too")

	# And the link actually lands on a rendered surface, not a dead kind.
	var landed: Array = Registry.sections(Target.texture(), data, {})
	_assert_true(landed.size() > 0, "the linked target renders")
	_assert_true(_action_kinds(landed).size() > 0, "…with its actions")


func _links_to_texture(sections: Array) -> bool:
	for sec in sections:
		for f in sec.get("fields", []):
			if String(f.get("shape", "")) == "link" \
					and String(f.get("target", {}).get("kind", "")) == "texture":
				return true
	return false


# --- fixtures -----------------------------------------------------------------

func _data(is_8bpp: bool, palette_ids: Array) -> EffectData:
	var data := EffectData.new()
	var frames := []
	for pid in palette_ids:
		frames.append({"is_8bpp": is_8bpp, "palette_id": int(pid),
			"texture_page": {"x_base": 6, "y_base": 0}})
	data.framesets = [{"frames": frames}]
	var img := Image.create(128, 256, false, Image.FORMAT_RGBA8)
	data.texture = ImageTexture.create_from_image(img)
	return data


func _flatten(rows) -> String:
	return JSON.stringify(rows)


func _field_names(sections: Array) -> Array:
	var names := []
	for sec in sections:
		for f in sec.get("fields", []):
			names.append(String(f.get("name", "")))
	return names


func _action_kinds(sections: Array) -> Array:
	var kinds := []
	for sec in sections:
		for f in sec.get("fields", []):
			if String(f.get("shape", "")) == "action":
				kinds.append(String(f.get("action", {}).get("kind", "")))
	return kinds


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
