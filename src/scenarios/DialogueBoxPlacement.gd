class_name DialogueBoxPlacement
extends RefCounted
## Pure, native-pixel port of the PSX FFT dialogue-box **placement model** — the
## `0x10 Display Message` box/tail/portrait/▼-arrow geometry, hand-authored per
## line by the event designer. NO nodes, NO camera, NO Godot units: this is the
## reverse-engineered integer math, isolated so it can be golden-tested against the
## live PSX captures. The scenario box pool feeds it a projected unit position +
## the authored operands and maps the returned native-px rect back into the
## camera's local space.
##
## Authoritative decode + every constant/address:
##   research/working_documents/scenario_1_captures/dialogue_box_triangle_aim_decode.md
##   §1 (order-of-ops), §1b (addresses), §2 (live golden table), §7 (portrait
##   side + ▼ arrow). Handler `FUN_801308c0 @ 0x801308C0`; compositor
##   `FUN_8014c18c @ 0x8014C18C`.
##
## The whole model is FRAME-AGNOSTIC in X: it operates in "the frame of `proj_x`".
## Tests pass `proj_x` in the PSX code/draw frame with the doc's literal clamp
## bounds `[0x88, 0x180]`; the runtime passes a screen-frame `proj_x` in native
## `[0,256]` px with screen-frame bounds. Only the ABSOLUTE clamp bounds move
## between frames — every `−w/2−4`, `+0xC`, `−8`, `w/2`, `0x18`, `0x10`, `0x30`
## term is a frame-independent delta and stays literal. See the module doc §"frame".

# --- Order-of-ops constants (native px; all from decode §1 / §1b) -------------
const BOX_LEFT_CENTRE_OFF := -4      # box_left = proj_x − w/2 − 4
const ALIGN1_LEFT_TWEAK := 0xC       # align 1 (box above): box_left += 0xC
const ALIGN2_LEFT_TWEAK := -8        # align 2 (box below): box_left −= 8
const ALIGN1_TOP_OFF := -0x28        # align 1: box_top = proj_y − h − 0x28
const ALIGN3_CENTRE_Y := 0x78        # align 3: box_top = 0x78 − h/2
const TAIL_BOX_OFF := -8             # tri_boxX = w/2 + local_b8 − 8
const TAIL_BOX_MARGIN := 0x10        # tri_boxX clamp [0x10, w − 0x10]
const LOCAL_B8_MARGIN := 0x18        # local_b8 clamp [0x18 − w/2, w/2 − 0x18]

# Default screen-frame clamp bounds (native 256x240). The PSX code frame uses
# [0x88, 0x180] in X / [0x16, 0xe4] in Y (see decode §1b); the runtime removes the
# ~132px draw-buffer X offset, leaving a symmetric [4, 252] band inside the 256px
# frame. Y carries no offset (proj_y is already screen-frame), so Y bounds are the
# literal doc values.
const DEFAULT_X_LO := 4
const DEFAULT_X_HI := 252
const DEFAULT_Y_LO := 0x16           # 22
const DEFAULT_Y_HI := 0xe4           # 228

# --- Portrait / ▼-arrow constants (decode §7) --------------------------------
const PORTRAIT_RIGHT_OFF := -0x30    # RIGHT dock: portrait_x = box_right − 0x30
const PORTRAIT_LEFT_OFF := 8         # LEFT dock:  portrait_x = box_left + 8
const ARROW_INSET_DEFAULT := 0x1e    # ▼ X inset from box_right
const ARROW_INSET_RIGHT := 0x3e      # …bumped when tail is on the RIGHT side
const ARROW_LOCAL_AC_RESET := 8      # local_ac ≥ 8 resets the RIGHT bump (rare class)
const ARROW_Y_BOTTOM_INSET := 0x18   # ▼ Y = box_top + h − 0x18 [−8][−8]
const ARROW_TAIL_NUDGE := 16         # msg[0x64]&0xf0 → ±16px tail nudge

# Dialog-byte / arrow-flag masks.
const ARROW_FLAG_NONE := 0x8         # (Dialog & 0xc) == 8 → no tail/arrow
const ARROW_FLAG_BUBBLE := 0x4       # (Dialog & 0xc) == 4 → thinking bubble


