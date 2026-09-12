extends "res://src/scenarios/ScenarioPlayerScene.gd"
## The game-state navigator's LIVE BOOT (HANDOFF_navigator_live_boot.md #4, decision
## #179). Walks the FFT story graph through the Orbonne opening run — prayer (group 1)
## → Orbonne battle (ENTD-387, scn 3) with a woven opener (scn 4) + victory (scn 6) →
## chain to Military Academy (group 7) → Gariland (group 9), played in full, and out onto
## the WORLD MAP that group 9's `world-map` successor lands on.
##
## Reuses ScenarioPlayerScene as the persistent world + playback primitive (map,
## camera, ENTD spawn, event VM, dialogue) via the inherited `_boot_scenario_world()`
## and `_play_member()`. It OWNS the walk ([GameNavigator] plan + [NavigatorRunner]
## state machine) and implements the runner's EXECUTOR, driving each sub-scene and
## advancing on its finish signal:
##   - SCENARIO groups: the applier plays the members, `ScenarioVM.group_finished`
##     yields → on_scenario_finished().
##   - BATTLE group: opener/victory beats play as members; combat is a BARE CombatLoop
##     on the SAME world units (decision #180), `CombatLoop.victory` yields →
##     on_combat_finished().
##
## Boot directly: `godot --path . res://assets/scenes/NavigatorMain.tscn`.
##
## PLAY ONE BATTLE: `-- --battle=N` (add `--watch-opener` to watch the opener play instead of
## fast-forwarding it). N is the battle GROUP ROOT, which is its setup record's scenario id
## — `--battle=9` is Gariland. This is the whole of "gambit mode's boot from one integer"
## (ADR-0264): the walk is planned as that one group and begun at its `pre_battle`
## action, so the battle inherits the spine's framing (the opener's terminal `{19}`), its
## clock (`ScenarioVM.idle_only_units`) and its facing (the zone's `unit_facing` nibble)
## rather than a second host re-deriving all three.
##
## PLAY IT AS A BATTLE: add `--stop-on-turn` and the walk stops on every turn that is
## YOURS, with the AT marker on the taker, the camera travelling to them and a badge saying
## which key ends the stop (ADR-0265). Space spends the turn, Home recentres on the taker,
## Esc pauses. Enemy turns are spent where they open.
##
##   godot --path . res://assets/scenes/NavigatorMain.tscn -- --battle=9 --stop-on-turn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const AnimationStateController = ExMateriaSpriteRig.AnimationStateController

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const CursorRig = ExMateriaBattlefield.CursorRig

## And the same for `addons/exmateria_schema`, whose six generic-English globals
## collapsed onto one façade in the same pass (ADR-0212 dec. 1).
const TerrainCell = ExMateriaSchema.TerrainCell

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const DeploymentZoneDatabase = ExMateriaAlmanac.DeploymentZoneDatabase

## ADR-0215 dec. 2 / ADR-0217 dec. 7 — the sprite rig's VALUE VOCABULARY is the
## kernel's; the behaviour-bearing hosts keep their class names and their behaviour.
## This line is what keeps the use sites below spelled the way they were
## (ADR-0211 dec. 4).
const ClockOwner = ExMateriaSchema.ClockOwner.Kind
const Character = ExMateriaCatalogue.Character
const RosterDebugView = ExMateriaCatalogue.RosterDebugView
const SlugBinding = ExMateriaCatalogue.SlugBinding
# 🔴 NO `PsxNum` ALIAS HERE, AND THAT IS DELIBERATE. This scene EXTENDS
# `ScenarioPlayerScene.gd`, which declares one, and GDScript refuses a member
# that already exists in the parent — *"The member `PsxNum` already exists in
# parent class"*, a parse error that takes this whole file out. The inherited
# constant is what `_ready()` below reads (ADR-0212 dec. 1, ADR-0211 dec. 4).


const START_ROOT := 1
## Stop sentinel: walk the successor chain to its NATURAL end rather than truncating it at a
## nominated group. Same value + same meaning as [code]NavigatorDebugPanel._NATURAL_END[/code]
## and as a [code]navigator_stop_root <= 0[/code] seek.
##
## [b]It used to be 9, and that one constant was the whole reason the walk never reached the
## overworld.[/b] The C2 crossing built every piece — [method GameNavigator.successor_kind] reads
## group 9's `world-map` successor, the planner appends a terminal `world_map` action on it,
## [NavigatorRunner] dispatches it, [method run_world_map] mounts the screen — and C2's own
## guard asserted, correctly, that `plan_actions(1, 9)` must NOT gain that action, because a
## stop root means STOP. Nothing was broken; the cold boot simply asked for a walk that ended
## one action short of the map, and no test read these constants to notice. Now it asks for
## the whole chain: 1 → 3 (Orbonne) → 7 (Military Academy) → 9 (Gariland, played in full:
## opener → deployment → combat → victory) → WORLD MAP. Groups chain by their graph exits
## (scn6 successor→7, scn8 successor→9); grp7 is a pure cinematic (no combat).
##
## A seek from the F3 Navigator panel still overrides this, and the three end-to-end
## navigator tests pin `navigator_stop_root = 9` explicitly, so they keep their old bound.
const STOP_ROOT := 0
const BATTLE_SEED := 0x0FF7   # deterministic auto-battle seed (v1: no live control)
## AUTOSAVE tunable (ADR-0068): when true, the universal pre-battle config breakpoint is
## skipped (straight to combat) — the pre-battle analogue of dialogue auto-advance. Toggle
## in the F3 Navigator panel; read (register-and-read) in `run_pre_battle`.
const SKIP_PRE_BATTLE_SLUG := "navigator.skip_pre_battle"

## AUTOPLAY (ADR-0068, default false): the walk drives itself. A PROFILE, not a mechanism —
## it turns on every gate that would otherwise wait for a human, and each of those stays
## independently settable so you can (say) auto-advance the map while still stopping at the
## pre-battle breakpoint. The four gates, three of which already existed:
##   - dialogue boxes      `scenario_vm.auto_advance` (ScenarioPlayerScene already forces it)
##   - pre-battle          `navigator.skip_pre_battle`
##   - a LOSS halts        `navigator.owned_invincible` — without it NavigatorRunner logs
##                         "combat lost" and stops, which reads as a hang in a sweep
##   - the world map       `navigator.auto_advance_node`, below
##
## [b][constant STOP_ON_TURN_SLUG] is deliberately NOT in this profile[/b], and it is the
## one gate you would expect to be: its SET state is the one that waits for a human, so
## "the walk drives itself" reads like it should suppress it. Three reasons it is not.
##   - This profile only ever turns a gate ON. Every entry above is something autoplay
##     wants set, ORed in by `_autoplay_gate`; a term that turned one OFF would be a second
##     and opposite kind of profile behaviour wearing the same name.
##   - Autoplay is a working state a human sits in, not a marker of an unattended process
##     — it is the natural thing to have on while walking to a battle you then want to
##     stop in. A profile term would make the new toggle silently dead exactly there: you
##     tick it, nothing happens, and nothing says why.
##   - The thing the suppression would protect does not need it. The opener sweep
##     (`tools/sweep_opener_fast_forward.py`) passes `--quit-after`, an unscaled real-time
##     auto-quit, and reads the `[opener-ff]` line ~15-25 s in — before combat exists. It
##     cannot hang on a turn.
## What DOES need protecting is the unattended end-to-end walks, and they protect
## themselves the way they already protect themselves from `skip_pre_battle`: each pins the
## slug false in its own `_ready`. See any of the five.
const AUTOPLAY_SLUG := "navigator.autoplay"

## AUTOPLAY tunable (ADR-0068, default false): on arriving at the overworld, take the one
## live hand-off instead of waiting for ○.
##
## No policy object, because the map has none to choose from: 44 of the 45 story-counter
## values that bind an `enter` bind exactly ONE, and the 45th (47) disambiguates on
## `var[162]`. So the rule is "if there is exactly one, take it" — and 0 or >1 STOPS with a
## named report rather than picking, because either is a real anomaly.
const AUTO_ADVANCE_NODE_SLUG := "navigator.auto_advance_node"

## AUTOSAVE tunable (ADR-0068, default false): the walk's battle STOPS on every turn, and
## Space spends it. The development gate for combat — hands-off is right for seeking, and
## you cannot develop a fight you cannot stop.
##
## Default false is load-bearing and not a preference. The walk's battle is a fast-forward
## that must auto-resolve to `winner == 0` for the end-to-end tests, and a world that stops
## on each turn with nobody there to press Space does not fail them, it HANGS them. So the
## stop opts in — and because this is an AUTOSAVE slug in the TRACKED
## `config/tune_overrides.json`, ticking it in the F3 panel arms it for every process in
## the checkout. The five tests that reach a live navigator battle therefore PIN it false
## in `_ready` rather than assuming the default, exactly as `NavigatorBattleLaunchTest`
## pins `skip_pre_battle`. A new test that goes live on this host owes the same two lines.
##
## It is NOT folded into [constant AUTOPLAY_SLUG]'s profile — see the note there for why.
##
## [b]Whose slug is this, and why not the director's?[/b] `TurnDirector` owns the field and
## already owns a tunable (`gambit.playback_rate`) — but that one is a `static var`, i.e.
## ONE value for every director in the process, and `stops_the_world` is exactly the thing
## the two hosts disagree about: `GambitBattle` is played by hand and keeps the default
## true, this walk is not. A `gambit.*` static var would make one host's stop policy the
## other's. The director's own docstring says as much — `stops_the_world` "is the host's to
## set" — so the slug lives on the host, beside the three sibling gates it reads with.
const STOP_ON_TURN_SLUG := "navigator.stop_on_turn"

## Proof-mode tunable (ADR-0068, default false): give the deployed OWNED team absurd HP so
## a roster-fed auto-battle reliably resolves `winner == 0` regardless of level/job balance
## (the Gariland proof deploys lv1 squires/chemists vs thieves). A deterministic guarantee
## for the end-to-end victory test, not a gameplay feature. Read at deploy time.
const OWNED_INVINCIBLE_SLUG := "navigator.owned_invincible"
const PROOF_HP := 9999

## Event unit id of the PROTAGONIST alias (Ramza) in the scenario VM's `_units_by_id`
## registry. The deployed owned leader (`_deployed_owned[0]`, Ramza —
## `CharacterCatalog.owned_units()` is Ramza-first) is registered under this id at deploy
## time so an event's `{1F}` Focus(0x01) / Unit-Anim(0x01) / Display Message(speaker 0x01)
## opcodes resolve onto him — the FFT-faithful camera focus, replacing the old heuristic
## re-home. This is an ALIAS: the same unit is also registered at
## [constant SQUAD_EVENT_UID_BASE] (index 0), which is how the openers' squad sweeps name him.
##
## `0x01` is never an ENTD slot — the player's units are not in the ENTD at all
## (GAME_STATE_TRANSITIONS.md §2.6), so this cannot collide with a spawned ENTD unit.
const RAMZA_EVENT_UID := 0x01

## Event unit id of the FORMATION SQUAD's first slot. A battle's deployed roster occupies
## `0x78 + <DeploymentPlan index>` (Ramza is index 0, and also answers to
## [constant RAMZA_EVENT_UID]); a histogram over all 480 scenario chunks finds exactly
## `0x78`–`0x7C` alongside `0x01` and the `0x80+` ENTD cast, and no ENTD record holds any
## of them. Openers ADDRESS these ids without ever adding them — Mandalia's scn 16 erases
## `0x01` + `0x78`–`0x7C` at PC 7-13 and draws them back at PC 58-64 — which is the event
## data's own statement that the squad already stands on the field when the opener boots.
##
## ⚠️ UNSETTLED: whether `0x78` is Ramza's slot or the first NON-Ramza slot. Lionel's opener
## (scn 197) draws only `0x79`–`0x7C`, which reads like "Ramza stays visible"; Riovanes
## (`max_squad_size` 2) erases all five, so the erase lists are NOT squad-size-derived.
## Registering `0x78 + index` with Ramza at index 0 satisfies both readings — do not write
## it up as decided without new evidence.
const SQUAD_EVENT_UID_BASE := 0x78

## Story-context STUB for the deploy-seam Form selection (ADR-0079). The active Form is
## chosen per story chapter; while the navigator reaches only Chapter 1 (Gariland) there is
## no live chapter state to read, so the seam selects with this constant. The seam SELECTS
## (`Character.active_special_name`) rather than hardcoding a `special_name`, so a reachable
## Ch2+ replaces this stub with real chapter state and every unique's later Form drops in.
const STORY_CHAPTER_STUB := 1

## Debug tunable (ADR-0068, default false): show the view-only FORMATION overlay between
## the opener and deployment (wayfinder #234 E). OFF by default → the proof plan omits the
## formation_view action entirely (non-gating). Read at plan time.
const SHOW_FORMATION_SLUG := "navigator.show_formation"


var _game_nav: GameNavigator = null

## How this walk's plan was built, replayed for every world-map hop appended to it.
var _mutation_script: MutationScript = null
var _show_formation: bool = false
var _nav_runner: NavigatorRunner = null

## The walk THIS boot planned, kept so `_publish_walk_position` can park a (root, action)
## pair that indexes into that same plan. Resuming from the action's own root instead would
## re-root the plan and renumber every action under it.
var _walk_start_root: int = -1
var _walk_stop_root: int = -1

## A click-to-rewind PC lifted out of [ScenarioDebugSession] at boot and handed to the
## FIRST member this walk plays — the action the walk resumed at. -1 = none pending.
var _pending_rewind_pc: int = -1

## Identity binding for the battle cast (ADR-0201): lifts each ENTD slot's
## (entd_record, unit_id) to a Catalog Character, falling back to ENTD-slot
## construction on a miss. One instance per run so the coverage gap accumulates.
var _binding: SlugBinding = SlugBinding.new()

## The group root whose world is currently booted for the battle interleave (opener
## → combat → victory all share it). -1 = no battle world standing.
var _battle_world_root: int = -1
## The battle root the owned squad currently stands deployed for, or -1. Placement is
## keyed on this rather than on `_battle_world_root` because the two answer different
## questions: the world can be up with nobody deployed on it (a predetermined ENTD cast,
## or a bare-construct unit test). It is what makes `_ensure_owned_deployed` idempotent
## across the boot → pre_battle → combat sequence within one battle, and it is reset by
## `_free_deployed_owned` so a group re-boot re-places.
var _deployed_root: int = -1
## The bare combat loop attached to the live world while the Orbonne battle runs.
var _combat_loop: CombatLoop = null
## The PUMP gate, and since #898 that is all it is. It answers "does this navigator drive
## this loop's clock at all" — `_process` calls `tick()` only while it is true — and it is
## NOT the freeze authority: the loop's own `combat_active` is.
##
## [b]The loop's flag has TWO writers now, and this mirror still has one.[/b] Hands-off
## (the default) the walk mounts the director with [member TurnDirector.stops_the_world]
## false, so it announces and spends turns inside one gate call and never touches
## `combat_active` — the old single-writer world, unchanged. Under
## [constant STOP_ON_TURN_SLUG] the director DOES freeze, and that is the second writer the
## old note here said would need answering. It is answered in three places and they are the
## whole of it:
##
##   1. `_on_director_turn_opened` / `_on_director_resumed` FOLLOW the director's writes
##      into this mirror, in the same call stack, so the two flags still agree on every
##      frame an observer can read them on. That agreement is an asserted invariant
##      (`NavigatorTurnDirectorMountTest` arm (d)) and it holds under BOTH policies.
##   2. `_toggle_tactical_stop` REFUSES while a turn is open — resuming a world the director
##      froze is precisely the hazard, and `GambitBattle._toggle_hold` refuses on the same
##      test — RUNNING only, because during TURN_OPEN the world is already frozen by somebody
##      who is owed a decision. Both hosts now put that refusal behind SPACE (`5406bd8be` on
##      gambit's side); the RULE and the key are shared. The modal pause (Esc) deliberately
##      does NOT refuse there — it saves and restores the flag instead of flipping it.
##   3. `_set_screen_pause` therefore saves and restores a mirror that already reads false
##      through a freeze, so closing the Formation screen cannot resume an open turn.
##
## `_set_combat_live` stays the only place that writes the LOOP's flag from this host.
var _combat_active: bool = false

## The TURN DIRECTOR (ADR-0239), mounted on the bare loop — design S11's check, and it is
## one line because the director is a component of the LOOP and not of a `CombatHost`
## (which this scene deliberately does not extend). Null outside a battle.
var _turn_director: TurnDirector = null
## The turn queue forecast strip (ADR-0244), mounted on the CAMERA rather than on this
## scene — which is why it costs this host one line too, and why it comes across from
## `GambitBattle` without either scene knowing about the other. Freed with the battle.
var _turn_queue_hud: TurnQueueHud = null

## The TURN-OPEN BEAT ([TurnBeat], ADR-0265) — the AT marker, the cue and the camera travel
## that make an open turn READ as one. A component and not an inheritance, because that is
## the only shape available: the feature grew up on `GambitBattle extends CombatHost` and
## this scene extends `ScenarioPlayerScene`.
##
## Built once and kept for the process, not per battle: it latches nothing (it is re-`bind`ed
## at every use) and its only owned node is the marker, which is a child of the UNIT and dies
## with it.
var _beat: TurnBeat = TurnBeat.mount()

## 🔴 WHOSE TURN IS YOURS IS NOT KEPT HERE ANY MORE. It was a `Dictionary` of unit index →
## true, resolved once per battle off `_deployed_owned`; [method is_commandable] reads
## [member Unit.commandable] instead and there is no set at all.
##
## The concept itself is still load-bearing and its ABSENCE — not the missing visuals — is
## what made [constant STOP_ON_TURN_SLUG] read as "a pause button with extra steps": with no
## steerability, every one of the eleven-odd turns in a Gariland round-robin stopped the world
## and asked the player to press Space for a unit the GPU was still driving. A turn that is
## not yours is spent where it opens, inside the freeze the director already took
## (`_on_director_turn_opened`), which is exactly what `GambitBattle` does with an enemy's.
##
## What was WRONG was the derivation. `_deployed_owned` is provenance — how a unit got onto
## this field — and the set difference against it silently answered "nobody" for a cast the
## ENTD bakes in, which is the one predetermined battle in the game (ADR-0265 Amendment 1).
## An ENTD-blue GUEST is still not yours, and is still excluded — by its own slot's control
## flag being false, which is a fact about the guest rather than a rule about guests.

## The one line of chrome that says WHICH stop the world is in ([StopBadge], ADR-0265).
## Deployment, an Esc pause, an open turn and a resolved battle are four motionless
## battlefields that used to be pixel-identical here, ended by three different keys.
##
## Mounted lazily on the first frame a battle exists and kept for the process — it is one
## hidden CanvasLayer between battles, and mounting it per battle would put its lifetime in
## the two teardown paths that already disagree about what they free.
var _stop_badge: StopBadge = null

## The encoded COMBAT gambits for the frozen loop (ADR-0082). A frozen CombatLoop boots with
## IDLE (empty) gambits; `_go_live` arms THESE when Space leaves Deployment — the idle→combat
## swap that makes Deployment and a mid-battle Pause the same flag state in code.
##
## 🔴 RE-ENCODED AT GO-LIVE, not captured at build. It used to be built once in
## `_build_frozen_combat_loop` and armed unchanged, which meant every gambit edit made during
## the Deployment park was thrown away — the player authored a rule on the formation screen,
## pressed Space, and the kernel ran the cast's BOOT list. `_refresh_pending_gambits` re-reads
## the cast at the moment the swap happens, which is the only moment the answer is knowable.
## The build-time value is still honoured when there is no cast to read, because the
## bare-construct rigs (`NavigatorCommandModeTest`) seed this array directly and own no units.
var _pending_gambits: Array = []


## The composed cast, held between the two halves of the battle build (see
## [method _build_battle_machinery]). Composing spawns the ENTD side, so the cast-shaped half
## hands the arrays forward rather than letting the position-shaped half compose a second set.
## Emptied by `_build_frozen_combat_loop` once `boot_battle` has taken them.
var _pending_team0: Array = []
var _pending_team1: Array = []

## The `role` of the beat currently playing ("opener" / "victory" / ""). Read by the prewarm,
## which must fire under the INTRO's dark screen and never under the outro's — the outro holds
## an identical black plate, and building a battle there would stand a CombatLoop up on the far
## side of the one that just ended.
var _beat_role: String = ""

## The world root whose battle machinery the prewarm has already taken care of (-1 = none), and
## the in-flight latch. Both are needed: the build spans frames, so "is the loop up yet" cannot
## answer "have I already started".
var _prewarmed_root: int = -1
var _prewarm_running: bool = false

## Has the cursor been seated on the leader for this battle? The seat belongs to the BUILD
## (ADR-0265 dec. 1 as amended — re-seating on the second entry pans the battlefield back to the
## leader when the player presses Space), and the build can now happen a beat earlier than the
## entry, so "did I build it just now" is no longer the same question as "has it been seated".
## Cleared with the rig in `_end_battle`.
var _command_surface_seated: bool = false

## Has `boot_battle` loaded the cast onto the GPU battle buffer? NOT the same question as
## "does `_combat_loop` exist" any more: the prewarm stands the loop up under the dark screen
## and leaves the position-shaped half behind, so between those two moments there is a live
## `CombatLoop` with no battle in it. Every guard that meant "is the battle built" has to ask
## THIS; a `_combat_loop == null` test would skip the boot entirely on the direct-seek path.
## Cleared with the loop in `_end_battle`.
var _battle_booted: bool = false

## Has the battlefield been frozen since the player's gambits were last armed? The one bit
## [method _rearm_gambits_if_unfroze] consumes — see there for why the re-arm hangs off this
## rather than off each door that un-freezes.
##
## It is a DIRTY bit and not "was live last frame", and the difference is a real hole: a freeze
## that opens and closes inside ONE frame never shows a polled flag anything but `true`, so an
## edge detector on the flag would miss it silently. A bit that only the freeze sets and only the
## re-arm clears cannot miss one however short it was.
var _gambits_dirty: bool = false

## The COMMAND-MODE cursor rig (ADR-0082): a map cursor + camera-follow the player uses to roam the
## frozen field during Deployment (and, once combat is live, a Pause). Built lazily at Deployment
## entry (`_enter_command_cursor`), seeded on the leader (first deployed owned unit) WHEN IT IS BUILT, and freed on
## world teardown. The same cursor rig GPUArena wires, through the published `CursorRig` port, — replicated here.
var _cursor_rig: CursorRig = null
## The Formation screen re-hosted over the live battlefield (ADR-0137), mounted with the cursor rig.
var _formation_map_screen: Node3D = null
## The Formation coordinator, by path — it carries no `class_name`.
const FormationDetailTransitionScript = preload("res://src/ui3/formation/FormationDetailTransition.gd")
const StartActionMenuScript = preload("res://src/ui3/detail/StartActionMenu.gd")

