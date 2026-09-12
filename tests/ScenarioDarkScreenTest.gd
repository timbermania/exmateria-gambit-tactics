extends Node
# test-kind: logic
# seeded-break: point ScenarioDarkScreen's `_mat.shader` at the in-scene mosaic twin
# unconditionally (drop the Fold.shader pick) and the dim/banner pairing assertion reds
# — that is the exact defect that put the fog over the banner. Or set
# ScenarioDarkScreen.DIM_DEFAULT back to 0.75, or RETRACT the
# `Shape` plumbing in `slot_delay()` so every shape returns the same metric — the
# first assertion of `_test_slot_law_matches_the_rom()` and the three per-shape
# max-delay assertions red respectively. For the {78} half, put 56 back into
# ScenarioVM.INSTANT_TASK_KINDS and the kind-56 barrier assertion reds.
## Tests for ScenarioVM's screen-overlay family around the {76} dim: {76} Dark
## Screen itself, {77} Remove Dark Screen, and the {78} Display Conditions screens
## that run BETWEEN them — the battle-intro banner and the whole outro pipeline.
##
## They live in one process because they are one mechanism and one fixture: every
## {78} in all 500 events runs inside a {76}/{77} pair, all three are VM-child
## screen overlays ticked outside the halt gate, and all three release the same way
## — through an {E5} Wait For Instruction barrier on a task kind. Splitting them
## would cost a whole ~2.3 s Godot boot forever (docs/TEST-CHARTER.md clause 13).
##
## RE: research/working_documents/DARKSCREEN_OPCODE_76_INVESTIGATION.md §13/§14 and
## BATTLE_RESULTS_SCREEN.md §4/§4B/§5/§8/§9/§13/§17.
##
## Pure-logic asserts (no headful needed): the operands decode, {76}/{77}/{78}
## dispatch to real handlers (not skip/halt), the per-slot mosaic law matches the
## ROM, {78} routes each mode to the right body and spends the measured number of
## vsyncs, and both {E5} barrier predicates go live then clear.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioDarkScreenTest.tscn

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")
const DarkScreenClass = preload("res://src/scenarios/ScenarioDarkScreen.gd")
const ResultsScreenClass = preload("res://src/scenarios/ScenarioResultsScreen.gd")
const DepthMode = ExMateriaSchema.DepthMode

var _passed: int = 0
var _failed: int = 0
var _nodes: Array = []


func _ready() -> void:
	_test_decode_operands()
	_test_handlers_registered_not_skip()
	_test_controller_grows_settles_and_clears()
	_test_controller_retracts()
	_test_barrier_predicate_live_then_clear()
	_test_slot_law_matches_the_rom()
	_test_display_conditions_modes()
	_test_display_conditions_barrier()
	_test_the_dim_folds_below_the_banner()

	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()

	print("\n=== ScenarioDarkScreenTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioDarkScreenTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioDarkScreenTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioDarkScreenTest")
		get_tree().quit(0)


# --- decode -----------------------------------------------------------------

# Mint an EventInstructionArgs reader from a name->value dict (the decoder takes
# the typed reader now, not a bare dict). Dark Screen operands are unsigned, so
# the default byte width is fine.
func _reader(vals: Dictionary) -> EventInstructionArgs:
	var arr: Array = []
	for k in vals:
		arr.append({"name": String(k), "value": int(vals[k]), "bytes": 1})
	return EventInstructionArgs.from_instruction({"params": arr}, {})


