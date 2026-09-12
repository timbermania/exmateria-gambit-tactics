class_name AudioBusMixerDebugPanel
extends BaseDebugPanel

## Live bus mixer — the F3 AUDIO tab's proof that the game is plugged into Godot's
## mixer rather than dumping everything at `Master` (`B3` task 2, `D3` dec. 6, #385).
##
## **Why this exists as a panel and not as a test.** `AudioBusLayoutTest` proves the
## routing is *declared*; it cannot show you the routing *working*. And Godot's own
## editor mixer is no help: running the project spawns a separate process with its own
## `AudioServer`, so the editor's Audio panel meters the editor, never the game. The
## only place the running game's bus graph can be seen is inside the running game.
##
## **The rows are read from the live `AudioServer`, not from a list in this file.** If
## the layout resource fails to load, this panel shows one bus named Master and the two
## stream readouts at the bottom say `Master` — which is exactly what a broken install
## looks like. Hardcoding the four names would have drawn the answer instead of measuring
## it.
##
## **The Master fader is deliberately read-only here.** `MasterBus` keeps bus 0's fader at
## unity on purpose and rides the whole-game gain on a *pre-limiter* `AudioEffectAmplify`
## (`MasterBus.gd:87-107`): a boost on the fader lands AFTER the effect rack and clips the
## device past the -0.3 dB ceiling. The whole-game volume has its own panel; this one must
## not offer a second, wrong way to set it.
##
## A view, not an owner: every control writes to `AudioServer`, whose state is the
## committed `default_bus_layout.tres`. Nothing here holds a value of its own.

const LAYOUT_SETTING := "audio/buses/default_bus_layout"
const METER_FLOOR_DB := -60.0
const METER_CEIL_DB := 6.0
## Meter fall-off. The raw peak flickers to the floor between blocks and reads as a dead
## bus; a decay makes a playing stream legibly *held* rather than strobing.
const METER_FALL_DB_PER_SEC := 48.0
## Demo cues. Slot 31 is the one MusicPlayer's own docstring uses; the cursor blip is the
## shortest SFX in the system bank, so it spikes the SFX bus without masking the music.
const DEMO_MUSIC_SLOT := 31
const DEMO_SFX_CUE := "ui.cursor_move"

var _rows: Array[Dictionary] = []
var _levels: PackedFloat32Array = PackedFloat32Array()
var _bus_box: VBoxContainer
var _status: Label
var _music_route: Label
var _sfx_route: Label
var _music_sched: Label
var _sfx_sched: Label
var _built_for_bus_count := -1


func setup() -> void:
	panel_title = "Bus mixer (live)"
	panel_category = Category.AUDIO
	_build_ui()


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(430, 0)
	add_child(vbox)

	add_section_title(vbox, "Godot bus graph — live")
	var layout_path := str(ProjectSettings.get_setting(LAYOUT_SETTING, ""))
	add_label(vbox, "Layout: %s" % ("<none>" if layout_path == "" else layout_path))

	_bus_box = VBoxContainer.new()
	vbox.add_child(_bus_box)
	_rebuild_rows()

	add_separator(vbox)
	var btns := add_button_row(vbox)
	_add_action(btns, "▶ Music", _play_music)
	_add_action(btns, "■ Stop", _stop_music)
	_add_action(btns, "🔊 SFX cue", _fire_sfx)

	_status = add_label(vbox, "Press ▶ Music, then watch the Music meter. Mute Music: the score")
	add_label(vbox, "stops and the SFX cue still fires — that is the split, audibly.")

	add_separator(vbox)
	add_section_title(vbox, "Where each stream actually plays")
	# Read back through AudioStreamPlayer.bus, whose GETTER resolves an unknown bus name
	# to &"Master". So these two lines cannot read "Music"/"SFX" unless the layout really
	# loaded — they are a measurement, not an echo of what the code assigned.
	_music_route = add_label(vbox, "SMDPlayer (.SMD music)  →  …")
	_sfx_route = add_label(vbox, "ExMateriaEffectSfx (battle SFX)  →  …")

	add_separator(vbox)
	add_section_title(vbox, "Music scheduler (the SPU renders on the audio thread)")
	# Music is an ExMateriaSpuStream now: `_mix` renders the 24-voice SPU itself, and
	# the GDScript sequencer stages register writes into a queue ahead of the audio
	# clock (#385 tasks 1/4). The two numbers that matter here are the LEAD — how far
	# ahead of what you are hearing the sequencer has written — and `late`, which
	# counts writes the audio thread reached after their frame had already passed.
	# `late` climbing is the main thread stalling for longer than the lead; it is
	# heard as the score hesitating, not as a dropout.
	_music_sched = add_label(vbox, "…")

	add_separator(vbox)
	add_section_title(vbox, "SFX scheduler (one AudioStream per SPU unit)")
	# Effect SFX runs the same mechanism since #385 task 3, with two differences
	# worth watching separately from music.
	#
	# The LEAD is short on purpose — ~25 ms against music's second — because an SFX
	# cue stamped at frame F *sounds* at frame F, so for SFX the lead IS the input
	# latency (`D3` dec. 7). That leaves far less slack, which is why `late` is the
	# number to watch here: it counts register writes the audio thread reached after
	# their frame had passed. It found a real defect during the build — at a 12.5 ms
	# lead, one mix block is 11.6 ms and `late` ran at ~180/s.
	#
	# `streams` is one per SOUNDING unit plus the parked ones; a parked unit keeps
	# its clock running but skips the mix entirely, so `streams` counting up while
	# nothing is audible is normal, not a leak.
	_sfx_sched = add_label(vbox, "…")

	add_separator(vbox)
	add_print_values_button(vbox)
	# No set_process() here on purpose: this runs BEFORE the panel enters the tree,
	# and Node's NOTIFICATION_READY re-arms _process for any script that defines
	# one. BaseDebugPanel's visibility gate owns it (W13 / #955).


