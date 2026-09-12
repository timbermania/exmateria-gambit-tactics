class_name CameraChannel
extends RefCounted

const CameraLowering = preload("res://src/effects/studio/CameraLowering.gd")
const CameraValueSemantics = preload("res://src/effects/studio/CameraValueSemantics.gd")
## Write-side channel encoder for the CAMERA Timeline (wayfinder #267) — the
## per-keyframe angle / position / zoom values and the packed command word. It
## owns the raw↔value encoding for a `CameraData.Keyframe`: given a raw edit it
## writes the storage field on the live keyframe, recomputes any derived cache,
## and declares whether the edit invalidates the sim.
##
## Unlike the read-live screen backdrop, camera framing is FOLDED during the sim
## (CameraSubsystem interpolates from/to per transition), so a keyframe change
## only shows after a re-fold — every camera edit is `invalidates_sim = true`.
##
## Channels supply encoders, not mutation logic; the single choke point is
## `EffectEditSession.apply_edit` (#255). Mirrors `ScreenChannel`.

# Decode maps for the packed command word — mirror parse_effect.CAMERA_SOURCE_MODES
# / CAMERA_INTERPOLATIONS (the ONE ROM layout shared by parser, writer and studio).
const _SOURCE_MODES := {
	0x000: "TARGET", 0x020: "OFFSET", 0x040: "DIRECT", 0x060: "ORIGIN",
	0x080: "EFFECT_CTR", 0x0C0: "MAP", 0x100: "SLOT_COPY", 0x140: "CASTER",
	0x180: "ALL_TARGETS", 0x1C0: "CURSOR",
}
const _INTERPOLATIONS := {
	0x0200: "IMMEDIATE", 0x0400: "COSINE_A", 0x0600: "COSINE_B", 0x0800: "LINEAR",
	0x0A00: "COSINE_C", 0x0C00: "ADDITIVE", 0x0E00: "ADDITIVE_B",
	0x1000: "SHAKE_DAMPED", 0x1200: "SHAKE_DIRECT", 0x1400: "SHAKE_DAMPED_B",
}

# Sub-channel name ↔ its channel_mask bit (the authoring lanes / runtime search grain).
# The signed-16-bit ceiling an `end_frame` lowers into — the open lane tail's Move room.
const S16_MAX := 32767
const _CHANNEL_BIT := {"angle": 1, "position": 2, "zoom": 4}
const _CHANNEL_NAME := {1: "angle", 2: "position", 4: "zoom"}

# Author-facing field name → the Vector3i storage attr + component index it edits.
const _VEC_FIELD := {
	"angle_x": ["angle", 0], "angle_y": ["angle", 1], "angle_z": ["angle", 2],
	"position_x": ["position", 0], "position_y": ["position", 1], "position_z": ["position", 2],
	"zoom": ["zoom", 0],   # only slot 0 is engine-used; slots 1/2 are ignored
}

# Command-word sub-fields → (clear_mask, shift). The edit clears `clear_mask` and
# ORs in `(new_raw << shift) & clear_mask`, preserving every other bit. source_mode
# / interpolation are fanned as already-positioned bits (shift 0); param_index /
# flags are fanned as small ints shifted into place. channel_mask is ABSENT — it is
# a lowering artifact (ADR-0086), emitted by the encoder, never edited in place.
const _CMD_FIELD := {
	"param_index":  [0x0018, 3],
	"source_mode":  [0x01E0, 0],
	"interpolation":[0x1E00, 0],
	"flags":        [0xE000, 13],
}


