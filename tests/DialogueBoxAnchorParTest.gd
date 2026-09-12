extends Node
# test-kind: logic
# seeded-break: make the PAR read unusable in src/scenarios/ScenarioDialogueBoxPool.gd `_sprite_billboard_anchor` (`var par: float = PSXDisplay.live_par` -> `= -1.0`), reproducing the pre-W14 state where the editor-only getter returned null outside the editor and the `if par > 0.0` guard never fired — 'PAR 1.5 stretches the anchor's cam-local x' (got 3.0, want 4.5) and '...and it reads the runtime mirror instead' red, 7 of 9 assertions still pass
## W14 (#956) — the dialogue tail's PAR correction must actually RUN in the shipped
## game, and it must stop calling an editor-only RenderingServer API to do it.
##
## `ScenarioDialogueBoxPool._sprite_billboard_anchor` read PAR through
## `RenderingServer.global_shader_parameter_get("pixel_aspect")`. That getter is
## editor-only: `MaterialStorage::global_shader_parameter_get` opens with
## `if (!Engine::get_singleton()->is_editor_hint()) { ERR_FAIL_V_MSG(Variant(),
## "This function should never be used outside the editor, ...") }`. Outside the
## editor it therefore returns `null` on EVERY call, so
##
##   1. the `if par != null` guard below it never fired and the ADR-0036 stretch this
##      code exists to apply had never once run in the shipped game; and
##   2. each call printed the engine error plus a four-line GDScript backtrace — about
##      286 000 of a 150 s navigator walk log's 288 124 lines, 99 % of everything the
##      game said (GPU-ARENA-PERF.md → W14).
##
## **This test is not a speed claim, and R29's A/B says it cannot be one**: arm B was
## +4.5 % but arm A's own two reps differed by 12 %, so the rig could not resolve a
## frame cost. What is assertable is the behaviour — and behaviour is what was broken.
##
## ⚠ At the committed default the multiply is by 1.0 (`pixel_aspect` in project.godot
## `[shader_globals]`, no `render.pixel_aspect` override), so this fix moves nothing
## on screen today. `_test_default_par_is_a_no_op` pins that, so nobody reads the fix
## as a visual change; `_test_par_stretches_the_anchor_at_runtime` pins the half that
## was actually dead.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/DialogueBoxAnchorParTest.tscn

const Pool = preload("res://src/scenarios/ScenarioDialogueBoxPool.gd")

const SPEAKER_X := 3.0
const SPEAKER_Y := 1.0
const SPEAKER_Z := -7.0

var _passed: int = 0
var _failed: int = 0
var _boot_par: float = 1.0


func _ready() -> void:
	_boot_par = PSXDisplay.live_par
	_test_par_stretches_the_anchor_at_runtime()
	_test_default_par_is_a_no_op()
	_test_the_editor_only_getter_is_gone()
	PSXDisplay.live_par = _boot_par   # shared autoload state — hand it back
	_finish()


## The dead half, restored. Outside the editor `live_par` is the only readable source
## of PAR, so a scrub to 1.5 must stretch the anchor's cam-local x by 1.5. Under the
## old code this assertion fails for any PAR: the getter returned null and the anchor
## came back unstretched.
func _test_par_stretches_the_anchor_at_runtime() -> void:
	_true(not Engine.is_editor_hint(),
		"this test runs OUTSIDE the editor — the whole point of the bug")

	var rig := _build_rig()
	var pool = Pool.new(null)
	pool.anchor_to_billboard = true
	pool.anchor_quad_frac_y = 0.0    # isolate x; the y slide is PAR-neutral

	PSXDisplay.live_par = 1.0
	var unstretched: Vector3 = pool._sprite_billboard_anchor(rig["cam"], rig["speaker"])
	PSXDisplay.live_par = 1.5
	var stretched: Vector3 = pool._sprite_billboard_anchor(rig["cam"], rig["speaker"])

	_true(absf(unstretched.x) > 0.01,
		"the rig puts the speaker OFF the camera axis, so a PAR multiply is visible (x=%.3f)"
			% unstretched.x)
	_true(is_equal_approx(stretched.x, unstretched.x * 1.5),
		"PAR 1.5 stretches the anchor's cam-local x (got %.4f, want %.4f)"
			% [stretched.x, unstretched.x * 1.5])
	_true(is_equal_approx(stretched.y, unstretched.y) and is_equal_approx(stretched.z, unstretched.z),
		"PAR touches x only — y and z are unchanged")

	rig["root"].queue_free()


