class_name WorldMapCursor
extends RefCounted
## Where the hand cursor is, and which node it is over.
##
## [b]The cursor is free-moving, not node-snapping[/b] (§21.2): tapping a direction
## moves it a few pixels and it clamps at the screen edge. It is not free of the node it
## is ON, though -- see "the snap" below, which is the click-into-place a player feels and
## which no amount of pixel-diffing a settled screenshot can see. The SELECTED node is not
## stored anywhere the cursor is — it is [i]derived[/i] from the cursor position by a
## hit test every frame, which is what [code]DAT_800D0BB4[/code] holds (§30.4). So this
## is screen state, not campaign state: it does not belong on [WorldMapProgress].
##
## Getting that backwards is what the scaffold did — it invented a cursor position from
## the selected node — and the cost was the cursor drawn four pixels low in every frame
## it rendered, invisible in a 73%-correct screenshot and a hard miss the moment the
## primitive list was diffed against the oracle.

## §27.4, `FUN_8008D060` at `0x8008D0A0`: a 21x21 rect hung 14 above and 6 below the
## node's projected point. The pin is drawn above its anchor and the box follows the art.
const HIT_X := 10
const HIT_UP := 14
const HIT_DOWN := 6

# ---------------------------------------------------------------- the dynamics
#
# All of this is `FUN_8006D194`, the cursor's per-vsync update, read start to finish.
# Every frame it does exactly four things, in this order:
#
#   0x8006D29C  jal 0x80068E70(&ramp_x, dir_x)   accelerate, per axis
#   0x8006D2F0  jal 0x80068E70(&ramp_y, dir_y)
#   0x8006D380  jal 0x8008D194(cx+vx, cy+vy, &dx, &dy)   the SNAP, on the PROPOSED point
#   0x8006D39C  vx += dx ;  vy += dy
#   0x8006D558  cursor.x += vx ;  cursor.y += vy
#
# WARNING **Section 27.6's cursor dynamics are RIGHT, and this port's first "correction"
# of them was wrong.** Its header says *"a held direction takes 8 frames to start moving"*
# and *"a 2-frame tap moves the cursor ZERO pixels"*; a previous round read
# `round10_travel_trace.csv`, saw the cursor move on frame 1 of the press it had
# identified, and threw the prose out. Both statements are true -- of a cursor **sitting
# on a node**, which is where it always starts, because the snap below eats the first five
# frames of the ramp exactly. The trace's frame 1 was mis-anchored: back the press up five
# vsyncs and the model below reproduces all 17 frames of it, and the three other gestures
# in the file, exactly and to the pixel.
#
# ---------------------------------------------------------------------------- the ramp
#
# `FUN_80068E70(struct, dir)` is a fixed-point accelerator. The struct at `0x8009EF6C`
# (x) and `0x8009F184` (y) is five words:
#
#     +0x00  acc      8.8 signed accumulator, THE state -- it carries the sign, so the
#                     direction is not stored separately and a reversal runs through zero
#     +0x04  max      cap on |acc|
#     +0x08  accel    added per vsync while a direction is held
#     +0x0C  decel    taken off per vsync while nothing is
#     +0x10  vel      acc >> 8 -- the px/vsync the caller reads back
#
# and the screen setup writes the four constants literally, `ori v0,zero,0x400` /
# `ori v0,zero,0x80`:
#
#     0x8006C6C0  x.max   = 0x400      0x8006C6B8  y.max   = 0x400
#     0x8006C704  x.accel = 0x80       0x8006C6FC  y.accel = 0x80
#     0x8006C6F4  x.decel = 0x80       0x8006C6EC  y.decel = 0x80
#
# **This is why an earlier round concluded the ramp was not in WLDCORE.** It searched for
# writers of the VELOCITY word, `0x8009EF7C`, found three, and all three store zero -- but
# the accelerator writes it as `sw v0,0x10(a0)` through the struct pointer, which is the
# indexed store `find_refs.py` cannot see. Those three zero-stores are resets. The curve is
# half a pixel per vsync of acceleration, capped at four, and it is a ROM constant, not a
# fit to a recording.
#
# ---------------------------------------------------------------------------- the snap
#
# `FUN_8008D194(cx, cy, &dx, &dy)` at `0x8008D194`, called with the PROPOSED position
# (`cursor + vel`), never the current one:
#
#     hit = FUN_8008D060(cx, cy)          the same 21x21 test as `node_under`
#     if hit == 0: return 0               dx = dy = 0
#     nx, ny = node[hit-1].screen         0x800D3CD0 / 0x800D3CD4, stride 0x34 -- the very
#     ty = ny - 4                         table the hit test walks, and the SAME -4 as
#                                         `rest_at`, so the target IS the resting point
#     dx = clamp(nx - cx, -2, +2)         0x8008D214..58
#     dy = clamp(ty - cy, -2, +2)         0x8008D264..A8
#
# So while the cursor is inside a node's box the game adds up to +/-2 px per vsync of pull
# toward that node's resting point, landing exactly rather than overshooting. That is the
# "click into place", and it is why both savestates read the cursor at *exactly*
# `rest_at(node)` -- nothing else parks it there. `FUN_8006C350`, the hard placement, has
# one caller, the screen initialiser at `0x80067C8C`, so entry is the only other way.
#
# It does not contradict section 21.2's *"the cursor is free-moving, not node-snapping"*:
# the cursor still moves freely and never jumps between nodes. The pull only exists inside
# a box you are already in, and against the ramp's 4 px/vsync it loses -- net 2 px/vsync
# outward -- which is how the cursor leaves at all.
#
# The pull is skipped entirely when `*(0x800D3C8C) & 2` (`0x8006D318`). That bit is zeroed
# by the screen initialiser at `0x80067EF0` and toggled only inside `0x8006CD08`'s block,
# a separate mode that also stashes the camera pan -- unreachable from anything this port
# has, so the pull is unconditional here.

