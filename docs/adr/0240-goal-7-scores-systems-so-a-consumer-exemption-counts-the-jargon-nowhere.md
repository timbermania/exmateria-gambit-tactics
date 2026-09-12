# Goal #7 scores systems, so exempting a consumer counts the provider's jargon nowhere

The session handoff put three decisions on `Sprite Rig`'s goal #7 and called them
conjunctive: retire the `psx_` prefix across the kernel's `.gdshaderinc` surface (worth 14
of 22 lines), rule whether a **consumer of an exempt system's published vocabulary is
itself exempt** (worth 14–20 with no rename at all), and rule whether `PSX_FOLD_GAIN` may
become `FOLD_GAIN` (the last 2). It named the second *"the highest-leverage claim on the
board"* and said to argue it first.

Measured. **The second decision's premise is false, and granting it anyway would make
those twenty lines countable by no row in the register.** The four files that publish the
symbols are booked to `schema` and `platform`, which are buckets and not members of
`SYSTEMS`, so the publisher is not `Render` and the exemption being borrowed is not the
one row 10 grants. The rename ran instead; goal #7 is 0.

Status: accepted (2026-09-06). Executes
[ADR-0129](0129-the-fold-is-renders-and-a-producer-keeps-its-shader.md) dec. 10, whose
trigger [ADR-0238](0238-a-global-uniform-is-validated-only-in-the-editor-and-the-debt-is-silent.md)
dec. 7 found had already fired twice. Reads
[ADR-0150](0150-psxdisplay-stays-because-render-is-the-playstation-look.md),
[ADR-0145](0145-the-baseline-is-taken-and-the-series-opens.md) dec. 4 and
[ADR-0117](0117-the-blueprints-ten-systems.md) row 10 / dec. 6 for the exemption, and
leaves every decision any of them made standing. Verified under
[ADR-0238](0238-a-global-uniform-is-validated-only-in-the-editor-and-the-debt-is-silent.md)'s
rule that a `global uniform` fails silently.
Tickets: closes the goal-#7 half of #899 and #583's `psx_par` clause; files nothing new.

## Context

### The vocabulary is published where nothing is scored

`Sprite Rig`'s 22 jargon lines name ten things, and eight of them are somebody else's:
`psx_ot_depth.gdshaderinc`, `psx_ot_depth`, the `psx_ot_computed_depth` varying,
`psx_color_stack.gdshaderinc`, `psx_color_apply`, `psx_par.gdshaderinc`,
`psx_par_anchor` and `psx_unit_stretch`. Every one is declared in
`addons/exmateria_schema` or `addons/exmateria_platform`. Only `PSX_FOLD_GAIN`, twice, is
the rig's own.

`score_goals.py` runs `classify()` over those four provider files and gets `schema`,
`schema`, `platform`, `platform`. `SYSTEMS` is the eleven names of ADR-0117, and neither
bucket is in it. The scorecard says so itself, in the line it prints above each of those
two addons:

> `-- addons/exmateria_schema: the classifier books no file here to a system
> (infrastructure, schema, tests); the ten goals score systems, so it is not scored here.`

So a `psx_` name minted in the kernel is charged to nobody at its declaration. It is
charged only where a *system* spells it — which, for these eight, is `Sprite Rig`,
`Battlefield` and `Render` among the extracted addons, plus whichever in-walk systems
carry the spelling out with them when they extract.

### The exemption being borrowed is not the one that exists

ADR-0117 row 10 gives `Render` the subject *"the depth model · colour modes · shader
templating · the fold · display aspect"*, and dec. 6 says *"It is about looking like a
PlayStation, not about tactics."* ADR-0150 turns that into the one entry in
`PLATFORM_EXEMPT`. The handoff's reading is that the depth model and the colour modes are
literally what these eight names encode, so a system consuming them is being charged for
`Render`'s subject matter.

The subject matter reading is right and the addressing is not. Extraction #4's kernel
split moved the depth model and the colour model into `exmateria_schema`, where `Render`
consumes them on exactly the same terms `Sprite Rig` does — `exmateria_render` scored 3
jargon lines of its own, not 20. Row 10 describes a **subject**, and `PLATFORM_EXEMPT`
keys a **system**; after the split those two stopped naming the same set of files, and the
proposed exemption is the gap between them rather than an extension of row 10.

## Measurement

### What the exemption would erase

Under it, each of the eight provider names disappears from every consuming system's count,
and none of them is counted at its declaration because the declaration sits in an unscored
bucket. The count for `Sprite Rig` falls 22 → 2 without a line of code changing, and the
same erasure runs through `Battlefield` and `Render`, and through every in-walk system
that extracts later.

