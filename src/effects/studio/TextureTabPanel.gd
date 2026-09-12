extends PanelContainer
## The TEXTURE TAB — ADR-0130's second (and shallow) texture surface: the sheet's
## picture, on every screen, without navigating.
##
## The complaint this answers is that the studio had FOUR texture surfaces and none
## of them drew the sheet: the only renderer (`FramesetCanvas`, ADR-0098) was gated
## to the `frame` target kind alone, so the Texture page could not show the texture
## by construction and the picture sat three drills deep from anywhere an author
## works.
##
## WHY A TAB AND NOT A BAND. The author's first proposal was a collapsible band
## spanning both columns. It was costed and rejected on arithmetic: a band takes
## height from `budget = h - path_bar - MIN_CHANNELS_H - frames_bar`, which is 268
## TOTAL at the dev body — and the sequence player already wants 348 and is clipped
## to 268 today. A tab is a different slice of a box that already exists, so it costs
## the row no height at all and the player never moves. Measured, showing a 128x256
## sheet at the dev body: the band shows 134 of 256 texel rows (52%), the tab 240
## (94%). See ADR-0130's table.
##
## WHY THIS IS A SEPARATE FILE. `EffectStudioPage.gd` is large and concurrently
## edited; `FramesetRegionScope.gd` split out for exactly this reason and says so.
## The page builds this, connects three signals and positions it — nothing else.
##
## THE HANDLES ARE LIVE AND THE SCOPE CONTROL IS BESIDE THEM (ADR-0130 dec. 5). They
## ship together or not at all: a UV rect is SHARED — E019's 184 frames sit on 14
## distinct rects, the biggest used by 30 — so a drag without the control that states
## its blast radius is the ADR-0099 failure by construction.
##
## ─── THE FACTS RIDE ON THE PICTURE (ADR-0130 dec. 11, 2026-08-21) ───
##
## The metadata is an OVERLAY pinned to the canvas's bottom-right corner, not a column
## beside it. The author, third report on this surface: "this box was supposed to just
## be some tiny box which minimally and/or doesn't cover the texture page. Instead its
## a giant column with a bunch of dead space on it taking up lots of horizontal space
## that should go to the texture."
##
## MEASURED, and the measurement is the whole reason the previous shape had to go
## rather than be tuned. At the dev body the page hands this tab a 1564px slot. The
## canvas was CAPPED at a 560px `CANVAS_W` while the facts `ScrollContainer` carried
## `SIZE_EXPAND_FILL`, so the leftover — 1000px — went to a column whose text is about
## 250px wide. Two thirds of the row was empty column. The sheet drew at 256px inside
## a 560px port with 1000px of nothing beside it.
##
## WHICH CONSTRAINT DISSOLVED, and it is not the one the split was defending.
## `768575272` / `bc2b238f0` made the width a SPLIT because 560 + 300 declared a
## combined minimum of 864 against a row that could be 727 — the panel overflowed
## RIGHT and the sequence player sliced the facts mid-word. That split is not wrong;
## it is UNREACHABLE now. A `Control` (which `FramesetCanvas` is — not a Container)
## does not fold an anchored child into its minimum size, so the facts contribute
## ZERO to this panel's minimum and there is no width for the row and the column to
## disagree about. The failure the split managed cannot occur, so the arithmetic that
## managed it (`CANVAS_W`, `CANVAS_MIN_W`, `DECLARED_SIDE_W`, `set_slot_width`,
## `canvas_width`, `chrome_width`) is deleted rather than left standing as dead
## reasoning. Their case is preserved above, deliberately — this surface has now
## frozen an incidental layout into a rule twice (ADR-0089 dec. 6 is the same shape
## one surface over) and the record of WHY is what stops a third.
##
## THE OTHER DISSOLVED CONSTRAINT is `CANVAS_W`'s own: "at a 1945px panel it made a
## 1241px canvas that centred a 128px sheet in the middle of nowhere, with the sheet's
## own metadata stranded 1100px away at the right edge. The picture and the facts
## about it belong in one glance." That is exactly right, and an overlay satisfies it
## the other way round: the facts are ON the port, so they are adjacent to the picture
## at every width by construction and can never be stranded. With the stranding
## impossible the cap has nothing left to defend, and the canvas takes the slot.
##
## THE THREE TRAPS THIS SHAPE HAS, each handled below and each asserted:
##   * THIRTY MEMBERS. E019's biggest region lists 30 frames. As a side column that is
##     what the scroll was for; as an overlay it would cover the sheet completely —
##     the same complaint, relocated. The scope gets a FIXED height (`SCOPE_H`) and
##     the `ItemList` scrolls inside it, and the whole overlay is capped to the port.
##   * REACHABILITY. Export/Import sit at the TOP of the overlay, above the facts, for
##     the reason `cbe359478` moved ⬥ above the colour grid: an overlay pinned to the
##     bottom edge can put its own last row off the bottom on a short row, and
##     "technically visible, actually unreachable" is the defect that commit fixed.
##   * MOUSE. The panel is `PASS` so hover, zoom and pan keep working through it and
##     the picture is not inert under its own metadata; the buttons and the member
##     list are `STOP` so they still take clicks.
##
## And it FOLDS to the caption alone — about 36px of corner — for when the author wants the
## sheet and nothing else. That is the "tiny box" the ask names. THE WHOLE HEADER IS THE
## TOGGLE, the studio's own collapsible idiom (`EffectKeyframeInspector`) and not one
## invented here; it shipped as a 17px chevron and the author could fold it but not unfold
## it, which is dec. 11c's reachability question on a third axis — present, visible, and
## still not hittable.
##
## No `class_name` (ADR-0004).

const Canvas = preload("res://src/effects/studio/FramesetCanvas.gd")
const RegionScope = preload("res://src/effects/studio/FramesetRegionScope.gd")
const TextureProjector = preload("res://src/effects/studio/TextureProjector.gd")
const TextureChannel = preload("res://src/effects/studio/TextureChannel.gd")
const FramesetRail = preload("res://src/effects/studio/RegionFramesetRail.gd")

