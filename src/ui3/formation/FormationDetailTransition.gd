extends Node3D
## Host that wires the formation roster's ○-press to the Status/detail transition
## (FORMATION_SCREEN.md §15.5) — the "big-picture" composition object the pieces plug
## into (per the 2026-08-05 design chat): it owns the FormationScene and, on
## `unit_activated`, overlays a DetailScene over it and plays the slide→gap→box-open.
##
## The transition plays OVER the (kept) formation: the grid + dark band stay behind as
## the background the DetailScene's vitals stripe subtracts from (§15.6 "band cut" =
## the formation band staying put while the detail stripe takes over). The formation's
## OWN docked pair is hidden the instant the detail cluster appears at the same docked
## spot, so the shared vitals+nameplate hands off seamlessly (one pair, not two).
##
## Run headful: `godot --path . res://assets/scenes/FormationDev.tscn` — that scene is
## [FormationDevBoot], which seeds a roster first. `FormationDetailTransition.tscn` is THIS script
## bare, which is what a host mounts, and standalone it shows an empty grid (ADR-0181).
## then Enter/○ on a unit to play the transition, Backspace/✕ to close it.
##
## [b]The three keys, because the comments in this tree used to name a fourth that does
## something else.[/b] `project.godot`'s InputMap, decoded: `ui_accept` = Enter + KP-Enter +
## pad 1 (○); `ui_cancel` = **Backspace** + pad 0 (✕); `formation_start_menu` = Tab + pad 3
## (△), shared with `unit_inspect` and `world_map_start_menu`. **Escape is not `ui_cancel`
## here at all** — it is bound to `battle_pause`. Nothing binds pad 2 (□).

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const CursorRig = ExMateriaBattlefield.CursorRig

## #1272 — `CharacterCatalog` is a host `[autoload]` line, and an addon cannot ship
## `project.godot` entries (ADR-0262 dec. 6). The catalogue SCRIPT already lives in
## `addons/exmateria_catalogue/`; `UIRoster` reaches the running node through its own
## `live()` and carries UI's empty-roster fallbacks. ADR-0308.
const UIRoster = preload("res://src/ui3/UIRoster.gd")

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const AbilityCandidates = ExMateriaAlmanac.AbilityCandidates
const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase
const AbilityLoadout = ExMateriaAlmanac.AbilityLoadout
const EquipCandidates = ExMateriaAlmanac.EquipCandidates
const EquipStatDelta = ExMateriaAlmanac.EquipStatDelta
const JobCandidates = ExMateriaAlmanac.JobCandidates
const JobDatabase = ExMateriaAlmanac.JobDatabase
const JobLevelsDatabase = ExMateriaAlmanac.JobLevelsDatabase


const FormationScene = preload("res://src/ui3/formation/FormationScene.gd")
const DetailScene = preload("res://src/ui3/detail/DetailScene.gd")
const StartActionMenu = preload("res://src/ui3/detail/StartActionMenu.gd")
const EquipPickerMenu = preload("res://src/ui3/detail/EquipPickerMenu.gd")
const UIUnitNameplate = preload("res://src/ui3/UIUnitNameplate.gd")
const SpriteSlideAnimator = preload("res://src/ui3/detail/SpriteSlideAnimator.gd")
const VitalsSlideAnimator = preload("res://src/ui3/detail/VitalsSlideAnimator.gd")
const ChangeJobScreen = preload("res://src/ui3/changejob/ChangeJobScreen.gd")
const ChangeJobWheel = preload("res://src/ui3/changejob/ChangeJobWheel.gd")
const TransitionEngine = preload("res://src/ui3/formation/FormationTransitionEngine.gd")

## The action-menu row that opens the Item → Equip sub-screen (StartActionMenu.ROWS[0]).
const EQUIP_MENU_ROW := 0
## The action-menu row that opens the Ability sub-screen (StartActionMenu.ROWS[1] = "Ability").
## §15.23 RE27: the exact mirror of the Item→Equip path — same slide/spotlight/orb-box/redock, only
## the settled lower panel (ability_only) + the list-menu (Set/Remove/Learn) differ.
const ABILITY_MENU_ROW := 1
## The action-menu row that opens the full-screen Change-Job screen (StartActionMenu.ROWS[2]).
## §15.24 RE28: a NEW full-screen builder (NOT a lower-panel sub-state like Equip/Ability) — the
## roster splits (upper rows exit left / lower right), the selected unit slides to the oval CENTRE,
## and a ring of gender-appropriate generic job bodies surrounds it, with the job title bottom-middle.
const CHANGEJOB_MENU_ROW := 2

## The action-menu rows this coordinator ACTS on, keyed by their LABEL (#1007).
##
## The three index consts above are what the ROM's own five-row menu is dispatched by, and they
## were the whole dispatch until a second coordinator-owned row set existed. ADR-0247 named the
## hazard that creates — "an index means nothing across two row sets" — and took the only
## position available at the time: a host that supplies rows also owns what they mean. That is
## still right for rows this coordinator did not author ("Deploy Unit" is not its verb), but it
## is not right for [constant StartActionMenu.ROWS_ADJUST], whose four rows are three of the
## ROM's own plus the gambit door.
##
## A LABEL means the same thing in both sets, so the dispatch keys on it: a row named "Item"
## enters the Equip screen whichever list it came from, and a row this table does not know still
## leaves through [signal action_row_chosen] exactly as before.
const MENU_LABEL_STATE := {
	"Item": State.EQUIP,            # §15.23
	"Ability": State.ABILITY,       # §15.23 RE27
	"Change Job": State.CHANGE_JOB, # §15.24 RE28
	"Gambit": State.GAMBIT,         # #1007 — game-original, ROWS_ADJUST only
}
## Which HOST this coordinator is wired to (ADR-0137). ROSTER = the standalone Formation screen,
## its own orthographic camera and stone floor, the 4x2 grid answering "who is selected" — the
## out-of-battle path. MAP = the SAME screen re-hosted over the live battlefield, mounted under the
## map's camera with the tile cursor answering the selection question.
##
## They coexist permanently; neither replaces the other. Set BEFORE add_child — `_ready` builds the
## host from it, and `_build_recipes` decides whether the camera-pan recipe exists.
enum Host { ROSTER, MAP }
@export var host_mode: Host = Host.ROSTER

## Mount the Formation screen over a live battlefield, camera-child, in one call (ADR-0137).
##
## Everything host-specific is a parameter, so the two map-bearing scenes (GPUArena, NavigatorMain)
## share this instead of each growing their own copy: `unit_at` is `func(Vector2i) -> Node` (each
## scene holds its unit list differently), `pause_battle_fn` is `func(bool)` (each flips its own
## `combat_active`). Returns the coordinator; it is a child of the map camera and carries the
## scale correction, so the DetailScene it overlays inherits it too.
static func mount_over_map(player_camera: CharacterBody3D, cursor_rig: CursorRig,
		unit_at: Callable, pause_battle_fn: Callable, can_open: Callable = Callable()) -> Node3D:
	var camera := player_camera.get_node_or_null("FocusPoint/Camera") as Camera3D
	if camera == null:
		push_error("[FormationDetailTransition] mount_over_map: no FocusPoint/Camera under the player camera")
		return null
	var host: Node3D = (load("res://src/ui3/formation/FormationDetailTransition.gd") as GDScript).new()
	host.name = "FormationMapScreen"
	host.host_mode = Host.MAP
	host.pause_battle = pause_battle_fn
	host.map_binding = {
		"cursor_rig": cursor_rig,
		"player_camera": player_camera,
		"unit_at": unit_at,
		"can_open": can_open,
	}
	camera.add_child(host)
	# The screen is authored for a keep-height ortho of 9.6 world units and this camera runs 12.6,
	# so the ROOT scales by 12.6/9.6. Never the camera — that would zoom the map, and the spec asks
	# for a pan.
	FormationMapHost.apply_mount_transform(host, camera)
	return host


## `func(paused: bool)` — pause/resume the battle across the whole gesture (ADR-0037). Injected by
## the map scene, because "the battle" is the map host's object, not this coordinator's. Pause sits
## deliberately OUTSIDE the recipe: it is a host STATE FLIP, not an animation, and giving it a beat
## would make the reversibility audit assert over something that has no motion to reverse.
var pause_battle: Callable = Callable()

## True while the CAMERA + PAUSE claims are held on the MAP host — taken by the push that made the
## stack non-empty, released by the pop that empties it (ADR-0261).
##
## [b]The camera takeover is not decoration: it IS the tile cursor's input gate.[/b]
## `TileCursor._input_allowed()` refuses every press unless `camera_mode == CURSOR`, so releasing
## the takeover hands the battlefield cursor back — and doing that under a screen that is still up
## is the whole lock-out bug. `PlayerCamera.request_takeover/release_takeover` is a single flag with
## no depth (and other drivers — cinematics, the effect viewer — share it), so it cannot be taken
## twice and released once. Owning it at ONE seam, the stack's own empty↔non-empty edge, is what
## makes "held iff a screen is up" a property rather than a hope.
var _claims_held := false

## The ADR-0172 screen-in — the ramp this screen runs on ITSELF as it comes up, on
## [constant Host.ROSTER] only. Null once it has landed (it frees itself; see
## `FormationScreenIn._release`) and null for the whole life of the MAP host.
##
## [b]Host-gated for the same reason `dismissed` is.[/b] `Host.ROSTER` means "I am a screen with
## a lifetime" — it raises itself and it hands the display back. `Host.MAP` means "I am a
## persistent overlay on somebody else's battlefield" — it does neither, and a full-screen
## subtractive quad there would black out the battle it is mounted over.
var _screen_in: FormationScreenIn = null


## True while the screen-in is still ramping — the screen is up but not yet listening.
## `CONTEXT.md` defines a screen-in as running "before it accepts input".
func screen_in_active() -> bool:
	return _screen_in != null and is_instance_valid(_screen_in) and _screen_in.is_active()


## Raise this screen under its own [FormationScreenIn] ramp (ADR-0172). Called by the HOST that
## mounts it — `NavigatorMain._on_world_map_menu_row` and [FormationDevBoot].
##
## [b]Opt-in, and it STARTS SETTLED — the same call ADR-0161 already made one level down.[/b]
## `WorldMapTownPage._open_frame` begins at `OPEN_VSYNCS` on purpose, and its docstring gives
## the reason verbatim: *"every existing caller and every settled-frame assertion keeps the
## numbers it already has, and the animation is opt-in through `begin_open()`. A page that
## animated by default would make every one of those assertions read a frame nobody asked it
## about."* Built into `_ready` instead and measured, that is exactly what happened here — 36
## tests `.new()` this coordinator and three of the first five went red, because a 30-vsync
## input gate is invisible to a test that waits 4 frames and then presses a key.
##
## This is a trigger, not an ownership change: the RAMP is still the screen's, on the screen's
## own clock, under the screen's own quad (ADR-0161 §1 — a screen that covers itself cannot have
## the layering bug). A host saying "you are being mounted" is not a host owning the fade.
##
## No-op on [constant Host.MAP], which is a persistent overlay on somebody else's battlefield.
func begin_screen_in() -> void:
	if host_mode == Host.MAP:
		return
	if _screen_in != null and is_instance_valid(_screen_in):
		return
	_screen_in = FormationScreenIn.new()
	_screen_in.name = "ScreenIn"
	add_child(_screen_in)

## MAP host wiring, set BEFORE add_child: {"cursor_rig": CursorRig, "player_camera":
## CharacterBody3D, "unit_at": Callable, "can_open": Callable}. The key was "tile_cursor"
## until ADR-0206 published the rig; the value is the PORT now, not the cursor node. Applied in `_ready` once the host node exists — the map
## scene cannot bind it itself because the host is built here, a frame later.
var map_binding: Dictionary = {}

## The HOST's own action rows (#941), set BEFORE the screen opens. Empty = the ROM's five
## (`StartActionMenu.ROWS`) and the §15.23 dispatch below; non-empty REPLACES both — the menu builds
## with these rows and every choice leaves this coordinator through [signal action_row_chosen].
##
## Both halves are load-bearing. Swapping the rows without swapping the dispatch would run the
## deployment menu's row 0 into `enter(State.EQUIP)`, because that dispatch is keyed by INDEX and an
## index means nothing across two row sets. So the host that supplies rows also owns what they mean;
## this coordinator stops having an opinion, which is the only honest position when it did not
## author the list.
##
## `action_menu_location` picks the window's home for them (`StartActionMenu.LOC_*`); "" keeps the
## detail-screen home the ROM rows use.
var action_rows: Array[String] = []
var action_menu_location: String = ""

## A row was chosen on a HOST-SUPPLIED action menu (see [member action_rows]). Never fires for the
## ROM's own five — those are dispatched here, by name, and always were.
signal action_row_chosen(row: int)

## What [method enter] with [constant State.PICK] raises the grid over —
## `{"characters": Array, "units": Array}`, parallel arrays (ADR-0261). Set BEFORE the `enter`, which
## is the same handshake `action_rows` and `action_menu_location` have: the state's leaf reads it
## while building, so a later write would describe a grid that is already up. Cleared on exit.
##
## The coordinator does not compute this and could not: WHO is eligible for a tile is a rule about
## a squad cap and a mandatory-unit reserve, which are the battle host's.
var pick_offer: Dictionary = {}

## The deployment pick has ended and its grid is down (ADR-0261). `cancelled` is true when ✕ ended it
## (nobody was deployed) and false when the host unwound it after a deploy — the two are different
## doors and only this coordinator can tell them apart.
signal pick_ended(cancelled: bool)

## A gambit slot was edited on the open [GambitSurface] (#1007). Carries the slot index, so a host
## can say which rule changed without reading the list back.
signal gambit_edited(slot: int)

## An imperative was issued on the open surface (#1006) — a charge is spent and a one-shot order
## stands above that unit's list. Re-emitted for hosts and guards; the order is already in the
## ledger, and it crosses to the GPU at the turn's commit like every other edit on this screen.
signal imperative_issued(order)

## Which lower sub-screen the current slide is bound for — set at begin_*_transition, read in
## _finish_sub / _open_sub_menu so the ONE transition machinery serves both Equip and Ability.
enum SubMode { EQUIP, ABILITY }
var _sub_mode: SubMode = SubMode.EQUIP
## How open_detail brings the Status/detail overlay in. TRANSITION = the ○-press arc (chrome
## slide + box-open, play_transition); SLIDE = the first-class chrome slide ONLY (play_entry_slide)
## for the main-menu sub-screens, which open their OWN lower panel after it settles; SETTLE = an
## instant snap (non-transitional). SLIDE is what fixes the main-menu "binary flip" (§15.1/§15.5).
enum Entry { TRANSITION, SLIDE, SETTLE, DOCKED }
## ADR-0084 coordinator states — one per Formation SCREEN the transitions move between. IDLE is the
## plain roster (nothing on the stack); the rest each name a screen the coordinator can `enter`/`leave`.
##
## PICK is APPENDED, never inserted, and that is load-bearing: several tests compare
## `current_state()` against these by VALUE, so renumbering IDLE..GAMBIT would silently redefine
## every one of them.
##
## [b]PICK is the deployment pick as a STACK LEVEL (ADR-0261).[/b] It was a host mode
## (`FormationMapHost._picking`) the coordinator could not see, so with a full roster grid raised
## over the battlefield `current_state()` answered IDLE — and three separate places grew a private
## `_picking()` question to work around the lie (the START-menu guard, the pad backstop, and
## `_on_menu_cancelled`'s one-press exit). Worse, the CLAIMS a pick holds (the camera takeover, and
## through it the tile cursor's input gate) were taken by the pick and released by whichever screen
## exited last: opening Status over the pick and backing out of its menu released the takeover while
## the grid was still up, which un-gated the tile cursor UNDER a live screen. One stack that reports
## what is actually on the display is what makes the claims' owner unambiguous.
enum State { IDLE, DETAIL, EQUIP, ABILITY, CHANGE_JOB, GAMBIT, PICK }

## How far ✕ unwinds out of each screen — the BACK GRAMMAR, declared once (ADR-0261).
##
## Every transition defect this table replaced was the same shape: a rule stated in one place and
## not another. The unwind depth used to live in `_exit_settled`'s match arms, the chrome beat's
## reverse, and `_teardown_sub_screen`, which is three chances for two of them to disagree — and
## `_on_menu_cancelled` had a FOURTH answer keyed on whether the host had supplied rows, which is
## not a fact about the screen at all.
##
## `POP_ONE` pops exactly the screen you are on; `UNWIND_ALL` clears the stack (ADR-0084 RE25 — the
## ROM's own Formation exits mostly unwind to the roster). The MAP host's column differs because it
## has no roster to bottom out at: its bottom is the battlefield, or a deployment PICK, and
## unwinding wholesale discards the screen the player was standing on one press ago (ADR-0137
## Amendment 7, user 2026-08-21).
const POP_ONE := 1
const UNWIND_ALL := -1

## `State` -> levels ✕ unwinds, on the ROSTER host.
const _UNWIND_ROSTER := {
	State.DETAIL: POP_ONE,          # the ○-press Status close pops exactly the DETAIL screen
	State.EQUIP: UNWIND_ALL,        # RE25: a sub-screen back-out bottoms out at the roster
	State.ABILITY: UNWIND_ALL,
	State.CHANGE_JOB: UNWIND_ALL,   # the job wheel is a full-screen takeover of the roster
	State.GAMBIT: POP_ONE,
}

## `State` -> levels ✕ unwinds, on the MAP host. Every sub-screen pops ONE, because the screen
## underneath is a destination here: Status is where you read the unit before choosing a row, and
## the battlefield below it is not a roster you can browse.
##
## CHANGE_JOB is in this column as of ADR-0261. Amendment 7 excluded it on the grounds that
## "committing a job change is a destination, not a detour" — but that argues about the COMMIT, and
## ✕ is the path where you did not commit. Left out, ✕ off Item landed on Status and ✕ off Change
## Job landed on the battlefield, from the same menu, one row apart. The full unwind stays on the
## commit path, where the Amendment's reasoning actually applies.
const _UNWIND_MAP := {
	State.DETAIL: POP_ONE,
	State.EQUIP: POP_ONE,
	State.ABILITY: POP_ONE,
	State.CHANGE_JOB: POP_ONE,
	State.GAMBIT: POP_ONE,
	State.PICK: POP_ONE,            # the bottom level here — popping it empties the stack
}
## Every action FormationScene._unhandled_input acts on. The roster grid does NOT know when it is
## COVERED by a screen, so while one is up the host must claim these itself or the grid acts blind
## underneath: ↑/↓ moved the hidden selection behind the Change-Job wheel, L2/R2 re-paged its sort,
## and ○ emitted `unit_activated` — which opened the Status overlay ON TOP of the wheel. Deliberately
## a NAMED set rather than "claim everything": mouse motion and the F3 debug panels must still reach
## the rest of the tree over an open screen.
const _ROSTER_ACTIONS: Array[String] = [
	"ui_accept", "ui_cancel", "ui_up", "ui_down", "ui_left", "ui_right",
	"formation_sort_next", "formation_sort_prev",
]
## The open gambit surface (#1007), or null. Parented to THIS node rather than to the detail
## screen for the reason ADR-0137 Amendment 2 gives about the action menu: the UI3Element basis
## lookup walks node PARENTS for a `screen_to_world` declarer, and this coordinator is the one
## that declares it. A surface hung off the DetailScene would find the same basis; a surface hung
## off the map scene would find none and clip every fragment away while looking built.
var _gambit_surface: GambitSurface = null

## The battle's imperative ledger ([ImperativeGambits], #1006), or null. Supplied by a BATTLE host
## and by nothing else: the roster host has no battle, so it has no charges, and its gambit surface
## is exactly the four slots it was before #1006. Set once at mount, beside `action_rows`.
var imperative_orders = null
## `func(character) -> int` — which unit index a character is, in the battle the ledger belongs to.
## The ledger is keyed by unit index because charges are BATTLE state; the Character is the durable
## representation that outlives the battle (ADR-0005), and only the host knows the mapping.
var imperative_unit_for: Callable = Callable()
## `func() -> int` — the world's tick right now, for the watchdog deadline an issue stamps.
var imperative_now: Callable = Callable()

## Menu-tick cadence (≈30 Hz), shared with the other §15 animators.
const _EQUIP_TICK := 2.0 / 60.0
## Per-frame catch-up ceiling for the delta-paced steppers below (Equip / Change-Job entry / rotate
## / exit). A single oversized frame — a stall, or the Hyprland `render_unfocused` throttle dropping
## the window to ~1 fps — otherwise runs their unbounded accumulator loops enough times to reach the
## slide's settle in ONE visual frame (the "teleport"). Clamping the delta bounds each frame's advance
## so intermediate frames stay visible; normal 30-60 fps deltas are well under it. Mirrors DetailScene._MAX_CATCHUP.
const _MAX_CATCHUP := 2.0 * _EQUIP_TICK

## ADR-0084 coordinator seam. `settled(to)` fires when an `enter`/`leave` reaches a resting screen
## (the resulting `current_state()`); input routing + guards read `current_state()`/`is_moving()`.
signal settled(to)

## The SCREEN is finished; whoever mounted it may take the display back. Emitted only on
## [constant Host.ROSTER] — see `_on_dismissed`.
##
## [b]Deliberately the same name [FormationScene] and [WorldMapScene] use, and that is the
## interface, not a coincidence.[/b] `dismissed` is how every screen in this game hands the
## display back: `NavigatorMain` awaits it for the debug formation view, for the world map and
## for the world-map Formation, and five navigator tests IDENTIFY the world-map screen by
## duck-typing `has_signal("dismissed")`. A coordinator that invented a second word would be the
## one screen the navigator could not treat uniformly.
##
## [b]Not [signal settled].[/b] `settled(to)` fires at every resting screen, and `_exit_settled`
## emits `settled(State.IDLE)` every time you back out of Detail to the roster — so a host awaiting
## it would tear the screen down while the player is still standing on the grid. `settled` is a
## WITHIN-screen seam; this is the screen's LIFETIME. ADR-0181.
##
## [b]Scope note.[/b] The FormationScene below also declares `dismissed`, and there it is the roster
## ELEMENT's cancel, consumed by `_on_dismissed`. Hosted, that signal stops at this coordinator;
## standalone (`Formation.tscn`), the same signal is that scene's own hand-back. Which role it plays
## is decided by whether anything is hosting it.
signal dismissed()
## The LIFO screen stack (ADR-0084). Top = the current screen; empty = IDLE (the plain roster). Most
## FFT Formation exits RE as a FULL unwind to the roster (memory `formation-detail-screen-port-built`
## / RE25), so a sub-screen exit clears the stack rather than popping one — the LIFO generalizes
## cleanly if a future nested screen (Confirm-Job) needs one-level pops.
##
## It is a GATE, not a ledger. It has exactly TWO writers: `enter()` pushes the screen it ACCEPTS,
## and `_exit_settled()` applies the unwind when a reverse animation rests. No entry/exit leaf may
## touch it — they play animations, the coordinator decides. That is what lets `enter()` refuse a
## screen you are already on: the decision is made by the one function that knows the state.
##
## Timing is deliberately asymmetric: PUSH at the start of the entry animation, UNWIND at the end of
## the exit animation. A screen is occupied the moment you begin entering it and vacated only once
## you are fully out, so `current_state()` never reports a screen that is still on its way off — and
## the `enter()` gate therefore holds mid-flight, not just at rest.
var _stack: Array[int] = []

