class_name CameraLowering
extends RefCounted
## The camera COALESCING COMPILER between the two camera models (ADR-0086).
##
## Camera authoring is three INDEPENDENT sub-channel lanes — angle / position /
## zoom — each an ordinary lane of ordinary events (source / interp / end / param
## / flags + its own value vec). The STORAGE model packs these into a flat
## `channel_mask` + shared-command-word keyframe array. This module compiles
## between them:
##   * `parse`  expands one masked keyframe into one event per set mask bit.
##   * `lower`  coalesces events that COINCIDE (same end_frame) AND AGREE (same
##     source / interp / param / flags) into one masked keyframe, and SPLITS them
##     into separate keyframes when they disagree.
## parse and lower are INVERSES up to SEMANTIC equivalence (equal per-sub-channel
## event streams) — NOT byte-identity. `channel_mask` is a lowering artifact, born
## only here; the author never touches it (the orphan bug dies by construction).
##
## An **event** is a Dictionary:
##   { "channel": int(1/2/4), "end_frame": int, "source_bits": int,
##     "interp_bits": int, "param": int, "flags": int, "value": Vector3i,
##     "origin_index": int }   # origin_index = the storage keyframe it came from
## (origin_index is provenance for the edit path — it is NOT semantic and is
## ignored by the round-trip comparison; it goes stale after a re-lower.)

const CameraDataClass = ExMateriaEffects.CameraData

# The three sub-channels, in bit order — the authoring lanes and the runtime's
# own search grain (CameraSubsystem CHANNEL_ANGLE/POSITION/ZOOM).
const _CHANNELS := [
	{"name": "angle", "mask": 1, "attr": "angle"},
	{"name": "position", "mask": 2, "attr": "position"},
	{"name": "zoom", "mask": 4, "attr": "zoom"},
]

# Decode maps for the packed command word — the ONE ROM layout shared by parser,
# writer and studio (mirror CameraChannel / parse_effect). Keyed by the already-
# positioned bits so decode is a masked lookup.
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

# Native SoA slot counts per phase table (mirror parse_effect.CAMERA_TRACK_TABLES) —
# the Faithful capacity cap. Post-compile: free authoring can lower to more
# non-mergeable keyframes than these, which Faithful reports (ADR-0086).
const NATIVE_SLOTS := {"phase1": 21, "for_each": 17, "phase2": 21}


## Expand a storage PhaseTable into three sub-channel event streams. Walks the LIVE
## keyframe window (0..max_keyframe inclusive, bounded by the array) in index order —
## mirroring the runtime search and the score projection — and for each keyframe emits
## one event per set mask bit, carrying the shared command word plus that channel's
## own value vec. mask=0 / stale-past-watermark keyframes contribute nothing.
static func parse(table) -> Dictionary:
	var lanes := {"angle": [], "position": [], "zoom": []}
	if table == null:
		return lanes
	var last: int = mini(table.keyframes.size(), table.max_keyframe + 1)
	for i in range(last):
		var kf = table.keyframes[i]
		var cr: int = int(kf.command_raw)
		for cc in _CHANNELS:
			if int(kf.channel_mask) & cc["mask"] == 0:
				continue
			lanes[cc["name"]].append({
				"channel": cc["mask"],
				"end_frame": int(kf.end_frame),
				"source_bits": cr & 0x01E0,
				"interp_bits": cr & 0x1E00,
				"param": (cr >> 3) & 0x03,
				"flags": (cr >> 13) & 0x07,
				"value": kf.get(cc["attr"]),
				"origin_index": i,
			})
	return lanes


