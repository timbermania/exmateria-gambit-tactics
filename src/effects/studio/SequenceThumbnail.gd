extends Control
## One TIME POSITION's picture, sized to sit in an inspector row (#247).
##
## The sequence inspector is ALREADY a vertical, scrolling, one-row-per-opcode list,
## so the film strip is that list rather than a second copy of it beside it: each row
## gains a picture. That is the vertical reel, and it costs no extra scrolling surface
## (user decision, 2026-08-18, after the horizontal ribbon showed 30 of 36 cells but a
## vertical strip in the same short band would have shown 2).
##
## WHAT THE PICTURE IS OF changed on 2026-08-20 (the ADR-0102 fencepost amendment): it
## was the animator state after that row's opcode ran, and it is now the animation at
## the row's `pos_tick`. For the rows in the middle those are the same picture; for the
## FIRST row (a `SET_OFFSET`, which used to draw an empty box) it is the animation's
## first frame, and for the LAST (usually a `LOOP`) its last. The row's TITLE still names
## the opcode, so the tooltip names the tick — otherwise "0: SET_OFFSET x=0 y=0" beside
## a drawn sprite is the only thing on screen saying what the cell is of.
##
## It paints through `SequenceSpritePainter`, the same code the viewport's player uses,
## so a thumbnail is a small copy of the player and cannot drift from it.
##
## THE SHARED BOX IS PASSED IN, never derived here. Every thumbnail in a sequence must
## use the SAME `SequenceTimeline.bounds`, or a row whose opcode only moved the sprite
## would re-centre and look identical to the row above it — which is exactly the
## information the offset opcodes exist to carry.
##
## No `class_name` (ADR-0004).

## Clicking a thumbnail PARKS the player on that opcode (#247 follow-on). Deliberately
## not navigation: the sequence view already renders exactly the section a focused-opcode
## target would show, so drilling in showed strictly less while costing the rebuild — and a
## rebuild is how you lose the fold and scroll state the author just set up. (That kind,
## `sequence_op`, was deleted 2026-08-19 for exactly this reason; ADR-0102's block made a
## park retarget the frameset rows too, which is the last thing drilling in bought.)
signal clicked
## RIGHT-click — the colour-keyframe entry point (ADR-0089 colour-move amendment). A separate
## signal and a separate button because the two gestures mean different things and the cheap
## version of this hijacked the existing one: a left click PARKS, and an author parks
## constantly while browsing, so folding "add a keyframe" onto it would mint an undo entry
## every time they looked at a frame. Right-click-means-edit-this-cell is also the track's own
## idiom one row up (right-click a handle removes it), so the strip and the track agree.
signal colour_requested

const SpritePainter = preload("res://src/effects/studio/SequenceSpritePainter.gd")
const CellColour = preload("res://src/effects/studio/SequenceCellColour.gd")
const BlendLayer = preload("res://src/effects/studio/SequenceBlendLayer.gd")

## Square by default. The row's height, not the sprite's shape, is the binding
## dimension in a list — a thumbnail that grew with its sprite would make the rows
## ragged and the list harder to scan.
const SIDE := 34.0
## The cell's SPRITE INSET — the 1px ring the background and border own, which the sprite
## is fitted inside. Shared with the blend layers, which derive their own fit from it.
const INSET := 1.0
## The cell backdrop's CODE DEFAULT — today's dark grey, so the strip arrives looking
## exactly as it did before ADR-0103. The live value is `backdrop` below.
const BG := Color(0.16, 0.16, 0.19)
## How much darker a cell holding no sprite is drawn. Kept as a RATIO of the backdrop
## rather than a rival constant, so scrubbing the backdrop to black takes the empty cells
## with it instead of leaving them lighter than the ones that have something in them.
const EMPTY_DARKEN := 0.2
const BORDER := Color(0.28, 0.28, 0.32)
const SELECTED := Color(1, 1, 0)
const PLAYHEAD := Color(1, 1, 1)
## What the cell says before it has been bound to one. Every live cell replaces this with
## its own tick in `bind_state`.
const TOOLTIP_UNBOUND := "Click to park the player here"

var _entry: Dictionary = {}
var _framesets: Array = []
var _box := Rect2i()
var _texture: Texture2D = null
var _selected: bool = false
var _is_playhead: bool = false
## Which opcode this thumbnail is OF — set by `follow`, so the marks can be resolved
## against the player's own indices, and the picture re-pulled when the decode moves.
var _op_index: int = -1
var _canvas = null
## The emitter colour curves this cell's piece of the ribbon is cut from (ADR-0103), and
## the cut's shared loop phase. Both are PULLED from the canvas — the same single-owner
## rule the trace and the bounds box already follow, so a row cannot be tinted from a
## different resolve than the animation playing beside it.
var _cr = null
var _cg = null
var _cb = null
var _cut_t: int = 0
## The per-blend-mode child CanvasItems this cell's sprite is drawn on (ADR-0103 dec. 7).
## Empty for a spriteless cell, ONE for 95.3% of the rest. Held as an explicit list rather
## than found by scanning children — see `SequenceBlendLayer.sync`.
var _layers: Array = []

