extends Node3D

## The Change-Job COMMIT cutscene MODEL — every per-frame quantity, pinned against the
## byte-exact ROM measurements in `research/working_documents/CHANGE_JOB_COMMIT.md`.
##
## The cutscene is a 240-frame (4.00 s @ 60 Hz) self-clocked beat that never leaves the
## Change-Job screen; the job is written only on the final frame. Four independent mechanisms
## run concurrently (chrome cut + band close, gouraud tint ramp, cylinder, pixel dissolve), so
## this guard checks each as a pure function of the frame counter `c92e` — which is exactly how
## the ROM computes them, and what makes them testable without a single rendered frame.
##
## Oracle rows quoted below are the spec's own `[dynamic]` savestate reads
## (`formation_changejob_commit_ss{0..4}`); a failure here means the port drifted off the ROM.

const Cutscene = preload("res://src/ui3/changejob/ChangeJobCommitCutscene.gd")

var _failed := false


func _ready() -> void:
	_clock_and_phases()
	_band_close()
	_gouraud_ramp()
	_cylinder_envelope()
	_cylinder_stripes()
	_the_skip()
	_the_dissolve()

	if _failed:
		print("[FAIL] ChangeJobCommitCutscene test")
	else:
		print("[PASS] ChangeJobCommitCutscene: 240-frame clock + phases, the band's -12/frame close, the four-hue gouraud ramp (byte-exact at ss1/ss2/ss3/ss4), the cylinder envelope + 64 stripes, the [40,220] skip, and the 480-cell dissolve exhausted exactly")
	get_tree().quit()


## §12: 240 frames total; phase 1 spans c92e 1..219, phase 2 (relax) 220..239, done at 240.
func _clock_and_phases() -> void:
	_eq(Cutscene.DURATION, 240, "total duration")
	_eq(Cutscene.RELAX_START, 220, "phase-2 (relax) start")

	var cut := Cutscene.new()
	_expect(not cut.is_running(), "a fresh cutscene reports running before begin()")
	_eq(cut.phase(), Cutscene.Phase.IDLE, "phase before begin")

	cut.begin(1234)
	_expect(cut.is_running(), "begin() did not start the cutscene")
	_eq(cut.frame(), 0, "frame at begin")
	_eq(cut.phase(), Cutscene.Phase.MAIN, "phase at begin")

	for _i in 219:
		cut.step()
	_eq(cut.frame(), 219, "frame after 219 steps")
	_eq(cut.phase(), Cutscene.Phase.MAIN, "phase at c92e=219 (still main)")
	cut.step()
	_eq(cut.frame(), 220, "frame at relax start")
	_eq(cut.phase(), Cutscene.Phase.RELAX, "phase at c92e=220")
	_expect(cut.is_running(), "the cutscene ended at the relax boundary instead of 240")

	for _i in 19:
		cut.step()
	_eq(cut.frame(), 239, "frame before the last step")
	_expect(cut.is_running(), "ended one frame early")
	_expect(cut.step(), "the step onto frame 240 did not report the APPLY")
	_eq(cut.frame(), 240, "final frame")
	_expect(not cut.is_running(), "the cutscene is still running at c92e=240")
	_eq(cut.phase(), Cutscene.Phase.IDLE, "phase after the apply")


## §6: the band is NOT a commit effect — clearing the chrome flag closes it on a fixed ramp,
## level 120 -> 0 at -12/frame over 10 frames, with row k = max(0, level - 12k) falling off
## from the centre block outward. `[dynamic]` c92e 0..10 read 120,108,96,...,12,0.
func _band_close() -> void:
	_eq(Cutscene.BAND_LEVEL_MAX, 120, "band level at full")
	_eq(Cutscene.BAND_STEP, 12, "band ramp step")
	var want := [120, 108, 96, 84, 72, 60, 48, 36, 24, 12, 0]
	for f in want.size():
		_eq(Cutscene.band_level(f), want[f], "band level at c92e=%d" % f)
	_eq(Cutscene.band_level(20), 0, "band level stays 0 past the close")
	# `[dynamic]` ss1's 19 TILE prims read 96,84,72,60,48,36,24,12,0,0 centre-outward.
	var rows: Array = []
	for k in 10:
		rows.append(Cutscene.band_row_level(96, k))
	_eq(rows, [96, 84, 72, 60, 48, 36, 24, 12, 0, 0], "band row falloff off level 96")
	# The port drives the shader with a 0..1 factor, not the raw 0..120 level.
	_expect(is_equal_approx(Cutscene.band_factor(0), 1.0), "band factor at c92e=0")
	_expect(is_equal_approx(Cutscene.band_factor(5), 0.5), "band factor at c92e=5")
	_expect(is_equal_approx(Cutscene.band_factor(10), 0.0), "band factor at c92e=10")