## Write one raw camera value for the keyframe named by `field_ref`, recompute any
## derived cache, and return the snapshot the choke point records for undo.
static func apply_raw(data, field_ref: Dictionary, new_raw) -> Dictionary:
	var kf = _resolve_keyframe(data, field_ref)
	if kf == null:
		push_error("CameraChannel: no camera keyframe for %s" % str(field_ref))
		return {}
	var field: String = field_ref.get("field", "")

	# Value fields live in their own vec (angle / position / zoom), so editing one
	# never perturbs a coalesced sibling — always a fast in-place write.
	if _VEC_FIELD.has(field):
		return _apply_vec(kf, field, int(new_raw))

	# RIPPLE (ADR-0087 decs. 15-16): with the flag on the field_ref, an end_frame
	# edit shifts the whole lane tail — write the edited event's end, add the delta to
	# every DOWNSTREAM end in the SAME sub-channel lane, and recompile. Camera is
	# endpoint-encoded, so this is inherently structural (parse→shift→lower); a
	# downstream coalesced keyframe splits out lane-locally through the lowerer.
	if field == "end_frame" and bool(field_ref.get("ripple", false)):
		return _apply_ripple_end(data, field_ref, int(new_raw))

	# Shared EVENT fields (end_frame + the command word). On a COALESCED keyframe —
	# one that also drives OTHER sub-channels — mutating the shared word in place
	# would drag the siblings along, so split the edited sub-channel out through the
	# coalescing lowerer (ADR-0086). A SOLO keyframe has no sibling → in-place fold.
	if field == "end_frame" or _CMD_FIELD.has(field):
		var channel_bit: int = int(_CHANNEL_BIT.get(field_ref.get("camera_channel", ""), 0))
		if channel_bit != 0 and (int(kf.channel_mask) & ~channel_bit) != 0:
			return _apply_split(data, field_ref, channel_bit, field, int(new_raw))
		# SOLO keyframe: fold the shared field in place, then attempt an auto-remerge.
		# Splitting is automatic (above); merging must be too — a solo edit that brings
		# this keyframe to COINCIDE-AND-AGREE with another re-lowers them into one masked
		# keyframe (ADR-0086), the inverse of the split. Value edits took the fast path
		# above and never reach here, so they never trigger a re-lower.
		var res: Dictionary
		if field == "end_frame":
			var before: int = int(kf.end_frame)
			kf.end_frame = int(new_raw)
			res = _result(before, int(new_raw), _s16_faithful("end_frame", int(new_raw)))
			# end_frame moves the span boundary and the compiled marker, so even this
			# non-structural fold must refresh the lane — the host reprojects the timeline.
			res["relayout"] = true
		else:
			res = _apply_command(kf, field, int(new_raw))
		_maybe_remerge(data, field_ref.get("context", ""), res)
		return res

	push_error("CameraChannel: unknown camera field '%s'" % field)
	return {}


# Lane default for a seeded event with no span to inherit from (empty lane / gap add):
# a plain LINEAR-to-TARGET move with zero value. source_bits/interp_bits are the already-
# positioned command-word bits (mirror CameraLowering's decode grain).
const _SEED_SOURCE_BITS := 0x000   # TARGET
const _SEED_INTERP_BITS := 0x0800  # LINEAR
# The one source mode that resolves against the camera's own current value, so a ZERO value
# under it is a HOLD (ADR-0086 dec. 15). The Move's manufactured padding.
const _HOLD_SOURCE_BITS := 0x0C0   # MAP


## Insert a new event into a sub-channel LANE at `field_ref.frame` — the INSERT-WAYPOINT
## verb (ADR-0086 dec. 7). This cuts a span in TIME (or seeds an empty/point
## lane); it is NOT the de-coalesce split (which un-shares a masked keyframe). Expands the
## phase table to lanes, adds the seeded event, re-lowers, and replaces the table — a whole-
## section recompile, so the edit is `structural` and the host re-projects. Seed: a span-cut
## takes the value interpolated at the frame along the span it cuts plus that span's command
## word (a visual no-op); an empty-lane / gap add seeds from lane defaults.
static func insert_event(data, field_ref: Dictionary) -> Dictionary:
	var phase: String = field_ref.get("context", "")
	if data == null or data.camera == null:
		return {}
	var table = data.camera.get_table(phase)
	if table == null:
		return {}
	var lane_name: String = str(field_ref.get("camera_channel", ""))
	var channel_bit: int = int(_CHANNEL_BIT.get(lane_name, 0))
	if channel_bit == 0:
		push_error("CameraChannel: insert into unknown lane '%s'" % lane_name)
		return {}
	var frame: int = int(field_ref.get("frame", 0))

	var lanes: Dictionary = CameraLowering.parse(table)
	var events: Array = lanes.get(lane_name, [])
	events.append(_seed_event(events, channel_bit, frame))
	lanes[lane_name] = events

	var compiled = CameraLowering.lower(lanes)
	data.camera.tables[phase] = compiled
	return _structural_result(compiled, phase, frame,
		_lane_ordinal_of_frame(compiled, lane_name, frame))


