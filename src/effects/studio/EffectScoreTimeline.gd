extends Control
## The Effect Studio **score timeline** — a pure-GDScript custom Control (web/WASM
## safe, no GDExtension) that draws a score (from EffectScoreModel) as multi-lane
## spans grouped by phase section, a top ruler, and one playhead, and turns clicks
## into transport intents. Thin glue over two testable cores: EffectScoreModel
## (the data) and TimelineAxis (the frame↔pixel transform). See CONTEXT.md
## "Effect Studio" / "Score" / "Playhead / scrub".
##
## Interaction (CONTEXT: "seek here vs inspect this must never fight over a click"):
##   • ruler drag/click            → seek_requested(frame)   (the seek surface)
##   • empty lane area drag/click  → seek_requested(frame)
##   • span click                  → span_selected(span_id)  (inspect, not seek)
##   • mouse wheel                 → cursor-anchored zoom
##   • middle / shift+left drag    → horizontal pan
##
## Rendering is ONE _draw pass that also populates hit-test rects; _gui_input tests
## those rects. Layout is split into rebuild_layout() (pure, size-driven) so the
## routing is unit-testable without a paint. No `class_name` (ADR-0004).

const TimelineAxis = preload("res://src/effects/studio/TimelineAxis.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const SoundGhostProjector = preload("res://src/effects/studio/SoundGhostProjector.gd")

signal seek_requested(frame: int)
signal span_selected(span_id: String)
## Right-click on a span — the host opens a context menu (e.g. "Copy keyframe
## address") for the keyframe under the cursor. Carries only the stable span id;
## the host owns the menu + the effect identity the address needs.
signal span_context_requested(span_id: String, frame: int)
## Right-click on a lane row's EMPTY space (no span hit) — there is no span to address,
## so this carries the LANE id (the host resolves phase + channel from it) and the
## score-absolute frame under the cursor (where the event would land). The gap
## counterpart to span_context_requested — the entry point for the Add-in-a-gap verbs:
## sound's "Add event here" (the gap gesture on an instant-marker lane, ADR-0085) and
## the particle / spacer adds (ADR-0089, ADR-0087 decs. 23-28). The host decides
## which lanes honour it.
signal lane_context_requested(lane_id: String, frame: int)
## The frame↔pixel transform changed (zoom or pan). The detached frames bar shares
## this axis and connects here to redraw in lock-step with the lanes.
signal axis_changed
## The playhead moved. Same purpose — keeps the detached frames bar's marker synced.
signal playhead_changed
## A lane's solo/mute state changed. The page recomputes the preview's audibility
## (EffectScoreModel.resolve_audibility) and forwards it to the host. Carries no
## payload — the listener reads muted_lanes()/soloed_lanes() off this control.
signal lane_audibility_changed
## An author dragged a sound trigger's ANCHOR handle (ADR-0085): the audible HIT now
## lands `offset` frames into the sound. Authoring-only intent — the host applies it
## to the live keyframe; the fire marker and on-disk bytes never move. Carries the
## trigger's span id and the clamped offset.
signal anchor_offset_changed(span_id: String, offset: int)
## An author dragged a sound trigger's INSTANT marker to MOVE it (ADR-0085 fire-drag).
## Carries the trigger's span id and the ABSOLUTE target fire frame under the cursor
## (snapped, unclamped). Authoring intent only — the host turns it into the stay-local
## gap edit (SoundGapMath) and reprojects the marker; the timeline never mutates the
## score itself. The FIRST trigger is pinned (no prior gap to trade) and emits nothing.
signal fire_frame_changed(span_id: String, new_fire_frame: int)
## Fire-drag lifecycle (ADR-0085 baseline-cumulative): emitted when a trigger marker is
## GRABBED (arm) and RELEASED (clear), so the host can snapshot a fixed drag-start
## baseline and feed cumulative deltas — the byte-exact reversibility guarantee.
signal fire_drag_started(span_id: String)
signal fire_drag_ended(span_id: String)
## An author dragged a camera sub-channel span's RIGHT EDGE to resize it (ADR-0086
## boundary-drag amendment). Carries the span id and the ABSOLUTE target frame under the
## cursor (snapped, UNCLAMPED). Authoring intent only — the host converts to phase-local,
## clamps to (prev_end, next_end), applies the single `end_frame` edit, and reprojects; the
## timeline never mutates the score. Because a span's start is derived from the previous
## event's end_frame, one edit moves both adjacent tiles (a stay-local boundary trade).
signal edge_dragged(span_id: String, frame: int)
## Boundary-drag lifecycle: emitted when a span's edge grip is GRABBED (arm) and RELEASED
## (clear), so the host can bracket the gesture as ONE undo (a drag-scoped same-field coalesce).
signal edge_drag_started(span_id: String)
signal edge_drag_ended(span_id: String)
## Body-drag (ADR-0089 particle_timeline Move): dragging a particle span's BODY slides the whole
## span. `delta` is the snapped frame offset from the grab point; the host clamps + applies both
## boundary shifts as one gesture. Grab/release bracket it as ONE undo.
signal span_body_drag_started(span_id: String)
signal span_body_dragged(span_id: String, delta: int)
signal span_body_drag_ended(span_id: String)

# The ruler now lives in a separate, floating EffectFramesBar (so the resizable
# inspector can't shove it around); the lanes here start at y=0. GUTTER_W is still
# owned here — the frames bar reads it off the bound timeline so the two never drift.
const GUTTER_W: float = 124.0
# Floor for the content-driven height so a sparse effect (a track or two) still
# gets a usable band; a dense one grows to fit all its tracks.
const MIN_TIMELINE_H: float = 160.0
const CONTENT_PAD_Y: float = 6.0
# Default zoom on load: show the first N frames across the frame area (most effect
# action is up front), rather than fitting the whole — often mostly padding — span.
const DEFAULT_VIEW_FRAMES: float = 70.0
const PAD_X: float = 8.0
const SECTION_H: float = 20.0
const LANE_H: float = 24.0
const LANE_GAP: float = 2.0
# The global "Time scale" pacing lane (#270, ADR-0093): a taller bottom strip carrying the two
# slowness bands, pinned below the phase lanes. Taller than a normal lane so the (value-2)/8
# swell is legible.
const PACING_LANE_H: float = 34.0
# Per-lane Solo / Mute buttons, right-justified inside the gutter. S (solo) then M
# (mute), M outermost. The gutter label is narrowed to the left of them so text and
# buttons never overlap.
const BTN_SIZE: float = 15.0
const BTN_PAD: float = 3.0
# Compiled-lane keyframe markers: a small diamond AT the keyframe's frame (the storage
# view is points, not intervals — a keyframe is a target reached at one frame). Coincident
# markers (a split) fan horizontally by MARKER_FAN so both stay individually clickable.
const MARKER_HALF: float = 5.0
const MARKER_FAN: float = 7.0
# A sound trigger draws as a thin instant marker, but its CLICK TARGET spans its
# whole visible footprint (marker + ghost bar) so the bar you see is the bar you can
# click. A ghost-less trigger still gets this minimum grabbable width.
const SOUND_HIT_MIN_W: float = 8.0
# The anchor handle on a ghost bar (ADR-0085): a small grabbable glyph centered on the
# HIT frame. Its grab target is this wide so a per-frame handle is still easy to catch.
const ANCHOR_HANDLE_W: float = 9.0
# The fire grab on a sound trigger's instant marker (ADR-0085 fire-drag): a grab target
# centered on the fire frame, wide enough to catch the thin marker tick. Checked before
# the anchor + footprint-select so the marker moves the trigger.
const FIRE_HANDLE_W: float = 9.0
# Loose selection: when a lane-row click misses every exact rect, the nearest marker
# within this many px still SELECTS (never drags) instead of scrubbing the playhead.
# Beyond it the lane row keeps its seek surface.
const LOOSE_SELECT_TOL: float = 14.0
# The edge grip on a camera sub-channel span's RIGHT edge (ADR-0086 boundary-drag): a grab
# target centered on the span's end_frame x, wide enough to catch the boundary. Checked
# before the whole-tile select so grabbing the edge resizes rather than selects.
const EDGE_HANDLE_W: float = 9.0
## The pixels of BODY a boundary grip must leave behind in each span it reaches into. The grip
## is centred on the boundary, so it eats EDGE_HANDLE_W/2 from the span on either side; a span
## shorter than the whole band (a 1-frame event at anything but a deep zoom) would be covered
## edge to edge by its two flanking grips, and its MOVE would stop being REACHABLE — `plan_move`
## still says yes, but no press can ever start one. So each half yields until this much body
## survives, and yields entirely on a span too narrow to share.
##
## Move wins the contested span because it is drag-ONLY, while the boundary a grip writes is
## also typeable in the inspector (camera's `end_frame` row, the colour lanes' Duration row): a
## grip that yields costs a zoom-in, a body that yields costs the verb. Unlike the ADR-0086
## reversal amendment's identity-based suppression — which made ~1945 colour keyframes
## permanently unreachable — this one is a function of ZOOM alone, so zooming in always brings
## the grip back.
const BODY_MIN_W: float = 5.0

# Palette (dark authoring surface).
const COL_BG := Color(0.09, 0.10, 0.13)
const COL_GUTTER := Color(0.12, 0.13, 0.17)
const COL_SECTION := Color(0.18, 0.20, 0.27)
const COL_LANE_A := Color(0.11, 0.12, 0.16)
const COL_LANE_B := Color(0.13, 0.14, 0.18)
const COL_GRID := Color(1, 1, 1, 0.05)
const COL_TEXT := Color(0.78, 0.82, 0.90)
const COL_TEXT_DIM := Color(0.55, 0.60, 0.70)
const COL_PLAYHEAD := Color(1.0, 0.85, 0.25)
const COL_SELECT := Color(1.0, 1.0, 1.0)
# The DERIVED effect end (EffectEndModel) — the frame the real engine reaps the
# cast (particles gone), which is NOT the last authored keyframe. Drawn as a hard
# red stop line; the authored tail past it is dimmed (it never plays in-game).
const COL_END := Color(0.95, 0.38, 0.42)
# Phase-boundary line + label (#271 follow-up): a cool blue, distinct from the yellow playhead
# and red end marker, so "where does for-each / phase 2 begin" reads at a glance across lanes.
const COL_PHASE_BOUNDARY := Color(0.50, 0.72, 0.98, 0.65)
# Loop region (ADR-0090): a low-alpha cyan band over the looped frames + a brighter rule
# on each boundary. Alpha kept low so spans under the band stay readable.
# The pacing lane (#270): a warm slowness fill (swells where time slows) under an always-present
# outline of the curve top, greyed when the curve's enable bit is off (drawn but inert), over a
# slightly darker strip background. The outline runs along the baseline through normal-speed (2)
# stretches so the band shows *something* everywhere (ADR-0093 revision — no collapsing humps).
const COL_PACING_STRIP := Color(0.10, 0.11, 0.15)
const COL_PACING_FILL := Color(1.0, 0.62, 0.30, 0.55)
const COL_PACING_FILL_OFF := Color(0.55, 0.58, 0.66, 0.30)
const COL_PACING_LINE := Color(1.0, 0.70, 0.36, 0.95)
const COL_PACING_LINE_OFF := Color(0.62, 0.66, 0.74, 0.75)
const COL_LOOP_BAND := Color(0.30, 0.75, 0.95, 0.10)
const COL_LOOP_EDGE := Color(0.40, 0.85, 1.0, 0.85)
# Translucent bg wash painted over the portion of a span that lies past the end.
const COL_PAST_END := Color(COL_BG.r, COL_BG.g, COL_BG.b, 0.62)
# Faint stripe ink for the disabled hatch (ADR-0087 dec. 26) — light enough to
# read as texture over the dim slate fill, never as a colour the tween produces.
const COL_SPACER_STRIPE := Color(0.72, 0.76, 0.84, 0.28)
# Solo/Mute button ink. Idle buttons are dim outlines; an active mute glows amber, an
# active solo glows green. A silenced (muted, or un-soloed while a solo is active)
# lane gets its gutter label dimmed so the isolation reads at a glance.
# Ghost-bar wash alphas (ADR-0085 four-pass render). Faint fills are all the same alpha
# so overlapping washes composite order-independently; the selected ghost gets a second
# fill on top (denser) and a brighter hairline top edge; unselected ghosts a dim edge.
const GHOST_FILL_A: float = 0.13
const GHOST_PIP_A: float = 0.75   # TIER-3 note-onset pips inside a ghost bar
const GHOST_SELECT_A: float = 0.18
const GHOST_EDGE_A: float = 0.35
const GHOST_EDGE_SEL_A: float = 0.85
const COL_BTN_IDLE := Color(0.30, 0.33, 0.40)
const COL_MUTE_ON := Color(0.95, 0.55, 0.25)
const COL_SOLO_ON := Color(0.45, 0.85, 0.45)
const COL_TEXT_SILENCED := Color(0.40, 0.43, 0.50)

var axis = TimelineAxis.new()
var snap_step: int = 1

var _score: Dictionary = {}
var _playhead: int = 0
var _selected_id: String = ""
# Derived end frame (0 = unknown → no marker, no dimming). Set by the host once
# per effect load via set_end_frame(); the host computes it with EffectEndModel.
var _end_frame: int = 0
# Loop region (ADR-0090): the inclusive `{start, end}` span the transport loops, or `{}`
# for none. Drawn as a full-height translucent band across the lanes (pure view off the
# shared axis) so the looped range is visible against the playhead. Host-owned; set here.
var _loop_region: Dictionary = {}

# Hit-test rects, rebuilt by rebuild_layout(): spans first (they win over the
# lane-area seek zone underneath).
var _span_rects: Array = []   # [{ "rect": Rect2, "span": Dictionary }]
var _marker_rects: Array = [] # [{ "center": Vector2, "rect": Rect2 (hit box), "span": Dictionary }]
# One coincidence tie per FANNED marker group (2+ markers on one frame), anchored at the
# TRUE frame x so a split reads as one coincident group, not markers at nearby frames (#285).
var _marker_ties: Array = []  # [{ "center_x": float, "left_x": float, "right_x": float, "y": float }]
# Read-only ghost bars for sound triggers (ADR-0085): the projected real length of
# a trigger's sound, drawn behind the instant marker. NOT hit-tested — a ghost is a
# projection, never an editable target. [{ "span_id", "rect", "color" }]
var _ghost_rects: Array = []
# Draggable anchor handles on the ghost bars (ADR-0085): the HIT position within a
# sound's real length. Hit-tested BEFORE the footprint select, so grabbing one drags
# the anchor rather than selecting the trigger. Present only where a ghost exists.
# [{ "span_id", "rect", "start", "ghost", "color" }]
var _anchor_rects: Array = []
# Fire grab handles on sound instant markers (ADR-0085 fire-drag): the draggable
# "move this trigger" target. Present for every trigger PAST the first (the first is
# pinned). Hit-tested BEFORE the anchor + footprint select. [{ "span_id", "rect", "start" }]
var _fire_rects: Array = []
# Edge grips on camera sub-channel spans (ADR-0086 boundary-drag): the draggable "resize
# this span's end_frame" target, centered on each span's right edge. Hit-tested BEFORE the
# whole-tile select so grabbing the boundary resizes rather than selects. [{ "span_id", "rect" }]
var _edge_rects: Array = []
var _lane_rows: Array = []    # [{ "lane": Dictionary, "rect": Rect2 }] (visual only)
var _section_rows: Array = [] # [{ "phase", "label", "rect", "band_start/end", "collapsed", "lane_count" }]
# Per-lane gutter Solo/Mute button hit-rects: [{ "lane_id", "kind": "solo"|"mute", "rect" }].
var _lane_button_rects: Array = []
var _content_h: float = 0.0

# The global "Time scale" pacing lane (#270, ADR-0093): the bottom strip rect + the two band
# hit-rects laid out over their frame ranges. Empty when the effect carries no time_scale.
# [{ "id", "field", "rect", "enabled", "pacing": Array }]. Laid out in rebuild_layout.
var _pacing_lane_rect: Rect2 = Rect2()
var _pacing_rects: Array = []

# Set-style lane audibility state (key = lane id). A muted lane is silenced; when any
# lane is soloed, every NON-soloed lane is silenced too (DAW rule, resolved for the
# preview by EffectScoreModel.resolve_audibility). Reset on load_score (per document).
var _muted: Dictionary = {}
var _soloed: Dictionary = {}

# Collapsed phase sections (phase name -> true). A collapsed section keeps its
# header (clickable to expand) but drops its lanes from layout — the ~45-lane
# all-channels console stays navigable. See load_score for the reset.
var _collapsed: Dictionary = {}

var _panning: bool = false
var _pan_last_x: float = 0.0
var _scrubbing: bool = false
# The span id whose anchor handle is being dragged (empty = none). Armed on a press
# that hit-tests as "anchor"; cleared on release.
var _anchor_drag_id: String = ""
# The span id whose instant marker is being fire-dragged (empty = none). Armed on a
# press that hit-tests as "fire"; cleared on release.
var _fire_drag_id: String = ""
# Fire-drag is RELATIVE to the grab, not the absolute frame under the cursor: the press
# records the grab's local x and the marker's frame, and motion emits
# `grab_frame + round((x - grab_x) / ppf)`. This stops a slightly-off-center grab of the
# ~9px handle from leaping the trigger to the cursor's rounded frame, and — crucially at a
# coarse zoom (ppf < 1, whole frames between pixels) — makes dragging back to the grab point
# return to the exact start frame instead of skipping it. Set on the "fire" press.
var _fire_grab_x: float = 0.0
var _fire_grab_frame: int = 0
# The camera span id whose right edge is being boundary-dragged (empty = none). Armed on a
# press that hit-tests as "edge"; cleared on release.
var _edge_drag_id: String = ""
# The particle span whose BODY is being dragged (Move), and the frame the grab started at
# (deltas are measured from it). Empty = none.
var _body_drag_id: String = ""
var _body_drag_start_frame: int = 0
# The camera span id whose edge grip the cursor is hovering (empty = none). Drives the hover
# grip highlight; updated on plain motion and only queue_redraw'd on a transition (not per pixel).
var _hover_edge_id: String = ""
# ADR-0089 Drag preview, GEOMETRY-ONLY arm: the span a live Move is showing at an OFFSET, and
# how many frames left/right. The score behind it is untouched — the colour kinds plan every
# motion and splice once on release — so the drag has no reprojection to ride and the offset is
# the only thing that moves. Empty id = no preview; the offset is the planner's clamped delta,
# so what the author sees is always where release will actually land.
var _move_preview_id: String = ""
var _move_preview_dx: int = 0
# Set on load_score; the load-time 0..DEFAULT_VIEW_FRAMES zoom is applied on the
# first _draw with a real width (the control is unsized during _ready's load).
var _needs_default_view: bool = false


func _ready() -> void:
	focus_mode = Control.FOCUS_CLICK
	mouse_filter = Control.MOUSE_FILTER_STOP


## Drop the edge-grip hover highlight when the cursor leaves the timeline, so it doesn't
## linger on a boundary the cursor is no longer over.
func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover_edge_id != "":
		_hover_edge_id = ""
		queue_redraw()


func load_score(score: Dictionary) -> void:
	"""Load a FRESH document (from EffectScoreModel.build). Fits the axis to the effect
	and resets transport/selection/audibility — a new effect starts clean. For a
	structural re-render of the SAME document (e.g. a sound Gap edit shifts later markers,
	or a Blend↔Gradient kind flip) use reproject_score(), which preserves the parked
	playhead, selection, solo/mute, end-frame, and zoom."""
	_score = score
	_selected_id = ""
	_playhead = 0
	_end_frame = 0   # cleared until the host recomputes it for this effect (set_end_frame)
	# A fresh document starts fully audible; lane ids differ per effect, so the old
	# solo/mute selection is meaningless here. The page re-resolves audibility after load.
	_muted = {}
	_soloed = {}
	axis.configure(GUTTER_W + PAD_X, TimelineAxis.DEFAULT_PPF)
	axis.scroll_x = 0.0
	_needs_default_view = true   # resolved on first _draw (needs a real width)
	# Size the control to its track count so the panel below hugs the last track
	# (the lane layout's y-extent is width-independent, so this is stable here).
	rebuild_layout()
	custom_minimum_size.y = maxf(MIN_TIMELINE_H, _content_h + CONTENT_PAD_Y)
	queue_redraw()


func reproject_score(score: Dictionary) -> void:
	"""Re-render the SAME document after a structural / layout edit (e.g. a sound Gap edit
	shifts trigger i+1 and every later marker on that channel; a camera keyframe end_frame
	nudge moves a span boundary / compiled marker; a Blend↔Gradient kind flip reshapes the
	field set + lane). Unlike load_score, this PRESERVES the parked playhead,
	span selection, solo/mute, end-frame, and zoom/pan — the author's place is kept. Only
	the score + layout are rebuilt (the content height may change). The selection +
	solo/mute are revalidated against the reshaped score: any that no longer exist are
	dropped (see _revalidate_preserved) so nothing points at a ghost."""
	_score = score
	_revalidate_preserved()
	rebuild_layout()
	custom_minimum_size.y = maxf(MIN_TIMELINE_H, _content_h + CONTENT_PAD_Y)
	queue_redraw()


## Show `span_id` `dx_frames` from where the score puts it, without reprojecting anything
## (ADR-0089 Drag preview). This is the whole per-motion cost of a structure-free colour Move:
## one repaint. `dx_frames` is the PLANNER'S clamped delta, never the cursor's — a preview that
## drew the cursor's wish would promise a landing the release refuses.
##
## Redraws only on a real change, so a cursor wandering inside one frame's worth of pixels (or
## pinned against the clamp, which is most of an over-dragged gesture) costs nothing at all.
func set_move_preview(span_id: String, dx_frames: int) -> void:
	if span_id == _move_preview_id and dx_frames == _move_preview_dx:
		return
	_move_preview_id = span_id
	_move_preview_dx = dx_frames
	queue_redraw()


## Drop the offset (release, or a gesture that ends without one). The caller reprojects the
## committed score itself — clearing the preview is not a commit and paints nothing new.
func clear_move_preview() -> void:
	set_move_preview("", 0)


## Where the preview currently stands, as `{id, dx}`. Test seam: the offset is invisible to
## `_score` by construction, so a guard on the drag has nothing else to read.
func move_preview_state() -> Dictionary:
	return {"id": _move_preview_id, "dx": _move_preview_dx}


## Drop any preserved selection / solo / mute that the reshaped score no longer contains.
## Scans the score lanes directly (not the laid-out rects) so a collapsed/scrolled section
## doesn't read as "gone". A sound Gap edit / Blend↔Gradient kind flip keeps ids stable
## (lane#index), so nothing is dropped there; this only bites a structural edit that removes
## a keyframe / sub-channel event (sound add/delete, camera add/delete #286) or a whole lane.
func _revalidate_preserved() -> void:
	var lane_ids := {}
	var span_ids := {}
	for lane in _score.get("lanes", []):
		lane_ids[lane["id"]] = true
		for span in lane["spans"]:
			span_ids[span["id"]] = true
	if _selected_id != "" and not span_ids.has(_selected_id):
		_selected_id = ""
	for lane_id in _muted.keys():
		if not lane_ids.has(lane_id):
			_muted.erase(lane_id)
	for lane_id in _soloed.keys():
		if not lane_ids.has(lane_id):
			_soloed.erase(lane_id)


func set_playhead(frame: int) -> void:
	_playhead = maxi(0, frame)
	playhead_changed.emit()
	queue_redraw()


## The derived runtime end frame (EffectEndModel.derived_end_frame). 0 clears the
## marker. Drives both the red end-stop line and the dimming of any span tail that
## extends past it. The frames bar reads it back off the bound timeline.
func set_end_frame(frame: int) -> void:
	_end_frame = maxi(0, frame)
	queue_redraw()


func get_end_frame() -> int:
	return _end_frame


## Adopt the loop region `{start, end}` (or `{}` for none) and redraw the band (ADR-0090).
func set_loop_region(region: Dictionary) -> void:
	_loop_region = region if region != null else {}
	queue_redraw()


## The full-height band rect for the current loop region, in local coordinates, aligned to
## the shared axis. Empty `Rect2()` when no region is set. Pure geometry (drawing clamps to
## the gutter separately) — the guard asserts alignment against the axis.
func loop_region_rect() -> Rect2:
	if not _loop_region.has("start") or not _loop_region.has("end"):
		return Rect2()
	var x0: float = axis.frame_to_x(float(_loop_region["start"]))
	var x1: float = axis.frame_to_x(float(_loop_region["end"]))
	return Rect2(x0, 0.0, x1 - x0, size.y)


## Cursor-anchored zoom, shared by this control's wheel handler AND the detached
## frames bar. Mutates the shared axis, redraws, and notifies via axis_changed.
func zoom_at(factor: float, cursor_x: float) -> void:
	axis.zoom_at(factor, cursor_x)
	axis_changed.emit()
	queue_redraw()


## Horizontal pan by a pixel delta (positive dx = drag right = scroll left).
## Shared with the frames bar; frame 0 is free to leave the left edge (no clamp).
func pan_by(dx: float) -> void:
	axis.scroll_x -= dx
	axis_changed.emit()
	queue_redraw()


func get_playhead() -> int:
	return _playhead


func select_span(span_id: String) -> void:
	_selected_id = span_id
	queue_redraw()


func selected_span_id() -> String:
	return _selected_id


## The hit-rect of the currently-selected span (y in timeline-content space), or an empty
## Rect2 if nothing is selected or the selection has no drawn rect. Mirrors ghost_rect_for so
## the page can scroll the selection into view WITHOUT reaching into the private _span_rects.
func selected_span_rect() -> Rect2:
	if _selected_id == "":
		return Rect2()
	for hit in _span_rects:
		if String(hit["span"]["id"]) == _selected_id:
			return hit["rect"]
	return Rect2()


## Is this span an INVISIBLE SPACER right now (ADR-0087 decs. 23-28 for colour,
## ADR-0086 dec. 15 for camera)? A spacer is the lane's empty space — it renders as NOTHING
## and is not selectable — but ONLY when it is verdict-inert (`fields.spacer`: colour's
## disable-equivalence fold, camera's local `MAP`+zero test) and not explicitly disabled.
## Two carve-outs keep it on screen:
##   • a DELIBERATELY-DISABLED event (`enabled` false) is "muted, not gone" — drawn, hatched,
##     selectable so its Enable knob is reachable (decision 4);
##   • the SELECTED span always draws, so a just-added / just-enabled-not-yet-coloured stub
##     never blinks out mid-edit (decision 5).
## The single source of truth for EVERY consumer of "is this drawn?": the painter (skip), the
## exact + loose hit-tests (unselectable → clicks fall through to empty-space seek / gap
## context), and `edge_grip_identity` (whose boundary a grip SPEAKS FOR — every tiled
## boundary has one). It is NOT a list of three — the rule is that anything asking "is this on screen?"
## asks HERE, and a new consumer joins rather than re-deriving the test. A span with no
## `spacer` field is never hidden. Pure so the decision is guarded without a paint.
##
## CAMERA (ADR-0086 dec. 15) joins on the same flag, which is why `enabled`
## defaults to **true**: the rule is "hidden unless EXPLICITLY disabled". Camera has no enable
## bit and no Solo/Mute, so a camera spacer carries no `enabled` field and hides; the colour
## lanes stamp `enabled` on every span, so their "muted, not gone" carve-out is untouched.
static func is_hidden_spacer(span: Dictionary, selected_id: String) -> bool:
	if String(span.get("id", "")) == selected_id:
		return false
	var f: Dictionary = span.get("fields", {})
	return bool(f.get("spacer", false)) and bool(f.get("enabled", true))


## Which lane KINDS arm a Move body-drag (ADR-0101 decision 3). Sound is instant-based (its
## gesture is the fire drag), `camera_compiled` is the read-only storage view, and the pacing
## strip is not a lane — none of them slides. The kind is the span id's own prefix, the same
## identity `_body_drag_id` carries, so `camera_compiled:…` does NOT match `camera`.
const MOVABLE_KINDS := ["particle", "camera", "palette", "screen"]


## Does a body press on this span arm a Move? Pure so the arming rule is guarded without a
## paint — the page re-gates on the resolved span's `kind` before it touches the session.
static func is_movable_span(span_id: String) -> bool:
	return span_id.get_slice(":", 0) in MOVABLE_KINDS


## Who does this span's right-edge grip belong to ON SCREEN? (ADR-0086 decs. 22-23 —
## ADR-0087 shares the seam, so colour lanes obey it too.)
##
## EVERY tiled boundary gets a grip. The grip's WRITE owner is always `span`: its `end_frame` /
## `time_value` IS the boundary — one stored number — and that never changes. What this decides
## is the grip's SELECT IDENTITY: who a drag selects, roots the inspector on, and draws the
## handle for. `""` means "leave the selection alone". Three cases:
##
##   • `span` is DRAWN → identity is itself. The classic right-edge grip, unchanged, whatever
##     follows it (dragging right into a hold is plainly resizing the tile you can see).
##   • `span` is a HIDDEN SPACER with a DRAWN successor → the boundary is that successor's
##     visible LEFT edge (`MAP`-delta amendment decision 4, stated on purpose), so the
##     identity is the successor. The drag still writes the hold's end; the author is dragging
##     the drawn span's start, and that is what must be selected. Rooting on the hold instead
##     UN-HIDES it — `is_hidden_spacer` never hides the selection — which was the reported
##     "drag the left resize handle and it creates a spacer and selects it". Nothing was
##     created; the hold was always there, and the force-select painted it.
##   • `span` is a HIDDEN SPACER with no drawn successor — the successor is ALSO hidden (a
##     BLIND boundary), or there is none at all (the LANE TAIL) → the grip exists with NO
##     identity. Drag it; the selection stays where the author put it, and the hold never
##     reveals. ADR-0086 already gives the last grip the end marker as its moving party rather
##     than a sibling; blind now joins it rather than being suppressed.
##
## The blind case USED to return no grip, on the argument that the keyframe kept a read-only
## home on the compiled lane. That lane is CAMERA-ONLY (`EffectScoreModel` emits no
## `palette_compiled` / `screen_compiled`), and a hidden colour hold is unpaintable and
## unselectable — so suppression made it unreachable outright. Measured across all 401
## effects it cost camera 56 boundaries (1.1%) and colour 1945 (12-17%). Reach wins; the
## reported bug was the force-select, never the grip.
##
## `next_span` empty = the lane tail. Pure and static so the rule is guarded without a paint.
static func edge_grip_identity(span: Dictionary, next_span: Dictionary,
		selected_id: String) -> String:
	if not is_hidden_spacer(span, selected_id):
		return String(span.get("id", ""))
	if next_span.is_empty() or is_hidden_spacer(next_span, selected_id):
		return ""                                   # lane tail, or blind — no selection moves
	return String(next_span.get("id", ""))


## Is this edge grip DRAWN right now? Grips are not peppered onto every tiled boundary (that
## would clutter a fully-tiled lane) — only the hovered one, plus the ones BELONGING to the
## selection. "Belonging" is the select identity, so a selected span lights both its own right
## grip and the left grip a hidden hold in front of it owns: the author's "left resize handle"
## made visible without a second grip ever existing. An identity-less grip (a lane-tail hold)
## is hover-only — matching "" against an empty selection would light up every tail the moment
## nothing is selected. Pure so the painter's rule is guarded without a paint.
static func edge_grip_drawn(entry: Dictionary, selected_id: String, hover_id: String) -> bool:
	if hover_id != "" and String(entry.get("span_id", "")) == hover_id:
		return true
	var ident := String(entry.get("select_id", ""))
	return ident != "" and ident == selected_id


## The next TILE after index `i` in a lane's span list — the span whose left edge IS span i's
## right edge. Skips point markers (laid out and fanned separately; they own no stretch of the
## timeline, so they can never be a boundary's other side). Empty = span i is the lane tail.
## How far a boundary grip may reach into a tile `tile_w` pixels wide: the full half-band on a
## roomy span, tapering to nothing once the span cannot spare BODY_MIN_W. The taper (rather
## than a cliff) keeps the grip usable right down to the span that can no longer host it.
static func _grip_reach(tile_w: float) -> float:
	return clampf(tile_w - BODY_MIN_W, 0.0, EDGE_HANDLE_W * 0.5)


## A tile's pixel width on the current axis — the same `maxf(2.0, …)` floor the hit rect uses,
## so `_grip_reach` judges the span the author can actually click.
func _tile_w(span: Dictionary) -> float:
	return maxf(2.0, axis.frame_to_x(float(span.get("end", 0)))
		- axis.frame_to_x(float(span.get("start", 0))))


static func _next_tile(spans: Array, i: int) -> Dictionary:
	for j in range(i + 1, spans.size()):
		if not spans[j].get("marker", false):
			return spans[j]
	return {}


## Apply the load-time zoom: fit exactly DEFAULT_VIEW_FRAMES across the frame area,
## frame 0 at the left. Deferred to _draw because the control has no width during
## _ready's synchronous effect load; retried each draw until the width is real.
func _resolve_default_view() -> void:
	if not _needs_default_view:
		return
	var frame_w := size.x - GUTTER_W - PAD_X * 2.0
	if frame_w <= 0.0:
		return   # unsized yet — try again next draw
	axis.pixels_per_frame = clampf(
		frame_w / DEFAULT_VIEW_FRAMES, TimelineAxis.MIN_PPF, TimelineAxis.MAX_PPF)
	axis.scroll_x = 0.0
	_needs_default_view = false
	# Resolved lazily on first draw (needs a real width) — notify the frames bar so
	# its ticks pick up the same load-time scale instead of the stale default.
	axis_changed.emit()


# --- Layout (pure, size-driven — the hit-test source of truth) ------------

## Recompute lane rows and span hit-rects for the current size + axis + score.
## Called by _draw before painting AND directly by tests. No side effects beyond
## the cached rect arrays.
func rebuild_layout() -> void:
	_span_rects.clear()
	_marker_rects.clear()
	_marker_ties.clear()
	_ghost_rects.clear()
	_anchor_rects.clear()
	_fire_rects.clear()
	_edge_rects.clear()
	_lane_rows.clear()
	_section_rows.clear()
	_lane_button_rects.clear()
	_pacing_rects.clear()
	_pacing_lane_rect = Rect2()
	var y := 0.0
	# Group lanes by phase section, in the score's phase order. Each section gets a
	# clickable header row; a collapsed section keeps the header but drops its lanes.
	for section in _score.get("phases", []):
		var section_lanes := _lanes_in_phase(section["name"])
		if section_lanes.is_empty():
			continue
		var collapsed: bool = _collapsed.get(section["name"], false)
		_section_rows.append({
			"phase": section["name"],
			"label": section["label"],
			"rect": Rect2(0.0, y, size.x, SECTION_H),
			"band_start": section["start"],
			"band_end": section["end"],
			"collapsed": collapsed,
			"lane_count": section_lanes.size(),
		})
		y += SECTION_H
		if collapsed:
			continue
		for lane in section_lanes:
			var lane_rect := Rect2(0.0, y, size.x, LANE_H)
			_lane_rows.append({"lane": lane, "rect": lane_rect})
			# Camera lanes are display-only (no S/M) — see EffectScoreModel.has_mute_controls.
			if Model.has_mute_controls(lane["kind"]):
				_append_lane_buttons(lane["id"], y)
			# Indexed, not for-each: the edge-grip rule needs each span's SUCCESSOR (a hidden
			# hold hands its grip to the next drawn tile — see edge_grip_identity).
			var lane_spans: Array = lane["spans"]
			for si in range(lane_spans.size()):
				var span: Dictionary = lane_spans[si]
				if span.get("marker", false):
					continue   # point markers are laid out (and fanned) separately below
				var x0 := axis.frame_to_x(float(span["start"]))
				var x1 := axis.frame_to_x(float(span["end"]))
				var is_sound: bool = span.get("kind", "") == "sound"
				var ghost_frames := int(span.get("ghost_frames", 0))
				# A sound trigger's read-only ghost bar: its projected real length, from
				# the instant rightward. Laid out here so paint and the pure layout agree.
				var ghost_w := 0.0
				if is_sound and ghost_frames > 0:
					ghost_w = maxf(0.0,
						axis.frame_to_x(float(span["start"]) + float(ghost_frames)) - x0)
					_ghost_rects.append({
						"span_id": span["id"],
						"rect": Rect2(x0, y + 2.0, ghost_w, LANE_H - 4.0),
						"color": span["color"],
						# ADR-0085 climax cue: the sound's 0..1 energy envelope, painted
						# as a filled swell inside the ghost bar (empty → no curve).
						"energy": span.get("energy", PackedFloat32Array()),
						# ADR-0085 TIER-3 ghost pips: the pair's unrolled note-onset
						# frames (fire-relative), drawn as read-only ticks — NEVER a
						# click target (no hit rect is ever appended for them).
						"pips": span.get("pips", []),
						"start": int(span["start"]),
					})
					# The anchor handle: a grabbable glyph on the ghost bar at the HIT
					# frame (fire + anchor_offset), clamped into the ghost length. Only
					# where a ghost exists — there's no length to place it on otherwise.
					var anchor_off := int(span.get("anchor_offset", 0))
					var hit_frame := SoundGhostProjector.anchor_hit_frame(
						int(span["start"]), anchor_off, ghost_frames)
					var hx := axis.frame_to_x(float(hit_frame))
					_anchor_rects.append({
						"span_id": span["id"],
						"rect": Rect2(hx - ANCHOR_HANDLE_W * 0.5, y + 2.0,
							ANCHOR_HANDLE_W, LANE_H - 4.0),
						"start": int(span["start"]),
						"ghost": ghost_frames,
						"color": span["color"],
					})
				# The fire grab on the instant marker (ADR-0085 fire-drag). Every EVENT
				# past the first gets one — the first is pinned (its fire is the phase
				# offset, no prior gap to trade). The gate is role=="event", NOT merely
				# index>0: the TERMINATOR end-cap (index == max_keyframe) is inert (its byte
				# is the last event's Gap; a second handle would be two-handles-one-byte), so
				# it is select-to-inspect only. No ghost needed: you can move a trigger
				# whatever its sound length.
				if is_sound and span.get("role", "event") == "event" \
						and int(span.get("keyframe_index", 0)) > 0:
					_fire_rects.append({
						"span_id": span["id"],
						"rect": Rect2(x0 - FIRE_HANDLE_W * 0.5, y + 2.0,
							FIRE_HANDLE_W, LANE_H - 4.0),
						"start": int(span["start"]),
					})
				# The hit target. ADR-0085 conformance: a sound trigger is an INSTANT, so
				# its select rect is the fixed marker width — DECOUPLED from the ghost. The
				# ghost is a read-only projection and never the click target; letting its
				# width own the select rect is the drift that swallows a near neighbour's
				# marker (a ringing sound's ghost overlaps the next trigger). Others use
				# their [start,end) width.
				var w: float
				if is_sound:
					w = SOUND_HIT_MIN_W
				else:
					w = maxf(2.0, x1 - x0)
				_span_rects.append({
					"span": span,
					"rect": Rect2(x0, y + 2.0, w, LANE_H - 4.0),
				})
				# The boundary-drag edge grip (ADR-0086 camera / ADR-0087 palette + screen): a
				# grab band centered on the span's RIGHT edge x. One grip per span, right edge
				# only — a "left edge" is always the neighbour's right edge or the pinned
				# frame-0 origin. Hit-tested before the whole-tile select so grabbing the
				# boundary resizes it. All three channels author absolutely (camera →
				# end_frame, palette/screen → snapped time_value trade), so they share the
				# grip + the report→apply→reproject seam.
				#
				# `span_id` is the WRITE owner (whose stored number the drag moves) and
				# `select_id` the on-screen owner (who it selects and draws a handle for).
				# They differ at a hidden hold, whose right edge is the next drawn span's
				# visible LEFT edge. EVERY tiled boundary registers — a hold with nothing
				# drawn after it simply carries no identity (ADR-0086 dec. 23;
				# suppressing it made ~1945 colour keyframes unreachable, not merely
				# un-grabbable). edge_grip_identity is the one place that decides.
				#
				# Each half of the band is clipped to leave BODY_MIN_W of body in the span it
				# reaches into — this span on the left, the next TILE on the right — so no span
				# is ever covered edge to edge and loses its Move (see BODY_MIN_W). Past the
				# lane's last tile there is nothing to protect, so the outward half stays whole.
				if span.get("kind", "") in ["camera", "palette", "screen", "particle"]:
					var nxt: Dictionary = _next_tile(lane_spans, si)
					var reach_in: float = _grip_reach(x1 - x0)
					var reach_out: float = EDGE_HANDLE_W * 0.5 if nxt.is_empty() \
						else _grip_reach(_tile_w(nxt))
					if reach_in + reach_out > 0.0:
						_edge_rects.append({
							"span_id": span["id"],
							"select_id": edge_grip_identity(span, nxt, _selected_id),
							"rect": Rect2(x1 - reach_in, y + 2.0,
								reach_in + reach_out, LANE_H - 4.0),
						})
			_layout_lane_markers(lane, y)
			y += LANE_H + LANE_GAP
	# The global "Time scale" pacing lane (#270, ADR-0093) — a first NON-phase lane, laid out
	# below every phase section as a full-width bottom strip. Its two bands tile their frame
	# ranges so they line up against the same axis as the phase lanes.
	y = _layout_pacing_lane(y)
	_content_h = y


## Lay out the global "Time scale" pacing lane's bottom strip + its two band hit-rects
## (#270, ADR-0093). Returns the new content-bottom y (unchanged when the effect carries no
## time_scale). Each band is a full [start,end)-mapped rect the click routes to the pop-up.
func _layout_pacing_lane(y: float) -> float:
	var lane: Dictionary = _score.get("pacing_lane", {})
	var bands: Array = lane.get("bands", [])
	if bands.is_empty():
		return y
	var strip_top := y
	_pacing_lane_rect = Rect2(0.0, strip_top, size.x, PACING_LANE_H)
	for band in bands:
		var x0 := axis.frame_to_x(float(band["start"]))
		var x1 := axis.frame_to_x(float(band["end"]))
		_pacing_rects.append({
			"id": band["id"],
			"field": band.get("field", ""),
			"rect": Rect2(x0, strip_top + 2.0, maxf(2.0, x1 - x0), PACING_LANE_H - 4.0),
			"enabled": bool(band.get("enabled", false)),
			"pacing": band.get("pacing", []),
		})
	return y + PACING_LANE_H + LANE_GAP


## The bottom pacing strip rect (#270), or an empty Rect2 when the effect has no time_scale.
## Test seam AND the pop-up-anchor source.
func pacing_lane_rect() -> Rect2:
	return _pacing_lane_rect


## The laid-out pacing band hit-rects — [{ id, field, rect, enabled, pacing }] — after
## rebuild_layout. Empty when the effect carries no time_scale. Test seam + the draw's source.
func pacing_band_rects() -> Array:
	return _pacing_rects


## Lay out a lane's point markers (compiled camera keyframes) into diamond centers +
## hit boxes. Markers sharing a frame — a split's coincident siblings — are FANNED
## horizontally around the true frame x so each stays individually clickable; the fan is
## centered on the frame so the group still reads as "here". Frame order is preserved
## (Dictionary keeps insertion order), so the fan is stable across redraws.
func _layout_lane_markers(lane: Dictionary, lane_y: float) -> void:
	var by_frame: Dictionary = {}
	for span in lane["spans"]:
		if not span.get("marker", false):
			continue
		var fr: int = int(span["start"])
		if not by_frame.has(fr):
			by_frame[fr] = []
		by_frame[fr].append(span)
	var cy := lane_y + LANE_H * 0.5
	for fr in by_frame:
		var group: Array = by_frame[fr]
		var base_x := axis.frame_to_x(float(fr))
		var n := group.size()
		for k in range(n):
			var cx: float = base_x + (float(k) - float(n - 1) * 0.5) * MARKER_FAN
			_marker_rects.append({
				"span": group[k],
				"center": Vector2(cx, cy),
				"rect": Rect2(cx - MARKER_HALF, cy - MARKER_HALF, MARKER_HALF * 2.0, MARKER_HALF * 2.0),
			})
		# A fanned group (2+) gets a coincidence tie at the TRUE frame x, spanning the fan,
		# so it reads as one coincident group rather than markers at nearby frames (#285).
		if n >= 2:
			var half_fan: float = float(n - 1) * 0.5 * MARKER_FAN
			_marker_ties.append({
				"center_x": base_x,
				"left_x": base_x - half_fan - MARKER_HALF,
				"right_x": base_x + half_fan + MARKER_HALF,
				"y": cy,
			})
## The read-only ghost-bar rect for a span id (the sound's projected real length),
## or an empty Rect2 if the span has no ghost. Public for the layout guard.
func ghost_rect_for(span_id: String) -> Rect2:
	for g in _ghost_rects:
		if g["span_id"] == span_id:
			return g["rect"]
	return Rect2()


## The energy envelope (ADR-0085 climax cue) carried on a span's ghost bar — the 0..1
## per-frame amplitude the draw pass paints as a swell. Empty when the span has no
## ghost or no rendered envelope. Public for the layout guard.
func ghost_energy_for(span_id: String) -> PackedFloat32Array:
	for g in _ghost_rects:
		if g["span_id"] == span_id:
			return g["energy"]
	return PackedFloat32Array()


## The anchor handle rect for a span id (the draggable HIT marker on its ghost bar),
## or an empty Rect2 when the span has no ghost (nothing to place the handle on).
func anchor_rect_for(span_id: String) -> Rect2:
	for a in _anchor_rects:
		if a["span_id"] == span_id:
			return a["rect"]
	return Rect2()


## The marker frame a fire-draggable span sits at (its `start`), read off the laid-out fire
## rects so the relative-drag grab anchors to the same value the marker draws at. 0 when the
## span has no fire grab (pinned / unknown) — a pinned trigger never arms a drag anyway.
func _fire_frame_for(span_id: String) -> int:
	for f in _fire_rects:
		if f["span_id"] == span_id:
			return int(f["start"])
	return 0


## The fire grab rect for a span id (the draggable instant marker), or an empty Rect2
## when the trigger is pinned (the first) or unknown.
func fire_rect_for(span_id: String) -> Rect2:
	for f in _fire_rects:
		if f["span_id"] == span_id:
			return f["rect"]
	return Rect2()


## The boundary-drag edge grip rect for a camera span id (the grab band on its right
## edge), or an empty Rect2 for a non-camera or unknown span. Public for the layout guard.
func edge_rect_for(span_id: String) -> Rect2:
	for e in _edge_rects:
		if e["span_id"] == span_id:
			return e["rect"]
	return Rect2()


## The boundary grip's SELECT IDENTITY for a span id — who a drag on that grip should select
## and inspect, which is NOT always who it writes (see edge_grip_identity). "" means "leave the
## selection alone": an unknown or gripless span, or a lane-tail hold, which speaks for no
## span. Public because the page owns selection and must not re-derive the rule.
func edge_identity_for(span_id: String) -> String:
	for e in _edge_rects:
		if e["span_id"] == span_id:
			return String(e.get("select_id", ""))
	return ""


## Reproject just one trigger's anchor handle during a live drag (ADR-0085): write the
## span's anchor_offset in place and relayout so the handle follows the cursor. Unlike
## load_score this does NOT reset the playhead, selection, zoom, or audibility — the
## authored value's source of truth is the host's live keyframe; this only keeps the
## displayed handle in lock-step. Unknown span ids are inert.
func set_anchor_offset(span_id: String, offset: int) -> void:
	for lane in _score.get("lanes", []):
		for span in lane.get("spans", []):
			if span.get("id", "") == span_id:
				span["anchor_offset"] = offset
				rebuild_layout()
				queue_redraw()
				return


## Append this lane's Solo (S) and Mute (M) gutter buttons, right-justified inside the
## label gutter at the lane's vertical center. M is outermost so it sits nearest the
## lanes; S is to its left. Kept in layout (not draw) so hit-testing and paint agree.
func _append_lane_buttons(lane_id: String, lane_y: float) -> void:
	var by := lane_y + (LANE_H - BTN_SIZE) * 0.5
	var mute_x := GUTTER_W - BTN_PAD - BTN_SIZE
	var solo_x := mute_x - BTN_PAD - BTN_SIZE
	_lane_button_rects.append({"lane_id": lane_id, "kind": "solo",
		"rect": Rect2(solo_x, by, BTN_SIZE, BTN_SIZE)})
	_lane_button_rects.append({"lane_id": lane_id, "kind": "mute",
		"rect": Rect2(mute_x, by, BTN_SIZE, BTN_SIZE)})


# --- Solo / Mute state ----------------------------------------------------

func muted_lanes() -> Dictionary:
	return _muted


func soloed_lanes() -> Dictionary:
	return _soloed


func is_lane_muted(lane_id: String) -> bool:
	return _muted.has(lane_id)


func is_lane_soloed(lane_id: String) -> bool:
	return _soloed.has(lane_id)


## A lane is silenced (its events ignored in the preview) if it is muted, or if any
## lane is soloed and this one is not — the same DAW rule resolve_audibility applies.
## Used only for the gutter's dim-the-label affordance; the preview's authority is
## resolve_audibility on the page.
func is_lane_silenced(lane_id: String) -> bool:
	return _muted.has(lane_id) or (not _soloed.is_empty() and not _soloed.has(lane_id))


## Toggle a lane's mute/solo and notify (lane_audibility_changed). Idempotent per
## click; the page re-resolves the whole preview audibility on the signal.
func toggle_mute(lane_id: String) -> void:
	if _muted.has(lane_id):
		_muted.erase(lane_id)
	else:
		_muted[lane_id] = true
	lane_audibility_changed.emit()
	queue_redraw()


func toggle_solo(lane_id: String) -> void:
	if _soloed.has(lane_id):
		_soloed.erase(lane_id)
	else:
		_soloed[lane_id] = true
	lane_audibility_changed.emit()
	queue_redraw()


## Collapse/expand a phase section by name, re-flowing the layout and re-hugging the
## control height. Idempotent per state; unknown phases are inert.
func toggle_section(phase: String) -> void:
	_collapsed[phase] = not _collapsed.get(phase, false)
	rebuild_layout()
	custom_minimum_size.y = maxf(MIN_TIMELINE_H, _content_h + CONTENT_PAD_Y)
	queue_redraw()


func is_section_collapsed(phase: String) -> bool:
	return _collapsed.get(phase, false)


func _lanes_in_phase(phase: String) -> Array:
	var out: Array = []
	for lane in _score.get("lanes", []):
		if lane["phase"] == phase:
			out.append(lane)
	return out


## Route a local point to a transport intent. Spans win over the lane-area seek
## zone; the ruler and empty lane area both seek. Returns:
##   {"kind": "seek", "frame": int} | {"kind": "select", "span_id": String}
##   | {"kind": "none"}
func hit_test(local_pos: Vector2) -> Dictionary:
	# Section headers are full-width and clickable (incl. over the gutter, where the
	# collapse arrow lives) — checked before the gutter-inert rule and the spans.
	for sec in _section_rows:
		if sec["rect"].has_point(local_pos):
			return {"kind": "toggle", "phase": sec["phase"]}
	# The per-lane Solo/Mute buttons live inside the gutter — checked before the
	# gutter-inert rule so the label area around them stays dead.
	for btn in _lane_button_rects:
		if btn["rect"].has_point(local_pos):
			return {"kind": btn["kind"], "lane_id": btn["lane_id"]}
	if local_pos.x < GUTTER_W:
		return {"kind": "none"}   # the gutter (lane labels) is inert
	# Point markers win over the seek zone too (small hit boxes; checked before intervals
	# so a marker overlapping an interval edge still selects the marker).
	for hit in _marker_rects:
		if hit["rect"].has_point(local_pos):
			return {"kind": "select", "span_id": hit["span"]["id"]}
	# A sound trigger's INSTANT marker fire-grab (ADR-0085) sits at the fire frame, on
	# top of both the anchor handle (when its offset is 0) and the footprint select — so
	# it is tested FIRST: the marker moves the trigger; the anchor stays reachable only
	# where its offset pulls it clear of the marker.
	for f in _fire_rects:
		if f["rect"].has_point(local_pos):
			return {"kind": "fire", "span_id": f["span_id"]}
	# A sound trigger's anchor handle sits ON its ghost bar, inside the footprint
	# select rect — so it must be tested before the whole-footprint select would
	# swallow the grab and you could never drag the anchor.
	for a in _anchor_rects:
		if a["rect"].has_point(local_pos):
			return {"kind": "anchor", "span_id": a["span_id"]}
	# A camera span's right-edge grip (ADR-0086 boundary-drag) sits on the boundary, inside
	# both adjacent tiles' select rects — so it is tested BEFORE the whole-tile select would
	# swallow the grab and you could never drag the boundary.
	for e in _edge_rects:
		if e["rect"].has_point(local_pos):
			return {"kind": "edge", "span_id": e["span_id"]}
	# The global pacing bands (#270): a click on a "Time scale" band selects it, which the host
	# reads as "open the pop-up painter for this curve". Checked before the phase-span loop (the
	# strip sits below every lane, so there is no overlap, but it keeps the select contract in
	# one place). No seek/scrub on the strip — it is an authoring surface, not the ruler.
	for pb in _pacing_rects:
		if pb["rect"].has_point(local_pos):
			return {"kind": "select", "span_id": pb["id"]}
	# ADR-0085 conformance: when several select rects contain the point (overlapping
	# instants — two triggers within the fixed marker width), the NEAREST fire marker
	# wins, not the first in order. A span's fire marker is its rect's left edge (an
	# instant's rect starts at the fire; a bar's at its start). Tie → first is fine.
	# A real EVENT always beats an inert TERMINATOR end-cap: the terminator is select-to-
	# inspect only, so it must never steal a neighbouring event's marker when their rects
	# overlap at a coarse zoom — a terminator wins only where no event rect covers the point.
	var best_id := ""
	var best_d := INF
	var best_is_term := true
	for hit in _span_rects:
		# A hidden spacer is empty space (ADR-0087 decs. 23-28) — not selectable. Skip it
		# so a click falls through to the seek zone (left → seek; right → gap context), exactly
		# how an emitter-lane gap behaves. The selected span is never hidden, so it stays grabbable.
		if is_hidden_spacer(hit["span"], _selected_id):
			continue
		if hit["rect"].has_point(local_pos):
			var span: Dictionary = hit["span"]
			var is_term: bool = str(span.get("role", "")) == "terminator"
			var d: float = absf(local_pos.x - hit["rect"].position.x)
			if (best_is_term and not is_term) or (best_is_term == is_term and d < best_d):
				best_d = d
				best_id = span["id"]
				best_is_term = is_term
	if best_id != "":
		return {"kind": "select", "span_id": best_id}
	# Loose selection ("difficult to select an event"): every exact pass missed, but a
	# marker on THIS lane row within LOOSE_SELECT_TOL px still means "I meant that one" —
	# so select the nearest rather than scrub the playhead out from under the author.
	# SELECT-only by design: a sloppy press must never arm a byte-moving fire/anchor drag
	# (the exact grabs above keep that). Event-beats-terminator carries over from the
	# exact pass, and the tolerance is lane-row-scoped — the ruler and other rows seek.
	var loose := _loose_select(local_pos)
	if loose != "":
		return {"kind": "select", "span_id": loose}
	return {"kind": "seek", "frame": TimelineAxis.snap(axis.x_to_frame(local_pos.x), snap_step)}


## The lane row (the score's lane Dictionary) whose band contains `local_pos`, or {} in the
## gutter / between rows / over a header. Used to resolve a gap right-click (a "seek" hit that
## lands on no span) to its lane, so the host can offer the Add-in-a-gap verb (ADR-0089).
func _lane_row_at(local_pos: Vector2) -> Dictionary:
	if local_pos.x < GUTTER_W:
		return {}
	for row in _lane_rows:
		if row["rect"].has_point(local_pos):
			return row["lane"]
	return {}


## The nearest selectable span id within LOOSE_SELECT_TOL px of a lane-row point, or ""
## when nothing qualifies. Candidates are the same rects the exact select passes test
## (point markers + span select rects), matched to the CLICKED ROW by their vertical
## center; distance is horizontal, to the rect's nearest edge. A real EVENT beats the
## inert terminator end-cap even when the terminator is strictly nearer.
func _loose_select(p: Vector2) -> String:
	var best_id := ""
	var best_d := INF
	var best_is_term := true
	for cand in [_marker_rects, _span_rects]:
		for hit in cand:
			var rect: Rect2 = hit["rect"]
			if absf(p.y - (rect.position.y + rect.size.y * 0.5)) > LANE_H * 0.5:
				continue   # a different lane row — the tolerance never crosses rows
			var d := maxf(0.0, maxf(rect.position.x - p.x, p.x - rect.end.x))
			if d > LOOSE_SELECT_TOL:
				continue
			var span: Dictionary = hit["span"]
			# A hidden SPACER is empty space, and the loose pass must honour that as strictly as
			# the exact pass does (:883). Its rect is still in _span_rects (the gap right-click
			# needs it), and `d` is 0 for any point INSIDE it — so without this skip the loose
			# pass would hand back the very span the exact pass just refused, and "not
			# selectable" would be true of neither click nor right-click.
			if is_hidden_spacer(span, _selected_id):
				continue
			var is_term: bool = str(span.get("role", "")) == "terminator"
			if (best_is_term and not is_term) or (best_is_term == is_term and d < best_d):
				best_d = d
				best_id = span["id"]
				best_is_term = is_term
	return best_id


# --- Input ----------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_on_mouse_button(event)
	elif event is InputEventMouseMotion and _panning:
		# No scroll_x >= 0 clamp: frame 0 is free to leave the left edge so you can
		# pan into the empty space before the effect starts (no snap-back to 0).
		pan_by(event.position.x - _pan_last_x)
		_pan_last_x = event.position.x
	elif event is InputEventMouseMotion and _fire_drag_id != "":
		_drag_fire_to_x(event.position.x)
	elif event is InputEventMouseMotion and _anchor_drag_id != "":
		_drag_anchor_to_x(event.position.x)
	elif event is InputEventMouseMotion and _edge_drag_id != "":
		_drag_edge_to_x(event.position.x)
	elif event is InputEventMouseMotion and _body_drag_id != "":
		_drag_body_to_x(event.position.x)
	elif event is InputEventMouseMotion and _scrubbing:
		_seek_to_x(event.position.x)
	elif event is InputEventMouseMotion:
		# No active interaction: track which camera edge grip (if any) the cursor is over so
		# the hover highlight shows. Redraw only on a transition, never per pixel.
		_update_edge_hover(event.position)


## Resolve the edge grip under `pos` and, if it changed, refresh the hover highlight. Cheap:
## a queue_redraw fires only when the hovered edge id actually changes (enter/leave), so plain
## mouse motion over the timeline doesn't repaint every frame.
func _update_edge_hover(pos: Vector2) -> void:
	var over := ""
	for e in _edge_rects:
		if e["rect"].has_point(pos):
			over = e["span_id"]
			break
	if over != _hover_edge_id:
		_hover_edge_id = over
		queue_redraw()


## Continuous scrub: map a local x to a snapped frame, move the playhead, and emit
## the seek. x is clamped to the frame area so dragging into the label gutter still
## resolves to frame 0 rather than running off the axis. Shared by press + drag.
func _seek_to_x(x: float) -> void:
	var frame := TimelineAxis.snap(axis.x_to_frame(maxf(GUTTER_W, x)), snap_step)
	set_playhead(frame)
	seek_requested.emit(frame)


## Continuous anchor drag: map local x to a snapped frame, turn it into the offset
## from the dragged trigger's fire (clamped into the ghost length), and emit the
## intent. The handle only moves once the host applies the edit and the layout
## re-projects — the timeline reports, it does not mutate the score.
func _drag_anchor_to_x(x: float) -> void:
	for a in _anchor_rects:
		if a["span_id"] == _anchor_drag_id:
			var frame := TimelineAxis.snap(axis.x_to_frame(maxf(GUTTER_W, x)), snap_step)
			var offset := SoundGhostProjector.anchor_offset_from_frame(
				frame, int(a["start"]), int(a["ghost"]))
			anchor_offset_changed.emit(_anchor_drag_id, offset)
			return


## Continuous fire drag: emit the trigger's new ABSOLUTE fire frame, computed RELATIVE to
## the grab — `grab_frame + round((x - grab_x) / ppf)` — NOT `round(x_to_frame(x))`. Relative
## keeps a slightly-off-center grab from jumping the marker, and (at ppf < 1) lets a back-drag
## land on the exact grab frame instead of a coarser neighbour. No clamping here — SoundGapMath
## (in the host) enforces the stay-local bounds; the marker only moves once the host applies the
## edit and reprojects (ADR-0085 unified path). The timeline reports, it does not mutate the score.
func _drag_fire_to_x(x: float) -> void:
	var delta_frames := int(round((x - _fire_grab_x) / axis.pixels_per_frame))
	var frame := maxi(0, _fire_grab_frame + delta_frames)
	fire_frame_changed.emit(_fire_drag_id, frame)


## Continuous boundary drag (ADR-0086): map local x to a snapped frame and emit it as the
## span's new ABSOLUTE right-edge frame. No clamping here — the host clamps to
## (prev_end, next_end) and applies the single end_frame edit; the grip only moves once the
## host reprojects. The timeline reports, it does not mutate the score.
func _drag_edge_to_x(x: float) -> void:
	var frame := TimelineAxis.snap(axis.x_to_frame(maxf(GUTTER_W, x)), snap_step)
	edge_dragged.emit(_edge_drag_id, frame)


## Continuous body drag (ADR-0089 Move): emit the snapped frame delta from the grab point. No
## clamping here — the host clamps to the surrounding gap room and slides both boundaries; the
## span only moves once the host reprojects. The timeline reports, it does not mutate the score.
func _drag_body_to_x(x: float) -> void:
	var frame := TimelineAxis.snap(axis.x_to_frame(maxf(GUTTER_W, x)), snap_step)
	span_body_dragged.emit(_body_drag_id, frame - _body_drag_start_frame)


func _on_mouse_button(event: InputEventMouseButton) -> void:
	# Frame-axis zoom is on CTRL+wheel; a plain wheel is left UNACCEPTED so it bubbles
	# to the enclosing ScrollContainer and scrolls the channel list vertically (the
	# DAW convention now that the timeline is a tall, scrolling panel).
	if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		if event.ctrl_pressed:
			zoom_at(1.15, event.position.x)
			accept_event()
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		if event.ctrl_pressed:
			zoom_at(1.0 / 1.15, event.position.x)
			accept_event()
		return
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = event.pressed
		_pan_last_x = event.position.x
		return
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		# Right-click a span → hand its id to the host for a context menu. Also
		# select it so the inspector shows the keyframe you're addressing. A right-click
		# never starts a drag, so the FIRE/ANCHOR grab hits count as the span too — else
		# a click dead center on a draggable marker (where the grab wins the hit-test)
		# would silently open nothing.
		rebuild_layout()
		var rhit := hit_test(event.position)
		if rhit["kind"] in ["select", "fire", "anchor"]:
			select_span(rhit["span_id"])
			span_selected.emit(rhit["span_id"])
			# Carry the frame under the cursor too — an Add-here (insert-waypoint) cuts the
			# span AT that frame, so the context menu needs it, not just the span id.
			span_context_requested.emit(rhit["span_id"], int(axis.x_to_frame(event.position.x)))
		elif rhit["kind"] == "seek":
			# A right-click on empty lane space: no span to address. A sound lane offers
			# "Add event here" at the cursor (the gap gesture on an instant-marker lane,
			# ADR-0085); a particle lane offers Add-in-a-gap (ADR-0089); a colour lane's
			# empty space is an INVISIBLE SPACER — hit_test skips it (unselectable), so a
			# right-click over it lands here too, and the host offers Add-into-the-spacer
			# (ADR-0087 decs. 23-28). A camera sub-channel lane's empty space is a hidden
			# MAP-delta hold (ADR-0086 dec. 15) and offers the same Add. Emit the LANE id +
			# the score-absolute cursor frame; the host resolves phase + channel. The read-only
			# compiled-storage lane has no gap verb → inert here. Off-row space (below the
			# lanes) resolves to no lane and stays inert.
			var lane := _lane_row_at(event.position)
			if not lane.is_empty() and String(lane.get("kind", "")) in ["sound", "particle", "palette", "screen", "camera"]:
				lane_context_requested.emit(String(lane.get("id", "")),
					TimelineAxis.snap(axis.x_to_frame(event.position.x), snap_step))
		accept_event()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed and event.shift_pressed:
		_panning = true
		_pan_last_x = event.position.x
		return
	if not event.pressed:
		_panning = false
		_scrubbing = false
		_anchor_drag_id = ""
		if _fire_drag_id != "":
			var ended := _fire_drag_id
			_fire_drag_id = ""
			fire_drag_ended.emit(ended)
		if _edge_drag_id != "":
			var edge_ended := _edge_drag_id
			_edge_drag_id = ""
			edge_drag_ended.emit(edge_ended)
		if _body_drag_id != "":
			var body_ended := _body_drag_id
			_body_drag_id = ""
			span_body_drag_ended.emit(body_ended)
		return
	# A plain left press: route through the hit-test. A press in a seek zone arms a
	# continuous scrub (hold + drag moves the playhead); a press on a span inspects
	# it and never scrubs — the "seek vs inspect never fight" invariant.
	rebuild_layout()
	var hit := hit_test(event.position)
	match hit["kind"]:
		"toggle":
			toggle_section(hit["phase"])
		"mute":
			toggle_mute(hit["lane_id"])
		"solo":
			toggle_solo(hit["lane_id"])
		"fire":
			# Grab the instant marker: arm a continuous fire drag. Record the grab's local
			# x and the marker's own frame so the drag is RELATIVE — a press that isn't
			# pixel-perfect on the marker (or a coarse zoom) never leaps the trigger.
			_fire_drag_id = hit["span_id"]
			_fire_grab_x = event.position.x
			_fire_grab_frame = _fire_frame_for(_fire_drag_id)
			fire_drag_started.emit(_fire_drag_id)
			_drag_fire_to_x(event.position.x)
		"anchor":
			# Grab the handle: arm a continuous anchor drag and report the offset at the
			# press point (a click without motion still confirms the current offset).
			_anchor_drag_id = hit["span_id"]
			_drag_anchor_to_x(event.position.x)
		"edge":
			# Grab the camera span's right edge: arm a boundary drag and report the frame at
			# the press point (a click without motion still confirms the current end_frame).
			_edge_drag_id = hit["span_id"]
			edge_drag_started.emit(_edge_drag_id)
			_drag_edge_to_x(event.position.x)
		"seek":
			_scrubbing = true
			set_playhead(hit["frame"])
			seek_requested.emit(hit["frame"])
		"select":
			select_span(hit["span_id"])
			span_selected.emit(hit["span_id"])
			# A span BODY press also arms a Move body-drag (ADR-0089, generalised to camera +
			# the two colour kinds by ADR-0101 decision 3): a click still just selects (no
			# motion → no delta emitted); a drag slides the span. The right-edge grip is
			# hit-tested first (kind "edge"), so the body-drag is body-only.
			if is_movable_span(String(hit["span_id"])):
				_body_drag_id = hit["span_id"]
				_body_drag_start_frame = TimelineAxis.snap(axis.x_to_frame(event.position.x), snap_step)
				span_body_drag_started.emit(_body_drag_id)


# --- Draw -----------------------------------------------------------------

func _draw() -> void:
	_resolve_default_view()
	rebuild_layout()
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG)
	_draw_lanes()
	_draw_sound_ghosts()
	_draw_spans()
	_draw_markers()
	_draw_anchor_handles()
	_draw_edge_grips()
	_draw_grid()
	_draw_pacing_bands()
	_draw_loop_band()
	_draw_gutter_labels()
	# Section header bars LAST (over the gutter fill) so the collapse arrow + label,
	# which live at the far left inside the gutter, aren't painted over by
	# _draw_gutter_labels' background.
	_draw_sections()
	_draw_phase_boundaries()
	_draw_end_marker()
	_draw_playhead()


