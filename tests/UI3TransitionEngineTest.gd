extends Node3D

## Guard (ADR-0088 slice 3): the shared transition engine — the ADR-0084 beat player
## extracted, driving elements' open()/close() from their `transition` criterion.
##   A. box_open open(): the BOX_OPEN beat drives _set_aperture through
##      BoxOpenAnimator.rect_at_frame — the center-out scissor, frame 0 = the p=10
##      seed box (the RE'd play_open behavior), settle at frame 8 = full rect +
##      `opened` exactly once.
##   B. close() = the SAME beat reversed (ADR-0084 invariant 1): the aperture walks
##      the open curve backward past frame 0 to the SHUT box, then `closed` fires.
##   C. A delta spike is clamped (MAX_CATCHUP): one oversized advance() cannot
##      teleport the box to settled.
##   D. Transition.NONE / RIDE_PARENT: open()/close() settle instantly (signal, no
##      playback) — an ANSWER, not a missing beat.
##   E. Boot reversibility audit: an element naming an unregistered beat, and a beat
##      with no reverse path, are both reported.
##   F. Per-beat CADENCE audit (ADR-0097 §1): the BEAT range-checks its own curve
##      vocabulary (validate_spec is static and beat-blind, so it cannot), and an authored
##      cadence mints an ENUM-hinted knob so the F3 row is a token dropdown.
##   H. IMMEDIATE (ADR-0097 §3): the identity curve is already finished at frame 0, so the
##      play settles INSIDE play() — no rendered frame at full size, the settle signal still
##      emitted (the free-on-closed teardown depends on it), and the landed rect exact.
##   I. The call-site override (ADR-0097 §4): one invocation's cadence, same type as the
##      authored value, dropped when the play ends — it is situational, never a standing
##      element property, so the NEXT play must read the authored answer again.
##   J. The MOVE slot (ADR-0097 §5): `place_at` is the WHERE verb and it now has a beat.
##      Absent/NONE = SNAP, exactly what place_at did before, so every existing caller is
##      unchanged; Move.SLIDE walks the §15.1 curve between the two homes and lands the
##      destination pixel-exact. A move needs no reverse — its inverse is another place_at.
##   G. The ADR-0182 house rule survives the ADR-0097 rewrite: DEFAULT means normal on an
##      open (settles at 8) and fast on a close (shut after 5), and per-verb authoring
##      escalates ONE verb without touching the other.
##
## Worked-example literals from the ROM integer math (BoxOpenAnimator.scaled_rect on
## full rect (76,135,174,101)): p=10 → (155,180,17,10); p=60 → (111,155,104,60);
## p=95 → (81,138,165,95).

var _failed := false


func _ready() -> void:
	await _test_box_open_forward()
	await _test_box_close_reverse()
	await _test_aperture_pad()
	_test_catchup_clamp()
	_test_instant_transitions()
	await _test_reversibility_audit()
	await _test_cadence_audit()
	await _test_house_rule_per_verb()
	await _test_immediate_is_synchronous()
	await _test_call_site_override()
	await _test_move_beat()

	if _failed:
		push_error("[FAIL] UI3TransitionEngineTest")
		get_tree().quit(1)
	else:
		print("[PASS] UI3TransitionEngineTest")
		get_tree().quit(0)


func _test_box_open_forward() -> void:
	var elem := _box_element("t.tr.open")
	add_child(elem)
	await get_tree().process_frame

	var opened_count := [0]
	elem.opened.connect(func() -> void: opened_count[0] += 1)

	elem.open()
	_expect(not elem.is_settled(), "open() must enter the beat (not settled at frame 0)")
	_expect(elem.aperture() == Rect2i(155, 180, 17, 10),
		"open() must drive frame 0 = the p=10 seed box (155,180,17,10), got %s" % elem.aperture())

	UI3Registry.transition_engine_step()   # frame 1: the curve holds p=10
	_expect(elem.aperture() == Rect2i(155, 180, 17, 10),
		"frame 1 must hold p=10 (155,180,17,10), got %s" % elem.aperture())
	UI3Registry.transition_engine_step()   # frame 2: p=60
	_expect(elem.aperture() == Rect2i(111, 155, 104, 60),
		"frame 2 must be the p=60 rect (111,155,104,60), got %s" % elem.aperture())

	for i in range(6):   # frames 3..8: settle at 8
		UI3Registry.transition_engine_step()
	_expect(elem.is_settled(), "box_open must settle at frame 8")
	_expect(elem.aperture() == Rect2i(76, 135, 174, 101),
		"settled aperture must be the full live rect, got %s" % elem.aperture())
	_expect(opened_count[0] == 1, "`opened` must fire exactly once, fired %d" % opened_count[0])
	elem.free()


