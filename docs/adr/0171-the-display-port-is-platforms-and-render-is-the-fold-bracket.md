# The display port is `platform`'s, and `Render` is the fold bracket

[#575](https://github.com/timbermania/fft-monorepo/issues/575) asked whether `Render` is
one of the eleven systems or a shared library the others may depend on. The question has
two answers because the addon holds **two modules**, and the disagreement it names belongs
to only one of them: `PSXDisplay` is a port and goes to `platform`; the fold bracket has a
system's shape and stays `Render`'s.

The argument matters more than the conclusion here. #575 and
[ADR-0169](0169-platform-ships-to-its-own-address-and-shipping-a-file-is-not-shipping-a-shader.md)
dec. 7 both state the case as *eight buckets reach into an addon the model calls a peer* —
a reach argument, and
[ADR-0139](0139-the-shared-kernel-is-enumerated-by-the-schema-list.md) dec. 2 already
refuted reach as an admission test: ranking by it *"admits `Debug` first and `Tune`
second, which is the reductio: **reach is not the test**"*. This ADR reaches #575's
conclusion on what the file **is** instead, and records the reach counts as the symptom
that made it visible.

Status: accepted (2026-08-25). Resolves
[#575](https://github.com/timbermania/fft-monorepo/issues/575), filed off map
[#560](https://github.com/timbermania/fft-monorepo/issues/560) by ADR-0169 dec. 7. Amends
[ADR-0150](0150-psxdisplay-stays-because-render-is-the-playstation-look.md). Adds a fourth
relocation to ADR-0169 dec. 2's pass-6 step and names a hole in its dec. 5 arm 4. Revives
[ADR-0129](0129-the-fold-is-renders-and-a-producer-keeps-its-shader.md) dec. 10, whose
trigger fired at extraction #1 and which did not execute. Re-evidences extraction #1's
`docs/GOALS.tsv` rows for goals #5 and #7.

Code at `efde53bd9`, classifier at `efde53bd9`.

## Context

ADR-0150 asked where `PSXDisplay.gd` belongs and answered *inside `Render`*, on the ground
that `Render` **is** the PlayStation look. That is an argument about **subject**. Nothing in
it, or anywhere else, examined the file's **shape** — whether a thing that holds no
behaviour of its own, coalesces `Tune` and pushes global shader parameters, is a member of a
system or a port beside one. ADR-0169 dec. 7 says as much: *"There is no decision anywhere
that examined that; ADR-0150 asked where the file belongs and never paired it with how many
buckets reach it."*

The shape question has a settled answer elsewhere in the same corpus. ADR-0139 dec. 12 rules
that tunable declarations are a schema whose realisation is a port's signature, so the
schema has *"no kernel member and never will"* — because `Tune` is a registry with I/O.
`PSXDisplay` is that sentence a second time: an autoload holding mutable applied-value state,
reading `ProjectSettings` and writing `RenderingServer`. It can never be kernel, and the
`platform` bucket is where the blueprint already files code of that shape.

Two vocabulary traps sit on this route and are worth pinning, because both were walked into
while reaching this decision.

**`platform` names two different classifications.** `BLUEPRINT.md` → *Not to be confused
with the platform tier* separates them: the **platform tier** is over ADRs, and it is
*"not a place for code"*; the **`platform` bucket** is over code, and it holds `Tune.gd`,
`PsxNum.gd` and two `.gdshaderinc` today. ADR-0129 dec. 9's *"not a place for code"* cites
the tier and raises no objection to a code booking.

**The `platform` bucket does not mean generic.** Same `BLUEPRINT.md` section, on `PsxUnits`:
*"is a platform-tier member and is PSX-specific, so it could never be generic"*. The bucket is
for code many systems reach that is not itself a system. It leaves the subject alone.

## Measurement

Measured at `efde53bd9`. Reach figures reproduce ADR-0169 dec. 7's.

**The addon is two modules with opposite shapes.**

| module | lines | interface | production consumers |
|---|---:|---|---:|
| `display_port/PSXDisplay.gd` | 260 | 5 properties, 5 signals, 2 methods | 19 files / 8 buckets |
| the fold bracket (`FoldSurface.gd` + 2 `.glsl` + `depth_debug.gdshader` + `plugin.gd`) | 447 | `setup(cam)`, `quantize_levels` | 1 |

**The port's published surface is mostly unread.** Of five signals, `live_cursor_stretch_changed`,
`live_unit_stretch_changed` and `live_fx_stretch_changed` have **zero** subscribers anywhere in
the tree — `src/`, `tests/` and `tools/`. `live_par_changed` has zero in production; its only
subscriber is `tests/TunePsxParTest.gd`. Only `live_ui_par_changed` carries load, with five UI3
subscribers. `shader_global_default()` is public for exactly one test.

**Four of the six knobs ship at identity.** `project.godot [shader_globals]` reads
`psx_par = 1.0`, `psx_cursor_stretch = 1.0`, `psx_unit_stretch = 1.0`, `psx_fx_stretch = 1.0`;
only `psx_gamma = 1.4` is not. `config/tune_overrides.json` (tracked, 10 keys) holds exactly one
`render.*` entry, `render.unit_y_lift`, which is **not** one of this module's six slugs. So with
no override committed, every `_apply_*` at boot pushes the value `project.godot` already
declares. The load-bearing production member is `live_ui_par` — 7 readers, no other source —
plus `live_par`'s single reader at `src/strategy/PlacementInputHandler.gd:79`.

**The globals are read far more widely than the symbol.** Counted across all four shader
extensions (ADR-0144): **17** shader files consume `psx_par`, **22** consume `psx_gamma`. None
names `PSXDisplay`. A three-extension count reports `psx_par: 0`, because the declaration sits
in `assets/shaders/psx_par.gdshaderinc` that the seventeen `#include`.

**Goal #7's exemption is almost entirely this one file.** `tools/score_goals.py` reads
`Render`'s 29 platform-jargon lines as **`PSXDisplay.gd` ×26, `depth_debug.gdshader` ×3**.

## Decision

**1. `PSXDisplay` is `platform`'s, on the port argument.** It holds no behaviour of its own; it
sources defaults from `ProjectSettings`, coalesces a `Tune` override over them, and pushes the
result to global shader parameters it does not declare. That is the shape ADR-0139 dec. 12 calls
a port, and it is `Tune`'s own shape — an autoload with I/O and mutable state, booked `platform`
and reached by ten systems without that being a crossing. The eight buckets are the symptom, not
the test; ADR-0139 dec. 2 governs, and this ADR does not disturb it.

The corroboration is already in the classifier. `classify_blueprint.py` books
`assets/shaders/psx_par.gdshaderinc` to `platform` and explains why in the comment above the
rule: *"Their CPU side is one `global uniform` pushed through a port (PSXDisplay._apply_par,
DebugConfig._apply_dither), not a second implementation of the same encoding."* The GPU half was
booked `platform` on the ground that `PSXDisplay` is its port. Booking the port to the same
bucket is a correction, not a new claim.

**2. `Render` remains one of the eleven, and it is the fold bracket.** 447 lines, one production
consumer, a two-item interface. ADR-0147 already met the size objection — *"is the smallest
system, full stop"*, 701 lines against `Campaign`'s 1,123 — and losing the port sharpens that
finding rather than changing it. The bracket is not kernel-admissible either: ADR-0139 dec. 1
names `FoldSurface` → `Fold` as the provider depending on the same encoding its consumers do,
which is an outbound edge, and the kernel's veto is zero outbound edges.

**3. The relocation is pass 6's fourth item. This ADR moves no file.** ADR-0169 dec. 2 populates
`addons/exmateria_platform/` at extraction #3's loop pass 6 with the two `.gdshaderinc` and
`PsxNum.gd`; `PSXDisplay.gd` joins that step, and its `RULES` booking lands in the same commit as
an exact rule ahead of the `addons/exmateria_render/` prefix — the mechanism ADR-0146 dec. 2
already used for `plugin.gd`, *"One exact rule ahead of the prefix books it `infrastructure`"*.

Deciding here and building there is deliberate: ADR-0169 dec. 3 gives pass 6 the whole 19-line
`#include` rewrite in one commit, and a second branch creating the same address and editing the
same `RULES` lines is a conflict that buys nothing. What this ADR must land before pass 6 is the
**decision**, because [#563](https://github.com/timbermania/fft-monorepo/issues/563) is open and
its table scores `PSXDisplay [Render] 2 lines / 1 files` as outbound debt while `Tune [platform]
59 lines / 6 files` is not debt — a difference that is entirely the tier. Under this decision that
row stops being debt. It remains one of the 104 standalone-parse breaks; goal #5 answers those.

**4. The autoload is renamed `DisplayCalibration`, and ADR-0129 dec. 10 is revived — both as a
follow-up ticket ([#583](https://github.com/timbermania/fft-monorepo/issues/583)), not in pass 6's
commit.** `PSXDisplay` is wrong twice over. It names `Render`'s
subject for a file that is no longer `Render`'s, and it promises a display abstraction it does not
have: what it owns is pixel aspect (world and UI), three per-taxonomy sprite width stretches, and
gamma — calibration, not a display. `DisplayCalibration` says that without naming a system.

ADR-0129 dec. 10 already retired the `psx_` prefix on the ground that the extraction path is the
tier marker, and set its own trigger: *"The rename happens when `Render` extracts, not here"*. The
trigger fired at extraction #1 and the rename did not happen — the kernel ships
`psx_ot_depth.gdshaderinc`, prefixed, inside the addon where dec. 10 says the prefix says nothing,
and `psx_par.gdshaderinc` is still not what dec. 10 asked for: *"Only `par` wants a longer name
(`pixel_aspect`)"*.

It is a follow-up rather than pass 6's work because the cost lands somewhere else entirely. The
autoload name is typed in **27 files — 19 production, 8 test, 90 lines** — plus `project.godot:44`,
and none of that is work pass 6 was already doing. The move unblocks #563 and pass 6; the rename
blocks nothing, and a 27-file symbol rename reviewed on its own diff is verifiable in a way the
same edit buried in an address-creation commit is not.

**5. Arm 4's subject has a hole, and this decision opens it.** ADR-0169 dec. 5 scopes arm 4 to
*"Any `global uniform` reachable from an addon root"*. `PSXDisplay` does not declare a
`global uniform` — it **pushes** five, by name, from the CPU side (`psx_par`, `psx_gamma`,
`psx_cursor_stretch`, `psx_unit_stretch`, `psx_fx_stretch`; `psx_ui_par` is deliberately not one,
being a GDScript-only mesh-width multiplier). Only **two** of the six globals this addon family
binds are declared by a file that moves with it — `psx_par` and `psx_dither_enabled`, the two
`.gdshaderinc` of decision 3. `psx_gamma` is the sharp case: 22 shader files read it, no addon file
declares it, and its declaration stays in the host's `project.godot`. An arm that reads only
`global uniform` declarations will therefore report those two and be silent about the push side and
about `psx_gamma` entirely. Arm 4 needs both sides; see the amendment below for where it was built.

**6. Extraction #1's goals #5 and #7 are re-evidenced, and #7 changes hands.** Goal #5 is unaffected
in substance — the port carries no outbound system reach, so *0 cross-system reach lines* holds for
the bracket alone — but the addon it was measured over drops 707 lines to 447 and the row should say
so. Goal #7 is the real move: 26 of `Render`'s 29 platform-jargon lines are `PSXDisplay.gd`'s, and
ADR-0150's exemption is restricted to `Render` on ADR-0117 row 10. When the file leaves, `Render`'s
count falls to **3** and 26 exempt lines arrive in a bucket where no exemption exists. Decision 4
discharges them rather than importing a defect: the rename is what makes those lines stop being PSX
jargon.

`addons/exmateria_platform/` is not scored by `tools/score_goals.py` and none is owed — the ten
goals score systems, and the scorer already declines `addons/exmateria_schema` on exactly that
ground.

## Consequences

- **`Render` is 447 lines and one module.** `addons/exmateria_render/README.md` claims
  `PSXDisplay` is *"the addon's entire published surface"*; that becomes false and is corrected
  with this ADR.
- **#563 loses one of its four outbound-debt rows** before it is answered.
- **Pass 6 gains one relocation and one `RULES` line**, and arm 4 gains a subject it did not have.
- **A rename ticket is owed** — [#583](https://github.com/timbermania/fft-monorepo/issues/583), carrying `PSXDisplay` → `DisplayCalibration` and ADR-0129 dec. 10's
  `psx_par` → `pixel_aspect`, over 27 files plus 17 shader files. It also owes a row in
  `CONTEXT.md` → *Extraction #1 translation table (`Render`)*: goal #2 is that a rename carries a
  translation table, and this is the first rename extraction #1 has produced since the table was
  written.
- **The three unsubscribed signals and `shader_global_default`'s public visibility are not touched
  here.** They are module-shape defects, true on either tier, and belong with the rename ticket
  where the file is already open.
- **ADR-0150 is amended, not superseded.** Its subject argument stands: `Render` is the PlayStation
  look, and that is why the fold bracket keeps the 5-bit crush by default (ADR-0152). What it may no
  longer do is settle membership from subject alone.

## Amendment (2026-08-25) — arms 3 and 4 are BUILT, here rather than at pass 6, and the port pushes five

Decision 5 said *"pass 6 owns arm 4"*. Both arms are now built and pushed on this branch
(`tools/check_addon_portability.py`, `tools/test_check_addon_portability.py`), and the reason
decision 3 gave for deciding-here-and-building-there does not reach them.

**Why the choke-point argument does not apply.** Decision 3 defers the *relocation* because
ADR-0169 dec. 3 gives pass 6 the whole 19-line `#include` rewrite in one commit, and two branches
creating `addons/exmateria_platform/` and editing the same `RULES` lines is a conflict that buys
nothing. The arms share neither: they are one tool file plus its test, and pass 6 touches
`classify_blueprint.py`, `_walk_roots.py` and a `git mv`. This branch is also a strict descendant
of `refactor/extraction-3-pass-4`, so pass 6 inherits them on a fast-forward.

**Why building them first is better, not merely allowed.** Arm 3 is armed against pass 6 dropping
one of nineteen `#include` rewrites — ADR-0169 dec. 5's *"a note in a document cannot catch that"*.
A guard authored in the same commit as the change it guards can be shaped to pass; authored before,
it is a tripwire. And arm 4 needed no precondition at all: `PSXDisplay.gd` is under
`addons/exmateria_render/` **today**, so the push side had a live subject before any file moved.
Arm 4 reports five lines now and exits 0 (in-walk DEBT, arm 2's strictness rule). Guards 36/36.

**Two numbers in decision 5 were wrong and are corrected above.** The port pushes **five** globals,
not four, and a declaration-only arm would report the **two** that move, not four.

**Three defects the seeds found that reading could not.** ADR-0169 dec. 5 and the house standard
require each arm be seeded red; each of these read as a working, green arm until it was:

1. **Arm 4's CPU side, built on arm 2's `strip_noncode`, reported zero.** That stripper blanks
   string literals — correctly, for arm 2, which hunts a bare identifier. The pushed global's name
   *is* a string literal, so `PSXDisplay.gd`'s five live pushes arrived as `&""`. The one token
   arm 4 needs is the one token arm 2 must destroy.
2. **Arm 3's shader stripper ate every `#include`, because `res://` contains `//`.** Read as a line
   comment, the line was blanked from the scheme onward, nothing resolved, and the arm returned a
   clean zero over a tree whose one real include it had never parsed.
3. **Both arms match their own documentation if read raw.** `effect_fold_add.gdshader` says
   "global uniform" in a `//` comment, `psx_ot_depth.gdshaderinc:11` spells an `#include` in one,
   and `PSXDisplay.gd:54–55` discusses `global_shader_parameter_set` thirty lines above calling it.

**One widening beyond the specification.** ADR-0169 dec. 5 writes arm 3 as `#include "res://…"`.
Matching only that literal prefix leaves `#include "../../assets/x.gdshaderinc"` — the same escape,
spelled the other legal way — invisible, so relative includes are resolved rather than skipped.
Arm 3 also fails a `#include` naming a file that does not exist, which is ADR-0146 dec. 8's rule.

**What pass 6 still owes.** The relocation itself (decision 3), and re-running this guard after it:
arm 4's five debt lines move addon but do not change count, and arm 3 must stay green across the
19-line rewrite — which is the whole reason it exists.

## Considered alternatives

**Sever the nineteen reaches.** #575's first horn, and ADR-0169 dec. 7's. It treats the model as
correct and the code as the defect, at a cost of nineteen call-site rewrites, and it would have to
sever `TileCursor.gd:240–241` — knowledge about what the fold re-applies — into the consumer rather
than out of it. Rejected: the model is what is wrong, and the tier correction is one line.

**`Render` was never a system.** #575's second horn: demote the whole addon. Rejected because it
answers a shape question with a size argument the project has already rejected in writing
(ADR-0147), and because the fold bracket has the shape a system has — real behaviour behind a
two-item interface, no inbound reach from the other ten.

**Merge the bracket into the kernel.** Foreclosed by ADR-0139: the kernel admits only files
realising a named published schema, with zero outbound edges and never an autoload. `FoldSurface`
depends on the kernel's own encoding, which is an outbound edge by construction.

**Keep the name `RenderCalibration`.** Considered and rejected during the decision: `Render` is a
capital-R system name in this repo, so a symbol named for it sitting in `addons/exmateria_platform/`
re-attaches the file by name to the system this ADR removes it from, and reads as a mistake under
ADR-0146 dec. 2's membership test — *"a reviewer checks membership with `ls`"*.

**Do the move on this branch.** Rejected on the choke point: pass 6 must touch
`addons/exmateria_platform/` and the same `RULES` block for the two `.gdshaderinc` regardless, so
building it twice on two branches produces a conflict and no earlier delivery.
