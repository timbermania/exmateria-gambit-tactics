@tool
extends Window
class_name DebugDashboard
## The BIG debug window — a separate OS-level window (not an in-viewport overlay).
## Cells flow left-to-right via HFlowContainer at their natural content width
## and wrap to a new row when the window narrows. CSS analogue:
## `display: flex; flex-wrap: wrap`. Each Category cell sizes to its own
## content — Designer (no registered panels) collapses to a header strip,
## Logging (60+ checkboxes) takes whatever width its content demands.
## Panels never scroll internally; the outer ScrollContainer handles overflow
## vertically (and only vertically — wrap means we never need horizontal
## scroll). See ADR-0035.
##
## Owned by DebugOverlay (the autoload). DebugOverlay registers panels into
## per-category cells via add_panel(panel, category). Position/size/ui_scale
## persist through UserSettings.debug_window.

## Min/max bounds for the UI scale spinbox (Window.content_scale_factor).
const UI_SCALE_MIN: float = 0.5
const UI_SCALE_MAX: float = 2.0
const UI_SCALE_DEFAULT: float = 1.0

## Pixels of vertical scroll per mouse-wheel notch (matches Godot's
## ScrollContainer default).
const WHEEL_SCROLL_STEP: int = 30

## Mirror of DebugOverlay's Category enum (kept here so this script doesn't
## have to chase the autoload's load order during @tool / startup).
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

signal window_geometry_changed(position: Vector2i, size: Vector2i)
signal ui_scale_changed(scale: float)
## Emitted when the user folds/unfolds a category cell via its title-bar toggle.
## DebugOverlay listens and persists the set through UserSettings.
signal category_collapsed_changed(category: int, collapsed: bool)

var _scroll: ScrollContainer
var _cells_flow: DebugMasonryContainer
# Page 2 (ADR-0068 registry): a full-width table of every tunable, a peer of the
# masonry page. The header page-switcher toggles which of the two is visible.
var _registry_scroll: ScrollContainer
var _registry_view: TunablesRegistryView
# Page 3 (Effect Studio): a full-width host a caller injects the Studio UI into
# via set_studio_page(). Empty until an effect scene registers its page. The
# effect itself renders in the MAIN window; only the Studio controls live here
# (the audio-editor split — ADR-0069 hosted as an F3 page, ADR-0035 window).
var _studio_host: MarginContainer
# Page 4 (UI3 elements, ADR-0088 / ADR-0035 dec. 8): the generated
# registered-element tree. The view reads the UI3Registry autoload directly.
var _ui3_view: UI3RegistryView
# Page 5 (the catalogue): which panels exist, which are mounted here, and what each one is
# a view onto. Rebuilt on entry — every fact it shows is live registry state.
var _catalog_scroll: ScrollContainer
var _catalog_body: VBoxContainer
var _page_buttons: Array = []
var _category_cells: Dictionary = {}      # Category -> VBoxContainer (the cell's content host)
var _cell_panels: Dictionary = {}         # Category -> PanelContainer (the cell wrapper that lives in the masonry)
var _collapse_buttons: Dictionary = {}    # Category -> Button (the ▼/▶ title-bar toggle)
var _cell_headers: Dictionary = {}        # Category -> HBoxContainer (the whole clickable title strip)
var _cell_folds: Dictionary = {}          # Category -> Array[{panel, outer, toggle, refresh}] per-panel folds
var _collapsed: Dictionary = {}           # Category -> true when the cell's content is folded away
var _scale_spinbox: SpinBox
# Page-wide fold controls (masonry page only — the UI3 page carries its own pair).
# Each drives every VISIBLE category cell's collapse at once.
var _fold_all_btn: Button
var _unfold_all_btn: Button


