class_name WorldMapScene
extends Node2D
## The FFT world-map screen — the scaffold.
##
## Assembles the three pieces and nothing else: [WorldMapAssets] (disc-derived VRAM
## and model), [WorldMapPrimitives] (the generator), [WorldMapRenderer] (the blend
## rules). The state it draws comes from [WorldMapProgress], which is Campaign's
## payload rather than the screen's — see docs/WORLD_MAP_PORT_LIST.md.
##
## [b]The oracle[/b] is `research/working_documents/world_map_captures/wldgen.py`,
## whose output matches the console packet for packet, and its picture is
## `world_map_captures/images/round13_generated_scene.png`. Compare against that,
## not against a percentage — `[[render-atlas-crops-and-look-at-them]]`.
##
## Run it:  godot --path . res://assets/scenes/WorldMap.tscn      (headful — never
## `--headless`, and /usr/local/bin/godot 4.8, never /usr/bin/godot 4.7)

## PSX screen-centred coordinates: framebuffer = screen + (128, 120) (§4).
const SCREEN_ORIGIN := Vector2i(128, 120)
const FB_SIZE := Vector2i(256, 240)
## §22.2 / §28.5, three instruments agreeing to the pixel: the GPU drawing area is
## framebuffer x 0..251, y 8..235. Eight blank rows at the top, four at the bottom,
## four blank columns at the right — applying it took §22's render from 92% to 96.7%.
const DRAW_AREA := Rect2i(0, 8, 252, 228)

## Which capture to reproduce. `ss2` is the more interesting one: it separates the
## three things `ss1` cannot (§30.4).
@export_enum("ss1", "ss2") var fixture: String = "ss1"
## Scale the 256x240 frame up so it is legible on a modern display. 0 = fit the viewport
## at the largest WHOLE zoom, which is the normal case; a fractional zoom would resample
## the console's pixels, which is the one thing this screen must not do. Set it (or
## `--zoom=`) only to force a scale, as the capture rig does.
@export var zoom: int = 0

## Where a capture lands, and the switch that arms one. Empty means "do not capture",
## which is every interactive run.
##
## ADR-0051: a scene never branches on the environment, and the toggle that drives a
## behaviour lives on the node that owns it -- so this is the source of truth and
## [WorldMapDebugPanel] is a thin view onto it, not the other way round. It also gates
## the music: a captured frame is the same either way, and a test that starts the music
## driver is a test that has to stop it.
##
## Set it before the scene enters the tree, or call [method capture_to] after.
@export_global_file("*.png") var capture_path: String = ""

## Which sub-screen the map opens WITH, or "" for the normal interactive boot.
##
## The one knob a debug panel cannot be the whole answer to, and the reason [method rig_arg]
## survives ADR-0051's panel route: these arms are read inside [method _ready], BEFORE the
## screen exists to have a checkbox toggled on it. `townopen`, `screenin` and `town` render
## CONTACT SHEETS rather than one settled frame — a fade and an aperture are pictures, not
## numbers (`[[dont-conflate-my-measurement-with-user-visual-goal]]`), and one `capture_path`
## frame cannot show a curve. A panel button clicked after boot would need the process
## restarted with the choice already made, which is a launch argument with extra steps.
##
## Still a property and not an environment read: the Inspector shows it, the panel can view
## it, and `--menu=` only WRITES it. Same shape as `fixture` and `zoom`.
## Valid: "" (normal boot), "1", "move", "townopen", "screenin", "screenout", "town".
## A plain
## String and not `@export_enum`: Godot rejects an empty enum argument outright
## ("Argument 1 of annotation @export_enum is empty"), and "" is the DEFAULT here.
@export var boot_menu: String = ""

## Emitted when the player leaves the screen. [NavigatorMain.run_world_map] awaits it,
## the same shape the Formation view uses.
signal dismissed()

## Emitted the vsync the [WorldMapScreenIn] ramp lands — the screen is now fully up.
## [b]Check [method screen_in_active] BEFORE awaiting this[/b]: an await armed after the
## signal already fired is dropped, and the navigator would hang on a screen that had
## already finished (§18.2 is the worked example of exactly that shape, from the
## ✕-during-fade case). The ramp only advances inside [method advance], so a
## check-then-await within one frame cannot interleave.
signal screen_in_finished()

## The player pressed ○ over a known node. [b]This is the whole of what the map reports
## to Campaign[/b] — ADR-0117 dec. 8: *"Campaign picks a Scenario, which points at an
## event script, which Cutscene plays"*, so the map never plays anything and never
## decides anything. Nothing subscribes yet; wiring it to the 182 per-node event scripts
## is crossing X1.
signal node_entered(node_1based: int)

## The party marker started walking to [param node_1based], and reached it. Both fire
## on the same walk; [signal node_entered] follows `arrived`.
signal departed(node_1based: int)
signal arrived(node_1based: int)

## A START-menu row that is NOT the map's own was taken — §33.3's table, by window id:
## 7 Formation, 11 Brave Story, 14 Tutorial, 12 Data, 5 Option. Row 0 (Move, window 6) is
## the map's and never comes out here; it opens the place list in place.
##
## [b]This is a report, not a mount[/b] — the same shape as [signal node_entered], for the
## same reason (ADR-0117 dec. 8: the map reports, Campaign decides). The menu has already
## closed by the time this fires, so a subscriber that mounts a screen is not racing a
## window that is still up. [NavigatorMain.run_world_map] is the subscriber that turns
## window 7 into the Formation screen.
signal menu_row_chosen(row: int, window: int)

var assets: WorldMapAssets
var progress: WorldMapProgress
var gen: WorldMapPrimitives
var renderer: WorldMapRenderer
var music: WorldMapMusicPort

## [b]The console's clock is 60 Hz, and both animations are counted in its vsyncs.[/b]
## §21.3 sampled the pin pulse once per vsync over 6,675 frames: ±2 per frame, a 128-frame
## period, *"= 2.133 s at 60 Hz"*. §21.4: the idle is 10 frames a cel, *"a 40-frame
## (0.667 s) cycle"*. Ticking once per RENDERED frame instead ran both at the display's
## refresh rate — measured 143.9 Hz here, so 2.4x fast, which is visible on the party
## marker long before it is visible on the pulse.
const VSYNC_HZ := 60.0
## Drop missed ticks rather than fast-forward through them: after a stall (a scene load,
## a breakpoint) the console would not replay the lost frames either, and burning 300
## ticks in one visual frame looks like a glitch rather than like catching up.
const MAX_CATCHUP_TICKS := 8

## Fractional vsyncs owed, carried between frames so the average rate is exact even
## though no display refresh divides 60 evenly.
var _tick_debt: float = 0.0
## Something other than the clock changed the frame (the cursor moved, the store was
## replaced) and it must be redrawn even on a frame that owes no tick.
var _dirty: bool = false
## Off while capturing: a determinate frame must not depend on what the keyboard is
## doing, and a test that mounts the screen should not be steered by a held key.
## The focus state name this screen pushes (ADR-0177). One per screen, and the string is
## what `Focus.describe()` prints, so it is the map's own name in every diagnostic.
const FOCUS_STATE := "world_map"

## The four pad actions and the component each one drives. §27.6 drove both axes and
## describes the controller as per-axis, so they are independent and diagonals are legal.
const PAD_AXES := {
	&"ui_right": Vector2i(1, 0),
	&"ui_left": Vector2i(-1, 0),
	&"ui_down": Vector2i(0, 1),
	&"ui_up": Vector2i(0, -1),
}

## §30.6 — the pin-pulse counter and its direction bit, driven here rather than read.
var _pulse_c: int = 40
var _pulse_up: bool = true
## The glove bob's frame counter — `FUN_800EC504` reads a free-running timer and takes it
## modulo the table's period, so it runs whether or not a window is open and both windows
## on this screen read the same one. Counted in VSYNCS like everything else here: at this
## machine's measured 143.9 Hz refresh a per-frame tick would bob 2.4x fast.
var _bob_frame: int = 0
## §21.4 / §26.2 — the party marker's idle cycle: frame list 16, four entries at 10
## frames each, cels 16, 17, 16, 18. A 40-frame ping-pong. While the marker is WALKING
## this indexes the fast bank's list instead (24 + facing), which changes at every
## waypoint — §29.6 saw frame lists 26, 26, 27, 27, 26, 28, 27, 26, 27, 28, 29, 28.
var _party_frame: int = 0
var _party_tick: int = 0
var _party_list: int = 16

## The walk in progress, or null. While it runs the cursor is frozen: §29.6's trace shows
## the cursor sitting on the destination node for all 94 vsyncs of the traversal.
var _travel: WorldMapTravel = null

## The [b]reveal animation[/b] in flight, or null — one [CampaignRevealPass] being paced
## across the vsync clock instead of drained inside one frame (ADR-0231, and ADR-0230
## dec. 4, which left exactly this on the map's side).
##
## [b]It is the same kind of state as [member _travel][/b]: the screen holds the input
## frame and consumes nothing, because it is mid-animation. On the console that is not a
## flag either — the reveal's animation page sits ABOVE mode 0 in the page stack
## (`0x800BB4F0`), so `FUN_8006C9FC`, the ○/START handler, is not ticked at all while one
## runs. [method held_direction] and [method _unhandled_input] are where that lands here,
## and it is a game-state gate rather than a sixth answer to "who has input" (ADR-0177).
var _reveal: WorldMapRevealAnimation = null
## The node an arrival is waiting to finish at, or 0 — see [method _arrive_at]. Arriving
## runs a pass, and the town page or [signal node_entered] must not land over one that is
## still drawing.
var _arrival_pending: int = 0

