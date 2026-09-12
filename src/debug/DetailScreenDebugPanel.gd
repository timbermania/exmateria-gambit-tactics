class_name DetailScreenDebugPanel
extends BaseDebugPanel
## F3 → Designer tab: live placement calibration for the unit-DETAIL / Status screen
## (FORMATION_SCREEN.md §15) — the screen the roster ○-press opens. Dials in the top-left
## corner + size of every window, box-open aperture, title tab and column band against the
## PSX oracle WITHOUT editing a constant and relaunching (the §15.x round-by-round pain).
##
## A VIEW, not an owner (ADR-0068 decision 12): DetailScene owns each `detail.*` slug —
## its `_bind_detail_tunables` binds the matching `static var` and rebuilds the settled
## lower panel on a scrub. This panel only groups TuneField rows and seeds each row's
## default from the class static var (instance-free, since DetailScene is created per-open),
## so the rows are live even before the detail screen has been opened.

const TuneField = preload("res://src/debug/TuneField.gd")
# Untyped so `.get(<dynamic prop>)` reads a static var off the class object (the typed
# `class_name DetailScene` form rejects Object.get at parse time — needs an instance).
const _DS: Object = preload("res://src/ui3/detail/DetailScene.gd")

const _POS := {"min": -64.0, "max": 320.0, "step": 1.0}    # top-left corner (display px)
const _SIZE := {"min": 0.0, "max": 320.0, "step": 1.0}     # frame width/height (display px)
const _NUDGE := {"min": -32.0, "max": 32.0, "step": 0.5}   # whole-panel align nudge
const _EDGE := {"min": 0.0, "max": 256.0, "step": 1.0}     # column-band / band-y edge (display px)


func setup() -> void:
	panel_title = "Detail / Status Screen"
	panel_category = Category.DESIGNER
	_build_ui()


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(340, 0)
	add_child(root)

	# One FOLD section per target game panel (ADR-0035 dec. 6): folded by default, so the
	# section titles read as a table of contents over the ~40+ rows.
	var stats := add_fold_section(root, "Stats band  (Move/Jump/… row)")
	_rect(stats, "frame", "STATS_FRAME")
	_rect(stats, "aperture", "STATS_CONTAINER")
	_vec2(stats, "panel align nudge", "STATS_PANEL_NUDGE", _NUDGE)
	_vec2(stats, "compare/delta offset", "STATS_DELTA_NUDGE", _NUDGE)   # fg panel; visible only in-picker preview
	_vec2(stats, "weapon legend (sword/rod)", "WEAPON_ICON_POS")
	# Value columns (§15.18): Move/Jump/Speed left edge, Weap.Power run left edge, AT right edge.
	_scalar(stats, "Move/Jump/Speed value X", "MJS_VALUE_X")
	_scalar(stats, "Weap.Power value X", "WP_VALUE_X")
	_scalar(stats, "AT value left X", "AT_VAL_X")

	var lower := add_fold_section(root, "Lower panel  (Eqp + Ability, joint)")
	_rect(lower, "frame", "LOWER_FRAME")
	_rect(lower, "aperture", "OPEN_CONTAINER")

	var equip := add_fold_section(root, "Equip sub-screen frame")
	_rect(equip, "frame", "LOWER_FRAME_EQUIP")

	var ability := add_fold_section(root, "Ability sub-screen frame")
	_rect(ability, "frame", "LOWER_FRAME_ABILITY")

	var tabs := add_fold_section(root, "Title tabs  (top-left corner)")
	_vec2(tabs, "Eqp tab", "EQP_TAB_POS")
	_vec2(tabs, "Ability tab", "ABL_TAB_POS")
	_vec2(tabs, "Ability tab (left mode)", "ABL_TAB_LEFT_POS")

	var bands := add_fold_section(root, "Column bands  (x edges + shared y)")
	_scalar(bands, "Eqp band x0", "EQP_BAND_X0")
	_scalar(bands, "Eqp band x1", "EQP_BAND_X1")
	_scalar(bands, "Ability band x0", "ABL_BAND_X0")
	_scalar(bands, "Ability band x1", "ABL_BAND_X1")
	_scalar(bands, "Ability band x0 (left)", "ABL_BAND_LEFT_X0")
	_scalar(bands, "Ability band x1 (left)", "ABL_BAND_LEFT_X1")
	_scalar(bands, "band top y", "BAND_TOP")
	_scalar(bands, "band bottom y", "BAND_BOT")

	var picker := add_fold_section(root, "Equip picker  (item-list window)")
	# The WINDOW's own knobs are ADR-0088 element auto-binds (equipicker.window.*), minted
	# when a picker instance boots — these are VIEW rows over the element's spec literals
	# (composite Rect2/Vector4 controls; read-only until a picker has been opened). The
	# generated UI3 dashboard page shows the same rows per element.
	# A rect pos scrub moves the coherent window group (chrome + strip + header + rows +
	# cursor ride the element origin); w/h grow the chrome + aperture.
	TuneField.add(picker, "window rect", "equipicker.window.rect")
	# The interior 9-slice CENTER tiles this fine-dither atlas patch (frame stays STRIPE chrome).
	TuneField.add(picker, "interior dither patch", "equipicker.window.frame_center_patch")
	# The CONTENT knobs are child-element auto-binds now (ADR-0088 amendment §1 — the
	# left strip / header / rows block are registered elements; every row below is a
	# VIEW over an element's composite rect or spec field, placeholder until a picker
	# boots). The generated UI3 page shows the same rows per element.
	# The BROWN vertical strip on the LEFT (a subtractive column band, §15.19).
	TuneField.add(picker, "left strip rect", "equipicker.strip.rect")
	TuneField.add(picker, "left strip subtract", "equipicker.strip.sub")
	TuneField.add(picker, "left strip feather", "equipicker.strip.feather")
	# The item-list ASSEMBLY (rows block): rect.y = row-0 text top; columns are fields.
	TuneField.add(picker, "rows rect (y = row 0 top)", "equipicker.rows.rect")
	TuneField.add(picker, "row pitch", "equipicker.rows.pitch")
	TuneField.add(picker, "type glyph X", "equipicker.rows.glyph_x")
	TuneField.add(picker, "type glyph Y nudge", "equipicker.rows.glyph_dy")
	TuneField.add(picker, "item icon X", "equipicker.rows.icon_x")
	TuneField.add(picker, "item icon Y nudge", "equipicker.rows.icon_dy")
	TuneField.add(picker, "item name X", "equipicker.rows.name_x")
	TuneField.add(picker, "equipped count right X", "equipicker.rows.eq_right_x")
	TuneField.add(picker, "count slash X", "equipicker.rows.slash_x")
	TuneField.add(picker, "owned count right X", "equipicker.rows.owned_right_x")
	# The "Eqp."/"ALL" header stripe cells (§15.26 f): rect.y = the stripe cell top.
	TuneField.add(picker, "header rect (y = cell top)", "equipicker.header.rect")
	TuneField.add(picker, "\"Eqp.\" label X", "equipicker.header.eqp_label_x")
	TuneField.add(picker, "\"ALL\" label X", "equipicker.header.all_label_x")

	var anim := add_fold_section(root, "Box-open animation  (§15.17 aperture)")
	# Fast = the 5-frame doubled-step curve walk (vs the ~9-frame normal). The curve itself is
	# ROM data (world_menu_open_curve) — deliberately NOT a knob.
	TuneField.add(anim, "detail fast open", "detail.fast", bool(_DS.get("FAST")))
	# The picker's fast-open is the window ELEMENT's beat param now (ADR-0088) — a view
	# row over the equipicker.window.fast spec literal.
	TuneField.add(anim, "picker fast open", "equipicker.window.fast")
	# Replay drives every LIVE box-opening panel (group box_open_panels) — an affordance, not a knob.
	var btns := add_button_row(anim)
	var open_btn := Button.new()
	open_btn.text = "Replay open"
	open_btn.pressed.connect(func() -> void:
		for n in get_tree().get_nodes_in_group("box_open_panels"):
			if n.has_method("play_open"):
				n.play_open())
	btns.add_child(open_btn)
	var close_btn := Button.new()
	close_btn.text = "Play close"
	close_btn.pressed.connect(func() -> void:
		for n in get_tree().get_nodes_in_group("box_open_panels"):
			if n.has_method("play_close"):
				n.play_close())
	btns.add_child(close_btn)


