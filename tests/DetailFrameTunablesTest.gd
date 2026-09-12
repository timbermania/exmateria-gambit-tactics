extends Node3D

## Guard (headful): the DETAIL / Status-screen frame tunables (ADR-0068). Locks that
## every window/aperture/tab/band `static var` on DetailScene is bound to a `detail.*`
## Tune slug at the settled defaults, and that scrubbing a slug drives the static var +
## rebuilds the settled lower panel live (the F3 "Detail Screen" panel is a pure view over
## these — DetailScreenDebugPanel). Catches a revert to hardcoded `const` frames (which a
## scrub can't reach) or a slug/name drift between the binder and the panel.

const DetailScene = preload("res://src/ui3/detail/DetailScene.gd")

var _failed := false


func _ready() -> void:
	var d: DetailScene = DetailScene.new()
	d.autoplay_open = false            # _ready binds the slugs + builds the panel settled
	add_child(d)

	# --- registration: the slugs exist at the settled §15.14 defaults ------------
	_expect(Tune.is_registered("detail.stats_frame_x"), "stats_frame_x not registered")
	# Materialised 2026-08-11: the F3 frame pins are the code literals now.
	_expect(_approx(Tune.default_of("detail.stats_frame_x"), 10.0), "stats_frame_x default != 10")
	_expect(_approx(Tune.default_of("detail.stats_frame_w"), 230.0), "stats_frame_w default != 230")
	_expect(_approx(Tune.default_of("detail.lower_frame_equip_w"), 125.0), "lower_frame_equip_w default != 125")
	_expect(_approx(Tune.default_of("detail.open_container_h"), 108.0), "open_container_h default != 108")
	_expect(_approx(Tune.default_of("detail.eqp_tab_pos_x"), 29.0), "eqp_tab_pos_x default != 29")
	_expect(_approx(Tune.default_of("detail.eqp_band_x0"), 30.0), "eqp_band_x0 default != 30")
	# §15.29 round 48: nudge = STATS_FRAME0 − STATS_FRAME.position — zero-net, so the
	# LBL_*/value consts ARE the on-screen display px (ROM table DAT_8018B3FC, oracle-verified).
	_expect(_approx(Tune.default_of("detail.stats_panel_nudge_y"), -4.0), "stats_panel_nudge_y default != -4")
	# §15.26 DEFECT #8: the compare/delta (foreground) stats panel's offset is now a live knob too.
	# Dialed DOWN-RIGHT to the ROM (§15.26 C2) and materialised 2026-08-11.
	_expect(_approx(Tune.default_of("detail.stats_delta_nudge_x"), 2.0), "stats_delta_nudge_x default != 2")
	_expect(_approx(Tune.default_of("detail.stats_delta_nudge_y"), 2.0), "stats_delta_nudge_y default != 2")

	# --- every slug the panel views is actually bound (name-drift guard) ---------
	for slug: String in _all_expected_slugs():
		_expect(Tune.is_registered(slug), "panel slug not bound by DetailScene: %s" % slug)

	# --- scrub drives the static var (Rect2 recompose + Rect2i rounding) ---------
	Tune.set_value("detail.stats_frame_x", 40.0)
	_expect(_approx(DetailScene.STATS_FRAME.position.x, 40.0),
		"scrub did not write STATS_FRAME.x (got %s)" % DetailScene.STATS_FRAME.position.x)
	Tune.set_value("detail.open_container_w", 200.0)   # Rect2i — must round to int, no error
	_expect(DetailScene.OPEN_CONTAINER.size.x == 200,
		"scrub did not write OPEN_CONTAINER.w (got %s)" % DetailScene.OPEN_CONTAINER.size.x)
	Tune.set_value("detail.eqp_band_x0", 33.0)
	_expect(_approx(DetailScene.EQP_BAND_X0, 33.0),
		"scrub did not write EQP_BAND_X0 (got %s)" % DetailScene.EQP_BAND_X0)
	Tune.set_value("detail.stats_delta_nudge_x", -5.0)   # Vector2 knob — writes the static var back
	_expect(_approx(DetailScene.STATS_DELTA_NUDGE.x, -5.0),
		"scrub did not write STATS_DELTA_NUDGE.x (got %s)" % DetailScene.STATS_DELTA_NUDGE.x)
	# Weapon legend + value-column knobs write through (const-revert guard), then restore.
	var wip_before: float = DetailScene.WEAPON_ICON_POS.x
	Tune.set_value("detail.weapon_icon_pos_x", wip_before + 6.0)
	_expect(_approx(DetailScene.WEAPON_ICON_POS.x, wip_before + 6.0),
		"scrub did not write WEAPON_ICON_POS.x (got %s)" % DetailScene.WEAPON_ICON_POS.x)
	Tune.clear("detail.weapon_icon_pos_x")
	var DS: Object = DetailScene   # untyped handle: .get(<dynamic prop>) reads class static vars
	for pair: Array in [["detail.mjs_value_x", "MJS_VALUE_X"], ["detail.wp_value_x", "WP_VALUE_X"],
			["detail.at_val_x", "AT_VAL_X"]]:
		var vslug: String = pair[0]
		var vprop: String = pair[1]
		var vbefore: float = float(DS.get(vprop))
		Tune.set_value(vslug, vbefore + 3.0)
		_expect(_approx(DS.get(vprop), vbefore + 3.0),
			"%s scrub did not write %s (got %s)" % [vslug, vprop, DS.get(vprop)])
		Tune.clear(vslug)

	# --- scrub rebuilds the settled lower panel (the frame node moves live) ------
	# The stats-band frame is drawn at STATS_FRAME (+ the panel nudge). A scrub of the
	# frame's x must survive the rebuild — the rebuilt node reflects the new value. Since the
	# frame chrome is now a CHILD of _stats_origin (the "frame = movable group" model), the frame
	# moves via the ORIGIN — check its GLOBAL x, not the (constant) local offset under the origin.
	_expect(d._open_root != null and is_instance_valid(d._open_root),
		"lower panel not built after settle")
	# Seed a stats view so the band has real content glyphs, then prove the CONTENT rides the frame:
	# scrubbing the frame position must move a stat glyph by the SAME delta as the chrome (the whole
	# point of the "frame = movable group" refactor — content no longer stays put when the frame moves).
	d.set_stats_view({"move": 4, "jump": 3, "speed": 8, "r_power": 9, "r_wev": 5,
		"l_power": 0, "l_wev": 0, "attack": 7, "evade": 12})
	var glyph_before := Vector3.INF
	if d._stats_text_root != null and d._stats_text_root.get_child_count() > 0:
		glyph_before = _first_mesh(d._stats_text_root).global_position
	var before_x: float = d._stats_frame_node.global_position.x
	Tune.set_value("detail.stats_frame_x", 60.0)
	d._flush_pending_rebuild()   # the scrub rebuild is DEFERRED (out of the input callstack) — flush it to observe this scrub's effect
	_expect(d._open_root != null and is_instance_valid(d._open_root),
		"lower panel gone after scrub-rebuild")
	var frame_dx: float = d._stats_frame_node.global_position.x - before_x
	_expect(not _approx(frame_dx, 0.0),
		"stats frame did not move on scrub (rebuild not wired?) x=%s" % d._stats_frame_node.global_position.x)
	if glyph_before != Vector3.INF:
		var glyph_after: Vector3 = _first_mesh(d._stats_text_root).global_position
		_expect(_approx(glyph_after.x - glyph_before.x, frame_dx),
			"stat glyph did NOT ride the frame move (content decoupled): glyph dx=%s vs frame dx=%s"
				% [glyph_after.x - glyph_before.x, frame_dx])

	# --- RESIZE PINS CONTENT: scrubbing the frame WIDTH grows the chrome but must NOT move content
	# (the design decision — chrome grows, content stays put; no reflow). -------------------------
	Tune.set_value("detail.stats_frame_x", 10.0)   # restore x so the glyph baseline is the settled home
	d._flush_pending_rebuild()   # apply the x-restore on its own (deferred rebuild coalesces per frame; flush isolates each scrub)
	var w_before: float = d._stats_frame_node.frame_size.x
	var glyph_pre := Vector3.INF
	if d._stats_text_root != null and d._stats_text_root.get_child_count() > 0:
		glyph_pre = _first_mesh(d._stats_text_root).global_position
	Tune.set_value("detail.stats_frame_w", 260.0)
	d._flush_pending_rebuild()
	_expect(d._stats_frame_node.frame_size.x > w_before,
		"frame width scrub did not grow the chrome (w %s -> %s)" % [w_before, d._stats_frame_node.frame_size.x])
	if glyph_pre != Vector3.INF:
		var glyph_post: Vector3 = _first_mesh(d._stats_text_root).global_position
		_expect(glyph_post.is_equal_approx(glyph_pre),
			"resize MOVED content (should pin): glyph %s -> %s" % [glyph_pre, glyph_post])

	# --- APERTURE RIDES THE FRAME: the box-open scissor's y/h are DERIVED from STATS_FRAME, so moving
	# the frame Y moves its reveal window too (the fix for "move the frame down → bottom gets clipped").
	# Relative delta (live defaults come from persisted tune_overrides, not the code literals).
	Tune.clear("detail.stats_frame_x"); Tune.clear("detail.stats_frame_w")   # restore prior scrubs
	d._flush_pending_rebuild()   # apply the cleared defaults before measuring the settled aperture
	d.set_open_frame(d._open_total_frames())         # settle so stats_aperture == the full derived rect
	var fy_before: float = DetailScene.STATS_FRAME.position.y
	var ap_before: int = d.stats_aperture().position.y
	Tune.set_value("detail.stats_frame_y", fy_before + 8.0)   # move the frame DOWN 8px
	d._flush_pending_rebuild()
	d.set_open_frame(d._open_total_frames())
	_expect(d.stats_aperture().position.y == ap_before + 8,
		"stats aperture did NOT ride the frame Y (content would clip): aperture y %d -> %d, want +8"
			% [ap_before, d.stats_aperture().position.y])
	# The aperture's y/h are derived, not knobs — so those slugs must NOT be registered.
	_expect(not Tune.is_registered("detail.stats_container_y"),
		"stats_container_y should be derived from STATS_FRAME, not a live knob")
	_expect(not Tune.is_registered("detail.stats_container_h"),
		"stats_container_h should be derived from STATS_FRAME, not a live knob")

	# --- IN-PICKER: the delta/compare (fg) panel offset knob moves the LIVE delta panel ----------
	# The compare band exists ONLY in the picker's stats-preview state (decision: in-picker only, no
	# force-preview toggle). Enter preview, then scrubbing STATS_DELTA_NUDGE must relocate the live delta
	# panel by the corresponding world delta — proof the knob reaches the fg panel through a rebuild.
	Tune.clear("detail.stats_delta_nudge_x"); Tune.clear("detail.stats_delta_nudge_y")
	d.set_stats_preview(true)
	_expect(d.stats_delta_active(), "delta panel not built in preview (can't dial the fg knob)")
	if d.stats_delta_active():
		var pos_before: float = d._stats_delta_root.global_position.x
		Tune.set_value("detail.stats_delta_nudge_x", DetailScene.STATS_DELTA_NUDGE.x - 3.0)  # 3px further left
		d._flush_pending_rebuild()
		_expect(d.stats_delta_active(), "delta panel gone after knob scrub-rebuild")
		var dx: float = d._stats_delta_root.global_position.x - pos_before
		_expect(_approx(dx, -3.0 * DetailScene.PIXELS_PER_UNIT),
			"fg-panel knob did not move the live delta panel: world dx=%s want %s"
				% [dx, -3.0 * DetailScene.PIXELS_PER_UNIT])
	d.set_stats_preview(false)
	Tune.clear("detail.stats_delta_nudge_x")

	# --- reset so a committed override / later test sees clean defaults ----------
	for slug: String in _all_expected_slugs():
		Tune.clear(slug)

	d.queue_free()
	if _failed:
		push_error("[FAIL] DetailFrameTunablesTest")
		get_tree().quit(1)
	else:
		print("[PASS] DetailFrameTunablesTest")
		get_tree().quit(0)