## True while parked at the universal pre-battle config breakpoint (debug pause) — the
## walk has built + presented this battle's config and is waiting for the player to start
## combat (Enter) before it dispatches the combat action.
var _pre_battle_active: bool = false

## BATTLE MODE (ADR-0177 Amendment 3, `docs/context/41-battle-mode-and-handback.md`): true
## between [method _enter_battle_mode] and the [method _end_battle] handback.
##
## It is a `Focus` state and THREE CLAIMS THAT ARE NOT INPUT — the cursor rig's existence,
## [member PlayerCamera.camera_mode], and every combat body's `clock_owner`. `Focus` gates
## DELIVERY and nothing else, so it cannot free a rig, return a camera or flip a clock; those
## ride the same push/pop edge and stay three named operations. Conflating "who gets keys"
## with "who owns the clock" is how the four Orbonne bugs happened, and folding them into the
## focus primitive would repeat it one level up.
##
## ⚠️ ENTERED AT THE FIRST CLAIM, NOT AT `_go_live`. The ADR's sentence is "`_go_live` pushes
## `battle`", which is true of a host where the three claims are taken together; on this one
## the cursor and the camera are claimed at DEPLOYMENT (`_enter_command_cursor`) and only the
## clock at `_go_live`. Entering at the later edge would leave Deployment holding two claims
## from outside the mode they belong to — and Deployment is a phase INSIDE battle mode, which
## is the ADR's own reason for pushing "deployment" on top of "battle" rather than instead of it.
var _battle_mode: bool = false

## What [member PlayerCamera.camera_mode] was before battle mode forced it to CURSOR, so the
## handback can give it back. -1 means nothing is claimed.
var _camera_mode_before_battle: int = -1

## The owned player Units deployed onto the zone this pre-battle (wayfinder #234 A/D) —
## spawned from `CharacterCatalog.owned_units()` and snapped onto the deployment tiles in
## `run_pre_battle`; folded onto team0 by `run_combat`'s `build_battle`. Empty for a
## predetermined battle (Orbonne) — its cast is entirely in the ENTD.
var _deployed_owned: Array = []

## The winner of the last resolved combat (0 = player), for the end-to-end proof to read.
## -1 until the first combat resolves.
var _last_combat_winner: int = -1

## True when the current battle's outcome is scripted (predetermined cast, e.g. Orbonne —
## the story advances regardless of the tactical result). A roster-fed battle (Gariland)
## routes its real winner. Set when the battle is built.
var _battle_scripted_outcome: bool = false


## Give back anything `warm_pipelines_async` parked and no battle ever claimed: a live
## local RenderingDevice at process shutdown is an exit-134 abort, not a leak warning
## (#471). A no-op once a battle claimed it — then `GPUBatchSimulator.cleanup()` owns it.
func _exit_tree() -> void:
	GPUBatchSimulator.release_prewarm()


func _ready() -> void:
	# The battle this walk is aimed at is seconds away at best and a world-map hop away at
	# worst, and its boot is where the driver's compute-pipeline compile lands — ~5.5 s of
	# frozen brown screen on a cold cache. Start it now, on a thread, so the gap between
	# here and `run_pre_battle` is what pays for it. No-op after the first call, so a
	# `Seek here` scene reload does not restart it.
	GPUBatchSimulator.warm_pipelines_async()
	# AND THE DEVICE ITSELF, here on the main thread — it is thread-affine, so it cannot
	# ride the warm-up above (#1168). ~180 ms, blocking, deliberately: this is a scene
	# boot with nothing on screen, and the alternative is paying it on the frame the
	# battle intro's dark screen is retracting over. See `GPUBatchSimulator.prewarm_device`.
	GPUBatchSimulator.prewarm_device()
	# X1: this walk IS the campaign, so every scenario it plays runs against Campaign's
	# one variable store (ADR-0179). Without this the story counter a scenario writes
	# evaporates at the next `start()` and the world-map loop can never advance past hop
	# one — which is precisely what it did.
	campaign_store = Campaign.vars()
	# A pending `path_target_scenario_id` means someone asked for plain SCENARIO-PLAYER
	# playback: boot that target's group root and walk the planned member route onto it
	# (parent `_ready`), rather than silently dropping the request and booting the default
	# story walk — the "picked root 3 / scn 6 but got the group-1 chapel" bug.
	#
	# The "Scenario" path panel used to be the producer; it is no longer registered on this
	# scene (see `_register_scenario_path_panel` below). The ONE remaining producer is
	# ScenarioVMDebugPanel's rewind-through-root — when you rewind to a PC inside a nested
	# group member it replays from the group root, and that is a scenario-player walk. It
	# stays: rewinding a chunk is inspection, and it is the tool you reach for while
	# debugging event instructions.
	#
	# A navigator seek, when present, still wins. (`path_target` is only >0 immediately
	# after a rewind click, which reloads at once; the parent consumes it, so it can't
	# linger into a later boot.)
	if ScenarioDebugSession.navigator_start_root <= 0 \
			and ScenarioDebugSession.path_target_scenario_id > 0:
		super._ready()
		return

	# Navigator-driven boot — do NOT call the parent `_ready` (that single-boots one
	# scenario). Plan the walk, then let the runner drive the executor (methods below).
	# A SEEK request (NavigatorDebugPanel, survives the scene reload via
	# ScenarioDebugSession) overrides the default 1→7 run + the from-the-top start.
	_game_nav = GameNavigator.new()
	var start_root := START_ROOT
	var stop_root := STOP_ROOT
	var start_action := 0
	# "PLAY BATTLE N" (ADR-0264) — `--battle=N` launches this walk INTO one battle
	# group instead of booting a second combat host. It supplies only the DEFAULT root, and
	# is therefore consulted first and overridden by both branches below: an interactive
	# seek and a rewind-resume each describe where you already are, while this describes
	# what the process was launched for. The ENTRY ACTION is resolved after planning, below,
	# because it is a property of the plan and not of the request.
	var battle_root := DebugConfig.battle_seek_root
	var watch_opener := DebugConfig.battle_watch_opener
	var resolve_battle_entry := battle_root > 0
	if battle_root > 0:
		start_root = battle_root
		stop_root = battle_root
	if ScenarioDebugSession.navigator_start_root > 0:
		start_root = ScenarioDebugSession.navigator_start_root
		stop_root = ScenarioDebugSession.navigator_stop_root  # <=0 → natural end of the successor chain
		start_action = maxi(ScenarioDebugSession.navigator_start_action, 0)
		# An explicit seek re-roots the walk; it is no longer the launched battle, so the
		# plan goes back to the ordinary chaining planner and the index is the panel's.
		battle_root = -1
		resolve_battle_entry = false
	elif ScenarioDebugSession.rewind_target_pc >= 0 \
			and ScenarioDebugSession.navigator_resume_root > 0:
		# A click-to-rewind staged from the F3 VM panel while THIS walk was on screen. The
		# panel issues no seek, and the seek that got us here was consumed on the previous
		# boot — so without this the walk replans from START_ROOT and the reload lands in
		# the Chapel of Orbonne no matter which group you were rewinding inside. That was
		# the reported "seek root 28, rewind to PC 32, arrive at Orbonne" defect. Resume
		# where the walk was, and carry the PC to the member replayed there.
		start_root = ScenarioDebugSession.navigator_resume_root
		stop_root = ScenarioDebugSession.navigator_resume_stop_root
		start_action = maxi(ScenarioDebugSession.navigator_resume_action, 0)
		_pending_rewind_pc = ScenarioDebugSession.rewind_target_pc
		ScenarioDebugSession.rewind_target_pc = -1
		print("[NavigatorMain] rewind → resuming the walk at root %d, action %d, pc %d"
			% [start_root, start_action, _pending_rewind_pc])
		# A rewind inside the launched battle must replan THE SAME plan: the resumed action
		# index is an index into the one-group plan, and the chaining planner numbers its
		# actions differently. Carry the launch when the walk is still in that group; drop
		# it when the rewind resumed somewhere else.
		resolve_battle_entry = false
		if start_root != battle_root:
			battle_root = -1
	# Consume the request so a later Ctrl+R replays the SAME seek rather than resetting.
	ScenarioDebugSession.navigator_start_root = -1
	ScenarioDebugSession.navigator_stop_root = -1
	ScenarioDebugSession.navigator_start_action = -1
	# Park where this walk begins BEFORE the runner dispatches — a rewind clicked mid-walk
	# resumes from this pair, and `_publish_walk_position` keeps it current as it moves.
	_walk_start_root = start_root
	_walk_stop_root = stop_root
	ScenarioDebugSession.navigator_resume_root = start_root
	ScenarioDebugSession.navigator_resume_stop_root = stop_root
	ScenarioDebugSession.navigator_resume_action = start_action

	# X2: a SEEK re-roots the plan; it must re-root the WORLD STATE too. `var[110]` (the
	# story counter) is written only by the scenarios' own `Zero(110); Add(110,k)` as they
	# play, so a seeked walk arrived at story counter 1 no matter where it was aimed. Its
	# first `world_map` action then asked Campaign what was live, got node 6 -> Beoulve
	# Residence, and (with auto-advance on) chained forward hop by hop through the entire
	# game. Installing the target group's own `enter` conditions is what makes the map
	# offer the right node. See [RosterTimeline].
	_install_world_state(start_root)

	# The plan carries the DERIVED mutation script (ADR-0216): each action's `mutations`
	# are the Catalog deltas the runner folds as the walk moves, built from the ROM's own
	# ENTD `join_after_event` flags rather than a hand-authored table. Every group grants
	# its recruits at its END, so a walk reaching group 9 arrives with the roster the ROM
	# says it should have (Ramza + the six Academy cadets owned; Delita catalogued as the
	# ENTD-blue guest the scene spawns itself).
	var script := StoryMutationScript.build()
	# Remembered so a world-map hop's appended sub-plan is built the same way as the
	# walk it is joining — same catalogue mutations, same formation gate.
	_mutation_script = script
	# The formation view (E) is debug-gated OFF; when set, it weaves a view-only overlay
	# node into each battle group's expansion (never on the default proof path).
	var show_formation := bool(Tune.bind(SHOW_FORMATION_SLUG, false, {}, Tune.Persist.AUTOSAVE))
	_show_formation = show_formation
	# A launched battle plans that ONE group (opener → pre_battle → combat → victory) and
	# stops; `plan_actions(root, root)` would chain onward past it (see `plan_battle_group`).
	var actions: Array = _game_nav.plan_battle_group(battle_root, script, show_formation) \
		if battle_root > 0 \
		else _game_nav.plan_actions(start_root, stop_root, script, show_formation)
	if resolve_battle_entry:
		start_action = GameNavigator.battle_entry_index(actions, watch_opener)
		if start_action < 0:
			push_error(("[NavigatorMain] --battle=%d: the plan carries no entry action "
				+ "(%d action(s)) — starting at the top of it instead") % [battle_root, actions.size()])
			start_action = 0
		print("[NavigatorMain] --battle=%d → seeking action %d (%s)" %
			[battle_root, start_action, "opener, played" if watch_opener else "pre_battle"])
		# The walk STARTS here, so this is where a click-to-rewind must resume it.
		ScenarioDebugSession.navigator_resume_action = start_action
	# A SEEK can re-root the walk past the story start. The re-rooted plan omits the
	# earlier groups' actions — and with them every recruit granted there, plus every
	# named unit their battles bound — so the seeked battle would arrive with an empty
	# cast. The derived timeline states that history directly, so the PROLOGUE is one
	# synthetic action carrying the fold of every group ahead of this one. It is defined
	# for ALL 155 roots, not only the ones a replan from the story root could chain to
	# (ADR-0216).
	var prologue: Array = []
	var seed := StoryMutationScript.prologue_deltas_before(start_root)
	if not seed.is_empty():
		prologue = [{"kind": "prologue", "mutations": seed}]
	print("[NavigatorMain] planned %d actions for walk %d → %d (seek @action %d, %d prologue action(s))" %
		[actions.size(), start_root, stop_root, start_action, prologue.size()])
	for a in actions:
		print("  - %s" % _action_line(a))

	# Inject the live Catalog: begin_at(N) resets it to new-game and silently folds the
	# skipped beats' deltas before dispatching N, so a seek arrives with the scripted
	# cast; the live walk folds each beat's delta as it is reached (ADR-0201).
	_nav_runner = NavigatorRunner.new(actions, self, CharacterCatalog, prologue)
	_nav_runner.state_changed.connect(_on_runner_state_changed)
	_nav_runner.walk_finished.connect(_on_runner_walk_finished)
	_nav_runner.defeated.connect(_on_runner_defeated)
	_nav_runner.begin_at(start_action)


## One plan action as ONE readable line. A derived delta carries the unit's whole ENTD
## slot (~40 fields), so `str(action)` prints thirty kilobytes for the Academy alone and
## buries the plan it is meant to show. The slot is data the STORY panel renders on
## demand; what the boot log is for is the SHAPE of the walk, so summarise the mutations
## as `op:slug` and keep the line scannable.
func _action_line(action: Dictionary) -> String:
	var kind := String(action.get("kind", "?"))
	var where := ""
	if action.has("root"):
		where = "root %d" % int(action.get("root", -1))
	elif action.has("beat"):
		where = "scn %d" % int(action.get("beat", {}).get("scenario_id", -1))
	var muts: Array[String] = []
	for m in (action.get("mutations", []) as Array):
		muts.append("%s:%s%s" % [String(m.get("op", "?")), String(m.get("slug", "?")),
			"*" if bool(m.get("own", false)) else ""])
	var tail := "" if muts.is_empty() else "  [%s]" % ", ".join(muts)
	var terminal := "  TERMINAL" if bool(action.get("terminal", false)) else ""
	return "%-10s %-9s%s%s" % [kind, where, terminal, tail]


## Re-root the world-map state for a seeked walk: reset exactly the variables the `enter`
## scripts gate on, then install the target group's own conditions (ADR-0179 -- Campaign
## owns the one store). A no-op for a walk starting at the story root.
##
## The reset is that gating set and NOT the whole store: var 528 sits inside
## [constant WorldMapProgress.NODE_KNOWN_BASE], so zeroing everything would un-reveal
## unrelated map nodes.
##
## Warns rather than refuses when nothing at or before the group is entered from the
## world map, or when the anchor's variables do not isolate it -- a Seek there is still
## useful, it just cannot promise the map is unambiguous.
func _install_world_state(start_root: int) -> void:
	if start_root == START_ROOT:
		return
	var store := Campaign.vars()
	if store == null:
		push_warning("[NavigatorMain] no variable store — world state not re-rooted for seek %d" % start_root)
		return
	var anchor := _enter_anchor(start_root)
	if anchor <= 0:
		push_warning(("[NavigatorMain] seek root %d: neither it nor any group before it is "
			+ "entered from the world map — story counter left at %d, so a world-map hop will "
			+ "offer whatever that state makes live") % [start_root, Campaign.story_counter()])
		return
	for idx in RosterTimeline.gating_vars():
		store.set_var(int(idx), 0)
	var wanted := RosterTimeline.enter_vars(anchor)
	for idx in wanted:
		store.set_var(int(idx), int(wanted[idx]))
	# A seek re-roots the plan and the variables; it must re-root the MARKER too, because
	# nothing else will. `WorldMapProgress`'s party node is written ONLY by the map's own
	# arrival path (`WorldMapScene._advance_travel`), so a walk that never travelled left it
	# on `new_campaign()`'s seed -- node 7, Gariland. That one stale value is BOTH reported
	# symptoms: the map drew Ramza in the wrong town, and it ran its opening reveal pass at
	# that node (`_start_reveal_pass(progress.party_node())`, ADR-0230 dec. 8), where nothing
	# is owed -- so the reveals the walk had just earned stayed hidden until the player
	# walked back to the right node by hand and tripped the arrival hook instead.
	#
	# ADR-0230's Prediction 1 assumes exactly what this line installs: "the four scripts
	# that would light [Sweegy Woods] sit on Igros, WHICH IS WHERE THE MARKER IS STANDING."
	# Nothing made that true on the seek path.
	var live := Campaign.live_enter_nodes()
	if live.size() == 1 and Campaign.progress != null:
		# The screen counts places from 1 and the store counts nodes from 0 --
		# `Campaign.place_to_index` is the inverse of this `+ 1`.
		Campaign.progress.set_party_node(int(live[0]) + 1)
	if not RosterTimeline.enter_is_exclusive(anchor):
		push_warning(("[NavigatorMain] seek root %d (enter anchor %d): its enter conditions "
			+ "do not isolate it (unmodelled `party has job`, or a genuine tie) — the map may "
			+ "offer nothing or more than one node, so the marker is left where it was")
			% [start_root, anchor])
	print(("[NavigatorMain] world state re-rooted for seek %d (enter anchor %d): "
		+ "story_counter=%d live_enter_nodes=%s party_node=%d") %
		[start_root, anchor, Campaign.story_counter(), str(Campaign.live_enter_nodes()),
			Campaign.progress.party_node() if Campaign.progress != null else -1])


## The group whose `enter` state says where the party is STANDING for a seek to
## [param start_root]: the target itself when the world map offers it, else the nearest
## group BEFORE it in story order that the map does offer. `-1` when nothing at or before
## it is ever entered from the map.
##
## The fallback is what a chain-reached group needs. Root 28 (Citadel of Igros Castle) has
## no `enter` of its own -- it chains off root 26, the Office of Igros Castle, which the
## map offers at node 2. A player who arrived there walked to Igros and then chained
## inward without touching the map again, so Igros is where they are standing, and it is
## the node whose script list owes the reveals the group earns.
static func _enter_anchor(start_root: int) -> int:
	if RosterTimeline.has_enter(start_root):
		return start_root
	var pos := RosterTimeline.position(start_root)
	if pos < 0:
		return -1
	var order := RosterTimeline.order()
	for i in range(mini(pos, order.size()) - 1, -1, -1):
		if RosterTimeline.has_enter(int(order[i])):
			return int(order[i])
	return -1


## The SCENARIO-PLAYER navigation launcher, SUPPRESSED here.
##
## The parent registers [ScenarioPathDebugPanel] — "pick a root -> pick a scenario ->
## Walk here" — at the head of the "Scenario" masonry cell. That is the launcher for the
## scenario player, which boots ONE group's world and walks a member route onto it. This
## scene is the story WALK: it chains group -> group over one persistent world and has its
## own launcher, [NavigatorDebugPanel], in that same cell. Two rival "pick a scene"
## pickers side by side, and driving the wrong one silently drops you out of the walk into
## plain scenario playback (the `_ready` fall-through below) — which is the one way this
## scene is never meant to be navigated.
##
## The parent's INSPECTION panels all stay: VM disassembly + stepping, dialogue-box
## placement, view gizmos, weather, the cinematic pose scrub, unit shader/alignment. Those
## read whatever is currently playing and are exactly what you want while debugging event
## instructions. It is only the navigation surface that is scenario-player-exclusive.
func _register_scenario_path_panel() -> void:
	pass


## Register the parent's scenario panels, then add the navigator SEEK panel
## ([NavigatorDebugPanel]). Find-or-create: DebugOverlay holds panels across a
## `reload_current_scene`, so a reload rebinds the same panel instead of stacking.
func _register_debug_panels() -> void:
	super._register_debug_panels()
	# Each of these four carries a catalogue id, so the F3 Catalogue page governs them the
	# same way it governs the parent's — the switch is refused at the seam
	# (`DebugOverlay.register_panel`) rather than by a check written into each branch.
	# Each panel is guarded independently so a scene reload re-registers the missing ones
	# (and rebinds the navigator-coupled ones) rather than an early-return skipping some.
	if _find_panel(DebugOverlay.Category.SCENARIO, "NavigatorDebugPanel") == null:
		var nav_panel := NavigatorDebugPanel.new()
		nav_panel.setup()
		DebugOverlay.register_panel(nav_panel, DebugOverlay.Category.SCENARIO, "navigator")

	# ROSTER (ADR-0201): the persistent "universe" catalogue + the current battle's binding.
	if _find_panel(DebugOverlay.Category.ROSTER, "RosterUniverseDebugPanel") == null:
		var uni := RosterUniverseDebugPanel.new()
		uni.setup()
		DebugOverlay.register_panel(uni, DebugOverlay.Category.ROSTER, "roster_universe")

	# STORY (ADR-0216): the DERIVED timeline both the Seek state and the roster come from.
	# Read-only, and its own cell rather than ROSTER's: it answers about the ROM's story
	# spine, not about the live catalogue ROSTER's two panels render.
	if _find_panel(DebugOverlay.Category.STORY, "StoryTimelineDebugPanel") == null:
		var story := StoryTimelineDebugPanel.new()
		story.setup()
		DebugOverlay.register_panel(story, DebugOverlay.Category.STORY, "story_timeline")

	# The binding panel reads the LIVE navigator; rebind it to `self` if it survived a reload.
	var bind_panel = _find_panel(DebugOverlay.Category.ROSTER, "BattleBindingDebugPanel")
	if bind_panel == null:
		var bp := BattleBindingDebugPanel.new()
		bp.setup(self)
		DebugOverlay.register_panel(bp, DebugOverlay.Category.ROSTER, "battle_binding")
	elif bind_panel.has_method("rebind"):
		bind_panel.rebind(self)


## The registered panel of the named class in `category`, or null. Matches by script
## resource name so it works for panels registered by a prior scene instance.
func _find_panel(category: int, class_ident: String):
	for panel in DebugOverlay._panels.get(category, []):
		if is_instance_valid(panel) and panel.get_script() != null \
				and panel.get_script().get_global_name() == class_ident:
			return panel
	return null


func _process(delta: float) -> void:
	# The event VM self-ticks (its own _process); here we only pump the bare combat
	# loop while a battle is live (the CombatHost pump, mirrored — CombatLoop has no
	# _process of its own). The deployed squad's march-idle at the pre-battle pause
	# rides the VM's ONE 60 Hz tick via `ScenarioVM.idle_only_units` (registered in
	# `_deploy_owned_units`, ADR-0065) — no second clock here.
	# The turn-open travel and the badge, ABOVE the live gate and deliberately: both have to
	# advance through the director's FREEZE, which is the only time either has anything to do.
	_beat.advance()
	_refresh_stop_badge()
	# ABOVE the live gate for the same reason the two lines above it are: the edge it watches for
	# is the frame the battlefield STARTS running, and on that frame `_combat_active` is still the
	# old value on some of the paths that set it (the director writes the loop's flag itself and
	# this host mirrors it a call later).
	_rearm_gambits_if_unfroze()
	# Called, never awaited: it is a coroutine that spans the frames it spends building, and the
	# whole point is that those frames keep rendering underneath it.
	_prewarm_battle_under_the_dark()
	if _combat_active and _combat_loop != null:
		_combat_loop.tick(delta)


