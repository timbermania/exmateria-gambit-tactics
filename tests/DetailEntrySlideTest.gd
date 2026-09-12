extends Node3D

## DetailScene ENTRY-SLIDE guard (headful) — the first-class chrome slide
## (FORMATION_SCREEN.md §15.1/§15.6) extracted from the ○-press transition so the
## main-menu sub-screens (Change-Job / Equip / Ability) can raise the shared
## vitals+nameplate PAIR from DOCKED→TOP without also running the §15.17 box-open.
##
## `play_entry_slide()` plays ONLY motion (1): the pair rises through the §15.1
## keyframes with the band cross-fade, then emits `entry_slide_done` and STOPS — the
## lower Eqp/Ability panel is never unfurled (that is the sub-screen's own job). This
## is the seam that fixes the "binary flip" when entering Change-Job from the main menu.
##
## Also pins the teleport-robustness clamp: a single oversized delta (a stall / the
## Hyprland render_unfocused throttle) must NOT collapse the slide to settled in one
## visual frame — intermediate keyframes stay visible.

const DetailScene = preload("res://src/ui3/detail/DetailScene.gd")
const VitalsSlideAnimator = preload("res://src/ui3/detail/VitalsSlideAnimator.gd")

const TICK := 2.0 / 60.0   # one menu tick (§15.5: keyframes held ~2 vsyncs)

var _failed := false


func _ready() -> void:
	# --- A: play_entry_slide raises the pair DOCKED→TOP, NO box-open, fires the signal ---
	var d: DetailScene = DetailScene.new()
	d.autoplay_open = false            # the entry slide drives placement, not _ready
	add_child(d)

	var done := [false]
	d.entry_slide_done.connect(func(): done[0] = true)
	d.play_entry_slide()

	# Phase start: pair DOCKED at the formation bottom, lower panel CLOSED (never opens).
	_expect(d._cluster != null, "cluster missing")
	_expect(d._cluster.vitals_origin_px().is_equal_approx(Vector2(13, 177)),
		"entry-slide start: vitals not docked (got %s, want (13,177))" % d._cluster.vitals_origin_px())
	_expect(d.lower_aperture().size == Vector2i.ZERO,
		"lower panel not closed at entry-slide start (aperture=%s)" % d.lower_aperture())
	_expect(not done[0], "entry_slide_done fired before the slide even ran")

	# Mid-slide: after a couple ticks the pair is BETWEEN docked and top (a real slide, not a snap).
	d._process(TICK)
	d._process(TICK)
	var mid := d._cluster.vitals_origin_px().y
	_expect(mid < 177.0 and mid > 32.0,
		"pair did not move through an intermediate position (y=%.1f, want between 32 and 177)" % mid)

	# Pump the slide to completion: the pair reaches the TOP layout and the signal fires.
	for _i in VitalsSlideAnimator.settle_frame() + 2:
		d._process(TICK)
	_expect(d._cluster.vitals_origin_px().is_equal_approx(Vector2(13, 32)),
		"after entry slide: vitals not at top (got %s, want (13,32))" % d._cluster.vitals_origin_px())
	_expect(done[0], "entry_slide_done never fired at settle")
	# The band cross-fade completed (roster band out, detail top stripe in).
	_expect(is_equal_approx(d.formation_band_factor(), 0.0),
		"formation band not faded out after entry slide (%.2f)" % d.formation_band_factor())

	# The CRUX: the box-open must NEVER start — pumping more frames leaves the lower panel CLOSED
	# (play_entry_slide is motion (1) only; the sub-screen opens its own panel). This is what
	# distinguishes it from play_transition (which would unfurl the box here).
	for _i in 30:
		d._process(TICK)
	_expect(d.lower_aperture().size == Vector2i.ZERO,
		"box-open ran after the entry slide — play_entry_slide must NOT open the lower panel (aperture=%s)" % d.lower_aperture())

	# --- B: teleport robustness — one oversized delta must NOT skip to settled -----------
	var d2: DetailScene = DetailScene.new()
	d2.autoplay_open = false
	add_child(d2)
	d2.play_entry_slide()
	_expect(d2._cluster.vitals_origin_px().is_equal_approx(Vector2(13, 177)),
		"d2 not docked at start (%s)" % d2._cluster.vitals_origin_px())
	# A single huge frame (1 s — a stall / render_unfocused throttle). The per-frame catch-up is
	# clamped, so the pair advances only a bounded step — it must NOT land at the settled top.
	d2._process(1.0)
	var y_after_spike := d2._cluster.vitals_origin_px().y
	_expect(y_after_spike > 40.0,
		"one oversized delta teleported the pair to settled (y=%.1f — the slide must not collapse)" % y_after_spike)

	if _failed:
		print("[FAIL] DetailEntrySlide test")
	else:
		print("[PASS] DetailEntrySlide: play_entry_slide raises the pair (no box-open), emits done; delta-spike clamped (no teleport)")
	get_tree().quit()


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] %s" % msg)
		_failed = true
