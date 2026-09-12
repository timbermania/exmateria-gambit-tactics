# The shared kernel is enumerated by the schema list, not by a property of files

The kernel admits a file only when that file realises a **named published
schema**. Adding a member therefore means adding a schema first — two named
systems and a payload, an ADR act — which is what stops a shared kernel from
becoming a junk drawer. Two mechanical vetoes back the gate: a member has **zero
outbound edges** into any system, and a member is **never an autoload**. Within
a member, code is admissible when it is computation *both sides must perform
identically* — the codec — and not when it decides *which* or *when*.

Status: accepted (2026-08-21). Gives
[ADR-0121](0121-systems-land-in-addons-src-only-shrinks.md) dec. 5's shared
kernel an owner, a slot, a name and an admission test; amends its dec. 6;
corrects [ADR-0118](0118-payloads-are-schemas-services-are-ports.md) dec. 1's
count and closes its open `infrastructure`-addon alternative; splits
[ADR-0129](0129-the-fold-is-renders-and-a-producer-keeps-its-shader.md) dec. 4's
shader library; corrects [ADR-0138](0138-a-publish-does-not-imply-an-assembler.md)
dec. 6's ordinal. Resolves
[#334](https://github.com/timbermania/fft-monorepo/issues/334) on blueprint map
[#305](https://github.com/timbermania/fft-monorepo/issues/305).

All figures measured on trunk `ffa42e0ad` with `classify_blueprint.py` at
`8c19a4d3f`, **2026-08-21**. Per ADR-0131's fourth amendment, both are named
because either alone moves the numbers.

## Context

ADR-0121 dec. 5 has always required the shared kernel be *"built before any
extraction"*, and ADR-0138 dec. 8 made that load-bearing rather than tidy:
#306's *"extraction order is free"* is conditional on the addon existing. Bind
`Effects` to `Fold` while `Fold.gd` still sits inside a `Render` addon and seven
systems hard-depend on `Render`, which must then extract first — exactly the
serialisation ADR-0118 dec. 5 exists to prevent.

ADR-0138 dec. 5 gave the kernel its first four members. What it did not give it
was an owner, a place in the extraction order, a name, or a test for what else
gets in. *"Nothing that is not a payload crossing a boundary"* admits the four
and plausibly a dozen more: `ColorStack` alone is 406 lines with real behaviour.
The live worry the ticket raised was that a computing schema readmits most of
`src/core/`, and the kernel becomes the thing it replaces.

## Decision

**1. The ticket's four-file table holds, and the kernel's true inbound is 46,
not 43.** `DepthMode` 237 / `ColorStack` 406 / `Fold` 33 / `ColorRecipe` 210 =
**886 lines**, and 43 edges from outside `Render` — reproduced exactly (42 from
the ten other systems, plus one from an assembler). The extra
three are `Render`'s **own** runtime: `EngineFoldCompositor` → `DepthMode`,
`EngineFoldCompositor` → `Fold`, `FoldSurface` → `Fold`. ADR-0138 measured
*inbound to `Render` from elsewhere*, a frame that structurally cannot see them.
They are not an error — they are dec. 5's argument in its strongest form, the
provider depending on the same encoding its consumers do. **Report 46.**

**2. The kernel is the third-largest shared surface, not the largest.** Five
things the eleven systems reach that are not each other. One definition
throughout: **edges from the eleven blueprint systems, excluding the surface
itself.**

| shared surface | edges from the eleven systems | largest single member |
|---|---|---|
| `Debug` | **88** | `DebugConfig` 55, autoload, from 7 systems |
| `platform` | **50** | `Tune` 42, autoload, from 10 |
| **kernel** (`schema`) | **45** (46 counting the one assembler edge) | `DepthMode` 19, from 6 |
| `content` | 39 | `JobDatabase` 20, from 7 |
| `infrastructure` | **3** | `UserSettings` 2, `ValidationUtils` 1 |

`DebugConfig` alone outreaches the entire kernel, and `Tune` alone nearly equals
it. Any admission test that ranks by reach admits `Debug` first and `Tune`
second, which is the reductio: **reach is not the test.**

The ranking is definition-sensitive and that is worth stating once. Drop `Debug`
as a *source* and `platform` falls to 30, below the kernel — which is how an
earlier pass of this same measurement read it. Neither reading changes dec. 3;
both refute a reach threshold.

> **Corrected by [ADR-0140](0140-debug-is-a-system-and-a-system-logs-itself.md)
> dec. 1 + dec. 3 (2026-08-21): `Debug`'s row is wrong, and the definition was
> not the reason.** The `Debug` bucket held 30 per-system panels that
> `classify_blueprint.py` intended to book to their own systems and could not — a
> stale `"DebugPanel"` entry in `DEBUG_HOST`, matched as a substring, shadowed 19
> of 30 `DEBUG_OWNER` rules. Re-measured from the corrected bucket, on the same
> definition stated above: **`Debug` is 160 edges, not 88** (`TuneField` 58 from
> 9 systems · `DebugConfig` 57 from 7 · `BaseDebugPanel` 37 from 9 · `GameLogger`
> 4 · `DebugOverlay` 4), and `Debug` is **15 files / 2,884 lines**, not 45 /
> 6,911. `platform` reads 49 and the kernel 45 on the corrected classifier.
>
> **Dec. 2's conclusion is unaffected and dec. 3 stands** — the correction makes
> `Debug` a *larger* outlier, so *"rank by reach admits `Debug` first"* is more
> true, not less. But the general lesson is stronger than the one recorded here:
> beyond being definition-sensitive, **a bucket hides every edge that crosses
> inside it**, so a surface's measured reach is a floor whose slack is exactly
> its mis-filed membership. `Debug`'s *outbound* count is the same finding from
> the other side — 34 before, **0** after, because all 34 were panels.

**3. The admission test is membership in a named published schema.** It is not a
new rule — ADR-0121 dec. 5 already says the addon is for *"the published
schemas"*, and this decision only makes that the *whole* of the test. A file
enters the kernel when it realises a row of ADR-0118 dec. 1's table, and by no
other route. The anti-junk-drawer mechanism is that **the list is the gate**: to
add a member you must first add a schema, which means naming a payload and the
two systems it crosses between, in an ADR. A file move cannot do it.

**4. Two mechanical vetoes back the gate, both checkable by `touch_matrix.py`.**

 **(a) The sink veto — a member has zero outbound edges into any system,
 `content` or `platform` bucket.** Measured, the kernel's outbound edge count is
 **0**: none of the four names anything in `src/`, and `Fold`'s only outbound
 reference at all is `preload("res://assets/fold_layer.tres")`. This is what
 makes the kernel safe for every addon to depend on — a member that reached into
 a system would drag that system behind every consumer and reintroduce the
 serialisation the kernel exists to prevent. It bites immediately:
 `Character.gd`, the only code candidate for the **character records** schema,
 fails with three (`GambitList`, `UnitProgression`, `JobDatabase`).

 **(b) The autoload veto — a member is never an autoload.** All four are
 `class_name` types; three are static functions and constants, one is a
 `RefCounted` the consumer instantiates. The kernel installs nothing into the
 host. An ambient global you ask for an answer is a **port** by ADR-0118 dec. 2,
 and ADR-0121 dec. 5 already excludes ports. This is what keeps `Tune` (42 edges
 from 10 systems) and `DebugConfig` (55 from 7) out on principle rather than on
 taste, and it is why the two *largest* shared surfaces in the repo are not
 kernel problems at all.

**5. Yes, a schema may compute — exactly the computation both sides must perform
identically.** `ColorStack`'s 406 lines are the **codec**, not policy. The
byte-exact DDA and the bounded uniform packing exist because
`psx_color_stack.gdshaderinc` unpacks precisely what `_pack` writes —
`color_layer_rgb0` / `rgb1` / `meta` / `count` — and `ColorStackGpuParityTest` is
the byte-exactness regression that would fail if either half drifted. What a
member may **not** compute is which recipe, or when: that is the driver's, and
`ColorStack`'s own docstring already says so (*"Drivers (ScenarioVM,
EffectTimeline) are thin: they push layers and evaluate"*). The sink veto is the
enforcement rather than taste — policy needs a system to decide against, so
policy cannot pass dec. 4(a).

**6. The fear that the kernel becomes `src/core/` is refuted by the
instrument.** `src/core/` is already dissolved, and only three of its ten files
land in the kernel:

| `src/core/` file | bucket |
|---|---|
| `ColorStack`, `ColorRecipe`, `DepthMode` (853) | **kernel** |
| `PSXDisplay` (254) | `Render` — and a **port** (ADR-0138 dec. 2) |
| `Tune` (543) | `platform` |
| `UserSettings`, `AssetManifest`, `ValidationUtils` (249) | `infrastructure` |
| `MapIlluminationDDA` (129) | `Battlefield` |
| `EventBus` (39) | `DELETE` (ADR-0118 dec. 7) |

The kernel is an **enumerated** category, not a residual one. `src/core/` was
residual — that is precisely the difference, and the classifier already
demonstrates it: the seven non-kernel files have named homes that were decided
without reference to the kernel.

**7. The shader library splits 2/3 on the same test, and the two codec halves
move with their `.gd` halves.** `psx_ot_depth.gdshaderinc` (90 lines) re-declares
**every** `DepthMode` calibration constant as a uniform default —
`0.19`, `0.13`, `0.05`, `0.05`, `-0.02`, `0.9999`, `0.9990`, `0.0001` — and
re-implements `ot_depth`. `psx_color_stack.gdshaderinc` (87 lines) declares
exactly the four uniform arrays `ColorStack` packs. Each is **one encoding in two
languages**, and splitting a codec across two addons makes drift invisible in
the one place a parity test currently catches it. They go in the kernel, and
their guards — `tools/check_depth_shaders.py`, `tools/check_color_shaders.py` —
travel with them.

The other three stay `Render`'s, and pass the same test cleanly: they have **no
CPU counterpart** and nothing agrees across them. `psx_par` is anchor space,
which ADR-0129 dec. 5 already ruled a library entry rather than a key field;
`psx_dither` and `psx_screen_blend` are techniques. Shared implementation is not
a crossing.

Measured today under ADR-0129 dec. 4's convention (`.gdshader` entry points,
`tests/` excluded): `ot_depth` **16**, `par` **11**, `screen_blend` **4**,
`color_stack` **3**, `dither` **1**. Counting every `#include` site including
`.gdshaderinc` intermediates and `tests/`: **21 / 16 / 4 / 5 / 3**. `par` and
`color_stack` each read one above ADR-0129's figure; the convention is named
here so the next reading is comparable.

