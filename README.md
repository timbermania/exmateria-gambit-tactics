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
own, and `godot` ≥ 4.6 plus `uv` on your `$PATH`.

```bash
git clone <this repo> exmateria-gambit-tactics
cd exmateria-gambit-tactics

# 1. extract your disc (fft-iso-patcher, or any tool that yields the layout
#    SETUP_FROM_SCRATCH.md section 1.2 describes)
# 2. point bootstrap at the extract:
FFT_ISO=/path/to/your/'Final Fantasy Tactics.bin' \
  bash tools/bootstrap_assets.sh /path/to/your/fft-extract

# 3. play
godot --path . res://assets/scenes/GPUArena.tscn
```

Bootstrap is idempotent — re-running it is a no-op for work already done.

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
> `SETUP_FROM_SCRATCH.md` section 1.2.

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
report what happens. Two other things Windows users should expect: `tools/bootstrap_assets.sh`
and the rest of `tools/*.sh` are bash, so you need Git Bash or WSL to produce the assets,
and the rest of the project is exercised only on Linux.

The C++ source is not in this repository — it lives in the separate `exmateria-sound`
project — so you cannot build the missing slots from here.
`SETUP_FROM_SCRATCH.md` section 1.3 has the detail.

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
