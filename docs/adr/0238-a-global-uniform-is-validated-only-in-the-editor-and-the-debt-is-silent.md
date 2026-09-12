# A `global uniform` is validated only in the editor, and the debt it leaves is silent

The session handoff named one piece of work as *"the strongest next piece"*: there are five
stranger rigs now, all five pass, and two `check_addon_portability.py` headings still say the
standalone project they are waiting for does not exist. Make the arms ENFORCING for any addon
that has a rig.

Measured. **Arm 4 cannot be made enforcing by a stranger rig, and the reason falsifies a
sentence this package repeats in fourteen places.** A `global uniform` a project has not
declared in `[shader_globals]` is a compile error **only in the editor**. Outside it — which
is every rig run, every `godot --path X scene.tscn`, and every shipped game — the check is
skipped, the shader compiles, and the missing value reads back as its type's zero.

Status: accepted (2026-09-05). Corrects the mechanism in
[ADR-0169](0169-platform-ships-to-its-own-address-and-shipping-a-file-is-not-shipping-a-shader.md)
dec. 4 and
[ADR-0190](0190-a-global-uniform-earns-its-host-entry-by-having-a-writer.md)'s Context, and
leaves every decision either of them made standing. Reads
[ADR-0220](0220-the-addon-that-declares-a-global-uniform-provides-it.md), whose provide rule is
unaffected and whose own Context already carries the correct consequence beside the wrong
mechanism. Reads
[ADR-0194](0194-a-test-belongs-to-the-addon-it-can-run-without-the-game.md) dec. 4 for
why the new arm is rig-owned.
Tickets: none filed here; #899's scope is corrected in the Measurement below.

## Context

### The quote was accurate and the gate four lines above it was not in the quote

ADR-0169's Measurement cites the engine by file and line, and the string is really there:

> `servers/rendering/shader_language.cpp:9866` in the 4.8 fork:
>
> > Global uniform '%s' does not exist. Create it in Project Settings.

ADR-0169 dec. 4 then reasons from it that *"the engine's response is stricter"* than arm 2's
parse error. ADR-0190's Context restates it from the same line number: *"the engine treats a
missing one as a **compile error**, not a warning"*.

Here is `shader_language.cpp` at 9862, four lines above the quoted error:

```cpp
if (uniform_scope == ShaderNode::Uniform::SCOPE_GLOBAL &&
        Engine::get_singleton()->is_editor_hint()) {
    // Type checking for global uniforms is not allowed outside the editor.
    DataType gvtype = global_shader_uniform_get_type_func(name);
    if (gvtype == TYPE_MAX) {
        _set_error(vformat(RTR("Global uniform '%s' does not exist. Create it in Project Settings."), ...
```

The engine's own comment states the rule. Nothing was misquoted; the enclosing condition was
never read. This is the shape the corpus already knows from a different toolchain — a
transcription is not the referee, the running thing is — and it survived because every later
site cited ADR-0169 dec. 4 rather than the engine.

### The conclusion was right the whole time, and one site already had the mechanism

Nothing here argues an addon may stop providing its `[shader_globals]` entries. ADR-0220
dec. 1, arms 4b and 4c, `plugin.gd`'s `PROVIDED_GLOBALS` and `PlatformProvidesTest` are all
correct and all stay exactly as they are. Only the sentence about *what breaks* was wrong.

And the corpus already contained the true answer, in ADR-0220's own Context, in the sentence
immediately after the false one:

> A `global uniform` a project has not declared in `[shader_globals]` is a **COMPILE** error
> — it fails the whole shader, not one file's parse (ADR-0169 dec. 4). And `PSXDisplay
> .shader_global_default` turns an absent `psx_par` into `0.0`, which collapses every
> vertex's x. Blank screen.

The second sentence is the measured behaviour. The first is not, and it is the one that got
copied. ADR-0203 dec. 7 says the same thing again — *"an absent or renamed name yields a
silent `0.0`"* — and neither reached the thirteen other places that kept saying COMPILE.

## Measurement

### The engine, on both binaries, at every stage that could matter

A witness uniform is declared after the subject; a shader that fails to compile exposes no
uniforms at all, so *witness present* is *compiled*. This is `stranger_install.gd`'s own idiom.

| case | fork 4.8 | stock 4.7.1 | reported |
|---|---|---|---|
| clean shader (control) | compiles | — | — |
| deliberate syntax error (**live control**) | **fails** | **fails** | `SHADER ERROR` + `Shader compilation failed` |
| `global uniform` no project declares | **compiles** | **compiles** | nothing |
| the same, as a real `.gdshader` file | **compiles** | **compiles** | nothing |
| the same, via `#include` of a seam — *the rig's exact arm shape* | **compiles** | **compiles** | nothing |
| editor import pass (`-e --quit`) over that file | — | clean | nothing |
| running with `is_editor_hint()` **true** | **fails** | — | `SHADER ERROR: Global uniform 'x' does not exist` |

