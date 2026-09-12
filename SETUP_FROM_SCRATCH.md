# Setting up the game from a fresh clone (Linux)

This document captures **every** step required to take this game from a freshly
cloned repo to a running GPUArena scene on Linux. Most steps have been folded
into `tools/bootstrap_assets.sh`; the manual walkthrough exists so you (or
future-you) can debug when something goes sideways.

**Every command in this document is run from the package root** — the
directory holding `project.godot`. In a monorepo checkout that is
`godot-learning/`; in a standalone clone it is the clone itself.

If you just want it to work:

```bash
bash tools/bootstrap_assets.sh /path/to/your/fft-extract
```

The rest of this doc explains what that script does, why each step exists, and
what's still NOT automated.

---

## 1. Prerequisites

### 1.1 System packages

| package | why |
|---|---|
| `godot` ≥ 4.6 (Forward+ Vulkan renderer) | the game runs on Vulkan compute shaders; OpenGL3 fallback cannot run `RenderingDevice` |
| **a Vulkan ICD for your GPU** | the Vulkan loader (`vulkan-icd-loader`) is not enough — without an ICD package `RenderingServer.create_local_rendering_device()` returns `null` |
| `uv` | Python tooling: every parser is invoked via `uv run python …`; deps are pinned in `tools/pyproject.toml` |
| `glslangValidator` / `glslc` (optional) | for offline SPIR-V validation of the compute shaders |

Arch example:

```bash
sudo pacman -S godot vulkan-intel uv glslang shaderc
#                  ↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑  (or vulkan-radeon / nvidia-utils / etc.)
```

**Verify Vulkan works** before continuing:

```bash
godot --version
# If on launch you see: "Required extension VK_KHR_surface not found" or
# "switching to OpenGL 3", you're missing the ICD. Install vulkan-<vendor>.
```

### 1.2 FFT PSX extract

You need an extracted FFT PSX disc with this top-level layout:

```
fft-extract/
├── BATTLE/        # .SPR, .SEQ, .SHP per character class
├── BATTLE.BIN     # main combat code/data
├── EFFECT/        # E000.BIN .. E511.BIN — spell/ability visual effects
├── EVENT/
├── MAP/           # MAP001.GNS, MAP001_0.MAP, … per battle map
├── MENU/
├── OPEN/
├── SCEAP.DAT
├── SCUS_942.21    # main executable
├── SOUND/         # SMD music + WAVESET
├── SYSTEM.CNF
├── WORLD/
└── Final Fantasy Tactics (USA).bin / .cue
```

You can get this from your own ISO via `fft-iso-patcher`:

```bash
fft-iso-patcher extract /path/to/Final\ Fantasy\ Tactics.bin \
    --out /wherever/you/want/fft-extract
```

The bootstrap script takes this directory as its argument and symlinks it into
`project-assets/fft-extract/` (see §3).

#### Where `project-assets/` actually lands — and why it is probably not where you expect

**`project-assets/` sits BESIDE this package, not inside it.** `tools/_repo_paths.py`
resolves the extract in this order:

1. an explicit path passed on a tool's command line
2. `$FFT_EXTRACT`
3. `<the package root's PARENT>/project-assets/fft-extract`

Rule 3 is the one worth reading twice, because the parent means different things
in the two checkout shapes:

```
MONOREPO CHECKOUT                    STANDALONE CLONE
fft-monorepo/                        some-dir/
├── project-assets/   ← here         ├── project-assets/   ← here, OUTSIDE the clone
│   └── fft-extract/                 │   └── fft-extract/
└── godot-learning/   ← package      └── exmateria-gambit-tactics/   ← package AND repo root
    └── project.godot                    └── project.godot
```

In a standalone clone the package root *is* the repo root, so "the parent" is the
directory you cloned **into**. `project-assets/` is therefore a sibling of the
clone and not part of it.

**That is deliberate, not a bug.** No ROM-derived byte ever lands inside the
repository, so there is nothing for a stray `git add` to commit and no `.gitignore`
rule carrying the weight of that guarantee. It does mean a fresh clone looks like
this before bootstrap, which surprises people:

```bash
git clone <url> exmateria-gambit-tactics
cd exmateria-gambit-tactics
# the extract goes ../project-assets/fft-extract, NOT ./project-assets
bash tools/bootstrap_assets.sh /path/to/your/fft-extract
```

**If you want it somewhere else, set `$FFT_EXTRACT`** — it beats rule 3 for every
tool, so you never have to move an extract you already have:

```bash
export FFT_EXTRACT=/mnt/roms/fft-extract
```