func _test_decode_operands() -> void:
	# Live scenario-4 operands (§8 D3): [00, Shape=1, ScreenExp=0x0C, Rot=0x0040,
	# SqExp=0x04] = the wiki defaults.
	var intent := ScenarioDecode.dark_screen(_reader({
		"Unknown": 0, "Shape": 1, "Screen Expansion Speed": 0x0C,
		"Rotation Speed": 0x40, "Square Expansion Speed": 0x04,
	}))
	_assert_eq(intent.shape, 1, "Shape decoded")
	_assert_eq(intent.screen_expansion_speed, 12, "ScreenExpansionSpeed decoded")
	_assert_eq(intent.rotation_speed, 0x40, "RotationSpeed decoded (carried, unused)")
	_assert_eq(intent.square_expansion_speed, 4, "SquareExpansionSpeed decoded")

	# Speeds clamp to >= 1 (a 0 would divide-by-zero the expansion scaling).
	var z := ScenarioDecode.dark_screen(_reader({"Screen Expansion Speed": 0, "Square Expansion Speed": 0}))
	_assert_true(z.screen_expansion_speed >= 1, "ScreenExpansionSpeed clamps to >=1")
	_assert_true(z.square_expansion_speed >= 1, "SquareExpansionSpeed clamps to >=1")


func _test_handlers_registered_not_skip() -> void:
	var vm := _make_vm()
	_assert_handler(vm, EventInstruction.DARK_SCREEN, "_op_dark_screen")
	_assert_handler(vm, EventInstruction.REMOVE_DARK_SCREEN, "_op_remove_dark_screen")
	_assert_handler(vm, EventInstruction.DISPLAY_CONDITIONS, "_op_display_conditions")


# --- controller animation ---------------------------------------------------

func _test_controller_grows_settles_and_clears() -> void:
	var d := _make_dark_screen()
	_assert_true(not d.is_sweeping(), "not sweeping before start")
	d.start(_default_intent())
	_assert_true(d.is_sweeping(), "sweeping immediately after start (dead delay counts)")
	_assert_eq(d.progress(), 0.0, "progress 0 during the dead delay")

	# During the dead delay the mosaic stays at 0 and the barrier stays live.
	for _f in DarkScreenClass.DEAD_FRAMES:
		d.tick()
	_assert_eq(d.progress(), 0.0, "progress still 0 at the end of the dead delay")
	_assert_true(d.is_sweeping(), "still sweeping through the dead delay")

	# Run through the whole expansion; progress must reach 1 and the barrier clear.
	var mid_seen := false
	for _f in d.sweep_frames() + 4:
		d.tick()
		var p: float = d.progress()
		if p > 0.05 and p < 0.95:
			mid_seen = true
	_assert_true(mid_seen, "progress passed through the mid-expansion range")
	_assert_eq(d.progress(), 1.0, "progress reaches 1.0 once fully expanded")
	_assert_true(not d.is_sweeping(), "barrier clears once the mosaic settles")


func _test_controller_retracts() -> void:
	var d := _make_dark_screen()
	d.start(_default_intent())
	# Fast-forward to fully settled.
	for _f in DarkScreenClass.DEAD_FRAMES + d.sweep_frames() + 4:
		d.tick()
	_assert_eq(d.progress(), 1.0, "settled before retract")
	d.remove()
	for _f in d.sweep_frames() + 2:
		d.tick()
	_assert_eq(d.progress(), 0.0, "progress returns to 0 after retract")
	_assert_true(not d.visible, "overlay hidden after retract completes")


# --- the per-slot law, straight out of 0x801CA664 ---------------------------

