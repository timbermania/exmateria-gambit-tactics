extends Node
## F0 guard (#263): the editability manifest CANNOT LIE about what is editable.
##
## The manifest (src/effects/studio/editability_manifest.json) is the single source of
## truth consumed by BOTH the offline coverage tracker (research/scripts/effect_
## editability_tracker.py) and the studio itself. This test pins it to reality so the
## "editable %" the tracker reports is honest:
##
##   (1) Well-formed: legend, editable_channels, and a subsystems map all present; every
##       subsystem's `default` is one of {editable,display,deferred,na}; any `fields`
##       override likewise; every subsystem with default "editable" declares a
##       `projector_channel` and that channel is listed in `editable_channels`.
##   (2) Manifest → projector: every channel the manifest calls editable is ACTUALLY
##       reachable from a real projector — as a shape:"edit" row, or (#280) as a
##       shape:"action" row that DECLARES the channel it writes, for a subsystem
##       authored by wholesale replacement rather than per-field cells. If a channel is
##       marked editable with no projector offering it, this FAILS (add the projector's
##       probe to _swept_edit_channels below when a subsystem ticket wires a channel).
##   (3) Projector → manifest (no drift): every channel a projector offers for writing
##       is marked editable in the manifest — you cannot ship an editor without registering
##       it, so the tracker can't silently under-count closed coverage.
##
## Today the ONE editable channel is "screen" (the #255 pilot: ScreenTweenProjector emits
## editable Blend/Gradient/Kind cells). As each subsystem build lands (Palette, Camera, ...),
## it flips its subsystem to editable, adds a projector_channel, and appends a probe here.
##
## Run: <GODOT> --path . --quit-after 2 res://tests/EffectEditabilityManifestTest.tscn

const EffectData = ExMateriaEffects.EffectData
const EffectEmitter = ExMateriaEffects.EffectEmitter
const ScreenData = ExMateriaEffects.ScreenData

const Projector = preload("res://src/effects/studio/ScreenTweenProjector.gd")
const CameraProjector = preload("res://src/effects/studio/CameraTweenProjector.gd")
const PaletteProjector = preload("res://src/effects/studio/PaletteTweenProjector.gd")
const SoundProjector = preload("res://src/effects/studio/SoundTriggerProjector.gd")
const TextureProjector = preload("res://src/effects/studio/TextureProjector.gd")
const MANIFEST_PATH := "res://src/effects/studio/editability_manifest.json"
const VALID_STATUS := ["editable", "display", "deferred", "na"]

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	var manifest := _load_manifest()
	if manifest.is_empty():
		print("[FAIL] EffectEditabilityManifestTest: manifest missing/unparseable at %s" % MANIFEST_PATH)
		get_tree().quit(1)
		return

	_test_manifest_wellformed(manifest)
	_test_editable_subsystems_declare_channels(manifest)
	_test_manifest_editable_channels_have_projectors(manifest)
	_test_no_projector_drift(manifest)
	_test_effect_flags_carving_matches_adr_0092(manifest)
	_test_time_scale_carving_matches_adr_0093(manifest)
	_test_frames_carving_matches_278(manifest)
	_test_animation_carving_matches_275(manifest)
	_test_texture_carving_matches_280(manifest)

	print("\n=== EffectEditabilityManifestTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectEditabilityManifestTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectEditabilityManifestTest")
		get_tree().quit(0)


# --- Seam 1: the manifest is structurally sound ----------------------------
func _test_manifest_wellformed(m: Dictionary) -> void:
	_check(m.has("legend"), "manifest has a legend")
	_check(m.has("editable_channels") and m["editable_channels"] is Array,
		"manifest has an editable_channels array")
	_check(m.has("subsystems") and m["subsystems"] is Dictionary and not m["subsystems"].is_empty(),
		"manifest has a non-empty subsystems map")

	for sid in m.get("subsystems", {}):
		var sub: Dictionary = m["subsystems"][sid]
		var default: String = str(sub.get("default", ""))
		_check(default in VALID_STATUS,
			"subsystem '%s' default '%s' is a valid status" % [sid, default])
		for fname in sub.get("fields", {}):
			var fstat: String = str(sub["fields"][fname])
			_check(fstat in VALID_STATUS,
				"subsystem '%s' field '%s' status '%s' is valid" % [sid, fname, fstat])


