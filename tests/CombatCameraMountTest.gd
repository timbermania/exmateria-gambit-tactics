extends Node
## ADR-0204 dec. 5's oracle: the mount-point move, COUNTED.
##
## 🔴 A GREEN SUITE IS NOT EVIDENCE FOR THIS MOVE, and that is the entire reason this file
## exists. `assets/scenes/CombatCamera.tscn` took over from
## `addons/exmateria_battlefield/camera/PlayerCamera.tscn` in 107 consumer scenes, and
## **104 of the 107 never mention `CombatUI` at all** — they inherited it from the addon's
## scene and now inherit it from the host's. A consumer the swap MISSED keeps working today
## (it still gets the UI from the addon) and would only fail once the addon's two lines go;
## a consumer where the node fails to arrive gets a null `combat_ui`, and
## `GPUCombatTestBase.gd:37` binds that with `$` rather than `get_node_or_null`, so the
## failure is a pushed error and a null field, not a crash. **65 of the 76** tests that
## inherit the binding never dereference it. They pass either way.
##
## 🔴 AND A SCOPED RUN IS STRUCTURALLY BLIND HERE. `closure.py` walks static edges, and 104
## of the 107 have none to any changed line — `scoped_tests.py` sees three. So neither of
## the two instruments this repo normally trusts to bound a change can see this one. What is
## left is the mechanical invariant, asserted directly:
##
##   1. every scene that instanced the addon camera now instances `CombatCamera.tscn`   107
##   2. `<consumer>/FocusPoint/Camera/CombatUI` resolves NON-NULL, instantiated, per scene
##
## 🔴 A THIRD ARM — "scenes still instancing the addon camera directly, 0" — WAS DELETED BY
## ADR-0207 dec. 7. When this file was written, nothing else asked that question. ADR-0205
## then built criterion 4, which asks it at target 0 across `.gd` AND `.tscn` and would fail
## an unlisted namer outright; the arm became a second copy. It was not free: holding the
## addon path as a constant to ask it made THIS FILE a criterion-4 site — the last
## undeclared namer of `camera/PlayerCamera.tscn` on the whole register. ADR-0207 dec. 4 hit
## the same wall writing `ProceduralMapMountTest` and deleted the same arm before shipping
## it. A test that manufactures the reach it forbids buys a duplicate witness at the price
## of a permanent burn-down row.
##
## Arm 2 is the one that cannot be faked by a text edit: it builds each consumer's node tree
## and looks the node up. `instantiate()` does not enter the tree, so no `_ready` runs and no
## GPU work happens — this is cheap, and it is the only thing that answers *did the node
## actually arrive*.
##
## ⚠️ ARM 1's COUNT IS PINNED, deliberately. A swap that missed a file would leave 106 and a
## new scene added later without the mount leaves 108 — both are findings, and a `>= 1` here
## would report neither. If you add or delete a scene that instances the camera, update
## `EXPECTED_CONSUMERS` in the same commit and say why.

