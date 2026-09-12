extends Node
## LOOK AT IT — a one-shot probe that drives the navigator to its first STOPPED PLAYER TURN
## and writes the frame to a PNG (ADR-0265).
##
## The turn surface is judged by playing it: both defects ADR-0265 fixes were found in about
## a minute at the keyboard while every test passed, and the tests that passed were not wrong
## — they asserted the clock, which worked. `NavigatorTurnStopTest` still owns the assertions.
## This owns the picture: the AT marker on the taker, the camera sitting on them, and the
## badge naming the key that ends the stop.
##
## Run (headful — never `--headless`):
##   godot --path . res://tools/probe_nav_turn_beat.tscn
##
## Writes `<user data dir>/nav_turn_beat.png` and prints the absolute path.

const SKIP_SLUG := "navigator.skip_pre_battle"
const INVINCIBLE_SLUG := "navigator.owned_invincible"
const STOP_ON_TURN_SLUG := "navigator.stop_on_turn"
const BATTLE_ROOT := 9          # Gariland
## Frames to let the beat land before the shot — the travel is
## `PlayerCamera.follow_ease_frames` long and the marker rides the taker.
const SETTLE_FRAMES := 40
const TIMEOUT_FRAMES := 4000

var _nav: Node = null
var _frames: int = 0
var _hold: int = -1
var _done: bool = false


func _ready() -> void:
	# `Tune.set_value` and not the tracked override file: an in-memory write does not dirty
	# `config/tune_overrides.json`, which is tracked, globally loaded, and has hung every
	# navigator walk on `main` once already.
	for slug in [SKIP_SLUG, INVINCIBLE_SLUG, STOP_ON_TURN_SLUG]:
		Tune.bind(slug, false, {}, Tune.Persist.AUTOSAVE)
		Tune.set_value(slug, true)
	DebugConfig.battle_seek_root = BATTLE_ROOT
	Engine.time_scale = 20.0
	var scene: PackedScene = load("res://assets/scenes/NavigatorMain.tscn")
	_nav = scene.instantiate()
	add_child(_nav)
	print("[probe_nav_turn_beat] booting --battle=%d with the turn stop armed" % BATTLE_ROOT)


func _process(_delta: float) -> void:
	if _done:
		return
	_frames += 1
	if _frames > TIMEOUT_FRAMES:
		print("[probe_nav_turn_beat] TIMEOUT — no commandable turn stop in %d frames" % TIMEOUT_FRAMES)
		_quit()
		return
	if _hold >= 0:
		_hold -= 1
		if _hold == 0:
			_shoot()
		return
	if _nav == null or not is_instance_valid(_nav):
		return
	var director = _nav._turn_director
	if director == null or not is_instance_valid(director):
		return
	if director.state() != TurnDirector.State.TURN_OPEN:
		return
	if not _nav._commandable.has(director.taker()):
		return
	# A stop the player is meant to end. Real time for the travel, then the shot.
	Engine.time_scale = 1.0
	_hold = SETTLE_FRAMES
	print("[probe_nav_turn_beat] stopped on taker %d — %s" % [director.taker(), _nav.stop_badge_text()])


func _shoot() -> void:
	var path := OS.get_user_data_dir() + "/nav_turn_beat.png"
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	print("[probe_nav_turn_beat] badge   : %s" % _nav.stop_badge_text())
	print("[probe_nav_turn_beat] marker  : unit %d, node=%s" % [
		_nav._beat.marker_unit, str(_nav._beat.marker != null)])
	print("[probe_nav_turn_beat] cursor  : %s" % (
		str(_nav._cursor_rig.grid_pos) if _nav._cursor_rig != null else "NO CURSOR RIG"))
	print("[probe_nav_turn_beat] shot    : %s (err %d)" % [path, err])
	_quit()


func _quit() -> void:
	_done = true
	get_tree().quit()
