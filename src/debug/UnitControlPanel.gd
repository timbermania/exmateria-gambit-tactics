class_name UnitControlPanel
extends BaseDebugPanel
## Debug panel for repositioning units and changing sprites in EffectViewer.
##
## Provides caster/target position spinboxes, distance control, swap, and sprite ID changes.

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const TerrainCell = ExMateriaSchema.TerrainCell

signal unit_moved

const TuneField = preload("res://src/debug/TuneField.gd")

# Grid coords are ints over the whole (permissive) map range, stepped by 1 tile.
const _POS_HINT := {"min": -99999, "max": 99999, "step": 1}
# Sprite ID is a byte (0x00-0xFF). EffectViewerScene owns these slugs (declares the
# default + AUTOSAVE at spawn and applies them to body_sprite_id); this panel is the view.
const _SPRITE_HINT := {"min": 0, "max": 0xFF, "step": 1}

var _caster: Unit
var _target: Unit
var _map: Node3D


func setup(caster: Unit, target: Unit, map: Node3D) -> void:
	_caster = caster
	_target = target
	_map = map
	panel_title = "Unit Control"
	panel_category = Category.UNIT
	_build_ui()
	_sync_from_components()


func _build_ui() -> void:
	var main_vbox = VBoxContainer.new()
	main_vbox.custom_minimum_size = Vector2(250, 0)
	add_child(main_vbox)

	# === CASTER SECTION ===
	var caster_section = create_collapsible_section(main_vbox, "Caster", true)
	_add_unit_controls(caster_section, "caster")

	# === TARGET SECTION ===
	var target_section = create_collapsible_section(main_vbox, "Target", true)
	_add_unit_controls(target_section, "target")

	add_separator(main_vbox)

	# === QUICK CONTROLS ===
	add_section_title(main_vbox, "Quick Controls")

	var dist_row = HBoxContainer.new()
	main_vbox.add_child(dist_row)
	add_label(dist_row, "Distance", 70)
	# Computed readout of |caster-target| (recomputed on every sync) plus a one-shot "Set
	# distance" command param — owned by the two positions, not a tunable.
	var dist_sb = SpinBox.new()  # tune-exempt: computed distance readout + one-shot Set param
	dist_sb.min_value = 1
	dist_sb.max_value = 99999
	dist_sb.step = 1
	dist_sb.value = 3
	dist_sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_controls["distance"] = dist_sb
	dist_row.add_child(dist_sb)
	var dist_btn = Button.new()
	dist_btn.text = "Set"
	dist_btn.pressed.connect(_on_set_distance)
	dist_row.add_child(dist_btn)

	var swap_btn = Button.new()
	swap_btn.text = "Swap Positions"
	swap_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	swap_btn.pressed.connect(_on_swap_positions)
	main_vbox.add_child(swap_btn)


func _add_unit_controls(parent: Control, prefix: String) -> void:
	var unit := _caster if prefix == "caster" else _target
	var cell: Vector3i = unit.get_current_cell() \
		if unit and is_instance_valid(unit) else TerrainCell.NONE
	var placed := cell != TerrainCell.NONE
	var def_x: int = cell.x if placed else 0
	var def_z: int = cell.y if placed else 0

	# Grid X / Z auto-persist (green TuneField, ADR-0068): each edit sticks across
	# reloads with no Pin. EffectViewerScene OWNS these slugs (declares the default +
	# AUTOSAVE at spawn) and reads them to place the unit; this panel is the VIEW. The
	# `def_*` here is moot (the scene registered first) but kept valid. Live-move on
	# edit — no Apply button; Y is re-snapped by place_on_tile.
	var x_sb: SpinBox = TuneField.add(parent, "Grid X",
		"effect_viewer.%s_x" % prefix, def_x, _POS_HINT, Tune.Persist.AUTOSAVE)
	x_sb.value_changed.connect(func(_v): _on_apply_position(prefix))
	_controls[prefix + "_x"] = x_sb

	var z_sb: SpinBox = TuneField.add(parent, "Grid Z",
		"effect_viewer.%s_z" % prefix, def_z, _POS_HINT, Tune.Persist.AUTOSAVE)
	z_sb.value_changed.connect(func(_v): _on_apply_position(prefix))
	_controls[prefix + "_z"] = z_sb

	# Sprite ID auto-persists (green TuneField, ADR-0068): the caster/target sprite is
	# deliberate test-setup state (like position), so it comes back after a reload.
	# EffectViewerScene OWNS the slug and applies it to body_sprite_id at spawn; this
	# panel is the VIEW — the live edit still pushes body_sprite_id via _on_sprite_changed.
	var def_sprite: int = int(unit.body_sprite_id) if unit and is_instance_valid(unit) else 0
	var sprite_sb: SpinBox = TuneField.add(parent, "Sprite",
		"effect_viewer.%s_sprite" % prefix, def_sprite, _SPRITE_HINT, Tune.Persist.AUTOSAVE)
	sprite_sb.prefix = "0x"
	sprite_sb.value_changed.connect(func(_v): _on_sprite_changed(sprite_sb.value, prefix))
	_controls[prefix + "_sprite"] = sprite_sb


