# A port answers arm 1 and not arm 2, and the `Debug` residue was print statements

[#563](https://github.com/timbermania/fft-monorepo/issues/563) asked how a reached host
autoload resolves inside the addon, and offered three shapes: **port**, **sever**, or
**accepted debt with a recorded reason**. The first of those is not a shape. `port` is a
verdict about *which bucket a name belongs to* — it licenses a reach and settles a tier —
and the 104 breaks the ticket counts are not about buckets at all. They are about a
*name* that only a `project.godot` `[autoload]` block creates. Every one of the three
answers leaves that name exactly where it was.

The ticket's own sharpest sentence is where this comes apart. It asks *"Does the shipped-port
answer cover all 59 reached lines, or only the shader half?"* Measured: **neither — it covers
zero of them**, and the shader half is not among the 59 in the first place.

The second finding is larger and was not on the ballot. Of the 38 `Debug` lines, **31 are a
`print` behind an on-off switch**. `Battlefield` could not ship because of trace logging.
They are deleted here, not migrated, and that is a correction to
[ADR-0140](0140-debug-is-a-system-and-a-system-logs-itself.md) dec. 5 rather than an
application of it.

Status: accepted (2026-08-26). Resolves
[#563](https://github.com/timbermania/fft-monorepo/issues/563) on map
[#560](https://github.com/timbermania/fft-monorepo/issues/560) (extraction #3, loop pass 5,
**8 of 9**). Amends **ADR-0140 dec. 5** in place. Builds on
[ADR-0167](0167-the-mount-inverts-to-the-host-and-the-fix-was-booked-into-the-bucket-it-drains.md)'s
inversion, [ADR-0169](0169-platform-ships-to-its-own-address-and-shipping-a-file-is-not-shipping-a-shader.md)
dec. 5's arms 3–4 and
[ADR-0171](0171-the-display-port-is-platforms-and-render-is-the-fold-bracket.md) dec. 1's
re-tier. Cites [ADR-0173](https://github.com/timbermania/fft-monorepo/blob/fix/535-invert-register-all/godot-learning/docs/adr/0173-a-central-replay-existed-because-reset-destroyed-what-only-the-owners-could-rebuild.md)
by URL — it lives on `fix/535-invert-register-all`
([PR #578](https://github.com/timbermania/fft-monorepo/pull/578), open), which this branch
does not contain. Files #588, #589, #590, #591.

Code at `5a8f9cd94`, classifier at `5a8f9cd94`.

> ⚠️ **This was written as 0174 and renumbered before push — the collision trap fired again.**
> `0174` was free across every remote when the number was claimed and taken by
> `feature/world-map-input` an hour later (*a guessed constant expired to a static scan…*).
> ADR-0171 was claimed three times the same way. **Nothing in this repo allocates ADR numbers**,
> and checking once at the start of a session is not enough; the check has to run again
> immediately before push. `0176` is next free as of this commit.

> ⚠️ **The number 0003 is ambiguous in this repo, and every reference below is to the
> repo-root document.** There are two: `docs/adr/0003-an-installed-addon-owns-five-global-names.md`
> (the `exmateria-sound` global-footprint decision, the one cited here) and
> `godot-learning/docs/adr/0003-unit-encode-is-a-single-looped-schema.md` (unrelated).
>
> 🔴 **`tools/check_adr_quotes.py` cannot see repo-root ADRs at all.** Its target set is
> `ADR_DIR.glob("[0-9][0-9][0-9][0-9]-*.md")` over `godot-learning/docs/adr/` only, so it
> resolved a quotation from the root document against the godot-learning one and reported it
> missing. That is how the collision surfaced, and the guard's blind spot is the more useful
> half: **any godot-learning ADR quoting a repo-root ADR reports a permanent false red**, and
> the root tier holds the decisions about what the published packages ship. Filed as
> [#591](https://github.com/timbermania/fft-monorepo/issues/591). Root documents are linked
> by path here and named by title rather than number where a quotation sits beside them, so
> this ADR adds no new false reds.

## Context

Goal #5's literal test is *"a system could ship to another tactics RPG with its interface
intact."* `tools/check_addon_portability.py` mechanizes it along arms that ask different
questions of the same lines:

* **Arm 1 — REACH.** Nothing under an addon root names a symbol the classifier books to one
  of the eleven systems. Its own docstring states the exemption: *"a port is what a portable
  addon is ALLOWED to reach"* (ADR-0139 dec. 12). `Battlefield → Tune` scores **0** here, and
  correctly.
* **Arm 2 — STANDALONE PARSE.** Nothing under an addon root names a bare identifier that only
  an `[autoload]` block declares. `Battlefield → Tune` is **59 lines** here.

Both statements are true simultaneously, and #563's three-shape menu has no vocabulary for
that. ADR-0159 dec. 3 and ADR-0171 dec. 1 both answer the arm-1 question — `platform` ships,
`PSXDisplay` is `platform`'s — and neither was ever answering arm 2. ADR-0171 dec. 3 says so
outright: *"Under this decision that row stops being debt … It remains one of the 104
standalone-parse breaks; goal #5 answers those."*

**The ticket's baseline is stale, and this ADR restates it.** #563's table reads **104 lines /
11 files**, measured before ADR-0167 landed. At `5a8f9cd94` the same tool reads **102 / 11** —
the `DebugOverlay` row is gone, retired by #555. Every number below is re-measured at this
commit.

**Two amendments on #563 that moved the ground before it was answered.** ADR-0171 re-tiers
`PSXDisplay` to `platform`, dropping the scored outbound debt from four rows to three. And
arm 4 landed a second class of standalone break on the same file, with the open question this
ADR's decision 1 closes: *"whether arm 2's 16-line `PSXDisplay.gd → Tune` debt dissolves once
both files sit in `addons/exmateria_platform/` … It is evidence for 'no' on the autoload side
too, but it is **not proof, and it has not been verified**."*

## Measurement

### The co-location question, verified with the real instrument

Arm 2's own docstring calls itself a floor: *"ARM 2 IS A FLOOR, NOT THE INSTRUMENT. The
instrument is `godot --path <pkg> --check-only -s <file>`."* Three arms, scratch trees,
Godot 4.8 fork:

| arm | tree | **Parse Errors** |
|---|---|---|
| **A** | `Tune.gd` + `PSXDisplay.gd` co-located in one `addons/exmateria_platform/`, its own `project.godot`, **no** `[autoload]` block | **16** — one per reach line (74, 80, 83, 86, 95, 98, 121, 125, 166, 170, 200, 204, 221, 225, 242, 246) |
| **B** | *the same tree*, `Tune` added to `[autoload]` | **0** |
| **C** | the real `godot-learning` host, the same file | **0** |

**Co-location dissolves nothing: 16 of 16 survive it.** Arm 4's answer for `psx_gamma` and
arm 2's answer for `Tune` are now both measured and they agree — moving a file moves an
address, never a name.

Two grader notes, because both were nearly errors. `rc=0` on **all three arms**: the exit code
is not the verdict, the `Parse Error` count is. And arms B and C each leave one residual
`Compile Error: Identifier not found: Tune` — **identical in the working host**, so it is the
`--check-only -s` noise floor (autoloads are not instantiated for a tool script), not a signal.

### The 102, by shape rather than by autoload

`#563` asks for a disposition *per autoload*. The shapes cut across the autoloads, so the
count is given both ways:

| autoload | bucket | lines | shape |
|---|---|---|---|
| `Tune` | `platform` | 59 | port — `bind` 24, `on_update` 13, `get_value` 13, `set_value` 6, `bind_update` 2, `value_changed.connect` 1 |
| `DebugConfig` | `Debug` | 32 | **31 gate reads** (`map_debug_enabled` 25, `iteration_debug_enabled` 6) + **1 write** |
| `GameLogger` | `Debug` | 6 | emit — all six `GameLogger.debug(GameLogger.Category.CAMERA, …)`, all in `PlayerCamera.gd` |
| `PSXDisplay` | `platform` (ADR-0171) | 2 | port |
| `MapTintOverlay` | `Effects` | 1 | push |
| `ScreenEffectOverlay` | `Effects` | 1 | push |
| `SfxRouter` | `Audio` | 1 | push |

**61 port · 38 `Debug` · 3 push.** Every one of the 13 `Tune.get_value` sites already has its
default in scope — it is the same constant the file passed to `bind`.

### The `Debug` block is 36 print lines under 31 gates

| kind | gates | example |
|---|---|---|
| development trace / ASCII banner | **25** | `print("\n=== REBUILDING DYNAMIC GEOMETRY MESH ===\n")`, `print("DoodadLibrary: Loading '%s' from cache")` |
| genuine warning — malformed data, fallback taken | **5** | `print("  Warning: manifest missing 'lighting' section, using defaults")` |
| diagnostic worth keeping | **1** | `print("[MapComposer] state weather_raw=%d night=%d arr=%d → palette=%s texture=%s")` |

Three facts make deletion safe rather than merely attractive:

1. **Nothing asserts them.** All ten distinct message prefixes, grepped across `tests/` and
   `tools/`: zero hits.
2. **`DebugConfig` is untouched by the fix.** Both flags are read widely by *other* systems
   (`iteration_debug_enabled` ×10 in `src/animation/`, ×2 in `src/debug/`;
   `map_debug_enabled` by `GameLogger.gd:53`). `Battlefield` stops reading them; they stay
   for their other owners.
3. **The replacement is already the house idiom and is not residue.** `push_warning` /
   `push_error` are engine built-ins — no autoload, no flag, no host — and this codebase uses
   them **511 times in `src/`**, with the same `[ClassName] message` convention that the
   gated `MapLightingConfig` line already wears.

Fact 2 is what kills ADR-0140 dec. 5's split for this population: dec. 5 requires
`map_debug_enabled` to split into per-system flags *because it is shared* (25 `Battlefield` /
9 `Battle` / 1 `Debug`). Delete `Battlefield`'s 25 and there is nothing left to split.

### `DebugConfig.psx_camera_angle_12bit` is not a debug reach

```
src/scenes/PlayerCamera.gd:557   RenderingServer.global_shader_parameter_set("psx_camera_angle", psx)
src/scenes/PlayerCamera.gd:561   DebugConfig.psx_camera_angle_12bit = psx        <- the reach
   readers:  src/animation/CameraRelativeRenderer.gd:35,43   [Sprite Rig]
             src/units/Unit.gd:937                            [Battle]
```

The autoload is being used as a global variable for camera state; `DebugConfig.gd:160`
documents it as such, and the comment beside the write gives the reason —
`global_shader_parameter_get` is editor-only and warns every frame at runtime. It is the
**sixth** global shader parameter this codebase pushes, pushed from outside the port that owns
the other five.

### A cross-addon `class_name` is arm 2's break in another spelling

Scratch project, `addons/plat/TunePort.gd` (`class_name TunePort`) named by
`addons/bf/Consumer.gd`, class cache warmed with `--import` on each arm:

| arm | tree | result |
|---|---|---|
| **D** | both addons present | clean |
| **E** | `addons/plat/` removed | `Parse Error: Identifier "TunePort" not declared` |

Arm 2 is structurally blind to arm E: `host_auto = autoload_names(PROJECT_DIR /
"project.godot")` — a `class_name` is never in that dict. Arm 2's docstring already named the
gap: *"a `class_name` a consumer happens to define would be another."* Measured subject on
today's tree: **157** `class_name` declared under addon roots, **4 lines / 1 edge** crossing
between roots (`addons/exmateria_render/fold_bracket/FoldSurface.gd:251,258,280,289` naming
`Fold`, declared in `addons/exmateria_schema`).

## Decision

**1. `port` is a tier verdict, not a resolution. All 102 breaks are open, and the axis is
re-bind / sever inward / invert outward / accepted debt.**

Arm 1 and arm 2 ask different questions and only arm 1 has an exemption for ports. Three legs,
each measured above:

* **The shader half is not in the 59.** `autoload_reach.py` reads `.gd` only; all 59 `Tune`
  lines are `src/map/*.gd` and `src/scenes/*.gd`. ADR-0159 dec. 3's `#include` legs are
  `.gdshader` and belong to arm 3. "Only the shader half" is not a smaller answer to this
  question — it answers a different one.
* **Shipping cannot touch arm 2, by construction.** Arms A/B/C. `exmateria_render/plugin.gd:6-8`
  already states the rule in prose: *"an autoload is a `project.godot` entry the HOST writes."*
* **The repo has answered arm 2 once, for real, and the answer was none of the three shapes.**
  `exmateria_sound` is the only package with its own `project.godot`, so the only one where
  arm 2 is *enforced red* rather than reported as debt. Both defects arm 2's docstring cites
  as its reason for existing are fixed on that tree today, by **node-path soft-bind** —
  `effect_sfx_engine.gd:300`, `spu_audio_debug_panel.gd:72`. Not ported, not severed, not
  accepted. **Re-bound.**

This does **not** reopen ADR-0159 dec. 3 or ADR-0171 dec. 1. Both decided the tier and both
are right. What this decision retires is the reading that *deciding the tier resolved the
break* — and with it #563's premise that the `Tune` and `PSXDisplay` rows were already
answered. They are the largest open block, not the settled one.

> The handoff into this ticket nominated ADR-0159 dec. 3's spent second argument — the
> `register_all()` `load()` mechanism, deleted by #535 — as the live
> `enforce-adr-conformance` candidate. It is moot under this decision. Dec. 3's second
> argument concerned whether *injection* hides rather than severs; since neither injection nor
> shipping resolves arm 2, the argument's health does not change dec. 3's answer or this one.

**2. The 61 port lines re-bind to a `class_name` façade in `addons/exmateria_platform/`,
soft-bound inside, and arm 5 pays for the trade.**

The façade wraps the `exmateria_sound` recipe once instead of 61 times; the call sites change
identifier and nothing else. Four reasons, in order of weight:

* **It converts a host-project-configuration dependency into an addon-presence dependency.**
  An `[autoload]` line can only be written by the consuming game's `project.godot` — an
  install step, not an interface, so goal #5 fails on it. An addon-presence dependency is
  vendorable, exactly as the repo-root
  [*An installed addon owns five global names*](../../../docs/adr/0003-an-installed-addon-owns-five-global-names.md)
  does it in its decision 4 — *"`D2`'s vendoring guarantees the SPU addon is present whenever
  Sound is, so the re-export never dangles."*
* **It is the shape ADR-0139 dec. 12 already named**: tunable declarations are *"a schema
  whose realisation is a **port's signature**."* A signature is a `class_name` with methods; a
  bare autoload identifier is not one.
* **Precedented**: ADR-0159 dec. 3 blesses `addons/exmateria_schema/` as *"an addon other
  addons name, on 23 lines from this system alone, that nobody calls debt."*
* **It dissolves a constraint ADR-0159's amendment called *"a hard bound on the fix"*** —
  that `Tune` is the first autoload, so a compile-time `class_name` edge **from** `Tune.gd`
  eager-loads an owner against a Nil `Tune`. The façade's edge runs the other way and reaches
  `Tune` by node path at call time; nothing eager-loads.

**The cost is named rather than pocketed.** Arm E proves the residual dependency is a real
parse failure and arm 2 cannot see it. So this decision is not separable from **arm 5**
(decision 6): without it, the ticket trades a measured break for an unmeasured one, which is
the ADR-0148 pattern this map has paid for repeatedly. *If arm 5 were refused, per-call-site
soft-bind would be the correct answer instead* — 61 ugly guards beat a green that stopped
looking.

**`EditorPlugin.add_autoload_singleton()` is rejected.** [the repo-root **ADR-0003**](../../../docs/adr/0003-an-installed-addon-owns-five-global-names.md) dec. 6 decided it and
*"Verified both methods exist on `EditorPlugin` in 4.8."* It is **unbuilt on all three branches
that could carry it** — `exmateria_sound/plugin.gd` and `exmateria_spu/plugin.gd` both have
`pass` bodies and still carry the *"autoload-free by design"* / *"no autoloads"* docstrings
dec. 6 says it retires, on `import-godot-game`, on `refactor/render-system` and on
`build/exmateria-b-tier`; `exmateria-sound/project.godot` has no `[autoload]` block.
`exmateria_render/plugin.gd:9-13` argues against it for this host specifically: *"only for a
plugin the host has ENABLED, and this project enables neither of its addons (`project.godot`
has no `[editor_plugins]` section at all). Wiring the registration to a switch nobody has
thrown would make the port's availability depend on editor state."* Confirmed still true.
And it would not make arm 2 green regardless — it puts the requirement back in the consumer's
project file, one layer down.

**3. The `Debug` block is DELETED, not migrated — delete-first precedes ADR-0140 dec. 5's
`static var`, and ADR-0140 dec. 5 is amended to say so. BUILT here.**

31 gates: **25 deleted outright, 5 become un-gated `push_warning()`, 1 becomes an un-gated
`print`** (consistent with the ungated `print("[Gradient] Applying …")` eleven lines above it
in the same file). The 6 `GameLogger` lines are deleted with them — ADR-0140 dec. 5 already
sentences that autoload (*"`GameLogger` is deleted, not promoted"*) and all six are
per-raycast camera trace. Their `log_result: bool = false` parameter existed only to gate
them and dies with them, across `_get_terrain_pivot()` and its one caller.

**This is the ticket's dec. 1 warning, answered.** #500 (`c981f928c`) severed 10 gates and
diagnosed itself at the time: *"It does NOT meaningfully reduce the standalone-parse count:
120 → 112 … **Swapping one host autoload name for another is a re-label.**"* Two things make
this different. Deletion has no residue at all — nothing lands on `Tune`, no flag splits,
`Tune` stays at 59. And where residue *does* remain, decision 2 gives it a destination that is
not a host global, so dec. 5's answer stops being a re-label wherever it is still the right
answer.

**ADR-0140 dec. 5 is corrected, not applied.** It says *"Each becomes a `static var` in the
system that prints through it"* — which presumes the print is worth keeping. Its Considered
Alternatives lists five rejected options and **"delete the traces" is not among them.** For 25
ASCII banners the presumption does not hold. The amended rule: *ask first whether the output
is worth keeping; the `static var` home is right for a gate that survives that question, and
25 of 31 here did not.*

**4. `DebugConfig.psx_camera_angle_12bit` is not `Debug`'s; it is the port's sixth pushed
global.** `DisplayCalibration.set_camera_angle(psx)` replaces **both** `PlayerCamera.gd:557`
and `:561`, and the two readers move to `live_camera_angle` beside the existing
`live_fx_stretch` / `live_cursor_stretch`. ADR-0171 dec. 1 defines the shape as the port's —
*"pushes the result to global shader parameters it does not declare"* — and ADR-0171 dec. 5
names the hole this closes: *"an arm that reads only `global uniform` declarations will report
those two and be silent about the push side."* Three effects: `Battlefield`'s line goes behind
decision 2's port, two *other* systems (`Sprite Rig`, `Battle`) lose a `Debug` reach #563 was
not counting, and no sixth pusher is left hiding outside the port. **Filed, not built** — the
port relocates at pass 6 and the rename is #583.

**5. The 3 push lines invert, as ONE assembler-side wiring block.** `MapTintOverlay
.register_material`, `ScreenEffectOverlay.set_default_gradient` and `SfxRouter.play_cue` are
the same shape — the addon hands a host singleton a value and gets nothing back — and
inverting them takes dec. 2's **scored outbound debt to zero**, since ADR-0171 already removed
the fourth row. Two supporting measurements: `register_material` and `set_default_gradient`
each have **exactly one caller in the whole tree** (the `Battlefield` line), so both host
methods exist solely to serve this system; and `TileCursor.gd:519` already emits
`cursor_moved` on the line above its `SfxRouter` reach, so that publish exists and the reach
is redundant with it.

**One assembler block rather than ADR-0167's consumer-side class, and the deviation is
deliberate.** ADR-0167 needed a `Debug`-side class because mounting a panel is real behaviour
with ordering constraints. These three are one-line hand-offs of a value the composer has
already computed, and wiring a system's outputs to other systems is ADR-0134's definition of
what the assembler *is* — *"a composition that wires once and leaves."* Two new classes for
three assignment statements is the shape this map keeps warning about.

**Filed, not built**, for ADR-0167's own reason, quoted from ADR-0159 dec. 5 amendment (b):
*"a behavioural change riding inside a booking correction makes the booking's own numbers
unattributable."* Verifying three functional hand-offs needs a headful boot and a look at the
map, not a guard.

**6. Arm 5, and the guard is registered in the suite — which it has never been.**

Arm 5 reports a `class_name` declared under one addon root and named under another. It is
**arm 1's rule one level down**: symbol → sibling addon instead of symbol → system. The free
set is derived, not listed — `system_of[home] is None`, which is arm 1's own test for the
kernel and the platform port (ADR-0139 dec. 9, dec. 12), so `addons/exmateria_platform/`
qualifies the day it exists without this file learning its name. Everything else takes arm 2's
strictness rule verbatim: RED for a package with its own `project.godot`, DEBT for one
without. **The free rows print**, because decision 2's whole trade is that arm 2 goes quiet
and nothing else in the file has a word for what replaced it.

🔴 **Arms 1–5 lived in a guard `run_all_tests.sh` has never invoked.** [the repo-root **ADR-0003**](../../../docs/adr/0003-an-installed-addon-owns-five-global-names.md)
dec. 7 measured that exact hole and named that exact file — *"the 8 that never run include
`check_addon_portability.py`, the existing addon guard"* — and it stayed true through
ADR-0169 dec. 5 and ADR-0171 dec. 5 building two more arms into it. Registered here, guard
and seed tests both. This is #555's and #565's shape a third time: **a guard the suite does
not list is a guard nobody runs.**

> ⚠️ **Amended 2026-08-26, hours after merge — arm 5's free set had ONE ground and needed
> TWO.** As written, the arm frees a target only when `system_of[home] is None` (the kernel
> and the platform port). That called **51 lines red** the moment `exmateria_spu` entered the
> subject list: `exmateria_sound` names `Spu`, declared in `exmateria_spu`, and **both resolve
> to `exmateria-sound/project.godot`**. They ship as ONE package, so co-presence is guaranteed
> by construction — which is the vendoring decision 2 above **cites in its own argument**
> (*"D2's vendoring guarantees the SPU addon is present whenever Sound is"*). The arm flagged
> the very relationship the decision leans on.
>
> The free set is now: the kernel/port **or** `own is not None and package_project(home) ==
> own`. The `own is not None` guard is load-bearing — two addons owned by the HOST both
> resolve to `None`, and `None == None` would excuse exactly the system reach this arm exists
> to catch.
>
> **It surfaced only because a merge widened the subject.** On this branch the walk held three
> addon roots; `build/exmateria-b-tier` declares `exmateria_spu` in `_walk_roots.EXTRACTED`,
> making four. A guard is only as tested as its subject list, which is the same lesson as
> *"WHY THIS GUARD WAS GREEN WHILE BOTH WERE TRUE"* in its own docstring — one level in.
> Two seed tests added; the second's first draft scanned `addons/*` and failed, because
> `addons/exmateria_sound` is a per-worktree SYMLINK into the package and resolves there
> correctly.

## Consequences

* **`autoload_reach.py Battlefield` goes 102 → 65 lines, 11 → 7 files, in this commit.** The
  `GameLogger` and `DebugOverlay` rows are **ABSENT, not smaller**; `DebugConfig` falls
  **32 → 1**. `Tune` is unchanged at **59** — the point of decision 3 is that nothing moved.

  ```
  Tune                [platform]  59   decision 2, pass 6
  PSXDisplay          [platform]   2   decision 2, pass 6   (row is ADR-0171's; tool reads the old tier)
  MapTintOverlay      [Effects ]   1   decision 5, #589
  ScreenEffectOverlay [Effects ]   1   decision 5, #589
  SfxRouter           [Audio   ]   1   decision 5, #589
  DebugConfig         [Debug   ]   1   decision 4, #590
  ```

* **37 lines retired with zero residue**, which no block on this map has managed before —
  every previous attempt moved one. The remaining 65 each carry a named disposition and a
  ticket.
* **Scored outbound debt reaches zero** once #589 lands: ADR-0171 took it 4 → 3 and decision 5
  is the other three.
* **`check_addon_portability.py` becomes an enforcing member of the suite**, five arms, and
  `tools/test_check_addon_portability.py` grows from 17 to **23** tests. Arm 5's seeds are
  proved live by mutation, not by passing: breaking `sibling_class_reaches` turns **3** red,
  emptying the free set turns **1** red, and the restored control is green.
* **Four tickets filed**: #588 (port façade + 61 re-points, pass 6), #589 (the three
  inversions), #590 (camera-angle re-home, behind #583), #591 (the quote guard's blind tier).
* **What was NOT proven.** Arm 5's `class_name` scan is a floor of the same kind as arm 2 —
  a regex over stripped source, not the compiler. The instrument remains `godot --check-only`,
  and arms D/E ran it on a two-file scratch project rather than on the real addon, which does
  not exist yet. Nothing here measures what `addons/exmateria_battlefield/` will actually do,
  because pass 6 has not created it.
* **The ticket's 104 is retired in favour of 102 at `5a8f9cd94`.** Anyone reading #563 forward
  should re-run the tool rather than quote the table; it was measured before ADR-0167 landed
  and this ADR was written on a different branch again.

## Considered alternatives

* **Hold #563's framing — `Tune` and `PSXDisplay` are ports, therefore resolved, and the
  ticket owes ~43 lines.** Rejected by arms A/B/C. There is no tree in which the shipped-port
  answer makes a `Tune.` line parse alone.
* **Per-call-site soft-bind, all 61.** The built precedent and genuinely the runner-up: no new
  global name, no dependency at all, and arm 2 keeps measuring the result. Rejected on
  duplication — 13 identical fallbacks and nothing stopping the seventh file getting it wrong
  — but it is the correct answer if decision 6 is ever dropped, and decision 2 says so.
* **`add_autoload_singleton` from `plugin.gd`.** Rejected in decision 2: decided-but-unbuilt
  on three branches, argued against for this host by `exmateria_render/plugin.gd`, and it
  relocates the requirement rather than removing it.
* **Apply ADR-0140 dec. 5 as written — split both shared flags, give each a `static var`
  home.** Rejected by measurement, and this was the recommendation until the prints were
  actually read: 25 of 31 gates guard ASCII banners and per-call traces that nothing asserts.
  Splitting a shared flag so that a `print("\n=== DYNAMIC MESH REBUILD COMPLETE ===\n")` can
  keep its switch is work with a negative return.
* **Accepted debt with a recorded reason for the 3 push lines.** Rejected: free now, but
  "accepted debt" on a *standalone-parse* break is not acceptance — the addon still does not
  parse. It defers, and it defers three lines after ADR-0171 spent a whole decision getting
  the count from four to three.
* **Build the inversions and the port façade here.** Rejected on ADR-0167's precedent for the
  inversions and on the pass-6 boundary for the façade: `addons/exmateria_platform/` does not
  exist until ADR-0169 dec. 2's step runs, and #563 is a decision ticket.
