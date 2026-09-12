extends Control
## The WYSIWYG texture canvas for #278/#279 (Frameset editing) — renders the
## effect's texture and draws the selected frame's UV rect as an overlay,
## mirroring `EffectCurvePainter`'s background/gridlines/overlay layering AND
## its "live preview locally, commit on release" drag model. #279 scope
## (locked via grill 2026-08-17): drag the rect BODY to move it (x/y), drag a
## CORNER HANDLE to resize it (width/height, opposite corner pinned). Vertices
## stay spinbox-only — not drawn/draggable here.
##
## ZOOM + PAN (native PSX textures are tiny — 44-256 px/side — so even a
## generously-sized panel reads as "small" without magnification past fit):
## the scroll wheel zooms (centered on the cursor), and MIDDLE-drag or
## Shift+LEFT-drag pans (ADR-0099 dec. 6 — it was right-drag, the studio's only
## outlier; right-click is now free for the region context menu). `Home` resets
## the view. Every other function here (`uv_to_canvas_rect`,
## hit-testing, move/resize) is unchanged — they only ever consume "the current
## draw rect", never re-derive fit themselves, so zoom/pan is a pure extension,
## not a rewrite.
##
## THE PIXEL LADDER (ADR-0098 dec. 1-2). A texel is a square of colour, not a
## sample to interpolate, so the sheet draws through `TEXTURE_FILTER_NEAREST`
## (never set before, so it fell through to the engine default `Linear` — a
## smear on a 44-256 px sheet magnified past 1:1). Nearest alone is not enough:
## at a fractional scale it renders roughly every tenth row of texels two pixels
## tall while its neighbours get one, which is what makes a per-texel readout
## untrustworthy. So the scale is only ever a LADDER RUNG — `1,2,3,…,16` when
## magnified, `1/2, 1/3…` when zoomed out — and the view OPENS AT 100%, one texel
## to one screen pixel, whatever size the panel is.
##
## Opening at a "fit" was tried and measured worse: the panel is 297×270 and E019's
## sheet is 128×256, so the raw fit is 0.992 — a hair under 1:1, where snapping down
## lands on the 1/2 rung and draws the sheet at 64×128 with three-quarters of the
## panel empty. E317 (1.98 raw) fell the same way. Both sheets sit just under a rung
## because the panel's HEIGHT binds, so "fit" cost ~50% of the view rather than the
## ~9% a width-limited estimate suggested. At 100% a tall sheet overflows the port by
## a sliver instead; the author pans (the per-axis clamp makes that reversible), or
## zooms out deliberately. `_zoom_steps` counts rungs from 100%.
##
## The coordinate + hit-test math (`texture_rect`/`zoomed_texture_rect`/
## `uv_to_canvas_rect`/`canvas_point_to_texture_pixel`/`hit_test`/`move_uv`/
## `resize_uv`) is exposed as PURE static functions — callable without a live
## node, the actual test seam. `_gui_input` just threads mouse state through
## them and emits `uv_rect_changed` ONCE on release (the same commit-on-release
## shape `EffectCurvePainter.curve_changed` uses) — the host applies it as ONE
## compound edit, so a whole drag gesture is one undo entry.
##
## No `class_name` (ADR-0004).

signal uv_rect_changed(new_uv: Dictionary)
## A drag committed on one of N LIVE GROUP regions (ADR-0130 dec. 12). Carries the index of
## a REPRESENTATIVE member within the bound frameset's frames array, never a region index:
## the page lowers a region edit through `region_members`/`region_write_verdict`/
## `region_edits`, all of which address by (frameset, frame), so handing it anything else
## would make the page re-derive an address — the ADR-0100 defect. Distinct from
## `uv_rect_changed` because that one means "the ONE bound frame", and the page's two
## handlers must not be able to confuse the two.
signal group_uv_changed(member_frame_index: int, new_uv: Dictionary)
## The live-group region under the cursor changed — a representative member's index within
## the bound frameset, or -1 for none. This is what lets the ADR-0099 dec. 5 scope control
## keep its promise on this surface: it must state the blast radius BEFORE the drag, and
## with N boxes on screen the region it should be describing is the one the press would
## take. Same index basis as `group_uv_changed`, so the control the author reads and the
## edit they then commit address the same region by construction.
signal group_region_hovered(member_frame_index: int)
## The author PINNED a region by clicking it, or released the pin (`-1`). Carries a
## representative member's index within the bound frameset, exactly as
## `group_region_hovered` does — the host lowers both through the same address.
signal group_region_locked(member_frame_index: int)
## The texel under the cursor: `{x, y, inside, scale}` in texture-pixel units. The
## host's readout renders it; the canvas owns the mapping, so it is the only honest
## source (ADR-0098 dec. 6).
signal hover_changed(hover: Dictionary)

const MARGIN := 8.0
const HANDLE_SIZE := 8.0
const ZOOM_MAX := 16.0   # the ladder's top rung: 16 screen pixels per texel
const CHECKER_CELL := 8.0            # screen pixels, not texels — the backdrop is not part of the sheet
const CHECKER_A := Color(0.32, 0.32, 0.34)
const CHECKER_B := Color(0.22, 0.22, 0.24)
## Both particle passes discard a texel whose `r,g,b` are all below this, whatever its
## alpha (`effect_particle_opaque.gdshader:22`, `effect_particle_stp.gdshaderinc:147`).
## The viewport uses the SHADERS' threshold rather than exact zero because the shaders
## are what the player sees (ADR-0098 dec. 3).
const BLACK_EPSILON := 0.01
## How hard the never-addressed part of the sheet is dimmed. Dead sheet is exactly
## where an author can paint freely (ADR-0098 dec. 5), so it stays readable.
const UNCOVERED_DIM := Color(0.0, 0.0, 0.0, 0.45)
## The UV box's corner handles. The ANCHOR is the corner this frame's stored `uv.x`/
## `uv.y` actually name (ADR-0099 dec. 8) — not the top-left for 2,628 corpus frames —
## and it is the ONLY per-member difference a region has to draw, since every member
## shares the identical block. The dragged corner outranks both: that is transient
## feedback, and dropping it would leave the anchor colour ambiguous mid-gesture.
const HANDLE_COLOR := Color(1, 1, 0)
## The frameset-in-context overlay (ADR-0130 dec. 4b). Every frame of the frameset now on
## screen gets a yellow outline, so "which rect is sampling what" is answerable for a GROUP
## and not only for the one frame you drilled into. Dimmer than `HANDLE_COLOR` because
## these are READ-ONLY — none of them has drag handles, and a box that looks draggable and
## is not would be worse than no box.
const GROUP_COLOR := Color(1, 1, 0, 0.40)
## The region under the cursor when several are live, drawn a touch brighter than its
## neighbours so the box that WOULD take the press is identifiable before it is pressed.
const HOVER_COLOR := Color(1, 1, 0.55)
const ANCHOR_COLOR := Color(0.2, 0.9, 1.0)
const DRAGGING_COLOR := Color(1, 1, 1)
## WHAT A PRESS GRABS, which is deliberately BIGGER than what is drawn.
##
## `hit_test` used to be handed `HANDLE_SIZE` and test a radius-`HANDLE_SIZE * 0.5` CIRCLE
## with it, while `_draw_uv_overlay` drew a `HANDLE_SIZE` SQUARE — so the affordance and
## the target disagreed, and its own docstring claimed they could not. The square's corner
## sits 5.66px out along the diagonal and the circle stopped at 4.00px: swept at 0.25px
## over the drawn square, **26.8% of the pixels the author can SEE do not grab**, and they
## are the diagonal-outward ones a hand actually aims at. Reported as *"it is difficult to
## grab the yellow handles in the corners"*.
##
## 14 against a drawn 8 takes each corner's target from the circle's **50.3px² to 196px²,
## 3.9x**, and unlike the circle it is the shape the eye reads a square handle as. The
## drawn square stays 8 because the handle does NOT scale with zoom and the box does: the
## canvas opens at 100% (ADR-0098 dec. 2), where a 23x23 UV box is 23px and its four
## handles already nearly meet. Widening the target is free; widening the picture is not.
const HANDLE_GRAB := 14.0
## THE MIDDLE THIRD OF EACH AXIS BELONGS TO THE BODY, and this is what makes the bigger
## target safe. A grab zone reaches its full half OUTWARD, where only a neighbouring region
## can compete, and is bounded INWARD to this fraction of the box's own side — so four
## corners can never consume the box they are the corners of, and the body drag (the MOVE
## gesture) always has somewhere to start.
##
## It is not a hypothetical bound. A fit that snaps down a rung draws a 12px UV box at 6px,
## where the OLD radius-4 circles already left **0.3px² of body** — the move was gone
## before this change. The same box under the bound gets **17.9px²** back, so the worst
## case improves rather than degrading.
const HANDLE_BODY_CORE := 1.0 / 3.0