## Delete the `(camera_channel, ordinal)` event from its lane — the inverse of
## insert-waypoint. Removing a mid-lane waypoint lets the neighbour re-span the gap;
## removing the sole event empties the lane. Re-lowers + replaces the table (structural).
## Selection lands on the previous neighbour (ADR-0086), or nothing if the lane emptied.
## Does this ref address a HOLD that now owns NOTHING — its `end_frame` sitting exactly on the
## end of the event before it (or on the phase origin, for ordinal 0)? ADR-0101 decision 7 says
## an owner of nothing is deleted, and `move_span` recognises the holds IT empties inline; this
## asks the same question from outside, after the fact, for the BOUNDARY drag — which can pull a
## hold's own end back onto its start and cannot delete mid-gesture (it re-resolves its address
## from the score each motion, so a renumbering lane would move the target under the cursor).
static func is_emptied_hold(data, field_ref: Dictionary) -> bool:
	var phase: String = field_ref.get("context", "")
	if data == null or data.camera == null:
		return false
	var table = data.camera.get_table(phase)
	if table == null:
		return false
	var lane_name: String = str(field_ref.get("camera_channel", ""))
	var events: Array = CameraLowering.parse(table).get(lane_name, [])
	var n: int = int(field_ref.get("ordinal", -1))
	if n < 0 or n >= events.size():
		return false
	if not _event_is_hold(table, events[n], lane_name):
		return false
	var own_start: int = int(events[n - 1]["end_frame"]) if n >= 1 else 0
	return int(events[n]["end_frame"]) <= own_start


static func delete_event(data, field_ref: Dictionary) -> Dictionary:
	var phase: String = field_ref.get("context", "")
	if data == null or data.camera == null:
		return {}
	var table = data.camera.get_table(phase)
	if table == null:
		return {}
	var lane_name: String = str(field_ref.get("camera_channel", ""))
	if int(_CHANNEL_BIT.get(lane_name, 0)) == 0:
		push_error("CameraChannel: delete from unknown lane '%s'" % lane_name)
		return {}
	var ordinal: int = int(field_ref.get("ordinal", -1))

	var lanes: Dictionary = CameraLowering.parse(table)
	var events: Array = lanes.get(lane_name, [])
	if ordinal < 0 or ordinal >= events.size():
		push_error("CameraChannel: no %s event at ordinal %d to delete" % [lane_name, ordinal])
		return {}
	events.remove_at(ordinal)
	lanes[lane_name] = events

	var compiled = CameraLowering.lower(lanes)
	data.camera.tables[phase] = compiled
	# Selection falls to the previous neighbour; -1 when the lane is now empty.
	var neighbour: int = mini(ordinal - 1, events.size() - 1)
	return _structural_result(compiled, phase, 0, neighbour)


## Seed the value + command word for a newly inserted event. When F falls INSIDE a
## covering span `[prev_end, end)`, the seed is a VISUAL NO-OP: the value interpolated
## at F along that span (LINEAR in value space — the dominant to-target case) and the
## span's inherited command word, so the motion is unchanged until the author drags the
## new waypoint (ADR-0086). With no covering span (empty lane / gap / past the last
## event) the seed is a lane default: zero value, LINEAR-to-TARGET.
static func _seed_event(events: Array, channel_bit: int, frame: int) -> Dictionary:
	var ev := {
		"channel": channel_bit, "end_frame": frame,
		"source_bits": _SEED_SOURCE_BITS, "interp_bits": _SEED_INTERP_BITS,
		"param": 0, "flags": 0, "value": Vector3i.ZERO, "origin_index": -1,
	}
	# Walk the lane in end_frame order; the covering span is the first event ending AFTER F.
	var ordered: Array = events.duplicate()
	ordered.sort_custom(func(a, b): return int(a["end_frame"]) < int(b["end_frame"]))
	var prev_end: int = 0
	var from_val: Vector3i = Vector3i.ZERO
	for e in ordered:
		var end: int = int(e["end_frame"])
		if end > frame:
			var t: float = 0.0 if end == prev_end \
				else float(frame - prev_end) / float(end - prev_end)
			ev["value"] = _lerp_vec3i(from_val, e["value"], t)
			ev["source_bits"] = int(e["source_bits"])
			ev["interp_bits"] = int(e["interp_bits"])
			ev["param"] = int(e["param"])
			ev["flags"] = int(e["flags"])
			break
		prev_end = end
		from_val = e["value"]
	return ev


## Round-to-nearest linear interpolation of a Vector3i value (component-wise) — the
## seed sampler for an insert-waypoint. Vector3i has no float lerp of its own.
static func _lerp_vec3i(a: Vector3i, b: Vector3i, t: float) -> Vector3i:
	return Vector3i(
		roundi(lerp(float(a.x), float(b.x), t)),
		roundi(lerp(float(a.y), float(b.y), t)),
		roundi(lerp(float(a.z), float(b.z), t)))


## The ordinal (§#286 address) of the lane event at `frame` in a compiled table — its
## index in CameraLowering.parse order. -1 if the lane has no event at that frame.
static func _lane_ordinal_of_frame(table, lane_name: String, frame: int) -> int:
	var events: Array = CameraLowering.parse(table).get(lane_name, [])
	for i in range(events.size()):
		if int(events[i]["end_frame"]) == frame:
			return i
	return -1


