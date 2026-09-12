extends Node
## The HOST's answer to `addons/exmateria_sprite_rig`'s content port — seven
## forwards and nothing else.
##
## `ExMateriaSpriteRig.ContentPort` declares seven scalar queries and implements
## none of them: it resolves this node by name at call time and asks. That
## inversion is why the addon compiles against no content store of this game's
## (ADR-0203, *an addon provides the names it can and injects the content it
## cannot*; ADR-0215 dec. 6; ADR-0217 dec. 9). This file is the whole of what the
## inversion costs the host, and it is host code by construction — the only place
## where the rig's need and this game's tables appear in the same line.
##
## It is an AUTOLOAD, registered as `SpriteRigContent`, because an `[autoload]`
## line is the one binding a consuming project can write and an addon cannot.
## `AudioHostAdapter` is the same shape for the sound package (ADR-0153 dec. 3).
##
## 🔴 NOTHING ELSE MAY CALL THIS. Host code that wants a job's palette row calls
## `JobDatabase`; this class exists only so the RIG does not have to. A second
## caller would make it an interface, and it is a translation.
##
## 🔴 IT IS BOOKED `content`, NOT `Sprite Rig`. A severance whose fix gets booked
## into the bucket it drains reads as no change at all — ADR-0167's fix first read
## as GROWTH for exactly that reason, and `BattlefieldWiring` was booked
## `assembler` to avoid it. This file holds seven lines of content lookups and no
## rig behaviour, so `content` is where it belongs and where the seven lines stay
## put rather than moving between systems.
##
## Every method here answers for a key it does not hold the way its store already
## does — `0` for a missing row — so the port's ABSENT table and this adapter's
## MISSING-ROW answers agree. `ability_effect_anim_id` is the one exception, and
## the reason is in the port's docstring: `0` is a real answer there.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase
const JobDatabase = ExMateriaAlmanac.JobDatabase
const WeaponGraphicData = ExMateriaAlmanac.WeaponGraphicData
const WeaponZeroFrames = ExMateriaAlmanac.WeaponZeroFrames



# --- the WEP1 sheet, keyed by ROM ITEM id -------------------------------------

## How far down WEP1.tga this weapon's graphics start, in pixels. `item_id` is the
## ROM item id, NOT `items.json`'s `graphic` menu-icon index.
func weapon_v_offset(item_id: int) -> int:
	return WeaponGraphicData.get_v_offset(item_id)


# --- the zero-frame tables, keyed by weapon TYPE id ---------------------------

## The WEP1 sheet's first frame for this weapon type.
func wep1_frame_offset(weapon_type_id: int) -> int:
	return WeaponZeroFrames.get_wep1_offset(weapon_type_id)


## The WEP2 sheet's first frame for this weapon type.
func wep2_frame_offset(weapon_type_id: int) -> int:
	return WeaponZeroFrames.get_wep2_offset(weapon_type_id)


## The EFF1 sheet's first frame for this weapon type.
func eff1_frame_offset(weapon_type_id: int) -> int:
	return WeaponZeroFrames.get_eff1_offset(weapon_type_id)


# --- the job tables, keyed by a JOB id as a lowercase hex STRING --------------

## The sub-palette row this job's colour comes from, unclamped. The record itself
## does not cross the port — only this one field does.
func job_body_palette_row(job_hex: String) -> int:
	return int(JobDatabase.get_job(job_hex).get("body_palette_row", 0))


## Whether this job's parser-emitted `kind` is "monster".
func job_is_monster(job_hex: String) -> bool:
	return JobDatabase.is_monster(job_hex)


# --- the ability table, keyed by ABILITY id -----------------------------------

## This ability's effect-animation id, or `-1` when `ability_id` is negative or
## names no ability. The `AbilityView` this reads is `generated` code and stops
## here: only the `int` crosses.
func ability_effect_anim_id(ability_id: int) -> int:
	if ability_id < 0:
		return -1
	var ability := AbilityDatabase.get_ability_view(ability_id)
	if ability.is_empty():
		return -1
	return int(ability.effect_anim_id)
