# ExMateria Gambit Tactics

An in-progress SRPG framework in Godot 4 — 3D isometric, sprite-based combat with the
simulation running as GPU compute shaders — bootstrapped to **Final Fantasy Tactics**
(PSX), which supplies its content and its reference behaviour rather than being the
target.

**Bring your own ISO.** This repository contains no Square Enix data of any kind.
Everything the game needs from the disc is produced on your machine, from your own
copy, by the parsers in `tools/`.

# Features

Fully featured VFX editor

https://github.com/user-attachments/assets/94584d40-3c3f-46f0-8501-27019e194810

Cutscene player and editor

https://github.com/user-attachments/assets/6cd0d1d2-7e30-4d8d-b4a8-3e388f9997f3

PSX blending in gamma space (On Forward+)

https://github.com/user-attachments/assets/51c29843-926f-446b-8c18-eef3dd264d45

UI and Menus

https://github.com/user-attachments/assets/f5bd8495-d5e5-49b0-9c95-b56c1d0a076d

Realtime gambit based battles

https://github.com/user-attachments/assets/6207aaa9-eea1-4e0c-811a-0f164694c7c9


---

## Quick start


You need Linux x86_64, `uv`, and an FFT PSX disc image you own.

```bash
# 1. the engine — a Godot 4.8 fork, prebuilt (glibc 2.35+: Ubuntu 22.04+, Arch, Fedora)
#    https://github.com/timbermania/godot/releases/latest
unzip -q ~/Downloads/godot-exmateria-*linux*.zip -d ~/godot-exmateria
sudo ln -sf ~/godot-exmateria/*/godot.linuxbsd.editor.x86_64 /usr/local/bin/godot

# 2. the game
git clone <this repo> exmateria-gambit-tactics
cd exmateria-gambit-tactics

# 3. your disc — extract it first (fft-iso-patcher, or anything that yields the
#    layout SETUP_FROM_SCRATCH.md §1.3 describes), then:
FFT_ISO=/path/to/your/'Final Fantasy Tactics.bin' \
  bash tools/bootstrap_assets.sh /path/to/your/fft-extract

# 4. play
godot --path . res://assets/scenes/NavigatorMain.tscn
```

Bootstrap takes a while, is idempotent, and produces ~800 MB: 156 sprite textures,
119 battle maps, 401 ability effects, 30 animation JSONs, 137 cutscene segments,
`WAVESET.WD` + 100 SMD music files. Then the game walks the FFT opening — the Orbonne
prayer, the Orbonne battle, on to the Military Academy and Gariland, and out onto the
world map. First launch compiles the compute pipelines (30–60 s), but `NavigatorMain`
warms them on a background thread while the opening plays, so it is not a frozen
screen; after that the SPIR-V cache makes it ~30 ms.

### Three things that surprise everyone

- **`project-assets/` lands BESIDE the clone, not inside it** — deliberately, so no
  ROM-derived byte can land in the repository. `$FFT_EXTRACT` overrides it.
- **Use the fork, not stock Godot.** Stock now runs the game rather than cascading
  parse errors, but the display-space effects fall back to in-scene twins nobody has
  compared yet, the native SPU is built against the fork so audio does not load, and
  Godot **rewrites `project.godot` on open**, editing your checkout.
  `SETUP_FROM_SCRATCH.md` §1.1 has the measurements.
- **Never pass `--headless`.** The renderer path the game depends on is not exercised
  without a window.

---

## Platform support

| | |
|---|---|
| **Linux x86_64** | ✅ the exercised platform — what the maintainers run |
| **Windows x86_64** | ⚠️ **unverified.** The native SPU DLLs ship here and a Windows fork editor ships in the [engine release](https://github.com/timbermania/godot/releases/latest), both built by CI; nobody has run the game on Windows. Bootstrap under WSL (the `tools/*.sh` are bash), then run the editor natively — WSLg reaches the GPU only through D3D12 translation. If you try it, report what happens. |
| **macOS, arm64** | ❌ no engine build and no SPU binary; the project will not open. |

---

## Working in it

| path | what |
|---|---|
| `assets/scenes/NavigatorMain.tscn` | **start here** — the story walk, where every system meets: scenario playback, battles, the world map |
| `assets/scenes/GPUArena.tscn` | one battle on its own, no story around it |
| `src/gpu/` | the compute-shader combat engine |
| `addons/exmateria_battlefield/` | terrain, movement, pathfinding, the walk integrator |
| `addons/exmateria_almanac/` | the data tier: abilities, jobs, items, encounters |
| `addons/exmateria_sprite_rig/` | sprite/animation resolution and rendering |
| `addons/exmateria_effects/` | the `E###.BIN` effect runtime and its studio |
| `tools/` | every parser, plus `bootstrap_assets.sh` |
| `docs/adr/` | why things are the way they are — read before changing a subsystem |

`CONTEXT.md` maps the domain vocabulary. Tests:

```bash
bash tests/run_all_tests.sh --sequential

```

---

## Licence

See `LICENSE`. Final Fantasy Tactics is a trademark of Square Enix; this project is not
affiliated with or endorsed by Square Enix, and it ships
none of their data. You supply your own copy of the game.