var _formation: FormationScene
var _detail: DetailScene
var _menu: StartActionMenu
## §15.23 in-place switch: the live START menu, PARKED (hidden, unrouted) while the
## sub-screen slide runs so it can be RE-HOMED as the Equip/Ability list-menu at settle
## — the ROM re-renders the SAME slot-6 window in place (the "Order Unit ghost" proof),
## so the port keeps ONE menu instance across the switch instead of teardown+rebuild.
## place_at is this verb's first production consumer (ADR-0088 Amendment 2 §4).
var _parked_menu: StartActionMenu
var _changejob: ChangeJobScreen   # §15.24 bottom-middle job-title frame (the wheel lives in FormationScene)
var _picker: EquipPickerMenu       # §15.26 equipment picker — mounted on ○ from a focused Eqp slot row
var _ability_picker: AbilityPickerMenu   # the ability "Set" picker — mounted on ○ from a focused ability slot
var _job_picker: JobPickerMenu           # the ability "Learn" job picker — mounted on ○ from the menu's Learn row
var _learn_list: LearnAbilityMenu        # Learn PHASE 1 — the ability list, mounted on ○ from the job picker
var _learn_job_id: String = ""           # the job the open ability list belongs to (its commit target)
var _learn_return_row := 0               # the job-picker row to re-seat when × backs out of the list
var _slot_remove_mode := false     # §15.31: slot focus was entered via "Remove" — ○ unequips, no picker
var _ability_remove_mode := false  # ability "Remove": slot focus where ○ CLEARS the ability slot, no picker

# ADR-0084 engine: ONE Player drives every PORTED screen's recipe — forward on enter, the SAME
# groups reversed on leave (no separately-authored exit; invariant 1). It owns the menu-tick
# accumulator + _MAX_CATCHUP clamp, so _process just feeds it delta. `_playing_recipe`/`_playing_reversed`
# name what is mid-flight so the semantic queries (is_equip_sliding / is_equip_exiting) can answer.
# The Item→Equip AND Ability sub-screens share the ONE "EQUIP" slide recipe (only `_sub_mode` differs,
# selected at the finish). The chrome descent on exit is still driven by DetailScene._process and ends
# the exit via its `closed` signal; the engine only drives the roster un-slide in lockstep.
var _player: TransitionEngine.Player = TransitionEngine.Player.new()
var _playing_recipe: TransitionEngine.Recipe = null
var _playing_reversed := false
# The recipe TABLE, built in _ready and audited for reversibility at boot (invariant 1). Keyed by id.
var _recipes: Dictionary = {}
# Envelope flag for the Equip/Ability animated back-out: the reversed EQUIP recipe drives the ONE
# concurrent group (roster un-slide + chrome descent together), so this stays true across the whole
# exit until the recipe settles into _teardown_sub_screen (which clears it).
var _sub_exiting := false

# Change-Job entry (roster split → ring contraction) and its animated back-out (ring spin+enlarge fling
# → roster un-split) are the CHANGE_JOB recipe on the Player above — NO per-screen steppers here.
# Only the ring ROTATION (§15.24 RE29, gap 3) survives as a stepper: a ←/→ press glides the ring one
# step. It is steady-state INTERACTION, not entry/exit choreography, so ADR-0084 keeps it out of the
# engine — its own small tick accumulator, driven in _process, distinct from the reversible envelope.
var _changejob_rot_active := false
var _changejob_rot_accum := 0.0

# The COMMIT cutscene (CHANGE_JOB_COMMIT.md). Deliberately NOT a recipe on the Player: the ROM's
# commit pushes no screen, pops none, and writes the job on its LAST frame, so there is no reverse
# driver that could exist — ADR-0084's "steady-state interaction stays out of the engine" clause,
# extended by its amendment to self-clocked in-place cutscenes. Its own clock too: the ROM ticks
# this one per VSYNC (`[dynamic]` 124 ticks in 2.00 s), not on the ~30 Hz menu tick the entry /
# rotate / exit animators share. Both cadences are correct; they are different animators.
const _COMMIT_TICK := 1.0 / 60.0
var _cj_commit: ChangeJobCommitCutscene = null
var _cj_commit_accum := 0.0
var _cj_commit_job := ""


func _ready() -> void:
	_build_recipes()
	if host_mode == Host.MAP:
		# The BATTLEFIELD is the roster: no seeding, no grid, and no `set_owned_characters` — the
		# map scene calls `bind_map()` on the host below to hand it the tile cursor + camera.
		_formation = FormationMapHost.new()
		_formation.name = "FormationMapHost"
		add_child(_formation)
		await get_tree().process_frame
		_formation.unit_activated.connect(_on_unit_activated)
		_formation.unit_act_requested.connect(_on_unit_act_requested)
		_formation.dismissed.connect(_on_dismissed)
		if not map_binding.is_empty():
			_formation.can_open = map_binding.get("can_open", Callable())
			_formation.bind_map(map_binding.get("cursor_rig"), map_binding.get("player_camera"),
				map_binding.get("unit_at", Callable()))
		print("[FormationDetailTransition] MAP host ready — △/Tab opens the unit's menus, ○/Enter picks, ×/Backspace backs out")
		return
	_formation = FormationScene.new()
	_formation.name = "Formation"
	add_child(_formation)
	await get_tree().process_frame          # let _ready build the grid before we inject
	_formation.set_owned_characters(_resolve_roster())
	_formation.unit_activated.connect(_on_unit_activated)
	_formation.dismissed.connect(_on_dismissed)
	print("[FormationDetailTransition] roster ready — Enter/○ opens a unit's Status screen")


# -----------------------------------------------------------------------------
# ADR-0084 recipe TABLE + the one Player. Each recipe wraps the FormationScene/DetailScene
# frame-stepped methods as beats (forward + reverse drivers); the drivers dereference `_formation`
# at CALL time, so the table is safely built before the roster exists (the boot audit never calls
# a driver — it only checks each beat carries a reverse). See ADR-0084 "Decision".
# -----------------------------------------------------------------------------

## Build every ported screen's recipe into `_recipes` and run the boot-time reversibility audit
## (invariant 1): a beat with no reverse driver aborts here, not at the user's first Esc.
func _build_recipes() -> void:
	# EQUIP (shared by Item→Equip AND Ability). ONE CONCURRENT group `[{chrome, split}]`: the top-chrome
	# raise (vitals+nameplate pair DOCKED→TOP + band cross-fade) and the roster split slide (the selected
	# unit slides to (166,173) while its rowmates slide off) play AT THE SAME TIME — the game runs them
	# concurrently, not sequentially (user 2026-08-08). Forward: chrome rises WHILE the split runs; the
	# merged group's barrier waits for the longest beat (the split), so the shorter chrome settles and
	# holds. Reverse (Esc): the SAME group reversed — the chrome DESCENDS back to the docked roster WHILE
	# the roster un-slides, the descent + orb/box reveal falling out of replaying the recipe reversed
	# (invariant 1), never a teardown snap. The two beats declare DISJOINT roles (chrome vs roster), so a
	# concurrent group is invariant-4-clean. Beats select targets by role (invariant 3); the chrome beat
	# drives DetailScene's pure-function-of-frame slide.
	var equip_chrome := _make_chrome_beat("equip_chrome")
	var equip_slide := TransitionEngine.Beat.new(
		"equip_slide",
		func(frame: int): if _formation != null and is_instance_valid(_formation): _formation.play_equip_slide(frame),
		func(frame: int): if _formation != null and is_instance_valid(_formation): _formation.play_equip_unslide(frame),
		SpriteSlideAnimator.SLIDE_DURATION, -1, ["roster"])
	# On the MAP host the group carries a THIRD beat: the camera pan+zoom (ADR-0137 Amendment 5).
	# It joins this group rather than getting its own because the whole point is that it runs
	# CONCURRENTLY with the narrowing — the frames close to `x14..138` and the unit arrives in the
	# space they open, as one move. Invariant 4 is satisfied by construction: the three beats declare
	# `chrome` / `roster` / `camera`, which do not overlap.
	var eq_beats: Array = [equip_chrome, equip_slide]
	var eq_forward := _equip_concurrent_enter_forward
	if host_mode == Host.MAP:
		eq_beats.append(TransitionEngine.Beat.new(
			"map_pan", _pan_forward_driver, _map_pan_hold_reverse,
			FormationMapHost.PAN_DURATION_DEFAULT, FormationMapHost.PAN_DURATION_DEFAULT, ["camera"]))
		eq_forward = _map_equip_concurrent_enter_forward
	var eq_g0 := TransitionEngine.Group.new(eq_beats, eq_forward, _chrome_enter_reverse)
	_recipes["EQUIP"] = TransitionEngine.Recipe.new("EQUIP", [eq_g0])

	# CHANGE_JOB (§15.24) — TWO groups `[{chrome, split}, [ring]]`: the chrome raise + roster split run
	# CONCURRENTLY (the merged group, same as EQUIP), THEN the ring ENTRY contraction as its own group.
	# The ring stays a separate group because its build barrier depends on the split being done, and on
	# exit the user confirmed the ring FLING plays FIRST, THEN the chrome-descent + roster-un-slide go
	# together (2026-08-08). Reverse play order is therefore [ring, {chrome, split}]: the fling first
	# (the ring's DISTINCT spin-and-enlarge reverse driver, RE32 — NOT the entry contraction reversed),
	# then at the merged group's reverse seam the ring is dropped + the un-slide reseeded + the orbs/box
	# revealed + the chrome descent begun, and the concurrent chrome-descent/un-slide plays out. Forward
	# seams: the merged group's forward hook raises the chrome + hides the orbs/box + seeds the split;
	# the ring group's build barrier builds the job ring + title and reports settled.
	var cj_chrome := _make_chrome_beat("changejob_chrome")
	var cj_split := TransitionEngine.Beat.new(
		"changejob_split",
		func(frame: int): if _formation != null and is_instance_valid(_formation): _formation.play_equip_slide(frame),
		func(frame: int): if _formation != null and is_instance_valid(_formation): _formation.play_equip_unslide(frame),
		SpriteSlideAnimator.SLIDE_DURATION, -1, ["roster"])
	var cj_ring := TransitionEngine.Beat.new(
		"changejob_ring",
		func(frame: int): if _formation != null and is_instance_valid(_formation): _formation.changejob_entry_step(frame),
		func(frame: int): if _formation != null and is_instance_valid(_formation): _formation.changejob_exit_step(frame),
		ChangeJobWheel.ENTRY_DURATION, ChangeJobWheel.EXIT_DURATION, ["ring"])
	var cj_g0 := TransitionEngine.Group.new(
		[cj_chrome, cj_split], _changejob_concurrent_enter_forward, _changejob_concurrent_enter_reverse)
	var cj_g1 := TransitionEngine.Group.new([cj_ring], _changejob_build_barrier, Callable())
	_recipes["CHANGE_JOB"] = TransitionEngine.Recipe.new("CHANGE_JOB", [cj_g0, cj_g1])

	if host_mode == Host.MAP:
		_recipes["MAP_DETAIL"] = _build_map_detail_recipe()

	var errors: Array = TransitionEngine.audit(_recipes.values())
	assert(errors.is_empty(), "ADR-0084 recipe audit FAILED (invariant 1 — reversibility): %s" % str(errors))
	var conflicts: Array = TransitionEngine.concurrency_conflicts(_recipes.values())
	assert(conflicts.is_empty(), "ADR-0084 recipe audit FAILED (invariant 4 — concurrent target overlap): %s" % str(conflicts))


## MAP_DETAIL (ADR-0137) — the camera takeover pan, as ONE group of ONE beat. The pan is the first
## beat of the DETAIL gesture on this host, and it is a first-class REVERSIBLE beat rather than a
## hand-sequenced phase: `leave()` replays the recipe reversed, so "pan in, then the screen" forward
## gives "the screen out, then pan" on exit with no separately-authored exit, and the boot-time
## reversibility audit covers it.
##
## Its reverse driver is genuinely ASYMMETRIC — `PlayerCamera.release_takeover()`'s own cosine ease
## back to the cursor's tile, not the entry run backward — which ADR-0084 blesses as first-class,
## hence the distinct `reverse_duration`.
##
## Rebuilt (not cached) each time it plays so a live F3 scrub of `formation.map.pan_ticks` reaches
## the beat; the copy built at `_ready` is what the boot audit inspects.
func _build_map_detail_recipe() -> TransitionEngine.Recipe:
	var hold := TransitionEngine.Beat.new(
		"map_hold", _pan_forward_driver, _pan_reverse_driver,
		FormationMapHost.HOLD_TICKS, FormationMapHost.PAN_RELEASE_TICKS, ["camera"])
	var g0 := TransitionEngine.Group.new([hold], _map_hold_enter_forward, Callable())
	return TransitionEngine.Recipe.new("MAP_DETAIL", [g0])


## REVERSE driver for the EQUIP group's pan beat — deliberately a HOLD, not a rewind. Still true,
## but for a DIFFERENT reason than when it was written, and the old one is worth keeping visible.
##
## It used to read: "the camera does go home on the way out, but not here — a sub-screen back-out is
## a FULL unwind (ADR-0084 RE25), so the MAP_DETAIL hold beat reverses immediately after this group
## and `release_takeover()` eases BOTH the body and the ortho size home; rewinding here as well would
## move the camera twice for one exit." ADR-0137 Amendment 7 FALSIFIED that: ✕ out of Equip/Ability
## now pops one level to DETAIL, the MAP_DETAIL beat does NOT reverse after it, and nothing
## downstream would have brought the camera back — the argument for holding evaporated even though
## the hold itself survived.
##
## What holds it up now is a DESIGN choice, not a bookkeeping one (user 2026-08-21, asked because the
## cheap and expensive versions differ a lot): the Status screen keeps the framing it was zoomed
## into, and the camera comes home only when you leave the unit for good. So the zoom belongs to the
## UNIT, not to the sub-screen — one takeover per visit, released once, on the final ✕ out of DETAIL
## (`_on_detail_closed` → MAP_DETAIL reversed → `release_takeover()`).
##
## It still TRACKS per frame, because the group's other beats are moving the panels and the clip
## basis has to keep up even when the camera itself is standing still.
func _map_pan_hold_reverse(_frame: int) -> void:
	_track_moving_camera()


## The pan beat's two drivers. Named methods rather than the inline lambdas the other beats use,
## because each is now two statements: step the camera, then FOLLOW it (see `_track_moving_camera`).
func _pan_forward_driver(frame: int) -> void:
	if _map_host() != null:
		_map_host().pan_step_forward(frame)
	_track_moving_camera()


func _pan_reverse_driver(frame: int) -> void:
	if _map_host() != null:
		_map_host().pan_step_reverse(frame)
	_track_moving_camera()


## Follow a camera that is MOVING UNDER US. Both halves of this exist because the pan now ZOOMS
## (ADR-0137 Amendment 3) and the original never did:
##
##  1. The root correction is `cam.size / 9.6`, so a changing size makes a FIXED mount wrong. It is
##     re-applied per frame, riding from x1.3125 down to x1.0 as the camera arrives — which is what
##     keeps the UI the same apparent size while the map behind it grows.
##  2. That re-mount moves this node, and this node IS the clip basis (see `screen_to_world`). Every
##     clipped panel's `clip_basis_inv` therefore goes stale on the same frame.
##     `UI3ClipEngine.clip_basis_inv_for`'s staleness note says in as many words that a gesture
##     animating the camera with a box-opening panel on screen would need a re-push per frame, and
##     that no such gesture existed. This is that gesture, so this is that re-push.
##
## The reverse beat calls it too: `release_takeover()` eases the size home over its own 16 frames,
## and the correction has to ride back UP with it or the screen is left 1.3125x too small on the way
## out. That the reverse beat is otherwise a no-op after frame 1 is exactly why this is not folded
## into `pan_step_reverse` — the host hands the camera back, but somebody still has to watch it.
func _track_moving_camera() -> void:
	if host_mode != Host.MAP:
		return
	var camera := get_parent() as Camera3D
	if camera == null:
		return
	if is_equal_approx(camera.size, _mounted_cam_size):
		return          # nothing moved — and this early-out is what makes a _process call free
	_mounted_cam_size = camera.size
	FormationMapHost.apply_mount_transform(self, camera)
	var registry = get_node_or_null("/root/UI3Registry")
	if registry != null:
		registry.refresh_clip_basis()


## The camera size the current mount was computed FOR. The mount is a function of that size, so
## comparing against it says whether the correction is stale — which is the whole tracking test.
var _mounted_cam_size := 0.0


## FORWARD hook at the hold group's seam: take the camera over and latch it WHERE IT IS. Everything the
## takeover implies — the dagger hidden, the tile cursor frozen with no key-repeat stuck, camera
## rotation dead, the tile highlight cleared and repainted on return — falls out of
## `camera_mode == CURSOR` gates that already exist, so there is nothing bespoke to undo.
func _map_hold_enter_forward() -> void:
	var host := _map_host()
	if host != null:
		host.begin_hold()


## FORWARD hook at the EQUIP group's seam on the MAP host: everything the roster host does at this
## seam, PLUS latch the pan+zoom motion — so the camera moves WHILE the frames narrow to `x14..138`
## and the unit is revealed by the same beat that reveals it (ADR-0137 Amendment 5).
func _map_equip_concurrent_enter_forward() -> void:
	_equip_concurrent_enter_forward()
	var host := _map_host()
	if host != null:
		host.begin_pan(host.selected_character())


## This coordinator's host, when it is the MAP one; null on the roster host. Lets the map-only
## beat drivers stay total without `has_method` duck-checks.
func _map_host() -> FormationMapHost:
	if _formation != null and is_instance_valid(_formation) and _formation is FormationMapHost:
		return _formation as FormationMapHost
	return null


## Build the SHARED top-chrome beat (ADR-0084): the vitals+nameplate pair raise (forward) / descend
## (reverse), driven frame-by-frame on the current DetailScene's pure-function-of-frame slide. Both
## EQUIP and CHANGE_JOB open the same chrome, so both recipes' first group is one of these. Reverse
## is a distinct driver (the box-less descent), so replaying the recipe reversed descends the chrome.
func _make_chrome_beat(id: String) -> TransitionEngine.Beat:
	return TransitionEngine.Beat.new(
		id,
		func(frame: int): if _detail != null and is_instance_valid(_detail): _detail.chrome_step_forward(frame),
		func(frame: int): if _detail != null and is_instance_valid(_detail): _detail.chrome_step_reverse(frame),
		VitalsSlideAnimator.settle_frame(), -1, ["chrome"])


## FORWARD chrome-group hook (EQUIP/CHANGE_JOB G0 on_enter_forward): arm the DetailScene chrome raise
## (a no-op HOLD if entered from the already-open detail screen) and hide the roster sort-header. Runs
## before the chrome beat's first frame — the instant work at the seam (ADR-0084).
func _chrome_enter_forward() -> void:
	if _detail != null and is_instance_valid(_detail):
		_detail.begin_chrome_raise()
	if _formation != null and is_instance_valid(_formation):
		_formation.set_header_visible(false)   # §15.22: no roster sort-header on the sub/full screen


## REVERSE chrome-group hook (EQUIP/CHANGE_JOB G0 on_enter_reverse): arm the chrome DESCENT at the
## seam. The orb/box VISUAL reveal is DEFERRED to teardown (_restore_formation, once the unit is HOME)
## — revealing it here popped the gold box in at the oval CENTRE (or the split origin) and rode it home
## as the roster un-slid (2026-08-08 regression, user-reported on the Change-Job close). The floor
## spotlight's box-GLIDE math is separate (end_equip_slide / _box_glide) and untouched by this.
func _chrome_enter_reverse() -> void:
	if _detail != null and is_instance_valid(_detail):
		# HOLD it when the exit lands back on the Status screen (Am.7): a chrome that was held on
		# the way in has nothing to descend to on the way out — the roster it would dock onto does
		# not exist on this host, and the screen it belongs to is not going anywhere.
		_detail.begin_chrome_descend(_sub_exit_returns_to_detail())


## FORWARD concurrent-group hook (EQUIP G0 on_enter_forward): chrome raise + roster-split seed fire
## TOGETHER at the seam now — the chrome rises WHILE the split runs (user 2026-08-08, concurrent not
## sequential). Composes the former two-group forward seams into the merged group's single hook. The
## EQUIP reverse hook is `_chrome_enter_reverse` directly (the caller seeds play_equip_unslide(0)).
func _equip_concurrent_enter_forward() -> void:
	_chrome_enter_forward()
	_equip_split_enter_forward()


## FORWARD concurrent-group hook (CHANGE_JOB G0 on_enter_forward): chrome raise + roster-split seed
## together (mirror of EQUIP, with the two-row-split targets).
func _changejob_concurrent_enter_forward() -> void:
	_chrome_enter_forward()
	_changejob_split_enter_forward()


## REVERSE concurrent-group hook (CHANGE_JOB G0 on_enter_reverse): the ring fling (the ring group,
## which reverses FIRST) has cleared off-screen and we are now entering the concurrent return group —
## drop the ring + reseed the un-slide (the former split-group reverse barrier) AND reveal the orbs/box
## + arm the chrome descent (the former chrome-group reverse). Both fire at the ONE seam so the chrome
## DESCENT and the roster UN-SLIDE then play out together (user 2026-08-08).
func _changejob_concurrent_enter_reverse() -> void:
	_changejob_reverse_barrier()
	_chrome_enter_reverse()


