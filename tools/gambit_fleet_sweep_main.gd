extends Node3D

## THE FLEET SWEEPER'S LAUNCHER — build the board, hand it to the sweeper, print the report.
## ADR-0275 decs. 13, 15, 16; issue #1130.
##
## This node exists for ONE reason: a [Lattice] is built by `MapComposer`, which is a
## `Node3D`, so something has to be in the tree to hold it. Everything past that line — the
## fleet, the lockstep advance, the latch, the scoring — is in `tools/gambit_fleet_sweep.gd`,
## which is a `RefCounted` and has no scene at all (dec. 13).
##
## It is NOT a [CombatHost] and must not become one. dec. 13 splits the lab on the fleet/live
## line: the live arm is a `CombatHost` subclass because a human watches one cell in it; this
## arm has no camera, no units, no `CombatLoop`, and renders nothing. The one thing it shares
## with the live arm is [GambitScenarioBoot], and that sharing is the point — a fleet cell and
## a live cell reach the GPU through the same `build_battle_spec`.
##
## === RUNNING IT ===========================================================================
##
## Headful, never `--headless`, on the 4.8 fork. From `godot-learning/`:
##
##     godot --path . tools/gambit_fleet_sweep.tscn
##     godot --path . tools/gambit_fleet_sweep.tscn -- fleet=64 out=res://tools/logs/x.txt
##     godot --path . tools/gambit_fleet_sweep.tscn -- only=COND_HP
##
## `--` args (all optional, ADR-0051 dec. 5): `fleet=` the battles per batch, `only=` a
## case-insensitive substring filter on the cell name, `out=` where the report goes.
##
## === THE REPORT IS GITIGNORED AND THAT IS A DECISION (dec. 16) =============================
##
## `res://tools/logs/` is covered by `godot-learning/**/logs/` in `.gitignore`. The sweep's
## INPUTS — the straddle table, the synthesizer, the two censuses — are knowledge and are
## committed; its OUTPUT is a measurement, and a committed measurement is a `tests/logs/` in
## waiting. If you want the numbers in the repo, put them on a ticket where they carry a date
## and a SHA, not in a file that will be stale and unmarked in a week.
##
## === IT IS NOT A TEST (dec. 15) ===========================================================
##
## It asserts nothing and gates nothing, and it exits 0 whatever the cells say — a FAIL row
## here is a finding to read, not a build to break. See the sweeper's docstring for why
## promoting any part of it to the suite is rejected rather than deferred.

const SWEEPER := preload("res://tools/gambit_fleet_sweep.gd")

const DEFAULT_OUT := "res://tools/logs/gambit_fleet_sweep.txt"

@onready var map: Node3D = $ProceduralMap

var _fleet: int = SWEEPER.MAX_FLEET
var _only: String = ""
var _out: String = DEFAULT_OUT


func _ready() -> void:
	print("\n=== gambit fleet sweep (ADR-0275 decs. 13/15/16, #1130) ===")
	print("[NOT_A_TEST] an INSTRUMENT — it measures every cell the synthesizer can build and "
		+ "asserts nothing. dec. 15 keeps it out of the suite permanently.")
	_parse_args()

	# Two frames so `MapComposer._ready` has finished its default build before `change_map`
	# tears it down — the same wait `tools/rollout_corpus.gd` takes for the same reason.
	await get_tree().process_frame
	await get_tree().process_frame

	if not map.change_map(GambitCellSynth.MAP):
		print("[sweep] could not load %s — nothing to sweep" % GambitCellSynth.MAP)
		_quit()
		return
	# ADR-0192 dec. 3's clean fetch — one untyped step at the seam into a typed local.
	var lat = map.lattice
	if lat == null:
		print("[sweep] %s has no lattice — nothing to sweep" % GambitCellSynth.MAP)
		_quit()
		return

	var df := DistanceFieldGenerator.new()
	df.generate(lat, SWEEPER.DISTANCE_FIELD_JUMP)

	# The board is BUILT, not loaded, so it is stated: two runs that disagree about the
	# terrain swept two different boards, and the cell names alone cannot tell them apart.
	print("[sweep] adapter: %s" % RenderingServer.get_video_adapter_name())
	print("[sweep] board %s, actor at (%d,%d), Manhattan max %d, CARDINAL max %d" % [
		GambitCellSynth.MAP, GambitCellSynth.ORIGIN_X, GambitCellSynth.ORIGIN_Z,
		GambitCellSynth.MAX_SEPARATION, GambitCellSynth.MAX_CARDINAL])

	var cells := GambitCellSynth.catalogue()
	var total := cells.size()
	if _only != "":
		var kept: Array = []
		for c in cells:
			if String(c["name"]).to_lower().contains(_only.to_lower()):
				kept.append(c)
		cells = kept
		# A filter is a CAP, and dec. 16's "no silent caps" clause covers it: a filtered run
		# that printed the same summary as a whole one would read as "covered everything".
		print("[sweep] ⚠️ FILTERED by only=%s — %d of %d cells swept, %d NOT MEASURED" % [
			_only, cells.size(), total, total - cells.size()])

	var t0 := Time.get_ticks_usec()
	var report: Dictionary = SWEEPER.new(lat, df).run(cells, {"fleet": _fleet})
	var wall_ms := float(Time.get_ticks_usec() - t0) / 1000.0

	var text := _format(report, wall_ms)
	print(text)
	_write(text)
	_quit()


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts: PackedStringArray = arg.split("=", true, 1)
		if parts.size() != 2:
			continue
		match parts[0].lstrip("-"):
			"fleet": _fleet = int(parts[1])
			"only": _only = parts[1]
			"out": _out = parts[1]


