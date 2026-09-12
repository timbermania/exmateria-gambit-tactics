extends Node3D

## Damage-number trending integration test — real DamageNumber3D on the real
## shader path (opaque + additive twin), driven deterministically by pumping
## 60 Hz frames. Complements the pure NumberPopupTrendTest: this proves the node
## wires the ROM ramp to actual per-digit MeshInstance3D scales, swaps to the
## additive shader in the fade band, and frees itself at teardown — headful, so
## a shader that fails to compile surfaces here.
##
## Uses a 3-digit number ("777") so all three place columns exercise the R->L
## reveal. Drives DamageNumber3D._process(1/60) directly (engine ticking is off)
## so phases advance one-per-call, independent of wall-clock frame timing.

const DamageNumber3DClass = preload("res://src/ui3/elements/DamageNumber3D.gd")
const NumberPopupTrend = preload("res://src/ui3/elements/NumberPopupTrend.gd")

var _failed := false


func _fail(msg: String) -> void:
	print("[FAIL] %s" % msg)
	_failed = true


func _digit_scale(number: Node, place: int) -> float:
	# Read the per-digit MeshInstance3D scale for a place column (0 = ones).
	for d in number._digits:
		if d["place"] == place:
			return d["inst"].scale.x
	return -1.0


func _ready() -> void:
	await _run()
	if _failed:
		print("[FAIL] DamageNumberTrend test")
	else:
		print("[PASS] DamageNumberTrend: per-digit ramp/reveal, additive-fade swap, teardown (headful)")
	get_tree().quit()


func _run() -> void:
	var trend = NumberPopupTrend.new()
	var number: Node3D = DamageNumber3DClass.new()
	add_child(number)
	number.setup(777, DamageNumber3DClass.Kind.DAMAGE, false)
	number.set_process(false)   # engine ticking off; we pump phases by hand
	await get_tree().process_frame

	if number._digits.size() != 3:
		_fail("expected 3 digit meshes for '777', got %d" % number._digits.size())
		return

	# DAMAGE lights digits through the ROM number CLUT (0x7d7c), not a flat tint.
	var mat0: ShaderMaterial = number._digits[0]["mat"]
	if not bool(mat0.get_shader_parameter("use_palette")):
		_fail("DAMAGE number should use the CLUT palette, not a flat tint")
	if mat0.get_shader_parameter("palette_tex") == null:
		_fail("DAMAGE number has no palette_tex bound")

	var dt := 1.0 / 60.0
	var ones_peak := 0.0
	var reveal_ok := false      # saw ones visible while hundreds still hidden
	var saw_additive := false
	var freed := false

	# Pump through the whole lifecycle (grow 0..20, steady 21..49, fade 50..60,
	# teardown 61). 70 frames covers it with margin.
	for _f in range(70):
		if not is_instance_valid(number) or number.is_queued_for_deletion():
			freed = true
			break
		number._process(dt)
		if not is_instance_valid(number) or number.is_queued_for_deletion():
			freed = true
			break
		var phase: int = number._phase
		var ones := _digit_scale(number, 0)
		var hundreds := _digit_scale(number, 2)
		ones_peak = maxf(ones_peak, ones)
		# Right-to-left reveal: early on, the ones is growing while the hundreds
		# place is still collapsed on the anchor (scale 0).
		if phase >= 2 and phase <= 6 and ones > 0.0 and hundreds == 0.0:
			reveal_ok = true
		if number._in_fade:
			saw_additive = true

	# 1. Overshoot: the ones column peaks at ~1.5x (Q12 6144) during grow.
	if ones_peak < 1.49:
		_fail("ones column never reached the 1.5 overshoot (peak %f)" % ones_peak)

	# 2. Right-to-left reveal happened.
	if not reveal_ok:
		_fail("never observed ones-visible-while-hundreds-hidden (R->L reveal)")

	# 3. The fade band swapped to the additive twin shader.
	if not saw_additive:
		_fail("never entered the additive fade band")
	elif is_instance_valid(number):
		# EITHER additive twin is correct. DamageNumber3D picks the fold variant whenever
		# the engine-fold compositor is driving the camera and the plain one otherwise
		# (`Fold.shader(SHADER_ADDITIVE_FOLD, SHADER_ADDITIVE)` — DamageNumber3D.fade_shader).
		# This assertion predates the fold variant and named only the plain path, so under
		# the 4.8 compositor fork — where the autopilot is ACTIVE for every scene — it
		# failed against a material that was on an additive shader the whole time.
		var additive_shaders := [DamageNumber3DClass.SHADER_ADDITIVE,
			DamageNumber3DClass.SHADER_ADDITIVE_FOLD]
		for d in number._digits:
			var sh: Shader = d["mat"].shader
			if not additive_shaders.has(sh):
				_fail("fade digit material not on either additive shader (%s)"
					% [sh.resource_path if sh != null else "<null>"])
				break

	# 4. Teardown frees the popup.
	if not freed:
		_fail("popup did not free itself at teardown (phase %d)" % (number._phase if is_instance_valid(number) else -1))
