extends Control
## The SEQUENCE viewport's PLAYER (#247): the assembled animation, playing, in a band
## under the inspector.
##
## It is only the player. The film strip that once sat beneath it here now lives on the
## inspector's own opcode rows as per-row thumbnails (`SequenceThumbnail`), because that
## list is ALREADY a vertical, scrolling, one-row-per-opcode surface — so the reel costs
## no second scrolling surface, and the opcodes are not listed twice. The measurement
## that moved it: in this band (148px tall on E019's 36-opcode sequence, the inspector's
## rows having taken the rest of the budget) a horizontal ribbon showed 30 of 36 cells
## while a vertical strip in the same band showed 2 — so vertical only pays somewhere
## tall, and the rows are that place.
##
## What stays here is the thing the rows cannot show: the sequence ASSEMBLED and moving.
##
## This canvas remains the single owner of the decode — `get_trace`/`get_bounds`/
## `get_framesets`/`get_display_texture` feed the row thumbnails, so a row's picture and
## the animation above it are drawn from one state through one painter and cannot
## disagree, and `display_image` runs once per texture rather than once per row.
##
## Measured, not assumed:
##   * `draw_polygon`'s UVs are NORMALIZED, probed with a half-red/half-blue sheet
##     through both conventions — pixel-space UVs wrap and sample the wrong half.
##   * The sheet draws through `FramesetCanvas.display_image`, or every sprite with an
##     erased texel inside its block renders a black slab.
##   * The quad keeps its RAW vertices against texel-centre UVs, so a 4-texel block
##     spans 3 units exactly as `_write_instance` packs it.
## All three live in `SequenceSpritePainter`, which does the drawing.
##
## Playback runs on THIS canvas's own clock at `TRANSPORT_HZ`, deliberately NOT the page
## transport: a sequence is a reusable asset played by whichever particle references it,
## not something pinned to a position on the effect timeline, so parking the page's
## playhead must not park the animation being authored.
##
## PACE, not position, is what authoring needs from a transport here. `trace` is ONE CELL
## PER OPCODE and the picture is constant across that cell's whole `ticks` dwell, so there
## is no sub-opcode visual state: a tick-level scrubber would slide through 8 ticks of an
## identical image. "Pick a frame" and "pick an opcode" are the same act, and a thumbnail
## click already performs it. What was missing is the ability to watch it slowly — hence
## `set_speed` and the opcode step, and no scrubber. The 2026-08-20 amendment does not
## disturb that: it moves WHERE a click lands within a cell's dwell (to `pos_tick`), which
## is a different question from whether the author can address a tick inside one.
##
## No `class_name` (ADR-0004).

## The running player moved onto a different opcode. Emitted only when `playhead_op()`
## actually CHANGES — once per opcode, not once per frame — so a transition repaints the
## two thumbnails whose mark moved and nothing else. Each thumbnail subscribes itself
## rather than the page holding a list of them: a host-held list is one more cache to go
## stale on the next inspector rebuild, and this repo has been bitten by exactly that.
signal playhead_changed(op_index: int)
## The author parked on a different opcode (or unparked, with -1). Same contract.
signal selection_changed(op_index: int)
## The bound sequence was RE-DECODED under the same binding — an opcode's parameters
## changed. Every cell may have moved, the shared bounds box may have resized, and the
## thumbnails drawn from this decode are stale. Emitted by `refresh_sequence` only, NOT
## by `bind_sequence`: a fresh bind is followed by an inspector rebuild that replaces the
## thumbnails wholesale, and telling the outgoing ones to re-read a sequence they are not
## of would paint a wrong picture for the frame before they are freed.
signal decode_changed
## The RIBBON CUT's loop phase advanced (ADR-0103 dec. 3). Emitted once per whole `t`,
## and ONLY while the player is stopped: while it runs, the sweeping playhead is the one
## motion the author is tracking and thirty-six private loops would compete with it.
## Cells whose piece is a single age (83.6% of them) ignore it by arithmetic.
signal cut_phase_changed(t: int)

const SequenceTimeline = preload("res://src/effects/studio/SequenceTimeline.gd")
const FramesetCanvas = preload("res://src/effects/studio/FramesetCanvas.gd")
const SpritePainter = preload("res://src/effects/studio/SequenceSpritePainter.gd")
const CellColour = preload("res://src/effects/studio/SequenceCellColour.gd")
const BlendLayer = preload("res://src/effects/studio/SequenceBlendLayer.gd")

## The game frame rate the page transport also steps at, so a sequence previewed here
## and the same sequence played by the effect run at one speed — at 1.00x. `_speed`
## multiplies it, and that is the only thing that ever divorces the two.
const TRANSPORT_HZ := 30.0
## Playback rate multiplier. TRUE GAME SPEED is 1.0, which for a 6-tick sequence means
## five loops a second — correct emulation and useless for authoring.
const SPEED_MIN := 0.1
const SPEED_MAX := 4.0

