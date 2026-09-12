@tool
class_name UICombatManager
extends UIWindowHost
## Self-contained combat UI manager.
##
## Manages roster bars, detail menus (equipment, ability, stats, gambits),
## and popups (equipment, job, passive ability, action ability, learn, gambit editor).
##
## Parent scenes just call set_friendly_units() / set_enemy_units() and everything works.
##
## Extends UIWindowHost to provide screen-space positioning for UI elements.

const TunePort = ExMateriaPlatform.TunePort

## Emitted when a unit is selected

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const Gambit = ExMateriaAlmanac.Gambit
const GambitList = ExMateriaAlmanac.GambitList
const ItemDatabase = ExMateriaAlmanac.ItemDatabase
const JobDatabase = ExMateriaAlmanac.JobDatabase

signal unit_selected(unit: Node)

## Emitted when selection is cleared
signal selection_cleared()

## Emitted when equipment changes (for external hooks)
signal equipment_changed(unit: Node, slot: int, item_id: int)

## Emitted when job changes (for external hooks)
signal job_changed(unit: Node, job_id: String, is_sub_job: bool)


#region Child References

## Base layer containing roster bars and detail panel
@onready var _base_layer: Node3D = $BaseLayer if has_node("BaseLayer") else null

## Modal layer - sits a unit in front of the base UI plane so modal windows
## draw above the non-modal windows structurally (no z bookkeeping). See ADR-0010.
@onready var _modal_layer: Node3D = $ModalLayer if has_node("ModalLayer") else null

## Friendly roster bar (type: UIRosterBar)
@onready var friendly_roster: Node3D = $BaseLayer/FriendlyRoster if has_node("BaseLayer/FriendlyRoster") else null

## Enemy roster bar (type: UIRosterBar)
@onready var enemy_roster: Node3D = $BaseLayer/EnemyRoster if has_node("BaseLayer/EnemyRoster") else null

## Friendly vitals column (type: UIVitalsRoster) — full HP/MP/CT panels, one per
## unit. Alternative to [member friendly_roster]; toggled via set_vitals_view_enabled().
@onready var friendly_vitals: Node3D = $BaseLayer/FriendlyVitals if has_node("BaseLayer/FriendlyVitals") else null

## Enemy vitals column (type: UIVitalsRoster). Mirrored so portraits hug the right border.
@onready var enemy_vitals: Node3D = $BaseLayer/EnemyVitals if has_node("BaseLayer/EnemyVitals") else null

## Detail layer (shown when unit is selected)
@onready var _detail_layer: Node3D = $DetailLayer if has_node("DetailLayer") else null

## Detail menus
@onready var _equipment_menu: UIMenuFrame = $DetailLayer/EquipmentMenu if has_node("DetailLayer/EquipmentMenu") else null
@onready var _ability_menu: UIMenuFrame = $DetailLayer/AbilityMenu if has_node("DetailLayer/AbilityMenu") else null
@onready var _stats_menu: UIMenuFrame = $DetailLayer/StatsMenu if has_node("DetailLayer/StatsMenu") else null
@onready var _gambit_display: UIGambitDisplay = $DetailLayer/GambitDisplay if has_node("DetailLayer/GambitDisplay") else null
@onready var _learn_button: UIButton = $DetailLayer/LearnButton if has_node("DetailLayer/LearnButton") else null

## Popup instances (scene nodes)
@onready var _equipment_popup: UIEquipmentPopup = $ModalLayer/EquipmentPopup if has_node("ModalLayer/EquipmentPopup") else null
@onready var _job_popup: UIJobPopup = $ModalLayer/JobPopup if has_node("ModalLayer/JobPopup") else null
@onready var _passive_popup: UIPassiveAbilityPopup = $ModalLayer/PassiveAbilityPopup if has_node("ModalLayer/PassiveAbilityPopup") else null
@onready var _action_popup: UIActionAbilityPopup = $ModalLayer/ActionAbilityPopup if has_node("ModalLayer/ActionAbilityPopup") else null
@onready var _learn_panel: UILearnPanel = $ModalLayer/LearnPanel if has_node("ModalLayer/LearnPanel") else null
@onready var _gambit_editor: UIGambitEditor3 = $ModalLayer/GambitEditor if has_node("ModalLayer/GambitEditor") else null

#endregion

#region Internal State

## Currently selected unit
var _selected_unit: Node = null

## Unit arrays (stored for roster portrait updates)
var _friendly_units: Array = []
var _enemy_units: Array = []

## Debug state
var _show_click_area_debug: bool = false

## When true, the full vitals columns are shown instead of the compact rosters.
var _vitals_view: bool = false

#endregion