## The canvas commits a drag ONCE on mouse-release with the final rect; the page lowers
## it through `Canvas.region_edits` exactly as the frameset canvas's drag does.
signal uv_rect_changed(new_uv: Dictionary)
## "texture_export" / "texture_import" — the SAME action kinds `TextureProjector` emits,
## deliberately: the page's dispatcher routes on `action.kind` alone, so this reuses the
## one dialog path rather than minting a second that could drift from it.
signal action_requested(kind: String)
signal scope_changed(members: Array)

## Re-emitted from the scope control: the author pressed Apply on the region SCALE verb
## (ADR-0099 dec. 3 amendment). Carries the factor and the members it is to reach, so the
## page never re-derives a member list the author did not read — the ADR-0100 rule.
signal region_scale_requested(factor: float, members: Array)
## A drag committed on one of N live group regions (ADR-0130 dec. 12), carrying a
## representative member's index within the BOUND frameset. Separate from
## `uv_rect_changed` all the way up to the page, because the page's two handlers lower
## through different addresses and must not be able to confuse them.
signal group_uv_rect_changed(member_frame_index: int, new_uv: Dictionary)

## The overlay's width. Wide enough for the longest fact this surface prints — "⚠ shared
## by 30 frames in this effect", which autowraps to two lines here — and narrow enough
## that it is corner furniture rather than a second column. The old side column declared
## 300 and was handed 1000; this is a CEILING, clamped down further on a narrow port by
## `overlay_rect`, and it is never a claim on the row.
const OVERLAY_W := 248.0
## The gap between the overlay and the port's corner, so it reads as floating on the
## picture rather than welded to the edge.
const OVERLAY_PAD := 8.0
## The scope control's fixed height when a frame is in context. FIXED, not expanding, and
## that is the whole answer to the thirty-member trap: `FramesetRegionScope`'s `ItemList`
## carries `SIZE_EXPAND_FILL` and has its own scrollbar, so a height stated here is a
## height the list honours by scrolling — where an expanding one would grow the overlay
## by 30 rows and cover the sheet it is annotating.
const SCOPE_H := 124.0
## The most of the port's HEIGHT the overlay may ever take. The width ceiling alone does
## not answer the ask — a 248px column running the full height of the port still covers
## the sheet it annotates, and measured on a `frameset` row (263px) the facts wanted 247 of
## it: 94%. Past this the overlay stops growing and scrolls instead.
##
## It also caps a real Godot transient. An autowrapping Label reports a minimum HEIGHT
## derived from the width it was last laid out at, so a hidden or mid-flow overlay measures
## its facts at a narrow width and asks for a wildly tall box — 966px against a 316px
## settled value, measured on the Texture page's shot. The next flow corrects it, but the
## cap means the wrong value is never large enough to matter.
const OVERLAY_MAX_H_FRACTION := 0.6
## Smaller than the dashboard's body text. The overlay sits ON the artwork, so it is read
## at a glance and not studied; the size is what makes 248px hold two-column facts.
##
## APPLIED AS A `Theme` ON THE OVERLAY, not as a per-Label override, and the screenshot is
## why. Per-node overrides styled the labels this file creates and missed every one it does
## not — `FramesetRegionScope`'s summary and member list are built by another file, so they
## rendered at the dashboard's full body size inside an 11px box and "30 frames in this
## region — all will move" was visually the loudest thing in the overlay. A Theme set on an
## ancestor propagates to every descendant, including the ones this file never touches.
const OVERLAY_FONT_SIZE := 11

var _canvas: Control
var _rail: Control
## The `frameset` of each cell of the sequence on screen, in cell order — the input to
## `FramesetRegionScope.order_framesets`, which is what makes the rail's order THUMBNAIL
## order. Handed in by the page: this panel does not know the sequence, and deriving one
## here would be a second walk of the opcodes that could disagree with the strip.
var _strip_framesets: Array = []
var _overlay: PanelContainer
var _overlay_body: VBoxContainer
var _overlay_scroll: ScrollContainer
var _header_btn: Button
## The caption's text, held apart from the Button that shows it: the fold glyph is
## re-rendered on every toggle and the caption on every bind, and the two must not be able
## to overwrite each other's half of the label.
var _caption_text: String = ""
var _scope
var _title: Label
var _readout: Label
var _facts_grid: GridContainer
var _actions: HBoxContainer
## The ADR-0199 verdict, held apart from `_actions.visible`. The fold hides the actions and
## so does an un-authorable sheet, and two writers on one flag means unfolding a 4bpp
## effect's overlay would offer buttons the format refuses.
var _actions_ok: bool = false
var _refusal: Label
var _export_btn: Button
var _import_btn: Button

## Folded state SURVIVES a rebind — an author who has folded the facts away to look at the
## sheet did not ask for them back because they clicked a different frame.
var _folded: bool = false

var _effect_data = null
var _fs_idx: int = -1
var _fr_idx: int = -1


func _ready() -> void:
	if _canvas == null:
		_build()


