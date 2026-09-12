class_name GambitDeployDebugPanel
extends BaseDebugPanel
## F3 → Simulation: [GambitBattle]'s deployment conveniences. One row today —
## **Auto-place squad**, the "stop hand-placing five units on every reload" toggle.
##
## A VIEW, not an owner (ADR-0068 decision 12): the slug is
## [constant DebugConfig.GAMBIT_AUTO_DEPLOY_SLUG], bound AUTOSAVE by `DebugConfig` at
## boot, and this row passes no `default_value` — so it renders green (sticks on every
## edit, no Pin) and registers nothing itself.
##
## The toggle is LIVE, and that is the host's doing rather than this panel's: `GambitBattle`
## subscribes to the slug with `Tune.on_update`, so ticking the box while the deployment is
## still open fills the zone right now, and the same subscription's boot-time apply is what
## fills it on the NEXT load. This panel therefore has no button and no host reference — it
## writes a tunable and the host reacts, which is why it survives a scene reload it is not
## part of.
##
## Registered by `GambitBattle` alone (nothing else has a deployment), so it is absent from
## the F3 window of every other scene.

const TuneField = preload("res://src/debug/TuneField.gd")


func setup() -> void:
	panel_title = "Deployment"
	panel_category = Category.SIMULATION
	_build_ui()


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(220, 0)
	add_child(root)

	TuneField.add(root, "Auto-place squad", DebugConfig.GAMBIT_AUTO_DEPLOY_SLUG)
	_wrapped(root, "Fills the deployment zone with the first units of the roster, in zone-table order. It does NOT start the battle — edit the placements as usual and press Space.")


## A word-wrapped description label capped to the panel width. Same shape as
## `SimulationDebugPanel._wrapped`, this cell's neighbour.
func _wrapped(parent: Control, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(210, 0)
	label.add_theme_font_size_override("font_size", 10)
	parent.add_child(label)
	return label
