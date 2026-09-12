class_name GambitLabScene
extends CombatHost

## THE GAMBIT LAB — LIVE ARM (ADR-0275 decs. 13, 14, 17, 19, 20, 24; issue #1128).
##
## One cell you can WATCH: a fixture booted on its own map, stepped a tick at a time, with
## the kernel's own per-slot VERDICT rendered beside the units it explains.
##
## === WHAT IT IS FOR ========================================================================
##
## `evaluate_gambits_up_to` has twelve distinct outcomes per slot and, before ADR-0275 dec. 4,
## exactly one of them stamped a reason anywhere a host could read. Group-B fall-through was
## therefore debugged by inference. The kernel now writes `{verdict, condition index, opcode,
## evaluated mask}` per pass into each slot's two reserved ints; this scene is where a human
## reads them WHILE the battle runs, rather than after it in a log.
##
## Its acceptance is not "it boots" (dec. 24 rejects that explicitly). It is that the lab
## EXPLAINS the two standing XFAILs in `tests/gambit_scenarios/scenarios_B_fallthrough.gd`.
##
## === WHY A HOST OF ITS OWN, AND NOT THE NAVIGATOR ==========================================
##
## ADR-0264 decides a combat-adjacent tool is a seek into `NavigatorMain` rather than a new
## `CombatHost`. ADR-0275 dec. 14 argues it does not reach here, and this is that argument in
## the file it decides: 0264's whole rationale is the three BATTLE-ENTRY INVARIANTS — opener
## framing, the deployment idle tick, ENTD facing — which "exist once in the spine and drift
## in a second copy". A synthetic two-unit cell on MAP042 reproduces NONE of them, and routing
## it through the navigator would force it to fake an opener it does not want. If you disagree,
## reopen dec. 14 rather than routing around it.
##
## It is also NOT a mode on `GambitScenarioRunner` (dec. 14): 84 fixtures read behaviour off
## that host. What the two DO share is the boot — [GambitScenarioBoot] — because a trace is
## only an explanation of an XFAIL if it is a trace of that same battle.
##
## === THE CORPUS IS ONE LIST: THE FIXTURES, THEN THE SYNTHESIZED CELLS ======================
##
## `N`/`B` walk **both halves**. The fixtures come first, then [GambitCellSynth]'s catalogue —
## each positive cell, its MIRROR, and the cells that REFUSE — because dec. 13 already made them
## one experiment: a cell spec carries a fixture-shaped `scenario` and [GambitScenarioBoot] boots
## it unchanged, so there is no second boot path and no second walker to disagree with the first.
## `Cells >` on the panel jumps straight to the seam.
##
## They were unreachable from the scene until #1129's follow-up: `--cell=` booted one and
## `--cells` printed the census, and nothing else in the lab could see them — so the arm that
## generates dec. 2's unit of evidence was invisible to the instrument that exists to read it,
## and the lab read as a fixed menu of somebody else's tests.
##
## A cell's prediction is SCORED the moment the actor is first evaluated, in the interactive arm
## as well as under `--trace`. That timing is not a convenience: `clear_verdict` wipes and
## rewrites every slot the next call walks, so the FIRST evaluation is the only one the
## prediction is about.
##
## === THE FIXTURES ARE READ-ONLY, AND THERE IS NO SAVE BUTTON ===============================
##
## dec. 17. The lab boots any of the 84 dicts and steps it, on ITS OWN map (67 are MAP042,
## 5 are MAP100) — never re-hosted, because 46 of 84 use plain `ATTACK`, which is height- and
## LOS-sensitive. Edits made in the surface go to the GPU and die with the process. There is
## deliberately no "save as fixture": a generated fixture asserts whatever the code did when
## the button was pressed, so if the behaviour being hunted was the bug, the click commits a
## guard protecting it.
##
## === THE SAFETY NET IS LABELLED, NEVER SUPPRESSED ==========================================
##
## dec. 19. ADR-0048's injected net fires in the lab exactly as it fires in a battle, and
## hiding it would make the lab debug a battle that does not exist. It renders as its own row,
## marked `[safety net]`, at slot index `GPUConstants.MAX_USER_GAMBITS` — DERIVED, never a
## literal 5.
##
## === RUNNING IT ============================================================================
##
## Headful, never `--headless`, on the 4.8 fork. From `godot-learning/`:
##
##     godot --path . assets/scenes/GambitLab.tscn                        # watch, interactively
##     godot --path . assets/scenes/GambitLab.tscn -- --scenario=B7       # boot a named fixture
##     godot --path . assets/scenes/GambitLab.tscn -- --scenario=B7 --trace=60
##
## And the SYNTHESIZED arm (ADR-0275 decs. 1/2/8-12, #1129 — [GambitCellSynth]):
##
##     godot --path . assets/scenes/GambitLab.tscn -- --coverage     # dec. 22's coverage line
##     godot --path . assets/scenes/GambitLab.tscn -- --cells        # the whole census, dry
##     godot --path . assets/scenes/GambitLab.tscn -- --cell=hp_below/mirror   # boot it, STAY
##     godot --path . assets/scenes/GambitLab.tscn -- --cell=hp_below/mirror --trace=80
##     godot --path . assets/scenes/GambitLab.tscn -- --cell=throw_speed --trace   # its OWN budget
##
## `--coverage` and `--cells` boot nothing — the synthesizer is a pure function, so its census
## costs no `RenderingDevice` and no tick. `--scenario=` and `--cell=` are the same verb over the
## two halves of the corpus: each resolves a needle to a CORPUS INDEX, and `_boot` reads the
## index alone, so a cell reached by `--cell=` and a cell reached by pressing `N` cannot differ.
## Either way the cell's prediction is SCORED field by field, which is what makes dec. 2's mirror
## worth generating: a pair that fails to flip is a defect regardless of what anyone expected.
##
## `--trace=N` is the batch arm: it steps N ticks in LOCKSTEP (one `CombatLoop.tick` per
## tick, no frame-rate coupling), prints a per-tick reason trace to stdout, and quits. That is
## the form the XFAIL explanations on #1128 were taken in. Bare `--trace` takes the budget from
## the ENTRY — a cell's derived `ticks_for_speed` (dec. 12's throw straddle drops Speed to 8, and
## a unit at Speed 8 needs 450 ticks to reach its first turn where one at 120 needs 30), a
## fixture's [constant DEFAULT_TRACE_TICKS].
##
## Keys: `SPACE` step one tick · `ENTER` run/pause · `R` reboot the entry ·
## `N`/`B` next/previous CORPUS ENTRY · `TAB` cycle the watched actor · `V` schematic/sprites ·
## `G` open the gambit surface on the watched actor · `BACKSPACE` close it.
##
## `WASD` walks the tile cursor, and ○/△ on a unit opens its Status screen — the same two doors
## the battlefield has, because since ADR-0275 dec. 25 this lab mounts the same
## map-hosted screen [GambitBattle] does rather than a second copy of the mount.
##
## ⚠️ WHILE A SCREEN IS UP THE LAB IS DEAF AND THE PUMP IS PAUSED, by ADR-0137's design and not
## by accident: an open screen claims the whole pad (mouse and `F3` exempt) and ADR-0037 pauses
## the battle under it. So `SPACE` does not step while you are reading a gambit list — close with
## `BACKSPACE` first. The `F3` readout stays visible throughout, which is the half that has to be
## simultaneous: the verdict is what the list is being read against.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias line per file
# keeps every use site's spelling, and makes a grep for the façade a complete census of
# host->addon symbol coupling.
const TileHighlights = ExMateriaBattlefield.TileHighlights
const CursorRig = ExMateriaBattlefield.CursorRig
const TerrainCell = ExMateriaSchema.TerrainCell
const CellMarking = ExMateriaSchema.CellMarking
const Gambit = ExMateriaAlmanac.Gambit
const GambitList = ExMateriaAlmanac.GambitList
const GambitCondition = ExMateriaAlmanac.GambitCondition
const TargetSelector = ExMateriaAlmanac.TargetSelector
const JobDatabase = ExMateriaAlmanac.JobDatabase
const Character = ExMateriaCatalogue.Character

const UnitField = GPUCombatPacker.UnitField

## The REAL map-hosted Formation coordinator (ADR-0137) — the thing that gives [GambitSurface]
## a render context. Preloaded by PATH rather than named as a class because that is how the two
## other map-bearing scenes reach it ([GambitBattle], [GPUArena]).
const FormationDetailTransitionScript = preload(
	"res://src/ui3/formation/FormationDetailTransition.gd")

## The lab watches ONE battle. The fleet arm (dec. 13) is the thing that holds 256.
const BATTLE := 0

## What bare `--trace` spends on a hand-authored FIXTURE, which carries no derived budget of its
## own. A cell takes `GambitCellSynth.ticks_for_speed` instead — see the derivation in `_ready`.
const DEFAULT_TRACE_TICKS := 60

## The keys this host acts on — the same list the class docstring and the panel legend
## print. Declared so `_unhandled_input` can consume a press BEFORE branching, rather than
## after an `await` that outlives the event.
const LAB_KEYS: Array[int] = [
	KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_R, KEY_N, KEY_B, KEY_TAB, KEY_V, KEY_G,
	# The SCRATCH CELL's verbs. Every one of these is unbound in `project.godot`'s InputMap —
	# checked, because `WASD` walks the cursor (`camera_*` / `ui_*`), `Q`/`E` rotate the camera
	# and `[`/`]` page the formation sort. A verb that shadowed one of those would take a key
	# the battlefield is already using and the collision would read as "the cursor is broken".
	KEY_F, KEY_1, KEY_2, KEY_X, KEY_M, KEY_J,
]

## The scratch cell's verbs, by key — the subset of [constant LAB_KEYS] that edits a CELL rather
## than driving one. Everything but `F` needs the scratch cell to be the booted entry.
const SCRATCH_KEYS: Array[int] = [KEY_1, KEY_2, KEY_X, KEY_M, KEY_J]

## The job a freshly added unit wears, and the ring `J` cycles through. `4c` is the corpus's own
## most-used job (105 of the 184 unit definitions).
const SCRATCH_JOB := "4c"

@onready var map: Node3D = $ProceduralMap
@onready var player_camera: Node3D = $PlayerCamera

