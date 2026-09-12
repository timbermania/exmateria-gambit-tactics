extends Node3D
## Global shared MultiMesh pool for batched effect particle rendering (ADR-0040)
##
## Pre-creates N effect slots at game startup. #227: each slot is now ONE MultiMeshInstance3D —
## RM_OPAQUE (canvas + depth, backs #210), the only in-scene draw. It carries the opaque shader on a
## fixed material; the per-effect sheet rides the slot's plain `_effect_tex` field (set via
## set_effect_texture on borrow). The four RM_MODE0..3 blend-mode carriers were retired — the combat
## display-space compositor folds the transparent prims published to the unified SSBO below, so the
## mode MultiMeshes (and their "stash the sheet on a mode material and read it back" indirection) are
## gone.
##
## Per-instance state (corners, depth_mode, uv_rect, color_modulate, semi_trans_on) is packed into
## the MultiMesh's per-instance buffers — see EffectParticleRenderer.gd for the packing and
## effect_particle_stp.gdshaderinc for the shader-side unpack.
##
## #218/#220/#225: for the COMBAT display-space compositor each slot ALSO owns a unified 24-float
## transparent-prim SSBO (depth-ordered runs) — the particle producers publish it via upload_unified,
## TrapEffect included (#225 retired its bespoke MultiMesh-run publish; it now stages + folds
## through the shared path like the general renderer). slice D (#221) routed Studio / EffectViewer
## through the compositor too.
##
## Effect spawn becomes a slot pop + one set_effect_texture. Replaces the per-MeshInstance3D
## EffectMeshPool path that ADR-0040 retired.
## Vault: [[Display Space Blend Fold]]
## Vault: [[Effect MultiMesh Pool]]

const EffectsDebug = preload("res://addons/exmateria_effects/install/EffectsDebug.gd")
const WARMUP_TOTAL_SLOTS: int = 64       # Concurrent effects pre-warmed
const WARMUP_SLOTS_PER_FRAME: int = 8
const INITIAL_INSTANCE_COUNT: int = 32   # Per (slot, render_mode) MultiMesh
const GROWTH_INSTANCE_COUNT: int = 32

# #227: only the opaque draw survives per slot. RM_OPAQUE names the one in-scene MultiMesh (canvas +
# depth, backs #210); the RM_MODE0..3 blend-mode carriers were retired — the display-space compositor
# folds transparent prims from the unified SSBO, and the effect sheet moved to the plain _effect_tex
# slot field. The compositor's mode->pipeline mapping rides the run descriptors, not a pool constant.
const RM_OPAQUE: int = 0

# #227: only the opaque shader — the pool draws only RM_OPAQUE in-scene. The four
# effect_particle_mode0..3 shaders are no longer loaded here (the transparent fold happens in the
# display-space compositor, not a per-mode in-scene material).
const _SHADER_PATHS: Array = [
	"res://addons/exmateria_effects/render/effect_particle_opaque.gdshader",
]

# Each slot is { _opaque_mm: MultiMeshInstance3D, _opaque_mat: ShaderMaterial, _effect_tex: Texture2D,
# _unified_buf/_unified_cap/_runs/_count, _use_palette/_palette_tex } — #227 collapsed the old
# 5-wide mm[]/mat[] carriers to the single opaque draw + the plain sheet/palette fields.
var _all_slots: Array[Dictionary] = []
var _available_indices: Array[int] = []  # Free-list stack (LIFO)

var _shared_quad: QuadMesh
var _shaders: Array[Shader] = []  # parallel to _SHADER_PATHS (opaque only since #227)

var _warmup_created: int = 0
var _warmup_done: bool = false

# #227: only RM_OPAQUE draws in-scene (canvas + depth, backs #210). The display-space compositor
# folds the transparent prims published to the unified SSBO (combat AND Studio/viewer, slice D #221)
# — so the RM_MODE0..3 blend-mode carriers, the old `_mode_carriers_visible` gate, and the in-scene
# LINEAR blend fallback were all retired.