## Top speed in pixels per vsync -- `max >> 8`.
const MAX_SPEED := 4
## The accumulator's cap, `0x8009EF70` / `0x8009F188`.
const MAX_ACC := 0x400
## Added to |acc| per vsync while held, `0x8009EF74` / `0x8009F18C`.
const ACCEL := 0x80
## Taken off |acc| per vsync while released, `0x8009EF78` / `0x8009F190`.
const DECEL := 0x80
## The snap's per-vsync cap, the `-2` / `+2` immediates at `0x8008D22C` and `0x8008D254`.
const SNAP := 2

## Where the cursor is, in screen-centred coordinates.
var position: Vector2i = Vector2i.ZERO

## The 1-based node the last [method step] hit-tested under the PROPOSED position, 0 for
## none -- `sw v0,0xc(s1)` at `0x8006D388`. This is the selection the circle branch reads,
## and it is deliberately not recomputed from the settled position: the two disagree on
## the frame the cursor leaves a box, and the console uses this one.
var hit_node := 0

## The 8.8 accumulators, one per axis -- `0x8009EF6C` and `0x8009F184`. Signed: the sign
## IS the direction, which is why a reversal decelerates through zero instead of
## restarting, and why nothing here remembers which way you were going.
var _acc := Vector2i.ZERO


## Step one vsync with [param dir] held (each component -1, 0 or +1) and clamp inside
## [param bounds]. True when the position changed.
##
## Pass [param assets] and [param progress] to get the snap; without them this is the bare
## ramp, which is what the movement assertions measure.
func step(dir: Vector2i, bounds: Rect2i, assets: WorldMapAssets = null,
		progress: WorldMapProgress = null) -> bool:
	_acc = Vector2i(_accelerate(_acc.x, dir.x), _accelerate(_acc.y, dir.y))
	var vel := Vector2i(_velocity(_acc.x, dir.x), _velocity(_acc.y, dir.y))
	if assets != null and progress != null:
		var proposed := position + vel
		hit_node = node_under(assets, progress, proposed)
		if hit_node > 0:
			var n: Dictionary = assets.node(hit_node - 1)
			vel += pull_toward(
					rest_at(Vector2i(int(n["screen"][0]), int(n["screen"][1]))), proposed)
	var want := position + vel
	var got := Vector2i(
			clampi(want.x, bounds.position.x, bounds.end.x),
			clampi(want.y, bounds.position.y, bounds.end.y))
	# Stopped by the edge: drop that axis's momentum rather than let it pile up against
	# the wall and fling the cursor away the moment the player turns around.
	#
	# WARNING not the console's rule. `FUN_8006D194` hands the surplus to `FUN_8006AC08` /
	# `FUN_8006AC98`, which SCROLL the camera (`0x8009F2C0`, panning to -116..128 by
	# -64..80) and give back only what the pan could not absorb; the cursor's own hard
	# clamp is much wider, x -112..120 and y -104..104 at `0x8006D5D0`..`0x8006D69C`.
	# Section 21.1 says the view never scrolls and the port has no pan, so porting those
	# wide clamps without it would walk the cursor off the drawn map. Left as the caller's
	# `_bounds_for_cursor`, and the scroll is filed rather than guessed at.
	if got.x != want.x:
		_acc.x = 0
	if got.y != want.y:
		_acc.y = 0
	var was := position
	position = got
	return position != was