## §7: four RGB triples seeded neutral (0x80), stepped +-1/frame, driving corners to
## RED / GREEN / BLUE / YELLOW while the other channels crush. Phase 2 walks all twelve back
## toward 0x80 by 1/frame. The four oracle rows are byte-exact.
func _gouraud_ramp() -> void:
	_eq(Cutscene.gouraud_at(0), _bytes([0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80]),
		"gouraud seed (the commit trigger's 12 x 0x80)")
	# ss1, c92e = 1
	_eq(Cutscene.gouraud_at(1), _bytes([0x81, 0x7F, 0x7F, 0x7F, 0x81, 0x7F, 0x7F, 0x7F, 0x81, 0x81, 0x81, 0x7F]),
		"gouraud at ss1 (c92e=1)")
	# ss2, c92e = 10
	_eq(Cutscene.gouraud_at(10), _bytes([0x8A, 0x76, 0x76, 0x76, 0x8A, 0x76, 0x76, 0x76, 0x8A, 0x8A, 0x8A, 0x76]),
		"gouraud at ss2 (c92e=10)")
	# ss3, c92e = 175 — the "up" bytes clamped at 0xFF since frame 127, the rest turned around
	_eq(Cutscene.gouraud_at(175), _bytes([0xFF, 0x33, 0x33, 0x33, 0xFF, 0x33, 0x33, 0x33, 0xFF, 0xFF, 0xFF, 0x33]),
		"gouraud at ss3 (c92e=175)")
	# ss4, c92e = 240 — end of phase 1 (0xFF/0x5F) plus 20 relax steps
	_eq(Cutscene.gouraud_at(240), _bytes([0xEB, 0x73, 0x73, 0x73, 0xEB, 0x73, 0x73, 0x73, 0xEB, 0xEB, 0xEB, 0x73]),
		"gouraud at ss4 (c92e=240)")
	# The tint peaks where the up-bytes saturate (§12).
	_eq(Cutscene.gouraud_at(Cutscene.TINT_PEAK)[0], 0xFF, "the R corner saturates at the tint peak")
	_eq(Cutscene.gouraud_at(Cutscene.TINT_PEAK - 1)[0], 0xFE, "the R corner is NOT saturated a frame early")


## §9: R = X radius, S = the vertical offset. Entry c92e 0..19 (R 0->19, S 160->8), steady
## 20..220, exit 221..239 (R 19->1, S 8->152) — the exit is the entry's arithmetic mirror.
func _cylinder_envelope() -> void:
	_eq(Cutscene.cylinder_radius(0), 0, "R at c92e=0")
	_eq(Cutscene.cylinder_offset(0), 160, "S at c92e=0")
	_eq(Cutscene.cylinder_radius(19), 19, "R at the end of the entry")
	_eq(Cutscene.cylinder_offset(19), 8, "S at the end of the entry")
	_eq(Cutscene.cylinder_radius(20), 20, "R at the steady state")
	_eq(Cutscene.cylinder_offset(20), 0, "S at the steady state")
	_eq(Cutscene.cylinder_radius(175), 20, "R mid-steady")
	_eq(Cutscene.cylinder_offset(220), 0, "S at the last steady frame")
	_eq(Cutscene.cylinder_radius(221), 19, "R at the first exit frame")
	_eq(Cutscene.cylinder_offset(221), 8, "S at the first exit frame")
	_eq(Cutscene.cylinder_radius(239), 1, "R at the last exit frame")
	_eq(Cutscene.cylinder_offset(239), 152, "S at the last exit frame")


## §9: 64 stripes on a computed rcos/rsin ring, each a vertical bar black->magenta (screen top
## down to Ytop) then magenta->black (Ytop+1 down to Ybot). At steady state the packet fit is
## exact: centre x 128, half-width 20, magenta min Ytop+1 = 73, black max y = 92, span 64.
func _cylinder_stripes() -> void:
	_eq(Cutscene.STRIPES, 64, "stripe count")
	var xs: Array = []
	var ytops: Array = []
	var ybots: Array = []
	for k in Cutscene.STRIPES:
		var s: Dictionary = Cutscene.stripe_at(k, 175)
		xs.append(s["x"])
		ytops.append(s["y_top"])
		ybots.append(s["y_bot"])
		_eq(s["y_bot"] - s["y_top"], 64, "stripe %d span at steady state" % k)
	var xmin: int = xs.min()
	var xmax: int = xs.max()
	_eq((xmin + xmax) / 2, 128, "cylinder centre x")
	_eq((xmax - xmin) / 2, 20, "cylinder half-width at steady state (R=20)")
	_eq(int(ytops.min()) + 1, 73, "magenta min Ytop+1 (= (146-10)-64+1)")
	_eq(int(ytops.max()), 92, "black max y (= (146+10)-64)")
	# The spin: theta advances 4/4096 per frame, so the 64-stripe pattern repeats every 16 frames.
	_eq(Cutscene.VISUAL_REPEAT, 16, "visual repeat period")
	# 16 frames of spin == exactly one stripe step (16 x 4 = 0x40), so stripe k slides into
	# where stripe k-1 was. That fast shimmer, not the 1024-frame revolution, is what you see.
	_eq(Cutscene.stripe_at(1, 175)["x"], Cutscene.stripe_at(0, 175 + Cutscene.VISUAL_REPEAT)["x"],
		"the stripe pattern did not repeat after 16 frames")
	# The colours: black -> magenta down to Ytop, magenta -> black down to Ybot.
	_eq(Cutscene.STRIPE_MAGENTA, Color8(255, 0, 255), "stripe peak colour")


