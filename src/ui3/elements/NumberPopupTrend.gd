class_name NumberPopupTrend
extends RefCounted
## ROM-faithful "trending" step machine for the floating damage/status number
## popup (DAMAGE_NUMBER_DISPLAY_INVESTIGATION.md, Round 4 / 5 / 5.2).
##
## FFT grows the number from a per-digit Q12 scale ramp the ROM ships
## (assets/sprites/number_popup_trend.json), NOT a wall-clock tween. A single
## integer PHASE counter (unit+0x2c2), advancing +1 per rendered frame at 60 Hz
## (the same vblanks-per-tick divider as the cursor bob, ADR-0046), drives the
## whole lifecycle:
##   grow  [0..20]  — each digit scales along one shared 9-step ramp
##                    (0.30 -> 1.5 overshoot -> 1.0), staggered right-to-left so
##                    the ones reveals first, then tens, then hundreds.
##   steady[21..49] — all revealed digits held at full size.
##   fade  [50..60] — the primitive switches opaque -> additive AND the palette
##                    ramps toward black (-0x1f/channel/frame) = fade to nothing.
##   teardown 61    — the popup is freed.
##
## The scale is a SINGLE canonical ramp applied per digit at a staggered start
## phase (`canonical_ramp[phase - stagger]`); before its stagger a digit is
## scale 0 (drawn nothing), after the ramp it holds full size. This exactly
## reproduces the pre-staggered `scale_by_phase_q12.{ones,tens,hundreds}` the
## asset also carries (NumberPopupTrendTest guards the equivalence).
##
## These queries are PURE (digit_index, phase -> Q12 scale / band / brightness).
## The owning node (DamageNumber3D) holds the integer phase counter and applies
## the scale about a shared right-edge anchor; this resource never holds state.
##
## Vault: [[Damage Number Popup System]]

const DEFAULT_JSON := "res://assets/sprites/number_popup_trend.json"

var q12_one: int = 4096                          ## Q12 fixed-point unit (== 1.0)
var canonical_ramp: Array[int] = []              ## the 9-step grow curve (Q12)
var grow_band: Vector2i = Vector2i(0, 20)        ## [first, last] phase inclusive
var steady_band: Vector2i = Vector2i(21, 49)
var fade_band: Vector2i = Vector2i(50, 60)
var teardown_phase: int = 61
var fade_channel_delta: int = -31                ## palette RGB step/frame (toward black)
var fade_switch_phase: int = 50                  ## opaque -> additive at 0x32

# Right-to-left reveal: the phase each place-column starts its ramp. ones=0th
# place (rightmost). Higher places extrapolate the +5 tail of {1,7,12}.
var _stagger: Array[int] = [1, 7, 12]


func _init(json_path: String = DEFAULT_JSON) -> void:
	load_asset(json_path)


func load_asset(json_path: String) -> bool:
	if not FileAccess.file_exists(json_path):
		push_error("NumberPopupTrend: missing asset %s" % json_path)
		return false
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(json_path)) != OK:
		push_error("NumberPopupTrend: JSON parse error in %s" % json_path)
		return false
	var data: Dictionary = json.data
	if data.get("format", "") != "number_popup_trend":
		push_error("NumberPopupTrend: %s is not a number_popup_trend asset" % json_path)
		return false

	q12_one = int(data.get("q12_one", q12_one))

	var grow: Dictionary = data.get("grow", {})
	canonical_ramp = _to_int_array(grow.get("canonical_ramp_q12", []))
	var stg: Dictionary = grow.get("reveal_stagger_phase", {})
	_stagger = [int(stg.get("ones", 1)), int(stg.get("tens", 7)), int(stg.get("hundreds", 12))]

	var bands: Dictionary = data.get("phase_bands", {})
	grow_band = _to_band(bands.get("grow", [0, 20]))
	steady_band = _to_band(bands.get("steady", [21, 49]))
	fade_band = _to_band(bands.get("fade", [50, 60]))
	teardown_phase = int(bands.get("teardown", teardown_phase))

	var fade: Dictionary = data.get("fade", {})
	fade_channel_delta = int(fade.get("per_channel_delta", fade_channel_delta))
	var blend: Dictionary = fade.get("blend", {})
	fade_switch_phase = _parse_hex(blend.get("switch_at_phase", "0x32"), fade_band.x)
	return not canonical_ramp.is_empty()


## Q12 scale (0..q12_one, but the overshoot exceeds q12_one) for place column
## `digit_index` (0 = ones/rightmost) at integer `phase`. Before the column's
## stagger it is 0 (draw nothing); after its 9-step ramp it holds full size.
func scale_q12(digit_index: int, phase: int) -> int:
	var local := phase - _stagger_for(digit_index)
	if local < 0:
		return 0
	if local >= canonical_ramp.size():
		return q12_one
	return canonical_ramp[local]


## Float multiplier for `digit_index` at `phase` (scale_q12 / q12_one).
func scale_f(digit_index: int, phase: int) -> float:
	if q12_one == 0:
		return 0.0
	return float(scale_q12(digit_index, phase)) / float(q12_one)


## Lifecycle band owning `phase`: &"grow" / &"steady" / &"fade" / &"teardown".
func band_for(phase: int) -> StringName:
	if phase >= teardown_phase:
		return &"teardown"
	if phase >= fade_band.x:
		return &"fade"
	if phase >= steady_band.x:
		return &"steady"
	return &"grow"


## True once the popup has run past its last drawn phase and should be freed.
func is_done(phase: int) -> bool:
	return phase >= teardown_phase


## True in the fade band, where the primitive is additive and darkening.
func is_fading(phase: int) -> bool:
	return phase >= fade_switch_phase and phase < teardown_phase


## Colour brightness multiplier (1 -> 0) as the fade band ramps the palette to
## black at |fade_channel_delta| per frame (255-based). 1.0 before the fade
## switch; under the additive blend, brightness 0 adds nothing = invisible.
func fade_brightness(phase: int) -> float:
	if phase < fade_switch_phase:
		return 1.0
	var frames_in := phase - fade_switch_phase
	var b := 1.0 - float(absi(fade_channel_delta)) * float(frames_in) / 255.0
	return clampf(b, 0.0, 1.0)


func _stagger_for(digit_index: int) -> int:
	if digit_index < 0:
		return 0
	if digit_index < _stagger.size():
		return _stagger[digit_index]
	# Places beyond hundreds extrapolate the +5 tail of {1,7,12}. FFT damage is
	# almost always <= 3 digits, so this is a graceful fallback, not ROM-pinned.
	return _stagger[_stagger.size() - 1] + 5 * (digit_index - (_stagger.size() - 1))


func _to_int_array(arr: Array) -> Array[int]:
	var out: Array[int] = []
	for v in arr:
		out.append(int(v))
	return out


func _to_band(arr: Variant) -> Vector2i:
	if arr is Array and arr.size() >= 2:
		return Vector2i(int(arr[0]), int(arr[1]))
	return Vector2i(0, 0)


func _parse_hex(v: Variant, fallback: int) -> int:
	var s := str(v)
	if s.begins_with("0x") or s.begins_with("0X"):
		return s.hex_to_int()
	if s.is_valid_int():
		return int(s)
	return fallback
