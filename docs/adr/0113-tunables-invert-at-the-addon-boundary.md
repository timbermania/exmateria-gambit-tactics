# Tunables invert at the addon boundary — the addon declares, the host discovers

An extracted addon **declares its own tunable schema through its own
interface**; the host's debug dashboard walks the loaded addons and renders
whatever they declare. The dependency arrow inverts: the addon depends on
nothing, the host depends on the addon.

Status: accepted (2026-08-19); the Context percentage corrected by [ADR-0131](0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md)
(2026-08-20). Extends
[ADR-0068](0068-tunables-bind-a-slug-to-a-code-default-with-a-coalescing-override-layer.md).

## Context

`project.godot` declares 24 autoloads, and **126 of 321 `src/` files (39%) touch
at least one**. The distribution is lopsided:

> **Amended by [ADR-0131](0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md) (2026-08-20).** **27%, not 39%.** `126` is the
> *current* count — re-measured with comments and string literals stripped, 126
> of **470** `src/` files touch at least one autoload. `321` is the 2026-07-12
> denominator ADR-0110 also quotes; the same current-numerator-on-stale-
> denominator error as ADR-0111 dec. 7. `project.godot` now declares **26**
> autoloads. The lopsided *distribution* below is the load-bearing claim and it
> holds — `DebugConfig` and `Tune` remain the top two by a wide margin.

| autoload | files | kind |
|---|---|---|
| **`DebugConfig`** | **69** | debug/tuning |
| `DebugOverlay` | 18 | debug |
| `PSXDisplay` | 13 | domain |
| `SfxRouter` / `ExMateriaEffectSfx` | 12 / 12 | domain |
| `PartyRoster` / `EnemyRoster` / `MusicPlayer` / `ScreenEffectOverlay` | 7 | domain |
| `EventBus` | 6 | domain |
| `GameLogger` / `PerfMonitor` / `ScenarioDebugSession` | 5 / 4 / 3 | debug |
| `CharacterCatalog` / `ExMateriaAudioEngine` / `EffectMultiMeshPool` | 3 | domain |
| `AssetManifest` | 1 | domain |

The debug and tuning autoloads account for ~99 of those references. **Every
domain autoload has a fan-in of 13 or fewer.** So the ambient-global barrier to
portability is not structural sprawl across the domain — it is ADR-0068's
tunables registry reaching into more than one `src/` file in five.

A system that reads `DebugConfig` cannot ship to another game without shipping
the debug harness with it. `exmateria_sound` — the portability exemplar —
references none of these.

## Decision

The addon owns and exposes its tunable schema; the host discovers and renders
it. `DebugConfig` stops being a thing addons reach *up* into.

> **Amended by [ADR-0140](0140-debug-is-a-system-and-a-system-logs-itself.md)
> dec. 4-6 (2026-08-21): the direction is right, the target is 12% of the
> problem.** `DebugConfig` is not a tunables registry — it is three unrelated
> things under one name. Measured at 324 references across 46 members:
> **235 (73%) are verbosity gates** (`if DebugConfig.x_debug_enabled: print(…)`
> — 171 of them literally that), **50 (15%) are launch control** (which scenario,
> which seed, autostart, skip the strategy phase, time scale, quit), and only
> **39 (12%) are tunables and overlay toggles**, which is the part this ADR
> describes. So *"the answer is applied 69 times"* is three migrations with three
> different destinations, not one:
>
> - **the gates go to the system that prints them**, as a `static var` under
>   ADR-0068, with that system's panel reading it as a view. **There is no
>   inter-system logging and none is introduced** — 12 of the 15 gates are
>   already used by exactly one system, and the three that are not are the defect
>   (`iteration_debug_enabled` alone is 107 refs across six systems, one name
>   doing generic verbose duty). `GameLogger` is **deleted, not promoted**: its
>   closed four-value `Category` enum is this ADR's own rejected alternative —
>   *"port my debug harness too"* — with a nicer API.
> - **launch control goes to the assembler.** It is the root scene's startup
>   arguments; no system reads it.
> - **the tunables invert as described here**, and ADR-0140 dec. 7 gives the
>   mechanism this ADR left open: `TuneField.add()` already calls `Tune.bind()`
>   (`TuneField.gd:78`), so one call both publishes the schema through
>   `platform`'s port and mints a `Control` from `Debug`. Splitting that one
>   function retires 58 of `Debug`'s edges; 121 of the 139 call sites (87%) go
>   through it.
>
> The *rejected* alternative below — **"declare `DebugConfig` a required platform
> service"** — is reaffirmed, and ADR-0140 dec. 8 adds the number: it would make
> 95 interface edges permanent instead of retiring them.

This composes with the tunable-compliance work already underway: a tunable
living as a `static var` in its production owner, with the debug panel as a pure
view, is already most of the way here — the owner declares, the panel observes.
Only the *discovery* direction changes.

## Considered alternatives

- **Inject a config/logger interface.** Rejected: plumbing through all 69 call
  sites, and losing ambient tuning would be felt daily during development.
- **Declare `DebugConfig` a required platform service** any host must provide,
  like Godot's own `Engine`. Rejected: zero call-site churn, but every addon
  then carries a hidden dependency, and "portable to any other game" quietly
  means "port my debug harness too" — goal #5 failing while appearing to pass.
- **Strip debug hooks at extraction**, leaving tuning only in the host's dev
  harness. Rejected: cleanest addons, but in-addon tuning is central to how this
  codebase is actually worked on.

## Consequences

- This is the single highest-leverage change in the package for portability, and
  it must be settled before the first extraction, because the answer is applied
  69 times.
- The domain autoloads are a far smaller problem than the count of 24 suggests
  and can be handled per-extraction rather than as a programme.
