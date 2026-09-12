extends RefCounted

## The addon's ONE injection point for host content it can never ship — ADR-0202 dec. 5's
## "settable search root with a default", built to `exmateria_battlefield`'s shape
## (`install/BattlefieldContent.gd`) verbatim. That file's own grounds are ADR-0202 dec. 5
## and ADR-0203 dec. 1 ("PROVIDE for names; INJECT for content"), and they are this file's
## grounds too — a content root is content, so it is injected and not provided.
##
## WHAT THIS IS FOR. Three of the membership's seven arm-6 rows name a `res://assets/`
## tree that CANNOT travel into the addon, and both trees fail the same test —
## `git check-ignore` names them, `git ls-files` does not:
##
##   assets/characters/templates/   ROM-derived, regenerable, emitted by the #201
##                                  character-alignment transform. 2 rows
##                                  (`templates/ResidueManifest.gd`,
##                                  `seeding/AllTemplatesSeeder.gd`).
##   assets/sprites/textures/       shared with `exmateria_sprite_rig`, two rig scenes,
##                                  `src/core/AssetManifest.gd`, `addons/exmateria_effects/trap/TrapEffect.gd`,
##                                  `src/projectiles/Projectile3D.gd` and
##                                  `src/ui3/elements/NumberFont.gd`. 1 row.
##
## ADR-0262 dec. 9 read the first of those as a payload that TRAVELS and named only the
## second as immovable. It is gitignored and untracked on every worktree in this repo, so
## "move it into the addon" was never available for it either — dec. 5's Class B exactly.
## The four payloads that ARE tracked did travel and sit beside their readers
## (`identity/unit_names.json`, `identity/unit_birthdays.json`,
## `templates/template_residue.json`, `seeding/template_jobs.json`), which is
## ADR-0251 dec. 2's rule and is why they are not this file's business.
##
## 🔴 THE DEFAULT IS EMPTY, ON PURPOSE, AND THAT IS THE WHOLE DESIGN — copied from
## `BattlefieldContent.gd`, which says why: a default of `res://assets/` would leave the
## literal in an addon file, so arm 6 would still score it and the three rows would not
## reach 0 — the fix would be booked into the bucket it drains (ADR-0167). It would also
## re-create the failure dec. 5 names: a bare project silently resolving paths that do not
## exist and loading nothing. Empty means `resolve()` refuses, once, in words that name
## the setting.
##
## THE HOST'S SIDE. `godot-learning/project.godot` declares
## `exmateria_catalogue/content_root="res://assets/"`. It is the THIRD such key in that
## file, beside `[exmateria_battlefield]` and `[exmateria_sprite_rig]`, and it is a
## separate key rather than a read of the rig's on the precedent of the two that are
## already there, and on ADR-0203 dec. 1's split: reading a SIBLING addon's key would
## make this addon depend on that addon being installed for a reason that has nothing to
## do with what it calls, and a host that installs the catalogue alone would then have a
## key it cannot find named in an error it did not cause.

## The `ProjectSettings` key a host points at its ROM-derived content tree. A directory
## path; a trailing slash is supplied by `resolve()` so a host may write it either way.
const ROOT_SETTING: String = "exmateria_catalogue/content_root"

## Subpaths BELOW the root. These are not `res://` literals and are not arm 6's business —
## they are the shape of the tree the contract describes, named here rather than at the
## call sites so the contract has one address.
const TEMPLATES_SUBPATH: String = "characters/templates/"
const TEXTURES_SUBPATH: String = "sprites/textures/"

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


## `root() + subpath`, or `""` with ONE `push_error` naming the setting when no host has
## declared a root. The refusal is once per run rather than per call: a formation rebuild
## asks for a template folder per cell, and an unset root would otherwise print thousands
## of identical lines and bury the one that matters.
static func resolve(subpath: String) -> String:
	var r := root()
	if r.is_empty():
		if not _unset_reported:
			_unset_reported = true
			push_error(
				"ExMateria Catalogue: no content root. This addon needs ROM-derived "
				+ "content it cannot ship (the character template store and the flat "
				+ "body sheets), so a host must declare `" + ROOT_SETTING + "` in "
				+ "project.godot, pointing at the directory holding its `"
				+ TEMPLATES_SUBPATH + "` and `" + TEXTURES_SUBPATH + "` trees. Until "
				+ "then the formation catalogue view lists nothing. See the addon "
				+ "README, \"Content the host must supply\"."
			)
		return ""
	return r + subpath