func _draw_lanes() -> void:
	# Lane row backgrounds (right of the gutter only). Section header bars are drawn
	# later by _draw_sections (on top of the gutter fill).
	var i := 0
	for row in _lane_rows:
		var col: Color = COL_LANE_A if (i % 2 == 0) else COL_LANE_B
		var r: Rect2 = row["rect"]
		draw_rect(Rect2(GUTTER_W, r.position.y, r.size.x - GUTTER_W, r.size.y), col)
		i += 1


## Full-width, clickable phase-section header bars — a collapse arrow (▾ open / ▸
## collapsed) + the phase label + lane count, plus the frame-range band highlight to
## the right of the gutter. Drawn from _section_rows so collapse state, hit-testing,
## and paint never drift.
func _draw_sections() -> void:
	var font := get_theme_default_font()
	for sec in _section_rows:
		var hr: Rect2 = sec["rect"]
		draw_rect(hr, COL_SECTION)
		var span_a := maxf(GUTTER_W, axis.frame_to_x(float(sec["band_start"])))
		var span_b := axis.frame_to_x(float(sec["band_end"]))
		if span_b > span_a:
			draw_rect(Rect2(span_a, hr.position.y, span_b - span_a, SECTION_H), Color(1, 1, 1, 0.05))
		# Bottom separator line so a collapsed section still reads as its own bar.
		draw_line(Vector2(0.0, hr.position.y + SECTION_H), Vector2(size.x, hr.position.y + SECTION_H),
			Color(0, 0, 0, 0.35), 1.0)
		if font:
			var arrow: String = "▸" if sec["collapsed"] else "▾"
			var txt := "%s  %s  (%d)" % [arrow, sec["label"], int(sec["lane_count"])]
			draw_string(font, Vector2(PAD_X, hr.position.y + SECTION_H - 6.0),
				txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_TEXT)