const MARGIN := 8.0
const BG_COLOR := Color(0.13, 0.13, 0.15)
const LABEL_DIM := Color(0.50, 0.50, 0.56)
## Re-exported from the painter, which owns the mark and its geometry.
const CROSSHAIR_COLOR := SpritePainter.CROSSHAIR_COLOR

var _texture: Texture2D = null
## `_texture` with the transparent class erased and STP un-washed — what is actually
## sampled. Rebuilt only when the bound texture changes.
var _display_texture: Texture2D = null
var _framesets: Array = []
var _trace: Array = []
var _bounds := Rect2i()
var _tick: float = 0.0
var _total_ticks: int = 0
var _playing: bool = true
var _speed: float = 1.0
## Which opcode the inspector has focused, or -1. While PAUSED the player shows this
## state, so drilling into an opcode shows that opcode assembled and still.
var _selected_op: int = -1
## The last opcode `playhead_changed` was emitted for — the change gate. -2 rather than
## -1 so the FIRST evaluation always emits, including for an empty trace's -1.
var _last_playhead_op: int = -2
## The emitter colour curves this sequence is tinted by (ADR-0103 dec. 1/4), resolved by
## the host through `SequenceCellColour.provenance` and pushed in. Held HERE, beside the
## decode, for the reason the decode is: the player and every row thumbnail read one
## state through one painter, so the picture in a row and the animation above it cannot
## disagree. Null (the `none` rung) is the identity — the white that shipped.
var _cr = null
var _cg = null
var _cb = null
## The cut's loop phase, in whole game frames, advancing only while stopped. Float so the
## rate honours `_speed`; `cut_phase_changed` fires on the INT, once per frame of the cut.
var _cut_t: float = 0.0
var _last_cut_t: int = -1
## The per-blend-mode child CanvasItems the sprite is drawn on (ADR-0103 dec. 7) — the
## player gets the same treatment as a row thumbnail, because the painter is shared and
## dec. 1 says the two surfaces satisfy the invariant together or not at all.
var _layers: Array = []
## The transport read-out, on a child so it survives the layers going above the host.
## Children draw ABOVE their parent, so a glyph left on the host would end up UNDER a
## bright additive sprite — and the glyph is the affordance that says a click plays.
var _chrome: Control = null


func _ready() -> void:
	# NEAREST for the same reason FramesetCanvas needs it: a native PSX sprite is 8-64px
	# and magnified here, where Linear is a smear.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(true)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_chrome = Control.new()
	_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chrome.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_chrome.draw.connect(_draw_chrome)
	add_child(_chrome)


## Bind an animation. `anim` is the raw sequence Dictionary; `framesets` may be EMPTY for
## a real effect — E509/E510 reference up to 14 framesets with no `frames.json`.
##
## `group_offset` resolves a FRAME opcode's RELATIVE frameset index to the absolute one
## (see `SequenceTimeline.trace`). The caller resolves it through
## `EffectData.frameset_group_offset` — the one derivation — and passes the number, so
## this canvas never has to know what an emitter is.
func bind_sequence(texture: Texture2D, framesets: Array, anim: Dictionary,
		group_offset: int = 0) -> void:
	if texture != _texture:
		_texture = texture
		_display_texture = null
		if texture != null:
			var src: Image = texture.get_image()
			if src != null:
				_display_texture = ImageTexture.create_from_image(FramesetCanvas.display_image(src))
	_framesets = framesets if framesets is Array else []
	_decode(anim, group_offset)
	_tick = 0.0
	_set_selected(-1)
	_publish_playhead()
	_repaint()


## Re-decode the sequence ALREADY bound, in place — an opcode's parameters just changed.
##
## The decode is a SNAPSHOT: `SequenceTimeline.trace` flattens the opcode stream once, so
## an edit to a duration or a frameset reaches this player only through here. Nothing else
## re-reads the stream; `_process` walks the trace, not the opcodes.
##
## The transport survives: the playhead stays where it is (wrapped if the sequence got
## shorter), the park stays parked, play/pause is untouched. An author lengthening a frame
## while watching the loop is not asking to be sent back to tick 0 — and a rebind that
## restarted playback on every scrub step would make the field unusable.
func refresh_sequence(anim: Dictionary, group_offset: int = 0) -> void:
	_decode(anim, group_offset)
	_tick = fmod(_tick, float(_total_ticks)) if _total_ticks > 0 else 0.0
	if _selected_op >= _trace.size():
		_set_selected(-1)
	# The cell under the playhead may be the same INDEX over different content, so force
	# the gate open — the thumbnails' marks have to agree with a trace that just moved.
	_last_playhead_op = -2
	_publish_playhead()
	decode_changed.emit()
	_repaint()