### 1.3 The audio source-of-truth tree

`addons/exmateria_sound/` and `addons/exmateria_spu/` are **gitignored in both
checkouts** — they are copies, and `tools/sync_exmateria_sound.sh` makes them. What
it copies FROM is the part that differs, and you do not have to care which case you
are in: the script picks.

```bash
bash tools/sync_exmateria_sound.sh      # bootstrap_assets.sh runs this for you
```

`pick_src()` takes the sibling checkout when there is one and this repo's own
`vendor/` when there is not:

```
MONOREPO CHECKOUT                      STANDALONE CLONE
fft-monorepo/                          exmateria-gambit-tactics/   ← package AND repo root
├── godot-learning/   ← this package   ├── vendor/                 ← the source, shipped
│   └── vendor/       (also present,   │   ├── .gdignore           ← keeps Godot out
│                      unused here)    │   ├── exmateria_sound/    315 files
└── exmateria-sound/  ← preferred      │   └── exmateria_spu/       23 files
    ├── addons/exmateria_sound/        └── addons/                 ← the sync writes here
    └── addons/exmateria_spu/
```

**There is no sibling `exmateria-sound/` in a standalone clone, and nothing is
missing.** This section used to say that checkout "MUST exist", which is true in the
monorepo and impossible in the repo this package ships as. The clone carries 373
tracked files under `vendor/` — the two sound addons plus `fft_iso_patcher` — and
bootstrap works with no extra checkout at all.

**Why `vendor/` is masked.** `vendor/exmateria_sound/` holds the same `class_name`
declarations as the synced copy under `addons/`, so if Godot scanned both it would
see every class twice. `vendor/.gdignore` stops the scan at that directory: the files
are source to be copied, never source to be parsed in place. The sync is what makes
them live.

⚠️ **`.gdignore` stops a scan; it cannot clean a cache.** If you ever see duplicate
`class_name` errors or stale `res://vendor/…` entries, delete `.godot/` and let it
rebuild — a cache written before the mask existed keeps its entries.

If the script cannot find either source it says which case failed and exits; in the
monorepo the fix is `tools/vendor_packages.py`, which is what populates `vendor/`.

**About the native library:** `vendor/exmateria_spu/bin/` ships a committed Linux
x86_64 build, so a clone needs no compiler. In the monorepo you can instead build it
with `scons` from `exmateria-sound/`. Every other platform is a real gap — see
*Platform support* below before assuming this runs anywhere else.

#### Platform support — Linux x86_64 only, and the reason is the SPU

`addons/exmateria_spu/exmateria_spu.gdextension` declares **twelve** library
slots. **One of them has a binary**, and this repository ships it committed:

| slot | ships? |
|---|---|
| `linux.debug.x86_64` | ✅ committed (1.4 MB), what the editor loads |
| `linux.release.x86_64` | ❌ absent — an **exported release build fails even on Linux** |
| `linux.{debug,release}.arm64` | ❌ absent |
| `windows.{debug,release}.{x86_64,arm64}` | ❌ absent |
| `macos.{debug,release}[.arm64]` | ❌ absent |

**This is not a soft degrade.** The SPU's twenty-four voices are mixed by a
native C++ core; the addon's own README says a tree without the compiled library
means "nothing will load". There is no GDScript mixer to fall back to, so on any
platform above without a binary the project does not open — it is a
parse-error cascade, not silent muting.

**And you cannot build one from this repository.** `addons/exmateria_spu/` ships
the GDScript runtime, the `.gdextension` and the prebuilt library — **no C++
source and no `SConstruct`**. Those live in the `exmateria-sound` project, which
is a separate repository. To run on Windows, macOS or arm64 you need to build
`libexmateria_spu` from *that* repository for your platform and drop the result
into `addons/exmateria_spu/bin/` under the exact filename the table above names.

Why the missing three were not simply cross-compiled and committed: measured on
the maintainer's box, no toolchain for any of them is present (`mingw-w64`,
`osxcross`, `aarch64-linux-gnu-g++` all absent), and macOS additionally needs
Apple's SDK, whose licence expects Apple hardware. Cross-building them is a real
task in the `exmateria-sound` repository, not a packaging oversight here.

---

## 2. What "fully set up" means

After the bootstrap, the following should be true:

- `godot --path . res://assets/scenes/GPUArena.tscn` launches into
  Forward+ Vulkan with no `No rendering device available` error.
- The first launch compiles the per-stage compute shaders (≈ 30–60 s on
  Intel iGPU, longer on cold NVIDIA — see `docs/`/timing notes).
  Subsequent launches hit the SPIRV cache in ~30 ms.
