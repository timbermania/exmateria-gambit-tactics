extends RefCounted

## The unique↔asset residue manifest (ADR-0072, issue #202).
##
## The small hand-authored bridge that maps a *unique* `Character`'s ROM
## `special_name` — the WHOLE unique [template key] (#199), one token packing
## identity + [Form] — to its owned [template] **folder**. It is the single
## authority for "which special_names are unique": a special_name present here
## is a unique (the [resolver] routes it by `special_name` alone); one absent is
## job-routed (generic). This is the *residue* the [character-alignment
## transform] consumes — the part of the ROM→asset mapping that is NOT cleanly
## derivable, hand-authored beside the flat parser output.
##
## The folders themselves are **derived and regenerable**: the transform (#201)
## emits them under `TEMPLATE_ROOT`, the runtime loaders (#203) read assets from
## them. So `folder_of` returns an *address* — the folder need not exist yet.
##
## Pure data, scene/GPU-agnostic — the same static-load shape as `UnitNames` and
## the other X databases. Source of truth: templates/template_residue.json, which
## ships INSIDE this addon (ADR-0251 dec. 2 — a payload travels beside its reader).

# ADR-0223 dec. 8 / ADR-0217 dec. 16 — `JsonAsset` is the PORT's, not the
# host's: it is a free-function loader with no host state, and leaving it in
# `src/` was goal #5 unmet on the TYPE axis for every addon that called it
# (#809). One alias line per file keeps this file's spelling (ADR-0211 dec. 4).
const JsonAsset = ExMateriaPlatform.JsonAsset

const PATH := "res://addons/exmateria_catalogue/templates/template_residue.json"

## The derived template store's root — every unique's folder lives one level
## below it (`TEMPLATE_ROOT + <token>/`). The transform (#201) owns this tree.
const CatalogueContent = preload("res://addons/exmateria_catalogue/install/CatalogueContent.gd")

# The template store is HOST CONTENT: ROM-derived, regenerable and gitignored, so it
# cannot travel into the addon (ADR-0202 dec. 5). A `static var` and not a `const`
# because the value is read from `ProjectSettings` rather than written here, and every
# call site keeps the spelling it already had.
static var TEMPLATE_ROOT: String = CatalogueContent.resolve(CatalogueContent.TEMPLATES_SUBPATH)

static var _residue: Dictionary = {}   # decimal-special_name String -> folder token String
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_residue = JsonAsset.load_dict(PATH).get("residue", {})


## True iff `special_name` names a unique (has an owned template folder). This is
## the resolver's unique-vs-job-routed dispatch bit — a pure function of the
## materialized `special_name`, no story context (the Form was baked into
## `special_name` upstream at the seeding seam).
static func has(special_name: int) -> bool:
	_ensure_loaded()
	return _residue.has(str(special_name))


## The full `res://` folder path for a unique's [template], or "" if the
## special_name is not a unique. The #203 loaders read assets straight from here.
static func folder_of(special_name: int) -> String:
	_ensure_loaded()
	var token: String = _residue.get(str(special_name), "")
	if token == "":
		return ""
	return TEMPLATE_ROOT + token + "/"