func _init() -> void:
	title = "Debug Dashboard"
	# Default geometry; DebugOverlay overrides from UserSettings before show().
	size = Vector2i(1200, 900)
	position = Vector2i(1300, 60)
	# Floor below which tiling WMs (Hyprland) can't shove the window. Prevents
	# the "tiled to 461x568, can't actually use anything" failure mode and
	# guarantees the ScrollContainer always has room to render its scrollbar.
	min_size = Vector2i(800, 500)
	# Skip the 3D rendering pipeline on this viewport — the dashboard is all
	# Control nodes. Reclaims the per-frame 3D cost we don't pay for here.
	disable_3d = true
	# Stay non-modal — game window keeps receiving WASD/etc. unless this is focused.
	exclusive = false
	transient = false
	# Start hidden; DebugOverlay calls show() on F3.
	visible = false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_build_ui()
	close_requested.connect(_on_close_requested)
	size_changed.connect(_on_size_changed)
	# Don't sample on focus_exited — on X11 / XWayland (Hyprland) that fires
	# constantly as focus bounces between the dashboard and the game window
	# and the handler reads `position`/`size` properties (each = X round-trip).
	# Position-only moves (no resize) save on shutdown instead.


func _build_ui() -> void:
	var root_panel := PanelContainer.new()
	root_panel.anchor_right = 1.0
	root_panel.anchor_bottom = 1.0
	add_child(root_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.13, 1.0)
	style.set_content_margin_all(10)
	root_panel.add_theme_stylebox_override("panel", style)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	root_panel.add_child(main_vbox)

	main_vbox.add_child(_build_header())

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	main_vbox.add_child(_scroll)

	# Masonry packing: uniform-width columns, each cell dropped into the
	# currently-shortest column so short cells don't leave dead space below.
	# CSS analogue: the experimental `grid-template-rows: masonry`.
	# Trade-off vs HFlowContainer: cells fill their column width (no longer
	# at natural content width).
	_cells_flow = DebugMasonryContainer.new()
	_cells_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cells_flow.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_scroll.add_child(_cells_flow)

	for category_idx in TAB_NAMES.keys():
		_category_cells[category_idx] = _build_cell(category_idx)

	# Page 2: the tunables registry, a full-width peer of the masonry (hidden until
	# the header switches to it). Its own scroll so a long registry scrolls independently.
	_registry_scroll = ScrollContainer.new()
	_registry_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_registry_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_registry_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_registry_scroll.visible = false
	main_vbox.add_child(_registry_scroll)
	_registry_view = TunablesRegistryView.new()
	_registry_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_registry_scroll.add_child(_registry_view)

	# Page 3: the Effect Studio host — a full-width, full-height slot a scene fills
	# via set_studio_page(). Hidden until switched to.
	_studio_host = MarginContainer.new()
	_studio_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_studio_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_studio_host.visible = false
	main_vbox.add_child(_studio_host)

	# Page 4: the UI3 element tree (ADR-0088), a full-width peer. The view owns its own
	# scrolling body (its page-wide controls ride a PINNED header bar that never scrolls),
	# so it mounts directly here — no outer ScrollContainer wrapping it.
	_ui3_view = UI3RegistryView.new()
	_ui3_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ui3_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ui3_view.visible = false
	main_vbox.add_child(_ui3_view)

	# Page 5: the panel catalogue. A full-width peer with its own scroll, hidden until
	# switched to. Content is built fresh in `_rebuild_catalog` on every entry.
	_catalog_scroll = ScrollContainer.new()
	_catalog_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_catalog_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_catalog_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_catalog_scroll.visible = false
	main_vbox.add_child(_catalog_scroll)
	_catalog_body = VBoxContainer.new()
	_catalog_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_catalog_scroll.add_child(_catalog_body)


