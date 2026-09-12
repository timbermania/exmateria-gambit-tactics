extends Node
## END-TO-END proof for structural FEDS authoring (ADR-0085 amendment 2026-08-18b):
## right-click resolution → the corpus menu → the insert verb → the pair re-derive →
## SAVE through the relocating writer. All three build steps in one motion, on a real
## effect, with the studio actually running.
##
## Extended for the 2026-08-18c delete (§4/§6): right-click a NOTE SPAN on the time
## lane, take its Delete row, and confirm the studio rests it — the ticks stay, the
## sound goes, and the grey bar it becomes offers no Delete row of its own.
##
## Extended for the 2026-08-19c OUTRO: the track's END offers two rows, the extend one
## hangs the corpus's 18 lengths off a submenu, and the tell is `end_tick` — every verb
## before this one held the clock still by construction, so the tiling alone said everything.
##
## KNOWN DEFECT (not this step's): the mid-run PNGs are wrong under a tiling WM. `page.
## get_window().size = 1500x1000` does not take (Hyprland tiles it), so the captured
## viewport is 626x1390 while the pair panel's global rect is 943 wide — the crop clips and
## the region saved is the timeline above it, not the pair band. The numeric tells below are
## computed from the real layout's span bars, so they are unaffected.
##
## Extended again for the 2026-08-19 UN-REST: take the grey bar's own row and sound it
## back. Ticks must hold a second time, and a corpus-shaped note (velocity 96, key C, a
## table duration) must come back byte-identical — delete's inverse, proven on real bytes.
##
## Run (NOT headless):
##   EFFECT=E001 PAIR=0 OUT=/tmp/feds_e2e \
##     godot --path . --quit-after 1200 res://tools/probe_feds_structural_e2e.tscn
##
## The save ROUND-TRIP claim needs a non-CODE-format effect: `FedsBank.load_from_file`
## cannot re-parse a CODE-format header, so E317 and E482 report `false` there whatever
## the edit was (they do at 16949844a too). E001 and E026 are the ones to quote.

const EffectViewer := preload("res://assets/scenes/EffectViewer.tscn")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const Page = preload("res://src/effects/studio/EffectStudioPage.gd")


