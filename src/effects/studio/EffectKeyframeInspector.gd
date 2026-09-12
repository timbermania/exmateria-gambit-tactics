extends PanelContainer
## The Effect Studio **keyframe inspector** — the right-docked panel for the selected
## span. ONE render path (ADR-0071): the archetype-independent header rows
## (EffectScoreModel.inspector_header) above the projector's `[Section]` list
## (EffectScoreModel.inspector_sections). A particle span's sections are its **Event**
## section (what the span OWNS) + the SHARED **emitter** groups (Emitter / Particle ·
## born-with / Particle · over-life / Config), each param a `{from → to, curve}` row
## whose curve is an inline **sparkline** that opens the painter for THAT param. A
## tween/trigger (screen/palette/camera/sound) is a single `const`-field section.
## Read-only.
##
## Each group is ONE GridContainer so its sub-columns (name │ from │ → │ to │ curve)
## align across every row — the whole content lives in a ScrollContainer so a tall
## emitter stays reachable when the panel is capped to the dock height.
##
## A standalone PanelContainer, NOT a BaseDebugPanel: the Studio is development, not
## the F3 debug overlay (ADR-0069). Web/WASM-safe (pure Control). No `class_name`
## (ADR-0004). The grouped projection is the model's job (EffectScoreModel.emitter_view);
## this is thin glue that lays it out.

## Emitted whenever the shown content changes (select/clear) so the host can re-flow
## the panel height — a ScrollContainer absorbs growth, so minimum_size_changed won't.
signal content_changed

## Emitted when the author EXPLICITLY toggles a section fold. Distinct from
## `content_changed` on purpose (ADR-0085 amendment 2026-08-21, decision 5): the host's
## height latch is a high-water mark built to absorb the REBUILD transient, and a
## deliberate collapse is not a transient — it must drop the mark, or collapsing a section
## leaves a permanent gap under the inspector for that root.
signal fold_toggled

const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const Sparkline = preload("res://src/effects/studio/EffectCurveSparkline.gd")
const ColourRibbonClass = preload("res://src/effects/studio/ColourRibbon.gd")
const ColourBoxPickerClass = preload("res://src/effects/studio/ColourBoxPicker.gd")
const ColourKeyframeTrackClass = preload("res://src/effects/studio/ColourKeyframeTrack.gd")
const EffectCurveClass = ExMateriaEffects.EffectCurve
const CurvePicker = preload("res://src/effects/studio/EffectCurvePicker.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const CameraUnits = preload("res://src/effects/studio/CameraUnits.gd")
const ScrubField = preload("res://src/effects/studio/ScrubField.gd")

# Header field rows flow left→right as label|value pairs (3 pairs per line).
const GRID_COLUMNS: int = 6
const PANEL_MARGIN: float = 8.0
# Nested param-group folds indent their rows under the fold header (ADR-0089).
const FOLD_INDENT: float = 14.0
# Fixed column widths (ADR-0089 decision 6): the row-name label and each cell
# type hold ONE width — clipped, never grown by content — so columns align
# across every grid in the inspector (grids can't share sizing on their own).
const NAME_COL_WIDTH: float = 240.0
## The TIGHT name column, for a panel whose row names are short and whose width is contended
## — the unified animation screen's two inspectors. 240 is sized for "Position · at start";
## the sequence view's longest name is "Depth mode" and the focus block's "Semi-trans on",
## so the column was spending 240px on ~90px of text and pushing every value widget right of
## it. That waste is not free here: the strip's declared `content_width()` is the term the
## ADR-0102 focus column's width is claimed from, so it came out of the frame parameters.
const NAME_COL_WIDTH_TIGHT: float = 132.0
const INT_CELL_WIDTH: float = 96.0   # matches ScrubField's intrinsic fixed size
const ENUM_CELL_WIDTH: float = 170.0
# Opaque authoring-surface background — matches the timeline's COL_BG.
const COL_BG := Color(0.09, 0.10, 0.13)
const COL_LABEL := Color(0.60, 0.66, 0.78)
const COL_VALUE := Color(0.90, 0.93, 0.98)
const COL_DIM := Color(0.42, 0.46, 0.55)      # disabled / inert (to without a curve)
const COL_WARN := Color(0.95, 0.72, 0.38)     # out-of-corpus tell (empirical range)
const COL_WARN_MILD := Color(0.78, 0.66, 0.46) # milder "unusual for X" instrument-envelope tell
const COL_GROUP := Color(0.72, 0.80, 0.95)
const COL_LINK := Color(0.55, 0.78, 1.00)     # clickable reference (link field / breadcrumb)

## Whether this panel draws its OWN chrome — the target title and the header grid above
## the sections. True for the page's main inspector; FALSE for a second instance that is
## already inside a titled panel of its own (the unified animation screen's focus panel),
## where the title would be a second name for a surface that has one and the empty grid a
## blank row. Consulted on every `show_target`, so it can be set once at construction.
var show_own_chrome: bool = true
## Whether the content may scroll SIDEWAYS as well as down. Off for the page's main
## inspector, whose declared `content_width()` is the number the right-hand column is
## clamped against (ADR-0100) — a panel that could scroll horizontally would report no
## width and the column would land on it. On for a second instance parked in a NARROW
## slot of its own (the unified animation screen's focus panel), where the alternative is
## a container that refuses to shrink below its widest row and overflows onto its
## neighbour. Read once in `_ready`, so set it before adding the node to the tree.
var allow_horizontal_scroll: bool = false
## The row-name column's width for THIS panel. `NAME_COL_WIDTH` (ADR-0089 dec. 6) is the
## number that keeps every grid in one panel column-aligned; it is per-PANEL, not global,
## because a second instance in a ~334px column of its own (the unified animation screen's
## focus panel) spends 240 of it on names and scrolls its values off the right. Alignment
## is preserved where it is claimed — inside a panel — and two panels side by side were
## never aligned with each other.
var name_column_width: float = NAME_COL_WIDTH
var _title: Label
# The content scroll. Held so a chain's scroll-to anchors (ADR-0073 dec. 11)
# can bring an already-rendered section into view instead of navigating to it.
var _scroll: ScrollContainer
var _grid: GridContainer
## Supplied by the host: `func(thumb_spec: Dictionary) -> Control`, returning the
## picture a header row or a SECTION asked for via its `thumb` key, or null to decline
## (#247). A Callable rather than effect data because this inspector renders SPECS and
## knows nothing about effects — see `_label_cell` and `_build_group`.
var thumbnail_provider: Callable = Callable()
var _placeholder: Label
var _row_count: int = 0
var _content: VBoxContainer
var _groups_box: VBoxContainer
# Live group grids as {grid, sub_cols} — single column inspector-wide (ADR-0089
# decision 1): columns are set once at build and never re-flowed by width.
var _group_grids: Array = []
# ADR-0089 nested param-group folds. `_fold_state` is the SESSION memory, keyed
# "<emitter_index>:<group id>" → expanded — deliberately NOT cleared on rebuild
# (re-selection / live-reproject must not snap folds shut). `_folds` are the live
# fold entries ({key, label, header, body, …}) and `_fold_bulk` the per-section
# Expand all / Collapse all controls — both rebuilt with the rows (test seams).
var _fold_state: Dictionary = {}
# The CHAIN's view of the section accordion (ADR-0085 amendment 2026-08-21, decision 4).
# The fold MEMORY itself is `_section_state` below — there is exactly one, keyed by the
# id a projector supplies as either `fold_id` or `fold_key`; two dicts keyed differently
# is how a fold silently stops being remembered. `_section_folds` are the live entries
# with their shut-form `summary` (a test seam) and `_section_by_key` locates one for the
# scroll-to anchor a chain's ancestor links degrade to.
var _section_folds: Array = []
var _section_by_key: Dictionary = {}
var _folds: Array = []
var _fold_bulk: Array = []
# The SECTION accordion, one level up from the param folds above and the same shape of
# memory: `_section_state` is keyed by a section's projector-supplied `fold_id` →
# expanded, and like `_fold_state` it is deliberately NOT cleared on rebuild, so a live
# reproject (the one an author's own edit fires) never shuts the section being typed
# into. `_section_folds` are the live entries (see below); `_section_bulk` is
# the one Expand all / Collapse all pair above the list, present whenever there is more
# than one section to drive. All three are test seams.
var _section_state: Dictionary = {}
var _section_bulk: Dictionary = {}
## The DECLARED content width, taken once at the end of a build — see `content_width()`.
var _content_width: float = 0.0
## The live `follow` buttons as `{ref, button, state}` — an edit to the value beside one
## re-aims it, so its destination is held in a mutable `state` cell. See `refresh_follows`.
var _follows: Array = []
var _sparklines: Array = []
# The emitter-elapsed playhead marker (ADR-0089 amendment). `_marker` is the current
# CurvePlayheadMarker payload; `_marker_sparklines` are the EMITTER-clocked sparklines it
# rides (collected at build) so the continuous sweep refreshes them without a rebuild.
# `_cur_section_clock` is the clock of the section _build_group is mid-way through — the
# gate that keeps age-clocked (over-life) sparklines marker-free.
var _marker: Dictionary = {}
var _marker_sparklines: Array = []
var _cur_section_clock: String = ""
# The three `Color (R/G/B) · curve` widgets, keyed by channel — recorded when a cell carries a
# `colour_channel` tag (ADR-0089 colour-keyframe editing-UX amendment, the stale-sparkline bug).
# A recolour forks the emitter's colour curves onto fresh indices; the page re-feeds these via
# refresh_colour_channels() so the "curves on the left" track the fork instead of a snapshot.
var _colour_channel_sparklines: Dictionary = {}
var _colour_channel_pickers: Dictionary = {}
# Field-relevance salience (ADR-0089 amendment). `_relevance_markers` are the live
# `!`-marker registrations ({kind: "inactive"/"dead"/"gate", why, node}); `_hidden_reveals`
# are the per-section "N hidden (not in effect)" folds that gather the Dead groups.
var _relevance_markers: Array = []
var _hidden_reveals: Array = []
# The velocity-family formula views rendered under a Dead reveal (ADR-0089 velocity
# amendment) — `{mode, fix, marked, node}`, a test seam + the one-per-section contract.
var _velocity_formulas: Array = []
# The salience marker glyphs: a bright `!` on a suppressed/inactive field, an
# outward `!` on a gate (hover = what it suppresses).
const MARK_INACTIVE := "! "
const MARK_GATE := "! "
const COL_MARK := Color(0.95, 0.78, 0.35)     # salience marker accent
var _param_row_count: int = 0
# "Hide inert" mode (ADR-0089 amendment): a session-local VIEW toggle owned by the page and
# threaded in through show_target. While on, a group/field renders iff its relevance is Live
# (or carries no verdict — plain Config/header rows); Inactive/Dead fields, suppressing gates
# at their neutral, the Dead reveal, the formula view, and now-empty sections all vanish. The
# Model still attaches verdicts; this is purely what the view chooses to draw.
var _hide_inert: bool = false
# The follow-a-reference callback (ADR-0073): a `link` field / clickable header row
# calls this with the InspectionTarget to navigate to. Host wires it to its nav stack.
var _on_navigate: Callable = func(_t): pass
# The live link Buttons (header + fields) — a test seam to drive the navigate path.
var _link_buttons: Array = []
# ADR-0075 per-edge child-spawn suppression. A live child-emitter link renders a checkbox
# beside its button; `_suppressed_provider.call(parent, edge)` seeds its checked state and
# `_on_toggle_suppress.call(parent, edge, suppressed)` mutates. Checked = spawning.
var _suppressed_provider: Callable = func(_p, _e): return false
var _on_toggle_suppress: Callable = func(_p, _e, _s): pass
# The live child-suppression CheckBoxes — a test seam to drive the toggle path.
var _child_toggles: Array = []
# The #255 authoring mutate callback: an editable cell (shape "edit") lowers a raw-byte
# edit through `_on_mutate.call(field_ref, new_raw)` → the host's EffectEditSession choke
# point. Used by the structural "choice" editors (e.g. the Kind selector).
var _on_mutate: Callable = func(_ref, _raw): pass
# The #255 target-colour authoring callback: a "target_color" cell fans the author's picked
# colour + the tween's field_refs through `_on_pick_target.call(field_refs, picked)` → the host,
# which back-solves the Blend param and lowers the chosen bytes through the choke point. It
# returns the ACHIEVED colour (which may differ from the pick when the target is unreachable).
var _on_pick_target: Callable = func(_refs, _col): return Color.BLACK
# The live target-colour pickers (ColorPickerButtons) — a test seam to drive the pick path.
var _pick_widgets: Array = []
# The live Gradient-stop pickers (ColorPickerButtons) — a test seam distinct from the Blend
# target pickers above. A gradient_color cell fans three DIRECT byte writes through _on_mutate
# (unsigned absolute set, no solver), so its widgets live on their own list.
var _gradient_pickers: Array = []
# The read-only "actual result" swatch beside the picker (repainted to the achieved colour) —
# a test seam AND the honest feedback when a picked target is unreachable.
var _actual_swatch: ColorRect = null
# The live choice widgets (OptionButtons, e.g. the Kind selector) — a test seam for the
# structural-variant mutate path, kept distinct from the pick widgets above.
var _choice_widgets: Array = []
# The F1 shared editor-widget kit (#264) — generic primitives every subsystem authoring build
# reuses. Each is a live-widget test seam, distinct from the screen-specific pickers above:
# `int` SpinBoxes, value-carrying `enum` OptionButtons, and `bitflags` checkbox GROUPS (each
# entry is the Array of that group's CheckBoxes). All lower through the ONE mutate callback.
var _int_widgets: Array = []
var _enum_widgets: Array = []
# NAVIGATING dropdowns (`nav_choice`) — an OptionButton whose items each carry an
# inspection TARGET. Deliberately a separate seam from `_enum_widgets`: those fan a raw
# byte through the mutate callback, these move the nav stack and never approach the write
# choke point at all (ADR-0085 amendment 2026-08-21, decision 3).
var _nav_choice_widgets: Array = []
var _bitflag_groups: Array = []
# The curve-assignment thumbnail pickers (`curve_pick`, ADR-0089 curve-UX amendment) —
# a live-widget test seam, distinct from the enum OptionButtons above; each fans the
# chosen nibble VALUE through the ONE mutate callback (byte-identical to the old enum).
var _curve_pick_widgets: Array = []
# The signed-Δ RGB row (ADR-0087 palette byte coverage): three signed-byte SpinBoxes and a
# "No tint" reset button — a test seam distinct from the pickers above. The widgets convert
# raw byte <-> signed display; the reset zeros all three (the explicit Δ = 0,0,0 no-op).
var _signed_rgb_boxes: Array = []
var _signed_rgb_reset: Button = null
# The dim per-value detail Labels beside a value_detail-carrying `enum` cell (ADR-0085
# instrument-chip loop verdict): one per such cell, refreshed on selection.
var _enum_detail_hints: Array = []
# The live `radio` groups (#289 SoundContainer Pick mode) — each entry is that field's
# Array of CheckBoxes (one ButtonGroup), in choice order. Value-carrying like `enum`,
# but ALL choices stay visible so the whole option space is scannable at once.
var _radio_groups: Array = []
# A projector-declared `action` field (shape "action") renders as a Button that, on press,
# fires `_on_action.call(action_dict)` — a generic "do a studio thing" seam (distinct from
# navigate/mutate). The SoundContainer "Audition sequence" affordance rides it. Its live
# Buttons are a test seam.
var _on_action: Callable = func(_a): pass
var _action_buttons: Array = []
# The dim inline "≈ achieved" hints beside a UNIT-tagged int cell (one per unit cell, in
# render order) — the honest quantization tell when a typed human value can't land exactly on
# a raw unit. A test seam AND the author-facing "you'll actually get X" feedback.
var _unit_hints: Array = []

# The dim inline empirical-usage-range hints beside a range-bound int cell (ADR-0085 §4):
# "typical A…B · median M · n=N" when the value sits inside the observed corpus, and an
# amber out-of-corpus tell when it leaves that envelope. A test seam AND author feedback.
var _range_hints: Array = []
# The SECOND, instrument-conditional line beside a range-bound int cell (ADR-0085
# 2026-08-12): "with <name>: A…B · median M · n=N" (n-adaptive), "none with <name>"
# for the empty bucket, or a milder "unusual for <name>" tell. One per cell that has
# a range_instrument; a separate seam from _range_hints so the global line's count
# (and its own tell) stay independent.
var _range_instrument_hints: Array = []


func _ready() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = COL_BG
	bg.set_content_margin_all(PANEL_MARGIN)
	add_theme_stylebox_override("panel", bg)

	# Content lives in a vertical scroll so a tall emitter is reachable when the host
	# caps the panel to the dock height (else the bottom rows run off-screen).
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = (ScrollContainer.SCROLL_MODE_AUTO if allow_horizontal_scroll
		else ScrollContainer.SCROLL_MODE_DISABLED)
	add_child(scroll)
	_scroll = scroll

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 6)
	scroll.add_child(_content)

	_title = Label.new()
	_title.text = "Keyframe"
	_title.add_theme_font_size_override("font_size", 14)
	_content.add_child(_title)
	_content.add_child(HSeparator.new())

	_placeholder = Label.new()
	_placeholder.text = "Select a span to inspect its keyframe."
	_placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_placeholder.modulate = Color(0.6, 0.65, 0.75)
	_content.add_child(_placeholder)

	_grid = GridContainer.new()
	_grid.columns = GRID_COLUMNS
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 4)
	_grid.visible = false
	_content.add_child(_grid)

	_groups_box = VBoxContainer.new()
	_groups_box.add_theme_constant_override("separation", 6)
	_content.add_child(_groups_box)