func _build_header() -> Control:
	var header_hbox := HBoxContainer.new()
	header_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var title_label := Label.new()
	title_label.text = "Debug Dashboard"
	title_label.add_theme_font_size_override("font_size", 18)
	header_hbox.add_child(title_label)

	# Page switcher: masonry panels (page 0) vs the tunables registry (page 1). A
	# shared ButtonGroup makes them mutually-exclusive radio toggles.
	var page_group := ButtonGroup.new()
	for i in ["Panels", "Registry", "Studio", "UI3", "Catalogue"]:
		var btn := Button.new()
		btn.text = i
		btn.toggle_mode = true
		btn.button_group = page_group
		btn.pressed.connect(_set_page.bind(_page_buttons.size()))
		header_hbox.add_child(btn)
		_page_buttons.append(btn)
	_page_buttons[0].button_pressed = true

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(spacer)

	# Fold all / Unfold all: one click instead of one click per cell. Masonry page
	# only — _set_page hides them on the pages whose content they cannot reach.
	_unfold_all_btn = Button.new()
	_unfold_all_btn.text = "Unfold all"
	_unfold_all_btn.focus_mode = Control.FOCUS_NONE
	_unfold_all_btn.tooltip_text = "Expand every section on this page"
	_unfold_all_btn.pressed.connect(_on_fold_all_pressed.bind(false))
	header_hbox.add_child(_unfold_all_btn)

	_fold_all_btn = Button.new()
	_fold_all_btn.text = "Fold all"
	_fold_all_btn.focus_mode = Control.FOCUS_NONE
	_fold_all_btn.tooltip_text = "Collapse every section on this page to its header strip"
	_fold_all_btn.pressed.connect(_on_fold_all_pressed.bind(true))
	header_hbox.add_child(_fold_all_btn)

	var scale_label := Label.new()
	scale_label.text = "UI Scale:"
	header_hbox.add_child(scale_label)

	_scale_spinbox = SpinBox.new()
	_scale_spinbox.min_value = UI_SCALE_MIN
	_scale_spinbox.max_value = UI_SCALE_MAX
	_scale_spinbox.step = 0.05
	_scale_spinbox.value = UI_SCALE_DEFAULT
	_scale_spinbox.custom_minimum_size.x = 80
	_scale_spinbox.value_changed.connect(_on_ui_scale_changed)
	header_hbox.add_child(_scale_spinbox)

	return header_hbox


## Switch between the masonry panels page (0) and the tunables registry page (1).
## The registry is rebuilt on entry so it reflects every slug registered so far.
func _set_page(page: int) -> void:
	if _scroll:
		_scroll.visible = page == 0
	if _registry_scroll:
		_registry_scroll.visible = page == 1
	if _studio_host:
		_studio_host.visible = page == 2
	if _ui3_view:
		_ui3_view.visible = page == 3
	if _catalog_scroll:
		_catalog_scroll.visible = page == 4
	# The fold-all pair drives the masonry cells and nothing else — the UI3 page
	# carries its own pair inside the view, the other three have nothing to fold.
	if _fold_all_btn:
		_fold_all_btn.visible = page == 0
	if _unfold_all_btn:
		_unfold_all_btn.visible = page == 0
	if page == 1 and _registry_view:
		_registry_view.rebuild()
	if page == 3 and _ui3_view:
		_ui3_view.rebuild()
	if page == 4:
		_rebuild_catalog()


## Inject the Effect Studio UI into the full-width Studio page (page 2). Replaces
## any prior content. The caller (an effect scene) owns the page's lifecycle.
func set_studio_page(control: Control) -> void:
	if _studio_host == null:
		return
	for c in _studio_host.get_children():
		_studio_host.remove_child(c)
		c.queue_free()
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_studio_host.add_child(control)


## Programmatically switch to the Studio page (used when a scene opens it).
func show_studio_page() -> void:
	if _page_buttons.size() >= 3:
		_page_buttons[2].button_pressed = true
	_set_page(2)


