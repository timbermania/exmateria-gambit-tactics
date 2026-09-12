# Sprite stretch is a per-taxonomy billboard-width PAR layered on the shared anchor

ADR-0036 split world PAR into two clip-space patterns: **Pattern 1**
(full-stretch — every vertex's `clip.x` PAR'd, used by the map and tile
overlays) and **Pattern 2** (anchor-only — the sprite's *anchor* tracks the
PAR'd map, but the billboard offset is added un-stretched so the sprite art
keeps native PSX pixel aspect, used by units / particles / projectiles /
shadows). It explicitly declined a billboard-width stretch:

> Speculative `par_billboard` is also not added: no content type wants
> stretched billboard width.

The floating tile cursor (ADR rendered like a sprite, two-pass STP, billboard)
is the first counterexample. As a Pattern-2 sprite it renders at native width,
and against the PAR-stretched map it reads **too thin** — the dagger wants to be
stretched horizontally to match the world's 1.25 feel. But the fix can't be
"stretch all sprites": ADR-0036 deliberately keeps **unit** sprite art native
("unit sprites at the 1.25 non-integer stretch looked subtly worse"). So the
cursor wants stretch *that units must not be forced to share*.

The clean split is the one ADR-0036 already found between *position* and
*shape*: keep the **anchor** on the shared `psx_par` (so every sprite still
tracks the map — that decision is unchanged and is what prevents tile drift),
and make the **billboard-offset multiplier** — hardcoded `1.0` in every
Pattern-2 shader today — a per-taxonomy value.

## Status

Accepted (2026-06-14). Supersedes ADR-0036's "no content type wants stretched
billboard width" and its decision not to add a billboard-width uniform. Leaves
ADR-0036's Pattern 1, the anchor-tracking behavior, and the World/UI PAR
channels unchanged.

## Decision

**Each Pattern-2 sprite gets the shared World-PAR anchor plus its taxonomy's own
horizontal width stretch.** The single Pattern-2 line

```glsl
par_clip.x = vertex_clip.x + anchor_clip.x * (psx_par - 1.0);   // offset × 1.0
```

becomes

```glsl
par_clip.x = anchor_clip.x * psx_par + (vertex_clip.x - anchor_clip.x) * <taxonomy>_stretch;
```

1. **The anchor always uses the shared `psx_par`.** The sprite tracks the
   PAR-stretched map exactly as before — no drift, regardless of stretch value.
   Stretch is purely the *width* of the art around that anchor.
2. **Three taxonomy globals**, each `float` default `1.0` (native art — the
   ADR-0036 "sprites don't stretch" default is preserved; nothing changes until a
   scrub moves it):
   - `psx_cursor_stretch` — the tile cursor (`tile_cursor.gdshaderinc`).
   - `psx_unit_stretch` — unit body sprites (`unit.gdshader`).
   - `psx_fx_stretch` — everything else: effect particles, projectiles, shadow
     blobs, callback meshes.