## The cursor NODE, by scene path — a scene-tree coupling, not a type reference (ADR-0196
## dec. 2). Everything read off it goes through `cursor_rig` (ADR-0206), exactly as
## [GambitBattle] and [FireCastReproScene] do it.
@onready var tile_cursor: Node3D = get_node_or_null("TileCursor")
var cursor_rig: CursorRig = null

# --- the corpus, and which of it is loaded -----------------------------------------------
var _scenarios: Array = []
## How many of `_scenarios` are hand-authored FIXTURES. Everything at or after this index is a
## synthesized cell — the one fact that tells the two halves of the corpus apart, and the reason
## `_is_cell` is an index question rather than a duck-type on the dict.
var _fixture_count: int = 0
## The corpus index of the editable scratch cell — always the LAST entry. -1 until built.
var _scratch_index: int = -1
## The scratch cell itself, fixture-shaped. The same dict `_scenarios[_scratch_index]` holds, so
## a mutation here IS a mutation of the corpus entry and `R` re-boots what you just edited.
var _scratch: Dictionary = {}
var _index: int = 0
## The current boot's ticket. Bumped by every `_boot`; a boot whose ticket is stale after an
## await abandons rather than writing into the boot that replaced it. See `_boot`.
var _boot_gen: int = 0
var _scenario: Dictionary = {}
var _current_map: String = ""

# --- drive ---------------------------------------------------------------------------------
var _running: bool = false
var _watched: int = 0          # unit index whose slots the readout details
var _schematic: bool = true
var _trace_ticks: int = 0      # >0 => batch arm: step this many, print, quit
## `--trace` with no `=N`: take the budget from the entry itself, once the boot knows which.
var _trace_derived: bool = false
var _open_surface_at_boot: bool = false
## `--shot=<path>` — write ONE viewport PNG and quit. "" = the interactive arm.
var _shot_path: String = ""

# --- the SYNTHESIZED arm (ADR-0275 decs. 1/2/8-12, #1129) ----------------------------------
## The cell spec being booted, or `{}` when the lab is replaying one of the 84 fixtures.
## [GambitCellSynth]'s spec carries a `scenario` shaped exactly like a fixture, so there is no
## second boot path — `_boot` reads THIS dict's `scenario` and [GambitScenarioBoot] takes it
## unchanged. A synthesized cell and a replayed fixture therefore reach the GPU identically,
## which is the only arrangement under which a cell's finding transfers to a fixture's.
var _cell: Dictionary = {}
## The actor's per-slot verdicts at the FIRST tick it was evaluated, and that tick.
##
## Scoring the END of the trace would score the LAST evaluation: `clear_verdict` wipes and
## rewrites every slot the call walks, so an actor that decided on tick 36 and decided again on
## tick 72 carries only the second reading. The cell's prediction is about the first decision,
## so the first is what gets captured — and a cell that never reaches one keeps this empty,
## which reads as "the actor never got a turn" rather than as a silent pass.
var _cell_first: Array = []
var _cell_first_tick: int = -1
## Has this boot's cell been scored yet? One score per boot, wherever the first evaluation is
## reached from — the interactive walker or `--trace`'s lockstep loop.
var _scored: bool = false
## The last score, for the panel: `{scored, pass, fail, tick}`. Empty until one is taken.
var _cell_score: Dictionary = {}
## Dry-run arms: print and quit without booting anything. Cheap on purpose — the synthesizer is
## a pure function, so its whole census costs no `RenderingDevice` and no tick.
var _census_mode: bool = false
var _coverage_mode: bool = false

# --- instrument ----------------------------------------------------------------------------
## The kernel's verdict, read through the SHARED instrument (#1211). It was four private members
## and six methods on this scene, which is exactly why `GambitVerdictReader` had two consumers in
## the whole tree and both were the lab: a host that wanted the readout had to become the lab.
var _probe := GambitVerdictProbe.new()
var _unit_names: Array = []    # GPU unit index -> name
var _cfgs: Array = []          # GPU unit index -> the fixture's own unit dict
var _panel = null
var _highlights: TileHighlights = null
var _painted: Array = []          # cells currently carrying a range marking
var _screen = null                # the map-hosted FormationDetailTransition — the surface's HOME
var _characters: Array = []       # one Character per unit — what the surface edits
var _last_rows: Array = []        # per-unit previous trace row, for change detection
var _trace: Array = []            # the whole per-tick trace of this boot


func _ready() -> void:
	_rlog = RegressionLogger.new("GambitLab", false)
	print("\n=== Gambit Lab (live arm) ===")
	if not _probe.load_layout():
		for c in _probe.reader.checks:
			if not c["ok"]:
				push_error("[GambitLab] %s" % c["what"])
		return

	await get_tree().process_frame
	await get_tree().process_frame
	# #589: hand the map's two outputs to the host systems that consume them.
	BattlefieldWiring.wire_map(map)
	var lat: Lattice = map.lattice
	lattice = lat
	if lattice == null:
		push_error("[GambitLab] no lattice after map build")
		return
	_highlights = map.highlights if ("highlights" in map) else null

	# The inherited legacy `CombatUI`, freed exactly as `GPUArena` and `GambitBattle` free
	# theirs (ADR-0137). It arrives from `assets/scenes/CombatCamera.tscn` — which 11 scenes
	# mount and, per that file's own header, "104 OF THE 107 CONSUMERS NEVER MENTION" — and
	# unbound it draws EIGHT EMPTY "Unit" CARDS down both edges of the screen, straight over
	# the margins this lab's readout wants. This is the THIRD copy of these five lines, which
	# `GambitBattle.gd` names as the signal to do ADR-0137's already-scoped global demolition
	# rather than copy a fourth time. Filed, not done here: making the lab usable is not the
	# change that should move 11 scenes.
	var legacy := get_node_or_null("PlayerCamera/FocusPoint/Camera/CombatUI")
	if legacy != null:
		legacy.get_parent().remove_child(legacy)
		legacy.queue_free()

	# THE CURSOR IS WHAT MAKES THE LAB DRIVABLE, and its absence is why WASD did nothing:
	# `PlayerCamera._execute_translation` returns early unless `free_camera()`, so in the
	# CURSOR mode the lab boots in, WASD is the CURSOR's walk and the camera only follows.
	# Mounted and bound the way the other four cursor-bearing scenes do it.
	if tile_cursor != null:
		cursor_rig = CursorRig.bind(self, tile_cursor, player_camera)
		BattlefieldWiring.wire_cursor(cursor_rig)
		cursor_rig.seed_from_map(map, Vector2i(0, 0))
	_mount_formation_map_screen()

	_scenarios = GambitScenarioBoot.load_scenarios()
	if _scenarios.is_empty():
		push_error("[GambitLab] no scenarios found under tests/gambit_scenarios/")
		return
	_fixture_count = _scenarios.size()
	# 🔴 THE SYNTHESIZED CELLS JOIN THE CORPUS; THEY DO NOT SIT BEHIND THEIR OWN FLAG.
	# `--cell=` booted one and `--cells` printed the census, and that was the whole of it:
	# `N`/`B` walked the 84 hand-authored fixtures and NOTHING in the scene could reach a
	# synthesized cell. So the arm that generates the positive case AND its mirror — dec. 2's
	# unit of evidence, the thing this instrument exists to make self-checking — was invisible
	# to the instrument, and the lab read as a fixed menu of somebody else's tests.
	#
	# ONE list, fixtures then cells, because dec. 13 already made them one experiment: a cell
	# spec carries a fixture-shaped `scenario` and [GambitScenarioBoot] boots it unchanged. A
	# second walker would be a second thing that can disagree about which battle is up.
	#
	# REFUSED cells are IN the list, not filtered out. dec. 10 makes the refusal the PRODUCT —
	# a cell that cannot be built without being nudged is a finding — and a walker that skipped
	# them would be the census lying by omission. They boot nothing and say why.
	_scenarios.append_array(GambitCellSynth.catalogue())
	# THE SCRATCH CELL — the corpus's LAST entry, and the only one you can edit (#1210).
	# Everything before it is somebody else's experiment: 92 hand-authored fixtures asserting
	# what the ROM does, and 29 synthesized cells whose whole value is that one knob moved. This
	# one is yours. It is a corpus entry rather than a mode so that `N`/`B`, `R`, the panel, the
	# trace and the verdict readout all reach it with no second code path — the same argument
	# Amendment 2 makes for the cells.
	#
	# dec. 17 is INTACT: there is still no save button. The scratch cell lives in memory and
	# dies with the process, which is exactly what dec. 17 asks for — its argument is against
	# COMMITTING a generated fixture ("if the behaviour being hunted was the bug, the click
	# commits a guard protecting it"), never against mutating a live cell.
	_scratch = _new_scratch()
	_scenarios.append(_scratch)
	_scratch_index = _scenarios.size() - 1
	_read_cmdline()

	if _coverage_mode:
		print("\n" + GambitCellSynth.coverage_line())
		get_tree().quit(0)
		return
	if _census_mode:
		_print_census()
		get_tree().quit(0)
		return

	_panel = preload("res://src/debug/GambitLabPanel.gd").new()
	_panel.setup(self)
	DebugOverlay.register_panel(_panel, DebugOverlay.Category.SIMULATION)
	DebugOverlay.show_overlay()
	DebugOverlay.switch_to_tab(DebugOverlay.Category.SIMULATION)

	await _boot(_index)
	# A synthesized cell knows its OWN tick budget — `GambitCellSynth.ticks_for_speed` derives it
	# from the actor's Speed, because the throw straddle (dec. 12) drops Speed to 8 and a unit at
	# Speed 8 needs 450 ticks to reach its first turn where one at 120 needs 30. A fixed
	# `--trace=60` would have made every throw cell read "NO VERDICT" and the conclusion would
	# have been about dec. 12 rather than about the budget.
	#
	# ⚠️ ARMED BY BARE `--trace`, NOT BY `--cell=`. It used to fire whenever a cell was booted
	# with no `--trace`, which made `--cell=` a batch-only flag that always quit — and the
	# docstring one screen up said the opposite: that `--cell=` boots a cell "exactly as
	# `--scenario=` boots a fixture". `--scenario=` stays up. The reason it could stay batch-only
	# was that the BATCH ARM WAS THE ONLY THING THAT SCORED; now the interactive arm scores on the
	# first evaluation too, so the trace has nothing left that it alone can do.
	if _trace_derived and not _cell.is_empty():
		_trace_ticks = int(_cell.get("ticks", GambitCellSynth.ticks_for_speed(
			int(_cell["actor_speed"]))))
		print("[cell] bare --trace; using the cell's own derived budget of %d ticks "
			% _trace_ticks + "(actor Speed %d)" % int(_cell["actor_speed"]))
	elif _trace_derived:
		_trace_ticks = DEFAULT_TRACE_TICKS
		print("[trace] bare --trace on a fixture; using %d ticks" % _trace_ticks)
	if _open_surface_at_boot:
		open_surface()
		await get_tree().process_frame
		_report_surface()
	if _shot_path != "":
		await _save_shot()
		get_tree().quit(0)
		return

	if _trace_ticks > 0:
		await _run_trace(_trace_ticks)
		get_tree().quit(0)


