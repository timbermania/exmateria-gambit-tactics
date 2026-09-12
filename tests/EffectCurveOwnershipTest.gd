extends Node
## TDD guard for the ADR-0089 **curve-ownership amendment**: a curve belongs to its
## USE SITE — an `(emitter, slot)` pair, where slot is a param name or one of colour
## r/g/b — and the shared, indexed, ≤15 table is an EXPORT format, not an authoring
## model.
##
## The headline property is PRIVACY: painting one use site's curve moves nothing
## else. It failed before the explode because the ROM shares curve slots as a matter
## of course, not as a tail case — 70.8% of corpus curve slots have more than one
## referrer, and E009's slot 0 is ridden by 30 use sites, so editing any one of them
## restyled 29 emitters the author was not looking at.
##
## The explode is what makes privacy STRUCTURAL rather than a rule a write path could
## forget: at load every use site gets its own copy at its own new index, so there is
## no shared slot left to accidentally mutate. The read path is unchanged — a use site
## still resolves by index through `EffectData.get_curve` — which is what keeps all 29
## `get_curve()` call sites untouched, and is the second property tested here.
##
## Run: <GODOT> --path . --quit-after 20 res://tests/EffectCurveOwnershipTest.tscn

const EffectCurve = ExMateriaEffects.EffectCurve

const EffectDataClass = ExMateriaEffects.EffectData
const CurvePaintModel = preload("res://src/effects/studio/CurvePaintModel.gd")
const ParticlePhysicsClass = preload("res://addons/exmateria_effects/particles/ParticlePhysics.gd")

## E009 is the corpus's worst sharer: curve slot 0 carries 30 referrers (every colour
## channel of 10 emitters), slot 1 carries 3, slot 2 exactly 1. 15 slots on disk, 3 of
## them referenced — so it exercises privacy, provenance AND residue in one effect.
const SHARER := "res://assets/effects/E009"
## E509/E510 are the corpus's only broken references: 7 emitters apiece pointing at
## curve slots in a curves.json with ZERO entries (60 dangling refs across the two).
## They resolve to null today and must keep resolving to null after the explode.
const DANGLER := "res://assets/effects/E509"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_explode_gives_every_use_site_its_own_index()
	_test_read_path_is_unchanged_by_the_explode()
	_test_painting_one_use_site_moves_nothing_else()
	_test_provenance_names_the_origin_slot()
	_test_unreferenced_slots_become_residue()
	_test_a_dangling_reference_still_resolves_to_no_curve()
	_test_the_all_zero_curve_is_an_exact_no_op()
	_test_a_committed_stroke_undoes_exactly()

	print("\n=== EffectCurveOwnershipTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectCurveOwnershipTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectCurveOwnershipTest")
		get_tree().quit(0)


# --- the amendment's properties -------------------------------------------

## Decision 2: after load, no two use sites share an index. Privacy is structural.
func _test_explode_gives_every_use_site_its_own_index() -> void:
	var data = EffectDataClass.load_from_directory(SHARER)
	var sites := _use_sites(data)
	_assert_true(sites.size() >= 30, "E009 has 30+ use sites (got %d)" % sites.size())
	var seen := {}
	var shared: Array = []
	for s in sites:
		var idx: int = int(s["index"])
		if seen.has(idx):
			shared.append("%s vs %s (index %d)" % [s["label"], seen[idx], idx])
		seen[idx] = s["label"]
	_assert_eq(shared.size(), 0, "no two use sites share an index — %s" % str(shared.slice(0, 3)))


## Decision 2: "the array grows; the read path does not change." Every use site still
## resolves to a curve carrying the samples its ORIGINAL slot carried, so nothing that
## reads through `get_curve` needs to know the explode happened.
func _test_read_path_is_unchanged_by_the_explode() -> void:
	var data = EffectDataClass.load_from_directory(SHARER)
	var disk := _disk_curves(SHARER)
	var origin := _disk_use_sites(SHARER)
	var mismatches: Array = []
	for s in _use_sites(data):
		var curve = data.get_curve(int(s["index"]))
		if curve == null:
			mismatches.append("%s resolves to null" % s["label"])
			continue
		var want: Array = disk[int(origin[s["label"]])]
		if not _same_samples(curve.samples, want):
			mismatches.append("%s reads different samples than its slot" % s["label"])
	_assert_eq(mismatches.size(), 0,
		"every use site reads its original slot's samples — %s" % str(mismatches.slice(0, 3)))


