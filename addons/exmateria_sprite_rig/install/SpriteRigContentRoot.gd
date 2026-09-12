extends RefCounted

## The addon's ONE injection point for host content it can never ship — ADR-0202 dec. 5's
## "settable search root with a default", built a second time for this addon (#744,
## 2026-09-01). `addons/exmateria_battlefield/install/BattlefieldContent.gd` is the
## original and this is deliberately its shape, down to the empty default and the
## once-per-run refusal.
##
## WHAT THIS IS FOR. Nine `res://assets/…` literals sat in this addon's code after the
## move: the WEP1/EFF1 texture+palette pairs, the SEQ/SHP animation tree, the layer
## priority table, the EVTCHR cutscene tree, and the crystal sheet. ADR-0215 dec. 7 books
## every one of them **Class B — gitignored, un-shippable**, so "move it into the addon"
## was never available. The addon stops NAMING `res://assets/` and takes a root from the
## host; the dependency survives as a documented contract, and P4 scores the literal
## rather than the dependency.
##
## 🔴 THE DEFAULT IS EMPTY, ON PURPOSE. A default of `res://assets/` would leave the
## literal in an addon file, so `check_addon_portability` would still score it and P4
## would not reach 0 — the fix booked into the bucket it drains. Empty means `resolve()`
## refuses, once, in words that name the setting.
##
## 🔴 THIS IS NOT THE CONTENT PORT, AND THE TWO ARE NOT INTERCHANGEABLE. `ContentPort`
## (ADR-0217 dec. 9) is seven SCALAR QUERIES about a combatant — what a ROM item id's
## weapon graphic is — answered by a host adapter that knows FFT. This is a DIRECTORY the
## host keeps its ROM rips in. A rig with a content root and no adapter renders sprites
## and knows nothing about jobs; a rig with an adapter and no root knows about jobs and
## renders nothing. Naming them apart is why this file is `…ContentRoot` and not a third
## thing called `SpriteRigContent` (which is already the host adapter, in `src/data/`).
##
## THE HOST'S SIDE. `godot-learning/project.godot` declares
## `exmateria_sprite_rig/content_root="res://assets/"`. A stranger project either declares
## its own or gets the refusal below.

## The `ProjectSettings` key a host points at its ROM-derived content tree. A directory
## path; a trailing slash is supplied by `resolve()` so a host may write it either way.
const ROOT_SETTING: String = "exmateria_sprite_rig/content_root"

## Subpaths BELOW the root. These are not `res://` literals and are not P4's business —
## they are the shape of the tree the contract describes, named here rather than at nine
## call sites so the contract has one address.
const ANIMATIONS_SUBPATH: String = "sprites/animations/"
const LAYER_PRIORITY_SUBPATH: String = "sprites/layer_priority.json"
const TEXTURES_SUBPATH: String = "sprites/textures/"
const WEP1_TEX_SUBPATH: String = "sprites/textures/WEP1.tga"
const WEP1_PALETTE_SUBPATH: String = "sprites/textures/WEP1.palette.tga"
const EFF1_TEX_SUBPATH: String = "sprites/textures/EFF1.tga"
const EFF1_PALETTE_SUBPATH: String = "sprites/textures/EFF1.palette.tga"
const EVTCHR_TEX_SUBPATH: String = "sprites/textures/evtchr/"
const EVTCHR_FRAMES_SUBPATH: String = "sprites/animations/evtchr_frames.json"
const CRYSTAL_SHEET_SUBPATH: String = "sprites/textures/crystal/crystal_sheet.png"
const ANIMATION_NAMES_SUBPATH: String = "sprites/animation_names.json"

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
## `FileAccess.open("sprites/…")` quietly resolving against the process's working
## directory. The refusal is reported ONCE per run — a `push_error` per layer per frame
## would bury it.
static func resolve(subpath: String) -> String:
	var base: String = root()
	if base.is_empty():
		if not _unset_reported:
			_unset_reported = true
			push_error(
				"ExMateria Sprite Rig: no content root. This addon needs ROM-derived "
				+ "content it cannot ship (the SEQ/SHP animation tree, the WEP1/EFF1 "
				+ "texture and palette atlases, the EVTCHR cutscene tree, the crystal "
				+ "sheet), so a host must declare `" + ROOT_SETTING + "` in "
				+ "project.godot, pointing at the directory holding its `"
				+ ANIMATIONS_SUBPATH + "` and `" + TEXTURES_SUBPATH + "` trees. Until "
				+ "then no unit sprite will composite. See the addon README, \"Content "
				+ "the host must supply\"."
			)
		return ""
	return base + subpath


## `res://…/sprites/animations/` — the per-sprite SEQ/SHP JSON tree. `""` when unset.
static func animations_dir() -> String:
	return resolve(ANIMATIONS_SUBPATH)


## `res://…/sprites/textures/` — the ROM-ripped sheet tree the viewer indexes by name.
## `""` when unset.
static func textures_dir() -> String:
	return resolve(TEXTURES_SUBPATH)
