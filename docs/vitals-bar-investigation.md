# Vitals bar (HP/MP/CT) — ground-truth investigation (LIVING DOC)

Started 2026-06-19. Purpose: stop trusting the contradictory revision history in
`battle-hud-faithful-spec.md` and re-derive — from **both** dynamic (PCSX-Redux
fork, live RAM + breakpoints + GP0 capture) **and** static (BATTLE.BIN Ghidra
export) analysis — exactly how FFT PSX renders the bottom-left **vitals bars**.

The current Godot reproduction looks bad. The user's three reference images:

1. **with swatch** — the swatch gives the border + background; something then
   "fills" the inside with a *pixelated gradient*.
2. **without swatch** — the bar's exact shape; colours are *pixelated* (a
   palette?).
3. **textures disabled for sprites AND polygons (PCSX GPU debug)** — the bars
   change/disappear. If a primitive vanishes when textures are off, it is
   **textured** (samples a tpage + CLUT). If it survives, it is an untextured
   gouraud primitive. This is the decisive disambiguation we must read carefully.

## The contradiction we are resolving

`battle-hud-faithful-spec.md` flip-flopped:

- Pass 3 / `vitals_bar.gdshader`: bar = **POLY_G4 gouraud quad**, `cur*32/max`
  wide, **"NO separate empty track or sprite behind it."**
- Later pass: bars = **textured SPRT swatch** at atlas (216,202), per-stat warm
  CLUT (`7efc/7f3c/7f7c`), "disable textures for sprites makes them vanish."
- Current code (`UIUnitInfoWindow._layout_bar`): draws **BOTH** — a full-width
  swatch TRACK *and* a gouraud-gradient FILL on top.