func _build() -> void:
	var vb := VBoxContainer.new()
	add_child(vb)

	_title = Label.new()
	_title.text = "Texture"
	# CLIPPED, so it cannot bid for width. A Label with neither autowrap nor clipping
	# reports its whole text run as its minimum — and this one prints the sheet's
	# dimensions, so an un-clipped one would make the panel's minimum a function of the
	# effect that happens to be loaded.
	_title.clip_text = true
	vb.add_child(_title)

	# THE PICTURE, AND IT TAKES THE SLOT. No `custom_minimum_size` and no cap: the facts
	# are anchored inside it now, so there is nothing else in the row to split with and
	# nothing that can be stranded by a wide port. See the header on both dissolutions.
	_canvas = Canvas.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# ADR-0098 dec. 2, AMENDED PER SURFACE (author, 2026-08-20: "can we get the texture
	# defaulted to a reasonable size when we open the texture page? it starts kind of
	# small"). The frame screen keeps the flat 100% ruling — pixel-exactness is what serves
	# UV editing there. THIS surface has no UV work to do when there is no frame in context
	# and a port whose height is whatever the row has, so it opens at the largest ladder
	# rung that shows the whole sheet, FLOORED AT 100%.
	#
	# The floor is the ADR-0098 ruling surviving rather than being overturned, and it is
	# load-bearing: measured on a `frameset` target the port is 263 tall against a 256-tall
	# sheet, so `fit_scale` is a hair under 1 and SNAPS DOWN to 0.5 — halving the picture to
	# save nine pixels, which is the exact objection that made the ruling in the first place.
	_canvas.open_at_fit = true
	vb.add_child(_canvas)
	_canvas.uv_rect_changed.connect(func(uv): uv_rect_changed.emit(uv))
	_canvas.hover_changed.connect(_on_hover)
	_canvas.group_uv_changed.connect(func(m, uv): group_uv_rect_changed.emit(m, uv))
	_canvas.group_region_hovered.connect(_on_group_region_hovered)
	_canvas.group_region_locked.connect(_on_group_region_locked)
	# The port's size is assigned by the layout, so the overlay is re-placed from the
	# signal rather than from `_relayout` — the page does not know this overlay exists and
	# should not have to.
	_canvas.resized.connect(func():
		_place_rail()
		_place_overlay())

	_build_rail()
	_build_overlay()

	_readout = Label.new()
	_readout.text = ""
	# Clipped for the same reason as `_title`, and more urgently: this one carries HOVER
	# text, so an un-clipped one would make the panel's minimum a function of where the
	# mouse is.
	_readout.clip_text = true
	vb.add_child(_readout)

	_place_overlay()


## The rail, ON the port, along its bottom edge. A child of `_canvas` for the same reason
## the overlay is one — `FramesetCanvas` is a `Control` and not a Container, so an anchored
## child reaches no ancestor's minimum size and cannot push this tab into the sequence
## player.
func _build_rail() -> void:
	_rail = FramesetRail.new()
	_rail.visible = false
	_canvas.add_child(_rail)
	_rail.frameset_toggled.connect(_on_rail_toggled)


## Place the rail across the bottom of the port and tell the overlay how much room it took.
## Height comes from the row's LENGTH (`rail_height`), so an empty row is zero and hides —
## the lesson the scope's member list learned when one row cost 124px of reserved void.
func _place_rail() -> void:
	if _rail == null or _canvas == null:
		return
	var n: int = _rail.row().size()
	var h: float = FramesetRail.rail_height(_canvas.size.x, n)
	# NEVER MORE THAN A THIRD OF THE PORT. The tab has measured ports of 150px and the rail
	# sits ON the sheet it annotates; a 71-frameset row at TILE_MAX would otherwise be a
	# second sheet. Past this the tiles shrink (and then the rail scrolls) rather than the
	# picture being covered.
	h = minf(h, _canvas.size.y * 0.34)
	_rail.visible = n > 0 and h > 0.0 and _canvas.size.y > 0.0
	_rail.position = Vector2(0.0, maxf(0.0, _canvas.size.y - h))
	_rail.size = Vector2(_canvas.size.x, h)


## The height the rail has taken off the bottom of the port, which is height the facts
## overlay may not use — and ZERO WHEN THE ROW DOES NOT REACH THE OVERLAY'S COLUMN.
##
## The rail is left-aligned and only as wide as its tiles (`used_width`), so the median
## three-frameset row occupies ~180 units of a port measured at 1562. Lifting the overlay
## by 40px for a rail nowhere near it is the same "reserve space you do not need" mistake
## the scope's own member list was just cured of; the two together would put the facts a
## third of the way up a sheet nothing is covering.
func _rail_reserved() -> float:
	if _rail == null or not _rail.visible:
		return 0.0
	var used: float = FramesetRail.used_width(_rail.size, _rail.row().size())
	if used <= _canvas.size.x - OVERLAY_W - 2.0 * OVERLAY_PAD:
		return 0.0
	return _rail.size.y + OVERLAY_PAD


## The author ticked a frameset. Lowered straight into the scope control, which is what
## switches the mode to `Pick` — the tile IS the chooser, so it never needs a mode press
## first (`FramesetRegionScope.toggle_frameset`).
func _on_rail_toggled(frameset_index: int) -> void:
	if _scope == null:
		return
	_scope.toggle_frameset(frameset_index)
	_refresh_rail_selection()


func _refresh_rail_selection() -> void:
	if _rail == null or _scope == null:
		return
	var sel: Dictionary = {}
	for m in _scope.selected_members():
		sel[int(m.get("frameset_index", -1))] = true
	_rail.set_selection(sel)


## Re-bind the rail's ROW from the scope's current region. Called on every bind and on every
## pin/hover change, because the row IS the region's framesets and a different region is a
## different row.
func _rebind_rail() -> void:
	if _rail == null or _scope == null or _effect_data == null:
		_place_rail()
		return
	var order: Array = RegionScope.order_framesets(_scope.region_framesets(), _strip_framesets)
	var sel: Dictionary = {}
	for m in _scope.selected_members():
		sel[int(m.get("frameset_index", -1))] = true
	# THE RAIL ALWAYS SHOWS THE REGION IT IS ABOUT (2026-08-21). It used to collapse a row of
	# one frameset to nothing — "a row of one is not a choice" — which was true about
	# TICKING and wrong about the rail. Measured, that hid it for 3636 of 6632 corpus regions
	# (54.8%), so its presence read as arbitrary: the same author gesture on two neighbouring
	# rects showed a strip of sprites or showed nothing, with the difference invisible.
	# Author: *"I think it only shows the thumbnails on the bottom if there are more than 1
	# frames referencing the rect - can we just always have it show? it makes it less
	# confusing."*
	#
	# It also cost more than it looked. 3361 of those regions (50.7% of ALL regions) have a
	# SINGLE member, and the member list is gated on `_members.size() > 1` — so the author saw
	# neither the rail nor the list, and nothing at all named the sprite the edit would
	# rewrite. A one-tile rail is not a chooser; it is the answer to "which sprite is this?",
	# which is the question the whole surface exists for.
	_rail.bind_row(_effect_data.framesets, order, sel, _canvas.display_texture(), _fs_idx)
	_place_rail()
	# THE RAIL REPLACES THE MEMBER LIST, it does not sit beside it. Both enumerate the same
	# region; the rail does it as pictures the author can tick, the list as `frameset 16 /
	# frame 0` rows they cannot. Keeping both spends the scarcest thing in this overlay —
	# height — on saying the weaker half twice.
	#
	# EXCEPT ON A ONE-TILE ROW, where the rail enumerates NOTHING: every member of the region
	# is inside that single frameset, so the tile stands for all of them and the list is the
	# only thing that can say there are several. That is 275 corpus regions (4.1%), of which
	# 68 have members that genuinely DISAGREE about a facet — mirrored, flipped, orientation —
	# and there the rows are not even repetition. Suppressing on a row of one is the only way
	# always-showing the rail could have LOST anything, so it does not.
	#
	# The line is drawn at one tile rather than at "tiles < members" deliberately: a 13-tile
	# row for 15 members already suppressed the list and always has. A row of ONE is different
	# in kind, not in degree — it enumerates zero of the choice, not most of it.
	if _scope != null:
		_scope.list_suppressed = _rail.visible and _rail.row().size() > 1
		_scope.list_max_height = SCOPE_H


