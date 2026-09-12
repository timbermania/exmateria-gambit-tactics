extends Control
## The FEDS pair **lane panel** (ADR-0085 amendment 2026-08-11) — the pair editor's
## page-level navigator + structure view, replacing the rejected inspector-hosted
## micro-strip (FedsPairStrip). Built on the EffectScoreTimeline idiom: 24px lanes,
## a ~124px label gutter, a real detached ruler band carrying the tick→seconds tell,
## and collapsible per-track sections.
##
## Lane taxonomy is DATA-DRIVEN (one note lane per track + one lane per opcode
## *kind* present — absent kinds draw no lane); loops FOLD by default with a
## per-loop wind/unwind toggle that unrolls the body in place (bounded by the
## ghost-pip caps — SoundGhostProjector.MAX_PIPS / the 30 s render ceiling — so a
## runaway Repeat cannot flood the lane) plus hover-peek on the folded badge.
## Opcodes render as TYPED CHIPS: a short fixed-width code in-lane, the full
## opcode name + params on hover — the cure for the tick-0 auto-width overdraw.
##
## The panel NAVIGATES; the F1 inspector EDITS (select → the existing rows). It
## renders a FedsPairModel pair_view verbatim — no bank access, no re-decode.
## No per-lane solo/mute (a concern-lane is not an audio channel). No class_name
## (ADR-0004).
##
## FRAME-AXIS PROJECTION (ADR-0085 amendment 2026-08-11): the panel is an
## INSPECTION surface that projects onto the effect timeline's shared
## `TimelineAxis` OBJECT (the FramesBar pattern) — one (base_x, ppf, scroll) for
## the whole band, so a sound's events line up with the flash/shake/palette lanes
## below. Placement is `axis.frame_to_x(fire + round(seconds × 30))`, seconds
## integrated by the same tempo math the ghost pips use. The tick/tempo axis
## survives as the ruler's tick·seconds label and as the numeric edit unit —
## no edit happens on the axis (projection, not composition).

const SoundGhostProjector = preload("res://src/effects/studio/SoundGhostProjector.gd")
const Semantics = preload("res://src/effects/studio/FedsParamSemantics.gd")
const Verdicts = preload("res://src/effects/studio/FedsOpcodeVerdicts.gd")
const TimelineAxis = preload("res://src/effects/studio/TimelineAxis.gd")
const Catalog = preload("res://src/effects/studio/FedsOpcodeCatalog.gd")

## A note bar / opcode chip was clicked: route to the F1 inspector's rows for the
## edit (decision 6 — lane navigates, inspector edits). Carries the track ordinal
## and the DECODED event index (the pair view's event_index), which is stable
## across ghost copies — clicking an unrolled copy selects the authored event.
signal event_selected(track_idx: int, event_index: int)

## A right-click resolved to a byte boundary in the pair: the panel COMPOSES as well
## as navigates (ADR-0085 amendment 2026-08-18b §2, superseding decision 6's
## "the panel NAVIGATES"). Carries the resolved context — see `context_at` — so the
## page can name what it resolved to before offering a verb.
signal pair_context_requested(ctx: Dictionary)

## A DRAG on the lane (ADR-0085 amendment 2026-08-19b §6): the three gestures — a note bar's
## body (move), its end grips (resize) and a drag inside a rest (paint) — reported as ticks,
## never as pixels. `pair_drag_started` opens the undo coalesce, every `pair_dragged` carries
## one motion's whole payload (the grab's address plus what it wants written), and
## `pair_drag_ended` closes the bracket, so ONE drag is ONE undo.
signal pair_drag_started(drag: Dictionary)
signal pair_dragged(drag: Dictionary)
signal pair_drag_ended()

const GUTTER_W: float = 124.0
const PAD_X: float = 8.0
const NOOP_TELL_H: float = 12.0  # the per-track A/B verdict row under a track's band
const JOINT_BAND_H: float = 40.0 # the joint (mixed-pair) energy waveform band
const HEADER_H: float = 18.0
const RULER_H: float = 18.0
const SECTION_H: float = 20.0
const LANE_H: float = 24.0
const LANE_GAP: float = 2.0
const NOTE_BAR_H: float = 16.0   # fixed — in LANES mode pitch is a label, never an axis

# --- The KEY ROLL (ADR-0085 amendment 2026-08-21d) --------------------------
# An opt-in second reading of the TIME lane: 12 fixed rows of `relative_key` plus a
# 13th Rest row, on the pair's OWN axis. Octave-agnostic on purpose — octave is set by
# the Octave / RaiseOctave / LowerOctave opcodes and read from the Opcodes lane's
# Oct3/Oct5 chips, so putting it on Y would encode an opcode's effect into the note
# lane's geometry, which is the "overlaying event types" decision 5 rejects. It also
# makes drag-to-pitch a one-byte `note_key` patch with NO octave boundary to cross.
const ROLL_KEYS: int = 12          # C..B, the note byte's key field
const ROLL_REST_ROW: int = 12      # the 13th row: authored silence, below the lowest pitch
const ROLL_ROWS: int = 13
const ROLL_ROW_H: float = 12.0
const ROLL_BAR_H: float = 10.0     # 1 px of air above and below, so two rows never touch
const ROLL_BADGE_W: float = 68.0   # the [ Lanes | Roll ] header chip — two words + a rule
# PITCH ASCENDS UPWARD, like every keyboard and every piano roll: row 0 is B, row 11 is
# C, and `roll_row` inverts. Row index is therefore 11 − relative_key, not relative_key
# — the accidental striping below only reads as a keyboard in that orientation.
# Spelled with "#", not "♯", to match FedsPairModel._NOTE_NAMES and the inspector's
# "Note key" dropdown: the row's name and the bar's label sit two inches apart and would
# otherwise disagree about how to spell the same key.
const ROLL_KEY_NAMES := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
const ROLL_ACCIDENTAL := [false, true, false, true, false, false, true, false, true,
		false, true, false]
## The roll's zoom ceiling. It does NOT share the editor band's axis, so it does not
## inherit TimelineAxis.MAX_PPF (40) — which is exactly the ceiling the crammed-notes
## complaint was already sitting at. Fit-to-pair wants ~108 px/frame on the median pair.
const ROLL_MAX_PPF: float = 4000.0
# ADR-0095 §1's grab band, transferred by 19b §6: 9 px CENTRED on the boundary, so grabbing
# either side of the line writes the same number. Capped at a quarter of the narrower of the
# two bars it straddles — this lane's bars host TWO gestures (the body moves, the edge
# resizes) where a colour tile hosts one, so a full-width band on a 6 px bar would swallow
# the body drag entirely. Below `GRIP_MIN_HALF` the bar has no room for two gestures at all
# and draws no grip: zoom in, or use the menu row, which is zoom-independent by design.
const GRIP_W: float = 9.0
const GRIP_MIN_HALF: float = 1.5
# How far the cursor travels before a press becomes a DRAG rather than a click. Below it the
# gesture is still a selection, so click-to-inspect survives a shaky hand.
const DRAG_THRESHOLD: float = 3.0
# Typed chip: fixed width, detail on hover. 44 px (= BADGE_W) rather than the
# original 34 because every chip now leads with its stream ordinal (ADR-0085
# 2026-08-18b §6) and a two-digit prefix does not fit in 34 at font size 9.
const CHIP_W: float = 44.0
const CHIP_H: float = 16.0
const CHIP_ROW_GAP: float = 2.0  # breathing room between chips, in-row and between rows
const BADGE_W: float = 44.0      # the ×N wind/unwind toggle chip on a loop bracket
const BADGE_H: float = 16.0
const MIN_PANEL_H: float = 90.0
const CONTENT_PAD_Y: float = 6.0
# Per-track energy band (ADR-0085 amendment 2026-08-12 §3): a taller strip under each
# track's lanes carrying the offline-rendered RMS swell on the shared frame axis, so
# the swell sits directly beneath the opcodes that cause it — the empirical ground
# truth for the §2 verdicts.
const ENERGY_BAND_H: float = 34.0

# Unroll bounds: REUSE the ghost-pip caps (ADR-0085 — the editor does not invent
# its own ceiling): at most MAX_PIPS unrolled event copies panel-wide, and never
# past the 30 s render ceiling.
const MAX_UNROLL_COPIES: int = SoundGhostProjector.MAX_PIPS
const MAX_UNROLL_SECONDS: float = \
		float(SoundGhostProjector.MAX_RENDER_FRAMES) / SoundGhostProjector.EFFECT_FPS

# Lane order within a track section; only kinds PRESENT in the track are drawn.
# Lane kinds. "time" is the SPAN lane (ADR-0085 2026-08-18c §5) — one bar per span,
# three fills; "structure" carries AUTHORED bytes (the EndBar / Coda / Repeat chips
# the composer wrote); "flow" carries DERIVED SPANS — a loop's bracket, and the
# phantom NoEnd of a stub track. Nothing on the flow lane is a byte, which is why
# a phantom can live there without the structure lane ever lying about what was
# written (ADR-0085 2026-08-18).
#
# 18b's "notes" / "hold" / "rest" trio collapsed into "time": it drew E317's ONE
# 160-tick C as a 16-tick bar on Notes plus an unrelated-looking Fermata chip on
# Holds, which is the complaint §5 raised about Fermata sitting beside Octave, moved
# one lane over rather than fixed.
const LANE_ORDER := ["time", "opcode", "tempo", "structure", "flow"]
const LANE_LABELS := {
	"time": "Time", "opcode": "Opcodes",
	"tempo": "Tempo", "structure": "Structure", "flow": "Flow",
}
const _TRACK_LETTERS := ["A", "B"]

# Typed-chip short codes for the common runtime-table labels; unknowns fall back
# to "?XX" and everything else to the label's first 3 chars. The chip stays fixed
# width regardless — the full name + params live on the hover tooltip.
const CHIP_CODES := {
	"Instrument": "Ins", "Octave": "Oct", "OctaveUp": "Oc+", "OctaveDown": "Oc-",
	"Dynamics": "Dyn", "Repeat": "Rep", "Coda": "Cda", "EndBar": "End",
	"Fermata": "Fer", "Tempo": "Tmp", "TempoSlide": "TmS", "Rest": "Rst",
	"Hold": "Hld", "PitchBendRel": "PBd", "Noise_EnableAndClock": "Noi",
}

# Palette (matches the timeline's dark authoring surface).
const COL_BG := Color(0.09, 0.10, 0.13)
const COL_GUTTER := Color(0.12, 0.13, 0.17)
const COL_SECTION := Color(0.18, 0.20, 0.27)
const COL_LANE_A := Color(0.11, 0.12, 0.16)
const COL_LANE_B := Color(0.13, 0.14, 0.18)
const COL_TEXT := Color(0.78, 0.82, 0.90)
const COL_TEXT_DIM := Color(0.55, 0.60, 0.70)
const COL_RULER := Color(0.5, 0.5, 0.55, 0.9)
# Per-frame orientation grid (ADR-0085 amendment 2026-08-12). Mirrors
# EffectScoreTimeline.COL_GRID (α0.05) but sits at α0.12 — the panel band is
# shorter, so its lines need to read a touch stronger to peg a chip in time.
const COL_GRID := Color(1, 1, 1, 0.12)
# The time lane's three fills (ADR-0085 2026-08-18c §5), the arrangement `fft-plugin`
# already ships (FFTTrackLaneView.cpp:1201-1223): blue is the note's own delta_time,
# amber the sounding time a Fermata adds butted against it, grey a rest span. A rest
# is DRAWN, not left as empty lane — it is authored silence FFT writes 87,793 times
# and the author will want to click it, inspect it and turn it back into a note.
const COL_BAR := Color(114.0 / 255.0, 178.0 / 255.0, 255.0 / 255.0, 0.9)
# Octave TINT (ADR-0085 amendment 2026-08-21c): the note fill carries its octave as a
# lightness step on the ONE note hue. Octave is ordered data, so it gets a sequential
# scale, not ten categorical hues that would fight the blue/amber/grey the lane already
# speaks. The ramp is GLOBAL — octave n is the same shade in every track — because 53%
# of tracks use a single octave and none uses more than five, so a per-track ramp would
# make the same shade mean different things two tracks apart for no separation gained.
# OCT_MID lands exactly on COL_BAR: octave 4 is 24.3% of the corpus, so the panel's
# commonest note keeps the colour it has always had.
const OCT_LO := 0
const OCT_MID := 4
const OCT_HI := 9
const COL_OCT_FLOOR := Color(0.05, 0.09, 0.18, 0.9)   # what the low octaves darken toward
const COL_OCT_CEIL := Color(1.0, 1.0, 1.0, 0.9)       # what the high octaves lighten toward
const OCT_DARKEN := 0.74   # how far octave 0 travels toward the floor
const OCT_LIGHTEN := 0.66  # how far octave 9 travels toward the ceiling
const COL_BAR_FERMATA := Color(255.0 / 255.0, 196.0 / 255.0, 92.0 / 255.0, 0.9)
const COL_BAR_REST := Color(110.0 / 255.0, 116.0 / 255.0, 128.0 / 255.0, 0.9)
const COL_CHIP := Color(0.8, 0.7, 0.4, 0.9)
const COL_CHIP_STRUCT := Color(0.6, 0.6, 0.65, 0.9)
const COL_CHIP_TEMPO := Color(0.55, 0.8, 0.6, 0.9)
const COL_BRACKET := Color(0.9, 0.6, 0.3, 0.9)
const COL_STUB := Color(0.9, 0.45, 0.35, 0.9)
# BORROWED (ADR-0085 2026-08-18): bytes this track did not author — the flow-through
# a stub runs on into. A SECOND, INDEPENDENT axis from `ghost` (an unrolled copy of
# an authored loop body): dim means "a copy", this violet means "not this track's
# bytes". They compose — a dimmed violet item is a copy of borrowed bytes, which is
# exactly what a loop inside a borrowed span produces.
const COL_FLOWED := Color(0.72, 0.55, 0.95, 0.95)
# The NoEnd phantom's bracket + badge: a derived span with NO byte behind it at all.
const COL_PHANTOM := Color(0.72, 0.55, 0.95, 0.85)
# Opcode-honesty verdict tints (ADR-0085 amendment 2026-08-12 §2): chips paint by
# verdict so the author reads the code as a map — Live is heard (green), Pre-arm is
# staged (amber), Inert writes nothing (dim grey), Structural shapes flow (blue-grey).
const COL_VERDICT := {
	"Live": Color(0.5, 0.85, 0.55, 0.95),
	"Pre-arm": Color(0.88, 0.72, 0.38, 0.92),
	"Inert": Color(0.5, 0.5, 0.55, 0.55),
	"Structural": Color(0.58, 0.62, 0.72, 0.9),
	# Live-by-proxy (ADR-0085 2026-08-12 §2): a global-scope opcode that colours
	# another voice — its own distinct tint, NEVER hatched. Teal reads apart from the
	# green Live and the amber Pre-arm without collapsing into either.
	"Live-by-proxy": Color(0.42, 0.82, 0.86, 0.95),
}
# A Muted chip/note KEEPS its hue (it falls through COL_VERDICT to its kind colour)
# and gets 45° diagonal hatch lines over it (§7 — the "struck out / does nothing"
# read, distinct from the plain-dim Inert tint). The faint gray-zone tell is a
# dotted, dimmed outline + a small ≈ — never a hatch (we do not over-claim silence).
const COL_HATCH := Color(0.05, 0.06, 0.08, 0.85)
const COL_FAINT := Color(0.62, 0.66, 0.74, 0.7)
const HATCH_STEP: float = 5.0   # px between diagonal hatch lines
const COL_SELECT := Color(1.0, 1.0, 1.0)
const COL_PLAYHEAD := Color(1.0, 0.85, 0.25)   # matches the frames bar / timeline
const COL_ENERGY_BG := Color(0.06, 0.07, 0.09, 0.85)   # the per-track energy band trough
const COL_ENERGY := Color(0.45, 0.72, 0.95, 0.85)      # the RMS swell fill
# No-op prune A/B tell tints (ADR-0085 amendment 2026-08-12 §4): the three a-priori
# tiers — inert ✓ (the no-ops truly do nothing), faint ≈ (a sub-audible floor leaks),
# changed ✗ (the classifier over-claimed — a real bug).
const COL_NOOP := {
	"inert": Color(0.5, 0.85, 0.55, 0.95),
	"faint": Color(0.9, 0.78, 0.4, 0.95),
	"changed": Color(0.95, 0.45, 0.45, 0.95),
}
const GHOST_COPY_A: float = 0.45   # unrolled loop copies draw dimmer than authored events
# The grip's ink: a translucent wash so the bar's own verdict hue still reads under it, and a
# hairline ON the boundary so the author can see WHICH number the band writes.
# The span BOUNDARY hairline (2026-08-21c). Near-black and opaque, so two neighbouring
# bars of the same fill stop being one unbroken rectangle.
const COL_SPAN_EDGE := Color(0.04, 0.05, 0.08, 0.95)
# The roll's keyboard: accidentals (C♯ D♯ F♯ G♯ A♯) striped darker, so the rows read as
# black keys rather than as an arbitrary 12-way split. The Rest row takes its own shade —
# it is not a pitch, and shading it like one would make silence look like a note you
# cannot name.
const COL_ROLL_NATURAL := Color(0.145, 0.155, 0.195)
const COL_ROLL_ACCIDENTAL := Color(0.085, 0.095, 0.125)
const COL_ROLL_REST_ROW := Color(0.115, 0.115, 0.135)
const COL_ROLL_RULE := Color(1.0, 1.0, 1.0, 0.045)
const COL_GRIP := Color(0.95, 0.95, 1.0, 0.22)
const COL_GRIP_LINE := Color(0.95, 0.95, 1.0, 0.8)

