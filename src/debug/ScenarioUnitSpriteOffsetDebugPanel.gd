class_name ScenarioUnitSpriteOffsetDebugPanel
extends BaseDebugPanel
## F3 rig for nudging ONE unit's sprite art on its billboard — the per-unit
## companion to ScenarioUnitAlignmentDebugPanel (which writes shared_loc_offset to
## EVERY unit at once). Purpose: dial a single unit's carried/cinematic pose into
## place against a PSX reference beat (scn6 carry: Ovelia sits detached up-right of
## Delita at PC210; move JUST her onto his shoulder).
##
## Mechanism: overrides the selected unit's `shared_loc_offset` shader uniform — the
## pixel-space placement of its sprite art WITHIN its mesh quad. This is "where on
## the mesh she is rendered," NOT the whole mesh: world anchor, depth-sort and shadow
## do not move (prior RE proved the carried unit's world feet-anchor already matches
## PSX; only the art is off). Overrides are keyed by unit id and RE-APPLIED every
## frame + on scene reload, so a tweak survives double-clicking a beat in the VM panel.
##
## Direction (this shader is inverse-gather, so X is flipped from intuition):
##   offset X:  + = art moves LEFT   · − = RIGHT
##   offset Y:  + = art moves DOWN   · − = UP
## The Print button dumps the absolute shared_loc_offset to bake into the fix.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const SpriteLayerManager = ExMateriaSpriteRig.SpriteLayerManager

var _scene_root: Node
var _get_units_by_id: Callable             # returns Dictionary{ id:int -> Unit }

var _unit_opt: OptionButton
var _x_sb: SpinBox
var _y_sb: SpinBox
var _status: Label

var _selected_id: int = -1
var _overrides: Dictionary = {}            # id -> Vector2 (absolute shared_loc_offset)
var _base_by_id: Dictionary = {}           # id -> Vector2 (value observed before any override)
var _suppress := false                     # guard so programmatic spinbox writes don't re-fire


func _init() -> void:
	# BaseDebugPanel gates a panel's `_process` on `is_visible_in_tree()`, because a
	# panel's per-frame work is normally a repaint nobody is watching (W13 / #955).
	# This one is the exception the gate is written to allow: its `_process` does not
	# refresh a label, it RE-APPLIES the stored `shared_loc_offset` overrides to the
	# live units every frame (the docstring above `_unit_opt` says so — "re-applied
	# per frame + on reload"), because the sprite pipeline rewrites the offset per
	# animation. Gate it and a calibration you set stops holding the moment you fold
	# the panel away, which is a broken rig rather than a saved 0.0x ms.
	processes_while_hidden = true


func setup(scene_root: Node, get_units_by_id_func: Callable) -> void:
	_scene_root = scene_root
	_get_units_by_id = get_units_by_id_func
	panel_title = "Unit Sprite Offset (per-unit)"
	panel_category = Category.SCENARIO_LOOK
	_build_ui()
	_refresh_units()


## Scene reloads on click-to-rewind (e.g. double-click beat 210). Rebind to the fresh
## scene + units and RE-APPLY every stored override to the freshly-spawned units, so
## the tweak persists across the jump. Ids are stable across reloads.
func rebind(scene_root: Node, get_units_by_id_func: Callable) -> void:
	_scene_root = scene_root
	_get_units_by_id = get_units_by_id_func
	_refresh_units()
	_apply_all_overrides()


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(320, 0)
	add_child(vbox)

	add_section_title(vbox, "Target unit")
	var unit_row := HBoxContainer.new()
	vbox.add_child(unit_row)
	var ul := Label.new()
	ul.text = "unit"
	ul.custom_minimum_size.x = 60
	unit_row.add_child(ul)
	# tune-exempt: per-scene target selector for this calibration rig; the offsets it drives
	# live in the in-memory _overrides dict keyed by scenario-specific unit id (re-applied per
	# frame + on reload), measured then BAKED into code via Print — not a persistable pref.
	_unit_opt = OptionButton.new()  # tune-exempt: per-scene unit target selector, id-keyed in-memory overrides
	_unit_opt.custom_minimum_size.x = 240
	_unit_opt.item_selected.connect(_on_unit_selected)
	unit_row.add_child(_unit_opt)

	var refresh_btn := Button.new()
	refresh_btn.text = "Refresh unit list"
	refresh_btn.pressed.connect(_refresh_units)
	vbox.add_child(refresh_btn)

	add_separator(vbox)
	add_section_title(vbox, "shared_loc_offset  (+X=left −X=right · +Y=down −Y=up)")
	_x_sb = _add_scrub(vbox, "offset X", -256.0, 256.0, 0.25, SpriteLayerManager.shared_loc_offset.x, _on_offset_changed)
	_y_sb = _add_scrub(vbox, "offset Y", -256.0, 256.0, 0.25, SpriteLayerManager.shared_loc_offset.y, _on_offset_changed)

	add_separator(vbox)
	var btn_row := add_button_row(vbox)
	var reset_btn := Button.new()
	reset_btn.text = "Reset this unit"
	reset_btn.pressed.connect(_on_reset_selected)
	btn_row.add_child(reset_btn)
	var print_btn := Button.new()
	print_btn.text = "Print Values"
	print_btn.pressed.connect(_on_print_values)
	btn_row.add_child(print_btn)

	_status = Label.new()
	_status.text = "(no unit selected)"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 320
	vbox.add_child(_status)


