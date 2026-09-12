extends Node3D
# test-kind: logic
# seeded-break: UIUnitNameplate.set_view drops the immediate detach (remove_child) before the deferred queue_free — the ADR-0180 double-bind-in-one-frame state; re-binding the docked pair now leaves both nameplate roots in the tree, so 'binding the docked pair twice in one frame doubled its mesh tree' reds (69 then 99); the 69-mesh re-based golden + bound-unit identity + mesh-count + the cluster/vitals/nameplate identity and parent-element tree asserts stay green

## Guard (ADR-0088 Amendment 5 §4): the FORMATION roster's docked vitals+nameplate group is a
## registered ELEMENT tree — `formation.unit_cluster` (screen-anchored ELEMENT root) with
## `.vitals` + `.nameplate` sub-elements. Independent per-screen instance (NO reparenting): the
## detail screen builds its own; ○-press hides this one.
##   A. GOLDEN — visual no-op: the cluster's rendered mesh multiset is byte-identical to the
##      pre-migration build.
##   B. IDENTITY — cluster + vitals + nameplate are registered ELEMENTs with formation.* ids.
##   C. TREE — vitals + nameplate resolve the cluster as their parent_element.
##
## Run: <GODOT> --path . --quit-after 30 res://tests/FormationUnitClusterElementTest.tscn

const FormationDetailTransition = preload("res://src/ui3/formation/FormationDetailTransition.gd")