## Solve the full box/tail/portrait/arrow geometry for one Display Message.
##
## Inputs (all native px, all ints — the caller rounds the projected unit first):
##   proj_x, proj_y   — the speaker's projected ground point in the working frame.
##   box_w, box_h     — the box footprint in native px (already includes any
##                      portrait-region reservation; the caller supplies the box's
##                      own measured size so the tail/portrait track what's DRAWN).
##   dialog           — the Dialog byte: align `&3`, box-type `&0x70`,
##                      arrow-flags `&0xc`, chain `&0x80`.
##   arrow_byte       — msg[0x64] ("Open Type"): low nibble = open tween (ignored
##                      here), high nibble `&0xf0` gates the ±16px tail nudge/mirror.
##   x58, y5c, fine_x60 — the authored signed offsets (box-X, box-Y, tail fine-X).
##   local_ac         — portrait row − 1 (decode §1c); ≥8 resets the ▼ RIGHT bump.
##                      Default −1 = the common no-explicit-row case.
##   clamp bounds     — override for the working frame (defaults = screen frame).
##
## Returns a Dictionary — see the keys assembled at the bottom.
static func solve(
		proj_x: int, proj_y: int,
		box_w: int, box_h: int,
		dialog: int, arrow_byte: int,
		x58: int, y5c: int, fine_x60: int,
		local_ac: int = -1,
		x_lo: int = DEFAULT_X_LO, x_hi: int = DEFAULT_X_HI,
		y_lo: int = DEFAULT_Y_LO, y_hi: int = DEFAULT_Y_HI) -> Dictionary:
	var align := dialog & 0x3
	var arrow_flags := dialog & 0xc
	var half_w := box_w >> 1                   # w/2 (w ≥ 0 → floor)

	# local_b8 is the shove-accumulator: each edge-clamp of box_left folds the
	# amount the box was pushed (pre − post) into it, so the tail keeps aiming at
	# the unit's true projected column even when the box is shoved off it.
	var local_b8 := 0

	# --- box_left: centre on proj_x, align tweak, clamp, += X58, clamp ---------
	var box_left := proj_x - half_w + BOX_LEFT_CENTRE_OFF
	if align == 1:
		box_left += ALIGN1_LEFT_TWEAK
	elif align == 2:
		box_left += ALIGN2_LEFT_TWEAK
	var r1 := _clamp_shove(box_left, box_w, x_lo, x_hi, local_b8)
	box_left = r1[0]
	local_b8 = r1[1]
	box_left += x58
	var r2 := _clamp_shove(box_left, box_w, x_lo, x_hi, local_b8)
	box_left = r2[0]
	local_b8 = r2[1]

	# --- box_top: align, += Y5c, clamp [Y_LO, Y_HI − h] -----------------------
	var box_top: int
	if align == 1:
		box_top = proj_y - box_h + ALIGN1_TOP_OFF
	elif align == 3:
		box_top = ALIGN3_CENTRE_Y - (box_h >> 1)
	else:                                      # align 2 (and 0, undefined → treat as 2)
		box_top = proj_y
	box_top += y5c
	var top_hi := y_hi - box_h
	if top_hi < y_lo:
		top_hi = y_lo
	box_top = clampi(box_top, y_lo, top_hi)

	# --- local_b8: += authored fine-X, then optional arrow nudge, then clamp ---
	local_b8 += fine_x60
	# msg[0x64] & 0xf0 (arrow high nibble): a ±16px tail nudge, direction by align
	# (decode §1c / §3.2). Sign is unverified against a golden line (every captured
	# chapel/knight line has &0xf0 == 0); implemented best-effort and gated off for
	# the common case so it can't regress it.
	if (arrow_byte & 0xf0) != 0:
		local_b8 += (ARROW_TAIL_NUDGE if align == 2 else -ARROW_TAIL_NUDGE)
	var b8_margin := half_w - LOCAL_B8_MARGIN
	if b8_margin < 0:
		b8_margin = 0
	local_b8 = clampi(local_b8, -b8_margin, b8_margin)

	# --- tail (triangle) X: box-local and screen ------------------------------
	var tri_box_x := half_w + local_b8 + TAIL_BOX_OFF
	var tri_margin_hi := box_w - TAIL_BOX_MARGIN
	if tri_margin_hi < TAIL_BOX_MARGIN:
		tri_margin_hi = TAIL_BOX_MARGIN
	tri_box_x = clampi(tri_box_x, TAIL_BOX_MARGIN, tri_margin_hi)
	var tri_scr_x := clampi(box_left + local_b8 + half_w, x_lo, x_hi)

	# --- portrait side = sign(local_b8) (decode §7.1) -------------------------
	var box_right := box_left + box_w
	var side_right := local_b8 >= 0
	var portrait_x := (box_right + PORTRAIT_RIGHT_OFF) if side_right else (box_left + PORTRAIT_LEFT_OFF)
	var portrait_mirror := not side_right       # LEFT dock mirrors to face inward

	# --- ▼ page-turn arrow (decode §7.2), right/bottom-corner anchored ---------
	var arrow_x := box_right - _arrow_x_inset(local_ac, side_right)
	var arrow_y := box_top + box_h - ARROW_Y_BOTTOM_INSET
	if arrow_flags != ARROW_FLAG_NONE and align != 2:
		arrow_y -= 8
	if arrow_flags == ARROW_FLAG_BUBBLE:
		arrow_y -= 8

	return {
		"box_left": box_left,
		"box_top": box_top,
		"box_right": box_right,
		"box_w": box_w,
		"box_h": box_h,
		"align": align,
		"local_b8": local_b8,
		"tri_box_x": tri_box_x,
		"tri_scr_x": tri_scr_x,
		"portrait_side_right": side_right,
		"portrait_mirror": portrait_mirror,
		"portrait_x": portrait_x,
		"arrow_x": arrow_x,
		"arrow_y": arrow_y,
	}


## The ▼ arrow's X inset from `box_right` (decode §7.2): `0x3e` on the RIGHT side,
## else `0x1e`; a `local_ac ≥ 8` box class resets the RIGHT bump back to `0x1e`.
## Exposed static so the §7.4 golden table can pin it directly.
static func arrow_x_inset(local_ac: int, side_right: bool) -> int:
	return _arrow_x_inset(local_ac, side_right)


static func _arrow_x_inset(local_ac: int, side_right: bool) -> int:
	if local_ac >= ARROW_LOCAL_AC_RESET:
		return ARROW_INSET_DEFAULT
	return ARROW_INSET_RIGHT if side_right else ARROW_INSET_DEFAULT


# Clamp box_left into [lo, hi − w] and fold the shove (pre − post) into local_b8,
# so the tail compensates for the box being pushed off the unit's column. Returns
# [clamped_box_left, updated_local_b8].
static func _clamp_shove(box_left: int, box_w: int, lo: int, hi: int, local_b8: int) -> Array:
	var hi_bound := hi - box_w
	if hi_bound < lo:
		hi_bound = lo
	var post := clampi(box_left, lo, hi_bound)
	local_b8 += box_left - post
	return [post, local_b8]
