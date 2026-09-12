class_name FormationMapHost
extends FormationScene
## The MAP host (ADR-0137) — the Formation screen re-hosted over the live battlefield.
##
## The SAME screen as [FormationScene], not a second copy of it: this subclass turns off exactly
## two things (the screen's own backdrop and the 4x2 roster grid) and re-answers exactly two
## questions (who is selected, and where the selected unit is). Everything else — the subtractive
## band, the vitals+nameplate cluster, `screen_to_world`, the body/shadow builders, the Change-Job
## wheel — is screen-common and inherited unchanged. See CONTEXT.md "Formation screen hosting".
##
## MOUNTING. This host lives under the map's own camera, as `CombatUI` already does
## (`GPUArena.tscn:34`), so the map is genuinely BEHIND it in the same opaque pass and the
## subtractive band subtracts from the map. Use [method mount_transform_for] to get the scale +
## offset: the screen is authored for a keep-height ortho of 240 px x 0.04 = 9.6 world units and
## the map camera runs 12.6, so the root scales by 12.6/9.6 = 1.3125 while the map is at ITS size.
##
## The gesture then ZOOMS the camera to the authored 9.6 (ADR-0137 Amendment 3, superseding the
## original "never the camera — the spec says pan, not zoom"): the map ends up read at the Formation
## scene's own scale, and the root correction rides back down to x1.0 as it goes. So the correction
## is not a fixed mount any more — it is re-applied per frame while the camera moves, which is also
## why the clip basis has to be re-pushed per frame (see `UI3ClipEngine.clip_basis_inv_for`).
##
## SELECTION inverts. On the roster host the grid says who is selected and the UI places itself
## around wherever that unit happens to be. Here the tile cursor says who is selected, and the
## BREAKOUT MARK is fixed — at feet (167,213), the centre of the gap the sub-screen opens between
## the narrowed lower panel and the list menu — and the camera moves until the unit satisfies it.

# `TunePort` is INHERITED from FormationScene -- a const is a member, so redeclaring it
# here is a parse error, not a duplicate. #1268 / ADR-0306.

## Menu-tick cadence, shared with the rest of the §15 animators and the ADR-0084 Player.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const CursorRig = ExMateriaBattlefield.CursorRig

const TICK := 2.0 / 60.0

## Forward pan length in MENU TICKS. AUTHORED — there is no ROM oracle for a camera move the ROM
## never makes (the roster host slides sprites; only this host pans). Per ADR-0068 an authored
## default is a `static var` bound to a Tune slug in its production owner, never a `const` — a
## `const` would file invented data in the drawer this codebase reserves for parsed measurements
## (see `VitalsSlideAnimator.SLIDE_CURVE`, which IS parsed).
const PAN_DURATION_SLUG := "formation.map.pan_ticks"
static var PAN_DURATION_DEFAULT := 14
const PAN_DURATION_HINT := {"min": 2, "max": 60, "step": 1}

## The ortho size [FormationScene] is AUTHORED for: 240 px x 0.04 world units per px. The map camera
## runs 12.6, and reconciling the two is what [method mount_transform_for] does. It is also the
## camera size the entry zoom targets (ADR-0137 Amendment 3) — landing there is precisely what makes
## the map read at the Formation scene's own scale, and it drops the root correction to x1.0.
const AUTHORED_ORTHO_SIZE := SCREEN.y * PIXELS_PER_UNIT   # 9.6 — Formation.tscn:12

## The HOLD beat's forward length. A takeover with no motion has nothing to animate, so it occupies
## exactly one tick and the panels open behind it; its REVERSE is the real one (PAN_RELEASE_TICKS).
const HOLD_TICKS := 1

## Reverse pan length in menu ticks. NOT authored and NOT symmetric: the return is
## `PlayerCamera.release_takeover()`'s own cosine ease, which self-drives over
## `PlayerCamera._return_total` = 16 vsync frames = 8 menu ticks. ADR-0084 blesses a genuinely
## asymmetric reverse driver as first-class; this beat declares its real length so the recipe's
## barrier waits for the camera to actually arrive.
const PAN_RELEASE_TICKS := 8

## The MAP host's BREAKOUT MARK, stated in FEET. Its OWN measurement — it no longer derives from
## [constant FormationScene.BREAKOUT_MARK_PX], which is the ROSTER host's.
##
## It used to: `BREAKOUT_MARK_PX + half the 24x40 roster descriptor`, on the reasoning that both
## hosts draw the same UNIT.BIN sprite at the same descriptor size. Neither half of that survived
## being looked at on a settled, DEPLOYED unit (user 2026-08-21, with a shot):
##
##  1. The roster settle answers "where does a unit go once it is no longer one of a GRID" — a
##     question about a grid this host does not have. What this host has to fill is the GAP the
##     sub-screen opens between the narrowed lower panel and the list menu. On Equip that gap runs
##     `x139..196` ([member DetailScene.LOWER_FRAME_EQUIP] right edge → [member
##     StartActionMenu.EQUIP_CONTAINER] left edge), centre x=167. The inherited 178 left ~19px of
##     air on the left and NONE on the right: the unit stood hard against the menu frame.
##     Ability's gap is wider (`x130..200`, centre 165), so the tighter Equip centre serves both.
##  2. The map sprite is not descriptor-sized. MEASURED off the settled shot at the Amendment-3
##     zoom (ortho 9.6; 1.0 world unit = 22.4 display px), a unit draws ~18x27 display px, not
##     24x40 — so "half a descriptor below the centre" was never the right feet offset either.
##     Stating the mark in FEET removes the conversion entirely: a battlefield unit's
##     `global_position` IS its feet (`Unit.place_on_tile`), and feet is what the pan solves for.
##
## y is UNCHANGED. The complaint was horizontal: at feet y=213 the sprite's centre already lands at
## y≈201 in a gap running y132..240, which reads as standing ON the terrain rather than floating.
const FEET_MARK_PX := Vector2(167.0, 213.0)

## The drawn map sprite, in display px at the Amendment-3 zoom — MEASURED (see [constant
## FEET_MARK_PX]), not the roster's 24x40 descriptor. Only the height is consumed, by
## [method selected_unit_screen_center]; the width is here because it is the same measurement and
## it is what says the mark is CENTRED in the gap rather than merely inside it.
const MAP_BODY_PX := Vector2(18.0, 27.0)

## Emitted when the cursor moves onto (or off) a unit — `character` is null when the cursor is over
## an empty tile. The hover cadence listens; the ADR-0084 coordinator does not.
signal unit_hovered(character)

## Emitted alongside `unit_activated` when the player ACTED on a unit (○/Enter) rather than merely
## asking to look at it (△/Tab). The coordinator reads it as "open the action menu once the detail
## settles" — acting on a unit means wanting to DO something to it, and the menu is where doing
## lives. Inspecting emits `unit_activated` alone, so the same screen opens without the menu.
signal unit_act_requested(character)

var _cursor_rig: CursorRig = null
var _player_camera: CharacterBody3D = null
var _camera: Camera3D = null
## `func(grid_pos: Vector2i) -> Node` — the battlefield's own answer to "which unit is standing
## there". Injected rather than looked up: the two map-bearing hosts (GPUArena, NavigatorMain) hold
## their unit lists differently, and this screen has no business knowing either shape.
var _unit_at: Callable = Callable()

