class_name EffectEditSession
extends RefCounted
## The SINGLE mutation choke point over the raw-authoritative `EffectData` (#255).
## Every author edit flows through `apply_edit(field_ref, new_raw)`: it routes to
## the per-channel encoder by `field_ref.channel`, which writes the raw byte,
## recomputes the derived `value` cache, and declares `invalidates_sim`. The
## inspector stays a dumb renderer and the host `studio_*` layer stays the
## re-derive trigger — neither owns mutation logic. (Slice 2 records the returned
## before/after raw onto a snapshot-command undo stack replayed through this same
## path.)

const ScreenChannel = preload("res://src/effects/studio/ScreenChannel.gd")
const CameraChannel = preload("res://src/effects/studio/CameraChannel.gd")
const PaletteChannel = preload("res://src/effects/studio/PaletteChannel.gd")
const SoundChannel = preload("res://src/effects/studio/SoundChannel.gd")
const SoundContainerChannel = preload("res://src/effects/studio/SoundContainerChannel.gd")
const SoundDefChannel = preload("res://src/effects/studio/SoundDefChannel.gd")
const SoundGhostProjector = preload("res://src/effects/studio/SoundGhostProjector.gd")
const EmitterChannel = preload("res://src/effects/studio/EmitterChannel.gd")
const ParticleTimelineChannel = preload("res://src/effects/studio/ParticleTimelineChannel.gd")
const ColourMovePlan = preload("res://src/effects/studio/ColourMovePlan.gd")
const TimelineHeaderChannel = preload("res://src/effects/studio/TimelineHeaderChannel.gd")
const EffectFlagsChannel = preload("res://src/effects/studio/EffectFlagsChannel.gd")
const TextureChannel = preload("res://src/effects/studio/TextureChannel.gd")
const EffectScriptChannel = preload("res://src/effects/studio/EffectScriptChannel.gd")
const TimeScaleChannel = preload("res://src/effects/studio/TimeScaleChannel.gd")
const FramesetChannel = preload("res://src/effects/studio/FramesetChannel.gd")
const CurveChannel = preload("res://src/effects/studio/CurveChannel.gd")
const CurveExplode = ExMateriaEffects.CurveExplode

var _data  # EffectData — the raw-authoritative authoring model (one storage home).

# Snapshot-command undo stack: {field_ref, before_raw, after_raw} per applied edit.
var _undo_stack: Array = []

# Drag-scoped undo coalesce (ADR-0086 boundary-drag). While active, repeated apply_edits to
# the coalesced field REPLACE the single undo entry's after_raw (keeping the pristine
# before_raw) instead of stacking — so a whole drag gesture is ONE undo. Opt-in: typed edits
# outside a begin/end_coalesce bracket keep the normal one-entry-per-edit behaviour.
var _coalesce_active: bool = false
var _coalesce_key: String = ""
var _coalesce_pushed: bool = false
# RESTORE-THEN-REAPPLY (ADR-0086 dec. 26): the pristine channel state
# captured at grab, replayed before every motion so the drag re-plans from the ORIGINAL data
# plus the current cursor rather than from its own previous output. Empty for the kinds that
# do not need it — see begin_coalesce.
var _coalesce_snapshot: Dictionary = {}


func _init(effect_data) -> void:
	_data = effect_data


## Open a drag-scoped coalesce for `field_ref`: the first apply_edit to this field pushes a
## single undo entry; every later apply_edit to the SAME field within the bracket replaces
## that entry's after_raw. Call at fire_edge_drag_started; close with end_coalesce (release).
func begin_coalesce(field_ref: Dictionary) -> void:
	_coalesce_active = true
	_coalesce_key = _ref_key(field_ref)
	_coalesce_pushed = false
	# COLOUR ONLY. A colour span's spacer verdict is a LIVE FOLD over the whole stream
	# (`SpacerVerdicts`) whose input includes duration — so a boundary drag can wake a neighbour
	# into a drawn tween, or put one to sleep as a hold, WHILE THE MOUSE IS STILL DOWN, changing
	# which span the grip writes to underneath the author. Snapshotting at grab makes every
	# motion re-plan from the pristine state, exactly as `move_preview` does, so the gesture is
	# idempotent and no intermediate state can steer it.
	#
	# Camera is deliberately excluded: its spacer test is `CameraValueSemantics`' LOCAL
	# `MAP`+zero on the stored value, which no `end_frame` drag can flip, and its boundary
	# arithmetic is absolute (no quantization to compound). Sound's fire-drag brackets a gap
	# trade with its own math. Paying for a per-motion channel copy where nothing can drift
	# would be cost without a fault.
	_coalesce_snapshot = _capture_structural(field_ref) if _is_colour_boundary(field_ref) else {}


## Close the current coalesce bracket. Later edits stack normally again.
func end_coalesce() -> void:
	_coalesce_active = false
	_coalesce_key = ""
	_coalesce_pushed = false
	_coalesce_snapshot = {}


## Is this bracket a COLOUR boundary drag — the one gesture whose own output can change the
## rule it is being steered by? Keyed on the synthetic boundary fields, not the channel alone,
## so a coalesced colour VALUE edit (which never moves a boundary) keeps the cheap path.
func _is_colour_boundary(field_ref: Dictionary) -> bool:
	return String(field_ref.get("channel", "")) in ["palette", "screen"] \
		and String(field_ref.get("field", "")) in ["boundary_end", "duration"]


## Replay the pristine state captured at grab, so the imminent apply_edit re-plans from the
## ORIGINAL keyframes. No-op outside a colour boundary bracket.
func _restore_coalesce_pristine() -> void:
	if _coalesce_snapshot.has("palette_snapshot"):
		PaletteChannel.restore(_data, _coalesce_snapshot["palette_snapshot"])
	elif _coalesce_snapshot.has("screen_snapshot"):
		ScreenChannel.restore(_data, _coalesce_snapshot["screen_snapshot"])


