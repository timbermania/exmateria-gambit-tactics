class_name TurnQueueHud
extends UIWindowHost
## The TURN QUEUE FORECAST — who acts next, drawn as a row of FRAMED cards on a
## subtractive band (design S6, #893; ADR-0269, which supersedes parts of ADR-0244).
##
## One full round-robin deep: the strip extends until every living unit has
## appeared at least once, so it SELF-SCALES. That depth is the whole design
## decision — a slow unit's long wait shows up as the pile of faster turns
## standing in front of it, rather than being implied by a bar the player has to
## do arithmetic on. Leftmost entry is the unit acting now.
##
## === What the redesign changed =================================================
##
## ADR-0244 built this as a bare row of [UIPortraitFrame]s with no chrome, no label,
## no team colour and no lifecycle — five things the user's review named in one
## sitting, and each has an answer here:
##
##   EVERY CARD IS FRAMED, AND THE STRIP IS NOT. A card wears its own [UIFrame]; the
##   bar wears [constant UI3Element.Frame.NONE] and sits on a [UIVitalsBand] instead.
##   ADR-0244 rejected per-card frames for a row of frameless cards, ADR-0269's first
##   build rejected them for one bar frame, and the user has now SEEN both — which is
##   the only thing that could settle it. The bar element stays, as the BAND'S CARRIER:
##   it owns the `OWN_APERTURE` + `BOX_OPEN` that sweep the backdrop open.
##
##   THE BAND IS THE WHOLE SCREEN WIDE. It used to stop at the last portrait, because it
##   was sized to a bar that was sized to the cards. It is still the bar's own payload —
##   that is what makes it ride the aperture for free — but the bar's rect is now the
##   SCREEN's span, derived from the viewport and not written down (see
##   [method _screen_span_px]). The cards left its subtree to make that safe.
##
##   A CARD ENTERS AND LEAVES BY ITS OWN APERTURE, and the three verbs are SERIALISED:
##   the head card closes, THEN the survivors shuffle left, THEN the new tail opens. Each
##   card therefore declares `Clip.OWN_APERTURE` — `BOX_OPEN` is inert without it — and
##   is a sibling of the band rather than a child, so nothing crops it. The chain is built
##   on the elements' `closed` / `moved` signals; there is no clock anywhere in it.
##
##   TEAMS ARE COLOURED, not just mirrored. FFT portraits key palette index 0 to
##   transparent, so the space around a head is a real hole — a coloured underlay
##   fills it and the card's SURROUND carries the side. Mirroring (ADR-0244 dec. 7)
##   is kept, but it only reads when two entries are adjacent to compare, which is
##   exactly the case a queue cannot promise.
##
##   IT IS UP FOR THE WHOLE BATTLE. The strip opens when the battle starts and closes
##   when it ends; `turn_opened` / `resumed` still drive the REFRESH, because they are
##   the two edges the queue can have changed on, but they no longer gate visibility.
##   The one thing that hides it is a full-screen unit screen opening OVER the
##   battlefield ([method set_covered]) — and that plays the box-open beat backwards
##   rather than dropping `visible`, so the strip leaves and returns the way it arrived.
##
##   IT IS MADE OF UI3 ELEMENTS. Every part — the band and each card — is a
##   [UI3Element] with declared criteria, so it inherits the whole system: the
##   box-open aperture, the slide beat and its cadences, clip, and F3-live criteria.
##
## === What it costs =============================================================
##
## Nothing per frame while it is settled. The forecast is closed-form arithmetic
## over the turn meters ([TurnQueue]) and is recomputed only on the two edges where
## the queue can have changed — a turn opening, and the world resuming afterwards.
## Those are the same two moments the player looks at it. There is no `_process`
## here and no per-frame readback; the transitions cost only while they play, and
## the shared UI3 engine owns that loop.
##
## That survives always-on, and it survives the band. The band's aperture uniforms are
## pushed by the CLIP ENGINE, not by this class, because its mesh lives in the bar's own
## payload subtree — so it rides `_set_aperture` and `refresh_clip_basis` exactly as the
## cards do, and this class never grew the per-frame push a hand-rolled backdrop needs.
##
## Between those edges the queue is a PROJECTION, and it is wrong under exactly
## the three conditions [TurnQueue] names — Haste/Slow, deaths, reinforcements —
## the same caveat every turn-queue game carries.
##
## === What it is NOT ============================================================
##
## **Not a component of the director.** It reads [method TurnDirector.forecast]
## and never writes: nothing here can freeze, commit or advance anything, so a HUD
## bug cannot become a battle bug.
##
## **Not a roster.** [UIRosterBar] draws one frame per UNIT; this draws one card
## per TURN, and a fast unit legitimately appears twice in the same strip.
##
## **Not a selector.** No click areas — a queue entry is information, and the thing
## you steer is the unit whose turn is open, which is the host's question (#894).

const TunePort = ExMateriaPlatform.TunePort

## ADR-0211 dec. 4 — the host autoload `PSXDisplay` is not nameable from inside an
## addon (every stranger rig declares an empty `[autoload]` block), so UI PAR is
## read and subscribed through the platform port. #1263 / ADR-0308.
const DisplayPort = ExMateriaPlatform.DisplayPort

const _UNDERLAY_SHADER := preload("res://assets/shaders/turn_queue_team_underlay.gdshader")

## The fold-rung ladder (ADR-0088 depth_rung + rp), back to front: the band under the whole
## strip, then each card's own frame, its team underlay, and its portrait. The chrome is
## BEHIND its own payload; a card's underlay is behind its portrait.
##
## The band is on the BAR and the other three are on a CARD, so the ladder crosses two
## elements — which is exactly why it is one table here rather than three literals.
const RP_BAND := 36
const RP_FRAME := 40
const RP_UNDERLAY := 44
const RP_PORTRAIT := 48

## Portrait footprint, DERIVED and not restated. [UIPortrait] samples a 48x32 cell and
## draws it rotated: its own `_update_mesh` computes width = `tex_height * PAR` and
## height = `tex_width`, so the footprint is (32*PAR, 48) — at PAR 1.25, 40 wide by 48
## tall. The pre-ADR-0269 constant here read `Vector2(48, 40)`: the two axes
## TRANSPOSED, which laid an 18 px-wide portrait out on a 21.6 px pitch and was part of
## what read as "wrong resolution". Reading it off UIPortrait's own constants is what
## stops that ever drifting again.
##
## PAR is READ here, never written — the portraits keep their subscription to the
## global `render.ui_pixel_aspect` and this follows them (see `_on_par_changed`).
static func portrait_base() -> Vector2:
	return Vector2(float(UIPortrait.DEFAULT_PORTRAIT_TEX_HEIGHT) * DisplayPort.live_ui_par(),
		float(UIPortrait.DEFAULT_PORTRAIT_TEX_WIDTH))


# --- Tunables (ADR-0068: the static var IS the home; the panel is a view) ------

## Portrait size multiplier. Eleven entries is a normal Gariland round-robin.
##
## A note for whoever scrubs this: a UI virtual px is `0.04 * 960/14 = 2.743` SCREEN px
## after [UIWindowHost]'s camera counter-scale, so a portrait texel lands on
## `scale * 2.743` screen px. At 0.45 that is 1.23 — some texels get one screen px and
## some get two, which is uneven UNDERSAMPLING and reads as "wrong resolution" rather
## than as small. 0.3646 lands exactly 1.0 and 0.7292 exactly 2.0. The real fix for the
## whole of ui3 is `pixels_per_unit = 0.04375` (a flat 3.0 everywhere) and is its own ticket.
##
## THE DEFAULT IS 0.85 AND IS NOT ONE OF THOSE EXACT RATIOS. It was dialed on the strip and
## materialized (ADR-0068 dec. 8), and what it buys is the fill the card/portrait split was cut
## for. MEASURED on a booted tree: against a card still at `card_scale` 0.7292 — 32x45 display px
## — a 0.85 face is 27.2x40.8 and sits at `portrait_offset` (2, 2), so the bare card left around
## it is (2, 2, 2.8, 2.2). At 0.7292 the face was 23.3x35.0 at the frame's own margins and left
## (4, 5, 4.7, 5.0). The face fills the frame now; it used to sit in the corner of one.
##
## So the sampling argument above is TRADED here, not answered: 0.85 lands a texel on 2.33 screen
## px, which is the same uneven undersampling 0.45 was faulted for, at a different ratio. It won
## by looking at portraits on the strip, which is the judgement 0.45 lost. 0.7292 (exactly 2.0)
## and 0.3646 (exactly 1.0) are still the two values that ANSWER the arithmetic, if the
## resampling is ever judged worse than the fill — 0.3646 is a quarter of the area, if the strip
## is also judged too dominant.
const SCALE_SLUG := "turnqueue.portrait_scale"
static var PORTRAIT_SCALE_DEFAULT := 0.85
const SCALE_HINT := {"min": 0.2, "max": 1.5, "step": 0.0001}

