class_name CombatHost
extends Node3D

## Shared mechanics for the two combat hosts (ADR-0018 follow-up).
##
## `GPUCombatTestBase` (test instrumentation) and `GPUArena` (production) both
## compose a [CombatLoop] and expose its battle state to their subclasses — and
## several tests subclass *each* host — so that accessor surface, plus the
## host-owned unit/terrain holders, was duplicated verbatim. It lives here now.
##
## Per ADR-0018's caution that a shared base must not re-introduce the coupling
## C8 removed, this base holds ONLY the accessor/sync **mechanics** and the shared
## data holders. It carries **no policy**: creating/wiring the loop, the `_rlog`
## logging, the `on_*` assertion hooks, the victory/quit behaviour, and the
## production UI all stay in the two hosts, which diverge sharply.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const Lattice = ExMateriaBattlefield.Lattice


const CombatLoopClass = preload("res://src/gpu/CombatLoop.gd")
const TICK_INTERVAL: float = 1.0 / 60.0
const GPU_FLAGS_DEAD_BIT: int = 1

# Composed loop + host-owned battle inputs (the host builds the Unit nodes; the
# loop drives them). Subclasses read these directly.
var combat_loop = null  # CombatLoop (untyped: the class_name may be absent from a stale global cache)
## The terrain PORT, taken off the map once at boot (ADR-0192 dec. 3: one typed
## fetch at the seam, `var lattice: Lattice = map.lattice`, typed from there on).
## Was `var terrain_index: TerrainIndex`, which is why every subclass's tile lookup
## read as "undeclared in this file" on the register — inference is per file and the
## declaration was here, not there.
var lattice: Lattice = null
var units: Array = []
var team0_units: Array = []
var team1_units: Array = []

# Regression logger — each host creates/injects it (enabled for tests, disabled for
# production) and the loop logs through it; declared here because subclasses read it.
var _rlog: RegressionLogger

# === Loop-state accessors =====================================================
# Read-only state is mirrored into plain FIELDS that hold the SAME object the loop
# holds (objects/dicts are reference types; the loop mutates them in place and
# refills `_all_states` via Array.assign, so the shared reference stays live with
# no per-tick copy). Populated by `_sync_loop_refs()` once the loop stands up its
# GPU + managers. They are NOT getter-only forwarding properties: GDScript drops a
# run of those (and every member after it) from the subclass-visible member table,
# which breaks subclasses with "Identifier not declared".
var gpu_simulator = null
var gpu_state_reader = null
var distance_field = null
var _all_states: Array = []
var _visual_bridge = null
var _combat_interp = null
var _spell_cast_active: Dictionary = {}
var _last_damage_tick: Dictionary = {}
var _last_evade_type: Dictionary = {}
var _hp_before_last_damage: Dictionary = {}
var projectile_manager = null
var effect_manager = null
# reaction routing is inlined on CombatLoop — no manager to mirror.

# The four mutable scalars a test writes (combat_active/victory_achieved to stop the
# loop, current_tick/_tick_accumulator for the manual-drive harness) forward to the
# loop so the write reaches it. A handful of get+set properties does not trigger the
# getter-only-run drop.
var current_tick:
	get: return combat_loop.current_tick if combat_loop != null else 0
	set(value):
		if combat_loop != null:
			combat_loop.current_tick = value

var _tick_accumulator:
	get: return combat_loop._tick_accumulator if combat_loop != null else 0.0
	set(value):
		if combat_loop != null:
			combat_loop._tick_accumulator = value

var combat_active:
	get: return combat_loop.combat_active if combat_loop != null else false
	set(value):
		if combat_loop != null:
			combat_loop.combat_active = value

var victory_achieved:
	get: return combat_loop.victory_achieved if combat_loop != null else false
	set(value):
		if combat_loop != null:
			combat_loop.victory_achieved = value


# The host drives the loop's pump; the loop has no _process of its own, so a
# subclass `super._process(delta)` still pumps exactly once. (The scalars above are
# forwarding properties, so no per-tick sync is needed.)
func _process(delta):
	if combat_loop:
		combat_loop.tick(delta)


func _sync_loop_refs() -> void:
	"""Adopt the loop's read-only state as shared references (see above). Idempotent;
	a host calls it after start_battle (and after the manual-drive harness's GPU setup)."""
	if not combat_loop:
		return
	gpu_simulator = combat_loop.gpu_simulator
	gpu_state_reader = combat_loop.gpu_state_reader
	distance_field = combat_loop.distance_field
	_all_states = combat_loop._all_states
	_visual_bridge = combat_loop._visual_bridge
	_combat_interp = combat_loop._combat_interp
	_spell_cast_active = combat_loop._spell_cast_active
	_last_damage_tick = combat_loop._last_damage_tick
	_last_evade_type = combat_loop._last_evade_type
	_hp_before_last_damage = combat_loop._hp_before_last_damage
	projectile_manager = combat_loop.projectile_manager
	effect_manager = combat_loop.effect_manager


func _is_unit_dead(state: Dictionary) -> bool:
	return (state.get("flags", 0) & GPU_FLAGS_DEAD_BIT) != 0