## Render a selected span through ONE path (ADR-0071): the archetype-independent
## header rows (EffectScoreModel.inspector_header), then the projector's `[Section]`
## list (EffectScoreModel.inspector_sections). A particle span's sections are its Event
## section + the shared emitter groups; a tween/trigger is a single section. A section
## whose fields are param-shaped renders sparklines (emitter over-life curves); a
## `const`-field section renders name/value. `curve_provider.call(index)` returns a
## curve's samples for a sparkline; `on_open.call(curve_index, name[, used_n])` opens the
## painter (a 3-arg consumer also receives the used window — ADR-0089 curve-UX amendment).
func show_target(target: Dictionary, header_rows: Array, sections: Array, curve_provider: Callable, on_open: Callable, on_navigate: Callable = func(_t): pass, suppressed_provider: Callable = func(_p, _e): return false, on_toggle_suppress: Callable = func(_p, _e, _s): pass, on_mutate: Callable = func(_ref, _raw): pass, on_pick_target: Callable = func(_refs, _col): return Color.BLACK, hide_inert: bool = false, marker: Dictionary = {}, on_action: Callable = func(_a): pass) -> void:
	if _grid == null:
		return
	_hide_inert = hide_inert
	_marker = marker
	_marker_sparklines.clear()
	if Target.is_empty(target):
		clear()
		return
	_on_navigate = on_navigate
	_suppressed_provider = suppressed_provider
	_on_toggle_suppress = on_toggle_suppress
	_on_mutate = on_mutate
	_on_pick_target = on_pick_target
	_on_action = on_action
	_action_buttons.clear()
	_link_buttons.clear()
	_child_toggles.clear()
	_pick_widgets.clear()
	_gradient_pickers.clear()
	_actual_swatch = null
	_choice_widgets.clear()
	_int_widgets.clear()
	_enum_widgets.clear()
	_nav_choice_widgets.clear()
	_section_folds.clear()
	_section_by_key.clear()
	_enum_detail_hints.clear()
	_curve_pick_widgets.clear()
	_bitflag_groups.clear()
	_signed_rgb_boxes.clear()
	_signed_rgb_reset = null
	_radio_groups.clear()
	_range_hints.clear()
	_range_instrument_hints.clear()
	_unit_hints.clear()
	_colour_channel_sparklines.clear()
	_colour_channel_pickers.clear()
	_render_header_rows(target, header_rows)
	_clear_groups()
	for section in sections:
		_build_group(section, curve_provider, on_open)
	_add_section_bulk_row()
	_record_content_width()
	content_changed.emit()


## Natural (unscrolled) content height — the height the host grows the panel toward
## before capping to the dock (the ScrollContainer hides this from min-size).
func content_height() -> float:
	if _content == null:
		return 0.0
	return _content.get_combined_minimum_size().y + PANEL_MARGIN * 2.0


## DECLARED content width — the width the host must leave this panel so nothing inside
## it is clipped, and therefore the width a right-hand column may NOT take (ADR-0100).
## The exact peer of `content_height()` above, and it exists for the same reason: a live
## minimum under-reports.
##
## Why it cannot simply read `get_combined_minimum_size().x`. A collapsed section's body
## is `visible = false`, and Godot's container minimum SKIPS invisible children — so the
## live minimum SWINGS with fold state. On the sequence view that is the difference
## between 653 and 311, and capping a column on it would resize the player every time
## the author opened a section. Recorded at BUILD instead, over every body at both
## accordion levels whether it is showing or not, and held until the next rebuild.
func content_width() -> float:
	return _content_width


## Take the width measurement, once, at the end of a build. Walks the registered
## accordion entries rather than the node tree: `_section_folds` and `_folds` are exactly the
## set of bodies that can be hidden, and each already holds the node.
func _record_content_width() -> void:
	if _content == null:
		_content_width = 0.0
		return
	# Everything currently showing — the header grid, the title, every section title row.
	var w: float = _content.get_combined_minimum_size().x
	# Plus every body that is (or could be) shut. A section body sits one indent in, and
	# a param fold's body carries its own indent already and sits inside a section body.
	for entry in _section_folds:
		w = maxf(w, (entry["body"] as Control).get_combined_minimum_size().x + FOLD_INDENT)
	for fold in _folds:
		w = maxf(w, (fold["body"] as Control).get_combined_minimum_size().x + FOLD_INDENT)
	# The panel's own overhead around `_content`, MEASURED rather than assumed to be the
	# two stylebox margins: the ScrollContainer reserves its vertical scrollbar too, and
	# a declared width that forgot it came out 8px UNDER the live minimum — i.e. under-
	# reporting, which is the one thing this number may never do.
	_content_width = w + maxf(0.0,
		get_combined_minimum_size().x - _content.get_combined_minimum_size().x)


## Render the header rows for a target. A row is either a plain `{label, value}` pair
## or a clickable `{label, link:{label, target}}` (breadcrumb / provenance edge, ADR-0073)
## whose value cell is a button that navigates. Title comes from the target, not a span id.
func _render_header_rows(target: Dictionary, rows: Array) -> void:
	_clear_grid()
	_row_count = rows.size()
	for row in rows:
		# A malformed row used to crash here with a bare "Invalid access to property
		# or key 'label'", naming neither the projector nor the kind — and only at
		# click time, so a projector test that stringifies its rows never sees it.
		# Report it and skip: loud in the log, legible, and the rest still renders.
		if not (row is Dictionary) or not row.has("label") \
				or not (row.has("value") or row.has("link")):
			push_error("inspector: header row for '%s' must be {label, value} or {label, link}, got %s"
				% [Target.kind(target), str(row)])
			_row_count -= 1
			continue
		var label_cell := _label_cell(row)
		_grid.add_child(label_cell)
		var value_cell: Control
		if row.has("link"):
			value_cell = _link_button(row["link"])
		else:
			value_cell = _cell(str(row["value"]), COL_VALUE)
		_grid.add_child(value_cell)
		# A header row may carry a `tooltip`, the same key a param row does and applied the
		# same way — to BOTH cells, so hovering either explains it. It is what lets a header
		# value be SHORT: "6 ticks" in the grid, "up to the terminator that ends the stream"
		# on hover, instead of a sentence setting the panel's declared width (ADR-0100).
		_apply_tooltip(label_cell, str(row.get("tooltip", "")))
		_apply_tooltip(value_cell, str(row.get("tooltip", "")))
	_title.text = Target.title(target)
	_title.visible = show_own_chrome
	_grid.visible = show_own_chrome
	_placeholder.visible = false