func _test_box_close_reverse() -> void:
	var elem := _box_element("t.tr.close")
	add_child(elem)
	await get_tree().process_frame

	var closed_count := [0]
	elem.closed.connect(func() -> void: closed_count[0] += 1)

	_expect(elem.is_settled(), "a fresh element must boot settled")
	_expect(elem.aperture() == Rect2i(76, 135, 174, 101),
		"settled boot aperture must be the full rect, got %s" % elem.aperture())

	elem.close()
	_expect(not elem.is_settled(), "close() must enter the reversed beat")
	UI3Registry.transition_engine_step()   # reverse n=1 → forward frame 7 → p=95
	_expect(elem.aperture() == Rect2i(81, 138, 165, 95),
		"close() frame 1 must be the reversed curve's p=95 rect (81,138,165,95), got %s" % elem.aperture())

	for i in range(8):   # n=2..9: past frame 0 to the shut box at n=settle+1
		UI3Registry.transition_engine_step()
	_expect(elem.aperture().size == Vector2i.ZERO,
		"a finished close must shut the aperture, got %s" % elem.aperture())
	_expect(elem.is_settled(), "a finished close must settle")
	_expect(closed_count[0] == 1, "`closed` must fire exactly once, fired %d" % closed_count[0])

	UI3Registry.transition_engine_step()   # idempotent once settled
	_expect(closed_count[0] == 1, "an extra step after settle must not re-fire `closed`")
	elem.free()


## ADR-0088 amendment §4: `aperture_pad` (Vector4 left/top/right/bottom, display px)
## pads THE BOX THE BEAT OPENS OVER — settled aperture = rect.grow_individual(pad) and
## the drive walks rect_at_frame over the PADDED box — never the per-frame reveal, so a
## finished close still ends fully shut. Worked-example literals: rect (76,135,174,101)
## + pad (0,4,0,0) → padded (76,131,174,105); ROM integer math at p=10 → (155,178,17,10),
## p=95 → (81,134,165,99).
func _test_aperture_pad() -> void:
	var elem: UI3Element = UI3Element.new({
		"id": "t.tr.pad",
		"rect": Rect2(76, 135, 174, 101),
		"transition": UI3Element.Transition.BOX_OPEN,
		"open_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		"close_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.OWN_APERTURE,
		"aperture_pad": Vector4(0, 4, 0, 0),
	})
	add_child(elem)
	await get_tree().process_frame

	_expect(elem.aperture() == Rect2i(76, 131, 174, 105),
		"settled boot aperture must be the PADDED box (76,131,174,105), got %s" % elem.aperture())

	elem.open()
	_expect(elem.aperture() == Rect2i(155, 178, 17, 10),
		"open() frame 0 must seed p=10 over the PADDED box (155,178,17,10), got %s" % elem.aperture())
	for i in range(8):
		UI3Registry.transition_engine_step()
	_expect(elem.is_settled(), "padded box_open must still settle at frame 8")
	_expect(elem.aperture() == Rect2i(76, 131, 174, 105),
		"settled open aperture must be the padded box, got %s" % elem.aperture())

	elem.close()
	UI3Registry.transition_engine_step()   # reverse n=1 → forward frame 7 → p=95
	_expect(elem.aperture() == Rect2i(81, 134, 165, 99),
		"close() frame 1 must reverse over the PADDED box (81,134,165,99), got %s" % elem.aperture())
	for i in range(8):
		UI3Registry.transition_engine_step()
	_expect(elem.aperture().size == Vector2i.ZERO,
		"a finished close must end fully SHUT — the pad never props the box open, got %s"
		% elem.aperture())

	# A live-rect move re-derives the settled aperture WITH the pad still applied.
	elem._apply_rect(Rect2(80, 135, 174, 101))
	elem.open()
	for i in range(9):
		UI3Registry.transition_engine_step()
	_expect(elem.aperture() == Rect2i(80, 131, 174, 105),
		"a moved rect must re-derive the padded settled aperture, got %s" % elem.aperture())

	# The pad is an ordinary auto-minted spec field: a scrub re-derives while settled.
	_expect(Tune.is_registered("t.tr.pad.aperture_pad"),
		"aperture_pad must auto-mint its <id>.aperture_pad bind")
	Tune.set_value("t.tr.pad.aperture_pad", Vector4(2, 4, 2, 0))
	_expect(elem.aperture() == Rect2i(78, 131, 178, 105),
		"a pad scrub must re-derive the settled aperture (78,131,178,105), got %s" % elem.aperture())
	Tune.clear("t.tr.pad.aperture_pad")
	elem.free()