## FORWARD Equip-split hook (folded into _equip_/_changejob_concurrent_enter_forward): the chrome is
## rising — hide the grid orbs/box (§15.23 RE24: the Equip screen has none near the settled unit) and
## seed the roster split at frame 0 (the Player's split beat drives 1..N). Mirror of the reveal.
func _equip_split_enter_forward() -> void:
	if _formation == null or not is_instance_valid(_formation):
		return
	_formation.set_orbs_visible(false)
	_formation.set_box_trail_visible(false)
	_formation.begin_equip_slide()
	_formation.play_equip_slide(0)               # frame 0 = initial split; the Player drives 1..N


## FORWARD Change-Job-split hook (CHANGE_JOB G1 on_enter_forward): the chrome is up — hide the grid
## orbs/box (§15.24: none on the Change-Job screen) and seed the two-row-split slide at frame 0.
func _changejob_split_enter_forward() -> void:
	if _formation == null or not is_instance_valid(_formation):
		return
	_formation.set_orbs_visible(false)
	_formation.set_box_trail_visible(false)
	_formation.begin_changejob_slide()
	_formation.play_equip_slide(0)               # frame 0 = initial split; the Player drives 1..N


## The recipes the coordinator can play (for the boot-audit guard + diagnostics). Array[Recipe].
func recipe_table() -> Array:
	return _recipes.values()


## Play `recipe` on the one Player — forward, or (reversed) the same groups in reverse order via each
## beat's reverse driver. `on_settled` fires when the last group settles. Records what's mid-flight so
## the semantic queries can name it.
func _play_recipe(recipe: TransitionEngine.Recipe, reversed: bool, on_settled: Callable) -> void:
	_playing_recipe = recipe
	_playing_reversed = reversed
	_player.play(recipe, reversed, func():
		_playing_recipe = null
		if on_settled.is_valid():
			on_settled.call())


## The owned roster to show — the catalogue's owned overlay, and nothing else (ADR-0180:
## one population). There is no second branch to disagree with it.
##
## [b]This used to seed, and seeding here was not a harness wart — it was destructive.[/b]
## The body was `CharacterCatalog.reset_to_new_game()` + [PromotedRosterSeeder] + an
## unlock-every-job pass, under a docstring that said *"a real host would pass the live
## `CharacterCatalog.owned_units()`"*. `reset_to_new_game()` clears `_owned_order` and
## unregisters every slug outside the new-game baseline, so the first real host to mount this
## — the world map's START-menu row — would have wiped the player's owned overlay, and any
## character joined during the walk, on the frame the screen opened. The harness had to leave
## before a navigator arrived, not merely be tidied.
##
## Where it went: [FormationDevBoot], the root of its own `assets/scenes/FormationDev.tscn`. That is the
## same shape [AllTemplatesFormationBoot] already had for the browsing half — the SCENE carries
## the fixture, the SCREEN reads the live catalogue — so the two dev harnesses are now
## symmetric ([AllTemplatesSeeder] browses, [PromotedRosterSeeder] edits) and neither is
## reachable from a hosted mount. ADR-0181.
func _resolve_roster() -> Array:
	return UIRoster.owned_units()


# -----------------------------------------------------------------------------
# ADR-0084 coordinator seam — enter(state) / leave() over the LIFO screen stack, plus the
# current_state()/is_moving() queries input routing + guards read. The reverse of every enter
# is a first-class animation (never an instant snap), so the Esc-teleport bug class is
# unreachable through this seam. The per-screen entry/exit RECIPES are the begin_*/exit_* methods
# below; this layer owns which one plays and keeps the stack + `settled` signal in sync.
# -----------------------------------------------------------------------------

## The current (top-of-stack) screen — IDLE when the roster is bare. Cheap query for input routing.
func current_state() -> int:
	return _stack.back() if not _stack.is_empty() else State.IDLE


## True while ANY entry/exit animation is mid-flight (a per-screen stepper is active, or the detail
## overlay's chrome is transitioning). Input routing swallows presses while this holds so a slide
## can't be interrupted mid-motion; guards use it to assert `leave()` actually started a reverse.
func is_moving() -> bool:
	# The Player covers every ported entry/exit envelope (Equip/Ability + Change-Job, both directions).
	# The ring ROTATION is a steady-state handler (ADR-0084: interaction stays OUT of the engine).
	if _player.is_playing() or _changejob_rot_active:
		return true
	return _detail != null and is_instance_valid(_detail) and _detail.is_transitioning()


## Enter `state` (the selected roster unit is ambient context, read from FormationScene). THE gate:
## every route onto a Formation screen — the coordinator, the two menus, the roster's own ○ — comes
## through here, so this is the single place that decides whether a transition happens at all and the
## single place that pushes the stack. `settled(state)` fires when the entry animation reaches its
## resting screen (per-recipe finishers).
##
## Two refusals, both silent no-ops rather than half-built screens (invariant 2):
##   - you are ALREADY on `state` — re-entering a screen you are on is nothing, not a rebuild;
##   - a precondition is unmet (no roster, no selection, or a state with no entry recipe).
##
## Which recipe runs depends on where you are entering FROM, not just on the target: a sub-screen
## reached from the DETAIL screen (the §15.20 action menu) already has its overlay up and only plays
## the slide, while the same sub-screen reached from the plain roster must build the overlay DOCKED
## first. That pair — (from, to) picks the recipe — is what makes this a state machine and not a
## dispatch table.
func enter(state: int) -> void:
	if state == current_state():
		return                    # already on this screen — an accepted no-op
	if not _can_enter(state):
		return                    # no recipe, or no unit to show it for — an OBSERVABLE gap
	var from := current_state()
	_stack.push_back(state)       # the accepted screen is occupied from here (see `_stack`)
	# The claims belong to the STACK, not to any one screen (ADR-0261) — taken by the push that made it
	# non-empty. Before the entry animation, because the takeover is what freezes the tile cursor and
	# a screen that is still raising itself must not be steerable underneath.
	_take_claims()
	match state:
		State.DETAIL:
			if host_mode == Host.MAP:
				_begin_map_detail()
			else:
				open_detail(_formation.selected_character())
		State.EQUIP, State.ABILITY:
			var mode := SubMode.ABILITY if state == State.ABILITY else SubMode.EQUIP
			if from == State.DETAIL:
				_begin_sub_on_detail(mode)      # §15.23: the overlay is already up — slide only
			else:
				_enter_sub_from_main_menu(mode) # from the roster: build it DOCKED, then slide
		State.CHANGE_JOB:
			if from == State.DETAIL:
				begin_changejob_transition()    # §15.24 RE28, from the action menu
			else:
				_enter_changejob_from_main_menu()
		State.GAMBIT:
			_begin_gambit()                     # #1007: the gambit surface, over whatever is up
		State.PICK:
			_begin_pick()                       # ADR-0261: the deployment pick, as a stack level


## Is there a screen to enter, and something to show on it? IDLE (and any unwired state) has no entry
## recipe; the other four all need a live roster with a selected unit. Kept next to `enter` because a
## precondition IS part of the transition decision — the leaves must never have to second-guess it.
func _can_enter(state: int) -> bool:
	match state:
		State.DETAIL, State.EQUIP, State.ABILITY, State.CHANGE_JOB, State.GAMBIT:
			return _formation != null and is_instance_valid(_formation) \
				and _formation.selected_character() != null
		State.PICK:
			# The pick RAISES the grid that answers "who is selected", so unlike every state above
			# it cannot require a selection first — it requires the OFFER it is about to seed one
			# from. Map host only: a pick over a plain roster would be the roster over itself.
			return host_mode == Host.MAP and _stack.is_empty() \
				and not pick_offer.get("characters", []).is_empty()
		_:
			return false


## Play the Equip/Ability slide on the ALREADY-open detail screen (the §15.20 action-menu route).
func _begin_sub_on_detail(mode: SubMode) -> void:
	if mode == SubMode.ABILITY:
		begin_ability_transition()
	else:
		begin_equip_transition()


## Play the current screen's EXIT recipe — the entry reversed (ADR-0084 invariant 1: every screen
## `enter` accepts is exitable by a first-class reverse, never an instant teardown). The stack is
## popped, and `settled(current_state())` fired, only when that reverse animation SETTLES (in the
## per-recipe teardown handlers), never before. No-op at IDLE.
func leave() -> void:
	match current_state():
		State.DETAIL:
			close_detail()
		State.EQUIP, State.ABILITY:
			_exit_equip_to_main_menu()
		State.CHANGE_JOB:
			_exit_changejob_to_main_menu()
		State.GAMBIT:
			_exit_gambit()
		State.PICK:
			_exit_pick()
		_:
			pass


## Back out of EVERY screen that is up, one animated level at a time, and land at IDLE (ADR-0261).
##
## For the exits that are a DESTINATION rather than a step back: a deployment that has happened, a
## battle that has been committed. ✕ is never this — that is `leave()`, which pops what the back
## grammar says and no more.
##
## [b]Chained HERE rather than by a host awaiting `settled`.[/b] `GambitBattle._close_picker` used
## to arm a `CONNECT_ONE_SHOT` on `settled` and call `leave()` again from the handler, but `settled`
## has eight emitters — the detail box-open, the gambit surface's own enter and exit, the sub-screen
## return — so any of them landing between the arm and the reverse stole the one shot and drove an
## unwind the host never asked for. The stack's owner is the only thing that can sequence its own
## unwind without a signal to race.
func unwind_all() -> void:
	if current_state() == State.IDLE:
		return
	_unwinding = true
	close_action_menu()
	leave()


## True while [method unwind_all] is walking the stack down. Read by [method _emit_settled], which
## is every teardown's last line and therefore the one place that sees each level land.
var _unwinding := false


## Every teardown's final report. It exists so that the two things which must happen AT a resting
## screen — releasing the claims when the stack has emptied, and taking the next step of a chained
## unwind — happen at one seam instead of at each of the eight `settled.emit` sites (ADR-0261).
func _emit_settled() -> void:
	if _stack.is_empty():
		_release_claims()
		_unwinding = false
	settled.emit(current_state())
	if _unwinding and not _stack.is_empty() and not is_moving():
		leave()


## The reverse animation for the screen on top of the stack has RESTED — apply its unwind. The other
## of the stack's two writers (see `_stack`): every teardown ends here, so which screens pop one and
## which unwind wholesale (ADR-0084 / RE25) is stated once, and no teardown gets a vote. Reached
## whichever door started the exit — `leave()`, an Esc branch, or a leaf's instant fallback.
## As of ADR-0261 this is a TABLE READ, not a match. The six match arms it replaced each stated an
## unwind depth in prose beside a `pop_back()`/`clear()`, and the prose is where they drifted apart:
## Change Job cleared the stack on a host where its sibling rows popped one, so ✕ off Item landed on
## Status and ✕ off Change Job landed on the battlefield, one row apart on the same menu.
func _exit_settled() -> void:
	if _stack.is_empty():
		return
	if _unwind_depth(current_state()) == POP_ONE:
		_stack.pop_back()
	else:
		_stack.clear()


## Does ✕ out of the CURRENT sub-screen land back ON the Status screen, rather than unwinding off
## it? THE predicate for ADR-0137 Amendment 7, asked in three places (the stack unwind, the chrome
## beat's reverse, and the teardown), so the three cannot disagree about which exit is happening.
##
## ADR-0084 RE25 — "a sub-screen back-out is a FULL unwind to the roster" — was written for a host
## that HAS a roster. It is still exactly right there: the Equip screen was reached FROM the roster
## as often as from the Status screen, and the roster is where the ✕ grammar bottoms out. The map
## host has no roster; its bottom is the battlefield, and unwinding to it discards the Status screen
## the player was standing on one press ago (user 2026-08-21: "I want it to go to the previous
## state, not exit and go back to the unit").
##
## CHANGE_JOB is included as of ADR-0261 — see [constant _UNWIND_MAP]. This predicate now READS the
## table rather than restating a slice of it, which is the point: the three askers cannot disagree
## with the unwind if there is only one statement of it.
func _sub_exit_returns_to_detail() -> bool:
	if host_mode != Host.MAP:
		return false
	if _stack.size() < 2:
		return false          # nothing underneath to return TO
	return _unwind_depth(current_state()) == POP_ONE \
		and _stack[_stack.size() - 2] == State.DETAIL


## How far ✕ unwinds out of `state` on THIS host — the one read of the back-grammar table (ADR-0261).
## An unwired state has nothing to pop, which is `UNWIND_ALL` on an already-empty stack: a no-op.
func _unwind_depth(state: int) -> int:
	var table: Dictionary = _UNWIND_MAP if host_mode == Host.MAP else _UNWIND_ROSTER
	return int(table.get(state, UNWIND_ALL))


## MAP host DETAIL entry (ADR-0137): pause the battle, take the pad, HOLD the camera, then open the
## menus. The hold is a takeover with no motion — it is what freezes the tile cursor, hides the
## dagger and kills rotation, and that does belong here: the view stops being the player's the
## moment a screen is up.
##
## The MOTION is NOT here (Amendment 5, superseding this ADR's original "pan in, then chrome"). The
## Decision argued the pan must come first so it would be SEEN, but settled Status tiles four opaque
## frames across `y32..231`, so the unit you panned to is behind them — the user played it and
## reported exactly that. It is the sub-screen that narrows the frames to `x14..138` and reveals the
## unit, so the pan+zoom rides in the EQUIP group instead.
##
## Pause + pad ownership are host STATE FLIPS and sit outside the recipe (ADR-0084) — they are not
## animations and have nothing to reverse frame by frame. As of ADR-0261 they are taken by
## [method _take_claims] at the stack's empty→non-empty edge instead of here, because DETAIL is not
## always the bottom: opened over a deployment PICK it is the second level, and re-taking a camera
## the pick already holds re-saves the TAKEOVER pose as the "restore to" pose.
##
## The MAP_DETAIL recipe — the camera hold and its release — therefore plays only when this screen
## IS the bottom. Over a pick there is nothing to hold (it is held) and nothing to pan to (the unit
## is a benched one standing on no tile), so the Status screen opens the self-clocked way the roster
## host opens it.
func _begin_map_detail() -> void:
	if _stack.size() > 1:
		open_detail(_formation.selected_character())
		return
	_recipes["MAP_DETAIL"] = _build_map_detail_recipe()
	_play_recipe(_recipes["MAP_DETAIL"], false, _on_map_pan_settled)


## The camera is held (Amendment 5 — held, not moved; the move belongs to the sub-screen). Open the
## Status screen the same self-clocked way the roster host does; `_on_detail_opened` fires
## `settled(DETAIL)`, which is also what opens the START menu on top of it (Amendment 6).
func _on_map_pan_settled() -> void:
	open_detail(_formation.selected_character())


## The exit pan has eased the camera home. Apply the stack unwind — a screen is vacated once you are
## fully out of it, never before — and then let [method _emit_settled] release the claims, which it
## does only if that unwind emptied the stack.
##
## The release used to be HERE, unconditionally, and that was the lock-out: this handler runs at the
## end of every DETAIL reverse, including the one that lands back on an open deployment PICK, so a
## ✕ out of Status handed the tile cursor back while a full roster grid was still on the display.
func _on_map_pan_released() -> void:
	_track_moving_camera()   # the release ease lands ON the barrier — take the arrived size, not the last stepped one
	_exit_settled()
	_emit_settled()


## Take the MAP host's claims — the battle pause and the camera takeover, which between them stop
## the world and gate the tile cursor. Called by the push that makes the stack non-empty, and by
## nothing else. Idempotent: a second take would re-save the takeover pose as the pose to restore.
func _take_claims() -> void:
	if host_mode != Host.MAP or _claims_held:
		return
	_claims_held = true
	_set_battle_paused(true)
	var host := _map_host()
	if host != null:
		host.begin_hold()     # freeze the tile cursor: the d-pad belongs to whatever is up


## Release them — the pop that empties the stack, and nothing else. The camera goes home on
## `release_takeover`'s own cosine ease (ADR-0041: it lerps to the CURSOR's tile, not to a saved
## position), so this is the start of a motion rather than a snap.
func _release_claims() -> void:
	if not _claims_held:
		return
	_claims_held = false
	var host := _map_host()
	# `is_panning()` is true exactly while this host still holds the takeover, which is what makes
	# this a release and not a second one. When DETAIL was the bottom, the MAP_DETAIL recipe's own
	# reverse released the camera at its FIRST frame — deliberately, so the ease and the beat's
	# barrier overlap and the exit waits for a camera that is actually moving — and by the time this
	# runs the ease has landed. When a PICK was the bottom there was no recipe and no such frame, so
	# this is the release.
	if host != null and host.is_panning():
		host.pan_step_reverse(1)   # release_takeover() — the cursor gets the d-pad back
	_set_battle_paused(false)


## True while this coordinator holds the MAP host's camera + pause claims. For hosts and guards:
## the invariant they exist to state is "held iff the stack is non-empty".
func claims_held() -> bool:
	return _claims_held


## ADR-0037 pause, routed through the injected callable so this coordinator never reaches into the
## battle host. Inert on the roster host (there is no battle to pause) and inert if nothing bound it.
func _set_battle_paused(paused: bool) -> void:
	if host_mode == Host.MAP and pause_battle.is_valid():
		pause_battle.call(paused)


## THE VITALS VIEW FOR THIS HOST — the identity's on the roster, the LIVE unit's on the battlefield.
##
## [method FormationScene.vitals_view_from_character] is the OUT-OF-BATTLE builder and it cannot
## report damage even in principle: [UnitProgression] holds no current HP at all, only
## `get_effective_hp()`, so it writes `current_hp = max_hp` BY CONSTRUCTION. On the roster that is
## the true answer — nobody in a menu has been hit. On the battlefield it never is, and this
## coordinator pushed it at every site, so the Status screen reported FULL HP for a unit the hover
## panel one keypress earlier had just reported as hurt.
##
## The coordinator cannot reach the live unit by itself — it holds a [Character], and the identity
## is exactly the object with no current HP on it. Only the MAP host knows which battlefield [Unit]
## the tile cursor latched, so ASK it, and pass the answer (possibly null) to the null-safe overlay.
## The roster host has no unit and no accessor, and takes the bare builder unchanged.
##
## Every `set_unit_view` in this file goes through here, so the two hosts differ in ONE place. What
## the overlay moves is only what a FIGHT can move — the numerators and the status list; the
## denominators, name, job, level, exp and portrait stay the identity's, which is what keeps the
## equip and Change-Job repaint sites (whose whole job is to show a MOVED denominator) correct.
func _vitals_view(character) -> Dictionary:
	var host := _map_host()
	if host == null:
		return FormationScene.vitals_view_from_character(character)
	return FormationMapHost.vitals_view_for(character, host.selected_battle_unit_for(character))


## Overlay a DetailScene bound to `character` and play the ○-press transition (§15.5).
## Returns the DetailScene so a host/test can drive or inspect it. FFT visuals, OUR data:
## the three views are threaded the same way the standalone boot + the formation panels do.
##
## A LEAF: it builds and animates, and does NOT touch the screen stack (ADR-0084 invariant 5 — only
## `enter()` pushes). Calling it directly therefore shows the screen WITHOUT entering it, which is
## what a screenshot host wants and what gameplay must never do: go through `enter(State.DETAIL)` so
## the gate can refuse a screen already up. It still frees a live overlay and rebuilds — that
## teardown is only safe because `enter()` no longer lets a redundant request reach here.
func open_detail(character, entry := Entry.TRANSITION) -> DetailScene:
	if _detail != null and is_instance_valid(_detail):
		_detail.queue_free()
	_formation.set_unit_info_visible(false)     # hand the docked pair off to the slide
	_formation.set_cell_readouts_visible(false) # blank the grid's per-unit HP readouts (unit sprites stay)
	_formation.set_header_visible(false)        # §15.22: hide the roster sort-header entirely (the Status
	                                            # screen shows its own ◄L1/R1► corner buttons instead)

	var d := DetailScene.new()
	d.name = "DetailOverlay"
	d.autoplay_open = false                     # the transition drives the box-open
	# The Status screen is an OVERLAY — lift its whole real-Z ladder above the formation's so
	# the menus occlude the grid units and the subtractive stripe darkens them (ADR-0077). Set
	# BEFORE add_child: _ready reads it while building every element.
	d.overlay_rung_offset = DetailScene.DEFAULT_OVERLAY_RUNG_OFFSET
	add_child(d)                                # _ready builds the panels over the formation
	d.set_unit_view(_vitals_view(character))
	d.set_nameplate_view(UIUnitNameplate.view_from_character(character, 1))
	d.set_stats_view(DetailScene.stats_view_from_character(character))
	match entry:
		Entry.DOCKED:
			d.prepare_chrome_docked()           # build the overlay parked DOCKED (lower panel closed,
			                                    # band at the roster start); the recipe's chrome BEAT
			                                    # raises it (ADR-0084 — chrome is a first-class beat)
		Entry.SLIDE:
			d.play_entry_slide()                # self-clocked chrome raise (§15.1/§15.6) — a retained
			                                    # DetailScene capability; the sub-screens now enter via
			                                    # DOCKED + the recipe chrome beat, so nothing routes here
		Entry.SETTLE:
			d.settle_open()                     # instant, non-transitional snap (no caller today)
		_:
			d.play_transition()                 # the ○-press vitals slide + box-open
			d.opened.connect(_on_detail_opened, CONNECT_ONE_SHOT)   # settled(DETAIL) at box-open done
	_detail = d
	return d


## The ○-press Status arc finished its box-open — the DETAIL screen is at rest (ADR-0084 seam).
func _on_detail_opened() -> void:
	_emit_settled()


## The screen that owns the pad owns the WHOLE pad. Swallow `event` when it names one of the roster's
## own actions, so a press this screen chose NOT to act on still cannot fall through to the covered
## grid. The routing half of ADR-0084 invariant 5: a screen is either up or it is not, and while it is
## up the grid behind it does not get a vote. Anything outside `_ROSTER_ACTIONS` passes through
## untouched — the debug overlay and the mouse keep working over an open screen.
func _claim_pad(event: InputEvent) -> void:
	if map_input_owned():
		# The MAP host takes the pad WHOLESALE, not by named action (ADR-0137). It has to:
		# `GPUArena._unhandled_input` tests RAW KEYCODES, not actions, so no named-action swallow
		# can reach it — and left leaking, its Space and NavigatorMain's Tab both mutate
		# `combat_active`, resuming the battle underneath an open screen and making the exit unpause
		# an already-running sim. A per-handler guard would also have to be re-applied to every
		# handler added later.
		#
		# Two exceptions, for the reason ADR-0084 gives for its narrower swallow: the MOUSE (so the
		# window stays usable) and the F3 debug bindings (so the overlay that scrubs this very
		# screen's cadence still opens over it).
		if map_pad_exempt(event):
			return
		get_viewport().set_input_as_handled()
		return
	for action in _ROSTER_ACTIONS:
		if event.is_action_pressed(action):
			get_viewport().set_input_as_handled()
			return


