# PAR is a per-content clip-space multiply, not a global frame stretch

The PSX renders at 256×240 (16:15) but displays at 4:3, so each PSX pixel
is ~1.25× wide × 1 tall. Reproducing this look on a modern square-pixel
display means stretching *something* horizontally by 1.25. The project has
tried both ends of the spectrum and landed in the middle:

1. **Per-element only (early attempt).** `UIChar` / `UIText` / `UIPortrait`
   carried a `pixel_aspect_ratio` exported field; flipping it to 1.25 fixed
   text and portraits. The look was partially right but the 3D world (map,
   units) had no PAR applied — so the game's framebuffer was still rendering
   at 1:1 outside of UI, which diverged from the PSX original at a deeper
   level than UI alone could close.

2. **Global frame stretch (later attempt).** `PSXDisplay` wrapped the main
   scene in a `SubViewport` (1024×960 at 16:15) inside a container scaled
   `(PAR, 1.0)` for a 1280×960 4:3 output. Map geometry looked dramatically
   better — roof slopes that had read as "too steep" flattened to FFT-correct
   proportions. But four things broke at once:
   - **Debug ergonomics**: the editor / runtime debug surface was no longer
     "the game" but a mesh holding the game, so picking, scene reload, and
     in-viewport tuning all routed through the wrapper layer awkwardly.
   - **Camera asymmetry**: horizontal vs. vertical camera pans no longer
     moved the view by the same world distance per input unit, because
     camera math was operating in pre-stretch coordinates while the user
     was reading post-stretch screen.
   - **Sprite filtering**: unit sprites at the 1.25 non-integer stretch
     looked subtly worse than their unstretched form, even at 4× internal
     resolution.
   - **Selective control was impossible**: the user wanted the map to
     stretch but not the units; a global wrapper can't express that.

The framing trap behind both failed attempts is the same: "is X PAR or
not?" hides the prior question of *which coordinate system X's position is
expressed in*. Resolve coordinates first and PAR collapses to a per-content
rendering detail.

## Status

Accepted (2026-06-10)

## Decision

**One canonical coordinate system, plus a per-mesh opt-in clip-space
multiply.** Concretely:

The eight rules below were an unnumbered bullet list until this ADR's audit;
they were numbered — text unchanged — so `ADR-0036 dec. N` citations resolve.
Amendment 1 grades each one against the tree.

1. **Display space is the only canonical screen-space.** UI positions,
   camera framing, gambit cursors, debug overlays, layout-container step
   values — all live in square display pixels (1280×960 today). Virtual
   PSX pixels never escape an individual element's renderer.
2. **PAR is a per-content rendering choice, not a global mode.** A mesh
   opts in by multiplying `clip_pos.x` by PAR **after**
   `PROJECTION_MATRIX * MODELVIEW_MATRIX`, in its vertex shader. Three
   patterns exhaust the design space for 3D-world meshes:
   - **Pattern 1 — Full-stretch.** Every vertex's `clip.x` is PAR'd. Used
     by the map, tile overlays, range indicators, the map skirt, effect
     callback meshes — any geometry whose *shape* should stretch with the
     map.
   - **Pattern 2 — Anchor-only.** The mesh's anchor projects through MVP,
     its clip-X is PAR'd, then the billboard's screen-space offset is added
     un-stretched. Used by units, status text floating above units, effect
     particles, unit shadows, projectiles — anything whose position should
     track the stretched map but whose sprite art should render at native
     pixel aspect.
   - **Pattern 3 — None.** No 3D-world candidates today. Reserved.
3. **The world stays PAR-blind end to end.** `CUSTOM0` is never multiplied
   by PAR. `VERTEX` in object space is never multiplied by PAR. Pathfinding,
   gambit conditions, distance checks, save files, debug logs, the GPU
   combat buffer — none know PAR exists. The only thing that ever
   multiplies by 1.25 is the final clip-X of a per-mesh opt-in shader.
4. **One project-wide `psx_par` global shader parameter drives every
   opt-in world shader.** `project.godot` declares `psx_par` in
   `[shader_globals]` (float, default `1.25`). Each opt-in shader reads
   it with `global uniform float psx_par;` and multiplies `clip_pos.x` by
   it after MVP — Pattern 1 on every vertex, Pattern 2 on the anchor only.
   No per-shader `par_anchor` / `par_billboard` uniform: one global,
   written once at the project level, tuned at runtime through
   `PSXDisplay.live_par` (see below). Editor preview reads the global's
   default (1.25); runtime overrides it.
