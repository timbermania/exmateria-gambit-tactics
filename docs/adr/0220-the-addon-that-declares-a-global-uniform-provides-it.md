# The addon that declares a `global uniform` provides it

The sprite rig does not install, and it fails **silently**. Its two unit shaders
`#include` two of the port's seams — which is legal, the port is in the rig's install
target — and what those includes pull onto the compile surface is two `global uniform`s
that nothing in the target declares:

    addons/exmateria_platform/pixel_aspect/psx_par.gdshaderinc:50        global uniform float psx_par;
    addons/exmateria_platform/display_port/psx_unit_stretch.gdshaderinc:24  global uniform float psx_unit_stretch;

A `global uniform` a project has not declared in `[shader_globals]` is a **COMPILE** error
— it fails the whole shader, not one file's parse (ADR-0169 dec. 4). And `PSXDisplay
.shader_global_default` turns an absent `psx_par` into `0.0`, which collapses every
vertex's x. Blank screen.

`psx_par` is provided — by `addons/exmateria_battlefield/plugin.gd:110`, off a declaration
that lives in `addons/exmateria_platform/`. `psx_unit_stretch` is provided by **nothing in
the tree at all**, and has not been since #744 split it into its own seam.

## Context

### The declaration and the provide are in different addons, and the install target is per subject

ADR-0202 dec. 2 makes an install target a property of the SUBJECT: the battlefield's is
fork + kernel + port + itself, and the sprite rig's is fork + kernel + port + itself. The
battlefield addon is in neither of the rig's roots and must not be — the rig depending on
it is the Class C layering inversion dec. 6 names.

So one declaration of `psx_par` gets two verdicts. `check_addon_install.py` arm 3 reads it
**green** for `exmateria_battlefield` and **red** for `exmateria_sprite_rig`, and both
readings are correct. That is the register's widening earning its keep, not a
contradiction — but it means the current provide answers the question *for one consumer*,
and a rule that has to be re-answered per consumer will be missed for the next one. It
already was.

### The port is not a disinterested declarer — it is a consumer of its own names

`addons/exmateria_platform/display_port/PSXDisplay.gd` calls `shader_global_default()` on
five of the six names in `register_tunables()`, and pushes six to the `RenderingServer`.
Its own error message, before this ADR, read:

> *"A project consuming `exmateria_platform` must declare it, or enable
> `exmateria_battlefield`, whose plugin provides it."*

That is the port directing its consumers at a sibling addon to obtain the port's own
names. ADR-0203 dec. 7 predicted the opposite — *"Under PROVIDE the read at
`PSXDisplay.gd:106` becomes correct by construction — the addon wrote what it reads"* —
and it is **false in the built tree**, because "the addon" is two addons. The error string
is where the author noticed and wrote it down.

### `check_addon_portability.py` already rules who may DECLARE, and stops there

Arm 4b (ADR-0190) enforces that only a non-system addon — the kernel and the platform port
— may declare a `global uniform`. It is enforcing, and it went green at ADR-0190 by moving
the battlefield addon's own declarations into the port. Nothing then asks what happens to
the name after it is declared. The declaring addon may provide it, another addon may, or
nobody may, and all three read identically.

### Why nothing said so for a whole extraction

`psx_unit_stretch.gdshaderinc` was created at #744, when the unit shaders moved into
`addons/exmateria_sprite_rig/` and `check_addon_portability`'s global-uniform arm went red
on two lines a system was declaring. The seam fixed the declaration and created a name no
`plugin.gd` provides.

The only instrument that could have caught it was the install register — and
`check_addon_install.py` did not score `exmateria_sprite_rig` until #746, a whole
extraction later. A rule that needs a SUBJECT cannot answer "is this declaration
provided", because the answer arrives only when somebody thinks to add the subject.
`check_addon_portability`'s arm 4 already reports the name as `[host]` in a DEBT block; a
reporting row in a passing guard is not a rule.

Status: accepted (2026-09-02). Extends **ADR-0203 dec. 1** — which ruled *what* is
providable and *how*, scoped to the only subject the register then had — by ruling *who*.
Built at #746's follow-up; the register moves are in the Prediction below.

## Decision

**1. The addon that DECLARES a `global uniform` PROVIDES its `[shader_globals]` entry.**

In its own `plugin.gd`'s `const PROVIDED_GLOBALS`, with `project.godot`'s type and
default. Not the addon that *reads* it, not the addon that *pushes* it, not whichever
addon a given install target happens to contain — the one whose file carries the
`global uniform` line.

The declaration IS the requirement: including the seam is what puts the name on a
consumer's compile surface, so every future includer inherits the same debt off the same
line. Keying the provide to the declarer closes it once, for every consumer present and
future. Keying it to the consumer is O(N addons) in work and O(N) in chances to forget —
and the sprite rig is the first N to forget.

Composed with ADR-0190's arm 4b — *only the kernel and the platform port may declare one*
— dec. 1 yields: **only the port declares, the declarer provides, therefore only the port
provides.** One array, in the addon that owns the seams, is the whole `[shader_globals]`
contract of this addon family.

**2. `exmateria_platform` provides all six; `exmateria_battlefield` provides none.**

The port's six are `psx_par`, `psx_dither_enabled`, `psx_fx_stretch`, `psx_cursor_stretch`,
`psx_unit_stretch` and `psx_camera_angle`. `exmateria_battlefield`'s `PROVIDED_GLOBALS`
becomes `[]`; it keeps `PROVIDED_ACTIONS` and every line of the provide machinery that
serves them, because ADR-0203 dec. 1's input-action half is untouched by this ADR.

⚠️ **The battlefield does not KEEP its five as a belt-and-braces copy**, and the reason is
ADR-0147/0148's standing rule — when two registers describe the same set you diff them,
you do not duplicate them. (The rule is **not** ADR-0146's; ADR-0149 records that
attribution as a defect and `tools/check_adr_quotes.py` carries it as a worked example.)
Two arrays
holding the same five defaults is a second home for the number that ADR-0203 dec. 7 spent
a decision making load-bearing, in the one place where disagreeing would present as a
blank screen. The battlefield loses nothing by shedding them — `exmateria_platform` is in
its own install target, so `provided_by_walk` finds them there.

**3. `check_addon_portability.py` arm 4c enforces dec. 1, and it keys on the DECLARING
ADDON, not on "provided by anything".**

🔴 `!= this addon` and not `is None`, and the difference is the whole arm. `psx_par` has
been provided for an entire extraction, by the wrong addon, and an `is None` predicate
reads that green — which is precisely the state that let `exmateria_sprite_rig` be
uninstallable while every guard in the family passed.

It is ENFORCING, on arm 4b's own ground: this asks *which addon the declaration sits in
and whether that addon's `plugin.gd` names it*, and both halves are facts about this tree,
answerable now, with no standalone project to compile against. It sits beside 4b because
it is 4b's other half.

⚠️ Its provide map comes from `_install_register_provides()`, which swallows every
exception and returns `{}` — written for the REPORTING arm 4, where an empty dict silently
reverts each row's wording. An ENFORCING arm reading the same `{}` reds **every**
declaration in the tree. That asymmetry is the licence to enforce on it, and a
`if not provides: skip` guard would convert it back into the silent direction.

**4. `psx_gamma` is excluded, and the exclusion is the ADR's, not an oversight.**

`PSXDisplay.gd` pushes it and reads its default, but its `global uniform` declaration
lives in the HOST — `src/ui3/shaders/formation_box.gdshaderinc:27`,
`src/ui3/shaders/formation_orb.gdshaderinc:20` and
`assets/shaders/effect_particle_stp.gdshaderinc:56` — and in no addon. Under dec. 1 it is nobody's
to provide, and arm 4c cannot grade it. Its absence is also REPORTED rather than silent
since ADR-0203 dec. 7 built the `push_error`, which is the opposite of the failure mode
this ADR exists to end.

Whether the port should provide a name it reads but does not declare is a real question
and it is left OPEN. Answering it "yes" would make the provide list stop being a function
of the declarations, which is what makes dec. 3's diff checkable in both directions.

**5. The arm does not ship alone.**

ADR-0203 dec. 4's constraint applies to arm 4c verbatim and for the identical reason: its
predicate is *a string appears in `plugin.gd`*, and six names typed into an array no code
path reaches would green it. `addons/exmateria_platform/tests/PlatformProvidesTest.gd`
calls `provide_into()` directly against an inspectable double and asserts each name's type
and default; it ships in the same commit as the arm change, and it runs in the STRANGER
project (`tests/stranger/exmateria_platform/run.sh`, ADR-0194), which is the only place in
this repo where *a project that did nothing for this addon* is real.

Its seventh arm is the one that is not a copy of `BattlefieldProvidesTest`'s: it reads the
`global uniform` lines out of the addon's own `.gdshaderinc` files at runtime and diffs
them against `provided_keys()` in BOTH directions. A seventh declaration added tomorrow
with no provide fails there as well as in arm 4c, and so does an entry left behind by a
deleted seam.

**6. The `[shader_globals]` block a consuming project pastes is SIX entries, and it is the
port's README that states it.**

`addons/exmateria_platform/README.md` carried a five-entry block and the sentence
*"`psx_gamma` and `psx_unit_stretch` … are declared at HOST call sites and read by no
addon shader"*. The `psx_unit_stretch` half stopped being true at #744, which moved the
declaration into this addon and the reader into `exmateria_sprite_rig`. The README's own
note says keeping that list true is a reader's job and not a guard's; dec. 3 makes it a
guard's, and the README now points at `PROVIDED_GLOBALS` as the single source rather than
restating it.

## Prediction

Written before the implementing pass runs, per ADR-0202 dec. 10's practice.

  - Arm 4c reads **6 rows** before the provide — 1 `[unprovided]` (`psx_unit_stretch`) and
    5 `[wrong addon]` (provided by `exmateria_battlefield`) — and **0** after. Six is the
    count of `global uniform` declarations under `addons/`, so the before-reading is
    *every declaration in the tree*, which is what "the declarer provides none of them"
    means.
  - `check_addon_install`'s axis B goes **`exmateria_sprite_rig` 2 → 0** and
    `exmateria_battlefield` stays **0**. The battlefield staying 0 while its
    `PROVIDED_GLOBALS` empties is the load-bearing half: it is what proves
    `provided_by_walk` finds the port inside the battlefield's own target, rather than the
    battlefield having been green off its own array all along.
  - The install register's two Class E rows go **stale together** and are deleted. E goes
    2 → 0; the rig's register goes 2 rows / 2 sites → **0**.
  - `check_addon_portability`'s arm 4 shader-global DEBT stays at **12 lines** — the
    declarations and pushes do not move — but 2 rows re-tag `[host]` → `[provided]`
    (`psx_unit_stretch`, both its declaration and its push). `psx_gamma`'s 1 row stays
    `[host]`, and that is dec. 4 visible in the report.
  - `check_lattice_scene`'s criterion 4 is **untouched at 7**. Different axis (ADR-0202
    dec. 1). If it moves, this change reached further than it should have.
  - `check_addon_globals` is **untouched**: no `class_name` is added or removed.
  - `BattlefieldProvidesTest` goes 13 names → **8**, seven arms → six (the globals arm
    retires to the port's test). Its `provide_into` returning 8 rather than 13 is the
    assertion that catches a `PROVIDED_GLOBALS` accidentally left populated.

## Consequences

**A consuming project must now ENABLE `exmateria_platform`'s plugin, and previously it did
not have to.** The port's `plugin.gd` did nothing before; a consumer could copy the addon
in and never enable it. This is a real new install step and it goes in the README beside
the existing one. It is not a new *class* of step — ADR-0203 dec. 6 already established
that the honest sequence is *copy → open → enable → reload*, and the first open still logs
shader compile errors for the same reason.

**The port's `plugin.gd` docstring's opening claim is now false and is rewritten.** It
read *"There is nothing to install here that this file can install"*. That was always
true of autoloads and `#include` targets, for the reasons `exmateria_render/plugin.gd`
states, and it was never true of `[shader_globals]`. The autoload and include reasons are
kept; the blanket claim goes.