func _ready() -> void:
	_ensure_layers_exist()

	if Engine.is_editor_hint():
		_setup_editor_preview()
		return

	_register_screen_positions()
	_setup_roster_connections()
	_setup_menu_text_items()
	_setup_menu_click_areas()
	_connect_popups()
	_bind_roster_tunables()

	# Ensure detail layer starts hidden until unit selected
	if _detail_layer:
		_detail_layer.visible = false


#region Editor Preview

func _setup_editor_preview() -> void:
	await get_tree().process_frame
	_register_screen_positions()
	_setup_menu_text_items()
	if _detail_layer:
		_detail_layer.visible = true
	_apply_mock_data()


func _apply_mock_data() -> void:
	var mock_sprites = [0x80, 0x81, 0x82, 0x83]
	if friendly_roster:
		friendly_roster.frame_count = 4
		for i in range(4):
			friendly_roster.set_frame_sprite_id(i, mock_sprites[i % mock_sprites.size()])
	if enemy_roster:
		enemy_roster.frame_count = 4
		for i in range(4):
			enemy_roster.set_frame_sprite_id(i, mock_sprites[(i + 2) % mock_sprites.size()])

#endregion


func _ensure_layers_exist() -> void:
	if not _base_layer:
		_base_layer = Node3D.new()
		_base_layer.name = "BaseLayer"
		add_child(_base_layer)

	if not _modal_layer:
		_modal_layer = Node3D.new()
		_modal_layer.name = "ModalLayer"
		# Layer z-gaps order the NON-MODAL windows (DetailLayer over BaseLayer)
		# for both render and click: a front window's body absorber (UIFrame,
		# ~flush) must out-front a back window's buttons (UIClickableField, now a
		# tiny +0.05 nudge), so any gap > ~0.05 suffices. BaseLayer=0,
		# DetailLayer=1, ModalLayer=2 (uniform 1.0). MODAL isolation does NOT rely
		# on these gaps — the host grabs input behind an open modal (ADR-0061),
		# so a back layer can't be clicked through a modal at any z. Keep in sync
		# with the layer transforms in CombatUI.tscn.
		_modal_layer.position.z = 2.0
		add_child(_modal_layer)


#region Screen Position Registration

func _register_screen_positions() -> void:
	# Every window (rosters, detail menus, gambit display, learn button, the
	# modal pickers) exposes screen_pos and lives under a layer, so the host
	# auto-registers them all for placement by node name. See ADR-0010.
	register_window_tree()

#endregion


#region Menu Text Setup

