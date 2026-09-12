class_name GambitEncoder
extends RefCounted

## Encodes gambit configurations into GPU-compatible integer arrays.
##
## This class converts high-level Gambit objects into the flat integer format
## expected by the GPU compute shader. Each gambit is encoded as 16 integers.
##
## Usage:
##   var encoder = GambitEncoder.new()
##   var gambits = [gambit1, gambit2, gambit3]  # Array of Gambit objects
##   var encoded = encoder.encode_gambits(gambits)
##   gpu_simulator.set_unit_gambits(battle_id, unit_idx, encoded)

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const Gambit = ExMateriaAlmanac.Gambit
const GambitCondition = ExMateriaAlmanac.GambitCondition
const StatusRegistry = ExMateriaAlmanac.StatusRegistry
const TargetSelector = ExMateriaAlmanac.TargetSelector
const UnitRole = ExMateriaSchema.UnitRole


# Must match shader constants (canonical values in GPUConstants). The encoder
# authors up to MAX_USER_GAMBITS slots; the injected safety net (ADR-0048) fills
# the last buffer slot, so the full MAX_GAMBITS is only the buffer's concern.
const MAX_USER_GAMBITS = GPUConstants.MAX_USER_GAMBITS
const GAMBIT_SIZE = GPUConstants.GAMBIT_SIZE

# Sentinel returned by _target_selector_to_gpu for a TargetSelector the GPU AI
# cannot faithfully express; the caller skips the whole gambit (ADR-0023).
const TARGET_UNSUPPORTED := -1

# Declared UNSUPPORTED sets (ADR-0023): domain enum values with no faithful GPU
# mapping. Authoring one skips the gambit (push_error + disabled slot) rather
# than silently substituting a different behavior. This is the editor↔engine gap
# list / backlog — #32 (range→distance, bridgeable), #33 (editor offers these),
# #34 — and draining an entry is gated by the completeness test (#35). The
# mapping functions below return the unsupported sentinel for exactly these
# (plus any unmapped value, as a safety net for a newly-added enum).
#
# TARGET_IN_RANGE DRAINED, and only it (ADR-0268 dec. 11 / #32). The kernel gained
# `COND_IN_RANGE`, which asks the gambit's OWN action whether it reaches the candidate —
# `ability_in_reach` for an ability, `can_attack_target` for the weapon verbs. The other three
# stay declared and stay unreachable from the gambit surface: ENEMY_IN_RANGE / ALLY_IN_RANGE
# fold a POOL into the condition, which this screen expresses with `condition_target` instead,
# and IN_RANGE_OF names an ability by string with no id to encode.
const UNSUPPORTED_CONDITION_TYPES: Array = [
	GambitCondition.Type.ENEMY_IN_RANGE,
	GambitCondition.Type.ALLY_IN_RANGE,
	GambitCondition.Type.IN_RANGE_OF,
	GambitCondition.Type.ENEMY_COUNT,
	GambitCondition.Type.ALLY_COUNT,
	GambitCondition.Type.HP_MISSING,
]
const UNSUPPORTED_POOL_TYPES: Array = [
	TargetSelector.PoolType.SPECIFIC_UNITS,
]
const UNSUPPORTED_RESOLUTIONS: Array = [
	TargetSelector.ResolutionStrategy.HIGHEST_STAT,
	TargetSelector.ResolutionStrategy.LOWEST_STAT,
	TargetSelector.ResolutionStrategy.FIRST_IN_ROSTER,
]
# GPU targets are ally/enemy-specific, so an "any team" filter has no equivalent.
# (A non-ANY role_filter is likewise unsupported but can't be a value set — it's
# handled by a guard in _target_selector_to_gpu.)
const UNSUPPORTED_TEAM_FILTERS: Array = [
	TargetSelector.TeamFilter.ANY,
]
# Control verbs with no GPU gambit-action mapping. Empty as of ADR-0062 and still
# empty after ADR-0301 put RETREAT back: ATTACK, WAIT, ABILITY, MOVE
# (unit-anchored, → ACTION_MOVE_TO_UNIT) and RETREAT (→ ACTION_RETREAT_STEP) all
# map. Kept as a declared set so a newly-added ActionKind that the match below
# doesn't handle is a visible, test-guarded gap rather than a silent fallback.
const UNSUPPORTED_ACTION_KINDS: Array = []