## The structural result the choke point records: no scalar before/after (insert/delete
## have no scalar inverse — undo is snapshot-based), a post-compile Faithful advisory
## (end_frame quantization + capacity), and the new/neighbour `ordinal` the host selects.
static func _structural_result(compiled, phase: String, frame: int, ordinal: int) -> Dictionary:
	var faithful: Dictionary = _s16_faithful("end_frame", frame)
	var capacity: Dictionary = CameraLowering.capacity_faithful(compiled.keyframes.size(), phase)
	if not capacity.get("ok", true):
		faithful = capacity
	return {
		"structural": true,
		"invalidates_sim": true,
		"faithful": faithful,
		"ordinal": ordinal,
	}


## Split the addressed sub-channel out of a coalesced keyframe: expand the phase
## table into sub-channel events, mutate ONLY the addressed event's shared field,
## then re-lower — the compiler re-packs it onto its own (or a coincident-agreeing)
## keyframe while the siblings keep their word. The whole camera section recompiles
## (ADR-0086: semantic, not byte-exact), so the edit is `structural` — the host
## re-projects. Reuses the parse↔lower round-trip guarded in CameraLoweringTest.
static func _apply_split(data, field_ref: Dictionary, channel_bit: int,
		field: String, new_raw: int) -> Dictionary:
	var phase: String = field_ref.get("context", "")
	var table = data.camera.get_table(phase)
	if table == null:
		return {}
	var lanes: Dictionary = CameraLowering.parse(table)
	var lane_name: String = _CHANNEL_NAME[channel_bit]
	# Address by ordinal within the lane (ADR-0086 dec. 5, #286): the ordinal-th event
	# is the same semantic event before and after any re-lower, so a split addressed here
	# tracks the sub-channel across the renumber it causes.
	var ordinal: int = int(field_ref.get("ordinal", -1))
	var events: Array = lanes.get(lane_name, [])
	if ordinal < 0 or ordinal >= events.size():
		push_error("CameraChannel: no %s event at ordinal %d for split" % [lane_name, ordinal])
		return {}
	var ev = events[ordinal]

	var before: int = _event_field(ev, field)
	_set_event_field(ev, field, new_raw)
	var after: int = _event_field(ev, field)

	var compiled = CameraLowering.lower(lanes)
	data.camera.tables[phase] = compiled

	# Faithful is a post-compile property here: value quantization (end_frame s16) AND
	# capacity (the split can push the compiled count past the native slots). Report
	# the capacity breach if any, else the value advisory.
	var faithful: Dictionary = _s16_faithful(field, new_raw) if field == "end_frame" \
		else {"ok": true, "reason": ""}
	var capacity: Dictionary = CameraLowering.capacity_faithful(compiled.keyframes.size(), phase)
	if not capacity.get("ok", true):
		faithful = capacity
	var res := _result(before, after, faithful)
	res["structural"] = true
	return res


## The RIPPLE end_frame write (ADR-0087 decs. 15-16): set the addressed event's end
## and shift every downstream end in the SAME lane by the delta, widths preserved, then
## re-lower. Lane-local by construction — sibling lanes are re-lowered untouched, so a
## downstream coalesced keyframe splits rather than dragging its siblings. REFUSES (error
## + empty-handed `no_edit`, so nothing is recorded) an edit that would push any shifted
## end_frame outside s16 — saturating would silently destroy spacing and make redo
## diverge from the recorded bytes.
static func _apply_ripple_end(data, field_ref: Dictionary, new_raw: int) -> Dictionary:
	var phase: String = field_ref.get("context", "")
	if data == null or data.camera == null:
		return {}
	var table = data.camera.get_table(phase)
	if table == null:
		return {}
	var lane_name: String = str(field_ref.get("camera_channel", ""))
	var ordinal: int = int(field_ref.get("ordinal", -1))
	var lanes: Dictionary = CameraLowering.parse(table)
	var events: Array = lanes.get(lane_name, [])
	if ordinal < 0 or ordinal >= events.size():
		push_error("CameraChannel: no %s event at ordinal %d for ripple" % [lane_name, ordinal])
		return {}
	var before: int = int(events[ordinal]["end_frame"])
	var delta: int = new_raw - before

	for i in range(ordinal, events.size()):
		var shifted: int = new_raw if i == ordinal else int(events[i]["end_frame"]) + delta
		if shifted < -32768 or shifted > 32767:
			push_error("CameraChannel: ripple refused — %s ordinal %d would land at %d, outside s16"
				% [lane_name, i, shifted])
			return {"no_edit": true, "faithful": {"ok": false, "reason":
				"ripple would push %s ordinal %d to %d, outside the signed 16-bit encoding"
				% [lane_name, i, shifted]}}

	events[ordinal]["end_frame"] = new_raw
	for i in range(ordinal + 1, events.size()):
		events[i]["end_frame"] = int(events[i]["end_frame"]) + delta
	lanes[lane_name] = events

	var compiled = CameraLowering.lower(lanes)
	data.camera.tables[phase] = compiled
	var faithful: Dictionary = _s16_faithful("end_frame", new_raw)
	var capacity: Dictionary = CameraLowering.capacity_faithful(compiled.keyframes.size(), phase)
	if not capacity.get("ok", true):
		faithful = capacity
	var res := _result(before, new_raw, faithful)
	res["structural"] = true
	return res


