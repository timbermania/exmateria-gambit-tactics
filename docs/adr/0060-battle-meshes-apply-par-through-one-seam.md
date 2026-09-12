# Every battle mesh applies PAR through one shared clip-space seam

[ADR-0036](0036-par-is-per-content-clip-space-not-global-stretch.md) decided
*what* PAR is — a per-mesh horizontal clip-space multiply, applied opt-in in
the vertex shader, never a global frame stretch. [ADR-0044](0044-sprite-stretch-is-per-taxonomy-billboard-width.md)
layered the per-taxonomy billboard-width multipliers on top. But those ADRs
decided a **model** without a **mechanism**: every shader that opted in
re-declared `global uniform float psx_par;` and hand-inlined one of two
clip-space formulas. ~11 shaders each carried their own copy.

The predictable failure followed. Twice, a new battle mesh shipped that
silently applied **zero** PAR and drifted horizontally out of alignment with
the units/map: the unit shadow (fixed 2026-07-04 — it was the one battle mesh
applying no `psx_par` at all) and, earlier, the dialogue box/tail placement.
Same root shape both times: PAR is a second placement axis, applied per-mesh in
the vertex shader, and a new consumer silently misses it (or picks the wrong
one of the two patterns).

This is the **identical** failure mode the DEPTH axis had — "a new mesh forgot
`CUSTOM0`" / "a new shader hand-rolled a `DEPTH` epsilon" — and
[ADR-0009](0009-ordering-table-depth-is-one-model.md) already solved it: one
shared shader function (`psx_ot_depth`) + one pure-Python preflight
(`check_depth_shaders.py`) that fails the build if any `DEPTH`-writing shader
skips the seam. PAR had the ADR (0036) but neither the seam nor the check. That
asymmetry is the bug factory. This ADR closes it by giving PAR the same two
pieces — the `POSITION` analogue of ADR-0009's `DEPTH` rule.

## Status

accepted

## Decision

One shared include, `assets/shaders/psx_par.gdshaderinc`, is the single home
for `global uniform float psx_par;` and the two — and only two — PAR patterns,
exposed as helper functions:

- `vec4 psx_par_full(vec4 clip)` — **Pattern 1, full-stretch**: `clip.x *=
  psx_par`. Flat, map-attached geometry that stretches *with* the map
  (terrain, map skirt, tile overlays, unit shadow, callback meshes).
- `vec4 psx_par_anchor(vec4 vertex_clip, vec4 anchor_clip, float stretch)` —
  **Pattern 2, anchor-only**: the anchor (object origin in clip space) tracks
  the PAR-stretched map while the sprite's footprint offset scales by the
  per-taxonomy `stretch` (ADR-0044; `1.0` = native art). Billboards whose
  anchor tracks the map but whose sprite art stays native (unit/effect/
  projectile sprites, tile cursor).

Every battle shader that writes `POSITION` must `#include` the seam and write
`POSITION` from one of these helpers. A pure-Python preflight,
`tools/check_par_shaders.py`, wired into `tests/run_all_tests.sh` beside the
depth check, fails the build otherwise. Genuine screen-space passes that map
quad corners straight to NDC (fullscreen overlays) opt out with an explicit,
greppable `// psx-par-exempt: <reason>` marker.

## Considered options

- **Shared include + helper functions + enforced preflight (chosen).**
  Operationalize ADR-0036 exactly the way ADR-0009 operationalized depth. The
  computation lives once; the check makes "silently forgot PAR" impossible to
  ship. Chosen because the depth axis already proved this shape retires this
  exact recurring bug at the root.
- **Shared include, no enforcement (rejected).** Dedup the two formulas into
  helpers but rely on code review to catch omissions. Rejected: the two
  incidents *passed* review — the whole point is a mesh that writes `POSITION`
  and never mentions PAR reads as complete. Only a preflight that keys on the
  `POSITION` write catches an *absence*.
- **Enforce include-presence only, not the `POSITION` RHS form (rejected).**
  A lighter check: assert the shader `#include`s the seam or is exempt, and
  trust the author used a helper. Rejected: it catches total omission (the
  shadow bug) but not "included the seam yet wrote `POSITION` wrong" — and the
  strict RHS check costs nothing extra, since `POSITION` genuinely *should*
  be written directly from a helper. So the check requires the helper call to
  appear in the `POSITION` write itself.
