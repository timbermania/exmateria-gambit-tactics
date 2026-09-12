# A stated host use was green and twenty times understated

[ADR-0208](0208-a-published-name-pays-a-path-reach-and-the-cameras-static-reach-was-a-class-load.md)
dec. 6 made the per-entry host-use comment on `DECLARED_PUBLISHED` a structural requirement, and
`test_every_declared_name_states_a_host_use` mechanized the only half its own docstring believed
mechanizable: **presence**. That arm was green while `Lattice`'s entry said a debug panel annotates
`map.lattice` and the tree held **50 references over 22 `src/` files** — the GPU combat pipeline,
the scenario VM, strategy placement and `Unit` all compile against the name. The arm required that
somebody wrote a sentence; nothing read it.

A sentence cannot be graded. A **citation** can. This pass corrects the entry and mechanizes the
half that was actually available: a comment naming a host `.gd` file makes a claim about the tree,
and both arms of that claim are checkable.

Status: accepted (2026-08-29). Loop **pass 16** of extraction #3, on map
[#560](https://github.com/timbermania/fft-monorepo/issues/560). Builds ADR-0208 dec. 6's unbuilt
half; scoped by
[ADR-0196](0196-the-marking-belongs-to-the-schema-and-a-respelling-is-never-the-reason.md) dec. 4.

**Axis B is unchanged and CLOSED**: `check_addon_install` reads 0 sites / 0 rows. The register this
touches is **axis A** criterion 1.
[ADR-0202](0202-installable-is-the-fork-plus-the-kernel-and-the-port.md) dec. 1 forbids reporting
either axis as the other, so both numbers appear here.

## Context

### The arm knew it was structural and said so

`test_every_declared_name_states_a_host_use`'s docstring is explicit: *"This is deliberately
STRUCTURAL and not semantic. It cannot tell a true host use from a false one; it can only tell that
somebody was made to write a sentence."* That is an accurate description of what it does and an
accurate statement of its limit. It is not a statement that no more was available — it is a
statement that nobody had looked for more.

### `Lattice` is the measurement that shows the gap is not theoretical

The entry read, in full: *"Host use: `src/debug/ScenarioUnitAlignmentDebugPanel.gd` annotates
`map.lattice` with it."* Measured across `src/`:

| consumer | shape |
|---|---|
| `GPUBatchSimulator` | `initialize(lattice: Lattice, …)`, `build_map_data(lattice: Lattice, …)`, `_create_buffers`, and a typed field |
| `DistanceFieldGenerator` | `generate(lattice: Lattice, …)` |
| `GPUMovementVisualizer`, `GPUCombatPacker`, `GPUVisualBridge` | typed parameters |
| `CombatHost`, `CombatLoop`, `ScenarioWeather`, `ProgressionTester` | typed fields |
| `ScenarioVM._lattice()`, `ScenarioPlayerScene._map_lattice()`, `NavigatorMain`, `GPUArena` | the typed fetches ADR-0192 dec. 3 named |
| `ScenarioPlacementSource`, `PlacementTileGenerator`, `PlacementInputHandler`, `StrategyPhaseManager` | strategy placement |
| `Unit`, `CinematicFacingResolver`, `TileTraversalUtils`, `ScenarioCameraDirector` | one seam each |

Twenty-two files, fifty references. The debug panel was the least of them, and it was the only one
the list knew about. An entry that understates its subject by a factor of twenty is not a lie a
reader would catch — it reads exactly like the eleven correct entries beside it.

### The two ways a citation rots, and both were green

Every one of the twelve host files cited across the eleven entries **exists** and **names its
symbol** today. That is what makes this a ratchet worth building rather than a burn-down: the arms
are green on this tree, so each can only ever fire on a change that arrives later. The two rots are
the two this corpus has already paid for elsewhere — a file that MOVED, and a call site that was
DELETED while the prose stayed.

### The 27-site `Tile` row is one fixture written three times, and collapsing it does not pay it

`tests/{EffectStudioCameraOwnership,TileCursorIntegration,TileCursorTakeover}Test.gd` each carried a
**byte-identical** copy of the same two inner classes and the same tile constructor — 8 lines /
9 `Tile` occurrences apiece, 27 in all. It is one problem written three times.

Arm 3 keys on the **name**, not the site: *"one namer is the whole defect"*. So collapsing three
copies into one moves `Tile x27 over 3 files` to `Tile x7 over 1 file` and leaves the row exactly
where it was, at target 0. That is stated here in the same breath as the collapse because booking a
site count against a row target is how a correct move reads as a win it is not.

### Why the fixture cannot stop naming `Tile`, measured rather than reasoned

`MapBufferBoundsTest` is the precedent that looks like it should apply: it *used to* call
`TerrainIndex.new()` and `add_tile(Tile.new())` with four `Tile` nodes, and ADR-0170 dec. 6's claim
— *"a `TerrainCell` is trivial to fabricate where a `StaticBody3D` is not"* — landed as that file
dropping its node plumbing entirely. It works there because its consumer,
`GPUBatchSimulator.build_map_data`, reads `all_cells()` and `is_cliff_edge()`: both VALUE members.

These three drive consumers that resolve the **node**. `TileCursor._get_tile_at()` and
`PlayerCamera._map_tiles()` read `Lattice._tile_at` / `_tiles` — the addon-internal back door
ADR-0192 sanctions for addon files — and both are `Tile`-annotated. A `Lattice` subclass answering
them with a stand-in node was probed under the fork:

```
SCRIPT ERROR: Trying to return a value of type "Node3D (_Stand)" from a
function whose return type is "Tile".
    at: _NoTileLattice._tile_at
```

GDScript enforces the return type at runtime and hands the caller `<null>`. **A host fixture cannot
supply anything but a real `Tile`**, and no rewrite of the fixture changes that.

## Decisions

**1. A declared name's comment may cite a host `.gd` file, and a cited file must EXIST and must
NAME the symbol.** `declared_citations()` in `check_lattice_publish.py` parses the entry comments;
`TheCitedHostFiles` in `test_check_lattice_publish.py` runs the two arms. Both are green on this
tree.

- *The boundary is the `.gd` suffix, and it is deliberate.* `MapIlluminationDDA`'s entry says
  `src/effects/PaletteSubsystem.build_illumination()` — path-shaped prose naming a **method**, which
  is house style here. Scoring any `src/…` token would red a correct comment for how it is written.
  🔴 **Stated blind spot**: a class-or-method citation rots unscored. `TileHighlights` and
  `MapIlluminationDDA` cite no file today and are therefore unscored by both arms.

- 🔴 *This does make deleting the last host call site red the arm, and that is not the inversion
  ADR-0196 dec. 4 rejected.* Dec. 4 made the declared-set report REPORTING because enforcing the
  declared-but-unnamed direction "would make deleting a host call site red this guard, which is
  backwards" — there, the remedy would have been to restore the coupling. Here the name stays
  declared and the remedy is to **re-read the comment**. That route is not hypothetical:
  `TileCursorCompositor` lost its last host namer to ADR-0200, its entry was rewritten to say
  `⚠️ NO HOST NAMER TODAY`, and it passes both arms today because the prose still names the symbol.
  The arm demands a current sentence, never a restored call.

- *The seeds drive the predicates, not the tree.* `_moved()` and `_silent()` are called by the live
  arms and by the seeds alike. A seed that re-states the condition it seeded ("the file is absent")
  proves the tree and never the arm — a shape this repo has shipped and watched a broken guard pass
  beside. Mutating `_moved()` to return `[]` reds the seed; the third seed pins the stated blind
  spot so it cannot be widened by accident.

**2. The three cursor/camera fixtures collapse into one host-owned file, and the row they hold is
FILED rather than paid (#716).** `tests/FakeBattlefieldMap.gd` is the single copy; the three tests
reach it by `preload`, not by a `class_name`, because a `class_name` is a global registration and
the addon's namespace is itself an open question (#717).

- *This does not pay the row and the register says so.* Arm 3 reads **5 names / 24 sites** after,
  against 5 / 44 before. `Tile` goes 27 → 7 and stays on `UNDECLARED_BURN_DOWN`; the row's `why`
  text now states the collapse and states that it did not pay. What the collapse buys is that the
  eventual payment is a ONE-file edit instead of three.

- *Every route on ADR-0208 dec. 2's menu costs an addon-interface decision, which is why this pass
  files instead of building.* Deleting the dependency is blocked by the measurement above; naming a
  published name is blocked because `Lattice` **has no published constructor** — `_init(store)` and
  `_bind(store)` both take `TileStore`, whose `class_name` ADR-0192 dec. 4 deliberately removed;
  host-owned indirection is what this decision did, and it moves sites and not rows; publishing
  `Tile` is forbidden outright by ADR-0164 dec. 4 criterion 3. #716 states the three-way fork.

- 🔴 *The collapse introduced two criterion-2 violations and the register caught them.* Replacing
  `tile.global_position` with the published `world_position_at` was right, but written as
  `fake_map.lattice.world_position_at(1, 1)` it is a chained duck-typed reach —
  `check_lattice_ports` arm 2 went 0 → 4. The tests' own comments warn about exactly this shape.
  Fixed by binding one typed handle at the seam, the form ADR-0192 dec. 3 permits; arm 2 is back
  to 0.

**3. The `PlayerCamera` row is PAID by deleting the const read, and the guard is an assert on the
EFFECT. The route the row's own comment proposed is superseded.** *(Applies
[ADR-0209](0209-one-ruling-over-three-rows-that-needed-three-and-a-file-can-be-ruled-back.md)
dec. 3 to the camera half of the pair ADR-0208 dec. 1 opened.)*

Both sites were `Tune.set_value(PlayerCamera.FREE_CAMERA_SLUG, ...)` in
`tests/TileCursorIntegrationTest.gd`. What the const read obtains is a **string key**, not a
compiled symbol — so the type reference bought the test nothing the literal does not, while costing
an arm-3 row. `FREE_CAMERA_SLUG` is now spelled in the test.

- *The row's comment proposed ADR-0196 dec. 6's route — move the slug to the schema. That route is
  wrong for this value and the later ruling says why.* ADR-0196 dec. 6 moves a value **two systems
  must agree on** (`CellMarking.Kind`: `src/strategy/` decides which cells are marked, the addon
  decides how). A Tune slug has exactly **one** writer — `PlayerCamera._static_init()` →
  `register_tunables()` → `TunePort.bind(...)` at class load — and the registry is already the
  shared surface. Putting a camera-private tuning key in the kernel would make the schema carry a
  name only the camera means anything by.

- 🔴 *A bare literal would rot silently, so the spelling is CHECKED — and that the check is a
  PREDICATE was measured, not reasoned.* The test instantiates the host mount
  `assets/scenes/CombatCamera.tscn`, which loads the camera and therefore registers the slug, so
  `Tune.is_registered(FREE_CAMERA_SLUG)` is asserted before the four free-pan assertions that would
  otherwise pass vacuously. Two probe scenes, run headful on the fork:

      a scene loading nothing            `Tune.is_registered("camera.free_camera_enabled")`   false
      a scene loading the host mount     same                                                 true

  The `false` row is what separates this from a tautology: rename the slug in the camera and the
  test reports it.

- *Arm 3 goes 5 names / 24 sites → **4 names / 22 sites**, and the burn-down's STALE arm is what
  reported the payment.* Deleting the two sites left the listed `PlayerCamera` row naming a name no
  longer both named-from-outside and undeclared; the guard failed with `STALE UNDECLARED_BURN_DOWN`
  until the row was removed. That is the ratchet's second arm doing the only thing that
  distinguishes a paid row from a scanner that stopped seeing it.


**4. `MapStateSelectorTest` moves into the addon as a SPLIT — the synthetic legs travel, the
content leg stays.** *(Applies [ADR-0194](0194-a-test-belongs-to-the-addon-it-can-run-without-the-game.md)
/ #652; the burn-down row's own objection is upheld, not overruled.)*

The row read **8 sites, one file** — every one `MapStateSelector.select(...)` from the class's own
unit test — and its comment said the ADR-0194 move "is NOT free here" because the test loads host
MAP056 content. That objection is correct and this decision does not wave it away: an addon-owned
test is run **only** by `tests/stranger/exmateria_battlefield/run.sh`, which globs
`addons/<addon>/tests/*.tscn` in a project with no content root, and ADR-0194 dec. 4 forbids running
one as `res://tests/X.tscn` in the host. A file that moves whole therefore stops asserting anywhere
its content is absent.

What made the row payable is a property of the **legs**, not of the class: five of the six build
their own `states[]` through a local `_state()` helper and need nothing at all.

- *The five synthetic legs* are now `addons/exmateria_battlefield/tests/MapStateSelectorTest.gd`.
  Inside the addon, `MapStateSelector.select(...)` is not a reach, and arm 3's row is paid — the
  STALE arm reported it before the row was deleted, as with dec. 3.
- *The sixth leg stayed* as `tests/MapStateExportTest.gd`, **re-expressed rather than copied**: a
  copy would have left the row at 2 sites and paid nothing. Its subject is the EXPORT — that MAP056's
  shipped `states[]` rows still carry `arrangement_id` / `night` / `weather_raw` / `default` with the
  values scenario 4 depends on — so it names no addon class. Both halves are needed and neither
  covers the other: the addon's legs pass against a stale export, and the host's leg passes against a
  broken selector.
- *Both assertions were direction-tested.* Seeding the expected sky as `(135,138,150)` and adding a
  key no row carries each produced exactly one `[FAIL]` and left the other arms quiet.
- *The absence path is a counted, printed `[SKIP]`*, not a silent pass, so a run that checked nothing
  does not read like a run that checked something.

**5. The remaining three rows are PRICED and FILED, and two of them are one problem.**

The brief asked for the host content each row needs to be priced before any ADR-0194 move. Measured:

| row | sites | what the legs need | move? |
|---|---|---|---|
| `MapStateSelector` | 8 | 5 of 6 legs synthetic | ✅ dec. 4 |
| `MapTextureAnimator` | 6 | all 4 legs need host MAP062; 2 more need MAP104; 1 is a mount-based host wiring test | ❌ coverage deletion |
| `DynamicGeometryBuilder` | 1 | a host wiring test on the `ProceduralMap.tscn` mount | ❌ blocked, below |
| `Tile` | 7 | — | ❌ #716, dec. 2 |

🔴 **`DynamicGeometryBuilder` and `Tile` are the same defect, and the measurement says so.**
`MapComposer.dynamic_geo_builder` is a **typed** member and GDScript enforces the type on assignment,
so the host cannot inject a stand-in:

    Invalid assignment of property 'dynamic_geo_builder' with value of type
    'RefCounted (Stand)' on a base object of type 'Node3D (MapComposer)'

The one route that does work — `preload("res://addons/exmateria_battlefield/terrain/DynamicGeometryBuilder.gd").new()`
— is **not payment**: `check_lattice_scene` enforces `tests/` and reads 0, so it converts an arm-3 row
into a criterion-4 row. That is laundering one register into another, and it is the same move
[ADR-0205](0205-a-path-reach-is-the-same-axis-as-a-type-reach.md)
built its register to make visible. Both rows need the addon-interface decision #716 already states:
**the addon exposes typed members whose types it does not publish**, and no host-side rewrite reaches
either. #716 is updated with this second instance.


**6. `exmateria_platform` and `exmateria_render` get stranger rigs, and both declarations are
MEASURED before they are written.** *(Completes ADR-0194's roster: all four in-walk addons now have
one.)*

Both addons had no rig, no `tests/`, and no `engine=` line, so `shared/rig.sh` would have exited 2 —
could-not-run, correctly, and invisibly as far as any suite was concerned. `exmateria_platform` is
additionally `exmateria_battlefield`'s own declared dependency and until now was only ever staged as
scaffolding for someone else's run.

- *`exmateria_render` is `engine="fork"`, `deps="exmateria_schema"`, and the fork claim was measured
  on BOTH binaries rather than inferred from the fold's reputation.* `FoldSurface.gd`'s `ResolvePass`
  sets `render_layers = [Fold.FOLD_LAYER]` and reads `get_layer_texture(...)`; probed through
  `ClassDB`, stock 4.7.1's `CompositorEffect` carries **neither** — no `render_layers` property, and
  `class_has_method(..., "get_layer_texture")` is `false` — where both are `true` on
  `4.8.dev.custom_build`. The dep is `Fold.FOLD_LAYER` itself.

- 🔴 *`exmateria_platform` is `engine="stock"`, the first here, and that is the STRONGER
  declaration.* It says the platform layer has no fork dependency at all. dec. 7's absence arm does
  **not** check it — that arm runs only for `fork`. What checks it is the install pass: `RUN_GODOT`
  *is* the stock binary, so stock is what loads all 20 staged files.

- *Step 3 was paid, six ways, three per rig, each restored after.* Platform: a member that stops
  parsing; a member that `preload`s into `res://src/`; and a fork-only
  `RenderingServer.is_compositor_layer_supported()` call under the `stock` declaration — rc 1, rc 1,
  rc 1. Render: a member that stops parsing; `deps=""` so the declared kernel is not staged, which
  leaves `Fold` unresolved — rc 1, rc 1; and dec. 7's absence arm, below.

- 🔴 *The absence arm cannot be pointed at the wrong engine by `GODOT_STOCK`, and finding that out
  is the reason to try.* Exporting `GODOT_STOCK=<the fork>` came back **rc 0** — not a hole: `resolve
  stock` rejects any binary whose `--version` contains `custom_build` and silently falls back to
  `/usr/bin/godot`, so the seeded run used the right binary all along. A seed that comes back green
  because the subject defended itself is indistinguishable from a seed that proved nothing, which is
  why it is written down here. The arm was proved red directly instead — the shared scene run under
  the fork reports `[FAIL]` naming both primitives.


## Consequences

- `Lattice`'s entry now states its real subject: the terrain query surface the host compiles
  against. It cites `src/gpu/CombatHost.gd` — the combat seam — rather than a debug panel, so the
  checked half of the claim points at a load-bearing file.
- The declared set gains a rot detector it did not have. Eleven entries, twelve citations, both arms
  at zero.
- Arm 3: **5 names / 44 sites → 5 names / 24 sites.** Both numbers are reported because the row
  count is the target and the site count is not.
- Three byte-identical 35-line fixtures become one. All three tests pass; the battlefield stranger
  rig passes; `check_lattice_ports`, `check_lattice_doors`, `check_lattice_scene`,
  `check_addon_install` and `check_move_manifest` are clean, and `docs/RESIDUE.tsv` is unchanged.
- A future entry may still be written with no file citation and pass. That is reported above rather
  than hidden, and it is the cost of not redding correct prose.

## Alternatives rejected

- **Require every entry to cite a file.** Would red `TileHighlights` and `MapIlluminationDDA`, whose
  comments are correct and name classes and a method instead. A guard that forces prose into one
  shape to be checkable trades a real statement for a checkable one.
- **Require the comment to name every host consumer.** `Lattice` would need twenty-two files, and
  the list would be stale on the next commit that adds or removes a seam. A comment that must
  enumerate a population is a second copy of that population — the exact defect this file's own
  header warns about two lists over.
- **Leave it structural and fix only the comment.** The comment was wrong for as long as it existed
  and no arm could say so. Fixing the instance without building the arm buys one correct entry and
  no ability to detect the next one.
