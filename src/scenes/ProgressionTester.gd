extends Node3D
## Progression Tester Scene
##
## Interactive test scene for the FFT-style progression system.
## Displays a unit with stats panel and controls for leveling and job changes.
##
## Controls:
## - Level Up/Down: Adjust unit level
## - Job Dropdown: Change current job
## - Base Type: Switch between Male/Female/Monster base stats

## ADR-0215 dec. 2 / ADR-0217 dec. 7 — the sprite rig's VALUE VOCABULARY is the
## kernel's; the behaviour-bearing hosts keep their class names and their behaviour.
## This line is what keeps the use sites below spelled the way they were
## (ADR-0211 dec. 4).
const FacingDirection = ExMateriaSchema.Facing.Direction

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const Lattice = ExMateriaBattlefield.Lattice

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const AbilityData = ExMateriaAlmanac.AbilityData
const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase
const ItemDatabase = ExMateriaAlmanac.ItemDatabase
const JobDatabase = ExMateriaAlmanac.JobDatabase
const JobLevelsDatabase = ExMateriaAlmanac.JobLevelsDatabase
const StatCalculator = ExMateriaAlmanac.StatCalculator
const UnitProgression = ExMateriaAlmanac.UnitProgression


const MAP_NAME = "MAP116"
const UNIT_POSITION = Vector2i(6, 6)

# All jobs will be loaded from JobDatabase
var all_jobs: Array = []  # [{id, name}, ...]

@onready var map: Node3D = $ProceduralMap

var unit: Unit
var lattice: Lattice

# UI components
var stats_label: RichTextLabel
var job_dropdown: OptionButton
var base_type_group: ButtonGroup
var level_label: Label

# Job tree panel components
var job_tree_container: VBoxContainer
var job_buttons: Dictionary = {}  # {job_id: Button}

# Ability learning panel components
var ability_panel: PanelContainer
var ability_list_container: HBoxContainer
var ability_buttons: Array = []

# Learned/Equipped panel components
var learned_panel: PanelContainer
var learned_list_container: VBoxContainer
var equipped_list_container: VBoxContainer

# Equipment panel components
var equipment_panel: PanelContainer
var equipment_slots_container: VBoxContainer
var item_dropdowns: Dictionary = {}  # {slot: OptionButton}


func _ready() -> void:
	print("\n=== PROGRESSION TESTER ===")

	# Load all jobs from database
	_load_all_jobs()
	print("[ProgressionTester] Loaded %d jobs" % all_jobs.size())

	# Wait for map to be ready
	await get_tree().process_frame
	await get_tree().process_frame

	# Change to test map
	map.change_map(MAP_NAME)
	await get_tree().process_frame
	await get_tree().process_frame

	# #589: hand the map's two outputs to the host systems that consume them.
	# Replay-then-connect, so a map the composer auto-built in ITS `_ready`
	# (children ready before parents) is covered by the replay and every later
	# `change_map` by the connect. See BattlefieldWiring.
	BattlefieldWiring.wire_map(map)
	lattice = map.lattice
	if not lattice:
		push_error("[ProgressionTester] Map has no lattice!")
		return

	print("[ProgressionTester] Map loaded: %s" % MAP_NAME)

	# Create unit with progression
	await _create_unit()

	# Create UI
	_setup_ui()
	_setup_job_tree_panel()
	_setup_learned_equipped_panel()
	_setup_equipment_panel()
	_setup_ability_panel()
	_setup_debug_panels()
	_update_stats_display()  # This also updates job tree and ability panel

	print("[ProgressionTester] Ready - Use controls to test progression")


func _setup_debug_panels() -> void:
	"""Register debug panels with the overlay."""
	# The map's Skirts + Map Render panels. Mounted host-side (#555) — `MapComposer`
	# used to construct and register them itself, which is an ADR-0068 R1 violation:
	# the production owner of the tunables also instantiated their view. Placed here,
	# after the map is composed, so the pure-VIEW rows resolve their owners' defaults.
	MapDebugPanels.register_map_panels(map)

	# Logging debug panel (toggle all logging flags)
	var logging_panel = LoggingDebugPanel.new()
	logging_panel.setup()
	DebugOverlay.register_panel(logging_panel, DebugOverlay.Category.LOGGING, "logging")


func _load_all_jobs() -> void:
	"""Load all jobs from JobDatabase."""
	all_jobs.clear()

	# Load all 160 jobs (0x00-0x9F)
	for offset in range(160):
		var job_id = "%02x" % offset
		var job = JobDatabase.get_job(job_id)
		if not job.is_empty():
			var name = job.get("name", "Unknown_%s" % job_id)
			# Add offset prefix for clarity
			all_jobs.append({"id": job_id, "name": "0x%02X %s" % [offset, name]})


func _find_job_index(job_id: String) -> int:
	"""Find index of job in all_jobs array."""
	for i in range(all_jobs.size()):
		if all_jobs[i].id == job_id:
			return i
	return -1


func _create_unit() -> void:
	"""Create a unit with FFT-style progression."""
	var unit_scene = load("res://assets/scenes/Unit.tscn")

	unit = unit_scene.instantiate()
	unit.name = "TestUnit"
	add_child(unit)
	await get_tree().process_frame

	unit.place_on_tile(UNIT_POSITION.x, UNIT_POSITION.y, map)

	# Initialize with progression system (Male Squire, level 1)
	unit.initialize_with_progression(
		UnitProgression.BaseStatType.MALE,
		"4a",  # Squire
		UnitStats.Team.PLAYER,
		1  # Starting level
	)
	unit.facing_direction = FacingDirection.SOUTH

	# Set initial sprite based on job
	_update_unit_sprite()

	print("  Unit created at (%d,%d) with progression" % [UNIT_POSITION.x, UNIT_POSITION.y])