3. **One global per taxonomy because the buckets must stretch independently** —
   the cursor can stretch while units stay native, which a single shared global
   could not express. If a bucket later needs to subdivide (a shadow that
   shouldn't track the FX stretch), split it then — the same way World and UI PAR
   are split.
4. **Runtime state lives in `PSXDisplay`, mirroring `live_par` / `live_ui_par`.**
   `live_cursor_stretch` / `live_unit_stretch` / `live_fx_stretch` each write
   their `psx_*_stretch` global and emit a `*_changed` signal. `DisplayDebugPanel`
   hosts three scrubs next to the World PAR scrub (sprite stretch is world-domain;
   UI PAR stays in `UIDisplayDebugPanel`).
5. **Naming.** Three distinct PAR axes now exist: **World PAR** (`psx_par` —
   Pattern-1 full-stretch + Pattern-2 anchor tracking), **UI PAR**
   (`live_ui_par` — UI mesh-width), and **Sprite stretch** (the per-taxonomy
   billboard-width family above).

## Considered options

- **Per-taxonomy stretch global, shared anchor (chosen).** Pays three new
  globals + channels + scrubs for independent control with the map-tracking
  anchor preserved and `1.0` defaults that change nothing until opted in.
- **One shared sprite-stretch global (rejected).** Simplest ("works like
  `psx_par`"), but couples cursor and units — scrubbing it stretches unit art,
  which ADR-0036 found looks worse. The whole point of the request is that the
  cursor stretches and units don't.
- **Cursor uses Pattern 1 (rejected).** Multiplying the cursor's final `clip.x`
  by `psx_par` would stretch its width *and* track the map — but it ties the
  cursor's stretch to the world value (can't tune it apart) and offers no path
  to stretch units independently. Pattern-2-plus-stretch generalizes cleanly;
  Pattern 1 is just its special case where width-stretch == anchor-stretch.
- **Per-material `stretch` uniform on each shader (rejected).** Works for the
  cursor's two materials but doesn't generalize to units/particles and breaks
  the "one runtime channel you scrub from one place" model that `live_par` /
  `live_ui_par` established. The global+channel form is the consistent shape.
- **World-space / node X-scale on the mesh (rejected).** Scaling the quad's X in
  object or world space leaks PAR into world coordinates — the exact thing
  ADR-0036's implementation invariant forbids ("never on `VERTEX` in object
  space"). PAR stays a post-MVP clip-space multiply.

## Consequences

- **Three new `[shader_globals]`** (`psx_cursor_stretch`, `psx_unit_stretch`,
  `psx_fx_stretch`, all default `1.0`), three `PSXDisplay` channels + signals,
  three `DisplayDebugPanel` scrubs. Default `1.0` everywhere = zero visual change
  until a scrub moves it.
- **GTE/OT depth untouched.** Like ADR-0036, only `clip.x` is multiplied; depth
  (`c.z / c.w`) is unaffected.
- **Shadows live in the Effects bucket**, not Unit — a shadow blob stretches
  with `psx_fx_stretch`, not with its unit's `psx_unit_stretch`. Revisit if a
  stretched unit over a native shadow (or vice-versa) reads wrong; the split
  escape hatch applies.
- **The cursor's interim per-material `cursor_par` uniform is removed** — it
  drove the *anchor* (wrong) and seeded from `live_par`; the cursor now reads the
  shared `psx_par` anchor + `psx_cursor_stretch` width like every other sprite.
- **CONTEXT.md gains a `Sprite stretch` term** in the `Display and pixel aspect`
  cluster, naming the three PAR axes distinctly.

## Amendment (2026-08-28) — the model is built and its formula is now one shared line, but two of the three buckets have lost a member the Decision names: the shadow left for Pattern 1 with no ADR, and the cursor's own outline pass reads the FX global

_Audit pass, 2026-08-28. The five Decision items above were unnumbered bullets
until this pass; numbering them is additive (this ADR had zero decision anchors
and zero `ADR-0044 dec. N` citations before, tree-wide), and every item below
grades against the code and tests, not against the ADRs that cite this one._

### What is current, per decision

| Dec. | Rule as written | Holds? | What the tree says |
|---|---|---|---|
| 1 | The anchor always uses the shared `psx_par`; stretch is purely the width around it | **holds** | `psx_par_anchor` at `addons/exmateria_platform/pixel_aspect/psx_par.gdshaderinc:66-68` is byte-for-byte the Decision's second code block, `stretch` in the `<taxonomy>_stretch` slot. Every Pattern-2 mesh calls it; none re-derives the anchor. |
| 2 | Three taxonomy globals, each `float` default `1.0` | **holds for the globals, MOVED for the roster** | `project.godot [shader_globals]` declares `psx_cursor_stretch` / `psx_unit_stretch` / `psx_fx_stretch`, all `{"type": "float", "value": 1.0}`. The membership sentence under each has drifted — see "The roster is not what it was" below. |
| 3 | One global per taxonomy, because the buckets must stretch independently | **holds** | Three globals, three independent Tune slugs, three independent `_apply_*`. The escape hatch it offers ("if a bucket later needs to subdivide … split it then") was never exercised as a split — the shadow left the bucket by changing *pattern*, not by gaining a fourth global. |
| 4 | Runtime state in `PSXDisplay` — three channels + three signals, three `DisplayDebugPanel` scrubs | **half: state holds, the scrub host is DELETED** | `live_cursor_stretch` / `live_unit_stretch` / `live_fx_stretch` at `PSXDisplay.gd:198/219/240` with `*_changed` at `:286-288`. But `DisplayDebugPanel` no longer exists (deleted by ADR-0151, `bb5f7fefa`); the three scrubs are now generated Tunables cards, bound as `render.psx_*_stretch` at `PSXDisplay.gd:80/83/86` with the same clamped 0.5–2.0 spinbox hint `psx_par` uses (ADR-0068). Nothing in shipped code writes a `live_*_stretch` directly — the only writer tree-wide is `tests/TunePortTest.gd:165`. |
| 5 | Naming: World PAR / UI PAR / Sprite stretch | **holds** | `docs/context/28-display-and-pixel-aspect.md:132` carries the `Sprite stretch` term naming all three axes, with an `_Avoid_` line against conflating it with World PAR. |

### The Decision's formula is now one shared line, not a per-shader copy

Dec. 1's code block is no longer hand-inlined per shader. ADR-0060 made
`psx_par.gdshaderinc` the single home for both PAR patterns and gave the
Pattern-2 helper this ADR's third argument:
`psx_par_anchor(vec4 vertex_clip, vec4 anchor_clip, float stretch)`. Eight call
sites read it; `tools/check_par_shaders.py` (`tests/run_all_tests.sh:330`) fails
the build if a `POSITION`-writing battle shader skips the seam. That is a
strengthening of dec. 1, not a departure from it — but it means the rule's live
home is ADR-0060's guard, which does not cite this ADR for the pattern, only for
the `stretch` argument.

The three-surface wiring *is* guarded here: `tools/check_sprite_stretch_globals.py`
(`tests/run_all_tests.sh:636`) asserts each of the three names exists as a
`PSXDisplay` setter, a `project.godot [shader_globals]` entry, and a shader
`global uniform float`. Run this pass: `OK: all three sprite-stretch channels
wired setter+globals+shader (ADR-0044).`, rc 0. What it cannot see is *which*
mesh reads which global — the roster below.

### The roster is not what it was

Dec. 2 names four members for `psx_fx_stretch`: "effect particles, projectiles,
shadow blobs, callback meshes". Measured across every `psx_par_anchor` call site:

| Mesh | Third argument today | Dec. 2 says |
|---|---|---|
| `assets/shaders/unit.gdshader:73`, `unit_additive.gdshader:70` | `psx_unit_stretch` | Unit ✓ |
| `addons/exmateria_battlefield/cursor/tile_cursor.gdshaderinc:64` | `psx_cursor_stretch` | Cursor ✓ |
| `assets/shaders/effect_particle_stp.gdshaderinc:120` | `psx_fx_stretch` | Effects ✓ |
| `assets/shaders/projectile_sprite.gdshader:80` | `psx_fx_stretch` | Effects ✓ |
| `addons/exmateria_battlefield/cursor/cursor_fold.gdshaderinc:50` | `psx_fx_stretch` | **the cursor's own STP outline, on the FX global** |
| `assets/shaders/projectile_vertex_color.gdshader:30` | literal `1.0` | a projectile, in **no** bucket |
| `assets/shaders/trap_charge_line.gdshader:17` | literal `1.0` | a callback-ish mesh, in **no** bucket |
| `assets/shaders/shadow_blob.gdshader:71` | **not Pattern 2** — `psx_par_full` | "shadow blobs" ✗ |

**The cursor's two passes are in two different taxonomies.** The dagger is one
sprite drawn twice: the opaque STP=0 body as surface 0 wearing
`tile_cursor_opaque.tres` → `tile_cursor.gdshaderinc` → `psx_cursor_stretch`
(`TileCursor.gd:137-148`), and the STP=1 outline as a direct compositor-fold
billboard → `cursor_fold.gdshaderinc` → `psx_fx_stretch`. The outline took the
FX global when it became a fold node (`542f418bd`, 2026-07-28, ADR-0074 ④c) —
after this ADR shipped. Both defaults are `1.0`, so today they agree and nothing
looks wrong. The moment anyone scrubs `psx_cursor_stretch` — the one knob this
ADR was written to create, for the one sprite it was written about — the body
widens and the outline does not. This is derived from the two shaders' third
arguments, not observed headful; the mechanism is certain, the visual severity
is not measured.

### The shadow left the Effects bucket, and no ADR records it

The Consequences say "**Shadows live in the Effects bucket**, not Unit — a
shadow blob stretches with `psx_fx_stretch`". That was true at this ADR's own
implementing commit: `9fec26b18` (2026-06-14) put
`anchor_clip.x * psx_par + (vertex_clip.x - anchor_clip.x) * psx_fx_stretch` in
`shadow_blob.gdshader`. It is false today. `shadow_blob.gdshader:68-71` reads
Pattern 1, `psx_par_full(clip_pos)` — full map stretch, no taxonomy at all.

The sequence: `ee46272fc` (2026-07-03) rebuilt the shadow as a ground-locked
subtractive decal draped to the terrain normal — no longer a billboard, so no
billboard offset to stretch. `66ecc4fb9` (2026-07-04) then gave it Pattern 1,
its message stating the reason ("The shadow is flat map-attached geometry, so it
now takes Pattern 1 (full-stretch), identical to tile_overlay"). Neither commit
cites this ADR, and there is no ADR for the ground-locked shadow at all
(no `docs/adr/*.md` mentions `shadow_blob`, "ground-locked" or "subtractive
blob"). ADR-0060 later *lists* "unit shadow" under Pattern 1 in its Decision
without noting that it is reversing a Consequence of this ADR.

Two corrections fall out of this, recorded here rather than edited into the
other document: ADR-0060's context line "the unit shadow (fixed 2026-07-04 — it
was the one battle mesh applying no `psx_par` at all)" is true of the decal that
existed on 2026-07-03, not of the mesh this ADR shipped — that one applied
`psx_par` on its anchor for two and a half weeks. And this ADR's own dec. 3
anticipated exactly this case ("a shadow that shouldn't track the FX stretch")
and prescribed a *split*; what actually happened is a pattern change, which is a
cleaner answer than the hatch offered.

### The rest of the Consequences

- **Three new `[shader_globals]`** — ✓, verified in `project.godot`.
- **GTE/OT depth untouched** — ✓. `psx_par_anchor` writes only `par_clip.x`;
  `shadow_blob.gdshader` and the unit shaders compute `DEPTH` from
  `psx_ot_depth` independently of any stretch.
- **The cursor's interim per-material `cursor_par` uniform is removed** — ✓,
  and completely: `cursor_par` has **zero** hits across `.gd`, `.gdshader`,
  `.gdshaderinc`, `.tres` and `project.godot`.
- **CONTEXT.md gains a `Sprite stretch` term** — ✓, `28-display-and-pixel-aspect.md:132`.
  Note that same file's line 109 still says `DisplayDebugPanel` hosts the
  channels; that panel is deleted (dec. 4 above).

### Recorded question — is the FX bucket a ROSTER or a DEFAULT?

Not resolved here, because the two readings prescribe opposite fixes.

**Reading A — dec. 2's third bullet is a roster, and three meshes are off it.**
"everything else: effect particles, projectiles, shadow blobs, callback meshes"
enumerates what must read `psx_fx_stretch`. Then `projectile_vertex_color.gdshader`
and `trap_charge_line.gdshader` hardcoding `1.0` are violations — a scrub of the
FX stretch would widen the arrow *sprite* but not the arrow *geometry*, and the
cursor outline reading FX rather than Cursor is a straightforward bucket error to
fix. Under A, the fix is three one-word shader edits plus a guard.

**Reading B — `1.0` is the legitimate "no billboard art to preserve" opt-out.**
Both hardcoders say so in their own comments: `trap_charge_line.gdshader:6-9`
("the line cluster's geometry is authored in world space … no native pixel
aspect to preserve"), `projectile_vertex_color.gdshader:25-26` ("the arrow's
geometry keeps its authored proportions"). Sprite stretch is defined as
*billboard width*; authored 3D geometry has no billboard width, so a literal
`1.0` is the correct expression of "this mesh has no taxonomy", and dec. 2's
bullet is a default for sprites, not a roster of meshes. Under B, the two
hardcoders are right and only the cursor outline is wrong.

Both readings agree the cursor outline is misfiled; they disagree on whether a
guard may assert "no `psx_par_anchor` call passes a literal". A human should
rule before either is written.

### On mechanizing this ADR

`check_sprite_stretch_globals.py` already guards the *wiring* (dec. 2's globals
+ dec. 4's channels), and it is deliberately path-independent — it walks
`_walk_roots.walk_roots()`, which is why `PSXDisplay.gd`'s two moves (into
`addons/exmateria_platform/display_port/` via ADR-0147 dec. 1 → ADR-0171 dec. 1
→ ADR-0184 dec. 2) never reported the seam as absent. Three arms are possible
and unwritten:

1. **The roster arm (blocked on the recorded question).** Parse the third
   argument of every `psx_par_anchor(` call and assert it is one of the three
   globals. Red today at three sites under reading A, one under reading B.
2. **The cursor-coherence arm (not blocked).** Assert that every shader reading
   the tile-cursor sprite's geometry passes `psx_cursor_stretch` — i.e. that
   `tile_cursor.gdshaderinc` and `cursor_fold.gdshaderinc` pass the *same*
   global. This is red today under either reading and asserts precisely what
   this ADR was written to make possible.
3. **The dec. 4 scrub arm.** Assert the three `render.psx_*_stretch` slugs are
   `bind_update`-registered, which is what makes them scrubbable now that
   `DisplayDebugPanel` is gone. Green today; it would have caught the deletion
   silently orphaning them.
