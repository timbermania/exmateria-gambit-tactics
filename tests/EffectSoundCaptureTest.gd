extends Node
## EffectSoundCaptureTest — offline audio-capture regression for the continuous
## FEDS effect-sound engine. Drives the REAL game path (EffectJSONLoader →
## EffectSoundController → ExMateriaEffectSfx.play_pair → shared pool/runtime/SPU) in
## ExMateriaEffectSfx.capture_mode, rendering the SFX SPU deterministically
## frame-by-frame to a PCM buffer instead of live audio. Writes a WAV per case
## (under user://sfx_captures/) and asserts:
##   - single effects are audible at the expected onset (incl. replay);
##   - TWO effects sequence simultaneously (concurrency);
##   - a cast's tail RINGS OUT after end_effect (no trimming).
##
## panic() is used between cases for clean isolation only — the gameplay engine
## is continuous and never reset.
##
## Run:  godot --path . res://tests/EffectSoundCaptureTest.tscn
## Suite verdict: prints [PASS] / [FAIL] (picked up by tests/run_all_tests.sh).

const EffectJSONLoaderClass = preload("res://addons/exmateria_sound/runtime/effect_json_loader.gd")
const EffectSoundControllerClass = preload("res://addons/exmateria_sound/runtime/effect_sound_controller.gd")

const SUBS_PER_FRAME := 8          # 240 Hz IRQ / 30 fps timeline
const CAPTURE_FRAMES := 150        # 5 s — onset + tail
const SILENCE_THRESH := 0.004      # normalized peak that counts as "audible"
const ONSET_TOLERANCE := 6

# Expected first-audible frame = phase start + track cumulative-onset:
#   Shiva/Ifrit fire in PHASE1 (frame 0) → 5 / 9; Cure fires in PHASE_FOR_EACH
#   (starts at phase1_duration=12) → 12 + 10 = 22.
var _cases := [
	{"id": "E065", "label": "Shiva", "onset": 5},
	{"id": "E001", "label": "Cure", "onset": 22},
	{"id": "E065", "label": "Shiva_replay", "onset": 5},
	{"id": "E067", "label": "Ifrit", "onset": 9},
]

var _cur_frame := 0


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	if not ExMateriaAudioEngine.ready_ok or not ExMateriaEffectSfx.ready_ok:
		print("[FAIL] audio engines not ready")
		get_tree().quit(1)
		return

	DirAccess.make_dir_recursive_absolute("user://sfx_captures")
	print("[capture] writing WAVs under: %s" % ProjectSettings.globalize_path("user://sfx_captures"))
	ExMateriaEffectSfx.capture_mode = true

	var all_pass := true
	for c in _cases:
		all_pass = _run_single(c) and all_pass
	all_pass = _run_concurrency() and all_pass
	all_pass = _run_tail() and all_pass
	all_pass = _run_noise_leak() and all_pass
	all_pass = _run_high_concurrency() and all_pass
	all_pass = _run_faithful_mode() and all_pass
	all_pass = _run_orphan_playout() and all_pass

	ExMateriaEffectSfx.capture_mode = false

	if all_pass:
		print("[PASS] continuous SFX engine: single effects audible+on-onset, 2 effects overlap, tail rings out")
		get_tree().quit(0)
	else:
		print("[FAIL] one or more effect-sound checks failed (see [case]/[concurrency]/[tail] lines)")
		get_tree().quit(1)


# ---- single-effect cases (audible + onset, incl. replay) --------------------