## The `frameset` of each cell of the sequence on screen, in cell order. See `_strip_framesets`.
func set_strip_framesets(cells: Array) -> void:
	_strip_framesets = cells
	_rebind_rail()


func rail() -> Control:
	return _rail


## The facts, ON the port. A child of `_canvas`, which is a `Control` and NOT a Container:
## that is the fact the whole shape rests on, because it means nothing in here reaches this
## panel's `get_combined_minimum_size()` and therefore nothing in here can push the tab
## into the sequence player. Asserted, not assumed — the history of this file is minimums
## propagating somewhere nobody expected.
func _build_overlay() -> void:
	_overlay = PanelContainer.new()
	# PASS, so hover / zoom / pan reach the canvas THROUGH the overlay and the picture is
	# not dead under its own metadata. The buttons and the member list below keep the
	# default STOP and so still take their clicks.
	_overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	var sb := StyleBoxFlat.new()
	# Translucent on purpose: the texels underneath stay legible, so the overlay reads as
	# floating on the sheet instead of punching a hole in it.
	sb.bg_color = Color(0.07, 0.08, 0.11, 0.86)
	sb.border_color = Color(1.0, 1.0, 1.0, 0.15)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(6.0)
	_overlay.add_theme_stylebox_override("panel", sb)
	var theme := Theme.new()
	theme.default_font_size = OVERLAY_FONT_SIZE
	_overlay.theme = theme
	_canvas.add_child(_overlay)

	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_PASS
	vb.add_theme_constant_override("separation", 3)
	_overlay.add_child(vb)

	# THE WHOLE HEADER IS THE TOGGLE, which is the studio's own collapsible idiom
	# (`EffectKeyframeInspector._build_section`: a flat, left-aligned, `toggle_mode` Button
	# whose text is "▾  title" / "▸  title") and not a shape invented here.
	#
	# IT SHIPPED AS A 17px CHEVRON BESIDE A PLAIN CAPTION LABEL AND THAT WAS A DEFECT. The
	# author: *"it seems like I can close the but can't reopen it"* — a flat Button draws no
	# border, so folded, the only clickable thing in the corner was one glyph with nothing
	# marking it as a target, next to a caption that looked like the obvious place to click
	# and was inert. `⌃`/`⌄` (U+2303/2304) are also not glyphs this theme's font is known to
	# carry, where `▾`/`▸` are used in five places in this package already.
	#
	# A header that IS the button makes the target the full 232px row in BOTH states, which
	# is the property the guard asserts — the reachability question from dec. 11c arriving
	# on a third axis: present, visible, and still not hittable.
	_header_btn = Button.new()
	_header_btn.toggle_mode = true
	_header_btn.button_pressed = not _folded
	_header_btn.flat = true
	_header_btn.focus_mode = Control.FOCUS_NONE
	_header_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	# CLIPPED, and for the reason `EffectKeyframeInspector` records at its own header: a
	# Button's TEXT sets its minimum width. The header is the one thing in this overlay that
	# is NOT inside the width-absorbing scroll, so an un-clipped caption would bid straight
	# into the overlay's minimum and `OVERLAY_W` would stop being a ceiling — the same
	# defect the body's `SHOW_NEVER` exists to prevent, entering one control higher up.
	_header_btn.clip_text = true
	_header_btn.tooltip_text = "Show or hide the sheet's facts. The picture stays either way."
	_header_btn.toggled.connect(func(on: bool): set_folded(not on))
	vb.add_child(_header_btn)

	# Everything below the header scrolls, because the port's HEIGHT is the row's leftover
	# and this family has measured rows of 263. Without it a short row would clip the last
	# fact silently — which is the vertical half of the very defect the old side column's
	# scroll existed to prevent, and it survives the move.
	_overlay_scroll = ScrollContainer.new()
	# PASS here too, and it composes: a `ScrollContainer` only ACCEPTS a wheel event when
	# it actually has somewhere to scroll, so a wheel over a fully-visible overlay falls
	# through to the canvas's zoom and a wheel over an overflowing one scrolls the facts.
	_overlay_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	# SHOW_NEVER, NOT DISABLED, and the difference is the overlay's width ceiling.
	#
	# `SCROLL_MODE_DISABLED` folds the CONTENT'S minimum width into the ScrollContainer's
	# own, which folds into the overlay's — so one un-wrapped Label anywhere below (the
	# scope's blast-radius line, measured at ~250px) sets the overlay's width instead of
	# `OVERLAY_W` did. Caught by `_test_the_picture_is_actually_on_screen` at 315px.
	# `SHOW_NEVER` keeps the minimum at zero and hides the bar, so `OVERLAY_W` is a real
	# ceiling and a long fact can never widen the box; the children are still laid out at
	# the overlay's width, so the autowrapping ones still wrap to it.
	_overlay_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_overlay_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_overlay_scroll)

	_overlay_body = VBoxContainer.new()
	_overlay_body.mouse_filter = Control.MOUSE_FILTER_PASS
	_overlay_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_overlay_body.add_theme_constant_override("separation", 3)
	_overlay_scroll.add_child(_overlay_body)
	# Content changes (a bind with more facts, the scope appearing) move the overlay's
	# wanted height, and the place has to follow them rather than only the port's resize.
	_overlay_body.minimum_size_changed.connect(
		func(): call_deferred("_place_overlay"))

	# THE SCOPE IS THE TOP OF THE SCROLLING BODY, because it is the only thing in here that
	# has to be read BEFORE a gesture rather than during one (ADR-0099 dec. 5, ADR-0130
	# dec. 5). Measured on a 626x688 window: the tab's port gave the overlay 108 units, and
	# with the blast-radius sentence wrapping to two lines the scope TOGGLE — the control
	# that decides how many frames the next drag rewrites — sat below the fold.
	#
	# It does NOT push the actions down, because the actions are no longer in this box; see
	# `_build_actions`.
	_scope = RegionScope.new()
	_overlay_body.add_child(_scope)
	_scope.scope_changed.connect(func(m):
		scope_changed.emit(m)
		_refresh_rail_selection())

	# The ADR-0199 refusal, in place. A 4bpp sheet offers NEITHER direction of the round
	# trip — 58 of the 60 4bpp effects render through 3-7 per-frame sub-palettes, so a
	# flat RGBA export is itself the untruthful artifact. Stated here rather than shown
	# as dead buttons or deferred to the page.
	_refusal = Label.new()
	_refusal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_refusal.visible = false
	_overlay_body.add_child(_refusal)

	_facts_grid = GridContainer.new()
	_facts_grid.columns = 2
	_facts_grid.mouse_filter = Control.MOUSE_FILTER_PASS
	_facts_grid.add_theme_constant_override("h_separation", 6)
	_facts_grid.add_theme_constant_override("v_separation", 1)
	_overlay_body.add_child(_facts_grid)

	_build_actions(vb)
	_apply_fold()


