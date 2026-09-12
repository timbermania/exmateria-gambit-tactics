extends Node
## COLOUR ON/OFF — the toggle the author asked for, and the mint that makes it mean the same
## thing everywhere (ADR-0089 colour-move amendment; author, 2026-08-20: *"I want to be able
## to toggle color on and off near where all the 'color' stuff is - which is that panel."*).
##
## The toggle itself is a RELOCATION — `EmitterParamRows`' "Colour curves" enum row on
## `emitter_flags_lo` bit 6, moved out of the inspector's flag section into the player's
## transport row. What needs guarding is the half that is new, and it needs a real host
## because every bit of it is a lowering:
##
##   * THE COMMON CASE (591 of the 605 corpus emitters with colour off): the indices already
##     resolve, so the flip alone lights the column and NOTHING is minted. Asserting "the
##     column appeared" without also asserting "no curve was created" would pass on an
##     implementation that minted over perfectly good ROM curves.
##   * THE 14 (E509 and E510, whose `curves.json` has ZERO entries while every emitter still
##     names slot 0 for r, g AND b): three flat curves are minted at the identity so the
##     toggle produces a column here too. This is the arm the author chose over refusing,
##     and E509 is the ONLY place in the corpus it can be exercised.
##   * ONE UNDO for either. The flag flip and up to three mints are one compound edit.
##
## Both arms were red before the fix and each failed DIFFERENTLY, which is why they are
## separate assertions rather than one round trip — see the commit.
##
## THE COLUMN MUST CARRY KEYFRAMES, NOT MERELY EXIST (2026-08-21). Everything above was green
## while the author reported *"when I turn color on the keyframes don't get added"*, because
## the suite stopped at "a column appeared, with rows in it". It had ONE keyframe on it, at
## age 0, for 291 of the 605 corpus colour-off emitters: the Douglas-Peucker import had a
## single 24-keyframe budget spanning all 160 samples, and a ROM curve whose tail oscillates
## spends it there — on ages past `life_n` that the renderer never samples and the column
## neither draws nor lets you click. The floor differs by arm and that is the point: a MINTED
## flat curve genuinely has one control point across its life, so 1 is honest there, while a
## real ROM curve that shows one is the starvation. `ColourKeyframeFitTest` holds the
## mechanism; `tools/census_colour_enable_keyframes.gd` is the instrument.
##
## Run: <GODOT> --path . --quit-after 900 res://tests/EffectStudioColourEnableTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const LifeColumn = preload("res://src/effects/studio/ColourLifeColumn.gd")

var _passed: int = 0
var _failed: int = 0
## Did `_run` reach its end? A GDScript coroutine that hits a runtime error unwinds SILENTLY
## and still reports `0 failed` — which is exactly how the bug this suite guards stayed
## invisible: `apply_compound` threw mid-loop on a member with no `before_raw`, half the
## gesture landed, and nothing anywhere said so.
var _completed: bool = false


func _ready() -> void:
	await _run()
	if not _completed:
		_failed += 1
		print("  [FAIL] _run never reached its end — it aborted mid-run")
	print("\n=== EffectStudioColourEnableTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioColourEnableTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioColourEnableTest")
		get_tree().quit(0)


func _run() -> void:
	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	var page = scn._studio_page
	var e001 := ""
	var e509 := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E001"):
			e001 = d
		if String(d).ends_with("E509"):
			e509 = d
	if e001 == "":
		print("[SKIP] E001 assets not available")
		_passed += 1
		_completed = true
		return

	# --- THE COMMON CASE: the flip alone, and nothing minted ------------------------
	await _arm(page, e001, 0, "E001", false)

	# --- THE 14: three flat curves are minted, at the IDENTITY -----------------------
	if e509 != "":
		await _arm(page, e509, 0, "E509", true)
	else:
		print("  [SKIP] E509 assets not available — the mint arm is unexercised, and it is "
			+ "the ONLY place in the corpus that can exercise it")
		_passed += 1
	_completed = true