func _run_single(c: Dictionary) -> bool:
	ExMateriaEffectSfx.panic()  # isolate from the previous case
	var loaded = EffectJSONLoaderClass.load_dir("res://assets/effects/%s" % c.id)
	if loaded == null or not loaded.has_sound():
		print("[case] %s: no sound data" % c.id)
		return false

	var triggers := [0]
	var token: int = ExMateriaEffectSfx.begin_effect()
	var stc = EffectSoundControllerClass.new()
	stc.debug_log = false
	if not stc.load_effect(loaded):
		print("[case] %s: load_effect failed" % c.id)
		ExMateriaEffectSfx.end_effect(token)
		return false
	var fb = loaded.feds_bank
	stc.pair_triggered.connect(func(pair_idx: int, _ch: int, sid: int, _ph: String) -> void:
		triggers[0] += 1
		ExMateriaEffectSfx.play_pair(token, fb, pair_idx, sid)
	)
	stc.start(1, 0, {})

	var pcm := PackedInt32Array()
	var env := _drive(stc, token, CAPTURE_FRAMES, pcm)
	ExMateriaEffectSfx.end_effect(token)
	_write_wav("user://sfx_captures/sfx_%s_%s.wav" % [c.id, c.label], pcm)

	var peak := _peak(env)
	var onset := _onset(env)
	var onset_ok: bool = onset >= 0 and absi(onset - int(c.onset)) <= ONSET_TOLERANCE
	var ok: bool = peak >= SILENCE_THRESH and triggers[0] > 0 and onset_ok
	print("[case] %-13s triggers=%d onset=%d (expect~%d) peak=%.4f -> %s"
		% [c.label, triggers[0], onset, int(c.onset), peak, "OK" if ok else "BAD"])
	return ok


# ---- concurrency: two effects sequencing at the same time -------------------

func _run_concurrency() -> bool:
	ExMateriaEffectSfx.panic()
	var a = EffectJSONLoaderClass.load_dir("res://assets/effects/E065")  # Shiva, onset ~5
	var b = EffectJSONLoaderClass.load_dir("res://assets/effects/E001")  # Cure, onset ~22
	if not a.has_sound() or not b.has_sound():
		print("[concurrency] missing sound data")
		return false

	var ta: int = ExMateriaEffectSfx.begin_effect()
	var tb: int = ExMateriaEffectSfx.begin_effect()
	var trig := [0, 0]
	var stc_a = EffectSoundControllerClass.new(); stc_a.debug_log = false; stc_a.load_effect(a)
	var stc_b = EffectSoundControllerClass.new(); stc_b.debug_log = false; stc_b.load_effect(b)
	var fa = a.feds_bank
	var fb = b.feds_bank
	stc_a.pair_triggered.connect(func(p: int, _c: int, s: int, _ph: String) -> void:
		trig[0] += 1; ExMateriaEffectSfx.play_pair(ta, fa, p, s))
	stc_b.pair_triggered.connect(func(p: int, _c: int, s: int, _ph: String) -> void:
		trig[1] += 1; ExMateriaEffectSfx.play_pair(tb, fb, p, s))
	stc_a.start(1, 0, {})
	stc_b.start(1, 0, {})

	var pcm := PackedInt32Array()
	var env := PackedFloat32Array()
	for f in range(CAPTURE_FRAMES):
		_cur_frame = f
		stc_a.update(f)
		stc_b.update(f)
		var sub := ExMateriaEffectSfx.render_subs(SUBS_PER_FRAME)
		env.append(_sub_peak(sub))
		pcm.append_array(sub)
	ExMateriaEffectSfx.end_effect(ta)
	ExMateriaEffectSfx.end_effect(tb)
	_write_wav("user://sfx_captures/sfx_concurrency_Shiva+Cure.wav", pcm)

	# Audio must be present in BOTH effects' onset windows within the one render.
	var shiva_on: bool = _audible_in(env, 3, 14)    # Shiva onset ~5
	var cure_on: bool = _audible_in(env, 18, 34)     # Cure onset ~22
	var ok: bool = trig[0] > 0 and trig[1] > 0 and shiva_on and cure_on
	print("[concurrency] shiva_triggers=%d cure_triggers=%d shiva_window_audible=%s cure_window_audible=%s peak=%.4f -> %s"
		% [trig[0], trig[1], str(shiva_on), str(cure_on), _peak(env), "OK" if ok else "BAD"])
	return ok


# ---- high concurrency: many simultaneous casts spread across stacked SPU
#      units (UNLOCKED) instead of preempting each other -----------------------

