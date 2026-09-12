extends Node
## The pacing knobs are REACHABLE from the gambit host, and the Pacing rows BUILD.
##
## 🔴 A PLAIN BOOT OF `GambitBattle.tscn` IS NOT A CHECK OF THIS. `register_panel()`
## only appends to a list, and `_build_ui` is where a bad row actually throws — so a
## host that registers nothing at all and a host that registers a broken panel print
## the same zero errors. `WorldMapDebugPanelTest` records the same trap for the same
## reason; this is that check for the pacing rows.
##
## The defect it was written against: `GambitBattle` has printed "F3 - debug overlay"
## in its boot banner since it landed while registering NO panels, so F3 opened an
## empty layout and the `pacing.*` knobs — the two that re-time FFT's turn-based
## balance for continuous combat — were unreachable in the one mode that needs them
## live. Shipping the knobs into `SimulationDebugPanel` was not the same thing as
## shipping them where they could be turned.
##
## Two arms, because either alone passes on a broken tree:
##   1. SOURCE — `GambitBattle` reaches the catalogue asking for the playback row, the
##      catalogue builds and registers the Simulation panel, and the host takes it back out.
##      A behavioural arm can't see this without booting a scenario (ROM assets, GPU).
##      Spans two files since ADR-0263 moved the mount out of the host.
##   2. BUILD  — the panel's `_build_ui` really produces the Pacing rows. Walked by
##      LABEL TEXT, with a pre-existing row ("Seed:") asserted in the same walk as the
##      positive control: an empty or failed walk would otherwise pass every
##      "row is absent" assertion for free.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/GambitBattlePacingPanelTest.tscn
# test-kind: logic
# seeded-break: delete the `"show_playback_rate": true` opt from GambitBattle's
# CombatPanelCatalog.mount call (arm 1 reds), or delete a Pacing row's TuneField.add from
# SimulationDebugPanel._build_ui (arm 2 reds).

const HOST_SRC := "res://src/scenes/GambitBattle.gd"
## The mount moved out of the host and into the shared catalogue (ADR-0263), so the wiring
## this test guards now spans TWO files: the host must ask for the panel, and the catalogue
## must build it. Asserting only the host would leave the construction unguarded, and
## asserting only the catalogue would stop checking that THIS host reaches it — which is the
## exact defect the test was written for.
const CATALOG_SRC := "res://src/debug/CombatPanelCatalog.gd"
## The Simulation panel itself is built by the mount ANY host shares — it needs no subject,
## so keeping it in a combat-only file was what made a ticked "Simulation" box do nothing on
## every screen that is not a combat host. The pacing rows still arrive through
## `CombatPanelCatalog.mount`, which passes the host's opts straight through.
const UNIVERSAL_SRC := "res://src/debug/UniversalDebugPanels.gd"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_arm_source()
	_arm_build()

	print("\n=== Gambit pacing panel: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] %d of %d checks failed" % [_failed, _passed + _failed])
	else:
		print("[PASS] GambitBattle registers the Simulation panel and its Pacing rows build")
	# A FRAME, not a duration (charter C14).
	await get_tree().process_frame
	get_tree().quit(0)


