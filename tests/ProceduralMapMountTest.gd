extends Node
## ADR-0207 dec. 4's oracle: the map-composer mount move, COUNTED.
##
## 🔴 THE REGISTER CANNOT ANSWER THIS QUESTION, and that is why the file exists.
## `check_lattice_scene.py` reads TEXT. It can say that no host names the addon's
## `assembly/MapComposer.gd` and that `assets/scenes/ProceduralMap.tscn` is the declared
## mount. It cannot say that the node ARRIVES. Delete the mount's `script =` line tomorrow
## and the register stays GREEN — MEASURED, by seeding exactly that: arm 1 held at 22
## sites, rc 0, `✅ resource-path register OK`, and the mount still printed as `live`.
## The mount NAMES the script in its `ext_resource` line whether or not any node carries it. Meanwhile all 109 consumers silently instance a bare
## `Node3D` with no composer on it.
##
## ⚠️ AND THE SUITE IS A DIFFUSE SIGNAL FOR IT. The failure would surface as a scatter of
## GPU-combat reds 14 minutes later, with the cause 109 files away from any of them. This
## asserts the invariant directly, in seconds:
##
##   1. every scene that declared the composer script now instances `ProceduralMap.tscn` 109
##   2. per consumer, an instanced node whose `scene_file_path` IS the mount and which
##      answers `change_map` — i.e. the composer script actually came with it
##
## Arm 2 is the one a text edit cannot fake. `instantiate()` does not enter the tree, so no
## `_ready` runs and no GPU work happens — this is cheap, and it is the only thing that
## answers *did the composer actually arrive*. Both arms were direction-tested by seeding:
## dropping the mount's script line reads **0 of 109 carrying the composer**, and reverting
## one consumer to the old spelling reads **108**.
##
## 🔴 A THIRD ARM WAS WRITTEN, MEASURED, AND DELETED — "no scene still names the addon
## composer itself, 0". It is criterion 4's own question for this target, already enforced
## at target 0 by `check_lattice_scene.py` across `.gd` as well as `.tscn`. Worse, holding
## the addon path as a constant to ask it MADE THIS FILE A CRITERION-4 SITE: the register
## reported `ProceduralMapMountTest.gd:6,37 → assembly/MapComposer.gd [string]` as UNLISTED
## the first time it ran. A test that manufactures the reach it forbids buys a second
## witness at the price of a permanent burn-down row, and the scanner already has an
## independent witness in `tools/test_check_lattice_scene.py`'s 16 seeds. So this file names
## the HOST mount only, and never the addon.
##
## ⚠️ ARM 1's COUNT IS PINNED, on `CombatCameraMountTest`'s precedent and for its reason. A
## swap that missed a file leaves 108 and a new scene added later without the mount leaves
## 110 — both are findings, and a `>= 1` here would report neither. If you add or delete a
## scene that carries a procedural map, update `EXPECTED_CONSUMERS` in the same commit and
## say why.
##
## ⚠️ FIVE `.gd` FILES also name the mount by path and are correct to — `preload(mount)
## .instantiate()` is how a script asks for the same node. Arm 1 walks `.tscn` only, so they
## are outside its count; the register walks `.gd` too and scores them there.
##
## Run: "$GODOT" --path . --quit-after 600 res://tests/ProceduralMapMountTest.tscn

