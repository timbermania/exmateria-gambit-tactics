extends CombatHost

class_name GPUCombatTestBase

## Thin TEST HOST for GPU combat unit tests with full visuals (ADR-0018, C7).
##
## Builds the [Unit] nodes from its config hooks, composes a [CombatLoop] (via the
## shared [CombatHost] base), feeds it those units + a battle spec, and subscribes
## to its signals — wiring them to the regression log (`_rlog`), the overridable
## `on_*` assertion hooks, and the timeout/victory quit. The loop owns the per-tick
## pump, the apply, and the battle state; [CombatHost] exposes that state to the
## ~45 subclasses; this host owns the config translation and the test
## instrumentation. **Composition, not inheritance** of the loop — the host holds
## one, it is not one (see ADR-0018 and CONTEXT "Combat loop").
##
## Override these methods in subclasses:
## - get_test_name() -> String
## - get_team0_unit_configs() -> Array[Dictionary]: Unit spawn configs
## - get_team1_unit_configs() -> Array[Dictionary]: Unit spawn configs
## - get_gambits_for_unit(unit_idx: int, team: int) -> Array
## - on_state_changed(unit_idx: int, old_state: int, new_state: int)
## - on_hp_changed(unit_idx: int, old_hp: int, new_hp: int, delta: int)
## - on_awaiting_impact(unit_idx: int): firer entered LOGICAL_ACTIVITY_AWAITING_IMPACT (ADR-0032)
## - on_victory(winning_team: int)
##
## Battle state (combat_loop / units / current_tick / _all_states / gpu_state_reader
## / the managers / …), `_rlog`, `_sync_loop_refs()`, `_is_unit_dead()`, `_process`
## (loop pump) and the `TICK_INTERVAL` / `GPU_FLAGS_DEAD_BIT` consts all live on
## [CombatHost]; only the test-host config + instrumentation is below.

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const TerrainCell = ExMateriaSchema.TerrainCell

## ADR-0215 dec. 2 / ADR-0217 dec. 7 — the sprite rig's VALUE VOCABULARY is the
## kernel's; the behaviour-bearing hosts keep their class names and their behaviour.
## This line is what keeps the use sites below spelled the way they were
## (ADR-0211 dec. 4).
const FacingDirection = ExMateriaSchema.Facing.Direction
const ClockOwner = ExMateriaSchema.ClockOwner.Kind

## ADR-0211 dec. 4 — the sprite rig's façade is its whole symbol surface, and one
## alias line per file keeps every use site's spelling. It sits HERE, below the
## class docstring, and not under `extends`: a `const` above `class_name` is a
## parse error, and it took out this base and its ~45 subclasses at once.
const DisplayActivity = ExMateriaSpriteRig.DisplayActivity

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const ElementEncoder = ExMateriaAlmanac.ElementEncoder
const Gambit = ExMateriaAlmanac.Gambit
const GambitCondition = ExMateriaAlmanac.GambitCondition
const GambitList = ExMateriaAlmanac.GambitList
const ItemDatabase = ExMateriaAlmanac.ItemDatabase
const JobDatabase = ExMateriaAlmanac.JobDatabase
const StatusEncoder = ExMateriaAlmanac.StatusEncoder
const TargetSelector = ExMateriaAlmanac.TargetSelector
const UnitProgression = ExMateriaAlmanac.UnitProgression

@export var auto_start: bool = true
@export var ticks_per_frame: int = 1
@export var test_time_scale: float = 4.0
@export var max_ticks: int = 6000
@export var regression_logging: bool = true  # Structured logging for regression testing

@onready var map: Node3D = $ProceduralMap
@onready var combat_ui: UICombatManager = $PlayerCamera/FocusPoint/Camera/CombatUI
@onready var player_camera: Node3D = $PlayerCamera


## Ticks advanced per frame by a test that drives its OWN manual tick loop (the post-hit
## branch in GPUReactDurationTest). Preserves the harness's nominal throughput:
## `Engine.time_scale = test_time_scale` multiplies the real delta, so a test at time_scale
## 4.0 / ticks_per_frame 1 nominally advances 4 ticks a frame at 60 fps.
##
## NOT used to replace CombatLoop's own delta-driven pump. That was tried and reverted: a
## fixed 4 ticks/frame only equals the real rate at exactly 60 fps, and these GPU combat
## scenes run well below it, so GPURangedCombatTest and GPUEvasionMixedTest stopped
## resolving inside `max_ticks` and hit TIMEOUT at tick 6000. The real-time-locked pump is
## load-bearing for combat resolution; only a test's own private loop may step fixed.
func _fixed_ticks_per_frame() -> int:
	return maxi(1, int(round(test_time_scale * float(ticks_per_frame))))