func _run_high_concurrency() -> bool:
	# 8 Shiva casts x 3 pairs = 24 pairs > one unit's 12, so the engine must
	# spawn a 2nd stacked SPU and place ALL of them without pool exhaustion.
	ExMateriaEffectSfx.panic()
	var loaded = EffectJSONLoaderClass.load_dir("res://assets/effects/E065")
	var fb = loaded.feds_bank
	var tokens: Array = []
	var all_dispatched := true
	for k in range(8):
		var t: int = ExMateriaEffectSfx.begin_effect()
		tokens.append(t)
		for pair in range(3):  # Shiva = 3 pairs
			if not ExMateriaEffectSfx.play_pair(t, fb, pair, pair + 1):
				all_dispatched = false
	var env := PackedFloat32Array()
	for _f in range(40):
		env.append(_sub_peak(ExMateriaEffectSfx.render_subs(SUBS_PER_FRAME)))
	var units: int = ExMateriaEffectSfx.unit_count()
	for t in tokens:
		ExMateriaEffectSfx.end_effect(t)

	var audible: bool = _peak(env) >= SILENCE_THRESH
	# 24 pairs needs >=2 units; all must have dispatched (no starvation).
	var ok: bool = all_dispatched and audible and units >= 2
	print("[concurrency_hi] 8 casts x3 pairs: units_spawned=%d all_dispatched=%s audible=%s -> %s"
		% [units, str(all_dispatched), str(audible), "OK" if ok else "BAD: starved/preempted"])
	# Reset back to a single unit so later state is clean.
	ExMateriaEffectSfx.panic()
	return ok


# ---- orphan playout: when an effect's VISUAL ends early (its node is freed),
#      the SOUND must keep playing to its natural end, not get cut --------------

func _run_orphan_playout() -> bool:
	# This reproduces the F5 path: a long sound (Shiva) whose visual finishes
	# while the sound is still going. orphan_effect() must let it play out.
	ExMateriaEffectSfx.panic()
	var loaded = EffectJSONLoaderClass.load_dir("res://assets/effects/E065")
	var fb = loaded.feds_bank
	var token: int = ExMateriaEffectSfx.begin_effect()
	var stc = EffectSoundControllerClass.new(); stc.debug_log = false; stc.load_effect(loaded)
	stc.pair_triggered.connect(func(p: int, _c: int, s: int, _ph: String) -> void:
		ExMateriaEffectSfx.play_pair(token, fb, p, s))
	stc.start(1, 0, {})

	# Drive ~20 frames so the pairs fire, then ORPHAN early (visual "ended").
	for f in range(20):
		stc.update(f)
		ExMateriaEffectSfx.render_subs(SUBS_PER_FRAME)
	ExMateriaEffectSfx.orphan_effect(token)  # F5: EffectInstance._exit_tree

	# With NO further controller ticks, the dispatched sound must keep playing.
	# Sample well past a mere release tail (~1.3 s): if still audible at ~2-3 s
	# the full FEDS sequence is playing out, not just a cut-off release.
	var env := PackedFloat32Array()
	for _f in range(120):  # 4 s
		env.append(_sub_peak(ExMateriaEffectSfx.render_subs(SUBS_PER_FRAME)))
	var early: bool = _audible_in(env, 0, 20)     # right after orphan
	var sustained: bool = _audible_in(env, 60, 110)  # 2-3.7 s later — full sequence, not just release
	var ok: bool = early and sustained
	print("[orphan] after orphan: early_audible=%s sustained(2-3.7s)=%s peak=%.3f -> %s"
		% [str(early), str(sustained), _peak(env), "OK" if ok else "BAD: sound cut at visual end"])
	ExMateriaEffectSfx.panic()
	return ok


# ---- FAITHFUL mode: the toggle keeps a single PSX SPU (3 pairs), never spawns
#      stacked units even under heavy load (it preempts, as the real game does) -

func _run_faithful_mode() -> bool:
	ExMateriaEffectSfx.set_voice_mode(ExMateriaEffectSfx.VoiceMode.FAITHFUL)
	ExMateriaEffectSfx.panic()
	var loaded = EffectJSONLoaderClass.load_dir("res://assets/effects/E065")
	var fb = loaded.feds_bank
	var tokens: Array = []
	for k in range(8):  # well over the 3-pair FAITHFUL budget
		var t: int = ExMateriaEffectSfx.begin_effect()
		tokens.append(t)
		for pair in range(3):
			ExMateriaEffectSfx.play_pair(t, fb, pair, pair + 1)
	var env := PackedFloat32Array()
	for _f in range(30):
		env.append(_sub_peak(ExMateriaEffectSfx.render_subs(SUBS_PER_FRAME)))
	var units: int = ExMateriaEffectSfx.unit_count()
	for t in tokens:
		ExMateriaEffectSfx.end_effect(t)
	var audible: bool = _peak(env) >= SILENCE_THRESH
	var ok: bool = audible and units == 1  # FAITHFUL must NOT stack SPUs
	print("[faithful] audible=%s units=%d (must be 1, no stacking) -> %s"
		% [str(audible), units, "OK" if ok else "BAD"])
	# Restore the game default.
	ExMateriaEffectSfx.set_voice_mode(ExMateriaEffectSfx.VoiceMode.UNLOCKED)
	ExMateriaEffectSfx.panic()
	return ok


