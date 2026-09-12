# Faithful Battle-HUD Spec (hardened — RE pass + grilling)

Goal: reproduce FFT PSX's **in-battle HUD** (the layer that appears during
active combat) with the same assets, in the same screen positions, with the
same behavior. Scope decided 2026-06-16: **in-battle HUD only** — not the
prep/equip/job menus, not formation/victory screens. Hardened 2026-06-17 via
`/grill-with-docs` → scope narrowed to the **feedback HUD** (see "Combat model &
scope" below); decisions captured in that section's "Resolved decisions".

This is the output of a static reverse-engineering pass over:

- `project-assets/fft-rom/hacktics_disassembly.txt` — 471 MB Ghidra export of
  BATTLE.BIN / WORLD / SCUS (+ overlays incl. HELPMENU.OUT), with ~2,357
  human-named labels (FFHacktics community RE work). **Primary source.**
- `project-assets/fft-rom/hacktics_symbols.tsv` — derived index:
  `name <TAB> xref_count <TAB> SECTION::firstaddr` (2,357 rows).
- `project-assets/fft-rom/scus_disassembly.txt` — our SCUS export.

> Status legend: **[FACT]** = read directly in disasm. **[INFER]** = deduced.
> **[CAPTURE]** = needs PCSX-Redux live confirmation (see §8). Addresses are PSX RAM.

---

## Combat model & scope (resolved in grilling, 2026-06-16)

This game is a **gambit-driven auto-battler**: the GPU compute engine is the
sole writer of battle state (`Battle-state authority`, ADR-0031); units fight
autonomously by evaluating player-authored gambits. That makes FFT's whole
**command** layer (the player taking a unit's turn) foreign to this game.

Faithfulness rule inherited from the project: **take FFT's visuals, remap the
meaning** (the `Battle range-overlay tile` precedent). Feedback elements are
mostly literal (same digit sprites, same over-unit placement); anything that
implies FFT's turn/command semantics is re-mapped to this game's model.

### Resolved decisions

1. **Combat control = hybrid, but the command half is future.** A
   *pause-and-command* capability is desired but **not yet built**; when built
   it is a **"command gambit"** — a one-shot gambit *action* like the existing
   move-to-tile (`ACTION_MOVE_TO`), flowing through the normal
   `Gambit→GPU projection → encode schema → buffer` path. The CPU never becomes
   a battle-state writer; it enqueues intent the shader consumes. (No ADR-0031
   carve-out needed.)
2. **This spec is the FEEDBACK HUD only** — it *observes* GPU-authored state and
   issues nothing. The COMMAND HUD (action menu §2, target/AoE **selection**
   cursor — the command part of §4) is **out of scope**; it belongs to the
   future command-gambit feature and will be re-specced then. Its RE is retained
   below (marked OUT OF SCOPE) so the work isn't lost. (The §4 cursor's
   *input/bob* already shipped — ADR-0046; only the selection use is out.)
3. **No turn-order display (vanilla).** FFT PSX has none to reproduce; the GPU
   sim already tracks CT for *acting*, so with nothing on screen we build no
   predictor. Revisit only if watching real battles proves you can't follow the
   action. (§1 retained as RE reference, OUT OF SCOPE.)
4. **Additive, not a replacement.** Build the faithful feedback elements *on top
   of* the current combat UI (roster bars, detail menus, gambit config stay).
   Long-term intent is to **deprecate the pieced-together parts where FFT has an
   equivalent**, incrementally and later — game-original pieces (gambit config
   above all) are kept deliberately. Nothing is removed by this spec.
5. **Presentation splits by placement** (ADR-0063). *Over-unit* elements —
   damage/heal/miss numbers and status/charge bubbles — are **unit-anchored 3D
   billboards** (shader enhancement or a child billboard), CUSTOM0 GTE depth,
   enrolled in `combat_visuals` for the ADR-0037 freeze; matches FFT
   (GTE-projected, `+0xC` raise), not a 2D overlay. *Screen-space* elements —
   the **unit-info window** and any menu-like panel — are **ordinary `ui3` HUD**
   at a fixed screen position, NOT billboards. Over-unit ownership nuance:
   persistent status/charge bubbles fit as a unit-child; transient damage numbers
   may be map-anchored (like `Projectile`) so the killing blow's number survives
   the unit's death-frame.
6. **Data comes from existing GPU signals/snapshot, not the ROM.** Damage
   numbers consume `CombatLoop.hp_changed(unit_index, prev_hp, new_hp, delta)`
   (GPU-authoritative, from `GPUCombatInterpreter`'s `HP_CHANGED`
   {`was_heal`, `killed`}); icons read status flags from the snapshot; the info
   window reads our own `UnitStats`. The HUD is a new **apply-only consumer** —
   it never reads FFT's `BattleUnitData` (so §8.5 is moot for us) and never
   writes battle state.
7. **Assets = RANGETILE texels + a new metadata parse.** The digit/icon texels
   live in the already-extracted `RANGETILE.tga` system atlas (256×256, with
   `RANGETILE.palette.tga`). `tools/parse_range_tiles.py` already emits tile +
   cursor UV rects into `RANGETILE.json`; **extend it** to also emit the
   damage-digit cells and status-icon cells (UV rects + CLUT/palette rows),
   sourced from the BATTLE.BIN tables the RE located (`Status_Bubble_Icon_X/Y`
   ~`0x800949dc`, digit cell geometry `0x10`/`0x0E`). No new texture extractor —
   metadata only.
8. **§3 inspect = field-inspect.** A faithful FFT info window opens when the
   player points/clicks a unit **on the battlefield** (3D pick,
   `collision_mask = 4`), added *alongside* the existing roster→StatsMenu path.
   Faithful part is the **layout/appearance** (FFT frame, font, field
   positions); data is our own. Keep field-inspect (read-only) distinct from the
   portrait-click that opens management menus.

### Build plan (sequence)

1. **Damage/heal/miss numbers** (§5) — headline addition; consumes `hp_changed`.
   Needs: RANGETILE digit-cell metadata parse (§7), a unit-anchored billboard
   number renderer (§5), type→colour mapping (damage/heal/miss/MP).
2. **Status & charge/CT icons** (§6) — unit-child billboard reading snapshot
   status flags; reuses the same RANGETILE metadata parse.
3. **Field-inspect info window** (§3) — 3D unit pick → FFT-style info window from
   our `UnitStats`; FFT layout, our data.

OUT OF SCOPE (RE reference only): §1 turn-order, §2 action menu, §4
selection-cursor (command use).

### Open questions for build time (non-blocking)

- Damage numbers: unit-child vs map-anchored (death-resilience trade-off, §5/dec 5).
- Field-inspect: click vs hover; does inspect also place a tile cursor on the unit?
- Info window: live-updating while the inspected unit moves/acts (yes — reads snapshot).
- Exact FFT screen positions / CLUT for digits, icons, info window → §8 CAPTURE.

---

## 0. Cross-cutting RE findings (apply to everything below)

- **Window frames + menu font live in an overlay, `HELPMENU.OUT`**, loaded at
  `0x801df000+`. Frame/font rasterizer is `FUN_801df050` (init `FUN_801df000`).
  It uses PSX GPU prims directly (`GetTPage`, `SetSemiTrans`). **[FACT]**
- **Two text paths.** `FntPrint` @ `0x800235ac` (SCUS) is the PSY-Q debug font.
  Player-facing glyphs are sprite quads through `BATTLE_text_character_handling`
  (~`0x801307xx`), fed by the message/format system
  (`BATTLE_text_format_string_fetch`, ~`0x80105xxx`). Don't confuse them. **[FACT/INFER]**
- **VRAM texture pages seen:** window/menu font at **TPage `0x3c0`, VRAM x=`0x100`**;
  dialogue/help box at **TPage `0x3c0`/`0x340`, ty=`0x100`**, CLUT coords
  `0x7c3c`/`0x7e7c`/`0x7d7c`/etc. Exact CLUT contents need a VRAM capture. **[FACT→CAPTURE]**
- **On-screen billboards (numbers, status icons, cursor)** are GTE-projected from
  the unit's 3D coord, with a **`+0xC` px vertical raise** so they float above the
  sprite. Projected screen XY is cached at unit-struct `+0x120`/`+0x122`. **[FACT]**
- **Screen cull window:** X ∈ `[0x61, 0x61+0x13f]`, Y ∈ `[-0x1f, -0x1f+0x12f]`
  (~320×240 with margins). **[FACT]**

---

## 1. AT / turn-order list  — ⛔ OUT OF SCOPE (vanilla: no display; RE reference only)

**Headline: vanilla FFT PSX has NO persistent on-screen turn-order sidebar.**
The "AT list" in the code is a **predictive CT simulation**, consumed
numerically, not rendered as a list. The portrait sidebar people associate with
"FFT turn order" is a **War of the Lions / hack feature** absent from this
BATTLE.BIN. **[FACT — no list-draw routine exists in these symbols]**

The simulation (fully specified, reproducible):

- 40-entry array (`slti …,0x28` = 40 everywhere), built into a stack buffer.
  Per-entry stride **4 bytes**: `byte[0]`=unit battle_id (low 5 bits; bit `0x40`
  / `+0x100` = action-vs-move / multi-turn flags), `byte[1]`=action/skillset
  marker, `half[2]`=**CT × 100** (the sort key). **[FACT]**
- Tick model: each unit's CT += Speed per tick; acts at **CT ≥ 100**
  (`sltiu …,0x64`); insert in sorted order via `BATTLE_at_list_sorting`. **[FACT]**
- Functions: `BATTLE_calculate_AT_list` (~`0x80183700`),
  `BATTLE_at_list_sorting` (~`0x80183ae0`),
  `BATTLE_at_list_preview` (~`0x801835fc`),
  `BATTLE_get_number_of_turns_to_resolve` (~`0x80181724`),
  `BATTLE_calc_tile_coords_and_glow_from_at_list` @ `0x80074b6c` (the **only**
  screen consumer — moves a tile glow/cursor to the active unit, not a list).
- `BATTLE_AT_List_ID` @ ~`0x800960fc` is a mode flag (0/1), not a list buffer.

**Decision for /grill-with-docs:** "the same one FFT has" = no sidebar, only the
numeric "turns to act" preview shown on the action-confirm. If we instead want a
WotL-style portrait/CT sidebar, that is *our* UI built on the (faithful) CT
prediction model — there is no ROM draw reference to match. **Pick one before building.**

UnitBattleData table base: `0x8019xxxx` segment, units at **0x1c0 stride**. **[FACT]**

---

## 2. Action command menu (Move / Act / Wait / Status)  — ⛔ OUT OF SCOPE (future command-gambit; RE reference only)

Not a single draw fn — a **menu-script / thread engine**: game-state selects a
builder → builder fills a menu struct → menu **thread** walks items each frame →
`HELPMENU.OUT` rasterizes frame+font → input resolver reads the choice. **[FACT/INFER]**

Key functions **[FACT]**:

| Role | Function | Addr |
|---|---|---|
| Root menu builder | `Build_Idle_Action_Menu` | `0x8013cf50` |
| Main menu (threaded) | `Build_Main_menu` | `0x80140900` |
| Per-frame menu body | `Display_Simple_Selection_Menu` | `0x80138ed4` |
| Menu-item primitive builder | `FUN_80138570` | `0x80138570` |
| Menu thread | `Menu_Building_Thread` | `0x8013c280` |
| Input → selection | `Data_setting_from_menu_selections` | `0x8013f528` |
| Frame+font raster (overlay) | `FUN_801df050` | `0x801df050` |
| Set menu script | `SetActionMenuScript` | `0x80070bf8` |

- **Menu struct layout [FACT]:** `+0x8`=screen X, `+0xa`=screen Y, item poly
  array at `+0x18`, active-item index at `+0x38`. Per-item **row height 0x10
  (16 px)**, first row Y offset `+0xa`. Struct copy size `0x7c` bytes.
- **Command source [FACT]:** the static `Skillset` table @ `0x80065cb4`
  (`[1]=Attack [2]=Defend [3]=EquipChange [6]=Item [17]=Geomancy [18]=Jump
  [19]=DrawOut [20]=Throw [21]=Math …`). Root entries map to skillset IDs; the
  "Act" submenu reuses `Display_Simple_Selection_Menu` with the unit's ability list.
- **Command strings** are message IDs resolved by the text system and drawn via
  the font path — not inline literals (e.g. `Move_Confirm_Menu` @ `0x80071b30`
  passes message id `0x183b`). **[FACT]**
- **Highlight:** semi-transparent sprite over the active row; variant byte 7 vs 2
  chosen in `FUN_801df050`. **[FACT]**
- `ActionState` @ `0x8017c98c` is the **act-resolution sub-state machine** (45
  xrefs in the spell-handler region), *not* the visual cursor index. **[FACT]**

---

## 3. Unit-info window + help / dialogue bar  — ✅ IN SCOPE (field-inspect; FFT layout, our data)

- **Populate from cursor [FACT]:**
  `BATTLE_store_name_and_unit_data_under_cursor` (~`0x8006ee70`) reads
  `BATTLE_Cursor_X/Y/Z`, resolves the unit, copies name + battle data into the
  display buffers. Variants `_cursor2` (acting unit) and `_caster`.
  Unit-display struct → `UnitBattleData` ptr at **`+0x134`**; unit/job/sprite id
  byte at **`+0x18a`**; status-flags byte at **`+0x58`**.
- **Status / full-info window [FACT]:** `BATTLE_display_inner_character_window`
  (~`0x80133cf8`) pulls `BattleUnitData*` via
  `BATTLE_get_battle_stats_from_battle_id`, builds 20-row + 8-cell tables, walks
  a **5×8 status-flag grid** to list active statuses, ends in
  `BATTLE_maybe_build_scrollable_menu`.
- **Help-open trigger [FACT]:** fn @ `0x80070ca0` sets
  `BATTLE_Help_Menu_Is_Opening = 1` (@ `0x800960ec`), populates, starts the menu
  thread. `BATTLE_Status_Menu_Requested` @ `0x800960f8`.
- **Text section select [FACT/INFER]:** `BATTLE_Status_Text_Data_Index` is a
  40-byte grid→string-id table (`FF FF 00 01 FF … 1A 1B`; `0xFF`=empty), matching
  the 5×8 status loop.
- **Dialogue/help box geometry [FACT]:** initializer `FUN_8012e348` builds **6
  box slots** (stride `0x230`/`0x118`), sprites via
  `BATTLE_makeDefaultSprites_withCLUT` (CLUT `0x7c3c`/`0x7e7c`),
  `GetTPage(abr=2, tx=0x3c0/0x340, ty=0x100)`, position bytes X
  `0xa8`/`0xb8`/`0xd8`/`0xe0`. Zeroes `BATTLE_Dialogue_Alignment` (@ `0x8016e450`;
  read in the cutscene changeDialog handler @ `0x80144694`).
- **BattleUnitData field offsets for HP/MP/Brave/Faith/CT/Lv are NOT labeled** in
  this export — only `+0x134`/`+0x18a`/`+0x58` are recoverable. **[CAPTURE / cross-ref FFHacktics struct]**

---

## 4. Tile/unit cursor  — ◐ input/bob SHIPPED (ADR-0046); selection/target use ⛔ OUT OF SCOPE (command)

- **Input fully recovered [FACT]:** `BATTLE_move_cursor_based_on_input` @
  `0x8006e7c0` (called from the 4 per-state handlers). 8-way pad → `±1` on
  `BATTLE_Cursor_X_Coord` (`0x800683f4`) / `_Y_Coord` (`0x80068400`); Z clamps to
  tile height (`check_cursor_bounds` @ `0x8006e97c`). Auto-repeat 90/60/30 frames
  (`0x5a/0x3c/0x1e`) from `SCUS_Custom_Options`; `BATTLE_Cursor_Repeat_Counter` @
  `0x8006e88c`. Confirm copies into `BATTLE_Old_Cursor_*`.
- **Tile surface vectors [FACT]:** `cursor_tile_vector_normal` @ `0x8006fc6c`,
  `cursor_tile_vector_shift` @ `0x8006fe00` (→ `BATTLE_Current_Vector` @ `0x800a1c48`).
- **Bob animation [FACT]:** ROM step tables in WORLD — `cursor_bob_pos_arr_idle`
  @ `0x800ec59c` (modulo `0x2e`), `cursor_bob_pos_arr_select` (modulo `0x26`).
  *(Already captured in our ADR-0046 + `tile-cursor-handoff.md` — reconcile.)*
- **⚠️ Cursor sprite DRAW fn is an un-disassembled gap** (`0x80070304–0x80070790`
  is `??` raw bytes in this export). The draw primitive (tile quad vs billboard),
  its tpage and CLUT are **not recoverable statically** — re-disassemble that
  range in Ghidra or capture live. **[CAPTURE]**

---

## 5. Damage / heal / miss numbers  — ✅ IN SCOPE (headline)

Fully recovered pipeline **[FACT]**:

- **Activate:** `BATTLE_activate_numerical_sprite_data(misc, type)` @ `0x80081024`
  — sets `0x1f`→`+0x4` of 3 number sub-objects (`+0x2c4/+0x2c8/+0x2cc`); `type`
  1/2/3 selects base flag `0x0800/0x1000/0x2000` at `+0x1b8` (damage/heal/MP-or-XP).
- **Per-frame:** `BATTLE_process_status_bubble_display` @ `0x80086594` — GTE-projects
  unit coord → screen XY at `+0x120/+0x122`, culls off-screen, then draws.
- **Digit builder:** `FUN_800810a4` — builds up to **six 16×16 (`0x10`) / 14×16
  (`0x0E`) digit quads** from a UV template at `misc+0x8`.
- **Type/speed:** `set_damage_display_from_agility` @ `0x80073ee0` (sets
  `SCUS_Animation_Speed`). State handler `main_DoEffectDamageDisp` @ `0x800770e8`.
- Number→digit split (div-by-10 loop) not isolated this pass; in `0x800810a4`
  prologue. **[INFER]**

---

## 6. Status / CT (charge) icons  — ✅ IN SCOPE

**[FACT]** `BATTLE_display_status_bubble` @ `0x8007eebc` — reads status bytes at
struct `+0x2dd/+0x2de/+0x2df` and halfwords `+0x2e0/+0x2e2/+0x2e4`, indexes icon
coords from `Status_Bubble_Icon_X/Y` tables (~`0x800949dc–0x800949fe`,
consts `0x8E`/`0xC8`), stores chosen icon index to `+0x13`, projects as a 3D
billboard above the unit (same `+0xC` raise). Setup `status_bubble_prep` @
`0x8007f1c8`. CT/charge reuses this bubble slot with a different icon index. **[INFER]**

---

## 7. Mapping to existing `ui3` components

| HUD element | Reuse from `ui3` | New work |
|---|---|---|
| Action menu frame + rows | `UIFrame` (9-slice), `UIText`/`UIChar`, `UIScrollableList` | menu-script driver, 16px rows, highlight sprite |
| Unit-info / help bar | `UIFrame`, `UIDataBinding`, `UIText` | field layout, status 5×8 grid, help-text table |
| Cursor | existing tile cursor + ADR-0046 bob | reconcile draw primitive vs capture |
| Damage numbers | — (none) | billboard digit renderer |
| Status/CT icons | portrait status (partial) | over-unit billboard icons |
| Turn order | — (none) | **see §1 decision** |

`frame.tga` + ROM bitmap font are already extracted and faithful — the work is
assembling them in the right places with the right behavior.

---

## 8. Open questions for PCSX-Redux dynamic analysis

Pruned to the **in-scope feedback HUD** after grilling. Each is a live-capture
task (breakpoint + VRAM dump on the FFT PSX ISO we mirror), feeding the
RANGETILE metadata parse (dec 7) and the §3 info-window layout.

**In scope:**

1. **Digit + status-icon cells in RANGETILE** — confirm the digit sheet and
   status-icon sprites live in the `RANGETILE.tga` atlas; recover each cell's UV
   rect + CLUT/palette row. Cross-ref the BATTLE.BIN tables (`Status_Bubble_Icon_X/Y`
   ~`0x800949dc`, digit geometry `0x10`/`0x0E`) against VRAM. *This is the
   blocking item for §5/§6 assets.*
2. **Number→digit split** — single-step `0x800810a4` on a known damage value to
   confirm digit-index mapping + the sign/MISS glyph (so our renderer matches).
3. **Type→colour mapping** — verify type 1/2/3 (`+0x1b8` base `0x0800/0x1000/0x2000`)
   = damage / heal / MP-or-XP, by watching CLUT per case.
4. **Animation timing** — number popup dwell/rise/fade and status-bubble
   appear/disappear cadence (frame counts; `SCUS_Animation_Speed` @ `0x80073ee0`).
5. **§3 info-window appearance** — exact FFT info-window frame/font CLUT/tpage
   (VRAM TPage `0x3c0`/`0x340`, ty `0x100`) and field layout positions, to
   reproduce the *look* (data is ours, not `BattleUnitData`).

**Dropped (out of scope / moot):** action-menu coords, command-string message
IDs, the cursor selection-draw primitive (all command HUD); `BattleUnitData`
field offsets (we read our own `UnitStats`, not the ROM struct).

Tooling note: drive PCSX-Redux from WSL via `cmd.exe curl.exe` POST of Lua to
`:8080/api/v1/lua/exec` (the Python agent's urllib can't reach the Windows port).
**If the agent `handlers.lua` is not loaded** (manually-launched GUI instance),
the Lua routes 404 — but the **built-in** endpoint
`GET /api/v1/gpu/vram/raw` still returns the full 1 MB VRAM with no Lua needed
(`curl.exe -s -o vram.bin http://localhost:8080/api/v1/gpu/vram/raw`). PSX VRAM
is 1024×512×16bpp; decode BGR555 (`r=(v&0x1f)<<3; g=((v>>5)&0x1f)<<3;
b=((v>>10)&0x1f)<<3`) for a viewable image (framebuffer renders true; 4bpp/8bpp
texture pages look like noise until palette-decoded).

### Capture results (2026-06-17 — live VRAM, built-in endpoint)

Battle screen captured live (matched the reference screenshot). Artifacts in
`project-assets/fft-rom/hud-capture/` (local-only): `vram_raw.bin`,
`vram_full.png`, `framebuffer_battle.png`, `info_window_layout.png`,
`rangetile_atlas.png`, `rangetile_digit_strip.png`.

1. **CONFIRMED — one atlas backs it all.** Digits, status icons, zodiac glyphs,
   gem/orb icons, and UI word-labels all live in the **RANGETILE 256×256 4bpp
   system atlas** (already extracted as `RANGETILE.tga`), loaded to VRAM page
   **(960,256) / tpage 0x3F** — the same `0x3c0`(=960) tpage the RE found for the
   menu/dialogue/font (§0). `parse_range_tiles.py` already extracts the texels +
   9 tile CLUTs; **only the per-cell UV + the menu CLUT id are missing** (#88).
2. **Digit set** = glyphs `0 1 2 3 4 5 6 7 8 9 /`, a fixed-width strip at
   ~RANGETILE `y=51–61, x≈168–255` (~8–9px pitch; glyphs nearly touch → measure
   as fixed pitch from an origin, not gap-split). The info-window `999` uses this
   set; the `/max` value is the same glyphs at a lower baseline (confirm whether a
   second smaller set exists for `/max`).
3. **Frame** = the already-extracted `frame.tga` (9-slice), *not* part of
   RANGETILE.
4. **HP/MP/CT bars have no sprite in the atlas** → they are gradient (gouraud)
   quads. Reproduce as gradient rects (HP green, MP pink, CT green), fill =
   value/max — not an extracted sprite.
5. **Info-window layout (faithful target, §3):** two side-by-side frames at the
   screen bottom. Left = acting unit (framed portrait; `cur/max  Lv.N  Exp.N`;
   then Hp/Mp/Ct rows = label + gradient bar + `cur`(large)`/max`(smaller, lower
   baseline) digits). Right = cursor unit (gem + `NN Name`, job, zodiac glyph,
   `Brave NN   Faith NN`). Exact pixel rects readable from the saved crops.

**Still open (interactive, during #88):** the menu CLUT id (cream digits / brown
labels — separate from the 9 tile CLUTs at `0x2DAE4`); a possible second small
digit set for `/max`; bar gradient endpoints. Non-blocking — colours can be
measured from `framebuffer_battle.png`.

### Live RE pass 2 (2026-06-17 — sstate1, fork PCSX VRAM, pixel-level)

Loaded `SCUS94221.sstate1` in the fork PCSX-Redux (Release dir), confirmed the
exact battle HUD, dumped VRAM (`hud-capture/vram_sstate1.bin`), decoded the
framebuffer + CLUT bank. Corrects two earlier conclusions and resolves the #88
menu-CLUT blocker. Artifacts: `hud-capture/sstate1_{framebuffer,left_panel,bars_digits_zoom}.png`.

1. **⚠️ Layout is ASYMMETRIC — the left panel is a DARK CONTRAST BAND, not a
   frame.** The acting-unit panel (portrait + `cur/tot Lv.N Exp.N` + Hp/Mp/Ct
   bars + digits) sits on a **dark translucent band** over the battlefield
   (spec dec-5 "darkened band" = THIS, the whole left panel — confirmed at the
   pixel level: between/around the bars is `(0,0,0)`, not tan). Only the
   **right** panel (gem + name, job, zodiac, Brave/Faith) is the tan `UIFrame`.
   The #91 build wrongly framed the left side too.
2. **Menu CLUT — RESOLVED (the open #88 item).** The text/digit palette is the
   16-colour CLUT at **VRAM (960, 498)**: index 1 = `(232,232,224)` cream (the
   digits), with a dark outline ramp. The tan **window-frame** CLUT is at
   **(960, 496)** (`0x7c3c`; bg tone `(168,160,136)`). Warm ramps at (960,501)/
   (960,505). CLUT bank lives at VRAM x=960, y≈496–509.
3. **Bars = gouraud gradient quads (~3 px tall), NO sprite.** Pixel profile
   shows a clean monotonic L→R gradient, vertically flat over 3 rows — a
   gouraud-shaded untextured quad, confirming the earlier "gradient quad"
   guess (the user's suspected bar sprite is not present). Measured endpoints:
   **HP** `(80,112,112)`→`(160,176,112)` (teal→green), **MP**
   `(136,72,56)`→`(216,152,72)` (brown→orange), **CT** `(88,112,64)`→
   `(168,168,64)` (olive→yellow-green). Each bar is bordered top/bottom by a
   dark row; fill width = value/max.
4. **Digits confirmed RANGETILE strip**, drawn cream (CLUT (960,498)); the
   `/max` value is the same glyphs at a lower baseline + smaller scale.
5. **Word-labels are RANGETILE sprites**, NOT bitmap-font text — the #91
   placeholder used the bitmap menu font (hence the wrong look + stray kana).
   Since the disasm has **no static UV table** (overlay-resident draw), the
   parser **derives** each cell from the ISO atlas texels by band segmentation
   (`tools/parse_range_tiles.py` `word_label_set`/`segment_words` — tight glyph
   rows + gap-split words; search-window + ordered names supplied, x/y/w/h
   computed). 5 labels emitted to `RANGETILE.json` `word_labels`: `Exp.`(146,32,
   18,10) `Hp`(168,32,13,10) `Mp`(184,32,13,10) `Ct`(200,32,15,10) — the y32
   band the user cited "145,32..239,42" — plus `Lv.`(49,15,13,9) from the upper
   band (~56,20). `Brave`/`Faith` are right-panel labels (not in the user's
   rangetile-label list); deferred. Loaded via `RangeTileAtlas.label_rect()`.

### Live RE pass 3 (2026-06-18 — bar fill ISOLATED: disasm + live RAM)

The bar **fill geometry** (left open in pass 2 — endpoints were capture-measured
on an all-full panel, so clip-vs-stretch was unknown) is now pinned to the ROM.
Loaded `SCUS94221.sstate1` in the fork PCSX-Redux, read the draw routine in the
BATTLE.BIN Ghidra export, and confirmed the constants against live RAM.

- **Renderer:** `FUN_801352bc` @ **`0x801352BC`** (per panel; called by the
  per-slot entries `0x80136128`/`0x801361e8`/`0x80136324`/`0x80136188` after the
  builder `FUN_80133588` @`0x80133588` copies the unit's stats into the display
  struct `&DAT_8014d038`: cur_hp +0xc, max_hp +0x10, cur_mp +0x12, max_mp +0x16,
  CT cur +0x18 / max +0x1c). Source unit struct = `FUN_80180afc(unit_id)`,
  cur_hp at unit+0x28 (verified live: unit struct @`0x8019268C`, cur_hp
  @`0x801926B4`).
- **Fill width formula (the answer):** `width_px = (cur << 5) / max` = **`cur*32/max`**.
  A full bar is **32 px** wide (confirmed live: active HP quad x0=180 → x1=212).
  The quad's RIGHT-edge X = `x_origin + width` — so the bar **SHRINKS** as the
  stat drops (right edge slides left). At `cur==0` the bar is hidden (`x_origin=0`).
- **Fill primitive:** ONE **gouraud POLY_G4** (untextured, vertex-coloured) quad
  per bar, **3 px tall** (y..y+3), rows ~11 px apart (`+0xb`). The left two
  vertices take a fixed **dark** colour, the right two a fixed **bright** colour;
  gouraud interpolates between them, so the *complete* dark→bright ramp is always
  shown, **compressed into the filled width** (not a clip of a fixed-width ramp,
  not a stretch-to-full-width).
- **Empty-bar TRACK / frame (the swatch layer):** the gradient fill does NOT stand
  alone — it sits over a full-width RANGETILE swatch (per-stat ISO CLUT
  0x7efc/7f3c/7f7c, see "BARS landed" note) acting as the bar's dim casing/frame,
  so the unfilled remainder reads as an empty bar, not blank band. (This textured
  layer is what the "disable textures kills the bars" GPU-toggle showed. The exact
  ROM draw path for track-vs-fill isn't fully reconciled in disasm — gouraud fill
  confirmed in FUN_801352bc; the swatch track is retained because both render
  together in the live game.)
- **Gradient endpoint colours** — read live from the ROM table at **`0x80168818`**
  (per bar: bytes 0/4 = left/right R, +1/+5 = G, +2/+6 = B; v0=v2, v1=v3):
  HP **(72,104,120)→(168,184,112)**, MP **(128,64,56)→(224,160,80)**,
  CT **(80,104,64)→(176,176,64)**. (Pass-2's capture values were BGR555-quantised
  approximations of these — these table bytes are authoritative.)
- **Special cases:** a "charging" flag (`DAT_80166044`) forces full width; the
  selected/blink state (`local_68`) halves all vertex colours (dim).

**Implemented** in `UIUnitInfoWindow._layout_bar` (two layers): `_bar_tracks[stat]`
= the full-width swatch (per-stat CLUT, `vitals_sprite.gdshader`, dim
`bar_track_brightness`) behind `_bars[stat]` = the gradient fill (QuadMesh sized
`frac*bar_full_width(32) × bar_height(3)`, `shaders/vitals_bar.gdshader` lerping
`bar_grad_left[stat]→bar_grad_right[stat]` across UV.x). The earlier build had ONLY
the swatch (sampled as the bar itself, shrinking) — which lost the dark→bright ramp
and read flat/empty; the gradient fill on top supplies the ramp while the swatch
stays as the frame/track.

### Disasm citations for the info-window draw (2026-06-17 — hacktics export)

> ⚠️ **CORRECTED 2026-06-17 (provenance pass) — read the "ROM-authoritative
> provenance" subsection below before trusting this block's premise.** The claim
> that `HELPMENU.OUT` is "NOT in this export" is **FALSE**: the overlay is fully
> disassembled in `hacktics_disassembly.txt` under a `HELPMENU::` section
> (`0x801df000`–`~0x801e0b2c`, with FFHacktics wiki annotations). The
> "RANGETILE.tga is therefore the authoritative UV source by elimination"
> reasoning collapses with it. The corrected model is below.

Cross-referenced `hacktics_disassembly.txt` for *how* the window draws each
element. Net: the per-element UV/label code lives in the **`HELPMENU.OUT`
overlay (`0x801df000+`), which is NOT in this BATTLE.BIN export** — so there is
**no embedded ROM UV table** for the digit/label cells. The extracted
`RANGETILE.tga` is therefore the authoritative UV source (measure + visually
confirm, the #88 pattern); no hidden table can contradict it. Recoverable:

- **Bars = POLY_G4 gouraud quad (`0x7000`)** — set in `BATTLE_display_inner_character_window`
  (~`0x80133dac`). **Untextured** per-vertex-colour quad; confirms the pixel
  profile. Gradient endpoint RGBs are runtime/GTE, not static → use the measured
  values (pass 2 above). **[FACT — primitive type; CAPTURE — colours]**
- **Frame CLUT `0x7c3c`** (VRAM (960,496)) — literal in
  `BATTLE_makeDefaultSprites_withCLUT` (~`0x8012e2b8`, stored to sprite `+0xe`).
  Text/digit CLUT is the +2 row (VRAM (960,498), `≈0x7c3e`) — measured, not a
  literal. **[FACT/INFER]**
- **Portrait** = `CreatePortraitPolygon` @ `0x80136bdc`: `GetTPage(abr=2,
  tx=0x340 normal / 0x380 unique, ty=0x100)` then dynamic `GetClut()`. UV/CLUT
  are unit-data-driven, no static table. (Our build uses our own portrait; this
  just confirms FFT's placement.) **[FACT]**
- **No static UV table** for digit/label cells found anywhere in the export
  (only `Status_Bubble_Icon_X/Y` @ `0x800949dc`/`0x800949f4`, already used by #88).
- ⚠️ The agent flagged `0x80133cf8`'s body as partly `??` raw bytes yet cited
  addresses inside it — treat in-body line citations as approximate; the
  high-level facts (POLY_G4, CLUT `0x7c3c`, portrait tpages) are corroborated by
  the live capture and are the ones to rely on.

### ROM-authoritative provenance (2026-06-17 — overlay-in-export breakthrough)

Re-investigation per `handoff-battle-hud-rom-provenance.md`. **The prior pass's
central premise was wrong**, and correcting it reframes the whole label/digit
parsing question. All claims below are cited by ADDRESS against
`hacktics_disassembly.txt`.

**Finding 1 — `HELPMENU.OUT` IS in the static export. [FACT]**
The overlay is fully disassembled under a `HELPMENU::` section (RAM
`0x801df000`–`~0x801e0b2c`), with FFHacktics wiki banners
(`HELPMENU.OUT_001df000_-_001df04c`, `…_001df050_-_001dfdd0`,
`…_001dfe10_-_001e05d4`). The `RAM:801df000 ??` lines elsewhere are just
placeholder copies at the runtime load address — the *real* code is the
`HELPMENU::` section. So there was never a "missing overlay" forcing us onto
atlas-segmentation guesswork.

**Finding 2 — the info window draws text via the HELPMENU bitmap-font path,
NOT a RANGETILE label-sprite table. [FACT → CAPTURE to confirm].**
The draw chain is now traced end-to-end:
- `BATTLE_display_inner_character_window` @ `0x80133cf8` builds the **bars**
  itself (POLY_G4 tag `0x7000` → OTs `0x801697d8`/`0x80169800`; header
  `{0x1015, 0x7d0}` → `0x80166a60`; a `0x8800`/stride-`0x80` block and bar
  params `0x7`/`0x3` → `0x801669c0`/`0x801669c2`), then **delegates** all
  text/menu work to the thread orchestrator at `FUN_8013c2dc` (and
  `BATTLE_maybe_build_scrollable_menu`).
- That orchestration path **`jal BATTLE_load_file(0x3)`** (loads `HELPMENU.OUT`)
  immediately followed by **`jal RAM:FUN_801df050`** (the HELPMENU rasterizer) —
  the two are adjacent with the `;HELPMENU.OUT` wiki banner literally between
  them.
- `FUN_801df050` emits its text via the **SCUS bitmap-font engine**
  (`FUN_8014c8a0` set-state + `FUN_8014ca38` glyph-emit, always with font
  descriptor `a1 = 0x801380c0` and a packed **text-id** in `a2`). It builds its
  tpage with a **constant** `GetTPage(tp=0, abr, tx=0x3c0, ty=0x100)` and makes
  **no `GetClut` call and no RANGETILE-specific access**. Its data region holds
  window-geometry/menu-structure tables (`0x801e05d8`+, 10-byte frame-cell
  arrays `0x801e078c`/`0x801e07fc`, a 2-byte item-index set + 4-byte pointer
  dispatch `0x801e0a3c`+), **not** a glyph-UV atlas.

**Finding 3 — "font vs RANGETILE" is a FALSE DICHOTOMY; one VRAM page backs
both. [FACT].**
`GetTPage(tx=0x3c0, ty=0x100)` = VRAM **(960, 256)** — byte-identical to the page
the prior capture assigned to "RANGETILE tpage `0x3F`". Decoding the tpage word:
`0x3F` (rangetile, abr=1) and `0x1F`/`0x5F` (HELPMENU font, abr=0/2) differ
**only in the ABR (semi-transparency) bits** — same physical 256×256 4bpp page
at VRAM x[960,1024) y[256,512). **The menu/UI bitmap-font glyphs live inside the
same atlas page as the range tiles, digits, and status icons** (`RANGETILE.tga`
is that whole page). This reconciles every earlier note that conflated
`0x3c0/0x100` (font) with `(960,256)` (rangetile) — they were always the same
page.

**Implication for the parser (`tools/parse_range_tiles.py`).**
The `word_labels` band-segmentation (treating "Hp"/"Mp"/"Ct"/"Lv."/"Exp." as
pre-baked label *cells*) is **likely modeling the wrong abstraction**: the ROM
composes those labels as **font strings** (text-id → glyph sequence) from a
**font-glyph grid** in the same atlas, not as per-label sprite rects. The
ROM-authoritative parse target for labels is therefore the **font-glyph layout**
(where each character `H p M C t L v E x . / 0-9` sits in the atlas + its
advance/width), reached through the `0x801380c0` font descriptor — not
hand-tuned label boxes. The segmentation is a reasonable *visual cross-check* but
is not the ROM model. **[INFER — gate on the live capture below before rewriting
the parser.]**
  - *Note:* the over-unit DIGITS (`FUN_800810a4`, cells `0x10`/`0x0E`) and
    STATUS ICONS (`Status_Bubble_Icon_X/Y` @ `0x800949dc`) remain genuinely
    table-driven RANGETILE sprites — #88's treatment of those is unaffected and
    stays authoritative. Only the **info-window word-labels** are reframed.

**Decisive next step (live GP0 capture — the handoff's definition-of-done test).**
Breakpoint the info-window draw on the savestate-1 HUD and capture the actual GP0
primitive stream for the label region: read each primitive's **tpage + UV + CLUT
+ XY**. The test settles it cleanly:
  - If the labels arrive as a **run of single-glyph sprites** sampling a
    font-glyph grid (UVs marching by a fixed advance, one quad per character) →
    Finding 2/parser-implication CONFIRMED; build a font-glyph metadata parse
    keyed off `0x801380c0`, retire `word_labels` segmentation.
  - If a label is a **single multi-character sprite** with one UV rect → the
    pre-baked-cell model stands; keep (and ROM-ground) the segmented rects.
Either way, also capture the bars' POLY_G4 vertex RGBs and the text CLUT row to
close §8 items 3/5. PCSX setup + savestate path: see handoff + §8 tooling note.

### ⚠️ Element taxonomy correction (2026-06-17 — user)

The bottom HUD is **two distinct conceptual elements** — do not conflate them
(the prior spec called the whole thing "the info window"). Whether they share one
draw function or split is **not yet verified**; the terminology distinction is
the firm part:

1. **Info window = RIGHT panel only** — gem + unit **name**, **job**, zodiac,
   **Brave/Faith**. This is the genuine *help/info box*, drawn through the
   **HELPMENU.OUT font path** (Finding 2 above: `load HELPMENU.OUT` →
   `FUN_801df050` → SCUS font engine, bitmap-font text-id strings). The
   font-glyph model applies HERE.
2. **Vitals readout = LEFT panel** — portrait + `Lv.` `Exp.` + `Hp`/`Mp`/`Ct`
   labels + gradient bars + `cur/max` digits. **This is NOT an info window**;
   it's the always-on combat vitals gauge. **These five labels (`Exp. Hp Mp Ct
   Lv.`) are exactly what `parse_range_tiles.py` `word_labels` targets** — so
   *this* element is the real subject of "ROM-authoritative RANGETILE parsing,"
   and its draw path is **still unlocated**.

**Also corrected: `BATTLE_display_inner_character_window` @ `0x80133cf8` is the
STATUS SCREEN, not the bottom HUD.** Reading its full body: it only writes
**primitive-type tags** into template buffers — POLY_G4 `0x7000` ×20 (→ OTs
`0x801697d8`/`0x80169800`), and a `0x8800` sprite tag into a **5-row×8-col loop**
gated by the status-flag byte `+0x58` (mask `a2` = `0x80` `srl` per bit) — i.e.
the 5×8 status-flag grid — then `load HELPMENU` + `BATTLE_maybe_build_scrollable_menu`.
It contains **no UV/coordinate literals**; UVs live in the pre-populated template
buffers (`0x80166a60`, `0x8014d264`, the two OTs) it merely toggles. So it is the
full unit **Status** screen, and the spec §3 label ("unit-info window builder")
is wrong.

**Revised next target:** locate the **left vitals-readout** draw function
(distinct from the status screen and from the right info box). Candidates to
trace from: `BATTLE_store_name_and_unit_data_under_cursor` @ `0x8006ee70`
(populates the readout from the cursor), and the over-unit digit builder
`FUN_800810a4` (does the readout's `cur/max` reuse it?). Then the live GP0
capture, aimed specifically at the LEFT panel's label + digit primitives, settles
their tpage/UV/CLUT — the parser's authoritative source.

### LOCATED via dynamic analysis (2026-06-17 — fork PCSX, sstate1)

**The vitals-readout draw function is `0x801352BC` — and it is in a `??` gap of
the static export** (the whole `0x80135xxx` page is undisassembled: 4096
placeholder `??` lines). *That is why every static pass failed to find it.*
Recovered by live RAM dump + capstone. Method (reusable):
1. **Value tracer** — scanned the 2 MB main RAM (`PCSX.getMemPtr()`) for the
   sstate1 fingerprint HP `999`=`0x03E7`, MP `799`=`0x031F`, CT `100`=`0x64`.
   Source structs: live `UnitBattleData` at `0x801926B4` (`0x8019xxxx` table) and
   a BATTLE.BIN display buffer near `0x8014D044`.
2. **Portrait exec-breakpoint** (the decisive anchor) — `PCSX.addBreakpoint(0x80136bdc,'Exec',…)`;
   the portrait is unambiguously left-panel. It fired with **`ra = 0x80135850`**
   for two unit slots (`a0` = portrait sprite at `s4+0x2c4`) → the caller is the
   left-panel drawer.

**What `0x801352BC` is/does (recovered disasm, cite by address):**
- Prologue `addiu sp,sp,-0x118` @ `0x801352BC`; portrait call `jal CreatePortraitPolygon`
  @ `0x80135848` (a0 = `s4+0x2c4`).
- **Per-unit display struct** base **`0x8017225C`, stride `0x2EC`**, two slots
  (acting + cursor unit; the two portrait `a0`s were `0x80172548` and `0x8017225C`).
  Sprite sub-objects live at struct offsets `0x170` (stride `0x28`), `0x198`,
  `0x238`, `0x2c4` (portrait), `0x2c4`-area.
- **Text/digit CLUT `0x7CBC`** = VRAM **(960, 498)** — passed literally
  (`a2=0x7cbc`) to `BATTLE_makeDefaultSprites_withCLUT` @ `0x8012e2b8` and stored
  into sprite `+0x17e`. Confirms the prior measured-only text CLUT as a code
  constant.
- **CT proof**: `slti v0,v0,0x65` → clamp to `0x64` (100) @ `~0x801356e8`,
  reading CT from `+0x18` of the unit struct — i.e. THIS function renders the CT
  `100/100`.
- **Row builders** (the label/value/bar emitters), all fed template
  **`a1 = 0x80165EA4`**: `0x801343e0` (w/h args — `0x28×0x28` portrait frame,
  `0x60×0x10` row), `0x80134a74`, and `0x8014a834` (called in loops of 2/4 — the
  Hp/Mp/Ct + Lv./Exp. rows). `0x8012e198` = per-sprite primitive init (×5 loop,
  `s4+0x170 + i*0x28`).
- **Template `0x80165EA4`**: small tpage/index records — notably a sequential
  glyph/tile-index run `1a 1b 1c 1d 1e 1f 20` and `(val,row)` pairs
  `01 b0 / 07 b0 / 03 b0` (`0xb0`=176 = an atlas row). Candidate authoritative
  UV/index source for the labels — needs decoding.

**Authoritative-UV next step (no more guessing):** the *built* sprite primitives
are sitting in RAM right now at `0x8017225C + {0x170,0x198,…,0x2c4}` — their
U/V/CLUT/XY are the literal on-screen values. Decode those structs (and/or
disassemble the 3 row-builders `0x801343e0`/`0x80134a74`/`0x8014a834` to learn
the field offsets) to read each Hp/Mp/Ct/Lv./Exp. label + digit cell's real UV.
That is the ROM-authoritative `RANGETILE` parse the segmentation was standing in
for. (The 3 builders are also in the `0x80134xxx`/`0x8014axxx` export gaps → live
disasm, same method.)

### AUTHORITATIVE primitives recovered (2026-06-17 — live POLY_FT4 decode)

Decoded the live primitives the vitals fn builds. **The labels ARE RANGETILE
sprites with real UV rects baked into each POLY_FT4** — the segmentation model is
vindicated *and* the rects are now ROM-exact.

**Sprite format:** `POLY_FT4`, 40 bytes (tag-len 9), `code 0x2c`. Fields:
`+8/10` xy0, `+12/13` u0/v0, `+14` **clut**, `+16/18` xy1, `+20/21` u1/v1, `+22`
**tpage**, `+24/26` xy2, `+28/29` u2/v2, `+32/34` xy3, `+36/37` u3/v3. tpage word
decodes `x=(tp&0xf)*64, y=((tp>>4)&1)*256`; `0x1f` = VRAM **(960,256)** = the
RANGETILE atlas page; UVs are pixels into `RANGETILE.tga`.

**Word-labels (clut `0x7cbc`, tpage `0x1f` = RANGETILE) — ROM-exact UV rects:**
| label | atlas UV | size | vs segmentation |
|---|---|---|---|
| `Lv.` | **(48,16)** | **14×8** | seg said (49,15) 13×9 — off by ≤1px ✓ |
| `Exp.` | **(146,32)** | **20×10** | seg said (146,32) 18×10 — exact origin ✓ |
| (unident.) | (177,144) | 25×9 | left of `Lv.` @screen x158 — TBD |

(`Hp/Mp/Ct` labels did NOT appear in the clut-`0x7cbc` set — see digits/CLUT
note below; likely a different clut or part of the bar rows. Still to pin.)

**Digits — SCUS number builder `jal 0x80023d30`**, CLUTs **`0x7c3c`** (→ sprite
`s4+0x1a6`) and **`0x7d7c`** (→ `s4+0x1ce`), NOT the label clut — which is why a
clut-`0x7cbc` scan misses them. Digit-group screen XY written to `s4+0x2cc /
0x2d4 / 0x2dc / 0x2e4` (cur/max groups) with column offsets `+2 / +0x21(33) /
+0x32(50)` from the panel base XY (`$fp`). Per-stat source struct ([sp+0x90]):
**cur at `+0xc`, max at `+0x10`**. Exact digit-cell UVs come from `0x80023d30`
(decode next).

**Bars (POLY_G4):** fill width = **`cur*32/max`** — computed at `0x80135AD8`
(`lh cur(+0xc)` `sll<<5` `div max(+0x10)`), confirming the gradient-quad/value
model with the exact formula.

**Portrait:** `CreatePortraitPolygon`, tpage `0x1d` = VRAM (832,256), UV
(80,192) 48×31, screen (142,172) — its own sprite-sheet page, not RANGETILE.

**Net for the parser:** the `word_labels` segmentation was a sound stand-in (its
`Lv.`/`Exp.` rects match ROM within 1px); replace its *derived* rects with these
**ROM-exact** ones and add the remaining labels/digit cells by decoding the rest
of the live primitive set. Method is fully established: scan RAM for the prim,
read UV/XY straight out of it.

### Hp/Mp/Ct labels + bars are SPRT, not POLY_FT4 (2026-06-17 — user GPU hint)

User: in PCSX-Redux *Debug → GPU → Show GPU debug → "disable textures for
sprites"*, **Hp/Mp/Ct (labels + bars) vanish while Lv./Exp. and the numbers
remain.** That toggle only affects **SPRT** primitives → Hp/Mp/Ct are SPRT;
Lv./Exp.+numbers are POLY_FT4. **This is why the POLY_FT4 (code `0x2c`) scan never
found Hp/Mp/Ct.** Re-scanned for SPRT (20 B: `tag(len 4) | rgbc code 0x64–0x7f |
xy | u,v,clut | w,h`; no tpage in-prim — uses current tpage). Found them, and
the UVs **match the segmentation exactly**:

| element | prim | atlas UV | size | CLUT | seg guess |
|---|---|---|---|---|---|
| `Hp` | SPRT (code 0x67) | **(168,32)** | 16×9 | `7cbc` | (168,32,13,10) ✓ |
| `Mp` | SPRT | **(184,32)** | 16×9 | `7cbc` | (184,32,13,10) ✓ |
| `Ct` | SPRT | **(200,32)** | 16×8 | `7cbc` | (200,32,15,10) ✓ |
| HP/MP/CT **bars** | SPRT | gradient swatch **(216,202)** | ~38×6 | warm `7efc`/`7f3c`/`7f7c` | (n/a) |

So the bars are **textured SPRT swatches** (one warm CLUT per stat —
teal/brown/olive), fill width from `cur*32/max` (§ above) — *not* a POLY_G4 here
(the POLY_G4 in `0x80133cf8` was the separate STATUS screen). All four `y=32`-band
labels share **atlas row 32**: `Exp.` is POLY_FT4, `Hp/Mp/Ct` are SPRT, same row
— the segmentation's `y=32` band was correct.

### Bar CLUT source LOCATED + bars LANDED (2026-06-17 — dynamic→ISO trace)

The swatch is a single rounded **bar shape at atlas `(216,202)` 38×6** (a
3-shade body, indices 1–3) — *not* a gradient ramp in the texels; the per-stat
**CLUT** supplies the colour, the swatch the shape, and the SPRT width the fill.
The three CLUTs are at VRAM rows **507/508/509** (`0x7efc`/`0x7f3c`/`0x7f7c`).

**They are NOT in BATTLE.BIN** (`0x2DAE4` slots 11–13 there are near-empty).
Dynamic trace: the captured CLUT bytes aren't in live main RAM but **are in the
ISO at `0x85025a`**, which falls inside the **same LBA `0xE68` raw-sector asset**
the parser reads for the texels — in the **palette tail right after the
`0x8000`-byte texel block**, at asset payload **`+0x9160`** (HP), `+0x9180` (MP),
`+0x91a0` (CT), three consecutive 32-byte BGR555 CLUTs. So the bar colours are
**ISO-derived**, no hardcoding.

**LANDED** in `tools/parse_range_tiles.py` (`bar_set(asset)` → `RANGETILE.json`
`"bars"`: `swatch` + `fill:"value/max"` + per-stat `{name, clut, colors[16]}`),
consumed by `RangeTileAtlas.gd` (`bar_swatch_rect()`/`bar_stat_colors()`) and
shown in `RangeTileAtlasViewer`. Guarded by `BAR_SWATCH_FIXTURE` (texels) +
`BAR_HP_CLUT_HEX` (palette); 21 Python tests + Godot `[PASS]`. Measured body
colours (idx3, 5→8-bit expanded): HP `(41,49,49)`, MP `(57,49,33)`, CT
`(41,57,25)`.

**`0x80023d30` is NOT a number builder** — it's a 4-instr helper that stamps a
primitive's tag-length byte (`sb 8, 3(a0)`; returns `0x38`). The digit drawing is
inline in the vitals fn after it (the `cur*32/max` + XY-store block).

**Search method for text-image labels (user insight):** the label/digit sprites
are *pictures of text*, so they can't be found by value-search (unlike HP=999).
But **they share CLUTs** (labels `7cbc`; digit shadow/fill `7d7c`/`7c3c`;
bars warm ramps) — so **scan by CLUT** to locate each kind. That's the reusable
hook for recovering the full UV set.

### Digits: #88's (168,52) strip CONFIRMED + the SPRT-tpage caveat (2026-06-17)

CLUT-scanned the digit prims (fill `7c3c`, shadow `7d7c`) → digits are a
**two-layer render** (a shadow sprite + a fill sprite, same cell). Cross-checked
against the on-disk `RANGETILE.tga`:

- **The only clean `0123456789/` digit strip in the atlas is at `(168,52)`** —
  exactly #88's segmented origin. **#88's digit cells are VINDICATED**, not wrong.
  (Rendered the atlas: row 52 x168+ is an unambiguous digit run; the `y=32` band
  is the `Hp/Mp/Ct` labels.)
- **⚠️ SPRT-tpage caveat (why raw digit UVs looked off-strip).** SPRT primitives
  carry **no tpage** — they sample whatever tpage the GPU had set (a separate
  `DR_TPAGE`/GP0 `0xE1`) when drawn. So a digit-SPRT's raw `u,v` is **only**
  atlas-relative if its active tpage is the rangetile page (960,256). The
  *label* SPRTs proved they use that page (Hp `u=168,v=32` lands exactly on the
  atlas `Hp`); the *digit* SPRTs read raw UVs like `(0,128)`/`(160,0)` that do
  **not** land on the strip → they use a **different active tpage**, so their raw
  UVs are not atlas coords. Mapping each glyph 0–9 needs the digit draw's tpage
  state (capture the `DR_TPAGE` before the digit run, or read the `GetTPage` in
  the inline digit code) — *then* the strip is (168,52) per #88. POLY_FT4 digits
  (if any) are reliable since FT4 carries tpage in-prim.

**Bottom line for the parser:** labels are fully ROM-pinned (table above + Lv./
Exp.). Digits: keep #88's `(168,52)` fixed-pitch strip (now atlas-confirmed); the
open item is purely the runtime tpage/clut the HUD applies (cosmetic — cream fill
`7c3c` + shadow `7d7c`), not the cell geometry. The unidentified `(177,144)`
POLY_FT4 (rangetile, screen x158 left of `Lv.`) still TBD.

### Resolved during #88 (2026-06-17 — measured from on-disk RANGETILE.tga)

Implemented in `tools/parse_range_tiles.py`; emitted into `RANGETILE.json` as
`digits` and `status_icons`; loaded by `src/ui3/elements/RangeTileAtlas.gd`;
visually confirmed by the `assets/scenes/RangeTileAtlasViewer.tscn` viewer
(digits read `0123456789/`, all 20 status bubbles render — incl. the `AT` charge
bubbles). Guarded by `tools/test_parse_range_tiles.py` (11 tests; texel fixtures
fail loud on drift) and `tests/RangeTileAtlasTest.tscn`.

- **Digit cells [MEASURED]:** glyphs `0123456789/`, **fixed pitch 8** from origin
  **(168, 52)**, cell **8×11**. 11×8 = 88 → x 168..256 (the atlas right edge).
  Reproducibility fixture = glyph `0` (an oval) at the origin.
- **`/max` digits:** the same glyph set drawn at a lower baseline at runtime —
  *not* a separate smaller sprite set (no second strip found in the atlas).
- **No `MISS`/sign glyph in the strip.** FFT draws `MISS` as a word-label (the
  atlas's label region), not a digit cell — out of this pass's digits scope.
- **Status-icon cells [MEASURED + ROM table]:** **20 icons**, read from the
  BATTLE.BIN parallel arrays `Status_Bubble_Icon_X` (file `0x2D9DC` / RAM
  `0x800949DC`) and `_Y` (file `0x2D9F4`). The `Y` byte is already the atlas
  texel row (`0xB0/0xBC/0xC8` = **176 / 188 / 200**); the `X` byte snaps to a
  **14px column grid at origin x=16** (`atlas_x = 16 + round(X/14)·14`). Cell
  **14×12**. Each of the 20 derived cells lands on a non-empty atlas box (tested).
- **Menu CLUT:** still the one open item (cream digits / brown labels). Emitted
  as `"clut": null` per set — the menu palette is *not* one of the 9 range-tile
  CLUT rows; the over-unit / info-window renderer applies it (colour derivable
  from `framebuffer_battle.png`; non-blocking for #89/#90/#91 geometry).
- **Number→digit split (for #89):** decimal, right-aligned, max 6 digits (the
  ROM digit builder `FUN_800810a4` lays up to six cells, §5); `/` is the
  info-window `cur/max` separator. No special encoding — split by `% 10`.

### ASSEMBLED — ROM-exact left-panel layout + faithful render (2026-06-17)

The left vitals panel is now **assembled and rendering** in-game
(`src/ui3/UIUnitInfoWindow.gd`, headful-verified against
`hud-capture/sstate1_left_panel.png`). The per-element screen XYs were re-derived
cleanly by dumping the **live display struct at `0x8017225C`** (acting-unit slot)
on sstate1 and decoding every built primitive (POLY_FT4 code `0x2c` / SPRT). This
supersedes the earlier hand-noted XYs — the authoritative table:

| element | prim | screen XY (top-left) | size | atlas UV | CLUT |
|---|---|---|---|---|---|
| portrait frame | SPRT | (140,170) | 35×51 | (0,0) | 7c3c |
| portrait | POLY_FT4 | (142,172) | 31×48 | (128,192) tpage 0x1d | 7a89 |
| `Lv.` | POLY_FT4 | (203,174) | 14×8 | (48,16) | 7cbc |
| `Exp.` | POLY_FT4 | (230,174) | 20×10 | (146,32) | 7cbc |
| `Hp` | SPRT | (171,189) | 16×9 | (168,32) | 7cbc |
| `Mp` | SPRT | (171,200) | 16×9 | (184,32) | 7cbc |
| `Ct` | SPRT | (171,211) | 16×8 | (200,32) | 7cbc |
| HP bar | SPRT | (183,193) | 38×6 | (216,202) | 7efc |
| MP bar | SPRT | (183,204) | 38×6 | (216,202) | 7f3c |
| CT bar | SPRT | (183,215) | 38×6 | (216,202) | 7f7c |
| cur/max numbers | POLY_FT4 | (218,188) | 40×40 | tpage 0x07 (scratch) | — |
| Lv/Exp numbers | POLY_FT4 | (166,170) | 96×16 | tpage 0x07 (scratch) | — |

**Panel-relative model (portable).** Origin = screen **(140,170)**; every element
is laid out at its offset from that origin (e.g. `Hp` = +(31,19), HP bar =
+(43,23)). The game places the panel at a ui3 screen position and lays the
elements at these FFT-px offsets scaled by the standard ui3 `PPU 0.04 × PAR
1.25` (ADR-0036) — same convention as `UIChar`. So the screen-space mapping
(handoff open piece) is resolved: **FFT px → ui3 world via PPU·PAR, panel anchored
by `screen_pos`**; the FFT draw-width (256 vs 320) is moot for the *relative*
layout. The `cur/max` numbers and `Lv/Exp` numbers are pre-composed by FFT in a
**scratch VRAM page (tpage 0x07 = VRAM (448,0))** then blitted as one POLY_FT4
each — so they carry no RANGETILE UV; we render them from the `(168,49)` digit
strip instead (cur large, `/max` small + lower baseline).

**Faithful render — the menu CLUT, RESOLVED (closes the last #88 open item).**
Labels and digits sample the RANGETILE index atlas through the **menu CLUT
`0x7cbc` = VRAM (960,498)** (read live from `vram_sstate1.bin`): index 1 =
`(239,239,231)` cream. Because the *label* glyphs are authored mostly with the
high/dark indices and the *digit* glyphs with index 1, **one CLUT** renders
labels dark-bodied/tan and digits bright cream — exactly the reference. Bars
sample the `(216,202)` swatch through each per-stat CLUT (`RangeTileAtlas`), drawn
at ~2.2× brightness (the PSX draws these dark-authored CLUTs hot, matching the
framebuffer endpoints in §8 pass 2); fill width = `value/max` (left-sampled).
All of it goes through one small shader, `src/ui3/shaders/vitals_sprite.gdshader`
(index→CLUT, cell-rect remap, `pow(.,2.2)` — mirrors `ui_font_char.gdshader`).
The left panel is the **dark contrast band** (a translucent quad), NOT a tan
frame. Open/optional: a real unit portrait texture (slot drawn, `portrait_texture`
export); the unidentified `(177,144)` POLY_FT4 did not appear in the clean slot
dump (was a stale/other-slot artifact).

### The cur/max DIGITS are composed through the font system (2026-06-17)

⚠️ **Refinement to the line above** ("digit glyphs with index 1"): the cur/max
numbers come from the **menu/font system**, which is **where they get their
palette** (`0x7cbc`) — same path that draws the thin menu text. They are **not**
the RANGETILE `(168,49)` damage-number strip (that's the over-unit damage set:
thin, indices 1,2,3,5,6 — *no* index 4, non-uniform → 0/1/2 shorter; direct
shape compare vs the on-screen glyph confirms a different glyph). FFT **composes**
the number at runtime into a VRAM **scratch page** (tpage **0x07** = VRAM (448,0))
— the same buffer where it builds the unit name/job — applying the font system's
bold/emboss, then blits one POLY_FT4 through `0x7cbc`. Decoding tpage 0x07 live:
the composed `999/799/100` sit there next to `Abraham`/`Knight`, body=index 4 (→
dark `(33,24,16)`) + cream highlight (index 1) + grey AA (2,3) — i.e. the
`#EFEFE7 #9C9C94 #52524A #211810` = `0x7cbc[1..4]` the user identified. So the
**palette + composition are the font system's** (the rangetile/menu atlas page);
the composed embossed glyph isn't a static cell anywhere in VRAM (searched all
pages, every 4bpp alignment) — it's produced by that processing, so there's no
static glyph table to parse. The takeaway is *where it's processed*, not a claim
that the rangetile/menu atlas is uninvolved.

**Faithful reproduction (SUPERSEDED → see `docs/hud-number-font.md`):** the
earlier approach byte-captured the composed glyphs from the scratch page
(`tools/build_hud_digits.py` → `HUDDIGITS.tga`), but a destructive "un-overlap"
pass damaged the `8`, and the scratch page composes at a tighter pitch than the
display. **Retired 2026-06-18.** The cur/max digits are now extracted statically
from `EVENT/FRAME.BIN` (ISO-reproducible, two authored sizes — big `cur`, small
`max`) by `tools/parse_frame_font.py` → `FRAMEFONT.tga`, loaded through
`src/ui3/elements/NumberFont.gd`, and composed at the per-size advances measured
off the framebuffer reference. The panel still renders through the SAME menu CLUT
`0x7cbc` (`vitals_sprite.gdshader`). The `scratchpad_sstate*.bin.gz` captures
remain as the test oracle.

---

## 9. Provenance

Symbol index: `project-assets/fft-rom/hacktics_symbols.tsv`. All addresses above
are citable against `hacktics_disassembly.txt` via that index or `grep -an`.
Hardened in `/grill-with-docs` against the `ui3` / Combat-UI domain model (see
CONTEXT.md **Feedback HUD**); architectural shape recorded in **ADR-0063**
(building on ADR-0037 combat-visual freeze / ADR-0031 battle-state authority).
Next: slice the Build plan into issues (`/to-issues`).