**`tests/stranger/exmateria_platform/project.godot`'s note is amended.** It reads *"THE
ADDON IS NOT ENABLED HERE, and for this addon that is the whole claim.
`exmateria_platform` installs nothing"*. The rig still does not enable the plugin — it
cannot, and dec. 5's oracle calls the write directly instead — but "installs nothing" is
no longer the claim being made.

**ADR-0190 dec. 4 still holds, and its block grows by one.** dec. 4 ruled that goal #5's
shader half is met *"as an install step, not as zero dependencies"*, documented once in
`addons/exmateria_platform/README.md` as a five-name block to paste. Nothing here overturns
that: the dependency is still real and the install step is still real. What changes is who
performs it — a `plugin.gd` write rather than a human paste — and that the block is six
names, because `psx_unit_stretch` joined the addon at #744 and dec. 4 predates it.

**Arm 4c is a rule about a population of six, and every one of them is in one addon
today.** If a second non-system addon ever declares a `global uniform`, dec. 1 binds it
identically and arm 4c will say so without being edited. That is the difference between
this and a burn-down.

**This does not make the sprite rig installable.** It closes axis B's Class E for that
subject — 2 rows to 0, which is all four arms of `check_addon_install` at 0 for the first
time. Axis A's criterion 4 is 7 and cannot reach 0 as currently scored; reporting this as
"the rig installs" would be ADR-0202 dec. 1's named failure.

