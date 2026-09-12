class_name StopBadge
extends CanvasLayer
## The one line of chrome that says WHICH stop the world is in (ADR-0265).
##
## A motionless battlefield is pixel-identical in every state that produces one —
## deployment, a pause, an open turn, a stopped clock — and the keys that end them
## are not the same key. A player with no badge has to guess, and on `GambitBattle`
## guessing wrong on ○ used to spend a turn. A correct binding the player cannot
## SEE is still an unusable binding.
##
## Extracted from `GambitBattle` when `NavigatorMain` grew the same four states
## (ADR-0265). What came across is the SEAT — a CanvasLayer above everything, an
## outlined label on the bottom edge — and nothing else: [b]the text is the host's[/b].
## Each host's states, and the keys that end them, are its own vocabulary, and a badge
## that tried to derive the sentence would need the host's steerability set, its
## director and its pause model handed to it one accessor at a time.
##
## A [CanvasLayer] and not a [UIWindowHost] seat: the turn-queue forecast strip already
## owns the camera's top edge in 3D screen space, and a second occupant there would have
## to negotiate for it. This is one label of diagnostic chrome and is honest about being
## that.

## The label itself. PUBLIC, because `GambitBattleTest` arm 4d deliberately asserts on the
## NODE and not only on the string its host's pure predicate returns — a pure predicate can
## be right about a badge nobody mounted.
var label: Label = null


## Mount a badge over `host`. Owned by the host: it is a child, and it dies with it.
##
## The label is built HERE and not in `_ready`, so a host that mounts before it is itself in
## the tree still gets a badge it can write to — `_ready` on a child of an out-of-tree parent
## is DEFERRED until the parent enters, and a badge whose label is null for that stretch reads
## exactly like a badge that refused to say anything.
static func mount(host: Node) -> StopBadge:
	var badge := StopBadge.new()
	badge.name = "StopBadgeLayer"
	# Above the forecast strip's world-space seat by construction — a CanvasLayer draws over
	# the 3D viewport regardless of what is parked in front of the camera.
	badge.layer = 10
	badge._build()
	host.add_child(badge)
	return badge


func _build() -> void:
	label = Label.new()
	label.name = "StopBadge"
	# Bottom-centre. The top belongs to the turn queue and the middle to the battlefield; this
	# is the one edge nothing else on either host claims.
	label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	label.offset_top = -64.0
	label.offset_bottom = -24.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Outlined rather than boxed: the battlefield behind it is any colour at all, and an
	# outline is legible over all of them without painting a panel over the map.
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_font_size_override("font_size", 20)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.visible = false
	add_child(label)


## Show `text`, or hide the badge entirely when it is `""`.
##
## Idempotent and cheap, because both hosts POLL it once a frame rather than driving it off an
## edge: `combat_active` has four writers on `GambitBattle` alone — its stop toggle, the
## Formation screen's pause hook, `TurnDirector._resume` and the director's own freeze — and a
## badge wired to a subset of them is a badge that lies in exactly the states nobody tested.
## One string compare a frame buys immunity to the next writer somebody adds.
func show_text(text: String) -> void:
	if label == null:
		return
	if text == label.text and label.visible == (text != ""):
		return
	label.text = text
	label.visible = text != ""


## What the badge is saying right now, for a test that would rather not read a pixel.
func shown_text() -> String:
	return label.text if label != null and label.visible else ""