## The CARD's size multiplier, against the same [method portrait_base] footprint
## `portrait_scale` uses — so at equal values the card is exactly the face plus its border and
## the pair behaves as the single knob it used to be.
##
## It exists because the card used to be DERIVED from the portrait: `_card_size()` read
## `_portrait_size()`, so the frame had no size of its own and the portrait/frame ratio was a
## constant fixed by [UIFrame]'s margins. Scrubbing `portrait_scale` grew both together, which
## is why "make the face fill the frame" was not a value anyone could dial — there was one
## degree of freedom for the whole chain. Splitting it gives the frame an authored size, which
## is the property that makes the VITALS portrait adjustable ([UIUnitInfoWindow]'s `frame_size`)
## and the one worth copying. Raise `portrait_scale` above this and the face grows INSIDE a card
## that stays put.
##
## ⚠️ This default STAYED at 0.7292 when [member PORTRAIT_SCALE_DEFAULT] went to 0.85, and the
## divergence is the split working rather than drift. The split LANDED as a no-op — both at
## 0.7292, same pixels before and after — and the first dial after it moved one knob and not the
## other. Do not "restore" the match: a face larger than its slot is the degree of freedom this
## knob was cut to give, and the two answer different questions now.
##
## Note this is the knob that moves LAYOUT. It drives the bar's rect, every card's rect and the
## band's relayout; `portrait_scale` drives none of them and only reshapes payload.
const CARD_SCALE_SLUG := "turnqueue.card_scale"
static var CARD_SCALE_DEFAULT := 0.7292
const CARD_SCALE_HINT := {"min": 0.2, "max": 1.5, "step": 0.0001}

## Where the face sits inside its card, in display px from the card's top-left.
##
## The default is (2, 2), dialed and materialized (ADR-0068 dec. 8). It STARTED at
## `(UIFrame.MARGIN_LEFT, UIFrame.MARGIN_TOP)` = (4, 5) — the inset [method _resize_card] used to
## FORCE, which is what made this knob a no-op at rest — and it moved in the same gesture that
## took `portrait_scale` to 0.85: a 27.2x40.8 face in a 32x45 card is centred by a ~2 px inset,
## not by the frame's margins. CHANGE EITHER ALONE AND THE FACE GOES OFF-CENTRE.
##
## Written as a literal and NOT as `Vector2(UIFrame.MARGIN_LEFT, UIFrame.MARGIN_TOP)` for the
## same reason `band_sub` is a literal: `tools/materialize_tunables.py` skips a non-literal
## default, and every future dial on this knob would be hand work. That is what paid off here —
## this dial went through the codemod rather than being hand-baked.
##
## CLASS-level, one offset for all eleven cards, per ADR-0269 dec. 9 — a per-card knob would
## multiply an F3 tree that already stands at ~100 rows, and vitals gets by with exactly one.
##
## ⚠️ Do not "fix" this against [method card_margins], which returns (LEFT, TOP, RIGHT, BOTTOM)
## while [member UIFrame.margins] is (left, right, top, bottom). Both are self-consistent in
## their own file; the two orders are a real difference, not a typo in one of them.
const PORTRAIT_OFFSET_SLUG := "turnqueue.portrait_offset"
static var PORTRAIT_OFFSET_DEFAULT := Vector2(2.0, 2.0)
const PORTRAIT_OFFSET_HINT := {"step": 0.5}

## Gap between the cards' OUTER boxes, in display px.
##
## 3 and not 0, AND THE 0 WAS A PREDICTION THAT LOOKING OVERTURNED. When each card gained its own
## 9-slice border the reasoning here was that the border IS the separation `spacing` used to buy,
## and that a positive gap on top of two adjacent borders would read as a dead channel rather
## than as a queue — so it went to 0, with "is 0 too tight" left open as a looking question. The
## looking came back 3: two abutting borders read as one thick divider between two cards, not as
## two cards. 3 px re-separates them without opening the channel the 0 was guarding against.
const SPACING_SLUG := "turnqueue.spacing"
static var SPACING_DEFAULT := 3.0
const SPACING_HINT := {"min": 0.0, "max": 24.0, "step": 0.5}

## The bar's content inset, display px, as (LEFT, TOP, RIGHT, BOTTOM). One Vector4 and not
## four consts: they are one shape — the margin of band that shows around the card row — and
## four independent knobs would let a scrub make it asymmetric by accident. A rect DRIVER, so
## the bar and every card re-derive on a scrub for free.
const PAD_SLUG := "turnqueue.pad"
static var PAD_DEFAULT := Vector4(6.0, 11.0, 6.0, 11.0)
const PAD_HINT := {"step": 0.5}

## The most cards drawn; overflow is simply not drawn.
##
## This is a DISPLAY POLICY and is now labelled as one. ADR-0244's `max_shown` was a belt
## ("a queue this long has stopped being readable") set at 16 and reported with a warning when
## it bit. Always-on made the width a real constraint rather than a theoretical one: a card
## MEASURES 32 display px wide at `card_scale` 0.7292, so with `spacing` 3 an eleven-card
## round-robin spans 11*32 + 10*3 = 382 of the ~373 display px this frustum gives and does not
## fit. Eight spans 8*32 + 7*3 = 277 and does. The answer is a chosen count, not a smaller
## portrait — 0.3646 is the other exact sampling ratio and is the size the user already called
## unreadable.
##
## ⚠️ Two premises here were RE-MEASURED and had drifted. It reads `card_scale` and not
## `portrait_scale` because the split gave the card its own size — `portrait_scale` moves the
## face INSIDE the card and no longer the pitch. And the width is measured at the PAR the game
## actually runs, which is `PSXDisplay.live_ui_par` = 1.0, NOT the 1.25 the older notes in this
## file assume: 1.25 is the ADR-0036 initial value on [UIPortrait]/[UIFrame]'s `@export`, and
## `live_ui_par` overwrites it on the first PAR notify. At 1.25 the same card would be 38 wide.
##
## No warning fires when it bites, because it is now MEANT to bite: a line printed on every
## Gariland battle is a line nobody reads. ADR-0244 dec. 1 ("an entry is a TURN") is untouched
## — it says what an entry MEANS, not how many of them fit on screen.
const MAX_CARDS_SLUG := "turnqueue.max_cards"
static var MAX_CARDS_DEFAULT := 8
const MAX_CARDS_HINT := {"min": 1, "max": 32, "step": 1}

## Team underlay colours, sRGB straight-alpha. Vector4 and NOT Color: Godot
## sRGB-linearizes a Color on its way into a shader parameter, which would
## double-correct against the underlay shader's own pow(., 2.2).
const ALLY_SLUG := "turnqueue.team_ally"
static var TEAM_ALLY_DEFAULT := Vector4(0.16, 0.24, 0.50, 0.92)
const FOE_SLUG := "turnqueue.team_foe"
static var TEAM_FOE_DEFAULT := Vector4(0.47, 0.14, 0.16, 0.92)

## The band's two dials. `band_sub` is the subtracted grey as fg/255. `band_feather` is how
## many display px the trapezoid takes to reach that strength at the top and bottom edges; 0
## collapses both ramps and the band becomes a flat rectangle (the shader's own documented
## degenerate case). Both live, because how dark a backdrop should be under portraits is
## settled by looking at portraits on it — and both of these values are what that looking
## returned, dialed on the screen and materialized (ADR-0068 dec. 8).
##
## `band_sub` 0.16 (~41/255) is a DELIBERATE DIVERGENCE from the oracle's `base_rgb` 120, and
## the divergence is dec. 7's doing. This band used to be the width of the card row, where
## [FormationScene]'s bottom-stripe strength was the right borrow: same job, same area, so the
## ROM's own number beat inventing one. Dec. 7 ran the band the WHOLE WIDTH OF THE SCREEN, and
## 120/255 over that much battlefield stops reading as a backdrop behind portraits and starts
## reading as a black bar across the map. The ROM number is recorded here as what this is
## measured AGAINST, not as what it is. This closes ADR-0269's `band_sub` soft spot, which is
## exactly the re-judgement it asked for: strength judged at the OLD width, now judged at this
## one.
##
## A plain literal and no longer `120.0 / 255.0`: an expression is not a literal, so materialize
## SKIPS it ("non-literal default — by hand") and every future dial on this knob is hand work.
const BAND_SUB_SLUG := "turnqueue.band_sub"
static var BAND_SUB_DEFAULT := 0.16
const BAND_SUB_HINT := {"min": 0.0, "max": 1.0, "step": 0.01}

