extends CombatHost

## GambitBattle — the gambit-mode host (ADR-0242, design S1/S9/S10).
##
## A THIN host beside [GPUArena], not a mode flag on it: `GPUArena` has three subclass
## tests reading state off it, and a second rules model would fork all of them. It does
## two things — **boot a scenario** and **run the deployment** — and then hands the field
## to [TurnDirector], which is a component on the loop rather than anything of this
## scene's. Everything downstream (the adjustment UI, the rollout enemy) mounts on the
## DIRECTOR, so `NavigatorMain` inherits it in one line without inheriting this host.
##
## === Boot ====================================================================
##
## One integer. `scenario_id` hands over map, weather, song, ENTD cast and the deployment
## zone (`ScenarioLoader.apply_scenario` + [ScenarioCast] + [DeploymentZoneDatabase]), so
## "which scenarios does this mode ship with" stays a roster question and never becomes a
## code one. Developed against Gariland (9). There is no size cap here by intent: a
## ceiling discovered by measurement belongs in a tunable, not a guard (design S10).
##
## === Deployment ==============================================================
##
## ENTD offers n units and the zone offers m tiles; you choose who fights and where they
## stand ([DeploymentAssignment]). Mechanically this is **a turn with the clock stopped
## and the meter gate removed** — `TurnDirector.open_deployment()` — so it is the turn
## cycle in a different mode rather than a second freeze path, and committing it starts
## the battle. Three consequences worth stating, because each one is a thing this scene
## deliberately does NOT do:
##
##   - **It holds no snapshot.** Nothing is ticking and the units are not in the GPU
##     buffer yet, so placements live on the CPU-side `Unit` nodes and land in ONE write
##     at commit (`start_battle`). "Throw my placements away" is
##     [DeploymentAssignment.clear], not [TurnDirector.cancel].
##   - **It does not pump.** [CombatLoop.tick] is the one pump (ADR-0037 dec. 2); this
##     host calls it through `CombatHost._process` exactly as `GPUArena` does, and the
##     director only GATES it.
##   - **It does not size the GPU battle until commit.** The arena boots its simulator
##     before placement because its march needs one; here the squad cap can BENCH units,
##     so the battle is sized by the squad that actually took the field.
##
## Enemies are not part of the assignment — they stand on their authored ENTD coords,
## because the ATTACK.OUT zone table is player start tiles only.
##
## === Whose turn you may steer =================================================
##
## The director announces the taker and never classifies sides — `NavigatorMain` puts
## guests on team 0, and a guest is a unit the player may not command. This host answers
## that question with the deployment assignment itself: **the units you deployed are the
## units you steer.** At Gariland that is exactly right — Delita arrives ENTD-blue on
## team0 and fights beside you without taking your orders.
##
## Controls (ADR-0137 Amendment 4's mapping, the same one `GPUArena` uses):
##   Space     - STOP / GO, in every state. It is ONE verb — "run the world" — and what running
##               costs is whatever the current stop is owed: the DEPLOYMENT commits, an OPEN TURN
##               commits (committing with no edits IS "wait" — ADR-0239), and a RUNNING battle
##               STOPS, with the next press starting it again. There is no state in which Space
##               does nothing, which is the property the player actually feels.
##               This SUPERSEDES ADR-0137 Amendment 2's "START and PAUSE are two keys, not one".
##               Amendment 2 was reasoning about a state machine, not about a hand: it split START
##               from PAUSE and left the turn-commit on ○, which made "the world is stopped" one
##               thing to the player and THREE things to the code, each with a different exit and
##               with Space and Esc both dead during a turn. The two keys stay two, but the line
##               between them moved — see Esc.
##   Enter     - ○ CONFIRM, and a CURSOR verb only. Deploying: LATCH the cursored unit (it stays
##               lit where it stands and the cursor walks on), or open the picker on an empty
##               zone tile; a second Enter moves or swaps. On your turn it is the map-hosted
##               Formation screen's, exactly as ✕/△ are — it does NOT spend the turn.
##               🔴 It used to. Two listeners sit on `cursor_confirmed` (this host and
##               [FormationMapHost]) and the screen's `can_open` was read AFTER this host's
##               handler had already run `director.commit()`, so one press over an occupied tile
##               both spent the turn AND opened the screen on somebody else — which re-froze the
##               world through `_set_screen_pause`. Moving the commit to Space removes the write
##               that the second listener was racing.
##   Backspace - ✕ BACK. Deploying: release the latch, or recall the cursored unit to the
##               bench. On your turn: cancel. It arrives as `CursorRig.cursor_cancelled`
##               (#941), not as a keycode this scene tests.
##   Arrows    - while the deployment picker is up, walk the roster grid; Tab opens its menu.
##   Esc       - THE CLASSIC PAUSE, and it is a SCREEN, not a flag: the battlefield dims, `PAUSED`
##               sits over it, and every other key is refused until Esc comes back. Available in
##               every state, frozen ones included — the clock is already stopped there, so
##               refusing it would buy nothing and cost a dead key.
##               Space's stop and Esc's stop are different features, which is why two keys is not
##               one key twice: Space STOPS THE CLOCK and nothing else — the cursor walks, the
##               camera pans, ○ still opens a unit, because you stopped the world to LOOK at it —
##               and Esc PAUSES (you stopped playing). The badge names Space's; the screen names
##               its own.
##   Home      - RECENTRE. Snap cursor and camera back to the turn taker. The cursor is left
##               FREE by the turn-open beat (`docs/TURN-OPEN-BEAT-DESIGN.md` §3) and the pan
##               keys move the camera without it, so this is the way back from either.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias line per
# file keeps every use site's spelling, and makes a grep for `ExMateriaBattlefield` a
# complete census of host->addon symbol coupling.
const CursorRig = ExMateriaBattlefield.CursorRig
## The highlight PUBLISH and the marking vocabulary — the deployment zone is painted, and the
## latch is a marking (`SELECTED`), not a variable this scene keeps to itself.
const TileHighlights = ExMateriaBattlefield.TileHighlights
const CellMarking = ExMateriaSchema.CellMarking
const TerrainCell = ExMateriaSchema.TerrainCell

const FormationDetailTransitionScript = preload("res://src/ui3/formation/FormationDetailTransition.gd")
const StartActionMenu = preload("res://src/ui3/detail/StartActionMenu.gd")

## The rows this scene's Formation screen carries whenever a pick is NOT open (#1007) — design
## §4's four adjustment types, one of which is the gambit surface's door. This host supplies them
## rather than the coordinator defaulting to them, because a formation screen over a WORLD MAP
## still wants the ROM's five: "Remove Unit" and "Order Unit" are roster verbs, and a roster is
## exactly what this scene does not have.
##
## The coordinator dispatches all four by LABEL, so none of them reaches `_on_picker_row_chosen` —
## unlike [constant StartActionMenu.ROWS_DEPLOY], whose one row is this scene's own verb.
## TYPED, and that matters: `action_rows` is `Array[String]` and the screen is reached as an
## untyped `Node3D`, so an untyped `Array` assigned into it fails at RUNTIME inside a signal
## handler, where the only trace is a backtrace nobody is watching for. (This const replaced a
## `NO_ROWS` empty array that carried the same warning and, since the screen now always has rows,
## had no remaining assignment to guard.)
const ADJUST_ROWS: Array[String] = StartActionMenu.ROWS_ADJUST

## The one row of [constant StartActionMenu.ROWS_DEPLOY]. Named rather than `0` for the reason
## `FormationDetailTransition` names its own three: a row index means nothing across row sets.
const DEPLOY_MENU_ROW := 0

## The deployment cues, from the system bank (`SfxCatalog.slot_for("system", …)` resolves these
## slugs to slots 10 / 9 / 5). A refusal used to be a `print()`, which is inaudible — the player
## presses ○, nothing moves, and nothing says why.
const CUE_SET := "set"                          # a unit landed on a tile
const CUE_REMOVE := "unit_removal"              # a unit went back to the bench
const CUE_INVALID := "invalid"                  # the rule refused
const CUE_LATCH := "confirm_selection"          # picked up and latched
const CUE_UNLATCH := "cancel_selection"         # latch released with nothing moved

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const ScenarioDatabase = ExMateriaAlmanac.ScenarioDatabase
const TargetSelector = ExMateriaAlmanac.TargetSelector


## The scenario this host boots into. 9 = "Gariland Fight" on MAP022 — the FFT tutorial
## battle, and the one design S10 says to develop against. The boot path itself is
## scenario-agnostic; this is a default, not a restriction.
@export var default_scenario_id: int = 9

@onready var map: Node3D = $ProceduralMap
# The cursor NODE, by scene path — a scene-tree coupling, not a type reference
# (ADR-0196 dec. 2). Everything read off the cursor goes through `cursor_rig` (ADR-0206).
@onready var tile_cursor: Node3D = $TileCursor
var cursor_rig: CursorRig = null

## The turn director, mounted on the loop (design S1). Public: this is the object the
## adjustment UI (#894) and the rollout driver (#895) attach to, not this scene.
var director: TurnDirector = null

## Panels this host registered into [DebugOverlay], kept so `_exit_tree` can take them
## back out — the overlay is an autoload and outlives the scene.
var _debug_panels: Array = []

# --- the kernel's per-slot VERDICT, over the battle you are actually playing (#1211) ---------
#
# ADR-0275 dec. 4 made `evaluate_gambits_up_to` write `{verdict, condition index, opcode,
# evaluated mask}` per pass, and until now the only host that could READ it was `GambitLabScene`
# — which has no deployment, no roster and no turn order. So "why did this unit's slot 2 decline
# on the turn I was watching" was answerable only about a synthesized cell, never about the
# battle in front of you. The instrument is [GambitVerdictProbe] and it is not lab-shaped; this
# host binds it to its own battle and names its own units.
const VerdictPanelScript = preload("res://src/debug/GambitVerdictPanel.gd")

var _verdict_probe := GambitVerdictProbe.new()
var _verdict_panel = null
## Whose slots the readout details — the unit under the TILE CURSOR. The cursor is already this
## scene's "which unit do you mean" answer (it is what ○ and △ act on), so the readout follows it
## rather than growing a second selection the player would have to keep in sync by hand.
var _verdict_watched: int = 0
## The deployment decision, while it is being made. Survives commit as the record of who
## the player chose — `_commandable` is derived from it.
var assignment: DeploymentAssignment = null
## The turn queue forecast strip (#893). Reads the director and writes nothing; it rides
## the camera rather than this scene, so `NavigatorMain` mounts it the same one line.
var turn_queue_hud: TurnQueueHud = null
## The open turn viewed as an EDITING window (#894, design §4) — the CPU half of the pre-turn
## image, the steerability rule, and the one crossing from Character to GPU. Pure and scene-free,
## like [DeploymentAssignment]; this scene supplies it the three edges the director emits.
var adjustment: AdjustmentTurn = AdjustmentTurn.new()
## The imperative ledger (#1006, design §5) — the charges, the standing one-shot orders and the
## watchdog. Pure and scene-free like [AdjustmentTurn], and wired to the SAME three director
## signals plus [signal CombatLoop.action_committed]: a charge is refunded by the turn's cancel,
## and an order is taken by the action that spends it.
var imperatives: ImperativeGambits = ImperativeGambits.new()
## The enemy's thinking beat (#897, design §7) — built at `commit_deployment`, because it
## needs the simulator the deployment sizes. Null before the battle exists, and null in a
## subclass that turned the AI off (see [member ai_enabled]).
var rollout: RolloutDriver = null
## How many thinking beats have actually RUN, and what the last one decided.
##
## Not bookkeeping for its own sake: a beat that never happened and a beat that held look
## identical from outside — both leave the gambit buffer untouched — so without a counter
## the only way to tell "the host wires the driver" from "the host does not" is to read the
## code. `GambitBattleTest` reads these.
var beats_taken: int = 0
var last_decision: Dictionary = {}
## Does a turn nobody may steer get THOUGHT about, or simply spent?
##
## True is the mode: an enemy turn opens, the rollout runs inside the freeze, the winning
## gambit edit lands, and the turn is committed. False is the pre-#897 behaviour — the turn
## is spent unchanged, which is exactly "wait" (ADR-0239) — and it is here for the subclass
## that needs to measure something ELSE about this host without a 138 ms beat and a
## 256-battle fleet in the middle of it. A test that turns it off is making a claim about
## its own subject; the flag exists so it has to write that claim down.
var ai_enabled: bool = true
## The packed ability table the rollout's static prefilter reads, built on first use. See
## [method _rollout_ability_buffer].
var _ability_buffer: PackedInt32Array = PackedInt32Array()

