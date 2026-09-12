extends Node
## The Fold kernel's published surface as a SPEC (ADR-0191): the build predicate `owns()`, the
## two-way pick `shader()` that hangs off it, and the `add()` enrol contract.
##
## Why the kernel owns the predicate: "is the fold available in this build?" was a verbatim
## six-line copy at fourteen call sites reaching a host autoload by node-path string. ADR-0191
## dec. 1 publishes it here on the measurement that CompositorAutopilot.active is written in
## exactly one place from exactly this RenderingServer query, so a kernel-side owns() is not
## merely equivalent to the old owns_compositing() — it is identical in every reachable state.
## THAT is what this test asserts: the two values, computed by two independent code paths, agree.
##
## Pure GDScript. No RenderingDevice, no render callback: owns() is a capability query and
## shader() is a pure two-way pick, so both are readable without entering a frame.
##
## Run: <GODOT> --path . res://tests/FoldTest.tscn

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const DepthMode = ExMateriaSchema.DepthMode
const Fold = ExMateriaSchema.Fold

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	# --- 1. owns() is the build predicate, and it agrees with the autoload it replaces ----------
	# The independent oracle is CompositorAutopilot.active — set once in its _ready from that file's
	# OWN RenderingServer query, never written again, which is the measurement ADR-0191 dec. 1 rests
	# on. If these two ever disagree, the migration in commit 2 silently changed behaviour at fourteen
	# sites.
	#
	# The autopilot's copy of the query is deliberate and load-bearing. It was briefly rewritten to
	# `active = Fold.owns()`, which turned this assert into x == x: seeding owns() to return the WRONG
	# answer left THIS LINE green while three other asserts went red. Two paths, or no oracle. If you
	# ever "dedupe" that query away, delete this assert in the same commit rather than leave it inert.
	var ap := get_node_or_null("/root/CompositorAutopilot")
	_assert_true(ap != null, "CompositorAutopilot autoload is up (the oracle for owns())")
	if ap != null:
		_assert_true(Fold.owns() == ap.active,
			"Fold.owns() == CompositorAutopilot.active (%s vs %s)" % [Fold.owns(), ap.active])

	# On the 4.8 compositor fork the answer is true; a run reporting false is either stock Godot
	# or a broken feature detect, and every folded prim would silently vanish. Assert the fork,
	# because a test suite that passes off-fork is grading a degraded frame.
	_assert_true(Fold.owns(), "owns() is true on the compositor fork (CLAUDE.md: never stock 4.7)")

	# It is a snapshot, not a live query: repeated reads must not disagree.
	_assert_true(Fold.owns() == Fold.owns(), "owns() is stable across calls (cached snapshot)")


	# --- 2. shader() picks the folded shader when the build owns compositing -------------------
	# Shader OBJECTS, never paths (ADR-0191 dec. 2): the kernel touches no filesystem and can name
	# no host file. Two bare Shader.new() instances are enough to assert the pick by IDENTITY — if
	# shader() ever load()ed anything, these could not be the values coming back.
	var folded_shader := Shader.new()
	var fallback_shader := Shader.new()
	_assert_true(Fold.shader(folded_shader, fallback_shader) == folded_shader,
		"shader() returns the FOLDED shader when owns() is true")

	# --- 3. shader() picks the FALLBACK when the build does NOT own compositing ----------------
	# Off-fork is the one branch a run here cannot reach: this suite only runs on the 4.8 compositor
	# fork (CLAUDE.md), where owns() is permanently true. So the predicate's cached snapshot is
	# overridden across these two asserts and restored immediately — the same mutate-and-restore
	# FoldSurfaceTest does to FoldSurface.quantize_levels. Without it the fallback half of every
	# producer's two-shader pick ships untested, and off-fork is precisely where nobody is looking.
	var restore_owns: int = Fold._owns_cache
	Fold._owns_cache = 0
	_assert_true(not Fold.owns(), "the off-fork state is reachable (owns() reads false under the override)")
	_assert_true(Fold.shader(folded_shader, fallback_shader) == fallback_shader,
		"shader() returns the FALLBACK shader when owns() is false")
	Fold._owns_cache = restore_owns
	_assert_true(Fold.owns(), "the override is restored — owns() is true again for the rest of the run")

	# --- 4. the Fold.add contract — the one piece of fold code there has ever been -------------
	# Consolidated here from CallbackFoldRoutingTest and FormationFoldRoutingTest, which asserted it
	# verbatim in both (ADR-0191 dec. 10). Those two are about ROUTING — which shaders declare
	# compositor_layer — and the decorator's contract is not that question.
	#
	# The expected order key is a LITERAL, not a re-call of DepthMode.render_layer_order_for: bucket 3
	# at RANK_STRIDE 1024 plus rank 2 is 3074. Recomputing it the way add() does would pass no matter
	# what either function did.
	var mi := MeshInstance3D.new()
	mi.mesh = QuadMesh.new()
	var mat := ShaderMaterial.new()
	var order_z := 3.0 * DepthMode.UNITS_PER_OT_BUCKET   # exactly OT bucket 3
	Fold.add(mi, mat, order_z, 2)
	_assert_true(mi.material_override == mat, "add() wears the given material as material_override")
	_assert_true(mi.render_layer == Fold.FOLD_LAYER,
		"add() joins the ONE shared fold layer (render_layer membership — one layer, one partition)")
	_assert_true(mi.render_layer_order == 3074,
		"add() stamps render_layer_order = bucket 3 * 1024 + rank 2 = 3074 (got %d)" % mi.render_layer_order)
	Fold.add(mi, mat, order_z)
	_assert_true(mi.render_layer_order == 3072, "add()'s default rank 0 sits exactly on the OT bucket (3 * 1024)")

	# Idempotent: add() may run every frame for a pooled carrier, so the tree_exiting un-enroll hook
	# must be connected at most once. Two more calls, then count.
	Fold.add(mi, mat, order_z)
	_assert_true(mi.tree_exiting.get_connections().size() == 1,
		"add() hooks tree_exiting exactly once across repeat calls (got %d)" % mi.tree_exiting.get_connections().size())
	mi.free()

	# A producer whose carrier was freed mid-frame must not crash the fold.
	Fold.add(null, mat, order_z)
	_assert_true(true, "add(null) is a no-op, not a crash")

	# --- 5. add() is a NO-OP off-fork (ADR-0191 dec. 12) ---------------------------------
	# `render_layer` / `render_layer_order` are FORK-ONLY properties. Measured on stock 4.7.1 in a
	# throwaway project: `mi.render_layer = null` raises "Invalid assignment of property or key
	# 'render_layer' ... on a base object of type 'MeshInstance3D'" and aborts the caller — the same
	# script SURVIVES on the 4.8 fork, which is the control arm that makes the stock result mean
	# something. So an unguarded add() does not "do nothing harmless" off-fork; it throws, every
	# frame, from _process. Two production paths reached it that way (CrystalSprite3D and the
	# additive tile overlay), so the gate belongs in the kernel that published the predicate.
	#
	# This runs ON the fork, where the assignment would succeed, so the override is what makes the
	# assert mean anything: it proves add() DECLINES to stamp, not that the engine refused it.
	var off_mi := MeshInstance3D.new()
	off_mi.mesh = QuadMesh.new()
	var off_restore: int = Fold._owns_cache
	Fold._owns_cache = 0
	Fold.add(off_mi, mat, order_z, 2)
	Fold._owns_cache = off_restore
	_assert_true(off_mi.render_layer == null,
		"add() off-fork leaves render_layer UNSET (the fork-only property is never assigned)")
	_assert_true(off_mi.render_layer_order == 0,
		"add() off-fork leaves render_layer_order at its default (got %d)" % off_mi.render_layer_order)
	_assert_true(off_mi.material_override == null,
		"add() off-fork wears no material_override either — it declines the whole decoration")
	_assert_true(off_mi.tree_exiting.get_connections().is_empty(),
		"add() off-fork hooks no tree_exiting (nothing to un-enroll)")
	off_mi.free()
	_assert_true(Fold.owns(), "the off-fork override is restored for the rest of the run")

	_finish()


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % label)


func _finish() -> void:
	print("\n=== FoldTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] FoldTest")
		get_tree().quit(1)
	else:
		print("[PASS] FoldTest")
		get_tree().quit(0)