## PAY THE BATTLE BUILD WHILE THE SCREEN IS BLACK.
##
## The story→battle handoff used to spend ~100 ms of one-frame blocking work on the six frames
## between the dark screen finishing its retract and the camera starting its glide:
## `setup_gpu_simulator` ~45 ms and `_mount_formation_map_screen` ~56 ms, measured with
## `tools/probe_ready_freeze.gd` (three runs, idle box). That placement was chosen deliberately
## and its stated reason was that a frozen frame on a STATIC image is invisible.
##
## 🔴 THE IMAGE IS NOT STATIC THERE, which is what re-opened this. The deployed squad is
## SCENARIO-owned and idle-breathing at 60 sprite-frames/s for the whole window — ten sprites,
## every one of them advancing on every rendered frame. `tools/probe_handoff_seq.gd` records what
## ADVANCED per frame, and across the two hitches it reads: hold for 44 ms then advance 2 sprite
## frames in the next 3.8 ms; hold for 61 ms then advance 4 in the next 15.9. A hold-and-snap on
## every sprite on screen at once, twice, on the frame the field is revealed. That is a stutter in
## a moving image, not an invisible freeze on a still one.
##
## So the work moves to where there genuinely is nothing to look at. The intro holds a fully
## established `{76}` dim for SECONDS while `{78}` paints the victory conditions over it (Gariland:
## ~6.5 s across two banners, against ~100 ms of build), and `ScenarioVM.screen_is_fully_dark()` is
## that cover as a predicate. Both builds are shaped by the CAST and the MAP and by nothing else —
## see `_build_battle_machinery` for why `boot_battle`, the one step that reads where units stand,
## deliberately stays behind at the normal time.
##
## Gated to the OPENER beat. The outro holds an identical black plate over the results screen, and
## a prewarm there would stand a fresh CombatLoop up on the far side of the battle that just ended.
func _prewarm_battle_under_the_dark() -> void:
	if _prewarm_running or _beat_role != "opener" or _battle_world_root < 0:
		return
	if _prewarmed_root == _battle_world_root:
		return
	if _combat_loop != null and is_instance_valid(_combat_loop):
		return
	if _vm == null or not is_instance_valid(_vm) or not _vm.has_method("screen_is_fully_dark"):
		return
	if not _vm.screen_is_fully_dark():
		return
	# Latched BEFORE the first await: `_process` runs again while this is in flight.
	_prewarm_running = true
	_prewarmed_root = _battle_world_root
	var root := _battle_world_root
	var t0 := Time.get_ticks_usec()
	var built := await _build_battle_machinery(root, true)
	if built:
		await _build_command_surface()
	_prewarm_running = false
	print("[NavigatorMain] battle build PREWARMED under the dark screen (root %d, %s, %.0f ms of cover spent)"
		% [root, "machinery + cursor surface" if built else "nothing — cast not ready",
		(Time.get_ticks_usec() - t0) / 1000.0])


# === Executor contract (NavigatorRunner drives these) ========================

## Play a whole SCENARIO group's members, yielding on the terminal member's Event End.
## The terminal STOP group (group 7) is ENTERED (world booted) and then halts without
## playing its members (T5: "enter group 7 and stop").
func play_scenario(root: int, beats: Array, terminal: bool) -> void:
	print("[NavigatorMain] play_scenario root=%d terminal=%s (%d beats)" %
		[root, terminal, beats.size()])
	_publish_walk_position()
	await _boot_world_for(root)
	if terminal:
		# Enter-and-stop: the Military Academy world is up; the walk ends here.
		_nav_runner.on_scenario_finished()
		return
	await _play_group_members(root, beats)
	_nav_runner.on_scenario_finished()


## Play ONE woven cinematic beat (opener scn 4 / victory scn 6) on the battle world.
## Boots the battle group's world on the first beat; reuses it (same units) after.
func play_beat(beat: Dictionary) -> void:
	var sid := int(beat.get("scenario_id", -1))
	var root := ScenarioGroupDatabase.root_for_scenario(sid)
	print("[NavigatorMain] play_beat scenario=%d (group root %d, role %s)" %
		[sid, root, str(beat.get("role", "?"))])
	_publish_walk_position()
	if _battle_world_root != root:
		await _boot_world_for(root)
		_battle_world_root = root
		# THE SQUAD IS ON THE FIELD BEFORE THE FIRST OPCODE. An opener does not ADD the
		# player's units — 28 of 72 battle groups' openers ERASE and DRAW them (Mandalia's
		# scn 16 sweeps `0x01` + `0x78`-`0x7C` at PC 7-13, redraws them at PC 58-64, then
		# Focuses `0x01`), which is the event data stating that they already stand there.
		# Placement used to live one action later, inside `run_pre_battle`, so those sweeps
		# addressed nothing and the Focus fell through to the authored `{19}` pose it exists
		# to overwrite — the camera panning to empty terrain with Ramza's dialogue on it.
		# See [method _ensure_owned_deployed]; it no-ops for a predetermined ENTD cast.
		await _ensure_owned_deployed(root)
	# Load the woven member onto the SAME live world and play it to its Event End.
	# fresh=false: keep the persistent overlays a prior member/opener armed.
	if not _play_member(sid):
		push_error("[NavigatorMain] failed to load beat scenario %d" % sid)
		_nav_runner.on_beat_finished()
		return
	# Combat->scenario POSE CARRY: the victory beat re-enters scenario space on the
	# SAME live combat units (decision #180), so preserve each unit's combat-committed
	# pose across `start()` instead of standing everyone up — KO'd units stay DOWN
	# (the {43} fade then sweeps the corpse), survivors hold their end-of-combat pose
	# until scn6's own opcodes re-pose them. Only the post-combat victory beat carries
	# poses; the opener (pre-combat) resets to idle like any fresh member.
	# Held for the prewarm, which must fire under the INTRO's dark screen and not the outro's.
	_beat_role = String(beat.get("role", ""))
	var preserve_combat_poses := _beat_role == "victory"
	_vm.start(false, preserve_combat_poses)
	# A rewind resumed the walk ONTO this beat — fast-forward it to the clicked PC.
	var beat_rewind_pc := _take_pending_rewind_pc()
	if beat_rewind_pc >= 0:
		_vm.set_rewind_target(beat_rewind_pc)
	await _vm.group_finished
	_nav_runner.on_beat_finished()


## Show the FORMATION view as a view-only overlay (wayfinder #234 E), bound to the owned
## roster. Debug-gated: the `formation_view` action is only in the plan when
## `navigator.show_formation` is set, so this runs on demand and NEVER on the proof path.
## Non-gating: instance the scene as a child overlay over the (paused) battle world, inject
## `CharacterCatalog.owned_units()` (Delita, an ENTD guest, is correctly absent), and yield
## until the player dismisses it — then free and proceed to deployment.
## The VIEW-ONLY checkpoint's scene — the bare [FormationScene], no coordinator.
##
## [b]Split from the player's screen by ADR-0181, because two callers had two intents under one
## name.[/b] This one is a debug-gated pause on the walk that yields on `dismissed` and proceeds
## to deployment; it mounts over the LIVE (paused) battle world. The world map's row opens the
## real, editable screen over a torn-down world ([constant FORMATION_SCREEN_PATH]). Keeping them
## on one constant would have handed this checkpoint Change-Job and Equip it never asked for, and
## put a full-screen NDC overlay quad inside a World3D that still holds a battlefield — ADR-0162's
## hazard exactly.
const FORMATION_VIEW_PATH := "res://assets/scenes/Formation.tscn"

## The PLAYER's Formation screen — the ADR-0084 coordinator, which owns ○ (Status/detail),
## △ (the main menu) and every sub-screen behind them. ADR-0181.
const FORMATION_SCREEN_PATH := "res://assets/scenes/FormationDetailTransition.tscn"

func run_formation_view(root: int) -> void:
	if not is_inside_tree():
		_nav_runner.on_formation_view_finished()
		return
	var scene: PackedScene = load(FORMATION_VIEW_PATH)
	if scene == null:
		push_error("[NavigatorMain] formation view: cannot load %s" % FORMATION_VIEW_PATH)
		_nav_runner.on_formation_view_finished()
		return
	var view = scene.instantiate()
	add_child(view)
	await get_tree().process_frame  # let _ready build the grid before we inject
	if view.has_method("set_owned_characters"):
		view.set_owned_characters(CharacterCatalog.owned_units())
	# The formation screen's F3 panels are mounted from the HOST side (#1267) — the scene is
	# moving into `addons/exmateria_ui/` and a member cannot name `src/debug/` classes.
	FormationDebugPanels.register_formation_panels(view)
	print("[NavigatorMain] FORMATION VIEW root %d — %d owned unit(s) (press Enter/Backspace to continue)" %
		[root, CharacterCatalog.owned_units().size()])
	if view.has_signal("dismissed"):
		await view.dismissed
	view.queue_free()
	_nav_runner.on_formation_view_finished()


## Mount the WORLD MAP screen (port-list crossing C2) — the overworld a group's
## `world-map` successor lands on. `GameState.State.WORLD_MAP` has been in the spine enum all
## along with nothing implementing it; this is the implementation.
##
## [b]A CanvasLayer, not a SubViewport.[/b] ADR-0137's Formation precedent mounts a screen
## as a CAMERA CHILD because it re-hosts over the live battlefield and
## `[[map-camera-is-ortho-ui-mounts-as-camera-child]]` records that a SubViewport map
## silently kills the compositor fold. The world map is the simpler case the port list
## calls it (§3, U2): a full-screen 256x240 2D surface with its own vignette and no
## battlefield underneath, so it needs no camera of its own — but it must still not be a
## SubViewport, and a CanvasLayer is the mount that is neither.
##
## The screen sizes itself to the viewport; it only resizes the WINDOW when it is run
## standalone as the current scene (the capture rig).
const WORLD_MAP_SCENE_PATH := "res://assets/scenes/WorldMap.tscn"

## Seconds of BLACK between the battlefield going down and the world map coming up.
##
## [b]This is a hold, not a fade — most of the time.[/b] A group whose successor is
## `world-map` normally ends on its own scene-out: scenario 12's tail runs
## [code]{3E} Color Screen Mode 2, (0,0,0)->(255,255,255), Time 60[/code], which has
## already driven the framebuffer to black by the time this runs. So on the measured path
## this tween is invisible, and what it buys is the black itself, standing in for the disc
## load the console really has there (WLDCORE + `WORLD.BIN` + `WLDTEX` + `MUSIC_27`,
## seconds of it, not 0.45).
##
## [b]`_fade_rect` ending opaque is what makes the teardown below legal (ADR-0162).[/b]
## [method run_world_map] tears the battlefield down the moment this returns, and the
## `{3E}` quad that was blacking the screen goes with it — so the rect must already be
## holding the black itself, not inheriting it. That is why this awaits its tween instead
## of firing and forgetting, and why it stays even where it shows nothing.
##
## It is also still a genuine fade for a group whose last beat does NOT fade itself out,
## and `_boot_world_for`'s load-under-black depends on the same opaque end state.
##
## [b]The world map's own ramp is no longer here.[/b] It moved to [WorldMapScreenIn], on
## the map's own vsync clock, because §24.1 measured the fade as WLDCORE's own BSS — the
## map fades ITSELF in. ADR-0161.
const WORLD_MAP_MOUNT_BLACK_SECONDS := 0.45

## True when [param slug] is set, or when the `navigator.autoplay` profile is. Both are
## register-read here, so both appear in the F3 panel whichever one you use.
func _autoplay_gate(slug: String) -> bool:
	var own := bool(Tune.bind(slug, false, {}, Tune.Persist.AUTOSAVE))
	var profile := bool(Tune.bind(AUTOPLAY_SLUG, false, {}, Tune.Persist.AUTOSAVE))
	return own or profile


## True when the walk's battle should STOP on every turn ([constant STOP_ON_TURN_SLUG]).
##
## Deliberately NOT `_autoplay_gate`: this gate is not in the autoplay profile and must not
## be read through it in either direction. The reasoning is on [constant AUTOPLAY_SLUG] —
## the short of it is that the profile only ever turns gates ON, and autoplay is a state a
## human works in, so a profile term would make this control silently dead in the very
## session that wanted it. The slug alone decides.
##
## A function rather than a bare `Tune.bind` at the one call site, because the tests assert
## the DECISION on this host (`NavigatorTurnStopTest` arm (f)) and `_mount_turn_director`
## is what proves the host consults it.
##
## `--stop-on-turn` is the LAUNCH REQUEST beside the stored preference, exactly as
## `--battle=` sits beside the seek panel. It is not a second source of truth: the slug is
## still the decision this host consults, and the flag is a way to arrive with it made —
## necessary because the toggle is AUTOSAVE, so arming it from a script means committing a
## value into the tracked `config/tune_overrides.json` (ADR-0265, and see `8651171df` for
## what a stray value in that file costs).
func stop_on_turn_armed() -> bool:
	if DebugConfig.battle_stop_on_turn:
		return true
	return bool(Tune.bind(STOP_ON_TURN_SLUG, false, {}, Tune.Persist.AUTOSAVE))


func run_world_map(root: int) -> void:
	if not is_inside_tree():
		_nav_runner.on_world_map_finished()
		return
	var scene: PackedScene = load(WORLD_MAP_SCENE_PATH)
	if scene == null:
		push_error("[NavigatorMain] world map: cannot load %s" % WORLD_MAP_SCENE_PATH)
		_nav_runner.on_world_map_finished()
		return
	var layer := CanvasLayer.new()
	layer.layer = 100
	var view = scene.instantiate()
	# Crossing C3 is a Query from the map INTO Campaign: the screen is HANDED the
	# progression, it does not construct it. There is no campaign-wide store to hand it
	# yet (no autoload is claimed — that is #416's call), so the saved campaign is loaded
	# here, at the mount, where a Campaign store will slot in without touching the screen.
	if view.has_method("set_progress"):
		view.set_progress(Campaign.progress)
	# Which places answer to Campaign rather than to the map's own town page. §29.3's
	# precedence: the event table is asked FIRST, and a town with a live hand-off hands
	# off. Gariland is exactly that, which is why this cannot be left to the map.
	if view.has_method("set_hand_off_places"):
		var places: Array[int] = []
		for index in Campaign.live_enter_nodes():
			places.append(index + 1)
		view.set_hand_off_places(places)
	# The map REPORTS a START-menu row and this decides what to do with it (ADR-0117
	# dec. 8, and WORLD_MAP_SCREEN.md §33.10 point 2: the five non-Move rows "hand off to
	# screens that are not the map's business"). Today that means Formation, window 7,
	# whose console handler `FUN_80113748` is the same formation mainloop
	# `FORMATION_SCREEN.md` already ports. The rest are named and left.
	if view.has_signal("menu_row_chosen"):
		view.menu_row_chosen.connect(
			func(_row: int, window: int) -> void: _on_world_map_menu_row(view, window))
	# X1 — the hand-off. The map REPORTS the node and Campaign decides what it means
	# (ADR-0117 dec. 8, WORLD_MAP_SCREEN.md §32.9 point 1). `node_entered` fires for
	# battlefield nodes from both arms — ○ on the node you stand on, and ARRIVAL after a
	# walk, which needs no second press (§32.2).
	if view.has_signal("node_entered"):
		view.node_entered.connect(
			func(place: int) -> void: _on_world_map_node_entered(view, place))
	layer.add_child(view)

	# Take the battlefield down to black BEFORE the map is in the tree, so the mount itself
	# is never a visible frame. The map then comes up under its OWN screen-in quad rather
	# than under a cover from here — which also retires a trap this used to carry: a cover
	# owned by the navigator could not be the inherited `_fade_rect`, because that lives in
	# `FadeLayer`, ALSO layer 100, and this layer joins the tree later, so the map drew on
	# top of the very rect meant to hide it. A screen that covers itself cannot have that
	# bug.
	await _fade_battlefield_out()
	# [b]The battlefield world goes with it (ADR-0162).[/b] `_fade_battlefield_out` returns
	# only once `_fade_rect.color.a == 1.0`, so the teardown frame is already hidden — and
	# the rect, not the outgoing group's `{3E}` quad, is what holds the black from here on.
	#
	# This is the console's own shape: entering the overworld is a `WORLD.BIN` load and the
	# battlefield is GONE, not parked. Keeping it parked is what put a black wall in front
	# of the Formation screen: a group's scene-out leaves a [ScreenOverlayQuad] quad
	# standing (scn 12 ends on `{3E} Color Screen Mode 2 (0,0,0)->(255,255,255)`), those
	# quads rewrite their corners to NDC and carry a cull-proof AABB, so they fill the
	# screen of ANY camera in the world — including the orthographic one `Formation.tscn`
	# brings with it. The map itself never noticed because it is a CanvasLayer at 100 and
	# draws over all 3D. Formation is a Node3D and cannot.
	#
	# Freeing the VM frees the whole family with it: every overlay is a VM CHILD
	# (`ScenarioVM._make_color_screen` and its siblings `add_child` them), so this needs no
	# per-overlay bookkeeping and cannot go stale when a fifth overlay is added.
	_teardown_world()
	# `_teardown_world` does not clear this, and `_ensure_battle_world` trusts it: leaving
	# the outgoing root here would make a later hop BACK to the same group skip its boot and
	# play a beat against a freed world.
	_battle_world_root = -1
	add_child(layer)
	await get_tree().process_frame

	# Hold until the screen has raised itself. Both reasons the old cover tween had for
	# SUSPENDING the screen here still hold — a screen the player cannot see yet must not
	# act on a press, and `dismissed` is awaited BELOW, so a ✕ landing mid-ramp would emit
	# it with nothing connected, be dropped, and hang the walk on a screen that had already
	# asked to close — but [method WorldMapScene.set_suspended] is the WRONG instrument for
	# them now, and calling it here is a deadlock.
	#
	# Suspending runs `set_animated(false)` -> `set_process(false)`, and the screen-in rides
	# that same clock. Suspend then await and the ramp never advances, `screen_in_finished`
	# never fires, and this await never returns. §33.7 is clear about what suspend is FOR:
	# handing the display to Formation/Data/Option, where the map genuinely does not tick.
	# A screen drawing itself in is not that.
	#
	# So the screen gates its own input while it raises itself (`WorldMapScene`'s
	# `_unhandled_input`), and this only waits. Nothing between the wait and
	# `await view.dismissed` below yields, so there is no frame in which a `dismissed`
	# could be emitted and dropped.
	await _await_screen_in(view)
	print("[NavigatorMain] WORLD MAP after group %d (press Enter/Backspace to continue)" % root)
	if _autoplay_gate(AUTO_ADVANCE_NODE_SLUG):
		# DEFERRED, and that is load-bearing. Auto-advance ends in `dismissed`, and the
		# `await` for it is three lines BELOW — so a synchronous call emits the signal with
		# nothing connected, the emission is dropped, and the walk hangs on a screen that
		# already asked to close. §18.2 is the worked example of exactly this hang, from
		# the ✕-during-fade case. Deferring lets `run_world_map` arm its await first.
		_auto_advance_world_map.call_deferred(view)
	if view.has_signal("dismissed"):
		await view.dismissed
	layer.queue_free()
	_nav_runner.on_world_map_finished()


## Take the one live hand-off without waiting for ○ (`navigator.auto_advance_node`).
##
## Drives the map's OWN entry path rather than calling the handler directly, so autoplay
## exercises what a press exercises: on the marker's node the event fires immediately, and
## on any other known node the marker walks there and it fires on ARRIVAL (§32.2). Either
## way it is [signal WorldMapScene.node_entered] that reaches Campaign.
##
## STOPS, loudly, on anything but exactly one. Zero means the story counter is at a value
## that binds no script — eight of them exist (§29.5) — or that a scenario failed to
## advance it. More than one means the map really is offering a choice, which the main
## story never does. Both are worth a human, and neither should be guessed past.
func _auto_advance_world_map(view: Node) -> void:
	var live := Campaign.live_enter_nodes()
	var story := Campaign.story_counter()
	if live.size() != 1:
		push_warning(("[NavigatorMain] auto-advance STOPPED: %d node(s) carry a live "
				+ "hand-off at story counter %d — expected exactly 1. %s")
				% [live.size(), story, str(live)])
		print("[NavigatorMain] auto-advance STOPPED at story %d — %d live hand-off(s) %s"
				% [story, live.size(), str(live)])
		return
	var index: int = live[0]
	var place := index + 1
	var emit := Campaign.enter_at(index)
	print("[NavigatorMain] auto-advance: story %d -> place %d, scenario %d"
			% [story, place, int(emit.get("scenario_id", -1))])
	if view.has_method("enter_place"):
		view.enter_place(place)
	else:
		push_error("[NavigatorMain] the world map has no `enter_place` — cannot auto-advance")


## A world-map node was entered — X1's whole job on the port side.
##
## `place` is a PLACE NUMBER (1-based, the ROM's own `hit = i + 1`); the node script table
## and the variable store are in NODE INDEX space. `Campaign.place_to_index` is the one
## conversion.
##
## The emit is `(scenario_id, transition_mode)`. `scenario_id` resolves to its group root,
## and `plan_actions(root, root)` yields that group's actions PLUS a fresh `world_map`
## action — because the group's own successor is `world-map`, and `GameNavigator` appends
## one on that. Appending it to the live plan is therefore all the chaining there is: the
## `world_map` action stops being terminal because a successor now exists, and the next hop
## comes for free. `NavigatorRunner._advance` re-reads `_actions.size()` each time, so no
## runner change is needed; its 512-iteration guard backstops a runaway chain.
func _on_world_map_node_entered(view: Node, place: int) -> void:
	var index := Campaign.place_to_index(place)
	var emit := Campaign.enter_at(index)
	if emit.is_empty():
		# Not every node hands off. A node with no live `enter` at this story counter is
		# ordinary — the player stands there and the map keeps running.
		print("[NavigatorMain] world map: place %d has no live hand-off at story %d"
				% [place, Campaign.story_counter()])
		return
	var scenario_id := int(emit["scenario_id"])
	var mode := int(emit["transition_mode"])
	var root := ScenarioGroupDatabase.root_for_scenario(scenario_id)
	if root < 0:
		push_error("[NavigatorMain] world map: scenario %d has no group — cannot chain"
				% scenario_id)
		return
	var actions := _game_nav.plan_actions(root, root, _mutation_script, _show_formation)
	if actions.is_empty():
		push_error("[NavigatorMain] world map: group %d planned 0 actions" % root)
		return
	# `transition_mode` is carried and logged, not acted on: §32.5 measured it as the
	# PRESENTATION (2 = light, else heavy) and explicitly refuses "mode = battle". Whether
	# this launch deploys is derived from the scenario record, in `run_pre_battle`.
	print("[NavigatorMain] world map -> scenario %d (group %d, transition mode %d) — "
			% [scenario_id, root, mode]
			+ "appending %d action(s) to the walk" % actions.size())
	_nav_runner._actions.append_array(actions)
	# Close the map. `run_world_map` is awaiting `dismissed`; when it releases it calls
	# `on_world_map_finished()` -> `_advance()`, which steps into the actions just appended.
	if view.has_method("leave"):
		view.leave()