## [b]What the pad is holding, accumulated from EVENTS.[/b] This used to be read straight
## off the [Input] singleton every frame, and that poll was the one thing Focus structurally
## could not gate: `set_process_unhandled_input(false)` stops Godot CALLING a non-holder, it
## cannot stop one ASKING. `held_direction()` therefore had to test `Focus.holds(self)` by
## hand — a branch on the flag ADR-0177 exists to delete, kept alive by the poll underneath
## it.
##
## Tracked here instead, the gate is the delivery itself: while a window holds the frame
## Godot does not call [method _unhandled_input] at all, so this vector cannot GROW while
## the map is deaf. What delivery alone cannot do is SHRINK it — a release that lands while
## another state holds focus is never delivered here — so [method _on_focus_changed] clears
## it on every transition this screen does not win. Losing a press across a window's whole
## lifetime is the correct reading of the two together: the console cannot have observed a
## hold it was never told about either.
var _held_dir := Vector2i.ZERO

## Screen state, not campaign state — see [WorldMapCursor]. The node it rests on is
## the party's on entry; `ss2` is the capture with it moved off onto Mandalia, which is
## the only thing that separates selected / party / highlight (§30.4).
const FIXTURE_CURSOR_NODE := {"ss1": 7, "ss2": 25}

var _cursor := WorldMapCursor.new()
## Screen-centred box the cursor may occupy: the drawing area, shrunk so the cursor's
## ART stays inside it rather than its anchor. §21.1 — the view never scrolls, the cursor
## runs to the edge and stops.
var _cursor_bounds: Rect2i
var _clip: Control
## Screen-centred, zoomed, and INSIDE the drawing-area clip — everything the frame draws
## mounts here, including the START menu, so it composites in the console's 5-bit channels
## and is widened by the one expansion pass like the rest of the picture.
var _holder: Node2D

## The START menu while it is up, else null. §33.1: the opener is START [b]or[/b] △
## (`andi 0x0810` at 0x8006CC64), which is `world_map_start_menu` in the input map — a
## separate action from Formation's `formation_start_menu`, which is that screen's.
var _menu: WorldMapStartMenu = null
## The Move row's place list while it is up, else null — WORLD.BIN window record 6.
var _places: WorldMapPlaceList = null
## The town page while it is up, else null — WLDCORE page mode 4 (§35).
var _town: WorldMapTownPage = null
## Set by the `--menu=townopen` arm — §38's transition is captured as a contact sheet
## instead of one settled frame. A FLAG rather than a second [method rig_arg] read: the
## `match` above is the one call site this screen needs, and one read cannot disagree with
## itself the way two can.
var _filmstrip: bool = false
## §24.1's screen-in as a contact sheet — `--menu=screenin`. Same reason as `townopen`:
## a fade is a picture, not a number, and a `--shot=` capture is one frame.
var _screen_in_filmstrip: bool = false

## The ramp the screen runs on itself as it comes up (ADR-0161). Never null after
## `_ready` succeeds; settled rather than absent when a capture wants the landed frame.
var _screen_in: WorldMapScreenIn = null
## The subtractive quad the ramp pushes into. Added to the tree BEFORE the expansion
## pass, so the frame computes `e(B - F)` and not `e(B) - e(F)`.
var _screen_in_rect: ColorRect = null
## ADR-0174's OUT arm, live only while the screen is leaving. Shares
## [member _screen_in_rect] with the in-arm because on console they ARE one descriptor
## (`0x800D0ADC..DE`) driven by one routine's two directions — and because that rect is
## added to the tree BEFORE the expansion pass, which is the ordering `_build_screen_in`
## documents and a second quad would have to get right all over again.
## The live value of `world_map.screen_out`, kept current by an `on_update` push rather
## than pulled at leave time.
##
## A PULL (`Tune.get_value` inside `_leave`) is legal under ADR-0068 R5 and was the first
## shape here — but it trips the R8 guard, which is right to complain: a slug read only when
## an EVENT happens has no consumer during the window between the scrub and the event, so
## toggling the panel checkbox printed *"scrubbed but nothing consumed it"* every time and
## the player had to leave the map to make the warning stop. R3's WRITE-BACK shape is the
## one that fits — the scrub lands on live state the instant it happens.
##
## The write-back lands HERE and is deliberately NOT mirrored back onto
## `WorldMapScreenOut.SCREEN_OUT_DEFAULT`. A `static var` is process-global, so mirroring a
## scrub into it would leak this visit's setting into every later mount and stop the member
## being a *default* at all — which is why every other R3 owner in the tree
## (`ScenarioWeather`, `ScenarioDialogueBoxPool`) writes to an instance var too. The static
## var is the AUTHORED value; this is the LIVE one.
var _screen_out_enabled: bool = WorldMapScreenOut.SCREEN_OUT_DEFAULT
var _screen_out: WorldMapScreenOut = null
## ADR-0174's OUT arm as a contact sheet — `--menu=screenout`. Same reason as `screenin`:
## a fade is a picture and one settled frame cannot show a curve, so the only way to judge
## the transition this adds is to render its frames into one image and LOOK at it
## (`[[render-atlas-crops-and-look-at-them]]`).
var _screen_out_filmstrip: bool = false
## Re-entrancy guard: ✕ pressed twice, or a hand-off racing the player, must not start two
## fades. `_leave` is a coroutine now, so "already leaving" is a state and not a moment.
##
## [b]It is a ONE-WAY latch, and that is deliberate — this screen is SINGLE-USE.[/b] The
## state has no exit because the object has no second visit: `NavigatorMain.run_world_map`
## calls `scene.instantiate()` for every trip to the overworld and `queue_free()`s the layer
## the moment `dismissed` releases it, so a fresh instance (with `_leaving` false) is what
## the next visit gets. Resetting the latch would be the WRONG repair: the only place a
## reset could sit is after `dismissed.emit()`, and re-arming there buys a second emit of a
## signal the host has already acted on — exactly the double-fire the guard exists to stop.
## If this scene is ever re-mounted rather than rebuilt, THAT is the change that has to
## revisit this line, because a re-mounted instance would be permanently un-leavable and
## `leave()` would go silent — the navigator hang, reached from the other side.
var _leaving: bool = false

## Campaign's store, injected by whoever mounts the screen (crossing C3 is a Query from
## the map INTO Campaign, so the screen never constructs the campaign's own state). With
## none injected: the named capture when standalone — the capture rig reproducing a
## savestate — and the saved campaign otherwise.
var _injected: WorldMapProgress = null


## Places that currently carry a live hand-off, HANDED to the screen the way
## [method set_progress] hands it the progression. The map does not read the node script
## table — that is Campaign's (ADR-0117 dec. 8, §32.9 point 1) — it is simply told which
## places answer to Campaign rather than to the map's own town page.
##
## [b]This is a PRECEDENCE, and the ROM's own.[/b] §29.3: `FUN_8008E2BC` asks the event
## table with mask 8 FIRST, and only when there is no live script does it reach anything
## else. Gariland is both a town (`kind == 1`) and the node that hands off to scenario 13
## at story 1 — the console watched `var[0x27] = 13` there, not a Bar/Shop menu. Empty
## (the default, and every standalone boot) leaves the old town-first behaviour intact.
var _hand_off_places: Dictionary = {}


func set_hand_off_places(places: Array) -> void:
	_hand_off_places = {}
	for p in places:
		_hand_off_places[int(p)] = true


## True when Campaign has claimed this place — checked BEFORE the town page, per §29.3.
func _hands_off(place: int) -> bool:
	return _hand_off_places.has(place)


func set_progress(p: WorldMapProgress) -> void:
	_injected = p
	if is_inside_tree() and progress != null:
		progress = p
		_cursor.place(WorldMapCursor.rest_at(_screen_of(p.party_node())))
		_cursor.resolve(assets, progress)
		_repaint()


## True when this scene IS the running scene — the capture rig and `godot --path .
## res://assets/scenes/WorldMap.tscn`. False when the navigator mounts it as an overlay.
var _standalone: bool = false
## Where the frame's top-left corner sits in the viewport, in viewport pixels.
var _origin: Vector2 = Vector2.ZERO


## The command-line SETTER for this screen's four `@export`s — `--fixture=`, `--zoom=`,
## `--menu=`, `--shot=`. Returns [param fallback] when the key is absent, so a bare launch
## is unaffected.
##
## [b]It is not a competing source of truth, and that distinction is the whole design.[/b]
## ADR-0051's route is the one trunk built: the properties live on this node,
## [WorldMapDebugPanel] is a thin view onto them, and [method capture_to] is the verb
## automation calls. All of that stands. What none of it can do is choose BEFORE
## [method _ready] runs, and [member boot_menu]'s contact sheets must — so a rig needs a
## way to write these properties at launch. This is that way, and it writes the same
## fields the Inspector and the panel edit.
##
## [b]Why `--` and not the environment.[/b] ADR-0051's stated harm is specific: an env var
## LEAKED ACROSS SHELLS and quit a scene in a session that did not know the var existed. A
## `--` arg is per-invocation and visible in the command typed, so no stale `export` can
## silently arm it. The form is the tree's own — 18 files use `OS.get_cmdline_user_args()`,
## among them `tools/capture_startmenu.gd` (a capture rig written a month AFTER the
## ADR-0051 guard landed) and `src/scenes/UnitInfoWindowViewer.gd`, which proves it works
## for a directly launched scene: *"run with `-- --autoshot`"*.
##
##   godot --path . res://assets/scenes/WorldMap.tscn -- --fixture=ss2 --shot=/tmp/wm.png
static func rig_arg(key: String, fallback: String = "") -> String:
	var pre := "--%s=" % key
	for a in OS.get_cmdline_user_args():
		if a.begins_with(pre):
			return a.substr(pre.length())
	return fallback


