extends RefCounted
## The rig's CONTENT PORT — seven scalar queries, four key spaces, and no record.
##
## The sprite rig does not know what a combatant IS. It asks for numbers keyed by
## FFT ids and it owns the pixels (ADR-0215 dec. 6, restated by ADR-0217 dec. 9).
## Seven call sites used to name four host content stores — `WeaponGraphicData`,
## `WeaponZeroFrames`, `JobDatabase`, `AbilityDatabase` — and every one of them was
## a pure query, so they collapse to one port the host adapts rather than four
## dependencies the addon carries.
##
## 🔴 **THIS IS KEYED BY FOUR DIFFERENT THINGS, NOT BY "FFT ID".** A ROM **item**
## id, a weapon **type** id, a **job** id as a lowercase hex string, and an
## **ability** id are four disjoint spaces that happen to share a numeric shape.
## `SpriteLayerManager` already carries a standing warning about exactly this
## collision — the WEP1 table is keyed by ROM item id and NOT by `items.json`'s
## `graphic` menu-icon index, and *wrong key samples the wrong row*. A signature
## that said `id` seven times would make that hazard permanent and hand it to
## readers who cannot ask, so **the key kind is carried in every parameter name**
## and the port is deliberately NOT split into four classes: the parameter names
## make the distinction the type names would only duplicate.
##
## Nothing here is instantiated. This class is a namespace of statics.
##
## ## How the binding works
##
## The same NODE-PATH soft-bind `addons/exmateria_platform/tunables/TunePort.gd`
## uses, and for the same two reasons (ADR-0175 dec. 2, ADR-0203 dec. 2). An
## `[autoload]` line can only be written by the consuming game's `project.godot`,
## so naming the host's adapter directly would be a host-project-configuration
## dependency; resolving it by name at CALL time is an addon-presence dependency
## instead. It is not a compile-time edge, so nothing here loads host code, and it
## gives the port a defined ABSENT behaviour — which is what makes this addon
## installable in a project that has no FFT content at all.
##
## 🔴 **ABSENT IS THE ANSWER AN EMPTY CONTENT SET GIVES — except for one query.**
##
## | query | with the adapter | without it |
## |---|---|---|
## | `weapon_v_offset` | the WEP1 row | `0` |
## | `wep1_frame_offset` | the WEP1 sheet's zero frame | `0` |
## | `wep2_frame_offset` | the WEP2 sheet's zero frame | `0` |
## | `eff1_frame_offset` | the EFF1 sheet's zero frame | `0` |
## | `job_body_palette_row` | the job's authored row | `0` |
## | `job_is_monster` | the job's parsed `kind` | `false` |
## | `ability_effect_anim_id` | the ability's field | **`-1`** |
##
## The first six answer `0` because `0` is what the host's own stores answer for a
## key they do not hold — an unshifted sheet and a default palette row, which is a
## drawable sprite rather than a crash. `ability_effect_anim_id` is the one query
## where **`0` is a real answer**: an ability with no cast animation reports 0, and
## `AnimationResolutionMap` branches on `> 0` to fall back to the per-sprite pose.
## So "no such ability" needs a sentinel `0` cannot be confused with, and `-1` is
## the one that call site already used.
##
## ## What is NOT here
##
## No content record, view or dictionary crosses this port. Two of the four shapes
## were "id → dict" only in their spelling: one call fetched an `AbilityView` and
## read a single field, another fetched a job record and read one key. Both now
## return the scalar, which is why `AbilityView` — `generated` code — is no longer
## named anywhere in the rig.
##
## Run the contract test with `tests/SpriteRigContentPortTest.gd`, which drives
## this port against the real content and asserts each query BY VALUE against a
## known row, so swapping two key spaces fails on a number rather than typechecking.


## The name the host's adapter is registered under. A consuming project supplies
## its own script at this autoload name; nothing about the file behind it is this
## addon's business, and only the seven verbs below are.
const ADAPTER_NODE := ^"SpriteRigContent"

## Resolved adapter, or `null`. Cached because these queries run per unit per
## layer per frame and a `get_node_or_null` + `has_method` on that path is not
## free. Never caches a NEGATIVE result: the adapter can appear later, and it can
## be replaced between tests.
static var _adapter: Node = null


