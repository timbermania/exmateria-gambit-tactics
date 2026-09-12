@tool
extends EditorPlugin
## ExMateria Battlefield — Godot editor plugin entry.
##
## **It provides eight names, and that is the point.** This file used to say there was
## "nothing to install here that this file can install", and after #564 (ADR-0183) that was
## true of AUTOLOADS — the addon publishes none, and none is coming back. It was never true
## of the input map: the addon binds **8 input actions**, which is a thing a bare project
## simply does not have. That is ADR-0202 Class D, twelve register rows over eight names.
##
## ADR-0203 dec. 1 settles the shape: **an addon PROVIDES what it can author and INJECTS
## what it cannot.** A name and a default are authorable, so D is provided here. ROM
## content is not, so Class B is injected through `BattlefieldContent` instead.
##
## 🔴 IT PROVIDED FIVE SHADER GLOBALS AND NO LONGER DOES — ADR-0220 dec. 2, and this is a
## LAYERING fix, not a retreat. All five were DECLARED in `addons/exmateria_platform/`
## (ADR-0190 took this addon to zero declarations of its own) and provided from here, which
## made one declaration of `pixel_aspect` arm-3 green for THIS subject and arm-3 red for
## `exmateria_sprite_rig`, whose install target holds the port and not this addon — the
## Class C inversion ADR-0202 dec. 6 names, arriving through the shader-global door. And
## `unit_stretch`, split into its own seam at #744, was provided by nothing at all.
##
## ADR-0220 dec. 1 puts the provide on the DECLARER: `addons/exmateria_platform/plugin.gd`
## now carries all six, `check_addon_portability.py` arm 4c enforces it, and this addon
## keeps its arm-3 zero because the port is inside its own install target — which is the
## reading that proves `provided_by_walk` finds it there rather than here.
##
## ⚠️ `PROVIDED_GLOBALS` stays as an EMPTY array rather than being deleted, and so does the
## loop over it in `provide_into`. The const is the contract `check_addon_install.py` and
## `check_addon_portability.py` both parse, and an addon that declares a `global uniform`
## tomorrow provides it by filling this in — the empty list says *this addon requires the
## host to hold none*, which a missing const cannot say.
##
## 🔴 `EditorPlugin` BLESSES AUTOLOADS WITH AN API AND BLESSES NOTHING FOR THIS CHANNEL.
## There is no `add_input_action()` (nor, in the port, an `add_shader_global()`).
## `ProjectSettings.set_setting()` plus `ProjectSettings.save()` is the whole mechanism, and ADR-0203 dec. 5
## says so explicitly so the next reader does not go hunting for an API that is not there
## and conclude the decision is unbuildable. dec. 8 of ADR-0202 wrote "an enable-time
## `ProjectSettings` WRITE" and not "an `EditorPlugin` registration call" for this reason.
##
## 🔴 IN THIS REPO THIS CODE NEVER RUNS, AND THAT IS A STATED FACT, NOT AN OVERSIGHT.
## `godot-learning/project.godot` has no `[editor_plugins]` section — no `plugin.gd` in this
## package has ever had `_enter_tree` called. `addons/exmateria_render/plugin.gd` wrote the
## objection down years before ADR-0203 confirmed it. Two consequences, both load-bearing:
##
##   1. The host keeps declaring all eight names itself, and SHOULD. A diff that deletes
##      them from `project.godot` has misread ADR-0203 dec. 4.
##   2. **Booting the game verifies nothing about this file.** A pass reporting "headful
##      boot, no errors" as evidence for the provide has measured the branch where the
##      write does not happen. The oracle is `tests/BattlefieldProvidesTest.gd`, which
##      calls `provide_into()` directly against a settings surface it can inspect.
##
## 🔴 AND THE INSTALL REGISTER ALONE IS A TAUTOLOGY. After ADR-0203 dec. 3 re-points arms 2
## and 3, their predicate is "does the addon require a name no addon in the walk provides" —
## which anybody can green by typing eight strings into the array below. The guard
## cannot tell a reached code path from a decorative one. dec. 4 REQUIRES the direct-call
## test to ship in the same commit as the arm change, and it did.
##
## THE READ BELOW IS PART OF THE WRITE. ADR-0203 dec. 2 amends ADR-0202 dec. 8's "the
## addon's count is 0 and must stay 0": the rule is about DIRECTION. A read that sources
## configuration the host was expected to supply stays forbidden; a read that decides
## whether this addon's own write is needed is part of the write. Without that carve-out
## dec. 8 forbids the only idempotent spelling of the thing dec. 8 permits — and the
## consumer that already declares these names (the in-repo game does) must not get a
## duplicate. Same argument, same shape, as `exmateria_sound/plugin.gd:46`.
##
## FIRST ENABLE IN A BARE PROJECT LOGS SHADER COMPILE ERRORS, and that is documented rather
## than fixed (ADR-0203 dec. 6). Godot imports and compiles this addon's shaders when the
## project OPENS; the plugins are enabled after. The honest install sequence is *copy the
## three addons → open → enable → reload*, and it is written into README.md. ⚠️ Since
## ADR-0220 dec. 2 the shader globals come from the PORT's plugin, so `exmateria_platform`
## is one of the plugins that has to be enabled — the reload is what makes the shaders
## compile either way.
##
## 🔴 AND THIS IS THE ONE PLACE THE COMPILE ERROR IS REAL, which is worth stating now that
## ADR-0238 has shown it is not real anywhere else. `shader_language.cpp` validates a
## `global uniform` only under `Engine::is_editor_hint()`, so the EDITOR OPEN above is
## exactly the path that reports it — and a running game, an exported build or a stranger
## rig reports nothing at all and renders with the name at its type's zero. So the noisy
## case is the benign one (you are about to enable and reload) and the quiet case is the
## damaging one.

