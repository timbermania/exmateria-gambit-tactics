---
status: accepted
---

# The fold predicate is the kernel's, and a producer picks between two shaders it owns

[ADR-0074](0074-display-space-fold-is-a-material-contract-not-a-module.md) made the
material producer-owned and the ordering `DepthMode`'s, and concluded that *"nothing is
left in the middle worth a module."* One thing was left, and 0074 could not have weighed
it: **"is the fold available in this build?"** — a boolean 0074 saw at **one** caller and
that had reached **fourteen call sites across thirteen files**, each a verbatim copy of the
same six lines reaching a host autoload by node-path string.

`Fold` publishes the predicate, the two-way pick that hangs off it, and the decorator. It
does **not** gain material construction — 0074's refusal of that stands, unamended.

Status: accepted (2026-08-27). **BUILT** 2026-08-27 in four commits on
`refactor/render-system-on-main`. Verified 2026-08-28 — decisions 1–13 all built. Amends
[ADR-0074](0074-display-space-fold-is-a-material-contract-not-a-module.md)'s *Considered
options* (which names this candidate by name and rejects it) and `CONTEXT.md`'s **Fold**
entry (whose *"the only fold code is a thin `Fold.add` decorator"* stopped being true).

## Context

**The predicate was duplicated at fourteen call sites across thirteen files.** Seven in
production (`EffectCallback`, `UI3Element`, `DetailScene`, `UIUnitNameplate`,
`FormationScene`, `DamageNumber3D`, and `TileCursor` inside
`addons/exmateria_battlefield/`), five in `tests/`, and two in one `tools/` script that
copied it twice. Every copy was `get_node_or_null("CompositorAutopilot")` followed by a
duck-typed `ap.owns_compositing()` on an untyped `Node`.

**That duplication is not what ADR-0074 saw.** 0074 landed **2026-07-28**, when exactly
one copy existed (`EffectCallback`, 07-27). The rest accreted after it: `DamageNumber3D`
07-29, `FormationScene` 07-30, `DetailScene` and `UIUnitNameplate` 08-04, `UI3Element`
08-11, `TileCursor` **08-26**. This is new evidence, not a re-argued position.

**The predicate has no host state in it.** `CompositorAutopilot.active` is written in
exactly one place, from `RenderingServer.has_method("is_compositor_layer_supported") and
RenderingServer.is_compositor_layer_supported()`. Nothing else ever writes it, including
the probes that stand the autopilot down. So a kernel-side `Fold.owns()` querying
`RenderingServer` directly is not merely equivalent to `owns_compositing()`, it is
**identical in every reachable state**.

**`native_blend` does not enter it.** The Effect Studio's compare toggle reaches only
`EngineFoldCompositor` (via `CompositorAutopilot.set_native_blend`), and no producer
consults it. The two questions were never conflated in the code, and are not merged here.

**An addon reached a host autoload, and the guard is blind to it.** `TileCursor` named
`CompositorAutopilot` — a `src/effects/` autoload — from inside
`addons/exmateria_battlefield/`. `tools/check_addon_portability.py` matches a bare
`Name.`, so the `get_node_or_null("Name")` route is invisible to it and goal #5 read clean
over a real reach. Confirmed as the only such reach: of the 26 host autoload names, the
other addon hits name their **own** addon's autoloads.

**Four of the fold/fallback twin pairs were one word apart.** Comments stripped:

| pair | differing lines |
|---|---|
| `effect_fold_add` / `effect_native_add` | **1** — `compositor_layer` on the `render_mode` line |
| `effect_fold_sub` / `effect_native_sub` | **1** — same |
| `effect_fold_mix` / `effect_native_mix` | **1** — same |
| `effect_callback_fold` / `effect_callback_additive` | that word, plus a constant renamed on one side only: `PSX_FOLD_GAIN` vs `PSX_OUTPUT_LEVEL`, both `2.2` |
| `formation_box_fold` / `formation_box` | **3** — and they are in different colour spaces |
| `formation_shadow_fold` / `formation_shadow` | **4** — fold writes `DEPTH`, scene sets `depth_test_disabled` |
| `formation_orb_rim_fold` / `formation_orb` | **10** |
| `feedback_hud_sprite_additive_fold` / `feedback_hud_sprite_additive` | **17** |

