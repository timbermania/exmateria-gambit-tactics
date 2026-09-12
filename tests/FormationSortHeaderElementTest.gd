extends Node3D
# test-kind: logic
# seeded-break: _build_sort_header registers the element with declared clip OWN_APERTURE instead of UNCLIPPED — the 'header clip answer must be UNCLIPPED (declared)' assert reds; the golden position multiset (positions are transform, not clip), element identity + id, grab-the-header move, and the formation.sort_header.origin knob + scrub-moves-the-whole-header asserts stay green

## ADR-0088 migration guard: the roster SORT HEADER (tan bar chrome + six label glyphs
## + L2/R2 buttons, §12.3.3/.5) is housed in the registered element
## `formation.sort_header` — a screen-anchored assembly (children mount at absolute
## display px), UNCLIPPED as its declared answer (top-of-screen chrome, never scissored).
##   A. REGRESSION — golden position multiset of the header subtree (pre-migration).
##   B. IDENTITY — the header root IS the registered element.
##   C. CAPABILITY — moving the element moves chrome + labels + buttons together.
##
## Run: <GODOT> --path . --quit-after 30 res://tests/FormationSortHeaderElementTest.tscn

const FormationDetailTransition = preload("res://src/ui3/formation/FormationDetailTransition.gd")

## Captured 2026-08-11 from the pre-migration build (this guard's print aid): the
## host-booted roster's settled header, sorted multiset of all header mesh positions.
const GOLDEN := [
	"1.6000,-0.8800,1.7100", "2.0000,-0.9000,2.2800", "2.0000,-0.8800,1.9000", "2.2800,-0.9000,2.4700",
	"2.4000,-0.8800,2.0900", "3.0200,-0.9000,2.0900", "3.7800,-0.9000,2.0900", "4.5600,-0.8800,2.0900",
	"5.1200,-0.8800,1.7100", "5.3400,-0.8800,2.0900", "5.9400,-0.9000,2.0900", "6.7000,-0.8800,2.0900",
	"6.9000,-0.9800,2.0900", "7.2000,-0.8800,2.0900", "7.8400,-0.8800,1.7100", "8.0800,-0.9000,2.2800",
	"8.2400,-0.8800,1.9000", "8.2800,-0.9000,2.4700", "8.4800,-0.9000,2.6600", "8.6400,-0.8800,2.0900",
]

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
	for _i in 4:
		await get_tree().process_frame

	var form = host._formation
	_expect(form != null, "no formation scene (host boot failed)")
	var hdr := form.find_child("SortHeader", true, false) as Node3D if form != null else null
	_expect(hdr != null, "SortHeader node missing")
	if hdr != null:
		# --- A. regression -------------------------------------------------------
		var observed := _collect_positions(hdr)
		var golden := _parse_golden()
		_expect(observed.size() == golden.size(),
			"header quad count drifted: observed %d vs golden %d" % [observed.size(), golden.size()])
		if observed.size() == golden.size():
			var worst := 0.0
			for i in observed.size():
				worst = maxf(worst, (observed[i] - golden[i]).length())
			_expect(worst < 0.001, "header content drifted from golden (worst %.4f)" % worst)
		if _failed > 0:
			print("[FormationSortHeaderElementTest] observed multiset (GOLDEN format):")
			var line := ""
			for i in observed.size():
				line += "\"%.4f,%.4f,%.4f\", " % [observed[i].x, observed[i].y, observed[i].z]
				if (i + 1) % 4 == 0 or i == observed.size() - 1:
					print("\t" + line.strip_edges())
					line = ""

		# --- B. identity ---------------------------------------------------------
		_expect(hdr is UI3Element, "SortHeader is not a registered UI3Element")
		if hdr is UI3Element:
			_expect((hdr as UI3Element).id() == "formation.sort_header",
				"element id %s != formation.sort_header" % (hdr as UI3Element).id())
			_expect((hdr as UI3Element).clip_mode() == UI3Element.Clip.UNCLIPPED,
				"header clip answer must be UNCLIPPED (declared)")

		# --- C. capability -------------------------------------------------------
		var before := _collect_positions(hdr)
		var delta := Vector3(1.234, -0.567, 0.0)
		hdr.position += delta
		var after := _collect_positions(hdr)
		var ok := after.size() == before.size() and before.size() > 0
		if ok:
			for i in before.size():
				if ((after[i] - before[i]) - delta).length() >= 0.001:
					ok = false
					break
		_expect(ok, "header content did not ride the element move")
		hdr.position -= delta

		# --- D. group-nudge origin knob (Amendment 4 §1 Option C) — the whole header
		# is draggable as a unit via the editable formation.sort_header.origin slug.
		_expect(Tune.is_registered("formation.sort_header.origin"),
			"the sort header must mint an editable formation.sort_header.origin knob")
		var pre := _collect_positions(hdr)
		Tune.set_value("formation.sort_header.origin", Vector2(10, 6))
		var post := _collect_positions(hdr)
		var moved := post.size() == pre.size() and pre.size() > 0
		var expect_delta := Vector3(10.0 * 0.04, -6.0 * 0.04, 0.0)
		if moved:
			for i in pre.size():
				if ((post[i] - pre[i]) - expect_delta).length() >= 0.001:
					moved = false
					break
		_expect(moved, "scrubbing the origin knob must move the WHOLE header by screen_to_world(px)")
		Tune.clear("formation.sort_header.origin")

	print("\n=== FormationSortHeaderElementTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] FormationSortHeaderElementTest")
		get_tree().quit(1)
	else:
		print("[PASS] FormationSortHeaderElementTest: formation.sort_header registered element (golden no-op + identity + grab)")
		get_tree().quit(0)


func _collect_positions(root: Node) -> Array:
	var out: Array = []
	if root != null and is_instance_valid(root):
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
		push_error("[FormationSortHeaderElementTest] %s" % msg)
		print("  [x] " + msg)
