extends Node
## EffectPickerResponsivenessTest — the picker-freeze regression guard (promoted from
## the diagnosing-bugs harness that caught it). Picking an E### effect used to block
## the main thread 0.7-6.7 s while _load_effect rendered every firing sound offline
## through the SPU; the fix (SoundRenderQueue + the session render cache) makes the
## pick instant and fills the ghost bars across idle frames.
##
## Drives the real EffectViewer scene and times the two interaction phases:
##   A. opening the E### OptionButton popup (~400 items)
##   B. item_selected → _load_effect for the measured-worst effects
##      (E065 was 6.7 s sync; E072 5.9 s; E329/E335 1.5-1.9 s)
## Fails if any single interaction blocks the main thread > THRESHOLD_MS. Then waits
## for the last pick's chunked renders to drain and asserts its ghosts actually
## arrived — instant-but-never-filled would be a silent regression of the bars.
##
## Run:  <GODOT> --path . --quit-after 3000 res://tests/EffectPickerResponsivenessTest.tscn

const THRESHOLD_MS := 500
const PICK_SUFFIXES := ["E329", "E335", "E072", "E065"]
const FILL_TIMEOUT_FRAMES := 3000

var _failed := false


func _ready() -> void:
	print("[pickerperf] boot: instantiating EffectViewer")
	var t0 := Time.get_ticks_msec()
	var scn = load("res://assets/scenes/EffectViewer.tscn").instantiate()
	add_child(scn)
	await _frames(30)
	print("[pickerperf] boot done in %d ms (includes default E317 load)" % (Time.get_ticks_msec() - t0))

	var page = scn._studio_page
	if page == null or page._picker == null:
		print("[pickerperf] FATAL: no studio page / picker")
		get_tree().quit(1)
		return

	# --- Phase A: open the popup (what a left-click does first) ---
	var ta := Time.get_ticks_msec()
	page._picker.show_popup()
	var blocked_a := Time.get_ticks_msec() - ta
	await get_tree().process_frame
	_check(blocked_a, "popup-open call")
	page._picker.get_popup().hide()
	await _frames(5)

	# --- Phase B: pick the measured-worst effects ---
	var last_picked := ""
	for suffix in PICK_SUFFIXES:
		var idx := -1
		for i in range(page._effect_dirs.size()):
			if String(page._effect_dirs[i]).ends_with(suffix):
				idx = i
				break
		if idx < 0:
			print("[pickerperf] %s not extracted, skipping" % suffix)
			continue
		var tb := Time.get_ticks_msec()
		page._picker.item_selected.emit(idx)
		var blocked_b := Time.get_ticks_msec() - tb
		await get_tree().process_frame
		print("[pickerperf] %s blocked main thread %d ms" % [suffix, blocked_b])
		_check(blocked_b, "load %s" % suffix)
		last_picked = suffix
		await _frames(5)

	# --- The other half of the contract: the ghosts DO arrive (async, off-click) ---
	if last_picked != "":
		var frames := 0
		while not page._ghost_queue.is_idle() and frames < FILL_TIMEOUT_FRAMES:
			await get_tree().process_frame
			frames += 1
		if not page._ghost_queue.is_idle():
			_failed = true
			print("[pickerperf] RED: %s ghost renders never drained (%d frames)" % [last_picked, frames])
		elif page._ghost_by_sound_id.is_empty():
			_failed = true
			print("[pickerperf] RED: %s drained but produced no ghosts" % last_picked)
		else:
			print("[pickerperf] %s ghosts filled in: %d sounds, %d frames after pick"
				% [last_picked, page._ghost_by_sound_id.size(), frames])

	print("[pickerperf] %s" % ("FAIL — an interaction exceeded %d ms (or ghosts never filled)" % THRESHOLD_MS
		if _failed else "PASS — picks instant, ghosts filled"))
	if _failed:
		print("[FAIL] EffectPickerResponsivenessTest")
	else:
		print("[PASS] EffectPickerResponsivenessTest")
	get_tree().quit(1 if _failed else 0)


func _check(ms: int, label: String) -> void:
	if ms > THRESHOLD_MS:
		_failed = true
		print("[pickerperf] RED: %s blocked %d ms (> %d)" % [label, ms, THRESHOLD_MS])


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