func _setup_menu_text_items() -> void:
	# Equipment menu text items (matching UI2 config)
	if _equipment_menu:
		_add_menu_text(_equipment_menu, "Equipment", Vector2(5, -6), UIChar.FontPalette.STAT, 0.8)
		_add_menu_text(_equipment_menu, "R. Hand", Vector2(-25, 8), UIChar.FontPalette.STAT, 0.7)
		_add_menu_text(_equipment_menu, "---", Vector2(15, 9), UIChar.FontPalette.MENU, 0.7)
		_add_menu_text(_equipment_menu, "L. Hand", Vector2(-25, 18), UIChar.FontPalette.STAT, 0.7)
		_add_menu_text(_equipment_menu, "---", Vector2(15, 19), UIChar.FontPalette.MENU, 0.7)
		_add_menu_text(_equipment_menu, "Head", Vector2(-12, 29), UIChar.FontPalette.STAT, 0.7)
		_add_menu_text(_equipment_menu, "---", Vector2(16, 29), UIChar.FontPalette.MENU, 0.7)
		_add_menu_text(_equipment_menu, "Body", Vector2(-12, 39), UIChar.FontPalette.STAT, 0.7)
		_add_menu_text(_equipment_menu, "---", Vector2(16, 40), UIChar.FontPalette.MENU, 0.7)
		_add_menu_text(_equipment_menu, "Accs.", Vector2(-15, 49), UIChar.FontPalette.STAT, 0.7)
		_add_menu_text(_equipment_menu, "---", Vector2(16, 50), UIChar.FontPalette.MENU, 0.7)

	# Ability menu text items
	if _ability_menu:
		_add_menu_text(_ability_menu, "Ability", Vector2(5, -6), UIChar.FontPalette.STAT, 0.8)
		_add_menu_text(_ability_menu, "Job", Vector2(-9, 8), UIChar.FontPalette.STAT, 0.7)
		_add_menu_text(_ability_menu, "---", Vector2(15, 9), UIChar.FontPalette.MENU, 0.7)
		_add_menu_text(_ability_menu, "Sub. Job", Vector2(-32, 18), UIChar.FontPalette.STAT, 0.7)
		_add_menu_text(_ability_menu, "---", Vector2(16, 19), UIChar.FontPalette.MENU, 0.7)
		_add_menu_text(_ability_menu, "React.", Vector2(-19, 29), UIChar.FontPalette.STAT, 0.7)
		_add_menu_text(_ability_menu, "---", Vector2(16, 29), UIChar.FontPalette.MENU, 0.7)
		_add_menu_text(_ability_menu, "Supprt.", Vector2(-24, 39), UIChar.FontPalette.STAT, 0.7)
		_add_menu_text(_ability_menu, "---", Vector2(16, 40), UIChar.FontPalette.MENU, 0.7)
		_add_menu_text(_ability_menu, "Move", Vector2(-14, 49), UIChar.FontPalette.STAT, 0.7)
		_add_menu_text(_ability_menu, "---", Vector2(16, 50), UIChar.FontPalette.MENU, 0.7)

	# Stats menu - match UI2 layout exactly (23 items from ui_combat.json)
	if _stats_menu:
		_add_menu_text(_stats_menu, "Stats", Vector2(5, -6), UIChar.FontPalette.STAT, 0.8)    # idx 0
		_add_menu_text(_stats_menu, "Move", Vector2(4, 8), UIChar.FontPalette.STAT, 0.7)      # idx 1
		_add_menu_text(_stats_menu, "Jmp.", Vector2(3, 20), UIChar.FontPalette.MENU, 0.7)     # idx 2
		_add_menu_text(_stats_menu, "0", Vector2(21, 20), UIChar.FontPalette.MENU, 0.7)       # idx 3 - Jump value
		_add_menu_text(_stats_menu, "Spd.", Vector2(3, 32), UIChar.FontPalette.MENU, 0.7)     # idx 4
		_add_menu_text(_stats_menu, "00", Vector2(20, 32), UIChar.FontPalette.MENU, 0.7)      # idx 5 - Speed value
		_add_menu_text(_stats_menu, "Weapon", Vector2(38, 8), UIChar.FontPalette.STAT, 0.7)   # idx 6
		_add_menu_text(_stats_menu, "000", Vector2(38, 20), UIChar.FontPalette.MENU, 0.7)     # idx 7 - R-hand power
		_add_menu_text(_stats_menu, "00%", Vector2(58, 20), UIChar.FontPalette.MENU, 0.7)     # idx 8 - R-hand evade
		_add_menu_text(_stats_menu, "---", Vector2(38, 32), UIChar.FontPalette.MENU, 0.7)     # idx 9 - L-hand power
		_add_menu_text(_stats_menu, "--%", Vector2(58, 32), UIChar.FontPalette.MENU, 0.7)     # idx 10 - L-hand evade
		_add_menu_text(_stats_menu, "AT", Vector2(82, 8), UIChar.FontPalette.STAT, 0.7)       # idx 11
		_add_menu_text(_stats_menu, "00", Vector2(85, 20), UIChar.FontPalette.MENU, 0.7)      # idx 12 - PA
		_add_menu_text(_stats_menu, "00", Vector2(85, 32), UIChar.FontPalette.MENU, 0.7)      # idx 13 - MA
		_add_menu_text(_stats_menu, "C-EV", Vector2(105, 8), UIChar.FontPalette.STAT, 0.7)    # idx 14
		_add_menu_text(_stats_menu, "00%", Vector2(111, 20), UIChar.FontPalette.MENU, 0.7)    # idx 15 - C-EV phys
		_add_menu_text(_stats_menu, "00%", Vector2(111, 32), UIChar.FontPalette.MENU, 0.7)    # idx 16 - C-EV magic
		_add_menu_text(_stats_menu, "S-EV", Vector2(138, 8), UIChar.FontPalette.STAT, 0.7)    # idx 17
		_add_menu_text(_stats_menu, "00%", Vector2(144, 20), UIChar.FontPalette.MENU, 0.7)    # idx 18 - S-EV phys
		_add_menu_text(_stats_menu, "00%", Vector2(144, 32), UIChar.FontPalette.MENU, 0.7)    # idx 19 - S-EV magic
		_add_menu_text(_stats_menu, "A-EV", Vector2(173, 8), UIChar.FontPalette.STAT, 0.7)    # idx 20
		_add_menu_text(_stats_menu, "00%", Vector2(173, 20), UIChar.FontPalette.MENU, 0.7)    # idx 21 - A-EV phys
		_add_menu_text(_stats_menu, "00%", Vector2(173, 32), UIChar.FontPalette.MENU, 0.7)    # idx 22 - A-EV magic


func _add_menu_text(menu: UIMenuFrame, text: String, offset: Vector2, palette: UIChar.FontPalette, scale: float) -> int:
	var idx = menu.add_text(text, offset, palette)
	menu.set_text_scale(idx, scale)
	menu.set_text_space_width(idx, 1.0)
	return idx

