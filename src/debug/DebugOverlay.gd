@tool
extends Node
## DebugOverlay - Thin Node-autoload that owns the BIG debug window.
##
## Per ADR-0035, the debug UI is a separate OS-level Window (the
## DebugDashboard) — not an in-viewport CanvasLayer overlay. This autoload's
## job shrank to:
##   - Owning the DebugDashboard Window child
##   - Routing register_panel(panel, category) into the dashboard's grid
##   - Toggling visibility from F3 (via DebugConfig.debug_overlay_visible)
##   - Persisting window geometry to UserSettings.debug_window
##
## Usage:
##   DebugOverlay.register_panel(my_panel, DebugOverlay.Category.UI)
##   DebugOverlay.show_overlay()
##   DebugOverlay.hide_overlay()

## Tab categories — mirrored on DebugDashboard so callers don't have to chase
## load order.
## 🔴 THE INTEGER VALUES ARE WRITTEN OUT, AND 6 IS A HOLE. `STRATEGY = 6` was the
## deployment march's placement panel and ADR-0258 retired it; every surviving member
## keeps the value it has always had, because `DebugConfig.debug_overlay_active_tab`
## persists a tab as a bare integer and a renumber would silently move the tab a user
## last had open. 6 is not reused.
##
## `TAB_NAMES` is a Dictionary keyed by these and NOT a positional Array, for the same
## reason: an Array indexed by the enum value is only correct while the values are
## dense, which is exactly the coupling this hole would have broken silently.
enum Category {
	GENERAL = 0, DESIGNER = 1, CAMERA = 2, FONT = 3, SKIRTS = 4, LOGGING = 5,
	# 6 — was STRATEGY (ADR-0258). Not reused.
	ROSTER = 7, PROJECTILE = 8, EFFECTS = 9, SHADERS = 10, SCENARIO = 11,
	SIMULATION = 12, DISPLAY = 13, UNIT = 14, TILES = 15, PERFORMANCE = 16,
	CURSOR = 17, AUDIO = 18, SCENARIO_PLAYBACK = 19, SCENARIO_LOOK = 20,
	TUNABLES = 21, STORY = 22, STATE = 23,
}

const TAB_NAMES: Dictionary = {
	Category.GENERAL: "General", Category.DESIGNER: "Designer", Category.CAMERA: "Camera",
	Category.FONT: "Font", Category.SKIRTS: "Skirts", Category.LOGGING: "Logging",
	Category.ROSTER: "Roster", Category.PROJECTILE: "Projectile", Category.EFFECTS: "Effects",
	Category.SHADERS: "Shaders", Category.SCENARIO: "Scenario", Category.SIMULATION: "Simulation",
	Category.DISPLAY: "Display", Category.UNIT: "Unit", Category.TILES: "Tiles",
	Category.PERFORMANCE: "Performance", Category.CURSOR: "Cursor", Category.AUDIO: "Audio",
	Category.SCENARIO_PLAYBACK: "Scenario Playback", Category.SCENARIO_LOOK: "Scenario Look",
	Category.TUNABLES: "Tunables", Category.STORY: "Story", Category.STATE: "State",
}

const _DEBUG_DASHBOARD_SCRIPT = preload("res://src/debug/DebugDashboard.gd")

## The STATE census (ADR-0177 Amendment 3). Registered by THIS autoload and not by a host,
## which is the whole of what makes it present in every scene — the census is most useful
## exactly where nobody thought to wire a panel, and the four Orbonne bugs were found on a
## host that had no state instrument at all.
##
## It is safe to preload from an autoload because it references NO game class: `Focus` is an
## autoload, and everything else it reads is duck-typed off the live tree or comes through the
## host's `debug_battle_state()` seam. A `TurnDirector.` / `GameState.` spelling on it would
## drag the GPU packer and the walk's enum into every scene's load closure.
const _STATE_PANEL_SCRIPT = preload("res://src/debug/StateDebugPanel.gd")