# ---- noise leak: an effect that used SPU noise (Shiva) must not leave a
#      reused voice in noise mode for the next effect (Reraise) --------------

func _run_noise_leak() -> bool:
	# Reraise alone peaks ~0.52. Before the fix, playing it after Shiva (which
	# puts a voice in SPU noise mode for its shimmer) left that voice in noise
	# mode -> Reraise played as noise and peaked ~1.0 (distorted). The pool now
	# clears voice noise/FMod at allocation (FFT FUN_800137d8), so Reraise should
	# stay ~0.52 regardless of Shiva having played first.
	ExMateriaEffectSfx.panic()
	var reraise_alone := _peak(_capture_effect("E007", 120).env)

	ExMateriaEffectSfx.panic()
	_drive_effect("E065", 60)            # Shiva (uses noise)
	ExMateriaEffectSfx.stop_all()           # end it (release)
	var reraise_after := _peak(_capture_effect("E007", 120).env)

	# After Shiva, Reraise must not be inflated toward full-scale by stale noise.
	var ratio := reraise_after / maxf(0.001, reraise_alone)
	var ok: bool = reraise_after <= 0.75 and ratio <= 1.4
	print("[noise_leak] reraise_alone=%.3f reraise_after_shiva=%.3f ratio=%.2f -> %s"
		% [reraise_alone, reraise_after, ratio, "OK" if ok else "BAD: noise leaked from Shiva"])
	return ok


func _capture_effect(eid: String, frames: int) -> Dictionary:
	var loaded = EffectJSONLoaderClass.load_dir("res://assets/effects/%s" % eid)
	var token: int = ExMateriaEffectSfx.begin_effect()
	var stc = EffectSoundControllerClass.new(); stc.debug_log = false; stc.load_effect(loaded)
	var fb = loaded.feds_bank
	stc.pair_triggered.connect(func(p: int, _c: int, s: int, _ph: String) -> void:
		ExMateriaEffectSfx.play_pair(token, fb, p, s))
	stc.start(1, 0, {})
	var env := PackedFloat32Array()
	for f in range(frames):
		stc.update(f)
		env.append(_sub_peak(ExMateriaEffectSfx.render_subs(SUBS_PER_FRAME)))
	ExMateriaEffectSfx.end_effect(token)
	return {"env": env}


func _drive_effect(eid: String, frames: int) -> void:
	var loaded = EffectJSONLoaderClass.load_dir("res://assets/effects/%s" % eid)
	var token: int = ExMateriaEffectSfx.begin_effect()
	var stc = EffectSoundControllerClass.new(); stc.debug_log = false; stc.load_effect(loaded)
	var fb = loaded.feds_bank
	stc.pair_triggered.connect(func(p: int, _c: int, s: int, _ph: String) -> void:
		ExMateriaEffectSfx.play_pair(token, fb, p, s))
	stc.start(1, 0, {})
	for f in range(frames):
		stc.update(f)
		ExMateriaEffectSfx.render_subs(SUBS_PER_FRAME)


# ---- tail: audio rings out AFTER end_effect (no trimming) -------------------