- `[GPU Arena] GPU simulator ready` appears in stdout.
- A battle map renders with unit sprites positioned on terrain (not stacked at
  origin), portrait colours correct, in-game text legible.
- Effects in the Effect Viewer are populated.

---

## 3. Manual walkthrough (what the script does, in order)

The numbering matches the function calls in `tools/bootstrap_assets.sh`.

### 3.1 Symlink the ROM extract into `project-assets/fft-extract/`

`project-assets/` is the canonical place for ROM-derived content. Every parser
defaults to looking for FFT data there, and it resolves to the package root's
PARENT — inside `fft-monorepo/` in a monorepo checkout, and beside the clone in a
standalone one. §1.2 has the resolution order and both layouts; `$FFT_EXTRACT`
overrides it. (In the monorepo, `SETUP.md` at the repo root covers the same ground
for every package.)

```bash
mkdir -p ../project-assets/fft-extract      # ../ — see §1.2
cd ../project-assets/fft-extract
for entry in /path/to/your/fft-extract/*; do
    name=$(basename "$entry")
    [ -e "$name" ] && continue        # don't clobber e.g. local sfx_banks/
    ln -s "$entry" "$name"
done
```

> **Why symlinks, not copies?** The extract is ~700 MB and you'll likely have
> it on disk somewhere already. `SETUP.md` explicitly recommends the symlink
> approach.

> **What about `SOUND/`?** If `project-assets/fft-extract/SOUND/` already
> exists (e.g. from a prior `sync_exmateria_sound` run), skip the symlink so
> you don't shadow whatever's already there. The `for` loop above handles
> this with the `[ -e ]` check.

### 3.2 Create asset output directories

The parsers write into these but don't `mkdir -p` them:

```bash
mkdir -p assets/sprites/animations \
         assets/sprites/textures \
         assets/ui \
         assets/fonts \
         assets/effects \
         assets/maps
```

### 3.3 Apply code patches

Several scripts and one runtime path need small, **idempotent** edits to work
on a case-sensitive filesystem. The bootstrap script applies them with `sed`
guarded by a "already patched?" `grep`, so re-running is safe.

#### 3.3.1 `tools/parse_seq.py` — extend `--all` list

The `parse_all_seq_files()` list is missing `WEP1/WEP2/EFF1/EFF2.SEQ`, so the
runtime errors with `File not found: …/wep1_seq.json …/eff1_seq.json`.

Add inside the `seq_files = [...]` literal:

```python
        ("OTHER.SEQ", "other_seq.json"),
        ("WEP1.SEQ", "wep1_seq.json"),
        ("WEP2.SEQ", "wep2_seq.json"),
        ("EFF1.SEQ", "eff1_seq.json"),
        ("EFF2.SEQ", "eff2_seq.json"),
    ]
```

#### 3.3.2 Parser path-resolution (no more hardcoded WSL paths)

All parsers in `tools/` previously hardcoded WSL-shaped paths like
`/mnt/c/Users/acurr/Documents/fft-extract/...`. They now import from a shared
helper, `tools/_repo_paths.py`, and auto-resolve to `project-assets/fft-extract/`
relative to the script's location on disk.

The helper's priority order:

1. an explicit CLI argument (`--fft-extract`, `--scus`, `--battle`, etc.)
2. the `FFT_EXTRACT` environment variable
3. `<repo>/project-assets/fft-extract/` computed from the script location

This means **the parsers** work identically on Linux, WSL, macOS, and Git Bash
on Windows — with zero configuration as long as the FFT extract lives at
`project-assets/fft-extract/`. They are stdlib Python and care about nothing else.

⚠️ **That is a claim about the parsers, not about the game.** Running the game
needs the native SPU library, and that ships for Linux x86_64 only — see
*Platform support* in §1.3. A reader who extracts an ISO on macOS gets correct
assets and a project that will not open.

Patched parsers (all retain backward-compatible CLI overrides):
- `parse_seq.py`, `parse_shp.py` (BATTLE/ directory)
- `parse_layer_priority.py`, `parse_sprite_types.py`, `parse_fft_font.py` (BATTLE.BIN)
- `parse_abilities.py` (SCUS_942.21 + BATTLE.BIN + EFFECT/)
- `parse_all_effects_py.py` (EFFECT/)
- `parse_frame.py` (FFT extract root)
- `extract_all_sprites.py` (FFT extract root + portrait-palette default flipped from 0 → 8)

#### 3.3.3 `src/ui3/elements/UIPortrait.gd` — case-fix