# --- Seam 2: editable subsystems declare a channel registered globally ------
func _test_editable_subsystems_declare_channels(m: Dictionary) -> void:
	var declared: Dictionary = {}
	for ch in m.get("editable_channels", []):
		declared[str(ch)] = true

	for sid in m.get("subsystems", {}):
		var sub: Dictionary = m["subsystems"][sid]
		if str(sub.get("default", "")) != "editable":
			continue
		var ch := str(sub.get("projector_channel", ""))
		_check(not ch.is_empty(),
			"editable subsystem '%s' declares a projector_channel" % sid)
		_check(declared.has(ch),
			"editable subsystem '%s' channel '%s' is in editable_channels" % [sid, ch])


# --- Seam 3: every editable channel is really produced by a projector -------
func _test_manifest_editable_channels_have_projectors(m: Dictionary) -> void:
	var swept := _swept_edit_channels()
	for ch in m.get("editable_channels", []):
		_check(swept.has(str(ch)),
			"channel '%s' marked editable is emitted as a shape:edit projector row "
			% str(ch)
			+ "(if you added a channel, append its projector probe to _swept_edit_channels)")


## Seam 9 (#280, ADR-0199): the texture subsystem closes its PIXEL PLANE and says so about
## the rest. Holding the CLUT fixed is a DECISION, not an unfinished gap, so the two
## palettes and the VRAM header are `deferred` — the subsystem's `display` gap must be 0
## while 1,028 bytes stay honestly out of scope.
func _test_texture_carving_matches_280(m: Dictionary) -> void:
	var sub: Dictionary = m.get("subsystems", {}).get("texture", {})
	_check(not sub.is_empty(), "texture subsystem is present")
	_check(str(sub.get("default", "")) == "editable", "texture defaults to editable (#280 landed)")
	_check(str(sub.get("projector_channel", "")) == "texture",
		"texture declares the texture write channel")
	var fields: Dictionary = sub.get("fields", {})
	_check(str(fields.get("pixel_plane", "")) == "editable", "the indexed pixel plane is editable")
	_check(str(fields.get("palette_1", "")) == "deferred",
		"palette 1 is deferred — the CLUT is fixed by decision, not by omission")
	_check(str(fields.get("palette_2", "")) == "deferred", "palette 2 likewise")
	_check(str(fields.get("vram_header", "")) == "deferred",
		"the VRAM header only moves on the deferred v2 resize")


# --- Seam 4: no projector emits an edit for an unregistered channel ----------
func _test_no_projector_drift(m: Dictionary) -> void:
	var declared: Dictionary = {}
	for ch in m.get("editable_channels", []):
		declared[str(ch)] = true
	for ch in _swept_edit_channels():
		_check(declared.has(ch),
			"projector emits editable rows for channel '%s' — mark it editable in the manifest" % ch)


## Seam 5 (#272, ADR-0092): the effect_flags subsystem carving is the honest partial-close —
## the flags_byte is editable on the effect_flags channel, the dead 0x04 is na (NOT an editable
## default_frame_delay), and the sound-channel block stays a display gap. Pins the ADR decision
## the tracker reads.
func _test_effect_flags_carving_matches_adr_0092(m: Dictionary) -> void:
	var sub: Dictionary = m.get("subsystems", {}).get("effect_flags", {})
	_check(not sub.is_empty(), "effect_flags subsystem is present")
	_check(str(sub.get("projector_channel", "")) == "effect_flags",
		"effect_flags declares the effect_flags projector_channel")
	var fields: Dictionary = sub.get("fields", {})
	_check(str(fields.get("flags_byte", "")) == "editable", "flags_byte is editable")
	_check(str(fields.get("spawn_delay_override", "")) == "na",
		"the dead 0x04 spawn_delay_override is na, not an editability gap")
	_check(str(fields.get("sound_channels", "")) == "display",
		"the sound-channel block stays a display gap (partial close, not 0)")