## Coalesce three sub-channel event streams back into a storage PhaseTable. Events
## that COINCIDE (same end_frame) AND AGREE (same source / interp / param / flags)
## fold into one masked keyframe (mask = OR of their channel bits, values slotted);
## events that disagree — or two events of the SAME channel — become separate
## keyframes. Keyframes are ordered by end_frame ascending (stable by first-seen
## order), so a per-channel walk of the result re-yields each lane in order: the
## semantic inverse of parse.
static func lower(lanes: Dictionary):
	var groups: Array = []   # each: {end_frame, source_bits, interp_bits, param, flags, mask, angle, position, zoom, ord}
	# Per channel: where its PREVIOUS event landed, as {end, ord}. Only a TIE constrains the
	# tie-break (see _find_group), and only the immediately preceding event of the same lane
	# can be overtaken, so one slot per channel is the whole bookkeeping.
	var prev_landing := {}
	for cc in _CHANNELS:
		for ev in lanes.get(cc["name"], []):
			var g = _find_group(groups, ev, prev_landing.get(cc["name"], {}))
			if g == null:
				g = {
					"end_frame": int(ev["end_frame"]),
					"source_bits": int(ev["source_bits"]),
					"interp_bits": int(ev["interp_bits"]),
					"param": int(ev["param"]),
					"flags": int(ev["flags"]),
					"mask": 0,
					"angle": Vector3i.ZERO,
					"position": Vector3i.ZERO,
					"zoom": Vector3i.ZERO,
					"ord": groups.size(),
				}
				groups.append(g)
			g["mask"] |= int(ev["channel"])
			g[cc["attr"]] = ev["value"]
			prev_landing[cc["name"]] = {"end": int(ev["end_frame"]), "ord": int(g["ord"])}

	# Order by end_frame ascending; ties broken by first-seen order (a stable total
	# order — GDScript sort_custom is not itself stable, so `ord` makes it so).
	groups.sort_custom(func(a, b):
		if a["end_frame"] != b["end_frame"]:
			return a["end_frame"] < b["end_frame"]
		return a["ord"] < b["ord"])

	var table = CameraDataClass.PhaseTable.new()
	table.table_name = ""
	for i in range(groups.size()):
		var g = groups[i]
		var kf = CameraDataClass.Keyframe.new()
		kf.index = i
		kf.end_frame = g["end_frame"]
		kf.angle = g["angle"]
		kf.position = g["position"]
		kf.zoom = g["zoom"]
		var cr: int = (g["flags"] << 13) | g["interp_bits"] | g["source_bits"] \
			| (g["param"] << 3) | g["mask"]
		_apply_command_word(kf, cr)
		table.keyframes.append(kf)
	# max_keyframe is the last LIVE index, inclusive (matches the runtime search bound).
	table.max_keyframe = maxi(0, groups.size() - 1)
	return table


## Non-destructive Faithful advisory on the COMPILED keyframe count: does the lowered
## table fit its phase's native SoA slots? Over-capacity is Free-only (still saved),
## consistent with the conformance profile — capacity is a post-compile property.
static func capacity_faithful(compiled_count: int, phase: String) -> Dictionary:
	var cap: int = int(NATIVE_SLOTS.get(phase, 21))
	if compiled_count > cap:
		return {"ok": false, "reason":
			"camera %s compiled to %d keyframes, over the %d native slots (Free-only)"
			% [phase, compiled_count, cap]}
	return {"ok": true, "reason": ""}


## Find an existing group this event can merge into: same coalescing key AND the
## group does not already carry this channel (two events of one channel never share
## a keyframe). null → the event starts a new group (the SPLIT path).
##
## `prev` is where this channel's PREVIOUS event landed ({end, ord}), and it rules out one more
## group: at a TIE — two events of one lane sharing an end_frame, which is exactly a zero-width
## HOLD (a hold re-timed down to its own start, written by both the boundary drag and MOVE) —
## a group created EARLIER than the previous event's would sort ahead of it and INVERT the lane.
## The final sort is (end_frame, ord) and groups are shared across channels, so a group minted
## during an earlier channel's walk can carry a low ordinal into a later lane's tie; merging
## there would hand a hold the span of the drawn event authored before it, and the camera would
## hold where the author drew a move. Refusing costs one extra keyframe and keeps `lower` the
## inverse of `parse` it claims to be. Nothing but a tie can trigger it, so a lane with no
## coincident same-channel events compiles byte-identically to before this rule existed.
static func _find_group(groups: Array, ev: Dictionary, prev: Dictionary = {}):
	var tied: bool = prev.has("ord") and int(prev["end"]) == int(ev["end_frame"])
	for g in groups:
		if g["end_frame"] == int(ev["end_frame"]) \
				and g["source_bits"] == int(ev["source_bits"]) \
				and g["interp_bits"] == int(ev["interp_bits"]) \
				and g["param"] == int(ev["param"]) \
				and g["flags"] == int(ev["flags"]) \
				and (g["mask"] & int(ev["channel"])) == 0:
			if tied and int(g["ord"]) < int(prev["ord"]):
				continue
			return g
	return null


## Set command_raw + re-derive every decoded sibling field (channel_mask /
## source_mode / interpolation / param_index / flags) the runtime and score read.
## Mirrors CameraChannel._recompute_command_cache — the one decode.
static func _apply_command_word(kf, cr: int) -> void:
	kf.command_raw = cr
	kf.channel_mask = cr & 0x0007
	kf.param_index = (cr >> 3) & 0x03
	kf.flags = (cr >> 13) & 0x07
	kf.source_mode = source_mode_name(cr & 0x01E0)
	kf.interpolation = _INTERPOLATIONS.get(cr & 0x1E00, "UNKNOWN_0x%04X" % (cr & 0x1E00))


## The decoded source-mode NAME for already-positioned `source_bits` — the same lookup
## `_apply_command_word` stamps onto a compiled keyframe, exposed because a caller holding a
## PARSED lane event (which carries `source_bits`, not the name) still needs the name to ask
## `CameraValueSemantics.is_spacer` whether that event is a hold. One decode, not two.
static func source_mode_name(source_bits: int) -> String:
	return _SOURCE_MODES.get(source_bits & 0x01E0, "UNKNOWN_0x%03X" % (source_bits & 0x01E0))
