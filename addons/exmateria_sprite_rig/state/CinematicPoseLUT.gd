extends RefCounted

## Per-direction pose LUT baked from BATTLE.BIN `0x800680dc..0x8006812b`
## (40 halfwords starting at file offset 0x10dc). Read at battle-load by
## PSX `FUN_80085c0c` into a stack-local buffer; here they live as
## `const Array[int]` because they're rodata, not runtime-populated.
##
## Six sub-tables share the 40 halfwords; today Path D only consumes four
## (A+B for the idle pose-octant dispatch, E+F for the SEQ-range cardinal
## dispatch). Sub-tables C+D drive the `anim_state >= 6` sub-part-index
## path the cinematic doesn't fire today (see ADR-0053 "Out of scope" +
## issue #126).
##
## Byte-equality with BATTLE.BIN is asserted in tests/CinematicPoseLUTTest.gd.
## Vault: [[Unit Anim Opcode]]
## Vault: [[Unit Sprite Render Pipeline]]

# ADR-0212 dec. 1 — the class is INTERNAL to this addon: no global `class_name`,
# so an in-addon consumer preloads the file it wants.
const AnimationStateController = preload("res://addons/exmateria_sprite_rig/state/AnimationStateController.gd")

# Sub-table A — pose-octant "tent" frame-base (`local[+0x38+poct*2]`).
# Indexed by 4-bit pose_octant (0..15); selects which of the 5 authored
# SHP frames (1..5) to paint. Symmetric around octant 7.5, peak at 5
# (back), trough at 1 (front).
const SUB_A_FRAME_BASE: Array[int] = [
	1, 2, 2, 3, 3, 4, 4, 5, 5, 4, 4, 3, 3, 2, 2, 1,
]

# Sub-table B — pose-octant mirror flag (`local[+0x18+poct*2]`). Indexed
# by 4-bit pose_octant; mode bits OR'd into the body variant's mode mask.
# Bit 1 (value 2) is the horizontal mirror flag — set for octants 9..14
# (left-facing half).
const SUB_B_MIRROR: Array[int] = [
	0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 2, 2, 2, 0,
]

# Sub-table E — cardinal-indexed SEQ frame-offset (`local[+0x20+card*2]`).
# Indexed by 2-bit cardinal_idx (= pose_octant >> 2; 0=S, 1=E, 2=W, 3=N).
# Adds 0 or 1 to `(anim_id-1)*2` to pick front vs back of the SEQ pair.
const SUB_E_CARDINAL_OFFSET: Array[int] = [
	0, 1, 1, 0,
]

# Sub-table F — cardinal-indexed SEQ mirror flag (`local[+0x18+card*2]`).
# Same indexing as Sub-table E; mode bits for the horizontal mirror of
# the SEQ-range pose. S/E → no mirror, W/N → mirror (value 2).
const SUB_F_CARDINAL_MIRROR: Array[int] = [
	0, 0, 2, 2,
]


## Resolve the TYPE1 body SEQ key for a low-range anim (`1..0x1f4`), mirroring
## PSX `FUN_80085c0c` (BATTLE.BIN `0x80085df4`+) exactly. The renderer dispatches
## on the animation, not on whether the SEQ is single-frame:
##   * `event_anim_id == 2` (Godot `current_anim_id == 3`) — the chapel "at-ease"
##     stance — takes the pose-octant "tent" (CASE A, `0x80085e14`, gated by
##     `bne v1,2`): one of the 5 authored frame bases by 4-bit pose_octant, so
##     the stance rotates smoothly under the camera swoop.
##   * every OTHER low-range anim takes the general path (CASE B, `0x80085ec4`):
##     `seq_key = event_anim_id*2 + frontback[cardinal]` (frontback `[0,1,1,0]`)
##     — its OWN authored frame, with the X-mirror from the cardinal table.
## Ground-truthed live (orbonne held-by-Simon beat): the female knight at
## `event_anim_id 0x24` resolves `unit[+0x1DC] = 0x48 = 72` → SHP frame 72 (the
## kneel), while the chapel anim-2 actors sit at tent keys `1..5`. The earlier
## "single-LoadFrameWait → tent" heuristic wrongly routed the kneel through the
## tent and painted a standing idle frame. Returns `{seq_key: String,
## mirror: bool}`; `type1_seq` is consulted only for the CASE B back-frame
## fallback when `(anim-1)*2 + 1` isn't authored.
static func resolve_low_range_seq_key(
		current_anim_id: int, pose_octant: int, type1_seq: Dictionary) -> Dictionary:
	if current_anim_id == 3:
		return {
			"seq_key": str(SUB_A_FRAME_BASE[pose_octant]),
			"mirror": (SUB_B_MIRROR[pose_octant] & 0x02) != 0,
		}
	# Render class (ADR-0057): the atlas cardinal is a derived view of the
	# camera-composed pose octant — route through the one converter.
	var cardinal_idx := AnimationStateController.pose_octant_to_atlas_cardinal(pose_octant)
	var use_back: int = SUB_E_CARDINAL_OFFSET[cardinal_idx]
	var key := str((current_anim_id - 1) * 2 + use_back)
	if not type1_seq.has(key):
		key = str((current_anim_id - 1) * 2)
	return {
		"seq_key": key,
		"mirror": (SUB_F_CARDINAL_MIRROR[cardinal_idx] & 0x02) != 0,
	}