func _ready():
	Engine.time_scale = test_time_scale
	_rlog = RegressionLogger.new(get_test_name(), regression_logging)

	print("\n=== %s ===" % get_test_name())
	print("Space - Pause/Resume")
	print("Ctrl+R - Reset")
	print("==================\n")

	await get_tree().process_frame
	await get_tree().process_frame

	# #589: hand the map's two outputs to the host systems that consume them.
	# Replay-then-connect, so a map the composer auto-built in ITS `_ready`
	# (children ready before parents) is covered by the replay and every later
	# `change_map` by the connect. See BattlefieldWiring.
	BattlefieldWiring.wire_map(map)
	# ADR-0192 dec. 3's clean fetch. It lands in a LOCAL annotated here and is stored
	# from there: `lattice` is declared on `CombatHost`, and the register's receiver
	# inference is per file, so a fetch landing straight into the inherited field reads
	# as "undeclared in this file".
	var lat: Lattice = map.lattice
	lattice = lat
	if not lattice:
		push_error("[%s] Map has no lattice!" % get_test_name())
		return

	await _create_units()
	_setup_combat_ui()
	_setup_debug_panels()

	_ensure_loop()
	combat_loop.start_battle(
		team0_units, team1_units, _build_gambits_array(),
		lattice, map, randi(), _build_battle_spec())
	_sync_loop_refs()

	# Log initial state for regression testing
	if regression_logging:
		_rlog.log_entry("TEST_START", {"name": get_test_name(), "units": units.size()})

	# Rotate camera as if Q was pressed twice
	if player_camera and player_camera.has_method("_rotate_around_terrain"):
		player_camera._rotate_around_terrain(1)
		player_camera._rotate_around_terrain(1)

	if auto_start:
		# Wait for camera rotation to settle before starting combat
		await get_tree().create_timer(1.0).timeout
		combat_active = true
		print("[%s] Combat started\n" % get_test_name())


func _ensure_loop() -> void:
	"""Create and wire the CombatLoop once. Idempotent — the manual-drive harness
	(GPUSeedReproTest) reaches it via the _setup_* shims before the normal path."""
	if combat_loop:
		return
	combat_loop = CombatLoopClass.new()
	combat_loop.name = "CombatLoop"
	combat_loop.battle_name = get_test_name()
	combat_loop._rlog = _rlog
	combat_loop.max_ticks = max_ticks
	combat_loop.ticks_per_frame = ticks_per_frame
	# The combat suite guards the victory dance (ADR-0026), so it opts into
	# celebrate mode; production (the navigator) defaults to the faithful pose.
	combat_loop.celebrate_on_victory = true
	combat_loop.lattice = lattice
	# Inject the overridable spell-effect seam (a Callable binds virtually, so a
	# subclass override of _spawn_spell_effect is what actually runs).
	combat_loop.spell_effect_hook = _spawn_spell_effect
	# Sibling seam for the PostGenericAttack hit cloud (see _spawn_hit_cloud).
	combat_loop.hit_cloud_hook = _spawn_hit_cloud
	add_child(combat_loop)
	combat_loop.state_changed.connect(_dispatch_state_changed)
	combat_loop.hp_changed.connect(on_hp_changed)
	combat_loop.victory.connect(_on_loop_victory)
	combat_loop.timed_out.connect(_on_loop_timed_out)


func _on_loop_victory(winner: int, team0_alive: int, team1_alive: int) -> void:
	"""The loop reports the result; the host logs it and quits (the test harness)."""
	# ADR-0026 anti-recurrence net — runs for EVERY test (subclasses override
	# on_victory, not this), before the per-test hook, so a regression in the
	# victory animation turns any test red.
	_assert_celebrating_invariant(winner)
	if winner == 0:
		_rlog.log_victory(0, current_tick)
		_rlog.output()
		print("\n[%s] TEAM 0 WINS at tick %d (%d remaining)" % [get_test_name(), current_tick, team0_alive])
		on_victory(0)
	elif winner == 1:
		_rlog.log_victory(1, current_tick)
		_rlog.output()
		print("\n[%s] TEAM 1 WINS at tick %d (%d remaining)" % [get_test_name(), current_tick, team1_alive])
		on_victory(1)
	else:
		_rlog.log_victory(-1, current_tick)
		_rlog.output()
		print("\n[%s] DRAW at tick %d" % [get_test_name(), current_tick])
		on_victory(-1)
	get_tree().quit()


