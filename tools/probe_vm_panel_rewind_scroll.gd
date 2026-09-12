extends SceneTree
## Regression probe for the Scenario VM debug panel's post-rewind scroll.
##
## Reproduces the exact double-click-rewind path a user drives by hand:
##   1. Boot ScenarioPlayer (scenario 2, 1689 opcodes) as the CURRENT scene so
##      the player's `reload_current_scene()` works.
##   2. Show the F3 debug overlay so the disassembly ItemList actually lays out
##      (get_item_rect / scrollbar max are only valid on a laid-out, visible list).
##   3. Scroll the list to the TOP, far from a target PC near the bottom.
##   4. Call `panel._request_rewind(target_pc)` — the same entry point the
##      ItemList's double-click (`_on_item_activated`) hits. This reloads the
##      scene and fast-forwards to target_pc.
##   5. After the reload + fast-forward settles, assert the target row is VISIBLE
##      in the list viewport (the fix) instead of the list sitting at the top
##      (the bug).
##
## Run (NOT headless — two windows open; stdout still returns):
##   # from the package root
##   godot --path . -s res://tools/probe_vm_panel_rewind_scroll.gd
##
## PASS = target row centred/visible after rewind. FAIL = list at top.

const SCEN := 2
const TARGET_PC := 350  # near the end of scenario 2's loaded chunk (~404 opcodes)

var _panel = null
var _f := 0
var _phase := "boot"
var _rewind_f := -1
var _pre_scroll_seen := false
var _maxf := 4000
var _quit := false

func _initialize() -> void:
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null:
		sess.selected_scenario_id = SCEN
	else:
		push_error("[probe] ScenarioDebugSession autoload missing")
	# Make ScenarioPlayer the CURRENT scene (change_scene, not add_child) so the
	# player's internal reload_current_scene() during rewind actually reloads it.
	var err := change_scene_to_file("res://assets/scenes/ScenarioPlayer.tscn")
	if err != OK:
		push_error("[probe] change_scene_to_file failed: %d" % err)
	# Show the overlay so the panel's ItemList lays out. (Reach autoloads via the
	# node, not the global identifier — a -s SceneTree script can't resolve those
	# at compile time.)
	var ov: Node = root.get_node_or_null("DebugOverlay")
	var cfg: Node = root.get_node_or_null("DebugConfig")
	if ov != null and cfg != null:
		if not bool(cfg.debug_overlay_visible):
			ov.toggle_overlay()
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	print("[probe] boot: scenario %d, target_pc=%d" % [SCEN, TARGET_PC])

func _process(_delta: float) -> bool:
	if _quit:
		quit()
		return true
	return false

func _host_list_in_main_viewport() -> void:
	var lst = _panel._list
	if lst == null:
		return
	var holder := PanelContainer.new()
	holder.name = "ProbeListHost"
	holder.position = Vector2(20, 20)
	holder.size = Vector2(380, 480)
	root.add_child(holder)
	lst.reparent(holder)
	lst.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lst.size_flags_vertical = Control.SIZE_EXPAND_FILL
	print("[probe] reparented list into main viewport host (380x480)")


func _find_panel() -> Object:
	# Duck-type the lookup — referencing the ScenarioVMDebugPanel class_name here
	# would force it (and its ScenarioDebugSession autoload dep) to compile before
	# autoloads register, breaking the -s launch. Match on the panel's members.
	var ov: Node = root.get_node_or_null("DebugOverlay")
	if ov == null:
		return null
	var cat = ov.Category.SCENARIO_PLAYBACK
	var arr: Array = ov._panels.get(cat, [])
	for p in arr:
		if p != null and is_instance_valid(p) and p.has_method("_request_rewind") \
				and ("_pending_scroll_row" in p):
			return p
	return null

func _vbar():
	if _panel == null or _panel._list == null:
		return null
	return _panel._list.get_v_scroll_bar()

func _row_visible(row: int) -> bool:
	var lst = _panel._list
	if row < 0 or row >= lst.item_count:
		return false
	var vbar = _vbar()
	if vbar == null:
		return false
	var rect: Rect2 = lst.get_item_rect(row)
	var top: float = vbar.value
	var bot: float = vbar.value + lst.size.y
	return rect.position.y >= top and (rect.position.y + rect.size.y) <= bot