#endregion


#region Menu Click Areas

func _setup_menu_click_areas() -> void:
	# Equipment menu click areas (slot value indices: 2, 4, 6, 8, 10)
	if _equipment_menu:
		var equipment_slot_indices = [2, 4, 6, 8, 10]
		for i in range(equipment_slot_indices.size()):
			var text_idx = equipment_slot_indices[i]
			var click_area = _equipment_menu.add_text_click_area(text_idx, "equipment_slot", Vector2(2, 1), Vector2(50, 10))
			if click_area:
				click_area.clicked.connect(_on_equipment_slot_clicked.bind(i))

	# Ability menu click areas (slot value indices: 2, 4, 6, 8, 10)
	if _ability_menu:
		var ability_slot_indices = [2, 4, 6, 8, 10]
		for i in range(ability_slot_indices.size()):
			var text_idx = ability_slot_indices[i]
			var click_area = _ability_menu.add_text_click_area(text_idx, "ability_slot", Vector2(2, 1), Vector2(50, 10))
			if click_area:
				click_area.clicked.connect(_on_ability_slot_clicked.bind(i))

	# Learn button signal
	if _learn_button:
		_learn_button.pressed.connect(_on_learn_button_pressed)

	# Gambit display row_clicked signal
	if _gambit_display:
		_gambit_display.row_clicked.connect(_on_gambit_row_clicked)

#endregion


#region Roster Management

func _setup_roster_connections() -> void:
	if friendly_roster:
		friendly_roster.frame_clicked.connect(_on_friendly_frame_clicked)
	if enemy_roster:
		enemy_roster.frame_clicked.connect(_on_enemy_frame_clicked)
	# Vitals columns mirror the roster's click->select behaviour.
	if friendly_vitals:
		friendly_vitals.frame_clicked.connect(_on_friendly_frame_clicked)
	if enemy_vitals:
		enemy_vitals.frame_clicked.connect(_on_enemy_frame_clicked)


## Set units for friendly roster (binds both the compact roster and the vitals
## column; only one is visible at a time — see set_vitals_view_enabled).
func set_friendly_units(units: Array) -> void:
	_friendly_units = units
	_populate_columns([friendly_roster, friendly_vitals], units)


## Set units for enemy roster (binds both the compact roster and the vitals column).
func set_enemy_units(units: Array) -> void:
	_enemy_units = units
	_populate_columns([enemy_roster, enemy_vitals], units)


## Bind a team's units into every present column view (roster bar + vitals
## column). Each exposes the same frame_count / set_frame_unit / set_frame_sprite_id
## surface, so one loop drives them all.
func _populate_columns(columns: Array, units: Array) -> void:
	for col in columns:
		if col:
			col.frame_count = units.size()
	for i in range(units.size()):
		var unit = units[i]
		var sprite_id = _get_unit_sprite_id(unit)
		for col in columns:
			if not col:
				continue
			col.set_frame_unit(i, unit)
			if sprite_id >= 0:
				col.set_frame_sprite_id(i, sprite_id)
		_wire_job_change_signal(unit)


## Subscribe to a unit's `unit_progression.job_changed` so the portrait
## refreshes regardless of which UI initiated the job change (production
## UIJobPopup, viewer debug overrides, scripted tests). Without this, only
## the popup handler's direct call refreshed the portrait.
func _wire_job_change_signal(unit: Node) -> void:
	if unit == null or not "unit_progression" in unit:
		return
	var prog = unit.unit_progression
	if prog == null or not prog.has_signal("job_changed"):
		return
	var cb := _on_unit_job_changed.bind(unit)
	if not prog.job_changed.is_connected(cb):
		prog.job_changed.connect(cb)


func _on_unit_job_changed(_old_job_id: String, _new_job_id: String, unit: Node) -> void:
	_update_roster_portrait_for_unit(unit)
	if unit == _selected_unit:
		# Mirror the popup-handler's full refresh chain (UICombatManager.gd:603+):
		# any caller of unit.change_job — production picker, debug override,
		# scripted test — gets the same downstream UI refresh.
		_update_equipment_menu(unit)
		_update_ability_menu(unit)
		_update_stats_menu(unit)
		_refresh_roster_stats_for_unit(unit)


## Get sprite_id from a unit, checking property first then method
func _get_unit_sprite_id(unit: Node) -> int:
	if "body_sprite_id" in unit:
		return unit.body_sprite_id
	if unit.has_method("get_sprite_id"):
		return unit.get_sprite_id()
	return -1

#endregion


#region Popup Management