## --- MOVE (ADR-0101 decision 3) ---------------------------------------------


## Plan the MOVE slide for one camera sub-channel event — the camera arm of ADR-0101
## decision 3, and the CHEAP kind: `end_frame` is ABSOLUTE, so a move is two boundary writes
## with no quantization, no padding and no slot budget. Span `n` owns
## `[events[n-1].end_frame, events[n].end_frame)`, so shifting BOTH ends by one clamped delta
## preserves its width and leaves everything outside the two immediate neighbours pinned.
##
## The two neighbours must be HOLDS — `CameraValueSemantics.is_spacer` (MAP + zero value),
## which is decidable LOCALLY with no fold, unlike the colour lanes. A span wedged between two
## drawn tweens is refused in `plan_move`'s existing vocabulary: a move must never change what
## another span renders, and shifting a drawn neighbour's end is exactly that.
##
## Event 0 owns `[0, end)` against the PHASE ORIGIN, which is a wall, so the first event has no
## movable left boundary. The lane TAIL is open (particle's rule): past the last event the
## right room runs to s16.
##
## PURE — `parse` builds fresh dictionaries, so the returned `lanes` is a detached copy the
## applier may mutate; the live table is untouched. Returns
## `{ok, delta, reason, lanes, lane, ordinal}`.
static func plan_move(data, field_ref: Dictionary, delta: int) -> Dictionary:
	var phase: String = field_ref.get("context", "")
	if data == null or data.camera == null:
		return _move_refused("no camera data")
	var table = data.camera.get_table(phase)
	if table == null:
		return _move_refused("no camera table for %s" % phase)
	var lane_name: String = str(field_ref.get("camera_channel", ""))
	var lanes: Dictionary = CameraLowering.parse(table)
	var events: Array = lanes.get(lane_name, [])
	var n: int = int(field_ref.get("ordinal", -1))
	if n < 0 or n >= events.size():
		return _move_refused("no %s event at ordinal %d" % [lane_name, n])

	# The LEAD is the space in front of the span: the previous event's window, or — for event 0
	# — the stretch from the phase origin. It can be SHRUNK only if it is a hold (shrinking a
	# drawn tween re-times what it draws); it can always be GROWN, because camera manufactures
	# its own holds. See _manufacture_hold: `MAP` + a zero value is a hold by the LOCAL
	# predicate, so unlike the colour lanes there is no fold to consult and no licence to earn.
	var lead_is_hold: bool = n >= 1 and _event_is_hold(table, events[n - 1], lane_name)
	# Where the span STARTS — the previous event's end, or the phase origin for event 0. This is
	# the frame a manufactured lead hold grows FROM, and it is NOT the lead's own start.
	var span_start: int = int(events[n - 1]["end_frame"]) if n >= 1 else 0
	# Where the LEAD starts, one further back — the bound on how much of it can be given up.
	var lead_start: int = int(events[n - 2]["end_frame"]) if n >= 2 else 0
	var own_end: int = int(events[n]["end_frame"])
	var has_right: bool = n + 1 < events.size()
	var trail_is_hold: bool = has_right and _event_is_hold(table, events[n + 1], lane_name)

	# Moving LEFT eats the lead and grows the trail; moving RIGHT does the reverse. Growing is
	# always possible (manufacture), so each direction's room is whatever the side that must
	# SHRINK actually has. Event 0's lead is the origin itself: no room to give up, which is
	# why the first event still never slides left.
	var left_room: int = (span_start - lead_start) if lead_is_hold else 0
	var right_room: int = 0
	if trail_is_hold:
		right_room = int(events[n + 1]["end_frame"]) - own_end
	elif not has_right:
		right_room = S16_MAX - own_end          # the open lane tail (particle's rule)
	if left_room <= 0 and right_room <= 0:
		return _move_refused("wedged: neither neighbour is a hold")
	return {
		"ok": true,
		"delta": clampi(delta, -maxi(0, left_room), maxi(0, right_room)),
		"reason": "",
		"lanes": lanes,
		"lane": lane_name,
		"ordinal": n,
		"lead_is_hold": lead_is_hold,
		"span_start": span_start,
		# Where the lead hold BEGINS — the frame it collapses onto when the slide takes all of
		# it, which is how `move_span` recognises a hold it has emptied (ADR-0101 decision 7).
		"lead_start": lead_start,
		"trail_is_hold": trail_is_hold,
		"has_right": has_right,
	}