## THE headline. Painting one use site's curve — the exact write EffectCurvePainter
## commits (CurvePaintModel.grid_to_curve onto the bound curve) — must leave every
## other use site's samples byte-identical. Before the explode, 29 of E009's colour
## channels moved with the one being painted.
func _test_painting_one_use_site_moves_nothing_else() -> void:
	var data = EffectDataClass.load_from_directory(SHARER)
	var sites := _use_sites(data)
	var target: Dictionary = sites[0]
	var before := {}
	for s in sites:
		var c = data.get_curve(int(s["index"]))
		before[s["label"]] = [] if c == null else Array(c.samples).duplicate()

	var painted = data.get_curve(int(target["index"]))
	_assert_true(painted != null, "the painted use site resolves to a curve")
	if painted == null:
		return
	var grid: Array = CurvePaintModel.curve_to_grid(painted, 255)
	CurvePaintModel.stroke_segment(grid, 0, 0, grid.size() - 1, 255, 0, 255)
	CurvePaintModel.grid_to_curve(painted, grid, 255)

	var moved: Array = []
	for s in sites:
		if s["label"] == target["label"]:
			continue
		var c = data.get_curve(int(s["index"]))
		var now: Array = [] if c == null else Array(c.samples)
		if not _same_floats(now, before[s["label"]]):
			moved.append(s["label"])
	_assert_true(not _same_floats(Array(painted.samples), before[target["label"]]),
		"the painted use site DID change (the stroke landed)")
	_assert_eq(moved.size(), 0,
		"painting %s moved %d other use sites — %s" % [target["label"], moved.size(),
			str(moved.slice(0, 4))])


## Decision 2's first safety condition: the exploded copy remembers the slot it came
## from, so the deferred compiler can restore an untouched effect's original indices
## by provenance rather than by a dedup that happens to be order-stable.
func _test_provenance_names_the_origin_slot() -> void:
	var data = EffectDataClass.load_from_directory(SHARER)
	var origin := _disk_use_sites(SHARER)
	var wrong: Array = []
	for s in _use_sites(data):
		var curve = data.get_curve(int(s["index"]))
		if curve == null or int(curve.index) != int(origin[s["label"]]):
			wrong.append("%s: provenance %s, origin slot %d" % [s["label"],
				"null" if curve == null else str(curve.index), int(origin[s["label"]])])
	_assert_eq(wrong.size(), 0, "provenance names the origin slot — %s" % str(wrong.slice(0, 3)))


## Decision 2's second safety condition: curves nothing references are RESIDUE, not
## use sites. They never enter the authoring model, but they are carried aside so a
## byte-exact export doesn't silently drop them (E009 references 3 of its 15 slots).
func _test_unreferenced_slots_become_residue() -> void:
	var data = EffectDataClass.load_from_directory(SHARER)
	var disk := _disk_curves(SHARER)
	var referenced := {}
	for s in _disk_use_sites(SHARER).values():
		referenced[int(s)] = true
	var want: Array = []
	for i in range(disk.size()):
		if not referenced.has(i):
			want.append(i)
	var got: Array = []
	for r in data.curve_residue:
		got.append(int(r["index"]))
	got.sort()
	_assert_eq(str(got), str(want), "residue is exactly the unreferenced slots")
	for r in data.curve_residue:
		_assert_true(_same_samples(r["curve"].samples, disk[int(r["index"])]),
			"residue slot %d keeps its samples" % int(r["index"]))


## E509/E510 point 60 use sites at a curves.json with no entries. Those references
## resolve to null today (get_curve range-checks), and must STILL resolve to null
## after the explode — an exploded array that happens to be longer must not let a
## stale index start resolving to some other use site's private curve.
func _test_a_dangling_reference_still_resolves_to_no_curve() -> void:
	var data = EffectDataClass.load_from_directory(DANGLER)
	var resolving: Array = []
	for s in _use_sites(data):
		if data.get_curve(int(s["index"])) != null:
			resolving.append(s["label"])
	_assert_eq(resolving.size(), 0,
		"a dangling reference resolves to no curve — %s" % str(resolving.slice(0, 3)))


## Decision 5: adding a curve to a param that had none must change NOTHING until it
## is painted, and that is EXACT rather than approximate — no curve makes the sim hold
## the start values, and an all-zero curve lerps to min_start at every frame. (This is
## the fact ADR-0089 line 40 and the picker's `none` glyph both got wrong for months:
## there is no linear start→end ramp.)
func _test_the_all_zero_curve_is_an_exact_no_op() -> void:
	var identity = EffectCurve.from_array(_zeros(160), 0)
	var rng := RandomNumberGenerator.new()
	var mismatches: Array = []
	for frame in [0, 1, 7, 40, 159, 160, 321]:
		var without: float = ParticlePhysicsClass.interpolate_range(5.0, 5.0, 9.0, 9.0, null, frame, rng)
		var with_identity: float = ParticlePhysicsClass.interpolate_range(
			5.0, 5.0, 9.0, 9.0, identity, frame, rng)
		if not is_equal_approx(without, with_identity):
			mismatches.append("f%d: %f vs %f" % [frame, without, with_identity])
	_assert_eq(mismatches.size(), 0,
		"constant(0) is bit-identical to no curve — %s" % str(mismatches))