## Read-only ghost bars — the projected real length of each sound trigger, painted
## behind the instant markers (drawn between the lane fills and the spans). Never an
## authorable span (ADR-0085: commensurable ≠ authorable) and never a click target.
##
## Four ordered passes so overlapping ghosts stay legible AND traceable (ADR-0085):
##   1. faint fills — every ghost the SAME colour + alpha, so source-over is
##      order-independent (a doubled-up region simply reads denser); the energy swell
##      rides inside this pass.
##   2. the SELECTED trigger's ghost brightens and draws in front.
##   3. a per-ghost hairline TOP edge, so every extent stays traceable under a neighbour.
##   4. (markers — drawn afterwards by _draw_spans, so they always win z-order.)
func _draw_sound_ghosts() -> void:
	# One off-screen cull, shared by all three passes (each iterates only visible ghosts).
	var visible := _visible_ghosts()
	# Pass 1: faint fills + energy swell (order-independent wash).
	for g in visible:
		var full: Rect2 = g["rect"]   # unclipped extent — the energy samples map onto it
		var col: Color = g["color"]
		draw_rect(_clip_to_gutter(full), Color(col.r, col.g, col.b, GHOST_FILL_A))
		# The climax cue: the sound's 0..1 energy envelope filled up from the baseline
		# (ADR-0085). Painted over the wash so the swell reads brighter where it peaks.
		_draw_ghost_energy(g["energy"], full, col)
		# TIER-3 ghost pips: the open pair's / selected trigger's unrolled note onsets,
		# small bright ticks inside the bar. Editor→timeline emphasis only — the pips
		# never register a hit region.
		for pf in g.get("pips", []):
			var px := axis.frame_to_x(float(int(g.get("start", 0)) + int(pf)))
			if px < GUTTER_W or px > full.position.x + full.size.x:
				continue
			draw_line(Vector2(px, full.position.y),
				Vector2(px, full.position.y + full.size.y * 0.55),
				Color(col.r, col.g, col.b, GHOST_PIP_A), 2.0)
	# Pass 2: the selected trigger's ghost brightens (a second fill on top).
	for g in visible:
		if g["span_id"] != _selected_id:
			continue
		var col: Color = g["color"]
		draw_rect(_clip_to_gutter(g["rect"]), Color(col.r, col.g, col.b, GHOST_SELECT_A))
	# Pass 3: per-ghost hairline TOP edge (the traceable extent under a neighbour); the
	# selected ghost's edge is brighter so it reads through the wash.
	for g in visible:
		var rect := _clip_to_gutter(g["rect"])
		var col: Color = g["color"]
		var a: float = GHOST_EDGE_SEL_A if g["span_id"] == _selected_id else GHOST_EDGE_A
		draw_line(Vector2(rect.position.x, rect.position.y),
			Vector2(rect.end.x, rect.position.y), Color(col.r, col.g, col.b, a), 1.0)


