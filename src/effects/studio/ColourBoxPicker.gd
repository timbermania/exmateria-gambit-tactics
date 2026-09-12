extends ColorPicker
## The colour-authoring grid (ADR-0089 colour-keyframe amendment, decision 4 — editing-UX
## amendment 2026-08-13, authoring-space amendment 2026-08-21). The FULL inline colour grid
## (the X/Y HSV square with every colour): it lives INLINE inside a collapsible fold (the
## inspector owns the fold, default expanded), so you expand once and author without a popup
## click per edit. Was a swatch-opens-popup button; inline reads fine in the wide inspector
## column.
##
## IT AUTHORS THE CURVE (the 2026-08-21 amendment). The picked RGB **is** the three colour-curve
## values, 0..255 → 0..1 per channel; the emitter's representative sprite texel `S` is not in
## the write path at all. Picking white writes curve (1,1,1) — the sprite unmodified, the
## brightest ALBEDO the multiply can produce — and picking black writes black, so *"reach every
## [0,0,0] to [255,255,255]"* is literally true of this control.
##
## What that replaced, and why: the picker used to author in MUXED space (you picked the OUTPUT
## colour `T`, the tool stored `clamp_to_box(T, S)` and compiled `T ⊘ S`). Two things were wrong
## with it from the author's seat, and only the first was ever visible as a limit:
##   • the range. Censused over 3213 corpus colour emitters, 97.5% have NO channel whose byte
##     slider can hold 255 — its ceiling is `round(S.k*255)` — and the worst channel's p10 is
##     57 distinct values out of 256. The author's *"I am not able to reach every [0,0,0] to
##     [255,255,255]"* was a true statement about this widget.
##   • the FIGHT. `EffectStudioPage._update_colour_picker_panel` re-seeds on every drag frame,
##     and the seed was the clamped colour — so each mouse-move toward a bright colour was
##     immediately overwritten with the darker achieved one and the grid crawled back under the
##     cursor. That is the whole of *"the color picker really just isn't working"*.
##
## `S` HAS NOT STOPPED MATTERING — it stopped being applied SILENTLY. A multiply can only scale
## a channel, never add one the sprite lacks, so the render is still bounded by `S`; the widget
## now REPORTS that bound instead of enforcing it, via `renders_as()` (the swatch's colour muxed
## through S — what the particle will actually look like) and `dead_channels()` (which existed
## for exactly this and had no caller). The ribbon still muxes, so it still shows what renders.
##
## `curve_picked` fans the picked colour clamped to the unit cube only. Seeding installs the
## current curve colour without firing a pick. `ColourBoxPicker` keeps its name for the file's
## sake; the box is now something it describes, not something it imposes.
## No `class_name` (ADR-0004) — preloaded by path.

signal curve_picked(curve: Color)

const ColourMux = preload("res://src/effects/studio/ColourMux.gd")

var _gamut: Color = Color.WHITE
var _seeding: bool = false


func _init() -> void:
	edit_alpha = false  # colour authoring is opaque RGB — transparency is a separate flag
	# Trim the inline grid to the essentials — the HSV square + sliders, no preset/sampler clutter.
	presets_visible = false
	sampler_visible = false
	can_add_swatches = false
	color_modes_visible = false
	color_changed.connect(_on_user_color_changed)


## Install the emitter's representative texel `s`. It bounds the RENDER, not the pick: it is what
## `renders_as` muxes through and what `dead_channels` reports.
func set_gamut(s: Color) -> void:
	_gamut = Color(s.r, s.g, s.b, 1.0)


## The current gamut (representative texel). Test seam.
func gamut() -> Color:
	return _gamut


## Seed the swatch from the live CURVE colour. Fires NO pick, and — the point of the amendment —
## clamps nothing, so a re-seed during a drag installs exactly what the author last picked
## instead of pulling the grid back down to `S`.
func seed_curve(curve: Color) -> void:
	_seeding = true
	color = ColourMux.clamp_unit(curve)
	_seeding = false


## Apply a pick: fan the picked curve colour and return it.
func pick(curve: Color) -> Color:
	var c: Color = ColourMux.clamp_unit(curve)
	curve_picked.emit(c)
	return c


## THE COLOUR A COMMIT WOULD WRITE — the swatch's current value as a curve triple, exactly what
## `pick` would have fanned. Needed because a pick on an INTERPOLATED age authors nothing
## (author, 2026-08-20: the ⬥ button is the second step), so the button has to be able to ask the
## picker what it is showing rather than remembering the last signal.
func picked() -> Color:
	return ColourMux.clamp_unit(color)


## What the particle will RENDER for the swatch's current value: `S ⊙ curve`, the same multiply
## the shader and the ribbon do. Shown beside the swatch — the pair the old design collapsed into
## one silently-clamped colour.
func renders_as() -> Color:
	return ColourMux.mux(picked(), _gamut)


## Which channels are dead (S.k == 0) — the sprite has no light there, so no curve value can
## render it. Reported, not enforced: the curve is still authored and still saved, it simply
## multiplies by zero. 4.2% of corpus colour emitters have at least one.
func dead_channels() -> Dictionary:
	return {
		"r": 1 if _gamut.r <= 0.0 else 0,
		"g": 1 if _gamut.g <= 0.0 else 0,
		"b": 1 if _gamut.b <= 0.0 else 0,
	}


## The dead channels as a SHORT tag for the renders-as row ("no G", "no R/B"), or "" when the
## sprite lights all three. Short because the row lives in a 298px column and must not wrap:
## a wrapping label's minimum height is a function of its width, which put the panel's header
## floor at 228px and cost the ⬥ button its place above the fold.
func dead_channel_tag() -> String:
	var names := _dead_names()
	return "" if names.is_empty() else "no %s" % "/".join(names)


## The same fact as a sentence, for the row's tooltip. This pair is `dead_channels` finally
## having a caller: the limit is stated on screen instead of being applied behind the pick.
func dead_channel_note() -> String:
	var names := _dead_names()
	if names.is_empty():
		return ""
	return ("The sprite has no %s, so that channel renders black whatever you pick. "
		+ "The curve still holds your value — a multiply can scale a channel, never add one."
		) % "/".join(names)


func _dead_names() -> Array:
	var dead := dead_channels()
	var names: Array = []
	for k in ["r", "g", "b"]:
		if int(dead[k]) == 1:
			names.append(k.to_upper())
	return names


func _on_user_color_changed(c: Color) -> void:
	if _seeding:
		return
	pick(c)