## The scenario actually booted (resolved from `DebugConfig` or the export).
var scenario_id: int = -1

## The player's own units — the assignable side, and the only side deployment moves.
var _owned: Array = []
## Team0's ENTD-blue slots (Delita at Gariland): they fight beside you, on the ROM's
## tiles, and you do not command them.
var _guests: Array = []
var _enemies: Array = []
## The tile whose unit is LATCHED, or [constant DeploymentAssignment.NO_TILE].
##
## A latch, not a carry (#941). Enter on an occupied tile does not pick the unit UP — it lights
## that tile with `CellMarking.Kind.SELECTED` ("Picked and LATCHED — the cursor has moved on") and
## leaves the real cursor free, so two tiles are lit and the second Enter says where the first one
## goes. Keyed by TILE rather than by unit because every verb the second press has — move, swap,
## refuse — is a question about tiles, and the unit is one `assignment.unit_at` away.
var _latched_tile: Vector2i = DeploymentAssignment.NO_TILE
## The tile the deployment picker was opened from, while its screen is up. The picker never asks
## WHERE: you said that by opening it from a tile.
var _picker_tile: Vector2i = DeploymentAssignment.NO_TILE
## The map-hosted Formation screen (ADR-0137) — the picker's screen, and the unit inspector once
## the battle is running. Mounted once, at boot, exactly as `GPUArena` mounts it.
var _formation_map_screen: Node3D = null
## The highlight publish, off the map. Null on a map that exposes none (a bare test scene).
var _highlights: TileHighlights = null
## Global unit index -> true for the units the player deployed. Built once at commit.
var _commandable: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _deployed: bool = false

## Host-owned config. This host never times out — it is a production host, not a
## regression test, and the tick budget a battle needs is the battle's business. Declared
## here rather than on [CombatHost] for the same reason `GPUArena` declares its own: the
## base holds accessor MECHANICS and no policy (ADR-0018).
var max_ticks: int = 999999


func get_test_name() -> String:
	return "Gambit Battle"


func _ready() -> void:
	# Deployment stands between here and `start_battle`, which is what boots the simulator
	# — so the driver's compute-pipeline compile has a gap to hide in. Start it on a thread
	# now rather than freezing on it at commit. See GPUBatchSimulator.warm_pipelines_async.
	GPUBatchSimulator.warm_pipelines_async()
	# AND THE DEVICE ITSELF, here on the main thread — it is thread-affine, so it cannot
	# ride the warm-up above (#1168). ~180 ms, blocking, deliberately: this is a scene
	# boot with nothing on screen, and the alternative is paying it on the frame the
	# battle intro's dark screen is retracting over. See `GPUBatchSimulator.prewarm_device`.
	GPUBatchSimulator.prewarm_device()
	# No regression log: this is a production host, not a test.
	_rlog = RegressionLogger.new(get_test_name(), false)

	if DebugConfig.combat_seed > 0:
		_rng.seed = DebugConfig.combat_seed
		DebugConfig.active_combat_seed = DebugConfig.combat_seed
	else:
		_rng.randomize()
		DebugConfig.active_combat_seed = _rng.seed

	print("\n=== GAMBIT BATTLE ===")
	print("Enter - confirm (deploy / set down; commit your turn)")
	print("Backspace - back (bench the cursored unit; cancel your turn)")
	print("Space - start the battle")
	print("Home - recentre on the unit whose turn it is")
	print("F3 - debug overlay")
	print("=====================\n")

	await get_tree().process_frame
	await get_tree().process_frame

	# The scenario persists in DebugConfig so a picker choice survives a scene reload;
	# -1 falls back to the scene default (the same contract `GPUArena` has).
	if DebugConfig.active_scenario_id < 0:
		DebugConfig.active_scenario_id = default_scenario_id
	scenario_id = DebugConfig.active_scenario_id

	# One integer: map (built here — the ProceduralMap node has auto_build_on_ready =
	# false), weather, night, and battle music (ADR-0030).
	ScenarioLoader.apply_scenario(scenario_id, map)

	# #589: hand the map's two outputs to the host systems that consume them.
	BattlefieldWiring.wire_map(map)
	# ADR-0192 dec. 3's clean fetch — one untyped step at the seam, `Lattice`-typed from
	# here on, landing in an annotated LOCAL first because receiver-type inference is per
	# file and the field is declared on `CombatHost`.
	var lat: Lattice = map.lattice
	lattice = lat
	if lattice == null:
		push_error("[GambitBattle] Map has no lattice!")
		return
	# The highlight publish, if this map has one. `in` rather than a type test: the map is a
	# scene-tree coupling here (ADR-0196 dec. 2), and a bare test map legitimately has none.
	_highlights = map.highlights if ("highlights" in map) else null

	if tile_cursor != null:
		cursor_rig = CursorRig.bind(self, tile_cursor, $PlayerCamera)
		BattlefieldWiring.wire_cursor(cursor_rig)
		cursor_rig.seed_from_map(map, Vector2i(0, 0))
		# The cursor states the EVENT; deciding what acting means is this scene's job,
		# and the phase supplies what acting IS. Three intents, three signals, no keycodes
		# (#941 — `cursor_cancelled` was a `ui_cancel` test in `_unhandled_input` here).
		cursor_rig.cursor_moved.connect(_on_cursor_moved_for_verdict)
		cursor_rig.cursor_confirmed.connect(_on_cursor_confirmed)
		cursor_rig.cursor_cancelled.connect(_on_cursor_cancelled)

	_ensure_loop()

	var battle_cast: Dictionary = await ScenarioCast.compose(self, scenario_id)
	_owned = battle_cast["owned"]
	_enemies = battle_cast["team1"]
	_guests = []
	for unit in battle_cast["team0"]:
		if not _owned.has(unit):
			_guests.append(unit)

	# The authored side stands NOW: the ATTACK.OUT zone table is player start tiles only,
	# so everything the ROM places is placed before the player is asked anything.
	_stand_authored_units()

	assignment = DeploymentAssignment.for_scenario(_owned, scenario_id, _slug_of)

	# The inherited legacy `CombatUI`, freed exactly as `GPUArena` frees its own
	# (ADR-0137): the node arrives from `assets/scenes/CombatCamera.tscn`, which a
	# child of an instanced scene cannot be removed from per-consumer, and unbound it
	# draws eight empty "Unit" cards down both edges of the screen — over the two
	# margins a battlefield HUD wants. THE THIRD COPY OF THESE FIVE LINES IS THE
	# SIGNAL TO DO THE GLOBAL DEMOLITION ADR-0137 already scoped, not to copy again.
	var legacy := get_node_or_null("PlayerCamera/FocusPoint/Camera/CombatUI")
	if legacy != null:
		legacy.get_parent().remove_child(legacy)
		legacy.queue_free()

	# Design S1's one-liner, and the whole of the wiring. The director gates the loop and
	# adds no pump.
	director = TurnDirector.mount(combat_loop, 0)
	director.turn_opened.connect(_on_turn_opened)
	director.turn_committed.connect(_on_turn_committed)
	# The adjustment turn's three edges are the director's three signals and nothing else — see
	# `AdjustmentTurn`, which never sees the director. `turn_cancelled` is connected HERE and not
	# where the other two are read, because the CPU restore has to happen before the director
	# re-opens the same turn and takes a fresh image (ADR-0239, `TurnDirector.cancel`).
	director.turn_cancelled.connect(_on_turn_cancelled)

	# The map-hosted Formation screen (ADR-0137), mounted ONCE and used for two things: the
	# deployment picker's screen, and — once the battle is running — the unit inspector every other
	# map-bearing scene already has. Mounted before the deployment opens, because the picker is the
	# first thing that can ask for it.
	_setup_formation_map_screen()

	# The forecast HUD (design S6). Mounted on the CAMERA and reading the director, so
	# it is not this host's machinery either — it stays hidden through deployment on its
	# own, because a battle with no GPU buffer has no turn order to show. It sits at the
	# top of the screen and the map host's pair parks off both edges, so the two camera
	# seats do not compete for the same real estate.
	turn_queue_hud = TurnQueueHud.mount($PlayerCamera/FocusPoint/Camera, director)

	_mount_pause_badge()

	_open_deployment()

	# The auto-place toggle's subscription (`gambit.auto_deploy`), AFTER `_open_deployment`
	# for the ordering the handler depends on: `on_update` applies the coalesced value AT
	# SUBSCRIBE, so the boot-time auto-place happens here, on an assignment that already
	# exists — and on the `--combat-autostart` path, which has by now committed, it sees
	# `_deployed` and does nothing. The box itself is `GambitDeployDebugPanel`, below.
	Tune.on_update(self, DebugConfig.GAMBIT_AUTO_DEPLOY_SLUG, _apply_auto_deploy)

	# ADR-0177: a device-input consumer REGISTERS rather than being grandfathered. This host
	# is the base state of its own scene's `game` stack, so it holds focus until something
	# nested (the adjustment UI, #894) pushes above it — at which point Godot stops
	# delivering to `_unhandled_input` here, structurally, rather than by a flag this scene
	# would have to remember to check.
	Focus.push("gambit_battle", self)

	# The boot banner has advertised "F3 - debug overlay" since this host landed, but
	# nothing registered a panel into it, so F3 opened an empty layout and the `pacing.*`
	# knobs were unreachable in the one mode that most needs them live. Placed after the
	# director mount so it reads with the rest of the wiring — the row's visibility is a
	# declared flag (`show_playback_rate`), not an ordering side effect.
	_setup_debug_panels()

	DebugConfig.quit_requested.connect(_on_quit_requested)


## The pump is [CombatHost]'s and stays there — nothing here pumps anything (ADR-0239). What this
## override adds is the imperative watchdog, and it is here because a deadline in TICKS can only be
## read after the ticks have been advanced.
##
## It cannot be moved onto a turn edge: the world runs BETWEEN turns, which is exactly the stretch
## an unconsumed order is exposed for, and a check that only ran at turn boundaries would leave an
## expired lock-on standing through the whole of it. It costs one Dictionary emptiness test per
## frame in the common case, which is every frame of every battle nobody issues an order in.
func _process(delta: float) -> void:
	super._process(delta)
	_sweep_imperatives()
	# The turn-open travel. Here and not on a `Tween` or an `await` because it has to advance
	# through the FREEZE, and because a frame counter is drivable from a test.
	_advance_turn_beat()
	_refresh_pause_badge()