## The ghosts whose UNCLIPPED extent is at least partly right of the label gutter — the
## shared off-screen cull for every ghost draw pass (a fully-left-of-gutter ghost draws nothing).
func _visible_ghosts() -> Array:
	var out: Array = []
	for g in _ghost_rects:
		var full: Rect2 = g["rect"]
		if full.position.x + full.size.x >= GUTTER_W:
			out.append(g)
	return out


## Clip a ghost rect's left edge to the label gutter (so no wash pixel sticks out left
## of the labels), returning the visible portion. Shared by the ghost draw passes.
func _clip_to_gutter(full: Rect2) -> Rect2:
	var rect := full
	if rect.position.x < GUTTER_W:
		var over := GUTTER_W - rect.position.x
		rect.position.x = GUTTER_W
		rect.size.x -= over
	return rect


## Paint one ghost bar's energy envelope as a filled swell from the baseline (ADR-0085
## climax cue). Samples are spread evenly across the bar's UNCLIPPED width and clipped
## against the label gutter here, so the curve lines up with the ghost even when the
## bar is scrolled partway behind the gutter. Fewer than two visible points → nothing.
func _draw_ghost_energy(energy: PackedFloat32Array, full: Rect2, col: Color) -> void:
	var n := energy.size()
	if n < 2:
		return
	var base_y := full.end.y - 1.0
	var span_h := base_y - (full.position.y + 1.0)
	if span_h <= 0.0:
		return
	var top := PackedVector2Array()
	for i in range(n):
		var x := full.position.x + (float(i) / float(n - 1)) * full.size.x
		if x < GUTTER_W:
			continue
		var h := clampf(energy[i], 0.0, 1.0) * span_h
		top.append(Vector2(x, base_y - h))
	if top.size() < 2:
		return
	var poly := top.duplicate()
	poly.append(Vector2(top[top.size() - 1].x, base_y))   # drop to baseline on the right
	poly.append(Vector2(top[0].x, base_y))                 # …and back along it to the left
	draw_colored_polygon(poly, Color(col.r, col.g, col.b, 0.30))