const BAND_FEATHER_SLUG := "turnqueue.band_feather"
static var BAND_FEATHER_DEFAULT := 10.0
const BAND_FEATHER_HINT := {"min": 0.0, "max": 32.0, "step": 0.5}

## Top-left of the strip, normalized (0,0 = top-left of the screen). The queue grows RIGHTWARD
## from here, so an anchor on the left keeps the strip's head still while its tail lengthens —
## a centred strip would slide the unit acting now sideways every time the queue's length
## changed.
##
## A `Tune` bind and no longer an `@export`. The export was authorable but not SCRUBBABLE: this
## host is built in code by [method mount], so nothing ever opened an inspector on it and the
## one number that decides where the strip sits was the one number a player could not move.
##
## Deliberately NOT a `<ns>.loc.` KEY LOCATION, which is the other place a position could live.
## A key location is a home a [UI3Element] occupies via `place_at`, and the UI3 page renders one
## with a re-home dropdown listing every element that could move there. This is a [UIWindowHost]
## screen anchor in NORMALIZED screen coordinates — no element is homed at it and `place_at`
## cannot take it — so filing it there would render an affordance that does nothing.
const SCREEN_POS_SLUG := "turnqueue.screen_pos"
## The literal is the clean (0.015, 0.03) and NOT the (0.0149999996647239, 0.0299999993294477)
## `materialize_tunables.py` emitted: a Vector2 component is a float32, the snapshot round-tripped
## it through one, and those two spellings are the SAME 32 bits. Only the readable one is kept.
static var SCREEN_POS_DEFAULT := Vector2(0.015, 0.03)
const SCREEN_POS_HINT := {"step": 0.005}

static var _tunables_bound := false


## Bind this class's knobs. Lazy + idempotent: the element specs below name
## CARD_SCALE_SLUG / SPACING_SLUG as rect DRIVERS, and a driver must be registered before
## the element that subscribes to it constructs (Tune.on_update asserts it).
static func bind_tunables() -> void:
	if _tunables_bound:
		return
	_tunables_bound = true
	TunePort.bind(SCALE_SLUG, PORTRAIT_SCALE_DEFAULT, SCALE_HINT)
	TunePort.bind(CARD_SCALE_SLUG, CARD_SCALE_DEFAULT, CARD_SCALE_HINT)
	TunePort.bind(PORTRAIT_OFFSET_SLUG, PORTRAIT_OFFSET_DEFAULT, PORTRAIT_OFFSET_HINT)
	TunePort.bind(SPACING_SLUG, SPACING_DEFAULT, SPACING_HINT)
	TunePort.bind(PAD_SLUG, PAD_DEFAULT, PAD_HINT)
	TunePort.bind(MAX_CARDS_SLUG, MAX_CARDS_DEFAULT, MAX_CARDS_HINT)
	TunePort.bind(ALLY_SLUG, TEAM_ALLY_DEFAULT)
	TunePort.bind(FOE_SLUG, TEAM_FOE_DEFAULT)
	TunePort.bind(BAND_SUB_SLUG, BAND_SUB_DEFAULT, BAND_SUB_HINT)
	TunePort.bind(BAND_FEATHER_SLUG, BAND_FEATHER_DEFAULT, BAND_FEATHER_HINT)
	TunePort.bind(SCREEN_POS_SLUG, SCREEN_POS_DEFAULT, SCREEN_POS_HINT)


static func portrait_scale() -> float:
	bind_tunables()
	return float(TunePort.get_value(SCALE_SLUG, PORTRAIT_SCALE_DEFAULT))


static func card_scale() -> float:
	bind_tunables()
	return float(TunePort.get_value(CARD_SCALE_SLUG, CARD_SCALE_DEFAULT))


## The face's top-left inside its card, display px.
static func portrait_offset() -> Vector2:
	bind_tunables()
	return Vector2(TunePort.get_value(PORTRAIT_OFFSET_SLUG, PORTRAIT_OFFSET_DEFAULT))


static func spacing() -> float:
	bind_tunables()
	return float(TunePort.get_value(SPACING_SLUG, SPACING_DEFAULT))


## The bar's content inset (LEFT, TOP, RIGHT, BOTTOM), display px.
static func pad() -> Vector4:
	bind_tunables()
	return Vector4(TunePort.get_value(PAD_SLUG, PAD_DEFAULT))


static func max_cards() -> int:
	bind_tunables()
	return maxi(1, int(TunePort.get_value(MAX_CARDS_SLUG, MAX_CARDS_DEFAULT)))


static func team_tint(team: int) -> Vector4:
	bind_tunables()
	return Vector4(TunePort.get_value(FOE_SLUG if team != 0 else ALLY_SLUG, TEAM_FOE_DEFAULT if team != 0 else TEAM_ALLY_DEFAULT))


static func band_sub() -> float:
	bind_tunables()
	return float(TunePort.get_value(BAND_SUB_SLUG, BAND_SUB_DEFAULT))


static func band_feather() -> float:
	bind_tunables()
	return maxf(0.0, float(TunePort.get_value(BAND_FEATHER_SLUG, BAND_FEATHER_DEFAULT)))


static func screen_pos() -> Vector2:
	bind_tunables()
	return Vector2(TunePort.get_value(SCREEN_POS_SLUG, SCREEN_POS_DEFAULT))


## The 9-slice border a framed card spends, as (LEFT, TOP, RIGHT, BOTTOM) display px.
##
## READ off [UIFrame]'s own MENU_TILE margins and never restated, for the same reason
## [method portrait_base] reads UIPortrait's: the frame's crop already moved once (the ROM
## dark-outline column pushed left/top from 3/4 to 4/5), and a second copy of those numbers
## here would have silently drawn the border over the faces the next time it moves.
static func card_margins() -> Vector4:
	return Vector4(float(UIFrame.MARGIN_LEFT), float(UIFrame.MARGIN_TOP),
		float(UIFrame.MARGIN_RIGHT), float(UIFrame.MARGIN_BOTTOM))


# --- Wiring -------------------------------------------------------------------

## The director this reads. Assigned by [method mount].
var director: TurnDirector = null


## How deep to ask for. Passed straight to [method TurnQueue.forecast] as its
## non-termination belt; well above [method max_cards] so the round-robin is complete
## before this class does any trimming of its own.
@export var request_depth: int = 512

