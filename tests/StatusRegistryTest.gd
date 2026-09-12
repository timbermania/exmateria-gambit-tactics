extends Node
## Pure StatusRegistry test (#67). No GPU / RenderingDevice / scene setup.
## Witnesses:
##   1. Round-trip [code]name → bit → name[/code] is identity.
##   2. Unknown name returns -1 (push_error is the loud-fail half).
##   3. [code]bitmask([&"silence", &"haste"])[/code] is the OR of their bits.
##   4. Every [code]STATUS_*[/code] constant in
##      [code]combat_common.glslinc[/code] matches the registry.
##   5. Every ROM duration and countdown slot ([code]DEFAULT_CT[/code] /
##      [code]TIMER_SLOT[/code], #1116) matches the shader's switch arms, in both
##      directions, and no two statuses claim one slot.
## The unknown-name case intentionally emits push_error — that ERROR line is
## expected and does not fail the run.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const StatusRegistry = ExMateriaAlmanac.StatusRegistry


# ADR-0251 dec. 4 — this path lives HERE, not on `StatusRegistry`. The registry
# moved into `addons/exmateria_almanac/`, and an addon that holds a `res://`
# path into `src/gpu/` is arm-6 debt (`check_addon_portability.py`); the parity
# check is a HOST fact about a host shader, so the host's test owns it.
const SHADER_PATH := "res://src/gpu/shaders/combat_common.glslinc"

var _failed := false


func _ready() -> void:
	_test_round_trip()
	_test_unknown_name()
	_test_bitmask()
	_test_shader_parity()
	_test_duration_parity()
	if _failed:
		print("[FAIL] StatusRegistry test")
	else:
		print("[PASS] StatusRegistry: name↔bit round-trip + unknown + bitmask + shader parity + ROM durations/slots OK")
	get_tree().quit()


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		print("[FAIL] %s" % msg)


func _test_round_trip() -> void:
	for n in StatusRegistry.NAMES_TO_BITS:
		var b: int = StatusRegistry.bit(n)
		_expect(b >= 0 and b < 32, "bit(%s) in [0,32), got %d" % [n, b])
		var back := StatusRegistry.name_of(b)
		_expect(back == n, "name_of(bit(%s)) = %s (got %s)" % [n, n, back])


func _test_unknown_name() -> void:
	# push_error here is expected — the test harness keys off [PASS]/[FAIL].
	_expect(StatusRegistry.bit(&"definitely_not_a_status") == -1,
		"unknown name returns -1")
	_expect(StatusRegistry.name_of(99) == &"",
		"name_of(99) returns empty StringName for unmapped bit")


func _test_bitmask() -> void:
	var mask := StatusRegistry.bitmask([&"silence", &"haste"])
	var expected := (1 << StatusRegistry.bit(&"silence")) | (1 << StatusRegistry.bit(&"haste"))
	_expect(mask == expected, "bitmask([silence,haste]) = %d (got %d)" % [expected, mask])

	var empty := StatusRegistry.bitmask([])
	_expect(empty == 0, "bitmask([]) = 0, got %d" % empty)


func _test_shader_parity() -> void:
	# This is the ONLY drift check now (ADR-0251 dec. 4). `StatusRegistry` used
	# to carry a copy in a static-var initializer, which fires at most once per
	# boot — so a run that loaded the registry early from another test never
	# witnessed it — and could only `push_error`, which fails nothing. This one
	# `_expect`s, so drift is a red.
	var f := FileAccess.open(SHADER_PATH, FileAccess.READ)
	_expect(f != null, "shader open(%s)" % SHADER_PATH)
	if f == null:
		return

	var rx := RegEx.new()
	rx.compile("^\\s*const\\s+int\\s+STATUS_([A-Z_]+)\\s*=\\s*(-?\\d+)\\s*;")

	var parsed := 0
	while not f.eof_reached():
		var line := f.get_line()
		var m := rx.search(line)
		if m == null:
			continue
		parsed += 1
		var sname := StringName(m.get_string(1).to_lower())
		var sbit := int(m.get_string(2))
		_expect(StatusRegistry.NAMES_TO_BITS.has(sname),
			"shader STATUS_%s missing from registry" % String(sname).to_upper())
		if StatusRegistry.NAMES_TO_BITS.has(sname):
			var rbit: int = StatusRegistry.NAMES_TO_BITS[sname]
			_expect(rbit == sbit,
				"STATUS_%s — registry=%d, shader=%d" % [String(sname).to_upper(), rbit, sbit])

	_expect(parsed == StatusRegistry.NAMES_TO_BITS.size(),
		"shader parsed %d STATUS_* constants, registry has %d" % [parsed, StatusRegistry.NAMES_TO_BITS.size()])


