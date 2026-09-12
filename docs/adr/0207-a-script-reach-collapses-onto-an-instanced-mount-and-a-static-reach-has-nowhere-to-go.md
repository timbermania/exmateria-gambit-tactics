# A script reach collapses onto an instanced mount, and a static reach has nowhere to go

115 of criterion 4's 137 sites named one target, `assembly/MapComposer.gd`. 109 of those 115 are
a `.tscn` line, and **a `.tscn` `ext_resource` names a path or a `uid`, never a `class_name`** —
so the mechanism that closed criterion 1 (drop the published symbol, reach through a port:
[ADR-0206](0206-the-cursor-ships-as-a-rig-and-two-implementation-names-lose-their-class-name.md))
is not merely expensive here, it is structurally unreachable for 109 of them. A scene population
is answerable only by a scene. The register reads **137 sites / 131 files → 16 sites / 18 files,
2 declared**, and the enforcing arm is still not a pass: criterion 4's target is 0.

Status: accepted (2026-08-29). Loop **pass 13** of extraction #3, on map
[#560](https://github.com/timbermania/fft-monorepo/issues/560). Takes the work
[ADR-0205](0205-a-path-reach-is-the-same-axis-as-a-type-reach.md) dec. 7 declined to price and
handed on. Prices — and **partly rejects** —
[ADR-0204](0204-the-mount-point-is-an-inherited-scene-because-the-addon-supplies-the-ui-to-a-hundred-and-seven.md)'s
inherited-scene mechanism for this population. Finishes the camera residue that ADR-0204's
pass left behind — see dec. 7. Does
**not** close criterion 4 — 16 sites remain, every one owned by a live pass.

**Axis B is unchanged and CLOSED**: `check_addon_install` reads 0 sites / 0 rows. The battlefield
system is **installable**; it is **not isolated**. ADR-0202 dec. 1 forbids reporting either as
the other, so both numbers appear here and in every report of this pass.

## Context

### The population, measured

    115  assembly/MapComposer.gd
         109  .tscn   ext_resource type="Script" + [node name="ProceduralMap" type="Node3D"] + script =
           5  .gd     preload(…)/load(…) then .new()
           1  .gd     a DEAD const — declared, read nowhere

Every one of the 109 `.tscn` sites is the **same four lines**, byte-identical modulo the
`ext_resource` id and (in 3 files) an `auto_build_on_ready` override. The host was not
configuring 109 different composers; it was re-declaring one, 109 times.

### 🔴 Why ADR-0206's port does not transfer, and why ADR-0204's inheritance only half does

ADR-0206 closed criterion 1 by deleting a `class_name` and routing the host through a published
port. That works because a `.gd` reach names a **symbol**. A `.tscn` reach names a **resource**;
there is no symbol in the line to unpublish. Deleting `MapComposer`'s `class_name` would move 6
sites and leave 109 exactly where they are — which is ADR-0206 dec. 1's own correction restated
from the other end: dropping a `class_name` does not delete a reach, it forces it into the path
spelling. Criterion 4 is where that spelling lands.

ADR-0204 is the right shape and the wrong half. Its mount is *host-owned indirection*: one host
file names the addon, and N host consumers name the host file. That half transfers exactly. Its
other half — **inheritance** — was chosen there for a stated reason: `CombatCamera.tscn` adds the
host's `CombatUI` as a child of the addon's camera rig, and inheriting kept every node path
byte-identical for 107 consumers. `MapComposer.gd` is a bare script on a bare `Node3D`. Nothing
adds a child, and the node has no internal structure to preserve paths into. Inheriting a
one-node scene from a one-node scene buys nothing and costs a second file.

### The gain nobody asked for, and the thing that had to be checked

`assets/scenes/ProgressionTester.tscn` carries `uid://drwmkkqfo2psl`, which **no file in the tree
owns** — a dangling uid that Godot resolves by falling back to `path=`. That is why the mount's
109 consumers name it by `path=` with no `uid=`: 589 of 835 `gd_scene` headers in this tree
already have none, and a uid that can dangle is a second thing to keep correct. `godot --path .
--import` is clean, rc 0.

An instanced node differs from a scripted node in exactly one observable this tree reads:
`scene_file_path` goes from `""` to the mount's path. That is a gain — it is what makes arrival
checkable at all (dec. 4) — and no host code branched on it being empty.

## Decisions

**1. `assets/scenes/ProceduralMap.tscn` is the host's map-composer mount, and criterion 4's
second `DECLARED_MOUNTS` entry.** A host-owned scene whose root node is the composer: same name
(`ProceduralMap`), same type (`Node3D`), same script, same place in each consumer's tree, same
exported defaults. The 109 host scenes instance it; the 5 live `.gd` sites `preload` it and
`instantiate()`; the dead const is deleted. 115 direct consumers collapse to 1. The mount carries
a comment header stating why it exists, so the next reader does not price the port again.

**2. The mount is an INSTANCE, not an inherited scene — ADR-0204's mechanism transfers by its
indirection half only.** ADR-0204 dec. 1 is not generalised to *mounts are inherited scenes*. It
is read as *a mount is one host file the consumers name instead of the addon*, with the
inheritance chosen there on facts that do not hold here: a host child to add, and node paths to
preserve. Where a mount's root is the whole of it, a plain instance is the mount. Stating this
matters because the cheap misreading — inherit by default — would have added a file and a
`base` edge per mount forever.

**3. A STATIC reach has no mount, and neither criterion has an answer for it today.**
`tests/ScenarioCommitPaletteTest.gd` called `MapComposer.bake_field_tint(...)` — a static method,
where a `PackedScene` hands out a node rather than a script. Two ways out were rejected. Naming
the type (`MapComposer.bake_field_tint`) is a **criterion-1** site, and `MapComposer` is on
`check_lattice_publish`'s `FORBIDDEN` list: that moves debt between registers instead of paying
it. Re-declaring the script path beside the mount re-creates the site the mount deleted. The
call goes through a throwaway instance (`instantiate()`, call, `free()`, documented at the call
site) and **the remaining static reach stays on the burn-down, unscheduled, owned by this
decision** — 1 row. A static entry point on an addon type is an unsolved shape, not a solved one,
and the register says so rather than hiding it.

🔴 **CORRECTED IN PART by [ADR-0208](0208-a-published-name-pays-a-path-reach-and-the-cameras-static-reach-was-a-class-load.md)
dec. 1.** This ruling is right about the composer, whose `bake_field_tint(...)` is a real call and
does need the symbol — and wrong about the camera row below, which was never a static call at all.
`CameraFeelDebugPanel` names no script; the `preload` was forcing a **class LOAD** whose
`_static_init` binds the slugs, and the explicit `register_tunables()` call was measured to be a
no-op. A mount is reachable by being **loaded**, not only by being instanced, so the camera row is
paid by the already-declared `CombatCamera.tscn` with no `instantiate()`. ADR-0208 dec. 2 also
narrows this decision's second sentence: `FORBIDDEN` membership says which register reports the
debt, not whether a re-spelling paid it — the rule is that a **published** name pays and an
unpublished one does not.

**4. The register cannot see whether the mount ARRIVES, so a test does — and the arm that would
have proved it twice was DELETED, not declared.** `tests/ProceduralMapMountTest.gd` is the
arrival oracle, in two arms: arm 1 pins the consumer count at 109; arm 2 instantiates every
consumer and asserts a node whose `scene_file_path` is the mount answers `change_map()`.
Direction-tested both ways — dropping the mount's `script =` line gives **0 of 109 carrying the
composer, [FAIL], with the register still green**; reverting one consumer gives **108, [FAIL]**.
This is the ADR-0192 dec. 1 pairing: the register proves nobody names the addon, the oracle
proves the thing they name instead still works.

🔴 It was first written with a **third** arm asserting *0 scenes still name the addon script* —
which required the test to spell the addon path, making the test itself a criterion-4 site. The
register caught it as UNLISTED. The rule taken from that: **a test that manufactures the reach it
forbids is a defect, and the answer is deletion rather than a declaration.** Criterion 4 already
enforces exactly that arm, at target 0, across `.gd` and `.tscn`; declaring it would have bought
a permanent exemption for a duplicate instrument.

**5. The cursor's 7 remaining path reaches rule TO a mount, in ADR-0204's inherited form — next
pass.** They were owned by *the pass that closes criterion 1*, which finished in #708; an owner
naming a completed pass is a register defect whichever way the rows are ruled, so they are
re-owned here. `cursor/TileCursor.tscn` has internal structure and host scenes author
`$TileCursor` into it (ADR-0206 dec. 2 deliberately left that authored), so unlike the composer's
case in dec. 2 the inheritance half of ADR-0204 does apply. 7 rows, owner *ADR-0207 dec. 5 — the cursor mount*.

**6. The three cursor IMPLEMENTATION reaches move into the addon under ADR-0194 — not to a
mount.** `CursorPanelTuneFieldTest` and `TileCursorBobTest` drive `cursor/TileCursor.gd` and
`cursor/TileCursorBob.gd`; `CursorClutPreviewViewer.tscn` names
`cursor/cursor_clut_preview.gdshader`. A mount is the wrong answer for a test of the addon's own
internals — ADR-0194's rule is that such a test belongs in `addons/<addon>/tests/`, where naming
the addon is not a reach at all. 3 rows, owner *ADR-0207 dec. 6*.

> **Corrected by [ADR-0209](0209-one-ruling-over-three-rows-that-needed-three-and-a-file-can-be-ruled-back.md)
> on two of the three rows.** The shared premise — *a test of the addon's own internals* — was
> measured and holds only for `TileCursorBobTest`, which moved as ruled.
> `CursorPanelTuneFieldTest`'s subject is the HOST's `src/debug/CursorDebugPanel.gd` and it drives
> the `Tune` autoload, so it is a host test with one addon fixture line; its reach was **deleted**
> once ADR-0208 dec. 1 showed the load it forced is one the subject already forces.
> `CursorClutPreviewViewer.tscn` is not a test at all — it prints `[NOT_A_TEST]` and is on no list
> — and needs two host textures plus a host JSON; the shader it names has one consumer in the
> whole tree and zero addon users, and the manifest records it entering the addon by DIRECTORY, so
> the **shader** was returned to the host instead. dec. 5 is unaffected and was built as written.

**7. Five tests built the addon camera directly when a host mount already existed, and the sixth
namer was an oracle's own arm.** The five are swapped to `assets/scenes/CombatCamera.tscn` —
ADR-0204's mount, live since pass 11. `CombatCameraMountTest.gd` carried the same duplicate arm
dec. 4 deletes, spelling `camera/PlayerCamera.tscn` to assert nobody else does; it and its
`ADDON_CAMERA`/`BASE_DECLARER` consts are deleted, arms renumbered, 5 passed / 0 failed, 107
consumers resolved. Together these pay the register's last **undeclared** namers of an
already-declared mount: both declared mounts now report **0**, where `CombatCamera.tscn` read 6
at the start of this pass. This is not new machinery — it is ADR-0204's residue, which its own
pass left as 7 rows. The seventh is dec. 3's static shape in camera form and stays on the
burn-down as 1 row, unscheduled — **paid one pass later by ADR-0208 dec. 1, which measured that it
was a class-load reach and not a static call.**

## Consequences

- **Criterion 4: 137 sites / 131 files → 16 sites / 18 files, 2 declared.** 121 rows deleted.
  `✅ resource-path register OK`, rc 0, no stale rows, **every remaining owner names a live
  pass**. Still not a pass on criterion 4 — target is 0.
- **Axis B unchanged: `check_addon_install` 0 / 0.** All five registers rc 0. The system is
  installable and not isolated; that has not moved this pass.
- Criterion 1 stays 0 / 0 — dec. 3 is the reason it did not go up. The static shape was the one
  temptation to launder criterion-4 debt into criterion-1 debt, and it was declined on record.
- **Two declared mounts is the shape going forward, and `DECLARED_MOUNTS` is REPORTED, not
  enforced** (ADR-0205 dec. 3). Arm 2's per-target undeclared-namer count is what keeps a mount
  from silently acquiring competitors; both mounts read 0 today, where `CombatCamera.tscn` read 6
  at the start of this pass.
- 🔴 **The register was not modified in the same commit as the population** (ADR-0192 dec. 1, and
  the handoff's explicit constraint). Order: move the 115, then delete their rows and declare the
  mount, then the camera swaps, then re-own the cursor rows. A scanner edited alongside its
  population cannot distinguish a fix from a blindness.
- `test_check_lattice_scene.py`'s 16 seed tests pass unchanged through a 138 → 16 row deletion,
  which half-answers its own docstring prediction that they must still fire on the day the
  population reaches zero. The other half is untested until it does.
- Two `.tscn` in this tree carry a fork-specific `unique_id=NNNN` in the node header
  (`ScenarioPlayer`, `UnitAnimationViewerScene`). A rewrite that does not preserve it is a silent
  loss; the rewrite refused to half-edit them and they were done in a second pass that keeps it.

## Alternatives rejected

- **Unpublish `MapComposer`'s `class_name` and route through a port, as ADR-0206 did for the
  cursor.** Rejected in Context: a `.tscn` `ext_resource` cannot name a `class_name`, so it moves
  6 of 115 sites and 109 stay exactly as they are.
- **Make the mount an inherited scene, following ADR-0204 dec. 1.** Rejected in dec. 2: nothing
  adds a child and the composer node has no internal structure, so inheritance buys nothing and
  costs a file plus a `base` edge.
- **Ship the mount scene from inside the addon.** Rejected: the consumers would then name an
  addon path — the mount would be a criterion-4 site 109 files could point at, which is the
  reach relabelled, not removed. The mount is host-owned by definition.
- **Declare the arrival test's addon-path const in `DECLARED_MOUNTS`.** Rejected in dec. 4: the
  arm duplicated criterion 4's enforcing arm, so declaring it would have bought a permanent
  exemption for a redundant instrument.
- **Re-spell the static `bake_field_tint` reach as a type reference.** Rejected in dec. 3: it is
  a criterion-1 `FORBIDDEN` name, so the site would move between registers rather than be paid.
- **Relabel the 10 orphaned cursor rows onto a generic unscheduled owner.** Rejected: the handoff
  asked for a ruling, and an owner that names no pass fails for the same reason an owner naming a
  finished pass fails. They are ruled in dec. 5 and dec. 6 as two different answers, because they
  are two different shapes.