## The debug panels this host registers — [CombatPanelCatalog], the same mount `GPUArena`
## uses. This REPLACES the deliberately-short one-panel list that stood here.
##
## That list was justified as "a panel that steers something this scene does not own would
## be a view without an owner here", which is sound reasoning on a false premise: this host
## owns a `ProceduralMap`, a `PlayerCamera`, a `CursorRig` and both team arrays — every
## subject `GPUArena`'s twenty ask for. The short list was not a scoping decision the
## subjects supported, it was a second hand-maintained list, and the two drifted to twenty
## versus one. Applicability is derived per slug and SHOWN on the dashboard's Catalogue page
## rather than guessed at by trimming a list here (ADR-0263).
##
## `show_playback_rate`: this host mounts a director, so the between-turn playback rate has
## something to scale. `GPUArena` does not, and must not show the row.
##
## CALLED TWICE, and the second call is not belt-and-braces. This runs from `_ready`, before
## deployment has committed, so the team arrays are empty and the roster panel cannot be
## built — but deferring the whole mount until the battle starts would put the `pacing.*`
## knobs out of reach for the whole of deployment, which is the defect (#1050) this host was
## last fixed for. So mount what is buildable now, and mount the rest at `start_battle`;
## `CombatPanelCatalog.mount` skips ids already up.
##
## `GambitDeployDebugPanel` stays HOST-PRIVATE and out of the catalogue, and that is the
## distinction the catalogue exists to make rather than an exception to it: the catalogue
## holds what BOTH combat hosts want, and the auto-place toggle is a view onto a question
## only a host with a deployment can ask. A scene with no deployment must not carry the row.
func _setup_debug_panels() -> void:
	CombatPanelCatalog.mount(self, _debug_panels, {"show_playback_rate": true})

	# The VERDICT readout (#1211). HOST-PRIVATE and out of the catalogue, for the reason the
	# deploy panel is: the catalogue holds what BOTH combat hosts want, and a readout of the
	# gambit kernel's per-slot decision is a question only a host running GAMBITS can ask —
	# `GPUArena` fields a cast that has none. Its own emptiness test, like the deploy panel's,
	# because it carries no catalogue id.
	#
	# A FAILED LAYOUT MOUNTS NOTHING, and says why. The verdict is read by decoding two reserved
	# ints against a layout parsed out of the kernel header; if that parse failed, every slot
	# would decode to zeros — and `VERDICT_NONE == 0` is a REAL answer ("this call did not walk
	# this slot"). A blank readout and a broken one would be byte-identical, which is exactly the
	# failure ADR-0275 dec. 18 exists to prevent.
	if _verdict_panel == null:
		if not _verdict_probe.load_layout():
			for c in _verdict_probe.reader.checks:
				if not c["ok"]:
					push_warning("[GambitBattle] verdict readout OFF — %s" % c["what"])
		else:
			_verdict_panel = VerdictPanelScript.new()
			_verdict_panel.setup(self, "Gambit verdict (live battle)")
			DebugOverlay.register_panel(_verdict_panel, DebugOverlay.Category.SIMULATION)
			_debug_panels.append(_verdict_panel)

	# Deployment: the auto-place toggle, in the Simulation cell because it is the same
	# question — what this host does without being asked. Registered by THIS host and
	# nowhere else, so it is absent from the F3 window of every scene that has no
	# deployment. The guard is defensive rather than load-bearing today — `start_battle`
	# re-enters the CATALOGUE, which is idempotent by id, and not this function — but this
	# panel carries no catalogue id, so nothing else would stop a second copy if a later
	# edit routed that second mount through here.
	if not _deploy_panel_mounted():
		var deploy_panel := GambitDeployDebugPanel.new()
		deploy_panel.setup()
		DebugOverlay.register_panel(deploy_panel, DebugOverlay.Category.SIMULATION)
		_debug_panels.append(deploy_panel)


## The readout follows the cursor. Kept to the VERDICT and nothing else — this handler must not
## grow a second opinion about what the cursor means, because `_on_cursor_confirmed` and the
## map-hosted Formation screen already dispatch that question between them (ADR-0137 Amendment 2)
## and a third reader would be a third thing to keep in agreement.
func _on_cursor_moved_for_verdict(grid_pos: Vector2i) -> void:
	var unit = _unit_at_grid(grid_pos)
	if unit == null:
		return          # an empty tile HOLDS the last pick rather than blanking the readout:
		                # walking the cursor across open ground would otherwise erase the very
		                # rows you moved it to compare against.
	var idx := units.find(unit)
	if idx >= 0:
		_verdict_watched = idx


## What [GambitVerdictPanel] draws (#1211) — the same shape [GambitLabScene] answers, so one
## renderer serves both. `units` is empty until `director.commit()`, and an empty row set draws as
## "no battle sampled yet" rather than as a battle with nothing in it.
func verdict_state() -> Dictionary:
	if gpu_simulator == null or units.is_empty():
		return {"rows": [], "watched": 0, "probe": _verdict_probe,
			"note": "no battle yet — deploy and commit"}
	# Bound every frame rather than once at commit: `units` is rebuilt by the deployment commit
	# and a probe bound before it would be naming the pre-commit cast. The GPU lays `team0 + team1`
	# out CONTIGUOUSLY (`GPUBatchSimulator.set_battle_units` walks one `unit_idx` across both), and
	# `units` is assembled in that same order, so the array IS the name table.
	var names: Array = []
	for u in units:
		# The IDENTITY's name, not the node's. `UnitSpawn` stamps the Character on every unit it
		# builds and `FormationMapHost.character_for_unit` is the one resolver for it (slug
		# fallback included) — reused rather than re-derived, because a second answer to "who is
		# this unit" is how a readout comes to print one character's name over another's HP.
		var ch = FormationMapHost.character_for_unit(u)
		names.append(String(ch.display_name) if ch != null and ch.display_name != ""
			else String(u.name))
	_verdict_probe.bind(gpu_simulator, 0, names)
	return {
		"rows": _verdict_probe.rows(units.size()),
		"watched": _verdict_watched,
		"probe": _verdict_probe,
		"note": "tick %d — cursor picks the unit" % current_tick,
	}


## Is this host's own deploy panel already up? The catalogue is idempotent by id; this panel
## has no id because it is not a catalogue entry, so it carries its own emptiness test.
func _deploy_panel_mounted() -> bool:
	for panel in _debug_panels:
		if is_instance_valid(panel) and panel is GambitDeployDebugPanel:
			return true
	return false

	# Deployment: the auto-place toggle, in the same cell because it is the same question
	# — what this host does without being asked. Registered by THIS host and nowhere else,
	# so it is absent from the F3 window of every scene that has no deployment.
	var deploy_panel := GambitDeployDebugPanel.new()
	deploy_panel.setup()
	DebugOverlay.register_panel(deploy_panel, DebugOverlay.Category.SIMULATION)
	_debug_panels.append(deploy_panel)


## The overlay outlives this scene, so a panel left registered after a reload is a view
## bound to a freed host — the same teardown `GPUArena._reset_arena` does before it
## reloads, done on the edge that covers every exit rather than one of them.
func _exit_tree() -> void:
	for panel in _debug_panels:
		if is_instance_valid(panel):
			DebugOverlay.unregister_panel(panel)
	_debug_panels.clear()
	# Give back anything `warm_pipelines_async` parked and no battle ever claimed: a live
	# local RenderingDevice at process shutdown is an exit-134 abort, not a leak warning
	# (#471). A no-op once a battle claimed it — then `GPUBatchSimulator.cleanup()` owns it.
	GPUBatchSimulator.release_prewarm()


func _ensure_loop() -> void:
	if combat_loop:
		return
	combat_loop = CombatLoopClass.new()
	combat_loop.name = "CombatLoop"
	combat_loop.battle_name = get_test_name()
	combat_loop._rlog = _rlog
	combat_loop.max_ticks = max_ticks
	combat_loop.lattice = lattice
	combat_loop.player_camera = $PlayerCamera
	combat_loop.map = map
	add_child(combat_loop)
	combat_loop.victory.connect(_on_victory)
	# Design §5's removal edge, and it already existed. ACTION_COMMITTED is keyed off the GPU's
	# `cast_step_id` bumping (`GPUCombatInterpreter`), so it is one per ACTION — ability or pure
	# attack — and a MOVE does not raise it. That is precisely what makes it the right edge: an
	# imperative that ordered an attack across the map survives the approach and is spent by the
	# blow, where a signal that fired on movement would consume the order before it landed.
	combat_loop.action_committed.connect(_on_action_committed)
	# The over-unit feedback billboards (ADR-0063): damage/heal numbers and status bubbles.
	# Mounted here because this is where the loop exists — `GPUArena` had the only mount in
	# the tree, so a battle played on this host showed no numbers at all.
	FeedbackHudManager.mount(combat_loop)


#region Deployment

## Open the assignment: frozen, no taker, no meter gate (design S9).
func _open_deployment() -> void:
	director.open_deployment()

	# The auto-fill debug path, mirroring `--combat-autostart`:
	# fill the zone by the plan and commit in the same breath, so a rig (or a "run with
	# seed") reaches a live battle without a keypress.
	if DebugConfig.combat_autostart:
		print("[GambitBattle] Auto-deploy: filling the zone and starting.")
		assignment.auto_fill()
		_show_assignment()
		commit_deployment()
		return

	print("[GambitBattle] Deploy: Enter on an empty green tile picks WHO fights there; Enter on one of your units latches it and a second Enter moves or swaps; Backspace lets go, or recalls. Space starts the battle.")
	print("[GambitBattle] Zone %d: %d tiles, squad cap %d, %d units available."
		% [int(ScenarioDatabase.get_scenario(scenario_id).get("first_squad_deployment_idx", 0)),
			assignment.tiles.size(), assignment.cap, _owned.size()])
	_show_assignment()


## Auto-place the squad — the debug toggle's whole behaviour, applied at boot and again
## whenever the box is ticked mid-deployment ([member DebugConfig.gambit_auto_deploy]).
##
## It PLACES and stops there: the deployment stays open, the placements are editable, and the
## battle still starts on your Space. That is the line between this and `--combat-autostart`,
## which fills and commits in the same breath — the whole point of this one is to reach an
## EDITABLE field without five picks.
##
## Refuses on an assignment that already has somebody standing on it, so ticking the box after
## you have placed a unit by hand never throws your work away. Unticking it places nothing back
## on the bench for the same reason: the toggle answers "what happens on load", and a toggle
## that also cleared the field would be two verbs on one control.
func _apply_auto_deploy(on: bool) -> void:
	if not on or _deployed or assignment == null:
		return
	if assignment.placed_count() > 0:
		return
	assignment.auto_fill()
	_show_assignment()
	print("[GambitBattle] Auto-place: %d of %d units on the zone's first tiles. Space starts the battle."
		% [assignment.placed_count(), _owned.size()])


## Stand every unit the ROM placed on the tile the ROM placed it on. Guests and enemies
## alike: the difference between them is who gives them orders, not where they start.
func _stand_authored_units() -> void:
	for unit in _guests + _enemies:
		if not unit.has_meta(ScenarioCast.ENTD_TILE_META):
			push_warning("[GambitBattle] %s has no authored ENTD tile" % unit.name)
			continue
		var cell: Vector3i = unit.get_meta(ScenarioCast.ENTD_TILE_META)
		unit.place_on_tile(cell.x, cell.y, map, cell.z)
		unit.visible = true


## Render the assignment onto the field: the squad stands on its tiles, the bench is
## hidden. Called after every edit, so what you see IS the assignment.
func _show_assignment() -> void:
	for unit in _owned:
		unit.visible = false
	for row in assignment.squad():
		var tile: Vector2i = row["tile"]
		row["unit"].place_on_tile(tile.x, tile.y, map)
		row["unit"].visible = true
		_face_toward_enemies(row["unit"], tile)
	_paint_zone()


## Turn a deployed unit to face the nearest authored enemy. Recomputed for EVERY unit on every edit
## rather than for the one that moved: a swap moves two, and a facing that is a pure function of the
## assignment cannot drift out of step with it. There is no rotate control in this ticket (#941) —
## the ROM's own deployment lets you turn a unit, and that is a separate verb with its own input.
##
## Distance is measured in COLUMNS, and the level is not in it: facing is a grid-axis question
## (ADR-0219 dec. 6), so a unit on the bridge faces the bank the same way one standing on it does.
func _face_toward_enemies(unit, tile: Vector2i) -> void:
	var best: Vector2i = Vector2i.ZERO
	var best_d: int = -1
	for enemy in _enemies:
		if enemy == null or not is_instance_valid(enemy) \
				or not enemy.has_meta(ScenarioCast.ENTD_TILE_META):
			continue
		var cell: Vector3i = enemy.get_meta(ScenarioCast.ENTD_TILE_META)
		var d: int = absi(cell.x - tile.x) + absi(cell.y - tile.y)
		if best_d < 0 or d < best_d:
			best_d = d
			best = Vector2i(cell.x, cell.y)
	if best_d < 0:
		return          # a scenario with no authored enemy has nothing to face
	unit.facing_direction = TileTraversalUtils.get_facing_direction_for_step(
		Vector3i(tile.x, tile.y, 0), Vector3i(best.x, best.y, 0))