## The battle's units, indexed the way the forecast indexes them (global unit
## index). Empty until [method bind_units].
var _units: Array = []
## The host-registered anchor. A plain [Node3D] and not the bar itself: the host
## writes `position.x/y` on whatever it registers, and a UI3Element places itself
## from its own rect — two writers on one transform. The anchor takes the host's
## screen placement, the bar takes UI3's.
var _strip: StripRoot = null
var _bar: UI3Element = null
## The subtractive backdrop the cards sit on ([UIVitalsBand]) — its holder, its mesh and its
## material. All three are held because a queue changes LENGTH every turn and the band has to
## follow: `UIVitalsBand.update_extent` MUTATES the carrier in place, and freeing a member of
## the compositor's fold layer while that layer is compositing corrupts the engine heap on the
## 4.8 fork. So the band is built once and reshaped, never rebuilt.
var _band_holder: Node3D = null
var _band_mesh: MeshInstance3D = null
var _band_mat: ShaderMaterial = null
## Live cards, in TURN ORDER. Each: `{key: [index, team], slot: [int], id: int,
## element: UI3Element, portrait: UIPortrait, tint: ShaderMaterial, open: bool}`. `slot` is a
## one-element ARRAY on purpose — the card's derived rect closure captures it, so
## writing `slot[0]` re-aims the placement without rebuilding the element. `open` is whether
## its entrance has actually been PLAYED: a card exists at its slot from the moment the diff
## names it, and stands there with a shut aperture until the chain reaches its turn.
var _cards: Array[Dictionary] = []
## Cards playing their close. Held so a second refresh mid-close cannot re-adopt one — and it
## is the BARRIER the serialised refresh waits on (see [method _advance_step]).
var _leaving: Array[UI3Element] = []
## Card ids in use (live + leaving). A card's id names a POOL SLOT, not a queue slot:
## ids mint Tune binds, so they must be bounded and stable, while a card's queue slot
## changes every time the strip shuffles.
var _used_ids: Dictionary = {}
## The (index, team) pairs currently drawn. The redraw gate: a portrait is a
## texture fetch and a mesh rebuild, and the queue's ORDER is unchanged across
## most refreshes.
var _shown: Array = []
## The pending serialised refresh: survivors still owed their shuffle, and entrants still owed
## their aperture-open. Both hold the CARD RECORDS rather than the elements, because
## `_open_card` has to stamp `open` on the record it opened.
var _to_move: Array[Dictionary] = []
var _to_open: Array[Dictionary] = []
## Survivors currently walking. A count and not a list: unlike `_leaving`, a card mid-shuffle
## is an ordinary live card and only the barrier has any interest in it.
var _moving: int = 0
## Cards still closing on the STRIP's own close, which the band waits for. Distinct from
## `_leaving`: those are cards a queue DIFF retired and no refresh may re-adopt, while these
## are still the queue — they are going off screen with it.
var _closing_cards: int = 0
## Which refresh the live chain belongs to. Bumped by every arming and by every teardown, so a
## callback from a superseded chain can tell that its queue is gone and decline to advance it.
var _step_gen: int = 0
## The last forecast this was handed, UNTRIMMED. Held for one reason: `turnqueue.max_cards` is
## a live knob, and a knob whose new value only lands on the next turn edge is half a knob.
var _entries: Array = []
## Is a battle running? The strip's gate beside "the queue is non-empty". Defaults TRUE, so a
## test, a capture rig or a battle-only harness with no state machine drives the view without
## knowing about phases — [GambitBattle] is exactly that case and is right to say nothing.
## [NavigatorMain] drives it off `NavigatorRunner.state_changed` (PRE_BATTLE -> BATTLE -> out).
var _battle_live: bool = true
## Is a full-screen unit screen standing over the battlefield? The strip's other gate: the
## map-hosted Formation/Status screen covers the battlefield the strip annotates, so leaving it
## up would draw a turn order over a screen that is not showing the turn.
var _covered: bool = false
## What the bar has been TOLD to do, so a repeat refresh does not restart its beat.
var _bar_open: bool = false
## How many times the strip has actually been repainted. The gate above is only
## observable as work NOT done, and node identity cannot see it (a queue of the
## same LENGTH reuses its cards whether the gate fires or not), so the subject
## counts — the shape `TunablesRegistryViewTest` already reads a rebuild through.
var _draws: int = 0


## The strip's SCREEN ROOT — the node whose local space IS display px, and the node the host
## places by [constant SCREEN_POS_SLUG].
##
## It exists to declare ONE method. [UI3ClipEngine.clip_basis_inv_for] resolves an element's
## clip basis by walking up for the nearest ancestor that DEFINES display space, and it
## identifies that ancestor by `has_method("screen_to_world")` — the idiom DetailScene and
## FormationScene already carry. A bare [Node3D] here answers no, the walk falls through to
## IDENTITY, and `clip_world` (display px * ppu, in THIS node's space) is then compared against
## a GLOBAL vertex position. The two disagree by the host's whole screen placement and camera
## counter-scale, so EVERY clipped fragment falls outside the box: the frame and all its cards
## render nothing at all while the unclipped title above them looks perfectly fine. That is
## exactly the symptom the engine's own docstring describes for the map-camera case, reached
## here by a different route.
##
## The engine only asks WHETHER this method exists and then takes the transform — but the
## method is implemented for real, because a marker that lies about what it computes is worse
## than no marker.
class StripRoot extends Node3D:
	var ppu: float = UI3Element.DEFAULT_PPU

	## Where the host puts this. [UIWindowHost._update_element_positions] prefers a registered
	## node's OWN `screen_pos` property over the value it was registered with, precisely so a
	## live edit lands — so declaring it here is what turns [constant SCREEN_POS_SLUG] from a
	## boot-time reading into a knob that moves the strip while you drag it.
	var screen_pos: Vector2 = TurnQueueHud.SCREEN_POS_DEFAULT

	## World position of a display-space pixel (top-left origin, +X right / -Y down).
	func screen_to_world(px: float, py: float) -> Vector3:
		return Vector3(px * ppu, -py * ppu, 0.0)


## Mount a HUD on a camera, reading a director. The one-line form, the same shape
## [method TurnDirector.mount] and `CursorRig.mount` already established.
##
## The CAMERA and not the host scene: this host places its windows in camera-local
## space (see [UIWindowHost]), which is what makes the strip ride a camera that
## pans over the battlefield without any per-frame work.
static func mount(camera: Node3D, p_director: TurnDirector) -> TurnQueueHud:
	var hud := TurnQueueHud.new()
	hud.name = "TurnQueueHud"
	hud.director = p_director
	camera.add_child(hud)
	return hud


func _ready() -> void:
	# The whole host sits `screen_space_depth` IN FRONT of the camera — the same
	# `z = -10` `CombatCamera.tscn` gives `CombatUI`. [UIWindowHost] places a window
	# by writing only its x and y, so a host left at the camera's own origin puts
	# every window ON the near plane, where it is clipped away: the strip draws
	# perfectly and is invisible, which is the one failure mode a unit test of the
	# layout cannot see.
	position = Vector3(0.0, 0.0, -screen_space_depth)
	bind_tunables()

	var strip := StripRoot.new()
	strip.ppu = pixels_per_unit
	strip.name = "Strip"
	_strip = strip
	add_child(_strip)
	strip.screen_pos = screen_pos()
	register_element("turn_queue", _strip, strip.screen_pos)
	TunePort.on_update(self, SCREEN_POS_SLUG, func(v: Variant) -> void:
		if _strip != null and is_instance_valid(_strip):
			_strip.screen_pos = Vector2(v)
			mark_placement_dirty())
	_build_bar()
	# Nothing to draw until a battle exists; `forecast` is empty through the whole
	# of deployment, so the strip would otherwise be an empty rectangle of nothing
	# during the one phase that has no turn order at all.
	visible = false

	# The layout is a function of PAR (see `portrait_base`), and PAR is live. The same
	# subscription UIPortrait / UIChar / UIFrame / UIUnitInfoWindow already carry.
	if not Engine.is_editor_hint():
		DisplayPort.connect_live_ui_par_changed(_on_par_changed)

	if director != null:
		# The COMPLETE edge set, and it is two signals and not four. `turn_opened`
		# covers the freeze, and cancel/commit both end by either opening the next
		# turn (which emits it again) or resuming. Subscribing to `turn_committed`
		# as well would buy a second readback of a queue that is about to be read
		# a millisecond later.
		director.turn_opened.connect(_on_turn_opened)
		director.resumed.connect(_on_resumed)


## Bind the battle's units. `units[i]` must be the unit at global index `i` — the
## same indexing the GPU buffer and the forecast use.
func bind_units(p_units: Array) -> void:
	_units = p_units
	# Force a full redraw: the same queue over a different cast is a different
	# picture, and the gate below compares indices, which did not move.
	_shown = []
	refresh()


## Recompute from the director and draw. Safe to call at any time.
func refresh() -> void:
	if director == null:
		return
	show_entries(director.forecast(request_depth))


## Draw an already-computed forecast — the pure-view seam. A test drives this with
## fabricated entries and needs no GPU, no director and no battle, which is the
## same reason [TurnQueue] is arithmetic over plain dictionaries.
##
## `entries` are [method TurnQueue.forecast]'s rows: `{index, team,
## ticks_from_now, turn_meter}`, in turn order.
func show_entries(entries: Array) -> void:
	if _bar == null:
		return
	_entries = entries
	var cap := max_cards()
	var shown: Array = entries.slice(0, cap) if entries.size() > cap else entries

	var key: Array = []
	for entry in shown:
		key.append([int(entry["index"]), int(entry["team"])])
	if key == _shown:
		return
	_shown = key

	_draws += 1
	# The band no longer resizes on a queue change: it is the screen's width whatever the queue
	# does, which is the whole of the user's first ask. So a refresh is the DIFF and the
	# lifecycle gate, and nothing else — the two lines that re-aimed and reshaped the bar every
	# turn are gone rather than made conditional.
	_reconcile(shown)
	_sync_open()


## Is a battle running? The strip's lifetime gate, separate from the pure-view seam so
## `show_entries` stays a function of the QUEUE alone.
##
## The strip is up for the WHOLE battle. ADR-0269's first build tied it to the open TURN, on
## ADR-0260's measurement that a Gariland battle stops 8 times: between the stops the strip
## was furniture. Seen on screen, the opposite reading won — what the player wants to know
## between the stops is who is coming, and a forecast that is only there once the answer has
## already arrived is a forecast nobody consults. The knob that restored the old behaviour is
## gone with it: `turnqueue.show_only_on_turn` would now be a knob that names a lifecycle no
## code implements.
func set_battle_live(live: bool) -> void:
	if _battle_live == live:
		return
	_battle_live = live
	_sync_open()