# (GambitField offsets used to be redefined here but were unused — the encoder
# returns string-keyed Dictionaries and GPUBatchSimulator.set_unit_gambits packs
# them via GPUCombatPacker._pack_gambits, keyed by the generated
# GPUCombatPacker.GambitField.)

# TargetType / ConditionType / ActionType used to be redefined here; they are now
# generated into GPUConstants (TARGET_* / COND_* / ACTION_*) from the shader.
# This file references GPUConstants.TARGET_SELF etc. directly.


## Encode a whole battle's gambit lists for the GPU — global unit index → encoded array,
## which is the shape [code]CombatLoop.arm_combat_gambits[/code] wants.
##
## Every unit routes through the encoder even when it has NO gambits, so it still gets the
## injected attack-nearest safety net (ADR-0048); skipping it would leave that unit standing
## idle all battle, the exact stranded-unit outcome the safety net exists to prevent.
##
## `log_label` names the host in the per-unit report and the two "no gambits" warnings. Pass
## "" to stay silent — the story path arms a whole walk's worth of battles and does not want
## a line per unit. This is the one copy: `GPUArena`, `GambitBattle` and `NavigatorMain` all
## call it, and the second and third used to be hand-written mirrors of the first (ADR-0242).
static func encode_for_units(units: Array, log_label: String = "") -> Array:
	var gambits: Array = []
	for i in range(units.size()):
		var unit = units[i]
		var non_empty := authored_gambits(unit)
		if non_empty.is_empty():
			if log_label != "":
				push_warning("[%s] Unit %d (%s) has no usable gambits!"
					% [log_label, i, str(unit.name) if unit != null else "<null>"])
			gambits.append(encode_gambits([]))
			continue
		var encoded := encode_gambits(non_empty)
		gambits.append(encoded)
		if log_label != "":
			print("[%s] Unit %d (%s): %d gambits" % [log_label, i, unit.name, encoded.size()])
	return gambits


## One unit's encoded gambit buffer, optionally led by an entry that is in no slot of its list.
##
## `lead` is the IMPERATIVE (#1006, design §5): a one-shot, top-priority order that sits ABOVE the
## unit's standing rules for one action. It goes first because the shader walks slots ascending and
## takes the first match (`evaluate_gambits_up_to`), so "top priority" is a position and not a
## flag — nothing in the kernel has to learn the word.
##
## It costs no slot and no buffer growth, and the arithmetic is why this is a parameter rather than
## a redesign: `GambitList.VISIBLE_SLOTS` is 4, `MAX_USER_GAMBITS` is 5, and ADR-0048's safety net
## lands after both. A unit with all four slots authored and an imperative standing encodes to
## exactly the five authored words the buffer already has room for.
##
## The one caller that must NOT pass a lead is the battle-arming path: an imperative is issued on
## a turn, and a battle that armed one at boot would be handing out an order nobody gave.
static func encode_for_unit(unit, lead = null) -> Array:
	var authored: Array = []
	if lead != null and not lead.is_empty():
		authored.append(lead)
	authored.append_array(authored_gambits(unit))
	return encode_gambits(authored)


## The gambits a unit has actually authored — its list minus the empty ("Wait on Self") slots
## `GambitList.ensure_fixed_size` pads with. Public because "has this unit authored anything" is
## the question the no-gambits warning above and the imperative's lead both turn on, and two
## copies of that filter would eventually disagree about what an empty slot is.
static func authored_gambits(unit) -> Array:
	var out: Array = []
	if unit == null or unit.gambit_list == null:
		return out
	for gambit in unit.gambit_list.gambits:
		if not gambit.is_empty():
			out.append(gambit)
	return out


