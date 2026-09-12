extends Node
## EffectStudioEnergyRenderChunkedTest — the per-edit-freeze fix (2026-08-13). The pair
## panel's §3 per-track energy bands + joint waveform used to render SYNCHRONOUSLY inside
## _render_current on every FEDS edit — three render_pair calls, 3-8 s of blocked main
## thread. They now go through a chunked queue (_energy_queue) pumped from _process, exactly
## like the ghost-length render. This guard locks:
##   (1) SCHEDULING is non-blocking — _schedule_pair_energy returns in << the render time
##       (it only enqueues; no render_pair runs on the calling thread);
##   (2) the CHUNKED assembly equals the old synchronous _render_pair_energy — same a/b
##       shared-normalized bands + peak-normalized joint (render_pair is the oracle, within
##       the SoundRenderQueue slot-rotation tolerance);
##   (3) a superseding schedule DISCARDS the in-flight render (debounce-by-supersede) — a
##       burst of edits pays for ONE render after it settles.
##
## Engine-scene test (needs the native SPU + ExMateriaEffectSfx autoload) → runs WITHOUT
## --quit-after; self-quits once done.
##
## Run:  <GODOT> --path . res://tests/EffectStudioEnergyRenderChunkedTest.tscn

const Page = preload("res://src/effects/studio/EffectStudioPage.gd")
const EffectDataClass = ExMateriaEffects.EffectData
const JSONLoader = preload("res://addons/exmateria_sound/runtime/effect_json_loader.gd")

const EFFECT := "res://assets/effects/E001"   # short pair → a quick, deterministic render
const PAIR := 0
const LEN_TOL := 3       # SoundRenderQueue slot-rotation tail wobble (shared with its test)
const ENV_TOL := 0.05
const SCHEDULE_BUDGET_MS := 50.0   # scheduling must be far under one render (seconds)

var _passed := 0
var _failed := 0


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not ExMateriaAudioEngine.ready_ok or not ExMateriaEffectSfx.ready_ok:
		print("[FAIL] audio engines not ready"); get_tree().quit(1); return

	var le = JSONLoader.load_dir(EFFECT)
	if le == null or le.feds_bank == null:
		print("[FAIL] %s has no FEDS bank" % EFFECT); get_tree().quit(1); return

	var page = Page.new()
	page._effect_data = EffectDataClass.load_from_directory(EFFECT)
	page._sound_env = {"feds_bank": le.feds_bank, "sound_containers": le.sound_containers}

	# The ORACLE: the old synchronous energy render (what the panel showed before the fix).
	var t_ref := Time.get_ticks_usec()
	var ref = page._render_pair_energy(PAIR)
	var ref_ms := (Time.get_ticks_usec() - t_ref) / 1000.0
	_assert_true(ref != null, "the synchronous reference render produced a result")
	if ref == null:
		_finish(page); return

	# (1) Scheduling the chunked render must NOT block — it only enqueues.
	var t_sched := Time.get_ticks_usec()
	page._schedule_pair_energy(PAIR)
	var sched_ms := (Time.get_ticks_usec() - t_sched) / 1000.0
	_assert_true(sched_ms < SCHEDULE_BUDGET_MS,
		"scheduling is non-blocking: %.1f ms << reference render %.1f ms" % [sched_ms, ref_ms])
	_assert_true(page._energy_pending_pair == PAIR, "the pair is marked pending after scheduling")
	_assert_true(not page._pair_energy_cache.has(PAIR), "scheduling does not synchronously fill the cache")

	# (2) Pump the queue to completion; the assembled bands equal the synchronous oracle.
	var guard := 0
	while not page._pair_energy_cache.has(PAIR) and guard < 200000:
		page._pump_energy_queue()
		guard += 1
	_assert_true(page._pair_energy_cache.has(PAIR), "pumping the queue fills the energy cache")
	if page._pair_energy_cache.has(PAIR):
		var got = page._pair_energy_cache[PAIR]
		_assert_env(got.get("a"), ref.get("a"), "chunked track-A band == synchronous oracle")
		_assert_env(got.get("b"), ref.get("b"), "chunked track-B band == synchronous oracle")
		var gj: Dictionary = got.get("joint", {})
		var rj: Dictionary = ref.get("joint", {})
		_assert_env(gj.get("samples"), rj.get("samples"), "chunked joint waveform == synchronous oracle")
	_assert_true(page._energy_pending_pair == -1, "pending clears once the render completes")

	# (3) Debounce-by-supersede: a fresh schedule mid-render discards the old partials.
	page._schedule_pair_energy(PAIR)
	page._pump_energy_queue()                 # one slice — a partial may be in flight
	page._pair_energy_cache.erase(PAIR)
	var other := PAIR + 1                       # a different VALID pair (E001 has ≥2 pairs)
	page._schedule_pair_energy(other)          # supersede
	_assert_true(page._energy_pending_pair == other, "a superseding schedule re-points the pending pair")
	_assert_true(page._energy_partials.is_empty(), "superseding drops the old render's partials")

	_finish(page)


func _finish(page) -> void:
	page.free()
	print("\n=== EffectStudioEnergyRenderChunkedTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioEnergyRenderChunkedTest"); get_tree().quit(1)
	else:
		print("[PASS] EffectStudioEnergyRenderChunkedTest"); get_tree().quit(0)


func _assert_env(a, b, label: String) -> void:
	if not (a is PackedFloat32Array) or not (b is PackedFloat32Array):
		_failed += 1; print("[FAIL] %s — a band was not rendered" % label); return
	var av: PackedFloat32Array = a
	var bv: PackedFloat32Array = b
	if absi(av.size() - bv.size()) > LEN_TOL:
		_failed += 1; print("[FAIL] %s — length %d vs %d" % [label, av.size(), bv.size()]); return
	var n := mini(av.size(), bv.size())
	if n == 0:
		# Both effectively empty (a silent track) → a match.
		if av.size() == bv.size(): _passed += 1
		else: _failed += 1; print("[FAIL] %s — one empty, one not" % label)
		return
	var dev := 0.0
	for i in range(n):
		dev += absf(av[i] - bv[i])
	if dev / float(n) <= ENV_TOL:
		_passed += 1
	else:
		_failed += 1; print("[FAIL] %s — mean dev %.4f > %.4f" % [label, dev / float(n), ENV_TOL])


func _assert_true(cond: bool, label: String) -> void:
	if cond: _passed += 1
	else: _failed += 1; print("[FAIL] %s" % label)