## Arm 1 — the host's wiring, read off its source. The registration happens inside a
## `_ready` that needs a scenario, a map and a GPU device, so this is the arm that can
## run at all; arm 2 is what proves the panel it names is not broken.
func _arm_source() -> void:
	var src := FileAccess.get_file_as_string(HOST_SRC)
	_check(src != "", "GambitBattle source is readable")
	_check(src.contains("_setup_debug_panels()"),
		"GambitBattle calls _setup_debug_panels()")
	_check(src.contains("CombatPanelCatalog.mount("),
		"GambitBattle mounts the shared panel catalogue")
	# This host mounts a TurnDirector, so it is one of the scenes that may show the
	# between-turn playback rate. It is now an opt passed to the catalogue, not a field the
	# host sets — the catalogue applies it before setup(), which is what builds the rows.
	_check(src.contains("\"show_playback_rate\": true"),
		"GambitBattle declares its director so the playback row shows")
	# The overlay is an autoload and outlives the scene, so a panel left registered
	# after a reload is a view bound to a freed host. Teardown stayed with the host.
	_check(src.contains("DebugOverlay.unregister_panel"),
		"GambitBattle unregisters on teardown")

	var cat := FileAccess.get_file_as_string(CATALOG_SRC)
	_check(cat != "", "CombatPanelCatalog source is readable")
	# The catalogue no longer builds this panel itself; it delegates the whole
	# subject-free set. Assert the DELEGATION, or the chain from the host's opt to the
	# panel's rows can break in the middle with both ends still looking right.
	_check(cat.contains("UniversalDebugPanels.mount(host, into, opts)"),
		"the catalogue delegates the universal set, opts and all")

	var uni := FileAccess.get_file_as_string(UNIVERSAL_SRC)
	_check(uni != "", "UniversalDebugPanels source is readable")
	_check(uni.contains("SimulationDebugPanel.new()"),
		"the universal mount constructs the Simulation panel")
	_check(uni.contains("DebugOverlay.register_panel(simulation_panel"),
		"the universal mount registers it into the overlay")
	# ADR-0151's widened marker: `check_debug_panel_tunables.py` reads panel identity off a
	# literal `var X = ClassName.new()` paired with `register_panel(X`. A loop over a preload
	# table satisfies neither half and deletes every panel from the guard SILENTLY. Assert the
	# shape here too, so the next refactor to "tidy up" the repetition reds a test rather than
	# quietly blinding the instrument.
	_check(uni.contains("simulation_panel.show_playback_rate = bool(opts."),
		"the universal mount applies the host's playback-rate opt before setup()")


## Arm 2 — the panel really builds. `setup()` runs `_build_ui`, which is where a bad
## slug, a missing owner or a renamed helper throws.
func _arm_build() -> void:
	var panel := SimulationDebugPanel.new()
	add_child(panel)
	panel.setup()

	var labels := _label_texts(panel)

	# POSITIVE CONTROL FIRST. A walk that found nothing would pass every absence
	# assertion below, so a row that predates this work has to be in the same list.
	_check(labels.has("Seed:"),
		"the walk sees the panel's pre-existing rows (%d labels)" % labels.size())

	_check(labels.has("Pacing"), "Pacing section is built")
	_check(labels.has("Move time"), "the move_time_scale row is built")
	_check(labels.has("Damage"), "the damage_scale row is built")

	# The knobs' owner binds the slugs; the panel is a pure VIEW of them (ADR-0068 R1).
	# A row whose owner never booted renders a placeholder instead of a control, which
	# is the failure this catches — the row would still be "present" by label.
	_check(not labels.has("(unregistered — owner not booted)"),
		"no Pacing row fell back to the unregistered placeholder")

	# BOTH DIRECTIONS, because a flag that is ignored and a flag that is always on look
	# identical from the "on" side alone. Default OFF: a scene running a bare CombatLoop
	# has no director for the between-turn rate to scale, and the knob would scrub a
	# static var nothing reads — an ADR-0068 R8 dead scrub.
	#
	# `Tune.is_registered` was the first gate here and it is a PREDICATE THAT CANNOT
	# FAIL: naming the slug in the panel's source class-loads TurnDirector, whose
	# `_static_init` binds it, so the check was true in every scene. This arm is what
	# would have caught that.
	_check(not labels.has("Playback"),
		"playback row is ABSENT by default (no director mounted)")

	panel.queue_free()

	var director_panel := SimulationDebugPanel.new()
	add_child(director_panel)
	director_panel.show_playback_rate = true
	director_panel.setup()
	var director_labels := _label_texts(director_panel)
	_check(director_labels.has("Playback"),
		"playback row is PRESENT when the host declares a director")
	_check(director_labels.has("Damage"),
		"the flag adds a row rather than replacing the panel (%d labels)" % director_labels.size())
	director_panel.queue_free()


## Every Label's text under `node`, recursively. Label text is the only handle a row
## exposes that survives the control type — a TuneField row builds a SpinBox, a
## CheckBox or an OptionButton depending on the bound value's type.
func _label_texts(node: Node) -> Array[String]:
	var out: Array[String] = []
	for child in node.get_children():
		if child is Label:
			out.append((child as Label).text)
		out.append_array(_label_texts(child))
	return out


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
		print("  ok   %s" % what)
	else:
		_failed += 1
		print("  BAD  %s" % what)