**Kernel total: 6 files, 1,063 lines** (886 `.gd` + 177 `.gdshaderinc`).

> **Built, corrected and sharpened by
> [ADR-0146](0146-the-kernel-is-built-and-a-codec-is-what-gets-in.md)
> (2026-08-21), the pass that carried this out.** Three corrections and one
> reason.
>
> **The census.** The kernel is **6 files / 1,086 lines** (909 `.gd` + 177
> `.gdshaderinc`) — the `.gd` half drifted 23 lines between this ADR and the
> move. `Fold.gd` was at `src/effects/Fold.gd`, not `src/core/`.
>
> **It is seven things, not six.** `assets/fold_layer.tres` moved with `Fold.gd`
> (ADR-0146 dec. 1). This ADR's table counts source; `asset_census.py` had
> already booked the resource `schema`, and dec. 4(a) named `Fold`'s `preload` of
> it as the kernel's only outbound reference of any kind. Left in the host it
> would be an outbound edge **into the game**, which dec. 10's promotion path
> cannot survive.
>
> **Dec. 7's reason for keeping `psx_par`, `psx_dither` and `psx_screen_blend`
> out is right but soft, and the mechanical form is: a member is half of a
> CODEC.** *"Anchor space"* and *"techniques"* describe what the files are about
> rather than testing them, and the reach evidence pulls the other way —
> `psx_par` is `#include`d by 16 shaders across six buckets and has its own
> guard, the exact profile `psx_ot_depth` has. The test that separates them is
> whether an encoding is implemented **twice**, once per language, such that the
> two must agree: `DepthMode.gd` re-declares all eight calibration magnitudes and
> re-implements `psx_ot_depth()`; `ColorStack._pack` writes exactly what
> `psx_color_stack` unpacks, with a byte-exactness parity test. `psx_par_full`
> and `psx_dither_and_quantize` are implemented **once**, in GLSL, and their CPU
> side is one `global_shader_parameter_set` pushed through a port. **A writer is
> not a counterpart**, so there is no agreement to publish.
>
> **And their bucket is `platform`, not `Render`** (ADR-0146 dec. 4). Dec. 7 was
> written before the walk saw shaders at all (ADR-0144); a display fact six
> buckets include cannot live inside the first system to extract.