func _ready() -> void:
	_standalone = get_tree().current_scene == self
	# [b]Claim the input frame (ADR-0177).[/b] The screen pushes ITSELF because it is the
	# live screen the moment it mounts — a host that wants it deaf calls
	# [method set_suspended], and a host that mounts something over it pushes that. Focus
	# drops the frame automatically on `tree_exiting`, so there is no teardown path that
	# can strand the stack and leave everything below it deaf.
	Focus.push(FOCUS_STATE, self)
	# The pad is tracked from events (see [member _held_dir]) and a release that lands while
	# another state holds the frame is never delivered here, so the transition itself has to
	# clear it.
	Focus.focus_changed.connect(_on_focus_changed)
	# ADR-0068 R3 write-back for the fade-out switch. Owner-scoped, so it drops itself when
	# the screen leaves the tree; the DEFAULT and the slug live on [WorldMapScreenOut], which
	# is the mechanism the switch turns off.
	Tune.on_update(self, WorldMapScreenOut.SCREEN_OUT_SLUG,
		func(v: bool) -> void: _screen_out_enabled = v)
	# The command-line SETTER for the four properties above (see [method rig_arg]). It is
	# not a second source of truth — it writes the same `@export`s the F3 panel edits and
	# the Inspector shows, and it runs before anything reads them:
	#   -- --fixture=ss1|ss2  --zoom=1  --menu=screenin  --shot=/tmp/wm.png
	capture_path = rig_arg("shot", capture_path)
	fixture = rig_arg("fixture", fixture)
	boot_menu = rig_arg("menu", boot_menu)
	var z := rig_arg("zoom")
	if z != "":
		zoom = maxi(1, int(z))

	assets = WorldMapAssets.new()
	if not assets.load_all():
		push_error("world map: %s" % assets.error)
		_show_missing_assets()
		return

	var on_node: int
	if _injected != null:
		progress = _injected
		on_node = progress.party_node()
	elif _standalone:
		progress = WorldMapProgress.ss2_fixture() if fixture == "ss2" \
				else WorldMapProgress.ss1_fixture()
		on_node = int(FIXTURE_CURSOR_NODE.get(fixture, progress.party_node()))
	else:
		progress = WorldMapProgress.load_or_new()
		on_node = progress.party_node()
	# ADR-0230 dec. 8: the map opening is one of the two moments a reveal pass runs.
	#
	# [b]It no longer LANDS here.[/b] Before ADR-0231 this drained inside `_ready` and the
	# map opened with every reveal already applied; paced, the map opens and THEN reveals,
	# which is what the console does — the drain is page mode `0x39`, ticking while the map
	# is up. The cursor is resolved below against the pre-pass known set and re-resolved by
	# [method _end_reveal], because the set moves while the animation runs.
	_start_reveal_pass(progress.party_node())
	_cursor.place(WorldMapCursor.rest_at(_screen_of(on_node)))
	_cursor.resolve(assets, progress)

	gen = WorldMapPrimitives.new(assets)
	_cursor_bounds = _bounds_for_cursor()

	# LAY OUT AGAINST THE VIEWPORT, NEVER AGAINST THE WINDOW. project.godot sets
	# `window/stretch/mode="viewport"` over a fixed 1024x960 viewport, so the window size
	# is decoration: resizing it does not give the frame more room, it only rescales the
	# finished 1024x960 image — and a tiling WM overrides it anyway (measured 1261x1390
	# for a window this scene had just set to 768x720).
	#
	# The scaffold sized the WINDOW to 256x240 x zoom and drew at the origin, which left
	# the map in the viewport's top-LEFT corner with black down the right and along the
	# bottom. That reads as two separate faults — "it doesn't fill the window" and "the
	# vignette is off-centre" — and is one: the frame was never centred in the surface it
	# was actually being drawn into.
	#
	# 1024 / 256 == 960 / 240 == 4, so the default fit is exact and there is no letterbox.
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if zoom <= 0:
		zoom = maxi(1, mini(int(vp.x) / FB_SIZE.x, int(vp.y) / FB_SIZE.y))
	_origin = ((vp - Vector2(FB_SIZE) * float(zoom)) * 0.5).floor()
	_backdrop_full_rect()

	# The drawing area clips the frame, so the screen mounts inside a Control that
	# is exactly it. Everything below is in screen-centred coordinates.
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.position = _origin + Vector2(DRAW_AREA.position) * zoom
	_clip.size = Vector2(DRAW_AREA.size) * zoom
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clip)

	_holder = Node2D.new()
	_holder.position = (Vector2(SCREEN_ORIGIN) - Vector2(DRAW_AREA.position)) * zoom
	_holder.scale = Vector2(zoom, zoom)
	_clip.add_child(_holder)

	renderer = WorldMapRenderer.new()
	renderer.setup(assets)
	_holder.add_child(renderer)

	_build_screen_in()
	_add_expansion_pass()

	# A1 — the one audio crossing. `MusicPlayer` is an autoload and stays host-side
	# per #410; the port exists so the screen never names it twice.
	music = WorldMapMusicPort.new(get_node_or_null(^"/root/MusicPlayer"))
	# Not while capturing: the frame is the same either way, and a test that starts the
	# music driver is a test that has to stop it.
	if capture_path.is_empty():
		music.play()

	_repaint()
	# --menu=1 opens the START menu at boot. §34.7-§34.11 leave this screen with NO
	# console-accurate pixel reference for the menu box, so the only way to judge it is
	# `[[render-atlas-crops-and-look-at-them]]` — and a `--shot=` capture quits before any
	# key can be pressed. Same shape as --fixture / --zoom / --shot above.
	match boot_menu:
		"1":
			_open_menu()
		"move":
			_open_menu()
			_open_places()
		"townopen":
			# §38's transition, as a FILMSTRIP. Same `match` arm as the three below, so
			# it adds no second [method rig_arg] call site. The open is judged by
			# eye — `[[dont-conflate-my-measurement-with-user-visual-goal]]` — and
			# a `--shot=` capture quits before ○ can be pressed,
			# so the only way to LOOK at it is to render its frames into one image.
			_filmstrip = true
			_open_town(progress.party_node())
		"screenin":
			# The SCREEN-IN as a FILMSTRIP. Same arm, same reason as `townopen`: this
			# ramp is judged by eye — `[[dont-conflate-my-measurement-with-user-visual-
			# goal]]` — and one `--shot=` frame cannot show a curve. The specific thing to
			# LOOK for is that it does not now STALL: the subtractive blend holds black
			# until F drops below the brightest pixel, so the black is longer than the
			# tick count alone suggests.
			_screen_in_filmstrip = true
		"screenout":
			# The SCREEN-OUT as a FILMSTRIP. The in-arm's sheet is what proved the ramp did
			# not stall; this is its counterpart, and the specific thing to LOOK for is the
			# opposite failure — the out-arm opens at 32, not 0, so the FIRST cell should
			# already be slightly down. A sheet whose first cell is the clean map means the
			# `+ 32` offset was dropped and the fade is starting from nothing.
			_screen_out_filmstrip = true
		"town":
			# §35's page. Same reason as the two above: the box and the row ink are
			# synthesis (the console's are a WORLD.BIN tpage and a scratch page this
			# port cannot read), so the only way to judge them is to look. This adds no
			# new [method rig_arg] call site — it is an arm of the one already on
			# the `match` above.
			_open_town(progress.party_node())

	print("[world map] %s — %d nodes known, %d routes drawn, gil %d, cursor %s on node %d"
			% [fixture, progress.known_nodes().size(), progress.drawn_routes().size(),
			   progress.gil(), _cursor.position,
			   WorldMapCursor.node_under(assets, progress, _cursor.position)])
	_register_debug_panel()

	if not capture_path.is_empty():
		_capture(capture_path)


## ADR-0051: scene configuration is a debug panel, never the environment. The panel is a
## thin VIEW -- `fixture`, `zoom` and `capture_path` stay this node's properties, which is
## the ADR's "toggles persist as scene-level vars, not autoload globals".
func _register_debug_panel() -> void:
	var overlay := get_node_or_null(^"/root/DebugOverlay")
	if overlay == null or not overlay.has_method("register_panel"):
		return                      # no overlay in a bare capture run; not an error
	var panel := preload("res://src/debug/WorldMapDebugPanel.gd").new()
	panel.bind(self)
	overlay.register_panel(panel, overlay.Category.SCENARIO)


## The frame above composites in the console's 5-bit channels (see
## [code]psx_expand_555.gdshader[/code]); this widens it to 8 bits once, at the end,
## which is the only place the console does it either.
##
## A [BackBufferCopy] rather than a [SubViewport]: the map is already a full-screen
## surface, and a SubViewport here would buy nothing while costing the thing
## `[[map-camera-is-ortho-ui-mounts-as-camera-child]]` records — a screen that mounts as
## a camera child cannot be inside one. One viewport copy per frame is the whole cost.
## Build the screen-in quad. Called from `_ready` BEFORE [method _add_expansion_pass],
## and that ORDER IS THE POINT: the expansion pass is a [BackBufferCopy] plus a rect that
## REPLACES the finished frame, so a quad added after it would be subtracted from an
## already-expanded frame — `e(B) - e(F)` where the console computes `e(B - F)`. Both
## live at the default z_index; tree order alone decides, so do not give this one a
## z_index without re-reading `psx_expand_555.gdshader`.
func _build_screen_in() -> void:
	_screen_in = WorldMapScreenIn.new()
	_screen_in_rect = ColorRect.new()
	_screen_in_rect.name = "ScreenIn"
	_screen_in_rect.material = ShaderMaterial.new()
	(_screen_in_rect.material as ShaderMaterial).shader = \
			load("res://src/world_map/screen_in_mode2.gdshader")
	# [b]Anchors are NOT enough here, and this cost a render.[/b] The parent is a [Node2D],
	# not a [Control], so there is no parent rect for `PRESET_FULL_RECT` to anchor against
	# and the rect keeps size (0,0) — it draws nothing, silently, while every assertion
	# about the RAMP still passes. Both full-screen siblings on this screen set `size` for
	# the same reason (`_backdrop_full_rect`, `_add_expansion_pass`); the "anchors only"
	# advice belongs to a rect parented to a CanvasLayer, which this is not.
	_screen_in_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen_in_rect.size = get_viewport_rect().size
	_screen_in_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_screen_in_rect)
	_push_screen_in()


