extends Node3D
# test-kind: logic
# seeded-break: shifted every trail-slot holder 8 display-px down in _update_box_trail (holder.position = screen_to_world(pos.x, pos.y + 8.0)) so the per-frame slot positioning off _box_history drifts; the 'gold box drifted from golden (worst 0.3200)' assert reds (0.32 = 8 px * 0.04 world/px), the quad-count + identity (id/UNCLIPPED) + set_box_trail_visible latch asserts stay green

## ADR-0088 migration guard: the roster GOLD SELECTION BOX trail (§11.5.3 — 8 additive
## trail slots gliding off _box_history) is housed in the registered element
## `formation.gold_box` — a screen-anchored assembly (slot holders position per-frame
## at absolute display px), UNCLIPPED as the cursor-class declared answer.
##   A. REGRESSION — golden position multiset (settled boot: slots collapsed on the head).
##   B. IDENTITY — the trail root IS the registered element (id + UNCLIPPED).
##   C. VISIBILITY LATCH — set_box_trail_visible(false) still hides the element
##      (the §15.23 RE24 Equip-screen hide is undisturbed by the migration).
##
## Run: <GODOT> --path . --quit-after 30 res://tests/FormationGoldBoxElementTest.tscn

const FormationDetailTransition = preload("res://src/ui3/formation/FormationDetailTransition.gd")

## Captured 2026-08-11 from the pre-migration build (this guard's print aid).
const GOLDEN := [
	"0.7200,-3.2400,0.3800", "0.7200,-3.2400,0.3800", "0.7200,-3.2400,0.3800", "0.7200,-3.2400,0.3800",
	"0.7200,-3.2400,0.3800", "0.7200,-3.2400,0.3800", "0.7200,-3.2400,0.3800", "0.7200,-3.2400,0.3800",
	"0.7200,-3.2000,0.5700", "0.7200,-3.2000,0.5700", "0.7200,-3.2000,0.5700", "0.7200,-3.2000,0.5700",
	"0.7200,-3.2000,0.5700", "0.7200,-3.2000,0.5700", "0.7200,-3.2000,0.5700", "0.7200,-3.2000,0.5700",
	"0.7200,-2.6000,0.3800", "0.7200,-2.6000,0.3800", "0.7200,-2.6000,0.3800", "0.7200,-2.6000,0.3800",
	"0.7200,-2.6000,0.3800", "0.7200,-2.6000,0.3800", "0.7200,-2.6000,0.3800", "0.7200,-2.6000,0.3800",
	"0.7200,-2.5600,0.5700", "0.7200,-2.5600,0.5700", "0.7200,-2.5600,0.5700", "0.7200,-2.5600,0.5700",
	"0.7200,-2.5600,0.5700", "0.7200,-2.5600,0.5700", "0.7200,-2.5600,0.5700", "0.7200,-2.5600,0.5700",
	"2.0000,-3.2400,0.3800", "2.0000,-3.2400,0.3800", "2.0000,-3.2400,0.3800", "2.0000,-3.2400,0.3800",
	"2.0000,-3.2400,0.3800", "2.0000,-3.2400,0.3800", "2.0000,-3.2400,0.3800", "2.0000,-3.2400,0.3800",
	"2.0000,-3.2000,0.5700", "2.0000,-3.2000,0.5700", "2.0000,-3.2000,0.5700", "2.0000,-3.2000,0.5700",
	"2.0000,-3.2000,0.5700", "2.0000,-3.2000,0.5700", "2.0000,-3.2000,0.5700", "2.0000,-3.2000,0.5700",
	"2.0000,-2.6000,0.3800", "2.0000,-2.6000,0.3800", "2.0000,-2.6000,0.3800", "2.0000,-2.6000,0.3800",
	"2.0000,-2.6000,0.3800", "2.0000,-2.6000,0.3800", "2.0000,-2.6000,0.3800", "2.0000,-2.6000,0.3800",
	"2.0000,-2.5600,0.5700", "2.0000,-2.5600,0.5700", "2.0000,-2.5600,0.5700", "2.0000,-2.5600,0.5700",
	"2.0000,-2.5600,0.5700", "2.0000,-2.5600,0.5700", "2.0000,-2.5600,0.5700", "2.0000,-2.5600,0.5700",
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
	var box := form.find_child("BoxTrail", true, false) as Node3D if form != null else null
	_expect(box != null, "BoxTrail root missing")
	if box != null:
		# --- A. regression -------------------------------------------------------
		var observed := _collect_positions(box)
		var golden := _parse_golden()
		_expect(observed.size() == golden.size(),
			"gold-box quad count drifted: observed %d vs golden %d" % [observed.size(), golden.size()])
		if observed.size() == golden.size():
			var worst := 0.0
			for i in observed.size():
				worst = maxf(worst, (observed[i] - golden[i]).length())
			_expect(worst < 0.001, "gold box drifted from golden (worst %.4f)" % worst)
		if _failed > 0:
			print("[FormationGoldBoxElementTest] observed multiset (GOLDEN format):")
			var line := ""
			for i in observed.size():
				line += "\"%.4f,%.4f,%.4f\", " % [observed[i].x, observed[i].y, observed[i].z]
				if (i + 1) % 4 == 0 or i == observed.size() - 1:
					print("\t" + line.strip_edges())
					line = ""

		# --- B. identity ---------------------------------------------------------
		_expect(box is UI3Element, "BoxTrail is not a registered UI3Element")
		if box is UI3Element:
			_expect((box as UI3Element).id() == "formation.gold_box",
				"element id %s != formation.gold_box" % (box as UI3Element).id())
			_expect((box as UI3Element).clip_mode() == UI3Element.Clip.UNCLIPPED,
				"gold-box clip answer must be UNCLIPPED (declared)")

		# --- C. visibility latch --------------------------------------------------
		form.set_box_trail_visible(false)
		_expect(not box.visible, "set_box_trail_visible(false) no longer hides the trail element")
		form.set_box_trail_visible(true)
		_expect(box.visible, "set_box_trail_visible(true) did not restore the trail")

	print("\n=== FormationGoldBoxElementTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] FormationGoldBoxElementTest")
		get_tree().quit(1)
	else:
		print("[PASS] FormationGoldBoxElementTest: formation.gold_box registered element (golden no-op + identity + visibility latch)")
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
		push_error("[FormationGoldBoxElementTest] %s" % msg)
		print("  [x] " + msg)
