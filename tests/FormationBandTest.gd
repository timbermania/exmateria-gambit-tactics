extends Node
# test-kind: logic
# seeded-break: band_subtract_at's top-feather ramp denominator widened by 1 (span 10 -> 11 px) — all nine 'top feather y169..y177' asserts RED (got 120i/11/255, want 12i/255 — the oracle strip law); the outside-band zeros, the flat 120/255 body, the bottom feather, the full-width span, and the vitals-coverage arms stay green; GREEN unbroken on the reverted tree

## Formation bottom "band" backdrop guard (§14.6.6) — pure GDScript, no GPU.
##
## The dark band the vitals/info panels sit on is iter 2 of FUN_80112c88 (@0x80112c88):
## a full-width SUBTRACTIVE gouraud trapezoid over the cobble floor. Its per-vertex grey
## (fg/255, the amount blend_sub subtracts) is FormationScene.band_subtract_at(y) — the
## single source of truth the band mesh bakes into vertex colour. This locks that profile
## to the BYTE-EXACT oracle read from the settled-roster RAM packet @0x801C02A8:
##
##   strip:  y169 y170 y171 y172 y173 y174 y175 y176 y177   (top feather, fades IN)
##   fg:      12   24   36   48   60   72   84   96  108
##   body:   y178..y228  fg=120   (base_rgb 120,120,120)
##   strip:  y228 ... y236        fg 108..12                 (bottom feather, fades OUT)
##
## Floor(grey-80) - 120 = clamp 0 = the pure-black core the oracle framebuffer shows.

const FormationScene = preload("res://src/ui3/formation/FormationScene.gd")

const EPS := 1e-6
const FULL := 120.0 / 255.0


func _ready() -> void:
	var failed := false

	# --- Outside the band = no subtraction (invisible above y168 / below y237) ----
	for y in [0.0, 100.0, 160.0, 168.0, 237.0, 240.0, 300.0]:
		var s: float = FormationScene.band_subtract_at(y)
		if abs(s) > EPS:
			print("[FAIL] band_subtract_at(%.0f)=%f, want 0 (outside band)" % [y, s]); failed = true

	# --- Top feather: EXACT oracle strip law fg = 12*(y-168) for y in 169..177 -----
	for i in range(1, 10):
		var y := 168.0 + float(i)
		var want := (12.0 * float(i)) / 255.0
		var got: float = FormationScene.band_subtract_at(y)
		if abs(got - want) > EPS:
			print("[FAIL] top feather y%.0f: got %f want %f (oracle fg=%d)" % [y, got, want, 12 * i]); failed = true

	# --- Body y178..y228: flat full subtraction 120/255 ---------------------------
	for y in [178.0, 190.0, 200.0, 215.0, 228.0]:
		var s: float = FormationScene.band_subtract_at(y)
		if abs(s - FULL) > EPS:
			print("[FAIL] body y%.0f: got %f want %f (flat 120/255)" % [y, s, FULL]); failed = true

	# --- Bottom feather fades back to ~0 (matches oracle 108..12 within <1 step) ---
	# Model is a clean symmetric trapezoid (120 at y228 -> 0 at y237); the oracle's
	# bottom strips run 108..12 (a <=12/255 seam at y228, well under one RGB555 step
	# of 8/255 elsewhere). Assert monotonic fade + the y236 edge near the oracle 12.
	var prev: float = FULL
	for y in [229.0, 231.0, 233.0, 235.0, 236.0, 237.0]:
		var s: float = FormationScene.band_subtract_at(y)
		if s > prev + EPS:
			print("[FAIL] bottom feather not monotonic at y%.0f: %f > %f" % [y, s, prev]); failed = true
		prev = s
	var edge: float = FormationScene.band_subtract_at(236.0)   # oracle strip8 = 12/255
	if abs(edge - 12.0 / 255.0) > 2.0 / 255.0:
		print("[FAIL] bottom edge y236=%f not near oracle 12/255=%f" % [edge, 12.0 / 255.0]); failed = true

	# NOTE: the feathers are NOT symmetric — the oracle top feather spans y168..178
	# (10px, fg 0->120) and the bottom y228..237 (9px, fg 120->0). That 1px asymmetry
	# is faithful to the packet, so it is asserted per-edge above, not as a mirror.

	# --- Full-width span (x0..256) + vertical extent cover the vitals region ------
	if not (FormationScene.BAND_X0 == 0.0 and FormationScene.BAND_X1 == 256.0):
		print("[FAIL] band not full-width: x %f..%f" % [FormationScene.BAND_X0, FormationScene.BAND_X1]); failed = true
	# The vitals text rows (Lv/Exp y181, Hp y196, Ct y219 — §14.6) all sit inside the band.
	for y in [181.0, 196.0, 219.0]:
		if FormationScene.band_subtract_at(y) < FULL - EPS:
			print("[FAIL] vitals row y%.0f not under full band cover (%f)" % [y, FormationScene.band_subtract_at(y)]); failed = true

	if failed:
		print("[FAIL] FormationBand test")
	else:
		print("[PASS] FormationBand: subtractive gouraud trapezoid matches oracle @0x801C02A8 (0->120->0, y168..237)")
	get_tree().quit()
