@tool
extends Node3D
## Test scene for ui3 Combat UI components.
##
## Spawns a real cast — the catalogue's owned overlay on one side, the Gariland ENTD's
## non-blue slots on the other — and passes it to the CombatUI (UICombatManager)
## instance, which handles all UI wiring. Same two populations the arena and the story
## path use (ADR-0180); the units are hidden, this harness only wants their DATA.

const CatalogueReplay = ExMateriaCatalogue.CatalogueReplay
const Character = ExMateriaCatalogue.Character

@onready var combat_ui: UICombatManager = $CombatUI
@onready var _info_window: UIUnitInfoWindow = $CombatUI/BaseLayer/FieldInspectWindow
@onready var _dialogue_box: DialogueBox = $CombatUI/BaseLayer/DialogueBox

var friendly_units: Array = []
var enemy_units: Array = []
var _field_inspect: FieldInspectController
var _formation_map_host: FormationMapHost
## Camera-local depth for the map-hosted Formation screen in this harness — NEARER than CombatUI's
## seat (which sits at local -10 over the map) so the two do not z-fight while both are up here.
## Over the real map only one of them is mounted; ADR-0137 replaces CombatUI rather than joining it.
const MAP_HOST_LOCAL_Z := -8.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	print("\n=== UI3 COMBAT UI TEST ===")

	# Wait for scene to settle
	await get_tree().process_frame
	await get_tree().process_frame

	# Create units
	await _create_units()

	# Pass units to combat UI
	combat_ui.set_friendly_units(friendly_units)
	combat_ui.set_enemy_units(enemy_units)

	# Field-inspect info window (#91): pick a battlefield unit (collision_mask=4)
	# to open it. Here the 3D units are hidden (data only), so we also seed the
	# window with the first friendly unit so it is visible for layout tuning.
	_setup_field_inspect()

	# Boxed-portrait DialogueBox: seed a sample so the frame + portrait +
	# triangle + typewriter can be tuned visually (ui3 integration rule).
	_setup_dialogue_box()

	# The MAP-hosted Formation screen (ADR-0137), same integration rule. Only its LAYOUT is
	# tunable here: this harness has no battlefield, so there is no tile cursor to select with and
	# no camera pan to watch — it mounts camera-child exactly as it does over the map, with the
	# hover forced to its settled rest state so the band + docked pair can be dialled. The parts
	# that need a real map (the pan onto the breakout mark, the band subtracting from live terrain)
	# are verified headful over GPUArena; see `tests/FormationMapHostTest.gd`.
	_setup_formation_map_host()

	# Setup debug panel
	call_deferred("_setup_debug_panels")

	print("[CombatUITest] Ready - click on roster frames to test")


## Dev capture for dialogue-box geometry refinement — finish the typewriter, let
## the box settle, and write a PNG of the viewport for pixel-diffing. Invoked from
## the "Capture dialogue box" button on the UI3 Combat debug panel (ADR-0051: a
## method the panel calls, replacing the former DLG_SHOT env var). Interactive —
## does NOT quit. See handoff_dialogue_box_geometry_REFINEMENT.md.
func capture_dialogue_box_to(path: String = "/tmp/dlg_box.png") -> void:
	if _dialogue_box == null:
		push_warning("[CombatUITest] no dialogue box to capture")
		return
	_dialogue_box.finish_typing()
	for _i in range(8):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
	print("[CombatUITest] saved %s" % path)


func _setup_field_inspect() -> void:
	if _info_window == null:
		return
	_field_inspect = FieldInspectController.new()
	_field_inspect.name = "FieldInspect"
	add_child(_field_inspect)
	_field_inspect.setup($Camera3D, _info_window)
	if not friendly_units.is_empty():
		_field_inspect.inspect_unit(friendly_units[0])   # seed for tuning


func _setup_formation_map_host() -> void:
	var cam := $Camera3D as Camera3D
	if cam == null:
		return
	_formation_map_host = FormationMapHost.new()
	_formation_map_host.name = "FormationMapHost"
	cam.add_child(_formation_map_host)
	# The screen is authored for a keep-height ortho of 9.6 world units; this camera runs 12.6, so
	# the ROOT scales by 12.6/9.6 — the same correction it takes over the map.
	FormationMapHost.apply_mount_transform(_formation_map_host, cam, MAP_HOST_LOCAL_Z)
	# HOST-side panel mount (#1267). This scene builds a bare `FormationMapHost` rather than
	# going through the coordinator, so it is its OWN mount site — and it already registers
	# two panels of its own below, which is why `src/ui3/testing/` is not a `UI` member.
	FormationDebugPanels.register_formation_panels(_formation_map_host)
	await get_tree().process_frame
	if not friendly_units.is_empty():
		var character = FormationMapHost.character_for_unit(friendly_units[0])
		if character != null:
			_formation_map_host.show_character(character)
	_formation_map_host.force_hover(true)


