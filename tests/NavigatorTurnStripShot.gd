extends Node
## NOT A GUARD — the screenshot rig for the turn queue strip riding the WALK's camera
## (#898, ADR-0245). It exists because ADR-0244 found the failure mode no assertion can
## reach: a UI3 window host left at the camera's own origin draws perfectly and is
## INVISIBLE, with every position it asserts correct. `NavigatorTurnDirectorMountTest`
## asserts the depth is negative; only a picture says the strip is legible, in the right
## corner, over the right battlefield, with portraits that resolved.
##
## Boots the real walk seeked to Gariland, drops the time scale once the battle is live
## (at 40x the whole battle resolves in a couple of frames), and saves three frames.
##
##   godot --path . --quit-after 3000 res://tests/NavigatorTurnStripShot.tscn
##   # writes user://shots/nav_turn_strip_{0,1,2}.png

const SKIP_SLUG := "navigator.skip_pre_battle"
const INVINCIBLE_SLUG := "navigator.owned_invincible"
## Pinned false in `_ready` — see the note there. Mirrors NavigatorMain.STOP_ON_TURN_SLUG.
const STOP_ON_TURN_SLUG := "navigator.stop_on_turn"

var _out: String = "user://shots"

var _nav: Node = null
var _shot: int = 0
var _busy: bool = false
var _done: bool = false


func _ready() -> void:
	print("[NOT_A_TEST] a screenshot rig for the walk's turn queue strip — its own header says NOT A GUARD")
	DirAccess.make_dir_recursive_absolute(_out)
	var idx := _gariland_opener_index()
	ScenarioDebugSession.navigator_start_root = 1
	ScenarioDebugSession.navigator_stop_root = 9
	ScenarioDebugSession.navigator_start_action = idx
	Tune.bind(SKIP_SLUG, false, {}, Tune.Persist.AUTOSAVE)
	Tune.set_value(SKIP_SLUG, true)
	Tune.bind(INVINCIBLE_SLUG, false, {}, Tune.Persist.AUTOSAVE)
	Tune.set_value(INVINCIBLE_SLUG, true)
	# Fast to the battle, then real time so the strip is on screen for long enough to
	# shoot it — at 40x the whole battle resolves in a couple of frames.
	Engine.time_scale = 40.0
	# PIN the turn stop OFF. `navigator.stop_on_turn` is an AUTOSAVE tunable, so a session that
	# ticked it in the F3 panel leaves it TRUE in the tracked `config/tune_overrides.json` — and a
	# walk that stops on every turn with nobody to press Space does not fail here, it HANGS. The
	# same reason `NavigatorBattleLaunchTest` pins `skip_pre_battle` false rather than assuming it.
	Tune.bind(STOP_ON_TURN_SLUG, false, {}, Tune.Persist.AUTOSAVE)
	Tune.set_value(STOP_ON_TURN_SLUG, false)

	var scene: PackedScene = load("res://assets/scenes/NavigatorMain.tscn")
	_nav = scene.instantiate()
	add_child(_nav)


func _process(_delta: float) -> void:
	if _done or _busy or _nav == null:
		return
	var hud = _nav._turn_queue_hud
	if hud == null or not is_instance_valid(hud) or not hud.visible:
		return
	Engine.time_scale = 0.25
	_busy = true
	_shoot()


func _shoot() -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/nav_turn_strip_%d.png" % [_out, _shot])
	var hud = _nav._turn_queue_hud
	if is_instance_valid(hud):
		print("[SHOT] %d — queue %s, draws %d" % [_shot, str(hud.shown_indices()), hud.draws()])
	_shot += 1
	if _shot >= 3:
		_done = true
		Engine.time_scale = 1.0
		get_tree().quit(0)
		return
	for i in range(40):
		await get_tree().process_frame
	_busy = false


func _gariland_opener_index() -> int:
	var plan := GameNavigator.new().plan_actions(1, 9, StoryMutationScript.build())
	for i in range(plan.size()):
		var a: Dictionary = plan[i]
		if String(a.get("kind", "")) == "opener" and int(a.get("beat", {}).get("scenario_id", -1)) == 10:
			return i
	return -1