## Is a full-screen unit screen standing over the battlefield? The strip annotates the MAP, and
## the map-hosted Formation/Status screen covers it — see [signal FormationMapHost.unit_activated]
## for the edge that raises this and the transition coordinator's settle back to
## `State.IDLE` for the one that drops it.
##
## It plays the BOX-OPEN BEAT both ways rather than writing `visible`. A strip that vanishes on
## one frame and reappears on another is the only thing on this screen that does not open and
## close like a window, and the beat costs nothing while it is not playing.
func set_covered(covered: bool) -> void:
	if _covered == covered:
		return
	_covered = covered
	_sync_open()


## Does the strip WANT to be on screen right now? Distinct from `visible`, which stays
## true through the bar's close animation.
func is_showing() -> bool:
	return _bar_open


## Repaints so far. The redraw gate's only witness: an unchanged queue must not
## move this, and a reordered one must.
func draws() -> int:
	return _draws


## The turn order currently on screen, as unit indices. For tests and for the
## debug overlay; the strip itself is the production reader.
func shown_indices() -> Array:
	var out: Array = []
	for pair in _shown:
		out.append(pair[0])
	return out


## Live cards, in turn order — the count `_frames()` used to answer. Cards playing
## their fade-OUT are excluded: they are on screen but they are not the queue.
func cards() -> Array[UI3Element]:
	var out: Array[UI3Element] = []
	for rec in _cards:
		out.append(rec["element"])
	return out


## The bar element — the one frame around the strip. For tests and the UI3 page.
func bar() -> UI3Element:
	return _bar


# The two edges the QUEUE can have changed on. They no longer gate visibility — they never
# described the strip's lifetime, only when its contents could be stale.

func _on_turn_opened(_taker: int, _team: int) -> void:
	refresh()


func _on_resumed() -> void:
	refresh()


## The band spans the SCREEN, so its width is a function of the VIEWPORT — and a viewport is not
## a `Tune` slug, so no rect driver re-evaluates when the window resizes. This host already polls
## for exactly that edge, so the strip's answer hangs off the same one rather than growing a
## `_process` of its own (which is the cost ADR-0269 dec. 7 spent the band's mounting to avoid).
func _relayout() -> void:
	super()
	if _bar == null or not is_instance_valid(_bar):
		return
	if _bar.rect().is_equal_approx(_bar_rect()):
		return
	_bar.move_to_answer(UI3MoveSlideBeat.Cadence.IMMEDIATE)
	# A rect landing on a SETTLED own-aperture element re-derives that aperture from the live
	# rect (`UI3Element._apply_rect`), and a shut element is settled — so without this a resize
	# during deployment would leave the band standing wide open behind `visible = false`, ready
	# to appear whole on the next frame the strip is shown.
	if not _bar_open:
		_bar.close(UI3BoxOpenBeat.Cadence.IMMEDIATE)
	_relayout_band()


func _on_par_changed(_value: float) -> void:
	# Every rect here is a derived() closure over the live PAR, so re-evaluating them
	# IS the relayout. IMMEDIATE, not the slide: a PAR scrub is an authoring gesture,
	# and animating the whole strip to a new metric would just be slow to read.
	if _bar == null:
		return
	_bar.move_to_answer(UI3MoveSlideBeat.Cadence.IMMEDIATE)
	if not _bar_open:
		_bar.close(UI3BoxOpenBeat.Cadence.IMMEDIATE)
	_relayout_band()
	for rec in _cards:
		_resize_card(rec)
		var element: UI3Element = rec["element"]
		element.move_to_answer(UI3MoveSlideBeat.Cadence.IMMEDIATE)
		# Same re-derive hazard as the bar above: a card still waiting its turn in the chain is
		# SHUT and SETTLED, and landing a rect on it would open its aperture behind the beat's
		# back — a card that appears whole and then plays its entrance.
		if not bool(rec["open"]):
			element.close(UI3BoxOpenBeat.Cadence.IMMEDIATE)


# --- Layout -------------------------------------------------------------------
#
# Every rect below is display px in the BAR's own space, and the bar's own rect sits
# at (0,0) with a frozen authored_home there — so a child's absolute rect and its
# offset from the bar's origin are the same number (UI3Element._place_self).

## The PORTRAIT's footprint inside a card — what the face itself occupies.
##
## Feeds the PAYLOAD only (the portrait's `pixels_per_unit` and the underlay quad); no rect on
## this widget is a function of it any more. Overscale it and the face grows inside a card that
## does not move — see [method _card_size].
func _portrait_size() -> Vector2:
	return portrait_base() * portrait_scale()


## The CARD's outer box: a face-sized box at `card_scale`, plus the 9-slice border around it.
## The element's rect IS this, because [method UI3Element._ensure_chrome] sizes the frame from
## the rect — so a card sized to the face alone would draw its border straight over it.
##
## Reads `card_scale`, NOT [method _portrait_size]. That is the decoupling: the card used to be
## derived from the portrait, which gave the frame no size of its own and made "fill the frame"
## undialable. The two knobs share [method portrait_base] and default to the same multiplier, so
## at rest this is the same box it always was.
##
## CEILED to whole display px, and that is a look fix, not tidiness. `portrait_base().x *
## 0.7292` is 23.33 at PAR 1.0, so an un-rounded box gives a fractional PITCH: the cards' left
## edges drift by a third of a pixel each, and every third gap picks up a stray dark column
## while its neighbours have none. Visible in the capture, and it is the same uneven-sampling
## family as critique 3 — a row of borders makes it much easier to see than a row of faces did.
## Ceiling rather than rounding, so a card is never SMALLER than the face plus its border; the
## spare fraction lands in the 9-slice's stretched middle, where nothing reads it.
func _card_size() -> Vector2:
	var m := card_margins()
	return (portrait_base() * card_scale() + Vector2(m.x + m.z, m.y + m.w)).ceil()


func _pitch() -> float:
	return _card_size().x + spacing()


## The screen's full width in the STRIP's own display-px space, as `(x0, width)`. `x0` is the
## screen's LEFT edge measured from the strip's anchor, so it is NEGATIVE for any
## `screen_pos.x > 0`, and `x0 + width` is the right edge.
##
## DERIVED, never a literal. ADR-0269 quotes ~373 px twice for the battle camera, and writing
## that number down would be a capture-rig constant masquerading as a layout. Under an ortho
## host it is `REFERENCE_CAMERA_SIZE * aspect / ppu`, and the camera SIZE cancels: [UIWindowHost]
## scales this whole host by `camera.size / REFERENCE_CAMERA_SIZE`, so a zoom widens the frustum
## and shrinks the strip's pixels by exactly as much. What is left is the viewport's ASPECT,
## which is the one thing a screen-wide band has to follow.
##
## MEASURED through the host's own frustum arithmetic whenever a camera exists, because that
## cancellation is an ORTHO identity and a perspective host gets no counter-scale. With NO camera
## (every UI3 unit rig) the ortho form is the fallback — it needs only the viewport, so the band
## keeps a real width instead of collapsing onto the zero
## [method UIWindowHost._calculate_world_position] returns when it cannot find one.
func _screen_span_px() -> Vector2:
	var p := maxf(0.0001, pixels_per_unit)
	var anchor := screen_pos()
	var camera := get_viewport().get_camera_3d() if get_viewport() != null else null
	if camera != null:
		var left := to_local(_calculate_world_position(Vector2(0.0, anchor.y))).x
		var right := to_local(_calculate_world_position(Vector2(1.0, anchor.y))).x
		var origin := to_local(_calculate_world_position(anchor)).x
		if right > left:
			return Vector2((left - origin) / p, (right - left) / p)
	var vp := _get_effective_viewport_size()
	var w := REFERENCE_CAMERA_SIZE * (vp.x / maxf(1.0, vp.y)) / p
	return Vector2(-anchor.x * w, w)