One-line change at line 158:

```diff
- var texture_path = "res://assets/sprites/textures/%02x.tga" % sprite_id
+ var texture_path = "res://assets/sprites/textures/%02X.tga" % sprite_id
```

**Why:** the extractor produces `6C.tga` (upper hex). Every *other* code path
in the game uses upper hex (via `to_upper()` or by reading the `'spr_file':
'6C.SPR'` field straight out of `sprite_types.json`); only this one line used
`%02x`. On case-insensitive filesystems (Windows, macOS-default) this
mismatch is invisible. On Linux it breaks portrait loading for every
hex-named sprite that contains an A–F.

#### 3.3.4 `assets/scenes/Unit.tscn` (case symlink)

The file is committed to git as `unit.tscn` (lowercase) but six call-sites
(`PartyRoster`, `EnemyRoster`, `EffectViewerScene`, `TrapViewerScene`,
`ProgressionTester`, `ProjectileTester`) load it as `Unit.tscn`. Symlink the
canonical case so both resolve:

```bash
ln -sfn unit.tscn assets/scenes/Unit.tscn
```

> Godot will warn `Case mismatch opening requested file ... stored as ... in
> the filesystem` at load time — the warning is cosmetic; loading succeeds
> via the symlink.

### 3.4 Sync the audio addon

`addons/exmateria_sound/` and `assets/music/` are gitignored. The sync script
copies them from `exmateria-sound/` and `project-assets/fft-extract/SOUND/`:

```bash
bash tools/sync_exmateria_sound.sh
```

This populates `addons/exmateria_sound/{bin,runtime,fft_spu.gdextension,…}`
and `assets/music/{WAVESET.WD, MUSIC_*.SMD}` (100 music files).

If you skip this, the `ExMateriaAudioEngine` and `MusicPlayer` autoloads will
fail to find the addon and music will not play; the game still runs. The error
text moved with `#383`: the addon reaches its own scripts by `preload` path now,
so a missing folder reports `Preload file ".../spu.gd" does not exist` rather
than an undeclared identifier.

### 3.5 Run the parsers

Every parser auto-resolves its inputs to `project-assets/fft-extract/` via the
shared `tools/_repo_paths.py` helper. None of them need path arguments
anymore — you can `cd tools/` and run them with no flags:

```bash
cd tools

uv run python parse_seq.py --all
#   → assets/sprites/animations/{type1,type2,…,wep1,wep2,eff1,eff2}_seq.json

uv run python parse_shp.py --all
#   → assets/sprites/animations/{type1,…,wep1,wep2,eff1,eff2}_shp.json

uv run python extract_all_sprites.py
#   → assets/sprites/textures/{00..FF}.tga + WEP1.tga, EFF1.tga, TRAP1.tga
#   Note: --portrait-palette now defaults to 8 (matches in-game colours).
#   Previously the wrapper defaulted to 0, which baked in wrong portrait colours.

uv run python parse_layer_priority.py
#   → assets/sprites/layer_priority.json

uv run python parse_all_maps.py "$FFT_EXTRACT_DIR/MAP" --force
#   → assets/maps/MAP???/{geometry_linked.json, manifest.json, …}
#   (parse_all_maps is the one parser that still takes the MAP path
#    positionally; the bootstrap script supplies it.)

uv run python parse_abilities.py
#   → assets/abilities/effects.json, assets/abilities/fft_names.json

uv run python parse_all_effects_py.py
#   → assets/effects/E000..E511/{emitters.json, timeline.json, texture.tga, …}

uv run python parse_fft_font.py "$FFT_EXTRACT_DIR/BATTLE.BIN" -o ../assets/fonts
#   → assets/fonts/{font_atlas.tga, font_meta.json}
#   (parse_fft_font still wants an explicit -o; otherwise output lands in
#    tools/assets/fonts/ — wrong place.)

uv run python parse_frame.py
#   → assets/ui/frame.tga
```

All parsers honour the `FFT_EXTRACT` environment variable if you want to
point them at a different extract location without symlinking.

### 3.6 Trigger Godot's import pass

After all of the above, the `.godot/` cache is stale (missing `.import` files
for every new TGA/JSON). Run:

```bash
godot --import --path .
```

This briefly opens the editor, imports every new resource, and quits. The
`.godot/imported/` directory gets populated and `global_script_class_cache.cfg`
gets refreshed.

> The `--import` flag is **not** `--headless`. It's a legitimate one-shot
> import; CLAUDE.md's "never run Godot headless" rule applies to running the
> *game*, not the importer.