5. **`PSXDisplay` owns runtime PAR state, split across two independent
   channels.** `live_par` (initial value sourced from the `psx_par`
   `[shader_globals]` default — see the ownership bullet below) writes the
   `psx_par` global shader parameter, so scrubbing it re-stretches every
   opt-in world shader in one move. `live_ui_par` (defaults to `PAR`) is a
   parallel value UI3 elements read for their mesh-width math. Both emit
   `*_changed` signals; `DisplayDebugPanel` and `UIDisplayDebugPanel`
   host parallel SpinBox scrubs that write the two values independently.
   The split is deliberate — UI fonts may want a different stretch than
   the world (a modern debug font at 1.0 while the world stays at 1.25,
   or vice-versa), and there is no single "PAR knob" the project agrees
   on; each surface tunes for its own evidence.
6. **Shader-global defaults live in ONE home: `project.godot`
   `[shader_globals]`; `PSXDisplay` mirrors by reading them, never by
   re-declaring them (Option A).** The four shader-backed mirrors
   (`live_par` / `live_cursor_stretch` / `live_unit_stretch` /
   `live_fx_stretch`) carry no numeric default on their `var` declaration.
   `PSXDisplay._ready()` sources each from its `[shader_globals]` boot value
   via the `PSXDisplay.shader_global_default(name)` helper (which reads
   `ProjectSettings.get_setting("shader_globals/<name>")` — NOT
   `RenderingServer.global_shader_parameter_get`, which returns null for the
   project.godot boot defaults). Reset buttons and panel initials resolve the
   same helper, so "reset" can't reintroduce a rival literal. This kills the
   old duplication where each default lived both in `project.godot` and as a
   hardcoded `= 1.0` in the autoload with nothing keeping the two equal.
   `PSXDisplaySingleSourceTest` guards the seam. **Exception: `live_ui_par` is
   NOT a shader global** — it's a GDScript-only mesh-width multiplier for UI3 —
   so it keeps its own constant default and is single-sourced already.
7. **UI elements that draw PSX pixel art default `pixel_aspect_ratio` to
   `PSXDisplay.PAR`.** `UIChar`, `UIText`, `UIPortrait`, `UIFrame` flip
   their `@export` defaults from 1.0 to 1.25; non-PSX UI (a future modern
   HUD font, debug-only text) sets 1.0 explicitly. Top-left positioning
   is invariant under PAR (the quad's centering offset already includes
   the PAR factor in `UIChar:154` / `UIPortrait:116`), so corner-anchored
   positions don't move. Layout consumers that need width —
   right-alignment, centering, container stepping — read
   `get_display_width()`, which already returns the post-PAR width.
8. **UI3 elements sync to `live_ui_par` at runtime, guarded by
   `Engine.is_editor_hint()`.** The `@export pixel_aspect_ratio` default
   is what the editor preview renders against (so the inspector keeps
   showing pixel-perfect art at the chosen default). At runtime each
   element checks `if not Engine.is_editor_hint()`, overwrites
   `pixel_aspect_ratio` from `PSXDisplay.live_ui_par`, and connects to
   `live_ui_par_changed` to rebuild on the fly. The guard is what keeps
   the editor preview decoupled from the runtime scrub.

## Considered options

- **Per-content clip-space PAR (chosen).** Pays the cost of "every 3D
  world shader needs to pick a pattern" in exchange for: selective
  control, world coordinates that don't know PAR exists, depth pipeline
  unchanged, camera and CameraSubsystem unchanged, easy per-mesh A/B
  experimentation, and one project-wide global (`psx_par` in
  `[shader_globals]`) so the design lands at canonical 1.25 by default
  and any subsystem can opt in by reading the global.
- **Global SubViewport stretch (rejected, retired).** The original
  `PSXDisplay` shape wrapped the main scene in a `SubViewport` scaled
  `(PAR, 1.0)`. Solved map look in isolation but couldn't selectively
  skip units, broke debug ergonomics, broke camera-pan symmetry, and
  added a scene-routing layer (`reload_scene` workaround, `current_scene`
  ↔ SubViewport reparenting) that the rest of the project then had to
  know about. The wrapping logic was deleted; the autoload's reason to
  exist is the runtime PAR state (`live_par` / `live_ui_par`) plus the
  `PAR := 1.25` constant.