var _view: Dictionary = {}
var _unwound: Dictionary = {}    # "track:loop_index" -> true (per-loop independent)
var _collapsed: Dictionary = {}  # track ordinal -> true
var _selected: Dictionary = {}   # {"track": int, "event_index": int}
# The bound EffectScoreTimeline whose axis OBJECT this panel projects onto (the
# FramesBar pattern). Re-read each layout — load_score re-configures it, so the
# three params are never cached here. null = unbound (tests): a private default
# axis stands in so the pure layout stays exercisable.
var _tl = null
var _own_axis = null
# The KEY ROLL's mode + its OWN axis (amendment 2026-08-21d). Per-pair and defaulting
# OFF: the roll is a second reading of one lane, not a replacement, and decision 5 stays
# intact precisely because it is opt-in rather than quietly overwritten. `_roll_fitted`
# is the once-per-open fit — after it, the author's zoom/pan is theirs to keep.
var _roll: bool = false
var _roll_axis = null
var _roll_fitted: bool = false
# The pair's tick-0 anchor on the frame axis: {"frame": int, "source": String}
# (source: "origin"|"selected"|"first"|"orphan"). Resolved by the page.
var _anchor: Dictionary = {}
var _panning: bool = false
var _pan_last_x: float = 0.0
# The armed drag: what a LMB press resolved to (see `drag_target`), or {}. `_drag_live` flips
# once the cursor has passed DRAG_THRESHOLD, which is when the coalesce bracket opens.
var _drag: Dictionary = {}
var _drag_live: bool = false
var _drag_last: Dictionary = {}   # the last motion EMITTED — the key drag's no-op filter


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


## Bind the timeline whose shared TimelineAxis this panel projects onto. Zoom /
## pan / playhead become unified with the whole band; the panel refits on axis
## changes (row-wrap depends on zoom) and redraws on playhead moves.
func bind_timeline(tl) -> void:
	_tl = tl
	if _tl:
		_tl.axis_changed.connect(_refit)
		_tl.playhead_changed.connect(queue_redraw)
	_refit()


## Frame-axis §6: the shared playhead's x on this panel — the bound timeline's
## playhead through the shared axis. DRAW-ONLY at v1 (the panel never seeks);
## -1.0 when unbound (nothing to draw).
func _playhead_x() -> float:
	if _tl == null:
		return -1.0
	# The roll's axis is PAIR-LOCAL (its origin is the pair's tick 0, not effect frame 0),
	# so the band's absolute playhead frame has to be rebased before it projects.
	if _roll:
		return _axis_obj().frame_to_x(
				float(_tl.get_playhead()) - float(int(_anchor.get("frame", 0))))
	return _axis_obj().frame_to_x(float(_tl.get_playhead()))


## The live axis to project on: the bound timeline's OBJECT, else the private
## default (unbound/tests). Never cache the returned object's params.
func _axis_obj():
	if _roll:
		return _roll_axis_obj()
	if _tl:
		return _tl.axis
	if _own_axis == null:
		_own_axis = TimelineAxis.new()
		_own_axis.configure(GUTTER_W + PAD_X, TimelineAxis.DEFAULT_PPF)
	return _own_axis


## The KEY ROLL's own axis: same transform, its OWN zoom band and its own scroll. It is
## not the band's axis on purpose — "zoom in" was never available on the shared one
## (the crammed-notes complaint was taken AT TimelineAxis.MAX_PPF), and a roll fitted to
## one pair has no business dragging the frames bar and the score along with it.
func _roll_axis_obj():
	if _roll_axis == null:
		_roll_axis = TimelineAxis.new()
		_roll_axis.set_zoom_band(TimelineAxis.MIN_PPF, ROLL_MAX_PPF)
		_roll_axis.configure(GUTTER_W + PAD_X, TimelineAxis.DEFAULT_PPF)
	return _roll_axis


## Load a FedsPairModel pair_view. Re-loading the SAME pair (a live re-derive after
## an edit) preserves the session wind/collapse/selection state; a different pair opens
## UNWOUND — every `Rep` bracket unrolled in place and every stub's `Flow` phantom
## revealed (the 2026-08-19d reversal of ADR-0085 decision 3's fold-default).
func set_view(view: Dictionary) -> void:
	var incoming := view if view != null else {}
	if int(incoming.get("pair_idx", -1)) != int(_view.get("pair_idx", -2)):
		_unwound = _unwound_keys(incoming)
		_collapsed = {}
		# The roll is PER PAIR and resets with it: its axis is fitted to one pair's length,
		# and carrying that fit onto a pair ten times longer would open on a sliver.
		_roll = false
		_roll_fitted = false
		# Slice 1 (ADR-0085 2026-08-12 §1): a NEW pair LANDS ON THE CODE — auto-select
		# track A's first event so the panel/inspector open on it, not on an empty
		# overview. Always track A, no stub fallthrough; a genuinely empty track A
		# falls back to {} (overview). A same-pair re-derive skips this branch and
		# keeps the author's live selection.
		_selected = _first_track_a_event(incoming)
	_view = incoming
	_refit()


## Track A's first decoded event as a selection ({"track": 0, "event_index": N}), or
## {} when track A carries no events (the overview fallback). "First" = the lowest
## event_index across the track's notes and command chips (decode order).
static func _first_track_a_event(view: Dictionary) -> Dictionary:
	var tracks: Array = view.get("tracks", [])
	if tracks.is_empty():
		return {}
	var a: Dictionary = tracks[0]
	var best := -1
	for n in a.get("notes", []):
		var ei := int(n.get("event_index", -1))
		if ei >= 0 and (best < 0 or ei < best):
			best = ei
	for c in a.get("commands", []):
		var ei := int(c.get("event_index", -1))
		if ei >= 0 and (best < 0 or ei < best):
			best = ei
	if best < 0:
		return {}
	return {"track": 0, "event_index": best}


func _refit() -> void:
	var w := maxf(size.x, 1.0)
	var lay := layout(_view, w, _state(), _axis_obj(), _anchor)
	# FIT TO THE PAIR, once per open (amendment 2026-08-21d §5). The whole point of the
	# roll's own axis is that the pair fills the width instead of being one squeezed inch
	# of a 600-frame effect timeline: the median pair's TIGHTEST note goes from 40 px (one
	# frame at the shared axis's ceiling) to ~108 px, and only the 15.6% of pairs still
	# holding a sub-20 px note need the zoom at all.
	if _roll and not _roll_fitted and w > GUTTER_W + PAD_X * 4.0 and not _view.is_empty():
		_fit_roll_axis(lay, w)
		_roll_fitted = true
		lay = layout(_view, w, _state(), _axis_obj(), _anchor)
	custom_minimum_size = Vector2(240.0, maxf(MIN_PANEL_H, float(lay.get("content_h", 0.0)) + CONTENT_PAD_Y))
	queue_redraw()


## Scale the roll's axis so the pair's whole length lands inside the lane field, scrolled
## back to its tick 0. `end_frame` is already pair-local in roll mode (layout anchors the
## roll at fire 0), so it IS the pair's length in frames.
func _fit_roll_axis(lay: Dictionary, w: float) -> void:
	var frames := maxf(1.0, float(int(lay.get("end_frame", 1))))
	var avail := maxf(80.0, w - GUTTER_W - PAD_X * 3.0)
	_roll_axis_obj().scroll_x = 0.0
	_roll_axis_obj().configure(GUTTER_W + PAD_X, avail / frames)


## The KEY ROLL toggle (amendment 2026-08-21d §1). Opt-in, per pair, and it re-fits on
## every entry rather than only the first — leaving a stale fit behind would make the
## second open of a roll the author already zoomed look broken.
func toggle_roll() -> void:
	_roll = not _roll
	if _roll:
		_roll_fitted = false
	_refit()


func is_roll() -> bool:
	return _roll


## The page-resolved tick-0 anchor {frame, source} for the open pair (frame-axis
## §2). A re-anchor (drill / selection change) refits so every x re-projects.
## (Named for the FIRE frame — Control already owns a native set_anchor.)
func set_fire_anchor(anchor: Dictionary) -> void:
	var incoming: Dictionary = anchor if anchor != null else {}
	if incoming == _anchor:
		return
	_anchor = incoming
	_refit()


func _state() -> Dictionary:
	return {"unwound": _unwound, "collapsed": _collapsed, "selected": _selected,
			"roll": _roll}


## The fold-state key. loop_index -1 is the track's NoEnd PHANTOM — it shares the
## loop's fold verb (`toggle_loop`), its badge and its hit-test route, so the whole
## gesture composes with zero new surface (ADR-0085 2026-08-18).
static func _loop_key(track_idx: int, loop_index: int) -> String:
	if loop_index < 0:
		return "%d:noend" % track_idx
	return "%d:%d" % [track_idx, loop_index]


func is_loop_unwound(track_idx: int, loop_index: int) -> bool:
	return _unwound.get(_loop_key(track_idx, loop_index), false)


## Per-loop wind/unwind (decision 3): reversible, independent per loop.
func toggle_loop(track_idx: int, loop_index: int) -> void:
	var key := _loop_key(track_idx, loop_index)
	if _unwound.has(key):
		_unwound.erase(key)
	else:
		_unwound[key] = true
	_refit()


## Header sugar: wind/unwind EVERY loop in the pair at once.
func set_all_unwound(on: bool) -> void:
	_unwound = _unwound_keys(_view) if on else {}
	_refit()