## The BAND's rect — the whole screen wide, one card row tall.
##
## It is no longer "the bar, sized to the cards", which is what the user's second review named:
## a backdrop that stopped at the last portrait. The band is this element's own payload, so the
## band's extent IS this rect, and its x0 is NEGATIVE — the screen's left edge lies to the left
## of the strip's anchor. Widening it moves nothing else, because the cards stopped being this
## element's children (they are the strip root's, homed at the anchor).
##
## The HEIGHT is unchanged and deliberately so: "all the way across the screen" is a claim about
## the horizontal extent, and a band as tall as the screen is a dim, not a strip.
func _bar_rect() -> Rect2:
	var card := _card_size()
	var p := pad()
	var span := _screen_span_px()
	return Rect2(span.x, 0.0, span.y, p.y + card.y + p.w)


## Where card `slot` sits, in the STRIP's own space: `pad.x` from the anchor, one pitch per slot.
## There is no staging rect off the right edge any more — a card is built AT its home and
## apertures open there — so the strip never holds a card that is not in the row.
func _slot_rect(slot: int) -> Rect2:
	var card := _card_size()
	var p := pad()
	return Rect2(p.x + float(slot) * _pitch(), p.y, card.x, card.y)


# --- Build --------------------------------------------------------------------

func _build_bar() -> void:
	_bar = UI3Element.new({
		"id": "turnqueue.bar",
		# Derived, not a literal: the band spans the screen and stands one card row tall, so
		# its rect is a function of the viewport and two layout knobs. It mints no `.rect` slug
		# (which would be a knob a window resize overwrites) and re-derives on a scrub for free.
		# `spacing` is NOT a driver any more — it moves the card PITCH, and the pitch stopped
		# deciding this element's width the moment the band went screen-wide.
		# `card_scale` and NOT `portrait_scale`: since the split it is the CARD's size that sets
		# this band's height, and the face's own multiplier moves no rect at all.
		"rect": UI3Element.derived([CARD_SCALE_SLUG, PAD_SLUG], _bar_rect),
		"authored_home": Vector2.ZERO,
		"transition": UI3Element.Transition.BOX_OPEN,
		"open_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		"close_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		# NO frame. Every CARD wears one instead (see `_spawn_card`). This element's job is the
		# BAND: it carries it as payload and owns the `OWN_APERTURE` + `BOX_OPEN` that make the
		# backdrop sweep open across the whole screen. It no longer clips the cards — each card
		# owns its own aperture so it can box-open in place — so the strip's CHROME and the
		# strip's CONTENTS are two independent plays that happen to start together. Putting the
		# aperture on the strip root instead would take the beat with it: the root is a plain
		# Node3D, not a UI3Element.
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.OWN_APERTURE,
		"ppu": pixels_per_unit,
	})
	_bar.name = "TurnQueueBar"
	_strip.add_child(_bar)
	_bar.closed.connect(_on_bar_closed)

	_build_band()

	# Boot SHUT — and LAST, after the band exists. A freshly-adopted element's settled
	# aperture is its full rect, so without this the very first `open()` renders one frame
	# of a fully-open box before the beat's frame 0 snaps it back to 10%: a flash exactly
	# one vsync long, on the first thing the player sees. IMMEDIATE settles SYNCHRONOUSLY
	# (ADR-0097 §3), so `_on_bar_closed` runs inside this call.
	_bar.close(UI3BoxOpenBeat.Cadence.IMMEDIATE)

	# `max_cards` drives no rect, so no derived() answer re-evaluates on a scrub of it — but it
	# does change how many cards there ARE. Re-run the last forecast through the new cap so the
	# knob lands while the player is looking at the strip, not on the next turn edge.
	TunePort.on_update(self, MAX_CARDS_SLUG, func(_v: Variant) -> void:
		if _bar != null and not _entries.is_empty():
			show_entries(_entries))
	# The band's own two dials, and the layout slugs that change its SIZE. The size ones are
	# already rect drivers for the bar, but a derived rect re-evaluating does not reshape a mesh
	# that is not part of any element's rect — the band is payload, not geometry UI3 places.
	# `spacing` is absent for the same reason it left the rect drivers above, and `portrait_scale`
	# because since the split the band's height follows the CARD.
	for slug in [BAND_SUB_SLUG, BAND_FEATHER_SLUG, CARD_SCALE_SLUG, PAD_SLUG]:
		TunePort.on_update(self, slug, func(_v: Variant) -> void: _relayout_band())
	# The two PAYLOAD knobs. Neither drives a rect any more, so nothing above re-evaluates on a
	# scrub of them and without this pair they would read as DEAD in F3 — which is precisely the
	# complaint the split was built to answer. `_resize_card` is the whole reshape: it re-derives
	# the portrait's `pixels_per_unit`, the underlay quad and both of their offsets.
	for slug in [SCALE_SLUG, PORTRAIT_OFFSET_SLUG]:
		TunePort.on_update(self, slug, func(_v: Variant) -> void:
			for rec in _cards:
				_resize_card(rec))


## The strip's backdrop: [UIVitalsBand], the SAME producer the vitals panel, the nameplate and
## the formation roster's bottom stripe use. Sized to the BAR — which is now the whole screen
## width (see [method _bar_rect]) — and mounted as the bar's own payload.
##
## Mounted UNDER the bar element rather than beside it, and that is the load-bearing detail.
## [method UI3ClipEngine.payload_materials] collects every ShaderMaterial in an element's own
## subtree, skipping nested registered elements — so a plain holder here IS the bar's payload,
## and the band receives `clip_world` and `clip_basis_inv` from the same pushes the cards do.
## It therefore rides the box-open scissor for free: the backdrop opens with the strip instead
## of snapping in behind it, and this class needs no per-frame uniform push of its own.
##
## It is SUBTRACTIVE and routes through the 4.8 fork's engine fold, so it darkens whatever the
## battlefield happens to be behind it rather than painting a guessed grey over it. Off-fork
## the shared producer falls back to its in-scene twin; with no floor spec it subtracts from an
## unsampled background, which is a fair approximation and not the target configuration.
func _build_band() -> void:
	var rect := _bar_rect()
	_band_mat = UIVitalsBand.build(_bar, _band_spec(rect), _bar.ppu(), rect.size)
	_band_holder = _bar.get_node_or_null("TurnQueueBand") as Node3D
	if _band_holder != null and _band_holder.get_child_count() > 0:
		_band_mesh = _band_holder.get_child(0) as MeshInstance3D
	# The mesh appeared after the element registered, so take the CURRENT aperture now rather
	# than waiting on the engine's coalesced mount-time push.
	_bar.refresh_payload()


## The band's spec for a bar of `rect`. Display px in the BAR ELEMENT'S OWN space and NOT the
## strip's, which is why x0 is 0 and not `rect.position.x`: [method UIVitalsBand.build] mounts
## its holder at `x0 * ppu` under the element, and the element node already stands at
## `rect.position`. The band covers the bar exactly, and the trapezoid's two ramps are
## `band_feather` px deep at the top and bottom.
## A feather of 0 collapses both ramps onto the outer bounds, which is the shader's own
## documented no-op for an axis — a flat rectangle, no gradient.
func _band_spec(rect: Rect2) -> Dictionary:
	var f := minf(band_feather(), rect.size.y * 0.5)
	return {
		"name": "TurnQueueBand",
		"x0": 0.0, "x1": rect.size.x,
		"y_top_out": 0.0, "y_top_in": f,
		"y_bot_in": rect.size.y - f, "y_bot_out": rect.size.y,
		"full_sub": band_sub(),
		"rung": _bar_rung(RP_BAND),
	}


## Reshape the band to the bar's current rect. MUTATES the carrier — `UIVitalsBand.update_extent`
## exists for exactly this, because the mesh is enrolled in the compositor's fold layer and
## freeing an enrolled member while that layer composites corrupts the engine heap on the fork.
## A queue changes length on most turns, so this runs far more often than a knob scrub does.
func _relayout_band() -> void:
	if _band_mesh == null or not is_instance_valid(_band_mesh) or _band_mat == null:
		return
	var rect := _bar_rect()
	var spec := _band_spec(rect)
	UIVitalsBand.update_extent(_band_mesh, _band_mat, spec, _bar.ppu())
	_band_mat.set_shader_parameter("full_sub", spec["full_sub"])
	# The quad's own x extent. Inert while there is no x feather (the shader's x profile is
	# 1.0 when `x_right_out <= x_left_out`, which is the unset default) — pushed anyway so the
	# uniform never disagrees with the mesh it describes.
	_band_mat.set_shader_parameter("band_x0", 0.0)
	_band_mat.set_shader_parameter("band_x1", rect.size.x)
	_band_mat.set_shader_parameter("screen_w", rect.size.x)
	_band_mat.set_shader_parameter("screen_h", rect.size.y)