## A stable value-key for a field_ref (Dictionary identity is unreliable across the fresh
## dicts a drag builds per motion), so coalesce matching compares content, not object.
## Covers every channel's address dims: camera/palette/screen use context, sound uses
## phase + channel_index (the ripple fire-drag brackets a sound gap), and a curve edit
## adds its own index — since the ADR-0089 explode every use site has its OWN curve, so
## two curve commits are the same field only when they are the same use site's.
func _ref_key(field_ref: Dictionary) -> String:
	return "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [
		str(field_ref.get("channel", "")), str(field_ref.get("context", "")),
		str(field_ref.get("phase", "")), str(field_ref.get("channel_index", "")),
		str(field_ref.get("camera_channel", "")), str(field_ref.get("ordinal", "")),
		str(field_ref.get("event_index", "")), str(field_ref.get("field", "")),
		# The FEDS drag's address (ADR-0085 19b): a sound_def gesture is keyed to the TRACK
		# and the span head it grabbed, so two brackets can never be mistaken for one.
		str(field_ref.get("track_idx", "")), str(field_ref.get("at", ""))] \
		+ ("|c%d" % int(field_ref.get("curve_index", -1)) if field_ref.has("curve_index") else "")


## Apply one raw-byte edit and return `{before_raw, after_raw, invalidates_sim}`.
## The caller (host) re-derives per `invalidates_sim`: false → repaint in place at
## the current frame; true → reset + re-pump (ADR-0070). The edit is recorded on the
## undo stack for `undo()`.
func apply_edit(field_ref: Dictionary, new_raw) -> Dictionary:
	# RESTORE-THEN-REAPPLY (ADR-0086 dec. 26). Inside a colour boundary
	# bracket, rewind to the state captured at grab before applying, so this motion re-plans
	# from the ORIGINAL keyframes plus the current cursor rather than from its own previous
	# output. `new_raw` is an ABSOLUTE boundary, so replaying it off the pristine state is
	# exactly the drag the author is making — and the gesture becomes idempotent. Gated on the
	# bracket's own key so an unrelated edit slipping into the bracket cannot rewind the channel.
	if _coalesce_active and not _coalesce_snapshot.is_empty() \
			and _ref_key(field_ref) == _coalesce_key:
		_restore_coalesce_pristine()
	# A RIPPLED camera end_frame edit (ADR-0087 decs. 15-16) recompiles the lane —
	# downstream shifts, coalesced keyframes split — so its undo is the STRUCTURAL
	# table-object stash (the insert/delete-verb shape), captured BEFORE dispatch, not a
	# scalar replay whose re-lower could diverge from the recorded bytes.
	var ripple_stash: Dictionary = {}
	if String(field_ref.get("channel", "")) == "camera" \
			and String(field_ref.get("field", "")) == "end_frame" \
			and bool(field_ref.get("ripple", false)):
		ripple_stash = _capture_structural(field_ref)
	# A particle BOUNDARY edit (ADR-0089 particle_timeline resize) can go STRUCTURAL mid-drag
	# (shrink-against-a-wall auto-opens a null span; a grow-to-zero-width gap is reclaimed), so
	# its undo is the channel snapshot captured BEFORE dispatch — the same shape ripple uses,
	# not a scalar replay whose structural side effect wouldn't unwind.
	if String(field_ref.get("channel", "")) == "particle" \
			and String(field_ref.get("field", "")) == "boundary_end":
		ripple_stash = _capture_structural(field_ref)
	# A script-pattern SWAP (ADR-0094) replaces script_ops wholesale — a structural edit
	# whose undo is the pre-swap snapshot, captured BEFORE dispatch.
	if String(field_ref.get("channel", "")) == "script_pattern":
		ripple_stash = _capture_structural(field_ref)
	# A SHAPE PICK (ADR-0089 curve-ownership decision 3) can MINT a curve — appending to the
	# array and repointing the use site — so its undo is a snapshot of the array plus the
	# site's address and samples, not a scalar replay of a value that may not have existed.
	if String(field_ref.get("channel", "")) == "curve_assign":
		ripple_stash = _capture_structural(field_ref)
	var res: Dictionary = _dispatch(field_ref, new_raw)
	if res.is_empty():
		return res
	# An encoder can report `no_edit` — the request changed nothing (e.g. enabling a COLD
	# screen no-op with no stash to restore, or a REFUSED over-s16 ripple) — so nothing
	# lands on the undo stack.
	if res.get("no_edit", false):
		return res
	if not ripple_stash.is_empty():
		# Drag-scoped coalesce keeps the FIRST stash: one drag bracket = one undo entry
		# whose restore is the pre-DRAG table. Later motions in the bracket record nothing.
		if _coalesce_active and _ref_key(field_ref) == _coalesce_key and _coalesce_pushed \
				and not _undo_stack.is_empty() \
				and (_undo_stack.back().has("snapshot") or _undo_stack.back().has("particle_snapshot")):
			return res
		_undo_stack.push_back(ripple_stash)
		if _coalesce_active and _ref_key(field_ref) == _coalesce_key:
			_coalesce_pushed = true
		return res
	# Drag-scoped coalesce: once this gesture has pushed its single entry and the top of the
	# stack is still that same-field scalar edit, fold this motion into it (advance after_raw,
	# keep the pristine before_raw) so one drag = one undo. Otherwise push a fresh entry.
	if _coalesce_active and _ref_key(field_ref) == _coalesce_key and _coalesce_pushed \
			and not _undo_stack.is_empty() \
			and _undo_stack.back().has("field_ref") \
			and _ref_key(_undo_stack.back()["field_ref"]) == _coalesce_key:
		_undo_stack.back()["after_raw"] = res["after_raw"]
	else:
		_undo_stack.push_back({
			"field_ref": field_ref,
			"before_raw": res["before_raw"],
			"after_raw": res["after_raw"],
		})
		if _coalesce_active and _ref_key(field_ref) == _coalesce_key:
			_coalesce_pushed = true
	return res



