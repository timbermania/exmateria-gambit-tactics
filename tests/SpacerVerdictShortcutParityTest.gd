extends Node
## PARITY guard for `SpacerVerdicts`' two no-fold shortcuts (the disabled op and the IDENTITY
## op) against the SHIPPED corpus. Both claim to return the same verdict the leave-one-out fold
## would, without folding — and a verdict decides what the painter hides and what
## `ColourMovePlan` may trade, so "same answer, cheaper" has to be measured, not argued.
##
## Method: recompute every palette and screen channel's verdicts twice — once through the real
## `verdicts()`, once with every shortcut FORCED OFF (each op taken through `_is_spacer`) — and
## require them equal, op for op, over every extractable effect. A single disagreement anywhere
## in the corpus fails.
##
## Why this file exists: the identity shortcut rests on three separate claims about
## `ColorStack` (identity map, `reads_base()` false so it can never shadow a restore, and
## affine-merge associativity). Those are arguments; this is the evidence.
##
## Slow by design (folds the whole corpus twice). NOT part of the fast net — run it directly:
##   <GODOT> --path . res://tests/SpacerVerdictShortcutParityTest.tscn

const EffectDataClass = ExMateriaEffects.EffectData
const SpacerVerdictsClass = preload("res://src/effects/studio/SpacerVerdicts.gd")
const PaletteDataClass = ExMateriaEffects.PaletteData
const EffectPhaseClass = ExMateriaEffects.EffectPhase
const Lowering = preload("res://src/effects/studio/ColorLowering.gd")

const EFFECTS_DIR := "res://assets/effects"

var _passed: int = 0
var _failed: int = 0
var _effects: int = 0
var _ops: int = 0
var _shortcut_disabled: int = 0
var _shortcut_identity: int = 0
var _mismatch: Array = []


func _ready() -> void:
	for dir in _effect_dirs():
		var ed = EffectDataClass.load_from_directory(dir)
		if ed == null or ed.palette == null:
			continue
		_effects += 1
		for cname in PaletteDataClass.ALL_CHANNELS:
			_check(_palette_ops(ed, cname), SpacerVerdictsClass.PALETTE_PROFILE,
				"%s %s" % [dir.get_file(), cname])

	print("[parity] %d effects, %d palette ops compared" % [_effects, _ops])
	print("[parity]   taken by the DISABLED shortcut: %d" % _shortcut_disabled)
	print("[parity]   taken by the IDENTITY shortcut: %d" % _shortcut_identity)
	_assert_true(_effects > 300, "the corpus actually loaded (%d effects)" % _effects)
	_assert_true(_ops > 5000, "there were real ops to compare (%d)" % _ops)
	_assert_true(_shortcut_identity > 0,
		"the identity shortcut actually FIRES on shipped data (%d ops)" % _shortcut_identity)
	_assert_eq(_mismatch.size(), 0,
		"every shortcut verdict equals the fold's (first 5: %s)" % str(_mismatch.slice(0, 5)))

	print("\n=== SpacerVerdictShortcutParityTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] SpacerVerdictShortcutParityTest")
		get_tree().quit(1)
	else:
		print("[PASS] SpacerVerdictShortcutParityTest")
		get_tree().quit(0)


## Compare the shipped `verdicts()` against the same computation with NO shortcut taken.
func _check(ops: Array, profile: Dictionary, label: String) -> void:
	if ops.is_empty():
		return
	var fast: Array = SpacerVerdictsClass.verdicts(ops, profile)
	var slow: Array = _verdicts_unshortcut(ops, profile)
	for i in range(ops.size()):
		_ops += 1
		if not bool(ops[i].get("enabled", true)):
			_shortcut_disabled += 1
		elif int(ops[i].get("mode", -1)) == 0 and int(ops[i].get("r", 0)) == 0 \
				and int(ops[i].get("g", 0)) == 0 and int(ops[i].get("b", 0)) == 0 \
				and not bool(ops[i].get("gradient", false)):
			_shortcut_identity += 1
		if bool(fast[i]) != bool(slow[i]) and _mismatch.size() < 20:
			_mismatch.append("%s op %d: shortcut says %s, the fold says %s (mode %d rgb %d,%d,%d)"
				% [label, i, str(fast[i]), str(slow[i]), int(ops[i].get("mode", -1)),
					int(ops[i].get("r", 0)), int(ops[i].get("g", 0)), int(ops[i].get("b", 0))])


## `verdicts()` with EVERY shortcut forced off: each op goes through the real leave-one-out
## fold. A disabled op still pushes nothing, so `_build_stack` handles it — the point is that
## no verdict here is asserted, every one is folded.
func _verdicts_unshortcut(ops: Array, profile: Dictionary) -> Array:
	var out: Array = []
	for i in range(ops.size()):
		out.append(SpacerVerdictsClass.is_spacer_by_fold(ops, i, profile))
	return out


## The op stream one palette channel_name presents, mirroring `palette_verdicts`.
func _palette_ops(ed, channel_name: String) -> Array:
	var offsets: Dictionary = Lowering.stream_offsets(ed)
	var ops: Array = []
	for phase in EffectPhaseClass.ALL:
		var ch = ed.palette.get_channel(phase, channel_name)
		if ch == null or ch.keyframes.is_empty():
			continue
		var offset := int(offsets.get(phase, 0))
		var start := 0
		var last_idx: int = mini(ch.keyframes.size(), maxi(0, ch.max_keyframe - 1))
		for i in range(last_idx):
			var kf = ch.keyframes[i]
			ops.append({"enabled": kf.enabled, "at": offset + start,
				"mode": int(kf.blend_mode), "r": int(kf.rgb.x), "g": int(kf.rgb.y),
				"b": int(kf.rgb.z), "time": int(kf.time_value)})
			start += maxi(1, kf.duration_frames)
	return ops


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
