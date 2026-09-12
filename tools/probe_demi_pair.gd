extends SceneTree
## DEMI 2 (E046) — isolate the two emitters the user named: idx1 (black subtractive, f22-38)
## + idx3 (white additive, f36-49). Disable the rest (0,2,4 incl. the confounding 1px-dot
## emitter). Seek to frames where black + white overlap and capture, to verify the white
## additive folds ON TOP of the black subtractive (age tie-break: white is newer = on top).
##
## Run (NEVER headless), from the package root:  godot --path . -s res://tools/probe_demi_pair.gd

const VIEWER := "res://assets/scenes/EffectViewer.tscn"
const EFFECT_ID := 46
const SEEKS := [36, 39, 42, 45]
const KEEP := [1, 3]            # emitters to keep enabled
const ALL_EMITTERS := 5

var _scene: Node
var _f := 0
var _played := false
var _si := -1
var _wait := 0
var _quit := false

func _initialize() -> void:
	_scene = load(VIEWER).instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	print("[pair] booting EffectViewer, E%03d, keep emitters %s" % [EFFECT_ID, str(KEEP)])

func _process(_dt: float) -> bool:
	if _quit:
		quit()
		return true
	return false

func _on_post_draw() -> void:
	_f += 1
	if not _played:
		var driver := _scene.get_node_or_null("CombatCompositeDriver")
		var ready: bool = _scene.get("_caster") != null and _scene.get("_target") != null and driver != null
		if ready and _f > 20:
			_scene.call("play_effect", EFFECT_ID, true)
			_played = true
			_si = 0
			_apply()
		elif _f > 300:
			print("[pair] FAIL — never settled")
			_quit = true
		return

	if _si >= SEEKS.size():
		return
	_wait -= 1
	if _wait <= 0:
		var img := root.get_texture().get_image()
		img.save_png("/tmp/demi_pair_f%02d.png" % SEEKS[_si])
		print("[pair] captured f%d -> /tmp/demi_pair_f%02d.png" % [SEEKS[_si], SEEKS[_si]])
		_si += 1
		if _si >= SEEKS.size():
			print("[pair] done")
			_quit = true
		else:
			_apply()

func _apply() -> void:
	var eff: Node = _scene.get("_current_effect")
	if eff != null and is_instance_valid(eff):
		var dis: Dictionary = {}
		for k in range(ALL_EMITTERS):
			if not KEEP.has(k):
				dis[k] = true
		eff.call("set_debug_emitter_filter", dis)
		eff.call("seek", SEEKS[_si])
	_wait = 4
