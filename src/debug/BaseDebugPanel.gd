class_name BaseDebugPanel
extends PanelContainer
## Base class for all debug panels in the DebugOverlay system.
##
## Provides:
## - Common _gui_input() that consumes mouse events and handles ESC for focus clear
## - Helper methods for building UI (separators, labels, collapsible sections)
## - Focus management integration with DebugOverlay
## - "Print Values" button helper

## Category for organizing panels in the overlay's tab bar.
##
## 🔴 THE VALUES ARE WRITTEN OUT AND 6 IS A HOLE, and this enum is one of THREE copies
## (`DebugOverlay.gd`, `DebugDashboard.gd`) that must agree integer-for-integer — a panel
## sets `panel_category` from THIS one and `DebugOverlay` looks the panel up by that
## integer. `STRATEGY = 6` was the deployment march's placement panel, retired by
## ADR-0258; deleting it from an implicitly-valued copy would renumber `ROSTER`..`STORY`
## in that copy ALONE and route every panel below it to the wrong tab, with nothing to
## say so. 6 is not reused.
enum Category {
	GENERAL = 0,      # Junk drawer / fallback default. Avoid registering new panels here.
	DESIGNER = 1,     # UI Designer tool panels
	CAMERA = 2,       # Camera controls
	FONT = 3,         # Font mapping tools
	SKIRTS = 4,       # Land skirt debugging
	LOGGING = 5,      # Logging toggle controls
	# 6 — was STRATEGY, the strategy-phase placement controls (ADR-0258). Not reused.
	ROSTER = 7,       # Unit progression and roster (collection-level)
	PROJECTILE = 8,   # Projectile tuning controls
	EFFECTS = 9,      # Effect viewer controls
	SHADERS = 10,     # Shader calibration + per-system shader debug
	SCENARIO = 11,    # Scenario picker (map + battle music selection)
	SIMULATION = 12,  # Time scale + RNG seed + run-with-seed
	DISPLAY = 13,     # PSX display toggles (dither, PAR, viewport, depth-vis)
	UNIT = 14,        # Single-unit live-control surfaces (animation viewer, caster/target control)
	TILES = 15,       # Range-overlay tile look, per highlight type
	PERFORMANCE = 16, # FPS / frame-time / spike log + corner HUD toggle
	CURSOR = 17,      # Tile-cursor dagger pose / palette / blend controls
	AUDIO = 18,       # Sound / SPU tuning (music + SFX + typewriter-click de-click)
	SCENARIO_PLAYBACK = 19,  # Scenario VM disassembly + stepping (instruction playback)
	SCENARIO_LOOK = 20,      # Scenario on-screen look (view gizmos, weather, dialogue box, cinematic scrub)
	TUNABLES = 21,           # Generated tunable dashboard — one auto-card per Tune slug (ADR-0068)
	STORY = 22,              # The DERIVED story spine — order, seek state, roster (ADR-0216)
	STATE = 23               # The live STATE census — one row per mechanism (ADR-0177 Am. 3)
}

## The category this panel belongs to (set in subclass)
var panel_category: Category = Category.GENERAL

## Title displayed in the overlay when this panel is shown
var panel_title: String = "Debug Panel"

## Dictionary for storing control references (SpinBoxes, etc.)
var _controls: Dictionary = {}


func _gui_input(event: InputEvent) -> void:
	# Consume mouse button events so they don't propagate to game
	if event is InputEventMouseButton:
		accept_event()
		return

	# ESC clears focus from any control within this panel
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		var focused = get_viewport().gui_get_focus_owner()
		if focused and is_ancestor_of(focused):
			focused.release_focus()
			accept_event()


## Called when the panel is registered with DebugOverlay.
## Override in subclasses to perform additional setup.
func on_registered() -> void:
	pass


## Called when the panel becomes visible in the overlay.
## Override to refresh data when panel is shown.
func on_shown() -> void:
	pass


#region Process gate

## A debug panel is a VIEW: its `_process` refreshes what a reader is looking at,
## so it must not run when nobody is looking. Two things conspire to run it anyway,
## and BOTH have to be answered here rather than per panel (W13 / #955):
##
## 1. **The engine arms it.** `Node`'s `NOTIFICATION_READY` calls `set_process(true)`
##    for any script that defines `_process`, *before* `_ready` runs. A
##    `set_process(false)` in a builder that runs before the node enters the tree —
##    which is how every panel here is constructed (`new()`, `setup()`, then
##    `register_panel()`) — is therefore inert.
## 2. **Registration arms it.** `DebugDashboard.add_panel()` calls `on_shown()`
##    unconditionally when a panel is registered, whether or not the dashboard
##    Window is visible.
##
## That is why `AudioBusMixerDebugPanel` metered every `AudioServer` bus every frame
## of every session with the F3 window closed, at 0.064–0.103 ms/frame — more than
## all 13 units' `_process` put together (`docs/GPU-ARENA-PERF.md` → W5, W13). There
## was an `on_hidden()` hook that would have stopped it; it had **no caller anywhere
## in the repo**, so it read as a gate while being none.
##
## The gate is `is_visible_in_tree()`, and it is strictly stronger than that hook
## pair could be. A panel is hidden by any of FOUR things — the dashboard Window,
## the header's page switcher, its category cell's fold, and its own per-panel fold
## — and `on_shown()`/`on_hidden()` can only ever see the first.
## `is_visible_in_tree()` sees all four, and `NOTIFICATION_VISIBILITY_CHANGED`
## reaches this panel for all four (`CanvasItem::_handle_visibility_change` recurses
## into child canvas items; `CanvasItem::_window_visibility_changed` is what carries
## a Window's hide down into them).
##
## Panels with no `_process` are unaffected — `set_process` on them is a no-op.

