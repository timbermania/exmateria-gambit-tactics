# A published name pays a path reach, and the camera's static reach was a class load

Criterion 4 counts a host file naming an addon resource path. Sixteen rows remained after
[ADR-0207](0207-a-script-reach-collapses-onto-an-instanced-mount-and-a-static-reach-has-nowhere-to-go.md),
six of them unscheduled, and one — the camera — was recorded there as a shape with no known
mechanism at all. This pass rules the six and pays them. **Criterion 4 reads 16 sites / 18 files
→ 10 sites / 12 files, 2 declared**, and every remaining row is owned by a live pass rather than
by the word *unscheduled*.

It also **corrects ADR-0207 dec. 3**, which lumped two different shapes under one ruling and was
measured wrong on the half it never tested.

Status: accepted (2026-08-29). Loop **pass 14** of extraction #3, on map
[#560](https://github.com/timbermania/fft-monorepo/issues/560). Applies
[ADR-0194](0194-a-test-belongs-to-the-addon-it-can-run-without-the-game.md) a third time and
[ADR-0192](0192-the-register-goes-first-because-the-port-erases-its-own-baseline.md) dec. 1 twice.

**Axis B is unchanged and CLOSED**: `check_addon_install` reads 0 sites / 0 rows. The battlefield
system is **installable**; it is **not isolated**. ADR-0202 dec. 1 forbids reporting either as the
other, so both numbers appear here and in every report of this pass.

## Context

### 🔴 The register scored a SPELLING, and the loophole was already live

Criterion 4 sees `preload("res://addons/…")`. It does not see `var _g: MapGridOverlay`. Five of
the six unscheduled rows targeted a class carrying a `class_name`, so each could have been closed
by deleting the path and writing the bare name — one line per row, the count falling to zero with
the dependency untouched. That is not hypothetical:

    src/debug/ScenarioUnitAlignmentDebugPanel.gd:40,139   var _grid: MapGridOverlay / .new()
    tests/MapPaletteFieldObjectTest.gd:141                PaletteTextureGenerator.create_palette_texture(…)

Both are host→addon reaches that criterion 4 cannot see, and the first is in `src/` — the shipped
game. The sibling register already prints the true size: **14 of the addon's 30 `class_name`s are
named as a type outside it**, five of them undeclared. So the handoff's *"`PaletteSubsystem.gd` is
the only remaining reach from `src/`"* is true of the register and false of the axis.

The naive conclusion — *re-spelling is always a fraud* — is wrong in the other direction, because
the addon **publishes ten names on purpose**, described in `check_lattice_publish.py` as *"the
port, its configuration, and the overlay/pathfinding surface a host is invited to name."*
`MapGridOverlay` and `MapIlluminationDDA` are both on that list. Refusing a host the use of a
published name would mean the addon publishes an API nothing may call, and it would refuse the
mechanism ADR-0206 built when it created `CursorRig`.

The distinction that survives both readings is **consent**. An unpublished name is the host
reaching past the addon's stated surface; a published one is the addon having offered it. dec. 2
rules on that, and dec. 6 gates the list so the rule cannot be evaded one level up.

### 🔴 The camera reach was never about reaching a `static func`

ADR-0207 dec. 3 ruled that a static reach has no mount, and left
`tests/CameraFeelPanelTuneFieldTest.gd` as the single row with no mechanism. Its reasoning was
that `PlayerCameraScript.register_tunables()` is `static`, that a `PackedScene` hands out a node
rather than a script, and that re-spelling it `PlayerCamera.register_tunables()` names a
criterion-1 `FORBIDDEN` symbol. The first two premises were never measured. Five arms, headful on
the 4.8 fork, reading `Tune.is_registered("camera.rot_speed")` without binding it:

    N      nothing                                    NOT registered   (control)
    A      load the ADDON script                      REGISTERED       `_static_init` at class load
    ACALL  A + explicit register_tunables()           REGISTERED       the call is a NO-OP
    B      load the HOST mount, no instantiate()      REGISTERED
    C      B + instantiate() + add_child()            REGISTERED + 8x SCRIPT ERROR

`CameraFeelDebugPanel` names no script at all — it is a pure view over `camera.*` slug **strings**
(`TuneField.add(vbox, "Rotation speed", "camera.rot_speed")`). So the `preload` was not fetching a
symbol. It was forcing the **class load** whose `_static_init` binds the slugs, and the explicit
call did nothing. Arm B shows the host's already-declared mount does the same thing by being
loaded. Arm C — the mechanism the handoff proposed — works and is the worst of the three: it
builds the whole camera rig plus the host's `CombatUI` and throws eight
`get_value(render.psx_ui_par) before its bind` errors doing it.

The composer's static reach is a **different shape** and dec. 3's answer for it stands.
`MapComposer.bake_field_tint(…)` is a real call; it needs the symbol, so an instance is required.
Lumping the two is why the camera's answer looked unsolved.

### `tools/` is a third shape, and it happens to have no rows

`tools/capture_grid_beat.gd` is `extends SceneTree`, run as `godot -s`. `tools/generate_palette_texture.gd`
is `@tool extends EditorScript` and never ships. Neither a mount (which needs a consumer scene)
nor ADR-0194 (which needs a test of addon internals) addresses either: a standalone entry point
**is** the top of the tree, so there is nothing for a mount to sit between. Measured while ruling
this: a global `class_name` **does** resolve inside a `-s` script, even though an autoload does
not (`Tune` fails to compile in the same context).

## Decisions

**1. A static CALL needs the symbol; a class-LOAD reach needs only the load. ADR-0207 dec. 3 is
corrected on its camera half and stands on its composer half.**
`tests/CameraFeelPanelTuneFieldTest.gd` now `preload`s `assets/scenes/CombatCamera.tscn` —
ADR-0204's mount, declared and live since pass 11 — and never instantiates it. `Tune.reset()`
becomes `Tune.reset_overrides()` and the `register_tunables()` call is deleted. Both follow from
the measurement and from ADR-0173: a `preload` fires once at script load, so `reset()` would wipe
the declarations with no way back, and replaying an owner's registration by naming it is the
deleted `register_all()` shape done by hand for one owner. `Tune.reset()`'s own docstring already
says a test in this shape wants `reset_overrides()`. Assertion parity held: 4 passed / 0 failed
either side. **A mount is reachable by being LOADED, not only by being instanced** — which is the
general fact dec. 3 missed, and it makes the camera row ordinary rather than unsolved.

🔴 The const has **no reader**; its entire value is the load side effect, so the next reader
deletes it as dead and four assertions pass vacuously against unregistered slugs. That is not a
hypothetical failure mode in this tree — `Tune.on_update`'s own 🔴 records `CameraFeel` printing
`[PASS]` through **5322** `get_value` script errors. It is guarded by an assert on the **effect**,
`Tune.is_registered("camera.rot_speed")`, which also fires if the mount stops carrying the script
or `_static_init` regresses. Direction-tested: deleting the const gives `Assertion failed … the
camera.* slugs are not registered` and no `[PASS]`. A comment could not have done that.

**2. A criterion-4 site is paid by deleting the dependency, by host-owned indirection, or by
naming a name the addon PUBLISHES — never by re-spelling an unpublished one.** The rule is on the
AXIS, not on `check_lattice_publish`'s `FORBIDDEN` list. ADR-0207 dec. 3 declined the re-spelling
only because `MapComposer` is forbidden, which is the weaker reason: it says *which register
reports the debt*, not whether the debt was paid. `FORBIDDEN` membership is now irrelevant to
whether a re-spelling pays. Three rows are paid under the third clause —
`src/effects/PaletteSubsystem.gd` (`MapIlluminationDDA`), `tools/capture_grid_beat.gd`
(`MapGridOverlay`) and `tools/generate_palette_texture.gd` (`PaletteTextureGenerator`).

This does not collide with [ADR-0004](0004-rosters-share-a-base-script.md)'s surviving decision,
which is scoped to `extends`: a base class resolved through a cold global class cache fails at
autoload-parse time, which is a different mechanism from a type annotation. `check_path_extends`
is green, and 14 of the addon's names are already reached as types from outside.

**3. A standalone entry point has no mount, and the shape is RECORDED rather than built.** A mount
needs a consumer scene; a `-s` SceneTree script and an `@tool EditorScript` are the top of the
tree. Their only faithful routes are a published name or moving the reach. **No `DECLARED_*`
category is created**, because after dec. 2 and dec. 4 the shape has zero rows and an empty
declared list is machinery justified by nothing. `tools/` stays inside criterion 4's walk: closing
these rows by narrowing the scan would be the failure `check_lattice_publish` names in its own
comment — *"an empty root left unscanned is a place the register can be satisfied by writing the
reach somewhere it does not look."*

**4. `PaletteTextureGenerator` joins `DECLARED_PUBLISHED`.** This RECORDS a surface two host
callers already used rather than inventing one: `tests/MapPaletteFieldObjectTest.gd:141` had been
calling `create_palette_texture()` as a type while the name was undeclared, which is why it
appeared in criterion 1's *named but NOT declared* set. It is a pure data→resource converter with
no scene coupling — the generation surface the declared set already describes. Five undeclared
now, not six.

**5. `src/effects/PaletteSubsystem.gd`'s reach is a stated RESERVATION, and the machinery is
KEPT.** The handoff priced this as the highest-value row because it is the last reach from shipped
code. It is less than that: the file's own comment records that `build_illumination` and the DDA
are *"no longer delivered to the map … Kept for a future untextured-terrain scope; exercised only
by PaletteSubsystemTest/MapIlluminationDDATest"*, and `src/effects/MapTintOverlay.gd:84` records
the same retention for the shader uniform. Deleting three methods would have closed the row and
removed the last `src/` reach in one stroke. Rejected: the retention is documented, reasoned and
tested, and **deleting live code to move a counter to zero is the register driving the design.**
The row is paid by dec. 2 instead. Its owner was also wrong — it sat under *"ADR-0205 dec. 7 —
texturing pass"* as though it were a sibling of the tool scripts, when the shape is *the host
keeps a reservation on addon machinery*, and that will recur.

**6. `DECLARED_PUBLISHED` is GATED, because dec. 2 makes it load-bearing.** Once a published name
pays a row, a row can be drained by declaring its target — dec. 2's own hole, one level up. The
gate: **a name joins the list only in a pass that STATES the host use it serves, and never in the
same commit as the row it would close.** The second half is ADR-0192 dec. 1 applied to a literal
instead of a scanner, and it is a discipline no scanner can read; this pass obeyed it, landing the
list change in its own commit ahead of every payment. The half that IS mechanizable is presence:
`test_every_declared_name_states_a_host_use` requires a comment above every entry, and pins that
it parsed every name so an empty parse cannot report zero. Direction-tested both ways — stripping
`MapConstants`'s comment fails, adding an uncommented `Doodad` fails.

The arm is **structural, not semantic**, and says so in its own docstring: it cannot tell a true
host use from a false one, only that somebody was made to write a sentence.
`TileCursorCompositor`'s entry states it has **no** host namer today; that is a stated answer, not
a yes, and it passes.

**7. `check_lattice_scene.py` scores COMMENTS, and that is recorded here rather than fixed.** The
first draft of `PaletteSubsystem.gd`'s new comment quoted the old `res://addons/…` literal to
explain what had changed, and the register counted the prose — re-creating at a new line number
the exact row the edit had just paid. Its sibling `check_lattice_publish.py` strips non-code via
`_code_lines`; this one does not. It is left alone in this pass because **a scanner must not be
edited alongside its own population** (ADR-0192 dec. 1) and every commit here moves that
population. It is a real defect in both directions: prose cannot discuss a paid spelling, and a
genuine reach hidden in a commented-out line is indistinguishable from commentary about one.

**8. The overlay pair's tests move into the addon under ADR-0194 — not by publishing their
names.** `TileOverlayColorTest` and `TileOverlayCompositorTest` each held exactly one reach, the
`preload` of the addon script under test, and touched no host code. That is ADR-0194's case
exactly, and ADR-0207 dec. 6 applied it to the three cursor tests one pass ago on identical
evidence. Publishing `TileOverlayColor` and `TileOverlayCompositor` so their own tests may name
them is the shape ADR-0206 went the other way on when it deleted two implementation `class_name`s
in favour of one `CursorRig`. `tests/stranger/exmateria_battlefield/run.sh` **globs** its addon's
`tests/*.tscn`, so the move enrols them with no second list; `known_failures.tsv` needs no row
because the lattice port already paid `overlay/TileOverlayCompositor.gd`'s. Both gained an
assertion counter in the move commit — ADR-0194 dec. 12 arm 2's convention — and report 28 and 20.

🔴 **The rig earned its keep immediately, and only the FULL SUITE found out.** Five green
registers, a green `check_addon_portability` and every assertion passing all said the move was
clean; `stranger:exmateria_battlefield` said `[FAIL] TileOverlayCompositorTest reported PASS while
throwing something the burn-down does not explain: Cannot call method 'get_width' on a null value.`
`TileOverlayCompositor._load_palette()` asks `BattlefieldContent.range_palette_path()` for **host
content**, which a project that did nothing for the addon does not have — so `_palette` stays null,
exactly as designed, and `_process` guards on it. The test called the private `_append_tile`
directly and walked past that guard into `TileOverlayColor.flat_color(null, …)`. **The addon is not
at fault and no shipped behaviour changed**: the test was quietly dependent on host content, which
is what ADR-0194 dec. 8 means by thin. Fixed by injecting a 16x1 stub palette — precisely what the
sibling `TileOverlayColorTest` already did, which is why *it* passed. Two lessons. The defect was
invisible to every instrument except the rig; and it was invisible **inside** the rig too except to
the script-error arm, because all 19 assertions passed either way — ADR-0194 dec. 12's counter is
necessary and not sufficient. The comment that misled here also named the wrong function (`_ready`,
where the load is in `_init`) — the pass's fourth stale prose fact.

## Consequences

- **Criterion 4: 16 sites / 18 files → 10 sites / 12 files, 2 declared.** Six rows deleted, four
  owner constants deleted with their last row. Still not a pass: the target is 0. Every remaining
  row is owned by a live pass — ADR-0207 dec. 5 (the cursor mount, 7) and dec. 6 (the
  implementation tests 2, the CLUT preview viewer 1). **Nothing is unscheduled any more.**
- **Axis B unchanged: `check_addon_install` 0 / 0.** All five registers rc 0. Installable, not
  isolated; that has not moved this pass.
- Criterion 1's arm 1 stays 0 / 0. The declared set goes 10 → 11 and the undeclared-but-named set
  6 → 5.
- 🔴 **Three stale counts were found in prose beside a list, in one pass.**
  `DECLARED_PUBLISHED`'s header read *"NINE, not thirty"* beside a ten-name tuple while the
  register printed `10 name(s) declared`; `check_lattice_scene`'s `TEXTURING` owner said *"one of
  only TWO `src/` rows"* where the register has listed one for a pass; `CombatCamera.tscn` named
  five `.gd` files that *"deliberately still"* preload the addon camera scene, which ADR-0207
  dec. 7 made false. All three are corrected, and the first is what dec. 6 makes structural rather
  than habitual. A number written beside a list is a second copy of the list.
- A pre-existing red is fixed and attributed rather than inherited silently:
  `check_test_baseline` had been failing on `TuneRegisterAllTest` since `5b16ee435`, where #535
  deleted `Tune.register_all()` and the test that mirrored it, and no ledger row was written. An
  early-aborting preflight guard hides every guard behind it, which would have left this pass
  unverifiable.
- 🔴 **dec. 2 IS RULED AND UNGUARDED, and it is the widest hole on the map.** Found by
  `enforce-adr-conformance` against this ADR minutes after writing it. `check_lattice_publish`
  arm 1 — the only ENFORCING arm that scores a type reach — scans the six-name `FORBIDDEN` tuple,
  and **only three of those six are still `class_name`s at all** (ADR-0206 dec. 1 unpublished
  `TileCursor` and `CursorController`; `TerrainIndex` went earlier), which is exactly why dec. 6
  keeps the dead entries. So **27 of the addon's 30 `class_name`s are scored by no enforcing arm
  in any register**: 13 are already named from outside, and **16 are undeclared**. Every one of
  those 16 is a criterion-4 row payable tomorrow by writing a bare name, with all five registers
  staying green — the precise move dec. 2 forbids. The rule currently rests on a reader having
  read it.
  The instrument is nearly free: `named but NOT declared` is **already computed and printed**
  (5 rows — `DynamicGeometryBuilder`, `MapStateSelector`, `MapTextureAnimator`, `PlayerCamera`,
  `Tile`), and turning that direction ENFORCING at a burn-down of 5 guards dec. 2 exactly.
  ADR-0196 dec. 4 made the declared-set report REPORTING, but its stated reason —
  *"enforcing that direction would make deleting a host call site red this guard"* — is about
  **declared-but-unnamed**, the opposite direction, and says nothing about this one. Not built
  here: ADR-0192 dec. 1 forbids editing a scanner in a pass that moves its population, and this
  pass moved criterion 4 six rows. Filed as
  [#713](https://github.com/timbermania/fft-monorepo/issues/713), and the register goes first
  there as it did in ADR-0205.
  ✅ **BUILT — `check_lattice_publish` arm 3**, alone in its own commit and before anything
  drains it. It reads the baseline this bullet predicted: **5 names over 44 sites**, all five
  under `tests/`, each with an owner and the pass that closes it. Two facts the bullet did not
  have. First, the arm scans the WHOLE corpus rather than arm 1's roots: arms 1 and 2 split
  `tests/` off and score nothing there, so a criterion-4 row in a test file — there are six
  today — was otherwise payable by re-spelling it as a bare name in the same file, in the one
  place no enforcing arm looks. Second, the arm's key is the NAME, not the site. Arm 1 counts
  couplings, so `(file, symbol)` is right for it; arm 3 asks whether a host MAY compile against
  a symbol at all, where one namer is the whole defect and a per-site key would manufacture rows
  that close by re-numbering lines. Seven seeded direction tests, including both closure routes
  — the last host namer going away, and the name being DECLARED, which is a legitimate payment
  under dec. 2 and is gated by dec. 6 one level up.
  This is what the three payments above rest on today, and they are clean: `MapIlluminationDDA`,
  `MapGridOverlay` and `PaletteTextureGenerator` are all declared, checked rather than assumed.
- The register still cannot see a rename. Criteria 1–4 all score spellings of a reach, so a pass
  that renames anything owes a full suite rather than five green registers.

## Alternatives rejected

- **Close the five re-spellable rows by naming their types, regardless of publication.** Rejected
  in dec. 2: it is the fraud the register cannot see, and two live sites prove the hole is real
  rather than theoretical.
- **Rule ALL re-spelling a fraud, published or not.** Rejected in dec. 2: it would mean the addon
  publishes ten names no host may use, and it contradicts ADR-0206, which closed criterion 1 by
  creating exactly such a name.
- **Build the mount rig to reach the camera's `static func`** (`instantiate()`, call, `free()`, as
  the handoff proposed). Rejected in dec. 1 on measurement: the call is a no-op, `instantiate()`
  is unnecessary, and doing it throws eight script errors in a bare tree.
- **Bind the `camera.*` slugs inside the camera test.** Rejected in dec. 1: the panel is a pure
  view over strings, so this would pass without PlayerCamera's real defaults and hints ever
  driving the rows, which is the whole subject of the test.
- **Delete `build_illumination` and the DDA machinery.** Rejected in dec. 5: documented, reasoned,
  tested retention; the register does not get to drive that.
- **Publish `TileOverlayColor` / `TileOverlayCompositor`.** Rejected in dec. 8: nothing wants those
  names except the tests that name them, which is publication as bookkeeping.
- **Narrow criterion 4's walk to drop `tools/`.** Rejected in dec. 3: it closes two rows by making
  the register blind, and it is how a future tool reach would go unseen.
- **Build a third `DECLARED_*` category for standalone entry points.** Rejected in dec. 3: after
  dec. 2 and dec. 4 it would be created empty.
- **Fix `check_lattice_scene`'s comment blindness in this pass.** Rejected in dec. 7: every commit
  here moves its population, and ADR-0192 dec. 1 forbids editing a scanner alongside one.
