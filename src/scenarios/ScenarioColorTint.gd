class_name ScenarioColorTint
extends RefCounted
## Per-unit "Color Unit" ({0x32}) palette tint — the door-exit fade and any
## per-unit palette-tint ramp in the event script. Pure model (no scene deps),
## unit-tested against a live PSX capture; ScenarioVM owns one per tinted unit.
##
## FFT decode (research/working_documents/UNIT_FADE_COLOR_UNIT_OPCODE.md):
## `DAT_800e4ea4` is the unit's live 16-colour CLUT (BGR555). The tint engine
## (`FUN_8008f710` @ 0x8008F710 setup + `FUN_800912a4` @ 0x800912A4 per-frame
## ramp) rewrites every CLUT entry each frame as `entry = f(mode, base, delta)`,
## clamped to 5-bit, DMA'd to VRAM (`FUN_80092f98` @ 0x80092F98) and consumed by
## the GPU as the sprite's palette — i.e. the tint is a modification of the
## sprite's palette colours, NOT a Gouraud/primitive colour.
##
## Key observation that makes this cheap in Godot: for the whole 16-entry
## palette every mode (except the luma modes 2/3/6/7) is the SAME per-channel
## affine map applied uniformly to each entry:
##     tinted_entry = base_entry * scale + bias
## Because our unit shader already samples the base palette colour into ALBEDO,
## we only need to feed it `scale` (mul) and `bias` (add) — no CLUT rewrite.
##
## Blend-mode table (`Color` param → transform of the current (scale,bias) and
## the signed 5-bit RGB `delta`), from FUN_8008f710's switch:
##   0  current + delta                → bias += delta
##   1  (current >> 1) + delta         → scale *= 0.5 ; bias = bias*0.5 + delta
##   4,9 palette + delta               → scale = 1    ; bias = delta
##   5  (palette >> 1) + delta         → scale = 0.5  ; bias = delta
##   8  palette (absolute, no delta)   → scale = 1    ; bias = 0
##   10 reset                          → scale = 1    ; bias = 0
##   2,3,6,7 luma (2R+3G+B)/{6,12}     → NOT uniform-affine; approximated as
##                                       mode 0 (a warn is logged by the caller)
##
## Ramp timing (FUN_800912a4, precomputed DDA tables in BATTLE.BIN): a change
## with Time==0 snaps instantly; 1..3 runs the FAST table = a fixed 8-frame
## linear ramp that lands exactly on target; Time>=4 runs the SLOW table = 32
## steps throttled every (Time>>2) frames (≈ 32*(Time>>2) frames). Each CLUT
## entry ramps linearly in 5-bit space, so the uniform (scale,bias) also ramps
## linearly — reproduced here as a lerp over the frame count.

## Current affine palette map: tinted = base*scale + bias (normalized [0,1]).
## Used by the per-channel modes (0/1/4/5/8/9/10). The luma modes (2/3/6/7) mix
## channels and cannot be an affine map, so they carry `luma_*` below instead and
## the shader takes a separate branch; affine stays identity for them.

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const ColorRecipe = ExMateriaSchema.ColorRecipe

var scale: Vector3 = Vector3.ONE
var bias: Vector3 = Vector3.ZERO

## Luma spec for Color modes 2/3/6/7 (the sepia/brown wash). `luma_div == 0` means
## "not a luma tint — use the affine (scale,bias) path". Otherwise the entry is
## `clamp(floor((2R+3G+B)/luma_div) + luma_delta5, 0, 31)` per `luma_out5`:
##   7 → div 12 base   6 → div 6 base   3 → div 12 current   2 → div 6 current.
var luma_div: int = 0
var luma_from_base: bool = true
var luma_delta5: Vector3i = Vector3i.ZERO
## Cross-fade weight for the luma output: 1.0 = full luma (sepia) output, 0.0 = the
## affine/base colour underneath. Only meaningful while `luma_div > 0`; the shader
## reads `mix(base_affine, luma_out, luma_mix)`. A mode-8 restore from a luma state
## (scn8 PC47/48) keeps the luma spec alive and ramps this 1 -> 0 so the sepia
## dissolves back to base instead of snapping — then collapses to luma_div == 0.
var luma_mix: float = 1.0