## Connect each modal's domain signals. Lifecycle (closed / mutual exclusion)
## is owned by the host's open_modal — see ADR-0010 — so there is no
## closed-wiring here. The action picker is single-owned by the gambit editor,
## so its selection signal is wired there, not in the manager.
func _connect_popups() -> void:
	if _equipment_popup:
		_equipment_popup.item_equipped.connect(_on_equipment_item_equipped)
	if _job_popup:
		_job_popup.job_selected.connect(_on_job_selected)
	if _passive_popup:
		_passive_popup.passive_selected.connect(_on_passive_ability_selected)
	if _learn_panel:
		_learn_panel.ability_learned.connect(_on_ability_learned)
	if _gambit_editor:
		_gambit_editor.gambit_saved.connect(_on_gambit_saved)
		_gambit_editor.gambit_changed.connect(_on_gambit_changed)
		# The action picker is the gambit editor's private nested sub-window.
		if _action_popup:
			_gambit_editor.set_ability_popup(_action_popup)


# Open/close animation lives on UIModalWindow (UIModalWindow.animate_open);
# the modal lifecycle (open_modal / close_current_modal / is_modal_open) lives
# on the host (UIWindowHost). Per ADR-0010 there is no z bookkeeping —
# modals draw above non-modal windows structurally (ModalLayer offset).


## Dismiss the current modal (mutual exclusion) plus any stray dropdown —
## dropdowns can be open in a detail menu independent of a modal, so the
## host's close_current_modal() isn't enough on its own.
func _dismiss_open_ui() -> void:
	UIDropdown.close_any_open()
	close_current_modal()

#endregion


#region Selection Management

## Select a unit and show detail panel
func select_unit(unit: Node) -> void:
	if _selected_unit == unit:
		return

	_dismiss_open_ui()

	_selected_unit = unit

	if _detail_layer:
		_detail_layer.visible = unit != null

	if unit:
		_update_equipment_menu(unit)
		_update_ability_menu(unit)
		_update_stats_menu(unit)
		_update_gambit_display(unit)
		# Animate detail menus opening
		for menu in [_equipment_menu, _ability_menu, _stats_menu, _gambit_display]:
			if menu:
				UIModalWindow.animate_open(menu)

	unit_selected.emit(unit)


## Clear the current selection
func clear_selection() -> void:
	if _selected_unit == null:
		return

	_selected_unit = null

	if _detail_layer:
		_detail_layer.visible = false

	_dismiss_open_ui()
	selection_cleared.emit()


## Get the currently selected unit
func get_selected_unit() -> Node:
	return _selected_unit


## Check if a unit is selected
func has_selection() -> bool:
	return _selected_unit != null

#endregion


#region Data Binding

func _get_progression(unit: Node):
	if not unit:
		return null
	if "unit_stats" in unit and unit.unit_stats:
		if unit.unit_stats.has_method("get_progression"):
			return unit.unit_stats.get_progression()
	return null


func _update_equipment_menu(unit: Node) -> void:
	if not _equipment_menu or not unit:
		return

	var progression = _get_progression(unit)
	if not progression:
		return

	var slot_to_text = {0: 2, 1: 4, 2: 6, 3: 8, 4: 10}
	for slot in slot_to_text.keys():
		var text_idx = slot_to_text[slot]
		var item_id = progression.get_equipped_item(slot)
		var item_name = ItemDatabase.get_item_name(item_id) if item_id >= 0 else "---"
		_equipment_menu.update_text(text_idx, item_name)


func _update_ability_menu(unit: Node) -> void:
	if not _ability_menu or not unit:
		return

	var progression = _get_progression(unit)
	if not progression:
		return

	var job = JobDatabase.get_job(progression.current_job_id) if JobDatabase else null
	var job_name = job.get("name", "---") if job else "---"
	_ability_menu.update_text(2, job_name)

	var sub_job_name = progression.get_sub_job_name() if progression.get_sub_job_name() else "---"
	_ability_menu.update_text(4, sub_job_name)

	var reaction_name = progression.get_equipped_reaction_name() if progression.get_equipped_reaction_name() else "---"
	_ability_menu.update_text(6, reaction_name)

	var support_name = progression.get_equipped_support_name() if progression.get_equipped_support_name() else "---"
	_ability_menu.update_text(8, support_name)

	var movement_name = progression.get_equipped_movement_name() if progression.get_equipped_movement_name() else "---"
	_ability_menu.update_text(10, movement_name)


