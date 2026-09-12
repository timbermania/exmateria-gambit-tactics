extends SceneTree
## Corpus audit: WHICH feds tracks are stubs (no EndBar in their bounded bytes)?
##
## Answers two questions the ADR-0085 flow-through work leaned on as assumptions:
##   1. Is a stub always the FIRST track of a pair (even index), so the flow always
##      lands in its own partner?
##   2. Does any flow's EndBar land in or past the NEXT pair's bytes (crosses_pair)?
##
## Uses the SAME decoder the panel does (FedsBank + SMD opcode walk) — never a
## byte-scan for 0x90 (a 0x90 byte can be another opcode's parameter).
##
## Run (NOT headless), from the package root:
##   godot --path . -s res://tools/feds_stub_audit.gd

const SMD = preload("res://addons/exmateria_sound/runtime/sound_opcodes.gd")


func _initialize() -> void:
	var dirs := _scan()
	var total_effects := 0
	var total_pairs := 0
	var stubs_even := 0
	var stubs_odd := 0
	var crosses := 0
	var no_end_at_all := 0
	var odd_examples: Array = []
	var cross_examples: Array = []
	var even_examples: Array = []
	for d in dirs:
		var path := "res://assets/effects/%s/feds.bin" % d
		if not FileAccess.file_exists(path):
			continue
		var bank = ExMateriaSound.FedsBank.load_from_file(path)
		if bank == null:
			continue
		total_effects += 1
		total_pairs += bank.num_pairs
		for ti in range(bank.num_tracks):
			var bounded: PackedByteArray = bank.get_track_bytes(ti)
			if bounded.is_empty():
				continue
			if _has_end_bar(SMD.decode_track(bounded, bounded.size())):
				continue
			# Stub.
			if ti % 2 == 0:
				stubs_even += 1
				if even_examples.size() < 6:
					even_examples.append("%s pair %d track A (%d B)" % [d, ti / 2, bounded.size()])
			else:
				stubs_odd += 1
				if odd_examples.size() < 20:
					odd_examples.append("%s pair %d track B (%d B)" % [d, ti / 2, bounded.size()])
			# Where does the continuous decode terminate?
			var flowed: Array = bank.get_track_events_from(ti)
			var base: int = bank.track_offsets[ti]
			var end_off := _end_bar_offset(flowed, base)
			if end_off < 0:
				no_end_at_all += 1
				cross_examples.append("%s track %d: NO EndBar anywhere" % [d, ti])
				continue
			var next_pair_track: int = (ti / 2 + 1) * 2
			var next_pair_off: int = bank.data_size
			if next_pair_track < bank.num_tracks:
				next_pair_off = bank.track_offsets[next_pair_track]
			if end_off >= next_pair_off:
				crosses += 1
				if cross_examples.size() < 20:
					cross_examples.append("%s track %d: EndBar @0x%X, next pair @0x%X"
							% [d, ti, end_off, next_pair_off])
	print("=== feds stub audit ===")
	print("effects with feds: %d   pairs: %d" % [total_effects, total_pairs])
	print("stub tracks on EVEN index (track A, flows into its own partner): %d" % stubs_even)
	print("stub tracks on ODD index (track B, flows into the NEXT pair): %d" % stubs_odd)
	print("flows crossing into the next pair (crosses_pair): %d" % crosses)
	print("flows with no EndBar anywhere: %d" % no_end_at_all)
	print("--- track A stub examples ---")
	for e in even_examples:
		print("  " + e)
	print("--- track B stub examples ---")
	for e in odd_examples:
		print("  " + e)
	print("--- crossing / unterminated examples ---")
	for e in cross_examples:
		print("  " + e)
	quit()


static func _has_end_bar(events: Array) -> bool:
	for e in events:
		if e is SMD.OpcodeEvent and e.opcode == 0x90:
			return true
	return false


static func _end_bar_offset(events: Array, base: int) -> int:
	for e in events:
		if e is SMD.OpcodeEvent and e.opcode == 0x90:
			return base + e.offset
	return -1


func _scan() -> Array:
	var out: Array = []
	var da := DirAccess.open("res://assets/effects")
	if da == null:
		return out
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if da.current_is_dir() and name.begins_with("E"):
			out.append(name)
		name = da.get_next()
	da.list_dir_end()
	out.sort()
	return out
