extends Node
## Move-2 guard (ADR-0068), re-pointed at the cut seam (#408 / ADR-0153 dec. 3): the
## typewriter-click retrigger fade is still OWNED by ExMateriaEffectSfx, but the engine now
## DECLARES it (`tunables()`) and `AudioHostAdapter` performs the bind + the on_update push,
## so an override still applies at boot in any scene. SpuAudioDebugPanel is a plain
## PanelContainer whose declared-tunable row the HOST builds into `tunable_rows`.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/SpuAudioPanelTuneFieldTest.tscn

const SpuPanel = preload("res://addons/exmateria_sound/debug/spu_audio_debug_panel.gd")
const TuneField = preload("res://src/debug/TuneField.gd")
const SLUG := "audio.click_retrigger_fade_ms"
const VOICE_SLUG := "audio.voice_mode"

var _passed := 0
var _failed := 0


func _ready() -> void:
	# The panel row is a pure VIEW — the slug (default + hint) must be registered before the
	# row is built or it renders unsupported. The ADAPTER binds now, not the engine; its
	# register_tunables() walks the engine's declarations and only binds (no audio hardware),
	# so it runs even when the engine autoload's _ready early-returned.
	if AudioHostAdapter:
		AudioHostAdapter.register_tunables()

	# The seam itself: the engine names no host config symbol, and its declaration is what
	# the host walks. Assert the declaration exists and covers the slug under test.
	var declared := PackedStringArray()
	for t in ExMateriaEffectSfx.tunables():
		declared.append(t["slug"])
	_assert_true(SLUG in declared, "ExMateriaEffectSfx DECLARES %s (the host binds it)" % SLUG)
	_assert_true("audio.monitor_enabled" in declared,
		"ExMateriaEffectSfx DECLARES audio.monitor_enabled (a system logs itself)")
	# goal #8 (ADR-0152): the PSX voice budget is a POLICY THE BRACKET IS GIVEN. This
	# assert is the one docs/GOALS.tsv row `2 Audio 8` was already claiming — the row
	# said "declared by tunables() and bound by the host adapter" while tunables()
	# returned two rows and neither was this one.
	_assert_true(VOICE_SLUG in declared,
		"ExMateriaEffectSfx DECLARES %s (the PSX voice budget is given, not hardcoded)" % VOICE_SLUG)

	# Owner bind: ExMateriaEffectSfx drives its property from the slug (only if the audio
	# autoload came up — its _ready early-returns without ExMateriaAudioEngine).
	if ExMateriaEffectSfx and ExMateriaEffectSfx.ready_ok:
		Tune.set_value(SLUG, 7.5)
		_assert_true(is_equal_approx(ExMateriaEffectSfx.click_retrigger_fade_ms, 7.5),
			"scrubbing the slug drives ExMateriaEffectSfx.click_retrigger_fade_ms (owner bind)")
		Tune.clear(SLUG)
		# The voice budget's setter must RECORD even where it cannot rebuild, because the
		# adapter pushes it at bind time — before _ready in a scene that autoloads the
		# adapter early. It used to drop the write on `not ready_ok`, which would boot
		# UNLOCKED while the registry said FAITHFUL.
		var was: int = ExMateriaEffectSfx.voice_mode
		Tune.set_value(VOICE_SLUG, ExMateriaEffectSfx.VoiceMode.FAITHFUL)
		_assert_true(ExMateriaEffectSfx.voice_mode == ExMateriaEffectSfx.VoiceMode.FAITHFUL,
			"scrubbing %s drives ExMateriaEffectSfx.voice_mode (owner bind)" % VOICE_SLUG)
		Tune.clear(VOICE_SLUG)
		ExMateriaEffectSfx.set_voice_mode(was)
	else:
		print("[note] ExMateriaEffectSfx not ready in this env — owner-bind assert skipped")

	# Panel row is TuneField-built BY THE HOST into the panel's declared slot, and writes
	# through to the slug. Built the same way AudioHostAdapter.register_panels() does it.
	var panel := SpuPanel.new()
	add_child(panel)
	panel.setup()
	_assert_true(panel.tunable_rows != null, "the panel declares a host-fillable row slot")
	_assert_true(panel.PANEL_CATEGORY == "audio",
		"the panel declares its debug category as a STRING the adapter maps")
	for t in ExMateriaEffectSfx.tunables():
		TuneField.add(panel.tunable_rows, t["label"], t["slug"])
	var row := _find_row(panel, "Fade (ms):")
	_assert_true(row != null, "the Fade row exists")
	if row:
		var label := row.get_child(0) as Label
		_assert_true(label != null and label.get_theme_color("font_color") == TuneField.TUNABLE_ACCENT,
			"the Fade row carries the TuneField accent label")
		var sb := _first_spinbox(row)
		_assert_true(sb != null, "the Fade row has a SpinBox control")
		if sb:
			sb.value = 6.0
			sb.value_changed.emit(6.0)
			_assert_true(is_equal_approx(float(Tune.bind(SLUG, 3.0)), 6.0),
				"scrubbing the row writes through to the slug")
	Tune.clear(SLUG)

	# The enum hint has to reach the CONTROL, not just the registry: ADR-0068 dec. 11's
	# resolver renders an OptionButton when `hint.enum` is present and a spinbox off the
	# bare int otherwise, so a declaration that forgot the hint would still bind, still
	# scrub, and render an unlabelled number nobody can read as FAITHFUL/UNLOCKED.
	var vrow := _find_row(panel, "Voice budget:")
	_assert_true(vrow != null, "the Voice budget row exists")
	if vrow:
		var ob := _first_option_button(vrow)
		_assert_true(ob != null, "the Voice budget row renders an OptionButton, not a SpinBox")
		if ob:
			_assert_true(ob.item_count == 2, "the OptionButton carries both voice modes")
	Tune.clear(VOICE_SLUG)

	# The write PORT (ADR-0113): the package writes a declared tunable through a Callable
	# the host filled, so a panel preset reaches the registry without the package naming it.
	ExMateriaEffectSfx.write_tunable(SLUG, 9.0)
	_assert_true(is_equal_approx(float(Tune.bind(SLUG, 3.0)), 9.0),
		"write_tunable reaches the host registry through the host-filled port")
	Tune.clear(SLUG)
	panel.queue_free()

	print("\n=== SpuAudioPanelTuneFieldTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] SpuAudioPanelTuneFieldTest")
		get_tree().quit(1)
	else:
		print("[PASS] SpuAudioPanelTuneFieldTest")
		get_tree().quit(0)


func _find_row(node: Node, label_text: String) -> Control:
	for child in node.get_children():
		if child is HBoxContainer and child.get_child_count() > 0:
			var lbl := child.get_child(0) as Label
			if lbl and lbl.text == label_text:
				return child
		var found := _find_row(child, label_text)
		if found:
			return found
	return null


func _first_option_button(row: Control) -> OptionButton:
	for child in row.get_children():
		if child is OptionButton:
			return child
	return null


func _first_spinbox(row: Control) -> SpinBox:
	for child in row.get_children():
		if child is SpinBox:
			return child
	return null


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — expected true" % label)
