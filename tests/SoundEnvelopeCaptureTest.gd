extends Node
## SoundEnvelopeCaptureTest — the ADR-0085 sound projection, derived from the REAL
## rendered sound rather than a tick sum. SoundGhostProjector resolves a timeline
## sound_id to its FEDS pair, synthesises that pair OFFLINE through the actual SPU
## (ExMateriaEffectSfx.capture_mode, deterministic PCM — no speakers) and reduces it to a
## per-frame RMS curve. From that ONE render come BOTH the ghost LENGTH (how long the
## sound stays audible) and its peak-normalised energy envelope, so the bar, the swell,
## and what you hear always agree. The load-bearing property this guards: the render
## length is the AUDIBLE length — an SFX whose short note fires a long one-shot sample
## is covered for its whole ring-out, not cut off at the note (the frame-35 bug).
##
## Engine-scene test (needs the native SPU + ExMateriaEffectSfx autoload) → runs WITHOUT
## --quit-after; self-quits once the autoloads are ready.
##
## Run:  <GODOT> --path . res://tests/SoundEnvelopeCaptureTest.tscn

const EffectData = ExMateriaEffects.EffectData

const Projector = preload("res://src/effects/studio/SoundGhostProjector.gd")
const EffectJSONLoaderClass = preload("res://addons/exmateria_sound/runtime/effect_json_loader.gd")

const EFFECT := "res://assets/effects/E317"   # the frame-35 repro: sid2 note is tiny, sample long

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	if not ExMateriaAudioEngine.ready_ok or not ExMateriaEffectSfx.ready_ok:
		print("[FAIL] audio engines not ready")
		get_tree().quit(1)
		return

	var loaded = EffectJSONLoaderClass.load_dir(EFFECT)
	if loaded == null or not loaded.has_sound() or loaded.feds_bank == null:
		print("[FAIL] %s has no FEDS sound data" % EFFECT)
		get_tree().quit(1)
		return

	var effect_data = EffectData.load_from_directory(EFFECT)
	var containers = loaded.sound_containers
	var fb = loaded.feds_bank
	var sids: Array = Projector.firing_sound_ids(effect_data.sound)
	if sids.is_empty():
		print("[FAIL] %s has no firing sound_ids" % EFFECT)
		get_tree().quit(1)
		return
	# The tick projection (what the ghost bar USED to use) — for the under-count guard.
	var tick_ghost: Dictionary = Projector.ghost_map(effect_data.sound, containers, fb)

	ExMateriaEffectSfx.capture_mode = true
	_test_render_pair_measures_audible_length_and_a_normalised_curve(containers, fb, sids)
	_test_rendered_length_covers_the_full_ringout_not_the_note(containers, fb, sids, tick_ghost)
	_test_render_is_deterministic(containers, fb, sids)
	_test_out_of_range_pair_has_no_projection(fb)
	_test_sound_projection_is_consistent_ghost_and_energy(effect_data, containers, fb, sids)
	ExMateriaEffectSfx.capture_mode = false

	print("\n=== SoundEnvelopeCaptureTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] SoundEnvelopeCaptureTest")
		get_tree().quit(1)
	else:
		print("[PASS] SoundEnvelopeCaptureTest")
		get_tree().quit(0)


## render_pair returns BOTH a length (frames until silence) and a peak-normalised RMS
## envelope of exactly that length: one sample per ghost frame, loudest reads 1.0, all
## within [0,1], and a genuinely SHAPED swell (not a flat bar) — the climax cue.
func _test_render_pair_measures_audible_length_and_a_normalised_curve(containers: Dictionary, fb, sids: Array) -> void:
	var sid: int = sids[0]
	var pair: int = Projector.resolve_pair_idx(containers, sid)
	var r := Projector.render_pair(ExMateriaEffectSfx, fb, pair, sid)
	var length: int = int(r["length"])
	var env: PackedFloat32Array = r["energy"]
	_assert_true(length > 0, "a real sound has a non-zero rendered length")
	_assert_eq(env.size(), length, "the envelope has one sample per rendered frame")
	_assert_almost(_max(env), 1.0, 1e-4, "the envelope is peak-normalised to 1.0")
	_assert_true(_in_unit_range(env), "every envelope sample is within [0,1]")
	_assert_true(_min(env) < _max(env) - 0.05, "the envelope is a shaped swell, not a flat bar")


