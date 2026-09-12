# An addon provides the names it can and injects the content it cannot, and the register scores the requirement

[ADR-0202](0202-installable-is-the-fork-plus-the-kernel-and-the-port.md) dec. 8 permits an
enable-time `ProjectSettings` write and dec. 9 sends the eight input actions to the same
answer, but neither says which way to go — dec. 8's own words leave it *"that pass's call"*.
Three tickets ([#689](https://github.com/timbermania/fft-monorepo/issues/689),
[#691](https://github.com/timbermania/fft-monorepo/issues/691),
[#692](https://github.com/timbermania/fft-monorepo/issues/692)) are each blocked on the same
unmade call, and dec. 9 says in its own words that D and E are one question. Settling it
inside whichever ticket got picked up first would put one pass's name on three tickets'
decision.

The call is made here, once.

🔴 **The thing that makes it a decision rather than a build is that the register and the goal
come apart.** `scan_actions` and `scan_globals` score *the addon naming host state*.
ADR-0202's goal is *the install having it*. An enable-time write makes the addon genuinely
installable and moves both arms **by zero** — so "make the register 0" and "make the addon
installable" are not the same instruction, and one of them has to be re-pointed.

Status: accepted (2026-08-28). Loop **pass 11** of extraction #3, on map
[#560](https://github.com/timbermania/fft-monorepo/issues/560). Settles
[ADR-0202](0202-installable-is-the-fork-plus-the-kernel-and-the-port.md) dec. 8's *"that
pass's call"* and dec. 9 with it; amends dec. 8's ProjectSettings-read rule and dec. 9's
stated test. Stands on
[ADR-0003](../../../docs/adr/0003-an-installed-addon-owns-five-global-names.md)
dec. 7 Arm A, which already shipped this exact instrument for the autoload channel. Does
**not** touch ADR-0202 dec. 5 (Class B is already ruled), dec. 6 (Class C, the mount point),
or ADR-0164 dec. 4 criterion 1.

## Context

### What is actually on the register

Measured on `7fff3cd90` (`main`, #641 merged), all four registers run:

    check_addon_install     rc=0   47 sites / 27 rows
      Class B  ROM-derived, un-shippable        9 rows
      Class C  layering inversion (dec. 6)      1 row
      Class D  input actions (dec. 9)          12 rows / 32 sites, 8 distinct names
      Class E  shader globals (dec. 8)          5 rows
      arm 4    fork-only, REPORTED, no target   8 files (conformant, dec. 3)

**D's eight names**: `camera_up`, `camera_down`, `camera_left`, `camera_right`,
`rotate_camera_cw`, `rotate_camera_ccw`, `unit_inspect`, `cursor_confirm`. Twelve rows over
eight names because `PAN_ACTIONS` and `CURSOR_ACTIONS` declare the *same four* in two files —
two rows per name, one per namer, because either file could be fixed alone.

**E's five names**: `psx_par`, `psx_dither_enabled`, `psx_fx_stretch`, `psx_cursor_stretch`,
`psx_camera_angle`. All five now declared in `exmateria_platform/display_port/` and reached
through an `#include` (ADR-0190), which is the shape `psx_par` always had.

### The instrument this decision needs already exists, in this monorepo, shipped

🔴 **`exmateria-sound/tools/check_globals.py`'s CREEP arm is the proposal, built, for the
autoload channel — and its docstring already contains the objection and the answer.** It says,
of the clause that matters:

> *"That last clause is read off the ADDON, not off the consumer. An earlier spelling scanned
> addon code for the names the consumer's `[autoload]` block happens to hold today, and that
> arm could not see the defect ADR-0003 decision 6 exists for … The arm now enumerates the
> addon's own singleton lookups and requires each to be a name `plugin.gd` registers, which is
> what decision 7 Arm A actually says and is **independent of what any consumer does next**."*

And it was not reasoned into place: *"Measured, not reasoned -- the seeded lookup passed
green."*

`exmateria_sound/plugin.gd` is the matching implementation — `_enter_tree` walks an
`AUTOLOADS` const and calls `add_autoload_singleton` for each name the project does not
already hold, `_exit_tree` removes only what it added. That addon is the one this monorepo
**releases in isolation**, and it provides rather than requires.

So the shape being decided here is not novel and not speculative. It is ADR-0003 dec. 7 Arm A,
ported from the autoload channel to the input-action and shader-global channels.

### The objection that is already written down, and is correct

⚠️ `addons/exmateria_render/plugin.gd` declines the same move in prose:

> *"`EditorPlugin.add_autoload_singleton()` exists and would do it, but only for a plugin the
> host has **ENABLED**, and this project enables neither of its addons (`project.godot` has no
> `[editor_plugins]` section at all). Wiring the registration to a switch nobody has thrown
> would make the port's availability depend on editor state."*

**Verified: `godot-learning/project.godot` has no `[editor_plugins]` section.** No `plugin.gd`
in this repo has ever had `_enter_tree` called. That is a live fact and it is the single most
important constraint on this decision — it is dealt with in dec. 4 rather than waved past.

### The port already reads `ProjectSettings` at runtime

`addons/exmateria_platform/display_port/PSXDisplay.gd:106`:

    var decl: Dictionary = ProjectSettings.get_setting("shader_globals/" + name, {})
    return float(decl.get("value", 0.0))

ADR-0202 dec. 8 says a runtime read *"stays forbidden — the addon's count is 0 today and must
stay 0."* That is true of `exmateria_battlefield` and **false of the install target**, which
dec. 2 defines as three addons including the port. The count is 1.

⚠️ And its miss is silent: an absent name yields `{}` yields **`0.0`**, indistinguishable from
a declared `0.0`. A `psx_par` of 0 collapses every vertex's x to zero. This is dec. 3's own
category — the blocker that produces no error at all — sitting inside the port's default
reader.

## Decision

**1. Split on what the addon CAN provide. PROVIDE for names; INJECT for content.**

  - **PROVIDE — class D input actions and class E shader globals.** These are names and
    defaults, nothing more. `plugin.gd` writes them at enable time. ADR-0202 dec. 8 already
    permits exactly this and dec. 9 already sends D to dec. 8's answer.
  - **INJECT — class B, ROM-derived content.** The addon can never ship `RANGETILE.tga` or
    `assets/maps/`; dec. 5 already ruled them un-shippable and already ruled the fix (the
    literal goes, a settable search root stays). Nothing here re-opens that.

This is not a compromise between two options. It is the distinction ADR-0202 already draws
between dec. 5 and dec. 8/9, made explicit and given a name: **an addon PROVIDES what it can
author and INJECTS what it cannot.** Authorship is the test, and it is the same test dec. 5
already applied when it separated Class A from Class B on **tracked-ness rather than
authorship** — a name has no bytes to track, so it is always providable.

⚠️ **Class B is not this decision's to make and is listed only to be excluded.** The handoff
that raised this framed INJECT-for-B as half the question; it is not. dec. 5 decided it. The
one thing still open on B is whether the search root's *default* is itself a `res://assets/`
literal — which arm 1 would still score — and that belongs to #689's builder, not here.

**2. The addon provides through `plugin.gd`, and `plugin.gd` may read `ProjectSettings` to
guard its own write.**

ADR-0202 dec. 8's *"the addon's count is 0 today and must stay 0"* is **amended**: the rule is
about *direction*, not about the symbol. A **runtime read that sources configuration the host
was expected to supply** stays forbidden. A **read that decides whether this addon's own write
is needed** is part of the write and is permitted — it is how `exmateria_sound/plugin.gd:46`
already does it, and its reason is a good one:

> *"A consumer that already declares the name (the in-repo game does, to keep its own autoload
> order explicit) must not get a duplicate."*

Without that carve-out, dec. 8 forbids the only idempotent spelling of the thing dec. 8
permits.

**3. Arms 2 and 3 stop scoring *the addon names it* and start scoring *the addon requires it
and no addon in the walk provides it*.**

This is the re-pointing the Context's 🔴 demands. Under PROVIDE the arms must measure the
install, not the mention, or a correct fix moves them by zero and the register stops tracking
its own goal.

🔴 **This does NOT re-open dec. 9's objection, and the reason is not the one the handoff
gave.** dec. 9 rejected keying the guard on the **host's** `project.godot`. ADR-0202 dec. 9's actual
words are *"a guard keyed on the host's `project.godot` would go blind the day the host
stopped declaring the action"* — ⚠️ **not** the *"guard keyed on the consumer"* spelling three
handoffs have now repeated. dec. 9 uses *a-guard-keyed-on-the-consumer* as the NAME of the
repo's prior failure in the clause after; the two got welded into one sentence somewhere
downstream and the misquote is what gets cited. The new
predicate reads the **addon's** provide list. The handoff offered ADR-0190's arm 4b as the
precedent; **arm 4b is the weaker precedent and should not be cited for this.** Arm 4b asks
*which addon a declaration sits in* — a structural fact about a file's location.
`check_globals.py`'s CREEP arm asks *does the thing this addon requires appear in the list
this addon's `plugin.gd` registers* — which is the identical predicate, already shipped,
already seeded, and already carrying the anti-consumer-keying argument in its own docstring.
Cite ADR-0003 dec. 7 Arm A.

**4. The provide is verified by EXECUTION, not by the register, and the register's zero may
never be read as evidence that the write works.**

This is dec. 3's constraint discharged rather than dodged. `project.godot` has no
`[editor_plugins]` section, so **in this repo the enable-time write never runs.** Every
consequence follows from that one fact:

  - A register that reads 0 after this change is reporting *the addon provides the name*. It
    is **not** reporting that the host stopped needing it, that the write executed, or that
    the written value is correct. The host will still declare all thirteen names, and should.
  - 🔴 **Therefore the register alone is a tautology and must not ship alone.** Its predicate
    is "a string appears in `plugin.gd`". Somebody can make the register green by typing
    thirteen names into a const array that no code path reaches. The guard cannot tell.
  - So the implementing pass **must** build, in the same commit as the arm change, a test that
    calls the registration path **directly** — not through the editor — against a settings
    surface it can inspect, and asserts each of the thirteen names lands with the right type
    and default. That test is the oracle; the register is the burn-down.
  - ⚠️ Playing the in-repo game verifies **nothing** about this change. A pass that reports
    "booted headful, no errors" as evidence for the provide has measured the branch where the
    write does not happen. Say so in the commit rather than letting a reader assume otherwise.

**5. `add_autoload_singleton` has no analogue for these two channels, and the raw write is
what dec. 8 permitted.**

`EditorPlugin` blesses autoloads with an API and blesses nothing for `input/*` or
`shader_globals/*`. Those are `ProjectSettings.set_setting(...)` plus `ProjectSettings.save()`.
That asymmetry is noted so the implementing pass does not go looking for an API that is not
there and conclude the decision is unbuildable. dec. 8 wrote *"an enable-time `ProjectSettings`
WRITE"* and not *"an `EditorPlugin` registration call"*, and this is why.

**6. The first enable in a bare project reports shader compile errors, and that is documented,
not fixed.**

Godot imports and compiles the addon's shaders when the project opens; the plugin is enabled
after. So the honest install sequence is *copy the three addons → open → enable → reload*, and
the first open logs compile failures for the five globals. This is ordinary Godot addon
behaviour and it is written into `addons/exmateria_battlefield/README.md` under ADR-0202
dec. 4, which already rules that the dependency claim lives in the README and the register.
An install step nobody wrote down is one somebody re-derives by crash — dec. 3's lesson,
applied to the step this ADR creates.

**7. The port's `shader_global_default` 0.0 fallback is named here and fixed by #692's
builder.**

Under PROVIDE the read at `PSXDisplay.gd:106` becomes correct by construction — the addon
wrote what it reads. It is still true that an absent or renamed name yields a silent `0.0`, so
the fallback should push an error rather than a degenerate value. This ADR does not build it;
it refuses to leave it undocumented while amending the decision that made the claim *"the
addon's count is 0"* about a tree where it is 1.

## Prediction

Written before the implementing pass runs, per ADR-0202 dec. 10's practice.

  - Arm 2 goes **12 rows → 0**, arm 3 **5 → 0**, register **47/27 → 25 sites / 10 rows** (B 9,
    C 1). Both arms' burn-down entries go **stale** together — 17 rows at once — and the stale
    arm is what grades the move.
  - The unlisted arm stays at **0**: no new site is created, only a provide list.
  - `check_lattice_ports`, `check_lattice_doors`, `check_lattice_publish` are **untouched** —
    different axis. If any of them moves, the change reached further than it should have, and
    that is the signal to stop. Closing criterion 3 once created criterion-2 violations, 0 → 1
    and 0 → 8; this family does not get to assume independence, it checks it.
  - The host's `project.godot` keeps all 8 actions and all 5 globals. A diff that removes them
    has misread dec. 4.
  - `check_globals.py` (the sound package's) is **unaffected** — different addons, different
    channel. If it moves, the new arm was written into the wrong tool.

## Consequences

**The register's meaning changes, and its header has to say so.** After this, `check_addon_
install` arms 2 and 3 answer *is this name unprovided*, not *is this name mentioned*. A reader
who carries the old meaning forward will read a green arm as "the addon does not use input
actions", which is false and will stay false.

**Two instruments now answer the install question and they must not drift.**
`check_addon_portability.py`'s arm 4 already reports the host `[shader_globals]` block as
DEBT. Once the addon provides those names, arm 4's debt is discharged and its wording is
stale. The implementing pass owns reconciling the two, the same way ADR-0202's Consequences
assigned the portability/install reconciliation to the pass that closes Class B.

**This does not make the addon installable on its own.** It makes D and E installable. Class B
(9 rows) and Class C (1 row) remain, and Class C is a mount point, not a path. Axis B closes
when all four classes do, and reporting this pass as "installable" would be ADR-0202 dec. 1's
named failure.

⚠️ **The corpus has a duplicate number.** Two distinct files are numbered **0196** across refs
— `0196-battle-cast-is-a-replay-derived-view-of-the-catalog.md` and
`0196-the-marking-belongs-to-the-schema-and-a-respelling-is-never-the-reason.md`. Filenames
differ so git merges both without conflict and no guard sees it. Found while verifying 0203
was free; recorded here because the next number-taker will hit it too. Not this ADR's to fix.

## Alternatives considered

**INJECT everywhere — the host declares all thirteen, the addon names none.** Rejected. It is
not reachable: an addon cannot *stop naming* an input action it binds or a global uniform its
shader reads without deleting the behaviour. The only spelling of "the addon names none" is
per-material uniforms pushed by the port, and **ADR-0190 dec. 4 already declined that for
`psx_camera_angle` by name**, on a measurement — per-frame, every map surface, a rebuild-heavy
path. Overturning a measured refusal requires a new measurement, and this pass has none.
INJECT is therefore not the conservative option; it is the option with no implementation.

**Keep the arms scoring mentions and accept that a correct fix moves them by zero.** Rejected,
because a burn-down that cannot reach 0 stops being read — ADR-0202 dec. 3 says exactly this
about scoring the fork, and declines to score the fork for that reason. Scoring the mention
after the provide exists is the same defect with a different subject.

**Do the write from a runtime autoload instead of `plugin.gd`, so it runs in this repo.**
Rejected, and it is the tempting one, because it would make the change verifiable by booting
the game. But `exmateria_battlefield` publishes **no autoloads at all** — ADR-0183/#564
re-pointed the last three onto `class_name`s — so this would re-introduce the exact host
registration that pass removed, to buy test convenience. dec. 4's direct-call test buys the
same confidence without it.

**Settle it inside #692 and let #689/#691 follow.** Rejected on ADR-0202 dec. 9's own grounds:
D and E are one question. Three tickets inheriting a decision made in one of them is how this
family produced four refuted ADR premises — the reasoning ends up in a commit message that the
other two tickets' readers never see.
