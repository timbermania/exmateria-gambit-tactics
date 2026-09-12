@tool
class_name UIVitalsRoster
extends UIWindow
## A column of full [UIUnitInfoWindow] vitals panels — one per unit — that
## REPLACES the compact [UIRosterBar] for a team. Each panel shows the FFT
## portrait + Lv/Exp + Hp/Mp/Ct gradient bars + cur/max digits, bound live to a
## unit. Origin is TOP-LEFT; panels stack DOWN.
##
## Mirrors UIRosterBar's public surface (`frame_count`, `set_frame_unit`,
## `set_frame_sprite_id`, `refresh_frame_stats`, `frame_clicked`,
## `show_click_area_debug`) so [UICombatManager] can drive a vitals column with
## the exact same calls it makes on a roster bar — the two are interchangeable
## and the manager just toggles which one is visible.
##
## The right-hand team sets [member mirrored] so each panel flips: the portrait
## moves to the band's right edge and the text pokes inward, the same border-
## hugging arrangement the flipped enemy roster uses.

## ADR-0211 dec. 4 — the host autoload `EventBus` is not nameable from inside an
## addon (every stranger rig declares an empty `[autoload]` block), so the live
## vitals subscription goes through the platform port. #1274 / ADR-0308.
const EventPort = ExMateriaPlatform.EventPort

## Emitted when a panel is clicked (parity with [UIRosterBar]).
signal frame_clicked(frame_index: int)

## Native portrait card footprint (matches [UIUnitInfoWindow.frame_size]); the
## per-roster [member portrait_scale] multiplies it.
const PORTRAIT_BASE_FRAME := Vector2(36, 52)

## World units per virtual pixel (cascades to each panel).
@export var pixels_per_unit: float = 0.04:
	set(value):
		if pixels_per_unit == value:
			return
		pixels_per_unit = value
		_apply_template_to_all()
		_mark_layout_dirty()

## Number of vitals panels (one per unit).
@export var frame_count: int = 4:
	set(value):
		var new_count := maxi(0, value)
		if frame_count == new_count:
			return
		frame_count = new_count
		_rebuild_panels()
		_mark_layout_dirty()

## Vertical gap between stacked panels, in virtual pixels.
@export var spacing: float = 6.0:
	set(value):
		if spacing == value:
			return
		spacing = value
		_mark_layout_dirty()

## Mirror every panel: portrait to the right edge (flipped), text slid inward.
## Set true for the right-hand team so portraits hug the right border.
@export var mirrored: bool = false:
	set(value):
		if mirrored == value:
			return
		mirrored = value
		_apply_template_to_all()
		_mark_layout_dirty()

## Sideways slide for the text block on mirrored panels (see
## [member UIUnitInfoWindow.mirror_text_shift]). Negative = into the vacated
## portrait zone on the left.
@export var mirror_text_shift: float = -29.0:
	set(value):
		if mirror_text_shift == value:
			return
		mirror_text_shift = value
		_apply_template_to_all()

## Draw the portrait card frame on each panel.
@export var show_portrait_frame: bool = true:
	set(value):
		if show_portrait_frame == value:
			return
		show_portrait_frame = value
		_apply_template_to_all()

## Uniform scale for every portrait card ONLY (image + frame together), within
## an otherwise unchanged panel. 1.0 = the native [constant PORTRAIT_BASE_FRAME].
@export var portrait_scale: float = 1.0:
	set(value):
		if portrait_scale == value:
			return
		portrait_scale = value
		_apply_template_to_all()

## Uniform scale for the WHOLE panel assembly (band + bars + text + portrait),
## applied as a node transform scale. The stack pitch scales with it so panels
## stay flush. 1.0 = native size.
@export var assembly_scale: float = 1.0:
	set(value):
		if assembly_scale == value:
			return
		assembly_scale = value
		_mark_layout_dirty()

#region Click Areas

## Enable click areas on panels (so a panel selects its unit like a roster frame).
@export_group("Click Areas")
@export var enable_click_areas: bool = true:
	set(value):
		if enable_click_areas == value:
			return
		enable_click_areas = value
		_rebuild_click_areas()

## Padding around each panel for click detection (virtual px).
@export var click_area_padding: Vector2 = Vector2(2, 2):
	set(value):
		if click_area_padding == value:
			return
		click_area_padding = value
		_update_click_area_positions()

## Show debug visualization for click areas.
@export var show_click_area_debug: bool = false:
	set(value):
		if show_click_area_debug == value:
			return
		show_click_area_debug = value
		_update_click_area_debug_visibility()

#endregion

#region Internal State

var _panels: Array[UIUnitInfoWindow] = []
var _click_areas: Array[UIClickableField] = []
var _units: Array = []           # bound unit per index (for data binding)
var _sprite_overrides: Array = []  # explicit sprite id per index, or -1

#endregion


func _ready() -> void:
	super._ready()
	# Live HP/MP through the platform port -- same channel the roster bar listens
	# on, reached without naming the `EventBus` autoload (#1274).
	if not Engine.is_editor_hint():
		EventPort.connect_unit_hp_changed(_on_eventbus_hp_changed)
		EventPort.connect_unit_mp_changed(_on_eventbus_mp_changed)


func _build_children() -> void:
	_rebuild_panels()


#region Panel Management

func _rebuild_panels() -> void:
	# Trim excess.
	while _panels.size() > frame_count:
		var panel: UIUnitInfoWindow = _panels.pop_back()
		if is_instance_valid(panel):
			panel.queue_free()
	while _click_areas.size() > frame_count:
		var ca: UIClickableField = _click_areas.pop_back()
		if is_instance_valid(ca):
			ca.queue_free()
	while _units.size() > frame_count:
		_units.pop_back()
	while _sprite_overrides.size() > frame_count:
		_sprite_overrides.pop_back()

	# Grow.
	while _panels.size() < frame_count:
		var panel := UIUnitInfoWindow.new()
		add_child(panel)
		_panels.append(panel)
		_units.append(null)
		_sprite_overrides.append(-1)

	_apply_template_to_all()
	_rebuild_click_areas()


