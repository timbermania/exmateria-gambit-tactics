extends Node
## Guards the TrapEffect → unified-compositor publish-path migration (#225): the CPU-side
## producer contract that feeds the display-space compositor, driven headless-safe in pure
## GDScript (no GPU needed — mirrors CombatDisplaySpaceCompositeTest._test_renderer_no_double_write).
##
## Trap keeps its bespoke particle sim; only render/publish changes. The invariants locked here:
##   - _particle_visual packs the ADR-0040 basis/uv/color the compositor consumes (commit 2);
##   - Trap emits 24-float unified records with the ADR-0040 packing + per-prim level (commit 3);
##   - each prim's blend mode is routed from its emitter's blend_mode (ADD→1/SUB→2/MIX→0/ADD25→3),
##     exercised with synthetic SUB + MIX emitters since the shipped asset is all-ADD (commit 3);
##   - per-particle ages are populated + drive newest-on-top ordering (commit 3);
##   - after the publish flip, Trap no longer writes the RM_MODE1 MultiMesh buffer (commit 4).
##
## Run: <GODOT> --path . --quit-after 60 res://tests/TrapUnifiedPublishTest.tscn

const TrapEffect = ExMateriaEffects.TrapEffect

const TrapEffectScript = ExMateriaEffects.TrapEffect

var _failed := false


func _check(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] %s" % msg)
		_failed = true


func _ready() -> void:
	_test_particle_visual_packing()
	_test_stage_records_and_mode_routing()
	_test_publish_flip_no_mm_write()

	if _failed:
		print("[FAIL] TrapUnifiedPublish test")
	else:
		print("[PASS] TrapUnifiedPublish: particle-visual packing; unified staging (record layout, mode routing, ages, level); publish flip (no MM write, unified published)")
	get_tree().quit()


## A synthetic TrapEffect with hand-set framesets/texture_size (bypasses initialize()'s asset
## load, so this is headless-safe). Caller spawns particles + drives the render helpers.
func _synthetic_trap() -> TrapEffect:
	var trap := TrapEffectScript.new()
	trap._framesets = [{
		"frames": [{
			"uv": {"x": 4, "y": 8, "width": 16, "height": 12},
			"vertices": {
				"top_left": [-8, -8], "top_right": [8, -8],
				"bottom_left": [-8, 8], "bottom_right": [8, 8],
			},
		}],
	}]
	trap._texture_size = Vector2(128, 128)
	add_child(trap)   # in-tree so global_position applies (and _ready runs harmlessly)
	trap.global_position = Vector3(2.0, 3.0, 4.0)
	return trap


func _mk_particle(frameset: int, pos: Vector3, palette_id: int, rgb: Vector3) -> Object:
	var p = TrapEffectScript.TrapParticle.new()
	p.current_frameset = frameset
	p.position = pos
	p.palette_id = palette_id
	p.rgb_mod = rgb
	return p


## Commit 2 (#225): _particle_visual(p, index) is the pure corner-basis / world-origin / uv_rect /
## color computation shared by the render paths. Assert its packed fields against hand-computed
## spec values (basis corners + depth_mode, texel-centered uv_rect, rgb_mod + palette_row/15 alpha,
## global_position + p.position origin) so the packing the compositor consumes can't drift.
func _test_particle_visual_packing() -> void:
	var trap := _synthetic_trap()
	var p = _mk_particle(0, Vector3(0.1, 0.2, 0.3), 10, Vector3(2.0, 2.0, 2.0))

	var v: Dictionary = trap._particle_visual(p, 0)
	_check(not v.is_empty(), "commit2: _particle_visual returns a value for a renderable particle")

	# Independently verify the packed fields (spec, not just self-consistency).
	_check(v["origin"].is_equal_approx(Vector3(2.1, 3.2, 4.3)),
		"commit2: origin = global_position + p.position, got %s" % v["origin"])
	var expect_uv := Color((4.0 + 0.5) / 128.0, (8.0 + 0.5) / 128.0,
		(16.0 - 1.0) / 128.0, (12.0 - 1.0) / 128.0)
	_check(v["uv_rect"].is_equal_approx(expect_uv),
		"commit2: texel-centered uv_rect, got %s expect %s" % [v["uv_rect"], expect_uv])
	_check(v["color"].is_equal_approx(Color(2.0, 2.0, 2.0, 10.0 / 15.0)),
		"commit2: color = rgb_mod + palette_id/15 in alpha, got %s" % v["color"])
	# Basis packs corners (tl.xy, tr.x)(tr.y, bl.xy)(br.xy, depth_mode).
	var expect_basis := Basis(
		Vector3(-8, -8, 8), Vector3(-8, -8, 8),
		Vector3(8, 8, float(TrapEffectScript._TRAP_DEPTH_MODE)))
	_check(v["basis"].is_equal_approx(expect_basis),
		"commit2: basis packs corners + depth_mode, got %s" % v["basis"])

	# A particle whose frameset index is out of range yields an empty (skip) result.
	var bad = _mk_particle(99, Vector3.ZERO, 0, Vector3.ONE)
	_check(trap._particle_visual(bad, 0).is_empty(),
		"commit2: _particle_visual returns {} for a non-renderable frameset")

	trap.queue_free()