const HOST_MOUNT: String = "res://assets/scenes/ProceduralMap.tscn"
const COMPOSER_METHOD: String = "change_map"
## 109 -> 110 (W1): `tests/GPUSnapshotUnionTest.tscn` is a new consumer — a
## `GPUArena`-derived scene that replays a seeded battle with every non-union field
## of the lean per-frame snapshot poisoned, so it instances the procedural map like
## every other combat scene.
## 110 -> 111 (chunky-battles fix): `tests/GPUVisualBridgeInterpolationTest.tscn` is
## a new consumer — a `GPUArena`-derived scene, so it instances the procedural map
## host the same way every other arena scene does. It asserts that units INTERPOLATE
## between tiles rather than snapping, which is what W1's lean snapshot silently
## broke by omitting `prev_move_pos` / `move_step_id`.
## 111 -> 114 (the GambitBattle branch, #888/#889/#890/#891 merged with `main`):
## FOUR new consumers landed across four tickets and NONE of them bumped this,
## because none ran the full suite — `GPUBattleSnapshotTest` (#888),
## `GPUTurnMeterTest` (#889), `GPURolloutBudgetBench` (#890) and `TurnDirectorTest`
## (#891). One consumer went away in the same branch:
## `tests/GPUCallbackE317Test.tscn` was DELETED (#533 arm 1 — its script was never
## in git at any commit). 111 + 4 - 1 = 114, and that reconciles with the measured
## walk exactly.
##
## 114 -> 116 (#892, the GambitBattle host scene): TWO new consumers, both from this
## one ticket — `assets/scenes/GambitBattle.tscn`, the host itself, and
## `tests/GambitBattleTest.tscn`, its subclass rig. Both are combat scenes and both
## instance the procedural map the way every other one does.
##
## ⚠️ This arm counts a FILESYSTEM walk of `res://`, not tracked files, so `git
## grep` disagrees with it and the runtime number is the only authority. Measure,
## do not derive.
##
## 116 → 117 (#941): `tests/GambitDeploymentPickerTest.tscn`, the deployment picker's rig. It is
## the gambit host's subclass like `GambitBattleTest` and instances the map the same way.
##
## 117 → 118 (W6): `tests/CombatLoopCatchupClampTest.tscn`, the catch-up clamp's rig. It
## stands a bare `CombatLoop` up by hand on `TurnDirectorTest`'s precedent — no host scene,
## no `Unit` nodes — and the map is instanced for the one thing the loop needs from it, a
## `Lattice`.
## 118 → 119 (#895): `tests/GPURolloutHarnessTest.tscn`, the rollout harness's rig. It
## builds its OWN multi-battle `GPUBatchSimulator` rather than a host's, on
## `GPURolloutBudgetBench`'s precedent, and instances the map for the same one thing
## the bench wants from it — a `Lattice` to place units on and build a distance field
## over.
## 119 → 120 (#896): `tools/rollout_corpus.tscn`, the value function's corpus generator.
## Same shape and same reason as the two rows above — its own multi-battle
## `GPUBatchSimulator`, and the map instanced for the `Lattice`. It is under `tools/`
## rather than `tests/` because #896 asks for a script and not a test, which changes
## nothing for this arm: the walk is over `.tscn` files, not over the test list.
## 120 → 121 (#1007): `tests/GambitSurfaceTest.tscn`, the gambit surface's rig. It subclasses
## the real `GambitBattle` host on `GambitDeploymentPickerTest`'s precedent, so it takes that
## rig's scene shape whole — the map is the battlefield the host boots onto, not a fixture the
## rig itself wants.
## 121 → 120 (#942): `tests/StrategyPhaseTest.tscn` DELETED with the deployment march
## (ADR-0258). It instanced the map for a real strategy phase — a `Lattice` AND tiles to place
## onto — not for the bare-`Lattice` reason the rigs above give. THE FIRST DECREMENT THIS COUNT
## HAS TAKEN. ⚠️ Composes with #1007's bump above, resolved by hand in a rebase: 120 +1 −1 = 120,
## the same number the pin held before either change, reached by two movements that cancel.
## 120 → 121 (#897): `tests/GPURolloutDriverTest.tscn`, the rollout driver's rig. Same
## shape and same reason as the three rollout rows above — its own multi-battle
## `GPUBatchSimulator`, and the map instanced for the `Lattice`. The FOURTH row in a row with
## that shape; a fifth is the signal to give the rollout rigs a shared scene rather than to
## write a sixth comment.
## 121 → 122 (#0f26d0091, paid VERY late): `tests/PacingKnobsTest.tscn`. Its author paid
## this exact debt on `CombatCameraMountTest`'s ledger in that same commit — the line is
## still there, worded "a rig was added, and its author owed a line here" — and did not
## pay it here, because that rig instances BOTH hosts and only one pin was red at the time.
## ⚠️ THIS PIN WAS THEREFORE RED ON TRUNK for two days before the merge that surfaced it,
## which is the failure mode the ledger exists to make visible: a stale census reads as
## "the merge broke it" to whoever runs the suite next, and cost a full pre/post A/B here
## to disprove. A bump that names one host should ask what else the new scene mounts.
## 122 → 123 (#1093, `0874b0157`): `tests/GPUSettleBrakeTest.tscn`, the settle-brake rig —
## the same scene that took `CombatCameraMountTest` 119 → 120, and the only consumer the
## merge actually added (MEASURED: the consumer set diffs by exactly this one file across
## `6106d914b`..`391a05d5a`).
## 123 → 125 (#1107, this PR): TWO consumers, and the line above is why this one
## is written at the same time as its twin rather than after it — *"a bump that
## names one host should ask what else the new scene mounts."* Both scenes here
## mount BOTH hosts, so `CombatCameraMountTest` takes 120 → 122 in the same commit.
## `tests/AttackPeriodTest.tscn` is this PR's — the levered-attack-period rig.
## `tests/GambitVerdictCellsTest.tscn` is main's `3537a65f2`, landed without either
## bump, so this pin was red on trunk first, exactly as the 121 → 122 line records
## happening before.
## MEASURED in ONE worktree with one class cache: `origin/main` at `91de94819`
## reports **got 124, want 123**; this branch reports **got 125**. +1 main, +1 here.
## 125 → 126 (#1128, this PR): ONE consumer, this PR's alone, and written at the same
## time as its twin for the standing reason above — *"a bump that names one host should
## ask what else the new scene mounts."* `assets/scenes/GambitLab.tscn` is the gambit lab's
## live arm (ADR-0275 dec. 13) and it mounts BOTH hosts, so `CombatCameraMountTest`
## takes 122 → 123 in this same commit.
## MEASURED by A/B in ONE worktree with one class cache: with `GambitLab.tscn` moved
## out of the tree this test reports **3 passed, 0 failed** at 125; with it back,
## **got 126, want 125**. Nothing here was owed by main — unlike the 123 → 125 bump.
## 126 → 128 (#1130, this PR): TWO movements and only ONE of them is this PR's, which is
## why they are written as two lines rather than one bump.
##   +1 OWED BY MAIN. `tests/GPUAOEEffectSideTest.tscn` arrived on trunk in `8460781eb`
##   (#1148, the AoE effect team gate) and bumped NEITHER pin, so BOTH mount pins were red
##   on `db3696310` before this branch existed. That is the third time this ledger records
##   it happening and the 121 → 122 line already says why it matters: *"a stale census reads
##   as 'the merge broke it' to whoever runs the suite next"*. It did — it cost the full-suite
##   triage this branch was opened alongside a separate attribution pass to rule out three
##   unclaimed tickets. It mounts BOTH hosts, so `CombatCameraMountTest` takes 123 → 124 in
##   this same commit and that bump is ENTIRELY main's, with nothing of this PR's in it.
##   +1 THIS PR's. `tools/gambit_fleet_sweep.tscn` is the gambit lab's fleet arm (ADR-0275
##   dec. 13). It instances the map for the bare-`Lattice` reason the rollout rigs above give
##   — `GPUBatchSimulator.initialize` wants a lattice and a distance field and nothing else —
##   and it mounts NO camera, because it renders nothing. So it moves this pin and not its
##   twin, which is the first row here to move exactly one of the two.
## MEASURED by running both tests in ONE worktree with one class cache: `origin/main` at
## `db3696310` reports **got 127, want 126** here and **got 124, want 123** on the camera;
## this branch reports **got 128** here and **got 124** there — unchanged on the camera,
## which is the arithmetic above proving itself rather than being asserted.
# 128 -> 130, and only ONE of the two is #1103's.
#
# `tests/GPUInflictModeTest.tscn` (#1117, ADR-0299) landed a `GPUCombatTestBase`
# fixture and bumped NEITHER host-mount pin, so `main` has been carrying got-129 /
# want-128 here and got-125 / want-124 on the camera since that merge. It is not
# visible until someone else's scene moves the same number, which is what happened:
# `tests/GPURetreatStepTest.tscn` (#1103, ADR-0301) is the second consumer, and this
# branch is where both get paid. The pin is doing exactly what its docstring says it
# is for -- a swap that missed a file and a scene added without the mount are both
# findings, and this was the first kind.
#
# Every `GPUCombatTestBase` fixture carries BOTH mounts, so the two pins move together
# for this population; the rollout rigs above are the rows that move only one.
const EXPECTED_CONSUMERS: int = 130

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	var scenes: Array[String] = _all_scenes()
	_assert(scenes.size() > 200, "the scene walk found something (%d .tscn)" % scenes.size())

	var consumers: Array[String] = []
	for path in scenes:
		if _read(path).contains(HOST_MOUNT) and path != HOST_MOUNT:
			consumers.append(path)

	# --- arm 1 -------------------------------------------------------------------------
	_assert_eq(consumers.size(), EXPECTED_CONSUMERS,
		"scenes instancing the HOST mount `ProceduralMap.tscn`")

	# --- arm 2 — the arrivals, COUNTED -------------------------------------------------
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
			# The node arriving is not enough — it must carry the composer. A mount whose
			# `script =` line was dropped instantiates a bare Node3D and answers nothing.
			if mount.has_method(COMPOSER_METHOD):
				found = true
		if found:
			resolved += 1
		else:
			missing.append(path)
		root.free()

	_assert_eq(resolved, consumers.size(),
		"consumers where the mount arrives carrying `%s()`" % COMPOSER_METHOD)
	for path in missing:
		print("  [x] composer did not arrive in: %s" % path)

	print("\n=== ProceduralMapMountTest: %d passed, %d failed ===" % [_passed, _failed])
	print("    %d consumer(s) on the host mount, %d carrying the composer"
		% [consumers.size(), resolved])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ProceduralMapMountTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ProceduralMapMountTest")
		get_tree().quit(1)
	else:
		print("[PASS] ProceduralMapMountTest")
		get_tree().quit(0)


## Every node in `root`'s tree that IS an instance of the host mount scene.
##
## Keyed on `scene_file_path` rather than on the node being called `ProceduralMap`, because
## this arm's question is "did the node arrive", not "is it spelled the way we expect".
func _mounts_in(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	var queue: Array[Node] = [root]
	while not queue.is_empty():
		var n: Node = queue.pop_back()
		if n.scene_file_path == HOST_MOUNT:
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
