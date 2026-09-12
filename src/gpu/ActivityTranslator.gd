class_name ActivityTranslator
extends RefCounted

## Translates a Logical activity (GPU side, LOGICAL_ACTIVITY_*) into the
## corresponding Display activity authored event (CPU animation layer).
##
## The dispatch shell -- `translate()` and the `match` body inside it -- is
## GENERATED from tools/activity_taxonomy.yaml. The `_translate_<routing>`
## methods below are hand-written; each captures the chunk that used to
## live inline in CombatLoop._update_unit_animation.
##
## CombatLoop owns the early-return guards above the call to translate()
## (CELEBRATING override, dead-unit guard, spell-cast-active latch); those
## reference CombatLoop-internal state so they stay at the call site.
##
## `attack_handler` is a Callable injected from CombatLoop. Weapon-loading +
## regression logging touch CombatLoop-internal state, so the impl stays
## there and the translator just invokes the callable.
##
## Regenerate the shell:
##   (cd tools && uv run python gen_activity_taxonomy.py)


# === BEGIN GENERATED: logical-activity-translate (tools/gen_activity_taxonomy.py) ===
# Source of truth: tools/activity_taxonomy.yaml
# DO NOT edit by hand. Regenerate:
#   (cd tools && uv run python gen_activity_taxonomy.py)

static func translate(unit, logical: int, state: Dictionary, unit_idx: int,
		attack_handler: Callable = Callable()) -> void:
	match logical:
		GPUConstants.LOGICAL_ACTIVITY_IDLE:
			_translate_resolver_variant(unit, state, ExMateriaSchema.UnitActivity.Display.IDLE, true)
		GPUConstants.LOGICAL_ACTIVITY_WALKING:
			_translate_visualizer(unit, state)
		GPUConstants.LOGICAL_ACTIVITY_WALKING_TO_CAST:
			_translate_visualizer(unit, state)
		GPUConstants.LOGICAL_ACTIVITY_APPROACHING:
			_translate_visualizer(unit, state)
		GPUConstants.LOGICAL_ACTIVITY_RETREATING:
			_translate_visualizer(unit, state)
		GPUConstants.LOGICAL_ACTIVITY_ACTING:
			if state.get('casting_ability_id', -1) >= 368 and state.get('casting_ability_id', -1) <= 381:
				_translate_parameterized(unit, state, "use_item", "casting_ability_id")
			elif state.get('casting_ability_id', -1) <= 0:
				_translate_attack_handler(unit, state, unit_idx, attack_handler)
			elif state.get('casting_ability_id', -1) > 0:
				_translate_cast_deferred(unit, state)
		GPUConstants.LOGICAL_ACTIVITY_SPELL_CHARGING:
			_translate_parameterized(unit, state, "charge_ability", "casting_ability_id")
		GPUConstants.LOGICAL_ACTIVITY_PREEMPTIVE_COUNTER:
			_translate_transient(unit, state)
		GPUConstants.LOGICAL_ACTIVITY_DYING:
			_translate_direct(unit, ExMateriaSchema.UnitActivity.Display.DYING, false)
		GPUConstants.LOGICAL_ACTIVITY_CELEBRATING:
			_translate_direct(unit, ExMateriaSchema.UnitActivity.Display.CELEBRATING, false)
		GPUConstants.LOGICAL_ACTIVITY_AWAITING_IMPACT:
			_translate_direct(unit, ExMateriaSchema.UnitActivity.Display.AWAITING_IMPACT, true)
# === END GENERATED ===


# --- hand-written routing implementations ----------------------------------

static func _translate_direct(unit, display: int, clear_ability_id: bool) -> void:
	if clear_ability_id:
		unit.active_ability_id = -1
	unit.activity = display

static func _translate_visualizer(_unit, _state: Dictionary) -> void:
	# Move visualizer authors the body activity from per-step writes; the
	# translator is intentionally a no-op here.
	pass

static func _translate_transient(_unit, _state: Dictionary) -> void:
	# Logical-only state (ADR-0033): the GPU's next-tick state handler
	# transitions out of this state, so the translator has nothing to do.
	# Used today by PREEMPTIVE_COUNTER (Hamedo's one-tick queued counter-
	# strike gateway). The defender shows the IDLE pose for the gateway
	# tick, then the next-tick LOGICAL_ACTIVITY_ACTING transition swaps in
	# the ATTACKING display via the attack_handler routing.
	pass

static func _translate_attack_handler(unit, _state: Dictionary, unit_idx: int,
		attack_handler: Callable) -> void:
	# Weapon attack path. _start_attack_animation lives on CombatLoop since
	# it consults gpu_state_reader / units / _rlog; the translator just
	# invokes the injected callable.
	if attack_handler.is_valid():
		attack_handler.call(unit, unit_idx)

static func _translate_cast_deferred(_unit, _state: Dictionary) -> void:
	# Cast path: SPELL_CASTING is set later by CombatLoop's
	# _on_spell_cast_complete handler so the cast SEQ is not cut short.
	pass

static func _translate_parameterized(unit, state: Dictionary, method: String,
		param_field: String) -> void:
	# Parameterized activity (ADR-0024): the resolver only fires through the
	# semantic method, not a bare activity write. Matches the pre-refactor
	# SPELL_CHARGING entry.
	var param = state.get(param_field, -1)
	unit.active_ability_id = param
	unit.call(method, param)

static func _translate_resolver_variant(unit, _state: Dictionary, base_display: int,
		clear_ability_id: bool) -> void:
	# Translator sets the base activity; AnimationResolutionMap picks the
	# variant (e.g. IDLE_LOW_HEALTH) from world state. The translator does
	# not need to know which variant resolves.
	if clear_ability_id:
		unit.active_ability_id = -1
	unit.activity = base_display