var _selected = null
var _selected_unit = null
var _hovered = null
## The battlefield [Unit] under the cursor — the LIVE half of `_hovered`, which is only its
## catalogue IDENTITY. The two are not interchangeable and that is the whole point: a [Character]
## carries no current HP (its [UnitProgression] holds `get_effective_hp()` and nothing else), so
## the identity can say who is standing there and only the unit can say how hurt they are.
var _hovered_unit = null
## The unit whose `hp_changed`/`mp_changed` this host is currently listening to — the parked-cursor
## refresh. Held so the connection can be moved when the cursor does, and dropped when it leaves.
var _vitals_watched = null

# Pan state. `_pan_from`/`_pan_to` are the CAMERA BODY's global position (PlayerCamera is what
# `apply_takeover` writes), latched at the seam so every frame is a pure function of `frame`.
var _pan_from := Vector3.ZERO
var _pan_to := Vector3.ZERO
var _pan_rot := Vector3.ZERO
# The ortho size at each end of the gesture. It used to be a single latched value held CONSTANT for
# the whole pan — the ADR's "never the camera" — which is what Amendment 3 overturns.
var _pan_size_from := 0.0
var _pan_size_to := 0.0
var _panning := false


# Hover state. `_hover_dir` is +1 while the pair is coming IN, -1 while it is going back OUT, and
# `_hover_frame` walks the two cadence curves. Self-clocked (see FormationHoverAnimator) — hover is
# steady-state interaction, which ADR-0084 keeps out of the recipe engine.
var _hover_frame := 0
var _hover_dir := 0
var _hover_accum := 0.0

## `func() -> bool` — may the player ACT on a unit through this screen right now? Injected, because
## "no" has host-specific reasons the screen cannot know: the deployment march owns ○ while it is
## running, since acting on a unit there means DEPLOYING it (ADR-0137 Amendment 2). Unset = always
## allowed.
##
## It gates ACTING only. INSPECTING (△) is never gated — looking at a unit cannot conflict with
## anything, and gating it was what made the screen unreachable for the whole deployment phase.
var can_open: Callable = Callable()

## `func(unit) -> bool` — may this battlefield [Unit] be EDITED right now? Supplied by the host,
## and unset means "no opinion", which is the answer every host but `GambitBattle` gives.
##
## Separate from [member can_open] because they gate different verbs: `can_open` decides whether ○
## opens the screen at all, and this decides whether the screen that opened has live action rows.
## A LOOK is never refused (ADR-0137 Amendment 6); an EDIT is what a turn scopes (#894).
var steerable: Callable = Callable()


# -----------------------------------------------------------------------------
# The host seam (ADR-0137) — the two predicates and the two inverted queries.
# -----------------------------------------------------------------------------

## No cobble floor, no pillarbox bars: the battlefield IS the background. The BAND still builds —
## `formation_band_fold.gdshader` is background-agnostic, so over the map it subtracts from the map.
func paints_own_backdrop() -> bool:
	return false


## No 4x2 grid. Every grid-shaped obligation the coordinator has therefore degenerates: the chrome
## setters find no cells/orbs/trail/header to hide, and the equip-slide cluster has no rows to
## split — the unit reaches the breakout mark by CAMERA PAN instead of by sliding.
##
## `set_unit_info_visible` is the one that does NOT degenerate, and deliberately so: the docked pair
## it hides is not roster chrome, it is the HOVER pair this host slides in, and it must still hand
## off to the detail overlay's own cluster at the same docked spot (one pair visible, not two).
func owns_roster_grid() -> bool:
	return false


func selected_character():
	# While a pick is open the GRID is the selection source, which is `FormationScene`'s own
	# answer-by-cell — the whole reason the grid is up (#941).
	if _picking:
		return super()
	return _selected


## The battlefield [Unit] this host latched beside `character`, or null when it cannot pair the two.
##
## The companion to [method selected_character], and deliberately not a bare `selected_unit()`: the
## caller always already holds an identity, and handing back a unit WITHOUT checking it is that
## identity's is how a panel comes to show one character's name over another's HP. Both fields are
## written together in [method _open_for] — the only place either moves — so the pairing is a
## straight equality here rather than a lookup.
##
## Null in the three cases where there is no honest answer, so callers can stay total:
##   * a PICK is open — `selected_character()` switches to the GRID's answer then, and `_selected_unit`
##     is still the tile cursor's last latch, i.e. a DIFFERENT character's unit. The grid also answers
##     with benched units this host cannot resolve to nodes at all (#941).
##   * `character` is not the latched selection (a harness or a caller painting somebody else).
##   * the latch is gone — freed unit, or a host that has never opened one.
##
## Callers pass the result straight to [method vitals_view_for], which is null-safe and degrades to
## the identity's full-HP view — the right answer whenever no live unit is in play.
##
## Named `..._for(character)` rather than `selected_unit()` to stay clear of
## [method selected_unit_screen_center], which answers about the SCREEN and not about a node.
func selected_battle_unit_for(character):
	if _picking or character == null:
		return null
	if _selected != character:
		return null
	if _selected_unit == null or not is_instance_valid(_selected_unit):
		return null
	return _selected_unit


## The breakout mark, FIXED, as a body CENTRE. This is the inversion: the roster host reports where
## the unit ended up, this host states where the unit must end up and pans the camera until it does.
##
## Derived from this host's OWN mark ([constant FEET_MARK_PX], feet) and its OWN measured sprite
## ([constant MAP_BODY_PX]) — NOT from [constant FormationScene.BREAKOUT_MARK_PX], which answers the
## roster's question with the roster's descriptor.
func selected_unit_screen_center() -> Vector2:
	return Vector2(FEET_MARK_PX.x, FEET_MARK_PX.y - MAP_BODY_PX.y * 0.5)


func _ready() -> void:
	super()
	# At REST the map host shows nothing at all: no band over the battlefield, and the pair parked
	# off both edges. Hovering a unit is what brings them in — which is also why this host never
	# collides with the (deprecated) CombatUI still in the camera's other seat: at rest there is
	# nothing of this screen on screen.
	if _cluster != null and is_instance_valid(_cluster):
		_cluster.place_layout(UnitInfoCluster.LAYOUT_OFF)
	set_band_fade(0.0)


## The map host has no roster array to index, so it builds the pair UNBOUND and binds a unit's views
## on hover. Same cluster, same element id, same depth rung as the roster host's.
func _build_unit_info_cluster() -> void:
	build_unit_info_cluster_unbound()


func _process(delta: float) -> void:
	super(delta)
	_advance_hover(delta)
	_advance_pick_in(delta)


## Walk the two hover curves one menu tick at a time. `_MAX_CATCHUP`-style clamping is unnecessary
## here for the reason it IS necessary elsewhere: a stall that collapses this into one frame costs a
## popped-in nameplate, not a transition that teleports past a screen the player never saw.
func _advance_hover(delta: float) -> void:
	if _hover_dir == 0:
		return
	_hover_accum += delta
	while _hover_accum >= FormationHoverAnimator.TICK:
		_hover_accum -= FormationHoverAnimator.TICK
		_hover_frame += _hover_dir
		var settle := FormationHoverAnimator.settle_frame()
		if _hover_frame >= settle:
			_hover_frame = settle
			_hover_dir = 0
		elif _hover_frame <= 0:
			_hover_frame = 0
			_hover_dir = 0
		_apply_hover_frame()


func _apply_hover_frame() -> void:
	if _cluster != null and is_instance_valid(_cluster):
		_cluster.set_slide_fraction(FormationHoverAnimator.pair_fraction_at(_hover_frame))
	set_band_fade(FormationHoverAnimator.band_fraction_at(_hover_frame))


