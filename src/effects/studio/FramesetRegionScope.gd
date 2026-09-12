extends VBoxContainer
## The region SCOPE control — ADR-0099 dec. 5, and the single thing standing between
## the region query and an author actually using it.
##
## "Move and resize both act on the region, under one visible scope control": a radio
## (*all N frames* — the default — / *this frame only* / *k selected*), facet filters
## (upright / mirrored / rotated / this frameset / palette) and a member list beneath
## it. The member count is stated BEFORE the drag, not after: E019 packs 184 frames
## onto 14 regions, so a drag routinely moves thirty sprites at once, and missing one
## leaves a frame pointing at the old art with no diagnostic anywhere.
##
## SCOPE IS A VISIBLE CONTROL, NEVER A MODIFIER (dec. 6). The studio's chords are all
## spoken for — `Shift`+left is pan on `EffectScoreTimeline`, `EffectFramesBar` and
## `FedsPairLanePanel`, `Alt`+left draws the frames-bar loop region — and a modifier
## cannot state a blast radius before the gesture starts anyway, which is the whole
## requirement.
##
## THE DEFAULT IS `ALL`, DELIBERATELY. *This frame only* is the safe-FEELING default
## and the wrong one: the sharing is the point of the model, and defaulting to a
## single frame would silently reproduce the 30-identical-drags problem the ADR was
## written to remove. The count is made visible instead of the default made timid.
##
## THE MODE PERSISTS; ONLY A HAND-BUILT SUBSET DOES NOT (ADR-0099 dec. 5e, 2026-08-21).
## The original reading — *it resets to `all` whenever a different region is opened* — was
## enforced by `bind`, which has FOUR callers and only one of which is "a different region
## was opened": the panel re-binding on a thumbnail change, the pointer crossing to another
## live box, a click pinning one, and the author's own drag committing. Reported as *"if you
## then change the thumbnail, it flips back to effect. the scope should persist."*
##
## Two things make persistence the safer reading, not the laxer one:
##   * THE RESET IS ITSELF A SILENT FAILURE, in the opposite and worse direction. An author
##     who narrows the scope, looks at another sprite and comes back drags believing they
##     are still narrow and moves thirty frames. dec. 5 was written to prevent exactly that
##     count being wrong; it prevented the under-edit and minted the over-edit.
##   * THE CONTROL IS VISIBLE AND STATES THE COUNT for whatever region it is now bound to,
##     which is dec. 5's actual requirement. A persisted mode is announced, not silent.
##
## `SCOPE_SUBSET` is the exception and it is not a compromise. The two other modes are
## RULES — *everything* and *this frameset* — which every region can honour and which
## re-evaluate against the new members by themselves. A subset is a hand-built LIST of one
## region's framesets; carried into a different region it either names framesets that region
## has no members in (an empty selection, which dec. 5c refuses outright) or happens to name
## all of them (a subset that silently means *all*, which is the failure dec. 5 exists to
## prevent). So it degrades to `SCOPE_FRAMESET` — the narrowest scope expressible without
## inventing a choice the author never made — and the radio says so.
##
## A region change is a change of MEMBERSHIP, not of block. The region's own rect moves on
## every commit, so comparing `Rect2i` would reset the scope after each drag — on the caller
## whose whole meaning is "the author's edit landed". And NO region in context (the resting
## bind, or the pointer between boxes) is not a change at all: it is the absence of a
## subject, so the scope keeps whatever it had and is intact when a box is entered again.
##
## The selection rule is exposed as PURE statics (`select_members`, `order_framesets`,
## `scope_label`) — the same test seam `FramesetCanvas`'s coordinate math uses, so the
## rule is assertable without a live node, a window or a screenshot. This is a separate
## file from `EffectStudioPage.gd` on purpose: the page only builds it and connects one
## signal, so the region feature does not have to land inside that (large, heavily
## contended) file.
##
## ─── THE LIST HAS TO SAY WHAT IT IS (2026-08-21) ───
##
## Author, on the ADR-0130 dec. 11 overlay: *"in the texture collapsible section why does
## it list frames? what's the thinking"*. The thinking was all of the above and NONE of it
## was on screen. Four things made a blast-radius statement read as an unexplained roster:
##
##   * "6 frames in this region — all will move" names `region`, which this overlay never
##     defines, and states a consequence with no agent and no gesture. It reads as one more
##     FACT — a row of the grid it sits under — where it is the only line in the box about
##     something that has not happened yet. It now names the gesture first: "⚠ An edit here
##     changes 6 frames", and the trailing text introduces the rows instead of standing
##     apart from them.
##   * THE SPLIT WAS NOT STATED. 81.4% of corpus regions have members in more than one
##     frameset, so the list is usually naming frames that are NOT ON SCREEN — which is
##     its whole job, and the one thing it never said. The author hit exactly this
##     ("I thought the change was effect wide?"). The label now prints the split: "3 in
##     this frameset, 3 in framesets not shown".
##   * A ONE-MEMBER LIST IS A RESTATEMENT. 17.2% of regions are singletons; there the row
##     repeats the address the facts grid printed two lines above it, verbatim. The COUNT
##     is still stated ("changes this frame only") — ADR-0099 dec. 5 asks for the count,
##     not for a list of one — and the list itself is hidden.
##   * THE HEIGHT WAS FIXED AT THE 30-MEMBER WORST CASE. Measured on E066 frameset 59 with
##     a `frame` target: one member, one row, and 124px of reserved box — ~200px of empty
##     dark rectangle under a single line. That is the author's own standing complaint
##     ("a bunch of dead space") reproduced inside the overlay that was built to answer it.
##     The host now states a CEILING (`list_max_height`) and the list asks for the height
##     its rows actually need.
##
## AND THE ROWS ARE NOT SELECTABLE. An `ItemList` is a picker; these rows highlight on
## click and do nothing, because the radio and the facet filters described above were
## never built — `set_scope` / `set_facet` have no caller outside the tests. An affordance
## that answers a click with nothing is a worse lie than an absent one, so selection is
## off until the control that would consume it exists.
##
## No `class_name` (ADR-0004).

