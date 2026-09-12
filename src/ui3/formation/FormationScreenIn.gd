class_name FormationScreenIn
extends ScreenOverlayQuad
## The Formation screen's SCREEN-IN — the ramp the screen runs on ITSELF as it comes up.
##
## A [b]screen-in[/b] (CONTEXT.md) is what a screen does on its way UP: unconditional,
## on the screen's own clock, before it accepts input. The counterpart is a [b]scene-out[/b],
## which is authored per-scenario in the chunk. That distinction is also the OWNERSHIP rule
## this file settles: a scene-out is an event-script instruction and belongs to `Cutscene`
## (`ScenarioColorScreen` and all four `screen_color_mode*.gdshader` classify there); a
## screen-in belongs to the screen's own system, and the Formation screen is `UI`
## (BLUEPRINT §6, *"the toolkit — windows, panels, fonts, lists, focus movement, the open
## and close cadence"*). ADR-0172.
##
## [b]Not `Render`, and not a `Battlefield` thing.[/b] ADR-0129 puts the FOLD BRACKET in
## `Render` and keeps a producer's shader with the producer; ADR-0147 then measured it —
## of the sixteen shaders declaring `compositor_layer`, `Render` produces ZERO. *"The system
## that owns the bracket is not a producer into it."* A screen fade is a drawable somebody
## submits, so it could never be `Render`'s. `Battlefield` owns the place, not fades.
##
## [b]Not a `UI3Beat`.[/b] ADR-0161 §5 already decided that and it stands: a beat declares a
## forward AND a reverse driver, and ADR-0084's boot audit refuses to start without one. A
## screen-in has no reverse — how the Formation screen LEAVES is undecided, the same way
## ADR-0161 §6 deliberately holds the world map's exit open on `transition_mode`. Giving this
## a beat's vocabulary would mean inventing a reversal for a ramp nobody has measured forward.
##
## [b]The length is borrowed from a MEASUREMENT; the mechanism is borrowed from a different
## worker; neither is a measurement of THIS screen.[/b] Nothing in the repo has observed how
## `WORLD.BIN`'s Formation screen comes up — §33.7 records only that it is an ordinary
## blocking call, and `FORMATION_SCREEN.md`'s "fade ramp" at `0x8018C88C` is the selection
## box's 8-slot cursor TRAIL, a per-slot brightness multiply, not a screen fade. So:
##
##   - [constant RAMP_TICKS] = 30 is [WorldMapTownPage]'s `world_menu_open_curve`
##     (`@0x801533B8`, §38.7): a 21-vsync hold plus a 9-entry curve, measured, for a
##     `WORLD.BIN`-era WINDOW coming up. It animates panel GEOMETRY rather than brightness,
##     so the length is an analogy — but it is an analogy to a measurement, and to the right
##     CATEGORY. The world map's own 60 was the alternative and it is a guess mirroring a
##     scenario TRANSITION, so copying it would have made this constant's only justification
##     another unmeasured constant.
##   - [constant STEP_TICKS] = 2 is the quantisation three independent console tables agree
##     on: `{3E}`'s worker `FUN_801467dc`, `world_menu_open_curve`'s doubled entries, and
##     (mirrored) the world map's screen-in.
##   - The blend is `{3E}` Mode 2, `B - F` — PSX abr 2, subtractive. NOT an alpha ramp over
##     black: `B*(1-a)` is a proportional dim while `B - F` is a floor lift that holds black
##     until the ramp drops below the brightest pixel, then emerges highlights-first.
##
## [b]Replacement condition.[/b] Capture `WORLD.BIN`'s Formation overlay across the world-map
## hand-off and log its fade descriptors per vsync, the way SS20.5 is meant to do for
## `WLDCORE`. The overlay is already mapped — `FORMATION_SCREEN.md` live-dumped its const
## block at `0x8018C884` — so this is a cheaper measurement than ADR-0161's, not a harder one.
## When it lands, two integers here change and nothing else does.
##
## [b]No 5-bit quantisation, deliberately.[/b] [WorldMapScreenIn] bakes every value to a whole
## 5-bit level because the world map composites in the GPU's own 5-bit channels and expands
## ONCE at end of frame (`psx_expand_555.gdshader`, a `BackBufferCopy`). The Formation screen
## has no such pass — `psx_expand_555` is referenced only under `src/world_map/` — so
## quantising here would be cargo, not fidelity. That, plus `canvas_item` vs `spatial`, is why
## "promote `WorldMapScreenIn` into a generic screen-in" was a rewrite wearing a shared name
## rather than a reuse.

