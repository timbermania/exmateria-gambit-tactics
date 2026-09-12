extends Control
# test-kind: logic
# seeded-break: neutralise the throttle gate in src/debug/PerfDebugPanel.gd `_on_sample_taken` (`if _since_update_ms < LIVE_UPDATE_INTERVAL_MS:` -> `if false:`) so both fidelities run at sample rate again — arm 1 ('1000 samples of 1 ms moved the live label 1000 times, expected 10') and arm 2 (the same simulated second as 100 samples of 10 ms, which is what proves the throttle counts SIMULATED ms and not frames) both red
## W4 — the F3 overlay's live readout refreshes at ~10 Hz, not at frame rate.
##
## The overlay costs ~26 % fps WHILE OPEN, and the goal is a fast game with it up, so
## "close it" is not the fix. Round 2 split that cost: `PerfDebugPanel`'s 240-sample
## graph redraw is ~31 % of it and its per-frame `Label` format another ~15 %. Both are
## a readout a human eye reads; ten updates a second is fully legible.
##
## `PerfMonitor` samples EVERY frame and emits `sample_taken` every frame — that part is
## right, the ring buffer the graph draws has to stay dense. What was wrong is that the
## panel did full-fidelity work on every one of those emissions.
##
## Counted work, never wall clock (W8's standing ruling). The panel accumulates each
## sample's OWN `frame_time_ms` rather than reading the clock, so this test drives the
## rate deterministically by handing it synthetic samples.
##
##   1. The throttle holds — 1000 samples of 1 ms each (one simulated second) update the
##      live label 10 times, not 1000. Control: the same 1000 samples with the ceiling
##      dropped to zero update it every time, so a passing arm 1 cannot be a panel that
##      simply stopped working.
##   2. It is a RATE, not every-Nth-sample — 100 samples of 10 ms each is the same
##      simulated second and must also give 10 updates. A frame-count throttle would
##      give 1 here, and would stall the readout exactly when the frame rate drops and a
##      developer most needs to read it.
##   3. The visibility gate still comes first — with the overlay flag down, 1000 samples
##      update the label zero times.
##   4. The graph redraw shares the ONE gate. Counted through real `draw` emissions on
##      the graph control, which is why this test is a `Control` in the main viewport
##      rather than a bare object.

const PerfMonitorScript = preload("res://src/debug/PerfMonitor.gd")

## One simulated second, spent two ways. Both must buy the same number of updates.
const SIM_SECOND_MS: float = 1000.0
const EXPECTED_UPDATES: int = 10

var _panel: PerfDebugPanel = null
var _label: Label = null
var _graph: Control = null
var _draws: int = 0
var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	if not _build_panel():
		print("[FAIL] Perf panel throttle: the panel did not come up")
		get_tree().quit()
		return

	_arm_1_the_throttle_holds()
	_arm_2_it_is_a_rate_not_every_nth_sample()
	_arm_3_the_visibility_gate_comes_first()
	_arm_4_the_graph_shares_the_gate()

	print("=== PerfPanelThrottleTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] PerfPanelThrottleTest")
	else:
		print("[PASS] Perf panel throttle: one simulated second buys %d live updates however it is spent, the visibility gate still comes first, and the graph redraw shares the gate" % EXPECTED_UPDATES)
	get_tree().quit()


# === Harness ==================================================================

## Stand the real panel up the way `GPUArena` does — `new()`, `setup()` — and mount it
## in the main viewport so `is_visible_in_tree()` is true for the label and the graph.
##
## `setup()` subscribes the panel to the live `PerfMonitor`, which emits once per real
## frame. That is disconnected immediately: every sample this test counts must be one it
## handed over itself, or the count would be a function of how many frames the run took.
func _build_panel() -> bool:
	_panel = PerfDebugPanel.new()
	_panel.setup()
	add_child(_panel)
	if PerfMonitor and PerfMonitor.sample_taken.is_connected(_panel._on_sample):
		PerfMonitor.sample_taken.disconnect(_panel._on_sample)
	_label = _panel._live_label
	_graph = _panel._graph
	if _label == null or _graph == null:
		push_error("[PerfPanelThrottleTest] the panel built no live label / graph")
		return false
	DebugConfig.debug_overlay_visible = true
	await_visible()
	return _label.is_visible_in_tree() and _graph.is_visible_in_tree()


