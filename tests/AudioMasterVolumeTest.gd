extends Node
## Whole-game volume control: MasterBus OWNS the master volume — it applies to the
## Godot Master bus (index 0, where music + SFX + UI re-sum) and persists the value in
## the per-machine UserSettings (user_settings.json). AudioMasterVolumeDebugPanel is a plain
## slider view that delegates to MasterBus.
##
## Re-pointed at #409, which split `ExMateriaAudioEngine` at the SPU/bus line (ADR-0153 dec. 2):
## the SPUs stayed `ExMateriaAudioEngine` and left for the package, the bus rack became `MasterBus`
## and stayed host. Every assertion below is about the bus half, so all of it moved.
##
## This guard proves the owner logic without depending on audio hardware being loaded:
## the Master bus exists regardless of any SPU being up, so the linear->dB mapping,
## the 0..1 clamp, the silent floor, and the UserSettings round-trip are all testable,
## plus the panel builds a slider that drives MasterBus.set_master_volume.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/AudioMasterVolumeTest.tscn

const VolumePanel = preload("res://src/debug/AudioMasterVolumeDebugPanel.gd")
const MASTER_BUS := 0

var _passed := 0
var _failed := 0
var _saved_volume := 1.0


func _ready() -> void:
	# Snapshot the real per-machine value so the disk-free (persist=false) checks below
	# never leave a test value in user_settings.json.
	_saved_volume = UserSettings.master_volume

	# --- Owner: the linear->dB mapping onto the Master bus. The curve is shifted UP by
	# MASTER_MAX_GAIN_DB so 100% BOOSTS into the -0.3 dB limiter (the SPU source sits ~11 dB
	# below full scale, so plain unity was too quiet); the limiter catches any peaks. ---
	# The gain lives on the PRE-limiter Amplify (get_master_gain_db), NOT the bus fader — a boost
	# on the fader would land after the limiter and clip.
	MasterBus.set_master_volume(0.5, false)
	_assert_approx(MasterBus.get_master_gain_db(),
		MasterBus.MASTER_MAX_GAIN_DB + linear_to_db(0.5),
		"set_master_volume(0.5) drives the pre-limiter gain to MASTER_MAX_GAIN_DB + linear_to_db(0.5)")
	_assert_approx(MasterBus.get_master_volume(), 0.5,
		"get_master_volume reflects the last set (0.5)")

	# --- Clamp above unity; 1.0 = the full boost (drives the quiet source up to the limiter) ---
	MasterBus.set_master_volume(2.0, false)
	_assert_approx(MasterBus.get_master_volume(), 1.0, "over-unity clamps to 1.0")
	_assert_approx(MasterBus.get_master_gain_db(), MasterBus.MASTER_MAX_GAIN_DB,
		"1.0 => MASTER_MAX_GAIN_DB (full boost into the limiter)")
	_assert_true(MasterBus.MASTER_MAX_GAIN_DB > 0.0, "the top of the slider is a real boost, not unity")
	# The gain must sit BEFORE the limiter in the rack (or a boost clips past it).
	var amp_idx := -1
	var lim_idx := -1
	for i in range(AudioServer.get_bus_effect_count(MASTER_BUS)):
		var fx = AudioServer.get_bus_effect(MASTER_BUS, i)
		if fx is AudioEffectAmplify and amp_idx < 0: amp_idx = i
		if fx is AudioEffectHardLimiter and lim_idx < 0: lim_idx = i
	_assert_true(amp_idx >= 0 and lim_idx >= 0 and amp_idx < lim_idx,
		"the whole-game gain (Amplify @%d) sits BEFORE the HardLimiter (@%d)" % [amp_idx, lim_idx])

	# --- Silent floor: 0.0 is fully silent, not linear_to_db(0)=-inf noise ---
	MasterBus.set_master_volume(0.0, false)
	_assert_approx(MasterBus.get_master_volume(), 0.0, "0.0 clamps/holds at 0.0")
	_assert_true(MasterBus.get_master_gain_db() <= -60.0,
		"0.0 drives the gain to a silent floor (<= -60 dB)")

	# --- UserSettings round-trip in memory (no disk) ---
	MasterBus.set_master_volume(0.42, false)
	_assert_approx(UserSettings.master_volume, 0.42,
		"MasterBus delegates the live value to UserSettings.master_volume")

	# --- Panel: a slider that drives the owner ---
	var panel := VolumePanel.new()
	add_child(panel)
	panel.setup()
	var slider := _find_slider(panel)
	_assert_true(slider != null, "the panel builds a Master volume slider")
	if slider:
		_assert_true(is_equal_approx(slider.min_value, 0.0) and is_equal_approx(slider.max_value, 1.0),
			"the slider spans 0..1")
		slider.value = 0.25
		slider.value_changed.emit(0.25)
		_assert_approx(MasterBus.get_master_volume(), 0.25,
			"scrubbing the slider drives MasterBus.set_master_volume")
	panel.queue_free()

	# Restore the user's real value (persisted, so the game boots at what they had).
	MasterBus.set_master_volume(_saved_volume, true)

	print("\n=== AudioMasterVolumeTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] AudioMasterVolumeTest")
		get_tree().quit(1)
	else:
		print("[PASS] AudioMasterVolumeTest")
		get_tree().quit(0)


func _find_slider(node: Node) -> Slider:
	for child in node.get_children():
		if child is Slider:
			return child
		var found := _find_slider(child)
		if found:
			return found
	return null


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — expected true" % label)


func _assert_approx(actual: float, expected: float, label: String) -> void:
	if is_equal_approx(actual, expected) or absf(actual - expected) < 0.01:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — expected %.4f, got %.4f" % [label, expected, actual])