## Frames between ramp steps. See the class docs: three console tables agree on 2.
const STEP_TICKS := 2

## Ramp length in vsyncs. 30 = 0.50 s — `WorldMapTownPage.OPEN_VSYNCS`, measured (§38.7).
const RAMP_TICKS := 30

## Where the subtractive quad starts, 0..255. At 255 `B - F` is 0 for every pixel the
## framebuffer can hold, so the screen is fully black and this quad IS the cover — nothing
## else has to hold one (ADR-0161 §1: a screen that covers itself cannot have the layering bug).
const START_VALUE := 255.0

## `{3E}` Mode 2 — `B - F`. Shared with the scene-out family (ADR-0172 books the resulting
## `UI -> Cutscene` crossing openly rather than copying eight lines to avoid it; the base class
## and this shader move to `platform` in their own pass).
const MODE2_SHADER := "res://assets/shaders/screen_color_mode2.gdshader"

## PSX vsync rate — the clock this ramp is counted in, never the display's.
const VSYNC_HZ := 60.0

var _ticks: int = 0
var _tick_debt: float = 0.0
var _active: bool = true
var _mat: ShaderMaterial = null
var _mmi: MeshInstance3D = null


## The pushed value at [param tick], 0..255 — a PURE function of the tick, so a rig can seek
## any frame without running the ones before it (the shape [WorldMapScreenIn.value_at] and
## `WorldMapTownPage.set_open_frame` both have). `iv = 2*floor(t/2)` is a new step every
## [constant STEP_TICKS] frames; the ramp lands exactly on clear AT `t == RAMP_TICKS` rather
## than one step short of it.
static func value_at(tick: int) -> float:
	var iv := (maxi(tick, 0) / STEP_TICKS) * STEP_TICKS
	if iv >= RAMP_TICKS:
		return 0.0
	return START_VALUE * (1.0 - float(iv) / float(RAMP_TICKS))


func _ready() -> void:
	var shader := load(MODE2_SHADER) as Shader
	if shader == null:
		# Ramp logic still works headless-of-shaders (a pure unit test); there is just no quad.
		return
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_mat.render_priority = 100      # foreground overlay: sort over other transparents
	_mmi = _make_overlay_quad("FormationScreenInQuad", _mat)
	_push()


## True while the ramp is still running — the screen does not accept input yet. `CONTEXT.md`
## defines a screen-in as running "before it accepts input", and this is where that is true.
func is_active() -> bool:
	return _active


## Elapsed vsyncs (for tests and for a seek rig).
func ticks() -> int:
	return _ticks


## Advance by `delta` seconds' worth of vsyncs, carrying the fraction so the ramp runs at 60 Hz
## on a 144 Hz panel. Returns true on the frame the ramp LANDS.
##
## [b]Counted in vsyncs, not tweened.[/b] ADR-0161 states the reason and it is not stylistic:
## *"a delta-driven tween would run the ramp at the display's rate and finish the open in a
## third of the time on a 144 Hz panel."* The coordinator has no vsync clock of its own — its
## steppers are menu-tick paced — so this carries the debt itself.
func advance(delta: float) -> bool:
	if not _active:
		return false
	_tick_debt += delta * VSYNC_HZ
	while _tick_debt >= 1.0:
		_tick_debt -= 1.0
		_ticks += 1
	_push()
	if _ticks >= RAMP_TICKS:
		_active = false
		_release()
		return true
	return false


## Jump straight to `tick` (a seek rig, or a capture that must settle the ramp).
func seek(tick: int) -> void:
	_ticks = maxi(tick, 0)
	_tick_debt = 0.0
	_active = _ticks < RAMP_TICKS
	if _active:
		_push()
	else:
		_release()


func _push() -> void:
	if _mat != null:
		_mat.set_shader_parameter("screen_color", Vector3.ONE * (value_at(_ticks) / 255.0))


## [b]FREE the quad; do not merely zero it.[/b] ADR-0162: an overlay quad rewrites its corners
## to NDC and carries a +-4096 `custom_aabb` plus `depth_test_disabled`, so it *"fills the
## screen of any camera that renders it, from anywhere, at any zoom, over everything"*. A
## standing quad at value 0 is invisible only until the next camera enters this `World3D` — and
## a `{3E}` quad outliving its scene is EXACTLY the bug that made Formation render black on
## this route twice. Landing is the end of this object's life, not a resting state.
func _release() -> void:
	if _mmi != null and is_instance_valid(_mmi):
		_mmi.queue_free()
	_mmi = null
	_mat = null
	queue_free()