## Registered panels organized by category (mirror of what's in the dashboard).
var _panels: Dictionary = {
	Category.GENERAL: [],
	Category.DESIGNER: [],
	Category.CAMERA: [],
	Category.FONT: [],
	Category.SKIRTS: [],
	Category.LOGGING: [],
	Category.ROSTER: [],
	Category.PROJECTILE: [],
	Category.EFFECTS: [],
	Category.SHADERS: [],
	Category.SCENARIO: [],
	Category.SIMULATION: [],
	Category.DISPLAY: [],
	Category.UNIT: [],
	Category.TILES: [],
	Category.PERFORMANCE: [],
	Category.CURSOR: [],
	Category.AUDIO: [],
	Category.SCENARIO_PLAYBACK: [],
	Category.SCENARIO_LOOK: [],
	Category.TUNABLES: [],
	Category.STORY: [],
	Category.STATE: []
}

var _dashboard: Window  # DebugDashboard instance; built lazily in _ready


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	_dashboard = _DEBUG_DASHBOARD_SCRIPT.new()
	add_child(_dashboard)
	# Restore persisted geometry + UI scale.
	var dw: Dictionary = UserSettings.debug_window
	_dashboard.position = Vector2i(int(dw.position_x), int(dw.position_y))
	_dashboard.size = Vector2i(int(dw.size_x), int(dw.size_y))
	_dashboard.apply_ui_scale(float(dw.get("ui_scale", 1.0)))
	_dashboard.window_geometry_changed.connect(_on_dashboard_geometry_changed)
	_dashboard.ui_scale_changed.connect(_on_dashboard_ui_scale_changed)
	# Restore folded category cells from last session, then listen for changes.
	# Applied before any panels register — collapse state lives on the cell's
	# Content VBox, which persists across a panel registering into the cell.
	for cat in dw.get("collapsed_categories", []):
		_dashboard.set_category_collapsed(int(cat), true)
	_dashboard.category_collapsed_changed.connect(_on_category_collapsed_changed)
	# DebugConfig is the source of truth for the visibility flag; the dashboard
	# follows it.
	if DebugConfig:
		DebugConfig.debug_overlay_toggled.connect(_on_overlay_toggled)
		# Honor last-session state if the user closed the game while it was open.
		if dw.was_visible:
			DebugConfig.debug_overlay_visible = true
		# ...and honor a flag that was already true before this autoload existed to hear
		# the toggle. `--debug-overlay` is set in `DebugConfig`'s own `_ready`, one
		# autoload earlier, so the signal fired into nothing; the setter then swallows a
		# second write as a no-op. Read the flag instead of waiting to be told.
		if DebugConfig.debug_overlay_visible:
			_on_overlay_toggled(true)
			# Say so, and say it with the OS's own count. An open-vs-closed timing arm
			# whose "open" side never mapped a second window measures nothing, and a
			# blind instrument's zero reads exactly like an absent effect (W4).
			print("[DebugOverlay] dashboard shown on boot: visible=%s os_windows=%d" % [
				_dashboard.visible, DisplayServer.get_window_list().size()])
	_register_state_panel()


## Stand up the STATE census panel. Find-or-create against `_panels`, for the same reason
## `NavigatorMain._register_debug_panels` is: this autoload survives a `reload_current_scene`,
## and a second copy of a live-view panel is two pollers of the same eight mechanisms.
func _register_state_panel() -> void:
	for panel in _panels[Category.STATE]:
		if is_instance_valid(panel):
			return
	var state_panel = _STATE_PANEL_SCRIPT.new()
	state_panel.setup()
	register_panel(state_panel, Category.STATE, "state")


func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return

	# F3 toggles dashboard visibility
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		toggle_overlay()
		get_viewport().set_input_as_handled()


#region Visibility

func _on_overlay_toggled(shown: bool) -> void:
	if _dashboard == null:
		return
	if shown:
		_dashboard.show()
		# Don't grab_focus() — on X11 / XWayland it triggers a WM round-trip
		# that has caused BadWindow X errors on Hyprland. The user can click
		# the dashboard to focus it.
		#
		# Showing a separate OS Window (ADR-0035) makes the WM hand keyboard
		# focus TO the dashboard, which then swallows gameplay keys — Space
		# pause, Enter, etc. route to the dashboard window instead of the
		# game's _unhandled_input. That's the "pause doesn't work at the start
		# but works once I click the game" bug. Hand focus straight back to the
		# main game window. Deferred so it lands after the WM finishes mapping
		# and focusing the freshly-shown dashboard.
		_return_focus_to_game.call_deferred()
	else:
		_dashboard.hide()


## Return OS keyboard focus to the main game window so gameplay keys keep
## flowing to the scene's _unhandled_input after the dashboard is shown.
func _return_focus_to_game() -> void:
	var main_window := get_tree().root
	if main_window:
		main_window.grab_focus()


