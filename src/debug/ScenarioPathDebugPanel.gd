class_name ScenarioPathDebugPanel
extends BaseDebugPanel

## F3 front-end for the [Path] debug navigation — "get me to scenario N without a
## live battle". Two ways to drive the ONE [ScenarioPath] planner (per the
## no-env-vars rule; both just park a target in [ScenarioDebugSession] and reload):
##
##   1. Flat scenario picker — pick any group member from a flat list; its group is
##      auto-resolved and the planned path is walked.
##   2. Group flowchart — pick a group, see its [ScenarioDirector] edges listed as
##      the group root plus one row per member (guard-labelled) with a "Walk here"
##      button on each.
##
## Both set `ScenarioDebugSession.path_target_scenario_id` and
## `reload_current_scene()`; `ScenarioPlayerScene._ready` reads it, boots the group
## root world once, and runs the [ScenarioPathApplier]. This panel is stateless
## w.r.t. the VM — it needs no rebind across the reload.
##
## Rendered as a plain VBox of controls (NOT a GraphEdit): the dashboard packs
## panels into narrow masonry columns and wraps everything in a ScrollContainer, so
## a fixed-width interactive canvas would overflow its column (overlapping the
## neighbour) and swallow the wheel/drag the dashboard needs. Same width budget as
## the sibling Scenario panels so the column stays uniform.

const _PANEL_WIDTH := 380

# Default selection: group root 3 (Orbonne Monastery) / member scenario 6
# "Abducting the Princess" — the scene under active development, matching
# ScenarioPlayerScene.DEFAULT_PATH_TARGET so the panel reflects the fresh-boot
# default. The pickers pre-select these on open (falling back to index 0 if the
# ids aren't present).
const _DEFAULT_GROUP_ROOT := 3
const _DEFAULT_MEMBER := 6

var _flat_picker: OptionButton
var _group_picker: OptionButton
var _flow_vbox: VBoxContainer  # host the selected group's root + member rows


func setup() -> void:
	panel_title = "Scenario Path"
	panel_category = Category.SCENARIO
	_build_ui()


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(_PANEL_WIDTH, 0)
	add_child(vbox)

	# --- Flat scenario picker: walk to any group member ---
	add_section_title(vbox, "Walk to scenario (flat)")
	add_label(vbox, "Pick a scenario; its group is auto-resolved and walked.")
	# tune-exempt: navigation launcher — a transient input to the "Walk" action; the actually
	# booted target is owned by ScenarioDebugSession (+ scene reload), and the picker
	# deliberately pre-selects the dev scene (_DEFAULT_MEMBER). Not a persistable pref.
	_flat_picker = OptionButton.new()  # tune-exempt: navigation launcher, target owned by ScenarioDebugSession
	_flat_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flat_picker.fit_to_longest_item = false  # don't let long names widen the column
	_populate_flat_picker()
	vbox.add_child(_flat_picker)

	var walk_btn := Button.new()
	walk_btn.text = "▶ Walk path to selected"
	walk_btn.pressed.connect(_on_walk_flat_pressed)
	vbox.add_child(walk_btn)

	add_separator(vbox)

	# --- Group flowchart (root → members, as rows) ---
	add_section_title(vbox, "Group flowchart")
	# tune-exempt: browse selector that renders the group flowchart (an action); the booted
	# target is owned by ScenarioDebugSession, with a deliberate _DEFAULT_GROUP_ROOT default.
	_group_picker = OptionButton.new()  # tune-exempt: browse/navigation selector, not a persistable pref
	_group_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_group_picker.fit_to_longest_item = false
	_populate_group_picker()
	_group_picker.item_selected.connect(_on_group_selected)
	vbox.add_child(_group_picker)

	_flow_vbox = VBoxContainer.new()
	_flow_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_flow_vbox)

	# Render the first group so the section isn't blank on open.
	if _group_picker.item_count > 0:
		_on_group_selected(_group_picker.selected)


# --- Flat picker -----------------------------------------------------------