The only report outside the editor arrives at DRAW time, once a material using the name is
actually rendered, and it is a warning:

    WARNING: Shader uses global parameter 'zzz_never_declared_file', but it was removed at
    some point. Material will not display correctly.
       at: update_uniform_buffer (.../material_storage.cpp:767)

The value reads as the type's zero. So the real failure mode is: **compiles, installs, runs,
draws wrong, warns once per material at draw time.** That is strictly worse than the
documented compile error, which would at least have failed loudly at install.

### The rig is blind, and it passes today for that reason

`tests/stranger/exmateria_platform/` stages `exmateria_platform` into a project whose
`project.godot` has **no `[shader_globals]` section at all** — its own comment says so — and
`stranger_install._test_every_shader_include_compiles` compiles all five seams that declare
the addon's six `global uniform`s. It reports 29 passed, 0 failed. Every one of arm 4's twelve
debt lines is in that addon, and the rig cannot see one of them: compilation is its witness,
and compilation succeeds.

So the handoff's proposal inverts. The rigs are not the missing enforcement for arm 4; they
are a demonstration that arm 4's subject is invisible to a compile-based check.

### Arm 2's register is already empty, so "make it enforcing" is a ratchet and not a discovery

The other heading named for the same treatment is arm 2's standalone-parse DEBT. It does not
print today: `check_addon_portability.py` guards it with `if debt:` and #848 discharged the
last row. Its premise — *"there is no standalone project to parse against yet"* — is expired
in the same way arm 4's is, but converting it enforces nothing that is not already at zero.
The same is true of the `cross-addon class_name DEBT` heading, which the handoff counted as
one of two and is in fact one of three.

### The other named hypothesis: goal #7 and the shader-global register are nearly disjoint

The handoff proposed, explicitly as a claim and not a finding, that goal #7's residual jargon
and arm 4's twelve shader-global lines are *largely the same names*, so one provider-side
rename would discharge both. Measured against `score_goals.jargon_hits` and the guard, over
`addons/exmateria_sprite_rig`'s 22 lines:

| what the line names | lines | owner |
|---|---:|---|
| `psx_ot_computed_depth` / `psx_ot_depth(…)` | 10 | **kernel** — `exmateria_schema` |
| `#include` of a kernel seam (`psx_ot_depth`, `psx_color_stack`) | 3 | **kernel** |
| `psx_color_apply(…)` | 1 | **kernel** |
| `#include` of a platform seam (`psx_par`, `psx_unit_stretch`) | 4 | platform |
| **binds** a shader global (`psx_unit_stretch`, on the `psx_par_anchor` call) | 2 | platform |
| `PSX_FOLD_GAIN` | 2 | goal **#8**, not #7 |

**2 of 22 bind a shader global; 6 of 22 touch one of the seven names at all; 14 of 22 belong
to the kernel.** In the other direction all twelve shader-global debt lines are
`exmateria_platform`'s own files and none is in `exmateria_sprite_rig`, so the two registers
share **zero rows**. One provider-side rename does not discharge both, and `score_goals` has
no partial credit, so goal #7 does not move at all.

The relocation this produces is the useful part. #899's title books the block to *a
PROVIDER-side `psx_` retirement*, and the majority provider is the **kernel**, not the
platform — `psx_ot_*` and `psx_color_*` under `addons/exmateria_schema/`, named across five
addons and 23 files. ADR-0129 dec. 10 already ruled that rename — *"The generic includes drop
their `psx_` prefix, and gain no replacement"* — and its trigger, *"The rename happens when
`Render` extracts, not here"*, fired at extraction #1. It never ran, because the file landed
in `addons/exmateria_schema/` rather than the `addons/render/` path dec. 10 wrote. #583's body
already names `psx_ot_depth.gdshaderinc` as unfinished; its **acceptance criteria do not**,
which is how the kernel half has stayed nobody's.

## Decision