func _setup_ui() -> void:
	"""Create control panel UI."""
	var canvas = CanvasLayer.new()
	canvas.name = "LeftPanelCanvas"
	add_child(canvas)

	# Main container for all left-side UI - uses VBoxContainer to stack panels
	var left_container = VBoxContainer.new()
	left_container.anchor_left = 0.0
	left_container.anchor_right = 0.0
	left_container.anchor_top = 0.0
	left_container.anchor_bottom = 1.0
	left_container.offset_left = 10
	left_container.offset_right = 310
	left_container.offset_top = 10
	left_container.offset_bottom = -10
	left_container.add_theme_constant_override("separation", 10)
	left_container.name = "LeftContainer"
	canvas.add_child(left_container)

	# Stats panel (top section) - in a scroll container
	var panel = PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_container.add_child(panel)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(280, 0)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "Progression Tester"
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	_add_separator(vbox)

	# Stats display (RichTextLabel for formatting)
	stats_label = RichTextLabel.new()
	stats_label.bbcode_enabled = true
	stats_label.fit_content = true
	stats_label.custom_minimum_size = Vector2(270, 300)
	stats_label.add_theme_font_size_override("normal_font_size", 11)
	stats_label.add_theme_font_size_override("mono_font_size", 11)
	vbox.add_child(stats_label)

	_add_separator(vbox)

	# Level controls
	var level_row = HBoxContainer.new()
	vbox.add_child(level_row)

	var level_down_btn = Button.new()
	level_down_btn.text = "- Level"
	level_down_btn.pressed.connect(_on_level_down)
	level_row.add_child(level_down_btn)

	level_label = Label.new()
	level_label.text = "Lv 1"
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.custom_minimum_size = Vector2(60, 0)
	level_row.add_child(level_label)

	var level_up_btn = Button.new()
	level_up_btn.text = "+ Level"
	level_up_btn.pressed.connect(_on_level_up)
	level_row.add_child(level_up_btn)

	# +10 levels button
	var level_up_10_btn = Button.new()
	level_up_10_btn.text = "+10"
	level_up_10_btn.pressed.connect(_on_level_up_10)
	level_row.add_child(level_up_10_btn)

	_add_separator(vbox)

	# JP controls
	var jp_row = HBoxContainer.new()
	vbox.add_child(jp_row)

	var jp_label = Label.new()
	jp_label.text = "JP:"
	jp_label.custom_minimum_size = Vector2(30, 0)
	jp_row.add_child(jp_label)

	var jp_50_btn = Button.new()
	jp_50_btn.text = "+50"
	jp_50_btn.pressed.connect(func(): _on_add_jp(50))
	jp_row.add_child(jp_50_btn)

	var jp_100_btn = Button.new()
	jp_100_btn.text = "+100"
	jp_100_btn.pressed.connect(func(): _on_add_jp(100))
	jp_row.add_child(jp_100_btn)

	var jp_500_btn = Button.new()
	jp_500_btn.text = "+500"
	jp_500_btn.pressed.connect(func(): _on_add_jp(500))
	jp_row.add_child(jp_500_btn)

	var jp_max_btn = Button.new()
	jp_max_btn.text = "Max (Lv8)"
	jp_max_btn.pressed.connect(func(): _on_add_jp(2100))
	jp_row.add_child(jp_max_btn)

	_add_separator(vbox)

	# Job dropdown
	var job_label = Label.new()
	job_label.text = "Job:"
	vbox.add_child(job_label)

	job_dropdown = OptionButton.new()
	for job in all_jobs:
		job_dropdown.add_item(job.name)
	# Default to Squire (0x4A)
	var squire_idx = _find_job_index("4a")
	if squire_idx >= 0:
		job_dropdown.select(squire_idx)
	job_dropdown.item_selected.connect(_on_job_selected)
	vbox.add_child(job_dropdown)

	_add_separator(vbox)

	# Base type radio buttons
	var type_label = Label.new()
	type_label.text = "Base Type:"
	vbox.add_child(type_label)

	base_type_group = ButtonGroup.new()

	var type_row = HBoxContainer.new()
	vbox.add_child(type_row)

	var male_btn = CheckBox.new()
	male_btn.text = "Male"
	male_btn.button_group = base_type_group
	male_btn.button_pressed = true
	male_btn.pressed.connect(func(): _on_base_type_changed(0))
	type_row.add_child(male_btn)

	var female_btn = CheckBox.new()
	female_btn.text = "Female"
	female_btn.button_group = base_type_group
	female_btn.pressed.connect(func(): _on_base_type_changed(1))
	type_row.add_child(female_btn)

	var monster_btn = CheckBox.new()
	monster_btn.text = "Monster"
	monster_btn.button_group = base_type_group
	monster_btn.pressed.connect(func(): _on_base_type_changed(2))
	type_row.add_child(monster_btn)

	_add_separator(vbox)

	# Brave/Faith controls
	var bf_label = Label.new()
	bf_label.text = "Brave/Faith (0-100):"
	vbox.add_child(bf_label)

	var brave_row = HBoxContainer.new()
	vbox.add_child(brave_row)

	var brave_label = Label.new()
	brave_label.text = "Brave:"
	brave_label.custom_minimum_size = Vector2(50, 0)
	brave_row.add_child(brave_label)

	var brave_spin = SpinBox.new()
	brave_spin.min_value = 0
	brave_spin.max_value = 100
	brave_spin.value = 50
	brave_spin.value_changed.connect(_on_brave_changed)
	brave_row.add_child(brave_spin)

	var faith_row = HBoxContainer.new()
	vbox.add_child(faith_row)

	var faith_label = Label.new()
	faith_label.text = "Faith:"
	faith_label.custom_minimum_size = Vector2(50, 0)
	faith_row.add_child(faith_label)

	var faith_spin = SpinBox.new()
	faith_spin.min_value = 0
	faith_spin.max_value = 100
	faith_spin.value = 50
	faith_spin.value_changed.connect(_on_faith_changed)
	faith_row.add_child(faith_spin)

	_add_separator(vbox)

	# Reset button
	var reset_btn = Button.new()
	reset_btn.text = "Reset to Level 1"
	reset_btn.pressed.connect(_on_reset)
	vbox.add_child(reset_btn)


func _add_separator(parent: Control) -> void:
	var sep = HSeparator.new()
	sep.custom_minimum_size = Vector2(0, 10)
	parent.add_child(sep)