## Window ids from WORLD_MAP_SCREEN.md §33.3's table. Only `7` is built; the others exist
## so that "not built" reads as a named screen rather than as a number.
const WM_WINDOW_NAMES := {
	7: "Formation", 11: "Brave Story", 14: "Tutorial", 12: "Data", 5: "Option",
}
const WM_WINDOW_FORMATION := 7


## A START-menu row landed. Formation opens the ported screen; the rest say so and return
## to the map.
##
## [b]This is not [method run_formation_view].[/b] That one is debug-gated behind
## `navigator.show_formation` and is documented as running "on demand and NEVER on the
## proof path" — the world map opening Formation is ordinary gameplay, so it must not
## inherit a debug gate. Since ADR-0181 they no longer even share a scene: this mounts the
## ADR-0084 COORDINATOR ([constant FORMATION_SCREEN_PATH]), which is what makes ○ open a
## unit's Status screen and △ the main menu. On the bare [FormationScene] both keys were
## dead — `unit_activated` was emitted into the void and `formation_start_menu` had no
## branch at all.
##
## [b]Nothing is injected.[/b] The coordinator reads `CharacterCatalog.owned_units()` itself
## (ADR-0180's one population, ADR-0181's `_resolve_roster`), so there is no second branch
## that could answer with a different list — which is the defect class that put a unit named
## "Marcus" on this very screen.
##
## The map is SUSPENDED rather than layered under, because that is what the console does
## (§33.7: Formation is a blocking `WORLD.BIN` call, not a page push) — and because the
## map is a CanvasLayer at layer 100, so anything mounted in the 3D world would render
## UNDER it however the cameras are arranged.
func _on_world_map_menu_row(view: Node, window: int) -> void:
	var name: String = WM_WINDOW_NAMES.get(window, "window %d" % window)
	if window != WM_WINDOW_FORMATION:
		print("[NavigatorMain] world map menu -> %s — not ported (§33.3)" % name)
		return
	var scene: PackedScene = load(FORMATION_SCREEN_PATH)
	if scene == null:
		push_error("[NavigatorMain] world map -> Formation: cannot load %s"
				% FORMATION_SCREEN_PATH)
		return
	var layer := view.get_parent() as CanvasLayer
	if view.has_method("set_suspended"):
		view.set_suspended(true)
	if layer != null:
		layer.visible = false
	# [b]Lift the battlefield fade rect, or Formation renders behind a black wall.[/b]
	# `_fade_battlefield_out` tweened it to alpha 1 and LEFT it there — it is what stands in
	# for the torn-down battlefield while the map is up, and the map's own CanvasLayer draws
	# over it only because that layer is added later at the same layer 100. Hiding the map
	# layer un-hides the rect.
	#
	# Formation cannot draw over it: the screen is a **Node3D with its own orthographic
	# Camera3D**, so it renders through the 3D world, and a CanvasLayer at 100 covers all 3D
	# regardless of what is mounted beneath it. Reported from play as "the formation screen
	# just goes black".
	var fade_alpha := 0.0
	if _fade_rect != null and is_instance_valid(_fade_rect):
		fade_alpha = _fade_rect.color.a
		_fade_rect.color.a = 0.0
	var formation = scene.instantiate()
	add_child(formation)
	# ADR-0172: the screen raises ITSELF under its own subtractive ramp; the mount only says
	# "go". Opt-in rather than automatic for the reason `WorldMapTownPage.begin_open` gives —
	# see `FormationDetailTransition.begin_screen_in`.
	if formation.has_method("begin_screen_in"):
		formation.begin_screen_in()
	# [b]The screen takes the input frame (ADR-0177).[/b] `set_suspended(true)` above yielded
	# the map's; this claims it for Formation, so everything else is deafened STRUCTURALLY
	# rather than by each consumer remembering to check a flag. Popped below, and Focus also
	# drops it on `tree_exiting` — so the `queue_free` path cannot strand the stack.
	Focus.push("formation", formation)
	print("[NavigatorMain] world map -> FORMATION — %d owned unit(s)"
			% CharacterCatalog.owned_units().size())
	# The coordinator eats `FormationScene.dismissed` for its own unwind and re-emits its OWN
	# at rest (ADR-0181). Awaiting the wrong one is not a wrong value, it is a HANG — this
	# await simply never returns and the map never comes back, with no error anywhere.
	# `NavigatorWorldMapFormationDismissTest` seeds that arm red.
	if formation.has_signal("dismissed"):
		await formation.dismissed
	if Focus.holds(formation):
		Focus.pop(formation)
	formation.queue_free()
	await get_tree().process_frame
	# Put the rect back before the map reappears: it is the map layer's backdrop for the
	# rest of this mount, and leaving it clear would show the torn-down battlefield.
	if _fade_rect != null and is_instance_valid(_fade_rect):
		_fade_rect.color.a = fade_alpha
	if layer != null and is_instance_valid(layer):
		layer.visible = true
	if is_instance_valid(view) and view.has_method("set_suspended"):
		view.set_suspended(false)
	print("[NavigatorMain] world map <- Formation")


## Universal PRE-BATTLE setup breakpoint (GAME_STATE_TRANSITIONS.md §2.6). EVERY battle
## runs this before combat: the world is already booted (opener beat), so `_entd_record`
## is this battle's ENTD, units are spawned at their positions, and the roster→slot binding
## is resolvable. Present the config and PAUSE (debug pause) — press Enter to start combat;
## inspect the config live via F3 → ROSTER → "Battle Binding".
##
## The ENTD control flag (GAME_STATE_TRANSITIONS.md §2.6) only changes what the setup step
## HOSTS — a predetermined cast (Orbonne, the one control>0 battle) presents a fixed config;
## a roster-fed battle will host DEPLOYMENT placement here (stubbed for now). The config
## breakpoint itself is universal: there is always a battle to set up.
func run_pre_battle(root: int) -> void:
	# THE BATTLE WORLD MUST EXIST FIRST, and not only so the breakpoint has something to stand
	# on. On the linear walk the opener beat already booted it and this is a no-op; on a DIRECT
	# SEEK into pre_battle — which is what "play battle N" is (ADR-0264) — nothing else will.
	#
	# 🔴 AND IT MUST COME BEFORE THE ENTD IS READ. `_entd_record` is resolved by the world boot
	# (`_boot_world_for` → `_resolve_scenario`), so every question asked above this line was
	# asked of the PREVIOUS scenario's ENTD — record "256" on a fresh seek, which is not
	# predetermined. That is how a seek into Orbonne, the one control>0 battle in the game,
	# announced itself as "roster-fed (0 owned deployed)" and took the roster-fed branch while
	# `_ensure_owned_deployed` — which re-reads the record AFTER the boot — correctly refused
	# to deploy anybody. Two answers to one question, from one field read a frame apart.
	#
	# The tree check is the bare-construct navigator unit tests, which call this on a `new()`'d
	# host with no scene under it; they set `_entd_record` themselves.
	if is_inside_tree():
		await _ensure_battle_world(root)
	var entd = _load_entd_record(_entd_record)
	var predetermined := BattleDeployment.is_predetermined(entd)

	# ROSTER-FED DEPLOYMENT (wayfinder #234 A/D): a control=0 battle (Gariland) is not baked
	# into the ENTD — the player's owned roster deploys onto the zone tiles. This step no
	# longer OWNS that placement: the squad is put on the field when the battle world boots
	# (`play_beat` / `_ensure_battle_world`), because an opener addresses it. What remains
	# here is the ENSURE — idempotent, and the thing that still places on a direct seek
	# straight into pre_battle, where no opener beat ran.
	#
	# THIS IS THE ONLY QUESTION `_is_roster_fed` STILL ANSWERS (ADR-0265 Amendment 1). It used
	# to gate the loop and the cursor below as well, and transitively to decide who could be
	# steered; both of those are questions about the BATTLE, not about where its cast came from.
	var roster_fed := _is_roster_fed(predetermined)
	if roster_fed:
		await _ensure_owned_deployed(root)

	# "Skip pre-battle breakpoints" (AUTOSAVE, ADR-0068) — the pre-battle analogue of dialogue
	# auto-advance: when set, don't park; go straight to combat. `bind` register-reads in one
	# call (idempotent, coalesces the persisted override), so this is safe regardless of panel
	# build order. The debug toggle lives in NavigatorDebugPanel.
	if _autoplay_gate(SKIP_PRE_BATTLE_SLUG):
		print("[NavigatorMain] PRE-BATTLE skipped (%s) — straight to combat" % SKIP_PRE_BATTLE_SLUG)
		_nav_runner.on_pre_battle_finished()
		return
	var slots: Array = entd.get("slots", []) if entd != null else []
	var summary: Dictionary = RosterDebugView.binding_summary(
		slots, int(_entd_record), _binding, CharacterCatalog)
	var cast := "predetermined cast (%d control)" % BattleDeployment.control_count(entd) \
		if predetermined else "roster-fed (%d owned deployed)" % _deployed_owned.size()
	print("[NavigatorMain] PRE-BATTLE root %d ENTD %s — %s; config: %d slot(s), %d bound / %d fallback. COMMAND MODE — Deployment; press Space to start combat (F3 → ROSTER → Battle Binding to inspect)."
		% [root, str(_entd_record), cast, int(summary["total"]), int(summary["bound"]), int(summary["fallback"])])
	# COMMAND MODE — Deployment (ADR-0082): build the CombatLoop UP FRONT frozen
	# (combat_active=false, idle gambits) and wire the roam cursor seeded on the leader, so
	# Deployment IS command mode — the same flag state a mid-battle Pause is, not a separate
	# "no loop yet" mechanism. Space then leaves Deployment (→ run_combat → `_go_live`).
	#
	# UNCONDITIONAL, and that is the fourth Orbonne report (ADR-0265 Amendment 1). This was
	# `if roster_fed:`, so on a predetermined battle `_pre_battle_active` was set with no loop
	# and no cursor under it — the player parked over a field they could not point at, and the
	# cursor appeared only once combat started. A cursor and a frozen loop are what "the battle
	# is set up" MEANS; neither is a question about how the cast was fed.
	#
	# Idempotent with `run_combat`, which builds both again if this did not run — the
	# bare-construct unit tests are out of tree and reach neither.
	if is_inside_tree():
		await _build_frozen_combat_loop(root)
		await _enter_command_cursor()
	_pre_battle_active = true


## Is `root`'s battle fed by the player's ROSTER (rather than a predetermined ENTD cast)?
##
## A control=0 battle (Gariland, Mandalia — the ordinary case) is not baked into the ENTD:
## the player's units are not in the ENTD at all (GAME_STATE_TRANSITIONS.md §2.6) and are
## inserted from the saved formation into the deployment zone at battle start. A
## predetermined cast (Orbonne, the one control>0 battle) has nothing to insert.
##
## ⚠️ IT ANSWERS ONE QUESTION AND ONLY ONE: should the saved roster be PLACED. It used to
## gate the frozen loop and the cursor as well, and — through `_deployed_owned` — to decide
## who the player could steer; neither of those is a question about roster-feeding, and both
## answered "nobody" on the one predetermined battle in the game (ADR-0265 Amendment 1).
##
## Also gated on a live scene (`is_inside_tree`) + a non-empty owned roster, so the
## bare-construct navigator unit tests — which call `run_pre_battle` on a `new()`'d host
## with no world under it — are unaffected. `predetermined` is passed in because both
## callers have already loaded the ENTD record to compute it.
func _is_roster_fed(predetermined: bool) -> bool:
	return not predetermined and is_inside_tree() and not CharacterCatalog.owned_units().is_empty()


## Place the owned squad on `root`'s battle world if it is not already standing there.
##
## THE ONE PLACEMENT ENTRY POINT. Called at world boot (`play_beat`, `_ensure_battle_world`)
## so the squad precedes the opener's first opcode, and again from `run_pre_battle` — where
## it is a no-op on the linear walk and the actual placement on a direct seek into
## pre_battle. Idempotence is keyed on `_deployed_root`, not on `_deployed_owned` being
## non-empty: a battle whose zone placed nobody must not be retried on every beat.
##
## Re-placing is not merely wasteful — `_deploy_owned_units` frees and respawns, so running
## it after an opener would discard the visibility and pose state that opener's Erase/Draw
## sweeps just established on those same units.
func _ensure_owned_deployed(root: int) -> void:
	if _deployed_root == root:
		return
	var entd = _load_entd_record(_entd_record)
	if not _is_roster_fed(BattleDeployment.is_predetermined(entd)):
		return
	await _deploy_owned_units(root)
	_deployed_root = root


## Snap-deploy the owned roster onto the battle's deployment zone (wayfinder #234 D). Spawn
## each `CharacterCatalog.owned_units()` Character as a combat-ready Unit, place it on a zone
## tile, and stash the placed units in `_deployed_owned` for combat.
##
## [b]The placement comes from a [DeploymentAssignment], not from [DeploymentPlan] direct.[/b]
## `auto_fill()` is mandatory-hoist + the same `DeploymentPlan.assign` call this used to make,
## so the squad it produces is identical wherever the roster already leads with the mandatory
## unit — which is every battle today, because `CharacterCatalog.owned_units()` is Ramza-first.
## The difference is what happens when it is NOT: the old direct call honoured the scenario's
## `ramza_mandatory` flag only by accident of roster order, and a roster that had been sorted,
## filtered or grown past the cap would have benched him with nothing to say so. `auto_fill`
## hoists the mandatory units to the front by construction.
##
## This is also the seam the interactive picker plugs into (ADR-0264): an assignment is the
## thing a picker EDITS, and auto-deploy then lives inside it rather than beside it.
## Runs on the already-booted battle world, immediately after the boot and BEFORE any beat
## plays on it. NOT the auto-march. Reached only through [method _ensure_owned_deployed] —
## call that, not this: it is what keeps placement to once per booted battle world.
func _deploy_owned_units(root: int) -> void:
	_free_deployed_owned()
	var owned: Array = CharacterCatalog.owned_units()
	var scenario := ScenarioDatabase.get_scenario(root)
	var zone_idx := int(scenario.get("first_squad_deployment_idx", 0))
	var zone := DeploymentZoneDatabase.get_zone(zone_idx)
	# `for_scenario` reads the same scenario record and the same zone this does, and resolves
	# the mandatory unit from the scenario's own `ramza_mandatory` flag. Identity is the
	# catalogue slug (ADR-0180) and it is passed as a Callable, because that class deliberately
	# knows nothing about what it is holding — here it holds Characters, on `GambitBattle` it
	# holds Units, and neither has to be the other.
	var assignment := DeploymentAssignment.for_scenario(owned, root,
		func(c) -> String: return String(c.slug) if c != null and "slug" in c else "")
	if assignment.tiles.is_empty():
		push_warning("[NavigatorMain] deploy: no zone tiles for idx %d — no owned units placed" % zone_idx)
		return
	assignment.auto_fill()
	# The deployment zone dictates which way the placed units face. `unit_facing_12bit` is
	# the parser's `start_facing_12bit` — BOTH nibbles of the record's byte 0x07 composed,
	# because the engine adds them (`R = zone_facing + unit_facing - 1`, ATTACK.OUT overlay
	# 0x801C5588; derivation above `start_facing_12bit`). THE KEY NAME LIES: it is not the
	# `unit_facing` nibble lifted on its own — reading it that way is what stood the squad
	# side-on at Mandalia, since the nibble is only absolute when `zone_facing == 3`
	# (Gariland's family, which is why one battle validated it). The result is an
	# Orientation pose consumed raw, NOT chirality-flipped. Without applying it the owned
	# units keep their spawn-default facing (all the same, "awkward"); with it they face the
	# battlefield (Gariland zone 256 -> 0x000 East at the far-half thieves; Mandalia zone 257
	# -> 0x800 West at the Corps). Combat units face via the plain cardinal setter
	# (`facing_direction` forward-converts to the angle), so `is_cinematic_unit` stays
	# false — no scenario tent pose.
	var deploy_facing_12bit := int(zone.get("unit_facing_12bit", PsxNum.EAST_12BIT))
	var deploy_facing := AnimationStateController.angle_12bit_to_facing(deploy_facing_12bit)
	var invincible := _autoplay_gate(OWNED_INVINCIBLE_SLUG)
	# ZONE-TILE order, which is `squad()`'s contract — the field fills the way the table reads.
	for row in assignment.squad():
		var character = row["unit"]
		var tile: Vector2i = row["tile"]
		var unit = await _spawn_owned_unit(character)
		if unit == null:
			continue
		unit.place_on_tile(tile.x, tile.y, _map)
		_make_combat_ready_from_character(unit, character, UnitStats.Team.PLAYER)
		# COMMANDABLE — the roster writer (cluster 41). A deployed unit is the player's
		# because the player placed it; that is a fact about the deployment, which is why it
		# is written here and not off any ENTD slot. The ENTD writer is `_make_combat_ready`.
		if "commandable" in unit:
			unit.commandable = true
		unit.facing_direction = deploy_facing
		# ON THE FIELD ⇒ PRESENT. A deployed unit stands on the battlefield, exactly like an
		# ENTD-spawned combat unit — which `_spawn_units` marks `scenario_present=true` /
		# team_color at spawn (ScenarioPlayerScene). Roster-deployed units bypass that spawn,
		# so set the same truth here; otherwise a woven scenario beat's frame-0 render gate
		# (`_apply_initial_visibility`, run per member load) hides any of these units the VM
		# registers (e.g. the protagonist under RAMZA_EVENT_UID below) — the victory beat then
		# frames a unit whose sprite isn't drawn. team_color 0 = Blue/player (off the {43}
		# dead-unit-fade sweep). Not a "leader" special case — every deployed unit is present.
		if "scenario_present" in unit:
			unit.scenario_present = true
		if "scenario_team_color" in unit:
			unit.scenario_team_color = 0
		if invincible:
			unit.unit_stats.max_hp = PROOF_HP
			unit.unit_stats.current_hp = PROOF_HP
		_deployed_owned.append(unit)
	# Register the WHOLE deployed squad on the event-unit registry, not just the leader. The
	# formation squad occupies `0x78 + <plan index>` ([constant SQUAD_EVENT_UID_BASE]) and the
	# leader ALSO answers to `0x01` ([constant RAMZA_EVENT_UID]) — an alias, one unit under two
	# keys. The VM reads the SAME `_units_by_id` dict (wired by reference in
	# `_boot_scenario_world`), and deploy now runs at world boot, so every id is in place before
	# the opener's first opcode.
	#
	# Registering only the leader was correct for exactly one battle. Gariland's scn 12 names
	# `0x01` and nothing else, so "the other owned generics stay unregistered — no opcode
	# addresses them" read as a rule when it was a fact about one chunk. 28 of 72 battle groups'
	# openers name `0x78`-`0x7C`; those Erase/Draw sweeps silently addressed nothing, which the
	# runtime reported all along as `Erase Unit 0x78 — no spawned unit; skipping`.
	#
	# (Presence/visibility is established per-unit in the deploy loop above — a deployed unit is
	# on the field.)
	for i in _deployed_owned.size():
		_units_by_id[SQUAD_EVENT_UID_BASE + i] = _deployed_owned[i]
	if not _deployed_owned.is_empty():
		_units_by_id[RAMZA_EVENT_UID] = _deployed_owned[0]
	_register_deployed_idle_pump()
	var facing_names := ["N", "E", "S", "W"]  # FacingDirection order (avoid enum.keys() reflection)
	print("[NavigatorMain] DEPLOY root %d zone %d — placed %d/%d owned onto %d zone tile(s), facing 0x%03X (%s)%s" %
		[root, zone_idx, _deployed_owned.size(), owned.size(), assignment.tiles.size(),
		deploy_facing_12bit, facing_names[deploy_facing] if deploy_facing < facing_names.size() else str(deploy_facing),
		" [proof: invincible]" if invincible else ""])


## March-idle the deployed squad on the ONE 60 Hz VM tick (ADR-0065) — no second clock. The VM
## pumps `units_by_id` AND `idle_only_units`, so this list is the REMAINDER: every deployed unit
## the registration above did not give an event id. Register a unit on both and it is
## double-pumped.
##
## Today that remainder is empty — the whole squad takes `0x78`+ ids. This is not therefore dead
## code: it is what keeps the pump correct when it is NOT, and a deploy that placed more units
## than the squad id block covers is exactly such a case. Computing the remainder is also the only
## version of this that cannot go stale, which the version it replaces did: it sliced index 0 off
## a list on the standing rule that non-leader units "must NOT enter `units_by_id` — no scn-12
## opcode names them". Scn 12 does not name them; 28 of 72 openers do.
##
## The VM only pumps this list; NavigatorMain owns its lifecycle (populated here, cleared in
## `_free_deployed_owned`).
func _register_deployed_idle_pump() -> void:
	if _vm == null or not is_instance_valid(_vm) or not ("idle_only_units" in _vm):
		return
	var registered: Array = _units_by_id.values()
	var strays: Array = []
	for u in _deployed_owned:
		if not (u in registered):
			strays.append(u)
	_vm.idle_only_units = strays


## Instance a fresh Unit from a catalogue [Character] (owned units are catalogue-resident,
## not ENTD slots) through the one spawn seam, [UnitSpawn.build] — which resolves the
## owned body/portrait via the one template resolver seam. Added to the tree; awaits one
## frame so Unit._ready builds the animation set + playbacks (place_on_tile /
## combat-ready both need the movement component up). What this adds over the bare seam
## is the Form stamp below: the deploy seam has no ENTD slot to read `special_name` off.
func _spawn_owned_unit(character) -> Node:
	# Materialize the active Form at the deploy seam (ADR-0079). A roster-deployed owned
	# unit has no live ENTD slot to read `special_name` off (the ENTD seam ScenarioPlayerScene
	# uses), so it SELECTS the active Form from the ROM-derived Form set on its Catalog
	# Character and stamps that Form's `special_name` one line before `resolve()` — mirroring
	# the SHAPE of the ENTD seam. A miss (no Form on file) returns SPECIAL_NAME_NONE, which the
	# resolver job-routes — exactly right for the generic squadmates. Story-context selection
	# is stubbed to Ch1 while Gariland is the sole reachable chapter; the seam SELECTS (not
	# hardcodes), so a Ch2+ battle drops in without reshaping it. The resolver stays a pure
	# function of the stamped param — it never reads story context.
	character.special_name = character.active_special_name(STORY_CHAPTER_STUB)
	var unit := UnitSpawn.build(character)
	if unit == null:
		push_error("[NavigatorMain] deploy: cannot spawn a Unit for %s" % str(character.slug))
		return null
	# force_readable_name: the seeded generics are named for their JOB, so the squad
	# collides on `name` (2 Squires, 2 Chemists) and Godot's fast path would rename the
	# duplicates `@Node3D@<id>`. Identity is the `character_slug` meta; `name` is display.
	add_child(unit, true)
	await get_tree().process_frame
	return unit


