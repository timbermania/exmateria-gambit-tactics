# Sprite palette is runtime-applied via shader, BODY layer only

FFT renders unit sprites as **paletted indexed-color** images at the PSX
hardware level — every `.SPR` file holds a 4bpp index texture plus a 256-color
palette table (16 rows × 16 colors), and per-unit color variants
(Yellow / Black / Red Chocobo, Goblin variants, Dragon variants, future status
effects, future team colors) are **palette-row swaps on the same SPR**, not
separate sprites. The palette row to use is per-job ROM data
(`jobs.json.male_palette`, parsed from SCUS_942.21 byte 0x2E — same field
TacticsG calls `monster_palette_id`).

Today's `extract_spr.py` pre-bakes RGBA — one fixed palette per output `.tga`
(body region uses palette row 0; portrait region uses row 8 via the
`--portrait-palette` extractor flag). The runtime can't switch palettes,
so all three Chocobo variant jobs render identically (always palette row 0).

We move to **runtime palette swap via shader**, scoped to the BODY layer,
extending an architectural pattern the project already uses for map rendering
(`assets/shaders/indexed_color.gdshader`). This is the same direction TacticsG
takes (`set_sprite_palette(job_data.monster_palette_id)` at `unit.gd:1509`),
though TacticsG re-bakes textures per palette change while ours stays
fully shader-side.

## Status

accepted

## Decision

The eight rules below were decided by this ADR but were only ever stated as a
flat bullet list. They are numbered here on 2026-08-28 so `ADR-0022 dec. N` is a
checkable citation; the anchor scanner read **zero** decision anchors on this
file before the numbering, so no existing citation could break. No word is
removed and no rule is retired by the numbering. Amendment 1 grades each of the
eight against the shipped code — **two of them no longer describe the tree.**

1. **Runtime palette swap in the unit shader** (Option B from the grill, not
   Option A pre-baked variants nor Option C texture re-bake). Per-frame palette
   selection becomes a uniform; no asset bloat for variants; palette animation
   (water tint, status pulses, transitions) is enabled as future capability
   essentially for free.
2. **BODY layer only**. WEAPON and EFFECT layers stay RGBA-baked. WEAPON
   palette is per-equipped-weapon (already a parameter the layer takes via
   `wep1_v_offset_pixels`); EFFECT palette is per-keyframe in effect data.
   Neither has a per-unit palette-row concern.
3. **Sprite-specific shader idiom, not reuse of `indexed_color.gdshader`**.
   The unit shader has its own concerns (layered compositing TYPE1/WEP1/EFF1,
   per-tile inversions/reversions, camera variants); forcing the map's idiom
   into it would be awkward. Same data-shape, different shader body.
4. **Two-file on-disk format per BODY sprite**:
   `NN.tga` (indexed grayscale, indices 0-15 scaled to 0-255 for debug
   visibility) + `NN.palette.tga` (16×16 RGBA palette table). No JSON parse
   at runtime; Godot imports both natively as samplers.
5. **Two separate palette-row uniforms — body and portrait**. The current
   extractor uses different palette rows per region (body=0, portrait=8 — a
   long-standing FFT convention for humanoid sprites). The new shaders preserve
   this split:
   - BODY shader: `body_palette_row: int` uniform, default 0. Set per-unit
     from `jobs.json.male_palette` for monster jobs.
   - Portrait shader: `portrait_palette_row: int` uniform, default 8. No
     per-unit / per-job override yet.
6. **Monster portrait color variants are known-broken in v1**. All three
   Chocobo variants render the same portrait region (always row 8). This
   matches TacticsG's status — they have a stubbed `portrait_palette_id: int = 0`
   field that's never assigned anywhere. No reference implementation solves
   this; deferring is the honest choice. Future v2: ROM research + per-monster
   portrait palette override if FFT actually does differentiate.
7. **Field renames in jobs.json**:
   `male_palette` → `body_palette_row` (the field has nothing to do with
   males; it's the monster's per-job sprite palette row index).
   `male_portrait` → `body_portrait_sprite_id` for consistency. The parser
   comment block updates accordingly.
8. **Vocabulary lock-in** (CONTEXT.md updates inline with this ADR):
   **"Sprite palette"** — the PSX-native indexed-color table baked into a SPR
   (16 rows × 16 colors). **"Palette row"** — which row to apply at runtime.
   Distinct from the existing `PaletteSubsystem` palette (effects-system RGB
   tint, ADR-0011/0014) and "font palette" (UI text colors).

## Considered options

