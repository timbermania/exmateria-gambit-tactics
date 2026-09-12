extends Node3D

## Unit Animation Viewer scene (ADR-0021, ADR-0022, ADR-0024).
##
## Loads the 1-unit seed (assets/roster/unit_animation_viewer_roster.json) through the
## ONE spawn seam ([UnitSpawn]), places it on UNIT_TILE, binds the embedded CombatUI
## (inside PlayerCamera.tscn) to it, and registers the world-state debug panel.
##
## **Unit state** (job, gender, equipment) is reconfigured through the
## production CombatUI — clicking the portrait opens detail menus,
## clicking an equipment slot opens UIEquipmentPopup, etc. Same code
## path as F5 / GPUArena. **World state** (activity, facing, attack
## vertical, ability id) is reconfigured through UnitAnimationViewerPanel
## in the F3 debug overlay — those axes have no production UI.

# ADR-0223 dec. 8 / ADR-0217 dec. 16 — `JsonAsset` is the PORT's, not the
# host's: it is a free-function loader with no host state, and leaving it in
# `src/` was goal #5 unmet on the TYPE axis for every addon that called it
# (#809). One alias line per file keeps this file's spelling (ADR-0211 dec. 4).
const JsonAsset = ExMateriaPlatform.JsonAsset

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const ResourceHotReload = ExMateriaSpriteRig.ResourceHotReload

## ADR-0215 dec. 2 / ADR-0217 dec. 7 — the sprite rig's VALUE VOCABULARY is the
## kernel's; the behaviour-bearing hosts keep their class names and their behaviour.
## This line is what keeps the use sites below spelled the way they were
## (ADR-0211 dec. 4).
const FacingDirection = ExMateriaSchema.Facing.Direction

const CharacterClass = ExMateriaCatalogue.Character
## The viewer's committed fixture: ONE unit, deliberately minimal — a level-1 male
## Squire with no weapon, which the F3 panel then reconfigures in place through the
## production paths. Read straight from disk, never through a save: the viewer is an
## authoring tool, and there is nothing here to persist.
const SEED_PATH := "res://assets/roster/unit_animation_viewer_roster.json"

const UNIT_TILE := Vector2i(6, 6)
const COMBAT_UI_PATH := "PlayerCamera/FocusPoint/Camera/CombatUI"
const MAP_NAME := "MAP116"  # Same map ProgressionTester uses — a clean test surface.

@onready var _map: Node3D = $ProceduralMap
@onready var _combat_ui: UICombatManager = get_node(COMBAT_UI_PATH)

var _character = null
var _unit: Unit
var _panel: UnitAnimationViewerPanel
var _hot_reload: ResourceHotReload


func _ready() -> void:
	await _wait_for_map()
	# Swap the default MapComposer map (MAP042) for MAP116 — same map
	# ProgressionTester uses. Pattern mirrors ProgressionTester._ready: two
	# frame yields after change_map for the new tiles to settle before the
	# unit is placed on UNIT_TILE.
	# #589: hand the map's two outputs to the host systems that consume them.
	# Replay-then-connect, so a map the composer auto-built in ITS `_ready`
	# (children ready before parents) is covered by the replay and every later
	# `change_map` by the connect. See BattlefieldWiring.
	BattlefieldWiring.wire_map(_map)
	_map.change_map(MAP_NAME)
	await get_tree().process_frame
	await get_tree().process_frame
	_load_seed()
	await _spawn_unit()
	_bind_combat_ui()
	_setup_panel()


func _wait_for_map() -> void:
	while not _map or not _map.has_method("get") or _map.get("lattice") == null:
		await get_tree().process_frame


## Read the one seeded [Character] off disk.
##
## This used to be a whole `BaseRoster` subclass — save path, asset seed, catalogue
## promotion, index-keyed spawn — to load ONE unit. It also inherited BaseRoster's
## `_promote_units_to_catalog()` under the default `roster:` slug prefix, so an
## authoring tool was quietly registering `roster:0` into the shared
## [CharacterCatalog] (a namespace the story navigator's scrub list did not even
## name). ADR-0180 retired the base; what the viewer actually needed was two lines.
func _load_seed() -> void:
	var units: Array = JsonAsset.load_dict(SEED_PATH).get("units", [])
	if units.is_empty():
		push_error("[UnitAnimationViewerScene] seed missing or empty: %s" % SEED_PATH)
		return
	_character = CharacterClass.from_dict(units[0])


func _spawn_unit() -> void:
	if _character == null:
		return
	_unit = UnitSpawn.build(_character)
	if _unit == null:
		push_error("[UnitAnimationViewerScene] spawn failed")
		return
	add_child(_unit)
	await get_tree().process_frame
	UnitSpawn.bind_for_combat(_unit, _character, UnitStats.Team.PLAYER)
	_unit.unit_stats.current_hp = _unit.unit_stats.max_hp
	_unit.unit_stats.current_mp = _unit.unit_stats.max_mp
	_unit.place_on_tile(UNIT_TILE.x, UNIT_TILE.y, _map)
	_unit.facing_direction = FacingDirection.SOUTH


func _bind_combat_ui() -> void:
	# CombatUI is embedded in PlayerCamera.tscn — it's already in the tree but
	# unbound until we hand it a cast. 1 friendly, 0 enemy.
	if _combat_ui == null:
		push_warning("[UnitAnimationViewerScene] CombatUI not found at %s" % COMBAT_UI_PATH)
		return
	_combat_ui.set_friendly_units([_unit])
	_combat_ui.set_enemy_units([])
	# Auto-select so the detail menus light up without the user having to click
	# the lone portrait first.
	_combat_ui.select_unit(_unit)


func _setup_panel() -> void:
	# The map's Skirts + Map Render panels. Mounted host-side (#555) — `MapComposer`
	# used to construct and register them itself, which is an ADR-0068 R1 violation:
	# the production owner of the tunables also instantiated their view. Placed here,
	# after the map is composed, so the pure-VIEW rows resolve their owners' defaults.
	MapDebugPanels.register_map_panels(_map)

	_panel = UnitAnimationViewerPanel.new()
	_panel.setup(_unit)
	DebugOverlay.register_panel(_panel, DebugOverlay.Category.UNIT)
	# Scene-local map.tres watcher (live-edit Q5 / Q9). Polls the file every
	# 0.5s; when the user saves in the Godot Inspector, the panel re-fires
	# its current activity so the BODY repaints with the new routing.
	_hot_reload = ResourceHotReload.new()
	add_child(_hot_reload)
	_hot_reload.resource_reloaded.connect(_panel.on_resource_reloaded)