## One accordion section: a toggle header (expanded by default) over a single-column
## body (ADR-0089 decision 1 — no width reflow). Ungrouped rows share grids whose
## sub-columns align (a shaped group uses 5: name/from/→/to/curve; a curve-only group
## 2: name/curve; Config 2: name/value). Rows carrying an explicit `group` stamp
## (decision 7) cluster into ONE nested fold per parameter group — collapsed unless
## the session fold state says otherwise — and a fold-carrying section grows an
## Expand all / Collapse all control beside its title.
func _build_group(group: Dictionary, curve_provider: Callable, on_open: Callable) -> void:
	var kind := _group_kind(group)
	var sub_cols := 5 if kind == "shaped" else 2
	# Clock-domain gate (ADR-0089 amendment): sparklines built under this section carry the
	# span-anchored playhead marker only when the section is emitter-clocked. Set for the whole
	# synchronous subtree of this call (header sparkline + fold-body curve rows).
	_cur_section_clock = str(group.get("clock", ""))

	# "Hide inert" empty-section prune (ADR-0089 amendment): if hiding leaves this section with
	# zero rendered rows, omit its header too (no bare headers). `_param_row_count` only counts
	# rendered rows, so its delta over this section is the row count; roll `_fold_bulk` back to
	# undo the Expand/Collapse pair built for a section we then drop.
	var rows_before := _param_row_count
	var fold_bulk_before := _fold_bulk.size()

	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 2)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 2)

	var title: String = group.get("title", "")
	# TWO projectors' worth of fold vocabulary, ONE mechanism. The sequence view asks for a
	# section to start SHUT with a stable `fold_id` so the author's toggle outlives the
	# rebuild an edit fires; chain inspection (ADR-0085 amendment 2026-08-21, decision 4)
	# asks the same thing under `fold_key` and additionally supplies a one-line `summary`
	# for the shut form, so a chain's upper tiers cede the vertical budget to the FEDS
	# surface while still saying what they are. They are the same concept, so they resolve
	# to one id and one state dict â two half-working memories keyed differently is how a
	# fold silently stops being remembered. A section declaring none of them keeps today's
	# behaviour exactly: built expanded, titled "▾  <title>", never remembered.
	var section_id := str(group.get("fold_id", group.get("fold_key", "")))
	var summary: String = str(group.get("summary", ""))
	var expanded: bool = not bool(group.get("collapsed", false))
	if section_id != "" and _section_state.has(section_id):
		expanded = bool(_section_state[section_id])
	# The collapsed form mirrors the nested param folds' `▸ label    summary`.
	var section_text := func(on: bool) -> String:
		if on or summary == "":
			return "%s  %s" % ["▾" if on else "▸", title]
		return "▸  %s    %s" % [title, summary]
	var header := Button.new()
	header.toggle_mode = true
	header.button_pressed = expanded
	header.focus_mode = Control.FOCUS_NONE
	header.flat = true
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.add_theme_color_override("font_color", COL_GROUP)
	header.text = section_text.call(expanded)
	# THE SECTION'S LONG FORM RIDES THE TOOLTIP (2026-08-20). A header is a `Button`, so its
	# TEXT sets its minimum width and that propagates through the inspector's content width
	# to the whole right column â which is how "Frameset 0 â shown by opcode 1 Â· colour from
	# emitter 2 (drilled from)" broke the value tables sharing the row. ADR-0103 dec. 5's
	# "a title suffix costs 0px" was reasoning about HEIGHT. Text here costs width; a
	# tooltip costs nothing.
	header.tooltip_text = str(group.get("tooltip", ""))
	# `toggled` only fires on CHANGE, so the body's opening visibility is set here rather
	# than left to the Button â a section built SHUT would otherwise render its body
	# anyway and the arrow beside the title would be lying.
	body.visible = expanded
	header.toggled.connect(func(on: bool):
		body.visible = on
		header.text = section_text.call(on)
		if section_id != "":
			_section_state[section_id] = on
		# An EXPLICIT toggle, never a rebuild â the host drops its height high-water mark.
		fold_toggled.emit())

	# The fold keys this section will hang (in row order) — known up front so the
	# Expand all / Collapse all control can be built into the title row.
	var fold_keys: Array = []
	for param in group.get("fields", []):
		var k := _fold_key(param.get("group", {}))
		if k != "" and not (k in fold_keys):
			fold_keys.append(k)

	# The section's own PICTURE, when it asked for one and the host can supply it (#247).
	# It rides the TITLE row, not the body, so a SHUT section still shows it — that is
	# what makes a column of collapsed opcode sections read as a film strip.
	var thumb: Control = null
	if group.has("thumb") and thumbnail_provider.is_valid():
		var supplied = thumbnail_provider.call(group["thumb"])
		if supplied is Control:
			thumb = supplied

	if fold_keys.is_empty() and thumb == null:
		section.add_child(header)
	else:
		# Buttons ride right beside the title (an expanding header would shove
		# them to the panel's far edge, unreachable by eye on a wide dock).
		var title_row := HBoxContainer.new()
		title_row.add_theme_constant_override("separation", 12)
		if thumb != null:
			title_row.add_child(thumb)
		title_row.add_child(header)
		if not fold_keys.is_empty():
			var expand_btn := _bulk_fold_button("Expand all", fold_keys, true)
			var collapse_btn := _bulk_fold_button("Collapse all", fold_keys, false)
			title_row.add_child(expand_btn)
			title_row.add_child(collapse_btn)
			_fold_bulk.append({"expand": expand_btn, "collapse": collapse_btn})
		section.add_child(title_row)

	# "shared by N events" (ADR-0071) — the honest fan-out signal on the emitter's
	# SHARED sections. A dim sub-header under the title; absent on span-local sections.
	var note: String = group.get("note", "")
	if note != "":
		var note_lbl := Label.new()
		note_lbl.text = note
		note_lbl.modulate = COL_DIM
		note_lbl.add_theme_font_size_override("font_size", 10)
		section.add_child(note_lbl)

	# Cluster rows: consecutive same-stamp rows land in that group's fold grid;
	# ungrouped runs share a plain grid. Order is preserved either way. A group the
	# oracle verdicts DEAD (ADR-0089 amendment) is diverted into a per-section
	# "N hidden (not in effect)" reveal instead of rendered inline — the field-count
	# win — while its end-axis rows are collapsed in a Live group with no curve.
	var plain_grid: GridContainer = null
	var fold_grid: GridContainer = null
	var fold_key := ""
	var reveal: Dictionary = {}   # lazy Dead-group reveal ({header, body}), created on demand
	for param in group.get("fields", []):
		var key := _fold_key(param.get("group", {}))
		if key == "":
			# Plain row (no group stamp). In "Hide inert" mode a lone Inactive/Dead field —
			# a colour channel with colour off, a child index, a homing blend, a gate at its
			# neutral — is dropped outright (the row that would carry its `!` never renders).
			if _hidden(param.get("relevance", {})):
				continue
			fold_key = ""
			if plain_grid == null:
				plain_grid = _param_grid(sub_cols)
				body.add_child(plain_grid)
			_add_param_cells(plain_grid, kind, param, curve_provider, on_open)
		else:
			plain_grid = null
			var stamp: Dictionary = param.get("group", {})
			var rel: Dictionary = stamp.get("relevance", {})
			if key != fold_key:
				fold_key = key
				# "Hide inert": an Inactive/Dead group fold vanishes wholesale — do NOT
				# divert a Dead one to the reveal (that stays empty → no reveal, no formula).
				if _hidden(rel):
					fold_grid = null
				elif str(rel.get("state", "")) == "dead":
					if reveal.is_empty():
						reveal = _make_hidden_reveal(body)
					fold_grid = _make_fold(stamp, key, sub_cols, reveal["body"], curve_provider, on_open)
					reveal["count"] = int(reveal.get("count", 0)) + 1
				else:
					fold_grid = _make_fold(stamp, key, sub_cols, body, curve_provider, on_open)
			if fold_grid == null:
				continue   # a hidden fold — drop every one of its rows
			# End-axis Dead (Live group, no curve): drop the "at end" rows — the end
			# column is unread, so collapse it in place (a note rides the header).
			if bool(rel.get("end_dead", false)) and str(rel.get("state", "")) != "dead" \
					and " at end" in str(param.get("name", "")):
				continue
			_add_param_cells(fold_grid, kind, param, curve_provider, on_open)
		_param_row_count += 1
	if not reveal.is_empty():
		reveal["header"].text = "▸  %d hidden (not in effect)" % int(reveal.get("count", 0))
		_hidden_reveals.append({"header": reveal["header"], "body": reveal["body"],
			"count": int(reveal.get("count", 0))})
		# Velocity-family formula view (ADR-0089 velocity amendment): rendered ONCE per
		# section, under its Dead reveal, only when the section carries the descriptor
		# (something in the family is Dead). Explains the annihilation with marked
		# factors + an imperative fix line naming flag labels.
		var vformula: Dictionary = group.get("velocity_formula", {})
		if not vformula.is_empty():
			_add_velocity_formula(reveal["body"], vformula)
	# Indent the whole body one hierarchy step under the section header, so a fold's
	# nesting depth reads at a glance (section ▸ group fold ▸ cells). The fold's own
	# cells add a further step inside _make_fold.
	var body_wrap := MarginContainer.new()
	body_wrap.add_theme_constant_override("margin_left", int(FOLD_INDENT))
	body_wrap.add_child(body)
	section.add_child(body_wrap)

	if _hide_inert and _param_row_count == rows_before:
		_fold_bulk.resize(fold_bulk_before)
		section.free()   # orphan (never entered the tree) — drop it whole, header included
		return
	_groups_box.add_child(section)
	# ONE entry per section, carrying BOTH readers' vocabulary: `id`/`key` are the same fold
	# id, `summary` is its shut-form line, and `section` is the node an ancestor link scrolls
	# to. Two lists meant two copies of one title, and a live retitle updated only one.
	_section_folds.append({"id": section_id, "key": section_id, "title": title,
		"summary": summary, "header": header, "body": body, "section": section})
	if section_id != "":
		_section_by_key[section_id] = section


## THE COLOUR RIBBON, TRACK AND PICKER LEFT THIS COLUMN (ADR-0089 colour-move amendment,
## 2026-08-20). They are the player column's now — ONE editable ribbon on the particle-LIFE
## axis, hosted by its keyframe track, with the film strip beside it as a second entry point
## and the picker as a third stacked panel. `EffectStudioPage._build_sequence_canvas_overlay`
## builds them; `_bind_colour_track` fills them. The inspector-BUILDS / page-FILLS split
## survived the move intact; only the column changed.
##
## Measured on the "Particle · over-life" section before the move: a 668 x 610 body, of which
## the track and picker were 477px — 78% of the section and 21% of the whole 2108px inspector
## scroll, spent on every colour-enabled emitter permanently.
##
## WHAT STAYS IS THE THREE `Color (R/G/B) · curve` ROWS, and they stay for a reason rather
## than by omission. The row is the freehand curve painter's door (click its sparkline) and
## the shape picker's home (`curve_pick`) — and the painter is not a colour tool. It serves
## ~18 emitter params plus the ADR-0093 pacing curves, of which colour is three, so moving
## the rows would have meant building a second door in the player column for a panel that was
## never about colour. `refresh_colour_channels` keeps re-feeding those rows after a recolour
## un-aliases r=g=b onto fresh private curves (editing-UX amendment dec. 5); that seam is
## untouched by the move because it never went through the ribbon.
##
## The `ribbon` payload `EffectScoreModel` still emits is the PAGE's input now, read off the
## section it is attached to. Nothing here consumes it.


## The velocity-family formula block (ADR-0089 velocity amendment): three lines under
## the Dead reveal — the active formula with each annihilating factor accented + an `✕`
## glyph, the consequence (Dead field labels + human reason), and an imperative `→ fix`.
## Flag LABELS, never mode-name jargon (the descriptor already carries them).
func _add_velocity_formula(parent: VBoxContainer, formula: Dictionary) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)

	# Formula line — each marked factor is a zero factor: accent it and mark it `(0 ✕)`.
	var marked: Array = formula.get("marked_factors", [])
	var marked_line := str(formula.get("formula", ""))
	for factor in marked:
		marked_line = marked_line.replace(str(factor),
			"[color=#%s]%s(0 ✕)[/color]" % [COL_MARK.to_html(false), str(factor)])
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_OFF
	rt.add_theme_font_size_override("normal_font_size", 11)
	rt.text = "    " + marked_line
	box.add_child(rt)

	# Consequence: the Dead fields named by their labels + the human reason.
	var unused: Array = formula.get("unused_labels", [])
	var cons := Label.new()
	cons.text = "    ⇒ %s unused — %s" % [", ".join(unused), str(formula.get("reason", ""))]
	cons.modulate = COL_DIM
	cons.add_theme_font_size_override("font_size", 11)
	box.add_child(cons)

	# The imperative fix — the one knob to throw, accented like a gate marker.
	var fix := Label.new()
	fix.text = "    → %s" % str(formula.get("fix", ""))
	fix.add_theme_color_override("font_color", COL_MARK)
	fix.add_theme_font_size_override("font_size", 11)
	box.add_child(fix)

	parent.add_child(box)
	_velocity_formulas.append({"mode": str(formula.get("mode", "")),
		"fix": str(formula.get("fix", "")), "marked": marked, "node": box})


## The velocity-family formula views rendered this pass (ADR-0089 velocity amendment) —
## `{mode, fix, marked, node}`. Test seam for the one-per-Dead-reveal contract.
func velocity_formulas() -> Array:
	return _velocity_formulas


## A per-section "N hidden (not in effect)" reveal (ADR-0089 amendment): a dim
## toggle over an indented, collapsed-by-default body that gathers the section's
## Dead groups. Returns {header, body} so the caller hangs Dead folds under `body`
## and back-fills the count once the section is walked.
func _make_hidden_reveal(parent: VBoxContainer) -> Dictionary:
	var header := Button.new()
	header.toggle_mode = true
	header.button_pressed = false
	header.focus_mode = Control.FOCUS_NONE
	header.flat = true
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.modulate = COL_DIM
	header.text = "▸  hidden (not in effect)"
	header.tooltip_text = "Fields the simulation provably never reads at these values. Editing them does nothing until a gate is changed."
	parent.add_child(header)

	# The hidden Dead folds indent one step further under the reveal header, so the
	# extra nesting depth (section ▸ reveal ▸ dead fold) is legible when expanded.
	var reveal_wrap := MarginContainer.new()
	reveal_wrap.add_theme_constant_override("margin_left", int(FOLD_INDENT))
	var reveal_body := VBoxContainer.new()
	reveal_body.add_theme_constant_override("separation", 2)
	reveal_body.visible = false
	reveal_wrap.add_child(reveal_body)
	parent.add_child(reveal_wrap)

	header.toggled.connect(func(on: bool):
		reveal_body.visible = on
		header.text = "%s  %d hidden (not in effect)" % ["▾" if on else "▸",
			reveal_body.get_child_count()])
	return {"header": header, "body": reveal_body, "count": 0}