## The ROM's durations, held to the shader's copy of them (#1116).
##
## 🔴 THE BIT PARITY ABOVE CANNOT SEE THIS. `status_default_ct` and
## `status_timer_slot` are switch statements, not `const int` declarations, so the
## regex above walks straight past them — a duration that disagreed with the
## almanac would decay statuses at one rate in the kernel and be reported at
## another by every CPU-side consumer, with every existing arm green.
##
## Both directions, because one is not the other: a row the shader has and the
## registry does not is a number nobody can read, and a row the registry has and
## the shader does not is a status that silently never expires.
func _test_duration_parity() -> void:
	var f := FileAccess.open(SHADER_PATH, FileAccess.READ)
	_expect(f != null, "shader open(%s)" % SHADER_PATH)
	if f == null:
		return

	# `case STATUS_POISON:     return 36;` — the switch arms of both tables.
	var rx := RegEx.new()
	rx.compile("^\\s*case\\s+STATUS_([A-Z_]+)\\s*:\\s*return\\s+(-?\\d+)\\s*;")
	var in_ct := false
	var in_slot := false
	var shader_ct := {}
	var shader_slot := {}
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("int status_default_ct("):
			in_ct = true
			in_slot = false
			continue
		if line.begins_with("int status_timer_slot("):
			in_slot = true
			in_ct = false
			continue
		if line.begins_with("}"):
			in_ct = false
			in_slot = false
			continue
		var m := rx.search(line)
		if m == null:
			continue
		var sname := StringName(m.get_string(1).to_lower())
		var value := int(m.get_string(2))
		if in_ct:
			shader_ct[sname] = value
		elif in_slot:
			shader_slot[sname] = value

	# Positive control: a regex that matched nothing would pass every arm below.
	_expect(shader_ct.size() > 0 and shader_slot.size() > 0,
		"parsed %d durations and %d slots out of the shader — the switch arms moved and this test stopped looking" % [
			shader_ct.size(), shader_slot.size()])

	for sname in StatusRegistry.DEFAULT_CT:
		_expect(shader_ct.has(sname),
			"registry times %s (%d CT) and the shader does not — it would never expire" % [
				sname, int(StatusRegistry.DEFAULT_CT[sname])])
		if shader_ct.has(sname):
			_expect(int(shader_ct[sname]) == int(StatusRegistry.DEFAULT_CT[sname]),
				"%s CT — registry=%d, shader=%d" % [
					sname, int(StatusRegistry.DEFAULT_CT[sname]), int(shader_ct[sname])])
	for sname in shader_ct:
		_expect(StatusRegistry.DEFAULT_CT.has(sname),
			"shader times %s and the registry does not — no CPU consumer can report it" % sname)

	for sname in StatusRegistry.TIMER_SLOT:
		_expect(shader_slot.get(sname, -1) == int(StatusRegistry.TIMER_SLOT[sname]),
			"%s countdown slot — registry=%d, shader=%s" % [
				sname, int(StatusRegistry.TIMER_SLOT[sname]), str(shader_slot.get(sname, -1))])
	_expect(shader_slot.size() == StatusRegistry.TIMER_SLOT.size(),
		"shader slots %d statuses, registry slots %d" % [shader_slot.size(), StatusRegistry.TIMER_SLOT.size()])

	# A status with a duration and no slot has nowhere to count down; a slot with
	# no duration is a counter nothing ever arms. The ROM has neither, and the
	# extractor asserts the same pairing on the ROM bytes themselves.
	for sname in StatusRegistry.DEFAULT_CT:
		_expect(StatusRegistry.TIMER_SLOT.has(sname),
			"%s has a duration and no countdown slot" % sname)
	for sname in StatusRegistry.TIMER_SLOT:
		_expect(StatusRegistry.DEFAULT_CT.has(sname),
			"%s has a countdown slot and no duration" % sname)

	# Two counters share each int, so a duplicated slot silently overwrites a
	# neighbour's countdown.
	var seen := {}
	for sname in StatusRegistry.TIMER_SLOT:
		var slot: int = int(StatusRegistry.TIMER_SLOT[sname])
		_expect(slot >= 0 and slot < 16, "%s slot %d outside the ROM's sixteen" % [sname, slot])
		_expect(not seen.has(slot), "%s and %s both claim countdown slot %d" % [
			sname, seen.get(slot, &"?"), slot])
		seen[slot] = sname

	# The conversion is derived from the turn meter, not chosen (ADR-0236).
	_expect(StatusRegistry.TICKS_PER_CLOCK_TICK * 100 == 3600,
		"TICKS_PER_CLOCK_TICK=%d disagrees with TURN_METER_FULL/100" % StatusRegistry.TICKS_PER_CLOCK_TICK)
	_expect(StatusRegistry.default_duration_ticks(&"sleep") == 60 * StatusRegistry.TICKS_PER_CLOCK_TICK,
		"sleep should be 60 CT in ticks, got %d" % StatusRegistry.default_duration_ticks(&"sleep"))
	_expect(StatusRegistry.default_duration_ticks(&"darkness") == 0,
		"darkness has no ROM countdown — it must read 0, not a default")
	_expect(StatusRegistry.timer_slot_for_bit(StatusRegistry.bit(&"poison")) == 0,
		"timer_slot_for_bit(poison) should be the ROM's slot 0")
	_expect(StatusRegistry.timer_slot_for_bit(StatusRegistry.bit(&"oil")) == -1,
		"oil is never timed, so it has no slot")