**8. Owner and slot: a seventh prologue pass, immediately after the baseline.**
The kernel is not a system, so ADR-0110 dec. 2's unit of work — *a system
extracted outward* — does not fit it and it is not a loop iteration. It is not
carried by the first extraction either: that would mix 1,063 lines of pure
relocation into the first system's measurement, at exactly the moment the metric
is least trusted. And it must **not** precede pass 6, or the baseline records the
post-move state and the largest single relocation in the plan becomes invisible —
the failure ADR-0131's amendments have now warned about four times.

Placed after the baseline it is the instrument's **calibration shot**: a move
with zero behaviour change, zero autoloads dislodged (none of the six members is
an autoload, and dislodging autoloads is the expensive part of ADR-0110's
extraction), and a fully predicted metric delta. Anything the instrument reports
beyond that delta is instrument error, found before a real extraction can be
blamed for it. ADR-0121 dec. 5's *"built before any extraction"* is satisfied:
pass 7 is still the prologue.

> **Renumbered and DONE.** [#310](https://github.com/timbermania/fft-monorepo/issues/310)
> re-ordered the prologue on 2026-08-21, hours after this was written: what this
> decision calls *pass 7* is **pass 6** in `refactor-loop.md` today. It ran on
> 2026-08-21 as [ADR-0146](0146-the-kernel-is-built-and-a-codec-is-what-gets-in.md),
> and **the predicted zero held exactly** — `check_baseline.py --delta` reports
> +0 lines, +0 reaches out and +0 reaches in for all eleven systems, and
> `docs/BASELINE.tsv` did not move. The shot also did the job dec. 8 claims for
> it: it found two instrument defects — the walk did not follow source out of
> `src/` (ADR-0146 dec. 5, half of ADR-0145 dec. 5's hole, arriving a pass early)
> and both seam guards accepted an `#include` naming a path that no longer exists
> (dec. 8) — plus one false residue attribution (dec. 7). All three would have
> been charged to the first extraction.

**9. Name and place: `godot-learning/addons/exmateria_schema/`.** It matches the
one landed precedent, `addons/exmateria_sound/` (ADR-0121 dec. 1), and takes the
classifier's own bucket word. That second property is load-bearing rather than
cosmetic: `classify_blueprint.py`'s four hand-written path rules collapse to one
directory prefix, after which **adding a file to the kernel shows up in the
classifier diff by itself**. Dec. 3's gate stops being a convention someone must
remember and becomes a line in a review.

> **Amended by [ADR-0146](0146-the-kernel-is-built-and-a-codec-is-what-gets-in.md)
> dec. 6: the prefix is the gate for members, and the gate needs one door for the
> doorframe.** `plugin.gd` — the 16 lines that exist so `plugin.cfg` has a
> `script=` — realises no schema, so by dec. 3's own rule it is not a member; but
> the prefix would put it in the bucket that **is** the membership list. One exact
> rule ahead of the prefix books it `infrastructure`, and every *other* new file
> under the addon still trips the prefix and shows up in the classifier diff as a
> kernel admission. The layout landed as **one directory per schema**
> (`compositing_key/`, `colour_model/`), which makes dec. 3's list `ls` and a new
> schema a new directory.

**10. ADR-0121 dec. 7 is unchanged; the kernel is promoted with the first system
promoted, never on its own schedule.** Dec. 7's trigger is a consumer *outside
this repo*. Every addon here is inside it, so extraction changes nothing. When
the first system is released, it cannot depend on a path inside the host — so the
kernel is promoted in the same act, as a dependency of that release. The case
dec. 7 did not consider (a thing every addon consumes from day one) turns out not
to need a new rule: it needs the observation that the kernel is never the *first*
thing promoted, because a package with no consumer is what dec. 7 exists to
prevent.

**11. The kernel is built once from what exists, and grows only inside an owning
system's pass.** Of the seven schemas on ADR-0118 dec. 1's table, exactly **two
have code members today**, and both are already in the bucket:

| schema | code member today | why not |
|---|---|---|
| compositing key | `Fold`, `DepthMode`, `psx_ot_depth` | — |
| colour model | `ColorStack`, `ColorRecipe`, `psx_color_stack` | — |
| effect channels | none | dispatched by hardcoded autoload name (#315) |
| effect log | none | not written yet |
| pose requests | none | untested publish (ADR-0138 dec. 9) |
| character records | none | `Character.gd` fails the sink veto — dec. 4(a) |
| tunable declarations | **none, ever** | realised by a port signature — dec. 12 |

So *"built before any extraction"* means **the addon exists and holds every
schema that has a member** — not that all seven are written. Two thirds of the
kernel being unwritable today is not a blocker; it is a consequence of those
schemas not being explicit yet, and each becomes explicit inside its owning
system's pass, where the context to write it exists.

**12. Tunable declarations is a schema whose realisation is a port's signature,
so it has no kernel member and never will.** The payload is
`(slug, default, type, persist)`; it is published by every system and consumed by
`Debug` (ADR-0113). But `Tune` is a **registry with I/O** — it reads and writes
`res://config/tune_overrides.json`, holds mutable override state and walks
captured stacks — so `Tune.get_value` is a port by ADR-0118 dec. 3's test, and
`TuneField` builds Godot `Control`s, which is `Debug`'s presentation. The
schema's only code artifact is the `Tune.Persist` enum, three values nested
inside the port that consumes them. *(Extended by
[ADR-0140](0140-debug-is-a-system-and-a-system-logs-itself.md) dec. 7,
2026-08-21: `TuneField` is presentation **and** registration —
`TuneField.add()` calls `Tune.bind()` at `TuneField.gd:78`, so one call publishes
this schema through the port and mints a `Control` from `Debug`. That is why a
schema declared memberless still shows 58 edges into `Debug`; splitting the
factory moves them to `Tune`. 121 of 139 call sites go through the one door.)* Hoisting three values into an addon buys
nothing; ADR-0068 keeps it. **This is the first schema shown to be memberless by
construction rather than by not-yet**, and it is why dec. 3's gate is stated as
*realises* a schema rather than *is named by* one.

**13. ADR-0118's open `infrastructure`-addon alternative closes: no.** It was
recorded as *"small enough that an addon may not be warranted… recorded as
open."* Measured, the eleven systems reach `infrastructure` **three times** —
`UserSettings` twice (`Audio`, `Debug`) and `ValidationUtils` once (`Battle`).
Three edges across 141,837 lines does not justify an addon, a `plugin.cfg` or a
promotion path. The three files stay in the host. `AssetManifest` has **zero**
inbound edges from anything at all.

**14. The schema count is seven, and `CONTEXT.md` is missing one.** ADR-0118
dec. 1's table carries seven rows; `CONTEXT.md`'s **Schema** entry says *"Six"*
and lists six — it drops **tunable declarations** and adds the colour model,
holding the count constant by coincidence. ADR-0138 dec. 6 called the colour
model *"the sixth"*, which was the correct ordinal against `CONTEXT.md`'s
five-item list of the day and wrong against ADR-0118's six. It is the
**seventh**. Corrected in `CONTEXT.md` in place; ADR-0118 dec. 1 and ADR-0138
dec. 6 amended.

## Considered alternatives

- **Reach-count thresholds ("anything ≥ N systems reach").** Rejected by dec. 2:
  the ranking puts `DebugConfig` (55 edges, 7 systems) and `Tune` (42, 10) above
  every kernel member, so the test admits the debug autoload before it admits
  `Fold`.
- **The sink veto as the whole admission test.** Rejected: it is a veto, not a
  gate. `JsonAsset` (15 edges from 6 buckets), `PsxNum` (8 from 3),
  `TerrainIndex`, `DisplayActivity` and `AnimationClock` all have zero outbound
  edges and none of them is a payload crossing a boundary. Necessary, not
  sufficient — which is exactly how dec. 4 states it.
- **"A schema may not compute" (data only).** Rejected: it evicts `ColorStack`
  and `DepthMode`, i.e. 643 of the kernel's 886 `.gd` lines, and leaves the
  encoding described by nothing while both halves keep implementing it
  separately. It also makes ADR-0138 dec. 5 and dec. 6 wrong — which was the
  outcome #334 explicitly flagged as possible, and it is not the one measurement
  supports.
- **Keep `assets/shaders/` whole under ADR-0121 dec. 6.** Rejected by dec. 7:
  the kernel would ship a CPU encoder whose decoder lives in a different addon,
  and the eight duplicated `DepthMode` constants would be free to drift across an
  addon boundary. Amending dec. 6 for two files is the smaller cost.
- **Build the kernel before the baseline.** Rejected by dec. 8: it hides the
  largest relocation in the plan inside the reading the whole loop is measured
  against, which is the fourth instance of the failure ADR-0131 dec. 6's
  amendments track.
- **`addons/kernel/` or `addons/fft_schemas/`.** Rejected for `exmateria_schema`
  on dec. 9's second ground: the classifier bucket is already named `schema`, and
  matching it is what makes the admission gate show up in a diff.

## Consequences

- **Prologue pass 7 exists** and `docs/agents/refactor-loop.md` gains it, after
  pass 6 and before the loop. It is the only prologue pass that moves code.
- **The predicted metric delta for pass 7 is exactly zero for the eleven
  systems.** The 46 edges already point at `schema`, and the 886 lines are
  already booked out of `Render` — ADR-0138 dec. 7 did that bookkeeping in
  advance. What pass 7 changes is the *tree*, and the classifier rules collapse
  from four paths to one prefix. Anything else the instrument reports is
  instrument error, which is the point of dec. 8.
- **The shader baseline gap narrows by 177 lines.** Of the 4,304 shader lines the
  baseline still omits, `psx_ot_depth` and `psx_color_stack` now have a named
  owner that is not a system. The remaining 4,127 stay open — separate fog on
  #305, nominal owner pass 6.
- **`Debug` is now the largest unowned shared surface in the plan, at 88 edges,
  and no ADR books it.** `DebugConfig` is 55 of them, reached by autoload name
  from 7 systems. `platform` is second at 50, of which `Tune` is 42 — and dec. 12
  settles what `Tune` *is* without settling where it goes. Whether `Debug` is a
  system that extracts or host machinery that never does is not settled anywhere,
  and dec. 4(b) deliberately declines to make it the kernel's problem. Filed as a
  new ticket on #305.
- **A member can be checked in one command.** `touch_matrix.py`'s cache answers
  both vetoes: outbound edges from the `schema` bucket must be 0, and no member
  may appear in `project.godot`'s `[autoload]` block.
- **Two of the seven schemas remain untested publishes** (ADR-0138 dec. 9), and
  dec. 4(a) now gives one of them — character records — a measured reason it
  cannot enter the kernel as written. That is a fact about `Character.gd`, not a
  re-decision of the schema.