## `0x801CA664` read line by line (DARKSCREEN_OPCODE_76_INVESTIGATION.md §13) and
## checked against the running emulator (§14 / BATTLE_RESULTS_SCREEN.md §17). Four
## claims the first port was written against have been RETRACTED, and each one is a
## row here:
##
##   1. the covered pixel is a plain ½·bg + ½·F — the "PSX draws each diamond TWICE"
##      reading was the slot's A/B double buffer, so `dim` is 0.5 and not 0.75;
##   2. `Shape` picks the SWEEP METRIC (0 = circle from the screen centre, 1 =
##      quarter-circle from the top-left, 2 = a vertical front), and the whole sweep
##      is `d² / (256·ScreenExpansionSpeed)` per slot — it was decoded and dropped;
##   3. the squares SPIN 0 → 512 (= 45°) as they grow — they are axis-aligned squares
##      at angle 0 and the measured diamonds only at the cap;
##   4. the retract is the SAME loop run backwards through the same per-slot delays,
##      measured live at 112 vsyncs — not a snappier 24.
##
## Every number below is either §13's law or §14/§17's live dump of all 288 slots.
func _test_slot_law_matches_the_rom() -> void:
	# 1 — the blend. One packet per diamond per frame, abr 0.
	_assert_eq(DarkScreenClass.DIM_DEFAULT, 0.5, "dim is a plain half-blend (§11.2 retraction)")

	# The lattice — 24 columns x 12 rows, all 288 matched live with 0 mismatches (§14).
	var seen := {}
	var min_c := Vector2i(9999, 9999)
	var max_c := Vector2i(-9999, -9999)
	for row in DarkScreenClass.LATTICE_ROWS:
		for col in DarkScreenClass.LATTICE_COLS:
			var c: Vector2i = DarkScreenClass.lattice_center(col, row)
			seen[c] = true
			min_c = Vector2i(mini(min_c.x, c.x), mini(min_c.y, c.y))
			max_c = Vector2i(maxi(max_c.x, c.x), maxi(max_c.y, c.y))
	_assert_eq(seen.size(), 288, "288 distinct lattice slots")
	_assert_eq(min_c, Vector2i(-12, -24), "lattice starts one cell off the top-left")
	_assert_eq(max_c, Vector2i(264, 252), "lattice runs one cell past the bottom-right")

	# 2 — Shape is the sweep metric, and it changes how long the sweep takes. The
	# three shipped shapes' max delays fall straight out of `d²/3072` over the lattice.
	var by_shape := {}
	for shape in [0, 1, 2, 3]:
		var worst := 0
		for row in DarkScreenClass.LATTICE_ROWS:
			for col in DarkScreenClass.LATTICE_COLS:
				worst = maxi(worst, DarkScreenClass.slot_delay(
					DarkScreenClass.lattice_center(col, row), shape, 12))
		by_shape[shape] = worst
	_assert_eq(by_shape[0], 13, "Shape 0 (circle from screen centre) peaks at delay 13")
	_assert_eq(by_shape[1], 41, "Shape 1 (quarter-circle from top-left) peaks at delay 41")
	_assert_eq(by_shape[2], 22, "Shape 2 (vertical front) peaks at delay 22")
	_assert_eq(by_shape[3], 13, "Shape >=3 (diagonal band) peaks at delay 13")
	# The top-left slot is born immediately under Shape 1 and late under Shape 0.
	_assert_eq(DarkScreenClass.slot_delay(Vector2i(-12, -24), 1, 12), 0, "Shape 1 starts at the corner")
	_assert_true(DarkScreenClass.slot_delay(Vector2i(-12, -24), 0, 12) > 10, "Shape 0 reaches the corner last")

	# 3 — the spin. `size` steps by SquareExpansionSpeed capped at 48 (12 yields),
	# `angle` by RotationSpeed capped at 512 (8 yields) — §14 dumped both grids live.
	var sizes := {}
	var angles := {}
	for t in 20:
		sizes[DarkScreenClass.slot_size(t, 4, false)] = true
		angles[DarkScreenClass.slot_angle(t, 0x40, false)] = true
	_assert_eq(DarkScreenClass.slot_size(0, 4, false), 0, "a slot starts as a point")
	_assert_eq(DarkScreenClass.slot_angle(0, 0x40, false), 0, "and axis-aligned, NOT a diamond")
	_assert_eq(DarkScreenClass.slot_angle(8, 0x40, false), 512, "the spin finishes in 8 yields")
	_assert_eq(DarkScreenClass.slot_size(12, 4, false), 48, "the growth finishes in 12 yields")
	_assert_eq(DarkScreenClass.slot_size(99, 4, false), 48, "size clamps at 48")
	_assert_eq(DarkScreenClass.slot_angle(99, 0x40, false), 512, "angle clamps at 512 (45 degrees)")
	_assert_eq(sizes.size(), 13, "sizes land on the live {0,4,..,48} grid, nothing off-grid")
	_assert_eq(angles.size(), 9, "angles land on the live {0,64,..,512} grid")
	# Backwards, the same two ramps run the other way (`angle -= Rot`, `size -= Sqr`).
	_assert_eq(DarkScreenClass.slot_size(0, 4, true), 48, "retract: a slot before its turn is still FULL")
	_assert_eq(DarkScreenClass.slot_angle(0, 0x40, true), 512, "retract: ...and still a diamond")
	_assert_eq(DarkScreenClass.slot_size(12, 4, true), 0, "retract: gone 12 yields after its turn")

	# 4 — the retract is the expansion backwards, so both are `max delay + 48/step`
	# yields long. At §17's measured 2.1 vsyncs per yield the shipped Shape-1 operand
	# set comes out at 112 vsyncs — which is what §17 measured off the live emulator.
	var d := _make_dark_screen()
	d.start(_default_intent())
	_assert_eq(d.sweep_yields(), 53, "Shape 1 sweeps 41 delay + 12 growth = 53 yields")
	_assert_eq(d.sweep_frames(), 112, "...= 112 vsyncs, the live-measured retract (§17)")
	var s0 := _make_dark_screen()
	s0.start(_intent(0, 0x0C, 0x40, 0x04))
	_assert_eq(s0.sweep_yields(), 25, "Shape 0 sweeps 13 + 12 = 25 yields")
	_assert_true(s0.sweep_frames() < d.sweep_frames(), "a circle-from-centre sweep is shorter than a corner one")

	# The retract spends the SAME frames as the grow-in — the defect the old
	# RETRACT_FRAMES := 24 ("snappier than the grow-in") encoded.
	var r := _make_dark_screen()
	r.start(_default_intent())
	for _f in DarkScreenClass.DEAD_FRAMES + r.sweep_frames() + 2:
		r.tick()
	_assert_eq(r.progress(), 1.0, "settled")
	r.remove()
	var spent := 0
	while r.progress() > 0.0 and spent < 400:
		r.tick()
		spent += 1
	_assert_eq(spent, r.sweep_frames(), "the retract spends the grow-in's frames, not a quarter of them")