## The live adapter, or `null` when this addon is installed in a project that does
## not supply one.
##
## Two rejections, not one — the shape `TunePort._resolve` documents. `null` is the
## ordinary absent case; a node that resolves but has no `job_is_monster` is the
## EDITOR case, where a non-`@tool` autoload is instantiated as a placeholder that
## answers to the name and carries none of the script's methods. `has_method` is
## what separates them.
static func _resolve() -> Node:
	if _adapter != null and is_instance_valid(_adapter):
		return _adapter
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	var root: Window = (loop as SceneTree).root
	if root == null:
		return null
	var n := root.get_node_or_null(ADAPTER_NODE)
	if n == null or not n.has_method(&"job_is_monster"):
		return null
	_adapter = n
	return n


## Test seam: forget the cached resolution so the next call re-resolves.
##
## The cache is keyed on `is_instance_valid`, which is a question about the OBJECT
## and not about the LOOKUP — a node that has been renamed or reparented is still
## "valid" and the cache still answers with it, while `_resolve()` would now fail.
## A test that wants to observe the absent path has to say so.
static func _forget_adapter() -> void:
	_adapter = null


# --- the WEP1 sheet, keyed by ROM ITEM id -------------------------------------

## How far down WEP1.tga this weapon's graphics start, in pixels.
##
## 🔴 `item_id` is the **ROM item id**, NOT `items.json`'s `graphic` field, which
## is the menu-icon index and a separate concept. Wrong key samples the wrong row.
static func weapon_v_offset(item_id: int) -> int:
	var a := _resolve()
	if a == null:
		return 0
	return int(a.weapon_v_offset(item_id))


# --- the zero-frame tables, keyed by weapon TYPE id ---------------------------
#
# A weapon TYPE id is not an item id: it names the animation family (knife, bow,
# staff…), and the three sheets each hold their own zero frame for it. The WEP SEQ
# animations use relative frame ids, and these offsets are what turn one into the
# actual SHP frame.

## The WEP1 sheet's first frame for this weapon type.
static func wep1_frame_offset(weapon_type_id: int) -> int:
	var a := _resolve()
	if a == null:
		return 0
	return int(a.wep1_frame_offset(weapon_type_id))


## The WEP2 sheet's first frame for this weapon type. TYPE2 sprites draw from
## WEP2.tga, which has different frame boundaries — it is not WEP1's number.
static func wep2_frame_offset(weapon_type_id: int) -> int:
	var a := _resolve()
	if a == null:
		return 0
	return int(a.wep2_frame_offset(weapon_type_id))


## The EFF1 sheet's first frame for this weapon type.
static func eff1_frame_offset(weapon_type_id: int) -> int:
	var a := _resolve()
	if a == null:
		return 0
	return int(a.eff1_frame_offset(weapon_type_id))


# --- the job tables, keyed by a JOB id as a lowercase hex STRING --------------
#
# `job_hex` is a string, not a number: `"4a"`, `"5e"`, `"60"`. The host's store
# lowercases what it is handed, so case does not matter, but the WIDTH does — the
# key is two hex digits and `"4"` is not `"04"`.

## The sub-palette row this job's colour comes from — the JOB axis on its own,
## unclamped, straight out of the authored table (SCUS 0x2E, ADR-0022).
##
## Monsters carry their variant row here (Yellow Chocobo 0 / Black 1 / Red 2) and
## `special` non-humanoid jobs carry a real row too, while every humanoid job
## carries 0 because its default palette is baked at SPR row 0.
static func job_body_palette_row(job_hex: String) -> int:
	var a := _resolve()
	if a == null:
		return 0
	return int(a.job_body_palette_row(job_hex))


## Whether this job is a monster (parser-derived `kind`, ADR-0013).
##
## ⚠️ INDEPENDENT of `job_body_palette_row`. A `special` job such as the Holy
## Dragon carries a non-zero row and is NOT a monster, so neither query can be
## derived from the other.
static func job_is_monster(job_hex: String) -> bool:
	var a := _resolve()
	if a == null:
		return false
	return bool(a.job_is_monster(job_hex))


# --- the ability table, keyed by ABILITY id -----------------------------------

## This ability's effect-animation id, or `-1` when `ability_id` is negative or
## names no ability.
##
## 🔴 `0` AND `-1` ARE DIFFERENT ANSWERS. `0` means the ability exists and has no
## cast animation; `-1` means there is no such ability. `AnimationResolutionMap`
## branches on `> 0`, so both fall back — but only one of them is a missing row,
## and collapsing them would hide a bad id behind a legitimate value.
static func ability_effect_anim_id(ability_id: int) -> int:
	var a := _resolve()
	if a == null:
		return -1
	return int(a.ability_effect_anim_id(ability_id))