## Push the ramp's current value into the quad. Hides the quad outright at 0, matching
## `FUN_8008f208` (the PSX skips the draw at colour (0,0,0)) and §24.1's enable gate,
## whose test is on the descriptor's own r/g/b.
func _push_screen_in() -> void:
	if _screen_in == null or _screen_in_rect == null:
		return
	var v := _screen_in.current_value()
	_screen_in_rect.visible = v > 0.0
	var mat := _screen_in_rect.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("screen_color", Vector3(v, v, v) / 255.0)


## Push the OUT ramp's value into the same quad the in-arm uses. Separate from
## [method _push_screen_in] rather than parameterised: the two read different objects, and
## a single pusher would have to decide which one wins on a frame where both exist.
func _push_screen_out() -> void:
	if _screen_out == null or _screen_in_rect == null:
		return
	var v := _screen_out.current_value()
	_screen_in_rect.visible = v > 0.0
	var mat := _screen_in_rect.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("screen_color", Vector3(v, v, v) / 255.0)


## True while the screen-OUT ramp is in flight — the mirror of [method screen_in_active],
## for a test or a host that wants to know the map is on its way out.
func screen_out_active() -> bool:
	return _screen_out != null and _screen_out.is_active()


## The tick the screen-OUT ramp is on. The companion to [method screen_out_active], and the
## seam that lets a WAITER bound itself in ramp PROGRESS instead of in rendered frames — see
## [constant WorldMapScreenOut.STALL_FRAMES] for why those are different units and why only
## one of them survives a fast display. [WorldMapScreenOut.ticks] already documents itself as
## existing for "a test or a contact sheet"; this is that value, reachable from outside.
##
## [b]No ramp reads 0, not a sentinel, and that is deliberate.[/b] This returned -1 for "no
## ramp" for exactly one commit. Every consumer of this value is a stall loop comparing
## `now == last` — and `-1 == -1` is the same non-progress as `0 == 0`, so the sentinel was
## a distinction that read identically at the only place it could ever be seen. A waiter
## that needs "is there a ramp at all" has [method screen_out_active] and
## [method has_screen_quad] to ask with; this one answers PROGRESS, where a ramp that does
## not exist and a ramp that has not advanced are the same answer.
func screen_out_ticks() -> int:
	if _screen_out == null:
		return 0
	return _screen_out.ticks()


## True when the shared screen quad exists — [method _run_screen_out]'s THIRD skip, readable
## from outside the scene.
##
## The skip is real and it is silent: `_screen_in_rect` is null when `leave()` arrives before
## `_ready` finished raising the screen, and the ramp is then cut rather than spent pushing
## into [method _push_screen_out]'s own null check. A test asserting that some OTHER skip is
## the one under judgement has to rule this one out, and reaching for the quad by its node
## name (`find_child("ScreenIn", ...)`) pins a string set in [method _build_screen_in] that no
## caller outside this file should have to know.
func has_screen_quad() -> bool:
	return _screen_in_rect != null


## True while the screen-in ramp is still in flight. [b]The navigator polls this before
## awaiting [signal screen_in_finished][/b] — see that signal's docs for why.
func screen_in_active() -> bool:
	return _screen_in != null and _screen_in.is_active()


## Land the screen-in immediately. For a caller that mounts the map with no ramp at all
## (a test, or a re-entry that was never covered by black in the first place).
func settle_screen_in() -> void:
	if _screen_in == null:
		return
	_screen_in.settle()
	_push_screen_in()


func _add_expansion_pass() -> void:
	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(copy)
	var pass_rect := ColorRect.new()
	pass_rect.z_index = 100
	pass_rect.material = ShaderMaterial.new()
	(pass_rect.material as ShaderMaterial).shader = \
			load("res://src/world_map/psx_expand_555.gdshader")
	pass_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	pass_rect.size = get_viewport_rect().size
	pass_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pass_rect)


## The scene's black backdrop is authored at one zoom; stretch it to whatever the
## viewport actually is, so a mounted screen does not show the world behind it.
func _backdrop_full_rect() -> void:
	var backdrop := get_node_or_null(^"Backdrop") as ColorRect
	if backdrop != null:
		backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
		backdrop.size = get_viewport_rect().size
		backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Leave the screen. Mounted, the navigator is awaiting [signal dismissed]; standalone
