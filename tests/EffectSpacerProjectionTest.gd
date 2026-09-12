extends Node
## TDD guard for SPACER projection (ADR-0087 FIFTH amendment): `fields.spacer` is the
## DISABLE-EQUIVALENCE verdict — computed lane-wide at score build by the pure fold oracle
## (SpacerVerdicts). The fifth amendment keeps the PREDICATE but reverses the TREATMENT: an
## enabled inert spacer is invisible EMPTY SPACE (EffectScoreTimeline.is_hidden_spacer), the
## inert slate + flavour note are retired, and a DELIBERATELY-DISABLED event stays drawn
## (dimmed) under the repurposed hatch. Every colour VALUE edit rebuilds the score, so the
## projected verdict is never stale — the live re-projection reads the snapshot verdict.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectSpacerProjectionTest.tscn

const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const TimelineDataClass = ExMateriaEffects.TimelineData
const PaletteDataClass = ExMateriaEffects.PaletteData
const ScreenDataClass = ExMateriaEffects.ScreenData
const PaletteChannelClass = preload("res://src/effects/studio/PaletteChannel.gd")
const ScreenChannelClass = preload("res://src/effects/studio/ScreenChannel.gd")
const TimelineClass = preload("res://src/effects/studio/EffectScoreTimeline.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_palette_verdict_is_contextual_lead_vs_fade()
	_test_palette_projection_carries_spacer()
	_test_screen_projection_carries_spacer()
	_test_screen_contextual_lead_in_hatches()
	_test_spacer_is_empty_space_on_both_lanes()
	_test_palette_edit_flags_layout_on_spacer_flip()
	_test_screen_edit_flags_layout_on_spacer_flip()
	_test_no_spacer_note_on_either_lane()
	_test_redundant_gradient_is_inert_no_note()
	_test_real_effects_ground_the_spacer_invariants()

	print("\n=== EffectSpacerProjectionTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectSpacerProjectionTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectSpacerProjectionTest")
		get_tree().quit(0)


## The fourth amendment's motivating shape (E317 caster): byte-identical m4 Δ0 events
## get OPPOSITE verdicts by context — the lead-in (nothing beneath) and the post-fade
## hold hatch; the flash's fade-out ramp is real. `spacer_contextual` marks the
## fold-derived flavour (an enabled event whose bytes aren't intrinsically inert).
func _test_palette_verdict_is_contextual_lead_vs_fade() -> void:
	var ed = _effect_with_palette([
		{"index": 0, "duration_frames": 8, "time_value": 1, "enabled": true,
			"blend_mode": 4, "rgb": [0, 0, 0]},
		{"index": 1, "duration_frames": 8, "time_value": 1, "enabled": true,
			"blend_mode": 4, "rgb": [25, 23, 8]},
		{"index": 2, "duration_frames": 8, "time_value": 1, "enabled": true,
			"blend_mode": 4, "rgb": [0, 0, 0]},
		{"index": 3, "duration_frames": 8, "time_value": 1, "enabled": true,
			"blend_mode": 4, "rgb": [0, 0, 0]},
	])
	var lane := _lane(Model.build(ed), "palette:for_each:caster")
	var flags: Array = []
	for span in lane["spans"]:
		flags.append(bool(span["fields"].get("spacer", false)))
	_assert_eq(flags, [true, false, false, true],
		"m4 Δ0 lead-in + post-fade hold hatch; the flash and its fade-out ramp stay real")
	# Fifth amendment: an ENABLED inert spacer is invisible EMPTY SPACE — hidden, not slate.
	_assert_true(bool(lane["spans"][0]["fields"].get("enabled", false)),
		"the lead-in is enabled (the fold detected the no-op; the author never chose off)")
	_assert_true(TimelineClass.is_hidden_spacer(lane["spans"][0], ""),
		"…so it renders as nothing (invisible empty space)")
	_assert_eq(lane["spans"][0]["color"], Color(0, 0, 0, 1),
		"…its fill is its own (black) rgb, NOT the retired inert slate")


## The intrinsic class is SUBSUMED: a disabled null tween and an enabled mode-0 Δ0
## still project spacer=true (nothing hatched under the third amendment un-hatches),
## now flagged spacer_contextual=false (the bytes themselves are inert — the note
## keeps the stronger wording). A real tint stays hued.
func _test_palette_projection_carries_spacer() -> void:
	var ed = _effect_with_palette([
		{"index": 0, "duration_frames": 6, "enabled": false, "rgb": [0, 0, 0]},
		{"index": 1, "duration_frames": 8, "enabled": true, "blend_mode": 0, "rgb": [0, 0, 0]},
		{"index": 2, "duration_frames": 10, "enabled": true, "blend_mode": 3, "rgb": [0, 255, 0]},
	])
	var lane := _lane(Model.build(ed), "palette:for_each:caster")
	_assert_eq(lane["spans"].size(), 3, "all three played keyframes draw (fully-tiled)")
	var disabled: Dictionary = lane["spans"][0]
	var identity: Dictionary = lane["spans"][1]
	var real: Dictionary = lane["spans"][2]
	_assert_true(bool(disabled["fields"].get("spacer", false)),
		"the disabled null tween projects spacer=true")
	_assert_true(bool(identity["fields"].get("spacer", false)),
		"the enabled mode-0 Δ0 identity projects spacer=true")
	_assert_true(not bool(real["fields"].get("spacer", false)),
		"a real tint projects spacer=false")
	_assert_eq(real["color"], Color(0, 1, 0, 1), "the real tween keeps its rgb hue")
	# Fifth amendment: the ENABLED identity spacer is hidden; the DISABLED null tween is
	# "muted, not gone" — drawn dimmed + selectable.
	_assert_true(bool(identity["fields"].get("enabled", false)),
		"the enabled identity spacer stays enabled")
	_assert_true(TimelineClass.is_hidden_spacer(identity, ""),
		"…and is hidden (empty space)")
	_assert_true(not bool(disabled["fields"].get("enabled", true)),
		"the disabled null tween reads enabled=false")
	_assert_true(not TimelineClass.is_hidden_spacer(disabled, ""),
		"…so it is NOT hidden (a human chose off — muted, not gone)")
	_assert_true(disabled["color"] != Color(0.28, 0.30, 0.34, 1.0),
		"…and it wears no inert slate (that treatment is retired)")


## The screen identity no-op (the disable byte-swap) stays a spacer — by fold
## equivalence now, no special-casing. Real Blends and leading Gradients stay real
## (transform equality keeps an absolute set real even when it coincides with the
## previewed sky); the border still tells the KIND, untouched by the hatch.
func _test_screen_projection_carries_spacer() -> void:
	var ed = _effect_with_screen([
		# kf0: the identity no-op Blend (mode TINT, blend_mode 0, zero start bytes) — a spacer.
		{"index": 0, "duration_frames": 12, "mode": "TINT", "blend_mode": 0,
			"start_r": 0, "start_g": 0, "start_b": 0},
		# kf1: a real Blend tint.
		{"index": 1, "duration_frames": 20, "mode": "TINT", "blend_mode": 1,
			"start_r": 255, "start_g": 0, "start_b": 0},
		# kf2: a LEADING Gradient — an absolute set, real as a transform for any base.
		{"index": 2, "duration_frames": 8, "mode": "FADE",
			"start_r": 10, "start_g": 20, "start_b": 30,
			"end_r": 40, "end_g": 50, "end_b": 60},
		# trailing terminator outside the played window (max_keyframe 4 → plays 0..2)
		{"index": 3, "duration_frames": 8, "mode": "FADE"},
	], 4)
	var lane := _lane(Model.build(ed), "screen:for_each")
	_assert_eq(lane["spans"].size(), 3, "the played window draws (terminator doesn't)")
	var noop: Dictionary = lane["spans"][0]
	var blend: Dictionary = lane["spans"][1]
	var grad: Dictionary = lane["spans"][2]
	_assert_true(bool(noop["fields"].get("spacer", false)),
		"the identity no-op Blend projects spacer=true")
	_assert_eq(str(noop["fields"].get("border", "solid")), "solid",
		"…border stays the KIND (solid Blend) — orthogonal to the hatch")
	# Fifth amendment: the screen lane carries `enabled` too, and an enabled inert no-op is
	# invisible empty space (not slate).
	_assert_true(bool(noop["fields"].get("enabled", false)),
		"the identity no-op is enabled (an intrinsic byte no-op, not a human-cleared bit)")
	_assert_true(TimelineClass.is_hidden_spacer(noop, ""),
		"…so the screen spacer renders as nothing")
	_assert_true(noop["color"] != Color(0.28, 0.30, 0.34, 1.0),
		"…and wears no inert slate (retired)")
	_assert_true(not bool(blend["fields"].get("spacer", false)),
		"a real Blend is not a spacer")
	_assert_eq(blend["color"], Color(1, 0, 0, 1), "…and keeps its produced colour")
	_assert_true(not bool(grad["fields"].get("spacer", false)),
		"a leading Gradient is never a spacer (an absolute set ≠ passthrough as transforms)")
	_assert_eq(str(grad["fields"].get("border", "solid")), "dashed",
		"…and keeps its dashed KIND border")


## The screen lane hatches CONTEXTUALLY too: a bm4 Δ0 lead-in (base + 0 over a clean
## backdrop) is a spacer by the fold even though its bytes are not the identity class
## — the E317 screen lane's real shape.
func _test_screen_contextual_lead_in_hatches() -> void:
	var ed = _effect_with_screen([
		{"index": 0, "duration_frames": 12, "mode": "TINT", "blend_mode": 4,
			"start_r": 0, "start_g": 0, "start_b": 0},
		{"index": 1, "duration_frames": 20, "mode": "TINT", "blend_mode": 5,
			"start_r": 0, "start_g": 0, "start_b": 0},
	], 3)
	var lane := _lane(Model.build(ed), "screen:for_each")
	var lead: Dictionary = lane["spans"][0]
	_assert_true(bool(lead["fields"].get("spacer", false)),
		"a bm4 Δ0 lead-in over a clean backdrop is inert (contextual verdict)")
	_assert_true(not bool(lane["spans"][1]["fields"].get("spacer", false)),
		"the bm5 Δ0 half-dim is real — it IS the darkening")


## One treatment across lanes (fifth amendment): an enabled inert spacer is invisible EMPTY
## SPACE on BOTH colour lanes — the author's question (real event or empty space?) is binary
## and lane-independent, and empty space is the shared answer (not a shared slate fill).
func _test_spacer_is_empty_space_on_both_lanes() -> void:
	var pal_ed = _effect_with_palette([
		{"index": 0, "duration_frames": 8, "time_value": 1, "enabled": true,
			"blend_mode": 0, "rgb": [0, 0, 0]},
		{"index": 1, "duration_frames": 8, "enabled": true, "blend_mode": 3, "rgb": [9, 9, 9]},
	])
	var scr_ed = _effect_with_screen([
		{"index": 0, "duration_frames": 12, "mode": "TINT", "blend_mode": 0,
			"start_r": 0, "start_g": 0, "start_b": 0},
		{"index": 1, "duration_frames": 20, "mode": "TINT", "blend_mode": 1,
			"start_r": 255, "start_g": 0, "start_b": 0},
	], 3)
	var pal_spacer: Dictionary = _lane(Model.build(pal_ed), "palette:for_each:caster")["spans"][0]
	var scr_spacer: Dictionary = _lane(Model.build(scr_ed), "screen:for_each")["spans"][0]
	_assert_true(TimelineClass.is_hidden_spacer(pal_spacer, ""),
		"the palette enabled-inert spacer is empty space")
	_assert_true(TimelineClass.is_hidden_spacer(scr_spacer, ""),
		"the screen enabled-inert spacer is empty space — one lane-independent treatment")


## RESTYLE (fourth amendment decision 4): every palette VALUE edit flags
## `invalidates_layout` UNCONDITIONALLY — the verdict is contextual now, so ANY colour
## edit can flip ANOTHER keyframe's verdict; the host rebuild recomputes lane-wide.
## The third amendment's per-keyframe verdict-flip wrapper is deleted (subsumed).
## The projected verdict of a DIFFERENT keyframe follows the rebuild: editing the
## flash's Δ to zero makes the ex-fade-out redundant — its span hatches next build.
func _test_palette_edit_flags_layout_on_spacer_flip() -> void:
	var ed = _effect_with_palette([
		{"index": 0, "duration_frames": 8, "time_value": 1, "enabled": true,
			"blend_mode": 4, "rgb": [25, 23, 8]},
		{"index": 1, "duration_frames": 8, "time_value": 1, "enabled": true,
			"blend_mode": 4, "rgb": [0, 0, 0]},
	])
	var lane := _lane(Model.build(ed), "palette:for_each:caster")
	_assert_true(not bool(lane["spans"][1]["fields"].get("spacer", false)),
		"the m4 Δ0 after a live flash starts REAL (it is the fade-out)")
	var ref := {"channel": "palette", "context": "for_each", "channel_name": "caster",
		"event_index": 0, "field": "r"}
	var res: Dictionary = PaletteChannelClass.apply_raw(ed, ref, 5)
	_assert_true(bool(res.get("invalidates_layout", false)),
		"an rgb byte edit flags layout unconditionally (verdicts are contextual)")
	res = PaletteChannelClass.apply_raw(ed, ref, 9)
	_assert_true(bool(res.get("invalidates_layout", false)),
		"…every value edit does — no more per-keyframe flip detection")
	var mode_ref := {"channel": "palette", "context": "for_each", "channel_name": "caster",
		"event_index": 0, "field": "blend_mode"}
	res = PaletteChannelClass.apply_raw(ed, mode_ref, 9)
	_assert_true(bool(res.get("invalidates_layout", false)),
		"a blend-mode edit flags layout unconditionally")
	# Cross-keyframe restyle: zero the flash — keyframe 1 goes redundant, and the
	# REBUILT projection hatches it without keyframe 1 ever being touched.
	for f in ["r", "g", "b"]:
		PaletteChannelClass.apply_raw(ed, {"channel": "palette", "context": "for_each",
			"channel_name": "caster", "event_index": 0, "field": f}, 0)
	lane = _lane(Model.build(ed), "palette:for_each:caster")
	_assert_true(bool(lane["spans"][1]["fields"].get("spacer", false)),
		"editing keyframe 0 wakes keyframe 1's hatch on the rebuilt score (cross-keyframe restyle)")


## Same on the screen lane: colour-byte and blend-mode edits flag layout
## unconditionally (kind/enabled are already structural and reproject).
func _test_screen_edit_flags_layout_on_spacer_flip() -> void:
	var ed = _effect_with_screen([
		{"index": 0, "duration_frames": 12, "mode": "TINT", "blend_mode": 0,
			"start_r": 0, "start_g": 0, "start_b": 0},
		{"index": 1, "duration_frames": 8, "mode": "FADE"},
	], 3)
	var ref := {"channel": "screen", "context": "for_each", "event_index": 0, "field": "start_r"}
	var res: Dictionary = ScreenChannelClass.apply_raw(ed, ref, 5)
	_assert_true(bool(res.get("invalidates_layout", false)),
		"a colour byte edit flags layout (spacer → real restyles)")
	res = ScreenChannelClass.apply_raw(ed, ref, 9)
	_assert_true(bool(res.get("invalidates_layout", false)),
		"…and unconditionally (a real → real edit can flip ANOTHER keyframe's verdict)")
	var mode_ref := {"channel": "screen", "context": "for_each", "event_index": 0,
		"field": "blend_mode"}
	res = ScreenChannelClass.apply_raw(ed, mode_ref, 3)
	_assert_true(bool(res.get("invalidates_layout", false)),
		"a blend-mode edit flags layout unconditionally")


## The inspector note is REMOVED (fifth amendment decision 6): a spacer can no longer be
## selected, so the only span whose section shows is a DISABLED (still-selectable) event —
## and it relies on the Enabled control, not a "Spacer" note. No colour section carries a
## Spacer note anymore, on either lane; the Enabled row stays so a disabled event re-enables.
func _test_no_spacer_note_on_either_lane() -> void:
	var pal_ed = _effect_with_palette([
		{"index": 0, "duration_frames": 6, "enabled": false, "rgb": [0, 0, 0]},
		{"index": 1, "duration_frames": 8, "enabled": true, "blend_mode": 3, "rgb": [0, 255, 0]},
	])
	var pal_lane := _lane(Model.build(pal_ed), "palette:for_each:caster")
	var disabled_rows := _section_fields(Model.span_sections(pal_lane["spans"][0], pal_ed))
	var real_rows := _section_fields(Model.span_sections(pal_lane["spans"][1], pal_ed))
	_assert_true(_note_row(disabled_rows).is_empty(),
		"a disabled palette tween's section carries NO Spacer note (removed)")
	_assert_true(not _enabled_row(disabled_rows).is_empty(),
		"…but keeps the Enabled control so it can be re-enabled")
	_assert_true(_note_row(real_rows).is_empty(),
		"a real palette tween carries no Spacer note")

	var scr_ed = _effect_with_screen([
		{"index": 0, "duration_frames": 12, "mode": "TINT", "blend_mode": 0,
			"start_r": 0, "start_g": 0, "start_b": 0},
		{"index": 1, "duration_frames": 20, "mode": "TINT", "blend_mode": 1,
			"start_r": 255, "start_g": 0, "start_b": 0},
	], 3)
	var scr_lane := _lane(Model.build(scr_ed), "screen:for_each")
	var scr_rows := _section_fields(Model.span_sections(scr_lane["spans"][0], scr_ed))
	_assert_true(_note_row(scr_rows).is_empty(),
		"a screen spacer's section carries NO Spacer note (removed)")


## Grounding on real ROM data (E317 palette-rich, E015 screen-rich) — the amendment's
## acceptance pins, static-rooted (ColorRecipe/ColorStack) and validated here on the
## real extracts. Pristine played windows now CONTAIN spacers (the ROM spaces its
## colour lanes with over-base Δ0 ops and restores-over-nothing):
##   E317 caster: [lead, lead, flash, fade-out, hold, m8] → [T, T, F, F, T, T].
##   The DARKENING m5/bm5 Δ0 events stay real (E317 affected_units kf1, E015 screen);
##   an idempotent REPEAT of a settled base-source op hatches (E317 aff. kf4 —
##   disable-equivalent by construction, the fold's honest refinement of the
##   amendment's "1/5 never spacers" bullet, which holds for the first-of-kind).
##   E015 phase2's opening m8 hatches on palette AND screen (for_each already
##   restored everything — cross-phase context); for_each's own m8 stays real.
func _test_real_effects_ground_the_spacer_invariants() -> void:
	var seen := 0
	var invariants_hold := true
	for name in ["E317", "E015"]:
		var dir := "res://assets/effects/%s" % name
		if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
			print("[SKIP] %s assets absent — regen with tools/bootstrap_assets.sh" % name)
			continue
		var ed = ExMateriaEffects.EffectData.load_from_directory(dir)
		for lane in Model.build(ed)["lanes"]:
			if not (lane["kind"] in ["palette", "screen"]):
				continue
			for span in lane["spans"]:
				seen += 1
				var f: Dictionary = span.get("fields", {})
				# Fifth amendment: an ENABLED inert spacer is invisible empty space (never slate),
				# and no colour span wears the retired inert slate at all.
				if span["color"] == Color(0.28, 0.30, 0.34, 1.0):
					invariants_hold = false   # the inert slate is retired
				if bool(f.get("spacer", false)) and bool(f.get("enabled", false)) \
						and not TimelineClass.is_hidden_spacer(span, ""):
					invariants_hold = false   # an enabled inert spacer must be hidden
				if str(f.get("border", "solid")) == "dashed" \
						and (lane["kind"] != "screen" or str(f.get("screen_kind", "")) != "Grad"):
					invariants_hold = false   # dashed = Gradient only, everywhere
	if seen == 0:
		return   # both extracts absent — grounding skipped
	_assert_true(invariants_hold, "pristine spans: spacer ⇔ inert fill; dashed only on screen Gradients")

	var dir317 := "res://assets/effects/E317"
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir317)):
		var ed317 = ExMateriaEffects.EffectData.load_from_directory(dir317)
		var score := Model.build(ed317)
		var caster := _lane(score, "palette:for_each:caster")
		_assert_eq(_spacer_flags(caster), [true, true, false, false, true, true],
			"E317 caster: lead-ins + post-fade hold + trailing m8 inert; flash + fade-out real")
		_assert_true(TimelineClass.is_hidden_spacer(caster["spans"][0], ""),
			"…the enabled lead-in is invisible empty space")
		var aff := _lane(score, "palette:for_each:affected_units")
		_assert_true(not bool(aff["spans"][1]["fields"].get("spacer", false)),
			"E317 affected_units kf1 (m5 Δ0, THE darkening) stays real")
		_assert_true(bool(aff["spans"][4]["fields"].get("spacer", false)),
			"…kf4 (m5 Δ0 repeat of the settled half-dim) hatches — idempotent repeat")
		_assert_true(not bool(aff["spans"][15]["fields"].get("spacer", false)),
			"…the m8 after live tints stays real (the cleanup)")
		var scr := _lane(score, "screen:for_each")
		_assert_true(bool(scr["spans"][0]["fields"].get("spacer", false)),
			"E317 screen bm4 Δ0 lead-in hatches")
		_assert_true(not bool(scr["spans"][1]["fields"].get("spacer", false)),
			"E317 screen bm5 Δ0 (the backdrop dim) stays real")
		_assert_true(not bool(scr["spans"][6]["fields"].get("spacer", false)),
			"E317 screen bm8 after the live dim stays real")

		# A fresh insert on real E317 is BORN a spacer (disabled null tween seed).
		var res := PaletteChannelClass.insert_event(ed317,
			{"channel": "palette", "context": "for_each", "channel_name": "caster", "frame": 20})
		var new_index := int(res.get("event_index", -1))
		_assert_true(new_index >= 0, "insert-waypoint lands on the real E317 caster lane")
		var lane317 := _lane(Model.build(ed317), "palette:for_each:caster")
		var inserted := {}
		var real_events := 0
		for span in lane317["spans"]:
			if int(span["keyframe_index"]) == new_index:
				inserted = span
			elif not bool(span["fields"].get("spacer", false)):
				real_events += 1
		_assert_true(not inserted.is_empty(), "the inserted keyframe projects a span")
		_assert_true(bool(inserted.get("fields", {}).get("spacer", false)),
			"…and is born a spacer (hatched, ready to be edited into a real event)")
		_assert_true(real_events > 0, "…alongside the lane's real colour events")

	var dir015 := "res://assets/effects/E015"
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir015)):
		var ed015 = ExMateriaEffects.EffectData.load_from_directory(dir015)
		var score := Model.build(ed015)
		var p2 := _lane(score, "palette:phase2:affected_units")
		_assert_true(bool(p2["spans"][0]["fields"].get("spacer", false)),
			"E015 phase2's opening m8 hatches (for_each already restored — cross-phase)")
		var fe := _lane(score, "palette:for_each:affected_units")
		_assert_true(not bool(fe["spans"][21]["fields"].get("spacer", false)),
			"…for_each's own m8 (after LIVE tints) stays real")
		var scr2 := _lane(score, "screen:phase2")
		_assert_true(bool(scr2["spans"][0]["fields"].get("spacer", false)),
			"E015 screen phase2's opening bm8 hatches too")
		var scrfe := _lane(score, "screen:for_each")
		_assert_true(not bool(scrfe["spans"][6]["fields"].get("spacer", false)),
			"E015 screen for_each bm5 Δ0 (the dim) stays real")