func _setup_job_tree_panel() -> void:
	"""Create the job unlock tree panel on the right side."""
	var canvas = CanvasLayer.new()
	add_child(canvas)

	var panel = PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.offset_left = -320
	panel.offset_right = -10
	panel.offset_top = 10
	canvas.add_child(panel)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 600)
	panel.add_child(scroll)

	job_tree_container = VBoxContainer.new()
	scroll.add_child(job_tree_container)

	# Title
	var title = Label.new()
	title.text = "Job Unlock Tree"
	title.add_theme_font_size_override("font_size", 18)
	job_tree_container.add_child(title)

	_add_separator(job_tree_container)

	# Physical tree label
	var phys_label = Label.new()
	phys_label.text = "[Physical Branch]"
	phys_label.add_theme_color_override("font_color", Color.ORANGE)
	job_tree_container.add_child(phys_label)

	# Physical jobs - organized by tier
	_add_job_row(["4a"], 0)  # Squire (base)
	_add_job_row(["4c", "4d"], 1)  # Knight, Archer (tier 1)
	_add_job_row(["4e", "53"], 2)  # Monk, Thief (tier 2)
	_add_job_row(["56", "57"], 3)  # Geomancer, Dragoon (tier 3)
	_add_job_row(["59", "58", "5c"], 4)  # Ninja, Samurai, Dancer (tier 4)

	_add_separator(job_tree_container)

	# Magical tree label
	var magic_label = Label.new()
	magic_label.text = "[Magical Branch]"
	magic_label.add_theme_color_override("font_color", Color.CYAN)
	job_tree_container.add_child(magic_label)

	# Magical jobs
	_add_job_row(["4b"], 0)  # Chemist (base)
	_add_job_row(["4f", "50"], 1)  # White Mage, Black Mage (tier 1)
	_add_job_row(["55", "51"], 2)  # Mystic, Time Mage (tier 2)
	_add_job_row(["54", "52"], 3)  # Orator, Summoner (tier 3)
	_add_job_row(["5a", "5b"], 4)  # Arithmetician, Bard (tier 4)

	_add_separator(job_tree_container)

	# Special jobs
	var special_label = Label.new()
	special_label.text = "[Special]"
	special_label.add_theme_color_override("font_color", Color.YELLOW)
	job_tree_container.add_child(special_label)

	_add_job_row(["5d"], 5)  # Mime (requires both trees)

	_add_separator(job_tree_container)

	# Legend
	var legend_label = Label.new()
	legend_label.text = "Legend:"
	job_tree_container.add_child(legend_label)

	var legend_unlocked = Label.new()
	legend_unlocked.text = "  [Green] = Unlocked"
	legend_unlocked.add_theme_color_override("font_color", Color.GREEN)
	legend_unlocked.add_theme_font_size_override("font_size", 12)
	job_tree_container.add_child(legend_unlocked)

	var legend_locked = Label.new()
	legend_locked.text = "  [Red] = Locked"
	legend_locked.add_theme_color_override("font_color", Color.RED)
	legend_locked.add_theme_font_size_override("font_size", 12)
	job_tree_container.add_child(legend_locked)

	var legend_current = Label.new()
	legend_current.text = "  [Yellow Border] = Current Job"
	legend_current.add_theme_font_size_override("font_size", 12)
	job_tree_container.add_child(legend_current)


func _add_job_row(job_ids: Array, indent: int) -> void:
	"""Add a row of job buttons with indentation."""
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)

	# Add indentation spacer
	if indent > 0:
		var spacer = Control.new()
		spacer.custom_minimum_size = Vector2(indent * 15, 0)
		row.add_child(spacer)

	# Add arrow for non-base jobs
	if indent > 0:
		var arrow = Label.new()
		arrow.text = "└"
		arrow.add_theme_font_size_override("font_size", 12)
		row.add_child(arrow)

	# Add job buttons
	for job_id in job_ids:
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(90, 30)
		btn.add_theme_font_size_override("font_size", 11)
		btn.pressed.connect(_on_job_tree_button_pressed.bind(job_id))
		row.add_child(btn)
		job_buttons[job_id] = btn

	job_tree_container.add_child(row)


func _update_job_tree_display() -> void:
	"""Update all job buttons in the tree based on current unlock status."""
	if not unit or not unit.unit_progression:
		return

	var prog = unit.unit_progression

	for job_id in job_buttons:
		var btn: Button = job_buttons[job_id]
		var job_name = JobLevelsDatabase.get_job_name(job_id)
		var job_level = prog.get_job_level(job_id)
		var is_unlocked = prog.is_job_unlocked(job_id)
		var is_current = prog.current_job_id == job_id

		# Set button text: Name + Level
		if job_level > 0:
			btn.text = "%s Lv%d" % [job_name, job_level]
		else:
			btn.text = job_name

		# Set button colors based on status
		var style = StyleBoxFlat.new()
		if is_current:
			style.bg_color = Color(0.2, 0.5, 0.2)  # Dark green for current
			style.border_color = Color.YELLOW
			style.set_border_width_all(2)
		elif is_unlocked:
			style.bg_color = Color(0.15, 0.4, 0.15)  # Green for unlocked
			style.border_color = Color.GREEN
			style.set_border_width_all(1)
		else:
			style.bg_color = Color(0.4, 0.15, 0.15)  # Red for locked
			style.border_color = Color.RED
			style.set_border_width_all(1)

		style.set_corner_radius_all(4)
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("pressed", style)

		# Set tooltip showing requirements
		if is_unlocked:
			btn.tooltip_text = "%s\nJP: %d\nClick to change job" % [job_name, prog.get_job_jp(job_id)]
		else:
			var missing = prog.get_missing_prerequisites(job_id)
			btn.tooltip_text = "%s (LOCKED)\nRequires:\n  %s" % [job_name, "\n  ".join(missing)]


func _on_job_tree_button_pressed(job_id: String) -> void:
	"""Handle clicking a job in the tree."""
	if not unit or not unit.unit_progression:
		return

	var prog = unit.unit_progression

	if not prog.is_job_unlocked(job_id):
		var missing = prog.get_missing_prerequisites(job_id)
		print("[ProgressionTester] Cannot change to %s - requires: %s" % [
			JobLevelsDatabase.get_job_name(job_id),
			", ".join(missing)
		])
		return

	unit.change_job(job_id)
	_update_unit_sprite()
	_update_stats_display()  # This also updates job tree

	# Update dropdown to match
	var job_idx = _find_job_index(job_id)
	if job_idx >= 0:
		job_dropdown.select(job_idx)

	print("[ProgressionTester] Changed to %s via tree" % JobLevelsDatabase.get_job_name(job_id))