func _decode(anim: Dictionary, group_offset: int) -> void:
	_trace = SequenceTimeline.trace(anim, group_offset)
	_bounds = SequenceTimeline.bounds(_trace, _framesets)
	_total_ticks = SequenceTimeline.total_ticks(_trace)


## The decode this canvas holds. Exposed so the inspector's per-opcode thumbnails draw
## from the SAME trace, bounds and display texture the player does.
func get_trace() -> Array:
	return _trace


func get_bounds() -> Rect2i:
	return _bounds


func get_framesets() -> Array:
	return _framesets


func get_display_texture() -> Texture2D:
	return _display_texture


## Bind the emitter colour curves this sequence is seen through (ADR-0103 dec. 1). The
## HOST resolves the provenance ladder — it owns `_nav`, which is the only thing that can
## tell a drilled sequence from a browsed one — and pushes the three curves in. Three
## nulls is the `none` rung and draws untinted.
##
## Called BEFORE the inspector is fed, in the same ordering that lets a thumbnail pull the
## trace: `_update_sequence_canvas` runs first on every nav update, so a row asking for
## its colour asks a canvas already bound to its own sequence.
func bind_colour(cr, cg, cb) -> void:
	_cr = cr
	_cg = cg
	_cb = cb
	_repaint()


## The bound curves, for the row thumbnails to draw their own piece of the same ribbon.
func get_colour_curves() -> Dictionary:
	return {"r": _cr, "g": _cg, "b": _cb}


## The cut's current loop phase. A thumbnail seeds itself with this on `follow` so a row
## built mid-loop arrives in step with the rows above it instead of restarting the phase.
func cut_phase() -> int:
	return int(_cut_t)


## The colour the cell at `idx` draws with RIGHT NOW — the one place the player's two
## clocks meet the cut. Running, the phase is the real age (`_tick` minus the cell's own
## `cut_start`), so the player shows the colour the game would; stopped, it is the cut's
## own loop. `cell_color` wraps at the piece length either way, so this is one expression.
func cell_modulate(idx: int) -> Color:
	if idx < 0 or idx >= _trace.size():
		return CellColour.IDENTITY
	var entry: Dictionary = _trace[idx]
	var phase: int = (int(_tick) - int(entry.get("cut_start", 0))) if _playing else int(_cut_t)
	return CellColour.cell_color(entry, _cr, _cg, _cb, phase)


## Park the player on one opcode — a thumbnail click, or a step button. Parking always
## STOPS: a still that keeps running is not a look at the state.
##
## IT SEEKS TO THE CELL'S `pos_tick`, NOT TO ITS `tick_start` (2026-08-20, the ADR-0102
## fencepost amendment; the author's call on the open question). A cell IS a position on
## the animation's clock now, so a click has to land on the position the cell stands for
## — the END of its dwell — or the strip would advertise a fencepost it cannot reach.
## For the 83.6% of cells that dwell one tick the two are the same number and nothing
## visibly moves; it is the long holds, and the two spare end slots, that this buys.
## `pos_tick` is always inside `[0, total_ticks - 1]`, so no clamp is needed here.
##
## Re-parking on the opcode already parked is NOT a no-op while the player is running:
## the click still has to stop it and seek. Only a request that changes nothing at all
## returns early.
func select_op(op_index: int) -> void:
	var in_range: bool = op_index >= 0 and op_index < _trace.size()
	if _selected_op == op_index and not (in_range and _playing):
		return
	_set_selected(op_index)
	if in_range:
		_playing = false
		_tick = float(int(_trace[op_index].get("pos_tick", 0)))
		_publish_playhead()
	_repaint()


## Park on the opcode `delta` places along, WRAPPING at both ends — the sequence loops,
## so its transport does too. From unparked, a step lands relative to wherever the
## playhead currently is, so pausing and stepping continues from what you were watching.
func step_op(delta: int) -> void:
	var n: int = _trace.size()
	if n <= 0:
		return
	var from: int = _selected_op if _selected_op >= 0 and _selected_op < n else playhead_op()
	if from < 0:
		from = 0
	select_op(posmod(from + delta, n))


func set_playing(playing: bool) -> void:
	_playing = playing
	_repaint()


func is_playing() -> bool:
	return _playing


## Which opcode the author parked on, or -1.
func selected_op() -> int:
	return _selected_op


## Playback rate. Session state owned by the HOST (it outlives this canvas's per-target
## rebinds), clamped here so the canvas is the one place the range is enforced.
func set_speed(v: float) -> void:
	_speed = clampf(v, SPEED_MIN, SPEED_MAX)