func _sync_from_components() -> void:
	# Grid X/Z are shown by the AUTOSAVE TuneFields (bound to Tune), so a reposition
	# reaches them through _write_pos → Tune → bind, not through here. Only the plain
	# sprite fields need a manual push; distance is recomputed below.
	if _caster and is_instance_valid(_caster):
		set_spinbox_value("caster_sprite", _caster.body_sprite_id)
	if _target and is_instance_valid(_target):
		set_spinbox_value("target_sprite", _target.body_sprite_id)

	_update_distance_spinbox()


func _write_pos(prefix: String, grid_x: int, grid_z: int) -> void:
	"""Persist a programmatic reposition (swap / distance / off-map correction) through
	the AUTOSAVE slugs the X/Z TuneFields bind to: set_value updates the bound spinboxes
	(via Tune.bind, no signal loop) and commit_slug writes it to the staging file so it
	survives a reload — exactly what a direct edit of the field does."""
	var x_slug := "effect_viewer.%s_x" % prefix
	var z_slug := "effect_viewer.%s_z" % prefix
	Tune.set_value(x_slug, grid_x)
	Tune.commit_slug(x_slug)
	Tune.set_value(z_slug, grid_z)
	Tune.commit_slug(z_slug)


func sync_from_units() -> void:
	"""Public method for EffectViewerScene to call after map changes."""
	_sync_from_components()


func on_shown() -> void:
	_sync_from_components()


func _update_distance_spinbox() -> void:
	var caster_cell: Vector3i = _caster.get_current_cell() \
		if _caster and is_instance_valid(_caster) else TerrainCell.NONE
	var target_cell: Vector3i = _target.get_current_cell() \
		if _target and is_instance_valid(_target) else TerrainCell.NONE
	if caster_cell != TerrainCell.NONE and target_cell != TerrainCell.NONE:
		var dist = absi(target_cell.x - caster_cell.x) + absi(target_cell.y - caster_cell.y)
		set_spinbox_value("distance", dist)


func _on_apply_position(prefix: String) -> void:
	var unit = _caster if prefix == "caster" else _target
	var gx = int(get_spinbox_value(prefix + "_x"))
	var gz = int(get_spinbox_value(prefix + "_z"))
	_move_unit(unit, gx, gz)


func _move_unit(unit: Unit, grid_x: int, grid_z: int) -> void:
	if not unit or not is_instance_valid(unit):
		return

	var prefix := "caster" if unit == _caster else "target"

	# Kept for the off-map fallback below, not released: nothing to release.
	var old_cell := unit.get_current_cell()

	# Place on new tile
	var success = unit.place_on_tile(grid_x, grid_z, _map)
	if not success:
		# Off-map request: keep the unit where it was and snap the persisted position
		# (and the bound spinboxes) back to that valid tile — never persist a bad value.
		if old_cell != TerrainCell.NONE:
			unit.place_on_tile(old_cell.x, old_cell.y, _map)
			_write_pos(prefix, old_cell.x, old_cell.y)
		_sync_from_components()
		return

	# Update facing for both units
	if _caster and _target and is_instance_valid(_caster) and is_instance_valid(_target):
		_caster.face_toward_unit(_target)
		_target.face_toward_unit(_caster)

	_write_pos(prefix, grid_x, grid_z)
	_sync_from_components()
	unit_moved.emit()


func _on_sprite_changed(value: float, prefix: String) -> void:
	var unit = _caster if prefix == "caster" else _target
	if unit and is_instance_valid(unit):
		unit.body_sprite_id = int(value)


func _on_set_distance() -> void:
	var dist = int(get_spinbox_value("distance"))
	if not _caster or not is_instance_valid(_caster):
		return

	var caster_cell := _caster.get_current_cell()
	if caster_cell == TerrainCell.NONE:
		return

	# Move target to caster_x + distance, same z
	var target_x = caster_cell.x + dist
	var target_z = caster_cell.y
	_move_unit(_target, target_x, target_z)


func _on_swap_positions() -> void:
	if not _caster or not _target:
		return
	if not is_instance_valid(_caster) or not is_instance_valid(_target):
		return

	var caster_cell := _caster.get_current_cell()
	var target_cell := _target.get_current_cell()
	if caster_cell == TerrainCell.NONE or target_cell == TerrainCell.NONE:
		return

	var cx = caster_cell.x
	var cz = caster_cell.y
	var tx = target_cell.x
	var tz = target_cell.y

	# Place in swapped positions
	_caster.place_on_tile(tx, tz, _map)
	_target.place_on_tile(cx, cz, _map)

	# Update facing
	_caster.face_toward_unit(_target)
	_target.face_toward_unit(_caster)

	# Persist the swap (updates the bound spinboxes too).
	_write_pos("caster", tx, tz)
	_write_pos("target", cx, cz)

	_sync_from_components()
	unit_moved.emit()