## Arm the hover animation in `direction` (+1 in, -1 out). Re-arming mid-flight keeps the CURRENT
## frame and just turns the walk around, so cursoring quickly across a row reads as one continuous
## motion instead of restarting from off-screen each time.
func _arm_hover(direction: int) -> void:
	if _cluster != null and is_instance_valid(_cluster):
		_cluster.arm_slide(UnitInfoCluster.LAYOUT_OFF, UnitInfoCluster.LAYOUT_DOCKED)
	_hover_dir = direction
	_hover_accum = 0.0
	_apply_hover_frame()


## True once the pair has fully arrived (or fully left) — the hover's resting query.
func hover_settled() -> bool:
	return _hover_dir == 0


## Current hover cadence frame, for guards.
func hover_frame() -> int:
	return _hover_frame


## Drive the hover to one of its two rest states with no cursor and no animation — the harness /
## F3 hook (`CombatUITest`) for looking at the settled pair while dialling its layout. Gameplay
## never calls this: there the tile cursor arms the cadence and the curves walk it.
func force_hover(settled: bool) -> void:
	if _cluster != null and is_instance_valid(_cluster):
		_cluster.arm_slide(UnitInfoCluster.LAYOUT_OFF, UnitInfoCluster.LAYOUT_DOCKED)
	_hover_dir = 0
	_hover_accum = 0.0
	_hover_frame = FormationHoverAnimator.settle_frame() if settled else 0
	_apply_hover_frame()


## Bind a character's views to the docked pair directly, without a cursor. Same harness use as
## [method force_hover] — this screen normally learns its unit from the battlefield.
func show_character(character) -> void:
	_hovered = character
	_hovered_unit = null
	_watch_vitals(null)
	_push_pair_views(character, null)


## LATCH `character` (and the battlefield [Unit] it is standing as) as the SELECTION, without
## announcing an open. The selection counterpart of [method show_character], and the same kind of
## seam: this screen normally learns its selection from the tile cursor, and a caller that already
## knows who it wants has no cursor gesture to make.
##
## [b]The "without announcing" half is the whole reason it exists.[/b] [method _open_for] — the
## cursor's own door — sets these same two fields and then emits `unit_activated`, which the
## coordinator turns into `enter(State.DETAIL)`. That is right for a press on a tile and wrong for
## a caller that wants a DIFFERENT state on the same unit: [GambitLabScene]'s `G` opens
## `State.GAMBIT` straight over the running battlefield, and routing it through the cursor's door
## would raise the Status screen over the battle it exists to let you watch.
##
## `unit` may be null — [method selected_battle_unit_for] then answers null and the vitals degrade
## to the identity's full-HP view, which is what it already does off a battlefield.
func select_character(character, unit = null) -> void:
	_selected = character
	_selected_unit = unit
	_push_pair_views(character, unit)


# -----------------------------------------------------------------------------
# The DEPLOYMENT PICK (#941) — the roster GRID, over the battlefield
# -----------------------------------------------------------------------------
#
# This host turns the grid OFF, because over a battlefield the map IS the roster: the tile
# cursor answers "who is selected". Deployment is the one phase where that is not enough — a
# BENCHED unit stands on no tile, which is what benched means — so for the length of a pick the
# grid comes back and answers instead.
#
# It is the same screen either way. `owns_roster_grid()` gated only the BUILD, so the grid is
# built lazily here and torn down at the end of the pick, and while it is up this host routes
# the roster's own d-pad navigation (`FormationScene._unhandled_input`) that it otherwise
# suppresses. `paints_own_backdrop()` stays FALSE throughout — that is the whole reason this is
# the map host with its grid switched on rather than the roster host mounted over a battlefield:
# the roster host would paint its cobble floor over the map you are deploying onto.

## How hard the pick DIM subtracts from the battlefield behind the grid, 0..1 in the band's own
## `full_sub` units (the roster screen's own stripe runs at the oracle 120/255 = 0.47).
##
## ADR-0068: the authored default lives HERE, in the production owner, and the F3 panel is a pure
## view of it — so the strength is scrubbable live, which is the only honest way to settle a number
## whose whole justification is "does the grid read over the map".
const PICK_DIM_SLUG := "formation.map.pick_dim"
static var PICK_DIM_DEFAULT := 0.35
const PICK_DIM_HINT := {"min": 0.0, "max": 1.0, "step": 0.01}

## The full-screen subtractive quad raised behind a pick's grid, or null.
var _pick_dim: Node3D = null
## The quad's ShaderMaterial, kept so the dim's strength can be RAMPED rather than authored once.
## `UIVitalsBand.build` returns it for exactly this ("so the caller can keep pushing per-frame
## uniforms"); the first cut discarded it and that is why the dim used to snap on.
var _pick_dim_mat: ShaderMaterial = null
## The pick-in gesture (dim fade + unit slide-in), or null between picks. See [FormationPickIn].
var _pick_in: FormationPickIn = null

## The units the open pick is over, keyed by the Character the grid renders. The caller wants a
## battlefield [Unit] back and the grid answers with a Character, so this is the return leg.
var _pick_units_by_character: Dictionary = {}
## True while the grid is the selection source. Separate from `_pick_units_by_character` being
## non-empty so the two cannot disagree about whether a pick is open.
var _picking: bool = false


## Open a pick over `characters` (with `units` parallel to it): raise the roster grid over the
## battlefield, seed it with them, and take the camera so the frozen tile cursor stops competing
## for the d-pad. Returns false when the list is empty.
##
## It does NOT emit `unit_activated`. The grid is the picker, so the screen the player is looking
## at IS the answer — a Status overlay would cover the grid they are choosing from. ○ on a cell
## still opens one, through the roster's own path, for a player who wants to read the stats first.
func begin_pick(characters: Array, units: Array) -> bool:
	if characters.is_empty():
		return false
	_pick_units_by_character.clear()
	for i in range(characters.size()):
		if i < units.size():
			_pick_units_by_character[characters[i]] = units[i]
	_picking = true
	build_roster_grid()
	set_owned_characters(characters)
	set_selected_cell(Vector2i(0, 0))
	# The band and the docked pair are parked at rest on this host (`_ready`); a pick wants both,
	# because reading who you are about to deploy is the entire point of picking on this screen.
	set_band_fade(1.0)
	if _cluster != null and is_instance_valid(_cluster):
		_cluster.place_layout(UnitInfoCluster.LAYOUT_DOCKED)
	_update_vitals_for_selection()
	_raise_pick_dim()
	_begin_pick_in()
	# The camera hold that freezes the tile cursor is NOT taken here (ADR-0261). It is a CLAIM, and the
	# coordinator takes it on the push that raised this pick, releases it on the pop that ends it,
	# and holds it across everything opened in between. Taken here it was released by whichever
	# screen exited last: opening a Status screen over this grid and backing out of its menu handed
	# the battlefield cursor back with the grid still up.
	return true