## `--scenario=<needle>` matches a fixture by `name` or by `rule`, case-insensitively;
## `--trace=<n>` arms the batch arm. Both are the tree's own form (18 files read
## `OS.get_cmdline_user_args()`); ADR-0051 bans env vars for scene configuration.
func _read_cmdline() -> void:
	for a in OS.get_cmdline_user_args():
		var arg: String = a
		if arg.begins_with("--scenario="):
			var needle := arg.substr("--scenario=".length()).to_lower()
			var found := _find_scenario(needle)
			if found < 0:
				push_error("[GambitLab] no fixture matches '%s'" % needle)
			else:
				_index = found
		elif arg == "--open-surface":
			_open_surface_at_boot = true
		elif arg.begins_with("--shot="):
			_shot_path = arg.substr("--shot=".length())
		elif arg == "--trace":
			# Bare: the budget is the ENTRY's, derived below once the boot knows which entry it
			# is. A cell's is `ticks_for_speed`; a fixture has no such number and takes the
			# constant.
			_trace_derived = true
		elif arg.begins_with("--trace="):
			_trace_ticks = maxi(1, arg.substr("--trace=".length()).to_int())
		elif arg.begins_with("--cell="):
			# One SYNTHESIZED cell, by a substring of its catalogue name. Deliberately the same
			# shape as `--scenario=` — the two arms differ in where the dict came from and in
			# nothing else, so a session that knows one knows the other.
			var cneedle := arg.substr("--cell=".length())
			var ci := _find_cell(cneedle)
			if ci < 0:
				push_error("[GambitLab] no synthesized cell matches '%s' — run with --cells to "
					% cneedle + "list the catalogue")
			else:
				_index = ci
		elif arg == "--cells":
			_census_mode = true
		elif arg == "--coverage":
			_coverage_mode = true


## A hand-authored FIXTURE by `name` substring or exact `rule`. Deliberately searches only the
## fixture half of the corpus: `--scenario=` and `--cell=` name two different populations, and a
## needle that happens to match both must not depend on which half is scanned first.
func _find_scenario(needle: String) -> int:
	for i in range(_fixture_count):
		var s: Dictionary = _scenarios[i]
		if String(s.get("name", "")).to_lower().contains(needle):
			return i
		if String(s.get("rule", "")).to_lower() == needle:
			return i
	return -1


## A SYNTHESIZED cell by a case-insensitive substring of its catalogue name
## (`cell/COND_MP_ABOVE/mirror`, `ladder/3_rungs`). The mirror of [method _find_scenario] over the
## other half, and it answers a corpus INDEX rather than the spec, so both flags land in the same
## place: `_index`, which is the one thing `_boot` reads.
func _find_cell(needle: String) -> int:
	var n := needle.to_lower()
	for i in range(_fixture_count, _scenarios.size()):
		if String(_scenarios[i].get("name", "")).to_lower().contains(n):
			return i
	return -1


## Is corpus entry [param idx] a synthesized cell rather than a hand-authored fixture?
## The SCRATCH cell is neither — it is a plain fixture-shaped dict with no axis and no
## prediction, so it must not answer true here or `_boot` would look for an `axis` it has not
## got.
func _is_cell(idx: int) -> bool:
	return idx >= _fixture_count and idx < _scenarios.size() and idx != _scratch_index


## Is corpus entry [param idx] the editable scratch cell?
func _is_scratch(idx: int) -> bool:
	return idx >= 0 and idx == _scratch_index


## Which of the corpus's three populations entry [param idx] belongs to, for the boot line and the
## panel. SCRATCH is asked FIRST: it sits past `_fixture_count` exactly as the cells do, so a bare
## "is it a cell" test calls it one.
func _kind_of(idx: int) -> String:
	if _is_scratch(idx):
		return "SCRATCH — yours"
	return "synthesized cell" if _is_cell(idx) else "fixture"


## What the readout and the boot line call entry [param idx]. A fixture is `rule/name`; a cell is
## its catalogue name, which already carries the opcode and the side (`cell/COND_MP_BELOW/mirror`)
## and is the name `--cell=` matches — so the scene names it the way the census does.
func _title_of(idx: int) -> String:
	if idx < 0 or idx >= _scenarios.size():
		return "?"
	var e: Dictionary = _scenarios[idx]
	if _is_scratch(idx):
		return "scratch/%s (%d unit%s)" % [e.get("from", "empty"),
			(e.get("units", []) as Array).size(),
			"" if (e.get("units", []) as Array).size() == 1 else "s"]
	if _is_cell(idx):
		return String(e.get("name", "cell?"))
	return "%s/%s" % [e.get("rule", "??"), e.get("name", "?")]


# =============================================================================================
# Boot
# =============================================================================================

## Stand the fixture at [param idx] up on ITS OWN map, paused at tick 0.
func _boot(idx: int) -> void:
	# 🔴 `_boot` IS A COROUTINE AND THE DRIVE KEYS ARE RE-ENTRANT, which is the whole of the
	# reported crash. It awaits once per unit inside `GambitScenarioBoot.spawn_unit`, so `N`
	# pressed again before the spawns finish starts a SECOND `_boot` INSIDE the first one's
	# await. Both write the same instance fields — `units`, `team0_units`, `team1_units`,
	# `_cfgs`, `_scenario` — so the loser resumes into the winner's arrays, appends its own
	# units to them, and hands `CombatLoop.start_battle` a `units` list and an `encoded`
	# gambit list that describe DIFFERENT battles. The symptom was
	# `arm_combat_gambits: Out of bounds get index '2' (on base: 'Array')`, reported from a
	# helper that names neither this function nor the race (fixed there too, to say so).
	#
	# A GENERATION TICKET, not a `_booting` no-op flag. Dropping the second press would make a
	# mashed `N` silently do nothing, which is a second bug wearing the first one's clothes.
	# Every boot takes the next ticket; after every await it checks whether it is still the
	# current one and abandons if not. **Last press wins**, which is what the key means.
	_boot_gen += 1
	var gen := _boot_gen
	_teardown()
	_index = clampi(idx, 0, _scenarios.size() - 1)
	# A synthesized cell supplies its own scenario dict, in the fixture's shape. The branch is
	# ONE line because that is the whole integration dec. 13 asks for: the synthesizer emits
	# what `GambitScenarioBoot` already boots. WHICH entry it is comes from the index alone, so
	# `--cell=` and `N` reach a cell by the same route and cannot disagree about `_cell`.
	_cell = _scenarios[_index] if _is_cell(_index) else {}
	_scenario = _cell["scenario"] if not _cell.is_empty() else _scenarios[_index]
	_cell_first = []
	_cell_first_tick = -1
	_scored = false
	_cell_score = {}
	_watched = 0
	_trace = []
	_last_rows = []
	_cfgs = []

	# dec. 10 — a refused cell is a FINDING, and walking onto one has to say so rather than boot
	# the last thing that worked or an empty field with no explanation. It stands on the corpus
	# because hiding it would make the walker disagree with the census about what exists.
	if not _cell.is_empty() and bool(_cell.get("refused", false)):
		_scenario = {}
		_current_map = ""
		print("\n[lab] %s — REFUSED, and never nudged (dec. 10):\n       %s"
			% [_title_of(_index), _cell.get("refusal", "?")])
		for n in _cell.get("notes", []):
			print("       | %s" % n)
		_refresh_panel()
		return

	var map_id: String = _scenario.get("map", "MAP042")
	if map_id != _current_map:
		map.change_map(map_id)
		await get_tree().process_frame
		if gen != _boot_gen:
			return
		# `map.lattice` is the SAME object across a change_map — the composer rebinds the
		# port onto the new store rather than replacing it, precisely so a handle taken at
		# boot keeps answering for the map on screen. Re-read anyway.
		var lat2: Lattice = map.lattice
		lattice = lat2
		_current_map = map_id

	# THE ORDER HERE IS THE GPU'S, NOT THE FIXTURE'S, and that is load-bearing for every
	# label this instrument prints. `GPUBatchSimulator.set_battle_units` writes team 0 into
	# unit indices 0..n0-1 and team 1 into n0..n0+n1-1 — contiguous, in TEAM order. A name
	# table built in the dict's own order is correct only while a fixture happens to list its
	# team-0 units first, and a fixture that does not would have every `target=` and every
	# row heading naming the wrong unit, in a trace whose whole job is to say WHO.
	# 🔴 SPAWNED INTO LOCALS AND PUBLISHED AT THE END, never appended to the instance fields as
	# they arrive. This is the other half of the generation guard and the half that actually
	# removes the hazard: the loop awaits once per unit, so a field written inside it is a field
	# two boots can be holding at once. Published only when the whole cast is standing, a
	# superseded boot has written NOTHING to share — and it knows exactly what it built, so it
	# can take its own cast down with it.
	#
	# Freeing on abandon is not housekeeping. A loser that returns without it leaves its
	# half-spawned units parented to this scene but absent from `units`, which makes them
	# invisible to the trace, to `_teardown`, to the range overlay and to every readout — and
	# permanent for the life of the process. Measured at **13 orphans after twelve mashed `N`
	# presses**, standing on the winner's map.
	var t0: Array = []
	var t1: Array = []
	var cfgs0: Array = []
	var cfgs1: Array = []
	var spawned_count := 0
	for cfg in _scenario.get("units", []):
		var spawned = await GambitScenarioBoot.spawn_unit(self, map, cfg, spawned_count)
		if gen != _boot_gen:
			if spawned != null and is_instance_valid(spawned):
				spawned.queue_free()
			_free_all(t0)
			_free_all(t1)
			return
		if spawned == null:
			push_error("[GambitLab] failed to spawn %s" % cfg.get("name", "?"))
			_free_all(t0)
			_free_all(t1)
			return
		spawned_count += 1
		if cfg.get("team", 0) == 0:
			t0.append(spawned)
			cfgs0.append(cfg)
		else:
			t1.append(spawned)
			cfgs1.append(cfg)
	# PUBLISHED — from here on the instance fields describe this boot and only this boot.
	team0_units = t0
	team1_units = t1
	_characters = []
	units = team0_units + team1_units
	_cfgs = cfgs0 + cfgs1
	_unit_names = []
	for i in range(_cfgs.size()):
		_unit_names.append(String(_cfgs[i].get("name", "Unit%d" % i)))
		_characters.append(_character_for(_cfgs[i]))
		# THE ONE LINK BETWEEN A BATTLEFIELD UNIT AND THE IDENTITY A SCREEN RENDERS.
		# `FormationMapHost.character_for_unit` reads this meta (falling back to the catalogue
		# SLUG), and `GambitScenarioBoot.spawn_unit` stamps neither — so without this line every
		# lab tile answers null, which on the map host is indistinguishable from an empty tile:
		# ○ and △ over a unit would do nothing, silently. The lab's Characters are synthesized
		# per boot and never enter [CharacterCatalog], so the meta is the only answer available.
		units[i].set_meta(UnitSpawn.CHARACTER_META, _characters[i])

	var encoded := GambitScenarioBoot.encode_units(_scenario)
	if int(encoded["skips"]) > 0:
		# dec. 22 — opcodes the encoder cannot emit are REPORTED, not bypassed. There is no
		# raw-opcode injection path into the gambit buffer, so a skip is a COVERAGE line.
		print("[lab] encoder skipped %d authored gambit(s) in this fixture — those slots are"
			% int(encoded["skips"]) + " empty on the GPU, and the verdict will say DISABLED")

	combat_loop = CombatLoopClass.new()
	combat_loop.name = "CombatLoop"
	combat_loop.battle_name = String(_scenario.get("name", "lab"))
	# The loop logs THROUGH this and does not null-check it: without one, the reaction path
	# (`CombatLoop._spawn_hit_cloud` -> `EffectManager.spawn_trap_effect`) raises
	# *"Nonexistent function 'log_effect' in base 'Nil'"* on the first physical hit. That is
	# a hole in the LAB, not a finding about the battle — but an instrument that throws on
	# the first swing is one whose silence later cannot be read.
	combat_loop._rlog = _rlog
	combat_loop.max_ticks = int(_scenario.get("max_ticks", 400))
	combat_loop.lattice = lattice
	add_child(combat_loop)

	var spec := GambitScenarioBoot.build_battle_spec(_scenario, lattice)
	combat_loop.start_battle(team0_units, team1_units, encoded["gambits"],
			lattice, map, _scenario.get("seed", 42), spec)
	_sync_loop_refs()
	# 🔴 BOUND HERE — AFTER `_sync_loop_refs` publishes `gpu_simulator`, and not lazily on the
	# first sample. `unit_name()` delegates to the probe and the probe knows no names until it is
	# bound, so a lazy bind makes every reader that runs BEFORE the first tick answer `u0`.
	# Measured: `--open-surface` printed *"mounted Node3D on u0"* where it had printed *"on
	# Wizard"*, because `_report_surface` runs at boot and no `_sample` had happened yet. In an
	# instrument whose whole job is to say WHO, that is not a cosmetic slip.
	#
	# The table is `_cfgs`' order — the GPU's TEAM order, not the fixture's — built that way
	# thirty lines up and for the same reason.
	_probe.bind(gpu_simulator, BATTLE, _unit_names)
	combat_active = true
	_running = false

	_apply_view()
	_paint_range()
	_center_cursor_on_watched()
	print("[lab] %s on %s — %d units, paused at tick 0 [%d/%d, %s]" % [
		_title_of(_index), map_id, units.size(), _index + 1, _scenarios.size(),
		_kind_of(_index)])
	if not _cell.is_empty():
		var ax: Dictionary = _cell["axis"]
		print("[cell] axis %s ci=%s knob %s=%s  |  %s" % [
			ax.get("opcode_name", "?"), str(ax.get("condition_index", "-")),
			ax.get("knob", "-"), str(ax.get("knob_value", "-")), ax.get("predicate", "")])
	_refresh_panel()