## 🔴 NAMED SO THE BOOT LOADS THEM. THIS CONST HAS NO READER AND THAT IS THE POINT.
##
## A tunable's owner registers its slugs in `_static_init`, i.e. at CLASS LOAD (ADR-0068
## R2) — and every pure-VIEW panel row reads its default and hint back OUT of the `Tune`
## registry (dec. 12). A slug whose owner class has not loaded is simply absent, so the F3
## Registry page under-reports at boot and a row built for it renders a dead "(unregistered
## — owner not booted)" placeholder for the rest of the session, which
## `MapDebugPanels.register_map_panels` records in its own header.
##
## Naming the two mounts compile-loads them, which loads every panel class they construct,
## and each panel's TYPED `setup()` parameter (`CursorDebugPanel.setup(_rig: CursorRig)`,
## `CameraFeelDebugPanel.setup(_camera)`, and the map pair's composer) loads the subject
## whose `_static_init` does the registering. The dashboard is built by the `DebugOverlay`
## autoload, so that whole chain runs during the autoload pass, before any scene exists —
## which is exactly what `Tune`'s replay queue was built to catch.
##
## This used to happen by ACCIDENT: `_rebuild_catalog` read `CombatPanelCatalog.IDS`, and
## the id space moving to [DebugPanelIds] — a table that names no panel — silently cut the
## edge. `TunePortTest` is what noticed, reporting five addon slugs missing from the boot
## pass; it is the guard on this const, and its failure line names which owner went dark.
## `preload`, not the bare `class_name`s: a global class is not a constant expression, and
## an array of them will not compile. Preloading is what actually loads the script anyway.
const PANEL_MOUNTS := [
	preload("res://src/debug/CombatPanelCatalog.gd"),
	preload("res://src/debug/UniversalDebugPanels.gd"),
]


## Rebuild the catalogue page: every [DebugPanelIds] entry with its on/off switch and, for
## the ones that are mounted, what their rows are actually views onto.
##
## The table it walks was `CombatPanelCatalog.IDS` — fourteen ids owned by the mount for the
## two scenes that `extends CombatHost`. On any other screen the page therefore listed the
## fourteen panels a combat host could have and NONE of the ones actually in the window,
## which is the same shape as the bug it was built to answer. It now walks the whole id
## space, sectioned, and calls out any live id the space does not contain.
##
## 🔴 NOTHING IS EVER HIDDEN HERE, and that is the point of the page. The complaint that
## produced it was a panel that was not there — `GambitBattle` printed "F3 - debug overlay"
## while registering nothing — so a page that quietly omitted the entries it judged
## inapplicable would reproduce that bug wearing a justification. An entry that is off, or
## unmounted, or mounted-but-with-nothing-consuming-it, is LISTED, with the reason.
##
## The three sections answer three different questions, and they are separate because
## collapsing them is what made the original bug invisible:
##   1. catalogue entries — every switchable panel in the GAME, sectioned by what it needs
##                          from its host, each with whether this screen mounted it
##   2. bespoke mounts    — panels in this window that are not catalogue entries at all
##                          (FormationScene's three, the audio tab), so the page is a
##                          complete census of the window rather than of the catalogue
##   3. the caveat        — what the liveness column does not know, in the window itself,
##                          because a reader who has to find the ADR will read the column
##                          as a verdict
func _rebuild_catalog() -> void:
	if _catalog_body == null:
		return
	for c in _catalog_body.get_children():
		_catalog_body.remove_child(c)
		c.queue_free()

	# Panels currently registered, indexed by catalogue id, so an entry can show its live
	# row counts rather than merely "on".
	var mounted := {}
	var bespoke: Array = []
	for entry: Dictionary in DebugOverlay.registered_panels():
		var panel: Node = entry["panel"]
		if panel.has_meta(DebugOverlay.CATALOG_ID_META):
			mounted[String(panel.get_meta(DebugOverlay.CATALOG_ID_META))] = panel
		else:
			bespoke.append(entry)

	_catalog_body.add_child(_catalog_heading("Catalogue entries"))
	var listed := {}
	for section: Dictionary in DebugPanelIds.SECTIONS:
		_catalog_body.add_child(_catalog_note("  %s" % String(section["title"])))
		for id: String in section["ids"]:
			listed[id] = true
			_catalog_body.add_child(_catalog_row(id, mounted.get(id)))

	# An id stamped on a live panel that this table does not know about. It cannot happen
	# through `DebugPanelIds`, only through a literal typo at a `register_panel` call site —
	# and the failure mode is the one this page exists to make impossible: a panel present in
	# the window with no switch anywhere, invisible to the census because it is neither a
	# known entry nor bespoke. So it is listed, loudly, rather than falling between the two.
	for id: Variant in mounted.keys():
		if not listed.has(String(id)):
			_catalog_body.add_child(_catalog_note(
				"    %s — UNKNOWN ID (not in DebugPanelIds; no switch)" % String(id)))

	_catalog_body.add_child(_catalog_heading("Mounted outside the catalogue"))
	if bespoke.is_empty():
		_catalog_body.add_child(_catalog_note("(none on this screen)"))
	for entry: Dictionary in bespoke:
		var panel: Node = entry["panel"]
		var title_v: Variant = panel.get("panel_title")
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = "    %s" % (String(title_v) if title_v else String(panel.name))
		name_label.custom_minimum_size.x = 260
		row.add_child(name_label)
		row.add_child(_catalog_note(PanelApplicability.summarise(
			PanelApplicability.summary_of(panel))))
		_catalog_body.add_child(row)

	_catalog_body.add_child(_catalog_heading("What the row counts do NOT tell you"))
	_catalog_body.add_child(_catalog_note(
		"\"consumed\" means something was SEEN to read the slug this session — a push"))
	_catalog_body.add_child(_catalog_note(
		"subscriber that is not a debug row, or at least one get_value. It is monotone and"))
	_catalog_body.add_child(_catalog_note(
		"PROCESS-scoped: once a battle has booted, its slugs stay declared on every later"))
	_catalog_body.add_child(_catalog_note(
		"screen. \"declared — no consumer seen\" is therefore the ABSENCE of evidence, not"))
	_catalog_body.add_child(_catalog_note(
		"evidence of absence: a pull consumer that reads once at build time looks identical"))
	_catalog_body.add_child(_catalog_note(
		"to a dead knob. Only \"not booted\" is a confident answer."))


