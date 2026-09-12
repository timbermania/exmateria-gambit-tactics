extends Node3D
# test-kind: logic
# seeded-break: renamed the _build_background() UI3Element's id to 'formation.background_seedbroken'; the identity assert id()==formation.background reds (golden-multiset + capability still pass)

## ADR-0088 migration guard: the roster BACKDROP group (the §14.6 cobble floor quad +
## the §14.6.6 subtractive band backdrop, one blend-ordered holder) is housed in the
## registered element `formation.background` — a screen-anchored assembly, UNCLIPPED,
## no beat (the band fades via the band factor, not a transition).
##   A. REGRESSION — golden position multiset (floor + band quads, pre-migration).
##   B. IDENTITY — the Background holder IS the registered element.
##   C. CAPABILITY — moving the element moves floor + band together.
##
## Run: <GODOT> --path . --quit-after 30 res://tests/FormationBackdropElementTest.tscn

const FormationDetailTransition = preload("res://src/ui3/formation/FormationDetailTransition.gd")

## Captured 2026-08-11 from the pre-migration build (this guard's print aid).
const GOLDEN := [
	"5.1200,-8.1000,0.1900",
	"5.1200,-4.8000,0.0000",
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
	var bg := form.find_child("Background", true, false) as Node3D if form != null else null
	_expect(bg != null, "Background holder missing")
	if bg != null:
		# --- A. regression -------------------------------------------------------
		var observed := _collect_positions(bg)
		var golden := _parse_golden()
		_expect(observed.size() == golden.size(),
			"backdrop quad count drifted: observed %d vs golden %d" % [observed.size(), golden.size()])
		if observed.size() == golden.size():
			var worst := 0.0
			for i in observed.size():
				worst = maxf(worst, (observed[i] - golden[i]).length())
			_expect(worst < 0.001, "backdrop drifted from golden (worst %.4f)" % worst)
		if _failed > 0:
			print("[FormationBackdropElementTest] observed multiset (GOLDEN format):")
			for i in observed.size():
				print("\t\"%.4f,%.4f,%.4f\"," % [observed[i].x, observed[i].y, observed[i].z])

		# --- B. identity ---------------------------------------------------------
		_expect(bg is UI3Element, "Background is not a registered UI3Element")
		if bg is UI3Element:
			_expect((bg as UI3Element).id() == "formation.background",
				"element id %s != formation.background" % (bg as UI3Element).id())
			_expect((bg as UI3Element).clip_mode() == UI3Element.Clip.UNCLIPPED,
				"backdrop clip answer must be UNCLIPPED (declared)")

		# --- C. capability -------------------------------------------------------
		var before := _collect_positions(bg)
		var delta := Vector3(1.234, -0.567, 0.0)
		bg.position += delta
		var after := _collect_positions(bg)
		var ok := after.size() == before.size() and before.size() > 0
		if ok:
			for i in before.size():
				if ((after[i] - before[i]) - delta).length() >= 0.001:
					ok = false
					break
		_expect(ok, "backdrop content did not ride the element move")
		bg.position -= delta

	print("\n=== FormationBackdropElementTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] FormationBackdropElementTest")
		get_tree().quit(1)
	else:
		print("[PASS] FormationBackdropElementTest: formation.background registered element (golden no-op + identity + grab)")
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
		push_error("[FormationBackdropElementTest] %s" % msg)
		print("  [x] " + msg)