func _assert_celebrating_invariant(winner: int) -> void:
	"""Anti-recurrence net for the victory animation (ADR-0026). Every surviving
	winner must be performing the CELEBRATING activity, with its BODY render
	field (`current_animation_front`) bound to the resolved celebrate slot — NOT
	merely its anim clock (`type1_playback.anim_id`), which read correct while
	the bobbing bug was live, so asserting on it would be a false green.

	Binds on the render field per ADR-0026. The core `activity == CELEBRATING`
	check holds for every sprite type (the resolver MISS for unauthored,
	non-humanoid types still sets the activity); the atlas/slot binding is
	required only for the authored humanoid types (TYPE1/TYPE3) — non-humanoid
	celebrate is an intentional MISS (ADR-0021). Prints `[FAIL]` on violation,
	which `run_all_tests.sh` detects."""
	if winner < 0:
		return  # draw — no winners to celebrate
	if not gpu_state_reader:
		return
	var states = gpu_state_reader.get_all_unit_states()
	var A = DisplayActivity.Activity
	for i in range(units.size()):
		var unit = units[i]
		if not is_instance_valid(unit):
			continue
		var st: Dictionary = states[i] if i < states.size() else {}
		if st.get("team", -1) != winner or _is_unit_dead(st):
			continue
		if unit.activity != A.CELEBRATING:
			print("\n[FAIL] ADR-0026: winner %s is not CELEBRATING (activity=%s)" % [
				unit.name, A.keys()[unit.activity]])
			continue
		var r = unit.last_resolution
		if r != null and r.source == "atlas":
			if unit.current_animation_front != str(r.body_slot):
				print("\n[FAIL] ADR-0026: winner %s render field stale (current_animation_front=%s, resolved celebrate slot=%d)" % [
					unit.name, unit.current_animation_front, r.body_slot])
		elif unit.get_seq_type() in ["TYPE1", "TYPE3"]:
			print("\n[FAIL] ADR-0026: winner %s (%s) did not resolve CELEBRATING to atlas (source=%s)" % [
				unit.name, unit.get_seq_type(), "null" if r == null else r.source])


func _on_loop_timed_out(tick: int) -> void:
	_rlog.log_entry("TIMEOUT", {"tick": tick})
	_rlog.output()
	print("[%s] TIMEOUT at tick %d" % [get_test_name(), tick])
	get_tree().quit()


func _unhandled_input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R and event.ctrl_pressed:
			get_tree().reload_current_scene()
			return
		if event.keycode == KEY_SPACE:
			combat_active = not combat_active
			print("[%s] %s" % [get_test_name(), "RESUMED" if combat_active else "PAUSED"])


# === Setup shims (manual-drive harness) =======================================
# GPUSeedReproTest stands up the GPU sim and drives step_tick itself, bypassing
# the pump. These delegate to the loop so that path stays byte-identical.

func _setup_distance_field():
	_ensure_loop()
	combat_loop.lattice = lattice
	combat_loop.setup_distance_field()


func _setup_gpu_simulator():
	_ensure_loop()
	combat_loop.setup_gpu_simulator()
	_sync_loop_refs()


# === Unit creation (host concern) =============================================

func _create_units():
	var team0_configs = get_team0_unit_configs()
	var team1_configs = get_team1_unit_configs()

	for cfg in team0_configs:
		var unit = await _spawn_unit_from_config(cfg, UnitStats.Team.PLAYER,
			FacingDirection.NORTH, UnitProgression.BaseStatType.MALE)
		team0_units.append(unit)
		units.append(unit)

	for cfg in team1_configs:
		var unit = await _spawn_unit_from_config(cfg, UnitStats.Team.ENEMY,
			FacingDirection.SOUTH, UnitProgression.BaseStatType.FEMALE)
		team1_units.append(unit)
		units.append(unit)


