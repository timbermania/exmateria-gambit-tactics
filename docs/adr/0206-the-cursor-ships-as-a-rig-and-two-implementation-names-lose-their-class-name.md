# The cursor ships as a rig, and two implementation names lose their `class_name`

[ADR-0196](0196-the-marking-belongs-to-the-schema-and-a-respelling-is-never-the-reason.md)
dec. 8 left criterion 1 with 21 sites over 2 symbols and 8 files, and said why it could not
close them on that pass:

> **`TileCursor` (9) and `CursorController` (8) stay on the burn-down.** Four host scenes call
> `CursorController.new()` directly. That is a **construction** coupling — who builds the
> controller, and does `TileCursor` become a scene the addon hands out — and it is an
> **interface question, not a re-spelling**.

This ADR answers the interface question. The answer already had a precedent in this addon,
one pass old and written down in the file it changed.

Status: accepted (2026-08-29). Loop **pass 12** of extraction #3, on map
[#560](https://github.com/timbermania/fft-monorepo/issues/560). Closes **ADR-0164 dec. 4
criterion 1**. Sibling to [ADR-0205](0205-a-path-reach-is-the-same-axis-as-a-type-reach.md),
which opened criterion 4 on the same pass. Applies
[ADR-0192](0192-the-register-goes-first-because-the-port-erases-its-own-baseline.md) dec. 4 a second time.

## Context

### The 21 sites, and what they actually reach

| file | sites | shape |
|---|---|---|
| `src/debug/CursorDebugPanel.gd` | 5 | one `setup(_cursor: TileCursor)` + **four reads of `TileCursor.SEMI_MODE_LABELS`** |
| `src/scenarios/NavigatorMain.gd` | 3 | field + `CursorController.new()` + `TileCursor` field |
| `src/scenes/GPUArena.gd` | 3 | `@onready … = $TileCursor` + field + `.new()` |
| `src/scenes/EffectViewerScene.gd` | 3 | same shape |
| `src/scenes/FireCastReproScene.gd` | 3 | same shape |
| `src/scenes/BattlefieldWiring.gd` | 1 | `static func wire_cursor(tile_cursor: TileCursor)` |
| `src/ui3/formation/FormationMapHost.gd` | 2 | field + `bind_map` parameter |
| `src/ui3/formation/FormationDetailTransition.gd` | 1 | `mount_over_map` parameter |

The decisive measurement is not the site count but the **member surface**. Across all of
`src/`, the union of everything read off a cursor handle is:

    4 signals   cursor_moved / cursor_stepped / cursor_confirmed / cursor_inspected,
                every one `(grid_pos: Vector2i)`
    1 property  grid_pos
    1 constant  SEMI_MODE_LABELS
    2 exports   procedural_map_path / player_camera_path — set ONCE, at construction
    3 methods   CursorController.setup / seed_from_map / queue_free

Nine members. And `CursorController`'s whole host-facing surface is **three**.

🔴 **One member on the first list was not real.** `GPUArena.gd:559` reads
`tile_cursor.active_tile()` — **inside a comment**. A grep that counts `handle.member`
without stripping comments reports it as a reach, and it was on the first draft of this
port's surface. The port does not carry it.

### The precedent is one pass old and lives in the file it changed

`addons/exmateria_battlefield/lattice/TerrainIndex.gd` opens with:

> 🔴 **THIS FILE HAS NO `class_name`, AND THAT IS THE DECISION** (ADR-0192 dec. 4).
> ADR-0164 dec. 4 criterion 1 scans `class_name`s, so a type without one cannot be in the
> published set — and a door on a class nobody can name is not a door.

ADR-0192 dec. 4 rejected the cheaper runner-up — renaming in place and underscore-prefixing
the mutators — on the grounds that *published* would then be a **naming convention**, which
is exactly what criterion 1 exists to replace. The same two options are on the table here,
and the same argument settles them.

## Decisions

**1. The addon publishes `CursorRig`. `TileCursor` and `CursorController` lose their
`class_name`s.** `addons/exmateria_battlefield/cursor/CursorRig.gd` is the port; both
implementations are `preload`ed by it and by each other, exactly as `TerrainIndex` is by
`Lattice`. `TileCursor.tscn` carries its script **by path** and is untouched.

Dropping the names is not a convention. It removes the **only unmeasured spelling** of the
reach. 🔴 *Not* "structurally unnameable" — that is what ADR-0192 dec. 4 says about
`TerrainIndex`, and repeating it here would be false: **8 live sites outside the addon still
name `TileCursor` by path** today — 3 `assets/scenes/*.tscn` `ext_resource`s, 4 test
`preload`s of `TileCursor.tscn`, and `tests/CursorPanelTuneFieldTest.gd:12`, which
`preload`s `TileCursor.gd` and could legally annotate with the result. A dropped
`class_name` does not delete the reach; it forces it into the **path** spelling, and the
path spelling is scored — all 8 are rows on `check_lattice_scene`'s register (ADR-0205
criterion 4). That is the claim this pass can defend, and it is the stronger one: the debt
moved from a register that is structurally blind to it into one that counts it.