func _on_post_draw() -> void:
	_f += 1
	if _f > _maxf:
		print("[probe] TIMEOUT at f=%d in phase '%s'" % [_f, _phase])
		_quit = true
		return

	if _panel == null:
		_panel = _find_panel()
		if _panel != null:
			print("[probe] panel found at f=%d" % _f)
			# The panel's ItemList lives inside the dashboard's separate Window, which
			# doesn't render (so never lays out its rows) in a -s launch. Reparent the
			# list into the MAIN viewport under a fixed-size container so it renders and
			# lays out exactly as the user sees it — the panel keeps driving it by ref.
			_host_list_in_main_viewport()
		return

	var vm = _panel._vm
	var vm_alive: bool = vm != null and is_instance_valid(vm)
	var lst = _panel._list

	match _phase:
		"boot":
			# Wait until the chunk is loaded (list populated) and the VM is idle
			# enough that the list has laid out.
			if _f % 120 == 0:
				var vb = _vbar()
				print("[probe] boot f=%d: vm_alive=%s ic=%d ff=%s list_sz=%s vbar_max=%s vis=%s" % [
					_f, str(vm_alive),
					(lst.item_count if lst != null else -1),
					(str(vm.is_fast_playing()) if vm_alive else "n/a"),
					(str(lst.size) if lst != null else "n/a"),
					(str(vb.max_value) if vb != null else "n/a"),
					str(_panel.visible)])
			if vm_alive and lst != null and lst.item_count > TARGET_PC and not vm.is_fast_playing():
				var vbar = _vbar()
				if vbar != null and vbar.max_value > 0.0:
					_phase = "scroll_top"
					print("[probe] list ready: item_count=%d, vbar.max=%.0f at f=%d" % [
						lst.item_count, vbar.max_value, _f])

		"scroll_top":
			# Scroll to the very top so the target row (near the bottom) is off-screen.
			var vbar = _vbar()
			vbar.value = vbar.min_value
			var vis_before := _row_visible(TARGET_PC)
			print("[probe] scrolled to top (value=%.1f); target row %d visible BEFORE rewind = %s" % [
				vbar.value, TARGET_PC, str(vis_before)])
			if vis_before:
				print("[probe] WARN: target already visible at top — pick a higher TARGET_PC")
			_phase = "rewind"

		"rewind":
			# The exact call a double-click makes. Reloads the scene + fast-forwards.
			print("[probe] firing _request_rewind(%d) at f=%d (scene will reload)" % [TARGET_PC, _f])
			_panel._request_rewind(TARGET_PC)
			_rewind_f = _f
			_phase = "await_settle"

		"await_settle":
			# After reload the panel rebinds and the VM fast-forwards to target_pc,
			# then pauses; the panel's own _process then runs _maybe_scroll_to_rewind_
			# target and consumes _pending_scroll_row. Wait until that has happened
			# (pending back to -1) so we measure the settled scroll, not a mid-flight
			# frame. Fall through to a verdict at the frame cap regardless.
			var settled: bool = vm_alive and not vm.is_fast_playing() and vm.paused \
					and lst != null and lst.item_count > TARGET_PC
			if settled and _panel._pending_scroll_row < 0 and _f > _rewind_f + 3:
				_evaluate()

func _evaluate() -> void:
	var lst = _panel._list
	var vbar = _vbar()
	var vis := _row_visible(TARGET_PC)
	var pc: int = _panel._vm.get_pc()
	print("[probe] ===== RESULT =====")
	print("[probe] after rewind+settle: vm.pc=%d  vbar.value=%.1f (max=%.1f, page=%.1f)  item_count=%d" % [
		pc, vbar.value, vbar.max_value, vbar.page, lst.item_count])
	var rect: Rect2 = lst.get_item_rect(TARGET_PC)
	print("[probe] target row %d content-y=%.1f..%.1f   viewport=%.1f..%.1f" % [
		TARGET_PC, rect.position.y, rect.position.y + rect.size.y,
		vbar.value, vbar.value + lst.size.y])
	print("[probe] pending_scroll_row (should be -1 = consumed): %d" % _panel._pending_scroll_row)
	if vis and vbar.value > 1.0:
		print("[probe] PASS ✓ — target row is visible and the list did NOT snap to the top")
	elif vbar.value <= 1.0:
		print("[probe] FAIL ✗ — list is at the TOP (value=%.1f); the bug is still present" % vbar.value)
	else:
		print("[probe] FAIL ✗ — target row %d is NOT visible in the viewport" % TARGET_PC)
	_quit = true
