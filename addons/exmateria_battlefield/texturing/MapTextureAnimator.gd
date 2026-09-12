extends RefCounted

## Renders FFT map "Texture Animation Instructions" — the asset behind
## event-script opcode {55} Use Field Object.
##
## On PSX, {55} Use Field Object ID=N plays texture-animation slot N from the
## map Mesh Resource (descriptor table 0x80121d7c, stride 0x14, indexed by ID).
## A slot is a VRAM-to-VRAM blit recipe: each frame it copies a source rectangle
## (first_frame + frame*size, advancing every `frame_duration` ticks) into a
## fixed "canvas" rectangle that the map polygons sample. {57} Wait Field Object
## barriers until the animation finishes. See
## `research/working_documents/scenario_1_captures/use_field_object_decode.md`.
##
## We reproduce this faithfully by cloning the imported indexed-color atlas into
## a mutable ImageTexture and blitting frames into the canvas region. The atlas
## is 256 wide; FFT's 4 texture pages (256x256 each) stack vertically, so a page
## offset is `page * 256` in Y only (matches the exporter's convert_uv:
## `atlas_v = (v + page*256) / 1024`). Slot index == Field Object ID.
##
## The slot table comes from the map manifest's `animations.texture_animations`
## (emitted index-stable by tools/fft_exporter/parsers/animation.py).
## Vault: [[Map Animation Systems]]

const ATLAS_WIDTH := 256
const PAGE_HEIGHT := 256       # each texture page is 256px tall; pages stack in Y
const TICKS_PER_SECOND := 60.0  # PSX field animation cadence

# Reverse-playback UV modes (parser emits the mode name with underscores
# stripped). Everything else plays forward.
const _REVERSE_MODES := {
	"ReverseOnceOnTrigger": true,
}

const PALETTE_ANIM_ROW_BASE := 16  # animation-frame palettes live in rows 16-31

var _slots: Array = []            # texture_animations from manifest (index == ID)
var _source_img: Image = null     # immutable original atlas (RGBA8)
var _work_img: Image = null       # live, mutated atlas
var _work_tex: ImageTexture = null  # GPU texture backing _work_img
# Palette-kind slots swap a base palette row for a cycling animation-frame row.
# The palette texture is 16x32 (base rows 0-15, animation rows 16-31); the map
# shader samples the base row by the polygon's palette_id, so a palette field
# object blits animation row (16 + start_index + frame) over base row
# `overridden_palette_id` in this mutable copy. Null when no palette texture was
# supplied (setup's 3rd arg) — palette slots then only register a {57} barrier.
var _pal_source_img: Image = null  # immutable original palette (16x32 RGBA8)
var _pal_work_img: Image = null    # live, mutated palette
var _pal_work_tex: ImageTexture = null  # GPU texture backing _pal_work_img
var _active: Dictionary = {}      # id -> active-animation record
var _ready := false


## Build the mutable working texture from the imported indexed atlas. Returns the
## ImageTexture the caller must swap into the map materials, or null on failure.
## Idempotent: returns the existing work texture if already set up.
func setup(slots: Array, indexed_texture: Texture2D, palette_texture: Texture2D = null) -> ImageTexture:
	if _ready:
		return _work_tex
	_slots = slots if slots != null else []
	if indexed_texture == null:
		push_warning("[MapTextureAnimator] no indexed texture; field animation disabled")
		return null
	var src := indexed_texture.get_image()
	if src == null:
		push_warning("[MapTextureAnimator] indexed texture has no retrievable Image")
		return null
	src = src.duplicate()
	if src.get_format() != Image.FORMAT_RGBA8:
		src.convert(Image.FORMAT_RGBA8)
	_source_img = src
	_work_img = src.duplicate()
	_work_tex = ImageTexture.create_from_image(_work_img)
	_setup_palette(palette_texture)
	_ready = true
	return _work_tex


## Build the mutable palette texture from the 16x32 palette atlas. Optional — only
## palette-kind field-object slots need it; UV slots ignore it entirely. Returns
## the ImageTexture the caller must swap into the map materials, or null if no
## palette texture was supplied.
func _setup_palette(palette_texture: Texture2D) -> ImageTexture:
	if palette_texture == null:
		return null
	# Only build the mutable palette (and let the caller repoint materials at it)
	# when a slot actually palette-animates. A UV-only door map must keep sampling
	# the shared palette so a later {33}/{66} field-tint commit stays visible.
	if not _has_palette_slot():
		return null
	var src := palette_texture.get_image()
	if src == null:
		push_warning("[MapTextureAnimator] palette texture has no retrievable Image")
		return null
	src = src.duplicate()
	if src.get_format() != Image.FORMAT_RGBA8:
		src.convert(Image.FORMAT_RGBA8)
	_pal_source_img = src
	_pal_work_img = src.duplicate()
	_pal_work_tex = ImageTexture.create_from_image(_pal_work_img)
	return _pal_work_tex


## True if any slot is a palette-kind field object (mode 0x0D). Gates whether the
## mutable palette texture is built at all.
func _has_palette_slot() -> bool:
	for slot in _slots:
		if slot is Dictionary and String(slot.get("kind", "")) == "palette":
			return true
	return false