## The two events the MAP host's wholesale pad claim lets THROUGH (ADR-0137), for the reason
## ADR-0084 gives for its narrower swallow: the MOUSE, so the window stays usable over an open
## screen, and F3, so the debug overlay that scrubs this very screen's cadence can still be opened
## on top of it. Pure + static so the exemption is one testable statement rather than two `if`s
## buried in a routing function.
static func map_pad_exempt(event: InputEvent) -> bool:
	if event is InputEventMouse:
		return true
	return event is InputEventKey and (event as InputEventKey).keycode == KEY_F3


## True while this coordinator owns the whole pad on the MAP host — while an OVERLAY is up over the
## battlefield, from `enter` accepting it until its reverse has rested.
##
## [b]DERIVED from the stack as of ADR-0261, not a flag.[/b] As a flag it was set by `_begin_map_detail`
## and cleared by `_on_map_pan_released` — one writer each — so it described "the last screen to
## open/close" rather than "a screen is up", and every nesting the map host grew after it (Status
## over a pick) made those two different sentences.
##
## [constant State.PICK] is excluded deliberately, and it is the one state that must be. A pick IS
## the roster grid, and the grid reads the pad through `FormationScene._unhandled_input` — which a
## wholesale claim in `_input` (an EARLIER callback) would swallow before it ever arrived, taking
## the arrows that walk the grid with it. Nothing is unguarded there: the battlefield cursor
## underneath is frozen by the camera takeover, which the pick holds as a claim.
func map_input_owned() -> bool:
	if host_mode != Host.MAP:
		return false
	var s := current_state()
	return s != State.IDLE and s != State.PICK


## Directions are deliberately NOT refused. A one-axis list is not REFUSING left — it simply has no
## left — and buzzing there would train the player to ignore the cue, which is the failure mode this
## whole mechanism exists to avoid.
const _NAV_ACTIONS := ["ui_up", "ui_down", "ui_left", "ui_right"]


## An open list was handed a press it has no verb for. Claim the pad as before, and SAY SO.
##
## This exists because the silence cost two sessions. The map-hosted screen was reported as "the
## START menu opens and its rows draw, but picking one does nothing" — and it was not broken at all:
## the key being pressed was Tab, which was never `ui_accept`, so it fell through every branch to
## `_claim_pad` and was swallowed without a buzz, a log, or any other trace. A WRONG KEY and a BROKEN
## SCREEN produced byte-identical feedback, so the report could not distinguish them and neither
## could the person reading it.
##
## The cue is the one a disabled row already uses (`SfxRouter.play_system("invalid")`), so this adds
## no new vocabulary — it extends an existing refusal to the case that had none.
func _refuse(event: InputEvent) -> void:
	_claim_pad(event)
	if map_pad_exempt(event):
		return          # the mouse and F3 are EXEMPT, not refused — they were never ours to act on
	var is_press := (event is InputEventKey and (event as InputEventKey).pressed \
			and not (event as InputEventKey).echo) \
		or (event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed)
	if not is_press:
		return          # releases and echoes are not a second refusal of the same press
	for nav in _NAV_ACTIONS:
		if event.is_action_pressed(nav):
			return
	print("[FormationDetailTransition] refused: no verb for %s on the open screen" % str(event.as_text()))
	SfxRouter.play_system("invalid")


## Input routing while an overlay is up. Handled in `_input` (BEFORE FormationScene's
## `_unhandled_input`) so the START sub-menu, when open, owns the pad and the roster grid
## behind it does NOT also move. △/Tab on the settled detail screen (re)opens the §15.20 action
## menu; while it is open ↑/↓ navigate, ○/Enter confirms, ×/Backspace backs out. One intent per
## button (ADR-0137 Amendment 4) — and anything else on an open list is REFUSED, not swallowed.
func _input(event: InputEvent) -> void:
	# A screen that is still raising itself does not listen yet (ADR-0172; `CONTEXT.md`'s
	# `Screen-in` is defined as running "before it accepts input"). Gated HERE, at the top of
	# `_input`, because this callback runs BEFORE `FormationScene._unhandled_input`.
	#
	# [b]It SWALLOWS rather than returns, and the difference is the whole gate.[/b] A bare
	# `return` leaves the event unhandled, so it falls straight through to the roster grid's
	# `_unhandled_input` — which is where ○ on the plain roster actually opens a Status screen.
	# Written as a return first, and `FormationScreenInTest` arm D passed anyway because it
	# drove `_input` directly; pushed through the viewport instead, the press opened Status
	# behind a fully black ramp. Ignoring an event and consuming it are different verbs.
	#
	# The mouse and F3 stay exempt, for the reason `_claim_pad` gives: the window has to remain
	# usable and the debug overlay that scrubs this very ramp's cadence has to open over it.
	if screen_in_active():
		if not map_pad_exempt(event):
			get_viewport().set_input_as_handled()
		return
	# §15.26 equipment PICKER: once ○ on a slot row has opened the picker, IT owns the pad — ↑/↓ move
	# among items, × closes back to the §15.25 slot focus. Checked BEFORE the slot-focus block (one
	# level deeper). ○ is the equip COMMIT — confirm() emits `chosen` → _on_equip_picker_chosen equips
	# the focused slot and closes back to slot focus (a slot-illegal pick no-ops, holding the picker).
	if _picker != null and is_instance_valid(_picker):
		if event.is_action_pressed("ui_up"):
			_picker.move_up()
		elif event.is_action_pressed("ui_down"):
			_picker.move_down()
		elif event.is_action_pressed("ui_cancel"):
			_close_equip_picker()
		elif event.is_action_pressed("ui_accept"):
			_picker.confirm()   # §15.26 equip commit → chosen(row)
		else:
			_refuse(event)   # unacted-on — and SAID so, rather than swallowed in silence
			return
		get_viewport().set_input_as_handled()
		return
	# The ability "Set" PICKER (mirror of the equip picker branch): once open it owns the pad —
	# ↑/↓ move among candidates, ○ commits (chosen → _on_ability_picker_chosen), × closes.
	if _ability_picker != null and is_instance_valid(_ability_picker):
		if event.is_action_pressed("ui_up"):
			_ability_picker.move_up()
		elif event.is_action_pressed("ui_down"):
			_ability_picker.move_down()
		elif event.is_action_pressed("ui_cancel"):
			_close_ability_picker()
		elif event.is_action_pressed("ui_accept"):
			_ability_picker.confirm()
		else:
			_refuse(event)   # unacted-on — and SAID so, rather than swallowed in silence
			return
		get_viewport().set_input_as_handled()
		return
	# The Learn ABILITY LIST — phase 1, one level deeper than the job picker, so it is checked
	# FIRST and owns the pad outright while it is up (LEARN_ABILITY_LIST.md §9). ↑/↓ walk the
	# current tab's rows, LEFT/RIGHT step the four ability-type tabs (each keeping its own
	# cursor, `FUN_8012BA7C` bits 0x8000/0x2000), ○ commits or buzzes, × goes back to the
	# job picker — NOT out of the screen (§13.5).
	if _learn_list != null and is_instance_valid(_learn_list):
		if event.is_action_pressed("ui_up"):
			_learn_list.move_up()
		elif event.is_action_pressed("ui_down"):
			_learn_list.move_down()
		elif event.is_action_pressed("ui_left"):
			_learn_list.tab_prev()
		elif event.is_action_pressed("ui_right"):
			_learn_list.tab_next()
		elif event.is_action_pressed("ui_cancel"):
			_close_learn_list()
		elif event.is_action_pressed("ui_accept"):
			_learn_list.confirm()
		else:
			_refuse(event)   # an open screen owns the WHOLE pad — but a refusal is not silence
			return
		get_viewport().set_input_as_handled()
		return
	# The "Learn" job PICKER (mirror of the ability picker branch): once open it owns the pad —
	# ↑/↓ move among the unit's unlocked jobs, ○ JP-gates + commits (chosen →
	# _on_job_picker_chosen; a JP-fail buzzes and stays open), × closes back to the ability
	# list-menu. Checked before the slot-focus block (one level deeper), like its siblings.
	if _job_picker != null and is_instance_valid(_job_picker):
		if event.is_action_pressed("ui_up"):
			_job_picker.move_up()
		elif event.is_action_pressed("ui_down"):
			_job_picker.move_down()
		elif event.is_action_pressed("ui_cancel"):
			_close_job_picker()
		elif event.is_action_pressed("ui_accept"):
			_job_picker.confirm()
		else:
			_refuse(event)   # unacted-on — and SAID so, rather than swallowed in silence
			return
		get_viewport().set_input_as_handled()
		return
	# §15.25 Eqp slot-list FOCUS sub-state: once ○ on "Equip" has handed focus into the panel, the
	# glove walks the slot rows and the (backgrounded) list-menu no longer consumes ↑/↓. Checked BEFORE
	# the list-menu block so the panel owns the pad while focused. × returns focus to the list-menu;
	# ○ on a slot row opens the equipment picker (§15.26).
	if _detail != null and is_instance_valid(_detail) and _detail.is_slot_focused():
		if event.is_action_pressed("ui_up"):
			_detail.slot_cursor_up()
			if _slot_remove_mode:
				_refresh_remove_preview_for_current_slot()   # §15.31: re-gate the compare panel per new slot
		elif event.is_action_pressed("ui_down"):
			_detail.slot_cursor_down()
			if _slot_remove_mode:
				_refresh_remove_preview_for_current_slot()
		elif event.is_action_pressed("ui_cancel"):
			_return_focus_to_menu()
		elif event.is_action_pressed("ui_accept"):
			if _slot_remove_mode:
				_remove_focused_slot()   # §15.31: ○ on the slot row unequips it (mirror of the picker path)
			elif _ability_remove_mode:
				_remove_focused_ability_slot()   # ability "Remove": ○ on the slot CLEARS it (mirror of the commit path)
			elif _sub_mode == SubMode.ABILITY:
				_open_ability_picker()   # ability "Set": ○ on the slot opens the ability picker
			else:
				_open_equip_picker()   # §15.26: ○ on the slot row opens the equipment picker
		else:
			_refuse(event)   # unacted-on — and SAID so, rather than swallowed in silence
			return
		get_viewport().set_input_as_handled()
		return
	# The GAMBIT surface (#1007) — once open it owns the pad outright, like its picker siblings
	# above. It runs its OWN two-level stack internally (row → choice), so the actions go
	# through one door and the surface decides what each level does with them; ✕ at its top
	# level reaches `dismissed` and unwinds this state.
	#
	# SIX now, not four (ADR-0268). ←/→ walk the parts of the focused row, and the two
	# camera-rotate actions raise and lower the focused slot. Both are RE-MEANINGS and not
	# rebindings: while this screen is up it is the only reader of the pad, so no second action
	# is losing a race for the binding — which is the hazard ADR-0137 Amendment 4's
	# one-intent-per-button rule was written against, and why dec. 5 could restate that rule
	# rather than dodge it. The surface adds no action of its own.
	#
	# `handle_action` answering FALSE falls through to `_refuse`, which is why the loop reads
	# its return: the choice list is a column and has no horizontal axis, so ← on it is a
	# refusal the player can hear rather than a press that vanished.
	if _gambit_surface != null and is_instance_valid(_gambit_surface):
		for action in ["ui_up", "ui_down", "ui_left", "ui_right",
				"rotate_camera_cw", "rotate_camera_ccw", "ui_accept", "ui_cancel"]:
			if event.is_action_pressed(action):
				if _gambit_surface.handle_action(action):
					get_viewport().set_input_as_handled()
					return
				break
		_refuse(event)   # an open screen owns the WHOLE pad — but a refusal is not silence
		return
	if _menu != null and is_instance_valid(_menu):
		if event.is_action_pressed("ui_up"):
			_menu.move_up()
		elif event.is_action_pressed("ui_down"):
			_menu.move_down()
		elif event.is_action_pressed("ui_accept"):
			_menu.confirm()
		elif event.is_action_pressed("ui_cancel"):
			_menu.cancel()
		else:
			_refuse(event)   # unacted-on — and SAID so, rather than swallowed in silence
			return
		get_viewport().set_input_as_handled()
		return
	# The Change-Job screen has no list-menu — it owns the pad directly. ←/→ ROTATE the job ring (§15.24
	# RE29, gap 3): RIGHT → next job, LEFT → prev; the ring glides and the title plate updates. ○/Enter
	# COMMITS the front job and leaves; ×/Backspace leaves without committing (the same back behavior as
	# Equip/Ability).
	if is_changejob_exiting():
		# The exit fling owns the pad — swallow all input until it settles (no re-entry, no rotate).
		get_viewport().set_input_as_handled()
		return
	# §10: the commit cutscene owns the pad. ○ and × — and ONLY those two, proven live against all
	# four face buttons — fast-forward it; everything else is swallowed. The latch is remembered
	# even outside the [40,220] window, so an impatient press before frame 40 still fires.
	if is_changejob_committing():
		if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
			_cj_commit.request_skip()
		_claim_pad(event)
		return
	if _changejob != null and is_instance_valid(_changejob) or is_changejob_sliding():
		if event.is_action_pressed("ui_cancel"):
			leave()
		elif event.is_action_pressed("ui_accept"):
			confirm_changejob()
		elif event.is_action_pressed("ui_right"):
			changejob_rotate(1)
		elif event.is_action_pressed("ui_left"):
			changejob_rotate(-1)
		_claim_pad(event)   # the wheel owns the pad WHOLE — ○ must never reach the covered roster
		return
	# The SETTLED Status screen, no menu open. It had NO branch here at all, which is how ○ and △ got
	# to the covered roster in the first place: ○ came back as `unit_activated` (a teardown + rebuild
	# of the very screen you were on) and △ as `dismissed`. Now the screen owns them — △ LEAVES it,
	# and ○ is a no-op because the Status screen has nothing to confirm. START still falls through
	# below to open the §15.20 action menu.
	if current_state() == State.DETAIL and _detail != null and is_instance_valid(_detail):
		if event.is_action_pressed("ui_cancel"):
			leave()
			get_viewport().set_input_as_handled()
			return
	# No menu yet: START opens the action menu. On the detail/Status screen it opens at the detail
	# container (172,120, §15.20); on the PLAIN roster it opens the MAIN-formation menu top-left
	# (10,32, §15.20 grid context / RE round 25, oracle savestate4).
	#
	# NOT on the map host while nothing is open. The ORIGINAL reason (Amendment 2) was a key
	# COLLISION: `formation_start_menu` shared Tab with the map cursor's `unit_inspect`, so claiming
	# it while IDLE swallowed the press and the cursor never saw it. Amendment 4 removed that
	# collision at the source — △/Tab carries BOTH, because they are one intent at two depths — so
	# this guard no longer defends against a shared key.
	#
	# It stays because the SECOND half of that reasoning never depended on the collision: a map has
	# no plain roster, so a MAIN-formation menu over a battlefield is a menu about nothing. The
	# guard now says only that, which is the part that was always true.
	if event.is_action_pressed("formation_start_menu"):
		if host_mode == Host.MAP and current_state() == State.IDLE:
			# A map has no plain roster, so a MAIN-formation menu over a battlefield is a menu
			# about nothing. The `and not _picking()` this used to carry is GONE (ADR-0261): a pick
			# does have a roster to be about, and it now says so by BEING on the stack, so IDLE
			# already means "nothing is up" instead of meaning it except during a pick.
			return
		if _detail != null and is_instance_valid(_detail):
			open_action_menu()
		else:
			open_main_menu()
		get_viewport().set_input_as_handled()
		return
	# Backstop for every branch above that declined to act: if ANY screen is up, the roster behind it
	# does not get the press. On the plain roster (IDLE) this is inert, so normal grid navigation is
	# untouched — the grid only stops acting once something is covering it.
	#
	# PICK is exempt for the reason `map_input_owned()` gives: there the grid IS the screen, and the
	# press it is waiting for arrives through `FormationScene._unhandled_input`, which runs after
	# this callback and never gets the event if this claims it.
	if current_state() != State.IDLE and current_state() != State.PICK:
		_claim_pad(event)


## World position of a virtual-screen pixel — the SAME mapping `FormationScene` and `DetailScene`
## answer, declared here because this coordinator is itself a screen root: on the MAP host it is the
## node carrying the ×1.3125 mount transform, so display space is measured from HERE.
##
## It exists for `UI3ClipEngine.clip_basis_inv_for`, which walks an element's ancestors for the
## nearest node answering this and takes its transform as the clip basis. Children this coordinator
## parents DIRECTLY -- the StartActionMenu, which hangs off the coordinator and not off the
## DetailScene -- used to walk past it and find nothing, falling back to IDENTITY. Identity is right
## on the roster host (that root sits at the world origin) and wrong on the map host, so every
## OWN_APERTURE / PARENT_APERTURE element of the menu discarded every fragment while its UNCLIPPED
## title tab and glove drew fine: a menu that looked like it had failed to open.
##
## That is ADR-0137 Amendment 1 §4's bug exactly, in the one path that fix could not reach -- it
## corrected the SHADERS and the basis lookup, but the lookup can only find a basis somebody
## declares. Amendment 2.
func screen_to_world(px: float, py: float) -> Vector3:
	return Vector3(px * FormationScene.PIXELS_PER_UNIT, -py * FormationScene.PIXELS_PER_UNIT, 0.0)


## Overlay a [StartActionMenu] on the current detail screen (§15.20) and play its box-open.
## Returns the menu (a host/test can drive or inspect it). Its fold real-Z base sits above the
## detail overlay behind it (StartActionMenu.DEFAULT_MENU_RUNG), so it occludes the Status chrome.
func open_action_menu() -> StartActionMenu:
	if _detail == null or not is_instance_valid(_detail):
		return null
	if _menu != null and is_instance_valid(_menu):
		return _menu
	var m := StartActionMenu.new()
	m.name = "StartActionMenu"
	# A host's own rows and home, if it supplied any — BEFORE add_child, which is the handshake
	# `rows` and `location` have always had (`_ready` builds from both).
	if not action_rows.is_empty():
		m.rows = action_rows
		# An explicit host home wins; otherwise the row set picks its own twin of the home the
		# ROM's five would have used (#1007) — a four-row list in a five-row box leaves a dead
		# row of frame under it, which reads as a menu that failed to build its last row.
		m.location = action_menu_location if action_menu_location != "" \
			else StartActionMenu.home_for(action_rows, m.location)
	_apply_ownership(m)                         # BEFORE add_child — the build reads the ink state
	add_child(m)                                # _ready builds + plays the box-open
	m.chosen.connect(_on_menu_chosen)
	m.cancelled.connect(_on_menu_cancelled)
	_menu = m
	if _detail != null:
		_detail.set_backgrounded(true)   # §15.21: send the Status windows to background while the menu is up
	return m


## Open the MAIN-formation START menu (§15.20 grid context / RE round 25) — the SAME 5-item
## StartActionMenu widget, but at the TOP-LEFT container (10,32) over the plain roster instead of
## the detail-screen (172,120). Opened by pressing START on the roster (no detail overlay up), and
## the screen the Equip flow returns to on esc. Returns the menu (a host/test can drive/inspect it).
func open_main_menu() -> StartActionMenu:
	if _menu != null and is_instance_valid(_menu):
		return _menu
	var m := StartActionMenu.new()
	m.name = "MainStartMenu"
	# Open OPPOSITE the selected unit's screen half so the menu never overlaps it (§15.20 RE26,
	# oracle ss4/ss6): unit on the LEFT half → menu top-RIGHT (172,32); unit on the RIGHT half →
	# menu top-LEFT (10,32). Policy returns a KEY-LOCATION slug (ADR-0088 Amendment 2): the
	# orchestrator asks policy, then picks the location BEFORE add_child (_ready derives from it).
	var unit_cx := 999.0
	if _formation != null and is_instance_valid(_formation):
		unit_cx = _formation.selected_unit_screen_center().x
	m.location = StartActionMenu.main_container_for(unit_cx)
	# rows default to the 5-item ROWS (Item/Ability/Change Job/Remove Unit/Order Unit); a host
	# that supplied its own replaces them AND their home, BEFORE add_child (#941).
	if not action_rows.is_empty():
		m.rows = action_rows
		m.location = action_menu_location if action_menu_location != "" \
			else StartActionMenu.home_for(action_rows, m.location)
	_apply_ownership(m)
	add_child(m)
	m.chosen.connect(_on_main_menu_chosen)
	m.cancelled.connect(_on_main_menu_cancelled)
	_menu = m
	return m


## Disable every action row when the selection may not be EDITED right now. The rows stay PRESENT
## and cursorable — this screen is the same screen read-only, not a different one — painted through
## the ROM's own disabled shade band.
##
## Two reasons a selection is not editable, and the screen must not be able to tell them apart:
## it is not the player's unit (ADR-0137), or it is not that unit's turn (#894, design §4). The
## formation host answers both as one predicate, so this asks once.
func _apply_ownership(m: StartActionMenu) -> void:
	if _formation == null or not is_instance_valid(_formation):
		return
	m.set_all_rows_disabled(not _formation.selection_is_steerable())


## A row was chosen on the MAIN-formation menu (0=Item … 4=Order Unit). "Item" (row 0) enters the
## Equip sub-screen (§15.23); the other rows are the separate outer layer (out of scope) — reported
## and closed back to the roster.
func _on_main_menu_chosen(row: int) -> void:
	if _dispatch_menu_row("main menu", row):
		return
	close_action_menu()


## The label showing on `row` of the menu that is up — the ROW SET's own string, whether that set
## is the ROM's five, a host's, or the adjustment four. Empty for an out-of-range row.
func _row_label(row: int) -> String:
	var rows: Array[String] = action_rows if not action_rows.is_empty() else StartActionMenu.ROWS
	return rows[row] if row >= 0 and row < rows.size() else ""