const Canvas = preload("res://src/effects/studio/FramesetCanvas.gd")
const ScrubField = preload("res://src/effects/studio/ScrubField.gd")

## The factor's bounds. Wide enough for anything the corpus plausibly wants (its own ramps
## span 6x) and short of the values where every member refuses anyway — `scale_verdict`
## is what actually decides, per member, before any write.
const SCALE_MIN := 0.05
const SCALE_MAX := 20.0

## The member list the next edit will touch. Emitted whenever the scope, a facet or the
## bound region changes — the page lowers it through `Canvas.region_edits` (dec. 9).
signal scope_changed(members: Array)

## The author asked to SCALE the selected members by `factor` (ADR-0099 dec. 3 amendment).
## Emitted on Apply, never on a keystroke — the factor is a value the author is composing
## and half of "1.25" is "1.2", which would be a 30-frame edit nobody asked for.
##
## THE VERB LIVES HERE, BESIDE THE COUNT, and that placement is dec. 5 and not taste. The
## per-frame Width/Height rows on the frame screen were the other candidate and are the
## more discoverable surface, but dec. 5 requires the blast radius to be STATED BEFORE the
## gesture: a row that looks per-frame silently moving 30 frames is the exact failure the
## scope control exists to prevent, and that row cannot show a count from the screen it
## lives on. So Width/Height stay this frame's, and the region verb is named, deliberate,
## and sitting under the sentence that says how many frames it will reach.
signal scale_requested(factor: float, members: Array)

## THE SCOPE VOCABULARY, AMENDING ADR-0099 dec. 5 (author, 2026-08-21: *"I think we need
## to have a scope toggle. effect wide, frameset wide, subset of framesets (manual toggle,
## thumbnail order)"*).
##
## IT KEYS ON THE FRAMESET, NOT THE FRAME, and the corpus is why. Censused over all 398
## effects with framesets (`tools/census_region_framesets.gd`): of the 3,251 regions with
## more than one member, **91.5% have members in more than one frameset**, and a region
## spans a median of **3** framesets (p75 6, p90 11, p95 15, max 71) against a median of 4
## members (p90 12, max 107). So the frameset is both the smaller list AND the unit the
## author is looking at — the strip draws framesets, the viewport plays framesets, and
## "frame 2 of frameset 17" is an address they cannot see.
##
## dec. 5's original vocabulary was `all / this frame only / k selected` with facet filters
## on flip, orientation, frameset and palette. SUPERSEDED, and not for convenience:
##   * `this frame only` is not expressible as a picture. E019 puts two members of one
##     region in the SAME frameset, so "this frame" and "this frameset" differ — and the
##     author cannot see which of the two frames they got.
##   * THE FACET FILTERS ARE DROPPED. They enumerate the ways members can DIFFER (mirrored,
##     rotated, palette), which is a fact about the data and not a task anyone has: two
##     members sampling one rect draw the same texels whether or not one is mirrored, so
##     there is no art reason to move one and not the other. They were also never built —
##     `set_facet` had no caller outside the tests for the whole life of the file.
enum { SCOPE_EFFECT, SCOPE_FRAMESET, SCOPE_SUBSET }