## there is nothing to return to, so it quits.
func _unhandled_input(event: InputEvent) -> void:
	# A screen that is still raising itself does not listen yet — CONTEXT.md's `Screen-in`
	# is defined as running "before it accepts input", and this is where that is true.
	#
	# [b]It is gated HERE and not by [method set_suspended], and that is load-bearing.[/b]
	# Suspending calls `set_animated(false)` -> `set_process(false)`, which stops the very
	# vsync clock [WorldMapScreenIn] rides: a caller that suspended the screen and then
	# waited for [signal screen_in_finished] would wait forever. Suspend means HANDOVER
	# (§33.7 — Formation/Data/Option own the display and this screen neither draws nor
	# ticks); a screen-in is the opposite, the screen drawing itself into existence.
	if screen_in_active():
		return
	# [b]The pad, ABOVE the press-only gate.[/b] A release is the half a poll never had to be
	# told about, and it is the half the gate below would eat. Directions match none of the
	# three actions further down, so taking the event here costs nothing.
	if _track_pad(event):
		return
	# [b]Mid-reveal the screen listens to nothing[/b] — ADR-0231. On the console the
	# reveal's animation page is pushed ABOVE mode 0, so `FUN_8006C9FC` — the whole of the
	# ○/START/✕ handler quoted through §29.2 — is not ticked while one runs. Below
	# [method _track_pad] rather than above it, so a release that lands during a reveal is
	# still recorded: delivery gates the growth of [member _held_dir], and dropping the
	# release here would leave the cursor walking when the pass ends.
	if _reveal != null:
		return
	if not event.is_pressed() or event.is_echo():
		return
	# [b]The window dispatch that used to stand here IS the Focus stack now (ADR-0177).[/b]
	# Three `if _x != null: return` arms, ordered by nullable precedence, were a hand-rolled
	# focus stack: they answered "am I deaf?" and could not answer "what are the states?".
	# Each window now pushes itself and receives its own `_unhandled_input`, so while one is
	# up Godot does not call THIS method at all — the map's own ✕ still never fires from
	# behind a window, but structurally rather than by an early `return`.
	#
	# That is record 4's `+0x20 = 1` — one level — expressed as a frame instead of a branch,
	# and the ordering the chain encoded is now the push order the openers perform.
	if event.is_action(&"world_map_start_menu"):
		get_viewport().set_input_as_handled()
		_open_menu()
		return
	if event.is_action(&"ui_accept") or event.is_action(&"cursor_confirm"):
		get_viewport().set_input_as_handled()
		_confirm()
		return
	# NB `ui_cancel` is BACKSPACE in this project's input map — Escape is `battle_pause`.
	if event.is_action(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_leave()


## START or △. Not while the party is walking: §29.6's trace has the whole screen frozen
## for the 94 vsyncs of a traversal, cursor included.
func _open_menu() -> void:
	if _menu != null or _places != null or _town != null or _travel != null \
			or _reveal != null or _holder == null:
		return
	var m := WorldMapStartMenu.new()
	if not m.setup(assets, gen):
		m.free()
		return
	m.chose.connect(_on_menu_chose)
	m.cancelled.connect(_close_menu)
	_holder.add_child(m)
	_menu = m
	m.set_bob_frame(_bob_frame)
	# The map's own cursor goes blue-grey behind an open window (§15.21). Repaint NOW
	# rather than setting `_dirty`: opening a window is a state change, not a tick, and a
	# capture (`--shot=`) stops the clock before the next `_process` would ever run it.
	_repaint()
	print("[world map] START menu: %s" % ", ".join(
			range(m.rows()).map(func(r: int) -> String: return m.label_of(r))))


func _close_menu() -> void:
	if _menu == null:
		return
	_holder.remove_child(_menu)
	_menu.queue_free()
	_menu = null
	_repaint()


## A row was taken. Row 0 is Move and is the map's own (§33.10 point 3); the other five
## open screens that are not the map's business, so the map REPORTS them and stops —
## ADR-0117 dec. 8. §33.3 is the table of what each is.
func _on_menu_chose(r: int, window: int) -> void:
	var label := _menu.label_of(r)
	print("[world map] menu row %d — %s (window %d)" % [r, label, window])
	var places: Variant = assets.model.get("place_list")
	if typeof(places) == TYPE_DICTIONARY \
			and window == int((places as Dictionary).get("window_record", -1)):
		_open_places()
		return
	# Close FIRST, then report: a subscriber that mounts a screen must not find this
	# window still up underneath it, and on the console taking one of these rows is a
	# blocking call into WORLD.BIN that owns the whole screen until it returns (§33.7).
	_close_menu()
	menu_row_chosen.emit(r, window)


## Row 0. The place list mounts OVER the menu rather than replacing it, because record 6's
## `+0x20` is one level: ✕ on the list goes back to the menu, not to the map.
func _open_places() -> void:
	if _places != null or _holder == null:
		return
	var pl := WorldMapPlaceList.new()
	if not pl.setup(assets, gen, progress):
		pl.free()
		return
	pl.picked.connect(_on_place_picked)
	pl.cancelled.connect(_close_places)
	_holder.add_child(pl)
	_places = pl
	pl.set_bob_frame(_bob_frame)
	_repaint()
	print("[world map] place list: %d known nodes, standing on %d"
			% [pl.rows(), progress.party_node()])


func _close_places() -> void:
	if _places == null:
		return
	_holder.remove_child(_places)
	_places.queue_free()
	_places = null
	_repaint()


## ○ on the node the party is standing on, when that node is a town — WLDCORE page mode
## 4. The place list closes first if it was the route in (Move onto your own node is
## refused, so this only happens via the map's own ○), and the START menu with it: on the
## console mode 4 is a PAGE PUSH, and the windows the map had up are not underneath it.
func _open_town(n: int) -> void:
	if _town != null or _holder == null:
		return
	var page := WorldMapTownPage.new()
	if not page.setup(assets, gen, progress, n):
		page.free()
		return
	_close_places()
	_close_menu()
	page.chose.connect(_on_town_chose)
	page.cancelled.connect(_close_town)
	_holder.add_child(page)
	_town = page
	page.set_bob_frame(_bob_frame)
	# §38 — the page does NOT arrive settled. Four animations over 30 vsyncs, and the
	# console's own ○ is the only thing that starts them, which is why `setup` builds the
	# settled frame and this is the one call site that opts in.
	page.begin_open()
	_repaint()
	print("[world map] town page: node %d — %s, rows: %s"
			% [n, assets.node(n - 1).get("name", "?"), ", ".join(
					range(page.rows()).map(
							func(r: int) -> String: return page.label_of(r)))])


func _close_town() -> void:
	if _town == null:
		return
	_holder.remove_child(_town)
	_town.queue_free()
	_town = null
	_repaint()


## A town row was taken. §35.9 read where all four go and §36 read what is behind three
## of them — one 28-state machine in WORLD.BIN, entered at states 0 / 14 / 20 and leaving
## through a single shared teardown at state 13. None of it is ported, so this REPORTS
## and leaves the page up: the console's row is a blocking call that owns the screen
## until it returns, and a port that closed the page here would be inventing a dismissal.
func _on_town_chose(r: int, msg: int, label: String, leads_to: Dictionary) -> void:
	print("[world map] town row %d — %s (msg 0x%04X) -> %s %d"
			% [r, label, msg, leads_to.get("kind", "?"), int(leads_to.get("arg", 0))])


## The pick. §33.10 point 2 and ADR-0117 dec. 8: `Move` ends in `FUN_8008E2BC`, which is
## where ○ over a node already ends — so this calls the SAME function and adds no second
## mechanism. Both menus close first, because the walk owns the screen from here.
func _on_place_picked(node_1based: int) -> void:
	_close_places()
	_close_menu()
	_enter_node(node_1based)


## ○ over a known node. §27.6 watched this on the console: *"○ on a node loads that node
## — on Mandalia Plains (a battlefield) it started the battle; on Igros Castle, two hops
## away, it loaded the town."* Off a node it does nothing, because §21.2's cursor is free
## and `DAT_800D0BB4` goes to 0 whenever it is not over one.
func _confirm() -> void:
	if _travel != null:
		return
	# The console reads the hit the cursor's own update stored (`sw v0,0xc(s1)`), which
	# was tested against the PROPOSED position, not the settled one. They differ on the
	# frame the cursor leaves a box; take the console's.
	var n := _cursor.hit_node
	if n <= 0:
		print("[world map] cursor at %s is over no node" % _cursor.position)
		return
	_enter_node(n)


## `FUN_8008E2BC` — the one departure, shared by ○ over a node and by the START menu's
## Move row (§33.10 point 2). §27.6 read the trigger straight off the branch:
## `if (hit_node != marker_node) FUN_8008E2BC(...)`. ○ on the node you are ALREADY on
## loads it; ○ on any other known node walks there first.
## Enter a place from OUTSIDE — what an autoplay walk calls instead of pressing ○.
##
## Deliberately the SAME path a press takes, so autoplay exercises the real thing: on the
## node the marker stands on it hands off immediately, and on any other known node the
## marker walks there first and the event fires on ARRIVAL, with no second press (§32.2).
## `place` is a place number (1-based), matching [signal node_entered].
func enter_place(place: int) -> void:
	_enter_node(place)


func _enter_node(n: int) -> void:
	# `_reveal` for the same reason as `_travel`: the screen is mid-animation. The press
	# path cannot reach here during one ([method _unhandled_input] returns first), but
	# [method enter_place] is a public entry an autoplay walk uses and it must not start a
	# walk across a road that is still being drawn.
	if _travel != null or _reveal != null:
		return
	# §29.3, and it precedes EVERYTHING — the town page and the pathfinder both:
	#
	#     if (FUN_80091238(*(u32*)0x8009F254, 0x08)) {   // the MARKER's node
	#         ... hand off ...
	#         return 0;                                  // the pathfinder is never reached
	#     }
	#
	# `0x8009F254` is the marker's node, not the node under the cursor. **So when a live
	# hand-off exists, ○ does the same thing wherever the cursor is**, and no travel is
	# possible at all. That is why §29.5 measured all three opening savestates as having no
	# reachable walk: FFT will not let you leave Gariland until Gariland is cleared.
	#
	# Without this, ○ on Mandalia Plains at story 1 planned a walk, arrived, found no
	# hand-off THERE, and did nothing — the player's report that "nothing plays".
	var marker := progress.party_node()
	if _hands_off(marker):
		print("[world map] hand-off at node %d — %s (cursor was on %d; ○ ignores it)"
				% [marker, assets.node(marker - 1).get("name", "?"), n])
		node_entered.emit(marker)
		return
	if n == progress.party_node():
		# §35: on a TOWN this is the map's own screen and never leaves it —
		# `FUN_8006FAF0(node)` pushes WLDCORE page mode 4 and the map keeps drawing
		# underneath. On anything else the node is Campaign's business, which is what
		# [signal node_entered] reports. §27.6 watched both arms on the console: *"on
		# Mandalia Plains (a battlefield) it started the battle; on Igros Castle, two
		# hops away, it loaded the town."* [b]Both were ○ presses[/b] — that session
		# never reached a walk (§27.6: "the marker never moved"), which is why the
		# sentence does not license anything about ARRIVING. See [method _arrive_at].
		# `_hands_off(n)` is not tested here: n == marker on this branch, and a marker
		# that hands off returned above.
		if WorldMapTownPage.opens_for(assets, n):
			_open_town(n)
			return
		print("[world map] entered node %d — %s"
				% [n, assets.node(n - 1).get("name", "?")])
		node_entered.emit(n)
		return
	var walk := WorldMapTravel.plan(assets, progress, progress.party_node(), n)
	if walk == null:
		print("[world map] no route to node %d" % n)
		return
	_travel = walk
	print("[world map] departing for node %d — %s: %d legs, %d vsyncs"
			% [n, assets.node(n - 1).get("name", "?"), walk.legs.size(),
			   walk.total_ticks()])
	departed.emit(n)


## Leave the screen from OUTSIDE — what Campaign calls when a node hands off to a
## scenario. Same path as the player's ✕ (music stops, [signal dismissed] fires), so the
## navigator's `await view.dismissed` releases either way and there is one exit, not two.
##
## [b]This RETURNS BEFORE THE SCREEN HAS LEFT.[/b] `-> void` is honest about the return value
## and silent about the interesting part: `_leave` is a coroutine that spends the whole
## screen-out ramp, and this does not await it, so control is back at the call site while
## the map is still fading. That is what the caller wants — `NavigatorMain` fires this from
## a signal handler and is already parked on `await view.dismissed` — but it means
## [b]`dismissed` is the completion signal and this call is not[/b]. Awaiting `leave()`
## rather than `dismissed` would resume a frame later and be a bug that looks like a fix.
func leave() -> void:
	_leave()


func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	if music != null:
		music.stop()
	await _run_screen_out()
	dismissed.emit()
	if _standalone:
		get_tree().quit()


## Strike the screen with ADR-0174's OUT arm, then return. A no-op — and importantly a
## SYNCHRONOUS one — when the tunable is off, so the cut this replaces is one switch away.
##
## [b]There are THREE skips, and each returns synchronously.[/b] Listed one per line rather
## than folded into one `or`, because they are three different statements about the world:
##
## 1. [b]The tunable is off[/b] — the product choice ADR-0188 put behind
##    `world_map.screen_out`. The cut this replaces, one switch away.
## 2. [b]A capture is running.[/b] `_capture` calls `set_process(false)` to freeze the vsync
##    clock for a determinate frame, and this ramp is ticked FROM that clock, so a fade
##    started under a capture would never advance and the await would never return. The gate
##    is the same `capture_path` the music gate uses, for the same reason.
## 3. [b]There is no quad to paint.[/b] `_screen_in_rect` is built unconditionally by
##    `_build_screen_in` from `_ready`, so a null here means `leave()` arrived BEFORE the
##    screen finished coming up. Running the ramp then would spend all
##    [constant WorldMapScreenOut.RAMP_TICKS] vsyncs pushing into
##    [method _push_screen_out]'s own null check — the host would wait out a fade that
##    darkens nothing. Cutting is the honest answer when there is no picture to fade.
##
## [b]The bound counts STALLED frames, not total ones.[/b] It is a deadlock guard, not a
## timing choice: `while is_active()` is correct only while something is ticking, and a host
## that suspends the screen mid-leave would otherwise hang the navigator's
## `await view.dismissed` forever — a hang being the one failure mode that reads as
## "nothing happened" rather than as an error. A flat frame count cannot express that,
## because the two sides count different things: this loop resumes once per RENDERED frame
## while the ramp advances once per VSYNC at [constant VSYNC_HZ] through [method advance].
## Above ~480 fps a flat `RAMP_TICKS * k` expires while the ramp is still healthily running
## and the fade would be cut short on the fastest displays — the guard firing on success.
## Counting frames that made NO progress inverts at no refresh rate at all.
##
## [b]Guarded against the node leaving the tree, not just against a stall.[/b] `get_tree()`
## is null the instant this node is out of the scene tree, so a screen freed or reparented
## across the await would raise from the resume rather than from anything a budget can see.
func _run_screen_out() -> void:
	if not _screen_out_enabled:
		return
	if not capture_path.is_empty():
		return
	if _screen_in_rect == null:
		return
	_screen_out = WorldMapScreenOut.new()
	_push_screen_out()
	var stall := WorldMapScreenOut.STALL_FRAMES
	var last := _screen_out.ticks()
	while _screen_out.is_active() and stall > 0:
		if not is_inside_tree():
			return
		await get_tree().process_frame
		if not is_inside_tree():
			return
		var now := _screen_out.ticks()
		if now == last:
			stall -= 1
		else:
			last = now
			stall = WorldMapScreenOut.STALL_FRAMES


## Screenshot and quit — for diffing against the oracle.
##
##   godot --path . res://assets/scenes/WorldMap.tscn -- --shot=/tmp/wm.png --fixture=ss2
##
## The grab must follow [signal RenderingServer.frame_post_draw]; a viewport read
## taken mid-`_process` comes back blank, which `tools/capture_godot_frame.gd`
## documents too. Doing it from a `-s` SceneTree script instead does NOT work —
## the signal never fires there and the process blocks at 0% CPU forever.
## Capture the frame to [param path], then quit. THE VERB AUTOMATION CALLS -- ADR-0051's
## "automation invokes methods, not env vars", and the replacement for the `SHOT` read
## this scene used to do.
##
## Callable before or after the scene is ready. Before, it only arms
## [member capture_path], and [method _ready] fires the capture at the end of its own
## setup so the frame is complete; after, it captures now.
## [param quit_when_done] is the difference between the two callers. The capture rig
## boots, shoots and exits, so it keeps the quit; [WorldMapDebugPanel]'s button shoots
## from inside a live session and must not take the session down with it.
func capture_to(path: String, quit_when_done: bool = true) -> void:
	capture_path = path
	if is_node_ready() and not path.is_empty():
		_capture(path, quit_when_done)


func _capture(path: String, quit_when_done: bool = true) -> void:
	set_process(false)                       # freeze the pulse: a determinate frame
	if Focus.holds(self):                    # and yield focus: a rig steers nothing
		Focus.pop(self)
	if _screen_in_filmstrip:
		for _i in 4:
			await get_tree().process_frame
		await _capture_screen_in_filmstrip(path, quit_when_done)
		return
	if _screen_out_filmstrip:
		for _i in 4:
			await get_tree().process_frame
		# The in-arm has to be out of the way first: it is landed by now (value 0) but the
		# sheet drives ONE shared quad, so seeking the out-arm while the in-arm still owns
		# the uniform would render whichever pushed last.
		if _screen_in != null:
			_screen_in.settle()
			_push_screen_in()
		_screen_out = WorldMapScreenOut.new()
		await _capture_screen_out_filmstrip(path, quit_when_done)
		return
	# SETTLE the screen-in. `set_process(false)` stops the vsync clock, so without this
	# every `--shot=` capture would freeze on whatever frame of the ramp the four warm-up
	# frames reached — and every A/B against the console is about the SETTLED frame.
	# Same guarantee the `_town.set_open_frame` line below gives §38.
	if _screen_in != null:
		_screen_in.settle()
		_push_screen_in()
	# SETTLE the reveal pass for the same reason (ADR-0231): `--shot=` is about the frame
	# the drain LANDS on, and a frozen clock would otherwise hold whatever beat the four
	# warm-up frames reached — a half-drawn road in every capture of a node that owes one.
	settle_reveal()
	if _town != null:
		if _filmstrip:
			for _i in 4:
				await get_tree().process_frame
			await _capture_filmstrip(path, quit_when_done)
			return
		# ...otherwise SETTLE it. `set_process(false)` stops the vsync clock, so without
		# this the capture would freeze on whatever frame of §38 the four warm-up frames
		# happened to reach — and the A/B against the console is about the SETTLED frame.
		_town.set_open_frame(WorldMapTownPage.OPEN_VSYNCS)
		_repaint()
	for _i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	# The frame is CENTRED in the viewport, so crop where it actually is. Cropping from
	# the top-left worked only while the scene was resizing the window down to the frame.
	var want := Rect2i(Vector2i(_origin), Vector2i(FB_SIZE.x * zoom, FB_SIZE.y * zoom))
	var have := Rect2i(Vector2i.ZERO, Vector2i(img.get_width(), img.get_height()))
	if want != have:
		img = img.get_region(want.intersection(have))
	var err := img.save_png(path)
	print("[world map] capture %s -> %s (%dx%d)"
			% ["ok" if err == OK else "FAILED %d" % err, path,
			   img.get_width(), img.get_height()])
	if quit_when_done:
		get_tree().quit()
	else:
		set_process(true)


## §38's transition as one contact sheet — eleven frames of the open, in a 4-wide grid,
## each labelled by its vsync in the print. The frames are chosen to straddle every
## boundary the section names: both apertures' first and last steps, the ramp's black
## start, and the two vsyncs where nothing but the ramp is moving.
const FILMSTRIP_FRAMES: Array[int] = [0, 2, 4, 6, 8, 12, 19, 21, 23, 25, 29]


func _capture_filmstrip(path: String, quit_when_done: bool = true) -> void:
	await _contact_sheet(path, FILMSTRIP_FRAMES, func(f: int) -> void:
		_town.set_open_frame(f)
		_repaint(), quit_when_done)


## ADR-0161's screen-in as one contact sheet — now EVERY frame of it (ADR-0174).
##
## The old list sampled eleven of sixty and its docstring justified the spacing by a stall
## that cannot happen any more: it argued the ramp "starts at level 31 and steps every 2
## vsyncs, so it is still above level 24 for the first quarter." Measured, it starts at
## level 24 and steps every frame. At sixteen frames the whole ramp fits in one sheet, so
## there is nothing left to sample and no spacing left to defend.
##
## [b]Two things to LOOK for, and neither is a number.[/b] (1) The old risk was a stall;
## the new one is its opposite — sixteen frames is a quarter of a second and it may read as
## a POP. (2) Tick 0 is level 24, not 31, so the top seven framebuffer levels survive it:
## if the mount frame leaks, it leaks in cell 0 and nowhere else. `WorldMapScreenInTest`
## pins that seven as arithmetic; only this sheet can say whether the map HAS pixels there.
const SCREEN_IN_FRAMES: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]