ADR-0145 dec. 4 refuses precisely this shape. Faced with a figure that a real coupling
distorts, it reports it: *"This is **reported and not adjusted for**"*, on the ground that
*"Netting it out would produce a flattering second instrument measuring a different
thing"*. `score_goals.py`'s own comment attaches that citation to the half of the design
it actually supports — *"the count is still reported for an exempt system, never
suppressed (ADR-0145 dec. 4)"*. A consumer exemption is the netting-out, not the
reporting.

It is also the flag ADR-0150's map was built to prevent, in a second language. A per-system
map cannot be acquired silently; an exemption that propagates along `#include` edges is
acquired by an edge, and nobody rules on it.

### ADR-0129 dec. 10 never ran because it was addressed to a path that never existed

dec. 10 reads *"The generic includes drop their `psx_` prefix, and gain no replacement"*
and *"Only `par` wants a longer name (`pixel_aspect`)"*, and defers execution: *"The rename
happens when `Render` extracts, not here"*. ADR-0238 dec. 7 found the trigger had fired and
the work had not moved. The address is why. dec. 10 wrote the destination as
`res://addons/render/shaders/ot_depth.gdshaderinc`; the files landed in
`addons/exmateria_schema/compositing_key/` and `addons/exmateria_platform/pixel_aspect/`,
so no grep for the ruled path ever found the ruled file.

**The CPU half had already run, which is the tell nobody read.**
`DepthMode.ot_depth(point, proj, view, mode)` has carried the un-prefixed name the whole
time — the GDScript port of the same function, in the same directory, one file away from a
shader function called `psx_ot_depth`. `addons/exmateria_platform/README.md` had the other
half of the tell, booking the file rename to #583 by name: dec. 10 *"be honoured by the
address today without renaming the file, which is #583's work"*.

### The rename, and what it moved that a shader grep does not show

`psx_ot_*` → `ot_*` (function, varying, eight uniforms), `psx_color_*` → `color_*`,
`psx_quantize` → `quantize`, `psx_par` → `pixel_aspect` (global uniform, `_full`, `_anchor`,
the `psx-par-exempt` opt-out marker and the file), `psx_unit_stretch` → `unit_stretch`, and
the two kernel includes renamed. Three Tune slugs moved with them —
`render.psx_ot_unit_forward`, `render.psx_par`, `render.psx_unit_stretch` — as did two
`[shader_globals]` keys in `project.godot` and `PSXDisplay`'s
`global_shader_parameter_set` writers.

| addon | before | after |
|---|---|---|
| `exmateria_sprite_rig` | 22 | **0** |
| `exmateria_schema` | 36 | **0** |
| `exmateria_render` | 3 | **0** |
| `exmateria_battlefield` | 118 | **74** |
| `exmateria_platform` | 68 | **41** |

### A textual guard cannot witness this rename, so runtime did

Nine `check_*.py` guards were green before the rename and are green after, and that proves
less than it looks: `pixel_aspect` and `unit_stretch` are `global uniform`s, and ADR-0238
established that a project which has not declared one gets no compile error outside the
editor — the name reads its type's zero and a `pixel_aspect` of `0.0` blanks the screen
with nothing in the log. The witnesses are therefore runtime, and each reads a value back
rather than reading a file: `PlatformProvidesTest` 54/54 over 7 arms,
`PSXDisplaySingleSourceTest` 4/4, `TunePsxParTest` 5/5, `AlignmentPanelTuneFieldTest`
14/14, `UnitMaterialVariantTest` green. For the kernel half, `ColorStackGpuParityTest`
11/11 compiles and renders `color_apply` through the renamed include on the GPU, and
`DepthModeTest` 35/35 holds the CPU twin. `godot --path . --import` is clean and
`score_goals.py` exits 0.

## Decision

**1. A consumer of an exempt system's published vocabulary is NOT exempt, and
`PLATFORM_EXEMPT` keeps its single entry.** Two independent grounds, either sufficient: the
publisher of these names is the kernel and the port, not `Render`, so there is no exemption
to inherit; and an exemption that travels along an `#include` edge is acquired without a
ruling, which is the flag ADR-0150's map refuses and the netting-out ADR-0145 dec. 4
refuses. A future system may still be *argued into* the map — this closes the transitive
route, not the map.