## Commit 3 (#225): Trap builds the submission-order unified staging (records/modes/depths/ages)
## alongside its particle sim — byte-identical producer contract to EffectParticleRenderer. Each
## prim's blend mode is DATA-DERIVED from its emitter's blend_mode (emitters.json), mapped into the
## compositor enum (ADD→1/SUB→2/MIX→0/ADD25→3). The shipped asset is all-ADD, so this exercises
## SYNTHETIC sub/mix/add25 emitters to prove routing + per-prim level (0.25 for add25). Ages are
## populated (they drive newest-on-top ordering once published). Nothing consumes the arrays yet.
func _test_stage_records_and_mode_routing() -> void:
	var trap := _synthetic_trap()
	# Synthetic emitters exercising every blend_mode (the shipped asset is all-ADD).
	trap._emitters_config = [
		{"blend_mode": "ADD"},    # 0 -> mode 1
		{"blend_mode": "SUB"},    # 1 -> mode 2
		{"blend_mode": "MIX"},    # 2 -> mode 0
		{"blend_mode": "ADD25"},  # 3 -> mode 3
	]
	# Direct mode-routing unit checks.
	_check(trap._compositor_mode_for(0) == 1, "commit3: ADD -> compositor mode 1")
	_check(trap._compositor_mode_for(1) == 2, "commit3: SUB -> compositor mode 2")
	_check(trap._compositor_mode_for(2) == 0, "commit3: MIX -> compositor mode 0")
	_check(trap._compositor_mode_for(3) == 3, "commit3: ADD25 -> compositor mode 3")
	_check(trap._compositor_mode_for(99) == 1, "commit3: out-of-range emitter -> add fallback")

	# Four particles, one per emitter, distinct ages.
	var ages := [7, 3, 11, 1]
	for e in range(4):
		var p = _mk_particle(0, Vector3(0.1 * e, 0.2, 0.3), 10 + e, Vector3.ONE)
		p.emitter_type = e
		p.age = ages[e]
		trap._particles.append(p)

	trap._stage_unified_prims()

	# #6.2: the staging now lives in the shared UnifiedPrimStager (trap._stager) — same invariants,
	# single-sourced layout. Read the parallel arrays through its accessors.
	var recs: PackedFloat32Array = trap._stager.records()
	var modes: PackedInt32Array = trap._stager.modes()
	var ages_out: PackedFloat32Array = trap._stager.ages()
	var depths: PackedFloat32Array = trap._stager.depths()
	_check(recs.size() == 4 * 24,
		"commit3: 4 prims -> 4*24 unified floats, got %d" % recs.size())
	_check(modes.size() == 4 and ages_out.size() == 4 and depths.size() == 4,
		"commit3: parallel mode/age/depth arrays are N-long")
	_check(Array(modes) == [1, 2, 0, 3],
		"commit3: per-prim modes routed [add,sub,mix,add25], got %s" % [Array(modes)])
	_check(Array(ages_out) == [7.0, 3.0, 11.0, 1.0],
		"commit3: per-prim ages populated, got %s" % [Array(ages_out)])
	# Per-prim level_scale at [20]: 0.25 only for the ADD25 prim (index 3); pad [21..23] == 0.
	for e in range(4):
		var expect_level: float = 0.25 if e == 3 else 1.0
		_check(absf(recs[e * 24 + 20] - expect_level) < 1e-6,
			"commit3: prim %d level_scale = %.2f" % [e, expect_level])
		_check(recs[e * 24 + 21] == 0.0 and recs[e * 24 + 22] == 0.0
			and recs[e * 24 + 23] == 0.0, "commit3: prim %d pad [21..23] == 0" % e)

	# Record[0..19] byte-match _particle_visual for prim 0 (the ADR-0040 MultiMesh packing).
	var p0 = trap._particles[0]
	var v0: Dictionary = trap._particle_visual(p0, 0)
	var b: Basis = v0["basis"]
	var o: Vector3 = v0["origin"]
	var col: Color = v0["color"]
	var cust: Color = v0["uv_rect"]
	var expect0 := [b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y,
		b.x.z, b.y.z, b.z.z, o.z, col.r, col.g, col.b, col.a, cust.r, cust.g, cust.b, cust.a]
	var ok := true
	for f in range(20):
		if absf(recs[f] - expect0[f]) > 1e-6:
			ok = false
	_check(ok, "commit3: prim0 record[0..19] == _particle_visual ADR-0040 packing")

	trap.queue_free()