func _ready() -> void:
	var want: String = OS.get_environment("EFFECT")
	if want == "":
		want = "E001"
	var pair_idx: int = int(OS.get_environment("PAIR")) if OS.has_environment("PAIR") else 0
	var out: String = OS.get_environment("OUT")
	if out == "":
		out = "/tmp/feds_e2e"
	DirAccess.make_dir_recursive_absolute(out)

	var scn = load(EffectViewer.resource_path).instantiate()
	add_child(scn)
	await _frames(40)
	var page = scn._studio_page
	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with(want):
			dir = d
	if dir == "":
		print("[e2e] %s not in the picker" % want)
		get_tree().quit(1)
		return
	page._load_effect(dir)
	await _frames(30)
	page.get_window().size = Vector2i(1500, 1000)
	await _frames(10)
	page._set_root(Target.pair(pair_idx))
	await _frames(15)
	var panel = page._pair_panel
	if not panel.visible:
		print("[e2e] pair %d did not open" % pair_idx)
		get_tree().quit(1)
		return

	# 1. Resolve a right-click onto the first chip of track A — the gesture's address.
	var lay: Dictionary = panel.layout(panel._view, panel.size.x, panel._state(),
			panel._axis_obj(), panel._anchor)
	var target := Rect2()
	var best := 1e9
	for chip in lay["chips"]:
		if int(chip.get("track", -1)) != 0 or bool(chip.get("flowed", false)) \
				or bool(chip.get("ghost", false)):
			continue
		var r: Rect2 = chip["rect"]
		if r.position.x < best:
			best = r.position.x
			target = r
	if target.size.x <= 0.0:
		print("[e2e] track A of %s pair %d draws no chip to anchor to" % [want, pair_idx])
		get_tree().quit(0)
		return
	var ctx: Dictionary = panel.context_at(target.get_center())
	var anchor: Dictionary = ctx.get("anchor", {})
	print("[e2e] resolved to byte %d — %s" % [int(ctx.get("at", -1)),
			"the track start" if anchor.is_empty()
			else "after `%s` @ tick %d" % [str(anchor.get("label", "?")), int(anchor.get("tick", 0))]])

	# 2. The menu the page would pop, from the corpus.
	var actions: Array = Page._pair_context_actions(ctx)
	if actions.is_empty():
		print("[e2e] no verbs offered here")
		get_tree().quit(1)
		return
	var options: Array = actions[0]["options"]
	print("[e2e] %s → %d opcodes on offer, head: %s" % [str(actions[0]["label"]), options.size(),
			", ".join([str(options[0]["label"]), str(options[1]["label"]), str(options[2]["label"])])])
	for a in actions:
		if not a.has("options"):
			print("[e2e] …and %s" % str(a["label"]))

	# 3. Run the insert with the top-coverage opcode at its corpus-mode param.
	var before: int = scn._current_effect.effect_data.feds_bank.raw.size()
	var opt: Dictionary = options[0]
	var ref: Dictionary = (actions[0]["field_ref"] as Dictionary).duplicate()
	ref["opcode"] = int(opt["opcode"])
	ref["params"] = opt["params"]
	page._run_lane_verb({"verb": "insert", "field_ref": ref})
	await _frames(15)
	var after: int = scn._current_effect.effect_data.feds_bank.raw.size()
	print("[e2e] inserted %s(%s) — bank %d → %d bytes, selection now %s"
			% [str(opt["label"]), ", ".join(_ints(opt["params"])), before, after,
			str(panel.selected_event())])

	print("[e2e] inspector rows on the NEW opcode: %s" % _rows(page))

	# 3b. DELETE a note span (18c §4): right-click the first sounding span on the time
	# lane and take its Delete row. Deleting time means resting it, so the clock must
	# come back identical and the bar must turn into a rest with no Delete of its own.
	var lay2: Dictionary = panel.layout(panel._view, panel.size.x, panel._state(),
			panel._axis_obj(), panel._anchor)
	var span_rect := Rect2()
	var span_track := -1
	var span_best := 1e9
	for bar in lay2["span_bars"]:
		if bool(bar.get("rest", false)) or bool(bar.get("flowed", false)) \
				or bool(bar.get("ghost", false)):
			continue
		var br: Rect2 = bar["rect"]
		if br.position.x < span_best:
			span_best = br.position.x
			span_rect = br
			span_track = int(bar.get("track", -1))
	if span_rect.size.x <= 0.0:
		print("[e2e] %s pair %d draws no note span to delete" % [want, pair_idx])
	else:
		var tv: Dictionary = panel._view.get("tracks", [])[span_track]
		var ticks_before: int = int(tv.get("end_tick", -1))
		var bytes_before: int = scn._current_effect.effect_data.feds_bank.raw.size()
		var sctx: Dictionary = panel.context_at(span_rect.get_center())
		var del: Dictionary = sctx.get("delete", {})
		if del.is_empty():
			print("[e2e] the note span offered NO Delete row — the verb is unreachable")
		else:
			var dref: Dictionary = {}
			for a in Page._pair_context_actions(sctx):
				if str(a.get("verb", "")) == "delete":
					dref = a["field_ref"]
			print("[e2e] delete row on the span: `%s` @ byte %d"
					% [str(del.get("label", "?")), int(del.get("at", -1))])
			var track_before: PackedByteArray = scn._current_effect.effect_data.feds_bank \
					.get_track_bytes(pair_idx * 2 + span_track)
			page._run_lane_verb({"verb": "delete", "field_ref": dref})
			await _frames(15)
			var tv2: Dictionary = panel._view.get("tracks", [])[span_track]
			print("[e2e] rested: track %d ticks %d → %d, bank %d → %d bytes, selection %s"
					% [span_track, ticks_before, int(tv2.get("end_tick", -1)),
					bytes_before, scn._current_effect.effect_data.feds_bank.raw.size(),
					str(panel.selected_event())])
			# The bar at that spot is now a rest, and a rest has no Delete row.
			var lay3: Dictionary = panel.layout(panel._view, panel.size.x, panel._state(),
					panel._axis_obj(), panel._anchor)
			var rested_ei: int = int((panel.selected_event() as Dictionary).get("event_index", -1))
			var rest_bar: Dictionary = _bar_at(lay3, span_track, rested_ei)
			var now_rest: bool = bool(rest_bar.get("rest", false))
			# Right-click the bar WHERE IT NOW DRAWS: an edit re-derives the pair views and
			# the axis re-anchors, so the pre-edit rectangle points at another span's pixels.
			var rctx: Dictionary = panel.context_at((rest_bar.get("rect", Rect2()) as Rect2).get_center())
			print("[e2e] the span now draws as a rest: %s; its menu offers Delete: %s"
					% [now_rest, not (rctx.get("delete", {}) as Dictionary).is_empty()])

			# 3b'. PAINT into the rest (2026-08-19b) — the one verb that raises the event
			# count. Grabbed a third of the way along the bar, so the row is read off the
			# BAR's own rect, not off the axis. Undone afterwards so 3c below still meets
			# the whole rest it expects.
			var prect: Rect2 = rest_bar.get("rect", Rect2())
			var pctx: Dictionary = panel.context_at(Vector2(
					prect.position.x + prect.size.x / 3.0, prect.get_center().y))
			var pnt: Dictionary = pctx.get("paint", {})
			if pnt.is_empty():
				print("[e2e] the rest offered NO paint row at +1/3 — too short to split")
			else:
				var pref: Dictionary = {}
				var plabel := ""
				for a in Page._pair_context_actions(pctx):
					if str(a.get("verb", "")) == "paint":
						pref = a["field_ref"]
						plabel = str(a.get("label", ""))
				var tiling_before: String = _tiling(panel, span_track)
				print("[e2e] paint row on the grey bar: %s" % plabel)
				page._run_lane_verb({"verb": "paint", "field_ref": pref})
				await _frames(15)
				var tvp: Dictionary = panel._view.get("tracks", [])[span_track]
				var layp: Dictionary = panel.layout(panel._view, panel.size.x, panel._state(),
						panel._axis_obj(), panel._anchor)
				var painted: Dictionary = _bar_at(layp, span_track,
						int((panel.selected_event() as Dictionary).get("event_index", -1)))
				print(("[e2e] painted: track %d ticks %d (unchanged: %s), bank %d bytes, "
						+ "selection landed on a %s")
						% [span_track, int(tvp.get("end_tick", -1)),
						int(tvp.get("end_tick", -1)) == ticks_before,
						scn._current_effect.effect_data.feds_bank.raw.size(),
						"rest" if bool(painted.get("rest", true)) else "NOTE"])
				# The tiling itself is the tell: one grey bar becomes rest·note(·rest),
				# and the trailing piece is simply absent when the paint runs to the end.
				print("[e2e] tiling: %s → %s" % [tiling_before, _tiling(panel, span_track)])
				await _shot(page, out, "painted")
				print("[e2e] wrote %s/painted.png" % out)
				# Ctrl+Z goes through the PAGE, which re-points the cached env at the
				# swapped-back bank and re-derives the pair views. The host method alone
				# only refolds, and FEDS bytes are sound, not the folded framebuffer.
				page._undo()
				await _frames(15)
				print("[e2e] undone: bank %d bytes, ticks %d"
						% [scn._current_effect.effect_data.feds_bank.raw.size(),
						int((panel._view.get("tracks", [])[span_track] as Dictionary)
								.get("end_tick", -1))])
				# The axis re-anchored twice over; re-resolve the grey bar where it NOW draws.
				var layr: Dictionary = panel.layout(panel._view, panel.size.x, panel._state(),
						panel._axis_obj(), panel._anchor)
				rctx = panel.context_at((_bar_at(layr, span_track, rested_ei)
						.get("rect", Rect2()) as Rect2).get_center())

			# 3c. UN-REST it again (2026-08-19) — the row a grey bar carries INSTEAD of
			# Delete. The clock must not move a second time, and the corpus's own note
			# (velocity 96, key C, a table duration) comes back byte-for-byte.
			var un: Dictionary = rctx.get("unrest", {})
			if un.is_empty():
				print("[e2e] the rest offered NO un-rest row — delete has no inverse here")
			else:
				var uref: Dictionary = {}
				var ulabel := ""
				for a in Page._pair_context_actions(rctx):
					if str(a.get("verb", "")) == "unrest":
						uref = a["field_ref"]
						ulabel = str(a.get("label", ""))
				print("[e2e] un-rest row on the grey bar: %s" % ulabel)
				page._run_lane_verb({"verb": "unrest", "field_ref": uref})
				await _frames(15)
				var tv3: Dictionary = panel._view.get("tracks", [])[span_track]
				var track_after: PackedByteArray = scn._current_effect.effect_data.feds_bank \
						.get_track_bytes(pair_idx * 2 + span_track)
				var same_bytes: bool = Array(track_after) == Array(track_before)
				print("[e2e] sounded: track %d ticks %d, bytes back to before the delete: %s%s"
						% [span_track, int(tv3.get("end_tick", -1)), same_bytes,
						"" if same_bytes else
						" — `%s` comes back as a C: the rest held its ticks, never its key"
						% str(del.get("label", "?"))])
				var lay4: Dictionary = panel.layout(panel._view, panel.size.x, panel._state(),
						panel._axis_obj(), panel._anchor)
				var note_bar: Dictionary = _bar_at(lay4, span_track, rested_ei)
				var back_to_note: bool = not note_bar.is_empty() and not bool(note_bar.get("rest", true))
				var nctx: Dictionary = panel.context_at((note_bar.get("rect", Rect2()) as Rect2).get_center())
				print("[e2e] the bar draws as a note again: %s; its menu offers Delete: %s, un-rest: %s"
						% [back_to_note, not (nctx.get("delete", {}) as Dictionary).is_empty(),
						not (nctx.get("unrest", {}) as Dictionary).is_empty()])


			# 3d. DRAG (2026-08-19b §7 stages 2-4) — the direct-manipulation path to the same
			# verbs. Driven through the SAME chain the mouse takes: `drag_target` resolves
			# the grab once and in ticks, `drag_motion` turns each cursor x into a delta from
			# it, and the page's three handlers open / feed / close the coalesce bracket.
			var layd: Dictionary = panel.layout(panel._view, panel.size.x, panel._state(),
					panel._axis_obj(), panel._anchor)
			var grip_tell: PackedStringArray = []
			for g in layd["grips"]:
				grip_tell.append("%d%s" % [int(g["event_index"]), str(g["side"]).left(1)])
			print("[e2e] grips on the lane: %s" % ("none" if grip_tell.is_empty()
					else " ".join(grip_tell)))
			var drag_bar: Dictionary = _bar_at(layd, span_track, rested_ei)
			var dr: Rect2 = drag_bar.get("rect", Rect2())
			var drag: Dictionary = panel.drag_target(panel._view, layd,
					Vector2(dr.position.x + dr.size.x * 0.5, dr.get_center().y))
			if drag.is_empty():
				print("[e2e] the note is walled on both sides — no drag is armed, which is "
						+ "the honest answer for 95.2% of the corpus")
			else:
				var px_per_tick: float = 1.0 / maxf(0.0001, float(drag["ticks_per_px"]))
				var pre_drag: String = _tiling(panel, span_track)
				print("[e2e] armed a %s on `%s` (%d ticks; currency %d left / %d right)"
						% [str(drag["gesture"]), str(drag_bar.get("label", "?")),
						int(drag["span_ticks"]), int(drag_bar.get("left_ticks", 0)),
						int(drag_bar.get("right_ticks", 0))])
				page._on_pair_drag_started(drag)
				# Motion 1: far past the wall, to see the clamp and the splice.
				var far: Dictionary = _motion(panel, page, drag,
						float(drag["start_x"]) + px_per_tick * 400.0)
				await _frames(10)
				print("[e2e] tiling: %s → %s   (asked +400 ticks, the law wrote %+d)"
						% [pre_drag, _tiling(panel, span_track),
						int(far.get("delta_ticks", 0))])
				await _shot(page, out, "dragged")
				print("[e2e] wrote %s/dragged.png" % out)
				# Motion 2: a smaller delta from the SAME grab. It must read as planned
				# against the PRE-DRAG tiling, not compounded on motion 1's splices.
				_motion(panel, page, drag, float(drag["start_x"]) + px_per_tick * 8.0)
				await _frames(10)
				print("[e2e] tiling: → %s   (same grab, +8 ticks — re-planned, not compounded)"
						% _tiling(panel, span_track))
				# Motion 3: back to the grab. The pristine tiling returns while the mouse is
				# still held, which is what makes a consuming drag self-inverse (ADR-0095 §4).
				_motion(panel, page, drag, float(drag["start_x"]))
				await _frames(10)
				var back: String = _tiling(panel, span_track)
				print("[e2e] tiling: → %s   (dragged back; pristine again: %s)"
						% [back, back == pre_drag])
				page._on_pair_drag_ended()
				# …and one Ctrl+Z undoes the WHOLE gesture, not one motion of it.
				_motion(panel, page, drag, float(drag["start_x"]) + px_per_tick * 400.0)
				page._on_pair_drag_ended()
				await _frames(10)
				var moved: String = _tiling(panel, span_track)
				page._undo()
				await _frames(10)
				print("[e2e] one drag, one undo: %s → %s (pristine: %s)"
						% [moved, _tiling(panel, span_track),
						_tiling(panel, span_track) == pre_drag])

	# 3e. The OUTRO (2026-08-19c) — the FIRST verb whose tell is `end_tick` rather than the
	# tiling. Driven through the real menu path: the context resolved at the track's END,
	# the row the page builds, and the submenu handler the popup calls.
	var otrack: int = maxi(0, span_track)
	var otv: Dictionary = panel._view.get("tracks", [])[otrack]
	var end_ei := -1
	for c in otv.get("commands", []):
		if int((c as Dictionary).get("opcode", -1)) == 0x90 \
				and not bool((c as Dictionary).get("flowed", false)):
			end_ei = int((c as Dictionary)["event_index"])
	if end_ei < 0:
		print(("[e2e] track %d is a STUB — no terminator, so the outro is refused, which is "
				+ "the honest answer for 70 of the corpus's 2008 byte-owning tracks") % otrack)
	else:
		var octx: Dictionary = panel._context_for(panel._view, otrack, end_ei, true)
		var oact: Dictionary = {}
		var otrim: Dictionary = {}
		for a in Page._pair_context_actions(octx):
			if str(a.get("verb", "")) == "outro":
				if a.has("outro_options"):
					oact = a
				else:
					otrim = a
		print("[e2e] at the track's end: %s%s" % [str(oact.get("label", "—")),
				"" if otrim.is_empty() else "  |  " + str(otrim["label"])])
		var pre_o: String = _clock(panel, otrack)
		# The 48-tick step (one beat) out of the corpus's 18 lengths, through the handler
		# the popup calls — so the arithmetic the row did is the arithmetic that is written.
		var step := -1
		for j in range((oact.get("outro_options", []) as Array).size()):
			if int((oact["outro_options"][j] as Dictionary)["ticks"]) == 48:
				step = j
		page._pair_outro_opts = oact.get("outro_options", [])
		page._pair_outro_ref = oact.get("field_ref", {})
		page._on_pair_outro_menu_id(step)
		await _frames(10)
		print("[e2e] extend +48: %s → %s" % [pre_o, _clock(panel, otrack)])
		# The composition: the new silence is an ORDINARY rest span, so the paint that
		# shipped in 19b sounds a note where FFT's track used to have no time at all.
		var tv2: Dictionary = panel._view.get("tracks", [])[otrack]
		var tail_off := -1
		for c in tv2.get("commands", []):
			var cd: Dictionary = c
			if int(cd.get("opcode", -1)) == 0x80 and int(cd.get("span_total_ticks", 0)) >= 24 \
					and not bool(cd.get("flowed", false)):
				tail_off = int(cd["offset"])
		if tail_off >= 0:
			var paint_ref: Dictionary = (oact["field_ref"] as Dictionary).duplicate()
			paint_ref["at"] = tail_off
			paint_ref["offset_ticks"] = 0
			paint_ref["duration_ticks"] = 24
			page._run_lane_verb({"verb": "paint", "field_ref": paint_ref})
			await _frames(10)
			print("[e2e] painted into it: %s" % _clock(panel, otrack))
		# …and trim takes the clock back, which no other verb on this lane can do.
		var trim_ref: Dictionary = (oact["field_ref"] as Dictionary).duplicate()
		trim_ref["outro_ticks"] = 0
		page._run_lane_verb({"verb": "outro", "field_ref": trim_ref})
		await _frames(10)
		print("[e2e] trim → 0: %s" % _clock(panel, otrack))
		await _shot(page, out, "outro")
		print("[e2e] wrote %s/outro.png" % out)

	# 3e. CUT → PASTE (ADR-0085 amendment 2026-08-19e §2): the re-order. Cut lowers to the
	# delete verb and paste to the insert verb, both already exercised above — what is new is
	# that the opcode's OWN params travel with it, where the Add menu would have re-inserted
	# the corpus mode. Proven on real bytes: the stream before and after must differ only by
	# where that opcode sits.
	var cut_ei := -1
	var cut_clip: Dictionary = {}
	var cut_at := -1
	var ctv: Dictionary = panel._view.get("tracks", [])[0]
	for c in ctv.get("commands", []):
		var cd: Dictionary = c
		if bool(cd.get("flowed", false)) or int(cd.get("event_index", -1)) <= 0:
			continue
		var cctx: Dictionary = panel._context_for(panel._view, 0, int(cd["event_index"]), true)
		var cclip: Dictionary = cctx.get("cut", {})
		if cclip.is_empty():
			continue
		cut_ei = int(cd["event_index"])
		cut_clip = cclip
		cut_at = int(cclip["at"])
		break
	if cut_ei < 0:
		print("[e2e] track A has no re-orderable opcode — every one of them is flow or a span")
	else:
		var pre_bytes := _hex(scn._current_effect.effect_data.feds_bank.get_track_bytes(pair_idx * 2))
		var cut_ref := {"channel": "sound_def", "pair_idx": pair_idx,
				"track_idx": pair_idx * 2, "at": cut_at}
		page._run_lane_verb({"verb": "cut", "field_ref": cut_ref,
			"clip": {"opcode": int(cut_clip["opcode"]), "params": cut_clip["params"],
				"label": str(cut_clip["label"])}})
		await _frames(10)
		print("[e2e] cut `%s`(%s) from byte %d — the clipboard holds its OWN params, not the corpus mode"
				% [str(cut_clip["label"]), ", ".join(_ints(cut_clip["params"])), cut_at])
		# Paste it at the track START — the one address that is always there, and a real move.
		var start_ctx: Dictionary = panel._context_for(panel._view, 0, -1, false)
		var pastes: Array = []
		for a in Page._pair_context_actions(start_ctx, page._feds_clip):
			if str(a.get("label", "")).begins_with("Paste"):
				pastes.append(a)
		print("[e2e] at the track start the menu now offers: %s"
				% ("nothing" if pastes.is_empty() else str((pastes[0] as Dictionary)["label"])))
		if not pastes.is_empty():
			page._run_lane_verb(pastes[0])
			await _frames(10)
			print("[e2e] re-ordered: %s" % pre_bytes)
			print("[e2e]         →   %s"
					% _hex(scn._current_effect.effect_data.feds_bank.get_track_bytes(pair_idx * 2)))

	# 3f. The POPUP itself. `_pair_context_actions` is pure and guarded by the suite, but the
	# builder that turns its rows into PopupMenu items is not — and the two rows added in
	# 2026-08-19e are exactly the ones with no precedent there: a DISABLED refusal row, and
	# the disabled header lines ahead of the corpus submenu. Built for real, then read back.
	page._on_pair_context(panel._context_for(panel._view, 0, 0, true))
	await _frames(2)
	var add_menu: PopupMenu = page._pair_add_menu
	var head_lines: Array = []
	for i in range(add_menu.item_count):
		if not add_menu.is_item_disabled(i) and not add_menu.is_item_separator(i):
			break
		if not add_menu.is_item_separator(i):
			head_lines.append(add_menu.get_item_text(i))
	print("[e2e] the Add submenu opens with %d disabled lines, then %d corpus rows"
			% [head_lines.size(), add_menu.item_count - head_lines.size() - 1])
	for l in head_lines:
		print("[e2e]   %s" % str(l))
	page._ctx_menu.hide()
	# …and the refusal: one row, disabled, naming the place the click landed on.
	page._on_pair_context({"refused": "The track label strip — no bytes live here."})
	await _frames(2)
	print("[e2e] a click on no bytes pops %d row: \"%s\" (disabled: %s)"
			% [page._ctx_menu.item_count, page._ctx_menu.get_item_text(0),
			page._ctx_menu.is_item_disabled(0)])
	page._ctx_menu.hide()

	# 4. SAVE — the relocating writer is what makes a resized sound persistable at all.
	var res: Dictionary = scn.studio_save()
	print("[e2e] save: ok=%s error=%s" % [res.get("ok", false), res.get("error", "")])
	if bool(res.get("ok", false)):
		var saved = ExMateriaSound.FedsBank.load_from_file(String(res["out_path"]))
		var round_trip: bool = saved != null \
				and saved.get_track_bytes(pair_idx * 2) == scn._current_effect.effect_data.feds_bank.get_track_bytes(pair_idx * 2)
		print("[e2e] the saved BIN re-parses to the edited track: %s" % round_trip)

	await _shot(page, out, "structural")
	print("[e2e] wrote %s/structural.png" % out)
	get_tree().quit(0)


