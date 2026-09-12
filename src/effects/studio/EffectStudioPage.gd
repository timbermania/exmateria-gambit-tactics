extends Control
## The Effect Studio as a **full-width F3 debug-dashboard page** (ADR-0069 hosted
## per ADR-0035's separate-window model, resolved this way at the user's steer —
## the standalone boot scene occluded the effect). The audio-editor split is now
## literal: the effect renders in the MAIN game window (unobstructed), and these
## controls — transport, score timeline, keyframe inspector, curve painter — live
## in the dashboard window.
##
## The page owns no 3D. It drives a bound **host** (the effect scene, e.g.
## EffectViewerScene) through a tiny interface:
##   host.studio_select_effect(effect_id)  — spawn/park the preview instance
##   host.studio_seek(frame)               — deterministic seek (ADR-0070)
##   host.studio_set_playing(playing)      — resume / halt the instance clock
##   host.studio_current_frame() -> int    — feedback while playing
## and reads the parsed EffectData itself (pure) to draw the score. No class_name
## (ADR-0004). Reuses the tested EffectScoreTimeline / Inspector / CurvePainter.

const Timeline = preload("res://src/effects/studio/EffectScoreTimeline.gd")
const FramesBar = preload("res://src/effects/studio/EffectFramesBar.gd")
const PathBar = preload("res://src/effects/studio/EffectPathBar.gd")
const Inspector = preload("res://src/effects/studio/EffectKeyframeInspector.gd")
const CurvePainter = preload("res://src/effects/studio/EffectCurvePainter.gd")
const FramesetCanvas = preload("res://src/effects/studio/FramesetCanvas.gd")
const FrameQuadTransform = preload("res://src/effects/studio/FrameQuadTransform.gd")
const SequenceCanvas = preload("res://src/effects/studio/SequenceCanvas.gd")
const SequenceThumbnail = preload("res://src/effects/studio/SequenceThumbnail.gd")
const CellColour = preload("res://src/effects/studio/SequenceCellColour.gd")
const ColourRibbon = preload("res://src/effects/studio/ColourRibbon.gd")
const ColourTrack = preload("res://src/effects/studio/ColourKeyframeTrack.gd")
const LifeColumn = preload("res://src/effects/studio/ColourLifeColumn.gd")
const ColourPicker_ = preload("res://src/effects/studio/ColourBoxPicker.gd")
const LifeWindow = preload("res://src/effects/studio/EmitterLifeWindow.gd")
const LifeMap = preload("res://src/effects/studio/SequenceLifeMap.gd")
const EmitterSpriteColor = preload("res://src/effects/studio/EmitterSpriteColor.gd")
const ColourKeyframeFit = preload("res://src/effects/studio/ColourKeyframeFit.gd")
const EmitterSubject = preload("res://src/effects/studio/EmitterSequenceSubject.gd")
const FocusBlock = preload("res://src/effects/studio/SequenceFocusBlock.gd")
const RegionScope = preload("res://src/effects/studio/FramesetRegionScope.gd")
const CurvePaintModel = preload("res://src/effects/studio/CurvePaintModel.gd")
const CurveShapeSet = preload("res://src/effects/studio/CurveShapeSet.gd")
const EffectCurveClass = ExMateriaEffects.EffectCurve
const Sparkline = preload("res://src/effects/studio/EffectCurveSparkline.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const CameraChannelClass = preload("res://src/effects/studio/CameraChannel.gd")
const GhostProjector = preload("res://src/effects/studio/SoundGhostProjector.gd")
const RenderQueue = preload("res://src/effects/studio/SoundRenderQueue.gd")
const EffectSfxEngineScript = preload("res://addons/exmateria_sound/runtime/effect_sfx_engine.gd")
const SoundContainerModel = preload("res://src/effects/studio/SoundContainerModel.gd")
const FedsPairModel = preload("res://src/effects/studio/FedsPairModel.gd")
const NoteAudition = preload("res://src/effects/studio/FedsNoteAudition.gd")
const PairPanel = preload("res://src/effects/studio/FedsPairLanePanel.gd")
const FedsCatalog = preload("res://src/effects/studio/FedsOpcodeCatalog.gd")
const GapMath = preload("res://src/effects/studio/SoundGapMath.gd")
const JSONLoader = preload("res://addons/exmateria_sound/runtime/effect_json_loader.gd")
const EndModel = ExMateriaEffects.EffectEndModel
const EffectDataClass = ExMateriaEffects.EffectData
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const PaletteTintSolver = preload("res://src/effects/studio/PaletteTintSolver.gd")
const ScreenDataClass = ExMateriaEffects.ScreenData
const EmitterRelevance = preload("res://src/effects/studio/EmitterFieldRelevance.gd")
const Transport = preload("res://src/effects/studio/LoopTransport.gd")
const LoopRegion = preload("res://src/effects/studio/LoopRegion.gd")
const ScrubField = preload("res://src/effects/studio/ScrubField.gd")
const PlayheadMarker = preload("res://src/effects/studio/CurvePlayheadMarker.gd")

# Page-driven transport base rate (ADR-0090): the effect clock ticks 30 game frames
# a second; the page accumulates `delta × TRANSPORT_HZ × speed` and steps the bounce
# transport once per whole frame, seeking the host. Replaces the host free-run mirror.
# The pacing painter's Y-range top (#270, ADR-0093): 0..10 (baseline 2). The 600 ints wrap as an
# EffectCurve normalized by /10 — lossless for the corpus's 0..10 alphabet, and 10 is preserved
# (a 0..9 range would clamp the real 10 samples and break byte-exact round-trip).
const PACING_VMAX: int = 10
const TRANSPORT_HZ: float = 30.0
# Clamp the per-_process accumulator so a stall (breakpoint, GC) can't dump a huge
# burst of catch-up steps — each reverse step re-pumps from 0 and is expensive.
const MAX_STEPS_PER_FRAME: int = 4
# Loop-mode labels, indexed by LoopTransport.MODE_* (Off/Forward/Ping-pong).
const _LOOP_MODE_LABELS: Array = ["Loop: off", "Loop: fwd →", "Loop: ping ⇄"]
const CTX_COPY_ADDRESS: int = 0
# Camera sub-channel mask bit → its authoring lane name (the §#286 address grain).
const _CAMERA_MASK_NAME := {1: "angle", 2: "position", 4: "zoom"}
# Upper clamp for a tail edge drag (no successor to trade against): end_frame is an s16, so
# its max is 32767. Faithful still advises on over-long tweens at compile; this only bounds
# the drag against overflow (ADR-0086 boundary-drag).
const CAMERA_END_MAX := 32767
# The channel list never shrinks below this — the inspector caps its own growth so at
# least this many pixels of timeline stay visible (and scrollable) beneath the ruler.
const MIN_CHANNELS_H: float = 180.0
# The gap left above a span when scrolling it back into view after the inspector grows over it
# (Feature 2). One lane tall (EffectScoreTimeline.LANE_H) so the selection isn't flush against
# the editor's bottom edge. A plain layout const — a nudge amount, not a tunable.
const SCROLL_INTO_VIEW_HEADROOM: float = 24.0

var _host                       # the effect scene implementing studio_* (weak coupling)
var _texture_dialog: FileDialog = null   # #280: the Export/Import .tga picker, built lazily
var _texture_dialog_is_export: bool = false
var _timeline
# The FEDS pair LANE PANEL (ADR-0085 2026-08-11 amendment): the pair editor's
# page-level navigator/structure view, a band of the body between the inspector
# and the frames bar. Visible only while a pair target is open; the F1 inspector
# stays the edit surface. Hosted in its own ScrollContainer so a capped band
# scrolls internally instead of overdrawing the ruler. See _update_pair_panel.
var _pair_panel
var _pair_scroll: ScrollContainer
var _frames_bar
var _body                       # holds the three overlaid children (channels/bar/editor)
## The drill-down trail as its own full-width strip above the inspector row — the nav
## stack's presentation, not a second model of it (see EffectPathBar).
var _path_bar
var _scroll: ScrollContainer
var _prev_editor_h: float = 0.0      # last inspector height — re-scroll the timelines by its delta
## The channel scroll settles ONE deferred hop after `_relayout`, and both writers go
## through that hop so they cannot race each other. See `_settle_channel_scroll`.
var _settle_target: int = -1         # scroll `_relayout` last asked for (−1 = leave it alone)
var _settle_queued: bool = false     # one continuation per flush, however many flows ran
var _into_view_pending: bool = false # a FRESH span selection is waiting to be scrolled into view
## THE NUDGE HAS TO SURVIVE THE SETTLING WINDOW, and this is what bounds it.
##
## Firing once per click is not enough, and that is measured, not feared: in the N=11 suite
## run of 2026-08-23 the acceptance test failed `rect.y=22.0 scroll=198.0 max=442.0
## page=180.0` while BOTH ordering assertions passed. The nudge ran, ran after `_relayout`'s
## write, and still left the span behind the editor — because the viewport shrink that
## creates the scroll range at all (page 442 -> 180) arrives on a LATER flow, after the
## one-shot flag has been consumed, and nothing re-nudges.
##
## So the nudge re-arms on every `_relayout` whose editor height actually MOVED, for as long
## as the window is open.
##
## IT DOES NOT CLOSE ON THE FIRST `delta == 0`, and that was the first attempt's bug. A
## probe trace at N=11 showed this flag set and cleared again on the very next pass: the
## flows straight after a click carry `delta = 0`, because the height latch is already at
## its high-water from `_load_effect`. The window shut before any height change could reopen
## it, so the guard was inert — which is why the run that added it still failed the suite at
## N=10 with `scroll=262`, the channel list pinned at exactly its maximum (442 − 180).
##
## BOUNDED BY THE SELECTION INSTEAD, which is what keeps ADR-0073's rule intact. Drill,
## step-back and passive re-renders also change the editor height, and re-scrolling on those
## is what `_on_span_selected`'s "FRESH span selection only" comment forbids — so `_set_root`
## clears this for EVERY caller and `_on_span_selected` re-opens it immediately after, making
## the fresh click the only path that owns a window. Esc and a fresh effect load close it.
var _selection_settling: bool = false
## Test seam for the ordering the fix exists to establish — see `into_view_debug`.
var _into_view_runs: int = 0
var _into_view_saw_pending_settle: bool = false
var _inspector
## The unified animation screen's focus panel and the second inspector inside it — the
## frameset block's own container, out of the film strip's flow (ADR-0102 second
## amendment). See `_build_sequence_focus_overlay`.
var _focus_panel: PanelContainer
var _focus_inspector
## Whether the OPEN TARGET has a block to show. Distinct from `_focus_panel.visible`, which
## `_relayout` owns and also answers "is there room for it" — a column too SHORT to stack it
## under the player drops it (`focus_stack_height`) without the page forgetting that the
## target has one, so it comes back when the window does.
var _focus_wanted: bool = false
var _painter
var _painter_panel: PanelContainer
var _painter_title: Label
# The #278 frameset WYSIWYG texture canvas: shows the effect's texture with the
# current frame's UV rect overlaid (read-only in v1 — drag-to-edit is #279).
# Docked top-right (unlike the curve painter's centered modal) so it sits
# alongside the inspector rather than over it; visible only while the current
# inspection target is a "frame" (see _update_frameset_canvas).
var _frameset_canvas
var _frameset_panel: PanelContainer
# The #247 sequence viewport. It shares the inspector row's RIGHT-hand area with the
# frameset canvas rather than claiming its own: the two are mutually exclusive by
# target kind (a "frame" parks the frameset canvas; an "animation", an "emitter" or a
# particle "span" parks this player), so one slot that swaps occupants keeps `_relayout`
# with a single canvas column to reason about instead of two that could both want it.
var _sequence_panel: PanelContainer
var _sequence_canvas
var _sequence_canvas_title: Label
## ADR-0130: the inspector row's LEFT column has two tabs. `_inspector` is the Values
## tab; `_texture_panel` is the Texture tab, and they are mutually exclusive occupants
## of ONE rect — the same shape the right column's two occupants already use, except
## chosen by a visible strip rather than by target kind.
##
## The tab costs the row NO height and the right column NO width: the strip takes its
## height out of the left column's own rect, and `_relayout` keeps claiming the column
## from `_inspector.content_width()` whichever tab shows, so switching cannot resize
## the player (ADR-0130 dec. 3).
var _texture_panel
var _tab_strip: HBoxContainer
var _tab_values_btn: Button
var _tab_texture_btn: Button
var _active_tab: String = "values"
var _sequence_speed_field
## The colour provenance rung the bound sequence's strip is tinted by (ADR-0103 dec. 4),
## re-resolved on every sequence bind. Read by the focus block's title, which is the ONLY
## place the rung is stated — a title suffix costs 0px in a row three surfaces share.
var _sequence_provenance: Dictionary = {}
## WHAT THE PLAYER IS ACTUALLY BOUND TO: `{anim_index, group}`, stamped by
## `_update_sequence_canvas` and empty whenever the panel is down.
##
## Stored rather than re-derived, and that is the load-bearing half of ADR-0100's amended
## decision 1. The three surfaces that need the bound address used to read it back off
## `_nav.back().ref.index` — correct while only an `animation` target could open the
## column, and silently WRONG the moment an `emitter` one can, because an emitter ref's
## `index` is an emitter index. `animations[3]` for emitter 3 decodes a real sequence and
## draws real sprites; nothing on screen says it is the wrong one. One stamp, one reader.
var _sequence_bound: Dictionary = {}
## The texture `_sequence_canvas` was last bound against, so `_update_sequence_canvas` can
## tell "the same sequence, re-rendered" from "a different sequence". Kept OUT of
## `_sequence_bound`, which is an ADDRESS and is compared field-wise in four places.
var _sequence_bound_texture: Texture2D = null
## The film strip under the player: the RESERVED slot, the scroller inside it, and the row
## the thumbnails are rebuilt into on every bind.
## The panel's body ROW: the player's square on the left, the life column on the right
## (ADR-0089 vertical-column amendment). Held because `_canvas_chrome_h` walks up from the
## canvas and has to know where the stack stops being a stack.
var _sequence_body: Control = null
## The reserved slot the vertical ribbon + strip live in. Declares a WIDTH, not a height —
## this occupant costs the canvas width now.
var _sequence_life_slot: Control = null
var _sequence_strip_scroll: ScrollContainer
var _sequence_strip_row: BoxContainer
## The Colour ribbon under the sequence player, and the RESERVED slot that holds its
## height whether or not it draws. See `_build_sequence_canvas_overlay` for why the slot
## exists at all — it is not decoration, it is what keeps the film strip still.
var _sequence_ribbon = null
## The EDITABLE colour track in the player column (ADR-0089 colour-move amendment). It hosts
## `_sequence_ribbon` in its band region, so there is ONE ribbon and the band is its own click
## target. Owned by the PAGE, not the inspector: the widgets moved columns, the logic did not.
## The vertical colour ribbon (`ColourLifeColumn`) beside the strip. Replaces
## the horizontal `ColourKeyframeTrack`, whose band is gone; the signal contract is
## identical, so every handler below is shared rather than forked.
var _sequence_life_column = null
## `SequenceLifeMap.life_rows` for the bound emitter — the projection BOTH the ribbon and
## the strip are laid out from, stamped once per rebuild so they cannot be built from two
## different walks. Empty when colour is off (the strip then falls back to the trace).
var _sequence_life_rows: Array = []
## The wrapped columns (ADR-0089 vertical-column amendment, wrap amendment 2026-08-20).
## `_sequence_life_column` / `_sequence_strip_row` are element 0 of these — kept as their own
## names because "the canonical column" is a different question from "the k-th column", and
## every caller that wants the first kind should not have to spell an index to say so.
var _sequence_life_columns: Array = []
var _sequence_strip_rows: Array = []
var _sequence_life_pairs: Array = []
## Every strip cell in reading order — the life-row thumbnails then the unreached ones.
## The strip is REBUILT from the trace and REDISTRIBUTED across columns, and those are two
## different events at two different rates: a bind rebuilds, a resize only redistributes.
## Holding the cells here is what lets the second happen without the first.
var _sequence_strip_cells: Array = []
## The split currently APPLIED, so a redistribute that would change nothing does nothing —
## `_relayout` runs on every flow and re-parenting thirty-six thumbnails per flow is a freeze.
var _strip_split: Dictionary = {}
## The widest band the life slot can currently afford one column (`life_band_ceiling`).
## Cached rather than recomputed at each `configure`, because the two callers know different
## halves: `_distribute_strip` has the slot's live width, `_bind_life_column` has the rows.
##
## DELIBERATELY NOT PART OF `_strip_split`'s guard. That guard exists to stop a re-flow from
## reparenting thirty-six thumbnails on every mouse-move, and a continuous float would defeat
## it on every one-pixel resize.
var _life_band_ceiling: float = LifeColumn.band_width
## The emitter whose colour the column is currently authoring, and its life window — stamped by
## `_update_colour_surface` for the same reason `_sequence_bound` is stamped rather than
## re-derived (ADR-0100 dec. 1's amendment): every surface that asks must get the same answer.
var _sequence_colour_emitter: int = -1
var _sequence_colour_window: Dictionary = {}
var _colour_picker_panel: PanelContainer = null
var _colour_picker = null
var _colour_picker_title: Label = null
## The RENDERS-AS row — the swatch muxed through the emitter's sprite texel, and the label that
## names it (and the dead channels). See `_build_colour_picker_panel`.
var _colour_renders_as: ColorRect = null
var _colour_renders_as_label: Label = null
## The sequence player's OWN playback rate, deliberately not `_speed_value`. The page
## transport scrubs the effect TIMELINE; this scrubs a reusable asset being authored,
## and `SequenceCanvas`'s docstring already argues why the two clocks are separate — the
## same reasoning covers their speeds. Page state like Ripple / Hide inert: it survives
## picking another sequence and loading another effect, because the reason you slowed it
## down (you are watching closely) outlives the thing you were watching.
var _sequence_speed: float = 1.0
var _frameset_canvas_title: Label
## The sheet-region scope control (ADR-0099 dec. 5) — which frames the next drag moves.
## A UV rect is SHARED: E019's 184 frames address only 14 regions, one of them used by
## 30 frames across 15 framesets, so a drag's blast radius has to be visible before it.
var _region_scope
## The per-texel readout ADR-0098 dec. 6 specified. The canvas owns the mapping, so it is
## the only honest source; this just renders what it reports.
var _frameset_readout: Label
# The Time-Scale pacing painter mode (#270, ADR-0093). "" = the emitter-curve mode; a curve
# field name ("outer_phases"/"for_each") = the pacing mode. BOTH now route the committed stroke
# through the live EffectEditSession (undo + save) — the pacing curves were always private, and
# the ADR-0089 curve-ownership amendment made emitter curves private too, so the two modes differ
# only in WHICH channel they lower through, not in whether the edit is real.
var _painter_pacing_field: String = ""
var _pacing_curve  # the shared EffectCurve the pacing painter binds (samples = ints / 10)
# The USE SITE the emitter-curve painter is bound to (-1 = none / pacing mode). Its private
# curve's index IS its address for the `curve` channel (ADR-0089 curve-ownership amendment).
var _painter_curve_index: int = -1
var _painter_note: Label       # the painter's honest save note
var _painter_gauge: Label      # "Shapes N/15" — the live PSX budget (ADR-0089 decision 4)
var _pacing_enable_check: CheckBox  # the per-curve enable checkbox (effect_flags bit 5/6)
var _effect_data
# {sound_id → ghost frames} for the loaded effect (SoundGhostProjector, ADR-0085).
# Computed once per load from the effect's FEDS bank + SoundContainers; handed to
# EffectScoreModel.build so sound triggers draw their read-only ghost bars.
var _ghost_by_sound_id: Dictionary = {}
# {sound_id → 0..1 energy envelope} for the loaded effect (SoundGhostProjector climax
# cue, ADR-0085). The audio sibling of the ghost map: each firing sound is rendered
# offline through the real SPU once per load and reduced to a per-frame RMS curve,
# handed to EffectScoreModel.build so triggers paint their swell inside the ghost bar.
var _energy_by_sound_id: Dictionary = {}
# {pair_idx → {a, b}} per-track energy envelopes for the OPEN pair lane panel (ADR-0085
# amendment 2026-08-12 §3). Each is two isolated offline SPU renders (track A alone /
# track B alone) shared-peak normalized, computed lazily on pair-open and cached so a
# re-open is instant. Cleared on effect-switch and when a FEDS edit changes a pair's bytes.
var _pair_energy_cache: Dictionary = {}
# {pair_idx → {0: tell, 1: tell}} the manual no-op prune A/B result for the OPEN pair
# (ADR-0085 amendment 2026-08-12 "active corroboration"). Computed only when the author
# presses the panel button (3 offline mixed renders); cached until the pair's bytes change,
# never persisted (proof-only). A tell = {tier, max_abs, peak_delta}.
var _pair_noop_ab_cache: Dictionary = {}
# The effect's FEDS bank + SoundContainers, loaded from disk ONCE at _load_effect and cached
# so a sound_id edit can RE-PROJECT the ghost/energy for the newly-selected sound without a
# disk re-read (a sound_id edit only changes which container fires, never the bank). {} when
# the effect has no FEDS section. See _load_sound_env / _project_sound / _refresh_sound_ghosts.
var _sound_env: Dictionary = {}
# Debounce for the ~0.6s offline SPU render a BRAND-NEW sound_id needs (an already-known id is
# instant from the cached map). A burst of edits — typing or scrubbing through ids — bumps the
# token; only the latest survives the settle delay and renders, so the hitch happens ONCE after
# the value settles, never per keystroke. Bumped on effect load too, to cancel a stale pending
# render. See _schedule_ghost_reproject.
const GHOST_REPROJECT_DELAY_S: float = 0.2
var _ghost_reproject_token: int = 0
# The picker-freeze fix (chunked ghost renders): an IN-TREE load no longer renders its
# firing sounds synchronously (0.7-6.7 s block per pick). It shows the score with NO
# ghost bars (a supported degenerate state), queues the missing renders here, and
# _process pumps them a time-budgeted slice per frame; each landing ghost merges via
# _rebuild_score (transport-preserving). A bare out-of-tree page (unit tests) keeps
# the old deterministic sync path.
const GHOST_RENDER_BUDGET_MS := 30.0
# Queue pause windows: the offline capture parks the producer AND panics the engine,
# so it must yield to anything audible. Play pauses it outright; a scrub's re-pump /
# an audition sets a holdoff long enough for the fired sounds to ring out.
const GHOST_SEEK_HOLDOFF_MS := 2000
const GHOST_AUDITION_HOLDOFF_MS := 4500
# The no-op A/B measurement runs offline AFTER the pruned audition so its render-panic
# doesn't cut the audible playback — this is how long we let the audition ring first.
const NOOP_AB_MEASURE_DELAY_S := 2.0
var _ghost_queue = RenderQueue.new()
var _ghost_queue_holdoff_ms: int = 0
# The pair-panel ENERGY renders (§3 per-track bands + joint waveform) go through their OWN
# chunked queue, pumped from _process like _ghost_queue, so a FEDS edit no longer blocks the
# main thread 3-8 s on three synchronous render_pair calls. Only ONE of the two queues holds
# the shared engine's capture bracket at a time — _process gives the ghost queue priority and
# aborts an in-flight energy job before pumping it (a render's panic() would corrupt the other).
# _energy_partials collects the {a,b,joint} raw renders as they complete out of order; once all
# three land, _on_energy_job_done shared-normalizes them into the _pair_energy_cache entry and
# re-injects the open panel. A newer edit resets the queue, so a burst renders ONCE after it
# settles (debounce-by-supersede — no timer). _energy_pending_pair guards against re-queuing.
var _energy_queue = RenderQueue.new()
var _energy_partials: Dictionary = {}
var _energy_pending_pair: int = -1
# The DEDICATED offline-capture SPU (ExMateriaEffectSfx.init_as_capture). All studio ghost/energy
# renders run on THIS engine — its own SPU hardware, no producer thread — so they NEVER park the
# live-audio autoload's producer. Editing, auditioning, and building the energy band all run
# concurrently ("everything as we go"). Lazily created (a bare page in a unit test builds it on
# first render); both queues share it, so the _process pump still serializes one capture job at
# a time (a render's panic() would corrupt the other queue's cast on the same SPU).
var _capture_engine = null
# Session-wide render cache {(effect_dir + "|" + sound_id): {"length", "energy"}}.
# The FEDS bank is per-effect, so sound_id alone is NOT a valid cross-effect key.
# Makes revisits (and the boot default's re-load) seed their ghosts instantly.
# Invalidated when a container edit retargets a sound's resolved pair (_apply_edit).
var _ghost_render_cache: Dictionary = {}
var _current_dir: String = ""   # the loaded effect's dir — the cache key's first half
# ADR-0085 TIER-2: the effect's shared SoundContainers pre-projected to legible views
# (SoundContainerModel) — computed once per load from the FEDS bank + SoundContainers +
# the sound tracks, threaded into EffectScoreModel.build for the container-kind projector
# and listed by the exhaustive _container_picker browser.
var _container_views: Array = []
# The pre-projected FEDS pair views (ADR-0085 TIER-3, FedsPairModel) threaded into the
# score for the pair-kind projector. Recomputed with the container views (provenance
# reads the same live docs).
var _pair_views: Array = []
# Ghost pips (ADR-0085 TIER-3): sound_id → the resolved pair's UNROLLED note-onset
# frames, scoped to the OPEN pair / the SELECTED sound trigger (one-way editor→timeline
# emphasis). Recomputed on nav changes in _render_current; {} lights nothing.
var _pips_by_sound_id: Dictionary = {}
# ADR-0085 fire-drag baseline: the fixed drag-start snapshot (deep-copied gaps + the
# trigger's address + its fire frame). Every motion computes edits from THIS, not the
# live gaps mutated by prior motions — the byte-exact reversibility guarantee. Empty
# between drags.
var _fire_drag_baseline: Dictionary = {}
# ADR-0086 camera boundary-drag: the span id whose right edge is being dragged (empty
# between drags), and the latest pending end_frame edit `{field_ref, value}` — applied at
# most once per _process frame so the whole-section camera recompile is bounded to the
# frame rate, not the raw motion-event rate (mirrors the _pending_seek scrub coalesce).
var _edge_drag_id: String = ""
# Which edge of `_edge_drag_id` is being dragged — "right" (its own boundary_end) or "left"
# (the same stored number one index down). ADR-0095's split grab band.
var _edge_drag_side: String = "right"
# The dragged colour lane's WALL MASK, captured ONCE at grab (see _on_edge_drag_started) and
# carried on every motion's field_ref. Empty outside a colour drag.
var _edge_drag_visible: Array = []
# How many keyframe slots the last motion's consume reclaimed — the release uses it to
# re-point a selection whose index shifted (ADR-0095).
var _edge_drag_removed: int = 0
var _pending_edge: Dictionary = {}
# Move body-drag (ADR-0089): the span being slid and the latest pending delta, drained once per
# _process frame (like _pending_edge) so the reproject is bounded to the frame rate.
var _body_drag_id: String = ""
# The Move gesture's PRISTINE address + lane, captured at grab (ADR-0101 decision 3). A colour
# Move is structural, so the span's raw index moves under the drag — the plan must keep aiming
# at the address the drag-start snapshot describes, and the SELECTION must follow the span.
var _body_drag_ref: Dictionary = {}
var _body_drag_lane_id: String = ""
var _pending_body_move: Dictionary = {}
# The address an in-flight boundary drag writes through, captured at grab. Survives the span
# vanishing from the score when a hold is emptied (_drop_emptied_camera_hold).
var _pending_edge_ref: Dictionary = {}
var _effect_dirs: Array = []    # real effects only (E001+; E000 is junk)
var _current_id: int = -1
var _playing: bool = false
# The note-chip AUDITION CONSOLE (ADR-0085 2026-08-13, hold-to-play). The transient
# "Audition as" override id — TRANSIENT, never saved; -1 = "no override, use the note's
# running instrument". Reset on navigation so re-opening a chip starts at the running
# instrument. Playback is HOLD-TO-PLAY through ExMateriaEffectSfx.audition_note_on/off (a
# managed reserved unit — reliable, unlike a raw SPU poke). `_audition_holding` suppresses
# the studio's offline ghost/energy renders while a note sounds: those set the engine's
# capture_mode, which PARKS the live producer and would silence the audition (the root
# cause of "works once then silent"). On release we let the tail ring out via a holdoff.
const AUDITION_RELEASE_RINGOUT_MS := 2500
var _audition_override_id: int = -1
var _audition_holding: bool = false
# The DERIVED runtime end (EffectEndModel) for the loaded effect — the frame the
# real engine reaps the cast (particles gone), NOT the last authored keyframe.
# Transport (auto-stop / loop / restart) clamps to THIS, so the playhead halts at
# the real end; scrubbing may still range past it to inspect the (dimmed) tail.
# 0 = not computed → fall back to the score's authored max_frame.
var _end_frame: int = 0

var _ctx_menu: PopupMenu
# The FEDS insert submenu (the corpus, §7) and the pending Add address it applies to.
var _pair_add_menu: PopupMenu
var _pair_add_opts: Array = []
var _pair_add_ref: Dictionary = {}
# The FEDS extend submenu (the corpus's delta-time lengths, 2026-08-19c) and the track it
# applies to. Separate from the Add submenu: two submenus can be open on one context menu,
# and sharing one PopupMenu would make the second row rebuild the first row's list.
var _pair_outro_menu: PopupMenu
var _pair_outro_opts: Array = []
var _pair_outro_ref: Dictionary = {}
# The FEDS opcode CLIPBOARD (2026-08-19e §2): {opcode, params, label} of the last Cut, or {}.
# It outlives the popup and the pair, because re-ordering across the two tracks of a pair is
# the same gesture as re-ordering inside one — the paste's address is whatever boundary the
# next right-click resolves to. Not persisted: it is a gesture's memory, not a document's.
var _feds_clip: Dictionary = {}
# The top panel's latched height, {key, h} — see `_latched_editor_h`. Keyed by the open ROOT
# target so clicking around inside one pair never re-flows the band.
var _editor_latch: Dictionary = {}
var _ctx_span_id: String = ""
# Lane verbs (Add/Delete) offered for the current right-click, indexed by (menu id - 1).
# Rebuilt per popup from _lane_context_actions; the trailing "Copy address" item is id 0.
var _ctx_actions: Array = []

# The inspection NAV STACK (ADR-0073): targets from the current root (a timeline span or a
# browsed emitter) down the drill path. Following a link pushes; a breadcrumb click / a
# revisited ancestor truncates. The last element is what the inspector shows.
var _nav: Array = []
# CHAIN INSPECTION (ADR-0073 + ADR-0085 amendments, 2026-08-21): when true this stack was
# SEEDED as a resolved chain in one gesture rather than walked, and the inspector renders
# EVERY entry co-resident instead of just the top. Opt-in PER SEED, never per kind — a
# `link` drill leaves it false, so every other inspectable kind keeps rendering exactly one
# entry. That one-entry path is the regression contract, and this flag is what fences it.
var _nav_chain: bool = false
# The chain tier to render EXPANDED instead of collapsed — the fold key of the trigger under
# a live fire drag, "" otherwise. Set on the grab, dropped on release.
var _chain_expand_key: String = ""

var _picker: OptionButton
# Exhaustive EMITTER BROWSER (ADR-0073): every emitter in EffectData.emitters, so an
# emitter reached by NO keyframe (child-on-death / mid-life / callback) or referenced by
# nothing is still inspectable. Selecting one sets it as a fresh inspection root.
var _emitter_picker: OptionButton
# Exhaustive SOUNDCONTAINER BROWSER (ADR-0085 TIER-2 / ADR-0073): every container in the
# effect, so a container referenced by NO trigger is still inspectable. Selecting one sets
# it as a fresh inspection root — the shared, effect-global sound-selection logic.
var _container_picker: OptionButton
# Exhaustive FRAME BROWSER (#278): every (frameset, frame) pair in EffectData.framesets,
# so a frame no sequence opcode currently references is still inspectable/authorable.
# Selecting one sets it as a fresh inspection root; each item's metadata carries its
# InspectionTarget (a frame's identity is a PAIR of indices, unlike the flat emitter list).
var _frameset_picker: OptionButton

# Exhaustive SEQUENCE BROWSER (#275): every animation sequence in EffectData.animations,
# so a sequence no emitter currently plays is still reachable. Sits beside the frame
# browser on transport row 3.
var _sequence_picker: OptionButton
var _play_btn: Button
var _speed_btn: ScrubField
var _loop_btn: Button
# Loop MODE (ADR-0090): Off / Forward / Ping-pong (LoopTransport.MODE_*), cycled from
# the one Loop button. Replaces the old on/off `_looping` bool. Persists across effect
# loads as page state (like Ripple / Hide-inert).
var _loop_mode: int = Transport.MODE_OFF
# The session-scoped loop REGION — an inclusive `{start, end}` span, or `{}` for "no
# region" (whole-score fallback). Ephemeral: cleared on effect load, never written to
# E###.BIN. Set by the frames bar's Alt+left-drag, "Loop life", or Clear.
var _loop_region: Dictionary = {}
# The bounce transport's current direction (LoopTransport.DIR_*), reset to forward on
# each Play. Only ping-pong ever flips it.
var _loop_dir: int = Transport.DIR_FWD
# Page-side frame accumulator for the 30 Hz × speed transport clock. Fractional frames
# carry across _process ticks so non-integer speeds (0.25×/2×) stay frame-exact.
var _transport_accum: float = 0.0
var _loop_life_btn: Button
var _clear_region_btn: Button
var _freecam_btn: Button
var _free_cam: bool = false      # "free camera" debug toggle: fly the camera while the effect plays
var _native_btn: Button
var _native_blend: bool = false  # render-layer compare (#7916): fold (correct) vs native in-scene blend (wrong)
# RIPPLE mode (ADR-0087 dec. 10): a SESSION-LOCAL authoring toggle, off by default and
# never persisted into the effect file. While on, a colour-lane resize (edge drag AND typed
# Duration — the same flag, so the two affordances can't diverge) skips the sum-preserving
# trade: downstream keyframes in that lane shift by the delta. Lane-local; camera stays out (v1).
var _ripple_btn: Button
var _ripple: bool = false
# "Hide inert" mode (ADR-0089 amendment): a SESSION-LOCAL view toggle, off by default and
# never persisted into the effect, mirroring Ripple. While on, the emitter/particle inspector
# renders only Live fields (Inactive/Dead fields, neutral gates, the Dead reveal, the formula
# view, and now-empty sections all vanish); toggle off to recover a hidden knob. The flag is
# page-level state (survives target re-selection) threaded through show_target in _render_current.
var _hide_inert_btn: Button
var _hide_inert: bool = false
# Effect Settings entry (#271): navigates to the effect_settings inspection target (the GLOBAL
# settings surface: timeline phase durations today).
var _effect_settings_btn: Button
# Curve-sparkline display toggles (ADR-0089 curve-UX): "Fit H" re-fits Y to each
# window's own min/max (shape) vs a fixed 0..1 range (magnitude); "Fit W" trims to the
# used window vs the whole curve. Global (EffectCurveSparkline statics) so every
# sparkline shares one scale, comparable across rows. Buttons only mirror the statics.
var _fit_h_btn: Button
var _fit_w_btn: Button
# Playback speed (ADR-0090 dec. 4): a continuous 0.1×–4× multiplier on the transport
# accumulator, driven by the toolbar ScrubField. Page state — persists across effect load.
var _speed_value: float = 1.0
var _frame_label: Label
var _save_label: Label   # one-click Save feedback (output path / error)

# Coalesced scrub target: a drag emits seek_requested per mouse-motion (many per
# frame), and each host seek can reset+repump the effect from 0 — ~0.7 ms/frame,
# so a backward seek to a late frame costs 100+ ms. We stamp the latest requested
# frame here and apply exactly ONE host seek per _process tick (latest wins). The
# playhead still tracks every event (cheap), so the UI stays responsive. -1 = none.
var _pending_seek: int = -1


func _ready() -> void:
	_effect_dirs = _scan_effect_dirs()
	# ADR-0103 dec. 8: the film strip's cell backdrop. Registered from the page because a
	# `Tune.bind` per thumbnail would be 36 registrations of one slug; the static-var home
	# and the value itself live on `SequenceThumbnail`, which owns the drawing.
	SequenceThumbnail.register_tunables(self)
	_build_ui()
	set_process(true)


## Bind the effect scene this page drives. Call before/after add — idempotent.
func bind_host(host) -> void:
	_host = host


func _build_ui() -> void:
	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vb)

	vb.add_child(_build_transport())

	# Layout: the transport is a normal top strip. Below it a `body` stacks three
	# manually-positioned children (see _relayout):
	#   • inspector "editor" (top)  — resizes to its content height, then scrolls its
	#                                 own overflow once it reaches the timeline ceiling.
	#   • frames bar  (middle)      — the ruler, glued directly under the inspector.
	#   • channel list (bottom)     — fills the rest and scrolls INTERNALLY, so every
	#                                 lane stays reachable however tall the inspector.
	# The inspector eats the channel-list viewport from the TOP; to honour "selecting an
	# event must not move the timelines on screen" _relayout re-scrolls the channel list
	# by the inspector's height delta (bottom-anchored) — the visible lanes stay pinned
	# while the inspector grows over the top lanes (still reachable by scrolling up).
	_body = Control.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.clip_contents = true
	vb.add_child(_body)

	# Right-click keyframe menu: "Copy keyframe address" puts a precise, pasteable
	# reference (effect · lane · kf# · frames · payload) on the clipboard.
	_ctx_menu = PopupMenu.new()
	# Items are rebuilt per right-click in _on_span_context (lane verbs + Copy address).
	_ctx_menu.id_pressed.connect(_on_ctx_menu_id)
	add_child(_ctx_menu)

	# Channel list: the timeline lives inside a vertical ScrollContainer so its full
	# track height (custom_minimum_size.y, set from content) can overflow and scroll.
	# Horizontal scroll is disabled — the timeline owns its own frame-axis pan/zoom.
	# Added FIRST so it draws UNDER the frames bar + inspector overlay.
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(_scroll)

	_timeline = Timeline.new()
	_timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timeline.size_flags_vertical = Control.SIZE_SHRINK_BEGIN  # use content height, don't fill
	_timeline.span_selected.connect(_on_span_selected)
	_timeline.seek_requested.connect(_on_seek_requested)
	_timeline.span_context_requested.connect(_on_span_context)
	_timeline.lane_context_requested.connect(_on_lane_context)
	_timeline.lane_audibility_changed.connect(_apply_audibility)
	_timeline.anchor_offset_changed.connect(_on_anchor_offset_changed)
	_timeline.fire_frame_changed.connect(_on_fire_frame_changed)
	_timeline.fire_drag_started.connect(_on_fire_drag_started)
	_timeline.fire_drag_ended.connect(_on_fire_drag_ended)
	_timeline.edge_dragged.connect(_on_edge_dragged)
	_timeline.edge_drag_started.connect(_on_edge_drag_started)
	_timeline.edge_drag_ended.connect(_on_edge_drag_ended)
	_timeline.span_body_drag_started.connect(_on_span_body_drag_started)
	_timeline.span_body_dragged.connect(_on_span_body_dragged)
	_timeline.span_body_drag_ended.connect(_on_span_body_drag_ended)
	_scroll.add_child(_timeline)

	# FEDS pair lane panel: its OWN band between the inspector and the frames bar
	# (see _relayout) — NOT a child of the channel scroll, whose content top is
	# permanently covered by the floating inspector overlay. Its host scroll gives
	# the band internal vertical overflow when the window is short (a Control's
	# size can't shrink below its content minimum). Hidden until a pair target
	# opens (_update_pair_panel).
	_pair_scroll = ScrollContainer.new()
	_pair_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_pair_scroll.visible = false
	_body.add_child(_pair_scroll)
	_pair_panel = PairPanel.new()
	_pair_panel.visible = false
	_pair_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pair_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_pair_panel.event_selected.connect(_on_pair_event_selected)
	_pair_panel.pair_context_requested.connect(_on_pair_context)
	_pair_panel.pair_drag_started.connect(_on_pair_drag_started)
	_pair_panel.pair_dragged.connect(_on_pair_dragged)
	_pair_panel.pair_drag_ended.connect(_on_pair_drag_ended)
	_pair_panel.minimum_size_changed.connect(_relayout)
	# Frame-axis projection (ADR-0085 2026-08-11 amendment): the panel shares the
	# timeline's TimelineAxis OBJECT so a sound's events line up with the effect
	# lanes below — one zoom/pan/playhead for the whole band.
	_pair_panel.bind_timeline(_timeline)
	_pair_scroll.add_child(_pair_panel)

	# Frames bar: the detached ruler, sharing the timeline's axis so its ticks +
	# playhead stay pixel-aligned with the lanes. Floats between editor and channels.
	_frames_bar = FramesBar.new()
	_frames_bar.bind_timeline(_timeline)
	_frames_bar.seek_requested.connect(_on_seek_requested)
	_frames_bar.region_changed.connect(_on_region_changed)
	_body.add_child(_frames_bar)

	# Keyframe inspector ("editor"): fit-to-size, floats on TOP (added last) and
	# grows downward. minimum_size_changed fires whenever its content resizes → we
	# re-flow the bar under it without touching the channel list.
	_inspector = Inspector.new()
	_body.add_child(_inspector)

	# Path bar: the drill trail, promoted out of the inspector's grid into a strip of
	# its own. Added LAST so it draws over both the inspector and the right column, and
	# positioned by _relayout as the row above them.
	_path_bar = PathBar.new()
	_path_bar.navigate_requested.connect(_navigate_to)
	_path_bar.back_requested.connect(_step_back)
	_body.add_child(_path_bar)

	_body.resized.connect(_relayout)
	# The inspector's content lives in a ScrollContainer, so growth is absorbed and
	# minimum_size_changed won't fire — it emits content_changed on select/clear.
	# The per-opcode pictures the sequence rows ask for (#247). Set once: the inspector
	# calls back only for rows that carry a `thumb`, so every other target is unaffected.
	_inspector.thumbnail_provider = _sequence_thumbnail_for
	_inspector.content_changed.connect(_relayout)
	# An EXPLICIT fold toggle is not the rebuild transient the latch absorbs (ADR-0085
	# amendment 2026-08-21, decision 5) — it drops the high-water mark first, then re-flows.
	_inspector.fold_toggled.connect(_on_inspector_fold_toggled)
	call_deferred("_relayout")

	_build_curve_painter_overlay()
	_build_texture_tab()
	_build_frameset_canvas_overlay()
	_build_sequence_canvas_overlay()
	_build_sequence_focus_overlay()

	if not _effect_dirs.is_empty():
		# Default to a real, recognisable effect (E317 Choco Ball) if present.
		var default_idx := 0
		for i in range(_effect_dirs.size()):
			if _effect_dirs[i].ends_with("E317"):
				default_idx = i
				break
		_picker.select(default_idx)
		_load_effect(_effect_dirs[default_idx])


## THE FOCUS PANEL (ADR-0102 second amendment): the unified animation screen's frameset
## block, in a container of its OWN — a second `EffectKeyframeInspector` holding exactly
## one section, parked above the film strip and sized by `_relayout`, never in the strip's
## own flow.
##
## WHY IT LEFT THE SECTION LIST. As a section it sat in the same VBoxContainer as the 36
## opcode sections below it, so its height was theirs: a two-member frameset is one fold
## taller than a one-member one, and MEASURED on E019 sequence 0 every thumbnail below the
## block slid 39px each time the author clicked between them. "The thumbnails should not be
## moving as you click other things" is the whole requirement, and a block that cannot
## reach the strip's container is the only shape that satisfies it — the alternative
## (a fixed-height section inside the flow) still moves everything when the block is
## SHOWN or HIDDEN, which is what a spriteless opcode does.
##
## WHY A SECOND INSPECTOR AND NOT A HAND-ROLLED ROW HOST. The block's rows are ordinary
## registry rows — ScrubFields, enum pickers, nested folds, `field_ref` edit routing — and
## re-implementing that beside the real one is how two surfaces drift. `show_own_chrome`
## is off because this instance is already inside a panel: its own target title would be a
## second name for one surface and its header grid a blank row, in ~130px of height.
##
## The retarget is a plain `show_target` on THIS inspector — one section, ~34 rows — which
## is why the film-strip click needed no in-place section rebuild in the end (ADR-0102 dec.
## 3's `rebuild_section` was deleted with its last caller). Nothing in the main inspector is
## touched, so a ScrubField being dragged there cannot be freed by a click through the
## strip (`87c081b7b`).
func _build_sequence_focus_overlay() -> void:
	_focus_panel = PanelContainer.new()
	_focus_panel.visible = false
	_body.add_child(_focus_panel)
	_focus_inspector = Inspector.new()
	_focus_inspector.show_own_chrome = false
	# …and it may scroll SIDEWAYS. Its widest row declares 584px against a column of ~334,
	# and a Container cannot shrink below its combined minimum — without this the panel
	# would overflow onto the film strip by the difference rather than scrolling.
	_focus_inspector.allow_horizontal_scroll = true
	# …and a narrower name column than the 240px house width. In a ~334px column, 240 of it
	# spent on names puts every VALUE off the right edge behind a scrollbar — see
	# `name_column_width` for why the alignment rule ADR-0089 dec. 6 states is not broken
	# by this (it is claimed per panel, and these are two panels).
	_focus_inspector.name_column_width = Inspector.NAME_COL_WIDTH_TIGHT
	# NOT connected to `content_changed` → `_relayout`, unlike the main inspector: this
	# panel's height is assigned, not derived, so a content change has nothing to tell the
	# layout — and a relayout per retarget would be a flow storm for no movement.
	_focus_panel.add_child(_focus_inspector)


func _build_transport() -> Control:
	var bar := PanelContainer.new()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	bar.add_child(vb)

	# First row: Core editing workflow
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	vb.add_child(row1)

	_picker = OptionButton.new()
	for d in _effect_dirs:
		_picker.add_item(d.get_file())
	_picker.item_selected.connect(func(i): _load_effect(_effect_dirs[i]))
	row1.add_child(_picker)

	_play_btn = _tool_button(row1, "▶ Play", _toggle_play)
	_tool_button(row1, "⏹ Stop", _stop)
	_tool_button(row1, "⏮ -1", func(): _step_frame(-1))
	_tool_button(row1, "+1 ⏭", func(): _step_frame(1))
	_speed_btn = ScrubField.new()
	_speed_btn.min_value = 0.1
	_speed_btn.max_value = 4.0
	_speed_btn.step = 0.05
	_speed_btn.scrub_sensitivity = 0.01
	_speed_btn.suffix = "×"
	row1.add_child(_speed_btn)
	_speed_btn.set_value_no_signal(1.0)
	_speed_btn.value_changed.connect(func(v): _speed_value = v)
	_loop_btn = _tool_button(row1, "Loop: off", _cycle_loop_mode)
	_loop_life_btn = _tool_button(row1, "Loop life", _set_loop_life)
	_clear_region_btn = _tool_button(row1, "Clear region", _clear_region)
	_tool_button(row1, "💾 Save", _save)
	# The verdict strip for every whole-document verb on this row — Save, and the #280
	# texture Export/Import round trip. The field existed and was never built, so Save's
	# own result only ever reached the console; a texture import that the host REFUSED
	# looked exactly like one that worked. EXPAND_FILL with a zero minimum takes only the
	# leftover width, so it can never squeeze the buttons; clipped text keeps a long path
	# from re-flowing the row, and the tooltip carries the full string.
	_save_label = Label.new()
	_save_label.clip_text = true
	_save_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_label.custom_minimum_size.x = 0.0
	row1.add_child(_save_label)

	# Second row: View and editor options
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	vb.add_child(row2)

	_freecam_btn = _tool_button(row2, "Free cam: off", _toggle_free_cam)
	_native_btn = _tool_button(row2, "Render-layer: fold", _toggle_native_blend)
	_ripple_btn = _tool_button(row2, "Ripple: off", _toggle_ripple)
	_hide_inert_btn = _tool_button(row2, "Hide inert: off", _toggle_hide_inert)
	_fit_h_btn = _tool_button(row2, "Fit H: abs", _toggle_fit_height)
	_fit_w_btn = _tool_button(row2, "Fit W: all", _toggle_fit_width)
	_effect_settings_btn = _tool_button(row2, "Effect ⚙", _open_effect_settings)

	_frame_label = Label.new()
	_frame_label.custom_minimum_size.x = 140.0
	row2.add_child(_frame_label)

	# Third row: Navigation and information
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 8)
	vb.add_child(row3)

	# The emitter browser — the exhaustive entry point that guarantees reachability of
	# every emitter, including orphan / callback-only ones no span or link reaches.
	var em_label := Label.new()
	em_label.text = "Emitters:"
	row3.add_child(em_label)
	_emitter_picker = OptionButton.new()
	_emitter_picker.item_selected.connect(_on_emitter_browsed)
	row3.add_child(_emitter_picker)

	# The SoundContainer browser — the exhaustive entry point (ADR-0085 TIER-2) that makes
	# every shared container reachable, including one no trigger references.
	var sc_label := Label.new()
	sc_label.text = "Containers:"
	row3.add_child(sc_label)
	_container_picker = OptionButton.new()
	# `index_pressed`, NOT `item_selected`: the latter fires only when the index
	# CHANGES, so re-picking the entry already showing did nothing at all — the
	# author's way back after navigating away was silently dead.
	_container_picker.get_popup().index_pressed.connect(_on_container_browsed)
	row3.add_child(_container_picker)

	# The frame browser (#278) — the exhaustive entry point that guarantees reachability of
	# every frame, including ones no sequence opcode currently displays.
	var fr_label := Label.new()
	fr_label.text = "Frames:"
	row3.add_child(fr_label)
	_frameset_picker = OptionButton.new()
	# `index_pressed`, NOT `item_selected`: the latter fires only when the index
	# CHANGES, so re-picking the entry already showing did nothing at all — the
	# author's way back after navigating away was silently dead.
	_frameset_picker.get_popup().index_pressed.connect(_on_frameset_browsed)
	row3.add_child(_frameset_picker)

	# The sequence browser (#275) — the exhaustive entry point that guarantees reachability
	# of every animation sequence, including ones no emitter's anim_param selects.
	var sq_label := Label.new()
	sq_label.text = "Sequences:"
	row3.add_child(sq_label)
	_sequence_picker = OptionButton.new()
	# `index_pressed`, NOT `item_selected`: the latter fires only when the index
	# CHANGES, so re-picking the entry already showing did nothing at all — the
	# author's way back after navigating away was silently dead.
	_sequence_picker.get_popup().index_pressed.connect(_on_sequence_browsed)
	row3.add_child(_sequence_picker)
	_update_labels()   # seed toggle-button captions (Loop / Ripple / Fit H / Fit W)
	return bar


## Populate the emitter browser with one entry per emitter in the loaded effect (ADR-0073).
## Entries are labeled by the **0-based emitter index** — the same number the timeline shows
## on a span ("E0", "E1", …) and the target carries. Position 0 is a placeholder prompt;
## emitter index == item position − 1 (we key off POSITION, not item id — OptionButton
## auto-assigns id = index for a default-id item, which would collide the placeholder with
## emitter 0).
func _refresh_emitter_browser() -> void:
	if _emitter_picker == null:
		return
	_emitter_picker.clear()
	_emitter_picker.add_item("— pick emitter —")
	var count := 0
	if _effect_data != null and _effect_data.emitters != null:
		count = _effect_data.emitters.size()
	for i in range(count):
		_emitter_picker.add_item("emitter %d" % i)   # 0-based index, matching the timeline "E<i>"
	_emitter_picker.select(0)


## Browse to an emitter as a fresh inspection root. Position 0 is the placeholder (no-op);
## every other position maps to emitter index = position − 1.
func _on_emitter_browsed(item_index: int) -> void:
	if item_index <= 0:
		return
	_set_root(Target.emitter(item_index - 1))


## Populate the SoundContainer browser with one entry per pre-projected container view
## (ADR-0085 TIER-2). Position 0 is a placeholder prompt; container index == position − 1
## (keyed off POSITION, like the emitter browser). Lists EVERY container so an orphan one
## (referenced by no trigger) is still reachable.
func _refresh_container_browser() -> void:
	if _container_picker == null:
		return
	_container_picker.clear()
	_container_picker.add_item("— pick container —")
	for view in _container_views:
		var idx := int(view.get("index", -1))
		_container_picker.add_item("container %d · %s" % [idx, str(view.get("mode_name", ""))])
	_container_picker.select(0)


## Browse to a SoundContainer as a fresh inspection root. Position 0 is the placeholder
## (no-op); every other position maps to container index = position − 1.
func _on_container_browsed(item_index: int) -> void:
	if item_index <= 0:
		return
	_set_root(Target.container(item_index - 1))


## Populate the frame browser with one entry per (frameset, frame) pair (#278). Position 0
## is a placeholder prompt; every other position's item METADATA carries the frame's
## InspectionTarget directly (a frame's identity is a pair of indices, so — unlike the
## emitter/container browsers — position-minus-one isn't enough addressing on its own).
func _refresh_frameset_browser() -> void:
	if _frameset_picker == null:
		return
	_frameset_picker.clear()
	_frameset_picker.add_item("— pick frame —")
	if _effect_data != null and _effect_data.framesets is Array:
		for fs_idx in range(_effect_data.framesets.size()):
			var fs = _effect_data.framesets[fs_idx]
			if not (fs is Dictionary):
				continue
			var frames: Array = fs.get("frames", [])
			for fr_idx in range(frames.size()):
				var idx := _frameset_picker.item_count
				_frameset_picker.add_item("frameset %d / frame %d" % [fs_idx, fr_idx])
				_frameset_picker.set_item_metadata(idx, Target.frame(fs_idx, fr_idx))
	_frameset_picker.select(0)


## Browse to a frame as a fresh inspection root. Position 0 is the placeholder (no-op).
func _on_frameset_browsed(item_index: int) -> void:
	if item_index <= 0:
		return
	var target: Dictionary = _frameset_picker.get_item_metadata(item_index)
	if target is Dictionary:
		_set_root(target)


## Populate the sequence browser with one entry per animation sequence (#275). Position 0
## is a placeholder prompt; every other position's item METADATA carries the sequence's
## InspectionTarget (kept symmetric with the frame browser, even though a sequence's
## identity is a single index).
func _refresh_sequence_browser() -> void:
	if _sequence_picker == null:
		return
	_sequence_picker.clear()
	_sequence_picker.add_item("— pick sequence —")
	if _effect_data != null and _effect_data.animations is Array:
		for anim_idx in range(_effect_data.animations.size()):
			var anim = _effect_data.animations[anim_idx]
			if not (anim is Dictionary):
				continue
			var opcodes: Array = anim.get("opcodes", [])
			var idx := _sequence_picker.item_count
			_sequence_picker.add_item("sequence %d (%d opcodes)" % [anim_idx, opcodes.size()])
			_sequence_picker.set_item_metadata(idx, Target.animation(anim_idx))
	_sequence_picker.select(0)


## Browse to a sequence as a fresh inspection root. Position 0 is the placeholder (no-op).
func _on_sequence_browsed(item_index: int) -> void:
	if item_index <= 0:
		return
	var target = _sequence_picker.get_item_metadata(item_index)
	if target is Dictionary:
		_set_root(target)


func _build_curve_painter_overlay() -> void:
	_painter_panel = PanelContainer.new()
	_painter_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_painter_panel.custom_minimum_size = Vector2(560, 300)
	_painter_panel.visible = false
	add_child(_painter_panel)

	var vb := VBoxContainer.new()
	_painter_panel.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	_painter_title = Label.new()
	_painter_title.text = "Curve"
	_painter_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_painter_title)
	# The SHAPE GAUGE (ADR-0089 curve-ownership amendment, decision 4): distinct shapes in
	# use against the ROM's 15 slots. Authoring is unbounded by design and the compiler is
	# what refuses, so refusing is only FAIR if the number is watchable while authoring —
	# this is that number. It is the same dedup the compiler runs, not a second mechanism.
	# Hidden in pacing mode: the pacing curves live in their own section and never enter
	# the curve table.
	_painter_gauge = Label.new()
	_painter_gauge.add_theme_font_size_override("font_size", 11)
	# Breathing room so the gauge does not read as part of the Close button beside it.
	_painter_gauge.add_theme_constant_override("outline_size", 0)
	head.add_child(_painter_gauge)
	var gauge_gap := Control.new()
	gauge_gap.custom_minimum_size = Vector2(10.0, 0.0)
	head.add_child(gauge_gap)
	# The per-curve enable checkbox (#270, ADR-0092 amendment): only shown in pacing mode, it
	# gates that curve's effect_flags bit (5 = Phase 1 / 6 = For-each). Toggling writes the flags
	# byte through the same session so the band greys/ungreys live.
	_pacing_enable_check = CheckBox.new()
	_pacing_enable_check.text = "Enabled"
	_pacing_enable_check.visible = false
	_pacing_enable_check.toggled.connect(_on_pacing_enable_toggled)
	head.add_child(_pacing_enable_check)
	_tool_button(head, "Close", func(): _painter_panel.visible = false)

	_painter = CurvePainter.new()
	_painter.custom_minimum_size = Vector2(540, 250)
	vb.add_child(_painter)

	# Curve CONTENTS are PRIVATE to their use site since the ADR-0089 curve-ownership
	# amendment, and the commit routes through EffectEditSession like every other edit —
	# so the note that used to say "Preview only — curve edits aren't saved yet" is gone
	# with the model that made it true. (A global curve-table editor was the honest home
	# for a shared N-referrer surface; it is dissolved, not deferred, along with the
	# sharing it existed to make visible.)
	_painter_note = Label.new()
	_painter_note.text = "Painted live — saved to the effect (undoable)"
	_painter_note.modulate = Color(0.55, 0.72, 0.55)
	_painter_note.add_theme_font_size_override("font_size", 11)
	vb.add_child(_painter_note)

	# The painter writes the bound curve on mouse-up (curve_changed) — ONE commit per
	# stroke, which is what makes an undo entry a gesture rather than a pixel.
	_painter.curve_changed.connect(_on_curve_changed)


## The frameset canvas is the RIGHT-HAND AREA of the inspector row — a peer of the frame
## controls column, not a floating overlay. Every previous attempt here hand-computed a
## rect against the PAGE (measure the transport's rendered right edge, dock to the page's
## top-right, take `size.y` for height) and each one broke differently, because a rect
## derived from the page knows nothing about the band it has to stay inside: the last one
## overran the timeline section by 388px at a 1261x688 dashboard. `_relayout` already owns
## that band — it hands the inspector a height (`editor_h`) clamped to a `budget` that
## keeps MIN_CHANNELS_H of lanes below the ruler — so splitting THAT row in two makes
## "never covers the transport" and "never bleeds into the timeline" structural facts
## rather than arithmetic that has to be kept correct.
const TextureTab = preload("res://src/effects/studio/TextureTabPanel.gd")
const _CANVAS_CHROME_W := 16.0   # PanelContainer's own left+right padding
## The PanelContainer's own top+bottom padding. The rest of the chrome is MEASURED —
## see `_canvas_chrome_h`. This was `_CANVAS_CHROME_H := 40.0  # title label + padding`,
## a constant that silently became wrong the moment ADR-0099's scope control was added
## below the canvas: the canvas stopped being square (aspect 0.68) and the panel ran
## 111px into the timeline, because a guess cannot track a panel that gains rows.
const _CANVAS_CHROME_PAD_H := 20.0
const _CANVAS_GUTTER := 8.0      # gap between the frame-controls column and the canvas
## The unified animation screen's focus panel (ADR-0102 second amendment) is a COLUMN
## between the film strip and the player, not a band above the strip. Both were built and
## photographed at the dev body (a 268px row, 1241px wide):
##
##   * stacked, the two halves get 131px each. The strip spends ~100 of its 131 on chrome
##     it cannot drop (its title, the "Plays for N ticks" header row, the Expand/Collapse
##     bulk row), so it showed ONE opcode; the block showed ONE parameter row.
##   * side by side, both take the row's full 268px. The strip pays the same ~100px of
##     chrome once and shows ~3 thumbnails; the block shows ~5 rows.
##
## The width is the SLACK — what the row has left once the strip's declared
## `content_width()` and the width the player already wanted are both accounted for. That
## ordering is forced, not chosen: a Container cannot shrink below its combined minimum, so
## width taken from either neighbour does not narrow it, it makes it overflow onto this
## column (ADR-0100 dec. 2's failure, one column further left). The player's want is the
## square `column_width` derives, floored at the panel's own irreducible chrome — taking
## the block's width off the row BEFORE that floor was applied is what put the sequence
## panel 9px past the body's right edge at a 1187px body.
##
## So the block absorbs the row's slack rather than a fixed share of it: at the 1241px dev
## body that is 677 strip + 330 block + 218 player + two gutters, exactly full. When the
## slack falls under `_FOCUS_MIN_W` the column takes what there is and scrolls sideways;
## under `_FOCUS_COLLAPSE_W` it goes away entirely, because a 60px column of name/value
## rows is not an authoring surface, it is a stripe.
const _FOCUS_MIN_W := 240.0      # narrower than this a name/value row starts to scroll
const _FOCUS_COLLAPSE_W := 120.0 # …and under this the column is not worth its own gutter
## What the focus panel needs AROUND its declared content: its PanelContainer's left/right
## padding plus the vertical scrollbar it reserves. `content_width()` normally folds that in
## by measuring `get_combined_minimum_size().x - _content...x`, but this panel scrolls
## horizontally, so its own minimum collapses to nothing and that term clamps to zero — it
## under-reports by exactly this much, and a column sized to the under-report grows a
## horizontal scrollbar for the last 20px of every row.
const _FOCUS_CHROME_W := 28.0
## The stacked block's own bounds, the vertical peers of `_FOCUS_MIN_W`/`_FOCUS_COLLAPSE_W`
## (author, 2026-08-19: "shift the right panel with the sequence animation to the right and
## then fit the frameset controls underneath it"). Under the collapse height the block is a
## letterbox showing one clipped row and is not worth its own gutter.
const _FOCUS_MIN_H := 120.0
const _FOCUS_COLLAPSE_H := 64.0
const _FOCUS_GUTTER := 8.0
const _CANVAS_MIN_SIDE := 180.0
## THE BOX'S FIXED SIDE (ADR-0100 dec. 2, second amendment). The canvas is a square of this
## many pixels whatever the window does, and the panel around it is that plus its own
## measured chrome. A constant, not a derivation, because "it should have fixed dimensions"
## is the requirement and every derivation tried so far had a term that moves: off the
## inspector's content height the box resized on every click and every fold; off the row's
## whole budget it resized with the WINDOW, and on a tall one it grew to half the row and
## starved the focus column beside it out of existence.
##
## 260 is the largest side that leaves the three-column row working at the narrow end: at a
## 1205px body it is 677 (the strip's declared width) + 276 (this, plus 16 of panel chrome)
## + 16 of gutters, leaving 236 for the focus column — above its 240px comfortable minimum
## by a hair and well above the 120 at which the column is dropped. Raise it and the block
## is what pays.
const _CANVAS_SIDE := 260.0
## ADR-0130 dec. 2/3. The tab strip's height, taken out of the LEFT column's rect and
## never out of `budget` — which is the whole reason a tab was chosen over the band the
## author first proposed. A band would have taken 134 of the dev body's 268px budget and
## clipped the sequence player from 348 to 134; this takes 0.
const _TAB_STRIP_H := 26.0
## THE STRIP IS A SINGLE COLUMN, and that reverses the rule this block used to carry.
##
## It used to WRAP — an `HFlowContainer` in a wide, short band under the player, because one
## line of 34px cells showed 7 of E019's 35 opcodes and wrapping showed two or three times as
## many. Since the ADR-0089 vertical-column amendment (2026-08-20) the strip runs DOWN the
## panel beside the colour ribbon, and a second column of thumbnails would have no ribbon
## next to it — which is the whole alignment claim broken. So it never wraps, and its
## overflow scrolls vertically as it already did.
##
## `strip_rows` survives only as the number of cells the slot's HEIGHT used to declare; the
## slot declares a WIDTH now (`sequence_life_column_w` below) and its height is the panel's,
## so nothing reads this. It is kept because the ADR-0068 tunable is still the right lever if
## the column ever needs a declared row budget again.
static var strip_rows: int = 2

## THE LIFE COLUMN'S DECLARED WIDTH — the vertical ribbon, the thumbnail beside it, the
## separation between them, and room for the scrollbar. Declared ONCE at build for the same
## reason the old strip declared a height once: `_canvas_floor_w` skips invisible children,
## so a width that appeared and disappeared with the ribbon would re-size the player's box
## on navigation.
##
## The scrollbar allowance IS needed here, unlike in the old horizontal strip where the bar
## cost width and the slot declared height. Here it costs width and the slot declares width,
## so leaving it out would clip the thumbnails by the bar's thickness on every sequence long
## enough to scroll — which is most of them (median 9 rows against the ~6 a short panel shows).
static func sequence_life_column_w() -> float:
	return _life_pair_w() + _LIFE_SCROLLBAR_W
const _LIFE_SCROLLBAR_W := 12.0

## ONE (ribbon + thumbnail) PAIR, without the scrollbar. The scrollbar is paid ONCE for the
## whole scroller no matter how many columns are in it, which is why it is not in here and
## why `sequence_life_slot_w` adds it separately rather than multiplying it.
static func _life_pair_w() -> float:
	return LifeColumn.band_width + _STRIP_SEP + SequenceThumbnail.SIDE
## The gap BETWEEN pairs. Wider than `_STRIP_SEP` (which separates a ribbon from its own
## thumbnails) precisely so the grouping reads: a thumbnail is closer to its ribbon than to
## the next column's ribbon, which is the whole alignment claim said in whitespace.
const _LIFE_COL_SEP := 6.0

## HOW MANY COLUMNS THE STRIP MAY WRAP INTO (author, 2026-08-20: *"I don't want to have to
## scroll to see all the thumb nails. I just want them to form another row on the right."*).
##
## THREE, and the author picked it against the arithmetic rather than in ignorance of it.
## Rows per emitter across the corpus are median 9, p90 22, p99 35, max 75
## (`tools/census_life_column.gd`); at roughly a dozen rows to a column, three columns cover
## the 99th percentile and the last 1% scrolls. Wrapping does NOT remove scrolling — it
## removes it for everything but the tail, and the tail was priced before this was chosen.
##
## The cost is real and it is CONSTANT: the extra columns are bid whatever the emitter shows,
## so the inspector gives up the width on every target. Bidding per-emitter would have made
## the inspector's right edge move on every click — the "the animation box is changing in
## size all the time" complaint ADR-0100 dec. 2's amendment exists to answer, one level out.
## Offered exactly that and the author rejected it.
##
## An ADR-0068 static var, so the price is retunable without a rebuild: 1 restores the
## single column this replaced.
static var life_columns: int = 3


## The width the life slot wants for `n` columns. One scrollbar, `n` pairs, `n-1` gaps.
static func sequence_life_slot_w(n: int) -> float:
	var c: int = maxi(1, n)
	return _life_pair_w() * float(c) + _LIFE_COL_SEP * float(c - 1) + _LIFE_SCROLLBAR_W


## HOW WIDE THE RIBBON MAY BE when the strip only uses `cols` of its pairs — the inverse of
## `sequence_life_slot_w`, solved for the band instead of for the slot.
##
## The author, on a one-frame sprite held for its whole life: *"things get crazy on the
## keyframes — can we maybe do a minimum width keyframes?"* A row draws one sub-column per
## life frame across the band, so a single row owning 128 ages gets 0.17px each and 106 of
## them are unreachable by any click.
##
## THE WIDTH IS ALREADY DECLARED AND ALREADY UNUSED. The slot bids for three pairs on every
## target (unconditional, so the inspector's right edge never moves — see the bid in
## `_relayout` and the "the animation box is changing in size all the time" complaint it
## answers), but a strip that wraps into ONE pair leaves the other two's share empty. And
## the arithmetic lands because `rows x ticks ~= life_n`: a row is wide exactly when there
## are few rows, which is exactly when there are spare pairs. One pair affords 150px, two
## afford 54, three afford 22 — and 22 is `band_width`, so this formula's bottom end IS the
## constant it replaces.
##
## Read off the slot's ACTUAL width, not its declared one: on a narrow row the bid is refused
## and the slot keeps its 70px minimum, where the honest ceiling is the floor.
static func life_band_ceiling(slot_w: float, cols: int) -> float:
	var c: int = maxi(1, cols)
	var usable: float = slot_w - _LIFE_SCROLLBAR_W - _LIFE_COL_SEP * float(c - 1)
	return maxf(LifeColumn.band_width,
		usable / float(c) - SequenceThumbnail.SIDE - _STRIP_SEP)


## How many columns a slot of `slot_w` can actually SHOW. The slot's declared minimum is
## still ONE column and that is deliberate: raising the minimum to three would raise the
## player panel's hard floor by ~128px, and a Container cannot shrink below its minimum, so
## a narrow row would push the panel onto the inspector — the failure ADR-0100 dec. 2's clamp
## exists to make unrepresentable. The extra columns are BID in `_relayout` and taken only if
## the leftover clamp leaves room; this is what the strip does with the answer.
static func life_columns_affordable(slot_w: float) -> int:
	var usable: float = slot_w - _LIFE_SCROLLBAR_W
	if usable < _life_pair_w():
		return 1
	var extra: int = int(floor((usable - _life_pair_w()) / (_life_pair_w() + _LIFE_COL_SEP)))
	return clampi(1 + extra, 1, maxi(1, life_columns))


## HOW THE STRIP'S CELLS SPLIT ACROSS COLUMNS — pure, so the whole space is sweepable.
##
## `capacity` is how many rows fit in one column at the panel's current height; `max_cols` is
## what the width affords. The rule is *use as many columns as it takes to avoid scrolling,
## up to the limit, then BALANCE them*:
##
##   9 cells, cap 12, lim 3  -> 1 column of 9    (the median emitter; unchanged from before)
##   20 cells, cap 12, lim 3 -> 2 columns of 10  (balanced, not 12 + 8)
##   35 cells, cap 12, lim 3 -> 3 columns of 12  (p99, and the last row that fits)
##   75 cells, cap 12, lim 3 -> 3 columns of 25  (the tail: it scrolls, and that is stated)
##
## BALANCED rather than fill-then-spill because a 13-cell strip against a 12-cell column
## would otherwise be a full column beside a single lonely thumbnail. Both avoid the scroll;
## only one of them looks like it meant to.
static func strip_columns(cell_count: int, capacity: int, max_cols: int) -> Dictionary:
	var cap: int = maxi(1, capacity)
	var lim: int = maxi(1, max_cols)
	if cell_count <= 0:
		return {"cols": 1, "per": 0}
	var want: int = int(ceil(float(cell_count) / float(cap)))
	var cols: int = clampi(want, 1, lim)
	return {"cols": cols, "per": int(ceil(float(cell_count) / float(cols)))}


const _STRIP_SEP := 2.0
## ADR-0130's Texture tab: the sheet's picture, on every screen, without navigating.
##
## The audit this answers found FOUR texture surfaces and none of them drawing the sheet
## — the only renderer was gated to the `frame` kind alone, so the Texture PAGE could not
## show the texture by construction. The tab is the shallow surface; the page stays the
## deep one.
##
## Built here but living in `TextureTabPanel.gd`, for the reason `FramesetRegionScope.gd`
## states in its own docstring: this file is large and concurrently edited, so a feature
## that can own a file should. The page builds it, connects three signals, positions it.
func _build_texture_tab() -> void:
	_tab_strip = HBoxContainer.new()
	_body.add_child(_tab_strip)
	_tab_texture_btn = Button.new()
	_tab_texture_btn.text = "Texture"
	_tab_texture_btn.toggle_mode = true
	_tab_texture_btn.tooltip_text = "The effect's texture sheet — the image every frame UVs into."
	_tab_texture_btn.pressed.connect(func(): _set_active_tab("texture"))
	_tab_strip.add_child(_tab_texture_btn)
	_tab_values_btn = Button.new()
	_tab_values_btn.text = "Values"
	_tab_values_btn.toggle_mode = true
	_tab_values_btn.button_pressed = true
	_tab_values_btn.tooltip_text = "The inspector — this target's fields."
	_tab_values_btn.pressed.connect(func(): _set_active_tab("values"))
	_tab_strip.add_child(_tab_values_btn)

	_texture_panel = TextureTab.new()
	_texture_panel.visible = false
	_body.add_child(_texture_panel)
	# The SAME two action kinds `TextureProjector` emits, so both routes land on the one
	# dispatcher (`_open_texture_dialog` reads `_effect_data`, never the open target).
	_texture_panel.action_requested.connect(func(kind: String):
		_open_texture_dialog(kind == "texture_export"))
	_texture_panel.uv_rect_changed.connect(_on_texture_tab_uv_changed)
	_texture_panel.group_uv_rect_changed.connect(_on_texture_tab_group_uv_changed)
	_texture_panel.region_scale_requested.connect(_on_region_scale_requested)


## The tab strip's REAL height, not the constant.
##
## `_TAB_STRIP_H` is a FLOOR, exactly as `PathBar.BAR_H` is: an HBoxContainer of Buttons
## carries its own font/padding minimum, and a Container cannot shrink below its minimum
## — so assigning the constant does not make the strip that tall, it makes the strip
## OVERHANG the rect by the difference and land on the inspector. Measured 31 against a
## 26 constant at the dev body, i.e. a 5px overlap, which `EffectStudioFramesetLayoutTest`
## caught as "the inspector abuts the tab strip exactly (strip bottom 231, inspector top
## 226)". The page already had this pattern for the path bar and this is the second copy;
## if a third appears it should be one helper.
func _tab_strip_h() -> float:
	if _tab_strip == null:
		return 0.0
	return maxf(_TAB_STRIP_H, _tab_strip.get_combined_minimum_size().y)


## Which of the left column's two occupants is showing. Re-flows, because the strip and
## both panels are manually positioned `_body` children.
func _set_active_tab(which: String) -> void:
	_active_tab = which
	# Switching TO the texture tab has to catch up on every playhead move made while it was
	# hidden — `_resync_texture_tab_to_playhead` declines to work on an invisible panel so
	# the coverage mask is not rebuilt behind the Values tab.
	if which == "texture":
		call_deferred("_resync_texture_tab_to_playhead")
	if _tab_values_btn != null:
		_tab_values_btn.button_pressed = (which == "values")
	if _tab_texture_btn != null:
		_tab_texture_btn.button_pressed = (which == "texture")
	_relayout()


## Bind the Texture tab to whatever the open target can honestly say about the sheet
## (ADR-0130 dec. 4). A `frame` target names one frame — one UV box, live handles, scope.
## A `frameset` names a group, which narrows the COVERAGE mask but mints no box (dec. 4a).
## Everything else is the whole sheet, read-only.
func _update_texture_tab(target: Dictionary) -> void:
	if _texture_panel == null:
		return
	var fs_idx := -1
	var fr_idx := -1
	var ref: Dictionary = Target.ref(target)
	match Target.kind(target):
		"frame":
			fs_idx = int(ref.get("frameset_index", -1))
			fr_idx = int(ref.get("frame_index", -1))
		"frameset":
			fs_idx = int(ref.get("index", -1))
		_:
			# ADR-0130 dec. 4b. An `emitter`, `animation` or particle `span` target has no
			# frameset of its own — but the PLAYER beside it is showing one, and "how does
			# it know which frameset is active" had no answer before this: the tab ignored
			# the playhead entirely and drew the whole effect.
			fs_idx = _shown_frameset()
	# THUMBNAIL ORDER, handed down before the bind so the rail's first row is already in it.
	# The tab does not know the sequence and must not derive one — a second walk of the
	# opcodes here would be a copy of the strip's decode that could disagree with it.
	_texture_panel.set_strip_framesets(_strip_framesets())
	_texture_panel.bind_sheet(_effect_data, fs_idx, fr_idx)


## The `frameset` of every cell of the sequence on screen, IN CELL ORDER, repeats and all.
##
## The rail beneath the texture viewfinder orders its tiles by this
## (`FramesetRegionScope.order_framesets`), so an author ticking framesets reads them in the
## order the sprite they are watching reaches them. Read from the canvas's own trace for the
## same reason `_shown_frameset` is: it is the decode the player is actually drawing.
##
## EMPTY IS A REAL ANSWER, not a failure — a `texture` target has no sequence panel up, and
## `order_framesets` leaves the row in index order when handed nothing.
func _strip_framesets() -> Array:
	if _sequence_canvas == null or _sequence_panel == null or not _sequence_panel.visible:
		return []
	var out: Array = []
	for cell in _sequence_canvas.get_trace():
		if cell is Dictionary:
			out.append(int(cell.get("frameset", -1)))
	return out


## The frameset the sequence player is currently showing, or -1.
##
## Read from the canvas's OWN trace and its own `shown_op`, never re-derived from `_nav`:
## the trace is the decode the player is actually drawing, and `shown_op` already owns the
## playing-vs-parked rule (a still that keeps running is not a look). A cell's `frameset`
## is absolute — `SequenceTimeline.trace` folds the group offset in — so it indexes
## `_effect_data.framesets` directly.
func _shown_frameset() -> int:
	if _sequence_canvas == null or _sequence_panel == null or not _sequence_panel.visible:
		return -1
	var trace: Array = _sequence_canvas.get_trace()
	var idx: int = _sequence_canvas.shown_op()
	if idx < 0 or idx >= trace.size() or not (trace[idx] is Dictionary):
		return -1
	return int(trace[idx].get("frameset", -1))


## A drag committed on the TAB's canvas. Deliberately not `_on_frameset_uv_changed`: that
## one reads `_nav.back()` and refuses anything but a `frame` target, which is right for
## the right-hand canvas (it is only ever shown on one) and wrong here — the tab is on
## every screen. This reads the address the TAB STAMPED at bind instead, the ADR-0100
## lesson that a re-derived address decodes a real rect and draws a real box with nothing
## on screen saying it is the wrong one.
func _on_texture_tab_uv_changed(new_uv: Dictionary) -> void:
	if _effect_data == null or not (_effect_data.framesets is Array):
		return
	var fs_idx: int = _texture_panel.bound_frameset()
	var fr_idx: int = _texture_panel.bound_frame()
	if fs_idx < 0 or fr_idx < 0:
		return   # no frame in context — the canvas draws no handles, so this cannot fire
	_commit_region_uv(fs_idx, fr_idx, new_uv)


## A drag committed on one of the N LIVE REGIONS the tab draws when the target is an
## `emitter`/`animation`/`span` (ADR-0130 dec. 12). The canvas hands over a REPRESENTATIVE
## MEMBER of the region it was dragging, as an index into the frameset the tab bound — so
## the address is still stamped upstream and still never re-derived here, which is the
## ADR-0100 rule this file's twin handler above exists to obey.
##
## From that point the two are the same edit and share `_commit_region_uv`: a region is a
## region however it was picked, and the scope, the per-member encodability verdict and the
## merge announcement must not be able to differ between the two surfaces.
func _on_texture_tab_group_uv_changed(member_frame_index: int, new_uv: Dictionary) -> void:
	if _effect_data == null or not (_effect_data.framesets is Array):
		return
	var fs_idx: int = _texture_panel.bound_frameset()
	if fs_idx < 0 or member_frame_index < 0:
		return
	_commit_region_uv(fs_idx, member_frame_index, new_uv)


## Lower a UV drag onto the REGION the dragged frame belongs to, through the #255 choke
## point as one compound edit and one undo (ADR-0099 dec. 9).
##
## `fr_idx` names ONE frame and the edit reaches every frame in the effect that shares its
## block — 81.4% of corpus regions have members in more than one frameset, and the biggest
## holds 107 frames. `region_members` is what expands it; the scope control is what lets the
## author narrow it, and its explicit ticks win when it has any (dec. 5's default is ALL).
func _commit_region_uv(fs_idx: int, fr_idx: int, new_uv: Dictionary) -> void:
	var block: Rect2i = FramesetCanvas.normalised_block(new_uv)
	var picked: Array = _texture_panel.selected_members()
	var members: Array = picked
	if members.is_empty():
		members = FramesetCanvas.region_members(_effect_data.framesets,
			FramesetCanvas.region_of(_effect_data.framesets, fs_idx, fr_idx))
	if members.is_empty():
		return
	# Asked of EVERY member before release (ADR-0099 dec. 4a): the encodable range of
	# uv.width/height is per-frame and per-axis, so a block one member stores comfortably
	# may be unstorable for another — and the writer masks the overflow silently, losing
	# both the block and the flip.
	var verdict: Dictionary = FramesetCanvas.region_write_verdict(
		_effect_data.framesets, members, block)
	if not verdict.get("ok", false):
		_set_status(String(verdict.get("message", "that block cannot be stored")))
		_render_current()
		return
	var compound: Array = FramesetCanvas.region_edits(_effect_data.framesets, members, block)
	if compound.is_empty():
		return
	if _host and _host.has_method("studio_apply_compound"):
		_host.studio_apply_compound(compound)
	var merge: Dictionary = FramesetCanvas.region_merge_preview(
		_effect_data.framesets, members, block)
	_set_status(_region_commit_status(members, fs_idx, merge))
	_render_current()


## Lower one turn of a quad transform knob (Width / Height / Rotation / Shear / Position)
## onto the eight raw corner components, as ONE compound edit and one undo.
##
## The knob is not a stored field. `FrameQuadTransform.decompose` reads the four corners as
## a transform over the sheet region, `with_term` replaces the ONE term the author typed —
## leaving every other at the precision it was read with, which is what stops the 8.89% of
## quads at an arbitrary angle from drifting a corner per keystroke — and `vertex_edits`
## emits only the components that actually moved. A knob nudged back to where it started
## therefore produces no edit and no undo entry to press through.
##
## SCOPE IS THIS FRAME. A quad is per-frame data and always has been (ADR-0099 dec. 3): the
## members of a shared region deliberately draw at different sizes, so there is nothing for
## the scope control to do here. The region-scoped verb is a SCALE, which is a different
## gesture with a different guarantee, and it lives beside the UV region commit.
func _commit_quad_term(field_ref: Dictionary, value) -> void:
	if _effect_data == null or not (_effect_data.framesets is Array):
		return
	var fs_idx := int(field_ref.get("frameset_index", -1))
	var fr_idx := int(field_ref.get("frame_index", -1))
	if fs_idx < 0 or fs_idx >= _effect_data.framesets.size():
		return
	var fs = _effect_data.framesets[fs_idx]
	var frames: Array = (fs.get("frames", []) if fs is Dictionary else [])
	if fr_idx < 0 or fr_idx >= frames.size() or not (frames[fr_idx] is Dictionary):
		return
	var frame: Dictionary = frames[fr_idx]

	var t: Dictionary = FrameQuadTransform.decompose(frame)
	if not bool(t.get("ok", false)):
		# A degenerate quad has no basis to decompose against, so there is no term to move.
		# The projector already says so and points at the raw corner rows.
		_set_status("this quad is degenerate — edit it through Raw corners")
		return
	var next: Dictionary = FrameQuadTransform.with_term(t, str(field_ref.get("field", "")), value)
	var compound: Array = FrameQuadTransform.vertex_edits(fs_idx, fr_idx, frame, next)
	if compound.is_empty():
		return
	if _host and _host.has_method("studio_apply_compound"):
		_host.studio_apply_compound(compound)
	# IN PLACE, never `_render_current()`. These rows are ScrubFields and every one of these
	# edits arrives outside a defer_refold drag, so a reproject would queue_free the field
	# being dragged and the drag would die after one pixel — the reasoning `_apply_edit`'s
	# `sequence` and `frameset` branches already carry. `_refresh_sequence_preview` no-ops
	# unless the sequence player is up; on the frame screen the frameset canvas owns its own
	# refresh, and the quad it draws is re-read from the (live) frame dict.
	_refresh_sequence_preview()
	if _frameset_canvas != null and _frameset_panel != null and _frameset_panel.visible:
		_frameset_canvas.queue_redraw()


## THE REGION-SCOPED SCALE (ADR-0099 dec. 3 amendment). Multiply every member the scope
## control has selected by `factor`, about the sprite origin, as ONE compound and one undo.
##
## Reported as: *"I don't think its like UVs where things move identically - I do think
## there should be some sort of - all frames at this UV get a scaled adjustment"*. That
## sentence is precisely the one region-scoped vertex operation the corpus does not refuse.
## Dec. 3 forbids the whole class in its LETTER; its REASONING objects only to an ADDITIVE
## delta, which over a group drawing at 7x7 through 56x56 "would flatten a 6x growth ramp
## into a constant offset". Multiplying preserves every ratio the group encodes.
##
## `members` arrives FROM the control, never re-derived here: it is the list the author read
## the count off before pressing Apply, and re-deriving it would be the ADR-0100 defect —
## the number stated and the number edited coming from two places.
##
## Asked before ANY member is written (dec. 4a), because the alternatives are silent: a
## component that leaves signed 16-bit, and a member small enough that the factor rounds it
## to no area at all. A clamp discovered halfway through 30 members is a partial edit with
## no diagnostic anywhere.
func _on_region_scale_requested(factor: float, members: Array) -> void:
	if _effect_data == null or not (_effect_data.framesets is Array):
		return
	if members.is_empty():
		return
	var verdict: Dictionary = FrameQuadTransform.scale_verdict(
		_effect_data.framesets, members, factor)
	if not verdict.get("ok", false):
		_set_status(String(verdict.get("message", "that scale cannot be stored")))
		return
	var compound: Array = FrameQuadTransform.scale_edits(_effect_data.framesets, members, factor)
	if compound.is_empty():
		return   # a factor that rounds to no change on any member — not an undo entry
	if _host and _host.has_method("studio_apply_compound"):
		_host.studio_apply_compound(compound)
	_set_status(_region_scale_status(members, factor))
	_render_current()


## What the author is told after a region scale lands. NAMES THE FRAMESETS IT REACHED THAT
## ARE NOT ON SCREEN, for the same reason `_region_commit_status` does: 81.4% of corpus
## regions have members in more than one frameset, so "scaled 6 frames" is true and still
## leaves the author counting thumbnails to check it. Pure.
static func _region_scale_status(members: Array, factor: float) -> String:
	var elsewhere: Dictionary = {}
	for m in members:
		elsewhere[int(m.get("frameset_index", -1))] = true
	var head := "Scaled %d frame%s by %.2f×" % [members.size(),
		"" if members.size() == 1 else "s", factor]
	if elsewhere.size() <= 1:
		return head
	var names: Array = elsewhere.keys()
	names.sort()
	var listed: Array = []
	for n in names:
		listed.append(str(n))
	return "%s — framesets %s" % [head, ", ".join(listed)]


## The #278 frameset texture canvas — the right-hand area of the inspector row, shown and
## hidden per-target by `_update_frameset_canvas` (not by a Close button): it tracks
## whatever frame is being inspected rather than being opened on demand. It is a child of
## `_body`, NOT of the page, so it shares the inspector's coordinate space, is clipped by
## `_body.clip_contents`, and is positioned by `_relayout` alongside every other body child.
func _build_frameset_canvas_overlay() -> void:
	_frameset_panel = PanelContainer.new()
	_frameset_panel.visible = false
	_body.add_child(_frameset_panel)

	var vb2 := VBoxContainer.new()
	_frameset_panel.add_child(vb2)
	_frameset_canvas_title = Label.new()
	_frameset_canvas_title.text = "Frame"
	vb2.add_child(_frameset_canvas_title)

	_frameset_canvas = FramesetCanvas.new()
	# EXPAND_FILL — a custom_minimum_size floor alone doesn't grow a child past its
	# minimum even when the parent has more room; without this the canvas sat at a
	# small natural size inside the (correctly big) panel, leaving a dead gap of
	# transparent VBoxContainer space around it (the actual cause of "still lots of
	# empty space" — not `texture_rect`'s letterboxing, which only kicks in once the
	# canvas's OWN rect is already the full available size).
	_frameset_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_frameset_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb2.add_child(_frameset_canvas)
	_frameset_canvas.uv_rect_changed.connect(_on_frameset_uv_changed)

	# ADR-0098 dec. 6's readout. `hover_changed` was built and guarded on the canvas and
	# had NO CALLER until now, so the readout it exists to feed never appeared.
	_frameset_readout = Label.new()
	_frameset_readout.text = ""
	vb2.add_child(_frameset_readout)
	_frameset_canvas.hover_changed.connect(_on_frameset_hover)

	# ADR-0099 dec. 5. Below the canvas rather than beside it: the scope has to be read
	# in the same glance as the box it will move.
	_region_scope = RegionScope.new()
	vb2.add_child(_region_scope)


## Show the frameset texture canvas, bound to the current frame, while a "frame" target is
## open; hide it for every other target (mirrors `_update_pair_panel`'s per-target show/hide
## shape). Read-only in v1 — the canvas draws the UV box, it doesn't yet accept drags (#279).
func _update_frameset_canvas(target: Dictionary) -> void:
	if _frameset_canvas == null or _frameset_panel == null:
		return
	# ADR-0130 dec. 8. This gate is the load-bearing line of the whole complaint: the ONLY
	# renderer of the sheet admitted the `frame` kind alone, so the Texture PAGE could not
	# show the texture BY CONSTRUCTION and the picture sat three drills deep. `texture` is
	# admitted now, and binds the EMPTY frame — the read-only whole-sheet view that
	# `FramesetCanvas._draw` has always been able to draw (it paints sheet + coverage
	# unconditionally and only then `if not _frame.is_empty()` draws the overlay) and that
	# nothing had ever called.
	# ADR-0130 dec. 10: a `frame` target NO LONGER parks the sheet here. The Texture tab
	# already draws it in the left column, with the same live handles and the same scope
	# control, so showing it twice paid for one picture twice and gave the author two
	# places to drag the same box. The slot goes to the sequence player instead — the frame
	# screen becomes "the sheet on the left, the animation on the right". Same trade that
	# made the tab beat the band: stop spending the row on a duplicate.
	#
	# `texture` KEEPS it. There is no sequence for a texture target to show, and dec. 8 —
	# the page finally having a picture without switching tabs — is the whole complaint
	# this ADR opened on.
	var kind: String = Target.kind(target)
	if not (kind in ["texture"]) or _effect_data == null:
		_frameset_panel.visible = false
		_relayout()   # give the width back to the frame-controls column
		return
	# Nothing to speak for but the sheet, and nothing invented: no UV box, no handles, no
	# scope control. `FramesetCanvas._draw` paints the sheet and the ADR-0098 dec. 5
	# coverage mask unconditionally and only then `if not _frame.is_empty()` draws the
	# overlay — so the empty dictionary IS the read-only whole-sheet view, and it is the
	# view this page existed to show and never could.
	#
	# The per-frame branch that used to live here is GONE (ADR-0130 dec. 10): a `frame`
	# target no longer reaches this function at all, so its fs/fr resolution, its
	# `_region_scope.bind` and its title were dead the moment the gate above narrowed to
	# `texture`. The Texture tab owns that job now, scope control included.
	if _effect_data.texture == null:
		_frameset_panel.visible = false
		_relayout()
		return
	_frameset_canvas_title.text = "Texture — the whole sheet"
	_frameset_canvas.bind_frame(_effect_data.texture, {})
	_frameset_canvas.bind_framesets(_effect_data.framesets,
		Vector2i(_effect_data.texture.get_width(), _effect_data.texture.get_height()))
	_frameset_canvas.bind_group([])
	if _region_scope != null:
		_region_scope.visible = false
	# Visible FIRST, then re-flow: `_relayout` splits the row only when the panel is
	# showing, so flipping visibility after would leave the left column at full width.
	_frameset_panel.visible = true
	_relayout()


## The #247 sequence viewport: the assembled animation, playing, with a transport under
## it. Structurally a twin of `_build_frameset_canvas_overlay` — a title over a canvas in
## a PanelContainer parented to `_body` — so that `_canvas_chrome_h` can measure it by the
## same rule. It MEASURES the chrome rather than assuming it, which is what lets this
## panel grow a transport row at all: the constant it replaced went silently wrong the
## first time the frameset panel gained a row.
##
## The transport is speed and opcode STEP, and no scrubber. `SequenceTimeline.trace` is
## one cell per opcode and the picture is constant for that cell's whole dwell, so a
## tick-level scrubber would slide through eight ticks of an identical image; picking an
## opcode is the only pick there is, and a thumbnail click already makes it.
func _build_sequence_canvas_overlay() -> void:
	_sequence_panel = PanelContainer.new()
	_sequence_panel.visible = false
	_body.add_child(_sequence_panel)

	var vb := VBoxContainer.new()
	_sequence_panel.add_child(vb)
	_sequence_canvas_title = Label.new()
	_sequence_canvas_title.text = "Sequence"
	vb.add_child(_sequence_canvas_title)

	# THE PANEL'S BODY IS A ROW, not a stack (ADR-0089 vertical-column amendment,
	# 2026-08-20). The colour ribbon and the film strip used to sit UNDER the player,
	# stacked, and between them they ate 108px of the panel's height — which is why the
	# canvas, whose box is a CONSTANT 260 square (ADR-0100 dec. 2), was being starved to
	# 260x84 at the developer's window. They are now a COLUMN to the right of the player,
	# where the space was already dead: the square is centred in the panel's width, so a
	# 558px panel had ~149px unused on each side of it.
	#
	# Author's shape, and the reason it is a row at all: *"the ribbon should run vertical
	# down the side of the thumbnails"*. Row i of the ribbon is thumbnail i, so the two
	# cannot disagree about alignment — the complaint that started this ("it looks like the
	# thumbnails should align to the color ribbon but they don't") is unrepresentable now
	# rather than merely explained.
	_sequence_body = HBoxContainer.new()
	_sequence_body.add_theme_constant_override("separation", int(_STRIP_SEP))
	_sequence_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sequence_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_sequence_body)

	_sequence_canvas = SequenceCanvas.new()
	# EXPAND_FILL and NO custom_minimum_size floor of its own: a floor here would
	# raise the PanelContainer's combined minimum above the height `_relayout` assigns
	# and a container cannot shrink below its minimum, so the panel would overflow
	# DOWNWARD into the timeline. `_relayout` sizes it explicitly instead.
	# SHRINK_CENTER, not EXPAND_FILL: the column is now sized for whichever of its two
	# occupants wants more width — the player's constant square or the frameset block stacked
	# under it — and an expanding canvas would stretch the box to whatever the BLOCK asked
	# for. The box is a constant (ADR-0100 dec. 2); it sits centred in the surplus instead.
	_sequence_canvas.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_sequence_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# The unified animation screen's block follows the film strip through this ONE signal
	# (ADR-0102). Connected here, at construction, because the panel is built once and lives
	# for the page's lifetime — re-connecting per bind would stack duplicate handlers.
	_sequence_canvas.selection_changed.connect(_on_sequence_selection_changed)
	# The RUNNING player moves the tab too — dec. 4c's "scrubbing walks the outlines around
	# the sheet" is about watching the sheet as the animation plays, which is the case a
	# thumbnail click does not cover. Fires once per opcode, not once per frame.
	_sequence_canvas.playhead_changed.connect(func(_op): _resync_texture_tab_to_playhead())
	_sequence_body.add_child(_sequence_canvas)

	# THE LIFE COLUMN — the colour ribbon and the film strip, side by side, running DOWN
	# the panel to the right of the player (ADR-0089 vertical-column amendment, 2026-08-20).
	#
	# One slot, not two, because the ribbon and the strip now share a scroll offset BY
	# CONSTRUCTION: they are siblings inside one ScrollContainer, so a row and its thumbnail
	# cannot drift apart no matter how far the author scrolls. Two scrollers kept in sync by
	# a signal would be the same picture with a bug in it.
	#
	# ITS SLOT IS RESERVED, exactly as the ribbon's and the strip's were when they were
	# stacked, and the reason is unchanged: `_canvas_chrome_h` and `_canvas_floor_w` both
	# SKIP INVISIBLE CHILDREN, so anything here that hid itself would swing the panel's
	# measured chrome as the author browsed from a colour-enabled sequence to one without.
	# What CHANGED is the dimension it declares — this occupant costs the canvas WIDTH now,
	# not height, so the slot declares a width and lets its height be the panel's.
	_sequence_life_slot = Control.new()
	_sequence_life_slot.custom_minimum_size = Vector2(sequence_life_column_w(), 0.0)
	_sequence_life_slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# PASS, not IGNORE: a tooltip needs the mouse, and this is where the colour provenance
	# rung is spelled out in full for an author who cannot see the focus panel's title.
	_sequence_life_slot.mouse_filter = Control.MOUSE_FILTER_PASS
	_sequence_body.add_child(_sequence_life_slot)

	_sequence_strip_scroll = ScrollContainer.new()
	_sequence_strip_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# HORIZONTAL DISABLED, vertical AUTO — the inverse of what the wrapping strip needed.
	# The old strip was an HFlowContainer that had to be handed an edge to wrap against;
	# this one never wraps, so horizontal scrolling would only ever hide the ribbon or the
	# thumbnails from each other.
	_sequence_strip_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sequence_strip_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_sequence_life_slot.add_child(_sequence_strip_scroll)

	# THE COLUMNS' OWN ROW. One HBox holding `life_columns` (ribbon, thumbnails) PAIRS, all
	# built here and none ever created or destroyed at layout time — wrapping moves children
	# between the pairs, it does not build new ones. Every pair is inside the ONE
	# ScrollContainer above, which is what keeps a shared scroll offset across all of them:
	# scrolling column 1 cannot slide it out of step with column 2, because there is only
	# one offset to slide.
	var life_row := HBoxContainer.new()
	life_row.add_theme_constant_override("separation", int(_LIFE_COL_SEP))
	life_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_sequence_strip_scroll.add_child(life_row)

	# THE RIBBON, VERTICAL. Not `ColourRibbon` rotated: the mapping is fundamentally
	# different (row + column, not a linear x), so this is its own control. What it does
	# share is the colour resolve — it is fed `ColourRibbon.frame_colors`, the same array
	# the horizontal band drew, including the representative-sprite mux. One term, one
	# meaning; only the geometry moved.
	# THE PAIRS. Each is a ribbon and the thumbnails it belongs to, side by side, and the
	# wrap works because the RIBBON WRAPS TOO — which is precisely the argument that reversed
	# the old no-wrap rule (see `EffectStudioSequenceViewportTest`). "A second column of
	# thumbnails would have no ribbon next to it" was true of a design with one ribbon; it is
	# not a fact about wrapping, it was a fact about that design.
	#
	# EVERY PAIR SHARES THE SAME `_colour_selected_frame` and the same keyframe list, and
	# nothing had to change in `ColourLifeColumn` to make that safe: `rect_of_frame` returns
	# an empty rect for an age outside the slice it was configured with, so a column simply
	# draws no mark for a selection that is not its own. The widget was already frame-
	# addressed rather than index-addressed (ADR-0089 dec. 5), and that is what makes a
	# slice a legal configuration of it.
	_sequence_life_columns = []
	_sequence_strip_rows = []
	_sequence_life_pairs = []
	for i in range(maxi(1, life_columns)):
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", int(_STRIP_SEP))
		pair.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		life_row.add_child(pair)
		var lc = LifeColumn.new()
		lc.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		pair.add_child(lc)
		lc.frame_selected.connect(_on_colour_frame_selected)
		lc.keyframe_remove_requested.connect(_on_colour_kf_remove)
		_sequence_life_columns.append(lc)
		# THE FILM STRIP, one thumbnail per LIFE ROW. A VBox and not the old
		# HFlowContainer: the flow wrapped in the WRONG AXIS for a column beside a ribbon.
		# The wrap is back, one level up — between pairs — where the ribbon comes with it.
		var sv := VBoxContainer.new()
		sv.add_theme_constant_override("separation", 0)
		sv.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		pair.add_child(sv)
		_sequence_strip_rows.append(sv)
		_sequence_life_pairs.append(pair)
	# COLUMN 0 IS THE CANONICAL ONE. Everything that asks a single question of the surface —
	# is colour live, where is the selection, how tall is a row — asks this one, because
	# those answers are the same for every column by construction. Only layout is plural.
	_sequence_life_column = _sequence_life_columns[0]
	_sequence_strip_row = _sequence_strip_rows[0]

	# The horizontal ribbon that used to live under the player is GONE, and with it
	# its slot and its `ColourKeyframeTrack`. `_sequence_ribbon` survives as a
	# headless resolver — `_update_sequence_ribbon` still feeds it curves and reads
	# `colors()` — because that is where the sprite mux and the `Fit W` trim live, and
	# re-deriving them here would be the second copy those exist to prevent.
	_sequence_ribbon = ColourRibbon.new()
	# HEADLESS, AND IT HAS TO BE RE-PARKED. `set_curves` sets its own visibility from the
	# colour-enabled flag — that was the point when it drew itself — so a one-time
	# `visible = false` here is undone by the first bind. Every call site re-parks it, which
	# is two lines and is why this is not a subclass: the instance is kept for its STATE (the
	# sprite mux, the `Fit W` trim, the resolved `colors()` array), not for its picture.
	_sequence_ribbon.visible = false
	_sequence_ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sequence_life_slot.add_child(_sequence_ribbon)

	var transport := HBoxContainer.new()
	transport.add_theme_constant_override("separation", 6)
	vb.add_child(transport)
	_tool_button(transport, "⏮ op", func(): _park_sequence_on_step(-1))
	_tool_button(transport, "op ⏭", func(): _park_sequence_on_step(1))
	# The page transport's speed idiom exactly (`_speed_btn`), with its own value.
	_sequence_speed_field = ScrubField.new()
	_sequence_speed_field.min_value = SequenceCanvas.SPEED_MIN
	_sequence_speed_field.max_value = SequenceCanvas.SPEED_MAX
	_sequence_speed_field.step = 0.05
	_sequence_speed_field.scrub_sensitivity = 0.01
	_sequence_speed_field.suffix = "×"
	_sequence_speed_field.tooltip_text = ("Playback rate for THIS player only — the effect "
		+ "timeline keeps its own. 1.00× is true game speed (30 ticks/s).")
	transport.add_child(_sequence_speed_field)
	_sequence_speed_field.set_value_no_signal(_sequence_speed)
	_sequence_speed_field.value_changed.connect(func(v):
		_sequence_speed = v
		if _sequence_canvas != null:
			_sequence_canvas.set_speed(v))

	# COLOUR ON/OFF, in the transport row (author, 2026-08-20: *"I want to be able to toggle
	# color on and off near where all the 'color' stuff is - which is that panel."*).
	#
	# THE MACHINERY ALREADY EXISTED — `EmitterParamRows`' "Colour curves" enum row, on
	# `emitter_flags_lo` bit 6 — buried in the emitter inspector's flag section. This is a
	# RELOCATION, and the only new code is the mint (see `studio_colour_enable`).
	#
	# HERE, and not in the picker panel the author pointed at, for a reason the ask itself
	# cannot see: the picker panel only exists while an age is SELECTED, and there is no age
	# to select while colour is off — a toggle living there could turn colour off and never
	# turn it back on. The transport row is the nearest thing that is always up whenever the
	# player column is, sits directly under the colour column, and costs no chrome height.
	#
	# IT IS ALSO THE ANSWER TO "WHY IS THERE NO COLUMN?". With colour off the column is
	# simply absent with nothing explaining why, which is what sent the author looking for a
	# ⬥ button that was not there to find. Reading "Colour: off" in the player's own
	# transport closes that loop, so this is a label as much as a control.
	_colour_enable_btn = Button.new()
	_colour_enable_btn.toggle_mode = true
	_colour_enable_btn.text = "Colour"
	_colour_enable_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	transport.add_child(_colour_enable_btn)
	_colour_enable_btn.toggled.connect(_on_colour_enable_toggled)

	_build_colour_picker_panel()


## THE COLOUR PICKER, a THIRD stacked panel in the player's column (ADR-0089 colour-move
## amendment; ADR-0100 dec. 1's occupant list grows by one).
##
## It is a SIBLING of the player panel, not a row inside it, and that placement is the whole
## design. Inside the player panel it would be measured by `_canvas_chrome_h`, which skips
## invisible children — so a picker that hid itself with no selection would swing the panel's
## chrome by 439px and re-size the canvas square every time the author clicked a keyframe.
## That is the failure ADR-0102/0103's reserved slots keep re-learning, at eleven times the
## amplitude. As its own panel it is laid out explicitly by `_relayout` and the square never
## hears about it.
##
## IT IS ALWAYS PRESENT WHILE THE COLUMN IS, and shows a dimmed plate when nothing is selected
## rather than collapsing (author's decision, 2026-08-20: nothing moves). The author's ask was
## "the colour picker should only appear when a keyframe is selected"; what they chose when
## shown the cost was the constant-height reading of it — the picker is only USABLE on a
## selection, and the space is not handed back and forth under the cursor.
##
## THE HEIGHT IS DECLARED, AND IT IS EXPENSIVE. Godot's `ColorPicker` reports a hard
## 298 x 439 combined minimum and refuses to shrink (measured; `sliders_visible = false` and
## `hex_visible = false` bring it to 298 x 264 and the width never moves — it is the theme's).
## So this panel roughly doubles the column's vertical appetite: the player's box is
## `_CANVAS_SIDE` plus ~188 of measured chrome, and `focus_stack_height` hands the ADR-0102
## frameset block only what is left. That block already required a row over roughly 510px and
## therefore never appeared on the developer dashboard's 268px row; this raises the threshold
## rather than introducing a new failure — but it raises it a long way, which is why the height
## is an ADR-0068 static var rather than a constant. Move it without a rebuild.
static var picker_panel_h: float = 439.0
## The picker's declared WIDTH, the horizontal peer of the height above and the reason the
## player's column is 314 rather than 276 whenever it is up. Measured, not chosen: a bare
## `ColourBoxPicker` reports (298, 439) and returns the same 298 after being assigned 200.
static var picker_panel_w: float = 298.0
## The panel's height with the GRID HIDDEN — the title row plus the ⬥ button. This is the
## FLOOR the panel degrades to rather than disappearing, and it is why ⬥ is reachable on a
## row that cannot afford `picker_panel_h`. Declared rather than measured for the same reason
## `picker_panel_h` is: `_relayout` has to decide whether the grid fits BEFORE it can hide it,
## and a minimum read back from a container whose children were just hidden is a frame stale.
## `EffectStudioColourColumnTest` asserts the real header minimum does not exceed this, so it
## cannot rot silently.
##
## It grew from 64 on 2026-08-21 to hold the RENDERS-AS row. That row is header, not grid, on
## purpose: once the picker authors the curve rather than the output (ADR-0089 decision 4,
## amended), the swatch alone no longer says what the particle will look like, and the row that
## says it has to survive the same slack the ⬥ button does.
static var picker_head_h: float = 88.0


## Does the column's SLACK under the player afford the colour grid? Pure and static, the peer
## of `focus_stack_height`, so the three-way height choice can be swept across the whole slack
## range without a window — including the negative slack a very short row produces, which is
## the case the old `picker_h > 0` visibility rule got wrong and no live layout test would
## naturally reach.
static func colour_picker_grid_fits(slack: float) -> bool:
	return slack >= picker_panel_h


## The picker panel's height for a given slack. NEVER ZERO while an age is selected — that is
## the whole contract: the full panel when the grid fits, the header alone (title + ⬥) when it
## does not. See `_relayout` for why there is no intermediate reading.
static func colour_picker_height(slack: float) -> float:
	return picker_panel_h if colour_picker_grid_fits(slack) else picker_head_h
func _build_colour_picker_panel() -> void:
	_colour_picker_panel = PanelContainer.new()
	_colour_picker_panel.visible = false
	_body.add_child(_colour_picker_panel)
	var pv := VBoxContainer.new()
	_colour_picker_panel.add_child(pv)
	_colour_picker_title = Label.new()
	_colour_picker_title.add_theme_font_size_override("font_size", 11)
	_colour_picker_title.text = "Colour"
	pv.add_child(_colour_picker_title)
	# NO "nothing selected" PLATE. The panel itself is the conditional thing now, so a plate
	# saying "pick a frame" would only ever be drawn in the frame between a selection being
	# cleared and the re-stack — 439px of column held open to say the column is not needed.
	#
	# ⬥ SET KEYFRAME — THE SECOND STEP (author, 2026-08-20: *"selecting frames is good but
	# adding them by clicking them is not. there needs be a second step to lock it into
	# being a keyframe instead of just a frame"*).
	#
	# The author was shown that an explicit-button-only rule means dragging the picker on an
	# interpolated age changes nothing on screen, and chose it anyway. So: the picker widget
	# still moves under the cursor — it is a colour picker — but NOTHING is authored and no
	# keyframe is minted until this is pressed. Nothing keys implicitly.
	#
	# It is one control carrying a state and an action, the way an animation tool's diamond
	# does: enabled and labelled "Set keyframe" on an interpolated age, disabled and labelled
	# "keyframe" on one that already is. A separate indicator would have been a second thing
	# to keep in sync with the same fact.
	#
	# IT IS THE SECOND CHILD, ABOVE THE GRID, and that is not cosmetics (author, 2026-08-20:
	# *"I don't see where I toggle key frame on and off. You said there was a button - but I
	# don't see it."*). As the LAST child of this VBox it sat under a 439px wall of colour at
	# the very bottom edge of the display — measured on the author's window at y=1019 of a
	# 1069px body, 50px of clearance. Two things put it there and both are fixed here:
	# the panel's CONTENT minimum (~500px) exceeds its declared `picker_panel_h` (439), so a
	# Control that cannot shrink below its minimum overflows DOWNWARD past the rect
	# `_relayout` hands it — and everything that overflows is whatever is at the bottom.
	# Above the grid, the button is inside the first ~60px of the panel and survives any
	# amount of that overflow. See also the header floor in `_relayout`.
	_colour_key_button = Button.new()
	_colour_key_button.text = "⬥ Set keyframe"
	_colour_key_button.tooltip_text = ("Lock the selected age in as a real keyframe at the "
		+ "colour shown, or press K. Until you press this, the picker is a preview and the "
		+ "curve is untouched.")
	_colour_key_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	pv.add_child(_colour_key_button)
	_colour_key_button.pressed.connect(_on_colour_set_keyframe)

	# RENDERS AS — the second half of the pick, and the reason the picker is allowed to be
	# unrestricted (ADR-0089 decision 4, amended 2026-08-21). The grid now authors the CURVE, so
	# the swatch is the value being written and no longer a preview of the particle: the render
	# is `S ⊙ curve` and a multiply can never add a channel the sprite lacks. That bound used to
	# be applied silently to the pick, which is what made 97.5% of colour emitters unable to hold
	# 255 in any channel. It is stated here instead — the colour the emitter will actually show
	# for what is in the grid, beside the grid, plus the dead channels named when there are any.
	#
	# It sits ABOVE the grid with the ⬥ button for the same reason ⬥ does: the panel's content
	# minimum exceeds `picker_panel_h`, so everything at the bottom is what overflows off the
	# display, and a bound nobody can see is the fault this row exists to remove.
	var rv := HBoxContainer.new()
	rv.add_theme_constant_override("separation", 5)
	pv.add_child(rv)
	_colour_renders_as = ColorRect.new()
	_colour_renders_as.custom_minimum_size = Vector2(14, 14)
	_colour_renders_as.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rv.add_child(_colour_renders_as)
	_colour_renders_as_label = Label.new()
	_colour_renders_as_label.add_theme_font_size_override("font_size", 10)
	# ONE LINE, CLIPPED — never wrapping. An autowrap Label's minimum HEIGHT is a function of
	# the width it is given, and in this 298px column that put the panel's header minimum at
	# 228px against a declared floor of 88 — which is not a cosmetic overrun: the floor is what
	# `_relayout` degrades to on a short row, and everything past it overflows off the bottom of
	# the display taking the ⬥ button with it. The dead-channel fact is carried as a short tag
	# here and as a sentence in the tooltip.
	_colour_renders_as_label.clip_text = true
	_colour_renders_as_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_colour_renders_as_label.text = "renders as"
	rv.add_child(_colour_renders_as_label)

	# THE GRID LAST, because it is the only child that can be dropped. When the column's
	# slack cannot afford `picker_panel_h`, `_relayout` hides THIS and the panel collapses to
	# its header — the title and ⬥ — rather than the whole panel disappearing and taking the
	# only way to mint a keyframe with it. A Container cannot render a PARTIAL ColorPicker
	# (298x439 is a hard minimum it refuses to shrink), so "some of the grid" was never one
	# of the options; the choice is the grid or the gesture, and the gesture wins.
	_colour_picker = ColourPicker_.new()
	_colour_picker.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_colour_picker.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pv.add_child(_colour_picker)
	_colour_picker.curve_picked.connect(_on_colour_authored)


## Rebuild the film strip under the player from the canvas's ALREADY-COMPUTED trace, bounds
## and display texture — the same three things `_sequence_thumbnail_for` feeds the inspector's
## opcode rows, so a cell here and a cell there cannot disagree about what an opcode looks
## like, and the expensive `display_image` conversion stays one per texture.
##
## Rebuilt wholesale per bind rather than diffed: a bind changes the sequence, so every cell's
## subject changes, and `queue_free` drops each thumbnail's four canvas connections with the
## node (`follow` relies on exactly that contract). What is NOT rebuilt is the response to an
## EDIT — each thumbnail subscribes itself to `decode_changed` and re-pulls its own cell, so
## there is no list here to go stale (ADR-0100 dec. 8's reasoning, one layer down).
func _rebuild_sequence_strip() -> void:
	if _sequence_strip_row == null or _sequence_canvas == null:
		return
	for vb in _sequence_strip_rows:
		for child in (vb as Control).get_children():
			(vb as Control).remove_child(child)
			child.queue_free()
	_sequence_strip_cells = []
	_strip_split = {}
	var trace: Array = _sequence_canvas.get_trace()
	var framesets: Array = _sequence_canvas.get_framesets()
	var bounds: Rect2i = _sequence_canvas.get_bounds()
	var tex: Texture2D = _sequence_canvas.get_display_texture()
	# THE SECOND ENTRY POINT (ADR-0089 colour-move amendment). Each cell knows which life
	# frame it lands on, so right-clicking it authors a colour there — the author's own
	# model: "either way it's 1 ribbon at the frame level with 2 entry points".
	#
	# The projection is a PARTIAL function and the cells that fall outside it are dimmed
	# rather than silently inert. 324 of the corpus's 2622 colour-enabled emitters (12.4%)
	# die mid-animation, so their tail opcodes never play at all — a dimmed cell with a
	# tooltip saying so is strictly more than the strip used to know.
	# THE STRIP IS THE PARTICLE'S LIFE NOW, not the opcode list (ADR-0089 vertical-column
	# amendment). One thumbnail per LIFE ROW, so the ribbon beside it can be one row per
	# thumbnail and the two cannot disagree about alignment. Three consequences, all of them
	# the model rather than side effects:
	#
	#   * a ZERO-DWELL cell (LOOP, SET_OFFSET) holds no age, so it gets no row. It is still
	#     in the trace and the inspector's opcode rows still show it; it is simply not part
	#     of any life frame, and a thumbnail beside a colour it never displays would be a
	#     lie in the one place this surface exists to tell the truth.
	#   * a LOOPED cell appears ONCE PER PASS (105 corpus emitters, 4.0%). The old strip
	#     showed it once and `SequenceLifeMap` resolved repeats to the first occurrence,
	#     which left every later pass unauthorable. Each pass is its own row now.
	#   * a PARKED terminal frame (726 emitters, 27.8%) is ONE row holding many columns —
	#     the tail is inside its row, not a run of duplicate thumbnails.
	#
	# Net: the column is SHORTER than the strip it replaces — median 9 rows against 12 trace
	# cells, max 75 against 98 (`tools/census_life_column.gd`).
	var life_n: int = int(_sequence_colour_window.get("n", -1))
	var colour_live: bool = _sequence_life_column != null and _sequence_life_column.visible
	_sequence_life_rows = LifeMap.life_rows(trace, life_n) if colour_live else []
	# COLOUR OFF FALLS BACK TO THE TRACE, one row per cell. The strip is the sequence's
	# picture first and the colour surface's ruler second, so an emitter with no colour
	# curves still gets its film strip — it just gets no ribbon beside it.
	var rows: Array = _sequence_life_rows
	if rows.is_empty():
		rows = []
		for i in range(trace.size()):
			rows.append({"cell": i, "start": -1, "ticks": 0})
	for r in rows:
		var ci: int = int(r["cell"])
		if ci < 0 or ci >= trace.size():
			continue
		var thumb = SequenceThumbnail.new()
		thumb.bind_state(trace[ci], framesets, bounds, tex)
		thumb.clicked.connect(_park_sequence_on.bind(ci))
		if colour_live:
			var start: int = int(r["start"])
			var held: int = int(r["ticks"])
			thumb.colour_requested.connect(_on_strip_colour_requested.bind(ci, start))
			thumb.tooltip_text += ("\n\nLife frame %d%s — right-click to colour it"
				% [start, (" – %d (%d frames held)" % [start + held - 1, held]) if held > 1 else ""])
		# Both marks go live: yellow where the author parked, white under the running
		# playhead — see SequenceThumbnail.follow. A looped cell has several rows, and all
		# of them light: the picture really is showing at each of those ages.
		thumb.follow(_sequence_canvas, ci)
		_sequence_strip_cells.append(thumb)
	# THE CELLS THE PARTICLE NEVER REACHES, kept and MARKED (author's call, 2026-08-20:
	# "show both, marked"). 374 corpus emitters (14.3%) die mid-animation, so their tail
	# opcodes have no life row at all. Dropping them would misrepresent the ANIMATION to say
	# something about the particle; they follow the life rows, dimmed, with no ribbon beside
	# them — which is what "no colour to author here" looks like when the ribbon is a column.
	if colour_live:
		var reached: Dictionary = {}
		for r in _sequence_life_rows:
			reached[int(r["cell"])] = true
		for i in range(trace.size()):
			if reached.has(i) or int(trace[i].get("ticks", 0)) <= 0:
				continue
			var dead = SequenceThumbnail.new()
			dead.bind_state(trace[i], framesets, bounds, tex)
			dead.clicked.connect(_park_sequence_on.bind(i))
			dead.modulate = Color(1.0, 1.0, 1.0, 0.35)
			dead.tooltip_text += ("\n\nThis particle dies before reaching this opcode "
				+ "(life is %d frames) — no colour to author here." % life_n)
			dead.follow(_sequence_canvas, i)
			# APPENDED AFTER the life rows, and the order is load-bearing for the wrap: a
			# column's ribbon slice is its share of `_sequence_life_rows`, so as long as
			# every unreached cell sorts after every life row, the ribbon beside a column
			# covers exactly its top and the unreached tail hangs below it with no ribbon —
			# which is what "no colour to author here" looks like, per column now.
			_sequence_strip_cells.append(dead)
	_bind_life_column()
	_distribute_strip()
	_scroll_strip_to_selection()


## LAY THE ALREADY-BUILT CELLS OUT ACROSS THE COLUMNS (author, 2026-08-20: *"I don't want to
## have to scroll to see all the thumb nails. I just want them to form another row on the
## right."*).
##
## Reparents, never rebuilds. The cells are expensive — each carries a bound frameset, a
## display texture and four canvas subscriptions — and the thing that changes when the window
## resizes is only WHICH COLUMN a cell is in. Godot signal connections survive a reparent, so
## a moved thumbnail keeps following the canvas it was already following.
##
## GUARDED ON THE SPLIT, because `_relayout` calls this on every flow and moving thirty-six
## thumbnails per flow is a freeze — the same lesson as the spacer fold, one surface over.
##
## `slot_w`/`slot_h` are passed in rather than read off the slot: `_relayout` is the caller
## that knows them, and by the time the slot's own rect reports them it is a frame stale, so
## the strip would lay out for the PREVIOUS window size on the flow that changed it.
func _distribute_strip(slot_w: float = -1.0, slot_h: float = -1.0) -> void:
	if _sequence_strip_rows.is_empty():
		return
	var sw: float = slot_w if slot_w > 0.0 else _sequence_life_slot.size.x
	var sh: float = slot_h if slot_h > 0.0 else _sequence_strip_scroll.size.y
	# A capacity of at least 1: a slot with no height yet (the first bind, before any flow)
	# must not resolve to "zero rows fit" and therefore `ceil(n/0)` columns.
	var capacity: int = maxi(1, int(floor(sh / maxf(1.0, SequenceThumbnail.SIDE))))
	var split: Dictionary = strip_columns(_sequence_strip_cells.size(), capacity,
		life_columns_affordable(sw))
	# THE BAND'S CEILING TRACKS THE WIDTH CONTINUOUSLY, above the split guard, because it is
	# cheap (a float, and `configure` is a no-op when nothing moved) while the reparenting
	# below is not. A resize that does not change the column count still changes what one
	# column can afford.
	var ceiling: float = life_band_ceiling(sw, int(split.get("cols", 1)))
	var ceiling_moved: bool = not is_equal_approx(ceiling, _life_band_ceiling)
	_life_band_ceiling = ceiling
	if split == _strip_split:
		# The columns are where they belong; only what they may take changed. Re-bind rather
		# than fall through, so the reparenting below stays behind its guard.
		if ceiling_moved:
			_bind_life_column()
		return
	_strip_split = split
	var cols: int = int(split["cols"])
	var per: int = int(split["per"])
	var colors: Array = _sequence_ribbon.colors() if _sequence_ribbon != null else []
	var live: bool = _sequence_life_column != null and _sequence_life_column.visible
	# DETACH EVERYTHING FIRST, IN ITS OWN PASS. Interleaving the remove and the add is a bug
	# that hides in plain sight: a cell moving from column 2 to column 0 is still parented to
	# column 2 when column 0 asks for it, so `add_child` refuses and that cell is simply
	# dropped from the strip — built, alive, holding its four canvas subscriptions, and not
	# on screen. Nothing looks broken; the sequence just has fewer frames than it has. Caught
	# by `EffectStudioColourColumnTest`'s "every one of them is in a column" count, which is
	# in the suite precisely because no picture-level assertion could see it.
	for vb0 in _sequence_strip_rows:
		for child in (vb0 as Control).get_children():
			(vb0 as Control).remove_child(child)
	for k in range(_sequence_strip_rows.size()):
		var vb: Control = _sequence_strip_rows[k]
		var lc = _sequence_life_columns[k]
		var pair: Control = _sequence_life_pairs[k]
		var lo: int = k * per
		var hi: int = mini(lo + per, _sequence_strip_cells.size())
		# A pair with nothing in it is HIDDEN, not left as an empty gap. It still exists —
		# nothing is built or freed here — so this costs a visibility flag and the column
		# count can go back up without a rebuild.
		pair.visible = k < cols and lo < hi
		for i in range(lo, hi):
			vb.add_child(_sequence_strip_cells[i])
		# THE RIBBON'S SLICE IS THE SAME SLICE, intersected with the life rows. The unreached
		# cells sort after every life row, so this is a prefix cut and the ribbon lines up
		# with the top of its column by construction rather than by an offset anyone has to
		# keep right.
		var rlo: int = mini(lo, _sequence_life_rows.size())
		var rhi: int = mini(hi, _sequence_life_rows.size())
		lc.configure(_sequence_life_rows.slice(rlo, rhi) if live else [], colors,
			SequenceThumbnail.SIDE, _life_band_ceiling)
		lc.set_keyframes(_colour_keyframes)
		lc.set_selected_frame(_colour_selected_frame)
		lc.visible = live


## Right-clicked a film-strip cell: select the colour keyframe at the life frame it lands on,
## or add one there. `frame` is `SequenceLifeMap`'s answer, resolved when the strip was built
## so a cell cannot disagree with its own tooltip.
##
## SELECT ONLY, never add — it used to be select-or-ADD, and that fell with the click-to-add
## rule on 2026-08-20 for the same reason: a right-click meant to look at a cell's colour
## permanently altered the curve. It selects the age; the ⬥ button is still the only thing
## that mints a keyframe, whichever surface you reached the age from.
func _on_strip_colour_requested(_cell_index: int, frame: int) -> void:
	if frame < 0:
		return
	_park_sequence_on(_cell_index)
	_on_colour_frame_selected(frame)


## Keep the parked cell inside the strip's viewport. Without this the strip is unusable on any
## real sequence: E019's longest is 35 opcodes against the `strip_rows` the slot shows, so the
## marked cell spends most of the loop out of view and the author is watching a static grid.
##
## VERTICAL now the flow wraps — the cell's row is what moves off-screen, not its column.
## Deferred one frame because the cells have no position until the flow lays out, and an offset
## computed against an unlaid-out row is zero.
func _scroll_strip_to_selection() -> void:
	if _sequence_strip_scroll == null or _sequence_canvas == null or _sequence_strip_row == null:
		return
	# A ROW INDEX, not the opcode index (ADR-0089 vertical-column amendment). The strip is
	# laid out by LIFE ROW now, so `child(selected_op())` is a different cell — and on a
	# looped animation the same opcode owns several rows. Scroll to its FIRST, which is the
	# earliest age it plays at; the rest are reachable by scrolling, and picking the first
	# is the one choice that does not jump backwards as the player advances through a loop.
	var op: int = int(_sequence_canvas.selected_op())
	var i: int = _strip_row_of_cell(op)
	if i < 0:
		return
	await get_tree().process_frame
	if not is_instance_valid(_sequence_strip_scroll):
		return
	# INDEX THE CELL LIST, not a column's children. Since the wrap, row i is the i-th cell of
	# the STRIP and only sometimes the i-th child of column 0 — reading `get_child(i)` would
	# quietly scroll to the wrong thumbnail on every emitter long enough to wrap, which is
	# every emitter this feature was built for.
	if i >= _sequence_strip_cells.size():
		return
	var cell: Control = _sequence_strip_cells[i]
	if cell == null or not is_instance_valid(cell):
		return
	# `global_position`, not `position`: a wrapped cell's y is relative to ITS column, and
	# the columns all start at the scroller's top, so the local y of row 20 in column 2 is
	# the local y of row 8. Only the global one answers "how far down the scroller is this".
	var view_h: float = _sequence_strip_scroll.size.y
	var top: float = cell.global_position.y - _sequence_strip_scroll.global_position.y \
		+ float(_sequence_strip_scroll.scroll_vertical)
	var target: float = top - (view_h - cell.size.y) * 0.5
	_sequence_strip_scroll.scroll_vertical = int(maxf(0.0, target))


## Which STRIP ROW shows trace cell `cell` — its first, when a loop gives it several. -1 when
## the cell has no row (the particle dies before reaching it) or nothing is bound.
##
## Reads `_sequence_life_rows`, the SAME projection the strip was built from, rather than
## re-deriving: the whole claim of this surface is that row i is thumbnail i, and a second
## walk is how that stops being true without anything looking wrong.
func _strip_row_of_cell(cell: int) -> int:
	if cell < 0 or _sequence_strip_row == null:
		return -1
	if _sequence_life_rows.is_empty():
		# Colour off — the strip fell back to one row per trace cell.
		return cell if cell < _sequence_strip_cells.size() else -1
	for i in range(_sequence_life_rows.size()):
		if int(_sequence_life_rows[i].get("cell", -1)) == cell:
			return i
	return -1


## Step the sequence player one opcode and park it there — the transport's twin of a
## thumbnail click, so both routes land in `select_op` and agree on what parked means.
func _park_sequence_on_step(delta: int) -> void:
	if _sequence_canvas != null:
		_sequence_canvas.step_op(delta)


## Show the sequence viewport while a target that names a SEQUENCE is open, and hide it
## otherwise — the same per-target show/hide shape `_update_frameset_canvas` uses. A
## focused opcode keeps the WHOLE sequence on screen with that opcode selected, because an
## opcode is only meaningful against the animation it sits in.
##
## THREE KINDS NAME A SEQUENCE, by two different routes (ADR-0100 dec. 1, amended
## 2026-08-19 — "I get a very tall pane with tons of empty space on the right"):
##
##   * an `animation` target names one DIRECTLY, index and lens both in its ref, and that
##     ref wins on this screen because the lens is part of the target's identity —
##     `animation(4, 0)` and `animation(4, 1)` are different targets and only the ref
##     knows which the author asked for;
##   * an `emitter`, or the particle `span` that fires one, names it THROUGH the emitter's
##     `anim_index`/`anim_param` (`EmitterSequenceSubject`). That is the screen the author
##     spends the most time in, and it left the column empty for want of an address rather
##     than for want of a reason: 512px of unclaimed width beside 2027px of fields that
##     have to scroll past a 268px row.
##
## The emitter screens are the ones that gain "the particle this emitter spawns, playing,
## while you edit its physics" — and ADR-0103 is what makes that worth more than a sprite
## preview, since the player and its ribbon are tinted by THIS emitter's own colour curves.
func _update_sequence_canvas(target: Dictionary) -> void:
	if _sequence_canvas == null or _sequence_panel == null:
		return
	# Dropped up front, so a target that never reaches the resolve below cannot leave the
	# PREVIOUS sequence's rung standing in the focus block's title, or its address standing
	# as what the thumbnails and the in-place refresh believe is bound.
	_sequence_provenance = {}
	var was_bound: Dictionary = _sequence_bound
	var was_texture: Texture2D = _sequence_bound_texture
	_sequence_bound = {}
	if _effect_data == null:
		_sequence_panel.visible = false
		_relayout()
		return
	var anim_idx: int = -1
	var group: int = 0
	# The emitter this column is ABOUT, or -1 on an animation target — where the emitter is
	# a ladder answer rather than a fact, and the ladder is `CellColour.provenance`'s job.
	var origin_ei: int = -1
	if Target.kind(target) == "animation":
		var ref: Dictionary = Target.ref(target)
		anim_idx = int(ref.get("index", -1))
		group = int(ref.get("group", 0))
	else:
		var subject: Dictionary = EmitterSubject.resolve(target, _effect_data,
			_timeline._score if _timeline else {})
		if not subject.is_empty():
			anim_idx = int(subject["anim_index"])
			group = int(subject["group"])
			origin_ei = int(subject["emitter_index"])
		else:
			# ADR-0130 dec. 10. A `frame`/`frameset` target has no emitter, but it does
			# have a frameset, and a frameset is what FRAME opcodes name — so "which
			# animation shows this?" is answerable, and is what the column now shows.
			var shown: Dictionary = _animation_showing_frameset(target)
			if not shown.is_empty():
				anim_idx = int(shown["anim_index"])
				group = int(shown["group"])
	if not (_effect_data.animations is Array) or anim_idx < 0 or anim_idx >= _effect_data.animations.size():
		_sequence_panel.visible = false
		_relayout()
		return
	var anim = _effect_data.animations[anim_idx]
	if not (anim is Dictionary):
		_sequence_panel.visible = false
		_relayout()
		return
	_sequence_bound = {"anim_index": anim_idx, "group": group}
	# `Target.title` of the equivalent animation target, NOT a second format string: the
	# lens has to be named when it shifts something (18 of 401 effects have more than one
	# group) and suppressed when it does not, and `_group_suffix` is the one rule for that.
	# It is also the answer to "which sequence does this emitter play" — which, on an
	# emitter screen, is exactly the fact the column is there to state.
	_sequence_canvas_title.text = Target.title(Target.animation(anim_idx, group))
	# RE-DECODE IN PLACE WHEN IT IS THE SAME SEQUENCE, because `bind_sequence` resets the
	# transport — `_tick = 0` and `_set_selected(-1)` — and `_render_current` runs this on
	# every edit. The author: "select the 3rd thumbnail, move the yellow box, it auto
	# selects the first thumbnail."
	#
	# `refresh_sequence` is the verb that already exists for exactly this and says so in its
	# own docstring: "the playhead stays where it is, the park stays parked... an author
	# lengthening a frame while watching the loop is not asking to be sent back to tick 0."
	# A UV drag is that same case — the opcode stream did not change, one frame's rect did —
	# and it also emits `decode_changed`, which is what tells the strip's thumbnails their
	# picture is stale. So the park survives AND the art updates, where a rebind gave the
	# opposite of both.
	#
	# The comparison is the ADDRESS plus the TEXTURE: a different effect can hold the same
	# (anim_index, group), and only `bind_sequence` re-derives the display texture.
	_sequence_bound_texture = _effect_data.texture
	var same_sequence: bool = (not was_bound.is_empty()
		and int(was_bound.get("anim_index", -1)) == anim_idx
		and int(was_bound.get("group", -1)) == group
		and was_texture == _effect_data.texture)
	if same_sequence:
		_sequence_canvas.refresh_sequence(anim, _sequence_group_offset({"group": group}))
	else:
		_sequence_canvas.bind_sequence(_effect_data.texture, _effect_data.framesets, anim,
			_sequence_group_offset({"group": group}))
	# ADR-0103 dec. 1/4: the strip and the player draw the REAL colour, and which emitter's
	# curves that is comes off the provenance ladder — resolved HERE because `_nav` is the
	# only thing that can tell a drilled sequence from a browsed one, and a strip's target
	# is a sequence seen through a lens, never an emitter.
	#
	# UNLESS THE TARGET IS ITSELF THE EMITTER, in which case there is no ladder to climb and
	# climbing one would be a bug waiting for a second emitter: the trail walk answers with
	# the last emitter ON IT, which for a particle `span` is whatever the author drilled
	# through earlier — or nothing. Named directly, `origin` is true by construction.
	_sequence_provenance = (CellColour.for_emitter(_effect_data, origin_ei) if origin_ei >= 0
		else CellColour.provenance(_nav, _effect_data, anim_idx, group))
	_sequence_canvas.bind_colour(_sequence_provenance.get("r"),
		_sequence_provenance.get("g"), _sequence_provenance.get("b"))
	_update_sequence_ribbon(anim_idx)
	_rebuild_sequence_strip()
	# Session state, re-pushed on every bind: `bind_sequence` re-binds per target and per
	# effect load, and a rate the author set once must not be reset by picking the next
	# sequence to look at.
	_sequence_canvas.set_speed(_sequence_speed)
	_sequence_panel.visible = true
	_relayout()


## Which animation to play on a `frame`/`frameset` screen, or `{}` when none can be named
## honestly (ADR-0130 dec. 10).
##
## Measured over all 401 effects, 17,423 framesets: **76.4% are referenced by exactly ONE
## animation**, 10.8% by none, and 12.8% by two or more. So the address is usually a fact,
## sometimes absent, and occasionally a choice — and each of those three gets its own
## answer rather than one guess wearing a confident label:
##
## * exactly one → bind it;
## * several → bind the LOWEST and let `_sequence_canvas_title` name which, so the author
##   can see they are looking at one of N rather than at "the" animation;
## * none → `{}`, and the column simply does not claim the row. An orphan frameset has no
##   animation, and inventing one would be the ADR-0100 defect: a real sequence, real
##   sprites, and nothing on screen saying it is the wrong one. The width goes back to the
##   inspector, which is what ADR-0100 says an unclaimed column should do.
##
## THE LENS IS NOT APPLIED HERE, deliberately. A trace cell's frameset is `op.frameset +
## group_offset`, and the offset comes from an EMITTER's `anim_param`; a frame target has no
## emitter, so there is no lens to read and the scan matches base indices at group 0. On the
## 18 effects with more than one group this can miss an animation that only reaches the
## frameset through a shifted lens — stated rather than hidden, because the fix is an
## emitter, and if you have one you came through `EmitterSubject.resolve` above instead.
func _animation_showing_frameset(target: Dictionary) -> Dictionary:
	if _effect_data == null or not (_effect_data.animations is Array):
		return {}
	var fs_idx := -1
	var ref: Dictionary = Target.ref(target)
	match Target.kind(target):
		"frame":
			fs_idx = int(ref.get("frameset_index", -1))
		"frameset":
			fs_idx = int(ref.get("index", -1))
	if fs_idx < 0:
		return {}
	var found: Array = []
	for ai in range(_effect_data.animations.size()):
		var anim = _effect_data.animations[ai]
		if not (anim is Dictionary):
			continue
		for op in anim.get("opcodes", []):
			if op is Dictionary and str(op.get("type", "")) == "FRAME" \
					and int(op.get("frameset", -1)) == fs_idx:
				found.append(ai)
				break
	if found.is_empty():
		return {}
	return {"anim_index": int(found[0]), "group": 0, "candidates": found.size()}


## Feed the sequence player's Colour ribbon from the rung the provenance ladder just fired
## (ADR-0103 dec. 4), so the bar under the player and the tint on the strip are the SAME
## emitter's curves by construction rather than by agreement.
##
## THE WINDOW IS THE ANIMATION'S BAKED DISPLAY LENGTH, not a lifetime guess.
## `get_animation_display_length` sums `maxi(1, (duration + 1) >> 1)` over the FRAME opcodes,
## which is exactly what `SequenceTimeline.total_ticks` sums over the same opcodes' trace
## cells — so the ribbon spans precisely the ages the film strip's cells tile, and a
## position along the bar maps to a row. (The page-wide `Fit W: all` toggle still wins, as
## it does for the emitter screen's ribbon: it is one control over every curve surface.)
##
## The `none` rung feeds three nulls, which the ribbon answers by drawing nothing — and
## the reserved slot is what keeps that from moving anything.
func _update_sequence_ribbon(anim_idx: int) -> void:
	if _sequence_ribbon == null or _sequence_life_slot == null:
		return
	var on: bool = _sequence_provenance.get("r") != null
	var ei: int = int(_sequence_provenance.get("emitter_index", -1))
	# THE WINDOW IS THE PARTICLE'S LIFE, not the animation's display length (ADR-0089
	# colour-move amendment, 2026-08-20). It used to be the latter, which was defensible
	# while this bar was a read-only companion to the film strip: the two shared an axis and
	# a position along the bar mapped to a row. The bar is now the EDITABLE surface, and an
	# editable axis has to be the one the renderer reads — `life_n`, the upper bound of what
	# a particle ever samples (CONTEXT.md *Colour dead zone*).
	#
	# The two are not interchangeable. Of 2622 colour-enabled corpus emitters they disagree
	# for 1204 (45.9%) and 698 differ by more than 8 frames, so the old window would not
	# have nudged a keyframe, it would have relocated it. (`LifeWindow`'s own rule was then
	# corrected on 2026-08-20 — it had been reading two fields the spawner never samples,
	# and drew up to 32 frames of phantom life on 309 emitters. The axis is unchanged; the
	# number it resolves to shrank for 309 and grew for 4.) What it costs is the strip's 1:1
	# alignment: the cells below no longer sit under their own colour for those 1204. That
	# is why the strip became an ENTRY POINT (`SequenceLifeMap`) instead of a ruler —
	# clicking a cell projects onto this axis rather than assuming it already matches.
	_sequence_colour_emitter = ei
	_sequence_colour_window = LifeWindow.resolve(_effect_data, ei)
	var window: int = int(_sequence_colour_window.get("n", -1))
	# The representative-sprite mux, the SAME one the emitter screen's ribbon applies, so
	# the two read alike: a sprite channel that is always 0 can never light up, whatever
	# the curve says (the E138 green case). White is the identity.
	var base: Color = EmitterSpriteColor.representative(_effect_data, ei) if on else Color.WHITE
	_sequence_ribbon.set_curves(_sequence_provenance.get("r"), _sequence_provenance.get("g"),
		_sequence_provenance.get("b"), on, window, true, base)
	_sequence_ribbon.visible = false   # headless — see its build comment
	# The rung IN FULL, on the one surface that cannot be dropped for want of column width.
	# The focus panel's title states it too, but that panel is conditional on slack. The
	# window's KIND is named as well now that the axis is authored on: "16 frames" alone does
	# not tell an author whether the number came from a lifetime they can edit or from the
	# animation's length, and those behave differently when they change something.
	_sequence_life_slot.tooltip_text = ("Colour over the particle's whole life%s.\n%s\n%s"
		% [" — %d frames" % window if window > 0 else "",
			str(_sequence_colour_window.get("note", "")),
			CellColour.title_suffix(_sequence_provenance).strip_edges().trim_prefix("· ")])
	_bind_colour_track(on, window)


## Build one opcode's thumbnail for the inspector SECTION that asked for it (#247).
##
## Fed from `_sequence_canvas`'s ALREADY-COMPUTED trace, bounds and display texture, not
## from a second decode. Three consequences, all of them the point:
##   * a section's picture and the animation playing beside it cannot disagree;
##   * every thumbnail in the sequence shares ONE bounds box, so a section whose opcode
##     only MOVED the sprite looks different from the one above it instead of re-centring
##     into a duplicate;
##   * the expensive `display_image` conversion stays one per texture, not one per section.
##
## Ordering is what makes that safe: `_update_sequence_canvas` runs BEFORE the inspector
## is fed on every nav update, so the canvas is already bound to this very sequence by
## the time a section asks. The animation_index guard is the belt for that brace —
## decline rather than draw a picture from a different sequence.
##
## It reads `_sequence_bound`, the address the canvas was actually bound to, and NOT the
## open target's ref. Those were the same number while only an `animation` target could
## open this column; since an `emitter` one can (ADR-0100 dec. 1 amended), a ref's `index`
## is an emitter index on two of the three kinds — and comparing a spec's `animation_index`
## against one would be a coincidence test, passing exactly when emitter N happens to play
## sequence N. Only `SequenceProjector` emits these specs, so the miscompare is currently
## unreachable; it is fixed here rather than left as a trap for the next projector.
##
## Clicking one PARKS the player on that opcode. The park runs straight into the canvas
## and touches nothing else — no navigation, so no inspector rebuild, so the folds and
## the scroll position the author set up survive being looked at.
func _sequence_thumbnail_for(spec: Dictionary) -> Control:
	if _sequence_canvas == null or not _sequence_panel.visible:
		return null
	if _sequence_bound.is_empty():
		return null
	if int(spec.get("animation_index", -1)) != int(_sequence_bound["anim_index"]):
		return null
	var i: int = int(spec.get("opcode_index", -1))
	var tr: Array = _sequence_canvas.get_trace()
	if i < 0 or i >= tr.size():
		return null
	var thumb = SequenceThumbnail.new()
	thumb.bind_state(tr[i], _sequence_canvas.get_framesets(),
		_sequence_canvas.get_bounds(), _sequence_canvas.get_display_texture())
	thumb.clicked.connect(func(): _park_sequence_on(i))
	# Both marks go live: yellow where the author parked, white under the running
	# playhead. The thumbnail subscribes ITSELF — see SequenceThumbnail.follow.
	thumb.follow(_sequence_canvas, i)
	return thumb


## THE UNIFIED ANIMATION SCREEN (ADR-0102): show the selected opcode's frameset — and every
## member frame — in the focus panel above the film strip, so the whole chain
## `opcode → frameset → frame` is authorable on one screen instead of three.
##
## Composed HERE rather than inside `SequenceProjector` because the block's subject is the
## SELECTED opcode, which is live UI state (`SequenceCanvas._selected_op`) and reaches no
## projector: a projector is a pure function of `(target, effect_data, score)` and must
## stay one.
##
## THE PANEL'S SLOT IS RESERVED, not conditional — it is up for every `animation` target,
## including one parked on a SET_OFFSET or a LOOP. That is the answer to "should there even
## be a frameset section when the opcode has no frameset parameter": there is no longer a
## SECTION, and for a spriteless opcode the block is a single title line with no rows under
## it. Reserving the slot is what keeps the promise the panel exists to keep — hiding it
## would hand its height back to the strip and slide every thumbnail, which is the exact
## movement the author asked to stop, just on a different click.
func _update_focus_panel(target: Dictionary) -> void:
	if _focus_panel == null or _focus_inspector == null:
		return
	var block := {}
	# THE BLOCK FOLLOWS THE PLAYER, not the open target (2026-08-19). It used to be gated on
	# `kind == "animation"`, which was the same thing while only an animation target could
	# open the column — but an `emitter` or particle `span` binds the player too now
	# (ADR-0100 dec. 1, amended), and on those screens the author was looking at a running
	# sequence with no frameset controls under it at all. "I don't see any frameset controls
	# here — did I miss something?"
	#
	# It is fed `_sequence_bound`, the address the canvas was actually bound to, NEVER the
	# open target's ref: `FocusBlock.section` reads `ref.index` as an animation index and
	# `ref.group` as the lens, and on an emitter target `ref.index` is an emitter index. That
	# is the same landmine `_sequence_thumbnail_for` and `_refresh_sequence_preview` carry a
	# comment about, and it is silent — the block would name and EDIT a real frameset from an
	# unrelated sequence. Synthesizing the equivalent `animation` address keeps FocusBlock a
	# pure function of (sequence, lens, opcode), which is what its subject actually is.
	var subject: Dictionary = target
	if not _sequence_bound.is_empty() and _sequence_canvas != null:
		var score: Dictionary = _timeline._score if _timeline else {}
		subject = Target.animation(int(_sequence_bound["anim_index"]),
			int(_sequence_bound["group"]))
		block = FocusBlock.section(subject, _effect_data, score, _focus_op_index(),
			_sequence_provenance)
	if block.is_empty():
		if _focus_wanted:
			_focus_wanted = false
			_focus_panel.visible = false
			_focus_inspector.clear()
			_relayout()
		return
	var was_wanted: bool = _focus_wanted
	_focus_wanted = true
	# `subject`, not `target`: the panel states what it is SHOWING, which is a sequence seen
	# through a lens, and on an emitter screen the open target is the emitter. Identical on an
	# animation screen, where the two are the same address by construction.
	_focus_inspector.show_target(subject, [], [block], _curve_samples, _open_param_curve,
		_navigate_to, _child_edge_suppressed, _set_child_edge_suppressed, _apply_edit,
		_pick_target, _hide_inert, {}, _run_action)
	# Only when the panel APPEARS: its rect is a function of the row, not of its content, so
	# a retarget has nothing to re-flow. Arriving does — the two columns beside it move.
	if not was_wanted:
		_relayout()


## Which opcode the block is ABOUT — the parked selection, or, when nothing is parked, the
## opcode under the PLAYHEAD. A freshly opened sequence has no selection (a click on the
## film strip is what makes one), and a block reading "opcode -1" while a sprite is plainly
## drawn beside it is a worse answer than naming the sprite that is drawn. The retarget
## still fires on `selection_changed` only, so this is the OPENING subject and a click takes
## over from there — the block never chases a running playhead.
func _focus_op_index() -> int:
	if _sequence_canvas == null:
		return -1
	var selected: int = _sequence_canvas.selected_op()
	return selected if selected >= 0 else _sequence_canvas.playhead_op()


## The film strip moved: retarget the block to the newly selected opcode.
##
## THE FOCUS PANEL ONLY, never `_render_current()`. A full render `queue_free`s the widgets
## it rebuilds — including a ScrubField the author is dragging, which then dies after one
## pixel (`87c081b7b`) — and would also throw away every fold the author had opened in the
## strip and the strip's scroll position, which is the whole reason a thumbnail PARKS
## rather than navigating (ADR-0100 dec. 7). Since the block moved to a panel of its own
## this is a plain `show_target` on that panel: one section, ~34 rows, and the strip beside
## it is not touched at all — a stronger guarantee than the in-place section rebuild this
## used to need, and the reason `EffectKeyframeInspector.rebuild_section` is gone.
##
func _on_sequence_selection_changed(_op_index: int) -> void:
	_retarget_sequence_focus()
	# …and the TEXTURE TAB, which was the half of this that dec. 4c promised and never got.
	_resync_texture_tab_to_playhead()
	# …and slide the strip so the newly-parked cell is visible. The thumbnails repaint their
	# own marks (they each subscribe to the canvas); only the SCROLL is the host's business.
	_scroll_strip_to_selection()


## Keep the Texture tab on the frameset the PLAYER is actually showing (ADR-0130 dec. 4c).
##
## Dec. 4c said "scrubbing the sequence walks the outlines around the sheet" and nothing
## wired it. The tab read `_shown_frameset()` exactly once, inside `_render_current`, and
## parking on an opcode does not render — `_on_sequence_selection_changed` re-derived the
## focus block and stopped there. So the tab kept whatever frameset the target was opened
## on while the player walked away from it.
##
## Measured on E317 `particle:for_each:1#2`, the author's own screen: its cells are
## framesets 15, 15, 16, 22, 22, 22, and parking on op 3 left the tab drawing frameset 15's
## rect `(56,8,32,32)` while the player showed frameset 22's `(8,40,40,40)`. That is the
## ADR-0100 defect exactly — a real rect, a real box, nothing on screen saying it is the
## wrong one — and dec. 12 made it worse than a mislabel, because the author can now DRAG
## it and edit a frameset they are not looking at.
##
## RE-BINDS ONLY WHEN THE FRAMESET CHANGES, not once per opcode. `bind_sheet` rebuilds the
## ADR-0098 dec. 5 coverage mask, which is a whole-sheet pass, and this fires on every
## opcode transition while the player runs; E317's 15-cell span would otherwise rebuild it
## fifteen times a loop to show the same picture twice.
func _resync_texture_tab_to_playhead() -> void:
	if _texture_panel == null or not _texture_panel.visible or _nav.is_empty():
		return
	# A `frame` or `frameset` target NAMES its frameset and must keep it whatever the player
	# is doing — the playhead is not the subject there, the target is.
	var kind: String = Target.kind(_nav.back())
	if kind == "frame" or kind == "frameset":
		return
	var fs: int = _shown_frameset()
	if fs == _texture_panel.bound_frameset():
		return
	_texture_panel.set_strip_framesets(_strip_framesets())
	_texture_panel.bind_sheet(_effect_data, fs, -1)


## Rebuild the focus block alone, from whatever opcode it is now about — the one place the
## block is re-derived outside a full render.
func _retarget_sequence_focus() -> void:
	if _sequence_canvas == null or _nav.is_empty():
		return
	_update_focus_panel(_nav.back())


## Park the player on one opcode and repaint the marks. Called by a thumbnail click and
## by the transport's step buttons, so both routes agree on what "parked" means.
func _park_sequence_on(op_index: int) -> void:
	if _sequence_canvas == null:
		return
	_sequence_canvas.select_op(op_index)


## A FRAME opcode's frameset index is RELATIVE to the frameset GROUP the playing
## emitter selects, so the viewport needs the group's offset to draw the right sprite
## (18 of 401 corpus effects have more than one group). `EffectData.frameset_group_offset`
## is the ONE derivation of that number and its docstring asks callers not to make
## another copy — so this resolves through it and never recomputes the cumulative sum.
##
## Guarded by `has_method` because the group lens is landing on this branch
## separately: until it does, a ref carries no `group`, group 0's offset is always 0,
## and "no shift" is the correct answer for all 383 single-group effects anyway.
func _sequence_group_offset(ref: Dictionary) -> int:
	var group: int = int(ref.get("group", 0))
	if _effect_data != null and _effect_data.has_method("frameset_group_offset"):
		return int(_effect_data.frameset_group_offset(group))
	return 0


## How much vertical space the canvas panel's chrome takes: the title, the hover readout,
## the region scope control, and the PanelContainer's own padding. MEASURED from the
## canvas's siblings rather than assumed, because the constant it replaces ("title label +
## padding = 40") was invalidated the first time the panel gained a row, and would be again.
## No circularity — none of the siblings' minimum heights depend on the canvas.
func _canvas_chrome_h(canvas = null) -> float:
	if canvas == null:
		canvas = _frameset_canvas
	if canvas == null:
		return _CANVAS_CHROME_PAD_H
	# IT WALKS UP, not just one level (ADR-0089 vertical-column amendment). The sequence
	# panel's body is a ROW now — the player's square and the life column side by side —
	# so the canvas's immediate parent is an HBox whose sibling costs WIDTH, not height,
	# while the title and transport that DO cost height are one level further up. A
	# single-level walk measured the wrong container and reported the life column's whole
	# height as chrome, which starved the canvas to nothing.
	#
	# The rule per level is the container's own axis: a VBox's other children stack, so
	# their heights add; an HBox's do not. Everything else contributes nothing.
	var h: float = _CANVAS_CHROME_PAD_H
	var node: Control = canvas
	var parent = node.get_parent()
	while parent is BoxContainer:
		if parent is VBoxContainer:
			var siblings: int = 0
			for child in (parent as BoxContainer).get_children():
				if child == node or not (child is Control) or not (child as Control).visible:
					continue
				h += (child as Control).get_combined_minimum_size().y
				siblings += 1
			if siblings > 0:
				h += float(siblings) * float((parent as BoxContainer).get_theme_constant("separation"))
		node = parent as Control
		parent = node.get_parent()
	return h


## How WIDE the canvas panel's chrome insists on being: the widest of the panel's
## non-canvas children plus the PanelContainer's own left/right padding. The exact peer of
## `_canvas_chrome_h` above, MEASURED per occupant for the same reason — the sequence panel
## carries a transport row (202px) and the frameset panel a hover readout and the region
## scope, so a shared constant would be wrong for one of them, and a stale constant is what
## retired the chrome-height constant this pattern replaced.
func _canvas_floor_w(canvas = null) -> float:
	if canvas == null:
		return 0.0
	# The exact peer of `_canvas_chrome_h`'s walk, with the axes swapped: an HBox's other
	# children sit BESIDE the canvas so their widths ADD, a VBox's sit above and below so
	# only the widest of them can bind. The life column is in the first category — it is
	# the reason this had to grow a walk at all, and it is the term that keeps the player's
	# square from being sized as though the column were not there.
	var w: float = 0.0
	var node: Control = canvas
	var parent = node.get_parent()
	while parent is BoxContainer:
		var level: float = 0.0
		for child in (parent as BoxContainer).get_children():
			if child == node or not (child is Control) or not (child as Control).visible:
				continue
			var cw: float = (child as Control).get_combined_minimum_size().x
			if parent is HBoxContainer:
				level += cw + float((parent as BoxContainer).get_theme_constant("separation"))
			else:
				level = maxf(level, cw)
		w = maxf(w, level) if parent is VBoxContainer else w + level
		node = parent as Control
		parent = node.get_parent()
	return w + _CANVAS_CHROME_W


## The right column's WIDTH, given the row's width, the height the canvas itself gets
## (the row minus the panel's measured chrome) and the inspector's DECLARED content
## width. Pure/static for the same reason `_row_right_edge` below is: the invariant it
## carries has to be testable at window sizes where the terms actually contend, which
## the developer's 1261x688 dashboard is not — there the square is 218 against 556 of
## room, so a broken clamp measures clean.
##
## Square by construction: the row's height is the binding dimension (it is capped by
## the timeline below), so an equal width is the largest the canvas can be without
## letterboxing its own area — capped at half the row so the content column beside it
## never collapses.
##
## Then, and this is the load-bearing term, NEVER past what the inspector's declared
## content leaves. A container cannot shrink below its minimum, so a column that takes
## more than the leftover does not narrow the inspector: it lands ON it by the
## difference. That is exactly how the column was lost the first time (108px of overlap,
## `0306ae37c`). Clamping here makes the overlap unrepresentable rather than an
## empirical question re-answered per layout test — the frameset occupant was only
## ACCIDENTALLY safe before, at 457 declared against 621 of room.
## The inspector ROW's height: its content, floored at whatever the right-hand column needs
## and capped by the `budget` that reserves MIN_CHANNELS_H of lanes below.
##
## `column_floor_h` is `_CANVAS_SIDE + <the panel's measured chrome>` when the row carries a
## column and 0 when it does not, so the row is never shorter than the box it holds — and
## never TALLER than its own content just because it holds one. That second half is the
## correction to this amendment's first attempt, which gave a column-bearing row the whole
## budget: it did make the box stop resizing, but only by making it a function of the WINDOW
## instead, and on a tall one the box grew to half the row and starved the focus column
## beside it out of existence (the author photographed a sequence page with no block on it).
## The box is a CONSTANT now — see `_CANVAS_SIDE` — so the row does not have to be one.
##
## Pure/static so it is assertable at any window; at the dev body the budget is 268 against
## 1723 of content, so nothing here contends and a live measurement sees nothing.
static func inspector_row_height(natural_h: float, budget: float, panel_h: float,
		column_floor_h: float) -> float:
	var room: float = maxf(0.0, budget - panel_h)
	return clampf(maxf(natural_h, column_floor_h), 0.0, room)


## How TALL the focus block is: the column's SLACK under the player, once the player's box
## has the constant height it may not give up.
##
## This replaces `focus_column_width`, and it is the same rule turned ninety degrees. The
## block used to be the MIDDLE COLUMN, between the inspector and the player, claiming the
## row's leftover WIDTH. It is now stacked UNDER the player in the player's own column
## (ADR-0100 dec. 1, amended 2026-08-19) — so the width it held goes back to the inspector,
## which on the animation screen was pinned at 450 of a 1241px body while its opcode rows
## wanted more.
##
## THE SLACK IS TAKEN FROM THE COLUMN, NEVER FROM THE PLAYER, and that ordering is the whole
## of ADR-0100 dec. 2's amendment: the box is a CONSTANT. A rule that shrank the player to
## make room here would make the box a function of whether the open target happens to carry a
## frameset block — which is precisely the "the animation box is changing in size all the
## time as clicking through keyframes" complaint that made it a constant in the first place.
##
## Returns 0 below `_FOCUS_COLLAPSE_H`, which is also the signal to hide the panel. That is a
## real consequence and not a rounding case: the player's box is `_CANVAS_SIDE` plus ~188 of
## measured chrome, so a row under roughly 510px has no slack to give and the block does not
## appear at all. Pure/static so that threshold is assertable at any window, which the dev
## dashboard cannot express — there the row is 268 and the answer is always 0.
static func focus_stack_height(row_h: float, box_h: float, want_h: float = 0.0) -> float:
	var slack: float = row_h - box_h - _FOCUS_GUTTER
	if slack < _FOCUS_COLLAPSE_H:
		return 0.0
	# Never TALLER than the block's own declared content, for the reason the width rule had
	# the same clamp: on a tall window the surplus belongs to the surface that can use it,
	# and a name/value grid stretched down half a screen is not that surface.
	return minf(slack, maxf(_FOCUS_MIN_H, want_h))


static func column_width(row_w: float, canvas_h: float, content_w: float) -> float:
	var want: float = clampf(canvas_h + _CANVAS_CHROME_W,
		_CANVAS_MIN_SIDE, maxf(_CANVAS_MIN_SIDE, row_w * 0.5))
	return maxf(0.0, minf(minf(want, row_w), row_w - content_w - _CANVAS_GUTTER))


## The rightmost rendered edge (global X) across `row`'s visible Control children.
## Pure/static so the layout invariant is testable without a live page — see
## EffectStudioSequenceBrowserTest's regression case for why this must not read any
## single named control.
static func transport_right_edge(row: Control) -> float:
	var edge: float = 0.0
	if row == null:
		return edge
	for child in row.get_children():
		if child is Control and (child as Control).is_visible_in_tree():
			var gr: Rect2 = (child as Control).get_global_rect()
			edge = maxf(edge, gr.position.x + gr.size.x)
	return edge


## Commit a drag gesture on the frameset canvas (#279/ADR-0099): the canvas emits ONCE on
## mouse-release with the final `{x,y,width,height}`, and this lands as ONE compound edit —
## one undo entry per gesture, mirroring the sound stay-local trade's
## `studio_apply_compound` shape — then re-renders so the inspector's spinboxes and the
## canvas overlay both reflect the committed value.
##
## THE UNIT OF THE EDIT IS THE REGION, NOT THE FRAME (ADR-0099 dec. 5). This used to write
## four uv fields on the one dragged frame; a UV rect is shared, so on E019 that was one of
## thirty identical drags the author had to remember to repeat, and missing one left a frame
## pointing at the old art with no diagnostic anywhere. The scope control decides how many
## members go with it, and says so before the drag starts.
##
## Two things are asked BEFORE the write, both of which are silent failures otherwise:
##
##   - Can every member STORE the block (dec. 4a)? The encodable range of uv.width/height is
##     per-frame and per-AXIS, decided by a flag bit `frames.json` does not carry, and outside
##     it the writer's mask ALIASES rather than failing — E027 stores a region at width -128,
##     and -136 comes back as +120 with the flip lost. Refused rather than written.
##   - Does the block land on a NEIGHBOURING region, merging the two? Blocks frequently share
##     an origin (E173 stores one beam at five lengths off (56,48)), so this is routine, and
##     the merge is otherwise only visible three framesets later.
func _on_frameset_uv_changed(new_uv: Dictionary) -> void:
	if _nav.is_empty():
		return
	var target: Dictionary = _nav.back()
	if Target.kind(target) != "frame":
		return
	var ref: Dictionary = Target.ref(target)
	var fs_idx := int(ref.get("frameset_index", -1))
	var fr_idx := int(ref.get("frame_index", -1))
	if _effect_data == null or not (_effect_data.framesets is Array):
		return

	var block: Rect2i = FramesetCanvas.normalised_block(new_uv)
	var members: Array = _region_members_for_drag(fs_idx, fr_idx)
	if members.is_empty():
		return

	var verdict: Dictionary = FramesetCanvas.region_write_verdict(
		_effect_data.framesets, members, block)
	if not verdict.get("ok", false):
		# Refusing is the honest outcome: the alternative is a byte that aliases to a
		# different rect on the next load. The canvas re-renders from the UNCHANGED data,
		# so the box snaps back to where it was.
		_set_status(String(verdict.get("message", "that block cannot be stored")))
		_render_current()
		return

	var compound: Array = FramesetCanvas.region_edits(_effect_data.framesets, members, block)
	if compound.is_empty():
		return   # the gesture landed where it started — not an undo entry to press through
	if _host and _host.has_method("studio_apply_compound"):
		_host.studio_apply_compound(compound)

	var merge: Dictionary = FramesetCanvas.region_merge_preview(
		_effect_data.framesets, members, block)
	_set_status(_region_commit_status(members, fs_idx, merge))
	if _region_scope != null:
		_region_scope.bind(_effect_data.framesets, fs_idx, fr_idx)
	_render_current()


## Which frames the drag moves: whatever the scope control has selected, falling back to
## the dragged frame's whole region if the panel is not up yet. Never falls back to the
## single frame — that would quietly restore the pre-ADR-0099 behaviour under a UI that
## says otherwise.
func _region_members_for_drag(fs_idx: int, fr_idx: int) -> Array:
	if _region_scope != null:
		var picked: Array = _region_scope.selected_members()
		if not picked.is_empty():
			return picked
	return FramesetCanvas.region_members(_effect_data.framesets,
		FramesetCanvas.region_of(_effect_data.framesets, fs_idx, fr_idx))


## What the author is told after a region edit lands. Pure — the merge case is the one
## worth reading twice, so it is stated rather than left to be discovered downstream.
## What the status bar says after a region drag commits.
##
## NAMES THE FRAMESETS THE EDIT REACHED THAT ARE NOT THE ONE ON SCREEN, and that is the
## whole point of the amendment. The author moved a box on E317 emitter 6 and reported:
## *"only thumbnail 1 changed. I thought the change was effect wide?"* It was — six frames
## moved (framesets 15, 17, 18, 19, 20, 21) — but that emitter's sequence only ever plays
## framesets 15, 16 and 22, so five of the six were edited in framesets the strip beside
## the canvas cannot show. "Moved 6 frames" is true and still leaves the author counting
## thumbnails to check it, which is the wrong instrument.
##
## 81.4% of corpus regions have members in more than one frameset, so this is the ordinary
## case and not an edge one. Pure, so the sentence is assertable without a window.
static func _region_commit_status(members: Array, here_frameset: int,
		merge: Dictionary) -> String:
	var moved: int = members.size()
	var head := "Moved %d frame%s" % [moved, "" if moved == 1 else "s"]
	var elsewhere: Array = []
	var n_elsewhere := 0
	for m in members:
		var fi: int = int(m.get("frameset_index", -1))
		if fi == here_frameset or fi < 0:
			continue
		n_elsewhere += 1
		if not elsewhere.has(fi):
			elsewhere.append(fi)
	if n_elsewhere > 0 and here_frameset >= 0:
		elsewhere.sort()
		var names: Array = []
		for fi in elsewhere:
			names.append(str(fi))
		head += " — %d in frameset%s %s, which this view does not show" % [
			n_elsewhere, "" if elsewhere.size() == 1 else "s", ", ".join(names)]
	if bool(merge.get("merges", false)):
		return "%s — %s" % [head, String(merge.get("message", ""))]
	return head


## Render the per-texel readout ADR-0098 dec. 6 specified, from the only component that can
## answer honestly about it.
func _on_frameset_hover(hover: Dictionary) -> void:
	if _frameset_readout == null:
		return
	if not bool(hover.get("inside", false)):
		_frameset_readout.text = "—"
		return
	_frameset_readout.text = "texel %d, %d  ·  %d%%" % [
		int(hover.get("x", 0)), int(hover.get("y", 0)),
		roundi(float(hover.get("scale", 1.0)) * 100.0)]

## The vertical contention between the inspector and the FEDS pair panel, pure so it can be
## guarded without a scene. Space above the channel strip (which never shrinks below
## MIN_CHANNELS_H) is the budget. The pair panel shows WHOLE — its full content height,
## energy bands and all, no internal scroll when the window can hold it — ceding only what
## the inspector's own content needs above it. When the two together overflow the budget they
## contend, and the panel keeps at least half so neither surface disappears in a short window.
static func _editor_band(h: float, natural_h: float, panel_want: float,
		panel_visible: bool) -> Dictionary:
	var budget: float = maxf(0.0, h - MIN_CHANNELS_H - FramesBar.BAR_H)
	if not panel_visible:
		return {"editor_h": clampf(natural_h, 0.0, budget), "panel_h": 0.0}
	var editor_want: float = clampf(natural_h, 0.0, budget)
	var panel_h: float = minf(panel_want, maxf(0.0, budget - editor_want))
	var panel_floor: float = minf(panel_want, budget * 0.5)
	if panel_h < panel_floor:
		panel_h = panel_floor
	return {"editor_h": clampf(natural_h, 0.0, maxf(0.0, budget - panel_h)), "panel_h": panel_h}


## High-water height for the currently open ROOT target. `latch` is {key, h}, mutated in
## place. A new key starts over, so the mark is bounded by what ONE root actually needed and
## a tall target cannot leave a permanent gap behind it; within a root the height only ever
## grows, which is what stops a click from re-flowing the band. An empty key (nothing open)
## tracks the content exactly, so a cleared inspector still collapses to nothing.
static func _latched_editor_h(latch: Dictionary, key: String, natural_h: float) -> float:
	if str(latch.get("key", "")) != key:
		latch["key"] = key
		latch["h"] = 0.0
	if key == "":
		latch["h"] = natural_h
		return natural_h
	latch["h"] = maxf(float(latch.get("h", 0.0)), natural_h)
	return float(latch["h"])


## The author EXPLICITLY collapsed or expanded a section. `_latched_editor_h` is a
## high-water mark per open root, built by the 2026-08-20 amendment so a REBUILD transient
## could not re-flow the band while the author was only reading. A deliberate collapse is
## the opposite kind of event: without dropping the mark, expanding then collapsing the
## Container section would leave a permanent gap under the inspector for that root
## (ADR-0085 amendment 2026-08-21, decision 5). Clearing the whole latch is enough — the
## next `_relayout` re-keys it from the current root and starts the mark over at the
## content height the author just chose.
func _on_inspector_fold_toggled() -> void:
	_editor_latch.clear()
	_relayout()


## Identity of a target for the latch: kind plus ref — the same two fields `Target.equals`
## compares, so "the same root" here means the same root there.
static func _target_key(target: Dictionary) -> String:
	return "%s|%s" % [Target.kind(target), str(Target.ref(target))]


## Position the three stacked body children (inspector → frames bar → channel list) and
## re-scroll the channel list so the visible lanes don't move when the inspector resizes.
## The inspector (and, when open, the FEDS pair lane panel) resize to their content but
## together never past the `budget` that keeps a MIN_CHANNELS_H timeline strip below the
## ruler — the pair panel takes its full content first, beyond which they scroll internally.
## The channel list fills to the body's bottom (no gap) and scrolls internally, so every
## lane stays reachable. As the inspector grows by Δ it slides the channel viewport's top
## down by Δ; we add Δ to the channel scroll (bottom-anchored) so the lanes you can see
## stay pinned and the inspector grows over the TOP lanes. Called on body resize and
## whenever the inspector's content changes (content_changed).
func _relayout() -> void:
	if _body == null or _inspector == null or _frames_bar == null or _scroll == null:
		return
	var w: float = _body.size.x
	var h: float = _body.size.y
	if w <= 0.0 or h <= 0.0:
		return
	# The top panel's height is a property of the OPEN TARGET, not of the last click
	# (ADR-0085 amendment 2026-08-20). On a roomy window the band arithmetic lands
	# `editor_h` exactly on `natural_h`, so without the latch the inspector's height IS its
	# content height — and since every click on an opcode re-navigates to the pair root and
	# rebuilds the inspector, each click re-ran this and re-flowed the panel and every lane
	# below it. Content height is stable WITHIN one pair but moves 327..355 px across opcode
	# kinds and pairs, and a rebuild passes through smaller intermediate heights on its way
	# back, so the band jumped while the author was only reading.
	var natural_h: float = _latched_editor_h(_editor_latch,
			"" if _nav.is_empty() else _target_key(_nav[0]), _inspector.content_height())
	# The PATH BAR is the row above everything, and it takes its BAR_H off the top of the
	# body before any of the rest is shared out — so the inspector, the right column, the
	# pair band, the frames bar and the channel scroll all shift down by it, and the
	# `budget` below still reserves the same MIN_CHANNELS_H of lanes. It is constant
	# chrome (visible whenever an effect is loaded, empty inspection included), so nothing
	# below re-flows when the drill depth changes — the whole point of the ruling.
	# `bar_height()`, not the BAR_H constant: a Container cannot shrink below its combined
	# minimum, so the constant is a FLOOR the bar's own font/padding can exceed — reserving
	# the constant would put the bar on top of the inspector by the difference.
	var bar_h: float = _path_bar.bar_height() if (_path_bar != null and _path_bar.visible) else 0.0
	# The FEDS pair lane panel (when open) takes its content height as a band between
	# the inspector and the frames bar; the frames bar stays glued directly above the
	# lanes it rules. Space above the channel strip (which never shrinks below
	# MIN_CHANNELS_H) is shared by the inspector and the panel.
	var budget: float = maxf(0.0, h - bar_h - MIN_CHANNELS_H - FramesBar.BAR_H)
	var panel_h: float = 0.0
	var editor_h: float = 0.0
	if _pair_panel and _pair_panel.visible:
		# Show the pair panel WHOLE: it takes its FULL content height (energy bars and
		# all — no internal scroll when the window can hold it), ceding only what the
		# inspector's own content needs above it. When both together overflow the
		# budget they contend, and the panel keeps at least half so neither surface
		# disappears in a short window.
		var panel_want: float = _pair_panel.custom_minimum_size.y
		var editor_want: float = clampf(natural_h, 0.0, budget)
		panel_h = minf(panel_want, maxf(0.0, budget - editor_want))
		var panel_floor: float = minf(panel_want, budget * 0.5)
		if panel_h < panel_floor:
			panel_h = panel_floor
	# THE INSPECTOR ROW'S RIGHT COLUMN — ONE slot, two possible occupants, chosen by
	# target kind (ADR-0100). A `frame` target parks the frameset sheet there; an
	# `animation` target parks the sequence player. They are mutually exclusive by
	# construction (`_update_frameset_canvas` / `_update_sequence_canvas` show one and
	# hide the other), so the slot is never contended.
	#
	# The sequence player used to take a full-width BAND under the inspector instead,
	# for two reasons that have both since expired (see ADR-0100):
	#   * "a film strip is a RIBBON, the frameset canvas wants a SQUARE" — the strip left
	#     this panel; what remains is one assembled sprite, which wants a square too;
	#   * "there is no room beside a sequence inspector" — its per-opcode LINK rows put
	#     its minimum at 1068px of a 1241px body, and a Container cannot shrink below its
	#     minimum, so the column overlapped it by 108px. Those rows are deleted; the
	#     declared width is 677.
	var column_panel: PanelContainer = null
	var column_canvas = null
	if _frameset_panel != null and _frameset_panel.visible:
		column_panel = _frameset_panel
		column_canvas = _frameset_canvas
	elif _sequence_panel != null and _sequence_panel.visible:
		column_panel = _sequence_panel
		column_canvas = _sequence_canvas
	# The frameset canvas is the row's RIGHT area (#278/#279). It only ever takes height
	# the inspector row already has, so `budget` — which reserves MIN_CHANNELS_H of lanes
	# — bounds it too: bleeding into the timeline is now unrepresentable, where the old
	# page-relative rect could (and did) overrun it by 388px. The row grows to the canvas's
	# floor when the frame's own fields are shorter than that, never past the budget.
	# MEASURED per occupant, never shared: the frameset panel stacks a hover readout and
	# the region scope under its canvas (105px) and the sequence panel a transport row
	# (88px), so a single number would make one of them un-square.
	var chrome_h: float = _canvas_chrome_h(column_canvas)
	# THE BOX IS A CONSTANT, and the row is floored at it rather than derived from it.
	var box_h: float = (_CANVAS_SIDE + chrome_h) if column_panel != null else 0.0
	editor_h = inspector_row_height(natural_h, budget, panel_h, box_h)
	# …and clamped BACK to the row when the window is too short to hold the box whole. This
	# is the one case where the box is not its declared size, and it is unavoidable: a
	# container cannot be given more height than the band above the timeline has.
	var box_shown_h: float = minf(box_h, editor_h)
	var canvas_w: float = 0.0
	if column_panel != null:
		# ADR-0100 dec. 2 AMENDED: the box is a CONSTANT square (`_CANVAS_SIDE`), not a
		# square derived from the row.
		#
		# Dec. 2 made the canvas square off the row's height and the row's height off
		# `content_height()`, so the box was a function of whatever target was open and of
		# its FOLD STATE (`content_height` reads a container minimum, and Godot's container
		# minimums skip invisible children, so opening one section grew it): on a frame
		# target at a 600px budget, 400px of fields make a 311px box and one fold makes it
		# 411. "It should have fixed dimensions."
		#
		# The first attempt at that kept the derivation and changed the term — the row took
		# the whole budget, making the box a function of the WINDOW instead. It did stop
		# resizing per click; on a tall window it also grew to half the row, took every
		# pixel of the width the focus column is claimed from, and the author photographed a
		# sequence page with no block on it at all. A derivation with a moving term is what
		# the requirement was refusing, so the fix is not a better term — it is a constant.
		#
		# One residue, stated rather than hidden: the chrome is MEASURED per occupant (the
		# sequence panel's transport is 88px, the frameset panel's readout and scope 105),
		# so the two panels differ by 17px in height. They are never on screen together and
		# each is constant for its own screen; the canvas inside them is the same square.
		# `column_width` still owns the no-overlap clamp, and it is still pure — only the
		# height it is handed is now the constant rather than the row's.
		#
		# `content_width()`, not `get_combined_minimum_size().x`: a collapsed section's
		# body is invisible and Godot's container minimum skips invisible children, so
		# the live minimum swings with fold state and the column would resize every time
		# a section was opened. Same class of problem `content_height()` exists to solve.
		canvas_w = column_width(w, _CANVAS_SIDE, _inspector.content_width())
		# …but never NARROWER than the panel's own irreducible minimum. `column_width`'s
		# floor is `_CANVAS_MIN_SIDE` (180), which is a floor for the CANVAS; the panel
		# around it also carries chrome that has a width of its own — the sequence panel's
		# transport row (⏮ op / op ⏭ / speed) measures 202. A Container cannot shrink below
		# its minimum, so assigning less does not narrow the panel: it makes the panel
		# overhang the rect by the difference and land on the inspector — the exact failure
		# ADR-0100 dec. 2 exists to make unrepresentable, in the one direction that clamp
		# did not cover. The frameset occupant was only ACCIDENTALLY safe (its chrome is
		# narrower than 180); the sequence occupant is 6px over at the dev body height, and
		# was pushed there by the path bar taking its row off the same budget.
		#
		canvas_w = maxf(canvas_w, _canvas_floor_w(column_canvas))
		# …and WIDER STILL when the column has a second occupant with a bigger appetite.
		# The stacked frameset block declares 710px of rows (eight vertex spinboxes and a
		# sheet-region link) against the player's 276, so a column sized for the player alone
		# left the block scrolling sideways by 434px — "the left side of the panel needs to
		# come left so that we don't need to horizontal scroll there".
		#
		# Clamped by what the INSPECTOR declares, which is the same leftover rule below: at a
		# 1187px body the block can have 473 of the 710 it wants before the strip beside it
		# would start scrolling instead, and trading one panel's scrollbar for another's is
		# not a fix. So the deficit shrinks from 434 to 237 rather than vanishing — the rest
		# is the block's own width to give up, not the row's to find.
		if _focus_wanted and _focus_inspector != null:
			canvas_w = maxf(canvas_w, minf(_focus_inspector.content_width(),
				maxf(0.0, w - _inspector.content_width() - _CANVAS_GUTTER)))
		# …and wider still for the COLOUR PICKER stacked below (ADR-0089 colour-move
		# amendment). Godot's ColorPicker reports a hard 298px minimum and will not shrink —
		# measured, and it is the theme's, not the content's: hiding the sliders and the hex
		# field takes 175px off the HEIGHT and not one pixel off the width. A Container
		# cannot shrink below its minimum, so a column sized for the player's 276 would not
		# narrow the picker, it would make the picker overhang onto the inspector, which is
		# the failure ADR-0100 dec. 2's clamp exists to make unrepresentable.
		#
		# Bid, never assert: the same leftover clamp below still wins, so on a body too
		# narrow to afford 314 the picker scrolls rather than the strip.
		#
		# It is bid whenever the COLUMN is up, not whenever colour is on. Bidding on the
		# colour flag would make the player's square a function of which emitter is open —
		# "the animation box is changing in size all the time as clicking through keyframes",
		# the complaint ADR-0100 dec. 2's amendment made the box a constant to answer.
		# The WIDTH bid is unconditional while the column is up, even though the panel is
		# not. Bidding on the selection would make the player's square a function of
		# whether a keyframe happens to be selected — "the animation box is changing in
		# size all the time as clicking through keyframes", the complaint ADR-0100 dec. 2's
		# amendment made the box a constant to answer. The HEIGHT is safe to make
		# conditional precisely because this is a sibling panel; the width is not, because
		# `column_width` feeds the square.
		if _colour_picker_panel != null and column_panel == _sequence_panel:
			canvas_w = maxf(canvas_w, minf(picker_panel_w + _CANVAS_CHROME_W,
				maxf(0.0, w - _inspector.content_width() - _CANVAS_GUTTER)))
		# …and wider still for the STRIP'S EXTRA COLUMNS (the wrap amendment, 2026-08-20).
		# `_canvas_floor_w` already counts the life slot, but at its DECLARED minimum, which
		# is deliberately still one column: raising that minimum is how the player panel ends
		# up unable to shrink and overhanging the inspector on a narrow row. So the extra
		# columns are bid HERE, on top of the floor's own answer, and taken only if the
		# leftover clamp below leaves room. Bid, never assert — exactly the picker's rule
		# above, and the reason a small window silently keeps the single column it had.
		#
		# UNCONDITIONAL while the column is up, like the picker's width and for the same
		# reason: bidding on how many rows THIS emitter happens to have would make the
		# inspector's right edge a function of which emitter is open. The author was offered
		# that (it never scrolls, at any length) and rejected it.
		if column_canvas != null and column_panel == _sequence_panel and life_columns > 1:
			canvas_w = maxf(canvas_w, minf(
				_CANVAS_SIDE + _canvas_floor_w(column_canvas)
					+ (sequence_life_slot_w(life_columns) - sequence_life_column_w()),
				maxf(0.0, w - _inspector.content_width() - _CANVAS_GUTTER)))
	# THE FOCUS BLOCK IS STACKED UNDER THE PLAYER, inside the player's own column, and claims
	# NOTHING from the row's width. It was the middle column until 2026-08-19; the width it
	# held goes back to the inspector, which the block had pinned at 450 of a 1241px body.
	# Its height is the column's slack once the player's constant box is paid — see
	# `focus_stack_height`, and note that a short row therefore has none and drops it.
	# THE PICKER IS STACKED UNDER THE PLAYER and takes its declared height from the column's
	# slack BEFORE the frameset block sees any. The block has always been the column's
	# residual claimant — `focus_stack_height` returns 0 when the slack runs out, and a row
	# under roughly 510px already had none, which is why the block never appeared on the
	# developer dashboard's 268px row. This raises that threshold to roughly 960, and it is
	# stated rather than hidden: 439px of ColorPicker in a column whose box is 260 is the
	# price of "the picker never moves", and `picker_panel_h` is a static var so the author
	# can pay less without a rebuild.
	# …and ONLY under the SEQUENCE occupant. ADR-0100 dec. 1's two occupants are mutually
	# exclusive: a `frame` target parks the frameset canvas in this column and there is no
	# particle, no life axis and nothing to colour, so a picker stacked under it would be a
	# 439px panel offering to author something that is not on screen.
	#
	# AND THE PANEL NEVER VANISHES WHILE AN AGE IS SELECTED. It used to: `picker_h` was the
	# raw slack, and `visible` was `picker_h > 0`, so a short row hid the panel and with it
	# the ONLY way to mint a colour keyframe — ADR-0089 dec. 5 deliberately removed the
	# click-to-add path, so losing ⬥ is losing the gesture outright, not losing a shortcut
	# for it. That made a decision about GESTURES a function of the window's height, which
	# is not a trade anybody chose.
	#
	# So the height is a THREE-WAY choice, not a clamp: the full panel when the slack affords
	# `picker_panel_h`; otherwise the HEADER ALONE — title and ⬥, `picker_head_h` — with the
	# grid hidden. There is no fourth reading where the grid appears at a reduced height:
	# Godot's ColorPicker reports a hard 298x439 minimum and a Container cannot render a
	# child below its minimum, so "some of the grid" would be the whole grid overflowing the
	# rect. The header is floored, not clamped, so on a row with almost no slack the panel
	# overhangs by at most `picker_head_h` — a far smaller fault than an unreachable gesture,
	# and one the author can retune without a rebuild.
	var picker_h: float = 0.0
	var picker_grid: bool = false
	var colour_column: bool = column_panel != null and column_panel == _sequence_panel
	if _colour_picker_panel != null and colour_column and _colour_picker_wanted():
		var picker_slack: float = editor_h - box_shown_h - _FOCUS_GUTTER
		picker_grid = colour_picker_grid_fits(picker_slack)
		picker_h = colour_picker_height(picker_slack)
	if _colour_picker != null:
		_colour_picker.visible = picker_grid
	if _colour_picker_panel != null:
		_colour_picker_panel.visible = colour_column and picker_h > 0.0
	var focus_h: float = 0.0
	if _focus_wanted and column_panel != null:
		focus_h = focus_stack_height(editor_h,
			box_shown_h + (picker_h + _FOCUS_GUTTER if picker_h > 0.0 else 0.0),
			_focus_inspector.content_height())
	if _focus_panel != null:
		_focus_panel.visible = _focus_wanted and focus_h > 0.0
	if column_panel != null:
		# The leftover clamp, LAST and over everything: landing on the inspector is worse
		# than a slightly un-square canvas, which is exactly ADR-0100 dec. 2's ordering.
		# No focus term any more — the block is inside this column, not beside it.
		canvas_w = minf(canvas_w, maxf(0.0, w - _inspector.content_width() - _CANVAS_GUTTER))
	var editor_w: float = maxf(0.0, w - canvas_w - (_CANVAS_GUTTER if canvas_w > 0.0 else 0.0))
	# The FEDS pair lane panel is the only remaining BAND under the inspector row.
	var band_h: float = panel_h
	var channels_top: float = bar_h + editor_h + band_h + FramesBar.BAR_H
	if _path_bar != null:
		_path_bar.position = Vector2(0.0, 0.0)
		_path_bar.size = Vector2(w, bar_h)
	# ADR-0130: the strip, then whichever tab is showing, both inside the LEFT column's
	# rect. `editor_h` is unchanged — the row's total height, and therefore the right column and
	# everything stacked below, do not move when a tab is switched or the strip appears.
	var tab_h: float = minf(_tab_strip_h(), editor_h)
	var left_h: float = maxf(0.0, editor_h - tab_h)
	if _tab_strip != null:
		_tab_strip.position = Vector2(0.0, bar_h)
		_tab_strip.size = Vector2(editor_w, tab_h)
	_inspector.visible = (_active_tab != "texture")
	_inspector.position = Vector2(0.0, bar_h + tab_h)
	_inspector.size = Vector2(editor_w, left_h)
	if _texture_panel != null:
		_texture_panel.visible = (_active_tab == "texture")
		# NO SLOT TO STATE ANY MORE (ADR-0130 dec. 11). This used to call
		# `set_slot_width(editor_w)` first, because the tab declared a 560px canvas beside a
		# 300px facts column and so carried an 864px combined minimum against a row that
		# measured 727 — `Control.size` clamps UP to the minimum, so the panel silently
		# overflowed right and the sequence player sliced the facts mid-word.
		#
		# The facts are now an overlay ANCHORED INSIDE the tab's canvas, and a `Control` does
		# not fold an anchored child into its minimum size, so the tab's minimum is chrome
		# alone and fits any slot this row can hand it. The clamp cannot bind, so there is
		# nothing to pre-state. The canvas takes the whole width instead — which is the point
		# of the move: 1000px of empty column at the dev body went back to the picture.
		_texture_panel.position = Vector2(0.0, bar_h + tab_h)
		_texture_panel.size = Vector2(editor_w, left_h)
	# The focus panel sits UNDER the player, in the player's column and at the player's width,
	# starting one gutter below the box. The inspector's rect is a function of the row and the
	# column alone, never of what the block happens to be showing — which was the point of
	# taking the block out of the strip's flow, and it survives the move.
	var stacked_top: float = bar_h + box_shown_h + _FOCUS_GUTTER
	if _colour_picker_panel != null and _colour_picker_panel.visible:
		_colour_picker_panel.position = Vector2(w - canvas_w, stacked_top)
		_colour_picker_panel.size = Vector2(canvas_w, picker_h)
		stacked_top += picker_h + _FOCUS_GUTTER
	if _focus_panel != null and _focus_panel.visible:
		_focus_panel.position = Vector2(w - canvas_w, stacked_top)
		_focus_panel.size = Vector2(canvas_w, focus_h)
	if column_panel != null:
		# custom_minimum_size drives a PanelContainer's size, so it has to be re-derived
		# every flow — assigning `.size` alone would be clamped back up by a stale floor.
		# It is also the ONLY floor: a minimum declared on the canvas itself would raise
		# the panel's combined minimum above the rect assigned here, and a container
		# cannot shrink below its minimum, so the panel would overflow the row.
		# THE BOX STAYS A CONSTANT SQUARE even when the column is widened for the block
		# under it (ADR-0100 dec. 2's amendment, in the one direction the stack could have
		# broken it). Sizing the canvas to the column would make the player's width a
		# function of whether the open target happens to carry a frameset block — the very
		# "the animation box is changing in size all the time as clicking through keyframes"
		# failure that made it a constant. It stays `_CANVAS_SIDE` and the surplus is the
		# panel's padding; only the block below actually spends the extra width.
		column_canvas.custom_minimum_size = Vector2(
			minf(maxf(0.0, canvas_w - _CANVAS_CHROME_W), _CANVAS_SIDE),
			maxf(0.0, box_shown_h - chrome_h))
		column_panel.position = Vector2(w - canvas_w, bar_h)
		column_panel.size = Vector2(canvas_w, box_shown_h)
		# RE-WRAP THE STRIP AGAINST THE RECT WE JUST DECIDED, not against the one the slot
		# is still reporting. The slot's own size is a flow behind this assignment, so
		# reading it here would lay the strip out for the PREVIOUS window on exactly the
		# flow that changed it — the resize would take two passes to settle and look like a
		# lag. Both terms are derived from what this function already computed.
		if column_panel == _sequence_panel:
			_distribute_strip(
				maxf(0.0, canvas_w - _CANVAS_CHROME_W - column_canvas.custom_minimum_size.x
					- _STRIP_SEP),
				maxf(0.0, box_shown_h - chrome_h))
	if _pair_scroll:
		_pair_scroll.visible = _pair_panel != null and _pair_panel.visible
		_pair_scroll.position = Vector2(0.0, bar_h + editor_h)
		_pair_scroll.size = Vector2(w, panel_h)
	_frames_bar.position = Vector2(0.0, bar_h + editor_h + band_h)
	_frames_bar.size = Vector2(w, FramesBar.BAR_H)
	_scroll.position = Vector2(0.0, channels_top)
	_scroll.size = Vector2(w, maxf(0.0, h - channels_top))
	# Bottom-anchor the visible lanes: shift the channel scroll by the height delta of
	# everything stacked above them (inspector + pair panel) so growth doesn't move the
	# lanes on screen. The ScrollContainer's max grows on its deferred re-sort (viewport
	# just shrank), so apply the target deferred too — an immediate set would clamp to
	# the stale, smaller max.
	var delta: float = (bar_h + editor_h + band_h) - _prev_editor_h
	_prev_editor_h = bar_h + editor_h + band_h
	if delta != 0.0:
		_settle_target = maxi(0, _scroll.scroll_vertical + int(round(delta)))
		_scroll.scroll_vertical = _settle_target
	# ONE continuation per flush, whatever the flow count. It used to be a bare
	# `set_deferred` per flow, which is last-write-wins and therefore fine on its own —
	# but Feature 2's nudge has to run AFTER the winner, and a second deferred writer
	# cannot express "after" to a property write. See `_settle_channel_scroll`.
	# The height moved and we are still inside one click's settling window, so the nudge gets
	# another go against the layout as it now stands. When it stops moving, so does this.
	if _selection_settling and delta != 0.0:
		_into_view_pending = true
	if delta != 0.0 or _into_view_pending:
		if not _settle_queued:
			_settle_queued = true
			call_deferred("_settle_channel_scroll")


func _scan_effect_dirs() -> Array:
	var base := "res://assets/effects"
	var out: Array = []
	var da := DirAccess.open(base)
	if da == null:
		return out
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		# Real effects are E001+; E000 is a junk/placeholder dir — skip it.
		if da.current_is_dir() and name.begins_with("E") and name != "E000":
			out.append(base.path_join(name))
		name = da.get_next()
	da.list_dir_end()
	out.sort()
	return out


func _load_effect(dir: String) -> void:
	_current_id = int(dir.get_file().substr(1))   # "E317" -> 317
	_current_dir = dir
	_playing = false
	# The loop region is frame-specific → meaningless for a different effect. Clear it on
	# load (ADR-0090); the loop MODE persists (page state, like Ripple / Hide-inert).
	_loop_region = {}
	_effect_data = EffectDataClass.load_from_directory(dir)
	_ghost_reproject_token += 1          # cancel any debounced ghost render from the prior effect
	_sound_env = _load_sound_env(dir)   # cache the FEDS bank so edits can re-project ghosts
	_seed_sound_ghosts(dir)             # seed _ghost_by_sound_id / _energy_by_sound_id
	_container_views = _compute_container_views(dir)
	_pair_views = _compute_pair_views()
	# The score is projected EXACTLY ONCE per pick, and it is the single most expensive
	# thing on this path (~360 ms cold). When the host can hand back its live model the
	# build has to WAIT for that re-bind below — building here as well would throw the
	# whole ~360 ms away. The host leg is doubly conditional, so gate on the same two
	# has_method checks it uses and let the leg that actually runs own the build:
	# host-less (and live == null) pages still get theirs, just further down.
	var host_rebinds: bool = _host != null and _host.has_method("studio_select_effect") \
			and _host.has_method("studio_effect_data")
	if not host_rebinds:
		_load_score()   # fresh document → reset transport/selection/zoom
	if _scroll:
		_scroll.scroll_vertical = 0   # new score → the old lane-scroll offset is meaningless
		_settle_target = -1           # …and so is any settle the outgoing score had queued
	_into_view_pending = false
	_selection_settling = false
	if _inspector:
		_inspector.clear()
	_update_focus_panel({})
	_nav.clear()   # a new effect drops any prior inspection path (ADR-0073)
	_nav_chain = false
	_update_pair_panel({})   # …and parks the pair lane panel with it
	_refresh_emitter_browser()
	_refresh_container_browser()
	_refresh_frameset_browser()
	_refresh_sequence_browser()
	if _painter_panel:
		_painter_panel.visible = false
	if _host and _host.has_method("studio_select_effect"):
		_host.studio_select_effect(_current_id)   # spawn + park in the main window
		# Project from the host's LIVE model (the one the choke point mutates) so the
		# inspector/timeline reflect edits — one source of truth, no page-vs-host drift.
		if _host.has_method("studio_effect_data"):
			var live = _host.studio_effect_data()
			if live != null:
				_effect_data = live
			# The one build for this pick, from whichever model ended up authoritative.
			# Unconditional: a host that spawns nothing (live == null) skipped the build
			# above on the strength of host_rebinds, so it has to be paid here.
			_load_score()   # the fresh load of this effect (re-bound to live data)
	# Derive the displayed end frame AFTER the final (re-bound) load_score — load_score resets
	# the timeline's end to 0, so computing it earlier (before the host re-bind) would be wiped.
	# The stop line + phase-2 floor + tail dimming all key off this. A short RD-free simulation.
	_recompute_end_frame()
	# A fresh instance starts fully audible; re-push the current solo/mute selection so
	# it matches (load_score cleared the selection, so this is normally "all audible").
	_apply_audibility()
	_update_labels()
	# The player and the canvases, parked at the new (empty) inspection. LAST, so it runs
	# after the host re-bind above may have swapped `_effect_data` for the live model —
	# parking against the loader's copy would rebind the tab to a texture the choke point
	# does not mutate.
	_park_target_surfaces()
	# A fresh document with an empty inspection: the bar shows the new effect id alone.
	# No render happens on this path either (the nav was cleared above).
	_update_path_bar()


## Project the loaded effect's firing sounds (ADR-0085): render each once offline
## through the real SPU (ExMateriaEffectSfx capture mode) and read BOTH its ghost LENGTH
## (how long it stays audible — NOT a tick sum, so a short note firing a long sample is
## covered for its full ring-out) and its energy-envelope climax cue. Returns
## {"ghost": {sid→frames}, "energy": {sid→samples}} — the two consistent maps
## _rebuild_score threads into the model. Runs in a tight capture burst BEFORE live
## playback is armed, with capture_mode restored on the way out, so it never disturbs
## the studio's live audio. Empty maps when there's no FEDS section or the engine isn't
## ready (ghost bars simply don't show — a purely additive projection).
## Load the effect's FEDS bank + SoundContainers from disk ONCE and cache them, so a later
## sound_id edit can re-project the ghosts without re-reading disk. {} when there's no FEDS
## section (ghost bars simply don't show — a purely additive projection).
func _load_sound_env(dir: String) -> Dictionary:
	var le = JSONLoader.load_dir(dir)
	if le == null or le.feds_bank == null:
		return {}
	# Single source of truth (Slice 1, #289): bind the containers to EffectData's OWN doc
	# — the one the choke point mutates — not the loader's separate parse, so a container
	# edit is seen by ghost re-projection through this same reference. Since ADR-0085
	# TIER-3 (bounded FEDS editing) the bank is no longer read-only either: bind
	# EffectData's OWN FedsBank (the object SoundDefChannel patches in place) so pair
	# views / ghosts / pips re-derive from the edited bytes, falling back to the
	# loader's copy only if EffectData carries none.
	var bank = _effect_data.feds_bank if _effect_data.feds_bank != null else le.feds_bank
	return {"feds_bank": bank, "sound_containers": _effect_data.sound_containers}


## (Re)project the LIVE effect's firing sounds from the CACHED bank, updating the ghost/energy
## maps _rebuild_score threads into the model. Called at load AND after a sound_id edit, so the
## ghost tail follows the newly-selected sound. Leaves the maps untouched when it can't project
## (no FEDS env / engine not ready) so a transient miss never wipes existing ghosts.
func _refresh_sound_ghosts() -> void:
	var proj := _project_sound()
	if proj.is_empty():
		return
	_ghost_by_sound_id = proj["ghost"]
	_energy_by_sound_id = proj["energy"]


## Seed the ghost/energy maps for a fresh load WITHOUT blocking (the picker-freeze
## fix). Cache hits land immediately; the misses are queued for the chunked renderer
## _process pumps, so the pick shows the timeline at once and the ghost bars fill in
## across the next frames. A bare out-of-tree page (a unit test, no _process ticks)
## keeps the old synchronous render so its maps are complete on return.
func _seed_sound_ghosts(dir: String) -> void:
	_ghost_queue.reset([])   # an effect switch discards the prior effect's renders
	_reset_energy_queue()    # …and the prior effect's in-flight per-track energy render
	_ghost_by_sound_id = {}
	_energy_by_sound_id = {}
	_pair_energy_cache = {}   # §3: the prior effect's per-track energy renders are stale
	_pair_noop_ab_cache = {}  # …and the prior effect's no-op A/B results
	if _sound_env.is_empty() or _effect_data == null:
		return
	if not is_inside_tree():
		_refresh_sound_ghosts()
		for sid in _ghost_by_sound_id:
			_ghost_cache_store(dir, int(sid))
		return
	var pending: Array = []
	for sid in GhostProjector.firing_sound_ids(_effect_data.sound):
		var c = _ghost_render_cache.get(_ghost_cache_key(dir, sid))
		if c != null:
			_ghost_by_sound_id[sid] = int(c["length"])
			_energy_by_sound_id[sid] = c["energy"]
		else:
			pending.append({"sid": sid,
				"pair_idx": GhostProjector.resolve_pair_idx(_sound_env["sound_containers"], sid)})
	_ghost_queue.reset(pending)


func _ghost_cache_key(dir: String, sid: int) -> String:
	return "%s|%d" % [dir, sid]


func _ghost_cache_store(dir: String, sid: int) -> void:
	if _ghost_by_sound_id.has(sid):
		_ghost_render_cache[_ghost_cache_key(dir, sid)] = {
			"length": int(_ghost_by_sound_id[sid]), "energy": _energy_by_sound_id.get(sid, PackedFloat32Array())}


## Lazily build the dedicated capture SPU (own hardware, no producer) the first time a render
## needs it. Idempotent. A bare out-of-tree page (unit test) builds it here on first render.
func _ensure_capture_engine() -> void:
	if _capture_engine != null:
		return
	if not (ExMateriaEffectSfx and ExMateriaEffectSfx.ready_ok):
		return
	var e = EffectSfxEngineScript.new()
	if e.init_as_capture():
		_capture_engine = e
	else:
		e.free()


func _exit_tree() -> void:
	if _capture_engine != null:
		_capture_engine.free()
		_capture_engine = null


## Pump the chunked ghost renderer one budgeted slice per frame (from _process). Runs on the
## DEDICATED capture SPU, so it NO LONGER yields to live audio — an offline render never parks
## the live producer, so ghost bars keep filling while you play / audition. Each completed render
## merges into the maps + cache and reprojects the SAME document (preserving transport/selection).
func _pump_ghost_queue() -> void:
	_ensure_capture_engine()
	if _ghost_queue.is_idle() or _capture_engine == null:
		return
	var done: Array = _ghost_queue.step(
		_capture_engine, _sound_env.get("feds_bank"), GHOST_RENDER_BUDGET_MS)
	if done.is_empty():
		return
	for r in done:
		var sid: int = int(r["sid"])
		_ghost_by_sound_id[sid] = int(r["length"])
		_energy_by_sound_id[sid] = r["energy"]
		_ghost_cache_store(_current_dir, sid)
	_rebuild_score()


## Drop any in-flight / pending pair-energy render and forget its partials — the
## effect-switch + reset counterpart to _ghost_queue.reset([]).
func _reset_energy_queue() -> void:
	_energy_queue.reset([])
	_energy_partials = {}
	_energy_pending_pair = -1


## Queue the three chunked renders (§3 track-A, track-B, joint mix) for one pair's energy
## bands, superseding any in-flight energy render. This is the CHUNKED replacement for the
## synchronous _render_pair_energy: reset-per-call means a burst of FEDS edits renders ONCE
## after it settles (debounce-by-supersede). The pair's own resolved sound id is pair_idx+1
## (the container-resolver contract, as _render_pair_energy uses). No-op without a FEDS bank.
func _schedule_pair_energy(pair_idx: int) -> void:
	if _sound_env.is_empty() or pair_idx < 0:
		_reset_energy_queue()
		return
	var bank = _sound_env.get("feds_bank")
	if bank == null or pair_idx >= bank.num_pairs:
		_reset_energy_queue()
		return
	var sid := pair_idx + 1
	_energy_partials = {}
	_energy_pending_pair = pair_idx
	# single_track / normalized / trim mirror render_track_energies (A,B: track-alone, RAW,
	# trimmed) and render_pair_mixed_energy (joint: mixed, RAW, UNtrimmed). RAW so
	# _on_energy_job_done can shared-normalize A+B and peak-normalize the joint, exactly as
	# the synchronous path did — the queue just spreads each render across frames.
	_energy_queue.reset([
		{"sid": sid, "pair_idx": pair_idx, "single_track": 0, "normalized": false, "trim": true, "tag": "a"},
		{"sid": sid, "pair_idx": pair_idx, "single_track": 1, "normalized": false, "trim": true, "tag": "b"},
		{"sid": sid, "pair_idx": pair_idx, "single_track": -1, "normalized": false, "trim": false, "tag": "joint"},
	])


## Ensure a pair's energy bands are cached or being rendered — schedule the chunked render
## only when it is neither (a fresh panel open). Idempotent across the many _render_current
## calls a single interaction makes, so it never re-queues the pair already in flight.
func _ensure_pair_energy(pair_idx: int) -> void:
	if _pair_energy_cache.has(pair_idx) or _energy_pending_pair == pair_idx:
		return
	_schedule_pair_energy(pair_idx)


## Advance the pair-energy render a budgeted slice per frame (from _process, only while the
## ghost queue is idle — see the pump discipline there). Runs on the DEDICATED capture SPU, so
## it no longer yields to live audio — the energy band builds while you play / audition.
func _pump_energy_queue() -> void:
	_ensure_capture_engine()
	if _energy_queue.is_idle() or _capture_engine == null:
		return
	var done: Array = _energy_queue.step(
		_capture_engine, _sound_env.get("feds_bank"), GHOST_RENDER_BUDGET_MS)
	for r in done:
		_on_energy_job_done(r)


## Collect one completed §3 energy render (a/b/joint, out of order). Once all three of the
## PENDING pair's tags have landed, assemble them into the _pair_energy_cache entry — the
## same {a,b,a_peak,b_peak,joint} shape _render_pair_energy produced (shared-normalize A+B,
## peak-normalize the joint) — and re-inject the open panel so the bands appear.
func _on_energy_job_done(r: Dictionary) -> void:
	if int(r.get("pair_idx", -1)) != _energy_pending_pair:
		return   # a superseded render's straggler — the pending pair moved on
	_energy_partials[r.get("tag", "")] = r.get("energy", PackedFloat32Array())
	if not (_energy_partials.has("a") and _energy_partials.has("b") and _energy_partials.has("joint")):
		return
	var raw_a: PackedFloat32Array = _energy_partials["a"]
	var raw_b: PackedFloat32Array = _energy_partials["b"]
	var raw_j: PackedFloat32Array = _energy_partials["joint"]
	var shared: Array = GhostProjector.normalize_pair_shared(raw_a, raw_b)
	var pair_idx := _energy_pending_pair
	_pair_energy_cache[pair_idx] = {
		"a": shared[0], "b": shared[1],
		"a_peak": GhostProjector.raw_peak(raw_a), "b_peak": GhostProjector.raw_peak(raw_b),
		"joint": {"samples": GhostProjector.normalize_peak(raw_j), "raw_peak": GhostProjector.raw_peak(raw_j)},
	}
	_energy_partials = {}
	_energy_pending_pair = -1
	# Re-inject onto the open pair view + re-render the panel so the freshly-rendered bands show.
	_update_pair_panel({} if _nav.is_empty() else _nav.back())


## Debounced render of a brand-new sound_id's ghost. Nothing to do — and no render scheduled —
## when the id is silent, already cached, or the effect has no FEDS bank (the instant
## _rebuild_score already showed the right thing). Otherwise coalesce a burst of edits behind a
## short settle delay so the ~0.6s offline render runs ONCE after the value stops changing, then
## reproject the timeline to reveal the tail. A newer edit (or an effect switch) bumps the token
## and supersedes any in-flight render. Renders inline when there's no SceneTree to time against
## (a bare page in a unit test).
func _schedule_ghost_reproject(sid: int) -> void:
	if sid < 2 or _ghost_by_sound_id.has(sid) or _sound_env.is_empty():
		return
	_ghost_reproject_token += 1
	if not is_inside_tree():
		_reproject_sound_id(sid)
		_rebuild_score()
		return
	var token: int = _ghost_reproject_token
	await get_tree().create_timer(GHOST_REPROJECT_DELAY_S).timeout
	if token != _ghost_reproject_token:
		return   # a newer sound_id edit (or an effect switch) superseded this render
	_reproject_sound_id(sid)
	_rebuild_score()


## Ensure the ghost/energy for ONE just-selected sound_id is in the maps, rendering it if new.
## The incremental sibling of _refresh_sound_ghosts (which renders ALL firing sounds, ~0.6s
## EACH — too slow to redo per edit). The common case — retargeting to a sound the effect
## already fires — is ALREADY in the map, so this no-ops and _rebuild_score shows its ghost
## instantly; only a genuinely NEW id pays a single ~0.6s render. Silent ids (0/1) and a
## missing FEDS env have no ghost and are left to _rebuild_score (the span simply shows none).
func _reproject_sound_id(sid: int) -> void:
	if sid < 2 or _ghost_by_sound_id.has(sid):
		return   # silent, or already rendered → the current map + _rebuild_score suffice
	if _sound_env.is_empty() or _effect_data == null:
		return
	# A sid already rendered for THIS effect (session cache) seeds instantly — the
	# common retarget-and-back edit pays no second render.
	var cached = _ghost_render_cache.get(_ghost_cache_key(_current_dir, sid))
	if cached != null:
		_ghost_by_sound_id[sid] = int(cached["length"])
		_energy_by_sound_id[sid] = cached["energy"]
		return
	if not (ExMateriaEffectSfx and ExMateriaEffectSfx.ready_ok):
		return
	var pair_idx: int = GhostProjector.resolve_pair_idx(_sound_env["sound_containers"], sid)
	# In a scene tree, render the ghost length CHUNKED through the SAME queue the load path uses
	# (pumped from _process) so an edit's re-render never blocks — _pump_ghost_queue stores the
	# length + energy, caches, and reprojects when it lands. Deduped by sid, so the debounced
	# burst enqueues one render. Out-of-tree (a unit test, no _process pump) renders synchronously
	# so its maps are complete on return.
	if is_inside_tree():
		_ghost_queue.enqueue({"sid": sid, "pair_idx": pair_idx})
		return
	# Out-of-tree (unit test): render synchronously on the dedicated capture engine (never the
	# live one, which would park the producer). The capture engine is permanently capture-mode.
	_ensure_capture_engine()
	if _capture_engine == null:
		return
	_ghost_queue.abort()   # a sync render panics the engine — never under an in-flight chunk
	var r: Dictionary = GhostProjector.render_pair(_capture_engine, _sound_env["feds_bank"], pair_idx, sid)
	_ghost_by_sound_id[sid] = r["length"]
	_energy_by_sound_id[sid] = r["energy"]
	_ghost_cache_store(_current_dir, sid)


## Render each firing sound once offline through the real SPU (capture mode) and read BOTH its
## ghost LENGTH (how long it stays audible — not a tick sum, so a short note firing a long
## sample is covered for its full ring-out) and its energy-envelope climax cue. Returns
## {"ghost": {sid→frames}, "energy": {sid→samples}}, or {} when it can't project (no cached
## env / engine not ready). capture_mode is restored on the way out so it never disturbs live
## audio. Reads the LIVE _effect_data.sound, so a just-edited sound_id projects its new sound.
func _project_sound() -> Dictionary:
	if _sound_env.is_empty() or _effect_data == null:
		return {}
	_ensure_capture_engine()
	if _capture_engine == null:
		return {}
	# Render on the dedicated capture SPU (permanently capture-mode) — never the live engine.
	return GhostProjector.sound_projection(
		_capture_engine, _effect_data.sound, _sound_env["sound_containers"], _sound_env["feds_bank"])


## Pre-project the effect's shared SoundContainers to legible views (ADR-0085 TIER-2) —
## mode / emitted ids / FEDS pairs / used-by, one per container. Pure (no SPU render), so
## it just loads the FEDS bank + SoundContainers and reads them; the container-kind
## projector and the browser consume the result. Empty when there's no FEDS section.
func _compute_container_views(_dir: String) -> Array:
	if _effect_data == null or _sound_env.is_empty():
		return []
	# Read the containers straight off EffectData's shared doc (Slice 1, #289) so a
	# recompute after a container edit reflects the live bytes; the FEDS bank comes from
	# the cached sound env.
	return SoundContainerModel.container_views(
		_effect_data.sound_containers, _sound_env["feds_bank"], _effect_data.sound)


## Ghost-pip scoping (ADR-0085 TIER-3): pips light up ONLY for (a) the pair open in
## the editor — every firing sound_id resolving to it — or (b) the selected sound
## trigger's own ghost. Pure tick-math decode (no SPU), so it's cheap per nav change.
func _compute_pips() -> Dictionary:
	if _effect_data == null or _sound_env.is_empty() or _nav.is_empty():
		return {}
	var target: Dictionary = _nav.back()
	var bank = _sound_env["feds_bank"]
	var out: Dictionary = {}
	match str(target.get("kind", "")):
		"pair":
			var pidx := int(target.get("ref", {}).get("pair_idx", -1))
			for sid in GhostProjector.firing_sound_ids(_effect_data.sound):
				if GhostProjector.resolve_pair_idx(_sound_env["sound_containers"], sid) == pidx:
					out[int(sid)] = GhostProjector.pair_pips(bank, pidx)
		"span":
			var span_id := str(target.get("ref", {}).get("span_id", ""))
			if span_id.begins_with("sound:"):
				var sid := _span_sound_id(span_id)
				var pidx2 := GhostProjector.resolve_pair_idx(_sound_env["sound_containers"], sid)
				if pidx2 >= 0:
					out[sid] = GhostProjector.pair_pips(bank, pidx2)
	return out


## The live sound_id a sound span addresses ("sound:<phase>:<ci>#<i>"), or 0.
func _span_sound_id(span_id: String) -> int:
	var parts := span_id.split("#")
	if parts.size() != 2:
		return 0
	var lane := parts[0].split(":")
	if lane.size() != 3:
		return 0
	var channels = _effect_data.sound.get(lane[1], [])
	if not (channels is Array):
		return 0
	for ch in channels:
		if ch is Dictionary and int(ch.get("channel_index", -1)) == int(lane[2]):
			var kfs = ch.get("keyframes", [])
			var i := int(parts[1])
			if kfs is Array and i >= 0 and i < kfs.size():
				return int(kfs[i].get("sound_id", 0))
	return 0


## Pre-project every FEDS pair to its lane view (ADR-0085 TIER-3) — notes/chips on the
## pair's own tick axis + container provenance — for the pair-kind projector. Pure decode
## off the cached bank (no SPU render); reads the LIVE containers/sound docs so provenance
## follows edits. Empty when there's no FEDS section.
func _compute_pair_views() -> Array:
	if _effect_data == null or _sound_env.is_empty():
		return []
	var bank = _sound_env["feds_bank"]
	var out: Array = []
	for i in range(bank.num_pairs):
		out.append(FedsPairModel.pair_view(
				bank, i, _effect_data.sound_containers, _effect_data.sound))
	return out


## The single build site: reproject the live effect_data into the timeline score,
## threading the ghost-length map, the energy-envelope map, and the pre-projected
## SoundContainer views so sound triggers carry their read-only ghost bar + climax swell
## and drill into their container (ADR-0085). Every structural re-project funnels through
## here so the projected data never drifts.
func _rebuild_score() -> void:
	_timeline.reproject_score(_build_score())


## Project the live effect_data into a fresh score Dictionary. Shared by the fresh-load
## path (_load_score → load_score, resets transport) and the same-document reshape path
## (_rebuild_score → reproject_score, preserves the author's playhead/selection/zoom).
func _build_score() -> Dictionary:
	return Model.build(
		_effect_data, _ghost_by_sound_id, _energy_by_sound_id, _container_views,
		_pair_views, _pips_by_sound_id)


## Load the current effect as a FRESH document — resets transport/selection/zoom (a new
## effect starts clean). Distinct from _rebuild_score, which re-renders the SAME document
## and keeps the author's place (a Gap edit must not clear the inspector it's typing in).
func _load_score() -> void:
	_timeline.load_score(_build_score())


# --- Save (game→json→bin; the host owns the disk repack) ------------------

## One-click Save: ask the host to lower the live edited effect back to a byte-patched
## E###.BIN on disk. The page owns the button; the host owns the data + the repack. The
## result path / error is shown inline on the transport bar.
func _save() -> void:
	if _host == null or not _host.has_method("studio_save"):
		return
	var res: Dictionary = _host.studio_save()
	var ok: bool = res.get("ok", false)
	_set_status(("Saved: %s" % res.get("out_path", "")) if ok else ("Save failed: %s" % res.get("error", "")))
	if ok:
		print("[Studio] saved %s" % res.get("out_path", ""))
	else:
		push_error("[Studio] save failed: %s" % res.get("error", ""))


# --- Transport (drives the host's live instance) --------------------------

## The frame playback stops / loops at: the derived runtime end when known, else
## the authored max_frame. Scrubbing/stepping is NOT bound to this — only the
## automatic transport (play → stop, loop wrap, restart-from-end).
func _stop_frame() -> int:
	if _end_frame > 0:
		return _end_frame
	return int(_timeline._score.get("max_frame", 0)) if _timeline else 0


func _process(delta: float) -> void:
	# Drain a coalesced scrub seek first: at most one (expensive) host seek per
	# frame, latest cursor position wins. Collapses a fast drag's burst of
	# seek_requested into the single frame the cursor actually landed on.
	if _pending_seek >= 0:
		# A seek's re-pump FIRES sounds; release the chunked ghost render BEFORE the
		# seek so they play audibly (and can't bleed into the offline capture), and
		# hold the queue off long enough for them to ring out.
		if not _ghost_queue.is_idle():
			_ghost_queue_holdoff_ms = Time.get_ticks_msec() + GHOST_SEEK_HOLDOFF_MS
			_ghost_queue.abort()
		var target := _pending_seek
		_pending_seek = -1
		if _host and _host.has_method("studio_seek"):
			_host.studio_seek(target)
		_update_labels()

	# The picker-freeze fix: advance queued ghost renders a budgeted slice per frame.
	# Only one queue may hold the engine's capture bracket at a time (a render's panic()
	# would corrupt the other's in-flight cast), so the ghost queue has priority: when it
	# has work, abort any in-flight energy job (requeued) first; otherwise pump energy.
	if not _ghost_queue.is_idle():
		if not _energy_queue.is_idle():
			_energy_queue.abort()
		_pump_ghost_queue()
	else:
		_pump_energy_queue()

	# Drain a coalesced camera edge edit: at most one whole-section recompile per frame,
	# latest dragged boundary wins (ADR-0086 boundary-drag). No-op when no drag is pending.
	_flush_pending_edge()
	# Drain a coalesced particle Move body-drag: at most one slide+reproject per frame.
	_flush_pending_body_move()

	# Page-driven transport (ADR-0090): the host is PARKED — the page owns the clock.
	# Accumulate 30 Hz × speed and step the bounce transport once per whole frame,
	# seeking the host each step. This is the single playback path (Off / Forward /
	# Ping-pong), replacing the old host free-run mirror.
	if not _playing:
		return
	# The authored Time Scale curve slows the clock exactly like the game does (its accumulator
	# scales by _time_scale_factor). The parked preview instance never runs that accumulator, so
	# the page applies the same factor here: a slow-mo frame accrues fewer transport steps and thus
	# dwells longer (#270 / ADR-0093). 1.0 when the effect has no pacing or the pattern is disabled.
	_transport_accum += delta * TRANSPORT_HZ * _speed() * _pacing_factor_now()
	var steps := 0
	while _playing and _transport_accum >= 1.0 and steps < MAX_STEPS_PER_FRAME:
		_transport_accum -= 1.0
		_transport_step()
		steps += 1
	# Drop any leftover backlog beyond the burst cap so a stall doesn't queue catch-up.
	if _transport_accum >= 1.0:
		_transport_accum = 0.0


func _toggle_play() -> void:
	_playing = not _playing
	# Page-driven transport (ADR-0090): the host stays PARKED — the page seeks it each
	# tick. On Play we arm the bounce transport (reset direction, seek to the loop span's
	# start if the playhead sits outside it), so both a fresh Play and a Play-while-parked
	# -at-the-end begin cleanly. Pausing just stops the accumulator.
	if _playing:
		# Release the offline ghost renderer NOW (not one _process frame later): it holds
		# engine.capture_mode = true across frames while it pre-renders the effect's ghost
		# waveforms on load, and capture_mode PARKS the live producer. Without this, the
		# effect's opening one-shot fires silently in the frame between play-start and the
		# next _pump_ghost_queue abort — the "play right after open = no sound until you
		# audition" bug (an audition already aborts the queue, which is why it un-sticks it).
		# abort() restores the queue's saved capture flag, but nested capture brackets can
		# leave that saved flag true, so FORCE the producer live: Play always means audible.
		_ghost_queue.abort()
		if ExMateriaEffectSfx and ExMateriaEffectSfx.ready_ok:
			ExMateriaEffectSfx.capture_mode = false
		_arm_transport()
	_set_host_playing(false)   # keep the instance parked; only seek moves it
	_update_labels()


## Arm the bounce transport for a Play: reset direction to forward, clear the fractional
## accumulator, and — if the playhead sits OUTSIDE the effective loop span — seek to its
## start so playback begins inside the region (ADR-0090). Scrubbing/stepping stays free;
## only automatic Play snaps into the span.
func _arm_transport() -> void:
	_loop_dir = Transport.DIR_FWD
	_transport_accum = 0.0
	var span := LoopRegion.effective(_loop_region, _stop_frame())
	var cur: int = _timeline.get_playhead()
	if cur < int(span["start"]) or cur >= int(span["end"]):
		_seek(int(span["start"]))


## Advance the transport one frame: step LoopTransport over the effective loop span and
## seek the host to the result. A ping-pong REVERSE step (dir back) uses the SILENT seek
## path (skips the sound re-arm — you can't play a sound backward); forward steps and a
## Forward-mode wrap use the normal re-arming seek. In Off mode the step reports `done`
## at the stop frame → halt (the old non-loop stop-at-end behaviour).
func _transport_step() -> void:
	var span := LoopRegion.effective(_loop_region, _stop_frame())
	var cur: int = _timeline.get_playhead()
	var s := Transport.step(int(span["start"]), int(span["end"]), _loop_mode, _loop_dir, cur)
	var f: int = int(s["frame"])
	if s["done"]:
		_playing = false
		_set_host_playing(false)
		_timeline.set_playhead(f)
		_update_labels()
		return
	_loop_dir = int(s["dir"])
	_timeline.set_playhead(f)
	if _host:
		if _loop_dir == Transport.DIR_BACK and _host.has_method("studio_seek_silent"):
			_host.studio_seek_silent(f)
		elif _host.has_method("studio_seek"):
			_host.studio_seek(f)
	_update_labels()


func _stop() -> void:
	_playing = false
	_set_host_playing(false)
	_seek(0)
	# Hand the camera back to the free cursor camera (the instance stays parked at
	# 0). Play/select re-engage the effect camera. Without this the camera would
	# sit on the effect's frame-0 pose with the tile cursor hidden.
	if _host and _host.has_method("studio_stop"):
		_host.studio_stop()


func _step_frame(d: int) -> void:
	_playing = false
	_set_host_playing(false)
	_seek(_timeline.get_playhead() + d)


## Cycle the loop MODE Off → Forward → Ping-pong → Off (ADR-0090). Page state, persists
## across effect loads. What it loops is the region when set, else the whole score.
func _cycle_loop_mode() -> void:
	_loop_mode = (_loop_mode + 1) % 3
	_update_labels()


## "Loop life": one-click set the region to the particle's real lifespan
## `[0, animation display length]` (ADR-0090). Falls back to the whole score end when the
## effect has no resolvable animation-driven length.
func _set_loop_life() -> void:
	var life := _animation_display_length()
	if life <= 0:
		life = _stop_frame()
	_set_region({"start": 0, "end": maxi(1, life)})


## Clear the loop region → whole-score fallback.
func _clear_region() -> void:
	_set_region({})


## Adopt a new loop region (or `{}` to clear) and refresh the region-driven views.
func _set_region(region: Dictionary) -> void:
	_loop_region = region
	if _timeline and _timeline.has_method("set_loop_region"):
		_timeline.set_loop_region(region)
	if _frames_bar and _frames_bar.has_method("set_loop_region"):
		_frames_bar.set_loop_region(region)
	_update_labels()


## The loaded effect's animation-driven display length (baked game frames) for "Loop
## life". Uses the first emitter's animation index; returns -1 when unresolvable so the
## caller falls back to the whole-score end.
func _animation_display_length() -> int:
	if _effect_data == null or _effect_data.emitters.is_empty():
		return -1
	var em = _effect_data.emitters[0]
	return _effect_data.get_animation_display_length(int(em.anim_index))


## Toggle the "free camera" debug mode on the host. When on, the effect keeps
## playing but the editor hands the camera back to the scene's free tile-cursor
## camera (see EffectViewerScene.studio_set_free_camera). Page-level UI state,
## reset on reload; the host reconciles ownership immediately.
func _toggle_free_cam() -> void:
	_free_cam = not _free_cam
	if _host and _host.has_method("studio_set_free_camera"):
		_host.studio_set_free_camera(_free_cam)
	_update_labels()


## Render-layer compare toggle (#7916): flip the effect between the display-space fold (correct,
## clamped) and native Forward+ in-scene blend (the muddy "wrong" side) via the host, so both can be
## captured from the Studio. Page-level UI state; the host forwards to CompositorAutopilot.
func _toggle_native_blend() -> void:
	_native_blend = not _native_blend
	if _host and _host.has_method("studio_set_native_blend"):
		_host.studio_set_native_blend(_native_blend)
	_update_labels()


## Ripple toggle (ADR-0087 dec. 10): pure page state — nothing to tell the host; the
## flag is injected per-edit at _apply_edit so it lands on the field_ref (and thus the undo
## record) of colour-lane resizes only.
func _toggle_ripple() -> void:
	_ripple = not _ripple
	_update_labels()


## "Hide inert" toggle (ADR-0089 amendment): flip the session-local flag, relabel, and
## re-render so the inspector redraws in the new mode. Unlike Ripple (edit-time only), this
## mode changes what is DRAWN, so it must re-render. Session-local — never written to the effect.
func _toggle_hide_inert() -> void:
	_hide_inert = not _hide_inert
	_update_labels()
	_render_current()


## Curve-sparkline "Fit H" toggle (ADR-0089 curve-UX): flip the GLOBAL height-normalize
## static, relabel, and re-render so every sparkline re-plots at the new scale. Global
## by design — a shared scale is what makes the rows comparable.
func _toggle_fit_height() -> void:
	Sparkline.display_normalize_height = not Sparkline.display_normalize_height
	_update_labels()
	_render_current()


## Curve-sparkline "Fit W" toggle: flip the GLOBAL width-trim static (trim to the used
## window vs draw the whole curve), relabel, and re-render.
func _toggle_fit_width() -> void:
	Sparkline.display_trim_width = not Sparkline.display_trim_width
	_update_labels()
	_render_current()


## The current playback speed multiplier (page-side transport accumulator). Speed lives on
## the PAGE (ADR-0090): it multiplies the accumulator, not the host clock (the host is
## parked and only seeks). Driven by the toolbar ScrubField; no studio_set_speed call.
func _speed() -> float:
	return _speed_value


## The authored Time Scale pacing factor at the current playhead — 2/value, gated by the enable
## flags (EffectScoreModel.pacing_factor_at). Slows the transport clock the same way the game's
## _time_scale_factor slows its accumulator. 1.0 when no effect / no pacing / pattern disabled.
func _pacing_factor_now() -> float:
	if _effect_data == null:
		return 1.0
	var p1d := 0
	if _effect_data.timeline != null:
		p1d = int(_effect_data.timeline.phase1_duration)
	return Model.pacing_factor_at(_effect_data.time_scale, p1d, _timeline.get_playhead())


## The frames bar announced an Alt+left-drag loop region — adopt it (ADR-0090).
func _on_region_changed(start: int, end: int) -> void:
	_set_region({"start": start, "end": end})


func _seek(frame: int) -> void:
	var f: int = maxi(0, frame)
	_timeline.set_playhead(f)
	if _host and _host.has_method("studio_seek"):
		_host.studio_seek(f)
	_update_labels()


func _set_host_playing(playing: bool) -> void:
	if _host and _host.has_method("studio_set_playing"):
		_host.studio_set_playing(playing)


## Resolve the timeline's per-lane solo/mute selection into the preview's silence
## (EffectScoreModel.resolve_audibility) and forward it to the host, which routes the
## disabled emitters to the particle renderer and the silenced lanes to the
## screen/palette/camera/sound subsystems. Called on every solo/mute toggle AND after
## a fresh effect load (a new instance starts fully audible). No-op without a host.
func _apply_audibility() -> void:
	if _host == null or not _host.has_method("studio_set_audibility") or _timeline == null:
		return
	var res := Model.resolve_audibility(_timeline._score,
		_timeline.muted_lanes(), _timeline.soloed_lanes())
	_host.studio_set_audibility(res)


func _update_labels() -> void:
	if _play_btn:
		_play_btn.text = "⏸ Pause" if _playing else "▶ Play"
	if _loop_btn:
		_loop_btn.text = _LOOP_MODE_LABELS[_loop_mode]
	if _clear_region_btn:
		# Name the active region so the whole-score fallback is legible.
		if LoopRegion.is_empty(_loop_region):
			_clear_region_btn.text = "Region: whole"
		else:
			_clear_region_btn.text = "Region: %d-%d ✕" % [int(_loop_region["start"]), int(_loop_region["end"])]
	if _freecam_btn:
		_freecam_btn.text = "Free cam: on" if _free_cam else "Free cam: off"
	if _native_btn:
		_native_btn.text = "Render-layer: NATIVE (wrong)" if _native_blend else "Render-layer: fold"
	if _ripple_btn:
		_ripple_btn.text = "Ripple: on" if _ripple else "Ripple: off"
	if _hide_inert_btn:
		_hide_inert_btn.text = "Hide inert: on" if _hide_inert else "Hide inert: off"
	if _fit_h_btn:
		_fit_h_btn.text = "Fit H: fit" if Sparkline.display_normalize_height else "Fit H: abs"
	if _fit_w_btn:
		_fit_w_btn.text = "Fit W: win" if Sparkline.display_trim_width else "Fit W: all"
	# The speed ScrubField renders its own value — no label to sync here.
	# The frame readout needs the timeline; _update_labels can run at transport-build
	# time (to seed toggle captions) before _timeline exists, so guard it.
	if _frame_label and _timeline:
		# Denominator is the real end (where playback stops); note the authored span
		# when it differs so the trimmed/over-run tail is still legible in the readout.
		var stop_frame: int = _stop_frame()
		var authored: int = int(_timeline._score.get("max_frame", 0))
		var txt := "frame %d / %d" % [_timeline.get_playhead(), stop_frame]
		if authored != stop_frame:
			txt += "  (authored %d)" % authored
		_frame_label.text = txt
	# Continuous playhead-marker sweep (ADR-0089 amendment): _update_labels is the one hook
	# both the scrub path and every transport tick funnel through, so refresh the marker here.
	_refresh_playhead_marker()


# --- Selection / curves ---------------------------------------------------

func _on_span_selected(span_id: String) -> void:
	# The global "Time scale" bands (#270, ADR-0093) are not inspection spans — clicking one
	# opens the pop-up painter for that pacing curve, never a span inspection root.
	if span_id.begins_with("time_scale#"):
		_open_pacing_painter(span_id.substr("time_scale#".length()))
		return
	# Slice 1 (ADR-0085 2026-08-12 §1): a sound-trigger click LANDS DEEP on its pair —
	# seed the full [span → container → pair] trail so the panel/inspector open on the
	# FEDS code, replacing the old 4-click step-in drill onto an empty overview. The
	# container and trigger survive as breadcrumb crumbs (_navigate_to truncates back to
	# them — one click to step back). A non-sound / silent / unresolved span stays a
	# plain span ROOT (the ADR-0073 fresh entry point).
	if _seed_sound_chain(span_id):
		return
	# Timeline select = a FRESH inspection ROOT (discards any prior drill path). A span is
	# one entry point into the effect's object graph (ADR-0073); child-ref links + the
	# browser DRILL from here, breadcrumb entries STEP BACK — all through the same inspector.
	# Feature 2: rendering grows the inspector, and _relayout bottom-anchors the lanes — pushing
	# the just-clicked span above the visible window. Armed BEFORE the render, because the render
	# is what runs `_relayout` (synchronously, via `content_changed`), and `_relayout` is where
	# the settle continuation gets queued. Arming after would miss the flow that needs it.
	# FRESH span selection only (the click path); drill / step-back / passive re-renders don't
	# re-scroll.
	# `_into_view_pending` BEFORE the render (the render runs `_relayout` synchronously via
	# `content_changed`, and that is where the settle continuation is queued);
	# `_selection_settling` AFTER, because `_set_root` clears it for every other caller.
	_into_view_pending = true
	_set_root(Target.span(span_id))
	_selection_settling = true


## Esc → the Deselected (empty inspection) state (CONTEXT.md): drop the whole nav path, clear
## the inspector EXPLICITLY (a render won't — _render_current early-returns on empty _nav), and
## clear the timeline highlight. No focus grab (the focus owner is left null). Returns true only
## when it actually cleared a selection, so the caller consumes only a meaningful Esc — an
## already-empty Esc is a no-op that stays free to bubble (a future close-window).
## Park every per-target surface — the inspector row's two right-column occupants and the
## Texture tab's bind — at an EMPTY target.
##
## Called from the only two paths that clear `_nav`: Esc (`_deselect`) and a fresh effect
## load. Both of them relied on `_render_current()` to update these, and it EARLY-RETURNS on
## an empty nav — a fact both functions had a comment celebrating as a saving ("no render
## happens on this path"). The saving was a gap: nothing ever told these three surfaces that
## what they were showing had gone away.
##
## Measured before it was fixed, driving the real page E019 → Esc → E317: after Esc the
## sequence player was still visible and still bound to `{anim_index: 1}` of the emitter
## just deselected; after loading E317 it was STILL bound to E019's animation 1, and the
## Texture tab still held E019's sheet (instance …977776 against the loaded …091137). An
## author looking at E317 was looking at E019's art.
##
## ORDER MATTERS. The sequence panel is parked BEFORE the tab, because the tab asks
## `_shown_frameset()` — the player's current opcode — for a frameset when the target names
## none. Parking the tab first would let it read the outgoing sequence and outline regions
## belonging to the effect being replaced.
func _park_target_surfaces() -> void:
	_update_frameset_canvas({})
	_update_sequence_canvas({})
	_update_texture_tab({})


func _deselect() -> bool:
	var had_selection: bool = not _nav.is_empty() \
		or (_timeline != null and _timeline.selected_span_id() != "")
	if not had_selection:
		return false
	_nav.clear()
	_nav_chain = false
	# A nudge armed by the click being undone here has nothing left to scroll to, and
	# leaving it armed would let it fire against the NEXT flow's selection. The settling
	# window closes with it — Esc ends the click that opened it.
	_into_view_pending = false
	_selection_settling = false
	if _inspector:
		_inspector.clear()
	# The colour-keyframe selection is a SUB-selection of the target being dropped, so it
	# cannot survive it — leaving it set kept `_colour_picker_wanted()` true against a target
	# that no longer exists, and the picker was the one panel Esc could not close.
	_clear_colour_selection()
	_update_focus_panel({})
	_park_target_surfaces()   # …and the player/canvases, which no render would reach
	if _timeline:
		_timeline.select_span("")
	_update_path_bar()   # no render happens on this path (_render_current early-returns)
	return true


## THE CHANNEL SCROLL'S ONE SETTLE POINT, one deferred hop after `_relayout` — which is when
## the ScrollContainer has re-sorted and `scroll_vertical`'s MAX is finally correct.
##
## WHY BOTH WRITERS HAD TO BE PUT IN ONE PLACE (#453). `_relayout` bottom-anchors the lanes and
## Feature 2 nudges the selection back into view, and the second is only meaningful AFTER the
## first. That ordering was expressed as `_scroll.set_deferred("scroll_vertical", target)` in
## `_relayout` plus `call_deferred("_scroll_selected_into_view")` in `_on_span_selected`, with a
## comment asserting the nudge would therefore run last. MEASURED, it ran FIRST — and worse, it
## ran against a `scroll_vertical` that both of `_relayout`'s writes had left at 0 (the immediate
## one clamps to the stale, smaller max; the deferred one had not landed yet). So the nudge asked
## `compute_scroll_target` whether a span at y=22 was visible in a window starting at 0, got the
## honest answer "yes, leave it alone" (−1), and did nothing — every time. Feature 2 has never
## fired since it was written.
##
## What made that invisible: `_relayout`'s deferred write then lands on the correct max, and on
## an idle box it re-clamps to 0, so the span IS visible and the acceptance test goes green —
## vacuously, never once exercising the scroll it is named for. Under contention that same write
## lands non-zero (187 / 198 / 262 observed across three failures) and the span is behind the
## editor. The flake was the only time the feature's absence was observable.
##
## A property `set_deferred` cannot say "after the other deferred write", so the fix is to stop
## trying: one continuation owns the settle, applies `_relayout`'s target first and the nudge
## second, and is queued once per flush however many flows ran.
func _settle_channel_scroll() -> void:
	_settle_queued = false
	if _scroll == null:
		_settle_target = -1
		_into_view_pending = false
		return
	if _settle_target >= 0:
		_scroll.scroll_vertical = _settle_target
		_settle_target = -1
	if _into_view_pending:
		_into_view_pending = false
		_scroll_selected_into_view()


## Feature 2 (run from `_settle_channel_scroll`): scroll the selected span back into the visible
## timeline window after the inspector grew over it. rebuild_layout() first so the span rects are
## current, then apply the pure compute_scroll_target decision (−1 = already visible → leave it).
func _scroll_selected_into_view() -> void:
	if _timeline == null or _scroll == null:
		return
	_into_view_runs += 1
	# THE INVARIANT THIS FUNCTION'S CORRECTNESS RESTS ON, recorded rather than assumed.
	# A `_settle_target` still outstanding means `_relayout` has queued a scroll write that
	# has not landed, so `_scroll.scroll_vertical` below is a value about to be overwritten
	# and every decision taken from it is void. That was the defect: the nudge ran first,
	# read 0, answered "already visible", and `_relayout`'s write then moved the window out
	# from under it. Cheap to record, and `into_view_debug` lets a test assert it.
	_into_view_saw_pending_settle = _settle_target >= 0
	_timeline.rebuild_layout()
	var rect: Rect2 = _timeline.selected_span_rect()
	if rect.size.y <= 0.0:
		return   # nothing selected / no drawn rect
	var target: int = compute_scroll_target(rect, _scroll.scroll_vertical, _scroll.size.y,
		SCROLL_INTO_VIEW_HEADROOM)
	if target >= 0:
		_scroll.scroll_vertical = target


## Test seam (#453): how many times the into-view nudge has run, and whether the LAST run
## happened while `_relayout` still had a scroll write outstanding. `saw_pending_settle` must
## be false — it is the whole content of the ordering fix, and it is true on the old code.
## `runs` is here so a test can tell "ordered correctly" from "never ran at all", which is
## the confusion that let the defect survive: a nudge that never fires and a nudge that
## fires and correctly declines look identical from outside.
func into_view_debug() -> Dictionary:
	return {"runs": _into_view_runs, "saw_pending_settle": _into_view_saw_pending_settle,
		"settling": _selection_settling}


## Open the GLOBAL Effect Settings surface (#271) — the effect_settings inspection target.
## A fresh inspection ROOT (like a browsed emitter), so the toolbar button drops the current
## drill path and shows the effect's global knobs (timeline phase durations today).
func _open_effect_settings() -> void:
	_set_root(Target.effect_settings())


## The deep [span → container → pair] nav a sound-trigger click seeds when the span
## resolves into a FEDS pair (ADR-0085 §1), else [] (a non-sound / silent / unresolved
## span stays a plain span root). The container index is the trigger's sound_id − 2
## (the Target.container contract); the pair is the container resolver's first-fire pair.
## Seed the all-in-one chain page for a sound trigger and render it, returning true when
## it took. False means the span resolves to no pair (a silent slot, a dead container, an
## end-cap) and the caller should fall back to its own plain-root behaviour.
##
## SHARED BY BOTH CLICK PATHS ON PURPOSE. A sound trigger stacks several hit targets on the
## same few pixels, and `hit_test` gives the FIRE handle priority over the select marker —
## by design, so a marker grab drags the trigger instead of merely inspecting it. But the
## handle is 9 px wide over an 8 px select rect, so for every trigger past the first it
## covers the marker COMPLETELY: pressing the thing the author actually aims at never
## reaches `_on_span_selected`. When the chain was built (ADR-0085 amendment 2026-08-21)
## the seeding was added there and only there, so `_on_fire_drag_started`'s own
## `_set_root` — which predates it — quietly answered a click on the marker with the
## one-entry span root, i.e. the config rows and no chain at all.
##
## The rule this restores: **the press is a SELECTION and the drag is an EDIT.** Which pixel
## of a trigger you press decides what you can drag; it must never decide what you inspect.
func _seed_sound_chain(span_id: String) -> bool:
	var seed := _pair_nav_for_sound_span(span_id)
	if seed.is_empty():
		return false
	_nav = seed
	# …and the chain RENDERS WHOLE (ADR-0085 amendment 2026-08-21, decision 1). The
	# three tiers were always things the author wanted to SEE, not to visit; walking
	# them was pure cost. This is the one gesture in the studio that opts in.
	_nav_chain = true
	_render_current()
	return true


func _pair_nav_for_sound_span(span_id: String) -> Array:
	if not span_id.begins_with("sound:") or _sound_env.is_empty():
		return []
	# The TERMINATOR end-cap has no chain. ADR-0085's terminator rule is that the runtime
	# never fires index == max_keyframe: its own projector renders one inert row reading
	# "End of track … It is not a sound". Its slot's sound_id is real padding all the same —
	# 112 end-caps across 52 effects carry one that resolves to a live container — so
	# seeding off it would put "this is not a sound" and a full container → FEDS pair chain
	# claiming what it plays on the SAME page. Short, not special-cased (decision 7).
	if str(Model.find_span(_timeline._score if _timeline else {}, span_id)
			.get("role", "event")) == "terminator":
		return []
	var sid := _span_sound_id(span_id)
	var pair_idx: int = GhostProjector.resolve_pair_idx(
			_sound_env["sound_containers"], sid)
	if pair_idx < 0:
		return []
	return [Target.span(span_id), Target.container(sid - 2), Target.pair(pair_idx)]


## Start a fresh inspection at `target` (a timeline span or a browsed emitter): reset the
## nav stack to just this root, then render.
func _set_root(target: Dictionary) -> void:
	if Target.is_empty(target):
		return
	# ANY root that is not a fresh span click closes the into-view window — drill,
	# step-back, effect-settings. `_on_span_selected` re-opens it immediately after this
	# returns, so the click path keeps its window and ADR-0073's "drill / step-back /
	# passive re-renders don't re-scroll" survives unchanged.
	_selection_settling = false
	_audition_override_id = -1   # a new root re-opens a chip (ADR-0085 2026-08-13)
	_nav = [target]
	_nav_chain = false           # a fresh root is one entry, never a chain
	_render_current()


## Follow a reference (a `link` field / a breadcrumb row): DRILL to a new target (push), or
## if the target is already on the path, STEP BACK to it (truncate). Consecutive dupes
## collapse so re-clicking the current object is a no-op.
func _navigate_to(target: Dictionary) -> void:
	if Target.is_empty(target):
		return
	# A nav / event-selection change re-opens a chip → reset the transient audition override
	# to the note's running instrument (ADR-0085 2026-08-13 — preview UI, not a sticky choice).
	# A dropdown pick re-renders via _apply_edit → _render_current (NOT this path), so the
	# override survives that render and its re-gating sticks.
	# Chain inspection (ADR-0085 amendment 2026-08-21, decision 6): in a seeded chain every
	# entry is ALREADY ON SCREEN, so a link to an ancestor is not a step back — it is a
	# scroll. The ordinary rule would truncate, and the trigger's own `Plays → container N`
	# cell points at _nav[1], so following it would destroy the chain the author is reading.
	# The BACK entry stays exempt: re-navigating to it is the pair panel's event selection
	# (_on_pair_event_selected), which needs the re-render.
	if _nav_chain and not _nav.is_empty():
		var on_screen := _chain_index_of(target)
		if on_screen >= 0 and on_screen < _nav.size() - 1:
			if _inspector:
				_inspector.scroll_to_section(_chain_fold_key(_nav[on_screen]))
			return
		# Decision 3: the deepest slot holds exactly ONE pair. A sibling — picked from the
		# fire dropdown or followed from the container's own bank-entry links — REPLACES it.
		# Appending would put two FEDS sections and two ~350px lane panels on the page, which
		# is the alternative the amendment rejected on the vertical budget.
		if Target.kind(target) == "pair" and Target.kind(_nav.back()) == "pair" \
				and not Target.equals(_nav.back(), target):
			_audition_override_id = -1
			_nav[_nav.size() - 1] = target
			_render_current()
			return
	_audition_override_id = -1
	if _nav.is_empty():
		_nav = [target]
	else:
		var at := -1
		for i in range(_nav.size()):
			if Target.equals(_nav[i], target):
				at = i
				break
		if at >= 0:
			_nav.resize(at + 1)          # step back to an ancestor already on the path
		elif not Target.equals(_nav.back(), target):
			_nav.append(target)          # drill one level deeper
	_render_current()


## Render the top-of-stack target: a breadcrumb of the ancestors (clickable to step back)
## above the target's own header + sections, through the target-kind seam. The timeline
## highlight is authoritative ONLY for a span target (ADR-0073) — drilling into an emitter
## leaves the origin span highlighted, it doesn't try to select a non-span on the timeline.
func _render_current() -> void:
	# Ghost pips track the nav target (open pair / selected sound trigger — ADR-0085
	# TIER-3 one-way emphasis): recompute the scoped map and re-thread the score only
	# when it actually changed, so ordinary renders stay reproject-free.
	var pips := _compute_pips()
	if pips != _pips_by_sound_id:
		_pips_by_sound_id = pips
		if _timeline:
			_rebuild_score()
	_update_pair_panel({} if _nav.is_empty() else _nav.back())
	_update_frameset_canvas({} if _nav.is_empty() else _nav.back())
	_update_sequence_canvas({} if _nav.is_empty() else _nav.back())
	_update_texture_tab({} if _nav.is_empty() else _nav.back())
	# AFTER `_update_sequence_canvas`, which binds the player the block's subject opcode is
	# read off (`_focus_op_index`), and before the early return so an empty nav parks it.
	_update_focus_panel({} if _nav.is_empty() else _nav.back())
	_update_path_bar()
	if _inspector == null or _nav.is_empty():
		return
	var target: Dictionary = _nav.back()
	var score: Dictionary = _timeline._score if _timeline else {}
	# The trail is the PATH BAR's, not the header's — prepending it here as well would
	# render it twice, once as chrome and once as grid rows.
	var header: Array = Model.inspector_header(target, _effect_data, score)
	# …but the SECTIONS are still the chain's when one is seeded (ADR-0073 dec. 11):
	# a one-entry stack lowers to exactly `Model.inspector_sections(back)`,
	# so this is additive, and taking the single-entry form here would render only the
	# deepest tier and silently un-build chain inspection.
	var sections := _sections_for_render(score)
	_inject_target_color_seed(sections)
	# The name column is per-BUILD, so the sequence view can run tight while every other
	# target keeps the 240px house width ADR-0089 dec. 6 sized for "Position · at start".
	# Alignment is claimed WITHIN a panel and one number still serves the whole build, so
	# nothing inside this view misaligns — and on the animation screen the width saved is
	# width the focus column beside it gets (ADR-0100's leftover is measured off
	# `content_width()`).
	_inspector.name_column_width = (Inspector.NAME_COL_WIDTH_TIGHT
		if Target.kind(target) == "animation" else Inspector.NAME_COL_WIDTH)
	_inspector.show_target(target, header, sections, _curve_samples, _open_param_curve, _navigate_to,
		_child_edge_suppressed, _set_child_edge_suppressed, _apply_edit, _pick_target, _hide_inert,
		_marker_for_target(), _run_action)
	_wire_colour_author()
	if _timeline and Target.kind(target) == "span":
		_timeline.select_span(str(Target.ref(target).get("span_id", "")))


## What the inspector renders for the current stack. For an ORDINARY stack this is
## `_nav.back()`'s sections and nothing else — byte-identically what it has always been,
## which is the regression contract the whole chain build rests on (ADR-0073 dec. 11).
## Only a SEEDED chain composes: every entry's sections in stack order, the
## upper tiers folded to a summary line each, and — where the container can fire more than
## one pair — a fire dropdown ahead of the FEDS tier.
func _sections_for_render(score: Dictionary) -> Array:
	if _nav.is_empty():
		return []
	if not _nav_chain:
		return Model.inspector_sections(_nav.back(), _effect_data, score)
	var out: Array = []
	for i in range(_nav.size() - 1):
		out.append_array(_chain_entry_sections(_nav[i], score))
	var choice := _pair_choice_section(score)
	if not choice.is_empty():
		out.append(choice)
	out.append_array(Model.inspector_sections(_nav.back(), _effect_data, score))
	return out


## One upper-tier entry of a chain, rendered as a COLLAPSED summary line (ADR-0085
## amendment 2026-08-21, decision 4). The entry's projector is untouched — its `sections()`
## come through unchanged and its `header()` rows are folded in as ordinary cells, so the
## container's `Used by N triggers` reverse-links survive as clickable rows rather than
## being dropped on the floor. Only the section's TITLE, its default fold state and its
## one-line summary are the page's doing.
func _chain_entry_sections(target: Dictionary, score: Dictionary) -> Array:
	var secs: Array = []
	for sec in Model.inspector_sections(target, _effect_data, score):
		secs.append((sec as Dictionary).duplicate())
	var head: Array = Model.inspector_header(target, _effect_data, score)
	if secs.is_empty():
		if head.is_empty():
			return []
		secs = [{"title": Target.title(target), "fields": []}]
	var fields: Array = _header_rows_as_fields(head)
	fields.append_array(secs[0].get("fields", []))
	secs[0]["fields"] = fields
	secs[0]["title"] = Target.title(target)
	secs[0]["summary"] = _chain_summary(target, score)
	secs[0]["fold_key"] = _chain_fold_key(target)
	# An upper tier collapses to a summary line (decision 4) — unless it is the one being
	# DRAGGED right now, whose live numbers are the reason the gesture re-renders at all.
	secs[0]["collapsed"] = str(secs[0]["fold_key"]) != _chain_expand_key
	# A tier with more than one section (none today) folds the rest under their own keys
	# rather than leaving a stray expanded block above the FEDS surface.
	for j in range(1, secs.size()):
		secs[j]["collapsed"] = true
		secs[j]["fold_key"] = "%s:%d" % [_chain_fold_key(target), j]
	return secs


## An entry's header rows as inspector FIELDS. A `{label, link}` row keeps its target (so a
## provenance edge stays navigable inside a fold); a `{label, value}` row becomes a const
## cell. Pure — the rows are already display strings by the time a projector emits them.
static func _header_rows_as_fields(rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		if r.has("link"):
			var link: Dictionary = r.get("link", {})
			out.append({"name": str(r.get("label", "")), "shape": "link",
				"label": str(link.get("label", "")), "target": link.get("target", {})})
		else:
			out.append({"name": str(r.get("label", "")), "shape": "const",
				"value": str(r.get("value", ""))})
	return out


## The one line a collapsed chain tier is reduced to. The CONTAINER's line carries
## `used by N triggers` — that is the ADR-0092 property the amendment claims to keep alive,
## and it is the reason this summary is not just the tier's title.
func _chain_summary(target: Dictionary, score: Dictionary) -> String:
	match Target.kind(target):
		"span":
			var sid := _span_sound_id(str(Target.ref(target).get("span_id", "")))
			if sid < 2:
				return "fires no sound"
			return "plays container %d" % (sid - 2)
		"container":
			var view := _container_view(int(Target.ref(target).get("index", -1)), score)
			if view.is_empty():
				return ""
			var n := int(view.get("used_by", 0))
			return "%s · used by %d trigger%s" % [
				str(view.get("mode_author_label", "")), n, "" if n == 1 else "s"]
	return Target.label(target, _effect_data, score)


## The durable fold key for a chain tier — one per KIND, so the author's collapse choice
## survives clicking from one sound event to the next (each click rebuilds the inspector).
static func _chain_fold_key(target: Dictionary) -> String:
	return "chain:%s" % Target.kind(target)


## The pre-projected container view for an index off the score, or {}.
func _container_view(index: int, score: Dictionary) -> Dictionary:
	var views = score.get("sound_containers", [])
	if not (views is Array) or index < 0 or index >= views.size():
		return {}
	return views[index]


## Is `target` already an entry of the open chain? Index, or -1.
func _chain_index_of(target: Dictionary) -> int:
	for i in range(_nav.size()):
		if Target.equals(_nav[i], target):
			return i
	return -1


## The FIRE CHOICE section that leads a chain's FEDS tier when the container can fire more
## than one distinct pair (15.3% of corpus events) — ADR-0085 amendment 2026-08-21,
## decision 3. One `nav_choice` row, labelled by fire ordinal and slot; picking a sibling
## REPLACES the deepest stack entry. Empty for the other 84.7%, so it costs them nothing.
## It states no reachability: see SoundContainerModel.pair_choices for why.
func _pair_choice_section(score: Dictionary) -> Dictionary:
	if _nav.size() < 3 or _sound_env.is_empty() or _effect_data == null:
		return {}
	if Target.kind(_nav[1]) != "container" or Target.kind(_nav.back()) != "pair":
		return {}
	var bank = _sound_env.get("feds_bank")
	if bank == null:
		return {}
	var index := int(Target.ref(_nav[1]).get("index", -1))
	var open_idx := int(Target.ref(_nav.back()).get("pair_idx", -1))
	var choices: Array = SoundContainerModel.pair_choices(
			_effect_data.sound_containers, index, bank.num_pairs)
	if choices.size() < 2:
		return {}
	var items: Array = []
	for c in choices:
		items.append({
			"label": str(c.get("label", "")),
			"target": Target.pair(int(c.get("pair_idx", -1))),
			"selected": int(c.get("pair_idx", -1)) == open_idx,
		})
	var view := _container_view(index, score)
	return {"title": "Which sound", "fields": [{
		"name": "Fires",
		"shape": "nav_choice",
		"choices": items,
		"tooltip": "Container %d (%s) can fire %d different sounds. This picks WHICH one "
			% [index, str(view.get("mode_author_label", "")), choices.size()]
			+ "the FEDS surface below shows — it edits nothing. The ordinal is the fire "
			+ "that first reaches that sound; whether a later fire happens in a given cast "
			+ "depends on the per-container counter, so no claim is made either way.",
	}]}


## Show the FEDS pair lane panel while a pair target is open (loaded with that
## pair's live view — re-loading the SAME pair preserves the session wind/collapse
## state), hide it for every other target. The panel is the navigator; the F1
## inspector below stays the edit surface (ADR-0085 2026-08-11 amendment).
func _update_pair_panel(target: Dictionary) -> void:
	if _pair_panel == null:
		return
	if Target.kind(target) == "pair":
		var idx := int(Target.ref(target).get("pair_idx", -1))
		for v in _pair_views:
			if int(v.get("pair_idx", -1)) == idx and bool(v.get("valid", false)):
				# Frame-axis §2: resolve the pair's tick-0 anchor (representative
				# firing trigger) before the view lands, so the first layout
				# already projects at the right frames.
				_pair_panel.set_fire_anchor(_pair_anchor(idx))
				# Per-track energy (§3): render (once, cached) the two tracks' isolated
				# shared-normalized envelopes and inject them onto the view's tracks so
				# the panel draws a swell under each lane — the empirical ground truth
				# for the §2 verdicts. Skipped while playing / engine busy (bands fill in
				# on a later open); the fresh view carries no energy until injected.
				_inject_pair_energy(idx, v)
				# The manual no-op A/B tell (active corroboration): injected only when the
				# author has run it for this pair (cache hit) — the fresh view carries none.
				_inject_noop_ab(idx, v)
				_pair_panel.set_view(v)
				# Scope the inspector to the panel's selected event: the panel owns
				# the selection (it survives same-pair set_view), the page mirrors it
				# onto the LIVE view each render — so a view re-derive (an edit's
				# invalidates_feds recompute builds fresh dicts) keeps the Event
				# section instead of dropping the author back to the overview.
				var sel: Dictionary = _pair_panel.selected_event()
				if sel.is_empty():
					v.erase("selected")
				else:
					v["selected"] = sel
				# The transient audition override (ADR-0085 2026-08-13) rides the LIVE view so
				# the projector gates the note-chip console on the effective instrument.
				v["audition_override"] = _audition_override_id
				if not _pair_panel.visible:
					_pair_panel.visible = true
					_relayout()   # the panel band just appeared — re-stack the body
				return
	if _pair_panel.visible:
		_pair_panel.visible = false
		_relayout()


## Inject the open pair's per-track energy bands (§3) onto its view's two tracks:
## a cache hit lands immediately; a miss renders the two isolated envelopes offline
## (when the engine is idle) and caches them. A skipped render (engine busy / bad
## pair) leaves the tracks band-less — the panel simply draws no swell until a later
## open renders it. The energy rides the LIVE view dict, so a re-derive re-injects.
func _inject_pair_energy(pair_idx: int, view: Dictionary) -> void:
	var tracks: Array = view.get("tracks", [])
	if tracks.size() < 2:
		return
	var e = _pair_energy_cache.get(pair_idx)
	if e == null:
		# In a scene tree, render the energy bands CHUNKED off the main thread (the freeze
		# fix) — schedule it and leave the panel band-less until it lands (_on_energy_job_done
		# re-injects). A bare out-of-tree page (unit test, no _process pump) still renders
		# synchronously so its view is complete on return.
		if is_inside_tree():
			_ensure_pair_energy(pair_idx)
			return
		e = _render_pair_energy(pair_idx)
		if e == null:
			return
		_pair_energy_cache[pair_idx] = e
	(tracks[0] as Dictionary)["energy"] = e.get("a", PackedFloat32Array())
	(tracks[1] as Dictionary)["energy"] = e.get("b", PackedFloat32Array())
	# The absolute raw peak rides alongside (ADR-0085 §6, display-only): the panel band's
	# "silent in isolation" tell reads it so a shared-normalized floor swell can't lie.
	(tracks[0] as Dictionary)["energy_raw_peak"] = float(e.get("a_peak", -1.0))
	(tracks[1] as Dictionary)["energy_raw_peak"] = float(e.get("b_peak", -1.0))
	# The JOINT (mixed-pair) waveform — the combined sound the isolated bands never showed.
	# Baseline only here; the A/B run (_inject_noop_ab) overlays the pruned mix afterward.
	var j: Dictionary = e.get("joint", {})
	var jsamples: PackedFloat32Array = j.get("samples", PackedFloat32Array())
	if jsamples.size() > 0:
		view["joint"] = {"baseline": jsamples, "pruned": PackedFloat32Array(),
				"raw_peak": float(j.get("raw_peak", -1.0))}


## Render one pair's two isolated per-track energy envelopes offline (~2 SPU renders,
## shared-peak normalized), or null when it can't render now (no FEDS env / engine not
## ready / transport playing — a live render would panic the audible cast). The pair's
## own resolved sound id is pair_idx + 1 (the container-resolver contract).
func _render_pair_energy(pair_idx: int):
	if _sound_env.is_empty():
		return null
	var bank = _sound_env.get("feds_bank")
	if bank == null or pair_idx < 0 or pair_idx >= bank.num_pairs:
		return null
	_ensure_capture_engine()
	if _capture_engine == null:
		return null
	# Render on the dedicated capture SPU (permanently capture-mode). This synchronous path is the
	# out-of-tree (unit-test) fallback; in a scene tree the bands render chunked via _energy_queue.
	var r: Dictionary = GhostProjector.render_track_energies(
			_capture_engine, bank, pair_idx, pair_idx + 1)
	# The joint (mixed) waveform rides along — one more offline render of both voices together.
	r["joint"] = GhostProjector.render_pair_mixed_energy(
			_capture_engine, bank, pair_idx, pair_idx + 1)
	return r


## THE NO-OP PRUNE A/B (ADR-0085 amendment 2026-08-12 "active corroboration"). Driven by
## the inspector's '▶ Audition (no-ops pruned)' action (beside '▶ Audition pair'): prune
## every no-op, re-render the mixed pair, A/B the energy, and audibly play the pruned pair.
## Proof-only — the per-track tell + joint overlay never flow back into the verdict/hatch.
## Run the three mixed renders (baseline + track-A-pruned + track-B-pruned) for one pair,
## cache the per-track tells, inject them onto the open view and re-render the panel. Mirrors
## the capture-mode dance (_playing guard, capture_mode = true, panic() isolation via
## render_pair, restore on the way out); a live render during playback would panic the
## audible cast, so it no-ops while playing / engine busy. Returns the tells ({} on skip).
func _run_noop_ab(pair_idx: int) -> Dictionary:
	if _sound_env.is_empty():
		return {}
	var bank = _sound_env.get("feds_bank")
	if bank == null or pair_idx < 0 or pair_idx >= bank.num_pairs:
		return {}
	_ensure_capture_engine()
	if _capture_engine == null:
		return {}
	# ONE call on the dedicated capture SPU, baseline rendered once and reused (4 offline renders,
	# not 5) — runs off the live engine so it never parks live audio.
	var entry: Dictionary = GhostProjector.noop_ab(_capture_engine, bank, pair_idx, pair_idx + 1)
	if entry.is_empty() or not entry.has(0):
		return {}
	_pair_noop_ab_cache[pair_idx] = entry
	for v in _pair_views:
		if int(v.get("pair_idx", -1)) == pair_idx:
			_inject_noop_ab(pair_idx, v)
	_update_pair_panel({} if _nav.is_empty() else _nav.back())
	return entry


## The '▶ Audition (no-ops pruned)' action: AUDIO FIRST so it feels instant, then the
## offline A/B measurement. The audition plays immediately; the Δ + joint overlay are
## rendered offline AFTER a short delay — the offline renders panic() the engine, which
## would cut the audition, so we let it ring first. Skips the measurement when the pair has
## no prunable no-ops (the Δ is trivially 0 and re-auditioning is the same sound).
func _audition_pruned(pair_idx: int) -> void:
	if _sound_env.is_empty() or _playing or _audition_holding or not (ExMateriaEffectSfx and ExMateriaEffectSfx.ready_ok):
		return
	var bank = _sound_env.get("feds_bank")
	if bank == null or pair_idx < 0 or pair_idx >= bank.num_pairs:
		return
	var pruned = GhostProjector.build_pruned_bank(bank, pair_idx, [0, 1])
	if pruned == null:
		return
	# 1. Instant audio: play the de-no-op'd pair now.
	_ghost_queue_holdoff_ms = Time.get_ticks_msec() + GHOST_AUDITION_HOLDOFF_MS
	_ghost_queue.abort()
	ExMateriaEffectSfx.audition_bank(pruned, pair_idx, pair_idx + 1)
	# 2. Deferred measurement: nothing to prove if nothing was pruned.
	if pruned.raw == bank.raw:
		return   # build_pruned_bank returned an identical blob → no no-ops here
	if not is_inside_tree():
		_run_noop_ab(pair_idx)
		return
	await get_tree().create_timer(NOOP_AB_MEASURE_DELAY_S).timeout
	if not is_inside_tree() or _playing:
		return   # the page was freed, or the author started playback — skip the measure
	_run_noop_ab(pair_idx)


## Prune-for-real commit (ADR-0085 2026-08-13 amendment): DELETE every no-op opcode from the
## pair for REAL — swap in the smaller byte-exact bank through the host's EffectEditSession
## (undoable via Ctrl+Z, persisted on the next Save), then re-derive + re-render exactly as a
## sound_def byte patch does. A no-op (with a console tell) when the pair has nothing prunable.
func _commit_prune_noops(pair_idx: int) -> void:
	if _sound_env.is_empty() or _playing or _audition_holding or _effect_data == null:
		return
	if not (_host and _host.has_method("studio_prune_feds_noops")):
		return
	var res: Dictionary = _host.studio_prune_feds_noops(pair_idx)
	if res.is_empty():
		print("[Studio] pair %d has no no-ops to delete" % pair_idx)
		return
	# The bank OBJECT was swapped (a delete shrinks the blob) — re-point the cached env at the
	# live model's new bank so every re-derive below reads the pruned bytes. (A same-size
	# sound_def patch shares the object in place; a structural swap does not.)
	_sound_env["feds_bank"] = _effect_data.feds_bank
	# The SAME re-derive a FEDS byte patch takes (invalidates_feds): pair views re-read the new
	# bytes, the pair's energy + no-op A/B proof go stale, and the ghost/energy of every sound_id
	# resolving into this pair is evicted + re-rendered off the debounced offline path.
	_pair_views = _compute_pair_views()
	_pair_energy_cache.erase(pair_idx)
	_invalidate_noop_ab(pair_idx)
	var containers: Array = _sound_env["sound_containers"].get("containers", [])
	for ci in range(containers.size()):
		var sid: int = ci + 2
		if GhostProjector.resolve_pair_idx(_sound_env["sound_containers"], sid) == pair_idx:
			_ghost_by_sound_id.erase(sid)
			_energy_by_sound_id.erase(sid)
			_ghost_render_cache.erase(_ghost_cache_key(_current_dir, sid))
			_schedule_ghost_reproject(sid)
	_rebuild_score()
	_render_current()
	print("[Studio] deleted no-ops from pair %d — %d → %d bytes (Save to persist)" % [
			pair_idx, int(res.get("before_bytes", 0)), int(res.get("after_bytes", 0))])


## The note-chip AUDITION CONSOLE live playback (ADR-0085 2026-08-13, HOLD-TO-PLAY). Routed
## through ExMateriaEffectSfx's managed reserved audition unit (audition_note_on/off) — NOT a raw
## SPU poke, which is unreliable (it races the producer thread AND unit 0 idles out of the
## render path → "silent after the first play"). While a note sounds, `_audition_holding`
## suppresses the studio's offline ghost/energy renders (they set capture_mode, which PARKS
## the live producer and would kill the audition). Guarded to a PARKED transport; nothing is
## saved or fed back into any projector.

## Press-and-HOLD "▶ Hear this note" (tail=false) or "▶ Tail only" (tail=true): key the note on
## at its real pitch and hold it until release. Tail starts AT the loop point (skips the attack).
func _audition_note_press(action: Dictionary, tail: bool) -> void:
	var id := _resolve_audition_instrument(int(action.get("default_instrument", -1)))
	var inst = _audition_instrument(id)
	if inst == null:
		return
	var params: Dictionary = NoteAudition.build(_audition_note_from_action(action), id)
	if tail and not bool((params.get("tail", {}) as Dictionary).get("available", false)):
		return
	if not tail and not bool(params.get("hold_enabled", false)):
		return
	var pitch: int = ExMateriaSound.PitchTable.note_to_pitch(int(params["hold"]["midi_note"]), int(inst.fine_tune))
	# Offline ghost + energy renders now run on the DEDICATED capture SPU (_capture_engine), a
	# SEPARATE hardware from the live producer — so they NO LONGER need to be aborted to audition.
	# The energy band keeps building while the note sounds (the "everything as we go" win). The
	# _audition_holding flag survives for the sync out-of-tree render guards, but nothing here
	# parks the live producer anymore.
	_audition_holding = true
	# instrument_idx is the WAVESET index = raw 0xAC id + 1 (FFT's +1 rule, effect_sound/opcodes/
	# instrument.gd) — the same index _audition_instrument resolved from.
	if tail:
		var loop_off: int = int(params["tail"]["loop_offset_bytes"])
		# Mirror sequencer._resolve_voice_addresses: start_addr adds RAM_INSTRUMENT_BASE, the
		# loop_addr does NOT (FFT PC 0x80016FE0). Start AT the loop point → the pure ring.
		var start_addr: int = ExMateriaSpu.Spu.RAM_INSTRUMENT_BASE + int(inst.sample_offset) + loop_off
		var loop_addr: int = int(inst.sample_offset) + loop_off
		ExMateriaEffectSfx.audition_note_on(id + 1, pitch, int(inst.adsr1), int(inst.adsr2),
				start_addr, loop_addr)
	else:
		ExMateriaEffectSfx.audition_note_on(id + 1, pitch, int(inst.adsr1), int(inst.adsr2))


## Release (button-up): key-off → ADSR release fade, and let the tail ring out via a short
## ghost holdoff before the offline renders resume.
func _audition_note_release() -> void:
	if ExMateriaEffectSfx and ExMateriaEffectSfx.ready_ok:
		ExMateriaEffectSfx.audition_note_off()
	_audition_holding = false
	_ghost_queue_holdoff_ms = Time.get_ticks_msec() + AUDITION_RELEASE_RINGOUT_MS


## The instrument id to audition: the transient dropdown override when set, else the note's
## running instrument carried on the action.
func _resolve_audition_instrument(default_instrument: int) -> int:
	return _audition_override_id if _audition_override_id >= 0 else default_instrument


## The live waveset Instrument for a raw 0xAC `id`, applying FFT's +1 index rule (runtime inst
## N maps to waveset[N+1]; effect_sound/opcodes/instrument.gd) — its fine_tune/adsr/sample_offset feed
## the audition. null when not auditionable now (transport playing / engine not ready / bad id /
## null slot). The buttons are already guarded to a parked transport.
func _audition_instrument(id: int):
	if _playing or not (ExMateriaAudioEngine and ExMateriaAudioEngine.ready_ok):
		return null
	var ws = ExMateriaAudioEngine.waveset
	var rid := id + 1
	if ws == null or rid < 0 or rid >= ws.instruments.size():
		return null
	var inst = ws.instruments[rid]
	return null if inst.is_null else inst


## The pure note dict the builder needs, reconstructed from an audition action's payload.
func _audition_note_from_action(action: Dictionary) -> Dictionary:
	return {
		"octave": int(action.get("octave", 4)),
		"relative_key": int(action.get("relative_key", 0)),
		"duration_ticks": int(action.get("duration_ticks", 0)),
		"duration_seconds": float(action.get("duration_seconds", 0.0)),
		"velocity": int(action.get("velocity", 0)),
	}


## Stamp the cached no-op A/B tells onto the open pair view's two tracks (the tell rides the
## LIVE view dict, so a re-derive re-injects). No-op when the author hasn't run it for this pair.
func _inject_noop_ab(pair_idx: int, view: Dictionary) -> void:
	var tells = _pair_noop_ab_cache.get(pair_idx)
	if tells == null:
		return
	var tracks: Array = view.get("tracks", [])
	for t in range(mini(2, tracks.size())):
		if tells.has(t):
			(tracks[t] as Dictionary)["noop_ab"] = tells[t]
	# Overlay the pruned mix on the joint waveform (baseline was injected by _inject_pair_energy).
	var joint: Dictionary = tells.get("joint", {})
	if not joint.is_empty() and (joint.get("baseline", PackedFloat32Array()) as PackedFloat32Array).size() > 0:
		view["joint"] = joint


## Drop a pair's cached no-op A/B proof — its bytes changed, so the old Δ no longer describes it.
func _invalidate_noop_ab(pair_idx: int) -> void:
	_pair_noop_ab_cache.erase(pair_idx)


## Frame-axis §2 (ADR-0085): the representative trigger whose fire frame anchors
## the open pair's tick-0 — the panel projects `fire + converted` onto the shared
## axis. Priority: the span the drill STARTED from → the timeline's selected
## resolving trigger (live re-anchor on selection) → the FIRST firing trigger
## resolving into the pair (the ghost pips' first-fire representative) → an
## orphan pair anchors at frame 0 with a visible header tell.
func _pair_anchor(pair_idx: int) -> Dictionary:
	var score: Dictionary = _timeline._score if _timeline else {}
	for i in range(_nav.size() - 1, -1, -1):
		var t: Dictionary = _nav[i]
		if str(t.get("kind", "")) == "span":
			var origin := str(t.get("ref", {}).get("span_id", ""))
			if _span_resolves_to_pair(origin, pair_idx):
				return {"frame": _span_start(score, origin), "source": "origin"}
	var sel: String = _timeline.selected_span_id() if _timeline else ""
	if _span_resolves_to_pair(sel, pair_idx):
		return {"frame": _span_start(score, sel), "source": "selected"}
	var first := -1
	for lane in score.get("lanes", []):
		if str(lane.get("kind", "")) != "sound":
			continue
		for span in lane.get("spans", []):
			if str(span.get("role", "")) == "event" \
					and _span_resolves_to_pair(str(span.get("id", "")), pair_idx):
				var s := int(span.get("start", 0))
				if first < 0 or s < first:
					first = s
	if first >= 0:
		return {"frame": first, "source": "first"}
	return {"frame": 0, "source": "orphan"}


## Does this sound span's trigger resolve (ADR-0073 reference-following) into the
## given FEDS pair? The container resolver stays the single fire-table truth.
func _span_resolves_to_pair(span_id: String, pair_idx: int) -> bool:
	if not span_id.begins_with("sound:") or _sound_env.is_empty():
		return false
	return GhostProjector.resolve_pair_idx(
			_sound_env["sound_containers"], _span_sound_id(span_id)) == pair_idx


## A span's fire frame off the projected score (span["start"]), 0 when unknown.
func _span_start(score: Dictionary, span_id: String) -> int:
	for lane in score.get("lanes", []):
		for span in lane.get("spans", []):
			if str(span.get("id", "")) == span_id:
				return int(span.get("start", 0))
	return 0


## A note bar / opcode chip was clicked in the pair lane panel: route to the F1
## inspector's existing rows. _navigate_to collapses consecutive dupes, so a
## same-pair re-selection re-renders WITHOUT growing the nav back-stack.
func _on_pair_event_selected(_track_idx: int, _event_index: int) -> void:
	var idx := int(_pair_panel._view.get("pair_idx", -1)) if _pair_panel else -1
	if idx >= 0:
		_navigate_to(Target.pair(idx))


# Colour-keyframe editor state (ADR-0089 amendment): the last-fetched keyframes (index↔frame) and
# the selected keyframe's particle-age, persisted across the reprojections a structural add causes.
var _colour_keyframes: Array = []
## The selected AGE, keyframe or not. It was only ever set to ages that HAD keyframes until
## the 2026-08-20 two-step change; now it is any age the column addresses, and
## `_colour_index_of_frame` returning -1 is a real, common state rather than "no selection".
var _colour_selected_frame: int = -1
## The ⬥ Set keyframe button — the second step. See `_build_colour_picker_panel`.
var _colour_key_button: Button = null
## Colour on/off for the open emitter — `emitter_flags_lo` bit 6, relocated out of the
## inspector's flag section into the player's transport row. See the build for why it is
## there and not in the picker panel the author pointed at.
var _colour_enable_btn: Button = null


## Wire the inspector's colour-keyframe editor (ADR-0089 amendment) to the host session. The
## inspector BUILDS the age-axis track + box-clamped picker under the ribbon; the page fills the
## track's keyframes from the host session and connects the click/pick signals here, so
## show_target's signature stays stable. Selection is persisted by particle-age FRAME across the
## reprojections that a structural edit (add) triggers.
## Bind the player column's colour track to the emitter the column is about — the FILL half
## of the split the inspector used to own ("inspector BUILDS, page FILLS"). The widgets moved
## columns; the split did not, and neither did any of the model below it.
##
## The signals are connected ONCE at build (`_build_sequence_canvas_overlay`) rather than
## re-checked per bind, because the track is built once and lives for the page's lifetime.
## That is the difference the move buys: the inspector rebuilt its widgets on every reproject,
## so every one of its wirings had to be an `is_connected` guard against stacking handlers.
func _bind_colour_track(on: bool, window: int) -> void:
	if _sequence_life_column == null:
		return
	var ei: int = _sequence_colour_emitter
	var live: bool = on and ei >= 0 and _host != null \
		and _host.has_method("studio_colour_keyframes")
	for lc in _sequence_life_columns:
		lc.visible = live
	# THE TOGGLE IS SYNCED WHETHER OR NOT COLOUR IS LIVE, and the `not live` arm is the whole
	# point of it: that is the state where the column is absent and nothing on screen says
	# why. It reads "Colour: off" there rather than disappearing with everything else.
	_sync_colour_enable_btn()
	if not live:
		_colour_keyframes = []
		_sequence_life_rows = []
		for lc in _sequence_life_columns:
			lc.configure([], [], SequenceThumbnail.SIDE)
			lc.set_keyframes([])
			lc.set_selected_frame(-1)
		_update_colour_picker_panel()
		return
	var state: Dictionary = _host.studio_colour_keyframes(ei)
	_colour_keyframes = state.get("keyframes", [])
	if _colour_picker != null:
		_colour_picker.set_gamut(state.get("gamut", Color.WHITE))
	_bind_life_column()
	_update_colour_picker_panel()


## Push the life rows + the resolved colours into the vertical ribbon, and state what the
## column cannot reach. Split out of `_bind_colour_track` because the STRIP rebuild also has
## to call it: the rows are computed there (they are the strip's own layout), and a ribbon
## configured from a second walk of the trace would be the drift this surface exists to
## remove — row i beside thumbnail i is only true if one projection produced both.
##
## `colors()`, not a re-sample: `_update_sequence_ribbon` has already applied the
## representative-sprite mux and the page-wide `Fit W: win/all` trim, and that array is the
## SHARED resolve the particle renderer paints with (`EffectCurve.sample_rgb`). A second
## sampler here is the drift ADR-0103 dec. 1 forbids.
func _bind_life_column() -> void:
	if _sequence_life_column == null or not _sequence_life_column.visible:
		return
	var colors: Array = _sequence_ribbon.colors() if _sequence_ribbon != null else []
	# THE ROWS ARE PUSHED PER COLUMN, through the SPLIT the strip is already laid out by —
	# never as "all the rows into column 0". Re-slicing here from the applied split rather
	# than recomputing one is what keeps row i beside thumbnail i after a wrap: two walks
	# that agree today are the drift this surface exists to remove, and a wrap gives them
	# somewhere new to disagree.
	var per: int = int(_strip_split.get("per", 0))
	for k in range(_sequence_life_columns.size()):
		var lo: int = mini(k * per, _sequence_life_rows.size()) if per > 0 else 0
		var hi: int = mini(lo + per, _sequence_life_rows.size()) if per > 0 else \
			(_sequence_life_rows.size() if k == 0 else 0)
		_sequence_life_columns[k].configure(_sequence_life_rows.slice(lo, hi), colors,
			SequenceThumbnail.SIDE, _life_band_ceiling)
	# TWO CALLS, because they are two facts. The keyframes and the selection used to arrive
	# together as (array, index into it), which could not express "this age is selected and
	# is not a keyframe" — the state the two-step gesture is entirely about.
	_set_life_keyframes(_colour_keyframes)
	_set_life_selection(_colour_selected_frame)
	# The keyframes the fit carries past this particle's lifetime, SAID rather than silently
	# dropped. They are real curve control points — Douglas-Peucker always keeps the terminal
	# sample, so every colour emitter has at least one — but they address ages the renderer
	# never reads, so the column's domain (the life rows) excludes them. It rides the slot's
	# tooltip because the author had the hint line deleted (2026-08-19) and prose in the
	# column would land on top of the colours it is describing.
	if _sequence_life_slot != null:
		var beyond: int = LifeColumn.beyond_count(_colour_keyframes, _sequence_life_rows)
		if beyond > 0:
			_sequence_life_slot.tooltip_text += \
				"\n· %d past this particle's life, not shown" % beyond


## Colour on/off for the open emitter. Lowered through the host so the flag flip and any
## curve mint are ONE compound edit and therefore one undo (`studio_colour_enable`), then
## reprojected — enabling reshapes the inspector's own relevance table (`EmitterFieldRelevance`
## deads every `color_curve_*` field while the flag is off), so this is not a repaint.
##
## `set_pressed_no_signal` on the way back in: `_sync_colour_enable_btn` runs on every bind,
## and a plain `button_pressed =` would re-emit `toggled` and author the state it was only
## displaying — the same trap `seed_curve` exists for on the picker.
func _on_colour_enable_toggled(on: bool) -> void:
	# `_colour_emitter_index` STILL ANSWERS WITH COLOUR OFF, which is what makes this
	# workable: the provenance ladder's `origin` rung names the emitter a target IS,
	# independently of whether its curves resolve, so an emitter with colour off has an
	# index here even though it has no column. What is -1 is a browsed SEQUENCE with no
	# colour-enabled emitter anywhere — there the toggle has no single emitter to act on and
	# is disabled rather than guessing one.
	var em := _colour_emitter_index()
	if em < 0 or _host == null or not _host.has_method("studio_colour_enable"):
		_sync_colour_enable_btn()
		return
	_host.studio_colour_enable(em, on)
	_render_current()


## Show the flag's real state, and say it in words. Disabled with no emitter to act on, so a
## toggle that could do nothing does not look like a toggle that says "off".
func _sync_colour_enable_btn() -> void:
	if _colour_enable_btn == null:
		return
	var em := _colour_emitter_index()
	var data = _effect_data
	var on := false
	var have := false
	if em >= 0 and data != null and data.emitters is Array and em < data.emitters.size():
		have = true
		on = bool(data.emitters[em].flags.get("color_curve_enabled", false))
	_colour_enable_btn.disabled = not have
	_colour_enable_btn.set_pressed_no_signal(on)
	_colour_enable_btn.text = "Colour: on" if on else "Colour: off"
	_colour_enable_btn.tooltip_text = ("Colour curves for emitter %d — `emitter_flags_lo` "
		% em + "bit 6, the same flag the inspector's Config section carries. With it off "
		+ "the particle renders untinted and there is no colour column to author on. "
		+ "Turning it on where the emitter has no colour curves creates three flat ones at "
		+ "full, which renders identically until you author something.") if have \
		else "No emitter open — colour is a per-emitter flag."


## THE SELECTION AND THE KEYFRAMES GO TO EVERY COLUMN. Both are page facts about an AGE,
## not about a column, and a column that only sometimes hears them would draw a stale mark
## the moment the wrap moved that age somewhere else. Broadcasting is safe because
## `ColourLifeColumn` is frame-addressed: a column whose slice does not contain the age
## resolves an empty rect and draws nothing, so "tell them all" and "tell the right one" are
## the same picture with one fewer thing to get wrong.
func _set_life_selection(frame: int) -> void:
	for lc in _sequence_life_columns:
		lc.set_selected_frame(frame)


func _set_life_keyframes(keyframes: Array) -> void:
	for lc in _sequence_life_columns:
		lc.set_keyframes(keyframes)


## Is there anything for the picker to author? Colour live on this emitter AND a real
## keyframe selected — the author's ask verbatim, *"the color picker should only appear when
## a keyframe is selected"*.
##
## THE FIRST BUILD IGNORED THIS AND KEPT THE PANEL UP ALWAYS, and it was wrong for a reason
## worth writing down: the argument for a constant height was that a picker which hides
## itself swings `_canvas_chrome_h` and re-sizes the canvas square. That is true of a picker
## INSIDE the player panel — and this one is a SIBLING panel, laid out explicitly by
## `_relayout`, which the chrome measurement never looks at. The constraint that bought the
## constant height did not survive the placement that answered it.
##
## What it cost meanwhile was the ADR-0102 frameset block, measured: at a 1069px body the
## row is 799 and the column's slack under the player is 327, so a permanent 439px picker
## left `focus_stack_height` 16px — under its 64px collapse floor — and the frameset controls
## a thumbnail click retargets simply never appeared. ("When I click on a thumbnail I don't
## see the frameset controls now.")
func _colour_picker_wanted() -> bool:
	# A SELECTED AGE, not a selected keyframe. That widened on 2026-08-20 with the two-step
	# gesture: an interpolated age is a perfectly good thing to have selected — it is the
	# state the ⬥ button acts on — and the picker is how you see and choose its colour.
	return _sequence_life_column != null and _sequence_life_column.visible \
		and _colour_selected_frame >= 0


## Seed the picker to the selected keyframe and name the frame it is authoring, then re-stack
## the column if the panel's WANTED state just flipped — appearing and disappearing is the
## whole point of it, and the frameset block below it has to get the space back.
func _update_colour_picker_panel() -> void:
	if _colour_picker_panel == null:
		return
	var was: bool = _colour_picker_panel.visible
	var frame := _colour_selected_frame
	var sel := _colour_index_of_frame(frame)
	if frame >= 0:
		# SEED WITHOUT FIRING A PICK. `seed_muxed` is the whole reason the picker has a seam
		# instead of `color = c`: the setter emits `color_changed`, which would author the
		# colour it just displayed and mint an undo entry for opening a panel. That mattered
		# more than ever now — an unseamed setter on an INTERPOLATED age would key it just by
		# being looked at, which is the whole thing the two-step gesture removes.
		#
		# THE SEED IS THE CURVE, NOT THE RIBBON (ADR-0089 decision 4, amended 2026-08-21). One
		# expression covers a keyframe and an interpolated age alike, because `curve_at` IS the
		# interpolation `compile_to_curves` performs — so the grid opens on exactly the value the
		# compile would write there, keyframe or not.
		#
		# It used to read the RESOLVED RIBBON for an interpolated age, which was right while the
		# picker authored the muxed output: `colors()` is the array the column paints from, so
		# the swatch and the cell under the cursor agreed by construction. They no longer do, and
		# that is the amendment rather than a regression — the swatch is the curve and the cell
		# is the render. The RENDERS-AS row is where they are shown to agree.
		#
		# Seeding from the ribbon was also the FIGHT the author hit: this runs on every drag
		# frame, and the ribbon's colour is the muxed one, so each mouse-move toward a bright
		# colour was overwritten by the darker achieved value and the grid crawled back under
		# the cursor. `seed_curve` clamps to the unit cube only, so a re-seed mid-drag now
		# installs what the author just picked.
		var seed: Color = Color.WHITE
		if not _colour_keyframes.is_empty():
			seed = ColourKeyframeFit.curve_at(_colour_keyframes, frame)
		_colour_picker.seed_curve(seed)
		# THE TITLE SAYS WHICH STATE THIS AGE IS IN. Without it the picker looks identical on
		# a keyframe and on an interpolated age, and the ⬥ button's enabled-ness would be the
		# only clue that a pick is live or a preview.
		_colour_picker_title.text = "Colour · frame %d of %d · %s" \
			% [frame, int(_sequence_colour_window.get("n", 0)),
				"keyframe" if sel >= 0 else "interpolated"]
		if _colour_key_button != null:
			_colour_key_button.disabled = sel >= 0
			_colour_key_button.text = "⬥ keyframe" if sel >= 0 else "⬥ Set keyframe"
	_sync_colour_renders_as()
	# `_relayout` decides the panel's visibility (it owns the column's height budget); this
	# only asks for one when the answer would change. Guarded, because a recolour calls
	# through here on every drag frame and an unguarded re-stack per frame is a freeze.
	if was != _colour_picker_wanted():
		_relayout()


## Kept as the seam `show_target` calls; the widgets it used to find are the page's now, and
## the column binds them from `_update_sequence_canvas` instead. It survives as the hook that
## re-syncs the picker after a reproject rebuilt the inspector under a live selection.
func _wire_colour_author() -> void:
	_update_colour_picker_panel()


## Index into `_colour_keyframes` of the keyframe at particle-age `frame`, or -1.
func _colour_index_of_frame(frame: int) -> int:
	if frame < 0:
		return -1
	for i in range(_colour_keyframes.size()):
		if int(_colour_keyframes[i]["frame"]) == frame:
			return i
	return -1


## The colour to seed the picker with: the selected keyframe's, else the first keyframe's, else white.
func _colour_seed(sel: int) -> Color:
	if sel >= 0 and sel < _colour_keyframes.size():
		return _colour_keyframes[sel]["color"]
	if not _colour_keyframes.is_empty():
		return _colour_keyframes[0]["color"]
	return Color.WHITE


## The emitter the colour surface is authoring. STAMPED by `_update_sequence_ribbon`, never
## re-derived — the same discipline `_sequence_bound` is under and for the same reason: an
## emitter index used as anything else here is invisible, because every wrong answer is also
## a real emitter with real curves.
func _colour_emitter_index() -> int:
	return _sequence_colour_emitter


## Clicked a column: make that AGE the selected one and seed the picker to the colour there.
## Pure selection — no host edit, no reproject, and since 2026-08-20 no keyframe either. The
## age may well be interpolated; that is the state the ⬥ button exists to act on.
##
## `frame == -1` is a DESELECT (a second click on the selected cell), which is also how the
## picker closes.
func _on_colour_frame_selected(frame: int) -> void:
	if frame < 0:
		_clear_colour_selection()
		return
	_colour_selected_frame = frame
	# PUSH IT BACK TO THE COLUMN. Redundant when the click came FROM the column (it set its
	# own `_selected_frame` before emitting) and load-bearing when it did not: the strip's
	# right-click reaches this the same way, and without this line that route moved the page
	# state and the picker while the ribbon showed no selection at all.
	if _sequence_life_column != null:
		_set_life_selection(frame)
	_update_colour_picker_panel()


## ⬥ THE SECOND STEP: lock the selected age in as a real keyframe, at the colour the picker
## is currently showing.
##
## Structural (it mints a curve control point), so it reprojects — unlike a recolour, which
## refreshes in place so a live picker drag survives. Ordered add-then-author because
## `studio_author_colour` writes a colour AT a keyframe: with no keyframe there yet it would
## have nowhere to land.
func _on_colour_set_keyframe() -> void:
	var em := _colour_emitter_index()
	if em < 0 or _host == null or not _host.has_method("studio_colour_add"):
		return
	var frame := _colour_selected_frame
	if frame < 0 or _colour_index_of_frame(frame) >= 0:
		return   # nothing selected, or it is already a keyframe
	_host.studio_colour_add(em, frame)
	if _colour_picker != null and _host.has_method("studio_author_colour"):
		_host.studio_author_colour(em, frame, _colour_picker.picked())
	_colour_selected_frame = frame
	_render_current()


## Drop the colour selection and close the picker with it. ONE place, because the selection
## has three ways out — a second click on the cell, Esc, and deselecting the whole target —
## and a picker that only half-closes (state cleared, cell still outlined) is the fault this
## is fixing, not a smaller version of it.
##
## Returns true only when it actually cleared something, so an Esc that found nothing stays
## free to fall through to the next stage.
##
## IT TESTS THE FRAME, NOT WHETHER IT IS A KEYFRAME (2026-08-20). It used to ask
## `_colour_index_of_frame(...) >= 0`, which was the same question while only keyframes could
## be selected; with the two-step gesture an interpolated selection is the common case, and
## that test would have reported "nothing to clear" while the picker was plainly up — so Esc
## would have fallen straight through and torn down the whole screen instead.
func _clear_colour_selection() -> bool:
	if _colour_selected_frame < 0:
		return false
	_colour_selected_frame = -1
	if _sequence_life_column != null:
		_set_life_selection(-1)
	_update_colour_picker_panel()
	return true


## Right-clicked a real handle → remove that keyframe (ADR-0089 editing-UX amendment, decision 4).
## The curve interps across the gap; re-adding is trivial. Structural, so reproject to redraw.
func _on_colour_kf_remove(index: int) -> void:
	if index < 0 or index >= _colour_keyframes.size():
		return
	_delete_colour_keyframe(int(_colour_keyframes[index]["frame"]))


## True when Del should remove a colour keyframe: the colour editor is present AND a REAL keyframe
## (one at the selected particle-age) is selected. The pure key match is _is_colour_delete_shortcut.
func _colour_delete_available() -> bool:
	return _sequence_life_column != null and _sequence_life_column.visible \
		and _colour_index_of_frame(_colour_selected_frame) >= 0


## Delete the colour keyframe at particle-age `frame` via the host session (the curve interps
## across the gap). Clears the selection when it was the deleted one, then reprojects to redraw.
func _delete_colour_keyframe(frame: int) -> void:
	var em := _colour_emitter_index()
	if em < 0 or _host == null or not _host.has_method("studio_colour_delete"):
		return
	_host.studio_colour_delete(em, frame)
	if _colour_selected_frame == frame:
		_colour_selected_frame = -1
	_render_current()


## Picked a colour: recolour the selected keyframe. The host forks + compiles + repaints the
## burst; refresh the ribbon + column markers IN PLACE (no full reproject, so a live picker
## drag survives).
##
## IT AUTHORS ONLY A REAL KEYFRAME (2026-08-20). On an interpolated age this returns without
## touching anything and the picker is a PREVIEW — the author chose the explicit-button-only
## rule with that cost stated: *"nothing keys implicitly."* The ⬥ button reads
## `_colour_picker.picked()` when it commits, so the colour you were dragging is the colour
## you get; nothing is lost by not writing it here.
##
## The `_colour_selected_frame < 0 → author age 0` fallback is GONE with it. It existed for a
## picker that was permanently up with nothing selected, which cannot happen now, and it was
## the one path that could write a keyframe the author had not pointed at.
func _on_colour_authored(curve: Color) -> void:
	# THE READ-OUT FOLLOWS THE GRID EVEN WHEN NOTHING IS AUTHORED, and it has to be updated
	# before the two early returns below rather than after them: on an INTERPOLATED age the
	# ⬥ gesture means a pick writes nothing (author, 2026-08-20), so the returns are the
	# COMMON path while the author is deciding — which is exactly when they want to know what
	# the colour under the cursor will render as.
	_sync_colour_renders_as()
	var em := _colour_emitter_index()
	if em < 0 or _host == null or not _host.has_method("studio_author_colour"):
		return
	if _colour_index_of_frame(_colour_selected_frame) < 0:
		return
	_host.studio_author_colour(em, _colour_selected_frame, curve)
	_refresh_colour_editor_live(em)


## Paint the RENDERS-AS swatch from what is in the grid: `S ⊙ curve`, the multiply the shader
## and the ribbon both do. The picker owns the maths (it is the thing holding the gamut), so
## this is a two-line push rather than a second resolve — a second one is the drift ADR-0103
## dec. 1 forbids, and this surface exists precisely to state a relationship, not to compute
## a rival one.
##
## The label carries the dead channels when the sprite has any. `dead_channels()` was written
## as "informational … callers use it to explain the limit" and then had NO caller for the
## whole life of the muxed picker — the explanation was built and never wired, which is this
## family's recurring shape. This is the wiring.
func _sync_colour_renders_as() -> void:
	if _colour_picker == null or _colour_renders_as == null:
		return
	_colour_renders_as.color = _colour_picker.renders_as()
	if _colour_renders_as_label != null:
		var tag: String = _colour_picker.dead_channel_tag()
		_colour_renders_as_label.text = "renders as" if tag == "" else "renders as · " + tag
		_colour_renders_as_label.tooltip_text = _colour_picker.dead_channel_note()
		_colour_renders_as.tooltip_text = _colour_renders_as_label.tooltip_text


## Re-feed the ribbon with the emitter's CURRENT (forked) curves and refresh the track markers,
## without rebuilding the inspector — the live in-place repaint for a recolour.
func _refresh_colour_editor_live(emitter_index: int) -> void:
	if _inspector == null or _effect_data == null:
		return
	var ribbon = _sequence_ribbon
	if ribbon == null or emitter_index < 0 or emitter_index >= _effect_data.emitters.size():
		return
	var em = _effect_data.emitters[emitter_index]
	var ri := int(em.color_curves.get("r", -1))
	var gi := int(em.color_curves.get("g", -1))
	var bi := int(em.color_curves.get("b", -1))
	var cr = _effect_data.get_curve(ri)
	var cg = _effect_data.get_curve(gi)
	var cb = _effect_data.get_curve(bi)
	if cr != null and cg != null and cb != null:
		ribbon.set_curves(cr, cg, cb, true, ribbon.used_n(), true, ribbon.sprite_base())
		ribbon.visible = false   # headless — see its build comment
	# Re-feed the three `Color (R/G/B) · curve` sparklines + curve_pick labels on the LEFT with
	# the forked curves — the recolour un-aliases r=g=b onto fresh indices, so a snapshot goes
	# stale ("the curves on the left aren't updating"). ADR-0089 editing-UX amendment, decision 5.
	_inspector.refresh_colour_channels({"r": ri, "g": gi, "b": bi}, _curve_samples)
	if _sequence_life_column != null and _host != null \
			and _host.has_method("studio_colour_keyframes"):
		var state: Dictionary = _host.studio_colour_keyframes(emitter_index)
		_colour_keyframes = state.get("keyframes", [])
		# The COLOURS move too, not just the handles — a recolour changes the band the
		# author is looking at, and this is the live path that must not reproject (it
		# would rebuild the picker out from under a drag).
		_bind_life_column()
		# The picker's TITLE names the frame it is authoring, so it has to follow a live
		# recolour too — the frame did not change, but the window it is stated against can
		# (a lifetime edit reprojects through here).
		_update_colour_picker_panel()


## The emitter-elapsed playhead marker for the CURRENT target (ADR-0089 amendment): pure
## geometry from the live playhead + the selected firing's start/end (CurvePlayheadMarker).
## A span target resolves a marker; a browsed/drilled emitter (no governing firing) returns
## an absent marker carrying the "select this emitter's span" hint; anything else is absent.
func _marker_for_target() -> Dictionary:
	if _timeline == null or _nav.is_empty():
		return PlayheadMarker.absent()
	var target: Dictionary = _nav.back()
	match Target.kind(target):
		"span":
			var span := Model.find_span(_timeline._score, str(Target.ref(target).get("span_id", "")))
			if span.is_empty():
				return PlayheadMarker.absent()
			return PlayheadMarker.resolve(_timeline.get_playhead(),
				int(span.get("start", 0)), int(span.get("end", 0)))
		"emitter":
			var hint := PlayheadMarker.absent()
			hint["hint"] = "select this emitter's span"
			return hint
	return PlayheadMarker.absent()


## Refresh the playhead marker on the inspector sparklines + the painter WITHOUT a rebuild —
## the continuous cadence (ADR-0089 amendment): called each transport tick / scrub so the
## marker sweeps across the curves over a looped region. Cheap (queue_redraw only).
func _refresh_playhead_marker() -> void:
	var m := _marker_for_target()
	if _inspector != null:
		_inspector.update_marker(m)
	if _painter != null:
		_painter.set_marker(m)


## The nav stack projected for the PATH BAR — `[{label, target}, …]` root-first, the last
## entry the current target (the bar marks it and renders it inert). ADR-0073's trail, but
## the WHOLE path: as header rows it deliberately stopped at the parent, because the
## inspector's own title said where you were. A strip has no title under it, so a trail
## that stops one short doesn't read as "where am I" — see EffectPathBar.
func _path_crumbs(score: Dictionary) -> Array:
	# A SEEDED CHAIN HAS NO TRAIL (ADR-0073 dec. 11). Its entries
	# are not a path the author walked — they are all rendered on the page below, so
	# "Event › Container › Pair" would name three surfaces you are already looking at.
	# That is chrome describing itself, not navigation; and the crumbs would be dead
	# besides, since a click on one is a scroll rather than a step back.
	if _nav_chain:
		return []
	var crumbs: Array = []
	for t in _nav:
		crumbs.append({"label": Target.label(t, _effect_data, score), "target": t})
	return crumbs


## Push the current path into the bar. Called from every place the stack or the document
## moves — a render, a deselect (which does NOT render), a fresh effect load.
func _update_path_bar() -> void:
	if _path_bar == null:
		return
	var was_visible: bool = _path_bar.visible
	_path_bar.visible = _effect_data != null
	var score: Dictionary = _timeline._score if _timeline else {}
	_path_bar.set_path("E%03d" % _current_id if _effect_data != null else "",
		_path_crumbs(score))
	if _path_bar.visible != was_visible:
		_relayout()   # the bar's row appeared/vanished — everything below it moves


## Step back exactly ONE level (the `‹` button, Alt+Left). A no-op at the root: the bar
## disables `‹` there, but the shortcut has no such gate, and stepping off the root would
## mean deselecting — which is Esc's job, not this one's (the two gestures stay distinct).
## Returns true when it moved, so the key handler consumes only a meaningful Alt+Left.
func _step_back() -> bool:
	if _nav.size() < 2:
		return false
	_navigate_to(_nav[_nav.size() - 2])
	return true


## Right-clicked a keyframe span: pop the context menu at the cursor. The span is already
## selected (the timeline did that) so the inspector shows what's addressed. The menu is
## rebuilt from the lane verbs this span offers at `frame` (Add here / Delete — camera only
## this pass) plus the always-available Copy-address item.
func _on_span_context(span_id: String, frame: int) -> void:
	_ctx_span_id = span_id
	if _ctx_menu == null or _timeline == null:
		return
	var span := Model.find_span(_timeline._score, span_id)
	_ctx_actions = _lane_context_actions(span, frame)
	_ctx_menu.clear()
	for i in range(_ctx_actions.size()):
		_ctx_menu.add_item(String(_ctx_actions[i]["label"]), i + 1)
	if not _ctx_actions.is_empty():
		_ctx_menu.add_separator()
	_ctx_menu.add_item("Copy keyframe address", CTX_COPY_ADDRESS)
	_ctx_menu.reset_size()
	_ctx_menu.position = DisplayServer.mouse_get_position()
	_ctx_menu.popup()


## Right-clicked a lane row's EMPTY space (a gap): pop the lane-level gap menu. Sound
## offers "Add sound event here" (events are instants — the gap IS the add surface);
## particle offers "Add span here" (ADR-0089); a colour lane's empty space is an
## invisible SPACER offering "Add event here" (ADR-0087 decs. 23-28). No span is
## addressed, so no selection change and no Copy-address item; lanes with no gap
## verbs open nothing.
func _on_lane_context(lane_id: String, frame: int) -> void:
	_ctx_span_id = ""
	if _ctx_menu == null or _timeline == null:
		return
	var lane := _find_lane(_timeline._score, lane_id)
	var kind: String = String(lane.get("kind", ""))
	if lane.is_empty() or not (kind in ["sound", "particle", "palette", "screen", "camera"]):
		return
	if kind == "sound":
		# Sound's gap IS the add surface (offset comes off the lane's projected spans
		# inside _gap_context_actions).
		_ctx_actions = _gap_context_actions(lane, frame)
	else:
		# Phase-offset the score-absolute cursor off the lane row's phase band — derive
		# it from the lane, not a span, since a gap has none.
		var phase: String = String(lane.get("phase", ""))
		var local_frame: int = frame - _phase_start(phase)
		if kind == "particle":
			_ctx_actions = _lane_gap_context_actions(phase, int(lane.get("channel_index", -1)), local_frame)
		elif kind == "camera":
			_ctx_actions = _camera_spacer_gap_actions(lane, local_frame)
		else:
			_ctx_actions = _colour_spacer_gap_actions(lane, local_frame)
	if _ctx_actions.is_empty():
		return
	_ctx_menu.clear()
	for i in range(_ctx_actions.size()):
		_ctx_menu.add_item(String(_ctx_actions[i]["label"]), i + 1)
	_ctx_menu.reset_size()
	_ctx_menu.position = DisplayServer.mouse_get_position()
	_ctx_menu.popup()


## The score lane by id, or {}.
static func _find_lane(score: Dictionary, lane_id: String) -> Dictionary:
	for lane in score.get("lanes", []):
		if String(lane.get("id", "")) == lane_id:
			return lane
	return {}


## The score-absolute start frame of a phase section — the offset a phase-local frame adds to.
## Reads the score's phase bands (start == EffectScoreModel.phase_offset). 0 if the phase is
## absent (only phases with at least one lane get a band).
func _phase_start(phase: String) -> int:
	if _timeline == null:
		return 0
	for sec in _timeline._score.get("phases", []):
		if String(sec.get("name", "")) == phase:
			return int(sec.get("start", 0))
	return 0


func _on_ctx_menu_id(id: int) -> void:
	if id == CTX_COPY_ADDRESS:
		_copy_keyframe_address()
		return
	var idx: int = id - 1
	if idx < 0 or idx >= _ctx_actions.size():
		return
	_run_lane_verb(_ctx_actions[idx])


func _copy_keyframe_address() -> void:
	if _timeline == null:
		return
	var span := Model.find_span(_timeline._score, _ctx_span_id)
	var addr := Model.keyframe_address(_effect_label(), span)
	if addr != "":
		DisplayServer.clipboard_set(addr)


## Run a lane verb (Add/Delete) through the host's EffectEditSession choke point, then — for
## a structural result — re-project the same document (preserving the transport) and land the
## selection on the new (add) / neighbour (delete) event by its §#286 ordinal. Mirrors
## _apply_edit's structural branch; the verbs are the insert-waypoint / delete counterparts.
## The context-menu verbs for a right-click on the FEDS pair band (ADR-0085 amendment
## 2026-08-18b §2: the panel navigates AND composes; the inspector still owns parameter
## editing). `ctx` is FedsPairLanePanel.context_at's resolved byte boundary.
##
## Two entries at most, and both NAME what the click resolved to — "Add opcode after
## `Oct3` @ tick 0", never a silent pick among the four events that can share a tick
## (§4). The Add row carries `options`: the corpus menu (§7), which the popup builder
## hangs off it as a submenu. The second row is the span's ONE time verb: Delete on a
## note (which means putting a rest there), the un-rest on a rest (2026-08-19).
##
## Pure so the choice is guarded without a scene, like `_lane_context_actions`.
static func _pair_context_actions(ctx: Dictionary, clip: Dictionary = {}) -> Array:
	# A resolution that found no bytes says which place it found instead (2026-08-19e §1).
	# One disabled row, no verb: the popup still opens, so the gesture is answered rather
	# than swallowed, and there is nothing on it that could be run.
	var refused: String = str(ctx.get("refused", ""))
	if refused != "":
		return [{"label": refused, "verb": "", "disabled": true}]
	if ctx.is_empty() or int(ctx.get("track_idx", -1)) < 0:
		return []
	var anchor: Dictionary = ctx.get("anchor", {})
	# A multi-segment span owns TWO boundaries and the bar draws them as one picture, so
	# each row has to say which one it is (2026-08-19f). `at` is the boundary after the head
	# NOTE byte — inside the bar, and the tick it fires at is the span's start plus the
	# note's own ticks, never the anchor's tick, which is what the old "after `C4` @ tick 0"
	# row said while writing at tick 12.
	var span_end: Dictionary = ctx.get("span_end", {})
	var where: String
	if anchor.is_empty():
		where = "at the start of this track"
	elif not span_end.is_empty():
		where = "inside `%s` — before its %s, @ tick %d" % [str(anchor.get("label", "?")),
				str(span_end.get("label", "Fermata")), int(span_end.get("inside_tick", 0))]
	else:
		where = "after `%s` @ tick %d" % [str(anchor.get("label", "?")), int(anchor.get("tick", 0))]
	var base_ref := {"channel": "sound_def", "pair_idx": int(ctx.get("pair_idx", -1)),
			"track_idx": int(ctx.get("track_idx", -1)), "at": int(ctx.get("at", -1))}
	var out: Array = [{
		"label": "Add opcode %s" % where,
		"verb": "insert",
		"field_ref": base_ref,
		"options": FedsCatalog.insert_menu(bool(ctx.get("phantom_boundary", false))),
		# The corpus submenu is where an author goes looking for "add a note", and it is
		# the one place the refusal can be explained at the moment of the wrong guess
		# (2026-08-19e §3). A note is not an opcode — it is a velocity byte below 0x80 —
		# and time is fully tiled (18c), so a note can only be TAKEN from a neighbour.
		# Both ways of taking it are compositions the surface never named; here they are.
		"options_header": [
			"A note is not an opcode — there is no row that adds one.",
			"    Inside the track:  Delete a span, then sound the rest it leaves.",
			"    Past the end:  Extend the track, then sound the new silence.",
		],
	}]
	# …and the boundary PAST the span's last segment, which had no click target of its own
	# because a fermata is drawn as the bar's tail rather than as a chip.
	if not span_end.is_empty():
		var end_ref := base_ref.duplicate()
		end_ref["at"] = int(span_end.get("at", -1))
		out.append({
			"label": "Add opcode after `%s`'s %s @ tick %d" % [str(anchor.get("label", "?")),
					str(span_end.get("label", "Fermata")), int(span_end.get("tick", 0))],
			"verb": "insert",
			"field_ref": end_ref,
			"options": FedsCatalog.insert_menu(bool(span_end.get("phantom_boundary", false))),
			"options_header": (out[0] as Dictionary)["options_header"],
		})
	# The PASTE (2026-08-19e §2), the other half of the cut, offered wherever a boundary
	# resolved. BOTH directions, because neither is derivable from the other on a surface
	# where zero-tick opcodes stack: "before `Oct3`" is Oct3's own first byte and "after
	# `Oct3`" is the boundary past it — 18b §4's two endpoints, said out loud. The bytes
	# are the ones that were cut, so a re-order keeps the params the author typed.
	if not clip.is_empty():
		var clip_label: String = str(clip.get("label", "?"))
		var sites: Array = []
		if anchor.is_empty():
			sites.append(["at the start of this track", int(ctx.get("at", -1))])
		else:
			var aname := "`%s` @ tick %d" % [str(anchor.get("label", "?")),
					int(anchor.get("tick", 0))]
			sites.append(["before " + aname, int(ctx.get("before_at", -1))])
			if span_end.is_empty():
				sites.append(["after " + aname, int(ctx.get("at", -1))])
			else:
				# The same two boundaries the Add rows split, named the same way: a paste
				# INSIDE the span is where 3151 of the corpus's interior opcodes live, and a
				# paste after the last segment is where the other 1534 sit.
				sites.append(["inside `%s` — before its %s" % [str(anchor.get("label", "?")),
						str(span_end.get("label", "Fermata"))], int(ctx.get("at", -1))])
				sites.append(["after `%s`'s %s" % [str(anchor.get("label", "?")),
						str(span_end.get("label", "Fermata"))], int(span_end.get("at", -1))])
		for site in sites:
			var p_ref := base_ref.duplicate()
			p_ref["at"] = int(site[1])
			p_ref["opcode"] = int(clip.get("opcode", -1))
			p_ref["params"] = clip.get("params", PackedByteArray())
			out.append({"label": "Paste `%s` %s" % [clip_label, str(site[0])],
				"verb": "insert", "field_ref": p_ref})
	var del: Dictionary = ctx.get("delete", {})
	if not del.is_empty():
		var del_ref := base_ref.duplicate()
		del_ref["at"] = int(del.get("at", -1))
		# A delete on a SPAN leaves silence of exactly its length, and that silence is the
		# currency the paint spends (2026-08-19e §3). Naming the number turns "Delete" into
		# the first half of a composition the author can see through, instead of a verb
		# whose consequence only the ADR records. A zero-tick opcode leaves nothing, and
		# its row stays the bare "Delete `X`".
		var del_ticks: int = int(del.get("ticks", 0))
		var del_label: String = "Delete `%s`" % str(del.get("label", "?"))
		if del_ticks > 0:
			del_label += " — leaves %d ticks of silence to sound" % del_ticks
		out.append({"label": del_label, "verb": "delete", "field_ref": del_ref})
	# The CUT: delete's re-orderable twin. It runs the SAME delete verb and then remembers
	# the bytes, so it needs no case in either dispatch seam — the clipboard is the page's.
	var cut: Dictionary = ctx.get("cut", {})
	if not cut.is_empty():
		var cut_ref := base_ref.duplicate()
		cut_ref["at"] = int(cut.get("at", -1))
		out.append({"label": "Cut `%s` — to paste at another boundary" % str(cut.get("label", "?")),
			"verb": "cut", "field_ref": cut_ref,
			"clip": {"opcode": int(cut.get("opcode", -1)),
				"params": cut.get("params", PackedByteArray()),
				"label": str(cut.get("label", "?"))}})
	# The grey bar's own time verb (ADR-0085 2026-08-19): delete's inverse, named for what
	# it writes — a note of the rest's exact length, at the corpus's velocity and key.
	var unrest: Dictionary = ctx.get("unrest", {})
	if not unrest.is_empty():
		var un_ref := base_ref.duplicate()
		un_ref["at"] = int(unrest.get("at", -1))
		out.append({"label": "Sound `%s` — C, %d ticks"
				% [str(unrest.get("label", "?")), int(unrest.get("ticks", 0))],
			"verb": "unrest", "field_ref": un_ref})
	# The PAINT (2026-08-19b §2/§6): a note INSIDE the silence, starting where the author
	# grabbed. The row names both numbers it will write, as the un-rest names its one —
	# and the un-rest row stays beside it, because it is the precise, zoom-independent way
	# to say "all of it".
	var paint: Dictionary = ctx.get("paint", {})
	if not paint.is_empty():
		var paint_ref := base_ref.duplicate()
		paint_ref["at"] = int(paint.get("at", -1))
		paint_ref["offset_ticks"] = int(paint.get("offset_ticks", 0))
		paint_ref["duration_ticks"] = int(paint.get("duration_ticks", 0))
		out.append({"label": "Sound `%s` from +%d — C, %d ticks"
				% [str(paint.get("label", "?")), int(paint.get("offset_ticks", 0)),
					int(paint.get("duration_ticks", 0))],
			"verb": "paint", "field_ref": paint_ref})
	# The OUTRO (2026-08-19c §4): the track's END, offered as the two things that can be done
	# to it. Extend hangs the corpus's own 18 delta-time values off a submenu, the way the Add
	# row hangs the opcode corpus — zoom-independent and exact, because there is no bar past
	# the end to drag and the axis would rescale under the cursor if there were. Trim appears
	# only when there IS trailing silence, and it says the number it is removing.
	var outro: Dictionary = ctx.get("outro", {})
	if not outro.is_empty():
		var otick: int = int(outro.get("ticks", 0))
		var oref := {"channel": "sound_def", "pair_idx": int(ctx.get("pair_idx", -1)),
				"track_idx": int(ctx.get("track_idx", -1))}
		out.append({
			"label": "Extend the track — %d ticks of silence before the end" % otick,
			"verb": "outro", "field_ref": oref, "outro_options": _outro_options(otick)})
		if otick > 0:
			var trim_ref: Dictionary = oref.duplicate()
			trim_ref["outro_ticks"] = 0
			out.append({"label": "Trim the trailing silence — %d ticks → 0" % otick,
				"verb": "outro", "field_ref": trim_ref})
	return out


## The extend submenu: the corpus's own `DELTA_TIME_TABLE` lengths, shortest first, each
## named in ticks AND beats because 48 ticks is one beat and neither number alone reads.
## The rows carry the ABSOLUTE result (`current + step`), so the arithmetic lives here and
## the verb keeps taking one number.
static func _outro_options(current: int) -> Array:
	var steps: Array = []
	for v in ExMateriaSound.SoundOpcodes.DELTA_TIME_TABLE:
		if int(v) > 0:
			steps.append(int(v))
	steps.sort()
	var out: Array = []
	for v in steps:
		out.append({"ticks": v, "outro_ticks": current + v,
			"label": "+%d ticks  (%s beat)" % [v,
				String.num(float(v) / 48.0, 2).pad_decimals(2)]})
	return out


func _on_pair_context(ctx: Dictionary) -> void:
	_ctx_span_id = ""
	if _ctx_menu == null:
		return
	_ctx_actions = _pair_context_actions(ctx, _feds_clip)
	if _ctx_actions.is_empty():
		return
	_ctx_menu.clear()
	if _pair_add_menu == null:
		# The corpus menu is 51 entries long; it hangs off the Add row as a submenu so
		# the two verbs still read as one short list (§2: one place to look).
		_pair_add_menu = PopupMenu.new()
		_pair_add_menu.name = "FedsAddOpcode"
		_pair_add_menu.id_pressed.connect(_on_pair_add_menu_id)
		_ctx_menu.add_child(_pair_add_menu)
	if _pair_outro_menu == null:
		_pair_outro_menu = PopupMenu.new()
		_pair_outro_menu.name = "FedsOutroSteps"
		_pair_outro_menu.id_pressed.connect(_on_pair_outro_menu_id)
		_ctx_menu.add_child(_pair_outro_menu)
	for i in range(_ctx_actions.size()):
		var action: Dictionary = _ctx_actions[i]
		if action.has("outro_options"):
			_pair_outro_opts = action["outro_options"]
			_pair_outro_ref = action["field_ref"]
			_pair_outro_menu.clear()
			for j in range(_pair_outro_opts.size()):
				_pair_outro_menu.add_item(str((_pair_outro_opts[j] as Dictionary)["label"]), j)
			_ctx_menu.add_submenu_node_item(String(action["label"]), _pair_outro_menu)
		elif action.has("options"):
			_pair_add_opts = action["options"]
			_pair_add_ref = action["field_ref"]
			_pair_add_menu.clear()
			# The header (2026-08-19e §3): why there is no "add a note" row here, and the
			# two compositions that are the answer. Disabled and ahead of the corpus, so it
			# is read exactly when the author comes looking for the row that does not exist.
			for line in (action.get("options_header", []) as Array):
				_pair_add_menu.add_item(String(line), -1)
				_pair_add_menu.set_item_disabled(_pair_add_menu.item_count - 1, true)
			if _pair_add_menu.item_count > 0:
				_pair_add_menu.add_separator()
			for j in range(_pair_add_opts.size()):
				var o: Dictionary = _pair_add_opts[j]
				# Coverage rides every row: the ordering IS the corpus, said out loud.
				_pair_add_menu.add_item("%s  (%d tracks)" % [str(o["label"]), int(o["tracks"])], j)
			_ctx_menu.add_submenu_node_item(String(action["label"]), _pair_add_menu)
		else:
			_ctx_menu.add_item(String(action["label"]), i + 1)
			if bool(action.get("disabled", false)):
				_ctx_menu.set_item_disabled(_ctx_menu.item_count - 1, true)
	_ctx_menu.reset_size()
	_ctx_menu.position = DisplayServer.mouse_get_position()
	_ctx_menu.popup()


## A length was picked out of the extend submenu: set the track's outro to the ABSOLUTE
## count that row already worked out (current + step), so the verb still takes one number.
func _on_pair_outro_menu_id(id: int) -> void:
	if id < 0 or id >= _pair_outro_opts.size():
		return
	var ref: Dictionary = _pair_outro_ref.duplicate()
	ref["outro_ticks"] = int((_pair_outro_opts[id] as Dictionary)["outro_ticks"])
	_run_lane_verb({"verb": "outro", "field_ref": ref})


## An opcode was picked out of the corpus submenu: run the insert with that opcode and
## its corpus-mode parameters.
func _on_pair_add_menu_id(id: int) -> void:
	if id < 0 or id >= _pair_add_opts.size():
		return
	var opt: Dictionary = _pair_add_opts[id]
	var ref: Dictionary = _pair_add_ref.duplicate()
	ref["opcode"] = int(opt["opcode"])
	ref["params"] = opt["params"]
	_run_lane_verb({"verb": "insert", "field_ref": ref})


## The FEDS lane DRAG (ADR-0085 2026-08-19b §6), the three gestures the panel reports in
## ticks. The bracket is the whole point: `begin_coalesce` makes one gesture ONE undo whose
## restore is the pre-drag bank, and it is also what turns on the session's pristine re-plan,
## so every motion is planned against those bytes instead of compounding on the last one's
## splices — drag past a rest, drag back, the rest returns while the mouse is still held.
func _on_pair_drag_started(drag: Dictionary) -> void:
	if _host and _host.has_method("studio_begin_coalesce"):
		_host.studio_begin_coalesce(_pair_drag_ref(drag))


## The KEY ROLL's vertical drag (ADR-0085 amendment 2026-08-21d §7). It is NOT one of the
## three lane verbs: it writes the note data byte's upper field, which is the SAME
## `note_key` address the inspector's "Note key" dropdown already offers — a same-size,
## bounded parameter edit through the scalar choke point, not a structural splice. The roll
## is octave-agnostic, so the drag has no octave boundary to cross and the byte it patches
## is the only byte that moves.
static func _pair_key_ref(drag: Dictionary) -> Dictionary:
	# `at` is the note EVENT's blob-absolute head — its velocity byte. The key rides the
	# next byte (data = key × 19 + delta index), exactly as FedsPairProjector._note_fields
	# addresses it, so the drag and the dropdown write through one address, not two.
	return {"channel": "sound_def", "kind": "note_key",
			"offset": int(drag.get("at", -1)) + 1,
			"pair_idx": int(drag.get("pair_idx", -1))}


## Returns the verb's result so a caller can read back what the drag ACHIEVED after clamping
## (`delta_ticks`) — the gesture asks for the cursor, the law answers with the wall.
func _on_pair_dragged(drag: Dictionary) -> Dictionary:
	if str(drag.get("verb", "")) == "key":
		var key := int(drag.get("relative_key", -1))
		if key < 0 or int(drag.get("at", -1)) < 0:
			return {}
		_apply_edit(_pair_key_ref(drag), key)
		return {}
	return _run_lane_verb({"verb": str(drag.get("verb", "drag")),
			"field_ref": _pair_drag_ref(drag)})


func _on_pair_drag_ended() -> void:
	if _host and _host.has_method("studio_end_coalesce"):
		_host.studio_end_coalesce()


## PURE: the field_ref one motion of a lane drag lowers to. The address half is the grab's,
## resolved once and identical for every motion of the gesture — which is what keeps it valid
## after a motion has spliced a rest out from in front of the span (the session restores the
## pristine bytes before each re-dispatch, so the ORIGINAL offset is always the live one).
## The payload half is the gesture's: a paint takes two tick numbers, a move or a resize one
## signed delta.
static func _pair_drag_ref(drag: Dictionary) -> Dictionary:
	# A key drag is a SCALAR edit at a byte address, so its coalesce opens on that address
	# rather than on the lane-verb shape — one gesture, one undo, restoring the one byte.
	if str(drag.get("gesture", "")) == "key" or str(drag.get("verb", "")) == "key":
		return _pair_key_ref(drag)
	var ref := {
		"channel": "sound_def",
		"pair_idx": int(drag.get("pair_idx", -1)),
		"track_idx": int(drag.get("track_idx", -1)),
		"at": int(drag.get("at", -1)),
	}
	if str(drag.get("verb", "drag")) == "paint":
		ref["offset_ticks"] = int(drag.get("offset_ticks", 0))
		ref["duration_ticks"] = int(drag.get("duration_ticks", 0))
	else:
		ref["gesture"] = str(drag.get("gesture", "move"))
		ref["delta_ticks"] = int(drag.get("delta_ticks", 0))
	return ref


func _run_lane_verb(action: Dictionary) -> Dictionary:
	var verb: String = String(action.get("verb", ""))
	var field_ref: Dictionary = action.get("field_ref", {})
	var res = null
	# CUT is DELETE that remembers (2026-08-19e §2). It lowers to the existing delete verb
	# rather than a sixth sound_def case, so neither dispatch seam grows a branch — the
	# clipboard is a page concern, the bytes are already the author's, and the paste is the
	# insert that was always there. Stashed only on a delete that actually happened, so a
	# refused cut leaves the previous clipboard alone rather than emptying it.
	if verb == "cut":
		var stashed: Dictionary = _run_lane_verb({"verb": "delete", "field_ref": field_ref})
		if not stashed.is_empty():
			_feds_clip = action.get("clip", {})
		return stashed
	if verb == "insert" and _host and _host.has_method("studio_insert_event"):
		res = _host.studio_insert_event(field_ref)
	elif verb == "delete" and _host and _host.has_method("studio_delete_event"):
		res = _host.studio_delete_event(field_ref)
	elif verb == "unrest" and _host and _host.has_method("studio_unrest_event"):
		res = _host.studio_unrest_event(field_ref)
	elif verb == "paint" and _host and _host.has_method("studio_paint_event"):
		res = _host.studio_paint_event(field_ref)
	elif verb == "drag" and _host and _host.has_method("studio_drag_event"):
		res = _host.studio_drag_event(field_ref)
	elif verb == "outro" and _host and _host.has_method("studio_set_outro"):
		res = _host.studio_set_outro(field_ref)
	if not (res is Dictionary and res.get("structural", false)):
		return {}
	# A structural FEDS edit is SOUND, not the folded framebuffer: it re-derives the
	# pair views + ghosts the way a byte patch does and lands its selection inside the
	# pair band, not on a timeline span (ADR-0085 amendment 2026-08-18b).
	if String(field_ref.get("channel", "")) == "sound_def":
		_after_feds_structural(res)
		return res
	_rebuild_score()
	# Land the selection on the new (add) / neighbour (delete) event: sound addresses by
	# the result ordinal (folded by _verb_landing_span_id); every other channel through
	# _structural_result_span_id (camera by its §#286 sub-channel ordinal; palette / screen
	# by raw keyframe index; particle by phase + channel + index). An empty id (the lane
	# emptied) just re-renders the current target.
	var span_id := ""
	if String(field_ref.get("channel", "")) == "sound":
		var ordinal: int = int(res.get("ordinal", -1))
		if ordinal >= 0:
			span_id = _verb_landing_span_id(field_ref, ordinal)
	else:
		span_id = _structural_result_span_id(field_ref, res)
	if span_id != "":
		_timeline.select_span(span_id)
		_on_span_selected(span_id)
	else:
		_render_current()
	return res


## Re-derive after a structural FEDS edit (insert / delete of an opcode) and land the
## selection. This is `_commit_prune_noops`' choreography — the two are the same shape:
## a verb SWAPPED the whole FedsBank, so the cached env must be re-pointed at the live
## model's new bank before anything re-reads it, then the pair views, the pair's energy
## and no-op A/B proof, and the ghost + energy of every sound_id resolving into the pair
## all go stale together.
##
## §8: the selection lands on the NEW opcode after an insert (so "add an Instrument" and
## "set it to 42" are one motion) and on the anchor after a delete. Doing nothing is not
## an option — a resize shifts every later event_index, so the held selection would
## silently address a different event. The verb's `track_idx` is the GLOBAL bank index;
## the panel addresses its two lanes pair-locally.
func _after_feds_structural(res: Dictionary) -> void:
	if _effect_data == null:
		return
	var pair_idx := int(res.get("pair_idx", -1))
	if not _sound_env.is_empty():
		_sound_env["feds_bank"] = _effect_data.feds_bank
	_pair_views = _compute_pair_views()
	_pair_energy_cache.erase(pair_idx)
	_schedule_pair_energy(pair_idx)
	_invalidate_noop_ab(pair_idx)
	if not _sound_env.is_empty():
		var containers: Array = _sound_env["sound_containers"].get("containers", [])
		for ci in range(containers.size()):
			var sid: int = ci + 2
			if GhostProjector.resolve_pair_idx(_sound_env["sound_containers"], sid) == pair_idx:
				_ghost_by_sound_id.erase(sid)
				_energy_by_sound_id.erase(sid)
				_ghost_render_cache.erase(_ghost_cache_key(_current_dir, sid))
				_schedule_ghost_reproject(sid)
	_rebuild_score()
	if _pair_panel and pair_idx >= 0:
		_pair_panel.select_event(int(res.get("track_idx", -1)) - pair_idx * 2,
				int(res.get("event_index", -1)))
	_render_current()
	print("[Studio] pair %d track %d: %d → %d bytes (Save to persist)" % [
			pair_idx, int(res.get("track_idx", -1)),
			int(res.get("before_bytes", 0)), int(res.get("after_bytes", 0))])


## The span id to select after a structural verb, built from the edit's channel: camera uses
## the sub-channel ordinal, palette and screen the raw keyframe index. Empty when nothing to
## select.
func _structural_result_span_id(field_ref: Dictionary, res: Dictionary) -> String:
	match String(field_ref.get("channel", "")):
		"camera":
			var ordinal: int = int(res.get("ordinal", -1))
			if ordinal < 0:
				return ""
			return "camera:%s:%s#%d" % [String(field_ref.get("context", "")),
				String(field_ref.get("camera_channel", "")), ordinal]
		"palette":
			var index: int = int(res.get("event_index", -1))
			if index < 0:
				return ""
			return "palette:%s:%s#%d" % [String(field_ref.get("context", "")),
				String(field_ref.get("channel_name", "")), index]
		"screen":
			var index: int = int(res.get("event_index", -1))
			if index < 0:
				return ""
			return "screen:%s#%d" % [String(field_ref.get("context", "")), index]
		"particle":
			var index: int = int(res.get("event_index", -1))
			if index < 0:
				return ""
			return "particle:%s:%d#%d" % [String(field_ref.get("context", "")),
				int(field_ref.get("channel_index", -1)), index]
	return ""


## The effect dir name for the loaded effect (E317), the address's first token.
func _effect_label() -> String:
	return "E%03d" % _current_id if _current_id >= 0 else "E???"


func _on_seek_requested(frame: int) -> void:
	# Scrub path (ruler/lane drag). Move the playhead now (cheap) but COALESCE the
	# host seek to _process — see _pending_seek. Discrete transport (stop/step/
	# restart) still calls _seek() directly for an immediate, single seek.
	_playing = false
	_set_host_playing(false)
	_timeline.set_playhead(maxi(0, frame))
	_pending_seek = maxi(0, frame)
	_update_labels()


## The sparkline of a specific emitter param was clicked — open the freehand painter
## bound to THAT param's curve. The curve hangs off the param, so the title names it.
func _open_param_curve(curve_index: int, param_name: String, used_n: int = -1) -> void:
	if _effect_data == null:
		return
	var curve = _effect_data.get_curve(curve_index)
	if curve == null:
		return
	# The painter is bound to THIS USE SITE's own private curve (ADR-0089 curve-ownership
	# amendment) — leaving pacing mode and recording the address the commit lowers through.
	_painter_pacing_field = ""
	_painter_curve_index = curve_index
	_pacing_enable_check.visible = false
	# used_n is the SAME datum the row sparkline trims to (ADR-0089 curve-UX
	# amendment): the painter keeps all frames editable but veils the inactive tail.
	_painter.bind_curve(curve, 0, 255, used_n)
	# Seed the emitter-elapsed playhead marker on the freshly-bound curve (ADR-0089
	# amendment); the continuous cadence keeps sweeping it as the playhead moves.
	_painter.set_marker(_marker_for_target())
	# The param NAMES the curve — an index is an export concern, and after the explode it
	# is a private array position that means nothing to an author.
	_painter_title.text = param_name
	if _painter_note:
		_painter_note.text = "Painted live — saved to the effect (undoable)"
		_painter_note.modulate = Color(0.55, 0.72, 0.55)
	_refresh_shape_gauge()
	_painter_panel.visible = true


## The painter committed a curve-contents edit (mouse-up) — ONE stroke, ONE undo entry.
##
## Curve contents are PRIVATE to their use site since the ADR-0089 curve-ownership
## amendment, so this moves that one param on that one emitter and nothing else. (It used
## to mutate a SHARED curve and restyle every referring param — 70.8% of ROM curve slots
## have more than one referrer, so that was the common case, not the tail.)
##
## The painter reports the finished stroke rather than writing the bound curve, so the
## choke point still sees the PRE-edit samples and can snapshot them for undo. The whole
## inspector refreshes anyway: several rows can be looking at the same SHAPE even though
## they no longer share a curve, and the gauge moves.
func _on_curve_changed(values: Array = []) -> void:
	# Pacing mode (#270, ADR-0093): a 600-int curve on the time_scale channel. The pacing
	# curves were private before the amendment made every curve private, and they are still
	# the only ones whose edit also re-derives the end marker.
	if _painter_pacing_field != "":
		_commit_pacing_edit(_painter_pacing_field, values)
		return
	if _painter_curve_index >= 0 and not values.is_empty():
		_apply_edit({"channel": "curve", "curve_index": _painter_curve_index}, values)
	# A reshaped curve can split off a shape nothing else draws (or merge onto one), so the
	# budget moves with the stroke — this is the "watchable before export" half of decision 6.
	_refresh_shape_gauge()
	_rebuild_score()
	_render_current()
	if _timeline:
		_seek(_timeline.get_playhead())


## Refresh the shape gauge — distinct shapes in use / 15 (ADR-0089 curve-ownership
## amendment, decision 4). Hidden in pacing mode (those curves live in their own section
## and never enter the effect's curve table) and when nothing is loaded. Over budget reads
## warm, because that is what export will refuse on — and refusing is only fair while the
## number is watchable, which is the whole reason it is computed here and not only at save.
func _refresh_shape_gauge() -> void:
	if _painter_gauge == null:
		return
	if _effect_data == null or _painter_pacing_field != "":
		_painter_gauge.visible = false
		return
	var g: Dictionary = CurveShapeSet.gauge(_effect_data)
	_painter_gauge.visible = true
	_painter_gauge.text = CurveShapeSet.gauge_text(_effect_data)
	_painter_gauge.modulate = Color(0.95, 0.6, 0.45) if bool(g["over"]) else Color(0.6, 0.66, 0.78)


## Open the Time-Scale pop-up painter bound to `field`'s pacing curve (#270, ADR-0093). Builds a
## shared EffectCurve from the live 600-int curve (samples = value/10, lossless for the 0..10
## alphabet), binds it at Y-range 0..10 with the played window veiled past its tail, seeds the
## per-curve enable checkbox, and shows the panel. Reuses the one painter (mode = pacing).
func _open_pacing_painter(field: String) -> void:
	if _effect_data == null or not (_effect_data.time_scale is Dictionary) \
			or not (_effect_data.time_scale.get(field, null) is Array):
		return
	var ints: Array = _effect_data.time_scale[field]
	_pacing_curve = EffectCurveClass.new()
	_pacing_curve.samples.resize(ints.size())
	for i in range(ints.size()):
		_pacing_curve.samples[i] = clampf(float(ints[i]) / float(PACING_VMAX), 0.0, 1.0)
	_painter_pacing_field = field
	_painter_curve_index = -1   # pacing lowers through time_scale, not a use site's curve
	_refresh_shape_gauge()      # → hidden: pacing curves are not in the effect's curve table
	# Played window = the band's carried sample count (phase-1 duration / for-each region).
	var used_n := _pacing_window(field)
	_painter.bind_curve(_pacing_curve, 0, PACING_VMAX, used_n)
	_painter.set_marker({"present": false})
	_painter_title.text = "%s  —  freehand paint (0–10, baseline 2)" % _pacing_label(field)
	# The enable checkbox reflects this curve's flag bit; the note flips to the honest "saved".
	_pacing_enable_check.visible = true
	_pacing_enable_check.set_pressed_no_signal(_pacing_enabled(field))
	if _painter_note:
		_painter_note.text = "Painted live — saved to the effect (undoable)"
		_painter_note.modulate = Color(0.55, 0.72, 0.55)
	_painter_panel.visible = true


## Commit a whole painted pacing curve through the live session (undo + save) and re-render the
## band + preview. The time_scale edit invalidates_sim (pacing feeds tl.setup → EffectEndModel),
## so re-derive the end marker and re-seek to re-fold the preview at the parked frame.
func _commit_pacing_edit(field: String, ints: Array) -> void:
	if ints.is_empty():
		return   # nothing painted — never lower an empty curve over a real one
	_apply_edit({"channel": "time_scale", "field": field}, ints)
	_rebuild_score()
	_recompute_end_frame()
	_render_current()
	if _timeline:
		_seek(_timeline.get_playhead())


## The enable checkbox flipped — write this curve's effect_flags bit (5 = Phase 1 / 6 = For-each)
## through the same session, then re-render so the band greys/ungreys live.
func _on_pacing_enable_toggled(on: bool) -> void:
	if _painter_pacing_field == "":
		return
	_toggle_pacing_enable(_painter_pacing_field, on)


## Read-modify-write the flags byte to set/clear `field`'s enable bit, through the effect_flags
## channel (the choke keeps data.flags + the time_scale.flags mirror in sync), then rebuild so the
## band greys/ungreys and the preview re-arms.
func _toggle_pacing_enable(field: String, on: bool) -> void:
	if _effect_data == null or not (_effect_data.flags is Dictionary):
		return
	var bit := _pacing_enable_bit(field)
	if bit == 0:
		return
	var byte: int = int(_effect_data.flags.get("flags_byte", 0))
	byte = (byte | bit) if on else (byte & ~bit)
	_apply_edit({"channel": "effect_flags", "field": "flags_byte"}, byte)
	_rebuild_score()
	_recompute_end_frame()
	_render_current()
	if _timeline:
		_seek(_timeline.get_playhead())
	if _pacing_enable_check:
		_pacing_enable_check.set_pressed_no_signal(on)


## The played-window length for `field` — the band's carried sample count (phase-1 duration for
## outer_phases, the for-each region for for_each). Falls back to the full curve when the band is
## absent (no phase content). The painter veils the inactive tail past this N.
func _pacing_window(field: String) -> int:
	for b in (_build_score().get("pacing_lane", {}) as Dictionary).get("bands", []):
		if String(b.get("field", "")) == field:
			return (b.get("pacing", []) as Array).size()
	return -1


## This curve's enable state from the live flags (mirrors the parsed time_scale.flags).
func _pacing_enabled(field: String) -> bool:
	var byte: int = int((_effect_data.flags if _effect_data else {}).get("flags_byte", 0))
	return (byte & _pacing_enable_bit(field)) != 0


## The effect_flags bit each pacing curve gates: outer_phases = bit 5 (0x20, time_scale_pattern1),
## for_each = bit 6 (0x40, time_scale_pattern2). 0 for an unknown field.
static func _pacing_enable_bit(field: String) -> int:
	match field:
		"outer_phases": return 0x20
		"for_each": return 0x40
	return 0


## The author-facing pacing label (CONTEXT "Pacing curve": the honest names, NOT the arming-
## pattern "3-phase/1-phase").
static func _pacing_label(field: String) -> String:
	match field:
		"outer_phases": return "Phase 1 pacing"
		"for_each": return "For-each pacing"
	return field


## ADR-0075 suppressed-state provider: is this parent→child edge currently suppressed?
## Feeds the inspector checkbox's initial checked state (checked = spawning = not suppressed).
func _child_edge_suppressed(parent_index: int, edge: String) -> bool:
	if _host and _host.has_method("studio_is_child_edge_suppressed"):
		return _host.studio_is_child_edge_suppressed(parent_index, edge)
	return false


## ADR-0075 toggle callback: the inspector checkbox flipped. Route to the host, which sets
## the sim flag and re-seeks the preview. The checkbox already reflects its own new state,
## so no inspector re-render is needed.
func _set_child_edge_suppressed(parent_index: int, edge: String, suppressed: bool) -> void:
	if _host and _host.has_method("studio_set_child_edge_suppressed"):
		_host.studio_set_child_edge_suppressed(parent_index, edge, suppressed)


## #255 authoring mutate callback: an editable inspector cell lowered a raw-byte edit.
## Route it to the host, which owns the live EffectEditSession choke point and re-derives.
## Screen colour is read-live (invalidates_sim=false) so the host repaints in place with
## no re-seek — the reason #253 picked the Screen backdrop as the authoring pilot.
## Ctrl+Z anywhere in the studio unwinds the last edit. _unhandled_key_input fires for
## key events no focused control consumed, so undo works without the timeline holding focus.
func _unhandled_key_input(event: InputEvent) -> void:
	if _is_undo_shortcut(event):
		_undo()
		get_viewport().set_input_as_handled()
	elif _is_colour_delete_shortcut(event) and _colour_delete_available():
		# Del removes the selected colour keyframe (ADR-0089 editing-UX amendment, decision 4);
		# only when a real keyframe is selected, so Del elsewhere is untouched.
		_delete_colour_keyframe(_colour_selected_frame)
		get_viewport().set_input_as_handled()
	elif _is_colour_key_shortcut(event) and _colour_key_available():
		# K mints a keyframe at the selected age — the ⬥ button's keyboard half, and the
		# exact peer of Del beside it: Del un-keys a real keyframe, K keys an interpolated
		# age. It exists because ⬥ is the ONLY way to author a colour keyframe since
		# ADR-0089 dec. 5 retired click-to-add, and a sole gesture that lives at the bottom
		# of a panel the column's height budget can drop is a sole gesture with a condition
		# on it. Gated the same way Del is, so K elsewhere in the studio is untouched.
		_on_colour_set_keyframe()
		get_viewport().set_input_as_handled()
	elif _is_back_shortcut(event) and _step_back():
		# Alt+Left → step back one level (the `‹` button's keyboard half). Consumed only
		# when it actually moved, so an Alt+Left at the root stays free to bubble.
		get_viewport().set_input_as_handled()
	elif _is_escape(event):
		# Esc → Deselected (empty inspection). THREE stages, innermost first, because that is
		# what Esc means everywhere else in the studio: a focused value cell drops that FIELD
		# (a focused cell doesn't bind Esc, so this hook still fires); then a selected COLOUR
		# KEYFRAME drops — it is a sub-selection inside the target, and it is what the picker's
		# visibility is bound to, so this is how the picker closes; then the whole selection.
		# Consume just the Esc that did something; an empty-state Esc stays free to bubble to a
		# future close-window. No focus grab after deselect (focus owner left null).
		var focus_owner: Control = get_viewport().gui_get_focus_owner()
		if _is_text_focus(focus_owner):
			focus_owner.release_focus()
			get_viewport().set_input_as_handled()
		elif _clear_colour_selection():
			get_viewport().set_input_as_handled()
		elif _deselect():
			get_viewport().set_input_as_handled()


## Is this the undo keybinding — Ctrl+Z key-down, not an auto-repeat echo? Pure so the
## recognition is guarded without a scene (EffectStudioUndoShortcutTest).
static func _is_undo_shortcut(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and not event.echo \
		and event.keycode == KEY_Z and event.ctrl_pressed


## Is this the colour-keyframe delete keybinding — Del key-down, not an echo? Pure; the
## "a real keyframe is selected" gate lives in _colour_delete_available (page state).
static func _is_colour_delete_shortcut(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and not event.echo \
		and event.keycode == KEY_DELETE


## Is this the colour-key keybinding — a bare K key-down, not an echo? Pure, like its Del
## peer above. Modifiers are EXCLUDED rather than ignored: Ctrl+K and friends belong to
## whatever binds them next, and a recognizer that swallowed them would be the kind of
## silent overlap this file keeps its recognizers pure to make testable.
static func _is_colour_key_shortcut(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and not event.echo \
		and event.keycode == KEY_K and not event.ctrl_pressed and not event.alt_pressed \
		and not event.shift_pressed and not event.meta_pressed


## Is a colour keyframe MINTABLE right now — the column is up, an age is selected, and that
## age is not already a keyframe? The exact inverse of `_colour_delete_available`, and the
## same gate `_colour_key_button.disabled` reads.
func _colour_key_available() -> bool:
	return _sequence_life_column != null and _sequence_life_column.visible \
		and _colour_selected_frame >= 0 \
		and _colour_index_of_frame(_colour_selected_frame) < 0


## Is this the step-back keybinding — Alt+Left key-down, not an auto-repeat echo? Pure so
## the recognition is guarded without a scene (EffectStudioPathBarTest), like the undo and
## Esc recognizers beside it.
##
## Alt+Left and NOT Esc: Esc means "let go of everything" (two-stage — drop the focused
## field, then deselect), which is a different gesture from walking back up one level of
## the same inspection. Overloading Esc would make the shallow and the deep gesture the
## same key with a hidden mode.
static func _is_back_shortcut(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and not event.echo \
		and event.keycode == KEY_LEFT and event.alt_pressed


## Is this the deselect keybinding — Esc key-down, not an auto-repeat echo? Pure so the
## recognition is guarded without a scene (EffectStudioDeselectScrollTest).
static func _is_escape(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and not event.echo \
		and event.keycode == KEY_ESCAPE


## Is `control` a value-cell edit (a text/number field the author might be mid-typing)? Drives
## the two-stage Esc: an Esc while such a cell holds focus drops the FIELD (cancels the edit)
## rather than the whole selection, so the next Esc deselects. A focused SpinBox routes focus to
## its inner LineEdit, so the LineEdit case covers both; SpinBox/TextEdit kept for completeness.
## Pure so it's guarded without a scene.
static func _is_text_focus(control: Control) -> bool:
	return control is LineEdit or control is TextEdit or control is SpinBox


## Feature 2 (scroll-selected-into-view): the new scroll_vertical that brings `span_rect` (y in
## timeline-content space) just inside the visible window [scroll_vertical, scroll_vertical +
## viewport_h), or −1 if it is already fully visible (leave the scroll alone — no jarring nudge).
## A span pushed ABOVE the window (the inspector grew over it) drops so its top sits `headroom`
## below the window top; a span BELOW rises so its bottom sits `headroom` above the window bottom
## (symmetric, though a click can't reach it). Clamped to the content top (never negative). Pure
## so the decision is guarded without a scene.
static func compute_scroll_target(span_rect: Rect2, scroll_vertical: int, viewport_h: float, headroom: float) -> int:
	var top: float = float(scroll_vertical)
	var bottom: float = top + viewport_h
	if span_rect.position.y >= top and span_rect.end.y <= bottom:
		return -1
	if span_rect.position.y < top:
		return maxi(0, int(round(span_rect.position.y - headroom)))
	return maxi(0, int(round(span_rect.end.y - viewport_h + headroom)))


## The lane context-menu verbs for a right-clicked `span` at the cursor `frame` — the pure
## decision (ADR-0086 dec. 7; ADR-0087 generalises it to palette + screen;
## ADR-0089 particle_timeline). A camera sub-channel span offers Add (insert-waypoint at the
## cursor frame, a span-cut, addressed by frame) and Delete (this event by its §#286 ordinal);
## palette and screen offer the same two verbs addressed by raw keyframe index (ADR-0087); a
## particle span offers Split + Delete by flat raw index (ADR-0089). A sound EVENT span offers
## Delete only — its Add lives on the GAP right-click (events are instants); the inert
## TERMINATOR end-cap offers nothing (select-to-inspect only). The read-only compiled storage
## lane (kind camera_compiled) offers nothing. Each action is `{label, verb, field_ref}`; the
## menu runs `verb` through the EffectEditSession choke point. Pure so the choice is guarded
## without a scene (EffectStudioLaneContextMenuTest).
static func _lane_context_actions(span: Dictionary, frame: int) -> Array:
	# The cursor `frame` is score-absolute (the axis includes the phase offset); the
	# authored addresses are phase-local. start − authored_start IS the offset.
	var offset: int = int(span.get("start", 0)) - int(span.get("authored_start", 0))
	var local_frame: int = frame - offset
	var phase: String = String(span.get("phase", ""))
	match String(span.get("kind", "")):
		"camera":
			var lane_name: String = String(_CAMERA_MASK_NAME.get(int(span.get("channel_index", 0)), ""))
			if lane_name == "":
				return []
			return [
				{"label": "Add waypoint here", "verb": "insert", "field_ref":
					{"channel": "camera", "context": phase, "camera_channel": lane_name, "frame": local_frame}},
				{"label": "Delete waypoint", "verb": "delete", "field_ref":
					{"channel": "camera", "context": phase, "camera_channel": lane_name,
						"ordinal": int(span.get("ordinal", -1))}},
			]
		"palette":
			# Palette generalises the verbs (ADR-0087) but addresses by RAW keyframe index (no
			# ordinal): it is lane-event-atomic 1:1 with storage, so only insert/delete renumber.
			var channel_name: String = String(span.get("fields", {}).get("channel", ""))
			return [
				{"label": "Add tween here", "verb": "insert", "field_ref":
					{"channel": "palette", "context": phase, "channel_name": channel_name, "frame": local_frame}},
				{"label": "Delete tween", "verb": "delete", "field_ref":
					{"channel": "palette", "context": phase, "channel_name": channel_name,
						"event_index": int(span.get("keyframe_index", -1))}},
			]
		"screen":
			# Screen carries the same length-encoded verbs (ADR-0087); its address is 1-D — the
			# phase context alone (one implicit channel), raw keyframe index like palette.
			return [
				{"label": "Add tween here", "verb": "insert", "field_ref":
					{"channel": "screen", "context": phase, "frame": local_frame}},
				{"label": "Delete tween", "verb": "delete", "field_ref":
					{"channel": "screen", "context": phase,
						"event_index": int(span.get("keyframe_index", -1))}},
			]
		"particle":
			# Particle events (ADR-0089 particle_timeline): flat raw-index address (phase +
			# channel_index). On a DRAWN burst the insert genuinely CUTS the span at the cursor, so
			# it is honestly labelled "Split span here" (not "Add" — that reads as a no-op). The gap
			# entry point (_lane_gap_context_actions) reuses the SAME insert lowering as a true Add.
			# Delete merges the window into the next span.
			var ci: int = int(span.get("channel_index", -1))
			return [
				{"label": "Split span here", "verb": "insert", "field_ref":
					{"channel": "particle", "context": phase, "channel_index": ci, "frame": local_frame}},
				{"label": "Delete span", "verb": "delete", "field_ref":
					{"channel": "particle", "context": phase, "channel_index": ci,
						"event_index": int(span.get("keyframe_index", -1))}},
			]
		"sound":
			# An event is an INSTANT — Add is a GAP gesture (_gap_context_actions, off
			# the lane-level right-click), so a marker offers only Delete; the inert
			# terminator end-cap offers nothing (select-to-inspect only).
			if String(span.get("role", "event")) != "event":
				return []
			return [
				{"label": "Delete sound event", "verb": "delete", "field_ref":
					{"channel": "sound", "phase": phase,
						"channel_index": int(span.get("channel_index", 0)),
						"event_index": int(span.get("keyframe_index", -1))}},
			]
	return []


## The lane-level context-menu verbs for a right-click on a lane row's EMPTY space at
## the cursor `frame` — the GAP gesture. Sound is the channel where this is the ADD
## surface: events are instants, so "add here" targets the gap between them, which on
## the timeline is empty space (the user's model: it's a split, but a split in a GAP).
## The phase offset comes off the lane's projected spans (start − authored_start); an
## empty sound lane offers nothing (no offset to read, and the verb cannot seed an
## empty channel yet). Camera tiles its spans across the row (its Add lives on the
## span); screen / palette are follow-ups. Pure — guarded without a scene.
static func _gap_context_actions(lane: Dictionary, frame: int) -> Array:
	if String(lane.get("kind", "")) != "sound":
		return []
	var spans: Array = lane.get("spans", [])
	if spans.is_empty():
		return []
	var offset: int = int(spans[0].get("start", 0)) - int(spans[0].get("authored_start", 0))
	return [
		{"label": "Add sound event here", "verb": "insert", "field_ref":
			{"channel": "sound", "phase": String(lane.get("phase", "")),
				"channel_index": int(lane.get("channel_index", 0)),
				"frame": frame - offset}},
	]


## The span id a structural verb's selection lands on — the result `ordinal` folded into
## the channel's stable lane address. Pure so the landing is guarded without a scene.
static func _verb_landing_span_id(field_ref: Dictionary, ordinal: int) -> String:
	if String(field_ref.get("channel", "")) == "sound":
		return "sound:%s:%d#%d" % [String(field_ref.get("phase", "")),
			int(field_ref.get("channel_index", -1)), ordinal]
	return "camera:%s:%s#%d" % [String(field_ref.get("context", "")),
		String(field_ref.get("camera_channel", "")), ordinal]


## The lane context-menu verbs for a right-clicked GAP (empty stretch) in a particle lane —
## the pure decision (ADR-0089 particle_timeline Add-in-a-gap). Unlike _lane_context_actions
## there is no span to address; the caller resolves the lane to (phase, channel_index) and the
## cursor to a PHASE-LOCAL frame. A gap offers ONLY Add (born-disabled insert at the cursor,
## opening a new dimmed span to the next wall) — no Delete, because a gap has no drawn span to
## remove. Lowers to the SAME insert_event as a drawn-span Split; only the entry point differs.
## Pure so the choice is guarded without a scene (EffectStudioLaneContextMenuTest).
static func _lane_gap_context_actions(phase: String, channel_index: int, local_frame: int) -> Array:
	return [
		{"label": "Add span here", "verb": "insert", "field_ref":
			{"channel": "particle", "context": phase, "channel_index": channel_index, "frame": local_frame}},
	]


## The lane context-menu verb for a right-clicked INVISIBLE SPACER region of a CAMERA
## sub-channel lane (ADR-0086 dec. 15). A camera spacer is a `MAP`-delta-of-zero
## HOLD: it owns its span, moves nothing, and so draws as empty space you cannot select. The
## timeline routes the right-click here through lane_context (like an emitter gap), and the only
## verb is the SAME insert-waypoint a drawn camera span offers — only the entry point differs.
##
## No `spacer_stub` flag (colour's born-disabled seed): camera has no Enable bit, and
## `CameraChannel._seed_event` deliberately inherits the covering span's command word, so the
## added waypoint is ITSELF a spacer — drawn while selected, gone on deselect unless the author
## gives it a real Source or a non-zero value (ADR-0086 dec. 19). Delete is absent
## for the same reason it is absent on a colour spacer: there is no event here to address.
## Pure so the choice is guarded without a scene (EffectStudioLaneContextMenuTest).
static func _camera_spacer_gap_actions(lane: Dictionary, local_frame: int) -> Array:
	var lane_name: String = String(_CAMERA_MASK_NAME.get(int(lane.get("channel_index", 0)), ""))
	if lane_name == "":
		return []
	return [
		{"label": "Add waypoint here", "verb": "insert", "field_ref":
			{"channel": "camera", "context": String(lane.get("phase", "")),
				"camera_channel": lane_name, "frame": local_frame}},
	]


## The lane context-menu verbs for a right-clicked INVISIBLE SPACER region of a colour lane
## (ADR-0087 decs. 23-28). A spacer is empty space you can't select, so the timeline routes
## the right-click through lane_context (like an emitter gap). A spacer offers ONLY "Add event
## here": a `spacer_stub` insert that cuts the covering spacer into a 1-frame born-disabled stub
## bracketed by spacers — you build a new event INTO the empty space, you never convert it (so no
## Delete). `local_frame` is already phase-local (the page offset-corrected it); palette carries
## its tint channel_name parsed from the lane id ("palette:phase:channel_name"), screen is 1-D.
## Pure so the choice is guarded without a scene (EffectStudioLaneContextMenuTest).
static func _colour_spacer_gap_actions(lane: Dictionary, local_frame: int) -> Array:
	var kind: String = String(lane.get("kind", ""))
	var phase: String = String(lane.get("phase", ""))
	if kind == "palette":
		# "palette:<phase>:<channel_name>" → recover the tint channel (the 2-D address dim).
		var parts: PackedStringArray = String(lane.get("id", "")).split(":")
		var channel_name: String = parts[2] if parts.size() >= 3 else ""
		return [
			{"label": "Add event here", "verb": "insert", "field_ref":
				{"channel": "palette", "context": phase, "channel_name": channel_name,
					"frame": local_frame, "spacer_stub": true}},
		]
	if kind == "screen":
		return [
			{"label": "Add event here", "verb": "insert", "field_ref":
				{"channel": "screen", "context": phase, "frame": local_frame, "spacer_stub": true}},
		]
	return []


## Unwind the last edit through the host's live EffectEditSession, then re-project the SAME
## document — an undo can be structural (unwinding a split re-coalesces), so reproject_score
## refreshes the lane geometry while preserving the transport + the author's selection (the
## span id is stable per the #286 ordinal address). Re-render so the inspector reflects the
## reverted value. No-op when there is nothing to undo or the host can't.
func _undo() -> void:
	if not (_host and _host.has_method("studio_undo")):
		return
	if _host.studio_undo():
		# A prune-for-real undo (ADR-0085 2026-08-13) SWAPS the FedsBank object back, so re-point
		# the cached env at the live model's bank and re-derive the pair views before re-projecting
		# — otherwise the panel stays on the pruned view over the restored bytes. Idempotent for
		# every other undo kind (the bank is unchanged, so the re-point is a no-op).
		if not _sound_env.is_empty() and _effect_data != null:
			_sound_env["feds_bank"] = _effect_data.feds_bank
			_pair_views = _compute_pair_views()
		_rebuild_score()
		_render_current()


## Dispatch a projector-declared `action` (an inspector button press) to the host:
## "audition_container" = hear a SoundContainer's repeat pattern by firing it several
## times through the SFX engine; "audition_sound" = hear ONE resolved sound id once (the
## ▶ preview beside a container's Sound A/B/C picker). Inert if the host can't audition.
func _run_action(action: Dictionary) -> void:
	# Yield the chunked ghost render to the audition FIRST: a held capture would both
	# silence it and mix its casts into the offline render. The holdoff spans the
	# audition's fires + ring-out; the aborted render restarts after.
	match str(action.get("kind", "")):
		"audition_container", "audition_sound", "audition_pruned":
			_ghost_queue_holdoff_ms = Time.get_ticks_msec() + GHOST_AUDITION_HOLDOFF_MS
			_ghost_queue.abort()
	match str(action.get("kind", "")):
		"audition_container":
			if _host and _host.has_method("studio_audition_container"):
				_host.studio_audition_container(int(action.get("index", -1)))
		"audition_sound":
			if _host and _host.has_method("studio_audition_sound"):
				_host.studio_audition_sound(int(action.get("id", -1)))
		"audition_pruned":
			# The no-op prune A/B: play the pruned pair NOW (instant), then measure the Δ +
			# joint overlay offline after it rings out — one press, hear it then see it.
			_audition_pruned(int(action.get("pair_idx", -1)))
		"audition_note_hold":
			_audition_note_press(action, false)
		"audition_note_tail":
			_audition_note_press(action, true)
		"audition_note_release":
			_audition_note_release()
		"prune_noops_commit":
			# Prune-for-real (ADR-0085 2026-08-13): DELETE this pair's no-op opcodes for real.
			_commit_prune_noops(int(action.get("pair_idx", -1)))
		"texture_export", "texture_import":
			# #280: both halves of the artist round trip live here so the loop never
			# depends on the Lua/PCSX extractor. Export writes the sheet as a 32-bit
			# RGBA .tga; Import reads a repainted one back through the fixed-CLUT
			# index delta.
			_open_texture_dialog(str(action.get("kind", "")) == "texture_export")


## Open the .tga picker for one direction of the texture round trip (#280).
## The dialog is built once and re-modes per press — the studio page lives in a
## separate OS Window, so the dialog is parented to the page itself rather than
## the main viewport.
func _open_texture_dialog(is_export: bool) -> void:
	_texture_dialog_is_export = is_export
	if _texture_dialog == null:
		_texture_dialog = FileDialog.new()
		_texture_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_texture_dialog.use_native_dialog = false
		_texture_dialog.file_selected.connect(_on_texture_dialog_confirmed)
		add_child(_texture_dialog)
	_texture_dialog.filters = PackedStringArray(["*.tga ; RGBA Targa image"])
	if is_export:
		_texture_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		_texture_dialog.title = "Export texture sheet"
		var eff := "texture"
		if _effect_data != null and not String(_effect_data.name).is_empty():
			eff = String(_effect_data.name)     # the effect folder name, e.g. "E019"
		_texture_dialog.current_file = "%s.texture.tga" % eff
	else:
		_texture_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_texture_dialog.title = "Import texture sheet"
	_texture_dialog.popup_centered_ratio(0.6)


func _on_texture_dialog_confirmed(path: String) -> void:
	_on_texture_file_selected(path, _texture_dialog_is_export)


## Hand a chosen path to the host and SHOW what it said. Split from the dialog so the
## wiring is testable without driving a real picker.
##
## Both halves report on `_save_label` (the same strip the Save verdict uses). They used to
## be fire-and-forget: the host's three import refusals — unreadable file, a .tga the decoder
## won't take, a dimension mismatch — were bare `push_warning`s, so a refused import and a
## working one were indistinguishable on screen.
##
## An accepted import also re-renders the page. The frameset canvas caches the texture object
## it was handed and only rebinds when the inspection TARGET changes, so an import with a
## frame already open would keep drawing the pre-import sheet — and re-picking the same
## dropdown entry fires no signal at all, leaving the author no way to force it (#280).
func _on_texture_file_selected(path: String, is_export: bool) -> void:
	if _host == null:
		return
	var verb := "studio_export_texture" if is_export else "studio_import_texture"
	if not _host.has_method(verb):
		return
	var res = _host.call(verb, path)
	if not (res is Dictionary):
		return   # an older host that still returns void — nothing to report
	var ok: bool = bool(res.get("ok", false))
	if ok:
		_set_status(("Exported: %s" % path) if is_export else ("Imported: %s" % path))
	else:
		_set_status(("Export failed: %s" if is_export else "Import refused: %s")
			% str(res.get("error", "")))
	if ok and not is_export:
		_render_current()


## defer_refold (ADR-0089 Drag preview): during a live drag the geometry reprojects per motion
## but the expensive sim rescrub is deferred to release — the host skips the refold and the
## drag's terminal _commit_drag_refold folds ONCE. A discrete (typed) edit passes false, so it
## refolds at once. Only sim-invalidating channels are affected; read-live lanes never refold.
func _apply_edit(field_ref: Dictionary, new_raw, defer_refold: bool = false) -> void:
	# The note-chip audition override (ADR-0085 2026-08-13): a TRANSIENT session pick that
	# drives the two audition buttons — it NEVER reaches the host/EditSession, so no byte is
	# written and nothing is saved. Intercept it before the choke point.
	if str(field_ref.get("channel", "")) == "audition":
		_audition_override_id = int(new_raw)
		# Re-render so the override DRIVES both buttons (ADR-0085 2026-08-13): a silent /
		# one-shot override re-gates them live. This path skips _navigate_to, so the override
		# survives the render (only nav / event-selection resets it).
		_render_current()
		return
	# A QUAD TRANSFORM TERM (2026-08-21). `frameset_quad` is not a channel and never reaches
	# `EffectEditSession._dispatch`: the six terms are DERIVED from the eight stored corner
	# components, so one knob turn is a recomposition of up to eight raw writes rather than a
	# byte write. Intercepted here, beside the `audition` override above, and lowered as ONE
	# compound so the whole turn is one undo entry (ADR-0099 dec. 9).
	if str(field_ref.get("channel", "")) == "frameset_quad":
		_commit_quad_term(field_ref, new_raw)
		return
	if not (_host and _host.has_method("studio_apply_edit")):
		return
	# RIPPLE (ADR-0087 dec. 10 + second amendment — every lane): while the toggle is on, a
	# resize — the drag's boundary AND the typed row, so the two affordances can't diverge —
	# carries the flag into the choke point: colour lanes skip the sum-preserving trade,
	# camera shifts its lane's downstream end_frames. Injected on the field_ref (not read
	# as ambient state) so the undo record replays the same semantics after the toggle flips.
	var _rip_ch: String = String(field_ref.get("channel", ""))
	var _rip_field: String = String(field_ref.get("field", ""))
	if _ripple and ((_rip_ch in ["palette", "screen"] and _rip_field in ["boundary_end", "duration"]) \
			or (_rip_ch == "camera" and _rip_field == "end_frame")):
		field_ref = field_ref.duplicate()
		field_ref["ripple"] = true
	# Field-relevance salience (ADR-0089 amendment): a plain emitter value edit is not
	# structural, but it can still flip a relevance VERDICT — waking an Inactive field to Live
	# (its `!` marker clears) or crossing a NUMERIC gate (homing strength → 0 deads target
	# offset, hiding its fold). Snapshot the emitter's render-affecting relevance BEFORE the
	# edit so the branch below can reproject iff it changed. Only emitter, non-drag edits ask.
	var rel_before: String = ""
	if String(field_ref.get("channel", "")) == "emitter" and not defer_refold:
		rel_before = _emitter_relevance_signature(field_ref)
	# A container edit MAY retarget the referencing trigger's ghost — but only when it
	# changes the container's resolved FIRST fire (mode changes reorder fires 2,3,… and
	# id_b/id_c edits touch dead-on-fire-0 slots; neither moves the first fire for modes
	# 0-4). Snapshot the resolved pair BEFORE the edit mutates the shared doc so the
	# invalidates_containers branch can tell "ghost unchanged" from "ghost retargeted"
	# and skip the ~0.6s offline SPU re-render on the (common) unchanged case.
	var pre_pair: int = -1
	var container_sid: int = -1
	if str(field_ref.get("channel", "")) == "sound_container" and not _sound_env.is_empty():
		container_sid = int(field_ref.get("index", -1)) + 2
		pre_pair = GhostProjector.resolve_pair_idx(_sound_env["sound_containers"], container_sid)
	var res = _host.studio_apply_edit(field_ref, new_raw, defer_refold)
	if not (res is Dictionary):
		return
	# STRUCTURAL and RELAYOUT edits take the SAME full refresh — they differ only in what changed:
	#   * structural (a Blend↔Gradient kind flip; a camera split/merge) reshapes the field set and
	#     the lane rendering. reproject_score preserves the transport + the author's selection
	#     (dropped only if the selected span truly vanished); camera addresses spans by a stable
	#     sub-channel ordinal (ADR-0086 dec. 5, #286), so a split/merge that renumbers the
	#     packed keyframes keeps the selection valid.
	#   * relayout (an end_frame nudge, or a source/interp change that alters what the value MEANS
	#     — the #281 value-row labels) moved a span boundary/marker or changed the labels but kept
	#     the field set.
	# Either way: rebuild the score, re-derive the end marker (the reshape can move it), re-resolve
	# audibility for the reshaped lanes, re-render the inspector, and re-seek the host to the
	# preserved DISPLAYED frame so UI↔host agree (#255, 68be01dbd).
	if res.get("structural", false) or res.get("relayout", false):
		_rebuild_score()
		_recompute_end_frame()
		_apply_audibility()
		_render_current()
		_seek(_timeline.get_playhead())
	# A sound LAYOUT edit (a Gap / duration_frames change) moves trigger i+1 and every later
	# marker on the channel but leaves the FIELD SET identical — so re-project the ruler WITHOUT
	# re-deriving the inspector: the spinbox being typed into keeps focus and its live value.
	elif res.get("invalidates_layout", false):
		_rebuild_score()
		# A layout edit can move the effect's end — a timeline-header duration shifts the phase
		# offsets (and phase 2's content extent), a sound gap shifts later markers. Recompute the
		# displayed end so its marker tracks. Skip mid-drag (defer_refold): _settle_after_drag
		# recomputes once on release, so the particle sim doesn't re-run per motion.
		if not defer_refold:
			_recompute_end_frame()
	# A shared SoundContainer edit (Pick mode / an id) is effect-global (ADR-0073): it changes
	# what EVERY trigger playing this container resolves to. Recompute the legible container
	# views (mode name / Sound set / pairs) AND re-project the ghost tail for the trigger that
	# plays this container — the container's timeline selector is index+2 — so both the
	# inspector and the timeline follow the new selection without a reload. Re-render off the
	# cached FEDS bank (no disk re-read); the erase forces a fresh render even for an id already
	# in the map (the container now resolves it differently). Safe inside value_changed — the
	# inspector queue_free()s old widgets deferred, so the emitting widget isn't freed mid-signal.
	elif bool(res.get("invalidates_containers", false)):
		_container_views = _compute_container_views("")
		_pair_views = _compute_pair_views()   # provenance follows the re-pointed slots
		# Ghost honesty WITHOUT the per-keystroke stall: only when the edit actually moved
		# the container's resolved first fire does the ghost need a re-render — and even
		# then it goes through the DEBOUNCED path (like sound_id edits) so a burst of
		# clicks pays for ONE offline SPU render after the value settles. The unchanged
		# case (every mode flip, every dead-slot id edit) keeps the cached ghost and the
		# rebuild below is pure re-projection — instant.
		var sid := int(field_ref.get("index", -1)) + 2
		if container_sid == sid and not _sound_env.is_empty():
			var post_pair: int = GhostProjector.resolve_pair_idx(_sound_env["sound_containers"], sid)
			if post_pair != pre_pair:
				_ghost_by_sound_id.erase(sid)
				_energy_by_sound_id.erase(sid)
				# The session cache holds the OLD pair's render — a revisit (or the
				# debounced re-render's cache consult) must not resurrect it.
				_ghost_render_cache.erase(_ghost_cache_key(_current_dir, sid))
				_schedule_ghost_reproject(sid)
		_rebuild_score()
		_render_current()
	# A FEDS byte patch (TIER-3, ADR-0085) changes the SOUND CONTENT a pair plays, so the
	# pair views re-derive (the strip + rows must read the new byte) and the ghost/energy
	# of EVERY sound_id resolving into the edited pair goes stale — the fan-out is scoped
	# by the field_ref's pair_idx so an unrelated container's cached render survives.
	# Renders go through the DEBOUNCED path (one offline SPU render after a burst
	# settles), mirroring the container branch above.
	elif bool(res.get("invalidates_feds", false)):
		_pair_views = _compute_pair_views()
		var edited_pair := int(field_ref.get("pair_idx", -1))
		_pair_energy_cache.erase(edited_pair)   # §3: the edited pair's energy render is stale
		_schedule_pair_energy(edited_pair)      # …re-render its bands CHUNKED (supersedes any in-flight)
		_invalidate_noop_ab(edited_pair)        # …and its no-op A/B proof is stale too
		if not _sound_env.is_empty():
			var containers: Array = _sound_env["sound_containers"].get("containers", [])
			for ci in range(containers.size()):
				var sid2: int = ci + 2
				if GhostProjector.resolve_pair_idx(_sound_env["sound_containers"], sid2) == edited_pair:
					_ghost_by_sound_id.erase(sid2)
					_energy_by_sound_id.erase(sid2)
					_ghost_render_cache.erase(_ghost_cache_key(_current_dir, sid2))
					_schedule_ghost_reproject(sid2)
		_rebuild_score()
		_render_current()
	# A sound_id edit changes which sound the trigger plays, so BOTH its timeline ghost/energy
	# tail AND its derived inspector content (the "Plays → container N" link + the Sound tooltip)
	# must follow the new value — otherwise the author has to click off and re-select to see it.
	# Re-project the ghost for the newly-selected sound (offline SPU render off the cached FEDS
	# bank — no disk re-read), reproject the timeline so the tail redraws, and re-derive the
	# inspector so the link/tooltip refresh. Safe from inside the field's value_changed because
	# the inspector queue_free()s the old widgets (deferred), so the emitting spinbox isn't freed
	# mid-signal.
	elif str(field_ref.get("channel", "")) == "sound" and str(field_ref.get("field", "")) == "sound_id":
		# Instant: reproject the timeline (the ghost for an already-known sound shows at once)
		# and re-derive the inspector (the "Plays" link + tooltip).
		_rebuild_score()
		_render_current()
		# Debounced: a brand-new sound's ghost needs a ~0.6s SPU render — coalesce a burst of
		# edits so it runs ONCE after the value settles, then reproject again to show it.
		_schedule_ghost_reproject(int(new_raw))
	# A plain EMITTER value edit that flipped the field-relevance verdict (ADR-0089 amendment):
	# the host already re-folded the preview (invalidates_sim), but the inspector only re-derives
	# the `!` salience markers + hidden-Dead membership on a reproject. Reproject iff a verdict
	# actually moved — an ordinary in-range nudge (signature unchanged) is left alone so the live
	# spinbox is NOT rebuilt mid-scrub (the very reason the plain-value branch skips it below).
	elif String(field_ref.get("channel", "")) == "emitter" and not defer_refold \
			and _emitter_relevance_signature(field_ref) != rel_before:
		_render_current()
	# A SEQUENCE opcode edit. `invalidates_sim` re-folds the particle preview, but the
	# studio's own sequence player holds a DECODE — `SequenceTimeline.trace` flattens the
	# opcode stream once at bind — so a duration or frameset change reached the effect and
	# not the thing the author was looking at while making it. Re-decode in place.
	#
	# In place, and not `_render_current()`: an inspector rebuild would queue_free the very
	# ScrubField being dragged, and every one of these edits arrives with defer_refold false
	# (only a timeline edge drag defers), so the drag would die after one pixel. Same
	# reasoning as the plain-value branch below — the difference is that a sequence view
	# puts live values in its section TITLES, so those have to be refreshed too.
	elif String(field_ref.get("channel", "")) == "sequence":
		_refresh_sequence_preview()
	# A FRAMESET edit made while the sequence player is open — the unified animation screen's
	# grafted frame rows (ADR-0102). `FramesetChannel` returns `invalidates_sim: false`
	# (frames are read LIVE by the renderer), so this edit reached the effect through no
	# branch above and, before this one existed, refreshed nothing at all.
	#
	# It has to refresh the same thing a sequence edit does, for a reason that is not
	# obvious: `SequenceCanvas._decode` computes the player's shared `_bounds` box from the
	# FRAMESETS, not from the opcodes. So widening a frame's quad from the unified screen
	# moves the box every thumbnail and the assembled sprite are drawn in — and the player,
	# holding a decode taken at bind, would go on drawing the old one. Same staleness, same
	# fix, same function.
	#
	# `_refresh_sequence_preview` no-ops unless the sequence panel is up, so the FRAME detail
	# screen — where the frameset canvas is the column occupant and owns its own refresh — is
	# untouched by this branch.
	elif String(field_ref.get("channel", "")) == "frameset":
		_refresh_sequence_preview()
	# A plain value edit (screen colour, sound_id, a camera value) neither reshapes fields nor
	# moves a marker; the picker/spinbox keeps its state and the preview repaints on its own.
	# The tint rows are the exception: the +/- delta row is the single source of truth, so a
	# byte edit here (a +/- box, or the No-tint reset — NOT the picker, which goes through
	# _pick_target) must MATERIALIZE into the other views. update_picker=true moves the picker
	# colour too, since the picker was not the source (ADR-0087).
	_sync_tint(field_ref, true)


## Re-decode the open sequence player and re-label what the edit just invalidated, all
## without rebuilding a widget (see `_apply_edit`'s sequence branch for why not).
##
## Three surfaces go stale on one opcode edit, and they are stale in three different
## places: the PLAYER holds the flattened trace, each opcode SECTION's title is the
## instruction label spelling out that opcode's own values, and the header's "Plays for N
## ticks" is a sum over every duration below it. The thumbnails are not in this list on
## purpose — each one subscribes itself to the canvas's `decode_changed` and re-pulls its
## own cell, so there is no list of them here to go stale (ADR-0100 dec. 8's reasoning,
## one layer down).
func _refresh_sequence_preview() -> void:
	if _sequence_canvas == null or _sequence_panel == null or not _sequence_panel.visible:
		return
	if _effect_data == null or _inspector == null or _nav.is_empty():
		return
	var target: Dictionary = _nav.back()
	# `_sequence_bound`, not the target's ref, for the reason `_sequence_thumbnail_for`
	# gives one screen up: on an `emitter` or `span` target a ref's `index` is not an
	# animation index, and re-decoding `animations[emitter_index]` here would swap the
	# player's sequence for an unrelated one on the next opcode edit — a stale picture that
	# looks exactly like a fresh one.
	if _sequence_bound.is_empty():
		return
	var anim_idx: int = int(_sequence_bound["anim_index"])
	if not (_effect_data.animations is Array) \
			or anim_idx < 0 or anim_idx >= _effect_data.animations.size():
		return
	var anim = _effect_data.animations[anim_idx]
	if not (anim is Dictionary):
		return
	_sequence_canvas.refresh_sequence(anim, _sequence_group_offset(_sequence_bound))

	# Re-derive the labels through the SAME path `_render_current` uses, so the refreshed
	# text and a full render can never disagree — only the widgets differ.
	var score: Dictionary = _timeline._score if _timeline else {}
	var header: Array = Model.inspector_header(target, _effect_data, score)
	_inspector.refresh_header_values(header)
	var sections: Array = Model.inspector_sections(target, _effect_data, score)
	var titles: Dictionary = {}
	for section in sections:
		var id := str(section.get("fold_id", ""))
		if id != "":
			titles[id] = str(section.get("title", ""))
	_inspector.refresh_section_titles(titles)
	# And the follow beside the Frameset editor, which is DERIVED from the value just
	# typed into it (`frameset + group offset`). Left alone it keeps its old destination:
	# point the opcode at frameset 3 and the button beside it still opens frameset 1.
	_inspector.refresh_follows(sections)


## The emitter's render-affecting relevance signature (EmitterFieldRelevance), or "" when the
## field_ref does not address an emitter or the emitter is absent. The page compares this
## across a plain value edit to decide whether the salience markers changed and the inspector
## must reproject. Pure read off the LIVE effect_data (the same object the host just mutated).
func _emitter_relevance_signature(field_ref: Dictionary) -> String:
	if _effect_data == null:
		return ""
	var em = _effect_data.get_emitter(int(field_ref.get("emitter_index", -1)))
	if em == null:
		return ""
	return EmitterRelevance.render_signature(em)


## The ONE lane-parameterized tint-refresh seam (ADR-0087 dec. 14): after a tint-byte
## edit (a Δ box, the No-tint reset, or a picker pick via _pick_target), refresh the +/- delta
## row (the source of truth), the "actual" swatch, and — when the picker wasn't the source —
## the picker colour, all IN PLACE (a live picker popup / mid-scrub spinbox is never
## destroyed). The lanes differ only in the facts this dispatch supplies: the address shape
## (palette 2-D, screen 1-D), which fields are tint bytes, and the achieved colour — palette
## folds its bytes over the fixed mid-grey reference (PaletteTintSolver), screen reads the
## LIVE folded backdrop top from the host (which re-delivered applying the edit). No-op for
## any other field, and for a screen Gradient (it shares the storage fields but has no Δ row).
func _sync_tint(field_ref: Dictionary, update_picker: bool) -> void:
	if _inspector == null or _effect_data == null:
		return
	var rgb: Vector3i
	var achieved: Color
	match String(field_ref.get("channel", "")):
		"palette":
			if not (String(field_ref.get("field", "")) in ["r", "g", "b"]):
				return
			if _effect_data.palette == null:
				return
			var ch = _effect_data.palette.get_channel(
				String(field_ref.get("context", "")), String(field_ref.get("channel_name", "")))
			if ch == null:
				return
			var kf = ch.get_keyframe(int(field_ref.get("event_index", -1)))
			if kf == null:
				return
			rgb = kf.rgb
			achieved = PaletteTintSolver.result(
				int(kf.blend_mode), int(kf.rgb.x), int(kf.rgb.y), int(kf.rgb.z))
		"screen":
			if not (String(field_ref.get("field", "")) in ["start_r", "start_g", "start_b"]):
				return
			if _effect_data.screen == null:
				return
			var ch = _effect_data.screen.get_channel(String(field_ref.get("context", "")))
			if ch == null:
				return
			var kf = ch.get_keyframe(int(field_ref.get("event_index", -1)))
			if kf == null or int(kf.mode) != ScreenDataClass.ScreenMode.BLEND:
				return
			rgb = Vector3i(int(kf.start_r_raw), int(kf.start_g_raw), int(kf.start_b_raw))
			achieved = _host.studio_screen_top_color() \
				if (_host and _host.has_method("studio_screen_top_color")) else Color.BLACK
		_:
			return
	_inspector.refresh_palette_tint(rgb, achieved, update_picker)


## ADR-0085 anchor drag: the author moved a sound trigger's anchor handle, declaring the
## audible HIT lands `offset` frames into the sound. Resolve the trigger's keyframe
## address off the live score span, lower the authoring-only `anchor_offset` through the
## SAME choke point (it never reaches the ROM bytes — byte-faithful), then reproject just
## the handle so it tracks the cursor WITHOUT the transport/selection reset a full
## rebuild would cause. The fire marker and on-disk bytes never move.
func _on_anchor_offset_changed(span_id: String, offset: int) -> void:
	var score: Dictionary = _timeline._score if _timeline else {}
	var span: Dictionary = Model.find_span(score, span_id)
	if span.is_empty():
		return
	var ref := {
		"channel": "sound",
		"phase": str(span.get("phase", "")),
		"channel_index": int(span.get("channel_index", -1)),
		"event_index": int(span.get("keyframe_index", -1)),
		"field": "anchor_offset",
	}
	if _host and _host.has_method("studio_apply_edit"):
		_host.studio_apply_edit(ref, offset)
	_timeline.set_anchor_offset(span_id, offset)


## ADR-0086 boundary-drag GRAB: open a one-undo coalesce for this span's boundary field and
## make the grip's on-screen owner the inspection root so its Length/End-frame tracks the
## drag. Inert on an unresolvable span (edge grips only exist on camera / palette / screen /
## particle spans).
##
## `span_id` is the grip's WRITE owner — the span whose stored boundary number the drag moves,
## and the only thing `_edge_field_ref` may ever address. What gets SELECTED is the grip's
## identity (ADR-0086 dec. 23): normally the same span, but at
## a hidden hold it is the next DRAWN span, whose visible left edge that boundary is. Rooting
## on the hold instead un-hides it — a selected span is never a hidden spacer — which is what
## made a left-edge drag look like it "created a spacer and selected it". "" identity (the
## lane-tail hold, speaking for no span) leaves the selection alone.
func _on_edge_drag_started(span_id: String) -> void:
	var span: Dictionary = Model.find_span(_timeline._score if _timeline else {}, span_id)
	if span.is_empty():
		return
	var ref: Dictionary = _edge_field_ref(span)
	if ref.is_empty():
		return
	if _host and _host.has_method("studio_begin_coalesce"):
		_host.studio_begin_coalesce(ref)
	var select_id: String = _timeline.edge_identity_for(span_id) if _timeline else ""
	if select_id != "":
		if _timeline:
			_timeline.select_span(select_id)
		_set_root(Target.span(select_id))
	_edge_drag_id = span_id
	# The gesture's write address, kept for the release-time emptied-hold check: once the hold
	# owns nothing the score stops emitting a span for it, so `span_id` can no longer resolve.
	_pending_edge_ref = ref


## ADR-0086 boundary-drag MOVE: convert the ABSOLUTE cursor frame to phase-local, clamp it
## strictly between neighbours (min 1 frame each side; the tail clamps only on the left), and
## stamp it as the pending edit. The apply itself is deferred to the once-per-frame _process
## drain — the timeline reported intent; the host owns the bounds and the recompile cadence.
func _on_edge_dragged(span_id: String, abs_frame: int) -> void:
	var span: Dictionary = Model.find_span(_timeline._score if _timeline else {}, span_id)
	if span.is_empty():
		return
	var ref: Dictionary = _edge_field_ref(span)
	if ref.is_empty():
		return
	_pending_edge = {"field_ref": ref, "value": _edge_local_frame(span, abs_frame)}


## ADR-0086 boundary-drag RELEASE: flush the last pending edit (so the final frame isn't lost
## to a release that beat the next _process), close the undo bracket, fold the sim once, and —
## for a particle resize that took the geometry-only drag path — settle the inspector + preview.
func _on_edge_drag_ended(span_id: String) -> void:
	_flush_pending_edge()
	if _host and _host.has_method("studio_end_coalesce"):
		_host.studio_end_coalesce()
	_drop_emptied_camera_hold(span_id)
	var was_particle: bool = String(Model.find_span(
		_timeline._score if _timeline else {}, span_id).get("kind", "")) == "particle"
	_edge_drag_id = ""
	_commit_drag_refold()
	if was_particle:
		_settle_after_drag()


## ADR-0101 decision 7 for the BOUNDARY drag: a camera hold pulled back onto its own start now
## owns nothing, and an owner of nothing is deleted rather than parked at zero width — the same
## rule `CameraChannel.move_span` applies to a hold a slide empties. Left behind, it is invisible
## in the lane (the score only emits a span for `end > prev_end`) yet still a real opcode: it
## holds a native SoA slot, draws a marker on the read-only compiled lane, and adds one to every
## later event's ordinal, so a drag out and back would cost a keyframe every time.
##
## Deferred to RELEASE rather than applied per motion because the drag re-resolves its address
## from the score each motion (`lane#ordinal`); deleting mid-gesture would renumber the lane
## under the cursor. The cost is that this one gesture records TWO undo entries — the resize,
## then the delete — where Move keeps a single one by re-planning from its grab snapshot.
func _drop_emptied_camera_hold(span_id: String) -> void:
	var ref: Dictionary = _pending_edge_ref if not _pending_edge_ref.is_empty() \
		else _edge_field_ref(Model.find_span(_timeline._score if _timeline else {}, span_id))
	_pending_edge_ref = {}
	if String(ref.get("channel", "")) != "camera" or _effect_data == null:
		return
	if not CameraChannelClass.is_emptied_hold(_effect_data, ref):
		return
	if _host and _host.has_method("studio_delete_event"):
		_host.studio_delete_event(ref)
		_rebuild_score()
		_render_current()


## Apply the pending camera edge edit (if any) through the choke point, reprojecting on the
## relayout an end_frame edit returns. At most one per call — the _process drain and the
## release flush both route here, so a burst of motions collapses to one recompile per frame.
func _flush_pending_edge() -> void:
	if _pending_edge.is_empty():
		return
	var edit: Dictionary = _pending_edge
	_pending_edge = {}
	var ref: Dictionary = edit["field_ref"]
	# Live PARTICLE edge drag (Resize): bypass _apply_edit's full-rebuild reproject. A particle
	# resize moves only particle geometry, so do the host edit (deferring the refold) then
	# reproject ONLY the particle lanes (~1ms) instead of a full Model.build (~460ms with the
	# palette/screen spacer oracle). Inspector + re-seek settle on release. ADR-0089 Drag
	# preview. Colour/camera edge drags keep _apply_edit's full path (unchanged).
	if _edge_drag_id != "" and String(ref.get("channel", "")) == "particle":
		if _host and _host.has_method("studio_apply_edit"):
			_host.studio_apply_edit(ref, int(edit["value"]), true)
			_reproject_dragged_kind("particle")
		return
	# Live COLOUR edge drag: same shape. A colour boundary moves only colour geometry, so
	# reproject that kind (~1ms) instead of _apply_edit's full Model.build, whose palette +
	# screen spacer oracle costs ~280ms EVERY motion. The oracle still runs — rebuild_kind_lanes
	# re-derives the dragged kind's verdicts — so a consume that wakes a neighbouring spacer
	# shows immediately; it just doesn't re-fold the lanes the drag cannot touch. `removed` is
	# the slot count the consume reclaimed, which the release uses to re-point the selection.
	if _edge_drag_id != "" and String(ref.get("channel", "")) in ["palette", "screen"]:
		if _host and _host.has_method("studio_apply_edit"):
			var res = _host.studio_apply_edit(ref, int(edit["value"]), true)
			if res is Dictionary:
				_edge_drag_removed = int(res.get("removed", 0))
			_reproject_dragged_kind(String(ref.get("channel", "")))
		return
	# Mid-drag (edge id still set) → defer the sim refold; the release flush + _commit_drag_refold
	# fold once. A typed edit routes through _apply_edit directly with defer_refold=false.
	_apply_edit(ref, int(edit["value"]), _edge_drag_id != "")


## ADR-0089 Move GRAB (generalised to camera + colour by ADR-0101 dec. 3): open the drag's
## single-snapshot undo for this span and make it the inspection root. Inert on an unresolvable
## span, or a kind with no Move (sound, the read-only compiled camera lane, the pacing strip).
func _on_span_body_drag_started(span_id: String) -> void:
	var span: Dictionary = Model.find_span(_timeline._score if _timeline else {}, span_id)
	var ref: Dictionary = _move_field_ref(span)
	if ref.is_empty():
		return
	if _host and _host.has_method("studio_begin_move"):
		_host.studio_begin_move(ref)
	if _timeline:
		_timeline.select_span(span_id)
	_set_root(Target.span(span_id))
	_body_drag_id = span_id
	# The gesture's PRISTINE address, captured once. A colour Move is STRUCTURAL — padding is
	# inserted, an emptied hold run is deleted — so the span's raw index changes under the
	# drag; and every motion re-plans from the snapshot taken at THIS instant. Re-resolving the
	# address from the reprojected score each motion would therefore aim at the wrong keyframe.
	_body_drag_ref = ref
	_body_drag_lane_id = String(span.get("lane_id", ""))


## ADR-0089 Move MOTION: stamp the pending slide (absolute delta from the grab). Applied at most
## once per _process frame — the timeline reported intent; the host owns the clamp + reproject.
func _on_span_body_dragged(span_id: String, delta: int) -> void:
	# Mid-gesture the address is the one captured at grab (see _on_span_body_drag_started); a
	# stray motion outside a live drag falls back to resolving the span it names.
	var ref: Dictionary = _body_drag_ref
	var kind: String = _body_drag_ref.get("channel", "")
	if ref.is_empty():
		var span: Dictionary = Model.find_span(_timeline._score if _timeline else {}, span_id)
		ref = _move_field_ref(span)
		kind = String(span.get("kind", ""))
	if ref.is_empty():
		return
	_pending_body_move = {"field_ref": ref, "delta": delta, "kind": kind}


## ADR-0089 Move RELEASE: flush the last pending slide, then close the one-undo bracket, fold
## the sim once, and settle the inspector + preview (the per-motion drag skipped those).
func _on_span_body_drag_ended(_span_id: String) -> void:
	_flush_pending_body_move()
	var landed = _host.studio_end_move() if (_host and _host.has_method("studio_end_move")) else {}
	# THE ONE SPLICE, for a structure-free colour drag: `studio_end_move` just performed it, and
	# a hint means it changed the lane. So this is where the gesture's ONLY reprojection happens
	# — the same `rebuild_kind_lanes` the old shape ran once per motion, run once per GESTURE,
	# with the address chase (`_follow_structural_move`) collapsing to the single renumber it
	# was always compensating for. Not a full `_rebuild_score`: a Move slides one span inside
	# one channel and preserves the lane's total length (ADR-0101 dec. 1), so every other kind's
	# lanes are byte-identical and re-running Model.build's whole spacer oracle would buy
	# nothing for ~400ms. Then the geometry offset is dropped, onto the committed lane.
	if landed is Dictionary and not landed.is_empty():
		_follow_structural_move(landed)
		_reproject_dragged_kind(String(_body_drag_ref.get("channel", "palette")))
	if _timeline:
		_timeline.clear_move_preview()
	# Re-root on where the span ACTUALLY landed: a structural colour Move renumbers it, so the
	# id the gesture started on can name a different keyframe by now.
	if _body_drag_id != "":
		_set_root(Target.span(_body_drag_id))
	_body_drag_id = ""
	_body_drag_ref = {}
	_body_drag_lane_id = ""
	_commit_drag_refold()
	_settle_after_drag()


## ADR-0089 Drag preview: a drag deferred every sim rescrub to keep the per-motion preview
## cheap (geometry-only); on release we fold ONCE so the particle cloud snaps to the committed
## result. The host no-ops when nothing sim-invalidating was deferred (a read-live colour drag).
func _commit_drag_refold() -> void:
	if _host and _host.has_method("studio_commit_refold"):
		_host.studio_commit_refold()


## Reproject ONLY the dragged channel's lane geometry (ADR-0089 Drag preview) — the sim-free
## layout update a live drag needs each motion, skipping the full Model.build whose palette +
## screen spacer oracle costs ~460ms. Correct because a drag on one channel leaves every other
## lane byte-identical (rebuild_kind_lanes reuses them by reference).
func _reproject_dragged_kind(kind: String) -> void:
	if _timeline == null:
		return
	_timeline.reproject_score(Model.rebuild_kind_lanes(
		_timeline._score, _effect_data, kind, _ghost_by_sound_id, _energy_by_sound_id))


## Settle after a geometry-only drag (ADR-0089 Drag preview): the per-motion path reprojected
## only lane geometry, so on release refresh the inspector, the derived end-frame marker, and
## re-seek the preview ONCE — the expensive inspector rebuild happens here, not every frame.
func _settle_after_drag() -> void:
	_recompute_end_frame()
	_render_current()


## The studio's DISPLAYED end frame: the faithful particle-reap end (EffectEndModel) floored at
## phase 2's authored content (EffectScoreModel.phase2_content_end) so a scheduled phase 2 plays
## live instead of dimming as dead when particles reap at the phase-2 boundary. EndModel stays
## faithful — this max() is the studio display choice (the "run through phase 2" decision). Reads
## the CURRENT score, so callers rebuild it (or load it) first.
func _recompute_end_frame() -> void:
	var derived := EndModel.derived_end_frame(_effect_data)
	var floor_p2 := Model.phase2_content_end(_timeline._score) if _timeline else 0
	_end_frame = maxi(derived, floor_p2)
	if _timeline:
		_timeline.set_end_frame(_end_frame)
	_seek(_timeline.get_playhead())


## Apply the pending Move slide (if any) through the host's live-preview seam, reprojecting the
## score so the span (and its neighbours' gaps) follow the drag. At most one per call.
func _flush_pending_body_move() -> void:
	if _pending_body_move.is_empty():
		return
	var mv: Dictionary = _pending_body_move
	_pending_body_move = {}
	if not (_host and _host.has_method("studio_move_preview")):
		return
	# Mid-Move (body id still set) → defer the sim refold; the geometry still reprojects per
	# motion below. _commit_drag_refold folds once on release (ADR-0089 Drag preview).
	var res = _host.studio_move_preview(mv["field_ref"], int(mv["delta"]), _body_drag_id != "")
	# STRUCTURE-FREE (the colour kinds): the session planned and stopped — not one keyframe
	# moved — so there is nothing to reproject and nothing to chase. The span tracks the cursor
	# as GEOMETRY, drawn at its committed start plus the planner's clamped delta, and the whole
	# splice waits for release (_on_span_body_drag_ended). This is the path that took the
	# gesture from ~95ms a motion — mint the padding, renumber the lane, re-fold the palette
	# spacer oracle, then throw it away and re-plan from the same snapshot on the next motion —
	# down to a repaint. A clamped-to-zero answer is drawn at HOME, not ignored: the motion
	# before it may have previewed a slide the author has now dragged back off.
	if res is Dictionary and bool(res.get("preview_only", false)):
		if _timeline:
			_timeline.set_move_preview(_body_drag_id, int(res.get("delta", 0)))
		return
	if res is Dictionary and not res.is_empty():
		# Live drag: reproject ONLY the dragged KIND's lanes. A full _rebuild_score re-runs
		# Model.build's whole ~400ms palette+screen spacer oracle every motion even though a
		# Move slides one span within one channel and preserves the lane's total length (the
		# two hold runs trade the delta), so every other kind's lanes stay byte-identical. The
		# inspector rebuild + re-seek settle ONCE on release (_settle_after_drag).
		if _body_drag_id != "":
			_reproject_dragged_kind(String(mv.get("kind", "particle")))
			_follow_structural_move(res)
		else:
			_rebuild_score()
			_render_current()
			_seek(_timeline.get_playhead())


## Keep the selection glued to a span a STRUCTURAL move renumbered (ADR-0101 decisions 6-7:
## padding keyframes are inserted, an emptied hold run is deleted). The plan reports where the
## span landed; without following it the selection would drift onto a neighbour mid-drag — and
## since `is_hidden_spacer` never hides the SELECTED span, a drifted selection would also
## reveal a hold as a painted tile. Inert for the non-structural kinds, which report no index.
func _follow_structural_move(res) -> void:
	if not (res is Dictionary) or not res.has("event_index") or _body_drag_lane_id == "":
		return
	var landed := "%s#%d" % [_body_drag_lane_id, int(res["event_index"])]
	if landed == _body_drag_id:
		return
	_body_drag_id = landed
	if _timeline:
		_timeline.select_span(landed)


## The Move field_ref for a span, dispatched by kind (ADR-0101 decision 3) — the address the
## kind's `plan_move` resolves its two neighbours from. Empty for a span that cannot slide (an
## unresolvable id, sound, the read-only compiled camera lane, the pacing strip), which is what
## both body-drag handlers gate on. Camera and colour reuse the boundary-drag addresses minus
## the `field` key: Move is not a per-field write, it re-times a whole span.
func _move_field_ref(span: Dictionary) -> Dictionary:
	if span.is_empty():
		return {}
	var ref: Dictionary
	match String(span.get("kind", "")):
		"particle":
			return _particle_move_field_ref(span)
		"camera":
			ref = _camera_end_field_ref(span)
		"palette":
			ref = _palette_boundary_field_ref(span)
		"screen":
			ref = _screen_boundary_field_ref(span)
		_:
			return {}
	ref.erase("field")
	return ref


## The Move field_ref for a particle span — the flat (phase, channel_index, keyframe index)
## address plan_move resolves the neighbours from.
func _particle_move_field_ref(span: Dictionary) -> Dictionary:
	return {
		"channel": "particle",
		"context": String(span.get("phase", "")),
		"channel_index": int(span.get("channel_index", -1)),
		"event_index": int(span.get("keyframe_index", -1)),
	}


## The boundary-drag field_ref for a span, dispatched by kind: camera → the end_frame address,
## palette / screen → the snapped-time_value boundary address (ADR-0087). Empty for any other
## kind (no edge grip exists there). All three share the report→apply→reproject seam + grip infra.
## The `span` passed here is the boundary's OWNER — the tile whose RIGHT edge it is — which
## `_edge_owner_span` resolves from the grabbed span + side.
func _edge_field_ref(span: Dictionary) -> Dictionary:
	match String(span.get("kind", "")):
		"camera":
			return _camera_end_field_ref(span)
		"palette":
			return _with_visibility(_palette_boundary_field_ref(span))
		"screen":
			return _with_visibility(_screen_boundary_field_ref(span))
		"particle":
			return _particle_boundary_field_ref(span)
	return {}


## Carry the drag's captured VISIBILITY mask into the colour boundary edit (ADR-0095). It
## rides the field_ref exactly like `ripple` does — as data, not ambient state — so the undo
## record replays the same consume semantics. Absent outside a drag, which is precisely what
## the typed Duration row wants: a typed length never eats a neighbouring spacer.
func _with_visibility(ref: Dictionary) -> Dictionary:
	if _edge_drag_visible.is_empty():
		return ref
	ref["visible"] = _edge_drag_visible
	return ref


## The span whose RIGHT edge this grip addresses (ADR-0095): the grabbed span itself for a
## right grip, the tile one index down for a left one. Storage knowledge lives HERE, not in the
## timeline — camera addresses by a split-surviving sub-channel ORDINAL, the other three by a
## raw keyframe index.
##
## For colour and particle the previous tile is addressed, not looked up: a particle GAP has no
## span at all (ADR-0089 emits none) and that is exactly the boundary a left grip exists to
## reach, so the owner is synthesized by decrementing the index. Only the phase offset and the
## lane address are read downstream, and both are lane-wide. Camera IS looked up, because its
## clamp reads the previous sibling's own authored extent — and camera lanes are fully tiled,
## so that sibling always exists above the ordinal >= 1 floor.
func _edge_owner_span(span: Dictionary, side: String) -> Dictionary:
	if side != "left":
		return span
	match String(span.get("kind", "")):
		"camera":
			return _camera_sibling(span, int(span.get("ordinal", -1)) - 1)
		"palette", "screen", "particle":
			var prev: Dictionary = span.duplicate()
			prev["keyframe_index"] = int(span.get("keyframe_index", -1)) - 1
			return prev
	return {}


## The camera sibling at `ordinal` on the same sub-channel lane, or {} when there is none.
func _camera_sibling(span: Dictionary, ordinal: int) -> Dictionary:
	if ordinal < 0:
		return {}
	var lane_id: String = String(span.get("lane_id", ""))
	for lane in (_timeline._score.get("lanes", []) if _timeline else []):
		if String(lane.get("id", "")) != lane_id:
			continue
		for s in lane.get("spans", []):
			if int(s.get("ordinal", -1)) == ordinal:
				return s
	return {}


## The colour lane's WALL MASK, indexed by keyframe index: true = authored work a drag must
## clamp against, false = the invisible empty space it may consume (ADR-0095). Selection is
## deliberately NOT consulted (`is_hidden_spacer(sp, "")`): a spacer that happens to be drawn
## because it is selected is still empty space, and selecting one must not change what a drag
## means. Empty for a non-colour lane — camera is fully tiled (nothing to consume) and particle
## consumes gaps inside its own encoder.
func _colour_lane_visibility(span: Dictionary) -> Array:
	if not (String(span.get("kind", "")) in ["palette", "screen"]):
		return []
	var out: Array = []
	for lane in (_timeline._score.get("lanes", []) if _timeline else []):
		if String(lane.get("id", "")) != String(span.get("lane_id", "")):
			continue
		for sp in lane.get("spans", []):
			var k: int = int(sp.get("keyframe_index", -1))
			if k < 0:
				continue
			while out.size() <= k:
				out.append(true)
			out[k] = not Timeline.is_hidden_spacer(sp, "")
	return out


## The span id the grabbed tile moved to after a consuming drag reclaimed `removed` slots
## below it — same lane, keyframe index shifted down (span ids are "<lane_id>#<index>").
func _shifted_span_id(span_id: String, removed: int) -> String:
	var cut: int = span_id.rfind("#")
	if cut < 0 or removed <= 0:
		return span_id
	var idx: int = int(span_id.substr(cut + 1))
	return "%s#%d" % [span_id.substr(0, cut), maxi(0, idx - removed)]


## The clamped phase-local boundary value for a span's edge drag. Camera clamps in the page
## (it knows its sub-channel neighbours by ordinal); palette and screen clamp in the CHANNEL
## (an array-level sum-preserving trade, where non-drawn keyframes between visible spans make
## a page-side neighbour lookup wrong), so here it only offset-corrects the absolute cursor
## frame to local.
func _edge_local_frame(span: Dictionary, abs_frame: int) -> int:
	if String(span.get("kind", "")) in ["palette", "screen", "particle"]:
		var offset: int = int(span.get("start", 0)) - int(span.get("authored_start", 0))
		return abs_frame - offset
	return _camera_edge_local_frame(span, abs_frame)


## The palette boundary-drag field_ref (ADR-0087): palette's two-dim address (phase +
## channel_name) plus the keyframe index, writing the synthetic `boundary_end` field the
## PaletteChannel encoder turns into a sum-preserving duration trade.
func _palette_boundary_field_ref(span: Dictionary) -> Dictionary:
	return {
		"channel": "palette",
		"context": String(span.get("phase", "")),
		"channel_name": String(span.get("fields", {}).get("channel", "")),
		"event_index": int(span.get("keyframe_index", -1)),
		"field": "boundary_end",
	}


## The screen boundary-drag field_ref (ADR-0087): screen's 1-D address (phase context only —
## one implicit channel) plus the keyframe index, writing the synthetic `boundary_end` field
## the ScreenChannel encoder turns into a sum-preserving duration trade.
func _screen_boundary_field_ref(span: Dictionary) -> Dictionary:
	return {
		"channel": "screen",
		"context": String(span.get("phase", "")),
		"event_index": int(span.get("keyframe_index", -1)),
		"field": "boundary_end",
	}


## The particle boundary-drag field_ref (ADR-0089 particle_timeline): particle's flat 2-D
## address (phase context + channel_index) plus the RAW keyframe index, writing the synthetic
## `boundary_end` field the ParticleTimelineChannel turns into a direct kf[N].time clamp.
func _particle_boundary_field_ref(span: Dictionary) -> Dictionary:
	return {
		"channel": "particle",
		"context": String(span.get("phase", "")),
		"channel_index": int(span.get("channel_index", -1)),
		"event_index": int(span.get("keyframe_index", -1)),
		"field": "boundary_end",
	}


## The camera end_frame field_ref for a camera span — the stable (channel, phase,
## sub-channel, ordinal) address the projector also emits. Empty for a non-camera span.
func _camera_end_field_ref(span: Dictionary) -> Dictionary:
	if String(span.get("kind", "")) != "camera":
		return {}
	var lane_name: String = String(_CAMERA_MASK_NAME.get(int(span.get("channel_index", 0)), ""))
	if lane_name == "":
		return {}
	return {
		"channel": "camera",
		"context": String(span.get("phase", "")),
		"camera_channel": lane_name,
		"ordinal": int(span.get("ordinal", -1)),
		"field": "end_frame",
	}


## Convert an absolute cursor frame to the clamped phase-local end_frame for `span`. The
## offset is the span's own start − authored_start (the axis includes the phase offset;
## end_frame is phase-local). Clamp: lower = prev_end (+1 for a DRAWN span, see below); upper
## = next_end − 1 (keep the NEIGHBOUR >= 1) or CAMERA_END_MAX for the tail (no successor).
## With RIPPLE on (ADR-0087 decs. 15-16) the neighbour bound is the thing ripple exists
## to drop — the upper clamp becomes TAIL HEADROOM, CAMERA_END_MAX − (lane_last_end −
## this_end), so shifting the whole lane tail can never push its last end past s16.
func _camera_edge_local_frame(span: Dictionary, abs_frame: int) -> int:
	var offset: int = int(span.get("start", 0)) - int(span.get("authored_start", 0))
	var local: int = abs_frame - offset
	# The lower bound is per-KIND-OF-SPAN, not one number. A DRAWN span must keep at least one
	# frame: a zero-width one renders nothing, drops out of the projection (`_camera_spans`
	# only emits `end > prev_end`) and takes its own grip with it — collapsing a drawn span is
	# the delete verb's job, not a drag's. A HOLD owns EMPTY SPACE, and empty space may
	# legitimately go to nothing — that is precisely the number MOVE already writes when it
	# slides the first event back to the phase origin (CameraChannel.move_span re-times the
	# lead hold to `span_start`). The two verbs write the same stored number through different
	# gestures, so a floor here and not there was a rule that only one of them obeyed.
	#
	# That mismatch was the author's residual gap: a rightward Move MANUFACTURES the hold that
	# owns the space it vacated, and by the grip-identity rule (EffectScoreTimeline's edge-rect
	# build) that hidden hold's RIGHT edge is the moved span's visible LEFT edge. Reaching for
	# that edge to drag the span back is therefore an EDGE drag on the hold, which this floor
	# stopped one frame short of the origin — a constant 1-frame residue, whatever the distance.
	var lo: int = int(span.get("authored_start", 0))
	if not bool(span.get("fields", {}).get("spacer", false)):
		lo += 1
	var hi: int
	if _ripple:
		hi = CAMERA_END_MAX - (_camera_lane_last_end(span) - int(span.get("authored_end", 0)))
	else:
		var next_end: int = _camera_next_end(span)
		hi = (next_end - 1) if next_end >= 0 else CAMERA_END_MAX
	return clampi(local, lo, hi)


## The lane TAIL's authored_end (phase-local) — the last end_frame the ripple shift will
## push — for the ripple headroom clamp. Falls back to the span's own end (a tail span's
## headroom is then the plain CAMERA_END_MAX bound, same as the non-ripple tail).
func _camera_lane_last_end(span: Dictionary) -> int:
	var lane_id: String = String(span.get("lane_id", ""))
	var last: int = int(span.get("authored_end", 0))
	for lane in (_timeline._score.get("lanes", []) if _timeline else []):
		if String(lane.get("id", "")) != lane_id:
			continue
		for s in lane.get("spans", []):
			last = maxi(last, int(s.get("authored_end", 0)))
	return last


## The next sub-channel sibling's authored_end (phase-local) — the event at ordinal+1 in the
## same lane — or -1 when `span` is the lane tail (no successor to trade against).
func _camera_next_end(span: Dictionary) -> int:
	var lane_id: String = String(span.get("lane_id", ""))
	var want: int = int(span.get("ordinal", -1)) + 1
	for lane in (_timeline._score.get("lanes", []) if _timeline else []):
		if String(lane.get("id", "")) != lane_id:
			continue
		for s in lane.get("spans", []):
			if int(s.get("ordinal", -1)) == want:
				return int(s.get("authored_end", -1))
	return -1


## ADR-0085 fire-drag GRAB: snapshot the byte-exact reversibility baseline for this
## trigger — its three-dim address, its fire frame, and a DEEP COPY of the channel's
## live gaps. The deep copy is essential: the live gaps mutate as the drag applies each
## motion, but every motion must be computed from the pristine drag-start gaps + a
## cumulative delta so re-dragging retraces exactly. Inert on an unresolvable span.
func _on_fire_drag_started(span_id: String) -> void:
	_fire_drag_baseline = {}
	var score: Dictionary = _timeline._score if _timeline else {}
	var span: Dictionary = Model.find_span(score, span_id)
	if span.is_empty():
		return
	var phase: String = str(span.get("phase", ""))
	var ci: int = int(span.get("channel_index", -1))
	var gaps: Array = []
	for kf in _sound_keyframes(phase, ci):
		gaps.append({
			"duration_frames": int(kf.get("duration_frames", 0)),
			"sound_id": int(kf.get("sound_id", 0)),
		})
	_fire_drag_baseline = {
		"span_id": span_id,
		"phase": phase,
		"channel_index": ci,
		"keyframe_index": int(span.get("keyframe_index", -1)),
		"fire": int(span.get("start", 0)),
		"gaps": gaps,
	}
	# Grabbing a trigger makes it the inspection root — selects it on the timeline AND shows
	# it in the inspector — so its Gap tracks the drag live (each move re-derives the
	# inspector, see _on_fire_frame_changed). Without this a fire-grab selected nothing and
	# the inspector stayed on a stale trigger. Select explicitly too: the render only reaches
	# the timeline highlight through _render_current, which no-ops when no inspector is bound.
	#
	# It seeds the CHAIN where one resolves (see `_seed_sound_chain`) rather than the bare
	# span root: the fire handle covers the select marker, so this is the path a plain click
	# on a trigger takes, and answering it with the config rows alone was the "where did my
	# all-in-one sound page go" bug. The trigger tier opens EXPANDED for the duration of the
	# grab so the Gap this comment is about is still on screen while the drag moves it.
	if _timeline:
		_timeline.select_span(span_id)
	_chain_expand_key = _chain_fold_key(Target.span(span_id))
	if not _seed_sound_chain(span_id):
		_chain_expand_key = ""
		_set_root(Target.span(span_id))
	# Bracket the gesture as ONE undo for the RIPPLE path (ADR-0087 decs. 15-16): its
	# per-motion scalar prior-gap edits coalesce into a single entry. Harmless with ripple
	# off — the stay-local compound path records its own single compound per motion and
	# never consults the bracket. The first trigger has no prior gap: nothing to bracket.
	var kf_i: int = int(span.get("keyframe_index", -1))
	if kf_i > 0 and _host and _host.has_method("studio_begin_coalesce"):
		_host.studio_begin_coalesce({"channel": "sound", "phase": phase,
			"channel_index": ci, "event_index": kf_i - 1, "field": "duration_frames"})


## ADR-0085 fire-drag RELEASE: drop the baseline so later motions fall back to live gaps,
## and close the ripple path's one-undo coalesce bracket.
func _on_fire_drag_ended(_span_id: String) -> void:
	_fire_drag_baseline = {}
	# Stop forcing the trigger tier open, but do NOT re-render to re-collapse it: a render
	# is a full inspector rebuild and this fires on every click release, drag or not. The
	# tier folds back on the next natural render, and until then it is showing the trigger
	# the author just touched.
	_chain_expand_key = ""
	if _host and _host.has_method("studio_end_coalesce"):
		_host.studio_end_coalesce()


## ADR-0085 fire-drag: the author dragged a sound trigger's instant marker to a new fire
## frame. Turn that into a STAY-LOCAL, SKIP-AWARE move (SoundGapMath: consume the gaps
## between this trigger and the previous AUDIBLE one, nearest-first; the right gap absorbs
## the move to pin every later fire), lower the governed-window duration_frames writes as
## ONE compound edit (a single undo) through the host choke point, then reproject the marker
## to the CLAMPED fire the module reports. Baseline-cumulative: when a drag baseline exists
## (the real UI path) the edits are computed from the fixed drag-start snapshot + a
## cumulative delta → byte-exact reversible. With no baseline (a synthetic/test call) it
## falls back to the live gaps. The first trigger is pinned (no prior gap) → no edits.
## Byte-faithful: only s16 gap fields change.
func _on_fire_frame_changed(span_id: String, new_fire_frame: int) -> void:
	var phase: String
	var ci: int
	var kf_index: int
	var kfs: Array
	var fire: int
	if not _fire_drag_baseline.is_empty() and str(_fire_drag_baseline.get("span_id", "")) == span_id:
		phase = str(_fire_drag_baseline.get("phase", ""))
		ci = int(_fire_drag_baseline.get("channel_index", -1))
		kf_index = int(_fire_drag_baseline.get("keyframe_index", -1))
		kfs = _fire_drag_baseline.get("gaps", [])
		fire = int(_fire_drag_baseline.get("fire", 0))
	else:
		var score: Dictionary = _timeline._score if _timeline else {}
		var span: Dictionary = Model.find_span(score, span_id)
		if span.is_empty():
			return
		phase = str(span.get("phase", ""))
		ci = int(span.get("channel_index", -1))
		kf_index = int(span.get("keyframe_index", -1))
		kfs = _sound_keyframes(phase, ci)
		fire = int(span.get("start", 0))
	if kfs.is_empty():
		return
	var delta: int = new_fire_frame - fire
	# RIPPLE (ADR-0087 decs. 15-16): skip the stay-local gap trade — edit ONLY the
	# grabbed trigger's PRIOR gap, clamped to [0, 32767], so every later fire shifts by
	# the delta. A plain scalar through the choke point (the grab's coalesce bracket folds
	# the motions into one undo); the first trigger has no prior gap and stays pinned.
	# Dragging left bottoms out at gap 0 (fires coincide, same as typing Gap = 0). The
	# typed Gap needs no branch — the gap IS the offset to the next trigger, natively
	# ripple. Baseline-cumulative like the trade path: `kfs`/`fire` are the drag-start
	# snapshot, so each motion recomputes from pristine gaps + the cumulative delta.
	if _ripple:
		if kf_index <= 0 or kf_index >= kfs.size():
			return
		var prior: int = int(kfs[kf_index - 1].get("duration_frames", 0))
		var new_prior: int = clampi(prior + delta, 0, 32767)
		if new_prior == prior:
			return
		_apply_edit({"channel": "sound", "phase": phase, "channel_index": ci,
			"event_index": kf_index - 1, "field": "duration_frames"}, new_prior)
		# Same live re-derive as the trade path below: the layout branch of _apply_edit
		# already reprojected the ruler; re-render so the grabbed trigger's Gap tracks.
		_render_current()
		return
	var res: Dictionary = GapMath.stay_local_edits(kfs, kf_index, delta)
	var edits: Dictionary = res.get("edits", {})
	if edits.is_empty():
		return
	var compound: Array = []
	for idx in edits:
		compound.append({
			"field_ref": {
				"channel": "sound", "phase": phase, "channel_index": ci,
				"event_index": int(idx), "field": "duration_frames",
			},
			"new_raw": int(edits[idx]),
		})
	if _host and _host.has_method("studio_apply_compound"):
		_host.studio_apply_compound(compound)
	# Reproject the whole score from the now-edited live gaps (ADR-0085 unified path): the
	# host applied the stay-local gap trade to _effect_data, so a rebuild lands EVERY marker
	# on its new fire — the dragged trigger on its clamped fire, the rest pinned. This is the
	# SAME transport-preserving reproject a typed Gap edit takes (_apply_edit's layout branch),
	# so dragging and typing agree — no surgical set_fire_frame path to drift out of sync.
	_rebuild_score()
	# Re-derive the inspector so the dragged trigger's Gap tracks the drag live (the grab made
	# it the inspection root). Reads the live keyframe → the just-applied gap. No-op when no
	# inspector is bound. Safe to re-render mid-drag: the mouse is on the timeline marker, not
	# a focused spinbox, so this doesn't fight the typed-edit's keep-focus rule.
	_render_current()


## The live raw sound keyframes for one addressed channel
## (`_effect_data.sound[phase][channel_index]["keyframes"]`), or [] when absent. The
## authoritative gaps SoundGapMath reads — the same dicts SoundChannel edits in place.
func _sound_keyframes(phase: String, ci: int) -> Array:
	if _effect_data == null or _effect_data.sound == null or not (_effect_data.sound is Dictionary):
		return []
	var channels = _effect_data.sound.get(phase, null)
	if not (channels is Array) or ci < 0 or ci >= channels.size():
		return []
	var ch = channels[ci]
	if not (ch is Dictionary):
		return []
	var kfs = ch.get("keyframes", [])
	return kfs if kfs is Array else []


## Seed the WYSIWYG target-colour picker(s) with the LIVE resulting top colour (#255). The
## projector cell is pure display (no runtime), so the page — which reaches the host's live
## ScreenSubsystem — injects the seed here, just before rendering, so the picker opens showing
## what the backdrop currently IS at the parked frame (the author nudges from there).
func _inject_target_color_seed(sections: Array) -> void:
	if not (_host and _host.has_method("studio_screen_top_color")):
		return
	var seed: Color = _host.studio_screen_top_color()
	for sec in sections:
		for f in sec.get("fields", []):
			# Only the SCREEN Blend picker seeds from the live backdrop. The PALETTE tint reuses
			# the same target_color widget but seeds itself (the forward fold of its stored bytes
			# over the fixed mid-grey reference, ADR-0087) — its seed must not be clobbered here.
			if f.get("editor", "") == "target_color" \
					and f.get("field_refs", {}).get("r", {}).get("channel", "") == "screen":
				f["seed"] = seed


## #255 target-colour pick callback: the author picked a target colour in the inspector. Route
## it to the host, which back-solves the signed Blend param through the REAL forward blend fold
## and lowers the chosen bytes through the choke point (read-live → repaints in place, no
## re-seek). Returns the ACHIEVED colour so the widget can show the honest result (a target may
## be unreachable → nearest match).
##
## VERDICT FRESHNESS (ADR-0087 dec. 29). The pick keeps the field set — but it does NOT
## keep the score: the spacer verdict is CONTEXTUAL (disable-equivalence folded over the whole
## stream), so writing bytes here can flip ANY keyframe's verdict on this lane. The host lowers
## the solved bytes with three DIRECT `studio_apply_edit` calls, bypassing this page's
## `_apply_edit` — so its unconditional `invalidates_layout` branch, the one that re-runs
## `SpacerVerdicts`, never fires. Without the re-derive below, a just-coloured event keeps its
## stale "spacer" verdict and VANISHES the moment it is deselected (`is_hidden_spacer`), while
## the RGB spinners — which do route through `_apply_edit` — appear to "work". That was the bug.
##
## The re-derive is KIND-SCOPED, not a full `_rebuild_score()`: palette and screen are
## independent fold streams in `SpacerVerdicts` (separate profiles, separate build_streams), so
## a screen byte can only flip screen verdicts. It has to be scoped — a full `Model.build` is
## ~280ms on E015 and `color_changed` fires continuously while the author drags in the popup.
## Safe for the live picker: `_reproject_dragged_kind` touches lane geometry only and never
## re-renders the inspector (which would free the open `ColorPickerButton` mid-signal).
func _pick_target(field_refs: Dictionary, target: Color) -> Color:
	if not (_host and _host.has_method("studio_pick_target")):
		return Color.BLACK
	var achieved = _host.studio_pick_target(field_refs, target)
	var kind: String = String(field_refs.get("r", {}).get("channel", ""))
	if kind in ["screen", "palette"]:
		_reproject_dragged_kind(kind)
	# The picker just wrote the solved Δ into the bytes — MATERIALIZE it into the +/- delta row
	# (the source of truth). update_picker=false: the picker IS the source, so don't move its own
	# value out from under the author's pick (only the boxes + the "actual" swatch refresh).
	_sync_tint(field_refs.get("r", {}), false)
	return achieved if achieved is Color else Color.BLACK


## Sparkline data source: one param curve's samples (empty if absent).
func _curve_samples(index: int) -> Array:
	if _effect_data == null:
		return []
	var curve = _effect_data.get_curve(index)
	return curve.samples if curve != null else []


## Write the transport-bar verdict strip. The label CLIPS, so the full string also goes to
## the tooltip — a refusal reason is usually a sentence and a truncated one is not actionable.
func _set_status(text: String) -> void:
	if _save_label == null:
		return
	_save_label.text = text
	_save_label.tooltip_text = text


func _tool_button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b
