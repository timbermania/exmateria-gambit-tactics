# The unit sprite is a module, and a consumer asks for a variant

`UI` and `Cutscene` do not fork `Sprite Rig`'s sprite compositor because they need a
different one. They fork it because `SpriteLayerManager` takes its material from the
caller, so the only way to change *how* a unit sprite blends is to reach into that
material and replace its `.shader`. Both of them did exactly that, in one line each. The
1,018-line duplicate in `src/ui3/shaders/formation_unit.gdshader` was what that hole
leaked, not the defect itself.

`Sprite Rig` publishes a **variant**; no consumer outside it names a unit shader path.

## Status

Accepted. Renumbered from 0172 on 2026-08-27 after `main` independently took that
number. Reopens [ADR-0129](0129-the-fold-is-renders-and-a-producer-keeps-its-shader.md)
dec. 4 for the sprite compositor specifically. Amends `docs/BLUEPRINT.md` §4 (a new
`Sprite Rig` Part). Re-books two files in `tools/classify_blueprint.py`.

Verified 2026-08-28 — decs. 1–9 built. `src/animation/UnitMaterial.gd` publishes
`for_variant()` and `shader_for()` over a `Variant` enum; the fork is now
`assets/shaders/unit_flat.gdshader` at **177** lines beside two 99-line battle entries
over a 907-line shared body that defines no `vertex()`/`fragment()`;
`tools/check_unit_shader_paths.py` holds dec. 8 with three named variant paths and three
allowance rows; and `classify_blueprint.py`, `check_par_shaders.py` and
`check_color_shaders.py` all carry dec. 7's edits.

## Context

An architecture review of the render system found `src/ui3/shaders/formation_unit.gdshader`
and `assets/shaders/unit_sprite_body.gdshaderinc` to be near-duplicates. Measured by whole
function body with comments stripped, **22 of the flat variant's 24 functions were
byte-identical** to the include; only `vertex`, `fragment` and its own `cj_cell_noise`
differed, and its non-function declarations — every uniform, every other `#include` — were
identical line for line. The fork's own header asked a human to maintain it: *"If the unit
compositor changes materially, re-sync this fork."*

**The duplication was a symptom.** The CPU driver was never forked. All three materials are
driven by the same `SpriteLayerManager`, and all three start from the same resource:

| consumer | bucket | what it did with `assets/materials/unit.tres` |
|---|---|---|
| `src/units/Unit.gd` | `Battle` | `load()`s it and uses it |
| `src/ui3/formation/FormationScene.gd` | `UI` | `load().duplicate()`, then `base.shader = load(_UNIT_SHADER)` |
| `src/scenarios/ScenarioVM.gd` | `Cutscene` | `mat.shader = _UNIT_ADDITIVE_SHADER if additive else _UNIT_OPAQUE_SHADER` |

`SpriteLayerManager.initialize(anim_set, shader_material)` accepts the material from its
caller — five production call sites. That parameter is the hole: two foreign systems
substituted an implementation through it and then drove the result through the interface
they went around.

## The blueprint already draws the line

`BLUEPRINT.md` §4 defines `Sprite Rig` as *"Give it a pose, a facing, a camera quadrant and
an equipment set, and it draws."* Its crossing is stated as *"a pose request on the
published schema — pose, facing, quadrant, equipment set, attachments — and a position."*
Position crosses **in**; the caller supplies it, `Sprite Rig` draws. Neither `UI` nor
`Cutscene` needs to author a shader to obtain either of the things they actually want.

What the blueprint does **not** cover is the change-job commit dissolve — see decision 5.

## Decision

**1. The de-forking is a re-pointing, not a `#define`.** `unit_sprite_body.gdshaderinc`
does not own `vertex()` or `fragment()`. It publishes four names — `billboard()`,
`unit_paint(uv, out albedo, out alpha)`, `unit_colour(albedo)`, `unit_light(albedo)` —
plus the uniform block, and each entry shader writes its own short `vertex()`/`fragment()`.
There is no `UNIT_ADDITIVE` and no `#ifdef`.

