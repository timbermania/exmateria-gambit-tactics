extends Node
## TDD guard (real page + fake host) for the exhaustive SOUNDCONTAINER BROWSER (ADR-0085
## TIER-2 / ADR-0073) — the entry point that guarantees EVERY shared container is
## inspectable, including an ORPHAN one referenced by no trigger (used_by 0). Asserts the
## browser lists all containers and that activating one sets it as a fresh inspection root.
##
## The views are set directly (the real ones need a ROM E-dir's FEDS bank); this test is
## about the browser/nav wiring, not the projection (guarded by SoundContainerModelTest).
##
## Run: <GODOT> --path . --quit-after 6 res://tests/EffectStudioContainerBrowserTest.tscn

const Page = preload("res://src/effects/studio/EffectStudioPage.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_browser_lists_every_container()
	await _test_browsing_reaches_an_orphan_container()
	await _test_placeholder_is_a_no_op()

	print("\n=== EffectStudioContainerBrowserTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioContainerBrowserTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioContainerBrowserTest")
		get_tree().quit(0)


# Three containers; container 2 is an ORPHAN (used_by 0 — no trigger references it).
func _views() -> Array:
	return [
		{"index": 0, "mode_name": "TRIPLE_CYCLE", "used_by": 2},
		{"index": 1, "mode_name": "DIRECT_A", "used_by": 1},
		{"index": 2, "mode_name": "PARITY_A", "used_by": 0},
	]


func _test_browser_lists_every_container() -> void:
	var page = await _page()
	page._container_views = _views()
	page._refresh_container_browser()
	# One entry per container, plus the leading placeholder prompt.
	_assert_eq(page._container_picker.item_count, 4, "the browser lists every container (+ placeholder)")
	_assert_true(page._container_picker.get_item_text(3).find("container 2") != -1,
		"the last entry names container index 2")
	page.queue_free()


## Container 2 is referenced by no trigger — unreachable via a trigger link. The browser
## is the ONLY way in; activating it makes it the inspection root.
func _test_browsing_reaches_an_orphan_container() -> void:
	var page = await _page()
	page._container_views = _views()
	page._nav.clear()
	page._on_container_browsed(3)   # position 3 → container index 2 (the orphan)
	_assert_eq(page._nav.size(), 1, "browsing a container starts a fresh root")
	_assert_true(Target.equals(page._nav.back(), Target.container(2)),
		"the orphan container is now the inspection root — reachability guaranteed")
	page.queue_free()


func _test_placeholder_is_a_no_op() -> void:
	var page = await _page()
	page._container_views = _views()
	page._nav.clear()
	page._on_container_browsed(0)   # the "— pick container —" placeholder
	_assert_eq(page._nav.size(), 0, "selecting the placeholder mints no target")
	page.queue_free()


func _page():
	var page = Page.new()
	add_child(page)
	await get_tree().process_frame
	page.bind_host(_FakeHost.new())
	return page


class _FakeHost extends RefCounted:
	func studio_seek(_frame: int) -> void: pass
	func studio_set_playing(_playing: bool) -> void: pass
	func studio_current_frame() -> int: return 0
	func studio_select_effect(_id: int) -> void: pass


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