**1. The mechanism is editor-only validation; every rule built on the old mechanism stands.**
`global uniform` type checking runs under `Engine::is_editor_hint()` and nowhere else. The
provide rule (ADR-0220 dec. 1), arm 4b, arm 4c, `PROVIDED_GLOBALS` and `PlatformProvidesTest`
are unchanged — they were reasoning to the right conclusion from a wrong premise, and the
conclusion is load-bearing for a reason this ADR strengthens rather than weakens.

**2. The debt is SILENT, and that is a promotion, not a downgrade.** The sixteen sites are
corrected to say what happens: the shader compiles, the missing global reads its type's zero,
and the only report is a per-material draw-time warning. A reader who believes the old
sentence expects the failure to announce itself at install and will not look for a blank
screen. ADR-0203 dec. 7 and ADR-0220's Context already said so; they stop being the exception.

**3. Arm 4 stays REPORTING, and its heading loses a premise that is now false twice.** The
heading claimed *"there is no standalone project to compile against yet"* — there are five,
and they compile the seams — and predicted the debt would be *"stricter than the parse debt
above when it lands"*. Neither holds. The new heading gives the actual reason it cannot
enforce, which is the engine's gate and not a missing project. An IOU that names the wrong
blocker is worse than one that names none, because it sends the next session to build
something that cannot work.

**4. A rig-owned arm pins the engine fact, and it goes RED ON GOOD NEWS.**
`tests/stranger/exmateria_platform/global_uniform_unvalidated.tscn` asserts, in a project that
declares no `[shader_globals]`: that a broken shader does **not** compile (the live control),
that an undeclared `global uniform` **does**, and that all five of the addon's own seams do.
If a future engine validates outside the editor, the arm fails — and the correct response is
not to fix the arm, it is to make arm 4 enforcing, because the rigs would finally be able to
see the debt. This is `stranger_fork_absent.gd`'s shape and ADR-0194 dec. 7's argument: a
claim nothing checks is what these rigs exist to end.

**5. It is rig-owned, not addon-owned.** The claim is only true where no `[shader_globals]`
exists, and `godot-learning/project.godot` declares seven. An addon-owned test would be
falsified by its own host. ADR-0194 dec. 4 in the other direction, the same argument `rig.sh`
already makes for the sprite rig's arm.

**6. Arm 2's and the cross-addon heading's premises are corrected in place, and neither is
converted.** Both registers are empty. Converting an empty register to enforcing is a ratchet
against regression, which is worth having and is not what the handoff was buying; it is filed
as a note in the guard rather than built here, because nothing measurable changes.

**7. Goal #7's majority owner is the kernel, and it is recorded where the tickets are.** The
6/22-versus-14/22 split above goes on #899, whose framing sends a reader to
`exmateria_platform`. No new ticket is filed: #583 already carries ADR-0129 dec. 10 and
already names `psx_ot_depth.gdshaderinc`; what it lacks is the kernel half in its acceptance
criteria, which is a scope correction on an open issue rather than a new one.

## Consequences

- **Fourteen sites** carried the false mechanism and now describe the silent zero-default:
  `tools/check_addon_portability.py` (4), `addons/exmateria_platform/README.md`,
  `addons/exmateria_platform/plugin.gd`, `psx_sprite_stretch.gdshaderinc` (2),
  `psx_unit_stretch.gdshaderinc`, `addons/exmateria_battlefield/README.md`,
  `addons/exmateria_battlefield/terrain/fft_visible_angles.gdshaderinc`, and dated amendments
  on ADR-0169, ADR-0190 and ADR-0220.
- **Two more sites said it and were RIGHT**, and are annotated rather than corrected: the
  *"FIRST ENABLE IN A BARE PROJECT LOGS SHADER COMPILE ERRORS"* blocks in both `plugin.gd`s
  (ADR-0203 dec. 6). The editor open is the gated path, so that is the one place the compile
  error is real — the noisy case is the benign one and the quiet case is the damaging one.
- The platform rig gains its first rig-owned scene. `rig.sh`'s rig-owned loop has existed
  since ADR-0229 and has run zero scenes until now, so this is also the first exercise of it
  outside the sprite rig.
- **Arm 4 is now the only "Not enforced" heading in the guard that prints**, and it prints for
  a reason that is checked rather than promised.
- What is still unbuilt and is NOT claimed here: nothing detects a missing `[shader_globals]`
  entry *at runtime*. The draw-time warning is the engine's and no arm reads it. Arm 4c's
  static declarer/provider diff remains the only enforcement, and it cannot see a consumer
  that includes a seam whose provider is never enabled — ADR-0203 dec. 1's enable-time gap,
  unchanged by this ADR.