func _test_catchup_clamp() -> void:
	var elem := _box_element("t.tr.clamp")
	add_child(elem)
	elem.open()
	UI3Registry.transition_engine_advance(10.0)   # a stall's worth of delta
	_expect(not elem.is_settled(),
		"a single spiked delta must not teleport the box to settled (MAX_CATCHUP)")
	elem.free()


func _test_instant_transitions() -> void:
	for kind: int in [UI3Element.Transition.NONE, UI3Element.Transition.RIDE_PARENT]:
		var elem: UI3Element = UI3Element.new({
			"id": "t.tr.instant",
			"rect": Rect2(10, 20, 30, 40),
			"transition": kind,
			"frame": UI3Element.Frame.NONE,
			"clip": UI3Element.Clip.OWN_APERTURE,
		})
		add_child(elem)
		var log := []
		elem.opened.connect(func() -> void: log.append("opened"))
		elem.closed.connect(func() -> void: log.append("closed"))
		elem.open()
		_expect(elem.is_settled(), "instant open() must settle immediately (kind %d)" % kind)
		elem.close()
		_expect(elem.is_settled(), "instant close() must settle immediately (kind %d)" % kind)
		_expect(log == ["opened", "closed"],
			"instant transitions must still emit settle signals (kind %d), got %s" % [kind, log])
		elem.free()


func _test_reversibility_audit() -> void:
	var errors: Array = UI3Registry.transition_reversibility_errors()
	_expect(errors.is_empty(),
		"the stock registration must audit clean, got %s" % [errors])

	# An element naming a beat nobody registered → reported by name.
	var slider: UI3Element = UI3Element.new({
		"id": "t.tr.slider",
		"rect": Rect2(0, 0, 10, 10),
		"transition": UI3Element.Transition.SLIDE,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
		# Declaring a beat KIND is what requires a cadence per verb (ADR-0097 §2) — whether
		# anyone registered a beat for that kind is the audit's business, not validate_spec's.
		# 0 is DEFAULT in every vocabulary by the UI3Beat convention, which is the only answer
		# available before SLIDE has a beat to name an enum member on.
		"open_cadence": 0,
		"close_cadence": 0,
	})
	add_child(slider)
	var no_beat: Array = UI3Registry.transition_reversibility_errors()
	_expect(no_beat.size() == 1 and String(no_beat[0]).contains("slide"),
		"an element naming an unregistered beat must be reported, got %s" % [no_beat])

	# A registered beat with NO reverse path → reported as irreversible.
	UI3Registry.register_beat(UI3Element.Transition.SLIDE, UI3IrreversibleProbeBeat.new())
	var with_broken: Array = UI3Registry.transition_reversibility_errors()
	_expect(with_broken.size() == 1 and String(with_broken[0]).contains("reverse"),
		"an irreversible beat must be reported by the audit, got %s" % [with_broken])

	UI3Registry.register_beat(UI3Element.Transition.SLIDE, null)   # restore
	slider.free()
	await get_tree().process_frame