static func encode_gambits(gambits: Array) -> Array:
	"""Encode an array of gambits into GPU format.

	Args:
		gambits: Array of Gambit objects

	Returns:
		Array of Dictionary configs suitable for GPUBatchSimulator.set_unit_gambits()
	"""
	var result: Array = []

	for i in range(mini(gambits.size(), MAX_USER_GAMBITS)):
		var gambit = gambits[i]
		if gambit == null:
			result.append(null)
			continue

		result.append(_encode_from_gambit_object(gambit))

	# Pad the authored region so the safety net always lands at slot
	# MAX_USER_GAMBITS regardless of how many gambits the unit authored.
	while result.size() < MAX_USER_GAMBITS:
		result.append(null)

	# ADR-0048: auto-append one fixed safety-net gambit per unit. It exists only
	# in the encoded GPU buffer — the domain (Gambit / GambitList / UI editor)
	# stays unaware.
	result.append(_safety_net_config())

	return result


# The safety net is invariant (same shape for every unit), so encode it once and
# reuse. Built through the real encoder path the first time, so it still tracks
# the TargetSelector/condition mapping rather than duplicating it.
static var _safety_net_config_cache: Variant = null


static func _safety_net_config() -> Dictionary:
	"""The encoded ATTACK + NEAREST_ENEMY + ALWAYS fallback config (ADR-0048).
	Returns a fresh copy so a caller mutating its encoded slots can't corrupt the
	shared template."""
	if _safety_net_config_cache == null:
		_safety_net_config_cache = _encode_from_gambit_object(safety_net_gambit())
	return _safety_net_config_cache.duplicate(true)


## The fixed ATTACK + NEAREST_ENEMY + ALWAYS fallback (ADR-0048 dec. 1). Same shape for every
## unit, regardless of job, brave/faith, or authored gambit list — it guarantees the gambit pass
## always has a terminal candidate while an enemy is in reach (it still falls through to IDLE
## once no enemy remains).
##
## PUBLIC since ADR-0270, which made the net a visible row on the gambit surface. The screen
## renders THIS object rather than three literal strings, so the row and the buffer cannot come
## to disagree about what the net does — which is the exact failure a readout that restates a
## value in its own words eventually reaches.
static func safety_net_gambit() -> Gambit:
	return Gambit.create(
		TargetSelector.enemies(),        # the foe pool (default NEAREST_FIRST resolution)
		[GambitCondition.always()],
		Gambit.ActionKind.ATTACK,
		-1,                              # ability_id unused for ATTACK
		TargetSelector.triggering(),     # act on the matched (nearest) enemy
	)