func _ready() -> void:
	# Shared quad mesh (1×1 in PSX units, scaled in the vertex shader)
	_shared_quad = QuadMesh.new()
	_shared_quad.size = Vector2(1.0, 1.0)

	# Load the slot shader(s) once (#227: opaque only)
	_shaders.resize(_SHADER_PATHS.size())
	for i in range(_SHADER_PATHS.size()):
		_shaders[i] = load(_SHADER_PATHS[i])


func _process(_delta: float) -> void:
	if _warmup_done:
		set_process(false)
		return
	_warmup_frame()


func _warmup_frame() -> void:
	var to_create: int = mini(WARMUP_SLOTS_PER_FRAME, WARMUP_TOTAL_SLOTS - _warmup_created)
	for i in range(to_create):
		_create_slot()
	_warmup_created += to_create

	if EffectsDebug.particle():
		print("[EffectMultiMeshPool] Warmup: %d / %d slots" % [_warmup_created, WARMUP_TOTAL_SLOTS])

	if _warmup_created >= WARMUP_TOTAL_SLOTS:
		_warmup_done = true
		if EffectsDebug.particle():
			print("[EffectMultiMeshPool] Warmup complete: %d slots ready" % _all_slots.size())


func _create_slot() -> void:
	var slot_idx: int = _all_slots.size()

	# #227: one MultiMesh per slot — RM_OPAQUE (canvas + depth, backs #210). The four RM_MODE0..3
	# blend-mode carriers were retired (the compositor folds transparent prims from the unified SSBO).
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = _shared_quad
	multimesh.instance_count = INITIAL_INSTANCE_COUNT
	multimesh.visible_instance_count = 0

	var mat := ShaderMaterial.new()
	mat.shader = _shaders[RM_OPAQUE]

	var mm_inst := MultiMeshInstance3D.new()
	mm_inst.multimesh = multimesh
	mm_inst.material_override = mat
	mm_inst.name = "Slot_%d_RM_OPAQUE" % slot_idx
	# Wide custom AABB — particles travel away from the slot's origin, and the basis stores corner
	# data (not a transform), so per-instance AABB computation would be wrong. The slot is parented
	# under this autoload but global_transform reads the effect's world origin per instance.
	mm_inst.custom_aabb = AABB(Vector3(-128.0, -128.0, -128.0), Vector3(256.0, 256.0, 256.0))
	mm_inst.visible = false
	add_child(mm_inst)

	# #218/Slice-D: the compositor folds ONE unified 24-float SSBO per slot.
	#   _opaque_mm/_opaque_mat — the one in-scene draw (RM_OPAQUE: canvas + depth).
	#   _effect_tex      — the effect sheet as a plain Texture2D (set by the producer; #227 replaced
	#                      the old "stash it on a mode material and read it back" round-trip).
	#   _unified_buf     — the RD storage buffer (invalid until the first upload; created/grown
	#                      on the RENDER THREAD via call_on_render_thread — main only references it)
	#   _unified_cap     — its capacity in bytes (free+recreate with headroom when exceeded)
	#   _runs / _count   — the run descriptors + total instance count the renderer published
	# (Single buffer, no double-buffering — RD barriers make buffer_update correct. Double-
	# buffering is a deferred perf follow-on.)
	_all_slots.append({
		"_opaque_mm": mm_inst, "_opaque_mat": mat,
		"_unified_buf": RID(), "_unified_cap": 0, "_runs": [], "_count": 0,
		"_effect_tex": null, "_palette_tex_2d": null,
	})
	_available_indices.append(slot_idx)