The formation split is load-bearing and is not a flag: the fold twin adds raw
display-space colour (`clamp(c.rgb * brightness)`) and joins the OT depth ladder; the scene
twin does the sRGB round-trip (`quantize5(pow(c.rgb, psx_gamma) * ...)`) and opts out of
depth with `depth_test_disabled`. A `pow` on the fold side is the gold-box bug
`tools/check_no_pow_in_fold.py` exists to prevent.

**The stub pattern already shipped.** `cursor_fold_{add,mix,sub}.gdshader` are three code
lines each — a `render_mode` line and `#include "cursor_fold.gdshaderinc"`. `render_mode`
is compile-time, so two files is the floor; the `effect_*` set was paying nine lines each.

## Decision

**1. `Fold.owns() -> bool` is published by the kernel.** A `static` on
`addons/exmateria_schema/compositing_key/Fold.gd`, querying `RenderingServer` and caching
in a tri-state `static var` on first call — the same snapshot `CompositorAutopilot._ready`
takes. The kernel is the right home on three counts: it makes `TileCursor`'s reach a
permitted sibling-addon edge rather than a foreign-autoload name; it is available to the
`tests/` copies without an autoload booting; and it is honest about what the value is, a
property of the **build**, not of the game.

   The predicate carries **no tree dependency**, and a caller that needs one carries its
   own. `UI3Element.z_for()` learned this the expensive way: the copy it replaced opened
   with `if not is_inside_tree(): return false`, the migration dropped that as *"a tree
   dependency the question never had"* — true of the *question*, false of the *caller* —
   and `z_for()` began answering off-tree calls with a real rung Z instead of
   `Vector3.ZERO`. The guard is restored at the call site, written as two questions with a
   comment saying which is which.

**2. `Fold.shader(folded: Shader, fallback: Shader) -> Shader`.** It takes `Shader`
objects, never paths, so the kernel touches no filesystem and can name no host file in any
form. Callers hold `preload`ed consts. This is deliberate over a path-taking variant: a
`load()` on a mistyped path returns `null`, and in this subsystem a null shader means the
fold *"just stops, with no error"* (`tests/FoldSurfaceTest.gd` records the hazard by
name). `preload` makes the same typo a parse error.

   Not every producer has two shaders to pick between. `TileCursor._setup_outline_producer()`
   spells the same decision as an early `return`: it has no in-scene fallback and simply
   draws no outline off-fork. That is a producer's own call, not a third spelling of the
   pick.

   **This decision's scope is the PICK.** Its reasoning has two independent legs and only
   one of them is: *kernel purity* is a fact about `Fold.shader`'s signature, while *the
   silent null* is true of any `load()` of a fold shader, on a pick or not. Dec. 11 is the
   second leg's own rule; a const that is not on a pick answers to that decision, not this
   one.

**3. `CompositorAutopilot.owns_compositing()` is DELETED, not forwarded.** All fourteen
sites move in one commit. A forwarder would leave two names for one fact and the next
author would copy whichever they found first, which is how one copy became fourteen.
Deleting it makes a missed site a parse error rather than a silent fallback.

   `CompositorAutopilot` keeps its **own** `RenderingServer` query, and deduping it onto
   `Fold.owns()` is forbidden. It is not the deleted method coming back — `active` has one
   reader outside that file, `tests/FoldTest.gd`, which exists to compare it against
   `Fold.owns()`. One test reading a value in order to *check* it is the opposite of
   fourteen producers reading it in order to *route* on it. The local query is the second
   independent evaluation that assertion needs: it was briefly rewritten to
   `active = Fold.owns()`, which turned the assert into `x == x` — seeding `owns()` to
   return the wrong answer left that line green while three others went red. Two paths, or
   no oracle.