var _framesets: Array = []
var _region: Rect2i = Rect2i()
var _members: Array = []
var _scope: int = SCOPE_EFFECT
var _this_ref: Vector2i = Vector2i(-1, -1)   # (frameset_index, frame_index) the region was opened from
## The ticked FRAMESETS under `SCOPE_SUBSET`, `frameset_index -> true`. Frameset-keyed, so
## a tick means "this whole sprite moves" and cannot half-select a frameset whose two
## members both sit in this region.
var _ticked: Dictionary = {}
## Which members `_scope` and `_ticked` were last chosen FOR — `member_key`'s addresses.
## Only a bind whose members differ from these is "a different region was opened"; see the
## header. Left untouched by a bind that resolves no region at all.
var _scope_key: Array = []
## How many live regions the host is showing when NO frame is in context. Zero on a
## `frame` target, where there is a region and the members speak for themselves. It is the
## difference between "there is nothing here" and "there are five things here and you have
## not pointed at one yet" — and the old label said the first while five draggable boxes
## were on screen.
var _region_count: int = 0

## Hide the member list outright, for a host that is already showing the same set BETTER.
## The texture tab's frameset rail draws every frameset of the region as a ticked
## thumbnail, so the rows underneath it repeat that set as text — in a box whose height is
## the scarcest thing on the surface. The page's column host has no rail and keeps them.
## A SETTER, because the host sets it AFTER `bind` — it cannot know whether its rail has a
## row until the scope has resolved one — and `bind`'s refresh has already run by then. A
## plain field would leave the list drawn until whatever happened to refresh next.
var list_suppressed: bool = false:
	set(value):
		if value == list_suppressed:
			return
		list_suppressed = value
		_refresh()

## The most HEIGHT the member list may take, stated by the HOST because the right answer
## differs per host: a column has height to give and wants the list to expand into it, an
## overlay on the artwork does not. Zero means unbounded (the column case, and the
## historical behaviour). Non-zero makes the list ask for its rows and stop there.
var list_max_height: float = 0.0

var _summary: Label = null
var _member_list: ItemList = null
var _scope_group: ButtonGroup = null
var _scope_buttons: Array = []
var _scale_field = null
var _scale_apply: Button = null


func _ready() -> void:
	if _summary == null:
		_build()


func _build() -> void:
	_summary = Label.new()
	_summary.text = "No region"
	# WRAPPED, NOT CLIPPED, and that is a width decision as much as a reading one. This
	# label is the ADR-0099 blast-radius statement ("30 frames in this region — all will
	# move"), so clipping it would hide the number it exists to show. Un-wrapped it reports
	# its whole text run as its minimum width — ~250px — and since ADR-0130 dec. 11 this
	# control lives inside a 248px overlay on the texture canvas, where that minimum blew
	# the overlay out to 315px and the tab's own guard caught it. Autowrap makes the
	# minimum the longest WORD instead, and the sentence still reads in full.
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_summary)
	add_child(_build_scope_row())
	_member_list = ItemList.new()
	# NO height floor. This panel sits inside the frameset canvas's PanelContainer, whose
	# assigned height `EffectStudioPage._relayout` computes; a `custom_minimum_size` floor
	# here would raise that container's COMBINED MINIMUM above the height it is given, and
	# a container cannot shrink below its minimum — so the panel would silently overflow
	# downward into the timeline. It expands into whatever is left instead.
	_member_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_member_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_member_list)
	add_child(_build_scale_row())