## ○/Enter while deploying. Two presses, and the FIRST one does not move anything.
##
## On an occupied tile it LATCHES (#941): the tile lights `SELECTED` and the cursor walks on, so
## the player is looking at both ends of the move when they press the second time. On an EMPTY zone
## tile there is nothing to latch and the question is who fights here, so the picker opens — which
## is the whole ticket: at Gariland the cap is 5 against a 7-unit roster, and `benched()[0]` answered
## that question for the player, correctly, BY ACCIDENT OF ROSTER ORDER.
func _on_deployment_confirm(column: Vector2i) -> void:
	if _screen_up():
		return          # the screen owns the pad; this signal cannot reach here while it is up
	if _latched_tile == DeploymentAssignment.NO_TILE:
		if assignment.unit_at(column) != null:
			_latch(column)
			return
		_open_deployment_picker(column)
		return
	_resolve_latch(column)


## The FIRST press on an occupied tile. Nothing moves; the tile is marked and the cursor is free.
func _latch(column: Vector2i) -> void:
	_latched_tile = column
	_paint(column, CellMarking.Kind.SELECTED)
	SfxRouter.play_system(CUE_LATCH)
	print("[GambitBattle] %s is picked — Enter on another tile to move or swap, Backspace to let go."
		% assignment.unit_at(column).name)


## Drop the latch, leaving both units where they are. The marking goes with it: `SELECTED` has its
## own slot, so clearing it reveals the zone paint underneath rather than erasing it.
func _unlatch(cue: String = "") -> void:
	if _latched_tile == DeploymentAssignment.NO_TILE:
		return
	_clear(_latched_tile, CellMarking.Kind.SELECTED)
	_latched_tile = DeploymentAssignment.NO_TILE
	if cue != "":
		SfxRouter.play_system(cue)


## The SECOND press. A free zone tile MOVES, an occupied one SWAPS, and anything outside the zone
## refuses and STAYS LATCHED — a misfire must not cost the player the selection they just made.
func _resolve_latch(column: Vector2i) -> void:
	var latched = assignment.unit_at(_latched_tile)
	if latched == null:
		_unlatch()      # the latched tile emptied underneath us; nothing to resolve
		return
	if column == _latched_tile:
		_unlatch(CUE_UNLATCH)
		return
	if not assignment.tiles.has(column):
		SfxRouter.play_system(CUE_INVALID)
		print("[GambitBattle] %s is not a deployment tile — %s is still picked."
			% [str(column), latched.name])
		return
	var standing = assignment.unit_at(column)
	var from: Vector2i = _latched_tile
	if standing != null:
		# A SWAP. Both sides are already on the field, so neither placement can be refused by the
		# cap or the reserve — the squad size does not change.
		assignment.unplace(latched)
		assignment.unplace(standing)
		assignment.place(latched, column)
		assignment.place(standing, from)
	elif not assignment.place(latched, column):
		_report_refusal(latched, column)
		return
	_unlatch()
	SfxRouter.play_system(CUE_SET)
	_show_assignment()


## ✕/Backspace while deploying. Release the latch if there is one; otherwise RECALL the unit under
## the cursor to the bench.
##
## Ordered latch-first because the latch is the more recent intent: a player who has one tile lit
## and presses ✕ means "not that one", never "and also bench whatever I am standing on now".
func _on_deployment_back(column: Vector2i) -> void:
	if _screen_up():
		return          # the screen owns the pad; ✕ is its back, not the map's
	if _latched_tile != DeploymentAssignment.NO_TILE:
		var was = assignment.unit_at(_latched_tile)
		_unlatch(CUE_UNLATCH)
		print("[GambitBattle] Let go of %s." % (was.name if was != null else "it"))
		return
	var standing = assignment.unit_at(column)
	if standing == null:
		return
	if assignment.is_mandatory(standing):
		SfxRouter.play_system(CUE_INVALID)
		print("[GambitBattle] %s must be deployed (this scenario's ATTACK.OUT flag)." % standing.name)
		return
	assignment.unplace(standing)
	SfxRouter.play_system(CUE_REMOVE)
	_show_assignment()


## Say WHICH rule refused the placement, out loud as well as in the log. A refusal with no reason is
## the shape of UI that makes a player think the game is broken, and the reserve in particular is
## invisible — the tile is empty and the squad is under the cap, and it still will not take this
## unit. The `invalid` cue is the audible half: a `print()` is not feedback at all.
func _report_refusal(unit, column: Vector2i) -> void:
	SfxRouter.play_system(CUE_INVALID)
	if not assignment.tiles.has(column):
		print("[GambitBattle] %s is not a deployment tile." % str(column))
	elif assignment.placed_count() >= assignment.cap:
		print("[GambitBattle] Squad is full (cap %d) — bench someone first." % assignment.cap)
	elif assignment.reserved_slots() > 0:
		var held: Array = []
		for candidate in assignment.candidates():
			if assignment.is_mandatory(candidate) and not assignment.is_placed(candidate):
				held.append(candidate.name)
		print("[GambitBattle] The last %d of %d slots %s reserved for %s — deploy %s first."
			% [assignment.reserved_slots(), assignment.cap,
				"is" if assignment.reserved_slots() == 1 else "are",
				", ".join(held), "them" if held.size() > 1 else held[0]])
	else:
		print("[GambitBattle] Cannot deploy %s there." % unit.name)


## Paint the deployment zone. GREEN (`PLACEMENT_PLAYER`), which is what a "you may deploy here"
## square already means everywhere else in this tree — blue is `PLACEMENT_ENEMY`, i.e. "you may NOT
## place here", and re-colouring the palette to match a description would touch an overlay `GPUArena`
## shares (#941). All four `PLACEMENT_*` kinds share ONE slot, so this never disturbs the cursor's
## marking or the latch: those live in slots of their own (ADR-0221).
func _paint_zone() -> void:
	for tile in assignment.tiles:
		_paint(tile, CellMarking.Kind.PLACEMENT_PLAYER)


## Drop every marking this scene painted. Called at commit: the zone is not a thing you may deploy
## on once the battle has started.
func _clear_zone() -> void:
	_unlatch()
	for tile in assignment.tiles:
		_clear(tile, CellMarking.Kind.PLACEMENT_PLAYER)


## Paint one deployment COLUMN, at its ground cell. The publish is keyed by cell and the assignment
## by column, and `ground_at` is the query that bridges them — the same "lowest thing here" answer
## `place_on_tile` lands a unit on.
func _paint(column: Vector2i, kind: CellMarking.Kind) -> void:
	var cell := _cell_of(column)
	if _highlights != null and cell != TerrainCell.NONE:
		_highlights.paint(cell, kind)


func _clear(column: Vector2i, kind: CellMarking.Kind) -> void:
	var cell := _cell_of(column)
	if _highlights != null and cell != TerrainCell.NONE:
		_highlights.clear(cell, kind)


func _cell_of(column: Vector2i) -> Vector3i:
	if lattice == null:
		return TerrainCell.NONE
	var ground := lattice.ground_at(column.x, column.y)
	return ground.grid if ground != null else TerrainCell.NONE


## Commit the deployment and start the battle — the ONE write (design S9).
##
## Everything up to here was CPU-side: this is where the chosen squad becomes a GPU
## battle. The benched units are not in it at all, which is why the simulator is sized
## HERE and not at boot. Returns false (and says why) when the assignment is not legal.
func commit_deployment() -> bool:
	if _deployed:
		return false
	var problems := assignment.problems()
	if not problems.is_empty():
		for problem in problems:
			print("[GambitBattle] Cannot start: %s" % problem)
		return false

	# The zone stops being a place you may deploy the moment the battle exists.
	_clear_zone()

	var squad: Array = assignment.squad()
	team0_units = []
	for row in squad:
		var tile: Vector2i = row["tile"]
		row["unit"].place_on_tile(tile.x, tile.y, map)
		row["unit"].visible = true
		team0_units.append(row["unit"])
	team0_units.append_array(_guests)
	team1_units = _enemies
	units = team0_units + team1_units

	# The bench does not come to the battle. Freed rather than hidden: a Unit left in the
	# tree is still a `_unit_at_grid` answer and still animates, and this scene has no
	# reason to hold a cast it did not field.
	for unit in assignment.benched():
		unit.queue_free()

	# `units_per_battle` splits the GPU battle at its midpoint and CombatLoop indexes
	# `team0 + team1` contiguously, so team0 must land exactly in [0, ups/2) — the same
	# arithmetic `GPUArena` does before its strategy phase (ADR-0180).
	combat_loop.units_per_battle = 2 * maxi(
		maxi(team0_units.size(), team1_units.size()), 1)
	if team1_units.size() > team0_units.size():
		push_warning("[GambitBattle] team1(%d) > team0(%d) — GPU team split may mis-slot"
			% [team1_units.size(), team0_units.size()])

	# The rollout fleet, sized HERE and nowhere else (#897, ADR-0237 dec. 8). It has to be
	# set before `start_battle`, which is what boots the simulator, because the buffers are
	# sized once. `CombatLoop`'s own default stays 0 = one battle so that `GPUArena` and
	# `NavigatorMain` — neither of which runs a rollout — go on paying nothing for it.
	combat_loop.rollout_fleet_size = RolloutDriver.fleet_size_now() if ai_enabled else 0

	# Who you may steer, resolved once, from the assignment itself.
	_commandable.clear()
	for i in range(units.size()):
		for row in squad:
			if row["unit"] == units[i]:
				_commandable[i] = true
				break

	# Charges are per unit PER BATTLE, so the ledger starts empty with the battle. The arming
	# encode passes no lead: an imperative is issued on a turn, and a battle that armed one at boot
	# would be handing out an order nobody gave.
	imperatives.reset()

	combat_loop.start_battle(team0_units, team1_units,
		GambitEncoder.encode_for_units(units, "GambitBattle"),
		lattice, map, _rng.randi())
	_sync_loop_refs()
	_deployed = true
	_mount_rollout_driver()

	# Second catalogue pass — see `_setup_debug_panels`. The roster panel's rows are per-unit
	# and the teams did not exist at `_ready`; everything already mounted is skipped by id.
	CombatPanelCatalog.mount(self, _debug_panels, {"show_playback_rate": true})

	# Before `director.commit()`, not after: committing resumes the world and the HUD
	# refreshes on that edge, so a cast bound afterwards would draw one queue of blank
	# cards first.
	if turn_queue_hud != null:
		turn_queue_hud.bind_units(units)

	print("[GambitBattle] Deployed %d, benched %d, %d guests, %d enemies — battle %d units."
		% [squad.size(), assignment.benched().size(), _guests.size(),
			team1_units.size(), units.size()])

	# The director's own verb: committing DEPLOYMENT is what starts the clock. It resumes
	# the world, which is why nothing here sets `combat_active`.
	director.commit()
	return true

#endregion


#region The deployment picker (#941)