- **Option A — pre-bake palette variants offline** (rejected). Each monster
  sprite extracted at every plausible palette row (0-15), producing e.g.
  `86_pal0.tga`, `86_pal1.tga`. Runtime loads the variant by `job.male_palette`.
  Simple runtime; bloats `textures/` dir; design doesn't extend to status
  effects, team colors, or palette animation without exponential variant
  growth.
- **Option C — TacticsG-style hybrid: re-bake texture per palette change**
  (rejected). Stays RGBA on disk; runtime re-creates the texture with palette
  baked in on each palette-id change. Simpler shader (no indexing). Cost: texture
  allocation/free per palette change; per-frame palette animation requires
  re-baking every frame (defeats the point). Picks the worst of both worlds
  for our use case.
- **Reuse `indexed_color.gdshader` for unit sprites** (rejected). The map
  shader's idiom (single sampler, per-vertex `COLOR.r` palette_id, GaneshaDx-
  style lighting) fights the unit shader's existing concerns (multi-sampler
  compositing, per-tile flips, camera variant logic). Same data shape, but
  a sprite-specific shader body avoids the forced fit.
- **Single shared `palette_row` for body + portrait** (rejected). Doesn't
  work — humanoid SPRs use palette row 0 for body and row 8 for portrait by
  convention. Forcing one row would break humanoid portraits to fix monster
  bodies.
- **Two shared fields like TacticsG** (`portrait_palette_id` on Unit, no
  per-job source). Adopted in shape but with explicit per-job sourcing for
  body and explicit known-limitation note for portrait. Avoids TacticsG's
  stub-that-does-nothing trap.

## Consequences

- `extract_spr.py` changes shape: outputs **two TGAs per body sprite** (indexed
  + palette) instead of one pre-baked RGBA TGA. ~156 numeric SPRs × 2 = 312
  files in `assets/sprites/textures/`. WEP / OTHER unchanged.
- The unit body shader (`assets/shaders/unit.gdshader`) gains a new sampler
  (`palette_texture`) and a uniform (`body_palette_row: int`). The BODY-sample
  path changes from `texture(type1_tex, uv)` to:
  `texture(palette_texture, vec2(texture(indexed_texture, uv).r * 15.0 / 15.0, body_palette_row / 15.0))`
  (or equivalent — actual UV math depends on palette texture dimensions).
- The portrait shader (`assets/shaders/unit_portrait_3d.gdshader`) gains the
  same two extras and uses `portrait_palette_row` instead.
- `Unit.gd` gains `body_palette_row: int = 0` and `portrait_palette_row: int = 8`
  properties. The body setter pushes the uniform to the body material; the
  portrait setter pushes to the portrait material.
- `JobDatabase` or wherever `change_job` lives reads
  `jobs.json[job_id].body_palette_row` for monster jobs and sets
  `unit.body_palette_row`. Humanoid jobs leave it at 0.
- `tools/extract_fft_data.py` renames the output keys
  (`male_palette` → `body_palette_row`, `male_portrait` → `body_portrait_sprite_id`).
  All consumers of `jobs.json` get a one-time grep+replace.
- All existing roster JSON / saved-data that referenced `male_palette` by
  field name (none currently, but worth checking) updates.
- The current `--portrait-palette` CLI flag on `extract_spr.py` is retired —
  no longer relevant; portrait row is a runtime uniform now.
- Palette animation (FFT water tint, status effect pulses) becomes a
  conceivable v3 feature without further architectural change — animate
  `body_palette_row` over time, or add a `palette_animation_offset` uniform.

## Migration

1. **Extractor rewrite**. `extract_spr.py` outputs indexed.tga + palette.tga
   per BODY sprite. Verify size and structure (256×488 indexed, 16×16 RGBA
   palette) against a few known sprites (0x60 Male Squire body looks right
   after shader runs at body_palette_row=0; 0x86 Chocobo body at row 0/1/2
   for Yellow/Black/Red).
2. **Body shader rewrite**. `unit.gdshader` BODY-sample path: add
   `indexed_texture` + `palette_texture` samplers + `body_palette_row` uniform.
   Preserve existing inversions/reversions/compositing on the post-palette-lookup
   RGBA.
3. **Portrait shader rewrite**. `unit_portrait_3d.gdshader`: same shape with
   `portrait_palette_row` uniform.
4. **`Unit.gd` properties**. Add `body_palette_row` + `portrait_palette_row`
   setters that push uniforms.
5. **Job application**. `change_job` reads `body_palette_row` from jobs.json
   for monster jobs; sets `unit.body_palette_row`.