func borrow_slot() -> int:
	"""Pop one slot index from the free list. Grows on demand."""
	if _available_indices.is_empty():
		_create_slot()
		if EffectsDebug.particle():
			print("[EffectMultiMeshPool] On-demand growth: +1 slot (total %d)" % _all_slots.size())
	var idx: int = _available_indices.pop_back()
	# #227: only RM_OPAQUE draws in-scene (canvas + depth). The compositor folds transparent prims
	# from the unified buffer; nothing else renders in-scene.
	var opaque: MultiMeshInstance3D = _all_slots[idx]["_opaque_mm"]
	opaque.visible = true
	opaque.multimesh.visible_instance_count = 0
	# #218: the borrowed slot's unified transparent-prim buffer starts empty (the renderer
	# publishes it via upload_unified each frame). The RD buffer itself is retained across
	# borrows so its capacity is reused.
	_all_slots[idx]["_count"] = 0
	_all_slots[idx]["_runs"] = []
	_all_slots[idx]["_use_palette"] = false
	_all_slots[idx]["_palette_tex"] = RID()
	_all_slots[idx]["_palette_rows"] = 16
	_all_slots[idx]["_effect_tex"] = null  # #227: sheet set by the producer after borrow
	_all_slots[idx]["_palette_tex_2d"] = null  # engine-fold harness: palette as a Texture2D (set by paletted producers)
	return idx


func release_slot(idx: int) -> void:
	"""Hide the slot's opaque MultiMesh, reset its visible count, return to free list."""
	if idx < 0 or idx >= _all_slots.size():
		return
	var opaque: MultiMeshInstance3D = _all_slots[idx]["_opaque_mm"]
	opaque.multimesh.visible_instance_count = 0
	opaque.visible = false
	_all_slots[idx]["_count"] = 0
	_all_slots[idx]["_runs"] = []
	_all_slots[idx]["_effect_tex"] = null  # #227: released slot holds no sheet
	_available_indices.append(idx)


func get_multimesh(idx: int) -> MultiMesh:
	return _all_slots[idx]["_opaque_mm"].multimesh


func get_material(idx: int) -> ShaderMaterial:
	return _all_slots[idx]["_opaque_mat"]


func set_effect_texture(idx: int, tex: Texture2D) -> void:
	"""#227: stash this slot's effect sheet on the plain `_effect_tex` field. The compositor reads it
	back via get_active_effect_buckets (once repointed in commit 3), replacing the sheet's old home
	on a mode ShaderMaterial. Called by every producer (EffectParticleRenderer, TrapEffect) after
	borrow."""
	if idx < 0 or idx >= _all_slots.size():
		return
	_all_slots[idx]["_effect_tex"] = tex


func set_palette_texture(idx: int, tex: Texture2D) -> void:
	"""Engine-fold (Forward+) feed: stash this slot's CLUT as a plain Texture2D (parallel to
	set_effect_texture for the sheet). The raw-RD/GLSL fold reads the palette as an RD RID off
	upload_unified's `palette_tex`; the engine-fold ShaderMaterial fold needs a Texture2D for its
	`palette_texture` uniform, so a paletted producer calls this after borrow. ONE caller —
	TrapEffect.gd:304 (corrected 2026-08-21, ADR-0200: TileCursorCompositor left the pool to become a
	direct Fold.add producer and no longer calls this). null on an RGBA producer (no palette). Surfaced as `palette_tex_2d` by
	get_active_effect_buckets."""
	if idx < 0 or idx >= _all_slots.size():
		return
	_all_slots[idx]["_palette_tex_2d"] = tex


func ensure_instance_capacity(idx: int, needed: int) -> void:
	"""Grow the slot's opaque MultiMesh instance_count if needed."""
	var multimesh: MultiMesh = _all_slots[idx]["_opaque_mm"].multimesh
	if multimesh.instance_count >= needed:
		return
	var new_count: int = maxi(needed, multimesh.instance_count + GROWTH_INSTANCE_COUNT)
	multimesh.instance_count = new_count
	if EffectsDebug.particle():
		print("[EffectMultiMeshPool] Grew slot %d to %d instances" % [idx, new_count])


