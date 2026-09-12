extends Node
## PARITY guard for `EffectScoreModel`'s palette VERDICT REUSE against the shipped corpus.
##
## `rebuild_kind_lanes` (the live-drag reproject) now reuses a channel's spacer verdicts
## straight out of the previous score when the live channel still presents an identical op
## stream, instead of re-running the disable-equivalence fold. That fold is the studio's most
## expensive computation by an order of magnitude — measured on E317, a palette reproject cost
## 74ms pristine and 143ms once a fine Move had laid its padding down, which is 7fps mid-drag
## against camera's 0.9ms — and a Move touches ONE channel, so the rest of them were being
## re-folded for nothing.
##
## The risk it introduces is a STALE VERDICT: a lane painting yesterday's answer, which would
## hide a tint that should draw (or draw a spacer that should not) and, because
## `PaletteChannel._hold_flags` asks the same question, would also let `ColourMovePlan` trade
## frames it does not own. So the reuse is held to the honest answer here, over real data and
## across a real STRUCTURAL edit — the case it exists for and the case that renumbers the lane.
##
## Slow by design. NOT part of the fast net — run it directly:
##   <GODOT> --path . res://tests/ScoreReprojectReuseParityTest.tscn

const EffectDataClass = ExMateriaEffects.EffectData
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const PaletteChannelClass = preload("res://src/effects/studio/PaletteChannel.gd")
const Session = preload("res://src/effects/studio/EffectEditSession.gd")
const PaletteDataClass = ExMateriaEffects.PaletteData
const EffectPhaseClass = ExMateriaEffects.EffectPhase
const Lowering = preload("res://src/effects/studio/ColorLowering.gd")

const EFFECTS_DIR := "res://assets/effects"
const SAMPLE_EVERY := 8

var _passed: int = 0
var _failed: int = 0
var _effects: int = 0
var _reprojects: int = 0
var _after_edit: int = 0
var _mismatch: Array = []


func _ready() -> void:
	var dirs := _effect_dirs()
	for k in range(0, dirs.size(), SAMPLE_EVERY):
		var ed = EffectDataClass.load_from_directory(dirs[k])
		if ed == null or ed.palette == null:
			continue
		_effects += 1
		var score: Dictionary = Model.build(ed)

		# 1. NOTHING changed — every channel reuses. The reproject must still equal the build.
		_compare(score, ed, dirs[k], "pristine")

		# 2. A real STRUCTURAL edit on one channel: the edited channel must re-fold, the others
		#    must reuse, and the whole thing must equal an honest full build of the new state.
		for phase in EffectPhaseClass.ALL:
			for cname in PaletteDataClass.ALL_CHANNELS:
				var ch = ed.palette.get_channel(phase, cname)
				if ch == null or ch.keyframes.is_empty():
					continue
				var n := _first_movable(ed, phase, cname)
				if n < 0:
					continue
				var ref := {"channel": "palette", "context": phase,
					"channel_name": cname, "event_index": n}
				var snap: Dictionary = PaletteChannelClass.snapshot(ed, ref)
				if Session.new(ed).move_span(ref, -3).is_empty():
					PaletteChannelClass.restore(ed, snap)
					continue
				_after_edit += 1
				# `score` is the PRE-edit score — exactly what a live drag hands the reproject.
				_compare(score, ed, dirs[k], "after a -3 Move on %s/%s" % [phase, cname])
				PaletteChannelClass.restore(ed, snap)
				break

	print("[reuse] %d effects, %d reprojects compared (%d of them across a structural edit)"
		% [_effects, _reprojects, _after_edit])
	_assert_true(_effects > 40, "the corpus sample actually loaded (%d effects)" % _effects)
	_assert_true(_after_edit > 20,
		"the sweep found real structural edits to reproject across (%d)" % _after_edit)
	_assert_eq(_mismatch.size(), 0,
		"every reprojected palette lane equals an honest full build (first 5: %s)"
			% str(_mismatch.slice(0, 5)))

	print("\n=== ScoreReprojectReuseParityTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ScoreReprojectReuseParityTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScoreReprojectReuseParityTest")
		get_tree().quit(0)


## The reprojected palette lanes must match a from-scratch build of the CURRENT data, span for
## span — id, frames, colour and every field, `spacer` above all.
func _compare(old_score: Dictionary, ed, dir: String, what: String) -> void:
	_reprojects += 1
	var cheap_score: Dictionary = Model.rebuild_kind_lanes(old_score, ed, "palette")
	var honest_score: Dictionary = Model.build(ed)
	# THE AXIS, before the lanes. A reproject that agrees span-for-span can still hand the
	# timeline a different ruler, and then every lane in the score is drawn at the wrong scale
	# — which is what the two builders' forked `max_frame` loops did on every drag of an effect
	# carrying a distant sound terminator (E317: 112 → 691).
	if int(cheap_score.get("max_frame", -1)) != int(honest_score.get("max_frame", -2)):
		_note("%s %s: reproject max_frame %d, honest build %d"
			% [dir.get_file(), what, int(cheap_score.get("max_frame", -1)),
				int(honest_score.get("max_frame", -2))])
		return
	var cheap: Array = _palette_lanes(cheap_score)
	var honest: Array = _palette_lanes(honest_score)
	if cheap.size() != honest.size():
		_note("%s %s: %d palette lanes, honest build has %d"
			% [dir.get_file(), what, cheap.size(), honest.size()])
		return
	for li in range(cheap.size()):
		var a: Dictionary = cheap[li]
		var b: Dictionary = honest[li]
		if String(a.get("id", "")) != String(b.get("id", "")):
			_note("%s %s: lane %d is %s, honest build says %s"
				% [dir.get_file(), what, li, str(a.get("id")), str(b.get("id"))])
			return
		var sa: Array = a.get("spans", [])
		var sb: Array = b.get("spans", [])
		if sa.size() != sb.size():
			_note("%s %s: %s has %d spans, honest build has %d"
				% [dir.get_file(), what, str(a.get("id")), sa.size(), sb.size()])
			return
		for si in range(sa.size()):
			if sa[si] != sb[si]:
				_note("%s %s: %s span %d differs (spacer %s vs %s)"
					% [dir.get_file(), what, str(a.get("id")), si,
						str(sa[si].get("fields", {}).get("spacer")),
						str(sb[si].get("fields", {}).get("spacer"))])
				return


func _note(msg: String) -> void:
	if _mismatch.size() < 20:
		_mismatch.append(msg)


## The first played keyframe on this channel a Move can actually address (not a hold).
func _first_movable(ed, phase: String, cname: String) -> int:
	var ref := {"channel": "palette", "context": phase, "channel_name": cname,
		"event_index": 0}
	var ctx: Dictionary = PaletteChannelClass.move_context(ed, ref)
	if ctx.is_empty():
		return -1
	var holds: Array = ctx["holds"]
	for i in range(holds.size()):
		if not bool(holds[i]):
			return i
	return -1


func _palette_lanes(score: Dictionary) -> Array:
	var out: Array = []
	for lane in score.get("lanes", []):
		if String(lane.get("kind", "")) == "palette":
			out.append(lane)
	return out


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