## The honest other half: `pixel_aspect` ships at 1.0, so restoring the correction
## changes no frame the player sees today. Said out loud so the fix is not sold as a
## visual change it is not.
func _test_default_par_is_a_no_op() -> void:
	var decl: Variant = ProjectSettings.get_setting("shader_globals/pixel_aspect")
	_true(decl != null and is_equal_approx(float((decl as Dictionary)["value"]), 1.0),
		"project.godot ships pixel_aspect = 1.0, so the restored multiply is by one")

	var rig := _build_rig()
	var pool = Pool.new(null)
	pool.anchor_to_billboard = true
	pool.anchor_quad_frac_y = 0.0
	PSXDisplay.live_par = 1.0
	var anchor: Vector3 = pool._sprite_billboard_anchor(rig["cam"], rig["speaker"])
	var raw: Vector3 = rig["cam"].to_local((rig["mesh"] as Node3D).global_position)
	_true(is_equal_approx(anchor.x, raw.x),
		"at PAR 1.0 the anchor is the raw mesh origin — no shipped frame moves")
	rig["root"].queue_free()


## The counted witness. What regresses is not a millisecond, it is a call: the next
## person to want PAR here must not reach for the editor-only getter again. One
## production call site missed the memo and this was it — `PSXDisplay` is the mirror.
func _test_the_editor_only_getter_is_gone() -> void:
	var src := FileAccess.get_file_as_string("res://src/scenarios/ScenarioDialogueBoxPool.gd")
	_true(src != "", "read ScenarioDialogueBoxPool.gd")
	# Match the CALL, not the word: the fix's own comment explains the trap by name,
	# and a guard that its own explanation satisfies is the classic false green.
	_true(not src.contains("RenderingServer.global_shader_parameter_get("),
		"the box pool no longer CALLS the editor-only getter (it reads PSXDisplay.live_par)")
	_true(src.contains("PSXDisplay.live_par"),
		"...and it reads the runtime mirror instead")


## A camera and a speaker with the `UnitMesh` child the anchor requires, both in the
## tree so global transforms resolve. The speaker sits off the camera's forward axis
## on purpose: an anchor at x = 0 would multiply to itself and pass any PAR.
func _build_rig() -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.global_position = Vector3.ZERO
	cam.look_at_from_position(Vector3.ZERO, Vector3(0, 0, -1), Vector3.UP)

	var speaker := Node3D.new()
	root.add_child(speaker)
	speaker.global_position = Vector3(SPEAKER_X, SPEAKER_Y, SPEAKER_Z)
	var mesh := Node3D.new()
	mesh.name = "UnitMesh"
	speaker.add_child(mesh)
	mesh.scale = Vector3(1.0, 8.0, 1.0)   # the ~8 the anchor's scale_y comment expects
	return {"root": root, "cam": cam, "speaker": speaker, "mesh": mesh}


func _true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL %s" % msg)


func _finish() -> void:
	if _passed == 0 and _failed == 0:
		print("[FAIL] DialogueBoxAnchorParTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] DialogueBoxAnchorParTest — %d/%d" % [_passed, _passed + _failed])
		get_tree().quit(1)
	else:
		print("[PASS] DialogueBoxAnchorParTest — %d/%d" % [_passed, _passed])
		get_tree().quit(0)