var _texture: Texture2D = null
## What is actually drawn: `_texture` with the transparent class erased and the STP
## class un-washed (`display_image`). Rebuilt only when `_texture` changes — it is a
## whole-image pass, far too expensive for `_draw`.
var _display_texture: Texture2D = null
var _frame: Dictionary = {}
## The frameset-in-context's distinct sheet regions (ADR-0130 dec. 4b), one entry per
## DISTINCT normalised block — see `group_regions` for the shape. Drawn as read-only
## outlines when `group_live` is false, and as fully live yellow boxes with corner
## handles and anchor colouring when it is (ADR-0130 dec. 12).
var _group_blocks: Array = []
## Are the group's regions draggable? False on a `frame` target, where they are the dim
## siblings drawn around the ONE box that is live; true on the emitter page, where there
## is no single frame in context and every region the shown frameset samples is its own
## editable box (ADR-0130 dec. 12). Set by the panel at bind, never inferred here.
var group_live: bool = false
## Index into `_group_blocks` of the region being dragged, or -1. Distinct from
## `_drag_mode`, which says WHICH PART is being dragged: with N live boxes the two
## questions have different answers and a single variable cannot hold both.
var _active_region: int = -1
## Index into `_group_blocks` of the region under the cursor, or -1 — the hover
## highlight, which is what makes "which one am I about to grab" answerable BEFORE the
## press rather than after it. 118 corpus region pairs overlap within one frameset and
## 48 of those share a top-left origin, so the handles genuinely stack.
var _hover_region: int = -1
## Index into `_group_blocks` of the region the author has PINNED with a click, or -1.
##
## WHY A LOCK EXISTS AT ALL. ADR-0130 dec. 12d makes the scope control follow the pointer,
## which is the only way to state a blast radius before the gesture when there are N boxes.
## It also means every control that reads the scope is unreachable: the facts overlay sits
## in the port's bottom-right corner, so the pointer travelling from a box to a tick, a
## button or a scroll bar CROSSES the sheet — and 118 corpus region pairs overlap within
## one frameset — so the panel is rebound, and the thing being reached for is replaced,
## before the hand arrives. That is already true of Export/Import today; it is fatal for a
## rail of per-frameset ticks.
##
## Locked, hover stops rebinding and only this region is grabbable. The others draw dim and
## inert — not merely un-highlighted — because a box that still looks live and no longer
## takes a press is the "present, visible, and not hittable" defect this surface has now
## shipped three times.
var _locked_region: int = -1
## Did the pointer actually move between press and release? A press-release with no motion
## is a CLICK and locks; anything else is a drag and commits. Tracked rather than compared
## against the start pixel because a resize that returns to its origin is still a drag the
## author made, and `region_edits` will correctly find nothing to write.
var _drag_moved: bool = false
## Every frameset of the bound effect, for the coverage overlay only — the canvas
## never edits them. Set by `bind_framesets`; empty means "draw no overlay".
var _framesets: Array = []
var _coverage_texture: Texture2D = null

# Drag state (ADR-0004 plain members, mirrors EffectCurvePainter's _dragging/_last_col).
var _drag_mode: String = ""          # "" | "body" | "tl" | "tr" | "bl" | "br"
var _drag_start_uv: Dictionary = {}  # uv snapshot at press (resize/move both compute FROM this)
var _drag_start_tex_px: Vector2 = Vector2.ZERO   # texture-pixel position of the press (move only)
var _preview_uv: Dictionary = {}     # live-during-drag uv; drawn instead of _frame.uv while dragging

# Zoom/pan state — view-only, never written back (not part of any frame's authored data).
# `_zoom_steps` is a count of ladder rungs from 100%, never a scale — a scale would need
# re-deriving on every resize. Negative steps walk OUT, down the reciprocal rungs, but
# only as far as `min_scale`: once the whole sheet is visible, smaller is just margin.
var _zoom_steps: int = 0
var _pan: Vector2 = Vector2.ZERO
## WHICH RUNG `_zoom_steps` IS COUNTED FROM — ADR-0098 dec. 2, made per-surface 2026-08-20.
##
## `false` is dec. 2 verbatim: the view opens at a flat 100%, always. That ruling was made
## for the FRAME SCREEN, where the canvas is a pixel-exact instrument for dragging a UV box
## and a fit that snaps down a rung renders a 23x23 box at 12px — smaller than its own 8px
## corner handles.
##
## `true` opens at the largest rung showing the whole sheet, FLOORED AT 100% — never
## smaller than dec. 2 gives, bigger where the port has room. The Texture TAB sets it,
## because that surface has no UV drag when nothing is in context and a port whose height
## is whatever the inspector row has: measured, a 128x256 sheet sits in a 701-tall port on
## a `frame` target and drew 128x256 in the middle of it ("it starts kind of small").
##
## DERIVED, NEVER STORED, for the same reason `_zoom_steps` is a rung count and not a
## scale: this port's height changes with the target, so a scale snapshotted at bind would
## be stale exactly when it mattered. The cost, stated: an author who has zoomed keeps
## their RUNG COUNT and not their absolute scale across a resize that moves the base.
var open_at_fit: bool = false
var _panning: bool = false
var _pan_start_mouse: Vector2 = Vector2.ZERO
var _pan_start_pan: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true   # a zoomed/panned draw can extend past the widget bounds
	# ADR-0098 dec. 1. Set NOWHERE before this — not here, not in project.godot — so it
	# fell through to the engine's `Linear` default and bilinearly smeared every sheet.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Bind a new frame (or effect) resets the view — an unrelated frame's old zoom/pan
## would be disorienting, and a differently-sized texture may not even validly support
## the old pan offset. Called from `bind_frame` below.
func reset_view() -> void:
	_zoom_steps = 0
	_pan = Vector2.ZERO
	queue_redraw()


## The rung a freshly-bound sheet opens at, and the base `_zoom_steps` walks from. See
## `open_at_fit` for why this is a per-surface policy rather than the flat 100% ADR-0098
## dec. 2 states.
##
## The `maxf` is the ADR-0098 ruling SURVIVING as a floor rather than being overturned, and
## it is load-bearing rather than defensive: `fit_scale` snaps DOWN the ladder, so a 256-tall
## sheet in a 263-tall port fits at 0.96 and snaps to 0.5 — halving the picture to save nine
## pixels, which is the measurement that made dec. 2 a flat 100% in the first place.
func opening_scale() -> float:
	if not open_at_fit:
		return 1.0
	return maxf(1.0, fit_scale(size, _texture_size(), MARGIN))


## The scale (screen pixels per texel) the sheet is drawn at right now: the opening rung,
## walked `_zoom_steps` rungs (negative walks out). Always a ladder rung, so a texel is
## always a whole number of screen pixels.
func current_scale() -> float:
	return clampf(ladder_advance(opening_scale(), _zoom_steps),
		min_scale(size, _texture_size(), MARGIN), ZOOM_MAX)


## Where the sheet is drawn right now. Every consumer here (hit-testing, the UV
## overlay, the drag math, the readout) takes THIS rect rather than re-deriving fit.
func current_draw_rect() -> Rect2:
	return view_rect(size, _texture_size(), MARGIN, current_scale(), _pan)


func _texture_size() -> Vector2:
	if _texture == null:
		return Vector2.ZERO
	return Vector2(_texture.get_width(), _texture.get_height())


func _gui_input(event: InputEvent) -> void:
	if _texture == null:
		return
	var texture_size := Vector2(_texture.get_width(), _texture.get_height())
	if texture_size.x <= 0 or texture_size.y <= 0:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		_zoom_at(event.position, 1)
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		_zoom_at(event.position, -1)
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_HOME:
		# The way back to the opening view. `reset_view` was built for ADR-0098 dec. 8 and
		# left with no key and no button; the amended, deliberately generous pan clamp
		# below makes it load-bearing rather than a convenience.
		reset_view()
		return
	# PAN is middle-drag + Shift+left-drag (ADR-0099 dec. 6). It was right-drag, which
	# made this the studio's only outlier — EffectScoreTimeline:1051, EffectFramesBar:103/116
	# and FedsPairLanePanel:917/921 all use these two — and it squatted on the button
	# EffectScoreTimeline and ColourKeyframeTrack open context menus with. Right-click is
	# now free for the region menu.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = event.pressed
		if _panning:
			_pan_start_mouse = event.position
			_pan_start_pan = _pan
		return
	# The Shift branch is tested BEFORE the UV-box hit-test below, the ordering hazard
	# EffectFramesBar:111 already documents for its own Alt branch: otherwise a Shift-drag
	# that happened to start inside the box would move the box instead of panning.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed and event.shift_pressed:
		_panning = true
		_pan_start_mouse = event.position
		_pan_start_pan = _pan
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and not event.pressed and _panning:
		_panning = false
		return
	if event is InputEventMouseMotion and _panning:
		# Clamped on the way IN, not just at draw time, so the stored pan can never drift
		# to a value a later zoom would snap back from (ADR-0098 dec. 8).
		_pan = clamp_pan(size, texture_size, MARGIN, current_scale(),
			_pan_start_pan + (event.position - _pan_start_mouse))
		queue_redraw()
		return

	if event is InputEventMouseMotion:
		_emit_hover(event.position, texture_size)

	# N LIVE REGIONS (ADR-0130 dec. 12) — the emitter page, where there is no single frame
	# in context and every distinct region the shown frameset samples is its own box. Taken
	# BEFORE the `_frame.is_empty()` return below, which is what used to end the input path
	# on every target kind but `frame`.
	if _frame.is_empty() and group_live and not _group_blocks.is_empty():
		_group_input(event, texture_size)
		return

	if _frame.is_empty():
		return
	var draw_rect := current_draw_rect()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var uv: Dictionary = _frame.get("uv", {})
			var mode := hit_test(event.position, uv, texture_size, draw_rect, HANDLE_GRAB)
			if mode == "":
				return
			_drag_mode = mode
			_drag_start_uv = uv.duplicate()
			_preview_uv = uv.duplicate()
			_drag_start_tex_px = canvas_point_to_texture_pixel(event.position, texture_size, draw_rect)
		elif _drag_mode != "":
			_drag_mode = ""
			uv_rect_changed.emit(_preview_uv)
	elif event is InputEventMouseMotion and _drag_mode != "":
		var tex_px := canvas_point_to_texture_pixel(event.position, texture_size, draw_rect)
		if _drag_mode == "body":
			_preview_uv = move_uv(_drag_start_uv, tex_px - _drag_start_tex_px)
		else:
			_preview_uv = resize_uv(_drag_start_uv, _drag_mode, tex_px)
		queue_redraw()