# Active ramp toward (_to_scale,_to_bias). _ramp_frames counts DOWN to 0.
var _ramp_frames: int = 0
var _ramp_total: int = 0
var _from_scale: Vector3 = Vector3.ONE
var _from_bias: Vector3 = Vector3.ZERO
var _to_scale: Vector3 = Vector3.ONE
var _to_bias: Vector3 = Vector3.ZERO
# Luma-delta ramp endpoints (Color 2/3/6/7 with Time>0). The div/mode snap on arm;
# only the signed 5-bit delta lerps — a fixed-div luma's per-entry DDA reduces to
# lerping the delta (COLOR_TINT_LUMA_MODE_SEPIA.md §2.3).
var _from_delta5: Vector3i = Vector3i.ZERO
var _to_delta5: Vector3i = Vector3i.ZERO
# Luma cross-fade ramp endpoints (the mode-8 restore-from-luma case). luma_mix walks
# _from_mix -> _to_mix; _to_luma_div is the div to LAND on (0 to collapse the luma
# branch to the affine base when the fade completes). During a same-mode delta ramp
# both mix endpoints are 1.0 and _to_luma_div == luma_div, so this path is inert.
var _from_mix: float = 1.0
var _to_mix: float = 1.0
var _to_luma_div: int = 0

## FFT fast-table ramp length (Time 1..3 → fixed 8 frames regardless of Time).
## Single source: ColorRecipe (the extracted byte-exact core the shipped stack uses).
const RAMP_FAST_FRAMES := ColorRecipe.RAMP_FAST_FRAMES

## Poison's green sprite recolor, ROM-DERIVED (issue #154 follow-up, doc §12.5).
## The {92} SS=2 apply schedules a sprite/tile rebuild that recolors the unit's VRAM
## CLUT IN PLACE via the shared status-recolor dispatch `FUN_800927bc` (selector
## @~0x80082180, staging strip 0x800E54A4, writer store 0x80092CA0 — the same
## palette-content machinery as prayer darkening). A live BP on the writer's
## registers (op92 rig, scenario 6 {92} SS=2) pins the exact per-channel transform:
##
##     out_ch = base_ch / 2 + offset_ch,   offset (R,G,B) = (0, 8, 0)  [5-bit BGR555]
##
## i.e. HALVE every channel (scale 0.5) then add green 8/31. It is a COMPUTED shift,
## NOT a selected SPR palette row: the green CLUT overwrites the base at the SAME VRAM
## address and each of the 45 non-transparent entries is a clean function of its base
## (confirmed err-0 vs the live poisoned CLUT at VRAM Y=483 — the poison offset triple
## t7/t6/t5 = 0/8/0 read straight from the dispatch's stack args).
##
## SOURCE (also dynamically pinned): NOT the {32}/{33} tint engine
## (`color_tint_blend_apply @ 0x8008F710` fired 0× across the SS=2 window) and NOT an
## inflict-effect E###.BIN keyframe (a direct opcode poke with no ability still greens).
##
## Reproduce: research/working_documents/op92_status_probe/probe_poison_clut_delta.py.
## This supersedes the earlier additive-only framebuffer-fit placeholder (-0.22,0,-0.18).
const POISON_SCALE := Vector3(0.5, 0.5, 0.5)
const POISON_GREEN_BIAS := Vector3(0.0, 8.0 / 31.0, 0.0)  # (0, 0.258, 0) normalized


## Frame count a given `Time` byte ramps over. Delegates to the ColorRecipe core so
## the DDA table is defined once (see RAMP_FAST_FRAMES).
static func ramp_frames_for_time(time: int) -> int:
	return ColorRecipe.ramp_frames_for_time(time)


## Sign-extend a param byte (Red/Green/Blue are signed bytes in the applier).
## Delegates to the ColorRecipe core (single source; the shipped stack uses it too).
static func _sb(b: int) -> int:
	return ColorRecipe._sb(b)