## Mount the map-hosted Formation screen (ADR-0137), the same coordinator `GPUArena` mounts, in its
## MAP host mode. It answers TWO questions here and the gate below is what keeps them apart:
##
##   - while the battle runs, ○ on a unit opens that unit's screen, exactly as on the arena;
##   - while deploying, ○ is THIS scene's (latch / picker) and the screen never sees it.
##
## `can_open` is the exact NEGATION of `_cursor_confirm_is_mine`, which is what makes two listeners
## on one signal a DISPATCH rather than a race: for any press exactly one of them acts, because the
## same predicate decides both (ADR-0137 Amendment 2).
##
## 🔴 THAT WAS A CLAIM ABOUT A PREDICATE THAT COULD CHANGE MID-PRESS. The two handlers read it at
## two different moments — this host is connected first (`_ready`), the screen when the signal
## reaches it — so while `_on_cursor_confirmed` still committed the turn, the commit flipped
## `state()` to RUNNING and the screen then read `can_open` as TRUE. One press over an occupied
## tile spent the turn AND opened the screen on somebody else. The negation is only a dispatch if
## nothing a handler does can change the answer, so the predicate is now DEPLOYMENT-only and no
## confirm handler writes director state. `GambitBattleTest` arm 4d is the arm that holds it.
func _setup_formation_map_screen() -> void:
	var cam := get_node_or_null("PlayerCamera")
	if cam == null or cursor_rig == null:
		return
	_formation_map_screen = FormationDetailTransitionScript.mount_over_map(
		cam, cursor_rig, _unit_at_grid, _set_screen_pause,
		func() -> bool: return not _cursor_confirm_is_mine())
	if _formation_map_screen == null:
		return
	# HOST-side panel mount (#1267). `FormationMapHost extends FormationScene`, so the deleted
	# `_setup_debug_panels()` ran from `_ready()` on THIS path too — wiring the roster screen
	# alone would have silently deleted the panels from the in-battle screen. `mount_over_map`
	# `add_child`s the coordinator before returning, so `formation()` is already live here.
	FormationDebugPanels.register_formation_panels(_formation_map_screen.formation())
	_formation_map_screen.action_row_chosen.connect(_on_picker_row_chosen)
	# The pick's END, whichever door reached it (ADR-0261) — connected at MOUNT rather than at each
	# `_open_deployment_picker`, because a connection made per pick is a connection that can be made
	# twice or not at all.
	_formation_map_screen.pick_ended.connect(_on_pick_ended)
	var host := _map_formation_host()
	if host != null:
		# WHOSE turn it is is this scene's knowledge, so the screen asks rather than decides
		# (#894). It gates the action ROWS only: the screen still opens on anybody, because
		# refusing a look is what ADR-0137 Amendment 6 ruled out.
		host.steerable = _unit_is_steerable
		# Opening the screen on the taker is what marks the turn as touched, and both doors
		# (○ and △) arrive here. A turn nobody opened the screen on skips the commit push.
		host.unit_act_requested.connect(_on_unit_act_requested)
	# Armed at mount, not at the first turn: the screen is reachable in every phase (△ is never
	# refused), and a menu that grew a "Gambit" row only once a turn opened would be a different
	# screen depending on when you looked at it.
	_formation_map_screen.action_rows = ADJUST_ROWS

	# The imperative row (#1006) is offered because a BATTLE host supplies the ledger; the roster
	# host supplies none and its surface stays the four slots it was. The unit index and the tick
	# are this scene's knowledge, so the screen asks rather than guesses — the same shape as
	# `host.steerable` above.
	_formation_map_screen.imperative_orders = imperatives
	_formation_map_screen.imperative_unit_for = _unit_index_of_character
	_formation_map_screen.imperative_now = _current_tick
	_formation_map_screen.imperative_issued.connect(_on_imperative_issued)


## Which unit is standing on `grid_pos` — this scene's own answer, handed to the map host so the
## screen never has to know how a battlefield stores its units. Asks the COLUMN question, because
## that is what the cursor names.
func _unit_at_grid(grid_pos: Vector2i):
	for unit in _all_standing_units():
		var cell: Vector3i = unit.get_current_cell()
		if Vector2i(cell.x, cell.y) == grid_pos:
			return unit
	return null


## Everything on the field right now — the deployed squad plus the ROM's own side. Deliberately not
## `units`: that array does not exist until commit (design S9), and the screen has to work during
## deployment, which is the phase this whole ticket is about.
func _all_standing_units() -> Array:
	var out: Array = []
	for row in assignment.squad():
		out.append(row["unit"])
	for unit in _guests + _enemies:
		if unit != null and is_instance_valid(unit) and not unit.is_dead:
			out.append(unit)
	return out


## What the screen was interrupting, so closing it can put that back. Captured on open rather than
## assumed on close — forcing `combat_active = true` here would START the battle because the player
## looked at a unit during deployment.
var _combat_active_before_screen := false


func _set_screen_pause(paused: bool) -> void:
	if paused:
		_combat_active_before_screen = combat_active
		combat_active = false
	else:
		combat_active = _combat_active_before_screen
	# The forecast strip leaves while a screen stands over the battlefield it annotates. This hook
	# is the coordinator's own `_take_claims` / `_release_claims` edge, which is why it is the one
	# used: the MAP host emits no `dismissed` (it is PERSISTENT — see
	# `FormationDetailTransition._on_dismissed`), so hiding on `unit_activated` would be a hide
	# with no matching show. There is no `set_battle_live` counterpart here on purpose: this scene
	# has no `NavigatorRunner` and no `GameState`, and the strip's default is LIVE — a battle-only
	# harness is up from the moment the queue has anything in it, which is the right answer rather
	# than a missing feature.
	if is_instance_valid(turn_queue_hud):
		turn_queue_hud.set_covered(paused)


## True while the deployment picker's screen is up.
func _picker_open() -> bool:
	return _picker_tile != DeploymentAssignment.NO_TILE


## Is ANYTHING of the map-hosted Formation screen standing over the battlefield right now (ADR-0261)?
##
## The one question the cursor's two deployment verbs ask before acting, and it has to be about the
## SCREEN rather than about the pick: `_picker_open()` answers "is a pick in progress", which was
## enough for ○ (a pick is the only screen ○ can raise while deploying) and never enough for ✕. A
## deployed unit can have its Status screen open over it with no pick anywhere, and ✕ there used to
## fall through to `_on_deployment_back` and BENCH whatever the map cursor was standing on.
##
## Asked of the coordinator's stack, not of this scene's own flags, because the stack is the thing
## that knows — that is the whole of what ADR-0261 made it able to answer.
func _screen_up() -> bool:
	if _formation_map_screen == null or not is_instance_valid(_formation_map_screen):
		return false
	return _formation_map_screen.current_state() != FormationDetailTransitionScript.State.IDLE


## ○ on an EMPTY zone tile: open the picker on the bench, over the tile you pressed.
##
## The list is the bench filtered by what this tile would actually TAKE — the reserve holds the last
## slot for a mandatory unit, so with four of five Gariland tiles filled the only name the picker
## offers is Ramza's. Offering a unit the confirm would then refuse is the "legal all the way to the
## commit and then refused at it" shape the reserve exists to end.
func _open_deployment_picker(column: Vector2i) -> void:
	if not assignment.tiles.has(column):
		SfxRouter.play_system(CUE_INVALID)
		print("[GambitBattle] %s is not a deployment tile." % str(column))
		return
	var eligible: Array = []
	for unit in assignment.benched():
		if assignment.placed_count() < assignment.effective_cap(unit):
			eligible.append(unit)
	if eligible.is_empty():
		_report_refusal(assignment.benched()[0] if not assignment.benched().is_empty() else null,
			column)
		return
	var host = _map_formation_host()
	if host == null:
		SfxRouter.play_system(CUE_INVALID)
		push_warning("[GambitBattle] No Formation screen to pick with")
		return
	var characters: Array = []
	var units_for: Array = []
	for unit in eligible:
		var character = FormationMapHost.character_for_unit(unit)
		if character == null:
			continue          # a unit the catalogue cannot name has nothing to show on the screen
		characters.append(character)
		units_for.append(unit)
	if characters.is_empty():
		SfxRouter.play_system(CUE_INVALID)
		push_warning("[GambitBattle] The bench resolved to no catalogue characters")
		return
	_picker_tile = column
	_formation_map_screen.action_rows = StartActionMenu.ROWS_DEPLOY
	_formation_map_screen.action_menu_location = StartActionMenu.LOC_DEPLOY
	# The pick is a STACK LEVEL, entered like any other screen (ADR-0261) — it is not `host.begin_pick`
	# called behind the coordinator's back any more. The offer goes in BEFORE the `enter`, the same
	# handshake `action_rows` above has: the leaf reads it while raising the grid.
	#
	# What the `enter` buys is the thing this scene could not arrange itself: the camera takeover
	# (and with it the battlefield cursor's freeze) is now held by the STACK, so a Status screen
	# opened over this grid and closed again cannot hand the cursor back underneath it.
	_formation_map_screen.pick_offer = {"characters": characters, "units": units_for}
	_formation_map_screen.enter(FormationDetailTransitionScript.State.PICK)
	if not host.picking():
		_picker_tile = DeploymentAssignment.NO_TILE
		_formation_map_screen.pick_offer = {}
		_formation_map_screen.action_rows = ADJUST_ROWS
		_formation_map_screen.action_menu_location = ""
		return
	print("[GambitBattle] Who fights on %s? %d on the bench — arrows to choose, Tab for the menu, Backspace to back out."
		% [str(column), characters.size()])


## "Deploy Unit" was chosen: the unit the grid's box is on lands on the tile the picker was opened
## from. You already expressed the placement by choosing that tile — do not ask twice.
func _on_picker_row_chosen(row: int) -> void:
	if not _picker_open() or row != DEPLOY_MENU_ROW:
		return
	var host = _map_formation_host()
	var unit = host.picked_unit() if host != null else null
	var tile: Vector2i = _picker_tile
	if unit == null or not assignment.place(unit, tile):
		_report_refusal(unit, tile)
		return
	SfxRouter.play_system(CUE_SET)
	print("[GambitBattle] Deployed %s to %s." % [unit.name, str(tile)])
	_close_picker()
	_show_assignment()


## The pick is over and its grid is down — the coordinator's own report (ADR-0261), raised whichever
## door ended it. `cancelled` is ✕ off the grid: the tile stays empty and the bench is unchanged,
## and the player is back on the map with the cursor where they left it.
func _on_pick_ended(cancelled: bool) -> void:
	if cancelled:
		SfxRouter.play_system(CUE_UNLATCH)
	_end_pick()


## Drop the grid, the menu and the camera hold, and hand the menu's rows back so a later △ on a
## deployed unit gets the four adjustment rows again. The one place a pick ends, whichever door
## ended it.
##
## A pick can have a SCREEN standing on it. The grid is a roster, so the roster's own ○ opens the
## picked unit's Status screen over it — and `open_action_menu` on that screen carries the very same
## deploy row (ADR-0247 §3 states the host-rows check on BOTH dispatches precisely because both
## doors exist). Ending the pick under one tore the grid and the dim down and left the Status panels
## over the map with the coordinator still owning the pad: the deploy had happened and the player
## had no way out of the screen it happened on.
##
## So the screen comes down first, and the whole stack comes down with it — `unwind_all()` (ADR-0261),
## because a completed deployment is a DESTINATION and not a step back. It walks the stack down one
## animated level at a time and lands at IDLE, and the PICK level at the bottom is what tears the
## grid down and reports `pick_ended`.
##
## [b]The `settled` one-shot this replaced was stealable.[/b] It armed `CONNECT_ONE_SHOT` on
## `settled` and called `leave()` again from the handler — but `settled` has eight emitters, so a
## detail box-open or a gambit surface landing between the arm and the reverse consumed the shot and
## drove an unwind nobody asked for. Sequencing a stack's own unwind belongs to the stack.
func _close_picker() -> void:
	_formation_map_screen.unwind_all()


## The pick's own teardown, once the coordinator says its grid is down: forget the tile and hand the
## menu's rows back, so a later △ on a deployed unit gets the four adjustment rows again.
func _end_pick() -> void:
	_picker_tile = DeploymentAssignment.NO_TILE
	_formation_map_screen.action_rows = ADJUST_ROWS
	_formation_map_screen.action_menu_location = ""