## THE SCOPE TOGGLE — three counted buttons, and the control ADR-0099 dec. 5 has been
## describing since it was written.
##
## COUNTED, because the count is the decision. "Frameset" is not a meaningful choice until
## you know it means 2 of 12; dec. 5's rule is that the blast radius is stated BEFORE the
## gesture, and a toggle whose consequence you learn by pressing it states it after.
##
## `button_group` rather than three independent toggles: they are mutually exclusive and a
## radio that can show two pressed states is a control that has lied at least once.
##
## `Pick` DOES NOT OPEN ANYTHING. It seeds the rail's ticks from what is showing and hands
## the author the rail, which is already on screen — a mode press that spawned a chooser
## would be the popup this design rejected, and the tiles are the chooser.
func _build_scope_row() -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_theme_constant_override("separation", 2)
	# NO ROW LABEL. It shipped with one ("Move") and the label was the only thing that
	# survived: at 11px inside a 236px overlay it took ~40px the three buttons then did not
	# have. It was also wrong — move, resize AND the scale verb all act on this selection,
	# so naming one of them mislabels the other two. The sentence directly above already
	# says what the choice is about ("⚠ An edit here changes 15 frames").
	_scope_group = ButtonGroup.new()
	for spec in [[SCOPE_EFFECT, "Effect", "Every frame in the effect that samples this rect."],
			[SCOPE_FRAMESET, "Frameset", "Only this frameset's frames. The others keep the old rect and split off."],
			[SCOPE_SUBSET, "Pick", "Tick the framesets on the rail below the sheet."]]:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = _scope_group
		# NOT `flat`. Every other Button this family builds is flat, and for a fold header or
		# a one-shot action that is right. A RADIO is different: its entire job is to say
		# which of three states is current, and a flat Button's pressed state is a faint
		# background wash with no border to contrast against — on the shot it was not
		# readable at all. That is the fold chevron's defect one control over ("a flat Button
		# draws no border", `cbe359478`'s sibling), and here it would leave the author unable
		# to tell an effect-wide drag from a two-frame one.
		b.focus_mode = Control.FOCUS_NONE
		# CLIPPED. A Button's text sets its minimum width, and this row is the third control
		# in this file to bid straight into the 248px overlay's ceiling if left un-clipped.
		b.clip_text = true
		# EXPAND_FILL, AND WITHOUT IT THE ROW IS INVISIBLE. `clip_text` drops a Button's
		# minimum width to ~zero — which is the point, it is what stops the longest count
		# from setting the overlay's width — and an `HBoxContainer` hands a child with no
		# expand flag exactly its minimum. So all three collapsed to nothing and the row
		# rendered as a bare label. Screenshotted; every assertion was green, because a
		# control that is present, laid out and zero pixels wide passes every predicate
		# about its existence. The three now split the row evenly instead.
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = String(spec[2])
		b.set_meta("scope_mode", int(spec[0]))
		b.pressed.connect(func(): set_scope(int(spec[0])))
		_scope_buttons.append(b)
		row.add_child(b)
	return row


## Repaint the toggle row: the pressed one, and each button's count.
##
## `set_pressed_no_signal`, because `set_scope` is reachable from the buttons AND from
## `toggle_frameset` (a rail tick switches the mode) — writing `button_pressed` here would
## re-enter through `pressed` and reset the ticks the tick just made.
func _refresh_scope_row() -> void:
	for b in _scope_buttons:
		var mode: int = int(b.get_meta("scope_mode", SCOPE_EFFECT))
		b.set_pressed_no_signal(mode == _scope)
		var n: int = select_members(_members, mode, _this_ref.x,
			_ticked if mode == SCOPE_SUBSET else {}).size()
		var name: String = ["Effect", "Frameset", "Pick"][mode]
		# NO COUNT ON AN UNRESOLVED REGION — "Effect 0" beside five draggable boxes reads as
		# a broken control, which is the defect the resting label was fixed for.
		b.text = name if _members.is_empty() else "%s %d" % [name, n]
		b.disabled = _members.is_empty()


