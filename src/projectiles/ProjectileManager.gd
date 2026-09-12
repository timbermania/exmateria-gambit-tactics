class_name ProjectileManager
extends RefCounted
## Manages projectile spawning and landing dispatch.
##
## Extracted from the combat loop (ADR-0018). Per ADR-0038 the manager is now
## a spawner + dispatcher: it owns the spawn record list and emits
## projectile_landed on flight completion, but per-frame advancement
## (position, spin, tumble) lives on Projectile3D._process. _active_projectiles
## is kept so the landing dispatch can find the firer/target metadata; the
## node itself is in the combat_visuals group and self-paces against
## ADR-0037's freeze predicate.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase
const ItemDatabase = ExMateriaAlmanac.ItemDatabase


signal projectile_landed(caster_idx: int, target_idx: int, proj_data: Dictionary)

const Projectile3DClass = preload("res://src/projectiles/Projectile3D.gd")

# PSX bow arc constants
const PSX_PER_GODOT := 28.0  # uniform: PSX ÷50 × TILE_SCALE = ÷28
const PSX_ARC_K := 4096.0
const PSX_ARC_R := 336.0
const PSX_HEIGHT_UNIT := 12.0  # 1h = 12 PSX world units

var _active_projectiles: Array = []
var _base  # CombatLoop (untyped: avoids the new-class-cache + preload-cycle issue)


func _init(base) -> void:
	_base = base


