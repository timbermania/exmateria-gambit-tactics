extends Node3D

## Guard (ADR-0088 Amendment 5 §4): the Status-screen vitals+nameplate group is now a
## registered ELEMENT tree — `detail.unit_cluster` (a screen-anchored ELEMENT root owning the
## group slide + an <id>.origin group-nudge), with `.vitals` (UIUnitInfoWindow, ELEMENT via
## the base-swap) and `.nameplate` (UIUnitNameplate, bespoke ELEMENT re-base) as child
## sub-elements. Payload (HP/MP/CT bars, portrait, glyphs) stays PAYLOAD.
##   A. GOLDEN — the whole change is a visual no-op: the cluster's rendered mesh multiset is
##      byte-identical to the pre-migration build (ELEMENT bind defaults == retired consts).
##   B. IDENTITY — cluster + vitals + nameplate are registered ELEMENTs with the right ids.
##   C. TREE — vitals + nameplate resolve the cluster as their parent_element.
##
## Run: <GODOT> --path . --quit-after 20 res://tests/DetailUnitClusterElementTest.tscn

const DetailScene = preload("res://src/ui3/detail/DetailScene.gd")

const _UNIT_VIEW := {
	"name": "Ramza", "job": "Squire", "level": 5, "exp": 40,
	"sprite_id": "", "template_folder": "",
	"current_hp": 120, "max_hp": 120, "current_mp": 30, "max_mp": 30,
	"ct": 0, "has_ct": false, "brave": 70, "faith": 65, "statuses": [],
}
const _NAMEPLATE_VIEW := {"number": 1, "name": "Ramza", "job": "Squire", "brave": 70, "faith": 65, "zodiac": 0}

## Captured 2026-08-12 from the pre-migration build (Ramza/Squire fixture above).
##
## ONE entry has been edited since, and deliberately: `vitals.portrait_offset` was dialed to
## (2, 2) and materialized, which slides the PORTRAIT one virtual px right and down inside its
## frame. MEASURED as a multiset diff against this list rather than re-captured wholesale —
## 61 of the 62 meshes did not move, and the one that did moved by exactly (+0.04, -0.04, 0),
## which is that 1px at this cluster's ppu (1.2800,-2.3600 -> 1.3200,-2.4000, z unchanged).
##
## Re-capturing all 62 would have been the wrong repair. Arm A's claim is that the ELEMENT
## migration was a VISUAL NO-OP against the PRE-migration build, and a wholesale re-capture
## retargets it at the current build, where it can only ever compare the tree to itself. The
## 61 untouched rows are still the pre-migration evidence; this row is an intentional layout
## change with its delta recorded, which is a different thing from drift.
const GOLDEN: Array = [
	"1.3200,-2.4000,2.2800", "1.3200,-2.4000,2.1800", "2.0800,-3.0800,2.3800",
	"2.0800,-2.6600,2.3800", "2.0800,-2.2200,2.3800", "2.8000,-1.6000,2.3800",
	"3.0000,-3.1600,2.2800", "3.0000,-3.1600,2.3300", "3.0000,-2.7200,2.2800",
	"3.0000,-2.7200,2.3300", "3.0000,-2.3900,2.1300", "3.0000,-2.2800,2.2800",
	"3.0000,-2.2800,2.3300", "3.2200,-1.6400,2.3800", "3.4200,-1.6400,2.3800",
	"3.7600,-3.1000,2.3800", "3.7600,-2.6800,2.3800", "3.7600,-2.2400,2.3800",
	"3.9600,-3.1000,2.3800", "3.9600,-2.6800,2.3800", "3.9600,-2.2400,2.3800",
	"3.9600,-1.6400,2.3800", "4.1600,-3.1000,2.3800", "4.1600,-2.6800,2.3800",
	"4.1600,-2.2400,2.3800", "4.3600,-3.1800,2.3800", "4.3600,-2.7600,2.3800",
	"4.3600,-2.3200,2.3800", "4.4200,-1.6400,2.3800", "4.5600,-3.2600,2.3800",
	"4.5600,-2.8400,2.3800", "4.5600,-2.4000,2.3800", "4.6200,-1.6400,2.3800",
	"4.7600,-3.2600,2.3800", "4.7600,-2.8400,2.3800", "4.7600,-2.4000,2.3800",
	"4.9600,-3.2600,2.3800", "4.9600,-2.8400,2.3800", "4.9600,-2.4000,2.3800",
	"5.5200,-1.6400,2.4700", "5.5200,-1.6400,2.4700", "5.8400,-1.6800,2.6600",
	"5.8800,-2.8400,2.4700", "6.0400,-1.6800,2.6600", "6.3600,-2.4000,2.6600",
	"6.3600,-1.7600,2.6600", "6.6000,-2.4000,2.6600", "6.6000,-1.7600,2.6600",
	"6.7600,-2.4000,2.6600", "6.7600,-1.7600,2.6600", "6.7800,-3.0200,2.6600",
	"6.9200,-2.4000,2.6600", "7.0000,-2.4000,2.6600", "7.0000,-1.7600,2.6600",
	"7.1600,-2.4000,2.6600", "7.1600,-1.7600,2.6600", "7.4800,-3.0000,2.6600",
	"7.4800,-2.3600,2.2800", "7.6800,-3.0000,2.6600", "8.4400,-3.0200,2.6600",
	"9.0400,-3.0000,2.6600", "9.2400,-3.0000,2.6600",
]