**2. ADR-0129 dec. 10 executes now, re-addressed.** Its destination is
`addons/exmateria_schema/compositing_key/ot_depth.gdshaderinc` and
`addons/exmateria_schema/colour_model/color_stack.gdshaderinc`, not the `addons/render/`
path it wrote. Nothing in dec. 10's reasoning depended on the path; it named `Render`'s
extraction as the trigger and the kernel split is the same event under a different name.

**3. `par` becomes `pixel_aspect` everywhere it is a name**, per dec. 10's one exception —
the global uniform, both helpers, the file, the Tune slug and the `psx-par-exempt` marker,
which is part of the seam's contract and would otherwise name a seam that no longer exists.
The UI half goes with it: `render.psx_ui_par` becomes `render.ui_pixel_aspect`, because a
world PAR called `pixel_aspect` beside a UI PAR called `psx_ui_par` is one concept spelled
two ways, which is the shape this ADR is refusing elsewhere. The one place it keeps the old
spelling is `tests/fixtures/verdict/camera_feel_threw_excerpt.log`, a captured log that is
evidence rather than code.

**4. `PSX_FOLD_GAIN` becomes `FOLD_GAIN`, and the compromise moves into the comment.** The
counter-argument was that the identifier records a PSX compromise. It cannot: the const
lives inside `crystal_fold.gdshader`, a producer whose entire job is a PlayStation
reproduction, so the prefix distinguishes it from nothing in its own file. The four lines
above it already state the fact, and ADR-0149's rule scores prose at zero.

**5. The rest of the platform's `psx_` surface is deliberately left, and this says which.**
`psx_gamma`, `psx_dither_enabled`, `psx_camera_angle`, `psx_sprite_stretch`,
`psx_fx_stretch`, `psx_cursor_stretch`, `PsxNum` and `PSXDisplay` (whose rename is
ADR-0171 dec. 4's) block no goal-#7 row. `gamma` is too generic a name to take as a
project-wide global without an argument, and taking the other three stretches would split
ADR-0044's taxonomy across two spellings for no score movement. `tests/TunePsxParTest`
keeps its name: renaming it invalidates citations in ADR-0171 and ADR-0186 and two test
baselines, and `tests/` is unclassified so it scores nothing either way.

**6. A `global uniform` rename is verified by a runtime read-back, never by a guard.** The
guards are textual and the failure mode is silent (ADR-0238), so "the checks are still
green" is not evidence about this class of change. The port's own tests are the instrument.

**7. Historical records keep their original spelling.** `docs/adr/**`, the
`EXTRACTION-*-PATH-REFERENCES` registers and the pass-9 measurement say what was true when
written; only the living documents move — `BLUEPRINT.md`, `docs/context/*`, the addon
`README`s and the `GOALS.tsv` row, whose evidence column is a claim about now.

## Consequences

**`Sprite Rig` goal #7 is `met` at 0, and it is the first of the four open rows to close
without an epilogue.** The register said `open` and the code said `met`, which made
`score_goals.py` exit 1 until the row was rewritten; it exits 0 now.

**Three of the handoff's three decisions resolved, and only one of them was a decision.**
Decision 1 was already ruled and merely mis-addressed. Decision 3 was a ruling and was
ruled. Decision 2 was the only open argument and it dies on a `classify()` call — which is
the shape ADR-0148 exists to prefer: the instrument answers faster than the corpus, and it
answered against the reading that would have saved the most work.

**Three other addons moved for free and none of them is a row.** `exmateria_schema` and
`exmateria_render` are at 0, and `Battlefield` shed 44 lines it was being charged for
spelling somebody else's name. `Battlefield`'s remaining 74 are its
own — `PlayerCamera.gd` x16, `MapConstants.gd` x5, `fft_visible_angles.gdshaderinc` x5 —
and the same is true of `platform`'s 41.

**ADR-0117 row 10 now names a subject its own system only partly owns.** The depth model
and the colour modes are the kernel's published vocabulary and `Render` consumes them like
everyone else. `Render`'s exemption still holds for the fold, the compositor and shader
templating, but the row and the addon boundary have drifted apart, and a later pass that
reads row 10 as an address rather than a subject will reach the same false premise this
one did. Not fixed here; `PLATFORM_EXEMPT` was not widened and no row moved on it.

**NOT CLAIMED.** Nothing detects a missing `[shader_globals]` entry at runtime — ADR-0238
dec. 3's gap is unchanged, and this rename passed through it on the strength of six
runtime tests rather than an instrument. The full test suite was not run: two other
sessions held the box, and the claim this change rests on is a compile-and-render one that
the named tests answer directly.
