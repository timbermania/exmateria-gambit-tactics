extends RefCounted

## The single seam between disk JSON and runtime `UnitAnimationSet`.
##
## Lazy `_ensure_loaded` shape (the JobDatabase / SpriteDatabase
## convention). One entry point: `get_set(seq_type, shp_type)` returns
## a cached `UnitAnimationSet`; two same-typed units share one instance.
##
## SEQ-file `op_code_id` annotation lives inside `_load_json` and fires
## unconditionally for every `_seq.json` — there is no second path that
## could load a SEQ without it. This retires the duplicate-loading-path
## bug class CLAUDE.md's Common Mistakes table documents.
##
## See ADR-0034 and CONTEXT.md "### Animation playback".
## Vault: [[Unit Sprite Render Pipeline]]
## Vault: [[Weapon Animation System]]

# ADR-0223 dec. 8 — this line USED to name `JsonAsset` where `src/data/`
# declared it, which is ARM7_BURN_DOWN #809 and goal #5 unmet on the TYPE
# axis. The file moved to the port; naming the port is what a portable addon
# is ALLOWED to do (ADR-0139 dec. 12, `plugin.cfg` `deps=`), and the spelling
# below is unchanged (ADR-0212 dec. 1).
const JsonAsset = ExMateriaPlatform.JsonAsset

# ADR-0212 dec. 1 — the class is INTERNAL to this addon: no global `class_name`,
# so an in-addon consumer preloads the file it wants.
const UnitAnimationSet = preload("res://addons/exmateria_sprite_rig/sequence/UnitAnimationSet.gd")

## `AnimationOpcodes` is `addons/exmateria_sprite_rig`'s now, published on the
## addon's one global name; this aliases it back so every use site below keeps
## the spelling it had (ADR-0211 dec. 4, ADR-0217 dec. 6).
const AnimationOpcodes = ExMateriaSpriteRig.AnimationOpcodes

const ContentRoot = preload("res://addons/exmateria_sprite_rig/install/SpriteRigContentRoot.gd")

## The SEQ/SHP tree and the layer-priority table are Class B — ROM-derived and gitignored
## — so they are resolved against the host's content root rather than addressed (#744,
## ADR-0215 dec. 7). Both are `""` in a project that declared no root, and `_get_json`
## already treats an unreadable path as an empty table.

# Cache of fully-built sets, keyed by "{seq_type}::{shp_type}".
static var _sets: Dictionary = {}

# Per-file JSON cache so the eight shared layers (wep1, wep2, eff1,
# layer_priority, *_names) are read from disk once across all sets.
static var _json_cache: Dictionary = {}


static func get_set(seq_type: String, shp_type: String) -> UnitAnimationSet:
	var seq_key := seq_type.to_lower()
	var shp_key := shp_type.to_lower()
	var set_key := "%s::%s" % [seq_key, shp_key]

	if _sets.has(set_key):
		return _sets[set_key]

	var anims := UnitAnimationSet.new()

	anims.type1_seq = _get_typed_json(seq_key, "_seq.json", true)
	anims.type1_shp = _get_typed_json(shp_key, "_shp.json", false)

	anims.is_type2 = (shp_key == "type2")
	if anims.is_type2:
		anims.wep_seq = _get_json(ContentRoot.animations_dir() + "wep2_seq.json")
		anims.wep_shp = _get_json(ContentRoot.animations_dir() + "wep2_shp.json")
	else:
		anims.wep_seq = _get_json(ContentRoot.animations_dir() + "wep1_seq.json")
		anims.wep_shp = _get_json(ContentRoot.animations_dir() + "wep1_shp.json")

	anims.eff1_seq = _get_json(ContentRoot.animations_dir() + "eff1_seq.json")
	anims.eff1_shp = _get_json(ContentRoot.animations_dir() + "eff1_shp.json")
	anims.layer_priority = _get_json(ContentRoot.resolve(ContentRoot.LAYER_PRIORITY_SUBPATH))

	# Per-slot animation labels live in AnimationNames, not on this set.

	_sets[set_key] = anims
	return anims


static func clear_cache() -> void:
	_sets.clear()
	_json_cache.clear()


# Loads `{key}{suffix}` from the content root's animations dir; falls back to `type1{suffix}` for
# unknown unit types (preserving the prior loader's behaviour, with a
# warning).
static func _get_typed_json(key: String, suffix: String, is_seq: bool) -> Dictionary:
	var path := ContentRoot.animations_dir() + key + suffix
	var data := _get_json(path)
	if not data.is_empty():
		return data

	var kind := "SEQ" if is_seq else "SHP"
	push_warning("[AnimationDatabase] %s data not found for '%s', falling back to type1" % [kind, key])
	return _get_json(ContentRoot.animations_dir() + "type1" + suffix)


static func _get_json(path: String) -> Dictionary:
	if _json_cache.has(path):
		return _json_cache[path]

	var data := _load_json(path)
	_json_cache[path] = data
	return data


static func _load_json(path: String) -> Dictionary:
	# JsonAsset absorbs the open/parse/error boilerplate; the SEQ opcode
	# annotation below is this loader's own concern and stays here.
	var data := JsonAsset.load_dict(path)
	if path.ends_with("_seq.json"):
		for anim_id_str in data:
			var opcodes: Variant = data[anim_id_str]
			if opcodes is Array:
				for op in opcodes:
					if op is Dictionary and op.has("op_code_name"):
						op["op_code_id"] = AnimationOpcodes.from_string(op["op_code_name"])
	return data