## RE-CAPTURED 2026-08-25, and the re-capture is a finding.
##
## The 2026-08-12 golden was taken "from the default roster selection" — which, measured, was
## `PartyRoster`'s `party:0`, a hand-invented blank Squire called **"Marcus"**. This host injects
## its real roster a frame AFTER `add_child`, so `_build_unit_info_cluster` bound the
## self-discovery fallback and nothing ever rebound it. The golden was pinning the exact defect
## ADR-0180 was written about. Six of the 69 meshes below are the difference between rendering
## "Marcus" (6 glyphs) and rendering the unit this screen is actually showing.
##
## So this is a RE-BASE, not a no-op proof any more: it still locks the cluster's rendered mesh
## multiset against future drift, but it can no longer claim byte-identity with the pre-migration
## build, because the pre-migration build was drawing the wrong unit.
##
## COUPLED to the template store. The bound unit comes from `PromotedRosterSeeder`, which promotes
## `AllTemplatesSeeder` rows out of `assets/characters/templates/`. A worktree without that store
## seeds something else and this golden drifts — which is why the predecessor could not re-capture
## it here. `_test_bound_unit_identity` below names that dependency so the failure says WHY.
##
## [b]This test now seeds its OWN fixture, and that is a fix rather than a cost.[/b] It used to
## inherit whatever `FormationDetailTransition._resolve_roster()` seeded; ADR-0181 emptied that
## function down to `CharacterCatalog.owned_units()` and moved the fixture into
## [FormationDevBoot], because the seeding opened with a destructive `reset_to_new_game()` that
## would have wiped a real host's owned overlay. A golden about the CLUSTER'S RENDERED MESHES has
## no business inheriting its cast from the production path — pinning the input beside the output
## is what keeps the golden a statement about drawing rather than about roster policy. It is also
## why the golden did NOT have to be re-captured for ADR-0181: same fixture, same 69 meshes.
const GOLDEN: Array = [
	"1.2800,-8.1600,2.0900", "1.3200,-8.2000,1.9900", "2.0800,-8.8800,2.1900",
	"2.0800,-8.4600,2.1900", "2.0800,-8.0200,2.1900", "2.8000,-7.4000,2.1900",
	"3.0000,-8.9600,2.0900", "3.0000,-8.9600,2.1400", "3.0000,-8.5200,2.0900",
	"3.0000,-8.5200,2.1400", "3.0000,-8.1900,1.9400", "3.0000,-8.0800,2.0900",
	"3.0000,-8.0800,2.1400", "3.2200,-7.4400,2.1900", "3.4200,-7.4400,2.1900",
	"3.7600,-8.9000,2.1900", "3.7600,-8.4800,2.1900", "3.7600,-8.0400,2.1900",
	"3.9600,-8.9000,2.1900", "3.9600,-8.4800,2.1900", "3.9600,-8.0400,2.1900",
	"3.9600,-7.4400,2.1900", "4.1600,-8.9000,2.1900", "4.1600,-8.4800,2.1900",
	"4.1600,-8.0400,2.1900", "4.3600,-8.9800,2.1900", "4.3600,-8.5600,2.1900",
	"4.3600,-8.1200,2.1900", "4.4200,-7.4400,2.1900", "4.5600,-9.0600,2.1900",
	"4.5600,-8.6400,2.1900", "4.5600,-8.2000,2.1900", "4.6200,-7.4400,2.1900",
	"4.7600,-9.0600,2.1900", "4.7600,-8.6400,2.1900", "4.7600,-8.2000,2.1900",
	"4.9600,-9.0600,2.1900", "4.9600,-8.6400,2.1900", "4.9600,-8.2000,2.1900",
	"5.6800,-7.4000,2.4700", "5.6800,-7.4000,2.4700", "6.0000,-7.4400,2.6600",
	"6.0400,-8.6000,2.4700", "6.2000,-7.4400,2.6600", "6.5200,-8.1600,2.6600",
	"6.5200,-7.5200,2.6600", "6.7600,-8.1600,2.6600", "6.7600,-7.5200,2.6600",
	"6.9200,-8.1600,2.6600", "6.9400,-8.7800,2.6600", "7.0800,-8.1600,2.6600",
	"7.1600,-8.1600,2.6600", "7.1600,-7.5200,2.6600", "7.3200,-8.1600,2.6600",
	"7.3200,-7.5200,2.6600", "7.4800,-7.5200,2.6600", "7.6400,-8.7600,2.6600",
	"7.6400,-8.1200,2.2800", "7.6400,-7.5200,2.6600", "7.8400,-8.7600,2.6600",
	"7.9600,-7.5200,2.6600", "8.1200,-7.5200,2.6600", "8.2000,-7.5200,2.6600",
	"8.5200,-7.5200,2.6600", "8.6000,-8.7800,2.6600", "8.7600,-7.5200,2.6600",
	"8.9200,-7.5200,2.6600", "9.2000,-8.7600,2.6600", "9.4000,-8.7600,2.6600",
]

## The unit the GOLDEN above was captured with bound — `PromotedRosterSeeder`'s first row,
## a template-store identity. Its NAME LENGTH is load-bearing: the nameplate mounts one mesh
## per glyph, so a different first row moves the mesh multiset legitimately.
const BOUND_UNIT_NAME := "10 year old man"

var _passed := 0
var _failed := 0