**4. There is no `Fold.material()`. REFUSED on a measurement.** Of the **16** shaders
declaring `compositor_layer`, **six** are mechanical enough for a factory: two triplets,
`cursor_fold_{add,mix,sub}` (3 code lines each) and `effect_fold_{add,mix,sub}` (4). The
other **ten** carry the producer's own fragment body — `feedback_hud_sprite_additive_fold`
66 code lines, `formation_band_fold` 52, `effect_callback_fold` 30, `formation_orb_rim_fold`
24, `crystal_fold` 21, `formation_shadow_fold` 19, `changejob_cylinder_fold` 16,
`tile_decal_fold` 14, `formation_box_fold` and `formation_box_sub_fold` 12 each. A factory
would also have to take `texture`, `palette_texture` and `palette_rows` across the seam to
configure what it built — data the fold has no business knowing.

   The refusal does **not** rest on that minority, which at six-of-sixteen is too thin to
   carry it. It rests on **where the mechanical six already share their body**: dec. 6
   folds each triplet into one `.gdshaderinc` — `cursor_fold.gdshaderinc` and
   `effect_particle_fold.gdshaderinc` — so the duplication a `Fold.material()` would
   collapse is already collapsed, one layer down, in the language the shared thing is
   written in. A GDScript factory would deduplicate nothing that is still duplicated, and
   would buy that nothing at the price of a `res://`-holding kernel dec. 5 refuses on its
   own grounds. ADR-0074's *"material is producer-owned"* is upheld, not amended.

**5. There is no registry. REFUSED on two grounds.** A `Fold.register(key, fold, fallback)`
table would make the kernel hold `res://` paths pointing into `src/ui3/shaders/`,
`assets/shaders/` and a sibling addon — which `check_addon_portability.py` forbids
outright — and it would introduce a startup ordering requirement whose failure mode is a
missing registration presenting as *"the effect silently vanished"*, the exact bug class
this subsystem keeps producing. The stateless picker has no table, no lifecycle, and no
state. The inventory of everything that folds already exists, derived from the shaders
themselves, in `tools/check_compositor_routing.py` — a source a producer cannot forget to
join.

**6. The six `effect_fold_*` / `effect_native_*` entry shaders are stubs over one shared
include**, on the `cursor_fold_*` pattern — four code lines each (`shader_type`,
`render_mode`, `#define EFFECT_STP_ALPHA`, `#include`) — and the `PSX_FOLD_GAIN` /
`PSX_OUTPUT_LEVEL` rename drift between `effect_callback_fold` and
`effect_callback_additive` resolves to one name. The `#define` carries **no `#ifndef`
default**: a stub that forgets it must fail to compile rather than silently take someone
else's blend, which is the silent-wrong-frame class decs. 2 and 3 are both written
against.

   The drift rule is a **twin-pair** rule, and `crystal_fold`'s `PSX_FOLD_GAIN` is
   therefore not renamed: it is a lone shader with a shader-local const and no twin to
   diverge from, and the name is cited by `tools/check_no_psx_brightness_in_fold.py`'s own
   exemption comments.

**7. The formation fold/scene pairs stay two shaders**, per the colour-space measurement
above. So do `feedback_hud` and `formation_orb_rim`.

**8. The carrier-triplet const blocks stay where they are.** `EngineFoldCompositor`'s and
`TileCursorCompositor`'s select on `native_blend` and on blend mode, not on `Fold.owns()`.
Different question, different owner, untouched. They are `preload`ed `Shader` objects
under dec. 11 — the same blocks, selecting on the same question, holding a different type.