## Act on a chosen row, or hand it back to the host. Returns true when the row was CONSUMED here.
##
## One function for both menus. `_on_menu_chosen` (the detail-screen menu) and
## `_on_main_menu_chosen` (the roster/battlefield menu) had the same body twice and the same
## comment twice, and #941 found out the hard way that a rule stated in only one of them is a
## rule that does not hold: a host-rows check on only the detail path sent the deployment pick's
## row 0 into the Equip screen.
func _dispatch_menu_row(which: String, row: int) -> bool:
	var label := _row_label(row)
	print("[FormationDetailTransition] %s chose row %d = %s" % [which, row, label if not label.is_empty() else "?"])
	if MENU_LABEL_STATE.has(label):
		enter(int(MENU_LABEL_STATE[label]))
		return true
	if not action_rows.is_empty():
		# Not ours to interpret (#941): the rows came from the host and this label is not one of
		# our verbs, so the choice goes back to it.
		action_row_chosen.emit(row)
		return true
	return false


## ×/Backspace on the MAIN-formation menu backs out to the plain roster.
func _on_main_menu_cancelled() -> void:
	close_action_menu()
	# No `leave()` here, unlike `_on_menu_cancelled`: this menu opens over the plain roster, and
	# backing out of it puts the player on the grid, which IS a destination — during a deployment
	# pick it is the picker itself. ✕ again dismisses the grid.


## Enter a sub-screen (Equip or Ability) FROM the main-formation menu: close the menu, build the
## detail overlay parked DOCKED, then play the EQUIP recipe forward — its ONE concurrent group SLIDES
## the top chrome up (§15.1/§15.5) WHILE the §15.23 roster slide runs (they play together, not
## sequenced). Mirrors the detail-screen path (open_detail → begin_*_transition). One helper for both rows.
func _enter_sub_from_main_menu(mode: SubMode) -> void:
	if _formation == null or not is_instance_valid(_formation):
		return
	var character = _formation.selected_character()
	if character == null:
		close_action_menu()
		return
	_park_menu()   # §15.23: PARK the main menu (hidden) — begin_*_transition RE-HOMES it as the sub-menu
	# Build the overlay parked DOCKED; the EQUIP recipe's ONE concurrent group raises the shared top
	# chrome (vitals+nameplate PAIR) DOCKED→TOP (§15.1/§15.5) — no longer a "binary flip" snap — WHILE
	# the split slide runs alongside it. Reverse (Esc) descends the chrome as that same group reversed.
	open_detail(character, Entry.DOCKED)
	if mode == SubMode.ABILITY:
		begin_ability_transition()
	else:
		begin_equip_transition()


## Back out of the Equip/Ability sub-screen (×/Backspace) → the plain roster + top-left START menu,
## ANIMATED as the REVERSE of the entry (ADR-0084): replay the EQUIP recipe REVERSED — the ONE
## concurrent group runs the roster UN-SLIDE back to the grid AND the top chrome DESCENT (TOP→DOCKED +
## §15.6 band cross-fade run backward) TOGETHER, with the orb/box reveal at the seam. The chrome descent
## + reveal FALL OUT of the reversed recipe (invariant 1) — no separately-authored exit slide, no
## `closed`-signal gate. The teardown
## (free the list-menu + detail overlay, restore the roster, reopen the main menu) is the recipe's
## on_settled. Falls back to an instant teardown if the screen never fully opened (still sliding in) or
## an exit is already running. NOT a stack unwind to the detail screen behind it.
func _exit_equip_to_main_menu() -> void:
	if _sub_exiting:
		return
	_exit_slot_remove_mode()   # §15.31: clear the remove flag/preview on any full-screen teardown
	_ability_remove_mode = false   # likewise clear the ability "Remove" flag on any full-screen teardown
	# Is the sub-screen fully settled (lower panel open + a cluster to descend)? Decide BEFORE
	# closing the menu — is_equip_screen_open() also requires the menu, which we're about to free.
	var settled := not is_equip_sliding() and _detail != null and is_instance_valid(_detail) \
		and (_detail.equip_only or _detail.ability_only) \
		and _detail._cluster != null and is_instance_valid(_detail._cluster)
	close_action_menu()
	# Not fully settled (still sliding in, or no cluster to slide) → the old instant teardown.
	if not settled:
		_teardown_sub_screen()
		return
	_sub_exiting = true
	# SEQUENTIAL back-out (user 2026-08-08): the lower Eqp/stats panel folds shut FIRST, and only THEN —
	# once it is fully closed — does everything else happen at once (the chrome descent + roster un-slide
	# together). So the box-close leads; `lower_closed` gates the reversed recipe. DetailScene._process
	# drives the box-close; when it fires, _begin_sub_exit_reverse seeds the un-slide + plays the recipe.
	if _detail != null and is_instance_valid(_detail):
		_detail.lower_closed.connect(_begin_sub_exit_reverse, CONNECT_ONE_SHOT)
		_detail.play_lower_close()
	else:
		_begin_sub_exit_reverse()


## Second half of the SEQUENTIAL Equip/Ability back-out (gated on the lower-panel box-close finishing):
## now that the menu/panel is shut, replay the EQUIP recipe REVERSED — the ONE concurrent group runs the
## roster un-slide (play_equip_unslide) + the chrome DESCENT TOGETHER ("everything else at once"), with
## the orb/box reveal deferred to teardown. on_settled = _teardown_sub_screen.
func _begin_sub_exit_reverse() -> void:
	if _formation != null and is_instance_valid(_formation):
		_formation.play_equip_unslide(0)
	_play_recipe(_recipes["EQUIP"], true, _teardown_sub_screen)


## True while the animated Equip/Ability back-out is playing (roster un-slide + chrome descent) — the
## whole envelope, from the exit start until the reversed recipe settles into _teardown_sub_screen.
func is_equip_exiting() -> bool:
	return _sub_exiting


## Free the Equip/Ability list-menu + detail overlay and restore the roster to the docked baseline,
## then reopen the top-left main-formation menu. Shared by the animated exit (on settle) and the
## instant fallback.
func _teardown_sub_screen() -> void:
	_sub_exiting = false
	# The chrome descent (DetailScene) can dock BEFORE the roster un-slide the Player is driving
	# finishes — stop the Player so it isn't left "moving" past teardown; redock_units() below snaps
	# the roster docked (the un-slide already had it nearly there), preserving the byte-restore.
	_player.stop()
	_playing_recipe = null
	close_action_menu()
	# ADR-0137 Amendment 7: on the MAP host this exit RETURNS to the Status screen. Everything below
	# — freeing the overlay, restoring a roster, releasing the camera — is the vocabulary of LEAVING,
	# and none of it applies. Asked before `_exit_settled()` runs, because that is what pops the
	# state the predicate reads.
	if _sub_exit_returns_to_detail():
		_return_sub_screen_to_detail()
		return
	if _detail != null and is_instance_valid(_detail):
		_detail.queue_free()
		_detail = null
	_restore_formation()       # un-slide (redock) + restore orbs/box/readouts/band/header/cluster
	if host_mode == Host.MAP:
		# There is no plain roster to return to, so there is no MAIN menu to open over it — the
		# battlefield IS the exit. What there IS, and what this path never did, is a camera still
		# HELD, a battle still paused and a pad still owned: a sub-screen back-out is a FULL unwind
		# on this host (`_exit_settled`, RE25), so it has to unwind all of it, not just the panels.
		# The MAP_DETAIL hold beat's reverse is what releases the camera, and `release_takeover()`
		# eases the body AND the ortho size home together — one return for the pan and the zoom.
		# The unwind waits for it, so `current_state()` still reports the sub-screen while the
		# camera is on its way back, exactly as the DETAIL close already does.
		_play_recipe(_recipes["MAP_DETAIL"], true, _on_map_pan_released)
		return
	_exit_settled()            # ADR-0084: the coordinator applies the unwind, not this teardown
	open_main_menu()
	_emit_settled()


## The MAP host's sub-screen back-out has finished its reverse play and lands ON the Status screen
## (ADR-0137 Amendment 7) — the counterpart of the roster host's "restore the roster, reopen the main
## menu" tail, for a host whose bottom is not a roster.
##
## Three things happen and nothing else does. `_restore_formation()` is NOT called: it un-slides a
## grid this host has none of and re-shows the docked vitals pair, which would leave a SECOND pair
## behind the overlay's own. The overlay is NOT freed — it is the screen we are returning to. The
## camera is NOT released: the user chose to keep the sub-screen's framing on the way back
## (2026-08-21), so the zoom comes home only on the final ✕ out of DETAIL — which is what keeps
## `_map_pan_hold_reverse`'s no-op correct after this amendment falsified its original reason.
##
## The lower panel DOES have work: `_exit_equip_to_main_menu` box-closed the narrow Eqp/Ability frame
## on the way out, so the joint §15.19 panel has to be rebuilt and box-opened again.
func _return_sub_screen_to_detail() -> void:
	_exit_settled()            # pops EQUIP/ABILITY → DETAIL (the coordinator owns the unwind)
	# Nothing to widen? Then finish HERE. `exit_sub_mode` is idempotent, so on a screen that never
	# narrowed — the instant-teardown fallback in `_exit_equip_to_main_menu` reaches this while the
	# sub-screen is still sliding in — it no-ops and its `opened` never fires. Waiting on a signal
	# that is not coming would strand the player on a menu-less screen with `settled` never sent.
	if _detail == null or not is_instance_valid(_detail) \
			or not (_detail.equip_only or _detail.ability_only):
		_on_sub_return_opened()
		return
	# The menu and `settled` wait for the box-open to REST, the same way the ○-press Status arc does
	# (`open_detail` → `opened` → `_on_detail_opened`). Opening the menu on the same frame would box
	# it open over apertures still growing underneath it, and `settled` would name a screen that has
	# not arrived. One-shot: this connection is per exit, not per screen.
	_detail.opened.connect(_on_sub_return_opened, CONNECT_ONE_SHOT)
	_detail.exit_sub_mode()    # widen back to the joint §15.19 panel and box-open it


## The joint panel has finished re-opening after a ✕ back onto the Status screen (Am.7) — the screen
## has ARRIVED, so put the START menu back where the player left it and report DETAIL settled.
func _on_sub_return_opened() -> void:
	open_action_menu()         # they came from the START menu; that is where ✕ puts them back
	_emit_settled()


## The action menu returned a chosen row (0..4). Acting on it (Item screen, Change Job, …) is
## the SEPARATE outer layer (§15.20) — out of scope here; we report the choice and close back
## to the detail screen so the loop is drivable.
func _on_menu_chosen(row: int) -> void:
	if _dispatch_menu_row("action menu", row):
		return
	close_action_menu()


## Item → Equip transition (§15.23). Closes the START menu and the LOWER Status panels
## (Eqp/Ability + stats) — the vitals + nameplate cluster STAYS, as the oracle keeps it
## on-screen throughout — then slides the revealed formation unit rows: the selected unit
## settles at (166,173), every other slides off the right edge (SpriteSlideAnimator, ease-in).
## Stepped per menu-tick by _process; ends by reopening the (Eqp) lower panel.
func begin_equip_transition() -> void:
	_sub_mode = SubMode.EQUIP
	_begin_sub_transition()


## Ability sub-screen (§15.23 RE27) — the exact mirror of begin_equip_transition: the SAME slide,
## floor-spotlight retarget, orb/box hide and redock; only the settled panel (ability_only) and the
## list-menu (Set/Remove/Learn) differ (both selected in _finish_sub / _open_sub_menu by _sub_mode).
func begin_ability_transition() -> void:
	_sub_mode = SubMode.ABILITY
	_begin_sub_transition()


func _begin_sub_transition() -> void:
	if _formation == null or not is_instance_valid(_formation):
		return
	_park_menu()   # §15.23: PARK the live menu (hidden) — _finish_sub RE-HOMES it, never teardown+rebuild
	# Recipe seam (ADR-0084): the ONE concurrent group's forward hook raises the chrome + hides the header
	# + hides the orbs/box (§15.23 RE24 — the Equip screen has none near the settled unit; the box-GLIDE
	# math stays live to drive the floor spotlight) + seeds the split, all running together. on_settled=
	# _finish_sub reopens the (Eqp/Ability) lower panel at the group's end.
	_play_recipe(_recipes["EQUIP"], false, _finish_sub)


## Enter the Change-Job screen FROM the main-formation menu (§15.24). Closes the menu, builds a SETTLED
## detail overlay (top chrome: vitals cluster LAYOUT_TOP + ◄L1/R1► pager), then runs the two-row split
## slide. Mirrors _enter_sub_from_main_menu but drives the Change-Job path.
func _enter_changejob_from_main_menu() -> void:
	if _formation == null or not is_instance_valid(_formation):
		return
	var character = _formation.selected_character()
	if character == null:
		close_action_menu()
		return
	if _menu != null and is_instance_valid(_menu):
		_menu.queue_free()
		_menu = null
	# Build the overlay parked DOCKED; the CHANGE_JOB recipe's FIRST group raises the shared top chrome
	# (vitals cluster + pager) DOCKED→TOP (§15.1/§15.5) WHILE it splits the roster, then G1 builds the ring.
	open_detail(character, Entry.DOCKED)
	begin_changejob_transition()


## Change Job transition (§15.24 RE28). Collapses the LOWER Status panels (the vitals cluster + pager
## STAY — they are the Change-Job top chrome), hides the grid orbs/box, then runs the two-row-split
## slide (upper roster rows exit left / lower right, selected → oval centre). Stepped per menu-tick by
## _process; at the end builds the job wheel + the bottom-middle job-title frame.
func begin_changejob_transition() -> void:
	if _formation == null or not is_instance_valid(_formation):
		return
	close_action_menu()
	# Everything is a recipe seam now (ADR-0084): G0's forward hook raises the chrome + hides the header
	# + hides the orbs/box + seeds the split (all concurrent), G1's build barrier builds the ring + title
	# and reports settled. So nothing imperative here but starting the Player forward. Final on_settled is
	# empty — the ring contraction just comes to rest (settled(CHANGE_JOB) already fired at the barrier).
	_play_recipe(_recipes["CHANGE_JOB"], false, Callable())


## Advance the Change-Job roster split slide one logical frame — a thin shim over the Player for
## guards that hand-drive (only while G0, the concurrent chrome+split, is what's playing). The build
## barrier reveals the ring at SLIDE_DURATION; _process advances the Player directly.
func changejob_step() -> void:
	if is_changejob_sliding():
		_player.step()


## Advance the ring entry contraction one menu-tick (§15.24 RE29, gap 2) — a thin shim over the Player
## while G1 (the ring entry) is what's playing. At ENTRY_DURATION the members have settled onto the oval.
func changejob_entry_step() -> void:
	if _is_changejob_entry():
		_player.step()


## Begin a one-step ring rotation (§15.24 RE29, gap 3): ←/→ glides the ring so the next/prev job rotates
## to the front-bottom slot. Ignored until the entry has settled (and not while another rotation glides).
func changejob_rotate(direction: int) -> void:
	if _is_changejob_entry() or _changejob_rot_active:
		return
	if _formation == null or not is_instance_valid(_formation):
		return
	_formation.changejob_begin_rotate(direction)
	_changejob_rot_accum = 0.0
	_changejob_rot_active = _formation.changejob_is_rotating()


## ○/Enter on the Change-Job wheel. §4: the press has THREE outcomes, not two, and none of them
## leaves the screen — the ROM's commit is a 240-frame cutscene played in place (§0/§11).
##
##   - the job the unit is ALREADY in  → a deny cue and nothing else (`DAT_8018bacc = 5`). It is
##     NOT a no-op success: the current job's list entry carries the not-selectable flag, so it
##     can never be committed. The old port treated this as "confirm and leave", which was wrong
##     twice over.
##   - a shown-but-LOCKED job          → the job's DESCRIPTION box (`FUN_801134e8(idx + 0xE800,
##     0x30)`). Note the correction in §4: it tells you what the job IS, not what you are missing.
##   - anything else                   → COMMIT: start the cutscene (§5's five writes), and stay.
##
## Returns whether the cutscene STARTED (the commit itself lands 240 frames later, in
## `_finish_changejob_commit`). Refused while the ring is in motion — there is no settled front
## job mid-glide — and while a commit is already playing.
func confirm_changejob() -> bool:
	if _is_changejob_entry() or _changejob_rot_active or is_changejob_exiting():
		return false
	if is_changejob_committing():
		return false
	if _formation == null or not is_instance_valid(_formation):
		return false
	var character = _formation.selected_character()
	if character == null or character.progression == null:
		return false
	var job_id: String = _formation.changejob_highlighted_job_id()
	if job_id == "":
		return false
	# §4 row 2 — the current job. Deny cue, no box, no commit, and the screen stays up.
	if job_id == character.progression.current_job_id:
		print("[FormationDetailTransition] change job DENIED — already a %s (ROM cue 5)"
			% ChangeJobWheel.job_name(job_id))
		return false
	# §4 row 3 — shown but locked. The ROM opens the job's flavour DESCRIPTION box here.
	# TODO(#change-job): the box itself needs two things this port does not have yet — the 0xE800
	# job-description string table (not in the repo; it lives in the ROM text the fft-ghidra
	# exports do not currently cover) and a 0x30-style message-box element. Until both exist this
	# branch is a named refusal that keeps the wheel up, which is the ROM's control flow minus the
	# text. It is NOT the "requirements not met" error the first RE round assumed it was.
	if not character.progression.is_job_unlocked(job_id):
		print("[FormationDetailTransition] change job LOCKED — %s (ROM opens its description box)"
			% ChangeJobWheel.job_name(job_id))
		return false
	_begin_changejob_commit(job_id)
	return true


## §5 — the commit trigger, one frame, in ROM order. The chrome flag clearing is ONE action with
## TWO visible consequences (§6): the vitals/nameplate/pager stop being emitted *and* the screen's
## own subtractive band starts its fixed 120 → 0 close. A port that models those as two beats is
## modelling one beat twice, which is exactly what the round-50 reading would have produced.
func _begin_changejob_commit(job_id: String) -> void:
	_cj_commit_job = job_id
	_cj_commit = ChangeJobCommitCutscene.new()
	_cj_commit.begin(randi())
	_cj_commit_accum = 0.0
	# The instant chrome CUT. Not a fade, not a slide — the draw call is simply skipped while the
	# animation phase is non-zero (`0x801190AC` gotos the tail, past the banner draw).
	if _detail != null and is_instance_valid(_detail):
		_detail.set_panels_visible(false)
	if _formation != null and is_instance_valid(_formation):
		_formation.begin_changejob_commit(job_id)
	_changejob_commit_apply_frame()


## Advance the cutscene one vsync tick and push the frame. Returns true on the APPLY frame.
func changejob_commit_step() -> bool:
	if _cj_commit == null:
		return false
	var applied := _cj_commit.step()
	_changejob_commit_apply_frame()
	if applied:
		_finish_changejob_commit()
	return applied


## Push the current cutscene frame onto everything it drives: the band's close (a consequence of
## the chrome cut, driven off the same clock), the dissolve fraction, the four gouraud corners and
## the cylinder. All pure reads off the model.
func _changejob_commit_apply_frame() -> void:
	if _cj_commit == null:
		return
	var f: int = _cj_commit.frame()
	if _detail != null and is_instance_valid(_detail):
		_detail.set_vitals_band_factor(ChangeJobCommitCutscene.band_factor(f))
	if _formation != null and is_instance_valid(_formation):
		var revealed := float(_cj_commit.revealed_count()) / float(ChangeJobCommitCutscene.CELLS)
		_formation.changejob_commit_step(f, revealed, ChangeJobCommitCutscene.gouraud_at(f))


## §11 — the end. Apply, rebuild, restore, and STAY. The ROM writes the job to the unit, rebuilds
## the wheel's job list with the flags swapped, restores the chrome flag and returns the subscreen
## id to 3 — the Change-Job screen, cursor unmoved. §11b: the nameplate's job text and the vitals
## HP/MP change (the apply RECOMPUTES stats — 44/44 → 38/38 on the oracle's Squire→Chemist), and
## the title plate LOSES its "Lv. N" line, because the highlighted job is now the current one.
func _finish_changejob_commit() -> void:
	var job_id := _cj_commit_job
	_cj_commit = null
	_cj_commit_job = ""
	var character = _formation.selected_character() if _formation != null and is_instance_valid(_formation) else null
	if character != null and character.progression != null and job_id != "":
		character.progression.change_job(job_id)
		print("[FormationDetailTransition] job changed -> %s (%s)" % [job_id, ChangeJobWheel.job_name(job_id)])
	if _formation != null and is_instance_valid(_formation):
		_formation.end_changejob_commit()
		_formation.rebuild_selected_body()   # the centre avatar is the new job now
	# Restore the chrome flag (`DAT_8018ba25 = DAT_8018bae9`) — panels back, band back to full.
	if _detail != null and is_instance_valid(_detail):
		_detail.set_panels_visible(true)
		_detail.set_vitals_band_factor(1.0)
		if character != null:
			_detail.set_unit_view(_vitals_view(character))
			_detail.set_nameplate_view(UIUnitNameplate.view_from_character(character, 1))
	# The plate re-renders for the SAME highlighted job — which is now the current one, so
	# `_job_level_for` returns 0 and the cream "Lv. N" line goes away (§11b consequence 3).
	if _changejob != null and is_instance_valid(_changejob) and character != null:
		_changejob.update_job(ChangeJobWheel.job_name(job_id), _job_level_for(character, job_id))


## True while the commit cutscene is playing. The wheel is up and the screen has not moved, but
## the pad belongs to the cutscene (only ○/× do anything, and only as the SKIP).
func is_changejob_committing() -> bool:
	return _cj_commit != null


## The cutscene's frame counter, or -1 when nothing is playing. For the guard.
func changejob_commit_frame() -> int:
	return _cj_commit.frame() if _cj_commit != null else -1


## Advance the rotation glide one menu-tick; when it settles, re-render the plate name + Lv for the newly
## front job (the centre avatar + top-right nameplate deliberately DON'T change — §15.24 RE29).
func changejob_rot_step() -> void:
	if not _changejob_rot_active:
		return
	if _formation.changejob_rotate_step():
		_changejob_rot_active = false
		var job_id: String = _formation.changejob_highlighted_job_id()
		if job_id != "" and _changejob != null and is_instance_valid(_changejob):
			var character = _formation.selected_character()
			_changejob.update_job(ChangeJobWheel.job_name(job_id), _job_level_for(character, job_id))


