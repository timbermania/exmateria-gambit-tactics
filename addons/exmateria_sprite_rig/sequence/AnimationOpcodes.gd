extends RefCounted
## 🔴 NO `class_name`. This is `addons/exmateria_sprite_rig`'s, and the addon
## declares exactly one global name — the folder-named façade (ADR-0212 dec. 1).
## Reach it as `ExMateriaSpriteRig.AnimationOpcodes`, or alias it back to the
## bare spelling in your own class (ADR-0211 dec. 4):
##
##     const AnimationOpcodes = ExMateriaSpriteRig.AnimationOpcodes
##
## 🔴 `Op` AND `SideEffect` STAY IN ONE FILE (ADR-0217 dec. 6). They share four
## member names at DIFFERENT integer values — `Op.QUEUE_SPRITE_ANIM` is 2 and
## `SideEffect.QUEUE_SPRITE_ANIM` is 0 — so splitting them across a package
## boundary would manufacture a conflation hazard in the pass that exists to
## retire conflation hazards.

## Enum-based opcode identification for animation sequences.
##
## Replaces string comparisons like `op.get("op_code_name") == "LoadFrameWait"`
## with integer enum comparisons for type safety and performance.
## Vault: [[SEQ Movement Opcodes]]
## Vault: [[Unit Sprite Render Pipeline]]
## Vault: [[Unit Sprite SEQ Opcodes]]

enum Op {
	UNKNOWN = 0,
	LOAD_FRAME_WAIT,
	QUEUE_SPRITE_ANIM,
	SET_LAYER_PRIORITY,
	POST_GENERIC_ATTACK,
	QUEUE_THROW_ANIMATION,
	QUEUE_DISTORT_ANIM,
	WAIT_FOR_DISTORT,
	INCREMENT_LOOP,
	PAUSE_ANIMATION,
	# Fixed-increment movement opcodes
	MOVE_FORWARD_1,
	MOVE_FORWARD_2,
	MOVE_BACKWARD_1,
	MOVE_BACKWARD_2,
	MOVE_UP_1,
	MOVE_UP_2,
	MOVE_DOWN_1,
	MOVE_DOWN_2,
	# Parameterized movement opcodes
	MOVE_UNIT_FB,
	MOVE_UNIT_DU,
	MOVE_UNIT_RL,
	MOVE_UNIT_RLDU_FB,
	# Non-gameplay opcodes (not matched in code, but present in data)
	FLIP_HORIZONTAL,
	LOAD_MF_ITEM,
	MF_ITEM_POS_FBDU,
	PLAY_ATTACK_SOUND,
	PLAY_SOUND,
	SET_FRAME_OFFSET,
	UNLOAD_MF_ITEM,
	WAIT,
	WAIT_FOR_INPUT,
	WEAPON_SHEATHE_CHECK_1,
	WEAPON_SHEATHE_CHECK_2,
}

## Side effect types emitted by AnimationPlayback.side_effect signal.
enum SideEffect {
	QUEUE_SPRITE_ANIM = 0,
	SET_LAYER_PRIORITY,
	POST_GENERIC_ATTACK,
	QUEUE_THROW_ANIMATION,
}

# Lazy-initialized lookup dictionary
static var _name_to_op: Dictionary = {}

static func from_string(op_name: String) -> int:
	if _name_to_op.is_empty():
		_name_to_op = {
			"LoadFrameWait": Op.LOAD_FRAME_WAIT,
			"QueueSpriteAnim": Op.QUEUE_SPRITE_ANIM,
			"SetLayerPriority": Op.SET_LAYER_PRIORITY,
			"PostGenericAttack": Op.POST_GENERIC_ATTACK,
			"QueueThrowAnimation": Op.QUEUE_THROW_ANIMATION,
			"QueueDistortAnim": Op.QUEUE_DISTORT_ANIM,
			"WaitForDistort": Op.WAIT_FOR_DISTORT,
			"IncrementLoop": Op.INCREMENT_LOOP,
			"PauseAnimation": Op.PAUSE_ANIMATION,
			"MoveForward1": Op.MOVE_FORWARD_1,
			"MoveForward2": Op.MOVE_FORWARD_2,
			"MoveBackward1": Op.MOVE_BACKWARD_1,
			"MoveBackward2": Op.MOVE_BACKWARD_2,
			"MoveUp1": Op.MOVE_UP_1,
			"MoveUp2": Op.MOVE_UP_2,
			"MoveDown1": Op.MOVE_DOWN_1,
			"MoveDown2": Op.MOVE_DOWN_2,
			"MoveUnitFB": Op.MOVE_UNIT_FB,
			"MoveUnitDU": Op.MOVE_UNIT_DU,
			"MoveUnitRL": Op.MOVE_UNIT_RL,
			"MoveUnitRLDUFB": Op.MOVE_UNIT_RLDU_FB,
			"FlipHorizontal": Op.FLIP_HORIZONTAL,
			"LoadMFItem": Op.LOAD_MF_ITEM,
			"MFItemPosFBDU": Op.MF_ITEM_POS_FBDU,
			"PlayAttackSound": Op.PLAY_ATTACK_SOUND,
			"PlaySound": Op.PLAY_SOUND,
			"SetFrameOffset": Op.SET_FRAME_OFFSET,
			"UnloadMFItem": Op.UNLOAD_MF_ITEM,
			"Wait": Op.WAIT,
			"WaitForInput": Op.WAIT_FOR_INPUT,
			"WeaponSheatheCheck1": Op.WEAPON_SHEATHE_CHECK_1,
			"WeaponSheatheCheck2": Op.WEAPON_SHEATHE_CHECK_2,
		}
	return _name_to_op.get(op_name, Op.UNKNOWN)