## One nested param-group fold (ADR-0089): a header toggle under the section, over
## an indented grid of the group's rows. Expansion seeds from the session fold
## state (fresh groups start collapsed) and every toggle writes it back, so
## re-selection / live-reproject rebuilds keep the author's folds.
func _make_fold(stamp: Dictionary, key: String, sub_cols: int, parent: VBoxContainer,
		curve_provider: Callable, on_open: Callable) -> GridContainer:
	var label := str(stamp.get("label", ""))
	var summary := str(stamp.get("summary", ""))
	# Folds default SHUT, but a stamp may ask for one to open — the exact peer of a
	# section's `collapsed` hint, and it exists for the same reason: a surface whose whole
	# point is the fold's CONTENT should not open showing only headers. The session state
	# still wins where the author has touched this fold, so the hint decides the first
	# render and never fights a later choice.
	var expanded: bool = bool(_fold_state.get(key, bool(stamp.get("expanded", false))))

	# Field-relevance salience (ADR-0089 amendment): an Inactive group (read but at
	# neutral) wears a `!` marker + why hover and dims — never hidden, so the author
	# can wake it. This SUPERSEDES the old ad-hoc "inert" dim (which conflated
	# Dead/Inactive and missed inertia's non-zero neutral). Dead groups never reach
	# here (they are diverted to the reveal); their end-axis-only cousins get a note.
	var rel: Dictionary = stamp.get("relevance", {})
	var state := str(rel.get("state", ""))
	var inactive := state == "inactive"
	var mark := MARK_INACTIVE if inactive else ""

	# Collapsed = [marker] label + the read-only summary (the scan surface,
	# decision 3); expanded = label only — the editing cells take over.
	var text_for := func(on: bool) -> String:
		if on or summary == "":
			return "%s %s%s" % ["▾" if on else "▸", mark, label]
		return "▸ %s%s    %s" % [mark, label, summary]

	var fold_header := Button.new()
	fold_header.toggle_mode = true
	fold_header.button_pressed = expanded
	fold_header.focus_mode = Control.FOCUS_NONE
	fold_header.flat = true
	fold_header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	fold_header.text = text_for.call(expanded)

	# Header tooltip: the full uncollapsed values, plus any salience why-strings.
	var tip := str(stamp.get("summary_tooltip", ""))
	if inactive:
		tip = "%s\n%s" % [str(rel.get("why", "")), tip]
		fold_header.modulate = COL_DIM
		_relevance_markers.append({"kind": "inactive", "why": str(rel.get("why", "")),
			"node": fold_header})
	elif bool(stamp.get("inert", false)):
		fold_header.modulate = COL_DIM   # no relevance verdict — legacy inert dim
	if bool(rel.get("end_dead", false)) and state != "dead":
		tip = "%s\n%s" % [tip, str(rel.get("end_why", ""))]
		_relevance_markers.append({"kind": "end_dead", "why": str(rel.get("end_why", "")),
			"node": fold_header})
	fold_header.tooltip_text = tip

	# Every live group carries a shape glyph on the collapsed header, beside its
	# summary (`Name  (0,4,0) → (0,0,0)  ▁▂▄█`): a curve-assigned group shows its
	# bright, clickable curve sparkline (used-window dimmed, decisions 3+5); a
	# no-curve group shows a dim, read-only LINEAR slope of its start→end
	# trajectory (#291 follow-on). An inert group (nothing happens) shows nothing.
	# Hidden while expanded — the editing cells take over.
	var spark = null
	if int(stamp.get("curve_index", -1)) >= 0:
		spark = _make_sparkline({"curve_index": stamp.get("curve_index", -1),
			"used_n": stamp.get("used_n", -1), "name": label}, true, curve_provider, on_open)
	elif not bool(stamp.get("inert", false)):
		var traj: Array = stamp.get("traj", [])
		if traj.size() == 2:
			spark = Sparkline.new()
			spark.set_linear(float(traj[0]), float(traj[1]))
	if spark != null:
		spark.visible = not expanded
		var head_row := HBoxContainer.new()
		head_row.add_theme_constant_override("separation", 6)
		head_row.add_child(fold_header)
		head_row.add_child(spark)
		parent.add_child(head_row)
	else:
		parent.add_child(fold_header)

	var grid := _param_grid(sub_cols)
	var body := MarginContainer.new()
	body.add_theme_constant_override("margin_left", int(FOLD_INDENT))
	body.add_child(grid)
	body.visible = expanded
	parent.add_child(body)

	fold_header.toggled.connect(func(on: bool):
		body.visible = on
		fold_header.text = text_for.call(on)
		if spark != null:
			spark.visible = not on
		_fold_state[key] = on)

	_folds.append({"key": key, "label": label, "header": fold_header, "body": body,
		"spark": spark})
	return grid


## A group grid with the fixed sub-column count — set once, never width-reflowed.
func _param_grid(sub_cols: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = sub_cols
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 3)
	_group_grids.append({"grid": grid, "sub_cols": sub_cols})
	return grid


## "Hide inert" predicate (ADR-0089 amendment): a verdict hides iff the mode is on AND its
## state is Inactive or Dead. A missing/empty verdict (plain Config rows, Live fields, header
## rows) is never hidden — that is why Live and un-stamped rows survive. A suppressing gate at
## its neutral self-classifies Inactive, so it hides here too (deliberate: toggle off to wake).
func _hidden(rel: Dictionary) -> bool:
	return _hide_inert and str(rel.get("state", "")) in ["inactive", "dead"]


## The session fold-state key for a group stamp ("" = not a parameter group).
func _fold_key(stamp: Dictionary) -> String:
	if stamp.is_empty():
		return ""
	return "%d:%s" % [int(stamp.get("emitter_index", -1)), str(stamp.get("id", ""))]


## An Expand all / Collapse all control button driving every param-fold key it was
## built over — pressing writes the session state and flips the live fold toggles.
func _bulk_fold_button(text: String, keys: Array, on: bool) -> Button:
	return _bulk_button(text, keys, on, _fold_state, _folds, "key")


## The SECTION-level Expand all / Collapse all, above the whole section list. Built
## for ANY target with more than one section — not just the sequence view: a fifteen-
## section emitter is exactly as tedious to shut by hand as a thirty-six-opcode
## sequence, and the control is the same act one level up.
##
## Only sections that carry a `fold_id` are remembered across the rebuild; an id-less
## section still toggles here and now, it just re-reads its projector's hint next time.
func _add_section_bulk_row() -> void:
	_section_bulk = {}
	if _groups_box == null or _section_folds.size() <= 1:
		return
	var ids: Array = []
	for entry in _section_folds:
		ids.append(str(entry["id"]))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var lbl := Label.new()
	lbl.text = "%d sections" % _section_folds.size()
	lbl.modulate = COL_DIM
	lbl.add_theme_font_size_override("font_size", 10)
	row.add_child(lbl)
	var expand_btn := _bulk_button("Expand all", ids, true, _section_state, _section_folds, "id")
	var collapse_btn := _bulk_button("Collapse all", ids, false, _section_state, _section_folds, "id")
	row.add_child(expand_btn)
	row.add_child(collapse_btn)
	_groups_box.add_child(row)
	# Built last (the sections have to exist to be counted) but shown FIRST — the
	# control belongs above the list it drives.
	_groups_box.move_child(row, 0)
	_section_bulk = {"expand": expand_btn, "collapse": collapse_btn, "row": row}