func _setup_learned_equipped_panel() -> void:
	"""Create the learned/equipped abilities panel below the stats panel."""
	# Find the left container created in _setup_ui
	var left_container = find_child("LeftContainer", true, false)
	if not left_container:
		push_error("[ProgressionTester] LeftContainer not found!")
		return

	learned_panel = PanelContainer.new()
	learned_panel.custom_minimum_size = Vector2(280, 200)
	left_container.add_child(learned_panel)

	var main_vbox = VBoxContainer.new()
	main_vbox.custom_minimum_size = Vector2(280, 0)
	learned_panel.add_child(main_vbox)

	# Learned Abilities Section
	var learned_title = Label.new()
	learned_title.text = "Learned Abilities"
	learned_title.add_theme_font_size_override("font_size", 14)
	learned_title.add_theme_color_override("font_color", Color.GREEN)
	main_vbox.add_child(learned_title)

	var learned_scroll = ScrollContainer.new()
	learned_scroll.custom_minimum_size = Vector2(0, 100)
	main_vbox.add_child(learned_scroll)

	learned_list_container = VBoxContainer.new()
	learned_list_container.add_theme_constant_override("separation", 2)
	learned_scroll.add_child(learned_list_container)

	_add_separator(main_vbox)

	# Equipped Abilities Section
	var equipped_title = Label.new()
	equipped_title.text = "Equipped Abilities"
	equipped_title.add_theme_font_size_override("font_size", 14)
	equipped_title.add_theme_color_override("font_color", Color.CYAN)
	main_vbox.add_child(equipped_title)

	var equipped_scroll = ScrollContainer.new()
	equipped_scroll.custom_minimum_size = Vector2(0, 100)
	main_vbox.add_child(equipped_scroll)

	equipped_list_container = VBoxContainer.new()
	equipped_list_container.add_theme_constant_override("separation", 2)
	equipped_scroll.add_child(equipped_list_container)


func _setup_equipment_panel() -> void:
	"""Create the equipment panel below learned/equipped panel."""
	# Find the left container created in _setup_ui
	var left_container = find_child("LeftContainer", true, false)
	if not left_container:
		push_error("[ProgressionTester] LeftContainer not found for equipment panel!")
		return

	equipment_panel = PanelContainer.new()
	equipment_panel.custom_minimum_size = Vector2(280, 220)
	left_container.add_child(equipment_panel)

	var main_vbox = VBoxContainer.new()
	main_vbox.custom_minimum_size = Vector2(280, 0)
	equipment_panel.add_child(main_vbox)

	# Title
	var title = Label.new()
	title.text = "Equipment"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color.ORANGE)
	main_vbox.add_child(title)

	_add_separator(main_vbox)

	equipment_slots_container = VBoxContainer.new()
	equipment_slots_container.add_theme_constant_override("separation", 4)
	main_vbox.add_child(equipment_slots_container)

	# Create slot rows
	_add_equipment_slot_row("Right Hand", UnitProgression.EquipSlot.RIGHT_HAND, "weapon")
	_add_equipment_slot_row("Left Hand", UnitProgression.EquipSlot.LEFT_HAND, "shield")
	_add_equipment_slot_row("Head", UnitProgression.EquipSlot.HEAD, "head")
	_add_equipment_slot_row("Body", UnitProgression.EquipSlot.BODY, "body")
	_add_equipment_slot_row("Accessory", UnitProgression.EquipSlot.ACCESSORY, "accessory")

	_add_separator(main_vbox)

	# Equipment stats summary
	var stats_label = Label.new()
	stats_label.name = "EquipStatsLabel"
	stats_label.add_theme_font_size_override("font_size", 11)
	stats_label.add_theme_color_override("font_color", Color.GRAY)
	main_vbox.add_child(stats_label)


func _add_equipment_slot_row(slot_name: String, slot: int, item_category: String) -> void:
	"""Add a row for an equipment slot with dropdown."""
	var hbox = HBoxContainer.new()
	equipment_slots_container.add_child(hbox)

	var label = Label.new()
	label.text = slot_name + ":"
	label.custom_minimum_size = Vector2(70, 0)
	label.add_theme_font_size_override("font_size", 11)
	hbox.add_child(label)

	var dropdown = OptionButton.new()
	dropdown.custom_minimum_size = Vector2(180, 0)
	dropdown.add_theme_font_size_override("font_size", 10)

	# Populate with items based on category
	dropdown.add_item("(Empty)", -1)
	dropdown.set_item_metadata(0, -1)

	var items = _get_items_for_slot(slot, item_category)
	for i in range(items.size()):
		var item = items[i]
		var display_name = item.name
		if item_category == "weapon":
			display_name = "%s (WP:%d)" % [item.name, item.get("weapon", {}).get("weapon_power", 0)]
		elif item_category == "shield":
			display_name = "%s (B:%d/%d)" % [item.name, item.get("shield", {}).get("physical_block", 0), item.get("shield", {}).get("magic_block", 0)]
		dropdown.add_item(display_name, item.id)
		dropdown.set_item_metadata(i + 1, item.id)

	dropdown.item_selected.connect(_on_equipment_changed.bind(slot))
	hbox.add_child(dropdown)
	item_dropdowns[slot] = dropdown


func _get_items_for_slot(slot: int, category: String) -> Array:
	"""Get items that can go in a slot."""
	var items: Array = []

	match category:
		"weapon":
			items = ItemDatabase.get_weapons()
		"shield":
			items = ItemDatabase.get_shields()
		"head":
			# Head armor (helmets, hats, hair adornments)
			for item in ItemDatabase.get_armor():
				if ItemDatabase.is_head_armor(item.id):
					items.append(item)
		"body":
			# Body armor (armor, clothing, robes)
			for item in ItemDatabase.get_armor():
				if ItemDatabase.is_body_armor(item.id):
					items.append(item)
		"accessory":
			items = ItemDatabase.get_accessories()

	return items


func _on_equipment_changed(index: int, slot: int) -> void:
	"""Handle equipment dropdown change."""
	if not unit or not unit.unit_progression:
		return

	var dropdown: OptionButton = item_dropdowns[slot]
	var item_id = dropdown.get_item_metadata(index)

	if item_id == -1:
		unit.unequip_item(slot)
		print("[ProgressionTester] Unequipped from slot %d" % slot)
	else:
		if unit.equip_item(slot, item_id):
			var item_name = ItemDatabase.get_item_name(item_id)
			print("[ProgressionTester] Equipped %s to slot %d" % [item_name, slot])
		else:
			# Revert dropdown if equip failed
			dropdown.select(0)
			print("[ProgressionTester] Failed to equip item %d to slot %d" % [item_id, slot])

	_update_equipment_display()
	_update_stats_display()