# --- VM barrier wiring ------------------------------------------------------

func _test_barrier_predicate_live_then_clear() -> void:
	# The kind-54 predicate (what {E5} Wait For Instruction(0x36) polls) must be
	# LIVE while the mosaic grows in and CLEAR once it settles.
	var vm := _make_vm()
	vm._dark_screen = _adopt(vm._make_dark_screen())
	vm._dark_screen.start(_default_intent())
	_assert_true(vm._task_kind_live(ScenarioVMClass.TASK_DARKSCREEN, null),
		"kind-54 barrier LIVE while the mosaic is growing in")

	for _f in DarkScreenClass.DEAD_FRAMES + vm._dark_screen.sweep_frames() + 4:
		vm._dark_screen.tick()
	_assert_true(not vm._task_kind_live(ScenarioVMClass.TASK_DARKSCREEN, null),
		"kind-54 barrier CLEAR once the mosaic has settled")

	# AND THE RETRACT HOLDS IT TOO — #1168. The barrier is on the task KIND: {77}
	# re-labels the slot back to 0x36 and runs the same loop backwards, so the
	# `{E5} 36 00` that follows {77} waits out the whole 112-frame teardown. The
	# predicate used to read `_dir == 1` only, so it reported DEAD on the frame {77}
	# ran and the battle intro lost its last 1.87 s. Ticked ONE SHORT of the sweep
	# first, because "live at frame 1" and "live at the last frame" are different
	# claims and only the second one is the bug.
	vm._dark_screen.remove()
	_assert_true(vm._task_kind_live(ScenarioVMClass.TASK_DARKSCREEN, null),
		"kind-54 barrier LIVE on the frame {77} runs")
	for _f in vm._dark_screen.sweep_frames() - 1:
		vm._dark_screen.tick()
	_assert_true(vm._task_kind_live(ScenarioVMClass.TASK_DARKSCREEN, null),
		"kind-54 barrier STILL LIVE one frame short of the retract's end")
	vm._dark_screen.tick()
	_assert_true(not vm._task_kind_live(ScenarioVMClass.TASK_DARKSCREEN, null),
		"kind-54 barrier CLEAR once the retract has finished")