## FORWARD barrier hook (CHANGE_JOB G0→G1): the concurrent chrome+split group is done — ring the centred
## unit with one generic body per gender-appropriate job (§15.24 beat 8), seed the ENTRY contraction
## (frame 0; the Player's G1 beat drives it in), box-open the bottom-middle job-title plate, and report
## the screen settled. Runs BEFORE the ring-entry beat's first frame (invariant: instant work at the seam).
func _changejob_build_barrier() -> void:
	if _formation == null or not is_instance_valid(_formation):
		return
	var character = _formation.selected_character()
	_formation.build_changejob_wheel(character)
	_formation.begin_changejob_entry()
	# The bottom-middle job-title frame shows the HIGHLIGHTED job — at settle, the unit's current job. It
	# BOX-OPENS (§15.24 RE29, gap 1) and carries the cream "Lv. N" line (RE29 / user note).
	var job_id: String = "4a"
	if character != null and character.progression != null:
		job_id = character.progression.current_job_id
	if _changejob != null and is_instance_valid(_changejob):
		_changejob.queue_free()
	_changejob = ChangeJobScreen.new()
	_changejob.name = "ChangeJobTitle"
	_changejob.set_job(ChangeJobWheel.job_name(job_id), _job_level_for(character, job_id))
	add_child(_changejob)
	_emit_settled()   # ADR-0084: the Change-Job entry recipe reached its resting screen


## REVERSE seam work (folded into _changejob_concurrent_enter_reverse, fired at G1→G0 on leave): the
## ring fling has cleared off-screen — drop the ring and reseed the roster un-slide at frame 0 (the
## Player's G0 reverse split beat drives it back). This is the exact seam the old changejob_exit_step
## handled at its phase-0→phase-1 transition.
func _changejob_reverse_barrier() -> void:
	if _formation == null or not is_instance_valid(_formation):
		return
	_formation.clear_changejob_wheel()   # ring is off-screen — drop it
	_formation.play_equip_unslide(0)      # units start fully exited, ready to slide back


## The unit's LEVEL in `job_id` (job_levels 0-8; 1 if never entered) — the "Lv. N" plate value (§15.24 RE29).
## The CURRENT job returns 0 → NO Lv line (oracle: Squire-as-current shows the name only; rotate to another
## job and its "Lv. N" appears — §15.24 RE30). Only prospective jobs display the level you'd have in them.
func _job_level_for(character, job_id: String) -> int:
	if character == null or character.progression == null:
		return 1
	if job_id == character.progression.current_job_id:
		return 0
	return int(character.progression.job_levels.get(job_id, 1))


## True once the Change-Job screen is fully settled (wheel built + title frame up, roster split done).
func is_changejob_open() -> bool:
	return not is_changejob_sliding() and _changejob != null and is_instance_valid(_changejob) \
		and _formation != null and is_instance_valid(_formation) \
		and _formation.changejob_wheel_body_count() > 0


## True while the Change-Job roster SPLIT slide is mid-flight — the Player is playing the CHANGE_JOB
## recipe forward and is on the FIRST group (G0 = the concurrent chrome-raise + roster-split; the build
## barrier crosses G0→G1 to the ring). The split now shares the chrome's group, so it is live from the
## group's first frame, not deferred behind a chrome barrier.
func is_changejob_sliding() -> bool:
	return _player.is_playing() and not _playing_reversed \
		and _playing_recipe == _recipes.get("CHANGE_JOB") and _player.current_group_index() == 0


## True while the ring ENTRY contraction (recipe G1) is mid-flight — CHANGE_JOB forward, SECOND group
## (G0 = concurrent chrome+split, G1 = ring). The rotation handler waits on this so a ←/→ can't glide
## the ring before it has settled onto the oval.
func _is_changejob_entry() -> bool:
	return _player.is_playing() and not _playing_reversed \
		and _playing_recipe == _recipes.get("CHANGE_JOB") and _player.current_group_index() == 1


func changejob_screen() -> ChangeJobScreen:
	return _changejob


## Back out of the Change-Job screen (×/Backspace) → the plain roster + top-left START menu, ANIMATED as the
## REVERSE of the entry (§15.24, user 2026-08-08; oracle × back-out `tmp/cx_*.png`): FIRST the ring
## SPINS + ENLARGES off-screen, THEN the roster UN-SPLITS back in (top-from-left / bottom-from-right)
## WHILE the top chrome DESCENDS — the un-split and the chrome descent play CONCURRENTLY (user confirmed
## "the circle fling happens first THEN the other things go together"). The teardown (free wheel + detail
## overlay, restore chrome, reopen the menu) is GATED on the exit settling — the chrome stays up through
## the fling so the escaping ring vanishes behind it. Falls back to an instant teardown if the screen
## never fully built (still sliding in / no wheel) or an exit is already running.
func _exit_changejob_to_main_menu() -> void:
	if is_changejob_exiting():
		return
	if _formation == null or not is_instance_valid(_formation) or _formation.changejob_wheel_body_count() == 0:
		_teardown_changejob()
		return
	# The bottom job-title plate closes at once (oracle: gone by exit frame ~1).
	if _changejob != null and is_instance_valid(_changejob):
		_changejob.queue_free()
		_changejob = null
	_formation.begin_changejob_exit()   # frame 0: seed the spin+enlarge fling; the Player drives 1..N
	# Play the recipe REVERSED (groups [ring, {chrome,split}]): G1's ring beat via its DISTINCT reverse
	# driver (the fling) first, then (at the merged group's reverse seam) drop the ring + reseed the
	# un-slide + reveal orbs/box + arm the chrome descent, and G0's roster + chrome beats reversed run
	# TOGETHER (un-slide back to the grid WHILE the chrome descends). Final on_settled = _teardown_changejob.
	_play_recipe(_recipes["CHANGE_JOB"], true, _teardown_changejob)


## Advance the animated exit one menu-tick — a thin shim over the Player while the reversed CHANGE_JOB
## recipe is playing (the fling, then the concurrent chrome-descent + roster un-slide). _process
## advances the Player directly.
func changejob_exit_step() -> void:
	if is_changejob_exiting():
		_player.step()


## The instant teardown shared by the animated exit (Player's final on_settled) and the fallback: free
## the wheel + detail overlay, restore + redock the roster (a final snap; the animated un-slide already
## left it docked), and reopen the top-left main menu.
func _teardown_changejob() -> void:
	_player.stop()             # if a fallback teardown pre-empts a running exit, don't leave it "moving"
	_playing_recipe = null
	if _changejob != null and is_instance_valid(_changejob):
		_changejob.queue_free()
		_changejob = null
	if _formation != null and is_instance_valid(_formation):
		_formation.clear_changejob_wheel()
	# ADR-0137 Amendment 7 as amended by ADR-0261: on the MAP host ✕ off the wheel RETURNS to the
	# Status screen it was reached from, exactly as ✕ off Item and Ability do. Everything below —
	# freeing the overlay, restoring a roster, reopening a main menu over a battlefield that has
	# none — is the vocabulary of LEAVING, and none of it applies. The mirror of
	# `_return_sub_screen_to_detail`, minus its panel widening: the wheel never narrowed the joint
	# §15.19 panel, it replaced the screen wholesale, so the overlay underneath is intact.
	if _sub_exit_returns_to_detail():
		_exit_settled()        # pops CHANGE_JOB → DETAIL (the coordinator owns the unwind)
		open_action_menu()     # they came from the START menu; that is where ✕ puts them back
		_emit_settled()
		return
	if _detail != null and is_instance_valid(_detail):
		_detail.queue_free()
		_detail = null
	_restore_formation()
	_exit_settled()            # ADR-0084: the coordinator applies the unwind, not this teardown
	open_main_menu()
	_emit_settled()


## True while the animated back-out is playing (ring fling → roster un-slide) — the Player driving the
## CHANGE_JOB recipe REVERSED. For the guard/capture + the input swallow while the fling owns the pad.
func is_changejob_exiting() -> bool:
	return _player.is_playing() and _playing_reversed and _playing_recipe == _recipes.get("CHANGE_JOB")


## Advance the Equip slide one logical frame — a thin shim over the Player for guards/callers that
## hand-drive; _process advances the Player directly. The recipe's on_settled (_finish_sub) reopens
## the lower panel at SLIDE_DURATION. No-op unless the EQUIP forward slide is what's playing.
func equip_step() -> void:
	if _player.is_playing() and not _playing_reversed:
		_player.step()


func _finish_sub() -> void:
	if _detail != null and is_instance_valid(_detail):
		# §15.23: the lower panel reopens as the surviving sub-screen — the Eqp-ONLY column (RE23)
		# or the Ability-ONLY column relocated LEFT (RE27) — with the dropped half gone and the frame
		# narrowed, leaving the settled unit visible in the terrain gap on the right.
		if _sub_mode == SubMode.ABILITY:
			_detail.enter_ability_mode()
		else:
			_detail.enter_equip_mode()
	_open_sub_menu()   # the reused slot-6 list-menu: Equip/Best/Remove/List OR Set/Remove/Learn (§15.23)
	_emit_settled()   # ADR-0084: the Equip/Ability entry recipe reached its resting screen


## PARK the live START menu (§15.23): hide it, drop its input routing (`_menu` → null) and
## disconnect its choose/cancel wiring, but KEEP the instance in `_parked_menu` so
## _open_sub_menu can RE-HOME it (place_at + set_rows) instead of freeing + rebuilding. A
## no-op when no menu is up (so a double-park from the main-menu path is harmless, and the
## already-parked instance is never clobbered). Un-backgrounds the detail (mirrors the old
## close_action_menu §15.21 reset the sub-transition used to do).
func _park_menu() -> void:
	if _menu == null or not is_instance_valid(_menu):
		return
	_disconnect_menu_signals(_menu)
	_menu.visible = false
	_parked_menu = _menu
	_menu = null
	if _detail != null and is_instance_valid(_detail):
		_detail.set_backgrounded(false)   # §15.21: the parked menu no longer holds focus over the detail


## Disconnect every choose/cancel handler this host may have wired onto `m` (the entry
## context — roster main menu, detail START menu, or sub-menu — decides which). Called
## before a re-home rewires the sub-menu handlers so a stale handler can't ALSO fire.
func _disconnect_menu_signals(m: StartActionMenu) -> void:
	for cb in [_on_menu_chosen, _on_main_menu_chosen, _on_equip_menu_chosen]:
		if m.chosen.is_connected(cb):
			m.chosen.disconnect(cb)
	for cb in [_on_menu_cancelled, _on_main_menu_cancelled, _on_equip_menu_cancelled]:
		if m.cancelled.is_connected(cb):
			m.cancelled.disconnect(cb)


## Open the Item→Equip 4-item list-menu (Equip/Best/Remove/List) — the SAME §15.20 list-menu
## widget re-rendered with the 4-item set (§15.23; the slot-6 window is reused in place). Unlike
## the START menu it is FOREGROUND: it does NOT send the Status windows to background (§15.21 —
## the oracle Equip screen is fully tan, no blue). Returns the menu (a host/test can drive it).
##
## place_at's first production consumer (ADR-0088 Amendment 2 §4): the PARKED live menu is
## RE-HOMED onto the sub-screen's key location + content-swapped in place, and its box-open
## REPLAYS at the new home (§15.17 center-out), instead of teardown+rebuild — matching the ROM's
## in-place slot-6 re-render (§15.23). Falls back to a fresh build if nothing was parked.
func _open_sub_menu() -> StartActionMenu:
	if _menu != null and is_instance_valid(_menu):
		return _menu
	var loc := StartActionMenu.LOC_ABILITY if _sub_mode == SubMode.ABILITY else StartActionMenu.LOC_EQUIP
	var rows: Array[String] = StartActionMenu.ROWS_ABILITY if _sub_mode == SubMode.ABILITY else StartActionMenu.ROWS_EQUIP
	var m: StartActionMenu
	if _parked_menu != null and is_instance_valid(_parked_menu):
		# RE-HOME the surviving instance (§15.23): the window origin carries the move, the
		# rows/frame re-render at the new home, and the box-open replays center-out.
		m = _parked_menu
		_parked_menu = null
		m.place_at(loc)            # §15.23 RE24/RE27: smaller/lower window than START
		m.set_rows(rows)           # content swap in place + selection reset to row 0
		m.visible = true
		m.play_open()              # box-open REPLAYS at the new home (§15.17 center-out)
	else:
		# Fallback: no parked instance (a direct/test entry) — build fresh.
		m = StartActionMenu.new()
		m.rows = rows              # set BEFORE add_child so _ready builds the content
		m.location = loc
		add_child(m)               # _ready builds + box-opens the menu
	m.name = "AbilityActionMenu" if _sub_mode == SubMode.ABILITY else "EquipActionMenu"
	m.chosen.connect(_on_equip_menu_chosen)
	m.cancelled.connect(_on_equip_menu_cancelled)
	_menu = m
	return m


## A sub-screen menu row was chosen — Equip (0=Equip … 3=List) or Ability (0=Set,1=Remove,2=Learn).
## §15.25: choosing "Equip" (row 0) on the EQUIP sub-screen hands INPUT FOCUS from the list-menu into
## the Eqp slot panel — the glove moves onto slot row 0 (R.Hand) and the list-menu goes to background
## (§15.21). ↑/↓ then walk the 5 slot rows (see `_input`). A further ○ (the per-slot item picker) and
## the other rows / the Ability Set-Remove-Learn are the SEPARATE outer layer — out of scope; report.
func _on_equip_menu_chosen(row: int) -> void:
	# §15.25 "Equip" (row 0) AND §15.31 "Remove" (row 2) both hand focus into the Eqp slot panel the SAME
	# way — the live glove walks the slot rows. They differ only in what ○ on a slot does (open the picker
	# vs unequip): "Remove" arms _slot_remove_mode, which the shared `_input` slot-○ branch reads.
	if _sub_mode == SubMode.EQUIP and (row == 0 or row == 2) \
			and _detail != null and is_instance_valid(_detail) and _detail.equip_only \
			and _menu != null and is_instance_valid(_menu):
		_detail.enter_slot_focus()        # glove → Eqp panel slot row 0 (R.Hand)
		_menu.set_backgrounded(true)      # §15.21: the list-menu deactivates (blue) while the panel holds focus
		_menu.set_cursor_visible(false)   # remove the old (list-menu) cursor — one active cursor on screen
		_slot_remove_mode = (row == 2)
		if _slot_remove_mode:
			# §15.31: the dashed compare panel is gated on the STARTING slot's occupancy (R.Hand row 0).
			_refresh_remove_preview_for_current_slot()
		return
	# Ability "Set" (row 0) AND "Remove" (row 1) both hand focus into the ability panel the same way —
	# the glove walks the editable ability slots (secondary/reaction/support/movement; the primary is
	# skipped). They differ only in what ○ on a slot does (open the picker vs CLEAR the slot): "Remove"
	# arms _ability_remove_mode, which the shared `_input` slot-○ branch reads.
	if _sub_mode == SubMode.ABILITY and (row == 0 or row == 1) \
			and _detail != null and is_instance_valid(_detail) and _detail.ability_only \
			and _menu != null and is_instance_valid(_menu):
		_detail.enter_ability_slot_focus()   # glove → ability panel secondary row
		_menu.set_backgrounded(true)          # §15.21: the list-menu deactivates while the panel holds focus
		_menu.set_cursor_visible(false)       # one active cursor on screen
		_ability_remove_mode = (row == 1)
		return
	# Ability "Learn" (row 2) opens the JOB PICKER straight from the menu row (LEARN_PICKER.md §12) —
	# NO slot-focus handoff: the ROM's Learn entry tears the panel down and builds the job list in one
	# beat (§4), so the port skips the Set/Remove slot-focus step entirely.
	if _sub_mode == SubMode.ABILITY and row == 2 \
			and _detail != null and is_instance_valid(_detail) and _detail.ability_only \
			and _menu != null and is_instance_valid(_menu):
		_open_job_picker()
		return
	var label: String = _menu.rows[row] if _menu != null and is_instance_valid(_menu) and row < _menu.rows.size() else str(row)
	print("[FormationDetailTransition] %s menu chose row %d = %s" % [
		"ability" if _sub_mode == SubMode.ABILITY else "equip", row, label])


## Return focus from the Eqp slot list back to the list-menu (×, §15.25): tear the panel cursor
## down and un-background the menu. Does NOT tear the whole Equip screen down (that is the menu's own
## × — `_on_equip_menu_cancelled` — which only fires when the LIST-MENU has focus).
func _return_focus_to_menu() -> void:
	# §15.31: tearing down remove-mode slot focus must drop any open compare preview and clear the flag —
	# a stale _slot_remove_mode must not leak into a later "Equip" session (which shares this slot focus).
	_exit_slot_remove_mode()
	_ability_remove_mode = false   # same for the ability "Remove" flag (no preview to drop)
	if _detail != null and is_instance_valid(_detail):
		_detail.exit_slot_focus()
	if _menu != null and is_instance_valid(_menu):
		_menu.set_backgrounded(false)
		_menu.set_cursor_visible(true)    # the list-menu regains its cursor as focus returns


## §15.31: ○ on a focused Eqp slot row in REMOVE mode unequips that slot directly (the mirror of the
## §15.26 picker COMMIT — "equip nothing"). A non-empty slot → UnitProgression.unequip_item + a
## set_stats_view repaint (icon AND name vanish, stats drop), then STAY in remove slot focus (remove
## more); the now-empty slot re-gates its preview OFF so the base panel shows the real reduced stats.
## An empty slot is a silent no-op (unequip_item returns −1). No inventory ledger — the removed id is
## discarded (mirrors §15.26's first-cut "overwrite, no stock ledger"; no shop economy yet).
func _remove_focused_slot() -> void:
	if _detail == null or not is_instance_valid(_detail) or not _detail.is_slot_focused():
		return
	var character = _formation.selected_character() if _formation != null and is_instance_valid(_formation) else null
	if character == null or character.progression == null:
		return
	var slot: int = _detail.slot_row()                     # UnitProgression.EquipSlot order
	if character.progression.unequip_item(slot) < 0:
		return                                             # empty slot: silent no-op
	# Repaint the Eqp icon column + stats band from the LIVE (now-reduced) progression, then re-gate the
	# preview for this slot — which is empty now, so the panel turns off and the real stats show.
	_detail.set_stats_view(DetailScene.stats_view_from_character(character))
	# ...AND refresh the vitals HP/MP gauge — removing armor lowers HP/MP, which live on the vitals
	# cluster, not the stats band. Must precede the preview re-gate: _refresh_remove_preview_for_current_slot
	# calls set_vitals_preview(false) for the now-empty slot, which re-applies `_current`; refresh it first
	# so the gauge drops to the reduced value instead of reverting to the removed item's HP. (Mirror of the
	# equip-commit refresh above.) Guard: FormationEquipRemoveVitalsTest.
	_detail.set_unit_view(_vitals_view(character))
	_refresh_remove_preview_for_current_slot()


## §15.31: re-evaluate the dashed compare panel for the slot the glove is currently on. Driven by the
## SLOT cursor (not a picker) — a filled slot shows the DASHED preview (like §15.26), an empty slot hides
## it. Only the OCCUPANCY→shown transition matters, so a filled→filled or empty→empty move is a no-op
## (the panel is dashes regardless of item — no close/reopen); the box-open reveal replays empty→filled.
func _refresh_remove_preview_for_current_slot() -> void:
	if _detail == null or not is_instance_valid(_detail):
		return
	var character = _formation.selected_character() if _formation != null and is_instance_valid(_formation) else null
	if character == null or character.progression == null:
		return
	var occupied: bool = character.progression.get_equipped_item(_detail.slot_row()) >= 0
	_set_remove_preview(occupied)


## Drive the §15.31 dashed compare preview to `on`. Reconciles against the DetailScene's ACTUAL preview
## state (`is_stats_preview()`), NOT a private shadow flag — the picker path also writes set_stats_preview
## (and tears the compare down on a DEFERRED box-close), so a shadow flag drifts out of sync and then
## suppresses the diff on a filled slot (the reported bug). Reading the real state makes this idempotent
## and self-correcting on every cursor move. Keeps the live glove + slot panel foreground — deliberately
## SKIP the picker's set_slot_panel_backgrounded / set_slot_cursor_visible(false) (those exist only
## because the picker steals the cursor; remove-mode does not).
func _set_remove_preview(on: bool) -> void:
	if _detail == null or not is_instance_valid(_detail):
		return
	var showing: bool = _detail.is_stats_preview()
	if on:
		# EQUIP_STAT_PREVIEW.md: "Remove" = equip NOTHING, so the delta = preview−base with the
		# candidate empty (-1) = the NEGATED contribution of the item in this slot ("-4 / -5" red,
		# HP "-5"). Recompute EVERY call — a filled→filled slot move changes the occupant, so this
		# is NOT idempotent on the slot the way the old dashes-both-sides preview was.
		var slot: int = _detail.slot_row()
		var delta: Dictionary = EquipStatDelta.compute(-1, _slot_occupant(slot))
		_detail.set_vitals_preview_delta(int(delta.get("hp", 0)), int(delta.get("mp", 0)))
		_detail.set_stats_preview_delta(delta, slot)    # enters preview + (re)builds the compare panel
		if not showing:
			var compare: UI3Element = _detail.stats_compare_element()
			if compare != null:
				compare.open()                          # §15.26 box-open reveal (replays empty→filled)
	else:
		if not showing:
			return                                      # already off — no redundant teardown
		# set_stats_preview(false) synchronously tears the compare panel down (real values return).
		_detail.set_stats_preview(false)
		_detail.set_vitals_preview(false)


## Leave §15.31 remove mode: drop any open compare preview and clear the mode flag. Only forces the
## preview off when we were actually in remove mode — the normal (non-remove) Equip back-out shares this
## via _return_focus_to_menu and must not touch the picker's own preview lifecycle.
func _exit_slot_remove_mode() -> void:
	if _slot_remove_mode:
		_set_remove_preview(false)
	_slot_remove_mode = false