## Seam 6 (#270, ADR-0093): the time_scale subsystem CLOSES to editable — both pacing curves
## author (via the on-timeline band + pop-up painter, not a projector row) and save byte-exact.
## Its edit surface is the timeline, so its "projector_channel" (the write channel) is time_scale
## and both curve fields are editable — the subsystem gap shrinks to 0.
func _test_time_scale_carving_matches_adr_0093(m: Dictionary) -> void:
	var sub: Dictionary = m.get("subsystems", {}).get("time_scale", {})
	_check(not sub.is_empty(), "time_scale subsystem is present")
	_check(str(sub.get("default", "")) == "editable", "time_scale defaults to editable (#270 landed)")
	_check(str(sub.get("projector_channel", "")) == "time_scale",
		"time_scale declares the time_scale write channel")
	var fields: Dictionary = sub.get("fields", {})
	_check(str(fields.get("outer_phases", "")) == "editable", "the Phase-1 pacing curve is editable")
	_check(str(fields.get("for_each", "")) == "editable", "the For-each pacing curve is editable")


## Seam 7 (#278, 2026-08-17): the frames subsystem carving is an honest PARTIAL close —
## per-frame UV/vertices/palette_id/blend mode ARE editable (the "frameset" channel); the
## group/offset table, each frameset's header_flags/sprite_count, and texture_page stay a
## display gap (v1 is in-place field edits only — no structural resize). No byte here is na:
## every non-editable byte is real data, just not yet authorable.
func _test_frames_carving_matches_278(m: Dictionary) -> void:
	var sub: Dictionary = m.get("subsystems", {}).get("frames", {})
	_check(not sub.is_empty(), "frames subsystem is present")
	_check(str(sub.get("default", "")) == "editable", "frames defaults to editable (#278 landed)")
	_check(str(sub.get("projector_channel", "")) == "frameset",
		"frames declares the frameset write channel")
	var fields: Dictionary = sub.get("fields", {})
	_check(str(fields.get("flags_byte0", "")) == "editable", "byte0 (palette_id/mode/depth) is editable")
	_check(str(fields.get("flags_byte1", "")) == "editable", "byte1 (semi_trans_on, RMW-preserved) is editable")
	_check(str(fields.get("uv_width", "")) == "editable", "UV rect fields are editable")
	_check(str(fields.get("top_left_x", "")) == "editable", "vertex components are editable")
	_check(str(fields.get("texture_page", "")) == "display", "texture_page stays a display gap, not editable")
	_check(str(fields.get("sprite_count", "")) == "display",
		"sprite_count (frame-array length) stays a display gap — a resize is structural, out of v1")
	_check(str(fields.get("group_table", "")) == "display", "the group/offset table stays a display gap")