## One axis of `FUN_80068E70`: `0x80068E9C` (dir +1), `0x80068F44` (dir -1),
## `0x80068EEC` (released).
static func _accelerate(acc: int, dir: int) -> int:
	if dir > 0:
		if acc < MAX_ACC:
			acc += ACCEL
		return mini(acc, MAX_ACC)
	if dir < 0:
		if -acc < MAX_ACC:
			acc -= ACCEL
		return maxi(acc, -MAX_ACC)
	if acc > 0:
		return maxi(acc - DECEL, 0)
	return mini(acc + DECEL, 0)


## `sw v0,0x10(a0)`. Two spellings of the shift, and they are NOT the same: the dir >= 0
## path is a bare `sra v0,v0,8` (`0x80068EE8`), the dir < 0 path negates around it
## (`0x80068F90`..`98`). On a whole accumulator they agree; mid-reversal, where acc's sign
## opposes the held direction, `sra` floors and the other truncates, so acc = +0x380 reads
## 4 px/vsync while LEFT is held and 3 while nothing is. Faithful, not tidied.
static func _velocity(acc: int, dir: int) -> int:
	if dir < 0:
		return -((-acc) >> 8)
	if dir > 0:
		return acc >> 8
	return acc >> 8 if acc > 0 else -((-acc) >> 8)


## `FUN_8008D194`'s two output words: the per-vsync pull from [param at] toward
## [param target], each axis capped at [constant SNAP] and never overshooting.
static func pull_toward(target: Vector2i, at: Vector2i) -> Vector2i:
	return Vector2i(
			clampi(target.x - at.x, -SNAP, SNAP),
			clampi(target.y - at.y, -SNAP, SNAP))


## Park the cursor with no residual motion — entering the screen, or a warp.
func place(at: Vector2i) -> void:
	position = at
	_acc = Vector2i.ZERO
	hit_node = 0


## Re-run the hit test where the cursor currently stands and publish it as
## [member hit_node], without stepping. The console's update writes that word every vsync
## whether or not anything moved, so a screen that has placed the cursor and not yet
## ticked still has a live selection -- and circle on the frame the screen opens has to
## work.
func resolve(assets: WorldMapAssets, p: WorldMapProgress) -> int:
	hit_node = node_under(assets, p, position)
	return hit_node


## Where the cursor sits when it is resting on the node at [param node_screen].
##
## [b]Read out of the ROM[/b], not fitted. `FUN_8006C350` places the resting cursor:
## [codeblock]
## 8006c398  sw v1,0x0(at)     cursor.x = *0x8009F27C          the node's projected x
## 8006c3b8  addiu v0,v0,-4    cursor.y = *0x8009F280 - 4      ... and its y, MINUS FOUR
## [/codeblock]
## It also happens to be the hit box's centre, `(HIT_DOWN - HIT_UP) / 2`, and both
## captures land on it — ss1 node 7 `(-4,0)` -> `(-4,-4)`, ss2 node 25 `(-46,-11)` ->
## `(-46,-15)`. Three agreeing sources, one of them the instruction itself.
static func rest_at(node_screen: Vector2i) -> Vector2i:
	return node_screen + Vector2i(0, (HIT_DOWN - HIT_UP) / 2)


## The 1-based node the cursor is over, 0 for none — §27.4's hit test.
##
## [codeblock]
## best = 0xFFFFFF; hit = 0;
## for i in 0..42:
##     if not known(i):                  continue
##     if node[i].flags & 0x18:          continue
##     if |cx - sx| > 10 or cy < sy-14 or cy > sy+6:  continue
##     if node[i].tier < best: hit = i + 1; best = node[i].tier
## [/codeblock]
##
## Two of those lines have no port. `flags & 0x10` is *the same bit* as node-known —
## §29's correction measured 43 nodes x 3 savestates with zero mismatches between the
## flag and bit `512+i` — so the known check covers it. `flags & 0x08` has no located
## source at all and reads clear in every capture; it is left unported rather than
## guessed, and the tier tie-break below is what would notice if it mattered.
static func node_under(assets: WorldMapAssets, p: WorldMapProgress,
		cursor: Vector2i) -> int:
	var hit := 0
	var best := 0xFFFFFF
	for i in range(WorldMapProgress.NODE_COUNT):
		if not p.is_node_known(i):
			continue
		var n: Dictionary = assets.node(i)
		var sx: int = int(n["screen"][0])
		var sy: int = int(n["screen"][1])
		if cursor.x < sx - HIT_X or cursor.x > sx + HIT_X:
			continue
		if cursor.y < sy - HIT_UP or cursor.y > sy + HIT_DOWN:
			continue
		var tier: int = int(n["tier"][0])
		if tier < best:
			hit = i + 1
			best = tier
	return hit