func _capture_screen_in_filmstrip(path: String, quit_when_done: bool = true) -> void:
	await _contact_sheet(path, SCREEN_IN_FRAMES, func(f: int) -> void:
		_screen_in.seek(f)
		_push_screen_in(), quit_when_done)


## ADR-0174's OUT arm as one contact sheet — every frame of it, same as the in-arm's.
## The ramp is 16 ticks and lands at 14, so seventeen cells hold the whole thing including
## the two frames after the picture is already black.
const SCREEN_OUT_FRAMES: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]


func _capture_screen_out_filmstrip(path: String, quit_when_done: bool = true) -> void:
	await _contact_sheet(path, SCREEN_OUT_FRAMES, func(f: int) -> void:
		_screen_out.seek(f)
		_push_screen_out(), quit_when_done)


## Render [param frames] of some ramp into one 4-wide contact sheet, each cell the
## cropped 256x240 frame, and quit. [param seek] puts the ramp on a given vsync — which
## is why every ramp that wants a sheet has to be SEEKABLE rather than accumulated.
##
## Shared by §38's town-page open and ADR-0161's screen-in because they are two answers
## to ONE question ("render these chosen vsyncs into a grid"), unlike the two ramps
## themselves, which answer different ones and stay apart on purpose.
func _contact_sheet(path: String, frames: Array[int], seek: Callable,
		quit_when_done: bool = true) -> void:
	var cell := Vector2i(FB_SIZE) * zoom
	var cols := 4
	var rows := int(ceil(float(frames.size()) / float(cols)))
	var sheet := Image.create_empty(cell.x * cols, cell.y * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.BLACK)
	for i in frames.size():
		seek.call(frames[i])
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var want := Rect2i(Vector2i(_origin), cell)
		var have := Rect2i(Vector2i.ZERO, Vector2i(img.get_width(), img.get_height()))
		img = img.get_region(want.intersection(have))
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()),
				Vector2i(i % cols, i / cols) * cell)
	var err := sheet.save_png(path)
	print("[world map] filmstrip %s -> %s (%dx%d), vsyncs %s"
			% ["ok" if err == OK else "FAILED %d" % err, path,
			   sheet.get_width(), sheet.get_height(), frames])
	if quit_when_done:
		get_tree().quit()
	else:
		set_process(true)


## The screen-centred box the cursor's ANCHOR may occupy: the measured drawing area
## (§22.2 / §28.5 — framebuffer x 0..251, y 8..235, three instruments agreeing) shrunk by
## the cursor cel's own extent, so the hand stays on screen rather than its anchor point.
## That extent is x −17..+1, y −5..+13 — the hand trails down and to the LEFT of the
## point it indicates.
##
## ⚠ Derived, not measured. §21.1 establishes only that the cursor "runs to the far left
## edge and stops"; nothing read says where the console clamps. This is the weakest thing
## on the screen — built from two measured pieces, and flagged rather than asserted.
func _bounds_for_cursor() -> Rect2i:
	var art := assets.cel_bounds(assets.static_cel(WorldMapPrimitives.CURSOR_FRAME))
	var lo := DRAW_AREA.position - SCREEN_ORIGIN - art.position
	var hi := DRAW_AREA.end - SCREEN_ORIGIN - art.end
	return Rect2i(lo, hi - lo)


