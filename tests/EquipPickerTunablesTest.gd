extends Node3D
## Guard (headful): the equip-picker's interior geometry is FULLY TUNEABLE through the
## ADR-0088 element model (amendment §1 — no second registration tier for content knobs):
## the left strip / header / rows block are registered CHILD elements of the window, each
## knob either a child element's composite `rect` or a spec FIELD on the element that owns
## it (auto-minted `equipicker.<part>.<field>` slugs). The old flat `equipicker.*` static-var
## slugs are RETIRED — their re-appearance is a revert. Scrubbing a placement knob must
## CHANGE the rendered quad positions (the ADR §7.3 write-through sweep) and restore
## cleanly on clear; interior knobs (sub/feather) must land on the band material.

const EquipPickerMenu = preload("res://src/ui3/detail/EquipPickerMenu.gd")

var _failed := false


func _ready() -> void:
	var m: EquipPickerMenu = EquipPickerMenu.new()
	m.autoplay_open = false
	add_child(m)
	await get_tree().process_frame
	await get_tree().process_frame

	# --- the window's own auto-binds are unchanged (slice-5 model) ----------------
	for slug: String in ["equipicker.window.rect", "equipicker.window.frame_center_patch",
			"equipicker.window.open_cadence"]:
		_expect(Tune.is_registered(slug), "window slug not bound: %s" % slug)

	# --- child elements registered with composite rects at the authored defaults --
	_expect(Tune.is_registered("equipicker.strip.rect"), "strip element rect not bound")
	_expect(Tune.default_of("equipicker.strip.rect") == Rect2(95, 142, 17, 87),
		"strip rect default drift (got %s)" % [Tune.default_of("equipicker.strip.rect")])
	_expect(Tune.is_registered("equipicker.header.rect"), "header element rect not bound")
	_expect(_approx(_rect_default("equipicker.header.rect").position.y, 132.0),
		"header rect default y must carry the authored HEADER_Y (got %s)"
		% [Tune.default_of("equipicker.header.rect")])
	_expect(Tune.is_registered("equipicker.rows.rect"), "rows assembly rect not bound")
	_expect(_approx(_rect_default("equipicker.rows.rect").position.y, 150.0),
		"rows rect default y must carry the authored row-0 text top (got %s)"
		% [Tune.default_of("equipicker.rows.rect")])

	# --- content knobs are spec FIELDS on their owning element (amendment §1) -----
	for slug: String in _field_slugs():
		_expect(Tune.is_registered(slug), "content-knob field not bound: %s" % slug)
	_expect(_approx(_float_default("equipicker.rows.pitch"), 16.0), "row pitch default drift")
	_expect(_approx(_float_default("equipicker.rows.name_x"), 120.0), "name_x default drift")
	# §15.27 (round-46 prim scan + 2026-08-11 quicksave ink-row measurement): BIG eq digits
	# end x217, owned end x238 (was 214/235 SMALL); count_dy −1 lands digit ink on oracle
	# rows 152..160-equivalent; slash_dy 2 bottom-aligns the SMALL '/' with the digit ink.
	_expect(_approx(_float_default("equipicker.rows.eq_right_x"), 217.0), "eq_right_x default drift")
	_expect(_approx(_float_default("equipicker.rows.owned_right_x"), 238.0), "owned_right_x default drift")
	_expect(_approx(_float_default("equipicker.rows.count_dy"), -1.0), "count_dy default drift")
	_expect(_approx(_float_default("equipicker.rows.slash_dy"), 2.0), "slash_dy default drift")
	_expect(_approx(_float_default("equipicker.header.eqp_label_x"), 200.0),
		"eqp_label_x default drift")
	_expect(_approx(_float_default("equipicker.strip.feather"), 2.5), "feather default drift")

	# --- the flat static-var slugs are RETIRED (a re-bind is a model revert) ------
	for slug: String in _retired_slugs():
		_expect(not Tune.is_registered(slug), "retired flat slug re-appeared: %s" % slug)

	# --- the child elements hang off the window in the registry tree --------------
	var reg := get_node("/root/UI3Registry")
	var child_ids: Array = []
	for e: UI3Element in reg.children_of(m.window()):
		child_ids.append(e.id())
	for want: String in ["equipicker.strip", "equipicker.header", "equipicker.rows",
			"equipicker.cursor"]:
		_expect(child_ids.has(want), "element %s not a registry child of the window (got %s)"
			% [want, child_ids])

	# --- write-through sweep: every PLACEMENT knob visibly moves the screen -------
	# (ADR-0088 §7.3.) Scrub → the quad-position multiset changes; clear → it restores.
	var baseline := _positions(m)
	_expect(baseline.size() > 0, "picker built no quads")
	_sweep_rect(m, "equipicker.strip.rect", baseline)
	_sweep_rect(m, "equipicker.header.rect", baseline)
	_sweep_rect(m, "equipicker.rows.rect", baseline)
	for slug: String in ["equipicker.header.eqp_label_x", "equipicker.header.all_label_x",
			"equipicker.rows.pitch", "equipicker.rows.name_x", "equipicker.rows.glyph_x",
			"equipicker.rows.glyph_dy", "equipicker.rows.icon_x", "equipicker.rows.icon_dy",
			"equipicker.rows.eq_right_x", "equipicker.rows.slash_x",
			"equipicker.rows.owned_right_x", "equipicker.rows.count_dy",
			"equipicker.rows.slash_dy"]:
		_sweep_scalar(m, slug, baseline)

	# --- interior knobs land on the live band material ----------------------------
	if Tune.is_registered("equipicker.strip.sub") and m.left_strip_material() != null:
		Tune.set_value("equipicker.strip.sub", 0.5)
		m._flush_pending_rebuild()   # the content-knob rebuild is DEFERRED (out of the input callstack) — flush to observe it
		_expect(m.left_strip_material() != null
			and _approx(m.left_strip_material().get_shader_parameter("full_sub"), 0.5),
			"strip sub scrub did not land on the band material")
		Tune.clear("equipicker.strip.sub")
		m._flush_pending_rebuild()
		var feather_before: float = m.left_strip_material().get_shader_parameter("x_left_out")
		Tune.set_value("equipicker.strip.feather", 6.0)
		m._flush_pending_rebuild()
		_expect(m.left_strip_material() != null
			and not _approx(m.left_strip_material().get_shader_parameter("x_left_out"), feather_before),
			"strip feather scrub did not rebuild the band fade")
		Tune.clear("equipicker.strip.feather")
	else:
		_expect(false, "strip sub/feather fields or band material missing — interior knobs unreachable")

	# --- the window pads its aperture for the header poke (amendment §4, consumer 1) --
	# HEADER_Y 132 pokes above the window rect top (y136); the authored aperture_pad
	# (0,4,0,0) grows the box the box-open plays over so the cells aren't clipped.
	_expect(Tune.is_registered("equipicker.window.aperture_pad"),
		"window aperture_pad spec field not auto-bound")
	var wrect := Rect2(m.window().rect())
	_expect(m.aperture().position.y == int(wrect.position.y) - 4
		and m.aperture().size.y == int(wrect.size.y) + 4,
		"settled aperture must include the 4px top pad (rect %s, aperture %s)"
		% [wrect, m.aperture()])

	# --- the strip element rect is the public strip geometry ----------------------
	_expect(m.left_strip_rect() == Rect2(95, 142, 17, 87),
		"left_strip_rect must read the strip element's live rect (got %s)" % [m.left_strip_rect()])
	_expect(m.body_materials().has(m.left_strip_material()),
		"strip material must be in body_materials() (box-open reveals child-element payload)")

	m.queue_free()
	if _failed:
		push_error("[FAIL] EquipPickerTunablesTest")
		get_tree().quit(1)
	else:
		print("[PASS] EquipPickerTunablesTest")
		get_tree().quit(0)


