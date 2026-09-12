extends Control
## SfxStressTest — interactive stress + monitor for the effect-sound engine.
## Plays many effect sounds at once through the REAL ExMateriaEffectSfx (same path
## the game uses) and shows live SPU/unit/voice state, so we can see whether
## effects are starving (preemption), being cut early, or playing out fully.
##
## Each cast here is allowed to play to its NATURAL end: its EffectSoundController
## runs the full timeline, then we wait a tail before end_effect — so if you DON'T
## hear whole effects here, it's the engine; if you DO hear them here but NOT in
## F5, the effect's node is being freed (end_effect) before its sound finishes.
##
## Run, from the package root:  Godot --path . res://assets/scenes/SfxStressTest.tscn
## Keys: SPACE burst 8 | A auto-burst | F toggle FAITHFUL/UNLOCKED | S stop all
##       1 single Shiva | 2 single Cure | UP/DOWN burst size
##       B toggle ambient rain bed (reserved unit) | LEFT/RIGHT ambient level trim
##
## The B/LEFT/RIGHT keys drive the dedicated {6B} ambient path: the bed binds a
## RESERVED unit outside the transient pool (never costs combat a slot) and feeds
## its OWN bus (Ambient); LEFT/RIGHT is the ambient sub-level knob (set_bg_level).
## Burst combat while a bed plays to watch cap_doublings stay 0 and the two limiter
## min_gains move independently.

const Loader = preload("res://addons/exmateria_sound/runtime/effect_json_loader.gd")
const STC = preload("res://addons/exmateria_sound/runtime/effect_sound_controller.gd")

const FX_IDS := ["E001", "E010", "E065", "E067", "E016", "E020", "E041", "E255"]
const TICK := 1.0 / 30.0
const TAIL_FRAMES := 120          # ~4 s ring-out after the timeline finishes
const AUTO_PERIOD := 0.7

@onready var _label: Label = $Panel/Label

var _loaded: Dictionary = {}      # id -> LoadedEffect
var _casts: Array = []            # {token, stc, fb, frame, fin_frame, id}
var _acc := 0.0
var _auto := false
var _auto_acc := 0.0
var _burst_size := 8
var _spawned_total := 0
var _last_action := "ready"
var _start_acc := 0.0
var _started := false
var _log_frame := 0
var _verbose := false       # L toggles per-second stdout snapshots (default off)
var _label_frame := 0
const ENV_BANK := "res://assets/audio/sfx_banks/env.feds"
var _bed_handle := 0        # live ambient rain bed (0 = none); B toggles


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	for id in FX_IDS:
		var l = Loader.load_dir("res://assets/effects/%s" % id)
		if l != null and l.has_sound():
			_loaded[id] = l
	if not ExMateriaEffectSfx.ready_ok:
		_last_action = "ENGINE NOT READY"
	_last_action = "loaded %d effects with sound" % _loaded.size()


func _spawn(id: String) -> void:
	if not _loaded.has(id):
		return
	var l = _loaded[id]
	var fb = l.feds_bank
	var token: int = ExMateriaEffectSfx.begin_effect()
	var stc = STC.new()
	stc.debug_log = false
	stc.load_effect(l)
	stc.pair_triggered.connect(func(p: int, _c: int, s: int, _ph: String) -> void:
		ExMateriaEffectSfx.play_pair(token, fb, p, s))
	stc.start(1, 0, {})
	_casts.append({"token": token, "stc": stc, "frame": 0, "fin_frame": -1, "id": id})
	_spawned_total += 1


func _burst(n: int) -> void:
	var ids: Array = _loaded.keys()
	if ids.is_empty():
		return
	for i in range(n):
		_spawn(ids[randi() % ids.size()])
	_last_action = "burst %d" % n


func _process(delta: float) -> void:
	# One automatic burst shortly after load so there's immediate activity to
	# hear/see (and to log for headless-graphical diagnosis).
	if not _started:
		_start_acc += delta
		if _start_acc >= 1.5:
			_started = true
			_burst(8)
	_acc += delta
	while _acc >= TICK:
		_acc -= TICK
		_tick30()
	if _auto:
		_auto_acc += delta
		if _auto_acc >= AUTO_PERIOD:
			_auto_acc = 0.0
			_burst(_burst_size)
	# Throttle the monitor refresh (string-building) to ~10/s instead of every frame.
	_label_frame += 1
	if _label_frame % 6 == 0:
		_update_label()


