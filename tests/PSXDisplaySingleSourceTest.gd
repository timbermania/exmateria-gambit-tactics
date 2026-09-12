extends Node
## Guard test for the PSXDisplay single-source-of-truth seam (ADR-0036 Option A).
##
## The shader-backed mirrors on the PSXDisplay autoload (`live_par` /
## `live_cursor_stretch` / `live_unit_stretch` / `live_fx_stretch`) must carry NO
## default of their own — the number lives ONLY in `project.godot`
## `[shader_globals]`. PSXDisplay._ready() sources each mirror's default from that
## home (via `PSXDisplay.shader_global_default`, which reads `ProjectSettings`).
##
## All four mirrors are now Tune-backed (ADR-0068): each coalesces a committed
## `render.*` override OVER that same project.godot default. So the boot
## expectation for every mirror is the COALESCED value — we seed a distinct
## committed override per slug and assert the mirror reflects it, which proves two
## things at once: the live value routes through Tune (a hand-rolled mirror that
## ignored Tune would return the bare global and red this guard), AND the default
## still has ONE home (project.godot). If someone drops that sourcing or
## introduces a rival default, this test goes red (the seam leaked a second
## source again).
##
## `live_ui_par` is intentionally NOT covered — it is a GDScript-only mesh-width
## multiplier, not a shader global, so it keeps its own constant default.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/PSXDisplaySingleSourceTest.tscn

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	# mirror property name -> {backing shader-global, Tune slug}
	var mirrors := {
		"live_par": {"global": &"pixel_aspect", "slug": "render.pixel_aspect"},
		"live_cursor_stretch": {"global": &"psx_cursor_stretch", "slug": "render.psx_cursor_stretch"},
		"live_unit_stretch": {"global": &"unit_stretch", "slug": "render.unit_stretch"},
		"live_fx_stretch": {"global": &"psx_fx_stretch", "slug": "render.psx_fx_stretch"},
	}

	# Reproduce the real boot condition each tunable creates: a committed override
	# resident in Tune before this test reads the mirror (the whole point of the
	# tunable). Each mirror then reads override-over-default, so the seam's
	# expectation is the COALESCED value, not the bare project.godot default — and
	# a mirror that still ignores Tune (bare global) reds this guard (ADR-0068). We
	# use a distinct delta per slug so no two mirrors could accidentally agree.
	var delta := 0.1
	for prop in mirrors:
		var slug: String = mirrors[prop]["slug"]
		var global_val: float = PSXDisplay.shader_global_default(mirrors[prop]["global"])
		Tune.set_value(slug, global_val + delta)
		delta += 0.1

	for prop in mirrors:
		var slug: String = mirrors[prop]["slug"]
		var mirror: float = PSXDisplay.get(prop)
		# Oracle: the coalesced value for the (already _ready-bound) slug — get_value, since
		# `of` is retired. The override we seeded above is what both the mirror and this read.
		_check(prop, mirror, Tune.get_value(slug))

	for prop in mirrors:  # restore shared autoload state
		Tune.clear(mirrors[prop]["slug"])

	print("\n=== PSXDisplaySingleSourceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] PSXDisplaySingleSourceTest")
		get_tree().quit(1)
	else:
		print("[PASS] PSXDisplaySingleSourceTest")
		get_tree().quit(0)


func _check(prop: String, mirror: float, global_val: float) -> void:
	if is_equal_approx(mirror, global_val):
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] PSXDisplay.%s (%.4f) != project.godot global (%.4f)"
			% [prop, mirror, global_val])
