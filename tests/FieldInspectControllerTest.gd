extends Node

## FieldInspectController.view_from_unit test — the integration glue that reads
## a live Unit's own components (UnitStats / progression / status) into a
## UnitInfoPresenter view. Uses lightweight fakes so the extraction is testable
## without spawning a full Unit. (The 3D raycast pick + window toggle are
## verified headful in GPUArena.)

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const JobDatabase = ExMateriaAlmanac.JobDatabase


const FieldInspectController = preload("res://src/ui3/FieldInspectController.gd")


class FakeStats extends RefCounted:
	var current_hp := 80
	var max_hp := 100
	var current_mp := 20
	var max_mp := 50


class FakeProg extends RefCounted:
	var level := 5
	var brave := 70
	var faith := 55
	var current_job_id := "4a"   # Squire


class FakeUnit extends Node:
	var unit_stats: FakeStats
	var unit_progression: FakeProg
	var body_sprite_id := 0x05
	var template_folder := "res://assets/characters/templates/ramza_3/"


func _ready() -> void:
	var failed := false

	var unit := FakeUnit.new()
	unit.name = "Ramza"
	unit.unit_stats = FakeStats.new()
	unit.unit_progression = FakeProg.new()
	var status := UnitStatusManager.new()
	status.name = "UnitStatusManager"
	unit.add_child(status)
	status.add_status(&"haste")
	add_child(unit)

	var view: Dictionary = FieldInspectController.view_from_unit(unit)

	# 1. Identity + stats are read from the unit's own components.
	if view.get("name") != "Ramza":
		print("[FAIL] name: %s" % view.get("name")); failed = true
	if view.get("current_hp") != 80 or view.get("max_hp") != 100:
		print("[FAIL] hp: %s/%s" % [view.get("current_hp"), view.get("max_hp")]); failed = true
	if view.get("current_mp") != 20 or view.get("max_mp") != 50:
		print("[FAIL] mp: %s/%s" % [view.get("current_mp"), view.get("max_mp")]); failed = true

	# 2. Progression: level / brave / faith / job name.
	if view.get("level") != 5 or view.get("brave") != 70 or view.get("faith") != 55:
		print("[FAIL] prog: %s" % view); failed = true
	var expected_job = JobDatabase.get_job("4a").get("name", "4a")
	if view.get("job") != expected_job:
		print("[FAIL] job: %s != %s" % [view.get("job"), expected_job]); failed = true

	# 3. Active statuses, capitalized for display.
	if view.get("statuses") != ["Haste"]:
		print("[FAIL] statuses: %s" % str(view.get("statuses"))); failed = true

	# 3b. Portrait sprite id read from the unit's body_sprite_id.
	if view.get("sprite_id") != 0x05:
		print("[FAIL] sprite_id: %s" % str(view.get("sprite_id"))); failed = true

	# 3c. Template folder (OWNED portrait source, #205) read from the unit so the
	# info window can front the flat sprite sheet with a unique's own portrait.tga.
	if view.get("template_folder") != "res://assets/characters/templates/ramza_3/":
		print("[FAIL] template_folder: %s" % str(view.get("template_folder"))); failed = true

	# 4. The view feeds the presenter cleanly (end-to-end).
	var m := UnitInfoPresenter.build(view)
	if m["hp"]["text"] != "80/100":
		print("[FAIL] presenter hp: %s" % m["hp"]); failed = true

	if failed:
		print("[FAIL] FieldInspectController.view_from_unit test")
	else:
		print("[PASS] FieldInspectController.view_from_unit: stats/prog/status -> presenter view")
	get_tree().quit()