## EXPORT / IMPORT, OUTSIDE THE SCROLL. A sibling of the `ScrollContainer`, last in the
## overlay's own VBox, so they are pinned to the overlay's bottom edge and are the one thing
## in here that a short port cannot scroll away.
##
## THEY USED TO BE FIRST IN THE BODY, which was `cbe359478`'s rule ("an overlay clamped to
## `OVERLAY_MAX_H_FRACTION` loses its LAST row first, so what may not be lost goes first")
## applied when they were the only thing in the box. Once the scope toggle arrived, first
## became a contest neither could win: whichever went second was below the fold on a short
## port, and the guard for the losing one reddened. Measured, a 520x150 probe: 96px of port,
## 27 of header, and the scope's two-line sentence plus its toggle row is 50 — there is no
## ordering of a scrolling list that shows both.
##
## Out of the scroll entirely, there is no contest. The `ScrollContainer` between them
## carries `SIZE_EXPAND_FILL` and a ~zero minimum, so it absorbs every pixel of the clamp
## while the header and this row keep theirs — and the overlay's combined minimum stays
## header + actions + padding, which is what lets `overlay_rect` shrink it at all.
func _build_actions(vb: VBoxContainer) -> void:
	_actions = HBoxContainer.new()
	_actions.mouse_filter = Control.MOUSE_FILTER_PASS
	vb.add_child(_actions)
	_export_btn = Button.new()
	_export_btn.text = "⭳ Export"
	_export_btn.tooltip_text = ("Write this sheet as a 32-bit RGBA .tga — the same bytes "
		+ "extract_effect_texture.lua produces.")
	_export_btn.pressed.connect(func(): action_requested.emit("texture_export"))
	_actions.add_child(_export_btn)
	_import_btn = Button.new()
	_import_btn.text = "⭱ Import"
	_import_btn.tooltip_text = ("Replace this sheet from a repainted RGBA .tga. Colours are "
		+ "matched into the existing palette (which never changes). Undoable (Ctrl+Z).")
	_import_btn.pressed.connect(func(): action_requested.emit("texture_import"))
	_actions.add_child(_import_btn)



## Whether the facts are folded away to the caption alone.
func is_folded() -> bool:
	return _folded


func set_folded(value: bool) -> void:
	_folded = value
	_apply_fold()
	_place_overlay()


func _apply_fold() -> void:
	if _header_btn == null:
		return
	# `set_pressed_no_signal`, because `set_folded` is reachable BOTH from the button's own
	# `toggled` and from callers (the guard, and any future keybinding). Writing
	# `button_pressed` here would re-enter through the signal on the second path.
	_header_btn.set_pressed_no_signal(not _folded)
	_header_btn.text = "%s  %s" % ["▸" if _folded else "▾", _caption_text]
	_overlay_scroll.visible = not _folded
	# Folded is "the sheet and nothing else" — the tiny box the ask names — so the actions
	# go with the facts. They come back only if the sheet is authorable at all.
	if _actions != null:
		_actions.visible = _actions_ok and not _folded


## PURE. Where a `want`-sized overlay goes in a `canvas_size` port: the bottom-right
## corner, one pad in, CLAMPED to the port on both axes.
##
## Pure because the two things that can go wrong here are both expressible with no window
## — the overlay hanging off a port shorter than its content (which is the reachability
## defect `cbe359478` fixed, arriving on the other axis), and the overlay eating a narrow
## port whole. The dashboard's body is compositor-chosen and this family has measured
## ports from 153px up, so neither is hypothetical and neither should need a screenshot.
static func overlay_rect(canvas_size: Vector2, want: Vector2) -> Rect2:
	var w: float = minf(want.x, maxf(0.0, canvas_size.x - 2.0 * OVERLAY_PAD))
	var h: float = minf(want.y, maxf(0.0, canvas_size.y - 2.0 * OVERLAY_PAD))
	# THE HEIGHT SHARE, applied after the port clamp and never to a FOLDED overlay: folded,
	# the caption row is the whole thing and 60% of a short port could cut it in half, which
	# would be an overlay that cannot be unfolded because its own button is gone.
	if want.y > canvas_size.y * OVERLAY_MAX_H_FRACTION:
		h = minf(h, maxf(0.0, canvas_size.y * OVERLAY_MAX_H_FRACTION))
	# THE ORIGIN IS CLAMPED TOO, and that is not belt-and-braces. On a port smaller than
	# the pad itself — which is a real state, not a hypothetical: the tab is built before
	# `_relayout` ever runs, so its first placement happens at a 0x0 canvas — the size
	# clamp above yields zero and `canvas_size - w - PAD` is then NEGATIVE, putting the
	# overlay one pad off the top-left corner. Caught by the guard's degenerate-port case.
	return Rect2(maxf(0.0, canvas_size.x - w - OVERLAY_PAD),
		maxf(0.0, canvas_size.y - h - OVERLAY_PAD), w, h)