## The report, rendered. Every row is printed — the passes too, and the refusals in the list
## rather than filtered out of it, because dec. 9 makes the refusal count the product and a
## summary that hid them would be hiding it.
func _format(report: Dictionary, wall_ms: float) -> String:
	var out: Array = []
	out.append("\n--- gambit fleet sweep ---")
	if not bool(report.get("layout_ok", false)):
		out.append("  🔴 THE VERDICT LAYOUT DID NOT LOAD — the sweep declined to run rather "
			+ "than decode every cell against a layout the kernel does not have.")
		for c in report.get("layout_checks", []):
			out.append("     %s %s" % ["ok  " if bool(c["ok"]) else "FAIL", c["what"]])
		return "\n".join(out)

	for r in report["rows"]:
		match String(r["outcome"]):
			"PASS":
				out.append("  PASS     %-52s tick %-4d  %d field-set(s) held" % [
					r["name"], int(r["latched_tick"]), int(r["held"])])
			"FAIL":
				out.append("  FAIL     %-52s tick %-4d" % [r["name"], int(r["latched_tick"])])
				for p in r["problems"]:
					out.append("       %s" % p)
			"BLIND":
				out.append("  BLIND    %-52s %s" % [r["name"], r["note"]])
			"REFUSED":
				out.append("  REFUSED  %-52s %s" % [r["name"], r["note"]])
			_:
				out.append("  %-8s %-52s %s" % [r["outcome"], r["name"], r["note"]])

	for i in range(report["batches"].size()):
		var b: Dictionary = report["batches"][i]
		if bool(b.get("failed_init", false)):
			out.append("\n  batch %d: FAILED TO INITIALIZE" % i)
			continue
		out.append("\n  batch %d: %d battles x %d unit slots, horizon %d ticks, STOPPED at %d"
			% [i, int(b["seated"]), int(b["width"]), int(b["horizon"]), int(b["stopped_at"])])
		# dec. 12's bimodal spread, printed rather than averaged: a batch holding 30-tick and
		# 450-tick cells has no meaningful mean, and the mean is what would hide it.
		out.append("    tick budgets in this batch: %s" % str(b["budgets"]))
		# The control on the latch. Every cell here latches on tick 1, and a latch that fired
		# on the sweep's own seating would look exactly the same — so the buffer is read once
		# before the first tick and this is what it said.
		if int(b["pre_step_walked"]) == 0:
			out.append("    control: 0 of %d actors had a verdict BEFORE the first tick, so "
				% int(b["seated"]) + "the latch is reading the kernel and not its own seating")
		else:
			out.append("    🔴 CONTROL FAILED: %d of %d actors carried a verdict BEFORE any "
				% [int(b["pre_step_walked"]), int(b["seated"])]
				+ "tick ran. The latch is firing on residue and every row above is "
				+ "unattributable — do not read this sweep.")
		if int(b["unlatched"]) > 0:
			out.append("    ⚠️ %d cell(s) never evaluated inside the horizon — see BLIND above"
				% int(b["unlatched"]))

	var cost: Dictionary = report.get("cost", {})
	var ticks: int = int(cost.get("ticks", 0))
	if ticks > 0:
		# The measurement behind the sweeper's claim that bucketing by tick budget would buy
		# nothing. Quoted from the run, never from the docstring.
		out.append("\n  per tick over %d ticks: submit %.1f us, read %.1f us, scan %.1f us" % [
			ticks, float(cost["submit_us"]) / ticks, float(cost["read_us"]) / ticks,
			float(cost["scan_us"]) / ticks])
	out.append("  wall clock: %.0f ms for the whole sweep, in ONE RenderingDevice" % wall_ms)
	out.append("\n  %d cells: %d scored (%d PASS, %d FAIL), %d blind, %d refused, %d dropped"
		% [int(report["cells"]), int(report["scored"]), int(report["passed"]),
			int(report["failed"]), int(report["blind"]), int(report["refused"]),
			int(report["dropped"])])
	if int(report["failed"]) > 0:
		out.append("  A cell whose prediction misses is a FINDING about one of three things: "
			+ "the kernel, the straddle row, or the board. It is never evidence the cell "
			+ "should be nudged until it passes (dec. 10).")
	return "\n".join(out)


func _write(text: String) -> void:
	var dir_abs := ProjectSettings.globalize_path(_out.get_base_dir() + "/")
	DirAccess.make_dir_recursive_absolute(dir_abs)
	var path := ProjectSettings.globalize_path(_out)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("[sweep] could not open %s for writing" % path)
		return
	f.store_line(text)
	f.close()
	print("[sweep] report written to %s (gitignored — dec. 16)" % path)


func _quit() -> void:
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0)
