extends RefCounted
## The pure decode behind the SEQUENCE film-strip viewport: an animation's opcode
## stream turned into what the strip and the player above it draw.
##
## THE MODEL (revised with the user 2026-08-20 — an ADR-0102 amendment). The strip is
## a ROW OF TIME POSITIONS. ONE CELL PER OPCODE still — every opcode, not only `FRAME` —
## but a cell now answers "what does the animation look like at THIS point on its clock",
## and it carries the point it stands for in `pos_tick`:
##
##   the FIRST cell    the animation at t=0            — its first frame
##   an interior cell  the END of that opcode's duration
##   the LAST cell     the animation at its end        — its last frame
##
## THE FENCEPOST IS WHY. N stretches of time have N+1 boundaries; the strip exposed only
## the interior ones, so there was no way to park on — or key at — the animation's start
## or its end. The two spare slots are exactly where those two boundaries go, and both
## already exist in the data: all 2,428 corpus animations open with a `SET_OFFSET` (the
## first `FRAME` is opcode 1 in every one of them) and 2,377 close with a `LOOP`.
##
## THIS REVERSES the decision locked on 2026-08-18 — "cell 0 draws an empty box with a
## crosshair, because a cell is a state readout and inventing a sprite there would make
## it lie." That rationale does not carry over, because the PURPOSE changed. A cell is no
## longer a readout of one opcode's state; it is a position on the animation's clock, and
## the picture at t=0 is not invented — it is what the game puts on screen at t=0. So
## every cell before the first `FRAME` ADOPTS that frame's whole state (frameset, depth
## mode AND offset), rather than borrowing a neighbour's sprite at its own offset.
##
## ONE EXPRESSION, NO SPECIAL CASES. `pos_tick` is `tick_start + ticks - 1` for a cell
## that occupies time and `maxi(0, tick_start - 1)` for one that does not. That single
## rule lands all three cases above by itself — including the 51 animations with no
## trailing `LOOP`, where the last `FRAME`'s end already IS the animation's end — it is
## monotone non-decreasing down the strip, and it keeps every `pos_tick` inside
## `[0, total_ticks - 1]`, so a park can never seek off the end of the sequence.
##
## WHAT DID NOT CHANGE: `tick_start`/`ticks` are still the DWELL, the per-opcode view of
## `ParticleAnimator._bake_animations`, and `total_ticks` still equals that bake's array
## length. `pos_tick` is a second reading of the same numbers, not a rival clock.
##
## The state is `(frameset, offset, depth_mode)` and every opcode transitions it:
##   SET_OFFSET   offset  = (x, y)        — the sprite is untouched, only moved
##   ADD_OFFSET   offset += (dx, dy)      — likewise
##   FRAME        frameset/depth_mode set; dwells `max(1, (duration + 1) >> 1)` ticks
##   LOOP         changes nothing; marks the wrap point
##
## Two things follow, and both are load-bearing rather than stylistic:
##
##   * A CELL MUST HONOUR ITS OFFSET. E190 anim 2 plays frameset 1 three times in a
##     row, and those three cells differ ONLY by offset — centre them and the strip
##     draws three identical pictures of a sprite that is visibly falling.
##   * EVERY CELL SHARES ONE COORDINATE BOX (`bounds`). A per-cell fit re-centres
##     each sprite, which cancels exactly the offset the previous point preserves.
##
## A cell with no sprite is now only possible for an animation holding no `FRAME` at
## all — none in the corpus, but E509/E510 prove the strip must stay navigable with
## nothing to draw, so the crosshair path stays.
##
## WHY NOT `ParticleAnimator._bake_animations`: that bakes one entry per displayed
## TICK for playback, collapsing the offset opcodes it consumes and losing the
## opcode indices the strip has to select on. This is the same arithmetic viewed
## per-opcode instead of per-tick — `tick_start`/`ticks` keep the two reconcilable,
## and `total_ticks` here equals that bake's array length.
##
## Pure statics throughout — the actual test seam
## (`tests/EffectStudioSequenceTimelineTest.gd`), callable with no live node. The
## expectations there came from an independent Python oracle that decodes
## `animations.json` without reading this file.
##
## No `class_name` (ADR-0004).