## Make a spawned Unit combat-ready from the [Character] it IS: bind the progression,
## seed the job's starter abilities and the gambit list ([UnitSpawn.bind_for_combat]),
## then this host's own two steps — the logical tile the scenario's `cinematic_place`
## never populated, and SCENARIO clock ownership until `_go_live`.
##
## The whole combat-ready tail for BOTH navigator paths. `_make_combat_ready` resolves an
## ENTD slot's identity and then calls this; the deploy path (wayfinder #234 A's Character
## path — no ENTD slot, no SlugBinding) calls it directly because the identity is already
## the catalogue Character. A slot and an owned entry differ in WHO the unit is, never in
## what making one combat-ready does.
func _make_combat_ready_from_character(unit: Node, character, team: int) -> void:
	if character.progression == null:
		push_warning("[NavigatorMain] owned unit %s has no progression — skipping" % character.slug)
		return
	# Progression (by reference), job starter abilities and the gambit list are the
	# ONE spawn-bind seam (ADR-0180) — the same three steps the arena runs. What
	# follows them is this host's own: the scenario placed the unit without a
	# logical tile, and the clock is SCENARIO-owned until `_go_live`.
	UnitSpawn.bind_for_combat(unit, character, team)
	if unit.movement_component != null:
		# #817 — DO NOT RESET THE LEVEL. This call used to pass no argument, which
		# defaults `level` to the ground; the transform answers the two grid axes
		# and nothing answers the third, so a hardcoded 0 was the only level a unit
		# could enter battle on.
		#
		# That was harmless only while battle could not HOLD a level: the GPU packer
		# dropped `cell.z` anyway (#816). ADR-0224's shader pass makes it a live loss
		# site — a unit that walked onto a bridge in a scenario would be silently
		# reseated on the ground under it — which is why the fix lands in the same
		# commit that creates the hazard rather than before or after it.
		#
		# The scenario mover is already level-aware (ADR-0219) and PR #815 made its
		# walk latch the level, so `current_cell.z` is the answer whenever the unit
		# has a logical tile at all. When it does not — the hole this call's own
		# comment was patching — the ground is still the only defensible default,
		# because the level is exactly what a transform cannot say.
		var seat_level := TerrainCell.GROUND_LEVEL
		if unit.movement_component.current_cell != TerrainCell.NONE:
			seat_level = unit.movement_component.current_cell.z
		unit.movement_component.initialize_logical_position(seat_level)
	# SCENARIO-owned pre-live so the VM idle pump breathes it through Deployment;
	# `_go_live` flips the whole loaded cast SCENARIO→COMBAT at the handoff (ADR-0083).
	unit.clock_owner = ClockOwner.SCENARIO
	if "is_cinematic_unit" in unit:
		unit.is_cinematic_unit = false


## Free the units deployed for a prior battle (so a group re-boot doesn't leak them —
## they live outside `_units_by_id`, which `_teardown_world` prunes).
func _free_deployed_owned() -> void:
	# The squad is registered on `_units_by_id` under its `0x78`+ ids plus the leader's `0x01`
	# alias (see _deploy_owned_units). Drop every entry that POINTS AT a deployed-owned unit —
	# by identity, not by id, so the alias and the squad ids are dropped by one rule and a
	# predetermined battle that legitimately spawned an ENTD unit on one of those ids isn't
	# disturbed. WITHOUT a second free: the loop below frees the instances, so
	# `_teardown_world`'s `_units_by_id` sweep must no longer see them (else it queue_frees
	# already-freed units).
	for uid in _units_by_id.keys():
		if _units_by_id[uid] in _deployed_owned:
			_units_by_id.erase(uid)
	# Stop the VM idle-pump before the units are freed (the generics were registered on the
	# VM's one-tick idle-only list in `_deploy_owned_units`). Clear rather than filter — the
	# whole squad is going away.
	if _vm != null and is_instance_valid(_vm) and "idle_only_units" in _vm:
		_vm.idle_only_units = []
	for u in _deployed_owned:
		if is_instance_valid(u):
			u.queue_free()
	_deployed_owned = []
	# Nobody is deployed anywhere now, so the next `_ensure_owned_deployed` must place.
	_deployed_root = -1


## Resume from the pre-battle config breakpoint → dispatch combat. Fired by the debug pause
## (Enter, see `_unhandled_input`) or a programmatic resume. No-op when not parked.
func resume_pre_battle() -> void:
	if not _pre_battle_active:
		return
	_pre_battle_active = false
	print("[NavigatorMain] PRE-BATTLE resume → combat")
	_nav_runner.on_pre_battle_finished()


## COMMAND MODE keys (ADR-0082, split by ADR-0137 Amendment 2). Tab used to be the ONE key driving
## every command-mode ⇄ Live transition; it now drives none of them. Starting the battle is a
## one-way phase EXIT and pausing is a repeatable TOGGLE, and one key carrying both is what left
## this host disagreeing with GPUArena (which used Space) and left Tab with no room to mean
## "inspect the unit under the cursor" on the map.
##
## TWO KEYS, TWO STOPS (cluster 41). SPACE governs whether time runs — deployment commit, turn
## commit, tactical stop, one rule reaching three states ([method _start_battle]). ESC raises
## the MODAL pause ([method _toggle_pause_screen]) and is the only key that leaves it. They are
## different kinds of stop, and the [StopBadge] exists because a motionless battlefield looks
## the same in both.
##
## Enter is reserved for the cursor's ACT and reaches it through `cursor_confirmed`; Tab reaches
## INSPECT through `cursor_inspected`. Neither is wired here.
func _unhandled_input(event: InputEvent) -> void:
	if not _in_command_mode_context():
		return
	# THE PAUSE SCREEN IS MODAL, and this is the half of the swallow the cursor's and camera's
	# `input_enabled` cannot cover — Space, Home and Esc reach neither of them. Esc is let
	# through because a modal with no reachable exit is a lock-out, not a pause. Same branch,
	# same order and the same reason as `GambitBattle._unhandled_input`'s.
	if pause_screen_open():
		if event.is_action_pressed("battle_pause"):
			_toggle_pause_screen()
		get_viewport().set_input_as_handled()
		return
	# THERE IS NO SKIP (design §1). The THIRD of the three gates the beat closes — the cursor
	# rig and the camera close their own, and this handler owns Space and Esc, which reach
	# neither. Without it the player could still start or pause a battle out from under a
	# running travel.
	if _beat.running():
		get_viewport().set_input_as_handled()
		return
	# `Home` — the way back to the taker from anywhere (design §4). Above the other two only
	# because it is the cheaper test; the three actions are disjoint.
	if event.is_action_pressed("turn_recenter"):
		# The handle lands in an annotated slot rather than going straight into the call:
		# `check_lattice_ports` reads a bare `_map.lattice` as an unprovable fetch (ADR-0192
		# dec. 3), and the annotation is also what types the argument at the seam.
		var lattice: Lattice = _map.lattice if _map != null else null
		_beat.bind(_cursor_rig, _player_camera, lattice,
			_combat_loop.units if _combat_loop != null else [])
		_beat.recenter()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("battle_start"):
		_start_battle()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("battle_pause"):
		_toggle_pause_screen()
		get_viewport().set_input_as_handled()


## True when the navigator has a battle whose command-mode keys are meaningful — either parked in
## Deployment (`_pre_battle_active`) or a live/paused CombatLoop exists. Guards the handlers so a
## stray Space/Esc outside a battle is ignored.
func _in_command_mode_context() -> bool:
	return _pre_battle_active or _combat_loop != null


## Space — ONE RULE, three states (cluster 41: *"Space is one rule: it governs whether time
## runs. Deployment commit, turn commit and the tactical stop are that one rule reaching three
## states — not three meanings."*). The three arms, in the order they are tested:
##
##   1. AN OPEN TURN, and it is yours → commit it. Tested first because a battle stopping on
##      turns is long past its pre-battle park, so the states are disjoint in practice and the
##      order only decides which no-op you get.
##   2. THE PRE-BATTLE PARK → leave Deployment (resume_pre_battle → runner advances →
##      run_combat goes live on the frozen loop). ADR-0082's FIRST transition and the only
##      one-way one; "starting the battle" is mechanically just leaving Deployment.
##   3. A RUNNING BATTLE → the tactical stop, and back. This arm did not exist until
##      ADR-0177 Amendment 3's step 5, which is exactly why ADR-0265 Amendment 1 could rule
##      gap F ("Space means two different things; a DECISION, not a port") REFUTED without
##      building anything: a host that lacks a state cannot reach that arm of the one rule.
##
## [b]Space is GO[/b] — the same grammar `GambitBattle._unhandled_input` settled on: one key ends
## whichever stop the player is expected to end, and it is never a pause key. The pause is Esc
## and it raises a modal ([method _toggle_pause_screen]); the two stops are different states
## ended by different keys, which is the whole reason the [StopBadge] exists.
##
## Committing with no edits IS "wait" (ADR-0239) — and here it is still ALL that commit can be:
## there is no adjustment UI on this host yet, so a spent turn is a waited turn. What CHANGED
## (ADR-0265) is whose turn reaches this line at all. The spine used to have no steerability
## concept, so every turn in the round-robin stopped the world and asked for a Space; now
## [method is_commandable] answers it, an enemy's turn is spent where it opens, and the press
## below serves only a turn that is actually the player's.
##
## 🔴 The guard is not a formality even so. `_on_director_turn_opened` passes a non-commandable
## turn with `call_deferred`, so there is exactly one frame in which an enemy's turn is open and
## a Space would spend a turn the player was never offered.
func _start_battle() -> void:
	if _turn_director != null and is_instance_valid(_turn_director) \
			and _turn_director.state() == TurnDirector.State.TURN_OPEN:
		if is_commandable(_turn_director.taker()):
			_turn_director.commit()
		return
	if _pre_battle_active:
		resume_pre_battle()
		return
	# THE TACTICAL STOP — Space's third arm, and the one that makes the other two read as one
	# key (cluster 41: "Space is one rule: it governs whether time runs"). This host used to
	# lack the state entirely, which is why ADR-0265 Amendment 1 could rule the gap-F question
	# ("Space means two different things") REFUTED: one rule, differently reachable, and a host
	# that lacks a state simply cannot reach that arm of it. It can now.
	_toggle_tactical_stop()


## THE TACTICAL STOP (cluster 41) — Space on a running battle. The sim halts and everything
## else stays live: the cursor walks, the camera pans, ○ opens a unit's screen. Stop and look.
##
## ⚠️ IT IS NOT A PAUSE, and the distinction is the reason the [StopBadge] exists. A pause is
## Esc, it raises a modal, and it is ended by a different key; this is Space both ways, and it
## leaves the battlefield drivable. Two motionless battlefields, two keys — a player with no
## badge would have to guess which one they are looking at.
##
## Reached from [method _start_battle] and not from its own action: Space carries all three
## arms of the one rule (deployment commit, turn commit, this), which is what keeps them one
## rule instead of three meanings. ADR-0082's two transitions are untouched — the flag state is
## the same one-flag state; what changed is which key drives it and what Esc does instead.
func _toggle_tactical_stop() -> void:
	if _combat_loop == null:
		return
	# Never while a turn is open. The world is ALREADY frozen — by the director, which holds the
	# loop's flag through the stop — so a toggle that flipped it would run the battle out from
	# under an open turn, which is the second-writer hazard [member _combat_active] names.
	# `GambitBattle._toggle_hold` refuses on exactly this test, and since `5406bd8be` both hosts
	# reach it from the same key. `_start_battle` already returns on TURN_OPEN, so this is the
	# belt to that braces and the guard a direct caller still needs. Hands-off (the default) the
	# director never leaves RUNNING, so this line costs the walk nothing.
	if _turn_director != null and is_instance_valid(_turn_director) \
			and _turn_director.state() != TurnDirector.State.RUNNING:
		return
	if _combat_active:
		_set_combat_live(false)
		print("[NavigatorMain] TACTICAL STOP (sim frozen; cursor + camera live) — Space resumes")
	else:
		_set_combat_live(true)
		print("[NavigatorMain] LIVE (sim resumed)")


# === The modal pause (Esc) ====================================================

## The pause screen's seat. Mounted on first use, like the badge: a walk that never reaches a
## battle never builds one.
var _pause_screen: PauseScreen = null

## What the world was doing when the pause was taken, so closing it RESTORES rather than
## assumes. Closing a pause taken during an open turn must not start the battle, and closing
## one taken while Space had stopped the clock must not start it again.
var _combat_active_before_pause := false


## Is the modal pause up? PUBLIC: it is the one question every other input owner on this host
## has to be able to ask, and a private flag would make each of them keep their own.
func pause_screen_open() -> bool:
	return _pause_screen != null and is_instance_valid(_pause_screen) and _pause_screen.is_open()


## Esc. Raise the pause screen over whatever the world was doing, or close it and put that back.
##
## Available in EVERY state, including a frozen one — "you may not pause while it is your turn"
## is a rule with nothing behind it, since the clock is already stopped and refusing costs the
## player a key that visibly does nothing. `GambitBattle._toggle_pause_screen` settled that and
## this is the same call on the same grounds.
##
## 🔴 It does NOT refuse over the map-hosted Formation screen, because that screen holds the
## camera takeover and its own saved clock (ADR-0261) and a second modal over it would release
## claims it did not take — the ownership bug that produced a hard lock-out on the other host
## once already. Its own ✕ closes it first.
func _toggle_pause_screen() -> void:
	if _combat_loop == null or not is_instance_valid(_combat_loop):
		return
	if _pause_screen == null or not is_instance_valid(_pause_screen):
		if not is_inside_tree():
			return  # bare-construct unit tests: no tree to hang a CanvasLayer on
		_pause_screen = PauseScreen.mount(self)
	if pause_screen_open():
		_pause_screen.close()
		_set_combat_live(_combat_active_before_pause)
		_set_battlefield_input(true)
		print("[NavigatorMain] resumed")
		return
	if _formation_map_screen != null and is_instance_valid(_formation_map_screen) \
			and _formation_map_screen.has_method("claims_held") \
			and _formation_map_screen.claims_held():
		return
	_combat_active_before_pause = _combat_active
	_set_combat_live(false)
	_pause_screen.open()
	_set_battlefield_input(false)
	print("[NavigatorMain] paused")


## The two device-input gates the battlefield accepts on, driven together. The same pair
## `GambitBattle._set_battlefield_input` drives, and for the same reason: gating one of the two
## is not a swallow, it just tells the player which key still works.
func _set_battlefield_input(enabled: bool) -> void:
	if _cursor_rig != null and is_instance_valid(_cursor_rig):
		_cursor_rig.input_enabled = enabled
	if _player_camera != null and is_instance_valid(_player_camera) \
			and "input_enabled" in _player_camera:
		_player_camera.input_enabled = enabled


## Flip the live/frozen flag on both the loop (its own tick gate) and our mirror in lockstep — the
## mid-battle pause/resume half of the toggle. The Deployment→Live half arms combat gambits via
## `_go_live` (a frozen loop has only idle gambits); a mid-battle pause/resume leaves gambits armed.
## Combat bodies are already COMBAT-owned (handed off at `_go_live`), so the VM pump skips them in
## both Live and Paused — no per-toggle freeze needed for the double-pump (ADR-0083). The ONLY thing
## this toggles on the VM is the Pause survey freeze: on Live→Paused freeze the SCENARIO-owned ambient
## pump so a paused battlefield is a full freeze-frame; on Paused→Live thaw it.
func _set_combat_live(live: bool) -> void:
	if _combat_loop != null and is_instance_valid(_combat_loop):
		_combat_loop.combat_active = live
	_combat_active = live
	_set_survey_freeze(not live)
	# The freeze is where the player edits (the formation screen holds one while it is up), so
	# it is what makes the armed gambits stale. Marked HERE and not only in the `_process` poll
	# because a freeze shorter than one frame is invisible to a poll — see [member _gambits_dirty].
	if not live:
		_gambits_dirty = true


## A turn opened. FOLLOW the loop into the pump mirror — the director has already written the
## loop's `combat_active` and that flag is its to write through a stop, so this is the mirror
## alone and NOT `_set_combat_live`, which would write the loop's flag back over the director's.
##
## Same call stack as the director's write, so no observer can ever catch the two disagreeing —
## the invariant `NavigatorTurnDirectorMountTest` arm (d) reads every frame. The survey freeze
## rides along for the same reason it does on Esc: a stopped turn should be a freeze-frame, which
## is the entire point of stopping on one.
##
## 🔴 IT READS THE FLAG, IT DOES NOT ASSUME IT. This used to open `_combat_active = false`, which
## is only true of a director that STOPS — so the handler could not be connected on a hands-off
## walk, so the connection became a mount-time bet on a runtime-mutable policy flag
## (`_mount_turn_director`). A hands-off director announces every turn it spends where it opens,
## with the world still running; asking the loop rather than assuming makes that arrival a no-op
## and the wiring unconditional.
func _on_director_turn_opened(taker: int, team: int) -> void:
	var frozen := _combat_loop != null and is_instance_valid(_combat_loop) \
		and not bool(_combat_loop.combat_active)
	_combat_active = not frozen
	_set_survey_freeze(frozen)
	# A turn nothing stopped for is not this host's business: the director spends it itself
	# (`_spend_where_it_opens`) and there is no stop to dress, nobody to tell and no press to
	# advertise. Returning here is what keeps the five unattended walks byte-identical.
	if not frozen:
		return
	# DEPLOYMENT opens with taker == -1 (TurnDirector design S9). This host never opens one —
	# its Deployment is `_pre_battle_active`, not a director state — but the signal is the same
	# signal in a different mode, so it is refused by name rather than by assuming it cannot
	# arrive.
	if taker < 0:
		return
	if not is_commandable(taker):
		# NOT YOURS TO STEER: a guest or an enemy. Spent where it opens, inside the freeze the
		# director already took, which is what makes it invisible to the battle around it. A
		# turn with no decision behind it is spent unchanged, and that is exactly "wait"
		# (ADR-0239) — this host has no rollout driver to think for it, and the unit's combat
		# gambits are already armed, so the auto-battle keeps driving it as it always has.
		#
		# Deferred so the commit never re-enters the signal it is inside — the same reason
		# `GambitBattle._on_turn_opened` defers `_pass_turn`.
		print("[NavigatorMain] unit %d acts (team %d)." % [taker, team])
		call_deferred("_pass_turn")
		return
	var who: String = _name_of_unit(taker)
	print("[NavigatorMain] YOUR TURN — %s (unit %d, team %d); Space spends it, Home recentres"
		% [who, taker, team])
	# The BEAT (`docs/TURN-OPEN-BEAT-DESIGN.md`): AT marker, cue, camera travel. Bound at use
	# because the cursor rig and the cast are both per-battle.
	var lattice: Lattice = _map.lattice if _map != null else null
	_beat.bind(_cursor_rig, _player_camera, lattice,
		_combat_loop.units if _combat_loop != null else [])
	_beat.open(taker)


## COMMANDABLE (cluster 41): does the unit at loop index [param unit_index] take the player's
## orders at all?
##
## THE ONE READER. Every consumer — the Space handler, the turn-open filter, the badge — asks
## here, so "whose turn is yours" has one answer instead of three copies of a `Dictionary.has`.
## Public because it is also what the Orbonne guard reads: an arm written against the private
## set could not survive that set being replaced by the fact on the unit, which is exactly what
## ADR-0265 Amendment 1 says has to happen.
func is_commandable(unit_index: int) -> bool:
	if _combat_loop == null or not is_instance_valid(_combat_loop):
		return false
	if unit_index < 0 or unit_index >= _combat_loop.units.size():
		return false
	var unit = _combat_loop.units[unit_index]
	return unit != null and is_instance_valid(unit) \
		and "commandable" in unit and bool(unit.commandable)


## How many of the booted cast take the player's orders. For the F3 State census and for
## the boot line — an empty commandable set is LEGAL (ADR-0265 Amendment 1) but it must be
## visible, because "the battle never stopped" and "the battle stopped on nobody's turn"
## are the same sentence from two sides and only one of them names the cause.
func commandable_count() -> int:
	if _combat_loop == null or not is_instance_valid(_combat_loop):
		return 0
	var n := 0
	for i in range(_combat_loop.units.size()):
		if is_commandable(i):
			n += 1
	return n


## Spend a turn that is not the player's. `commit()` and not a separate pass verb: spending a
## turn having changed nothing IS waiting (ADR-0239), and this host changes nothing on any turn
## it does not stop for.
func _pass_turn() -> void:
	if _turn_director != null and is_instance_valid(_turn_director) \
			and _turn_director.state() == TurnDirector.State.TURN_OPEN:
		_turn_director.commit()


## A turn ended — the beat's other end. The marker comes off and the cursor gets its ears back
## whatever ended it, including a commit that landed inside the travel.
func _on_director_turn_committed(_taker: int) -> void:
	_beat.hide_marker()
	_beat.end()
	_beat.beat_taker = -1


## What the badge should say right now, or `""` for "nothing worth saying".
##
## PURE, and public: a test can ask what the player would be told without owning a viewport or
## reading a pixel. The `GambitBattle` twin is `stop_badge_text`, and the two are deliberately
## NOT one function — the states are this host's (a pre-battle park, an Esc pause, an open
## turn) and so are the keys that end them.
##
## The ORDER of the tests is the whole content. Every one of these states has `_combat_active`
## false, so a badge that asked "is the sim running?" first would call all of them the same
## thing and tell the player to press the one key that refuses.
func stop_badge_text() -> String:
	if _combat_loop == null or not is_instance_valid(_combat_loop):
		return ""
	# The pre-battle park is a stop the player ends with Space, and it is not a pause.
	if _pre_battle_active:
		return "DEPLOYING — Space to start the battle"
	if _turn_director != null and is_instance_valid(_turn_director) \
			and _turn_director.state() == TurnDirector.State.TURN_OPEN:
		var taker := _turn_director.taker()
		# A guest's or an enemy's turn is opened and passed inside the same freeze
		# (`_on_director_turn_opened`), so there is no press to advertise and the badge would
		# flash once per enemy turn saying something the player cannot act on.
		if not is_commandable(taker):
			return ""
		return "YOUR TURN: %s — Space to spend it, Home to recentre" % _name_of_unit(taker)
	# The modal pause says PAUSED on its own scrim, in 56 px. A badge repeating it under the
	# screen that already covers the field is the one state this line must NOT claim.
	if pause_screen_open():
		return ""
	# The TACTICAL STOP. Named STOPPED and not PAUSED, and ended by the key that took it —
	# this host now has both stops (cluster 41), and telling them apart is the whole reason
	# the badge exists: two motionless battlefields are pixel-identical.
	return "" if _combat_active else "STOPPED — Space to resume"