**9. The guards are unchanged — none is retired and no guard line is deleted.** They scan
shader source, and producers still author shader source. Only the *routing* is centralised;
the colour-space, PAR, depth, prim-kind and tonemap contracts are not. Recorded because
the architecture review that produced this ADR claimed otherwise, and the claim was wrong.
The count goes 13 → **14**, the addition being dec. 11's.

**10. One `tests/FoldTest`** covers `owns()`, **both** branches of `shader()`, the
`Fold.add` contract, and dec. 12's off-fork no-op. The two `Fold.add` assertions duplicated
verbatim in `tests/CallbackFoldRoutingTest.gd` and `tests/FormationFoldRoutingTest.gd` left
those files; a third copy in `tests/FeedbackHudFoldRoutingTest.gd` was found after the fact
and is **#649** rather than a silent extension of this decision. The three producer tests
(`TileCursorCompositorTest`, `TileOverlayCompositorTest`, `CrystalSpriteCompositorTest`)
are not touched — they assert geometry baking and carrier construction, not routing. The
*"declares `compositor_layer`"* assertions stay in the tests even though a guard also scans
for it: the static scan *"can only locate, not prove"* for scene meshes, so the file saying
the word and the live material carrying it are two claims.

**11. A fold shader named from GDScript is a `preload`ed `Shader`, whether or not it sits
on a pick.** This is dec. 2's *silent null* leg, scoped to the hazard rather than to the
signature. Nine paths across six files answer to it: `EngineFoldCompositor` (3, plus its 3
`effect_native_*` twins — not fold shaders, but `_make_mat` takes one type and a
half-`String` half-`Shader` block is the drift dec. 6 fixed one layer down),
`TileCursorCompositor` (3, via its `MODE_SHADER` table), `TileOverlayCompositor`,
`CrystalSpriteCompositor`, and both capture probes. Producer tests consuming those consts
read `.resource_path`, or better, assert **identity** against the const itself.

   The hazard is the untyped `load()`, not the file extension: `EquipPickerMenu` reached
   its producer through `load("res://src/ui3/UIVitalsBand.gd")`, and an untyped `load()` of
   a *script* defeats the parser exactly as one of a shader path does — dec. 13's arity
   change would have been a runtime error at that one seldom-walked call site rather than
   the parse error the other three callers gave. It is a `preload`ed const now.

   `tools/check_fold_shader_preload.py` is the guard. It reads which files declare
   `compositor_layer`, then asks who names them from GDScript, failing on any
   `res://….gdshader` literal outside a `preload(...)`. It is seeded on the **shaders**,
   not the predicate, so a producer that never mentions the fold is visible to it — the
   exact gap that hid `UIVitalsBand` from three reviews. It scans `tools/` and `tests/` in
   addition to `walk_roots()`, because both capture probes live outside the walk roots and
   a guard blind to them would read clean over a real reach.

**12. `Fold.add` no-ops when `owns()` is false**, decorating nothing at all, not even the
`material_override`. Off-fork the decorator does not quietly do nothing: `render_layer` and
`render_layer_order` are **fork-only properties**, so the assignments *raise* and abort the
caller. Two production paths reached them ungated — `CrystalSprite3D._publish`, every frame
from `_process`, and `Tile.gd` → `TileOverlayCompositor.register`, which gates on **blend
mode** rather than on the predicate.

   The gate belongs to the kernel rather than to those two call sites, on dec. 3's own
   reasoning: two spellings of one fact is how one copy became fourteen. `Fold` published
   `owns()`; a decorator that throws on the one build state `owns()` exists to describe is
   the kernel handing that property back to every caller to remember. Off-fork a producer
   draws its in-scene fallback (dec. 1) and decorates nothing.