## A Gradient can be a CONTEXTUAL spacer too (a redundant re-set after an equal settled
## Gradient) — the fold still marks it inert (so the painter can hide it), but the fifth
## amendment removed the flavour note; no Gradient section narrates it.
func _test_redundant_gradient_is_inert_no_note() -> void:
	var ed = _effect_with_screen([
		{"index": 0, "duration_frames": 8, "mode": "FADE",
			"start_r": 32, "start_g": 64, "start_b": 124,
			"end_r": 32, "end_g": 64, "end_b": 124},
		{"index": 1, "duration_frames": 8, "mode": "FADE",
			"start_r": 32, "start_g": 64, "start_b": 124,
			"end_r": 32, "end_g": 64, "end_b": 124},
	], 3)
	var lane := _lane(Model.build(ed), "screen:for_each")
	_assert_true(bool(lane["spans"][1]["fields"].get("spacer", false)),
		"the redundant re-set Gradient is verdict-inert")
	var note := _note_row(_section_fields(Model.span_sections(lane["spans"][1], ed)))
	_assert_true(note.is_empty(), "…but its Gradient section carries NO note (removed)")
	var lead_note := _note_row(_section_fields(Model.span_sections(lane["spans"][0], ed)))
	_assert_true(lead_note.is_empty(), "the leading Gradient stays note-free (real)")


