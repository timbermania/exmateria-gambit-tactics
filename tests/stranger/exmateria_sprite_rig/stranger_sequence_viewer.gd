extends Node
## The sprite rig's own stranger arm: **`SequenceViewer` comes up in a project with no
## content, and REFUSES in the words its contract promises** — it does not crash, it does
## not die quietly, and it does not throw once a frame forever.
##
## WHY THIS SCENE EXISTS AND `stranger_install.gd` IS NOT ENOUGH. That arm asks whether every
## member LOADS. `SequenceViewer.tscn` loads, `SequenceViewer.gd` compiles, and both were
## green on the run that found this — the defect is entirely in what happens after `_ready`
## starts. Loading a scene and DRIVING it are different claims, and only the second one can
## see an early `return` that leaves an object half-wired. ADR-0229.
##
## WHY THE VIEWER AND NOT SOMETHING SMALLER. `docs/ROOT_SET.tsv` books
## `viewer/SequenceViewer.gd` `set=authoring, status=root`: it is the scene that exercises the
## whole addon by hand, and its entire preload set is in-addon plus `ExMateriaSpriteRig` and
## `ExMateriaSchema` — a declared dep. So it is the largest thing this rig can drive that
## needs nothing the rig does not already stage.
##
## 🔴 THE PRECONDITION IS ASSERTED, NOT ASSUMED. Every claim below is a claim about a project
## that declares NO `exmateria_sprite_rig/content_root`. A rig that quietly acquired one
## would turn this whole scene green while measuring the opposite thing, so arm 1 checks the
## setting is absent and a failure there is a FAILURE, not a skip (ADR-0194 dec. 12 arm 2).
##
## Run by `tests/stranger/exmateria_sprite_rig/run.sh`; skipped by the assembly suite with a
## `stranger` row, because in the host the content root is always declared and the branch
## this scene exists to take is unreachable there.

## Subpaths INSIDE the subject. The addon root itself is LEARNED, never spelled — see
## `_subject()`.
const CONTENT_ROOT_REL := "install/SpriteRigContentRoot.gd"
const VIEWER_REL := "viewer/SequenceViewer.tscn"

## Long enough that `_process` would have thrown many times over if the refusal had not
## disabled it. The pre-fix viewer threw twice per frame from frame one.
const FRAMES_TO_PUMP := 30

var _passed: int = 0
var _failed: int = 0

## `res://addons/<subject>`, learned from the staged project's own name in `_ready`.
var _addon: String = ""
## The subject's `SpriteRigContentRoot`, loaded through `_addon`. A `Script`, not a class
## reference: every use below is a static call or a static-var read through the value, which
## GDScript allows on a `Script` and refuses on a `const` class reference (that spelling is
## how `get_script_constant_map()` failed on this arm's first run).
var _cr: Script = null
## `res://addons/<subject>/viewer/SequenceViewer.tscn`.
var _viewer_scene: String = ""


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s" % label)


func _subject() -> String:
	"""`res://addons/<subject>`, from `application/config/name`.

	🔴 THIS FILE MAY NOT SPELL THE ADDON'S PATH, and the reason is the rig's own thesis. A
	guard that hardcodes its subject's directory breaks the day the subject moves, which is
	the one event this rig exists to survive; `check_lattice_scene`'s criterion 4 says the
	same thing from the other side and caught the first draft of this file doing it. The
	shared arm already learns its subject this way (`stranger_install.gd:_subject`) — this is
	that rule, applied to the first scene a rig has ever owned."""
	var name := str(ProjectSettings.get_setting("application/config/name", ""))
	if not name.begins_with("stranger_"):
		_check(false, "the staged project is named %s, which does not say `stranger_<addon>` — "
			% name + "this scene cannot know what to measure")
		return ""
	var path := "res://addons/%s" % name.substr(9)
	if DirAccess.open(path) == null:
		_check(false, "the project names subject %s but %s is not staged" % [name, path])
		return ""
	return path


func _ready() -> void:
	_addon = _subject()
	if _addon == "":
		print("%d passed, %d failed" % [_passed, _failed])
		print("[FAIL] the rig has no subject; nothing below was measured")
		get_tree().quit()
		return
	_viewer_scene = "%s/%s" % [_addon, VIEWER_REL]
	_cr = load("%s/%s" % [_addon, CONTENT_ROOT_REL]) as Script
	_check(_cr != null, "%s/%s did not load — the content-root contract is the subject of "
		% [_addon, CONTENT_ROOT_REL] + "every arm below and there is nothing to measure "
		+ "without it")
	if _cr == null:
		print("%d passed, %d failed" % [_passed, _failed])
		print("[FAIL] the sprite rig's exerciser does not survive a project with no content")
		get_tree().quit()
		return

	_test_this_project_declares_no_content_root()
	_test_every_documented_subpath_refuses()
	_test_the_refusal_is_reported_once_per_run()
	await _test_the_viewer_comes_up_and_refuses()

	if _passed == 0:
		print("[FAIL] ran zero assertions — nothing was checked, which is not a pass")
		_failed += 1
	print("%d passed, %d failed" % [_passed, _failed])
	if _failed == 0:
		print("[PASS] SequenceViewer comes up in a project with no sprite content and refuses "
			+ "in the words `%s` names, without throwing" % _cr.ROOT_SETTING)
	else:
		print("[FAIL] the sprite rig's exerciser does not survive a project with no content")
	get_tree().quit()


