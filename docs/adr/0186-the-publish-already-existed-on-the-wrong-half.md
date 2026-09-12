# The publish already existed — on the wrong half of the emit

Extraction #3's **isolation pass**, the half loop pass 6 did not build. Pass 6 landed the
*address* ([ADR-0184](0184-the-address-lands-and-arm-1s-debt-is-named-rather-than-hidden.md));
`addons/exmateria_battlefield/` existed and **was not isolated**. This pass builds
[#590](https://github.com/timbermania/fft-monorepo/issues/590) and
[#589](https://github.com/timbermania/fft-monorepo/issues/589), which together take
`Battlefield`'s scored outbound debt — ADR-0157 dec. 2's measurement, the thing that made
this system the one extraction #3 chose — to **zero**.

The finding is not the severance. It is that **#589's enabling measurement was true of the
symbol and false of the site**: *"`TileCursor` already emits `cursor_moved` on the line
above its `SfxRouter` reach"* is correct, and inverting the cue onto that signal would have
added a cursor-move sound to every programmatic reposition, because `cursor_moved` has
**two** emit sites and the cue sat below exactly one of them.

Status: accepted (2026-08-26). Extraction #3, isolation pass, on map
[#560](https://github.com/timbermania/fft-monorepo/issues/560). Builds
[ADR-0175](0175-a-port-answers-arm-1-and-not-arm-2-and-the-debug-residue-was-print-statements.md)
dec. 4 and dec. 5, which decided both shapes and deliberately built neither. Gated on
ADR-0184 dec. 4's burn-down, which is what made a split pass possible at all.

> ⚠️ **`0186`, not `0185`.** The collision trap's sixth firing.
> `godot-learning/docs/adr/` has a clean high-water mark of `0184` across every remote ref
> and every local worktree — but `origin/research/map-to-disc-delivery-361` holds
> `docs/adr/0185-the-addon-ships-a-workspace-and-panels-follow-the-subject.md` at the
> **repo root**, and an `ADR-0185` citation would not resolve. The two directories are
> different namespaces that share one citation space, which is
> [#605](https://github.com/timbermania/fft-monorepo/issues/605)'s subject. Counting only
> the game line's directory is the instrument that has been wrong five times.

## Measurement

Re-derived on this branch at each step, not read out of the handoff.

| | before | after |
|---|---:|---:|
| `check_addon_portability` arm 1 — reaches on `ARM1_BURN_DOWN` | **10** | **6** |
| `autoload_reach.py Battlefield` — *"dec. 2 counts"* | **3** | **0** |
| arm 2 — `Battlefield` host-autoload lines | 65 | **62**, and **all 62 are PORTS** (`Tune` 59, `PSXDisplay` 3) |
| arm 4 — `[shader_globals]` lines under `addons/exmateria_battlefield/` | 5 (4 declare, 1 push) | **4, all declare** |
| arm 4 — pushers of any global in the family | `PSXDisplay` ×5, `PlayerCamera` ×1 | **the port and nothing else** |
| `classify_blueprint` — `assembler` | 20 files | **21** (`Effects` and `Audio` unmoved) |

`Battlefield`'s remaining goal-#5 debt is now exactly three named things: **six arm-1 lattice
reach lines** (ADR-0166 dec. 2/3 ×4, ADR-0164 dec. 1/2 ×2), **62 arm-2 port names** (all
#588's), and **four arm-4 declarations**, which nobody owns.

## Decision

**1. #590 lands on `PSXDisplay`, not on `DisplayCalibration`.**

ADR-0175 dec. 4 names the target `DisplayCalibration.set_camera_angle()`. That spelling is
[#583](https://github.com/timbermania/fft-monorepo/issues/583)'s rename and has not run.
Waiting would put a **one-line** fix behind a **27-file, 90-line** symbol rename that
#583's own Ordering section says *"blocks nothing"*; landing now costs that rename one more
line in a sweep it already carries. ADR-0171 dec. 4 made the rename a follow-up precisely
so it could be reviewed on its own diff, and that argument runs in this direction too.

**2. `DebugConfig.psx_camera_angle_12bit` was not a debug flag, and its two READERS are
what proves it.** The value is written every frame by `PlayerCamera` and read by
`Unit._build_view` (`Battle`) and `CameraRelativeRenderer` (`Sprite Rig`). A `Debug`
autoload hosting live camera state for two other systems is a global variable with a
misleading address. Both halves — the `RenderingServer` push and the mirror — are
`PSXDisplay.set_camera_angle()` now, beside the five globals that port already pushed.

**3. 🔴 THE PUSH HALF OF A GLOBAL SHADER PARAMETER IS NOT ASSERTABLE FROM GDSCRIPT, and
finding that out is the reason the mirror exists at all.**

`CameraAnglePortTest` arm 2 was written as
`global_shader_parameter_get(&"psx_camera_angle") == PROBE`, on the reading that
`TunePsxParTest`'s comment only claims the getter is null for **boot defaults** that never
went through the RenderingServer registry — so a value pushed one line earlier should read
back. It does not. The engine raises *"This function should never be used outside the
editor, it can severely damage performance"* and returns `null` unconditionally at runtime.
Editor-only means editor-only, and the mirror is the whole reason this codebase does not
call it.

So the push side has a different owner, and it already had one. `check_addon_portability`
arm 4 reads **both** sides of every `[shader_globals]` name — the declaration and the
`global_shader_parameter_set` — which is the hole ADR-0171 dec. 5 opened after ADR-0169
dec. 5 specified a declaration-only scan. After #590 that arm names the port and nothing
else, which is the sentence *"the port is the only pusher"* in the one instrument that can
say it. The test arm is replaced by a note pointing there rather than by a weaker assertion.

**4. 🔴 THE `SfxRouter` INVERSION NEEDED A NEW SIGNAL, because `cursor_moved` fires from
two sites and the cue sat below one of them.**

#589 lists as an enabling measurement: *"`TileCursor.gd:519` emits `cursor_moved` on the
line immediately above the reach"*, and concludes *"the `SfxRouter` publish already
exists."* The first clause is true. The second does not follow. `cursor_moved.emit` also
appears at `TileCursor.gd:404`, inside `move_to` — *"Host scenes call this after the map
has been built so the cursor starts on a valid tile"* — and `CursorController` and
`FormationMapHost` both consume it. Connecting `SfxRouter.play_cue("ui.cursor_move")` to
`cursor_moved` would have played a cursor-move sound on every programmatic reposition:
a behaviour change wearing a refactor's clothes, invisible to every guard, and audible.

`cursor_stepped` is the published surface instead — the PLAYER moved the cursor, by
pressing a direction. It is emitted from `_try_step` only, which is exactly the set the cue
had. **The general form: a signal is a publish of the EVENT, and "there is already a signal
on the line above" is a claim about one emit site, not about the signal.** Check the emit
set, not the neighbouring line.

**5. The wiring block is ONE class, split by SUBJECT rather than by consumer system, and it
is booked `assembler` — which is what keeps the delta attributable.**

`src/scenes/BattlefieldWiring.gd`, with `wire_map(composer)` and `wire_cursor(cursor)` —
an assembler in [ADR-0134](0134-the-studio-is-an-assembler-and-the-assembler-is-one-file.md)'s
sense, a composition that *"wires once and leaves"*.
#589 refused ADR-0167's consumer-side shape.
Its own words for why — *"two new classes for three assignment statements is the shape this
map keeps warning about"* — are the TICKET's, not that ADR's. This paragraph attributed
them to the ADR at first and `check_adr_quotes.py` caught it, which is the one instrument
that checks WHAT a citation says rather than where it points. Splitting by subject gives
one class and one call per thing the host owns.

The booking is the load-bearing half. **ADR-0167's own severance first read as GROWTH**
(`→ Debug` 42 → 47) because the class the fix was written in got booked to the bucket it
was draining, and #589 restates that trap as a warning to `classify()` any new file before
believing a delta. `assembler` is not one of the eleven systems, so no system's reach count
moves for this file — measured, not assumed: `assembler` 20 → 21 files with `Effects` and
`Audio` byte-identical. The precedent is `classify_blueprint`'s own, three lines below the
new rule: ADR-0135 dec. 10 moved three `*Boot.gd` wiring files out of `UI` for the same
reason, and `CompositorAutopilot.gd` is booked there on identity.

**6. Every map seam publishes BOTH a replay and a signal, and neither alone is correct.**

`MapComposer.map_materials()` + `map_material_created`, `map_gradient()` +
`map_gradient_resolved`.

- **Connect-only is wrong** because `dynamic_geo_builder` is constructed *inside*
  `_build_map`. Nothing outside the addon can subscribe before the first materials and the
  first gradient exist, and children `_ready` before parents, so a composer embedded in a
  root's scene has already auto-built by the time the root runs.
- **Drain-only is wrong** because `_create_material` is lazy, per surface type, on every
  `rebuild_mesh` — including the ones a doodad add/remove triggers long after composition.

Both signals are published by `MapComposer` rather than by the file that computes them,
because the builder is **replaced** on every `_build_map`: a subscriber bound to the
builder would silently drop on the next map change. The composer forwards.

`map_gradient()` returns an **empty** array until a manifest resolves one. *"No gradient"*
and *"the fallback gradient"* are different facts, and the wiring must not paint the
composer's fallback blue over a host that has not composed a map.

**7. 🔴 THE TICKET'S CALL-SITE COUNT WAS OFF BY MORE THAN A FACTOR OF TWO, and every missed
site is a SILENT loss.**

#589 says the block is *"called from the scene roots that compose a map"*, on the
`MapDebugPanels.register_map_panels` precedent — **six** roots. The real subject:
**110 scenes** contain a `MapComposer` node, and **eight** script hosts hold one
(`GPUArena`, `EffectViewerScene`, `ProgressionTester`, `TrapViewerScene`,
`UnitAnimationViewerScene`, `ScenarioPlayerScene` — which `NavigatorMain` inherits —
plus `tests/GPUCombatTestBase.gd`, which ~95 GPU tests and `FireCastReproScene` inherit,
and `GambitScenarioRunner`). Two of those eight never called `register_map_panels` at all,
so the precedent could not have found them.

This is the cost the inversion actually has, and it is worth stating in the currency that
matters: a missed site does not error. The map simply stops tinting during effects and the
sky keeps its fallback. That is why the wiring has a behavioural test and not only a guard.

**8. THE "WIRING TWICE" ASSERTION CANNOT FAIL, so it is deleted rather than shipped.**

An arm was written to pin idempotence — wire the same composer twice, assert one connection
per signal. Seeded with both `is_connected` guards removed, it still read 1 and 1: **the
ENGINE refuses a duplicate connection** (*"Signal 'map_material_created' is already
connected to given callable"*). The invariant is Godot's, not `BattlefieldWiring`'s, and an
assertion on it is a tautology dressed as coverage — this repo's `✅`-that-cannot-report-the-
event defect (#534 arm 2) arriving in a new spelling. What the guards do buy is the absence
of two `ERROR` lines per re-wire, and roots do re-wire; that is a log-surface property and
the suite's error grep is its instrument.

**A SENTINEL, NOT A BEFORE-READING**, for the same class of reason. The arm asserting an
unbuilt composer pushes nothing first read the overlay's *current* gradient and asserted it
did not move — and it was inert: seeded, the fallback got pushed and the arm still passed,
because the overlay's boot state already **was** that fallback. Two different facts compared
equal. It pins a colour nothing else in the tree uses now.

## The suite

**684 / 691, THREW 0, 28.4 min at `-N 4`** — the same 684 pass-6 measured, over two more
tests (both new here, both PASS). Seven non-PASS, and none of them is this pass's:

| test | verdict | |
|---|---|---|
| `GambitScenarioRunnerTest` | HUNG | ADR-0184's known, unowned. **Re-run serially, 600 s, 0 `SCRIPT ERROR`** — it reaches "GPU battle configured with 3 units", well past the `wire_map` call this pass added to it, so the edit is not the cause |
| `GPUEvasionMixedTest` | HUNG | ADR-0184's known, unowned |
| `WorldMapMountTest`, `WorldMapPrimitivesTest` | NO_VERDICT | `[SKIP]`, #586 item 3 |
| `GPUStatusInflictTest` | FAIL | **PASSES serially** |
| `EffectStudioTextureTabTest` | FAIL | **PASSES serially** |
| `SpuClippingMetricsTest` | FAIL | **PASSES serially** |

ADR-0184 warned that *"the FAILED set is not stable"* — its run's single FAIL was
`EffectStudioColourColumnTest`, which passes serially. This run has three, all different,
all passing serially, and none overlapping with that one. **The parallel FAIL set is noise
with a changing membership, and reading it as a regression signal is the error the warning
exists to prevent.** The stable population is the four HUNG/NO_VERDICT knowns.

## Consequences

- **Goal #5 is still open, and its remainder is now three owned-or-unowned things** rather
  than a mixed list. Arm 1's six are the lattice work (ADR-0166 dec. 2/3, ADR-0164 dec. 1/2)
  and ADR-0184's two owed registers belong with them. Arm 2's 62 are entirely #588's, and
  every one of them names a **port** — which is the first time that sentence has been true.
- **Arm 4's four declarations have no owner and no decision.** ADR-0169's Consequences call
  that *"pass 6's call"* and pass 6 did not make it; this pass has not either. The three
  candidate answers are unchanged: document-and-accept, push through the port, or design
  away (a non-global uniform / `ShaderMaterial` parameter). It is the hardest of the three
  because a missing `global uniform` is a **compile** error with no GDScript stack.
- **`Battlefield` gained published surface**: `cursor_stepped`, `map_material_created`,
  `map_gradient_resolved`, `map_materials()`, `map_gradient()`. The addon is +91 lines,
  nearly all of it interface and the reasoning above.
- **`BattlefieldWiring` is a new obligation on every future map host.** A ninth script that
  embeds a `MapComposer` and forgets the call loses tinting silently. Nothing mechanizes
  that yet; a guard over "scenes containing a `MapComposer` whose root script reaches
  `wire_map`" is the shape, and it is not built here.
