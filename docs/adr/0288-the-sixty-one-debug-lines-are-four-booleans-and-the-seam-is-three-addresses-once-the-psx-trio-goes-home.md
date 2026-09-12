# The sixty-one `Debug` lines are four booleans, and the seam is three addresses once the PSX trio goes home

[ADR-0286](0286-extraction-7-is-the-effects-runtime-and-the-studio-that-is-seventy-percent-of-the-bucket-is-a-root-set-that-stays.md)
S3 and [ADR-0287](0287-the-backwards-edge-is-one-misfiled-file-and-the-arm-that-fails-is-the-one-no-selection-ever-ran.md)
S1 both deferred the same item — *"the 61 `DebugConfig` lines are STILL unexamined … nobody
has checked whether they are one port's two signatures or 61 independent decisions."* This
pass read all sixty-one.

**They are neither.** They are **four booleans** — `particle_debug_enabled` ×26,
`iteration_debug_enabled` ×24, `timeline_debug_enabled` ×9, `camera_debug_enabled` ×2 —
**read, never written**, and every one gates a `print`. Two of the four
(`particle`, `timeline`, **35 of the 61 lines**) have no production reader outside this
membership at all: they are `Effects`' own flags wearing a host autoload's name. And the
severance is not a design problem, it is a **transcription**:
`addons/exmateria_sprite_rig/install/RigDebug.gd` already did it for the same autoload, the
same `debug.*` slugs and the same reason, at #744.

Two further things this pass found by reading rather than counting:

**`src/effects/` holds a third kind of misfiled file, and this one is a port.**
`PsxUnits.gd` (121), `CameraCalib.gd` (35) and `PSXCameraConvert.gd` (60) are a closed
216-line triangle whose only outside dependency is `ExMateriaPlatform.PsxNum`. Their own
docstrings say what they are. `PsxUnits.gd:3` — *"The ONE home for PSX continuous-magnitude
↔ game-unit conversions"*; `CameraCalib.gd:3` — *"the thin, CALIBRATED render/camera layer
atop PsxUnits"*; `PSXCameraConvert.gd:8` — *"a thin FACADE over the consolidated seams"*.
All three cite ADR-0091 and none of the three mentions an effect. They are **18 of the 32 game-side inbound lines** to this
membership. Send them to the port and the `Effects` façade stops being asked for camera
arithmetic.

**The `Audio` crossing is fifteen lines, not eleven, and the extra four are the ones no arm
can see.** `EffectInstance.gd:17/20/21` `preload` three scripts by path out of
`addons/exmateria_sound/runtime/` — all three are published on the `ExMateriaSound` façade,
and all three are invisible to every one of the nine arms because the target is inside an
addon root.

