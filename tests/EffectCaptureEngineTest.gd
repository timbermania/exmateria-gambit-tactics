extends Node
## EffectCaptureEngineTest — the DEDICATED offline-capture SPU (the "everything as we go" fix).
## The studio's ghost/energy renders used to run on the shared live-audio ExMateriaEffectSfx, whose
## capture_mode PARKS the producer thread for the whole render → live audio dead for seconds
## ("stops playing until I change effects"). A dedicated capture engine (ExMateriaEffectSfx
## .init_as_capture) renders on its OWN SPU, so it never touches live playback. This guard locks:
##   (1) PARITY — a capture-engine render_pair equals the live-engine render_pair (same waveset,
##       same code, own SPU), within the SoundRenderQueue slot-rotation tolerance;
##   (2) ISOLATION — rendering on the capture engine does NOT flip the live autoload's
##       capture_mode (so the live producer keeps running: audio never parks during a capture).
##
## Engine-scene test (needs the native SPU + ExMateriaAudioEngine/ExMateriaEffectSfx autoloads) → runs
## WITHOUT --quit-after; self-quits once done.
##
## Run:  <GODOT> --path . res://tests/EffectCaptureEngineTest.tscn

const Projector = preload("res://src/effects/studio/SoundGhostProjector.gd")
const EffectSfxEngineScript = preload("res://addons/exmateria_sound/runtime/effect_sfx_engine.gd")
const EffectJSONLoaderClass = preload("res://addons/exmateria_sound/runtime/effect_json_loader.gd")

const EFFECT := "res://assets/effects/E065"   # Shiva — several pairs, real ring-out
const LEN_TOL := 4        # slot-rotation tail wobble (a hair looser than SoundRenderQueueTest's 3)
const ENV_TOL := 0.06

var _passed := 0
var _failed := 0


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not ExMateriaAudioEngine.ready_ok or not ExMateriaEffectSfx.ready_ok:
		print("[FAIL] audio engines not ready"); get_tree().quit(1); return

	var le = EffectJSONLoaderClass.load_dir(EFFECT)
	if le == null or le.feds_bank == null:
		print("[FAIL] %s has no FEDS bank" % EFFECT); get_tree().quit(1); return
	var fb = le.feds_bank

	# The dedicated capture engine — bare .new(), NOT added to the tree, capture-only.
	var ce = EffectSfxEngineScript.new()
	var ok: bool = ce.init_as_capture()
	_assert_true(ok, "init_as_capture() succeeds (own SPU, no producer)")
	_assert_true(ce.ready_ok, "the capture engine reports ready")
	if not ok:
		_finish(ce); return

	# ISOLATION: live producer running (capture_mode false). A capture render must not park it.
	ExMateriaEffectSfx.capture_mode = false

	var n := mini(fb.num_pairs, 3)
	for pair_idx in range(n):
		var sid := pair_idx + 1
		# Oracle on the LIVE engine (parks its producer for the render — that's the old path).
		ExMateriaEffectSfx.capture_mode = true
		var oracle: Dictionary = Projector.render_pair(ExMateriaEffectSfx, fb, pair_idx, sid)
		ExMateriaEffectSfx.capture_mode = false
		# The same render on the DEDICATED capture engine, WHILE live capture_mode is false.
		var got: Dictionary = Projector.render_pair(ce, fb, pair_idx, sid)
		_assert_true(not ExMateriaEffectSfx.capture_mode,
			"pair %d: a capture-engine render leaves the LIVE producer un-parked" % pair_idx)
		_assert_match(got, oracle, "pair %d: capture render == live render (parity)" % pair_idx)

	_finish(ce)


func _finish(ce) -> void:
	if ce != null:
		ce.free()
	print("\n=== EffectCaptureEngineTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectCaptureEngineTest"); get_tree().quit(1)
	else:
		print("[PASS] EffectCaptureEngineTest"); get_tree().quit(0)


func _assert_match(got: Dictionary, oracle: Dictionary, label: String) -> void:
	var gl := int(got.get("length", -1))
	var ol := int(oracle.get("length", -2))
	if absi(gl - ol) > LEN_TOL:
		_failed += 1; print("[FAIL] %s — length %d vs %d" % [label, gl, ol]); return
	var a: PackedFloat32Array = got.get("energy", PackedFloat32Array())
	var b: PackedFloat32Array = oracle.get("energy", PackedFloat32Array())
	var m := mini(a.size(), b.size())
	if m == 0:
		if a.size() == b.size(): _passed += 1
		else: _failed += 1; print("[FAIL] %s — one empty" % label)
		return
	var dev := 0.0
	for i in range(m):
		dev += absf(a[i] - b[i])
	if dev / float(m) <= ENV_TOL:
		_passed += 1
	else:
		_failed += 1; print("[FAIL] %s — mean dev %.4f > %.4f" % [label, dev / float(m), ENV_TOL])


func _assert_true(cond: bool, label: String) -> void:
	if cond: _passed += 1
	else: _failed += 1; print("[FAIL] %s" % label)