const INPUT_PREFIX: String = "input/"
const SHADER_GLOBAL_PREFIX: String = "shader_globals/"

## The 8 input actions the addon binds — ADR-0202 dec. 9's Class D, 12 register rows over 8
## distinct names (`PAN_ACTIONS` and `CURSOR_ACTIONS` declare the same four in two files).
##
## `[name, deadzone, [[kind, code], …]]`, where kind is "key" (a PHYSICAL keycode, matching
## how the host declares them so a non-QWERTY layout behaves identically) or "pad" (a
## joypad button index). Defaults reproduce `project.godot`'s bindings exactly; the point of
## a provide is that a bare project behaves like the in-repo one, not merely that the name
## exists.
##
## ⚠️ PLAIN STRINGS, NOT `&"…"` StringNames, and that is deliberate. The install register's
## arm 2 finds action names by scanning for the `&"…"` literal and for `is_action_*("…")`
## call sites. Spelling this list with `&` would book eight fresh sites against the file
## whose whole job is to retire them — harmless under the re-pointed predicate, but it would
## make the register's own report read as if the addon had grown new debt.
const PROVIDED_ACTIONS: Array = [
	# The four pan/cursor steps. WASD + arrows + D-pad, the same four names in both
	# `PlayerCamera.PAN_ACTIONS` and `TileCursor.CURSOR_ACTIONS`.
	["camera_up", 0.5, [["key", KEY_W], ["key", KEY_UP], ["pad", JOY_BUTTON_DPAD_UP]]],
	["camera_down", 0.5, [["key", KEY_S], ["key", KEY_DOWN], ["pad", JOY_BUTTON_DPAD_DOWN]]],
	["camera_left", 0.5, [["key", KEY_A], ["key", KEY_LEFT], ["pad", JOY_BUTTON_DPAD_LEFT]]],
	["camera_right", 0.5, [["key", KEY_D], ["key", KEY_RIGHT], ["pad", JOY_BUTTON_DPAD_RIGHT]]],
	# The two isometric yaw steps — `PlayerCamera.gd:491`/`:493`, the only two of the eight
	# an inline-literal grep ever found, which is where the inherited count of 2 came from.
	#
	# L1/R1 join them (ADR-0268 dec. 6): the shoulders rotate the camera on the real hardware,
	# and these two actions carried NO pad button at all — an omission, not a decision. Paired
	# BY SIDE with the keys already on them: Q is the left key and takes the left shoulder, E
	# the right. That is one action with one intent, so `_test_one_intent_per_button` gains no
	# row to collide with, and the gambit surface re-means them as raise/lower slot while it
	# owns the pad rather than asking for bindings of its own.
	["rotate_camera_cw", 0.5, [["key", KEY_Q], ["pad", JOY_BUTTON_LEFT_SHOULDER]]],
	["rotate_camera_ccw", 0.5, [["key", KEY_E], ["pad", JOY_BUTTON_RIGHT_SHOULDER]]],
	# Tab / pad △ (`TileCursor.CURSOR_INSPECT_ACTION`). Tab is bound by three host actions —
	# this one, `formation_start_menu` and `world_map_start_menu` — which do not contend
	# because they belong to three different screens. Only `unit_inspect` is the addon's, and
	# only `unit_inspect` is provided here; a provide that reached for the other two would be
	# this addon installing names it does not use.
	["unit_inspect", 0.5, [["key", KEY_TAB], ["pad", JOY_BUTTON_Y]]],
	# Enter / KP-Enter / pad ○. NOT `ui_accept`: Godot's default binds SPACE and on the
	# battlefield Space STARTS the battle, so riding `ui_accept` would make starting a
	# battle also a confirm (`TileCursor.CURSOR_CONFIRM_ACTION`, ADR-0137).
	["cursor_confirm", 0.5, [["key", KEY_ENTER], ["key", KEY_KP_ENTER], ["pad", JOY_BUTTON_B]]],
]

