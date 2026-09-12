extends Node3D

## Slice 1 (ADR-0088 Amendment 4 §1/§3) — the screen-anchored rect answer form + the
## no-empty-DERIVED audit, the core machinery all five backdrops convert onto.
##   A. screen_anchored() → criteria() rect row is Source.SCREEN_ANCHORED, mints no slug,
##      exposes no drivers; the element still places at screen origin (a visual no-op vs the
##      old derived([], Rect2(0,0,SCREEN)) sentinel — same origin, honest source).
##   B. empty_derived_violations(): a derived([]) / bare-Callable rect is flagged BY ID;
##      screen_anchored, authored, and derived-WITH-drivers are exempt.
##   C. check_empty_derived(): an unlisted offender fails naming the id; a listed one passes
##      (the shrink-only ratchet's per-screen check, seeded with the current offenders).
##
## Run: <GODOT> --path . --quit-after 10 res://tests/UI3ScreenAnchoredAuditTest.tscn

var _failed := 0
var _passed := 0


func _ready() -> void:
	var sa := UI3Element.new({
		"id": "t.sa",
		"rect": UI3Element.screen_anchored(),
		"transition": UI3Element.Transition.NONE,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})
	add_child(sa)
	var empty := UI3Element.new({
		"id": "t.empty",
		"rect": UI3Element.derived([], func() -> Rect2: return Rect2(10, 20, 30, 40)),
		"transition": UI3Element.Transition.NONE,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})
	add_child(empty)
	# BIND the synthetic driver before subscribing to it. `t.driver` is invented by this
	# file and owned by nothing, and `Tune.on_update`'s contract has always been that the
	# slug is *"already registered by a `bind`"* — it carries no literal and reads the
	# registered default to coalesce. That contract went unenforced until `on_update` grew
	# the assert `get_value` always had, and this is the ONLY place in 706 tests that was
	# violating it: every production `derived` driver is a real slug its owner binds.
	# Without this line the subscribe raises a SCRIPT ERROR and the runner reports THREW
	# while the assertions below all still pass — a verdict that says nothing is wrong.
	Tune.bind("t.driver", 0.0)
	var driven := UI3Element.new({
		"id": "t.driven",
		"rect": UI3Element.derived(["t.driver"], func() -> Rect2: return Rect2(1, 2, 3, 4)),
		"transition": UI3Element.Transition.NONE,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})
	add_child(driven)
	var authored := UI3Element.new({
		"id": "t.authored",
		"rect": Rect2(5, 6, 7, 8),
		"transition": UI3Element.Transition.NONE,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})
	add_child(authored)
	await get_tree().process_frame

	# --- A. screen_anchored criteria --------------------------------------------
	var row := _rect_row(sa)
	_expect(row.get("source") == UI3Element.Source.SCREEN_ANCHORED,
		"screen_anchored rect row must report Source.SCREEN_ANCHORED, got %s" % row.get("source"))
	_expect((row.get("drivers", []) as Array).is_empty(), "screen_anchored row exposes no drivers")
	_expect(sa.position.length() < 0.001,
		"screen_anchored element must place at screen origin (0,0,0) at default, got %s" % sa.position)

	# --- Group-nudge origin knob (ADR-0088 Amdt 4 §1, Option C) ------------------
	# screen_anchored mints ONE editable <id>.origin (Vector2 px) that translates the whole
	# assembly — every payload rides. Default (0,0) is a visual no-op.
	_expect(String(row.get("slug")) == "t.sa.origin",
		"screen_anchored rect row must carry the <id>.origin group-nudge slug, got %s" % [row])
	_expect(Tune.is_registered("t.sa.origin"), "screen_anchored must mint an editable <id>.origin knob")
	Tune.set_value("t.sa.origin", Vector2(8, 5))
	_expect(sa.position.is_equal_approx(Vector3(8 * 0.04, -5 * 0.04, 0.0)),
		"scrubbing <id>.origin must translate the assembly by screen_to_world(px), got %s" % sa.position)
	Tune.clear("t.sa.origin")

	# --- B. empty_derived_violations --------------------------------------------
	var v: Array = UI3RegistrationAudit.empty_derived_violations(self)
	_expect(v.has("t.empty"), "the empty-drivers derived rect must be flagged, got %s" % [v])
	_expect(not v.has("t.sa"), "screen_anchored must be exempt from the empty-derived audit")
	_expect(not v.has("t.driven"), "derived-WITH-drivers must be exempt")
	_expect(not v.has("t.authored"), "an authored literal must be exempt")

	# --- C. check_empty_derived -------------------------------------------------
	var listed: Array = UI3RegistrationAudit.check_empty_derived(self, ["t.empty"])
	_expect(listed.is_empty(), "a listed offender must pass, got %s" % [listed])
	var unlisted: Array = UI3RegistrationAudit.check_empty_derived(self, [])
	_expect(unlisted.size() == 1 and String(unlisted[0]).contains("t.empty"),
		"an unlisted empty-derived rect must fail naming the id, got %s" % [unlisted])

	print("\n=== UI3ScreenAnchoredAuditTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] UI3ScreenAnchoredAuditTest")
		get_tree().quit(1)
	else:
		print("[PASS] UI3ScreenAnchoredAuditTest")
		get_tree().quit(0)


func _rect_row(e: UI3Element) -> Dictionary:
	for r: Dictionary in e.criteria():
		if String(r["field"]) == "rect":
			return r
	return {}


func _expect(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		push_error("[UI3ScreenAnchoredAuditTest] " + msg)
		print("  [x] " + msg)