func _rebuild_rows() -> void:
	for child in _bus_box.get_children():
		child.queue_free()
	_rows.clear()
	_levels.resize(AudioServer.bus_count)
	_levels.fill(METER_FLOOR_DB)
	for i in range(AudioServer.bus_count):
		_rows.append(_build_bus_row(_bus_box, i))
	_built_for_bus_count = AudioServer.bus_count


func _build_bus_row(parent: VBoxContainer, idx: int) -> Dictionary:
	var send := str(AudioServer.get_bus_send(idx))
	var row := VBoxContainer.new()
	parent.add_child(row)

	var head := HBoxContainer.new()
	row.add_child(head)
	var title := "%s" % AudioServer.get_bus_name(idx)
	if send != "":
		title = "  ↳ %s  → %s" % [AudioServer.get_bus_name(idx), send]
	add_label(head, title, 150)
	var meter := ProgressBar.new()
	meter.min_value = METER_FLOOR_DB
	meter.max_value = 0.0
	meter.value = METER_FLOOR_DB
	meter.show_percentage = false
	meter.custom_minimum_size = Vector2(150, 12)
	head.add_child(meter)
	var peak_label := add_label(head, "—", 62)

	var ctl := HBoxContainer.new()
	row.add_child(ctl)
	add_label(ctl, "", 150)
	var fader := HSlider.new()
	fader.min_value = METER_FLOOR_DB
	fader.max_value = METER_CEIL_DB
	fader.step = 0.5
	fader.value = AudioServer.get_bus_volume_db(idx)
	fader.custom_minimum_size.x = 150
	ctl.add_child(fader)
	var fader_label := add_label(ctl, "%.1f dB" % fader.value, 62)

	if idx == 0:
		# See the class docstring: bus 0's fader stays at unity by design — the whole-game
		# gain rides a pre-limiter Amplify so the -0.3 dB HardLimiter can still catch it.
		fader.editable = false
		fader.tooltip_text = "Read-only — whole-game volume rides MasterBus's pre-limiter Amplify."
		fader_label.text = "%.1f dB (fixed)" % fader.value
	else:
		fader.value_changed.connect(func(v: float) -> void:
			AudioServer.set_bus_volume_db(idx, v)
			fader_label.text = "%.1f dB" % v)

	# tune-exempt: bus mute/solo is AudioServer state persisted in default_bus_layout.tres,
	# not a Tune slug — this panel is a view onto Godot's mixer, which owns the value.
	var mute := CheckBox.new()  # tune-exempt: AudioServer bus state, owned by the bus layout
	mute.text = "M"
	mute.button_pressed = AudioServer.is_bus_mute(idx)
	mute.toggled.connect(func(on: bool) -> void: AudioServer.set_bus_mute(idx, on))
	ctl.add_child(mute)

	var solo := CheckBox.new()  # tune-exempt: AudioServer bus state, owned by the bus layout
	solo.text = "S"
	solo.button_pressed = AudioServer.is_bus_solo(idx)
	solo.toggled.connect(func(on: bool) -> void: AudioServer.set_bus_solo(idx, on))
	ctl.add_child(solo)

	return {"idx": idx, "meter": meter, "peak": peak_label}


