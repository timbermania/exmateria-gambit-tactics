extends Node3D

## DetailScene ○-press TRANSITION guard (headful) — the three-phase arc
## (FORMATION_SCREEN.md §15.5/§15.9): (1) the shared vitals+nameplate cluster SLIDES
## bottom→top via the §15.1 keyframe curve while the lower Eqp/Ability panel stays
## CLOSED; (2) a short dead gap; (3) the §15.17 box-open unfurls the lower panel.
##
## Drives `_process` deterministically (fixed 2/60 s ticks, the menu cadence) so the
## whole sequence is reproducible without wall-clock. Locks the ordering a silent edit
## could regress: no box-open before the slide settles; box-open completes after.

const DetailScene = preload("res://src/ui3/detail/DetailScene.gd")
const UnitInfoCluster = preload("res://src/ui3/UnitInfoCluster.gd")
const VitalsSlideAnimator = preload("res://src/ui3/detail/VitalsSlideAnimator.gd")

const TICK := 2.0 / 60.0   # one menu tick (§15.5: keyframes held ~2 vsyncs)

var _failed := false


func _ready() -> void:
	var d: DetailScene = DetailScene.new()
	d.autoplay_open = false            # the transition drives the box-open, not _ready
	add_child(d)                       # builds panels; box-open settled

	d.play_transition()

	# --- phase 1 start: pair DOCKED at the formation bottom, lower panel CLOSED ---
	_expect(d._cluster != null, "cluster missing")
	_expect(d._cluster.vitals_origin_px().is_equal_approx(Vector2(13, 177)),
		"transition start: vitals not docked (got %s, want (13,177))" % d._cluster.vitals_origin_px())
	# The box-open is a scissor reveal (§15.17): "closed" = an empty aperture, not scale 0.
	_expect(d.lower_aperture().size == Vector2i.ZERO,
		"lower panel not closed during slide (aperture=%s)" % d.lower_aperture())

	# --- pump the slide to completion: the pair rises to the TOP layout ----------
	for _i in VitalsSlideAnimator.settle_frame() + 1:
		d._process(TICK)
	_expect(d._cluster.vitals_origin_px().is_equal_approx(Vector2(13, 32)),
		"after slide: vitals not at top (got %s, want (13,32))" % d._cluster.vitals_origin_px())
	# The windows must NOT have started opening yet (still the dead gap).
	_expect(d.lower_aperture().size == Vector2i.ZERO,
		"box-open started before the dead gap elapsed (aperture=%s)" % d.lower_aperture())

	# --- pump through the dead gap + the box-open: lower panel aperture reaches FULL -----
	for _i in 24:
		d._process(TICK)
	_expect(d.lower_aperture() == DetailScene.OPEN_CONTAINER,
		"box-open did not settle after the transition (aperture=%s, want full)" % d.lower_aperture())
	# And the pair holds at the top (the slide doesn't drift back).
	_expect(d._cluster.vitals_origin_px().is_equal_approx(Vector2(13, 32)),
		"vitals drifted off the top after settling (got %s)" % d._cluster.vitals_origin_px())

	# --- REVERSE (Esc): box folds shut FIRST, THEN the pair slides back to docked ---
	var got_closed := [false]
	d.closed.connect(func(): got_closed[0] = true)
	d.play_close()
	# One tick in: the box is folding (scale dropping) while the pair still holds at the top —
	# the ORDER is box-close before slide-down (the opposite of open's slide-before-box).
	d._process(TICK)
	_expect(d.lower_aperture() != DetailScene.OPEN_CONTAINER,
		"box did not begin folding shut on close (aperture still full: %s)" % d.lower_aperture())
	_expect(d._cluster.vitals_origin_px().is_equal_approx(Vector2(13, 32)),
		"pair slid before the box folded shut (got %s)" % d._cluster.vitals_origin_px())
	# Pump the rest: box shut → gap → slide down to docked, then `closed` fires.
	for _i in 40:
		if got_closed[0]:
			break
		d._process(TICK)
	_expect(got_closed[0], "reverse transition never emitted `closed`")
	_expect(d._cluster.vitals_origin_px().is_equal_approx(Vector2(13, 177)),
		"pair not back at the docked layout after close (got %s)" % d._cluster.vitals_origin_px())
	_expect(d.lower_aperture().size == Vector2i.ZERO,
		"lower panel not closed after the reverse transition (aperture=%s)" % d.lower_aperture())

	if _failed:
		print("[FAIL] DetailTransition test")
	else:
		print("[PASS] DetailTransition: §15.5 slide → gap → box-open, ordered")
	get_tree().quit()


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] %s" % msg)
		_failed = true
