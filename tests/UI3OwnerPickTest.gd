extends Node3D
## Guard: CLICK A COLOR ON THE OWNERSHIP MAP -> JUMP TO THAT ROW IN THE DEBUG PAGE.
##
## The map is already a false-color ID buffer (ui3_owner_color.gdshader is unshaded, normal
## blend, alpha-tested, and its header states the intent: "the on-screen color matches the
## page's swatch"). So click->element needs no colliders and no production change: read the
## framebuffer pixel and look the color up. UI3 payload is bare MeshInstance3D with no Area3D,
## and the only physics picking in the codebase works on Area3D, so a collider approach would
## have meant touching production for a debug feature.
##
## MEASURED FIRST, because the whole design rests on it (headful, the real formation/detail
## scene so the compositor engine-fold and camera are in play):
##
##   * Of 18 registered elements, 10 owner colors came back BYTE-EQUAL from the framebuffer.
##   * 6 "misses" are elements the detail overlay OCCLUDES — their color is not drawn at all,
##     which is correct, not a transform failure. You cannot click what is not on screen.
##   * 2 came back off by ONE on a single channel (startmenu.frame 162,193,255 -> 161,193,255;
##     startmenu.cursor 209,177,255 -> 208,177,255). Both have a saturated channel; the error
##     is deterministic across runs.
##
## Hence EXACT first, then a +/-1-per-channel fallback that must resolve to exactly ONE owner.
## That is not a nearest-color match: a genuine gap (the occluded elements were L1 57..104 from
## anything on screen) stays a MISS and is reported as one. Nearest-match was rejected because
## the ramp compresses as N grows -- measured min pairwise L1 over color_for_rank:
##
##   N=18 -> 44    N=30 -> 26    N=50 -> 14    N=80 -> 8    N=120 -> 5    N=200 -> 3
##
## so nearest-matching degrades exactly when the map is most crowded, which is the case the
## user cares about. The +/-1 box is safe to N~120 and AMBIGUOUS beyond it -- and ambiguity is
## reported, never guessed. ALARM stays L1 223 from every owner color at every N, so
## "clicked unowned payload" can never be confused with an owner.
##
## Run: <GODOT> --path . --quit-after 40 res://tests/UI3OwnerPickTest.tscn

const OwnerColors := preload("res://src/debug/UI3OwnerColors.gd")
const OwnerColorMap := preload("res://src/debug/UI3OwnerColorMap.gd")

## Mirrors UI3OwnerColorMap.PICK_CHANNEL_TOLERANCE — stated here so the assertions read as
## claims about the design, not about an import.
const PICK_TOLERANCE := 1

var _passed := 0
var _failed := 0


func _ready() -> void:
	_test_exact_lookup()
	_test_off_by_one_is_recovered()
	_test_a_real_gap_stays_a_miss()
	_test_ramp_never_gets_ambiguous()
	_test_ambiguity_is_reported_not_guessed()
	_test_alarm_is_distinguishable()
	_test_round_trip_over_the_whole_ramp()
	print("\n=== UI3OwnerPickTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] UI3OwnerPickTest")
		get_tree().quit(1)
	else:
		print("[PASS] UI3OwnerPickTest")
		get_tree().quit(0)


## A synthetic palette of `n` owners, exactly as assign_colors would build it.
func _palette(n: int) -> Dictionary:
	var out: Dictionary = {}
	for rank in n:
		out["e%d" % rank] = OwnerColors.color_for_rank(rank, n)
	return out


func _test_exact_lookup() -> void:
	var pal := _palette(18)
	for id: String in pal.keys():
		var got: String = OwnerColorMap.resolve_owner(pal, pal[id])
		_expect(got == id, "exact lookup of %s returned '%s'" % [id, got])


## The measured framebuffer error: one channel off by one.
func _test_off_by_one_is_recovered() -> void:
	var pal := _palette(18)
	for id: String in pal.keys():
		var c: Color = pal[id]
		for chan in 3:
			for delta in [-1.0, 1.0]:
				var nudged := Color(c.r, c.g, c.b)
				nudged[chan] = clampf(c[chan] + delta / 255.0, 0.0, 1.0)
				var got: String = OwnerColorMap.resolve_owner(pal, nudged)
				_expect(got == id,
					"a +/-1 nudge on channel %d of %s must still resolve to it, got '%s'"
						% [chan, id, got])