## The shared body of both bulk controls: write `state[key] = on` for every key, then
## flip the live entries whose `key_field` is one of them. Two levels of accordion, one
## behaviour — a param-fold pair passes `_fold_state`/`_folds`, the section pair passes
## `_section_state`/`_section_folds`.
func _bulk_button(text: String, keys: Array, on: bool, state: Dictionary,
		entries: Array, key_field: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.flat = true
	b.add_theme_font_size_override("font_size", 10)
	b.add_theme_color_override("font_color", COL_LABEL)
	b.pressed.connect(func():
		for key in keys:
			if str(key) != "":
				state[key] = on
		for entry in entries:
			if str(entry[key_field]) in keys:
				entry["header"].button_pressed = on)
	return b


## "const" (Config values / clickable links), "curve" (over-life, curve-only), or
## "shaped" (from→to). A `link` field (ADR-0073) shares the const 2-column layout —
## name │ value/button — so a mixed link+const section (Event, Config) stays aligned.
func _group_kind(group: Dictionary) -> String:
	for p in group.get("fields", []):
		var shape: String = p.get("shape", "")
		if shape == "const" or shape == "link" or shape == "edit" or shape == "action" \
				or shape == "nav_choice":
			return "const"
	for p in group.get("fields", []):
		if p.get("shape", "") != "curve_only":
			return "shaped"
	return "curve"


## Append one param's cells into the group grid — exactly `sub_cols` cells so every
## row stays column-aligned. The curve-presence bit greys the `to`/→/sparkline in
## place (disable, never hide — CONTEXT "Pinned / disabled row").
func _add_param_cells(body: GridContainer, kind: String, param: Dictionary, curve_provider: Callable, on_open: Callable) -> void:
	var enabled: bool = param.get("enabled", false)
	# A field may carry a `tooltip` (ADR-0071 legibility): applied to BOTH the label and the
	# value/edit widget so hovering either explains the cell. Projector-declared, generic.
	var tip: String = str(param.get("tooltip", ""))
	var name_cell := _cell(param.get("name", ""), COL_LABEL)
	name_cell.custom_minimum_size.x = name_column_width
	name_cell.clip_text = true
	_apply_tooltip(name_cell, tip)
	_apply_row_relevance(name_cell, param)
	body.add_child(name_cell)

	if kind == "const":
		var shape: String = param.get("shape", "")
		if shape == "link":
			# A clickable reference (ADR-0073): the value cell follows to another target.
			var link_btn := _link_button({"label": param.get("label", ""), "target": param.get("target", {})})
			_apply_tooltip(link_btn, tip)
			if param.has("toggle"):
				# ADR-0075: a live child-spawn edge — a checkbox suppresses this parent's
				# spawn of the child. Wrapped WITH the link in one HBox so the value cell
				# stays a single grid column (the const 2-col layout is preserved).
				body.add_child(_suppress_cell(param["toggle"], link_btn))
			else:
				body.add_child(link_btn)
		elif shape == "edit":
			# An editable authoring cell (#255): the value cell is a live widget that
			# lowers raw-byte edits through the mutate callback → the choke point. A
			# `preview_action`-carrying cell (#289: hear a Sound slot alone) gets a small
			# ▶ button beside the editor, wrapped in one HBox so the grid keeps 2 columns.
			var edit_w := _edit_cell(param, curve_provider, on_open)
			_apply_tooltip(edit_w, tip)
			if param.has("preview_action"):
				body.add_child(_preview_wrap(edit_w, param))
			elif param.has("follow"):
				body.add_child(_follow_wrap(edit_w, param))
			else:
				body.add_child(edit_w)
		elif shape == "action":
			# A do-something button (e.g. "Audition sequence"): pressing it fires the host's
			# action callback with the field's `action` dict. Value cell stays one column.
			var act_btn := _action_button(param)
			_apply_tooltip(act_btn, tip)
			body.add_child(act_btn)
		elif shape == "nav_choice":
			# A NAVIGATING dropdown (ADR-0073 dec. 3): several `link`s
			# collapsed into one cell. Picking an item moves the nav stack; nothing here
			# writes a byte, so it stays clear of the edit choke point entirely.
			var nav_w := _nav_choice_cell(param)
			_apply_tooltip(nav_w, tip)
			body.add_child(nav_w)
		else:
			var val_cell := _cell(str(param.get("value", "")), COL_VALUE)
			_apply_tooltip(val_cell, tip)
			body.add_child(val_cell)
		return

	if kind == "shaped":
		body.add_child(_cell(str(param.get("from", "")), COL_VALUE))
		body.add_child(_cell("→", COL_LABEL if enabled else COL_DIM))
		body.add_child(_cell(str(param.get("to", "")), COL_VALUE if enabled else COL_DIM))

	body.add_child(_make_sparkline(param, enabled, curve_provider, on_open))


## Field-relevance salience (ADR-0089 amendment) on a lone row (Config gate/gated
## field, over-life curve): a Dead row wears a `!` marker + why hover and dims; a
## GATE row that is currently suppressing something wears its own `!` whose hover
## says WHAT it suppresses (the bidirectional marker — navigable from the switch).
func _apply_row_relevance(name_cell: Label, param: Dictionary) -> void:
	var rel: Dictionary = param.get("relevance", {})
	if rel.is_empty():
		return
	if str(rel.get("state", "")) == "dead":
		name_cell.text = "%s%s" % [MARK_INACTIVE, name_cell.text]
		name_cell.modulate = COL_DIM
		name_cell.tooltip_text = str(rel.get("why", ""))
		_relevance_markers.append({"kind": "dead", "why": str(rel.get("why", "")), "node": name_cell})
	var gates: Array = rel.get("gates", [])
	if not gates.is_empty():
		var targets: Array = []
		for e in gates:
			targets.append(str(e.get("target", "")))
		name_cell.text = "%s%s" % [MARK_GATE, name_cell.text]
		name_cell.tooltip_text = "Suppressing: %s" % ", ".join(targets)
		_relevance_markers.append({"kind": "gate", "why": name_cell.tooltip_text, "node": name_cell})


## A NAVIGATING dropdown (`nav_choice`) — the chain's deepest slot as a choice among its
## siblings (ADR-0085 amendment 2026-08-21, decision 3). Each item carries an inspection
## `target`; picking one calls the navigate callback, exactly as a `link` cell does. It is
## NOT an `enum` editor: there is no `field_ref`, nothing reaches `_on_mutate`, and the
## author is choosing WHICH object to look at rather than changing one.
func _nav_choice_cell(param: Dictionary) -> Control:
	var ob := OptionButton.new()
	ob.custom_minimum_size.x = ENUM_CELL_WIDTH * 1.6
	ob.clip_text = true
	var targets: Array = []
	var choices: Array = param.get("choices", [])
	for i in range(choices.size()):
		var c: Dictionary = choices[i]
		ob.add_item(str(c.get("label", "")), i)
		targets.append(c.get("target", {}))
		if bool(c.get("selected", false)):
			ob.select(i)
	ob.item_selected.connect(func(i: int):
		if i >= 0 and i < targets.size():
			_on_navigate.call(targets[i]))
	_nav_choice_widgets.append(ob)
	return ob


## An editable authoring cell (#255 + the F1 #264 shared kit). Screen-specific editors:
## `target_color` (WYSIWYG backdrop pick, host back-solves the signed Blend param — see
## _target_color_cell), `gradient_color` (absolute stop pick), `choice` (index-carrying Kind
## selector). Shared kit primitives every subsystem reuses: `int` (type-ranged SpinBox),
## `enum` (value-carrying dropdown), `radio` (value-carrying visible option list),
## `bitflags` (checkbox group), `curve` (sparkline → painter).
## Anything unknown falls back to a plain read-only value cell.
func _edit_cell(param: Dictionary, curve_provider: Callable = func(_i): return [], on_open: Callable = func(_ci, _n): pass) -> Control:
	match param.get("editor", ""):
		"target_color": return _target_color_cell(param)
		"gradient_color": return _gradient_color_cell(param)
		"signed_rgb": return _signed_rgb_cell(param)
		"choice": return _choice_cell(param)
		"int": return _int_cell(param)
		"float": return _float_cell(param)
		"enum": return _enum_cell(param)
		"radio": return _radio_cell(param)
		"curve_pick": return _curve_pick_cell(param, curve_provider)
		"bitflags": return _bitflags_cell(param)
		"cells": return _cells_strip(param, curve_provider, on_open)
		"curve": return _make_sparkline(param, int(param.get("curve_index", -1)) >= 0,
			curve_provider, on_open)
		_: return _cell(str(param.get("value", "")), COL_VALUE)


## A `choice` editor (CONTEXT §Variant): an OptionButton seeded to the current index; on
## selection it fans the chosen index to the mutate callback with the cell's field_ref. Used
## for the screen tween KIND selector (Blend/Gradient) — a STRUCTURAL edit that reshapes the
## fields, so the host re-projects after applying it. Exposed via choice_widgets() (a test seam
## distinct from pick_widgets(), the target-colour picker).
func _choice_cell(param: Dictionary) -> Control:
	var ob := OptionButton.new()
	var choices: Array = param.get("choices", [])
	for i in range(choices.size()):
		ob.add_item(str(choices[i]), i)
	ob.selected = int(param.get("value", 0))
	var ref: Dictionary = param.get("field_ref", {})
	ob.item_selected.connect(func(idx: int): _on_mutate.call(ref, idx))
	_choice_widgets.append(ob)
	return ob


## F1 shared kit — an `int` SpinBox with a type-derived range (u8/s8/u16/s16/u32/s32). An
## explicit `min`/`max` overrides the range (e.g. a 0–10 mode code); a `bias` handles bipolar
## storage (the screen signed-byte lesson): the box shows the SIGNED display value and the fanned
## raw re-adds the bias (raw = display + bias). Seeding uses set_value_no_signal (range clamps may
## fire value_changed) and the mutate connect is made AFTER, so seeding fans NO spurious edit.
##
## A `unit` descriptor (CameraUnits — camera authoring in degrees/tiles/×) adds a SCALE term to
## that same affine: the box shows the HUMAN value (raw / scale) with a fractional step and a unit
## suffix, and the fanned value is converted back to RAW (round(display · scale)) — so the choke
## point, the byte writer, and the runtime never see anything but raw. The scale path is symmetric
## with the bias-only path (both seed display, fan raw); a cell with no `unit` is byte-identical
## to before.
## A `float` editor: a ScrubField that fans a FLOAT, not a rounded byte.
##
## Every other numeric cell in this kit lowers to a raw integer, because every other field
## in the studio IS one. The frame quad's transform terms are not — `scale` is a ratio,
## `rotation` is an angle, `shear` is a lean — and they are DERIVED from the eight stored
## integers rather than stored themselves (`FrameQuadTransform`). Rounding them at the cell
## would round them before the recomposition that turns them back into corners, which is
## exactly the drift that file keeps its precision to avoid: 8.89% of corpus quads sit at
## an arbitrary angle, and on a 179-unit quad a whole-degree rounding moves a corner.
##
## `decimals` is display only; the fanned value is the box's full float. Seeded with
## `set_value_no_signal` and connected AFTER, so seeding fans no spurious edit — the same
## contract `_int_cell` documents above.
func _float_cell(param: Dictionary) -> Control:
	var ref: Dictionary = param.get("field_ref", {})
	var sb := ScrubField.new()
	sb.custom_minimum_size.x = INT_CELL_WIDTH
	sb.prefix = str(param.get("prefix", ""))
	sb.suffix = str(param.get("suffix", ""))
	sb.step = float(param.get("step", 0.01))
	sb.min_value = float(param.get("min", -100000.0))
	sb.max_value = float(param.get("max", 100000.0))
	# ScrubField derives its displayed decimals FROM `step`, so a 0.01 step shows 1.12 for
	# an underlying 1.118 — display only. The transform keeps the exact value and
	# `with_term` replaces just the one the author typed, so the rounding the author sees
	# never reaches the corners of the terms they did not touch.
	sb.scrub_sensitivity = float(param.get("scrub", 0.0))
	sb.set_value_no_signal(float(param.get("value", 0.0)))
	sb.value_changed.connect(func(v: float): _on_mutate.call(ref, v))
	_int_widgets.append(sb)
	return sb


func _int_cell(param: Dictionary) -> Control:
	var ref: Dictionary = param.get("field_ref", {})
	var sb := ScrubField.new()
	sb.custom_minimum_size.x = INT_CELL_WIDTH
	# A pure display decoration (e.g. "±" on a symmetric shake amplitude) — never touches the
	# seeded value or the fanned raw. Applies to both the unit and raw paths below.
	sb.prefix = str(param.get("prefix", ""))

	if param.has("unit"):
		var unit: Dictionary = param["unit"]
		var rng: Array = _int_type_range(param.get("type", "s16"))
		# The chirality term (ADR-0089 amendment): a directional-Y cell flips sign
		# between raw storage and the game-up display, so the author sees the value
		# the sim caches and commits the opposite raw. Magnitude still routes through
		# the descriptor; this is the separate sign axis, never baked into the unit.
		var flip: int = -1 if param.get("flip_sign", false) else 1
		sb.step = pow(10.0, -int(unit.get("decimals", 1)))
		sb.scrub_sensitivity = float(unit.get("scrub", 0.0))
		sb.suffix = str(unit.get("suffix", ""))
		# Negating reverses the display order of the raw endpoints, so min/max is the
		# ordered pair of both converted ends (identical to before when flip == 1).
		var d_lo := CameraUnits.to_display(flip * int(param.get("min", rng[0])), unit)
		var d_hi := CameraUnits.to_display(flip * int(param.get("max", rng[1])), unit)
		sb.min_value = minf(d_lo, d_hi)
		sb.max_value = maxf(d_lo, d_hi)
		sb.set_value_no_signal(CameraUnits.to_display(flip * int(param.get("value", 0)), unit))

		# The honest quantization tell: 4096/360 (and ~28/tile) aren't integer-per-human-unit,
		# so a typed value may round to a raw the author didn't ask for. Show the ACHIEVED value
		# beside the box whenever the round-trip changes it (silent when faithful — angles at
		# 0.1° always are, tiles/zoom sometimes aren't). Never rounds silently.
		var hint := Label.new()
		hint.modulate = COL_DIM
		hint.add_theme_font_size_override("font_size", 10)
		var decimals: int = int(unit.get("decimals", 1))
		var refresh := func(display: float):
			var q: Dictionary = CameraUnits.quantize(display, unit)
			hint.text = "" if q["ok"] else "≈ %s%s" % [
				String.num(q["achieved_display"], decimals).pad_decimals(decimals), sb.suffix]
		refresh.call(sb.value)  # seed silent (a seeded raw always round-trips faithfully)

		sb.value_changed.connect(func(v: float):
			_on_mutate.call(ref, flip * CameraUnits.to_raw(v, unit))
			refresh.call(v))

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(sb)
		row.add_child(hint)
		_int_widgets.append(sb)
		_unit_hints.append(hint)
		return row

	var signed := str(param.get("type", "")) == "s8"
	var bias: int = int(param.get("bias", 0))
	var rng2: Array = _int_type_range(param.get("type", "u8"))
	sb.step = 1.0
	sb.min_value = int(param.get("min", rng2[0] - bias))
	sb.max_value = int(param.get("max", rng2[1] - bias))
	# A signed byte (ADR-0085 §2) is a DISPLAY-only transform: sign-extend the seed
	# (254 → −2) and MASK the fanned write (−100 → 156) so SoundDefChannel's 0-255
	# "byte" contract is unchanged. Signedness and bias are mutually exclusive (a
	# signed byte carries no bias); two's-complement is piecewise, not a linear bias.
	if signed:
		sb.set_value_no_signal(_sb_byte(int(param.get("value", 0))))
	else:
		sb.set_value_no_signal(int(param.get("value", 0)) - bias)

	# The empirical usage range (ADR-0085 §4): a dim inline hint of what shipped effects
	# do with this byte + an out-of-corpus TELL when the DISPLAYED value leaves that
	# envelope. Compared in the same (signed) space the box shows; refreshed live. When
	# an instrument is active (ADR-0085 2026-08-12) a SECOND, instrument-conditional line
	# rides beside it, with n-adaptive wording and a gated, distinct milder tell.
	var refresh_range: Callable = func(_v: float): pass
	var range_hint: Label = null
	var range_inst_hint: Label = null
	if param.has("range"):
		var rd: Dictionary = param["range"]
		var rmin: int = int(rd.get("min", 0))
		var rmax: int = int(rd.get("max", 0))
		var rmed: int = int(rd.get("median", 0))
		var rn: int = int(rd.get("n", 0))
		range_hint = Label.new()
		range_hint.add_theme_font_size_override("font_size", 10)
		# The instrument line's static facts (resolved once; the tell recomputes live).
		var has_inst: bool = param.has("range_instrument")
		var ird: Dictionary = param.get("range_instrument", {})
		var iname: String = str(ird.get("name", ""))
		var iempty: bool = bool(ird.get("empty", false))
		var imin: int = int(ird.get("min", 0))
		var imax: int = int(ird.get("max", 0))
		var imed: int = int(ird.get("median", 0))
		var in_: int = int(ird.get("n", 0))
		# The instrument line's steady (non-tell) wording, n-adaptive: n=1 is "seen once
		# at X" (never a dressed-up range); the empty bucket is the honest "none with X".
		var inst_base := ""
		if has_inst:
			if iempty:
				inst_base = "none with %s" % iname
			elif in_ == 1:
				inst_base = "with %s: seen once at %d" % [iname, imed]
			else:
				inst_base = "with %s: %d…%d · median %d · n=%d" % [iname, imin, imax, imed, in_]
			range_inst_hint = Label.new()
			range_inst_hint.add_theme_font_size_override("font_size", 10)
		# The global line is relabeled "(all)" ONLY when an instrument line joins it, so the
		# two are distinguishable; alone it keeps the original "typical …" wording.
		var lead := "typical (all): " if has_inst else "typical "
		refresh_range = func(display: float):
			var shown := int(round(display))
			var outside_global := shown < rmin or shown > rmax
			if outside_global:
				range_hint.text = "⚠ outside corpus · %s%d…%d" % [lead, rmin, rmax]
				range_hint.modulate = COL_WARN
			else:
				range_hint.text = "%s%d…%d · median %d · n=%d" % [lead, rmin, rmax, rmed, rn]
				range_hint.modulate = COL_DIM
			if range_inst_hint == null:
				return
			# The instrument tell fires ONLY on a confident bucket (n≥8) and ONLY when the
			# stronger outside-global signal has NOT already fired (precedence). It reads
			# "unusual for X" — honest that the value IS precedented elsewhere, unlike the
			# loud "outside corpus". The empty bucket and small buckets never blare.
			var outside_inst := (not iempty) and (shown < imin or shown > imax)
			if outside_inst and in_ >= 8 and not outside_global:
				range_inst_hint.text = "⚠ unusual for %s · uses %d…%d" % [iname, imin, imax]
				range_inst_hint.modulate = COL_WARN_MILD
			else:
				range_inst_hint.text = inst_base
				range_inst_hint.modulate = COL_DIM
		refresh_range.call(sb.value)   # seed silent
		_range_hints.append(range_hint)
		if range_inst_hint != null:
			_range_instrument_hints.append(range_inst_hint)

	sb.value_changed.connect(func(v: float):
		_on_mutate.call(ref, (int(round(v)) & 0xFF) if signed else int(round(v)) + bias)
		refresh_range.call(v))
	_int_widgets.append(sb)
	if range_hint != null:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(sb)
		# Stack the two range lines vertically so the second (instrument) line sits under
		# the first without stretching the row.
		if range_inst_hint != null:
			var lines := VBoxContainer.new()
			lines.add_theme_constant_override("separation", 0)
			lines.add_child(range_hint)
			lines.add_child(range_inst_hint)
			row.add_child(lines)
		else:
			row.add_child(range_hint)
		return row
	return sb


## [min, max] for an integer storage type, in RAW (unbiased) space.
func _int_type_range(t: String) -> Array:
	match t:
		"s8": return [-128, 127]
		"u16": return [0, 65535]
		"s16": return [-32768, 32767]
		"u32": return [0, 4294967295]
		"s32": return [-2147483648, 2147483647]
		_: return [0, 255]  # u8 default


## F1 shared kit — a value-carrying `enum` OptionButton. Distinct from `choice` (which fans the
## selected INDEX, index-aligned to an enum): each item's id IS its VALUE, so a field whose codes
## aren't 0..N-1 fans the real code. Seeded to the item whose value matches the current raw;
## `.selected =` fires no item_selected, so seeding fans no edit.
func _enum_cell(param: Dictionary) -> Control:
	var ob := OptionButton.new()
	ob.custom_minimum_size.x = ENUM_CELL_WIDTH
	ob.clip_text = true
	var choices: Array = param.get("choices", [])
	var cur: int = int(param.get("value", 0))
	var sel_idx: int = 0
	for i in range(choices.size()):
		var val: int = int(choices[i].get("value", i))
		ob.add_item(str(choices[i].get("label", str(val))), val)  # item id == value
		if val == cur:
			sel_idx = i
	ob.selected = sel_idx
	var ref: Dictionary = param.get("field_ref", {})
	ob.item_selected.connect(func(idx: int): _on_mutate.call(ref, ob.get_item_id(idx)))
	_enum_widgets.append(ob)

	# An optional per-value detail read-out (ADR-0085 instrument-chip loop verdict): a
	# dim Label under the dropdown showing value_detail.call(selected), refreshed on
	# selection. Absent → the bare OptionButton, exactly as before.
	var detail: Variant = param.get("value_detail")
	if not (detail is Callable):
		return ob
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.add_child(ob)
	var hint := Label.new()
	hint.modulate = COL_DIM
	hint.add_theme_font_size_override("font_size", 10)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = str((detail as Callable).call(cur))
	box.add_child(hint)
	ob.item_selected.connect(func(idx: int): hint.text = str((detail as Callable).call(ob.get_item_id(idx))))
	_enum_detail_hints.append(hint)
	return box


## A value-carrying `radio` list (#289): every choice visible at once as one ButtonGroup
## of CheckBoxes — for a small fixed option space whose SEMANTICS are the point (the
## SoundContainer Pick modes), where a dropdown would hide all but the current pick. A
## choice may carry a dim `detail` read-out beside its label (e.g. the sequence that mode
## would play). Seeded with set_pressed_no_signal so building fans no edit; selecting a
## row fans its VALUE through the mutate callback, exactly like `enum`.
func _radio_cell(param: Dictionary) -> Control:
	var ref: Dictionary = param.get("field_ref", {})
	var cur: int = int(param.get("value", 0))
	# A 2-column grid — [radio+label | detail] — so the detail read-outs (the step
	# patterns) line up in ONE column regardless of each label's width.
	var box := GridContainer.new()
	box.columns = 2
	box.add_theme_constant_override("v_separation", 2)
	box.add_theme_constant_override("h_separation", 12)
	var bg := ButtonGroup.new()
	var group: Array = []
	for choice in param.get("choices", []):
		var val: int = int(choice.get("value", 0))
		var cb := CheckBox.new()
		cb.text = str(choice.get("label", str(val)))
		cb.button_group = bg
		cb.focus_mode = Control.FOCUS_NONE
		cb.set_pressed_no_signal(val == cur)
		cb.toggled.connect(func(on: bool):
			if on:
				_on_mutate.call(ref, val))
		box.add_child(cb)
		var d := Label.new()
		d.text = str(choice.get("detail", ""))
		d.modulate = COL_VALUE if val == cur else COL_DIM
		d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(d)
		group.append(cb)
	_radio_groups.append(group)
	return box


## Wrap an editable cell with its ▶ `preview_action` button (#289: hear one Sound slot
## alone) in one HBox, so the pair occupies a single grid column. The button rides the
## generic action seam (registered in _action_buttons like any action Button).
func _preview_wrap(edit_w: Control, param: Dictionary) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	# A common minimum editor width so the ▶ buttons line up in one column across the
	# Sound 1/2/3 rows (each OptionButton would otherwise size to its own text).
	edit_w.custom_minimum_size.x = maxf(edit_w.custom_minimum_size.x, 200.0)
	hb.add_child(edit_w)
	var b := Button.new()
	b.text = "▶"
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "Play this sound once."
	var action: Dictionary = param.get("preview_action", {})
	b.pressed.connect(func(): _on_action.call(action))
	_action_buttons.append(b)
	hb.add_child(b)
	return hb


## Wrap an editable cell with its FOLLOW button (ADR-0073 dec. 7) in one
## HBox, so the pair still occupies a single grid column — the same shape `_preview_wrap`
## uses for the ▶ Sound button.
##
## This is the answer to "drill down and edit want the same row": a `link` field and an
## `edit` field are different shapes, and the reference fields the drill-down chain needs
## (an emitter's Animation set, a FRAME opcode's Frameset) are EDITABLE authoring cells
## that ADR-0089 tier-1 put there on purpose. The editor is untouched and gains a
## following affordance beside it, rather than being regressed to a link.
##
## A DISABLED follow (the reference points nowhere — anim_index/frameset are u8s with no
## validity guarantee) renders NO button at all, and the projector pairs it with the
## ADR-0089 `relevance` dead marker on the row's label so the row still says WHY. An inert
## button that navigates to an empty inspector would read as broken.
##
## The button registers on `_link_buttons`, not `_action_buttons`: it IS a link — same
## navigate callback, same target — so every test seam and every behaviour that already
## enumerates links picks it up without knowing this shape exists.
func _follow_wrap(edit_w: Control, param: Dictionary) -> Control:
	var follow: Dictionary = param.get("follow", {})
	if bool(follow.get("disabled", false)):
		return edit_w
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	# The editor and the button share ONE grid column, so the button's label eats into the
	# editor's width. A floor keeps the spinbox usable on a narrow panel; deliberately low
	# (a u8 needs three digits) because raising it would push the pair past the column and
	# reflow the panel, which ADR-0089 decision 1 forbids.
	edit_w.custom_minimum_size.x = maxf(edit_w.custom_minimum_size.x, 90.0)
	hb.add_child(edit_w)
	var b := Button.new()
	b.text = "→ %s" % str(follow.get("label", ""))
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_color_override("font_color", COL_LINK)
	b.tooltip_text = str(follow.get("tooltip", ""))
	# The destination lives in a MUTABLE cell the lambda closes over, not captured by
	# value: a follow is derived from the editor sitting right beside it (a FRAME opcode's
	# Frameset row follows to `frameset + group offset`), so editing that value re-aims
	# this button. A captured target would keep navigating to the OLD object — the author
	# points the opcode at frameset 3 and the button beside it still opens frameset 1.
	# See `refresh_follows`, which rewrites this cell in place.
	var state: Dictionary = {"target": follow.get("target", {})}
	b.pressed.connect(func(): _on_navigate.call(state["target"]))
	_link_buttons.append(b)
	_follows.append({"ref": param.get("field_ref", {}), "button": b, "state": state})
	hb.add_child(b)
	return hb


## Re-aim the follow buttons IN PLACE from freshly projected `sections` — the label, the
## tooltip and the DESTINATION. Same contract and same reason as `refresh_section_titles`:
## a follow is derived from the value in the editor beside it, so it goes stale the moment
## that editor is used, and re-deriving the whole inspector to fix it would destroy the
## widget being dragged.
##
## Matched by `field_ref`, which addresses the stored parameter and is stable across the
## edit. A follow that has become disabled (the new value points off the end of the
## framesets array) is greyed and made inert rather than removed, because removing a
## widget is the rebuild this seam exists to avoid — the projector's own `disabled` shape
## renders no button at all, and the next full render will agree with it.
func refresh_follows(sections: Array) -> void:
	if _follows.is_empty():
		return
	var by_ref: Array = []
	for section in sections:
		for param in section.get("fields", []):
			if param is Dictionary and param.has("follow") and param.has("field_ref"):
				by_ref.append(param)
	for entry in _follows:
		for param in by_ref:
			if param["field_ref"] != entry["ref"]:
				continue
			var follow: Dictionary = param["follow"]
			var b: Button = entry["button"]
			if bool(follow.get("disabled", false)):
				b.disabled = true
				b.text = "→ —"
				b.tooltip_text = "This reference points off the end — fix the value beside it."
				entry["state"]["target"] = {}
			else:
				b.disabled = false
				b.text = "→ %s" % str(follow.get("label", ""))
				b.tooltip_text = str(follow.get("tooltip", ""))
				entry["state"]["target"] = follow.get("target", {})
			break


## The live follow buttons (`{ref, button, state}`) — the ADR-0100 refresh test seam.
func follow_buttons() -> Array:
	return _follows


## The curve-assignment thumbnail picker (`curve_pick`, ADR-0089 curve-UX amendment).
## The face shows the shape this use site draws; a popup grid browses WHOLE-curve
## thumbnails of the effect's distinct shapes.
##
## A pick fans the chosen shape's SAMPLES, not its ordinal, because the verb is COPY, not
## reference (curve-ownership amendment, decision 3): there is no shared slot to name, so
## the edit is "put these 160 values in this use site's own curve". `none` fans an empty
## array — the one choice that clears the address instead of writing samples.
##
## `curve_provider` is unused for choices that carry their own samples; it survives for
## callers still handing index-shaped choices.
func _curve_pick_cell(param: Dictionary, curve_provider: Callable) -> Control:
	var picker = CurvePicker.new()
	var ref: Dictionary = param.get("field_ref", {})
	var choices: Array = param.get("choices", [])
	picker.setup(choices, int(param.get("value", 0)), curve_provider)
	picker.picked.connect(func(v: int): _on_mutate.call(ref, _pick_payload(choices, v)))
	_curve_pick_widgets.append(picker)
	return picker


## The payload a pick lowers: the chosen shape's 0-255 samples, or an EMPTY array for
## `none`. A choice with no carried samples falls back to its raw value so a legacy
## index-shaped picker still fans what it always did.
func _pick_payload(choices: Array, value: int):
	if value <= 0:
		return []
	for c in choices:
		if int(c.get("value", 0)) == value:
			return Array(c["samples"]) if c.has("samples") else value
	return value


## F1 shared kit — a `bitflags` checkbox group over declared masks. Each toggle recomputes the
## WHOLE word from a running state (so successive toggles compound) and fans it through the choke
## point. Seeded with set_pressed_no_signal so no toggle fires on build. The group's CheckBoxes
## are exposed as one entry in bitflag_widgets() for tests.
## A `cells` strip (ADR-0089 two-axis emitter rows): several kit editors in ONE
## value column — min/max or X/Y/Z on an emitter axis row. Each sub-cell is a full
## `_edit_cell` param with its OWN field_ref (editing one fans only that cell's
## edit); an optional `label` renders as a dim prefix ("min", "X"), and a sub-cell
## `tooltip` (the raw RE name + byte offset) rides the widget.
func _cells_strip(param: Dictionary, curve_provider: Callable, on_open: Callable) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	for cell in param.get("cells", []):
		var lbl: String = str(cell.get("label", ""))
		if lbl != "":
			box.add_child(_cell(lbl, COL_DIM))
		var w := _edit_cell(cell, curve_provider, on_open)
		_apply_tooltip(w, str(cell.get("tooltip", "")))
		# A colour-curve cell (ADR-0089 editing-UX amendment) records its widget by channel so
		# a recolour can re-feed it in place: the `curve` cell's sparkline and the `curve_pick`.
		var chan: String = str(cell.get("colour_channel", ""))
		if chan != "":
			match str(cell.get("editor", "")):
				"curve": _colour_channel_sparklines[chan] = w
				"curve_pick": _colour_channel_pickers[chan] = w
		box.add_child(w)
	return box


func _bitflags_cell(param: Dictionary) -> Control:
	var ref: Dictionary = param.get("field_ref", {})
	var state := {"word": int(param.get("value", 0))}
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var group: Array = []
	for bit in param.get("bits", []):
		var mask: int = int(bit.get("mask", 0))
		var cb := CheckBox.new()
		cb.text = str(bit.get("label", ""))
		cb.focus_mode = Control.FOCUS_NONE
		cb.set_pressed_no_signal((int(state["word"]) & mask) != 0)
		cb.toggled.connect(func(on: bool):
			state["word"] = (int(state["word"]) | mask) if on else (int(state["word"]) & ~mask)
			_on_mutate.call(ref, int(state["word"])))
		box.add_child(cb)
		group.append(cb)
	_bitflag_groups.append(group)
	return box


## A WYSIWYG target-colour cell (#255): ONE ColorPickerButton (RGB only — the backdrop is
## opaque) SEEDED with the cell's `seed` colour (the live resulting top colour, injected by the
## page which owns the runtime), beside a read-only "actual result" swatch. On a colour change
## the picked colour + the tween's three per-component field_refs fan through the pick callback
## → the host, which back-solves the signed Blend param through the REAL forward blend fold and
## lowers the chosen bytes through the choke point. The host returns the ACHIEVED colour; when a
## target is unreachable (mode/range/clamp) it differs from the pick, so the actual swatch is the
## honest feedback (the live preview is the other). Seeding sets `.color` directly, which does
## NOT emit color_changed — no spurious pick.
func _target_color_cell(param: Dictionary) -> Control:
	var refs: Dictionary = param.get("field_refs", {})
	var seed: Color = param.get("seed", Color.BLACK)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var picker := ColorPickerButton.new()
	picker.edit_alpha = false
	picker.custom_minimum_size = Vector2(72, 0)
	picker.color = seed

	var actual := ColorRect.new()
	actual.custom_minimum_size = Vector2(24, 20)
	actual.color = seed
	actual.tooltip_text = "The colour the backdrop ACTUALLY reaches — differs from your pick when the target is unreachable (nearest match)."

	picker.color_changed.connect(func(col: Color):
		var achieved = _on_pick_target.call(refs, col)
		if achieved is Color:
			actual.color = achieved)

	row.add_child(picker)
	row.add_child(_cell("→", COL_DIM))
	row.add_child(actual)

	_pick_widgets.append(picker)
	_actual_swatch = actual
	return row


## A plain Gradient-stop colour cell (#255 scope B): ONE RGB ColorPickerButton seeded with the
## cell's `seed` colour (the stop's current absolute value, supplied by the projector — no host
## runtime needed). A Gradient stop is an UNSIGNED ABSOLUTE colour, so — unlike the Blend
## target_color cell — there is no solver: a colour change fans three DIRECT byte writes
## (round(c·255)) for the stop's r/g/b field_refs through the byte choke point (_on_mutate).
## Seeding sets `.color` directly, which does NOT emit color_changed — no spurious write.
func _gradient_color_cell(param: Dictionary) -> Control:
	var refs: Dictionary = param.get("field_refs", {})
	var seed: Color = param.get("seed", Color.BLACK)

	var picker := ColorPickerButton.new()
	picker.edit_alpha = false
	picker.custom_minimum_size = Vector2(72, 0)
	picker.color = seed

	picker.color_changed.connect(func(col: Color):
		_on_mutate.call(refs.get("r", {}), int(round(col.r * 255.0)))
		_on_mutate.call(refs.get("g", {}), int(round(col.g * 255.0)))
		_on_mutate.call(refs.get("b", {}), int(round(col.b * 255.0))))

	_gradient_pickers.append(picker)
	return picker


## The signed-Δ RGB row (ADR-0087) — the precise companion to the WYSIWYG picker. Three
## signed-byte SpinBoxes (−128..127) seeded to the SIGNED interpretation of the raw tint bytes
## (`seed` is the raw Vector3i), each fanning the RAW byte (display & 0xFF) to its r/g/b
## field_ref through the byte choke point — so the storage convention stays 0-255 and the fold's
## sign-extension is unchanged. A "No tint" button zeros all three: the explicit Δ = 0,0,0 no-op
## the mid-grey result-picker can never surface. Seeding uses set_value_no_signal → no spurious
## write.
func _signed_rgb_cell(param: Dictionary) -> Control:
	var refs: Dictionary = param.get("field_refs", {})
	var seed = param.get("seed", Vector3i.ZERO)
	var raw := [int(seed.x), int(seed.y), int(seed.z)]
	var keys := ["r", "g", "b"]
	var labels := ["R", "G", "B"]

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for i in range(3):
		var lab := Label.new()
		lab.text = labels[i]
		lab.modulate = COL_DIM
		row.add_child(lab)
		var sb := SpinBox.new()
		sb.min_value = -128
		sb.max_value = 127
		sb.step = 1.0
		sb.custom_minimum_size = Vector2(52, 0)
		sb.set_value_no_signal(_sb_byte(raw[i]))
		var ref: Dictionary = refs.get(keys[i], {})
		sb.value_changed.connect(func(v: float): _on_mutate.call(ref, int(round(v)) & 0xFF))
		row.add_child(sb)
		_signed_rgb_boxes.append(sb)

	var reset := Button.new()
	reset.text = "No tint"
	reset.focus_mode = Control.FOCUS_NONE
	reset.tooltip_text = "Set Δ = (0, 0, 0) — a true no-op (no colour change) in the additive modes."
	reset.pressed.connect(func():
		for k in keys:
			_on_mutate.call(refs.get(k, {}), 0))
	row.add_child(reset)
	_signed_rgb_reset = reset
	return row


## Sign-extend a raw 0-255 byte to its signed −128..127 value (the widget's display space).
func _sb_byte(b: int) -> int:
	b = b & 0xFF
	return b - 256 if b >= 128 else b


func _make_sparkline(param: Dictionary, enabled: bool, curve_provider: Callable, on_open: Callable) -> Control:
	var spark = Sparkline.new()
	var samples: Array = []
	var ci: int = int(param.get("curve_index", -1))
	if enabled and ci >= 0:
		var s = curve_provider.call(ci)
		if s is Array or s is PackedFloat32Array:
			samples = Array(s)
	var used_n := int(param.get("used_n", -1))
	spark.set_curve(samples, enabled, used_n)
	if enabled and ci >= 0:
		# The open seam carries used_n so the painter veils the SAME window the
		# sparkline trims (ADR-0089 curve-UX amendment). Arity-aware so legacy
		# 2-arg on_open callbacks (many tests, the _edit_cell default) still work.
		spark.pressed.connect(func():
			if on_open.get_argument_count() >= 3:
				on_open.call(ci, param.get("name", ""), used_n)
			else:
				on_open.call(ci, param.get("name", "")))
	_sparklines.append(spark)
	# Emitter-elapsed playhead marker (ADR-0089 amendment): a curve-assigned sparkline under
	# an emitter-clocked section carries the marker; age-clocked (over-life) sparklines opt out.
	if enabled and ci >= 0 and _cur_section_clock == "emitter":
		spark.set_marker(_marker)
		_marker_sparklines.append(spark)
	return spark


## The emitter-clocked sparklines the playhead marker rides — a test seam AND the cheap
## continuous-refresh set. Rebuilt each show_target.
func marker_sparklines() -> Array:
	return _marker_sparklines


## Refresh the emitter-elapsed playhead marker on the already-built sparklines WITHOUT a
## rebuild (ADR-0089 amendment — continuous cadence). The page calls this each transport tick
## / scrub so the marker sweeps across the curves over a looped region.
func update_marker(marker: Dictionary) -> void:
	_marker = marker
	for spark in _marker_sparklines:
		if is_instance_valid(spark):
			spark.set_marker(marker)


## Return to the empty state (no selection).
func clear() -> void:
	_clear_grid()
	_clear_groups()
	_link_buttons.clear()
	_action_buttons.clear()
	_child_toggles.clear()
	_row_count = 0
	if _title:
		_title.text = "Keyframe"
	if _grid:
		_grid.visible = false
	if _placeholder:
		_placeholder.visible = true
	_content_width = 0.0
	content_changed.emit()


## Header field rows shown (test seam).
func row_count() -> int:
	return _row_count


## Accordion sections currently shown (test seam). Counts the SECTIONS, not
## `_groups_box`'s children — the box also carries the section-level Expand all /
## Collapse all row, which is a control over the list rather than a member of it.
func group_count() -> int:
	return _section_folds.size()


## The live SECTION accordion entries in render order (test seam), carrying BOTH readers'
## vocabulary for one section: `id`/`key` are the same fold id, `summary` is its shut-form
## line and `section` the node an ancestor link scrolls to.
func section_folds() -> Array:
	return _section_folds


## The navigating dropdowns currently shown (test seam).
func nav_choice_widgets() -> Array:
	return _nav_choice_widgets


## Bring an ALREADY-RENDERED section into view (ADR-0073 dec. 11): what a
## chain's `link` cells degrade to, since the thing they point at is on this same page.
## A no-op for an unknown key, so a link into something genuinely absent still navigates.
func scroll_to_section(key: String) -> bool:
	if _scroll == null or not _section_by_key.has(key):
		return false
	var node: Control = _section_by_key[key]
	if not is_instance_valid(node):
		return false
	# Deferred: the section's position is only final after the container re-sorts, which a
	# just-rebuilt tree has not done yet.
	_scroll.set_deferred("scroll_vertical", int(node.position.y))
	return true


## Total param rows across all groups (test seam).
func param_row_count() -> int:
	return _param_row_count


## The live nested param-group folds — `{key, label, header (toggle Button),
## body (Control)}` per group, in render order (ADR-0089 test seam).
func param_folds() -> Array:
	return _folds


## The per-section Expand all / Collapse all Button pairs (`{expand, collapse}`),
## one entry per fold-carrying section (ADR-0089 test seam).
func fold_bulk_buttons() -> Array:
	return _fold_bulk


## Rewrite the section titles IN PLACE from `{fold_id: title}`, without rebuilding a
## single widget. A section title can carry live values — a sequence opcode's is its full
## instruction label, `"1: FRAME fs=3 dur=8 depth=1"` — so it goes stale the moment one of
## its own fields is edited, and re-deriving the inspector to fix that would destroy the
## ScrubField mid-drag (the reason the plain-value edit path deliberately does not render).
## Untouched: fold state, scroll position, focus, and any section not named in the map.
func refresh_section_titles(titles: Dictionary) -> void:
	for entry in _section_folds:
		var id := str(entry["id"])
		if id == "" or not titles.has(id):
			continue
		var title := str(titles[id])
		if title == str(entry["title"]):
			continue
		entry["title"] = title
		var header: Button = entry["header"]
		var shut_summary := str(entry.get("summary", ""))
		if header.button_pressed or shut_summary == "":
			header.text = "%s  %s" % ["▾" if header.button_pressed else "▸", title]
		else:
			header.text = "▸  %s    %s" % [title, shut_summary]


## Rewrite the header rows' VALUE cells in place, same contract and same reason as
## `refresh_section_titles` above — a sequence's "Plays for N ticks" is a sum over the
## opcode durations being edited below it.
##
## Refuses rather than guesses when the row list no longer matches what is rendered: the
## grid holds two cells per row in order, so a shape change means this is not the same
## header and writing into it would relabel the wrong cells.
func refresh_header_values(rows: Array) -> void:
	if _grid == null or _grid.get_child_count() != rows.size() * 2:
		return
	for i in range(rows.size()):
		var row = rows[i]
		if not (row is Dictionary) or not row.has("value"):
			continue   # a link row's cell is a Button, and its label is not a live value
		var cell = _grid.get_child(i * 2 + 1)
		if cell is Label:
			(cell as Label).text = str(row["value"])


## The section-level Expand all / Collapse all pair (`{expand, collapse, row}`), or an
## empty Dictionary when there are fewer than two sections (ADR-0100 test seam).
func section_bulk_buttons() -> Dictionary:
	return _section_bulk


## The live field-relevance `!` markers (`{kind, why, node}`) — the salience test
## seam (ADR-0089 amendment). kind ∈ "inactive"/"dead"/"gate".
func relevance_markers() -> Array:
	return _relevance_markers


## The per-section "N hidden (not in effect)" reveal folds gathering Dead groups
## (`{header, body, count}`), collapsed by default (ADR-0089 amendment test seam).
func hidden_reveals() -> Array:
	return _hidden_reveals


## Every live group grid's actual vs intrinsic column count (`{columns, sub_cols}`)
## — the single-column guard seam (ADR-0089 decision 1: these never diverge).
func group_grid_columns() -> Array:
	var out: Array = []
	for entry in _group_grids:
		if is_instance_valid(entry["grid"]):
			out.append({"columns": int(entry["grid"].columns), "sub_cols": int(entry["sub_cols"])})
	return out


## The live sparkline Controls, for tests to drive the open-curve seam.
func sparklines() -> Array:
	return _sparklines


## The three `Color (R/G/B) · curve` sparklines keyed by channel (ADR-0089 editing-UX
## amendment) — the "curves on the left" a recolour must keep live. Test seam.
func colour_channel_sparklines() -> Dictionary:
	return _colour_channel_sparklines


## The three colour-channel curve_pick widgets keyed by channel. Test seam.
func colour_channel_pickers() -> Dictionary:
	return _colour_channel_pickers


## Re-feed the colour-channel sparklines + pickers after a recolour forks the emitter's colour
## curves onto fresh indices (ADR-0089 editing-UX amendment — the stale-sparkline bug). `indices`
## maps channel → the forked curve INDEX; `provider` maps a curve index to its live samples. Each
## sparkline keeps its used window; each picker moves onto the forked nibble (index + 1) WITHOUT
## fanning a pick. A light in-place refresh — no reproject, so a live picker drag survives.
func refresh_colour_channels(indices: Dictionary, provider: Callable) -> void:
	for chan in indices:
		var idx := int(indices[chan])
		var samples: Array = Array(provider.call(idx))
		if _colour_channel_sparklines.has(chan):
			var spark = _colour_channel_sparklines[chan]
			if is_instance_valid(spark):
				spark.set_curve(samples, true, spark.used_window())
		if _colour_channel_pickers.has(chan):
			var picker = _colour_channel_pickers[chan]
			if is_instance_valid(picker):
				# The face is re-fed the SAMPLES, not an index. A recolour rewrites this
				# channel's private curve into a shape that is usually in no other use site,
				# so it is not in the grid the picker was built from — and since ADR-0089's
				# curve-ownership amendment there is no shared index to name it by anyway.
				picker.show_shape(samples)


## The live link Buttons (header breadcrumb/provenance + `link` fields), for tests to
## drive the navigate seam (ADR-0073).
func link_buttons() -> Array:
	return _link_buttons


## The live child-spawn suppression CheckBoxes (ADR-0075), for tests to drive the toggle.
func child_toggles() -> Array:
	return _child_toggles


## The live target-colour pickers (ColorPickerButtons, #255), for tests to drive the pick path.
func pick_widgets() -> Array:
	return _pick_widgets


## The live Gradient-stop pickers (ColorPickerButtons, #255 scope B), for tests to drive the
## direct-byte-write path — distinct from pick_widgets() (the signed Blend target solver).
func gradient_pickers() -> Array:
	return _gradient_pickers


## The read-only "actual result" swatch beside the picker (repainted to the achieved colour),
## for tests to assert the honest unreachable-target feedback.
func actual_swatch() -> ColorRect:
	return _actual_swatch


## The live choice-editor widgets (OptionButtons, e.g. the Kind selector), for tests to drive
## the structural-variant mutate path.
func choice_widgets() -> Array:
	return _choice_widgets


## The live F1-kit `int` SpinBoxes, for tests to drive the spinbox mutate path.
func int_widgets() -> Array:
	return _int_widgets


## The live `action` Buttons (e.g. "Audition sequence"), for tests to drive the action seam.
func action_buttons() -> Array:
	return _action_buttons


## The live F1-kit `enum` OptionButtons (value-carrying, distinct from choice_widgets()).
func enum_widgets() -> Array:
	return _enum_widgets


## The dim per-value detail Labels beside value_detail-carrying `enum` cells (ADR-0085
## instrument-chip loop verdict) — a test/inspection seam, one per such cell.
func enum_detail_hints() -> Array:
	return _enum_detail_hints


## The live F1-kit `bitflags` groups — each entry is that group's Array of CheckBoxes.
func bitflag_widgets() -> Array:
	return _bitflag_groups


## The live `radio` groups — each entry is that field's Array of CheckBoxes (one
## ButtonGroup, choice order), for tests to drive the radio mutate path.
func radio_groups() -> Array:
	return _radio_groups


## The live curve-assignment thumbnail pickers (`curve_pick`), for tests to drive the
## pick → same-field_ref mutate path (ADR-0089 curve-UX amendment).
func curve_pick_widgets() -> Array:
	return _curve_pick_widgets


## The live signed-Δ RGB SpinBoxes (R/G/B), for tests to drive the raw-byte fan (ADR-0087).
func signed_rgb_widgets() -> Array:
	return _signed_rgb_boxes


## The "No tint" reset button on the signed-Δ row (zeros all three channels → Δ = 0,0,0).
func signed_rgb_reset_button() -> Button:
	return _signed_rgb_reset


## The shared tint-refresh seam (ADR-0087 dec. 14) — lane-agnostic despite the
## palette-era name: the page's _sync_tint dispatch feeds it either lane's bytes + achieved
## colour (palette r/g/b or screen start_r/g/b), and it refreshes whichever tint widgets the
## rendered section owns.
## Materialize the current tint bytes into the palette controls IN PLACE (ADR-0087) — the
## signed-Δ row is the single source of truth, so whatever set the bytes (the picker, a +/- box,
## the No-tint reset) refreshes the OTHER views without a re-render (which would destroy a live
## picker popup or a mid-scrub spinbox). `rgb` is the raw byte triple; the boxes show its signed
## form. `achieved` is the folded result (TintSolver.result) — the "actual" swatch always shows
## it, and the picker colour moves to it too when `update_picker` is set (i.e. the picker was NOT
## the source, so it's safe to move; false during an active pick leaves the picker's own value).
## All setters are non-emitting (set_value_no_signal / .color), so refreshing fans no edits.
func refresh_palette_tint(rgb, achieved: Color, update_picker: bool) -> void:
	var comps := [int(rgb.x), int(rgb.y), int(rgb.z)]
	for i in range(mini(3, _signed_rgb_boxes.size())):
		_signed_rgb_boxes[i].set_value_no_signal(_sb_byte(comps[i]))
	if _actual_swatch != null:
		_actual_swatch.color = achieved
	if update_picker:
		for p in _pick_widgets:
			p.color = achieved


## The live inline quantization-tell Labels beside UNIT-tagged int cells (empty text when
## the typed value round-trips faithfully; "≈ <achieved>" when it can't be hit exactly).
func unit_hints() -> Array:
	return _unit_hints


## The live inline empirical-usage-range hints beside range-bound int cells (ADR-0085 §4):
## the "typical A…B · median M · n=N" corpus hint, flipping to the amber out-of-corpus
## tell when the displayed value leaves the observed envelope.
func range_hints() -> Array:
	return _range_hints


## The live SECOND, instrument-conditional line beside range-bound int cells (ADR-0085
## 2026-08-12): the "with <name>: A…B · median M · n=N" (n-adaptive) corpus line, the
## "none with <name>" empty-bucket line, or the milder "unusual for <name>" tell.
func range_instrument_hints() -> Array:
	return _range_instrument_hints


func _clear_grid() -> void:
	for c in _grid.get_children():
		c.queue_free()
		_grid.remove_child(c)


func _clear_groups() -> void:
	if _groups_box == null:
		return
	for c in _groups_box.get_children():
		c.queue_free()
		_groups_box.remove_child(c)
	_group_grids.clear()
	_colour_channel_sparklines.clear()
	_colour_channel_pickers.clear()
	_folds.clear()          # live widgets only — _fold_state is the session memory
	_fold_bulk.clear()
	_section_folds.clear()       # ditto: _section_state is what survives the rebuild
	_section_bulk = {}
	_follows.clear()
	_relevance_markers.clear()
	_hidden_reveals.clear()
	_velocity_formulas.clear()
	_sparklines.clear()
	_child_toggles.clear()
	_pick_widgets.clear()
	_gradient_pickers.clear()
	_actual_swatch = null
	_choice_widgets.clear()
	_int_widgets.clear()
	_enum_widgets.clear()
	_enum_detail_hints.clear()
	_curve_pick_widgets.clear()
	_bitflag_groups.clear()
	_radio_groups.clear()
	_signed_rgb_boxes.clear()
	_signed_rgb_reset = null
	_range_hints.clear()
	_range_instrument_hints.clear()
	_unit_hints.clear()
	_param_row_count = 0


# A value cell longer than this wraps instead of stretching its grid column — an
# unwrapped long const string widens the column past the panel edge and shoves every
# LATER field (including buttons) out of the visible area. Width caps the wrap column.
const LONG_CELL_WRAP_CHARS := 48
const LONG_CELL_WRAP_WIDTH := 260.0


## A header row's LABEL cell, which grows a picture when the row asked for one and a
## provider is set (#247). The thumbnail rides INSIDE the label cell rather than taking
## a column of its own: `_grid` packs `GRID_COLUMNS` cells per line — three label/value
## pairs across — so a third cell per row would re-flow every header in the studio, not
## just the sequence ones.
##
## The provider is the host's, because a thumbnail needs the texture, the framesets and
## the sequence's shared bounds, and this inspector deliberately holds no effect data.
## No provider, or a provider that declines, renders exactly the old label.
func _label_cell(row: Dictionary) -> Control:
	var label := _cell(row["label"], COL_LABEL)
	if not row.has("thumb") or not thumbnail_provider.is_valid():
		return label
	var thumb = thumbnail_provider.call(row["thumb"])
	if thumb == null or not (thumb is Control):
		return label
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(thumb)
	box.add_child(label)
	return box


func _cell(text: String, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = col
	if text.length() > LONG_CELL_WRAP_CHARS:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = LONG_CELL_WRAP_WIDTH
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## Apply a projector-declared field tooltip to a rendered cell. A Label ignores the mouse
## by default, so a hover tooltip needs mouse_filter STOP; other Controls already accept it.
## Empty tooltip → no-op (the common case).
func _apply_tooltip(c: Control, tip: String) -> void:
	if tip == "":
		return
	c.tooltip_text = tip
	if c is Label:
		c.mouse_filter = Control.MOUSE_FILTER_STOP


## A clickable reference cell (ADR-0073). `link = {label, target}`: pressing it calls
## the host's navigate callback with the InspectionTarget, following the reference to
## another inspectable object. Rendered flat so it reads like a value, not a fat button.
func _link_button(link: Dictionary) -> Button:
	var b := Button.new()
	b.text = str(link.get("label", ""))
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_color_override("font_color", COL_LINK)
	var target: Dictionary = link.get("target", {})
	b.pressed.connect(func(): _on_navigate.call(target))
	_link_buttons.append(b)
	return b


## An `action` field's value cell: a button whose press fires the host's action callback
## with the field's `action` dict. Rendered as a real (non-flat) button so it reads as a
## "do this" affordance, distinct from a flat link. A `disabled` field greys the button
## (an inert press never reads as broken — the audition console's silent/one-shot gates,
## ADR-0085 2026-08-13); an optional dim sub-label (the `disabled_reason` when disabled,
## else a `hint`) rides under it — e.g. the tail button's "uses the game's fallback point".
func _action_button(param: Dictionary) -> Control:
	var b := Button.new()
	b.text = str(param.get("label", param.get("name", "")))
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.disabled = bool(param.get("disabled", false))
	var action: Dictionary = param.get("action", {})
	if bool(param.get("hold", false)):
		# HOLD-TO-PLAY (ADR-0085 2026-08-13 audition console): sounds while pressed. Press
		# fires `action`; release fires the field's `release_action` (a plain key-off).
		var release: Dictionary = param.get("release_action", {})
		b.button_down.connect(func(): _on_action.call(action))
		b.button_up.connect(func(): _on_action.call(release))
	else:
		b.pressed.connect(func(): _on_action.call(action))
	_action_buttons.append(b)
	var sub: String = str(param.get("disabled_reason", "")) if b.disabled else str(param.get("hint", ""))
	if sub == "":
		return b
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.add_child(b)
	var lbl := Label.new()
	lbl.text = sub
	lbl.modulate = COL_DIM
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(lbl)
	return box


## A live child-spawn edge's value cell (ADR-0075): a checkbox + the child link in one
## HBox (so it occupies a single grid column). Checked = spawning; unchecking suppresses
## the `(parent, edge)` spawn via the toggle callback. Seeded from the suppressed provider.
func _suppress_cell(toggle: Dictionary, link_btn: Button) -> Control:
	var pidx: int = int(toggle.get("parent_index", -1))
	var edge: String = str(toggle.get("edge", ""))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	var cb := CheckBox.new()
	cb.focus_mode = Control.FOCUS_NONE
	cb.button_pressed = not bool(_suppressed_provider.call(pidx, edge))
	cb.tooltip_text = "Checked = this emitter spawns the child (%s). Uncheck to suppress that spawn and re-simulate." % edge
	cb.toggled.connect(func(on: bool): _on_toggle_suppress.call(pidx, edge, not on))
	hb.add_child(cb)
	hb.add_child(link_btn)
	_child_toggles.append(cb)
	return hb