## Free every live node in [param nodes]. For a boot abandoning its own half-spawned cast — the
## instance fields are somebody else's by then, so `_teardown` cannot do it.
func _free_all(nodes: Array) -> void:
	for n in nodes:
		if n != null and is_instance_valid(n):
			n.queue_free()


func _teardown() -> void:
	_drop_surface()
	_clear_range()
	for child in get_children():
		if child is Label3D and String(child.name).begins_with("LabMarker"):
			child.queue_free()
	if combat_loop:
		combat_loop.queue_free()
		combat_loop = null
	for u in units:
		if is_instance_valid(u):
			u.queue_free()
	units = []
	team0_units = []
	team1_units = []


## A [Character] per unit — what [GambitSurface] edits (dec. 20). Seeded from the fixture's
## OWN authored `Gambit` objects, so opening the surface shows the rules the battle is under
## rather than an empty list.
func _character_for(cfg: Dictionary):
	var ch = Character.create_default(String(cfg.get("name", "Unit")),
		String(cfg.get("job", "4c")), false)
	var list := GambitList.new()
	for g in cfg.get("gambits", []):
		# 🔴 CLONED, NEVER SHARED — dec. 17 says the fixtures are READ-ONLY and until this line
		# they were not. `list.add(g)` added the FIXTURE'S OWN `Gambit` object, and
		# `GambitSurface`'s apply closures write it in place (`g.action_kind = picked["kind"]`).
		# So one edit through the editor permanently rewrote the corpus entry for the rest of
		# the process: press `N` and come back with `B` and your edit is still there, in a
		# fixture whose whole job is to assert what the ROM does.
		#
		# MEASURED, not reasoned about: `_characters[0].gambits.get_at(0)` and
		# `_scenarios[i]["units"][0]["gambits"][0]` were the same object, and setting
		# `action_kind` on the character changed the fixture's printed rule and survived a
		# re-boot of that fixture.
		#
		# It was latent for as long as the surface rendered nothing (ADR-0275 dec. 25) —
		# nobody could reach the editor to fire it. Making the surface work is what made it
		# live, so it is fixed in the same breath.
		#
		# `to_dict`/`from_dict` is the domain object's OWN round-trip and carries every field
		# (`enabled`, both TargetSelectors, the condition list, `action_kind`, `ability_id`).
		# It is not the "flat-dict shortcut" `GambitScenarioBoot` rejects: that one is about
		# bypassing [GambitEncoder] on the way to the GPU, and this clone still encodes through
		# it exactly as before.
		if g != null:
			list.add(Gambit.from_dict(g.to_dict()))
	list.ensure_fixed_size()
	ch.gambits = list
	return ch


# =============================================================================================
# Drive — the loop is pumped a TICK at a time, never a frame at a time
# =============================================================================================

## Override `CombatHost._process`, which pumps `combat_loop.tick(delta)` every frame. The lab
## is a lockstep instrument: a frame-driven pump advances a variable number of ticks per
## frame, and a per-tick trace taken off that cannot say WHICH tick a field moved on.
func _process(_delta: float) -> void:
	if _running:
		_step_one()


## Exactly one tick. `TICK_INTERVAL` is the loop's own fixed step and `playback_scale`
## defaults to 1.0, so the drain runs its body once and leaves the accumulator at zero.
func _step_one() -> void:
	if combat_loop == null:
		return
	combat_loop.tick(TICK_INTERVAL)
	_sample()
	_refresh_panel()


func _sample() -> void:
	var snap := _snapshot()
	if snap.is_empty():
		return
	var rows: Array = []
	for u in range(units.size()):
		rows.append(_row_for(u, snap))
	_trace.append({"tick": current_tick, "rows": rows})
	_last_rows = rows
	if not _cell.is_empty() and _cell_first.is_empty() and not rows.is_empty():
		# The actor is GPU unit 0 by construction (the cell spec lists it first and it is team 0,
		# and `set_battle_units` writes team 0 into indices 0..n0-1). Any slot turning non-NONE
		# means this call WALKED the actor's list, which is the tick the prediction is about.
		for d in (rows[0]["slots"] as Array):
			if int(d["p1"]) != 0:
				_cell_first = (rows[0]["slots"] as Array).duplicate(true)
				_cell_first_tick = current_tick
				# SCORE IT HERE, not only at the end of `--trace`. dec. 2's argument is that a
				# pair which fails to flip is a defect regardless of what anyone expected — and
				# that is only true if somebody COMPARES. The batch arm was the only thing that
				# did, so a cell walked to interactively showed its verdict columns and never
				# its PREDICTION, which is the half that makes the reading falsifiable.
				#
				# On the first evaluation because that is the one the prediction is about:
				# `clear_verdict` wipes and rewrites every slot the NEXT call walks.
				_score_cell()
				_scored = true
				break
	if _schematic:
		_apply_view()


func _snapshot() -> Dictionary:
	return _probe.snapshot()


# =============================================================================================
# The readout — the verdict, and the unit fields the verdict does NOT cover
# =============================================================================================

## One unit's whole per-tick picture: the kernel's per-slot verdicts PLUS the three unit
## fields a verdict cannot answer. The verdict says which slot committed and why the others
## declined; it says nothing about what happened to `U_TARGET` afterwards, and a target
## rewritten downstream of the decision is invisible to it.
func _row_for(unit: int, snap: Dictionary) -> Dictionary:
	return _probe.row_for(unit, snap)


func state_name(s: int) -> String:
	return _probe.state_name(s)


func reason_name(r: int) -> String:
	return _probe.reason_name(r)


func unit_name(u: int) -> String:
	return _probe.unit_name(u)


## Is this slot the ADR-0048 safety net? Its index is `MAX_USER_GAMBITS` — DERIVED (dec. 19),
## because a literal 5 is a number that stops being true the day the cap moves.
func is_safety_net_slot(slot: int) -> bool:
	return _probe.is_safety_net_slot(slot)


