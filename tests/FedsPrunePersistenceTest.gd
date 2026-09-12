extends Node
## Prune-for-real corpus round-trip gate (ADR-0085 2026-08-13 amendment).
##
## This is the gate the compile path was DEFERRED behind: re-emitted bytes must reproduce the
## ROM's exact encoding. `build_pruned_bank` operates at the BYTE level (slice + splice,
## arithmetic offset fixup) and never re-emits from a parsed event model, so byte-exactness of
## the UNPRUNED regions is guaranteed by construction — but that claim is proven MECHANICALLY
## across the whole effect corpus here, not asserted. For every assets/effects/E###/feds.bin,
## for every pair:
##   (a) SPLICE IDENTITY — replacing a track with ITSELF through the fixup reproduces the
##       original blob byte-for-byte (the offset/section-length math is a true identity at Δ0).
##   (b) OFFSET SELF-CONSISTENCY — the pruned bank's track offsets stay in-bounds and its
##       parse() round-trips (parse(pruned.raw).raw == pruned.raw).
##   (c) TICK PRESERVATION — each pruned track's total delta_time equals the original's (a
##       delete may shrink the bytes but MUST NOT shift the clock).
## No SPU render here — the audible-Δ=0 claim is the proof-only A/B's job (E001/E004/E317).
##
## Run: <GODOT> --path . res://tests/FedsPrunePersistenceTest.tscn

const SMD = preload("res://addons/exmateria_sound/runtime/sound_opcodes.gd")
const FedsBankScript = preload("res://addons/exmateria_sound/runtime/feds_bank.gd")
const GP = preload("res://src/effects/studio/SoundGhostProjector.gd")

const EFFECTS_ROOT := "res://assets/effects"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	var effects := _list_effects()
	# Corpus-dependent (the gitignored ROM-derived effect extract), so it is kept OUT of
	# run_all_tests.sh — like the FEDS acceptance guards. SKIP gracefully on a clean checkout.
	if effects.is_empty():
		print("[SKIP] no effect extract under %s (populate project-assets)" % EFFECTS_ROOT)
		print("[PASS] FedsPrunePersistenceTest")
		get_tree().quit(0)
		return

	var checked_effects := 0
	var checked_pairs := 0
	var identity_fails: Array = []      # (a)
	var parse_fails: Array = []         # (b) — parse round-trip
	var offset_fails: Array = []        # (b) — out-of-bounds offsets
	var tick_fails: Array = []          # (c)

	for eid in effects:
		var path := "%s/%s/feds.bin" % [EFFECTS_ROOT, eid]
		if not FileAccess.file_exists(path):
			continue
		var bank = FedsBankScript.load_from_file(path)
		if bank == null or bank.num_pairs <= 0:
			continue
		checked_effects += 1
		for p in range(bank.num_pairs):
			checked_pairs += 1
			# (a) Splice identity: replace each track with itself → the blob is unchanged.
			for lt in [0, 1]:
				var ti: int = p * 2 + lt
				var same = GP.rebuild_bank_with_track(bank, ti, bank.get_track_bytes(ti))
				if same == null or same.raw != bank.raw:
					identity_fails.append("%s pair %d track %d" % [eid, p, lt])
			# Build the real per-pair prune (full set, both tracks).
			var pruned = GP.build_pruned_bank(bank, p, [0, 1])
			if pruned == null:
				parse_fails.append("%s pair %d — build_pruned_bank null" % [eid, p])
				continue
			# (b) Parse round-trip: the pruned blob re-parses to the identical bytes.
			var reparsed = FedsBankScript.parse(pruned.raw)
			if reparsed == null or reparsed.raw != pruned.raw:
				parse_fails.append("%s pair %d" % [eid, p])
			# (b) Offset self-consistency: every track offset lands inside the pruned blob.
			for i in range(pruned.num_tracks):
				var o: int = pruned.track_offsets[i]
				if o < 0 or o > pruned.raw.size():
					offset_fails.append("%s track_off[%d]=%d (blob %d)" % [eid, i, o, pruned.raw.size()])
			# (c) Tick preservation: each of the pair's two tracks keeps its total delta_time.
			for lt in [0, 1]:
				var ti2: int = p * 2 + lt
				var before_ticks := _total_ticks(bank.get_track_bytes(ti2))
				var after_ticks := _total_ticks(pruned.get_track_bytes(ti2))
				if before_ticks != after_ticks:
					tick_fails.append("%s pair %d track %d: %d → %d" % [eid, p, lt, before_ticks, after_ticks])

	print("[FedsPrunePersistence] %d effects, %d pairs checked" % [checked_effects, checked_pairs])
	_assert_true(checked_pairs > 0, "at least one real pair was exercised")
	_report("(a) splice identity (track-with-itself is byte-exact)", identity_fails)
	_report("(b) pruned blob re-parses identically", parse_fails)
	_report("(b) pruned track offsets stay in-bounds", offset_fails)
	_report("(c) prune preserves each track's total ticks", tick_fails)

	print("\n=== FedsPrunePersistenceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] FedsPrunePersistenceTest")
		get_tree().quit(1)
	else:
		print("[PASS] FedsPrunePersistenceTest")
		get_tree().quit(0)


func _list_effects() -> Array:
	var out: Array = []
	var d := DirAccess.open(EFFECTS_ROOT)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if d.current_is_dir() and name.begins_with("E"):
			out.append(name)
		name = d.get_next()
	d.list_dir_end()
	out.sort()
	return out


## A track's whole clock. Every form that moves the tick counts — the note path's
## delta_time AND the two time-carrying opcodes' parameters (ADR-0085 2026-08-18c §2:
## `0x80 Rest` and `0x81 Fermata` each add exactly `param` ticks; they differ in whose
## ticks they are, never in how many). Counting only NoteEvents was safe while the
## prune's substitute was a note-form rest and blind the moment it became `0x80` —
## the guard would have read the retrofit as 12 ticks vanishing.
func _total_ticks(track_bytes: PackedByteArray) -> int:
	var total := 0
	for e in SMD.decode_track(track_bytes):
		if e is SMD.NoteEvent:
			total += int(e.delta_time)
		elif e.opcode in [0x80, 0x81]:
			total += int(e.params[0]) if e.params.size() > 0 else 0
	return total


func _report(label: String, fails: Array) -> void:
	if fails.is_empty():
		_passed += 1
		return
	_failed += 1
	print("[FAIL] %s — %d violation(s):" % [label, fails.size()])
	for i in range(mini(fails.size(), 8)):
		print("    %s" % fails[i])
	if fails.size() > 8:
		print("    …and %d more" % (fails.size() - 8))


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