func _update_stats_menu(unit: Node) -> void:
	if not _stats_menu or not unit:
		return

	var progression = _get_progression(unit)
	if not progression:
		return

	_stats_menu.update_text(3, str(progression.get_jump()))
	_stats_menu.update_text(5, "%02d" % progression.get_effective_speed())
	_stats_menu.update_text(7, "%03d" % progression.get_weapon_power())
	_stats_menu.update_text(8, "%02d%%" % progression.get_weapon_evade())
	_stats_menu.update_text(9, "---")
	_stats_menu.update_text(10, "--%")
	_stats_menu.update_text(12, "%02d" % progression.get_effective_pa())
	_stats_menu.update_text(13, "%02d" % progression.get_effective_ma())
	var c_ev = progression.get_c_evade()
	_stats_menu.update_text(15, "%02d%%" % c_ev)
	_stats_menu.update_text(16, "%02d%%" % c_ev)
	_stats_menu.update_text(18, "%02d%%" % progression.get_physical_evade())
	_stats_menu.update_text(19, "%02d%%" % progression.get_magic_evade())
	_stats_menu.update_text(21, "00%")
	_stats_menu.update_text(22, "00%")


func _update_gambit_display(unit: Node) -> void:
	if not unit or not _gambit_display:
		return

	if not "gambit_list" in unit or not unit.gambit_list:
		_gambit_display.clear_rows()
		return

	var glist = unit.gambit_list
	for i in range(_gambit_display.get_row_count()):
		var gambit = glist.get_at(i) if i < glist.size() else null

		if gambit and not gambit.is_empty():
			# The six lines are GambitProse's since #1160 (ADR-0280 dec. 4) — the
			# gambit holds the rule, this layer decides how to say it.
			var lines = GambitProse.sentence_lines(gambit)
			_gambit_display.update_row_lines(i, lines)
		else:
			_gambit_display.update_row_lines(i, ["---", "", "", "", "", ""])

#endregion


#region Popup Show Methods

func _show_equipment_popup(slot: int) -> void:
	_dismiss_open_ui()
	if _equipment_popup and _selected_unit:
		_equipment_popup.show_for_slot(slot, _selected_unit)
		open_modal(_equipment_popup)


func _show_ability_popup(slot: int) -> void:
	_dismiss_open_ui()
	if not _selected_unit:
		return

	match slot:
		0:  # Job
			if _job_popup:
				_job_popup.show_jobs(false)
				open_modal(_job_popup)
		1:  # Sub-Job
			if _job_popup:
				_job_popup.show_jobs(true)
				open_modal(_job_popup)
		2:  # Reaction
			if _passive_popup:
				_passive_popup.show_for_type("Reaction")
				open_modal(_passive_popup)
		3:  # Support
			if _passive_popup:
				_passive_popup.show_for_type("Support")
				open_modal(_passive_popup)
		4:  # Movement
			if _passive_popup:
				_passive_popup.show_for_type("Movement")
				open_modal(_passive_popup)


func _show_learn_panel() -> void:
	_dismiss_open_ui()
	if _learn_panel and _selected_unit:
		var job_id: String = ""
		var progression = _get_progression(_selected_unit)
		if progression and "current_job_id" in progression:
			job_id = progression.current_job_id
		_learn_panel.open_for_job(job_id, _selected_unit)
		open_modal(_learn_panel)


func _show_gambit_editor(gambit_index: int) -> void:
	_dismiss_open_ui()
	if _gambit_editor and _selected_unit:
		# Roster-spawned units are always pre-bound to their entry's shared
		# GambitList, so edits persist with no writeback (ADR-0005). This
		# fallback only fires for standalone (non-roster) units, which have no
		# entry to persist to — so an unshared fresh list is correct there.
		if not "gambit_list" in _selected_unit or not _selected_unit.gambit_list:
			if _selected_unit.has_method("set_gambit_list"):
				_selected_unit.set_gambit_list(GambitList.new())
			else:
				return
		_gambit_editor.open_at(_selected_unit, gambit_index)
		open_modal(_gambit_editor)

#endregion


#region Click Handlers

func _on_equipment_slot_clicked(_field_type: String, _field_index: int, slot: int) -> void:
	if _selected_unit:
		_show_equipment_popup(slot)


func _on_ability_slot_clicked(_field_type: String, _field_index: int, slot: int) -> void:
	if _selected_unit:
		_show_ability_popup(slot)


func _on_learn_button_pressed(_button_id: String) -> void:
	if _selected_unit:
		_show_learn_panel()


func _on_gambit_row_clicked(row_index: int) -> void:
	if _selected_unit:
		_show_gambit_editor(row_index)

#endregion


#region Popup Callbacks

func _on_equipment_item_equipped(slot: int, item_id: int) -> void:
	if not _selected_unit:
		return

	_selected_unit.equip_item(slot, item_id)

	_update_equipment_menu(_selected_unit)
	_update_stats_menu(_selected_unit)
	_refresh_roster_stats_for_unit(_selected_unit)
	equipment_changed.emit(_selected_unit, slot, item_id)