func _catalog_heading(text: String) -> Control:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	return label


func _catalog_note(text: String) -> Control:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.62, 0.62, 0.66))
	return label


## One catalogue entry: its switch, its title, and its state. `panel` is the live panel when
## the entry is mounted on this screen, null otherwise.
func _catalog_row(id: String, panel: Variant) -> Control:
	var row := HBoxContainer.new()

	# The switch is a plain CheckBox and NOT a TuneField row: this is not a tunable. It is a
	# per-machine view preference persisted in user_settings.json alongside the window
	# geometry, with no code default, no owner and nothing to Pin — routing it through Tune
	# would declare a slug that means nothing to the game.
	var box := CheckBox.new()  # tune-exempt: view preference, persisted via UserSettings
	box.button_pressed = DebugOverlay.is_panel_enabled(id)
	box.toggled.connect(func(on: bool) -> void:
		DebugOverlay.set_panel_enabled(id, on)
		_rebuild_catalog.call_deferred())
	row.add_child(box)

	var name_label := Label.new()
	name_label.text = DebugPanelIds.title_of(id)
	name_label.custom_minimum_size.x = 240
	row.add_child(name_label)

	var status := Label.new()
	if not DebugOverlay.is_panel_enabled(id):
		status.text = "off"
		status.add_theme_color_override("font_color", Color(0.62, 0.62, 0.66))
	elif panel == null:
		# Enabled but absent: this screen mounted no combat catalogue, or the entry's
		# subject was not ready when the host mounted. Both are states worth SEEING.
		status.text = "not mounted on this screen"
		status.add_theme_color_override("font_color", Color(0.85, 0.72, 0.45))
	else:
		var summary := PanelApplicability.summary_of(panel)
		status.text = PanelApplicability.summarise(summary)
		var consumed := int(summary["consumed"])
		var total := int(summary["total"])
		status.add_theme_color_override("font_color",
			Color(0.62, 0.62, 0.66) if total > 0 and consumed == 0 else Color(0.72, 0.85, 0.72))
	row.add_child(status)
	return row