func _map_formation_host() -> FormationMapHost:
	if _formation_map_screen == null or not is_instance_valid(_formation_map_screen):
		return null
	return _formation_map_screen.formation() as FormationMapHost

#endregion


#region The turn-open beat (docs/TURN-OPEN-BEAT-DESIGN.md)

## The beat is a COMPONENT now ([TurnBeat], ADR-0265). The AT marker, the cue, the camera
## travel and the two battlefield input gates it closes are identical on both CombatLoop
## hosts, and `NavigatorMain` — which extends `ScenarioPlayerScene`, not `CombatHost` —
## could not inherit one line of it.
##
## What stays HERE is what is genuinely this host's: WHEN to arm the beat (`_commandable`,
## in `_on_turn_opened`), what to PRINT, and the third input gate, which is this scene's own
## `_unhandled_input` and which no component can close for us.
##
## The wrappers below are not ceremony. They are this host's vocabulary for the component's
## verbs, they lend it the per-battle handles it deliberately does not latch, and they are
## the names `GambitBattleTest` and `GambitSurfaceTest` already read.
var beat: TurnBeat = TurnBeat.mount()

## Mirrors [member TurnBeat.marker_unit] — the observable `GambitBattleTest` samples at each
## `turn_committed`.
##
## A get+set forwarding PAIR and not a getter-only property: GDScript drops a RUN of
## getter-only properties (and every member after it) from the subclass-visible member
## table, which is why `CombatHost` writes its four scalars this way and why
## `GambitSurfaceTest` — a subclass — can still see this one.
var turn_marker_unit: int:
	get: return beat.marker_unit
	set(value): beat.marker_unit = value

## Mirrors [member TurnBeat.marker] — the marker NODE, which `GambitBattleTest` asserts on
## directly: its PARENT (it must be a child of the taker) and its `position.y` (the
## per-sprite-type height table, #1065). Neither fact survives being reduced to an index, so
## the node has to stay reachable under the name that test already reads. A get+set pair, for
## the same reason as above.
var _turn_marker: TurnMarker3D:
	get: return beat.marker
	set(value): beat.marker = value


## Lend the component this host's cursor / camera / terrain / cast, immediately before every
## use. `cursor_rig` is built after `_ready` and `units` arrives at `commit_deployment`, so a
## bind taken once at construction would be a bind taken too early.
func _bind_beat() -> void:
	beat.bind(cursor_rig, get_node_or_null("PlayerCamera"), lattice, units)


## Arm the beat for a steerable taker, and say whose turn it is.
##
## The print is the host's and stays the host's: the component is mounted by two scenes that
## write two different log prefixes, and a component that printed would have to be told which.
func _open_turn_beat(taker: int, who: String, team: int) -> void:
	print("[GambitBattle] Your turn: %s (team %d). Tab to adjust, Space to commit, Backspace to cancel."
		% [who, team])
	_bind_beat()
	beat.open(taker)


## One frame of the travel, pumped from `_process` — see [method TurnBeat.advance] for why it
## is a frame counter and not an `await`.
func _advance_turn_beat() -> void:
	beat.advance()


## Beat over: the cursor gets its ears back. Called on commit as well as on landing.
func _end_turn_beat() -> void:
	beat.end()


## Is the travel running right now? The one predicate `_unhandled_input` asks — the THIRD of
## the three gates the beat closes, and the one that has to live on the host: Space, Home and
## Esc reach neither the cursor rig nor the camera.
func _turn_beat_running() -> bool:
	return beat.running()


## `Home` — snap BOTH cursor and camera back to the turn taker (design §4, and see
## [method TurnBeat.recenter] for why the design's stated reason is not the measured one).
func _recenter_on_taker() -> void:
	_bind_beat()
	beat.recenter()


## The AT marker seam — SHOW. Player turns only; the gate is `_commandable`, per
## TURN-OPEN-BEAT-DESIGN.md §5.
func show_turn_marker(unit_index: int) -> void:
	_bind_beat()
	beat.show_marker(unit_index)


## The AT marker seam — HIDE. On `turn_committed` and nowhere else.
func hide_turn_marker() -> void:
	beat.hide_marker()

#endregion


#region Turns

## A turn opened: the world froze on the exact tick a living unit crossed the meter.
##
## `taker == -1` is DEPLOYMENT, which this host opened itself and already reported.
func _on_turn_opened(taker: int, team: int) -> void:
	if taker < 0:
		return
	var who: String = units[taker].name if taker < units.size() else "unit %d" % taker
	if _commandable.has(taker):
		# The CPU half of the pre-turn image, taken at the same instant the director took the GPU
		# half and for the same reason: before any edit, while the meter is still unspent.
		adjustment.open(taker, FormationMapHost.character_for_unit(units[taker]))
		# The THIRD half of the pre-turn image (#1006): a charge is in no SSBO and on no Character,
		# so neither of the other two halves would refund one. Opened only for a taker the player
		# may steer, exactly as the adjustment window is — an enemy spends no charges.
		imperatives.open(taker)
		# The BEAT (`docs/TURN-OPEN-BEAT-DESIGN.md`). It is deliberately the LAST thing here and
		# the two `open()` calls above are deliberately the first: those two are the pre-turn
		# UNDO IMAGE and are taken at the crossing tick, while the beat is a 0.3 s travel. An
		# image taken at the end of the travel would snapshot a world the turn did not open in.
		_open_turn_beat(taker, who, team)
		return
	# Not yours to steer: a guest or an enemy. THIS is where the thinking beat runs (#897,
	# design §7) — inside the freeze the director already took, which is what makes it
	# invisible to the battle it forks from. A turn with no decision behind it is spent
	# unchanged, which is exactly "wait" (ADR-0239). Deferred so the commit never re-enters
	# the signal it is inside.
	print("[GambitBattle] %s acts (team %d)." % [who, team])
	_think_for(taker, team)
	call_deferred("_pass_turn")


## Build the driver, once, on the simulator the deployment just sized.
##
## After `start_battle` because that is what boots the simulator, and the driver takes a
## reference to it. A driver whose objective did not load is dropped here
## rather than carried: it would spend the whole horizon on every enemy turn and then return
## the incumbent by tie-break, which is indistinguishable in the log from a search that
## considered its options and held.
func _mount_rollout_driver() -> void:
	if not ai_enabled or gpu_simulator == null:
		return
	var driver := RolloutDriver.new(gpu_simulator, director.battle_id)
	if not driver.is_ready():
		push_warning("[GambitBattle] the rollout driver is not ready (objective '%s') — enemy turns will be spent unchanged" % RolloutDriver.objective_id)
		return
	rollout = driver
	# Reported from the COALESCED tunables and the simulator's own shape, not from the
	# static-var defaults — this line is what a session reads to find out what the AI is
	# about to do, and a line that reported the defaults while the beat ran a scrub would
	# be worse than no line.
	var s := RolloutDriver.settings()
	# The objective is named on its own line and BEFORE the shape line, because it is the
	# thing a session reading this log is most likely to be wrong about: `f` is the one the
	# subsystem's prose describes, and it is not the one running (ADR-0274).
	var horizon_check: Dictionary = RolloutDriver.check_horizon(driver.objective(), int(s["horizon"]))
	print("[GambitBattle] Rollout objective: '%s' — %s" % [
		driver.objective().id(), horizon_check["message"]])
	var sized: Dictionary = RolloutDriver.plan(float(s["cap_ms"]),
		gpu_simulator.get_units_per_battle(), gpu_simulator.get_num_battles(),
		int(s["candidates"]), int(s["seeds"]), int(s["horizon"]))
	print("[GambitBattle] Rollout AI armed: K=%d x M=%d x H=%d over %d battles at U=%d, ~%.0f ms/beat predicted against a %.0f ms cap%s"
		% [sized["k"], sized["m"], sized["horizon"], gpu_simulator.get_num_battles(),
			gpu_simulator.get_units_per_battle(), sized["predicted_ms"], sized["cap_ms"],
			"" if bool(sized["ok"]) else " — REFUSED: %s" % sized["reason"]])


## Run the beat for a taker the player does not command, and land its edit.
##
## Synchronous, inside `turn_opened`, in a world the director has already stopped — so its
## cost is a hitch the player sees between the turn opening and the enemy acting, and that
## is what `RolloutDriver.cap_ms` is priced as. Everything that could refuse has already
## refused by the time this returns: a driver that is not there, a plan that does not fit,
## a unit whose list admits no distinct edit. Each of those spends the turn unchanged.
func _think_for(taker: int, team: int) -> void:
	# `ai_enabled` gates the BEHAVIOUR and not only the mount, so a caller can turn the AI
	# off part-way through a battle — which is what a test does when it has proved the
	# wiring and wants the rest of the fight to be the fight it was written against.
	if rollout == null or not ai_enabled:
		return
	var ctx := _rollout_context(taker)
	if ctx.is_empty():
		return
	var decision: Dictionary = rollout.decide(taker, team, ctx)
	last_decision = decision
	if bool(decision["ok"]):
		beats_taken += 1
	if not bool(decision["ok"]):
		print("[GambitBattle]   no decision: %s" % decision["reason"])
		return
	if bool(decision["held"]):
		# "v" and not "P(win)": only the fitted objective returns a probability, and a log
		# line that spelled the provisional objective's ordering as one would be the same
		# lie the `p_victory` key was (ADR-0274 dec. 4).
		print("[GambitBattle]   holds its posture (v %.3f, %.0f ms)"
			% [decision["value"], decision["beat_ms"]])
		return
	if rollout.apply(taker, decision["rows"]):
		print("[GambitBattle]   re-plans to candidate %d: v %.3f over the incumbent's %.3f (%.0f ms)"
			% [decision["candidate"], decision["value"], decision["value_incumbent"],
				decision["beat_ms"]])


## The taker's static facts, as `RolloutCandidates` wants them: job, usable abilities, max
## MP, and the very ability table the shader indexes.
##
## Host knowledge by construction — `RolloutDriver` does not know what a `Character` is, for
## the same reason `AdjustmentTurn` does not.
##
## The ability set is the union of what the unit has LEARNED and what its gambit list
## already NAMES, and it is sorted. The union, because an ENTD-placed enemy is built from a
## ROM record and need not carry a learned-ability table at all — a unit whose gambits cast
## Fire can obviously cast Fire, and reading only `learned_abilities` would hand the search
## an empty action family and leave the AI shuffling conditions. Sorted, because candidate
## order is part of what makes the choice reproducible, and `Dictionary.keys()` is insertion
## order — a property of how a `Character` was BUILT, not of what it is.
func _rollout_context(taker: int) -> Dictionary:
	var unit = units[taker] if taker >= 0 and taker < units.size() else null
	if unit == null:
		return {}
	var character = FormationMapHost.character_for_unit(unit)
	if character == null or character.progression == null:
		return {}
	var ids := {}
	for raw in character.progression.get_learned_abilities():
		ids[int(raw)] = true
	if character.gambits != null:
		for gambit in character.gambits.gambits:
			if gambit != null and gambit.ability_id >= 0:
				ids[int(gambit.ability_id)] = true
	var ability_ids: Array = ids.keys()
	ability_ids.sort()
	return RolloutCandidates.make_context(character.progression.current_job_id,
		ability_ids, int(unit.max_mp), _rollout_ability_buffer())


## The packed ability table, built once. It is the WHOLE database and depends on no unit, so
## a per-beat rebuild would walk 512 ability records to produce the same bytes every time.
func _rollout_ability_buffer() -> PackedInt32Array:
	if _ability_buffer.is_empty():
		_ability_buffer = GPUAbilityLoader.build()["buffer"]
	return _ability_buffer


func _pass_turn() -> void:
	if director != null and director.state() == TurnDirector.State.TURN_OPEN:
		director.commit()