## The anchor handles — a bright diamond on the ghost bar at each trigger's HIT frame
## (fire + anchor_offset), with a thin stem down to the ghost baseline. This is the
## draggable "the audible hit lands HERE" marker (ADR-0085); it reads as a grabbable
## glyph, distinct from the read-only ghost wash behind it.
func _draw_anchor_handles() -> void:
	for a in _anchor_rects:
		var rect: Rect2 = a["rect"]
		var cx := rect.get_center().x
		if cx < GUTTER_W:
			continue   # scrolled behind the label gutter
		var col: Color = a["color"]
		var bright := Color(col.r, col.g, col.b, 1.0).lightened(0.35)
		var cy := rect.get_center().y
		var r := ANCHOR_HANDLE_W * 0.5
		# A stem from the diamond down to the ghost baseline (the hit's position cue).
		draw_line(Vector2(cx, rect.position.y), Vector2(cx, rect.end.y),
			Color(bright.r, bright.g, bright.b, 0.5), 1.0)
		var diamond := PackedVector2Array([
			Vector2(cx, cy - r), Vector2(cx + r, cy),
			Vector2(cx, cy + r), Vector2(cx - r, cy)])
		draw_colored_polygon(diamond, bright)


## Draw the camera boundary-drag edge grips (ADR-0086): a vertical bar with two notch lines
## (the "resize this boundary" cue) on every edge BELONGING to the selected span, plus the
## edge under the cursor (hover). Not all-edges-always — that would pepper every fully-tiled
## tile. "Belonging" is the grip's select identity, not its write owner, so a selected span
## shows its own right handle AND the left handle owned by a hidden hold in front of it
## (edge_grip_drawn holds the whole rule).
func _draw_edge_grips() -> void:
	# A live move preview hides every grip. The dragged span's own grips are drawn (it is the
	# selection), and they sit on the boundaries the SCORE still reports — which the bar has
	# just slid away from, so drawing them would put a resize handle where there is no longer
	# an edge. They come back on release, against the committed lane.
	if _move_preview_id != "":
		return
	var sel := selected_span_id()
	for e in _edge_rects:
		var span_id: String = e["span_id"]
		if not edge_grip_drawn(e, sel, _hover_edge_id):
			continue
		var rect: Rect2 = e["rect"]
		var cx := rect.get_center().x
		if cx < GUTTER_W:
			continue   # scrolled behind the label gutter
		var strong: bool = span_id == _hover_edge_id
		var col := Color(0.95, 0.97, 1.0, 0.95 if strong else 0.7)
		# The boundary line, plus two short notches so it reads as a grabbable resize handle.
		draw_line(Vector2(cx, rect.position.y), Vector2(cx, rect.end.y), col, 2.0 if strong else 1.5)
		var ny0 := rect.position.y + rect.size.y * 0.35
		var ny1 := rect.position.y + rect.size.y * 0.65
		for dx in [-2.0, 2.0]:
			draw_line(Vector2(cx + dx, ny0), Vector2(cx + dx, ny1), Color(col.r, col.g, col.b, col.a * 0.7), 1.0)