## One entry per opcode: the animation at the time position that opcode stands for.
## Keys —
##   `op_index`   which opcode this cell selects (the player parks on it; there is no
##                focused-opcode inspection target — see SequenceProjector)
##   `type`       the opcode's own type, so the cell can label itself
##   `frameset`   the frameset SHOWN, adopted from the first FRAME before one has run
##   `offset`     the accumulated Vector2i offset, adopted with it
##   `depth_mode` the depth mode shown, likewise
##   `duration`   the FRAME's stored duration, else -1
##   `ticks`      how long it DWELLS (0 for a non-FRAME opcode) — the bake's view
##   `tick_start` the tick this cell's dwell begins at
##   `pos_tick`   THE POSITION THIS CELL STANDS FOR — the end of its dwell, or the
##                boundary it sits on. Always inside `[0, total_ticks - 1]`, and what
##                a click parks the player at.
##   `cut_start`  the first tick of the cell's colour window (ADR-0103's "piece")
##   `cut_ticks`  how many ticks that window spans — `maxi(1, ticks)`, so a cell that
##                occupies no time is a STILL rather than a hole. `cut_start` and
##                `cut_ticks` are pinned to `pos_tick` by
##                `cut_start + cut_ticks - 1 == pos_tick`: a cell's position is the
##                LAST tick of its colour window, which is the whole model in one line.
##   `is_terminal`duration 0 — shows once, then the animation stops
##   `has_sprite` whether there is anything to draw at all
## `group_offset` shifts every FRAME opcode's stored index to its ABSOLUTE one. A
## FRAME's `frameset` is RELATIVE to the frameset GROUP the playing emitter selects
## via its `anim_param` — `ParticleAnimator.gd:120` resolves it as
## `opcode.frameset + particle.frameset_group_offset` — so the same sequence draws
## different sprites depending on who plays it. 18 of the 401 corpus effects have
## more than one group (17 have two, E040 has three); the rest are group 0, whose
## offset is always 0, which is why the default is the identity.
##
## It arrives as a plain int to keep this module PURE. Resolving an emitter's group
## to an offset is `EffectData.frameset_group_offset`'s job — the one derivation,
## whose docstring asks callers not to make a fifth copy of it — so the page
## resolves and passes the number down.
## Pure.
static func trace(anim: Dictionary, group_offset: int = 0) -> Array:
	var out: Array = []
	var frameset: int = -1
	var depth_mode: int = -1
	var offset := Vector2i.ZERO
	var tick: int = 0
	var opcodes: Array = anim.get("opcodes", [])
	for i in range(opcodes.size()):
		var op = opcodes[i]
		if not (op is Dictionary):
			continue
		var t: String = str(op.get("type", ""))
		var duration: int = -1
		var ticks: int = 0
		var terminal: bool = false
		match t:
			"SET_OFFSET":
				offset = Vector2i(int(op.get("x", 0)), int(op.get("y", 0)))
			"ADD_OFFSET":
				offset += Vector2i(int(op.get("dx", 0)), int(op.get("dy", 0)))
			"FRAME":
				# The offset lands HERE, not on the running `frameset`, so a cell
				# before the first FRAME keeps -1 through the walk rather than being
				# shifted into a real-looking index it does not hold. What it ends up
				# SHOWING is settled afterwards, by `_adopt_first_frame`.
				frameset = int(op.get("frameset", 0)) + group_offset
				depth_mode = int(op.get("depth_mode", 0))
				duration = int(op.get("duration", 1))
				# FFT decrements frame_timer by 2 per game frame, so a FRAME is on
				# screen for duration/2 — and duration 0 still shows ONCE before it
				# terminates, which is why the floor is 1 and not 0.
				#
				# The halving ROUNDS UP. `render_particle_sprite` @0x801AA1F8 seeds
				# frame_timer = duration and advances only when `timer -= 2` leaves a
				# sign-extended value < 1, so the entry survives ceil(duration/2)
				# render calls. Even durations are unaffected (21,032 of the corpus's
				# 21,043 FRAME opcodes); the 10 odd ones >= 3 were each a tick short.
				ticks = maxi(1, (duration + 1) >> 1)
				terminal = (duration == 0)
			"LOOP":
				pass
		# THE POSITION, one expression. A cell that occupies time stands for the END
		# of its dwell; one that does not stands for the boundary it sits on, which is
		# the tick just BEFORE the dwell it precedes. That lands the animation's start
		# on the leading SET_OFFSET (`maxi` floors -1 to 0) and its end on the trailing
		# LOOP, with no branch for either — and with no branch for the 51 animations
		# that have no trailing LOOP, whose last FRAME's end already IS the end.
		var pos: int = (tick + ticks - 1) if ticks > 0 else maxi(0, tick - 1)
		var cut_ticks: int = maxi(1, ticks)
		out.append({
			"op_index": i,
			"type": t,
			"frameset": frameset,
			"offset": offset,
			"depth_mode": depth_mode,
			"duration": duration,
			"ticks": ticks,
			"tick_start": tick,
			"pos_tick": pos,
			"cut_start": pos - cut_ticks + 1,
			"cut_ticks": cut_ticks,
			"is_terminal": terminal,
			"has_sprite": frameset >= 0,
		})
		tick += ticks
	_adopt_first_frame(out)
	return out