- **One helper with a mode enum, mirroring `psx_ot_depth(..., mode)`
  (rejected).** PAR has exactly two patterns with structurally different
  signatures (one clip in vs. a vertex+anchor+stretch triple). Two named
  functions self-document which pattern a call site uses and don't conflate
  the signatures; the depth seam's mode-int fits *its* six modes over one
  point, not this.
- **A billboard-rotation seam too (deferred, not rejected).** The user framed
  the bug as "not billboarding the same." PAR is the axis that actually bit
  both incidents; billboard *rotation* is already shared where it matters
  (`unit.gdshader`'s `billboard()`), and has not demonstrated a bug. Scoped to
  PAR; a rotation seam is a possible later follow-up on its own evidence.

## Consequences

- **The two patterns are algebraically one.** `psx_par_anchor(v, a, 1.0)`
  reduces to `v.x + a.x*(psx_par - 1.0)` — the native-width billboard form two
  shaders (`projectile_vertex_color`, `trap_charge_line`) previously inlined
  by hand. They now pass `stretch = 1.0` to the same helper, so there is one
  anchor formula, not two.
- **PAR-then-cull became cull-then-PAR in two shaders.** `black_unlit` and
  `indexed_color` ran `fft_apply_visible_angles_cull` *after* the PAR multiply,
  so the final `POSITION` wasn't the PAR result. Reordering the cull *before*
  the seam call is behavior-preserving: a culled vertex is set to `(2,2,2,1)`
  (off-screen), and scaling its `x` by `psx_par` keeps it off-screen. The
  final `POSITION` write is now the helper, satisfying the strict check.
- **`tile_overlay`'s `debug_no_psx` bypass survives.** The isolation-scene
  toggle is preserved as `POSITION = debug_no_psx ? clip : psx_par_full(clip);`
  — the helper call still appears in the `POSITION` write, so the strict check
  passes without special-casing.
- **The check scans `.gdshaderinc` too.** Three `POSITION` writes live in
  shared includes (`tile_overlay` / `tile_cursor` / `effect_particle_stp`),
  which the DEPTH check's `.gdshader`-only glob would miss. `check_par_shaders.py`
  globs both extensions so include-based shaders — exactly the kind that could
  silently miss PAR — are covered.
- **One global to scrub.** With `psx_par` declared once in the seam, the F3
  Display debug panel's global scrub (`PSXDisplay.live_par`) remains the manual
  regression for "everything shares one PAR" — now guaranteed by construction,
  not by every shader happening to read the same global name.
- **This is pure dedup — no PAR values or patterns changed.** The migration is
  mechanical: same two formulas, same taxonomy-stretch uniforms
  (`psx_unit_stretch` / `psx_fx_stretch` / `psx_cursor_stretch` stay per-shader,
  ADR-0044), verified headful that map/units/particles/cursor/shadow render
  pixel-identical before/after.
- **Three fullscreen overlays are explicitly exempt.** `show_graphic`,
  `screen_background`, and `darkscreen_mosaic` map quad corners straight to NDC
  (`sign(VERTEX.xy)`) and have no battle-space position to align to. The
  `// psx-par-exempt:` marker converts "silently missing PAR" into "declared
  exempt, reviewed once."
- **Relationship to ADR-0057.** PAR and OT depth are both *render-class*
  transforms in the [ADR-0057](0057-psx-spatial-transforms-sort-into-three-classes-placement-orientation-render.md)
  taxonomy — the two axes a battle mesh's vertex shader owns. Each now has a
  seam + a preflight; a new battle shader wires up both or is flagged.
- **Vocabulary.** `CONTEXT.md`'s "Display and pixel aspect" cluster records
  that PAR is now applied through the shared `psx_par` seam and enforced,
  alongside the "Rendering depth" cluster's `psx_ot_depth` entry.
  `CLAUDE.md`'s "Common Mistakes" table gains a "battle mesh without `psx_par`"
  row, sibling to the existing "3D mesh without CUSTOM0 GTE depth".
- **Not part of `bootstrap_assets.sh`.** The include and the check are
  hand-authored render code, not ISO-derived assets.