func _ready() -> void:
	# ADR-0181: the host no longer seeds — it reads `CharacterCatalog.owned_units()`, so the
	# fixture this test was implicitly getting is now stated here. Same seeder, same units,
	# so every golden below is unmoved; what changed is that the input is written down.
	# It sits at the top of `_ready` rather than beside a `.new()` because a file can hold
	# more than one host factory, and whichever runs FIRST must already find a roster.
	CharacterCatalog.reset_to_new_game()
	PromotedRosterSeeder.seed()
	var host: FormationDetailTransition = FormationDetailTransition.new()
	host.name = "Host"
	add_child(host)
	for _i in 6:
		await get_tree().process_frame

	var form = host._formation
	_expect(form != null, "no formation scene (host boot failed)")
	var cluster = form.find_child("UnitInfoCluster", true, false) if form != null else null
	_expect(cluster != null, "UnitInfoCluster missing on the formation roster")
	if cluster != null:
		# --- A. golden (visual no-op) --------------------------------------------
		var observed := _collect_positions(cluster)
		if GOLDEN.is_empty():
			print("[FormationUnitClusterElementTest] CAPTURE — %d mesh positions:" % observed.size())
			for v: Vector3 in observed:
				print("\t\"%.4f,%.4f,%.4f\"," % [v.x, v.y, v.z])
		else:
			var golden := _parse_golden()
			# WHICH unit the golden was captured against. A mesh-count drift is opaque; a
			# named cause is not. If the seeder's first row changes — or the template store
			# is missing, so it seeds something else entirely — this fails FIRST and says so.
			var bound: Array = form._roster_characters()
			_expect(bound.size() > 0, "the host must have injected a roster before the golden")
			if bound.size() > 0:
				_expect(str(bound[0].display_name) == BOUND_UNIT_NAME,
					"the golden was captured with %s bound; the seeder now gives %s — re-capture"
						% [BOUND_UNIT_NAME, str(bound[0].display_name)])
			_expect(observed.size() == golden.size(),
				"cluster mesh count drifted: observed %d vs golden %d" % [observed.size(), golden.size()])
			# D. IDEMPOTENT RE-BIND — ADR-0180 rebinds the docked pair from `rebuild_cells`,
			# so this pair IS bound more than once, and can be bound twice in ONE frame (the
			# build-time bind, then again the moment an injected roster arrives). The nameplate
			# REBUILDS on every bind and frees its old root with `queue_free`, which is
			# DEFERRED — so without an immediate detach both roots stay in the tree for the
			# rest of the frame and everything that walks this subtree sees a doubled mesh
			# tree. Confirmed RED against `UIUnitNameplate.set_view` without its `remove_child`.
			form._update_vitals_for_selection()
			var rebound := _collect_positions(cluster)
			_expect(rebound.size() == observed.size(),
				"binding the docked pair twice in one frame doubled its mesh tree: %d then %d"
					% [observed.size(), rebound.size()])

			if observed.size() == golden.size():
				var worst := 0.0
				for i in observed.size():
					worst = maxf(worst, (observed[i] - golden[i]).length())
				_expect(worst < 0.001, "cluster drifted from golden (worst %.4f)" % worst)

		# --- B/C. identity + tree ------------------------------------------------
		_expect(cluster is UI3Element, "cluster is not a UI3Element")
		if cluster is UI3Element:
			var ce := cluster as UI3Element
			_expect(ce.id() == "formation.unit_cluster", "cluster id %s != formation.unit_cluster" % ce.id())
			_expect(ce.role() == UI3Element.Role.ELEMENT, "cluster must be Role.ELEMENT")

		var vitals = form.find_child("VitalsPanel", true, false)
		var np_elem := _find_element_by_id(form, "formation.unit_cluster.nameplate")
		_expect(vitals is UI3Element and (vitals as UI3Element).role() == UI3Element.Role.ELEMENT,
			"vitals panel must be a Role.ELEMENT")
		if vitals is UI3Element:
			_expect((vitals as UI3Element).id() == "formation.unit_cluster.vitals",
				"vitals id %s != formation.unit_cluster.vitals" % (vitals as UI3Element).id())
			_expect((vitals as UI3Element).parent_element() == cluster,
				"vitals parent_element must be the cluster")
		_expect(np_elem != null, "nameplate element (formation.unit_cluster.nameplate) missing")
		if np_elem != null:
			_expect(np_elem.parent_element() == cluster, "nameplate parent_element must be the cluster")

	print("\n=== FormationUnitClusterElementTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] FormationUnitClusterElementTest")
		get_tree().quit(1)
	else:
		print("[PASS] FormationUnitClusterElementTest: formation.unit_cluster ELEMENT tree"
			+ " (re-based golden + bound-unit identity + idempotent re-bind + ELEMENT tree)")
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
		push_error("[FormationUnitClusterElementTest] %s" % msg)
		print("  [x] " + msg)