func speed() -> float:
	return _speed


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if not _playing:
		# ADR-0103 dec. 3: the ribbon cut's loops run ONLY here, in the gap the transport
		# leaves. `_tick` deliberately does not move — a park is a park.
		_advance_cut(delta)
		return
	if _total_ticks <= 0:
		return
	_tick = fmod(_tick + delta * TRANSPORT_HZ * _speed, float(_total_ticks))
	_publish_playhead()
	_repaint()


## Step the cut's phase and publish it once per whole frame. Unbounded on purpose: every
## consumer takes it `posmod` its own piece length, so there is no shared period to wrap
## at — the cells have different ones.
func _advance_cut(delta: float) -> void:
	_cut_t += delta * TRANSPORT_HZ * _speed
	var t: int = int(_cut_t)
	if t == _last_cut_t:
		return
	_last_cut_t = t
	cut_phase_changed.emit(t)
	_repaint()


func _set_selected(op_index: int) -> void:
	if _selected_op == op_index:
		return
	_selected_op = op_index
	selection_changed.emit(op_index)


## Emit `playhead_changed` iff the cell under the playhead moved. Called from the tick
## advance (every frame) and from every seek; the gate is what keeps it one emission per
## opcode rather than one per frame.
func _publish_playhead() -> void:
	var op: int = playhead_op()
	if op == _last_playhead_op:
		return
	_last_playhead_op = op
	playhead_changed.emit(op)


## Which cell the playhead is on. Only FRAME cells occupy time, so an offset or LOOP
## opcode is never addressed here.
func playhead_op() -> int:
	return SequenceTimeline.op_at_tick(_trace, int(_tick))


func _fit(into: Rect2) -> Dictionary:
	return SpritePainter.fit(_bounds, into)


## Which cell is on screen: the playhead's while running, the parked one while stopped —
## drilling into an opcode is a request to look at THAT state, and a still that keeps
## running is not a look.
func shown_op() -> int:
	var idx: int = playhead_op()
	if not _playing and _selected_op >= 0 and _selected_op < _trace.size():
		idx = _selected_op
	if idx < 0 or idx >= _trace.size():
		idx = 0
	return idx


## How many blend layers the shown cell is drawing on. Exposed for the same reason the
## thumbnail exposes it: dec. 7's partition is assertable without reading pixels.
func layer_count() -> int:
	return _layers.size()


## Re-stand the blend layers for whatever cell is shown now, and repaint. Called wherever
## this used to call `queue_redraw` alone — the layers ARE the picture, so a redraw that
## left them pointing at the previous cell would show the previous cell.
func _repaint() -> void:
	if _trace.is_empty() or _chrome == null:
		if _chrome != null:
			_chrome.queue_redraw()
		queue_redraw()
		return
	var idx: int = shown_op()
	_layers = BlendLayer.sync(self, _layers, _trace[idx], _framesets, _bounds,
		_display_texture, MARGIN, cell_modulate(idx))
	move_child(_chrome, -1)
	_chrome.queue_redraw()
	queue_redraw()


## THE SPRITE IS NOT DRAWN HERE (ADR-0103 dec. 7) — it is on `_layers`, one per blend
## mode, because Godot's blend mode is per-CanvasItem. What stays is the background and
## the crosshair that stands in for a state holding no sprite yet, both at normal blend.
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR, true)
	if _trace.is_empty():
		return
	var area := _area()
	if area.size.x <= 0.0 or area.size.y <= 0.0:
		return
	SpritePainter.paint_mark(self, _trace[shown_op()], _bounds, _fit(area), area)


func _area() -> Rect2:
	return Rect2(MARGIN, MARGIN, maxf(0.0, size.x - MARGIN * 2.0),
		maxf(0.0, size.y - MARGIN * 2.0))


## The transport read-out, drawn on the topmost child so a bright additive sprite cannot
## bury it.
func _draw_chrome() -> void:
	if _trace.is_empty():
		return
	var area := _area()
	if area.size.x <= 0.0 or area.size.y <= 0.0:
		return
	# Clicking the canvas toggles play/pause; the glyph says which it will do.
	var glyph := "⏸" if _playing else "▶"
	_chrome.draw_string(ThemeDB.fallback_font, area.position + Vector2(2.0, 14.0), glyph,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, LABEL_DIM)
	_chrome.draw_string(ThemeDB.fallback_font, area.position + Vector2(20.0, 14.0),
		"tick %d / %d — opcode %d%s" % [int(_tick), _total_ticks, shown_op(),
			"" if _selected_op < 0 else " (parked)"],
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, LABEL_DIM)


func _gui_input(event: InputEvent) -> void:
	if _trace.is_empty():
		return
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_playing = not _playing
		# Resuming UNPARKS. `_draw` prefers the parked cell whenever the player is
		# stopped, so a park left standing across a resume would have shown a frozen
		# still for the rest of the loop and looked like playback was broken.
		if _playing:
			_set_selected(-1)
		_repaint()
		accept_event()