func _build_cell(category: int) -> VBoxContainer:
	# Cell = bordered VBox with a header label, then a content host the
	# DebugOverlay appends registered panels into. Horizontally the cell
	# fills its masonry column's uniform width; vertically it shrinks to
	# its content so the masonry packer sees the right height.
	var cell_panel := PanelContainer.new()
	cell_panel.size_flags_horizontal = Control.SIZE_FILL
	cell_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var cell_style := StyleBoxFlat.new()
	cell_style.bg_color = Color(0.16, 0.16, 0.18, 1.0)
	cell_style.border_color = Color(0.28, 0.28, 0.32, 1.0)
	cell_style.set_border_width_all(1)
	cell_style.set_corner_radius_all(4)
	cell_style.set_content_margin_all(8)
	cell_panel.add_theme_stylebox_override("panel", cell_style)

	var cell_vbox := VBoxContainer.new()
	cell_panel.add_child(cell_vbox)

	# The WHOLE header strip toggles the cell, not just the ▼ at its right end — a
	# 16px triangle is a miserable hit target for a thing you fold constantly. The
	# strip takes mouse events itself (the Label defaults to IGNORE, so its pixels
	# fall through to the row) and the ▼ Button keeps consuming its own clicks, so
	# a hit on the triangle toggles ONCE, not twice.
	var header_row := HBoxContainer.new()
	header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.mouse_filter = Control.MOUSE_FILTER_STOP
	header_row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	header_row.tooltip_text = "Click to collapse / expand this section"
	header_row.gui_input.connect(_on_cell_header_input.bind(category, header_row))
	cell_vbox.add_child(header_row)

	var header := Label.new()
	header.text = TAB_NAMES[category]
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(header)

	# Collapse/expand toggle, pinned to the right of the title bar. Toggling hides
	# the Content VBox below, shrinking the cell to a header strip; the masonry
	# reflows automatically on the child min-size change. The collapsed state
	# persists via DebugOverlay → UserSettings (category_collapsed_changed).
	var collapse_btn := Button.new()
	collapse_btn.flat = true
	collapse_btn.focus_mode = Control.FOCUS_NONE
	collapse_btn.text = "▼"
	collapse_btn.tooltip_text = "Collapse / expand this section"
	collapse_btn.pressed.connect(_on_collapse_pressed.bind(category))
	header_row.add_child(collapse_btn)
	_collapse_buttons[category] = collapse_btn
	_cell_headers[category] = header_row

	var sep := HSeparator.new()
	sep.custom_minimum_size.y = 2
	cell_vbox.add_child(sep)

	var content := VBoxContainer.new()
	content.name = "Content"
	cell_vbox.add_child(content)

	# Start hidden — add_panel flips this on for any category a scene actually
	# registers something into. Categories with no registered panel for the
	# current scene (Designer in GPUArena, etc.) stay invisible and HFlowContainer
	# skips them entirely, so we don't waste a header strip on empty cells.
	cell_panel.visible = false
	_cells_flow.add_child(cell_panel)
	_cell_panels[category] = cell_panel
	return content


