@tool
extends EditorPlugin
## ExMateria Sprite Rig — Godot editor plugin entry.
##
## There is nothing to install here that this file can install. The rig is
## reached two ways, and neither is an editor registration: the SYMBOL channel is
## `ExMateriaSpriteRig.<Name>` — a constant on the addon's one global name
## (ADR-0212 dec. 1) — and the SCENE channel is a DECLARED MOUNT,
## `assets/scenes/Unit.tscn`, which names the rig by `ext_resource` path
## (ADR-0217 dec. 3). A host writes both; an addon cannot ship a root scene
## (ADR-0134), and this project enables no plugin at all — `project.godot` has no
## `[editor_plugins]` section — so wiring anything to `_enter_tree` would make
## the rig's availability depend on a switch nobody has thrown.
##
## This file exists so the directory is a real addon with a promotion path
## (ADR-0121 dec. 7 / ADR-0139 dec. 10), not so it does work.

func _enter_tree() -> void:
	pass

func _exit_tree() -> void:
	pass