## The drag path when N regions are live. Deliberately a sibling of the single-frame path
## above rather than a generalisation of it: that one reads `_frame`, which is EMPTY here,
## and folding the two would mean a null-frame branch in every line of it.
##
## The commit addresses `members[0]` of the picked region. Any member would do — they share
## the block by construction (ADR-0099 dec. 2) — and the page re-expands it to the region's
## true, effect-wide membership through `region_members`, which reaches frames in other
## framesets for 81.4% of corpus regions. That expansion is the scope control's subject and
## is emphatically not this widget's business.
func _group_input(event: InputEvent, texture_size: Vector2) -> void:
	var draw_rect := current_draw_rect()
	if event is InputEventMouseMotion and _drag_mode == "":
		# HOVER. What the press WOULD take, resolved by the same `pick_region` the press
		# itself uses, so the highlight cannot promise a different box than the one that
		# gets grabbed.
		# LOCKED: the pointer no longer speaks for the scope. Nothing is emitted and the
		# highlight does not move, so an author crossing the sheet on the way to the rail
		# arrives at the same panel they left.
		if _locked_region >= 0:
			return
		var over: Dictionary = pick_region(event.position, _group_blocks, texture_size,
			draw_rect, HANDLE_GRAB)
		var idx: int = int(over.get("index", -1))
		if idx != _hover_region:
			_hover_region = idx
			queue_redraw()
			group_region_hovered.emit(hovered_member())
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var pick: Dictionary = pick_region(event.position, _group_blocks, texture_size,
				draw_rect, HANDLE_GRAB)
			var idx: int = int(pick.get("index", -1))
			# A PRESS ON BARE SHEET RELEASES THE LOCK, which is the only unlock gesture that
			# needs no chrome and no keyboard. It is a press and not a release so the box
			# stops being pinned the moment the author commits to leaving it.
			if idx < 0:
				if _locked_region >= 0:
					set_locked_region(-1)
				return
			# WHILE LOCKED, ONLY THE LOCKED BOX IS GRABBABLE. Otherwise a click aimed at the
			# rail that clipped a neighbouring box would start a drag on a region whose blast
			# radius is not the one the panel is showing — the exact confusion the lock is
			# here to remove.
			if _locked_region >= 0 and idx != _locked_region:
				return
			var region: Dictionary = _group_blocks[idx]
			var block: Rect2i = region["block"]
			# The drag runs in BLOCK space with positive signs. A region's members may wind
			# differently (419 corpus regions do), so there is no single set of signs the
			# preview could honestly carry — and it does not need any: `region_edits` writes
			# each member through its OWN signs at commit (ADR-0099 dec. 4).
			_active_region = idx
			_drag_mode = String(pick.get("mode", ""))
			_drag_start_uv = {"x": block.position.x, "y": block.position.y,
				"width": block.size.x, "height": block.size.y}
			_preview_uv = _drag_start_uv.duplicate()
			_drag_start_tex_px = canvas_point_to_texture_pixel(event.position, texture_size, draw_rect)
		elif _drag_mode != "" and _active_region >= 0:
			var members: Array = _group_blocks[_active_region].get("members", [])
			var uv: Dictionary = _preview_uv
			var idx: int = _active_region
			var moved: bool = _drag_moved
			_drag_mode = ""
			_active_region = -1
			_drag_moved = false
			# A CLICK IS NOT A ZERO-LENGTH DRAG. It used to be: the release committed an
			# unchanged rect, `region_edits` found nothing to write and the page returned
			# early — so a click was a no-op that travelled the whole commit path. It is a
			# LOCK now, which costs that path nothing (it never wrote anything) and gives the
			# gesture the meaning an author already expects from clicking a thing.
			if not moved:
				set_locked_region(idx)
				return
			queue_redraw()
			if not members.is_empty():
				group_uv_changed.emit(int(members[0]), uv)
	elif event is InputEventMouseMotion and _drag_mode != "":
		_drag_moved = true
		var tex_px := canvas_point_to_texture_pixel(event.position, texture_size, draw_rect)
		if _drag_mode == "body":
			_preview_uv = move_uv(_drag_start_uv, tex_px - _drag_start_tex_px)
		else:
			_preview_uv = resize_uv(_drag_start_uv, _drag_mode, tex_px)
		queue_redraw()


## Walk `steps` rungs of the pixel ladder, keeping the texel currently under `cursor`
## fixed on screen (the standard "zoom toward cursor" feel). The held texel is solved
## for directly (`pan_to_hold`) rather than nudged by a delta, so it lands exactly even
## though the rungs are not a constant ratio apart (1→2 doubles, 8→9 does not).
func _zoom_at(cursor: Vector2, steps: int) -> void:
	var texture_size := _texture_size()
	var want: int = _zoom_steps + steps
	# From the OPENING rung, not from 100% — otherwise a tab that opens at 2x would take
	# one wheel-down to reach 1x and report a step it had not taken, and `ZOOM_MAX` would
	# be reachable from a base that is already above 1.
	var want_scale := ladder_advance(opening_scale(), want)
	if want_scale > ZOOM_MAX or want_scale < min_scale(size, texture_size, MARGIN):
		return
	if want == _zoom_steps:
		return
	var tex_px := canvas_point_to_texture_pixel(cursor, texture_size, current_draw_rect())
	_zoom_steps = want
	var scale := current_scale()
	_pan = clamp_pan(size, texture_size, MARGIN, scale,
		pan_to_hold(size, texture_size, MARGIN, scale, tex_px, cursor))
	queue_redraw()
	hover_changed.emit(_hover_payload(cursor, texture_size))


## ESCAPE RELEASES THE PIN, and it is `_unhandled_key_input` rather than `_gui_input`
## because this canvas never takes focus — `_gui_input` would only see a key after a click
## had focused the Control, i.e. after the very gesture the author is trying to undo.
##
## Guarded on `_locked_region` so the event is only ACCEPTED when there is something to
## release: Escape is the studio's general "get me out of this" key, and swallowing it while
## nothing is pinned would make this canvas eat a keystroke meant for a dialog.
func _unhandled_key_input(event: InputEvent) -> void:
	if _locked_region < 0:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		set_locked_region(-1)
		get_viewport().set_input_as_handled()


## Report the texel under the cursor so the host's readout (ADR-0098 dec. 6) can name it.
## The canvas owns the mapping, so it is the only place that can answer honestly.
func _emit_hover(point: Vector2, texture_size: Vector2) -> void:
	hover_changed.emit(_hover_payload(point, texture_size))


func _hover_payload(point: Vector2, texture_size: Vector2) -> Dictionary:
	var px := canvas_point_to_texture_pixel(point, texture_size, current_draw_rect())
	var tx := floori(px.x)
	var ty := floori(px.y)
	var inside := tx >= 0 and ty >= 0 and tx < int(texture_size.x) and ty < int(texture_size.y)
	return {"x": tx, "y": ty, "inside": inside, "scale": current_scale()}


## Bind the effect's texture + the currently-selected frame Dictionary (the SAME
## shape `parse_frame()`/`FramesetChannel` read: `uv` {x,y,width,height},
## `vertices` {top_left,top_right,bottom_left,bottom_right}). Triggers a redraw.
## The zoom/pan VIEW resets only when the TEXTURE itself changes (a different
## effect loaded) — switching frames within the same sprite sheet keeps
## whatever region the author was zoomed into, since they're all on one texture.
func bind_frame(texture: Texture2D, frame: Dictionary) -> void:
	if texture != _texture:
		reset_view()
		_display_texture = null if texture == null else ImageTexture.create_from_image(
			display_image(texture.get_image()))
	_texture = texture
	_frame = frame
	queue_redraw()


## Bind every frameset of the effect so the canvas can show which parts of the sheet
## any frame actually addresses (ADR-0098 dec. 5). Separate from `bind_frame` because
## it changes per EFFECT, not per frame, and rebuilding the mask is a whole-sheet pass.
## Bind the FRAMESET in context (ADR-0130 dec. 4b): every distinct sheet region its frames
## sample, outlined read-only.
##
## This is the answer to "I can't get the yellow boxes showing which rect is sampling what".
## A frameset is a GROUP of frames, each with its own UV, so `bind_frame` — which takes
## exactly one — could only ever show a group by picking one member and lying about the
## rest. The refusal to pick was right; drawing NONE was the mistake, because N outlines
## were always available.
##
## DEDUPED BY BLOCK, deliberately. A UV rect is a shared region (ADR-0099) and members of
## one region have the identical block, so a frameset whose frames all sample the same rect
## draws ONE outline, not eight stacked on each other — the count in the readout would
## otherwise disagree with what the eye can see.
func bind_group(frames: Array) -> void:
	_group_blocks = group_regions(frames)
	_active_region = -1
	_hover_region = -1
	# THE LOCK IS AN INDEX INTO `_group_blocks`, so it cannot survive them being replaced —
	# a stale one would pin box 3 of a frameset that now has two. Silent, because a bind is
	# not a gesture: the host rebinds its own scope from the same call.
	_locked_region = -1
	_drag_moved = false
	queue_redraw()