## Polled once a frame from `_process`, above the live gate — see [method StopBadge.show_text]
## for why a poll and not an edge. Mounts the badge on first use: a walk that never reaches a
## battle never builds one.
func _refresh_stop_badge() -> void:
	if _combat_loop == null or not is_instance_valid(_combat_loop):
		if _stop_badge != null and is_instance_valid(_stop_badge):
			_stop_badge.show_text("")
		return
	if _stop_badge == null or not is_instance_valid(_stop_badge):
		if not is_inside_tree():
			return  # bare-construct unit tests: no tree to hang a CanvasLayer on
		_stop_badge = StopBadge.mount(self)
	_stop_badge.show_text(stop_badge_text())


## The taker's display name, for the log line and the badge. `Unit.name` is what
## `GambitBattle` prints and it is the only name this host is sure of.
func _name_of_unit(index: int) -> String:
	if _combat_loop == null or not is_instance_valid(_combat_loop) \
			or index < 0 or index >= _combat_loop.units.size():
		return "unit %d" % index
	var unit = _combat_loop.units[index]
	return str(unit.name) if unit != null and is_instance_valid(unit) else "unit %d" % index


## The director resumed. Driven off `resumed` and NOT off `turn_committed`, which would be the
## obvious pairing and is wrong: `TurnDirector.commit` emits `turn_committed` while the world is
## STILL frozen and then DRAINS — two units ready at one stop re-open without resuming at all — so
## a mirror on that signal goes live under an open turn once per double-ready stop. `resumed` is
## emitted from `_resume`, immediately after the loop's flag goes true, which is the event this
## mirrors.
func _on_director_resumed() -> void:
	_combat_active = true
	_set_survey_freeze(false)


## Go live on the battle handed off from the navigator (decision #180). Yields (via the loop's
## victory signal) on the runner's side. Command mode (ADR-0082): the roster-fed Deployment hold
## already built the frozen loop in run_pre_battle, so this just arms it live; a predetermined
## (Orbonne) or direct-seek battle skipped that, so build the frozen loop here first — then go live.
## "Leaving Deployment" and "un-pausing" both funnel through `_go_live`.
func run_combat(root: int) -> void:
	print("[NavigatorMain] run_combat root=%d" % root)
	# The world was booted + settled by the opener beat (linear walk) or by run_pre_battle's
	# deployment (which also ensures it). On a direct seek straight into combat, this boots
	# + fast-forwards the opener so the world settles through the real event instructions.
	await _ensure_battle_world(root)
	if not _battle_booted:
		await _build_frozen_combat_loop(root)
	# THE MAP CURSOR IS THE BATTLE'S, NOT PRE-BATTLE'S (ADR-0265). It used to be mounted only
	# by `run_pre_battle`, BELOW that function's `skip_pre_battle` early return — and that gate
	# is on in every seek and every autoplay path, which is to say in every way a human
	# actually reaches a battle here. So "play battle N" mounted no `CursorRig` at all and the
	# battlefield had no cursor on it: not a missing feature, a control-flow fact.
	#
	# Idempotent with the pre-battle call: the rig is built once and SEATED ONCE, with the
	# build, so the linear walk gets the same cursor it already had, standing where the player
	# left it. It used to be re-seated on the leader here, and once the pre-battle mount became
	# unconditional (`05dd65803`) that re-seat was a camera pan on every Space at deployment.
	# On a direct seek nothing has built a rig yet, so this call builds it and seats it.
	# AFTER `_ensure_battle_world`, because that is what settles the opener — and this forces
	# `camera_mode = CURSOR`, which under a live cinematic would wake the cursor beneath it.
	await _enter_command_cursor()
	_go_live()


## Ensure the battle world for `root` is booted + settled. In the linear walk the opener
## beat (or the pre-battle deployment) already did this, so this is a no-op; on a direct
## SEEK (into pre_battle or combat) the opener never PLAYED, so boot the world and fast-
## forward the group's opener cinematic (30×) so it settles through the real event
## instructions, exactly as the linear walk leaves it. Idempotent across pre_battle→combat
## within one battle (same `_battle_world_root`).
func _ensure_battle_world(root: int) -> void:
	if _battle_world_root != root:
		await _boot_world_for(root)
		_battle_world_root = root
		# Deploy BEFORE the opener is fast-forwarded, not after: the seek must settle the
		# world through the same instructions the linear walk does, and the opener's unit
		# sweeps only mean something with the squad already placed (see `play_beat`).
		await _ensure_owned_deployed(root)
		await _settle_world_via_opener(root)
		# RULE: every pre-battle scenario effect must be RESOLVED before combat starts. The
		# VM's time-driven ramps (fades, weather, overlays) advance one frame per tick
		# independently; a 30× seek can park with one still mid-flight. Snap them to their
		# committed end-state so the seek lands exactly where the walk does.
		#
		# 🔴 INSIDE THE SEEK BRANCH, and that is the second half of the READY!-fadeout
		# freeze (#1168). This used to run unconditionally, one line further out — which
		# put the SEEK's fast-forward guarantee on the ORDINARY LINEAR WALK, where nothing
		# was fast-forwarded and every one of those ramps is a real authored animation
		# still playing at 1×. What it snapped away was `{77}`'s 112-frame dark-screen
		# retract: the last 1.87 s of the battle intro vanished in a single frame, and the
		# battle build then landed on a fully revealed field with nothing over it.
		# `_battle_world_root != root` IS the seek predicate — `play_beat` stamps it when
		# the opener beat boots the world, so the walk never reaches this line and the
		# guarantee still covers every path that skipped the opener's real playback.
		if _vm != null and is_instance_valid(_vm) and _vm.has_method("settle_screen_effects"):
			_vm.settle_screen_effects()


## Replay the battle group's opener cinematic onto the freshly-booted world (fast-
## forwarded) so the pre-combat world state settles via real event instructions — a
## direct SEEK to combat skips the opener's normal-speed playback (see run_combat).
## Falls back to a bare fade reveal if the group carries no opener beat / it won't load.
func _settle_world_via_opener(root: int) -> void:
	var opener_sid := _opener_scenario_for(root)
	if opener_sid < 0:
		_reveal_for_combat()  # no pre-combat cinematic — at least make the world visible
		return
	print("[NavigatorMain] seek: fast-forwarding opener scn %d to settle the battle world" % opener_sid)
	var applier := ScenarioPathApplier.new(_vm, _play_member, get_tree())
	var loaded: bool = await applier.fast_forward_member(opener_sid)
	if not loaded:
		push_error("[NavigatorMain] seek: opener scn %d failed to load — revealing bare world" % opener_sid)
	# THE CAP IS THE FAILURE MODE THIS PATH HAS TO SAY OUT LOUD (ADR-0264). A truncated
	# fast-forward leaves the world on whichever `{19}` it reached — an authored pose, just
	# not the one the battle opens on — so it looks correct and is not. `fast_forward_member`
	# returns "the chunk loaded", which is true in exactly that case; the outcome is what
	# distinguishes settled from cut short.
	elif applier.last_ff_outcome != ScenarioPathApplier.FfOutcome.ENDED:
		push_error(("[NavigatorMain] seek: opener scn %d did NOT reach Event End (%s after %d "
			+ "frames) — the battle world is settled on an EARLIER camera/palette state")
			% [opener_sid, "hit the frame cap" if applier.last_ff_outcome == ScenarioPathApplier.FfOutcome.CAPPED
				else "stalled", applier.last_ff_frames])
	# The MARGIN, always — this line is the sweep's data channel
	# (`tools/sweep_opener_fast_forward.py`) and, on a live seek, the difference between
	# "settled with room to spare" and "settled on the last frame it had".
	print("[opener-ff] scn=%d outcome=%s frames=%d cap=%d" %
		[opener_sid, _FF_OUTCOME_NAMES[applier.last_ff_outcome], applier.last_ff_frames,
		ScenarioPathApplier._MAX_FF_FRAMES])
	# Snap the fade fully clear regardless: the opener's {Reveal} ends transparent, but its
	# timed fade ticker can still be mid-reveal when the opcode stream reaches end-of-script.
	# This guarantees the battle is visible WITHOUT touching the settled palette/camera.
	_reveal_for_combat()
	# Dismiss any opener dialogue box left up: at 30× fast-play the box's real-time dwell
	# timer doesn't elapse, so the fast-forward parks with the last line still shown —
	# combat must not inherit it.
	if _dialogue_overlay != null and is_instance_valid(_dialogue_overlay) and _dialogue_overlay.has_method("clear"):
		_dialogue_overlay.clear()


## [enum ScenarioPathApplier.FfOutcome] as words, for the `[opener-ff]` report line. An enum
## int in a log is a number a reader has to go look up.
const _FF_OUTCOME_NAMES := ["none", "ended", "stalled", "capped"]


## The opener cinematic's scenario id for a battle group (the pre-combat member that
## shapes the battle world), or -1 if the group has none.
func _opener_scenario_for(root: int) -> int:
	for b in _game_nav.beats_for_group(root):
		if String(b.get("role", "")) == "opener":
			return int(b.get("scenario_id", -1))
	return -1


## Clear the boot-time fade-to-black so the battle world is visible. A settle-time
## guarantee (see _settle_world_via_opener) matching the VM's settled-reveal end state
## (alpha 0); does not disturb the palette/camera the opener committed.
func _reveal_for_combat() -> void:
	if _fade_rect != null and is_instance_valid(_fade_rect):
		_fade_rect.color = Color(0, 0, 0, 0)


## Prime the fade fully BLACK — the symmetric partner to `_reveal_for_combat`. Called at
## the top of a cross-group re-boot so the teardown + map rebuild + spawn all happen under
## black (matching PSX load-under-black); the prior group may have left the fade revealed,
## so this must black it regardless of its current state. The incoming member's {Reveal}
## then fades the new world in. Null-safe (a re-boot can run before the rect is wired).
func _prime_fade_black() -> void:
	if _fade_rect != null and is_instance_valid(_fade_rect):
		_fade_rect.color = Color(0, 0, 0, 1)


## Ramp the inherited battlefield fade rect up to opaque black and return once it is
## there. Tweens from whatever alpha the last beat left it on, so a victory beat that
## already faded out costs no extra time. Null-safe and tree-safe: with no rect (or no
## tree) there is nothing to fade and the caller proceeds immediately.
##
## On the measured path this shows NOTHING — the group's own scene-out has already
## blacked the screen with a `{3E}` quad. Its work is the END STATE, not the ramp:
## [method run_world_map] frees that quad immediately after this returns (ADR-0162), so
## the rect is the only black left. See [constant WORLD_MAP_MOUNT_BLACK_SECONDS].
func _fade_battlefield_out() -> void:
	if _fade_rect == null or not is_instance_valid(_fade_rect) or not is_inside_tree():
		return
	if _fade_rect.color.a >= 1.0:
		return
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color:a", 1.0, WORLD_MAP_MOUNT_BLACK_SECONDS)
	await tween.finished


## Hold until the map's own screen-in ramp lands (ADR-0161). Replaces the cover tween
## this used to run: the ramp belongs to the screen now, so the navigator waits on it
## instead of driving it.
##
## [b]CHECK-then-await, and the order is the whole safety argument.[/b] `await` on a
## signal that has ALREADY fired never returns — which is §18.2's hang, reached here by
## the identical route the `dismissed` deferral below guards. [method
## WorldMapScene.advance] is the only thing that advances the ramp and it runs in
## `_process`, so nothing can land between the poll and the await inside one frame.
##
## Silently proceeds for a view that has neither member — a stub or a test double mounts
## and runs, exactly as it did when the cover was the navigator's.
func _await_screen_in(view: Node) -> void:
	if not view.has_method("screen_in_active") or not view.has_signal("screen_in_finished"):
		return
	if not view.screen_in_active():
		return
	await view.screen_in_finished


# === World lifecycle (persistent across a group, rebuilt across groups) =======

## Tear down the current world (VM + spawned units) and boot a fresh one for
## `scenario_id`'s scenario (map + ENTD spawn + VM wire), reusing the inherited
## `_boot_scenario_world()`. Groups change map/cast, so a full rebuild across groups
## is correct — the "no swap" persistence (decision #179) is scenario↔combat WITHIN a
## group, honored by keeping the same units across the opener/combat/victory beats.
func _boot_world_for(scenario_id: int) -> void:
	# Load under black: a cross-group re-boot rebuilds the world, and the 2+ render frames
	# inside `_boot_scenario_world` would otherwise flash the new world's DEFAULT camera —
	# a viewpoint the game never shows — because the prior group left the fade revealed.
	# Prime black FIRST (before teardown) so teardown + rebuild + spawn stay hidden until
	# the incoming member's {Reveal} fades in. (ScenarioPlayerScene also primes black, but
	# only after the build; this covers the whole transition, teardown frame included.)
	_prime_fade_black()
	# The eight compute stages, onto the device parked at `_ready` — HERE, because this is
	# a loading stall under a primed-black screen and the alternative is the frame the
	# battle intro's dark screen retracts over (#1168). Blocks; that is the point. See
	# `GPUBatchSimulator.prewarm_stages` for why it cannot ride the worker warm-up.
	GPUBatchSimulator.prewarm_stages()
	_teardown_world()
	# Route the resolver at this group root (its map + ENTD seed the world). The
	# inherited `_resolve_scenario` reads ScenarioDebugSession.selected_scenario_id.
	ScenarioDebugSession.selected_scenario_id = scenario_id
	_resolve_scenario()
	_hide_combat_ui()
	await _boot_scenario_world()


func _teardown_world() -> void:
	_combat_active = false
	# A world that is going away takes battle mode with it. Without this a cross-group re-boot
	# leaves a `"battle"` frame on the focus stack forever, with everything under it deaf and
	# nothing in the log to say so — the failure `Focus._on_root_exiting` guards against for a
	# freed root, which this host is not (it survives every teardown).
	_end_battle()
	_free_turn_queue_hud()
	_free_command_cursor()
	_free_deployed_owned()
	if is_instance_valid(_combat_loop):
		_combat_loop.queue_free()
	_combat_loop = null
	# The battle and its prewarm die with the loop: a fresh one has to build and boot again.
	_battle_booted = false
	_prewarmed_root = -1
	_pending_team0 = []
	_pending_team1 = []
	if _vm != null and is_instance_valid(_vm):
		_vm.queue_free()
	_vm = null
	for uid in _units_by_id.keys():
		var u = _units_by_id[uid]
		if is_instance_valid(u):
			u.queue_free()
	_units_by_id.clear()


## Play a linear group's members via the reused applier: intermediate members
## fast-forward, the terminal member plays at normal speed, and we yield on its
## `group_finished`. Mirrors ScenarioPlayerScene's path-mode boot.
func _play_group_members(root: int, beats: Array) -> void:
	var terminal_member := int(beats[beats.size() - 1].get("scenario_id", root)) if not beats.is_empty() else root
	var bc_id := ScenarioGroupDatabase.bc_id_for_scenario(root)
	var plan: Array = ScenarioPath.new().plan(bc_id, terminal_member)
	# A rewind resumed the walk onto this group — hand the clicked PC to the member it
	# belongs to. Mirrors ScenarioPlayerScene's own two boot shapes: the applier rewinds
	# its FINAL member, and a single-member group arms the VM right after `start()`.
	var rewind_pc := _take_pending_rewind_pc()
	if plan.is_empty():
		# Target IS the root (single-member group) — play it directly.
		if not _play_member(terminal_member):
			push_error("[NavigatorMain] failed to load member %d" % terminal_member)
			return
		_vm.start(false)
		if rewind_pc >= 0:
			_vm.set_rewind_target(rewind_pc)
	else:
		var applier := ScenarioPathApplier.new(_vm, _play_member, get_tree())
		await applier.walk(plan, bc_id, rewind_pc)
	# The terminal member is now playing; wait for its main-context Event End.
	await _vm.group_finished


## Park where the walk is NOW, so a click-to-rewind staged from the F3 VM panel resumes
## this walk instead of replanning from [constant START_ROOT]. Also the "a navigator walk
## is what you are looking at" flag [ScenarioVMDebugPanel] routes on.
##
## Called from the two executor entry points that put a scenario VM on screen — the only
## places a rewind can be clicked. [NavigatorRunner]'s `state_changed` would be the tidier
## hook, but `_set_state` only emits when the state CHANGES, so two consecutive scenario
## actions would publish once between them and the second would resume as the first.
func _publish_walk_position() -> void:
	if _nav_runner == null:
		return
	ScenarioDebugSession.navigator_resume_root = _walk_start_root
	ScenarioDebugSession.navigator_resume_stop_root = _walk_stop_root
	ScenarioDebugSession.navigator_resume_action = _nav_runner.current_action_index


## Take the pending click-to-rewind PC, clearing it so only the FIRST member replayed
## rewinds — the later members of a resumed group play through at normal speed.
func _take_pending_rewind_pc() -> int:
	var pc := _pending_rewind_pc
	_pending_rewind_pc = -1
	return pc


# === Debug read-seams =========================================================

## The current battle's roster→ENTD binding, for the F3 "Battle Binding" panel:
## { context:int, slots:Array, binding:SlugBinding, catalogue }. Empty {} when no
## battle world is booted yet (`_entd_record` still at its "256" default / unresolved).
## Loads the ENTD record fresh (mirrors `_build_frozen_combat_loop`); read-only inspection.
func debug_current_binding() -> Dictionary:
	if _binding == null or _entd_record == null:
		return {}
	var entd = _load_entd_record(_entd_record)
	if entd == null:
		return {}
	return {
		"context": int(_entd_record),
		"slots": entd.get("slots", []),
		"binding": _binding,
		"catalogue": CharacterCatalog,
	}


## The host half of the F3 "State" census ([StateDebugPanel], ADR-0177 Amendment 3).
##
## READ-ONLY, and every value is the flag ITSELF rather than anything derived from another one
## on this list. The panel's whole worth is the rows DISAGREEING — a `combat_active` false next
## to a `COMBAT`-owned clock census is ADR-0083 Amendment 1's defect made visible — so a seam
## that computed one entry from another would erase exactly what it exists to show.
##
## The panel reads the cursor rig, the Formation screen, the camera and the clock census off
## the live TREE and not from here, deliberately: a host that believes it freed the cursor is
## the last thing that can report a cursor still standing.
##
## `null` means "this mechanism is not standing right now" and is kept distinct from `false`.
func debug_battle_state() -> Dictionary:
	var director_up := _turn_director != null and is_instance_valid(_turn_director)
	var loop_up := _combat_loop != null and is_instance_valid(_combat_loop)
	var vm_up := _vm != null and is_instance_valid(_vm) and "survey_frozen" in _vm
	return {
		"host": "NavigatorMain",
		"has_runner": _nav_runner != null,
		"runner_state": _nav_runner.current_state if _nav_runner != null else -1,
		"runner_state_name": _game_state_name(_nav_runner.current_state) if _nav_runner != null else "",
		"combat_active": _combat_active,
		"pre_battle_active": _pre_battle_active,
		"survey_frozen": _vm.survey_frozen if vm_up else null,
		"director_state": _turn_director.state() if director_up else null,
		"director_state_name": TurnDirector.State.keys()[_turn_director.state()] if director_up else "",
		"director_taker": _turn_director.taker() if director_up else null,
		"director_stops": _turn_director.stops_the_world if director_up else null,
		"commandable_count": commandable_count(),
		"cast_size": _combat_loop.units.size() if loop_up else 0,
	}


## A [GameState] state value as its enum name, for the census row. The names live HERE and
## not on the panel because the panel is registered by the [DebugOverlay] autoload into every
## scene, and a `GameState.` / `TurnDirector.` reference on it would drag the walk's enum and
## the GPU packer into every scene's load closure — the "an autoload is a load-time reach"
## trap `tools/scoped_tests.py` prints about.
func _game_state_name(state: int) -> String:
	var names := GameState.State.keys()
	return String(names[state]) if state >= 0 and state < names.size() else "?%d" % state


# === ENTD battle bridge =======================================================

## Build the battle's CombatLoop from the ENTD on the already-booted world, FROZEN (ADR-0082 command
## mode). Split the spawned world units by `team_color` (Blue→team0, Red→team1), make each combat-ready
## (bind progression, job abilities, empty gambit list → encoder's attack-nearest safety net, logical
## tile), and BOOT a bare CombatLoop on the live world (decision #180, #182) with IDLE gambits —
## `combat_active` stays false. The real combat gambits are captured in `_pending_gambits`; `_go_live`
## arms them + flips the loop live when Tab leaves Deployment. Run on the roster-fed Deployment hold
## (run_pre_battle) or on a direct-seek into combat (run_combat) — the loop exists BEFORE go-live either way.
func _build_frozen_combat_loop(root: int) -> void:
	if _battle_booted:
		return
	if not await _build_battle_machinery(root, false):
		return
	# THE CAST'S POSITIONS ARE READ HERE AND NOWHERE ABOVE, which is the whole reason the
	# machinery above can be paid early: `boot_battle` loads each unit onto the GPU battle
	# buffer AT ITS TILE, so it is the one step that would bake a mid-opener position if it
	# ran before the opener's last opcode. Everything above it is shaped by the CAST (how
	# many bodies, which teams) and by the MAP, both of which are settled at world boot.
	await get_tree().process_frame
	_combat_loop.boot_battle(_pending_team0, _pending_team1, _map.lattice, _map, BATTLE_SEED)
	_battle_booted = true
	if _combat_loop.gpu_simulator == null:
		push_error("[NavigatorMain] boot_battle left no simulator — the frozen loop did not "
			+ "come up, and every step after this one is operating on a battle that is not "
			+ "there. See GPUBatchSimulator.initialize (#430 / #1168).")
	await get_tree().process_frame
	_mount_turn_director()
	print("[NavigatorMain] battle loop FROZEN (%d units, %d commandable) — command mode; Space to start"
		% [_pending_team0.size() + _pending_team1.size(), commandable_count()])
	_pending_team0 = []
	_pending_team1 = []


