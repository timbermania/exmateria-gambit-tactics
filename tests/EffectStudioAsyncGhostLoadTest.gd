extends Node
## EffectStudioAsyncGhostLoadTest — the picker-freeze fix's page-side half.
##
## _load_effect used to render every firing sound offline through the SPU
## SYNCHRONOUSLY (0.7–6.7 s main-thread block per pick). The fix: an IN-TREE page
## loads instantly with NO ghost bars (a supported degenerate state), then the
## SoundRenderQueue fills the ghost/energy maps across idle frames and each landing
## ghost merges through _rebuild_score — the transport-preserving reproject — so the
## author's place is undisturbed. The VALUES must equal the old sync projection;
## only WHEN they arrive changes.
##
## Also guards the session render cache (slice 3): revisiting an effect seeds its
## ghosts from cache instantly, and a container edit that retargets a sound's
## resolved pair drops the stale cache entry.
##
## Engine-scene test (needs the SPU + ExMateriaEffectSfx autoload) → self-quits.
## Run:  <GODOT> --path . res://tests/EffectStudioAsyncGhostLoadTest.tscn

const EffectData = ExMateriaEffects.EffectData

const PageClass = preload("res://src/effects/studio/EffectStudioPage.gd")
const Projector = preload("res://src/effects/studio/SoundGhostProjector.gd")

const EFFECT := "res://assets/effects/E317"
const LOAD_BLOCK_BUDGET_MS := 500
const FILL_TIMEOUT_FRAMES := 3000

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	if not ExMateriaAudioEngine.ready_ok or not ExMateriaEffectSfx.ready_ok:
		print("[FAIL] audio engines not ready")
		get_tree().quit(1)
		return

	var page = PageClass.new()
	page.size = Vector2(1200, 700)
	add_child(page)   # IN TREE — the async path under test
	await get_tree().process_frame

	var sids: Array = await _test_load_is_instant_and_ghosts_fill_in_late(page)
	if not sids.is_empty():
		await _test_revisit_seeds_ghosts_from_cache_instantly(page)
	_test_reproject_sound_id_consults_the_cache(page)
	_test_container_edit_drops_the_stale_cache_entry(page)

	page.queue_free()
	print("\n=== EffectStudioAsyncGhostLoadTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioAsyncGhostLoadTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioAsyncGhostLoadTest")
		get_tree().quit(0)


## The core fix: an in-tree _load_effect returns inside the interaction budget with
## the score built and NO ghosts yet; the ghosts then land across idle frames, equal
## to the sync projection, WITHOUT resetting the author's playhead. Returns the
## firing sids (empty on abort).
func _test_load_is_instant_and_ghosts_fill_in_late(page) -> Array:
	# The oracle: what the old sync path produced for this effect (rendered here,
	# independently, through the projector itself).
	var effect_data = EffectData.load_from_directory(EFFECT)
	var sids: Array = Projector.firing_sound_ids(effect_data.sound)
	if sids.is_empty():
		print("[FAIL] %s has no firing sound_ids" % EFFECT)
		_failed += 1
		return []
	var loaded = preload("res://addons/exmateria_sound/runtime/effect_json_loader.gd").load_dir(EFFECT)
	ExMateriaEffectSfx.capture_mode = true
	var oracle: Dictionary = Projector.sound_projection(
		ExMateriaEffectSfx, effect_data.sound, loaded.sound_containers, loaded.feds_bank)
	ExMateriaEffectSfx.capture_mode = false

	var t0 := Time.get_ticks_msec()
	page._load_effect(EFFECT)
	var blocked := Time.get_ticks_msec() - t0
	_assert_true(blocked < LOAD_BLOCK_BUDGET_MS,
		"_load_effect returns inside the interaction budget (blocked %d ms)" % blocked)
	_assert_true(page._ghost_by_sound_id.is_empty(),
		"a first visit starts with no ghost bars (they fill in late)")
	_assert_true(not page._timeline._score.is_empty() if page._timeline._score is Dictionary else true,
		"the score is built and shown immediately")

	# Park the playhead somewhere non-zero: the late merges must not move it.
	page._timeline.set_playhead(7)

	var frames := 0
	while page._ghost_by_sound_id.size() < sids.size() and frames < FILL_TIMEOUT_FRAMES:
		await get_tree().process_frame
		frames += 1
	_assert_eq(page._ghost_by_sound_id.size(), sids.size(),
		"every firing sound's ghost lands within the fill window")
	# Tolerant match: the engine's slot-rotation tail wobble (±1-2 frames, a
	# pre-existing property of the sync path too) — see SoundRenderQueueTest header.
	var all_match := true
	for sid in sids:
		var pl: int = int(page._ghost_by_sound_id.get(sid, -100))
		var ol: int = int(oracle["ghost"].get(sid, -200))
		if absi(pl - ol) > 3:
			all_match = false
			print("    [diff] sid %d: async length %d vs sync %d" % [sid, pl, ol])
		if page._energy_by_sound_id.get(sid, PackedFloat32Array()).size() != pl:
			all_match = false
	_assert_true(all_match, "the async ghost lengths match the sync projection's (and each envelope spans its ghost)")
	_assert_eq(page._timeline.get_playhead(), 7,
		"late ghost merges preserve the author's playhead (reproject, not reload)")
	return sids