func _populate_flat_picker() -> void:
	_flat_picker.clear()
	var rows: Array = []
	for g in ScenarioGroupDatabase.all_groups():
		var root := int(g.get("group_root_id", -1))
		for m in g.get("members", []):
			rows.append({
				"id": int(m.get("scenario_id", -1)),
				"name": str(m.get("name", "?")),
				"role": str(m.get("role", "member")),
				"root": root,
			})
	rows.sort_custom(func(a, b): return a["id"] < b["id"])
	var select_idx := 0
	for i in rows.size():
		var r: Dictionary = rows[i]
		var tag := " [setup]" if r["role"] == "setup" else ""
		_flat_picker.add_item("%d: %s%s" % [r["id"], r["name"], tag], r["id"])
		if int(r["id"]) == _DEFAULT_MEMBER:
			select_idx = i
	if _flat_picker.item_count > 0:
		_flat_picker.select(select_idx)


func _on_walk_flat_pressed() -> void:
	if _flat_picker.selected < 0:
		return
	_walk_to(_flat_picker.get_item_id(_flat_picker.selected))


# --- Group flowchart -------------------------------------------------------

func _populate_group_picker() -> void:
	_group_picker.clear()
	var groups: Array = ScenarioGroupDatabase.all_groups()
	var select_idx := 0
	for i in groups.size():
		var g: Dictionary = groups[i]
		var root := int(g.get("group_root_id", -1))
		var bc := int(g.get("battle_conditionals_id", -1))
		var map_name := str(g.get("map_name", "MAP%03d" % int(g.get("map_id", 0))))
		_group_picker.add_item("root %d — %s (bc %d)" % [root, map_name, bc], root)
		if root == _DEFAULT_GROUP_ROOT:
			select_idx = i
	if _group_picker.item_count > 0:
		_group_picker.select(select_idx)


func _on_group_selected(index: int) -> void:
	_render_group_flowchart(_group_picker.get_item_id(index))


# Render `edges(bc_id)` as a readable column: the group root, then one row per
# member/edge target with the guard that advances to it and a "Walk here" button.
# This is the director's honest model — it re-evaluates the whole set each
# transition, so every edge is "root state → member".
func _render_group_flowchart(root_id: int) -> void:
	for child in _flow_vbox.get_children():
		child.queue_free()

	var group := ScenarioGroupDatabase.get_group_by_root(root_id)
	if group.is_empty():
		_flow_vbox.add_child(_dim_label("(no group)"))
		return
	var bc := int(group.get("battle_conditionals_id", -1))
	var edges := ScenarioDirector.new().edges(bc)

	# Member names for nicer row titles.
	var name_of: Dictionary = {}
	for m in group.get("members", []):
		name_of[int(m.get("scenario_id", -1))] = str(m.get("name", "?"))

	var root_row := HBoxContainer.new()
	var root_lbl := Label.new()
	root_lbl.text = "● root %d — %s" % [root_id, str(name_of.get(root_id, "setup"))]
	root_lbl.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	root_row.add_child(root_lbl)
	_flow_vbox.add_child(root_row)

	if edges.is_empty():
		_flow_vbox.add_child(_dim_label("  (no transitions in bc %d)" % bc))
		return

	for e in edges:
		var target := int(e["target"])
		_flow_vbox.add_child(_make_member_row(target,
			str(name_of.get(target, "member %d" % target)), str(e.get("guard", "-"))))


func _make_member_row(scenario_id: int, node_name: String, guard: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "  → %d: %s" % [scenario_id, node_name]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	header.add_child(title)

	var btn := Button.new()
	btn.text = "▶ Walk here"
	btn.pressed.connect(_walk_to.bind(scenario_id))
	header.add_child(btn)
	box.add_child(header)

	var guard_lbl := Label.new()
	guard_lbl.text = "      when: %s" % guard
	guard_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guard_lbl.custom_minimum_size = Vector2(_PANEL_WIDTH - 20, 0)
	guard_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.72))
	guard_lbl.add_theme_font_size_override("font_size", 11)
	box.add_child(guard_lbl)

	box.add_child(HSeparator.new())
	return box


func _dim_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.72))
	return lbl


# --- Shared: stage the walk and reload -------------------------------------

func _walk_to(scenario_id: int) -> void:
	ScenarioDebugSession.path_target_scenario_id = scenario_id
	# Clear any single-scenario pick so it doesn't fight the path root resolution.
	ScenarioDebugSession.selected_scenario_id = -1
	print("[ScenarioPathDebugPanel] walk → scenario %d (scene reload)" % scenario_id)
	get_tree().reload_current_scene()