## Is this edit a LATER motion of an open drag bracket whose single snapshot is already on the
## stack? Then that snapshot — not a fresh capture — is the pristine state to re-plan from.
func _in_snapshot_bracket(field_ref: Dictionary) -> bool:
	return _coalesce_active and _ref_key(field_ref) == _coalesce_key and _coalesce_pushed \
		and not _undo_stack.is_empty() and _is_snapshot_entry(_undo_stack.back())


func _is_snapshot_entry(cmd: Dictionary) -> bool:
	return cmd.has("snapshot") or cmd.has("palette_snapshot") or cmd.has("screen_snapshot") \
		or cmd.has("particle_snapshot") or cmd.has("script_snapshot")


## Put a structural snapshot back — the shared restore behind `undo()` and the pristine
## re-plan. Restoring the stashed object wholesale IS byte-exact: the verbs never mutate it.
func _restore_structural(cmd: Dictionary) -> void:
	if cmd.has("snapshot"):
		# The channel tag routes the restore; entries without one are camera (the
		# historical shape).
		if cmd.get("channel", "") == "sound":
			_data.sound[cmd["phase"]][cmd["channel_index"]] = cmd["snapshot"]
		elif cmd.get("channel", "") == "feds":
			# Prune-for-real (ADR-0085 2026-08-13): the swapped-out bank is restored wholesale.
			_data.feds_bank = cmd["snapshot"]
		else:
			_data.camera.tables[cmd["phase"]] = cmd["snapshot"]
	elif cmd.has("palette_snapshot"):
		PaletteChannel.restore(_data, cmd["palette_snapshot"])
	elif cmd.has("screen_snapshot"):
		ScreenChannel.restore(_data, cmd["screen_snapshot"])
	elif cmd.has("particle_snapshot"):
		ParticleTimelineChannel.restore(_data, cmd["particle_snapshot"])
	elif cmd.has("script_snapshot"):
		_data.script_ops = cmd["script_snapshot"]


## Insert a new lane event at `field_ref.frame` — the INSERT-WAYPOINT verb (ADR-0086
## second amendment, generalised to palette + screen by ADR-0087). Structural, so undo is
## snapshot-based (per channel) rather than a scalar replay.
func insert_event(field_ref: Dictionary) -> Dictionary:
	return _structural_verb(field_ref, "insert")


## Delete the addressed lane event — the inverse of insert-waypoint. Same snapshot-undo
## contract as `insert_event`.
func delete_event(field_ref: Dictionary) -> Dictionary:
	return _structural_verb(field_ref, "delete")


## Sound the addressed FEDS rest span — delete's inverse on the time lane (ADR-0085
## amendment 2026-08-19). FEDS-only: it is the one channel whose lane is fully tiled, so
## it is the one channel where a delete leaves a rest to undo. Same snapshot-undo contract.
func unrest_event(field_ref: Dictionary) -> Dictionary:
	return _structural_verb(field_ref, "unrest")


## Paint a note INSIDE the addressed FEDS rest span, splitting it (ADR-0085 amendment
## 2026-08-19b §2). FEDS-only for the same reason the un-rest is: it is the one channel
## whose time is fully tiled, so it is the one channel with silence to paint into. The
## only structural verb that changes the event COUNT of a fully-tiled lane, which is
## exactly why it rides the snapshot contract rather than a replay.
func paint_event(field_ref: Dictionary) -> Dictionary:
	return _structural_verb(field_ref, "paint")


## DRAG a FEDS note span through the silence around it (ADR-0085 amendment 2026-08-19b
## §2/§3) — move, resize-right and resize-left behind one verb, because all three write the
## same kind of number: a rest's tick count. FEDS-only like the un-rest and the paint, and
## for the same reason: no other channel tiles its time, so no other channel has silence for
## a drag to spend. Bracketed by `begin_coalesce` / `end_coalesce`, one gesture is ONE undo
## whose restore is the pre-drag bank, and every motion re-plans from that pristine state —
## so dragging past a rest and back brings that rest back (ADR-0095 §4).
func drag_event(field_ref: Dictionary) -> Dictionary:
	return _structural_verb(field_ref, "drag")


## SET the addressed FEDS track's OUTRO — the silence between its last authored event and
## its EndBar (ADR-0085 amendment 2026-08-19c). FEDS-only like the other three time verbs,
## and the only one of the six that moves `end_tick`: every other verb re-tiles a fixed
## clock, this one is where new time comes from. Same snapshot-undo contract — the verb
## swaps the whole bank, so the pre-edit object IS the exact restore.
func set_outro(field_ref: Dictionary) -> Dictionary:
	return _structural_verb(field_ref, "outro")


## Shared plumbing for the two structural verbs. Because a verb REPLACES its storage
## object (camera: `data.camera.tables[phase]`; sound: `data.sound[phase][ci]`) with a
## freshly-built one — it never mutates the old one in place — stashing the pre-edit
## object IS an exact snapshot: undo just puts it back. Records a channel-tagged
## `{snapshot, …}` entry the hybrid `undo()` recognizes.
func _structural_verb(field_ref: Dictionary, verb: String) -> Dictionary:
	# PRISTINE RE-PLAN, the structural half (ADR-0095 §4, generalized by ADR-0085 19b §6).
	# A LATER motion of an open drag bracket restores the bracket's one snapshot before
	# re-dispatching, so every motion is planned against the pre-drag bytes instead of
	# compounding on the previous motion's splices — which is what makes a consuming drag
	# self-inverse while the mouse is still held. It records nothing: the entry already on
	# the stack IS the pre-drag state, so one gesture stays one undo.
	if _in_snapshot_bracket(field_ref):
		_restore_structural(_undo_stack.back())
		return _dispatch_structural(field_ref, verb)
	var restore: Dictionary = _capture_structural(field_ref)
	var res: Dictionary = _dispatch_structural(field_ref, verb)
	if not res.is_empty() and not restore.is_empty():
		_undo_stack.push_back(restore)
		if _coalesce_active and _ref_key(field_ref) == _coalesce_key:
			_coalesce_pushed = true
	return res


