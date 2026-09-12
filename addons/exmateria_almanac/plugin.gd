@tool
extends EditorPlugin
## ExMateria Almanac — Godot editor plugin entry.
##
## There is nothing to install. The almanac is a set of types published on the
## `ExMateriaAlmanac` façade (ADR-0212 dec. 1) and thirteen JSON payloads its
## own databases load by `res://addons/exmateria_almanac/...` path; it registers
## no autoload, no singleton and no editor UI. A table that installed itself
## into the host would be a port, not a table.
##
## This file exists so the directory is a real addon with a promotion path
## (ADR-0121 dec. 7 / ADR-0139 dec. 10), not so it does work.

func _enter_tree() -> void:
	pass

func _exit_tree() -> void:
	pass