func _all_expected_slugs() -> Array:
	var out: Array = []
	for r in ["stats_frame", "lower_frame", "lower_frame_equip", "lower_frame_ability",
			"open_container"]:
		for c in ["x", "y", "w", "h"]:
			out.append("detail.%s_%s" % [r, c])
	# STATS_CONTAINER exposes only x/w — its y/h are DERIVED from STATS_FRAME (the aperture rides the
	# frame), so there are deliberately no stats_container_y / _h knobs.
	out.append("detail.stats_container_x")
	out.append("detail.stats_container_w")
	for v in ["eqp_tab_pos", "abl_tab_pos", "abl_tab_left_pos", "stats_panel_nudge", "stats_delta_nudge",
			"weapon_icon_pos"]:
		out.append("detail.%s_x" % v)
		out.append("detail.%s_y" % v)
	for s in ["mjs_value_x", "wp_value_x", "at_val_x"]:
		out.append("detail.%s" % s)
	for s in ["eqp_band_x0", "eqp_band_x1", "abl_band_x0", "abl_band_x1",
			"abl_band_left_x0", "abl_band_left_x1", "band_top", "band_bot"]:
		out.append("detail.%s" % s)
	return out


## First MeshInstance3D in a subtree (a real drawn glyph/quad), or null.
func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var m := _first_mesh(c)
		if m != null:
			return m
	return null


func _approx(a: Variant, b: float) -> bool:
	return abs(float(a) - b) < 0.001


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		push_error("[DetailFrameTunablesTest] %s" % msg)