### 3.7 Launch

```bash
godot --path . res://assets/scenes/GPUArena.tscn
```

First launch: 30–60 s of GPU pipeline compilation (you'll see
`[GPUBatchSimulator][TIMING] stage_compute COMPILE total=XXXms pipeline_create=…`
lines — `stage_compute` is by far the long pole). Subsequent launches:
cache-hit in ~30 ms.

---

## 4. Known issues NOT yet automated

These are real gaps but didn't block bringing the scene up:

### 4.1 `*_names.json` files (type1, wep1, eff1) are not regenerated

`AnimationData.gd` (long gone -- ADR-0034 replaced it with `UnitAnimationSet`) referenced
`assets/sprites/animations/{type1,wep1,eff1}_names.json` but no parser in
`tools/` produces them. They appear to be hand-authored or generated by a
defunct tool. Runtime logs them as `ERROR` but continues; on-screen text
labels read the names from `assets/abilities/fft_names.json` (which §3.5.6
does produce), so the visible impact is small.

### 4.2 Map / doodad palettes (`generate_palette_texture.gd`)

`tools/generate_palette_texture.gd` is a Godot `@tool EditorScript` that
walks `assets/doodads/MAPxxx/palettes.json` and writes a palette texture for
the map-tile palette-animation shader. The bootstrap script can't run an
EditorScript from the CLI; if you see washed-out doodads, open the project in
the Godot editor and run `File → Run → generate_palette_texture.gd`.

### 4.3 The shader-refactor work (`stage_*.glsl`)

The 5-pass per-stage compute shader split (`src/gpu/shaders/`) is a separate
code change — not produced by this bootstrap. It lives in source control on
the `redesign-battle-compute-shader` branch. Once that branch merges to
`main`, all clones use the split; until then, fresh clones of `main` may
still carry the older single-file `combat_batch.glsl` layout, which is
functionally identical but pays a larger cold pipeline_create cost.

---

## 5. Bootstrap script reference

`tools/bootstrap_assets.sh`:

```
Usage:
    bash tools/bootstrap_assets.sh <path-to-fft-extract>
or:
    FFT_EXTRACT=/path/to/fft-extract bash tools/bootstrap_assets.sh
```

The script:

1. Validates the extract directory contains the expected files
   (`BATTLE/`, `BATTLE.BIN`, `MAP/`, `EFFECT/`, `SCUS_942.21`)
2. Validates that `godot` and `uv` are on `$PATH`
3. Verifies a Vulkan ICD is registered (prints a warning if not, doesn't abort)
4. Performs §3.1 through §3.6
5. Prints a clear summary at the end

It is **idempotent** — re-running it is a no-op for steps already done. You
can re-run after updating the FFT extract to refresh parsed assets.

---

## 6. Troubleshooting cheat sheet

| symptom in log | what to check |
|---|---|
| `Required extension VK_KHR_surface not found` | install Vulkan ICD (`vulkan-intel`, `vulkan-radeon`, etc.) |
| `No rendering device available` | same — Godot fell back to OpenGL3, which has no RenderingDevice |
| `Parse Error: Identifier "WavesetParser"` / `"Spu"` | run `tools/sync_exmateria_sound.sh` (it syncs BOTH addons); ensure `exmateria-sound/addons/exmateria_spu/bin/libexmateria_spu.linux.*.so` exists |
| `FATAL: Could not open …/type1_seq.json` | run `parse_seq.py --all` (§3.5.1) |
| `Resource file not found: …/sprites/textures/6C.tga` | did you keep the canonical UPPERCASE filenames? do NOT lowercase them; instead patch `UIPortrait.gd` (§3.3.3) |
| `Cannot open file 'res://assets/scenes/Unit.tscn'` | create the case-fix symlink (§3.3.4) |
| `DoodadLibrary: Doodad not found: 'MAP042'` | run `parse_all_maps.py` (§3.5.5) |
| `UIFont: Cannot load atlas texture at …/font_atlas.tga` | re-run `parse_fft_font.py` with absolute `-o` (§3.5.8) |
| `Assertion failed: Animation 60 timing mismatch` | (resolved by `tools/opcodeParameters.txt` being bundled in the repo; if it returns, re-run `parse_seq.py --all`) |
| First launch sits compiling for minutes | expected — driver pipeline_create on `stage_compute` (or original `PASS_COMPUTE`) is the long pole; cached on subsequent runs |
| Game re-imports every TGA on every launch | check `assets/sprites/textures/` for both `6c.tga` and `6C.tga` — only one canonical case should be present (UPPERCASE for hex names) |