func _spawn_unit_from_config(cfg: Dictionary, team: UnitStats.Team, facing: int, base_stat_type: int) -> Unit:
	"""Instantiate, configure, and place a single unit from a config dictionary."""
	var unit_scene = load("res://assets/scenes/Unit.tscn")
	var team_prefix = "Team0" if team == UnitStats.Team.PLAYER else "Team1"
	var unit = unit_scene.instantiate()
	unit.name = cfg.get("name", "%s_Unit" % team_prefix)
	add_child(unit)
	await get_tree().process_frame

	if cfg.has("body_sprite_id"):
		unit.body_sprite_id = cfg["body_sprite_id"]

	unit.place_on_tile(cfg["pos_x"], cfg["pos_z"], map)
	unit.facing_direction = facing

	# Initialize with progression if job_id is available (enables UI stat panels)
	var job_id = cfg.get("job_id", "")
	if job_id != "":
		unit.initialize_with_progression(base_stat_type, job_id, team)
		_override_progression_stats(unit.unit_progression, cfg)
	else:
		_ensure_unit_progression(unit)
		unit.unit_stats.team = team

	# Apply stats (override progression-derived current values with config)
	unit.unit_stats.max_hp = cfg.get("max_hp", 100)
	unit.unit_stats.current_hp = cfg.get("hp", cfg.get("max_hp", 100))
	unit.unit_stats.max_mp = cfg.get("max_mp", 50)
	unit.unit_stats.current_mp = cfg.get("mp", cfg.get("max_mp", 50))

	# Equip weapon if specified
	if cfg.has("weapon_id"):
		if not unit.unit_progression:
			_ensure_unit_progression(unit)
		unit.unit_progression.equip_item(UnitProgression.EquipSlot.RIGHT_HAND, cfg["weapon_id"])

	# Equip shield if specified (caches frame/v_offset for shield_block reaction)
	if cfg.has("shield_id"):
		if not unit.unit_progression:
			_ensure_unit_progression(unit)
		unit.unit_progression.equip_item(UnitProgression.EquipSlot.LEFT_HAND, cfg["shield_id"])
		unit.update_shield_sprite(cfg["shield_id"])

	# Build UI gambit list from GPU gambit data
	var ui_gambits = _build_ui_gambit_list(cfg)
	if ui_gambits:
		unit.set_gambit_list(ui_gambits)

	# Enable tick-based animation — frames advance in lockstep with GPU ticks.
	# (The loop wires the animation signals in start_battle; it drives the units.)
	# All six playbacks ride the GPU tick (ADR-0037) — parity with GPUArena.
	# COMBAT-owned (ADR-0083).
	unit.clock_owner = ClockOwner.COMBAT

	if DebugConfig.iteration_debug_enabled:
		print("[%s] %s placed at (%d,%d)" % [get_test_name(), unit.name, cfg["pos_x"], cfg["pos_z"]])

	return unit


func _setup_combat_ui():
	"""Initialize combat UI with unit rosters."""
	if not combat_ui:
		push_warning("[%s] No CombatUI found" % get_test_name())
		return

	combat_ui.set_friendly_units(team0_units)
	combat_ui.set_enemy_units(team1_units)
	print("[%s] Combat UI initialized with %d friendly, %d enemy units" % [
		get_test_name(), team0_units.size(), team1_units.size()])


func _setup_debug_panels():
	var unit_shader_panel = UnitShaderDebugPanel.new()
	unit_shader_panel.setup(self, func(): return units)
	DebugOverlay.register_panel(unit_shader_panel, DebugOverlay.Category.GENERAL, "unit_shader")


# === Battle-spec translation (host-side, ADR-0018) ============================
# The loop speaks Unit nodes + a GPU battle spec, never test dict shapes; the
# test cfg → GPU config translation stays here.

func _build_battle_spec() -> Dictionary:
	var gpu_team0: Array = []
	var gpu_team1: Array = []
	var team0_configs = get_team0_unit_configs()
	var team1_configs = get_team1_unit_configs()
	for i in range(team0_units.size()):
		gpu_team0.append(_build_gpu_config(
			team0_units[i].movement_component.current_cell, team0_configs[i]))
	for i in range(team1_units.size()):
		gpu_team1.append(_build_gpu_config(
			team1_units[i].movement_component.current_cell, team1_configs[i]))
	return {"team0": gpu_team0, "team1": gpu_team1}


func _build_gambits_array() -> Array:
	"""Per-unit gambits indexed by global unit index (team0 then team1)."""
	var gambits: Array = []
	for i in range(team0_units.size()):
		gambits.append(get_gambits_for_unit(i, 0))
	for i in range(team1_units.size()):
		gambits.append(get_gambits_for_unit(team0_units.size() + i, 1))
	return gambits


func _ensure_unit_progression(unit: Node) -> void:
	"""Ensure unit has a UnitProgression component for equipment."""
	if unit.unit_progression:
		return

	# Create a minimal UnitProgression Resource (no longer a child node) and bind
	# it to the unit. Seed base stats the way the old Node _ready did (raw_hp==0
	# -> _initialize_from_base_stats), since a Resource has no _ready.
	var progression = UnitProgression.new()
	progression.initialize(progression.base_stat_type, progression.current_job_id)
	unit.unit_progression = progression

	# Connect equipment_changed signal to update weapon sprite
	if progression.has_signal("equipment_changed") \
			and not progression.equipment_changed.is_connected(unit._on_equipment_changed):
		progression.equipment_changed.connect(unit._on_equipment_changed)