static func _encode_from_gambit_object(gambit) -> Variant:
	"""Encode a single gambit from a Gambit object.

	This handles the actual Gambit class from the AI system, which has:
	- condition_target: TargetSelector (who to check conditions against)
	- conditions: Array[GambitCondition] (what must be true)
	- action_kind: Gambit.ActionKind (+ ability_id when ABILITY)
	- action_target: TargetSelector (who to act on)

	Returns the encoded config Dictionary, or null when the gambit cannot be
	faithfully mapped (e.g. an unsupported action). null slots are treated as
	disabled by _pack_gambits, so the unit falls through to its remaining
	gambits — see ADR-0023 (faithful-or-explicit, no silent fallback).
	"""
	var config: Dictionary = {
		"enabled": gambit.enabled if "enabled" in gambit else true,
		"cond_target_type": GPUConstants.TARGET_NEAREST_ENEMY,
		"conditions": [],
		"action_type": GPUConstants.ACTION_ATTACK,
		"action_id": 0,
		"action_target_type": GPUConstants.TARGET_THEM,
	}

	# Map condition_target (TargetSelector) to GPU target type. Faithful-or-
	# explicit (ADR-0023): an unmappable selector skips the whole gambit.
	if "condition_target" in gambit and gambit.condition_target != null:
		var cond_target := _target_selector_to_gpu(gambit.condition_target)
		if cond_target == TARGET_UNSUPPORTED:
			push_error("[GambitEncoder] Unsupported condition_target %s — gambit skipped." % _describe_selector(gambit.condition_target))
			return null
		config["cond_target_type"] = cond_target

	# Encode all conditions from the conditions array
	if "conditions" in gambit:
		for cond in gambit.conditions:
			var encoded_cond = _encode_gambit_condition(cond)
			if encoded_cond == null:
				push_error("[GambitEncoder] Unsupported gambit condition %s — gambit skipped." % _cond_type_name(cond))
				return null
			config["conditions"].append(encoded_cond)

	# Map action_kind + ability_id to GPU action_type / action_id. The Gambit
	# carries a stable ability_id (ADR-0023) — no name lookup on the hot path.
	match gambit.action_kind:
		Gambit.ActionKind.ATTACK:
			config["action_type"] = GPUConstants.ACTION_ATTACK
			config["action_id"] = 0
		Gambit.ActionKind.WAIT:
			config["action_type"] = GPUConstants.ACTION_WAIT
			config["action_id"] = 0
		Gambit.ActionKind.ABILITY:
			if gambit.ability_id < 0:
				push_error("[GambitEncoder] ABILITY action with no ability_id — gambit skipped.")
				return null
			config["action_type"] = GPUConstants.ACTION_SPELL
			config["action_id"] = gambit.ability_id
		Gambit.ActionKind.MOVE:
			# Unit-anchored reposition (ADR-0062). The destination is the unit the
			# action_target resolves to — encoded below by the shared
			# _target_selector_to_gpu(action_target) block (so MOVE inherits the
			# same supported/UNSUPPORTED target set as every other action). action_id
			# is unused. Absolute-tile moves are a separate program-built command
			# path (ACTION_MOVE_TO) that does not pass through this encoder.
			config["action_type"] = GPUConstants.ACTION_MOVE_TO_UNIT
			config["action_id"] = 0
		Gambit.ActionKind.RETREAT:
			# ADR-0301. Same shape as MOVE with the sign flipped: the action_target
			# is the unit to move AWAY from, encoded by the same shared
			# _target_selector_to_gpu(action_target) block below, so RETREAT inherits
			# the same supported/UNSUPPORTED target set for free.
			#
			# action_id is 0 HERE and not on the GPU. The kernel overwrites it at
			# commit time with the adjacent cell `retreat_step_cell` picked — the
			# destination cannot be known at encode time because it depends on where
			# both units are standing when the slot fires.
			config["action_type"] = GPUConstants.ACTION_RETREAT_STEP
			config["action_id"] = 0
		_:
			# A newly-added ActionKind the match doesn't handle — UNSUPPORTED
			# (skip + warn) rather than silently degrading to Attack.
			push_error("[GambitEncoder] Unsupported gambit action %s — gambit skipped." % Gambit.ActionKind.keys()[gambit.action_kind])
			return null

	# Map action_target (TargetSelector) to GPU target type
	if "action_target" in gambit and gambit.action_target != null:
		var act_target := _target_selector_to_gpu(gambit.action_target)
		if act_target == TARGET_UNSUPPORTED:
			push_error("[GambitEncoder] Unsupported action_target %s — gambit skipped." % _describe_selector(gambit.action_target))
			return null
		config["action_target_type"] = act_target

	return config