## The frames of one frameset, folded into its DISTINCT sheet regions. Pure, and the seam
## every group behaviour is asserted through — the drawing, the hit priority and the
## anchor rule all read this array and nothing else, so a test needs no live node.
##
## Grouping is ADR-0099 decisions 1 and 2, verbatim and unweakened: identity is the
## NORMALISED block (the flip folded out, so E005's `(39,40,-32,32)` and `(8,40,32,32)`
## are one region), and two frames share a region **iff those blocks are exactly equal**
## — "not overlapping, not containing, not near". Partial overlap and containment stay
## SEPARATE regions and therefore separate boxes: E173 holds five rects at one origin (a
## beam at five lengths) plus a sprite nested inside their footprint, and all six are
## independently editable because no one rect can represent them (ADR-0099 context, 4).
##
## Each entry carries:
##   `block`   Rect2i  — the normalised region, what is drawn and hit-tested
##   `uv`      Dict    — the FIRST member's uv, kept for its SIGNS. A region write is
##                       sign-preserving per member (dec. 4), so a representative is only
##                       ever a source of signs for the preview, never for the commit.
##   `members` Array   — indices into `frames` of every member, in order. The frameset's
##                       own members; the effect-wide blast radius is `region_members`,
##                       which is a different and usually larger set (81.4% of corpus
##                       regions have members in more than one frameset).
##   `anchors` Array   — the DISTINCT anchor corners among those members, in tl/tr/bl/br
##                       order. Usually one; see `group_handle_color` for why it is a set.
static func group_regions(frames: Array) -> Array:
	var by_block := {}
	var out: Array = []
	for i in range(frames.size()):
		var fr = frames[i]
		if not (fr is Dictionary):
			continue
		var uv: Dictionary = fr.get("uv", {})
		if uv.is_empty():
			continue
		var block: Rect2i = normalised_block(uv)
		if by_block.has(block):
			var e: Dictionary = out[by_block[block]]
			e["members"].append(i)
			var a: String = anchor_corner(uv)
			if not e["anchors"].has(a):
				e["anchors"].append(a)
			continue
		by_block[block] = out.size()
		out.append({"block": block, "uv": uv.duplicate(), "members": [i],
			"anchors": [anchor_corner(uv)]})
	# Stable, and ordered SMALLEST-FIRST so a nested sprite is drawn over the rect it sits
	# inside rather than under it. `pick_region` re-derives its own priority from the areas
	# and does not lean on this, but the picture and the hit priority agreeing is the point.
	out.sort_custom(func(a, b): return a["block"].get_area() > b["block"].get_area())
	return out


## How many distinct regions the bound frameset samples — the readout's number, taken from
## the same array that is drawn so the two cannot disagree.
func group_region_count() -> int:
	return _group_blocks.size()


## The regions, for the panel's readout and the page's drag lowering.
func group_regions_bound() -> Array:
	return _group_blocks


## The region currently being dragged, or -1.
func active_region() -> int:
	return _active_region


## A representative member of the region under the cursor, as an index into the bound
## frameset's frames, or -1. Any member serves — they share the block by construction
## (ADR-0099 dec. 2) — and the page re-expands it to the region's true effect-wide
## membership, which is a larger set for 81.4% of corpus regions.
## Pin the scope to region `idx`, or release with `-1`. Idempotent, and it clears the hover
## highlight so the picture has exactly one "this one" cue rather than two that can disagree.
func set_locked_region(idx: int) -> void:
	if idx == _locked_region:
		return
	_locked_region = idx
	_hover_region = idx
	queue_redraw()
	group_region_locked.emit(locked_member())


## The sheet as it is DRAWN — `display_image`'d, with the erased class un-washed. The rail
## paints frameset thumbnails from this rather than the raw sheet for the reason
## `SequenceSpritePainter` records at its own head: RGBA has no "erased" value and the
## extractor carries 0x0000 as opaque black, so a raw sheet paints the erased class as a
## solid slab.
func display_texture() -> Texture2D:
	return _display_texture if _display_texture != null else _texture


func locked_region() -> int:
	return _locked_region


## A representative member of the pinned region, or -1. Any member does — they share the
## block by construction (ADR-0099 dec. 2) — and the host re-expands it to the region's
## true, effect-wide membership.
func locked_member() -> int:
	if _locked_region < 0 or _locked_region >= _group_blocks.size():
		return -1
	var members: Array = _group_blocks[_locked_region].get("members", [])
	return -1 if members.is_empty() else int(members[0])


func hovered_member() -> int:
	if _hover_region < 0 or _hover_region >= _group_blocks.size():
		return -1
	var members: Array = _group_blocks[_hover_region].get("members", [])
	return -1 if members.is_empty() else int(members[0])


func _draw_group_overlay(draw_rect: Rect2, texture_size: Vector2) -> void:
	var anchors_last: Array = []
	for i in range(_group_blocks.size()):
		var region: Dictionary = _group_blocks[i]
		var block: Rect2i = region["block"]
		var uv := {"x": block.position.x, "y": block.position.y,
			"width": block.size.x, "height": block.size.y}
		# The live preview replaces the stored block for the region under the drag, so the
		# box tracks the mouse exactly as the single-frame overlay's does.
		if group_live and i == _active_region and _drag_mode != "" and not _preview_uv.is_empty():
			uv = _preview_uv
		# Through `uv_to_canvas_rect` rather than a second coordinate derivation: it already
		# owns the block-not-signed-rect rule that a negative width otherwise breaks.
		var r := uv_to_canvas_rect(uv, texture_size, draw_rect)
		if not group_live:
			draw_rect_outline(r, GROUP_COLOR)
			continue
		# LIVE (ADR-0130 dec. 12). Every distinct region of the shown frameset is its own
		# editable box, because a frameset's frames each carry their own UV and the ones
		# that coincide exactly have already been folded into this single entry.
		# PINNED (the click-to-lock gesture): the locked box keeps its handles and its bright
		# outline; every other box goes to the read-only `GROUP_COLOR` outline and grows no
		# handles at all. Drawing them live while refusing their presses is the "present,
		# visible, and not hittable" defect this surface has shipped three times — so the
		# picture and the input rule are read off the same variable.
		if _locked_region >= 0 and i != _locked_region:
			draw_rect_outline(r, GROUP_COLOR)
			continue
		draw_rect_outline(r, HOVER_COLOR if i == _hover_region else HANDLE_COLOR)
		for corner in ["tl", "tr", "bl", "br"]:
			var p := _corner_point(r, corner)
			var hs := HANDLE_SIZE * 0.5
			var col: Color = group_handle_color(corner, region["anchors"],
				_drag_mode if i == _active_region else "")
			var square := Rect2(p - Vector2(hs, hs), Vector2(HANDLE_SIZE, HANDLE_SIZE))
			# ANCHORS ARE DEFERRED TO A SECOND PASS, and that is not cosmetic ordering.
			# 48 corpus region pairs share a top-left origin, so their handles occupy the
			# SAME pixels — and drawing in region order let a later region's plain yellow
			# square paint over an earlier one's cyan anchor, silently removing the one cue
			# that says which way a rect is wound (ADR-0099 dec. 8). Caught by screenshot on
			# E066 emitter 0, whose two regions both start at (216,8): the tl-anchored one is
			# drawn first, so its anchor vanished under the other's corner.
			#
			# Anchors last means a stacked corner shows cyan whenever ANY region anchors
			# there, which is the honest reading — the alternative hides information that
			# exists rather than showing information that does not.
			if col == ANCHOR_COLOR:
				anchors_last.append([square, col])
			else:
				draw_rect(square, col, true)


	for entry in anchors_last:
		draw_rect(entry[0], entry[1], true)


## What colour a corner handle draws in for a LIVE GROUP region, given the distinct anchor
## corners of that region's members. Pure, and the group twin of `handle_color`.
##
## WHY `anchors` IS A SET AND NOT A CORNER. ADR-0099 dec. 8 colours the corner this frame's
## stored `(x,y)` actually refers to, and on a `frame` target "this frame" is unambiguous.
## On the emitter page there is no single frame — a region is N members, and every member
## has the identical block but NOT necessarily the same winding: 419 of 19,518 corpus
## regions have members that disagree. Picking one member's corner there would paint a
## cyan anchor that contradicts the other members with nothing on screen saying so, which
## is the ADR-0100 defect this ADR family keeps refusing.
##
## So EVERY corner that is some member's anchor is coloured. When the members agree — 97.9%
## of regions — that is exactly one cyan corner and the picture is unchanged from the
## single-frame case. When they disagree the author sees two (or more), which is the honest
## statement that this region's members are wound differently. Precedence is
## dragged > anchor > plain, matching `handle_color`.
static func group_handle_color(corner: String, anchors: Array, drag_mode: String) -> Color:
	if corner == drag_mode:
		return DRAGGING_COLOR
	return ANCHOR_COLOR if anchors.has(corner) else HANDLE_COLOR


## What a mouse-down at canvas-local `point` grabs when N regions are live: which region
## and which part of it. Returns `{"index": int, "mode": String}` with `index == -1` and
## `mode == ""` when the press hits nothing. Pure.
##
## THE PRIORITY RULE, and it exists because the boxes genuinely stack. Within one frameset
## the corpus holds 118 overlapping region pairs, 69 of them nested and 48 sharing a
## top-left origin — so corner handles land exactly on top of each other and a naive
## first-hit-wins would make the smaller box of a nested pair ungrabbable.
##
##   1. A CORNER beats a BODY, across regions, not just within one. A handle sitting inside
##      a bigger neighbour's body must win, or resizing the inner rect of a nested pair
##      would move the outer one instead.
##   2. Within the same class the SMALLER block wins. Nesting is asymmetric — the small
##      sprite is reachable nowhere else, while the big one is reachable anywhere the small
##      one is not — so this is the only tie-break that leaves every region grabbable.
static func pick_region(point: Vector2, regions: Array, texture_size: Vector2,
		texture_draw_rect: Rect2, handle_size: float) -> Dictionary:
	var best_index := -1
	var best_mode := ""
	var best_corner := false
	var best_area := 0
	for i in range(regions.size()):
		var region: Dictionary = regions[i]
		var block: Rect2i = region["block"]
		var mode := hit_test(point, {"x": block.position.x, "y": block.position.y,
			"width": block.size.x, "height": block.size.y},
			texture_size, texture_draw_rect, handle_size)
		if mode == "":
			continue
		var is_corner: bool = mode != "body"
		var area: int = block.get_area()
		if best_index == -1 or (is_corner and not best_corner) \
				or (is_corner == best_corner and area < best_area):
			best_index = i
			best_mode = mode
			best_corner = is_corner
			best_area = area
	return {"index": best_index, "mode": best_mode}


func bind_framesets(framesets: Array, texture_size: Vector2i) -> void:
	_framesets = framesets
	_coverage_texture = null
	if not framesets.is_empty() and texture_size.x > 0 and texture_size.y > 0:
		_coverage_texture = ImageTexture.create_from_image(
			coverage_image(framesets, texture_size))
	queue_redraw()


