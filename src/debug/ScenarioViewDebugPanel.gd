class_name ScenarioViewDebugPanel
extends BaseDebugPanel

## On-screen debug-overlay toggles for the scenario VIEW gizmos that live on
## `ScenarioPlayerScene` (not the VM): the yellow per-unit facing gizmos (uid/
## facing TEXT label + 3D facing ARROW) and the screen-space COMPASS overlay.
##
## The scene is the source of truth (`show_facing_debug` / `show_compass`,
## also flippable via F6 / the inspector); this panel mirrors + drives those
## properties. `on_shown` re-syncs the checkboxes so an F6 press made while the
## panel was hidden is reflected when it reopens.

const TuneField = preload("res://src/debug/TuneField.gd")

var _scene  # ScenarioPlayerScene

var _facing_cb: CheckBox
var _compass_cb: CheckBox


func setup(scene) -> void:
	_scene = scene
	panel_title = "Scenario View"
	panel_category = Category.SCENARIO_LOOK
	_build_ui()
	# The AUTOSAVE checkboxes already hold the persisted pref (coalesced by TuneField at
	# build); drive the scene FROM them, not the other way, so a remembered toggle applies.
	_push_panel_values_into_scene()


## The panel outlives a scene reload (owned by DebugOverlay); rebind to the
## freshly-booted ScenarioPlayerScene and push the panel's current toggle
## state into it so the user's view choices survive the reload.
func rebind(scene) -> void:
	_scene = scene
	_push_panel_values_into_scene()


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(260, 0)
	add_child(vbox)

	# View-overlay prefs auto-persist (green TuneField, ADR-0068): a gizmo you turned on
	# comes back next launch. This panel OWNS the slugs (it outlives scene reloads, being
	# DebugOverlay-scoped); the scene's show_facing_debug/show_compass are consumers the
	# toggle handler and _push_panel_values_into_scene drive. Default = the scene's own
	# resting value, so a fresh install behaves exactly as before.
	add_section_title(vbox, "Facing gizmos (F6)")
	_facing_cb = TuneField.add(vbox, "Yellow uid/facing text + arrows",
		"scenario_view.show_facing", bool(_scene.show_facing_debug), {},
		Tune.Persist.AUTOSAVE) as CheckBox
	_facing_cb.toggled.connect(_on_facing_toggled)
	_controls["facing"] = _facing_cb

	add_separator(vbox)
	add_section_title(vbox, "Compass")
	_compass_cb = TuneField.add(vbox, "Screen-space N/E/S/W compass",
		"scenario_view.show_compass", bool(_scene.show_compass), {},
		Tune.Persist.AUTOSAVE) as CheckBox
	_compass_cb.toggled.connect(_on_compass_toggled)
	_controls["compass"] = _compass_cb


func on_shown() -> void:
	# An F6 press (or inspector edit) while the panel was hidden can desync the
	# checkboxes from the scene — re-read on every open.
	_sync_from_scene()


func _sync_from_scene() -> void:
	if not is_instance_valid(_scene):
		return
	set_checkbox_value("facing", bool(_scene.show_facing_debug))
	set_checkbox_value("compass", bool(_scene.show_compass))


func _push_panel_values_into_scene() -> void:
	if not is_instance_valid(_scene):
		return
	if _facing_cb != null:
		_scene.show_facing_debug = _facing_cb.button_pressed
	if _compass_cb != null:
		_scene.show_compass = _compass_cb.button_pressed


func _on_facing_toggled(pressed: bool) -> void:
	if is_instance_valid(_scene):
		_scene.show_facing_debug = pressed  # setter repaints the gizmos


func _on_compass_toggled(pressed: bool) -> void:
	if is_instance_valid(_scene):
		_scene.show_compass = pressed  # setter flips the CompassLayer