## A 1-based node's projected screen point; (0,0) for "no node".
func _screen_of(node_1based: int) -> Vector2i:
	if node_1based <= 0:
		return Vector2i.ZERO
	var n: Dictionary = assets.node(node_1based - 1)
	return Vector2i(int(n["screen"][0]), int(n["screen"][1]))


func _process(delta: float) -> void:
	if renderer == null:
		return
	if advance(delta) > 0 or _dirty:
		_dirty = false
		_repaint()


## Run the console's clock forward by [param delta] seconds and return the number of
## vsyncs actually stepped. Split out from [method _process] so the rate is testable
## without a wall clock — a test that measured elapsed TIME would be measuring the
## harness, which throttles presentation.
func advance(delta: float) -> int:
	_tick_debt += delta * VSYNC_HZ
	var ticks := int(_tick_debt)
	if ticks <= 0:
		return 0
	_tick_debt -= float(ticks)
	ticks = mini(ticks, MAX_CATCHUP_TICKS)
	var dir := held_direction()
	for _i in ticks:
		_advance_pulse()
		_advance_bob()
		# §38's transition runs on the same vsync clock as the bob, and on nothing else —
		# a delta-driven tween would run the ramp at the display's rate and finish the
		# open in a third of the time on a 144 Hz panel.
		if _town != null and _town.advance_open():
			_dirty = true
		# ADR-0161's screen-in, on that same clock and for that same reason — the shape
		# it REPLACES was a `create_tween()` in the navigator. No `_dirty`: the ramp is a
		# shader uniform on its own quad, so it costs a uniform write, not a repaint.
		if _screen_in != null and _screen_in.is_active():
			_screen_in.tick()
			_push_screen_in()
			if not _screen_in.is_active():
				screen_in_finished.emit()
		# The OUT arm, on the same clock and for the same reason. It cannot be live at the
		# same time as the in-arm in practice (one raises the screen, the other strikes it),
		# but it is ticked second so that if it ever were, the frame the player sees is the
		# one that is leaving.
		if _screen_out != null and _screen_out.is_active():
			_screen_out.tick()
			_push_screen_out()
		# ADR-0231's reveal animation, on the same clock and for the same reason. It waits
		# for the screen-in: CONTEXT.md defines a screen-in as the ramp that runs *before
		# the screen accepts input*, and a reveal is a thing the player is meant to watch,
		# so starting it under the fade would spend the first beats behind black.
		if _reveal != null and not screen_in_active():
			if _reveal.tick():
				_dirty = true
			if not _reveal.is_active():
				_end_reveal()
		if _travel != null:
			_advance_travel()
		_advance_party()
		# One cursor step per VSYNC, not per rendered frame — the ramp, the coast and the
		# snap are all counted in the console's frames, so a 143.9 Hz display would
		# otherwise overshoot every node by 2.4x.
		#
		# `assets` and `progress` are what let the step run the console's magnetic snap
		# (`FUN_8008D194`): inside a node's box the cursor is pulled up to 2 px/vsync onto
		# that node's resting point. Without them it is the bare ramp, and the screen
		# feels like the node is not there.
		if _cursor.step(dir, _cursor_bounds, assets, progress):
			_dirty = true
	return ticks


## One step of the glove bob, pushed to whichever list windows are up. The counter is
## wrapped on the idle table's own period (46) so it cannot drift out of int range on a
## screen that is left open, and so `set_bob_frame` sees the same value on every cycle.
func _advance_bob() -> void:
	_bob_frame = (_bob_frame + 1) % maxi(1, WorldMapStartMenu.glove_period())
	if _menu != null:
		_menu.set_bob_frame(_bob_frame)
	if _places != null:
		_places.set_bob_frame(_bob_frame)
	if _town != null:
		_town.set_bob_frame(_bob_frame)


func _advance_travel() -> void:
	if _travel.step():
		_dirty = true
	# §32.2's arrival tick asks its question at EVERY node the marker reaches, and the
	# order is the point:
	#
	#     DAT_8009F254 = arrived_node;                 // the marker node, each time
	#     if (FUN_80091238(arrived_node, 8)) { ... fire ...; return; }
	#     ...
	#     if (more_legs) { ... start the next route ...; return; }
	#
	# The query PRECEDES the more-legs branch, so a live hand-off standing on the way
	# ends the walk there. The port flattens every route hop into one `legs` array
	# ([member WorldMapTravel._leg_end_node] is what keeps the boundary), and without
	# this the marker walked straight through Mandalia Plains — story battle and all —
	# on its way to Igros Castle, and nothing fired.
	var reached := _travel.reached_node
	if reached > 0 and not _travel.finished:
		progress.set_party_node(reached)
		if not _hands_off(reached):
			# Nothing here. `FUN_80090D30(0x43)` cues a sound and the next route starts.
			return
		_travel = null
		_cursor.resolve(assets, progress)
		_dirty = true
		arrived.emit(reached)
		print("[world map] arrived at node %d — %s (hand-off; the rest of the walk is "
				% [reached, assets.node(reached - 1).get("name", "?")]
				+ "abandoned)")
		_arrive_at(reached)
		return
	if not _travel.finished:
		return
	var n := _travel.destination
	_travel = null
	progress.set_party_node(n)
	# The marker moved, so the hit test the cursor is holding is about the OLD world.
	# The console's cursor update writes that word every vsync whether or not anything
	# moved (`sw v0,0xc(s1)`), so a stale one is a divergence and not just untidy: the
	# next ○ reads it.
	_cursor.resolve(assets, progress)
	_dirty = true
	arrived.emit(n)
	print("[world map] arrived at node %d — %s" % [n, assets.node(n - 1).get("name", "?")])
	_arrive_at(n)


## What ARRIVING at a node does — and it is [b]not[/b] what ○ on the node you are already
## standing on does. Two different lists, two different triggers.
##
## [b]This used to call [method _enter_node], so walking to a town popped its menu open by
## itself.[/b] The comment that justified it cited §27.6's *"○ two hops away walked the
## marker there and then loaded the town"* — and §27.6 says the opposite of that. Its own
## text: *"the marker never moved, never changed frame list, and the ribbon never grew.
## No walk is reachable from this savestate."* Both arms it watched were ○ presses with no
## travel in between, so the console was never observed auto-opening anything on arrival.
##
## The disassembly settles it. The arrival tick `FUN_8008E540` reaches `0x8008EA34`, which
## calls [b]`FUN_8008D3C0`[/b] — the ERRANDS list, built from the node's type-4 emits — and
## only then, and only if that list came back with a positive count
## (`beq a0,-1` / `blez a0` at `0x8008EA44`/`0x8008EA4C`), does it push a page at
## `0x8008EA94`. It never calls `FUN_8008D2C8`, the Bar / Shop / Soldier office builder.
## The three sites that DO pair `jal FUN_8008D2C8` with `jal FUN_8006FAF0` are all ○
## handlers. So the town menu is on the ○ path and on no other.
##
## Battlefields are unchanged: the node is still Campaign's business through
## [signal node_entered], which is the arrival event firing, not a menu.
func _arrive_at(n: int) -> void:
	# ADR-0230 dec. 8's other trigger, and it is BEFORE the town-page return — arriving at
	# a town would otherwise skip its reveals. Two beats are reachable no other way:
	# counter 31's live on Dorter with no hand-off at 30, and Zeltennia/Warjilis are gated
	# on `var[170]`/`var[165]` and never on the story counter at all.
	#
	# [b]And the rest of the arrival WAITS for it (ADR-0231).[/b] Both endings below hand
	# the screen away — the town page mounts over the map, [signal node_entered] can tear
	# it down entirely — and either one landing over a running reveal would cut the
	# animation off mid-beat or draw a menu across it. Paced, "arrived" and "arrived and
	# finished revealing" are two different moments, so the second half is a state
	# ([member _arrival_pending]) rather than the next statement.
	if _start_reveal_pass(n):
		_arrival_pending = n
		return
	_finish_arrival(n)


## The half of [method _arrive_at] that happens once the node's reveals have finished
## drawing. Called straight through when the node owed none, and from
## [method _end_reveal] when it did.
func _finish_arrival(n: int) -> void:
	if not _hands_off(n) and WorldMapTownPage.opens_for(assets, n):
		# Stand there. ○ opens the menu — `FUN_8008D2C8` is reachable from the map's own
		# input handler and from nothing on this path.
		return
	print("[world map] entered node %d — %s" % [n, assets.node(n - 1).get("name", "?")])
	node_entered.emit(n)


## Start pacing the [b]reveal pass[/b] the party's node owes. True when it owed anything,
## i.e. when there is now an animation to wait for.
##
## [param place] is a PLACE NUMBER (1-based, 0 = between two nodes) because both callers
## hold one; `Campaign.place_to_index` is the one conversion. The pacing is the map's, not
## Campaign's — ADR-0230 dec. 4 — so this is where the wait lives and nothing in Campaign
## moved to build it.
##
## The map does not read `events.json` and never learns what a reveal IS — it asks for the
## pass, paces it, and repaints. That is the whole crossing (dec. 2).
func _start_reveal_pass(place: int) -> bool:
	if place <= 0 or progress == null:
		return false
	# A pass already in flight is not interrupted. The two triggers cannot overlap in
	# practice — the map opens once and an arrival ends a walk that a reveal was blocking
	# input for — but "start a second one" has no defined picture, and dropping the new
	# one silently would lose reveals, so the running one is finished first.
	if _reveal != null:
		_reveal.settle()
		_end_reveal()
	var anim := WorldMapRevealAnimation.new(
			Campaign.reveal_pass(Campaign.place_to_index(place), progress), assets)
	if not anim.is_active():
		return false
	_reveal = anim
	_dirty = true
	print("[world map] reveal pass at node %d" % place)
	return true