## Every cell BEFORE the first FRAME shows what the animation shows at t=0 — which is
## that first FRAME's whole state, offset included.
##
## The picture is not borrowed and not invented: those cells all stand for tick 0 (the
## `maxi(0, tick_start - 1)` above), and tick 0 is the first FRAME. Taking its OFFSET
## too is the part that needs saying — a leading `SET_OFFSET` followed by an
## `ADD_OFFSET` would otherwise draw the sprite at a position it is never at. No corpus
## animation is shaped that way (the first FRAME is opcode 1 in all 2,428), so this is
## correct-by-construction rather than observable, which is exactly why it is written
## down here instead of left implicit.
static func _adopt_first_frame(out: Array) -> void:
	var first: int = -1
	for i in range(out.size()):
		if bool(out[i].get("has_sprite", false)):
			first = i
			break
	# -1 is an animation with no FRAME at all: nothing to adopt, and the crosshair
	# stands in for the whole strip.
	if first <= 0:
		return
	var src: Dictionary = out[first]
	for i in range(first):
		out[i]["frameset"] = src["frameset"]
		out[i]["offset"] = src["offset"]
		out[i]["depth_mode"] = src["depth_mode"]
		out[i]["has_sprite"] = true


## How many ticks the whole sequence runs — equal to the length of
## `ParticleAnimator.baked_animations[i]` for the same animation. Pure.
static func total_ticks(tr: Array) -> int:
	var n: int = 0
	for e in tr:
		n += int(e.get("ticks", 0))
	return n


## The cell the playhead highlights while the player is at `tick`. Only FRAME cells
## occupy time, so an offset or LOOP cell is never addressed here; past the end
## returns -1 rather than clamping, so a finished player shows no highlight instead
## of a false one. Returns an INDEX INTO `tr`, which is also the opcode index.
##
## THIS IS THE DWELL QUESTION, NOT THE POSITION QUESTION, and deliberately so. It
## answers "which frame is on screen at this tick" — what the white playhead mark
## means — while `pos_tick` answers "which tick does this row stand for", which is what
## a click means. The two agree wherever a row occupies time, and where they do not,
## the yellow parked mark and the white playhead mark sit one row apart: parking on the
## trailing LOOP shows the last FRAME's row as the one actually rendering. That is the
## honest reading of both marks, not a mismatch to paper over. Pure.
static func op_at_tick(tr: Array, tick: int) -> int:
	if tick < 0:
		return -1
	for i in range(tr.size()):
		var ticks: int = int(tr[i].get("ticks", 0))
		if ticks <= 0:
			continue
		var start: int = int(tr[i].get("tick_start", 0))
		if tick >= start and tick < start + ticks:
			return i
	return -1


## The ONE coordinate box every cell draws through: the union of every step's quad
## extents, each taken at that step's own offset, in PSX units with +y DOWN (the
## stored vertex convention — the shader negates it at `VERTEX.y = -corner.y`).
##
## Sharing it is what makes an offset visible: fit each cell to its own sprite and
## three cells of a falling frameset re-centre into three identical pictures.
##
## An empty `Rect2i()` when nothing is drawable. That is a real corpus case, not a
## defensive branch: E509 and E510 reference up to 14 framesets with an EMPTY
## `frames.json`, and the strip must stay navigable with nothing to draw. Pure.
static func bounds(tr: Array, framesets: Array) -> Rect2i:
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	var any := false
	for e in tr:
		if not bool(e.get("has_sprite", false)):
			continue
		var fs_i: int = int(e.get("frameset", -1))
		if fs_i < 0 or fs_i >= framesets.size():
			continue
		var fs = framesets[fs_i]
		if not (fs is Dictionary):
			continue
		var offset: Vector2i = e.get("offset", Vector2i.ZERO)
		for frame in fs.get("frames", []):
			if not (frame is Dictionary):
				continue
			var bb: Rect2i = _quad_bbox(frame)
			if bb.size == Vector2i.ZERO:
				continue
			any = true
			lo.x = mini(lo.x, bb.position.x + offset.x)
			lo.y = mini(lo.y, bb.position.y + offset.y)
			hi.x = maxi(hi.x, bb.position.x + bb.size.x - 1 + offset.x)
			hi.y = maxi(hi.y, bb.position.y + bb.size.y - 1 + offset.y)
	if not any:
		return Rect2i()
	return Rect2i(lo, hi - lo + Vector2i.ONE)