## §15.26: ○ on a focused Eqp slot row opens the equipment PICKER — one level deeper than §15.25. The
## picker takes the active cursor; the Eqp SLOT panel backgrounds (blue), the §15.25 slot glove is
## removed (one active cursor), and the vitals + stats panels flip to preview ("-") mode. The list-menu
## is already backgrounded from §15.25. Only meaningful while slot-focused on the Eqp-only screen.
func _open_equip_picker() -> void:
	if _picker != null and is_instance_valid(_picker):
		return
	if _detail == null or not is_instance_valid(_detail) or not _detail.is_slot_focused():
		return
	var p := EquipPickerMenu.new()
	p.name = "EquipPickerMenu"
	# (round 49, ITEM_EQUIPMENT_DATA.md) rows are BUILT FROM ITEM DATA for the FOCUSED slot:
	# the full slot-legal catalog (every item whose ROM id-range fits the slot — hands take
	# weapons AND shields — descending id), with live roster counts (equipped-across-roster /
	# party-total) on each row. slot_row() order == UnitProgression.EquipSlot order.
	# Job/equippable-by filtering (the ROM's 0x4000 grey rows) is a future layer.
	p.entries = EquipCandidates.build_catalog(_detail.slot_row(), UIRoster.owned_units())
	add_child(p)                                     # _ready builds + box-opens the picker
	p.chosen.connect(_on_equip_picker_chosen)
	p.cancelled.connect(_close_equip_picker)
	# EQUIP_STAT_PREVIEW.md: the compare panel tracks the cursor — recompute preview−base for each
	# item the cursor lands on. Connected AFTER add_child (the build's own emit can't be caught), so
	# the INITIAL selection is pushed explicitly below.
	p.selection_changed.connect(_push_equip_delta_for_row)
	_picker = p
	_detail.set_slot_panel_backgrounded(true)       # §15.26: the Eqp slot panel blues (§15.21 swap)
	_detail.set_slot_cursor_visible(false)          # remove the §15.25 slot glove — one active cursor
	# Fill the stats + vitals compare panel with the SIGNED delta of the first-highlighted item
	# (this also enters preview mode + builds the compare element). preview−base over the focused slot.
	_push_equip_delta_for_row(p.selected_row())
	# ADR-0088 amendment §5: the ORCHESTRATOR decides WHEN — open the registered compare
	# element alongside the picker via the verb (its criterion names the BOX_OPEN beat).
	# Port-side reveal by product decision; the ROM pops slot 0xb in (see DetailScene notes).
	var compare: UI3Element = _detail.stats_compare_element()
	if compare != null:
		compare.open()
	# HIDE the list-menu frame while the picker owns the right column — the picker window (slot 0xf)
	# stands IN its place (§15.23), so the backgrounded action-menu frame must not show through behind it.
	# Restored in _close_equip_picker. (User-directed: hide the menu when the picker opens.)
	if _menu != null and is_instance_valid(_menu):
		_menu.visible = false


## EQUIP_STAT_PREVIEW.md: compute the signed stat-DELTA for the item under the picker cursor and
## push it into the shared compare panel (stats band + vitals numerators). delta = preview − base =
## contribution(cursor item) − contribution(current occupant of the focused slot); an empty slot
## contributes 0. Weapon fields (wp/wev) colour the Weap.Power row; hp/mp the vitals numerators.
func _push_equip_delta_for_row(row: int) -> void:
	if _detail == null or not is_instance_valid(_detail):
		return
	if _picker == null or not is_instance_valid(_picker) or row < 0 or row >= _picker.entries.size():
		return
	var candidate: int = int(_picker.entries[row].get("id", -1))
	var slot: int = _detail.slot_row()
	var delta: Dictionary = EquipStatDelta.compute(candidate, _slot_occupant(slot))
	_detail.set_stats_preview_delta(delta, slot)
	_detail.set_vitals_preview_delta(int(delta.get("hp", 0)), int(delta.get("mp", 0)))


## The item id currently equipped in `slot` on the selected unit (-1 = empty) — the delta's base.
func _slot_occupant(slot: int) -> int:
	var character = _formation.selected_character() if _formation != null and is_instance_valid(_formation) else null
	if character == null or character.progression == null:
		return -1
	return character.progression.get_equipped_item(slot)


## The picker highlighted a row and pressed ○ → the equip COMMIT (§15.26). Wire the pick to the
## REAL equip mechanic: UnitProgression.equip_item(slot, id) sets the focused slot on the selected
## unit, then the Eqp panel's equipped-item icon column + the stats band repaint from the live
## progression and the picker closes back to §15.25 slot focus.
##
## First cut (user-confirmed): SET the slot — overwrite, no stock ledger / return-to-pool (the port
## has no shop economy yet). Job-equippability (ROM 0x4000 grey rows) and two-hands/two-swords
## legality are unported, so build_catalog lists items can_equip_item still rejects (e.g. a shield
## onto the Right Hand); a rejected pick NO-OPs and holds the picker open (no grey-out layer yet).
func _on_equip_picker_chosen(row: int) -> void:
	if _picker == null or not is_instance_valid(_picker) or row >= _picker.entries.size():
		return
	if _detail == null or not is_instance_valid(_detail) or not _detail.is_slot_focused():
		return
	var character = _formation.selected_character() if _formation != null and is_instance_valid(_formation) else null
	if character == null or character.progression == null:
		return
	var slot: int = _detail.slot_row()                     # UnitProgression.EquipSlot order (== build_catalog input)
	var item_id: int = int(_picker.entries[row].get("id", -1))
	if not character.progression.equip_item(slot, item_id):
		return                                             # slot-illegal pick: no-op, hold the picker open
	# Repaint the Eqp icon column + stats band from the LIVE progression (set_stats_view rebuilds
	# BOTH; the dash-preview persists until the compare panel closes with the picker, then the fresh
	# values show), then close back to §15.25 slot focus (the reused verb un-previews, un-backgrounds
	# the slot panel, and restores the slot glove).
	_detail.set_stats_view(DetailScene.stats_view_from_character(character))
	# ...AND refresh the vitals HP/MP gauge from the live unit. Equipment usually moves HP/MP (armor),
	# which live on the vitals cluster, NOT the stats band. Without this the gauge keeps the stale
	# build-time `_current`, and the deferred set_vitals_preview(false) on close re-applies THAT stale
	# view — so the +N delta shown during preview snaps back to the OLD numerator on commit ("stats
	# don't update as I equip"). Guard: FormationEquipVitalsRefreshTest.
	_detail.set_unit_view(_vitals_view(character))
	_close_equip_picker()


## × on the picker closes it back to the §15.25 slot focus: drop the picker, un-preview the vitals +
## stats, un-background the Eqp slot panel, and restore the slot glove. NOT a whole-screen unwind.
## The picker plays its box-CLOSE (the §15.17 aperture in reverse) and frees itself when shut —
## `_picker` nulls immediately, so input routing + the equip_picker() accessor read "closed" now.
func _close_equip_picker() -> void:
	# Handle dropped before the play, same reason as _close_job_picker (ADR-0097 §3): the
	# docstring's "`_picker` nulls immediately" has to hold for a synchronous close too, so
	# input routing and equip_picker() read "closed" from inside the `closed` handler as well.
	var p := _picker
	_picker = null
	if p != null and is_instance_valid(p):
		p.closed.connect(p.queue_free, CONNECT_ONE_SHOT)
		p.play_close()
	# Restore the list-menu frame the picker hid on open (§15.26 / user-directed).
	if _menu != null and is_instance_valid(_menu):
		_menu.visible = true
	if _detail != null and is_instance_valid(_detail):
		# The compare panel closes ALONGSIDE the picker (amendment §5) — the same beat
		# reversed — and its teardown moves to `closed` (mirror the picker's
		# free-on-closed above): leaving stats preview is what frees the panel.
		var compare: UI3Element = _detail.stats_compare_element()
		if compare != null:
			var d := _detail
			# Deferred: the teardown frees the element, which cannot happen while it is
			# still mid-emit of `closed` ("Attempted to free a locked object").
			compare.closed.connect(func() -> void:
				if d != null and is_instance_valid(d):
					d.set_stats_preview.call_deferred(false), CONNECT_ONE_SHOT)
			compare.close()
		else:
			_detail.set_stats_preview(false)
		_detail.set_vitals_preview(false)
		_detail.set_slot_panel_backgrounded(false)
		_detail.set_slot_cursor_visible(true)       # the §15.25 slot glove returns as focus does


## The equipment picker widget (for the guard / a host to drive or inspect). Null unless open.
func equip_picker() -> EquipPickerMenu:
	return _picker


## The ability picker widget (for the guard / a host to drive or inspect). Null unless open.
func ability_picker() -> AbilityPickerMenu:
	return _ability_picker


## The "Learn" job picker widget (for the guard / a host to drive or inspect). Null unless open.
func job_picker() -> JobPickerMenu:
	return _job_picker


## ○ on a focused ability slot opens the ability PICKER for that slot's class (ABILITY_PICKER.md).
## Candidates come from the full, unit-independent CATALOG (AbilityCandidates.build_catalog, the
## ADR-0197 scaffold that exercises the scroll pipeline) — the gated learned/unlocked sibling
## (AbilityLoadout.candidates) is retained for the one-line revert. The slot panel backgrounds and
## the slot glove hides (one active cursor), mirroring the equip picker but WITHOUT the equip
## stat-delta preview (abilities have no numeric preview). An empty catalog (a non-editable slot)
## no-ops and holds slot focus.
func _open_ability_picker() -> void:
	if _ability_picker != null and is_instance_valid(_ability_picker):
		return
	if _detail == null or not is_instance_valid(_detail) or not _detail.is_slot_focused():
		return
	var character = _formation.selected_character() if _formation != null and is_instance_valid(_formation) else null
	if character == null or character.progression == null:
		return
	# slot_row() is the ability slot index 1..4 == AbilityLoadout.Slot SECONDARY..MOVEMENT.
	var slot: int = _detail.slot_row()
	# ADR-0197 scaffold: source the FULL, unit-independent catalog so the 5-row scroll
	# pipeline gets exercised, instead of the near-empty learned/unlocked set. This is the
	# single revert seam — restore `AbilityLoadout.from_progression(character.progression)
	# .candidates(slot)` (kept intact as the gated sibling) when progression data is real.
	var cands: Array = AbilityCandidates.build_catalog(slot)
	if cands.is_empty():
		return   # non-editable slot (e.g. primary) — hold slot focus (no empty picker)
	var p := AbilityPickerMenu.new()
	p.name = "AbilityPickerMenu"
	p.entries = cands
	add_child(p)                                     # _ready builds + box-opens the picker
	p.chosen.connect(_on_ability_picker_chosen)
	p.cancelled.connect(_close_ability_picker)
	_ability_picker = p
	_detail.set_slot_panel_backgrounded(true)        # the ability slot panel deactivates while the picker holds focus
	_detail.set_slot_cursor_visible(false)           # remove the slot glove — one active cursor
	if _menu != null and is_instance_valid(_menu):
		_menu.visible = false                        # the picker window stands in the menu's place


## The picker highlighted a candidate and pressed ○ → the ability slot COMMIT
## (world_ability_slot_commit): write the picked id back to the unit's persistent progression,
## repaint the panel from the live data, and close back to slot focus.
func _on_ability_picker_chosen(row: int) -> void:
	if _ability_picker == null or not is_instance_valid(_ability_picker) or row >= _ability_picker.entries.size():
		return
	if _detail == null or not is_instance_valid(_detail) or not _detail.is_slot_focused():
		return
	var character = _formation.selected_character() if _formation != null and is_instance_valid(_formation) else null
	if character == null or character.progression == null:
		return
	var slot: int = _detail.slot_row()
	var ability_id: int = int(_ability_picker.entries[row].get("id", -1))
	AbilityLoadout.commit_to_progression(character.progression, slot, ability_id)
	_detail.set_stats_view(DetailScene.stats_view_from_character(character))
	_close_ability_picker()


## Ability "Remove": ○ on a focused ability slot CLEARS it directly (the mirror of the ability
## commit — "set nothing"). A filled slot → AbilityLoadout.clear_in_progression (sub_job_id "" /
## equipped_* -1) + a set_stats_view repaint (the NAME column blanks that slot), then STAY in remove
## slot focus (clear more). The job-fixed primary is skipped (never focusable) and an already-empty
## slot is a silent no-op (clear returns false), mirroring _remove_focused_slot. Abilities carry no
## numeric preview, so there is no compare panel to re-gate on the slot cursor (unlike §15.31 equip).
func _remove_focused_ability_slot() -> void:
	if _detail == null or not is_instance_valid(_detail) or not _detail.is_slot_focused():
		return
	var character = _formation.selected_character() if _formation != null and is_instance_valid(_formation) else null
	if character == null or character.progression == null:
		return
	var slot: int = _detail.slot_row()                     # 1..4 == AbilityLoadout.Slot SECONDARY..MOVEMENT
	if not AbilityLoadout.clear_in_progression(character.progression, slot):
		return                                             # empty/primary slot: silent no-op
	# Repaint the ability NAME column from the LIVE (now-cleared) progression — the slot goes blank.
	_detail.set_stats_view(DetailScene.stats_view_from_character(character))


## × on the ability picker (or a commit) closes it back to slot focus: drop the picker,
## un-background the ability slot panel, and restore the slot glove. NOT a whole-screen unwind.
func _close_ability_picker() -> void:
	if _ability_picker != null and is_instance_valid(_ability_picker):
		_ability_picker.queue_free()
	_ability_picker = null
	if _detail != null and is_instance_valid(_detail):
		_detail.set_slot_panel_backgrounded(false)
		_detail.set_slot_cursor_visible(true)        # the slot glove returns as focus does
	if _menu != null and is_instance_valid(_menu):
		_menu.visible = true


## The ability "Learn" row opens the job PICKER over the full job CATALOGUE — every job
## carrying a learnable ability ([JobCandidates], 80 rows: generic + special + monster),
## NOT the unit's unlocked generics, so the list is populated to its max for the port
## (the job-domain twin of ADR-0197's ability catalogue). The gated
## `progression.get_unlocked_jobs()` stays intact as the revert seam
## (LEARN_PICKER.md §12): a single scrollable text list (the ROM's two non-crossing columns
## are a display-list detail the port drops — LEFT/RIGHT move no cursor there either), the
## cream "JOB" font header (§9.2), and the shared glove cursor. The picker window stands in
## the list-menu's place; NO slot-focus handoff (the ROM tears the panel down and builds the
## list in one beat, §4).
## `start_row` seats the picker's cursor and `band_ramp` says whether the OPEN fades the vitals
## band. Both default to the fresh-press answer (row 0, ramp on); `_close_learn_list` passes
## the restored row and mutes the ramp, because the band is already cleared one level down.
func _open_job_picker(start_row: int = 0, band_ramp: bool = true) -> void:
	if _job_picker != null and is_instance_valid(_job_picker):
		return
	var character = _formation.selected_character() if _formation != null and is_instance_valid(_formation) else null
	if character == null or character.progression == null:
		return
	# Each row carries its four number columns (LEARN_PICKER.md round 10 #5): the picker is a
	# renderer, so the HOST reads them off the progression. Lv. / Next / Jp derive from the
	# SPENDABLE pool exactly as before — only `total` reads the new lifetime accrual — so
	# adding the columns changed no progression behaviour. `next` is the JP still owed toward
	# the next job level.
	var entries: Array = []
	# The row SET is the full job CATALOGUE (JobCandidates), not this unit's unlocked
	# generics: the scaffold's one wiring seam, mirroring how the ability "Set" picker
	# switched to AbilityCandidates (ADR-0197). `progression.get_unlocked_jobs()` is left
	# intact and unreferenced here as the revert seam — flip this one call back to restore
	# the gated list.
	for row in JobCandidates.build_catalog():
		var job_id: String = String(row["id"])
		var lv: int = character.progression.get_job_level(job_id)
		var jp: int = character.progression.get_job_jp(job_id)
		entries.append({
			"id": job_id,
			"name": row["name"],
			"lv": lv,
			"total": character.progression.get_job_jp_total(job_id),
			"next": maxi(0, JobLevelsDatabase.get_jp_for_level(lv + 1) - jp),
			"jp": jp,
		})
	if entries.is_empty():
		return   # nothing unlocked — hold the menu (no empty picker)
	# A picker from a previous close may still be walking its box shut (the handle nulls at
	# close-START, so we get here while the node lives). It would keep publishing band
	# factors over this open's walk — two clocks fighting for one stripe. Drop it now; the
	# new picker owns the band.
	for stale in get_children():
		if stale is JobPickerMenu:
			if stale.band_factor_changed.is_connected(_on_job_picker_band_factor):
				stale.band_factor_changed.disconnect(_on_job_picker_band_factor)
			stale.queue_free()
	var p := JobPickerMenu.new()
	p.name = "JobPickerMenu"
	p.entries = entries
	p.initial_row = clampi(start_row, 0, maxi(0, entries.size() - 1))
	p.band_ramp_on_open = band_ramp
	# Wire BEFORE add_child: _ready box-opens the picker, and frame 0 of that walk already
	# publishes a band factor.
	p.chosen.connect(_on_job_picker_chosen)
	p.cancelled.connect(_close_job_picker)
	p.band_factor_changed.connect(_on_job_picker_band_factor)
	add_child(p)                                     # _ready builds + box-opens the picker
	_job_picker = p
	# The ROM press (§4 / LEARN_PICKER.md round 10 #2) tears the WHOLE detail screen down and
	# builds the job list over the still-lit formation: the ability list-menu AND every
	# DetailScene panel go, while `detail.vitals_band` + the 3D formation (the ROM's window 0)
	# stay. _close_job_picker puts them all back.
	if _menu != null and is_instance_valid(_menu):
		_menu.visible = false                        # the picker window stands in the menu's place
	if _detail != null and is_instance_valid(_detail):
		_detail.set_panels_visible(false)


## The picker's aperture walk drives this screen's vitals stripe (round 10 #3): it fades out
## with the box-OPEN (the measured ROM pairing, LEARN_PICKER.md §4 beat 2). The close does NOT
## ramp it back — the picker holds it cleared and publishes a single 1.0 when the box is shut,
## so the band returns on the same step as the menu and panels. The picker owns the clock; the
## host only forwards it to the panel that owns the band.
func _on_job_picker_band_factor(factor: float) -> void:
	if _detail != null and is_instance_valid(_detail):
		_detail.set_vitals_band_factor(factor)


## The picker highlighted a job and pressed ○ → **Learn PHASE 1**, the ability list
## ([LearnAbilityMenu], ROM `FUN_8011F5F0`). This used to be a stub that auto-resolved the
## job's first unlearned ability and committed it; the real screen lets the player pick.
##
## The handoff is NOT a close-then-open. `LEARN_ABILITY_LIST.md` §1: the Learn entry
## `0x8011ED18` simply sets `DAT_801C854C = 1` and starts calling `FUN_8011F5F0` instead of
## the chooser, so the job picker stops being emitted mid-frame and the ability list plays its
## OWN aperture from stage 0. There is no picker close animation to reproduce — the ROM
## animates opens only (ADR-0182) — so the picker is dropped in one beat and the list opens
## over the same torn-down screen the picker was already standing on.
func _on_job_picker_chosen(row: int) -> void:
	if _job_picker == null or not is_instance_valid(_job_picker) or row >= _job_picker.entries.size():
		return
	var job_id: String = String(_job_picker.entries[row].get("id", ""))
	if job_id.is_empty():
		return
	# Where × comes back to (§13.5: the ROM restores the picker's own 6-byte record).
	_learn_return_row = _job_picker.selected_row()
	var p := _job_picker
	_job_picker = null                       # routing reads "closed" NOW
	if p.band_factor_changed.is_connected(_on_job_picker_band_factor):
		p.band_factor_changed.disconnect(_on_job_picker_band_factor)
	p.queue_free()                           # no close play — see the docstring
	_open_learn_list(job_id)


## Mount the Learn ability list over the (already torn-down) detail screen. The menu is a
## RENDERER — every number it paints is read off the progression here, exactly as
## `_open_job_picker` does for its four columns:
##   Mp    = the record's `mp_cost` (ROM: extension record `+0x0D`);
##   Speed = `ceil(100 / ct)` (ROM prov[8] `0x8011F494`, divides `+0x0C`) — the port's `ct` is
##           the same field, pinned this session against round 4's positive control
##           (ability `0x0B`: `ct 4` → `25`, `mp_cost 6` → `06`, `jp_cost 70` → `0070`);
##   Jp    = `jp_cost` (ROM: common record `+0x00`, the same table the commit spends from).
## `learned` and `affordable` are the ROM candidate array's bits 12 and 14–15 (§8).
func _open_learn_list(job_id: String) -> void:
	if _learn_list != null and is_instance_valid(_learn_list):
		return
	var character = _formation.selected_character() if _formation != null and is_instance_valid(_formation) else null
	if character == null or character.progression == null:
		return
	_learn_job_id = job_id
	var p := LearnAbilityMenu.new()
	p.name = "LearnAbilityMenu"
	p.entries = _learn_entries_for(character, job_id)
	p.job_summary = _learn_job_summary_for(character, job_id)
	# Wire BEFORE add_child — _ready box-opens both panels.
	p.chosen.connect(_on_learn_list_chosen)
	p.refused.connect(_on_learn_list_refused)
	p.cancelled.connect(_close_learn_list)
	add_child(p)
	_learn_list = p


## The ability list's rows for `job_id`, in the database's own order — which reproduces the
## ROM's candidate array order per tab (verified against §13.3's four live tab captures).
func _learn_entries_for(character, job_id: String) -> Array:
	var jp: int = character.progression.get_job_jp(job_id)
	var rows: Array = []
	for a in AbilityDatabase.get_learnable_abilities_for_job(job_id):
		var rec: Dictionary = AbilityDatabase.ABILITIES.get(a.id, {})
		rows.append({
			"id": int(a.id),
			"name": a.name,
			"mp": int(rec.get("mp_cost", 0)),
			"speed": LearnAbilityMenu.speed_from_ct(int(rec.get("ct", 0))),
			"jp": int(a.jp_cost),
			"learned": character.progression.has_learned_ability(a.id),
			"affordable": jp >= int(a.jp_cost),
		})
	return rows


## The top frame's one summary row. Same four columns the job picker's row carries, plus
## `mastered` — the port's reading of the ROM's prov[5] gate (`DAT_801C85D4`, §6/§3.2): every
## learnable of the job already learned, which is what puts `Master!` + the star in place of
## the Next and Jp columns.
func _learn_job_summary_for(character, job_id: String) -> Dictionary:
	var lv: int = character.progression.get_job_level(job_id)
	var jp: int = character.progression.get_job_jp(job_id)
	var learnable: Array = AbilityDatabase.get_learnable_abilities_for_job(job_id)
	var mastered := not learnable.is_empty()
	for a in learnable:
		if not character.progression.has_learned_ability(a.id):
			mastered = false
			break
	return {
		"name": String(JobDatabase.get_job(job_id).get("name", "")),
		"lv": lv,
		"total": character.progression.get_job_jp_total(job_id),
		"next": maxi(0, JobLevelsDatabase.get_jp_for_level(lv + 1) - jp),
		"jp": jp,
		"mastered": mastered,
	}