## Alternatives considered

**The CONSUMER provides — the sprite rig's `plugin.gd` gains the two names it needs.**
Rejected. It is the shape the tree already had, and the tree is what raised the defect: it
answers the question per subject, so the answer must be re-derived every time an addon
starts including a seam, and there is no instrument that can ask it without a subject
list. It also duplicates a default whose wrongness is a blank screen, once per consumer.
Its one genuine advantage — a consumer that enables only the addon it wants gets its
globals — is bought back by dec. 1's install step, which is one line of README.

**Both provide: the port adds all six and the battlefield keeps its five.** Rejected on
ADR-0147/0148's diff-don't-duplicate rule. The `has_setting` guard makes the double write harmless at runtime, so this is
not a correctness argument; it is that two arrays holding `psx_par`'s 1.0 is two places
for it to be edited and one place for it to be edited wrong, in the value ADR-0203 dec. 7
spent a decision on.

**`exmateria_render` provides.** Rejected as unreachable rather than as a bad idea: it is
not in either subject's install target — the rig's target is fork + kernel + port + itself
and `exmateria_render` was measured out of it, adding zero reaches — so `provided_by_walk`
would never see it and both arms would still be red.

**Stop declaring the names: push per-material uniforms from the port instead.** Rejected,
and it is somebody else's rejection. ADR-0190 dec. 4 declined exactly this for
`psx_camera_angle` on a measurement — it changes every frame and is read by every map
surface, so a `ShaderMaterial` parameter means a per-material push on a rebuild-heavy
path. Overturning a measured refusal requires a new measurement and this pass has none.