func _setup_dialogue_box() -> void:
	if _dialogue_box == null:
		return
	# #1273 — this scene EMBEDS a DialogueBox in its .tscn rather than going through
	# `ScenarioPlayerScene`'s pool, so the inversion would have silently deleted the
	# typing and page-flip blips here. This file is host-side (ADR-0304 dec. 1), so
	# naming the cue in it is the same ruling, not an exception to it.
	UIWiring.wire_dialogue_box(_dialogue_box)
	# Use the first friendly unit's sprite for the speaker portrait when
	# available; else show portrait-less.
	var sprite_id := -1
	if not friendly_units.is_empty():
		sprite_id = friendly_units[0].body_sprite_id
	var tokens := [
		{"type": "color", "palette": 8},
		{"type": "text", "value": "Princess Ovelia"},
		{"type": "newline"},
		{"type": "color", "palette": 0},
		{"type": "text", "value": "Princess Ovelia, "},
		{"type": "delay", "frames": 0x08},
		{"type": "text", "value": "let's go."},
	]
	# 0x12 = 3-line portrait, Bottom align (box below unit → arrow UP). Positive
	# unit offset = unit to the right → portrait on the right.
	_dialogue_box.show_dialog(tokens, 0x12, sprite_id, 40.0)


## The ENTD this harness draws its enemy side from — Gariland (scenario 9), the same
## record the arena boots. A fixed record on purpose: this is a UI harness, not a
## scenario player, and it wants a stable cast to paint.
const HARNESS_ENTD := "388"

## Panels for four a side is all the CombatUI lays out.
const SIDE_CAP := 4


func _create_units() -> void:
	# The player side is the catalogue's owned overlay. It is established by folding a
	# MutationScript through CatalogueReplay (ADR-0201) — nothing else mints it, so seed
	# it here exactly as the arena does when it finds the overlay empty.
	if CharacterCatalog.owned_units().is_empty():
		CatalogueReplay.apply_action(
			{"mutations": GarilandMutationScript.owned_seed_deltas()}, CharacterCatalog)
	var owned: Array = CharacterCatalog.owned_units().slice(0, SIDE_CAP)
	print("[CombatUITest] Creating %d friendly units" % owned.size())
	friendly_units = await _spawn_side(owned, UnitStats.Team.PLAYER)

	# The enemy side is the ENTD's non-blue slots — no second store, and no invented
	# cast (ADR-0180). `from_entd_slot` is the same construction the navigator falls
	# back to for an unbound slot.
	var harness_slots := EntdBattle.combatant_slots(EntdBattle.record(HARNESS_ENTD))
	var split := EntdBattle.split_slots(harness_slots)
	# The level sentinel's ceiling is the record's, not the slot's (ADR-0289, #1179).
	var ceiling := Character.level_ceiling_for_slots(harness_slots)
	var foes: Array = []
	for slot in (split["team1"] as Array).slice(0, SIDE_CAP):
		foes.append(Character.from_entd_slot(slot, null, ceiling))
	print("[CombatUITest] Creating %d enemy units" % foes.size())
	enemy_units = await _spawn_side(foes, UnitStats.Team.ENEMY)


## Spawn one hidden [Unit] per [Character] through the ONE spawn seam. Hidden because
## this harness wants the DATA behind the panels, not a battlefield.
func _spawn_side(characters: Array, team: UnitStats.Team) -> Array:
	var out: Array = []
	for character in characters:
		var unit := UnitSpawn.build(character)
		if unit == null:
			continue
		add_child(unit, true)   # readable names: the seeded generics collide on job name
		await get_tree().process_frame
		UnitSpawn.bind_for_combat(unit, character, team)
		unit.unit_stats.current_hp = unit.unit_stats.max_hp
		unit.unit_stats.current_mp = unit.unit_stats.max_mp
		unit.visible = false  # Hide 3D unit, we just want the data
		out.append(unit)
		print("  - %s (sprite_id=0x%02X)" % [unit.name, unit.body_sprite_id])
	return out


func _setup_debug_panels() -> void:
	var panel = preload("res://src/ui3/testing/CombatUIDebugPanel.gd").new()
	panel.setup(combat_ui, self)
	DebugOverlay.register_panel(panel, DebugOverlay.Category.DESIGNER)

	# UI PAR scrub (ADR-0036): independent of world PAR, drives every UI3
	# element's mesh-width via PSXDisplay.live_ui_par.
	var ui_display_panel = UIDisplayDebugPanel.new()
	ui_display_panel.setup()
	DebugOverlay.register_panel(ui_display_panel, DebugOverlay.Category.DISPLAY, "ui_display")