func _run_tail() -> bool:
	# Shiva is a long SUSTAINED summon sound (>5 s). Stopping it mid-sustain is
	# the exact "stuck note droning forever" case: end_effect must key-off so the
	# held note RELEASES (audible tail) and then DECAYS to silence (not stuck).
	ExMateriaEffectSfx.panic()
	var loaded = EffectJSONLoaderClass.load_dir("res://assets/effects/E065")
	if not loaded.has_sound():
		print("[tail] missing sound data")
		return false
	var token: int = ExMateriaEffectSfx.begin_effect()
	var stc = EffectSoundControllerClass.new(); stc.debug_log = false; stc.load_effect(loaded)
	var fb = loaded.feds_bank
	stc.pair_triggered.connect(func(p: int, _c: int, s: int, _ph: String) -> void:
		ExMateriaEffectSfx.play_pair(token, fb, p, s))
	stc.start(1, 0, {})

	# Drive ~1.3 s into the sustain, then stop (simulate a mid-play stop).
	const END_AT := 40
	const POST_FRAMES := 180  # ~6 s of tail to confirm it actually decays
	var pcm := PackedInt32Array()
	for f in range(END_AT):
		stc.update(f)
		pcm.append_array(ExMateriaEffectSfx.render_subs(SUBS_PER_FRAME))
	ExMateriaEffectSfx.end_effect(token)  # key-off -> release, NOT a hard cut

	var post_env := PackedFloat32Array()
	for _f in range(POST_FRAMES):
		var sub := ExMateriaEffectSfx.render_subs(SUBS_PER_FRAME)
		post_env.append(_sub_peak(sub))
		pcm.append_array(sub)
	_write_wav("user://sfx_captures/sfx_tail_Shiva_stop.wav", pcm)

	# (a) tail audible right after stop (release ringing, not hard-cut);
	# (b) decays to silence by the end (NOT a stuck/droning note).
	var tail_audible: bool = _audible_in(post_env, 1, 20)
	var last_audible := -1
	for i in range(post_env.size()):
		if post_env[i] >= SILENCE_THRESH:
			last_audible = i
	var decayed: bool = last_audible >= 0 and last_audible < POST_FRAMES - 5
	var ok: bool = tail_audible and decayed
	print("[tail] mid-sustain stop: tail_audible=%s decays_to_silence=%s (last audible %d/%d frames after stop) -> %s"
		% [str(tail_audible), str(decayed), last_audible, POST_FRAMES,
			"OK" if ok else ("BAD: STUCK/DRONING" if tail_audible else "BAD: trimmed")])
	return ok


# ---- helpers ----------------------------------------------------------------

func _drive(stc, _token: int, frames: int, pcm: PackedInt32Array) -> PackedFloat32Array:
	var env := PackedFloat32Array()
	for f in range(frames):
		_cur_frame = f
		stc.update(f)
		var sub := ExMateriaEffectSfx.render_subs(SUBS_PER_FRAME)
		env.append(_sub_peak(sub))
		pcm.append_array(sub)
	return env


func _sub_peak(sub: PackedInt32Array) -> float:
	var pk := 0
	for v in sub:
		var a: int = absi(v)
		if a > pk:
			pk = a
	return float(pk) / 32767.0


func _peak(env: PackedFloat32Array) -> float:
	var p := 0.0
	for v in env:
		if v > p:
			p = v
	return p


func _onset(env: PackedFloat32Array) -> int:
	for i in range(env.size()):
		if env[i] >= SILENCE_THRESH:
			return i
	return -1


func _audible_in(env: PackedFloat32Array, lo: int, hi: int) -> bool:
	for i in range(maxi(0, lo), mini(env.size(), hi + 1)):
		if env[i] >= SILENCE_THRESH:
			return true
	return false


func _write_wav(path: String, pcm: PackedInt32Array) -> void:
	var n_samples := pcm.size()  # frames*2 (interleaved stereo)
	var bytes := PackedByteArray()
	bytes.resize(n_samples * 2)
	for i in range(n_samples):
		var s: int = clampi(pcm[i], -32768, 32767)
		if s < 0:
			s += 65536
		bytes[i * 2] = s & 0xFF
		bytes[i * 2 + 1] = (s >> 8) & 0xFF
	var rate := int(ExMateriaSpu.Spu.SAMPLE_RATE)
	var data_size := bytes.size()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("[capture] could not open %s" % path)
		return
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + data_size)
	f.store_buffer("WAVE".to_ascii_buffer())
	f.store_buffer("fmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)            # PCM
	f.store_16(2)            # stereo
	f.store_32(rate)
	f.store_32(rate * 2 * 2) # byte rate
	f.store_16(2 * 2)        # block align
	f.store_16(16)           # bits
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(data_size)
	f.store_buffer(bytes)
	f.close()