- **World-space vertex scaling on the map mesh.** Multiply map vertices'
  X by 1.25 in world space (or as a static node scale). Reproduces the
  roof-flattening at camera rotation 0°. Fails at rotation 90° / 180° /
  270° because screen-X corresponds to different world axes per
  rotation — would require a different mesh scale per quadrant, or a
  shader uniform that reads camera rotation and scales the per-vertex
  world offset accordingly (which is the clip-space PAR approach in
  disguise). Rejected: clip-space is the simpler expression of "stretch
  the screen-axis output of this mesh."
- **Custom horizontal-only projection matrix on the camera.** Replace the
  Camera3D projection with one whose horizontal world span is `size *
  aspect * PAR`. Effectively pre-bakes PAR into the camera. Equivalent
  to global stretch in visual result — stretches everything in view,
  including units. Rejected for the same reason global stretch was: no
  selective control.
- **Two unit shaders, `unit.gdshader` and `unit_par_anchor.gdshader`.**
  Switch which material the mesh uses based on a project flag. Rejected:
  the unit shader carries layer composition (ADR-0019), palette /
  animation / state machinery, and GTE depth — two copies guarantee
  drift across the project's most-edited shader. One shader reading the
  `psx_par` global is the same change with no maintenance tax.
- **Per-shader `par_anchor` / `par_billboard` uniforms (rejected).**
  Each opt-in shader takes its own uniform defaulting to 1.0 (no-op);
  flipping it to 1.25 enables PAR for that surface. Would have let
  Pattern 2 ship without any visible change. Rejected after Pattern 1
  landed and surfaced the second tax: every new opt-in shader has to
  re-declare the uniform, every debug surface has to expose a separate
  scrub per shader, and there's no single number to read when a
  subsystem wants to know "what PAR are we tuning the world at right
  now?". One project-wide `psx_par` global written from
  `PSXDisplay.live_par` collapses the multiplicity — opt-in shaders
  just read the global. Speculative `par_billboard` is also not added:
  no content type wants stretched billboard width.

## Consequences

- **GTE depth pipeline is untouched.** Face depth is `c.z / c.w` from the
  projected `CUSTOM0` centroid. PAR multiplies only `c.x`, which neither
  term reads. OT bucket assignment, `Depth mode` biases (relative `PULL_*`,
  absolute `FIXED_*`, project nudges `UNIT` / `TILE_OVERLAY` /
  `MAP_SKIRT`), and `Layer priority` intra-unit stacking all sort
  identically to today. ADR-0009 is unaffected.
- **CameraSubsystem is unchanged.** It operates in PSX coords mapped to
  Godot world coords via `PSXCameraConvert`, then drives the Camera3D's
  transform. World-to-world conversion is PAR-blind by construction.
  Effects that frame a target at NDC 0 keep it at NDC 0 (center is
  PAR-invariant); effects that frame off-center elements render the
  composition ~1.25× wider in screen space than the PSX TV did. The
  shift is "more dramatic" rather than "wrong" and is tunable per-effect
  if any specific cast feels off-balance.
- **Camera horizontal coverage shrinks ~20%.** PAR'd map content covers
  1.25× more screen pixels per world unit, so the same camera ortho
  `size` shows 1/1.25 = 80% as much horizontal world. No compensation in
  the camera; the user widens `size` manually if a play feel suffers. A
  future `Projection` override that widens horizontal-only is a known
  upgrade path if manual zoom isn't enough.
- **Mouse-click → tile resolution PAR-corrects.** Godot's
  `unproject_position` doesn't know about the shader-side multiply, so a
  click at screen pixel (px, py) divides by `PSXDisplay.live_par` before
  unprojection to land on the tile the user visually clicked. Wired in
  `PlacementInputHandler.gd:79` — one line, reads the live scrub so the
  raycast stays correct under any PAR tuning.
- **UI position authoring locks PAR.** With `@export pixel_aspect_ratio`
  defaults flipped to 1.25 and no global toggle, eyeballed positions are
  stable. Don't tune positions with PAR off and flip it on later —
  anything center- or right-aligned will shift. The runtime `live_ui_par`
  scrub is for *visual evaluation* of alternate PAR values, not for
  authoring positions against; saved positions should target the chosen
  default.