func spawn_from_gpu(unit_idx: int, state: Dictionary, all_states: Array) -> void:
	"""Spawn projectile when GPU signals projectile_triggered flag.

	The GPU sets projectile_triggered when anim_frame crosses projectile_frame.
	This works for ranged weapons (WEP1 timing), throw abilities (TYPE1 timing),
	and items (ability IDs 368-381).
	"""
	var item_type_id = state.get("weapon_type", 0)
	var casting_ability_id = state.get("casting_ability_id", -1)

	# Determine projectile type and arc
	var projectile_type = Projectile3D.ProjectileType.ARROW
	var arc_multiplier = 0.0  # Straight line by default; only bows arc
	var is_item_ability = false
	var is_weapon_sprite_throw = false
	var throw_item_type_id = 0
	var item_graphic = -1
	var item_palette = 0

	# Check if this is an ability-based projectile
	var is_throw_ability = false
	if casting_ability_id > 0:
		var ability := AbilityDatabase.get_ability_view(casting_ability_id)
		if not ability.is_empty():
			# effect_anim_id 76 (0x4C) = Throw Weapon animation = fires projectile
			if ability.effect_anim_id == 76:
				is_throw_ability = true
				var ability_type_id = ability.ability_type_id
				if ability_type_id == 3:  # Throwing (Ninja) - use WEP1 weapon sprite
					is_weapon_sprite_throw = true
					arc_multiplier = 0.0
					throw_item_type_id = ability.throw_item_id
				else:  # Normal (ThrowStone, PleaseEat, etc.)
					projectile_type = Projectile3D.ProjectileType.STONE
					arc_multiplier = 0.0
			# Check for item ability (IDs 368-381)
			elif casting_ability_id >= 368 and casting_ability_id <= 381:
				is_item_ability = true
				projectile_type = Projectile3D.ProjectileType.ITEM
				arc_multiplier = 0.0
				# Get item graphic from ItemDatabase
				var item_id = casting_ability_id - GPUConstants.ITEM_ABILITY_ID_OFFSET  # Potion = 368 - 128 = 240
				item_graphic = ItemDatabase.get_item_graphic(item_id)
				item_palette = ItemDatabase.get_weapon_palette(item_id)

	# Only spawn for ranged weapons, throw abilities, or items
	if not is_throw_ability and not is_item_ability and item_type_id not in GPUConstants.RANGED_WEAPON_TYPES:
		return

	var target_idx = state.get("target", -1)
	if target_idx < 0 or target_idx >= _base.units.size():
		return

	var attacker = _base.units[unit_idx]
	var target = _base.units[target_idx]

	if not is_instance_valid(attacker) or not is_instance_valid(target):
		return

	# Projectile positions
	var start_pos = attacker.global_position + Vector3(0, 0.5, 0)
	var end_pos = target.global_position + Vector3(0, 0.5, 0)

	# Calculate arc height based on distance
	var distance = start_pos.distance_to(end_pos)
	var arc_height = distance * arc_multiplier

	# For ranged weapons, determine type from weapon
	if not is_throw_ability and not is_item_ability:
		if item_type_id == 10:  # Gun
			projectile_type = Projectile3D.ProjectileType.BULLET
			# arc_height already 0.0
		elif item_type_id == 12:  # Bow — PSX low arc
			var xz_delta = Vector3(end_pos.x - start_pos.x, 0.0, end_pos.z - start_pos.z)
			var delta_y = float(end_pos.y - start_pos.y)  # positive = target higher
			arc_height = _compute_psx_bow_arc(xz_delta.length(), delta_y)
		# Crossbow (11) keeps arc_height = 0.0 (straight line, ARROW visual)

	# ADR-0038: flight time is the GPU's SEQ-authored damage_frame - anim_frame at
	# spawn, so the projectile lands at the same tick the GPU writes damage
	# (`_trigger_projectile_reaction` keys hit-vs-evade off that tick — see
	# CombatLoop). The retired BULLET /3 and throw/item `flight_speed_mult`
	# special cases are GONE — uniform SEQ-derived timing across all projectile
	# families replaces both, which is the consistent-speed fix the user's
	# "speed feels weird" symptom asked for.
	var tracked_type = Projectile3D.ProjectileType.WEAPON_SPRITE if is_weapon_sprite_throw else projectile_type
	var damage_frame: int = int(state.get("damage_frame", 30))
	var projectile_frame: int = int(state.get("projectile_frame", 15))
	var anim_frame: int = int(state.get("anim_frame", projectile_frame))
	var flight_ticks: int = maxi(damage_frame - anim_frame, 1)
	var flight_seconds: float = float(flight_ticks) / GPUConstants.TICKS_PER_SECOND

	# Create projectile visual
	var projectile = Projectile3DClass.new()
	_base.add_child(projectile)

	if is_weapon_sprite_throw:
		projectile.initialize_weapon_sprite(start_pos, end_pos, arc_height, flight_seconds, throw_item_type_id)
	elif is_item_ability and item_graphic >= 0:
		projectile.initialize_item(start_pos, end_pos, arc_height, flight_seconds, item_graphic, item_palette)
	else:
		projectile.projectile_type = projectile_type
		projectile.start_pos = start_pos
		projectile.end_pos = end_pos
		projectile.arc_height = arc_height
		projectile.flight_duration = flight_seconds
		projectile.global_position = start_pos
		projectile._create_visual()

	# Death-resilient end_pos tracking: while target Node is alive, _process
	# updates end_pos from target_node.global_position; once freed, end_pos
	# sticks at its last seen value so the projectile completes flight to the
	# target's death-tile (ADR-0038).
	projectile.target_node = target

	# Track projectile for landing dispatch. The spawn record carries the
	# metadata projectile_landed consumers need (hit/miss snapshot,
	# pre-damage HP, evade type); per-frame state lives on Projectile3D.
	var spawn_record := {
		"node": projectile,
		"caster_idx": unit_idx,
		"target_idx": target_idx,
		"start_pos": start_pos,
		"arc_height": arc_height,
		"projectile_type": tracked_type,
		"ability_id": casting_ability_id,
		"is_item_ability": is_item_ability,
		"hit_target": state.get("damage_target", -1),
		"target_hp_at_spawn": _base._hp_before_last_damage.get(target_idx, _base._combat_interp.last_hp(target_idx)),
		"evade_type_at_spawn": _base._last_evade_type.get(target_idx, 0),
	}
	_active_projectiles.append(spawn_record)
	# Projectile3D's flight_completed flips a flag on the spawn record; the
	# actual projectile_landed emit happens in update() (post-GPU-step) so
	# CombatLoop._trigger_projectile_reaction's `is_hit` heuristic compares
	# against a current `_last_damage_tick` (set earlier in the same combat
	# tick by `_read_tick_columns`).
	projectile.flight_completed.connect(func(): spawn_record["_landed"] = true)

	# Regression logging for projectile spawn
	var proj_type_name = Projectile3D.ProjectileType.keys()[tracked_type]
	var ability_for_log = casting_ability_id if (is_throw_ability or is_item_ability) else -1
	_base._rlog.log_projectile_spawn(unit_idx, target_idx, proj_type_name, flight_ticks, ability_for_log)

	if DebugConfig.iteration_debug_enabled:
		print("[%s] Spawned %s projectile: %s -> %s (dist=%.2f, flight=%d ticks, proj_frame=%d, dmg_frame=%d)" % [
			_base.get_test_name(),
			proj_type_name,
			attacker.name, target.name, distance, flight_ticks, projectile_frame, damage_frame
		])