A `#define UNIT_FLAT_SCREEN` extension of the existing mechanism was the obvious move and
is refused on a mechanical ground, not a stylistic one. The flat variant writes `POSITION`
with no PAR helper and is carried as debt on `tools/check_par_shaders.py`'s `BURN_DOWN`
list (11 entries). Under a `#define`, that un-PAR'd write would relocate **into**
`unit_sprite_body.gdshaderinc`, which sits on the battle path and already holds the PAR'd
write; the guard has no preprocessor, would see two writes in one file, and would red a
`Sprite Rig` file. Meanwhile the flat variant, now writing no `POSITION` at all, would read
as a stale `BURN_DOWN` entry — which that guard also fails on, direction-tested both ways.
The debt would be laundered into the shared include rather than paid.

**2. The shared body stays `Sprite Rig`'s, in `assets/shaders/`.** A third `#include` is
not an admission argument: ADR-0139 dec. 2 rules that *"reach is not the test"*, and
`CONTEXT.md` → **Shader library** already assigns this file — *"Tier 2 —
`effect_particle_stp`, `unit_sprite_body`, `tile_overlay` — is **not** in it and leaves
with its own system."* Promotion to `addons/exmateria_schema/` fails that kernel's own
admission test (ADR-0146 dec. 3): a kernel shader member is half of a codec, implemented
twice and required to agree. `unit_sprite_body` is implemented once, in GLSL, with no CPU
counterpart. It is shared implementation, not a crossing.

**3. `Sprite Rig` publishes `UnitMaterial.for_variant(OPAQUE | ADDITIVE | FLAT)`.** A
small module beside the manager owns `assets/materials/unit.tres` and the variant table
and returns a configured duplicate. It publishes **two doors, not one**:
`shader_for(variant) -> Shader` exists because `ScenarioVM` owns a live per-unit material
and changes only the blend, so building a whole material just to read `.shader` off it
would allocate a duplicate per fade. No file outside `Sprite Rig` names a unit shader path.

`SpriteLayerManager.initialize(anim_set, shader_material)` keeps its signature and its five
callers. Folding material construction into the manager would close the residual hole —
a caller can still hand-build a `ShaderMaterial` — at the cost of putting resource loading
into the widest module in `Sprite Rig` (883 lines) and disturbing the battle path in a
change whose subject is elsewhere. The residual hole is a guard's job; see decision 8.

**4. Three variants, one file move, no renames.** The fork lives at
`assets/shaders/unit_flat.gdshader`, carrying its original `uid://cfwiu2dfki6ex` so
`uid://` references survive. `unit.gdshader` and `unit_additive.gdshader` keep their names:
renaming for symmetry would touch `assets/materials/unit.tres`, `assets/scenes/Unit.tscn`,
`assets/scenes/SequenceViewer.tscn`, `ScenarioVM.gd` and two tests, by path **and** uid,
for no gain.

Leaving the file in `src/ui3/shaders/` was refused because `("src/ui3/shaders/", "UI")` is
a **prefix** rule in `classify_blueprint.py`; a `Sprite Rig` file there needs a per-file
exception ahead of the prefix — the shape ADR-0141 called a defect in `src/data/`'s
catch-all. `assets/shaders/` is the tree that splits by system.

`flat` is `CONTEXT.md` vocabulary, not invention: the **Depth ladder** entry names the
formation/roster screen a *flat orthographic UI scene*.

**5. `Sprite Rig` has a Part — `modulation`, per-pixel operations on a composed
sprite — and the change-job dissolve is booked to it.** This is a blueprint amendment, and
it is stated as one because the honest finding is that `cj_*` belongs to **neither**
system's Parts as written. It is not a pose, a facing, a quadrant, an equipment set or a
position, so §4 does not reach it; and §6 gives `UI` *"the toolkit | windows, panels,
fonts, lists, focus movement, the open and close cadence"* and *"preview + commit | a
candidate scored by a legality oracle the model owns, then an irrevocable commit"* — under
which the commit animation reads as `UI`'s.