## Scrub a composite rect slug by +8px x and assert the screen changed, then restore.
func _sweep_rect(m: Node, slug: String, baseline: Array) -> void:
	if not Tune.is_registered(slug):
		_expect(false, "%s not bound — placement sweep unreachable" % slug)
		return
	var r := _rect_default(slug)
	Tune.set_value(slug, Rect2(r.position.x + 8.0, r.position.y, r.size.x, r.size.y))
	_expect(not _same(_positions(m), baseline), "%s scrub did not move the screen" % slug)
	Tune.clear(slug)
	_expect(_same(_positions(m), baseline), "%s clear did not restore the screen" % slug)


## Scrub a scalar field slug by +5 and assert the screen changed, then restore.
func _sweep_scalar(m: Node, slug: String, baseline: Array) -> void:
	if not Tune.is_registered(slug):
		_expect(false, "%s not bound — placement sweep unreachable" % slug)
		return
	var v := _float_default(slug)
	Tune.set_value(slug, v + 5.0)
	m._flush_pending_rebuild()   # content-knob rebuild is DEFERRED off the input callstack — flush to observe this scrub
	_expect(not _same(_positions(m), baseline), "%s scrub did not move the screen" % slug)
	Tune.clear(slug)
	m._flush_pending_rebuild()
	_expect(_same(_positions(m), baseline), "%s clear did not restore the screen" % slug)


