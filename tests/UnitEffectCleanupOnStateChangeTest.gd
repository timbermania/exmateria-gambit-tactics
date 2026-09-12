extends Node

## Weapon/effect-sprite cleanup on terminal state change (regression).
##
## Bug: when a unit dies or achieves victory while a weapon (WEP1) / effect
## (EFF1) sprite is on screen — e.g. a mid-swing slash — the secondary layers
## are NOT torn down, so the slash stays frozen on top of the corpse / victor.
##
## Root cause (ADR-0053 Path-D regression): parameterized state changes
## (attack / cast / charge) go through `_apply_resolution()`, which stops the
## wep1/eff1 playbacks AND disables the WEP1/EFF1 layers. Parameterless state
## changes (IDLE / DYING / CELEBRATING / ...) go through `update_animation()` →
## `current_anim_id` setter → `_arm_anim_id_clock()`, which dropped that
## teardown. Because the secondary playbacks are tick-based (advanced by
## CombatLoop.tick), a dead unit / post-victory unit stops getting advance_tick,
## so they never self-complete to fire `_on_eff1_complete` / `_on_wep1_complete`
## — the layer stays enabled forever.
##
## This test spawns a real Unit (the UnitWeaponBindTest fixture), arms the
## WEP1/EFF1 layers to simulate an in-flight slash, then drives each terminal
## transition and asserts the layers are disabled SYNCHRONOUSLY (no _process
## awaited — so the assertion catches the transition's own teardown, not a
## later self-completion that only happens in a standalone delta-mode harness).

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const DisplayActivity = ExMateriaSpriteRig.DisplayActivity

## ADR-0215 dec. 2 / ADR-0217 dec. 7 — the sprite rig's VALUE VOCABULARY is the
## kernel's; the behaviour-bearing hosts keep their class names and their behaviour.
## This line is what keeps the use sites below spelled the way they were
## (ADR-0211 dec. 4).
const SpriteLayer = ExMateriaSchema.SpriteLayer.Kind

const UNIT_SCENE_PATH := "res://assets/scenes/Unit.tscn"
const UnitProgressionClass = ExMateriaAlmanac.UnitProgression

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const JobDatabase = ExMateriaAlmanac.JobDatabase

const CHEMIST_JOB := "4b"
const BLAZE_GUN := 74


func _ready() -> void:
	var failed := false

	failed = await _run_case("death", failed)
	failed = await _run_case("victory", failed)

	if failed:
		print("[FAIL] UnitEffectCleanupOnStateChangeTest")
	else:
		print("[PASS] UnitEffectCleanupOnStateChangeTest: WEP1/EFF1 torn down on death + victory")
	get_tree().quit()


func _run_case(trigger: String, failed_so_far: bool) -> bool:
	var failed := failed_so_far
	var unit = await _make_unit()
	if unit == null:
		print("[FAIL] %s: could not spawn unit fixture" % trigger)
		return true

	# Arm the secondary layers: simulate a weapon slash currently on screen.
	if not _arm_effect(unit):
		print("[FAIL] %s: fixture has no wep1/eff1 seqs to arm" % trigger)
		unit.queue_free()
		return true

	# Precondition: both layers are enabled (the slash is visible).
	failed = _expect(unit.material.get_shader_parameter("wep_enable") == true,
		"%s: precondition WEP1 enabled" % trigger, failed)
	failed = _expect(unit.material.get_shader_parameter("eff_enable") == true,
		"%s: precondition EFF1 enabled" % trigger, failed)

	# Trigger the terminal transition (synchronous: the activity setter runs
	# update_animation() inline via the activity_changed signal).
	match trigger:
		"death":
			unit._on_unit_died()
		"victory":
			unit.activity = DisplayActivity.Activity.CELEBRATING

	# The player rotates the camera over the dead/victorious unit. This repaints
	# every layer for the new view (a constant gameplay event). If the secondary
	# playbacks were not STOPPED by the transition, this re-enables the frozen
	# slash — the user-reported symptom.
	unit._render_camera_variant()

	# Assert: the slash must be gone after the transition — no _process awaited.
	failed = _expect(unit.material.get_shader_parameter("wep_enable") == false,
		"%s: WEP1 disabled after transition (slash removed)" % trigger, failed)
	failed = _expect(unit.material.get_shader_parameter("eff_enable") == false,
		"%s: EFF1 disabled after transition (slash removed)" % trigger, failed)

	unit.queue_free()
	return failed


func _make_unit():
	var unit_scene: PackedScene = load(UNIT_SCENE_PATH)
	var unit = unit_scene.instantiate()
	unit.body_sprite_id = JobDatabase.get_sprite_id(CHEMIST_JOB, true)
	add_child(unit)
	await get_tree().process_frame  # let @onready + _ready sprite-init run

	var prog = UnitProgressionClass.new()
	prog.initialize(UnitProgressionClass.BaseStatType.FEMALE, CHEMIST_JOB)
	prog.equipment[UnitProgressionClass.EquipSlot.RIGHT_HAND] = BLAZE_GUN
	unit.bind_progression(prog, UnitStats.Team.ENEMY)
	await get_tree().process_frame
	if not unit._initialized or unit.animation_set == null or unit.material == null:
		return null
	return unit


func _arm_effect(unit) -> bool:
	"""Put a weapon + effect sprite on screen, the way a mid-swing attack does."""
	var wep_keys: Array = unit.animation_set.wep_seq.keys()
	var eff_keys: Array = unit.animation_set.eff1_seq.keys()
	if wep_keys.is_empty() or eff_keys.is_empty():
		return false
	unit.display.wep1_playback.start(str(wep_keys[0]), unit.animation_set.wep_seq)
	unit.display.eff1_playback.start(str(eff_keys[0]), unit.animation_set.eff1_seq)
	unit.sprite_layers.enable_layer(SpriteLayer.WEP1, true)
	unit.sprite_layers.enable_layer(SpriteLayer.EFF1, true)
	return true


func _expect(cond: bool, label: String, failed_so_far: bool) -> bool:
	if not cond:
		print("[FAIL] %s" % label)
		return true
	print("[ok] %s" % label)
	return failed_so_far
