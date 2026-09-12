extends Node

## Weapon-sprite-on-bind regression test.
##
## Guards the bug where a roster-spawned Unit rendered every equipped weapon as
## a dagger: Unit._ready()'s sprite-init runs update_weapon_sprite() BEFORE the
## roster binds the progression (ADR-0005 bind-by-reference), so the weapon id
## resolved to -1, no weapon texture loaded, and _wep1_frame_offset stayed at 0
## (the type-0 Knife frames). equipment_changed only fires on later changes, not
## on the initial bind, so the gun never appeared. The fix re-runs
## update_weapon_sprite() inside _attach_progression once equipment is known.
##
## This test instantiates a real Unit, lets _ready() run with NO progression
## (reproducing the early sprite-init), then binds a progression that equips a
## gun, and asserts the weapon frame offset reflects the gun rather than the
## unbound default. No GPU/RenderingDevice or SPU dependency.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const WeaponAnimationSelector = ExMateriaSpriteRig.WeaponAnimationSelector

const UNIT_SCENE_PATH := "res://assets/scenes/Unit.tscn"
const UnitProgressionClass = ExMateriaAlmanac.UnitProgression

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const ItemDatabase = ExMateriaAlmanac.ItemDatabase
const JobDatabase = ExMateriaAlmanac.JobDatabase

const CHEMIST_JOB := "4b"
const BLAZE_GUN := 74          # item_type_id 10 (Gun)
const GUN_TYPE_ID := 10


func _ready() -> void:
	var failed := false

	# 1. Instantiate a real Unit and let _ready() run with NO progression bound.
	#    This is the moment the bug bit: sprite-init's update_weapon_sprite() sees
	#    no equipped weapon and leaves the WEP1 layer on the Knife frames.
	var unit_scene: PackedScene = load(UNIT_SCENE_PATH)
	var unit = unit_scene.instantiate()
	unit.body_sprite_id = JobDatabase.get_sprite_id(CHEMIST_JOB, true)  # female chemist (Sera)
	add_child(unit)
	await get_tree().process_frame  # let @onready + _ready sprite-init run

	var offset_before: int = unit.display._wep1_frame_offset
	print("[INFO] weapon frame offset before bind (no progression): %d" % offset_before)

	# 2. Build the durable progression a roster entry would hold: a chemist with a
	#    gun seeded into the weapon slot (the save/create_default seeding shape).
	var prog = UnitProgressionClass.new()
	prog.initialize(UnitProgressionClass.BaseStatType.FEMALE, CHEMIST_JOB)
	prog.equipment[UnitProgressionClass.EquipSlot.RIGHT_HAND] = BLAZE_GUN

	# Sanity-guard the fixture against item-data drift: id 74 must still be a Gun.
	var resolved_type := ItemDatabase.get_item_type_id(BLAZE_GUN)
	if resolved_type != GUN_TYPE_ID:
		print("[FAIL] fixture drift: item %d resolved to type %d, expected Gun (%d)" % [
			BLAZE_GUN, resolved_type, GUN_TYPE_ID])
		failed = true

	# 3. Bind the progression the way the roster does after spawn.
	unit.bind_progression(prog, UnitStats.Team.ENEMY)

	# 4. After bind, the weapon offset must reflect the equipped gun, not the
	#    unbound default. Computed from the unit's own WEP2-ness so the assertion
	#    holds for TYPE1 and TYPE2 sprites alike.
	var uses_wep2: bool = unit.animation_set.is_type2 if unit.animation_set else false
	var expected_offset := WeaponAnimationSelector.get_wep_frame_offset(GUN_TYPE_ID, uses_wep2)

	if expected_offset == 0:
		print("[FAIL] gun frame offset table returned 0 — table regression for type %d" % GUN_TYPE_ID)
		failed = true

	var offset_after: int = unit.display._wep1_frame_offset
	if offset_after != expected_offset:
		print("[FAIL] weapon frame offset after bind = %d, expected gun offset %d (uses_wep2=%s). Weapon sprite did not load on bind." % [
			offset_after, expected_offset, str(uses_wep2)])
		failed = true

	unit.queue_free()

	if failed:
		print("[FAIL] UnitWeaponBind test")
	else:
		print("[PASS] UnitWeaponBind: equipped gun loads its WEP frames on progression bind (offset %d)" % offset_after)
	get_tree().quit()
