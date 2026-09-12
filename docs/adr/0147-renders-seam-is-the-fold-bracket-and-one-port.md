# `Render`'s seam is the fold bracket and one port

Extraction #1's scope pass. `Render` extracts as **7 files / 701 lines** — the
pre-transparent fold **bracket** plus the PAR/gamma **port** — and eight files
leave for `Effects` on the way out. Its inbound is one symbol; its outbound into
any system is zero. `Render` does not own a shader library, and it produces
nothing into its own fold.

Status: accepted (2026-08-21). **Built at loop passes 5–9, `e0323e7bf`
([#354](https://github.com/timbermania/fft-monorepo/issues/354)).**

> **Amended by [ADR-0148](0148-a-walk-that-does-not-follow-the-refactor-loses-coverage-silently.md) — four of dec. 9's
> predictions are wrong, and three of them because the table did not apply its own
> prose.** `Render` → systems is **5**, not 0 (dec. 3 reasoned only about
> `ColorTimelineModel` and left out the `Debug` reach this ADR's own audit records
> as 9). Inbound is **28**, not 26, and the published surface is **two** symbols,
> not one — dec. 1 gave the bracket its first inbound edge and dec. 2 did not
> notice. The cross-system total **FELL 11 to 1,132** where dec. 9 predicted a
> rise. Dec. 8's blind spot is real but is worth **2**, not the large hole one
> instance implied, and both are `assembler`-sourced so the printed total never
> moved. Line arithmetic holds; `infrastructure` gains 23 for the addon's
> `plugin.gd`, which dec. 9's *"everything else +0"* did not allow for.

Loop passes 2–4 of extraction #1
([ADR-0141](0141-extraction-1-is-render-and-the-clean-five-is-retired.md)).
Discharges [ADR-0200](0200-the-batch-payload-is-deleted-not-designed.md) dec. 13's
gate (*"pass 6 gates that"* — the prologue is finished at
[ADR-0146](0146-the-kernel-is-built-and-a-codec-is-what-gets-in.md)); builds
[ADR-0111](0111-the-research-vault-is-ballast-not-blueprint.md) dec. 7 as amended
by [#310](https://github.com/timbermania/fft-monorepo/issues/310); corrects
ADR-0141's census; amends `BLUEPRINT.md` §10 and its shader-library paragraph.

Code at `449463b2f`, classifier at `449463b2f`. Per ADR-0131's fourth amendment
both are named, because either alone moves the numbers. **This pass's own edits
add 17 lines to `Render` and change nothing else** — 9 anchor lines (dec. 6) and
8 exemption lines (dec. 7). Every census figure below is the pre-edit reading.

## Context

ADR-0141 chose `Render` and sized it at *"6 files / 905 `.gd` lines plus 139
shader lines"*. That census predates [ADR-0144](0144-the-instruments-see-the-shaders-the-assets-and-the-closure.md)'s
shader walk and [ADR-0140](0140-debug-is-a-system-and-a-system-logs-itself.md)'s
`Debug` re-bookings. **The bucket reads 15 files / 1,163 lines** (9 shader files
/ 258 shader lines). Correcting a prior pass's number is the normal cadence here
— ADR-0146 did the same to ADR-0139's 1,063 — and the conclusion is untouched:
`Render` is still the smallest system and still first.

The scope pass then found that the interesting question is not what `Render`
holds but **what has already been decided about it and never landed.**

## The audit (ADR-0126's six checks)

**1 · The crossings, read as a floor.** `touch_matrix.py` at `449463b2f`, unit =
lines:

| direction | lines | where |
|---|---:|---|
| in, from systems | **27** | `PSXDisplay` **26** (UI 21, Cutscene 2, Battlefield 2, Battle 1) · `ColorTimelineModel` 1 (Effects) |
| in, from `assembler` | 7 | `DisplayDebugPanel` 5, `ShaderCalibrationPanel` 1, `depth_debug.gdshader` 1 |
| out, into systems | **8** | `Effects`: `ColorTimelineModel` → `EffectPhase`/`ScreenData` 2, six carrier shaders `#include effect_particle_stp.gdshaderinc` 6 |
| out, into `Debug` | 9 | `BaseDebugPanel` + `TuneField`, from the two panels |
| out, into `platform` | 17 | `Tune`, from `PSXDisplay` (16) and `DisplayDebugPanel` (1) |
| out, into `schema` | 7 | `Fold` 5, `DepthMode` 1, `#include psx_ot_depth` 1 |

**One symbol carries 26 of the 27 inbound system lines**, and the 27th is a
mis-booking (dec. 3). The floor is real and it is large: `EngineFoldCompositor`
polls `EffectMultiMeshPool` by node **name** and calls
`get_active_effect_buckets` by **string**, then reads a ten-field dictionary and
a five-field run record — the biggest thing `Effects` hands `Render`, worth **0**
of the 1,143. ADR-0137 dec. 12 measured that; this pass adds a **second** blind
spot of the same shape (dec. 8).

**2 · The blueprint's claim about this system, tested rather than inherited.**
`BLUEPRINT.md` §10 gives `Render` a *"shader templating"* Part — *"the generic
`.gdshaderinc` library producers `#include`"* — and names its five entries.
Every one of them is booked somewhere else today:

| library entry | booked | by |
|---|---|---|
| `ot_depth` | `schema` | ADR-0139 / ADR-0146 |
| `color_stack` | `schema` | ADR-0139 / ADR-0146 |
| `par` | `platform` | ADR-0146 dec. 4 |
| `dither` | `platform` | ADR-0146 dec. 4 |
| `screen_blend` | `Cutscene` | classifier, exact path |

**`Render` owns zero library includes.** Its nine shader files are nine concrete
shaders, no includes among them. See dec. 4.

**3 · The muxed slot, and the demux above and below it.** `unified_bytes` is one
flat `PackedByteArray` of stride-24 float records that only `(base, count,
stride)` per run can cut apart, reinterpreted at fixed offsets — `[0..11]`
transform, `[12..15]` `COLOR`, `[16..19]` `CUSTOM0`, `[20]` `level_scale`.
**Both demuxes already exist**: `UnifiedPrimStager` writes the record above, and
the 20-float `MultiMesh` instance layout plus `effect_particle_stp.gdshaderinc`'s
`MODEL_MATRIX` unpack read it below. `EngineFoldCompositor` sits between them
re-cutting a slot neither end needed cut. ADR-0137 dec. 4 already called the
24-float record a fossil.

**4 · Units on every typed payload.** `render_layer_order_for(order_z, rank)`
takes `order_z` in **world units** (view-space Z), divides by
`UNITS_PER_OT_BUCKET = 0.19` world-u/bucket and multiplies by
`RANK_STRIDE = 1024`. The units are declared and consistent. Two soft spots at
the call site, neither a bug claim:

- `run.get("depth", 0.0)` — `0.0` is a **valid `order_z`**, not a sentinel, so a
  missing key folds silently at bucket 0.
- `rank` is `fold_idx`, a counter over **all** runs in the frame against a hard
  bound of `RANK_STRIDE`. The assert is stripped in release; at ≥ 1024 runs the
  key spills into the next bucket. Not reachable at today's
  `WARMUP_TOTAL_SLOTS = 64`, and unclamped.

**5 · Spellings of the contested resource.** The contested resource is the fold
**carrier material**. Sixteen shaders declare `compositor_layer` in
`render_mode` — and that count is itself a trap: a plain grep for the word reads
**31**, because fifteen files only *mention* it in a comment, three of them to
say they deliberately do **not** declare it. By owning bucket, today: `UI` 7,
`Battlefield` 4, **`Render` 3**, `Sprite Rig` 1, `Effects` 1.

**6 · The live set, before quoting any number.** Of the 15 files, `closure.py`
reaches **13 / 1,029 lines** from the ratified eleven-scene root set.
`ColorTimelineModel.gd` (115) is `UNREACHED` — its one consumer,
`EffectTimelineView`, is itself unreached — and `depth_debug.gdshader` (19) is
reached only from a declined scene. `RESIDUE.tsv` already carries both, as `test`
and `declined`; neither is dead and nothing is deleted (ADR-0142 dec. 8).

## Decision

**1. `Render` extracts as the fold BRACKET plus one port, and eight files leave
for `Effects` first.** `EngineFoldCompositor.gd` (208) and its six carrier
shaders (139) go to `Effects`; `ColorTimelineModel.gd` (115) goes with them for a
different reason (dec. 3). What lands in `addons/exmateria_render/` is:

| lines | file | what |
|---:|---|---|
| 263 | `src/effects/FoldSurface.gd` | Pass A/C, the bracket |
| 254 | `src/core/PSXDisplay.gd` | the PAR/gamma port |
| 50 | `assets/shaders/foldsurface_seed.glsl` | Pass A |
| 50 | `assets/shaders/foldsurface_resolve.glsl` | Pass C |
| 36 | `src/debug/DisplayDebugPanel.gd` | a view |
| 29 | `src/debug/ShaderCalibrationPanel.gd` | a view |
| 19 | `assets/shaders/depth_debug.gdshader` | declined; travels, is not deleted |
| **701** | **7 files** (3 shader / 119) | from 15 / 1,163 |

This is **not new** — [ADR-0200](0200-the-batch-payload-is-deleted-not-designed.md)
decs. 1 and 11 decided it and dec. 13 gated the code move on prologue pass 6,
which ADR-0146 finished. Extraction #1 is where it lands, and it is **not
optional for extraction #1**: an addon that reached `EffectMultiMeshPool` by node
name would make `exmateria_render` depend on the game that consumed it. That is
the same sink veto ADR-0146 dec. 1 used to move `fold_layer.tres`, and ADR-0139
dec. 10's promotion path cannot survive it either.

**2. The addon's interface is ONE symbol, `PSXDisplay`, and it is a port.** 26 of
27 inbound system lines land on it, from four systems, and it is `extends Node`
with no `class_name` — an autoload, i.e. a global name, which
`BLUEPRINT.md` says *"can never be a crossing, because an addon cannot ship
`project.godot` entries."* So the extraction's one interface question is the
shape of that port, and everything else that looks like an inbound edge on
`Render` lands on the **kernel** — `Fold`, `DepthMode`, `ColorStack`,
`ColorRecipe` — which `Render`'s own runtime depends on identically (ADR-0138
dec. 2, ADR-0146's *"the provider depending on the same encoding its consumers
do"*).

`FoldSurface` and the two compute stages are named by nothing outside `Render`.
The bracket is 363 of the 701 lines and has **no inbound edge at all**.

**3. The 27th inbound edge is a substring-table defect, and it is fixed at pass 6
with the code, not here.**

> **Amended by [ADR-0148](0148-a-walk-that-does-not-follow-the-refactor-loses-coverage-silently.md) dec. 6.** *"Once
> it moves, `Render`'s outbound into any system is zero"* is wrong: it is **5**,
> all into `Debug`, from the two panels that travelled with the system and still
> `extends BaseDebugPanel` / call `TuneField.add`. The audit table four sections
> above this one records *"out, into `Debug`: 9"* and the Consequences repeat it.
> `Render` → `Effects` **is** zero, which is what dec. 3 actually reasoned about.
> The sink veto holds against every system except the one no ADR has decided about.
>
> The fix landed at pass 6 as written, and the guard forced more than this ADR
> predicted: **all three** `Render` fragments had to leave `DEBUG_OWNER`, not just
> `("Color", "Render")`. `"Display"` and `"Shader"` went SHADOWED — not dead — the
> moment the panels left `src/debug/`, because `UIDisplayDebugPanel` and
> `UnitShaderDebugPanel` are claimed first by `"UI"` and `"Unit"`. `DEBUG_OWNER`'s `("Color", "Render")` books
`src/debug/ColorTimelineModel.gd` to `Render` **on its name**. The file is a pure
projection of an effect's colour keyframes; its only consumer is
`EffectTimelineView` (`Effects`), and its only two outbound edges are
`EffectPhase` and `ScreenData` (`Effects`). It is `Effects`'. This is the third
instance of the shadowing failure ADR-0140 dec. 1 and ADR-0144 dec. 3 each had to
correct once — a substring table is order-sensitive and silent.

Fixing it **now** would move numbers this ADR quotes, which is exactly the
precedent ADR-0141 set with `src/data/`'s directory catch-all: *"fixing it moves
every number and should not ride in the same commit as a decision that quotes
them."* It is booked at loop pass 6, where the booking follows the code
(ADR-0137 dec. 13). Once it moves, **`Render`'s outbound into any system is
zero** — the sink veto, mechanically, as `schema` already reads.

**4. `BLUEPRINT.md` §10's *shader templating* row is empty, and `Render` does not
grow when it extracts.** All five named library entries are booked elsewhere (the
audit's check 2). BLUEPRINT's *"`classify_blueprint.py` walks `src/**/*.gd` only,
so it cannot see any of this and `Render` reads as the smallest system in the
repo until it extracts"* predicted the walk would hand `Render` a library back.
ADR-0144 made the walk see shaders and it handed back **258 lines**; ADR-0146
then distributed the library itself between the kernel and `platform`, for the
reason that a fact six buckets `#include` cannot live inside the first system to
extract. **`Render` is the smallest system, full stop** — and after dec. 1 it is
701 lines, smaller than `Campaign`'s 1,123.

The prediction was sound when written and its premise is gone. The Part is
amended to name what `Render` actually templates: **nothing today**, and the
two compute stages tomorrow.

**5. Four systems produce into the fold, not five — `Render` produces nothing.**
BLUEPRINT §10: *"Five systems produce into the fold — `Effects`, `Battlefield`,
`Sprite Rig`, `UI` and `Render` itself."* The fifth was `effect_fold_{add,sub,mix}`
being booked `Render`, which ADR-0137 dec. 11 had already reassigned. After
dec. 1 the sixteen carriers read `UI` 7, `Battlefield` 4, `Effects` 4,
`Sprite Rig` 1, **`Render` 0**.

That is the right shape and worth saying plainly: **the system that owns the
bracket is not a producer into it.** A renderer that also produced into its own
pass would be the thing ADR-0129 dec. 4's *"a producer keeps its own shader"*
exists to prevent.

**6. The vault anchor is `Vault: [[Note Name]]`, and a guard enforces that it
resolves.** ADR-0111 dec. 7 asked code to cite its vault note in a comment and
never fixed a form; adoption is **0 of 470**, so extraction #1 sets it.
`tools/check_vault_anchors.py` enforces **two** rules and neither is coverage:
an anchor must name a note that exists at `vault/<name>.md` on `main`, and the
string `Vault:` must never appear outside the anchor form (a bare `Vault: Foo` is
a typo a coverage grep misses silently). It walks `classify_blueprint.WALK_ROOTS`,
not a hard-coded `src/`, per ADR-0146 dec. 5.

**Coverage is reported, never asserted.** Adoption is per-extraction (#310), so a
global threshold would be red for months and deleted within a week — ADR-0145
dec. 4's argument for `--delta`, applied again.

`Render`'s scope is **2 notes over 6 files**: `[[Display Space Blend Fold]]` into
`FoldSurface.gd`, `EngineFoldCompositor.gd` and `effect_fold_{add,sub,mix}`, and
`[[Scenario Camera Framing]]` into `PSXDisplay.gd`. Three of those six leave for
`Effects` at pass 6 and **are anchored anyway** — that is the point of anchoring
before anything moves.

Two findings from doing it, both about the seed rather than the anchor:

- **A citation can be a bare basename.** `Display Space Blend Fold` cites
  `` `…/effect_fold_add.gdshader` / `effect_fold_sub.gdshader` /
  `effect_fold_mix.gdshader` `` — one full path and two basenames. A path-only
  scan of the `R:` seed finds **one** of the three files.
- **`.gd` swallows `.gdshader` in a naive alternation.** ADR-0111 counts *"12 …
  a `.gdshader`-cited-as-`.gd` counting artifact"* in the vault; the identical
  artifact is one regex away in any tool that reads the seed, and this pass wrote
  it once before catching it. Order the extensions longest-first.

**7. The two `effect_native_*` shaders the routing guard names are
`compositor-exempt`, and that is not ADR-0137 dec. 10's fix.**
`check_compositor_routing.py` has been red at trunk naming
`effect_native_add.gdshader` and `effect_native_sub.gdshader` — both in
`Render`'s bucket, so extraction #1 owns it. They declare in-scene
`blend_add`/`blend_sub` because that is their **entire purpose**: each is its
`effect_fold_*` twin minus `compositor_layer`, so the muddy native-blend result
can be compared against the display-space fold. Routing them would delete the
comparison. They are the guard's own *"by-decision in-scene material"* case and
they earn its `// compositor-exempt:` marker, which is a different thing from the
`ALLOWLIST` (a burn-down that only shrinks). **The suite is 27 / 27 green** for
the first time in this series.

`effect_native_mix.gdshader` is deliberately **not** marked. The guard never asks
about `blend_mix`, so an exemption there would be inert text that a later reader
mistakes for a needed one. An exemption should be exactly as wide as the defect.

**This does not fix ADR-0141's second soft spot.** `native_blend`'s partiality —
zero of the ten direct `Fold.add` producers consult it, so the toggle puts pooled
particles and trap into native blend while nine other producers keep folding — is
ADR-0137 dec. 10, and its fix is a second read on the `owns_compositing()` port
that **every producer** answers. That touches ten producers in four systems and
is not `Render`'s to do alone. It stays open, and it is now the only part of
ADR-0137 that extraction #1 does not discharge.

**8. A second reach blind spot, recorded with its slot, not fixed here.**

> **Amended by [ADR-0148](0148-a-walk-that-does-not-follow-the-refactor-loses-coverage-silently.md) dec. 2 — fixed,
> and smaller and differently shaped than this reads.** The matrix is not blind to
> `const`; it is blind to **a literal bound to a name before it is used**, because
> shape 1 matches the raw line (so a bare inline `load("res://…")` IS seen) and
> `strip_noncode` blanks string literals before any other shape looks. Measured:
> **196** such declarations, 117 naming a `.tscn` the source walk does not carry,
> 77 same-bucket, **2 cross-bucket** — `CompositorAutopilot.gd:18` and
> `src/ui3/detail/DetailSceneBoot.gd:22`. Both are `assembler`-sourced and
> `assembler` is not one of the eleven systems the matrix sums, so fixing it moved
> the published total by **zero** and extraction #1 carries no instrument
> discontinuity. Extraction #1 also moved the first edge's destination: it is
> `assembler → Effects` now, not `assembler → Render`.
`touch_matrix.py` cannot see a `res://` path held in a `const` and passed to
`load()`. The live instance is `src/effects/CompositorAutopilot.gd:18` —
`const ENGINE_FOLD := "res://src/effects/EngineFoldCompositor.gd"` — an
`assembler → Render` edge worth **0** on all five shapes. `closure.py` **does**
see it, because it scans for `res://` literals rather than for call syntax. **Two
instruments describe the same edge and disagree**, which is ADR-0146's *"when two
registers describe the same set, diff them"* arriving one pass later, and it is
the same root cause as ADR-0137 dec. 12's poll: the matrix tests **call syntax**
where the dependency is a **string**.

It is not fixed here for ADR-0141's reason — it moves the count this ADR quotes —
and it joins the instrument work already owed at loop pass 9: **ADR-0145 dec. 5's
REACH half**, the 22 lines reaching into the extracted `exmateria_sound`
(`Effects` 14, `Audio` 8) that are still counted nowhere. One ADR, measured both
ways, before extraction #1's number is published.

**9. The predicted metric, before building.** Loop pass 3 requires this, so that
a wrong boundary is learned before the work is built rather than after.

| reading | at `449463b2f` | predicted after extraction #1 |
|---|---:|---:|
| `Render` files / lines | 15 / 1,163 | **7 / 701** |
| `Render` shader files / lines | 9 / 258 | 3 / 119 |
| `Render` → systems (lines) | 8 | **0** |
| systems → `Render` (lines) | 27 | 26 |
| distinct inbound symbols | 2 | **1** |
| `Effects` files / lines | 183 / 57,480 | 191 / 57,942 |
| fold carriers owned by `Render` | 3 of 16 | **0 of 16** |
| cross-system total (lines) | 1,143 | **rises** |

**The last row is the prediction that matters and it is deliberately not a
number.** `EngineFoldCompositor`'s poll of `Effects` is worth 0 today; the same
relationship, once the file sits in `Effects` and reaches `Fold` and
`FoldSurface` by `class_name`, is worth +1 to +2 — and the six `#include`s stop
being a crossing because both ends land in `Effects`. Whether the total rises or
falls depends on which of those dominates, and **either answer is the instrument
behaving correctly**: ADR-0131 dec. 6's floor, ADR-0134's 33-verb facade and
ADR-0137 dec. 12 all say the same thing. **The baseline series must not be read
as monotone.** Predicting a direction and not a value is the honest form of this
prediction.

Line arithmetic is a different matter and **is** asserted: `Render` −462,
`Effects` +462, everything else +0, and the package total unchanged. A relocation
that reads as a deletion is the failure ADR-0146 dec. 5 exists to prevent, and
`WALK_ROOTS` gains `addons/exmateria_render` in the same commit that creates it.

## Considered alternatives

- **Keep `EngineFoldCompositor` in `Render` and give the addon an injected pool
  port.** Rejected. It preserves a file that knows ten fields of `Effects`'
  payload, five run fields and the E### palette format, and pays for it with a
  bespoke port for one caller — ADR-0137 dec. 8's objection exactly. The carrier
  build is `Effects` work wherever it is housed.
- **Fix the `ColorTimelineModel` booking in this commit.** Rejected by ADR-0141's
  precedent: it moves every number this ADR quotes. Deferred to pass 6, where the
  booking follows the code and both move together.
- **Fix `touch_matrix.py`'s const-path blind spot now, so extraction #1 is
  measured with a better instrument.** Rejected for the same reason, and for a
  sharper one: changing the instrument *inside* the extraction it measures is the
  instrument-changes-mid-series failure the frozen baseline exists to prevent.
  ADR-0145 gave it a slot; it goes there.
- **Route `effect_native_add/sub` through the compositor to clear the guard.**
  Rejected: they exist to *not* be routed. Routing them makes the guard green by
  deleting the thing it is guarding.
- **Add `effect_native_*` to the routing guard's `ALLOWLIST`.** Rejected: the
  allowlist is an add/sub burn-down that only shrinks, and these are not debt.
  Exemption and allowlist are different claims and the guard already distinguishes
  them.
- **Anchor only the files that stay in `Render`.** Rejected — it inverts the
  whole point. ADR-0112 makes each addon an analog authored fresh, so the anchor
  must exist *before* the code moves, and three of the six anchored files are
  moving.
  > **Amended by [ADR-0154](0154-goal-1-is-about-decisions-and-goal-3-is-about-orphans.md)
  > (2026-08-22, recorded at extraction #2's pass 9): ADR-0112 does not say this** — a
  > sixth site, not in ADR-0154 dec. 1's table. **The rejection stands and its reason is
  > now measured rather than asserted.** Under ADR-0110 dec. 1's lift the anchor on a
  > moving file travels for free, so *this* alternative's premise is the wrong half:
  > anchoring only the stayers fails not because the movers lose their anchors but
  > because the files that were **never anchored** are exactly the ones the extraction
  > makes unreachable to the walk. Extraction #2 measured both halves — **5 anchors in 1
  > file travelled with the lift, and 159 had to be authored** into addon code that
  > predates the refactor ([#404](https://github.com/timbermania/fft-monorepo/issues/404)).

- **Make the anchor guard assert a coverage floor for the system being
  extracted.** Rejected: a floor is a number in prose, and ADR-0145's whole
  finding is that those move without code changing. Coverage is a `--delta`-shaped
  reading, not a guard.

## Consequences

- **`Render` is the smallest system in the package after extraction, not before
  it.** 701 lines against `Campaign`'s 1,123. Extraction #1 is a small move that
  settles a large question, which is what a calibration extraction should be.
- **`Fold.add` is the kernel's, so `Render` publishes no fold interface at all.**
  BLUEPRINT §10's *"Crosses in: … via `Fold.add`, the sole sanctioned entry"* was
  written when `Fold` was `Render`'s; ADR-0146 moved it to
  `addons/exmateria_schema/compositing_key/`. **`Render`'s published surface is
  the port and nothing else**, and the fold's protocol — declare
  `compositor_layer`, join `FOLD_LAYER`, stamp `render_layer_order_for` — is a
  kernel schema three other systems already encode against without naming
  `Render` once.
- **ADR-0137 is discharged except dec. 10.** Decs. 1 and 11 land at pass 6; dec.
  13's gate is spent; dec. 12's prediction is tested at pass 9. Dec. 10's
  `native_blend` port is the residue, and it is `Effects`' pass, not this one.
- **The guard suite is 27 / 27.** It has been 26 with one red since before this
  series began, and the red was in `Render`'s bucket the whole time.
- **`docs/BASELINE.tsv` does not move and the freeze is untouched.** This pass
  adds 17 lines to `Render` (9 anchors, 8 exemption comments) and changes no other
  row; `--delta` reports it, and reports nothing else.
- **Two soft spots at the fold-order call site are now written down** — the
  `0.0` depth default that is a valid value rather than a sentinel, and the
  unclamped `fold_idx` rank against `RANK_STRIDE`. Neither is reachable today and
  neither is fixed here; they belong to the file that is moving to `Effects`.
- **`Debug` is still unowned and this pass did not touch it.** Two of `Render`'s
  seven files are debug panels (65 lines, 9.3% of the extracted system) and
  `Render` reaches `Debug` on 9 lines. ADR-0139 dec. 4(b) declined to make it the
  kernel's problem and no ADR says whether `Debug` extracts. Extraction #1 does
  not need the answer; extraction #2 may.
