extends SceneTree
## DEMI 2 (E046) emitter isolation — boots the real EffectViewer, plays E046 parked, and
## captures the effect at a fixed dense frame with only ONE emitter enabled at a time (then
## one pass with ALL enabled, and one with a chosen emitter disabled). Identifies which
## emitter is the confounding 1px-dot particle vs the black-subtractive / white-additive blobs.
##
## Run (NEVER headless), from the package root:  godot --path . -s res://tools/probe_demi_emitters.gd

const VIEWER := "res://assets/scenes/EffectViewer.tscn"
const EFFECT_ID := 46
const SEEK_FRAME := 26
const NUM_EMITTERS := 5

var _scene: Node
var _f := 0
var _played := false
var _play_f := -1
var _passes: Array = []   # each = {label, disabled:Array}
var _pass_i := -1
var _wait := 0
var _quit := false

func _initialize() -> void:
	# one pass per emitter (all others disabled) + all-on + a couple with candidates removed
	for e in range(NUM_EMITTERS):
		var dis: Array = []
		for k in range(NUM_EMITTERS):
			if k != e:
				dis.append(k)
		_passes.append({"label": "only%d" % e, "disabled": dis})
	_passes.append({"label": "all", "disabled": []})
	_scene = load(VIEWER).instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	print("[emit] booting EffectViewer for E%03d isolation @ frame %d" % [EFFECT_ID, SEEK_FRAME])

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
			_play_f = _f
			_pass_i = 0
			_apply_pass()
		elif _f > 300:
			print("[emit] FAIL — never settled")
			_quit = true
		return

	if _pass_i >= _passes.size():
		return
	_wait -= 1
	if _wait <= 0:
		var img := root.get_texture().get_image()
		var lbl: String = _passes[_pass_i]["label"]
		img.save_png("/tmp/demi_emit_%s.png" % lbl)
		print("[emit] captured pass '%s' (disabled=%s) -> /tmp/demi_emit_%s.png" % [
			lbl, str(_passes[_pass_i]["disabled"]), lbl])
		_pass_i += 1
		if _pass_i >= _passes.size():
			print("[emit] done")
			_quit = true
		else:
			_apply_pass()

func _apply_pass() -> void:
	var eff: Node = _scene.get("_current_effect")
	if eff != null and is_instance_valid(eff):
		var d: Dictionary = {}
		for k in _passes[_pass_i]["disabled"]:
			d[k] = true
		eff.call("set_debug_emitter_filter", d)
		eff.call("seek", SEEK_FRAME)
	_wait = 4