6. **jobs.json field rename** + parser update. `male_palette` →
   `body_palette_row`, `male_portrait` → `body_portrait_sprite_id`. Re-emit
   jobs.json via `tools/extract_fft_data.py`.
7. **CONTEXT.md vocabulary entries** — "Sprite palette" + "Palette row"
   under the Sprite layers cluster; disambiguation note pointing at the
   other two existing "palette" usages (PaletteSubsystem RGB tint, UI font
   palette).
8. **Wipe textures + re-extract + Godot --import** as in the prior sprite
   alignment fix.
9. **Visual verification** in ResolutionViewerScene: Yellow / Black / Red
   Chocobo jobs render distinct body colors; humanoid sprites unchanged from
   pre-migration appearance.

Out of scope for v1, tracked as follow-ups:

- **Status effect palette overrides** (crystal, treasure, zombie, petrify).
  Add `body_palette_row_override: int = -1` as a TacticsG-style override
  channel; ADR + implementation when the first concrete need lands.
- **Monster portrait color variants** (Black Chocobo's portrait should look
  black, not yellow). Requires ROM research — does FFT actually differentiate?
  If yes, add per-job `portrait_palette_row` source.
- **Palette animation** (FFT water tint, smooth transitions, status pulses).
  Animate the uniforms over time; trivial once the per-frame infrastructure
  is in place.

## Amendment 1 — "BODY layer only" is not what shipped, and the humanoid row is not 0

Measured 2026-08-28 against the tree. Two of the eight decisions no longer
describe the code; one Consequence is simply false; the rest hold. Nothing here
retires a decision — it records where the tree went and what now holds the live
answer.

### What is current, per decision

| Decision | Status | Where the live answer is |
| --- | --- | --- |
| dec. 1 | **holds**, location noun stale | uniforms and paletted sampling live in `assets/shaders/unit_sprite_body.gdshaderinc`, not in `unit.gdshader` — that file is now a 4 KB shell that `#include`s it (`unit.gdshader:32`) |
| dec. 2 | **superseded in code** | all three layers are paletted: `type1_palette`/`body_palette_row` (`:640`/`:644`), `wep1_palette`/`wep1_palette_row` (`:652`/`:656`), `eff1_palette`/`eff1_palette_row` (`:657`/`:661`) |
| dec. 3 | **holds** | no unit shader includes or reuses `indexed_color.gdshader`; it is cited only as a convention to match (`unit_sprite_body.gdshaderinc:898`) |
| dec. 4 | **holds** | `extract_spr_indexed` writes the pair (`extract_spr.py:453-454`), named `{sid:02X}.tga` + `{sid:02X}.palette.tga` by `extract_all_sprites.py:71-77` |
| dec. 5 | **holds on the uniforms, superseded on the body source** | defaults are exactly as written (`body_palette_row = 0`, `portrait_palette_row = 8`); the row's *source* is now the two-axis `SpritePaletteResolver.resolve_body_palette_row` |
| dec. 6 | **holds, and did not become the stub it feared** | zero GDScript in the tree assigns `portrait_palette_row` — the uniform keeps its default 8 |
| dec. 7 | **holds** | `tools/extract_fft_data.py:293-294` emits `body_portrait_sprite_id` / `body_palette_row` |
| dec. 8 | **holds** | "Sprite palette" / "Palette row" are in `CONTEXT.md` |

### Decision 2 is superseded, and its stated reason is the thing that was wrong

The ADR scoped the paletted path to BODY on the ground that "Neither
[WEAPON nor EFFECT] has a per-unit palette-row concern." The shipped shader
carries a palette sampler **and** a row uniform for all three layers, and the
comment above them names the source the ADR did not know about: the row uniforms
"come from BATTLE.BIN's per-item table at `0x2d3e4` (parsed into
`weapon_graphic_data.json`) — X nibble drives `wep1_palette_row`, Y nibble drives
`eff1_palette_row`" (`unit_sprite_body.gdshaderinc` above `:652`). So the concern
is real and it is **per-equipped-item**, which is precisely the axis dec. 2 named
for WEAPON before concluding it needed no row.

The pattern also travelled well past the unit sprite. Every one of these cites
this ADR as its source and none of them is a BODY layer:

- **WEP1 / EFF1** — the extension above (`extract_spr.py`'s `extract_wep_spr`).
- **TRAP1** — `effect_particle_stp.gdshaderinc:33` ("ADR-0022 indexed-texture
  pattern, extended to TRAP1"); `TrapEffect.gd:254` loads the 16×16 sidecar.
- **Projectiles** — `Projectile3D.gd:222`/`:641` load `WEP1.palette.tga` and set
  `palette_texture`.
- **Range-tile overlays** — `tile_overlay.gdshaderinc:8`/`:13`.
- **Event sprites (EVTCHR)** — `tools/bake_evtchr_textures.py:4`,
  `tools/event_asset_slicing.py:11` (which pins the index packing: `INDEX_SCALE
  = 17`, so a 4-bit index becomes `index * 17` = 0..255, matching dec. 4's
  "indices 0-15 scaled to 0-255").

Read as "the BODY layer is where this starts", dec. 2 is a migration order and
it held. Read as a standing scope limit — which is how it is written — it is
superseded. **Not resolved here:** whether the intended reading was scope or
sequence. The bullet's own justification argues scope, and the code contradicts
the justification, not just the boundary.

### The humanoid row is no longer 0

Decision 5 says the body row is "set per-unit from `jobs.json.male_palette` for
monster jobs", and the Consequences add "Humanoid jobs leave it at 0." The
shipped rule is two-axis (`SpritePaletteResolver.resolve_body_palette_row:80`,
called from `ScenarioPlayerScene:786`):

- **Monster** → the JOB's `body_palette_row` (SCUS `0x2E`), and the ENTD
  `palette` byte is **ignored**. Ground truth is real PSX: scenario-6 unit
  `0x8B` is job `0x5E` and renders Yellow despite `palette: 2`.
- **Human / named** → the **ENTD slot's `palette` byte**, clamped to the rows
  the resolved SPR actually authored, read from the bake-time manifest
  `assets/sprites/populated_rows.json` (`tools/bake_populated_rows.py`).
  Generics author rows 0-4 so Blue=0 / Red=2 pass through; Delita's SPR `0x05`
  authors only rows {0,1}, so a stale byte of 2 clamps to 0 rather than sampling
  an all-black row. An unknown sprite does not clamp at all.

Both axes are pinned by `tests/ResolveBodyPaletteRowTest.gd`. The older V14 rule
(`unit.body_palette_row = slot["palette"]` written directly at spawn) is still
described in `tests/ScenarioPaletteResolutionTest.gd`'s docstring; its chapel
fixture is all-human with `palette: 0`, so the test still passes under the
two-axis rule and the docstring's *mechanism* sentence is stale even though its
*expected values* are right.

### One Consequence is false: the extractor flag was never retired

"The current `--portrait-palette` CLI flag on `extract_spr.py` is retired — no
longer relevant; portrait row is a runtime uniform now." It is still declared
(`extract_all_sprites.py:213`, default 8), still threaded through
`extract_one` (`:101`), and `extract_spr` still bakes it into RGBA output
(`extract_spr.py:502`, `:516` via `decode_portrait_rows`'s
`portrait_palette_offset`). What is true is narrower: the flag no longer reaches
the **body** path — `extract_body_sprite` (`:71-77`) calls `extract_spr_indexed`
with no palette argument — so it only reaches the system-SPR branch
(`WEP.SPR` / `OTHER.SPR`), where the decision it implements does not apply.

### The uniform names in the Consequences never existed

The Consequences predict a `palette_texture` sampler and an `indexed_texture`
sampler on the unit shader. Neither name is on the unit path: the body samplers
are `type1_tex` + `type1_palette`, and the portrait's are `sprite_texture` +
`sprite_palette` (`unit_portrait_3d.gdshader:12-13`). `palette_texture` *is* a
live uniform name — on the **effect and projectile** paths
(`EngineFoldCompositor.gd:196`, `Projectile3D.gd:232`) — so grepping this ADR's
noun lands a reader on the wrong subsystem.

### On mechanizing this ADR

A text guard is possible and cheap for the parts that are file-shaped: assert
that every `.tga` under `assets/sprites/textures/` matching `^[0-9A-F]{2}\.tga$`
has a `*.palette.tga` sibling (dec. 4), that no emitter writes `male_palette` /
`male_portrait` as a **jobs.json key** (dec. 7), and that `unit_portrait_3d`
still declares `portrait_palette_row` with default 8 (dec. 5). Two of the eight
are not mechanizable as written: dec. 2 because the code deliberately violates
it, and dec. 1/3 because "the unit shader has its own idiom" is a judgement, not
a predicate. **The one worth building is the dec. 4 sibling check** — it is the
only rule here whose breakage is silent (a missing palette sidecar renders as a
transparent sprite, and `UIPortrait.gd:386` explicitly documents that
non-fatal path). Note that this cannot run in a checkout without the
ROM-derived assets populated: `assets/sprites/textures/` is gitignored and is
empty in this documentation worktree, so the guard needs the same
asset-presence skip the other extraction-dependent checks use.