## Slice 3 — the session cache: loading another effect and coming BACK seeds the
## ghost maps synchronously from cache (no waiting, no re-render).
func _test_revisit_seeds_ghosts_from_cache_instantly(page) -> void:
	var expected: Dictionary = page._ghost_by_sound_id.duplicate()
	# Switch away (any other extracted effect will do; E317 default always exists).
	var other := ""
	for d in page._effect_dirs:
		if String(d) != EFFECT:
			other = String(d)
			break
	if other == "":
		print("[SKIP] only one effect extracted — revisit test skipped")
		return
	page._load_effect(other)
	page._load_effect(EFFECT)   # revisit — NO awaited frames on purpose
	_assert_eq(page._ghost_by_sound_id, expected,
		"a revisit seeds every ghost from the session cache instantly")


## The debounced edit-path render (_reproject_sound_id) reads the session cache too:
## a sid already rendered for this effect_dir seeds the maps WITHOUT an SPU render.
func _test_reproject_sound_id_consults_the_cache(page) -> void:
	page._ghost_by_sound_id.erase(19)
	page._energy_by_sound_id.erase(19)
	page._ghost_render_cache[page._ghost_cache_key(EFFECT, 19)] = {
		"length": 21, "energy": PackedFloat32Array([1.0])}
	page._reproject_sound_id(19)
	_assert_eq(int(page._ghost_by_sound_id.get(19, -1)), 21,
		"_reproject_sound_id seeds a cached sid from the session cache (no render)")
	page._ghost_by_sound_id.erase(19)
	page._energy_by_sound_id.erase(19)
	page._ghost_render_cache.erase(page._ghost_cache_key(EFFECT, 19))


## …and a sid it really renders lands in the cache too (chunked, pumped by _process —
## the old synchronous assert is gone with the dedicated capture SPU design).


## A container edit that MOVES the sound's resolved first fire must drop the cache
## entry along with the live map (both are stale for the new pair) — otherwise a
## revisit would resurrect the old sound's ghost.
func _test_container_edit_drops_the_stale_cache_entry(page) -> void:
	var host := _FakeEditHost.new()
	host.bind(page._effect_data)
	page._host = host
	var key: String = page._ghost_cache_key(EFFECT, 2)
	page._ghost_render_cache[key] = {"length": 30, "energy": PackedFloat32Array()}
	# Retarget container 0's first fire to a far-off id: the resolved pair moves, so
	# both the live ghost and the cached render are stale.
	page._apply_edit({"channel": "sound_container", "index": 0, "field": "id_a"}, 200)
	_assert_true(not page._ghost_render_cache.has(key),
		"a first-fire-moving container edit erases the (effect_dir, sid) cache entry")
	page._host = null


## A host double that applies the edit through the REAL EffectEditSession, so the
## container doc the page re-resolves is genuinely mutated (same as EffectStudioSoundEditTest).
class _FakeEditHost extends RefCounted:
	var _session = null
	func bind(ed) -> void:
		_session = load("res://src/effects/studio/EffectEditSession.gd").new(ed)
	func studio_apply_edit(ref: Dictionary, raw, defer_refold = false) -> Dictionary:
		return _session.apply_edit(ref, raw) if _session != null else {}


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