func show_overlay() -> void:
	DebugConfig.debug_overlay_visible = true


func hide_overlay() -> void:
	DebugConfig.debug_overlay_visible = false


func toggle_overlay() -> void:
	DebugConfig.debug_overlay_visible = not DebugConfig.debug_overlay_visible

#endregion


#region Panel registration

## Register a debug panel with the dashboard. Adds it to the cell for the
## given category; every cell is visible at once (no tabs).
##
## `catalog_id` names the [DebugPanelIds] entry this panel is, when it is one. It is what
## the user's on/off choice is keyed by and what makes a re-callable mount idempotent; a
## bespoke mount (a scene's own tool surface, the audio tab) passes nothing and is simply
## not a catalogue entry. The id is stamped on the panel rather than held in a side table so
## it survives `unregister_panel` finding the panel by identity.
##
## 🔴 THIS FUNCTION IS THE GATE, AND THAT IS WHY IT IS HERE AND NOT IN A MOUNT. The gate
## used to live inside `CombatPanelCatalog._wanted()` — one host-specific mount, reached by
## the two scenes that `extends CombatHost` and by nothing else. Every other screen's panels
## were hand-registered with no id, so `set_panel_enabled("map", false)` was a silent no-op
## on `NavigatorMain`: its Skirts panel came up anyway, because nothing on the path from
## `.new()` to the dashboard ever asked. Moving the question to the seam every panel already
## passes through is what makes a NEW panel unable to escape the switchboard — the only way
## out is to pass no id, which is a deliberate, listed choice (see [DebugPanelIds]).
##
## A refused panel is FREED, not returned: every caller of this function builds the panel
## immediately before the call and holds it in a local (the sites that keep a field for
## their panel are exactly the bespoke ones, which pass no id and so can never be refused),
## so leaving it unparented and unreferenced would leak one orphan Node per scene reload.
##
## Returns whether the panel was registered.
func register_panel(panel, category: Category = Category.GENERAL, catalog_id: String = "") -> bool:
	if catalog_id != "" and not is_panel_enabled(catalog_id):
		if panel is Node and panel.get_parent() == null:
			panel.queue_free()
		if DebugConfig.iteration_debug_enabled:
			print("[DebugOverlay] Panel refused (switched off): %s" % catalog_id)
		return false

	if panel.has_method("set"):
		panel.set("panel_category", category)
	if catalog_id != "":
		panel.set_meta(CATALOG_ID_META, catalog_id)
		note_catalog_id(catalog_id)
	_panels[category].append(panel)

	if _dashboard:
		_dashboard.add_panel(panel, category)

	if DebugConfig.iteration_debug_enabled:
		var title = panel.get("panel_title") if panel.get("panel_title") else "Unknown"
		print("[DebugOverlay] Registered panel: %s (category: %s)" % [title, TAB_NAMES[category]])
	return true


## Unregister a debug panel from the dashboard.
func unregister_panel(panel) -> void:
	var category = panel.get("panel_category") if panel.get("panel_category") != null else Category.GENERAL
	_panels[category].erase(panel)
	# Forget the catalogue id too, or a re-mount after a scene reload sees the id still
	# claimed and silently skips the panel — the "green because it stopped looking" shape,
	# which here would present as a panel that vanishes for the rest of the session.
	if panel is Object and panel.has_meta(CATALOG_ID_META):
		_mounted_catalog_ids.erase(String(panel.get_meta(CATALOG_ID_META)))
	if _dashboard:
		_dashboard.remove_panel(panel, category)


#region Catalogue ids and the user's on/off set

## Metadata key under which a catalogue-mounted panel carries its entry id.
const CATALOG_ID_META := "catalog_id"

## Catalogue ids currently mounted. `CombatPanelCatalog.mount()` reads this to skip what is
## already up, which is what lets a host call it twice (at `_ready`, then again once the
## roster exists) without stacking duplicates.
var _mounted_catalog_ids: Dictionary = {}

## Rebuild-the-mount hook, set by `CombatPanelCatalog.mount` and bound to the host that
## called it. Turning an entry back ON re-runs the mount, and the catalogue's idempotence
## means only the missing entries are built. Invalid once the host is freed — a toggle on a
## screen with no combat host simply records the preference for next time.
var _catalog_remount: Callable = Callable()