## Darken the battlefield behind the grid.
##
## The roster host does not need this: it paints a cobble floor, and the grid reads against it.
## Over the map there is no backdrop at all — [method paints_own_backdrop] is false, which is what
## lets the map show through — so the grid competes with a lit battlefield for the player's eye.
## A subtractive dim is what pushes the map back without hiding it, and it is what the ROM's own
## screens do to a background: this is [UIVitalsBand], the SAME producer as the roster's bottom
## stripe, run full-screen. `formation_band_fold.gdshader` is background-agnostic
## (`ALBEDO = vec3(sub)`), so over the map it subtracts from the map exactly as the stripe does.
##
## Flat, not feathered: both axis profiles collapse to 1.0 when their `out` bounds coincide, which
## is the shader's own documented no-op. At [constant FormationScene.RP_BACKGROUND] it sits BELOW
## every rung the grid draws on (the box is 2, bodies 5, orbs 6) and below the bottom stripe at 1,
## so the ladder is dim → stripe → content with nothing co-planar.
func _raise_pick_dim() -> void:
	if _pick_dim != null and is_instance_valid(_pick_dim):
		return
	var holder := Node3D.new()
	holder.name = "PickDim"
	add_child(holder)
	# Built at ZERO, not at the authored strength: `_begin_pick_in` ramps it up from here, and a
	# quad that opened at full would show one snapped frame before the first ramp push — the very
	# frame this follow-up exists to remove.
	_pick_dim_mat = UIVitalsBand.build(holder, {
		"name": "PickDimQuad",
		"x0": 0.0, "x1": SCREEN.x,
		"y_top_out": 0.0, "y_top_in": 0.0,
		"y_bot_in": SCREEN.y, "y_bot_out": SCREEN.y,
		"full_sub": 0.0,
		"rung": RP_BACKGROUND,
	}, PIXELS_PER_UNIT, SCREEN)
	_pick_dim = holder


## Is the dim raised? Asked by the rig for [method has_roster_grid]'s reason: nothing else in the
## picker's behaviour changes when the battlefield behind the grid is or is not darkened, so
## without this the one thing the dim exists to do has no assertion at all.
func has_pick_dim() -> bool:
	return _pick_dim != null and is_instance_valid(_pick_dim)


## FREE the dim; do not merely zero it (ADR-0162's rule for a full-screen overlay). A quad left
## standing at strength 0 is invisible only until something changes what is behind it, and a
## screen-covering quad outliving its screen is the bug that made Formation render black twice.
func _drop_pick_dim() -> void:
	if _pick_dim != null and is_instance_valid(_pick_dim):
		_pick_dim.queue_free()
	_pick_dim = null
	_pick_dim_mat = null


## Start the PICK-IN: the dim fades up from nothing while the units slide in from the right, one
## gesture on one vsync clock ([FormationPickIn]).
##
## Called from [method begin_pick] AFTER the grid is built and seeded, because the slide latches the
## body holders and there are none until the cells are populated. It pushes tick 0 immediately —
## dim at zero, units off the right edge — so the first frame the player sees is the START of the
## gesture and never a snapped-on grid.
func _begin_pick_in() -> void:
	_pick_in = FormationPickIn.new(ROWS)
	begin_pick_slide()
	_push_pick_in()


## Walk the pick-in one vsync at a time and push what the tick says. Sits beside `_advance_hover`
## in `_process` for the reason ADR-0161 §5 gives for [FormationScreenIn] not being a UI3Beat: a
## beat must declare a reverse driver and the pick has none — [method end_pick] frees the dim
## outright (ADR-0162), it does not ramp it back down.
##
## Stops pushing on the frame the gesture lands. A finished ramp that kept writing `full_sub` every
## frame would be a per-frame uniform push for a value that cannot change again.
func _advance_pick_in(delta: float) -> void:
	if _pick_in == null:
		return
	var landed := _pick_in.advance(delta)
	# PUSH FIRST, then drop the latch. `advance` clamps the tick to the gesture's length on the
	# landing frame, so this push is what places every unit exactly on its authored origin (see
	# [method FormationScene.end_pick_slide]). Dropping the latch first would make the landing push
	# a no-op and leave the units one eased sample short of their cells, forever.
	_push_pick_in()
	if landed:
		end_pick_slide()
		_pick_in = null


## Push the current tick's dim strength and slide positions. Split out of [method _advance_pick_in]
## so the opening frame and every later frame go through ONE path.
func _push_pick_in() -> void:
	if _pick_in == null:
		return
	if _pick_dim_mat != null:
		_pick_dim_mat.set_shader_parameter(
			"full_sub", _pick_in.dim_strength(float(TunePort.get_value(PICK_DIM_SLUG, PICK_DIM_DEFAULT))))
	play_pick_slide(_pick_in.ticks())


## Land the pick-in wherever it is and drop it — the pick is closing, so there is nothing left to
## ramp onto. Dropping the latch here keeps [method end_pick_slide]'s contract (it never outlives
## the cells it is keyed by) when the player picks or backs out MID-gesture; the units' positions
## do not need fixing up, because `free_roster_grid` is about to take the cells with it.
func _end_pick_in() -> void:
	_pick_in = null
	end_pick_slide()


## Is the pick-in gesture still running? Asked by the rig because a fade and a slide have no
## observable at REST: one that never runs and one that completes instantly leave the dim at its
## authored strength and the units in their cells, identically. Companion of [method has_pick_dim],
## which exists for the same reason one level up.
func pick_animating() -> bool:
	return _pick_in != null and _pick_in.is_active()


## Elapsed vsyncs of the open pick-in, or -1 when none is running. The rig's seek handle: with
## [FormationPickIn]'s pure statics this is enough to assert the SHAPE of the ramp — that the dim
## rose through intermediate values and the units travelled — rather than only its destination.
func pick_in_ticks() -> int:
	return _pick_in.ticks() if _pick_in != null else -1


## The dim's CURRENT strength as the material holds it, or -1.0 when no dim is up. Reads back the
## pushed uniform rather than recomputing it, so a ramp that computes correctly and pushes nowhere
## (the first cut's exact defect — the returned material was discarded) fails here.
func pick_dim_strength() -> float:
	if _pick_dim_mat == null:
		return -1.0
	return float(_pick_dim_mat.get_shader_parameter("full_sub"))


## True while a pick is the selection source.
func picking() -> bool:
	return _picking


## How many entries the open pick has. The list SIZE is a separate question from what is selected,
## and a caller that only ever asks the second one cannot tell a correctly-filtered list from an
## unfiltered one whose first entry happens to be right — which is the accident of roster order
## #940 recorded and #941 exists to remove.
func pick_count() -> int:
	return _pick_units_by_character.size()


## The battlefield [Unit] behind the grid's current selection — what a deployment does with the
## pick. Null when nothing is picked or the selection is not one of the offered characters.
func picked_unit():
	if not _picking:
		return null
	return _pick_units_by_character.get(selected_character(), null)


## Close the pick: drop the grid, park the band and the pair again, and hand the camera back.
func end_pick() -> void:
	if not _picking:
		return
	_picking = false
	_pick_units_by_character.clear()
	_end_pick_in()
	set_owned_characters([])
	free_roster_grid()
	_drop_pick_dim()
	set_band_fade(0.0)
	if _cluster != null and is_instance_valid(_cluster):
		_cluster.place_layout(UnitInfoCluster.LAYOUT_OFF)
	# The camera is NOT released here — see `begin_pick`. The coordinator releases it once its stack
	# is empty, which is the same moment for a pick ended from the bare grid and a later moment for
	# one ended from a screen standing on it. Released here as well, the two calls raced: the
	# deploy-from-Status path released the takeover in the screen's reverse and released it AGAIN
	# from this teardown, and between them the tile cursor was live under a grid still on screen.
	pass