func _draw() -> void:
	if _texture == null:
		return
	var texture_size := Vector2(_texture.get_width(), _texture.get_height())
	if texture_size.x <= 0 or texture_size.y <= 0:
		return
	var draw_rect := current_draw_rect()
	_draw_checkerboard(draw_rect)
	draw_texture_rect(_display_texture if _display_texture != null else _texture, draw_rect, false)
	if _coverage_texture != null:
		draw_texture_rect(_coverage_texture, draw_rect, false)
	if not _group_blocks.is_empty():
		_draw_group_overlay(draw_rect, texture_size)
	if not _frame.is_empty():
		_draw_uv_overlay(draw_rect, texture_size)


## The backdrop the erased (transparent-class) texels reveal — ADR-0098 dec. 4. Only
## over the sheet itself, never the letterbox, so it reads as "this part of the sheet
## is nothing" rather than as panel chrome. Iterated over the VISIBLE cells only: at
## rung 16 a 256 px sheet is 4096 px wide and all but a couple of dozen cells are
## clipped away.
func _draw_checkerboard(sheet: Rect2) -> void:
	var visible_area := sheet.intersection(Rect2(Vector2.ZERO, size))
	if visible_area.size.x <= 0.0 or visible_area.size.y <= 0.0:
		return
	var first := Vector2i(
		floori((visible_area.position.x - sheet.position.x) / CHECKER_CELL),
		floori((visible_area.position.y - sheet.position.y) / CHECKER_CELL))
	var last := Vector2i(
		floori((visible_area.end.x - sheet.position.x - 0.001) / CHECKER_CELL),
		floori((visible_area.end.y - sheet.position.y - 0.001) / CHECKER_CELL))
	for cy in range(first.y, last.y + 1):
		for cx in range(first.x, last.x + 1):
			var cell := Rect2(
				sheet.position + Vector2(float(cx), float(cy)) * CHECKER_CELL,
				Vector2(CHECKER_CELL, CHECKER_CELL)).intersection(visible_area)
			if cell.size.x > 0.0 and cell.size.y > 0.0:
				draw_rect(cell, checker_color_at(cx, cy), true)


func _draw_uv_overlay(draw_rect: Rect2, texture_size: Vector2) -> void:
	var uv: Dictionary = _preview_uv if _drag_mode != "" else _frame.get("uv", {})
	if uv.is_empty():
		return
	var uv_rect := uv_to_canvas_rect(uv, texture_size, draw_rect)
	draw_rect_outline(uv_rect, HANDLE_COLOR)
	# Corner handles (#279) — small filled squares at each corner, the drag affordance
	# `hit_test` targets. Highlighted while that specific corner is being dragged, and
	# the ANCHOR corner is coloured apart (ADR-0099 dec. 8): for a mirrored frame the
	# stored (x,y) is the top-RIGHT, and painting the top-left as the anchor would
	# contradict the spinboxes beside the canvas.
	for corner in ["tl", "tr", "bl", "br"]:
		var p := _corner_point(uv_rect, corner)
		var hs := HANDLE_SIZE * 0.5
		draw_rect(Rect2(p - Vector2(hs, hs), Vector2(HANDLE_SIZE, HANDLE_SIZE)),
			handle_color(corner, uv, _drag_mode), true)


## What colour corner handle `corner` draws in, given the frame it belongs to and the
## corner currently being dragged (`""` when none). Pure — split out of `_draw_uv_overlay`
## so the rule is assertable without a live node or a screenshot. Precedence is
## dragged > anchor > plain.
static func handle_color(corner: String, uv: Dictionary, drag_mode: String) -> Color:
	if corner == drag_mode:
		return DRAGGING_COLOR
	return ANCHOR_COLOR if corner == anchor_corner(uv) else HANDLE_COLOR


## The rectangle a press must land in to grab `corner` of the drawn box `r`, in the same
## canvas-local pixels `hit_test` is given. Pure, and the SINGLE owner of the asymmetry the
## two constants above describe: `grab_size * 0.5` outward, at most `HANDLE_BODY_CORE` of
## the box's own side inward.
##
## Exposed rather than inlined because the interesting question about a grab target is not
## "does this one point hit" but "how much of the thing I can see is reachable" — which is
## a rect, assertable with no window, and the shape `timeline-grip-swallows-short-spans`
## says to measure rather than eyeball.
static func corner_grab_rect(r: Rect2, corner: String, grab_size: float) -> Rect2:
	var half := grab_size * 0.5
	var inward_x := minf(half, absf(r.size.x) * HANDLE_BODY_CORE)
	var inward_y := minf(half, absf(r.size.y) * HANDLE_BODY_CORE)
	var left_of_x: bool = corner == "tl" or corner == "bl"
	var above_y: bool = corner == "tl" or corner == "tr"
	var left: float = half if left_of_x else inward_x
	var right: float = inward_x if left_of_x else half
	var top: float = half if above_y else inward_y
	var bottom: float = inward_y if above_y else half
	return Rect2(_corner_point(r, corner) - Vector2(left, top),
		Vector2(left + right, top + bottom))


static func _corner_point(r: Rect2, corner: String) -> Vector2:
	match corner:
		"tl": return r.position
		"tr": return r.position + Vector2(r.size.x, 0)
		"bl": return r.position + Vector2(0, r.size.y)
		"br": return r.position + r.size
	return r.position


func draw_rect_outline(r: Rect2, color: Color) -> void:
	draw_rect(r, color, false, 2.0)


## The rect a freshly-bound sheet is drawn at: `texture_size` at 100%, centered within
## `canvas_size` (inset by `margin` on every side). NOT a fit — see the pixel-ladder
## note in the header for why fitting opened E019 at half size. Pure; identical to
## `view_rect` at scale 1 with no pan, which is exactly the state a fresh bind is in.
static func texture_rect(canvas_size: Vector2, texture_size: Vector2, margin: float = MARGIN) -> Rect2:
	return view_rect(canvas_size, texture_size, margin, 1.0, Vector2.ZERO)


## The area inside `canvas_size` the sheet may occupy: the widget minus `margin` on
## every side. Pure — `fit_scale`, `view_rect` and `clamp_pan` must all agree on it.
static func available_size(canvas_size: Vector2, margin: float) -> Vector2:
	return Vector2(maxf(canvas_size.x - margin * 2.0, 0.0), maxf(canvas_size.y - margin * 2.0, 0.0))


## Snap a raw scale DOWN to the nearest pixel-ladder rung — `1,2,3,…,ZOOM_MAX` at or
## above 1:1, reciprocal integers (`1/2, 1/3, …`) below it. Snapping down rather than
## to-nearest is what guarantees the result still FITS: a 1.098× fit rounded to 1×
## letterboxes a little more, rounded to 2× would overflow the port. Pure.
static func ladder_snap(raw: float) -> float:
	if raw <= 0.0:
		return 1.0
	if raw >= 1.0:
		return clampf(floorf(raw + 1e-6), 1.0, ZOOM_MAX)
	return 1.0 / float(maxi(1, ceili(1.0 / raw - 1e-6)))


## The next rung up (`up`) or down from `scale`. The ladder is not a constant ratio:
## 1→2 doubles, 8→9 does not, and below 1:1 the rungs are reciprocal integers, so
## stepping is a rung walk rather than a multiply. Pure.
static func ladder_step(scale: float, up: bool) -> float:
	if scale >= 1.0:
		var n: int = maxi(1, roundi(scale))
		if up:
			return minf(float(n + 1), ZOOM_MAX)
		return 0.5 if n <= 1 else float(n - 1)
	var d: int = maxi(2, roundi(1.0 / scale))
	if up:
		return 1.0 if d <= 2 else 1.0 / float(d - 1)
	return 1.0 / float(d + 1)


## `scale` walked `steps` rungs (negative walks down). Pure.
static func ladder_advance(scale: float, steps: int) -> float:
	var s := scale
	for _i in range(absi(steps)):
		s = ladder_step(s, steps > 0)
	return s


## The largest ladder rung at which the WHOLE sheet is visible inside the port. Not
## where the view opens (that is always 100%) — this is the floor zooming out stops at.
## Pure.
static func fit_scale(canvas_size: Vector2, texture_size: Vector2, margin: float = MARGIN) -> float:
	var available := available_size(canvas_size, margin)
	if texture_size.x <= 0 or texture_size.y <= 0 or available.x <= 0 or available.y <= 0:
		return 1.0
	return ladder_snap(minf(available.x / texture_size.x, available.y / texture_size.y))


## How far OUT the view may zoom: enough to see the whole sheet, and no further, since
## shrinking past that adds margin rather than information. Never above 100% — a sheet
## smaller than the port is already wholly visible at 1:1 and zooming out is refused.
## Pure.
static func min_scale(canvas_size: Vector2, texture_size: Vector2, margin: float = MARGIN) -> float:
	return minf(1.0, fit_scale(canvas_size, texture_size, margin))


## Where the sheet lands at `scale`, centered in the port and shifted by `pan` (which
## is clamped here, so the returned rect can never be a view the user cannot get back
## from). The size is `texture_size * scale` EXACTLY — a whole number of screen pixels
## per texel, which is the property the readout depends on. Pure.
static func view_rect(canvas_size: Vector2, texture_size: Vector2, margin: float,
		scale: float, pan: Vector2) -> Rect2:
	var available := available_size(canvas_size, margin)
	if texture_size.x <= 0 or texture_size.y <= 0 or available.x <= 0 or available.y <= 0:
		return Rect2(Vector2(margin, margin), Vector2.ZERO)
	var sheet := texture_size * scale
	var base := Vector2(margin, margin) + (available - sheet) * 0.5
	return Rect2(base + clamp_pan(canvas_size, texture_size, margin, scale, pan), sheet)