func add_panel(panel: Control, category: int) -> void:
	"""Append a debug panel to the right category cell, wrapped in its OWN titled
	fold (ADR-0035 dec. 7): the cell reads as a table of contents of panel
	titles instead of one untitled blob. A cell's ONLY panel starts open (nothing
	to disambiguate — and a lone list panel keeps its list visible); when a second
	panel joins the cell, every fold in it collapses to the TOC state."""
	var cell: VBoxContainer = _category_cells.get(category)
	if cell == null:
		push_warning("[DebugDashboard] No cell for category %d; falling back to GENERAL" % category)
		cell = _category_cells[Category.GENERAL]
		category = Category.GENERAL
	var title_v: Variant = panel.get("panel_title")   # BaseDebugPanel property; fall back to node name
	var fold_title := String(title_v) if title_v else String(panel.name)

	var outer := VBoxContainer.new()
	var toggle := Button.new()
	toggle.toggle_mode = true
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.add_theme_font_size_override("font_size", 14)
	outer.add_child(toggle)
	var content := VBoxContainer.new()
	outer.add_child(content)
	content.add_child(panel)
	panel.visible = true
	var refresh := func() -> void:
		toggle.text = ("▾  " if toggle.button_pressed else "▸  ") + fold_title
		content.visible = toggle.button_pressed
	toggle.toggled.connect(func(_on: bool) -> void: refresh.call())

	var folds: Array = _cell_folds.get(category, [])
	folds.append({"panel": panel, "outer": outer, "toggle": toggle, "refresh": refresh})
	_cell_folds[category] = folds
	if folds.size() == 1:
		toggle.set_pressed_no_signal(true)
	else:
		for f: Dictionary in folds:
			(f["toggle"] as Button).set_pressed_no_signal(false)
			(f["refresh"] as Callable).call()
	refresh.call()
	cell.add_child(outer)

	# Reveal the cell now that it has content — empty cells stay hidden so
	# unused categories don't waste a header strip on the page.
	var cell_panel: PanelContainer = _cell_panels.get(category)
	if cell_panel:
		cell_panel.visible = true
	if panel.has_method("on_registered"):
		panel.on_registered()
	if panel.has_method("on_shown"):
		panel.on_shown()


func remove_panel(panel: Control, category: int) -> void:
	var cell: VBoxContainer = _category_cells.get(category)
	# The panel sits inside its fold wrapper — free the whole wrapper and drop its entry.
	var folds: Array = _cell_folds.get(category, [])
	for f: Dictionary in folds:
		if f["panel"] == panel:
			var outer: VBoxContainer = f["outer"]
			if is_instance_valid(outer):
				(f["panel"] as Control).get_parent().remove_child(f["panel"])
				outer.queue_free()
			folds.erase(f)
			break
	_cell_folds[category] = folds
	if cell and panel.get_parent() == cell:
		cell.remove_child(panel)   # legacy path: a panel added before the fold wrapper existed
	# Hide the cell again if removing this panel left the category empty (fold accounting is
	# authoritative — freed wrappers still count as children until end of frame).
	if cell and folds.is_empty():
		var cell_panel: PanelContainer = _cell_panels.get(category)
		if cell_panel:
			cell_panel.visible = false


func _on_collapse_pressed(category: int) -> void:
	var now_collapsed: bool = not bool(_collapsed.get(category, false))
	set_category_collapsed(category, now_collapsed)
	category_collapsed_changed.emit(category, now_collapsed)


## Left-click anywhere on a cell's header strip folds/unfolds it. Accepts the event
## so the click can't also reach whatever the strip sits on.
func _on_cell_header_input(event: InputEvent, category: int, header_row: Control) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	_on_collapse_pressed(category)
	if is_instance_valid(header_row):
		header_row.accept_event()


## Fold (or unfold) every category cell that is actually ON the page. Cells with no
## registered panel are skipped deliberately: they are invisible, so folding them
## would persist a collapse the user never asked for and never saw, and it would be
## waiting for them in the next scene that DOES register into that category.
func fold_all_categories(collapsed: bool) -> void:
	for category: int in _category_cells.keys():
		var cell_panel: PanelContainer = _cell_panels.get(category)
		if cell_panel == null or not cell_panel.visible:
			continue
		if bool(_collapsed.get(category, false)) == collapsed:
			continue
		set_category_collapsed(category, collapsed)
		category_collapsed_changed.emit(category, collapsed)


func _on_fold_all_pressed(collapsed: bool) -> void:
	fold_all_categories(collapsed)


## The page-wide fold controls (guard surface) and the per-cell state they drive.
func fold_all_button() -> Button:
	return _fold_all_btn


func unfold_all_button() -> Button:
	return _unfold_all_btn


func is_category_collapsed(category: int) -> bool:
	return bool(_collapsed.get(category, false))


