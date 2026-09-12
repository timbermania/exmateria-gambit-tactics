# ExMateria Effects

**What a cast looks like.** The parsed `E###.BIN` file model, the cast that runs
it, the four channel subsystems, the particle pool, the TRAP family, the twelve
fold/native shaders and the engine-fold compositor. **Extraction #7** of the
`godot-learning` refactor — selected and audited at
[ADR-0286](../../docs/adr)/[0287](../../docs/adr)/[0288](../../docs/adr), moved
here at [ADR-0295](../../docs/adr/0295-the-forty-five-class-names-collapse-to-twenty-one-and-forty-eight-vault-notes-are-held-by-two-anchors.md).

**64 members, 14,569 lines, ten directories.** Plus the façade and `plugin.gd`,
which are addon files and not members. It moved in at 64 / 14,498 / nine — the same
member count by coincidence, not by stasis: [#1218](https://github.com/timbermania/fft-monorepo/issues/1218)
added `install/EffectsDebug.gd` (and the tenth directory) and
[#1224](https://github.com/timbermania/fft-monorepo/issues/1224) deleted
`overlay/MapTintOverlay.gd` by merging it into `TintedSurfaces`.

| directory | files | what it is |
|---|---:|---|
| `file_model/` | 8 | what a parsed `E###.BIN` is — `EffectData`, `EffectEmitter`, `EffectCurve`, `CurveExplode`, `TimelineData`, and the palette / screen / camera keyframe data |
| `cast/` | 5 | an effect while it runs — `EffectInstance` (930 lines), `EffectManager`, `EffectTimeline`, `EffectPhase`, `EffectEndModel` |
| `subsystem/` | 8 | the four channel runtimes over one `Subsystem` base, plus `PhaseBlock` |
| `particles/` | 5 | the emitter, the pool, the physics and the animator |
| `render/` | 14 | the prim pool, the particle renderer, the STP/fold shaders, `UnifiedPrimStager`, `OTDepthPrimOrder` and the engine-fold compositor |
| `callbacks/` | 14 | the ten ROM callback shapes, their registry and manager, and two callback shaders |
| `trap/` | 6 | the TRAP particle system, its charge-line and orbital handlers, the palette controller and `trap_charge_line.gdshader` |
| `overlay/` | 2 | `ScreenEffectOverlay` and `TintedSurfaces` — two of the addon's three autoloads. `TintedSurfaces` was `UnitTintOverlay` until [#1223](https://github.com/timbermania/fft-monorepo/issues/1223) (it never dereferences the id it is keyed by, so it is a registry of tinted SURFACES and the key is an opaque token) and absorbed `MapTintOverlay` as the reserved `SURFACE_MAP` token at [#1224](https://github.com/timbermania/fft-monorepo/issues/1224) |
| `camera/` | 1 | `CinematicFacingResolver` |
| `install/` | 1 | `EffectsDebug` — the addon's four `debug.*` verbosity flags, read through `ExMateriaPlatform.TunePort` so no member names the host's `DebugConfig` autoload (#1218). Not published on the façade: internal, like `exmateria_sprite_rig`'s `RigDebug` |

## The one global name

`ExMateriaEffects`, and nothing else
([ADR-0212](../../docs/adr/0212-a-count-of-one-was-never-the-invariant-the-addons-one-global-is-the-folder-named-facade.md)
dec. 1). Godot has no package scope — a `class_name` is engine-global, so every
one an addon declares lands in *your* project's global scope. This addon
declared **42** on the day it moved; they are all gone, and everything is a
constant on that one name. `tools/check_addon_globals.py` holds both directions:
nothing else here may declare a global, and nothing published may dangle.

The published surface is **21 names**, derived rather than assumed: a member is
published when something outside this addon reaches it. Fifteen further members
are reached only from this repo's own `tests/` and `tools/` and are deliberately
**not** published — they are bound by `res://` path instead, and every one of
those sites is declared in `tools/check_lattice_scene.py`'s criterion-4 register
rather than hidden. That register is therefore **non-zero for this addon by
decision** (ADR-0295 dec. 1).

| published | what it is |
|---|---|
| `ExMateriaEffects.EffectData` | the parsed effect — emitters, timeline, curves, keyframes |
| `ExMateriaEffects.EffectEmitter` | one emitter's configuration |
| `ExMateriaEffects.EffectCurve` | FFT curve data, 160 samples |
| `ExMateriaEffects.CurveExplode` | the ROM's shared 15-slot curve table, exploded per emitter |
| `ExMateriaEffects.TimelineData` | emitter start/stop timing |
| `ExMateriaEffects.PaletteData` / `.ScreenData` / `.CameraData` | the three keyframe data models |
| `ExMateriaEffects.EffectInstance` | one running effect, as a `Node3D` |
| `ExMateriaEffects.EffectManager` | spawning, cleanup polling, the cast lifecycle |
| `ExMateriaEffects.EffectPhase` | the timeline phase constants |
| `ExMateriaEffects.EffectEndModel` | the derived effect end — when the engine REAPS the cast |
| `ExMateriaEffects.PaletteSubsystem` / `.ScreenSubsystem` | two of the four channel runtimes |
| `ExMateriaEffects.PhaseBlock` | one phase's cursor + channel state |
| `ExMateriaEffects.EngineFoldCompositor` | the display-space compositor (Forward+, fork only) |
| `ExMateriaEffects.UnifiedPrimStager` | the shared transparent-prim staging |
| `ExMateriaEffects.TrapEffect` / `.TrapChargeLineEffect` / `.TrapOrbitalEffect` | the TRAP family |
| `ExMateriaEffects.CinematicFacingResolver` | the effect camera's base yaw |

A consumer may alias one back to a bare local name, which is what keeps existing
use sites spelled the way they were ([ADR-0211](../../docs/adr) dec. 4):

```gdscript
const EffectData = ExMateriaEffects.EffectData
```

## Install

1. Copy `addons/exmateria_effects/` — and its `deps=` (`exmateria_schema`,
   `exmateria_platform`, `exmateria_render`, `exmateria_battlefield`,
   `exmateria_almanac`) — into your project.
2. **Open the project, then enable the plugin, then reload.** Godot imports and
   compiles shaders when the project OPENS; a first enable in a bare project
   logs shader compile errors for names the plugin has not provided yet
   (ADR-0203 dec. 6).
3. Enabling registers three autoloads — `EffectMultiMeshPool`,
   `ScreenEffectOverlay`, `TintedSurfaces`. A project that declares them itself
   keeps its own lines; the plugin only adds what is missing.
4. **Declare `exmateria_effects/content_root`** — see *Content the host must
   supply* below. Without it nothing loads, and you get one `push_error` saying so.

## Content the host must supply

**This addon ships no ROM-derived content, and it never can.** The per-effect `E###`
directories (emitters, curves, framesets, the per-callback payloads) and the `TRAP1`
indexed texture with its palette are extracted from a disc the repo does not
redistribute; `assets/effects/` is gitignored outright. ADR-0202 dec. 5 calls this Class
B and rules that the *hardcoding* was the defect while the *dependency* is a legitimate
contract — so the addon stopped naming `res://assets/` and takes a search root from the
host instead ([#1224](https://github.com/timbermania/fft-monorepo/issues/1224)'s sibling
item; the register rows were seeded by
[#1225](https://github.com/timbermania/fft-monorepo/issues/1225)).

Declare it in the consuming project's `project.godot`:

```
[exmateria_effects]

content_root="res://assets/"
```

`EffectsContent` resolves every subpath against that root:

| subpath | what needs it |
|---|---|
| `effects/E###` | `EffectManager` (spell, cinematic and item spawn — three sites) |
| `effects/E###/callbacks/CB##/callback_data.json` | `EffectCallback` (the per-callback ROM payload) |
| `effects/trap/emitters.json` | `TrapEffect` |
| `effects/trap/frames.json` | `TrapEffect` |
| `effects/trap/animations.json` | `TrapEffect` |
| `effects/trap/element_config.json` | `TrapEffect` |
| `sprites/textures/TRAP1.tga` | `TrapEffect` (the indexed atlas) |
| `sprites/textures/TRAP1.palette.tga` | `TrapEffect` (its CLUT) |

**A project that omits the key gets one `push_error` naming it**, not a silent empty
load — that legibility is dec. 5's stated goal, and it is why the setting's default is
empty rather than `res://assets/`. A default pointing at the host's own layout would
also have left the literal inside an addon file, where the install register still scores
it.

⚠️ **ADR-0142 makes the CONTENT un-shippable; it does not make the LITERAL permanent.**
The register rows this replaced said the TRAP texture pair was *"PERMANENT under
ADR-0142 rather than targeted at zero"*. That conflated two claims: a content root
removes every literal without moving one ROM-derived byte, so the dependency survives as
this documented install step and the install register reaches 0.

### It needs the fork

`plugin.cfg` declares `engine="fork"`, and that is measured rather than assumed:
`render/EngineFoldCompositor.gd` extends `CompositorEffect` and ten shaders
declare `render_mode compositor_fold`. Under a stock build the compositor
self-disables and every folded prim silently vanishes — the failure is quiet,
which is why the declaration exists.

### It needs ROM-derived content the addon does not ship

Four `res://assets/effects/trap/*.json` tables, the per-effect
`res://assets/effects/E###/` directories, and
`res://assets/sprites/textures/TRAP1.tga` + `TRAP1.palette.tga`. Those literals
are ROM-derived and un-shippable ([ADR-0142](../../docs/adr)), which is why
`check_addon_portability.py` arm 6 reads **2** here and the number is declared
permanent rather than targeted at zero.
