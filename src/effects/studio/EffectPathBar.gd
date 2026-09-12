extends PanelContainer
## The Effect Studio **path bar** — the drill-down trail, promoted out of the inspector's
## 6-column grid into a full-width strip of its own above the inspector row.
##
## The nav STACK it renders (`EffectStudioPage._nav`, ADR-0073) is unchanged; only the
## presentation moves. As header rows the trail was indistinguishable from the target's
## own label/value pairs and it WRAPPED — measured at depth 4, the trail took one and a
## bit grid lines and the target's own rows started mid-line. As a strip it reads as
## chrome, it can't wrap, and it costs the inspector's declared `content_width()` nothing.
##
## Three things it shows that the header rows did not:
##   * the CURRENT target, marked `▸` and NOT a link — a trail that stops at the parent
##     doesn't read as "where am I";
##   * the effect itself as a dim, non-navigable root (there is no effect target kind);
##   * a `‹` step-back affordance, the visible half of Alt+Left.
##
## Always visible while an effect is loaded, including the empty inspection (just `E019`)
## and depth 1: conditional chrome re-flows the inspector, the right column, the frames
## bar and the channel scroll on the single most common gesture, and `Alt+Left` wants an
## affordance you can see BEFORE you are lost.
##
## Pure Control, web/WASM-safe. No `class_name` (ADR-0004); preloaded by path like the
## other effect-studio scripts.

## A crumb was clicked: step back / re-enter at that target. The page routes it straight
## into `_navigate_to`, which already truncates to an ancestor.
signal navigate_requested(target: Dictionary)

## `‹` was pressed — step back exactly one level. Distinct from `navigate_requested` so
## the page owns "one level" (the bar does not hold the stack).
signal back_requested

## The row's declared FLOOR, not its height — see `bar_height()`. A Container cannot
## shrink below its combined minimum, so a hard constant here would be a number the bar
## then overflowed, silently overlapping the inspector under it.
const BAR_H: float = 26.0

const FONT_SIZE: int = 12

## Past this depth the middle is elided to `…`, keeping the root and the last two. The
## deepest real chains are 5-6 (`span → emitter → sequence → frameset → frame → texture`).
const ELIDE_OVER: int = 4

const COL_BG := Color(0.11, 0.12, 0.16)
const COL_ROOT := Color(0.50, 0.55, 0.66)     # the effect id — context, not a link
const COL_LINK := Color(0.55, 0.78, 1.00)     # matches the inspector's link colour
const COL_CURRENT := Color(0.90, 0.93, 0.98)  # where you are — bright, not clickable
const COL_SEP := Color(0.38, 0.42, 0.52)

const MARK_CURRENT := "▸ "

var _row: HBoxContainer
var _back: Button
var _root: Label
## The live crumb buttons, in path order, for the tests and for `crumb_buttons()`.
var _crumbs: Array = []
## The `…` button standing in for the elided middle, or null when nothing is elided.
var _elided: MenuButton = null
## The targets that button offers, in path order.
var _elided_targets: Array = []


## The height this bar actually needs — the floor, or its live combined minimum when the
## theme's font and button padding want more (measured: 35 at the dev theme, against a
## 26 floor). The peer of the inspector's `content_height()`, and it exists for the same
## reason: a declared number that UNDER-reports puts chrome on top of the panel below it.
func bar_height() -> float:
	return maxf(BAR_H, get_combined_minimum_size().y)


func _ready() -> void:
	custom_minimum_size.y = BAR_H
	var bg := StyleBoxFlat.new()
	bg.bg_color = COL_BG
	bg.content_margin_left = 6.0
	bg.content_margin_right = 6.0
	bg.content_margin_top = 2.0
	bg.content_margin_bottom = 2.0
	add_theme_stylebox_override("panel", bg)

	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 2)
	add_child(_row)

	_back = Button.new()
	_back.text = "‹"
	_back.flat = true
	_back.focus_mode = Control.FOCUS_NONE
	_back.tooltip_text = "Step back one level (Alt+Left)"
	_back.add_theme_font_size_override("font_size", FONT_SIZE)
	_back.disabled = true
	_back.pressed.connect(func(): back_requested.emit())
	_row.add_child(_back)

	_root = Label.new()
	_root.add_theme_color_override("font_color", COL_ROOT)
	_root.add_theme_font_size_override("font_size", FONT_SIZE)
	_row.add_child(_root)


