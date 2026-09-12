extends Node
## CORPUS invariant sweep for the colour boundary trade (ADR-0101 decision 1). The synthetic
## guard (`ColourBoundaryFarEdgeTest`) proves the invariant over a hand-built fixture space;
## this one proves it over the SHIPPED distribution — every adjacent keyframe pair on every
## palette and screen channel of every extractable effect.
##
## Why both: the fixture space is what someone thought to write down, and the last three bugs
## in this area all had guards that exercised the decision and never the data. The totals a real
## channel produces are the thing decision 1 rests on — "a trade's total is by construction the
## sum of two storable lengths, so an exact pair always exists" is a claim ABOUT THE CORPUS, and
## this is where it gets checked rather than argued.
##
## Runs the REAL choke point (`EffectEditSession.apply_edit`) against real loaded channels,
## snapshotting and restoring around each edit so the shared EffectData cache is left pristine.
##
## Slow by design (loads the whole corpus). NOT part of the fast net — run it directly:
##   <GODOT> --path . res://tests/ColourBoundaryCorpusSweepTest.tscn

const Session = preload("res://src/effects/studio/EffectEditSession.gd")
const EffectDataClass = ExMateriaEffects.EffectData
const Lowering = preload("res://src/effects/studio/ColorLowering.gd")
const PaletteChannelClass = preload("res://src/effects/studio/PaletteChannel.gd")
const ScreenChannelClass = preload("res://src/effects/studio/ScreenChannel.gd")
const PaletteDataClass = ExMateriaEffects.PaletteData
const EffectPhaseClass = ExMateriaEffects.EffectPhase

const EFFECTS_DIR := "res://assets/effects"
## Drag positions probed per boundary, as fractions of the pair's total — plus the two extremes,
## which is where the 1-frame minimum (and therefore the drift) lived.
const PROBE_FRACTIONS := [0.0, 0.03, 0.25, 0.5, 0.75, 0.97, 1.0]

var _passed: int = 0
var _failed: int = 0
var _effects: int = 0
var _channels: int = 0
var _boundaries: int = 0
var _edits: int = 0
var _violations: Array = []
var _unreachable_totals: Dictionary = {}


func _ready() -> void:
	var dirs := _effect_dirs()
	for dir in dirs:
		var ed = EffectDataClass.load_from_directory(dir)
		if ed == null:
			continue
		_effects += 1
		if ed.palette != null:
			_sweep_palette(ed, dir)
		if ed.screen != null:
			_sweep_screen(ed, dir)

	print("[corpus] %d effects, %d colour channels, %d boundaries, %d trades applied"
		% [_effects, _channels, _boundaries, _edits])

	_assert_true(_effects > 300, "the corpus actually loaded (%d effects)" % _effects)
	_assert_true(_boundaries > 1000, "the sweep found real boundaries to drag (%d)" % _boundaries)
	_assert_eq(_violations.size(), 0,
		"every trade in the corpus conserved its far edge (first 3: %s)"
			% str(_violations.slice(0, 3)))
	_assert_eq(_unreachable_totals.size(), 0,
		"every total in the corpus admits an exact storable pair (%s)"
			% str(_unreachable_totals.keys().slice(0, 5)))

	print("\n=== ColourBoundaryCorpusSweepTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ColourBoundaryCorpusSweepTest")
		get_tree().quit(1)
	else:
		print("[PASS] ColourBoundaryCorpusSweepTest")
		get_tree().quit(0)


func _sweep_palette(ed, dir: String) -> void:
	for phase in EffectPhaseClass.ALL:
		for channel_name in PaletteDataClass.ALL_CHANNELS:
			var ch = ed.palette.get_channel(phase, channel_name)
			if ch == null:
				continue
			_channels += 1
			var ref := {"channel": "palette", "context": phase,
				"channel_name": channel_name, "field": "boundary_end"}
			_sweep_channel(ed, ch, ref, PaletteChannelClass, dir)


func _sweep_screen(ed, dir: String) -> void:
	for phase in EffectPhaseClass.ALL:
		var ch = ed.screen.get_channel(phase)
		if ch == null:
			continue
		_channels += 1
		var ref := {"channel": "screen", "context": phase, "field": "boundary_end"}
		_sweep_channel(ed, ch, ref, ScreenChannelClass, dir)


## Every adjacent PLAYED pair on one channel: drag their shared boundary to a spread of
## positions and assert the pair's combined length never changes.
func _sweep_channel(ed, ch, base_ref: Dictionary, channel_class, dir: String) -> void:
	var last: int = mini(ch.keyframes.size(), maxi(0, int(ch.max_keyframe) - 1))
	var session = Session.new(ed)
	for n in range(0, last - 1):
		var dur_a: int = Lowering.duration_for_time_value(int(ch.keyframes[n].time_value))
		var dur_b: int = Lowering.duration_for_time_value(int(ch.keyframes[n + 1].time_value))
		var total: int = dur_a + dur_b
		_boundaries += 1

		# Decision 1's load-bearing claim, checked against the real total.
		var pair := Lowering.trade_durations(total, total / 2)
		if int(pair["first"]) + int(pair["second"]) != total:
			_unreachable_totals[total] = true

		var start_n: int = 0
		for i in range(n):
			start_n += Lowering.duration_for_time_value(int(ch.keyframes[i].time_value))

		var ref := base_ref.duplicate()
		ref["event_index"] = n
		for frac in PROBE_FRACTIONS:
			var snap: Dictionary = channel_class.snapshot(ed, ref)
			var desired: int = start_n + int(round(float(total) * float(frac)))
			session.apply_edit(ref, desired)
			_edits += 1
			var got: int = Lowering.duration_for_time_value(int(ch.keyframes[n].time_value)) \
				+ Lowering.duration_for_time_value(int(ch.keyframes[n + 1].time_value))
			if got != total and _violations.size() < 20:
				_violations.append("%s %s[%d] total %d → %d (drag %d)"
					% [dir.get_file(), str(base_ref.get("channel", "")), n, total, got, desired])
			channel_class.restore(ed, snap)   # leave the shared cache pristine


func _effect_dirs() -> Array:
	var out: Array = []
	var da := DirAccess.open(EFFECTS_DIR)
	if da == null:
		return out
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if da.current_is_dir() and name.begins_with("E"):
			out.append("%s/%s" % [EFFECTS_DIR, name])
		name = da.get_next()
	da.list_dir_end()
	out.sort()
	return out


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
