class_name GPUAnimationTimingLoader
extends RefCounted

## Builds the GPU animation timing buffer from SEQ JSON files.
##
## Extracted from GPUBatchSimulator._build_animation_timings().
## Buffer layout:
##   [anim_id * 2]         = damage_frame (PostGenericAttack tick)
##   [anim_id * 2 + 1]     = total_frames (animation duration)
##   [512 + anim_id]       = move_start_frame (MoveUp2 tick)
##   [768 + wep_anim_id*2] = projectile_frame (QueueSpriteAnim to eff1 tick)
##   [768 + wep_anim_id*2+1] = total_frames for WEP1 animation

const MAX_WEP1_ANIMS = 64
const WEP1_OFFSET = 768


static func build() -> PackedInt32Array:
	var data = PackedInt32Array()
	data.resize(GPUConstants.MAX_ANIMATIONS * 2 + GPUConstants.MAX_ANIMATIONS + MAX_WEP1_ANIMS * 2)

	# Initialize with sentinel values
	for i in range(GPUConstants.MAX_ANIMATIONS):
		data[i * 2] = -1
		data[i * 2 + 1] = -1
		data[512 + i] = -1

	for i in range(MAX_WEP1_ANIMS):
		data[WEP1_OFFSET + i * 2] = -1
		data[WEP1_OFFSET + i * 2 + 1] = -1

	# Load TYPE1 animation timings
	var anim_count = _load_type1_timings(data)

	# Load WEP1 animation timings
	var wep1_count = _load_wep1_timings(data)

	if DebugConfig.gpu_debug_enabled:
		print("[GPUAnimationTimingLoader] Loaded %d TYPE1, %d WEP1 animation timings" % [anim_count, wep1_count])

	return data


static func _load_type1_timings(data: PackedInt32Array) -> int:
	var seq_path = "res://assets/sprites/animations/type1_seq.json"
	var seq_file = FileAccess.open(seq_path, FileAccess.READ)
	if not seq_file:
		push_error("[GPUAnimationTimingLoader] FATAL: Could not open %s" % seq_path)
		assert(false, "SEQ JSON required for animation timing")
		return 0

	var json = JSON.new()
	var err = json.parse(seq_file.get_as_text())
	seq_file.close()

	if err != OK:
		push_error("[GPUAnimationTimingLoader] FATAL: Failed to parse SEQ JSON: %s" % json.get_error_message())
		assert(false, "SEQ JSON parse failed")
		return 0

	var sequences = json.data
	if not sequences is Dictionary:
		push_error("[GPUAnimationTimingLoader] FATAL: SEQ JSON root is not a Dictionary")
		assert(false, "SEQ JSON format invalid")
		return 0

	# parse_seq.py (Phase 1 of issue #53) emits a "_timings" sidecar with the
	# per-animation fields this loader used to walk the opcode stream for.
	# Stale JSON without the sidecar should fail loudly, not silently fall back.
	assert(sequences.has("_timings"),
		"type1_seq.json missing _timings sidecar -- rerun tools/parse_seq.py --all")
	var timings: Dictionary = sequences.get("_timings", {})

	var anim_count = 0
	var move_anim_count = 0
	for anim_id_str in timings.keys():
		var anim_id = int(anim_id_str)
		if anim_id < 0 or anim_id >= GPUConstants.MAX_ANIMATIONS:
			continue

		var t: Dictionary = timings[anim_id_str]
		var damage_frame: int = int(t.get("damage_frame", -1))
		var total_frames: int = int(t.get("total_frames", 0))
		var move_start_frame: int = int(t.get("move_start_frame", -1))

		data[anim_id * 2] = damage_frame
		data[anim_id * 2 + 1] = total_frames
		data[512 + anim_id] = move_start_frame
		anim_count += 1
		if move_start_frame >= 0:
			move_anim_count += 1

	# Verify critical animations loaded correctly
	var anim_60_move_start = data[512 + 60]
	if DebugConfig.gpu_debug_enabled:
		print("[GPUAnimationTimingLoader] Animation 60 (JUMPING) move_start_frame = %d (expected 22)" % anim_60_move_start)
	if anim_60_move_start != 22:
		push_error("[GPUAnimationTimingLoader] FATAL: Animation 60 move_start_frame mismatch! Got %d, expected 22" % anim_60_move_start)
		assert(false, "Animation 60 timing mismatch")

	if DebugConfig.gpu_debug_enabled:
		print("[GPUAnimationTimingLoader] Loaded %d TYPE1 animation timings (%d with MoveUp2)" % [anim_count, move_anim_count])

	return anim_count


static func _load_wep1_timings(data: PackedInt32Array) -> int:
	var wep1_path = "res://assets/sprites/animations/wep1_seq.json"
	var wep1_file = FileAccess.open(wep1_path, FileAccess.READ)
	if not wep1_file:
		push_warning("[GPUAnimationTimingLoader] Could not open %s - projectile timing unavailable" % wep1_path)
		return 0

	var json = JSON.new()
	var err = json.parse(wep1_file.get_as_text())
	wep1_file.close()

	if err != OK:
		push_warning("[GPUAnimationTimingLoader] Failed to parse WEP1 SEQ JSON: %s" % json.get_error_message())
		return 0

	var sequences = json.data
	if not sequences is Dictionary:
		push_warning("[GPUAnimationTimingLoader] WEP1 SEQ JSON root is not a Dictionary")
		return 0

	# parse_seq.py (Phase 1 of issue #53) emits a "_timings" sidecar with the
	# per-animation projectile-frame analog this loader used to walk for.
	assert(sequences.has("_timings"),
		"wep1_seq.json missing _timings sidecar -- rerun tools/parse_seq.py --all")
	var timings: Dictionary = sequences.get("_timings", {})

	var wep1_count = 0
	for anim_id_str in timings.keys():
		var anim_id = int(anim_id_str)
		if anim_id < 0 or anim_id >= MAX_WEP1_ANIMS:
			continue

		var t: Dictionary = timings[anim_id_str]
		var projectile_frame: int = int(t.get("damage_frame", -1))
		var total_frames: int = int(t.get("total_frames", 0))

		data[WEP1_OFFSET + anim_id * 2] = projectile_frame
		data[WEP1_OFFSET + anim_id * 2 + 1] = total_frames
		wep1_count += 1

	# Verify bow animation timing
	var bow_proj_frame = data[WEP1_OFFSET + 12 * 2]
	var bow_total_frames = data[WEP1_OFFSET + 12 * 2 + 1]
	if DebugConfig.gpu_debug_enabled:
		print("[GPUAnimationTimingLoader] WEP1 anim 12: projectile_frame=%d, total_frames=%d at buffer index %d" % [
			bow_proj_frame, bow_total_frames, WEP1_OFFSET + 12 * 2])
		print("[GPUAnimationTimingLoader] Buffer size: %d elements" % data.size())

	return wep1_count