## Capture the pre-edit structural snapshot for `field_ref`'s channel — the token the hybrid
## `undo()` restores. Sound: the whole channel dict object. Camera: the whole phase table
## object. Palette / screen / particle: a deep copy of the channel.
func _capture_structural(field_ref: Dictionary) -> Dictionary:
	match field_ref.get("channel", ""):
		"sound":
			var phase: String = str(field_ref.get("phase", ""))
			var ci: int = int(field_ref.get("channel_index", -1))
			return {"snapshot": _sound_channel(phase, ci), "channel": "sound",
				"phase": phase, "channel_index": ci}
		"camera":
			var phase: String = field_ref.get("context", "")
			return {"snapshot": _camera_table(phase), "phase": phase}
		"palette":
			return {"palette_snapshot": PaletteChannel.snapshot(_data, field_ref)}
		"screen":
			return {"screen_snapshot": ScreenChannel.snapshot(_data, field_ref)}
		"particle":
			return {"particle_snapshot": ParticleTimelineChannel.snapshot(_data, field_ref)}
		"sound_def":
			# Structural FEDS authoring (ADR-0085 2026-08-18b): the verbs swap the whole
			# FedsBank rather than mutating it, so the pre-edit bank IS the snapshot —
			# the prune's contract, restored through the same "feds" channel tag.
			return {"snapshot": _data.feds_bank, "channel": "feds"}
		"script_pattern":
			# A pattern swap replaces script_ops wholesale (structure-preserving section
			# rewrite, ADR-0094); stash the pre-swap array to restore on undo.
			return {"script_snapshot": _data.script_ops}
		"curve_assign":
			# Three things a pick can move, so all three are stashed: the curve ARRAY (a
			# mint appends to it), the use site's ADDRESS, and — when it already had a
			# curve — that curve's SAMPLES, which a shallow array copy still shares.
			var e: int = int(field_ref.get("emitter_index", -1))
			var slot: String = str(field_ref.get("slot", ""))
			var kind: String = str(field_ref.get("kind", "param"))
			var idx: int = CurveExplode.site_index(_data, e, slot, kind)
			var samples: Array = []
			if idx >= 0 and idx < _data.curves.size():
				samples = _data.curves[idx].samples.duplicate()
			return {"curve_assign_snapshot": {"curves": _data.curves.duplicate(),
				"emitter_index": e, "slot": slot, "kind": kind, "index": idx,
				"samples": samples}}
	return {}


## Prune-for-real (ADR-0085 2026-08-13 amendment): DELETE every no-op opcode (Muted ∪ Inert)
## from the OPEN pair's two tracks and swap the whole FedsBank for the smaller, byte-exact
## result. Deleting opcodes SHRINKS the track, so this cannot ride the same-size sound_def
## patcher (`apply_raw`) — it is a structural verb. The rewrite + offset-table/section-length
## fixup already exist in `SoundGhostProjector.build_pruned_bank` (the proof-only A/B's engine);
## here it becomes a real mutation. Undo is snapshot-based like the camera insert/delete verbs:
## the WHOLE pre-edit bank is stashed (never mutated in place) and restored wholesale. A true
## no-op when the pair has nothing prunable — no swap, no undo entry, {} returned — so the
## button does nothing rather than pushing an empty edit. Returns
## `{invalidates_feds, pair_idx, before_bytes, after_bytes}` so the host reuses the SAME
## re-derive path a `sound_def` byte patch takes.
## Replace the effect's texture sheet from an imported RGBA image (#280,
## ADR-0199). A wholesale swap, so it records the SNAPSHOT undo shape rather than
## a scalar before/after — the same path `prune_feds_noops` takes for the feds
## bank. Returns the channel's verdict plus `invalidates_sim`; a refused import
## (wrong dimensions, wrong byte count) records nothing.
func replace_texture(rgba: PackedByteArray, width: int, height: int) -> Dictionary:
	if _data == null:
		return {"ok": false, "error": "no effect loaded", "invalidates_sim": false}
	var res: Dictionary = TextureChannel.replace(_data, rgba, width, height)
	if not res.get("ok", false):
		return res
	_undo_stack.push_back({"texture_snapshot": res["texture_snapshot"]})
	return res


func prune_feds_noops(pair_idx: int) -> Dictionary:
	if _data == null or _data.feds_bank == null:
		return {}
	var before = _data.feds_bank
	var pruned = SoundGhostProjector.build_pruned_bank(before, pair_idx, [0, 1])
	if pruned == null or pruned.raw == before.raw:
		return {}   # bad pair, or no prunable no-ops → true no-op
	_data.feds_bank = pruned
	_undo_stack.push_back({"snapshot": before, "channel": "feds"})
	return {
		"invalidates_feds": true,
		"pair_idx": pair_idx,
		"before_bytes": before.raw.size(),
		"after_bytes": pruned.raw.size(),
	}