## Apply the MOVE slide: shift the span's two boundaries by the planned delta and re-lower the
## whole phase table, exactly as the ripple write does. Structural by construction (a shifted
## end can coalesce with — or split from — a sibling lane's keyframe), so the choke point's
## undo is the pre-edit table object, which `lower` never mutates. Returns {} when refused or
## clamped to a no-op, so nothing is recorded.
static func move_span(data, field_ref: Dictionary, delta: int) -> Dictionary:
	var plan: Dictionary = plan_move(data, field_ref, delta)
	if not plan.get("ok", false) or int(plan.get("delta", 0)) == 0:
		return {}
	var d: int = int(plan["delta"])
	var lanes: Dictionary = plan["lanes"]
	var events: Array = lanes[plan["lane"]]
	var n: int = int(plan["ordinal"])
	var before: int = int(events[n]["end_frame"])
	var landed: int = n

	# The span's own end always moves by the delta — that is the half of the slide nothing else
	# can absorb.
	events[n]["end_frame"] = before + d

	# THE LEAD. An existing hold in front just re-times; where there is none (event 0, or a
	# DRAWN left neighbour) the space in front is not stored at all, so a rightward slide
	# MANUFACTURES the hold that owns it. That is the author's "it would do a spacer to the
	# left of it", and it is what keeps a drawn neighbour's extent untouched.
	#
	# And when the slide takes ALL of it, the hold is DELETED rather than left owning nothing
	# (ADR-0101 decision 7: "dragging into a hold run collapses it and deletes the emptied
	# keyframes, freeing their slots"). A zero-width hold is invisible in the lane — the score
	# only emits a span for `end > prev_end` — which is exactly what made it easy to leave
	# behind: it is still a real opcode, holding a native SoA slot, drawing a marker on the
	# read-only compiled lane, and shifting every later event's ordinal by one. So a Move away
	# and back used to cost a keyframe and renumber the lane every round trip. The span may now
	# butt straight against the drawn event before it, which is decision 7's own wording.
	if bool(plan["lead_is_hold"]):
		var lead_start: int = int(plan["lead_start"])
		var had_width: bool = int(events[n - 1]["end_frame"]) > lead_start
		var lead_end: int = int(events[n - 1]["end_frame"]) + d
		events[n - 1]["end_frame"] = lead_end
		# `had_width` is the difference between a hold THIS SLIDE emptied and one that arrived
		# empty — 8 shipped holds already own nothing. Deleting those would edit ROM data the
		# author never touched, and would make a slide out and back lossy in the other
		# direction. Only the slide's own leavings go.
		if had_width and lead_end == lead_start:
			events.remove_at(n - 1)
			landed = n - 1
	elif d > 0:
		events.insert(n, _manufacture_hold(events[n], int(plan["span_start"]) + d))
		landed = n + 1

	# THE TRAIL. Symmetrically: a leftward slide vacates frames behind the span, and they must
	# belong to a hold rather than stretch the drawn tween that follows — while a rightward one
	# eats into the hold behind and, at full reach, empties it. Same rule, other side: a hold
	# that ends up owning nothing goes.
	if d < 0 and bool(plan["has_right"]) and not bool(plan["trail_is_hold"]):
		events.insert(landed + 1, _manufacture_hold(events[landed], before))
	elif d > 0 and bool(plan["has_right"]) and bool(plan["trail_is_hold"]) \
			and int(events[landed + 1]["end_frame"]) > before \
			and int(events[landed + 1]["end_frame"]) == before + d:
		events.remove_at(landed + 1)

	var phase: String = field_ref.get("context", "")
	var compiled = CameraLowering.lower(lanes)
	data.camera.tables[phase] = compiled
	var faithful: Dictionary = _s16_faithful("end_frame", before + d)
	var capacity: Dictionary = CameraLowering.capacity_faithful(compiled.keyframes.size(), phase)
	if not capacity.get("ok", true):
		faithful = capacity
	var res := _result(before, before + d, faithful)
	res["structural"] = true
	res["relayout"] = true
	res["delta"] = d
	# A manufactured lead hold takes the span's ordinal, so the host re-selects on where the
	# span actually landed rather than on the address it was grabbed by.
	res["event_index"] = landed
	return res