func _apply_template_to_all() -> void:
	for panel in _panels:
		if not is_instance_valid(panel):
			continue
		panel.pixels_per_unit = pixels_per_unit
		panel.mirrored = mirrored
		panel.mirror_text_shift = mirror_text_shift
		panel.show_portrait_frame = show_portrait_frame
		panel.portrait_scale = portrait_scale
		panel.frame_size = PORTRAIT_BASE_FRAME * portrait_scale


func _update_layout() -> void:
	for i in range(_panels.size()):
		var panel := _panels[i]
		if not is_instance_valid(panel):
			continue
		panel.pixels_per_unit = pixels_per_unit
		panel.mirrored = mirrored
		panel.mirror_text_shift = mirror_text_shift
		panel.portrait_scale = portrait_scale
		panel.frame_size = PORTRAIT_BASE_FRAME * portrait_scale
		# Scale the whole panel (band + bars + text + portrait) as one node.
		panel.scale = Vector3(assembly_scale, assembly_scale, assembly_scale)
		# Stack downward: pitch = one (scaled) band height + the gap.
		var pitch: float = (panel.band_size.y + spacing) * pixels_per_unit * assembly_scale
		panel.position = Vector3(0.0, -float(i) * pitch, 0.0)
	_update_click_area_positions()

#endregion


#region Click Areas

func _rebuild_click_areas() -> void:
	for ca in _click_areas:
		if is_instance_valid(ca):
			ca.queue_free()
	_click_areas.clear()

	if not enable_click_areas:
		return

	for i in range(_panels.size()):
		var ca := UIClickableField.new()
		add_child(ca)
		ca.clicked.connect(_on_click_area_clicked)
		_click_areas.append(ca)

	_update_click_area_positions()


func _update_click_area_positions() -> void:
	if not enable_click_areas:
		return
	for i in range(_click_areas.size()):
		if i >= _panels.size():
			break
		var ca := _click_areas[i]
		var panel := _panels[i]
		if not is_instance_valid(ca) or not is_instance_valid(panel):
			continue
		# Cover the whole band. The band stays at the panel origin (x: 0..band_w)
		# in both layouts — only its contents reflect when mirrored.
		var rect := Rect2(
			-click_area_padding.x,
			-click_area_padding.y,
			panel.band_size.x + click_area_padding.x * 2.0,
			panel.band_size.y + click_area_padding.y * 2.0)
		# Size/position the hit box in the panel's scaled space so it tracks the
		# assembly_scale node transform.
		ca.configure("vitals_panel", i, rect, pixels_per_unit * assembly_scale, show_click_area_debug)
		var local_offset := ca.position
		ca.position = Vector3(
			panel.position.x + local_offset.x,
			panel.position.y + local_offset.y,
			local_offset.z)


func _update_click_area_debug_visibility() -> void:
	for ca in _click_areas:
		if is_instance_valid(ca):
			ca.set_debug_visible(show_click_area_debug)


func _on_click_area_clicked(_field_type: String, field_index: int) -> void:
	frame_clicked.emit(field_index)

#endregion


#region Public API (UIRosterBar parity)

## Bind a live unit to a panel; refreshes immediately and on stat changes.
func set_frame_unit(index: int, unit: Node) -> void:
	while _units.size() <= index:
		_units.append(null)
	while _sprite_overrides.size() <= index:
		_sprite_overrides.append(-1)

	var old_unit = _units[index]
	if old_unit and old_unit.has_signal("stats_changed"):
		if old_unit.is_connected("stats_changed", _on_unit_stats_changed.bind(index)):
			old_unit.disconnect("stats_changed", _on_unit_stats_changed.bind(index))

	_units[index] = unit

	if unit and unit.has_signal("stats_changed"):
		unit.connect("stats_changed", _on_unit_stats_changed.bind(index))

	refresh_frame_stats(index)


## Override the portrait sprite for a panel (e.g. after a job change). Merged
## into the unit view so it survives the next refresh.
func set_frame_sprite_id(index: int, sprite_id: int) -> void:
	while _sprite_overrides.size() <= index:
		_sprite_overrides.append(-1)
	_sprite_overrides[index] = sprite_id
	refresh_frame_stats(index)


## Rebuild a panel's view from its bound unit.
func refresh_frame_stats(index: int) -> void:
	if index < 0 or index >= _panels.size():
		return
	var panel := _panels[index]
	var unit = _units[index] if index < _units.size() else null
	if not is_instance_valid(panel) or unit == null:
		return
	var view := FieldInspectController.view_from_unit(unit)
	var override: int = _sprite_overrides[index] if index < _sprite_overrides.size() else -1
	if override >= 0:
		view["sprite_id"] = override
	panel.set_unit_view(view)


## Get a panel by index.
func get_frame(index: int) -> UIUnitInfoWindow:
	if index >= 0 and index < _panels.size():
		return _panels[index]
	return null

#endregion


#region Data Binding

func _on_unit_stats_changed(index: int) -> void:
	refresh_frame_stats(index)


func _on_eventbus_hp_changed(unit: Node, _old_hp: int, _new_hp: int) -> void:
	_refresh_for_unit(unit)


func _on_eventbus_mp_changed(unit: Node, _old_mp: int, _new_mp: int) -> void:
	_refresh_for_unit(unit)


func _refresh_for_unit(unit: Node) -> void:
	for i in range(_units.size()):
		if _units[i] == unit:
			refresh_frame_stats(i)
			return

#endregion
