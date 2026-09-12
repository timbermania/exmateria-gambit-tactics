# The published autoloads were named from INSIDE, and that half was uncounted

[#564](https://github.com/timbermania/fft-monorepo/issues/564) asks what happens to the three
autoloads `Battlefield` **publishes**, and frames the question around the **21 outside
reaches** its measurement found — all of them `Debug` panels. The framing is not wrong, it is
aimed at the smaller half. `tools/autoload_reach.py` reports who names a system's autoloads
**from outside that system**, which is the direction that cannot break a standalone parse.
The direction that can is invisible to it: **27 lines inside the addon-to-be name
`Battlefield`'s own published autoloads**, and no instrument in this repo was counting them.

`check_addon_portability.py`'s arm-2 docstring had already sentenced them in a clause nobody
had cashed — an autoload name is created by *"a project that does not autoload it —
**including the addon's own**."*

Status: accepted (2026-08-26). Resolves
[#564](https://github.com/timbermania/fft-monorepo/issues/564) on map
[#560](https://github.com/timbermania/fft-monorepo/issues/560) (extraction #3, loop pass 5,
**9 of 9 — the map closes**). Builds on
[ADR-0175](0175-a-port-answers-arm-1-and-not-arm-2-and-the-debug-residue-was-print-statements.md)
dec. 2, whose argument this decision runs in the opposite direction. **BUILT here**, not filed.

Code at `0f8a7a372` + this branch.

> ⚠️ **Written as 0176 and renumbered before push — the collision trap fired a fourth time.**
> ADR-0175's own warning said *"`0176` is next free as of this commit"*, and the handoff into
> this ticket said the world-map line held up to `0181`. Both were stale within the day:
> `feature/world-map-input` now holds **0176–0181** and `605-adr-number-collisions` holds
> **0182**. `0183` was the first
> free number across every remote ref at the time of this commit, re-checked immediately
> before push. [#605](https://github.com/timbermania/fft-monorepo/issues/605) is now tracking
> the underlying defect — five numbers already name two accepted ADRs each.

## Context

Goal #5's test is *"a system could ship to another tactics RPG with its interface intact."*
ADR-0175 dec. 2 settled the **reached** direction — an addon does not name a host autoload,
because:

> An `[autoload]` line can only be written by the consuming game's `project.godot` — an
> install step, not an interface, so goal #5 fails on it. An addon-presence dependency is
> vendorable; a host-project-configuration dependency is not.

#564's Context is explicit that the two directions must agree, *"because the same mechanism
(an addon naming `/root/` paths, and being named by them) answers both."* Run the sentence
backwards and publishing is not merely as bad, it is **worse**: depending on a host autoload
asks a consuming game for nothing it was not already doing; *publishing* one asks every
consuming game to add three `[autoload]` lines before the addon's own `Tile.gd` will parse.

## Measurement

### The reach table sees the smaller half

`tools/autoload_reach.py Battlefield`, re-run at `0f8a7a372` (the ticket's own figures were
stale — ADR-0167 had moved `SkirtDebugPanel.gd`'s line numbers):

```
SkirtConfig             15 lines,   4 from OUTSIDE   src/debug/SkirtDebugPanel.gd:38,42,44,45
TileOverlayConfig       20 lines,  17 from OUTSIDE   src/debug/TilesDebugPanel.gd:35,46,57,58,59,60
TileOverlayCompositor    5 lines,   0 from OUTSIDE
```

Running **arm 2's own stripper** (`_sg.strip_noncode`, the same function the guard uses) over
the 46 `.gd` rows of `docs/EXTRACTION-3-MOVE-MANIFEST.tsv` — i.e. over the tree
`addons/exmateria_battlefield/` becomes at pass 6:

| autoload | lines | files | |
|---|---|---|---|
| `Tune` | 59 | 6 | reached, #588 |
| **`SkirtConfig`** | **11** | 2 | **published — and self-named** |
| **`TileOverlayConfig`** | **11** | 2 | **published — and self-named** |
| **`TileOverlayCompositor`** | **5** | 1 | **published — and self-named** |
| `PSXDisplay` · `DebugConfig` · `MapTintOverlay` · `ScreenEffectOverlay` · `SfxRouter` | 6 | 5 | reached, #589/#590 |

**65 reached + 27 self-named = 92 arm-2 breaks after pass 6, not 65.** #588 is scoped to the
65. Had #564 answered *"the three stay autoloads"*, pass 6 would have shipped 27 unowned
breaks and #588 would have closed green over an addon that still could not parse alone.

Arm 2 is blind to them **today** only because the files are still under `src/`; the defect is
latent, not absent, and it lands the moment the manifest is executed.

### The control, and the two replacement shapes

Scratch project, Godot `4.8.dev.custom_build`, **no `[autoload]` block at all**, class cache
warmed with `--import`. `rc` is 0 on every arm — the `Parse Error` count is the verdict:

| arm | subject | Parse Error | runtime |
|---|---|---|---|
| **control** | an addon file naming `SkirtConfig` | **1** — `Identifier "SkirtConfig" not declared` | — |
| **S** | `class_name` + `static var` **with a getter** | **0** | `depth=0.15` |
| **I** | `class_name extends Node` + lazy `static func of()`, self-parenting to `root` | **0** | `changed paused=true` |

The control is what makes arms S and I mean anything: the seed moves the instrument. Arm S
also settles a fact this decision rests on and which is easy to assume wrongly — **GDScript
4.8 supports getters and setters on `static var`**, so a pure-façade config class loses
nothing by going static.

### Which shape each of the three earns, measured rather than chosen

`Tune.register_all()` already carries **two** owner idioms, and its own comment is the
discriminator — the `res://` list is *"`_static_init` owners … reached by runtime `load()`"*,
the `/root/` list is for singletons *"whose `register_tunables` reads instance state seeded in
`_ready`"*:

| | measured state | shape |
|---|---|---|
| `SkirtConfig` | **none** — 3 consts and getters that are pure `Tune` reads | **static class** |
| `TileOverlayConfig` | `changed` signal, `paused`/`scrub_phase` | **`class_name` + lazy singleton**, with its tunable half static |
| `TileOverlayCompositor` | child `MeshInstance3D`, `_process`, `get_tree()` | **`class_name` + lazy singleton** |

### `TileOverlayCompositor` fails delete-first, and it is not close

ADR-0175 dec. 3 established *ask first whether the output is worth keeping* — 31 of #563's 38
`Debug` breaks were `print` behind a switch. #564 invites the same test, reading the
compositor's 0 outside reaches as *"an autoload with no external namer may not need to be an
autoload at all."* Right about the autoload; wrong about deletion. It has **five namers in
`Tile.gd`**, and its docstring records what it exists for: the routed Move/Attack tiles are
flat ground decals that the old particle path *"billboard-interpreted … and VANISHED"* on
Forward+. Zero *outside* reaches is a statement about its interface, not its liveness.

### The fourth row resolves itself, and generalises

#565's comment adds `src/debug/MapGridOverlay.gd` — addon surface whose one consumer,
`ScenarioUnitAlignmentDebugPanel.gd`, books `Cutscene` rather than `Debug`. It needs no new
mechanism: it is already `class_name MapGridOverlay`, reached at `:135` as
`MapGridOverlay.new()`. That is the general case. **Of the 46 moving rows, 25 already declare
a `class_name`.** Battlefield's published surface was 25 `class_name`s and 3 autoloads; the
three were the exception, not the pattern.

## Decision

**1. `Battlefield` publishes `class_name`s and no `[autoload]` names — the same mechanism as
ADR-0175 dec. 2, run in the publishing direction.**

A `class_name` is registered from the addon's own files at import; an `[autoload]` line is
written by the consuming game. Dec. 2's *"an addon-presence dependency is vendorable; a
host-project-configuration dependency is not"* holds a fortiori here. `exmateria_render/
plugin.gd:6-13` states the same rule in prose for `PSXDisplay` and declines
`add_autoload_singleton()`; all three of ADR-0175's grounds for that rejection were re-checked
and hold in this direction, the `[editor_plugins]` ground more strongly — three names would
have to exist before the addon's own `Tile.gd` would parse.

**2. The three convert: `SkirtConfig` static, the other two `class_name` + `of()`. BUILT.**

`SkirtConfig` joins `Tune.register_all()`'s `load()` list beside `SkirtGeometryGenerator.gd`
(10 of its 11 namers) and binds at `_static_init`, the house idiom. Its 15 call sites are
**unchanged** — a `static var` reads identically.

`TileOverlayConfig` splits along the seam its own code already had: the **tunable half is
static** (`_types`, `tex_size`, the `_uv_*` defaults, `get_param`/`param_slug`/`tunable_types`)
and binds at `_static_init`; only `changed`, `paused`/`scrub_phase` and the two functions that
read them need `of()`. `TileOverlayCompositor.is_routed()` is static for the same reason —
every `Tile` asks it and most answers are false, so the question must not construct the node.

**The split was forced by a red test, not chosen.** The first build bound `tile.*` slugs
inside `of()`, and `TuneRegisterAllTest` failed on `bound at boot by TileOverlayConfig:
tile.uv_offset_x` — with no autoload, nothing touched `of()` at boot, and the ADR-0068 R5
registration both config files document in prose (*"the dashboard enumerates them without a
prior read"*, `SkirtConfig.gd:55`) silently died. #534's coverage assert caught
a real behavioural regression the same day it landed.

**3. Two concerns, not one — and what they share is a pattern, not a base class.**

`skirt.*` vs `tile.*`; `terrain/` vs `overlay/` in ADR-0168's manifest; terrain-build consumers
vs per-tile-highlight consumers; static vs Node. Zero shared code. They cannot share a base
class and should not acquire one; the shared shape — *a Tune-backed config façade over a slug
prefix, with the debug panel as a pure `TuneField` view* — is ADR-0068 R1 restated and belongs
in `CONTEXT.md`'s translation table, where ADR-0175 put three of its own.

**4. No new guard. Arm 2 already covers all 27, on the day pass 6 lands them.**

The only reason arm 2 reports zero today is that the files are under `src/`. Adding an arm to
watch a condition that expires at the next pass is machinery with a known end-of-life. The
existing instruments were verified to still report after the change: `check_tune_owner_
manifest.py` clean at 19 subjects / 15 `res://` + 2 `/root/`, and its **mutation seed still
moves all four rules** — R4's seed had to be re-pointed from `/root/SkirtConfig` to
`/root/AudioHostAdapter`, because its old subject left the list and a seed that rewrites
nothing reads clean.

**One cost is named and not paid.** A *host* file naming an absent `exmateria_battlefield`
is measured by nothing — arm 2 is addon-internal, arm 5 is addon→addon. This is accepted
rather than guarded: a dangling host is not what goal #5 measures, and the 21 inbound `Debug`
reaches are what a published interface is *for*.

**5. Built before pass 6 rather than after, on the user's instruction, and the consequence is
recorded here so pass 6's numbers stay attributable.**

The recommendation was to file this and let pass 6 stay a pure move — ADR-0159 dec. 5
amendment (b), *"a behavioural change riding inside a booking correction makes the booking's
own numbers unattributable."* The user chose to build. The correction is therefore stated in
advance: **pass 6's `--delta` baseline is this branch, not `0f8a7a372`.** The 46 manifest rows
are untouched in count and destination; what moved is the *content* of three of them plus 31
call sites in five files. Post-change, `autoload_reach.py Battlefield` reads **`publishes 0
autoload(s)`** and the projected post-move arm-2 total is **65, down from 92** — the exact set
#588 already owns, and nothing else.

## Consequences

- Map [#560](https://github.com/timbermania/fft-monorepo/issues/560) closes at **9 of 9**;
  loop pass 6 is released.
- `project.godot` drops from 29 autoloads to 26.
- `Battlefield`'s published surface is **28 `class_name`s and 0 autoloads**.
- #588's target is unchanged at 65 and is now the *whole* remainder, which it was not before.
- `Tune.register_all()`'s `res://` list grows to 15 and its `/root/` list shrinks to 2
  (`PSXDisplay`, `AudioHostAdapter`). Both are asserted by `TuneRegisterAllTest`.

## Considered alternatives

**Publish the three as autoloads and document the install step.** Rejected: it is ADR-0175
dec. 2's own argument with the sign flipped, and it makes the addon's *internal* files
unparseable without host configuration — a defect dec. 2 did not even have to consider.

**`EditorPlugin.add_autoload_singleton()`.** Rejected for ADR-0175's three grounds, re-checked
and still true, plus a fourth specific to publishing: it runs only for an enabled plugin, and
the names would have to exist before the addon's own files parse.

**Static forwarders that hide `of()` entirely**, preserving all 45 call sites verbatim.
Rejected: it doubles the API surface and hides a real lifetime. The static/instance split in
dec. 2 gets the same call-site stability for the 31 sites that deserve it (they touch no
instance state) and is honest about the 14 that do.

**Split `TileOverlayConfig` into a schema type and a transient-state type.** Rejected:
`apply_to_material` reads both halves, so the seam does not cut cleanly, and this map's
standing warning about two classes for a handful of statements applies. The split landed as
`static` vs instance *within* one class instead — same seam, no second type.

**Fold the 27 lines into #588.** Rejected: different addon, different mechanism (no façade is
needed — `class_name` is already the shape 25 of 46 rows wear), different residual cost. Then
overtaken by dec. 5 — they are built here.