func verdict_reader() -> GambitVerdictReader:
	return _probe.reader




# =============================================================================================
# The batch arm — a per-tick reason trace, printed
# =============================================================================================

## Step [param ticks] ticks in lockstep and print every tick on which any watched field
## MOVED. A dump of every tick is unreadable and a dump of only the ticks you predicted is
## an answer you wrote yourself, so the filter is CHANGE — on state, target, reason, the
## committed slot, HP, position, or any slot's verdict word.
func _run_trace(ticks: int) -> void:
	# NOTHING IS UP, so there is nothing to trace. Reached by a REFUSED cell (dec. 10 — it boots
	# no battle by design) and by any `_boot` that returned early on a spawn failure. Without
	# this the loop below reads `_trace.back()` on an empty array and the run ends in a script
	# error, which reads as a defect in the thing being traced rather than as "this cell was
	# refused" — the refusal printed one line earlier and the error buried it.
	if combat_loop == null or units.is_empty():
		print("\n[trace] %s booted no battle — nothing to trace." % _title_of(_index))
		return
	print("\n[trace] %s — %d ticks, lockstep" % [_title_of(_index), ticks])
	print("[trace] units: %s" % ", ".join(_unit_names))
	print("[trace] columns: tick | unit | state | target | reason | slot | hp | (x,z)")
	_sample()
	_print_rows(_trace.back()["rows"], true)
	for _i in range(ticks):
		combat_loop.tick(TICK_INTERVAL)
		var prev: Array = _last_rows.duplicate(true)
		_sample()
		_print_rows_changed(prev, _trace.back()["rows"])
		await get_tree().process_frame
	print("[trace] ended at tick %d" % current_tick)
	_print_verdicts()
	# `_sample` already scored it the moment the actor was first evaluated. This is the
	# BLIND-RUN arm: a cell that never reached an evaluation inside the budget has no verdict
	# to score, and `_score_cell` says exactly that rather than letting the silence read as a
	# pass (dec. 18 — a zero from a blind instrument is not absence).
	if not _cell.is_empty() and not _scored:
		_score_cell()


func _print_rows(rows: Array, _first: bool) -> void:
	for r in rows:
		print(_fmt_row(r))


func _print_rows_changed(prev: Array, now: Array) -> void:
	for i in range(now.size()):
		if i >= prev.size() or _row_moved(prev[i], now[i]):
			print(_fmt_row(now[i]))


func _row_moved(a: Dictionary, b: Dictionary) -> bool:
	for k in ["state", "target", "reason", "gambit", "hp", "x", "z"]:
		if a[k] != b[k]:
			return true
	var sa: Array = a["slots"]
	var sb: Array = b["slots"]
	for i in range(sb.size()):
		if i >= sa.size():
			return true
		for f in GambitVerdictReader.FIELD_KEYS:
			if sa[i][f] != sb[i][f]:
				return true
		if sa[i]["payload"] != sb[i]["payload"]:
			return true
	return false


func _fmt_row(r: Dictionary) -> String:
	var head := "t%-4d %-16s %-16s target=%-14s reason=%-18s slot=%-3d hp=%-5d (%d,%d)" % [
		current_tick, r["name"], state_name(int(r["state"])),
		unit_name(int(r["target"])), reason_name(int(r["reason"])),
		int(r["gambit"]), int(r["hp"]), int(r["x"]), int(r["z"])]
	var lines: Array = [head]
	var slots: Array = r["slots"]
	for s in range(slots.size()):
		var d: Dictionary = slots[s]
		if int(d["p1"]) == 0 and int(d["p2"]) == 0 and int(d["payload"]) == 0:
			continue
		lines.append("        slot %d%s  %s" % [
			s, "  [safety net]" if is_safety_net_slot(s) else "", _probe.reader.format(d)])
	return "\n".join(lines)


## The final per-slot picture for every unit, printed whole — including the slots that never
## moved, so a slot the kernel never walked is VISIBLE as `NONE(not walked)` rather than
## absent. A zero from a blind instrument is not absence (dec. 18).
func _print_verdicts() -> void:
	print("\n[trace] final per-slot verdicts")
	if _last_rows.is_empty():
		print("  (no sample)")
		return
	for r in _last_rows:
		print("  %s (unit %d) state=%s target=%s reason=%s committed slot=%d" % [
			r["name"], int(r["unit"]), state_name(int(r["state"])),
			unit_name(int(r["target"])), reason_name(int(r["reason"])), int(r["gambit"])])
		var slots: Array = r["slots"]
		for s in range(slots.size()):
			print("    slot %d%s  %s" % [
				s, "  [safety net]" if is_safety_net_slot(s) else "",
				_probe.reader.format(slots[s])])


# =============================================================================================
# The SYNTHESIZED arm — the census, and scoring one cell's prediction (#1129)
# =============================================================================================

## The whole catalogue, printed, with the refusals IN the list rather than filtered out of it.
##
## dec. 9's refusal count is a to-do list, so a census that hid the refusals would be hiding the
## product. No GPU, no tick: the synthesizer is a pure function and this arm exercises all of it.
func _print_census() -> void:
	var cells := GambitCellSynth.catalogue()
	print("\n=== the synthesizer's census (ADR-0275 decs. 1/2/8-12) ===")
	print("map %s, actor at (%d,%d), Manhattan max %d, CARDINAL max %d" % [
		GambitCellSynth.MAP, GambitCellSynth.ORIGIN_X, GambitCellSynth.ORIGIN_Z,
		GambitCellSynth.MAX_SEPARATION, GambitCellSynth.MAX_CARDINAL])
	var built := 0
	var refused := 0
	for c in cells:
		if bool(c["refused"]):
			refused += 1
			print("  REFUSED  %-52s %s" % [c["name"], c["refusal"]])
		else:
			built += 1
			var ax: Dictionary = c["axis"]
			var kv = ax.get("knob_value", null)
			print("  built    %-52s sep=%-2d speed=%-4d knob=%s" % [
				c["name"], int(c["separation"]), int(c["actor_speed"]),
				"-" if kv == null else "%s=%s" % [ax.get("knob", "-"), str(kv)]])
		for n in c["notes"]:
			print("               | %s" % n)
	print("\n%d cells built, %d REFUSED and counted (dec. 10 — never nudged)." % [built, refused])
	print("\n" + GambitCellSynth.coverage_line())


## Score the booted cell's prediction against what the kernel actually wrote.
##
## 🔴 THIS IS THE HALF THAT MAKES A MIRROR WORTH GENERATING. dec. 2's argument is that a PAIR
## that fails to flip is a defect regardless of what anyone expected — which is only true if
## somebody compares. Every row of the spec's `expect` names a decoded FIELD and an exact value,
## never nonzero-ness: `VERDICT_NONE == 0` is a real answer ("this call did not walk this slot"),
## so an instrument that scored "something was written" would pass on a write that never fired.
func _score_cell() -> void:
	print("\n[cell] %s" % _cell["name"])
	var ax: Dictionary = _cell["axis"]
	print("[cell] axis %s ci=%s knob %s=%s  |  %s" % [
		ax.get("opcode_name", "?"), str(ax.get("condition_index", "-")),
		ax.get("knob", "-"), str(ax.get("knob_value", "-")), ax.get("predicate", "")])
	print("[cell] int B measures: %s" % ax.get("measures", "?"))
	if _cell_first.is_empty():
		_cell_score = {"scored": false, "pass": 0, "fail": 0, "tick": -1}
		# The budget is `--trace`'s on the batch arm and "however far you have stepped" on the
		# interactive one, so SAY WHICH — a "never evaluated inside 0 ticks" line read as a
		# failed prediction when the honest answer was "you have not stepped far enough yet".
		var budget := ("%d ticks" % _trace_ticks) if _trace_ticks > 0 \
			else "the %d tick(s) stepped so far" % current_tick
		print("[cell] 🔴 NO VERDICT — the actor was never evaluated inside %s. That is not "
			% budget + "a failed prediction, it is a BLIND run: nothing here can be scored, "
			+ "and a zero from a blind instrument is not absence.")
		if _trace_ticks <= 0:
			print("[cell] this cell's own derived budget is %d ticks (actor Speed %d) — step or "
				% [int(_cell.get("ticks", GambitCellSynth.ticks_for_speed(
					int(_cell["actor_speed"])))), int(_cell["actor_speed"])]
				+ "ENTER to run there.")
		_refresh_panel()
		return
	print("[cell] scored at tick %d — the FIRST evaluation, because clear_verdict rewrites every "
		% _cell_first_tick + "slot the next one walks")
	var pass_n := 0
	var fail_n := 0
	for e in _cell["expect"]:
		var slot: int = int(e["slot"])
		if slot >= _cell_first.size():
			print("  FAIL slot %d is past MAX_GAMBITS" % slot)
			fail_n += 1
			continue
		var d: Dictionary = _cell_first[slot]
		var problems: Array = []
		if e.has("p1"):
			var want: int = int(_probe.reader.code_of.get(String(e["p1"]), -1))
			if int(d["p1"]) != want:
				problems.append("p1 is %s, predicted %s" % [
					_probe.reader.verdict_name(int(d["p1"])), e["p1"]])
		for f in ["ci", "op", "payload"]:
			if e.has(f) and int(d[f]) != int(e[f]):
				problems.append("%s is %d, predicted %d" % [f, int(d[f]), int(e[f])])
		if problems.is_empty():
			pass_n += 1
			print("  PASS slot %d%s  %s" % [slot,
				"  [safety net]" if is_safety_net_slot(slot) else "", e.get("why", "")])
		else:
			fail_n += 1
			print("  FAIL slot %d%s  %s" % [slot,
				"  [safety net]" if is_safety_net_slot(slot) else "", ", ".join(problems)])
			print("       predicted: %s" % e.get("why", ""))
			print("       measured:  %s" % _probe.reader.format(d))
	_cell_score = {"scored": true, "pass": pass_n, "fail": fail_n, "tick": _cell_first_tick}
	_refresh_panel()
	print("[cell] %d predicted field-sets held, %d did not." % [pass_n, fail_n])
	if fail_n > 0:
		print("[cell] A cell whose prediction misses is a FINDING about one of three things: the "
			+ "kernel, the straddle row, or the board. It is never evidence the cell should be "
			+ "nudged until it passes (dec. 10).")