**Leave arm 4c REPORTING, like arm 4 beside it.** Rejected. Arm 4 reports because it asks
whether the HOST declares a name, which is unanswerable in-walk. Arm 4c asks which addon a
declaration sits in and whether that addon's `plugin.gd` names it, and both are facts
about this tree — the same ground on which 4b enforces. And a reporting row is what this
name already had: `psx_unit_stretch` sat in arm 4's DEBT block tagged `[host]` for an
entire extraction, inside a guard that exited 0.

## Built (2026-09-02)

Every prediction above held, measured on this branch after the provide landed. The one
number worth reading twice is the second: **`exmateria_battlefield` stayed at 0 while its
`PROVIDED_GLOBALS` emptied**, which is what proves `provided_by_walk` finds the port
inside the battlefield's own install target rather than the battlefield having been green
off its own array all along. Had that gone red, dec. 2 would have been wrong and the two
addons would both have had to provide.

    check_addon_portability   arm 4c            6 rows -> 0, rc 0
                              arm 4 DEBT        12 lines, unmoved; `psx_unit_stretch`'s
                                                two rows re-tagged [host] -> [provided],
                                                `psx_gamma`'s one row still [host]
    check_addon_install       axis B            exmateria_battlefield 0 (was 0),
                                                exmateria_sprite_rig 2 -> 0
                              Class E           2 rows -> 0, `_SPRITE_RIG_ROWS` now empty
                              arm 3 provider    battlefield: platform(6) + battlefield(8
                                                actions); rig: platform(6)

The six rows arm 4c read before the fix were **every `global uniform` declaration under
`addons/`** — one `[unprovided]` and five `[wrong addon]`. That is dec. 1's premise stated
as a measurement: before this ADR, no declaration in the tree was provided by its own
addon.

## Amendment (2026-09-05): the Context's first sentence is wrong and its second is right

The Context opens with two sentences about what a missing `[shader_globals]` entry costs:

> A `global uniform` a project has not declared in `[shader_globals]` is a **COMPILE** error
> — it fails the whole shader, not one file's parse (ADR-0169 dec. 4). And `PSXDisplay
> .shader_global_default` turns an absent `psx_par` into `0.0`, which collapses every
> vertex's x. Blank screen.

Measured 2026-09-05: **the first sentence is false and the second is the actual
behaviour.** `shader_language.cpp` gates global-uniform validation on
`Engine::is_editor_hint()`, so outside the editor there is no compile error — the shader
compiles and the name reads its type's zero, which is precisely the `0.0` the second
sentence describes. The two were never alternatives; the blank screen is what happens,
and it happens with nothing in the log but a draw-time warning.

**Every decision here stands, and dec. 1 is load-bearing for a stronger reason than it
knew.** *The addon that declares a `global uniform` provides it* is the only thing
standing between a consumer and a silent wrong render. See
[ADR-0238](0238-a-global-uniform-is-validated-only-in-the-editor-and-the-debt-is-silent.md).