var _passed := 0
var _failed := 0


func _ready() -> void:
	var d: DetailScene = DetailScene.new()
	d.autoplay_open = false
	d.set_unit_view(_UNIT_VIEW)
	d.set_nameplate_view(_NAMEPLATE_VIEW)
	add_child(d)
	d.set_stats_view(_UNIT_VIEW)
	for _i in 4:
		await get_tree().process_frame

	var cluster := d.find_child("UnitInfoCluster", true, false)
	_expect(cluster != null, "UnitInfoCluster missing")
	if cluster != null:
		# --- A. golden (visual no-op) --------------------------------------------
		var observed := _collect_positions(cluster)
		if GOLDEN.is_empty():
			print("[DetailUnitClusterElementTest] CAPTURE — %d mesh positions:" % observed.size())
			for v: Vector3 in observed:
				print("\t\"%.4f,%.4f,%.4f\"," % [v.x, v.y, v.z])
		else:
			var golden := _parse_golden()
			_expect(observed.size() == golden.size(),
				"cluster mesh count drifted: observed %d vs golden %d" % [observed.size(), golden.size()])
			if observed.size() == golden.size():
				var worst := 0.0
				for i in observed.size():
					worst = maxf(worst, (observed[i] - golden[i]).length())
				_expect(worst < 0.001, "cluster drifted from golden (worst %.4f)" % worst)

		# --- B. identity ---------------------------------------------------------
		_expect(cluster is UI3Element, "cluster is not a UI3Element")
		if cluster is UI3Element:
			var ce := cluster as UI3Element
			_expect(ce.id() == "detail.unit_cluster", "cluster id %s != detail.unit_cluster" % ce.id())
			_expect(ce.role() == UI3Element.Role.ELEMENT, "cluster must be Role.ELEMENT")
			_expect(ce.parent_element() == null, "cluster is a root (the screen is not an element)")

		var vitals := d.find_child("VitalsPanel", true, false)
		var nameplate := d.find_child("Nameplate", true, false)
		# Nameplate: the widget node (UIUnitNameplate) is the element; its inner glyph tree is
		# ALSO named "Nameplate" — find the UI3Element one.
		var np_elem := _find_element_by_id(d, "detail.unit_cluster.nameplate")
		_expect(vitals is UI3Element and (vitals as UI3Element).role() == UI3Element.Role.ELEMENT,
			"vitals panel must be a Role.ELEMENT")
		if vitals is UI3Element:
			_expect((vitals as UI3Element).id() == "detail.unit_cluster.vitals",
				"vitals id %s != detail.unit_cluster.vitals" % (vitals as UI3Element).id())
			_expect((vitals as UI3Element).parent_element() == cluster,
				"vitals parent_element must be the cluster")
		_expect(np_elem != null, "nameplate element (detail.unit_cluster.nameplate) missing")
		if np_elem != null:
			_expect(np_elem.role() == UI3Element.Role.ELEMENT, "nameplate must be a Role.ELEMENT")
			_expect(np_elem.parent_element() == cluster, "nameplate parent_element must be the cluster")

	d.queue_free()
	print("\n=== DetailUnitClusterElementTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] DetailUnitClusterElementTest")
		get_tree().quit(1)
	else:
		print("[PASS] DetailUnitClusterElementTest: detail.unit_cluster ELEMENT tree (golden no-op + identity)")
		get_tree().quit(0)


func _find_element_by_id(root: Node, id: String) -> UI3Element:
	if root is UI3Element and (root as UI3Element).id() == id:
		return root
	for c in root.get_children():
		var e := _find_element_by_id(c, id)
		if e != null:
			return e
	return null


func _collect_positions(root: Node) -> Array:
	var out: Array = []
	_collect(root, out)
	out.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		if not is_equal_approx(a.x, b.x): return a.x < b.x
		if not is_equal_approx(a.y, b.y): return a.y < b.y
		return a.z < b.z)
	return out


func _collect(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append((n as MeshInstance3D).global_position)
	for c in n.get_children():
		_collect(c, out)


func _parse_golden() -> Array:
	var out: Array = []
	for s: String in GOLDEN:
		var p := s.split(",")
		out.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
	out.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		if not is_equal_approx(a.x, b.x): return a.x < b.x
		if not is_equal_approx(a.y, b.y): return a.y < b.y
		return a.z < b.z)
	return out


func _expect(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		push_error("[DetailUnitClusterElementTest] %s" % msg)
		print("  [x] " + msg)