# --- {78} Display Conditions ------------------------------------------------

## `{78}`'s first operand is a MODE, not a conditions id, and the dispatcher
## `0x801CAFD4` routes it to one of eight bodies (BATTLE_RESULTS_SCREEN.md §13).
## The durations below are the ones §9 re-measured live at 1-vsync resolution and
## §13 read out of the drivers' own wait counts — NOT yield counts doubled by hand.
func _test_display_conditions_modes() -> void:
	# Modes >= 8 — the victory-condition banner, page `mode - 8`, `20 + Time + 10`
	# yields. At the shipped `Time = 90` that is 120 frame-swaps ~= 4.0 s.
	var banner := _make_results()
	banner.run(8, 90)
	_assert_eq(banner.mode(), 8, "mode 8 routes to the banner")
	_assert_eq(_run_to_end(banner), 242, "banner = (20 + 90 + 10) swaps of 2 vsyncs")
	# `Time` REACHES the banner: a different hold is a different length.
	var banner60 := _make_results()
	banner60.run(8, 60)
	_assert_eq(_run_to_end(banner60), 182, "banner honours its Time operand")

	# Mode 0 — READY!, spawned FIRST and held `Time` swaps, then commanded out.
	var ready := _make_results()
	ready.run(0, 60)
	_assert_eq(_run_to_end(ready), 132, "READY! = 60 swaps held + the fade-out")

	# Mode 2 — the victory text. `0x801C3DF8` waits 30 swaps between the two lines
	# and 180 more before commanding both out; §9 measured the whole beat at 434
	# vsyncs and the settled hold at the 5.7 s it is famous for.
	var victory := _make_results()
	victory.run(2, 60)
	var spent := _run_to_end(victory)
	_assert_true(absi(spent - 434) <= 4, "victory text ~= 434 vsyncs, got %d" % spent)

	# Mode 3 — BONUS MONEY + the gil reel. The reel is a 1/256-px integrator, one
	# `pos += vel` per vsync, and §8.4/§9 measured 55,700 Gil landing its five
	# columns 32 vsyncs apart with the whole reel at 248 vsyncs.
	ResultsScreenClass.bonus_gil = 55700
	var reel := _make_results()
	reel.run(3, 60)
	_assert_eq(reel.reel_positions().size(), 5, "55,700 splits into five columns")
	var reel_spent := _run_to_end(reel)
	_assert_true(absi(reel_spent - 389) <= 6,
		"reel screen ~= 248 reel + 127 hold + fade, got %d" % reel_spent)
	# Every column lands EXACTLY on its digit cell: `pos mod 8192 == 244` on all
	# five in ss9, because the braking phase adds a fixed 46,580 units and cruise
	# and crawl are both multiples of 256. A 1-in-256 coincidence, five times over.
	for p in reel.reel_positions():
		_assert_eq(p % 8192, 244, "column settles on the §8.4 landing residue")
	ResultsScreenClass.bonus_gil = 0

	# Modes 1 and 4..7 are real pipeline steps that find nothing to draw — §17 drove
	# the live outro to the end and measured 4/5/6 at two vsyncs each and 7 at less
	# than one, because that battle dropped no loot, lost nobody and recruited
	# nobody. They must NOT hold the barrier.
	for m in [1, 4, 5, 6, 7]:
		var noop := _make_results()
		noop.run(m, 60)
		_assert_true(not noop.is_live(), "mode %d finds nothing to draw" % m)


