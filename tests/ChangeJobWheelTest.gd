extends Node

## Pure-model guard for the Change-Job wheel (FORMATION_SCREEN.md §15.24, RE round 28).
## Asserts the DATA-DERIVED invariants (ADR-0001): the ring is one member per gender-appropriate
## generic job, the gender lock drops the opposite-sex job (Bard for females, Dancer for males), and
## every member resolves a real per-sex body sprite + a job name. No rendering — behavior, not pixels.

const ChangeJobWheel = preload("res://src/ui3/changejob/ChangeJobWheel.gd")
const ChangeJobScreen = preload("res://src/ui3/changejob/ChangeJobScreen.gd")

var _failed := false


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] " + msg)
		_failed = true


func _ready() -> void:
	var male := ChangeJobWheel.job_ids_for_sex(false)
	var female := ChangeJobWheel.job_ids_for_sex(true)

	# 20 generic jobs (0x4A..0x5D) minus the one opposite-sex-locked job = 19 each (oracle male ring = 19).
	_expect(male.size() == 19, "male wheel not 19 jobs (got %d)" % male.size())
	_expect(female.size() == 19, "female wheel not 19 jobs (got %d)" % female.size())

	# Gender lock: male sees Bard (0x5b) not Dancer (0x5c); female the reverse.
	_expect(male.has("5b") and not male.has("5c"), "male wheel must include Bard, exclude Dancer")
	_expect(female.has("5c") and not female.has("5b"), "female wheel must include Dancer, exclude Bard")

	# Both include Squire (0x4a) and Mime (0x5d) — sex-neutral generic jobs.
	_expect(male.has("4a") and male.has("5d"), "male wheel missing Squire/Mime")
	_expect(female.has("4a") and female.has("5d"), "female wheel missing Squire/Mime")

	# Every member resolves a real body sprite id and a job name (data-derived, no hand-encoding).
	for jid in male:
		_expect(ChangeJobWheel.body_sprite_id(jid, false) > 0, "no male body sprite for job %s" % jid)
		_expect(ChangeJobWheel.job_name(jid) != jid, "no job name for %s" % jid)
	_expect(ChangeJobWheel.job_name("4a") == "Squire", "job 0x4a name != Squire (got %s)" % ChangeJobWheel.job_name("4a"))

	# Oval: ring members lie on the oval around CENTRE; the front member (index 0) is bottom-centre.
	var p0 := ChangeJobWheel.ring_position(0, male.size())
	_expect(abs(p0.x - ChangeJobWheel.CENTRE.x) < 0.5 and p0.y > ChangeJobWheel.CENTRE.y,
		"ring member 0 not at front/bottom-centre (got %s)" % p0)
	# All members within the oval bounding box (rx,ry) of the centre.
	for i in male.size():
		var p := ChangeJobWheel.ring_position(i, male.size())
		var off := p - ChangeJobWheel.CENTRE
		_expect(abs(off.x) <= ChangeJobWheel.RADIUS_X + 0.5 and abs(off.y) <= ChangeJobWheel.RADIUS_Y + 0.5,
			"ring member %d outside oval (got %s)" % [i, p])

	# --- ENTRY contraction (§15.24 RE29, gap 2): members slide in from OUTSIDE the oval (k>1) and settle
	# to k=1. entry_position scales the settled slot out from CENTRE by k.
	_expect(ChangeJobWheel.entry_k(0) > 1.0, "entry k at frame 0 not off-oval (got %.2f)" % ChangeJobWheel.entry_k(0))
	_expect(abs(ChangeJobWheel.entry_k(ChangeJobWheel.ENTRY_DURATION) - 1.0) < 0.001, "entry k not settled to 1 at end")
	_expect(ChangeJobWheel.entry_k(1) < ChangeJobWheel.entry_k(0), "entry k not decreasing (ease-out contraction)")
	var settled := ChangeJobWheel.ring_position(3, male.size())
	var far := ChangeJobWheel.entry_position(settled, ChangeJobWheel.entry_k(0))
	_expect((far - ChangeJobWheel.CENTRE).length() > (settled - ChangeJobWheel.CENTRE).length(),
		"entry_position at k>1 not farther from centre than settled")
	_expect(ChangeJobWheel.entry_position(settled, 1.0).distance_to(settled) < 0.001,
		"entry_position at k=1 not equal to the settled slot")

	# --- EXIT fling (§15.24, user 2026-08-08): k grows 1.0 → EXIT_K_END (ease-in, accelerate outward),
	# big enough that every member clears the 256×240 screen. Mirror of the entry contraction, reversed.
	_expect(abs(ChangeJobWheel.exit_k(0) - 1.0) < 0.001, "exit k at frame 0 not the settled oval (1.0)")
	_expect(abs(ChangeJobWheel.exit_k(ChangeJobWheel.EXIT_DURATION) - ChangeJobWheel.EXIT_K_END) < 0.001,
		"exit k not EXIT_K_END at the end")
	_expect(ChangeJobWheel.exit_k(1) > 1.0 and ChangeJobWheel.exit_k(1) < ChangeJobWheel.exit_k(2),
		"exit k not accelerating outward (ease-in)")
	# At EXIT_K_END the front-bottom member is off the bottom edge and the side members off the L/R edges.
	var front_end := ChangeJobWheel.entry_position(ChangeJobWheel.ring_position(0, male.size()), ChangeJobWheel.EXIT_K_END)
	_expect(front_end.y > 240.0, "exit does not fling the front member off the bottom (y=%.1f)" % front_end.y)
	var side_end := ChangeJobWheel.entry_position(Vector2(ChangeJobWheel.CENTRE.x + ChangeJobWheel.RADIUS_X, ChangeJobWheel.CENTRE.y), ChangeJobWheel.EXIT_K_END)
	_expect(side_end.x > 256.0, "exit does not fling side members off the right edge (x=%.1f)" % side_end.x)

	# --- STATIC-DERIVED geometry (§15.24 RE31, FUN_80119AA0, 0px-validated on the live ring). Lock the
	# ROM constants so a future tweak can't silently drift back to the old dynamic-fitted guesses.
	_expect(ChangeJobWheel.CENTRE == Vector2(128.0, 126.0), "ring CENTRE != (128,126) (got %s)" % ChangeJobWheel.CENTRE)
	_expect(ChangeJobWheel.RADIUS_X == 100.0, "ring RADIUS_X != 100 (got %s)" % ChangeJobWheel.RADIUS_X)
	_expect(ChangeJobWheel.RADIUS_Y == 60.0, "ring RADIUS_Y != 60 (got %s)" % ChangeJobWheel.RADIUS_Y)
	# The front member (index 0) sits at the oval bottom, centre (128,186); its 24×40 sprite (centre+20 =
	# bottom y206) must CLEAR the job-title plate top (oracle ~1px gap) — else it collides like the old bug.
	var pf := ChangeJobWheel.ring_position(0, male.size())
	_expect(pf == Vector2(128.0, 186.0), "front member centre != (128,186) (got %s)" % pf)
	var sprite_bottom := pf.y + 20.0
	_expect(sprite_bottom <= float(ChangeJobScreen.TITLE_FRAME.position.y),
		"front ring body (bottom y%.0f) overlaps the plate top (y%d)" % [sprite_bottom, ChangeJobScreen.TITLE_FRAME.position.y])
	# The cream "Lv. N" label STRADDLES the plate top edge (half above / half on the tan border, oracle).
	var plate_top := float(ChangeJobScreen.TITLE_FRAME.position.y)
	_expect(ChangeJobScreen.LEVEL_LABEL_TOP_Y < plate_top,
		"Lv label top (%.0f) not above plate top (%.0f) — should poke out" % [ChangeJobScreen.LEVEL_LABEL_TOP_Y, plate_top])
	_expect(ChangeJobScreen.LEVEL_LABEL_TOP_Y + 8.0 > plate_top,
		"Lv label (top %.0f) does not reach onto the plate (%.0f) — not straddling" % [ChangeJobScreen.LEVEL_LABEL_TOP_Y, plate_top])

	# --- ROTATION offset (§15.24 RE29, gap 3): a fractional front_index rotates the ring; the member AT
	# front_index sits at the front-bottom slot (where member 0 sits when front_index=0).
	var front0 := ChangeJobWheel.ring_position(0, male.size(), 0.0)
	var front2 := ChangeJobWheel.ring_position(2, male.size(), 2.0)
	_expect(front2.distance_to(front0) < 0.001, "member 2 at front_index=2 not at the front-bottom slot")
	_expect(ChangeJobWheel.index_of_job(male, "4d") == male.find("4d"), "index_of_job wrong for a present job")

	# --- DRAW ORDER / painter's depth (§15.24 RE31, FUN_80119AA0 iVar6). The ROM accumulates a per-member
	# OT priority that is MONOTONIC in the member's oval screen-Y: a front (bottom, larger screen-Y) member
	# draws OVER a back (top, smaller screen-Y) one. ring_depth_bias reproduces that ordering so overlapping
	# ring bodies occlude front-over-back. (Simulated iVar6 for n=19 is monotone in screen-Y — the ±1
	# left/right accumulator asymmetry only affects mirror members, which never overlap.)
	var n := male.size()
	# Monotone: for EVERY pair, the member lower on screen (larger y) has a bias >= the higher one.
	for i in n:
		for j in n:
			var yi := ChangeJobWheel.ring_position(i, n).y
			var yj := ChangeJobWheel.ring_position(j, n).y
			if yi > yj + 0.001:
				_expect(ChangeJobWheel.ring_depth_bias(i, n) >= ChangeJobWheel.ring_depth_bias(j, n) - 0.0001,
					"member %d (y%.1f) below member %d (y%.1f) but has LOWER depth bias" % [i, yi, j, yj])
	# The front member (bottom, index 0) has the MAX bias; the top-back member the MIN.
	var top_idx := 0
	var top_y := ChangeJobWheel.ring_position(0, n).y
	for i in n:
		var y := ChangeJobWheel.ring_position(i, n).y
		if y < top_y:
			top_y = y
			top_idx = i
	_expect(ChangeJobWheel.ring_depth_bias(0, n) > ChangeJobWheel.ring_depth_bias(top_idx, n),
		"front member (index 0) must draw OVER the top-back member")
	# Bias stays within [-0.5, +0.5] (a fraction of ONE OT rung so it never crosses into the shadow/orb rung).
	for i in n:
		var b := ChangeJobWheel.ring_depth_bias(i, n)
		_expect(b >= -0.5001 and b <= 0.5001, "depth bias %d out of [-0.5,0.5] (got %.3f)" % [i, b])
	# Tracks rotation: after rotating so member 5 sits at the front, member 5 gets the max bias.
	var max_bias := -1.0
	var max_i := -1
	for i in n:
		var b := ChangeJobWheel.ring_depth_bias(i, n, 5.0)
		if b > max_bias:
			max_bias = b
			max_i = i
	_expect(max_i == 5, "after rotating member 5 to front, member 5 not the max-depth (front) member (got %d)" % max_i)

	if _failed:
		print("[FAIL] ChangeJobWheel model test")
	else:
		print("[PASS] ChangeJobWheel: 19/sex, gender-lock, data-derived, oval + entry-contraction + rotation-offset")
	get_tree().quit()