func _draw_spans() -> void:
	var font := get_theme_default_font()
	for hit in _span_rects:
		var span: Dictionary = hit["span"]
		var rect: Rect2 = hit["rect"]
		# ADR-0089 Drag preview: a live structure-free Move draws THIS span at its committed
		# start plus the planner's clamped delta, and nothing else in the lane moves — because
		# nothing else in the DATA moved. Applied before the gutter clip below so a span
		# previewed back past the labels clips exactly like a scrolled one.
		if _move_preview_dx != 0 and String(span.get("id", "")) == _move_preview_id:
			rect.position.x += float(_move_preview_dx) * axis.pixels_per_frame
		# A hidden spacer (ADR-0087 decs. 23-28) renders as NOTHING — invisible empty
		# space, like an emitter-lane gap. It stays in _span_rects (for the gap-context
		# right-click), but the painter skips it entirely.
		if is_hidden_spacer(span, _selected_id):
			continue
		# Clip: skip spans entirely left of the gutter.
		if rect.position.x + rect.size.x < GUTTER_W:
			continue
		# Never paint a scrolled-in span into the label gutter: clamp its left edge
		# (and everything drawn from it — fill, border, selection outline, text) to
		# the gutter's right edge, so no track pixel sticks out left of the labels.
		if rect.position.x < GUTTER_W:
			var over := GUTTER_W - rect.position.x
			rect.position.x = GUTTER_W
			rect.size.x -= over
		var col: Color = span["color"]
		# A sound trigger is an INSTANT, not a bar: a bright vertical tick at the fire
		# frame (+ its ♪ label), with the ghost bar behind it carrying the length. The
		# terminator (index == max_keyframe) is instead a distinct INERT end-cap glyph
		# (ADR-0085 decision 4) — same select handle, but it reads as "end of track", not
		# a fire, and it never carries a tail.
		if span.get("kind", "") == "sound":
			if span.get("role", "event") == "terminator":
				_draw_sound_terminator(span, rect, font, col)
			else:
				_draw_sound_marker(span, rect, font, col)
			continue
		draw_rect(rect, Color(col.r, col.g, col.b, 0.85))
		# DISABLED (ADR-0087 decs. 23-28): hatch = "a human turned this off". The stripe's
		# meaning flipped from the third/fourth amendments' auto-detected inertness (now invisible
		# empty space) to a deliberately-disabled event — "muted, not gone", drawn dimmed under
		# the hatch, still selectable so its Enabled knob is reachable. Colour lanes carry the
		# `enabled` flag; other lanes lack it (default enabled → no hatch). Orthogonal to the
		# border (kind) and the past-end wash (the ADR-0071 display-hint pattern).
		if not bool(span.get("fields", {}).get("enabled", true)):
			for seg in _hatch_segments(rect):
				draw_line(seg[0], seg[1], COL_SPACER_STRIPE, 1.0)
		# Border: a Gradient screen tween gets a DASHED outline, everything else solid —
		# the at-a-glance Blend-vs-Gradient distinction (ADR-0071). Fill stays the color
		# the tween produces; only the outline (and the label) tell the kinds apart.
		if str(span.get("fields", {}).get("border", "solid")) == "dashed":
			_stroke_dashed(rect, Color(col.r, col.g, col.b, 1.0))
		else:
			draw_rect(rect, Color(col.r, col.g, col.b, 1.0), false, 1.0)
		# Dim the part of this span that lies PAST the derived end — that tail never
		# plays in-game (the cast is reaped when particles are gone), so wash it back
		# toward the background. A span entirely past the end is fully dimmed.
		if _end_frame > 0:
			var end_x := axis.frame_to_x(float(_end_frame))
			var dim_x: float = clampf(end_x, rect.position.x, rect.position.x + rect.size.x)
			if dim_x < rect.position.x + rect.size.x:
				draw_rect(Rect2(dim_x, rect.position.y,
					rect.position.x + rect.size.x - dim_x, rect.size.y), COL_PAST_END)
		if span["id"] == _selected_id:
			draw_rect(rect.grow(1.0), COL_SELECT, false, 2.0)
		if font and rect.size.x > 26.0:
			var label := _span_label(span)
			draw_string(font, rect.position + Vector2(4.0, rect.size.y - 6.0),
				label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 6.0, 10, _label_on(col))