func is_ready() -> bool:
	return _ready


## Start texture-animation slot `id` (the event-script Field Object ID). A new
## {55} on an already-active id restarts it.
func play(id: int) -> void:
	if not _ready:
		return
	if id < 0 or id >= _slots.size():
		push_warning("[MapTextureAnimator] field object id %d out of range (%d slots)" % [id, _slots.size()])
		return
	var slot: Dictionary = _slots[id]
	var kind := String(slot.get("kind", ""))

	# Frame timing. UV slots carry real frame data; non-UV slots (palette /
	# disabled) have no blit recipe — still register a short barrier so {57}
	# releases instead of hanging.
	var frame_count: int = int(slot.get("frame_count", 1))
	var frame_duration: int = int(slot.get("frame_duration", 1))
	var total_ticks: float = float(max(1, frame_count) * max(1, frame_duration))

	_active[id] = {
		"slot": slot,
		"kind": kind,
		"reverse": _REVERSE_MODES.has(String(slot.get("animation_mode", ""))),
		"frame_count": max(1, frame_count),
		"frame_duration": max(1, frame_duration),
		"elapsed": 0.0,
		"total": total_ticks,
		"cur_frame": -1,
	}
	# Draw the opening frame immediately so the animation is visible on the very
	# first tick (mirrors the PSX consumer arming the slot the same frame).
	if kind == "uv":
		_step_frame(id, true)
		if _work_tex:
			_work_tex.update(_work_img)
	elif kind == "palette":
		_step_palette_frame(id, true)
		if _pal_work_tex:
			_pal_work_tex.update(_pal_work_img)


func is_active(id: int) -> bool:
	return _active.has(id)


## The live (mutated) atlas image. Exposed for verification/tests.
func get_work_image() -> Image:
	return _work_img


## The pristine source atlas image. Exposed for verification/tests.
func get_source_image() -> Image:
	return _source_img


## Re-seed the pristine + working atlas from a freshly-derived indexed texture (e.g.
## a live `map.atlas_dilate_passes` scrub) WITHOUT replacing the material-facing
## `_work_tex`. The materials keep sampling the same texture object, so an
## edge-padding change lands on the running animation in place — the alternative,
## the caller swapping a static dilated texture into the `indexed_texture` uniform,
## would orphan this canvas and freeze the animation. Dilation preserves the atlas
## dimensions, so the in-place `_work_tex.update()` stays valid; a size mismatch is
## refused (returns false) rather than reallocating a texture the materials no
## longer point at. Returns false as a no-op when not yet set up.
func reseed_indexed_source(indexed_texture: Texture2D) -> bool:
	if not _ready or indexed_texture == null:
		return false
	var src := indexed_texture.get_image()
	if src == null:
		return false
	src = src.duplicate()
	if src.get_format() != Image.FORMAT_RGBA8:
		src.convert(Image.FORMAT_RGBA8)
	if _source_img != null and src.get_size() != _source_img.get_size():
		push_warning("[MapTextureAnimator] reseed size mismatch (%s vs %s); ignoring" \
			% [src.get_size(), _source_img.get_size()])
		return false
	_source_img = src
	_work_img = src.duplicate()
	# Redraw each active UV slot's current frame onto the fresh base so the animation
	# does not flash back to frame 0 between now and the next tick. (Palette slots
	# blit from _pal_source_img, which dilation does not touch.)
	for id in _active.keys():
		if String(_active[id]["kind"]) == "uv":
			_step_frame(id, true)
	if _work_tex:
		_work_tex.update(_work_img)
	return true


## The live (mutated) palette image. Exposed for verification/tests. Null when no
## palette texture was supplied to setup().
func get_work_palette_image() -> Image:
	return _pal_work_img


## The GPU texture backing the mutable palette. The caller swaps this into the map
## materials so palette-kind blits become visible. Null when no palette texture
## was supplied to setup().
func get_work_palette_texture() -> ImageTexture:
	return _pal_work_tex


## Compute the current frame for palette animation `id` and blit its animation row
## over the base palette row if it changed. Returns true if the palette image was
## modified. When `force` is true the blit always happens (the opening frame).
func _step_palette_frame(id: int, force: bool) -> bool:
	if _pal_work_img == null:
		return false
	var rec: Dictionary = _active[id]
	var count: int = int(rec["frame_count"])
	var dur: int = int(rec["frame_duration"])
	var step: int = int(float(rec["elapsed"]) / float(dur))
	var fidx: int
	if bool(rec["reverse"]):
		fidx = clampi(count - 1 - step, 0, count - 1)
	else:
		fidx = clampi(step, 0, count - 1)
	if not force and fidx == int(rec["cur_frame"]):
		return false
	rec["cur_frame"] = fidx
	_blit_palette_frame(rec["slot"], fidx)
	return true


