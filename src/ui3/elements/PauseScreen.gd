class_name PauseScreen
extends CanvasLayer
## THE MODAL PAUSE — Esc, the stop that is not a tactical stop
## (`docs/context/41-battle-mode-and-handback.md`).
##
## A scrim, the word PAUSED, and the way out. Extracted from `GambitBattle` when
## `NavigatorMain` grew the same state, and extracted the way [StopBadge] was and for the
## same reason (ADR-0265 dec. 4): what crosses is the SEAT — a CanvasLayer above the badge,
## a darkened field, a title and a hint — and [b]the policy is the host's[/b]. What a pause
## freezes, what it restores on close, and what refuses to open one are questions about that
## host's battle, and a screen that tried to answer them would need the host's combat flag,
## its director and its Formation-screen claims handed to it one accessor at a time.
##
## [b]It darkens rather than hides.[/b] A pause you cannot read the field through is worse
## than no pause: the whole point of stopping is to look. The scrim is a flat `ColorRect` and
## not a shader for exactly that reason.
##
## [b]It states its exit.[/b] A modal with no stated way out is how a pause becomes a
## lock-out, which `GambitBattle` shipped once already (ADR-0261). The hint is a `mount()`
## argument because the key differs by host in principle even where it does not in fact.
##
## 🔴 NOT a `Focus` participant yet. The host's own `_unhandled_input` keeps an early branch
## that swallows everything but the closing key while this is up, which is the hand-rolled
## shape ADR-0177 exists to replace — but converting it means the screen must carry the
## callback that closes it, and that is a change to both hosts' input grammar rather than to
## this seat. Listed here so the next conversion can find it.

## The scrim, the title and the hint. PUBLIC for the same reason [member StopBadge.label] is:
## a test asserting only on the host's predicate can be right about a screen nobody mounted.
var scrim: ColorRect = null
var title: Label = null
var hint: Label = null


## Mount a pause screen over `host`, hidden. Owned by the host: a child, and it dies with it.
##
## Built HERE and not in `_ready`, so a host that mounts before it is itself in the tree still
## gets a screen it can raise — `_ready` on a child of an out-of-tree parent is DEFERRED until
## the parent enters, and a screen whose labels are null for that stretch is indistinguishable
## from one that refused to appear.
static func mount(host: Node, exit_hint: String = "Esc to resume") -> PauseScreen:
	var screen := PauseScreen.new()
	screen.name = "PauseScreenLayer"
	# Above [StopBadge]'s layer 10: this screen is the thing that replaces the badge.
	screen.layer = 20
	screen._build(exit_hint)
	screen.visible = false
	host.add_child(screen)
	return screen


func _build(exit_hint: String) -> void:
	var root := Control.new()
	root.name = "PauseScreen"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	scrim = ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = Color(0.0, 0.0, 0.05, 0.62)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(scrim)

	title = _outlined_label("PausedTitle", "PAUSED", 56, 8, Color(1.0, 1.0, 1.0))
	root.add_child(title)

	hint = _outlined_label("PausedHint", exit_hint, 18, 6, Color(0.85, 0.85, 0.9))
	# Clear of the 56 px title rather than tucked under it: the offset shifts the whole rect,
	# and a centred label in a rect shifted by N sits N/2 lower — so this is ~60 px of real
	# separation.
	hint.offset_top = 120.0
	root.add_child(hint)


func _outlined_label(node_name: String, text: String, size: int, outline: int,
		color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Outlined rather than boxed: the battlefield behind the scrim is any colour at all.
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	label.add_theme_constant_override("outline_size", outline)
	label.add_theme_font_size_override("font_size", size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Is the screen up? THE question every other input owner on a host has to be able to ask,
## which is why it is a method here and not a flag each of them keeps.
func is_open() -> bool:
	return visible


func open() -> void:
	visible = true


func close() -> void:
	visible = false


## The exit key, if a host wants to say a different one. The screen is the only place the
## player is told, so a host that changes the key must change this too.
func set_exit_hint(text: String) -> void:
	if hint != null and is_instance_valid(hint):
		hint.text = text