## The occluded-element case: a color nothing on screen is near must NOT be snapped to the
## closest owner. This is the assertion that keeps this from being a nearest-color match.
func _test_a_real_gap_stays_a_miss() -> void:
	var pal := _palette(18)
	# Mid-grey: the empty-screen color the probe saw, L1 129..342 from every owner.
	var got: String = OwnerColorMap.resolve_owner(pal, Color8(76, 76, 76))
	_expect(got == "", "a color far from every owner must MISS, got '%s'" % got)
	# ...and a color only a FEW steps off is still a miss, not a snap.
	var near: Color = pal["e0"]
	var off := Color(clampf(near.r + 6.0 / 255.0, 0, 1), clampf(near.g - 6.0 / 255.0, 0, 1), near.b)
	_expect(OwnerColorMap.resolve_owner(pal, off) == "",
		"6/255 off an owner is outside the measured error and must MISS, not snap")


## Two halves, because the +/-1 box is only honest if BOTH hold.
##
## (a) The ramp never compresses enough for the box to be ambiguous. A +/-1 box around owner A
## can only contain owner B if they are within 1 on EVERY channel, so a min per-channel
## separation of >=2 makes ambiguity unreachable by construction. Measured, this holds all the
## way to N=200 (the ramp's min per-channel separation there is exactly 2) — which is why the
## real palette never needs the ambiguity branch. This assertion is what would go RED if the
## ramp were ever widened in N or narrowed in hue range past the point where +/-1 is safe.
func _test_ramp_never_gets_ambiguous() -> void:
	for n in [2, 5, 10, 18, 30, 50, 80, 120, 200]:
		var pal := _palette(n)
		var ids: Array = pal.keys()
		var worst := 255
		var pair := ""
		for i in ids.size():
			for j in range(i + 1, ids.size()):
				var sep := _channel_separation(pal[ids[i]], pal[ids[j]])
				if sep < worst:
					worst = sep
					pair = "%s vs %s" % [ids[i], ids[j]]
		_expect(worst > PICK_TOLERANCE,
			("N=%d: min per-channel separation is %d, which is NOT more than the +/-%d pick "
			+ "tolerance — the box can now cover two owners (%s). Either tighten the tolerance "
			+ "or stop growing the ramp.") % [n, worst, PICK_TOLERANCE, pair])


## (b) ...and if it ever DID compress, resolve_owner reports the ambiguity instead of guessing.
## Proven against a hand-built palette, since the real ramp (a) can no longer produce one.
func _test_ambiguity_is_reported_not_guessed() -> void:
	var touching := {
		"a": Color8(100, 100, 100),
		"b": Color8(101, 100, 100),   # 1 away on one channel — inside a's box and vice versa
		"far": Color8(10, 200, 30),
	}
	_expect(OwnerColorMap.resolve_owner(touching, Color8(100, 100, 100)) == "a",
		"an EXACT hit must win outright even when a neighbour is inside the tolerance box")
	var got: String = OwnerColorMap.resolve_owner(touching, Color8(100, 101, 100))
	_expect(got == "",
		"a color inside the +/-1 box of TWO owners must resolve to nothing, got '%s'" % got)
	_expect(OwnerColorMap.resolve_owner(touching, Color8(10, 200, 31)) == "far",
		"an unambiguous neighbour must still resolve through the tolerance")


func _channel_separation(a: Color, b: Color) -> int:
	return maxi(absi(roundi(a.r * 255.0) - roundi(b.r * 255.0)),
		maxi(absi(roundi(a.g * 255.0) - roundi(b.g * 255.0)),
			absi(roundi(a.b * 255.0) - roundi(b.b * 255.0))))


## ALARM is reserved (pure magenta, sat 1.0) and can never be an owner color, so "you clicked
## unowned payload" is a distinct answer from "you clicked nothing".
func _test_alarm_is_distinguishable() -> void:
	for n in [2, 18, 80, 200]:
		var pal := _palette(n)
		_expect(OwnerColorMap.resolve_owner(pal, OwnerColors.ALARM) == "",
			"ALARM must never resolve to an owner (N=%d)" % n)
		_expect(OwnerColorMap.is_alarm_color(OwnerColors.ALARM),
			"ALARM must be recognised as the unowned-payload color")
		_expect(not OwnerColorMap.is_alarm_color(pal["e0"]),
			"an owner color must not be mistaken for ALARM (N=%d)" % n)


## Every rank of a realistic ramp round-trips through its own exact color.
func _test_round_trip_over_the_whole_ramp() -> void:
	for n in [1, 2, 5, 18, 50, 80]:
		var pal := _palette(n)
		var wrong := 0
		for id: String in pal.keys():
			if OwnerColorMap.resolve_owner(pal, pal[id]) != id:
				wrong += 1
		_expect(wrong == 0, "N=%d: %d of %d owner colors failed to round-trip" % [n, wrong, n])


func _expect(ok: bool, msg: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] " + msg)