func _on_job_selected(job_id: String) -> void:
	if not _selected_unit:
		return

	var is_sub_job = _job_popup and _job_popup._for_sub_job
	if is_sub_job:
		_selected_unit.set_sub_job(job_id)
	else:
		# Unit.change_job now folds the sprite_id + palette refresh, and
		# UICombatManager listens to unit_progression.job_changed so the
		# portrait refreshes automatically (see _wire_job_change_signal).
		_selected_unit.change_job(job_id)

	_update_ability_menu(_selected_unit)
	_update_stats_menu(_selected_unit)
	_refresh_roster_stats_for_unit(_selected_unit)
	job_changed.emit(_selected_unit, job_id, is_sub_job)


func _on_passive_ability_selected(slot_type: String, ability_id: int) -> void:
	if not _selected_unit:
		return

	match slot_type:
		"Reaction":
			_selected_unit.set_equipped_reaction(ability_id)
		"Support":
			_selected_unit.set_equipped_support(ability_id)
		"Movement":
			_selected_unit.set_equipped_movement(ability_id)

	_update_ability_menu(_selected_unit)
	_update_stats_menu(_selected_unit)


func _on_ability_learned(_ability_id: int) -> void:
	pass


func _on_gambit_saved(_gambit_index: int, _gambit: Gambit) -> void:
	if _selected_unit:
		_update_gambit_display(_selected_unit)


func _on_gambit_changed(_gambit: Gambit) -> void:
	if _selected_unit:
		_update_gambit_display(_selected_unit)


func _refresh_roster_stats_for_unit(unit: Node) -> void:
	for i in range(_friendly_units.size()):
		if _friendly_units[i] == unit:
			for col in [friendly_roster, friendly_vitals]:
				if col:
					col.refresh_frame_stats(i)
			return
	for i in range(_enemy_units.size()):
		if _enemy_units[i] == unit:
			for col in [enemy_roster, enemy_vitals]:
				if col:
					col.refresh_frame_stats(i)
			return


func _update_roster_portrait_for_unit(unit: Node) -> void:
	var sprite_id = _get_unit_sprite_id(unit)
	if sprite_id < 0:
		return
	for i in range(_friendly_units.size()):
		if _friendly_units[i] == unit:
			for col in [friendly_roster, friendly_vitals]:
				if col:
					col.set_frame_sprite_id(i, sprite_id)
			return
	for i in range(_enemy_units.size()):
		if _enemy_units[i] == unit:
			for col in [enemy_roster, enemy_vitals]:
				if col:
					col.set_frame_sprite_id(i, sprite_id)
			return

#endregion


#region Roster Click Handlers

func _on_friendly_frame_clicked(frame_index: int) -> void:
	if frame_index < _friendly_units.size():
		select_unit(_friendly_units[frame_index])


func _on_enemy_frame_clicked(frame_index: int) -> void:
	if frame_index < _enemy_units.size():
		select_unit(_enemy_units[frame_index])

#endregion


#region Input Handling

func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return

	if not visible:
		return

	if event is InputEventKey:
		var key_event: InputEventKey = event
		if key_event.pressed and key_event.keycode == KEY_ESCAPE:
			if close_current_modal():
				get_viewport().set_input_as_handled()
				return
			if has_selection():
				clear_selection()
				get_viewport().set_input_as_handled()

#endregion


#region Debug

## Swap the team displays between the compact rosters and the full vitals
## columns. Only the chosen pair is visible; the hidden Area3D click areas stop
## picking, so there is no click conflict. Driven by the `roster.use_vitals_view` Tune slug
## bound below, which is what kept this callable when #1070 deleted the panel that used to
## front it.
## Bind the roster-view placement knobs to their `roster.*` Tune slugs (ADR-0068).
## This manager OWNS them (it holds both vitals columns), so a committed override
## coalesces onto the roster at boot AND a scrub re-drives it in any scene — an F3 panel over
## these slugs is just a view (decision 12), which is why #1070 could delete the one that
## existed without touching a knob. The two columns are tuned
## INDEPENDENTLY (friendly vs enemy differ — screen side, mirrored), so each gets its
## OWN slug namespace (`roster.friendly.*` / `roster.enemy.*`); the Vector2 screen_pos
## is split into _x/_y float slugs. Defaults are read from each instance's resting
## @export state (the .tscn is the single home). Called only on the runtime path
## (past the _ready editor-guard), so no is_editor_hint check is needed here.
func _bind_roster_tunables() -> void:
	TunePort.bind_update(self, "roster.use_vitals_view", _vitals_view,
		func(v: bool) -> void: set_vitals_view_enabled(v))
	_bind_one_roster(friendly_vitals, "roster.friendly")
	_bind_one_roster(enemy_vitals, "roster.enemy")