func note_catalog_id(id: String) -> void:
	_mounted_catalog_ids[id] = true

func has_catalog_id(id: String) -> bool:
	return _mounted_catalog_ids.has(id)

func set_catalog_remount(remount: Callable) -> void:
	_catalog_remount = remount


## Is catalogue entry `id` switched on? The set persists the DISABLED ids, so an entry added
## to the catalogue later defaults ON rather than being invisible until someone finds the
## checkbox — the presenting complaint this whole page exists to answer was a panel that was
## not there, and a new panel silently defaulting off would reproduce it.
func is_panel_enabled(id: String) -> bool:
	for v in UserSettings.debug_window.get("disabled_panels", []):
		if String(v) == id:
			return false
	return true


## Should catalogue entry `id` be BUILT on this call — i.e. the user has not switched it
## off AND it is not already mounted. A mount that can be re-entered (a host that mounts at
## `_ready` and again once its roster exists; the catalogue page turning an entry back on)
## asks this before constructing, so it neither stacks a second copy nor builds a panel
## `register_panel` is about to refuse and free. The refusal at the seam is the backstop;
## this is the cheap path.
func wants_panel(id: String) -> bool:
	return is_panel_enabled(id) and not has_catalog_id(id)


## Switch a catalogue entry on or off and persist the choice. Off unregisters the live panel
## immediately; on re-runs the catalogue mount if a host is still around to mount against.
##
## The set is GLOBAL, not per-host, and that is a decision rather than a shortcut:
## applicability is already derived per host automatically ([PanelApplicability]), so this
## switch only ever means "I do not want to look at this", and a per-host toggle matrix would
## re-ask by hand the question the derived signal answers.
func set_panel_enabled(id: String, enabled: bool) -> void:
	UserSettings.set_panel_disabled(id, not enabled)

	if enabled:
		if _catalog_remount.is_valid():
			_catalog_remount.call()
	else:
		for cat: int in _panels.keys():
			for panel in _panels[cat].duplicate():
				if is_instance_valid(panel) and panel.has_meta(CATALOG_ID_META) \
						and String(panel.get_meta(CATALOG_ID_META)) == id:
					unregister_panel(panel)
		_mounted_catalog_ids.erase(id)


## Every panel currently registered, flattened, with its category — what the catalogue page
## renders as the census of "what is actually in this window", including the bespoke mounts
## that are not catalogue entries at all.
func registered_panels() -> Array:
	var out: Array = []
	for cat: int in _panels.keys():
		for panel in _panels[cat]:
			if is_instance_valid(panel):
				out.append({"panel": panel, "category": cat})
	return out

#endregion


## Scroll the dashboard so the given category is in view. Historically this
## switched a TabBar selection; in the dashboard everything is already visible,
## so it scrolls instead.
func switch_to_tab(category: Category) -> void:
	if _dashboard:
		_dashboard.scroll_to_category(category)


## Inject a scene's Effect Studio UI into the dashboard's full-width Studio page
## (ADR-0069 hosted as an F3 page). The effect renders in the main window; only
## the Studio controls live in the dashboard window.
func set_studio_page(control: Control) -> void:
	if _dashboard:
		_dashboard.set_studio_page(control)


## Show the dashboard and switch straight to the Studio page.
func show_studio_page() -> void:
	show_overlay()
	if _dashboard:
		_dashboard.show_studio_page()

#endregion


func _on_dashboard_geometry_changed(window_position: Vector2i, window_size: Vector2i) -> void:
	# size_changed fires once per WM resize — safe to save; pick up current scale too.
	var scale := float(_dashboard.content_scale_factor) if _dashboard else 1.0
	UserSettings.save_debug_window(window_position, window_size, DebugConfig.debug_overlay_visible, scale)


func _on_category_collapsed_changed(category: int, collapsed: bool) -> void:
	UserSettings.set_category_collapsed(category, collapsed)


func _on_dashboard_ui_scale_changed(_scale: float) -> void:
	# The SpinBox can fire many times during a drag; don't read position/size
	# (X round-trips) and don't write to disk on each step. The scale persists
	# next time geometry changes or on shutdown.
	pass


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if _dashboard and DebugConfig:
			UserSettings.save_debug_window(_dashboard.position, _dashboard.size, DebugConfig.debug_overlay_visible, float(_dashboard.content_scale_factor))