# =============================================================================================
# The view — schematic by default, sprites on request
# =============================================================================================

## Schematic is the DEFAULT because the question is "which rule fired and why", and a sprite
## standing on a tile answers neither. The sprite render is a toggle for the one cell being
## watched (dec. 13's shape), not a second mode with its own behaviour: the same battle is
## running either way and only the unit visuals change.
func _apply_view() -> void:
	for i in range(units.size()):
		var u = units[i]
		if not is_instance_valid(u):
			continue
		# The whole unit hides, and the marker is NOT one of its children — a marker parented
		# to the thing it labels disappears with it, which is how a schematic view ends up
		# rendering nothing and reading as a dead scene.
		u.visible = not _schematic
		_ensure_marker(u, i)


func _ensure_marker(unit: Node3D, idx: int) -> void:
	var name := "LabMarker%d" % idx
	var marker: Label3D = get_node_or_null(name)
	if marker == null:
		marker = Label3D.new()
		marker.name = name
		marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		marker.no_depth_test = true
		marker.fixed_size = true
		marker.pixel_size = 0.004
		add_child(marker)
	marker.visible = _schematic
	marker.global_position = unit.global_position + Vector3(0, 1.4, 0)
	var team0: bool = team0_units.has(unit)
	marker.modulate = Color(0.55, 0.85, 1.0) if team0 else Color(1.0, 0.6, 0.55)
	marker.text = "%s%s" % [unit_name(idx), "  <" if idx == _watched else ""]


## Paint the watched actor's MOVE reach and WEAPON reach. The two markings are the
## placement vocabulary (`PLACEMENT_PLAYER` / `PLACEMENT_ENEMY`) because that is the marking
## set `TileHighlights` arbitrates — the lab borrows the colours, and the panel is what says
## which is which. Reach is Manhattan against the fixture's own `move` / `weapon_range`.
## Put the cursor — and so the CAMERA, which follows it in cursor mode — on the watched
## actor's tile.
##
## 🔴 SEEDING (0,0) FRAMES THE MAP CORNER, NOT THE SUBJECT. A battle can seed the origin
## because it recentres on the turn taker a moment later; this lab has no taker and never
## moves the camera again. Measured on the first boot with a cursor mounted: the capture was
## empty sky with the map's corner in one edge, and both units off screen. The tile field is
## the same one `_paint_range` reads, so the cursor lands where the reach overlay is drawn.
func _center_cursor_on_watched() -> void:
	if cursor_rig == null or _watched >= _cfgs.size():
		return
	var tile: Array = _cfgs[_watched].get("tile", [0, 0])
	cursor_rig.seed_from_map(map, Vector2i(int(tile[0]), int(tile[1])))


func _paint_range() -> void:
	_clear_range()
	if _highlights == null or _watched >= units.size():
		return
	if _watched >= _cfgs.size():
		return
	var cfg: Dictionary = _cfgs[_watched]
	var tile: Array = cfg.get("tile", [0, 0])
	var ox: int = int(tile[0])
	var oz: int = int(tile[1])
	var move: int = int(cfg.get("move", 4))
	var reach: int = int(cfg.get("weapon_range", 1))
	var lat: Lattice = lattice
	for c in lat.all_cells():
		if c.grid.z != 0 or c.impassable:
			continue
		var d: int = absi(c.grid.x - ox) + absi(c.grid.y - oz)
		if d == 0:
			continue
		var kind = CellMarking.Kind.NONE
		if d <= reach:
			kind = CellMarking.Kind.PLACEMENT_ENEMY
		elif d <= move:
			kind = CellMarking.Kind.PLACEMENT_PLAYER
		if kind != CellMarking.Kind.NONE:
			_highlights.paint(c.grid, kind)
			_painted.append({"cell": c.grid, "kind": kind})


func _clear_range() -> void:
	if _highlights != null:
		for p in _painted:
			_highlights.clear(p["cell"], p["kind"])
	_painted = []


# =============================================================================================
# THE SCRATCH CELL — build your own battle (#1210)
# =============================================================================================
#
# The lab was a corpus you could only FLIP THROUGH. Every gambit was already written and every
# unit already placed, so the one question a human actually arrives with — *what happens if I put
# THIS rule on THAT unit standing THERE* — could only be asked by editing a fixture on disk and
# restarting.
#
# Gambits were already answered: dec. 20's editor writes through [GambitEncoder] to the live GPU
# on every keystroke. The missing half was the ROSTER, and it is missing for a structural reason
# rather than an oversight: units are spawned from the cell dict at boot, so placing one is not a
# runtime operation. That shapes everything below.
#
# ⚠️ EVERY ROSTER EDIT RE-BOOTS, and that is not laziness. `GPUBatchSimulator.set_battle_units`
# SIZES the battle's buffers, so the roster is fixed from that call until the next one — a unit
# added afterwards has nowhere to live and is dropped silently, which is the worst available
# failure. A re-boot is ~2 s and re-seeds the battle at tick 0, which is what you want anyway:
# you are asking a question about an opening position.
#
# MOVING is the exception that proves it — a teleport seam exists — but it re-boots too, so that
# "the cell on screen is the cell in the dict" needs no caveat. One rule, no exceptions to
# remember.

## A fresh, empty scratch cell, fixture-shaped. `rule`/`name` are what [method _title_of] and the
## trace print; `from` records what it was forked out of, so a cell you built an hour ago still
## says where it came from.
func _new_scratch() -> Dictionary:
	return {
		"rule": "scratch",
		"name": "my cell",
		"from": "empty",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 400,
		"units": [],
	}


## `F` — fork whatever is booted into the scratch cell, and boot that. The usual way in: starting
## from a battle that already works beats starting from an empty map, because a cell with no units
## has nothing to step and nothing to read.
##
## DEEP — the unit dicts are duplicated and every [Gambit] is cloned through its own
## `to_dict`/`from_dict`. A shallow fork would hand the scratch cell the FIXTURE'S rule objects
## and the editor writes them in place, so editing your copy would rewrite the original — the
## exact defect [method _character_for] documents, one level up.
func fork_into_scratch() -> void:
	var src: Dictionary = _scenario
	if src.is_empty() or (src.get("units", []) as Array).is_empty():
		print("[scratch] nothing to fork — %s stood no units up" % _title_of(_index))
		return
	_scratch["from"] = _title_of(_index)
	_scratch["map"] = src.get("map", "MAP042")
	_scratch["seed"] = src.get("seed", 42)
	_scratch["max_ticks"] = src.get("max_ticks", 400)
	var out: Array = []
	for cfg in src.get("units", []):
		out.append(_clone_unit_cfg(cfg))
	_scratch["units"] = out
	print("[scratch] forked %s — %d unit(s). It is corpus entry %d; `R` re-boots it."
		% [_scratch["from"], out.size(), _scratch_index + 1])
	await _boot(_scratch_index)


## One unit cfg, deep. `duplicate(true)` does NOT clone Objects — it copies the REFERENCE — so the
## gambit list is rebuilt through the domain object's own round-trip.
func _clone_unit_cfg(cfg: Dictionary) -> Dictionary:
	var out: Dictionary = cfg.duplicate(true)
	var gs: Array = []
	for g in cfg.get("gambits", []):
		if g != null:
			gs.append(Gambit.from_dict(g.to_dict()))
	out["gambits"] = gs
	return out


## The tile the cursor is standing on — the scratch verbs' one input. Null when there is no rig.
func _cursor_tile() -> Variant:
	if cursor_rig == null or not is_instance_valid(cursor_rig):
		return null
	return cursor_rig.grid_pos