func _add_action(parent: Control, text: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(fn)
	parent.add_child(b)
	return b


func _process(delta: float) -> void:
	# A layout can only change between runs, but a scene that added a bus at boot
	# would leave the rows stale. This used to live in on_shown(), which the
	# dashboard only calls at REGISTRATION — so it could not catch a bus added
	# after that, and it re-armed _process while the F3 window was closed
	# (W13 / #955). One int compare per visible frame is both cheaper and correct;
	# whether this method runs at all is BaseDebugPanel's visibility gate's call.
	if AudioServer.bus_count != _built_for_bus_count:
		_rebuild_rows()
	for row in _rows:
		var i: int = row["idx"]
		if i >= AudioServer.bus_count:
			continue
		var peak := maxf(AudioServer.get_bus_peak_volume_left_db(i, 0),
			AudioServer.get_bus_peak_volume_right_db(i, 0))
		var held := maxf(peak, _levels[i] - METER_FALL_DB_PER_SEC * delta)
		_levels[i] = clampf(held, METER_FLOOR_DB, 0.0)
		row["meter"].value = _levels[i]
		row["peak"].text = "—" if _levels[i] <= METER_FLOOR_DB + 0.01 else "%.1f dB" % _levels[i]
	_music_route.text = "SMDPlayer (.SMD music)  →  '%s'" % _bus_of(_stream_player(_music_root()))
	_sfx_route.text = "ExMateriaEffectSfx (battle SFX)  →  '%s'" % _bus_of(_stream_player(ExMateriaEffectSfx))
	_music_sched.text = _scheduler_line()
	_sfx_sched.text = _sfx_scheduler_line()


func _play_music() -> void:
	if MusicPlayer.suppressed:
		# A scene can raise a music kill switch (the Effect Studio previewer does); without
		# saying so, the dead Music meter reads as a routing failure.
		_status.text = "MusicPlayer.suppressed — this scene silences music on purpose."
		return
	if MusicPlayer.play_slot(DEMO_MUSIC_SLOT):
		_status.text = "Playing MUSIC_%02d.SMD — the Music meter is the proof." % DEMO_MUSIC_SLOT
	else:
		_status.text = "play_slot(%d) failed — assets missing? (see MusicPlayer)" % DEMO_MUSIC_SLOT


func _stop_music() -> void:
	MusicPlayer.stop()
	_status.text = "Stopped."


func _fire_sfx() -> void:
	var token := SfxRouter.play_cue(DEMO_SFX_CUE)
	_status.text = "Fired '%s' (token %d) — watch the SFX meter, not Music." % [DEMO_SFX_CUE, token]


## Reads the live SPU's own queue counters. Nothing here is stored by the panel —
## if music is not playing there is no scheduler to report on, and it says so
## rather than showing a stale last-known line.
func _scheduler_line() -> String:
	var smd = _music_root()
	if smd == null or not smd.is_playing():
		return "not playing — press ▶ Music"
	var stats = smd.mixer.get_deferred_stats()
	var lead_frames: int = int(stats.get("schedule_frame", 0)) - int(stats.get("audio_frame", 0))
	return "lead %.0f ms   queue %d/%d (peak %d)   late %d   dropped %d   voices %d" % [
		float(lead_frames) / 44100.0 * 1000.0,
		int(stats.get("pending", 0)),
		int(stats.get("capacity", 0)),
		int(stats.get("high_water", 0)),
		int(stats.get("overdue", 0)),
		int(stats.get("overflow", 0)),
		smd.mixer.get_audio_active_voices(),
	]


## The SFX engine's own scheduler health, aggregated across its units — the worst
## case, not an average, since one late unit is one audible cue in the wrong place.
func _sfx_scheduler_line() -> String:
	if not ExMateriaEffectSfx.ready_ok:
		return "engine not ready"
	if ExMateriaEffectSfx.capture_mode:
		return "parked (capture_mode) — the studio is driving the units offline"
	var snap: Dictionary = ExMateriaEffectSfx.debug_snapshot()
	var sc: Dictionary = snap.get("scheduler", {})
	if int(sc.get("streams", 0)) == 0:
		return "no streams armed"
	return "lead %.1f ms (target %.1f)   late %d   dropped %d   free slots %d   streams %d   voices %d" % [
		float(sc.get("lead_ms", 0.0)),
		float(sc.get("target_lead_ms", 0.0)),
		int(sc.get("late", 0)),
		int(sc.get("dropped", 0)),
		int(sc.get("min_free_slots", -1)),
		int(sc.get("streams", 0)),
		int(snap.get("total_voices", 0)),
	]


func _music_root() -> Node:
	return MusicPlayer.get_node_or_null("SMDPlayer")


func _stream_player(root: Node) -> AudioStreamPlayer:
	if root == null:
		return null
	for child in root.get_children():
		if child is AudioStreamPlayer:
			return child
	return null


func _bus_of(player: AudioStreamPlayer) -> String:
	return "no player" if player == null else str(player.bus)


func _on_print_values() -> void:
	print("[AudioBusMixer] layout=%s" % ProjectSettings.get_setting(LAYOUT_SETTING, "<none>"))
	for i in range(AudioServer.bus_count):
		# `now` is the INSTANTANEOUS peak and `held` is what the bar shows. They disagree
		# by design: a cue that fired half a second ago reads -200 now and still shows on
		# the meter, so printing only `now` would say "silent" about a bus you just heard.
		var now := AudioServer.get_bus_peak_volume_left_db(i, 0)
		var held: float = _levels[i] if i < _levels.size() else METER_FLOOR_DB
		print("  %d %-8s → '%s'  vol=%.1f dB  mute=%s solo=%s  fx=%d  peak now=%.1f dB held=%.1f dB" % [
			i, AudioServer.get_bus_name(i), AudioServer.get_bus_send(i),
			AudioServer.get_bus_volume_db(i), AudioServer.is_bus_mute(i),
			AudioServer.is_bus_solo(i), AudioServer.get_bus_effect_count(i), now, held])
	print("  SMDPlayer → '%s'   ExMateriaEffectSfx → '%s'" % [
		_bus_of(_stream_player(_music_root())), _bus_of(_stream_player(ExMateriaEffectSfx))])