const HOST_CAMERA: String = "res://assets/scenes/CombatCamera.tscn"
const UI_SUBPATH: String = "FocusPoint/Camera/CombatUI"
## 107 -> 108 (ADR-0224 PR B): `tests/GPUBridgeDescentTest.tscn` is a new consumer.
## It is the only `GPUCombatTestBase` scene that runs on a REAL exported map rather
## than the flat procedural arena — the arena has one level and cannot express the
## defect ADR-0224 fixes — and it instances the host camera for the same reason every
## other one does: the base binds `combat_ui` at
## `$PlayerCamera/FocusPoint/Camera/CombatUI`.
## 108 -> 109 (W1): `tests/GPUSnapshotUnionTest.tscn` is a new consumer. It replays a
## seeded battle with every NON-union field of the lean per-frame snapshot poisoned,
## which is the runtime half of what keeps `GPUCombatPacker.SNAPSHOT_HOT_UNION`
## honest, so it is a `GPUArena`-derived scene and instances the host camera like
## every other one.
## 109 -> 110 (chunky-battles fix): `tests/GPUVisualBridgeInterpolationTest.tscn` is
## a new consumer. It is the BEHAVIOUR half of the snapshot-union defence — the arm
## that catches a missing union field whose only job is to GATE a branch, which the
## poison arm above structurally cannot see because such a field is compared rather
## than propagated. It is a `GPUArena`-derived scene and instances the host camera
## like every other one.
## 110 -> 112 (the GambitBattle branch, #888/#889/#890 merged with `main`): THREE
## new consumers across three tickets, none of which bumped this —
## `GPUBattleSnapshotTest` (#888), `GPUTurnMeterTest` (#889) and
## `GPURolloutBudgetBench` (#890). One went away: `tests/GPUCallbackE317Test.tscn`
## was DELETED (#533 arm 1). 110 + 3 - 1 = 112.
##
## `TurnDirectorTest` (#891) is deliberately NOT in that list — it mounts a bare
## `CombatLoop` with no host scene, so it carries no combat camera. It is the one
## scene on this branch that adds to the procedural-map ratchet and not this one.
##
## 112 -> 114 (#892, the GambitBattle host scene): the same TWO consumers that moved
## the procedural-map ratchet — `assets/scenes/GambitBattle.tscn` and
## `tests/GambitBattleTest.tscn`. Unlike `TurnDirectorTest`, these ARE hosts: the
## gambit host mounts the production camera because the deployment cursor and the
## cinematic focus beat both need one.
##
## ⚠️ Counts a FILESYSTEM walk of `res://`, not tracked files. Measure, do not
## derive.
##
## 114 → 115 (#941): `tests/GambitDeploymentPickerTest.tscn`. The picker mounts the Formation
## screen UNDER this camera (`mount_over_map` is camera-child), so its rig needs the real one.
## 115 → 116 (#895): `tests/GPURolloutHarnessTest.tscn`, the rollout harness's rig,
## copying `GPURolloutBudgetBench.tscn`'s scene shape — map plus this camera. The rig
## renders nothing and asserts against buffers, so the camera is inherited convention
## rather than a need; it is counted here because the walk counts what the file DOES.
## 116 → 117 (#896): `tools/rollout_corpus.tscn`, the value function's corpus generator,
## copying the same scene shape for the same inherited-convention reason. Under `tools/`
## rather than `tests/`, which this arm does not care about — it walks `res://`.
## 117 → 118 (#1007): `tests/GambitSurfaceTest.tscn`, the gambit surface's rig. Same reason
## `GambitDeploymentPickerTest` is on this list and not merely inheriting a shape: the surface
## is mounted by the map-hosted Formation screen, which is a CAMERA CHILD (`mount_over_map`),
## so the rig needs the real camera or the screen has nothing to hang off.
## 118 → 117 (#942): `tests/StrategyPhaseTest.tscn` DELETED. ADR-0258 retired the deployment
## march and the rig went with it; it instanced this camera beside a `ProceduralMap`, the shape
## every host-ish rig here copies. THE FIRST DECREMENT THIS COUNT HAS TAKEN — every prior line
## is a bump, so a falling number is exactly the direction this pin exists to make somebody
## explain. ⚠️ The arithmetic composes with #1007's bump above and was resolved by hand in a
## rebase: 117 +1 (GambitSurfaceTest) −1 (StrategyPhaseTest) = 117, the SAME number the pin
## held before either change, reached by two movements that cancel.
## 117 → 118 (#897): `tests/GPURolloutDriverTest.tscn`, the rollout driver's rig, copying
## the same scene shape for the same inherited-convention reason — it renders nothing.
## 118 → 119 (#0f26d0091, paid late): `tests/PacingKnobsTest.tscn` is a new consumer and
## landed WITHOUT this bump, so this pin was red on trunk before the change that noticed
## it — the one thing the ledger above asks each bump to say. Nothing about the mount
## moved; a rig was added, and its author owed a line here.
## 119 → 120 (#1093, `0874b0157`): `tests/GPUSettleBrakeTest.tscn`, the settle-brake rig.
## It instances this host for the ordinary reason the rigs above do — it needs a battle,
## not a camera — and it is the one CONSUMER the merge of #1093/#1094/#1095/#1097 added.
## MEASURED as attributable rather than assumed: this pin is green at `6106d914b` and red
## at `391a05d5a` in ONE worktree with its own class cache, which is the only comparison
## that can tell a merge from a tree (the other seven reds that merge produced are green
## on both SHAs in that same worktree and belong to the hub's environment, not to it).
## 120 → 122 (#1107, this PR): TWO consumers, and only one of them is this PR's.
## `tests/AttackPeriodTest.tscn` is mine — the levered-attack-period rig, which
## instances this camera beside a `ProceduralMap` for the reason every rig above
## does: it needs a battle, not a camera. The other is
## `tests/GambitVerdictCellsTest.tscn`, landed by main's `3537a65f2` **without its
## bump**, so this pin was already red on trunk before this branch touched it —
## the same "paid late" shape as the 118 → 119 line above, which is why that line
## asks each bump to say so.
## MEASURED, not assumed, exactly as the 119 → 120 line demands: in ONE worktree
## with one class cache, `origin/main` at `91de94819` reports **got 121, want 120**
## and this branch reports **got 122**. So main owns +1 and this PR owns +1, and
## neither number is inferred from a file list.
## 122 → 123 (#1128, this PR): ONE consumer, and it is this PR's alone.
## `assets/scenes/GambitLab.tscn` is the gambit lab's live arm (ADR-0275 dec. 13) — it
## instances this camera beside a `ProceduralMap` for the reason every rig above
## does: it needs a battle, not a camera.
## MEASURED by A/B in ONE worktree with one class cache, which is what the 119 → 120
## line demands and what the 120 → 122 line above had to run to attribute its own: with
## `GambitLab.tscn` moved out of the tree this test reports **5 passed, 0 failed** at
## 122, and with it back it reports **got 123, want 122**. So the whole delta is this
## PR's and NONE of it was owed by main — unlike the two bumps above.
## Its twin moves in the same commit: the lab mounts BOTH hosts, so
## `ProceduralMapMountTest` takes 125 → 126 here.
## 123 → 124 (paid by #1130, owed by #1148): `tests/GPUAOEEffectSideTest.tscn`, which
## arrived on trunk in `8460781eb` and bumped neither pin — so this pin and
## `ProceduralMapMountTest`'s were BOTH red on `db3696310`. NOTHING in this bump belongs to
## the PR paying it: #1130's own new scene (`tools/gambit_fleet_sweep.tscn`) mounts the map
## and no camera, so it moves the twin pin and leaves this one alone. Written here rather
## than left for the next full-suite run because a red pin nobody owns is read as "the merge
## broke it", which is the failure mode the 121 → 122 line on the twin already records.
## MEASURED in ONE worktree with one class cache: main and this branch BOTH report
## **got 124, want 123** — identical, which is what makes the debt main's and not this PR's.
# 124 -> 126, the camera half of the same two scenes. See the twin's note in
# `ProceduralMapMountTest.gd`: `tests/GPUInflictModeTest.tscn` (#1117) is the owed
# one and `tests/GPURetreatStepTest.tscn` (#1103) is this branch's. Both are
# `GPUCombatTestBase` fixtures, which carry the camera and the map alike, so this
# number and its twin move by the same 2.
const EXPECTED_CONSUMERS: int = 126

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	var scenes: Array[String] = _all_scenes()
	_assert(scenes.size() > 200, "the scene walk found something (%d .tscn)" % scenes.size())

	var consumers: Array[String] = []
	for path in scenes:
		if _read(path).contains(HOST_CAMERA) and path != HOST_CAMERA:
			consumers.append(path)

	# --- arm 1 -----------------------------------------------------------------------
	_assert_eq(consumers.size(), EXPECTED_CONSUMERS,
		"scenes instancing the HOST mount `CombatCamera.tscn`")

	# --- arm 2 — the resolutions, COUNTED ---------------------------------------------
	var resolved: int = 0
	var missing: Array[String] = []
	for path in consumers:
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			missing.append("%s (did not load)" % path)
			continue
		var root: Node = packed.instantiate()
		if root == null:
			missing.append("%s (did not instantiate)" % path)
			continue
		var found: bool = false
		for mount in _mounts_in(root):
			if mount.get_node_or_null(UI_SUBPATH) != null:
				found = true
		if found:
			resolved += 1
		else:
			missing.append(path)
		root.free()

	_assert_eq(resolved, consumers.size(),
		"consumers where `<camera>/%s` RESOLVES on an instantiated tree" % UI_SUBPATH)
	for path in missing:
		print("  [x] combat UI did not arrive in: %s" % path)

	# --- arm 2b — the canonical path `GPUCombatTestBase.gd:37` actually binds ----------
	# That line is `$PlayerCamera/FocusPoint/Camera/CombatUI`, a strict `$` lookup: when it
	# misses, the field is null and the error is pushed, not raised. Arm 2 above is
	# name-agnostic on purpose (it finds the mount by `scene_file_path`), so this asserts
	# the one spelling 76 test scenes depend on literally.
	var base_scene: PackedScene = load("res://tests/GPUMeleeCombatTest.tscn") as PackedScene
	_assert(base_scene != null, "GPUMeleeCombatTest.tscn loads — the typical silent inheritor")
	if base_scene != null:
		var root: Node = base_scene.instantiate()
		_assert(root.get_node_or_null("PlayerCamera/" + UI_SUBPATH) != null,
			"`PlayerCamera/%s` resolves — the literal path GPUCombatTestBase.gd:37 binds"
			% UI_SUBPATH)
		root.free()

	print("\n=== CombatCameraMountTest: %d passed, %d failed ===" % [_passed, _failed])
	print("    %d consumer(s) on the host mount, %d resolved"
		% [consumers.size(), resolved])
	if _passed == 0 and _failed == 0:
		print("[FAIL] CombatCameraMountTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] CombatCameraMountTest")
		get_tree().quit(1)
	else:
		print("[PASS] CombatCameraMountTest")
		get_tree().quit(0)