## Draw the compiled-lane point markers — a filled diamond at each keyframe's frame, with
## a small mask tag (a/p/z) so the coalescing reads at a glance (all compiled markers share
## one slate hue, so the tag, not colour, tells the sub-channels apart). A marker past the
## derived end is washed back; the selected one gets a ring.
func _draw_markers() -> void:
	var font := get_theme_default_font()
	_draw_marker_ties()   # under the diamonds — the group's coincidence bracket
	for hit in _marker_rects:
		var span: Dictionary = hit["span"]
		var c: Vector2 = hit["center"]
		if c.x + MARKER_HALF < GUTTER_W:
			continue   # scrolled behind the gutter
		var col: Color = span["color"]
		_draw_diamond(c, MARKER_HALF, Color(col.r, col.g, col.b, 0.9), true)
		_draw_diamond(c, MARKER_HALF, Color(col.r, col.g, col.b, 1.0), false)
		# A marker past the derived end never plays in-game — wash it toward the background.
		if _end_frame > 0 and int(span["start"]) > _end_frame:
			_draw_diamond(c, MARKER_HALF, COL_PAST_END, true)
		if span["id"] == _selected_id:
			_draw_diamond(c, MARKER_HALF + 2.0, COL_SELECT, false)
		if font:
			var tag := _compiled_mask_tag(int(span.get("fields", {}).get("channel_mask", 0)))
			draw_string(font, Vector2(c.x + MARKER_HALF + 2.0, c.y + 3.0),
				tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COL_TEXT_DIM)


## Draw each coincidence tie: a thin bracket UNDER a fanned marker group, anchored at the
## true frame x with a short center tick, so a split reads as one coincident group at frame
## N rather than several markers at nearby frames (#285). The fan alone reads as a lie.
func _draw_marker_ties() -> void:
	for tie in _marker_ties:
		var left_x: float = maxf(float(tie["left_x"]), GUTTER_W)
		var right_x: float = float(tie["right_x"])
		if right_x < GUTTER_W:
			continue   # wholly behind the gutter
		var by: float = float(tie["y"]) + MARKER_HALF + 2.0
		draw_line(Vector2(left_x, by), Vector2(right_x, by), COL_TEXT_DIM, 1.0)
		# Small down-ticks at the ends + an up-tick at the true center, so the bracket
		# clearly binds the group to one frame.
		draw_line(Vector2(left_x, by), Vector2(left_x, by - 2.0), COL_TEXT_DIM, 1.0)
		draw_line(Vector2(right_x, by), Vector2(right_x, by - 2.0), COL_TEXT_DIM, 1.0)
		var cx: float = float(tie["center_x"])
		if cx >= GUTTER_W:
			draw_line(Vector2(cx, by), Vector2(cx, by + 2.0), COL_TEXT_DIM, 1.0)


## A diamond centered at c with half-extent r — filled polygon or a closed outline.
func _draw_diamond(c: Vector2, r: float, col: Color, filled: bool) -> void:
	var pts := PackedVector2Array([
		Vector2(c.x, c.y - r), Vector2(c.x + r, c.y),
		Vector2(c.x, c.y + r), Vector2(c.x - r, c.y)])
	if filled:
		draw_colored_polygon(pts, col)
	else:
		pts.append(pts[0])
		draw_polyline(pts, col, 1.0)
## Draw a sound trigger as an instant marker: a bright full-height vertical tick at
## the fire frame, a small downward caret at the top so it reads as a one-shot, and
## the ♪ label to its right (clear of the ghost bar behind it). Selection outlines
## the marker, not a bar.
func _draw_sound_marker(span: Dictionary, rect: Rect2, font, col: Color) -> void:
	var x := rect.position.x
	var top := rect.position.y
	var h := rect.size.y
	draw_rect(Rect2(x, top, 2.0, h), Color(col.r, col.g, col.b, 0.95))
	var caret := PackedVector2Array([
		Vector2(x - 3.0, top), Vector2(x + 5.0, top), Vector2(x + 1.0, top + 4.0)])
	draw_colored_polygon(caret, Color(col.r, col.g, col.b, 0.95))
	if span["id"] == _selected_id:
		draw_rect(Rect2(x - 2.0, top - 1.0, 6.0, h + 2.0), COL_SELECT, false, 2.0)
	if font:
		draw_string(font, Vector2(x + 5.0, top + h - 6.0), "♪",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)


## Draw the sound TERMINATOR as an inert end-cap glyph (ADR-0085 decision 4): a DIM
## vertical rule with a short left-pointing foot at top and bottom (a "⊣" end-bracket), so
## the last event's gap points at something visible that reads as "end of track" — not a
## fire (no bright tick, no caret, no ♪). Desaturated + dimmed so it never competes with a
## real trigger. Same select outline as a marker (it is select-to-inspect).
func _draw_sound_terminator(span: Dictionary, rect: Rect2, font, col: Color) -> void:
	var x := rect.position.x
	var top := rect.position.y
	var h := rect.size.y
	# A muted ink: keep the lane hue but drop it toward the dim text colour so it reads inert.
	var ink := Color(col.r, col.g, col.b, 0.55).lerp(COL_TEXT_DIM, 0.4)
	draw_rect(Rect2(x, top, 1.5, h), ink)
	var foot := 4.0
	draw_line(Vector2(x, top), Vector2(x - foot, top), ink, 1.0)
	draw_line(Vector2(x, top + h), Vector2(x - foot, top + h), ink, 1.0)
	if span["id"] == _selected_id:
		draw_rect(Rect2(x - foot - 1.0, top - 1.0, foot + 5.0, h + 2.0), COL_SELECT, false, 2.0)


## Readable label ink for a span: white on dark fills, near-black on light fills.
## Fixes unreadable dark-on-dark text (e.g. a deep-blue emitter or a dark tint).
func _label_on(fill: Color) -> Color:
	var luma := 0.299 * fill.r + 0.587 * fill.g + 0.114 * fill.b
	return Color(0.05, 0.05, 0.07, 0.95) if luma > 0.55 else Color(1, 1, 1, 0.95)


## The disabled hatch geometry (ADR-0087 dec. 26), PURE so the guard can pin it:
## 45° stripes (bottom-left → top-right) on a fixed pitch, each clipped to the span
## rect. Returns [ [a: Vector2, b: Vector2], … ]; the painter just draws the lines.
func _hatch_segments(rect: Rect2) -> Array:
	const PITCH := 6.0
	var out: Array = []
	var left := rect.position.x
	var right := rect.end.x
	var bottom := rect.end.y
	var h := rect.size.y
	var t := -h
	while t < rect.size.x:
		var x0: float = maxf(left, left + t)
		var x1: float = minf(right, left + t + h)
		if x1 > x0:
			# Along the stripe, y falls as x grows (screen y is down): y = bottom − (x − left − t).
			out.append([
				Vector2(x0, bottom - (x0 - left - t)),
				Vector2(x1, bottom - (x1 - left - t)),
			])
		t += PITCH
	return out


## A dashed rectangle outline (Godot's immediate draw has no dash mode) — the Gradient
## screen tween's border, distinguishing it from a solid-bordered Blend.
func _stroke_dashed(rect: Rect2, col: Color) -> void:
	const DASH := 4.0
	const GAP := 3.0
	var x := rect.position.x
	var right := rect.position.x + rect.size.x
	while x < right:
		var x2: float = minf(x + DASH, right)
		draw_line(Vector2(x, rect.position.y), Vector2(x2, rect.position.y), col, 1.0)
		draw_line(Vector2(x, rect.end.y), Vector2(x2, rect.end.y), col, 1.0)
		x += DASH + GAP
	draw_line(rect.position, Vector2(rect.position.x, rect.end.y), col, 1.0)
	draw_line(Vector2(right, rect.position.y), Vector2(right, rect.end.y), col, 1.0)