func _override_progression_stats(progression: UnitProgression, cfg: Dictionary) -> void:
	"""Override progression raw stats so effective values match GPU config.

	Raw stats are fixed-point × 16384. Effective = (raw × multiplier / 100) / 16384.
	To get target effective value: raw = target × 16384 × 100 / multiplier.
	"""
	var job = JobDatabase.get_job(progression.current_job_id)
	var hp_mult = job.get("hp_multiplier", 100)
	var mp_mult = job.get("mp_multiplier", 100)
	var pa_mult = job.get("pa_multiplier", 100)
	var ma_mult = job.get("ma_multiplier", 100)
	var speed_mult = job.get("speed_multiplier", 100)

	if cfg.has("max_hp"):
		progression.raw_hp = _target_to_raw(cfg["max_hp"], hp_mult)
	if cfg.has("max_mp"):
		progression.raw_mp = _target_to_raw(cfg["max_mp"], mp_mult)
	if cfg.has("pa"):
		progression.raw_pa = _target_to_raw(cfg["pa"], pa_mult)
	if cfg.has("ma"):
		progression.raw_ma = _target_to_raw(cfg["ma"], ma_mult)
	if cfg.has("speed"):
		progression.raw_speed = _target_to_raw(cfg["speed"], speed_mult)


func _target_to_raw(target_effective: int, job_multiplier: int) -> int:
	"""Reverse-calculate raw stat from desired effective value and job multiplier."""
	if job_multiplier <= 0:
		return target_effective * 16384
	return (target_effective * 16384 * 100 + job_multiplier - 1) / job_multiplier


func _build_ui_gambit_list(cfg: Dictionary) -> GambitList:
	"""Convert GPU-format gambits to a UI GambitList for display.

	GPU gambits use numeric constants (action_type, action_id, cond_target_type).
	UI gambits use Gambit objects with TargetSelector, GambitCondition, and action names.
	"""
	var gpu_gambits = cfg.get("gambits", [])
	if gpu_gambits.is_empty():
		return null

	var gambit_list = GambitList.new()

	for gpu_gambit in gpu_gambits:
		if not gpu_gambit.get("enabled", true):
			continue

		# Build condition_target (who to check conditions against)
		var cond_target_type = gpu_gambit.get("cond_target_type", GPUConstants.TARGET_SELF)
		var condition_target = _gpu_target_to_selector(cond_target_type)

		# Build conditions
		var conditions: Array[GambitCondition] = []
		var gpu_conditions = gpu_gambit.get("conditions", [])
		for gpu_cond in gpu_conditions:
			var cond_type = gpu_cond.get("type", GPUConstants.COND_ALWAYS)
			var cond_value = gpu_cond.get("value", 0)
			match cond_type:
				GPUConstants.COND_ALWAYS:
					conditions.append(GambitCondition.always())
				GPUConstants.COND_HP_BELOW:
					conditions.append(GambitCondition.new(
						GambitCondition.Type.TARGET_HP,
						GambitCondition.Comparator.LESS_THAN,
						float(cond_value)))
				_:
					conditions.append(GambitCondition.always())
		if conditions.is_empty():
			conditions.append(GambitCondition.always())

		# Build action kind + ability id (tagged sum type, ADR-0023)
		var action_type = gpu_gambit.get("action_type", GPUConstants.ACTION_ATTACK)
		var action_id = gpu_gambit.get("action_id", 0)
		var action_kind := Gambit.ActionKind.ATTACK
		var ability_id := -1
		match action_type:
			GPUConstants.ACTION_WAIT:
				action_kind = Gambit.ActionKind.WAIT
			GPUConstants.ACTION_SPELL, GPUConstants.ACTION_ABILITY, GPUConstants.ACTION_ITEM:
				action_kind = Gambit.ActionKind.ABILITY
				ability_id = action_id
			_:
				action_kind = Gambit.ActionKind.ATTACK

		# Build action_target (who to act on)
		var action_target_type = gpu_gambit.get("action_target_type", GPUConstants.TARGET_THEM)
		var action_target: TargetSelector
		match action_target_type:
			GPUConstants.TARGET_THEM:
				action_target = TargetSelector.triggering()
			GPUConstants.TARGET_SELF:
				action_target = TargetSelector.self_()
			_:
				action_target = TargetSelector.triggering()

		var gambit = Gambit.create(condition_target, conditions, action_kind, ability_id, action_target)
		gambit_list.add(gambit)

	gambit_list.ensure_fixed_size()
	return gambit_list


func _gpu_target_to_selector(target_type: int) -> TargetSelector:
	"""Convert GPU target type constant to a TargetSelector."""
	match target_type:
		GPUConstants.TARGET_NEAREST_ENEMY:
			return TargetSelector.enemies().with_resolution(
				TargetSelector.ResolutionStrategy.NEAREST_FIRST)
		GPUConstants.TARGET_NEAREST_ALLY:
			return TargetSelector.friendlies().with_resolution(
				TargetSelector.ResolutionStrategy.NEAREST_FIRST)
		GPUConstants.TARGET_LOWEST_HP_ALLY:
			return TargetSelector.friendlies().with_resolution(
				TargetSelector.ResolutionStrategy.MOST_CRITICAL)
		GPUConstants.TARGET_SELF:
			return TargetSelector.self_()
		_:
			return TargetSelector.self_()