static func _target_selector_to_gpu(selector) -> int:
	"""Convert a TargetSelector to a GPU TargetType enum, or TARGET_UNSUPPORTED
	when the selector has no faithful GPU mapping (ADR-0023 — the caller skips
	the gambit; never a silent substitution)."""
	if not selector:
		return TARGET_UNSUPPORTED

	if selector.pool_type in UNSUPPORTED_POOL_TYPES:
		return TARGET_UNSUPPORTED

	var includes_ko := _selector_includes_ko(selector)

	match selector.pool_type:
		TargetSelector.PoolType.SELF:
			# A KO'd unit never reaches gambit evaluation, so "self, including KO" names a
			# pool that cannot exist. UNSUPPORTED rather than dropping the flag: silently
			# ignoring an author's filter is the ADR-0023 sin whichever way it rounds.
			return TARGET_UNSUPPORTED if includes_ko else GPUConstants.TARGET_SELF
		TargetSelector.PoolType.TRIGGERING:
			# TARGET_THEM is set by the caller, not searched, so there is no pool here to
			# widen — the flag would be inert. Same reasoning as SELF.
			return TARGET_UNSUPPORTED if includes_ko else GPUConstants.TARGET_THEM
		TargetSelector.PoolType.TEAM_FILTER:
			if selector.resolution in UNSUPPORTED_RESOLUTIONS:
				return TARGET_UNSUPPORTED
			# team_filter ANY and any non-ANY role filter have no GPU equivalent
			# (GPU targets are ally/enemy-specific and role-agnostic) — skip rather
			# than silently collapsing ANY→ally or dropping the role (ADR-0023).
			if selector.team_filter in UNSUPPORTED_TEAM_FILTERS:
				return TARGET_UNSUPPORTED
			if selector.role_filter != UnitRole.Role.ANY:
				return TARGET_UNSUPPORTED
			var is_enemy = selector.team_filter == TargetSelector.TeamFilter.ENEMY
			if includes_ko:
				# ONE KO-inclusive pool has a GPU spelling (#1102): nearest FRIENDLY.
				# Everything else — a KO-inclusive enemy pool, or MOST_CRITICAL over the
				# fallen (whose HP% is 0, so the corpse would win every time and starve the
				# living) — is UNSUPPORTED until the kernel grows a type for it, rather than
				# encoding as its KO-blind cousin.
				# NEAREST_ONLY is refused here too and for the ordinary reason: there is no
				# `TARGET_NEAREST_ALLY_OR_KO_ONLY` in the kernel, and encoding it as either of
				# its two cousins would drop half of what the author asked for (ADR-0023).
				if is_enemy or selector.resolution != TargetSelector.ResolutionStrategy.NEAREST_FIRST:
					return TARGET_UNSUPPORTED
				return GPUConstants.TARGET_NEAREST_ALLY_OR_KO
			match selector.resolution:
				TargetSelector.ResolutionStrategy.NEAREST_FIRST:
					return GPUConstants.TARGET_NEAREST_ENEMY if is_enemy else GPUConstants.TARGET_NEAREST_ALLY
				TargetSelector.ResolutionStrategy.NEAREST_ONLY:
					# The STRICT pair (ADR-0285). Same search as NEAREST_FIRST one line up —
					# what these two GPU types buy is their ABSENCE from Pass 2's retry guard,
					# which is why the kernel needed a type at all and not a flag on this one.
					return GPUConstants.TARGET_NEAREST_ENEMY_ONLY if is_enemy else GPUConstants.TARGET_NEAREST_ALLY_ONLY
				TargetSelector.ResolutionStrategy.MOST_CRITICAL:
					return GPUConstants.TARGET_LOWEST_HP_ENEMY if is_enemy else GPUConstants.TARGET_LOWEST_HP_ALLY
				_:
					return TARGET_UNSUPPORTED

	return TARGET_UNSUPPORTED


static func _selector_includes_ko(selector) -> bool:
	"""Whether this selector admits KO'd units. Duck-typed like the rest of the encoder's
	reads, so a selector predating the field (or a test double) answers `false`."""
	return ("include_ko" in selector) and bool(selector.include_ko)


