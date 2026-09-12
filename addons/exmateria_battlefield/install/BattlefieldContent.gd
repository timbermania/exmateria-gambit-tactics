extends RefCounted

## The addon's ONE injection point for host content it can never ship — ADR-0202 dec. 5's
## "settable search root with a default", built.
##
## WHAT THIS IS FOR. Nine rows of the install register (ADR-0202 Class B) were
## `res://assets/…` literals sitting in addon code: the map tree, the doodad tree, and the
## `RANGETILE` texture/palette/manifest trio. All of it is ROM-derived and gitignored, so
## "move it into the addon" was never available — dec. 5 says so and says the fix instead:
## the addon stops NAMING `res://assets/` and takes a root from the host. The dependency
## survives as a documented contract; the register scores the literal, not the dependency.
##
## 🔴 THE DEFAULT IS EMPTY, ON PURPOSE, AND THAT IS THE WHOLE DESIGN. A default of
## `res://assets/` would leave the literal in an addon file, so arm 1 would still score it
## and the nine rows would not reach 0 — the fix would be booked into the bucket it drains.
## It would also re-create the failure dec. 5 names by name: a bare project would silently
## resolve paths that do not exist and load nothing. Empty means `resolve()` refuses, once,
## in words that name the setting — dec. 5's *"a legible failure instead of a silent empty
## load"*.
##
## THE READ IS **INJECT**, NOT THE READ ADR-0203 dec. 2 FORBIDS, and the two look alike
## enough to be worth separating here. dec. 2's forbidden direction is an addon sourcing
## from `ProjectSettings` configuration **it could have authored itself** — that is what
## PROVIDE is for, and it is why classes D and E move into `plugin.gd` instead. A content
## root is the opposite case: the addon cannot author where a host keeps its ROM rips, so
## the host is the only possible source. ADR-0203 dec. 1 blesses exactly this for Class B
## ("the literal goes, a settable search root stays") in the same breath as dec. 2.
##
## THE HOST'S SIDE. `godot-learning/project.godot` declares
## `exmateria_battlefield/content_root="res://assets/"`. A stranger project either declares
## its own or gets the refusal above. The claim lives in the addon README under ADR-0202
## dec. 4, because an install step nobody wrote down is one somebody re-derives by crash.

## The `ProjectSettings` key a host points at its ROM-derived content tree. A directory
## path; a trailing slash is supplied by `resolve()` so a host may write it either way.
const ROOT_SETTING: String = "exmateria_battlefield/content_root"

## Subpaths BELOW the root. These are not `res://` literals and are not the register's
## business — they are the shape of the tree the contract describes, and they are named
## here rather than at four call sites so the contract has one address.
const MAPS_SUBPATH: String = "maps/"
const DOODADS_SUBPATH: String = "doodads/"
const RANGE_TEX_SUBPATH: String = "sprites/textures/RANGETILE.tga"
const RANGE_PALETTE_SUBPATH: String = "sprites/textures/RANGETILE.palette.tga"
const RANGE_MANIFEST_SUBPATH: String = "sprites/textures/RANGETILE.json"

static var _unset_reported: bool = false


## The configured content root, normalised to a trailing slash. `""` when the host has not
## declared one — callers get that through `resolve()` rather than reading this directly.
static func root() -> String:
	var raw: String = str(ProjectSettings.get_setting(ROOT_SETTING, ""))
	if raw.is_empty():
		return ""
	return raw if raw.ends_with("/") else raw + "/"


## `true` when a host has pointed the addon at its content tree.
static func has_root() -> bool:
	return not root().is_empty()


## Resolve a subpath against the content root, or `""` if no host declared one.
##
## Returns `""` rather than a half-formed `res://`-less path so that every caller's own
## existence check fails the way it already fails for a missing file, instead of a
## `DirAccess.open("maps/")` quietly resolving against the process's working directory.
## The refusal is reported ONCE per run — `push_error` per tile per frame would bury it.
static func resolve(subpath: String) -> String:
	var base: String = root()
	if base.is_empty():
		if not _unset_reported:
			_unset_reported = true
			push_error(
				"ExMateria Battlefield: no content root. This addon needs ROM-derived "
				+ "content it cannot ship (map tree, doodad tree, RANGETILE atlas), so a "
				+ "host must declare `" + ROOT_SETTING + "` in project.godot, "
				+ "pointing at the directory holding its `" + MAPS_SUBPATH + "`, `"
				+ DOODADS_SUBPATH + "` and `sprites/textures/` trees. Until then maps, "
				+ "doodads and the cursor/overlay tile will not load. See the addon "
				+ "README, \"Content the host must supply\"."
			)
		return ""
	return base + subpath


## `res://…/maps/` — the MAP### tree. `""` when unset.
static func maps_dir() -> String:
	return resolve(MAPS_SUBPATH)


## `res://…/doodads/` — hand-crafted doodads. `""` when unset.
static func doodads_dir() -> String:
	return resolve(DOODADS_SUBPATH)


## The ROM-ripped range-tile atlas. `""` when unset.
static func range_tex_path() -> String:
	return resolve(RANGE_TEX_SUBPATH)


## The atlas's palette LUT. `""` when unset.
static func range_palette_path() -> String:
	return resolve(RANGE_PALETTE_SUBPATH)


## The atlas's UV manifest, which seeds the overlay crop. `""` when unset.
static func range_manifest_path() -> String:
	return resolve(RANGE_MANIFEST_SUBPATH)