## The FIX for the frame-35 bug: the rendered length is the AUDIBLE length, far longer
## than the FEDS note ticks when a short note fires a long sample. E317 sid2's tick
## projection was ~5 frames but the sample rings for ~90; the render must cover it (a
## sound firing at f22 has to still be "under a bar" at f35, i.e. length ≥ ~13+).
func _test_rendered_length_covers_the_full_ringout_not_the_note(containers: Dictionary, fb, sids: Array, tick_ghost: Dictionary) -> void:
	var sid: int = sids[0]   # E317 sid 2
	var pair: int = Projector.resolve_pair_idx(containers, sid)
	var length: int = int(Projector.render_pair(ExMateriaEffectSfx, fb, pair, sid)["length"])
	var tick_len: int = int(tick_ghost.get(sid, 0))
	_assert_true(length >= 40,
		"E317 sid2 rings out well past its fire (>=40f), covering frame 35 (was ~5)")
	_assert_true(length > tick_len + 10,
		"the rendered length exceeds the tick projection (the under-count is fixed)")


## The projection oracle relies on capture being deterministic: same pair rendered
## twice must give identical length AND identical envelope.
func _test_render_is_deterministic(containers: Dictionary, fb, sids: Array) -> void:
	var sid: int = sids[0]
	var pair: int = Projector.resolve_pair_idx(containers, sid)
	var a := Projector.render_pair(ExMateriaEffectSfx, fb, pair, sid)
	var b := Projector.render_pair(ExMateriaEffectSfx, fb, pair, sid)
	_assert_eq(int(a["length"]), int(b["length"]), "the rendered length is deterministic")
	_assert_true(_arrays_equal(a["energy"], b["energy"]), "the rendered envelope is deterministic")


## A pair index outside the bank yields no projection (length 0, empty envelope) — a
## skip sound_id or a broken reference must not fabricate a bar or a curve.
func _test_out_of_range_pair_has_no_projection(fb) -> void:
	var r := Projector.render_pair(ExMateriaEffectSfx, fb, 9999, 2)
	_assert_eq(int(r["length"]), 0, "an out-of-range pair has zero length")
	_assert_eq(r["energy"].size(), 0, "an out-of-range pair has an empty envelope")


## sound_projection renders every firing sound_id ONCE and returns the two maps
## EffectScoreModel.build consumes. They must cover exactly the firing ids, every
## ghost length must be > 0, and each envelope length must EQUAL its ghost length —
## the consistency the single-render design guarantees (bar == swell == audible).
func _test_sound_projection_is_consistent_ghost_and_energy(effect_data, containers: Dictionary, fb, sids: Array) -> void:
	var proj: Dictionary = Projector.sound_projection(ExMateriaEffectSfx, effect_data.sound, containers, fb)
	var ghost: Dictionary = proj["ghost"]
	var energy: Dictionary = proj["energy"]
	var covered := true
	for s in sids:
		if not (ghost.has(s) and energy.has(s)):
			covered = false
	_assert_true(covered and ghost.size() == sids.size(),
		"the projection covers exactly the firing sound_ids")
	var consistent := true
	for s in sids:
		if int(ghost[s]) <= 0 or energy[s].size() != int(ghost[s]):
			consistent = false
	_assert_true(consistent,
		"every ghost length is > 0 and its envelope spans exactly that length")


# --- reductions -----------------------------------------------------------

func _max(a: PackedFloat32Array) -> float:
	var m := -1.0
	for v in a:
		if v > m:
			m = v
	return m


func _min(a: PackedFloat32Array) -> float:
	if a.is_empty():
		return 0.0
	var m := a[0]
	for v in a:
		if v < m:
			m = v
	return m


func _in_unit_range(a: PackedFloat32Array) -> bool:
	for v in a:
		if v < 0.0 or v > 1.0001:
			return false
	return true


func _arrays_equal(a: PackedFloat32Array, b: PackedFloat32Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if absf(a[i] - b[i]) > 1e-9:
			return false
	return true


# --- asserts --------------------------------------------------------------

func _assert_almost(actual: float, expected: float, eps: float, label: String) -> void:
	if absf(actual - expected) <= eps:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %f, got %f" % [label, expected, actual])


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