## The height the overlay would LIKE, read off the live tree rather than counted.
##
## Read from `_overlay_body` and not from the `ScrollContainer` around it: a
## ScrollContainer's own minimum is ~zero by design (that is what makes it scroll), so
## asking the wrapper would place a 28px overlay over a 300px worth of facts and clip all
## of them. Folded, the body is invisible and contributes nothing — which is the fold.
func _wanted_overlay_size() -> Vector2:
	if _overlay == null:
		return Vector2.ZERO
	var pad: Vector2 = _overlay.get_theme_stylebox("panel").get_minimum_size()
	var vb: VBoxContainer = _overlay.get_child(0) as VBoxContainer
	var sep: float = float(vb.get_theme_constant("separation"))
	var h: float = pad.y + _header_btn.get_combined_minimum_size().y
	if not _folded:
		h += sep + _overlay_body.get_combined_minimum_size().y
		# The actions are a SIBLING of the scroll now, not content inside it, so their row
		# is height the overlay wants on top of the body rather than height the body already
		# counted. Missing this would place an overlay one row too short and clip the one
		# thing that was moved out here to be unclippable.
		if _actions != null and _actions.visible:
			h += sep + _actions.get_combined_minimum_size().y
	return Vector2(OVERLAY_W, h)


func _place_overlay() -> void:
	if _overlay == null or _canvas == null:
		return
	# The rail owns the bottom strip of the port, so the overlay is placed against a port
	# shortened by it. Not a clamp afterwards: the overlay is anchored to the BOTTOM, so
	# subtracting after the fact would move it without changing the height it was allowed.
	var r: Rect2 = overlay_rect(
		Vector2(_canvas.size.x, maxf(0.0, _canvas.size.y - _rail_reserved())),
		_wanted_overlay_size())
	_overlay.position = r.position
	_overlay.size = r.size


## Bind the sheet, and the frame IN CONTEXT if there is one (ADR-0130 dec. 4).
##
## `frame_index < 0` means there is no single frame to speak for — an effect-level or
## texture target. That binds the EMPTY dictionary, which is not a degraded state: it
## is the read-only whole-sheet view, because `FramesetCanvas._draw` paints the sheet
## and the coverage mask unconditionally and only then `if not _frame.is_empty()` draws
## the UV overlay. That view already existed and had no caller.
func bind_sheet(effect_data, frameset_index: int, frame_index: int) -> void:
	if _canvas == null:
		_build()
	_effect_data = effect_data
	_fs_idx = frameset_index
	_fr_idx = frame_index
	if effect_data == null:
		_title.text = "Texture — no effect loaded"
		_caption_text = "no effect"
		_apply_fold()
		_canvas.bind_frame(null, {})
		_place_overlay()
		return

	var frame: Dictionary = _resolve_frame(effect_data, frameset_index, frame_index)
	_canvas.bind_frame(effect_data.texture, frame)
	# ADR-0130 dec. 4b — every region the FRAMESET in context samples, outlined read-only.
	# Coverage dimming alone answered "which parts of the sheet does this group use" and
	# the author could not read it: "I can't get the yellow boxes showing which rect is
	# sampling what." Dimming is a property of the texels; an outline is a rectangle, and
	# a rectangle is what the question is about.
	_canvas.bind_group(_group_frames(effect_data, frameset_index))
	# ADR-0130 dec. 12 — and this one line is the whole of "the yellow boxes are editable on
	# the emitter page". The regions were always drawn; they were drawn DIM and unreachable
	# because dec. 4 had refused to bind a box where no single frame is in context.
	#
	# There is nothing to refuse. A frameset's frames each carry their own UV, so N regions
	# become N boxes, and the frames whose blocks are EXACTLY equal have already been folded
	# into one box by `group_regions` — which is what "perfectly overlapping frames move
	# together" means (ADR-0099 dec. 1+2). Partial overlap and containment stay separate
	# boxes, per that same decision's "not overlapping, not containing, not near".
	#
	# Live exactly when there is a frameset but no single frame: with a `frame` target the
	# ONE box is live already and these are its dim siblings, which must not compete with it.
	_canvas.group_live = frame.is_empty() and frameset_index >= 0
	# ADR-0098 dec. 5 coverage dimming, narrowed by ADR-0130 dec. 4a.
	#
	# With a FRAMESET in context the mask is built from that frameset ALONE, so the lit
	# texels are exactly the regions the sprite now on screen draws from. This is the
	# honest form of "watch the sheet as the animation plays": a shown sprite names N
	# rects (a frameset is a GROUP of frames, each with its own UV), and a coverage mask
	# can say N where a single UV box would have to pick one and lie about it.
	#
	# With nothing in context it falls back to the whole effect — which parts of the sheet
	# ANY frame addresses, so the dead sheet an author may paint freely is visible.
	if effect_data.texture != null:
		var size := Vector2i(effect_data.texture.get_width(), effect_data.texture.get_height())
		_canvas.bind_framesets(_coverage_framesets(effect_data, frameset_index), size)
	# `bind` KEEPS the scope unless the region's membership changed (ADR-0099 dec. 5e). This
	# call is the author's reported case — a thumbnail change re-binds the panel, and the
	# reset it used to do was how a narrowed scope silently became effect-wide again.
	if _scope != null:
		# With N live boxes there is no frame in context to scope, so the control follows the
		# HOVER instead (`_on_group_region_hovered`) and this bind is its resting state: the
		# sole region when the frameset samples only one — 90.5% of the corpus, where there
		# is nothing to disambiguate and the blast radius can be stated on arrival — and
		# otherwise nothing until the author points at a box.
		var seed_frame: int = frame_index
		var resting_regions: int = 0
		if _canvas.group_live:
			var regions: Array = _canvas.group_regions_bound()
			seed_frame = int(regions[0]["members"][0]) if regions.size() == 1 else -1
			# WHAT THE RESTING STATE IS ABOUT. Handed on so the control can say "5 regions
			# here — point at one" instead of "No region", which is what it said while five
			# draggable boxes sat on the sheet beside it.
			resting_regions = regions.size()
		_scope.bind(effect_data.framesets, frameset_index, seed_frame, resting_regions)
		# Inert when there is no region to scope, so the control never states a blast radius
		# for an edit that cannot be made. On the emitter page a region IS editable, so the
		# control is offered there whenever one is resolved (ADR-0130 dec. 5: the handles and
		# the control that states their blast radius ship together or not at all).
		# RESERVED WHENEVER THE HANDLES ARE LIVE, not only once a region is resolved. ADR-0130
		# dec. 5 pairs the handles with the control that states their blast radius, and a
		# control that appears when the pointer enters a box also RESIZES the overlay on a
		# mouse-move path — so the facts under it would jump as the author swept across the
		# sheet. It holds its height and its bind follows the hover instead.
		_scope.visible = (not frame.is_empty()) or _canvas.group_live
		# THE THIRTY-MEMBER CAP, AS A CEILING AND NOT A FLOOR. Stated from out here rather
		# than inside the scope control, which is shared: the list's `SIZE_EXPAND_FILL` is
		# right in a column that has height to give and wrong in an overlay, so the HOST
		# states the limit and the ItemList's own scrollbar does the rest.
		#
		# IT USED TO BE A FIXED `custom_minimum_size.y`, WHICH IS A FLOOR TOO. Measured on
		# E066 frameset 59 with a `frame` target: one member, one row, and 124px reserved —
		# ~200px of empty dark rectangle under a single line of text, inside the overlay
		# that exists to answer "a bunch of dead space". A ceiling caps the thirty-row case
		# without minting a void in the one-row case.
		_scope.list_max_height = SCOPE_H
		_scope.custom_minimum_size.y = 0.0
	_rebind_rail()

	_refresh_facts(effect_data, frame)