## The track's OWN span bar for one decode-order event — the identity both time verbs
## preserve (18c §4: the event count does not change, so the selection sits still). Keyed
## by event_index rather than by x: a bar's PIXELS move when the panel re-anchors after an
## edit, and ghost / borrowed copies draw over the same spot.
## One motion of a drag, through the page's handler exactly as `_gui_input` feeds it.
func _motion(panel, page, drag: Dictionary, x: float) -> Dictionary:
	var m: Dictionary = panel.drag_motion(drag, x)
	if m.is_empty():
		return {}
	var payload: Dictionary = drag.duplicate()
	payload.merge(m, true)
	# What the verb ACHIEVED after clamping — the gesture asks for the cursor, the law
	# answers with the wall, and the two are different numbers whenever a drag runs out of
	# currency. Overwrite the request so the print cannot claim what was not written.
	var res: Dictionary = page._on_pair_dragged(payload)
	if res.has("delta_ticks"):
		payload["delta_ticks"] = int(res["delta_ticks"])
	return payload


## The track's own span bars as a tick-ordered kind string — "note48 rest12 note4" — so a
## split reads as one bar becoming two or three rather than as a count that can stay equal.
func _tiling(panel, track: int) -> String:
	var lay: Dictionary = panel.layout(panel._view, panel.size.x, panel._state(),
			panel._axis_obj(), panel._anchor)
	var mine: Array = []
	for b in lay["span_bars"]:
		if int(b["track"]) == track and not bool(b.get("flowed", false)):
			mine.append(b)
	mine.sort_custom(func(a, c): return (a["rect"] as Rect2).position.x < (c["rect"] as Rect2).position.x)
	var parts: PackedStringArray = []
	for b in mine:
		parts.append("%s%d" % ["rest" if bool(b.get("rest", false)) else "note",
				int(b.get("span_total_ticks", 0))])
	return " ".join(parts)