## The absolute fold rung for a render priority on the BAR — the same sum
## [method UI3Element.z_for] computes, exposed because [UIVitalsBand] takes a rung and
## positions its own holder from it.
func _bar_rung(rp: int) -> int:
	return int(_bar.resolve_criterion("depth_rung", UI3Element.DEFAULT_DEPTH_RUNG)) + rp


# --- The queue diff (ADR-0269 dec. 6) -----------------------------------------
#
# The old build tore every card down and repainted the strip whenever the ORDER
# moved. That is why nothing could animate: a card that is destroyed and rebuilt one
# slot left has no identity to carry a motion. Matching entries to existing cards
# first is what turns "the queue changed" into three verbs a beat can play.

func _reconcile(shown: Array) -> void:
	if shown.is_empty():
		# The whole strip is going away, and the BAND's close is the animation. Closing
		# eleven cards under a backdrop that is already sweeping shut over them buys
		# nothing but eleven plays.
		_clear_cards()
		return

	var old := _cards
	var taken := {}
	var next: Array[Dictionary] = []
	var movers: Array[Dictionary] = []
	var entrants: Array[Dictionary] = []
	for i in range(shown.size()):
		var key := [int(shown[i]["index"]), int(shown[i]["team"])]
		var match_at := -1
		for j in range(old.size()):
			# FIRST unmatched card with this key, so a unit that appears twice in one
			# round-robin keeps both of its cards and they stay in order.
			if not taken.has(j) and old[j]["key"] == key:
				match_at = j
				break
		if match_at >= 0:
			taken[match_at] = true
			var rec: Dictionary = old[match_at]
			if int(rec["slot"][0]) != i:
				# The rect ANSWER is re-aimed HERE and the WALK is deferred to [method
				# _advance_step]. Writing `slot[0]` moves nothing by itself — `move_to_answer`
				# is the verb — which is exactly what lets the diff be immediate while the
				# motion waits for the head's close to finish.
				rec["slot"][0] = i
				movers.append(rec)
			if not bool(rec["open"]):
				# A card the previous chain never got to open, because a fresh queue arrived
				# first. It is still shut, so it is an entrant for THIS chain.
				entrants.append(rec)
			next.append(rec)
		else:
			var fresh := _spawn_card(i, key)
			entrants.append(fresh)
			next.append(fresh)
	# ARM the chain, then retire, then advance — in that order, and the order is load-bearing.
	# `close()` can settle SYNCHRONOUSLY (an already-shut card; an IMMEDIATE cadence), and a
	# `closed` that fired while these two lists still held the PREVIOUS refresh's work would
	# advance a chain belonging to a queue that no longer exists.
	#
	# A refresh landing mid-chain REPLACES the pending step rather than queueing behind it: the
	# queue it was going to animate is not the queue any more. The generation stamp is what
	# makes the old chain's in-flight callbacks inert instead of resurrecting it — and the diff
	# above has already folded any still-shut survivor into `entrants`, so the cancellation
	# strands nothing closed.
	_step_gen += 1
	_to_move = movers
	_to_open = entrants
	for j in range(old.size()):
		if not taken.has(j):
			_retire_card(old[j])
	_cards = next
	_advance_step()


## Walk the serialised refresh one stage on, if the stage before it has finished: the head's
## aperture CLOSES, then the survivors shuffle left, then the new tail's aperture OPENS. Three
## beats in that order and not three at once, which is the user's "wait for the one to close
## before moving ahead".
##
## Only the PLAYS are serialised — the DIFF is not. `_cards`, `shown_indices()` and `draws()`
## are all correct the instant `show_entries` returns, and an entrant waiting its turn is a real
## element standing at its real slot with a SHUT aperture, which draws nothing. That is what
## keeps the redraw gate and the pure-view seam honest while the animation takes its time.
##
## Built on the elements' own `closed` / `moved` signals and never on a clock: `create_timer` is
## forbidden under `tests/` (charter clause 14), and the hand-stepped transition engine the test
## drives has no wall clock to wait on in the first place.
##
## Called on every edge that can complete a stage — a retiring card's `closed`, a survivor's
## `moved`, and the arming in `_reconcile`, so a refresh with nothing to close starts shuffling
## immediately.
##
## The two counters are deliberately of different kinds. `_leaving` is a LIST because a card
## still fading out is a thing the rest of the class must not re-adopt; `_moving` is a COUNT
## because a survivor mid-walk is an ordinary live card and only the barrier cares.
func _advance_step() -> void:
	if not _leaving.is_empty():
		return   # something is still closing — this is the wait the user asked for
	if not _to_move.is_empty():
		var movers := _to_move
		_to_move = []
		var gen := _step_gen
		# Count them ALL before starting ANY. A move over a rig with no transition engine
		# settles synchronously inside `move_to_answer`, so a count that grew as the loop ran
		# would hit zero after the first card and open the tail while the rest were still to go.
		for rec in movers:
			if is_instance_valid(rec["element"] as UI3Element):
				_moving += 1
		for rec in movers:
			var element: UI3Element = rec["element"]
			if not is_instance_valid(element):
				continue
			element.moved.connect(func() -> void:
				_moving -= 1
				if gen == _step_gen:
					_advance_step(), CONNECT_ONE_SHOT)
			element.move_to_answer()
	if _moving > 0:
		return
	var entrants := _to_open
	_to_open = []
	for rec in entrants:
		_open_card(rec)


## Play one card's entrance — its aperture opening in place, at its slot.
##
## A no-op while the strip itself is shut. `_sync_open` opens every card WITH the band, so a
## card that arrived while a full-screen screen stood over the battlefield waits for the strip
## rather than opening behind something nobody can see past.
func _open_card(rec: Dictionary) -> void:
	var element: UI3Element = rec["element"]
	if not is_instance_valid(element) or not _bar_open or bool(rec["open"]):
		return
	rec["open"] = true
	element.open()


func _spawn_card(slot: int, key: Array) -> Dictionary:
	var id := _claim_id()
	# Constructed AT its slot. There is no staging position off the strip's right edge any
	# more: a card ENTERS by opening its own aperture where it belongs. That is the user's
	# second ask, and it is also what makes the screen-wide band safe — a slide in from the
	# band's new right edge would be a journey most of the screen long, on a cadence priced
	# against a one-card pitch.
	var box := [slot]
	var element := UI3Element.new({
		"id": "turnqueue.card.%d" % id,
		# `card_scale` drives the box; `portrait_scale` drives what is drawn IN it and is
		# deliberately absent — a face scrub must not re-derive a rect and re-open an aperture.
		"rect": UI3Element.derived([CARD_SCALE_SLUG, SPACING_SLUG, PAD_SLUG],
			func() -> Rect2: return _slot_rect(int(box[0]))),
		# The APERTURE is the entrance and the exit, and it needs OWN_APERTURE to exist at all:
		# `UI3BoxOpenBeat.precondition` reports itself inert on any other clip answer. That is
		# why a card left the bar's subtree — a card cropped by the strip AND scissoring itself
		# would be a private aperture inside the one already cropping it, which is the exact
		# objection that chose FADE the first time round. It stops applying once the strip has
		# no card outside its own row to crop.
		"transition": UI3Element.Transition.BOX_OPEN,
		"open_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		"close_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		"move": UI3Element.Move.SLIDE,
		"move_cadence": UI3MoveSlideBeat.Cadence.BACK,
		# PER-CARD, and the bar carries none. A card is the thing the player counts, and a
		# framed card is the thing every other readout on this screen is; the rect above is
		# grown by the 9-slice's own margins so the border draws AROUND the face, not over it.
		"frame": UI3Element.Frame.MENU_TILE,
		"frame_rp": RP_FRAME,
		"clip": UI3Element.Clip.OWN_APERTURE,
		# STATED, not inherited. A card's parent is now the strip root — a plain Node3D — so
		# there is no ancestor element to resolve `ppu` through, and the chain default would
		# silently disagree with the band the moment the host's own ppu moved off 0.04.
		"ppu": pixels_per_unit,
	})
	element.name = "TurnQueueCard%d" % id
	var rec := {"key": key, "slot": box, "id": id, "element": element,
		"portrait": null, "tint": null, "open": false}
	# A SIBLING of the band, not a child of it. Under the bar its rect would be read against a
	# FROZEN authored_home of (0,0) that the screen-wide rect has since moved away from, and
	# every card would sit one screen-margin left of its slot.
	_strip.add_child(element)
	_build_card_payload(rec)
	_paint(rec)
	# Boot SHUT, for the same reason the bar does: a freshly-adopted element's settled aperture
	# is its whole rect, so an `open()` without this renders one fully-open frame before the
	# beat's frame 0 snaps it back. IMMEDIATE settles SYNCHRONOUSLY (ADR-0097 §3), so the card
	# is already shut when this returns and the deferred open has something to open.
	element.close(UI3BoxOpenBeat.Cadence.IMMEDIATE)
	return rec


