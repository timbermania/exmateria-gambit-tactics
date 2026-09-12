extends SceneTree
## #7916 DEMO — effect side-by-side: CORRECT (render-layer fold) vs WRONG (native in-scene blend).
##
## Both sides run under Forward+ on the consume-material feature build. The only difference is the
## render layer, flipped via the PRODUCTION toggle (CompositorAutopilot.set_native_blend — the same
## path the Effect Studio checkbox drives):
##   fold   = autopilot ON, native_blend=false  -> display-space fold resolved to screen (clamped, correct)
##   linear = autopilot native_blend=true        -> EngineFoldCompositor rebuilds carriers with the native
##                                                   twins in-scene -> Forward+ linear HDR blend (muddy, wrong)
##
## Deterministic per-frame screen-grab (seek f -> settle -> grab root viewport) so the two runs align
## frame-for-frame; a compose step hstacks fold|native into an animated GIF + MP4.
##
## WINDOWED only, Forward+, consume-material build (the PR-build cf12328 can't run the game):
##   BIN=$(command -v godot)   # the 4.8 compositor fork, per CLAUDE.md
##   # from the package root
##   env WAYLAND_DISPLAY=wayland-1 DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 \
##     "$BIN" --path . --rendering-method forward_plus -s res://tools/probe_demi_sidebyside.gd \
##       -- <fold|linear> <effect_id> <frame_start> <frame_end>
## e.g.  -- fold 46 11 68     (DEMI 2)      -- linear 90 8 111   (SlowDance)

const VIEWER := "res://assets/scenes/EffectViewer.tscn"
const OUT_DIR := "/tmp/effect_demo"
const SETTLE := 4                 # draw ticks to hold a seek before grabbing

# Effect + frame range come from cmdline user-args: -- <mode> <effect_id> <frame_start> <frame_end>
var _mode := "fold"
var _effect_id := 46
var _frame_start := 0
var _frame_end := 60

var _scene: Node
var _cam: Camera3D
var _pool: Node
var _f := 0
var _played := false
var _frame := 0
var _hold := 0
var _quit := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and String(args[0]) == "linear":
		_mode = "linear"
	if args.size() > 1:
		_effect_id = int(String(args[1]))
	if args.size() > 2:
		_frame_start = int(String(args[2]))
	if args.size() > 3:
		_frame_end = int(String(args[3]))
	_frame = _frame_start
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	# Raw display texels: no linearize, unit PAR (the stp include reads these globals).
	RenderingServer.global_shader_parameter_set("psx_gamma", 1.0)
	RenderingServer.global_shader_parameter_set("psx_fx_stretch", 1.0)
	RenderingServer.global_shader_parameter_set("pixel_aspect", 1.0)
	_scene = load(VIEWER).instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	print("[sxs] mode=%s E%03d frames %d..%d" % [_mode, _effect_id, _frame_start, _frame_end])


func _process(_dt: float) -> bool:
	if _quit:
		quit()
		return true
	return false


func _on_post_draw() -> void:
	_f += 1
	if not _played:
		_try_start()
		return
	if _frame > _frame_end:
		return
	_hold -= 1
	if _hold <= 0:
		# The settled frame has been drawn; grab it, then advance + seek the next frame.
		_grab(_frame)
		_frame += 1
		if _frame > _frame_end:
			print("[sxs] done mode=%s E%03d (frames %d..%d in %s)" % [_mode, _effect_id, _frame_start, _frame_end, OUT_DIR])
			_quit = true
		else:
			_seek(_frame)


func _try_start() -> void:
	var driver := _scene.get_node_or_null("CombatCompositeDriver")
	_cam = _scene.get_node_or_null("PlayerCamera/FocusPoint/Camera") as Camera3D
	var ready: bool = _scene.get("_caster") != null and _scene.get("_target") != null and _cam != null
	if not ready:
		if _f > 300:
			print("[sxs] FAIL — never became ready")
			_quit = true
		return
	if _f <= 20:
		return
	_pool = root.get_node_or_null("EffectMultiMeshPool")
	# The retired raw-RD driver installs a compositor that errors under Forward+ — off (probe precedent).
	if driver != null:
		driver.set_process(false)
	if _mode == "linear":
		# WRONG side: flip the PRODUCTION toggle — same path the Effect Studio checkbox drives.
		# Autopilot's EngineFoldCompositor rebuilds carriers with the native twins in-scene (no fold).
		var ap := root.get_node_or_null("CompositorAutopilot")
		if ap != null and ap.has_method("set_native_blend"):
			ap.set_native_blend(true)
		else:
			print("[sxs] WARN no autopilot toggle — native side unavailable")
	# fold mode: leave the autopilot ON, native_blend=false — it folds to screen (correct side).
	_scene.call("play_effect", _effect_id, true)
	_played = true
	_seek(_frame_start)


func _seek(frame: int) -> void:
	var eff: Node = _scene.get("_current_effect")
	if eff != null and is_instance_valid(eff):
		eff.call("set_debug_emitter_filter", {})  # full effect — no emitter filter
		eff.call("seek", frame)
	_hold = SETTLE


func _grab(frame: int) -> void:
	var img := root.get_texture().get_image()
	if img == null:
		print("[sxs] WARN no viewport image at frame %d" % frame)
		return
	img.save_png("%s/e%03d_%s_f%03d.png" % [OUT_DIR, _effect_id, _mode, frame])