func _update_equipment_display() -> void:
	"""Update equipment panel display."""
	if not unit or not unit.unit_progression or not equipment_panel:
		return

	var prog = unit.unit_progression

	# Update dropdown selections to match current equipment
	for slot in item_dropdowns:
		var dropdown: OptionButton = item_dropdowns[slot]
		var equipped_id = prog.get_equipped_item(slot)

		# Find and select the matching item
		var found = false
		for i in range(dropdown.item_count):
			if dropdown.get_item_metadata(i) == equipped_id:
				dropdown.select(i)
				found = true
				break

		if not found:
			dropdown.select(0)  # Select "Empty"

	# Update stats summary
	var stats_label = equipment_panel.find_child("EquipStatsLabel", true, false)
	if stats_label:
		var bonuses = prog.get_equipment_stat_bonuses()
		var wp = prog.get_weapon_power()
		var phys_ev = prog.get_physical_evade()
		var mag_ev = prog.get_magic_evade()

		var parts: Array = []
		if wp > 0:
			parts.append("WP:%d" % wp)
		if phys_ev > 0 or mag_ev > 0:
			parts.append("Block:%d/%d" % [phys_ev, mag_ev])
		if bonuses.pa != 0:
			parts.append("PA%+d" % bonuses.pa)
		if bonuses.ma != 0:
			parts.append("MA%+d" % bonuses.ma)
		if bonuses.speed != 0:
			parts.append("Spd%+d" % bonuses.speed)
		if bonuses.move != 0:
			parts.append("Mv%+d" % bonuses.move)
		if bonuses.jump != 0:
			parts.append("Jmp%+d" % bonuses.jump)
		if bonuses.hp != 0:
			parts.append("HP%+d" % bonuses.hp)
		if bonuses.mp != 0:
			parts.append("MP%+d" % bonuses.mp)

		# Add elemental properties
		var elements = prog.get_equipment_elements()
		if DebugConfig.iteration_debug_enabled:
			print("[ProgressionTester] Equipment elements: %s" % str(elements))
		if not elements["weapon"].is_empty():
			parts.append("Wpn:" + ",".join(elements["weapon"]))
		if not elements["absorb"].is_empty():
			parts.append("Abs:" + ",".join(elements["absorb"]))
		if not elements["cancel"].is_empty():
			parts.append("Null:" + ",".join(elements["cancel"]))
		if not elements["half"].is_empty():
			parts.append("Half:" + ",".join(elements["half"]))
		if not elements["strengthen"].is_empty():
			parts.append("Str:" + ",".join(elements["strengthen"]))
		if not elements["weak"].is_empty():
			parts.append("Weak:" + ",".join(elements["weak"]))

		if DebugConfig.iteration_debug_enabled:
			print("[ProgressionTester] Parts array: %s" % str(parts))

		if parts.is_empty():
			stats_label.text = "No equipment bonuses"
		else:
			stats_label.text = "Bonuses: " + " ".join(parts)

		if DebugConfig.iteration_debug_enabled:
			print("[ProgressionTester] Final text: %s" % stats_label.text)


func _setup_ability_panel() -> void:
	"""Create the ability learning panel at the bottom-center of the screen."""
	var canvas = CanvasLayer.new()
	add_child(canvas)

	ability_panel = PanelContainer.new()
	# Span the center area between learned panel (left) and job tree (right)
	ability_panel.anchor_left = 0.0
	ability_panel.anchor_right = 1.0
	ability_panel.anchor_top = 1.0
	ability_panel.anchor_bottom = 1.0
	ability_panel.offset_left = 310   # Start after learned/equipped panel
	ability_panel.offset_right = -330  # Leave room for job tree panel
	ability_panel.offset_top = -200
	ability_panel.offset_bottom = -10
	canvas.add_child(ability_panel)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 180)
	ability_panel.add_child(scroll)

	var main_vbox = VBoxContainer.new()
	scroll.add_child(main_vbox)

	# Title row with JP info
	var title_row = HBoxContainer.new()
	main_vbox.add_child(title_row)

	var title = Label.new()
	title.text = "Learn Abilities (Current Job)"
	title.add_theme_font_size_override("font_size", 14)
	title_row.add_child(title)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(spacer)

	var jp_label = Label.new()
	jp_label.name = "JPCount"
	jp_label.add_theme_font_size_override("font_size", 12)
	title_row.add_child(jp_label)

	_add_separator(main_vbox)

	# Ability list container (will be populated dynamically)
	ability_list_container = HBoxContainer.new()
	ability_list_container.add_theme_constant_override("separation", 10)
	main_vbox.add_child(ability_list_container)


func _update_learned_equipped_panel() -> void:
	"""Update the learned and equipped abilities displays."""
	if not unit or not unit.unit_progression:
		return

	var prog = unit.unit_progression

	# Build set of equipped ability IDs for quick lookup
	var equipped_ids: Dictionary = {}
	if unit.equipped_abilities:
		for ability in unit.equipped_abilities.abilities:
			equipped_ids[ability.id] = true

	# Update learned abilities list
	if learned_list_container:
		for child in learned_list_container.get_children():
			child.queue_free()

		var learned = prog.get_learned_abilities()
		if learned.is_empty():
			var empty_label = Label.new()
			empty_label.text = "None learned yet"
			empty_label.add_theme_color_override("font_color", Color.GRAY)
			empty_label.add_theme_font_size_override("font_size", 11)
			learned_list_container.add_child(empty_label)
		else:
			for ability_id in learned:
				var ability_name = AbilityDatabase.get_ability_view(ability_id).name
				var is_equipped = equipped_ids.has(str(ability_id))

				var hbox = HBoxContainer.new()
				learned_list_container.add_child(hbox)

				var label = Label.new()
				if is_equipped:
					label.text = "✓ %s" % ability_name
					label.add_theme_color_override("font_color", Color.GREEN)
				else:
					label.text = "• %s" % ability_name
				label.add_theme_font_size_override("font_size", 11)
				label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				hbox.add_child(label)

				if not is_equipped:
					var equip_btn = Button.new()
					equip_btn.text = "Equip"
					equip_btn.add_theme_font_size_override("font_size", 9)
					equip_btn.custom_minimum_size = Vector2(40, 18)
					equip_btn.pressed.connect(_on_equip_ability.bind(ability_id))
					hbox.add_child(equip_btn)

	# Update equipped abilities list
	if equipped_list_container:
		for child in equipped_list_container.get_children():
			child.queue_free()

		if unit.equipped_abilities and unit.equipped_abilities.abilities.size() > 0:
			for ability in unit.equipped_abilities.abilities:
				var hbox = HBoxContainer.new()
				equipped_list_container.add_child(hbox)

				var label = Label.new()
				label.text = "• %s" % ability.display_name
				label.add_theme_font_size_override("font_size", 11)
				label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				hbox.add_child(label)

				var mp_label = Label.new()
				mp_label.text = "(%d MP)" % ability.mp_cost
				mp_label.add_theme_color_override("font_color", Color.CYAN)
				mp_label.add_theme_font_size_override("font_size", 10)
				hbox.add_child(mp_label)

				var unequip_btn = Button.new()
				unequip_btn.text = "X"
				unequip_btn.add_theme_font_size_override("font_size", 9)
				unequip_btn.custom_minimum_size = Vector2(20, 18)
				unequip_btn.tooltip_text = "Unequip"
				unequip_btn.pressed.connect(_on_unequip_ability.bind(ability.id))
				hbox.add_child(unequip_btn)
		else:
			var empty_label = Label.new()
			empty_label.text = "None equipped"
			empty_label.add_theme_color_override("font_color", Color.GRAY)
			empty_label.add_theme_font_size_override("font_size", 11)
			equipped_list_container.add_child(empty_label)