## A curve edit is a real, undoable edit now that curves are private. Through the choke
## point it moves ONE use site, and undo puts that use site's samples back exactly while
## still touching nothing else. (This is why the commit had to stop going through the
## painter's in-place write: the choke point must see the PRE-edit samples to snapshot
## them, which it cannot if the painter has already overwritten them.)
func _test_a_committed_stroke_undoes_exactly() -> void:
	var data = EffectDataClass.load_from_directory(SHARER)
	var sites := _use_sites(data)
	var target: Dictionary = sites[3]
	var before := {}
	for s in sites:
		var c = data.get_curve(int(s["index"]))
		before[s["label"]] = [] if c == null else Array(c.samples).duplicate()

	var session := EffectEditSession.new(data)
	var stroke: Array = []
	for i in range(160):
		stroke.append((i * 255) / 159)
	var res: Dictionary = session.apply_edit(
		{"channel": "curve", "curve_index": int(target["index"])}, stroke)
	_assert_true(not res.is_empty(), "the choke point accepted the curve edit")
	_assert_eq(Array(res.get("before_raw", [])).size(), 160,
		"…and snapshotted the whole PRE-edit curve for undo")
	_assert_eq(int(Array(res.get("before_raw", [0]))[159]),
		int(round(float(before[target["label"]][159]) * 255.0)),
		"…the snapshot is the samples as they were, not as they became")

	var painted = data.get_curve(int(target["index"]))
	_assert_true(int(round(painted.samples[159] * 255.0)) == 255, "the stroke landed")
	var moved: Array = []
	for s in sites:
		if s["label"] == target["label"]:
			continue
		var c = data.get_curve(int(s["index"]))
		if not _same_floats(Array(c.samples) if c != null else [], before[s["label"]]):
			moved.append(s["label"])
	_assert_eq(moved.size(), 0, "a committed stroke moves ONE use site — %s" % str(moved.slice(0, 3)))

	_assert_true(session.undo(), "the stroke is on the undo stack")
	var wrong: Array = []
	for s in sites:
		var c = data.get_curve(int(s["index"]))
		if not _same_floats(Array(c.samples) if c != null else [], before[s["label"]]):
			wrong.append(s["label"])
	_assert_eq(wrong.size(), 0, "undo restores every use site exactly — %s" % str(wrong.slice(0, 3)))


# --- helpers ---------------------------------------------------------------

## Every use site in the loaded effect as `{label, index}` — the (emitter, slot) pairs
## the amendment defines. Slot order is fixed (sorted params, then r/g/b) so the list
## is stable; `label` is the address the assertions name.
func _use_sites(data) -> Array:
	var out: Array = []
	for e in range(data.emitters.size()):
		var em = data.emitters[e]
		var params: Array = em.curves.keys()
		params.sort()
		for p in params:
			if int(em.curves[p]) >= 0:
				out.append({"label": "e%d.%s" % [e, p], "index": int(em.curves[p])})
		for chan in ["r", "g", "b"]:
			if int(em.color_curves.get(chan, -1)) >= 0:
				out.append({"label": "e%d.color_%s" % [e, chan],
					"index": int(em.color_curves[chan])})
	return out


## The ON-DISK use sites: label → the ORIGINAL curve slot, read straight from
## emitters.json. The oracle the explode is checked against — reading it back out of
## the loaded EffectData would only prove the explode agrees with itself.
func _disk_use_sites(dir_path: String) -> Dictionary:
	var out := {}
	var ems = _read_json(dir_path.path_join("emitters.json"))
	if not (ems is Array):
		return out
	for e in range(ems.size()):
		var em: Dictionary = ems[e]
		var curves: Dictionary = em.get("curves", {})
		var params: Array = curves.keys()
		params.sort()
		for p in params:
			if int(curves[p]) >= 0:
				out["e%d.%s" % [e, p]] = int(curves[p])
		var cc: Dictionary = em.get("color_curves", {})
		for chan in ["r", "g", "b"]:
			if int(cc.get(chan, -1)) >= 0:
				out["e%d.color_%s" % [e, chan]] = int(cc[chan])
	return out


## The ON-DISK curve table as raw 0-255 int arrays, indexed by slot.
func _disk_curves(dir_path: String) -> Array:
	var out: Array = []
	var raw = _read_json(dir_path.path_join("curves.json"))
	if not (raw is Array):
		return out
	for entry in raw:
		out.append(Array(entry.get("values", [])) if entry is Dictionary else Array(entry))
	return out


func _read_json(res_path: String):
	if not FileAccess.file_exists(res_path):
		return null
	var f := FileAccess.open(res_path, FileAccess.READ)
	if f == null:
		return null
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed


## Normalized samples vs the disk's 0-255 ints (load divides by 255).
func _same_samples(samples, disk_values: Array) -> bool:
	if samples.size() != disk_values.size():
		return false
	for i in range(disk_values.size()):
		if not is_equal_approx(float(samples[i]), float(disk_values[i]) / 255.0):
			return false
	return true


func _same_floats(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if not is_equal_approx(float(a[i]), float(b[i])):
			return false
	return true


func _zeros(n: int) -> Array:
	var a: Array = []
	a.resize(n)
	a.fill(0.0)
	return a


# --- harness ---------------------------------------------------------------

func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: %s" % msg)


func _assert_eq(got, want, msg: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: %s (got %s, want %s)" % [msg, str(got), str(want)])
