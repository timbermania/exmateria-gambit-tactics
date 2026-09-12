extends SceneTree
## DEMI 2 (E046) parity capture — boots the REAL EffectViewer, plays E046 through the
## display-space compositor, then DETERMINISTICALLY seeks (ADR-0070) to a series of
## effect frames and screenshots each, so we can find the "dense middle/end" moment
## where white additive points sit inside the black subtractive cloud.
## Pairs with the PSX oracle (savestate8 framebuffer box 113,131..137,157).
##
## Run (NEVER headless):
##   # from the package root
##   godot --path . -s res://tools/probe_demi_capture.gd

const VIEWER := "res://assets/scenes/EffectViewer.tscn"
const EFFECT_ID := 46
const SEEKS := [40, 44, 48]   # effect frames to sample

var _scene: Node
var _f := 0
var _played := false
var _play_f := -1
var _seek_i := -1
var _seek_wait := 0
var _quit := false

func _initialize() -> void:
	_scene = load(VIEWER).instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	print("[demi] booting EffectViewer, will play E%03d" % EFFECT_ID)

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
			print("[demi] settled at f=%d — playing E%03d" % [_f, EFFECT_ID])
			_scene.call("play_effect", EFFECT_ID, true)   # parked=true so we drive via seek
			_played = true
			_play_f = _f
			_seek_i = 0
			_do_seek()
		elif _f > 300:
			print("[demi] FAIL — never settled")
			_quit = true
		return

	# Give the compositor a couple frames to fold after each seek, then capture.
	if _seek_i >= SEEKS.size():
		return
	_seek_wait -= 1
	if _seek_wait <= 0:
		var eff: Node = _scene.get("_current_effect")
		var cnt: int = -1
		if eff != null and is_instance_valid(eff):
			cnt = int(eff.get_effect_frame())
		var img := root.get_texture().get_image()
		var path := "/tmp/demi_godot_seek%02d.png" % SEEKS[_seek_i]
		img.save_png(path)
		print("[demi] CAPTURED seek=%d effect_frame=%d -> %s" % [SEEKS[_seek_i], cnt, path])
		_seek_i += 1
		if _seek_i >= SEEKS.size():
			print("[demi] done")
			_quit = true
		else:
			_do_seek()

func _do_seek() -> void:
	var eff: Node = _scene.get("_current_effect")
	if eff != null and is_instance_valid(eff):
		eff.call("seek", SEEKS[_seek_i])
	_seek_wait = 3
