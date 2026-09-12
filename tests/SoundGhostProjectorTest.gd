extends Node
## TDD guard for SoundGhostProjector — the ADR-0085 tempo-map projection that
## turns a FEDS sound's tick/opcode domain into a length on the effect timeline's
## FRAME axis, through the shared real-SECONDS domain. The load-bearing property is
## that a mid-stream tempo change is INTEGRATED segment-by-segment, never applied
## as one scalar scale over the whole stream. Pure logic: synthetic SMD events and
## a synthetic FedsBank, no scene / no SPU.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/SoundGhostProjectorTest.tscn

const Projector = preload("res://src/effects/studio/SoundGhostProjector.gd")
const SMD = preload("res://addons/exmateria_sound/runtime/sound_opcodes.gd")
const FedsBankClass = preload("res://addons/exmateria_sound/runtime/feds_bank.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_seconds_per_tick_at_120_bpm()
	_test_track_seconds_sums_delta_at_default_tempo()
	_test_tempo_change_is_integrated_not_scaled()
	_test_pair_length_is_the_longer_track()
	_test_resolve_sound_id_through_container_to_pair()
	_test_ghost_frames_end_to_end()
	_test_ghost_map_covers_distinct_firing_sound_ids()
	_test_anchor_hit_frame_is_fire_plus_clamped_offset()
	_test_anchor_offset_from_frame_is_clamped_inverse()
	_test_frame_rms_is_root_mean_square_over_full_scale()
	_test_normalize_peak_scales_the_loudest_sample_to_one()
	_test_audible_length_is_the_last_audible_frame_plus_one()

	print("\n=== SoundGhostProjectorTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] SoundGhostProjectorTest")
		get_tree().quit(1)
	else:
		print("[PASS] SoundGhostProjectorTest")
		get_tree().quit(0)


## At 120 BPM one quarter note (PPQ=48 ticks) lasts exactly 0.5 s, so one tick is
## 0.5 / 48 s. Oracle is the physical definition of BPM, not the code's formula.
func _test_seconds_per_tick_at_120_bpm() -> void:
	_assert_almost(Projector.seconds_per_tick(120.0), 0.5 / 48.0, 1e-9,
		"one tick at 120 BPM is (quarter/48) = 0.5/48 s")


## With no tempo opcode a track defaults to 120 BPM, so summing note delta_times
## is just ticks→seconds at that one rate. Two quarter notes (2×48 ticks) = 1.0 s.
func _test_track_seconds_sums_delta_at_default_tempo() -> void:
	var events := [_note(48), _note(48)]
	_assert_almost(Projector.track_seconds(events), 1.0, 1e-9,
		"two quarter notes at the default 120 BPM last 1.0 s")


## A TEMPO opcode mid-stream must change the rate for the notes AFTER it only.
## First quarter plays at 120 BPM (0.5 s); a Tempo opcode then sets a faster
## tempo; the second quarter plays at the NEW rate. The integrated total must
## differ from both "scale everything by the final tempo" and "…by the initial
## tempo" — that difference is the whole point of the projection.
func _test_tempo_change_is_integrated_not_scaled() -> void:
	# tempo_val 204 → BPM = 204*256/218 (documented fft_tempo_to_bpm formula).
	# Closed-form second-quarter length = 60/BPM = 60*218/(204*256) s, derived
	# algebraically — independent of the projector's own helpers.
	var bpm2 := 204.0 * 256.0 / 218.0
	var seg1 := 0.5                         # first quarter @120 BPM (independent literal)
	var seg2 := 60.0 * 218.0 / (204.0 * 256.0)   # second quarter @bpm2 (closed form)
	var events := [_note(48), _tempo(204), _note(48)]

	_assert_almost(Projector.track_seconds(events), seg1 + seg2, 1e-6,
		"tempo change is integrated: seg1@120 + seg2@new, not one scale")
	# Sanity that the two mis-models are genuinely different numbers we reject.
	var scale_by_final := 96.0 * 60.0 / (bpm2 * 48.0)
	var scale_by_initial := 1.0
	_assert_true(absf((seg1 + seg2) - scale_by_final) > 1e-3,
		"integrated total is NOT scale-by-final-tempo")
	_assert_true(absf((seg1 + seg2) - scale_by_initial) > 1e-3,
		"integrated total is NOT scale-by-initial-tempo")


## A FEDS pair holds two tracks that play CONCURRENTLY, so the pair's real length
## is the LONGER of the two, not their sum. Track A = one quarter (0.5 s); track B
## = two quarters (1.0 s); the pair lasts 1.0 s → 30 frames at the 30 Hz effect
## clock.
func _test_pair_length_is_the_longer_track() -> void:
	var bank = _one_pair_bank()
	_assert_almost(Projector.pair_seconds(bank, 0), 1.0, 1e-9,
		"pair length is the longer of its two concurrent tracks")
	_assert_eq(Projector.pair_frames(bank, 0, 30.0), 30,
		"1.0 s projects to 30 frames at 30 fps")
	_assert_eq(Projector.pair_frames(bank, 99, 30.0), 0,
		"an out-of-range pair projects to 0 frames")


## A timeline sound_id resolves through SoundContainer[sound_id-2]; a DIRECT-mode
## container returns id_a, and the FEDS pair is (resolved-1). sound_id 0/1 skip.
func _test_resolve_sound_id_through_container_to_pair() -> void:
	# One DIRECT (mode 0) container whose id_a is 1 → resolved 1 → pair index 0.
	var containers := {"containers": [{"mode": 0, "id_a": 1, "id_b": 0, "id_c": 0, "index": 0}]}
	_assert_eq(Projector.resolve_pair_idx(containers, 2), 0,
		"sound_id 2 → container[0] DIRECT id_a=1 → pair 0")
	_assert_eq(Projector.resolve_pair_idx(containers, 0), -1,
		"sound_id 0 is a skip → no pair")
	_assert_eq(Projector.resolve_pair_idx(containers, 1), -1,
		"sound_id 1 is a skip → no pair")


## End to end: a sound_id projects to the ghost length in frames of the FEDS pair
## its container selects.
func _test_ghost_frames_end_to_end() -> void:
	var bank = _one_pair_bank()
	var containers := {"containers": [{"mode": 0, "id_a": 1, "id_b": 0, "id_c": 0, "index": 0}]}
	_assert_eq(Projector.ghost_frames_for_sound_id(containers, bank, 2, 30.0), 30,
		"sound_id 2 → container[0] → pair 0 → 1.0 s → 30 ghost frames")
	_assert_eq(Projector.ghost_frames_for_sound_id(containers, bank, 0, 30.0), 0,
		"a skip sound_id has no ghost length")


## The studio hands the model a {sound_id → ghost frames} map. ghost_map walks the
## effect's sound tracks (all phases/channels), collects the DISTINCT firing
## sound_ids (>=2), and projects each once. Skips (0/1) are absent from the map.
func _test_ghost_map_covers_distinct_firing_sound_ids() -> void:
	var bank = _one_pair_bank()
	var containers := {"containers": [{"mode": 0, "id_a": 1, "id_b": 0, "id_c": 0, "index": 0}]}
	var sound := {
		"for_each": [
			{"channel_index": 0, "max_keyframe": 2, "keyframes": [
				{"duration_frames": 6, "sound_id": 0},   # skip
				{"duration_frames": 4, "sound_id": 2},   # fires → pair 0
				{"duration_frames": 4, "sound_id": 2}]},  # same id again (deduped)
		],
	}
	var m := Projector.ghost_map(sound, containers, bank, 30.0)
	_assert_eq(m.get(2, -1), 30, "firing sound_id 2 maps to its 30-frame ghost")
	_assert_true(not m.has(0), "a skip sound_id is not in the ghost map")


## ADR-0085 anchor: the audible HIT lands `anchor_offset` frames into the sound, so
## it draws at `fire + anchor_offset` on the ghost bar. The offset is authoring-only
## metadata (no ROM counterpart) and is clamped to the sound's real length [0, ghost]
## — you cannot declare a hit before the onset or past the end of the sound. The fire
## marker itself never moves. Oracle values are worked by hand, not from the formula.
func _test_anchor_hit_frame_is_fire_plus_clamped_offset() -> void:
	# In range: fire 40, offset 7, ghost 30 → hit at 47.
	_assert_eq(Projector.anchor_hit_frame(40, 7, 30), 47,
		"hit frame is fire + offset when offset is within the ghost length")
	# Past the end: offset 50 > ghost 30 clamps to 30 → hit at 70 (the ghost's tail).
	_assert_eq(Projector.anchor_hit_frame(40, 50, 30), 70,
		"an offset past the sound's length clamps to the ghost end")
	# Before the onset: a negative offset clamps to 0 → hit sits on the fire marker.
	_assert_eq(Projector.anchor_hit_frame(40, -5, 30), 40,
		"a negative offset clamps to 0 (the onset)")
	# No ghost: [0,0] clamps everything to 0 → hit is the fire marker (no length to sit in).
	_assert_eq(Projector.anchor_hit_frame(40, 12, 0), 40,
		"with no ghost length the hit collapses onto the fire marker")


## The drag inverse: a hit position on the ghost bar becomes the offset from the fire
## marker, clamped to [0, ghost]. Round-trips with anchor_hit_frame for an in-range
## offset (the drag can't invent an offset outside the sound).
func _test_anchor_offset_from_frame_is_clamped_inverse() -> void:
	# Drop the hit at frame 47 with fire 40, ghost 30 → offset 7.
	_assert_eq(Projector.anchor_offset_from_frame(47, 40, 30), 7,
		"offset is (hit frame − fire), clamped into the ghost length")
	# Drag past the end (frame 100) clamps to the ghost length 30.
	_assert_eq(Projector.anchor_offset_from_frame(100, 40, 30), 30,
		"dragging past the ghost end clamps the offset to the length")
	# Drag left of the fire marker (frame 35) clamps to 0.
	_assert_eq(Projector.anchor_offset_from_frame(35, 40, 30), 0,
		"dragging before the onset clamps the offset to 0")
	# Round-trip: an in-range offset survives hit→offset.
	_assert_eq(Projector.anchor_offset_from_frame(Projector.anchor_hit_frame(40, 18, 30), 40, 30), 18,
		"an in-range offset round-trips through hit_frame and back")


## The per-frame energy metric (ADR-0085 climax cue) is the RMS of one rendered
## PCM frame — the "audiographic" amplitude, not an opcode guess. A frame is a flat
## interleaved-stereo Int32 PCM block; RMS = sqrt(mean(sample²)), reported over
## digital full-scale (32767) so a full-scale frame reads 1.0. Oracles are the
## physical RMS definition worked by hand, independent of the code.
func _test_frame_rms_is_root_mean_square_over_full_scale() -> void:
	# Empty frame → no energy.
	_assert_almost(Projector.frame_rms(PackedInt32Array([])), 0.0, 1e-9,
		"an empty PCM frame has zero RMS")
	# A single full-scale sample → RMS is full-scale → 1.0.
	_assert_almost(Projector.frame_rms(PackedInt32Array([32767])), 1.0, 1e-6,
		"a full-scale sample reads 1.0 (RMS over 32767)")
	# Two opposite half-ish samples: RMS = |30000| (both squared equal), /32767.
	_assert_almost(Projector.frame_rms(PackedInt32Array([30000, -30000])),
		30000.0 / 32767.0, 1e-6,
		"RMS ignores sign — two ±30000 samples read 30000/32767")
	# Worked mixed frame [3, 4]: sqrt((9+16)/2) = sqrt(12.5) = 3.53553, /32767.
	_assert_almost(Projector.frame_rms(PackedInt32Array([3, 4])),
		sqrt(12.5) / 32767.0, 1e-9,
		"RMS of [3,4] is sqrt(12.5)/32767 (hand-worked)")


## Peak-normalisation (the chosen scaling, ADR-0085): each sound's envelope is
## divided by its OWN loudest sample so the curve fills the ghost bar 0..1 — the
## constant render-scale cancels, and 'where does THIS sound swell' reads clearly.
## An all-zero (silent) envelope stays zero — never a divide-by-zero.
func _test_normalize_peak_scales_the_loudest_sample_to_one() -> void:
	var got := Projector.normalize_peak(PackedFloat32Array([0.5, 2.0, 1.0]))
	_assert_almost(got[0], 0.25, 1e-6, "0.5 / peak(2.0) = 0.25")
	_assert_almost(got[1], 1.0, 1e-6, "the peak sample normalises to 1.0")
	_assert_almost(got[2], 0.5, 1e-6, "1.0 / peak(2.0) = 0.5")
	# Silent envelope: no peak to divide by → stays all-zero (no NaN/inf).
	var silent := Projector.normalize_peak(PackedFloat32Array([0.0, 0.0, 0.0]))
	_assert_eq(silent.size(), 3, "normalising a silent envelope preserves its length")
	_assert_almost(silent[0], 0.0, 1e-9, "a silent envelope stays zero, no divide-by-zero")
	# Empty in → empty out.
	_assert_eq(Projector.normalize_peak(PackedFloat32Array([])).size(), 0,
		"an empty envelope normalises to empty")


## The ghost LENGTH now comes from the real render, not a tick sum: it is how long
## the sound stays AUDIBLE — the last frame at/above the silence threshold, plus one.
## A trailing quiet tail (reverb dropping below threshold) is trimmed; a sound never
## audible has length 0. Oracle values are worked by hand from the threshold rule.
func _test_audible_length_is_the_last_audible_frame_plus_one() -> void:
	_assert_eq(Projector.audible_length(PackedFloat32Array([]), 0.004), 0,
		"an empty render has zero length")
	_assert_eq(Projector.audible_length(PackedFloat32Array([0.0, 0.0, 0.0]), 0.004), 0,
		"a never-audible render has zero length")
	# Audible at 0 and 1, silent after → last audible index 1 → length 2 (tail trimmed).
	_assert_eq(Projector.audible_length(PackedFloat32Array([0.5, 0.1, 0.001, 0.002]), 0.004), 2,
		"the quiet tail past the last audible frame is trimmed")
	# A gap of silence in the MIDDLE doesn't end it — length reaches the last audible frame.
	_assert_eq(Projector.audible_length(PackedFloat32Array([0.001, 0.5, 0.001, 0.3, 0.0]), 0.004), 4,
		"length reaches the last audible frame even across an interior quiet gap")
	# A value exactly at the threshold counts as audible (>=).
	_assert_eq(Projector.audible_length(PackedFloat32Array([0.004]), 0.004), 1,
		"a frame exactly at the threshold is audible")


# --- synthetic FedsBank ---------------------------------------------------

## A hand-built one-pair FedsBank. Note bytecode: [velocity(<0x80), note_byte];
## note_byte 6 → relative_key 0 (a real note), delta index 6 → 48 ticks (a quarter
## at 120 BPM = 0.5 s). 0x90 is EndBar. Track A = one quarter; track B = two.
func _one_pair_bank():
	var fb = FedsBankClass.new()
	fb.pair_count_plus1 = 2                       # → num_pairs 1, num_tracks 2
	fb.raw = PackedByteArray([
		0x40, 6, 0x90,                            # track 0: one quarter + EndBar
		0x40, 6, 0x40, 6, 0x90,                   # track 1: two quarters + EndBar
	])
	fb.data_size = fb.raw.size()
	fb.track_offsets = PackedInt32Array([0, 3])
	return fb


# --- synthetic SMD events -------------------------------------------------

func _note(delta_ticks: int):
	var n = SMD.NoteEvent.new()
	n.velocity = 64
	n.relative_key = 0
	n.delta_time = delta_ticks
	n.note_byte = 0
	return n


func _tempo(tempo_val: int):
	var o = SMD.OpcodeEvent.new()
	o.opcode = 0xA0
	o.params = PackedInt32Array([tempo_val])
	return o


# --- asserts --------------------------------------------------------------

func _assert_almost(actual: float, expected: float, eps: float, label: String) -> void:
	if absf(actual - expected) <= eps:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %f, got %f" % [label, expected, actual])


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