func get_available_count() -> int:
	return _available_indices.size()


# --- #211/#217/#218: combat display-space compositor integration ---

# Extra headroom (bytes) when the unified buffer must grow, so a slowly-growing effect
# doesn't reallocate every frame.
const _UNIFIED_HEADROOM_BYTES: int = 8192


func upload_unified(idx: int, bytes: PackedByteArray, count: int, runs: Array,
		use_palette: bool = false, palette_tex: RID = RID(), palette_rows: int = 16) -> void:
	"""#218/#220: publish this slot's unified transparent-prim buffer for the combat compositor.
	`bytes` is the per-instance packing (24 floats/instance since slice C — the 20-float ADR-0040
	packing + per-prim level_scale at [20] + pad; this upload is byte-agnostic), `count` the total
	instance count, `runs` the run descriptors {mode,base,count,stride} the compositor folds (slice C
	collapses adjacent same-DIRECTION runs and stamps stride=24). #225: `use_palette` + `palette_tex`
	carry an INDEXED sheet — the one capability the unified path lacked (it assumed RGBA), so a
	paletted producer (TrapEffect's TRAP1 indexed sheet + 16×16 palette) can ride it. They default
	off, so existing RGBA callers (EffectParticleRenderer) are unaffected. Stored on the same slot
	fields get_active_effect_buckets already reads for palette. The RD storage buffer is
	created/grown/uploaded on the RENDER THREAD
	(RenderingServer.call_on_render_thread) — the main thread only stores the resulting RID and
	the run/count metadata. Created lazily on the first upload (a 1-frame warmup lag is fine; the
	compositor skips an invalid RID / zero count). Single buffer, no double-buffering — RD
	barriers make buffer_update correct (double-buffering is a deferred perf follow-on)."""
	if idx < 0 or idx >= _all_slots.size():
		return
	var slot: Dictionary = _all_slots[idx]
	slot["_runs"] = runs
	slot["_count"] = count
	slot["_use_palette"] = use_palette
	slot["_palette_tex"] = palette_tex
	# Palette texture HEIGHT (trap's TRAP1 palette is 16 rows, the tile cursor's RANGETILE 9). The
	# compositor's fold divides the CLUT row V by this, so effects of different height can coexist.
	slot["_palette_rows"] = palette_rows
	# Engine-fold (Forward+) feed: retain the main-thread CPU copy of the packed records so
	# EngineFoldCompositor can rebuild them as per-run MultiMesh carriers without a render-thread
	# buffer_get_data round-trip. The raw-RD/GLSL fold path reads the RD buffer directly instead.
	slot["_unified_bytes"] = bytes
	if count <= 0 or bytes.is_empty():
		return
	RenderingServer.call_on_render_thread(_rt_upload_unified.bind(idx, bytes))


func _rt_upload_unified(idx: int, bytes: PackedByteArray) -> void:
	"""RENDER-THREAD: create / grow / update the slot's unified RD storage buffer, writing the
	resulting RID back onto the slot. Main reads that RID next frame (guarded invalid); a grow
	frees the old buffer and allocates with headroom so steady state is a plain buffer_update."""
	var rd := RenderingServer.get_rendering_device()
	if rd == null:
		return
	var slot: Dictionary = _all_slots[idx]
	var buf: RID = slot["_unified_buf"]
	var cap: int = slot["_unified_cap"]
	var need: int = bytes.size()
	if not buf.is_valid() or need > cap:
		if buf.is_valid():
			rd.free_rid(buf)
		var alloc: int = need + _UNIFIED_HEADROOM_BYTES
		# storage_buffer_create rejects a data payload whose size != the requested buffer size, so
		# allocate the headroom-padded buffer EMPTY, then upload the `need` bytes (#213: the old
		# create(alloc, bytes) mismatched alloc vs bytes.size() and returned RID() every create —
		# so the unified combat carrier never got a valid buffer; only the direct-RD probes, which
		# create at exact size, exercised this path).
		buf = rd.storage_buffer_create(alloc)
		slot["_unified_buf"] = buf
		slot["_unified_cap"] = alloc
	rd.buffer_update(buf, 0, need, bytes)