## Is this PARSED lane event a hold — it owns its span and moves nothing? Read through the
## event's ORIGIN keyframe's own `source_mode`, which is the very field `EffectScoreModel.
## _camera_kf_fields` stamps `spacer` from, so the planner and the painter can never disagree
## about which tiles are empty space. (Decoding `ev.source_bits` instead would be a SECOND
## source of truth, and it diverges wherever `command_raw` was never packed.)
static func _event_is_hold(table, ev: Dictionary, lane_name: String) -> bool:
	var origin: int = int(ev.get("origin_index", -1))
	if origin < 0 or origin >= table.keyframes.size():
		return false
	return CameraValueSemantics.is_spacer(lane_name,
		table.keyframes[origin].source_mode, ev["value"])


## A fresh HOLD event for `lane_name`, ending at `end_frame` — the camera analogue of the
## colour lanes' padding keyframe, and a far cheaper one. `MAP` is the single source mode that
## resolves against the camera's OWN current value (`to = current + kf`), so a ZERO value gives
## `to == from` and every interpolation branch holds the pose. That makes it a hold by
## `CameraValueSemantics.is_spacer` — the LOCAL predicate the score stamps `fields.spacer`
## from — so it is invisible by construction, with no fold to ask and no 8%-of-the-time caveat
## the colour manufacture has to guard against. It inherits the moved event's own sub-channel
## bit and a plain LINEAR word; param/flags are zero because a hold reads neither.
static func _manufacture_hold(sibling: Dictionary, end_frame: int) -> Dictionary:
	return {
		"channel": int(sibling["channel"]),
		"end_frame": end_frame,
		"source_bits": _HOLD_SOURCE_BITS,
		"interp_bits": _SEED_INTERP_BITS,
		"param": 0,
		"flags": 0,
		"value": Vector3i.ZERO,
		"origin_index": -1,
	}


static func _move_refused(reason: String) -> Dictionary:
	return {"ok": false, "delta": 0, "reason": reason, "lanes": {}, "lane": "", "ordinal": -1,
		"lead_is_hold": false, "span_start": 0, "lead_start": 0,
		"trail_is_hold": false, "has_right": false}


## After an in-place shared-field fold on a SOLO keyframe, re-lower the phase table: if
## the edit made this keyframe coincide-and-agree with another, `lower` coalesces them and
## the keyframe count DROPS. Only then do we replace the table and mark the edit structural
## (the host re-projects, as it does for a split) — a fold with no merge leaves the fast
## in-place result untouched and non-structural. The mirror of the automatic split.
static func _maybe_remerge(data, phase: String, res: Dictionary) -> void:
	var table = data.camera.get_table(phase)
	if table == null:
		return
	var before_count: int = table.keyframes.size()
	var compiled = CameraLowering.lower(CameraLowering.parse(table))
	if compiled.keyframes.size() < before_count:
		data.camera.tables[phase] = compiled
		res["structural"] = true


## Read a sub-channel event's editable shared field (its OWN value, matching the
## before/after reporting of the in-place command fold).
static func _event_field(ev: Dictionary, field: String) -> int:
	match field:
		"end_frame": return int(ev["end_frame"])
		"source_mode": return int(ev["source_bits"])
		"interpolation": return int(ev["interp_bits"])
		"param_index": return int(ev["param"])
		"flags": return int(ev["flags"])
	return 0


## Write a shared field onto ONE sub-channel event. source/interp arrive as already-
## positioned bits (mask them to their field); param/flags arrive as small ints.
static func _set_event_field(ev: Dictionary, field: String, new_raw: int) -> void:
	match field:
		"end_frame": ev["end_frame"] = new_raw
		"source_mode": ev["source_bits"] = new_raw & 0x01E0
		"interpolation": ev["interp_bits"] = new_raw & 0x1E00
		"param_index": ev["param"] = new_raw & 0x03
		"flags": ev["flags"] = new_raw & 0x07