func _tick30() -> void:
	var keep: Array = []
	for c in _casts:
		c["stc"].update(c["frame"])
		c["frame"] += 1
		# When the timeline finishes firing keyframes, orphan the cast: the
		# already-dispatched FEDS pairs keep playing to their natural end (the
		# engine reaps them when the SOUND is done). This mirrors the game path
		# (EffectInstance._exit_tree -> orphan_effect).
		if c["stc"].is_finished():
			ExMateriaEffectSfx.orphan_effect(c["token"])
		else:
			keep.append(c)
	_casts = keep
	# Optional periodic stdout snapshot — OFF by default (toggle with L). The
	# on-screen monitor (throttled) is the normal view; stdout is for diagnosis.
	if _verbose:
		_log_frame += 1
		if _log_frame % 30 == 0:
			var s: Dictionary = ExMateriaEffectSfx.debug_snapshot()
			print("[stress] casts=%d units=%d voicesON=%d" % [
				_casts.size(), s["units"].size(), s["total_voices"]])


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE: _burst(_burst_size)
		KEY_1: _spawn("E065"); _last_action = "Shiva"
		KEY_2: _spawn("E001"); _last_action = "Cure"
		KEY_A:
			_auto = not _auto
			_last_action = "auto %s" % ("ON" if _auto else "OFF")
		KEY_F:
			var m = ExMateriaEffectSfx.VoiceMode.FAITHFUL if ExMateriaEffectSfx.voice_mode == ExMateriaEffectSfx.VoiceMode.UNLOCKED else ExMateriaEffectSfx.VoiceMode.UNLOCKED
			ExMateriaEffectSfx.set_voice_mode(m)
			for c in _casts:
				ExMateriaEffectSfx.end_effect(c["token"])  # casts dropped on mode switch
			_casts.clear()
			_last_action = "mode switch"
		KEY_S:
			for c in _casts:
				ExMateriaEffectSfx.end_effect(c["token"])
			_casts.clear()
			_last_action = "stop all"
		KEY_UP: _burst_size = mini(64, _burst_size + 1)
		KEY_DOWN: _burst_size = maxi(1, _burst_size - 1)
		KEY_L:
			_verbose = not _verbose
			_last_action = "verbose log %s" % ("ON" if _verbose else "OFF")
		KEY_B:
			if _bed_handle != 0:
				ExMateriaEffectSfx.stop_bg(_bed_handle)
				_bed_handle = 0
				_last_action = "ambient bed OFF"
			else:
				_bed_handle = ExMateriaEffectSfx.begin_bg(ENV_BANK, 0, 1)  # Rain 1
				ExMateriaEffectSfx.set_bg_gain(_bed_handle, 90)            # audible bed
				_last_action = "ambient bed ON (rain, reserved unit)"
		KEY_RIGHT:
			ExMateriaEffectSfx.set_bg_level(minf(1.0, ExMateriaEffectSfx.get_bg_level() + 0.1))
			_last_action = "ambient level %.1f" % ExMateriaEffectSfx.get_bg_level()
		KEY_LEFT:
			ExMateriaEffectSfx.set_bg_level(maxf(0.0, ExMateriaEffectSfx.get_bg_level() - 0.1))
			_last_action = "ambient level %.1f" % ExMateriaEffectSfx.get_bg_level()


func _update_label() -> void:
	var s: Dictionary = ExMateriaEffectSfx.debug_snapshot()
	var active_fin := 0
	for c in _casts:
		if c["fin_frame"] >= 0:
			active_fin += 1
	var lines: Array = []
	lines.append("SFX STRESS  —  mode=%s   units=%d/%d   total active voices=%d" % [
		s["mode"], s["units"].size(), s["max_units"], s["total_voices"]])
	lines.append("active casts=%d  (timeline-finished, tail ringing=%d)   spawned total=%d" % [
		_casts.size(), active_fin, _spawned_total])
	lines.append("")
	for i in range(s["units"].size()):
		var u = s["units"][i]
		lines.append("  unit %d:  voices ON = %2d / 24    casts=%d    %s" % [
			i, u["voices"], u["sessions"], "ACTIVE" if u["active"] else "idle (sleeping)"])
	lines.append("")
	# Dedicated ambient ({6B}) channel — reserved units on their own bus + level.
	var bg_units: Array = s.get("bg_units", [])
	var sched: Dictionary = s.get("scheduler", {})
	lines.append("AMBIENT  bed=%s   level=%.1f   reserved units=%d/%d   cap_doublings=%d" % [
		("ON" if _bed_handle != 0 else "off"), s.get("bg_level", 1.0),
		bg_units.size(), s.get("max_bg_units", 0), s.get("cap_doublings", 0)])
	for i in range(bg_units.size()):
		var u = bg_units[i]
		lines.append("  ambient %d:  voices ON = %2d / 24    beds=%d    %s" % [
			i, u["voices"], u["sessions"], "ACTIVE" if u["active"] else "idle (sleeping)"])
	# The independent-headroom claim moved from two GDScript limiters onto the bus
	# split (#385 task 3), so what is worth watching here is the SCHEDULER instead:
	# late/dropped are the only failures the streamed path can have.
	lines.append("  scheduler:  lead=%.1fms (target %.1f)  late=%d  dropped=%d  streams=%d" % [
		sched.get("lead_ms", 0.0), sched.get("target_lead_ms", 0.0),
		sched.get("late", 0), sched.get("dropped", 0), sched.get("streams", 0)])
	lines.append("")
	lines.append("[SPACE] burst %d   [UP/DOWN] size   [A] auto:%s   [1]Shiva [2]Cure   [F] mode   [S] stop" % [
		_burst_size, ("ON" if _auto else "off")])
	lines.append("[B] ambient bed   [LEFT/RIGHT] ambient level")
	lines.append("last: %s" % _last_action)
	_label.text = "\n".join(lines)