## `1` / `2` — add a unit of [param team] at the cursor tile.
##
## It arrives with `Attack / Any Enemy / Always`, not an empty list. An empty list is padded to
## four `Self / Always / Wait` rows by `ensure_fixed_size`, so a blank unit STANDS THERE DOING
## NOTHING and reads as a broken lab rather than as an unwritten rule. One working rule is the
## honest default, and `G` rewrites it.
func scratch_add_unit(team: int) -> void:
	if not _require_scratch("add a unit"):
		return
	var tile = _cursor_tile()
	if tile == null:
		return
	if _scratch_unit_at(tile) != null:
		print("[scratch] (%d,%d) is occupied — `X` clears it first" % [tile.x, tile.y])
		return
	var units_arr: Array = _scratch["units"]
	units_arr.append({
		"name": "%s%d" % ["Ally" if team == 0 else "Foe", _scratch_team_count(team) + 1],
		"team": team,
		"tile": [int(tile.x), int(tile.y)],
		"job": SCRATCH_JOB,
		"max_hp": 200, "hp": 200, "max_mp": 50, "mp": 50,
		"speed": 100, "move": 4, "jump": 3,
		"gambits": [Gambit.create(TargetSelector.enemies(), [GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1, TargetSelector.triggering())],
	})
	print("[scratch] added %s at (%d,%d) — %d unit(s)"
		% [units_arr[-1]["name"], tile.x, tile.y, units_arr.size()])
	await _boot(_scratch_index)


## `X` — delete the unit standing on the cursor tile.
func scratch_delete_unit() -> void:
	if not _require_scratch("delete a unit"):
		return
	var tile = _cursor_tile()
	if tile == null:
		return
	var cfg = _scratch_unit_at(tile)
	if cfg == null:
		print("[scratch] nothing on (%d,%d)" % [tile.x, tile.y])
		return
	(_scratch["units"] as Array).erase(cfg)
	print("[scratch] deleted %s — %d unit(s) left"
		% [cfg.get("name", "?"), (_scratch["units"] as Array).size()])
	await _boot(_scratch_index)


## `M` — move the WATCHED unit to the cursor tile. The watched unit rather than the one under the
## cursor, because the cursor is the destination: you cannot point at both ends with one cursor,
## and `TAB` already names the subject.
func scratch_move_watched() -> void:
	if not _require_scratch("move a unit"):
		return
	var tile = _cursor_tile()
	if tile == null:
		return
	var units_arr: Array = _scratch["units"]
	if _watched >= _cfgs.size():
		return
	# `_cfgs` is in the GPU's TEAM order and `_scratch["units"]` is in authoring order, so the
	# watched index cannot be used against the scratch array. Match by identity — `_boot` builds
	# `_cfgs` out of the very dicts `_scratch["units"]` holds, so this is the same object.
	var cfg = _cfgs[_watched]
	if not units_arr.has(cfg):
		print("[scratch] the watched unit is not this cell's — re-boot it with `R`")
		return
	var occupant = _scratch_unit_at(tile)
	if occupant != null and occupant != cfg:
		print("[scratch] (%d,%d) is occupied by %s" % [tile.x, tile.y, occupant.get("name", "?")])
		return
	cfg["tile"] = [int(tile.x), int(tile.y)]
	print("[scratch] moved %s to (%d,%d)" % [cfg.get("name", "?"), tile.x, tile.y])
	await _boot(_scratch_index)


## `J` — cycle the job of the unit under the cursor through the generic roster. The job drives the
## sprite AND `initialize_with_progression`, so it moves the unit's stats as well as its look —
## which is the point: a Knight and a Wizard are different experiments.
func scratch_cycle_job() -> void:
	if not _require_scratch("change a job"):
		return
	var tile = _cursor_tile()
	if tile == null:
		return
	var cfg = _scratch_unit_at(tile)
	if cfg == null:
		print("[scratch] nothing on (%d,%d)" % [tile.x, tile.y])
		return
	var ids: Array = JobDatabase.get_all_generic_jobs().keys()
	ids.sort()
	if ids.is_empty():
		push_warning("[scratch] the job database is empty — `J` has nothing to cycle")
		return
	var at := ids.find(String(cfg.get("job", SCRATCH_JOB)))
	cfg["job"] = String(ids[(at + 1) % ids.size()])
	print("[scratch] %s is now job %s" % [cfg.get("name", "?"), cfg["job"]])
	await _boot(_scratch_index)


## The scratch cell's unit cfg standing on [param tile], or null.
func _scratch_unit_at(tile: Vector2i):
	for cfg in _scratch.get("units", []):
		var t: Array = cfg.get("tile", [0, 0])
		if int(t[0]) == tile.x and int(t[1]) == tile.y:
			return cfg
	return null


func _scratch_team_count(team: int) -> int:
	var n := 0
	for cfg in _scratch.get("units", []):
		if int(cfg.get("team", 0)) == team:
			n += 1
	return n


## The scratch verbs edit the BOOTED cell, so they refuse anywhere else — loudly, naming the way
## in. Silently editing a scratch cell you are not looking at is the shape where a user presses a
## key, sees nothing change, and concludes the lab is broken.
func _require_scratch(verb: String) -> bool:
	if _is_scratch(_index):
		return true
	print("[scratch] `%s` edits the SCRATCH cell and you are on %s — press `F` to fork this "
		% [verb, _title_of(_index)] + "one into it first.")
	return false


# =============================================================================================
# The real editor (dec. 20)
# =============================================================================================

## Mount the map-hosted Formation coordinator (ADR-0137) — the screen [GambitSurface] is a part
## of, over this lab's own battlefield, exactly as [GambitBattle] and [GPUArena] mount it.
##
## 🔴 THIS IS ADR-0275 dec. 25 — THE SETTLED ANSWER TO THE TRIAL dec. 20 ASKED FOR.
## dec. 20 said to decide the mount by TRYING, and the hand-rolled one it shipped —
## `add_child(GambitSurface.new())` onto this scene root — **rendered nothing**. Measured: the
## viewport before and after `G` was byte-identical while the scene reported four rows built and
## `visible = true`. The surface was at the world ORIGIN with a camera at tile (4,7).
##
## Two causes, and either alone is fatal:
##
##   1. **Position.** The screen is authored in display pixels under an ORTHOGRAPHIC camera and
##      has to be a CHILD of that camera carrying the mount transform
##      ([method FormationMapHost.apply_mount_transform] — ×1.3125 here, because this lab's
##      camera runs `size = 12.6` against the authored 9.6). A scene root is neither.
##   2. **The CLIP BASIS, which no amount of repositioning fixes.**
##      `UI3ClipEngine.clip_basis_inv_for` walks an element's ancestors for the nearest node
##      answering `screen_to_world(px, py)` and takes its transform as the basis; finding none it
##      falls back to `Transform3D.IDENTITY`. This scene root declares no such method, so every
##      `OWN_APERTURE`/`PARENT_APERTURE` fragment of the surface was compared against a basis off
##      by the whole placement and DISCARDED. That is ADR-0137 Amendment 2's bug, in a third
##      caller. [FormationDetailTransition] declares `screen_to_world` precisely to be that basis.
##
## So the fix is not a better hand-rolled mount; it is to stop having one. A second mount is a
## second thing to keep correct, which is the same argument dec. 20 makes for keeping the real
## editor rather than a debug-panel picker — one rung up.
##
## The cursor is what made this possible only now: `mount_over_map` requires a [CursorRig], and
## the lab had no cursor until #1183.
func _mount_formation_map_screen() -> void:
	var cam := player_camera as CharacterBody3D
	if cam == null or cursor_rig == null:
		push_warning("[GambitLab] no PlayerCamera/cursor rig — `G` will have nowhere to mount")
		return
	_screen = FormationDetailTransitionScript.mount_over_map(
		cam, cursor_rig, _unit_at_grid, _set_screen_pause)
	if _screen == null:
		return
	# HOST-side panel mount (#1267). The lab's screen is the same `FormationMapHost`, so it
	# carried the same three F3 panels out of `FormationScene._ready()` until that call was
	# deleted. This scene is `src/scenes/`, not a `UI` member, so it may name `src/debug/`.
	FormationDebugPanels.register_formation_panels(_screen.formation())
	# Every edit re-encodes through [GambitEncoder] and goes straight to the GPU, so the very
	# next tick runs under the rule you just wrote (dec. 20). Taken off the COORDINATOR's
	# re-emission rather than off the surface, because the surface is built and freed per open
	# and a connection made per open is one that can be made twice or not at all.
	_screen.gambit_edited.connect(_on_gambit_edited)
	_screen.settled.connect(_on_screen_settled)


## Which unit is standing on `grid_pos` — this scene's own answer, handed to the map host so the
## screen never has to know how a lab stores its units. Same shape as
## `GambitBattle._unit_at_grid`, minus the deployment phase this scene does not have.
func _unit_at_grid(grid_pos: Vector2i):
	for u in units:
		if u == null or not is_instance_valid(u):
			continue
		var cell: Vector3i = u.get_current_cell()
		if Vector2i(cell.x, cell.y) == grid_pos:
			return u
	return null


## ADR-0037 pause, as this lab spells it. The lab's clock is `_running` (dec. 13's lockstep
## pump), not a `combat_active` flag, so a screen standing over the battlefield stops the pump
## and `✕` starts it again only if it was running when the screen went up.
func _set_screen_pause(paused: bool) -> void:
	if paused:
		_running_before_screen = _running
		_running = false
	else:
		_running = _running_before_screen
	_refresh_panel()


## What the pump was doing when a screen went up, so closing it can put that back.
var _running_before_screen := false


## The coordinator reached a resting screen. The only thing this lab wants from it is the
## PANEL's `surface_open` line staying true, and the surface going away on the way back to IDLE.
func _on_screen_settled(_to) -> void:
	_refresh_panel()


## The open [GambitSurface], or null — owned by the coordinator, never by this scene.
func surface():
	if _screen == null or not is_instance_valid(_screen):
		return null
	return _screen.gambit_surface()


## Open the REAL [GambitSurface] on the watched actor — not a debug-panel picker. A panel
## building [Gambit] objects directly routes around [GambitEncoder], and editor->encoder
## drift is a bug class this instrument exists to catch, so excluding it by construction
## would defeat the purpose.
##
## Straight to `State.GAMBIT`, over the running battlefield — NOT through the cursor's own door.
## ○/△ on a tile emits `unit_activated`, which the coordinator turns into `enter(State.DETAIL)`,
## and settled Status tiles four opaque frames across `y32..231`: it would cover the battle this
## lab exists to let you watch, and cost two more presses to reach the gambit row. Both doors
## work here — the cursor's is still wired, and ○ on a unit opens its Status screen — but `G` is
## the lab's verb and it lands on the list.
func open_surface() -> void:
	if _screen == null or not is_instance_valid(_screen):
		push_warning("[GambitLab] no formation screen mounted — nothing to open `G` on")
		return
	if _watched >= _characters.size() or _watched >= units.size():
		return
	if _screen.current_state() != FormationDetailTransitionScript.State.IDLE:
		return
	# The map host learns its selection from the tile cursor, and `G` makes no cursor gesture —
	# so say who, in the seam that says it without announcing an open.
	var host = _screen.formation()
	if host == null or not is_instance_valid(host):
		return
	_center_cursor_on_watched()
	host.select_character(_characters[_watched], units[_watched])
	_screen.enter(FormationDetailTransitionScript.State.GAMBIT)
	_refresh_panel()


## dec. 20 said to decide the mount by TRYING; Amendment 1 is that trial's verdict. This prints
## what the real surface actually built, so "it mounted" is a count of rows and not an impression — and, since Amendment 1,
## WHERE it built: a surface at the world origin under a camera at tile (4,7) is the empty-screen
## signature, and printing the global position is what made that legible.
func _report_surface() -> void:
	var surf = surface()
	if surf == null or not is_instance_valid(surf):
		print("[surface] NOT MOUNTED")
		return
	var ch = _characters[_watched]
	print("[surface] mounted %s on %s — parent %s, global %s, %d Node3D children, %d rows, "
		% [surf.get_class(), unit_name(_watched),
			surf.get_parent().name if surf.get_parent() != null else "<none>",
			str(surf.global_position), surf.get_child_count(),
			ch.gambits.size() if ch.gambits != null else 0]
		+ "net row index %d" % surf.safety_net_row_index())
	for i in range(ch.gambits.size() if ch.gambits != null else 0):
		var g = ch.gambits.get_at(i)
		# An `ensure_fixed_size` pad is `Self / Always / Wait` and prints as a real rule, so
		# say which rows are PADS — otherwise a one-gambit unit reads as a four-gambit one.
		var tag := ""
		if g == null:
			tag = "---"
		else:
			tag = "%s%s" % [str(g), "   [pad — not authored]" if g.is_empty() else ""]
		print("[surface]   slot %d: %s" % [i, tag])


## 🔴 THE ONLY INSTRUMENT THAT CAN ANSWER "DOES THIS SCREEN DRAW", and the reason it is a scene
## arm rather than a test. ADR-0275 dec. 15 keeps lab arms out of the suite, and the suite could
## not see this anyway: every assertion available to it — child count, `visible`, row count,
## `safety_net_row_index()` — was TRUE for a surface that rendered nothing at all for the whole
## life of dec. 20's hand-rolled mount. The frame is the referee.
##
## Godot must run headful here, so the capture is taken from INSIDE the process rather than by the
## compositor: `grim` aimed at an off-screen window silently returns the ACTIVE workspace instead,
## which looks exactly like a successful capture of the wrong thing.
##
##     godot --path . assets/scenes/GambitLab.tscn -- --scenario=A1 --open-surface --shot=surf.png
##
## A bare filename lands in `user://` (`~/.local/share/godot/app_userdata/learning/`); an absolute
## path is written where it says.
func _save_shot() -> void:
	# Three frames, not one: the coordinator builds its host a frame after `add_child`, the
	# surface builds its rows a frame after that, and `_relayout` places them on the frame after
	# THAT. A capture taken too early is an empty screen for a reason that has nothing to do with
	# the mount, which is the confusion this instrument exists to end.
	for _i in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := _shot_path if _shot_path.begins_with("/") or _shot_path.contains("://") \
		else "user://%s" % _shot_path
	var err := img.save_png(path)
	if err != OK:
		push_error("[GambitLab] --shot: could not write %s (%d)" % [path, err])
		return
	print("[shot] wrote %s — %dx%d" % [ProjectSettings.globalize_path(path),
		img.get_width(), img.get_height()])


## Close whatever the coordinator has up, through its OWN back grammar (ADR-0261) — never by
## freeing the surface behind its back, which would leave the stack claiming a screen that is
## gone and the camera takeover held forever.
func _drop_surface() -> void:
	if _screen == null or not is_instance_valid(_screen):
		return
	if _screen.current_state() != FormationDetailTransitionScript.State.IDLE:
		_screen.unwind_all()


## An edit landed. Re-encode the watched actor's whole list through [GambitEncoder] and push
## it at the live battle. The safety net is re-appended by the encoder itself, which is why
## this does not add one: dec. 19 labels the net, it does not own it.
func _on_gambit_edited(_slot: int) -> void:
	if gpu_simulator == null or _watched >= _characters.size():
		return
	var ch = _characters[_watched]
	# EMPTY SLOTS ARE FILTERED, and this line is the drift dec. 20 said the mount exists to
	# catch — caught here on the first mount, in this file. `GambitSurface._ready` calls
	# `GambitList.ensure_fixed_size()`, which pads the list to four with `Gambit.new()`:
	# Self / Always / Wait, and `enabled = true`. Nothing in `_encode_from_gambit_object`
	# consults `is_empty()`, so a padded slot encodes to a LIVE unconditional WAIT — and the
	# kernel walks slots ascending and takes the first match, so one of those pre-empts every
	# lower slot INCLUDING ADR-0048's safety net at `MAX_USER_GAMBITS`. Editing slot 0 on a
	# one-gambit unit would have silently installed three WAITs and stopped it fighting.
	# `GambitEncoder.authored_gambits` is the production path's filter; it reads
	# `unit.gambit_list` and this holds a `Character`, so the predicate is reused rather than
	# the function — one definition of "empty", which is the `is_empty()` the filter names.
	#
	# ⚠️ AND IT CANNOT BE FIXED INSIDE THE ENCODER, which is where the next reader will reach
	# first. `is_empty()` matches `Self / Always / Wait` — and that is EXACTLY what an
	# AUTHORED wait looks like; B7's two knights are written with one. The value does not
	# carry the difference between "the player wrote WAIT here" and "`ensure_fixed_size`
	# filled this in", so only the boundary that knows which list it is holding can tell
	# them apart. Filtering in `encode_gambits` would silently strip every authored WAIT in
	# the corpus and make those knights fight.
	var authored: Array = []
	if ch.gambits != null:
		for i in range(ch.gambits.size()):
			var g = ch.gambits.get_at(i)
			if g != null and not g.is_empty():
				authored.append(g)
	var encoded := GambitEncoder.encode_gambits(authored)
	gpu_simulator.set_unit_gambits(BATTLE, _watched, encoded)
	print("[lab] re-encoded %s's %d authored slot(s) (empties filtered) and pushed them to the"
		% [unit_name(_watched), authored.size()] + " live battle")
	_refresh_panel()


# =============================================================================================
# Controls
# =============================================================================================

## 🔴 `_shortcut_input`, NOT `_unhandled_input`, AND THE CURSOR IS WHY.
##
## `TileCursor._unhandled_input` claims the cursor verbs — confirm, inspect, cancel — and
## calls `set_input_as_handled()` on each. Godot walks `_unhandled_input` bottom-up, so the
## CURSOR (a child) is asked before this SCENE ROOT is, and the lab's `ENTER` (run/pause) and
## `TAB` (cycle the watched actor) were swallowed before they arrived. Measured, in-process,
## with no window manager in the picture: with the cursor mounted 3 of 5 keys reached this
## handler; with the cursor removed, 5 of 5 did; moved here, 5 of 5 with the cursor mounted.
##
## `_shortcut_input` runs BEFORE `_unhandled_input`, so the lab wins the two keys it names in
## its own docstring and the cursor keeps everything else — WASD still walks it, because this
## handler consumes only `LAB_KEYS` and lets every other press fall through.
##
## Confirming a TILE means nothing here: the lab watches one synthesized cell and never asks
## the user to pick anything, which is why taking ENTER from the cursor costs this scene
## nothing. A scene where confirm IS a verb must not copy this — [GambitBattle] listens to
## `cursor_rig.cursor_confirmed` instead, and that is the right shape when the verb is real.
func _shortcut_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	# 🔴 THIS BRANCH IS A BACKSTOP, NOT THE GATE, and reading it as the gate is a mistake this
	# comment exists to stop. An open screen owns the WHOLE pad from `FormationDetailTransition._input`
	# (ADR-0137: a wholesale claim, mouse and F3 exempt), and `_input` runs BEFORE `_shortcut_input`
	# — so while the surface is up this handler is not called at all. It stands because the claim
	# is the coordinator's to make and this scene must not depend on it having been made.
	#
	# ✕ is BACKSPACE, not Escape (`project.godot`: `ui_cancel` = Backspace + pad ✕; Escape is
	# `battle_pause`). The surface closes through the coordinator's own back grammar, which is
	# what releases the camera takeover and un-pauses the pump.
	if _screen != null and is_instance_valid(_screen) \
			and _screen.current_state() != FormationDetailTransitionScript.State.IDLE:
		return
	# Say the key was ours the way `GambitBattle._unhandled_input` does, BEFORE acting:
	# three branches below `await _boot(...)`, and a `set_input_as_handled()` placed after
	# an await lands a frame late, by which time the event has already travelled on.
	if event.keycode in LAB_KEYS:
		get_viewport().set_input_as_handled()
	match event.keycode:
		KEY_SPACE:
			_running = false
			_step_one()
		KEY_ENTER, KEY_KP_ENTER:
			_running = not _running
		KEY_R:
			await _boot(_index)
		KEY_N:
			await _boot(_index + 1)
		KEY_B:
			await _boot(_index - 1)
		KEY_TAB:
			_watched = (_watched + 1) % maxi(1, units.size())
			_apply_view()
			_paint_range()
			_center_cursor_on_watched()
			_refresh_panel()
		KEY_V:
			_schematic = not _schematic
			_apply_view()
		KEY_G:
			open_surface()
		KEY_F:
			await fork_into_scratch()
		KEY_1:
			await scratch_add_unit(0)
		KEY_2:
			await scratch_add_unit(1)
		KEY_X:
			await scratch_delete_unit()
		KEY_M:
			await scratch_move_watched()
		KEY_J:
			await scratch_cycle_job()


# =============================================================================================
# Panel surface — the panel is a pure VIEW; this host owns the state (ADR-0069's split)
# =============================================================================================

func _refresh_panel() -> void:
	if _panel != null and is_instance_valid(_panel):
		_panel.render(lab_state())


## What [GambitVerdictPanel] draws — the shared shape both hosts answer (#1211). The lab's own
## `lab_state()` is a superset of it, so the panel can be fed either.
func verdict_state() -> Dictionary:
	return {"rows": _last_rows, "watched": _watched, "probe": _probe,
		"note": "%s — tick %d" % [_title_of(_index), current_tick]}


## Everything the readout draws, in one dict. The panel never reaches into the host.
func lab_state() -> Dictionary:
	return {
		"scenario": _title_of(_index),
		"map": _current_map,
		"index": _index,
		"count": _scenarios.size(),
		"fixture_count": _fixture_count,
		"is_cell": _is_cell(_index),
		"cell_axis": _cell.get("axis", {}),
		"cell_refused": bool(_cell.get("refused", false)),
		"cell_refusal": String(_cell.get("refusal", "")),
		"cell_notes": _cell.get("notes", []),
		"cell_expect": _cell.get("expect", []),
		"cell_score": _cell_score,
		"is_scratch": _is_scratch(_index),
		"scratch_index": _scratch_index,
		"tick": current_tick,
		"running": _running,
		"schematic": _schematic,
		"watched": _watched,
		"surface_open": surface() != null,
		"xfail": _scenario.get("xfail", []),
		"xfail_reason": _scenario.get("xfail_reason", ""),
		"rows": _last_rows,
		"probe": _probe,
	}


## Every corpus entry's title, fixtures then cells, in the order `N`/`B` walk them.
func scenario_titles() -> Array:
	var out: Array = []
	for i in range(_scenarios.size()):
		out.append(_title_of(i))
	return out


## The scratch cell's corpus index — the panel's "jump to my cell" verb.
func scratch_index() -> int:
	return _scratch_index


## The corpus index the synthesized half starts at — the panel's "jump to the cells" verb, and
## the answer to "where does the hand-authored corpus end".
func first_cell_index() -> int:
	return _fixture_count


func boot_index(idx: int) -> void:
	await _boot(idx)


func toggle_running() -> void:
	_running = not _running
	_refresh_panel()


func step_one() -> void:
	_running = false
	_step_one()