## Clamp `pan` per axis — ADR-0098 dec. 8, AMENDED. Both of that decision's original
## sentences turned out to be false in practice. Slack of `(sheet - available)/2` keeps
## the PORT inside the SHEET, which means no corner of the sheet can ever be brought to
## the middle of the port — exactly where an author zoomed to rung 16 wants to work, and
## where the region chrome needs room around the box. And it centre-LOCKED any axis where
## the sheet letterboxes, so a tall sheet in a wide port could not be nudged on x at all.
##
## The rule is now slack `(available + sheet)/2` on both axes: enough for any texel to
## reach the port centre, with no letterbox special case. It is still a CLAMP, never
## unbounded — the failure dec. 8 was actually written against was `_pan` being clamped
## nowhere, so a drag could push the sheet out with no way back short of rebinding the
## effect. A bounded pan is always draggable back, and `Home` now resets the view outright.
## Pure.
static func clamp_pan(canvas_size: Vector2, texture_size: Vector2, margin: float,
		scale: float, pan: Vector2) -> Vector2:
	var available := available_size(canvas_size, margin)
	var sheet := texture_size * scale
	var slack := (available + sheet) * 0.5
	return Vector2(clampf(pan.x, -slack.x, slack.x), clampf(pan.y, -slack.y, slack.y))


## The pan that puts texture-pixel `tex_px` exactly under canvas point `cursor` at
## `scale` — solved, not nudged, so a zoom step lands the held texel exactly. Pure;
## the caller clamps the result (an unreachable hold is a clamped one, not an error).
static func pan_to_hold(canvas_size: Vector2, texture_size: Vector2, margin: float,
		scale: float, tex_px: Vector2, cursor: Vector2) -> Vector2:
	var available := available_size(canvas_size, margin)
	var base := Vector2(margin, margin) + (available - texture_size * scale) * 0.5
	return cursor - tex_px * scale - base


## Which of the three texel classes `c` is — ADR-0098 dec. 3. The partition is the
## SHADERS', not a palette-word taxonomy: both passes discard on colour before they
## look at alpha, so `0x8000` (black with STP set, which `TEXTURE_AND_PALETTE_FORMAT.md`
## calls "opaque black" — a name for the PSX convention, not for what this engine
## draws) is transparent, not art. Classifying it by alpha instead would move 158,778
## corpus texels into the visible art and read E001/E509/E510 as 88.1% art the game
## never draws. Pure.
static func texel_class(c: Color) -> String:
	if c.r < BLACK_EPSILON and c.g < BLACK_EPSILON and c.b < BLACK_EPSILON:
		return "transparent"
	return "opaque" if c.a >= 1.0 else "stp"


## The three-way partition of a whole sheet, `{transparent, stp, opaque}`. Pure;
## the readout and the corpus guard both consume it.
static func class_counts(img: Image) -> Dictionary:
	var counts := {"transparent": 0, "stp": 0, "opaque": 0}
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var key := texel_class(img.get_pixel(x, y))
			counts[key] = int(counts[key]) + 1
	return counts


## The sheet as the viewport should draw it: the transparent class erased (it was
## painting as solid black over 73.20% of the corpus — RGBA has no "erased" value, so
## the extractor carries `0x0000` as opaque black) and the STP class forced to alpha 1
## (its alpha is a blend-mode FLAG per ADR-0096, and `draw_texture_rect` was rendering
## that flag as half opacity — washing out every visible texel on the sheet).
## Colour is never altered: tinting a class would be a different lie. Pure — the
## source image is left untouched.
static func display_image(src: Image) -> Image:
	var out := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	for y in range(src.get_height()):
		for x in range(src.get_width()):
			var c := src.get_pixel(x, y)
			if texel_class(c) == "transparent":
				out.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				out.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
	return out


## Which texels of a `texture_size` sheet some frame's UV rect addresses, as one byte
## per texel. The UNION, not the sum: frames overlap constantly (E019 packs 184 of them
## onto one 128x256 sheet), so adding rect areas would report well over 100%. UV rects
## are authored bytes and nothing stops them running off the sheet, so they clip. Pure.
static func coverage_mask(framesets: Array, texture_size: Vector2i) -> PackedByteArray:
	var mask := PackedByteArray()
	if texture_size.x <= 0 or texture_size.y <= 0:
		return mask
	mask.resize(texture_size.x * texture_size.y)
	for fs in framesets:
		for f in (fs.get("frames", []) if fs is Dictionary else []):
			var uv: Dictionary = f.get("uv", {}) if f is Dictionary else {}
			if uv.is_empty():
				continue
			# Through the flip fold: a negative width used to make `x1 < x0`, an empty
			# range, so a mirrored frame contributed NO coverage at all (ADR-0099).
			var block := normalised_block(uv)
			var x0: int = maxi(0, block.position.x)
			var y0: int = maxi(0, block.position.y)
			var x1: int = mini(texture_size.x, block.position.x + block.size.x)
			var y1: int = mini(texture_size.y, block.position.y + block.size.y)
			for y in range(y0, y1):
				var row: int = y * texture_size.x
				for x in range(x0, x1):
					mask[row + x] = 1
	return mask


## How many texels of the sheet any frame addresses. E019 is 26,652 of 32,768 (81.3%),
## E317 only 4,480 of 16,384 (27.3%) — three-quarters of that sheet is dead. Pure.
static func covered_texel_count(framesets: Array, texture_size: Vector2i) -> int:
	var mask := coverage_mask(framesets, texture_size)
	var n := 0
	for b in mask:
		n += b
	return n


## The dimming overlay: clear where a frame reaches, `UNCOVERED_DIM` where none does.
## Sheet-sized, so it maps 1:1 onto whatever rect the sheet is drawn at. Pure.
static func coverage_image(framesets: Array, texture_size: Vector2i) -> Image:
	var mask := coverage_mask(framesets, texture_size)
	var img := Image.create(maxi(1, texture_size.x), maxi(1, texture_size.y), false, Image.FORMAT_RGBA8)
	img.fill(UNCOVERED_DIM)
	for y in range(texture_size.y):
		var row: int = y * texture_size.x
		for x in range(texture_size.x):
			if mask[row + x] == 1:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return img


## The BGR555 palette word a texel's colour + STP bit pack back into —
## `bit 15 STP | 14-10 Blue | 9-5 Green | 4-0 Red` (TEXTURE_AND_PALETTE_FORMAT.md).
## The readout shows it because a colour alone cannot distinguish `0x0000` (the
## transparent one) from `0x8000` (the one the format doc calls opaque black): both
## are black, and the viewport draws neither. Pure.
static func palette_word(c: Color) -> int:
	var r5: int = clampi(int(c.r * 255.0) >> 3, 0, 31)
	var g5: int = clampi(int(c.g * 255.0) >> 3, 0, 31)
	var b5: int = clampi(int(c.b * 255.0) >> 3, 0, 31)
	var stp: int = 0 if c.a >= 1.0 else 1
	return (stp << 15) | (b5 << 10) | (g5 << 5) | r5


static func format_palette_word(word: int) -> String:
	return "0x%04X" % word


## Every CLUT slot holding `c`, compared in FIVE-BIT space. Two independent reasons:
## (1) `parse_effect.extract_palette` bit-replicates a 5-bit channel to 8 (`(v<<3)|(v>>2)`)
## while the TGA path truncates (`v*8`), so one palette word is 198 in
## `texture_palette.json` and 192 in `texture.tga` — on E019 only 6 of 66 colours match
## exactly, but 66 of 66 match after `>>3`. (2) A colour does not identify an index
## (ADR-0199): E019 holds 67 distinct colours in 256 slots. Naming one would be a
## fabrication, so every match is named. Pure.
static func matching_palette_indices(palette: Array, c: Color) -> Array:
	var want := Vector3i(int(c.r * 255.0) >> 3, int(c.g * 255.0) >> 3, int(c.b * 255.0) >> 3)
	var hits: Array = []
	for i in range(palette.size()):
		var e = palette[i]
		if not (e is Array) or e.size() < 3:
			continue
		if Vector3i(int(e[0]) >> 3, int(e[1]) >> 3, int(e[2]) >> 3) == want:
			hits.append(i)
	return hits


## What this viewport cannot honestly show for the bound frame, named precisely, or ""
## when there is nothing to admit (ADR-0098 dec. 6). The flat `texture.tga` is one RGBA
## decode through ONE sub-palette, but `frames.json` carries the CLUT-line select
## (`uses_palette_2`, `flags_byte0 & 0x10`) and `palette_id` per frame — so the readout
## can name both sides rather than shrug "colours approximate". Pure.
static func clut_caveat(frame: Dictionary) -> String:
	var line: int = 2 if bool(frame.get("uses_palette_2", false)) else 1
	if not bool(frame.get("is_8bpp", true)):
		# A 4bpp sheet is not one image: `extract_effect_texture.lua` decodes it from CLUT
		# line 2's first 16 entries, while `texture_palette.json` — the swatch strip — is
		# always line 1. Neither is necessarily what this frame reads. Recolouring per
		# frame needs the index plane, which the asset dir does not carry.
		return ("4bpp: this frame reads CLUT line %d / sub-palette %d. The sheet was decoded"
			+ " from line 2's first 16 entries and the swatch strip is line 1, so both are"
			+ " indicative only — a true per-frame view needs the index plane (#297).") % [
				line, int(frame.get("palette_id", 0))]
	if line == 2:
		return ("This frame reads CLUT line 2; the export decoded line 1, so these colours"
			+ " are the right shape but not necessarily the right hues (#297).")
	return ""


## The checkerboard cell colour at cell `(cx, cy)`. Two greys, neither black — the
## never-drawn texels ARE black, so a flat backdrop of any colour could be mistaken
## for one. Pure.
static func checker_color_at(cx: int, cy: int) -> Color:
	return CHECKER_A if (cx + cy) % 2 == 0 else CHECKER_B


