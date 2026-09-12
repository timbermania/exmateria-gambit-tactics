class_name LoggingDebugPanel
extends BaseDebugPanel
## Toggles the DebugConfig logging flags. Each row is a shared TuneField bound to the
## flag's `debug.*` Tune slug (ADR-0068 move 2): blue accent label, right-click
## Pin/Reset, and auto-synced with the same slug anywhere else (the generated Tunables
## dashboard, or another panel showing it). DebugConfig OWNS the value; this panel is
## just a view (decision 12) — no hand-rolled checkbox/sync machinery.

const TuneField = preload("res://src/debug/TuneField.gd")

# (row label, flag name) grouped under a section header. The slug is `debug.<flag>`
# and the flag's code default is false, both matching the DebugConfig property.
const SECTIONS := [
	["UI / Iteration", [
		["Iteration Debug", "iteration_debug_enabled"],
	]],
	["Camera & Map", [
		["Camera Debug", "camera_debug_enabled"],
		["Map Debug", "map_debug_enabled"],
	]],
	["Effects System", [
		["Screen Debug", "screen_debug_enabled"],
		["Palette Debug", "palette_debug_enabled"],
		["Particle Debug", "particle_debug_enabled"],
		["Timeline Debug", "timeline_debug_enabled"],
		["Emitter Debug", "emitter_debug_enabled"],
	]],
	["Animation & Misc", [
		["Action/Anim Debug", "action_debug_enabled"],
		["Transition Debug", "transition_debug_enabled"],
		["Reaction Debug", "reaction_debug_enabled"],
		["GPU Debug", "gpu_debug_enabled"],
	]],
]


func setup() -> void:
	panel_title = "Logging"
	panel_category = Category.LOGGING
	_build_ui()


func _build_ui() -> void:
	# Panels never scroll internally — the DebugDashboard wraps everything in one
	# outer ScrollContainer (ADR-0035). Just stack the rows flat.
	var container = VBoxContainer.new()
	container.add_theme_constant_override("separation", 2)
	add_child(container)

	add_section_title(container, "Debug Logging Flags")
	add_separator(container)

	var first := true
	for section in SECTIONS:
		if not first:
			add_separator(container)
		first = false
		_add_category_label(container, section[0])
		for row in section[1]:
			# TuneField owns the whole row: coalescing read, two-way binding to the
			# slug, accent/dirty markers, and the Pin/Reset menu.
			TuneField.add(container, row[0], "debug.%s" % row[1], false)

	add_separator(container)
	var btn_row = add_button_row(container)
	var enable_all_btn = Button.new()
	enable_all_btn.text = "Enable All"
	enable_all_btn.pressed.connect(_on_set_all.bind(true))
	btn_row.add_child(enable_all_btn)
	var disable_all_btn = Button.new()
	disable_all_btn.text = "Disable All"
	disable_all_btn.pressed.connect(_on_set_all.bind(false))
	btn_row.add_child(disable_all_btn)


func _add_category_label(parent: Control, text: String) -> void:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	parent.add_child(label)


## Enable/Disable All write each slug through Tune; every bound row (here + the
## dashboard) resyncs off the resulting value_changed, so the blue checkboxes update
## and DebugConfig reflects the new state — no manual checkbox walk.
func _on_set_all(on: bool) -> void:
	for section in SECTIONS:
		for row in section[1]:
			Tune.set_value("debug.%s" % row[1], on)