## Slide a span by `delta` — the MOVE verb (ADR-0089 particle_timeline, generalised to
## palette / screen / camera by ADR-0101 decision 3). One clamped delta shifts BOTH of the
## span's boundaries (width preserved); the two immediate neighbours absorb it and everything
## outside them stays pinned. A span wedged between two drawn neighbours is refused.
##
## The KIND decides the lowering, never the rule: particle writes two absolute `boundary_raw`
## times as ONE apply_compound (one undo — the sound fire-drag precedent); camera and the two
## colour kinds re-time structurally, so their undo is the pre-edit channel SNAPSHOT (the
## insert/delete-verb shape). Returns {} when refused or clamped to a no-op — nothing recorded.
## Distinct from the live body-drag below, which is the same verb under one gesture-wide undo.
func move_span(field_ref: Dictionary, delta: int) -> Dictionary:
	if String(field_ref.get("channel", "")) == "particle":
		var plan: Dictionary = ParticleTimelineChannel.plan_move(_data, field_ref, delta)
		if not plan.get("ok", false):
			return {}
		if int(plan.get("delta", 0)) == 0:
			return {}   # clamped to a no-op — nothing to record
		return apply_compound(plan["edits"])
	# Structural kinds: stash the pre-edit channel first, then apply; an empty result means
	# refused, so the stash is dropped rather than pushed.
	var stash: Dictionary = _capture_structural(field_ref)
	var res: Dictionary = _perform_move(field_ref, delta, _move_context(field_ref))
	if res.is_empty():
		return {}
	if not stash.is_empty():
		_undo_stack.push_back(stash)
	return res


## --- Live Move body-drag (ADR-0089 particle_timeline; ADR-0101 dec. 3 for the rest) -------
## A body-drag emits many deltas; to keep it ONE undo, the drag captures a single channel
## snapshot at grab time, and every motion RESTORES that snapshot then re-applies the absolute
## delta (so motions never compound). Release records the one snapshot — but only if the span
## actually moved, so a plain click (which arms and closes the bracket without a motion) leaves
## the undo stack alone. Distinct from move_span (the discrete, self-contained slide).
var _move_snapshot: Dictionary = {}
var _move_active: bool = false
var _move_dirty: bool = false
# The gesture-scoped MOVE CONTEXT: the per-kind facts a plan needs that are expensive to
# recompute (the colour lanes' fold-derived hold verdicts + slot budget). Captured ONCE at grab
# and reused every motion — correct precisely because every motion re-plans from the SAME
# pristine snapshot, so the verdicts it describes never go stale mid-gesture. Empty for the
# kinds whose hold predicate is local (particle: `emitter_id == 0`; camera:
# `CameraValueSemantics.is_spacer`).
var _move_ctx: Dictionary = {}
# The STRUCTURE-FREE gesture's pending slide: the address it grabbed and the planner's clamped
# delta from the LAST motion. Only the colour kinds use these — their motions plan and stop, so
# the whole gesture's effect on the data is this one number, spent once by `end_move`. A refused
# or clamped-to-zero motion resets the delta to 0, which is how dragging back onto home un-moves
# the span: release then has nothing to commit and the click rule takes over.
var _move_ref: Dictionary = {}
var _move_delta: int = 0


## Grab: capture the drag-start channel snapshot (the single undo entry the release records)
## plus the gesture-scoped move context.
func begin_move(field_ref: Dictionary) -> void:
	_move_snapshot = _capture_structural(field_ref)
	_move_ctx = _move_context(field_ref)
	_move_active = true
	_move_dirty = false
	_move_ref = {}
	_move_delta = 0


## Motion. TWO SHAPES, by kind.
##
## STRUCTURE-FREE (the colour kinds — ADR-0089's Drag preview, generalised from particle by this
## commit): plan and STOP. Not one keyframe is written; the motion's whole output is the
## planner's clamped delta, which the page draws the span at (`start + delta`) and which
## `end_move` spends once. The old shape restored the grab snapshot, re-planned, minted padding,
## deleted emptied runs and renumbered the lane — ~95ms a motion on E317 — and then threw all of
## it away on the next motion to re-plan from the same pristine snapshot. The answer was already
## a pure function of the grab context and the absolute delta; this stops paying for it in data.
##
## APPLY-PER-MOTION (particle, camera): restore the drag-start state and re-apply the ABSOLUTE
## `delta` from grab, so the slide never compounds. Particle's move is two scalar boundary
## writes and camera's is a small table relower — neither pays the colour fold, so neither needs
## the preview.
##
## Records NO undo either way — the release owns the single entry. Returns the reproject hint;
## `{}` means the gesture could not be addressed at all (no live bracket). Note that a
## structure-free motion answers with `delta: 0` rather than `{}` where the PLAN refuses: the
## page must tell "draw it at home" apart from "no answer", because the motion before it may
## have previewed a slide the author has now dragged back off.
func move_preview(field_ref: Dictionary, delta: int) -> Dictionary:
	if not _move_active or _move_snapshot.is_empty():
		return {}
	if _is_structure_free_move(field_ref):
		var pv: Dictionary = _preview_move(field_ref, delta)
		_move_ref = field_ref
		_move_delta = int(pv.get("delta", 0))
		return {
			# Nothing was written, so there is nothing to re-derive and nothing to re-project:
			# the page repaints one rect at an offset and that is the entire per-motion cost.
			"invalidates_sim": false,
			"invalidates_layout": false,
			"preview_only": true,
			"delta": _move_delta,
			"granularity": int(pv.get("granularity", 0)),
		}
	_restore_move_pristine()
	var res: Dictionary = _perform_move(field_ref, delta, _move_ctx)
	if not res.is_empty():
		_move_dirty = true
	return res


## Release. For a STRUCTURE-FREE gesture this is where the move happens at all: one plan, one
## splice, at the last previewed delta, against data no motion touched — so it is byte-for-byte
## the discrete verb's own result, and the drag is structural exactly once instead of once per
## frame of cursor travel. Then the drag-start snapshot is recorded as the SINGLE undo entry
## (unless the span never left its start — a click records nothing, and a slide dragged back
## onto home is a click by the time it gets here).
##
## Returns the commit's reproject hint (with `event_index`: a colour Move renumbers the lane, so
## this is where the page learns the span's new address). Empty for the apply-per-motion kinds,
## whose last motion already reported theirs, and for a gesture that committed nothing.
func end_move() -> Dictionary:
	var res: Dictionary = {}
	if _move_active and _move_delta != 0 and not _move_ref.is_empty():
		res = _perform_move(_move_ref, _move_delta, _move_ctx)
		if not res.is_empty():
			_move_dirty = true
	if _move_active and _move_dirty and not _move_snapshot.is_empty():
		_undo_stack.push_back(_move_snapshot)
	_move_active = false
	_move_dirty = false
	_move_snapshot = {}
	_move_ctx = {}
	_move_ref = {}
	_move_delta = 0
	return res