func _build_card_payload(rec: Dictionary) -> void:
	var element: UI3Element = rec["element"]
	var ppu := element.ppu()

	# The team underlay. It sits BEHIND the portrait and shows through the magic-0
	# holes the portrait shader discards, so it tints the head's surround.
	var underlay := MeshInstance3D.new()
	underlay.name = "TeamUnderlay"
	var mat := ShaderMaterial.new()
	mat.shader = _UNDERLAY_SHADER
	mat.render_priority = RP_UNDERLAY
	underlay.material_override = mat
	underlay.mesh = QuadMesh.new()
	element.add_child(underlay)
	rec["tint"] = mat
	rec["underlay"] = underlay

	var portrait := UIPortrait.new()
	portrait.name = "Portrait"
	portrait.pixels_per_unit = ppu * portrait_scale()
	element.add_child(portrait)
	portrait.set_overlay_priority(RP_PORTRAIT)
	rec["portrait"] = portrait

	_resize_card(rec)


## Size the card's payload to the current metric. Split out because a PAR or scale
## scrub changes the mesh, not just where it sits.
##
## Since `portrait_scale` and `portrait_offset` drive no rect, this is the ONLY thing that
## answers a scrub of either — [method _build_bar] subscribes both straight to it.
func _resize_card(rec: Dictionary) -> void:
	var element: UI3Element = rec["element"]
	var ppu := element.ppu()
	var face := _portrait_size()
	# The card's origin is its top-left and so is the portrait's, but they no longer coincide.
	# This used to be FORCED to the frame's own (LEFT, TOP) margins — the face could only ever
	# sit hard against the border's inner corner. It is a knob now, defaulting to exactly those
	# margins, so the offset at rest is the inset it always was. Getting this wrong does not
	# misalign the face, it puts the border ON it.
	var off := portrait_offset()
	var inset := Vector3(off.x * ppu, -off.y * ppu, 0.0)
	var portrait: UIPortrait = rec["portrait"]
	if is_instance_valid(portrait):
		portrait.pixels_per_unit = ppu * portrait_scale()
		portrait.position = inset + element.z_for(RP_PORTRAIT)
	var underlay: MeshInstance3D = rec["underlay"]
	if is_instance_valid(underlay):
		# The underlay backs the FACE, not the card: it fills the magic-0 holes around a head,
		# and stretching it under the border would paint the team colour on the frame instead.
		# So it rides `portrait_offset` and `portrait_scale` with the portrait — the same
		# `inset` and the same `face` — and NOT the card's box. Leaving it on the old margins
		# would slide the tint out from under the head the moment either knob moved.
		(underlay.mesh as QuadMesh).size = face * ppu
		# QuadMesh is centred on its own origin; the face's origin is its top-left.
		underlay.position = inset + Vector3(face.x * ppu * 0.5, -face.y * ppu * 0.5, 0.0) \
			+ element.z_for(RP_UNDERLAY)


## Draw one entry. The portrait resolution is [UICombatManager]'s: the owned
## template folder when the unit has one, else the flat sprite sheet.
func _paint(rec: Dictionary) -> void:
	var unit_index: int = int(rec["key"][0])
	var team: int = int(rec["key"][1])
	var portrait: UIPortrait = rec["portrait"]
	var unit = _units[unit_index] if unit_index >= 0 and unit_index < _units.size() else null
	var sprite_id: int = _sprite_id_of(unit)
	if sprite_id >= 0:
		portrait.display_from_template(_template_folder_of(unit), sprite_id)
	else:
		portrait.clear()
	# The enemy roster's own convention (`CombatUI.tscn` flips `EnemyRoster`), applied
	# PER ENTRY because a queue interleaves the teams. KEPT from ADR-0244 dec. 7 — but
	# it is no longer the ONLY side marking, because it is only legible when two
	# entries sit next to each other and a queue cannot promise that. The UNDERLAY is
	# the one that reads without a neighbour, and it is now the only other one: the
	# baked "Enemy" word cell is gone (two markings where the review asked for one).
	portrait.flipped = team != 0
	(rec["tint"] as ShaderMaterial).set_shader_parameter("tint", team_tint(team))


## Retire one card: its aperture closes, and when it HAS closed the chain moves on. This is the
## one place the serialised refresh actually blocks — everything downstream of it is waiting on
## `_leaving` emptying, and `_advance_step` is called after the erase rather than beside it so
## the barrier reads the list it is about to be true of.
func _retire_card(rec: Dictionary) -> void:
	var element: UI3Element = rec["element"]
	var id: int = int(rec["id"])
	_leaving.append(element)
	element.closed.connect(func() -> void:
		_leaving.erase(element)
		_used_ids.erase(id)
		element.queue_free()
		_advance_step(), CONNECT_ONE_SHOT)
	element.close()


func _clear_cards() -> void:
	for rec in _cards:
		var element: UI3Element = rec["element"]
		_used_ids.erase(int(rec["id"]))
		element.queue_free()
	_cards = []
	# The pending chain goes with them, and the generation bump is what makes it stay gone: a
	# survivor freed mid-walk never emits `moved`, so a `_moving` left standing would block the
	# next queue's entrances forever on a card that no longer exists.
	_step_gen += 1
	_to_move = []
	_to_open = []
	_moving = 0
	_closing_cards = 0
	# The gate's memory goes with them. Without this, the strip closing on `resumed`
	# and re-opening on the NEXT `turn_opened` over an unchanged queue would hit
	# `key == _shown` and return early — the bar would open onto no cards at all. The
	# gate compares the queue; what it must actually answer is "is what I drew still
	# on screen", and after a teardown the answer is no.
	_shown = []


## The lowest free pool id. Bounded by [method max_cards] plus whatever is still fading out,
## so the Tune slugs these mint are a bounded set rather than one per card ever built.
func _claim_id() -> int:
	var id := 0
	while _used_ids.has(id):
		id += 1
	_used_ids[id] = true
	return id


# --- Visibility ---------------------------------------------------------------

func _sync_open() -> void:
	var want: bool = not _cards.is_empty() and _battle_live and not _covered
	if want == _bar_open:
		return
	_bar_open = want
	if want:
		visible = true
		# The BAND opens first and the cards follow it, and that order was found by LOOKING.
		# Both are centre-out box-opens, but the band's box is the screen and a card's is 32 px:
		# played together, the band's scissor has not yet reached the leftmost cards while those
		# cards are already scissoring themselves open, so for four frames two cards stand on the
		# bare battlefield with no backdrop under them. It reads as a glitch, not as a reveal.
		# Cards stopped riding the bar's aperture when dec. 3 gave them their own, which is what
		# turned a free ordering into one this class has to state.
		_to_open = _cards.duplicate()
		_bar.opened.connect(_advance_step, CONNECT_ONE_SHOT)
		_bar.open()
	else:
		# ...and the mirror on the way out: a band retreating centre-out uncovers the outermost
		# cards before they have finished going. Cards close, then the band closes over them.
		_closing_cards = 0
		for rec in _cards:
			if bool(rec["open"]):
				_closing_cards += 1
		if _closing_cards == 0:
			_bar.close()
			return
		for rec in _cards:
			if not bool(rec["open"]):
				continue
			rec["open"] = false
			var element: UI3Element = rec["element"]
			element.closed.connect(func() -> void:
				_closing_cards -= 1
				# `not _bar_open` and not a generation stamp: a re-open mid-close REVERSES each
				# card's play, so `closed` never arrives for it and this counter is simply left
				# standing — which is harmless, because the next close resets it before reading.
				if _closing_cards <= 0 and not _bar_open:
					_bar.close(), CONNECT_ONE_SHOT)
			element.close()


func _on_bar_closed() -> void:
	if _bar_open:
		return   # a re-open landed mid-close; the new play owns the state
	visible = false
	_clear_cards()


func _sprite_id_of(unit) -> int:
	if unit == null or not is_instance_valid(unit):
		return -1
	if "body_sprite_id" in unit:
		return unit.body_sprite_id
	if unit.has_method("get_sprite_id"):
		return unit.get_sprite_id()
	return -1


func _template_folder_of(unit) -> String:
	if unit == null or not is_instance_valid(unit):
		return ""
	var folder = unit.get("template_folder")
	return "" if folder == null else str(folder)