## §10: the skip latch is one frame AHEAD of the jump; the window is c92e in [40,220] and the
## target is 220. A press before 40 is remembered and fires the moment the clock reaches 40.
func _the_skip() -> void:
	_eq(Cutscene.SKIP_WINDOW_LO, 40, "skip window low")
	_eq(Cutscene.SKIP_WINDOW_HI, 220, "skip window high")

	var cut := _at_frame(175)
	cut.request_skip()
	cut.step()
	_eq(cut.frame(), 176, "the skip JUMPED on the latch frame (it is one frame ahead)")
	_expect(cut.skip_latched(), "the skip did not latch")
	cut.step()
	_eq(cut.frame(), Cutscene.SKIP_WINDOW_HI, "the skip did not jump the clock to 220")

	# Pressed before the window opens: remembered, fires the moment the clock reaches 40.
	var early := _at_frame(5)
	early.request_skip()
	early.step()
	_expect(early.skip_latched(), "an early press did not latch")
	_eq(early.frame(), 6, "an early press jumped before the window opened")
	while early.frame() < 39:
		early.step()
	_eq(early.frame(), 39, "the clock overshot the window opening")
	# The increment that LANDS on 40 opens the window, and the latched press fires the same step.
	early.step()
	_eq(early.frame(), Cutscene.SKIP_WINDOW_HI, "a latched early press did not fire at frame 40")

	# Past the window: the relax phase plays out, no jump backward.
	var late := _at_frame(225)
	late.request_skip()
	late.step()
	late.step()
	_eq(late.frame(), 227, "a press past the window rewound the clock")


## §8: a shuffled permutation of the sprite's 480 cells, consumed 2 per frame, so the revealed
## fraction walks 0 -> 100% in random order over exactly 240 frames. Each cell is TWO horizontal
## pixels (480 bytes at 4bpp = 960 px = 24x40), which is why the dissolve reads granular.
func _the_dissolve() -> void:
	_eq(Cutscene.CELLS, 480, "dissolve cell count")
	_eq(Cutscene.CELL_PX, 2, "pixels per dissolve cell (4bpp packs two per byte)")
	_eq(Cutscene.SPRITE_W * Cutscene.SPRITE_H, Cutscene.CELLS * Cutscene.CELL_PX, "sprite is 24x40")
	_eq(Cutscene.REVEAL_PER_FRAME * Cutscene.DURATION, Cutscene.CELLS,
		"2 cells/frame x 240 frames must exhaust the permutation EXACTLY")

	var cut := Cutscene.new()
	cut.begin(99)
	var perm: PackedInt32Array = cut.shuffle()
	_eq(perm.size(), Cutscene.CELLS, "shuffle table size")
	var seen := {}
	for v in perm:
		seen[v] = true
	_eq(seen.size(), Cutscene.CELLS, "the shuffle is not a permutation of 0..479")
	_expect(perm != _identity_desc(), "the shuffle table is still the unshuffled identity")

	_eq(cut.revealed_count(), 0, "cells revealed before the first step")
	cut.step()
	_eq(cut.revealed_count(), 2, "cells revealed after one step")
	while cut.is_running():
		cut.step()
	_eq(cut.revealed_count(), Cutscene.CELLS, "the dissolve did not finish fully revealed")
	var mask: PackedByteArray = cut.reveal_mask()
	_eq(mask.size(), Cutscene.CELLS, "reveal mask size")
	for i in mask.size():
		if mask[i] == 0:
			_expect(false, "cell %d was never revealed" % i)
			break

	# Same seed, same dissolve — the model is deterministic, so a guard can pin an exact frame.
	var a := Cutscene.new(); a.begin(7)
	var b := Cutscene.new(); b.begin(7)
	_eq(a.shuffle(), b.shuffle(), "the same seed produced a different shuffle")


# --- helpers -----------------------------------------------------------------------------

func _at_frame(f: int) -> Cutscene:
	var cut := Cutscene.new()
	cut.begin(1)
	while cut.frame() < f:
		cut.step()
	return cut


func _identity_desc() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in Cutscene.CELLS:
		out.append(Cutscene.CELLS - 1 - i)
	return out


func _bytes(vals: Array) -> PackedByteArray:
	var out := PackedByteArray()
	for v in vals:
		out.append(v)
	return out


func _eq(got, want, what: String) -> void:
	if got != want:
		print("[FAIL] %s: got %s, want %s" % [what, got, want])
		_failed = true


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] %s" % msg)
		_failed = true
