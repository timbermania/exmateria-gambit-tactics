extends Node
## Pure GambitEncoder safety-net test (ADR-0048). No GPU / RenderingDevice.
##
## The encoder auto-appends one fixed safety-net gambit per unit at slot
## MAX_USER_GAMBITS: ATTACK + NEAREST_ENEMY + ALWAYS, action target the
## triggering unit (THEM). It is a pure buffer-injection concern — the domain
## (Gambit / GambitList / UI editor) stays unaware and authors at most
## MAX_USER_GAMBITS slots.
##
## Verifies:
##   1. A unit with no authored gambits still gets the safety net at slot 5.
##   2. The authored region caps at MAX_USER_GAMBITS — a 6th authored gambit
##      does not displace or overwrite the safety net.
##   3. The safety net always lands at slot MAX_USER_GAMBITS regardless of how
##      many (fewer) authored gambits the unit has (padding).
##   4. The packed GPU buffer carries the safety net in slot 5.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const Gambit = ExMateriaAlmanac.Gambit
const GambitCondition = ExMateriaAlmanac.GambitCondition
const TargetSelector = ExMateriaAlmanac.TargetSelector


# Derived from the same constants as the encoder, so a future MAX_GAMBITS bump
# moves these assertions with it instead of failing on a stale literal (the whole
# point of MAX_USER_GAMBITS = MAX_GAMBITS - 1, ADR-0048).
const TOTAL_SLOTS := GPUConstants.MAX_GAMBITS        # buffer slots (authored + safety net)
const AUTHORED_SLOTS := GPUConstants.MAX_USER_GAMBITS # authored cap
const SAFETY_SLOT := GPUConstants.MAX_USER_GAMBITS    # safety net lands here (last slot)

var _failed := false


func _ready() -> void:
	_test_safety_net_appended_when_no_authored_gambits()
	_test_authored_region_caps_at_max_user_gambits()
	_test_safety_net_lands_at_slot_5_with_short_authored_list()
	_test_packed_buffer_carries_safety_net_in_slot_5()
	if _failed:
		print("[FAIL] GambitSafetyNet test")
	else:
		print("[PASS] GambitSafetyNet: encoder injects ATTACK/NEAREST_ENEMY/ALWAYS at slot MAX_USER_GAMBITS")
	get_tree().quit()


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		print("[FAIL] %s" % msg)


func _expect_safety_net(config, where: String) -> void:
	# The fixed safety-net shape (ADR-0048), asserted at the config-dict level.
	_expect(config != null, "%s: safety-net slot is null" % where)
	if config == null:
		return
	_expect(config.get("action_type") == GPUConstants.ACTION_ATTACK,
		"%s: action_type should be ATTACK, got %s" % [where, str(config.get("action_type"))])
	_expect(config.get("cond_target_type") == GPUConstants.TARGET_NEAREST_ENEMY,
		"%s: cond_target should be NEAREST_ENEMY, got %s" % [where, str(config.get("cond_target_type"))])
	_expect(config.get("action_target_type") == GPUConstants.TARGET_THEM,
		"%s: action_target should be THEM (triggering), got %s" % [where, str(config.get("action_target_type"))])
	var conds = config.get("conditions", [])
	_expect(conds.size() == 1 and conds[0].get("type") == GPUConstants.COND_ALWAYS,
		"%s: conditions should be [ALWAYS], got %s" % [where, str(conds)])


func _test_safety_net_appended_when_no_authored_gambits() -> void:
	var encoded = GambitEncoder.encode_gambits([])
	# Buffer holds AUTHORED_SLOTS authored slots + 1 injected safety net.
	_expect(encoded.size() == TOTAL_SLOTS, "no-authored: expected %d slots (authored + safety net), got %d" % [TOTAL_SLOTS, encoded.size()])
	if encoded.size() != TOTAL_SLOTS:
		return
	# Authored region is empty (all null); safety net sits at the last slot.
	for i in range(AUTHORED_SLOTS):
		_expect(encoded[i] == null, "no-authored: slot %d should be null, got %s" % [i, str(encoded[i])])
	_expect_safety_net(encoded[SAFETY_SLOT], "no-authored safety slot")


func _authored_wait_gambit() -> Gambit:
	# A distinguishable authored gambit (WAIT, not ATTACK) so we can tell the
	# authored region apart from the injected safety net.
	return Gambit.create(
		TargetSelector.self_(),
		[GambitCondition.always()],
		Gambit.ActionKind.WAIT,
		-1,
		TargetSelector.self_(),
	)


func _test_authored_region_caps_at_max_user_gambits() -> void:
	# One more authored gambit than the authored cap. The extra must be dropped
	# (not overwrite the safety net); the safety net stays at the last slot.
	var authored: Array = []
	for i in range(AUTHORED_SLOTS + 1):
		authored.append(_authored_wait_gambit())
	var encoded = GambitEncoder.encode_gambits(authored)
	_expect(encoded.size() == TOTAL_SLOTS, "cap: expected %d slots, got %d" % [TOTAL_SLOTS, encoded.size()])
	if encoded.size() != TOTAL_SLOTS:
		return
	for i in range(AUTHORED_SLOTS):
		_expect(encoded[i] != null and encoded[i].get("action_type") == GPUConstants.ACTION_WAIT,
			"cap: authored slot %d should be WAIT, got %s" % [i, str(encoded[i])])
	_expect_safety_net(encoded[SAFETY_SLOT], "cap safety slot")


func _test_safety_net_lands_at_slot_5_with_short_authored_list() -> void:
	# Two authored gambits — the padding must place the safety net at the last
	# slot, not immediately after the authored ones.
	var encoded = GambitEncoder.encode_gambits([_authored_wait_gambit(), _authored_wait_gambit()])
	_expect(encoded.size() == TOTAL_SLOTS, "short: expected %d slots, got %d" % [TOTAL_SLOTS, encoded.size()])
	if encoded.size() != TOTAL_SLOTS:
		return
	_expect(encoded[0] != null and encoded[1] != null, "short: authored slots 0/1 should be set")
	for i in range(2, AUTHORED_SLOTS):
		_expect(encoded[i] == null, "short: pad slot %d should be null, got %s" % [i, str(encoded[i])])
	_expect_safety_net(encoded[SAFETY_SLOT], "short safety slot")


func _test_packed_buffer_carries_safety_net_in_slot_5() -> void:
	# End-to-end: the injected slot survives packing into the real GPU buffer at
	# the safety-slot offset (proves the buffer grew and the packer iterates it).
	var packed = GPUCombatPacker._pack_gambits(GambitEncoder.encode_gambits([]))
	_expect(packed.size() == GPUCombatPacker.GAMBITS_PER_UNIT,
		"packed: expected %d ints, got %d" % [GPUCombatPacker.GAMBITS_PER_UNIT, packed.size()])
	if packed.size() != GPUCombatPacker.GAMBITS_PER_UNIT:
		return
	var base = SAFETY_SLOT * GPUConstants.GAMBIT_SIZE
	_expect(packed[base + GPUCombatPacker.GambitField.ACTION_TYPE] == GPUConstants.ACTION_ATTACK,
		"packed: safety-slot action should be ATTACK")
	_expect(packed[base + GPUCombatPacker.GambitField.COND_COUNT] == 1,
		"packed: slot-5 should have 1 condition")
	_expect(packed[base + GPUCombatPacker.GambitField.COND_TYPE_0] == GPUConstants.COND_ALWAYS,
		"packed: slot-5 condition should be ALWAYS")