## A cell's clickable title strip (guard surface: the hit target is the whole header,
## not just the ▼ at its end).
func category_header(category: int) -> Control:
	return _cell_headers.get(category)


## Fold (hide content) or unfold (show content) a category cell. Driven by the
## title-bar toggle and by DebugOverlay at boot to restore persisted state.
## Only touches the Content VBox's visibility — orthogonal to add_panel's
## cell-reveal, so a folded empty cell stays hidden until a panel registers.
func set_category_collapsed(category: int, collapsed: bool) -> void:
	var content: VBoxContainer = _category_cells.get(category)
	if content == null:
		return
	content.visible = not collapsed
	_collapsed[category] = collapsed
	var btn: Button = _collapse_buttons.get(category)
	if btn:
		btn.text = "▶" if collapsed else "▼"


func scroll_to_category(category: int) -> void:
	"""Scroll the dashboard so the named category's cell is in view.
	Replaces the old 'switch_to_tab' navigation."""
	var cell_panel: PanelContainer = _cell_panels.get(category)
	if cell_panel == null or _scroll == null:
		return
	await get_tree().process_frame  # let layout settle
	_scroll.scroll_vertical = int(cell_panel.position.y)


func apply_ui_scale(scale: float) -> void:
	"""Apply a UI scale (Window.content_scale_factor). Called by DebugOverlay
	at boot from UserSettings, and by the SpinBox when the user adjusts."""
	scale = clamp(scale, UI_SCALE_MIN, UI_SCALE_MAX)
	content_scale_factor = scale
	if _scale_spinbox and not is_equal_approx(_scale_spinbox.value, scale):
		_scale_spinbox.set_value_no_signal(scale)


func _on_ui_scale_changed(value: float) -> void:
	content_scale_factor = value
	ui_scale_changed.emit(value)


func _input(event: InputEvent) -> void:
	# Capture mouse-wheel events at the Window level and apply them to the
	# outer ScrollContainer, with one exception: if the hovered control (or
	# any of its ancestors) is a Range — SpinBox, HSlider, VSlider —
	# eat the event silently so it doesn't scrub the value. Everything else
	# (ItemList, Tree, TextEdit, plain controls) is left alone so its native
	# wheel handling works; the event then bubbles up to the outer
	# ScrollContainer naturally if the inner control doesn't consume it.
	if _scroll == null:
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index != MOUSE_BUTTON_WHEEL_UP and event.button_index != MOUSE_BUTTON_WHEEL_DOWN:
		return

	var hovered := get_viewport().gui_get_hovered_control()
	if hovered != null and not _ancestor_chain_is_range(hovered):
		# Let the hovered control / its parents handle the wheel natively.
		# If nothing internal consumes it, the outer ScrollContainer (which
		# wraps every panel) will receive it via normal propagation.
		return

	# Either no control is hovered (mouse over dashboard margin) OR the
	# hovered control is a Range whose scrubbing we want to suppress.
	# Manually drive the outer ScrollContainer.
	var delta: int = WHEEL_SCROLL_STEP
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		delta = -WHEEL_SCROLL_STEP
	_scroll.scroll_vertical = max(0, _scroll.scroll_vertical + delta)
	get_viewport().set_input_as_handled()


# Returns true if `ctrl` or any of its Control ancestors is a Range
# (SpinBox / HSlider / VSlider). Used by `_input` to decide whether to
# suppress wheel-scrub on Ranges while letting other controls handle wheel.
func _ancestor_chain_is_range(ctrl: Control) -> bool:
	var n: Node = ctrl
	while n != null:
		if n is Range:
			return true
		n = n.get_parent()
	return false


func _on_close_requested() -> void:
	_emit_geometry_changed()
	hide()


func _on_size_changed() -> void:
	# HFlowContainer reflows itself on resize; no per-cell re-layout work to do.
	_emit_geometry_changed()


func _emit_geometry_changed() -> void:
	window_geometry_changed.emit(position, size)