## The battlefield has two sides, so this is a real question here. Enemies get the SYMMETRICAL
## screen — hover and Enter behave identically, the panels open and show their real equipment,
## abilities and stats — and only the START menu's action rows go disabled.
##
## OWNED, not team0 (ADR-0180). It used to read the `roster_team` meta and so answered "owned"
## for anything `BaseRoster.spawn_unit` had not made — every navigator-deployed unit and every
## ENTD enemy alike — which handed the enemy screen live action rows. The overlay is the
## question's actual subject, and it is also the one that stays right for the case team0 gets
## wrong: an ENTD-blue **guest** (Delita fights on your side at Gariland) is team0 and is not
## yours to re-equip. An unresolvable selection degrades to owned, the roster host's answer.
func selection_is_owned() -> bool:
	if _selected_unit == null or not is_instance_valid(_selected_unit):
		return true
	return unit_is_owned(_selected_unit)


## May the selected unit be edited RIGHT NOW — ownership AND the moment (#894, design §4).
##
## Ownership is permanent and is [method selection_is_owned]'s question; the moment is the host's,
## because only the host knows whether a turn is open and whose it is. The conjunction lives here
## so the screen asks ONE question and neither term can be forgotten at a call site.
func selection_is_steerable() -> bool:
	if not selection_is_owned():
		return false
	if not steerable.is_valid():
		return true
	return bool(steerable.call(_selected_unit))


## Is this battlefield [Unit] one of the player's own — i.e. in the catalogue's owned overlay?
## Static + null-safe alongside [method character_for_unit], so guards can ask without a host.
static func unit_is_owned(unit) -> bool:
	var character = character_for_unit(unit)
	if character == null:
		return true
	return UIRoster.is_owned(character.slug)


func _unhandled_input(event: InputEvent) -> void:
	# The roster host's d-pad grid nav / L2-R2 sort paging / O-press all read a grid that does not
	# exist here. On the battlefield the TILE CURSOR owns those keys and answers the selection
	# question; this host listens to its signals instead (bind_map).
	#
	# EXCEPT during a pick (#941), when the grid is exactly what does exist and the cursor is
	# frozen by `begin_hold`. Then the roster's own routing is the right routing, unchanged —
	# arrows walk the cells, ✕ dismisses, ○ opens the unit's screen — and this host adds nothing
	# to it, which is the point of the grid being the SAME grid.
	if _picking:
		super(event)


# -----------------------------------------------------------------------------
# Binding + mounting
# -----------------------------------------------------------------------------

## Wire this host to the battlefield it re-hosts over. `unit_at` is `func(Vector2i) -> Node`
## returning the unit standing on that grid position (or null).
func bind_map(cursor_rig: CursorRig, player_camera: CharacterBody3D, unit_at: Callable) -> void:
	_cursor_rig = cursor_rig
	_player_camera = player_camera
	_unit_at = unit_at
	_camera = player_camera.get_node_or_null("FocusPoint/Camera") as Camera3D
	if _cursor_rig != null and is_instance_valid(_cursor_rig):
		if not _cursor_rig.cursor_moved.is_connected(_on_cursor_moved):
			_cursor_rig.cursor_moved.connect(_on_cursor_moved)
		if not _cursor_rig.cursor_confirmed.is_connected(_on_cursor_confirmed):
			_cursor_rig.cursor_confirmed.connect(_on_cursor_confirmed)
		if not _cursor_rig.cursor_inspected.is_connected(_on_cursor_inspected):
			_cursor_rig.cursor_inspected.connect(_on_cursor_inspected)
		_on_cursor_moved(_cursor_rig.grid_pos)


## The camera-child mount transform for a UI root authored at [constant FormationScene.SCREEN] px
## and [constant FormationScene.PIXELS_PER_UNIT] world units per px, under an orthographic camera of
## `cam_size`. Returns `{"scale": float, "position": Vector3}`.
##
## `local_z` is the camera-local depth the whole screen sits at; -10 is the shipped `CombatUI` depth
## (`GPUArena.tscn:34`). Pure, so it unit-tests without a camera.
static func mount_transform_for(cam_size: float, local_z: float = -10.0) -> Dictionary:
	var s := cam_size / AUTHORED_ORTHO_SIZE               # 12.6/9.6 = 1.3125
	# The authored screen has its origin at display (0,0) — the TOP-LEFT — so its centre must be
	# pushed back to the camera's local origin, at the scaled size.
	return {
		"scale": s,
		"position": Vector3(-SCREEN.x * 0.5 * PIXELS_PER_UNIT * s,
			SCREEN.y * 0.5 * PIXELS_PER_UNIT * s, local_z),
	}


## Apply [method mount_transform_for] to `node` (this host's ROOT — in practice the coordinator, so
## the DetailScene it overlays inherits the same correction).
##
## [b]THE SCALE IS X/Y ONLY. Z IS LEFT AT 1.0, and that is the whole of this function's care.[/b]
##
## The correction reconciles an authored 256x240 screen against a camera whose ortho height is not
## the authored 9.6 — a SCREEN-SIZE ratio, in the two axes a screen has. Z under this node is not a
## screen quantity at all: it is the ordering-table rung ladder (ADR-0009), `rung *
## DepthMode.UNITS_PER_OT_BUCKET`, an ABSOLUTE depth in world units. Multiplying a depth bucket by
## a screen-size ratio is a category error, and `Vector3.ONE * s` did exactly that.
##
## It was invisible for as long as it was, because `position.z` is pinned at `local_z` (-10) while
## the ladder above it stretches: the correction does not move the stack, it SPLAYS it toward the
## camera. Nothing crosses until a rung is tall enough, and the crossing rung is
## `-local_z / UNITS_PER_OT_BUCKET / s` — 52.6 at x1.0, but only [b]40.1[/b] at x1.3125.
##
## The gambit surface (#1007) is the first screen in the tree with a stack that tall: its glove is
## `depth_rung -6 + RP 52` = rung 46, so 46 * 0.19 = 8.74 local, and
##
##   x1.0     -> -10 + 8.74  = -1.26   in front of `near` 0.1
##   x1.3125  -> -10 + 11.47 = +1.47   BEHIND the camera — near-plane clipped
##
## It read as "the modal opens but the UI elements do not show up": the surface existed, held the
## pad, was `visible_in_tree`, was not culled, had real AABBs, and had a SETTLED box-open — and
## every quad was clipped. Its siblings escape only because their entry recipes pan the camera to
## the authored size first (`begin_pan`, latched at the EQUIP group's seam), which rides s to 1.0
## before they are looked at; the gambit surface mounts with no transition group, so it is the one
## screen that renders while s is still 1.3125. Fixing the ladder rather than adding a pan is what
## makes the screen correct AT EVERY s — including mid-ride, which is a state ADR-0137 Amendment 3
## explicitly puts every screen through.
##
## MEASURED on the shipped `GambitBattle.tscn`: entering GAMBIT straight from DETAIL reported
## `cam.size=12.600 scale=1.3125 z_max=+1.471` and drew nothing; after any sibling sub-screen had
## paid the pan, `9.600 / 1.0 / -1.260` and drew correctly.
static func apply_mount_transform(node: Node3D, cam: Camera3D, local_z: float = -10.0) -> void:
	var m := mount_transform_for(cam.size, local_z)
	var s := float(m["scale"])
	node.scale = Vector3(s, s, 1.0)
	node.position = m["position"]


# -----------------------------------------------------------------------------
# Cursor -> selection (the LISTENER half of `cursor_confirmed`; ADR-0137 / CONTEXT.md "Tile cursor")
# -----------------------------------------------------------------------------