ADR-0192 dec. 4's phrasing is not wrong *there* — measured on this tree, `TerrainIndex.gd`
has **0** path reaches from outside the addon, so for it the two claims coincide. The
difference is that `TileCursor` also ships a `.tscn`, and a scene is reachable by path
whatever its script is called. Check the count before reusing the phrase.

The runner-up — leave both names and ask hosts to prefer the rig — is rejected for
ADR-0192 dec. 4's reason, and it would leave criterion 1 green only for as long as everyone
remembered.

**2. Two entry points, because the hosts genuinely differ, and neither changes a scene.**

    bind(parent, cursor, camera)              the cursor is AUTHORED IN THE SCENE
                                              ($TileCursor — GPUArena, EffectViewerScene,
                                              FireCastReproScene)
    mount(parent, camera, map_path, cam_path) the host has no cursor node and wants one
                                              (NavigatorMain's command cursor)

ADR-0204's lesson was that changing scene structure to suit a register is the expensive
mistake. `$TileCursor` stays exactly where it is; a node path is a scene-tree coupling, not a
type reference (ADR-0196 dec. 2). `mount()` sets the two exported NodePaths **before**
`add_child`, because the cursor's `_ready` resolves them relative to its parent — and it
records that it built the cursor, so `dispose()` frees it there and not at a `bind()` site.

**3. The port re-exports the measured surface and nothing else.** Four relayed signals, a
`grid_pos` getter, `SEMI_MODE_LABELS`, `seed_from_map`, `dispose`. Each signal has **exactly
one emit site** — the relay connection in `_relay()`. A second `emit` anywhere in the port
would make a consumer see one step twice, and no test could say which fired.

**4. Every host handle is `CursorRig`, statically typed, so this is not the forwarder
ADR-0170 dec. 1 refused.** `BattlefieldWiring.wire_cursor(rig: CursorRig)`,
`FormationMapHost.bind_map(cursor_rig: CursorRig, …)`,
`FormationDetailTransition.mount_over_map(…, cursor_rig: CursorRig, …)` and
`CursorDebugPanel.setup(_rig: CursorRig)` all take the port by name where they used to take a
`TileCursor`. ADR-0170's refusal was about the **receiver being untypeable** — `$ProceduralMap`
infers `Node`, so a forwarder left every consumer duck-typed. Consumers name `CursorRig` by
type. Delegation was never the objection.

**5. All 12 `PUBLISH_BURN_DOWN` rows are DELETED, and the list is now empty.** A stale row is
what success looks like (ADR-0196 dec. 4). The list is not repopulated to "keep the guard
exercised" — see dec. 7.

**6. `FORBIDDEN` keeps the two dead names.** Four of its six now have no `class_name` at all
(`TerrainIndex` from ADR-0192 dec. 4; these two from here), so they score 0 by construction.
That is precisely why they stay: re-adding `class_name TileCursor` would make every host
reach nameable again, and this list is what turns that into a red instead of a silent
regression. **Removing an entry because it reads 0 retires the guard on the day it starts
working.** `CursorRig` joins `DECLARED_PUBLISHED` in the same commit.

**7. The seed tests already survive an empty burn-down, and this was checked before the
close, not after.** The handoff into this pass predicted the opposite — that
`check_lattice_publish`'s tests would hit the same wall `test_check_addon_install.py` did,
where asserting the literal `"Not a pass"` (a heading the register prints only while carrying
debt) reddened pre-flight for everyone the day the last row was paid. That was the **sixth**
guard in this repo to expire on success. **It did not happen here.** All 30 assertions in the
module were audited against the register's output before any row was deleted; every one reads
seeded output, and `test_a_LISTED_row_prints_above_the_verdict` **constructs both the site and
the row**. All 15 tests pass with `PUBLISH_BURN_DOWN` empty. This is the first control in this
family to survive its own success, and it survived because a previous pass built it to.

## Consequences

- **Criterion 1 reads `PUBLISHED-SYMBOL REGISTER CLEAR`** — arm 1 at 0 rows / 0 sites, down
  from 12 / 21. ADR-0164 dec. 4's first criterion is met.
- Criterion 4 gets a row for free: `NavigatorMain.gd`'s `TILE_CURSOR_SCENE_PATH` const is gone
  because `CursorRig.mount()` owns the instantiation, so `check_lattice_scene` goes
  **138 → 137**.
- Arm 2 (`tests/`, reported) is unchanged in kind; **five** test annotations became `Node3D`.
  A test that drives the raw implementation holds it as a node, which is honest — it is
  testing the implementation, not the port. One test (`TileCursorIntegrationTest`) now builds
  a real `CursorRig`, so it exercises the shipped seam rather than a hand-assembled copy.
- 🔴 **The README's `class_name` count was stale, and this pass made it correct BY ACCIDENT.**
  The README says **30**; the tree actually held **31** before this pass. `CursorRig` in,
  `TileCursor` and `CursorController` out, is net −1 — so the tree is now 30 and the sentence
  is right for the first time in several passes, for a reason nobody chose. It was checked
  rather than assumed: an earlier draft of this ADR asserted the count was "now 29 and stale",
  which was arithmetic on a number the README had already got wrong. Nothing enforces it —
  `check_lattice_publish` deliberately does **not** parse that sentence, because a source
  assertion that matches its own prose stays green through the deletion of the line it guards
  — so the README now carries the drift history and the one-line re-count command.
- Anything outside the addon that wants a cursor now names one type. There is no supported way
  to reach `TileCursor` as a type from a host, and that is the point.

## Alternatives rejected

- **Keep both `class_name`s and route hosts through the rig by convention.** Rejected for
  ADR-0192 dec. 4's reason: *published* becomes a naming convention, which is what criterion 1
  exists to replace. It also stays green only while everyone remembers.
- **Hand out `TileCursor.tscn` as a scene and let hosts keep the node.** Rejected: it answers
  the construction half and leaves the 13 type annotations exactly where they are.
- **Have the rig expose the cursor node (`rig.cursor`) for the handoff sites.** Rejected: it
  reintroduces the duck-typed receiver at `bind_map` / `wire_cursor` / `mount_over_map` —
  ADR-0170 dec. 1's actual objection — for no gain, since the four signals and `grid_pos` are
  the entire thing those sites reach.
- **Move `SEMI_MODE_LABELS` into the schema addon**, mirroring `Tile.HighlightType` →
  `CellMarking.Kind`. Rejected: it is a debug-panel label table, not schema, and its only
  reader is one panel. Re-exporting it from the port costs one line and puts it where its
  reader already looks.