## Does this address's kind drag STRUCTURE-FREE? Every kind whose Move is STRUCTURAL does —
## the two colour kinds and camera. Their slides do not merely re-time a boundary: they mint
## padding keyframes, delete the ones a slide empties, and RENUMBER everything after. That is a
## real edit to make sixty times a second for a preview the author sees as one rectangle moving,
## and the renumber means the ordinal they grabbed names a different event one motion later.
##
## Particle is the exception and stays apply-per-motion: its Move is two scalar `boundary_raw`
## writes with no insert, no delete and no renumber, so there is no structure to be free of.
static func _is_structure_free_move(field_ref: Dictionary) -> bool:
	var kind := String(field_ref.get("channel", ""))
	return kind == "palette" or kind == "screen" or kind == "camera"


## PLAN one move without applying it — the per-kind arm of the structure-free motion, mirroring
## `_perform_move`'s routing so the two cannot answer differently about the same gesture. Each
## kind's planner is already pure; this only routes and normalises. Returns `{}` for a refused
## or clamped-to-zero slide, which the caller reports as `delta: 0`.
func _preview_move(field_ref: Dictionary, delta: int) -> Dictionary:
	match String(field_ref.get("channel", "")):
		"palette", "screen":
			# Both colour kinds share one planner and one context shape (ADR-0101), so this is
			# ONE arm on purpose — a forked colour rule is how the last three bugs here happened.
			return ColourMovePlan.preview(_move_ctx, int(field_ref.get("event_index", -1)), delta)
		"camera":
			# `CameraChannel.plan_move` parses the table into fresh lanes and computes over
			# those, so calling it alone leaves `_data` untouched — the same purity the colour
			# planner has, just arrived at differently (camera's hold predicate is local, so it
			# needs no gesture-scoped context at all and `_move_ctx` is empty for it).
			var p: Dictionary = CameraChannel.plan_move(_data, field_ref, delta)
			if not p.get("ok", false) or int(p.get("delta", 0)) == 0:
				return {}
			# Camera is frame-granular unconditionally: absolute `end_frame`s, no length
			# encoding, so no slot budget and nothing to degrade to eights.
			return {"delta": int(p["delta"]), "granularity": 1}
	return {}


## Replay the drag-start channel state so the imminent motion re-plans from the ORIGINAL
## keyframes. Routed by the snapshot's own shape — the same tags `_capture_structural` mints
## and `undo()` restores.
func _restore_move_pristine() -> void:
	if _move_snapshot.has("particle_snapshot"):
		ParticleTimelineChannel.restore(_data, _move_snapshot["particle_snapshot"])
	elif _move_snapshot.has("palette_snapshot"):
		PaletteChannel.restore(_data, _move_snapshot["palette_snapshot"])
	elif _move_snapshot.has("screen_snapshot"):
		ScreenChannel.restore(_data, _move_snapshot["screen_snapshot"])
	elif _move_snapshot.has("snapshot") and _move_snapshot.has("phase"):
		# Camera: the verbs REPLACE `tables[phase]` with a freshly lowered table and never
		# mutate the stashed one, so putting the object back is an exact rewind.
		_data.camera.tables[_move_snapshot["phase"]] = _move_snapshot["snapshot"]


## The gesture-scoped facts a colour plan needs (fold-derived hold verdicts + slot budget).
## Empty for particle / camera, whose hold predicate is decidable locally per motion.
func _move_context(field_ref: Dictionary) -> Dictionary:
	match String(field_ref.get("channel", "")):
		"palette":
			return PaletteChannel.move_context(_data, field_ref)
		"screen":
			return ScreenChannel.move_context(_data, field_ref)
	return {}


## Plan + apply ONE move for whichever kind `field_ref` addresses, returning the host's
## reproject hint (or {} when refused / a no-op). The rule lives in each channel's `plan_move`;
## this only routes and normalises the hint.
func _perform_move(field_ref: Dictionary, delta: int, ctx: Dictionary) -> Dictionary:
	match String(field_ref.get("channel", "")):
		"particle":
			var plan: Dictionary = ParticleTimelineChannel.plan_move(_data, field_ref, delta)
			if not plan.get("ok", false):
				return {}
			for e in plan["edits"]:
				_dispatch(e["field_ref"], e["new_raw"])
			return {"invalidates_sim": true, "invalidates_layout": true,
				"delta": int(plan.get("delta", 0))}
		"camera":
			return _move_hint(CameraChannel.move_span(_data, field_ref, delta), true)
		"palette":
			return _move_hint(PaletteChannel.move_span(_data, field_ref, delta, ctx), false)
		"screen":
			return _move_hint(ScreenChannel.move_span(_data, field_ref, delta, ctx), false)
	return {}


## Normalise a structural move's result into the host's reproject hint. `sim` is the kind's
## own re-derive answer: camera framing is FOLDED during the sim, the colour lanes are
## READ-LIVE (PaletteSubsystem / ScreenSubsystem rebuild from the keyframes every frame).
func _move_hint(res: Dictionary, sim: bool) -> Dictionary:
	if res.is_empty():
		return {}
	var hint := {
		"invalidates_sim": sim,
		"invalidates_layout": true,
		"structural": true,
		"delta": int(res.get("delta", 0)),
	}
	# A colour move is STRUCTURAL, so the span's raw index moved with it — the host re-selects
	# on the new address rather than on a stale `lane#index`. `granularity` is decision 5's
	# tell (1 = the span tracks the cursor frame by frame, 8 = it snaps in eights).
	if res.has("event_index"):
		hint["event_index"] = int(res["event_index"])
	if res.has("granularity"):
		hint["granularity"] = int(res["granularity"])
	return hint


