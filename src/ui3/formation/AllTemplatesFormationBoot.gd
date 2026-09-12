extends Node3D

## Standalone headful harness for the formation "show all templates" view (ADR-0081).
##
## Seeds one owned Character per body-bearing template ([AllTemplatesSeeder]) and mounts a
## [FormationScene] bound to that full owned roster — ↓/↑ scroll the row window through all
## ~156 sheets. A thin iteration vehicle (NOT a test): it just wires the seeder to the view.
##
## Run: <GODOT> --path . res://assets/scenes/AllTemplatesFormation.tscn

const FormationSceneClass = preload("res://src/ui3/formation/FormationScene.gd")
const AllTemplatesSeeder = ExMateriaCatalogue.AllTemplatesSeeder


func _ready() -> void:
	CharacterCatalog.reset_to_new_game()
	var owned_count := AllTemplatesSeeder.seed()

	var form: FormationScene = FormationSceneClass.new()
	form.name = "Formation"
	# Inject BEFORE entering the tree so _ready builds straight from the injected,
	# SCROLLABLE list. Since ADR-0180 the self-discovery fallback reads the same owned
	# overlay, but unwindowed — entering first would build a first frame from its
	# leading 8 and leave a stale non-template vitals panel behind.
	form.set_owned_characters(CharacterCatalog.owned_units())
	add_child(form)
	# HOST-side panel mount (#1267). This file is booked `assembler`, not `UI`
	# (`classify_blueprint.py`, ADR-0135 dec. 10), so it may name `src/debug/`.
	FormationDebugPanels.register_formation_panels(form)

	print("[AllTemplatesFormation] seeded %d owned templates; window shows %d/%d" %
		[owned_count, FormationSceneClass.ROWS * FormationSceneClass.COLS, owned_count])