## Every fold key a pair has, all unwound — every loop bracket, plus each stub's NoEnd
## phantom, because "show me everything this pair actually does" includes the borrowed
## span: after the phantom it IS the part the bytes do not show. This is BOTH the
## unwind-all chip's target and the state a newly opened pair lands in, so the chip and
## the open cannot drift apart.
static func _unwound_keys(view: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var tracks: Array = view.get("tracks", [])
	for t in range(tracks.size()):
		var loops: Array = (tracks[t] as Dictionary).get("loops", [])
		for li in range(loops.size()):
			out[_loop_key(t, li)] = true
		if not (tracks[t] as Dictionary).get("flow_through", {}).is_empty():
			out[_loop_key(t, -1)] = true
	return out


func toggle_section(track_idx: int) -> void:
	_collapsed[track_idx] = not _collapsed.get(track_idx, false)
	_refit()


func is_section_collapsed(track_idx: int) -> bool:
	return _collapsed.get(track_idx, false)


func selected_event() -> Dictionary:
	return _selected


## Land the selection on one event (ADR-0085 amendment 2026-08-18b §8). A structural
## resize shifts every later `event_index`, so leaving the selection alone would make
## it silently point at a DIFFERENT event — it is recomputed by the verb, never stale.
## No signal: the page already re-renders, and this is the landing, not a click.
func select_event(track_idx: int, event_index: int) -> void:
	if track_idx < 0 or event_index < 0:
		_selected = {}
	else:
		_selected = {"track": track_idx, "event_index": event_index}
	queue_redraw()


# --- Pure layout ------------------------------------------------------------

## PURE: place every ruler mark / section header / lane row / note bar / chip /
## loop bracket for `width` pixels under `state` ({unwound, collapsed, selected}),
## PROJECTED onto `axis` (the timeline's shared TimelineAxis; null → a default
## axis for unbound panels) with the pair's tick-0 at `anchor.frame` (the
## representative firing trigger's fire frame). Placement is
## axis.frame_to_x(fire + round(seconds × EFFECT_FPS)) — the pip conversion.
## Returns {header, ruler, sections, lanes, span_bars, chips, brackets,
## total_ticks, end_frame, content_h}. Tests assert placement without pixels;
## _draw and hit_test both consume this so paint and routing never drift.
static func layout(view: Dictionary, width: float, state: Dictionary,
		axis = null, anchor: Dictionary = {}) -> Dictionary:
	if axis == null:
		axis = TimelineAxis.new()
		axis.configure(GUTTER_W + PAD_X, TimelineAxis.DEFAULT_PPF)
	var roll: bool = bool(state.get("roll", false))
	# The roll is PAIR-LOCAL: its origin is the pair's own tick 0, not the firing
	# trigger's frame. That is what lets it be fitted and zoomed independently — the
	# lanes view stays anchored at `fire` so it keeps coinciding with the score below.
	var fire := 0 if roll else int(anchor.get("frame", 0))
	var tracks: Array = view.get("tracks", [])
	var unwound: Dictionary = state.get("unwound", {})
	var collapsed: Dictionary = state.get("collapsed", {})

	# Expand each track's events under the wind state (bounded, in-place unroll).
	var budget := {"left": MAX_UNROLL_COPIES}
	var expanded: Array = []
	var total_ticks := 1
	var end_seconds := 0.0
	for t in range(tracks.size()):
		var ex := _expand_track(tracks[t], t, unwound, budget)
		expanded.append(ex)
		total_ticks = maxi(total_ticks, int(ex["end_tick"]))
		end_seconds = maxf(end_seconds, float(ex["end_seconds"]))

	var header := {
		"rect": Rect2(0.0, 0.0, width, HEADER_H),
		"text": _header_text(view, anchor),
		"unwind_all_rect": Rect2(width - BADGE_W - PAD_X, 1.0, BADGE_W, HEADER_H - 2.0),
		"all_unwound": _all_unwound(view, unwound),
		# The [Lanes|Roll] toggle, a sibling of the unwind-all chip so `hit_in`'s existing
		# header special case grows one rect rather than a second routing rule.
		"roll_rect": Rect2(width - BADGE_W - ROLL_BADGE_W - PAD_X * 2.0, 1.0,
				ROLL_BADGE_W, HEADER_H - 2.0),
		"roll": roll,
	}

	# Ruler band: quarter marks over the EFFECTIVE (wind-state) axis, each with
	# the seconds tell (linear share — a LABEL, not a clock; ADR-0085 frame-axis
	# §3), projected at the axis-derived x of that share.
	var ruler: Array = []
	var seen_ticks := {}
	for q in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var tick := int(round(q * float(total_ticks)))
		if seen_ticks.has(tick):
			continue
		seen_ticks[tick] = true
		var sec := end_seconds * float(tick) / float(total_ticks)
		ruler.append({
			"x": _sec_x(axis, fire, sec),
			"tick": tick,
			"seconds": sec,
		})

	# Per-frame orientation grid (ADR-0085 amendment 2026-08-12): full-height lines
	# at ROUND absolute frames (from frame 0, NOT `fire`) by the same _ruler_step
	# spacing the FramesBar / EffectScoreTimeline use, so they coincide pixel-for-
	# pixel with the score's _draw_grid directly below. Clipped to [GUTTER_W, width]
	# — the gutter is inert, off-screen frames are skipped. x advances ≥48 px per
	# step (the _ruler_step guarantee), so the walk always terminates.
	var grid: Array = []
	if roll:
		# The roll does not share the band's axis, so a grid at ROUND ABSOLUTE FRAMES
		# would no longer coincide with anything — it would just be lines at numbers this
		# view never says. On its own axis the honest reference is the pair's own clock,
		# so the orientation grid becomes a TICK grid (amendment 2026-08-21d §4).
		grid = _tick_grid(axis, total_ticks, end_seconds, width)
	else:
		var grid_step := _ruler_step_for(axis)
		var gf := 0
		while true:
			var gx: float = axis.frame_to_x(float(gf))
			if gx > width:
				break
			if gx >= GUTTER_W:
				grid.append({"x": gx, "frame": gf})
			gf += grid_step

	var sections: Array = []
	var lanes: Array = []
	var span_bars: Array = []
	var chips: Array = []
	var brackets: Array = []
	var energy_bands: Array = []
	var noop_tells: Array = []
	var roll_rows: Array = []
	var y := HEADER_H + RULER_H
	for t in range(tracks.size()):
		var tr: Dictionary = tracks[t]
		var ex: Dictionary = expanded[t]
		# Opcode-honesty verdicts (§2): classify the track ONCE, then paint each chip /
		# note bar by verdict and speak the Sounding/Stub tell on the section header.
		var vd: Dictionary = Verdicts.verdicts(tr)
		var letter: String = _TRACK_LETTERS[t] if t < _TRACK_LETTERS.size() else str(t)
		var label := "Track %s · %d bytes · %s" % [letter,
				int(tr.get("size_bytes", 0)), str(vd.get("track", ""))]
		# The wholly-Muted tell (§3): no note in this track ever sounds — every event
		# hatches. Said out loud on the section header, alongside the Sounding/Stub tell.
		if bool(vd.get("wholly_muted", false)):
			label += " · wholly Muted"
		# The SOURCE TELL (ADR-0085 2026-08-18): a stub's borrowed span is named on
		# the section header, always visible — the condition is never hidden behind
		# the fold. FedsPairProjector.gd:11's standing promise, kept.
		var ft: Dictionary = tr.get("flow_through", {})
		if not ft.is_empty():
			label += " · borrows Track %s's notes" % _TRACK_LETTERS[(t + 1) % 2] \
					if int(ft.get("into_track", -1)) >= 0 \
					else " · borrows the bytecode that follows"
			var bend := int(ft.get("own_pitch_bend_total", 0))
			if bend != 0:
				label += "; PitchBendRel %+d detunes" % bend
		var is_collapsed: bool = collapsed.get(t, false)
		sections.append({
			"track": t,
			"label": label,
			"stub": bool(tr.get("stub", false)),
			"collapsed": is_collapsed,
			"rect": Rect2(0.0, y, width, SECTION_H),
		})
		y += SECTION_H
		if is_collapsed:
			continue
		for kind in LANE_ORDER:
			if not _kind_present(ex, kind):
				continue
			var lane_h := LANE_H
			match kind:
				"time":
					# The ONE structural difference between the two readings: in roll mode
					# the time lane is 13 rows tall and a bar's y is its KEY, not the lane
					# centre. Everything else — chips, brackets, energy, the verdicts —
					# is the same layout re-projected onto the roll's axis.
					if roll:
						lane_h = float(ROLL_ROWS) * ROLL_ROW_H
						_place_roll_rows(t, y, width, roll_rows)
					_place_span_bars(ex["spans"], t, y, axis, fire, span_bars, vd, roll)
				"flow":
					_place_brackets(ex["brackets"], t, y, axis, fire, brackets)
				_:
					# Chips wrap to rows at their true x (amendment §5) — the lane
					# grows to hold them.
					var rows := _place_chips(ex["chips"], t, kind, y, axis, fire, chips, vd)
					lane_h += float(rows - 1) * (CHIP_H + CHIP_ROW_GAP)
			lanes.append({"track": t, "kind": kind,
					"label": LANE_LABELS.get(kind, kind), "rect": Rect2(0.0, y, width, lane_h)})
			y += lane_h + LANE_GAP
		# Per-track energy band (§3): inline under the track's lanes, on the shared
		# frame axis, when the page has rendered this track's isolated energy. The
		# swell sits directly beneath the opcodes that cause it → it corroborates the
		# §2 verdicts (a flat band means those opcodes really are inert here).
		var energy: PackedFloat32Array = tr.get("energy", PackedFloat32Array())
		if energy.size() > 0 and not roll:
			var raw_peak: float = float(tr.get("energy_raw_peak", -1.0))
			energy_bands.append(_place_energy_band(t, energy, y, width, axis, fire, raw_peak))
			y += ENERGY_BAND_H + LANE_GAP
		# The no-op prune A/B verdict (ADR-0085 amendment 2026-08-12): the active
		# corroboration of the §2 hatch — this track's no-ops pruned, the mixed pair
		# re-rendered, and the measured Δ tiered inert/faint/changed. Sits directly under
		# the track's energy band, present only once the page has run the button.
		var noop: Dictionary = tr.get("noop_ab", {})
		if not noop.is_empty() and not roll:
			noop_tells.append({
				"track": t,
				"tell": noop,
				"rect": Rect2(GUTTER_W, y, maxf(0.0, width - GUTTER_W), NOOP_TELL_H),
			})
			y += NOOP_TELL_H + LANE_GAP

	# The JOINT (mixed-pair) energy waveform — both voices together, the combined "what
	# the pair sounds like" the isolated per-track bands never showed. Present on pair-open
	# (baseline only); once the no-op A/B runs, the pruned mix overlays it so the Δ is the
	# visible gap between the two curves (ADR-0085 amendment 2026-08-12 "active corroboration").
	# THE THREE CORROBORATION ROWS ARE LANES-ONLY (amendment 2026-08-21d §4.3). The
	# per-track energy band, the no-op A/B tell and the joint mix band exist to answer
	# "is this opcode really inert" — the §2 verdict question, which is what the Opcodes
	# lane asks. The roll asks a different one: what pitch, and when. They also cost 142 px,
	# and 142 px is exactly the difference between the roll FITTING WHOLE in the band on a
	# maximised 1440 window (626 of 654 px granted) and being scrolled inside it. One click
	# back to Lanes brings all three back, unchanged.
	var joint_band: Dictionary = {}
	var jd: Dictionary = view.get("joint", {})
	if not roll and (jd.get("baseline", PackedFloat32Array()) as PackedFloat32Array).size() > 0:
		joint_band = _place_joint_band(jd, y, width, axis, fire)
		y += JOINT_BAND_H + LANE_GAP
	# The model stamps a borrowed event's owner as a GLOBAL bank track index
	# (pair_idx*2 + t), but every coordinate in this layout — lanes, chips, the
	# selection, the verbs' addresses — is PAIR-LOCAL (0/1). Map it here, once, so
	# clicking a borrowed item in pair 2 selects track 5's real event instead of
	# looking for a lane 5 that does not exist.
	_localize_owner_tracks(view, span_bars)
	_localize_owner_tracks(view, chips)
	return {
		"span_seps": _place_separators(span_bars),
		"grips": _place_grips(span_bars),
		"roll": roll,
		"roll_rows": roll_rows,
		"header": header,
		"ruler": ruler,
		"grid": grid,
		"sections": sections,
		"lanes": lanes,
		"span_bars": span_bars,
		"chips": chips,
		"brackets": brackets,
		"energy_bands": energy_bands,
		"noop_tells": noop_tells,
		"joint_band": joint_band,
		"total_ticks": total_ticks,
		"end_frame": fire + int(round(end_seconds * SoundGhostProjector.EFFECT_FPS)),
		"content_h": y,
	}


## Rewrite each item's `owner_track` from the model's GLOBAL bank index to this
## pair's local 0/1. An owner outside the pair keeps -1 — the item is then inert
## rather than pointing at a wrong lane (`crosses_pair` is dead data: 0 corpus
## occurrences, so this is a guard, not a path).
static func _localize_owner_tracks(view: Dictionary, items: Array) -> void:
	var local_of := {}
	var tracks: Array = view.get("tracks", [])
	for i in range(tracks.size()):
		local_of[int((tracks[i] as Dictionary).get("track_idx", -1))] = i
	for it in items:
		if not bool(it.get("flowed", false)):
			continue
		it["owner_track"] = int(local_of.get(int(it.get("owner_track", -1)), -1))


## One conversion, shared by every placer: integrated seconds → effect frame →
## axis pixel. The frame is FRACTIONAL (ADR-0085 amendment 2026-08-21c). It used to be
## `round(sec × fps)`, matching pair_pips' quantization so a bar's edge landed on its
## ghost pip's x — but that rounding collapsed 314 of the corpus's 6439 notes (4.9%) to
## ZERO width, where `maxf(2.0, …)` drew them as a 2 px sliver at every zoom, and pinned
## another 18.5% to one frame = 40 px at TimelineAxis.MAX_PPF, which is the panel's hard
## ceiling, not a zoom you can escape. A pip is frame-quantized by nature (pair_pips keys
## an int frame) and is a read-only coarse tell; the bar is what you click, label and
## resize — so the bar keeps the truth and the pip keeps the frame. They can now differ
## by up to half a frame: sub-pixel at the default zoom, ~20 px at the maximum, honest
## at both.
static func _sec_x(axis, fire: int, sec: float) -> float:
	return axis.frame_to_x(float(fire) + sec * SoundGhostProjector.EFFECT_FPS)


## Which of the roll's 13 rows a span sits on. PITCH ASCENDS UPWARD (row 0 is B, row 11
## is C), because the accidental striping only reads as a keyboard that way round and
## because every piano roll an author has ever used puts the high notes at the top. A
## REST takes the 13th row, below the lowest pitch — authored silence is not a pitch, and
## giving it one of the twelve would make it look like a note you cannot name.
static func roll_row(rest: bool, relative_key: int) -> int:
	if rest:
		return ROLL_REST_ROW
	return ROLL_KEYS - 1 - clampi(relative_key, 0, ROLL_KEYS - 1)


## The inverse: the `relative_key` a row writes. Out of the twelve → -1 (the Rest row is
## not a key, and a drag onto it must refuse rather than write key 12, which is the TIE
## form FFT never writes).
static func roll_key(row: int) -> int:
	if row < 0 or row >= ROLL_KEYS:
		return -1
	return ROLL_KEYS - 1 - row


## The roll's keyboard rows for one track's time lane: the striped backdrop, the gutter
## key names, and the row rects a test counts. Thirteen, always — rows never move and
## never scroll, which is the other half of why the roll is octave-agnostic.
static func _place_roll_rows(t: int, lane_y: float, width: float, out: Array) -> void:
	for r in range(ROLL_ROWS):
		var key := roll_key(r)
		out.append({
			"track": t,
			"row": r,
			"key": key,
			"rest": r == ROLL_REST_ROW,
			"label": "Rest" if key < 0 else str(ROLL_KEY_NAMES[key]),
			"accidental": key >= 0 and bool(ROLL_ACCIDENTAL[key]),
			"rect": Rect2(0.0, lane_y + float(r) * ROLL_ROW_H, width, ROLL_ROW_H),
		})


## The roll's orientation grid: lines at round TICK multiples, spaced ~48+ px apart by
## the same rule the frame grid uses. Ticks and seconds are one constant per track (the
## FEDS corpus carries zero Tempo and zero TempoSlide across all 1998 byte-owning
## tracks), so one linear conversion is exact, not merely consistent.
static func _tick_grid(axis, total_ticks: int, end_seconds: float, width: float) -> Array:
	var out: Array = []
	if total_ticks <= 0 or end_seconds <= 0.0:
		return out
	var spt := end_seconds / float(total_ticks)
	var px_per_tick: float = axis.pixels_per_frame * spt * SoundGhostProjector.EFFECT_FPS
	var step := 1536
	for c in [1, 2, 4, 8, 12, 24, 48, 96, 192, 384, 768, 1536]:
		if float(c) * px_per_tick >= 48.0:
			step = c
			break
	var tk := 0
	while tk <= total_ticks:
		var gx: float = _sec_x(axis, 0, spt * float(tk))
		if gx > width:
			break
		if gx >= GUTTER_W:
			out.append({"x": gx, "tick": tk, "frame": -1})
		tk += step
	return out


## Frame tick spacing (1/5/10/30/…) so grid lines land ~48+ px apart — the PURE
## mirror of EffectFramesBar._ruler_step(axis) / EffectScoreTimeline._ruler_step,
## taking `axis` as a param since layout() never reads self.axis (ADR-0004 purity).
static func _ruler_step_for(axis) -> int:
	for c in [1, 5, 10, 30, 60, 120, 300, 600]:
		if float(c) * axis.pixels_per_frame >= 48.0:
			return c
	return 600


static func _header_text(view: Dictionary, anchor: Dictionary = {}) -> String:
	var used: Array = view.get("used_by_containers", [])
	var parts: Array = []
	for u in used:
		var n := int(u.get("used_by", 0))
		parts.append("container %d → %d trigger%s" % [int(u.get("index", -1)), n,
				"" if n == 1 else "s"])
	var provenance: String = "used by " + ", ".join(parts) if not parts.is_empty() \
			else "no container (orphan pair)"
	var text := "FEDS pair %d — %s" % [int(view.get("pair_idx", -1)), provenance]
	# Frame-axis §2 orphan tell: no firing trigger anchors this pair, so its
	# tick-0 sits at frame 0 by default — said out loud, never silent.
	if str(anchor.get("source", "")) == "orphan":
		text += " · no firing trigger — anchored at frame 0"
	return text


static func _all_unwound(view: Dictionary, unwound: Dictionary) -> bool:
	var tracks: Array = view.get("tracks", [])
	var any := false
	for t in range(tracks.size()):
		var loops: Array = (tracks[t] as Dictionary).get("loops", [])
		for li in range(loops.size()):
			any = true
			if not unwound.get(_loop_key(t, li), false):
				return false
		if not (tracks[t] as Dictionary).get("flow_through", {}).is_empty():
			any = true
			if not unwound.get(_loop_key(t, -1), false):
				return false
	return any


## A lane exists iff the EXPANSION will actually draw something on it. Reading the
## expansion (not the raw track) is what lets borrowed content pull in the lanes it
## needs — a stub whose only authored byte is a Rest still gets a Notes lane once its
## NoEnd is unfolded — and what puts the phantom on the Flow lane of a track that
## never loops.
static func _kind_present(ex: Dictionary, kind: String) -> bool:
	match kind:
		"time":
			return not (ex["spans"] as Array).is_empty()
		"flow":
			return not (ex["brackets"] as Array).is_empty()
	for pc in ex["chips"]:
		if str((pc["src"] as Dictionary).get("kind", "")) == kind:
			return true
	return false


## §6 (ADR-0085 2026-08-18b): the ordinal an item DISPLAYS — its position in the
## track's ONE decode-order stream, notes and commands sharing the numbering, so the
## pair reads as a single ordered list across lanes and a gappy run on one lane is
## the tell that something else sits between.
##
## A borrowed or ghost copy wears its OWNER's number, never a fresh one: a borrowed
## `Ins10` is the other track's item 0 heard on this voice, and clicking it already
## routes to (owner_track, owner_event_index) — any other number would contradict
## the click. On a stub's lane the run therefore reads out of order and gappy ("one
## of mine, then someone else's list"), which the violet borrowed outline separates.
static func display_ordinal(item: Dictionary) -> int:
	if bool(item.get("flowed", false)):
		var owner := int(item.get("owner_event_index", -1))
		if owner >= 0:
			return owner
	return int(item.get("event_index", -1))


## What a chip / span bar actually DRAWS: the ordinal, then the type code (or the
## span's key+velocity label, or "Rest"). Split out so the ordinal stays a first-class
## datum on the layout item rather than being baked into `code` / `label`.
static func chip_text(chip: Dictionary) -> String:
	return _ordinal_prefixed(int(chip.get("ordinal", -1)), str(chip.get("code", "")))


static func span_text(bar: Dictionary) -> String:
	return _ordinal_prefixed(int(bar.get("ordinal", -1)), str(bar.get("label", "")))


static func _ordinal_prefixed(ordinal: int, body: String) -> String:
	return body if ordinal < 0 else "%d %s" % [ordinal, body]


## The one velocity 97.3% of the corpus shares, and therefore the one worth NOT printing.
const CORPUS_VELOCITY := 96


static func _note_label(key_label: String, velocity: int) -> String:
	return key_label if velocity == CORPUS_VELOCITY \
			else "%s · v%d" % [key_label, velocity]


## The label ELISION LADDER (ADR-0085 amendment 2026-08-21c), widest rung first. A bar
## draws the FIRST rung that fits inside its OWN rect — whole tokens only. The old
## `maxf(r.size.x - 2.0, 40.0)` clip let any bar under 42 px draw its label wider than
## itself, straight over its neighbour; simply removing that floor would move the clip
## inside the bar but still cut mid-token, and "8 C" reads as the key C rather than as a
## truncation. Dropping whole tokens never lies.
##
## PITCH goes before the ORDINAL because the Opcodes lane directly below reprints every
## ordinal in a fixed-width chip at the same x (2026-08-18b §6), so the ordinal is
## recoverable by looking down one lane; the pitch is recoverable from nowhere else on
## the panel.
static func span_text_rungs(bar: Dictionary, roll: bool = false) -> Array:
	if roll:
		return _roll_text_rungs(bar)
	var ordinal := int(bar.get("ordinal", -1))
	var full := _ordinal_prefixed(ordinal, str(bar.get("label", "")))
	var keyed := _ordinal_prefixed(ordinal, str(bar.get("key_label", bar.get("label", ""))))
	var out: Array = [full]
	if keyed != full:
		out.append(keyed)
	if ordinal >= 0:
		out.append(str(ordinal))
	out.append("")   # the last rung is always silence — a bar too narrow for one glyph
	return out


## The ROLL's ladder (amendment 2026-08-21d §4.1). The row already says the key, so
## reprinting "C3" would spend the bar on a fact the geometry states better; what the bar
## prints instead is the OCTAVE DIGIT — the half of the pitch the octave-agnostic Y axis
## deliberately does not carry.
##
## A WIDE bar still prints the whole pitch ("8 C3"), because there is room and "C3" reads
## instantly while a bare digit beside an ordinal ("8 3") does not. The elision is where
## the two ladders differ, and each drops the token that is most recoverable elsewhere:
##
##   8 C3 · v0  →  8 C3  →  8 3  →  3  →  (silence)
##
## Velocity goes first either way (97.3% of the corpus is 96). Then the KEY goes, because
## the ROW says it — that is the whole point of the roll, and reprinting it is the one
## token the geometry states better. Then the ORDINAL goes and the octave digit is what
## survives: the Opcodes lane directly below numbers this track's events at the same x, so
## an ordinal is recoverable by looking down one lane — but it only carries an Oct chip
## where an Octave / RaiseOctave / LowerOctave opcode actually FIRES, so a note between two
## of them has its octave recoverable from nowhere else on the panel.
##
## A rest lives on the Rest row, so "Rest" is redundant there exactly as the key is: its
## ladder is the ordinal alone.
static func _roll_text_rungs(bar: Dictionary) -> Array:
	var ordinal := int(bar.get("ordinal", -1))
	if bool(bar.get("rest", false)):
		var rout: Array = []
		if ordinal >= 0:
			rout.append(str(ordinal))
		rout.append("")
		return rout
	var oct := str(int(bar.get("octave", OCT_MID)))
	var keyed := str(bar.get("key_label", ""))
	var out: Array = []
	var vel := int(bar.get("velocity", CORPUS_VELOCITY))
	if vel != CORPUS_VELOCITY and not keyed.is_empty():
		out.append(_ordinal_prefixed(ordinal, "%s · v%d" % [keyed, vel]))
	if not keyed.is_empty():
		out.append(_ordinal_prefixed(ordinal, keyed))
	out.append(_ordinal_prefixed(ordinal, oct))
	if ordinal >= 0:
		out.append(oct)
	out.append("")
	return out


## The widest rung that fits `avail` px, or "" when not even the ordinal does. Static and
## font-taking rather than pure, because fitting is a measurement; the ladder itself
## (span_text_rungs) stays data and is tested without a font.
static func fit_label(font: Font, fs: int, rungs: Array, avail: float) -> String:
	for rung in rungs:
		var text := str(rung)
		if text.is_empty():
			return ""
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= avail:
			return text
	return ""


## Place the TIME lane's span bars (ADR-0085 2026-08-18c §5): ONE bar per span, with
## up to three fills — blue for the note's own delta_time, amber for the sounding time
## its Fermata segments add butted against it, grey for a rest span. The bar's `rect`
## covers the WHOLE span, so a click on the amber selects the note whose ticks those
## are, and §6's ordinal numbers the span rather than each byte inside it.
##
## A rest is drawn, never left as empty lane. The piano-roll reading (by analogy with
## a colour spacer being empty space rather than a hatched block) does not transfer: a
## spacer is an event that does nothing, whereas a rest is authored silence, and the
## author will want to click it, inspect it and turn it back into a note.
static func _place_span_bars(placed_spans: Array, t: int, lane_y: float, axis,
		fire: int, out: Array, verdicts: Dictionary = {}, roll: bool = false) -> void:
	var per_event: Dictionary = verdicts.get("per_event", {})
	var reasons: Dictionary = verdicts.get("reasons", {})
	var faint: Dictionary = verdicts.get("faint", {})
	var lane_bar_y := lane_y + (LANE_H - NOTE_BAR_H) * 0.5
	for ps in placed_spans:
		var n: Dictionary = ps["src"]
		var sec: float = ps["sec"]
		var ei := int(n.get("event_index", -1))
		var rest := str(n.get("span_kind", "note")) == "rest"
		# THE CORE EDIT (amendment 2026-08-21d §3). In lanes mode every bar sits on the
		# lane's centre line; in roll mode its y IS its key. Nothing else about the bar
		# changes — and because `hit_in` hit-tests span bars by RECT, generically, the
		# selection routing (borrowed-bar → owner included), the tooltips, `context_at`,
		# `resolve_context`, `_place_grips` and `drag_target` all follow it for free.
		var row := roll_row(rest, int(n.get("relative_key", -1))) if roll else -1
		var bar_h := ROLL_BAR_H if roll else NOTE_BAR_H
		var bar_y := lane_y + float(row) * ROLL_ROW_H + (ROLL_ROW_H - ROLL_BAR_H) * 0.5 \
				if roll else lane_bar_y
		var x := _sec_x(axis, fire, sec)
		var end_x := _sec_x(axis, fire, sec + float(n.get("span_total_seconds", 0.0)))
		var w := maxf(2.0, end_x - x)
		var bar := {
			"track": t,
			"event_index": ei,
			"ordinal": display_ordinal(n),
			"rect": Rect2(x, bar_y, w, bar_h),
			"rest": rest,
			# The roll's row and the key it stands for, stamped so the vertical drag reads
			# its start key off the BAR (never off the cursor's y, which on a borrowed bar
			# is a different lane from the bytes it addresses). -1 in lanes mode.
			"row": row,
			"relative_key": int(n.get("relative_key", -1)),
			# The bar IS the tick ruler for a grab (ADR-0085 2026-08-19b §5): one linear
			# rect per span, so interpolating inside it cannot disagree with the picture.
			"span_total_ticks": int(n.get("span_total_ticks", 0)),
			# The drag's reach (2026-08-19b §3/§6), stamped by the model: the ticks of
			# CURRENCY on each side. A note walled on both sides owns no grip, which is
			# honest for 95.2% of the corpus rather than a phantom handle.
			"left_ticks": int(n.get("span_left_ticks", 0)),
			"right_ticks": int(n.get("span_right_ticks", 0)),
			"segments": int((n.get("span_segments", []) as Array).size()),
			"interior_opcode": bool(n.get("span_interior_opcode", false)),
			# `· v96` is DROPPED: 6262 of the corpus's 6439 notes (97.3%) carry velocity 96,
			# so printing it spends ~5 characters of a bar that is often 40 px wide saying
			# what is almost always true. It prints when it is NOT 96 — the informative case
			# (v0 is 106 notes, and nothing else marks them: the MUTED / FAINT verdicts are
			# instrument-derived and never read velocity).
			"label": "Rest" if rest \
					else _note_label(str(n.get("label", "")), int(n.get("velocity", 0))),
			"velocity": int(n.get("velocity", CORPUS_VELOCITY)),
			# The KEY alone, without velocity — the elision ladder's middle rung.
			"key_label": "Rest" if rest else str(n.get("label", "")),
			# The octave this note SOUNDS at, for the fill tint. Set by the Octave /
			# RaiseOctave / LowerOctave opcodes — never by the note byte, whose key field
			# is octave-relative (0..11 = C..B).
			"octave": int(n.get("octave", OCT_MID)),
			"ghost": bool(ps.get("ghost", false)),
			"flowed": bool(n.get("flowed", false)),
			"owner_track": int(n.get("owner_track", t)),
			"owner_event_index": int(n.get("owner_event_index", ei)),
			"verdict": str(per_event.get(ei, "")),
			"faint": bool(faint.get(ei, false)),
			"reason": str(reasons.get(ei, "")),
		}
		# The blue/amber split, when the span has sounding time to split. A rest span
		# takes the whole bar in grey — one fill, because silence has no interior.
		if not rest:
			var note_end_x := _sec_x(axis, fire, sec + float(n.get("span_note_seconds", 0.0)))
			bar["note_rect"] = Rect2(x, bar_y, maxf(0.0, note_end_x - x), bar_h)
			# The fermata amber still BUTTS against the note's own blue, on the same row
			# (amendment 2026-08-21d §8): the ticks are one note's, and a sounding
			# extension does not change the key it sounds at.
			if float(n.get("span_extension_seconds", 0.0)) > 0.0:
				bar["fermata_rect"] = Rect2(note_end_x, bar_y,
						maxf(0.0, end_x - note_end_x), bar_h)
		out.append(bar)


## The boundary GRIPS a note span is resized by (ADR-0085 2026-08-19b §6, transferring
## ADR-0095 §1's split band). One grip per boundary the drag can actually spend across:
##
##   * only a NOTE bar owns them — a rest is the currency, and the verb that puts a note
##     inside one is the paint, which is the rest bar's own gesture;
##   * only where there IS currency on that side (`left_ticks` / `right_ticks`), so a note
##     walled on both sides draws none. That is 5932 of 6234 corpus notes, and drawing a
##     handle over a drag that cannot move would be the phantom ADR-0095 §2 removed;
##   * only on a SINGLE-SEGMENT span, because a resize refuses a multi-segment one
##     explicitly (§8) and a handle over a refusal is the same phantom;
##   * never on a ghost copy (not an address) or a BORROWED bar (drawn where the span is
##     HEARD; the verbs address where the bytes LIVE).
##
## The band is centred ON the boundary and therefore half of it lies over the neighbouring
## rest — that is ADR-0095's decision, not an accident: either half writes the same number.
## What is new here is the CAP (see `GRIP_W`), which this lane needs and the colour lanes do
## not, because a bar here hosts two gestures rather than one.
## A note fill shaded by the octave it sounds at. Interpolating toward a near-black floor
## below OCT_MID and toward white above it keeps the hue while spending the whole
## lightness range, which a single multiply cannot do without clipping a channel and
## dragging the hue with it. A bar with no octave (a rest, or a view that never stamped
## one) never reaches here — rests take COL_BAR_REST.
static func octave_tint(base: Color, octave: int) -> Color:
	var o := clampi(octave, OCT_LO, OCT_HI)
	if o == OCT_MID:
		return base
	if o < OCT_MID:
		return base.lerp(Color(COL_OCT_FLOOR.r, COL_OCT_FLOOR.g, COL_OCT_FLOOR.b, base.a),
				float(OCT_MID - o) / float(OCT_MID - OCT_LO) * OCT_DARKEN)
	return base.lerp(Color(COL_OCT_CEIL.r, COL_OCT_CEIL.g, COL_OCT_CEIL.b, base.a),
			float(o - OCT_MID) / float(OCT_HI - OCT_MID) * OCT_LIGHTEN)


## Ink that reads on the fill under it. Near-black was picked for the bright blue of the
## old single-shade bar; once the fill carries an octave the low octaves are dark enough
## to swallow it, so the ink follows the fill's luminance rather than a constant.
static func label_ink(fill: Color, rest: bool) -> Color:
	if rest:
		return COL_TEXT
	var lum := fill.r * 0.299 + fill.g * 0.587 + fill.b * 0.114
	return Color(0.06, 0.07, 0.1) if lum > 0.5 else COL_TEXT


## The span SEPARATORS (ADR-0085 amendment 2026-08-21c): a hairline at every span
## BOUNDARY — one per boundary, not a border per bar. Spans TILE a track end to end
## (CONTEXT.md "Span"), so two neighbours SHARE an edge; drawing it once is half the ink
## and the honest primitive. A LINE, never a rect outline: the outline vocabulary is
## already spoken for (violet COL_FLOWED = borrowed bytes, COL_SELECT = selected), and a
## third outline would leave those two differing only by hue, the weakest channel here.
##
## Derived from the placed bars rather than emitted alongside them, like _place_grips —
## the boundaries ARE the bar edges, and deriving them means they cannot drift. Deduped
## per lane row at half-pixel resolution: two boundaries closer than that are one pixel,
## and pretending otherwise would draw a fake gap.
static func _place_separators(span_bars: Array) -> Array:
	var per_lane: Dictionary = {}
	var heights: Dictionary = {}
	for bar in span_bars:
		var r: Rect2 = bar["rect"]
		var xs: Dictionary = per_lane.get(r.position.y, {})
		xs[snappedf(r.position.x, 0.5)] = true
		xs[snappedf(r.end.x, 0.5)] = true
		per_lane[r.position.y] = xs
		# The hairline is the BAR's height, read off the bar rather than pinned to
		# NOTE_BAR_H — the roll's rows are shorter, and a 16 px stroke on a 10 px bar
		# would be a lane rule again, which is the thing this primitive replaced.
		heights[r.position.y] = r.size.y
	var out: Array = []
	for y in per_lane.keys():
		for x in (per_lane[y] as Dictionary).keys():
			out.append({"x": float(x), "y": float(y), "h": float(heights[y])})
	return out


static func _place_grips(span_bars: Array) -> Array:
	var by_track: Dictionary = {}
	for bar in span_bars:
		if bool(bar.get("ghost", false)) or bool(bar.get("flowed", false)):
			continue
		var t := int(bar.get("track", -1))
		if not by_track.has(t):
			by_track[t] = []
		(by_track[t] as Array).append(bar)
	var out: Array = []
	for t in by_track.keys():
		var row: Array = by_track[t]
		row.sort_custom(func(a, b): return (a["rect"] as Rect2).position.x < (b["rect"] as Rect2).position.x)
		for i in range(row.size()):
			var bar: Dictionary = row[i]
			if bool(bar.get("rest", true)) or int(bar.get("segments", 1)) > 1:
				continue
			if int(bar.get("left_ticks", 0)) > 0 and i > 0:
				var gl := _grip(bar, row[i - 1], (bar["rect"] as Rect2).position.x, "left", int(t))
				if not gl.is_empty():
					out.append(gl)
			if int(bar.get("right_ticks", 0)) > 0 and i + 1 < row.size():
				var gr := _grip(bar, row[i + 1], (bar["rect"] as Rect2).end.x, "right", int(t))
				if not gr.is_empty():
					out.append(gr)
	return out


## One grip rect, or {} when the two bars it straddles are too narrow to host both a body
## drag and an edge drag.
static func _grip(bar: Dictionary, neighbour: Dictionary, x: float, side: String,
		t: int) -> Dictionary:
	var narrow: float = minf((bar["rect"] as Rect2).size.x, (neighbour["rect"] as Rect2).size.x)
	var half: float = minf(GRIP_W * 0.5, narrow * 0.25)
	if half < GRIP_MIN_HALF:
		return {}
	return {
		"track": t,
		"event_index": int(bar.get("event_index", -1)),
		"side": side,
		"gesture": "resize_left" if side == "left" else "resize_right",
		"rect": Rect2(x - half, (bar["rect"] as Rect2).position.y, half * 2.0,
				(bar["rect"] as Rect2).size.y),
	}


## Place one kind-lane's chips at their TRUE axis x (amendment §5 — a pushed chip
## falsifies its tick): a chip whose fixed-width rect would overlap an earlier one
## drops to the lowest free row (greedy first-fit in tick/byte order). Returns the
## row count so layout() can grow the lane by rows × (CHIP_H + gap). Unbounded
## rows — FEDS scale self-limits.
static func _place_chips(placed_chips: Array, t: int, kind: String, lane_y: float,
		axis, fire: int, out: Array, verdicts: Dictionary = {}) -> int:
	var per_event: Dictionary = verdicts.get("per_event", {})
	var reasons: Dictionary = verdicts.get("reasons", {})
	var chip_y := lane_y + (LANE_H - CHIP_H) * 0.5
	var mine: Array = []
	for i in range(placed_chips.size()):
		if str((placed_chips[i]["src"] as Dictionary).get("kind", "")) == kind:
			mine.append([int(placed_chips[i]["tick"]), i, placed_chips[i]])
	# Sort by placed tick (byte order breaks ties) so the row sweep is left→right.
	mine.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var row_free: Array = []   # per-row next free x (first-fit target)
	for entry in mine:
		var pc: Dictionary = entry[2]
		var c: Dictionary = pc["src"]
		var x := _sec_x(axis, fire, float(pc["sec"]))
		var row := 0
		while row < row_free.size() and x < float(row_free[row]):
			row += 1
		if row == row_free.size():
			row_free.append(-INF)
		row_free[row] = x + CHIP_W + CHIP_ROW_GAP
		var cei := int(c.get("event_index", -1))
		out.append({
			"track": t,
			"kind": kind,
			"event_index": cei,
			"ordinal": display_ordinal(c),
			"rect": Rect2(x, chip_y + float(row) * (CHIP_H + CHIP_ROW_GAP), CHIP_W, CHIP_H),
			"code": _chip_code(c),
			"full": _chip_full(c),
			"ghost": bool(pc.get("ghost", false)),
			"flowed": bool(c.get("flowed", false)),
			"owner_track": int(c.get("owner_track", t)),
			"owner_event_index": int(c.get("owner_event_index", cei)),
			"verdict": str(per_event.get(cei, "")),
			"reason": str(reasons.get(cei, "")),
		})
	return maxi(1, row_free.size())


## Place one track's energy band (§3): the per-frame RMS envelope plotted on the
## SHARED frame axis — sample i sits at axis.frame_to_x(fire + i), so a swell lands
## directly beneath the opcodes that produce it. Samples are already shared-peak
## normalized (SoundGhostProjector.normalize_pair_shared), so a stub reads flat and
## the carrier tall against a common baseline. Off-band samples (x outside the visible
## strip) are skipped. Returns {track, rect, points, peak}.
static func _place_energy_band(t: int, energy: PackedFloat32Array, band_y: float,
		width: float, axis, fire: int, raw_peak: float = -1.0) -> Dictionary:
	var bottom := band_y + ENERGY_BAND_H
	var pts := PackedVector2Array()
	var peak := 0.0
	for i in range(energy.size()):
		var x: float = axis.frame_to_x(float(fire + i))
		if x < GUTTER_W or x > width:
			continue
		var v: float = clampf(float(energy[i]), 0.0, 1.0)
		pts.append(Vector2(x, bottom - v * (ENERGY_BAND_H - 2.0)))
		peak = maxf(peak, v)
	# The absolute "silent in isolation" tell (§6, DISPLAY-ONLY): the shared-normalize
	# can dress a floor-level track UP to a full-height swell, so carry the RAW peak and
	# flag it when it never crosses the absolute-quiet threshold. This never touches the
	# opcode verdict — it only lets the author see past a normalized lie.
	return {
		"track": t,
		"rect": Rect2(GUTTER_W, band_y, maxf(0.0, width - GUTTER_W), ENERGY_BAND_H),
		"points": pts,
		"peak": peak,
		"raw_peak": raw_peak,
		"silent_in_isolation": raw_peak >= 0.0 \
				and SoundGhostProjector.is_silent_in_isolation(raw_peak),
	}


## The joint (mixed-pair) energy band: the baseline mix waveform, plus the pruned mix
## overlay once the A/B has run (both on the same scale, so the gap IS the Δ).
static func _place_joint_band(jd: Dictionary, band_y: float, width: float, axis,
		fire: int) -> Dictionary:
	var base: PackedFloat32Array = jd.get("baseline", PackedFloat32Array())
	var pruned: PackedFloat32Array = jd.get("pruned", PackedFloat32Array())
	return {
		"rect": Rect2(GUTTER_W, band_y, maxf(0.0, width - GUTTER_W), JOINT_BAND_H),
		"baseline_points": _band_points(base, band_y, width, axis, fire),
		"pruned_points": _band_points(pruned, band_y, width, axis, fire),
		"tier": str(jd.get("tier", "")),
		"max_abs": float(jd.get("max_abs", -1.0)),
		"raw_peak": float(jd.get("raw_peak", -1.0)),
	}


## Project a 0..1 envelope onto the shared frame axis within a JOINT_BAND_H band.
static func _band_points(samples: PackedFloat32Array, band_y: float, width: float,
		axis, fire: int) -> PackedVector2Array:
	var bottom := band_y + JOINT_BAND_H
	var pts := PackedVector2Array()
	for i in range(samples.size()):
		var x: float = axis.frame_to_x(float(fire + i))
		if x < GUTTER_W or x > width:
			continue
		var v: float = clampf(float(samples[i]), 0.0, 1.0)
		pts.append(Vector2(x, bottom - v * (JOINT_BAND_H - 2.0)))
	return pts


## The per-track no-op A/B tell string — the tier glyph plus the RAW measured Δ (always
## shown, never hidden behind the label; ADR-0085 §4 "always show the raw number").
static func _noop_tell_text(tell: Dictionary) -> String:
	var tier := str(tell.get("tier", ""))
	var glyph: String = {"inert": "✓", "faint": "≈", "changed": "✗"}.get(tier, "")
	return "no-op A/B: %s %s  Δ%.4f" % [tier, glyph, float(tell.get("max_abs", 0.0))]


static func _place_brackets(placed_brackets: Array, t: int, lane_y: float, axis,
		fire: int, out: Array) -> void:
	for pb in placed_brackets:
		var x0 := _sec_x(axis, fire, float(pb["start_sec"]))
		var x1 := _sec_x(axis, fire, float(pb["end_sec"]))
		var is_phantom := bool(pb.get("phantom", false))
		var arrow: String = "▾" if bool(pb["unwound"]) else "▸"
		var badge: String = "→%s %s" % [str(pb.get("into_letter", "?")), arrow] \
				if is_phantom else "×%d %s" % [int(pb["count"]), arrow]
		if bool(pb.get("truncated", false)):
			badge += "…"
		out.append({
			"track": t,
			"loop_index": int(pb["loop_index"]),
			"phantom": is_phantom,
			"x0": x0,
			"x1": x1,
			"y": lane_y + LANE_H * 0.5,
			"badge": badge,
			"unwound": bool(pb["unwound"]),
			"truncated": bool(pb.get("truncated", false)),
			"toggle_rect": Rect2(x0, lane_y + (LANE_H - BADGE_H) * 0.5, BADGE_W, BADGE_H),
		})


## The typed chip's short fixed-width code (detail lives on the hover tooltip).
static func _chip_code(c: Dictionary) -> String:
	var label := str(c.get("label", ""))
	var code: String
	if label.begins_with("Unknown_"):
		code = "?" + label.substr(8)
	else:
		code = CHIP_CODES.get(label, label.substr(0, 3))
	var params: Array = c.get("params", [])
	if not params.is_empty():
		code += str(int(params[0]))
	return code.substr(0, 6)


static func _chip_full(c: Dictionary) -> String:
	var parts: Array = []
	for p in c.get("params", []):
		parts.append(str(p))
	var full := str(c.get("label", ""))
	if not parts.is_empty():
		full += "(%s)" % ", ".join(parts)
	# The semantics layer speaks here too: an Instrument chip names the sample,
	# an ADSR chip reports its ≈ milliseconds (FedsParamSemantics).
	var extra := Semantics.param_summary(int(c.get("opcode", -1)), c.get("params", []))
	if extra != "":
		full += " — " + extra
	return "%s @ tick %d" % [full, int(c.get("tick", 0))]


# --- Bounded in-place unroll (decision 3) -----------------------------------

## Expand one track's folded view under the wind state. FRAME-AXIS §4: folding
## collapses DRAWING, never TIME — every loop ALWAYS reserves its full
## (count-1)×body downstream shift (tick AND seconds) so the panel agrees with
## the unrolled ghost pips in both states; the fold flag gates only whether the
## ghost copies are drawn. The panel-wide copy budget + the 30 s ceiling bound
## the reserved passes the same way in both states (a runaway ×200 truncates
## with a tell). Loops are treated as non-overlapping (FEDS scale); a nested
## bracket rides its outer body as chips. Returns {notes, spans, chips, brackets,
## end_tick, end_seconds} where notes/spans/chips are [{tick, sec, src, ghost}].
static func _expand_track(track: Dictionary, t_idx: int, unwound: Dictionary,
		budget: Dictionary) -> Dictionary:
	var loops: Array = track.get("loops", [])
	var folded_end := maxi(1, int(track.get("end_tick", 1)))
	var folded_secs := float(track.get("end_seconds", 0.0))
	var spt := folded_secs / float(folded_end)  # linear fallback for un-annotated views

	# Resolve each loop's reserved extra passes ("extra", always applied to time)
	# and its drawn ghost copies ("drawn", fold-gated) under the shared budget.
	var plans: Array = []   # [{start, end, len, body_sec, count, extra, drawn, …}]
	for li in range(loops.size()):
		var lp: Dictionary = loops[li]
		var start := int(lp.get("start_tick", 0))
		var end := int(lp.get("end_tick", 0))
		var count := maxi(1, int(lp.get("count", 1)))
		var body_len := maxi(0, end - start)
		var start_sec := float(lp.get("start_seconds", spt * float(start)))
		var body_sec := maxf(0.0, float(lp.get("end_seconds", spt * float(end))) - start_sec)
		var plan := {"start": start, "end": end, "len": body_len, "body_sec": body_sec,
				"count": count, "extra": 0, "drawn": 0, "loop_index": li,
				"truncated": false,
				"unwound": unwound.get("%d:%d" % [t_idx, li], false)}
		if body_len > 0:
			var body_events := _body_event_count(track, start, end)
			var extra := count - 1
			# Budget cap: at most `left` unrolled copies panel-wide. Consumed
			# regardless of fold state so unwinding can never MOVE the axis.
			if body_events > 0:
				extra = mini(extra, int(budget["left"]) / body_events)
			# 30 s ceiling: never extend the axis past the render ceiling.
			if body_sec > 0.0:
				extra = mini(extra, maxi(0, int((MAX_UNROLL_SECONDS - folded_secs) / body_sec)))
			plan["extra"] = maxi(0, extra)
			plan["drawn"] = int(plan["extra"]) if bool(plan["unwound"]) else 0
			plan["truncated"] = int(plan["extra"]) < count - 1
			budget["left"] = int(budget["left"]) - int(plan["extra"]) * body_events
		plans.append(plan)

	var notes: Array = []
	for n in track.get("notes", []):
		_place_expanded(int(n.get("start_tick", 0)),
				float(n.get("start_seconds", spt * float(n.get("start_tick", 0)))),
				n, plans, notes, false)
	# The TIME lane's spans (ADR-0085 2026-08-18c). They ride the same loop plans as
	# everything else — a span inside an unwound Repeat draws one ghost copy per pass,
	# which is exactly what it sounds like.
	var spans: Array = []
	for sp in track.get("spans", []):
		_place_expanded(int(sp.get("span_start_tick", 0)),
				float(sp.get("span_start_seconds",
						spt * float(sp.get("span_start_tick", 0)))),
				sp, plans, spans, false)
	var chips: Array = []
	for c in track.get("commands", []):
		_place_expanded(int(c.get("tick", 0)),
				float(c.get("seconds", spt * float(c.get("tick", 0)))),
				c, plans, chips, str(c.get("kind", "")) == "structure")
	var brackets: Array = []
	for plan in plans:
		var b_start_sec := float((loops[int(plan["loop_index"])] as Dictionary) \
				.get("start_seconds", spt * float(plan["start"]))) \
				+ _shift_secs_at(int(plan["start"]), plans)
		# The bracket spans its FULL reserved envelope in both fold states (§4):
		# a folded bracket covers the same frames its unrolled pips do.
		brackets.append({
			"loop_index": plan["loop_index"],
			"start_tick": int(plan["start"]) + _shift_at(int(plan["start"]), plans),
			"end_tick": int(plan["end"]) + _shift_at(int(plan["start"]), plans) \
					+ int(plan["extra"]) * int(plan["len"]),
			"start_sec": b_start_sec,
			"end_sec": b_start_sec + float(plan["body_sec"]) \
					* float(1 + int(plan["extra"])),
			"count": plan["count"],
			"unwound": plan["unwound"],
			"truncated": plan["truncated"],
		})
	# The NoEnd PHANTOM (ADR-0085 2026-08-18). A stub track has no EndBar, so its
	# voice runs on into the neighbour's bytecode and SOUNDS bytes it never authored.
	# That borrowed span is DERIVED — no byte encodes it — so it draws on the Flow
	# lane beside the loop brackets: same bracket shape, same fold badge, same verb.
	# The bracket spans its REAL envelope in BOTH fold states, because the span
	# already sounds (pips, energy and audio all include it as of 81d86a7e7): folding
	# hides content, never time — the loop bracket's law, applied to the other kind
	# of borrowing. Borrowed items ride the stub's own loop plans, so unrolling a
	# loop in the stub pushes the borrowed span later, exactly as it would sound.
	var ft: Dictionary = track.get("flow_through", {})
	if not ft.is_empty():
		var ph_unwound: bool = unwound.get(_loop_key(t_idx, -1), false)
		var first_tick := -1
		var first_sec := -1.0
		for n in ft.get("notes", []):
			if bool(n.get("flowed", false)):
				first_tick = int(n.get("start_tick", 0))
				first_sec = float(n.get("start_seconds", 0.0))
				break
		for c in ft.get("commands", []):
			if bool(c.get("flowed", false)):
				var cs := float(c.get("seconds", 0.0))
				if first_sec < 0.0 or cs < first_sec:
					first_tick = int(c.get("tick", 0))
					first_sec = cs
				break
		if first_sec >= 0.0:
			if ph_unwound:
				for n in ft.get("notes", []):
					if bool(n.get("flowed", false)):
						_place_expanded(int(n.get("start_tick", 0)),
								float(n.get("start_seconds", 0.0)), n, plans, notes, false)
				# The borrowed stream folds into spans too, so a borrowed 160-tick note
				# draws as 160 ticks here and on its owner's lane alike — the same bytes
				# read the same way, which is the whole point of the phantom.
				for sp in ft.get("spans", []):
					if bool(sp.get("flowed", false)):
						_place_expanded(int(sp.get("span_start_tick", 0)),
								float(sp.get("span_start_seconds", 0.0)), sp, plans,
								spans, false)
				for c in ft.get("commands", []):
					if bool(c.get("flowed", false)):
						_place_expanded(int(c.get("tick", 0)), float(c.get("seconds", 0.0)),
								c, plans, chips, str(c.get("kind", "")) == "structure")
			var shift := _shift_at(folded_end + 1, plans)
			var shift_sec := _shift_secs_at(folded_end + 1, plans)
			brackets.append({
				"loop_index": -1,
				"phantom": true,
				"into_letter": _TRACK_LETTERS[(t_idx + 1) % 2] \
						if int(ft.get("into_track", -1)) >= 0 else "?",
				"start_tick": first_tick + shift,
				"end_tick": int(ft.get("end_tick", first_tick)) + shift,
				"start_sec": first_sec + shift_sec,
				"end_sec": float(ft.get("end_seconds", first_sec)) + shift_sec,
				"count": 0,
				"unwound": ph_unwound,
				"truncated": false,
			})
	return {
		"notes": notes,
		"spans": spans,
		"chips": chips,
		"brackets": brackets,
		# The stub's DRAWN extent stays bounded by its own bytes: the amendment adds
		# CONTENT, never axis length (the pair's length is the sounding track's).
		"end_tick": folded_end + _shift_at(folded_end + 1, plans),
		"end_seconds": folded_secs + _shift_secs_at(folded_end + 1, plans),
	}


## Events strictly inside [start, end) — what one extra pass copies.
static func _body_event_count(track: Dictionary, start: int, end: int) -> int:
	var n := 0
	for note in track.get("notes", []):
		if int(note.get("start_tick", 0)) >= start and int(note.get("start_tick", 0)) < end:
			n += 1
	for c in track.get("commands", []):
		var tick := int(c.get("tick", 0))
		if tick >= start and tick < end and str(c.get("kind", "")) != "structure":
			n += 1
	return n


## Cumulative right-shift at an ORIGINAL folded tick from every loop that ends at
## or before it (events at a loop's end tick play after its last pass). Uses the
## RESERVED passes ("extra") — the shift applies regardless of fold state (§4).
static func _shift_at(tick: int, plans: Array) -> int:
	var shift := 0
	for plan in plans:
		if int(plan["extra"]) > 0 and int(plan["end"]) <= tick:
			shift += int(plan["extra"]) * int(plan["len"])
	return shift


## The seconds sibling of _shift_at: the reserved bodies' integrated seconds, so
## downstream events shift by real TIME (frame-axis honesty under inline TEMPO).
static func _shift_secs_at(tick: int, plans: Array) -> float:
	var shift := 0.0
	for plan in plans:
		if int(plan["extra"]) > 0 and int(plan["end"]) <= tick:
			shift += float(plan["extra"]) * float(plan["body_sec"])
	return shift


## Place one folded event into the expanded stream: the authored pass at its
## shifted tick+seconds, plus — only when its loop is UNWOUND (§4: fold gates
## drawing, not time) — one GHOST copy per drawn pass, copy k landing at
## base + k × body (tick AND seconds), the same march the ghost pips make
## (structure chips — the bracket's own Repeat/Coda — never copy; the bracket
## badge tells the story).
static func _place_expanded(tick: int, sec: float, src: Dictionary, plans: Array,
		out: Array, is_structure: bool) -> void:
	var body_plan: Dictionary = {}
	for plan in plans:
		if int(plan["drawn"]) > 0 and tick >= int(plan["start"]) and tick < int(plan["end"]):
			body_plan = plan
			break
	var shift_ref := tick if body_plan.is_empty() else int(body_plan["start"])
	var base := tick + _shift_at(shift_ref, plans)
	var base_sec := sec + _shift_secs_at(shift_ref, plans)
	out.append({"tick": base, "sec": base_sec, "src": src, "ghost": false})
	if body_plan.is_empty() or is_structure:
		return
	for k in range(1, int(body_plan["drawn"]) + 1):
		out.append({"tick": base + k * int(body_plan["len"]),
				"sec": base_sec + float(k) * float(body_plan["body_sec"]),
				"src": src, "ghost": true})


# --- Hit-test + input (the timeline's routing guard, panel-scale) -----------

## Route a local point: loop badges, then the unwind-all header chip, then section
## headers, then the gutter-inert rule, then event select. Returns
##   {"kind": "toggle_loop", track, loop_index} | {"kind": "toggle_all"}
##   | {"kind": "toggle_section", track}
##   | {"kind": "select", track, event_index} | {"kind": "none"}
func hit_test(local_pos: Vector2) -> Dictionary:
	return hit_in(layout(_view, size.x, _state(), _axis_obj(), _anchor), local_pos)


## PURE: what a click at `local_pos` lands on in an already-computed layout. Split
## from `hit_test` so the click-resolution laws are guarded without a scene.
static func hit_in(lay: Dictionary, local_pos: Vector2) -> Dictionary:
	for br in lay["brackets"]:
		if (br["toggle_rect"] as Rect2).has_point(local_pos):
			return {"kind": "toggle_loop", "track": int(br["track"]),
					"loop_index": int(br["loop_index"])}
	var header: Dictionary = lay["header"]
	if (header["unwind_all_rect"] as Rect2).has_point(local_pos):
		return {"kind": "toggle_all"}
	if (header.get("roll_rect", Rect2()) as Rect2).has_point(local_pos):
		return {"kind": "toggle_roll"}
	for sec in lay["sections"]:
		if (sec["rect"] as Rect2).has_point(local_pos):
			return {"kind": "toggle_section", "track": int(sec["track"])}
	if local_pos.x < GUTTER_W:
		return {"kind": "none"}   # the label gutter is inert (no S/M here — decision 7)
	for bar in lay["span_bars"]:
		if (bar["rect"] as Rect2).has_point(local_pos):
			return _select_route(bar)
	for chip in lay["chips"]:
		if (chip["rect"] as Rect2).has_point(local_pos):
			return _select_route(chip)
	return {"kind": "none"}


## A BORROWED item selects its OWNER's event: you edit a byte where it LIVES, never
## where it is heard (ADR-0085 2026-08-18). The selection highlight therefore jumps
## to the neighbour's real item and the F1 inspector opens that byte's rows — the
## same law the panel already applies to an unrolled loop copy, extended to the case
## where the author is a different track. Identity travels by blob-absolute offset
## (stamped by the model); an unresolvable owner is INERT, never a wrong target.
static func _select_route(item: Dictionary) -> Dictionary:
	if not bool(item.get("flowed", false)):
		return {"kind": "select", "track": int(item["track"]),
				"event_index": int(item["event_index"])}
	var ot := int(item.get("owner_track", -1))
	var oei := int(item.get("owner_event_index", -1))
	if ot < 0 or oei < 0:
		return {"kind": "none"}
	return {"kind": "select", "track": ot, "event_index": oei}


## How far INTO its span, in ticks, a grab at `local_pos` landed — or -1 when it did not
## land on that event's own span bar (ADR-0085 2026-08-19b §5).
##
## Read from the BAR, never from the axis. A span is drawn as ONE linear rect from its
## start to its end, so interpolating inside it is by construction the tick the author is
## pointing at: what you see is what you get, and no second projection can disagree with
## the first. It is exact as well as consistent — the FEDS corpus carries zero `0xA0 Tempo`
## and zero `0xA2 TempoSlide` across all 1998 byte-owning tracks, so ticks and seconds are
## one constant per track and the linear read has no error term.
##
## A BORROWED bar is skipped: its rect is drawn where the span is HEARD, and the verbs
## address where the bytes LIVE.
static func _grab_ticks(lay: Dictionary, local_pos: Vector2, event_index: int) -> int:
	for bar in lay["span_bars"]:
		if int(bar.get("event_index", -1)) != event_index or bool(bar.get("flowed", false)):
			continue
		var rect: Rect2 = bar["rect"]
		if not rect.has_point(local_pos):
			continue
		var total: int = int(bar.get("span_total_ticks", 0))
		if total <= 0 or rect.size.x <= 0.0:
			return -1
		var frac: float = (local_pos.x - rect.position.x) / rect.size.x
		return clampi(int(round(frac * float(total))), 0, total)
	return -1


## PURE: what a LEFT-BUTTON press at `local_pos` would DRAG (ADR-0085 2026-08-19b §6), or {}
## when it would drag nothing. Split from `_gui_input` so the three gestures' routing is
## guarded without a scene, exactly as `hit_in` and `resolve_context` are.
##
## Returns the grab, resolved ONCE and expressed in ticks from here on:
##   {gesture, pair_idx, track, track_idx, at, event_index, span_ticks, ticks_per_px,
##    grab_ticks, start_x}
##
## `at` is the span head's blob-absolute byte boundary — the address the un-rest and the
## paint already take — and `ticks_per_px` is read off the grabbed BAR, never by inverting
## the axis (§5): a span is drawn as ONE linear rect, so interpolating inside it is by
## construction the tick the author is pointing at. It is also exact, not merely consistent:
## the FEDS corpus carries zero Tempo and zero TempoSlide opcodes.
##
## A grip wins over the bar under it — the band straddles the boundary on purpose. Otherwise
## a rest bar drags out a PAINT and a note bar's body a MOVE. A move that has no currency at
## all, or whose span fires an opcode inside it (§8), arms nothing: the press stays a plain
## selection rather than becoming a gesture that cannot move.
static func drag_target(view: Dictionary, lay: Dictionary, local_pos: Vector2) -> Dictionary:
	if view.is_empty() or local_pos.x < GUTTER_W:
		return {}
	for g in lay.get("grips", []):
		if (g["rect"] as Rect2).has_point(local_pos):
			# A RESIZE stays horizontal in both readings: the grip is a boundary, and a
			# boundary has no key. Only the note BODY is two-axis in roll mode.
			return _drag_for(view, lay, int(g["track"]), int(g["event_index"]),
					str(g["gesture"]), local_pos)
	var hit := hit_in(lay, local_pos)
	if str(hit.get("kind", "")) != "select":
		return {}
	var bar := _authored_bar(lay, int(hit["track"]), int(hit["event_index"]))
	if bar.is_empty():
		return {}
	return _drag_for(view, lay, int(hit["track"]), int(hit["event_index"]),
			"paint" if bool(bar.get("rest", false)) else "move", local_pos,
			bool(lay.get("roll", false)))


static func _drag_for(view: Dictionary, lay: Dictionary, t: int, event_index: int,
		gesture: String, local_pos: Vector2, roll: bool = false) -> Dictionary:
	var bar := _authored_bar(lay, t, event_index)
	if bar.is_empty():
		return {}
	var total := int(bar.get("span_total_ticks", 0))
	var r: Rect2 = bar["rect"]
	if total <= 0 or r.size.x <= 0.0:
		return {}
	# Can this press MOVE in time? Unchanged, and in lanes mode a "no" arms nothing at all.
	var can_move := gesture != "move" \
			or (not bool(bar.get("interior_opcode", false)) \
				and int(bar.get("left_ticks", 0)) + int(bar.get("right_ticks", 0)) > 0)
	# Can it be dragged to a PITCH? Only a note bar in roll mode, and only one whose key
	# the bytes actually carry. A REST has no key (its gesture is the paint), and the Rest
	# row is not one of the twelve — a drag can neither start nor land there.
	var can_key := roll and not bool(bar.get("rest", false)) \
			and int(bar.get("relative_key", -1)) >= 0 and int(bar.get("row", -1)) >= 0 \
			and int(bar.get("row", -1)) < ROLL_KEYS
	if not can_move and not can_key:
		return {}
	var tracks: Array = view.get("tracks", [])
	if t < 0 or t >= tracks.size():
		return {}
	var tr: Dictionary = tracks[t]
	var ev: Dictionary = _own_event(tr, event_index)
	if ev.is_empty():
		return {}
	return {
		"gesture": gesture,
		"pair_idx": int(view.get("pair_idx", -1)),
		"track": t,
		"track_idx": int(tr.get("track_idx", -1)),
		"at": int(ev["offset"]),
		"event_index": event_index,
		"span_ticks": total,
		"ticks_per_px": float(total) / r.size.x,
		"grab_ticks": clampi(int(round((local_pos.x - r.position.x) / r.size.x * float(total))),
				0, total),
		"start_x": local_pos.x,
		# The roll's second axis. `start_key` is read off the BAR, never off the cursor's y:
		# a BORROWED bar is drawn where the span is HEARD, so its row belongs to the wrong
		# track — the drag addresses the owner's bytes (`_authored_bar` resolved that
		# already) and must start from the owner's key. The y only ever supplies a DISTANCE.
		"roll": roll,
		"start_y": local_pos.y,
		"start_key": int(bar.get("relative_key", -1)),
		"can_move": can_move,
		"can_key": can_key,
	}


## This track's OWN span bar for `event_index` — never a ghost copy and never a borrowed one.
static func _authored_bar(lay: Dictionary, t: int, event_index: int) -> Dictionary:
	for bar in lay["span_bars"]:
		if int(bar.get("track", -1)) != t or int(bar.get("event_index", -1)) != event_index:
			continue
		if bool(bar.get("ghost", false)) or bool(bar.get("flowed", false)):
			continue
		return bar
	return {}


## PURE: what one motion of `drag` at cursor x wants written, or {} when it wants nothing.
## The pixel became ticks at grab time (§5); this only ever multiplies a DISTANCE, so the
## axis re-anchoring under a structural edit cannot address the wrong span afterwards.
##
## A move / resize reports a signed `delta_ticks` from the drag's START, which is what makes
## every motion re-plannable from the pristine bytes (ADR-0095 §4) instead of compounding.
## A paint reports the RANGE between the grab tick and the cursor tick — dragging either way
## from the grab paints the span between them, and a zero-length range writes nothing rather
## than manufacturing the zero-tick note the un-rest refuses to sound.
static func drag_motion(drag: Dictionary, x: float, y: float = 0.0) -> Dictionary:
	if drag.is_empty():
		return {}
	# The KEY drag (amendment 2026-08-21d §7). It reports an ABSOLUTE `relative_key`, not a
	# delta: the write is a same-size one-byte patch of the note data byte's upper field, so
	# every motion re-states the whole answer and none of them compound. The roll is
	# octave-agnostic, so there is no octave boundary for the drag to cross — which is why
	# ADR-0085's rejection of drag-to-pitch STRUCTURAL verbs is satisfied here rather than
	# amended: this gesture is a bounded parameter edit and cannot restructure the stream.
	if str(drag["gesture"]) == "key":
		var rows := int(round((y - float(drag["start_y"])) / ROLL_ROW_H))
		# Rows ascend in PITCH going up, so travelling up (negative y) RAISES the key.
		var key := clampi(int(drag["start_key"]) - rows, 0, ROLL_KEYS - 1)
		return {"verb": "key", "relative_key": key}
	var d := int(round((x - float(drag["start_x"])) * float(drag["ticks_per_px"])))
	if str(drag["gesture"]) == "paint":
		var total := int(drag["span_ticks"])
		var grab := int(drag["grab_ticks"])
		var other := clampi(grab + d, 0, total)
		var lo := mini(grab, other)
		var hi := maxi(grab, other)
		if hi - lo <= 0:
			return {}
		return {"verb": "paint", "offset_ticks": lo, "duration_ticks": hi - lo}
	return {"verb": "drag", "gesture": str(drag["gesture"]), "delta_ticks": d}


## Resolve a RIGHT-CLICK to a byte boundary in the pair (ADR-0085 amendment
## 2026-08-18b §4). A tick is not a position in this stream — zero-tick opcodes stack,
## and E317 pair 0 has four events at tick 0 drawn at the same x — so the address is a
## byte boundary expressed as "after this event", and the caller must NAME what it
## resolved to rather than silently picking one of four.
##
## A direct hit on a chip / note bar resolves to that event (routed to its OWNER when
## borrowed — you edit a byte where it LIVES). A click in empty lane space resolves to
## the track's own last item drawn at or before the cursor, or to the track START when
## there is none; either way the returned `anchor` says which.
##
## Returns {} for the inert gutter and for anywhere outside a track's lanes.
## Otherwise: {pair_idx, track, track_idx, at, anchor, direct, delete, phantom_boundary}
##   track      pair-local 0/1;  track_idx  the GLOBAL bank index the verbs address
##   at         the blob-absolute byte boundary an insert would write at
##   anchor     {} at the track start, else {event_index, label, tick}
##   delete     {} when nothing deletable was hit, else {at, label}
func context_at(local_pos: Vector2) -> Dictionary:
	if _view.is_empty():
		return {}
	return resolve_context(_view, layout(_view, size.x, _state(), _axis_obj(), _anchor), local_pos)


## PURE: the resolution itself, over an already-computed layout — so the "name what
## you resolved to" law is guarded without a scene.
## A click that lands on no byte boundary now SAYS so (ADR-0085 amendment 2026-08-19e §1).
## The three returns that used to be a silent `{}` are the whole of the author's "right-
## clicking the note band didn't bring up anything": each names a real place on the panel
## that owns no bytes. A refusal carries no `track_idx`, so no verb can be built from it —
## the page turns it into one disabled row, which is the same law as "Add opcode after
## `Oct3` @ tick 0": name what the click resolved to, never resolve to nothing in silence.
static func resolve_context(view: Dictionary, lay: Dictionary, local_pos: Vector2) -> Dictionary:
	if local_pos.x < GUTTER_W:
		return {"refused": "The track label strip — no bytes live here. Right-click inside a lane."}
	var hit := hit_in(lay, local_pos)
	if str(hit.get("kind", "")) == "select":
		return _context_for(view, int(hit["track"]), int(hit["event_index"]), true,
				_grab_ticks(lay, local_pos, int(hit["event_index"])))
	# Empty lane space: whose rows are these?
	var t := -1
	for lane in lay["lanes"]:
		if (lane["rect"] as Rect2).has_point(local_pos):
			t = int(lane["track"])
	if t < 0:
		return {"refused": "No lane here — the space below and between the tracks owns no bytes."}
	# The track's OWN last item at or before the cursor. Borrowed and ghost copies are
	# skipped: they are somebody else's bytes / a redrawn one, so neither is an anchor
	# in THIS track's stream.
	var best_ei := -1
	var best_x := -INF
	for arr in [lay["span_bars"], lay["chips"]]:
		for it in arr:
			if int(it["track"]) != t or bool(it.get("ghost", false)) or bool(it.get("flowed", false)):
				continue
			var x: float = (it["rect"] as Rect2).position.x
			if x > local_pos.x:
				continue
			var ei := int(it["event_index"])
			# Same x = same tick: zero-tick events stack, and the LAST of a stack is
			# the boundary a click past them means.
			if x > best_x or (x == best_x and ei > best_ei):
				best_x = x
				best_ei = ei
	return _context_for(view, t, best_ei, false)


## Build the context for (pair-local track, event_index). `event_index` < 0 means the
## boundary BEFORE the first event — the track start, which is a real address (an
## Instrument ahead of every note is exactly the edit slice 1 must allow).
static func _context_for(view: Dictionary, t: int, event_index: int, direct: bool,
		grab_ticks: int = -1) -> Dictionary:
	var tracks: Array = view.get("tracks", [])
	if t < 0 or t >= tracks.size():
		return {}
	var tr: Dictionary = tracks[t]
	if bool(tr.get("null_track", false)):
		# A null slot owns no bytes — nothing to anchor to. 10 of 1009 pairs have one, and
		# it looks exactly like an empty track, so the refusal has to say which it is.
		return {"refused": "This slot is empty — the pair has no track here to edit."}
	var base: int = int(tr.get("offset", 0))
	var ev: Dictionary = _own_event(tr, event_index)
	var at: int = base if ev.is_empty() else int(ev["offset"]) + int(ev["size"])
	# What Delete is offered on (ADR-0085 2026-08-18c §6). A SPAN HEAD carries
	# `span_kind`: a note span gets a Delete row, because deleting it means putting a
	# rest there — but a REST span does not, because that is a literal no-op. A grey
	# bar's menu has no Delete row; the only way to remove silence is to make it not
	# silence — which is the UN-REST (2026-08-19), the row a grey bar carries INSTEAD.
	# So every span offers exactly one time verb, and the two are each other's inverse. Everything else keeps 18b's rule: a zero-tick opcode is deletable, and a
	# time-carrying event that is a SEGMENT of somebody's span (a Fermata inside a note,
	# a tie) is not addressable on its own.
	var deletable: bool
	var restful := false        # a rest span: the one bar the UN-REST is offered on
	if not ev.is_empty() and ev.has("span_kind"):
		deletable = direct and str(ev["span_kind"]) == "note"
		restful = direct and str(ev["span_kind"]) == "rest"
	else:
		deletable = not ev.is_empty() and direct \
				and int(ev.get("opcode", -1)) >= 0x80 \
				and not (int(ev["opcode"]) in Catalog.TIME_CARRYING)
	# The PAINT (2026-08-19b §2): a note inside the silence, starting where the author
	# grabbed and running to the end of the rest. Offered only when the grab is strictly
	# INSIDE the span — flush at the head the paint would BE the un-rest, and two rows that
	# write the same bytes is one row too many.
	var paint: Dictionary = {}
	if restful and grab_ticks > 0:
		var span_ticks := int(ev.get("span_total_ticks", 0))
		if grab_ticks < span_ticks:
			paint = {"at": int(ev["offset"]), "label": _event_label(ev),
				"offset_ticks": grab_ticks, "duration_ticks": span_ticks - grab_ticks}
	# The OUTRO rows (ADR-0085 2026-08-19c), offered where the track ENDS — a click on the
	# terminator chip, or anywhere in the empty lane past it, which resolves to the same
	# anchor. The outro is not an event and 1917 of the corpus's 1928 terminated tracks have
	# none, so there is no bar to point at until it exists; the track's end is the one thing
	# always drawn. A STUB offers nothing: it has no terminator, and the NoEnd phantom is
	# already advertising the EndBar insert that would give it one.
	var outro: Dictionary = {}
	if bool(tr.get("has_terminator", false)) and not ev.is_empty() \
			and int(ev.get("opcode", -1)) == Catalog.END_BAR:
		outro = {"ticks": int(tr.get("outro_ticks", 0)), "end_tick": int(tr.get("end_tick", 0))}
	# The SPAN END (ADR-0085 amendment 2026-08-19f). A multi-segment span's LAST byte
	# boundary — the one after its final `Fermata`. 18c §5 routed `0x81` to the time lane,
	# where it is drawn as the note bar's amber TAIL rather than as a chip; that is right,
	# but it left the fermata with no click target, so the only address the bar offered was
	# `at` — the boundary after the HEAD note byte, which sits INSIDE the picture the author
	# is pointing at, and where an opcode fires when the note's own ticks are up rather than
	# at the span's start tick. FFT writes at the span END in 1534 of its 1619 multi-segment
	# spans (805 `EndBar`, 162 `Dynamics`, 107 `Instrument`), so it is the ordinary address,
	# not an exotic one — it was simply unreachable. Both are offered, each named for the
	# boundary it is, as two ROWS rather than two halves of the bar: a span can be 6 px wide
	# and a menu row is zoom-independent where a pixel-half is not (ADR-0095 §2's lesson).
	var span_end: Dictionary = {}
	var segs: Array = ev.get("span_segments", []) as Array
	if direct and segs.size() > 1:
		var last_seg: Dictionary = _own_event(tr, int(segs[segs.size() - 1]))
		if not last_seg.is_empty():
			var end_at: int = int(last_seg["offset"]) + int(last_seg["size"])
			span_end = {
				"at": end_at,
				"label": str(last_seg.get("label", "Fermata")),
				"tick": int(ev.get("start_tick", 0)) + int(ev.get("span_total_ticks", 0)),
				"inside_tick": int(ev.get("start_tick", 0)) + int(ev.get("span_note_ticks", 0)),
				"phantom_boundary": bool(tr.get("stub", false)) and end_at == _own_end(tr),
			}
	# The CUT (ADR-0085 amendment 2026-08-19e §2). Re-ordering an opcode is delete + insert —
	# 18b §4 already addresses both endpoints — but the Add menu re-inserts CORPUS-mode
	# params, so a plain re-order silently reset the value the author had typed. Cut carries
	# the bytes it removed, and the paste writes exactly those back. Offered only on an
	# opcode `can_insert` will take again: it refuses the FLOW opcodes, and a cut with no
	# lawful paste is a trap rather than a verb.
	var cut: Dictionary = {}
	if deletable and not ev.has("span_kind") \
			and Catalog.can_insert(int(ev.get("opcode", -1)), false):
		cut = {"at": int(ev["offset"]), "label": _event_label(ev),
			"opcode": int(ev["opcode"]),
			"params": PackedByteArray(ev.get("params", []) as Array)}
	return {
		"pair_idx": int(view.get("pair_idx", -1)),
		"track": t,
		"track_idx": int(tr.get("track_idx", -1)),
		"at": at,
		"outro": outro,
		"anchor": {} if ev.is_empty() else {
			"event_index": int(ev["event_index"]),
			"label": _event_label(ev),
			"tick": int(ev.get("tick", ev.get("start_tick", 0))),
		},
		"direct": direct,
		# The boundary BEFORE the anchor's own first byte — the paste's other endpoint.
		# It is not derivable from `at` on the surface: zero-tick opcodes stack, so "before
		# `Oct3`" and "after `Oct3`" are two different addresses at the same tick (18b §4).
		"before_at": base if ev.is_empty() else int(ev["offset"]),
		"span_end": span_end,
		"cut": cut,
		# `ticks` is what a Delete on a SPAN leaves behind — the silence the paint spends.
		# The row says the number so the composition (delete → sound the rest) is legible
		# from the menu instead of only from the ADR.
		"delete": {} if not deletable else {"at": int(ev["offset"]), "label": _event_label(ev),
			"ticks": int(ev.get("span_total_ticks", 0))},
		"unrest": {} if not restful else {"at": int(ev["offset"]), "label": _event_label(ev),
			"ticks": int(ev.get("span_total_ticks", 0))},
		"paint": paint,
		"phantom_boundary": bool(tr.get("stub", false)) and at == _own_end(tr),
	}


## One of THIS track's own decoded events by index (notes and commands share the
## numbering), or {} when the index names none.
static func _own_event(tr: Dictionary, event_index: int) -> Dictionary:
	if event_index < 0:
		return {}
	for lst in [tr.get("commands", []), tr.get("notes", [])]:
		for e in lst:
			if int(e.get("event_index", -1)) == event_index:
				return e
	return {}


## Where the track's own authored stream stops — the phantom's boundary on a stub.
static func _own_end(tr: Dictionary) -> int:
	var end := int(tr.get("offset", 0))
	for lst in [tr.get("commands", []), tr.get("notes", [])]:
		for e in lst:
			end = maxi(end, int(e.get("offset", 0)) + int(e.get("size", 0)))
	return end


## What the menu calls this event: the same short code its chip wears (so the menu
## names what the author is looking at), or a note's key label.
static func _event_label(e: Dictionary) -> String:
	return _chip_code(e) if e.has("params") else str(e.get("label", "?"))


## Cursor-anchored zoom, on whichever axis is currently on screen. In roll mode that is
## the roll's own axis, whose band runs to ROLL_MAX_PPF — the whole reason the roll has an
## axis at all is that the shared one's ceiling is where the complaint screenshot already sat.
func _zoom_at(factor: float, cursor_x: float) -> void:
	if _roll:
		_roll_axis_obj().zoom_at(factor, cursor_x)
		_refit()
		return
	if _tl:
		_tl.zoom_at(factor, cursor_x)


func _gui_input(event: InputEvent) -> void:
	# Shared-axis gestures first (the FramesBar mirror): ctrl+wheel zooms and
	# middle/shift-drag pans THE TIMELINE'S axis — the panel is an extension of
	# the band, so its zoom is the band's zoom (ADR-0085 frame-axis §1).
	if event is InputEventMouseMotion and _panning:
		# In roll mode the gesture drives the ROLL's axis: the roll is not an extension of
		# the band, it is a second reading of one lane on its own clock, and panning it
		# must not drag the frames bar and the score along with it.
		if _roll:
			_roll_axis_obj().scroll_x -= event.position.x - _pan_last_x
			_pan_last_x = event.position.x
			_refit()
			return
		if _tl == null:
			return
		_tl.pan_by(event.position.x - _pan_last_x)
		_pan_last_x = event.position.x
		return
	# The DRAG (2026-08-19b §6). Armed by the press below, it becomes live once the cursor has
	# travelled DRAG_THRESHOLD — under that the gesture is still a click, so click-to-inspect
	# survives a shaky hand. Every motion reports a delta FROM THE GRAB, so the session can
	# re-plan each one against the pre-drag bytes rather than compounding (ADR-0095 §4).
	if event is InputEventMouseMotion and not _drag.is_empty():
		if not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			# The button came up somewhere this panel never saw (outside its rect, or over a
			# popup). Disarm on the first buttonless motion rather than waiting for a release
			# that will never arrive, or the next hover would drag.
			if _drag_live:
				pair_drag_ended.emit()
			_drag = {}
			_drag_live = false
			_drag_last = {}
			return
		if not _drag_live:
			var dx: float = absf(event.position.x - float(_drag["start_x"]))
			var dy: float = absf(event.position.y - float(_drag["start_y"]))
			if maxf(dx, dy) < DRAG_THRESHOLD:
				return
			# AXIS LOCK, decided once, at the moment the press becomes a drag. In roll mode a
			# note bar hosts two verbs — a MOVE in time (a structural byte splice) and a KEY
			# (a bounded one-byte patch) — and running both from one gesture would put two
			# different kinds of edit inside one undo bracket. Whichever way the cursor
			# actually went wins; a gesture whose winner is refused falls back to the other,
			# and one with no legal axis at all disarms rather than becoming a dead drag.
			var want_key: bool = bool(_drag.get("roll", false)) and dy > dx
			if want_key and bool(_drag.get("can_key", false)):
				_drag["gesture"] = "key"
			elif not bool(_drag.get("can_move", false)):
				if bool(_drag.get("can_key", false)):
					_drag["gesture"] = "key"
				else:
					_drag = {}
					return
			_drag_live = true
			# Seed the filter with the key the note ALREADY has, so the first motion of a
			# key drag — which is by definition still on the row it started on — does not
			# write the byte that is already there.
			_drag_last = {"verb": "key", "relative_key": int(_drag.get("start_key", -1))} \
					if str(_drag.get("gesture", "")) == "key" else {}
			pair_drag_started.emit(_drag)
		var motion := drag_motion(_drag, event.position.x, event.position.y)
		# A key drag re-states the SAME key on most motions (a row is 12 px tall), and
		# re-dispatching it would spend a full re-derive per mouse move for no change.
		# Suppressing on the last EMITTED value, not on the start value, is what lets a
		# drag away and back restore the original key while the button is still down.
		if not motion.is_empty() and motion != _drag_last:
			_drag_last = motion
			var payload := _drag.duplicate()
			payload.merge(motion, true)
			pair_dragged.emit(payload)
		accept_event()
		return
	if (_tl or _roll) and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed and event.ctrl_pressed:
			_zoom_at(1.15, event.position.x)
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed and event.ctrl_pressed:
			_zoom_at(1.0 / 1.15, event.position.x)
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
			_pan_last_x = event.position.x
			return
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.shift_pressed:
			_panning = true
			_pan_last_x = event.position.x
			return
		if not event.pressed:
			_panning = false
	# The panel COMPOSES as well as navigates (§2): a right-click resolves to a byte
	# boundary and hands the page a named context to build its verbs from.
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		var ctx := context_at(event.position)
		if not ctx.is_empty():
			pair_context_requested.emit(ctx)
			accept_event()
		return
	if event is InputEventMouseButton and not event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		# Release closes the coalesce bracket — one drag, one undo — and disarms. A press
		# that never crossed the threshold was a click, and emits nothing.
		if _drag_live:
			pair_drag_ended.emit()
			accept_event()
		_drag = {}
		_drag_live = false
		_drag_last = {}
		return
	if not (event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var lay := layout(_view, size.x, _state(), _axis_obj(), _anchor)
	# Arm the drag on the SAME press that selects: the selection is what the F1 inspector
	# opens, and a gesture that turns out to be a click must still have inspected something.
	_drag = drag_target(_view, lay, event.position)
	_drag_live = false
	var hit := hit_in(lay, event.position)
	match hit["kind"]:
		"toggle_loop":
			toggle_loop(int(hit["track"]), int(hit["loop_index"]))
			accept_event()
		"toggle_all":
			set_all_unwound(not _all_unwound(_view, _unwound))
			accept_event()
		"toggle_roll":
			toggle_roll()
			accept_event()
		"toggle_section":
			toggle_section(int(hit["track"]))
			accept_event()
		"select":
			_selected = {"track": int(hit["track"]), "event_index": int(hit["event_index"])}
			queue_redraw()
			event_selected.emit(int(hit["track"]), int(hit["event_index"]))
			accept_event()


## Position-dependent hover detail: the folded badge PEEKS its body (decision 3);
## a typed chip reveals its full opcode name + params; a note bar its timing.
func _get_tooltip(at_position: Vector2) -> String:
	var lay := layout(_view, size.x, _state(), _axis_obj(), _anchor)
	for br in lay["brackets"]:
		if (br["toggle_rect"] as Rect2).has_point(at_position):
			return _peek_text(int(br["track"]), int(br["loop_index"]))
	for chip in lay["chips"]:
		if (chip["rect"] as Rect2).has_point(at_position):
			return _with_verdict(str(chip["full"]), chip)
	for bar in lay["span_bars"]:
		if (bar["rect"] as Rect2).has_point(at_position):
			return _with_verdict(str(bar["label"]), bar)
	var header: Dictionary = lay["header"]
	if (header["unwind_all_rect"] as Rect2).has_point(at_position):
		return "Wind/unwind every loop in the pair"
	return ""


## Opcode-honesty (§2): the verdict + its reason ride the EXISTING chip/note hover
## label (not the F1 inspector), so the at-a-glance map and the "why is this here?"
## answer sit together, directly above the energy band that corroborates them.
static func _with_verdict(base: String, item: Dictionary) -> String:
	var verdict := str(item.get("verdict", ""))
	var reason := str(item.get("reason", ""))
	if verdict == "":
		return base
	if reason == "":
		return "%s\n%s" % [base, verdict]
	return "%s\n%s — %s" % [base, verdict, reason]


## The hover-peek body summary for one folded loop: what one pass contains,
## without committing to the unroll.
func _peek_text(track_idx: int, loop_index: int) -> String:
	var tracks: Array = _view.get("tracks", [])
	if track_idx >= tracks.size():
		return ""
	var tr: Dictionary = tracks[track_idx]
	if loop_index < 0:
		return _phantom_peek_text(tr)
	var loops: Array = tr.get("loops", [])
	if loop_index >= loops.size():
		return ""
	var lp: Dictionary = loops[loop_index]
	var start := int(lp.get("start_tick", 0))
	var end := int(lp.get("end_tick", 0))
	var parts: Array = []
	for n in tr.get("notes", []):
		if int(n.get("start_tick", 0)) >= start and int(n.get("start_tick", 0)) < end:
			parts.append("%s · v%d" % [str(n.get("label", "")), int(n.get("velocity", 0))])
	for c in tr.get("commands", []):
		var tick := int(c.get("tick", 0))
		if tick >= start and tick < end and str(c.get("kind", "")) != "structure":
			parts.append(_chip_full(c).get_slice(" @ ", 0))
	var body: String = ", ".join(parts) if not parts.is_empty() else "(empty body)"
	return "plays ×%d — body: %s" % [int(lp.get("count", 0)), body]


## The NoEnd phantom's hover: what the stub borrows, and what it does to it. Says
## "no EndBar" out loud — the fold badge is a derived tell, not an authored byte.
static func _phantom_peek_text(tr: Dictionary) -> String:
	var ft: Dictionary = tr.get("flow_through", {})
	if ft.is_empty():
		return ""
	var borrowed := 0
	for n in ft.get("notes", []):
		if bool(n.get("flowed", false)):
			borrowed += 1
	var into := int(ft.get("into_track", -1))
	var where: String = "Track %s" % _TRACK_LETTERS[into % 2] if into >= 0 \
			else "the bytecode that follows"
	var text := "no EndBar — this voice runs on into %s and sounds %d borrowed note%s" \
			% [where, borrowed, "" if borrowed == 1 else "s"]
	var bend := int(ft.get("own_pitch_bend_total", 0))
	if bend != 0:
		text += "\nits own PitchBendRel %+d detunes them" % bend
	return text + "\n(a derived span — no byte encodes it)"


# --- Draw -------------------------------------------------------------------

func _draw() -> void:
	if _view.is_empty():
		return
	var lay := layout(_view, size.x, _state(), _axis_obj(), _anchor)
	var font := get_theme_default_font()
	var fs := 9
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG)

	# Provenance header band + the unwind-all chip.
	var header: Dictionary = lay["header"]
	draw_rect(header["rect"], COL_GUTTER)
	draw_string(font, Vector2(PAD_X, HEADER_H - 5.0), str(header["text"]),
			HORIZONTAL_ALIGNMENT_LEFT,
			int(size.x - BADGE_W - ROLL_BADGE_W - PAD_X * 4.0), 10, COL_TEXT)
	# The [ Lanes | Roll ] toggle: the half in force is lit, the other dim, so the chip says
	# both which reading you are in and that a second one exists. The second word is placed
	# from the MEASURED width of the first, with a rule between them — a hardcoded x put
	# "Roll" exactly where "Lanes" ended and the chip read "LanesRoll".
	var rr: Rect2 = header["roll_rect"]
	draw_rect(rr, COL_SECTION)
	var in_roll: bool = bool(header.get("roll", false))
	var lanes_w: float = font.get_string_size("Lanes", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var div_x: float = rr.position.x + 4.0 + lanes_w + 4.0
	draw_string(font, Vector2(rr.position.x + 4.0, rr.end.y - 4.0), "Lanes",
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_TEXT_DIM if in_roll else COL_TEXT)
	draw_line(Vector2(div_x, rr.position.y + 3.0), Vector2(div_x, rr.end.y - 3.0),
			COL_TEXT_DIM, 1.0)
	draw_string(font, Vector2(div_x + 4.0, rr.end.y - 4.0), "Roll",
			HORIZONTAL_ALIGNMENT_LEFT, int(maxf(rr.end.x - div_x - 5.0, 1.0)), fs,
			COL_BRACKET if in_roll else COL_TEXT_DIM)
	var ua: Rect2 = header["unwind_all_rect"]
	draw_rect(ua, COL_SECTION)
	draw_string(font, Vector2(ua.position.x + 3.0, ua.end.y - 4.0),
			"⇕ all", HORIZONTAL_ALIGNMENT_LEFT, int(ua.size.x - 4.0), fs,
			COL_BRACKET if bool(header["all_unwound"]) else COL_TEXT_DIM)

	# Ruler band: IN-BAND tick marks + "tick · seconds" tells. The frame grid (below)
	# now owns the full-height reference, so the quarter-tick line is demoted to a
	# short mark within the ruler band and keeps only its seconds label.
	for m in lay["ruler"]:
		var x: float = m["x"]
		draw_line(Vector2(x, HEADER_H + 3.0), Vector2(x, HEADER_H + RULER_H),
				Color(COL_RULER.r, COL_RULER.g, COL_RULER.b, 0.25), 1.0)
		draw_string(font, Vector2(x + 2.0, HEADER_H + RULER_H - 5.0),
				"%d · %.3fs" % [int(m["tick"]), float(m["seconds"])],
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_RULER)

	# Lane rows (alternating fills) + gutter labels.
	var i := 0
	for lane in lay["lanes"]:
		var r: Rect2 = lane["rect"]
		draw_rect(Rect2(GUTTER_W, r.position.y, r.size.x - GUTTER_W, r.size.y),
				COL_LANE_A if (i % 2 == 0) else COL_LANE_B)
		draw_rect(Rect2(0.0, r.position.y, GUTTER_W, r.size.y), COL_GUTTER)
		draw_string(font, Vector2(PAD_X, r.position.y + LANE_H - 8.0),
				str(lane["label"]), HORIZONTAL_ALIGNMENT_LEFT, int(GUTTER_W - PAD_X * 2.0),
				10, COL_TEXT_DIM)
		i += 1

	# The KEY ROLL's keyboard (amendment 2026-08-21d §4): 12 fixed rows striped so the
	# accidentals read as black keys, plus the Rest row under them. Drawn over the lane
	# fill and under everything else, with the key name in the gutter — the roll's Y axis
	# has to be readable without hovering anything.
	for rw in lay.get("roll_rows", []):
		var rwr: Rect2 = rw["rect"]
		var rwc: Color = COL_ROLL_REST_ROW if bool(rw["rest"]) \
				else (COL_ROLL_ACCIDENTAL if bool(rw["accidental"]) else COL_ROLL_NATURAL)
		draw_rect(Rect2(GUTTER_W, rwr.position.y, rwr.size.x - GUTTER_W, rwr.size.y), rwc)
		draw_line(Vector2(GUTTER_W, rwr.position.y), Vector2(rwr.size.x, rwr.position.y),
				COL_ROLL_RULE, 1.0)
		draw_string(font, Vector2(GUTTER_W - 30.0, rwr.end.y - 3.0), str(rw["label"]),
				HORIZONTAL_ALIGNMENT_LEFT, 28.0, fs,
				COL_TEXT_DIM if bool(rw["accidental"]) or bool(rw["rest"]) else COL_TEXT)

	# Per-frame orientation grid (ADR-0085 amendment 2026-08-12): full-height lines
	# at round absolute frames, coinciding pixel-for-pixel with the score's
	# _draw_grid below. Painted ABOVE the lane/section background fills but BELOW the
	# chips/notes/brackets/playhead, so the empty inter-chip field shows the grid
	# while the chips themselves stay crisp. Spans below the ruler band → content_h.
	for g in lay["grid"]:
		var gx: float = g["x"]
		draw_line(Vector2(gx, HEADER_H + RULER_H), Vector2(gx, float(lay["content_h"])),
				COL_GRID, 1.0)

	# Span bars (§5): ONE bar per span, up to three fills — the note's own delta_time in
	# its OCTAVE's shade of the note hue, amber for the sounding time its Fermata
	# segments add, grey for a rest. Fixed height, labeled, ghost copies dimmer.
	#
	# THREE passes, because the boundary hairline has to sit above every fill and below
	# every outline: drawn per-bar it would land on top of the bar drawn after it, and
	# drawn last it would cover the vertical strokes of a selected bar's outline — on a
	# narrow bar, that is the whole selection tell.
	for bar in lay["span_bars"]:
		var r: Rect2 = bar["rect"]
		var rest := bool(bar.get("rest", false))
		var col: Color = COL_BAR_REST if rest \
				else octave_tint(COL_BAR, int(bar.get("octave", OCT_MID)))
		var amber := COL_BAR_FERMATA
		if bool(bar.get("ghost", false)):
			col = Color(col.r, col.g, col.b, GHOST_COPY_A)
			amber = Color(amber.r, amber.g, amber.b, GHOST_COPY_A)
		draw_rect(bar.get("note_rect", r), col)
		if bar.has("fermata_rect"):
			draw_rect(bar["fermata_rect"], amber)

	# Span separators: one hairline per span BOUNDARY, so two neighbouring bars of the
	# same fill stop being one unbroken ribbon. Above the fills, under every outline.
	for sep in lay.get("span_seps", []):
		var sx: float = sep["x"]
		var sy: float = sep["y"]
		draw_line(Vector2(sx, sy), Vector2(sx, sy + float(sep["h"])), COL_SPAN_EDGE, 1.0)

	for bar in lay["span_bars"]:
		var r: Rect2 = bar["rect"]
		var rest := bool(bar.get("rest", false))
		var col: Color = COL_BAR_REST if rest \
				else octave_tint(COL_BAR, int(bar.get("octave", OCT_MID)))
		if bool(bar.get("ghost", false)):
			col = Color(col.r, col.g, col.b, GHOST_COPY_A)
		# BORROWED: a violet outline, an axis independent of the ghost dim. Dim says
		# "a copy"; violet says "not this track's bytes". A dimmed violet item is a
		# copy of borrowed bytes. The outline (not a fill swap) keeps the §2 verdict
		# hue readable underneath — ownership and honesty are different questions.
		# It rides the WHOLE span, blue and amber alike: the ticks are one note's.
		if bool(bar.get("flowed", false)):
			draw_rect(r, COL_FLOWED, false, 2.0)
		# Muted (provably silent) → keep the hue, strike it with 45° hatch. Faint
		# (gray-zone clip, not provably silent) → the softer dotted + ≈ tell, no hatch.
		if str(bar.get("verdict", "")) == Verdicts.MUTED:
			_draw_hatch(r)
		elif bool(bar.get("faint", false)):
			_draw_faint(r, font)
		if _is_selected(bar):
			draw_rect(r, COL_SELECT, false, 1.5)
		# The label draws the widest LADDER rung that fits inside the bar — never a
		# floor, never a mid-token cut. Ink follows the fill's luminance, because the
		# octave tint now runs from near-black to near-white under it.
		var avail := r.size.x - 4.0
		var text := fit_label(font, fs, span_text_rungs(bar, bool(lay.get("roll", false))), avail)
		if not text.is_empty():
			draw_string(font, r.position + Vector2(2.0, (r.size.y + float(fs)) * 0.5 - 1.0), text,
					HORIZONTAL_ALIGNMENT_LEFT, int(maxf(avail, 1.0)), fs,
					label_ink(col, rest))

	# Boundary grips (2026-08-19b §6): the handles a resize is grabbed by, drawn ONLY where a
	# drag has currency to spend and the resize is legal — so most bars carry none, which is
	# what the corpus actually is rather than a phantom handle over a refusal.
	for g in lay.get("grips", []):
		var gr: Rect2 = g["rect"]
		draw_rect(gr, COL_GRIP)
		draw_line(Vector2(gr.get_center().x, gr.position.y),
				Vector2(gr.get_center().x, gr.end.y), COL_GRIP_LINE, 1.0)

	# Typed chips: fixed-width boxes with the short code; detail on hover.
	for chip in lay["chips"]:
		var r: Rect2 = chip["rect"]
		var col: Color = COL_CHIP
		match str(chip["kind"]):
			"structure":
				col = COL_CHIP_STRUCT
			"tempo":
				col = COL_CHIP_TEMPO
		# Opcode-honesty verdict paints over the kind tint (§2): the author reads the
		# code as a Live/Pre-arm/Inert/Structural map, corroborated by the energy band.
		if COL_VERDICT.has(str(chip.get("verdict", ""))):
			col = COL_VERDICT[str(chip["verdict"])]
		if bool(chip.get("ghost", false)):
			col = Color(col.r, col.g, col.b, GHOST_COPY_A)
		draw_rect(r, Color(col.r, col.g, col.b, 0.22))
		# BORROWED chips take the violet border in place of their own, so the §2
		# verdict hue still fills them: ownership on the edge, honesty inside.
		draw_rect(r, COL_FLOWED if bool(chip.get("flowed", false)) else col, false,
				2.0 if bool(chip.get("flowed", false)) else 1.0)
		# A Muted chip (a wholly-Muted track's voice-writes) keeps its hue and hatches;
		# Live-by-proxy already recoloured above and is never hatched (§2/§7).
		if str(chip.get("verdict", "")) == Verdicts.MUTED:
			_draw_hatch(r)
		if _is_selected(chip):
			draw_rect(r, COL_SELECT, false, 1.5)
		draw_string(font, Vector2(r.position.x + 2.0, r.end.y - 4.0), chip_text(chip),
				HORIZONTAL_ALIGNMENT_LEFT, int(CHIP_W - 3.0), fs, col)

	# Per-track energy bands (§3): a trough + the shared-normalized RMS swell on the
	# frame axis, directly under the track's opcode lanes — the empirical ground truth
	# for the §2 verdicts (flat = those opcodes really are inert here; tall = live).
	for band in lay["energy_bands"]:
		var eb: Rect2 = band["rect"]
		draw_rect(eb, COL_ENERGY_BG)
		var epts: PackedVector2Array = band["points"]
		if epts.size() >= 2:
			var ebottom := eb.end.y
			var fill := PackedVector2Array()
			fill.append(Vector2(epts[0].x, ebottom))
			fill.append_array(epts)
			fill.append(Vector2(epts[epts.size() - 1].x, ebottom))
			draw_colored_polygon(fill, COL_ENERGY)
		# The display-only "silent in isolation" tell (§6): a floor-level track whose
		# shared-normalized swell fills the band would otherwise read as sounding.
		if bool(band.get("silent_in_isolation", false)):
			draw_string(font, Vector2(eb.position.x + PAD_X, eb.position.y + 11.0),
					"silent in isolation (peak %.4f)" % float(band.get("raw_peak", 0.0)),
					HORIZONTAL_ALIGNMENT_LEFT, int(eb.size.x - PAD_X * 2.0), fs, COL_FAINT)

	# Per-track no-op A/B verdict rows: the measured Δ + its a-priori tier, tinted
	# inert/faint/changed, under the track's energy band (ADR-0085 amendment 2026-08-12 §4).
	for nt in lay["noop_tells"]:
		var nr: Rect2 = nt["rect"]
		var tell: Dictionary = nt["tell"]
		draw_string(font, Vector2(nr.position.x + PAD_X, nr.end.y - 2.0),
				_noop_tell_text(tell), HORIZONTAL_ALIGNMENT_LEFT,
				int(nr.size.x - PAD_X * 2.0), fs,
				COL_NOOP.get(str(tell.get("tier", "")), COL_TEXT_DIM))

	# The joint (mixed-pair) energy waveform: the combined sound of both voices. The BASELINE
	# mix is a muted blue area with a solid blue top edge; once the A/B has run, the PRUNED
	# mix is a bold tier-coloured line ON TOP, so the Δ reads as the gap between the two.
	var jb: Dictionary = lay.get("joint_band", {})
	if not jb.is_empty():
		var jr: Rect2 = jb["rect"]
		draw_rect(jr, COL_ENERGY_BG)
		draw_rect(Rect2(0.0, jr.position.y, GUTTER_W, jr.size.y), COL_GUTTER)
		draw_string(font, Vector2(PAD_X, jr.position.y + 10.0), "mix A/B",
				HORIZONTAL_ALIGNMENT_LEFT, int(GUTTER_W - PAD_X * 2.0), fs, COL_TEXT_DIM)
		var bpts: PackedVector2Array = jb["baseline_points"]
		if bpts.size() >= 2:
			var fill := PackedVector2Array()
			fill.append(Vector2(bpts[0].x, jr.end.y))
			fill.append_array(bpts)
			fill.append(Vector2(bpts[bpts.size() - 1].x, jr.end.y))
			draw_colored_polygon(fill, Color(COL_ENERGY.r, COL_ENERGY.g, COL_ENERGY.b, 0.30))
			draw_polyline(bpts, COL_ENERGY, 1.0)
		var ppts: PackedVector2Array = jb["pruned_points"]
		var has_pruned: bool = ppts.size() >= 2
		var pcol: Color = COL_NOOP.get(str(jb.get("tier", "")), COL_BRACKET)
		if has_pruned:
			draw_polyline(ppts, pcol, 2.0)
		# A legend so the two curves are never ambiguous: "baseline" (blue) then, after the
		# A/B, "pruned <tier> Δ<n>" (tier colour). Drawn from just past the gutter.
		var lx := jr.position.x + PAD_X
		draw_string(font, Vector2(lx, jr.position.y + 10.0), "baseline",
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_ENERGY)
		if has_pruned:
			draw_string(font, Vector2(lx + 58.0, jr.position.y + 10.0),
					"vs pruned  %s Δ%.4f" % [str(jb.get("tier", "")), float(jb.get("max_abs", 0.0))],
					HORIZONTAL_ALIGNMENT_LEFT, int(jr.size.x - 58.0 - PAD_X * 2.0), fs, pcol)

	# Loop brackets + the wind/unwind badge (the toggle).
	for br in lay["brackets"]:
		var y: float = br["y"]
		# A loop bracket is amber (authored repetition); the NoEnd phantom is violet
		# (a span with no byte behind it), matching the borrowed items it reveals.
		var bc: Color = COL_PHANTOM if bool(br.get("phantom", false)) else COL_BRACKET
		draw_line(Vector2(br["x0"], y), Vector2(br["x1"], y), bc, 2.0)
		draw_line(Vector2(br["x0"], y - 4.0), Vector2(br["x0"], y), bc, 2.0)
		draw_line(Vector2(br["x1"], y - 4.0), Vector2(br["x1"], y), bc, 2.0)
		var tr_: Rect2 = br["toggle_rect"]
		draw_rect(tr_, Color(bc.r, bc.g, bc.b, 0.25))
		draw_rect(tr_, bc, false, 1.0)
		draw_string(font, Vector2(tr_.position.x + 3.0, tr_.end.y - 4.0), str(br["badge"]),
				HORIZONTAL_ALIGNMENT_LEFT, int(BADGE_W - 4.0), fs, bc)

	# The shared playhead (frame-axis §6): draw-only — the panel shows where the
	# band's playhead sits over the pair's projected events, and never seeks.
	var px := _playhead_x()
	if px >= GUTTER_W:
		draw_line(Vector2(px, HEADER_H), Vector2(px, float(lay["content_h"])),
				COL_PLAYHEAD, 1.5)

	# Section header bars LAST (over the gutter fill), timeline idiom.
	for sec in lay["sections"]:
		var hr: Rect2 = sec["rect"]
		draw_rect(hr, COL_SECTION)
		var arrow: String = "▸" if bool(sec["collapsed"]) else "▾"
		draw_string(font, Vector2(PAD_X, hr.position.y + SECTION_H - 6.0),
				"%s  %s" % [arrow, str(sec["label"])], HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
				COL_STUB if bool(sec["stub"]) else COL_TEXT)


func _is_selected(item: Dictionary) -> bool:
	return not _selected.is_empty() \
			and int(_selected.get("track", -1)) == int(item.get("track", -2)) \
			and int(_selected.get("event_index", -1)) == int(item.get("event_index", -2))


## 45° diagonal hatch over a Muted chip / note bar (§7): repeated draw_line clipped to
## the rect — the recognisable "struck out / does nothing" read. Lines run bottom-left
## to top-right; each starts at a stepped x along the bottom edge and rises by the
## rect height, clipped so nothing bleeds past the rect. Pure paint, no state.
func _draw_hatch(rect: Rect2) -> void:
	var h := rect.size.y
	# Sweep the diagonal's bottom anchor from left of the rect to its right edge so the
	# whole face is covered (a 45° line entering at x rises to x+h at the top).
	var x := rect.position.x - h
	while x < rect.end.x:
		var x0 := x
		var y0 := rect.end.y
		var x1 := x + h
		var y1 := rect.position.y
		# Clip the segment to the rect's x-span (y already spans exactly one height).
		if x0 < rect.position.x:
			var dx := rect.position.x - x0
			x0 = rect.position.x
			y0 -= dx
		if x1 > rect.end.x:
			var dx := x1 - rect.end.x
			x1 = rect.end.x
			y1 += dx
		draw_line(Vector2(x0, y0), Vector2(x1, y1), COL_HATCH, 1.0)
		x += HATCH_STEP


## The gray-zone faint tell (§7): a dotted, dimmed outline plus a small ≈ — audible but
## nearly silent, NOT provably muted, so never a hatch. Mirrors the EffectScoreTimeline
## _stroke_dashed dashed-border idiom.
func _draw_faint(rect: Rect2, font) -> void:
	const DASH := 3.0
	const GAP := 2.0
	var x := rect.position.x
	while x < rect.end.x:
		var x2: float = minf(x + DASH, rect.end.x)
		draw_line(Vector2(x, rect.position.y), Vector2(x2, rect.position.y), COL_FAINT, 1.0)
		draw_line(Vector2(x, rect.end.y), Vector2(x2, rect.end.y), COL_FAINT, 1.0)
		x += DASH + GAP
	draw_string(font, Vector2(rect.position.x + 1.0, rect.position.y + rect.size.y - 4.0),
			"≈", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COL_FAINT)