## Apply SEVERAL raw edits as ONE gesture — the fire-drag trades the two neighbouring
## sound gaps, and one drag must be one undo. Each member (`{field_ref, new_raw}`) is
## dispatched through the SAME per-channel path as apply_edit, and the whole set is
## recorded as a SINGLE compound undo command (its members' pre-edit raws), so undo()
## unwinds them all in one step. Returns `{invalidates_sim, results}` — invalidates_sim
## is the OR over members (any sim-invalidating member forces a re-derive); results is
## the per-member dispatch return in order. An empty list records nothing.
func apply_compound(edits: Array) -> Dictionary:
	var members: Array = []
	var results: Array = []
	var invalidates := false
	var invalidates_layout := false
	for e in edits:
		var field_ref: Dictionary = e["field_ref"]
		# A MEMBER'S UNDO IS NOT ALWAYS A SCALAR REPLAY. `apply_edit` has always known that
		# a `curve_assign` MINTS — appending to the curve array and repointing a use site —
		# so its undo is a snapshot rather than a `before_raw` that may name a curve which
		# did not exist. This loop did not: it read `res["before_raw"]` unconditionally, and
		# a member without one threw INSIDE the loop, which in a coroutine unwinds silently.
		# Measured cost when the colour toggle first composed a flag flip with three mints:
		# the flag applied, the first mint applied, the second and third never dispatched,
		# and no undo entry was pushed at all — the whole gesture half-landed and reported
		# nothing. Capture the structural stash for the channels that need one, and treat a
		# missing `before_raw` as "this member is not undoable" rather than as a crash.
		var stash: Dictionary = {}
		if String(field_ref.get("channel", "")) == "curve_assign":
			stash = _capture_structural(field_ref)
		var res: Dictionary = _dispatch(field_ref, e["new_raw"])
		if res.is_empty() or res.get("no_edit", false):
			continue
		if not stash.is_empty():
			members.append(stash)
		elif res.has("before_raw"):
			members.append({"field_ref": field_ref, "before_raw": res["before_raw"]})
		results.append(res)
		invalidates = invalidates or bool(res.get("invalidates_sim", false))
		invalidates_layout = invalidates_layout or bool(res.get("invalidates_layout", false))
	if not members.is_empty():
		_undo_stack.push_back({"compound": members})
	return {"invalidates_sim": invalidates, "invalidates_layout": invalidates_layout, "results": results}


## Unwind the most recent edit. HYBRID stack, three command kinds: a STRUCTURAL entry
## carries a table `snapshot` (restore it wholesale); a COMPOUND entry replays ALL its
## members in reverse order (mirroring how they were applied) as one undo; a SCALAR entry
## replays its pre-edit raw through the same dispatch path (so the value cache and any
## re-derive stay consistent). Returns false when there is nothing to undo. The
## replay/restore is NOT itself recorded.
func undo() -> bool:
	if _undo_stack.is_empty():
		return false
	var cmd: Dictionary = _undo_stack.pop_back()
	if cmd.has("snapshot"):
		# The channel tag routes the restore; entries without one are camera (the
		# historical shape). Restoring the stashed object wholesale IS byte-exact —
		# the verbs never mutated it.
		if cmd.get("channel", "") == "sound":
			_data.sound[cmd["phase"]][cmd["channel_index"]] = cmd["snapshot"]
		elif cmd.get("channel", "") == "feds":
			# Prune-for-real (ADR-0085 2026-08-13): the swapped-out bank is restored wholesale —
			# the verb never mutated it, so this is byte-exact.
			_data.feds_bank = cmd["snapshot"]
		else:
			_data.camera.tables[cmd["phase"]] = cmd["snapshot"]
	elif cmd.has("palette_snapshot"):
		PaletteChannel.restore(_data, cmd["palette_snapshot"])
	elif cmd.has("screen_snapshot"):
		ScreenChannel.restore(_data, cmd["screen_snapshot"])
	elif cmd.has("particle_snapshot"):
		ParticleTimelineChannel.restore(_data, cmd["particle_snapshot"])
	elif cmd.has("script_snapshot"):
		_data.script_ops = cmd["script_snapshot"]
	elif cmd.has("curve_assign_snapshot"):
		# Unwind a shape pick: put the array back (dropping any minted curve), re-point the
		# use site, and restore the samples the pick overwrote. Exact — the verb only ever
		# appended to the array and wrote ONE curve's samples.
		var snap: Dictionary = cmd["curve_assign_snapshot"]
		_data.curves = snap["curves"]
		CurveExplode.set_site_index(_data, int(snap["emitter_index"]), str(snap["slot"]),
			str(snap["kind"]), int(snap["index"]))
		var i: int = int(snap["index"])
		if i >= 0 and i < _data.curves.size() and not (snap["samples"] as Array).is_empty():
			_data.curves[i].samples = snap["samples"]
	elif cmd.has("texture_snapshot"):
		# #280 / ADR-0199 dec. 5: a 33 KB sheet has no meaningful before/after
		# scalar, so the swapped-out texture + authored bytes are restored
		# wholesale — byte-exact, the verb never mutated them.
		TextureChannel.restore(_data, cmd["texture_snapshot"])
	elif cmd.has("compound"):
		# REVERSE ORDER, and each member unwound by its OWN kind — a compound can now mix a
		# scalar replay with a structural snapshot (see `apply_compound`), so this cannot
		# assume `before_raw`.
		var members: Array = cmd["compound"]
		for i in range(members.size() - 1, -1, -1):
			undo_member(members[i])
	else:
		_dispatch(cmd["field_ref"], cmd["before_raw"])
	return true