## The CAST-SHAPED half of the battle build: compose the teams, stand the [CombatLoop] up, and
## pay the two expensive GPU leaves (`setup_distance_field` ~13 ms, `setup_gpu_simulator` ~45 ms).
## Everything here is a function of WHO is in the battle and WHAT MAP it is on — never of where
## anybody is standing — so it can be paid at any point after the world boots. `_build_frozen_combat_loop`
## then adds the position-shaped half (`boot_battle`) at the normal time.
##
## Returns true when the machinery is up (or was already), false when it bailed.
##
## [b]`prewarm`[/b] — running ahead of the walk, under the battle intro's dark screen. The only
## difference is what a BAD battle does: the two error exits below hand the walk on
## (`on_combat_finished`), and doing that from under a playing cutscene would advance the walk out
## of the scene the player is watching. So a prewarm returns false and builds nothing, leaving the
## real call to reach the same exit at the moment the walk is actually there. (A composed-then-
## abandoned team leaks its ENTD spawns — accepted: it is reachable only on a battle that is about
## to end itself on the next line.)
func _build_battle_machinery(root: int, prewarm: bool) -> bool:
	if _combat_loop != null and is_instance_valid(_combat_loop):
		return true
	var entd = _load_entd_record(_entd_record)
	if entd == null:
		if prewarm:
			return false
		push_error("[NavigatorMain] ENTD record %s missing — cannot start battle" % _entd_record)
		# One of the two exits that BYPASS `_end_combat_and_advance` — they hand the walk on
		# directly, so the handback has to be here too or the claims Deployment took never come
		# back (ADR-0177 Amendment 3).
		_end_battle()
		_nav_runner.on_combat_finished(0)  # v1: treat as trivial player win so the walk continues
		return false
	# A predetermined cast (Orbonne) is a scripted-outcome battle (advance regardless); a
	# roster-fed one (Gariland) routes its real winner (#234 A/F).
	_battle_scripted_outcome = BattleDeployment.is_predetermined(entd)

	# Combatant roster: only units ACTUALLY on the field and meant to fight. The three
	# exclusions and their reasons live on [EntdBattle.combatant_slots] — the arena
	# composes the same battle and needs the same answer.
	var battle_slots: Array = EntdBattle.combatant_slots(entd)

	# Composition (wayfinder #234 A2): team0 = deployed owned  ∪  ENTD-blue; team1 =
	# ENTD-non-blue. The deployed owned units lead team0 (Orbonne = none → the baked
	# ENTD-blue cast unchanged; Gariland = {Ramza + 4 generics} ∪ {Delita, blue guest}
	# vs {5 red generics}). `EntdBattle.compose_teams` owns the partition + ordering; the
	# per-side spawn transforms combat-ready the ENTD-blue (Delita) / ENTD-red slots into
	# live units, while the already-placed deployed owned units pass through untouched.
	var teams := EntdBattle.compose_teams(
		_deployed_owned, battle_slots,
		func(slots: Array) -> Array: return _combat_ready_team(slots, UnitStats.Team.PLAYER),
		func(slots: Array) -> Array: return _combat_ready_team(slots, UnitStats.Team.ENEMY))
	var team0: Array = teams["team0"]
	var team1: Array = teams["team1"]
	# Proof mode (same tunable that made the owned team invincible): drop the enemy HP to 1
	# so a landed hit is lethal, guaranteeing a REAL decisive victory (winner==0, team1
	# defeated) well inside max_ticks — otherwise the invincible-but-low-damage owned team
	# just grinds peers past the tick cap into an inconclusive timeout. Deterministic proof,
	# not a gameplay path; only the deployed-owned side exists at Gariland so this is safe.
	if _autoplay_gate(OWNED_INVINCIBLE_SLUG):
		for u in team1:
			if is_instance_valid(u) and u.unit_stats != null:
				u.unit_stats.max_hp = 1
				u.unit_stats.current_hp = 1
	print("[NavigatorMain] teams: team0(owned+Blue)=%d (%d owned deployed) team1(Red)=%d (catalog-bound, %d slot(s) fell back to ENTD)" %
		[team0.size(), _deployed_owned.size(), team1.size(), _binding.fallback_count()])

	if team0.is_empty() or team1.is_empty():
		if prewarm:
			return false
		push_warning("[NavigatorMain] a team is empty (t0=%d t1=%d) — skipping combat, treating as win" %
			[team0.size(), team1.size()])
		_end_battle()   # the second bypass exit — see the note on the first
		_nav_runner.on_combat_finished(0)
		return false

	# GPU capacity: the sim splits teams at units_per_battle/2, and CombatLoop indexes
	# `team0 + team1` contiguously — so team0 MUST land exactly in [0, ups/2). Size the
	# battle to 2×team0 (Orbonne: 9 Blue → 18, team1=7 fits in the second half). Needs
	# team1 ≤ team0; warn (don't silently mis-slot) if a future ENTD violates that.
	if team1.size() > team0.size():
		push_warning("[NavigatorMain] team1(%d) > team0(%d) — GPU team split may mis-slot; capping"
			% [team1.size(), team0.size()])
	var per_battle := 2 * maxi(team0.size(), team1.size())

	# ADR-0192 dec. 3's clean fetch: ONE untyped step at the seam, `Lattice`-typed from
	# here on. This line used to read `var terrain: TerrainIndex = _map.terrain_index`
	# — the handle acquisition, a spelling of the door no call-site scan could see.
	var lattice: Lattice = _map.lattice
	# Name the battle by its group root (Orbonne = 3, Gariland = 9) instead of hardcoding
	# Orbonne — the seam is generalized across battles now.
	var battle_label := "Orbonne" if root == 3 else "Battle-%d" % root
	_combat_loop = CombatLoop.new()
	_combat_loop.name = "CombatLoop"
	_combat_loop.battle_name = battle_label
	_combat_loop.units_per_battle = per_battle
	_combat_loop.lattice = lattice
	_combat_loop.map = _map
	_combat_loop.player_camera = _player_camera
	# Post-battle pose: faithful HP-appropriate return-to-normal by default; the
	# NavigatorDebugPanel can opt into the made-up victory dance (ADR-0026).
	_combat_loop.celebrate_on_victory = ScenarioDebugSession.navigator_celebrate_on_victory
	# LET THEM FINISH BEFORE THE WALK MOVES ON. The walk's exit from a battle is the
	# most expensive one in the tree — the handback frees the cursor and returns the
	# camera, then a whole authored victory beat plays on the same live world — so a
	# unit cut off mid-step is cut off in front of the player and stays wrong for the
	# beat's whole opening. `settle_before_victory` holds the kernel's win report until
	# nobody is mid-anything, which delays `victory` and therefore delays the entire
	# handback with it, with no gate on this side at all. See the member's own note;
	# it is off everywhere it is not asked for.
	_combat_loop.settle_before_victory = true
	# The apply pump + managers (e.g. ProjectileManager) log through `_rlog`
	# UNGUARDED — a disabled logger responds to every log_* call without writing.
	_combat_loop._rlog = RegressionLogger.new(battle_label, false)
	add_child(_combat_loop)
	_combat_loop.victory.connect(_on_combat_victory)
	# A stalemated auto-battle (no decisive victory within max_ticks) must ADVANCE the
	# walk, not deadlock it. v1: a timeout is treated as an (inconclusive) player win so
	# the victory beat + chain still play — combat balance/positioning is a follow-up.
	_combat_loop.timed_out.connect(_on_combat_timed_out)
	# The over-unit feedback billboards (ADR-0063), the fifth per-host presentation mount
	# beside TurnBeat / StopBadge / TurnQueueHud / CursorRig (ADR-0265 dec. 2). It parents
	# under the loop, so it is freed with the loop and re-mounted with the next one.
	FeedbackHudManager.mount(_combat_loop)

	# BOOT frozen (ADR-0082): load the units into the GPU battle buffer on their tiles with IDLE
	# (empty) gambits and leave `combat_active` false — the loop exists but the sim does not tick.
	# `boot_battle` is the "boot" half of the ADR-0042 start_battle split; `_go_live` arms the
	# captured combat gambits + flips the flag when Tab leaves Deployment.
	_pending_gambits = _build_encoded_gambits(team0 + team1)
	# NOTHING IS RESOLVED HERE ANY MORE. Who you may steer is a fact on each unit, written
	# by whichever of the two writers put it on the field (`Unit.commandable`), so there is
	# no set to build and none to invalidate — a unit added mid-battle arrives carrying its
	# own answer. This used to be `_commandable[i] = true for i where _deployed_owned.has(...)`,
	# which is provenance, and a predetermined battle deploys nobody (ADR-0265 Amendment 1).
	# ONE FRAME'S WORTH PER FRAME, and that is the third part of the READY!-fadeout fix
	# (#1168). Everything from here to the seated cursor used to run inside a single
	# `_process` call at the end of the battle intro — 469-1597 ms of device, buffers,
	# distance field and node mounts on ONE frame, which is the freeze the player reported.
	# `_ensure_battle_world` above already awaits, so this function was always allowed to;
	# it simply never did. The yields are placed at the boundaries between the EXPENSIVE
	# leaves the trace named, not sprinkled: the GPU boot, the director mount, and (in
	# `_enter_command_cursor`) the Formation screen's 61-116 ms mount.
	#
	# ⚠️ A GDScript runtime error inside an awaited call returns the TYPE DEFAULT silently,
	# so a broken chunk here reads as a fast frame rather than as a red. The loop's own
	# arrival is asserted below rather than assumed.
	# `boot_battle` would do these two itself (it no-ops when `gpu_simulator` is already
	# up), and together they are 88 ms on one frame — the distance field 15-40 ms, the GPU
	# simulator's stage build + buffers the rest. Driven from here so a yield can sit
	# between them; the call below then finds a live simulator and skips straight to the
	# unit wiring.
	await get_tree().process_frame
	_combat_loop.setup_distance_field()
	await get_tree().process_frame
	_combat_loop.setup_gpu_simulator()
	# The cast this battle will boot with, held for the position-shaped half. Composing is not
	# free (it spawns the ENTD side) and composing twice would spawn it twice.
	_pending_team0 = team0
	_pending_team1 = team1
	return true


## Design S11, and the whole of it: mount the turn director on the bare loop, and the
## forecast strip on the camera. Two lines and no host change — which is the CLAIM #898
## exists to check, since `NavigatorMain` runs a bare [CombatLoop] and extends no
## `CombatHost`, so anything the director had taken from its host would have to be built
## again here.
##
## Mounted at BUILD and not at go-live, because the director's reach is the loop's
## simulator and `boot_battle` (above) is what creates it; the gate it installs cannot fire
## before the walk goes live in any case, since `_process` does not pump a frozen loop.
##
## The walk's stop policy DEFAULTS to the non-stopping one
## ([member TurnDirector.stops_the_world] false): nobody is playing this battle. Its turns
## are announced and spent where they open, which costs the walk no ticks and gives the
## strip a queue that MOVES — with nothing spending turns the kernel stops advancing a
## crossed meter, every living unit stays ready, and the forecast reads "everyone, now"
## forever.
##
## [constant STOP_ON_TURN_SLUG] opts out of that, and the read is HERE rather than per-turn
## because a policy that changed under a battle would change it under an open turn. Scrub
## the toggle and the next battle takes it; the one you are in keeps the policy it mounted
## with. The signal pair is connected only when the stop is armed — hands-off, `turn_opened`
## fires once per spent turn from `_spend_where_it_opens` and a mirror handler on it would
## be a per-turn write of a flag nothing froze.
func _mount_turn_director() -> void:
	if _combat_loop == null or not is_instance_valid(_combat_loop):
		return
	_turn_director = TurnDirector.mount(_combat_loop)
	_turn_director.stops_the_world = stop_on_turn_armed()
	# CONNECTED UNCONDITIONALLY, and that is the change. These three lines used to sit inside
	# `if _turn_director.stops_the_world`, which makes the WIRING a mount-time bet on a flag
	# that is a plain `var` with a setter — and a director whose policy became true after the
	# mount would freeze the loop with nothing following it, which is precisely the
	# `_combat_active` disagreement this host's mirror exists to prevent.
	#
	# What made the gate necessary was the handler ASSUMING the freeze. `_on_director_turn_opened`
	# now FOLLOWS `CombatLoop.combat_active` and returns immediately when the world is still
	# running — which is every `turn_opened` a hands-off walk emits, once per turn spent where it
	# opens — so the unattended walks read exactly as they did, with no per-turn write of a flag
	# nothing froze and no per-turn line in their logs.
	#
	# `turn_committed` was already the odd one out here for the same reason: it is the edge that
	# must fire whatever ended the turn — the marker comes off and the cursor gets its ears back
	# on a commit that landed inside its own travel just as much as on one that waited for it
	# (`GambitBattle._on_turn_committed` carries the same two lines for the same reason).
	_turn_director.turn_opened.connect(_on_director_turn_opened)
	_turn_director.resumed.connect(_on_director_resumed)
	_turn_director.turn_committed.connect(_on_director_turn_committed)
	if _turn_director.stops_the_world:
		print("[NavigatorMain] TURN STOP armed (%s) — the battle stops on YOUR turns, Space spends one"
			% STOP_ON_TURN_SLUG)

	# The camera seat CombatUI and the dialogue boxes already use (camera-local, z=-10 by
	# the host's own placement). Absent in a rig that boots no camera, which is a real
	# state and not an error: the director is the battle machinery, the strip is a view of
	# it, and the walk runs with or without the view.
	var cam := _player_camera.get_node_or_null("FocusPoint/Camera") if _player_camera != null else null
	if cam == null:
		return
	_turn_queue_hud = TurnQueueHud.mount(cam, _turn_director)
	# The cast the forecast indexes into. Bound HERE, at boot, and not at go-live: the
	# loop's units are what `boot_battle` just loaded, and the strip stays hidden through
	# the frozen stretch on its own (an unbooted battle forecasts nothing).
	_turn_queue_hud.bind_units(_combat_loop.units)


## Free the forecast strip. The director needs no counterpart — it is a child of the loop
## and dies with it — but the strip rides the CAMERA, which outlives every battle in the
## walk, so a strip left behind would draw the last battle's queue over the next map.
func _free_turn_queue_hud() -> void:
	if is_instance_valid(_turn_queue_hud):
		_turn_queue_hud.queue_free()
	_turn_queue_hud = null
	_turn_director = null
	# The battle's turn surface goes with the battle. The marker is a child of a unit that is
	# about to be freed, so this is belt-and-braces on the sprite and load-bearing on the two
	# INDICES: a `marker_unit` / `beat_taker` carried into the next battle names a unit in a
	# cast that no longer exists. Commandability needs no line here: it rides each unit and
	# dies with it, which is the point of moving it there.
	_beat.hide_marker()
	_beat.end()
	_beat.beat_taker = -1
	_beat.units = []


## Go live on the frozen loop (ADR-0082): arm the captured combat gambits (IDLE→combat swap), hand the
## loaded cast's clocks off to the CombatLoop, and flip both the loop's own tick gate (`combat_active`)
## and our mirror. The Deployment→Live half of the Tab toggle; a mid-battle pause/resume leaves gambits
## armed and only re-flips the flag (`_set_combat_live`). No-op if no loop was built (empty-team battle).
func _go_live() -> void:
	if _combat_loop == null or not is_instance_valid(_combat_loop):
		return
	_combat_loop.arm_combat_gambits(_refresh_pending_gambits())
	# THE ownership handoff (ADR-0083): every loaded battle body was SCENARIO-owned (VM idle-breathe
	# through Deployment); the instant CombatLoop takes over, flip the whole cast SCENARIO→COMBAT so the
	# CombatLoop tick becomes their SOLE clock. The VM's `_advance_scenario_anim` pump then skips them
	# (owner filter), so no double-drive races the SEQ 0xDE hit-cloud opcode past the GPU damage tick.
	# This single edge replaces the old scattered `battle_frozen` writes.
	_hand_off_clocks_to_combat()
	_combat_loop.combat_active = true
	_combat_active = true
	# Live: no survey freeze (ambient SCENARIO NPCs may breathe; combat bodies are frozen structurally
	# by ownership, not by this flag). A subsequent Live→Paused sets it; Deployment never does.
	_set_survey_freeze(false)
	print("[NavigatorMain] battle LIVE (%d units)" % _combat_loop.units.size())
	# The cast that just went live IS the armed cast, so the re-arm below must not fire again on
	# this same transition. Clearing it here (rather than letting `_process` catch a transition it
	# did not cause) keeps the first arm and every later one to ONE writer.
	_gambits_dirty = false


## The encoded gambits to arm, taken from the cast AS IT STANDS NOW (see [member _pending_gambits]).
##
## Reads `_combat_loop.units` and not `team0 + team1`, because that array is exactly what
## [method CombatLoop.arm_combat_gambits] indexes — encoding from the same array the arm walks is
## what makes the two orders impossible to disagree about.
func _refresh_pending_gambits() -> Array:
	if _combat_loop == null or not is_instance_valid(_combat_loop) \
			or _combat_loop.units.is_empty():
		return _pending_gambits   # bare-construct rigs seed the array and own no cast
	_pending_gambits = _build_encoded_gambits(_combat_loop.units)
	return _pending_gambits


## THE PLAYER'S UNITS RUN THE RULES THE PLAYER AUTHORED — re-armed every time this host
## un-freezes the battlefield, which is the one rule that covers every way an edit can be made.
##
## [b]Why one bit and not a call at each door.[/b] A gambit edit on this host can be
## made in four states, and they do not share a call site: at the DEPLOYMENT park; with the battle
## live and no turn open (the formation screen freezes the sim while it is up — `_set_screen_pause`
## — so every edit is made inside a freeze); on an open turn the stop is holding
## (`navigator.stop_on_turn`); and under the Esc pause. What they DO share is the moment they end:
## the sim starts running again. So the question "has the player edited anything?" is answered once,
## at the only edge where the answer can matter, instead of at four doors that would each have to
## remember to ask — and a fifth door added later inherits the rule for free.
##
## [b]Why only the commandable units.[/b] They are exactly the set the player can edit, so a wider
## sweep would buy nothing and would cost the enemy its plan the moment this host grows the rollout
## driver `GambitBattle` already has (`RolloutDriver` writes its candidate rows straight into this
## same buffer). Scoping it to the player's units makes that collision unreachable by construction.
##
## [b]No imperative lead.[/b] `encode_for_unit(unit)` is called without one deliberately — the
## imperative ledger (#1006) is `GambitBattle`'s and this host has none. When it grows one, the
## lead belongs here, on the same call.
func _rearm_player_gambits() -> void:
	if _combat_loop == null or not is_instance_valid(_combat_loop):
		return
	var sim = _combat_loop.gpu_simulator
	if sim == null:
		return
	var battle_id: int = _turn_director.battle_id if _turn_director != null \
		and is_instance_valid(_turn_director) else 0
	for i in range(_combat_loop.units.size()):
		if not is_commandable(i):
			continue
		sim.set_unit_gambits(battle_id, i, GambitEncoder.encode_for_unit(_combat_loop.units[i]))


## Re-arm the player's gambits on the first frame the battlefield is running again after any
## freeze. Called from `_process`, above the live gate, because on some of the paths that resume
## the sim `_combat_active` is still the old value on this frame — the director writes the loop's
## flag itself and this host mirrors it a call later.
##
## The freeze is recorded by two writers and that is deliberate. [method _set_combat_live] marks it
## SYNCHRONOUSLY, so a screen that opens and closes without a frame in between is still caught; the
## first branch below marks it for the freezes this host does not own, which is every one the
## [TurnDirector] takes by writing `combat_active` straight onto the loop.
func _rearm_gambits_if_unfroze() -> void:
	if _combat_loop == null or not is_instance_valid(_combat_loop):
		return
	if not bool(_combat_loop.combat_active):
		_gambits_dirty = true
		return
	if not _gambits_dirty:
		return
	_gambits_dirty = false
	_rearm_player_gambits()


## ENTER BATTLE MODE (ADR-0177 Amendment 3). Idempotent — the cursor is re-entered at
## Deployment and again as combat opens, and only the first of those enters the mode.
##
## Pushes the `"battle"` Focus state so the stack SAYS the battlefield is up, which decision 3
## says registration exists for and which the battlefield never did in either host: this one
## pushed only `"formation"`, and `GambitBattle` pushes `"gambit_battle"` and never pops. It
## also records the camera mode the battle is about to take, because a claim you cannot name
## the previous value of is a claim you cannot return.
func _enter_battle_mode() -> void:
	if _battle_mode:
		return
	_battle_mode = true
	if _player_camera != null and is_instance_valid(_player_camera) and "camera_mode" in _player_camera:
		_camera_mode_before_battle = int(_player_camera.camera_mode)
	if is_inside_tree():
		Focus.push("battle", self)
	print("[NavigatorMain] BATTLE MODE — %s" % Focus.describe(Focus.CHANNEL_GAME))


## THE HANDBACK — the edge that LEAVES battle mode, and the counterpart `_go_live` never had
## (ADR-0177 Amendment 3). Every one of the four Orbonne reports was a claim taken on entry and
## not returned, and they were four bugs rather than one only because there was no named place
## to return them from.
##
## Four returns, in an order that matters exactly once: the clocks are flipped BEFORE the
## cursor is freed, because freeing the rig can take the camera with it and a body whose clock
## is still COMBAT-owned after the CombatLoop is gone is animated by nothing at all
## (ADR-0083 Amendment 1 — the survivors "teleport" through scenario 6).
##
## [b]NOT a teardown.[/b] The world SURVIVES a handback — the victory beat plays on the live
## battlefield — which is why this frees the battle's claims and touches neither the units nor
## the map. `_teardown_world` is the other thing, and it calls this first.
##
## Idempotent, and safe to call from an exit that never entered: a battle abandoned before its
## cursor was mounted holds no claims and this is a no-op on it.
func _end_battle() -> void:
	if not _battle_mode:
		return
	_battle_mode = false
	_hand_off_clocks_to_scenario()
	_free_command_cursor()
	_return_camera()
	if Focus.holds(self):
		Focus.pop(self)
	print("[NavigatorMain] HANDBACK — battle mode left; %s" % Focus.describe(Focus.CHANNEL_GAME))


## The battle→scenario clock handback (ADR-0083 Amendment 1): give every COMBAT-owned body back
## to the ScenarioVM pump. The explicit, symmetric mirror of [method _hand_off_clocks_to_combat].
##
## Decision 2's parenthetical — "teardown frees the units (implicit revert)" — is false on the
## victory beat, which plays on the SAME live world: the units are not freed, so every survivor
## stayed COMBAT-owned with no `CombatLoop` left to tick it and `_advance_scenario_anim` skipped
## it by design. Scenario 6 then moved the survivors and nothing animated the move. They
## teleported. `play_beat` already carried `preserve_combat_poses` for that beat, so the POSE
## half of the carry had been thought about and the CLOCK half had not.
##
## Reads `_units_by_id` and not `_combat_loop.units`, deliberately: the registry is what the VM
## pumps, it survives the loop being freed, and it is the population the claim is actually about.
func _hand_off_clocks_to_scenario() -> void:
	var handed := 0
	for unit in _units_by_id.values():
		if unit == null or not is_instance_valid(unit) or not ("clock_owner" in unit):
			continue
		if unit.clock_owner != ClockOwner.COMBAT:
			continue
		unit.clock_owner = ClockOwner.SCENARIO
		handed += 1
	for unit in _deployed_owned:
		if unit != null and is_instance_valid(unit) and "clock_owner" in unit \
				and unit.clock_owner == ClockOwner.COMBAT:
			unit.clock_owner = ClockOwner.SCENARIO
			handed += 1
	if handed > 0:
		print("[NavigatorMain] clocks handed back COMBAT→SCENARIO — %d body(s)" % handed)