## THE CELL BACKDROP IS A VIEWING CONDITION, NOT DATA (ADR-0103 dec. 8) — so it is an
## ADR-0068 tunable with its STATIC-VAR HOME right here, in the production owner, with the
## debug panel as a pure view (Addendum R). No single backdrop serves both blend families:
## black gives `ADD` (93.5% of corpus frames) its true colour unclipped and makes `SUB`
## (3.0%) invisible, while mid-grey reveals `SUB` and clips bright `ADD` toward white.
## That is exactly an image editor's alpha-backdrop choice, and it belongs to whoever is
## looking. It costs the ~268px inspector row ZERO pixels, which is the other half of why
## it is a tunable and not a control.
static var backdrop: Color = BG
const BACKDROP_SLUG := "effect_studio.thumbnail_backdrop"


## Register the backdrop tunable, owned by the PAGE that hosts the strip — not by a
## thumbnail. `Tune.bind` captures a use-site and `on_update` a standing subscription, so
## binding per thumbnail would register 36 of each for one storage slot.
##
## Deliberately NOT guarded by a "already bound" flag. `bind` is first-write-wins on the
## registry, and the subscription is owner-scoped: a page that is freed and rebuilt (the
## dashboard reopening) drops its `on_update` with it, and a flag would then leave the
## static var permanently deaf to a scrub. Re-registering is the shape `PSXDisplay`
## already documents for exactly this reason.
static func register_tunables(owner: Node) -> void:
	Tune.bind_update(owner, BACKDROP_SLUG, BG,
		func(v: Variant) -> void: backdrop = v if v is Color else BG)


## The live backdrop, and the darker one an empty cell gets. Read through these, never off
## `BG` — a `const` is frozen at parse time and unscrubbable, which is the mistake
## ADR-0068 R1–R8 exists to name.
static func backdrop_colour() -> Color:
	return backdrop


static func empty_backdrop() -> Color:
	return backdrop.darkened(EMPTY_DARKEN)


func _init() -> void:
	custom_minimum_size = Vector2(SIDE, SIDE)
	# NEAREST for the same reason the canvas needs it: a native PSX sprite is 8-64px
	# and is being magnified, where Linear is a smear.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = TOOLTIP_UNBOUND


## A scrub of the backdrop reaches the static-var home structurally (one storage slot),
## but a Control still has to be TOLD to repaint. Godot drops the connection with the
## node, so a rebuilt strip leaves nothing dangling — the same contract `follow` relies on.
func _ready() -> void:
	Tune.value_changed.connect(_on_tune_value_changed)


func _on_tune_value_changed(slug: String, _value: Variant) -> void:
	if slug == BACKDROP_SLUG:
		queue_redraw()


## `box` is the whole sequence's shared bounds and `texture` must already be
## `FramesetCanvas.display_image`'d — both are the host's to supply, so that every
## thumbnail in one list agrees.
func bind_state(entry: Dictionary, framesets: Array, box: Rect2i, texture: Texture2D) -> void:
	_entry = entry
	_framesets = framesets
	_box = box
	_texture = texture
	# The tick is a fact about THIS cell, so it can only be said once the cell is bound.
	tooltip_text = "Click to park the player at tick %d" % int(entry.get("pos_tick", 0)) \
		if entry.has("pos_tick") else TOOLTIP_UNBOUND
	_sync_layers()
	queue_redraw()


## Subscribe THIS thumbnail to the player's marks. Each one listens for itself rather
## than the host keeping a list of thumbnails to push into: that list would be one more
## cache to go stale the next time the inspector rebuilds, which in this repo is the
## shape of bug that keeps recurring (see the renderer emitter cache and the texture
## import preview). Godot drops the connection when this node is freed, so a rebuilt
## inspector leaves nothing dangling.
func follow(canvas, op_index: int) -> void:
	_canvas = canvas
	_op_index = op_index
	canvas.playhead_changed.connect(_on_playhead_changed)
	canvas.selection_changed.connect(_on_selection_changed)
	canvas.decode_changed.connect(_on_decode_changed)
	canvas.cut_phase_changed.connect(_on_cut_phase_changed)
	# Seeded, not started at zero: a strip rebuilt mid-loop arrives in step with the rows
	# around it instead of restarting the phase — thirty-six private phases are exactly
	# what dec. 3 exists to prevent.
	bind_colour(canvas.get_colour_curves(), canvas.cut_phase())
	set_marks(canvas.selected_op() == op_index, canvas.playhead_op() == op_index)