## Commit 4 (#225): the publish flip. Trap no longer writes a mode MultiMesh BUFFER — it
## OT-depth-orders its unified staging and publishes via upload_unified (with its indexed palette).
## Drives the REAL runtime path (EffectMultiMeshPool autoload + TrapEffect._render_particles),
## RD-free for the assertions. Locks: after a render, the slot's ONLY MultiMesh (RM_OPAQUE, #227)
## stays unwritten (Trap draws no in-scene mesh), while the slot's unified buffer carries the prims +
## runs + palette flag.
func _test_publish_flip_no_mm_write() -> void:
	var pool = get_node_or_null("/root/EffectMultiMeshPool")
	_check(pool != null, "commit4: EffectMultiMeshPool autoload present")
	if pool == null:
		return

	var trap := _synthetic_trap()   # in-tree; _ready cached the pool + _use_global_pool
	trap._emitters_config = [{"blend_mode": "ADD"}]
	# A texture + palette so _borrow_slot_if_needed binds the indexed sheet.
	trap._texture = ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	trap._palette_texture = ImageTexture.create_from_image(Image.create(16, 16, false, Image.FORMAT_RGBA8))
	trap._texture_size = Vector2(4, 4)

	for k in range(2):
		var p = _mk_particle(0, Vector3(0.1 * k, 0.2, 0.3), 10, Vector3.ONE)
		p.emitter_type = 0
		trap._particles.append(p)

	trap._render_particles()

	var slot: int = trap._pool_slot
	_check(slot >= 0, "commit4: trap borrowed a pool slot")
	if slot < 0:
		trap.queue_free()
		return
	# #227: the slot's only MultiMesh (RM_OPAQUE) is NOT written by Trap (visible count stays 0 from
	# borrow) — Trap draws no in-scene mesh, it only publishes the unified buffer.
	_check(pool.get_multimesh(slot).visible_instance_count == 0,
		"commit4: no in-scene MultiMesh written after the publish flip (buffer no longer a data source)")
	# The unified buffer IS published (both prims), with runs + the palette flag.
	_check(pool._all_slots[slot]["_count"] == 2,
		"commit4: unified buffer published with the 2 prims, got %d" % pool._all_slots[slot]["_count"])
	_check(not (pool._all_slots[slot]["_runs"] as Array).is_empty(),
		"commit4: unified runs published")
	_check(pool._all_slots[slot]["_use_palette"] == true,
		"commit4: upload_unified carried use_palette=true for Trap's indexed sheet")

	# stop() clears the unified buffer so the compositor stops folding Trap.
	trap.stop()
	_check(pool._all_slots[slot]["_count"] == 0,
		"commit4: stop()/_hide_all_meshes clears the unified buffer (count 0)")

	trap.queue_free()