## F. The cadence audit is the BEAT's, not validate_spec's (ADR-0097 §1) — there is no
## global curve enum, so only UI3BoxOpenBeat can say that 99 is not one of its curves. The
## same "the beat owns its vocabulary" fact is what makes the knob a token dropdown.
func _test_cadence_audit() -> void:
	var ok: UI3Element = UI3Element.new({
		"id": "t.tr.cad_ok",
		"rect": Rect2(76, 135, 174, 101),
		"transition": UI3Element.Transition.BOX_OPEN,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.OWN_APERTURE,
		"open_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		"close_cadence": UI3BoxOpenBeat.Cadence.NORMAL,
	})
	add_child(ok)
	await get_tree().process_frame
	_expect(UI3Registry.transition_cadence_errors().is_empty(),
		"cadences from the beat's own vocabulary must audit clean, got %s"
		% [UI3Registry.transition_cadence_errors()])

	# The authored cadence mints an ENUM-hinted bind (ADR-0097 Consequences: DEFAULT is an
	# authored value, so it mints a slug like any other literal) — hinted, not a bare int,
	# so the F3 row is a token dropdown and materialise writes `Cadence.NORMAL` back.
	_expect(Tune.is_registered("t.tr.cad_ok.open_cadence"),
		"an authored cadence must mint its <id>.open_cadence bind")
	var meta := Tune.meta_of("t.tr.cad_ok.close_cadence")
	_expect(meta.has("enum") and (meta["enum"] as Dictionary).has("IMMEDIATE"),
		"a cadence knob must carry the BEAT's enum options, got %s" % [meta])
	_expect(String(meta.get("enum_tokens", "")) == "UI3BoxOpenBeat.Cadence",
		"a cadence knob must name the beat's token prefix for materialise, got %s" % [meta])
	ok.free()
	await get_tree().process_frame

	# An int outside the beat's vocabulary passes the static spec validation (which is
	# beat-blind) and is caught HERE — the new audit surface ADR-0097 calls out.
	var bad: UI3Element = UI3Element.new({
		"id": "t.tr.cad_bad",
		"rect": Rect2(76, 135, 174, 101),
		"transition": UI3Element.Transition.BOX_OPEN,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.OWN_APERTURE,
		"open_cadence": 99,
		"close_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
	})
	add_child(bad)
	await get_tree().process_frame
	var errors: Array = UI3Registry.transition_cadence_errors()
	_expect(errors.size() == 1 and String(errors[0]).contains("open_cadence"),
		"a cadence outside the beat's vocabulary must be reported, got %s" % [errors])
	bad.free()
	await get_tree().process_frame


## G. ADR-0182's house rule, restated in ADR-0097's vocabulary: DEFAULT is the AUTHORED
## "use the house rule" answer, and the house rule is per-DIRECTION — an open walks the
## normal 9-frame curve, a close the fast 5-frame one. Authoring one verb must not move the
## other, which is the whole reason cadence moved off the element onto the verb.
func _test_house_rule_per_verb() -> void:
	var beat := UI3BoxOpenBeat.new()
	var elem := _box_element("t.tr.house")
	add_child(elem)
	await get_tree().process_frame
	_expect(beat.settle_frame(elem) == 8,
		"a DEFAULT open must walk the normal curve (settle 8), got %d" % beat.settle_frame(elem))
	_expect(beat.reverse_frames(8, elem) == 5,
		"a DEFAULT close must walk the FAST curve (5 reverse frames), got %d"
		% beat.reverse_frames(8, elem))

	# Escalating the OPEN leaves the close where the house rule put it.
	elem.spec()["open_cadence"] = UI3BoxOpenBeat.Cadence.FAST
	_expect(beat.settle_frame(elem) == 4 and beat.reverse_frames(4, elem) == 5,
		"authoring open_cadence must move ONLY the open (got open %d / close %d)"
		% [beat.settle_frame(elem), beat.reverse_frames(4, elem)])
	# ...and de-escalating the CLOSE is now expressible at all, which `fast: bool` never was.
	elem.spec()["close_cadence"] = UI3BoxOpenBeat.Cadence.NORMAL
	_expect(beat.reverse_frames(4, elem) == 9,
		"authoring close_cadence NORMAL must slow the close to 9 frames, got %d"
		% beat.reverse_frames(4, elem))
	elem.free()
	await get_tree().process_frame


