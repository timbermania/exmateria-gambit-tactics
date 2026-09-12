@tool
extends EditorPlugin
## ExMateria Catalogue — Godot editor plugin entry.
##
## **It registers one autoload, and that is this addon's whole install step.**
## `CharacterCatalog` is the live registry of who exists — 34 host lines and 161
## test lines name it, in 63 files — and a registry has to be a singleton. The
## script travels with the addon (ADR-0262 dec. 6: leaving the system's centre
## behind inverts the extraction), so the addon is what registers it:
##
##   CharacterCatalog   registry/CharacterCatalog.gd   — the slug-keyed registry
##
## The shape is `addons/exmateria_sound/plugin.gd`'s verbatim, including the
## reason for the `has_setting` test: a consumer that would rather declare the
## line itself still can — `godot-learning` does, to keep its own autoload ORDER
## explicit, and `autoload_route_reaches` exempts the name on the `res://` path
## that line carries — but it must use this name, because the addon's own files
## reach `/root/CharacterCatalog` by node path.
##
## Everything else in this addon is reached through `ExMateriaCatalogue`, the one
## `class_name` it declares (ADR-0212 dec. 1). See README.md for the public API
## and for the content root the host must supply.

const AUTOLOADS := [
	["CharacterCatalog", "res://addons/exmateria_catalogue/registry/CharacterCatalog.gd"],
]

## Only the ones THIS plugin added. Removing on the way out what a consumer
## declared on its own would delete their line from their project file.
var _added: Array[String] = []


func _enter_tree() -> void:
	for entry in AUTOLOADS:
		# A consumer that already declares the name (the in-repo game does, to
		# keep its own autoload order explicit) must not get a duplicate.
		if not ProjectSettings.has_setting("autoload/" + entry[0]):
			add_autoload_singleton(entry[0], entry[1])
			_added.append(entry[0])


func _exit_tree() -> void:
	for name in _added:
		remove_autoload_singleton(name)
	_added.clear()