**13. A producer asks the predicate itself; it is not handed the answer.** `Fold.owns()` is
cached and free, so passing `folded` down as a parameter buys nothing and costs the thing
this ADR exists to protect: a parameterised producer proves its own ternary but cannot
catch a producer that asks the predicate **wrongly at its real call site**, which is the
failure mode. Where an off-fork branch needs exercising, the seam is the kernel's
`Fold._owns_cache` under a mutate-and-restore lever — precedented by `FoldSurfaceTest` on
`FoldSurface.quantize_levels` — not a producer parameter.

   `UIVitalsBand.build()` is the case that set the rule. It was the fifth producer, and it
   was invisible to every census this ADR ran, because each was seeded on the *predicate*
   (`owns_compositing`, `_fold_owns`, the autoload name) and `UIVitalsBand` never named it
   — it received the answer. The pick and the predicate are two different populations, and
   counting one does not count the other.

## Considered and rejected

- **A path-taking `Fold.shader(folded_path, fallback_path)`.** Rejected on the null-shader
  hazard in dec. 2: `load()` of a typo returns `null` and the fold stops silently, where
  `preload` of a typo is a parse error. Seven sites already precedented the preload,
  including `TileOverlayConfig`, which preloads a whole mode→shader table.
- **A forwarder from `CompositorAutopilot.owns_compositing()` to `Fold.owns()`** — see
  dec. 3. Two names for one fact reproduce the original defect.
- **`folded` as a producer parameter, kept as a test seam for the off-fork branch** —
  *(shipped, reversed 2026-08-28: all four of `UIVitalsBand.build()`'s callers passed
  `Fold.owns()` and no test ever passed `false`, so the parameter had exactly one reachable
  value and the fallback half was untested through it and unreachable without it.
  Superseded by dec. 13.)*
- **Deduping `CompositorAutopilot`'s own feature detect onto `Fold.owns()`** —
  *(shipped briefly 2026-08-27, reversed the same day: it turned `FoldTest`'s oracle assert
  into `x == x`. Superseded by dec. 3.)*
- **Gating `Fold.add` at its two ungated call sites instead of in the kernel.** Rejected in
  dec. 12. It was first proposed on a different benefit — that self-gating would delete the
  local `folded` at `_build_cell_orb` and `_build_one_box` — and that benefit is **nil**,
  measured across all fifteen production `Fold.add` sites: five are `if folded: … else:
  render_priority = …` where the `else` needs the predicate, two read the local elsewhere,
  four ask as one conjunct of a re-enrol guard, and four are unguarded. Zero locals are
  deleted. The decision is taken on the raise, not on the tidy-up.
- **An `#ifndef` default for `EFFECT_STP_ALPHA` in the shared include.** Rejected in
  dec. 6: a default lets a new entry that forgot the `#define` compile clean and render at
  the wrong alpha forever.
- **A deep `Fold` module owning material choice + attach + stamp** — ADR-0074's Candidate 1,
  rejected there and re-refused here in decs. 4 and 5.

## Relationship to ADR-0074