## The three curves this cell is tinted by, as `SequenceCanvas.get_colour_curves` returns
## them, plus the cut's current phase. Nulls (the `none` rung) draw the identity white.
func bind_colour(curves: Dictionary, cut_t: int) -> void:
	_cr = curves.get("r")
	_cg = curves.get("g")
	_cb = curves.get("b")
	_cut_t = cut_t
	_push_tint()
	queue_redraw()


## THE CUT'S LOOP, and the only thing that moves a stopped strip. A cell whose piece is a
## single age — 83.6% of them — redraws to the identical picture, so the repaint is the
## cost of not branching. Cheap enough: the strip is ~36 cells of 34px.
func _on_cut_phase_changed(t: int) -> void:
	if _cut_t == t:
		return
	_cut_t = t
	# The TINT only — the layers' structure is a function of the frameset, which a clock
	# tick cannot move. Re-syncing at 30Hz to change one colour would be work for nothing.
	_push_tint()


## The player re-decoded: this picture is of a cell that may have moved, resized, or
## changed sprite. Re-pull it — including the SHARED BOX, which a frameset edit can
## resize, and which every thumbnail in the sequence has to agree on.
func _on_decode_changed() -> void:
	var tr: Array = _canvas.get_trace()
	if _op_index < 0 or _op_index >= tr.size():
		return
	bind_state(tr[_op_index], _canvas.get_framesets(), _canvas.get_bounds(),
		_canvas.get_display_texture())
	# The CUT moved with the decode: an edited duration changes this cell's piece length
	# AND every later cell's start age, so the tint is as stale as the picture.
	bind_colour(_canvas.get_colour_curves(), _canvas.cut_phase())


func _on_playhead_changed(op_index: int) -> void:
	set_marks(_selected, op_index == _op_index)


func _on_selection_changed(op_index: int) -> void:
	set_marks(op_index == _op_index, _is_playhead)


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	match (event as InputEventMouseButton).button_index:
		MOUSE_BUTTON_LEFT:
			clicked.emit()
			accept_event()
		MOUSE_BUTTON_RIGHT:
			colour_requested.emit()
			accept_event()


## `selected` = the author parked here (yellow); `is_playhead` = the running player is
## on this cell (white). Both marks are live: the parked one is set on click, the
## playhead one follows SequenceCanvas.playhead_changed.
func set_marks(selected: bool, is_playhead: bool) -> void:
	if _selected == selected and _is_playhead == is_playhead:
		return
	_selected = selected
	_is_playhead = is_playhead
	queue_redraw()


## The colour this cell's piece of the ribbon resolves to right now.
func tint() -> Color:
	return CellColour.cell_color(_entry, _cr, _cg, _cb, _cut_t)


## How many blend layers this cell is drawing on — 0 for a spriteless cell, 1 for 95.3%
## of the rest. Exposed so a guard can assert the partition without reading pixels.
func layer_count() -> int:
	return _layers.size()


func _sync_layers() -> void:
	_layers = BlendLayer.sync(self, _layers, _entry, _framesets, _box, _texture, INSET, tint())


func _push_tint() -> void:
	var c: Color = tint()
	for l in _layers:
		l.set_tint(c)


## THE SPRITE IS NOT DRAWN HERE. Godot's blend mode is per-CanvasItem, so the quads live
## on `_layers` (ADR-0103 dec. 7) and what is left on the host is everything that draws at
## normal blend: the backdrop, the crosshair that stands in for a spriteless state, and
## the two marks. Children draw ABOVE their parent, so a 2px selection border can be
## clipped by a sprite that fills its box edge-to-edge — the ADR puts the border here
## anyway, and a chrome layer per row is not worth 1px of a mark.
func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var has_sprite: bool = bool(_entry.get("has_sprite", false))
	draw_rect(rect, backdrop_colour() if has_sprite else empty_backdrop(), true)
	var inner := rect.grow(-INSET)
	SpritePainter.paint_mark(self, _entry, _box, SpritePainter.fit(_box, inner), inner)
	var border: Color = BORDER
	var width: float = 1.0
	if _selected:
		border = SELECTED
		width = 2.0
	elif _is_playhead:
		border = PLAYHEAD
		width = 2.0
	draw_rect(rect, border, false, width)
