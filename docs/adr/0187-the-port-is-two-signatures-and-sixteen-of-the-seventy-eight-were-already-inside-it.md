# The port is two signatures, and sixteen of the seventy-eight were already inside it

[#588](https://github.com/timbermania/fft-monorepo/issues/588) is the last of `Battlefield`'s
GDScript standalone-parse debt: every line inside an addon that names a name only the HOST's
`project.godot [autoload]` block creates. [ADR-0175](0175-a-port-answers-arm-1-and-not-arm-2-and-the-debug-residue-was-print-statements.md)
dec. 2 settled the shape — a `class_name` façade in `addons/exmateria_platform/`, soft-bound to
the singleton by node path — and left the build to a later pass.

Three things the design did not say, each measured below. The façade is **two** classes, not
one, because there are two autoloads and one class cannot forward both. **Sixteen** of the 78
lines cost nothing at all to pay, because they were the port naming a name inside its own
addon. And `get_value` changes **arity**, which the ticket asserts it does not, in the same
paragraph that asserts the thing that makes the arity change safe.

Status: accepted (2026-08-26). Resolves
[#588](https://github.com/timbermania/fft-monorepo/issues/588) on map
[#560](https://github.com/timbermania/fft-monorepo/issues/560) (extraction #3, isolation pass).
Builds ADR-0175 dec. 2. Discharges ADR-0169 dec. 4's GDScript half; its shader half is measured and filed as
[#626](https://github.com/timbermania/fft-monorepo/issues/626). Amends ADR-0068 R6's codemod subject. Resolves
[#623](https://github.com/timbermania/fft-monorepo/issues/623). Shrinks
[#583](https://github.com/timbermania/fft-monorepo/issues/583).

Code at `6d63f6fbe`.

## Context

`check_addon_portability.py` arm 2 asks one question: does a file inside an addon name a
symbol that only a `[autoload]` block declares? An `[autoload]` line can only be written by the
consuming game's `project.godot` — an install step, not an interface — so every such line is a
file that does not parse where the addon is installed and the host script is not.

At `6d63f6fbe` the walk held **78** of them across **7 files and 2 addons** — 9 guard rows,
because `PlayerCamera.gd` and `TileCursor.gd` each break on two different names — and after #589 and
#590 ([ADR-0186](0186-the-publish-already-existed-on-the-wrong-half.md)) they were the ONLY
thing between `Battlefield` and a clean arm 2 — its scored outbound debt was already zero
(`autoload_reach.py Battlefield` read *"dec. 2 counts 0"*), and the six remaining arm-1 lines
are the lattice, which is an interface design and not a wiring change.

## Measurement

**The 78, by addon and by verb.** Counted with the guard's own `strip_noncode`, so a docstring
naming a verb is not in the count.

| addon | file | lines |
|---|---|---:|
| `exmateria_battlefield` | `assembly/MapComposer.gd` | 12 |
| | `camera/PlayerCamera.gd` | 17 |
| | `cursor/TileCursor.gd` | 12 |
| | `overlay/TileOverlayConfig.gd` | 15 |
| | `terrain/SkirtConfig.gd` | 3 |
| | `terrain/SkirtGeometryGenerator.gd` | 2 |
| | **subtotal** | **62** |
| `exmateria_platform` | `display_port/PSXDisplay.gd` | 16 |
| | **total** | **78** |

| verb | lines | absent-port answer |
|---|---:|---|
| `bind` | 24 | return the literal |
| `get_value` | 18 | return the fallback |
| `on_update` | 13 | **no-op** |
| `set_value` | 11 | no-op |
| `bind_update` | 8 | apply the literal once |
| `DisplayPort.*` | 3 | the identity / no-op |
| `on_any_change` | 1 | no-op, and say so |

🔴 **Sixteen were free, and nobody had counted that.** `PSXDisplay.gd` lives in
`addons/exmateria_platform/`, and so does the façade. Those 16 lines were arm 2 breaks — the
port naming a HOST autoload — and re-pointing them makes the reference **intra-addon**, which
arm 2 does not see and arm 5 does not count either. The measurement is the arm-5 delta:
**69 → 131 lines, +62**, exactly the battlefield's subtotal and not the 78. Every statement of
this ticket's size, including its own re-measurement comment, treated the 78 as one population.

🔴 **`get_value` sites change arity, and the ticket's two claims cannot both hold.** #588 says
*"the call sites change identifier and nothing else"* and also that *"every one of the 13
`get_value` sites already has its default in scope … so the fallback is total."* A fallback that
is total is a fallback that gets **passed**. There are 18 such sites, not 13 (13 was an older
tree), and the second claim is the true one: each site's fallback is the same constant the
matching `bind` declared, in scope at the call.

| file | sites | the fallback that was already there |
|---|---:|---|
| `MapComposer.gd` | 5 | `_uv_snap_*_default`, `_atlas_dilate_passes_default` |
| `TileOverlayConfig.gd` | 5 | `_uv_*_default`, and `p[key]` — the `_types` default store |
| `PSXDisplay.gd` | 5 | `_par_default`, `_ui_par_default`, the three `_*_stretch_default` |
| `PlayerCamera.gd` | 1 | `FREE_CAMERA_DEFAULT` |
| `SkirtConfig.gd` | 1 | `PROPERTY_META[prop]["default"]` |
| `SkirtGeometryGenerator.gd` | 1 | `LAND_SKIRT_DEBUG_DEFAULT` |

🔴 **`on_update` is the one verb with no honest absent answer, and the reason is structural.**
`bind` and `bind_update` carry their literal at the call site; `get_value` now carries its
fallback. `on_update` carries neither — it reads the default the matching `bind` registered. So
with no registry there is nothing it could apply, and applying `null` is precisely the failure
the absent path exists to prevent. It is a **no-op**, and that is correct because every one of
its 13 sites writes a member that already declares the same default (`@export_range(0.05, 1.0, 0.01) var
deadzone_width: float = DEADZONE_WIDTH_DEFAULT`). Verified for all seven `PlayerCamera` members
and both `TileCursor` groups: the code default stands.

**The codemod tail is 32 lines, not 26.** `tools/materialize_tunables.py:61`'s `CALLS` table
is a hardcoded list of registration spellings, and `locate_call_for_slug` reports **nothing**
for a spelling it does not hold — indistinguishable from *"no literal at this line."* 24 `bind`
+ 8 `bind_update` = **32** registration lines moved onto the façade. #588's comment measured 26
for `Battlefield` and named `PSXDisplay`'s 6 separately; the number that matters to the codemod
is the sum.

**The eager-load bound does dissolve, and it is verified rather than assumed.** ADR-0159's
amendment called it *"a hard bound on the fix"*: the registry is the first autoload, so a
compile-time `class_name` edge FROM it would eager-load every owner during its own boot against
a Nil singleton. The façade's edge runs the other way — six owner files name `TunePort`, and
`TunePort` reaches the registry by node path at call time. `TunePort.gd` has no `_static_init`
and no compile-time edge to anything, so loading it costs a script load and touches no
singleton. `TuneOwnerSelfRegistrationTest` is the instrument: it DISCOVERS every owner by
walking `res://src` and `res://addons` for a `static func register_tunables()`, then asserts
each owner's own boot path left its slugs in the registry. Green.

> ⚠️ **Amended when #535 landed.** This paragraph originally named `TuneRegisterAllTest` and
> `Tune.register_all()`. [ADR-0173](0173-a-central-replay-existed-because-reset-destroyed-what-only-the-owners-could-rebuild.md)
> deleted both — the central replay existed only because `reset()` cleared something only the
> owners could rebuild, and the fix was `reset_overrides()`, not a list of owner paths. The
> replacement is **stronger for this decision, not weaker**: it names no owner, so it cannot go
> stale the next time one of these six files moves — which is exactly what happened to the
> fifteen paths `register_all()` held when extraction #3 moved five of them.

## Decision

**1. Two façades, because there are two autoloads. `TunePort` (153 lines,
`addons/exmateria_platform/tunables/`) and `DisplayPort` (89 lines,
`addons/exmateria_platform/display_port/`).**

#588's title says *"a `class_name` façade"* and its body lists both `Tune` (59 lines) and
`PSXDisplay` (2, now 3). One class cannot forward both: a façade is a signature, and these are
two signatures with nothing in common but the soft-bind mechanism. Splitting them also puts each
beside what it fronts — `DisplayPort.gd` next to `PSXDisplay.gd`, `tunables/` as a new
subdirectory under the layout rule the platform README already states, *"the subdirectory names
are the fact each file encodes."*

**2. The soft-bind rejects on `has_method`, not on `null`, and never caches a negative.**

Two absent cases, not one. `null` is the ordinary one. The other is the **editor**: a non-`@tool`
autoload is instantiated in the editor as a placeholder that answers to the name and carries
none of the script's methods, so a bare null-check sails past it and calls into nothing. Both
façades are `@tool` — `MapComposer` and `SkirtConfig` are `@tool` and name them — and
`has_method` is what separates the two cases. Every consumer's existing `Engine.is_editor_hint()`
guard is left in place and is now belt-and-braces rather than the only thing standing between a
`@tool` script and a crash.

A negative resolution is never cached. A `_static_init` that runs before the autoload is up
would otherwise poison every later call for the whole session, and the failure would be silent.
`_forget_port()` is the test seam for the same reason.

**3. `get_value(slug, fallback)` — the arity change is the decision, and it is not optional.**

The alternative is a façade that returns `null` when the registry is absent and lets 18 call
sites decide what to do about it, which is 18 copies of this decision in the consumer. Making
`fallback` a required parameter puts the question at the call, where the answer already lived:
every one of the 18 sites had its default in scope before this pass touched it (table above).

This is the ONE place the port's signature deviates from the singleton's, and it is a
registration-free verb, so it does not reach the codemod.

**4. `TunePort.bind` and `TunePort.bind_update` are taught to `materialize_tunables.py` in the
same commit, and the reason is that the codemod FAILS QUIET.**

ADR-0148's stale-subject pattern, in the one place it goes silent rather than red. A `CALLS`
table without the façade would have made 32 registration lines unmaterializable with no output
at all, and nothing in #588's acceptance would have caught it. This is ADR-0151's
companion-change rule — *the guard's subject moves with the code* — applied to a codemod instead
of a guard.

Three tests, seeded in both directions: the façade spelling resolves for `bind` and
`bind_update`, and the four near-identical table keys do not shadow each other under the
matcher's `\s*\(` suffix. With the two rows commented out, 3 of 38 fail; restored, 38 pass.

**5. `_load_all_gd()` walks `src/` plus `_walk_roots.addon_roots()`, in the same commit and NOT
as scope creep. This resolves [#623](https://github.com/timbermania/fft-monorepo/issues/623).**

Its docstring said *"Every `.gd` under `src/`"*, which stopped describing this tree at loop pass
6. The rewrite set was never at risk — `main()` folds in every use-site file the runtime
snapshot names — but the two maps this function builds are what REVALIDATE a const-name slug
argument, and a const declared in a file the walk cannot see is a slug that silently fails to
resolve. 19+ const slug homes are under `addons/` today, 8 of them in `PlayerCamera.gd` alone.
It is folded in here because #588 is what makes those files the codemod's main subject rather
than an exception to it, and because it is the same hardcoded-directory defect as the five
[ADR-0184](0184-the-address-lands-and-arm-1s-debt-is-named-rather-than-hidden.md) dec. 5 named —
the sixth, and the quietest, because a codemod is not a guard: a map that lost entries produces a
shorter report and nothing on the page says a name went missing.

**The addon list is read, not re-derived** — `_walk_roots.addon_roots()`, the same answer
`check_addon_portability.py`, `score_goals.py` and `residue.py` already read. A fresh `addons/*`
scan is not a smaller version of that; it is a DIFFERENT defect, because it drags in the vendored
`addons/exmateria_sound`, which is another package's source and not this project's to rewrite.

**A ratchet has two arms and both are seeded.** Reverting to the `src/`-only scope fails 2 of the
3 new tests; replacing `addon_roots()` with a wholesale `addons/*` scan fails the third. Neither
seed moves the other's arm.

The walk uses `_walk_roots.walk_files`, not `rglob`, because `addons/exmateria_sound` is a real
directory in the canonical worktree and a symlink in every linked one — the reading that differs
by checkout, and the smaller one is the quiet one.

**6. `TunePortTest`, and its subject is the state no scene in this repo boots in.**

The re-point is enforced statically — arm 2 loses 78 rows and arm 5 gains 62, so re-adding a
bare autoload name inside an addon moves both numbers. What no static guard can reach is what
the façade ANSWERS when the autoload is absent, which is the only state the whole re-point was
for.

The absent case is manufactured by **renaming the autoload node** and dropping the resolution
cache. That is a truthful simulation and not a trick: `_resolve()` is a `get_node_or_null`
against a name, and a consuming project without the `[autoload]` line differs from this one in
exactly that lookup failing. It also leaves the GDScript identifier `Tune` working inside the
test itself — autoload identifiers resolve to the object, not the node path — which is what
lets the absent arm assert *"and `bind` did NOT reach the registry"* against the real registry.

27 assertions. Three seeds run, each moving a different arm: `get_value` answering with the
fallback unconditionally (5 fail), the absent `bind_update` dropping its literal (1 fail),
`_forget_port` no longer dropping the cache (2 fail). Every fallback assertion uses a SENTINEL
(`-77.25`) that the registry cannot produce — asserting `get_value(slug, X) == X` while the
registry also holds `X` is an arm that cannot fail, and this map has shipped one of those.

**7. `DisplayPort`'s fallbacks are the identity values, and it shrinks
[#583](https://github.com/timbermania/fft-monorepo/issues/583).**

With no autoload there is no `[shader_globals]` boot value to source a default from — the addon
cannot read the consuming project's `project.godot`, which is the whole reason the class exists.
`1.0` is *no stretch*: the value at which the fold's billboard math is a no-op, and this repo's
own `project.godot` entry for all three `psx_*_stretch` names.

The side effect is that three call sites stop naming the autoload's SPELLING. #583 renames
`PSXDisplay` to `DisplayCalibration` (ADR-0171 dec. 4); after this pass that rename reaches one
node-path literal inside the port and nothing in any addon. ADR-0186 dec. 1 chose to land #590
on today's spelling rather than wait for #583; this decision is why that was cheap.

## Consequences

- **`check_addon_portability.py` arm 2 prints no rows at all** — the `standalone-parse DEBT`
  block is absent, not zero-length. `autoload_reach.py Battlefield` reads *"dec. 2 counts 0;
  goal #5 answers for all 0."*
- **Arm 5 is 69 → 131 lines**, +62, all `TunePort` and `DisplayPort` under
  `addons/exmateria_battlefield/`, beside the `PsxNum` row that was already the precedent. This
  is ADR-0175 dec. 2's trade paid in the open: a host-project-configuration dependency became an
  addon-presence dependency, and arm 5 exists so the survivor is counted somewhere.
- **`Battlefield` gains a hard dependency on `exmateria_platform` being installed**, which was
  already true for `PsxNum` and for both `.gdshaderinc`.
- 🔴 **The addon PARSES standalone now. It still REACHES, and it still does not COMPILE.** Goal
  #5 fails three separate ways for this directory and this pass closed exactly one of them — the
  one about a NAME the host's `project.godot` creates. ⚠️ *"the GDScript half is done"* is the
  wrong summary and an earlier draft of this document said it: **arm 1's six lattice lines are
  `.gd` too.** The honest split is by FAILURE MODE, not by language:

  | | goal #5 fails because… | subject | state |
  |---|---|---|---|
  | arm 2 | one file does not parse — a host `[autoload]` name | `.gd` | **0, closed here** |
  | arm 1 | the addon reaches into one of the eleven systems | `.gd` | **6 lines — the lattice** |
  | arm 4 | a shader does not compile — a host `[shader_globals]` name | `.gdshaderinc` | **4 declarations** |

  **The shader row is untouched and still unowned** — ADR-0169's
  Consequences called it *"pass 6's call"*, pass 6 did not make it, and neither did this pass. It
  is the only open QUESTION left in this extraction, and it is [#626](https://github.com/timbermania/fft-monorepo/issues/626) — which measures the
  requirement by **include closure** and finds SIX names over 11 addon shaders rather than four
  declaration lines, `psx_par` alone in 10 of them, and `visible_angles_cull_mode` with no CPU
  writer anywhere in the tree.
- ⚠️ **A soft-bind converts a loud failure into a silent one.** Today a `_static_init` that ran
  before the registry was up would have hit a Nil autoload and said so; now it registers nothing
  and returns the literal. `TuneOwnerSelfRegistrationTest` is the detector — its phase 2 clears
  the registry, calls one owner's entry point, and asserts every slug it binds was ALREADY in the
  boot snapshot, i.e. that the owner's own boot path put it there. Because that test discovers
  its owner set by walking `res://addons` as well as `res://src`, the six addon owners are
  covered without being named. (Before #535 this role was `TuneRegisterAllTest`'s, against a
  hardcoded list.)
- ⚠️ **`TunePort.get_value`'s fallback is a SECOND home for a default**, in the ADR-0068 M5
  sense. It is the same identifier the `bind` passes, never a rival literal, and the codemod does
  not read `get_value` — but a future edit that inlines a constant there would create the drift
  M5 exists to prevent.
- **Prose was left alone.** Docstrings still say *"routes writes through `Tune`"* and *"so
  `Tune.register_all()` can replay it"*, which remain true: the registry is still the registry
  and `register_all` is still on the singleton. The guard blanks comments, so none of it is in
  any count.

## Considered alternatives

- **One façade for both autoloads.** Rejected by dec. 1: a signature that forwards `bind` and
  `live_fx_stretch` is not a port, it is a namespace.
- **Per-call-site soft-bind — 61 inline `get_node_or_null` guards.** ADR-0175 dec. 2 named this
  as the correct answer *if arm 5 were refused* (*"61 ugly guards beat a green that stopped
  looking"*). Arm 5 exists and prints, so the condition does not hold.
- **`EditorPlugin.add_autoload_singleton()`.** Rejected by the repo-root ADR-0003 dec. 6, by
  `exmateria_render/plugin.gd:9-13` for this host specifically, and independently because it
  would not make arm 2 green — it puts the requirement back in the consumer's project file, one
  layer down.
- **`get_value(slug)` with a `null` return.** Rejected by dec. 3: it distributes one decision
  across 18 call sites and re-introduces the null the absent path exists to avoid.
- **Leave `PSXDisplay.gd`'s 16 lines for a later pass**, on the reading that they are
  `platform`'s own debt and not `Battlefield`'s. Rejected on measurement: they are the cheapest
  16 of the 78 (dec. 1's finding — same-addon after the re-point, counted by neither arm), and
  #588's own comment already says the façade *"should cover them in the same pass, since it lives
  in the same addon."*
- **Update the docstrings that name `Tune.bind` in prose.** Rejected as churn across seven files
  for zero measured change; see the last Consequence.