func _build_gpu_config(cell: Vector3i, cfg: Dictionary) -> Dictionary:
	# Issue #98 -- mirror the encode-boundary translation that
	# GPUCombatPacker._extract_unit_config does for live Unit nodes via
	# the shared StatusEncoder accessor. The test path bypasses
	# _extract_unit_config (it builds dicts directly), so the call has to
	# repeat here -- the translation logic itself does not.
	var infl = StatusEncoder.weapon_inflict_for_item(int(cfg.get("weapon_id", -1)))
	var weapon_inflict_mask: int = infl["mask"]
	var weapon_inflict_mode: int = infl["mode"]
	# Issue #110 -- same shape for the four element-defense masks. Tests
	# either pass `element_defense_items` (an Array[int] of equipped item ids
	# to compose over) for the realistic Flame-Shield-style witness, or
	# preseed the masks directly via `element_*_mask` for synthetic cases.
	var ed_items: Array = cfg.get("element_defense_items", [])
	var ed_equipment: Dictionary = {}
	for i in range(ed_items.size()):
		ed_equipment[i] = int(ed_items[i])
	var ed := ElementEncoder.defense_for_equipment(ed_equipment)
	# Issue #116 -- right-hand weapon's element_id derived from the same
	# `weapon_id` the live Unit equips, matching _extract_unit_config's
	# collapse from items.json `weapon.elements` to a single element_id. Tests
	# can override with `weapon_element` for synthetic cases (unarmed unit
	# forced to deal Fire damage, etc.).
	var weapon_element_derived := 0
	var weapon_id_for_element: int = int(cfg.get("weapon_id", -1))
	if weapon_id_for_element >= 0 and ItemDatabase.is_weapon(weapon_id_for_element):
		var w_elements: Array = ItemDatabase.get_elements(weapon_id_for_element).get("weapon_elements", [])
		var w_mask = ElementEncoder.mask_from_names(w_elements)
		for b in range(1, 9):
			if (w_mask & (1 << b)) != 0:
				weapon_element_derived = b
				break
	# Issue #111 — OR the job-innate element-defense arrays onto the equipment
	# composition (e.g. Bomb job absorbs Fire). Tests opt in by setting
	# `job_id`; configs without it are unchanged (empty job dict, OR no-op).
	var job_id: String = cfg.get("job_id", "")
	if job_id != "":
		var job := JobDatabase.get_job(job_id)
		ed["absorb_mask"] |= ElementEncoder.mask_from_names(job.get("absorb_elements", []))
		ed["cancel_mask"] |= ElementEncoder.mask_from_names(job.get("cancel_elements", []))
		ed["half_mask"]   |= ElementEncoder.mask_from_names(job.get("half_elements",   []))
		ed["weak_mask"]   |= ElementEncoder.mask_from_names(job.get("weak_elements",   []))
	# Issue #117 -- attacker-side Strengthen-Elem (BoostElem). Auto-include the
	# right-hand weapon (cfg.weapon_id, when set) so a Flame-Rod test attacker
	# inherits the same strengthen-Fire a live Unit with the same equipment
	# would (mirrors `_extract_unit_config` calling
	# ElementEncoder.strengthen_for_equipment over the full `prog.equipment`).
	# Tests can also pass `strengthen_items` for body/accessory slots (Black
	# Robe id 205 = Fire/Lightning/Ice) or preseed `strengthen_mask` directly
	# for synthetic cases.
	var strength_equipment: Dictionary = {}
	if weapon_id_for_element >= 0:
		strength_equipment[-1] = weapon_id_for_element
	var strength_items: Array = cfg.get("strengthen_items", [])
	for i in range(strength_items.size()):
		strength_equipment[i] = int(strength_items[i])
	var strengthen_derived := ElementEncoder.strengthen_for_equipment(strength_equipment)
	return {
		"pos_x": cell.x,
		"pos_z": cell.y,
		# 🔴 `cell.z` IS THE LEVEL, and dropping it here is the same loss ADR-0224
		# opens with — one layer up. The packer's live-`Unit` path grew a
		# `pos_level` extractor in PR A (`UNIT_CONFIG_SCHEMA`), but this is the
		# TEST path: `_write_unit_data` reads config dicts by key, so a dict that
		# never says `pos_level` takes the schema default of 0 and every GPU test
		# unit is seated on the ground no matter what cell it was handed. Harmless
		# while no test could express an upper cell, and a silent floor under
		# `GPUBridgeDescentTest` the moment one does.
		"pos_level": cell.z,
		"hp": cfg.get("hp", 100),
		"max_hp": cfg.get("max_hp", 100),
		"pa": cfg.get("pa", 10),
		"ma": cfg.get("ma", 10),
		"wp": cfg.get("wp", 5),
		"brave": cfg.get("brave", 50),
		"faith": cfg.get("faith", 50),
		"speed": cfg.get("speed", 100),
		"mp": cfg.get("mp", 50),
		"max_mp": cfg.get("max_mp", 50),
		"move": cfg.get("move", 4),
		"jump": cfg.get("jump", 3),
		"height": _cell_height(cell),
		"weapon_range": cfg.get("weapon_range", 1),
		"weapon_flags": cfg.get("weapon_flags", 1),
		"weapon_type": cfg.get("weapon_type", 0),
		# #1107 — the levered attack period, Q8 (256 == 1.0x). A test states the
		# FACTOR directly rather than authoring a lever set, because what a battle
		# can observe is the kernel's half (recovery arithmetic and the IDLE-edge
		# timer); the LeverSet half — composition, clamping, the unarmed identity —
		# is pure arithmetic and is asserted in `LeverSetTest`, which needs no
		# battle. Two halves, each tested by the cheapest kind that can fail it
		# (test charter clause 2).
		"attack_period_factor_q8": cfg.get("attack_period_factor_q8", 256),
		"weapon_inflict_mask": weapon_inflict_mask,
		"weapon_inflict_mode": weapon_inflict_mode,
		"element_absorb_mask": cfg.get("element_absorb_mask", ed["absorb_mask"]),
		"element_cancel_mask": cfg.get("element_cancel_mask", ed["cancel_mask"]),
		"element_half_mask": cfg.get("element_half_mask", ed["half_mask"]),
		"element_weak_mask": cfg.get("element_weak_mask", ed["weak_mask"]),
		"weapon_element": cfg.get("weapon_element", weapon_element_derived),
		"strengthen_mask": cfg.get("strengthen_mask", strengthen_derived),
		"c_ev": cfg.get("c_ev", 0),
		"s_ev": cfg.get("s_ev", 0),
		"w_ev": cfg.get("w_ev", 0),
		"s_ev_mag": cfg.get("s_ev_mag", 0),
		"reaction_ability": cfg.get("reaction_ability", -1),
		"status_flags_lo": cfg.get("status_flags_lo", 0),
		"status_flags_hi": cfg.get("status_flags_hi", 0),
		"status_timers": cfg.get("status_timers", []),
		"pending_heal_target": cfg.get("pending_heal_target", -1),
		"pending_heal_amount": cfg.get("pending_heal_amount", 0),
	}


