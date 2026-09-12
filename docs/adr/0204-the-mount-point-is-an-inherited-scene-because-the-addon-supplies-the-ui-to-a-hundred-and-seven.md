# The mount point is an inherited scene, because the addon supplies the UI to a hundred and seven scenes

[ADR-0202](0202-installable-is-the-fork-plus-the-kernel-and-the-port.md) dec. 6 ruled the
`CombatUI.tscn` edge — Class C, the install register's last non-asset row — and named the shape
of the fix: *"The addon exposes the node the UI hangs from; the host instances its own UI into
it."* It did not say which node, or what the host does at the 100-odd call sites, because at
dec. 6's scale the edge looked like two lines in one file.

It is not two lines. This ADR measures it before building it, and the measurement changes the
answer.

Status: accepted (2026-08-28). Loop **pass 11** of extraction #3, on map
[#560](https://github.com/timbermania/fft-monorepo/issues/560), resolving
[#690](https://github.com/timbermania/fft-monorepo/issues/690). Implements — and corrects the
scale of — [ADR-0202](0202-installable-is-the-fork-plus-the-kernel-and-the-port.md) dec. 6.
Sibling to [ADR-0203](0203-an-addon-provides-the-names-it-can-and-injects-the-content-it-cannot.md),
which settles classes D and E; this one settles class C. Does **not** touch ADR-0202 dec. 5
(Class B) or ADR-0164 dec. 4 criterion 1 — see dec. 4.

## Context

### The edge

`addons/exmateria_battlefield/camera/PlayerCamera.tscn` names the host twice:

    :5   [ext_resource type="PackedScene" path="res://assets/scenes/CombatUI.tscn" id="3_combat_ui"]
    :38  [node name="CombatUI" parent="FocusPoint/Camera" instance=ExtResource("3_combat_ui")]

The addon's camera scene **instances the host's entire combat UI**. `PlayerCamera.gd` never
mentions it — the edge is scene-only, which is why no script-reading arm ever saw it.

### 🔴 The count that was being used is the wrong count

The handoff that raised this priced the blast radius at **19 sites**: two in the addon, 14 in
`assets/scenes/GPUArena.tscn` (an `[editable path=…]` plus 13 overrides reaching inside
`CombatUI`), and three script bindings —

    src/scenes/GPUArena.gd:40                const/onready $PlayerCamera/FocusPoint/Camera/CombatUI
    src/scenes/UnitAnimationViewerScene.gd:25  COMBAT_UI_PATH
    tests/GPUCombatTestBase.gd:37             @onready var combat_ui: UICombatManager = $…/CombatUI

That is the count of **sites that name the path**. It is not the count of **scenes that depend
on the node existing**, and those two numbers are three orders of magnitude apart in
consequence:

    scenes instancing addons/exmateria_battlefield/camera/PlayerCamera.tscn   107
    …of those, scenes that mention CombatUI at all                              3
    tests extending GPUCombatTestBase (which binds combat_ui)                  76
    files that dereference combat_ui                                           11

**104 of the 107 inherit the combat UI silently.** `tests/GPUMeleeCombatTest.tscn` is typical —
its whole node list is `ProceduralMap`, `PlayerCamera`, an override of
`PlayerCamera/FocusPoint/Camera`, and `[editable path="PlayerCamera"]`. It has no `CombatUI`
node and never had one. It gets the UI because the addon's scene carries it.

So *delete the two lines* is not a two-line change with a 19-site follow-up. It is a change that
silently empties `combat_ui` in **76 test scenes**, none of which would fail at parse time and
most of which would fail late, differently, and under load — this repo's worst failure class.

### Hosts already reach into the camera's interior

Every consumer that customises the camera already carries `[editable path="PlayerCamera"]` and
overrides `PlayerCamera/FocusPoint/Camera` (`EffectViewer.tscn:28`, `TrapViewer.tscn:23`,
`FireCastRepro.tscn:22`, and the ~90 test scenes). `EffectViewer.tscn:32` goes further and
overrides the inherited `CombatUI` node itself.

This matters for dec. 2: the host↔`FocusPoint/Camera` coupling is **not created by this
decision and is not removed by it**. It exists 100+ times over today.

## Decision

**1. The mount point is a host-owned INHERITED SCENE, not a new node in the addon.**

Add `assets/scenes/CombatCamera.tscn` — a Godot **inherited scene** whose base is
`addons/exmateria_battlefield/camera/PlayerCamera.tscn` — and give it the `CombatUI` instance at
`FocusPoint/Camera`. Then the addon scene drops `:5` and `:38`, and each of the 107 consumers
swaps one `ext_resource` path:

    - path="res://addons/exmateria_battlefield/camera/PlayerCamera.tscn"
    + path="res://assets/scenes/CombatCamera.tscn"

**Every node path in the tree stays byte-identical.** The consumer names its instance
`PlayerCamera` as it does today, so `PlayerCamera/FocusPoint/Camera/CombatUI/ModalLayer/JobPopup`
still resolves. `GPUArena.tscn`'s 13 overrides do not move. `GPUCombatTestBase.gd:37` does not
change. `GPUArena.gd:40` and `UnitAnimationViewerScene.gd:25` do not change.

The install register's Class C row goes to **0** because the addon no longer names
`res://assets/`, and the host gets the UI because the host's own scene puts it there. That is
dec. 6's sentence — *the addon exposes the node the UI hangs from; the host instances its own UI
into it* — with `FocusPoint/Camera` as the node and inheritance as the mechanism.

**2. No new node, and no new name, is added to the addon.**

⚠️ This is where this ADR departs from the obvious reading of dec. 6. A named slot —
`UIMount`, `HUDAnchor`, whatever — is the intuitive spelling of "expose the node the UI hangs
from", and it is the wrong move here for two measured reasons:

  - **It lengthens every path.** `…/Camera/CombatUI/…` becomes `…/Camera/UIMount/CombatUI/…`,
    so the 13 `GPUArena.tscn` overrides, the three script bindings and every future reader move
    — to buy a rename of a node that already exists.
  - **It buys a contract the host has already declined 100 times.** The argument for a named
    mount is that `FocusPoint/Camera` is an incidental internal path the addon could restructure.
    True — and ~90 test scenes plus four host scenes already override exactly that path under
    `[editable path="PlayerCamera"]`. Publishing one child of `Camera` while a hundred consumers
    reach `Camera` itself is not a contract, it is a gesture.

**3. Class C closes on the addon side only, and the decision says so out loud.**

After this the addon names no host path and the register reads 0 for Class C. The host still
depends on the addon's interior structure in 107 scenes. That dependency is **host → addon**,
which is [ADR-0164](0164-the-lattice-ships-as-one-port-and-one-publish-and-tile-never-crosses.md)
dec. 4 criterion 1's axis and not this register's — ADR-0202 dec. 1 forbids reporting either
axis as the other, and a pass that closed Class C and announced "the camera is isolated" would
be doing exactly that.

**4. Criterion 1 is not touched, and the mount-node option is the trap that would touch it.**

ADR-0202 dec. 11 keeps criterion 1 deliberately open under ADR-0196 dec. 8, on the grounds that
*"closing it as a bonus would put one pass's name on two decisions."* A named mount node is a
criterion-1 fix — it converts an incidental structural path into a published one — priced at 17
site edits, taken on a pass whose subject is the other axis. Declining it here is not deferral;
it is dec. 11 being obeyed by the pass most tempted to break it.

**5. The build is verified on the FULL suite, not a scoped run, and the oracle is a count.**

`GPUCombatTestBase.gd:37` is inherited by 76 test scenes. A scoped run derived from the changed
files would follow `closure.py`'s static edges and see the three scripts and the scenes that
name `CombatUI` — **three of the 107**. The 104 that inherit the node silently have no static
edge to the changed line, so the instrument that normally bounds a test run is structurally
blind to this change. Run the full suite (≈17 min at peak cores), and before it, assert the
mechanical invariant directly:

    every scene that instanced PlayerCamera.tscn now instances CombatCamera.tscn   107 → 107
    scenes still instancing the addon scene directly                                    0
    `$PlayerCamera/FocusPoint/Camera/CombatUI` resolves in a booted GPU combat test   non-null

A green full suite alone is not enough: a test whose `combat_ui` went null and which never
dereferences it still passes. 65 of the 76 do not touch it. **Count the resolutions, do not
infer them from green.**

## Prediction

Written before the build, per ADR-0202 dec. 10's practice.

  - `check_addon_install`: Class C **1 row → 0**; register **47/27 → 46 sites / 26 rows**. The
    Class C burn-down entry goes **stale**, and that is what grades the move.
  - Classes B, D and E are **unchanged** — 9, 12 and 5 rows. If any moves, the change reached
    past its subject.
  - `check_lattice_ports` / `_doors` / `_publish`: **untouched**. Publish stays 21/12.
  - The full suite's non-PASS set equals `main`'s known set — the 6 `EffectStudio*`,
    `ScenarioVarWaitValueTest`, `GambitScenarioRunnerTest` — and nothing else. Any GPU combat
    test that newly fails is a `combat_ui` that went null, not a flake, and must not be re-run
    into green.
  - `assets/scenes/EffectViewer.tscn:32`'s override of the inherited `CombatUI` is the one site
    with a real chance of needing a hand edit, because its `index="1"` hint is positional and
    the node now arrives from a different scene layer.

## Consequences

**A host scene now sits between the addon and 107 consumers.** `CombatCamera.tscn` is a new
host-owned file whose only job is to compose two things the host owns the relationship between.
That is a real addition to the host's surface, and it is the price of the addon not owning the
host's UI. It is cheaper than the alternative it replaces: the addon owning `CombatUI.tscn`.

**The 107-scene swap is mechanical and should be scripted, not hand-edited.** One `ext_resource`
path per file, same `uid` bookkeeping problem as any `.tscn` path move. A hand pass over 107
files will miss some, and the ones it misses keep working — they still get the UI from the addon
— until the addon's two lines are deleted, at which point they fail silently. **Delete the
addon's two lines LAST**, and let the "0 scenes still instancing the addon scene directly" count
above be the gate.

**`check_addon_install` cannot see this class of regression.** Its arm reads `res://` literals
out of addon files. It will report Class C green the moment the addon's two lines go, whether or
not any host ever gained the UI. The register grades the addon; the suite grades the tree; and
this ADR's dec. 5 exists because those are different questions.

## Alternatives considered

**A named mount node in the addon (`UIMount`).** The intuitive reading of dec. 6. Rejected in
dec. 2 on two measurements: it lengthens 17 live paths, and it publishes one child of a node
that ~90 consumers already reach past.

**The host parents `CombatUI` directly under `PlayerCamera/FocusPoint/Camera` in each scene.**
Preserves every path, same as the chosen option, and needs no new file — but it requires adding
a node block to **107 scenes** instead of changing a path in 107 scenes, and each block must
carry the transform (`0, 0, -10`) the addon currently supplies. 107 copies of one constant is a
worse tree than one inherited scene holding it once.

**Instance `CombatUI` at runtime from `GPUCombatTestBase._ready()` and `GPUArena.gd`.** Collapses
the edit to ~3 files and was seriously considered. Rejected because `GPUArena.tscn`'s 13
overrides configure children *inside* `CombatUI`, and a runtime instance cannot carry scene
overrides — they would have to be re-expressed as code, turning a declarative 13-line block into
imperative setup in the file this refactor is trying to simplify.

**Leave it and close Class C by re-pathing.** Explicitly refused by ADR-0202 dec. 6: *"Re-pathing
it is not a fix — the addon would still own the UI … the only one where the register going green
by a path edit would be a worse tree."*