func await_visible() -> void:
	_panel.visible = true
	show()


## Hand the panel `count` samples, each claiming `frame_ms` of frame time, and report how
## many of them actually moved the live label. `fps` is varied per sample so that every
## update the panel DOES perform writes a different string — otherwise two consecutive
## updates could format identically and read as one.
func _updates_over(count: int, frame_ms: float) -> int:
	_panel._since_update_ms = 0.0
	var seen: String = "«none»"
	_label.text = seen
	var updates: int = 0
	for i in range(count):
		var s = PerfMonitorScript.Sample.new()
		s.frame_time_ms = frame_ms
		s.fps = float(i)
		_panel._on_sample(s)
		if _label.text != seen:
			seen = _label.text
			updates += 1
	return updates


func _check(ok: bool, msg: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % msg)


# === 1. The throttle holds ====================================================

func _arm_1_the_throttle_holds() -> void:
	var updates: int = _updates_over(1000, 1.0)
	_check(updates == EXPECTED_UPDATES,
		"arm 1: 1000 samples of 1 ms moved the live label %d times, expected %d" % [
			updates, EXPECTED_UPDATES])

	# The control, through the production constant rather than around it: samples that
	# each claim a full interval of frame time must EVERY one land. Without this, arm 1
	# would pass just as well for a panel that had stopped updating entirely.
	var unthrottled: int = _updates_over(1000, _panel.LIVE_UPDATE_INTERVAL_MS)
	_check(unthrottled == 1000,
		"arm 1 control: %d of 1000 samples each carrying a full %.0f ms moved the label — arm 1 proves nothing" % [
			unthrottled, _panel.LIVE_UPDATE_INTERVAL_MS])


# === 2. It is a rate, not every-Nth-sample ====================================

func _arm_2_it_is_a_rate_not_every_nth_sample() -> void:
	var updates: int = _updates_over(100, 10.0)
	_check(updates == EXPECTED_UPDATES,
		"arm 2: the same simulated second spent as 100 samples of 10 ms moved the label %d times, expected %d — the throttle is counting frames, not time, and will stall the readout exactly when the frame rate drops" % [
			updates, EXPECTED_UPDATES])


# === 3. The visibility gate comes first =======================================

func _arm_3_the_visibility_gate_comes_first() -> void:
	DebugConfig.debug_overlay_visible = false
	var updates: int = _updates_over(1000, 1.0)
	DebugConfig.debug_overlay_visible = true
	_check(updates == 0,
		"arm 3: with the overlay flag down, %d of 1000 samples still moved the label" % updates)


# === 4. The graph redraw shares the gate ======================================

## The graph is the larger half of the two (~31 % of the overlay's cost against the
## label's ~15 %), so a throttle that reached only the label would leave most of the
## item in place. Counted through real `draw` emissions rather than the label, so this
## arm cannot be satisfied by the same branch arm 1 already checked.
##
## ⚠ The bound is deliberately loose, and honestly so: a `Control` also draws for
## reasons that are nobody's business here — the first layout pass, a theme change, a
## resize. The assertion is not "exactly 10"; it is "nowhere near 1000". Trunk redrew on
## every sample, so anything under 50 over 1000 samples is decisive for the regression
## this guards, and a stray layout draw cannot flip it.
func _arm_4_the_graph_shares_the_gate() -> void:
	_graph.draw.connect(_on_graph_draw)
	# A settled frame first, so the panel's own first layout draw is not in the count.
	await get_tree().process_frame
	_draws = 0
	_panel._since_update_ms = 0.0
	for i in range(1000):
		var s = PerfMonitorScript.Sample.new()
		s.frame_time_ms = 1.0
		s.fps = float(i)
		_panel._on_sample(s)
		if i % 100 == 99:
			await get_tree().process_frame
	_graph.draw.disconnect(_on_graph_draw)
	_check(_draws > 0 and _draws < 50,
		"arm 4: the graph drew %d times over 1000 samples — expected a handful (trunk drew on every sample); 0 would mean the graph never redraws at all" % _draws)


func _on_graph_draw() -> void:
	_draws += 1