func _on_cursor_moved(grid_pos: Vector2i) -> void:
	# The UNIT first, the identity from it — one lookup, and the live half is what the vitals
	# gauges need. `_character_at` asks `_unit_at` for exactly this and throws the unit away, which
	# is how the panel came to be built from the identity alone (see [method vitals_view_for]).
	var unit = _unit_at.call(grid_pos) if _unit_at.is_valid() else null
	var character = character_for_unit(unit)
	if character == _hovered:
		# Same identity, so no repaint — but the cursor may have stepped between two tiles that
		# resolve to the same Character (an unresolvable ghost answers null on both), and the field
		# that feeds the live gauges must not go stale behind the early return.
		_hovered_unit = unit
		_watch_vitals(unit)
		return
	_hovered = character
	_hovered_unit = unit
	_watch_vitals(unit)
	# The pair repaints; it never RECONSTRUCTS (ADR-0137). One cluster is built at mount and every
	# hover re-binds its views — the last two perf fixes on this screen
	# (`ui3-debug-page-rebuild-is-additive`, `ui3-picker-lag-was-manifest-reparse`) were both
	# construction costs misread as animation costs. No debounce until a stutter is actually seen.
	if character != null:
		_push_pair_views(character, unit)
		_arm_hover(1)
	else:
		_arm_hover(-1)
	unit_hovered.emit(character)


## ○/Enter — ACT on the unit under the cursor. What acting MEANS is the host's business: while the
## deployment march holds the claim (`can_open` false) it means "deploy this unit" and the host
## answers instead of us; otherwise it means "open this unit's screen with its menu up".
func _on_cursor_confirmed(grid_pos: Vector2i) -> void:
	if can_open.is_valid() and not can_open.call():
		return          # the deployment march owns ○ while it runs — the host acts, not us
	_open_for(grid_pos, true)


## △/Tab — GO INTO the unit's menus (ADR-0137 Amendment 6). Never gated: no phase, no march and no
## camera driver has a reason to refuse a LOOK, and refusing it for the whole PLACEMENT phase is
## what made the screen unreachable at boot.
##
## It now opens the screen WITH its menu up, which Amendment 2 deliberately did not do. That
## distinction — △ opens it menu-closed, ○ opens it menu-up — cost a THIRD key to reach the rows
## from the △ path, and a third key is what the user rejected: △ means "show me this unit's menus",
## so it should land on the menus. Closing the menu is ✕, and △ again brings it back.
func _on_cursor_inspected(grid_pos: Vector2i) -> void:
	_open_for(grid_pos, true)


## The one place either intent turns into an open. `acting` is now true from BOTH doors (Amendment
## 6) — the parameter survives because the deployment march still has to distinguish them at the
## gate above, not because the screen does.
func _open_for(grid_pos: Vector2i, acting: bool) -> void:
	var character = _character_at(grid_pos)
	if character == null:
		return          # an empty tile does nothing (ADR-0137 — no confirm dialog)
	_selected = character
	_selected_unit = _unit_at.call(grid_pos) if _unit_at.is_valid() else null
	_push_pair_views(character, _selected_unit)
	if acting:
		unit_act_requested.emit(character)
	unit_activated.emit(character)


## The character currently under the cursor, whether or not it has been confirmed.
func hovered_character():
	return _hovered


## The unit standing on `grid_pos`, as the CHARACTER this screen renders. A battlefield [Unit] is
## bound to its catalogue Character by the `character_slug` meta [UnitSpawn.build] stamps,
## which is the only link between the two.
func _character_at(grid_pos: Vector2i):
	if not _unit_at.is_valid():
		return null
	return character_for_unit(_unit_at.call(grid_pos))


## Resolve a spawned battlefield [Unit] back to the Character it was built from (ADR-0180
## dec. 6 + Amendment 2). Static + null-safe so both map-bearing hosts and the guards share
## the one implementation.
##
## The retired version keyed off `roster_index` + `roster_team` and looked the pair up in the
## PartyRoster / EnemyRoster autoloads. Only `BaseRoster.spawn_unit` set those metas, and the
## deploy seam that actually places owned units at Gariland
## ([NavigatorMain]`._spawn_owned_unit`) set neither — so this returned **null for every
## navigator-deployed unit**, silently, which on the map host is indistinguishable from an
## empty tile.
##
## The slug that replaced it fixed that population and MISSED another, the same way and for
## the same reason: a slug is an address, and dec. 6's premise was that there is now one
## population to resolve it against. There is not. Measured on the arena's own Gariland
## cast, 6 of 13 units resolved to null — the five ENTD generics, whose slug is the EMPTY
## STRING ([Character.create_default] leaves it for "Catalog promotion" and a nameless enemy
## is never promoted), and **Delita**, the ENTD-blue guest on team0, whose slug is real and
## whose registration the arena never folds. Every one of them read as an empty tile: no
## hover pair over an enemy, and none over the guest fighting beside you.
##
## So ask the meta that carries the identity rather than an address for it
## ([UnitSpawn.CHARACTER_META], stamped by the one spawn seam). The slug lookup stays as the
## FALLBACK — for a unit some other seam built, and because the catalogue is still
## authoritative for a Character the player can rename.
static func character_for_unit(unit):
	if unit == null or not is_instance_valid(unit):
		return null
	if unit.has_meta(UnitSpawn.CHARACTER_META):
		var character = unit.get_meta(UnitSpawn.CHARACTER_META)
		if character != null:
			return character
	if not unit.has_meta(UnitSpawn.CHARACTER_SLUG_META):
		return null
	return UIRoster.get_character(String(unit.get_meta(UnitSpawn.CHARACTER_SLUG_META)))


## The 1-based slot number the nameplate prints. On the roster host this is the grid slot; here it
## is the unit's place in the OWNED order — the same number the out-of-battle screen shows it
## under, because that screen renders the same list.
##
## A unit outside the overlay — an ENTD enemy, an ENTD-blue guest like Delita, an unresolvable
## ghost — has NO slot, and this answers **0** for it. It used to answer 1, on the reasoning that
## "the nameplate still has to print something": that put a confident `01` on the plate over every
## enemy in the game, the same number Ramza's plate carries, and a wrong number is worse than no
## number because the player reads it as an answer. `find` already yields -1 here; 0 is what that
## means, and [UIUnitNameplate.set_view] skips the digits for it. The blue orb bullet is a
## separate mount, so such a plate keeps its bullet and loses only the number.
##
## ⚠️ 0 IS NOT A SLOT AND MUST NOT BE PADDED. The digits are zero-padded to two, so a 0 that
## reached the mount would render `00` — the failure this returns 0 to avoid, wearing a different
## face. The skip is in the nameplate, where the printing is.
static func slot_number_for(unit) -> int:
	var character = character_for_unit(unit)
	if character == null:
		return 0
	var pos: int = UIRoster.owned_slugs().find(character.slug)
	return pos + 1 if pos >= 0 else 0


## Re-bind the (screen-common) docked pair to `character`. The roster host drives this from its cell
## selection; here the tile cursor does. Uses the roster host's OWN view builders so the two hosts
## paint byte-identical panels — this screen differs in its backdrop, not in its data.
##
## `unit` is the battlefield [Unit] that identity is STANDING as, or null when it is not on the
## field (the harness hook, a benched unit during a deployment pick). It is PASSED, never re-fetched
## from the cursor rig: the caller has already resolved it, and a second `_unit_at(_cursor_rig.
## grid_pos)` answers for wherever the cursor is NOW — which is not the tile the repaint is about
## the moment either the selection or the pick grid is what is being painted.
func _push_pair_views(character, unit) -> void:
	if _cluster == null or not is_instance_valid(_cluster):
		return
	if character == null or character.progression == null:
		return
	_cluster.set_unit_view(vitals_view_for(character, unit))
	_cluster.set_nameplate_view(info_view_from_character(character, slot_number_for(unit)))