## Every node in `root`'s tree that IS an instance of the host mount scene.
##
## Keyed on `scene_file_path` rather than on the node being called `PlayerCamera`, because
## arm 2's question is "did the node arrive", not "is it spelled the way we expect". Arm 3b
## asks the spelling question separately.
func _mounts_in(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	var queue: Array[Node] = [root]
	while not queue.is_empty():
		var n: Node = queue.pop_back()
		if n.scene_file_path == HOST_CAMERA:
			out.append(n)
		for c in n.get_children():
			queue.append(c)
	return out


func _all_scenes() -> Array[String]:
	var out: Array[String] = []
	var queue: Array[String] = ["res://"]
	while not queue.is_empty():
		var dir_path: String = queue.pop_back()
		var d: DirAccess = DirAccess.open(dir_path)
		if d == null:
			continue
		d.list_dir_begin()
		var name: String = d.get_next()
		while name != "":
			if name.begins_with("."):
				name = d.get_next()
				continue
			var full: String = dir_path.path_join(name)
			if d.current_is_dir():
				queue.append(full)
			elif name.ends_with(".tscn"):
				out.append(full)
			name = d.get_next()
		d.list_dir_end()
	out.sort()
	return out


func _read(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text: String = f.get_as_text()
	f.close()
	return text


func _assert(ok: bool, name: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("  [x] %s" % name)


func _assert_eq(got: int, want: int, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [x] %s — got %d, want %d" % [name, got, want])