## Unwind ONE compound member. A member is either a structural snapshot (the same shapes
## `_capture_structural` produces, restored by the branches in `undo` above) or a scalar
## `{field_ref, before_raw}` replayed through the dispatch path. Split out so a compound and
## a lone edit unwind a `curve_assign` by exactly the same code — two restores of a minted
## curve is precisely the kind of second copy that drifts.
func undo_member(member: Dictionary) -> void:
	if member.has("curve_assign_snapshot"):
		var snap: Dictionary = member["curve_assign_snapshot"]
		_data.curves = snap["curves"]
		CurveExplode.set_site_index(_data, int(snap["emitter_index"]), str(snap["slot"]),
			str(snap["kind"]), int(snap["index"]))
		var i: int = int(snap["index"])
		if i >= 0 and i < _data.curves.size() and not (snap["samples"] as Array).is_empty():
			_data.curves[i].samples = snap["samples"]
	elif member.has("field_ref") and member.has("before_raw"):
		_dispatch(member["field_ref"], member["before_raw"])


## The shared mutation path: route by channel to the per-channel raw↔value encoder.
## Both forward edits and undo replays go through here — only recording differs.
func _dispatch(field_ref: Dictionary, new_raw) -> Dictionary:
	match field_ref.get("channel", ""):
		"screen":
			return ScreenChannel.apply_raw(_data, field_ref, new_raw)
		"camera":
			return CameraChannel.apply_raw(_data, field_ref, new_raw)
		"palette":
			return PaletteChannel.apply_raw(_data, field_ref, new_raw)
		"sound":
			return SoundChannel.apply_raw(_data, field_ref, new_raw)
		"sound_container":
			return SoundContainerChannel.apply_raw(_data, field_ref, new_raw)
		"sound_def":
			return SoundDefChannel.apply_raw(_data, field_ref, new_raw)
		"emitter":
			return EmitterChannel.apply_raw(_data, field_ref, new_raw)
		"particle":
			return ParticleTimelineChannel.apply_raw(_data, field_ref, new_raw)
		"timeline_header":
			return TimelineHeaderChannel.apply_raw(_data, field_ref, new_raw)
		"effect_flags":
			return EffectFlagsChannel.apply_raw(_data, field_ref, new_raw)
		"script_pattern":
			return EffectScriptChannel.apply_raw(_data, field_ref, new_raw)
		"time_scale":
			return TimeScaleChannel.apply_raw(_data, field_ref, new_raw)
		"curve":
			return CurveChannel.apply_raw(_data, field_ref, new_raw)
		"curve_assign":
			return CurveChannel.assign_shape(_data, field_ref, new_raw)
		"frameset":
			return FramesetChannel.apply_raw(_data, field_ref, new_raw)
		"sequence":
			return SequenceChannel.apply_raw(_data, field_ref, new_raw)
		_:
			push_error("EffectEditSession: no encoder for channel '%s'" % field_ref.get("channel", ""))
			return {}


## Route a structural verb (insert / delete, plus FEDS's un-rest) to the per-channel encoder. Camera (ADR-0086),
## sound (the trigger-event verbs), palette and screen (ADR-0087) and particle (ADR-0089)
## carry lane-editing verbs; the rest stay lane-atomic.
func _dispatch_structural(field_ref: Dictionary, verb: String) -> Dictionary:
	if verb in ["unrest", "paint", "drag", "outro"] and field_ref.get("channel", "") != "sound_def":
		# Both are FEDS TIME verbs: they need a lane whose deletes leave a rest behind
		# (ADR-0085 2026-08-19 / 19b). No other channel tiles its time, so no other
		# channel has silence to sound or to paint into.
		push_error("EffectEditSession: no %s verb for channel '%s'"
			% [verb, field_ref.get("channel", "")])
		return {}
	match field_ref.get("channel", ""):
		"camera":
			return CameraChannel.insert_event(_data, field_ref) if verb == "insert" \
				else CameraChannel.delete_event(_data, field_ref)
		"sound":
			return SoundChannel.insert_event(_data, field_ref) if verb == "insert" \
				else SoundChannel.delete_event(_data, field_ref)
		"palette":
			return PaletteChannel.insert_event(_data, field_ref) if verb == "insert" \
				else PaletteChannel.delete_event(_data, field_ref)
		"screen":
			return ScreenChannel.insert_event(_data, field_ref) if verb == "insert" \
				else ScreenChannel.delete_event(_data, field_ref)
		"particle":
			return ParticleTimelineChannel.insert_event(_data, field_ref) if verb == "insert" \
				else ParticleTimelineChannel.delete_event(_data, field_ref)
		"sound_def":
			match verb:
				"insert":
					return SoundDefChannel.insert_event(_data, field_ref)
				"unrest":
					return SoundDefChannel.unrest_event(_data, field_ref)
				"paint":
					return SoundDefChannel.paint_event(_data, field_ref)
				"drag":
					return SoundDefChannel.drag_event(_data, field_ref)
				"outro":
					return SoundDefChannel.set_outro(_data, field_ref)
				"delete":
					return SoundDefChannel.delete_event(_data, field_ref)
				_:
					# Named, for the same reason the host's match is: an unhandled verb used to
					# become a delete at an address built for something else.
					push_error("EffectEditSession: no sound_def verb '%s'" % verb)
					return {}
		_:
			push_error("EffectEditSession: no %s verb for channel '%s'"
				% [verb, field_ref.get("channel", "")])
			return {}


## The live camera phase table for `phase`, or null. The pre-edit snapshot for undo.
func _camera_table(phase: String):
	if _data == null or _data.camera == null:
		return null
	return _data.camera.get_table(phase)


## The live sound channel dict at `data.sound[phase][ci]`, or null. The pre-edit
## snapshot for the sound structural verbs' undo.
func _sound_channel(phase: String, ci: int):
	if _data == null or not (_data.sound is Dictionary):
		return null
	var channels = _data.sound.get(phase, null)
	if not (channels is Array) or ci < 0 or ci >= channels.size():
		return null
	return channels[ci]