## ○ on a learnable row — charge the JP and set the learned bit, through the roster
## character's UnitProgression (this file's established mutation pattern). The ROM then
## REBUILDS the candidate list and re-seats the cursor rather than leaving (§9: "either way
## the candidate list is rebuilt"), so the screen stays open and the row it just committed
## flips to `Learned` under the glove.
func _on_learn_list_chosen(entry_index: int) -> void:
	if _learn_list == null or not is_instance_valid(_learn_list):
		return
	if entry_index < 0 or entry_index >= _learn_list.entries.size():
		return
	var character = _formation.selected_character() if _formation != null and is_instance_valid(_formation) else null
	if character == null or character.progression == null:
		return
	var ability_id := int((_learn_list.entries[entry_index] as Dictionary).get("id", 0))
	if not character.progression.learn_ability_from_job(ability_id, _learn_job_id):
		SfxRouter.play_system("invalid")
		return
	if _detail != null and is_instance_valid(_detail):
		_detail.set_stats_view(DetailScene.stats_view_from_character(character))
	_refresh_learn_list(character)


## ○ on a row the ROM refuses (§9's other two branches): unaffordable buzzes
## `FUN_801134E8(0xC009,0x30)`, already-learned sets `bacc = 5`. The port routes both as the
## system-bank "invalid" cue — the raw-id→slug mapping is unresolved, and it is the same cue
## the JP-fail on the job picker already uses.
func _on_learn_list_refused(_entry_index: int) -> void:
	SfxRouter.play_system("invalid")


## Re-derive the list's payload in place after a commit — the JP pool moved, so rows that
## were grey may now be affordable, and the committed row is now `Learned`. The cursor stays
## where it is: the row set does not change, only its flags.
func _refresh_learn_list(character) -> void:
	if _learn_list == null or not is_instance_valid(_learn_list):
		return
	_learn_list.entries = _learn_entries_for(character, _learn_job_id)
	_learn_list.job_summary = _learn_job_summary_for(character, _learn_job_id)
	_learn_list.rebuild()


## × on the ability list — back to the JOB PICKER, not out of the screen. §13.5 traced it
## live: two vsyncs of latency, then `bae3` flips 0→1, `cd824` drops to 2, the provider table
## swaps back and the picker **replays its own aperture open from stage 1**. So the port frees
## the list and constructs a fresh picker, which box-opens exactly as it did the first time.
##
## Two things the replay must NOT redo: the picker's row (restored from `_learn_return_row`,
## the ROM's own 6-byte record) and the vitals band ramp — the band is already cleared down
## here, and re-running the open ramp from frame 0 would flash it to full and fade it out a
## second time. `band_ramp_on_open = false` mutes exactly that, leaving the close's single 1.0
## intact so the band still returns with the rest of the screen when the picker finally shuts.
func _close_learn_list() -> void:
	var p := _learn_list
	_learn_list = null
	_learn_job_id = ""
	if p != null and is_instance_valid(p):
		p.queue_free()
	_open_job_picker(_learn_return_row, false)


## The Learn ability-list widget (for the guard / a host to drive or inspect). Null unless open.
func learn_ability_list() -> LearnAbilityMenu:
	return _learn_list


## × on the job picker (or a commit) closes it back to the ability list-menu (the menu keeps
## its row — the ROM's Learn exit restores the panel the same way). NOT a whole-screen unwind.
##
## The picker PLAYS its box-close (the §15.17 aperture in reverse) and frees itself when shut,
## exactly as _close_equip_picker does: `_job_picker` nulls immediately, so input routing and
## the job_picker() accessor read "closed" NOW while the node animates itself out.
##
## SEQUENCING — the ROM press is TWO beats (LEARN_PICKER.md §4 / round 4 #7): beat 1 tears the
## 0xf panel down, beat 2 opens the aperture and starts the band fade. The close is NOT that
## symmetric reverse: the box shuts 100% FIRST and the whole screen returns in ONE beat after
## it (_restore_after_job_picker, hung off `closed`). Restoring here would shut the box over an
## already-rebuilt screen.
##
## The vitals stripe rides that same single beat (user-directed 2026-08-19: "the closing of the
## panel should happen 100%, then the other stuff all happens at once"). The picker mutes its
## per-frame band publish while closing and emits one 1.0 from `_window.closed`, immediately
## before `closed` — so band, list-menu and panels all land on the same driven frame. Nothing
## to set here; _on_job_picker_band_factor does not guard on `_job_picker`, so that final 1.0
## still arrives after the handle is nulled.
##
## Reversing the open instead (what this used to do) put the band back at ~60% of the FAST
## close and the panels at 100% — one return read as two. That is not an ADR-0084 invariant-1
## violation to fix: invariant 1 governs coordinator RECIPES and positional beats, and this
## picker is self-clocked with the band published as a crossfade. Guard:
## FormationLearnPickerTest slice 4 samples band/menu/panels per driven close frame.
func _close_job_picker() -> void:
	# The handle is dropped BEFORE the close is played, not after (ADR-0097 §3): an IMMEDIATE
	# close settles inside play_close(), so `closed` — and with it _restore_after_job_picker —
	# can run before this function returns. _restore_after_job_picker bails when `_job_picker`
	# still points at a live picker (its abandoned-mid-close guard), so nulling afterwards
	# would make the synchronous case restore NOTHING and leave the screen torn down.
	var p := _job_picker
	_job_picker = null
	if p != null and is_instance_valid(p):
		p.closed.connect(func() -> void:
			_restore_after_job_picker()
			p.queue_free(), CONNECT_ONE_SHOT)
		p.play_close()
	else:
		_restore_after_job_picker()      # nothing to animate — rebuild now


## Beat 1 of the Learn press, played backwards: rebuild in ONE beat everything _open_job_picker
## tore down (round 10 #2) — the ability list-menu and every DetailScene panel. Runs when the
## picker's box has SHUT, never mid-walk. The vitals stripe is NOT set here; the picker's
## `closed` handler publishes its 1.0 on this very step, just before firing this (see
## _close_job_picker) — so the band, the menu and the panels return together.
func _restore_after_job_picker() -> void:
	# A picker abandoned mid-close by a re-open must NOT rebuild the screen: the new picker
	# is standing in its place and has torn it down again. Its `closed` still fires (the
	# open sweeps the node, but the engine can finish the reverse play first — the FAST
	# close makes that overlap routine), so the rebuild is gated on nobody owning the
	# screen. Guard: FormationLearnPickerTest slice 4.
	if _job_picker != null and is_instance_valid(_job_picker):
		return
	if _menu != null and is_instance_valid(_menu):
		_menu.visible = true
	if _detail != null and is_instance_valid(_detail):
		_detail.set_panels_visible(true)


## ×/Backspace on the Equip menu backs out to the MAIN formation + the top-left START menu (user-confirmed):
## the whole Equip screen is torn down (detail overlay + roster slide undone), NOT a stack unwind to
## the detail screen behind it.
func _on_equip_menu_cancelled() -> void:
	leave()


## True while a sub-screen is settled (Eqp-only OR Ability-only panel + its list-menu open).
func is_equip_screen_open() -> bool:
	return not is_equip_sliding() and _detail != null and is_instance_valid(_detail) \
		and (_detail.equip_only or _detail.ability_only) and _menu != null and is_instance_valid(_menu)


## True while the EQUIP/Ability forward roster slide is mid-flight (the ONE "EQUIP" recipe, played
## forward — shared by both sub-screens; the reverse play is the back-out, see is_equip_exiting).
func is_equip_sliding() -> bool:
	return _player.is_playing() and not _playing_reversed and _playing_recipe == _recipes.get("EQUIP")


## The action menu was cancelled (×/Backspace) — close it, back to the detail screen.
func _on_menu_cancelled() -> void:
	# ONE press, ONE level — the menu closes and you are on the screen it was over (ADR-0261). Nothing
	# else: the screen's own ✕ is what leaves the screen, and it is one more press away.
	#
	# [b]This used to ALSO `leave()` whenever the host had supplied rows, and that is the bug in the
	# user's report.[/b] The reasoning (#941) was that a host menu is its screen's only verb — true
	# of the one-row DEPLOY set, whose Status panels show you who you are about to deploy and
	# nothing more. But `action_rows` is not a question about the menu that is closing: the gambit
	# battle host assigns `ROWS_ADJUST` at MOUNT, so the branch fired on every ✕ on that host, and
	# backing out of the action menu tore the whole Status screen down. Over a deployment pick that
	# was worse than surprising — the teardown released the camera takeover with the pick's grid
	# still up, ungating the battlefield cursor under a live screen with no press left that could
	# reach it.
	#
	# The deploy set gets the same rule and is better for it: ✕ on the deploy menu now puts you back
	# on the GRID, which is where a player who did not want this unit wants to be.
	close_action_menu()


## Open the GAMBIT surface (#1007) over whatever is up, and hand it the pad.
##
## The action menu CLOSES rather than parks. The Equip/Ability flows park theirs because
## `begin_*_transition` re-homes the same instance as the sub-screen's own list-menu; this
## surface brings its own list, so a parked menu would be a hidden node waiting for a re-home
## that never comes — which is the leak `close_action_menu`'s safety net exists to catch.
func _begin_gambit() -> void:
	if _formation == null or not is_instance_valid(_formation):
		return
	var character = _formation.selected_character()
	if character == null:
		return
	close_action_menu()
	if _gambit_surface != null and is_instance_valid(_gambit_surface):
		_gambit_surface.queue_free()
	var surface := GambitSurface.new()
	surface.name = "GambitSurface"
	surface.character = character     # BEFORE add_child — `_ready` builds the slot rows from it
	# The imperative row is offered only when BOTH arrive (#1006). Off a battlefield the host
	# supplies neither and `offers_imperative()` is false, so the roster's surface is unchanged —
	# which is the honest answer, not a degradation: out of battle there is no turn to spend an
	# order on and no battle for a charge to be per.
	surface.imperative = imperative_orders
	surface.imperative_unit = int(imperative_unit_for.call(character)) \
		if imperative_unit_for.is_valid() else -1
	surface.imperative_now = imperative_now
	_gambit_surface = surface
	add_child(surface)
	surface.edited.connect(_on_gambit_edited)
	surface.imperative_issued.connect(func(order): imperative_issued.emit(order))
	surface.dismissed.connect(_exit_gambit)
	_emit_settled()


## ✕ off the surface's top level, or a `leave()`. Frees the surface and puts the player back on
## the menu they came from — the DETAIL screen's if one is up, the main one otherwise.
##
## [b]"Otherwise" stops at the battlefield.[/b] Unwinding to an EMPTY stack on the MAP host means
## there is no screen left, and the `formation_start_menu` branch in `_input` already states what
## the main menu means there: *"a map has no plain roster, so a MAIN-formation menu over a
## battlefield is a menu about nothing"* — it refuses to open one at IDLE. This said the opposite,
## in the one route that can reach IDLE from GAMBIT directly: a host that enters `State.GAMBIT`
## off the bottom of the stack ([GambitLabScene]'s `G`) got a five-row Item/Ability/Change Job
## menu left standing over its battlefield on the way out, with the claims already released under
## it. Reached from the action menu — every route that existed before — `_detail` is up and the
## first branch takes it, which is why the contradiction sat here unseen.
func _exit_gambit() -> void:
	if _gambit_surface != null and is_instance_valid(_gambit_surface):
		_gambit_surface.queue_free()
		_gambit_surface = null
	_exit_settled()
	if _detail != null and is_instance_valid(_detail):
		open_action_menu()
	elif not (host_mode == Host.MAP and current_state() == State.IDLE):
		open_main_menu()
	_emit_settled()


## Raise the deployment pick (ADR-0261) — the roster grid over the battlefield, seeded from
## [member pick_offer].
##
## A LEAF, like every other `enter` branch: it builds and animates and does not touch the stack. The
## claims are NOT taken here either — `enter()` took them on the push, which is what lets a Status
## screen open over this pick without a second takeover.
func _begin_pick() -> void:
	var host := _map_host()
	if host != null and host.begin_pick(pick_offer.get("characters", []), pick_offer.get("units", [])):
		_emit_settled()
		return
	# The grid did not come up, so nothing is occupying this level — take the push back rather than
	# leave a PICK on the stack with no screen under it. `_can_enter` already refuses an empty offer,
	# so reaching here means the host itself is gone, and a stranded level would hold the claims (and
	# with them the frozen battlefield cursor) for the rest of the battle.
	_stack.pop_back()
	pick_offer = {}
	_emit_settled()


## ✕ off the bare grid, or the last step of an [method unwind_all]. Drops the grid, the dim and the
## band; the CAMERA is not touched here — `_emit_settled` releases the claims once the stack is
## empty, which is the same seam every other screen's exit lands on.
##
## `pick_ended` carries whether this was a CANCEL, because the two doors mean different things to a
## host and the coordinator is the only thing that can tell them apart: a cancel is `leave()`, a
## completed deployment is `unwind_all()`.
func _exit_pick() -> void:
	var host := _map_host()
	if host != null:
		host.end_pick()
	pick_offer = {}
	var cancelled := not _unwinding
	_exit_settled()
	pick_ended.emit(cancelled)
	_emit_settled()


## A choice landed in the character's gambit list — re-emitted for hosts and guards.
##
## It does NOT mark the adjustment turn touched, and that is not an omission. `touch()` is raised
## by [signal FormationMapHost.unit_act_requested], which fires when ○ opens the screen on a unit
## — and there is no route to this surface that skips that press, because the "Gambit" row is on
## the menu that press opens. Marking it again here would be a second answer to a question already
## answered, and the two could only ever disagree by one being wrong.
func _on_gambit_edited(slot: int) -> void:
	gambit_edited.emit(slot)


## The open gambit surface, or null. For hosts and guards.
func gambit_surface() -> GambitSurface:
	return _gambit_surface


func close_action_menu() -> void:
	if _menu != null and is_instance_valid(_menu):
		_menu.queue_free()
		_menu = null
	# Safety net: free any menu still PARKED for a re-home that never completed (an exit
	# pre-empted the sub-screen mid-slide) — else the hidden instance leaks (§15.23 park).
	if _parked_menu != null and is_instance_valid(_parked_menu):
		_parked_menu.queue_free()
		_parked_menu = null
	if _detail != null and is_instance_valid(_detail):
		_detail.set_backgrounded(false)   # §15.21: back to foreground once the menu closes


func action_menu() -> StartActionMenu:
	return _menu


## Drive the roster's BOTTOM band fade from the detail overlay's transition each frame, so it
## fades OUT in lockstep with the overlay's TOP stripe fading IN (§15.6 cross-fade). The detail
## screen owns only its own top stripe; the formation band lives here, hence this thin driver.
func _process(delta: float) -> void:
	# ADR-0172: the screen-in owns its own vsync debt (a delta-driven tween would finish the
	# open in a third of the time on a 144 Hz panel — ADR-0161's stated reason). It frees
	# itself on landing, so this reference simply goes invalid; do not zero it and keep it.
	if _screen_in != null and is_instance_valid(_screen_in):
		_screen_in.advance(delta)
	if _detail != null and is_instance_valid(_detail) \
			and _formation != null and is_instance_valid(_formation):
		_formation.set_band_fade(_detail.formation_band_factor())
	# Drive EVERY ported entry/exit envelope via the one Player — Equip/Ability AND Change-Job, both
	# directions. It owns the menu-tick accumulator + the MAX_CATCHUP clamp (ADR-0084), so a delta
	# spike / render_unfocused throttle can't collapse a whole transition into one frame (the teleport).
	# Follow the camera EVERY frame on the map host, not just inside the beats that move it. The
	# beats cannot own this: `release_takeover()` eases over its own 16 vsync frames while the
	# reverse beat declares 8 menu ticks, so the beat's last frame lands with the camera still in
	# flight and the correction froze there — measured at x1.0458 (a camera at 10.04) when it should
	# have ridden home to x1.3125. Making the mount a function of the LIVE size instead of a
	# snapshot taken at a beat boundary removes the whole class: whoever moves the camera, and for
	# however long, the correction is right on the next frame.
	#
	# The size compare in `_track_moving_camera` early-outs when nothing moved, so in steady state
	# this is one float comparison per frame and never touches the clip engine.
	_track_moving_camera()
	_player.advance(delta)
	# The ring ROTATION glide (§15.24 RE29, gap 3) is steady-state interaction, NOT an entry/exit
	# envelope — it deliberately stays OUT of the engine (ADR-0084) with its own tick accumulator.
	if _changejob_rot_active:
		var d := minf(delta, _MAX_CATCHUP)
		_changejob_rot_accum += d
		while _changejob_rot_accum >= _EQUIP_TICK:
			_changejob_rot_accum -= _EQUIP_TICK
			changejob_rot_step()
	# The COMMIT cutscene, on its OWN vsync-paced clock (see _COMMIT_TICK). Same MAX_CATCHUP
	# discipline as everything else — a stall must not collapse four seconds into one visible
	# frame — but paced at 60 Hz because that is what the ROM measured at.
	if _cj_commit != null:
		_cj_commit_accum += minf(delta, _MAX_CATCHUP)
		while _cj_commit_accum >= _COMMIT_TICK and _cj_commit != null:
			_cj_commit_accum -= _COMMIT_TICK
			changejob_commit_step()


## Close the detail overlay by playing the transition in REVERSE (Esc). The DetailScene folds
## the panel shut + slides the pair back down; when it reaches the docked layout it emits
## `closed`, and `_on_detail_closed` frees the overlay + restores the roster's own docked pair.
func close_detail() -> void:
	# The action menu goes with the screen it is overlaid on. This used to be unreachable: the
	# menu-up path was ○ and the ○-close ran through the sub-screen teardown, which closes it, while
	# the △ path never had a menu at all. Amendment 6 opens the menu from △ too, so a `leave()` here
	# ORPHANED it — the freed screen left a live `_menu`, which then swallowed the next ○ as a row
	# press. Closing a screen closes what is stacked on it; nothing else can own that.
	close_action_menu()
	if _detail != null and is_instance_valid(_detail):
		if not _detail.closed.is_connected(_on_detail_closed):
			_detail.closed.connect(_on_detail_closed)
		_detail.play_close()
	else:
		_restore_formation()


## The DetailScene finished its reverse transition (docked again) — tear it down and hand the
## docked pair back to the formation, which held its own hidden pair at the same spot.
func _on_detail_closed() -> void:
	if _detail != null and is_instance_valid(_detail):
		_detail.queue_free()
		_detail = null
	_restore_formation()
	if host_mode == Host.MAP and _stack.size() == 1:
		# The chrome is out; now the LAST thing to reverse is the FIRST thing that played — the pan.
		# The unwind waits for it (`_on_map_pan_released`), so `current_state()` still reports DETAIL
		# while the camera is on its way home.
		#
		# ONLY when DETAIL is the bottom (ADR-0261): opened over a deployment PICK it played no pan
		# forward, so there is none to reverse, and reversing one anyway released the takeover that
		# the pick underneath is still relying on to hold the battlefield cursor still.
		_play_recipe(_recipes["MAP_DETAIL"], true, _on_map_pan_released)
		return
	_exit_settled()            # ADR-0084: the coordinator applies the unwind, not this teardown
	_emit_settled()


func _restore_formation() -> void:
	if _formation != null and is_instance_valid(_formation):
		_formation.end_equip_slide()                # clear the Equip spotlight retarget → pool eases back
		_formation.redock_units()                   # un-slide: return every unit to its docked grid cell
		_formation.set_orbs_visible(true)           # §15.23 RE24: bring the grid orbs back
		_formation.set_box_trail_visible(true)      # …and the gold selection box VISUAL
		_formation.set_unit_info_visible(true)
		_formation.set_cell_readouts_visible(true)  # bring the grid's per-unit HP readouts back
		_formation.set_band_fade(1.0)               # restore the bottom band the cross-fade faded out
		_formation.set_header_visible(true)         # §15.22: bring the roster sort-header back
		# A sub-screen can have CHANGED the unit while it was covering the grid — a Change-Job
		# commit recomputes HP/MP and rewrites the job. Re-read it: making the stale readouts
		# VISIBLE again is not the same as making them true.
		_formation.refresh_selection_readouts()


## This screen's SELECTION SOURCE — [FormationScene] on the roster host, [FormationMapHost] on the
## map. Public since #941: the deployment picker opens a pick list on the map host, and "who is
## selected" is the one question that host exists to re-answer. Untyped return because the two hosts
## are the two answers and a caller wanting the map one narrows it itself.
func formation() -> Node:
	return _formation


func detail_overlay() -> DetailScene:
	return _detail


func _on_unit_activated(character) -> void:
	# ○ on a roster unit is an `enter`, not a direct build: routing it through the coordinator is what
	# makes a second ○ on the settled Status screen a no-op instead of a teardown + rebuild + re-push.
	# `character` is FormationScene's own selection, which is exactly what enter(DETAIL) reads back.
	enter(State.DETAIL)


## Set by the MAP host just BEFORE `unit_activated` when the open was an ACT (○) rather than an
## INSPECT (△). One-shot: the menu follows the screen up once, then this clears, so a later △ on the
## same unit does not inherit it.
var _open_menu_on_settle := false


## ○ on a map unit — the same screen as △, plus the START menu once it settles. Deferred to `settled`
## rather than opened here because the map entry is a PAN followed by the panels (ADR-0137): opening
## the menu now would race the pan and land it mid-flight.
func _on_unit_act_requested(_character) -> void:
	if _open_menu_on_settle:
		return
	_open_menu_on_settle = true
	settled.connect(_open_menu_when_detail_settles, CONNECT_ONE_SHOT)


func _open_menu_when_detail_settles(to) -> void:
	_open_menu_on_settle = false
	if to == State.DETAIL:
		open_action_menu()


func _on_dismissed() -> void:
	# ✕/Backspace: if we are on a screen, LEAVE it (the coordinator picks the reverse and owns the
	# unwind). Otherwise the SCREEN itself is finished, and on the roster host that is a hand-back:
	# re-emit `dismissed` so the host mounting us can take the display back.
	if current_state() != State.IDLE:
		leave()
		return
	if host_mode == Host.MAP:
		# The MAP host is PERSISTENT — `_mount_formation_map_screen` builds it at Deployment entry
		# and `_free_command_cursor` frees it with the tile-cursor rig. It never "finishes", so a
		# hand-back here would be a claim that is false rather than merely unheard. ADR-0181.
		print("[FormationDetailTransition] map host: ✕ at rest — nothing to dismiss")
		return
	dismissed.emit()