func _test_this_project_declares_no_content_root() -> void:
	"""Arm 1 — the precondition, checked. See the 🔴 above."""
	var raw := str(ProjectSettings.get_setting(_cr.ROOT_SETTING, ""))
	_check(raw == "", "this project declares %s=\"%s\" — a stranger project that supplies the "
		% [_cr.ROOT_SETTING, raw] + "content makes every arm below measure the host's "
		+ "case instead of the stranger's")
	_check(not _cr.has_root(), "has_root() is true with no setting declared")


func _test_every_documented_subpath_refuses() -> void:
	"""Arm 2 — `resolve()` returns `""`, for every subpath the contract names.

	Derived from `SpriteRigContentRoot`'s own constants rather than from a list here: a
	subpath added to the contract joins this arm on the day it is written, and a second
	roster of subpaths in a test file is the failure `stranger_install.gd`'s header spends
	a paragraph on."""
	# `_cr` is a `Script` VALUE, not a `const` class reference. GDScript reads a call on a
	# class reference as a STATIC call, and `get_script_constant_map()` is not static —
	# a parse error, caught on this arm's first run.
	var constants := _cr.get_script_constant_map()
	var subpaths := []
	for k in constants:
		if str(k).ends_with("_SUBPATH"):
			subpaths.append(constants[k])
	_check(subpaths.size() > 0, "SpriteRigContentRoot declares no *_SUBPATH constants — "
		+ "this arm derives its population from them and would otherwise check nothing")
	for sp in subpaths:
		_check(_cr.resolve(sp) == "", "resolve(%s) did not return \"\" with no root; a "
			% sp + "half-formed path resolves against the process working directory instead of "
			+ "failing the way a missing file already fails")
	_check(_cr.animations_dir() == "", "animations_dir() did not return \"\"")
	_check(_cr.textures_dir() == "", "textures_dir() did not return \"\"")


func _test_the_refusal_is_reported_once_per_run() -> void:
	"""Arm 3 — the latch. `resolve()` refuses ONCE, because a `push_error` per layer per
	frame buries it; that is the docstring's word and this is the arm that holds it.

	This arm has CONSUMED the latch by the time it returns — arm 2 above already called
	`resolve()` many times — which is why arm 4 asserts the viewer's refusal against the
	LABEL IT WRITES rather than against stderr. The two are different surfaces on purpose:
	stderr is for the run, the label is for whoever is looking at the window."""
	_check(_cr._unset_reported, "SpriteRigContentRoot did not latch a refusal after "
		+ "resolve() was called with no root — the error is either never pushed or pushed "
		+ "every time, and the docstring promises exactly once")


func _test_the_viewer_comes_up_and_refuses() -> void:
	"""Arm 4 — the whole point. Load, instantiate, add, and PUMP.

	`came up and refused` and `came up and died` are the two outcomes goal #5 has to be able
	to tell apart, and no static instrument in this repo can. Before ADR-0229 this arm found
	`sprite_layers.wep1_v_offset_pixels` on Nil at `_ready` and
	`_get_active_playback().advance_frame()` on Nil twice per frame after it."""
	var packed := load(_viewer_scene) as PackedScene
	_check(packed != null, "%s did not load in this project" % _viewer_scene)
	if packed == null:
		return
	var viewer := packed.instantiate()
	_check(viewer != null, "%s loaded but did not instantiate" % _viewer_scene)
	if viewer == null:
		return
	add_child(viewer)
	_check(is_instance_valid(viewer), "the viewer did not survive being added to the tree")
	for i in FRAMES_TO_PUMP:
		if not is_instance_valid(viewer):
			break
		await get_tree().process_frame
	_check(is_instance_valid(viewer), "the viewer died within %d frames of coming up"
		% FRAMES_TO_PUMP)
	if not is_instance_valid(viewer):
		return
	_check(viewer.is_inside_tree(), "the viewer removed itself from the tree")
	# The load-bearing half of the refusal. With `_process` still enabled the viewer throws
	# on Nil twice a frame for the life of the run, which is a crash report and not a refusal.
	_check(not viewer.is_processing(), "the viewer is still processing with no content to "
		+ "drive — `_process` advances a null AnimationPlayback every frame")
	_check(not viewer._drivable, "the viewer reports itself drivable in a project that "
		+ "supplies it no sprite content")
	# Said where a person is looking, not only on stderr.
	var label: String = str(viewer.info_label.text) if viewer.info_label else ""
	_check(label.find(_cr.ROOT_SETTING) != -1, "the viewer's info label does not name "
		+ "`%s`, so a user looking at an empty window is not told what to declare (label was: "
		% _cr.ROOT_SETTING + "%s)" % label)
	viewer.queue_free()