## Byte-exact LUMA transform for one 5-bit CLUT entry — the pure integer core of
## Color modes 2/3/6/7, mirrored by the shaders and MapComposer's map-palette bake.
## `L = floor((2R + 3G + B) / div)`, then `out_ch = clamp(L + delta_ch, 0, 31)`; `div`
## is 6 (modes 2/6) or 12 (modes 3/7). Verified byte-exact (227/227) vs the live
## scenario-8 field CLUT — COLOR_TINT_LUMA_MODE_SEPIA.md §3.4. Delegates to ColorRecipe
## so the sepia core lives in exactly one place (the copy the shipped color stack folds).
static func luma_out5(base5: Vector3i, div: int, delta5: Vector3i) -> Vector3i:
	return ColorRecipe.luma_out5(base5, div, delta5)


## Compute the (scale,bias) TARGET for a Color Unit op without mutating state.
## `r,g,b` are the raw (possibly signed) RGB param bytes. Returns
## [target_scale: Vector3, target_bias: Vector3, luma_unsupported: bool].
func _target_for(mode: int, r: int, g: int, b: int) -> Array:
	# 5-bit signed delta normalized to [0,1] channel space (31 == full).
	var delta := Vector3(_sb(r), _sb(g), _sb(b)) / 31.0
	var ts := scale
	var tb := bias
	var luma := false
	match mode:
		0:
			tb = bias + delta
		1:
			ts = scale * 0.5
			tb = bias * 0.5 + delta
		4, 9:
			ts = Vector3.ONE
			tb = delta
		5:
			ts = Vector3.ONE * 0.5
			tb = delta
		8:
			ts = Vector3.ONE
			tb = Vector3.ZERO
		10:
			ts = Vector3.ONE
			tb = Vector3.ZERO
		2, 3, 6, 7:
			# Luma modes mix channels — not an affine map. The affine stays
			# identity; the real transform is carried in the luma_* spec (set by
			# apply) and taken by the shader / luma_out5. Flag it for the caller.
			ts = Vector3.ONE
			tb = Vector3.ZERO
			luma = true
	return [ts, tb, luma]


## The (div, from_base) luma spec for a Color mode, or (0, _) if the mode is a
## per-channel affine mode. 6/7 read the base palette (absolute/idempotent); 2/3
## read the current tinted colour. See luma_out5.
static func _luma_spec_for(mode: int) -> Array:
	match mode:
		7:
			return [12, true]
		6:
			return [6, true]
		3:
			return [12, false]
		2:
			return [6, false]
		_:
			return [0, true]


## Apply a Color Unit op. `time` is the ramp length in frames (0 == snap).
## Returns true if the op used an unsupported (luma) mode (for caller logging).
func apply(mode: int, r: int, g: int, b: int, time: int) -> bool:
	var tgt := _target_for(mode, r, g, b)
	var ts: Vector3 = tgt[0]
	var tb: Vector3 = tgt[1]
	var luma: bool = tgt[2]
	# Latch the luma spec (div 0 = affine path). The mode/div snap immediately; the
	# signed 5-bit delta snaps (Time=0) or ramps (Time>0) from its current value.
	var spec := _luma_spec_for(mode)
	var new_div: int = spec[0]
	var new_delta5 := Vector3i(_sb(r), _sb(g), _sb(b)) if new_div > 0 else Vector3i.ZERO
	var old_div := luma_div
	var old_delta5 := luma_delta5
	# A ramped restore OUT of a luma wash to an affine base (scn8 PC47/48: mode 8
	# Time>0 while a sepia is active). The PSX DDA walks each entry from its current
	# sepia value back to base; we mirror that by KEEPING the old luma spec alive and
	# cross-fading luma_mix 1 -> 0, collapsing to the affine base when it lands.
	var luma_fade_out := time > 0 and new_div == 0 and old_div > 0
	if luma_fade_out:
		# Keep luma_div / luma_from_base / luma_delta5 at their current sepia values;
		# arm the affine ramp toward the mode's base and the mix ramp toward 0.
		_from_scale = scale
		_from_bias = bias
		_to_scale = ts
		_to_bias = tb
		_from_delta5 = old_delta5
		_to_delta5 = old_delta5  # held (no-op lerp — the sepia is what we fade FROM)
		_from_mix = luma_mix
		_to_mix = 0.0
		_to_luma_div = 0  # collapse to the affine base once the fade completes
		_ramp_total = ramp_frames_for_time(time)
		_ramp_frames = _ramp_total
		return luma
	luma_div = new_div
	luma_from_base = spec[1]
	if time <= 0:
		# Snap.
		scale = ts
		bias = tb
		luma_delta5 = new_delta5
		luma_mix = 1.0
		_to_delta5 = new_delta5
		_to_mix = 1.0
		_to_luma_div = new_div
		_ramp_frames = 0
		_ramp_total = 0
	else:
		_from_scale = scale
		_from_bias = bias
		_to_scale = ts
		_to_bias = tb
		_from_delta5 = old_delta5 if new_div > 0 else Vector3i.ZERO
		_to_delta5 = new_delta5
		luma_delta5 = _from_delta5  # hold at start; tick() lerps toward target
		_from_mix = 1.0
		_to_mix = 1.0
		luma_mix = 1.0
		_to_luma_div = new_div
		_ramp_total = ramp_frames_for_time(time)
		_ramp_frames = _ramp_total
	return luma