func get_active_effect_buckets() -> Array:
	"""#218: enumerate every borrowed (active) slot with a populated unified buffer for the
	combat display-space compositor to fold. One entry per active slot with count>0 and a valid
	_unified_buf:
	  { unified_bytes: PackedByteArray — the CPU copy of the packed 24-float records (LIVE),
	    runs: Array         — run descriptors {mode, base, count, stride, depth} (base into records),
	    effect_tex_2d: Texture2D — the slot's effect sheet (LIVE),
	    palette_tex_2d: Texture2D, use_palette: bool, palette_rows: int (LIVE),
	    unified_buf: RID, effect_tex: RID, palette_tex: RID, count: int — DEAD, see below }
	Corrected 2026-08-21 (ADR-0200): this listed six fields; ten are emitted. The four marked
	DEAD have ZERO readers repo-wide — they served the raw-RD/GLSL fold retired in #228 Phase 3,
	and ADR-0200 dec. 3 deletes them along with _rt_upload_unified and the palette RD RID.
	Opaque-only / idle slots (count<=0) and slots whose buffer hasn't been created yet (1-frame
	warmup) are skipped. Main-thread only (texture_get_rd_texture). #227: the effect sheet is read
	from the slot's plain _effect_tex field (set by the producer via set_effect_texture) — the old
	"stash it on a mode ShaderMaterial and read it back" round-trip is retired."""
	var out: Array = []
	var avail := {}
	for i in _available_indices:
		avail[i] = true
	for idx in range(_all_slots.size()):
		if avail.has(idx):
			continue
		var slot: Dictionary = _all_slots[idx]
		var count: int = slot["_count"]
		var runs: Array = slot["_runs"]
		if count <= 0 or runs.is_empty():
			continue
		var unified: RID = slot["_unified_buf"]
		if not unified.is_valid():
			continue  # 1-frame warmup: the render-thread create hasn't landed yet
		# #227: effect sheet from the slot's plain _effect_tex field (set by the producer via
		# set_effect_texture), NOT read back off a mode ShaderMaterial. The mode-material round-trip is
		# gone; the field is the sole source of truth.
		var tex: Texture2D = slot["_effect_tex"]
		if tex == null:
			continue
		var tex_rd: RID = RenderingServer.texture_get_rd_texture(tex.get_rid())
		if not tex_rd.is_valid():
			continue
		# A paletted producer (TrapEffect's indexed TRAP1 sheet) sets these via upload_unified; the
		# RGBA renderer path leaves them off (default false / null palette).
		var use_palette: bool = slot.get("_use_palette", false)
		var pal_rid: RID = slot.get("_palette_tex", RID())
		out.append({
			"unified_buf": unified,
			"runs": runs,
			"count": count,
			"effect_tex": tex_rd,
			# Engine-fold (Forward+) feed: the sheet as a Texture2D (for a ShaderMaterial's
			# effect_texture uniform) + the main-thread CPU record bytes. The raw-RD/GLSL path uses
			# the RD RIDs (effect_tex / palette_tex) instead.
			"effect_tex_2d": tex,
			"unified_bytes": slot.get("_unified_bytes", PackedByteArray()),
			"palette_tex": pal_rid,
			# Engine-fold (Forward+) feed: the CLUT as a Texture2D for a ShaderMaterial's
			# palette_texture uniform (the raw-RD path uses palette_tex's RD RID). null on RGBA slots.
			"palette_tex_2d": slot.get("_palette_tex_2d", null),
			"use_palette": use_palette,
			"palette_rows": slot.get("_palette_rows", 16),
		})
	return out