## Seam 7 (#275, 2026-08-18): the animation subsystem carving is an honest PARTIAL close —
## every opcode PARAMETER is editable (the "sequence" channel); the u32 sequence count, the
## per-sequence offset table, and each non-FRAME opcode's TYPE byte stay a display gap
## (v1 is in-place parameter edits only — opcodes are variable-size, so a type change or an
## insert/delete/reorder is a structural rewrite). A FRAME's opcode byte IS its frameset
## index, so it is the one type byte that IS editable. Trailing alignment padding is na.
func _test_animation_carving_matches_275(m: Dictionary) -> void:
	var sub: Dictionary = m.get("subsystems", {}).get("animation", {})
	_check(not sub.is_empty(), "animation subsystem is present")
	_check(str(sub.get("default", "")) == "editable", "animation defaults to editable (#275 landed)")
	_check(str(sub.get("projector_channel", "")) == "sequence",
		"animation declares the sequence write channel")
	var fields: Dictionary = sub.get("fields", {})
	_check(str(fields.get("frameset", "")) == "editable",
		"a FRAME's frameset index is editable even though it IS the opcode byte")
	_check(str(fields.get("duration", "")) == "editable", "a FRAME's duration is editable")
	_check(str(fields.get("depth_mode", "")) == "editable", "a FRAME's depth mode is editable")
	_check(str(fields.get("offset_x", "")) == "editable", "SET_OFFSET's x/y are editable")
	_check(str(fields.get("delta_y", "")) == "editable", "ADD_OFFSET's dx/dy are editable")
	_check(str(fields.get("opcode_type", "")) == "display",
		"a non-FRAME opcode's type byte stays a display gap — changing it is a structural resize")
	_check(str(fields.get("seq_count", "")) == "display", "the sequence count stays a display gap")
	_check(str(fields.get("offset_table", "")) == "display",
		"the per-sequence offset table stays a display gap")
	_check(str(fields.get("padding", "")) == "na", "trailing alignment padding is na")