func advance_one_tick() -> void:
	"""Advance every active projectile by one GPU tick. Called from inside
	CombatLoop's `while _tick_accumulator` loop so flight stays tick-locked
	with the GPU damage tick regardless of `Engine.time_scale` (tests use
	4.0x). Sets the `_landed` flag on records that finish this tick;
	dispatch is deferred to `update()` (post-loop) so all of this frame's
	GPU damage writes are reflected in `_last_damage_tick` first."""
	for record in _active_projectiles:
		var node = record.get("node")
		if is_instance_valid(node):
			node.advance_tick()


func update(current_tick: int, all_states: Array) -> void:
	"""Post-GPU-step pump: dispatch `projectile_landed` for any projectile
	that finished its flight this frame, and clean up nodes freed
	externally. Runs after CombatLoop's while loop so `_read_tick_columns`
	has populated `_last_damage_tick` for any damage that applied this
	frame — the `_trigger_projectile_reaction` hit heuristic compares
	against that value."""
	var to_remove: Array = []
	for i in range(_active_projectiles.size()):
		var record: Dictionary = _active_projectiles[i]
		var node = record.get("node")
		if not is_instance_valid(node):
			to_remove.append(i)
			continue
		if record.get("_landed", false):
			_dispatch_landed(record)
			to_remove.append(i)
	for i in range(to_remove.size() - 1, -1, -1):
		_active_projectiles.remove_at(to_remove[i])


func _dispatch_landed(spawn_record: Dictionary) -> void:
	"""Emit projectile_landed + free the visual. Runs from update() after the
	GPU step so reaction routing's `_last_damage_tick` comparison is current.

	ADR-0038: runs once on natural landing AND on death-induced landing
	(target Node freed mid-flight — end_pos was snapshotted, projectile
	completed flight to that point). No damage write; damage stays
	GPU-authored per ADR-0032 / ADR-0031.
	"""
	var caster_idx: int = spawn_record["caster_idx"]
	var target_idx: int = spawn_record["target_idx"]
	var proj_type = spawn_record["projectile_type"]
	var proj_type_name = Projectile3D.ProjectileType.keys()[proj_type]
	var projectile = spawn_record.get("node")

	_base._rlog.log_projectile_land(caster_idx, target_idx, proj_type_name)
	projectile_landed.emit(caster_idx, target_idx, spawn_record)

	if is_instance_valid(projectile):
		projectile.queue_free()


func has_active_targeting(target_idx: int) -> bool:
	for proj_data in _active_projectiles:
		if proj_data.get("target_idx", -1) == target_idx:
			return true
	return false


func _compute_psx_bow_arc(godot_xz_dist: float, godot_delta_y: float) -> float:
	"""PSX low-arc bow height (bulge above straight line).

	Computes H from the quadratic endpoint constraint, then derives
	arc_height = (H²+K²)·D²/(4·K³·R·ppg) — matching the B coefficient
	between PSX's parabola and Godot's 4t(1-t) arc system.
	"""
	var D := godot_xz_dist * PSX_PER_GODOT * 64.0  # Q6 fixed-point
	var delta_y := godot_delta_y * PSX_PER_GODOT / PSX_HEIGHT_UNIT  # h units

	if D < 1.0:
		return 0.0  # same-tile: no meaningful arc

	var K := PSX_ARC_K
	var R := PSX_ARC_R
	var disc := R * R - 4.0 * delta_y * R - 4.0 * D * D / (K * K)
	if disc <= 0.0:
		return 0.0  # beyond valid range

	# Low arc H (minus sign = flatter trajectory)
	var H := K * K * (R - sqrt(disc)) / (2.0 * D)

	# arc_height = (H²+K²)·D²/(4·K³·R·ppg) — bulge above straight line
	var K2 := K * K
	var K3 := K2 * K
	return (H * H + K2) * D * D / (4.0 * K3 * R * PSX_PER_GODOT)