func _span_label(span: Dictionary) -> String:
	# A spacer names itself on ANY lane that has the role — colour (ADR-0087 dec. 27)
	# and camera (ADR-0086 dec. 15) — because the author's question is binary
	# (real event or empty space), so the flag wins over the kind label. Only ever seen on the
	# SELECTED span, which is the one carve-out that draws a spacer at all; on a camera hold it
	# is exactly the wanted answer to "why is this normally invisible?", and the sub-channel
	# identity is already on the lane header ("Cam angle").
	if bool(span.get("fields", {}).get("spacer", false)):
		return "Spacer"
	match span["kind"]:
		"particle": return "E%d" % span["emitter_index"]
		"screen": return str(span.get("fields", {}).get("screen_kind", "scr"))
		"palette": return "tint"
		"camera": return str(span.get("fields", {}).get("camera_channel", "cam")).substr(0, 3)
		"sound": return "♪"
	return ""


## A compact packed-keyframe tile tag — the mask as sub-channel initials joined by "+"
## (mask 3 → "a+p") so a coalesced keyframe reads its coalescing at a glance and a
## split/merge is visible right on the compiled tile.
func _compiled_mask_tag(mask: int) -> String:
	var tag := ""
	if mask & 1: tag += "a"
	if mask & 2: tag += ("+" if tag != "" else "") + "p"
	if mask & 4: tag += ("+" if tag != "" else "") + "z"
	return tag if tag != "" else "·"


## Vertical frame gridlines over the lanes (the tick labels + ruler band moved to
## the detached EffectFramesBar; only the through-lines that align spans to frames
## stay here). Same tick spacing as the bar, off the shared axis.
func _draw_grid() -> void:
	var step := _ruler_step()
	var max_frame: int = _score.get("max_frame", 0)
	var f := 0
	while f <= max_frame:
		var x := axis.frame_to_x(float(f))
		if x >= GUTTER_W:
			draw_line(Vector2(x, 0.0), Vector2(x, _content_h), COL_GRID, 1.0)
		f += step


## Choose a frame tick spacing (1/5/10/30/60/…) so ticks are ~48+ px apart.
func _ruler_step() -> int:
	var candidates := [1, 5, 10, 30, 60, 120, 300, 600]
	for c in candidates:
		if c * axis.pixels_per_frame >= 48.0:
			return c
	return 600


func _draw_gutter_labels() -> void:
	# Cover the full content height (not just size.y) so every lane's gutter is
	# painted even when the control is laid out shorter than its content.
	var gutter_h := maxf(size.y, _content_h)
	draw_rect(Rect2(0.0, 0.0, GUTTER_W, gutter_h), COL_GUTTER)
	var font := get_theme_default_font()
	if not font:
		return
	# Lanes WITH S/M buttons narrow their label to the left of the 2 buttons + pads so
	# it never runs under them; camera lanes (no buttons) get the full gutter width.
	var full_w := GUTTER_W - 10.0
	var button_w := full_w - (BTN_SIZE * 2.0 + BTN_PAD * 3.0)
	for row in _lane_rows:
		var r: Rect2 = row["rect"]
		var lane_id: String = row["lane"]["id"]
		var has_buttons: bool = Model.has_mute_controls(row["lane"]["kind"])
		# Camera has no S/M and never silences, so its label never dims.
		var dim := has_buttons and is_lane_silenced(lane_id)
		var ink: Color = COL_TEXT_SILENCED if dim else COL_TEXT
		draw_string(font, Vector2(6.0, r.position.y + LANE_H - 7.0),
			row["lane"]["label"], HORIZONTAL_ALIGNMENT_LEFT,
			button_w if has_buttons else full_w, 11, ink)
	_draw_lane_buttons(font)


## Paint each lane's Solo/Mute buttons over the gutter fill, off the same hit-rects
## the router uses. Idle = a dim glyph outline; an active mute glows amber, an active
## solo green (a filled chip). Drawn after the labels so the chips sit on top.
func _draw_lane_buttons(font) -> void:
	for btn in _lane_button_rects:
		var rect: Rect2 = btn["rect"]
		var is_solo: bool = btn["kind"] == "solo"
		var on: bool = _soloed.has(btn["lane_id"]) if is_solo else _muted.has(btn["lane_id"])
		var glyph: String = "S" if is_solo else "M"
		if on:
			var fill: Color = COL_SOLO_ON if is_solo else COL_MUTE_ON
			draw_rect(rect, fill)
			if font:
				draw_string(font, rect.position + Vector2(4.0, BTN_SIZE - 3.0),
					glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.06, 0.07, 0.09))
		else:
			draw_rect(rect, COL_BTN_IDLE, false, 1.0)
			if font:
				draw_string(font, rect.position + Vector2(4.0, BTN_SIZE - 3.0),
					glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_BTN_IDLE)


## The loop region as a full-height translucent band across the lanes (ADR-0090), with a
## brighter rule on each boundary. Low alpha so the spans under it stay legible; clamped to
## the frame area (never over the gutter). No band when no region is set.
## The global "Time scale" pacing lane (#270, ADR-0093): the bottom strip + its two slowness
## bands, each a filled swell whose height is (value-2)/8 (EffectScoreModel.pacing_norm) — normal
## stretches read flat, slow-mo swells stand out. A curve whose enable bit is off is still drawn,
## but greyed (you see the authored shape without it acting). Mirrors _draw_ghost_energy.
func _draw_pacing_bands() -> void:
	if _pacing_lane_rect.size.y <= 0.0:
		return
	# The strip background (right of the gutter only) + a gutter label.
	draw_rect(Rect2(GUTTER_W, _pacing_lane_rect.position.y,
		_pacing_lane_rect.size.x - GUTTER_W, _pacing_lane_rect.size.y), COL_PACING_STRIP)
	var font := get_theme_default_font()
	if font:
		draw_string(font, Vector2(PAD_X, _pacing_lane_rect.position.y + PACING_LANE_H - 11.0),
			"Time scale", HORIZONTAL_ALIGNMENT_LEFT, GUTTER_W - PAD_X, 11, COL_TEXT_DIM)
	for pb in _pacing_rects:
		var enabled := bool(pb["enabled"])
		var fill: Color = COL_PACING_FILL if enabled else COL_PACING_FILL_OFF
		var line: Color = COL_PACING_LINE if enabled else COL_PACING_LINE_OFF
		_draw_pacing_swell(pb["pacing"], pb["rect"], fill, line)


## The stepped "stair" of a pacing band's top edge: one flat segment per sample at height
## EffectScoreModel.pacing_norm(value), spread evenly across the band width and clipped against
## the gutter (like the sound energy ghost). Pure — the fill, the always-present outline, and the
## guard all read the same geometry. Full-width even when every sample is normal-speed 2 (height
## 0): the stair then runs along the baseline, so the band shows *something* everywhere.
func pacing_top_points(pacing: Array, band: Rect2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := pacing.size()
	if n < 1:
		return pts
	var base_y := band.end.y - 1.0
	var span_h := base_y - (band.position.y + 1.0)
	if span_h <= 0.0:
		return pts
	var step := band.size.x / float(n)
	for i in range(n):
		var x0 := band.position.x + float(i) * step
		var x1 := band.position.x + float(i + 1) * step
		var yt := base_y - Model.pacing_norm(int(pacing[i])) * span_h
		pts.append(Vector2(maxf(GUTTER_W, x0), yt))
		pts.append(Vector2(maxf(GUTTER_W, x1), yt))
	return pts


## The slowness fill as one filled rect per raised sample column: [x0, x1) from the sample's top
## down to the baseline, for every sample above normal speed. Pure. Per-column rects (not a single
## closed polygon) because a scrolled band clamps its off-screen points to GUTTER_W — a lone polygon
## then self-touches at the gutter and fails to triangulate, silently dropping the WHOLE fill (the
## outline survives, so the band shows an outline-only stretch that flickers with scroll). Rects
## clip cleanly. Reads the same stepped geometry as the outline (pacing_top_points, paired columns).
func pacing_fill_rects(pacing: Array, band: Rect2) -> Array:
	var rects: Array = []
	var top := pacing_top_points(pacing, band)
	var base_y := band.end.y - 1.0
	var i := 0
	while i + 1 < top.size():
		var x0 := top[i].x
		var x1 := top[i + 1].x
		var yt := top[i].y
		if x1 - x0 > 0.05 and yt < base_y - 0.5:
			rects.append(Rect2(x0, yt, x1 - x0, base_y - yt))
		i += 2
	return rects


## Draw one pacing band: the slowness fill swelling up from the baseline (only where a sample slows
## time, value > 2) UNDER an always-present outline of the curve top. The outline never collapses —
## through normal-speed stretches it lies flat on the baseline, so the band is legible everywhere
## (ADR-0093 revision). Fill and outline read the same stepped geometry (pacing_top_points).
func _draw_pacing_swell(pacing: Array, band: Rect2, fill_col: Color, line_col: Color) -> void:
	var top := pacing_top_points(pacing, band)
	if top.size() < 2:
		return
	# Fill: one rect per raised column — robust to horizontal-scroll clamping (see pacing_fill_rects).
	for r in pacing_fill_rects(pacing, band):
		draw_rect(r, fill_col)
	# Outline: the always-present curve top, so a flat-2 band still reads as a baseline line.
	draw_polyline(top, line_col, 1.0, true)


func _draw_loop_band() -> void:
	var r := loop_region_rect()
	if r.size == Vector2.ZERO:
		return
	var left: float = maxf(GUTTER_W, r.position.x)
	var right: float = maxf(GUTTER_W, r.end.x)
	if right <= left:
		return
	draw_rect(Rect2(left, 0.0, right - left, size.y), COL_LOOP_BAND)
	# Boundary rules (only where they fall inside the frame area).
	if r.position.x >= GUTTER_W:
		draw_line(Vector2(r.position.x, 0.0), Vector2(r.position.x, size.y), COL_LOOP_EDGE, 1.5)
	if r.end.x >= GUTTER_W:
		draw_line(Vector2(r.end.x, 0.0), Vector2(r.end.x, size.y), COL_LOOP_EDGE, 1.5)


func _draw_playhead() -> void:
	# The playhead LINE runs the full lane height here; the triangle marker lives on
	# the detached frames bar above (one head, drawn where the frame labels are).
	var x := axis.frame_to_x(float(_playhead))
	if x < GUTTER_W:
		return
	draw_line(Vector2(x, 0.0), Vector2(x, size.y), COL_PLAYHEAD, 1.5)


## The derived effect-end stop line — a full-height red rule at the frame the real
## engine reaps the cast. Everything drawn to its right (dimmed spans) never plays.
func _draw_end_marker() -> void:
	if _end_frame <= 0:
		return
	var x := axis.frame_to_x(float(_end_frame))
	if x < GUTTER_W:
		return
	draw_line(Vector2(x, 0.0), Vector2(x, size.y), COL_END, 1.5)


## The phase-boundary markers to draw on the time axis (#271 follow-up): one per phase section,
## its absolute START frame + label, in phase order. Pure — reads the projected score, so the
## draw and any test agree on where phase 1 / for-each / phase 2 begin.
func phase_boundaries() -> Array:
	var out: Array = []
	for section in _score.get("phases", []):
		out.append({"frame": int(section.get("start", 0)), "label": String(section.get("label", ""))})
	return out


## Draw a vertical boundary line + label at each phase start, spanning the full content height,
## so phase 1 / for-each / phase 2 transitions read at a glance across every lane (previously a
## 5%-alpha strip on the header row only). Frame 0 (phase 1) sits under the gutter — its line is
## skipped, but its label rides the frame area's left edge. Each label gets a small dark chip so
## it stays legible over lanes and spans.
func _draw_phase_boundaries() -> void:
	var font := get_theme_default_font()
	for b in phase_boundaries():
		var x := axis.frame_to_x(float(int(b["frame"])))
		var label_x := x
		if x >= GUTTER_W:
			draw_line(Vector2(x, 0.0), Vector2(x, _content_h), COL_PHASE_BOUNDARY, 1.0)
		else:
			label_x = GUTTER_W   # phase 1's line is under the gutter; ride its label at the edge
		if font:
			var label := String(b["label"])
			var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
			var lx := label_x + 3.0
			draw_rect(Rect2(lx - 2.0, 1.0, tw + 4.0, 12.0),
				Color(COL_BG.r, COL_BG.g, COL_BG.b, 0.78))
			draw_string(font, Vector2(lx, 11.0), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COL_PHASE_BOUNDARY)