## The set of channels that real projectors emit as shape:"edit" rows. Each entry is a
## probe: instantiate a subsystem's projector against representative data and collect the
## channels of its editable rows. Today only the screen projector emits edits (both its
## kinds). A new subsystem ticket appends its probe here.
func _swept_edit_channels() -> Dictionary:
	var channels: Dictionary = {}
	# Screen probe: both kinds (BLEND emits Kind+Color; GRADIENT emits Kind+2 stops).
	for mode in [ScreenData.ScreenMode.BLEND, ScreenData.ScreenMode.GRADIENT]:
		var kf = ScreenData.Keyframe.new()
		kf.mode = mode
		var secs: Array = Projector.sections(kf, {"context": "for_each", "event_index": 0})
		_collect_edit_channels(secs, channels)
	# Palette probe (#266): the palette projector emits editable Tint (gradient_color)
	# + Blend mode (enum) rows on the "palette" channel. It reads its write-side address
	# (phase / channel_name / keyframe_index) from the span, so a representative span is
	# enough.
	var pspan := {
		"phase": "for_each",
		"keyframe_index": 0,
		"color": Color.RED,
		"fields": {
			"channel": "affected_units",
			"rgb": Vector3i(10, 20, 30),
			"blend_mode": 0,
			"duration_frames": 1,
		},
	}
	_collect_edit_channels(PaletteProjector.sections(pspan), channels)
	# Camera probe (#267): the camera projector emits editable int/enum/bitflags rows on
	# the "camera" channel for one (phase, sub-channel) span. Reads its write-side address
	# (phase / keyframe_index) + seed values from the span.
	var cspan := {
		"kind": "camera",
		"phase": "phase1",
		"keyframe_index": 0,
		"fields": {
			"camera_channel": "angle",
			"angle": Vector3i.ZERO, "position": Vector3i.ZERO, "zoom": Vector3i.ZERO,
			"end_frame": 0, "command_raw": 0, "channel_mask": 0, "param_index": 0, "flags": 0,
		},
	}
	_collect_edit_channels(CameraProjector.sections(cspan), channels)
	# Texture probe (#280): the texture projector wires its channel through an
	# Import ACTION, not an edit row — the sheet is replaced wholesale. Needs an
	# in-scope (8bpp, single sub-palette) effect or the projector correctly
	# refuses and offers no actions at all.
	var tex_data := EffectData.new()
	tex_data.framesets = [{"frames": [{"is_8bpp": true, "palette_id": 0}]}]
	var tex_img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	tex_data.texture = ImageTexture.create_from_image(tex_img)
	_collect_edit_channels(
		TextureProjector.sections({"kind": "texture", "ref": {}}, tex_data, {}), channels)
	# Sound probe (#268): the sound projector emits editable int rows (Sound id u8,
	# Duration s16) on the "sound" channel for one trigger span. Reads its write-side
	# address (phase / channel_index / keyframe_index) from the span.
	var sspan := {
		"phase": "phase1",
		"channel_index": 0,
		"keyframe_index": 1,
		"fields": {
			"channel": 0,
			"sound_id": 2,
			"duration_frames": 5,
		},
	}
	_collect_edit_channels(SoundProjector.sections(sspan), channels)
	# Sound Def / FEDS probe (ADR-0085 amendment 2026-08-11): the pair projector emits
	# editable int/enum rows (opcode params, note velocity/key/duration, toggle
	# substitutions) on the "sound_def" channel. It reads a pre-projected pair view
	# from the score, so a tiny synthetic 1-pair bank suffices: Instrument(5) +
	# ReverbOn + note + EndBar (track A), 1-byte stub (track B).
	var feds_blob := PackedByteArray()
	feds_blob.append_array("feds".to_ascii_buffer())
	feds_blob.append_array([36, 0, 0, 0])              # data_size
	feds_blob.append_array([2, 0])                     # pair_count_plus1 (1 pair)
	feds_blob.append_array([7, 0])                     # resource_id
	feds_blob.append_array([28, 0, 0, 0])              # data_offset
	feds_blob.append_array([0, 0, 0, 0, 0, 0, 0, 0])   # pad to 0x18
	feds_blob.append_array([28, 0, 35, 0])             # track offset table
	feds_blob.append_array([0xAC, 0x05, 0xBA, 0x60, 0x0C, 0x90])   # track A @28
	feds_blob.append_array([0x90])                     # track B @35
	var bank = load("res://addons/exmateria_sound/runtime/feds_bank.gd").parse(feds_blob)
	var PairModel = load("res://src/effects/studio/FedsPairModel.gd")
	var PairProjector = load("res://src/effects/studio/FedsPairProjector.gd")
	# The pair inspector is EVENT-SCOPED (the lane panel is the listing): edit rows
	# only render for a selected event, so the probe selects the Instrument event.
	var pview: Dictionary = PairModel.pair_view(bank, 0, {}, null)
	pview["selected"] = {"track": 0, "event_index": 0}
	var pair_score := {"feds_pairs": [pview]}
	_collect_edit_channels(PairProjector.sections(
			{"kind": "pair", "ref": {"pair_idx": 0}}, null, pair_score), channels)
	# Emitter probe (ADR-0089): the shared-emitter groups emit editable cells/enum/int
	# rows on the "emitter" channel. EmitterParamRows reads the live emitter's raw
	# storage, so a minimal raw_data fixture is enough.
	var em = EffectEmitter.new()
	em.raw_data = {
		"position_start": [0, 0, 0], "curve_indices_raw": [0, 0, 0, 0, 0, 0, 0, 0],
		"motion_type_flag": 0, "animation_target_flag": 0,
		"emitter_flags_lo": 0, "emitter_flags_hi": 0,
	}
	var EmitterRows = load("res://src/effects/studio/EmitterParamRows.gd")
	# The group's Curve row is fed the effect's DISTINCT SHAPE SET (ADR-0089 curve-ownership
	# amendment), not a curve count. One synthetic shape is enough to sweep both of its
	# channels: the picker cell's `curve_assign` (a pick COPIES the shape here) and the
	# sparkline cell's `curve` (clicking it opens the painter, whose commit writes contents).
	var one_shape: Array = [{"key": "probe", "grid": [0, 128, 255], "index": 0,
		"sites": [{"emitter_index": 0, "slot": "position", "kind": "param"}]}]
	_collect_edit_channels([
		{"fields": EmitterRows.group(em, 0, "position", one_shape)},
		{"fields": EmitterRows.packed_config_rows(em, 0)},
	], channels)
	# Particle probe (ADR-0089 particle_timeline): the span projector's Event section emits
	# editable Enabled + Fires-emitter rows on the "particle" channel. EmitterProjector.sections
	# reads the write-side address (phase / channel_index / keyframe_index) from the span and
	# the retarget picker's choices from the effect's emitters.
	var EmitterProjectorClass = load("res://src/effects/studio/EmitterProjector.gd")
	var ped = ExMateriaEffects.EffectData.new()
	ped.emitters.append(EffectEmitter.new())
	var partspan := {
		"kind": "particle", "phase": "for_each", "channel_index": 0, "keyframe_index": 1,
		"emitter_index": 0, "emitter_id": 1, "disabled": false, "action_flags": 0,
	}
	_collect_edit_channels(EmitterProjectorClass.sections(partspan, ped), channels)
	# Effect-settings probe (#271 timeline_header + #272 effect_flags): the effect_settings
	# projector emits editable int rows on the "timeline_header" channel (the three GLOBAL phase
	# durations) AND a bitflags row on the "effect_flags" channel (the GLOBAL flags byte). It
	# reads the live TimelineData + flags dict off effect_data, so a minimal fixture of each is
	# enough. The flags dict must carry flags_byte so the Flags section is projected.
	var SettingsProjector = load("res://src/effects/studio/EffectSettingsProjector.gd")
	var sed = ExMateriaEffects.EffectData.new()
	sed.timeline = ExMateriaEffects.TimelineData.new()
	sed.flags = {"flags_byte": 0x23, "terrain_height_adjust": false, "audio_fade": false,
		"time_scale_pattern1": true, "time_scale_pattern2": false}
	# A swappable (DATA + canonical) E001-shaped 3-phase root so the effect_settings projector
	# emits the "script_pattern" choice row (#273, ADR-0094).
	sed.script_code_format = false
	sed.script_ops = [
		{"offset": 0, "opcode": 5, "name": "set_texture_page", "flags": 16, "size": 2},
		{"offset": 2, "opcode": 39, "name": "init_physics_params", "flags": 0, "size": 2},
		{"offset": 4, "opcode": 31, "name": "branch_target_type", "flags": 0, "size": 4, "arg1": 34},
		{"offset": 8, "opcode": 30, "name": "branch_anim_done_complex", "flags": 0, "size": 4, "arg1": 22},
		{"offset": 12, "opcode": 41, "name": "process_timeline_frame", "flags": 0, "size": 4, "arg1": 36},
		{"offset": 16, "opcode": 37, "name": "update_all_particles", "flags": 0, "size": 2},
		{"offset": 18, "opcode": 0, "name": "goto_yield", "flags": 0, "size": 4, "arg1": 8},
		{"offset": 22, "opcode": 37, "name": "update_all_particles", "flags": 0, "size": 2},
		{"offset": 24, "opcode": 22, "name": "branch_count_eq", "flags": 0, "size": 6, "arg1": 0, "arg2": 34},
		{"offset": 30, "opcode": 0, "name": "goto_yield", "flags": 0, "size": 4, "arg1": 22},
		{"offset": 34, "opcode": 4, "name": "end", "flags": 0, "size": 2},
	]
	var SettingsTarget = load("res://src/effects/studio/InspectionTarget.gd")
	_collect_edit_channels(SettingsProjector.sections(SettingsTarget.effect_settings(), sed, {}), channels)
	# Time-scale probe (#270, ADR-0093): the pacing curves author on the on-timeline "Time scale"
	# lane, not a projector row — so the editable surface is the score's pacing_lane. Each band
	# self-describes its write address (a shape:"edit" field with a time_scale field_ref, the same
	# address the band-click routes through), so the sweep picks up the "time_scale" channel the
	# same way it picks up projector rows.
	var TsModel = load("res://src/effects/studio/EffectScoreModel.gd")
	var tsed = ExMateriaEffects.EffectData.new()
	tsed.timeline = ExMateriaEffects.TimelineData.from_json({
		"header": {"phase1_duration": 8, "phase2_delay": 64}, "particle_channels": [
			{"context": "for_each", "channel_index": 0, "max_keyframe": 1, "keyframes": [
				{"time": 0, "emitter_id": 0}, {"time": 20, "emitter_id": 1}]}]})
	var ts_outer: Array = []
	var ts_foreach: Array = []
	for i in range(600):
		ts_outer.append(2)
		ts_foreach.append(2)
	tsed.time_scale = {"flags": {"time_scale_pattern1": true, "time_scale_pattern2": false},
		"outer_phases": ts_outer, "for_each": ts_foreach}
	var pacing_lane: Dictionary = TsModel.build(tsed).get("pacing_lane", {})
	_collect_edit_channels([{"fields": pacing_lane.get("bands", [])}], channels)
	# Frameset probe (#278): the frame target-kind projector emits editable int/choice
	# rows (palette_id, blend mode, semi_trans_on, is_8bpp, UV rect, vertices) on the
	# "frameset" channel. It reads a live frame Dictionary off effect_data.framesets,
	# so a minimal one-frame fixture is enough.
	var FramesetProjectorClass = load("res://src/effects/studio/FramesetProjector.gd")
	var FramesetTarget = load("res://src/effects/studio/InspectionTarget.gd")
	var fsed = ExMateriaEffects.EffectData.new()
	fsed.framesets = [{"index": 0, "header_flags": 0, "frames": [{
		"index": 0, "palette_id": 0, "semi_trans_mode": 0, "semi_trans_on": false,
		"is_8bpp": true, "blend_mode": "BLEND_50",
		"uv": {"x": 0, "y": 0, "width": 0, "height": 0},
		"vertices": {"top_left": [0, 0], "top_right": [0, 0],
			"bottom_left": [0, 0], "bottom_right": [0, 0]},
		"texture_page": {"x_base": 0, "y_base": 0, "blend": 0, "color_depth": 0},
	}]}]
	_collect_edit_channels(
		FramesetProjectorClass.sections(FramesetTarget.frame(0, 0), fsed, {}), channels)
	# Sequence probe (#275): the animation target-kind projector emits editable int/choice
	# rows (a FRAME's frameset/duration/depth_mode, SET_OFFSET's x/y, ADD_OFFSET's dx/dy)
	# on the "sequence" channel. It reads a live sequence Dictionary off
	# effect_data.animations, so a minimal one-of-each-opcode fixture is enough.
	var SequenceProjectorClass = load("res://src/effects/studio/SequenceProjector.gd")
	var sqed = ExMateriaEffects.EffectData.new()
	sqed.animations = [{"index": 0, "opcodes": [
		{"type": "SET_OFFSET", "x": 0, "y": 0},
		{"type": "FRAME", "frameset": 0, "duration": 0, "depth_mode": 0},
		{"type": "ADD_OFFSET", "dx": 0, "dy": 0},
		{"type": "LOOP"},
	]}]
	_collect_edit_channels(
		SequenceProjectorClass.sections(FramesetTarget.animation(0), sqed, {}), channels)
	return channels