## EMPTY, and deliberately present — ADR-0220 dec. 2.
##
## This addon declares no `global uniform` of its own (ADR-0190 / arm 4b) and therefore
## provides none. The five it used to carry — `pixel_aspect`, `psx_dither_enabled`,
## `psx_fx_stretch`, `psx_cursor_stretch`, `psx_camera_angle` — are all declared in
## `addons/exmateria_platform/` and reach this addon's shaders through an `#include`, and
## `addons/exmateria_platform/plugin.gd` now provides all six of that addon's declarations
## (the sixth, `unit_stretch`, was never provided by anyone).
##
## 🔴 THIS ADDON'S INSTALL DEBT DOES NOT MOVE, and that is the load-bearing reading.
## `exmateria_platform` is inside this subject's own install target (ADR-0202 dec. 2), so
## `check_addon_install`'s arm 3 still finds all five provided and still reads 0. If it had
## moved, the five would have been green off this array alone rather than off a target the
## consumer actually gets — which is exactly the confusion ADR-0220 dec. 1 ends.
##
## The old note here argued the opposite — that the port "ships beside" this addon and
## "neither can supply a HOST setting the other one needs". That is false as mechanism:
## `ProjectSettings` is one surface, and `provided_by_walk` already reads EVERY `plugin.gd`
## under a subject's permitted roots. Nothing prevented the port from providing; nothing
## had asked it to.
const PROVIDED_GLOBALS: Array = []

## Only the settings THIS plugin added. Removing on the way out what a consumer declared on
## its own would delete their line from their project file — `exmateria_sound/plugin.gd`'s
## `_added` for the same reason.
var _added: Array[String] = []


func _enter_tree() -> void:
	_added = provide_into(ProjectSettings)
	if not _added.is_empty():
		ProjectSettings.save()


func _exit_tree() -> void:
	revoke_from(ProjectSettings, _added)
	if not _added.is_empty():
		ProjectSettings.save()
	_added.clear()


## Write every name this addon provides that `surface` does not already hold. Returns the
## setting keys actually added, in write order.
##
## 🔴 STATIC, AND IT TAKES THE SURFACE, BECAUSE THAT IS WHAT MAKES IT TESTABLE. ADR-0203
## dec. 4 requires an oracle that calls the registration path directly rather than through
## the editor. A test cannot enable a plugin — and it must never write the REAL
## `ProjectSettings`, because `_enter_tree`'s companion `ProjectSettings.save()` would
## rewrite the repo's own `project.godot`. So the surface is a parameter, the test passes a
## dictionary-backed double, and nothing here touches global state on its own.
##
## `surface` needs `has_setting(String) -> bool` and `set_setting(String, Variant)`, which
## is the slice of `ProjectSettings` this uses and all of it.
##
## The `has_setting` guard is ADR-0203 dec. 2's permitted read: it decides whether this
## addon's own write is needed, which is part of the write, not a runtime configuration read.
static func provide_into(surface) -> Array[String]:
	var added: Array[String] = []
	for entry in PROVIDED_ACTIONS:
		var key: String = INPUT_PREFIX + entry[0]
		if surface.has_setting(key):
			continue
		surface.set_setting(key, {"deadzone": entry[1], "events": _build_events(entry[2])})
		added.append(key)
	for entry in PROVIDED_GLOBALS:
		var key: String = SHADER_GLOBAL_PREFIX + entry[0]
		if surface.has_setting(key):
			continue
		surface.set_setting(key, {"type": entry[1], "value": entry[2]})
		added.append(key)
	return added


## Remove exactly the keys `provide_into` reported adding, and nothing else.
static func revoke_from(surface, keys: Array[String]) -> void:
	for key in keys:
		surface.set_setting(key, null)


## `[[kind, code], …]` -> real `InputEvent`s. Keys bind the PHYSICAL keycode, matching how
## the host declares them, so the layout-independent behaviour survives the provide.
static func _build_events(specs: Array) -> Array:
	var events: Array = []
	for spec in specs:
		if spec[0] == "key":
			var k := InputEventKey.new()
			k.physical_keycode = spec[1]
			events.append(k)
		elif spec[0] == "pad":
			var b := InputEventJoypadButton.new()
			b.button_index = spec[1]
			events.append(b)
	return events


## Every setting key this addon provides — the list ADR-0203 dec. 3's re-pointed register
## arms compare the addon's REQUIREMENTS against. Named here so there is one answer to
## "what does this addon install", rather than two arrays a reader has to union by hand.
static func provided_keys() -> Array[String]:
	var keys: Array[String] = []
	for entry in PROVIDED_ACTIONS:
		keys.append(INPUT_PREFIX + entry[0])
	for entry in PROVIDED_GLOBALS:
		keys.append(SHADER_GLOBAL_PREFIX + entry[0])
	return keys