## Overridable presentation seam (ADR-0018): the loop calls this through its
## injected `spell_effect_hook`. Tests override it (and call super) to observe the
## spawned EffectInstance; the default just forwards to the effect manager.
func _spawn_spell_effect(caster: Unit, target: Unit, ability_id: int, effect_id: int):
	"""Thin wrapper for subclass override compatibility (super._spawn_spell_effect)."""
	effect_manager.spawn_spell_effect(caster, target, ability_id, effect_id)


## Overridable presentation seam (ADR-0018): the loop calls this through its
## injected `hit_cloud_hook`. Tests override it (and call super) to count the
## PostGenericAttack hit clouds; the default just forwards to the effect manager.
func _spawn_hit_cloud(position: Vector3, impact_dir: Vector3, target: Node, ability_id: int):
	"""Thin wrapper for subclass override compatibility (super._spawn_hit_cloud)."""
	effect_manager.spawn_trap_effect(position, impact_dir, target, ability_id, true)


# Override in subclasses

func get_test_name() -> String:
	return "GPUCombatTest"


func get_team0_unit_configs() -> Array:
	return [{
		"name": "Fighter0",
		"pos_x": 0, "pos_z": 0,
		"hp": 100, "max_hp": 100,
		"pa": 10, "ma": 10, "wp": 5,
		"weapon_range": 1, "weapon_flags": 1
	}]


func get_team1_unit_configs() -> Array:
	return [{
		"name": "Enemy0",
		"pos_x": 2, "pos_z": 0,
		"hp": 100, "max_hp": 100,
		"pa": 10, "ma": 10, "wp": 5,
		"weapon_range": 1, "weapon_flags": 1
	}]


func get_gambits_for_unit(_unit_idx: int, _team: int) -> Array:
	return [make_attack_gambit()]


func on_state_changed(_unit_idx: int, _old_state: int, _new_state: int):
	pass


func on_hp_changed(_unit_idx: int, _old_hp: int, _new_hp: int, _delta: int):
	pass


func on_awaiting_impact(_unit_idx: int):
	"""Hook fired when a firer enters LOGICAL_ACTIVITY_AWAITING_IMPACT — the flight tail
	after the attack SEQ ends, before damage lands (ADR-0032). Symmetric with
	the other state-edge hooks; fan-out lives in _dispatch_state_changed."""
	pass