Status: accepted (2026-09-11). This is
[ADR-0126](0126-every-system-pass-audits-before-it-designs.md)'s **pass 3** for extraction
#7 — audit the crossings that exist, design the seam, predict the metric. **Corrects
ADR-0286 dec. 8** (the inbound seam is not 44 lines over ~12 addresses; it is 12 code lines
over 3 addresses once the PSX trio and the two authoring roots are set aside) and **records
ADR-0287 dec. 8's crossing as fifteen lines, not eleven**. Everything else in `0286`/`0287`
stands. Reads
[ADR-0091](0091-psx-magnitudes-convert-to-game-units-at-a-single-per-subsystem-seam.md) for
the conversion seam the trio *is*,
[ADR-0124](0124-effects-tells-audio-a-code-and-a-time.md) for the `Audio` crossing,
[ADR-0175](0175-a-port-answers-arm-1-and-not-arm-2-and-the-debug-residue-was-print-statements.md)
dec. 2 and [ADR-0187](0187-the-port-is-two-signatures-and-sixteen-of-the-seventy-eight-were-already-inside-it.md)
for `TunePort`,
[ADR-0211](0211-nothing-preloads-in-so-the-class-name-set-is-the-whole-surface.md) dec. 4 for what arm 5
counts, [ADR-0220](0220-the-addon-that-declares-a-global-uniform-provides-it.md) for arm 4b's
two names, [ADR-0128](0128-a-colour-crossing-is-an-affine-op-with-an-opaque-mode-token.md) for the colour
op the overlays already carry, and
[ADR-0114](0114-refactor-progress-is-two-per-cluster-numbers.md)/[ADR-0131](0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md)
for the metric being predicted. **Supersedes nothing.** Ticket:
[#1191](https://github.com/timbermania/fft-monorepo/issues/1191) (selection
[#1184](https://github.com/timbermania/fft-monorepo/issues/1184)). This pass filed four:
[#1187](https://github.com/timbermania/fft-monorepo/issues/1187) (`psx_gamma`, **blocks pass
6**), [#1188](https://github.com/timbermania/fft-monorepo/issues/1188) (`inside_prefixes`),
[#1192](https://github.com/timbermania/fft-monorepo/issues/1192) (the dead illumination
machinery) and [#1193](https://github.com/timbermania/fft-monorepo/issues/1193)
(`Battlefield`'s sightline query).

## Context

### The nine arms reproduce exactly at `7cddb7934`

`tools/membership_arms.py` over the 67 audited paths as argv, **no `--inside=`** (ADR-0287's
own rule, and #1188's reason):

```
uv run python tools/membership_arms.py \
  $(ls src/effects/*.gd | grep -vE 'CompositorAutopilot|EffectScoreModel|PSXDitherCurves') \
  src/effects/callbacks/*.gd \
  assets/shaders/effect_*.gdshader assets/shaders/effect_*.gdshaderinc \
  assets/shaders/trap_charge_line.gdshader
```

**67 files / 14,441 lines**; arm 1 = 67, arm 2 = 72, arm 2b = 0, arm 3 = 7, arm 4 = 0,
arm 4b = 2 🔴, arm 5 = 63 over 19 rows (shape scan 18), arm 6 = 2, arm 7 = 1 name / 3 lines.
Every figure is ADR-0287's, unchanged. Nothing in this pass rests on a carried number.

### ADR-0126 check 1 — the touch matrix, and what it cannot charge for

`tools/touch_matrix.py` at the same commit: **675 cross-system lines**, of which the
`Effects` **row** is 87 (`Debug` 81, `Battle` 3, `Battlefield` 2, `Render` 1) and the
`Effects` **column** is 25 (`Battle` 14, `Cutscene` 11).

Three of its blind spots bite this membership and all three are load-bearing:

- **`Effects → Audio` reads zero.** `classify_blueprint.py:13` states it: *"`addons/
  exmateria_sound/` is NOT walked — it is a vendored copy."* Extraction #2's pass 3
  measured this same edge at 24 lines while `Audio` was still in the tree. It is 15 today
  and the matrix cannot see one of them. **An extraction makes its own inbound edges vanish
  from the progress bar**, which is a property of the instrument, not of the coupling.
- **`Effects → Debug = 81` is 61 the membership's and 20 the panels' own.** The other 20 are
  `EffectViewerPanel` / `TrapViewerPanel` / `FireCastReproPanel` naming `BaseDebugPanel` and
  `TuneField` — three `src/debug/` files booked `Effects` by `classify_blueprint.py:627/638`'s
  basename-prefix rules (`("Effect", "Effects")`, `("Trap", "Effects")`, `("FireCast",
  "Effects")`) and already ruled non-members by ADR-0286 dec. 3. A panel naming its own base
  class is not this system's crossing.
- **The column is blind to the assembler.** `src/scenes/BattlefieldWiring.gd` holds **6 of
  the 12** real inbound code lines and is booked `assembler`, so it appears in no row and no
  column.

### The sixty-one, read

All 61 sites, four names, zero assignments:

| flag | lines | files | production readers outside the membership |
|---|---:|---:|---|
| `particle_debug_enabled` | 26 | 12 | **none** — `DebugConfig`'s own declaration and one `LoggingDebugPanel` row |
| `iteration_debug_enabled` | 24 | 12 | `src/gpu/CombatLoop.gd` (~30), `Unit.gd`, `ui3/`, `projectiles/`, and `RigDebug.gd` |
| `timeline_debug_enabled` | 9 | 6 | **none** — same two |
| `camera_debug_enabled` | 2 | 1 | `src/debug/GameLogger.gd:48` |

Every site is `if DebugConfig.<flag>:` (or an `and` of it with a local rate-limit) over a
`print`. The three that are not a bare `if` are the same thing spelled for a hot path:
`EffectParticleRenderer.gd:204` and `EffectInstance.gd:539` cache the flag into a local
`_perf_enabled` that gates `Time.get_ticks_usec()` timestamps, and `TrapEffect.gd:430`
caches it into `_log_particles`. Three more (`ParticleSubsystem.gd:345`,
`TrapEffect.gd:853`, `TrapEffect.gd:980`) latch a log-once with `set_meta` / a bool. **No
site changes what the runtime does.**

And the flags are not plain `var`s. `src/debug/DebugConfig.gd:88-90`:

```gdscript
var particle_debug_enabled: bool:
	get: return _dbg_get(false, "debug.particle_debug_enabled")
	set(value): _dbg_set("debug.particle_debug_enabled", value)
```

`_dbg_get` is `Tune.is_registered` + `Tune.bind` + `Tune.get_value`. So the runtime reaches a
host autoload to read a registry the **port already exposes** — which is verbatim the
sentence `addons/exmateria_sprite_rig/install/RigDebug.gd:16-19` wrote for `Sprite Rig` at #744.

### ADR-0126 check 2 — the blueprint's three claims about `Effects`, tested

`docs/context/37-the-blueprint.md` makes three indicative claims about this system's code.
Sorted into ADR-0126's two piles and each given a falsifier:

| sentence | verdict |
|---|---|
| *"Depends on nothing."* (`:37-38`) | **FALSE.** 67 arm-1 lines, 72 arm-2, 63 arm-5, 3 arm-7. Named by ADR-0286 dec. 8; this pass prices the repair. |
| *"`Effects` reads `Audio`'s `feds.bin`."* (`:277-278`, Format owner) | **TRUE.** `src/effects/EffectData.gd:208` — `ExMateriaSound.FedsBank.load_from_file(feds_path)`. The first blueprint measurement in this series to survive its test. |
| *"Role binding … is what keeps `Effects` ignorant of what a combatant is."* (`:385-387`) | **Behaviourally TRUE, syntactically FALSE.** See below. |

The third is the interesting one, and it inverts ADR-0126's own worked example. Every use
the runtime makes of a caster or a target is `global_position`, `add_child`,
`get_instance_id()`, `is_instance_valid()` and — in a debug print — `.name`. That is
*exactly* the blueprint's anchor: *"anchors that answer position and orientation and nothing
else."* `EffectInstance.attach_anchors_to_units(caster: Node3D, target: Node3D)` is already
typed `Node3D`. `set_unit_targets(caster, target)` is untyped. `UnitTintOverlay` never
dereferences the id it is keyed by — `register_unit(unit_id, material)` is called by
`src/units/Unit.gd:730` **with the material**, so the overlay is a registry of tinted
surfaces and `unit_id` is an opaque token.

ADR-0126 cited `PaletteSubsystem`'s `WeakRef` + `get_instance_id()` as *"a real `Battle`
coupling the scan cannot see."* Re-read at this commit, it is the opposite: `get_instance_id()`
is `Object`'s, the WeakRef is held to avoid keeping a freed node alive, and nothing
`Unit`-shaped is ever asked for. **The duck-typed reach is clean and the three things the
scan CAN see are the whole defect** — `caster: Unit, target: Unit` on `EffectManager.gd:48`,
`:132`, `:258`.

### ADR-0126 check 5 — three overlays, re-tested, and now the shape is exact

ADR-0126 check 5 recorded *"three overlays with three different keys, three different remove
verbs and no shared base class."* Still true, and the reading is sharper than a count:

| | `UnitTintOverlay` | `MapTintOverlay` | `ScreenEffectOverlay` |
|---|---|---|---|
| register | `register_unit(unit_id, material)` | `register_material(mat)` | `_find_background_material()` (self) |
| stack | `update_stack(unit_id, owner_id, stack, now)` | `update_stack(owner_id, stack, now)` | `update_layer_gradient(owner_id, top, bottom, tint)` |
| layer | `update_layer(unit_id, owner_id, tint)` | `update_layer(owner_id, tint)` | `set_tint(tint, owner_id = 0)` |
| remove | `remove_layer(unit_id, owner_id)` | `remove_layer(owner_id)` | `remove_layer(owner_id)` / `clear_effect(owner_id = 0)` |
| sweep | `remove_all_layers_for_owner(owner_id)` | — | — |

**`MapTintOverlay` is `UnitTintOverlay` with the surface key erased**, not a different
interface — the map is the single-surface case. `ScreenEffectOverlay` is a third vocabulary
for the same `ColorStack`, and two of its verbs take `owner_id = 0` by default, which is the
shape [ADR-0119](0119-contested-resources-are-capabilities-not-flags.md)'s neighbourhood
calls an optional gate.

### ADR-0126 check 6 — the live set, and four of arm 5's ten debt lines

`PaletteSubsystem.gd:27` says it in the file: *"RETAINED-BUT-UNWIRED (Holy/E015 rev 5):
`build_illumination` + `MapIlluminationDDA` are no longer delivered to the map."* Checked
against the corpus: **`build_illumination` has exactly two callers and both are
`tests/PaletteSubsystemTest.gd`.** `addons/exmateria_battlefield/exmateria_battlefield.gd:133`
documents the host use — citing a caller that is test-only. ADR-0208 dec. 5 declined to
delete live, tested machinery to move a counter to zero, and that was right for a *counter*.
It is a different question for a *move*: ADR-0287 dec. 5 already ruled that **an extraction
must not carry dead code into an addon**.

### The inbound surface, split

`--inbound` plus a per-line attribution over the whole tree, `src/` only, minus the six
`src/debug/` non-members and minus `src/effects/studio/`: **49 production lines**. The unit is the
**distinct line**, so a line naming two members counts once — `EffectViewerScene.gd:23`,
`CombatLoop.gd:1858`, `CinematicManager.gd:46` and `ScenarioCameraDirector.gd:37` each do.
Counted per `(name, line)` instead the same reading is 54, which is why a by-name total and a
by-line total must not be mixed.

| | lines | |
|---|---:|---|
| authoring roots | 17 | `EffectViewerScene.gd` 12 (the studio's assembler), `TrapViewerScene.gd` 5 — both `authoring`/`root` in `ROOT_SET.tsv` |
| game-side, PSX trio | 18 | `PSXCameraConvert` / `PsxUnits` / `CameraCalib`, in `CinematicManager`, `ScenarioCameraDirector`, `Projectile3D` |
| game-side, the rest | 14 | over five files |

Of that last 14, **two are prose** — `src/gpu/CombatLoop.gd:1858` and `src/units/Unit.gd:1090`
are `"""`-docstrings naming `EffectInstance` / `PhaseBlock`, and a `#`-stripper does not eat
a GDScript docstring. ADR-0126 check 1's *"47% was prose"* warning, arriving inside this
pass's own instrument. **Twelve code lines**, over three addresses:

| address | lines | what |
|---|---:|---|
| **spawn** | 3 | `CombatLoop.gd:58` preloads `EffectManager`, `:397` types the field; `CinematicManager.gd:46` preloads `CinematicFacingResolver` |
| **tinted-surface registry** | 5 | `BattlefieldWiring.gd:76-78` register the map's materials, `Unit.gd:730`/`:743` register and unregister the unit's own `ShaderMaterial` — one verb, two callers, two autoloads today (dec. 7) |
| **screen backdrop** | 4 | `BattlefieldWiring.gd:83-85` publish the sky gradient, `ScenarioVM.gd:3610` sets the corners — the latter already a node-path soft-bind (`get_node_or_null("/root/ScreenEffectOverlay")`) and free by ADR-0175's own reading |

## Decision

**1. The sixty-one `DebugConfig` lines are four booleans and they sever by transcription, not
by design.** Add `EffectsDebug.gd` to the addon — statics only, no instance — binding the
four existing `debug.*` slugs through `ExMateriaPlatform.TunePort` and exposing them as
`particle()`, `iteration()`, `timeline()`, `camera()`. The 61 call sites change identifier
and nothing else. `addons/exmateria_sprite_rig/install/RigDebug.gd` is the template and is
followed rather than adapted, including its two non-obvious parts: `_static_init()` binds at
class load (without it every `get_value` asserts, because the slugs used to be bound lazily
by `DebugConfig._dbg_get` and so only if the *host* happened to read first), and the slug
literals are spelled `debug.*` deliberately so the two owners cannot disagree —
`Tune._register` is first-write-wins and two binds of one slug is the supported shape.

**The severance is test-transparent and that is not an accident.** Five tests write
`DebugConfig.particle_debug_enabled = true`; `_dbg_set` routes to `Tune.set_value`, and
`TunePort.get_value` reads the same registry. One registry, two spellings, so no test
changes.

**2. `particle_debug_enabled` and `timeline_debug_enabled` become the addon's, and the host
property becomes a re-export for its panel.** 35 of the 61 lines read flags with **no
production reader outside this membership** — `src/debug/DebugConfig.gd`'s own declaration
and one row each in `src/debug/LoggingDebugPanel.gd`. After the move the addon is the owner
and the host keeps a toggle. The other 26 (`iteration`, `camera`) read genuinely host-wide
flags and are shared with `CombatLoop`, `Unit`, `ui3/`, `GameLogger` and `Sprite Rig`'s own
`RigDebug`; those stay shared slugs, which is what a slug registry is for.

**3. ADR-0286 dec. 8's role binding is three type annotations, and the repair is
`Unit` → `Node3D`.** `EffectManager.gd:48`, `:132`, `:258`. Nothing under them changes: the
parameters are already used as anchors and `attach_anchors_to_units` is already typed
`Node3D`. This takes arm 7 to **0** and `Effects → Battle` in the touch matrix to **0**, and
it is the smallest repair in the extraction — which is worth saying plainly, because
ADR-0126 cited this system as its worked example of a coupling *"the scan cannot see"* and
the scan could see all of it.

The blueprint sentence is not rewritten; per ADR-0126 check 2 it is recorded.
*"Depends on nothing"* is **falsified** and stays in the file with that note until pass 6
makes it true;
*"`Effects` reads `Audio`'s `feds.bin`"* is **confirmed**; *"Role binding … keeps `Effects`
ignorant of what a combatant is"* is **confirmed in behaviour** and fails only on the three
annotations dec. 3 repairs.

**4. `PsxUnits.gd`, `CameraCalib.gd` and `PSXCameraConvert.gd` move to
`addons/exmateria_platform/`, and this is extraction #7's second `git mv` ticket.** 216
lines, one closed triangle, one outside dependency (`ExMateriaPlatform.PsxNum`, already
named at `PsxUnits.gd:35`), zero reach into anything `Effects`. This is the **third** kind of
file misfiled into `src/effects/` — after a studio file (ADR-0287 dec. 2) and a dead file
(ADR-0287 dec. 5), a **port-tier** file. The directory has now mis-sorted three different
ways, which is the case for ADR-0287 dec. 1's *directory rule minus an exception list*
being the permanent form rather than a concession.

Two consequences, both stated up front:

- **It removes 18 of the 32 game-side inbound lines from the `Effects` façade** and takes
  `Battle → Effects` from 14 to 5 and `Cutscene → Effects` from 11 to 1. The host keeps
  calling the same functions at their real address instead of reaching into an effects addon
  for camera arithmetic. ADR-0126 check 4 names the shape:
  *"a **PSX** vocabulary (4096 = a full turn, 28 units per tile) is content wearing an interface's clothes"*.
  Moving the vocabulary to the tier that owns it is the answer.
- **It makes arm 5 bigger.** Members use the trio on ~20 lines over 10 files; under
  ADR-0211 dec. 4 each file gains an alias line and every use site below it scores. Arm 5
  goes from 63 to roughly 93 — **all of the increase free by declared tier** (`port`,
  ADR-0157 dec. 2). The headline number gets worse while the coupling gets better, and
  #1059's tier mechanism is what makes that legible instead of alarming.

**5. The `Audio` crossing is fifteen lines over two files, and eleven of them are one port.**
ADR-0287 dec. 8 priced it at 11 from arm 2. The other four are `EffectInstance.gd:17/20/21`
(`preload` of `exmateria_sound/runtime/effect_sound_controller.gd`, `…/effect_json_loader.gd`,
`…/effect_sound_resolver.gd`) and `EffectData.gd:208` (`ExMateriaSound.FedsBank`, already
correct). **All three preloads name a path inside another package's `runtime/` directory,
and all three are published on the façade** as `ExMateriaSound.EffectSoundController`,
`.EffectJSONLoader`, `.EffectSoundResolver`.

Re-spell all fourteen through `ExMateriaSound`. The verb surface the autoload actually uses
is four — `begin_effect() -> int`, `play_pair(token, bank, pair_idx, sound_id)`,
`end_effect(token)`, `orphan_effect(token)` — which is ADR-0124's *code and a time* with a
cast token, and it is worth naming as that rather than as eleven autoload reaches.

**The trade is ADR-0175 dec. 2's, deliberately repeated**: arm 2 goes to **0** and arm 5's
debt rises by roughly the same amount, converting *"this addon will not parse in a project
whose `project.godot` lacks an `[autoload]` line"* into *"this addon needs that addon
present."* The second is vendorable; the first is an install step. The cost is named here
rather than pocketed, exactly as dec. 2 required.

**6. Six of the eleven `ExMateriaEffectSfx` lines are the studio's, and they are priced as
the studio's.** `EffectInstance.audition_container()` and `audition_sound()` (lines 501, 506,
515, 529, 530, 532) have **no caller outside the studio**: `src/effects/studio/
SoundContainerProjector.gd` and `FedsPairProjector.gd` emit the actions,
`EffectStudioPage.gd:6722-6731` routes them, and `src/scenes/EffectViewerScene.gd:768-783` —
the studio's assembler — invokes them by `has_method`. This is ADR-0287 dec. 2's finding one
level down: not a misfiled file but two misfiled **methods**.

They are **not** moved in this extraction. Duck-typed through `has_method` from the
assembler, they cost nothing to leave, and moving them needs `_live_feds_bank()` and
`effect_data` from outside the class. What is decided is that they are **the studio's five
lines of the fifteen**, so when the studio extracts they go with it, and pass 9 does not book
their removal to the runtime.

**7. `UnitTintOverlay` and `MapTintOverlay` are one registry, and the four autoloads become
two.** `MapTintOverlay` is the erased-key case of `UnitTintOverlay`, so publish one
`TintedSurfaces` autoload:

```
register_surface(surface_id, material)      unregister_surface(surface_id)
update_stack(surface_id, owner_id, stack, now)
update_layer(surface_id, owner_id, recipe)  remove_layer(surface_id, owner_id)
remove_all_layers_for_owner(owner_id)
```

with a reserved `SURFACE_MAP` id, and the payload spelled as the blueprint's **colour op**
(`:349`, ADR-0128 — `{scale, bias, duration, mode_token}`), which both overlays already carry
as `ExMateriaSchema.ColorStack` and which the kernel spells `ExMateriaSchema.ColorRecipe` in
code. *Colour op* is the blueprint's word; this ADR used *"colour recipe"* in its first draft,
which is a rival coinage for a term that already exists — the exact thing pass 4's goal #2/#7
work is for, caught here rather than inherited.
`ScreenEffectOverlay`'s **gradient half** does not fold in — `set_default_gradient` /
`set_corners` publish a background, not a tint — so it stays as a second, narrower autoload,
and its `owner_id = 0` defaults are removed (an optional gate argument is a gate that never
fires).

This takes the host's `[autoload]` obligation from **four lines to two** — `EffectMultiMeshPool`
is already reached by node path (`EffectParticleRenderer.gd:90`, `EngineFoldCompositor.gd:97`)
and needs no bare-identifier entry — and it merges what are today two inbound
addresses — the map's materials and a unit's — into one **tinted-surface registry**.

**8. Arm 5's ten debt lines are four different answers, not one number.**

| symbol | lines | verdict |
|---|---:|---|
| `ExMateriaBattlefield.MapIlluminationDDA` | 4 | **production-dead.** `build_illumination`'s only callers are two tests. Delete the machinery under ADR-0287 dec. 5's rule; the 4 lines go to 0 and the shipped game does not change. **#1192**, not a silent deletion — ADR-0208 dec. 5 declined this once and is owed the argument. |
| `ExMateriaRender.FoldSurface` | 3 | **honest and it stays.** `Render` owns the display-space scratch lifecycle (ADR-0074); `EngineFoldCompositor` installs one. `Effects` folds through `Render`, and that is a true sentence about the design, so it is declared debt rather than re-spelled away. |
| `ExMateriaBattlefield.Lattice` | 2 | **invertible, and not ours to invert.** `CinematicFacingResolver._sample_visible` marches the map lattice to answer *"is this silhouette point visible from the camera?"* — a `Battlefield` query that `Effects` is computing by hand. Recommend `Battlefield` publish `is_visible_from(origin, eye)`; **#1193**, not done in this extraction. |
| `ExMateriaSound.FedsBank` | 1 | **correct as written.** The blueprint's Format owner rule says `Effects` reads `Audio`'s `feds.bin`; this line is that sentence. |

**9. The game-side seam is twelve code lines over three addresses, and that is what the
façade publishes.** Restated from *Context* because ADR-0286 dec. 8's *"44 lines over ~12
addresses"* is the figure a pass-5 plan would otherwise inherit: **spawn** (3),
**overlay install** (6), **surface registration** (2), **screen background** (1). The 17
authoring-root lines are the studio's and `TrapViewer`'s, and are priced at pass 5 with the
rest of the authoring surface; the 18 PSX-trio lines leave under dec. 4.

**10. The predicted metric, against which pass 9 scores.** Instruments and commands are named
so the prediction is falsifiable rather than rhetorical.

`tools/membership_arms.py`, same invocation as *Context*:

| arm | today | predicted | why |
|---|---:|---:|---|
| 1 — reach into one of the eleven systems | 67 | **3** | −61 (dec. 1; `platform` is a tier, invisible to arm 1), −3 (dec. 3). The 3 are `ExMateriaBattlefield` ×2 + `ExMateriaRender` ×1, and it is **2** if dec. 8's dead DDA is deleted |
| 2 — foreign host autoload | 72 | **0** | −61 (dec. 1), −11 (dec. 5) |
| 2b | 0 | **0** | |
| 3 — `#include` outside every addon root | 7 | **8** | +1, the `psx_gamma` seam once #1187 lands; all free |
| 4 | 0 | **0** | |
| 4b — `global uniform` declared inside 🔴 | 2 | **0** | `psx_fx_stretch` delete-and-include, `psx_gamma` via #1187 |
| 5 — sibling `class_name`, guard's rule | 63 / **10 debt** | **≈93 / ≈10 debt** | +≈30 free (dec. 4, port tier), +≈7 debt (dec. 5, the sound façade), −4 debt (dec. 8, the dead DDA), −3 free (`PsxUnits.gd` leaves) |
| 6 — `res://` outside every addon root | 2 | **2** | **not payable.** `TrapEffect.gd:257-258` name `assets/sprites/textures/TRAP1.tga` and its palette, which live under the symlinked, gitignored `project-assets/` tree. ROM-derived content cannot ship inside a published addon, so this is a **content-pack dependency** (ADR-0142), not portability debt |
| 7 — host `class_name` | 3 | **0** | dec. 3 |

`tools/touch_matrix.py`, whole tree:

| | today | predicted |
|---|---:|---|
| `Effects` **row** | 87 | **23** — `Debug` 20 (the three panels' own `BaseDebugPanel`/`TuneField`, not the runtime's), `Battlefield` 2, `Render` 1, `Battle` 0 |
| `Effects` **column** | 25 | **6** — `Battle` 5, `Cutscene` 1 |
| total cross-system lines | 675 | **≈592** (−12.3%) |

`tools/classify_blueprint.py`: **`Effects` does not shrink.** 191 files / 58,124 lines today;
after the move the 67 files are booked `Effects` at their new address, exactly as
`addons/exmateria_battlefield/` is inside `Battlefield`'s 56 / 12,925. ADR-0286 dec. 10's
*"roughly 70% of its present size"* holds only if the new addon is **omitted from the walk
roots**, and every prior extraction added its own. **Add `addons/exmateria_effects/` to the
walk roots in the same commit as the move**, and read the extraction in the two numbers
above rather than in the bucket size. This is stated now because a 30% "improvement" that is
really a missing walk root is precisely the artifact ADR-0114 dec. 4 forbids.

**11. The build order, extending ADR-0287 dec. 9.** Before pass 6: (a) ADR-0287 dec. 2's
`EffectScoreModel.gd` move, (b) `psx_fx_stretch`, (c) **#1187** — the one item that blocks on
another package's corpus, filed today. Then, in the plan: (d) dec. 4's PSX trio, which is a
`git mv` whose blast radius is 18 host lines and 10 member files and should land before the
façade is designed, because it changes what the façade publishes; (e) dec. 1's
`EffectsDebug.gd`, the largest single arm reduction in the extraction and independent of
everything else; (f) dec. 3's three annotations; (g) dec. 5's façade re-spelling; (h) dec. 7's
overlay merge, which is the only item here that is genuinely new code rather than a move.
Dec. 8's dead-DDA deletion (**#1192**) and its `Lattice` inversion (**#1193**) are separate
tickets, neither blocking.

ADR-0286 dec. 11's gate is unchanged and restated for the pass-5 plan: the move does not
start without the studio quiescing or an agreed flag-day window against
[#262](https://github.com/timbermania/fft-monorepo/issues/262).

## Considered alternatives

**Keep `DebugConfig` and accept 61 lines of arm-2 debt.** Rejected on the same sentence
`RigDebug.gd:10-11` used: *"an addon that will not parse in a project without a `DebugConfig`
autoload fails goal #5 for four `print` gates."* Sixty-one, here, and the same four gates.

**Give `Effects` its own new slugs rather than binding `debug.*`.** Rejected — a second
spelling is a second registry, and the five tests that write `DebugConfig.particle_debug_enabled`
would stop reaching the flag the runtime reads. Two binds of one slug is the supported shape;
two slugs for one flag is the defect.

**Route the 61 through a narrow `Effects`-side log function instead of four predicates.**
Considered, and it is tempting because 61 `if` statements become 61 calls. Rejected for the
reason `RigDebug.log_animation`'s docstring records at the other end: a log verb that is
always called costs a string build on every frame whether or not the flag is on, and three of
these 61 sites exist precisely to hoist the flag read out of a per-particle loop. Predicates
preserve the shape the code already chose.

**Leave the PSX trio in the `Effects` addon.** The cheap answer, and it keeps arm 5 at 63.
Rejected: it publishes `PSXCameraConvert` — 16 lines of camera arithmetic used by
`CinematicManager` and `ScenarioCameraDirector`, neither of which is asking about effects —
on the `Effects` façade, and makes two unrelated systems depend on an effects addon for a
conversion `ADR-0091` already declared to be one seam. Arm 5's rise is in free lines by
declared tier; the alternative's cost is in the interface, where it is permanent.

**Move the trio to `exmateria_platform` but keep `PSXCameraConvert` in `Effects` as a thin
wrapper.** Rejected: `PSXCameraConvert` is *already* the thin wrapper (`:8` — *"This is a
thin FACADE over the consolidated seams (ADR-0091)"*), and its 16 inbound lines are the
largest single address in the inbound surface. A wrapper over a wrapper, published from the
wrong package.

**Move `audition_container` / `audition_sound` to the studio in this extraction.** Rejected
for ADR-0287's reason applied one level down: they need `_live_feds_bank()` and `effect_data`,
the assembler already reaches them by `has_method` so they cost nothing to leave, and a split
is not reversible the way a move is. Dec. 6 books them to the studio without moving them.

**Merge all three overlays, gradient included.** Rejected. A sky gradient is not a tint layer:
it has no owner stack, no recipe and no removal, and `BattlefieldWiring` publishes it once at
map load rather than per cast. Folding it in would produce a single wide façade — the thing
the blueprint's **Port** entry names as the failure mode of a façade (*"a single wide one hides
the crossings"*).

**Delete `build_illumination` in this pass.** Rejected on ADR-0287 dec. 5's own reasoning:
this pass establishes that the only callers are tests, which is a measurement; deleting live,
tested machinery is a decision that owes ADR-0208 dec. 5 an argument, and it gets its own
ticket rather than riding an audit.

**Invert the `Lattice` reach into a `Battlefield` sightline query as part of extraction #7.**
Rejected — it is the right design and it is a neighbouring subject's ADR. Widening or
inverting another system's published surface from inside an audit of this one is what
ADR-0262 declined twice and ADR-0287 dec. 6 declined a third time.

## Consequences

- **The oldest unpaid item in the extraction is paid, and it was cheap.** Two passes deferred
  the 61 lines; reading them took one `grep` and one `sort | uniq -c`. The deferral cost more
  than the work. ADR-0286 dec. 7 framed it as a choice:
  *"Pass 2 measures whether the 61 are a port's two signatures or 61 independent decisions."*
  The answer was outside both options — four booleans with a
  shipped precedent — which is the general lesson: **a binary framing in a soft spot is a
  guess about the shape, and it is worth nothing until somebody looks.**
- **`src/effects/` has now mis-sorted three different ways** — a studio file, a dead file, and
  a port-tier trio. The directory rule is not a membership and ADR-0287 dec. 1's exception
  list is the permanent form.
- **Two instrument blind spots are now measured, not suspected.** A raw `preload` into another
  addon's `runtime/` is invisible to all nine arms because the target is inside *an* addon
  root; and `touch_matrix.py` cannot see any edge into `addons/exmateria_sound/` because that
  tree is not walked. Between them they hid 4 of the 15 `Audio` lines. Neither is a defect
  worth fixing mid-extraction; both are worth stating whenever an arm total is quoted.
- **An extraction shrinks the progress bar partly by leaving the instrument's field of view.**
  `Effects → Audio` read 24 lines at extraction #2's pass 3 and reads 0 today with the coupling
  still present. The predicted 675 → 592 is real for the eleven systems; it is not a claim that
  83 dependencies stopped existing.
- **Arm 6's two lines are not debt and no extraction can pay them.** `TrapEffect.gd:257-258`
  name `assets/sprites/textures/TRAP1.tga` and its palette; `assets/sprites/` is a symlink
  into the gitignored `project-assets/` tree, so the targets are ROM-derived content that
  cannot be vendored inside a published addon by construction. Under ADR-0142 they are a
  **content-pack dependency**. Every future membership containing a ROM asset reader will
  read the same way, and a burn-down that treats arm 6 as payable will chase it forever.
- Pass 4 inherits a translation table with at least three rows: `UnitTintOverlay` →
  `TintedSurfaces` (it never dereferences a unit), `MapTintOverlay` → the `SURFACE_MAP` case of
  the same, and `SoundSubsystem` → whatever survives dec. 5's re-spelling. Goal #7's purge has a
  named subject rather than a directory.
- **#1187 is the only item that can stop extraction #7 and it is not ours to close.** Arm 4b
  enforces; `psx_gamma` is declared by no addon anywhere and the port that owns its value
  declines its declaration on a circular reading of ADR-0220 dec. 1. Filed the day this pass ran,
  as ADR-0287 S3 asked.

## Soft spots

**S1 — the metric prediction is arithmetic over a static scan, and one row of it is a
guess.** Arms 1, 2, 2b, 4b, 6 and 7 are subtraction and are safe. **Arm 5's ≈93 is not**: it
depends on how many of the ~20 member use sites of the PSX trio sit under an alias the guard
resolves versus being spelled through the façade directly, and ADR-0211 dec. 4's rule was
read, not run, against a tree where the trio has moved. Treat the *direction* (up, entirely in
free lines) as the claim and the number as ±15.

**S2 — no Godot process was started for this pass either.** ADR-0287 S2 said the same and the
risk has grown: dec. 3 changes three type annotations on the runtime's spawn entry points and
dec. 7 proposes merging two autoloads. A duck-typed reach or a non-literal `load()` is invisible
to everything used here (`closure.py` counts 225 such sites tree-wide). **The `Unit` → `Node3D`
change in particular must be verified by loading the combat scenes and asserting, not by
watching them come up** — ADR-0157's Spike A lesson, unpaid for two passes running.

**S3 — dec. 7 is the only decision here that is new code rather than a move, and it is the one
with no precedent in this repo.** Every other item transcribes something already shipped —
`RigDebug.gd` for dec. 1, ADR-0175 dec. 2 for dec. 5, `git mv` for dec. 4. Merging
`UnitTintOverlay` and `MapTintOverlay` re-prices ADR-0014's delivery path and touches
`src/units/Unit.gd`, which is `Battle`'s. If pass 5 finds it does not fit in the extraction's
window it should be dropped to its own ticket without dropping decs. 1–6 with it; the seam is
designed so that it is separable.

**S4 — "production-dead" for `build_illumination` is a name-and-path scan over 2,545 files plus
two test files read by hand.** It agrees with the file's own `RETAINED-BUT-UNWIRED` comment and
with `_deliver_output` no longer delivering it, which is three independent readings, but none
of them is a run. Dec. 8 asks for #1192, not a deletion, for that reason.

**S5 — the 1,044 test-and-tool references are still counted and still unopened.** ADR-0287 S5
said so. This pass added one fact about them and it is not reassuring: the `DebugConfig`
severance is test-transparent *because both spellings reach one `Tune` registry*, which is a
property of these four flags and generalises to nothing. Pass 5 prices the rest.

**S6 — the 20 residual `Effects → Debug` lines in the predicted matrix are an artifact and will
be read as a result.** They are `EffectViewerPanel` / `TrapViewerPanel` / `FireCastReproPanel`
naming `BaseDebugPanel` and `TuneField`, booked `Effects` by `classify_blueprint.py`'s
basename-prefix rules. Nothing in this extraction touches them and nothing should; a pass-9
reading that reports *"`Effects` still reaches `Debug` 20 times"* is describing
`classify_blueprint.py`'s rule table, not this system.
