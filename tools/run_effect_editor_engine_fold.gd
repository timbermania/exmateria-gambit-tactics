extends SceneTree
## Launch the Effect Studio / viewer with the NEW engine-fold compositor (Godot 4.8-dev, Forward+).
##
## Boots EffectViewer.tscn like normal, then swaps the shipped raw-GLSL CombatCompositeDriver for
## EngineFoldCompositor — so every effect you preview folds through the ENGINE Pass B pipeline
## (per-run MultiMesh + `compositor_fold` materials, sorting_offset order) instead of the raw-RD
## GLSL fold. The Studio UI (F3), effect picker, timeline scrub, emitter filter all work unchanged.
##
## RUN (headful; MUST be the 4.8-dev binary + Forward+):
##   BIN=~/Repos/godot-compositor-consume-material/bin/godot.linuxbsd.editor.dev.x86_64
##   # from the package root
##   # Interactive — press F3, pick an effect, scrub the timeline:
##   "$BIN" --path . --rendering-method forward_plus -s res://tools/run_effect_editor_engine_fold.gd
##   # Self-verify — auto-play an effect @ a frame, screenshot to /tmp, quit. Effect/frame are
##   # optional args (default E046 @ f45); e.g. `-- shot 65 50` for E065 Shiva @ f50:
##   "$BIN" --path . --rendering-method forward_plus -s res://tools/run_effect_editor_engine_fold.gd -- shot 65 50
##
## Occlusion (2026-07-27): fold materials are depth_draw_never + depth-test ENABLED, so folded effects
## are occluded by opaque units/map at their true depth (a spike behind a wall is hidden). Guard:
## tools/probe_occlusion_engine_fold.gd.

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const Fold = ExMateriaSchema.Fold

const VIEWER := "res://assets/scenes/EffectViewer.tscn"
## Defaults; override per-run with `-- shot <effect_id> <frame>` (e.g. `-- shot 65 40` for E065 Shiva).
const SHOT_EFFECT := 46
const SHOT_FRAME := 45
var _shot_effect := SHOT_EFFECT
var _shot_frame := SHOT_FRAME

var _scene: Node
var _mode := "interactive"
var _f := 0
var _swapped := false
var _shot_state := 0
var _quit := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and String(args[0]) == "shot":
		_mode = "shot"
		if args.size() > 1:
			_shot_effect = int(String(args[1]))
		if args.size() > 2:
			_shot_frame = int(String(args[2]))
	# Report the autopilot state so a `-s` run makes clear whether the branch-wide compositor autoload
	# is live (callbacks only fold when Fold.owns() is true).
	var ap := root.get_node_or_null("CompositorAutopilot")
	print("[engine-fold-editor] CompositorAutopilot present=%s Fold.owns=%s" % [
		ap != null, Fold.owns()])
	_scene = load(VIEWER).instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	print("[engine-fold-editor] booting EffectViewer (mode=%s)" % _mode)


func _process(_dt: float) -> bool:
	if _quit:
		quit()
		return true
	return false


func _on_post_draw() -> void:
	_f += 1
	if not _swapped:
		# When the branch-wide CompositorAutopilot owns compositing (fork + Forward+), it already
		# attaches EngineFoldCompositor to the live camera every frame — so DON'T also hand-swap here
		# (two folds fighting over cam.compositor). Just let it drive and proceed to play/seek/shot.
		if Fold.owns():
			if _f > 25:
				_swapped = true
				print("[engine-fold-editor] CompositorAutopilot owns compositing — no manual swap.")
			return
		var cam := _scene.get_node_or_null("PlayerCamera/FocusPoint/Camera") as Camera3D
		# Kill the shipped raw-RD compositor the moment it appears — under Forward+ it floods
		# push-constant errors (its 16-byte push vs the 8-byte copy/out shaders) until we swap.
		var old := _scene.get_node_or_null("CombatCompositeDriver")
		if old != null and cam != null and cam.compositor != null:
			old.set_process(false)
			cam.compositor = null
		var ready: bool = _scene.get("_caster") != null and _scene.get("_target") != null and cam != null
		if ready and _f > 25:
			_swap_driver(cam)
			_swapped = true
		elif _f > 400:
			push_error("[engine-fold-editor] scene never became ready")
			_quit = true
		return
	if _mode == "shot":
		_run_shot()


func _swap_driver(cam: Camera3D) -> void:
	var old := _scene.get_node_or_null("CombatCompositeDriver")
	if old:
		old.set_process(false)
		old.queue_free()
	var driver = ExMateriaEffects.EngineFoldCompositor.new()
	driver.name = "EngineFoldCompositor"
	_scene.add_child(driver)
	driver.setup(cam)
	print("[engine-fold-editor] swapped CombatCompositeDriver -> EngineFoldCompositor")
	if _mode == "interactive":
		print("[engine-fold-editor] READY — press F3 for the Studio, pick an effect, scrub the timeline.")


# Self-verify: park E046, seek the overlap frame, screenshot, quit.
func _run_shot() -> void:
	match _shot_state:
		0:
			_scene.call("play_effect", _shot_effect, true)
			_shot_state = 1
			_f = 0
		1:
			if _f > 15:
				var eff: Node = _scene.get("_current_effect")
				if eff != null and is_instance_valid(eff):
					eff.call("seek", _shot_frame)
				_shot_state = 2
				_f = 0
		2:
			if _f > 12:
				var img := root.get_texture().get_image()
				var path := "/tmp/engine_fold_editor_E%03d_f%02d.png" % [_shot_effect, _shot_frame]
				img.save_png(path)
				print("[engine-fold-editor] screenshot -> %s" % path)
				_shot_state = 3
				_quit = true