# Affordance hints (ADR-0068 decision 11) — the SINGLE home for each roster knob's min/max/step,
# passed in the bind_update meta below so any F3 view reads them back rather than restating them
# (`TuneField` / `PanelApplicability` read the same meta; the roster's own panel went at #1070).
# (The DEFAULT stays per-instance/.tscn-sourced — a legit non-materializable home, per ADR M5.)
const _ROSTER_POS_HINT := {"min": 0.0, "max": 1.0, "step": 0.005}
const _ROSTER_SPACING_HINT := {"min": -40.0, "max": 120.0, "step": 1.0}
const _ROSTER_SHIFT_HINT := {"min": -120.0, "max": 120.0, "step": 1.0}
const _ROSTER_PPU_HINT := {"min": 0.005, "max": 0.5, "step": 0.00125}
const _ROSTER_SCALE_HINT := {"min": 0.25, "max": 4.0, "step": 0.05}


## Bind one UIVitalsRoster's placement props under `ns`. `r` is duck-typed (the
## @onready refs are Node3D); each apply writes the property (its @export setter
## rebuilds), and screen_pos additionally re-marks placement like the old panel did.
func _bind_one_roster(r, ns: String) -> void:
	if r == null:
		return
	TunePort.bind_update(self, ns + ".screen_pos_x", r.screen_pos.x,
		_apply_roster_screen_pos_x.bind(r), _ROSTER_POS_HINT)
	TunePort.bind_update(self, ns + ".screen_pos_y", r.screen_pos.y,
		_apply_roster_screen_pos_y.bind(r), _ROSTER_POS_HINT)
	TunePort.bind_update(self, ns + ".spacing", r.spacing,
		func(v: float) -> void: r.spacing = v, _ROSTER_SPACING_HINT)
	TunePort.bind_update(self, ns + ".mirror_text_shift", r.mirror_text_shift,
		func(v: float) -> void: r.mirror_text_shift = v, _ROSTER_SHIFT_HINT)
	TunePort.bind_update(self, ns + ".pixels_per_unit", r.pixels_per_unit,
		func(v: float) -> void: r.pixels_per_unit = v, _ROSTER_PPU_HINT)
	TunePort.bind_update(self, ns + ".assembly_scale", r.assembly_scale,
		func(v: float) -> void: r.assembly_scale = v, _ROSTER_SCALE_HINT)
	TunePort.bind_update(self, ns + ".portrait_scale", r.portrait_scale,
		func(v: float) -> void: r.portrait_scale = v, _ROSTER_SCALE_HINT)
	TunePort.bind_update(self, ns + ".mirrored", r.mirrored,
		func(v: bool) -> void: r.mirrored = v)


## screen_pos component setters — named (not inline multi-line lambdas) so the bind_update
## meta arg can follow cleanly. `.bind(r)` threads the column; Tune calls them with (v).
func _apply_roster_screen_pos_x(v: float, r) -> void:
	r.screen_pos = Vector2(v, r.screen_pos.y)
	mark_placement_dirty()


func _apply_roster_screen_pos_y(v: float, r) -> void:
	r.screen_pos = Vector2(r.screen_pos.x, v)
	mark_placement_dirty()


func set_vitals_view_enabled(on: bool) -> void:
	_vitals_view = on
	if friendly_roster:
		friendly_roster.visible = not on
	if enemy_roster:
		enemy_roster.visible = not on
	if friendly_vitals:
		friendly_vitals.visible = on
	if enemy_vitals:
		enemy_vitals.visible = on
	mark_placement_dirty()


## Whether the vitals columns (rather than the compact rosters) are showing.
func is_vitals_view_enabled() -> bool:
	return _vitals_view


## Toggle click area debug visibility (called from debug panel)
func set_click_area_debug_visible(debug_visible: bool) -> void:
	_show_click_area_debug = debug_visible

	for col in [friendly_roster, enemy_roster, friendly_vitals, enemy_vitals]:
		if col:
			col.show_click_area_debug = debug_visible

	if _equipment_menu:
		_equipment_menu.set_click_areas_visible(debug_visible)
	if _ability_menu:
		_ability_menu.set_click_areas_visible(debug_visible)
	if _stats_menu:
		_stats_menu.set_click_areas_visible(debug_visible)

	if _gambit_display:
		_gambit_display.set_click_areas_visible(debug_visible)


## Get current click area debug state
func is_click_area_debug_visible() -> bool:
	return _show_click_area_debug

#endregion