## Opt out of the gate. Set this in a subclass whose `_process` DRIVES THE GAME
## rather than refreshing a view: that work is not the reader's, and it must not
## stop when the reader looks away. Exactly one panel qualifies today
## (`ScenarioUnitSpriteOffsetDebugPanel`, which re-applies its sprite-offset
## overrides every frame); anything that only repaints its own labels does not.
var processes_while_hidden: bool = false


func _notification(what: int) -> void:
	# NOT `_ready()`: a subclass overriding `_ready` would replace it, whereas
	# GDScript dispatches `_notification` to every script in the inheritance chain.
	# (No subclass defines either today — this keeps that from becoming a trap.)
	if what == NOTIFICATION_READY or what == NOTIFICATION_VISIBILITY_CHANGED:
		_sync_process_to_visibility()


func _sync_process_to_visibility() -> void:
	if processes_while_hidden:
		return
	set_process(is_visible_in_tree())

#endregion


#region UI Building Helpers

## Add a horizontal separator with standard spacing
func add_separator(parent: Control) -> HSeparator:
	var sep = HSeparator.new()
	sep.custom_minimum_size.y = 6
	parent.add_child(sep)
	return sep


## Add a simple text label
func add_label(parent: Control, text: String, min_width: float = 0) -> Label:
	var label = Label.new()
	label.text = text
	if min_width > 0:
		label.custom_minimum_size.x = min_width
	parent.add_child(label)
	return label


## Add a section title with larger font
func add_section_title(parent: Control, text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	parent.add_child(label)
	return label


## Create a titled section. Historically this was a collapsible (toggle button +
## fold). Per ADR-0035, sections now render flat — a bold title label sits above
## an always-visible VBoxContainer the caller fills. The `start_open` argument
## is kept for source compatibility with ~20 existing call sites and ignored.
func create_collapsible_section(parent: Control, title: String, _start_open: bool = true) -> VBoxContainer:
	var outer = VBoxContainer.new()
	parent.add_child(outer)

	var title_label = Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 13)
	outer.add_child(title_label)

	var content = VBoxContainer.new()
	outer.add_child(content)

	return content


## Create a REAL collapsible section — a toggle header button above a content
## VBoxContainer that folds. The ADR-0035 dec. 6 scoped exception for
## oversized calibration panels (40+ rows): one fold per TARGET GAME PANEL, so
## the section titles read as a table of contents. Folded by default. Small
## panels keep using the flat create_collapsible_section below.
func add_fold_section(parent: Control, title: String, start_open: bool = false) -> VBoxContainer:
	var outer = VBoxContainer.new()
	parent.add_child(outer)

	var toggle = Button.new()
	toggle.toggle_mode = true
	toggle.button_pressed = start_open
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.add_theme_font_size_override("font_size", 13)
	outer.add_child(toggle)

	var content = VBoxContainer.new()
	content.visible = start_open
	outer.add_child(content)

	var refresh = func() -> void:
		toggle.text = ("▾  " if toggle.button_pressed else "▸  ") + title
		content.visible = toggle.button_pressed
	toggle.toggled.connect(func(_on: bool) -> void: refresh.call())
	refresh.call()
	return content


## Add a "Print Values" button that calls _on_print_values() when pressed
func add_print_values_button(parent: Control, text: String = "Print Values") -> Button:
	var btn = Button.new()
	btn.text = text
	btn.pressed.connect(_on_print_values)
	parent.add_child(btn)
	return btn


## Add a centered button row container
func add_button_row(parent: VBoxContainer) -> HBoxContainer:
	var btn_container = HBoxContainer.new()
	btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(btn_container)
	return btn_container

#endregion


#region Control Value Helpers

## Set a SpinBox value without triggering the signal
func set_spinbox_value(key: String, value: float) -> void:
	var sb = _controls.get(key) as SpinBox
	if sb:
		sb.set_value_no_signal(value)


## Get a SpinBox value
func get_spinbox_value(key: String, default: float = 0.0) -> float:
	var sb = _controls.get(key) as SpinBox
	if sb:
		return sb.value
	return default


## Set a CheckBox state without triggering the signal
func set_checkbox_value(key: String, value: bool) -> void:
	var cb = _controls.get(key) as CheckBox
	if cb:
		cb.set_pressed_no_signal(value)


## Get a CheckBox state
func get_checkbox_value(key: String, default: bool = false) -> bool:
	var cb = _controls.get(key) as CheckBox
	if cb:
		return cb.button_pressed
	return default

#endregion


## Override this method to implement "Print Values" functionality
func _on_print_values() -> void:
	print("")
	print("=" .repeat(50))
	print("# %s values" % panel_title)
	print("=" .repeat(50))
	print("# (Override _on_print_values() to add content)")
	print("=" .repeat(50))
	print("")