0074's *Considered options* rejects **"a deep `Fold` module owning material choice + attach
+ stamp (the architecture review's Candidate 1)"**, on the reasoning that *"material became
producer-owned and ordering became `DepthMode`'s"*.

That reasoning is untouched and this ADR takes none of those three. Attach and stamp remain
`Fold.add`'s and `DepthMode`'s. Material construction is refused outright in dec. 4, on a
measurement 0074 did not have. What is taken is a boolean 0074 assessed at one caller —
implicitly, since it does not discuss the predicate at all — and which had reached fourteen,
across thirteen files.

The amendment to 0074 exists so that a future reviewer reading its rejection list finds the
correction there, rather than re-rejecting a narrower proposal on a wider ADR's reasoning.

## Consequences

- `Fold`'s published surface is three symbols, not one. `CONTEXT.md`'s **Fold** entry no
  longer says *"the only fold code is a thin `Fold.add` decorator"*.
- One foreign-autoload reach leaves `addons/exmateria_battlefield/`. The
  `check_addon_portability.py` blind spot that hid it is **not** fixed here — the guard
  still cannot see a `get_node_or_null("Name")` route. Filed as **#648**.
- Six `.gdshader` files are stubs; the count of files declaring `compositor_layer` is
  unchanged at **16**, because `render_mode` is compile-time.
- The *call* count rose (14 asks → ~48) and that is the honest number: removing six private
  wrappers turns one indirect ask into the direct asks it was fanning out to. What went to
  zero is the thing that was actually duplicated — the six-line reach, and the wrappers.
- `FormationScene.FOLD_PRIMS` still carries a `band` entry with no production consumer: the
  band's real pick moved into `UIVitalsBand` at the 2026-08-05 element extraction and
  nobody removed the entry behind it. It is **not** a second spelling of the pick
  (`fold_shader_for` *is* `Fold.shader`, fed a per-prim table), but it is a dead pick kept
  alive by its own test. Ticketed as **#655** rather than deleted here, because the
  "exactly six prims" assertion is a documented invariant and dropping to five is a
  decision about what a formation prim *is*.

## Not claimed

- No guard is retired and no guard line is deleted.
- The 16 producers still each restate the fold's shader-side contract. This ADR addresses
  the GDScript routing only; the shader-side contract remains a text convention policed by
  grep, and that is a separate, unsolved problem.
- Not "no behaviour changes". `Fold.owns()` returns what `owns_compositing()` returned in
  every reachable state, and that half holds — but dec. 1's `z_for()` regression and
  dec. 12's off-fork raise are both real behaviour changes, in opposite directions. The
  predicate's equivalence was never the whole claim.

## Verification

- `tests/FoldTest.gd` is the kernel's spec, in five sections: `owns()` against the
  independent `CompositorAutopilot.active` oracle (dec. 3), both branches of `shader()`,
  the `Fold.add` contract, and `add()`'s off-fork no-op (dec. 12). Section 5 is pinned
  under the `_owns_cache` lever, which is load-bearing there in a way it is nowhere else:
  the suite runs on the fork, where the assignment would have *succeeded*, so the untouched
  `material_override` is what proves `add()` **declines** to stamp rather than that the
  engine refused it.
- `tests/FormationFoldRoutingTest.gd` and `tests/CallbackFoldRoutingTest.gd` own *routing*
  — which shaders each producer declares — not the decorator contract. Formation's fifth
  section drives `UIVitalsBand.build()` under both snapshots (dec. 13) and asserts what
  only the producer can do off-fork: `render_priority` carrying the rung, and the holder
  sitting flat at z=0. Three seeds fire disjointly — `folded := true` reds the two off-fork
  arms, forcing the pick reds the shader-identity arm, deleting the `Fold.add` call reds
  the fork-side enrolment arm.
- `tools/check_fold_shader_preload.py` (dec. 11) was seeded six ways and behaved on all
  six, including on `UIVitalsBand`'s original shape — the defect that took three reviews to
  find — where it fires on the fold path and not on the in-scene twin. A `#` comment and a
  `# fold-shader-preload-exempt:` marker are both silent, and a reverted `tools/` probe
  outside `walk_roots()` still fires.
- `tests/ShaderCompileTest.gd` and `tests/FoldQuantizePolicyTest.gd`, plus the three fold
  guards `tests/run_all_tests.sh` invokes, gate dec. 6. That the `#define` reaches the
  shared include was proved by seeding it broken and watching `effect_fold_mix`, and only
  it, fail to compile — *"ShaderCompileTest passes"* would have been equally true of a
  silently-ignored define.
- Dec. 12's raise was measured with a two-arm control: on stock 4.7.1, in a throwaway
  project, `mi.render_layer = null` gives *"Invalid assignment of property or key
  'render_layer' … on a base object of type 'MeshInstance3D'"* and aborts the caller, while
  the identical script survives on the 4.8 fork. The control arm is what makes the stock
  result mean anything.
