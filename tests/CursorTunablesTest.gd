extends Node
## Move-2 guard for ADR-0068: the floating-cursor pose knobs (height, scale, bob
## scale, bob pace, palette row, and the STP-outline blend mode) are OWNED by
## TileCursor — it binds each to a `cursor.*` Tune slug in _ready — so a committed
## override coalesces onto the cursor on its first frame AND a live scrub re-drives
## the on-screen cursor, in EVERY scene, with no CursorDebugPanel fan-out (decision
## 12). Before this, the panel wrote straight onto the TileCursor node, so the knobs
## were dead in any scene without that panel open.
##
## Instantiates the real TileCursor.tscn (no map/camera — those lookups are guarded
## and null here); the cursor mesh is hidden after _ready, so its local Y rests at
## the static _apply_mesh_xform() value (no bob), which is what we assert against.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/CursorTunablesTest.tscn

var _passed: int = 0
var _failed: int = 0

const CURSOR_SCENE := "res://assets/scenes/CombatCursor.tscn"


func _ready() -> void:
	# Overrides must be live BEFORE the cursor spawns so its _ready bind sees them
	# (set-once at spawn, ADR-0068 R3.5).
	Tune.reset_overrides()
	# reset_overrides(), not reset(): the OVERRIDES go, the `_static_init` boot registration
	# stands. So every tunable this test's production scene reads — not just the ones it scrubs —
	# still coalesces onto a REGISTERED default rather than Nil (ADR-0068 R3), with
	# no central replay to call. This is the registration PRODUCTION runs on: nothing replays
	# there either (#535, ADR-0173). Plain reset() would clear the declarations and a
	# get_value() inside the spawned node would assert (R5).
	Tune.set_value("cursor.height", 3.0)
	Tune.set_value("cursor.scale", 1.5)

	# `TileCursor` has no `class_name` since ADR-0206 — the published name is
	# `CursorRig`. A test that drives the raw implementation holds it as a node.
	var cursor: Node3D = load(CURSOR_SCENE).instantiate()
	add_child(cursor)
	await get_tree().process_frame

	var mesh: MeshInstance3D = cursor.get_node("HighlightMesh")

	# --- Set-once at spawn: the pre-spawn overrides coalesced on the first frame ---
	_assert_approx(cursor.cursor_height, 3.0,
		"cursor.height override coalesces onto the cursor at spawn")
	_assert_approx(mesh.position.y, 3.0,
		"the spawn-time height override reaches the mesh Y")
	_assert_approx(cursor.cursor_scale, 1.5,
		"cursor.scale override coalesces onto the cursor at spawn")
	_assert_approx(mesh.scale.x, 1.5,
		"the spawn-time scale override reaches the mesh scale")

	# --- Live re-apply (bind, not read-once): scrubbing AFTER spawn re-drives it ---
	Tune.set_value("cursor.height", 2.0)
	Tune.set_value("cursor.scale", 0.5)
	Tune.set_value("cursor.bob_scale", 5.0)
	Tune.set_value("cursor.vblanks_per_tick", 4)
	Tune.set_value("cursor.palette_row", 2)
	Tune.set_value("cursor.blend_mode", 1)
	await get_tree().process_frame

	_assert_approx(cursor.cursor_height, 2.0,
		"scrubbing cursor.height live-updates the spawned cursor")
	_assert_approx(mesh.position.y, 2.0,
		"the live height scrub reaches the mesh Y")
	_assert_approx(cursor.cursor_scale, 0.5,
		"scrubbing cursor.scale live-updates the spawned cursor")
	_assert_approx(cursor.bob_scale, 5.0,
		"scrubbing cursor.bob_scale live-updates the spawned cursor")
	_assert_eq(cursor.vblanks_per_tick, 4,
		"scrubbing cursor.vblanks_per_tick live-updates the spawned cursor")

	var mats: Array = cursor.cursor_materials()
	_assert_eq(int(mats[0].get_shader_parameter("palette_row")), 2,
		"scrubbing cursor.palette_row re-drives the opaque body material param")
	# The semi outline routes through the compositor now (no swapped semi material) — the blend mode
	# is a plain value the producer reads. Scrubbing cursor.blend_mode updates it.
	_assert_eq(cursor.cursor_blend_mode(), 1,
		"scrubbing cursor.blend_mode updates the routed outline blend mode")

	print("\n=== CursorTunablesTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] CursorTunablesTest")
		get_tree().quit(1)
	else:
		print("[PASS] CursorTunablesTest")
		get_tree().quit(0)


func _assert_approx(actual: float, expected: float, label: String) -> void:
	if is_equal_approx(actual, expected):
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s (got %s, want %s)" % [label, actual, expected])


func _assert_eq(actual: int, expected: int, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s (got %s, want %s)" % [label, actual, expected])