## Give [member PlayerCamera.camera_mode] back to whatever held it before battle mode forced
## CURSOR. Only when the battle's own claim is still standing: a cinematic that took the camera
## over during the fight owns it now, and a handback that overwrote that would be the same
## defect in the other direction.
func _return_camera() -> void:
	var claimed := _camera_mode_before_battle
	_camera_mode_before_battle = -1
	if claimed < 0 or _player_camera == null or not is_instance_valid(_player_camera):
		return
	if not ("camera_mode" in _player_camera):
		return
	if _player_camera.camera_mode != _player_camera.CameraMode.CURSOR:
		return
	# Through the rig's edge, never by assignment. A bare `camera_mode = TAKEOVER` drops the
	# framing datum to zero in ONE frame — 40 of 240 native px — and on the victory beat the
	# next authored `{19}` is 1.49 s away, so the whole image jumps with nothing else moving.
	# `enter_takeover_framing` folds the datum into the body first, leaving the Camera3D's
	# world position bit-identical across the flip.
	if claimed == int(_player_camera.CameraMode.TAKEOVER):
		_player_camera.enter_takeover_framing()


## The scenario→battle clock handoff (ADR-0083): claim every CombatLoop unit for COMBAT so its body
## rides only the CombatLoop tick. Idempotent; safe across a Pause/resume (already COMBAT). No-op
## without a loop. Units too raw to own a clock (no `display` yet) no-op their setter, same as before.
func _hand_off_clocks_to_combat() -> void:
	if _combat_loop == null or not is_instance_valid(_combat_loop):
		return
	for unit in _combat_loop.units:
		if is_instance_valid(unit) and "clock_owner" in unit:
			unit.clock_owner = ClockOwner.COMBAT


## Toggle the command-mode Pause survey freeze on the VM (ADR-0083): halts the SCENARIO-owned ambient
## body pump so a paused battlefield is a full freeze-frame. NOT the double-pump guard — that is per-unit
## `clock_owner`. Set true on Live→Paused, false on Paused→Live and at go-live. No-op without a VM.
func _set_survey_freeze(frozen: bool) -> void:
	if _vm != null and is_instance_valid(_vm) and "survey_frozen" in _vm:
		_vm.survey_frozen = frozen


## Stand up the COMMAND-MODE roam cursor (ADR-0082) at Deployment entry, seeded on the leader (first
## deployed owned unit) so the handoff never lands on world-origin. Asks the addon for a cursor via
## `CursorRig.mount()`, a sibling of ProceduralMap / PlayerCamera (the paths the cursor's `_ready`
## resolves). What the rig builds behind that call is the addon's business (ADR-0206). Forces the camera
## into CURSOR mode so the dagger is visible + drivable (a scenario opener may have left a TAKEOVER).
## Idempotent: builds the rig once, and SEATS IT ONCE — with the build (see below). No-op if
## nothing was deployed.
func _enter_command_cursor() -> void:
	var leader = _cursor_seed_unit()
	if leader == null:
		return
	var leader_cell: Vector3i = leader.get_current_cell()
	if leader_cell == TerrainCell.NONE:
		return
	if not await _build_command_surface():
		return
	# BATTLE MODE IS ENTERED HERE — at the point the first two claims are actually taken, not
	# at a line that merely announces the intention to take them (ADR-0177 Amendment 3).
	_enter_battle_mode()
	# Command mode is a FREE camera on the cursor: force CURSOR mode so the dagger shows + drives the
	# camera (the opener cinematic may have left the camera in TAKEOVER). Through the rig's edge,
	# never by assignment: `resume_cursor_framing` eases the framing datum in over
	# `camera.handoff_ease_seconds` of WALL CLOCK instead of stepping it — the same curve, clock
	# and length as the seat's own glide two lines below, so the entry is ONE motion (#1189; it
	# was its own 16-FRAME counter, which only read alike while the glide was also ~18 frames) —
	# and re-syncs `x_target_rot`/`y_target_rot` from the pose the opener
	# actually left the rig holding — otherwise the targets stay whatever they were before the
	# opener took over and the first Q/E in battle steps from a yaw nobody is looking at. It is
	# EDGE-ONLY, which matters because this function runs twice per battle (see below).
	if _player_camera != null and _player_camera.has_method("resume_cursor_framing"):
		_player_camera.resume_cursor_framing()
	# 🔴 THE SEAT BELONGS TO THE BUILD. This was unconditional, and ADR-0265 dec. 1 said so on
	# purpose — *"the rig is built once and re-seeded, so the linear walk gets the same cursor
	# it already had, re-seated on the leader as combat opens."* That was harmless only while
	# pre-battle mounted no cursor on most paths. `05dd65803` made the pre-battle mount
	# UNCONDITIONAL, and from that commit on this function runs twice on every battle: once
	# from `run_pre_battle` and again from `run_combat`. The second call re-seated the cursor
	# on the leader, `CursorController._on_cursor_moved` forwarded that to
	# `PlayerCamera.track_cursor`, and the camera panned — press Space at deployment, having
	# walked the cursor somewhere you chose, and the battlefield slides back to the leader.
	#
	# So the seat is a property of BUILDING the rig, not of entering command mode. The
	# direct-seek path still seats: there the rig is null at `run_combat`, so that call builds
	# it AND seats it. The linear walk keeps the cursor where the player left it.
	#
	# Not a parameter on this function (there is one true call shape and two callers, so a flag
	# would only move the decision to the callers) and not "accept the pan" — the pan is the
	# report. `GambitBattle` seeds once, at its own mount, and never again, which is why the
	# user does not see this there.
	#
	# The seat runs HERE rather than inside the `if` above so its ordering is untouched: it
	# still follows `_enter_battle_mode()` and the CURSOR camera_mode, and it still follows
	# `_mount_formation_map_screen()`, whose `bind_map` reads the rig's position at bind time.
	# Only the SECOND entry changed.
	#
	# The cursor seats on a COLUMN and picks the ground of it (`CursorController.seed_from_map`),
	# so the leader's level is dropped deliberately here rather than by omission (#795).
	#
	# AND IT EASES RATHER THAN CUTS (#1168). Every other host seeds a cursor onto a bare
	# scene, where the hard cut IS the right move — there is no prior framing to keep. This
	# one seeds at the end of a battle intro, onto a camera scn 10's `{19}` (pc 33, under
	# the dim) deliberately posed as the battle's opening shot. Snapping there is the
	# "jerks into position on to the first unit" half of the report: 6.6425 units in zero
	# frames, on the frame the dark screen finished retracting, every run.
	#
	# ...AND THE GLIDE NEEDED ITS OWN CLOCK AND LENGTH (#1189). Easing fixed the teleport and
	# the report MOVED rather than went away. `ease_onto` had borrowed `follow_ease_frames`,
	# which is neither: 18 FRAMES is a single-TILE step, this is 6.699 units, and a frame
	# counter is armed HERE — one frame after `_mount_formation_map_screen`'s ~60 ms. The
	# swapchain has drained, so the next three frames render in 2-3 ms each and the glide
	# burns five of eighteen steps in 37 ms. It now runs on `camera.handoff_ease_seconds` of
	# wall clock (0.80, the ROM's own `Time=48` on the victory beat's `{19}` — the move the
	# report named as the good one). The ORDERING here is deliberate and unchanged: the two
	# build hitches land on a static field one frame BEFORE the glide, where a frozen frame
	# is invisible, rather than inside it where it would be judder.
	if not _command_surface_seated:
		_command_surface_seated = true
		_cursor_rig.seed_from_map(_map, Vector2i(leader_cell.x, leader_cell.y), false)


## THE CURSOR SURFACE, and nothing that moves the camera: mount the [CursorRig] (~2 ms) and the
## formation map screen (~56 ms — the single most expensive leaf left on this beat once the GPU
## device moved to the host's `_ready`, #1168). Both are shaped by the MAP and the CAST, not by
## where anybody is standing or where the camera is looking, so they can be paid early — which is
## what `_prewarm_battle_under_the_dark` does with them. Everything in `_enter_command_cursor`
## BELOW this call is the camera's: battle mode, CURSOR framing, and the seat.
##
## Idempotent on `_cursor_rig`; returns false only when the rig could not be mounted.
func _build_command_surface() -> bool:
	if _cursor_rig != null and is_instance_valid(_cursor_rig):
		return true
	# The exported NodePaths resolve in the cursor's `_ready` relative to its parent
	# (self), so ProceduralMap / PlayerCamera are "../ProceduralMap" /
	# "../PlayerCamera" -- exactly how GPUArena.tscn wires its $TileCursor. `mount()`
	# sets them BEFORE add_child so `_ready` reads them, and owns what it built.
	_cursor_rig = CursorRig.mount(self, _player_camera,
		NodePath("../ProceduralMap"), NodePath("../PlayerCamera"))
	if _cursor_rig == null:
		push_warning("[NavigatorMain] command cursor: CursorRig.mount failed")
		return false
	# #589: the cursor's player-driven step is an `Audio` cue, and the cue name
	# is host vocabulary (`OpeningMenu` plays the same one). Wired by the root
	# that OWNS the node -- a cursor handed onward (FormationMapHost.bind_map)
	# is already wired by its owner.
	BattlefieldWiring.wire_cursor(_cursor_rig)
	await get_tree().process_frame
	_mount_formation_map_screen()
	# The screen's mount and the battle-mode entry + camera seat are ~35 ms each — one frame's
	# budget apiece, so they get one frame apiece (#1168).
	await get_tree().process_frame
	return true


## Where the cursor starts: the LEADER — the first deployed owned unit.
##
## The fallback is not defensive padding. A PREDETERMINED battle (Orbonne) deploys no owned
## units at all, and the old `if _deployed_owned.is_empty(): return` meant that battle had no
## cursor on any path, including the one where pre-battle was not skipped. A battlefield you
## cannot point at is the same defect whether the cast came from the roster or the ENTD, so
## the seat falls back to the first unit of the booted cast, which is team0's first.
func _cursor_seed_unit():
	for unit in _deployed_owned:
		if unit != null and is_instance_valid(unit):
			return unit
	if _combat_loop != null and is_instance_valid(_combat_loop):
		for unit in _combat_loop.units:
			if unit != null and is_instance_valid(unit):
				return unit
	return null


## Mount the map-hosted Formation screen over this battlefield (ADR-0137) — the IN-battle half of
## the two-host dispatch. The out-of-battle half is `run_formation_view` above, which stays live
## permanently: neither replaces the other, and which one you get is decided by where you are.
##
## Built with the cursor rig, freed with it: the screen's whole selection model is the tile cursor,
## so it has no meaning without one.
func _mount_formation_map_screen() -> void:
	_formation_map_screen = FormationDetailTransitionScript.mount_over_map(
		_player_camera, _cursor_rig, _unit_at_grid,
		_set_screen_pause,
		func() -> bool: return _combat_loop != null)
	# The ROW SET, armed AT MOUNT and never re-armed — `mount_over_map` does not set it, and an
	# empty `action_rows` makes `FormationDetailTransition._row_label` fall back to the ROM's five,
	# whose row 3 is "Remove Unit". That row is not in `MENU_LABEL_STATE`, so Tab -> row 3 -> ○ went
	# through `_dispatch_menu_row`'s `return false` and did NOTHING, silently: this host had no
	# gambit door at all while `GambitBattle` (which arms the rows itself) had a working one, and
	# every test that mounts this screen runs on that host.
	#
	# At MOUNT and not at the first turn, for `GambitBattle.gd`'s reason verbatim: the screen is
	# reachable in every phase, and a menu that grew a "Gambit" row only once a turn opened would be
	# a different screen depending on when you looked at it. No restore site is needed beside it the
	# way `GambitBattle._end_pick` needs one — this host runs no `State.PICK`, so nothing ever swaps
	# the set out from under it.
	_formation_map_screen.action_rows = StartActionMenuScript.ROWS_ADJUST


## What the screen was interrupting, so closing it can put that back.
var _combat_active_before_screen := false


## The screen's pause hook. RESTORES the prior state rather than forcing the battle live on close.
## This host parks in Deployment (`combat_active` false) before the player presses Space, so a
## close that forced `_set_combat_live(true)` would start the fight because someone looked at a
## unit — and would also un-pause a battle the player had deliberately paused (ADR-0137 Am. 2).
func _set_screen_pause(paused: bool) -> void:
	if paused:
		_combat_active_before_screen = _combat_active
		_set_combat_live(false)
	else:
		_set_combat_live(_combat_active_before_screen)
	# The forecast strip annotates the BATTLEFIELD, and this hook is the one edge that says a
	# screen has taken the battlefield — the coordinator calls it from `_take_claims` /
	# `_release_claims`, i.e. exactly at the push that makes its stack non-empty and the pop that
	# empties it. Deliberately NOT `FormationMapHost.unit_activated` + a `dismissed`: the MAP host
	# never emits `dismissed` (`_on_dismissed` returns early on `Host.MAP` — it is PERSISTENT and
	# has nothing to hand back), so that pair would hide the strip and never bring it back.
	if is_instance_valid(_turn_queue_hud):
		_turn_queue_hud.set_covered(paused)


## Which unit stands on `grid_pos`. The scenario host keeps its units in `_units_by_id` (the VM's
## registry), so its answer differs from the arena's — which is exactly why the map host takes this
## as a callable instead of reaching for a units array itself.
##
## The cursor names a COLUMN (`Vector2i`), so this asks the column question: a unit on any level of
## `grid_pos` answers. Cycling the cursor between a column's levels is deferred (#795); until it
## lands there is no way for the cursor to mean the upper one. Same rule, same words, as the arena's
## own [code]GPUArena._unit_at_grid[/code] — two battlefields, one question.
##
## 🔴 THIS USED TO COMPARE THE CELL TO THE COLUMN. `get_current_cell()` returns the level-aware
## `Vector3i` (ADR-0219 / #795); `grid_pos` is a `Vector2i`. That is not a comparison that comes out
## false — it is `Invalid operands 'Vector3i' and 'Vector2i' in operator '=='`, a runtime error that
## aborts THIS function on its first unit, so every tile answered `null` and the map host read the
## whole battlefield as empty. The arena copy was corrected when the cell went level-aware and this
## one was not.
##
## It stayed invisible because `null` is a legitimate answer ("empty tile"), so nothing failed —
## only a `SCRIPT ERROR:` line, and reaching it at all is a race the suite usually won: the map host
## binds one `await process_frame` after the cursor mounts, and `NavigatorCommandModeProofTest`
## normally asserts and quits first. Deploying at world boot spends that frame, so the bind now
## lands 5 times in 5 — which is how a latent defect surfaced as a `THREW` verdict on a change that
## never touched this function. Guarded by `NavigatorPreBattleTest`, on the ANSWER not the error.
func _unit_at_grid(grid_pos: Vector2i):
	for unit in _units_by_id.values():
		if unit == null or not is_instance_valid(unit):
			continue
		var cell: Vector3i = unit.get_current_cell()
		# A unit with no logical tile stands nowhere — it must not answer for the sentinel's column.
		if cell == TerrainCell.NONE:
			continue
		if Vector2i(cell.x, cell.y) == grid_pos:
			return unit
	return null


## Free the command-mode cursor rig (built at Deployment entry). Called on world teardown so a
## cross-group re-boot doesn't leak or double-wire it; nulls the refs so a later Deployment rebuilds.
func _free_command_cursor() -> void:
	if _formation_map_screen != null and is_instance_valid(_formation_map_screen):
		_formation_map_screen.queue_free()
	_formation_map_screen = null
	if _cursor_rig != null and is_instance_valid(_cursor_rig):
		# `dispose()` frees the cursor too, because `mount()` built it (ADR-0206).
		_cursor_rig.dispose()
	_cursor_rig = null
	# The seat is a property of the rig; a rebuilt rig is an unseated one.
	_command_surface_seated = false


## Make each ENTD slot's already-spawned world unit combat-ready and return the list.
func _combat_ready_team(slots: Array, team: int) -> Array:
	var out: Array = []
	for slot in slots:
		var uid := int(slot.get("unit_id", ENTD_EMPTY_UID))
		var unit = _units_by_id.get(uid)
		if unit == null or not is_instance_valid(unit):
			push_warning("[NavigatorMain] ENTD slot uid 0x%02X has no spawned unit — skipping" % uid)
			continue
		_make_combat_ready(unit, slot, team)
		out.append(unit)
	return out


## Turn one scenario-spawned (visual-only) Unit into a combat-ready one. RESOLVES the
## identity — which Catalog Character this ENTD slot is — and hands off to the shared
## `_make_combat_ready_from_character` for everything after that (Explore gap analysis
## §6/§7).
func _make_combat_ready(unit: Node, slot: Dictionary, team: int) -> void:
	# WHO this unit is comes from the Catalog through the binding resolver — not the
	# raw ENTD slot (ADR-0201). A hit pulls the replayed Catalog Character (its
	# identity/progression flows into the fight); a miss falls back to ENTD-slot
	# construction exactly as before (at Orbonne the Catalog is near-empty, so every
	# slot falls back and the cast is byte-for-byte today's). The slot still owns
	# position/deploy; the scenario-spawned `unit` node is unchanged.
	var uid := int(slot.get("unit_id", ENTD_EMPTY_UID))
	# The level an ENTD sentinel scales to is a property of the RECORD, not of one slot
	# (godot-learning ADR-0289, #1179). `_load_entd_record` is the cached reader, so
	# deriving it per slot costs a 16-slot scan, not a re-parse.
	var ceiling := Character.level_ceiling_for_slots(
		EntdBattle.combatant_slots(_load_entd_record(_entd_record)))
	var character: Character = _binding.resolve_character(
		int(_entd_record), uid, slot, CharacterCatalog, ceiling)
	if character.progression == null:
		# A registered-but-BARE identity (the ADR-0066 protagonist seed carries no
		# progression yet) can't deploy. Rebuild it battle-ready from the ENTD slot —
		# from_entd_slot re-derives the same canonical identity (slug/name), so no
		# identity is lost; only the missing progression is filled. Replayed guests
		# (create/join sourced from a slot) DO carry progression and skip this.
		character = Character.from_entd_slot(slot, null, ceiling)
	# Everything from here down is identical to the roster-deployed path — an ENTD
	# slot and an owned overlay entry differ in WHO the Character is, never in what
	# making one combat-ready does. Resolving the identity is this function's whole
	# job; the rest is the shared one.
	_make_combat_ready_from_character(unit, character, team)
	# COMMANDABLE — the ENTD writer (cluster 41). The slot's control flag is read HERE,
	# where the slot is in hand, rather than re-derived later from where the unit came
	# from. Written unconditionally, so a body reused across battles cannot carry a stale
	# true. The roster writer is in `_deploy_owned_units`; there is no third.
	if "commandable" in unit:
		unit.commandable = BattleDeployment.slot_is_commandable(slot)


## Encode each unit's gambit list for the GPU (global index → encoded array).
## Gambit-less units still route through the encoder so they get the injected
## attack-nearest safety net (ADR-0048). No longer a MIRROR of the arena's copy:
## both call [GambitEncoder.encode_for_units] since ADR-0242. Silent here on
## purpose — a walk arms battle after battle and does not want a line per unit.
func _build_encoded_gambits(units: Array) -> Array:
	return GambitEncoder.encode_for_units(units)


# === Runner callbacks =========================================================

func _on_combat_victory(winner: int, team0_alive: int, team1_alive: int) -> void:
	if not _combat_active:
		return  # already resolved (e.g. a timeout beat us here)
	_last_combat_winner = winner
	print("[NavigatorMain] combat resolved winner=%d (t0_alive=%d t1_alive=%d)" %
		[winner, team0_alive, team1_alive])
	# A scripted-outcome battle (Orbonne — Ovelia is taken regardless of the tactical
	# result) always advances to its victory beat. A roster-fed battle (Gariland) routes
	# the REAL winner: winner==0 → victory beat → clean stop (#234 F); winner≠0 → v1 halt.
	_end_combat_and_advance(0 if _battle_scripted_outcome else winner)


## Tear the bare loop down and route the combat outcome to the runner (winner 0 = player
## → the victory beat; else the v1 defeat halt). `winner` is decided by the caller — a
## scripted-outcome battle passes 0; a timeout passes 0 (inconclusive → continue, v1).
func _end_combat_and_advance(winner: int) -> void:
	_combat_active = false
	# THE HANDBACK, before anything is freed: it reads the clocks off the live registry and
	# hands the cursor, the screen and the camera back to the world that SURVIVES this call —
	# the victory beat plays on that world (ADR-0177 Amendment 3).
	_end_battle()
	_free_turn_queue_hud()
	if is_instance_valid(_combat_loop):
		_combat_loop.queue_free()
	_combat_loop = null
	# The battle and its prewarm die with the loop: a fresh one has to build and boot again.
	_battle_booted = false
	_prewarmed_root = -1
	_pending_team0 = []
	_pending_team1 = []
	_nav_runner.on_combat_finished(winner)


func _on_combat_timed_out(tick: int) -> void:
	if not _combat_active:
		return  # victory already resolved this battle
	push_warning("[NavigatorMain] combat reached max_ticks (%d) with no decisive result — "
		% tick + "advancing the walk (v1 inconclusive→continue; positioning/balance is a follow-up)")
	_end_combat_and_advance(0)


func _on_runner_state_changed(state: int) -> void:
	print("[NavigatorMain] STATE → %s" % GameState.State.keys()[state] if state >= 0 else str(state))
	# The forecast strip's LIFETIME (ADR-0269 dec. 8): up for the whole battle, gone outside one.
	# The walk's own state machine already carries the edge — `NavigatorRunner._dispatch` sets
	# PRE_BATTLE then BATTLE — so there is no signal to invent here. The real edge is
	# PRE_BATTLE → BATTLE and back out; DEPLOYMENT is never set by this runner, and the strip is
	# deliberately absent during deployment anyway (there is no turn order to forecast until the
	# cast is committed, and whether the ORDER is useful while placing units is the head-marking
	# ticket's question, not this one).
	if is_instance_valid(_turn_queue_hud):
		_turn_queue_hud.set_battle_live(state == GameState.State.BATTLE)


func _on_runner_walk_finished() -> void:
	# The walk plays THROUGH Gariland and OUT onto the overworld: victory beat (scn 12) →
	# `world-map` successor → the terminal `world_map` action → the screen is dismissed →
	# walk_finished. Turning the node the player then enters into the NEXT scenario is X1.
	print("[NavigatorMain] ✅ WALK COMPLETE — Gariland cleared, world map dismissed.")
	# The camera is left where scenario 12's OWN victory-beat opcodes put it: op-10 {1F}
	# Focus(0x01) re-aims op-11's {19} Camera onto the deployed Ramza (registered under
	# RAMZA_EVENT_UID at deploy time), the FFT-faithful focus. No heuristic re-home needed.


func _on_runner_defeated() -> void:
	print("[NavigatorMain] ⛔ walk halted — combat lost — v1 halt (no retry / game-over).")