func _add_scrub(parent: Control, label: String, min_v: float, max_v: float, step: float,
		initial: float, on_changed: Callable) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label
	lbl.custom_minimum_size.x = 150
	row.add_child(lbl)
	# tune-exempt: per-unit offset multiplexed by _unit_opt — the live value is loaded from the
	# in-memory _overrides dict (id-keyed) for the selected unit, and baked into code via Print;
	# a single Tune slug would wrongly conflate every unit's offset.
	var sb := SpinBox.new()  # tune-exempt: per-unit multiplexed calibration value, id-keyed in-memory store
	sb.min_value = min_v
	sb.max_value = max_v
	sb.step = step
	sb.value = initial
	sb.custom_minimum_size.x = 120
	sb.value_changed.connect(on_changed)
	row.add_child(sb)
	return sb


func _units_by_id() -> Dictionary:
	if _get_units_by_id.is_valid():
		var d = _get_units_by_id.call()
		if d is Dictionary:
			return d
	return {}


func _unit_for(id: int):
	var d := _units_by_id()
	if d.has(id):
		var u = d[id]
		if u != null and is_instance_valid(u):
			return u
	return null


## (Re)populate the dropdown from live units, preserving the current selection.
func _refresh_units() -> void:
	if _unit_opt == null:
		return
	var d := _units_by_id()
	var ids: Array = d.keys()
	ids.sort()
	_unit_opt.clear()
	var pick_idx := -1
	for i in ids.size():
		var id: int = ids[i]
		var u = d[id]
		var nm := ""
		var anim := -1
		if u != null and is_instance_valid(u):
			nm = String(u.name)
			anim = u.current_anim_id
			if not _base_by_id.has(id) and u.material != null:
				var b = u.material.get_shader_parameter("shared_loc_offset")
				_base_by_id[id] = b if b != null else SpriteLayerManager.shared_loc_offset
		_unit_opt.add_item("id %d — %s (anim %d)" % [id, nm, anim])
		_unit_opt.set_item_metadata(i, id)
		if id == _selected_id:
			pick_idx = i
	if pick_idx < 0 and ids.size() > 0:
		pick_idx = 0
	if pick_idx >= 0:
		_unit_opt.select(pick_idx)
		_on_unit_selected(pick_idx)


func _on_unit_selected(idx: int) -> void:
	if idx < 0 or _unit_opt == null:
		return
	_selected_id = _unit_opt.get_item_metadata(idx)
	# Load the selected unit's live offset into the spinboxes (override if present).
	var cur: Vector2 = _overrides.get(_selected_id, _current_offset_of(_selected_id))
	_suppress = true
	if _x_sb: _x_sb.value = cur.x
	if _y_sb: _y_sb.value = cur.y
	_suppress = false
	_update_status()


func _current_offset_of(id: int) -> Vector2:
	var u = _unit_for(id)
	if u != null and u.material != null:
		var v = u.material.get_shader_parameter("shared_loc_offset")
		if v != null:
			return v
	return _base_by_id.get(id, SpriteLayerManager.shared_loc_offset)


func _on_offset_changed(_v: float) -> void:
	if _suppress or _selected_id < 0:
		return
	var off := Vector2(_x_sb.value, _y_sb.value)
	_overrides[_selected_id] = off
	_apply_override(_selected_id, off)
	_update_status()


## Apply an override to one unit: set the shader param AND the Unit's remembered base
## so nothing (start_attack / move-opcode re-derive) clobbers it back.
func _apply_override(id: int, off: Vector2) -> void:
	var u = _unit_for(id)
	if u == null:
		return
	if u.material != null:
		u.material.set_shader_parameter("shared_loc_offset", off)
	u.set("_base_loc_offset", off)


func _apply_all_overrides() -> void:
	for id in _overrides.keys():
		_apply_override(id, _overrides[id])


func _on_reset_selected() -> void:
	if _selected_id < 0:
		return
	_overrides.erase(_selected_id)
	var base: Vector2 = _base_by_id.get(_selected_id, SpriteLayerManager.shared_loc_offset)
	_apply_override(_selected_id, base)  # restore captured base
	_suppress = true
	if _x_sb: _x_sb.value = base.x
	if _y_sb: _y_sb.value = base.y
	_suppress = false
	_update_status()


func _update_status() -> void:
	if _status == null:
		return
	if _selected_id < 0:
		_status.text = "(no unit selected)"
		return
	var base: Vector2 = _base_by_id.get(_selected_id, SpriteLayerManager.shared_loc_offset)
	var cur := Vector2(_x_sb.value, _y_sb.value)
	var d := cur - base
	var overridden := _overrides.has(_selected_id)
	_status.text = "id %d  base=(%.2f, %.2f)  now=(%.2f, %.2f)  Δ=(%+.2f, %+.2f)%s" % [
		_selected_id, base.x, base.y, cur.x, cur.y, d.x, d.y,
		"  [OVERRIDE]" if overridden else ""]


func on_shown() -> void:
	_refresh_units()


## Keep active overrides applied — cheap (only touched units), and wins over anything
## else that writes shared_loc_offset while a beat is parked.
func _process(_dt: float) -> void:
	if _overrides.is_empty():
		return
	_apply_all_overrides()


func _on_print_values() -> void:
	print("")
	print("=".repeat(60))
	print("# Unit Sprite Offset — per-unit shared_loc_offset overrides")
	if _overrides.is_empty():
		print("  (none — nothing overridden yet)")
	for id in _overrides.keys():
		var off: Vector2 = _overrides[id]
		var base: Vector2 = _base_by_id.get(id, SpriteLayerManager.shared_loc_offset)
		var d := off - base
		var u = _unit_for(id)
		var nm: String = String(u.name) if (u != null and is_instance_valid(u)) else "?"
		var anim: int = u.current_anim_id if (u != null and is_instance_valid(u)) else -1
		print("  id %d (%s, anim %d):  shared_loc_offset=(%.2f, %.2f)   Δ from base=(%+.2f, %+.2f)" % [
			id, nm, anim, off.x, off.y, d.x, d.y])
	print("=".repeat(60))
	print("")