# --- TuneField rows (view onto the detail.* slugs DetailScene owns) --------------
# Slug base mirrors DetailScene._bind_detail_tunables: "detail." + the static var's
# lowercased name. Defaults are read from the class static vars (no live instance).

func _rect(parent: Control, label_text: String, prop: String) -> void:
	var base: Variant = _DS.get(prop)   # Rect2 or Rect2i
	var slug := "detail." + prop.to_lower()
	TuneField.add(parent, "%s pos X" % label_text, "%s_x" % slug, float(base.position.x), _POS)
	TuneField.add(parent, "%s pos Y" % label_text, "%s_y" % slug, float(base.position.y), _POS)
	TuneField.add(parent, "%s size W" % label_text, "%s_w" % slug, float(base.size.x), _SIZE)
	TuneField.add(parent, "%s size H" % label_text, "%s_h" % slug, float(base.size.y), _SIZE)


func _vec2(parent: Control, label_text: String, prop: String, hint: Dictionary = _POS) -> void:
	var v: Vector2 = _DS.get(prop)
	var slug := "detail." + prop.to_lower()
	TuneField.add(parent, "%s X" % label_text, "%s_x" % slug, v.x, hint)
	TuneField.add(parent, "%s Y" % label_text, "%s_y" % slug, v.y, hint)


func _scalar(parent: Control, label_text: String, prop: String, hint: Dictionary = _EDGE) -> void:
	TuneField.add(parent, label_text, "detail." + prop.to_lower(), float(_DS.get(prop)), hint)


# Equip-picker rows are ALL views over the element auto-binds now (ADR-0088 amendment
# §1: equipicker.window.* / .strip.* / .header.* / .rows.*) — no panel-owned defaults.