func _rect_default(slug: String) -> Rect2:
	var v: Variant = Tune.default_of(slug)
	return Rect2(v) if (v is Rect2 or v is Rect2i) else Rect2()


func _float_default(slug: String) -> float:
	var v: Variant = Tune.default_of(slug)
	return float(v) if (v is float or v is int) else 0.0


func _field_slugs() -> Array:
	return [
		"equipicker.strip.sub", "equipicker.strip.feather",
		"equipicker.header.eqp_label_x", "equipicker.header.all_label_x",
		"equipicker.rows.pitch", "equipicker.rows.name_x",
		"equipicker.rows.glyph_x", "equipicker.rows.glyph_dy",
		"equipicker.rows.icon_x", "equipicker.rows.icon_dy",
		"equipicker.rows.eq_right_x", "equipicker.rows.slash_x",
		"equipicker.rows.owned_right_x",
		"equipicker.rows.count_dy", "equipicker.rows.slash_dy",
	]


func _retired_slugs() -> Array:
	return [
		"equipicker.strip_x", "equipicker.strip_y", "equipicker.strip_w", "equipicker.strip_h",
		"equipicker.strip_sub", "equipicker.strip_feather",
		"equipicker.glyph_x", "equipicker.glyph_dy", "equipicker.icon_x", "equipicker.icon_dy",
		"equipicker.name_x", "equipicker.row0_y", "equipicker.row_pitch",
		"equipicker.eq_right_x", "equipicker.slash_x", "equipicker.owned_right_x",
		"equipicker.header_y", "equipicker.eqp_label_x", "equipicker.all_label_x",
	]


## The sorted world-position multiset of every drawn quad under the picker (the golden
## guard's collection, reused as the §7.3 "did the screen change" probe).
func _positions(root: Node) -> Array:
	var out: Array = []
	_collect(root, out)
	out.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		if not is_equal_approx(a.x, b.x): return a.x < b.x
		if not is_equal_approx(a.y, b.y): return a.y < b.y
		return a.z < b.z)
	return out


func _collect(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append((n as MeshInstance3D).global_position)
	for c in n.get_children():
		_collect(c, out)


func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if (a[i] - b[i]).length() >= 0.0005:
			return false
	return true


func _approx(a: Variant, b: float) -> bool:
	return abs(float(a) - b) < 0.001


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		push_error("[EquipPickerTunablesTest] %s" % msg)