## The region SCALE verb — ADR-0099 dec. 3's amendment, and the only vertex write a region
## edit is allowed to make.
##
## Dec. 3 forbids a region edit from touching vertices at all, on the grounds that "a region
## edit cannot change how big or how turned any member is drawn — which is what makes
## decision 1 safe for the 62% of groups that deliberately vary scale". That reasoning is
## about an ADDITIVE delta: a uniform offset over 30 members drawing at 7x7 through 56x56
## would flatten a 6x growth ramp into a constant. A MULTIPLICATIVE factor has no such
## failure — it preserves every ratio the group encodes, so the ramp stays a ramp — which is
## the distinction the amendment turns on and the reason this one verb is admitted while the
## rest of dec. 3 stands.
##
## MULTIPLY, NEVER SET. "Set every member to 1.50x" is expressible now that scale is read
## against a shared base, and it is exactly the flattening dec. 3 refused; it is not offered.
##
## The button is the commit, not the box: `1.25` typed a digit at a time passes through
## `1.2`, and a live-fanning factor would make that a 30-frame edit the author never asked
## for. The factor also resets to 1.00 after a commit, so a second Apply is never an
## accidental 2.25x compounding of a 1.5x the author has stopped looking at.
func _build_scale_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var label := Label.new()
	label.text = "Scale"
	row.add_child(label)
	_scale_field = ScrubField.new()
	_scale_field.min_value = SCALE_MIN
	_scale_field.max_value = SCALE_MAX
	_scale_field.step = 0.05
	_scale_field.suffix = "×"
	_scale_field.custom_minimum_size.x = 64.0
	_scale_field.set_value_no_signal(1.0)
	row.add_child(_scale_field)
	_scale_apply = Button.new()
	_scale_apply.text = "Apply"
	# A Button's TEXT sets its minimum width and that propagates through this control to the
	# 248px overlay it lives in (the same width lesson the summary label above records). One
	# short word, and the explanation rides the tooltip, which costs nothing.
	_scale_apply.tooltip_text = ("Multiply every selected member's drawn size by the factor, "
		+ "about the sprite origin. Ratios between members are preserved, so a growth ramp "
		+ "stays a ramp. Refused outright if any member would leave the signed 16-bit vertex "
		+ "range or collapse to no area.")
	_scale_apply.pressed.connect(func():
		var f: float = _scale_field.value
		if is_equal_approx(f, 1.0):
			return
		scale_requested.emit(f, selected_members())
		_scale_field.set_value_no_signal(1.0))
	row.add_child(_scale_apply)
	return row


## Open the region the frame at `(frameset_index, frame_index)` belongs to.
##
## THE SCOPE SURVIVES THIS unless the MEMBERSHIP changed, and a hand-built subset does not
## survive even then (ADR-0099 dec. 5e — the reasoning is in the header, and it is the whole
## point of this call rather than a detail of it).
##
## `region_count` is the RESTING state's content: how many live regions the host is
## showing when `frame_index` is negative because the author has not pointed at one yet.
## Without it this call resolves nothing and the control says "No region" — beside five
## yellow boxes that are all draggable, which is false and reads as broken.
func bind(framesets: Array, frameset_index: int, frame_index: int,
		region_count: int = 0) -> void:
	_framesets = framesets
	_region = Canvas.region_of(framesets, frameset_index, frame_index)
	_members = Canvas.region_members(framesets, _region)
	_this_ref = Vector2i(frameset_index, frame_index)
	_region_count = region_count
	var key: Array = member_key(_members)
	# NO REGION IN CONTEXT is not a region change. The resting bind on a multi-region
	# frameset and the pointer leaving every box both land here, and both are reachable on a
	# mouse-move — so treating them as a change would put the reset back on the exact path
	# ADR-0130 dec. 12f had to pin a region to escape.
	if not key.is_empty() and key != _scope_key:
		_scope_key = key
		# A LIST CANNOT BE CARRIED; a rule can. See the header.
		if _scope == SCOPE_SUBSET:
			_scope = SCOPE_FRAMESET
		_ticked = {}
	_refresh()


## Who the current scope is ABOUT: every member's `frameset/frame` address, sorted. The
## region's identity for the purpose of dec. 5e, and deliberately not its `Rect2i` — a
## region move rewrites the block and keeps the frames, so the block says "different region"
## on the one bind that means "your edit landed". Pure.
static func member_key(members: Array) -> Array:
	var out: Array = []
	for m in members:
		out.append("%d/%d" % [int(m.get("frameset_index", -1)), int(m.get("frame_index", -1))])
	out.sort()
	return out


func region() -> Rect2i:
	return _region