## The floor and ceiling on a cell's width:height. MEASURED over the 2,420 corpus
## animations that have drawable bounds, not chosen: the median aspect is EXACTLY
## 1.0 and so are p25 and p75 — half of all animations are square — while 7.1% fall
## outside [0.2, 5.0] and the extreme is 167:1. Clamping there keeps 92.9% of
## sequences drawn at their true proportions and letterboxes only the genuine beams,
## where honouring 167:1 would render a sprite one pixel wide.
const ASPECT_MIN := 0.2
const ASPECT_MAX := 5.0


## A cell's width:height, from the shared box. Square when there is nothing to go on.
## Pure.
static func cell_aspect(box: Rect2i) -> float:
	if box.size.x <= 0 or box.size.y <= 0:
		return 1.0
	return clampf(float(box.size.x) / float(box.size.y), ASPECT_MIN, ASPECT_MAX)


## One composited sprite: every frame of `frameset`, each as a quad of four corners
## in PSX units (offset applied) plus the four texel-space UVs that fill it.
##
## A FRAME opcode selects a FRAMESET, and `EffectParticleRenderer` loops every frame
## of it into its own quad — so one strip cell is one frameset drawn WHOLE. Reading
## this as one-cell-per-frame produces a strip of sprite LAYERS rather than animation
## frames, which looks plausible and is wrong.
##
## Corner order is `tl, tr, br, bl` — a single winding, so the result feeds
## `draw_polygon` directly. The UVs carry the mirror: a negative stored width means
## the stored `x` is the block's LAST column and sampling walks left, so the quad
## itself is never flipped, only its UV corners swap ends (ADR-0099's normalised
## block, in its raw signed form here because sampling wants the direction). UVs are
## texel CENTRES (`+0.5`, extent `w - sign(w)`), the mapping
## `EffectParticleRenderer._write_instance` uses to avoid seams on mirrored frames.
##
## Texel space, not normalised — the caller divides by its own texture size. Pure.
static func sprite_quads(frameset, offset: Vector2i) -> Array:
	var out: Array = []
	if not (frameset is Dictionary):
		return out
	var ox := float(offset.x)
	var oy := float(offset.y)
	for frame in frameset.get("frames", []):
		if not (frame is Dictionary):
			continue
		var v: Dictionary = frame.get("vertices", {})
		var tl: Array = v.get("top_left", [])
		var tr: Array = v.get("top_right", [])
		var bl: Array = v.get("bottom_left", [])
		var br: Array = v.get("bottom_right", [])
		if tl.size() < 2 or tr.size() < 2 or bl.size() < 2 or br.size() < 2:
			continue
		var points := PackedVector2Array([
			Vector2(float(tl[0]) + ox, float(tl[1]) + oy),
			Vector2(float(tr[0]) + ox, float(tr[1]) + oy),
			Vector2(float(br[0]) + ox, float(br[1]) + oy),
			Vector2(float(bl[0]) + ox, float(bl[1]) + oy),
		])
		var uv: Dictionary = frame.get("uv", {})
		var ux := float(uv.get("x", 0)) + 0.5
		var uy := float(uv.get("y", 0)) + 0.5
		var uw := float(uv.get("width", 0))
		var uh := float(uv.get("height", 0))
		# `w - sign(w)`: the span from the first texel's centre to the last one's,
		# which is one texel shorter than the block and is what keeps a mirrored
		# frame from sampling a neighbouring column.
		var uw_c := uw - signf(uw)
		var uh_c := uh - signf(uh)
		var uvs := PackedVector2Array([
			Vector2(ux, uy),
			Vector2(ux + uw_c, uy),
			Vector2(ux + uw_c, uy + uh_c),
			Vector2(ux, uy + uh_c),
		])
		out.append({
			"points": points,
			"uvs": uvs,
			"semi_trans_on": bool(frame.get("semi_trans_on", true)),
			"semi_trans_mode": int(frame.get("semi_trans_mode", 1)),
		})
	return out


## The bounding box of a frame's four vertices, in PSX units. Empty when the frame
## has no usable vertex data.
static func _quad_bbox(frame: Dictionary) -> Rect2i:
	var v: Dictionary = frame.get("vertices", {})
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	var any := false
	for key in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		var pt: Array = v.get(key, [])
		if pt.size() < 2:
			continue
		any = true
		lo = Vector2i(mini(lo.x, int(pt[0])), mini(lo.y, int(pt[1])))
		hi = Vector2i(maxi(hi.x, int(pt[0])), maxi(hi.y, int(pt[1])))
	if not any:
		return Rect2i()
	return Rect2i(lo, hi - lo + Vector2i.ONE)