It is booked to `Sprite Rig` on ordering, not on ownership sentiment. The gouraud corner
tint must modulate **between** `psx_color_apply` and `ambient_brightness` — where the PSX
applies gouraud. Only the system that owns that pipeline can guarantee that position. `UI`
owns *when* the commit runs and *with what corners*; `Sprite Rig` owns *how a unit sprite
dissolves*.

The principled alternative — express it through the colour stack, which is already in this
shader — is blocked, not merely unattractive. `ColorRecipe`'s affine is uniform over the
surface and this is bilinear over four corners; that is a third recipe **shape**, and the
wire format's discriminator is a two-way `rgb1[i].w == 0.0` test with no spare encoding.
Nine to eleven files, driven by one caller.

**6. The nine `cj_*` uniforms and `cj_cell_noise()` live in `unit_flat.gdshader`, not in
the shared body.** Decision 5 settles system ownership; it does not settle file placement.
Godot surfaces every declared uniform on the `ShaderMaterial` parameter list, so putting
them in the shared include would hang nine dead parameters off `unit.tres` and off every
battle unit material — inspector-visible, `.tres`-serialisable, and reachable by
`set_shader_parameter` from anywhere. A wider interface for two of three consumers, bought
for nothing.

`#include "res://assets/shaders/psx_par.gdshaderinc"` sits in the two entry shaders that
call `psx_par_anchor`, not in the shared body. The flat variant does not depend on PAR, and
leaving the include in the shared body would have it reach PAR transitively while never
applying it — the state the guard exists to prevent. The relocation is free: neither
`psx_par` nor `psx_unit_stretch` is on the material parameter contract at all —
`psx_unit_stretch` is a `global uniform` driven from `project.godot`.

**7. Guard and classifier consequences.**

- `classify_blueprint.py` books `assets/shaders/unit_flat.gdshader` to `Sprite Rig` and
  re-books `assets/shaders/unit_additive.gdshader` from `Cutscene` to `Sprite Rig`. Decision
  3 makes the variants `Sprite Rig`'s; leaving that row would leave the ownership
  half-landed.
- `check_par_shaders.py` carries the flat variant's `BURN_DOWN` entry under its new path —
  **repathed, not converted** to a `psx-par-exempt:` marker. An exemption is arguable on
  that guard's own terms — it
  reserves them for *"genuine screen-space passes that map quad corners straight to NDC
  (fullscreen overlays) — geometry with nothing in battle space to align to"*, and a flat
  ortho formation screen has none — but ten of the eleven entries are the *other* formation
  shaders. Reclassifying one member of a ten-member group from debt to exempt is a judgement
  on someone else's call and leaves the group incoherent. An observation for whoever burns
  the formation screen down, not a licence.
- `check_color_shaders.py`'s `REQUIRED_CONSUMERS` names **five** entry `.gdshader` files
  that reach `psx_color_apply`, not three: the three unit variants, `indexed_color` and
  `screen_background`. Two were unnamed before decision 4, and the fork was additionally
  unaddressable because the positive loop resolves names under `assets/shaders/` only.

**8. No `.gd` outside `Sprite Rig` names a variant path in code**, enforced by
`tools/check_unit_shader_paths.py` in the suite's pre-flight beside
`check_no_raw_psx_units.py` — the precedent, written the same way for ADR-0091 to hold a
de-duplication that had just landed and had nothing holding it.