func _on_equip_ability(ability_id: int) -> void:
	"""Equip a learned ability."""
	if not unit or not unit.equipped_abilities:
		return

	var ability = AbilityData.from_database(ability_id)
	if ability:
		unit.equipped_abilities.add_ability(ability)
		print("[ProgressionTester] Equipped: %s" % ability.display_name)
		_update_learned_equipped_panel()


func _on_unequip_ability(ability_id: String) -> void:
	"""Unequip an ability."""
	if not unit or not unit.equipped_abilities:
		return

	var abilities = unit.equipped_abilities.abilities
	for i in range(abilities.size()):
		if abilities[i].id == ability_id:
			var name = abilities[i].display_name
			abilities.remove_at(i)
			print("[ProgressionTester] Unequipped: %s" % name)
			_update_learned_equipped_panel()
			return


func _update_ability_panel() -> void:
	"""Update the ability learning panel with current job's abilities."""
	if not unit or not unit.unit_progression or not ability_list_container:
		return

	var prog = unit.unit_progression

	# Clear existing buttons
	for child in ability_list_container.get_children():
		child.queue_free()
	ability_buttons.clear()

	# Update JP count
	var jp_label = ability_panel.find_child("JPCount", true, false)
	if jp_label:
		jp_label.text = "JP: %d" % prog.get_job_jp()

	# Get learnable abilities for current job
	var abilities = prog.get_learnable_abilities()

	if abilities.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No abilities to learn from this job"
		empty_label.add_theme_color_override("font_color", Color.GRAY)
		ability_list_container.add_child(empty_label)
		return

	# Group abilities by category
	var actions: Array = []
	var reactions: Array = []
	var supports: Array = []
	var movements: Array = []

	for ability in abilities:
		match ability.category:
			"action":
				actions.append(ability)
			"reaction":
				reactions.append(ability)
			"support":
				supports.append(ability)
			"movement":
				movements.append(ability)
			_:
				actions.append(ability)

	# Create category columns
	if not actions.is_empty():
		_add_ability_category("Actions", actions)
	if not reactions.is_empty():
		_add_ability_category("Reactions", reactions)
	if not supports.is_empty():
		_add_ability_category("Support", supports)
	if not movements.is_empty():
		_add_ability_category("Movement", movements)


func _add_ability_category(title: String, abilities: Array) -> void:
	"""Add a category column with abilities."""
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	ability_list_container.add_child(vbox)

	var title_label = Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 12)
	title_label.add_theme_color_override("font_color", Color.YELLOW)
	vbox.add_child(title_label)

	for ability in abilities:
		var btn = Button.new()
		var ability_id = int(ability.id)
		var jp_cost = int(ability.jp_cost)
		var learned = ability.learned
		var can_afford = ability.can_afford

		# Button text
		if learned:
			btn.text = "[✓] %s" % ability.name
		else:
			btn.text = "%s (%d JP)" % [ability.name, jp_cost]

		btn.custom_minimum_size = Vector2(140, 24)
		btn.add_theme_font_size_override("font_size", 11)

		# Style based on status
		var style = StyleBoxFlat.new()
		style.set_corner_radius_all(3)

		if learned:
			style.bg_color = Color(0.2, 0.4, 0.2)  # Green - learned
			style.border_color = Color.GREEN
			btn.disabled = true
		elif can_afford:
			style.bg_color = Color(0.2, 0.2, 0.4)  # Blue - can learn
			style.border_color = Color.CYAN
			btn.pressed.connect(_on_learn_ability_pressed.bind(ability_id))
		else:
			style.bg_color = Color(0.3, 0.2, 0.2)  # Red - can't afford
			style.border_color = Color.DARK_RED
			btn.disabled = true

		style.set_border_width_all(1)
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("pressed", style)
		btn.add_theme_stylebox_override("disabled", style)

		btn.tooltip_text = "%s\nJP Cost: %d\n%s" % [
			ability.name,
			jp_cost,
			"LEARNED" if learned else ("Click to learn" if can_afford else "Not enough JP")
		]

		vbox.add_child(btn)
		ability_buttons.append(btn)


func _on_learn_ability_pressed(ability_id: int) -> void:
	"""Handle learning an ability."""
	if not unit or not unit.unit_progression:
		return

	var ability_name = AbilityDatabase.get_ability_view(ability_id).name
	if unit.learn_ability(ability_id):
		print("[ProgressionTester] Learned: %s" % ability_name)
		_update_stats_display()  # This updates everything including ability panel
	else:
		print("[ProgressionTester] Failed to learn: %s" % ability_name)


