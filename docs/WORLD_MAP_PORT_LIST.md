# The world-map screen — the port list

**Status:** open, written before the scene. Branch `feature/world-map-screen`, cut from
`origin/import-godot-game` (`a409bd39a`).

This is the load-bearing artifact of the world-map build, and it is written **first** on
purpose. The git-merge surface of a new screen is near zero — Formation's first commit was
9 files, 214 insertions, 0 modifications to existing files (`0c4c47457`, verified) — so branch age is not the cost.
The cost is the **reference surface**: shared symbols the screen reaches for do not
conflict, they break *silently*. A `preload("res://src/audio/…")` against a system that is
mid-lift just stops resolving.

Every row below is a crossing in [ADR-0116](adr/0116-a-crossing-needs-a-payload-an-owner-and-an-edge.md)'s
terms — **payload, owner, edge**, plus the cheapest legal *shape* (dec. 3). Enumerated
rather than inspired, per dec. 2: #306 authored crossings by inspiration and missed
`Render`, the map split and every port.

**The placement of the resulting code is NOT decided here** — see
[#416](https://github.com/timbermania/fft-monorepo/issues/416). New files only; the
placement is a `git mv`, this list is the real work.

---

## 0. What the screen is, in blueprint terms

**A feature, not a system.** `BLUEPRINT.md` → *"A feature is not a system"*: features are
threads, systems are the cloth, and asking the shipping question about a feature always
returns an alarming number. The world map threads **Campaign** (#9), **UI** (#6),
**Render** (#10), **Audio** (#7) and **Cutscene** (#8). It gets no addon.

Two blueprint passages name it and read as if they disagree. They do not:

- `BLUEPRINT.md:635`, **§9 Campaign — the spine**: *"Story scene, formation, deployment,
  battle, results, world map."* — the map is one of the **modes Campaign sequences**.
- `CONTEXT.md:8084`, the Campaign vocabulary entry: *"_Avoid_: world map (that is a screen
  over this)"* — a **naming** rule: do not call Campaign "the world map".

Together: **Campaign owns the progression state and the mode transition; something else
owns the screen.** That split is the spine of this list.

## 1. Where the model already is

The RE is finished and mechanised — `research/working_documents/WORLD_MAP_SCREEN.md`,
13 rounds, five suites, 126 green rows. Two things there are directly consumable:

- **`travel.py json`** — the port payload (§29.7): 43 nodes, 48 routes, the variable-store
  layout, the facing rules, all 182 node event scripts. One suite row proves a walk
  replayed *from that JSON alone* reproduces a watched traversal's twelve waypoints.
- **`wldgen.py`** (§30) — the generator. From a 13-field state vector plus the disc files
  it emits the settled frame's primitives **exactly**: 60/60 main list and 12/12 ribbon,
  packet for packet, on two captures. **This is the oracle the Godot scene is checked
  against**, and it is the reference implementation to port — not `render_scene.py`, which
  replays.

---

## 2. Render (#10) — EXTRACTED, `addons/exmateria_render`

Direction is downhill (Render ships early, the map ships late), so Query/Command are legal
and no inversion is needed.

| # | payload | owner | edge | shape | status |
|---|---|---|---|---|---|
| R1 | PAR / display geometry — `pixel_aspect`, the UI-side scrub | Render | map → Render | Query | **available**, autoload `PSXDisplay` |
| R2 | indexed-sprite sampling: an index atlas + a CLUT texture + a cell rect | Render *(should be)* | map → **`src/ui3/`** | Query | ⚠ **misplaced, see below** |
| R3 | PSX blend modes `abr` 0/1/2 over one surface | Render | map → Render | opaque mode token (ADR-0128) | ⚠ **no host counterpart** |

**R2 — the idiom exists but lives in the wrong system.** `src/ui3/elements/FrameCellAtlas.gd`
+ `src/ui3/shaders/vitals_sprite.gdshader` are exactly the "4bpp index atlas sampled through
a CLUT texture" contract the world map needs, and `FrameCellAtlas`'s own docstring states
the general rule: *"the ROM draws those cells as 4bpp indexed quads through whatever CLUT
the screen wants."* By ADR-0117 dec. 6 (*Render is genre-orthogonal — about looking like a
PlayStation*) that is Render's, not UI's. It is in UI3 because UI3 needed it first.

- **Do not copy it into the world map.** A second copy is a second source of truth for the
  index→CLUT contract and would have to be reconciled at Render's next extraction.
- **Do not silently depend on it either** — that is an uninterfaced reach (ADR-0131) into
  an unextracted system's private file.
- **Do:** reach for it explicitly by preload, list it here, and file it as a Render
  candidate for the next Render pass. Two concrete deltas the world map needs:
  `vitals_sprite.gdshader` is `shader_type spatial` with a **16-entry** CLUT, and the
  aperture is **8 bpp / 256 entries** (§13.1).

**R3 — the aperture is the hard one, and it is not a colour recipe.** §13.1/§13.2: two
layers of one 8 bpp distance field, read through two different 256-entry CLUT ramps, in two
different blend modes — subtractive (`B−F`, up to 31/31) and additive (`B+F`, up to 7/31),
both non-linear and slightly non-neutral. The document's own warning applies with force:

> *"you cannot get this from a greyscale mask and an alpha multiply."*

`ColorRecipe`'s affine shape (`c·scale + bias`) is the right *algebra* for add/subtract, but
the falloff **lives in the palette, not in the recipe** — the texel value is a distance and
the CLUT is the curve. So R3 is a **blend-mode token on a quad**, ADR-0128's *"opaque mode
token"*, not an ADR-0067 colour layer. Godot side this needs `blend_sub` alongside `blend_add`
on two passes over the same surface; see `[[psx-blend-clamp-forward-plus-fork]]` and
ADR-0103's finding that Godot blend is per-`CanvasItem` and the PSX level rides vertex alpha.

## 3. UI (#6) — UNEXTRACTED

| # | payload | owner | edge | shape | status |
|---|---|---|---|---|---|
| U1 | element registration | UI | map → `src/ui3/UI3Registry.gd` | Command | available (autoload), ADR-0088 |
| U2 | screen mount over the world | UI | map → `src/ui3/formation/` precedent | — | precedent only, ADR-0137 |
| U3 | cursor + input conventions | UI | map → UI | Query | precedent only |

ADR-0137 is the precedent to follow, not to import: the Formation screen re-hosts **over
the map as a camera child scene**, entered through a paused camera takeover. The world map
is a full-screen 256×240 surface with its own vignette and no battlefield underneath, so it
is a *simpler* case — but the mount mechanism (camera child, not a `SubViewport`) is the
same, and `[[map-camera-is-ortho-ui-mounts-as-camera-child]]` records why: a `SubViewport`
map silently kills the fold.

## 4. Campaign (#9) — UNEXTRACTED, and the biggest gap

| # | payload | owner | edge | shape | status |
|---|---|---|---|---|---|
| C1 | the state id `WORLD_MAP` | Campaign | map → `src/scenarios/GameState.gd` | Query | **available** — `GameState.State.WORLD_MAP = 4` |
| C2 | mode transition in / out | Campaign | Campaign → map | Command | declared, **not implemented** |
| C3 | node-known bits, route-drawn bits, story counter, gil, date | Campaign | map → Campaign | Query | ⚠ **DOES NOT EXIST** |

**C1 is real and already there.** `GameState.State.WORLD_MAP = 4` is in the spine enum, and
`GameState.for_sink("WORLD_MAP")` maps a `transition_graph.json` edge onto it. So the
navigator can already *name* the state.

**C2 — BUILT, and what was missing was the EDGE, not the scene.**

110 of the graph's ATTACK edges name a **sink** instead of an int scenario id — 97
`WORLD_MAP` (post = `0x80` GoToWorldMap) and 13 `RESET` (post = `0x82`). `GameNavigator`
ran `int(target)` over them; GDScript reads a non-numeric String as `0`, the caller reads
`0` as "no successor", and the walk **ended silently**. The very first story walk hits
one — `1 -> 3 -> 7 -> 9`, and group 9 (Gariland) exits to `WORLD_MAP`. `NavigatorMain`
even logged it: *"Walk finished at group 9 (world map OOS)."*

So the wiring is three small pieces and one new reading:

| | |
|---|---|
| `GameNavigator.exit_sink(root)` | the sink a group exits to, off the same edge `_next_root` reads, so the two cannot disagree about where a group goes |
| the planner | where the walk used to `break` on `next_root <= 0`, a `WORLD_MAP` sink now appends a `{"kind": "world_map"}` action |
| `NavigatorRunner` | dispatches it, sets `GameState.State.WORLD_MAP`, and advances on `on_world_map_finished()` |
| `NavigatorMain.run_world_map` | mounts `WorldMap.tscn` and awaits `dismissed` — the `run_formation_view` shape |

The sink reading is checkable from two sides: the graph's last-member `ATTACK` edge and
the group database's own `exit == "GoToWorldMap"` field, written by different tools.
**83 linear groups, zero disagreements.**

**A `CanvasLayer`, not a camera child and not a `SubViewport`.** ADR-0137's Formation
precedent mounts as a camera child because it re-hosts over the live battlefield, and
`[[map-camera-is-ortho-ui-mounts-as-camera-child]]` records that a `SubViewport` map
silently kills the compositor fold. The world map is the simpler case §3 predicted — a
full-screen 256×240 2D surface with its own vignette and no battlefield underneath — so
it needs no camera of its own. What it must not be is a `SubViewport`, and a
`CanvasLayer` is neither. Mounted it takes the largest WHOLE zoom the viewport allows
(4, at 1024×960) and centres; a fractional zoom would resample the console's pixels.

⚠ **The default proof walk is unchanged.** `plan_actions(1, 9)` stops at group 9 through
its own stop-root branch, before any successor is considered, so it still plans exactly
10 actions ending on the victory beat. The world map appears on the NATURAL-end walk
(`stop_root <= 0`), which is where the story actually goes. `WorldMapNavigatorTest` asserts
both arms.

> **Superseded by §17.** Every sentence above is true and both arms still pass — and
> `NavigatorMain.STOP_ROOT` was **9**, so the walk a player cold-boots was the truncated
> arm, not the natural-end one. This paragraph is the caveat; §17 is what it cost.

⚠ **The world-map action is terminal.** The map reports "the player entered node N" to
Campaign; turning that into the next scenario is X1 (ADR-0117 dec. 8), so the walk
finishes on the screen rather than one step short of it.

`assets/scenarios/game_states.json`'s `world_map` entry said *"The 0x80 fork was never
captured; ~0% RE'd … PARKED pending a world-map savestate"* and `godot_scene: null`. Both
have been true for a long time and neither is now.

**C2/C3 are the gap, and C3 is the one that matters.** `grep -rn WORLD_MAP src/ tests/`
returns four hits, **all four inside `GameState.gd` itself** — nothing implements the state.
And there is no world-flag store at all: on the PSX these are `WORLD.BIN`'s variable store
(node known = bit `512+i`, route drawn = bit `556+r`, the story counter = `var[110]`, plus
gil and the date), which `travel.py` reads directly; the Godot host has no counterpart.
`grep progression src/scenarios/` returns only *unit* progression, which is unrelated.

> **The world map's Campaign crossing has nothing to bind to.** The screen must supply the
> store itself. It should be written as **Campaign-owned from the first line** — a single
> typed object with the four questions on it (`is_node_known(i)`, `is_route_drawn(r)`,
> `story_counter()`, `gil()` / `date()`) — so the eventual Campaign extraction claims it
> whole instead of digging it back out of a screen. This is the row most likely to be got
> wrong by building the screen first and the state second.

**BUILT.** `WorldMapProgress` is that query surface and `WorldMapVariables` is its
backing — `WORLD.BIN`'s game-variable store in the ROM's own encoding: 684 bytes, three
regions that tile it exactly (u32 below 128, one bit below 864, one nibble below 1024).

The ROM's encoding rather than a `Dictionary` of booleans, because the 182 per-node event
scripts address these variables **by index**, and so do the battle side's
`event_set_script_variable` and the BC opcodes that read gil. Spelling the flags as
Godot-idiomatic fields would need a translation table the moment X1 lands, and that table
would be this layout written a second time.

Seeded from the console: `OPENING_CAPTURE` is 32 raw words lifted off
`world_map_ss1_settled_dialog_closed.sstate` by `tools/wm_progress_dump.py`. Word 140 is
`0x01000044` and word 141 is `0x0000A000`, and that they decode to exactly nodes
{2, 6, 24} and routes {1, 3} — which §29 measured by a different route, off the node
descriptors' own `flags & 0x10`, 43 nodes × 3 savestates with zero mismatches — is the
whole claim `WorldMapProgressTest` makes. The 26 rows also walk each region at its own
boundaries, because an off-by-one word in the bit or nibble base would still decode the
opening capture: every *named* variable it holds lives in the u32 or the bit region.

Two things it deliberately does **not** hold:

- **the selected node.** `DAT_800D0BB4` is the world map's own working RAM, not the
  variable store, and §27.4 derives it from the cursor by hit test every frame. It lives
  on `WorldMapCursor`. See §10.3 for what putting it here cost.
- **a proven new-game seed.** `OPENING_CAPTURE` is the earliest capture the repo holds;
  nothing read so far says what `WORLD.BIN` starts a fresh campaign with. Flagged in
  place rather than presented as one.

⚠ Also carried but *not* a game variable: the party's node. §30.4 reads it back off the
marker's descriptor position, and nothing located so far says where a save keeps it.

⚠ `gil` is var `0x2C`. That index was exported as "chapter" until 2026-08-22.

## 5. Audio (#7) — EXTRACTING RIGHT NOW under #410

| # | payload | owner | edge | shape | status |
|---|---|---|---|---|---|
| A1 | "play the world-map track" | Audio | map → **a one-method port** | Command | **BUILT** — slot 27, measured |

`src/audio/` is mid-lift. Per #410, `MusicPlayer` is on the **staying** side (host), along
with `SfxRouter`, `SfxCatalog`, `AttackSfxResolver` and `ExMateriaAudioEngine`'s bus half;
`ExMateriaEffectSfx` moves whole and `ExMateriaAudioEngine` splits. So:

**A1 — BUILT, and the slot is 27.** `WorldMapMusicPort.WORLD_MAP_SLOT` sat at `-1`
because a wrong track is audible the moment anyone listens, so it was left unplayed
rather than guessed. It is now measured, not guessed: a loaded SMD is resident verbatim
in main RAM, so a savestate says which one a screen holds.

| | |
|---|---|
| `MUSIC_27` resident in | **4 of the 38** savestates in `reference-assets/` — and all four are the SETTLED world map |
| absent from | the other 34, **including** the two world-map-adjacent ones, `load_now_loading` and `ss0_scenario_end_prequicksave`, where the map is not up yet |

Residency alone only proves it is loaded. The four world-map captures are the same screen
at four moments, and `MUSIC_27` is the only resident sequence whose per-channel cursors
**move** between them — 35 of 79 pointer slots differ, while `MUSIC_12`'s 108 and
`MUSIC_45`'s 35 are frozen to the byte. A playing sequence advances its cursors; a
preloaded one does not. (`MUSIC_12` is resident in 26 of the 38 and is the one advancing
in the Orbonne captures — a scenario track the world map keeps loaded, not its theme.)

Both arms: it tracks the SCREEN, not the disc region.

- **Do not reference `ExMateriaEffectSfx` or `ExMateriaAudioEngine`** — one moves, the other splits.
- `MusicPlayer` is an autoload (`project.godot:46`) with a usable surface:
  `play_slot(slot: int) -> bool`, `fade_out(ticks)`, `stop()`, `is_playing()`.
- **Still go behind a one-method port.** `src/` only shrinks (ADR-0121 dec. 2), and after E2
  the canonical source is `exmateria-sound/addons/exmateria_sound/`, synced by
  `tools/sync_exmateria_sound.sh`; `godot-learning/addons/exmateria_sound/` is a
  **gitignored deployment target, not a source tree** (#410 — and #326 is the evidence:
  that copy went 72 lines stale for weeks and surfaced as a parse error in a *different*
  package's UI). #387 / B5 is the eventual host-migration ticket. The point of the port is
  that it can be **implemented** now rather than stubbed.

## 6. Cutscene (#8) — UNEXTRACTED, not needed for the scaffold

| # | payload | owner | edge | shape | status |
|---|---|---|---|---|---|
| X1 | a scenario identity to run, on entering a node | Campaign → Cutscene | map → Campaign | Command | **the seam exists** — `WorldMapScene.node_entered`; nothing subscribes |

ADR-0117 dec. 8 fixes the direction: *"`Campaign` picks a `Scenario`, which points at an
event script, which `Cutscene` plays."* The map never plays anything — it reports "the
player entered node N" to Campaign. The 182 per-node scripts (§29) are a Campaign/Cutscene
concern, decoded and exported already but not wired here.

## 7. Assets — a new packet, and a new extractor

ADR-0142 dec. 1's test: *"if this asset's encoding changed, which system's code would have
to change?"* For the world map's art that is the **extractor plus the screen**, so the
packet is the screen's and is filed with whichever system finally hosts it (#416).

New extractor, following the `tools/parse_*.py` precedent (`parse_frame.py`,
`parse_formation_background.py` …) which turn `project-assets/fft-extract/` into gitignored,
regenerable `assets/…`:

| source | product | note |
|---|---|---|
| `WORLD/WLDTEX.TM2` | the VRAM image | §18 — decoded and **100% verified**, 126,416/126,416 halfwords bit-exact, reproduced by the extractor. ADR-0001: *"this is the parser a Godot-side extractor should be built from, not a hand-maintained dump"*. |
| `WORLD/WLDCORE.BIN` | node table, cel bank, frame lists, route polylines | node table from the **disc** at `0x80094DFC` (§30.1); cels and routes likewise. No savestate needed for any of it. |
| **`EVENT/FRAME.BIN`** | the shared UI sheet at VRAM (960,256) | **found by building this** — see below. |

**§18.1's open half, closed.** The doc records that the cursor, the map pins and the
war-funds digits come from a shared UI sheet at VRAM `(960,256)` which is *not* in
`WLDTEX.TM2`, and leaves *"finding that sheet's disc source"* as §15 #9's remainder.
Replaying the TM2 alone therefore draws a world map with **no cursor, no pins and no war
funds** — which is exactly what the first run of the scaffold showed, and how this was
found. It is **`EVENT/FRAME.BIN`**, and the mapping is a straight row shift:

    VRAM (960, 256 + r)  ==  FRAME.BIN pixel row (r + 32)      128 bytes each

Both sides are 4 bpp and 256 texels wide, so a row is 128 bytes either way and nothing is
repacked. **240 of the 256 page rows are byte-identical** to the console's VRAM; the last
16 differ and are left alone, because nothing the world map draws reaches them (cursor
v 0–16, pins v 0–28, funds digits v 40–64, its label v 120–128).

That is **crossing R2 showing up as a fact rather than a prediction**: `FRAME.BIN` is
already in this tree's hands — `tools/parse_frame.py` decodes it to `assets/ui/frame.tga`
and `FrameCellAtlas` inverts that back to 4bpp indices for exactly this purpose. Two
consumers, one sheet, and the format owner is not the world map.

⚠ **One input has no disc source: the 81-quad background grid** at `0x800C7320` is BSS —
the disc bytes there are zero. Open question §15 #17. It does not block the scaffold:
§28.3 shows the background is not geometry on a settled frame at all, it is a DMA of a
pre-composited cache, so the Godot side wants **one background image**, not 81 quads.

---

## 7b. The screen is driveable — four faults from actually looking at it

The port was measured against the console framebuffer and never *watched*. Running it
found four things a 99.59% pixel match cannot see — and the fourth (7b.5) was found by a
*player* saying the cursor did not "click into place", after three rounds of green
assertions had missed it and one round had asserted the opposite.

### 7b.1 The frame was never centred in the surface it was drawn into

`project.godot` sets `window/stretch/mode="viewport"` over a fixed **1024×960** viewport,
so the window size is decoration: resizing it does not give the frame more room, it
rescales the finished 1024×960 image. The scaffold sized the WINDOW to `256×240 × zoom`
and drew at the origin — which left the map in the viewport's top-**left** corner with
black down the right and along the bottom, and a tiling WM overrode the window size
anyway (measured 1261×1390 for a window the scene had just set to 768×720).

That reads as two faults, *"it doesn't fill the window"* and *"the vignette is
off-centre"*, and is **one**. Lay out against the viewport, largest whole zoom, centred.
1024 / 256 == 960 / 240 == **4**, so the fit is exact and there is no letterbox.

⚠ **The vignette really is off-centre, and that is the console's.** Luminance centroid,
console and port, both `(129.05, 112.25)` against a frame centre of `(127.5, 119.5)` —
about 7 px high. §13.4 names it (*"the off-centre glow at (-44,-32)"*), and §22.2's
drawing area is itself asymmetric by design: 8 blank rows at the top, 4 at the bottom, 4
blank columns at the right.

### 7b.2 The animation ran at the display's refresh rate

`_process` ticked the pin pulse and the party marker once per RENDERED frame. Both are
counted in the console's **vsyncs**: §21.3 sampled the pulse once per vsync over 6,675
frames and states the period as *"128 frames = 2.133 s at 60 Hz"*; §21.4 gives the idle
as *"a 40-frame (0.667 s) cycle"*. The measured display here is **143.9 Hz**, so both ran
**2.4× fast** — visible on the party marker long before it is visible on the pulse.

Fixed 60 Hz accumulator, fractional debt carried between frames, and missed ticks
**dropped** rather than replayed: after a stall the console would not replay them either,
and burning 300 ticks in one visual frame reads as a glitch, not as catching up.

### 7b.3 The cursor could not move — and §27.6's dynamics are RIGHT

Now it can: `ui_left/right/up/down` step it once per vsync, ○ (`ui_accept` /
`cursor_confirm`, i.e. Enter) over a known node emits `node_entered`, ✕ (`ui_cancel`)
leaves. ⚠ `ui_cancel` is **Backspace** in this project's input map — Escape is
`battle_pause`.

§27.6 states the dynamics as:

> *"a held direction takes 8 frames to start moving, accelerates to ~4 px/frame, and
> coasts ~12 px over 6 frames after release … a 2-frame tap moves it ZERO pixels"*

⚠ **All four are right, and this port called two of them wrong before it called them
right again.** The history is worth keeping, because the second mistake was made
*confidently, with a measurement in hand*:

1. **Round one** ported the sentence literally as an 8-frame dead zone. Driving it, the
   cursor felt broken — no feedback for an eighth of a second, and then almost impossible
   to land inside a 21×21 box.
2. **Round two** opened `round10_travel_trace.csv` — the per-vsync recording
   `capture_travel.lua` itself produced — found the cursor moving on frame 1 of the press
   it had picked out, declared the prose a bad summary, and asserted a fitted curve
   `1,1,2,2,3,3,4,4,4,3,3,2,2,1,1` in its place. That is 7b.5's story: **the frame 1 it
   picked was five vsyncs late**, because the first five frames of a press move the cursor
   nowhere for a reason nothing had looked for yet.
3. **Round three** read the instructions instead, and both halves fell out of the ROM.

**The ramp is a ROM constant.** `FUN_80068E70` at `0x80068E70` is a plain 8.8 fixed-point
accelerator over a five-word struct — `acc`, `max`, `accel`, `decel`, `vel` — and the
screen's setup writes the constants literally at `0x8006C6B8`..`0x8006C704`:

| | x, `0x8009EF6C` | y, `0x8009F184` |
|---|---|---|
| `max` | `0x400` | `0x400` |
| `accel` | `0x80` | `0x80` |
| `decel` | `0x80` | `0x80` |

Half a pixel of acceleration per vsync, capped at four; `vel = acc >> 8`, so a press reads
`0, 1, 1, 2, 2, 3, 3, 4, 4 …` and a release `3, 3, 2, 2, 1, 1` — **`3+3+2+2+1+1 = 12`,
§27.6's coast, and frame 1 of a press really does move zero pixels.** The accumulator is
signed and carries the direction, so a reversal decelerates *through* zero rather than
restarting; nothing needs to remember which way you were going.

⚠ **The rounding is not symmetric and the port keeps it that way.** The `dir >= 0` path
is a bare `sra v0,v0,8` (`0x80068EE8`); the `dir < 0` path negates around the shift
(`0x80068F90`..`98`). They agree on a whole accumulator and disagree mid-reversal, so
`acc = +0x380` reads **4** px/vsync while LEFT is held and **3** while nothing is — which
makes turning around coast 16 px where letting go coasts 12.

**What the disassembly settles**, since a harness summary had already been wrong once:

| | |
|---|---|
| `0x8006D530` | `cursor.x += *0x8009EF7C` |
| `0x8006D5A4` | `cursor.y += *0x8009F194` |

So it *is* a velocity model, and **x and y are separate globals** — the axes are
independent, which is why a diagonal runs both at full speed rather than sharing a
budget. `FUN_8006C350` also settles `rest_at`: `cursor.x = node.x`,
`cursor.y = node.y − 4`, that −4 being the literal `addiu v0,v0,-4` at `0x8006C3B8`. It
had been a two-sample fit; it is now the instruction itself.

⚠ **"The ramp's constants are NOT in this overlay" was wrong, and how it went wrong is
the useful part.** Round two searched for writers of the *velocity* word `0x8009EF7C`,
found three (`0x8006C6DC`/`E4`, `0x8006C880`/`88`, `0x8006D234`/`3C`), saw all three store
**zero**, and concluded the ramp lived in the shared engine. It then spent a pass scanning
`WLDCORE.BIN`, `BATTLE.BIN` and `SCUS_942.21` for the curve as a table, found one
unreferenced hit at `0x80096DD2`, correctly called it animation cel data, and declared the
curve unobtainable — *while citing `[[find-refs-blind-to-indexed-globals]]`, which is the
exact reason its own search had failed.*

The accelerator writes that word as `sw v0,0x10(a0)`, through the struct pointer. That is
the indexed store the note is about, and the three zero-stores are resets. **A search that
cannot see a class of writer cannot conclude there are none** — and quoting the note that
says so is not the same as applying it. The move that works is to find the *readers*,
which sit two lines apart at `0x8006D2FC` and `0x8006D30C`, and read backwards through the
two `jal`s immediately above them.

⚠ Still derived rather than measured **in the port**: where the cursor clamps. The
console's own answer is now known and is *not* what the port does. `FUN_8006D194` does not
clamp at the drawing area at all — it hands the surplus to `FUN_8006AC08` / `FUN_8006AC98`,
which **scroll the camera** (`0x8009F2C0`, panning to −116..128 by −64..80) and give back
only what the pan could not absorb; the cursor's own hard clamp is far wider, x −112..120
and y −104..104 (`0x8006D5D0`..`0x8006D69C`). §21.1 says the view never scrolls and no
capture shows a non-zero pan, so **the scroll is unported and the wide clamps are
deliberately not adopted** — taking the clamps without the pan would walk the cursor off
the drawn map. Filed rather than guessed at: the port keeps the drawing-area clamp and
drops the axis's momentum at the wall.

⚠ **§27.4's "the box follows the art, which is drawn above its anchor" is about the PIN,
not the cursor.** The two extents say so, and conflating them made the first version of
`WorldMapCursorTest` assert something false:

| | art extent | |
|---|---|---|
| pin, frame 106 | x −6..6, y −8..4 | inside the 21×21 hit box, leaning **up** |
| cursor, frame 0 | x −17..1, y −5..13 | the hand trails **down and left** |

### 7b.4 Travel — the marker walks

○ on a known node the party is NOT standing on walks there; ○ on the node it IS standing
on enters it. §27.6 read the trigger straight off the branch: `if (hit_node !=
marker_node) FUN_8008E2BC(...)`.

This is the most completely measured thing on the screen. §29.6 drove the console from
`ss1` to node 2 and recorded 2,709 vsyncs; `travel.py walk 6 2` predicts the same walk
from `WLDCORE.BIN` alone; the two agree **waypoint for waypoint**. `WorldMapTravelTest`
asserts the port against that recording's own literals:

| | |
|---|---|
| path | route 3 then route 1, **both reversed** |
| legs | 5 + 7 = **twelve** |
| headings | 951, 1183, 1407, 1362, 1078 · 1799, 1326, 1183, 1643, 2140, 2311, 2129 |
| frame lists | 26, 26, 27, 27, 26 · 28, 27, 26, 27, 28, 29, 28 — the **fast** bank throughout |
| duration | **94 vsyncs, 1.6 s** |

**The leg duration reading is new here.** A waypoint's `d` had no stated meaning in
vsyncs; `travel.py json` exports `2 * d` as "ticks". Fitting nine candidates against the
trace — `2d−1` / `2d` / `2d+1` motion steps × hold-a-vsync-or-not × three roundings —
leaves exactly one that ends the walk on the console's own **v321**:

> **a leg is `2 · d` motion steps plus ONE vsync held at its endpoint**, and the twelve
> sum to 94.

⚠ **73 of 95 vsyncs land on the console's exact pixel; the other 22 are within 1 px.**
Every waypoint *arrival* is exact, and so is every heading, frame list and leg duration —
what is unresolved is the rounding of the interpolation *between* waypoints. Truncation
toward zero is the best of the three tried. The console is presumably stepping a
fixed-point accumulator along the heading rather than interpolating endpoints; that is a
§15-shaped open question, not this port's.

⚠ **The idle frame list is 16, not `SLOW_BANK + facing(heading)`.** §29.6's v227 reads
heading 951 with frame list **16** and v228 reads 26 — the heading register is written a
vsync before `FUN_8008F434` follows it, so the marker is still standing in its resting
pose. Reproducing that first frame as "the slow bank at the new heading" gives 18, and
`WorldMapTravelTest` is what caught it. §26.2 says the same thing from the other side:
*"id = 16 at rest means the idle marker faces the camera."*

**The map does not write progression.** Arriving sets the party's node and emits
`arrived` / `node_entered`; it does **not** set the node-known or route-drawn bits.
Those are `WORLD.BIN` variables the event scripts write, and `ss1` proves the map cannot
be the author: it has routes 1 and 3 already drawn with the party still standing at
Gariland, having walked neither. ADR-0117 dec. 8 — the map reports, Campaign decides.

**Pathfinding is restricted to routes whose BOTH endpoints the party knows.** §29 measured
that the known set and the drawn set coincide (`ss1` knows {2, 6, 24} and has drawn
{1, 3}, *"exactly the two edges joining those three nodes"*), so the two gates agree on
every capture. Known-endpoints is the one used because the other is circular: a route is
drawn by story script, so gating travel on it would make a node you can see a node you
can never reach.

The travel waypoints are a **new export** — `tools/parse_world_map.py` read only the
ribbon's polyline table before. They are its sibling and not the same data: the polyline
stores PAIRS of edge vertices for drawing a strip, the waypoints are single points the
marker walks.

### 7b.5 The cursor "clicks into place" — a magnetic snap, and it explains everything else

> *"I am pushing enter on the city and it's not walking. Maybe the cursor isn't linking to
> the city? Is it supposed to kind of 'click' into place?"*

Yes. `FUN_8008D194` at `0x8008D194`, called **every vsync** from the cursor's own update
at `0x8006D380` with the **proposed** position (`cursor + velocity`), never the settled
one:

```c
*dx = *dy = 0;
hit = FUN_8008D060(cx, cy);              // the same 21x21 test as node_under, §27.4
if (hit == 0) return 0;
nx = *(0x800D3CD0 + 0x34*i);             // the very table the hit test walks
ny = *(0x800D3CD4 + 0x34*i);
ty = ny - 4;                             // the SAME -4 as rest_at — the target IS the
                                         // resting point, not the node's own point
*dx = clamp(nx - cx, -2, +2);            // 0x8008D214..58
*dy = clamp(ty - cy, -2, +2);            // 0x8008D264..A8
return hit;                              // -> sprite[+0x0C], the SELECTION
```

and the caller adds it straight onto the velocity: `addu a0,a0,v0` / `addu a1,a1,v1` at
`0x8006D39C`.

**So while the cursor is inside a node's box the game pulls it up to ±2 px per vsync onto
that node's resting point, landing exactly rather than stepping past.** That is the click.
It does *not* contradict §21.2's *"the cursor is free-moving, not node-snapping"*: the
cursor never jumps between nodes, and against the ramp's 4 px/vsync the pull loses — net
2 px/vsync outward — which is how you leave a node at all.

**Three separate mysteries collapse into this one mechanism:**

| what was believed | what it actually is |
|---|---|
| §27.6: *"8 frames to start moving"* — called wrong in round two | The cursor starts **on a node**. The pull cancels the ramp exactly for the press's first five frames; on the sixth the ramp clears 3 px against a 2 px pull and the cursor finally moves 1. Not a dead zone — a tug of war, and the prose was describing it from the outside. |
| §27.6: *"a 2-frame tap moves ZERO pixels"* — called a harness artefact in round two | Also true, and for the same reason. Off a node a 2-frame tap moves 1 px. |
| Both savestates read the cursor at *exactly* `rest_at(node)` | Nothing else parks it there. `FUN_8006C350`, the hard placement, has a single caller — the screen initialiser at `0x80067C8C` — so entry aside, only the pull can produce that. |

**Validated against the recording, not fitted to it.** `WorldMapCursorTest` replays two
stretches of `round10_travel_trace.csv` a vsync at a time and compares positions:

- **vsyncs 49–65**, LEFT held from Gariland: `−4 −4 −4 −4 −4 −5 −6 −8 −10 −12 −16 −19 −22
  −24 −26 −27 −28`. The five leading `−4`s are the pull eating the ramp; `−16` is the frame
  the cursor clears the 21-wide box and the pull stops.
- **vsyncs 168–177**, UP held from `(−65,−41)` into Igros Castle: the **x** column slides
  5 px sideways although x is never pressed, the cursor lands on `(−60,−53)` =
  `rest_at(node 3)`, and then **stops dead** — the entire release coast, 3+3+2+2+1+1, is
  absorbed by the pull rather than overshooting.

Both reproduce exactly, 27 consecutive vsyncs, position for position.

⚠ **The pull has a gate the port does not need.** It is skipped when
`*(0x800D3C8C) & 2` (`0x8006D318`). That bit is zeroed by the screen initialiser at
`0x80067EF0` and toggled only inside `0x8006CD08`'s block — a separate mode which also
stashes the camera pan into `0x800D3C98`, and which nothing this port has can reach. The
pull is unconditional here, and the gate is recorded so the next round does not rediscover
it as a contradiction.

**What this changes in the port:** `WorldMapCursor.step()` now takes the assets and
progress so it can run the hit test, and publishes `hit_node` — the console's own
`sw v0,0xc(s1)`, tested against the *proposed* position. `WorldMapScene._confirm` reads
that stored hit rather than re-testing the settled position; the two disagree on the frame
the cursor leaves a box, and the console uses the stored one. `WorldMapCursor.resolve()`
seeds it after a `place()` so ○ on the frame the screen opens works.

## 8. The rules this build works under

1. **`src/` is never reorganised** (ADR-0121 dec. 2). New files only; no preparatory moves.
2. **Never reach by autoload name + `.call("…")`.** #316 found `Render` reaching `Effects`
   that way — invisible to the classifier *and* to `touch_matrix.py`. Every crossing above
   is a typed, greppable preload or an autoload used by its declared surface.
3. **No new `class_name` collisions.** `src/` declares 337 globals (ADR-0121). World-map
   globals take a `WorldMap` prefix.
4. **Godot runs headful.** `/usr/local/bin/godot` (4.8), never `/usr/bin/godot` (4.7),
   never `--headless`. Root `CLAUDE.md`.
5. **The oracle is `wldgen.py`, and the check is a picture.** `[[render-atlas-crops-and-look-at-them]]`
   — compare against `research/working_documents/world_map_captures/images/round13_generated_scene.png`.

## 9. Summary — what is available, what must be built

| | crossings |
|---|---|
| **available now** | R1 `PSXDisplay` · U1 `UI3Registry` · C1 `GameState.State.WORLD_MAP` · A1 `MusicPlayer` behind a port |
| **exists, misplaced** | R2 the index+CLUT idiom (UI3's, should be Render's) — reach explicitly, do not copy |
| **BUILT** | R3 the two-layer 8 bpp aperture (§10.1) · C3 the Campaign world-flag store (§4) · C2 the mode transition (§4) · the extractor + asset packet |
| **not needed yet** | X1 node-event dispatch — the map reports the node, Campaign picks the scenario |

Four reaches, one of them misplaced, one system-owned store that has to be written from
scratch, and one genuinely hard renderer. That is the whole reference surface — which is
the number the branch-base argument was really about.

## 10. The scaffold, measured — against the CONSOLE

The measurement in the first cut of this section compared the Godot frame to
`wldgen.py render`'s picture. That is the wrong reference for *colour*, and the mistake
was load-bearing: `wldgen.py` is packet-exact, but it PAINTS its list with
`render_scene.py`'s rasteriser, which never applies the per-packet `rgb` modulation —
`blend()` takes `pal[idx]` straight. On this screen the modulated primitives are the map
pins, whose entire point is that they pulse (§21.3, §30.6). A renderer that modulates
*correctly* therefore reads as ~128 wrong pixels against the oracle's picture.

So there are two references and they answer different questions:

| | reference | answers |
|---|---|---|
| **packets** | `wldgen.py prims` — `tests/goldens/world_map_prims_ss{1,2}.txt` | geometry, uv, tpage, CLUT, order |
| **pixels** | the CONSOLE framebuffer, out of the savestate — `tools/wm_console_frame.py` | colour, blend, transparency |

`tools/wm_compare.py` prints the unblended core separately and a **histogram**, never a
mean: §10's first draft records a mean of ~0.26 being consistent with two different
stories about the residual, and only the histogram killed the wrong one.

**Where it stands**, 1:1, both captures, against the console:

| | exact | off by 1 | off by more |
|---|---|---|---|
| **unblended core** (x 37–79, y −40–39, no aperture pass at all, §13.3) | **3440 / 3440 = 100.00%** | 0 | 0 |
| `ss1` whole frame | **61187 / 61440 = 99.59%** | **0** | 253 (0.41%) |
| `ss2` whole frame | **61122 / 61440 = 99.48%** | **0** | 318 (0.52%) |
| *`wldgen.py render`, same comparison* | *59412 / 61440 = 96.70%* | *0* | *2028* |

Every remaining wrong pixel on both captures is inside the travel ribbon's band, and
**zero are anywhere else**. The ribbon is §22.3's own worst region for reasons that
predate this port: its texture is 1-texel dithered stripes on a sheared span, so the
result depends on sub-texel sampling. It is not chased here.

Two things closed the 26.5% the scaffold was missing.

### 10.1 R3 — blend in five bits, expand once

The scaffold expanded each texel to 8 bits at bake time and let Godot blend 8-bit
values, computing `e(B) op e(F)` where the console computes `e(B op F)`. With
`e(v) = (v<<3) | (v>>2)` those differ by 0 or 1 — 15,922 pixels, 25.9% of the frame,
off by exactly one 8-bit level.

The fix is not a blend shader. Keep the framebuffer in the console's own channels by
baking a level `v` as the byte `8v`, and expand ONCE at the end
(`psx_expand_555.gdshader`, on a `BackBufferCopy`, blending off). Fixed-function
blending then lands exactly where the GPU's does:

    abr 0  (B+F)/2   MIX alpha 0.5 -> byte 4(B+F), and floor(/8) IS (B+F)>>1
    abr 1   B+F      ADD           -> clamps at byte 255, i.e. level 31
    abr 2   B-F      SUB           -> clamps at byte 0
    abr 3   B+(F>>2) ADD, with F shifted AT BAKE TIME

abr 3 is the one that needed help: the console truncates the quarter and then adds,
Godot's alpha 0.25 truncates the sum, and a vertex alpha is 8-bit quantised so 0.25
lands at 63/255 and reads a whole level low on 51 of 1024 pairs. `F` is a CLUT entry, so
the shift is taken at bake time and the blend runs at alpha 1. No world-map primitive
uses abr 3; it is exact anyway, because a mode that is only correct because nothing
reaches it is a footnote waiting to be a bug.

`tests/WorldMapBlendTest.gd` walks all 4 x 32 x 32 = 4096 (mode, B, F) triples on the
GPU and compares each to `render_scene.py`'s `blend()`. No ROM asset needed.

A `BackBufferCopy` rather than a `SubViewport`: the map is already a full-screen surface
and a SubViewport here would buy nothing while costing what
`[[map-camera-is-ortho-ui-mounts-as-camera-child]]` records — a screen that mounts as a
camera child cannot be inside one (§3, U2).

### 10.2 ⚠️ Transparency is a property of the CLUT VALUE, not of the index

"Palette index 0 is the PSX's transparent key" is a convention, not a rule. The rule is
that a texel is dropped when its **resolved halfword is `0x0000`**. Both are true for
every 4bpp sprite on this screen, and both aperture ramps break the convention:

| clut | entry 0 | entries equal to `0x0000` |
|---|---|---|
| `0x7880` subtractive | `0xFFFF` -> **(31,31,31)**, full subtraction | **none, anywhere in it** |
| `0x7940` additive | `0x9CE7` -> (7,7,7) | **129 of 256** |

Reading the index threw away the subtractive ramp's blackest value exactly where the
vignette saturates — the four corners, where the console's frame is black and every
render of this screen had painted map. **956 pixels, 1.6% of the frame.**

§22.3 attributes that corner residual to *"a ±1 index difference flip\[ping\] a pixel
between black and nearly black"*. The measured errors there are **8 to 22 five-bit
levels**; a ±1 index cannot make one. The corners were a wrong transparency rule, in the
generator as well as in the port, and fixing it is most of why the Godot frame now sits
three points ahead of `wldgen.py render`'s own picture.

This is §13.2's warning arriving as a fact: *"you cannot get this from a greyscale mask
and an alpha multiply"* — the falloff lives in the palette, and so does the transparency.

### 10.3 Two defects the picture could not show

Both were found by diffing PACKETS (`tests/WorldMapPrimitivesTest.gd`), which is what
`wldgen.py`'s own docstring says to do: *a wrong CLUT or a swapped uv is a hard miss
here and a 0.1% residual in a screenshot.*

- **the cursor was drawn four pixels low**, in every frame the scaffold rendered, because
  the scene invented the cursor position *from* the selected node. It is the other way
  round — §21.2 the cursor is free-moving, §27.4 the selected node is derived from it
  every frame by a 21x21 hit test, and that is what `DAT_800D0BB4` holds. So `selected`
  came off `WorldMapProgress` entirely: it is world-map working RAM, not `WORLD.BIN`'s
  variable store, and **C3 is sharper for not carrying it**. New `WorldMapCursor` owns
  both halves.
- **the war-funds tick was not drawn at all.** A width-1 `Line2D` through `y0` straddles
  two rows by half a pixel each and Godot draws neither. The PSX fills cells `x0..x1`
  inclusive on one row, so the shape is an integer rect.

---

## 11. The START menu, watched — and four things §33/§34 had already measured

The menu was built from `WORLD.BIN`'s window record and never *looked at*, exactly the way
§7b describes the map itself being built. Running it produced five complaints. Four of the
five turned out to be **already answered inside `WORLD_MAP_SCREEN.md`**, in §33.9a's dump of
the console's ordering table with the menu open — seven primitives, printed in full:

```
1  66808080 FFB0FF90 7C3C0000 00700048   the box    (-112,-80)  72x112  clut 7C3C
2  E1 tpage=005F                         VRAM (960,256), 4bpp, abr 2
3  66808080 FFBCFF86 7DBC00B8 00100010   glove shadow (-122,-68) uv(184,0) 16x16
4  SPRT     (-124,-70) 16x16 uv(168,0) clut=7D7C   glove LIT
5  66808080 FFAFFF93 7CBC7878 00080018   "Menu" tab  (-109,-81) uv(120,120) 24x8 clut 7CBC
```

That listing was read for what it says about the **box** (§34.7–§34.11, the corrupt page).
Nobody had read primitives 4 and 5 for what they say about the **glove** and the **title**,
and they say everything.

### 11.1 The `slide` was the BOB, and it was already parsed and shipped

§33.2 reads the cursor sprite as `x = rec.x − 12 + slide` and never says what `slide` rests
at. The port wrote `static var cursor_slide := 31` and called it *"the only number a later
measurement can overrule"*. Primitive 4 is the measurement: `-124 = -112 − 12 + 0` and
`-70 = -80 + 16·0 + 10`. **`slide` is 0 at rest — it is the glove bob**, `FUN_800EC504`'s
threshold-pair table, which `assets/sprites/cursor_bob.json` has carried since ADR-0046
(`glove_idle`, WORLD.BIN `0x80156352`, period 46) and which `StartActionMenu` and
`JobPickerMenu` already consume.

So the port's `31` had pushed the hand off the frame and the labels right to clear it. The
console's glove **straddles the box's left edge**: 16 px starting at `rec.x − 12`, so 12 px
off it and 4 px onto it. The row labels then start at `rec.x + 9` —
`StartActionMenu.ROW_TEXT_INSET_X`, framebuffer-measured for the *same* window driver
(`FUN_800EC5B8` serves both screens), which is the one number on this window that is still
⚠ borrowed rather than measured here.

The bob is counted in **vsyncs** on `WorldMapScene.advance()`, not in `_process` — §7b.2's
fault, avoided rather than repeated. One counter for the screen, because `FUN_800EC504`
takes a free-running timer modulo the table's period.

### 11.2 The "Menu" title tab — and the CLUT tail `parse_world_map.py` was not copying

Primitive 5 is the title, field for field: uv (120,120), 24×8, CLUT `0x7CBC`, at
`rec + (3, −1)` — which is `StartActionMenu.TITLE_TAB_OFFSET` **exactly**, from a completely
separate port of the same routine. The texels were already in the world map's `vram.bin`.
The CLUT was not, and neither were fifteen others.

**`EVENT/FRAME.BIN` is not one flat band.** It uploads as three VRAM rects, and the third is
a run of sixteen 16-entry CLUTs at file offset **`0x9000`**: `0x9000 + N·0x20` → VRAM
`(960, 496 + N)`. `overlay_ui_sheet` copied only the 240-row *pixel* band and its docstring
said the last 16 page rows *"differ and are left alone, because nothing the world map draws
reaches them"*. They do not differ — they are simply somewhere else in the file. Extending
the pixel band's row shift would have copied FRAME.BIN row 272, a `0500 0005` pixel checker,
straight over the palettes.

Verified byte-identical, all 16 rows, against the live console VRAM of both settled
world-map savestates. Row 496 is `0x7C3C`, 498 is `0x7CBC`, 501/502 are the menu glove's
lit/shadow pair, 503 is `0x7DFC`.

> **So §1 of the round's handoff — "two honest routes, pick one and say which" (synthesise
> the cream ramp, or find who writes `0x7CBC`) — was a false choice. Nobody writes it: it is
> on the disc, in the file the extractor was already reading, 0x1000 bytes past where it
> stopped.**

⚠️ **And the tab is drawn OPAQUE even though the console's command byte is `0x66`.** On the
PSX a semi-transparent *textured* primitive blends per **texel**: only where the resolved
CLUT halfword sets bit 15 (STP). `0x7CBC` sets STP on entries 14 and 15 alone, and the
"Menu" cell uses indices 0, 1, 2, 3, 4 and 6 — none of them. `WorldMapRenderer` carries
`semi` per *primitive*, which is right for every cel on this screen (one blend byte per
descriptor) and wrong for this one quad: emitting it `semi: true` subtracts the whole tab
and **inverts the picture** — the cream letterforms go black and the dark plate lets the map
through. That is §10.2's lesson one level down: transparency is a property of the CLUT
value, and *whether a primitive blends at all* is a property of which values it reaches.

### 11.3 The map's cursor DOES go blue-grey — and nothing else does

§15.21's "send window to background" is a Formation-screen mechanism, and it was an open
question whether the world map runs it. It does, on the cursor, and on nothing else.

Diffing `round16_menu_open.png` (the console with the START menu up over `ss1`) against
`ss1`'s own framebuffer leaves **83 differing pixels in the whole right half of the screen**
— 66 inside the cursor's 16×16 lit quad, the other 17 the party marker's own idle animation,
which the two captures caught at different phases. The four texel indices that move go

| | settled | menu open |
|---|---|---|
| idx 2 | (239,239,239) | (140,148,165) |
| idx 4 | (99,107,115) | (74,90,99) |
| idx 5 | (123,140,156) | (90,107,115) |
| idx 6 | (181,189,198) | (107,123,140) |

which is CLUT **`0x7849`** at VRAM (144,481) — WLDTEX's copy of FRAME.BIN's `0x7DFC`
blue-grey twin, sitting in the map's own palette row. So it is reachable by §24.2's runtime
descriptor override at `pal = 10`, the same mechanism the "you are here" pin uses at
`pal = 12` (`clut=784B`, visible in `ss1`'s own ordering table). **The cursor's SHADOW keeps
`0x7844`** because its descriptor sets blend bit 3, which vetoes the override — a rule
`WorldMapPrimitives.part_packet` already modelled and that nothing had exercised.

The pins keep pulsing, the name plate stays cream, the war funds, the date and the map do
not change by one pixel. Rendering the port's own two frames back gives the **same 66
pixels and the same four colour pairs**.

⚠️ **A palette number is only meaningful on its own CLUT ROW.** The override moves x and
nothing else. The node-NAME cels sit on row **486**, where slot 0 is the only populated CLUT
in the entire row; applying `pal = 10` there resolves to `0x7989`, sixteen zero halfwords,
and the cel draws **nothing**. It did, for one build of the place list — the refused row
vanished instead of dimming. Row 486 slot 0 is byte-identical to `0x7847`, so the twin
exists; it just is not reachable from that row by an override.

### 11.4 The refused Move row is NOT drawn differently — read, not assumed

The place list painted the refused row (the node you are standing on) at `rgb = 0x404040`,
marked ⚠ as synthesis. It is now drawn like every other row, and that is a reading.

The per-row flag lives in the halfword array at `0x8016E500`, written by the walk — `8` or
`0` from `var[0x267 + n]`, then overwritten with `4` on the party's own row.
**`WORLD.BIN` materialises that address in exactly two places**: `0x80105E20`, which builds
the base for the walk that writes it, and `0x80105FA0`:

```
80105f9c  addu at,at,a1          ; a1 = row * 2
80105fa0  lh   v1,-0x1b00(at)    ; the row's flag
80105fa4  ori  v0,zero,0x4
80105fa8  beq  v1,v0,0x80106040  ; ...and refuse
```

and nothing else — there is no `lui rX,0x8016` anywhere in the overlay and no
`ori ...,0xE500`, so no second alias can reach it. **The flag is a predicate and never a
style: it never reaches the renderer.** The console draws the refused row at full brightness
and simply does not take it, and a port that dims it is inventing feedback the console does
not give.

That also answers half of §33.11's open `var[0x267 + n]`: whatever it *means*, its only
consumer is the `== 4` above, which `8` and `0` fail identically.

### 11.5 Formation opens — and the map still only reports

Row 1 is window 7, whose console handler `FUN_80113748` is the formation mainloop
`FORMATION_SCREEN.md` already ports. `WorldMapScene` gains
`menu_row_chosen(row, window)` alongside `node_entered` and **stops there** — ADR-0117 dec. 8,
the same shape and the same reason. `NavigatorMain.run_world_map` subscribes and turns
window 7 into a mounted `Formation.tscn`.

Three things that shape carries:

- It is **not** `run_formation_view`, which is debug-gated behind `navigator.show_formation`
  and documented as running *"on demand and NEVER on the proof path"*. The world map opening
  Formation is ordinary gameplay and must not inherit a debug gate. It shares the mount
  recipe, not the gate.
- The map is **suspended, not layered under** — §33.7: Formation, Data and Option are
  ordinary blocking calls into `WORLD.BIN` that own the display until they return, not page
  pushes (`0x800BB4F0` never sees them). `WorldMapScene.set_suspended` stops the clock and
  unhandled input together, because `held_direction()` polls `Input` directly and a
  suspended screen that kept its input would steer a cursor nobody can see.
- The menu **closes before the signal fires**, so a subscriber that mounts a screen never
  finds the window still up underneath it.

The signal carries the **entry table's** window id, not the row index — they differ for every
row but 0 (`6/7/11/14/12/5` against `0..5`), and a host that switched on the row would open
the wrong screen for five of six.

### 11.6 The guards

`WorldMapStartMenuTest` 80 → **126**, `WorldMapPrimitivesTest` 4 → **9**,
`WorldMapMountTest` 34 → **53**, `WorldMapPlaceListTest` 29 → **33**. Mutation-seeded, all
three ways: the tab offset `(3,−1)` → `(3,0)` drops 2; deleting the cel-bounds conversion in
`cursor_anchor` drops 3 and names the console packet it missed; `PAL_DEACTIVATED` 10 → 11
prints `7847 -> 784A, want 7847 -> 7849`.

`WorldMapPrimitivesTest`'s new check is the one worth copying: it asserts that backgrounding
the cursor changes **exactly one primitive of the frame**, changes **only its CLUT**, and
leaves the shadow's alone — which is the console's measurement stated as a property rather
than as a colour.

## 12. The town screen, built — and two of its five elements were already in the model

○ on the node the party is standing on, when that node is a town: the location painting,
its subtractive drop shadow, the name plate, and the Bar / Shop / Soldier office list.
`WORLD_MAP_SCREEN.md` §35 is the spec and the round changed none of it — but two of the
five elements turned out not to need building at all, and one number the RE gives had to
be read differently.

### 12.1 The drop shadow is a CEL, and the port has been emitting it since round 13

§35.7 describes the shadow as *"a nine-patch ring of 28 quads"* and stops there. It is
**frame list 11 → cel 15**, which `parse_world_map.py` has extracted all along: 28 parts,
tpage (512,256), CLUT (0,487), blend `0x60` — semi-transparent at abr 2. Drawn at
screen-centred **(−8, 16)** its parts reproduce the console's 28 packets exactly, xy, wh
**and** uv, and that anchor is the *unique* (dx, dy) over −128…128 in both axes that does
so, solved against `world_map_ss4_town_menu_open`'s ordering table.

It had drawn nothing for one reason: `WLDTEX.TM2` never writes the ramp texture. It is a
second TIM inside `WLDCORE.BIN` at `0x800944B4`, and blitting it to the two rects its own
header names — (0,487) and (512,464) — lands **16/16 CLUT and 1152/1152 image byte-exact**
against the console's VRAM. So the port draws the shadow through `cel_quads` like every
other sprite on the screen, and the ramp measures **8 units per pixel** in the render,
which is §35.7's *"≈7.9 units per pixel — one 5-bit step"*.

### 12.2 The node KIND is in a table this port does not read

There are **two** per-node tables in `WLDCORE.BIN` and they are not the same table: the
8-byte drawing record at `0x80094DFC` (§30.1), read since round 13, and a 4-byte record at
`0x80094F54` whose byte 2 is the picture id and byte 3 is the kind (§35.2). Reusing the
drawing record's `tier` bytes is the obvious move and is *nearly* right — it agrees on 37
of 43 nodes. The six it gets wrong are the six **castles**, which it calls kind 0 and the
console calls kind 1, so the reuse ships a game where Lesalia, Riovanes, Igros, Lionel,
Limberry and Zeltennia have no town menu. A spot check on a plains node cannot see it.

### 12.3 Where the picture goes — ADR-0178

All 92 `WLDPIC.BIN` entries land at VRAM (512,256) on the console and are swapped in
place. A static `vram.bin` cannot hold that, so each of the 19 node-reachable pictures
gets an address of its own in the empty `x 0..767, y 0..255` half, and the primitive
carries that slot's tpage/CLUT/uv. The layout is forced by the format: 60×80 halfwords
each, a uv reaches one 128×256-halfword page, so 6 per page and 4 pages.

The extractor **refuses rather than overwrites** and then **reads each picture back
through its own packet** — the blit addresses VRAM in halfwords and the primitive
addresses it in texels, and that is the only check the two agree. Seeded with the uv
doubling removed it reports `picture 2 slot 1: texel (0,0) reads 209 … but the disc says 2`.

### 12.4 Four pixels that make the word

§35.0 lists the name plate ahead of the box's nine `0x66`s, which reads as "the box covers
it". The plate sits at screen y 1..11 and the box's top edge is at y 8 — and the console's
framebuffer has ink at fb y 128 and 129, **on** the box: the descenders of the `g` in
"Magic" and the `y` in "City". Drawing the box last loses exactly those four pixels and
`Gariland Magic City` comes out reading `Gariland Manic Citu`. The plate is drawn with the
glove, over the panel.

### 12.5 A gate that would never have opened

`(node - 1) in gate["nodes"]` is **false** even when the node is on the list.
`JSON.parse_string` returns every number as a `float`, so the gate reads `[9.0, 12.0,
14.0]`, and Array `in` compares variants by type as well as by value — `9 in [9.0]` is
false. Written that way the **Fur shop row never appears**, at Dorter, Warjilis or
Zarghidas, and nothing else on the screen changes to say so. `WorldMapTownTest` drives the
gate both ways — the flag alone, and the node list alone — because only that shows the
`and` is not an `or`.

### 12.6 What is synthesis

The box and the row ink, and both are the synthesis the other two windows already carry.
The console's panel samples tpage `0x0407` = VRAM (448,0) — `WORLD.BIN`'s own uploaded
window art, not in this port's `vram.bin` — and §35.8 could not read where a row's ink sits
because the console rasterises the rows into a scratch page at VRAM (576,256) and blits
them as one rect. So the box is `UIFrame`'s nine-slice and the labels are the project font
at `label_inset_x = 9`. Against the console frame the panel fill, the three row baselines
and the glove all line up; what differs is the chrome — the console's box carries olive
bars inset at top and bottom that `frame.tga`'s nine-slice does not have.

The row **pitch** is *not* synthesis. `FUN_800EC5B8`'s formula belongs to the 18
`WORLD.BIN` window records and this window is not one of them — none is at (−42,8) 76×76,
and the formula lands at (−54,18) where the console is at (−51,22). The repo holds a
savestate **pair** from one driven run, cursor on row 0 and on row 2, and the glove's lit
quad moves (−51,22) → (−52,54): 32 px over two rows, so the pitch is 16 and the 1 px of x
is the bob.

### 12.7 The guards

`WorldMapTownTest` is new at **74**. It asserts the two node tables are distinct and names
the six castles; the 19-vs-16 picture/menu split and the three nodes that have one and not
the other; the shadow as a cel, its extent, and that its texture is actually in `vram.bin`;
the 19 picture slots being distinct and non-blank; and both gates driven both ways.

**Nine world-map tests were in no runner.** `grep WorldMap tests/run_all_tests.sh` returned
nothing before this round — every "the suite is green" claim about this port was a claim
about 409 other tests. All ten are registered and green: 394 assertions.

### 12.8 The walk and the load are ONE press — and they had come apart

Reported from play: *"I have to leave and go back to Gariland to be able to open the town
menu."*

§27.6 watched both halves on the console — *"○ two hops away walked the marker there **and
then loaded the town**"* — and `_advance_travel` had only the first. On arrival it emitted
`node_entered` straight out instead of routing through `_enter_node`, and nothing
subscribes to that signal, so the walk landed and **nothing opened**. The player then had
to press ○ a second time, already standing on the node, to get the page that should have
come with the walk. From the chair that reads as "I have to arrive and then do it again".

**Every static check passed the whole time.** The rows were right, the kind gate was right,
the page built correctly when asked, and `WorldMapTownTest`'s 74 assertions were green —
because all of them ask `rows_for` and `opens_for` questions, and none of them *drives a
traversal*. The arrival branch is scene code and only a moving marker reaches it.

The fix is to route arrival through `_enter_node` rather than restate its branch, so the
two cannot drift again, and to re-resolve the cursor's `hit_node` — the console's cursor
update writes that word every vsync whether or not anything moved, so a stale one is a
divergence and not merely untidy, because the next ○ reads it.

`WorldMapMountTest` 53 → **62**, and the new block walks away to a non-town, walks back,
and asserts the page opens on arrival. Mutation-seeded by restoring the original
`node_entered.emit(n)`: it prints `arriving at a TOWN opens the page, on the same press
that walked: got false, want true`.

A second bug rode along, on the same path and equally invisible to a data test: the
row-confirm `print` used `%#06x`. **GDScript's `%` has no `#` flag** — it throws
`unsupported format character` at RUNTIME, and only when a row is actually taken, so it
survived every build and every static assertion. `WorldMapTownTest` 74 → **80** now drives
`confirm()` through the object rather than only calling `rows_for` on it.

## 13. The panel was the wrong frame — and the word that said so had never been read

Reported by eye: *"The panel also doesn't look right… I think the menu is maybe the wrong
size? What are the margins? Where is the header? How do things open and close?"*

The frame was borrowed. `WorldMapTownPage` drew its box with `WorldMapStartMenu`'s crop —
`frame.tga` (2,2) 29×26, margins 4/4/5/4, the **flat** menu tile — because §35.8 had
recorded the console's box as unrecoverable: it samples tpage `0x0407` = VRAM (448,0), and
`vram.bin` is all zero there. Round 20 (`WORLD_MAP_SCREEN.md` **§37**) found it.

### 13.1 Five slices did not all sample `uv (0,0)`

§35.8 read nine `0x66` rects and five of them at `uv (0,0)` — which cannot draw four
different edges out of one texel region — and the handoff flagged the reading as suspect.
It was suspect, but not because the dump mis-parsed: what it printed as a bare `DR_TPAGE`
is a two-word libgpu **`DR_MODE`**, and the *second* word is a `GP0(E2)` **texture
window**. Six different windows across the nine slices; `uv (0,0)` is the origin of an
8×16 or 16×16 patch that the rect then **tiles**. A word was unread, not mis-read.

With the windows in hand the box stops being mysterious: the lattice is left 8 / right 8 /
top 16 / bottom 16 on a **76×76** box, and §35.8's unexplained *"right 16×44"* is a rect
whose outer 8 texel columns are transparent on all 16 rows — it paints nothing, and the
84-wide `DR_AREA` is only giving it room.

### 13.2 The art is `EVENT/FRAME.BIN`, which this port already decodes

Each of the nine patches matches a rect of FRAME.BIN texel for texel over all 16 rows, and
`tools/parse_frame.py` already bakes that file to `assets/ui/frame.tga` through **palette
0 — which is the console's own CLUT `0x7C3C`**. So `WorldMapTownPage.PANEL_TILES` names
the nine rects and `_panel_texture()` packs them into the 32×48 a `NinePatchRect` wants.
The top and bottom bands come from the banded prototype box at **(218,3)** — the same rect
`UIFrame.STRIPE_SOURCE` already pins — and the middle band from the tall flat box at
**(0,8)**; they are not contiguous, which is why one crop could never have been right.

**The header is the top edge.** Rows 3..11 of the top-edge patch are outline / bevel /
three rows of olive / tan / olive / outline / bevel. The olive bars are frame chrome inside
the nine-patch, not a tenth primitive and not a title tab.

### 13.3 The rows were 3px left and 2px high, and that was measurable all along

§35.8 said the console rasterises the labels into a VRAM scratch strip the port "cannot
read". It cannot read it in *pixel* space — but the strip decodes: `(-34,20) 66×50`,
`uv (0,254)`, which straddles the page wrap. Three ink bands, all starting at **x −30**
(the box origin + 12, not the borrowed +9) with tops at 24 / 40 / 56. `ROW_INK_XY` is
those numbers, and the old expression also subtracted the glove's **X** bob from the
label's **Y**.

### 13.4 The result

`-- --shot=… --menu=town` against `world_map_ss4_town_menu_open`'s framebuffer:

```
   whole screen   61408 / 61440 = 99.95 %
   the panel       6384 /  6384 = 100.00 %      (was: the wrong frame entirely)
   the picture     9600 /  9600 = 100.00 %
   the name plate   891 /   891 = 100.00 %
   the glove        399 /   399 = 100.00 %
```

The 32 remaining pixels are a 3×26 sliver at x 61..63, y 71..96 — the map background left
of the drop shadow, pre-existing and untouched by this round.

Note what 100 % on the panel means for the rows: the port's own FONT.BIN bake comes out
**pixel-identical** to the console's rasterised strip. That was not a goal; it is what
placing it at the measured ink produced.

### 13.5 The name plate — the alarm was measuring the padding

The round-18 handoff warned that **28 of the 43 name cels carry a self-centre of 0 where
Gariland's is 4**, so under a fixed anchor those 28 would sit 4px off, and no savestate
stands on a node from the other group.

The 4px split is real in the cel RECT and absent in the art: every rect is padded to a
multiple of 8 texels, and the two groups are exactly `x = -w/2` and `x = -(w-8)/2`.
Walking the actual texels of all 43 cels, the **ink** centres are one cluster from −3.5 to
+2.0. So the fixed `(−4,0)` anchor is right for every node, and `WorldMapTownTest` now
asserts the spread so a cel-bank change fails instead of 42 names drifting.

(Two readings this does *not* separate, because Gariland's node `screen` is itself
`(−4,0)`: whether the anchor is that constant or the node's own position, and whether the
picture is a screen constant or `node.screen + (−60,−76)`. Both need one driven ○ on a
non-central town — §37.5 names the instrument.)

### 13.6 Open/close: it IS the aperture, and it is still not built

Every constant of this page's glove is `FUN_800EC5B8`'s, byte for byte — lit `uv (168,0)`
CLUT `0x7D7C` opaque, shadow `uv (184,0)` CLUT `0x7DBC` at +2/+2 on `abr 2`,
`x = win.x + bob − 0xC`, row step `<< 4`. And that function's tail is **unconditional**:
`jal FUN_800ec764` then `jal FUN_800ec7b4`, and `FUN_800ec7b4` reads
`world_menu_open_curve @0x801533B8` = `[10,10,60,60,90,90,95,95,100,100,100,100]`. The
`bltz` above skips the *cursor* for row −1, not the scaler. So the town panel opens with
the same centre-out aperture as every other `WORLD.BIN` window — one curve index per
vsync, twelve steps, every coordinate snapped even — and **the port still pops it open**.

> **BUILT — §14.** It is a clip reveal, and so is the picture. The refusal below was the
> right call: the "centre-out scale of the nine-patch" reading was live until §38 caught
> two mid-open frames, and the nine slices turn out never to move at all. Everything from
> here to §13.7 is kept as written — it is the reasoning that made the capture worth
> running.

It is unbuilt on purpose. "The same aperture" does not settle what it LOOKS like here. The
vault's *"a clip reveal, not a geometry scale"* describes a window whose body is one quad
sampling a composited VRAM strip — shrink the quad, inset its uv by the same amount, and it
reads as a clip. This panel has no such strip (its body blit is parked off-screen at
x 1000) and draws nine slices laid out from the element `FUN_800ec7b4` shrinks, so the same
code plausibly produces a centre-out **scale** of the nine-patch with the `DR_AREA` merely
following. `ss3` is before the press and `ss4`/`ss5` are both settled, so nothing in the
repo shows a mid-open town box. Building either reading now would ship a picture nobody has
seen; the capture is twelve vsyncs of a driven ○ and §37.4 names the rig.

### 13.7 The guards

`WorldMapTownTest` 80 → **95**. The frame block is mutation-seeded: point the three
top-band tiles at the old flat crop and four assertions fail, including *"rows 5-7 are ONE
flat olive band across all 16 columns — the header bar"*. Research-side,
`dispatch.py town` 15 → **69**, and it passes on both halves of the pair (`ss3+ss4` row 0,
`ss3+ss5` row 2) — including a replay of the nine slices through their own texture
windows that reproduces the console framebuffer with **zero** wrong pixels.

## 14. The page no longer pops — §38's four animations, and two of them are one instruction

`WORLD_MAP_SCREEN.md` §38 watched the ~30 vsyncs before the settled frame on the console,
per primitive. §13.6 refused to build the aperture because *clip reveal versus geometry
scale* was undecided on this window's geometry and nothing in the repo showed a mid-open
box. There are two such savestates now, and it is a clip reveal — twice, by two different
mechanisms.

### 14.1 What the console does, and on which clock

```
frames  0..8    the picture opens          centre-out CLIP reveal, 5 percents, 2 vsyncs each
frames  0..19   the plate goes black->normal   level += 7, clamped at 128
frames  0..19   the drop shadow fades in       ...the SAME ramp, the same instruction
frames 21..29   the menu opens                 the panel's SCISSOR, 5 percents, 2 vsyncs each
```

Three clocks, not one, and the panel does not start until the ramp has finished. The
close is instant — measured, at primitive level: the panel's last drawn frame is full
size and there is no reverse curve.

### 14.2 The two things that were easy to get wrong

**The divisor is 200.** `FUN_8006B678` loads `0x51EB851F` and shifts the high word right
by **6**; `2**38 / 0x51EB851F == 200`. The same constant with `sra 5` is the familiar
divide-by-100, and reading it that way doubles every width and misses all ten measured
numbers. `WorldMapTownPage.aperture()` is that arithmetic, `& ~3` on the *half* — which
is why the drawn size snaps to a multiple of 8, p=50 gives 56 and not 60, and p=90 gives
104 and not 108.

**The panel's clip is derived from the ELEMENT, not from the box.** The drawn nine-patch
is 76 wide; the console's window element — and therefore its `DR_AREA` — is **84**,
because §37.1's 16-wide right slice needs the room and paints nothing with it. Deriving
the clip from `size()` makes every step ~10 % narrow and finishes 8 px short; that is
exactly what the first build did, and `WorldMapTownPage.PANEL_ELEM_WH` is the fix.

### 14.3 What it cost to build

Almost nothing, because two of the four animations are the same ramp on the same cel rgb.
`plate_quads()` and `shadow_quads()` gained one argument each — the ramp's grey — and the
shadow's fade falls out for free: `abr 2` is `B − F`, so scaling `rgb` scales how much is
subtracted, and at level 0 the quads subtract nothing and the shadow is simply absent.
There is no separate text animation either: the plate is a cel, and *"it starts black"* is
the page opener's `sb zero` on that cel's own rgb.

The panel is a `Control` with `clip_contents` around the nine-patch and the rows — the
engine's scissor. Not a scaled `NinePatchRect`: a centre-out geometry scale would crush
the corner art, and the console never does that.

The transition runs on the same vsync clock as the glove bob (§21.3), stepped from
`WorldMapScene.advance()`. A delta-driven tween would finish the open in a third of the
time on a 144 Hz panel.

### 14.4 Looking at it

`--menu=townopen` renders eleven frames of the transition into one contact sheet, chosen to
straddle every boundary §38 names:

```bash
godot --path . res://assets/scenes/WorldMap.tscn -- \
  --shot=/tmp/town_open.png --fixture=ss1 --zoom=1 --menu=townopen
```

It is a `match` arm of the existing `--menu` switch and a bool flag, so it adds **no**
second `rig_arg` call site. (The rig read the *environment* until #612; ADR-0051 dec. 5
moved it to `--` user args, which cannot leak in from another shell.) `--menu=town` now
*settles* the page before capturing, which is what makes the A/B
below reproducible: without it the capture freezes on whatever frame of §38 the four
warm-up frames happened to reach.

### 14.5 The result

The settled frame is **byte-identical** to §13.4 — the animation changed nothing about
where it lands:

```
   whole screen   61408 / 61440 = 99.95 %
   the panel       6384 /  6384 = 100.00 %
   the picture     9600 /  9600 = 100.00 %
   the name plate   880 /   880 = 100.00 %
   the glove        256 /   256 = 100.00 %
```

### 14.6 The guards

`WorldMapTownTest` 95 → **119**, and the new block is mutation-seeded the way §13.7's was:
make `begin_open()` jump straight to the settled frame — the exact bug this round exists to
fix — and **seven** assertions go red, including *"the picture walks five sizes and no
others"* and *"the panel's clip walks 84×[10,60,90,95,100]/100"*. A guard that only checked
the last frame would have passed on the pop. All ten world-map suites green: **448**
assertions, up from 424. Research-side, `dispatch.py town` 69 → **118**.

### 14.7 What §38 leaves for this port

- **The 21-vsync gap** between the page push and the panel's first frame is measured, not
  mechanised — §38.11 leaves what actually triggers the window open unread. If it turns
  out to be driven by the ramp's own completion, `OPEN_PANEL_DELAY` becomes derived rather
  than a constant.
- **§37.5's anchor** and **§37.4's 4 px `win.y` residual** are both untouched; both need a
  driven ○ on a non-central town, which is a traversal rather than a poke.

## 15. Walking into a town no longer opens its menu — and §27.6 never said it should

Arriving at a town popped the Bar / Shop / Soldier office list open by itself. Two
comments justified it, in `_advance_travel` and in `WorldMapMountTest`, both citing §27.6:
*"○ two hops away walked the marker there **and then loaded the town**."*

**§27.6 says the opposite of what it was cited for.** Same paragraph, four sentences later:
*"the marker never moved, never changed frame list, and the ribbon never grew. **No walk is
reachable from this savestate.**"* Both arms that session watched were ○ presses with no
travel between them. The sentence describes what ○ does; it licenses nothing about arrival.

The disassembly settles it, and it is two different lists:

```
FUN_8008E540   the arrival tick
  0x8008EA34     jal FUN_8008D3C0      <- the ERRANDS list, from type-4 emits
  0x8008EA44     beq a0,-1  -> skip
  0x8008EA4C     blez a0    -> skip     <- a page only if that list came back positive
  0x8008EA94     jal FUN_8006FAF0

FUN_8008D2C8   the Bar / Shop / Soldier office builder
  called from 0x8006CBAC, 0x80070B44, 0x80071B1C — all ○ handlers, and always paired
  with jal FUN_8006FAF0 sixteen instructions later.  The arrival tick never calls it.
```

So the town menu is on the ○ path and on no other. `_advance_travel` now routes to
`_arrive_at`, which emits `node_entered` for a battlefield — the arrival event, which the
console does fire — and does nothing for a town. Standing there and pressing ○ opens it,
through `_confirm` → `_enter_node`, which is the branch that was always right.

### 15.1 §12.8 was a real report, and the fix it got was the wrong one

§12.8 records the play report this auto-open was written for: *"I have to leave and go back
to Gariland to be able to open the town menu."* That is not a complaint about needing a
second press — it is a complaint that **○ on the node you are standing on did nothing**, so
the only way to get the page was to walk away and walk back. Making arrival open the menu
hid that symptom without touching its cause.

So the guard now drives `_confirm` — the real ○ input path — instead of `_enter_node`. The
difference matters: ○ reads `_cursor.hit_node`, and the cursor is free of the party marker
(§21.2), so arriving somewhere does not put the cursor on it. Calling `_enter_node` proves
the branch and misses exactly the thing that was broken. The test parks the cursor on the
node with `WorldMapCursor.rest_at` the way a player does, asserts the hit test finds the
town, and only then presses.

**The guard was asserting the bug.** `WorldMapMountTest._check_arrival_loads_the_node` is
inverted and re-cited, and it drives a real traversal both ways: walk in, assert nothing
opened, park the cursor, press ○, assert the page opens **animated** (§38) rather than
popped. Two seeds, both red:

```
restore the one-line auto-open   -> "arriving at a TOWN opens NOTHING"      66/67
make _confirm() a no-op          -> three assertions, incl. §12.8's own bug 64/67
```

`WorldMapMountTest` 62 → **67**; ten world-map suites **453** assertions, all green.

## 16. "The red glowing icons look too light" — two bugs, and each hid the other

Reported from play. Both halves of the question were right: they *are* drawn with
semi-transparency enabled, and part of them *is* supposed to be opaque.

### 16.1 The blend was per quad; the console's is per texel

`WORLD_MAP_SCREEN.md` §39 has the rule and the measurement. A `0x2E` command byte only
*enables* semi-transparency — the GPU blends a texel only when its own CLUT halfword has
bit 15 set. The pin CLUTs `0x784A` / `0x784B` carry that bit on 3 of 8 used entries (the
outer ring and the drop shadow) and not on the five that make the orange ball.

`WorldMapAssets.clut_levels` had the rule in its own doc comment — *"bit 15 = STP"* — and
then discarded it, returning `w = 1` for every non-zero halfword. `WorldMapRenderer` chose
one material per quad from `prim["semi"]`. So the ball was half-mixed into the map.

The fix keeps one draw. `_per_texel_blend` detects a semi quad whose CLUT is mixed, and
`_palette` then carries the blend factor in the **texture's** alpha — 255 for the written
texels, 128 for the blended ones — with the vertex alpha at 1. Under `MIX` that is exactly
the console's two rules: `F` and `(B + F) / 2`.

⚠️ **Restricted to abr 0, deliberately.** `ADD` and `SUB` have no "write F" at any alpha,
so a mixed CLUT on abr 1/2/3 would need two draws. Nothing on this screen is one, and
`WorldMapPrimitivesTest` asserts the corpus stays that way rather than leaving the gap
silent.

### 16.2 And underneath it, a clamp that ate every brightening

Fixing only the blend moved the pin from 71.5 % to **73.6 %** — almost nothing. The
opaque texels were now written rather than mixed, and still wrong, and by a constant.

§30.6's pulse is `96 + 2c` / `224 − 2c`, so half its period asks for a modulation
**above** `0x80` — a brightening, up to 1.75×. `_modulate` divided by `PSX_ONE` and handed
the result to `Polygon2D.color`, which Godot quantises to 8 bits a channel: everything
over 1.0 clamped to 1.0 and the brightening was simply lost. Both pins in `ss1` carry
`0x90` and `0xB0`; both were being drawn at 1.0×.

`bakes_modulation()` now routes a *brightening* rgb into the palette bake, where the
console's own `min(31, (level * rgb) >> 7)` — clamp included — is exact, and the vertex
colour goes white. Dimming keeps the vertex path: it is exact there, costs no bake, and is
what every other primitive uses.

### 16.3 The result

Against `world_map_ss1_settled_dialog_closed`:

```
                       pin B      pin A      whole screen
   before             71.53 %    64.58 %      99.588 %
   + per-texel        73.61 %    68.06 %      99.603 %
   + modulation       97.92 %    81.25 %      99.718 %
```

Classified per texel, the pins are now essentially exact: pin B **24/24** opaque texels
and 39/41 blended; pin A **38/39** and 23/27. What is left inside pin A's 12×12 box is 22
*background* pixels — texels the pin drops entirely — i.e. a pre-existing map difference,
not the pin.

The town-page A/B is unchanged: panel / picture / plate / glove **100 %**, whole screen
**99.948 %**. Ten world-map suites **460** assertions, all green.

### 16.4 The guard

`WorldMapPrimitivesTest` 9 → **16**, and it asserts the shape of the thing rather than a
percentage: which entries of each pin CLUT blend and which are written, that `0x7847`
reads all-opaque so it stays on the whole-quad path, that the pulse's bright end takes the
bake and its dim end does not, and that no primitive in either fixture is
semi + mixed-CLUT + abr 1/2/3.


## 17. "It didn't progress to the world map" — the walk that was proven was not the walk that ships

The user ran `NavigatorMain.tscn` through the Gariland battle and it stopped there. Nobody
had claimed otherwise: §14–§16 never touched the navigator, and every place C2 is written
down carries the ⚠ above saying the default proof walk is unchanged.

What made the claim *feel* made is that C2's headline is **"the walk enters the screen"**,
and its doc comment — repeated verbatim into `GameNavigator.gd` and
`WorldMapNavigatorTest.gd` — reads:

> *The very first story walk hits one: 1 → 3 → 7 → 9, and group 9 (Gariland) exits to
> `WORLD_MAP`.*

That is true of the **graph**. It was not true of the **walk**, because
`NavigatorMain.STOP_ROOT := 9` asked the planner for a walk bounded at group 9, and a stop
root means stop — the planner's stop-root branch `break`s before it ever consults
`exit_sink`. The sentence and the constant described two different walks and sat four lines
apart.

### 17.1 It was one cause, not two

The obvious decomposition — *(a) does the walk emit a `world_map` action, (b) would
`STOP_ROOT := 9` let it run* — has two answers but **one cause**. (a) is no *because of*
(b). There was nothing to build: `exit_sink`, the planner's sink branch, the runner's
dispatch, `run_world_map`'s mount, and the START-menu → Formation hand-off were all built
and all green. One constant truncated the walk one action short of them.

Measured on the real cold boot, before and after:

```
   before   [NavigatorMain] planned 10 actions for walk 1 → 9   … ends { "kind": "victory" }
   after    [NavigatorMain] planned 11 actions for walk 1 → 0   … ends { "kind": "world_map",
                                                                          "root": 9, "terminal": true }
```

### 17.2 The stale comment that made the report look impossible

`STOP_ROOT`'s own comment said the walk *"ENTER[s] Gariland (grp9, the first battle) and
STOP at its front door — before the deployment/recruitment screen, which the game doesn't
have yet."* The game **does** have it — wayfinder #234 built deployment, and
`_append_battle_actions` plays a battle stop root through in full. So a reader of the file
would have concluded the user could not have reached the end of the battle at all, when in
fact reaching it was correct and the comment was two features out of date. Corrected, along
with the class-doc route (*"chain to Military Academy (group 7) and STOP"*), the
walk-finished print (*"world map OOS"*), and `NavigatorDebugPanel`'s *"restart default
1 → 7"*.

### 17.3 The guards, and why the existing three could not have caught it

`WorldMapNavigatorTest` asserted `plan_actions(1, 9)` (stops — correct) and
`plan_actions(1, 0)` (reaches the map — correct). Both hardcode their bounds. **Between
them sits the only walk a player runs**, and nothing read `NavigatorMain`'s constants, so
the shipped default was the one arm with no assertion on it.

- **`WorldMapNavigatorTest._test_shipped_default_walk_reaches_the_world_map`** (14 → **20**)
  loads `NavigatorMain.gd` and plans from its *own* `START_ROOT`/`STOP_ROOT`. A constant
  that moves moves the guard with it.
- **`NavigatorWorldMapArrivalTest`** (new, **10**) drives the seam the other three faked. C2's
  dispatch test used a `FakeExecutor`; `WorldMapMountTest` builds the `CanvasLayer` itself.
  Neither ever called `NavigatorMain.run_world_map` on a live walk. This seeks the real
  navigator to the **victory beat** — one action *before* the map, because landing straight
  on `world_map` would prove the mount and skip the link this is actually about: that
  finishing Gariland's victory ADVANCES into the map instead of ending the walk, which is
  precisely where the walk used to stop. It then waits for the screen to really mount,
  asserts the runner is in `WORLD_MAP` and the walk has *not* finished, leaves with a real
  `ui_cancel` press, and asserts the walk resumes to `walk_finished` with the screen freed.
  `[[a-mechanism-that-could-explain-it-is-not-evidence-it-did]]` — five built pieces are not
  evidence anything runs them in series. The live log line it now produces:
  `[NavigatorMain] WORLD MAP after group 9`.

  The battles themselves are still skipped here; `NavigatorGarilandVictoryTest` owns the
  combat pipeline and keeps its own `stop_root = 9` bound.

Both were **seeded with the bug first**: at `STOP_ROOT := 9` the shipped-default arm fails
4 assertions and the arrival test fails at its first (`0/1` — it cannot even find an action
to seek to). Restored, **20/20** and **10/10**.

### 17.4 Baselines

`dispatch.py check` **310/310**, `dispatch.py town` **118/118**, town A/B panel / picture /
plate / glove **100 %** and whole screen **99.948 %** — untouched (this round is GDScript
only; it moves no pixel). Ten world-map suites **460 → 466** assertions, all green (the +6 is the new
shipped-default arm), plus `NavigatorWorldMapArrivalTest`'s 10 as an eleventh suite.

One incidental find: `WorldMapMountTest`'s documented `--quit-after 12` exits **before** its
verdict prints — 0 verdict lines at 12 and at 40, 67/67 at 90. A missing verdict reads as a
pass in any sweep that greps for `FAIL`, so the documented budget is now 120, with the
measurement written next to it.


## 18. The arrival was a cut — a cross-fade through black, deliberately unfaithful

§17 got the walk onto the map; it arrived in a single frame. The console fades, so the port
now does too — **explicitly not to spec**, and marked as such so a later reader does not
mistake it for measured work.

```
   battlefield  ── fade to black (0.45 s, the inherited FadeLayer rect) ──▶ black
   black        ── mount the map underneath, its own cover opaque ───────▶ black
   black        ── fade the cover out (0.45 s) ────────────────────────────▶ map
```

`WORLD_MAP_FADE_SECONDS` is one constant and both tweens are linear. When the real ramp is
read off `WLDCORE` — §38's town-page work is the pattern, four animations on three clocks —
this is what it replaces.

### 18.1 The cover cannot be the fade rect that already exists

`ScenarioPlayerScene`'s `FadeLayer` is `layer = 100`, and `run_world_map` mounts the map at
`layer = 100` as well. Same layer, and the map's layer joins the tree *later*, so it draws
**on top of** the rect that is supposed to hide it. Each surface fades under its own cover:
the battlefield under the inherited rect, the map under a `ColorRect` added after the view
inside the map's own layer.

### 18.2 The fade opened a dropped-signal hang, and the first test run found it

`run_world_map` awaits `view.dismissed` *after* the fade. A ✕ landing mid-fade emits
`dismissed` with nothing yet connected, the signal is dropped, and the walk hangs on a
screen that has already asked to close. The first run of the arrival test reproduced it
exactly — the map mounted, and no verdict ever printed.

Fixed by `set_suspended(true)` across the fade-in, which is also the right behaviour on its
own terms: a screen the player cannot see yet must not act on a press. The test presses
`ui_cancel` on a **loop** rather than once, because a single press fired at first sighting
is correctly swallowed by the suspend — and a test that hangs instead of failing is worth
less than no test.

### 18.3 The guard

`NavigatorWorldMapArrivalTest` 10 → **14**. Asserting a cover *exists* would pass on a cover
that lived one frame and snapped, which looks exactly like the cut this replaces — so it
samples the cover's alpha every frame and requires a monotonic descent through **≥ 5**
intermediate values, plus the cover being freed afterwards.

Direction-tested both ways: at `WORLD_MAP_FADE_SECONDS := 0.0` it fails with *"1 sampled"*
(13/14); restored, 14/14.

Everything in §17.4 still holds; `NavigatorGarilandVictoryTest` and
`NavigatorCommandModeProofTest` re-run green, as do `NavigatorRebootFadeTest` and
`NavigatorCombatRevealTest` — the two other users of the inherited fade rect.

