class_name NavigatorDebugPanel
extends BaseDebugPanel

## F3 "seek the story walk" panel for the game-state navigator (NavigatorMain) — the
## analogue of [ScenarioPathDebugPanel]'s "pick a root → pick a scenario" for the
## scenario player. Here the two levels are:
##   1. pick a GROUP ROOT to start the walk at (any group in the graph), then
##   2. pick a BEAT/ACTION within that run and press "Seek here".
##
## It is stateless w.r.t. the live navigator: like the scenario path panel it just
## parks the seek target in [ScenarioDebugSession] (`navigator_start_root` /
## `navigator_stop_root` / `navigator_start_action`) and `reload_current_scene()`;
## `NavigatorMain._ready` reads + consumes it, plans `plan_actions(root, stop)`, and
## `begin_at`s the chosen action. So the panel needs no rebind across the reload.

const TuneField = preload("res://src/debug/TuneField.gd")

## Any long label added here must set `autowrap_mode` + a `custom_minimum_size` of
## `_PANEL_WIDTH - 20`: a non-wrapping Label reports its full one-line width as its
## minimum and bursts the masonry column (DebugMasonryContainer sizes columns to the
## widest cell). The panel currently has none — the hint paragraphs were cut.
const _PANEL_WIDTH := 380
const _DEFAULT_ROOT := 1          # the Orbonne opening run's first group
const _NATURAL_END := 0           # stop sentinel: walk the ATTACK chain to its end
## Mirrors NavigatorMain.SKIP_PRE_BATTLE_SLUG (NavigatorMain has no class_name to import).
const _SKIP_PRE_BATTLE_SLUG := "navigator.skip_pre_battle"
## Mirrors NavigatorMain.AUTOPLAY_SLUG / AUTO_ADVANCE_NODE_SLUG / STOP_ON_TURN_SLUG.
const _AUTOPLAY_SLUG := "navigator.autoplay"
const _AUTO_ADVANCE_NODE_SLUG := "navigator.auto_advance_node"
const _STOP_ON_TURN_SLUG := "navigator.stop_on_turn"

var _root_picker: OptionButton    # tune-exempt: navigation launcher, target owned by ScenarioDebugSession
var _actions_vbox: VBoxContainer  # host the selected run's action rows
var _nav := GameNavigator.new()


func setup() -> void:
	panel_title = "Navigator"
	panel_category = Category.SCENARIO
	_build_ui()


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(_PANEL_WIDTH, 0)
	add_child(vbox)

	add_section_title(vbox, "Post-battle pose")
	var celebrate_cb := CheckBox.new()  # tune-exempt: session launcher, target owned by ScenarioDebugSession
	celebrate_cb.text = "Victory dance (else: return to normal)"
	celebrate_cb.set_pressed_no_signal(ScenarioDebugSession.navigator_celebrate_on_victory)
	celebrate_cb.toggled.connect(_on_celebrate_toggled)
	vbox.add_child(celebrate_cb)

	add_separator(vbox)

	add_section_title(vbox, "Pre-battle")
	# AUTOSAVE (green TuneField, ADR-0068): skip the universal pre-battle config breakpoint
	# and go straight to combat — the analogue of dialogue auto-advance. Read (register-read)
	# by NavigatorMain.run_pre_battle; the toggle persists across launches.
	var skip_cb := TuneField.add(vbox, "Skip pre-battle breakpoints (straight to combat)",
		_SKIP_PRE_BATTLE_SLUG, false, {}, Tune.Persist.AUTOSAVE) as CheckBox
	_controls["skip_pre_battle"] = skip_cb

	add_separator(vbox)

	add_section_title(vbox, "Autoplay")
	# A PROFILE over the three gates that already existed plus the map's. Each stays
	# independently settable — NavigatorMain ORs them — so "auto-advance the map but still
	# stop at the pre-battle breakpoint" is expressible, which is the combination you want
	# while debugging a chain.
	var autoplay_cb := TuneField.add(vbox, "Autoplay (the walk drives itself)",
		_AUTOPLAY_SLUG, false, {}, Tune.Persist.AUTOSAVE) as CheckBox
	_controls["autoplay"] = autoplay_cb

	var advance_cb := TuneField.add(vbox, "Auto-advance world-map nodes",
		_AUTO_ADVANCE_NODE_SLUG, false, {}, Tune.Persist.AUTOSAVE) as CheckBox
	_controls["auto_advance_node"] = advance_cb

	add_separator(vbox)

	add_section_title(vbox, "Battle")
	# The one gate autoplay turns OFF (NavigatorMain.stop_on_turn_armed): its set state is the
	# waiting one, so it sits under its own title rather than in the Autoplay block above, where
	# every neighbour ORs the profile in and this one ANDs its negation.
	#
	# Read at MOUNT, not per turn — scrubbing this mid-battle takes effect on the next battle.
	var stop_cb := TuneField.add(vbox, "Stop on every turn (Space to spend it)",
		_STOP_ON_TURN_SLUG, false, {}, Tune.Persist.AUTOSAVE) as CheckBox
	_controls["stop_on_turn"] = stop_cb

	add_separator(vbox)

	add_label(vbox, "Start group (root):")
	_root_picker = OptionButton.new()  # tune-exempt: navigation launcher, target owned by ScenarioDebugSession
	_root_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root_picker.fit_to_longest_item = false
	_populate_root_picker()
	_root_picker.item_selected.connect(_on_root_selected)
	vbox.add_child(_root_picker)

	add_separator(vbox)

	_actions_vbox = VBoxContainer.new()
	_actions_vbox.add_theme_constant_override("separation", 0)
	vbox.add_child(_actions_vbox)

	# Render the beats for the initially-selected root.
	if _root_picker.item_count > 0:
		_render_actions(_root_picker.get_item_id(_root_picker.selected))