func _update_stats_display() -> void:
	"""Update the stats label with current unit stats."""
	if not unit or not unit.unit_progression:
		stats_label.text = "[color=red]No progression data[/color]"
		return

	var prog = unit.unit_progression
	var job = JobDatabase.get_job(prog.current_job_id)

	# Build stats text with BBCode
	var text = ""
	text += "[b]%s[/b] (Level %d)\n" % [prog.get_current_job_name(), prog.level]
	text += "[color=gray]%s base stats[/color]\n\n" % _get_base_type_name(prog.base_stat_type)

	# Primary stats table
	text += "[table=3]"
	text += "[cell][b]Stat[/b][/cell][cell][b]Eff[/b][/cell][cell][b]Raw[/b][/cell]"

	text += _stat_row("HP", prog.get_effective_hp(), prog.raw_hp, job.get("hp_multiplier", 100))
	text += _stat_row("MP", prog.get_effective_mp(), prog.raw_mp, job.get("mp_multiplier", 100))
	text += _stat_row("Speed", prog.get_effective_speed(), prog.raw_speed, job.get("speed_multiplier", 100))
	text += _stat_row("PA", prog.get_effective_pa(), prog.raw_pa, job.get("pa_multiplier", 100))
	text += _stat_row("MA", prog.get_effective_ma(), prog.raw_ma, job.get("ma_multiplier", 100))

	text += "[/table]\n\n"

	# Movement
	text += "[b]Move:[/b] %d   [b]Jump:[/b] %d\n" % [prog.get_move(), prog.get_jump()]

	# Weapon power
	var wp = prog.get_weapon_power()
	if wp > 0:
		text += "[b]Weapon Power:[/b] %d\n" % wp

	# Evasion breakdown (C-EV + W-EV + S-EV)
	var c_ev = prog.get_c_evade()
	var w_ev = prog.get_weapon_evade()
	var phys_ev = prog.get_physical_evade()
	var mag_ev = prog.get_magic_evade()

	# Build evasion display string
	var evade_parts: Array = []
	if c_ev > 0:
		evade_parts.append("C-%d%%" % c_ev)
	if w_ev > 0:
		evade_parts.append("W-%d%%" % w_ev)
	if phys_ev > 0 or mag_ev > 0:
		evade_parts.append("S-%d/%d%%" % [phys_ev, mag_ev])

	if evade_parts.is_empty():
		text += "[b]Evade:[/b] None\n"
	else:
		var phys_total = mini(c_ev + w_ev + phys_ev, 99)
		var mag_total = mini(c_ev + mag_ev, 99)
		text += "[b]Evade:[/b] %s [color=gray](Phys:%d%% Mag:%d%%)[/color]\n" % [
			" ".join(evade_parts), phys_total, mag_total
		]

	# Brave and Faith (unit-level stats)
	text += "[b]Brave:[/b] %d   [b]Faith:[/b] %d\n" % [prog.brave, prog.faith]

	# Sprite mapping
	var is_female = prog.base_stat_type == UnitProgression.BaseStatType.FEMALE
	var sprite_id = JobDatabase.get_sprite_id(prog.current_job_id, is_female)
	var sprite_name = JobDatabase.get_sprite_name(sprite_id)
	text += "[b]Sprite:[/b] 0x%02X (%s)\n" % [sprite_id, sprite_name]

	# Elemental properties (combine job innate + equipment). jobs.json carries
	# decoded name arrays per ADR-0013 — `absorb_elements`, etc.
	var equip_elements = prog.get_equipment_elements()
	text += "\n[b]Elements:[/b]\n"
	text += "  [color=green]Absorb:[/color] %s\n" % _join_names_or_none(_merge_names(job.get("absorb_elements", []), equip_elements["absorb"]))
	text += "  [color=cyan]Nullify:[/color] %s\n" % _join_names_or_none(_merge_names(job.get("cancel_elements", []), equip_elements["cancel"]))
	text += "  [color=yellow]Half:[/color] %s\n" % _join_names_or_none(_merge_names(job.get("half_elements", []), equip_elements["half"]))
	text += "  [color=red]Weak:[/color] %s\n" % _join_names_or_none(_merge_names(job.get("weak_elements", []), equip_elements["weak"]))
	# Also show strengthen from equipment (not a job innate property)
	if not equip_elements["strengthen"].is_empty():
		text += "  [color=orange]Strengthen:[/color] %s\n" % ", ".join(equip_elements["strengthen"])
	# Show weapon element if equipped
	if not equip_elements["weapon"].is_empty():
		text += "  [color=purple]Weapon:[/color] %s\n" % ", ".join(equip_elements["weapon"])

	# Status effects (combine job innate + equipment)
	var equip_statuses = prog.get_equipment_statuses()

	# Permanent statuses from equipment (e.g., Angel Ring grants Reraise)
	if not equip_statuses["permanent"].is_empty():
		text += "\n[b]Permanent Status:[/b] [color=cyan]%s[/color]\n" % ", ".join(equip_statuses["permanent"])

	# Starting statuses from equipment (applied at battle start)
	if not equip_statuses["starting"].is_empty():
		text += "[b]Starting Status:[/b] [color=green]%s[/color]\n" % ", ".join(equip_statuses["starting"])

	# Status immunities (job + equipment). jobs.json `status_immunity` is now
	# a name array (set form) per ADR-0013.
	var combined_immunity = _merge_names(job.get("status_immunity", []), equip_statuses["immunity"])
	text += "[b]Status Immunity:[/b] %s\n" % _join_names_or_none(combined_immunity)

	# Innate abilities
	var innates = job.get("innate_abilities", [0, 0, 0, 0])
	var innate_str = _decode_innates(innates)
	text += "[b]Innate Abilities:[/b] %s\n" % innate_str

	# Equipment (simplified - just show the flags value for now)
	text += "[b]Equip Flags:[/b] 0x%08X\n" % job.get("equipment_flags", 0)

	# Skill set
	text += "[b]Skill Set ID:[/b] %d\n" % job.get("skill_set_id", 0)

	# Job unlocking info (only for generic jobs 0x4A-0x5D)
	var job_offset = prog.current_job_id.hex_to_int()
	if job_offset >= 0x4A and job_offset <= 0x5D:
		text += "\n[b]Job Progression:[/b]\n"

		# Current job level and JP
		var job_level = prog.get_job_level(prog.current_job_id)
		var job_jp = prog.get_job_jp(prog.current_job_id)
		var next_level_jp = JobLevelsDatabase.get_jp_for_level(job_level + 1) if job_level < 8 else 0
		text += "  Level %d (JP: %d" % [job_level, job_jp]
		if job_level < 8:
			text += " / %d for Lv%d" % [next_level_jp, job_level + 1]
		text += ")\n"

		# Unlocked/locked job counts
		var unlocked = prog.get_unlocked_jobs()
		var locked = prog.get_locked_jobs()
		text += "  [color=green]Unlocked:[/color] %d jobs  [color=red]Locked:[/color] %d jobs\n" % [unlocked.size(), locked.size()]

		# Show next few unlockable jobs (locked but close to requirements)
		if locked.size() > 0:
			text += "  [color=yellow]Closest to unlock:[/color]\n"
			var closest = _get_closest_to_unlock(prog, locked, 3)
			for job_info in closest:
				var missing = prog.get_missing_prerequisites(job_info.id)
				text += "    %s: %s\n" % [job_info.name, ", ".join(missing)]

	# Job multipliers (all of them)
	text += "\n[color=gray]Multipliers:[/color]\n"
	text += "[color=gray]  HP=%d%% MP=%d%% Spd=%d%% PA=%d%% MA=%d%%[/color]" % [
		job.get("hp_multiplier", 100),
		job.get("mp_multiplier", 100),
		job.get("speed_multiplier", 100),
		job.get("pa_multiplier", 100),
		job.get("ma_multiplier", 100)
	]

	stats_label.text = text
	level_label.text = "Lv %d" % prog.level

	# Update job tree if it exists
	if job_buttons.size() > 0:
		_update_job_tree_display()

	# Update ability panels if they exist
	if ability_list_container:
		_update_ability_panel()

	# Update learned/equipped panel if it exists
	if learned_list_container:
		_update_learned_equipped_panel()

	# Update equipment panel if it exists
	if equipment_slots_container:
		_update_equipment_display()