func on_victory(_winning_team: int):
	pass


func _dispatch_state_changed(unit_idx: int, old_state: int, new_state: int) -> void:
	"""Fan-out wrapper for state edges: calls on_state_changed and dispatches
	the dedicated on_awaiting_impact hook when LOGICAL_ACTIVITY_AWAITING_IMPACT is entered.
	Connected to combat_loop.state_changed in place of on_state_changed itself.
	The awaiting_impact hook is deferred so the CPU-side Unit.activity (set in
	CombatLoop._update_unit_animation, which runs synchronously after the signal
	emit) is the new value by the time the assertion reads it."""
	on_state_changed(unit_idx, old_state, new_state)
	if new_state == GPUConstants.LOGICAL_ACTIVITY_AWAITING_IMPACT and old_state != GPUConstants.LOGICAL_ACTIVITY_AWAITING_IMPACT:
		call_deferred("on_awaiting_impact", unit_idx)


# Gambit helpers

static func make_attack_gambit() -> Dictionary:
	return {
		"enabled": true,
		"cond_target_type": GPUConstants.TARGET_NEAREST_ENEMY,
		"conditions": [{"type": GPUConstants.COND_ALWAYS, "value": 0}],
		"action_type": GPUConstants.ACTION_ATTACK,
		"action_id": 0,
		"action_target_type": GPUConstants.TARGET_THEM
	}


static func make_spell_gambit(ability_id: int, target_type: int = GPUConstants.TARGET_NEAREST_ENEMY) -> Dictionary:
	return {
		"enabled": true,
		"cond_target_type": target_type,
		"conditions": [{"type": GPUConstants.COND_ALWAYS, "value": 0}],
		"action_type": GPUConstants.ACTION_SPELL,
		"action_id": ability_id,
		"action_target_type": GPUConstants.TARGET_THEM
	}


static func make_item_gambit(ability_id: int, target_type: int = GPUConstants.TARGET_SELF) -> Dictionary:
	return {
		"enabled": true,
		"cond_target_type": target_type,
		"conditions": [{"type": GPUConstants.COND_ALWAYS, "value": 0}],
		"action_type": GPUConstants.ACTION_ITEM,
		"action_id": ability_id,
		"action_target_type": target_type
	}


static func make_ability_gambit(ability_id: int, target_type: int = GPUConstants.TARGET_NEAREST_ENEMY) -> Dictionary:
	return {
		"enabled": true,
		"cond_target_type": target_type,
		"conditions": [{"type": GPUConstants.COND_ALWAYS, "value": 0}],
		"action_type": GPUConstants.ACTION_ABILITY,
		"action_id": ability_id,
		"action_target_type": GPUConstants.TARGET_THEM
	}


static func make_move_to_gambit(dest_x: int, dest_z: int) -> Dictionary:
	# Pack destination as x * 256 + z
	var packed_dest = dest_x * 256 + dest_z
	return {
		"enabled": true,
		"cond_target_type": GPUConstants.TARGET_SELF,
		"conditions": [{"type": GPUConstants.COND_ALWAYS, "value": 0}],
		"action_type": GPUConstants.ACTION_MOVE_TO,
		"action_id": packed_dest,
		"action_target_type": GPUConstants.TARGET_SELF
	}


static func make_wait_gambit() -> Dictionary:
	return {
		"enabled": true,
		"cond_target_type": GPUConstants.TARGET_SELF,
		"conditions": [{"type": GPUConstants.COND_ALWAYS, "value": 0}],
		"action_type": GPUConstants.ACTION_WAIT,
		"action_id": 0,
		"action_target_type": GPUConstants.TARGET_SELF
	}


## Terrain height at `cell` — the fact `_build_gpu_config` used to read off the held
## `Tile`. Holder 4 is a `Vector3i` now (ADR-0166 dec. 3 + ADR-0219 dec. 1), so height
## is a PORT question asked with the CELL rather than a field on whatever the unit
## happens to hold — and the level is part of what is asked.
func _cell_height(cell: Vector3i) -> int:
	if lattice == null or cell == TerrainCell.NONE:
		return 0
	# The inherited `lattice` (declared on `CombatHost`) re-annotated in the file that
	# uses it: the register's receiver inference is per FILE, so a call on the base
	# class's field alone reads as "undeclared in this file" — the one blind spot
	# ADR-0192's amendment names, and cross-file resolution is attempted by no guard
	# in this repo. One typed local makes the claim checkable where it is made.
	var lat: Lattice = lattice
	var terrain := lat.terrain_at(cell)
	return terrain.height if terrain != null else 0