## The kind-56 (0x38) barrier. Every {78} in all 500 events is followed by
## `{E5} 38 00`, and `0x801CAFD4`'s first act is `0x80149D48(0x38)` — so this is a
## plain "wait for the screen to finish", and it is what lets the gil reel own the
## frame for four seconds without the victory text still being up.
func _test_display_conditions_barrier() -> void:
	var vm := _make_vm()
	_assert_true(not ScenarioVMClass.INSTANT_TASK_KINDS.has(ScenarioVMClass.TASK_CONDITIONS),
		"kind 56 is NOT a silent fall-through — {78} owns it")
	_assert_true(not vm._task_kind_live(ScenarioVMClass.TASK_CONDITIONS, null),
		"kind-56 barrier CLEAR with no {78} in flight")
	vm._results_screen = _adopt_node(vm._make_results_screen())
	vm._results_screen.run(0, 60)
	_assert_true(vm._task_kind_live(ScenarioVMClass.TASK_CONDITIONS, null),
		"kind-56 barrier LIVE while READY! is on its clock")
	for _f in 400:
		if not vm._results_screen.is_live():
			break
		vm._results_screen.tick()
	_assert_true(not vm._task_kind_live(ScenarioVMClass.TASK_CONDITIONS, null),
		"kind-56 barrier CLEAR once the screen finishes")
	# settle() is the fast-play guarantee: a combat SEEK can park mid-screen.
	vm._results_screen.run(2, 60)
	vm._results_screen.settle()
	_assert_true(not vm._task_kind_live(ScenarioVMClass.TASK_CONDITIONS, null),
		"settle() lands the screen finished, so the barrier cannot deadlock a SEEK")


## Tick a screen until it reports done; returns the vsyncs it spent. Frame-budgeted
## (charter clause 5/6) so a screen that never finishes produces a verdict, not a hang.
func _run_to_end(r) -> int:
	var f := 0
	while r.is_live() and f < 2000:
		r.tick()
		f += 1
	return f


# --- the fold order the banner is drawn in ----------------------------------

## 🔴 THE DEFECT THIS PINS WAS INVISIBLE TO ALL 772 TESTS, and it is a ROUTING fact,
## not a timing one: {78}'s banner draws its shadow and text with `blend_add`/
## `blend_sub`, which must fold (the display-space scratch is where PSX's clamped
## `bg ± fg` belongs). But `FoldSurface`'s Pass C resolves at PRE_TRANSPARENT, so
## anything left in-scene as a TRANSPARENT draws over the resolved layer. With the
## banner folded and {76}'s dim in-scene, the dim covered the banner — measured by
## driving `dim` to 1.0 and reading the brightest pixel in the banner band: it was
## (48, 40, 16), the fog colour, i.e. the text was gone. At the shipped 0.5 it was a
## half-cover of fog, which reads as washed-out, low-contrast text and is worse the
## brighter the map underneath.
##
## The PSX orders them the other way — the text is at OT bucket 0 and the tint at
## bucket 1 (BATTLE_RESULTS_SCREEN.md §7) — so the fix is that BOTH fold and the dim
## takes the lower rung. These asserts are what stops the pair drifting apart again:
## a future change that un-folds the dim, or that gives the two banner passes the
## same rung, re-opens it.
func _test_the_dim_folds_below_the_banner() -> void:
	# The rungs must be strictly ordered — dim under shadow under text. A tie is not
	# "close enough": coincident prims fold-tie, which is how the shadow pass could
	# land on top of the text it is supposed to sit behind.
	_assert_true(DarkScreenClass.FOLD_RUNG_DIM < ResultsScreenClass.FOLD_RUNG_BANNER_SUB,
		"{76}'s dim folds BELOW {78}'s banner shadow")
	_assert_true(ResultsScreenClass.FOLD_RUNG_BANNER_SUB < ResultsScreenClass.FOLD_RUNG_BANNER_ADD,
		"the banner's shadow folds below its additive text (AddPrim's rendered order)")

	# ...and the rungs must survive the conversion to fold-order keys. `rung_z` is one
	# PSX OT bucket per rung, so distinct rungs MUST give distinct keys; asserting the
	# constants alone would pass even if both mapped onto one bucket.
	var k_dim := DepthMode.render_layer_order_for(DepthMode.rung_z(DarkScreenClass.FOLD_RUNG_DIM))
	var k_sub := DepthMode.render_layer_order_for(DepthMode.rung_z(ResultsScreenClass.FOLD_RUNG_BANNER_SUB))
	var k_add := DepthMode.render_layer_order_for(DepthMode.rung_z(ResultsScreenClass.FOLD_RUNG_BANNER_ADD))
	_assert_true(k_dim < k_sub and k_sub < k_add,
		"the three fold-order keys are strictly increasing (got %d, %d, %d)" % [k_dim, k_sub, k_add])

	# On a build that owns the fold, BOTH must actually be wearing their
	# `compositor_layer` variant. The bug was not that the banner failed to fold — it
	# folded correctly and the dim did not, which is the pairing this asserts.
	var d := _make_dark_screen()
	var r := _make_results()
	var dim_mat := (d._mmi.material_override as ShaderMaterial)
	var add_mat := (r._mmi["add"].material_override as ShaderMaterial)
	var folds: bool = ExMateriaSchema.Fold.owns()
	_assert_eq(dim_mat.shader.resource_path.contains("_fold"), folds,
		"the dim wears its fold twin exactly when the build owns a fold")
	_assert_eq(add_mat.shader.resource_path.contains("_fold"), folds,
		"the banner wears its fold twin exactly when the build owns a fold")
	# The pairing itself, stated as one claim so it cannot pass by both being false
	# for different reasons.
	_assert_eq(dim_mat.shader.resource_path.contains("_fold"),
		add_mat.shader.resource_path.contains("_fold"),
		"the dim and the banner are on the SAME side of the fold, always")