## THE BATTLE VITALS VIEW: the identity's panel with the LIVE unit's current HP/MP + statuses
## written over it.
##
## [method FormationScene.vitals_view_from_character] is the OUT-OF-BATTLE builder, and it cannot
## report damage even in principle — [UnitProgression] holds no current HP at all, only
## `get_effective_hp()`, so that builder writes `current_hp = max_hp` BY CONSTRUCTION. On the roster
## screen that is the right answer (nobody in a menu has been hit). On a battlefield it is never the
## right answer, and pushing it here is what made the hover panel report FULL HP for every unit in
## the fight, however hurt: reported on `NavigatorMain` as *"let it run so units get damaged some,
## move the cursor over them and they have full HP."*
##
## Live damage lands on the unit's [UnitStats] (`CombatLoop._apply_hp_change` writes
## `unit_stats.current_hp` off the GPU readback), so that is the one place to read it from. What is
## overlaid is only what the fight can MOVE: the numerators, and the status list. Name, job, level,
## exp and the DENOMINATORS stay the identity's — a Change-Job commit is what moves those, and the
## identity is where that lands.
##
## THE PORTRAIT IS SPLIT DOWN THE MIDDLE, and `display_from_template(template_folder,
## fallback_sprite_id)` already spells the split in its own signature — the two arguments have two
## different owners:
##
## - `fallback_sprite_id` is JOB-ROUTED. A Change-Job moves it, so it stays the IDENTITY's, like
##   the job name beside it.
## - `template_folder` IS the materialized Form. ADR-0079 forbids the identity from holding a
##   durable `special_name`, so on a battlefield the UNIT is the only object that holds one —
##   [method UnitSpawn.build] resolves the folder at spawn through the one template resolver, and
##   the scenario spawn seam reads it straight off the ENTD slot
##   (`ScenarioPlayerScene._resolve_template_folder`).
##   So it is OVERLAID, both ways: a unit that job-routes shows the job route even under a stamped
##   identity, and a unit standing as a unique shows the unique even under an unstamped one.
##
## That second leg is not hypothetical — it is the defect this overlay exists for. Orbonne (root 3,
## ENTD 387) is a PREDETERMINED battle, so neither deploy seam runs, `NavigatorMain._make_combat_ready`
## binds the CATALOGUE Ramza with `special_name = 0`, and the panel drew the generic Squire face
## while the turn-queue card one row away drew `templates/ramza_2/`. Both readers now read the
## unit's field, so they agree BY CONSTRUCTION rather than by both being stamped in time.
## [FieldInspectController.view_from_unit] and [TurnQueueHud._template_folder_of] are the other two
## readers, and they already source it this way.
##
## CT is deliberately left as the identity's dash row. There is no CPU-side turn gauge to read
## (nothing in `GPUCombatPacker.UnitField` mirrors one back), and a confident `0/100` under the
## cursor would be a wrong number rather than a missing one — the same rule
## [method slot_number_for] follows for a unit with no slot.
##
## Static + null-safe so both battle hosts and the guards can ask it without a host.
static func vitals_view_for(character, unit) -> Dictionary:
	var view := vitals_view_from_character(character)
	if unit == null or not is_instance_valid(unit):
		return view
	var stats = unit.get("unit_stats")
	if stats != null:
		view["current_hp"] = int(stats.current_hp)
		view["max_hp"] = int(stats.max_hp)
		view["current_mp"] = int(stats.current_mp)
		view["max_mp"] = int(stats.max_mp)
	var status = unit.get_node_or_null("UnitStatusManager")
	if status != null and status.has_method("get_all_statuses"):
		var names: Array = []
		for s in status.get_all_statuses():
			names.append(String(s).capitalize())
		view["statuses"] = names
	# The portrait's FOLDER half (see above): the unit holds the materialized Form, so it answers
	# for it whenever there IS a unit — including with "", which is a generic's real answer and not
	# a missing one. `sprite_id` is untouched; it is job-routed and stays the identity's.
	var folder = unit.get("template_folder")
	if folder != null:
		view["template_folder"] = String(folder)
	return view


## Follow the LIVE unit's HP/MP while the cursor is parked on it.
##
## The repaint above fires on a cursor MOVE, and a player who parks over a unit and watches it get
## hit is not moving the cursor — so without this the panel is correct only until the next hit. It
## is event-driven rather than per-frame on purpose: the nameplate rebuilds its glyph tree on
## `set_view`, so a per-frame repaint of the pair would pay a construction cost every frame for a
## number that changes a few times a battle. This re-pushes the VITALS half only.
func _watch_vitals(unit) -> void:
	if unit == _vitals_watched:
		return
	if _vitals_watched != null and is_instance_valid(_vitals_watched):
		var old_stats = _vitals_watched.get("unit_stats")
		if old_stats != null:
			if old_stats.hp_changed.is_connected(_on_watched_vitals_changed):
				old_stats.hp_changed.disconnect(_on_watched_vitals_changed)
			if old_stats.mp_changed.is_connected(_on_watched_vitals_changed):
				old_stats.mp_changed.disconnect(_on_watched_vitals_changed)
	_vitals_watched = unit
	if unit == null or not is_instance_valid(unit):
		return
	var stats = unit.get("unit_stats")
	if stats == null:
		return
	if not stats.hp_changed.is_connected(_on_watched_vitals_changed):
		stats.hp_changed.connect(_on_watched_vitals_changed)
	if not stats.mp_changed.is_connected(_on_watched_vitals_changed):
		stats.mp_changed.connect(_on_watched_vitals_changed)


## The watched unit's HP or MP moved — re-read the gauges. The nameplate is untouched (nothing on
## it can change from a hit), so this is the cheap half of the repaint.
func _on_watched_vitals_changed(_old: int, _new: int) -> void:
	if _cluster == null or not is_instance_valid(_cluster):
		return
	if _hovered == null or _hovered.progression == null:
		return
	if _vitals_watched != _hovered_unit:
		return
	_cluster.set_unit_view(vitals_view_for(_hovered, _hovered_unit))


## Repaint the docked pair for THIS host's selection — the third question the map host has to
## re-answer, beside [method selected_character] and [method selected_unit_screen_center].
##
## The inherited one reads `selected_cell` and indexes `_roster_characters()` with it. This host
## has no grid and never writes `selected_cell`, so the index was always `0*COLS + 0` = 0 — the
## first owned unit, Ramza. Nothing on the way IN reached it (hover and open both go through
## [method _push_pair_views]), which is why it stayed invisible; the way OUT does.
## `FormationDetailTransition._restore_formation` calls `refresh_selection_readouts()` on the way
## back from a screen, so ✕ out of DETAIL repainted the pair with Ramza no matter whose screen
## had just closed, and the cursor was left standing over somebody else.
##
## The cursor is the selection here, so the answer is what it is over NOW (`_hovered`) — the
## user's own words for the fix. `_selected` is the unit whose screen was open, which is the same
## character on the common path and the WRONG one the moment the two diverge.
##
## Its stated reason survives the override intact: a sub-screen can MUTATE the unit (a Change-Job
## commit recomputes HP/MP), so the pair has to be re-read and not merely re-shown.
## [method _push_pair_views] is this host's repaint primitive and re-reads both views.
func _update_vitals_for_selection() -> void:
	# While a pick is open the GRID says who is selected, so the pair reads the cell rather than
	# the hover — the tile cursor is frozen and `_hovered` is whatever it last passed over (#941).
	if _picking:
		# A pick's grid answers with a BENCHED unit as readily as a deployed one, and this host has
		# no character->unit reverse lookup to tell which. Deployment is also the one phase where
		# nobody has been hit yet, so the identity's full-HP view is the true one here.
		_push_pair_views(selected_character(), null)
		return
	if _hovered != null:
		_push_pair_views(_hovered, _hovered_unit)
	else:
		_push_pair_views(_selected, _selected_unit)


