extends Node3D

## Standalone headful harness for the Formation START sub-menu (§15.20).
##
## Mounts a settled [DetailScene] (the screen the menu opens ON TOP of), then overlays a
## [StartActionMenu] lifted above it and plays the §15.17 box-open once. A thin iteration
## vehicle (NOT a test): eyeball the frame / 5 rows / "Menu" title / glove cursor + the
## center-out reveal against the committed oracle states formation_startmenu_ss{0,1,2,3}.
##
## Controls: ↑/↓ move the selection, Enter confirms (prints the row), Backspace cancels.
## Run: <GODOT> --path . res://src/ui3/detail/StartActionMenu.tscn

const DetailSceneClass = preload("res://src/ui3/detail/DetailScene.gd")
const StartActionMenu = preload("res://src/ui3/detail/StartActionMenu.gd")
const FormationScene = preload("res://src/ui3/formation/FormationScene.gd")
const UIUnitNameplate = preload("res://src/ui3/UIUnitNameplate.gd")
const Character = ExMateriaCatalogue.Character
var _menu: StartActionMenu


func _ready() -> void:
	var c: Character = Character.create_default("Ramza", "4a", false)
	c.progression.brave = 70
	c.progression.faith = 70

	var detail: DetailScene = DetailSceneClass.new()
	detail.name = "DetailScreen"
	detail.autoplay_open = false                # keep the detail screen settled behind the menu
	add_child(detail)
	detail.set_unit_view(FormationScene.vitals_view_from_character(c))
	detail.set_nameplate_view(UIUnitNameplate.view_from_character(c, 1))
	detail.set_stats_view(DetailSceneClass.stats_view_from_character(c))

	_menu = StartActionMenu.new()
	_menu.name = "StartActionMenu"
	# The menu's fold real-Z base (DEFAULT_MENU_RUNG=32) already sits above the detail overlay
	# (top total 28) and under the camera-clip rung — the @export default is correct here.
	add_child(_menu)
	_menu.chosen.connect(func(r): print("[StartActionMenu] chosen row %d = %s" % [r, StartActionMenu.ROWS[r]]))
	_menu.cancelled.connect(func(): print("[StartActionMenu] cancelled"))
	print("[StartActionMenu] mounted over the Status screen; box-open playing (↑/↓ move, Enter confirm, Backspace cancel)")


func _unhandled_input(event: InputEvent) -> void:
	if _menu == null or not is_instance_valid(_menu):
		return
	if event.is_action_pressed("ui_down"):
		_menu.move_down()
	elif event.is_action_pressed("ui_up"):
		_menu.move_up()
	elif event.is_action_pressed("ui_accept"):
		_menu.confirm()
	elif event.is_action_pressed("ui_cancel"):
		_menu.cancel()