## The turn was spent: land whatever the player edited, on the GPU, now.
##
## The director emits this AFTER `consume_turn` and BEFORE it drains into the next turn, and its
## drain recomputes the ready list rather than caching it — expressly so a `reconfigure_unit`
## landing here is seen by the very next turn (ADR-0239). This is the only place in the scene where
## a Character edit crosses to the kernel.
func _on_turn_committed(taker: int) -> void:
	# The beat's other end, before either branch below: the marker is hidden on commit and the
	# cursor is handed back its ears whatever else happens here. A turn that committed inside its
	# own travel — Space held from the previous turn, the rollout passing a turn on the frame it
	# opened — would otherwise leave a deaf cursor and a marker on a unit that has already acted.
	hide_turn_marker()
	_end_turn_beat()
	beat.beat_taker = -1
	if not _commandable.has(taker) or not adjustment.is_open():
		adjustment.commit(null, 0, null)   # clears the window; nothing to land
		imperatives.close()
		return
	var unit = units[taker] if taker < units.size() else null
	var character = FormationMapHost.character_for_unit(unit)
	_report_prune(AdjustmentTurn.prune_unusable_gambits(character), character)
	# The imperative rides the SAME second write (ADR-0252 dec. 6) as a lead entry ahead of the
	# unit's four slots — it is a gambit-list edit, so it needs no write path of its own.
	if adjustment.commit(gpu_simulator, director.battle_id, unit,
			imperatives.entry_for(taker)):
		print("[GambitBattle] Turn landed: %s reconfigured." % _name_of(unit))
	if imperatives.close():
		print("[GambitBattle] Imperative standing on %s — %d charge(s) left."
			% [_name_of(unit), imperatives.charges_left(taker)])


## The turn's edits were thrown away. The director has already restored the GPU half; this is the
## CPU half, and it must run BEFORE the director re-opens the same turn and takes its fresh image —
## which it does, because `TurnDirector.cancel` emits this before calling `_open_turn`.
func _on_turn_cancelled(taker: int) -> void:
	var unit = units[taker] if taker >= 0 and taker < units.size() else null
	if adjustment.cancel(FormationMapHost.character_for_unit(unit)):
		print("[GambitBattle] Turn cancelled: %s restored." % _name_of(unit))
	# Design §4: "cancel must refund any imperative charge spent that turn, or cancel becomes a
	# trap". The refund is a plain CPU restore, like the Character's, and for the same reason — the
	# charge was never on the GPU for the director's snapshot to have taken it back.
	var refunded := imperatives.cancel()
	if refunded > 0:
		print("[GambitBattle] Imperative refunded: %s keeps %d charge(s)."
			% [_name_of(unit), imperatives.charges_left(taker)])


## May this unit be edited right now (#894)? Handed to the map-hosted Formation screen as a
## Callable, so the screen asks the phase instead of guessing it.
##
## Three phases, three answers. DEPLOYMENT: yes for anyone the screen will show — no GPU battle
## exists yet (design S9), so an edit has nothing to diverge from and lands at commit by
## construction. TURN_OPEN: only the taker, because a wider rule makes your fastest unit a
## universal remote and every other CT bar decoration. RUNNING: nobody — the turn IS the
## reconfiguration, so editing while the world plays would make the turn order ornamental.
func _unit_is_steerable(unit) -> bool:
	if director == null:
		return true
	# THE PHASE IS ASKED BEFORE THE UNIT, and that order is the whole of a regression this
	# already caused: during the deployment PICK the screen is showing a BENCHED unit, which
	# stands on no tile, so the map host's `_selected_unit` is null — and a null-first guard
	# returning false took the picker's one row dead. `selection_is_owned` has the matching rule
	# in the other direction ("an unresolvable selection degrades to owned"), so degrading to
	# REFUSED here was the disagreement. Mid-battle a null selection is still not steerable,
	# because the screen is not on a unit and `units.find(null)` is -1 anyway.
	if director.state() == TurnDirector.State.DEPLOYMENT:
		return true
	if unit == null:
		return false
	var index := units.find(unit)
	return _commandable.has(index) and adjustment.steerable(index, true, false)


## The edit surface opened on somebody. Only the taker's opening marks the turn as touched, and a
## touched turn is the only one that pays for a commit push — `reconfigure_unit` on an unedited
## unit is a proven no-op (ADR-0235), so this is a cost gate and never a correctness one.
func _on_unit_act_requested(_character) -> void:
	var host := _map_formation_host()
	if host == null or not host.selection_is_steerable():
		return
	adjustment.touch()


#region Imperatives (#1006)

## Which unit index `character` is. The imperative ledger is keyed by index because charges are
## BATTLE state; the Character is the durable representation that outlives the battle (ADR-0005),
## and the index is the only name the GPU buffers and this scene's `_commandable` share.
##
## `-1` before deployment commits — `units` does not exist until then (design S9), and a surface
## opened during the pick is looking at a benched unit that is in no battle.
func _unit_index_of_character(character) -> int:
	if character == null:
		return -1
	for i in range(units.size()):
		if FormationMapHost.character_for_unit(units[i]) == character:
			return i
	return -1


## The world's tick right now, for the deadline an issue stamps.
func _current_tick() -> int:
	return combat_loop.current_tick if combat_loop != null else 0


## An imperative was issued on the surface — report it. The order is already in the ledger and it
## crosses to the GPU at THIS turn's commit, as the lead entry `_on_turn_committed` hands to
## `AdjustmentTurn.commit`. Nothing to push here, and pushing would push it a turn early.
func _on_imperative_issued(_order) -> void:
	SfxRouter.play_system(CUE_LATCH)


## The unit acted — design §5's removal edge. One action is what a one-shot order buys, so it is
## gone, and the buffer that still names it has to be re-pushed without it.
##
## DEFERRED, for the reason `_pass_turn` is: this fires from inside the loop's event
## interpretation, and a GPU write that re-entered the tick it was raised by would be writing a
## buffer the same frame's dispatch is reading.
func _on_action_committed(unit_index: int, _ability_id: int, _target: int) -> void:
	if not imperatives.withdraw(unit_index):
		return
	call_deferred("_repush_gambits", unit_index)
	print("[GambitBattle] Imperative spent: %s acted." % _name_of(_unit_at(unit_index)))


## Take every imperative that has become uncompletable and re-push the units that lost one.
##
## Only while the world is RUNNING. A frozen turn advances no ticks and kills nobody, so a sweep
## there could only ever act on state the last stretch already left behind — and it would do it in
## the middle of the turn whose cancel is supposed to be able to take it back.
func _sweep_imperatives() -> void:
	if imperatives.idle() or director == null or combat_loop == null:
		return
	if director.state() != TurnDirector.State.RUNNING:
		return
	for unit_index in imperatives.expire(combat_loop.current_tick, _imperative_pool_alive):
		_repush_gambits(unit_index)
		# NO refund, and design §5 says why in as many words: a wasted lock-on is a real mistake.
		print("[GambitBattle] Imperative expired: %s never got to it."
			% _name_of(_unit_at(unit_index)))


## Does `entry`'s target pool still have anybody in it? The watchdog's "target dead/removed"
## (design §5), asked of the battlefield because that is where the answer is.
##
## The POOL and not a named unit, because the GPU cannot express a named one —
## `TargetSelector.PoolType.SPECIFIC_UNITS` is in `GambitEncoder.UNSUPPORTED_POOL_TYPES`, so an
## order claiming to lock onto one unit would encode as something else. An imperative locks onto a
## RULE, and this asks whether the rule can still pick anybody out.
##
## Liveness only. Reachability, line of sight and affordability are the shader's decisions, and a
## CPU copy of one is a second opinion that will eventually disagree with the kernel that acts.
func _imperative_pool_alive(unit_index: int, entry) -> bool:
	if entry == null or entry.condition_target == null:
		return false
	if not _unit_alive(unit_index):
		return false
	var aim = entry.condition_target
	# SELF and TRIGGERING both resolve to the actor here (an order acts on whoever it picked out,
	# and with no standing trigger that is the unit itself), so the pool is alive exactly while it
	# is — which the check above already established.
	if aim.pool_type != TargetSelector.PoolType.TEAM_FILTER:
		return true
	for i in range(units.size()):
		if i == unit_index or not _unit_alive(i):
			continue
		if aim.team_filter == TargetSelector.TeamFilter.ANY:
			return true
		var want_enemy: bool = aim.team_filter == TargetSelector.TeamFilter.ENEMY
		if _same_team(unit_index, i) != want_enemy:
			return true
	return false


## Push `unit_index`'s gambit buffer as it stands NOW — its authored slots, led by whatever
## imperative the ledger holds for it (none, after a withdraw). One function for both removal
## edges, so "what the kernel should be reading" is stated once.
func _repush_gambits(unit_index: int) -> void:
	var unit = _unit_at(unit_index)
	if unit == null or gpu_simulator == null or director == null:
		return
	gpu_simulator.set_unit_gambits(director.battle_id, unit_index,
		GambitEncoder.encode_for_unit(unit, imperatives.entry_for(unit_index)))


func _unit_at(unit_index: int):
	if unit_index < 0 or unit_index >= units.size():
		return null
	return units[unit_index]


func _unit_alive(unit_index: int) -> bool:
	var unit = _unit_at(unit_index)
	return unit != null and is_instance_valid(unit) and not unit.is_dead


## `units` is `team0_units + team1_units` contiguously (the split `units_per_battle` encodes), so
## team membership is a comparison against team0's size and needs no per-unit field.
func _same_team(a: int, b: int) -> bool:
	var split := team0_units.size()
	return (a < split) == (b < split)

#endregion


## Say what a job or sub-job change cost the unit's gambit list. Silence when nothing was pruned.
##
## SHOWN, never silent: a gambit list that looks armed and is not is the most confusing failure
## this design can produce, and it is worse than either refusing the job change or leaving a slot
## that no-ops (design §4).
func _report_prune(pruned: Array, character) -> void:
	if pruned.is_empty():
		return
	var who: String = character.display_name if character != null else "unit"
	for g in pruned:
		print("[GambitBattle] %s can no longer do that — gambit pruned: %s" % [who, str(g)])
	SfxRouter.play_system(CUE_INVALID)


func _name_of(unit) -> String:
	var character = FormationMapHost.character_for_unit(unit)
	return character.display_name if character != null else "unit"


func _on_victory(winner: int, team0_alive: int, team1_alive: int) -> void:
	# Annihilation is the engine's own rule (design S10) — the GPU declares the winner
	# when one side has nobody standing, and this host does not add a second condition or
	# quit on it. It reports.
	print("[GambitBattle] Battle over — winner team %d (team0 %d alive, team1 %d alive)."
		% [winner, team0_alive, team1_alive])

#endregion


#region Input

## The cursor's confirm. What ACTING means is the phase's answer, not the keycode's — and in
## exactly one phase, DEPLOYMENT, the answer is this host's. Everywhere else ○ belongs to the
## screen, and this handler declining is what hands it over.
##
## 🔴 NOTHING HERE MAY WRITE DIRECTOR STATE. [FormationMapHost] is the second listener on this
## signal and it evaluates `can_open` when the signal reaches IT, not when it was emitted, so a
## state change made here is read by the other handler as though it had always been true. That is
## not a dispatch, it is a read-after-write race in emission order, and it is why the turn-commit
## moved to Space.
func _on_cursor_confirmed(column: Vector2i) -> void:
	if director == null or not _cursor_confirm_is_mine():
		return
	if director.state() == TurnDirector.State.DEPLOYMENT:
		_on_deployment_confirm(column)


## Is ○ THIS scene's, or the map-hosted Formation screen's? The two listen to one signal, so the
## answer has to be one predicate both of them read — the screen's `can_open` is this, negated.
## Before ADR-0137 Amendment 2 each side checked a private condition and a press could fall through
## both; that is how "nothing happens" got in, and here it would have been worse than nothing,
## because the two would both act on the same press.
##
## DEPLOYMENT and nothing else. It used to also claim a commandable taker's TURN_OPEN, and that
## claim was the one state in which this predicate could DISAGREE WITH ITSELF between the two
## listeners: this host's handler committed, `state()` went RUNNING, and the screen then read a
## predicate that had flipped under it. A predicate that only ever answers "is the deployment
## running" cannot be changed by anything a confirm handler does, which is what makes the two
## readings agree by construction rather than by connect order.
func _cursor_confirm_is_mine() -> bool:
	if director == null:
		return true
	return director.state() == TurnDirector.State.DEPLOYMENT