func members() -> Array:
	return _members


func scope() -> int:
	return _scope


## Switch mode. `SCOPE_SUBSET` SEEDS ITS TICKS FROM WHAT WAS SHOWING, so the toggles are a
## bulk-set of the rail rather than a separate state that starts empty: an author who was
## on `Effect` and presses `Pick` gets everything ticked and un-ticks from there, which is
## dec. 5's "the count is made visible instead of the default made timid" applied to the
## new mode. Seeding from EMPTY would put an all-or-nothing default in front of the one
## control whose whole job is partial selection.
func set_scope(value: int) -> void:
	if value == SCOPE_SUBSET and _scope != SCOPE_SUBSET:
		_ticked = {}
		for m in select_members(_members, _scope, _this_ref.x, {}):
			_ticked[int(m.get("frameset_index", -1))] = true
	_scope = value
	_refresh()


## Tick or un-tick ONE frameset, and switch to `SCOPE_SUBSET` by doing so — touching a rail
## tile IS choosing to pick, so it never needs a mode press first.
##
## UN-TICKING THE LAST ONE IS REFUSED. An empty selection is an edit that moves nothing,
## and a drag that silently does nothing is worse than a refused click: the author would
## release the mouse and read a status line about zero frames. `Effect` is one press away.
##
## A ONE-FRAMESET REGION REFUSES THE WHOLE GESTURE, mode switch included (2026-08-21). The
## rail shows a tile for every region now, so its sole tile is clickable on the 54.8% of
## corpus regions that live in one frameset — and there the two rules above collided: the
## mode flipped to `Pick` and the un-tick was then refused, so the click's ENTIRE effect was
## to move the scope control to a mode with nothing in it to pick. Refusing before the
## switch makes the sole tile inert, which is what it means: there is no subset of one thing.
func toggle_frameset(frameset_index: int) -> void:
	if region_framesets().size() <= 1:
		return
	if _scope != SCOPE_SUBSET:
		set_scope(SCOPE_SUBSET)
	if _ticked.has(frameset_index):
		if _ticked.size() <= 1:
			return
		_ticked.erase(frameset_index)
	else:
		_ticked[frameset_index] = true
	_refresh()


## Every frameset this region has a member in, ASCENDING. The rail's row, and the unit the
## subset mode ticks. A host that knows the sequence re-orders it (`order_framesets`).
func region_framesets() -> Array:
	return distinct_framesets(_members)


func is_frameset_selected(frameset_index: int) -> bool:
	for m in selected_members():
		if int(m.get("frameset_index", -1)) == frameset_index:
			return true
	return false


## The members the next region edit will touch — the panel's whole contract to the page.
func selected_members() -> Array:
	return select_members(_members, _scope, _this_ref.x, _ticked)


func _refresh() -> void:
	var picked := selected_members()
	if _summary != null:
		_summary.text = scope_label(_members, picked, _this_ref.x, _region_count)
	if not _scope_buttons.is_empty():
		_refresh_scope_row()
	if _member_list != null:
		_member_list.clear()
		var varying: Dictionary = varying_facets(_members)
		for m in _members:
			var i: int = _member_list.add_item(member_label(m, varying))
			# NOT SELECTABLE — see the header. Set per item because `add_item` mints them
			# selectable and `ItemList` has no "never select" mode.
			_member_list.set_item_selectable(i, false)
		# A list of one repeats the line above it and the facts grid above that; a list of
		# none is a labelled void. Either way the COUNT is in the summary, which is what
		# dec. 5 asks for — the enumeration only earns its height when there is something
		# to enumerate.
		_member_list.visible = _members.size() > 1 and not list_suppressed
		_size_list()
	scope_changed.emit(picked)