## THE FLIP FOLD (ADR-0099 dec. 1). A flip is encoded in the UV COORDINATES, not in a
## flag: 2,628 of 22,920 corpus frames across 179 effects carry a negative `width` or
## `height`, and a negative width means the stored `x` is the block's LAST column.
## E005 stores one 32x32 block twice — `(8,40,32,32)` and `(39,40,-32,32)`, with
## 39 - 32 + 1 = 8 — the same texels, one drawn mirrored. The convention is measured,
## not assumed: folding negatives as "stored x is the last column" lands 847 raw corpus
## tuples onto blocks that already exist elsewhere in the same effect, while the
## off-by-one reading ("one past the block") lands ZERO. This is the sheet region's
## identity — derived on read, never stored. Pure.
static func normalised_block(uv: Dictionary) -> Rect2i:
	var x: int = int(uv.get("x", 0))
	var y: int = int(uv.get("y", 0))
	var w: int = int(uv.get("width", 0))
	var h: int = int(uv.get("height", 0))
	if w < 0:
		x += w + 1
		w = -w
	if h < 0:
		y += h + 1
		h = -h
	return Rect2i(x, y, w, h)


## The inverse, and the ONLY way a region edit may write (ADR-0099 dec. 4): the new block
## is computed once, then each member stores it through ITS OWN signs — `x_left` for a
## positive width, `x_left + w - 1` for a negative one. A mirrored member stays mirrored.
## `uv` supplies the signs (and every field the region does not own: `palette_id`,
## `is_8bpp`, the blend fields — dec. 3). Exact round trip on all 22,920 corpus frames.
## Pure.
static func block_to_uv(uv: Dictionary, block: Rect2i) -> Dictionary:
	var out := uv.duplicate()
	var w_neg: bool = int(uv.get("width", 0)) < 0
	var h_neg: bool = int(uv.get("height", 0)) < 0
	out["x"] = block.position.x + block.size.x - 1 if w_neg else block.position.x
	out["y"] = block.position.y + block.size.y - 1 if h_neg else block.position.y
	out["width"] = -block.size.x if w_neg else block.size.x
	out["height"] = -block.size.y if h_neg else block.size.y
	return out


## Which corner of the drawn box this frame's stored `(x,y)` actually refers to
## (ADR-0099 dec. 8). For 2,628 corpus frames it is not the top-left — the census is
## TL 20,292 / TR 1,498 / BL 633 / BR 497 — so a canvas that always paints the top-left
## as the anchor contradicts the spinboxes beside it. Every member of a region has the
## identical block, so this is the ONLY per-member difference there is to draw. Pure.
static func anchor_corner(uv: Dictionary) -> String:
	var right: bool = int(uv.get("width", 0)) < 0
	var bottom: bool = int(uv.get("height", 0)) < 0
	if bottom:
		return "br" if right else "bl"
	return "tr" if right else "tl"


## How this frame's quad is turned, classified by its EDGE DIRECTIONS (ADR-0099 dec. 2's
## companion measurement): rotation lives in the vertices, never in the UV, so a turned
## frame's UV rect is an ordinary positive one and the region cannot see it. Corpus:
## 19,120 `upright`, 1,735 `turned` (an axis-aligned quarter/half turn — the exact
## quarter-turn count, 1,703, is the ADR's), 2,064 `rotated` (no edge axis-aligned) and
## one degenerate. It is a FACET for dec. 5's member list, never part of identity — 387
## of the 3,253 shared groups have members that disagree on it. Pure.
static func quad_orientation(frame: Dictionary) -> String:
	var v: Dictionary = frame.get("vertices", {})
	var tl: Array = v.get("top_left", [])
	var tr: Array = v.get("top_right", [])
	var bl: Array = v.get("bottom_left", [])
	if tl.size() < 2 or tr.size() < 2 or bl.size() < 2:
		return "degenerate"
	var tx: int = int(tr[0]) - int(tl[0])
	var ty: int = int(tr[1]) - int(tl[1])
	var lx: int = int(bl[0]) - int(tl[0])
	var ly: int = int(bl[1]) - int(tl[1])
	if (tx == 0 and ty == 0) or (lx == 0 and ly == 0):
		return "degenerate"
	if ty == 0 and lx == 0:
		return "upright" if (tx > 0 and ly > 0) else "turned"
	if tx == 0 and ly == 0:
		return "turned"
	return "rotated"


## The size this frame's quad is DRAWN at, in PSX units — the bounding box of its four
## vertices. Not derivable from the region: scale is vertex data, and varying it over one
## shared block is the majority case (E019's biggest group draws one 23x23 block at ten
## sizes, 7x7 to 56x56; 1,944 of 3,253 groups draw at more than one size). It is why
## dec. 3 forbids a region edit from touching vertices, and why the member list must
## show it. Pure.
static func quad_size(frame: Dictionary) -> Vector2i:
	var v: Dictionary = frame.get("vertices", {})
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	var any := false
	for key in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		var pt: Array = v.get(key, [])
		if pt.size() < 2:
			continue
		any = true
		lo = Vector2i(mini(lo.x, int(pt[0])), mini(lo.y, int(pt[1])))
		hi = Vector2i(maxi(hi.x, int(pt[0])), maxi(hi.y, int(pt[1])))
	if not any:
		return Vector2i.ZERO
	return hi - lo + Vector2i.ONE


## THE REGION QUERY (ADR-0099 dec. 1-2). Every frame of the effect whose normalised block
## is EXACTLY `block` — never overlapping, never containing, never near. Overlap is worth
## drawing as a readout but is never identity: E173 holds five rects at one origin (a beam
## at five lengths) plus a sprite nested inside their footprint, and no single rect can
## represent them. There is no region id and no region table; membership is recomputed
## from the frame bytes on read, exactly as `coverage_mask` is, which is why the same
## effect reloaded always yields the same regions.
##
## Each member carries the facets dec. 5's scope control filters and lists on — the count
## alone is not enough to consent to a 30-frame edit when the members disagree about
## orientation and drawn size. Pure.
static func region_members(framesets: Array, block: Rect2i) -> Array:
	var out: Array = []
	for i in range(framesets.size()):
		var fs = framesets[i]
		var frames: Array = (fs.get("frames", []) if fs is Dictionary else [])
		for j in range(frames.size()):
			var frame = frames[j]
			if not (frame is Dictionary):
				continue
			var uv: Dictionary = frame.get("uv", {})
			if uv.is_empty() or normalised_block(uv) != block:
				continue
			out.append({
				"frameset_index": i,
				"frame_index": j,
				"mirrored": int(uv.get("width", 0)) < 0,
				"v_flipped": int(uv.get("height", 0)) < 0,
				"anchor": anchor_corner(uv),
				"orientation": quad_orientation(frame),
				"quad_size": quad_size(frame),
				"palette_id": int(frame.get("palette_id", 0)),
			})
	return out


## The block the frame at `(frameset_index, frame_index)` shares — i.e. which region a
## selection opens. `Rect2i()` when there is no such frame. Pure.
static func region_of(framesets: Array, frameset_index: int, frame_index: int) -> Rect2i:
	if frameset_index < 0 or frameset_index >= framesets.size():
		return Rect2i()
	var fs = framesets[frameset_index]
	var frames: Array = (fs.get("frames", []) if fs is Dictionary else [])
	if frame_index < 0 or frame_index >= frames.size():
		return Rect2i()
	var frame = frames[frame_index]
	if not (frame is Dictionary):
		return Rect2i()
	var uv: Dictionary = frame.get("uv", {})
	return Rect2i() if uv.is_empty() else normalised_block(uv)


## Every region on the sheet, `block -> member count`. E019's 184 frames collapse to
## FOURTEEN entries here; corpus-wide 22,920 frames collapse to 6,605 regions of which
## 3,253 hold two or more frames. Pure — the scope control's "N frames" and the
## frameset page's region list both read it.
static func region_index(framesets: Array) -> Dictionary:
	var index: Dictionary = {}
	for fs in framesets:
		for frame in (fs.get("frames", []) if fs is Dictionary else []):
			if not (frame is Dictionary):
				continue
			var uv: Dictionary = frame.get("uv", {})
			if uv.is_empty():
				continue
			var block := normalised_block(uv)
			index[block] = int(index.get(block, 0)) + 1
	return index


## What a frame's `uv.width`/`uv.height` BYTE can actually represent — inferred from the
## value the extractor produced, because the thing that decides it does not reach here.
##
## The sign is not in the value: it is a per-frame, per-AXIS flag bit (`E###.BIN` byte1
## bits 4/5) that `parse_frame` applies on read and `write_effect_frames.py` deliberately
## never authors. `frames.json` does not carry it. Corpus census over the real BINs:
## 13,614 frames flag-clear with a positive width, 996 flag-set with a negative one, and
## 16 flag-SET but POSITIVE — so "is negative" and "is flag-set" are different questions.
##
##   flag clear -> the byte is plain unsigned          -> 0..255
##   flag set   -> the byte is read two's-complement   -> -128..127
##
## A value the parser handed us that is negative PROVES the flag is set; one above 127
## proves it is clear (the parser would have negated it otherwise); one in 0..127 cannot
## tell, so the honest answer is the intersection. Guessing wider is not safe: outside the
## real range the writer's `& 0xFF` silently ALIASES — E027 stores a region at width -128,
## and growing it to -136 writes byte 120, which the still-set flag reads back as +120,
## losing the block and the flip at once. Pure.
static func encodable_uv_range(current: int) -> Vector2i:
	if current < 0:
		return Vector2i(-128, 127)
	if current > 127:
		return Vector2i(0, 255)
	return Vector2i(0, 127)