## ✕/Backspace, as a CURSOR intent (#941). Deploying, it lets go of the latch or recalls the unit
## under the cursor; on your turn it cancels the turn. It is the same shape its twin has — the
## cursor says the player asked to back out, and the PHASE supplies what backing out means.
func _on_cursor_cancelled(column: Vector2i) -> void:
	if director == null:
		return
	match director.state():
		TurnDirector.State.DEPLOYMENT:
			_on_deployment_back(column)
		TurnDirector.State.TURN_OPEN:
			if _commandable.has(director.taker()):
				director.cancel()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if director == null:
		return
	# THERE IS NO SKIP (design §1). The third of the three gates `_open_turn_beat` sets — this
	# handler owns Space and Esc, which reach neither the cursor nor the camera, so without this
	# the player could still start or pause a battle out from under a running beat.
	if _turn_beat_running():
		get_viewport().set_input_as_handled()
		return
	# The classic pause is MODAL, and this is the half of the swallow the cursor's and camera's
	# `input_enabled` cannot cover — Space, Home and Esc reach neither of them. Esc is let through
	# below because a modal with no reachable exit is a lock-out, not a pause.
	if pause_screen_open():
		if event.is_action_pressed("battle_pause"):
			_toggle_pause_screen()
		get_viewport().set_input_as_handled()
		return
	# The way back to the taker from anywhere (design §4). Above START and PAUSE only because it
	# is the cheaper test; the three are disjoint actions and the order is not load-bearing.
	if event.is_action_pressed("turn_recenter"):
		_recenter_on_taker()
		get_viewport().set_input_as_handled()
		return
	# Space is GO — the one key that ends a stop the player is expected to end, in BOTH states
	# that have one. It is still never a pause key (ADR-0137 Amendment 2's actual rule): a pause
	# is a stop with no decision behind it and Esc both makes and unmakes it.
	if event.is_action_pressed("battle_start"):
		match director.state():
			TurnDirector.State.DEPLOYMENT:
				commit_deployment()
				get_viewport().set_input_as_handled()
			TurnDirector.State.TURN_OPEN:
				# Yours to steer only. A guest's or an enemy's turn is opened and passed by
				# `_on_turn_opened` inside the same freeze, so there is no press to serve here —
				# and serving one would let the player spend a turn that is not theirs.
				if _commandable.has(director.taker()):
					# Committing with no edits IS "wait": there is no separate pass verb, because
					# spending a turn having changed nothing is exactly what waiting is (ADR-0239).
					director.commit()
					get_viewport().set_input_as_handled()
			TurnDirector.State.RUNNING:
				_toggle_running()
				get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("battle_pause"):
		_toggle_pause_screen()
		get_viewport().set_input_as_handled()
		return
	# ✕/Backspace is NOT here any more (#941). It arrives as `CursorRig.cursor_cancelled`, beside
	# confirm and inspect — a host-local keybind for one of three cursor intents is how `unit_inspect`
	# came to be bound by three different host actions.


## Space's third meaning, and the one that makes the other two read as one key: **a plain toggle on
## whether the battle is running.** Press to stop the clock, press again to start it.
##
## Space is not "commit" and it is not "start"; it is **stop/go**, and commit is what going means
## when a turn is stopping the world. This is the TACTICAL stop: the clock halts and everything
## else stays live — the cursor walks, the camera pans, ○ opens a unit's screen. Stop and look.
##
## RUNNING only, and the guard is not a formality: during DEPLOYMENT and TURN_OPEN the world is
## already frozen by somebody who is owed a decision, and flipping `combat_active` under them would
## run the battle while the player is still deciding — and would leave `state()` disagreeing with
## whether the world is live, which is the invariant `TurnDirector.commit` spells out.
## Those two states never reach here anyway; the `match` above sends them to their own verbs.
func _toggle_running() -> void:
	if director.state() != TurnDirector.State.RUNNING:
		return
	combat_active = not combat_active
	print("[GambitBattle] %s" % ("running" if combat_active else "stopped (Space)"))


func _on_quit_requested() -> void:
	get_tree().quit()

#endregion


#region The stop badge

## The one line of chrome that says WHICH stop the world is in.
##
## Three of this scene's four states show a motionless battlefield, and until this landed they were
## pixel-identical: deployment, a pause, and an open turn all read as "the game froze". The keys
## that end them are not the same key, so a player with no badge has to guess, and guessing wrong
## on ○ used to spend a turn (see `_on_cursor_confirmed`). A correct binding that the player cannot
## SEE is still an unusable binding.
##
## The SEAT is a component now ([StopBadge], ADR-0265) — `NavigatorMain` grew the same four states
## and the same guessing problem. What stayed here is the SENTENCE: this host's states, and the
## keys that end them, are this host's vocabulary.
var _stop_badge: StopBadge = null
## The component's label, under the name `GambitBattleTest` arm 4d already reads — that arm asserts
## on the NODE and not only on the pure predicate below, because a pure predicate can be right
## about a badge nobody mounted. A plain var holding the same object, not a forwarding property:
## GDScript drops a RUN of getter-only properties from the subclass-visible member table, and
## `GambitSurfaceTest` is a subclass.
var _pause_badge: Label = null


func _mount_pause_badge() -> void:
	_stop_badge = StopBadge.mount(self)
	_pause_badge = _stop_badge.label
	_mount_pause_screen()


## What the badge should say right now, or `""` for "the world is running, show nothing".
##
## PURE, and public for the reason every other predicate on this host is: a test can ask what the
## player would be told without owning a viewport or reading a pixel.
func stop_badge_text() -> String:
	if director == null:
		return ""
	# The classic pause is a SCREEN and it says PAUSED itself, in the middle, over a dimmed
	# battlefield. A second line of chrome under it would be saying it twice.
	if pause_screen_open():
		return ""
	match director.state():
		TurnDirector.State.DEPLOYMENT:
			return "DEPLOYING — Space to start"
		TurnDirector.State.TURN_OPEN:
			# A guest's or an enemy's turn is opened and passed inside the same freeze
			# (`_on_turn_opened`), so there is no press to advertise and the badge would flash
			# once per enemy turn saying something the player cannot act on.
			if not _commandable.has(director.taker()):
				return ""
			return "YOUR TURN: %s — Space to commit, Tab to adjust, Backspace to cancel" % _name_of(
				_unit_at(director.taker()))
	# RUNNING, and Space has stopped the clock. Named STOPPED and not PAUSED on purpose: the
	# classic pause takes the screen and refuses everything, and this one takes nothing — the
	# cursor still walks, the camera still pans, ○ still opens a unit. It is a stop you look
	# around inside, and calling both of them "paused" is what would make the two keys feel
	# redundant when they are doing different jobs.
	return "" if combat_active else "STOPPED — Space to resume, ○ to inspect"


## Polled, not driven off an edge — see [method StopBadge.show_text] for why.
func _refresh_pause_badge() -> void:
	if _stop_badge == null:
		return
	_stop_badge.show_text(stop_badge_text())

#endregion


#region The classic pause (Esc)

## Esc's pause is a SCREEN, and Space's is not. That is the whole distinction, and it is the reason
## the two keys are not redundant now that Space carries stop/go:
##
##   - **Space STOPS THE CLOCK.** A plain toggle, and nothing else stops with it. Walk the cursor,
##     pan the camera, open a unit's screen, read the turn queue. It is the tactical stop — you
##     stopped the world in order to look at it, so the world stays reachable.
##   - **Esc PAUSES.** The battlefield dims, `PAUSED` sits in the middle of it, and every other key
##     is refused until Esc comes back. It is the classic pause — you stopped *playing*.
##
## Two stops that look identical are a UI defect (that is what this whole change is about); two
## stops that are VISIBLY different and reachable by different keys are two features.
##
## Modal by construction, not by convention: `input_enabled` goes false on the cursor rig and the
## camera — the same two gates the turn-open beat uses — so the swallow does not depend on this
## host's `_unhandled_input` winning a race it does not win. Godot delivers `_unhandled_input`
## bottom-up, so [TileCursor] (a child) sees a press BEFORE this scene root does.
var _pause_screen: PauseScreen = null
## The pause screen's OWN saved clock, deliberately not `_combat_active_before_screen`. Sharing one
## slot with the Formation screen would let whichever closed second write the other's answer back,
## and "resume put the world in the state a DIFFERENT screen found it in" is a bug nobody would
## look for. The two are mutually exclusive today — a pause screen refuses to open over the
## Formation screen, and the Formation screen cannot be opened under a pause screen because the
## cursor is deaf — but exclusivity enforced in two places is not a reason to share the variable.
var _combat_active_before_pause := false


func _mount_pause_screen() -> void:
	# The SEAT is [PauseScreen] now (ADR-0265 dec. 4's shape, the same split [StopBadge] took):
	# a CanvasLayer at 20, a scrim that darkens rather than hides, the title and the stated
	# exit. What stayed here is the POLICY — what a pause freezes, what closing it restores,
	# and the Formation-claims refusal below.
	_pause_screen = PauseScreen.mount(self)


## Is the classic pause screen up? Public: it is the one question every other input owner on this
## host has to be able to ask, and a private flag would make each of them keep their own.
func pause_screen_open() -> bool:
	return _pause_screen != null and is_instance_valid(_pause_screen) and _pause_screen.is_open()


## Esc. Open the pause screen over whatever the world was doing, or close it and put that back.
##
## Available in EVERY state, including a frozen one. "You may not pause while it is your turn" is a
## rule with nothing behind it — the clock is already stopped, so pausing costs the battle nothing
## and refusing it is the second dead key this change exists to remove. What matters is that
## RESUMING restores rather than assumes: closing a pause taken during a turn must not start the
## battle, and closing one taken while Space had stopped the clock must not start it again.
func _toggle_pause_screen() -> void:
	if _pause_screen == null:
		return
	if pause_screen_open():
		_pause_screen.close()
		combat_active = _combat_active_before_pause
		_set_battlefield_input(true)
		print("[GambitBattle] resumed")
		return
	# Not over the Formation screen. That screen holds the camera takeover and its own saved clock
	# (ADR-0261), and a second modal over it would release claims it did not take — the exact
	# ownership bug that produced a hard lock-out here once already. Its own ✕ closes it first.
	if _formation_map_screen != null and _formation_map_screen.claims_held():
		return
	_combat_active_before_pause = combat_active
	combat_active = false
	_pause_screen.open()
	_set_battlefield_input(false)
	print("[GambitBattle] paused")


## The two device-input gates the battlefield accepts on, driven together. The same pair
## `_open_turn_beat` sets, and for the same reason: gating one of the two is not a swallow, it just
## tells the player which key still works.
##
## Safe to interleave with the turn-open beat because the two can never overlap — `_unhandled_input`
## swallows every key while a beat is travelling, so Esc cannot open this screen mid-beat; and no
## turn can OPEN under the pause screen, because the clock it would open on is stopped.
func _set_battlefield_input(enabled: bool) -> void:
	if cursor_rig != null:
		cursor_rig.input_enabled = enabled
	var cam := get_node_or_null("PlayerCamera")
	if cam != null:
		cam.input_enabled = enabled

#endregion


#region Helpers

## A unit's catalogue slug, handed to [DeploymentAssignment] as a Callable so that class
## never has to know what a `Unit` is. Identity is the slug meta, never `name` (ADR-0180).
func _slug_of(unit) -> String:
	if unit == null or not unit.has_meta(UnitSpawn.CHARACTER_SLUG_META):
		return ""
	return String(unit.get_meta(UnitSpawn.CHARACTER_SLUG_META))

#endregion