## Walk projected sections; for every shape:"edit" field, record the channel of its
## write-side field_ref / field_refs.
func _collect_edit_channels(sections: Array, out: Dictionary) -> void:
	for sec in sections:
		for f in sec.get("fields", []):
			# A subsystem can be wired by a WRITE ACTION rather than a field row
			# (#280: the texture is authored by wholesale replacement, so it has
			# no per-field shape:"edit" cell to sweep). Such an action names the
			# channel it writes, so the invariant still holds — every editable
			# channel is reachable from some projector.
			if f.get("shape", "") == "action":
				var act: Dictionary = f.get("action", {})
				if act.has("channel"):
					out[str(act["channel"])] = true
				continue
			if f.get("shape", "") != "edit":
				continue
			if f.has("field_ref"):
				out[str(f["field_ref"].get("channel", ""))] = true
			if f.has("field_refs"):
				for comp in f["field_refs"].values():
					out[str(comp.get("channel", ""))] = true
			# A `cells` strip (ADR-0089) carries its refs on the sub-cells.
			for cell in f.get("cells", []):
				if cell.has("field_ref"):
					out[str(cell["field_ref"].get("channel", ""))] = true


func _load_manifest() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return {}
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {}
	return json.data


func _check(ok: bool, msg: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % msg)