## Write one component of a Vector3i storage field (angle/position/zoom). Vector3i
## is a value type, so mutate a local copy and assign it back.
static func _apply_vec(kf, field: String, new_raw: int) -> Dictionary:
	var attr: String = _VEC_FIELD[field][0]
	var comp: int = _VEC_FIELD[field][1]
	var vec: Vector3i = kf.get(attr)
	var before: int = vec[comp]
	var was_spacer: bool = CameraValueSemantics.is_spacer(attr, kf.source_mode, vec)
	vec[comp] = new_raw
	kf.set(attr, vec)
	var res := _result(before, new_raw, _s16_faithful(field, new_raw))
	# ZERO CROSSING (ADR-0086 dec. 20). Under `MAP` a zero value is a
	# SPACER — the timeline draws it as empty space — so an edit that gives a hold a real value
	# (or zeroes a real move) FLIPS the lane's rendering and must reproject; without this the
	# woken event stays invisible until some other edit rebuilds the score. Deliberately NOT
	# ADR-0087's unconditional `invalidates_layout` on every value edit: the vec write is the
	# fast in-place path (no re-lower), and a rebuild per spinbox tick is exactly the cost
	# issue #298 is about. Only the crossing pays.
	if was_spacer != CameraValueSemantics.is_spacer(attr, kf.source_mode, vec):
		res["relayout"] = true
	return res


## Fold one command sub-field back into `command_raw` preserving the other bits,
## then recompute the decoded cache. before/after carry the sub-field's OWN value
## (the enum bits or the small int), so undo replays it straight back through here.
static func _apply_command(kf, field: String, new_raw: int) -> Dictionary:
	var clear_mask: int = _CMD_FIELD[field][0]
	var shift: int = _CMD_FIELD[field][1]
	var cr: int = int(kf.command_raw)
	var before: int = (cr & clear_mask) >> shift
	var after: int = new_raw & (clear_mask >> shift)
	kf.command_raw = (cr & ~clear_mask) | ((new_raw << shift) & clear_mask)
	_recompute_command_cache(kf)
	var res := _result(before, after, {"ok": true, "reason": ""})
	# source_mode / interpolation change what the value MEANS, so the value-row labels
	# (#281: offset / Δ / amplitude) must be re-projected in place — ask the page to relayout
	# so the labels (and the sim preview) refresh without waiting for a re-select. param /
	# flags touch neither label nor geometry, so they stay a cheap in-place fold.
	if field == "source_mode" or field == "interpolation":
		res["relayout"] = true
	return res


## Re-derive the decoded sibling fields from the authoritative command_raw
## (mirrors parse_camera_phase_table's decode).
static func _recompute_command_cache(kf) -> void:
	var cr: int = int(kf.command_raw)
	kf.channel_mask = cr & 0x0007
	kf.param_index = (cr >> 3) & 0x03
	kf.flags = (cr >> 13) & 0x07
	kf.source_mode = _SOURCE_MODES.get(cr & 0x01E0, "UNKNOWN_0x%03X" % (cr & 0x01E0))
	kf.interpolation = _INTERPOLATIONS.get(cr & 0x1E00, "UNKNOWN_0x%04X" % (cr & 0x1E00))


static func _result(before: int, after: int, faithful: Dictionary) -> Dictionary:
	return {
		"before_raw": before,
		"after_raw": after,
		"invalidates_sim": true,
		"faithful": faithful,
	}


## Non-destructive Faithful advisory: a camera value only lowers to E###.BIN if it
## fits the signed-16-bit SoA encoding (parse reads back with "<h").
static func _s16_faithful(field: String, raw: int) -> Dictionary:
	if raw < -32768 or raw > 32767:
		return {"ok": false,
			"reason": "%s = %d is outside the signed 16-bit encoding (Free-only)" % [field, raw]}
	return {"ok": true, "reason": ""}


## Resolve a camera field_ref to its live storage keyframe. The authoring address is
## `(camera_channel, ordinal)` — the Nth event of that sub-channel lane (ADR-0086
## amendment, #286) — NOT a raw keyframe index, which a split/merge renumbers. We ask
## the ONE enumerator (CameraLowering.parse) for the lane, take the ordinal-th event,
## and follow its `origin_index` to the packed keyframe it currently occupies.
static func _resolve_keyframe(data, field_ref: Dictionary):
	if data == null or data.camera == null:
		return null
	var table = data.camera.get_table(field_ref.get("context", ""))
	if table == null:
		return null
	var origin: int = _origin_index(table, field_ref)
	if origin < 0:
		return null
	return table.get_keyframe(origin)


## The raw storage index the addressed `(camera_channel, ordinal)` event currently
## lives at — resolved through CameraLowering.parse so it tracks the event across any
## re-lower. -1 when the lane/ordinal doesn't resolve.
static func _origin_index(table, field_ref: Dictionary) -> int:
	var lane_name: String = str(field_ref.get("camera_channel", ""))
	var ordinal: int = int(field_ref.get("ordinal", -1))
	var events: Array = CameraLowering.parse(table).get(lane_name, [])
	if ordinal < 0 or ordinal >= events.size():
		return -1
	return int(events[ordinal]["origin_index"])