## H. IMMEDIATE settles synchronously (ADR-0097 §3). The observable difference from "settles
## on the next step" is one rendered frame at full size — invisible in a screenshot, fatal to
## the claim that the system has ONE instant behaviour — so this asserts the state the caller
## sees the instant open()/close() returns, not the state after a step.
func _test_immediate_is_synchronous() -> void:
	var elem: UI3Element = UI3Element.new({
		"id": "t.tr.now",
		"rect": Rect2(76, 135, 174, 101),
		"transition": UI3Element.Transition.BOX_OPEN,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.OWN_APERTURE,
		"open_cadence": UI3BoxOpenBeat.Cadence.IMMEDIATE,
		"close_cadence": UI3BoxOpenBeat.Cadence.IMMEDIATE,
	})
	add_child(elem)
	await get_tree().process_frame
	var log := []
	elem.opened.connect(func() -> void: log.append("opened"))
	elem.closed.connect(func() -> void: log.append("closed"))

	elem.open()
	_expect(elem.is_settled(), "an IMMEDIATE open must be settled the instant open() returns")
	_expect(log == ["opened"], "an IMMEDIATE open must emit `opened` synchronously, got %s" % [log])
	# The identity curve's integer math is exact (w·100/100 = w; x + w/2 − w·100/200 = x), so
	# it lands the settled rect ITSELF — never a rect rounded through the curve.
	_expect(elem.aperture() == Rect2i(76, 135, 174, 101),
		"an IMMEDIATE open must land the exact settled rect, got %s" % elem.aperture())
	_expect(not UI3Registry.transition_engine_is_playing(elem),
		"an IMMEDIATE open must leave no play behind in the engine")

	elem.close()
	_expect(elem.is_settled(), "an IMMEDIATE close must be settled the instant close() returns")
	_expect(log == ["opened", "closed"],
		"an IMMEDIATE close must emit `closed` synchronously — the free-on-closed teardown "
		+ "leaks the node without it, got %s" % [log])
	_expect(elem.aperture().size == Vector2i.ZERO,
		"an IMMEDIATE close must land fully SHUT, got %s" % elem.aperture())

	UI3Registry.transition_engine_step()   # nothing left to step; no second emit
	_expect(log == ["opened", "closed"],
		"a step after an IMMEDIATE settle must not re-fire, got %s" % [log])

	# A cadence is per VERB, so IMMEDIATE on ONE verb must leave the other walking its curve.
	elem.spec()["open_cadence"] = UI3BoxOpenBeat.Cadence.DEFAULT
	elem.open()
	_expect(not elem.is_settled(),
		"a DEFAULT open beside an IMMEDIATE close must still walk its curve")
	for i in range(8):
		UI3Registry.transition_engine_step()
	_expect(elem.is_settled(), "the DEFAULT open must still settle at frame 8")
	elem.free()
	await get_tree().process_frame


## I. A cadence passed to open()/close() wins for THAT play only. The load-bearing half is
## the second one: an override that stuck would silently re-cadence every later open, which is
## exactly the standing-property shape ADR-0097 §4 refuses.
func _test_call_site_override() -> void:
	var elem := _box_element("t.tr.override")   # authored DEFAULT/DEFAULT
	add_child(elem)
	await get_tree().process_frame
	var closes := [0]
	elem.closed.connect(func() -> void: closes[0] += 1)

	# Snap THIS close, without the element being authored to snap.
	elem.close(UI3BoxOpenBeat.Cadence.IMMEDIATE)
	_expect(elem.is_settled() and closes[0] == 1,
		"a close() override must settle this play immediately (settled %s, closes %d)"
		% [elem.is_settled(), closes[0]])
	_expect(elem.aperture().size == Vector2i.ZERO, "the overridden close must land shut")

	# The override is spent: the next close is the AUTHORED one again — the house rule's
	# 5-frame fast walk, not another snap.
	elem.open()
	for i in range(8):
		UI3Registry.transition_engine_step()
	_expect(elem.is_settled(), "the re-open must settle on the authored normal curve")
	elem.close()
	_expect(not elem.is_settled(), "the override must NOT persist into the next close")
	for i in range(5):   # the fast close is 5 reverse frames: n=1..4 walking back, n=5 shut
		UI3Registry.transition_engine_step()
	_expect(elem.is_settled() and closes[0] == 2,
		"the un-overridden close must walk the authored fast curve to settle at 5 frames")

	# An open override reaches settle_frame() as well as drive(), so the play is genuinely
	# shorter — not just drawn differently.
	elem.open(UI3BoxOpenBeat.Cadence.FAST)
	for i in range(4):
		UI3Registry.transition_engine_step()
	_expect(elem.is_settled(), "an open() override to FAST must settle at frame 4, not 8")
	elem.free()
	await get_tree().process_frame


