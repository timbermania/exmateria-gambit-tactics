# One ruling over three rows that needed three, and a file can be ruled back

[ADR-0207](0207-a-script-reach-collapses-onto-an-instanced-mount-and-a-static-reach-has-nowhere-to-go.md)
dec. 6 ruled criterion 4's last three cursor rows **as one**: move the test into the addon under
[ADR-0194](0194-a-test-belongs-to-the-addon-it-can-run-without-the-game.md). Measured, that is
right for **one** of the three. The other two are a host test that merely preloaded an addon file,
and a shader that is not a test at all. Each is paid by a different route from
[ADR-0208](0208-a-published-name-pays-a-path-reach-and-the-cameras-static-reach-was-a-class-load.md)
dec. 2's already-ruled menu, so this pass picks three items from a ruled list rather than inventing
a rule. **Criterion 4 reads 10 sites / 12 files → 0.**

Status: accepted (2026-08-29). Loop **pass 15** of extraction #3, on map
[#560](https://github.com/timbermania/fft-monorepo/issues/560). Builds ADR-0207 dec. 5 and
**corrects dec. 6**; applies
[ADR-0192](0192-the-register-goes-first-because-the-port-erases-its-own-baseline.md) dec. 1 three
times and finds its first exception.

**Axis B is unchanged and CLOSED**: `check_addon_install` reads 0 sites / 0 rows. Criterion 4
reaching 0 is **axis A**. The battlefield system is **installable**, and on all four axis-A
criteria no host file now reaches it by path or by an unpublished name.
[ADR-0202](0202-installable-is-the-fork-plus-the-kernel-and-the-port.md) dec. 1 forbids reporting
either axis as the other, so both numbers appear here and in every report of this pass.

## Context

### dec. 6 stated a shared premise and it held for one row

dec. 6's sentence is *"A mount is the wrong answer for a test of the addon's own internals"*. That
is true, and it is the wrong question for two of the three rows, because two of them are not tests
of the addon's own internals. Measured per row:

| row | reaches | host code it needs | verdict |
|---|---|---|---|
| `tests/TileCursorBobTest.gd` | 1 (`preload` of the script under test) | none — its `tile_knife.json` table is tracked **inside** the addon | dec. 6 holds |
| `tests/CursorPanelTuneFieldTest.gd` | 1, plus 2 host `preload`s | `src/debug/CursorDebugPanel.gd`, `src/debug/TuneField.gd`, and the `Tune` autoload | host test |
| `tests/CursorClutPreviewViewer.tscn` | 1 (a `.gdshader`) | two host `.tga`s, and its `.gd` reads a host `.json` | not a test |

The comparison that settles it is dec. 8's own test, one pass earlier: the two overlay tests moved
because each *"held exactly ONE reach — the `preload` of the addon script under test — and touched
no host code at all"*. Only the bob test passes that test. `CursorPanelTuneFieldTest` drives the
`Tune` autoload, which is a host `project.godot` entry an addon cannot register; moving it would
put a test in `addons/` that cannot run in the project the addon claims to be installable in.

### The viewer would have reproduced a defect the rig had already caught

`7d892315c`, one pass ago, fixed a moved addon test that asked `BattlefieldContent` for **host**
content a stranger project does not have. The CLUT viewer names `RANGETILE.tga` and
`RANGETILE.cursor_clut_candidates.palette.tga` and reads a host JSON, so moving it in is that
defect again, by construction. dec. 6's own register entry had already flagged the risk in as many
words — *"An addon-side viewer has no precedent yet — price that before assuming the move is as
cheap as the two tests'"* — and this is the priced answer.

The other direction was measured instead:

    consumers of cursor_clut_preview.gdshader, whole tree   1  (the host viewer)
    addon files that use it                                 0
    how it entered the addon                                source `census` on the move manifest

`source census` is the fact that decides it. The file entered `addons/exmateria_battlefield/` in
[ADR-0184](0184-the-address-lands-and-arm-1s-debt-is-named-rather-than-hidden.md)'s bulk pass by
**directory**, not by a per-file ruling —
[ADR-0144](0144-the-instruments-see-the-shaders-the-assets-and-the-closure.md) had already noted it
as one of the `assets/shaders/` files no `.gd` reads — so putting it back is a reversal of a
mechanical move, not a new judgement about the addon's surface.

### The registers had no vocabulary for a reversal, and three arms called it a defect

`check_move_manifest.py` is set equality: every row's `dst` must be in the addon, and a row must be
in exactly one of its two places. Reversing a single row scored **45 failures**, of which 44 are
the guard's own documented blind spot — a non-empty `at_src` bucket **gates arm 2**, whose premise
is *"while the host copy is still there"*, i.e. during the extraction. One reversed row woke arm 2
in a world it was not written for and it reported every completed move as broken.

## Decisions

**1. Each of dec. 6's three rows is paid by its own route from ADR-0208 dec. 2's menu.** The menu
is already ruled — delete the dependency, use host-owned indirection, or name a name the addon
publishes — and one row per route is the answer, not one route for three rows. `TileCursorBobTest`
moves into the addon (dec. 6 as written); `CursorPanelTuneFieldTest` **deletes** its reach; the
preview shader is **returned** to the host. dec. 6 is corrected on its second and third rows and
stands on its first.

**2. A test whose subject is a host script is a host test, whatever it preloads.** ADR-0194's rule
keys on what a test *can run without*, and the count that matters is host code touched, not addon
files named. One addon `preload` used as a fixture does not make a test the addon's, and moving a
test that needs a host autoload into `addons/` would make the stranger rig assert a project shape
the addon does not claim.

**3. A class-load reach is paid by DELETING it when the subject already forces the load.**
ADR-0208 dec. 1 showed the camera row was a class LOAD, not a static call, and paid it by loading
the host mount. The cursor is the same shape with a shorter answer, measured:

    a scene loading nothing            `Tune.is_registered("cursor.height")`   false
    a scene loading the host mount     same                                    true
    `CursorDebugPanel` (the SUBJECT) annotates `setup(_rig: CursorRig)` and reads
    `CursorRig.SEMI_MODE_LABELS`; `CursorRig` preloads the cursor script

So loading the subject already loads the owner and **no const is needed at all** — not the addon
script, not the host mount. The explicit `register_tunables()` call goes with it, and `Tune.reset()`
becomes `reset_overrides()` for
[ADR-0173](0173-a-central-replay-existed-because-reset-destroyed-what-only-the-owners-could-rebuild.md)'s
reason: `_static_init` fires once per class load per process, so `reset()` wipes the declarations
with no way back, and replaying one owner by naming it is the deleted `register_all()` shape done
by hand.

🔴 **A deleted dependency still needs a guard, and it is an assert on the EFFECT.** The transitive
chain that now does the work is three hops of host code and nothing spells the requirement, so
`Tune.is_registered("cursor.height")` is asserted before the four pose-row assertions that would
otherwise pass vacuously. The `false` row above is what makes it a predicate rather than a
tautology: a scene that loads neither leaves the slug unregistered.

**4. A file the bulk census moved by DIRECTORY can be ruled BACK, and the manifest says so with a
`returned` disposition.** Modelled on the `new` disposition ADR-0192 dec. 4 added: src **present**,
dst **absent**, the mirror of a move, asserted in both directions rather than exempted. Arm 3 stops
wanting a returned `dst`; arm 2's gate is untouched, which is the point. Direction-tested four ways
by seeding the TSV, because the arm has no population until the commit after it and an unreachable
guard cannot fail.

🔴 **Deleting the row would also have gone green, and that is the wrong fix.** The row is the only
record that the file was ever moved — the thing the manifest exists to hold. A guard satisfied by
deleting the evidence is not a guard.

**5. ADR-0192 dec. 1's ordering is scoped to a THRESHOLD register; a path-keyed table must move
WITH its population.** `classify_blueprint.py`'s per-file rows are validated against the tree by
`check_blueprint_walk`'s STALE RULE arm — *"names a file the walk does not see"* — so a row added
one commit early scored 2 problems instead of 0. dec. 1 is not weakened: a register that scores a
COUNT can and must lead its population, and a table that asserts a PATH cannot. Stated here so the
next pass does not read a green-then-red sequence as a mistake.

**6. A host mount must not be created at the moved file's original path.** The cursor mount was
first written as `assets/scenes/TileCursor.tscn`, which is exactly the `src` of a move-manifest
row, and `check_move_manifest` arm 1 reported *"BOTH src and dst exist (copied, not moved)"* —
correctly, because by path a mount at the src is indistinguishable from an un-done move. Renamed
`assets/scenes/CombatCursor.tscn`, after the host role rather than the addon file, which also
makes it read as a pair with `assets/scenes/CombatCamera.tscn`. That one dodged the identical
collision by accident: the addon file it fronts is named `PlayerCamera.tscn`. **The rule for the
next mount is the deliberate version of that accident.**

**7. A green register must distinguish `all named` from `none left`.** `check_lattice_scene` exits
0 in both states and printed one sentence for both, which is how a burn-down gets read as a pass
while it still holds rows. Two verdicts now: `resource-path register OK … NOT a pass on criterion
4` while rows remain, and `CRITERION 4 IS 0` when the list is empty — the second re-stating that
this is axis A alone and axis B's number is still owed.

🔴 **The anti-expiry control expired on success — the seventh time in this repo.**
`test_the_OK_line_does_not_depend_on_carrying_debt` exists precisely to prove the ✅ line still
prints at 0 rows, and it asserted the literal `resource-path register OK`; the commit that reached
0 gave that state its own wording, so the control **failed on the one case it was written for**.
Not fixed by loosening it to `✅`: the two spellings are a distinction the register now makes on
purpose, so the control asks for the verdict belonging to the state it is in, and a second test
seeds **both** states over the same tree and asserts neither prints the other's line.

**8. The empty burn-down and its both-arm tests stay.** Empty is a MEASUREMENT, not a finished job.
Arm 1 is what makes the next unnamed reach red instead of silently joining a filter, and the
ratchet arms seed their own rows, so they say the same thing over an empty list. Deleting a
register because it reads 0 is how the number starts climbing with nothing left to report it.

## Consequences

- **Criterion 4: 10 sites / 12 files, 2 declared → 0 sites, 3 declared mounts.** The burn-down is
  empty. All five registers on this branch:

      criterion 1  `check_lattice_publish`  arm 1 0 / 0; arm 3 5 names over 44 sites, all named,
                   none stale — #713's new instrument for ADR-0208 dec. 2, a burn-down and not a pass
      criterion 2  `check_lattice_ports`    CLEAR
      criterion 3  `check_lattice_doors`    CLEAR
      criterion 4  `check_lattice_scene`    0 sites, 3 declared mounts
      axis B       `check_addon_install`    CLEAR, 0 / 0

- **The stranger rig runs 9 addon-owned tests, up from 8**, and enrolled the moved test with no
  second list: `tests/stranger/exmateria_battlefield/run.sh` globs its addon's `tests/*.tscn`. Run
  standalone, rc 0, `TileCursorBobTest` 122 passed / 0 failed, no script error, and the stock-4.7
  fork-declaration arm still green. Per the previous pass's lesson the rig was run **before** the
  suite, not waited for inside it.
- **The move manifest reads 51 rows — 47 moved, 4 written in the addon, 1 returned to the host.**
  The addon holds 50 source files, one fewer than at the start of the pass.
- 🔴 **A pre-existing stale register was fixed rather than inherited silently.** `docs/RESIDUE.tsv`
  was already stale before this pass's third commit: the cursor mount renamed a reference in
  `FireCastRepro.tscn` and residue attribution follows path references, so two rows changed claims
  and the file was not re-derived. `check_residue` is **not in preflight**, which is why nothing
  said so.
- 🔴 **A pre-existing red is recorded and NOT fixed.** `check_blueprint_walk` reports 1
  UNCLASSIFIED — `assets/shaders/effect_particle_fold.gdshaderinc`, 56 lines, added by `e4c175228`
  with no classifier row. It is red on `origin/main` too (the file is there, the row is not), so it
  is trunk's and not this branch's. Ruling which system owns a shared include would move the
  residue and goal numbers this pass is measuring, so it is named here instead of changed.
- **ADR-0194 dec. 10's `stranger` counter WAS built** and is not a conformance gap:
  `tools/freeze_test_baseline.py` emits a `# stranger` line beside `# suite_size`. The checked-in
  `docs/TEST-BASELINE-E2.tsv` predates that feature and is a frozen artifact, not a regenerated
  one, which is why it carries `# suite_size 413` and no `stranger` line.

## Alternatives rejected

- **Moving the CLUT viewer into the addon, as dec. 6 says.** It needs two host textures and a host
  JSON; the stranger rig would fail it exactly as it failed `TileOverlayCompositorTest`. The reach
  is one `.gdshader` with one consumer in the whole tree and zero addon users — moving the file
  the other way deletes the dependency instead of relocating it.
- **Deleting the manifest row instead of adding `returned`.** Green, and it erases the only record
  that the file was ever moved. See dec. 4.
- **Re-spelling the shader reach.** Not available and not wanted: a `.gdshader` has no
  `class_name`, and ADR-0208 dec. 2 forbids paying a path row by naming an unpublished name in any
  case.
- **Keeping `assets/scenes/TileCursor.tscn` and teaching arm 1 that a mount is not a copy.** The
  guard's complaint is substantively right — by path the two states are identical — and the fix
  that costs nothing is to stop giving the mount the moved file's name.
- **Loosening the anti-expiry control to look for `✅`.** It would pass in both states and assert
  nothing about which one the register is in, turning a control that just caught a real drift into
  one that cannot.