func _stat_row(name: String, effective: int, raw: int, multiplier: int) -> String:
	var mult_color = "green" if multiplier > 100 else ("red" if multiplier < 100 else "white")
	return "[cell]%s[/cell][cell][color=%s]%d[/color][/cell][cell][color=gray]%.1f[/color][/cell]" % [
		name, mult_color, effective, StatCalculator.raw_to_display(raw)
	]


# Element/status decoding lives at the parser boundary per ADR-0013;
# `jobs.json` carries decoded name arrays. The display layer only merges
# job-side and equipment-side names and joins them with commas.

func _merge_names(a: Array, b: Array) -> Array:
	"""Concatenate two name arrays, preserving order and de-duping."""
	var combined: Array = []
	for n in a:
		if n not in combined:
			combined.append(n)
	for n in b:
		if n not in combined:
			combined.append(n)
	return combined


func _join_names_or_none(names: Array) -> String:
	"""Join a name array with ', ', or return 'None' if empty."""
	return ", ".join(names) if not names.is_empty() else "None"


func _decode_innates(innate_ids: Array) -> String:
	"""Decode innate ability IDs."""
	var abilities: Array[String] = []
	for id in innate_ids:
		if id > 0:
			abilities.append(str(id))
	return ", ".join(abilities) if abilities else "None"


func _get_base_type_name(type: int) -> String:
	match type:
		0: return "Male"
		1: return "Female"
		2: return "Monster"
	return "Unknown"


func _get_closest_to_unlock(prog: UnitProgression, locked_jobs: Array, count: int) -> Array:
	"""Get the N locked jobs closest to being unlocked.

	Args:
		prog: Unit progression to check against
		locked_jobs: Array of locked job IDs
		count: Number of jobs to return

	Returns:
		Array of {id, name, missing_count} sorted by missing_count ascending
	"""
	var scored: Array = []

	for job_id in locked_jobs:
		var missing = prog.get_missing_prerequisites(job_id)
		var job_name = JobLevelsDatabase.get_job_name(job_id)
		scored.append({
			"id": job_id,
			"name": job_name,
			"missing_count": missing.size()
		})

	# Sort by number of missing prerequisites
	scored.sort_custom(func(a, b): return a.missing_count < b.missing_count)

	return scored.slice(0, count)


func _update_unit_sprite() -> void:
	"""Update unit's sprite texture and animation data based on current job and base type."""
	if not unit or not unit.unit_progression:
		return

	var prog = unit.unit_progression
	var is_female = prog.base_stat_type == UnitProgression.BaseStatType.FEMALE
	var new_sprite_id = JobDatabase.get_sprite_id(prog.current_job_id, is_female)

	# Setting sprite_id triggers _on_sprite_changed() which handles texture + animation data
	unit.body_sprite_id = new_sprite_id
	print("[ProgressionTester] Updated sprite to 0x%02X" % new_sprite_id)


func _on_level_up() -> void:
	if unit and unit.unit_progression:
		unit.level_up()
		_update_stats_display()
		print("[ProgressionTester] Level up -> %d" % unit.level)


func _on_level_up_10() -> void:
	if unit and unit.unit_progression:
		for i in range(10):
			unit.level_up()
		_update_stats_display()
		print("[ProgressionTester] +10 levels -> %d" % unit.level)


func _on_level_down() -> void:
	# Can't really "level down" in FFT - instead reset and re-level
	if unit and unit.unit_progression:
		var current_level = unit.unit_progression.level
		if current_level > 1:
			var new_level = current_level - 1
			_recreate_unit_at_level(new_level)
			print("[ProgressionTester] Level down -> %d" % new_level)


func _on_job_selected(index: int) -> void:
	if unit and unit.unit_progression and index < all_jobs.size():
		var job_id = all_jobs[index].id
		unit.change_job(job_id)
		_update_unit_sprite()
		_update_stats_display()
		print("[ProgressionTester] Changed job to %s" % all_jobs[index].name)


func _on_base_type_changed(type: int) -> void:
	if unit and unit.unit_progression:
		var current_level = unit.unit_progression.level
		var current_job = unit.unit_progression.current_job_id
		_recreate_unit_with_type(type, current_job, current_level)
		print("[ProgressionTester] Changed base type to %s" % _get_base_type_name(type))


func _on_reset() -> void:
	_recreate_unit_at_level(1)
	job_dropdown.select(0)
	print("[ProgressionTester] Reset to level 1 Squire")


func _on_brave_changed(value: float) -> void:
	if unit and unit.unit_progression:
		unit.unit_progression.brave = int(value)
		_update_stats_display()
		print("[ProgressionTester] Brave -> %d" % int(value))


func _on_faith_changed(value: float) -> void:
	if unit and unit.unit_progression:
		unit.unit_progression.faith = int(value)
		_update_stats_display()
		print("[ProgressionTester] Faith -> %d" % int(value))


func _on_add_jp(amount: int) -> void:
	if unit and unit.unit_progression:
		var old_level = unit.unit_progression.get_job_level()
		unit.unit_progression.add_jp(amount)
		var new_level = unit.unit_progression.get_job_level()
		_update_stats_display()
		if new_level > old_level:
			print("[ProgressionTester] +%d JP -> Job Level %d" % [amount, new_level])
		else:
			print("[ProgressionTester] +%d JP (total: %d)" % [amount, unit.unit_progression.get_job_jp()])


func _recreate_unit_at_level(target_level: int) -> void:
	"""Recreate unit at a specific level."""
	if not unit or not unit.unit_progression:
		return

	var base_type = unit.unit_progression.base_stat_type
	var job_id = unit.unit_progression.current_job_id
	_recreate_unit_with_type(base_type, job_id, target_level)


func _recreate_unit_with_type(base_type: int, job_id: String, level: int) -> void:
	"""Recreate unit with new base type."""
	# Remove old unit
	if unit:
		unit.queue_free()

	# Create new unit
	var unit_scene = load("res://assets/scenes/Unit.tscn")
	unit = unit_scene.instantiate()
	unit.name = "TestUnit"
	add_child(unit)

	# Need to wait for _ready
	await get_tree().process_frame

	unit.place_on_tile(UNIT_POSITION.x, UNIT_POSITION.y, map)
	unit.initialize_with_progression(base_type, job_id, UnitStats.Team.PLAYER, level)
	unit.facing_direction = FacingDirection.SOUTH

	_update_unit_sprite()
	_update_stats_display()