## The metadata on the picture. Reads `TextureProjector.facts` — the SAME static the
## Texture page reads, deliberately: two surfaces disagreeing about a sheet's depth or
## sub-palette would be a defect that looks like a rendering bug.
func _refresh_facts(effect_data, frame: Dictionary) -> void:
	var facts: Dictionary = TextureProjector.facts(effect_data)
	_title.text = "Texture — %d×%d · %s" % [facts["width"], facts["height"], facts["depth"]]
	# The caption is the folded state's entire content, so it says the two facts a glance
	# is usually after. The `Dimensions` and `Colour depth` ROWS are gone with it — a
	# 248px overlay cannot afford to print the same number twice.
	_caption_text = "%d×%d · %s" % [facts["width"], facts["height"], facts["depth"]]
	_apply_fold()

	for c in _facts_grid.get_children():
		c.queue_free()
	_add_fact("Sub-palette", str(facts["sub_palettes"]))
	_add_fact("Dual palette", str(facts["dual_palette"]))

	if _fs_idx >= 0:
		_add_fact("Frameset", "%d — %d frame%s on %d region%s" % [_fs_idx,
			_group_frames(effect_data, _fs_idx).size(),
			"" if _group_frames(effect_data, _fs_idx).size() == 1 else "s",
			_canvas.group_region_count(),
			"" if _canvas.group_region_count() == 1 else "s"])
	if frame.is_empty():
		# "outlined" was true under dec. 4b and is now a lie: the regions are LIVE BOXES
		# (dec. 12), so the row that tells the author what they are looking at has to say
		# they can be dragged. Naming the count here too, because "each" only means
		# something once you know how many there are.
		var n: int = _canvas.group_region_count()
		var text := "none in context — whole sheet"
		if _fs_idx >= 0 and _canvas.group_live:
			# SHORT, because the scope control now sits directly above this and says what a
			# region edit reaches ("⚠ An edit here changes 6 frames — 1 in this frameset,
			# 5 in framesets not shown"). This row used to carry that lesson too, in
			# different words, three lines away from the list that enumerates it — which is
			# how an author ends up asking which of the two the list belongs to.
			text = "none — drag any of the %d region%s" % [n, "" if n == 1 else "s"]
		elif _fs_idx >= 0:
			text = "none in context — the outlined regions are this frameset's"
		_add_fact("Frame", text)
	else:
		var block: Rect2i = Canvas.normalised_block(frame.get("uv", {}))
		_add_fact("Frame", "frameset %d / frame %d" % [_fs_idx, _fr_idx])
		_add_fact("UV rect", "%d,%d · %d×%d" % [
			block.position.x, block.position.y, block.size.x, block.size.y])
		# NO "⚠ shared by N frames" ROW HERE. It is the same number the scope control three
		# lines below states and then enumerates ("⚠ An edit here changes 6 frames…"), and
		# a 248px box that prints one fact twice in two vocabularies is the reason the
		# author could not tell which of them the member list belonged to. The warning
		# moved INTO the scope's summary rather than being dropped; `SequenceFocusBlock`
		# keeps its own copy, where there is no scope control to carry it (ADR-0099 dec. 5
		# — the surfaces that cannot edit the region still have to state the fan-out).
		# The scope is always visible on this branch: `_scope.visible` is true whenever a
		# frame is in context.

	var verdict: Dictionary = TextureChannel.authorable(effect_data.framesets)
	var ok: bool = bool(verdict.get("ok", false))
	_actions_ok = ok
	_actions.visible = ok and not _folded
	_refusal.visible = not ok
	if not ok:
		_refusal.text = "Not replaceable — %s" % str(verdict.get("reason", ""))
	_place_overlay()