# --- fixtures --------------------------------------------------------------

func _effect_with_palette(keyframes: Array):
	var ed = ExMateriaEffects.EffectData.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8, "phase2_delay": 64}, "particle_channels": []})
	ed.palette = PaletteDataClass.from_json({
		"for_each": {
			"caster": {"context": "for_each", "channel_name": "caster",
				# max_keyframe = size + 1 so ALL supplied keyframes are in the played
				# window (0..max_keyframe-2), mirroring PaletteSubsystem._each_keyframe.
				"max_keyframe": keyframes.size() + 1,
				"keyframes": keyframes},
		},
	})
	return ed


func _effect_with_screen(keyframes: Array, max_keyframe: int):
	var ed = ExMateriaEffects.EffectData.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8, "phase2_delay": 64}, "particle_channels": []})
	ed.screen = ScreenDataClass.from_json({
		"for_each": {"context": "for_each", "max_keyframe": max_keyframe,
			"keyframes": keyframes},
	})
	return ed


func _lane(score: Dictionary, lane_id: String) -> Dictionary:
	for lane in score["lanes"]:
		if lane["id"] == lane_id:
			return lane
	return {}


func _spacer_flags(lane: Dictionary) -> Array:
	var out: Array = []
	for span in lane.get("spans", []):
		out.append(bool(span["fields"].get("spacer", false)))
	return out


## Flatten a projector's [Section] list to its field rows.
func _section_fields(sections: Array) -> Array:
	var out: Array = []
	for s in sections:
		out.append_array(s.get("fields", []))
	return out


## The Spacer note row, identified by name ({} if absent). Since the fifth amendment removed
## the note, these helpers assert its ABSENCE.
func _note_row(rows: Array) -> Dictionary:
	for r in rows:
		if str(r.get("name", "")) == "Spacer":
			return r
	return {}


## The Enabled control row ({} if absent) — the fifth amendment keeps it (a disabled event
## re-enables through it) even though the Spacer note is gone.
func _enabled_row(rows: Array) -> Dictionary:
	for r in rows:
		if str(r.get("name", "")) == "Enabled":
			return r
	return {}


# --- asserts --------------------------------------------------------------

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