## The list asks for the height its ROWS need, up to the host's ceiling. Called on every
## refresh because the row count is the input, and read off the LIVE theme because this
## control is hosted at two font sizes (the dashboard body in a column, 11px inside the
## texture overlay) and a hard-coded row height would be wrong at one of them.
##
## Under-shooting is harmless — the `ItemList` has its own scrollbar and that is exactly
## what the 30-member case is for. Over-shooting is not, so the ceiling is a clamp and not
## a suggestion.
func _size_list() -> void:
	if _member_list == null:
		return
	if list_max_height <= 0.0:
		# The column host: expand into whatever height the container has, as before.
		_member_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_member_list.custom_minimum_size.y = 0.0
		return
	_member_list.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if not _member_list.visible:
		_member_list.custom_minimum_size.y = 0.0
		return
	var font: Font = _member_list.get_theme_font("font")
	var row: float = 16.0
	if font != null:
		row = font.get_height(_member_list.get_theme_font_size("font_size"))
	row += float(_member_list.get_theme_constant("v_separation"))
	var chrome: float = 0.0
	var sb: StyleBox = _member_list.get_theme_stylebox("panel")
	if sb != null:
		chrome = sb.get_minimum_size().y
	_member_list.custom_minimum_size.y = clampf(
		float(_members.size()) * row + chrome, 0.0, list_max_height)


## PURE. Which members a scope selects.
##
## `SCOPE_SUBSET` with NO ticks selects nothing, and deliberately does not fall back to the
## whole region: a selection that silently means "all" is how an author moves thirty frames
## intending to move two. The live control cannot reach that state (`toggle_frameset`
## refuses to un-tick the last one), which is a UI guarantee — this static still has to be
## honest for a caller that builds the dictionary itself.
static func select_members(members: Array, scope_mode: int, this_frameset: int,
		ticked: Dictionary) -> Array:
	var out: Array = []
	for m in members:
		var fs_i: int = int(m.get("frameset_index", -1))
		match scope_mode:
			SCOPE_FRAMESET:
				if fs_i != this_frameset:
					continue
			SCOPE_SUBSET:
				if not ticked.has(fs_i):
					continue
		out.append(m)
	return out


## PURE. The distinct framesets a member list touches, ascending. The rail's row.
static func distinct_framesets(members: Array) -> Array:
	var seen: Dictionary = {}
	for m in members:
		seen[int(m.get("frameset_index", -1))] = true
	var out: Array = seen.keys()
	out.sort()
	return out


## PURE. `framesets` re-ordered into THUMBNAIL ORDER — the order the sequence on screen
## first reaches each one — with the ones that sequence never plays kept, in index order,
## at the end.
##
## The tail is not a leftover, it is the point. On E317 the author moved a box on emitter 6
## and reported *"only thumbnail 1 changed. I thought the change was effect wide?"*: the
## region's six members sit in framesets 15/17/18/19/20/21 and that emitter's sequence only
## ever plays 15, 16 and 22 — so FIVE of the six are frames no thumbnail on screen can
## show. Ordering by the strip puts the ones they can check first and leaves the rest
## visible rather than sorted away.
##
## REPEATS RESOLVE TO THE FIRST OCCURRENCE, the same rule `SequenceLifeMap` settled on, so
## a looping sequence does not reorder the rail every time it comes round.
##
## `strip_framesets` is the `frameset` field of `SequenceTimeline.trace`, in cell order,
## repeats and all. Pure.
static func order_framesets(framesets: Array, strip_framesets: Array) -> Array:
	var rank: Dictionary = {}
	for i in range(strip_framesets.size()):
		var f: int = int(strip_framesets[i])
		if not rank.has(f):
			rank[f] = i
	var played: Array = []
	var unplayed: Array = []
	for f in framesets:
		if rank.has(int(f)):
			played.append(int(f))
		else:
			unplayed.append(int(f))
	played.sort_custom(func(a, b): return int(rank[a]) < int(rank[b]))
	unplayed.sort()
	return played + unplayed