## Can every member actually STORE this block? Verified by running the whole round trip
## for real — extractor -> region move -> `write_effect_frames.py` -> re-parse — over
## every flip-bearing region of all 401 `E###.BIN` files: 5,420 of 5,444 member writes
## reproduced the block exactly, which is the evidence dec. 4's `x_left + w - 1` was
## missing. The 24 that failed are one E027 region at the signed byte's extreme, and they
## fail on REPRESENTABILITY, not on the formula.
##
## The bound is per-member, not per-region: the same 136-wide block an upright member
## stores comfortably (its byte is unsigned) is unencodable for a mirrored one. So this
## is asked before release, like the merge announcement beside it, rather than discovered
## as corruption after a write. Pure.
static func region_write_verdict(framesets: Array, members: Array, block: Rect2i) -> Dictionary:
	var blocked: Array = []
	for m in members:
		var fi: int = int(m.get("frameset_index", -1))
		var fj: int = int(m.get("frame_index", -1))
		if fi < 0 or fi >= framesets.size():
			continue
		var fs = framesets[fi]
		var frames: Array = (fs.get("frames", []) if fs is Dictionary else [])
		if fj < 0 or fj >= frames.size() or not (frames[fj] is Dictionary):
			continue
		var uv: Dictionary = frames[fj].get("uv", {})
		if uv.is_empty():
			continue
		var want := block_to_uv(uv, block)
		for pair in [["width", "wide"], ["height", "tall"]]:
			var key: String = pair[0]
			var range_ := encodable_uv_range(int(uv.get(key, 0)))
			var value: int = int(want[key])
			if value >= range_.x and value <= range_.y:
				continue
			blocked.append({"frameset_index": fi, "frame_index": fj, "field": "uv_" + key,
				"value": value, "min": range_.x, "max": range_.y,
				"reason": "frameset %d frame %d cannot store %d %s — its uv_%s byte holds %d..%d"
					% [fi, fj, block.size.x if key == "width" else block.size.y, pair[1], key,
						range_.x, range_.y]})
	var message := ""
	if not blocked.is_empty():
		message = "%d of %d member%s cannot store %dx%d: %s" % [blocked.size(), members.size(),
			"" if members.size() == 1 else "s", block.size.x, block.size.y, blocked[0]["reason"]]
	return {"ok": blocked.is_empty(), "blocked": blocked, "message": message}


## What a region write lowers to (ADR-0099 dec. 9): one `{field_ref, new_raw}` per member
## per CHANGED uv field, in the shape `EffectEditSession.apply_compound` consumes — so a
## whole gesture over 30 frames is ONE undo entry, through the #255 choke point, exactly
## as the existing single-frame drag already is.
##
## The block is computed once by the caller; each member stores it through its OWN signs
## (dec. 4), so a mirrored member stays mirrored. Only changed fields are emitted, so a
## drag that lands where it started is not an undo entry the author has to press through.
## Nothing but `uv_*` is ever written — `palette_id`, `is_8bpp`, the blend fields and all
## eight vertex components stay per-frame (dec. 3), which is what makes a region edit safe
## for the 1,944 groups that deliberately vary scale. Pure.
static func region_edits(framesets: Array, members: Array, block: Rect2i) -> Array:
	var edits: Array = []
	for m in members:
		var fi: int = int(m.get("frameset_index", -1))
		var fj: int = int(m.get("frame_index", -1))
		if fi < 0 or fi >= framesets.size():
			continue
		var fs = framesets[fi]
		var frames: Array = (fs.get("frames", []) if fs is Dictionary else [])
		if fj < 0 or fj >= frames.size() or not (frames[fj] is Dictionary):
			continue
		var uv: Dictionary = frames[fj].get("uv", {})
		if uv.is_empty():
			continue
		var want := block_to_uv(uv, block)
		for pair in [["uv_x", "x"], ["uv_y", "y"], ["uv_width", "width"], ["uv_height", "height"]]:
			if int(want[pair[1]]) == int(uv.get(pair[1], 0)):
				continue
			edits.append({
				"field_ref": {"channel": "frameset", "frameset_index": fi, "frame_index": fj,
					"field": pair[0]},
				"new_raw": int(want[pair[1]]),
			})
	return edits


## Who ELSE would end up in this group if the gesture released on `block` — the
## announcement ADR-0099's Consequences require before release. Blocks frequently share
## an origin (E173 stores one beam at five lengths off `(56,48)`), so a resize lands on a
## neighbouring region's block routinely; the merge is otherwise silent and only visible
## three framesets later. `members` is the region being dragged, excluded from the count.
## Pure.
static func region_merge_preview(framesets: Array, members: Array, block: Rect2i) -> Dictionary:
	var dragged: Dictionary = {}
	for m in members:
		dragged["%d/%d" % [int(m.get("frameset_index", -1)), int(m.get("frame_index", -1))]] = true
	var joining: Array = []
	for m in region_members(framesets, block):
		if not dragged.has("%d/%d" % [int(m["frameset_index"]), int(m["frame_index"])]):
			joining.append(m)
	var message := ""
	if not joining.is_empty():
		message = "lands on region (%d, %d) %dx%d — %d more frame%s will join this group" % [
			block.position.x, block.position.y, block.size.x, block.size.y,
			joining.size(), "" if joining.size() == 1 else "s"]
	return {"merges": not joining.is_empty(), "joining": joining.size(),
		"members": joining, "message": message}


## Map a frame's UV rect (`{x,y,width,height}`, texture-pixel units) into
## canvas-local pixel coordinates within `texture_draw_rect` (the letterboxed
## rect `texture_rect` returned). Pure.
static func uv_to_canvas_rect(uv: Dictionary, texture_size: Vector2, texture_draw_rect: Rect2) -> Rect2:
	if texture_size.x <= 0 or texture_size.y <= 0:
		return Rect2()
	var scale := Vector2(texture_draw_rect.size.x / texture_size.x, texture_draw_rect.size.y / texture_size.y)
	# The BLOCK, not the signed rect: multiplying a negative width through produced a
	# negative-SIZE Rect2, for which `has_point` is false everywhere — so a mirrored
	# frame's box could not be grabbed by its body, only by a corner handle, which led
	# straight into `resize_uv`'s silent unflip (ADR-0099). Every member of a region has
	# the identical block, so there is exactly one rectangle to draw (dec. 8).
	var block := normalised_block(uv)
	var pos := texture_draw_rect.position + Vector2(block.position) * scale
	var sz := Vector2(block.size) * scale
	return Rect2(pos, sz)


## The inverse of `uv_to_canvas_rect`'s position mapping: a canvas-local pixel
## point -> the texture-pixel coordinate it addresses. Pure — the seam #279's
## click/drag hit-testing reuses to convert a mouse position back to a UV value.
static func canvas_point_to_texture_pixel(point: Vector2, texture_size: Vector2, texture_draw_rect: Rect2) -> Vector2:
	if texture_draw_rect.size.x <= 0 or texture_draw_rect.size.y <= 0:
		return Vector2.ZERO
	var rel := point - texture_draw_rect.position
	return Vector2(rel.x * texture_size.x / texture_draw_rect.size.x,
		rel.y * texture_size.y / texture_draw_rect.size.y)


## What a mouse-down at canvas-local `point` grabs (#279): a corner handle
## ("tl"/"tr"/"bl"/"br", checked first so a handle near the edge wins over the
## body), the rect body ("body"), or nothing ("" — the drag never starts).
##
## `handle_size` is the GRAB size (`HANDLE_GRAB`), NOT the drawn one. The docstring here
## used to say the opposite — *"the SAME square `_draw_uv_overlay` draws, so hit-testing
## and the visible affordance never disagree"* — and it was wrong in both halves: this took
## `HANDLE_SIZE` and tested a CIRCLE with it, so a quarter of the drawn square missed. The
## target is now a rect (`corner_grab_rect`) and it is deliberately the larger of the two,
## which is the only relationship that cannot strand a visible pixel.
##
## Pure.
static func hit_test(point: Vector2, uv: Dictionary, texture_size: Vector2,
		texture_draw_rect: Rect2, handle_size: float) -> String:
	var r := uv_to_canvas_rect(uv, texture_size, texture_draw_rect)
	for corner in ["tl", "tr", "bl", "br"]:
		if corner_grab_rect(r, corner, handle_size).has_point(point):
			return corner
	if r.has_point(point):
		return "body"
	return ""


## MOVE (#279): shift the rect's origin by `delta` (TEXTURE-pixel units), size
## unchanged. x/y clamp to >= 0 — uv.x/uv.y are plain unsigned bytes (see
## FramesetChannel's Faithful bound), so a negative position is never
## representable; clamping here keeps the drag honest rather than producing a
## value the writer/Faithful advisory would immediately flag. Pure.
static func move_uv(uv: Dictionary, delta: Vector2) -> Dictionary:
	var out := uv.duplicate()
	out["x"] = maxi(0, roundi(float(uv.get("x", 0)) + delta.x))
	out["y"] = maxi(0, roundi(float(uv.get("y", 0)) + delta.y))
	return out


## RESIZE (#279): drag `corner` to the texture-pixel position `new_point`,
## keeping the OPPOSITE corner fixed (the standard rect-handle convention).
## width/height floor at 1 (a zero/negative-size UV rect is never valid); x/y
## clamp to >= 0 for the same reason `move_uv` does. Pure.
static func resize_uv(uv: Dictionary, corner: String, new_point: Vector2) -> Dictionary:
	# `corner` names a VISUAL corner of the drawn box, which is the block's corner —
	# so the resize happens in block space and the result is written back through this
	# member's own signs (ADR-0099 dec. 4). Normalising through `min`/`max` and storing
	# a positive width, as this did, silently UNFLIPPED any of the 2,628 mirrored corpus
	# frames on its author's very first corner drag.
	var block := normalised_block(uv)
	var x0 := float(block.position.x)
	var y0 := float(block.position.y)
	var x1 := x0 + float(block.size.x)
	var y1 := y0 + float(block.size.y)
	match corner:
		"tl": x0 = new_point.x; y0 = new_point.y
		"tr": x1 = new_point.x; y0 = new_point.y
		"bl": x0 = new_point.x; y1 = new_point.y
		"br": x1 = new_point.x; y1 = new_point.y
	var left := maxf(0.0, minf(x0, x1))
	var top := maxf(0.0, minf(y0, y1))
	var right := maxf(x0, x1)
	var bottom := maxf(y0, y1)
	return block_to_uv(uv, Rect2i(roundi(left), roundi(top),
		maxi(1, roundi(right - left)), maxi(1, roundi(bottom - top))))