## True while a reveal is drawing. The screen holds the input frame and takes no input —
## see [member _reveal].
func reveal_active() -> bool:
	return _reveal != null


## Finish the pass immediately, applying every step it still owes. The capture rig freezes
## the vsync clock, and a host that mounts the map for one settled frame wants the state
## the drain lands on — the same guarantee [method settle_screen_in] gives the ramp, and
## the behaviour every caller had before ADR-0231.
func settle_reveal() -> void:
	if _reveal == null:
		return
	_reveal.settle()
	_end_reveal()


## The pass has finished drawing: re-resolve, repaint, and release whatever was waiting.
func _end_reveal() -> void:
	if _reveal == null:
		return
	var shown := _reveal.steps_shown
	_reveal = null
	# The known set moved, so the hit test the cursor is holding is about the old world —
	# the same reason the arrival path re-resolves. It is done HERE and not per step
	# because the cursor cannot move while a reveal runs, so nothing reads it in between.
	if assets != null:
		_cursor.resolve(assets, progress)
	_dirty = true
	print("[world map] %d reveal step(s) drawn" % shown)
	var n := _arrival_pending
	_arrival_pending = 0
	if n > 0:
		_finish_arrival(n)


## Fold one event into [member _held_dir], and say whether it WAS the pad. Both edges: a
## press sets its component, a release clears it.
##
## The release arm tests which way the axis is actually pointing first, because a pad can be
## rolled — LEFT down, RIGHT down, LEFT up — and zeroing the axis on that last event would
## drop a direction the player is still holding. A poll never had this problem and never had
## the release either; this is the whole of what tracking costs.
func _track_pad(event: InputEvent) -> bool:
	for action: StringName in PAD_AXES:
		if not event.is_action(action):
			continue
		var step: Vector2i = PAD_AXES[action]
		if event.is_action_pressed(action):
			if step.x != 0:
				_held_dir.x = step.x
			if step.y != 0:
				_held_dir.y = step.y
		elif event.is_action_released(action):
			if step.x != 0 and _held_dir.x == step.x:
				_held_dir.x = 0
			if step.y != 0 and _held_dir.y == step.y:
				_held_dir.y = 0
		return true
	return false


## A transition this screen did not win drops whatever the pad was holding.
##
## Delivery gates the GROWTH of [member _held_dir] for free — a deaf node is not called, so
## a press that lands under an open window cannot reach it. Delivery cannot gate the SHRINK:
## the matching release lands under that same window and is never delivered either. Without
## this, opening the START menu with LEFT held and closing it again leaves the cursor walking
## left forever, and nothing in the log says why.
func _on_focus_changed(_channel: String, _state_name: String) -> void:
	if not Focus.holds(self):
		_held_dir = Vector2i.ZERO


## The direction the pad is holding, each component -1, 0 or +1. Diagonals are legal:
## §27.6 drove both axes and describes the controller as per-axis.
func held_direction() -> Vector2i:
	# [b]`_input_enabled`, the three sub-screen nullables and the `Focus.holds` test are all
	# gone (ADR-0177).[/b] The first four were one question — "does someone else have
	# input?" — answered four times. The fifth was the same question a fifth time, and it
	# survived the first conversion only because the POLL underneath it forced it to: a
	# poller reads the device on frames it does not hold focus, so it has to ask. Nothing
	# asks now. `_held_dir` is delivered, and delivery is what Focus gates.
	#
	# `_travel` is NOT one of them and never was: it has no node and consumes no input. The
	# map still HOLDS focus while the marker walks, it is simply mid-animation — §29.6 froze
	# the whole screen for the 94 vsyncs of a traversal. That makes this a game-state gate,
	# the only kind left here.
	if _travel != null or _reveal != null:
		return Vector2i.ZERO
	return _held_dir


## Freeze the animation — the capture tool wants a determinate frame, and so does
## anyone diffing against the oracle.
func set_animated(on: bool) -> void:
	set_process(on)


## Hand the screen over to another one and take it back. §33.7: three of the START menu's
## six rows — Formation, Data, Option — are ordinary blocking calls into `WORLD.BIN` that
## own the display until they return, and the world map neither draws nor ticks under them
## (it is not a page; `0x800BB4F0` never sees it). So a host mounting one of those screens
## suspends this one rather than layering over it.
##
## Everything here is reversible and nothing is torn down: the clock stops where it is, the
## progression is untouched, and coming back re-arms the same frame. Input goes with it: the
## pop is what drops the frame, and [method _on_focus_changed] drops the held direction with
## it, so a suspended screen cannot steer a cursor nobody can see.
func set_suspended(on: bool) -> void:
	set_animated(not on)
	# [b]The input half is a FOCUS transition now, not a flag (ADR-0177).[/b] This used to
	# set `_input_enabled` and call `set_process_unhandled_input` by hand — two of the six
	# mechanisms that answered "who has input", in one function, next to a third
	# (`set_animated`, which is the PUMP: ADR-0119's other capability, and it stays here).
	# Yielding the frame is what stops the pad reaching this screen at all — there is no poll
	# left to gate, only delivery. The `set_process_unhandled_input` beside it
	# is NOT a second focus mechanism — it is this node's own processing state, the same
	# primitive Focus uses, and it is still needed because an EMPTY stack deafens nobody by
	# design (that transparency is what lets unconverted scenes keep working). A lone
	# participant that pops would otherwise stay audible; `WorldMapMountTest` proved it.
	#
	# Flat rather than nested, and that is faithful. §33.7: Formation is an ordinary
	# blocking `WORLD.BIN` call, not a page push — the map is not layered UNDER it, it is
	# suspended, and `0x800BB4F0` never sees the hand-off at all.
	if on:
		if Focus.holds(self):
			Focus.pop(self)
	elif not Focus.holds(self):
		Focus.push(FOCUS_STATE, self)
	# [b]AFTER the transition, not before.[/b] Popping the last frame empties the stack, and
	# an empty stack re-enables every registered root — so a `set_process_unhandled_input`
	# set first is immediately undone by the pop. Two mechanisms writing one property, and
	# the order decides. Found by `WorldMapMountTest`, not by reading.
	set_process_unhandled_input(not on)
	if not on:
		_dirty = true


## §30.6: phase 0 counts UP to 0x40 and flips, phase 1 counts DOWN to 0 and flips.
## 64 + 64 is the 128-frame period §21.3 measured over 6,675 sampled frames.
func _advance_pulse() -> void:
	if _pulse_up:
		_pulse_c += 1
		if _pulse_c >= WorldMapPrimitives.PULSE_TOP:
			_pulse_up = false
	else:
		_pulse_c -= 1
		if _pulse_c <= 0:
			_pulse_up = true


## Step the marker's own animation. The list it indexes is the idle one at rest and the
## fast bank's while walking, and it changes at every waypoint — so a change restarts the
## cycle rather than carrying an index into a list that may be shorter.
func _advance_party() -> void:
	var want: int = _travel.frame_list() if _travel != null else 16
	if want != _party_list:
		_party_list = want
		_party_frame = 0
		_party_tick = 0
		_dirty = true
	var fl: Array = assets.frame_list(_party_list)
	if fl.is_empty():
		return
	_party_tick += 1
	if _party_tick >= int(fl[_party_frame][1]):
		_party_tick = 0
		_party_frame = (_party_frame + 1) % fl.size()
		_dirty = true


func _repaint() -> void:
	var fl: Array = assets.frame_list(_party_list)
	var cel_id: int = int(fl[_party_frame][0]) if not fl.is_empty() else 16
	# While walking, the marker is at a point along a route rather than on a node — its
	# descriptor's own xy (§27.3), which is map space, so + PROJ to reach the screen.
	var at: Variant = null
	if _travel != null:
		at = _travel.position + WorldMapPrimitives.PROJ
	# What a running reveal contributes to THIS frame (ADR-0231). Immediate-mode: the
	# animation owns no node and mutates nothing — it answers three questions and the
	# frame is rebuilt from its answers, which is also how the console does it (every
	# animating tick ORs §28.1's rebuild bit into `0x8004D950` and the builder runs again).
	var skip_route := -1
	var ribbon: Dictionary = {}
	var regarding := 0
	var ghost := -1
	if _reveal != null:
		skip_route = _reveal.hidden_route()
		ribbon = _reveal.ribbon_quads()
		regarding = (_reveal.regarding + 1) if _reveal.regarding >= 0 else 0
		ghost = _reveal.ghost_node()
	var prims: Array = gen.background_quads()
	prims.append_array(gen.path_quads(progress, skip_route))
	if not ribbon.is_empty():
		var partial: Array = gen.ribbon_quads(int(ribbon["route"]), int(ribbon["quads"]),
				bool(ribbon["from_end"]))
		partial.reverse()
		prims.append_array(partial)
	# §15.21's "send to background", which this screen runs on the CURSOR and on nothing
	# else: while a window owns the screen the hand goes blue-grey and the map behind it
	# does not change by one pixel. Measured — see
	# [constant WorldMapPrimitives.PAL_DEACTIVATED].
	var cursor_pal := WorldMapPrimitives.PAL_DEACTIVATED \
			if (_menu != null or _places != null or _town != null) else 0
	prims.append_array(gen.main_list(progress, _cursor.position, _pulse_c, cel_id, at,
			cursor_pal, regarding, ghost))
	renderer.draw_primitives(prims)


func _show_missing_assets() -> void:
	var label := Label.new()
	label.text = "world map assets missing\n\n  uv run python tools/parse_world_map.py\n\n%s" \
			% assets.error
	label.position = Vector2(24, 24)
	add_child(label)