These cannot all be true. The GPU-toggle image (#3) is exactly the experiment
that settles textured-vs-untextured. Resolve it from the live GP0 stream, not
from prose.

## Reproduction (user-provided)

1. Load save state **savestate9** in the fork PCSX Release dir.
2. Arm breakpoints / analysis.
3. Press **Down** on the keyboard → vitals view switches from the **Knight**
   (CT 100/100, full bar) to **Ramza** (CT 20/100, partial bar). The bar updates
   somewhere — breakpoint that write/draw.

## Tooling (confirmed this session)

- Fork exe (real ~16MB, has agent surface):
  `C:\Users\acurr\Documents\GitHub\fft-project\vendor\pcsx-redux\vsprojects\x64\Release\pcsx-redux.exe`
- Agent handlers: `...\vendor\pcsx-redux\tools\agent\handlers.lua` (must `-dofile`).
- Drive from WSL via **`cmd.exe /c curl.exe`** POST Lua to
  `http://localhost:8080/api/v1/lua/exec` (urllib can't reach the Windows port).
  Liveness: `.../api/v1/lua/ping` → `pong`.
- Scratch Lua file POSTed as body:
  `/mnt/c/Users/acurr/AppData/Roaming/pcsx-redux/_q.lua`
  (Windows: `C:\Users\acurr\AppData\Roaming\pcsx-redux\_q.lua`).
- Savestates are gzip: `Support.File.zReader(file)` → `PCSX.loadSaveState(...)`.
- No symlinks for any path handed to the Windows exe. No `-portable` for the
  fork (it reads pcsx.json in its own Release dir; Dynarec OFF / Debug ON /
  FastBoot ON / port 8080 already set there).
- Breakpoints MUST be stored in GLOBAL Lua vars (locals get GC'd, silently die).
- Built-in (no Lua): `GET /api/v1/gpu/vram/raw` → full 1MB VRAM.

## Status log

- 2026-06-19: created doc; found a handler-less pcsx on 8080 (all Lua routes
  404). Launched the fork (PID via setsid) with `-dofile handlers.lua`; agent
  answers `pong`.
- 2026-06-19: full RE pass complete (static + dynamic + visual). See Findings.

## How the fork was driven (reproducible)

- Launched fork exe from its Release cwd:
  `setsid bash -c "cd '<release>' && ./pcsx-redux.exe -dofile '<handlers.win.path>' >log 2>&1" &`
- A **fresh** PCSX with no disc starts STOPPED (`vsync_count` never ticks).
  `getCPUCycles()` is the real "is it running" signal — `GPU::Vsync` events may
  not fire even while the CPU executes, so `pad_press` (auto-release on vsync)
  and `pad_status` are unreliable here. Drive the pad DIRECTLY instead:
  `PCSX.SIO0.slots[1].pads[1].setOverride(PCSX.CONSTS.PAD.BUTTON.DOWN)` /
  `clearOverride(...)` (dot-call). The HTTP `pad_set` route returns empty (buggy).
- **Breakpoints stall input.** An Exec/Read BP whose callback calls
  `pauseEmulator()` (or just fires every frame) keeps the emulator paused, so
  pad input never gets polled. CLEAR ALL breakpoints before pressing keys
  (`BP:remove()` each global) and confirm cycles free-run.
- LuaJIT 5.1: no `&` operator — use `bit.band`. Read RAM via
  `PCSX.getMemPtr()` indexed by `bit.band(addr,0x1fffff)`.
- Screenshot: `PCSX.GPU.takeScreenShot()` → `{data(122880 B BGR555), width=256,
  height=240}`; write `data` byte-by-byte to a file, decode `r=(v&0x1f)<<3` etc.

## Data anchors (live, savestate9)

- **Displayed-unit stat buffer base `0x8014D038`** (found by differential scan:
  pressing Down switched the readout's CT 100→20, exactly one byte flipped at
  **`0x8014D050`**). Layout confirmed: cur_hp `+0xc`, max_hp `+0x10`, cur_mp
  `+0x12`, max_mp `+0x16`, **CT cur `+0x18` (=0x8014D050)**, CT max `+0x1c`.
- **Draw function = `0x801352BC`** (in a `??` gap of the static BATTLE.BIN
  export; disassembled live via capstone). Confirmed by Read-BP on `0x8014D050`:
  read by `0x80135AD8` (the `cur*32/max` width calc) and `0x801356E0` (CT clamp
  `slti ,0x65`). Per-unit display/primitive struct: two slots at **`0x8017225C`**
  and **`0x80172548`**, stride **`0x2EC`**.

## FINDINGS — ground truth (each bar = TWO primitives)

Both layers verified three ways: live primitive bytes in the display struct,
the disassembled builder at `0x801352BC`, and pixel measurement of the
framebuffer (incl. a partial CT bar, CT 20/100).

### 1. Swatch / track — TEXTURED SPRT (the casing + empty-region background)
- Primitive **SPRT, code `0x67`** (sized textured rect), `rgbc=0x808080`
  (neutral → texel shown via CLUT unmodulated).
- Built into the display struct at **+0x238 / +0x24c / +0x260** (HP/MP/CT),
  20-byte stride.
- Screen XY **(183,193) / (183,204) / (183,215)**, size **38×6**.
- Atlas **UV (216,202)** into the RANGETILE page (same texel for all three).
- **Per-stat CLUT: HP `0x7efc`, MP `0x7f3c`, CT `0x7f7c`** (VRAM rows 507/508/509,
  warm ramps). This is why "disable textures for sprites" makes the bar casings
  vanish — it's a SPRT. The empty 80% of a partial bar IS this swatch background.

### 2. Fill — UNTEXTURED POLY_G4 gouraud gradient (no texture, no palette)
- Primitive **POLY_G4, code `0x38`**, 4 vertices `[R G B pad][X Y]` (8B/vertex),
  at struct **+0x4 / +0x28 / +0x4c**.
- **width = `cur*32/max`** (full = 32px), **3px tall** (computed at `0x80135AD8`:
  `lh cur(+0xc); sll<<5; div max(+0x10)`). Right edge slides left as the stat
  drops; `cur==0` → width 0 (hidden). A "charging" flag `DAT_80166044` forces
  full width; a selected/blink flag halves all vertex colours (`srl 1`).
- Gradient endpoint vertex RGB (8-bit, read straight from the built prims —
  the spec's "table @0x80168818" does NOT exist in this function; colours arrive
  via runtime `$s1`/`$s2` pointers):
  - **HP**  left `(72,104,120)` → right `(168,184,112)`
  - **MP**  left `(128,64,56)`  → right `(224,160,80)`
  - **CT**  left `(80,104,64)`   → right `(176,176,64)`

### 3. Geometry relationship (why it reads as "fill inside a frame")
- Swatch `x183 w38` → spans x183–221; fill `x187..219 w32`. Fill sits INSIDE the
  swatch with ~4px left / 2px right border. Swatch `y193 h6`; fill `y194 h3` →
  ~1px top / 2px bottom border. The swatch supplies the border + dim background;
  the gouraud fill supplies the bright gradient over the filled width.

### Corrections to the old spec / current code
- `vitals_bar.gdshader` comment "**NO separate empty track or sprite behind it**"
  is **WRONG** — there is a textured SPRT swatch behind every bar. The two-layer
  model in `UIUnitInfoWindow._layout_bar` (track + fill) is STRUCTURALLY FAITHFUL.
- But the current code draws the track at `bar_full_width × bar_height` (32×3) —
  the **same size as the fill**, so it shows no border. The ROM swatch is **38×6**
  and the **32×3 fill is inset inside it**. That missing border/oversize is a
  prime "looks bad" suspect. (Fill colours above match the code's exports.)
- Spec gradient-table address `0x80168818` is unsupported; cite the live prim
  vertices (above) instead.

### Ghidra: fill the `0x80135xxx` `??` gap (so this code is in future exports)

The vitals draw function `0x801352BC` sits in a **`??` raw-bytes gap** of our
BATTLE.BIN export (`project-assets/fft-rom/battle_disassembly.txt`) — the whole
`0x80135xxx` page was undisassembled, which is why every *static* pass missed it
and we had to disassemble it live. This is the same class of problem
`fft-ghidra/tools/ghidra_force_disassemble_battle.py` already solves: it runs
`DisassembleCommand` (the **"D"**) + `CreateFunctionCmd` (the **"F"**) over a
`RANGES` list of code regions the auto-analyzer left as data, then re-runs
analysis.

**Action (do once, in `fft-ghidra`):**
1. Add the page to `RANGES` in `ghidra_force_disassemble_battle.py`, e.g.
   `(0x80135000, 0x80136000)` (entry `0x801352BC`; the function runs to
   ~`0x80135D18`+). The script's D+F+re-analyze handles boundaries.
2. Add a label for it in the BATTLE label set (e.g.
   `BATTLE_draw_vitals_bars` / `vitals_readout_draw` @ `0x801352BC`) so it's
   named in the export — see `fft-ghidra/content/` tsvs + `LABELS.md`.
3. Re-run `fft-ghidra/tools/export_ghidra_text.sh` to regenerate
   `battle_disassembly.txt` / `battle_decompilation.c` with the function present.

After that, the bar renderer is statically citable by address (per the repo's
"Ghidra references: use addresses" rule) instead of needing a live capstone dump.

### Open / next (implementation, not RE)
- Reconcile `RangeTileAtlas.bar_swatch_rect()` against UV (216,202) 38×6 and the
  three CLUTs `0x7efc/7f3c/7f7c`.
- Make the track 38×6 and inset the 32×3 fill (per the geometry above).
- Revisit the `pow(2.2)`/brightness on both layers vs the measured framebuffer
  (PSX untextured gouraud outputs vertex colour ~directly; the swatch is a dark
  CLUT drawn "hot").