## Drive the toggle on emitter `em` of `dir` and assert the whole round trip.
## `expect_mint` says which arm this is: the corpus splits exactly two ways and the two
## have opposite expectations about the curve array, so a shared assertion would have to be
## `>= 0` and would agree with both answers.
func _arm(page, dir: String, em: int, name: String, expect_mint: bool) -> void:
	page._load_effect(dir)
	await _frames(30)
	page._set_root(Target.emitter(em))
	await _frames(24)
	var data = page._effect_data
	if data == null or not (data.emitters is Array) or em >= data.emitters.size():
		print("  [SKIP] %s emitter %d not present" % [name, em])
		_passed += 1
		return
	if bool(data.emitters[em].flags.get("color_curve_enabled", false)):
		print("  [SKIP] %s emitter %d already has colour ON — the enable arm needs an OFF one"
			% [name, em])
		_passed += 1
		return

	var btn = page._colour_enable_btn
	_assert_true(btn != null, "%s: the colour toggle is built" % name)
	_assert_true(not btn.disabled,
		"%s: …and it is LIVE on an emitter with colour off — that is the whole case it "
		% name + "exists for, so a toggle disabled here would be a toggle for nobody")
	_assert_eq(str(btn.text), "Colour: off",
		"%s: …and it SAYS off. With colour off the column is simply absent with nothing "
		% name + "explaining why, which is what sent the author hunting for a button")
	_assert_true(not page._sequence_life_column.visible,
		"%s: no column while colour is off" % name)

	var curves_before: int = data.curves.size()
	btn.button_pressed = true          # emits `toggled` — the author's own gesture
	await _frames(40)
	data = page._effect_data
	_assert_true(bool(data.emitters[em].flags.get("color_curve_enabled", false)),
		"%s: the flag flipped on" % name)
	_assert_eq(str(btn.text), "Colour: on", "%s: …and the button says so" % name)
	# THE ASSERTION THE WHOLE ITEM IS ABOUT. "The flag flipped" is not the feature; a column
	# to author on is. On the 14 the flag flipped and no column appeared, and the toggle read
	# as broken — which is the thing the author was asked to choose about.
	_assert_true(page._sequence_life_column.visible,
		"%s: TURNING COLOUR ON PRODUCES A COLUMN" % name)
	_assert_true(page._sequence_life_rows.size() > 0,
		"%s: …with rows in it (%d)" % [name, page._sequence_life_rows.size()])
	# …AND WITH KEYFRAMES ON IT. This assertion is the one that was missing, and its absence
	# is exactly how the 2026-08-21 report — *"when I turn color on the keyframes don't get
	# added"* — shipped under a green suite: "the flag flipped", "a column appeared" and
	# "it has rows" were all true while the column carried a single keyframe at age 0 and
	# nothing else. `_colour_keyframes` is the page's own copy of what the track draws, and
	# the count that matters is the one INSIDE the life — the fit spans all 160 samples but
	# the column's domain is `life_n`, and a keyframe past it is neither drawn nor clickable.
	var live_kfs: int = 0
	for kf in page._colour_keyframes:
		if LifeColumn.row_of_frame(int(kf["frame"]), page._sequence_life_rows) >= 0:
			live_kfs += 1
	# A minted curve is FLAT, so one control point across the life is the truth; E001's is a
	# real ROM curve with structure in its 10-frame life, and one keyframe there is the bug.
	var floor_kfs: int = 1 if expect_mint else 2
	_assert_true(live_kfs >= floor_kfs,
		"%s: …AND KEYFRAMES ON IT — %d of %d are inside the life, wanted >= %d. A column with "
		% [name, live_kfs, page._colour_keyframes.size(), floor_kfs]
		+ "one keyframe at age 0 is what \"the keyframes don't get added\" looks like")
	var minted: int = data.curves.size() - curves_before
	if expect_mint:
		_assert_eq(minted, 3,
			"%s: THREE curves were minted, one per channel (%d). The corpus's 14 point every "
			% [name, minted] + "channel at slot 0 against an EMPTY curve table, so a mint "
			+ "that trusts `site_index` makes one curve and calls the other two done")
		for ch in ["r", "g", "b"]:
			var c = data.get_curve(int(data.emitters[em].color_curves.get(ch, -1)))
			_assert_true(c != null and not c.samples.is_empty(),
				"%s: channel %s resolves to a real curve now" % [name, ch])
			if c != null and not c.samples.is_empty():
				_assert_true(absf(c.samples[0] - 1.0) < 0.005,
					"%s: …flat at the IDENTITY (%.3f). The render is `ALBEDO = S * curve` "
					% [name, c.samples[0]] + "and a disabled emitter modulates by white, so "
					+ "1.0 is exactly the untinted picture — nothing changes until authored")
	else:
		_assert_eq(minted, 0,
			"%s: NOTHING was minted — this emitter's indices already resolved, and minting "
			% name + "over good ROM curves would be a silent data loss that still lit a column")

	# --- ONE UNDO ---------------------------------------------------------------------
	page._undo()
	await _frames(40)
	data = page._effect_data
	_assert_true(not bool(data.emitters[em].flags.get("color_curve_enabled", false)),
		"%s: ONE undo puts the flag back" % name)
	_assert_eq(data.curves.size(), curves_before,
		"%s: …and takes any minted curve with it (%d, was %d) — the flag flip and the mints "
		% [name, data.curves.size(), curves_before] + "are ONE compound edit, not four")


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % msg)


func _assert_eq(a, b, msg: String) -> void:
	_assert_true(a == b, "%s (got %s, want %s)" % [msg, str(a), str(b)])