## Blit animation-frame row (16 + start_index + frame) of the pristine palette
## over base row `overridden_palette_id` in the working palette (a 16px-wide,
## 1px-tall row copy). The map shader samples the base row by palette_id, so this
## recolors every polygon painted with that palette.
func _blit_palette_frame(slot: Dictionary, frame_index: int) -> void:
	var dst_row: int = int(slot.get("overridden_palette_id", -1))
	var start: int = int(slot.get("animation_start_index", 0))
	if dst_row < 0 or dst_row >= PALETTE_ANIM_ROW_BASE:
		return
	var src_row: int = PALETTE_ANIM_ROW_BASE + start + frame_index
	if src_row < 0 or src_row >= _pal_source_img.get_height():
		return
	_pal_work_img.blit_rect(
		_pal_source_img, Rect2i(0, src_row, 16, 1), Vector2i(0, dst_row))


func has_active() -> bool:
	return not _active.is_empty()


## Advance all active animations by `delta` seconds. Call once per frame.
func tick(delta: float) -> void:
	if _active.is_empty():
		return
	var dirty := false
	var pal_dirty := false
	var finished: Array = []
	for id in _active.keys():
		var rec: Dictionary = _active[id]
		rec["elapsed"] = float(rec["elapsed"]) + delta * TICKS_PER_SECOND
		if String(rec["kind"]) == "uv":
			if _step_frame(id, false):
				dirty = true
		elif String(rec["kind"]) == "palette":
			if _step_palette_frame(id, false):
				pal_dirty = true
		if float(rec["elapsed"]) >= float(rec["total"]):
			finished.append(id)
	for id in finished:
		var rec: Dictionary = _active[id]
		# End-state, evidence-backed (chapel slot 1 is a door-opening animation):
		# a FORWARD once-on-trigger "open" HOLDS its final frame so the door stays
		# open until an explicit reverse {55} closes it. A REVERSE once "close"
		# ends on frame 0 (ajar), so settle it back to the base/closed texture to
		# complete the closure. Looping (non-reverse) modes also just hold.
		if String(rec["kind"]) == "uv" and bool(rec["reverse"]):
			_restore_canvas(rec["slot"])
			dirty = true
		_active.erase(id)
	if dirty and _work_tex:
		_work_tex.update(_work_img)
	# Palette forward-once fades HOLD their final frame (the room stays dim after
	# Balbanes dies); the last frame is already blitted before finishing, so the
	# finish loop just drops the record — no restore.
	if pal_dirty and _pal_work_tex:
		_pal_work_tex.update(_pal_work_img)


## Compute the current frame for animation `id` and blit it if it changed.
## Returns true if the work image was modified. When `force` is true the blit
## always happens (used for the opening frame).
func _step_frame(id: int, force: bool) -> bool:
	var rec: Dictionary = _active[id]
	var count: int = int(rec["frame_count"])
	var dur: int = int(rec["frame_duration"])
	var step: int = int(float(rec["elapsed"]) / float(dur))
	var fidx: int
	if bool(rec["reverse"]):
		fidx = clampi(count - 1 - step, 0, count - 1)
	else:
		fidx = clampi(step, 0, count - 1)
	if not force and fidx == int(rec["cur_frame"]):
		return false
	rec["cur_frame"] = fidx
	_blit_frame(rec["slot"], fidx)
	return true


func _blit_frame(slot: Dictionary, frame_index: int) -> void:
	var w: int = int(slot.get("size_width", 0))
	var h: int = int(slot.get("size_height", 0))
	if w <= 0 or h <= 0:
		return
	var src_x: int = int(slot.get("first_frame_x", 0)) + frame_index * w
	var src_y: int = int(slot.get("first_frame_y", 0)) + int(slot.get("first_frame_texture_page", 0)) * PAGE_HEIGHT
	var dst_x: int = int(slot.get("canvas_x", 0))
	var dst_y: int = int(slot.get("canvas_y", 0)) + int(slot.get("canvas_texture_page", 0)) * PAGE_HEIGHT
	_blit(src_x, src_y, dst_x, dst_y, w, h)


func _restore_canvas(slot: Dictionary) -> void:
	var w: int = int(slot.get("size_width", 0))
	var h: int = int(slot.get("size_height", 0))
	if w <= 0 or h <= 0:
		return
	var dst_x: int = int(slot.get("canvas_x", 0))
	var dst_y: int = int(slot.get("canvas_y", 0)) + int(slot.get("canvas_texture_page", 0)) * PAGE_HEIGHT
	# Restore == blit the canvas region from the pristine source onto itself.
	_blit(dst_x, dst_y, dst_x, dst_y, w, h)


## Copy a w*h rectangle from the pristine source atlas into the work atlas,
## clipped to atlas bounds.
func _blit(src_x: int, src_y: int, dst_x: int, dst_y: int, w: int, h: int) -> void:
	var atlas_h := _source_img.get_height()
	# Clip width/height so neither the source nor destination rectangle leaves
	# the atlas (defensive — chapel slots stay in-bounds).
	w = mini(w, mini(ATLAS_WIDTH - src_x, ATLAS_WIDTH - dst_x))
	h = mini(h, mini(atlas_h - src_y, atlas_h - dst_y))
	if w <= 0 or h <= 0:
		return
	_work_img.blit_rect(_source_img, Rect2i(src_x, src_y, w, h), Vector2i(dst_x, dst_y))
