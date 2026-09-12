extends Node

## NumberPopupTrend phase-machine test — pure GDScript, no rendering.
##
## Guards the ROM-faithful damage/status number "trending" step machine
## (DAMAGE_NUMBER_DISPLAY_INVESTIGATION.md, Round 4/5/5.2). The grow is one
## canonical 9-step Q12 ramp (0.30 -> 1.5 overshoot -> 1.0) applied per digit at
## a staggered start phase; the asset also ships the PRE-STAGGERED per-place
## tables (scale_by_phase_q12.{ones,tens,hundreds}). This asserts the generalized
## `scale_q12(place, phase)` reproduces those tables byte-for-byte, plus the
## lifecycle bands, the R->L reveal order, the fade brightness ramp, and JSON
## parity for the constants the port depends on.

const NumberPopupTrend = preload("res://src/ui3/elements/NumberPopupTrend.gd")
const ASSET := "res://assets/sprites/number_popup_trend.json"

var _failed := false


func _fail(msg: String) -> void:
	print("[FAIL] %s" % msg)
	_failed = true


func _ready() -> void:
	var trend = NumberPopupTrend.new()

	# The committed asset's pre-staggered per-place tables — the ground truth the
	# generalized ramp must reproduce.
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(ASSET))
	if typeof(raw) != TYPE_DICTIONARY:
		_fail("could not load %s" % ASSET)
		_finish()
		return
	var by_phase: Dictionary = raw["grow"]["scale_by_phase_q12"]
	var places := {0: "ones", 1: "tens", 2: "hundreds"}

	# 1. scale_q12(place, phase) == scale_by_phase_q12[place][phase] for the whole
	#    grow window (phase 0..20), every place. This is the core equivalence.
	for place in places:
		var table: Array = by_phase[places[place]]
		for phase in table.size():
			var got := trend.scale_q12(place, phase)
			var want := int(table[phase])
			if got != want:
				_fail("scale_q12(%s, %d) = %d, expected %d" % [places[place], phase, got, want])

	# 2. The overshoot peak is 1.5 (6144 Q12), reached by the ones at phase 5.
	if trend.scale_q12(0, 5) != 6144:
		_fail("ones overshoot peak = %d, expected 6144 (1.5x)" % trend.scale_q12(0, 5))
	if not is_equal_approx(trend.scale_f(0, 5), 1.5):
		_fail("ones scale_f at peak = %f, expected 1.5" % trend.scale_f(0, 5))

	# 3. Right-to-left reveal: before its stagger a place is scale 0 (hidden). The
	#    tens (place 1) is 0 through phase 6, nonzero from phase 7.
	if trend.scale_q12(1, 6) != 0:
		_fail("tens should be hidden (0) at phase 6, got %d" % trend.scale_q12(1, 6))
	if trend.scale_q12(1, 7) == 0:
		_fail("tens should reveal at phase 7, got 0")
	# Hundreds (place 2) hidden through phase 11, revealed at 12.
	if trend.scale_q12(2, 11) != 0:
		_fail("hundreds should be hidden at phase 11, got %d" % trend.scale_q12(2, 11))
	if trend.scale_q12(2, 12) == 0:
		_fail("hundreds should reveal at phase 12, got 0")

	# 4. All three places reach full size (4096) by the end of grow (phase 20) and
	#    hold it through steady/fade.
	for place in places:
		if trend.scale_q12(place, 20) != 4096:
			_fail("%s not full at phase 20 (got %d)" % [places[place], trend.scale_q12(place, 20)])
		if trend.scale_q12(place, 40) != 4096:
			_fail("%s not held full in steady phase 40 (got %d)" % [places[place], trend.scale_q12(place, 40)])

	# 5. Lifecycle bands: exact boundaries from phase_bands.
	var band_cases := {
		0: &"grow", 20: &"grow",
		21: &"steady", 49: &"steady",
		50: &"fade", 60: &"fade",
		61: &"teardown", 200: &"teardown",
	}
	for phase in band_cases:
		if trend.band_for(phase) != band_cases[phase]:
			_fail("band_for(%d) = %s, expected %s" % [phase, trend.band_for(phase), band_cases[phase]])

	# 6. is_done only past teardown.
	if trend.is_done(60):
		_fail("is_done(60) should be false (still fading)")
	if not trend.is_done(61):
		_fail("is_done(61) should be true (teardown)")

	# 7. Fade brightness: full (1.0) before the 0x32 switch, decreasing across the
	#    fade band, fully black by the end.
	if not is_equal_approx(trend.fade_brightness(49), 1.0):
		_fail("fade_brightness(49) = %f, expected 1.0 (pre-switch)" % trend.fade_brightness(49))
	if not is_equal_approx(trend.fade_brightness(50), 1.0):
		_fail("fade_brightness(50) = %f, expected 1.0 (switch frame)" % trend.fade_brightness(50))
	if trend.fade_brightness(55) >= trend.fade_brightness(51):
		_fail("fade_brightness should decrease across the fade band")
	if trend.fade_brightness(60) > 0.0:
		_fail("fade_brightness(60) = %f, expected 0.0 (black)" % trend.fade_brightness(60))

	# 8. JSON parity for the constants the port depends on.
	if trend.q12_one != 4096:
		_fail("q12_one = %d, expected 4096" % trend.q12_one)
	if trend.canonical_ramp != [1228, 2457, 3685, 4913, 6144, 4913, 3685, 3900, 4096]:
		_fail("canonical_ramp drifted: %s" % str(trend.canonical_ramp))
	if trend.fade_channel_delta != -31:
		_fail("fade_channel_delta = %d, expected -31" % trend.fade_channel_delta)
	if trend.fade_switch_phase != 50:
		_fail("fade_switch_phase = %d, expected 50 (0x32)" % trend.fade_switch_phase)

	_finish()


func _finish() -> void:
	if _failed:
		print("[FAIL] NumberPopupTrend phase-machine test")
	else:
		print("[PASS] NumberPopupTrend: per-place ramp==asset, overshoot 1.5, R->L reveal, bands, fade->black, JSON parity")
	get_tree().quit()