func _populate_root_picker() -> void:
	_root_picker.clear()
	var groups: Array = ScenarioGroupDatabase.all_groups()
	var select_idx := 0
	for i in groups.size():
		var g: Dictionary = groups[i]
		var root := int(g.get("group_root_id", -1))
		var map_name := str(g.get("map_name", "MAP%03d" % int(g.get("map_id", 0))))
		_root_picker.add_item("root %d — %s" % [root, map_name], root)
		if root == _DEFAULT_ROOT:
			select_idx = i
	if _root_picker.item_count > 0:
		_root_picker.select(select_idx)


func _on_root_selected(index: int) -> void:
	_render_actions(_root_picker.get_item_id(index))


# List every ACTION in the run starting at `root` (walked to the ATTACK chain's
# natural end), each with a "Seek here" button that begins the walk at that action.
func _render_actions(root: int) -> void:
	for child in _actions_vbox.get_children():
		child.queue_free()

	var actions: Array = _nav.plan_actions(root, _NATURAL_END)
	if actions.is_empty():
		_actions_vbox.add_child(_dim_label("  (no actions — group %d does not chain)" % root))
		return

	for i in actions.size():
		_actions_vbox.add_child(_make_action_row(root, i, actions[i]))


func _make_action_row(root: int, index: int, action: Dictionary) -> Control:
	var header := HBoxContainer.new()

	var title := Label.new()
	title.text = "  %d. %s" % [index, _action_label(action)]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	header.add_child(title)

	var btn := Button.new()
	btn.text = "▶ Seek here"
	btn.pressed.connect(_seek_to.bind(root, index))
	header.add_child(btn)
	return header


func _action_label(action: Dictionary) -> String:
	match String(action.get("kind", "")):
		"scenario":
			var tail := "  [STOP]" if bool(action.get("terminal", false)) else ""
			return "scenario group %d%s" % [int(action.get("root", -1)), tail]
		"opener":
			return "opener cinematic — scn %d" % int(action.get("beat", {}).get("scenario_id", -1))
		"combat":
			return "COMBAT — ENTD battle (root %d)" % int(action.get("root", -1))
		"victory":
			return "victory / abduction — scn %d" % int(action.get("beat", {}).get("scenario_id", -1))
	return String(action.get("kind", "?"))


# --- Stage the seek and reload -----------------------------------------------

func _seek_to(root: int, action_index: int) -> void:
	ScenarioDebugSession.navigator_start_root = root
	ScenarioDebugSession.navigator_stop_root = _NATURAL_END
	ScenarioDebugSession.navigator_start_action = action_index
	print("[NavigatorDebugPanel] seek → root %d, action %d (scene reload)" % [root, action_index])
	get_tree().reload_current_scene()


func _on_celebrate_toggled(pressed: bool) -> void:
	# Parked in the session autoload; NavigatorMain reads it when it builds the
	# next battle's CombatLoop. No reload here — the flag survives to whichever
	# seek/restart the user triggers next.
	ScenarioDebugSession.navigator_celebrate_on_victory = pressed
	print("[NavigatorDebugPanel] post-battle pose → %s" % ("victory dance" if pressed else "faithful (return to normal)"))


func _dim_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.72))
	return lbl