# --- fixtures ---------------------------------------------------------------

func _default_intent() -> ScenarioDecode.DarkScreenIntent:
	return _intent(1, 0x0C, 0x40, 0x04)


## The six-operand set `00 <Shape> <ScreenExp> <Rot16> <SqExp>`; the shipped one is
## `00 01 0C 4000 04` in 134 of the 153 pre-{DB} sites (BATTLE_RESULTS_SCREEN.md §13).
func _intent(shape: int, screen_exp: int, rot: int, sq_exp: int) -> ScenarioDecode.DarkScreenIntent:
	return ScenarioDecode.dark_screen(_reader({
		"Shape": shape, "Screen Expansion Speed": screen_exp,
		"Rotation Speed": rot, "Square Expansion Speed": sq_exp,
	}))


func _make_vm() -> ScenarioVMClass:
	var vm := ScenarioVMClass.new()
	add_child(vm)
	vm.set_process(false)
	_nodes.append(vm)
	return vm


func _make_dark_screen() -> ScenarioDarkScreen:
	var d := DarkScreenClass.new()
	add_child(d)  # _ready() builds the render resources
	_nodes.append(d)
	return d


func _make_results() -> ScenarioResultsScreen:
	var r := ResultsScreenClass.new()
	add_child(r)  # _ready() loads the manifest + builds the prim-list meshes
	_nodes.append(r)
	return r


## Track a VM-parented node for cleanup too.
func _adopt(d: ScenarioDarkScreen) -> ScenarioDarkScreen:
	_nodes.append(d)
	return d


func _adopt_node(n: Node) -> Node:
	_nodes.append(n)
	return n


# --- assert helpers ---------------------------------------------------------

func _assert_handler(vm, op: int, method: String) -> void:
	# op is an EventInstruction member (byte); the display name is the descriptor
	# label, kept for readable assertion messages only (dispatch is byte-keyed).
	var op_name := EventInstructionSet.name_of(op)
	var h = vm._handlers.get(op, null)
	_assert_true(h != null, "%s handler registered" % op_name)
	if h != null:
		_assert_eq((h as Callable).get_method(), method, "%s -> %s (not skip/halt)" % [op_name, method])


func _assert_eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _assert_true(cond: bool, name: String) -> void:
	_assert_eq(cond, true, name)
