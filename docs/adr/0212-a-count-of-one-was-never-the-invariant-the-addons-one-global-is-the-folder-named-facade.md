# A count of one was never the invariant — the addon's one global is the folder-named façade

`exmateria_render` already declares exactly one global `class_name`. It is `FoldSurface`, and it
collides in a consumer's project as readily as any of the thirty `exmateria_battlefield` shed under
[ADR-0211](0211-nothing-preloads-in-so-the-class-name-set-is-the-whole-surface.md). The three
finished addons are safe because their surviving name is **brand-prefixed and named after its
folder** — not because it is singular. This ADR states that as the invariant and applies it to the
three addons ADR-0211 dec. 8 left out.

Status: accepted (2026-08-30). Loop **pass 18** of extraction #3, on map
[#560](https://github.com/timbermania/fft-monorepo/issues/560). Settles
[#718](https://github.com/timbermania/fft-monorepo/issues/718) (render),
[#719](https://github.com/timbermania/fft-monorepo/issues/719) (platform) and
[#720](https://github.com/timbermania/fft-monorepo/issues/720) (schema). **Overturns two things in
ADR-0211** — dec. 8's deferral, and its rejection of *"Generalise the rule to every addon in the
monorepo"* — both of which rested on the same ground, that schema and platform were unmeasured.
They are measured below. Follows the shape the repo-root
`docs/adr/0003-an-installed-addon-owns-five-global-names.md` built for `exmateria_sound`. Rules the
**symbol** axis only — see dec. 4.

## Context

### The measurements ADR-0211 dec. 8 said did not exist

Taken on `main` @ `449049a1d`, over `src tests tools addons assets`, `--include=*.gd`. The
"host script preloads" column is **ADR-0211's own criterion**, verbatim from its Context: *"the same,
from inside the addon"* counts addon-internal, and the host row is `preload()`/`load()` of a `res://`
path into the addon **from a host `.gd`**.

| addon | globals | host `.gd` script preloads | complete symbol close? | alias cost |
|---|---|---|---|---|
| `exmateria_platform` | 3 | **0** | **yes** | 25 lines / 21 files / 191 sites |
| `exmateria_render` | 1 | **0** | **yes** | **4 lines / 4 files / 17 sites** |
| `exmateria_schema` | 6 | **16** | no | 129 lines / 99 files / 391 sites |
| `exmateria_sound` ✅ | 1 | **48** | **no — and it shipped anyway** | — |
| `exmateria_battlefield` ✅ | 1 | 0 | yes | ≤82 |
| `exmateria_spu` ✅ | 1 | 0 | yes | — |

Per-name reach, host `.gd` files naming it outside its own addon:
`Fold` 61 · `DepthMode` 32 · `TerrainCell` 32 · `ColorStack` 28 · `ColorRecipe` 20 ·
`PsxNum` 19 · `CellMarking` 10 · `FoldSurface` 7 · `TunePort` 7 · `DisplayPort` 3.

### Render's four "path reaches" are not symbol reaches, and reading them as ones inverts the table

A count of files naming `res://addons/exmateria_render/` returns four, which looks like the
open channel schema has. It is not. Read:

    src/scenes/DepthDebugScene.gd:16   const DEBUG_SHADER = preload(".../debug/depth_debug.gdshader")
    tests/FoldQuantizePolicyTest.gd:29 const RESOLVE  := ".../fold_bracket/foldsurface_resolve.glsl"
    tests/FoldSurfaceTest.gd:21,22     const SEED_GLSL := "…"  const RESOLVE_GLSL := "…"
    tests/ShaderCompileTest.gd:39,40   "…foldsurface_seed.glsl", "…foldsurface_resolve.glsl"

One loads a **Shader resource**; three are plain **String** constants handed to a compute pipeline.
**None loads a script.** Render's symbol surface is exactly `{FoldSurface}` — the identical shape to
the zero ADR-0211 measured for battlefield. Render is a *complete* close, and the addon is two `.gd`
files total.

### `exmateria_sound` disproves complete-close as a precondition

The obvious argument for keeping dec. 8's deferral, once *"a façade there would wrap a namespace in
a namespace"* is set aside, is that battlefield's façade was a **complete** close because nothing
preloaded in, and schema's is not because sixteen lines do. That argument does not survive one
measurement: `exmateria_sound` reads **48** host script preloads. It went 148 globals → 1 under
`#383` and the repo-root ADR-0003, and it is the precedent every one of these ADRs cites. Its close
was never complete on this criterion.

So complete-close has never gated a façade here. It is a **description of scope** — worth stating so
a reader knows what a façade did and did not shut — and not a precondition. The precondition is the
collision hazard, and that is identical across all six addons: Godot has no package scope, so a
consumer declaring a colliding name makes the **addon's** file fail to parse.

### Schema's sixteen are not a blocker; they are the cheapest sixteen of its own migration

Every one of the sixteen already binds a file-local name:

    src/effects/PaletteSubsystem.gd:26  const ColorStackClass = preload(".../colour_model/ColorStack.gd")
    src/units/Unit.gd:16                const DepthModeScript = preload(".../compositing_key/DepthMode.gd")
    tests/ColorStackTest.gd:14,15       const Recipe = preload(…)   const Stack = preload(…)

The migration rewrites the right-hand side to `= ExMateriaSchema.ColorStack`. That is the **same
edit**, not a prerequisite for it — and performing it drives this addon's host-preload count to
**0**, closing the channel dec. 8 described as staying open. Only three of the six names appear
here at all (`ColorStack`, `ColorRecipe`, `DepthMode`); `Fold`, `CellMarking` and `TerrainCell` have
no path channel to close.

### The cross-addon edge is the dominant case, it is already declared, and it already passes

`exmateria_battlefield` names nine of the ten globals in scope: `Fold` in 9 of its files,
`CellMarking` in 6, `TunePort` in 6, `DepthMode` in 4, `TerrainCell` in 4, `ColorStack` in 3,
`ColorRecipe` in 3, `DisplayPort` in 2, `PsxNum` in 1. `exmateria_render` names `Fold` at five code
sites in `FoldSurface.gd`. Only `FoldSurface` has no sibling namer at all.

This is not a hazard to clear before the work; it is a **declared** relationship with two
instruments already on it:

- `addons/exmateria_battlefield/plugin.cfg` carries `deps="exmateria_schema exmateria_platform"`
  and `addons/exmateria_render/plugin.cfg` carries `deps="exmateria_schema"`
  ([ADR-0194](0194-a-test-belongs-to-the-addon-it-can-run-without-the-game.md) dec. 7).
  `tests/stranger/shared/rig.sh` derives `DEPS` from that line and stages the siblings.
- `tools/check_addon_portability.py` runs **rc=0** on this tree and prints all 21 cross-addon reach
  lines under its own verdict: *"name no sibling addon's class_name outside the kernel and the port
  (goal #5)"*.

### The register was already N-addon, one generation up

`tools/check_addon_globals.py` was lifted from `exmateria-sound/tools/check_globals.py` (ADR-0211
dec. 6) and **narrowed** on the way: the ancestor carries

    FACADES = {
        "exmateria_spu": "ExMateriaSpu",
        "exmateria_sound": "ExMateriaSound",
    }

iterated by every arm, while the descendant hardcodes `ADDON = "exmateria_battlefield"` and
`FACADE = "ExMateriaBattlefield"`. Widening it back is restoring its own design, not inventing one,
and it does not touch the *lifted, not imported* precedent — there is still no cross-package import.

🔴 **One control does not survive the widening as written.** `test_check_addon_globals.py` asserts
`len(cag.gd_files(ADDON_DIR)) > 40` to prove the creep arm is not passing vacuously.
`addons/exmateria_render/` holds **two** `.gd` files. Copied unchanged that control asserts something
false; dropped, the arm can pass over an empty scan. It becomes per-addon, each floor derived from
the addon it guards.

## Decisions

**1. Every addon declares exactly one global `class_name`; it is `ExMateriaX`; and it lives in
`addons/exmateria_x/exmateria_x.gd`.** Not a count, not merely a prefix. `ExMateriaFoldSurface`
would be branded and still not a namespace, and would leave render nowhere to publish a second name.
The stronger form is already what the shipped guard asserts — `arm_rot` fails when
`class_name {FACADE}` is not in the file named after the folder — and already what all three
finished addons satisfy.

- *Render's fix is therefore a façade, not a rename.* A namespace holding one constant is uniform
  rather than silly, and it costs **four alias lines**. The cheaper-looking rename is cheaper by
  approximately nothing and buys a name that cannot grow.

**2. Complete-close is a description of scope, never a precondition for a façade.** `exmateria_sound`
shipped one with 48 host script preloads standing. What a façade closes is the **symbol** channel;
whether other channels were also empty is worth stating and is not a gate. Any future ruling that
defers a façade because a path channel is open is refuted by this decision and by the sound
precedent, and must find a different argument.

**3. ADR-0211 dec. 8's deferral is overturned. `exmateria_schema` (6) and `exmateria_platform` (3)
take façades, and so does `exmateria_render` (1).** Dec. 8's stated reason — a façade there *"would
wrap a namespace in a namespace"* — does not survive the numbers: schema is ten files and six types,
and `ExMateriaSchema.TerrainCell` reads exactly as `ExMateriaBattlefield.Lattice` does. By the
collision risk that motivated `#717`, schema's names are the **worse** offenders: `Fold`,
`ColorStack`, `DepthMode`, `CellMarking` and `ColorRecipe` are generic English, and `DisplayPort` is
the name of a hardware standard, where `Lattice` / `MapIlluminationDDA` / `TileOverlayConfig` were
distinctive.

- *Schema's sixteen preloads are members of the alias set, not a blocker.* They are rewritten in the
  same pass and the channel closes as a consequence (Context above).
- *ADR-0211's `Alternatives rejected` entry "Generalise the rule to every addon in the monorepo" is
  reversed on the same ground it was taken.* Its argument was that *"neither schema nor platform has
  been measured the way this ADR measures battlefield."* Both now are, by the same instrument, in
  the table above.

**4. This ADR rules the SYMBOL axis alone, exactly as ADR-0211 dec. 3 does.** "Internal" means "no
global symbol", never "unreached". The `.tscn` `path=`/`uid=` channel remains
`check_lattice_scene.py`'s criterion 4
([ADR-0205](0205-a-path-reach-is-the-same-axis-as-a-type-reach.md)); the autoload and host-global
channels remain `check_addon_install.py`'s
([ADR-0202](0202-installable-is-the-fork-plus-the-kernel-and-the-port.md) dec. 1).

**5. The shader `#include` channel is OUT OF SCOPE, and is stated rather than left silent.**
Roughly twenty `#include "res://addons/exmateria_platform/…"` lines reach in from `assets/shaders/`
and from `exmateria_battlefield` (`psx_par`, `psx_dither`, `psx_camera_angle`,
`psx_sprite_stretch`), and roughly twenty more into `exmateria_schema` (`psx_ot_depth`,
`psx_color_stack`). A `.gdshaderinc` declares no `class_name`, so it carries none of the collision
hazard this ADR is about, and no GDScript constant can route a preprocessor include.

- 🔴 *Said out loud because the alternative is a fourth re-measurement.* ADR-0211's title claims the
  `class_name` set is the whole surface. For these two addons that is false in a way it was not for
  battlefield, and a reader who discovers the includes without this paragraph has to work out
  from scratch whether they were missed or dismissed. `tools/check_addon_portability.py` arm 3
  already scores the direction that matters — an `#include` **out** of an addon
  ([ADR-0169](0169-platform-ships-to-its-own-address-and-shipping-a-file-is-not-shipping-a-shader.md)
  dec. 5).

**6. `tools/check_addon_globals.py` widens to a `FACADES` dict over four addons, with a per-addon
burn-down, and it lands ENFORCING before any `class_name` moves.** This is
[ADR-0192](0192-the-register-goes-first-because-the-port-erases-its-own-baseline.md) dec. 1's build
order, and it restores the shape of the guard's own ancestor. Seeds: battlefield **0** (drained),
platform **3**, schema **6**, render **1**. Shrink-only, named lists never filters (`#424`), both
directions scored on all three arms.

- 🔴 *It is enforcing on every verification pass the moment it lands.* `run_tests_parallel.py:377`
  runs preflight as `run_all_tests.sh --preflight-only`, and `run_all_tests.sh:303` calls this
  guard. The three new burn-downs are therefore seeded **in the same commit** that widens the dict —
  a widened dict with unseeded burn-downs reds preflight, and an early-aborting preflight hides
  every guard behind it.
- *The vacuity control becomes per-addon.* A flat `> 40`-file floor is false for render's two files.
  Each addon's floor is derived from the addon it guards and stated beside it.

**7. Arm 3 covers all four façades, and a citation MAY name a sibling addon provided it says so.**
The published-name rot arm — presence of a `## Host use:`, the cited `.gd` exists, and it still
names the symbol ([ADR-0210](0210-a-stated-host-use-was-green-and-twenty-times-understated.md)
dec. 1, rebuilt on this channel by ADR-0211 dec. 5) — applies unchanged. But schema's heaviest
consumers are inside `exmateria_battlefield`, so a rule requiring a `src/` citation would leave
`Fold`'s most load-bearing use uncitable.

- *Such entries carry the words **sibling namer**,* the way ADR-0211 dec. 5 made test-only entries
  carry **test-only namer**, so a reader can tell an addon consumer from a host one at a glance.
  The relationship is already declared in `plugin.cfg` `deps=` and already staged by the rig, so the
  citation records something checked rather than something assumed.
- *Landing three façades with the rot channel unwatched is refused.* That is precisely the defect
  the repo-root ADR-0003 was written for: an 18-key façade settled with one of its keys already
  deleted.

**8. The schema façade costs this addon its 3-of-4 stock loading, that cost is ACCEPTED, and
`plugin.cfg` is corrected in the same commit.** `compositing_key/Fold.gd:36` holds
`const FOLD_LAYER := preload(".../fold_layer.tres")`, a `CompositorRenderLayer` stock Godot does not
have, so on stock it is a parse error. A façade preloading all six members cascades that failure to
the façade file, and the addon goes from three members loading on stock to none.

- *The addon is already declared `engine="fork"` wholesale,* and the finer fact is a good property
  rather than an invariant anything enforces. What is refused is leaving `plugin.cfg`'s comment
  standing while it asserts *"one member is what makes this addon fork-only, which is the shape a
  downgrade would have to attack"* about a tree that no longer holds.
- *The repair is filed, not bundled:* [#721](https://github.com/timbermania/fft-monorepo/issues/721)
  makes the layer lazy behind `load()`, whose path-keyed cache preserves the shared-`ObjectID`
  guarantee `Fold.gd`'s own comment depends on. It is not a prerequisite, and a semantics change to
  the fold's shared layer does not belong inside a 129-line alias migration.

**9. `check_addon_portability`'s cross-addon report goes coarser, this is RECORDED, and the repair is
filed.** Today it resolves each reach to a name and a line —
`TileCursor.gd:273  Fold -> declared in addons/exmateria_schema`. After the migration those bare
types are file-local aliases the guard cannot see, and each file collapses to one row naming
`ExMateriaSchema`: 21 rows naming a symbol become ~19 naming a folder.

- 🔴 *This is the reverse of ADR-0211 dec. 4's prediction, and the difference is which side you stand
  on.* Dec. 4's *"Aliasing makes coupling more visible, not less"* is true for the **host**, where a
  coupling was a bare type naming nothing. It is false for this **guard**, which already resolved
  bare types to a declaring addon. Both readings are correct about different subjects, and recording
  only the flattering one is how an instrument's row count later drops with no explanation on file.
- [#722](https://github.com/timbermania/fft-monorepo/issues/722) teaches arm 1 to read through
  `const X = ExMateriaSchema.Y`, which restores per-name resolution and improves on today's output
  by naming the published symbol. Not built here: it is a fourth instrument, and bundling it makes a
  verification pass unreadable.

**10. Three PRs on one stack, ascending cost, and PR 3 discharges ADR-0211 dec. 9's owed run.**

| PR | contents | bar |
|---|---|---|
| 1 | the widened register (own commit, four burn-downs seeded) **+** `#718` render — 4 lines / 4 files | ADR-0211 dec. 9's bar |
| 2 | `#719` platform — 25 lines / 21 files | ADR-0211 dec. 9's bar |
| 3 | `#720` schema — 129 lines / 99 files, +13 battlefield, +1 render, `plugin.cfg` amended | **+ full `run_tests_parallel.py -N 4`** |

- *Render is deliberately first.* Four lines on a two-file addon proves the widened register
  end-to-end, red-green, before 154 more lines ride on it.
- *Schema is deliberately alone.* It is larger than battlefield's entire migration, it carries dec.
  8's `plugin.cfg` amendment, and it reaches into two sibling addons.
- *The bar named in the table* is ADR-0211 dec. 9's list: warm `--import` parse check, all five registers,
  all four stranger rigs, and a scoped run derived by `scoped_tests.py`. Never `--no-preflight`.
- 🔴 *PR 3's full run pays two debts at once.* ADR-0211 dec. 9 recorded a full suite as **owed** and
  unrun, because the GPU was held at 29 of 32 GB and two attempts returned 609/709 and 624/709 with
  different failing names each time. It is still held — 28,042 of 32,607 MiB by `VLLM::EngineCore`
  at the time of writing — so the run is `-N 12` if it frees and `-N 4` if it does not. Because it
  executes on a tree carrying the merged battlefield migration, a clean result discharges dec. 9.

**11. This ADR rules the four `godot-learning` addons. `exmateria_sound` and `exmateria_spu` stay
ruled by the repo-root `docs/adr/0003-an-installed-addon-owns-five-global-names.md`.** They live in
another package and are enforced by that package's own `tools/check_globals.py` — the very guard
whose `FACADES` shape dec. 6 restores. Restating the invariant over them here would put two rulings
and two instruments on one population across a package boundary.

- 🔴 *And the two corpora share one number space,* so a bare `ADR-0003` written in `godot-learning`
  addresses `0003-unit-encode-is-a-single-looped-schema.md`, not the addon-globals one. The root ADR
  is spelled as a path throughout this document for that reason.

## Consequences

- The monorepo's global `class_name` footprint across six addons goes **13 → 6**: `ExMateriaSound`,
  `ExMateriaSpu`, `ExMateriaBattlefield`, `ExMateriaPlatform`, `ExMateriaSchema`, `ExMateriaRender`.
  One per addon, every one brand-prefixed and folder-named, and the invariant is now stated rather
  than observed.
- `grep -rn ExMateriaSchema` becomes a complete census of symbol coupling into the kernel — 99 files
  today, a number no instrument produces now.
- **`exmateria_schema` closes completely.** Its 16 host preloads become façade aliases, so its host
  script-preload count reaches 0 and the channel ADR-0211 dec. 8 described as staying open is shut
  by the same pass that shrinks its globals.
- `exmateria_schema` stops loading any member on stock Godot (dec. 8), until `#721` lands.
- `check_addon_portability`'s cross-addon rows lose per-name resolution (dec. 9), until `#722` lands.
- The shader `#include` channel is unchanged and stays that way (dec. 5). ~40 lines reach into
  platform and schema by preprocessor include and no façade touches them.
- `tools/check_addon_globals.py` becomes the single register for the `class_name` channel of all
  four in-walk addons, replacing the prospect of four near-identical files drifting apart.
- Every remaining `class_name` in `godot-learning/addons/` is a façade, so arm 1's population is
  structurally empty — the shape ADR-0211 dec. 7 had to direction-test for
  `check_lattice_publish` arm 3. The seeds construct their subject rather than borrowing one from
  the tree, for the same reason dec. 7 records.

## Alternatives rejected

- **Rename `FoldSurface` to a branded name instead of giving render a façade.** The handoff that
  framed this work proposed it as *"a different and much cheaper change"*. Measured, it is cheaper by
  nothing: the façade is four alias lines against the rename's four call-site updates, and the
  rename buys a name that is branded but not a namespace — so render's second published symbol,
  whenever it arrives, reopens the whole question. Rejected on dec. 1.
- **Close schema's sixteen path reaches in a preparatory pass, then façade.** They are the same edit.
  A preparatory pass would rewrite `const ColorStackClass = preload(…)` to something, and the only
  something that is not the façade alias is another path spelling. Rejected on dec. 3.
- **Keep dec. 8's deferral and rule only platform and render.** The two complete-close addons are the
  easy half, and stopping there leaves the six worst-colliding names — the ones that motivated the
  question — in every consumer's global scope. The argument for deferring schema does not survive
  `exmateria_sound`'s 48 (dec. 2).
- **Clone `check_addon_globals.py` into three per-addon guards.** Four files stating one invariant
  drift, and the invariant is the thing this ADR exists to state once. The ancestor is already a
  dict. Rejected on dec. 6.
- **Fix `Fold.FOLD_LAYER` inside the schema migration to preserve 3-of-4 stock loading.** It is a
  semantics change to the shared held-out layer, in a PR already touching 99 files. Filed as `#721`
  (dec. 8).
- **Rule all six addons in one document.** Two rulings over one population across a package
  boundary, in a corpus that already shares a number space with the one holding the other ruling.
  Rejected on dec. 11.
- **Fold this into ADR-0211 as an amendment.** ADR-0211 is battlefield-specific by its own title and
  by dec. 8, and `check_adr_shape` caps an ADR at one dated section — a reversal of two of its
  positions plus eleven decisions is not an amendment. Dec. 8 is instead folded in place to state
  the now and point here, which adds no dated section at all.