## Re-render the trail. `effect_label` names the document (`"E019"`, or "" for none);
## `crumbs` is the nav stack projected to `[{label, target}, …]` root-first, with the
## LAST entry the current target — the bar owns the "the last one is where you are"
## rule so no caller can render a trail that stops at the parent.
func set_path(effect_label: String, crumbs: Array) -> void:
	_clear()
	_root.text = effect_label
	_root.visible = effect_label != ""
	_back.disabled = crumbs.size() < 2
	for entry in _visible_entries(crumbs):
		if entry is String:            # the elision stand-in
			_row.add_child(_make_elided(crumbs))
			continue
		_row.add_child(_separator())
		var i: int = int(entry)
		if i == crumbs.size() - 1:
			_row.add_child(_current_cell(crumbs[i]))
		else:
			_row.add_child(_crumb_button(crumbs[i]))


## Which crumbs actually render, as indices into `crumbs` — with the literal `"…"`
## standing where the middle was dropped. Pure: the elision rule is guarded without a
## scene. Past `ELIDE_OVER` keep the root and the last two; everything between goes into
## the `…` menu, so no crumb is ever unreachable, only folded.
static func visible_indices(count: int) -> Array:
	if count <= ELIDE_OVER:
		var all: Array = []
		for i in range(count):
			all.append(i)
		return all
	return [0, "…", count - 2, count - 1]


func _visible_entries(crumbs: Array) -> Array:
	return visible_indices(crumbs.size())


## The crumbs the `…` menu offers — the ones `visible_indices` dropped, in path order.
static func elided_indices(count: int) -> Array:
	var out: Array = []
	if count <= ELIDE_OVER:
		return out
	for i in range(1, count - 2):
		out.append(i)
	return out


func _make_elided(crumbs: Array) -> Control:
	var b := MenuButton.new()
	b.text = "…"
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "The elided middle of the path"
	b.add_theme_font_size_override("font_size", FONT_SIZE)
	var popup := b.get_popup()
	_elided_targets.clear()
	for i in elided_indices(crumbs.size()):
		var c: Dictionary = crumbs[i]
		popup.add_item(str(c.get("label", "")))
		_elided_targets.append(c.get("target", {}))
	popup.id_pressed.connect(func(id: int):
		if id >= 0 and id < _elided_targets.size():
			navigate_requested.emit(_elided_targets[id]))
	_elided = b
	# A separator BEFORE the ellipsis too, so the trail reads `E019 › … › sequence 0`.
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.add_child(_separator())
	box.add_child(b)
	return box


func _crumb_button(crumb: Dictionary) -> Button:
	var b := Button.new()
	b.text = str(crumb.get("label", ""))
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_color_override("font_color", COL_LINK)
	b.add_theme_font_size_override("font_size", FONT_SIZE)
	var target: Dictionary = crumb.get("target", {})
	b.pressed.connect(func(): navigate_requested.emit(target))
	_crumbs.append(b)
	return b


## The current target: marked and INERT. A Label, not a disabled Button — a disabled
## button reads as "this used to work", where the point is that you are already here.
func _current_cell(crumb: Dictionary) -> Label:
	var l := Label.new()
	l.text = MARK_CURRENT + str(crumb.get("label", ""))
	l.add_theme_color_override("font_color", COL_CURRENT)
	l.add_theme_font_size_override("font_size", FONT_SIZE)
	return l


func _separator() -> Label:
	var l := Label.new()
	l.text = "›"
	l.add_theme_color_override("font_color", COL_SEP)
	l.add_theme_font_size_override("font_size", FONT_SIZE)
	return l


func _clear() -> void:
	_crumbs.clear()
	_elided = null
	_elided_targets.clear()
	if _row == null:
		return
	for child in _row.get_children():
		if child == _back or child == _root:
			continue
		_row.remove_child(child)
		child.queue_free()


# --- test seams -----------------------------------------------------------

func back_button() -> Button:
	return _back


func crumb_buttons() -> Array:
	return _crumbs


func elided_button() -> MenuButton:
	return _elided


func elided_targets() -> Array:
	return _elided_targets


## The rendered trail as one string, for assertions and for the log — e.g.
## `"E019 › emitter 0 › ▸ sequence 0"`.
func path_text() -> String:
	var parts: Array = []
	for child in _row.get_children():
		if child == _back:
			continue
		parts.append(_text_of(child))
	var joined := " ".join(PackedStringArray(parts)).strip_edges()
	return joined


static func _text_of(control: Control) -> String:
	if control is Label:
		return control.text
	if control is Button:
		return control.text
	var out: Array = []
	for c in control.get_children():
		if c is Control:
			out.append(_text_of(c))
	return " ".join(PackedStringArray(out))
