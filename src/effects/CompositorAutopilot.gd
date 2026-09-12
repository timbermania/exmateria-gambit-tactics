extends Node
## Branch-wide "compositor is always on" autopilot (compositor-displayspace-blend).
##
## The intent on this branch: EVERY scene you launch folds its effects through the ENGINE-fold
## compositor (EngineFoldCompositor, Godot 4.8-dev Pass B) — no per-scene wiring, no wondering
## whether a given scene's effects went through the compositor or not. This autoload watches the
## live 3D camera and keeps EngineFoldCompositor attached to it across scene changes.
##
## It is a NO-OP unless the engine reports it supports the `compositor_layer` primitive (built by
## the fork; Forward+-only). On stock 4.6 (and any build predating the primitive) it stands down and
## effect compositing simply does not run — the effects fall back to the scene's native LINEAR blend
## (no display-space clamp). The raw-RD GLSL fallback (CombatDisplaySpaceComposite /
## CombatCompositeDriver) was retired in #228 Phase 3, so the engine-fold is now the ONLY
## display-space compositor.
##
## MUST be launched on the fork: bin/godot.linuxbsd.editor.dev.x86_64 --rendering-method forward_plus.

## ADR-0211 dec. 4 — the addon's façade is its whole symbol surface, so the
## compositor arrives as a TYPE rather than as a path this file has to spell.
## It was a `const ENGINE_FOLD` STRING naming the file's old `src/effects/`
## address, `load()`ed at attach time, until extraction #7 (#1225): repointed, that
## string would have been the one PRODUCTION `res://addons/exmateria_effects/…`
## site `check_lattice_scene.py` criterion 4 scored, and a `load()` of a path this
## file also spells is an indirection with no reader.
const EngineFoldCompositor = ExMateriaEffects.EngineFoldCompositor

## True when this build supports the compositor_layer primitive (Forward+). The PUBLIC read of that
## fact is Fold.owns() (ADR-0191) — this is the autopilot's own copy, used only to decide whether to
## run at all, and nothing outside this file reads it.
var active := false

var _cam: Camera3D = null
var _fold: Node = null   # the live EngineFoldCompositor, re-created per camera

## Demo/compare toggle (#7916): when true the engine-fold renders the effect prims with native
## in-scene blend (render-layer OFF, the muddy "wrong" side) instead of the display-space fold.
## Opt-in — default false is the normal production fold. Flip via set_native_blend() (Effect Studio).
var native_blend := false


## Switch the live fold between the display-space fold and native in-scene blend, rebuilding the
## EngineFoldCompositor so the new shader set + render path take effect immediately.
func set_native_blend(v: bool) -> void:
	if native_blend == v:
		return
	native_blend = v
	if not active:
		return
	_cam = null   # force _attach to rebuild against the current camera
	_attach(get_viewport().get_camera_3d())


func _ready() -> void:
	# The feature detect lives in Fold.owns() (ADR-0191 dec. 1) — this autoload used to own it and
	# publish it as owns_compositing(), which fourteen call sites then copied verbatim. The query is a
	# property of the BUILD, so the kernel is its honest home.
	#
	# This local query is NOT owns_compositing() coming back: that method was PUBLISHED and duck-typed
	# by fourteen foreign PRODUCTION callers, and dec. 3 deletes it. `active` has exactly one reader
	# outside this file — tests/FoldTest.gd, which exists to compare it against Fold.owns(). The
	# difference is not privacy, it is that one test reading a value in order to check it is the
	# opposite of fourteen producers reading it in order to route on it.
	# What the local query is, is the SECOND INDEPENDENT EVALUATION that FoldTest asserts against. dec. 1 rests on the claim that a kernel-side owns() is "identical in every
	# reachable state" to the copies it replaced, and the only executable check behind that claim is two
	# code paths computing the answer separately and agreeing. Write `active = Fold.owns()` here and the
	# assertion becomes x == x — measured: seeding owns() to return the WRONG answer left FoldTest's
	# oracle assert GREEN, because both sides moved together. So this duplication is deliberate. It is
	# not a leftover copy; it IS the test. Keep it byte-identical to Fold.owns()'s query.
	active = (RenderingServer.has_method("is_compositor_layer_supported")
		and RenderingServer.is_compositor_layer_supported())
	if active:
		print("[compositor-autopilot] ACTIVE — engine-fold on for every scene (compositor_layer supported)")
	else:
		print("[compositor-autopilot] inactive (compositor_layer unsupported; here %s / %s) — shipped path unchanged"
			% [Engine.get_version_info().get("string", "?"), RenderingServer.get_current_rendering_method()])
		set_process(false)


func _process(_dt: float) -> void:
	# Keep the engine-fold pinned to the current scene's active 3D camera. When the camera changes
	# (scene switch, camera toggled current), rebuild the fold against the new one.
	var cam := get_viewport().get_camera_3d()
	if cam != null and is_instance_valid(_cam) and cam == _cam and is_instance_valid(_fold):
		return
	_attach(cam)


func _attach(cam: Camera3D) -> void:
	if _fold != null and is_instance_valid(_fold):
		_fold.queue_free()
	_fold = null
	_cam = null
	if cam == null:
		return   # no 3D camera yet (loading / a 2D-only scene) — try again next frame
	_fold = EngineFoldCompositor.new()
	_fold.name = "EngineFoldCompositor"
	_fold.native_blend = native_blend
	add_child(_fold)
	_fold.setup(cam)
	_cam = cam
	print("[compositor-autopilot] attached engine-fold to camera '%s'" % cam.name)