## Advance one 60 Hz tick. Returns true while a ramp is in flight (i.e. the
## caller should re-push scale/bias to the shader this frame).
func tick() -> bool:
	if _ramp_frames <= 0:
		return false
	_ramp_frames -= 1
	if _ramp_frames <= 0:
		# Final frame lands exactly on target (the DDA row sums to the delta).
		scale = _to_scale
		bias = _to_bias
		luma_delta5 = _to_delta5
		luma_mix = _to_mix
		luma_div = _to_luma_div  # collapse the luma branch when a fade-out completes
		return true
	var done := 1.0 - float(_ramp_frames) / float(_ramp_total)
	scale = _from_scale.lerp(_to_scale, done)
	bias = _from_bias.lerp(_to_bias, done)
	luma_mix = lerp(_from_mix, _to_mix, done)
	if luma_div > 0:
		luma_delta5 = Vector3i(
			roundi(lerp(float(_from_delta5.x), float(_to_delta5.x), done)),
			roundi(lerp(float(_from_delta5.y), float(_to_delta5.y), done)),
			roundi(lerp(float(_from_delta5.z), float(_to_delta5.z), done)))
	return true


## Snap an in-flight ramp straight to its resolved end-state — identical to letting
## `tick()` run to its final frame, without spending the frames. The `{66}` Commit
## Palette bakes the SETTLED field tint into the base: on PSX the commit fires only
## AFTER the fade's `{E5}`/wait has let the DDA finish, so the committed value is
## always the ramp TARGET, never a mid-fade frame. A fast-forward (path walk) — or
## any scenario whose colour ramp outlasts its pre-commit wait — can reach the commit
## with the ramp still in flight; resolving here makes the commit faithful and
## timing-independent (no-op when nothing is ramping).
func resolve() -> void:
	if _ramp_frames <= 0:
		return
	scale = _to_scale
	bias = _to_bias
	luma_delta5 = _to_delta5
	luma_mix = _to_mix
	luma_div = _to_luma_div
	_ramp_frames = 0
	_ramp_total = 0


## Snap to a fixed affine (scale, bias), no ramp — a static, HELD tint. Used for
## status recolors the PSX bakes once and holds in VRAM (e.g. poison's additive
## green shift), as opposed to the {32} Color Unit ramp. The caller pushes
## `scale`/`bias` to the shader once; it holds every frame with no `tick()`.
func set_static(s: Vector3, b: Vector3) -> void:
	scale = s
	bias = b
	_ramp_frames = 0
	_ramp_total = 0


## True while a ramp is still in flight (frames remain). Pure query — unlike
## tick() it does not advance the ramp. The dead-unit fade sequencer
## ({43} Call Function 4, SCENARIO6_DEAD_UNIT_FADE.md) polls this to fire pass 2
## the moment pass 1 lands (mirroring FUN_800870ac's `+0x13e` 1->2 state advance
## when the fast ramp completes).
func is_ramping() -> bool:
	return _ramp_frames > 0


## True when the tint is neutral (identity) and idle — safe to drop. A luma tint
## is never identity (its affine is identity but it still remaps every entry), so
## luma_div > 0 keeps it alive.
func is_identity() -> bool:
	return _ramp_frames <= 0 \
		and luma_div == 0 \
		and scale.is_equal_approx(Vector3.ONE) \
		and bias.is_equal_approx(Vector3.ZERO)
