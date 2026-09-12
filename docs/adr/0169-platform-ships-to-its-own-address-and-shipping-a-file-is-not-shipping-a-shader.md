# `platform` ships to its own address, and shipping a file is not shipping a shader

[#566](https://github.com/timbermania/fft-monorepo/issues/566) asked where `platform`
ships, who owns the work, and whether `check_addon_portability.py` gains an arm.
[ADR-0159](0159-platform-is-not-a-leaf-and-battlefields-seam-waits-on-inverting-it.md)
dec. 3 had already settled that `platform` **ships** rather than gets injected, and named
no owner and no address; [#561](https://github.com/timbermania/fft-monorepo/issues/561)
made the question answerable by turning an abstract reach into a concrete broken path.

The address half is the smaller half. The larger finding is that **moving the file does not
make the addon compile**, and no instrument on this map can say so: both `platform`
shader includes declare a `global uniform`, whose name lives in the *host's*
`project.godot` — which is `check_addon_portability.py` arm 2's exact reasoning, one
language over, with no arm behind it.

Status: accepted (2026-08-25). Resolves
[#566](https://github.com/timbermania/fft-monorepo/issues/566) on map
[#560](https://github.com/timbermania/fft-monorepo/issues/560) (extraction #3, loop pass 5).
Discharges ADR-0159 dec. 3's *"whichever pass builds `addons/exmateria_platform/`"*.
Bounds ADR-0146 dec. 3 to membership rather than address. Files
[#575](https://github.com/timbermania/fft-monorepo/issues/575) off the map.

Code at `e2c8f806b`, classifier at `e2c8f806b`.

## Context

`platform` is **4 files / 877 lines**: `src/core/Tune.gd` (586), `src/scenarios/PsxNum.gd`
(176), `assets/shaders/psx_par.gdshaderinc` (70), `assets/shaders/psx_dither.gdshaderinc`
(45). #561 fixed `Battlefield`'s address at `godot-learning/addons/exmateria_battlefield/`,
**inside the walk**, with the system's 16 shader files moving out of `assets/shaders/`.
After that move, `Battlefield`'s shaders sit inside an addon and still name
`res://assets/shaders/`, which in a project without the host's `assets/` does not compile.

`score_goals.outbound_reaches()` does parse a shader `#include "res://…"` — it is not blind
to the line — but records a reach only when the target's bucket is one of the eleven
systems. `platform` is a **port**, and a port is what a portable addon is allowed to reach
(ADR-0139 dec. 12, ADR-0140 dec. 9). The rule is right for `Tune` and wrong for a
`#include`, and the guard cannot tell them apart.

## Measurement

**The reach, direct and transitive.** Exactly **8** of `Battlefield`'s 16 shader files carry
the `#include` **directly**, which is the right unit for the fix and the wrong one for the
breakage. Resolving `#include` chains across the manifest's 16 shader rows, **14 of 16**
transitively reach `psx_par` or `psx_dither`; the extra six —
`cursor_fold_add/mix/sub.gdshader`, `tile_cursor_opaque.gdshader`,
`tile_overlay_mode0/opaque.gdshader` — arrive through siblings *inside* the 16. Rewriting
the 8 lines repairs all 14. Only `cursor_clut_preview.gdshader` and
`fft_visible_angles.gdshaderinc` reach neither.

**The two files are included by 19 files across six buckets**, not the four systems the
ticket names — `Cutscene` was missing:

| includer bucket | `psx_par` | `psx_dither` |
|---|---:|---:|
| Battlefield | 7 | 1 |
| Effects | 4 | — |
| Battle | 3 | — |
| Cutscene | — | 2 |
| Sprite Rig | 1 | — |
| UI | 1 | — |
| **total** | **16** | **3** |

**`platform`'s three halves have three consumer sets and three host dependencies.**

| half | lines | production consumers | what the *host* must declare |
|---|---:|---|---|
| `Tune.gd` | 586 | 7 systems | `[autoload]` |
| the two `.gdshaderinc` | 115 | 19 shaders / 6 buckets | `[shader_globals]` ×2 |
| `PsxNum.gd` | 176 | Effects 2 + Cutscene/scenarios 8, **0 Battlefield** | nothing |

`PsxNum` is reached by `class_name` **only**: grepping `src/scenarios/PsxNum.gd` across the
tree returns zero production or test path references (four hits, all prose or
`classify_blueprint.py:166`). `Tune.gd` likewise has exactly one path reference,
`project.godot:24`. Cost is not what separates them.

**The `global uniform` finding.** `psx_par.gdshaderinc:50` declares
`global uniform float psx_par` and `psx_dither.gdshaderinc:7` declares
`global uniform bool psx_dither_enabled`. A global uniform resolves against the host's
`project.godot [shader_globals]`, and the engine treats a missing one as a **compile
error**, not a warning — `servers/rendering/shader_language.cpp:9866` in the 4.8 fork:

> Global uniform '%s' does not exist. Create it in Project Settings.

The extracted `Battlefield` addon needs **six** such entries, and **four are declared by
files that move into the addon**, so they survive the move unsatisfied:

| global | declared in | moves with |
|---|---|---|
| `psx_par` | `psx_par.gdshaderinc` | `platform` |
| `psx_dither_enabled` | `psx_dither.gdshaderinc` | `platform` |
| `psx_camera_angle`, `visible_angles_cull_mode` | `fft_visible_angles.gdshaderinc` | **Battlefield** |
| `psx_cursor_stretch` | `tile_cursor.gdshaderinc` | **Battlefield** |
| `psx_fx_stretch` | `cursor_fold.gdshaderinc` | **Battlefield** |

Neither kernel `.gdshaderinc` nor anything under `addons/exmateria_render/` declares a
global uniform. The hole is `Battlefield`'s alone, so an arm for it is a new constraint and
not a retroactive accusation.

## Decision

**1. The address is `addons/exmateria_platform/`, a sixth `WALK_ROOTS` member — and
`addons/exmateria_schema/` is refused on ADR-0146 dec. 2's `ls` test, not on its dec. 3.**

Dec. 3 turned `psx_par` and `psx_dither` down for **kernel membership**, on a mechanical
test — a member is one half of a codec, and these have a writer rather than a counterpart.
That is a **bucket** ruling and it stands unchanged; nothing about extracting `Battlefield`
gives either file a CPU counterpart. It is not, however, an **address** ruling, and the
distinction is not hypothetical: dec. 6 already ships two non-members out of that directory,
because `plugin.gd` and `plugin.cfg` live in `addons/exmateria_schema/` and are booked
outside the `schema` bucket.

What refuses the schema addon is dec. 2, whose layout rule exists so that
*"a reviewer checks membership with `ls`"* (ADR-0146 dec. 2). A `platform/` subdirectory
inside the kernel addon makes that check lie about the addon it is checking. One bucket,
one addon keeps the classifier row and the shipped directory 1:1, which is what makes both
`--delta` and `ls` readable, and it is the shape ADR-0159 dec. 3 named in as many words.

`addons/exmateria_render/` is refused twice over and correctly: ADR-0146 dec. 4 (a PSX
display fact six buckets include cannot live inside a system that extracts without dragging
it behind all six) and ADR-0150 dec. 5. It never fit `psx_dither` at all — that file's CPU
writer is `src/debug/DebugConfig.gd:255`, which is `Debug`, not `Render`. See dec. 7.

**2. One address, populated in two steps: the two `.gdshaderinc` and `PsxNum.gd` move at
pass 6; `Tune.gd` joins on #535's schedule. The split is temporal, not architectural.**

`PsxNum.gd` is taken because it is free — `class_name`-only, so the move is one
`classify_blueprint.py` `EXACT` row and no call-site edits — and because it makes the
addon's identity *"this is the `platform` bucket"* legible from birth instead of *"the two
shader includes"*. Its zero `Battlefield` consumers make it scope creep on a purist reading;
the alternative is a one-line move needing its own ticket later.

`Tune.gd` is left behind for **collision**, not cost. #535 deletes `register_all()` *"along
with all 15 path references"*, rewriting `src/core/Tune.gd` substantially. The entire case
for running #535 beside this map is that it parallelises and **shares no file with #566 or
#567**; moving `Tune.gd` destroys that property and puts two branches on the one file #535
rewrites. ADR-0159 dec. 3 already says the `Tune` work is not `Battlefield`'s, and its own
2026-08-24 amendment measured that extraction #3 reaches goal #5 without the inversion
(`Battlefield → Tune` is 66 lines scoring **0**, correctly).

The stated cost is that the `platform` bucket sits at two addresses for a pass or two. Both
are inside the walk and both classifier rows key on path, so `--delta` reports no rebooking
and no line goes uncounted: ADR-0146 dec. 5's hole does not reopen.

**3. Extraction #3's loop pass 6 owns the whole 19-line rewrite, in one commit, including
the 11 lines that are not `Battlefield`'s. Nothing blocks pass 6.**

Rewriting five other systems' shaders looks like scope creep until the kernel promotion is
checked. `psx_ot_depth.gdshaderinc` is included by **24 files across 8 buckets**, and
prologue pass 6 — commit `449463b2f`, *"the kernel is built, and a codec is what gets in"* —
moved it into `addons/exmateria_schema/` and rewrote **23 `#include` lines across 71 files
in a single commit**, touching every bucket that included it. Nobody called that scope
creep, because ADR-0139 dec. 10's promotion rule leaves no alternative: a released addon
cannot depend on a path inside the host. This is the same move at half the size.

There is no precondition. Creating the addon is a `git mv` of three files, the no-op
`plugin.cfg`/`plugin.gd` #561 already specified for `Battlefield`, `WALK_ROOTS` gaining a
sixth member, and three `classify_blueprint.py` `EXACT` rows repointed (`:166`, `:341`,
`:342`). #535 does not gate it — dec. 3's precondition ranking was withdrawn by its own
amendment — and under dec. 2 it still shares no file with it.

**4. Shipping a file is not shipping a shader: a `global uniform` is arm 2's defect in the
other language, and it does not move with the file.**

`check_addon_portability.py` arm 2 exists because, for an autoload, *"the name is the
host's `project.godot`"* (`check_addon_portability.py` arm-2 rationale). A `global uniform`
is that sentence verbatim in GDShader, and the engine's response is stricter — a compile
error, quoted in Measurement above. The extracted addon needs six `[shader_globals]`
entries and **four of them are declared by its own files**, so moving `psx_par` and
`psx_dither` into `addons/exmateria_platform/` fixes the *path* half of `Battlefield`'s
portability and leaves the *name* half untouched.

This is the pass-4 lesson the map records — ask what an instrument **cannot** represent —
arriving for the fourth time. Every register on this map reads paths and symbols; a
`[shader_globals]` binding is neither.

**5. Two new arms, not one. Arm 3 enforces; arm 4 reports, on the line the guard already
draws.**

- **Arm 3 — host path.** Any `#include "res://…"` under an addon root whose target lies
  outside every addon root. **Enforcing (red)**, because it is checkable without a
  standalone project: the path either resolves inside an addon root or it does not. Green
  on both existing addons today — `exmateria_render`'s only `#include` reaches
  `addons/exmateria_schema/`, which is the correct shape and the precedent.
- **Arm 4 — shader globals.** Any `global uniform` reachable from an addon root. Follows
  arm 2's existing strictness rule: **DEBT** for an addon with no `project.godot` of its
  own, **RED** for a package that has one.

The alternative — recording both as stated debt, as #561 did for the
`PlayerCamera.tscn → CombatUI.tscn` edge — is rejected for arm 3 specifically. The failure
mode is that pass 6 forgets one of 19 lines, and a note in a document cannot catch that.
It is accepted for arm 4, because in-walk there is no project to fail against, which is the
same reason arm 2 reports rather than fails.

**6. `check_par_shaders.py` never received ADR-0146 dec. 8's rule, and the move is when
that starts mattering.**

Dec. 8 requires that a seam guard check the file exists rather than just the basename.
`check_color_shaders.py` implements it — line 47 pins the full path in a `SEAM_RES`
constant and line 111 pairs `endswith` with `.is_file()`. `check_par_shaders.py` does not:
line 63 is `res_rel.endswith(INCLUDE)` alone, with `INCLUDE` a bare basename. The guard
therefore survives the move by accident and stays blind to a mistyped path. Line 164 also
hardcodes `res://assets/shaders/psx_par.gdshaderinc` in its fix hint, which goes stale the
moment the file moves. Both are pass 6's, recorded here rather than discovered there.

**7. `Render` is a shared library in fact and a system in the model, and that is
[#575](https://github.com/timbermania/fft-monorepo/issues/575), off this map.**

`PSXDisplay` is an autoload (`project.godot:44`) named by **19 production files across 8
buckets** — UI 9, Debug 2, Cutscene 2, assembler 2, Effects 1, Battlefield 1, Battle 1,
platform 1 — while `classify()` books `PSXDisplay.gd` to `Render`, one of the eleven
systems. Eight buckets reach into an addon the model calls a peer. There is no decision
anywhere that examined that; ADR-0150 asked where the file belongs and never paired it with
how many buckets reach it.

🔴 **It bites this extraction directly.** `src/scenes/TileCursor.gd` is a row of #565's
46-line move manifest, and lines 240–241 read `PSXDisplay.live_fx_stretch` and
`PSXDisplay.live_cursor_stretch`. The moment pass 6 moves that file,
`addons/exmateria_battlefield/` holds a file naming a **system** symbol — precisely what
arm 1 exists to red (ADR-0151). Neither #561 nor #565 saw it: both were reasoning about
*which files move*, and this is a reach *inside* a file that moves. Pass 6 must answer it
either way; what #575 decides is whether the answer is *sever it* or *`Render` was never a
system*.

Promoting `Render` is a blueprint change owed to eight buckets — the shape #560 already
ruled out of scope for #535 at seven — so it is filed off the map rather than resolved on
the route. It does not reopen dec. 1: `psx_dither`'s writer is `Debug`, so the pair does not
belong in `Render` on any answer #575 can give.

## Consequences

- **`addons/exmateria_platform/` is created at pass 6** with `psx_par.gdshaderinc`,
  `psx_dither.gdshaderinc` and `PsxNum.gd`, a no-op `plugin.cfg`/`plugin.gd`, and a
  `README.md` stating the `[shader_globals]` contract dec. 4 measured. `WALK_ROOTS` becomes
  `("src", "assets", "addons/exmateria_schema", "addons/exmateria_render",
  "addons/exmateria_battlefield", "addons/exmateria_platform")`.
- **19 `#include` lines are rewritten in the same commit**, 8 `Battlefield` and 11 across
  `Effects`, `Battle`, `Cutscene`, `Sprite Rig` and `UI`. `docs/EXTRACTION-3-MOVE-MANIFEST.tsv`
  is **not** amended — its rows are `Battlefield`'s files and none of these three are.
- **`Battlefield`'s addon ships with a `[shader_globals]` requirement of six names**, four
  of them its own. Whether that is documented-and-accepted or designed away (a non-global
  uniform, a `ShaderMaterial` parameter) is pass 6's call; dec. 5's arm 4 makes it visible
  either way. It is a **goal #5 debt** and should be stated in the pass 9 scorecard rather
  than scored as met.
- **Two guard arms are owed at pass 6**, joining the two registers ADR-0164 dec. 4 and
  ADR-0166 dec. 4 already owe there. Pass 6's owed-instrument count is now **four**.
- **`check_par_shaders.py` is edited at pass 6** for dec. 6, and that edit is the point at
  which ADR-0146 dec. 8 finally applies to both seam guards rather than one.
- ⚠️ **A `#include` count and a compile-failure count are different numbers for the same
  file set** — 8 and 14 here. Every prior statement of this reach, including #566's own and
  ADR-0159 dec. 3's, used the smaller one. The fix unit is 8; the honest portability
  statement is 14 of 16.
- ⚠️ **`platform` is at two addresses until #535 lands.** Anything reading the bucket as a
  directory will be wrong; both rows key on path and both are in the walk, so no instrument
  on this map is affected.

## Considered alternatives

- **Put the two `.gdshaderinc` in `addons/exmateria_schema/` beside `psx_ot_depth`.**
  Not foreclosed by ADR-0146 dec. 3, which rules on membership, and dec. 6 already ships
  non-members from that directory. Rejected on dec. 2's `ls` test — the kernel addon would
  stop meaning one thing, and it is the only addon whose membership is checked by looking.
- **Put them in `addons/exmateria_render/`, where `psx_par`'s CPU writer already lives.**
  Rejected by ADR-0146 dec. 4 and ADR-0150 dec. 5, and independently by cost: the addon is
  684 lines of which `FoldSurface.gd` (296) and its two `.glsl` (109) require the Godot 4.8
  compositor fork (`FoldSurface.gd:30`), so a consumer wanting 70 lines of stock-Godot
  GDShader would inherit 405 lines of forked-engine compute code. `psx_dither` does not fit
  it on any reading. Reopened as #575 in the wider form — see dec. 7.
- **Move all four `platform` files at pass 6.** Rejected by dec. 2 on collision with #535,
  not on cost: `Tune.gd`'s only path reference is `project.godot:24`.
- **Record the shader reach as stated debt and add no arm.** Rejected for arm 3 by dec. 5 —
  the failure mode is a forgotten line among 19, which a document cannot catch. Accepted in
  substance for arm 4, which reports rather than fails while the addon is in-walk.
- **Duplicate `psx_par.gdshaderinc` into each consuming addon.** Rejected by ADR-0139:
  vendoring a shared include is what `addons/exmateria_schema/` exists to prevent, and it
  would put six copies of a `global uniform` declaration in one project.

## Amendment (2026-09-05): dec. 4's mechanism is wrong — the check is editor-only

**Every decision in this ADR stands. One sentence of the reasoning behind dec. 4 does
not**, and it is the sentence that got copied into fifteen other places.

The Measurement above quotes `servers/rendering/shader_language.cpp:9866` accurately.
What it does not quote is the enclosing condition, four lines above:

```cpp
if (uniform_scope == ShaderNode::Uniform::SCOPE_GLOBAL &&
        Engine::get_singleton()->is_editor_hint()) {
    // Type checking for global uniforms is not allowed outside the editor.
```

So *"the engine's response is stricter"* is true **only in the editor**. Outside it —
every stranger-rig run, every `godot --path X scene.tscn`, every exported game — the
check is skipped: the shader compiles, exposes its uniforms, draws, and reads the
missing global at its type's zero. The only report is a per-material warning at DRAW
time from `update_uniform_buffer`.

This does not weaken dec. 4's conclusion; it strengthens it. A compile error would fail
loudly at install. What actually happens is a blank screen with no error anywhere — the
consequence ADR-0203 dec. 7 and ADR-0220's own Context already described and that this
ADR's mechanism sentence talked everyone out of looking for.

Measured on both binaries, with a live control, and pinned by
`tests/stranger/exmateria_platform/global_uniform_unvalidated.tscn`, which fails if a
future engine ever validates outside the editor. See
[ADR-0238](0238-a-global-uniform-is-validated-only-in-the-editor-and-the-debt-is-silent.md).