## J. The move slot. The load-bearing assertion is the FIRST one: day one, an element that
## says nothing about `move` must still snap, or ADR-0097 §5's "every existing caller is
## unchanged" is false.
func _test_move_beat() -> void:
	Tune.bind("t.mv.home", Rect2(10, 20, 30, 40))
	Tune.bind("t.mv.away", Rect2(110, 120, 30, 40))

	# --- absent `move` = SNAP: place_at arrives before it returns -------------------------
	var snapper: UI3Element = UI3Element.new({
		"id": "t.mv.snap",
		"rect": UI3Element.at("t.mv.home"),
		"transition": UI3Element.Transition.NONE,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})
	add_child(snapper)
	await get_tree().process_frame
	var snap_moves := [0]
	snapper.moved.connect(func() -> void: snap_moves[0] += 1)
	snapper.place_at("t.mv.away")
	_expect(snapper.rect() == Rect2(110, 120, 30, 40) and snapper.is_move_settled(),
		"an element declaring no move beat must SNAP, got %s" % [snapper.rect()])
	_expect(snap_moves[0] == 1, "a snap must still emit `moved`, got %d" % snap_moves[0])
	snapper.free()
	await get_tree().process_frame

	# --- Move.SLIDE: the rect WALKS, both endpoints exact ---------------------------------
	var slider: UI3Element = UI3Element.new({
		"id": "t.mv.slide",
		"rect": UI3Element.at("t.mv.home"),
		"transition": UI3Element.Transition.NONE,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
		"move": UI3Element.Move.SLIDE,
		"move_cadence": UI3MoveSlideBeat.Cadence.DEFAULT,
	})
	add_child(slider)
	await get_tree().process_frame
	_expect(UI3Registry.transition_reversibility_errors().is_empty(),
		"a declared move beat must audit clean — reversibility is not asked of it, got %s"
		% [UI3Registry.transition_reversibility_errors()])
	_expect(UI3Registry.transition_cadence_errors().is_empty(),
		"a valid move cadence must audit clean, got %s" % [UI3Registry.transition_cadence_errors()])

	var moves := [0]
	slider.moved.connect(func() -> void: moves[0] += 1)
	slider.place_at("t.mv.away")
	_expect(not slider.is_move_settled(), "a declared move beat must PLAY, not snap")
	# Frame 0 is the start exactly: fraction = 1 − 144/144 = 0.
	_expect(slider.rect().position.is_equal_approx(Vector2(10, 20)),
		"move frame 0 must be the start rect exactly, got %s" % [slider.rect()])
	UI3Registry.transition_engine_step()
	_expect(not slider.rect().position.is_equal_approx(Vector2(10, 20))
		and not slider.rect().position.is_equal_approx(Vector2(110, 120)),
		"move frame 1 must be mid-journey, got %s" % [slider.rect()])

	for i in range(VitalsSlideAnimator.settle_frame()):
		UI3Registry.transition_engine_step()
	_expect(slider.is_move_settled() and moves[0] == 1,
		"the move must settle at the §15.1 curve's settle frame (settled %s, moved %d)"
		% [slider.is_move_settled(), moves[0]])
	_expect(slider.rect() == Rect2(110, 120, 30, 40),
		"a settled move must land the destination EXACTLY (lerped, not offset), got %s"
		% [slider.rect()])
	_expect(not UI3Registry.transition_engine_is_moving(slider),
		"a settled move must leave no play behind")

	# The inverse of a move is another move to the other place — not a reverse (§5).
	slider.place_at("t.mv.home")
	for i in range(VitalsSlideAnimator.settle_frame() + 1):
		UI3Registry.transition_engine_step()
	_expect(slider.rect() == Rect2(10, 20, 30, 40),
		"place_at back must return the element exactly, got %s" % [slider.rect()])

	# IMMEDIATE arrives inside place_at, the same synchronous settle §3 gives a close.
	slider.place_at("t.mv.away", UI3MoveSlideBeat.Cadence.IMMEDIATE)
	_expect(slider.is_move_settled() and slider.rect() == Rect2(110, 120, 30, 40),
		"an IMMEDIATE move must arrive synchronously, got %s" % [slider.rect()])
	slider.free()
	await get_tree().process_frame
	Tune.clear("t.mv.home")
	Tune.clear("t.mv.away")


func _box_element(id: String) -> UI3Element:
	return UI3Element.new({
		"id": id,
		"rect": Rect2(76, 135, 174, 101),
		"transition": UI3Element.Transition.BOX_OPEN,
		"open_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		"close_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.OWN_APERTURE,
	})


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		push_error("[UI3TransitionEngineTest] %s" % msg)


## A probe beat with a forward drive but NO reverse path — what the audit exists to catch.
class UI3IrreversibleProbeBeat:
	extends UI3Beat

	func _init() -> void:
		reversible = false

	func settle_frame(_element: UI3Element) -> int:
		return 4

	func drive(_element: UI3Element, _frame: int) -> void:
		pass