## PURE. The blast radius, stated before the drag (dec. 5) — and, since the author read
## the old wording as a roster rather than a warning, stated as a CONSEQUENCE OF A GESTURE.
##
## "An edit here", not "in this region": the gesture is what the author is about to make
## and "here" is the box under the pointer, where `region` is vocabulary this overlay
## never defines. `An edit` and not `a drag` because move AND resize both act on the
## region (ADR-0099) and a label naming only one of them is wrong half the time.
##
## THE SPLIT IS THE PART THAT WAS MISSING. 81.4% of corpus regions have members in more
## than one frameset and the median region holds ~6 frames, so the list is normally naming
## frames the view cannot show — and saying only "6 frames" invites the reading the author
## actually had ("I thought the change was effect wide?"). `this_frameset` is the frameset
## on screen; pass -1 where there is none and the split is simply omitted rather than
## guessed at.
##
## The resting case is a real state, not an error: `region_count` live boxes on the sheet
## and the pointer on none of them. It used to say "No region", which is what a broken
## control says.
static func scope_label(members: Array, selected: Array, this_frameset: int = -1,
		region_count: int = 0) -> String:
	if members.is_empty():
		if region_count > 1:
			return "%d regions here — point at one to see what an edit changes" % region_count
		if region_count == 1:
			return "1 region here — point at it to see what an edit changes"
		return "No region"
	if selected.size() != members.size():
		# A NARROWED SCOPE IS A SPLIT, AND THE LABEL SAYS SPLIT. This is the sentence the
		# control exists to get right. `region_edits` writes each member's OWN uv bytes and
		# a region is RECOMPUTED from those bytes on every read — there is no region table —
		# so leaving a member out does not make a smaller edit, it gives the moved frames a
		# new rect and leaves the rest behind as their own region. "2 of 6 frames will move"
		# is true and useless: it hides that the group the author has been treating as one
		# thing stops being one thing. (`region_merge_preview` already announces the reverse,
		# when a drag lands on another region's exact block and the two fuse.)
		var staying: int = members.size() - selected.size()
		return ("⚠ SPLITS this region — %d frame%s move, %d keep the old rect:"
			% [selected.size(), "" if selected.size() == 1 else "s", staying])
	if members.size() == 1:
		return "An edit here changes this frame only"
	var here: int = 0
	if this_frameset >= 0:
		for m in members:
			if int(m.get("frameset_index", -1)) == this_frameset:
				here += 1
	var elsewhere: int = members.size() - here
	if this_frameset < 0 or elsewhere == 0:
		return "⚠ An edit here changes %d frames:" % members.size()
	return ("⚠ An edit here changes %d frames — %d in this frameset, %d in framesets "
		+ "not shown:") % [members.size(), here, elsewhere]


## PURE. Which facets the members of a region DISAGREE on. `{}` when they agree on
## everything, or when there is nothing to compare.
##
## The row labels print these and nothing else, and the reason is this file's own: the
## facets are carried because "the count alone is not enough to consent to a thirty-frame
## edit when the members disagree about how they are drawn". A facet every member SHARES
## carries no such information — it is the same word repeated down the column.
##
## It is also what makes a row fit. Measured inside the 248px texture overlay at 11px:
## "frameset 16 / frame 0  ·  105x113  ·  pal 0" truncated at "· p…", so the tail the
## author would need was the half that got cut. Dropping the agreed facets leaves
## "frameset 16 / frame 0" whole, and a row that DOES differ still prints why.
static func varying_facets(members: Array) -> Dictionary:
	var out: Dictionary = {}
	if members.size() < 2:
		return out
	for key in ["mirrored", "v_flipped", "orientation", "quad_size", "palette_id"]:
		var first = members[0].get(key, null)
		for m in members:
			if m.get(key, null) != first:
				out[key] = true
				break
	return out


## PURE. One member as the list renders it: where it lives, and the facets on which it
## differs from its neighbours.
##
## `varying` is `varying_facets(members)` — the keys worth printing. `null` prints every
## facet, which is the whole truth about one member and what a caller with room for it
## should ask for; the overlay has no room and asks for the differences.
static func member_label(member: Dictionary, varying = null) -> String:
	var bits: Array = ["frameset %d / frame %d" % [int(member.get("frameset_index", -1)),
		int(member.get("frame_index", -1))]]
	var all: bool = varying == null
	if (all or varying.has("mirrored")) and bool(member.get("mirrored", false)):
		bits.append("mirrored")
	if (all or varying.has("v_flipped")) and bool(member.get("v_flipped", false)):
		bits.append("v-flipped")
	var orientation: String = String(member.get("orientation", ""))
	if (all or varying.has("orientation")) and orientation != "" and orientation != "upright":
		bits.append(orientation)
	var qs = member.get("quad_size", Vector2i.ZERO)
	if (all or varying.has("quad_size")) and qs is Vector2i and qs != Vector2i.ZERO:
		bits.append("%d×%d" % [qs.x, qs.y])
	if all or varying.has("palette_id"):
		bits.append("pal %d" % int(member.get("palette_id", 0)))
	return "  ·  ".join(bits)