func _add_fact(name: String, value: String) -> void:
	var l := Label.new()
	l.text = name
	_facts_grid.add_child(l)
	var v := Label.new()
	v.text = value
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_facts_grid.add_child(v)


## The live-group region under the cursor changed — re-point the scope control at it, so
## the member count the author reads is the one the press they are about to make will edit.
## ADR-0099 dec. 5 requires the count to be stated BEFORE the drag; on a surface with N
## boxes that is only expressible by following the pointer.
##
## Rebinding KEEPS the scope's mode (ADR-0099 dec. 5e). dec. 5's original reset was argued
## from exactly this caller — moving between boxes is a mouse-move — and 5e reverses it for
## the same fact read the other way: a scope that resets on a mouse-move cannot be set at
## all, which is what ADR-0130 dec. 12f had already concluded when it pinned the region. A
## hand-built subset still degrades here, because these ARE different members.
func _on_group_region_hovered(member_frame_index: int) -> void:
	if _scope == null or _effect_data == null or _fs_idx < 0:
		return
	if not _canvas.group_live:
		return
	# A single-region frameset keeps its resting bind: the pointer leaving the box does not
	# make its blast radius less true, and blanking the control as the mouse drifts off
	# would flicker the one number the author is trying to read.
	if member_frame_index < 0 and _canvas.group_region_count() == 1:
		return
	# The resting count rides along: the pointer LEAVING every box (`member_frame_index`
	# < 0 on a multi-region frameset) is the state that used to print "No region", and it
	# is reachable on every mouse-move off a box, not only on arrival.
	_scope.bind(_effect_data.framesets, _fs_idx, member_frame_index,
		_canvas.group_region_count())
	_rebind_rail()
	# The FACTS are deliberately not rebuilt here. They would have to call the hovered region
	# "frameset N / frame M", and a region is not a frame — that label is the ADR-0100 defect
	# in miniature, naming one member of a set with nothing saying the others exist. The
	# scope control beside it already lists the members and states the count, which is what
	# dec. 5 actually asks for. It also avoids tearing down and rebuilding a Label grid on a
	# mouse-move path.


## The author PINNED a region by clicking it, or released the pin. Same lowering as the
## hover — the scope binds to a representative member — and deliberately the same handler
## shape, because a pin and a hover answer the identical question ("which region is the
## panel about") and differ only in what makes the answer change.
##
## A RELEASE (`-1`) DOES NOT BLANK THE CONTROL. Un-pinning means the pointer speaks again,
## so the scope re-resolves from wherever the pointer already is — blanking it would flash
## "5 regions here — point at one" while the author is pointing at one.
func _on_group_region_locked(member_frame_index: int) -> void:
	if _scope == null or _effect_data == null or _fs_idx < 0:
		return
	var member: int = member_frame_index
	if member < 0:
		member = _canvas.hovered_member()
	_scope.bind(_effect_data.framesets, _fs_idx, member, _canvas.group_region_count())
	_rebind_rail()
	_refresh_facts(_effect_data, _resolve_frame(_effect_data, _fs_idx, _fr_idx))


func _on_hover(payload: Dictionary) -> void:
	if _readout == null:
		return
	if payload.is_empty():
		_readout.text = ""
		return
	_readout.text = str(payload.get("text", ""))


static func _resolve_frame(effect_data, fs_idx: int, fr_idx: int) -> Dictionary:
	if fs_idx < 0 or fr_idx < 0 or not (effect_data.framesets is Array):
		return {}
	if fs_idx >= effect_data.framesets.size():
		return {}
	var fs = effect_data.framesets[fs_idx]
	if not (fs is Dictionary):
		return {}
	var frames: Array = fs.get("frames", [])
	if fr_idx >= frames.size() or not (frames[fr_idx] is Dictionary):
		return {}
	return frames[fr_idx]


## The region the scope control currently points at — the page needs this to lower a drag.
func scope_members() -> Array:
	return [] if _scope == null else _scope.members()


## The frames of the frameset in context, or none when there is no frameset in context.
## A `frame` target passes its own frameset, so the sibling regions it shares the sheet
## with are outlined around the one box that is actually draggable.
static func _group_frames(effect_data, frameset_index: int) -> Array:
	if frameset_index < 0 or not (effect_data.framesets is Array):
		return []
	if frameset_index >= effect_data.framesets.size():
		return []
	var fs = effect_data.framesets[frameset_index]
	return [] if not (fs is Dictionary) else fs.get("frames", [])


## The framesets the coverage mask is built from (ADR-0130 dec. 4a): the one in context
## if there is one, else the whole effect. A one-element array, NOT a filtered copy of the
## frames — `coverage_mask` already walks whatever array it is handed.
static func _coverage_framesets(effect_data, frameset_index: int) -> Array:
	if frameset_index < 0 or not (effect_data.framesets is Array):
		return effect_data.framesets
	if frameset_index >= effect_data.framesets.size():
		return effect_data.framesets
	return [effect_data.framesets[frameset_index]]


## The address this panel ACTUALLY bound, stamped at bind rather than re-derived by the
## page from `_nav`. ADR-0100's amendment is the reason: `ref.index` means a different
## thing per target kind, and a wrong bind decodes a real rect and draws a real box with
## nothing on screen saying it is the wrong one.
func bound_frameset() -> int:
	return _fs_idx


func bound_frame() -> int:
	return _fr_idx


## The scope control's explicit ticks, for the page's drag lowering. Empty means "the
## scope is not narrowed", which the page reads as the whole region (ADR-0099 dec. 5's
## default is ALL, deliberately).
func selected_members() -> Array:
	return [] if _scope == null else _scope.selected_members()


func region_scope():
	return _scope


func canvas():
	return _canvas


## The facts overlay, for the guards: its rect against the sheet's, and its buttons'
## rects against the port's bottom edge.
func overlay():
	return _overlay


## The header toggle, for the guard: its RECT is the assertion, not its existence.
func fold_toggle() -> Button:
	return _header_btn


func export_button() -> Button:
	return _export_btn


func import_button() -> Button:
	return _import_btn