## The tiling AND the clock it tiles. Every verb before the outro held `end_tick` still by
## construction, so the tiling alone was the whole tell; the outro moves it, and a tiling
## that says nothing about the total cannot report that.
func _clock(panel, track: int) -> String:
	var tv: Dictionary = panel._view.get("tracks", [])[track]
	return "%s  [end_tick %d, outro %d]" % [_tiling(panel, track),
			int(tv.get("end_tick", 0)), int(tv.get("outro_ticks", 0))]


func _bar_at(lay: Dictionary, track: int, event_index: int) -> Dictionary:
	for bar in lay["span_bars"]:
		if int(bar.get("track", -1)) == track and int(bar.get("event_index", -1)) == event_index \
				and not bool(bar.get("ghost", false)) and not bool(bar.get("flowed", false)):
			return bar
	return {}


## Every editable widget the F1 inspector is showing — §8's claim is that after an
## insert these are the NEW opcode's parameter rows, so "add an Instrument" and
## "set it to 42" are one motion.
func _rows(page) -> String:
	var i = page._inspector
	return "int=%d enum=%d choice=%d bitflags=%d" % [i.int_widgets().size(),
			i.enum_widgets().size(), i.choice_widgets().size(), i.bitflag_widgets().size()]


## One track's bytes as hex — the only honest way to show a re-order: the same bytes,
## in a different order.
func _hex(b: PackedByteArray) -> String:
	var out: Array = []
	for v in b:
		out.append("%02X" % int(v))
	return " ".join(out)


func _ints(a) -> Array:
	var out: Array = []
	for v in a:
		out.append(str(int(v)))
	return out


func _shot(page, out: String, tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = page.get_viewport().get_texture().get_image()
	var r: Rect2 = page._pair_scroll.get_global_rect()
	var crop := Rect2i(Vector2i(r.position), Vector2i(r.size)).intersection(
			Rect2i(Vector2i.ZERO, img.get_size()))
	if crop.size.x > 4 and crop.size.y > 4:
		img = img.get_region(crop)
	img.save_png("%s/%s.png" % [out, tag])


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