The rule names **the three variant paths explicitly**; a `unit*.gdshader` glob is wrong
twice over. `assets/shaders/unit_portrait_3d.gdshader` matches it and is not a variant — it
is booked `UI`, draws EVTFACE dialogue portraits from fully-resolved RGBA rather than the
SPR's indexed 90°-rotated landscape, and `UIPortrait.gd` naming it is correct, so a glob
would red a correct file and the repair would be an exemption apologising for the rule.
`unit_sprite_body.gdshaderinc` also matches, and it is the shared include: nothing mounts
it, and naming it is not the disease. The named list also fails the way a glob cannot — a
renamed variant makes a glob match nothing and pass quietly, where the list reports
`VARIANT_PATHS names a file that does not exist` (#424).

**Comments are stripped**: ten `.gd` files cross-reference a unit shader path in prose, and
only code can mount a shader. **The allowance list is three rows, each carrying its
reason** — `UnitMaterial.gd` (the module), `tests/UnitMaterialVariantTest.gd` (the
contract's own guard, which must name what it pins), and `tests/ScenarioDeadUnitFadeTest.gd`,
which is the **independent oracle** for the additive swap: it asserts
`enemy.material.shader == AdditiveShader` against a preloaded path, and routing it through
`UnitMaterial.shader_for(ADDITIVE)` would make it compare the module's answer to the
module's answer, unable to disagree with the code. A stale allowance row fails like a stale
`BURN_DOWN` entry.

**9. Entries discard; the shared body does not.** `unit_paint` returns coverage and each
entry discards below `UNIT_ALPHA_CUTOFF` itself. The flat variant's change-job dissolve is
a **second** discard that must run after the coverage one and before anything writes depth,
so the first cannot be buried in the shared body. This is the same seam decision 1 draws
between `unit_colour` and `unit_light`: publishing three stages rather than one `fragment()`
is what makes decision 5's ordering requirement reachable from an entry shader, and a
two-name split (`unit_paint` + everything-else) would put the flat variant straight back to
forking.

## Consequences

**ADR-0129 dec. 4 is reopened for this case only.** *"A producer keeps its own shader"* was
written about producers into `Render`'s fold, taking `Render`'s generic library for the
shared parts. This is a different relationship: `UI` and `Cutscene` were taking another
**system's entire sprite compositor**, not a library part. `unit_additive.gdshader` living
in `assets/shaders/` while booked `Cutscene` was dec. 4 instantiated, and decision 7 undoes
that booking. Nothing here touches dec. 4's standing for fold producers.

**A test surface appears where there was none.** Three shader files were three test
surfaces for one behaviour. The assertable claim is now `UnitMaterial.for_variant(v).shader`
— a pure function of an enum, testable without an animation set, a scene, or a GPU.

**What is not claimed.** The three entry shaders do not merge. `render_mode` must sit in
the entry `.gdshader`; Godot has no runtime blend switch. The deliverable is that
`FormationScene` and `ScenarioVM` do not contain a shader **path**, not that the file count
drops.

## Verification

- `tests/UnitMaterialVariantTest.gd` is the contract. Its load-bearing arm derives the
  required parameter set from two things that are **not shaders** — the 39
  `shader_parameter/` keys authored into `unit.tres`, and the parameters
  `SpriteLayerManager` pushes (26 literals plus 24 built by concatenation,
  `layer_name + "_rects"`, which no literal scan can see) — for 46 names asserted against
  all three variants. It also carries the narrow arm of decision 8: `FormationScene` and
  `ScenarioVM`, the two files that actually broke the seam, name no path in code.
- `tools/check_unit_shader_paths.py` is decision 8's wide arm, six arms each
  direction-tested with a reverted seed: the regrowth fires; the same path in a comment
  stays green; code with a trailing comment still fires; a renamed variant reports the stale
  rule; an unused allowance reports itself stale; a lost walk root reports the truncated
  scan.
- `tests/ScenarioDeadUnitFadeTest.gd` is the independent oracle for the additive swap and
  is allowed to name a path for exactly that reason (decision 8).

**A shader-to-shader diff is the wrong instrument here.** Three shaders that all drop the
same uniform agree perfectly, so the comparison is blind to precisely the refactor this ADR
performs. The uniform scan this repo uses elsewhere (`uniform\s+\w+\s+(\w+)`) is blind
again: it cannot see `uniform vec2[10] type1_rects;` — the declaration form of the entire
tile-compositing block — and reads 35 uniforms where there are 62. The contract above is
derived from the resource and the driver instead, which is why it did not move during the
refactor while the shader-to-shader arm did.

See ADR-0129 (a producer keeps its shader — reopened here), ADR-0139 (reach is not the
test), ADR-0146 (the kernel's admission test), ADR-0141 (prefix rules and per-file
exceptions), `docs/BLUEPRINT.md` §4, and `CONTEXT.md` → **Sprite compositor stages**.