- **CONTEXT.md gains a `Display and pixel aspect` cluster.** Four terms —
  `Display space`, `PAR`, `Layout under PAR`, `PSXDisplay` — and the
  implementation invariant ("PAR only multiplies `clip_pos.x` after
  `PROJECTION_MATRIX * MODELVIEW_MATRIX`") live there as the trail back
  to this ADR.

## Amendment 1 — the canonical 1.25 survives in no default, the three patterns became a mechanized seam, and `get_display_width()` has no readers

_Audit, 2026-08-28. Every decision above graded against the tree, not against
the ADRs that cite this one. The eight decisions were numbered in the same
pass; the Decision text itself is unchanged._

### What is current, per decision

| Dec. | Rule | Holds? | What the tree says |
| --- | --- | --- | --- |
| 1 | Display space is the only canonical screen-space | yes | No counter-example found. The PAR-blindness half is measured under dec. 3. |
| 2 | PAR is per-content; Patterns 1 / 2 / 3 | rule yes, **spelling superseded** | A conforming shader no longer writes `clip_pos.x *= psx_par` by hand. ADR-0060 moved both patterns behind `addons/exmateria_platform/pixel_aspect/psx_par.gdshaderinc`: `psx_par_full(vec4 clip)` (`:55`) and `psx_par_anchor(vec4 vertex_clip, vec4 anchor_clip, float stretch)` (`:66`). Pattern 3 ("None") is spelled as the `// psx-par-exempt: <reason>` marker. |
| 3 | The world stays PAR-blind end to end | yes | No shader multiplies `CUSTOM0` or object-space `VERTEX` by PAR. The seam's own comment (`psx_par.gdshaderinc:54`) records that `(clip.z / clip.w)` is untouched, and two Pattern-1 shaders restate it at their call sites (`black_unlit.gdshader:15`, `indexed_color.gdshader:114`). |
| 4 | One `psx_par` global, `[shader_globals]` **default `1.25`** | **structure yes, number NO** | `project.godot [shader_globals] psx_par` reads **`1.0`**. It landed at `1.25` in `311dab22a` (2026-06-10 — this ADR's own accept date) and moved to `1.0` in `b7b336491` (2026-07-06, _"scenario-debug: VM-panel rewind-scroll + alignment-workbench tuning"_). That commit names no ADR and this ADR was not amended. Everything else holds: one global, read as `global uniform float psx_par;`, no per-shader `par_anchor` / `par_billboard` uniform. The clause "Editor preview reads the global's default (1.25)" reads `1.0` today. |
| 5 | `PSXDisplay` owns runtime PAR, **two** channels, scrubbed by `DisplayDebugPanel` / `UIDisplayDebugPanel` | **three claims moved** | (a) There are **five** mirrors, not two: `live_par` and `live_ui_par` were joined by `live_cursor_stretch` / `live_unit_stretch` / `live_fx_stretch` (ADR-0044), plus `psx_gamma`. (b) All six are Tune tunables (ADR-0068) — the setters route through `TunePort.set_value`, the getters coalesce override-over-default, and each `_apply_*` is bound in `register_tunables()` (`PSXDisplay.gd:70`), so nothing writes the shader global directly any more. (c) **`DisplayDebugPanel` is deleted** (ADR-0151, `bb5f7fefa` — "the two panels declared nothing"); the world-PAR scrub is now the generated Tunables card, a clamped 0.5–2.0 spinbox declared at `PSXDisplay.gd:72-74`. `UIDisplayDebugPanel` survives. |
| 5 (cont.) | "`live_ui_par` (defaults to `PAR`)" | **no** | `_ui_par_default: float = 1.0`, whose own comment reads "square UI PAR for alignment work; was PAR 1.25". And the `PAR := 1.25` constant this clause names by symbol was **deleted** as a zero-reader constant by ADR-0152 (`PSXDisplay.gd:27-28`) — so the Considered-options line "the autoload's reason to exist is the runtime PAR state … plus the `PAR := 1.25` constant" names something that is gone. |
| 6 | Shader-global defaults have ONE home; `PSXDisplay` mirrors by reading (Option A) | **yes, in full** | The only decision here with a test. `shader_global_default(name)` (`PSXDisplay.gd:105`) reads `ProjectSettings.get_setting("shader_globals/" + name, {})` and explicitly not `RenderingServer.global_shader_parameter_get`, as written. The four shader-backed mirrors carry `= 0.0` sentinels, never a numeric default, and are sourced in `register_tunables()`. `tests/PSXDisplaySingleSourceTest.gd:32` drives the mirrors by slug. The `live_ui_par` exception holds — it is not a shader global and keeps its own constant default. |
| 7 | `UIChar` / `UIText` / `UIPortrait` / `UIFrame` default `pixel_aspect_ratio` to 1.25; width consumers read `get_display_width()` | **half** | The four `@export` defaults ARE 1.25 (`UIChar:75`, `UIText:42`, `UIPortrait:44`, `UIFrame:123`), and the sanctioned explicit-1.0 opt-out is exercised twice (`UI3Element.gd:538` for display-px-authored windows, `OpeningScene.gd:36`). But **`get_display_width()` has zero callers** — two definitions (`UIChar:212`, `UIPortrait:409`), no reads anywhere in the tree. The layout consumers this decision routes through it don't: `UIText` inlines `* pixel_aspect_ratio` at `:204`, `:251`, `:261`, `:286`. The two line citations are also stale — the PAR factor is at `UIChar:162`, and `UIPortrait:116` is now `_on_live_ui_par_changed`. |
| 8 | UI3 syncs to `live_ui_par` at runtime, guarded by `Engine.is_editor_hint()` | yes | All four elements carry the guard and the `live_ui_par_changed` connection (`UIChar:115-124`, `UIText:115/119`, `UIPortrait:90/110`, `UIFrame:157/164`). |

### The consequence dec. 4 and dec. 7 have between them

Decision 7 flips four `@export` defaults to 1.25 and decision 8 overwrites them
from `live_ui_par` at runtime — and `live_ui_par` now defaults to 1.0. So the
1.25 decision 7 chose is **editor-preview-only**: the inspector renders at 1.25,
the running game renders those same elements at 1.0. World content is at 1.0
too (dec. 4). The Consequences section's "UI position authoring locks PAR"
paragraph is dead as written — it assumes "defaults flipped to 1.25 and no
global toggle", and there is a global toggle, defaulting the other way. Its own
warning ("Don't tune positions with PAR off and flip it on later — anything
center- or right-aligned will shift") describes the state the tree is in.

### Open question for a human — is world PAR 1.0 a decision or a leak?

Nothing in the tree distinguishes these two readings, so this amendment records
both rather than picking one:

1. **1.25 was retired on evidence.** Alignment work wanted square pixels; the
   `PAR := 1.25` constant was deleted as unused (ADR-0152); and UI PAR's default
   comment records its flip deliberately ("was PAR 1.25"). Under this reading
   the 1.25 literals in decisions 4, 5 and 7 should be struck and PAR restated
   as a tunable with no canonical value.
2. **1.0 is a workbench scrub that got committed.** `b7b336491` is a
   scenario-debug tuning commit that moved several `[shader_globals]` values at
   once and cites no ADR, and it left the four UI `@export` defaults at 1.25 —
   which is what a leak looks like, not a retirement.

Either way the mechanized consequence is the same: **"1.25" is not a checkable
claim about this tree**, and any guard written from this ADR must read the
default rather than assert a literal.

### Consequences that still hold

- `PlacementInputHandler.gd:79` still PAR-corrects the click, still in one line,
  still reading `PSXDisplay.live_par` — so it follows the scrub as promised
  (including down to 1.0, where it is a no-op divide).
- The `Display and pixel aspect` CONTEXT cluster exists with its four terms, at
  `docs/context/28-display-and-pixel-aspect.md` after the CONTEXT.md split.

### On mechanizing this ADR

A guard already exists for decision 2, but it is **ADR-0060's**, not this
ADR's: `tools/check_par_shaders.py` walks `classify_blueprint.WALK_ROOTS` and
requires every POSITION-writing shader to `#include` the seam and write POSITION
from `psx_par_full(...)` or `psx_par_anchor(...)`, with `// psx-par-exempt:` the
only opt-out. Today it reports "102 walked, 11 on the BURN_DOWN list" — ten
`src/ui3/shaders/*` files plus `assets/shaders/unit_flat.gdshader`, each a
standing violation with a both-arms direction test on stale entries.

Two arms are missing and are cheap:

- **Decision 3 is mechanizable and unguarded.** Assert that no `.gdshader` /
  `.gdshaderinc` multiplies `CUSTOM0` or object-space `VERTEX` by `psx_par` or
  any `psx_*_stretch` global — the PAR-blindness invariant, which today survives
  only as prose in two shaders' comments.
- **Decision 7's `get_display_width()` clause is mechanizable and currently
  false.** Assert that the accessor has at least one caller, or delete the
  clause; a published width accessor with zero readers cannot be enforcing
  anything.

Decision 4's literal is deliberately left unmechanized until the open question
above is answered — a guard asserting `1.25` would be red on landing, and one
asserting `1.0` would ratify a value nobody chose in writing.
