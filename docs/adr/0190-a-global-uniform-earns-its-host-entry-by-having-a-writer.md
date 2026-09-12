# A `global uniform` earns its host entry by having a writer, and one of the four had none

[#626](https://github.com/timbermania/fft-monorepo/issues/626) is the last open QUESTION in
extraction #3. [ADR-0169](0169-platform-ships-to-its-own-address-and-shipping-a-file-is-not-shipping-a-shader.md)'s
Consequences called it *"pass 6's call"*; pass 6 declined, the isolation pass declined, and
[ADR-0187](0187-the-port-is-two-signatures-and-sixteen-of-the-seventy-eight-were-already-inside-it.md)
declined again while closing every other GDScript break. Three passes were right to decline —
it is a decision, not a build — and this one measures it before deciding.

🔴 **The first thing to say is that ADR-0169 had this right and its readers did not.**
ADR-0169 wrote *"a `[shader_globals]` requirement of six names, four of them its own"* — six is the number, and
it is the number the `#include` closure gives. What propagated afterwards was **four**, because
the battlefield README and three successive handoffs counted DECLARATION LINES INSIDE THE ADDON
and that is a different question. `psx_par` alone is ten of the eleven addon shaders and was
never in the four.

The finding that does move the question is smaller and worse: **one of the six has no CPU writer
anywhere in the tree.**

Status: accepted (2026-08-27). Resolves
[#626](https://github.com/timbermania/fft-monorepo/issues/626). Discharges ADR-0169 dec. 4's
shader half and its *"pass 6's call"*. Corrects the record on ADR-0169, which was right about
the count and about the options. Builds on ADR-0171 dec. 1 and ADR-0186 dec. 2.
Adds an ENFORCING arm to `check_addon_portability.py`.

Code at `7f4a3267f`.

## Context

A `global uniform` resolves against the **consuming project's** `project.godot
[shader_globals]` block, and the engine treats a missing one as a **compile error**, not a
warning (`servers/rendering/shader_language.cpp:9866`). So a shader that declares one is not
self-contained: it is an install step charged to whoever installs the addon.

`check_addon_portability.py` arm 4 reports these as DEBT rather than failing, because in-walk
there is no standalone project to compile against. That is right, and it is also why the
question sat open: the guard could name the lines but not decide them.

## Measurement

**The requirement is six names over eleven addon shaders, not four declarations.**

| name | addon shaders needing it | declared, before | **written by** |
|---|---:|---|---|
| `psx_par` | **10** of 11 | `exmateria_platform/pixel_aspect/` | the port |
| `psx_fx_stretch` | 3 | **battlefield** + 2 host files | the port |
| `psx_camera_angle` | 2 | **battlefield** | the port (#590) |
| `visible_angles_cull_mode` | 2 | **battlefield** | 🔴 **nobody, ever** |
| `psx_cursor_stretch` | 1 | **battlefield** | the port |
| `psx_dither_enabled` | 1 | `exmateria_platform/dither/` | `src/debug/DebugConfig.gd` |

🔴 **`visible_angles_cull_mode` has no writer.** There is no
`RenderingServer.global_shader_parameter_set("visible_angles_cull_mode", …)` anywhere in the
tree; its only value in any session was the `2` that `project.godot` declared. Its own header
named `enable_visible_angles_cull` as *"the F3 toggle"* that gates the test — **that identifier
does not exist in this repo either**. A knob with no writer and a switch that was never built.

**Five of the six are written by one file, and it declared none of them.** `PSXDisplay.gd`
pushes `psx_par`, `psx_gamma`, `psx_cursor_stretch`, `psx_unit_stretch`, `psx_fx_stretch` and
`psx_camera_angle`. ADR-0171 dec. 1 described the port as one that *"pushes the result to global
shader parameters it does not declare"* — read as a description; it is the anomaly.

**The repo had already written the rule, for one name.**
`addons/exmateria_platform/pixel_aspect/psx_par.gdshaderinc` says: *"Never redeclare this at a
call site — include this seam so there is exactly one declaration to scrub."* Pixel aspect had a
seam. The stretches and the camera angle did not, so their declarations landed wherever they were
first needed, which was inside a system's addon.

⚠️ **A third option was in circulation that no ADR ever offered, and this pass wrote it down
twice before checking.** ADR-0169 gives exactly two — *"documented-and-accepted or designed away
(a non-global uniform, a `ShaderMaterial` parameter)"*. The handoff chain rendered that as *three
candidates: document-and-accept · push through the port · design away*, and #626's own body and
this pass's handoff both repeated the third and attributed it to the ADR.

It could never have worked: a push does not create a name. `[shader_globals]` does, and
`RenderingServer.global_shader_parameter_add` at runtime is not the parser finding the name at
compile time. `tools/check_adr_quotes.py` is what caught it — the quote was in this document's
own prose and in no ADR.

## Decision

**1. `visible_angles_cull_mode` stops being a global uniform. It is a `const int` in the shader
that reads it, and it leaves `project.godot`.**

Not a decision about cost — a correction. A `global uniform` is a channel from CPU to GPU, and
this one never had a CPU end. Six host names become **five**, and the addon's own declarations
four become three, for no behavioural change and no lost capability: switching modes was always
an edit, and it is now an edit to the file that defines the modes rather than to the consuming
project's settings.

The three modes stay, and so does the branch on them — the compiler folds a `const`, and deleting
the diagnostic mode would be a second decision this one has no evidence for.

**2. The remaining three move to DECLARATION SEAMS in the port that pushes them:
`addons/exmateria_platform/display_port/psx_sprite_stretch.gdshaderinc` (`psx_fx_stretch`,
`psx_cursor_stretch`) and `.../psx_camera_angle.gdshaderinc` (`psx_camera_angle`).**

Two files, not one, because the platform README's layout rule is that *"the subdirectory names
are the fact each file encodes"* and these are two facts — the ADR-0044 stretch taxonomy, and the
camera-angle register. The three battlefield files `#include` instead of declaring.

🔴 **This does not reduce the host requirement, and nothing short of dec. 4 could.** It is still
five names. What it buys is that they are **one addon's documented contract instead of two**, so a
consuming project satisfies the whole shader half from `exmateria_platform`'s README — and that
`Battlefield`'s arm-4 declaration count is **zero**, which is what makes dec. 3 possible.

⚠️ **`psx_unit_stretch` is deliberately NOT in the stretch seam**, though it is the taxonomy's
third member and the port pushes it. It is declared at two host call sites, neither inside an
addon, and **no addon shader reads it**. Putting it in the seam would charge every includer — all
of them `Battlefield`'s — for a name none of them uses, taking the requirement back to six. Those
two call sites adopting the seam is a follow-up, not this decision's business.

**3. `check_addon_portability.py` gains arm 4b, and unlike arm 4 it ENFORCES: only an addon that
is not one of the eleven systems may DECLARE a `global uniform`.**

Arm 4 asks whether the HOST declares a name the addon binds, which is unanswerable in-walk — no
standalone project, hence DEBT. Arm 4b asks **which addon the declaration sits in**, which is a
fact about this tree and answerable now.

The free set is **arm 5's, derived the same way**: `system_of[addon] is None`, true for the kernel
and the platform port and false for every system (ADR-0139 dec. 9, dec. 12). No allowlist, so it
cannot go stale.

Seeded both directions: re-adding `global uniform int visible_angles_cull_mode` to
`fft_visible_angles.gdshaderinc` reds it; adding one to the platform port's own seam leaves it
green.

**4. The residual five-name block is DOCUMENTED AND ACCEPTED, stated once, in
`addons/exmateria_platform/README.md`. It is not designed away.**

`psx_camera_angle` changes **every frame** and is read by `indexed_color.gdshader` and
`black_unlit.gdshader` — every map surface. Converting it to a `ShaderMaterial` parameter means a
per-material push on a rebuild-heavy path, which is precisely what a global uniform exists to
avoid. The stretches are cheaper to convert but share the name with host files that would keep
the entry anyway.

So goal #5's shader half is met **as an install step, not as zero dependencies**, and the
scorecard should say so in those words rather than scoring it clean.

## Consequences

- **Host `[shader_globals]` names the addons require: 6 → 5.** `addons/exmateria_battlefield/`
  declares **0** global uniforms, down from 4. Every declaration under `addons/` is now in
  `exmateria_platform/`.
- **`check_addon_portability.py` arm 4b is RED-capable and green today**, and would have caught
  the defect that motivated it.
- ⚠️ **The seams cross-impose within an addon.** `tile_cursor_opaque.gdshader` used to need
  `psx_cursor_stretch` alone and now also declares `psx_fx_stretch`, because the seam carries the
  family. Verified that no shader's include closure declares a name **twice** — the one file that
  could have collided is `assets/shaders/effect_particle_stp.gdshaderinc`, which also declares
  `psx_fx_stretch` and which no battlefield shader reaches. The addon-level requirement is
  unchanged at five, which is the number a consumer pastes.
- **The cull still culls, and that was checked by rendering rather than by reading.** A `const`
  the compiler folds is exactly the kind of change that can go inert unnoticed. Three-way seed at
  two camera yaws on `MAP056`: mode 2 (shipped) 184.7 KB, mode 1 (over-cull) **76.6 KB**, mode 0
  (off) 186.0 KB. Mode 1 visibly guts the map, so the const is read; mode 2 differs from mode 0,
  so the angle-aware path is culling real polygons.
- ⚠️ **`psx_dither_enabled` is declared in the port and written by `src/debug/DebugConfig.gd`** —
  a host file, not the port. Arm 4b does not catch it because the declaration is in an allowed
  addon; a stricter *"declare only what you push"* rule would need a burn-down row for it. Left
  as it is, named here so the next reader does not mistake the asymmetry for an oversight.
- 🔴 **Goal #5's remainder for `Battlefield` is now one thing: the six `ARM1_BURN_DOWN` lattice
  reach lines** (ADR-0166 dec. 2/3, ADR-0164 dec. 1/2). Parse is closed (ADR-0187), compile is
  closed here, and reach is the last of the three.

## Considered alternatives

- **Document-and-accept, unchanged.** ADR-0169's first option, and it is what dec. 4 does for the
  residual five — but applied to all six it keeps `visible_angles_cull_mode`, a host entry with no
  writer, which no argument supports.
- **Push through the port.** Not an option ADR-0169 ever offered — a handoff added it and this
  pass repeated it twice before `check_adr_quotes.py` asked for the source. Rejected as a
  mis-statement of the mechanism regardless: a push does not create the name. See Measurement.
- **Design them all away** (ADR-0169's third). Free for `visible_angles_cull_mode` and taken.
  Rejected for `psx_camera_angle` by dec. 4's per-frame/per-surface cost, and pointless for
  `psx_fx_stretch`, whose name the host needs for `Effects` and `Battle` regardless.
- **One seam for all three names.** Rejected by dec. 2's layout rule and because it would impose
  `psx_camera_angle` on the two cursor shaders, which never read it.
- **Put `psx_unit_stretch` in the stretch seam for completeness.** Rejected by dec. 2: it would
  take the requirement back to six for a name no addon shader reads.
- **Make arm 4 itself enforcing.** Rejected — arm 4's question genuinely needs a standalone
  project, and forcing an answer would mean inventing one. Arm 4b is a different question that
  does not.

## Amendment (2026-09-05): the Context's compile-error claim is editor-only

This ADR's Context states, citing the same engine line as ADR-0169, that *"the engine
treats a missing one as a **compile error**, not a warning"*. Measured 2026-09-05: that
is true **only under `Engine::is_editor_hint()`**, which `shader_language.cpp` requires
four lines above the error it emits. Outside the editor the shader compiles and the name
reads its type's zero, warning once per material at draw time.

**The decision is unaffected and the rule is if anything better motivated.** Arm 4b's
question — *may a system addon DECLARE a `global uniform`* — does not depend on how the
absence is reported, and a failure mode that is silent is a stronger reason to keep the
declaration surface small, not a weaker one. The Context's second sentence, that such a
shader *"is not self-contained: it is an install step charged to whoever installs the
addon"*, is exactly right and is the part that carries the decision.

The Context's other claim — that arm 4 reports rather than fails *"because in-walk there
is no standalone project to compile against"* — has also expired: there are five stranger
rigs and they compile these seams. The reason arm 4 still cannot enforce is the engine
gate above, not a missing project. See
[ADR-0238](0238-a-global-uniform-is-validated-only-in-the-editor-and-the-debt-is-silent.md).
