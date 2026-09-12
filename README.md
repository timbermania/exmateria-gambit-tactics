# ExMateria Gambit Tactics

An in-progress SRPG framework in Godot 4 — 3D isometric, sprite-based combat with the
simulation running as GPU compute shaders — bootstrapped to **Final Fantasy Tactics**
(PSX), which supplies its content and its reference behaviour rather than being the
target.

**Bring your own ISO.** This repository contains no Square Enix data of any kind: no
disc bytes, no map geometry, no sprites, no audio, no VRAM captures. Everything the game
needs from the disc is produced on your machine, from your own copy, by the parsers in
`tools/`.

---

## Quick start

You need a Linux x86_64 machine (see *Platform support*), an FFT PSX disc image you
own, `uv` on your `$PATH`, and a **Godot 4.8 fork** carrying the `compositor_layer`
primitive — no stock Godot will do (see *Which Godot* immediately below).
[Download it](https://github.com/timbermania/godot/releases/latest) or build it
yourself; *Building the fork* covers both.

```bash
# 0. the engine — download the Linux editor zip from
#    https://github.com/timbermania/godot/releases/latest
#    (needs glibc 2.35+; build it yourself if you are older, or on Windows)
unzip -q ~/Downloads/godot-exmateria-*linux*.zip -d ~/godot-exmateria
sudo ln -sf ~/godot-exmateria/*/godot.linuxbsd.editor.x86_64 /usr/local/bin/godot

git clone <this repo> exmateria-gambit-tactics
cd exmateria-gambit-tactics

# 1. extract your disc (fft-iso-patcher, or any tool that yields the layout
#    SETUP_FROM_SCRATCH.md section 1.3 describes)
# 2. point bootstrap at the extract:
FFT_ISO=/path/to/your/'Final Fantasy Tactics.bin' \
  bash tools/bootstrap_assets.sh /path/to/your/fft-extract

# 3. play
godot --path . res://assets/scenes/GPUArena.tscn
```

Bootstrap is idempotent — re-running it is a no-op for work already done.

### Which Godot — this needs a fork, and stock will not do

`godot --version` must report **4.8** and the build must support the
`compositor_layer` primitive. Measured against stock 4.7.1:

| | stock 4.7.1 | a `compositor_layer` build |
|---|---|---|
| `CompositorRenderLayer` (the kernel's `fold_layer.tres`) | ✗ "Can't create sub resource" | ✓ |
| `RenderingServer.is_compositor_layer_supported()` | ✗ absent | ✓ |
| `addons/exmateria_schema/compositing_key/Fold.gd` compiles | ✓ **since #721** | ✓ |
| `Fold.owns()` | `false` | `true` |
| the display-space fold runs | ✗ — every producer draws its in-scene twin | ✓ |
| anyone has LOOKED at those twins | ✗ never | — |

⚠️ **This table changed on 2026-09-12 and the change is worth reading.** Until #721
neither of the first two rows degraded: each stopped `Fold.gd` COMPILING, so
`Fold.owns()` was "Nonexistent function" and the failure cascaded through every
display-space effect in the game. The kernel is written as a feature detect with an
in-scene fallback shader behind every folded one, and **that fallback had never once
been reachable** on the builds it exists for. It is now — the layer loads lazily and
the capability query is deferred to run time (ADR-0191 dec. 14).

🔴 **Reachable is not verified, so this is still not a supported way to run the
game.** Nobody has ever looked at the twelve pairs of twins side by side. Per the
folded shaders' own comments the difference is **order and blend correctness**, not
fidelity: `darkscreen_mosaic_fold.gdshader` composites identically either side of the
resolve, while an add/sub banner *must* fold or it renders with the fog painted over
it. So some will look identical and some will look *wrong* rather than merely worse.

⚠️ **And do not open this project with a stock build to find out.** Godot rewrites
`project.godot` on open and strips the `4.8` feature, so the attempt edits the repo.
Every stock measurement above was taken in a throwaway project for exactly that
reason.

### What that actually produces

Measured on a clean clone, so these are the numbers to expect rather than an estimate:

| | |
|---|---|
| animation JSONs | 30 |
| sprite textures | 156 TGA |
| EVTCHR cutscene segments | 137 TGA |
| battle maps | 119 |
| ability effects | 401 |
| music | `WAVESET.WD` + 100 SMD files |
| generated on disk | ~800 MB |

Then the game comes up in Forward+ Vulkan, reports `[GPU Arena] GPU simulator ready`,
and runs a 13-unit battle. First launch spends 30–60 s compiling compute pipelines;
after that the SPIR-V cache makes it ~30 ms.

> ⚠️ **`project-assets/` lands BESIDE the clone, not inside it.** That surprises
> everyone. It is deliberate: no ROM-derived byte ever lands inside the repository, so
> that guarantee rests on the layout rather than on a `.gitignore` rule somebody could
> edit. `$FFT_EXTRACT` overrides it. Full resolution order in
> `SETUP_FROM_SCRATCH.md` section 1.3.

---

## Building the fork

*Which Godot* above says what you need and what stock does instead; this is how to
get one. It lives at **<https://github.com/timbermania/godot>** (branch `master`) —
four commits over upstream `master`, the load-bearing one being compositor render
layers (`render_mode compositor_layer` plus named scratch surfaces).

### Download it

[**Latest release**](https://github.com/timbermania/godot/releases/latest) — editor
binaries built in CI, so you do not need a compiler:

| | |
|---|---|
| **Linux x86_64** | needs **glibc 2.35** or newer: Ubuntu 22.04+, Debian 12+, Fedora, Arch. Built on 22.04 for exactly that reach — a binary built on a rolling distro needs glibc 2.44 and starts on almost nothing else. |
| **Windows x86_64** | ⚠️ **unverified.** It compiles, links and answers `--version` on a clean runner; nobody has run the game on Windows. See *Platform support*. |

A release is a snapshot: when the fork rebases onto upstream it goes stale, and
nothing warns you. Building from source is always current, and stays the answer on
macOS, on arm64, and on any Linux older than glibc 2.35.

### Build it yourself

With upstream's own prerequisites
([Godot docs](https://docs.godotengine.org/en/stable/contributing/development/compiling/compiling_for_linuxbsd.html)),
then `scons platform=linuxbsd target=editor dev_build=no -j"$(nproc)"` in a clone of
it — roughly 20–40 min on a modern desktop once, and minutes for rebuilds after that. Keep `dev_build=no`: it is scons' default and
resolves `optimize` to `speed_trace`, while `dev_build=yes` gives you `-O0` with engine
asserts on, which is slow and useless to measure on.

> ⚠️ **`godot --version` prints `4.8.dev.custom_build.<sha>` whichever you built.** That
> `dev` is the version status in `version.py`, unrelated to `dev_build`, and
> `custom_build` is true of any source build — so `--version` tells you neither the build
> type nor that you have the fork. The build type is in the filename
> (`…editor.x86_64` optimized, `…editor.dev.x86_64` not); for the fork itself, query the
> primitive — `RenderingServer.is_compositor_layer_supported()`, the row *Which Godot*
> measures.

**On Windows,** `platform=linuxbsd` is obviously wrong and
[upstream's Windows instructions](https://docs.godotengine.org/en/stable/contributing/development/compiling/compiling_for_windows.html)
are the ones to follow — but nobody has built this fork for Windows or run the game
there, so you would be first, and *Platform support* below is the rest of that story.

Detail and failure modes: `SETUP_FROM_SCRATCH.md` section 1.1.

---

## Platform support — Linux x86_64, and an unverified Windows build

Worth knowing before you clone. The SPU's twenty-four voices are mixed by a native C++
core; `addons/exmateria_spu/exmateria_spu.gdextension` declares **twelve** library slots
and three of them ship:

| slot | ships? |
|---|---|
| `linux.debug.x86_64` | ✅ committed, exercised — what the maintainers run |
| `windows.debug.x86_64` | ⚠️ committed, **unverified** — see below |
| `windows.release.x86_64` | ⚠️ committed, **unverified** |
| `linux.release.x86_64` | ❌ so an **exported release build fails on Linux** |
| macOS / arm64 | ❌ |

There is no GDScript mixer to fall back to, so on a platform with no binary the project
does not open at all.

**On "unverified".** The Windows DLLs are built with MSVC by CI and have never been
run. They export the right entry symbol and import only `KERNEL32.dll`, so there is no
Visual C++ redistributable to install — but no maintainer owns a Windows machine, and
nothing beyond "it compiled and linked" has been established. If you try it, please
report what happens. Windows users should also know how the two halves want to be run:
**bootstrap under WSL** (the `tools/*.sh` are bash, and WSL has `rsync`, symlinks and
`python3`), then **run native `Godot.exe`** against those same files — WSLg reaches the
GPU only through a D3D12 translation layer, which is the wrong substrate for this
renderer. Git Bash works for bootstrap too, since the sync script now falls back to
`cp -RL` when `rsync` is missing and `$GODOT`/`$PYTHON` cover the differently-named
commands, but it is the less travelled path.

The C++ source is not in this repository — it lives in the separate `exmateria-sound`
project — so you cannot build the missing slots from here.
`SETUP_FROM_SCRATCH.md` section 1.4 has the detail.

---

## Where things are

| path | what |
|---|---|
| `assets/scenes/GPUArena.tscn` | the battle scene — start here |
| `src/gpu/` | the compute-shader combat engine |
| `addons/exmateria_battlefield/` | terrain, movement, pathfinding, the ROM-derived walk integrator |
| `addons/exmateria_almanac/` | the data tier: abilities, jobs, items, encounters |
| `addons/exmateria_sprite_rig/` | sprite/animation resolution and rendering |
| `addons/exmateria_effects/` | the `E###.BIN` effect runtime and its studio |
| `tools/` | every parser, plus `bootstrap_assets.sh` |
| `vendor/` | the audio addons' source, synced into `addons/` by bootstrap |
| `docs/adr/` | why things are the way they are — read these before changing a subsystem |

`docs/` is the honest place to start for anything non-obvious;
`CONTEXT.md` maps the domain vocabulary.

---

## Running the tests

```bash
bash tests/run_all_tests.sh --sequential     # the full suite, slowly
```

Two things to know. Tests whose oracle is a disc derivation **skip** rather than fail
when it is absent — that is expected in a clone and is why you may see `[SKIP]` lines
and `OK (skipped=N)`. And Godot must not be run with `--headless` here; the renderer
path the game depends on is not exercised without a window.

---

## Provenance, and why the history starts at one commit

This repository is a single squashed root by design. It was extracted from a monorepo
whose history carries roughly 22 MB of disc-derived data, and no `.gitignore` can reach a
byte that is already in a commit — replaying that history would have published exactly
what this repository exists not to contain.

Emptiness is enforced rather than asserted. `tools/export_standalone.py` is the one-way
sync from that monorepo, and its `--check` arm fails if an excluded path reaches the
export, if an exclusion rule rots into a no-op, if a required path goes missing, or if an
audited group of disc-derived files grows. `tools/check_generated_assets.py` holds the
companion invariant: every disc derivation is rebuilt by a named parser and never
committed.

---

## Licence

See `LICENSE`. Final Fantasy Tactics is a trademark of Square Enix; this project is
not affiliated with, endorsed by, or derived from any Square Enix source code, and it
ships none of their data. You supply your own copy of the game.