# -----------------------------------------------------------------------------
# The camera PAN — the map host's answer to "put the unit on the breakout mark".
#
# Driven as ADR-0084 BEATS (pure functions of `frame`), never `await`, so the coordinator's
# recipe can play it forward on enter and its distinct reverse driver on exit, and the boot-time
# reversibility audit can see it.
# -----------------------------------------------------------------------------

## Take the camera WITHOUT moving it — DETAIL entry (ADR-0137 Amendment 5). The takeover is what
## freezes the tile cursor, hides the dagger and kills camera rotation (all already gated on
## `camera_mode == CURSOR`), and that part still belongs at DETAIL entry: the view must stop being
## the player's the moment a screen is up.
##
## The MOTION does not belong here any more. Settled Status tiles four opaque frames across
## `y32..231`, so the unit the pan aims at is behind them — the ADR panned first precisely so the
## move would be SEEN, but the user played it and reported the opposite: you pan, and then the
## panels cover what you panned to. It is the sub-screen that narrows the frames to `x14..138` and
## actually reveals the unit, so that is where the move goes.
func begin_hold() -> void:
	if _player_camera == null or not is_instance_valid(_player_camera) or _camera == null:
		return
	_pan_from = _player_camera.global_position
	_pan_to = _pan_from                       # a HOLD is a pan whose ends coincide
	_pan_size_from = _camera.size
	_pan_size_to = _pan_size_from
	_pan_rot = _camera.get_parent().global_rotation
	# Only if the camera is not ALREADY ours — the same guard `begin_pan` carries, and needed here
	# for the same reason as of ADR-0261: the coordinator takes this claim on the stack's first push
	# and the MAP_DETAIL recipe's own forward beat asks for it again a frame later. A second
	# `request_takeover` re-latches `_saved_global_pos`/`_saved_camera_size` from the TAKEOVER pose,
	# so what `release_takeover` eases home to becomes the pose it was already at.
	if not _panning:
		_player_camera.request_takeover(self)   # latches `_saved_camera_size` — what release eases back to
	_panning = true


## Latch the pan+zoom MOTION, at sub-screen entry. Assumes the camera is already held (`begin_hold`
## ran at DETAIL entry), so it re-latches the ends rather than re-taking a camera it owns.
## Computes the body position that lands `character` on the breakout mark.
func begin_pan(character = null) -> void:
	if _player_camera == null or not is_instance_valid(_player_camera) or _camera == null:
		return
	var unit = _unit_node_for(character if character != null else _selected)
	if unit == null:
		return
	_pan_from = _player_camera.global_position
	_pan_size_from = _camera.size
	_pan_size_to = AUTHORED_ORTHO_SIZE
	# The mark is satisfied at the END of the gesture, so the delta is computed at the END size —
	# a display px is worth `size/240` world units, and the size is no longer what it was when the
	# pan was latched. Reading `_camera.size` here (as this did while the size was constant) would
	# aim at the pre-zoom framing and land the unit off the mark by the zoom ratio.
	_pan_to = _pan_from + _body_delta_to_mark(unit.global_position, _pan_size_to)
	_pan_rot = _camera.get_parent().global_rotation
	if not _panning:
		_player_camera.request_takeover(self)   # only if the hold did not already take it
	_panning = true


## Forward pan driver — frame 1..PAN_DURATION. Cosine ease in-out, matching the shape
## `release_takeover` uses on the way back so the two reads as one motion.
func pan_step_forward(frame: int) -> void:
	if not _panning or _player_camera == null or not is_instance_valid(_player_camera):
		return
	var t := clampf(float(frame) / float(pan_duration()), 0.0, 1.0)
	var ct := 0.5 - 0.5 * cos(PI * t)
	# Pan AND zoom, on one ease, so they read as a single move rather than two (Amendment 3).
	_player_camera.apply_takeover(_pan_from.lerp(_pan_to, ct), _pan_rot,
		lerpf(_pan_size_from, _pan_size_to, ct))


## REVERSE pan driver — genuinely asymmetric (ADR-0084). It is not the forward pan run backward:
## `release_takeover()` lerps the body to the cursor's own tile (ADR-0041 — the cursor, not a
## saved position, is authority on body XYZ) on its OWN cosine ease inside `PlayerCamera._process`.
## So frame 1 hands the camera back and every later frame is a deliberate no-op: the beat's only job
## from there is to hold the recipe's barrier open until the camera has actually arrived.
##
## That the return lands where we started is a TWO-ADR result, not luck: it equals the original
## position precisely because ADR-0084's "a screen that is up owns the whole pad" kept the cursor
## from moving while the screen was open.
func pan_step_reverse(frame: int) -> void:
	if frame != 1:
		return
	if _player_camera != null and is_instance_valid(_player_camera):
		_player_camera.release_takeover()
	_panning = false


func pan_duration() -> int:
	return PAN_DURATION_DEFAULT


## ADR-0068: the authored default lives HERE (its production owner) and the Tunables dashboard /
## F3 panel are pure views of it. `_static_init` binds at class load so a scrub reaches the beat
## even in a scene that never instances this host.
static func _static_init() -> void:
	if Engine.is_editor_hint():
		return
	register_tunables()


static func register_tunables() -> void:
	TunePort.bind(PAN_DURATION_SLUG, PAN_DURATION_DEFAULT, PAN_DURATION_HINT)
	TunePort.bind(PICK_DIM_SLUG, PICK_DIM_DEFAULT, PICK_DIM_HINT)


func is_panning() -> bool:
	return _panning


## World-space translation to apply to the CAMERA BODY so that `feet_world` projects onto
## [constant FEET_MARK_PX].
##
## Orthographic, so this is exact and needs no ray: a display px is `cam_size / SCREEN.y` world
## units in BOTH axes (keep-height), the wanted camera-local offset from screen centre is a plain
## scale of the px offset, and moving the camera by +D moves everything else -D in camera space.
##
## `cam_size` is a PARAMETER rather than a read of `_camera.size` because the gesture now zooms
## (Amendment 3): the mark is satisfied at the pan's END, so the caller passes the size it will
## have arrived at, not the one it is leaving.
func _body_delta_to_mark(feet_world: Vector3, cam_size: float) -> Vector3:
	var upp := cam_size / SCREEN.y                           # world units per display px
	var want := Vector3((FEET_MARK_PX.x - SCREEN.x * 0.5) * upp,
		-(FEET_MARK_PX.y - SCREEN.y * 0.5) * upp, 0.0)
	var cur := _camera.global_transform.affine_inverse() * feet_world
	var local_delta := Vector3(cur.x - want.x, cur.y - want.y, 0.0)
	return _camera.global_transform.basis * local_delta


## The battlefield node the pan aims at. Latched at CONFIRM (`_selected_unit`) rather than re-read
## from the cursor: by the time the pan runs the camera is in TAKEOVER and the cursor is frozen, but
## latching states the intent instead of relying on that.
func _unit_node_for(character):
	if _selected_unit != null and is_instance_valid(_selected_unit):
		return _selected_unit
	if character == null or not _unit_at.is_valid() or _cursor_rig == null:
		return null
	return _unit_at.call(_cursor_rig.grid_pos)