static func _encode_gambit_condition(cond) -> Variant:
	"""Encode a GambitCondition object to GPU format, or null when the condition
	has no faithful GPU mapping (ADR-0023 — the caller skips the gambit; never a
	silent COND_ALWAYS substitution)."""
	if cond.type in UNSUPPORTED_CONDITION_TYPES:
		return null
	match cond.type:
		GambitCondition.Type.ALWAYS:
			return {"type": GPUConstants.COND_ALWAYS, "value": 0}
		GambitCondition.Type.SELF_HP, GambitCondition.Type.ALLY_HP, \
		GambitCondition.Type.ENEMY_HP, GambitCondition.Type.TARGET_HP:
			if cond.comparator == GambitCondition.Comparator.LESS_THAN:
				return {"type": GPUConstants.COND_HP_BELOW, "value": int(cond.threshold)}
			else:
				return {"type": GPUConstants.COND_HP_ABOVE, "value": int(cond.threshold)}
		GambitCondition.Type.SELF_MP, GambitCondition.Type.TARGET_MP:
			if cond.comparator == GambitCondition.Comparator.LESS_THAN:
				return {"type": GPUConstants.COND_MP_BELOW, "value": int(cond.threshold)}
			else:
				return {"type": GPUConstants.COND_MP_ABOVE, "value": int(cond.threshold)}
		GambitCondition.Type.TARGET_IN_RANGE:
			# NO VALUE, and `range_type` is deliberately not read. The kernel resolves the
			# reach from the gambit's own action (ADR-0268 dec. 11): the equipped weapon
			# for Attack / Move / Wait, the ability's own range and vertical tolerance
			# otherwise. A range baked in here would be a second answer to a question the
			# action already answers — and a stale one, since throw range is `speed / 2 + 1`
			# and moves with a Speed Break mid-battle.
			return {"type": GPUConstants.COND_IN_RANGE, "value": 0}
		GambitCondition.Type.IS_KO:
			# `COND_IS_DEAD`, NEVER `COND_HAS_STATUS` on bit 0 (#1102). The kernel answers
			# this from FLAG_DEAD in the unit's flag word (`is_unit_dead`); STATUS_DEAD is a
			# different word that nothing sets, so the status spelling encodes cleanly and
			# never fires. The GPU constant keeps its DEAD spelling because it is generated
			# from the shader; the domain word on this side is KO.
			return {"type": GPUConstants.COND_IS_DEAD, "value": 0}
		GambitCondition.Type.IS_ALIVE:
			return {"type": GPUConstants.COND_IS_ALIVE, "value": 0}
		GambitCondition.Type.TARGET_DISTANCE:
			# MANHATTAN tiles, planar — a different question from the path cost that ranks a
			# NEAREST pool and from TARGET_IN_RANGE's action reach. EQUALS is skipped rather
			# than folded into GREATER_THAN: the kernel has no equality arm, and quietly
			# widening the author's `== 3` to `> 3` is the silent substitution ADR-0023 bans.
			match cond.comparator:
				GambitCondition.Comparator.LESS_THAN:
					return {"type": GPUConstants.COND_DISTANCE_LESS, "value": int(cond.threshold)}
				GambitCondition.Comparator.GREATER_THAN:
					return {"type": GPUConstants.COND_DISTANCE_GREATER, "value": int(cond.threshold)}
				_:
					return null
		GambitCondition.Type.HAS_STATUS, GambitCondition.Type.MISSING_STATUS:
			# Translate the StringName status_id to its bit index via the
			# StatusRegistry (#67). Unknown name → encoder-skip per ADR-0023;
			# StatusRegistry.bit already push_errors, so no extra log here.
			var status_bit := StatusRegistry.bit(cond.status_id)
			if status_bit < 0:
				return null
			var gpu_type: int = GPUConstants.COND_HAS_STATUS if cond.type == GambitCondition.Type.HAS_STATUS else GPUConstants.COND_NOT_STATUS
			return {"type": gpu_type, "value": status_bit}

	# Unmapped (incl. UNSUPPORTED_CONDITION_TYPES, and any newly-added enum as a
	# safety net) → caller skips the gambit rather than firing it always.
	return null


static func _cond_type_name(cond) -> String:
	"""Human-readable GambitCondition.Type name for diagnostics."""
	var names := GambitCondition.Type.keys()
	return names[cond.type] if cond.type >= 0 and cond.type < names.size() else str(cond.type)


static func _describe_selector(selector) -> String:
	"""Human-readable TargetSelector summary for diagnostics."""
	if not selector:
		return "null"
	var pool_names := TargetSelector.PoolType.keys()
	var pool: String = pool_names[selector.pool_type] if selector.pool_type < pool_names.size() else str(selector.pool_type)
	if selector.pool_type == TargetSelector.PoolType.TEAM_FILTER:
		var res_names := TargetSelector.ResolutionStrategy.keys()
		var res: String = res_names[selector.resolution] if selector.resolution < res_names.size() else str(selector.resolution)
		var team_names := TargetSelector.TeamFilter.keys()
		var team: String = team_names[selector.team_filter] if selector.team_filter < team_names.size() else str(selector.team_filter)
		var ko: String = "/incl_ko" if _selector_includes_ko(selector) else ""
		return "%s/%s/%s/role=%s%s" % [pool, team, res, UnitRole.get_role_name(selector.role_filter), ko]
	return "%s%s" % [pool, "/incl_ko" if _selector_includes_ko(selector) else ""]
