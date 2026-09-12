# Installable is the fork plus the kernel and the port, and a `res://assets/` reach splits three ways

[ADR-0164](0164-the-lattice-ships-as-one-port-and-one-publish-and-tile-never-crosses.md)
dec. 4's three criteria all measure one direction: **host → addon**, does another system
reach in by a name outside the published set. Criterion 2 closed at pass 6, criterion 3 at
pass 7, and criterion 1 is open at 21 sites with a register on it
([ADR-0196](0196-the-marking-belongs-to-the-schema-and-a-respelling-is-never-the-reason.md)
dec. 8).

None of them answers the opposite question. *Drop `addons/exmateria_battlefield/` into an
empty Godot project and it works* is **addon → host**, and ADR-0196's own Consequences say
so at `0196:249` — the install term is *"raised and unowned. No ADR rules on it."* Two
passes have now printed that sentence and moved on.

This ADR owns it.

Status: accepted (2026-08-28), **register built and Class A closed** (2026-08-28, three commits). Loop **pass 9** of extraction #3, on map
[#560](https://github.com/timbermania/fft-monorepo/issues/560). Rules on a term
[ADR-0196](0196-the-marking-belongs-to-the-schema-and-a-respelling-is-never-the-reason.md)
Consequences raised and left unowned; stands on
[ADR-0139](0139-the-shared-kernel-is-enumerated-by-the-schema-list.md) dec. 9 and dec. 12
for what a portable addon may name, and on
[ADR-0192](0192-the-register-goes-first-because-the-port-erases-its-own-baseline.md)
dec. 1 for building the register first. Does **not** touch ADR-0164 dec. 4 criterion 1.

## Context

### The two directions are different axes, and conflating them chases the wrong number

| direction | question | instrument | state |
|---|---|---|---|
| **host → addon** | does the host reach in by names outside the published set? | ADR-0164 dec. 4 criteria 1/2/3 | crit. 2 clear, crit. 3 clear, **crit. 1 at 21 sites** |
| **addon → host** | does the addon depend on anything the host provides? | `check_addon_portability.py` (goal #5) | **guard says OK — and it is green through every item below** |

Criterion 1's remaining 21 sites (`TileCursor` 13, `CursorController` 8) do **not** block
installability: they are the host naming the addon, deliberately open under ADR-0196 dec. 8.
This ADR leaves them alone.

### The instrument for this direction is blind, and that is the whole reason for dec. 10

`tools/check_addon_portability.py` reports **OK** across every blocker enumerated below except
the shader globals and the cross-addon `class_name`s, which it prints and does not enforce.
Its arms cover systems, autoloads, shader `#include` resolution, shader globals and sibling
`class_name`s. **No arm reads a `res://` path out of a `.gd` body or a `.tscn`
`ext_resource`.** Eleven code sites are invisible to it.

### What was measured, and where the received account was wrong

Every count below is from the tree at `ebff57409`. Three of them contradict the handoff this
pass started from, and the corrections are recorded because in this family a number carried
forward unmeasured has been wrong five times running.

- ✅ **11 asset sites over 8 files** — reproduces exactly (10 in `.gd`, one `.tscn`
  `ext_resource`), plus 4 more mentions in `DoodadLibrary.gd` docstrings that are prose, not
  edges.
- 🔴 **8 input actions, not 2** — corrected by the register on its first run, after this
  ADR predicted 2. `rotate_camera_ccw` / `rotate_camera_cw` are the only two an inline
  literal grep can find. The other six travel as `StringName` constants —
  `CURSOR_ACTIONS` and `PAN_ACTIONS` (each `&"camera_up"`, `&"camera_down"`,
  `&"camera_left"`, `&"camera_right"`), `CURSOR_CONFIRM_ACTION` (`cursor_confirm`) and
  `CURSOR_INSPECT_ACTION` (`unit_inspect`) — and reach `is_action_pressed` through a loop
  variable, so the only place every name is visible is the `&"…"` literal itself. All
  eight are host `project.godot` `[input]` entries and none is a `ui_*` built-in.
- ✅ **6 files** carry a fork-only compositor token.
- 🔴 **Shader globals: 6, not 12.** The portability guard's "12 line(s)" is the count over
  the *whole walk*. Only **4** are declared in `exmateria_battlefield`
  (`psx_fx_stretch`, `psx_cursor_stretch`, `psx_camera_angle`, `visible_angles_cull_mode`);
  two more (`psx_par`, `psx_dither_enabled`) reach the battlefield compile surface through
  `#include`s of `exmateria_platform`. The remaining six lines are `PSXDisplay.gd`
  **pushes** — GDScript writing a global — which are not shader declarations at all and
  cannot fail a compile.
- 🔴 **Cross-addon `class_name`: 23 rows, but 9 distinct symbols.** 23 is the printed
  `(file, symbol)` row count for battlefield; the guard's headline "119 line(s)" is the walk.
  The number that decides what must be *present* is **9**: `CellMarking`, `ColorRecipe`,
  `ColorStack`, `DepthMode`, `Fold`, `TerrainCell` (kernel) and `DisplayPort`, `PsxNum`,
  `TunePort` (port).
- 🔴 **"ROM-derived and gitignored" is false for most of the set.** Measured target by
  target: **only `assets/maps/` is gitignored**, and `RANGETILE.tga`,
  `RANGETILE.palette.tga`, `RANGETILE.json` live behind a symlink into the asset hub and are
  ignored there. The other five targets — `tile_cursor_opaque.tres`, `tile_overlay.tres`,
  `tile_knife.json`, `assets/doodads/`, `CombatUI.tscn` — are **tracked and ship with a
  clone**. This is the correction that changes the design: the reaches are not one contract,
  they are three classes with three different answers (dec. 5).

  > The blanket reading would have produced one answer — *"declare the asset contract"* —
  > for three sites whose targets the addon could simply own, and the register would then
  > have scored a permanent debt that was never real.

### One blocker nobody had listed

`Tune.` appears **12 times** in the addon. All twelve are in comments and docstrings; the
addon reaches the tunable store only through `TunePort`, which is ADR-0139 dec. 12's design
working as ruled. The portability guard's autoload arm is right to say OK. Recorded because
a grep for it looks alarming and will be re-run.

## Decision

**1. `isolated` and `installable` are different terms, and this ADR owns only the second.**
ADR-0164 dec. 4's criteria measure host → addon and are not evidence about installability in
either direction. An addon can satisfy all three criteria and still fail to load in a bare
project — which is exactly today's state. Neither term subsumes the other and neither may be
reported as the other.

**2. The install target is a bare Godot 4.8-compositor-fork project containing
`exmateria_schema`, `exmateria_platform` and `exmateria_battlefield`, and nothing else.**
Not bare-alone. The grounds are measured and not negotiable at this pass's scale: 9 distinct
sibling `class_name`s over 23 rows, **16 shader `#include` lines** into the two siblings
covering every shader the addon has, and one `preload` by path
(`debug/MapGridOverlay.gd:19` → `exmateria_schema/compositing_key/DepthMode.gd`). Naming the
kernel and the port is what ADR-0139 dec. 9 and dec. 12 **permit**; severing it would not be
a portability fix, it would be undoing ADR-0139. "Empty project" therefore means *empty +
kernel + port*.

**3. The fork is part of the target, not a defect on the register.** `compositor_fold`,
`compositor_layer` and `render_layer` appear in 6 addon files. They are fork-only: under
stock 4.7 the compositor self-disables and every folded prim silently vanishes, and
`Fold.add` off-fork *throws* (ADR-0186 Amdt 4 §3). So *works in an empty project* can only
ever mean *on the 4.8 compositor fork*. This is ruled rather than left implicit because it is
the one blocker that produces **no error at all** when violated, and a silent failure that
nobody has written down is one somebody re-derives. The register **reports** the 6 files with
no target, so the requirement stays visible without being scored as debt.

**4. `plugin.cfg` cannot express a dependency, so the README and the register carry it.**
Godot has no `requires` field. Dec. 2's target is therefore a claim that lives in exactly two
places — `addons/exmateria_battlefield/README.md` and the register's own header — and both
must name the kernel, the port and the fork. A dependency stated in neither is a dependency
the next installer discovers by crash.

**5. A `res://assets/…` reach is a defect, and it splits three ways by what the target
actually is.** The single blanket answer is refused; the measurement in Context is why.

  - **Class A — addon-owned, tracked, shippable. The fix is a MOVE, and there is no
    contract.** 3 sites: `cursor/TileCursor.gd:150` (`tile_cursor_opaque.tres`, a
    *`preload`*, so this one is a **parse-time** failure), `lattice/Tile.gd:169`
    (`tile_overlay.tres`), `cursor/TileCursorBob.gd:28` (`tile_knife.json`). They move into
    the addon root and the reach disappears.

    ⚠️ **The test is TRACKED-NESS, not authorship**, and the wording this decision first
    carried ("hand-authored") was wrong about one of its own three. `tile_knife.json` is
    **ROM-derived** — `parse_cursor_bob.py` extracts it from `BATTLE.BIN` at
    `FUN_8007e304` — and it is still Class A, because it is 426 bytes of step-table integers
    that the repo has already **committed**. Class B's members are un-shippable because they
    are gitignored, not because a ROM produced them. Whether the addon may ship the bytes is
    the question; who typed them is not.

  - **Class B — gitignored and un-shippable. The HARDCODING is the defect; the dependency
    is a contract.** 7 sites: `assembly/MapComposer.gd:732` and `doodad/DoodadLibrary.gd:21`
    (`assets/maps/`), `doodad/DoodadLibrary.gd:24` (`assets/doodads/`), `lattice/Tile.gd:25`
    and `:26`, `overlay/TileOverlayCompositor.gd:24`, `overlay/TileOverlayConfig.gd:36`
    (the `RANGETILE.*` trio). The addon can never bundle ROM-derived data, so "move it in"
    is not available and never was. What is available is that the addon stop **naming
    `res://assets/` literally**: a settable search root with a default, so a host points the
    addon at its data and a bare project gets a legible failure instead of a silent empty
    load. The register scores the literal, not the dependency.

  - **Class C — a layering inversion. Not a path problem.** 1 site, dec. 6.

**6. The `CombatUI.tscn` edge is the camera scene's, and the fix is a mount point.**
`camera/PlayerCamera.tscn:5` declares the host's combat UI as an `ext_resource` and `:38`
instances it as `[node name="CombatUI" parent="FocusPoint/Camera"]`. The addon's camera scene
**owns the host's entire combat UI**. Re-pathing it is not a fix — the addon would still own
the UI. The addon exposes the node the UI hangs from; the host instances its own UI into it.
This is the ugliest single edge in the set and the only one where the register going green by
a path edit would be a *worse* tree.

> **Amended 2026-08-28 by [ADR-0204](0204-the-mount-point-is-an-inherited-scene-because-the-addon-supplies-the-ui-to-a-hundred-and-seven.md).** The shape holds; the SCALE in this decision is
> wrong. *"The addon exposes the node the UI hangs from"* was written as if the edge were two
> lines in one file. **107 scenes instance `PlayerCamera.tscn` and 104 of them inherit
> `CombatUI` silently** — including 76 test scenes whose `.tscn` never names it and whose
> `combat_ui` binding comes from `GPUCombatTestBase.gd:37`. Deleting the addon's two lines
> empties `combat_ui` in all 76 with no parse error. ADR-0204 dec. 1 makes the mount an
> **inherited scene** (`assets/scenes/CombatCamera.tscn`) rather than a named node, so every
> node path stays byte-identical and the consumer edit is one `ext_resource` path × 107; dec. 2
> declines the named-mount spelling this decision's wording implies.

**7. A soft, null-guarded reach to a host autoload is conformant. A hard one is not.**
`exmateria_platform/tunables/TunePort.gd:78` does `root.get_node_or_null(^"Tune")` and serves
its defaults when the answer is null — the port's own docstring states this is the design,
because *"an `[autoload]` line can only be"* the host's. The consequence is stated rather
than discovered: **in a bare project every tunable override is inert and the compiled-in
defaults apply.** That is a working install, not a broken one. Do not "fix" it, and do not
let the register score it.

**8. Shader globals are a bare-project COMPILE failure, and an enable-time
`ProjectSettings` WRITE from `plugin.gd` is permitted.** Six names reach the battlefield
compile surface (Context; **not** the guard's headline 12). A missing `global uniform` fails
the whole shader, which is strictly worse than one file's parse error. The rule this ADR adds
is about direction: a **runtime read** of `ProjectSettings` means the addon depends on the
host having configured it, and stays forbidden — the addon's count is 0 today and must stay
0. An **enable-time write** means the addon *provides* its own configuration, which is the
opposite coupling and is how Godot intends an `EditorPlugin` to install itself. Whether the
implementing pass writes the settings, or removes the globals in favour of per-material
uniforms the port pushes, is that pass's call. This ADR rules only that the write is
permitted and that the 6 are on the register.

> **Amended 2026-08-28 by [ADR-0203](0203-an-addon-provides-the-names-it-can-and-injects-the-content-it-cannot.md) dec. 1 and dec. 2.**
> *"That pass's call"* is made: **PROVIDE** — `plugin.gd` writes the names at enable time.
> And *"the addon's count is 0 today and must stay 0"* is narrowed: it is true of
> `exmateria_battlefield` and **false of the install target**, which dec. 2 defines as three
> addons — `exmateria_platform/display_port/PSXDisplay.gd:106` reads
> `ProjectSettings.get_setting("shader_globals/" + name, {})` at runtime, so the count is 1.
> The rule is about DIRECTION: a runtime read sourcing configuration the host was expected to
> supply stays forbidden; a read that decides whether this addon's own write is needed is part
> of the write and is permitted. Without that carve-out this decision forbids the only
> idempotent spelling of the thing it permits.

**9. The eight input actions get dec. 8's answer, because they are dec. 8's shape.**
All eight are host `project.godot` input-map entries. Same choice, same permission, same
register. The **test is that the action is not a `ui_*` built-in**, not that the host
happens to declare it: a guard keyed on the host's `project.godot` would go blind the day
the host stopped declaring the action, which is this repo's own
*a-guard-keyed-on-the-consumer* failure.

> **Amended 2026-08-28 by [ADR-0203](0203-an-addon-provides-the-names-it-can-and-injects-the-content-it-cannot.md) dec. 3.** The stated test — *"the action is not a
> `ui_*` built-in"* — is superseded. Arms 2 and 3 now score *the addon REQUIRES it and no
> addon in the walk PROVIDES it*, because under dec. 8's permitted write a correct fix moves
> the old predicate by zero. This does not re-open the objection above: the new predicate
> reads the ADDON's provide list, not the host's `project.godot`. The precedent is
> **ADR-0003 dec. 7 Arm A** (`exmateria-sound/tools/check_globals.py`'s CREEP arm), which
> ships this exact predicate for the autoload channel — not ADR-0190's arm 4b, which asks the
> weaker question of where a declaration sits.
> ⚠️ ADR-0203 dec. 4: this repo's `project.godot` has **no `[editor_plugins]` section**, so
> the write never executes here. The register's zero means *the addon provides*, never *the
> write works* — that needs a direct-call test, and booting the game proves nothing.

**10. The register is built BEFORE any move** — ADR-0192 dec. 1 as applied by ADR-0196
dec. 1. *After the move, a scanner blind to the old spelling is indistinguishable from a
correct one*, and this pass's Class A move erases its own baseline exactly the way the enum
move did: once `tile_overlay.tres` lives in the addon, a scanner that never learned to read
`res://` out of a `.gd` reports the same **0** as a correct one. The burn-down is a **named
list, never a filter** (#424), and both ratchet arms are seeded: an unlisted reach reds, and
a listed row whose site is gone reds as **stale**. Every seed constructs *both* the site and
the row — a control in this family has expired on success four times, and a seed that reads a
row off the shipped list goes vacuous the day the list empties.

**11. Criterion 1 is not touched by this pass.** Different axis, deliberately open under
ADR-0196 dec. 8. Closing it as a bonus would put one pass's name on two decisions and make
the register answer two questions, which is ADR-0131 dec. 7's own named failure.

## Prediction

Written before the register is built, so the first run grades it rather than the reverse.
A blind scanner and a clean tree both report 0; only a *predicted* population separates them.

1. **Arm 1 (asset reaches) reads 11 sites over 8 files on first run.** If it reads 0, it is
   blind, not clean. If it reads more than 11, the extra is either a `res://addons/…` path
   the permitted-root test failed to exempt, or a docstring — `DoodadLibrary.gd` holds 4 of
   the latter and they must **not** score.
2. **Arm 2 (input actions) reads exactly 2.** The addon names no `ui_*` action; measured 0.
3. **Arm 3 (shader globals) reads 6**, of which 4 are declared inside the addon and 2 arrive
   through platform `#include`s. If it reads 4 the include walk is missing; if it reads 12 it
   is scoring the whole walk and `PSXDisplay.gd`'s pushes, which are not declarations.
4. **Arm 4 (fork tokens) reports 6 files and scores nothing.**
5. **Class A's three rows go STALE when the move lands**, and the register returns 1 until
   they are deleted. That red is the grade, not a regression — it is the only evidence the
   scanner was satisfied rather than blind.
6. **`debug/MapGridOverlay.gd:19` scores 0 in arm 1.** It is a `res://addons/exmateria_schema/`
   preload, permitted by dec. 2. A register that flags it has the permitted-root test
   inverted; a register that cannot see it at all is blind to `preload` and will also be
   blind to `TileCursor.gd:150`, which is the one parse-time site in Class A.

### Graded — the register's first run, `0b13c4b45`

**5 of 6 held; prediction 2 missed by a factor of four, and the miss is the useful one.**

1. ✅ **11 sites over 8 files**, exactly. No docstring scored — `DoodadLibrary.gd`'s four
   prose mentions stayed out — and no permitted-root path scored.
2. 🔴 **MISSED: 8 distinct actions over 12 rows and 32 sites, not 2.** The predicted number
   came from a grep for `is_action_pressed("literal")`, and six of the eight names never
   appear inside such a call. Had the register been built to that prediction it would have
   reported 2, agreed with the number it was checked against, and been **blind to three
   quarters of the arm** — which is dec. 10's entire thesis arriving one arm early and about
   this ADR rather than about a later pass. The prediction is left standing above, wrong,
   because a corrected prediction grades nothing.
3. ✅ **6 globals**, 4 declared in the addon and 2 reached through platform `#include`s.
4. ✅ **6 files** in the fork arm, scoring nothing.
5. ✅ **HELD, and in both directions at once.** The move landed with the burn-down
   untouched and the register returned **1**: three Class A rows **STALE**, and *two rows
   UNLISTED* that the move had relocated. Neither half could have been faked by a blind
   scanner — a scanner that could not read `res://` out of a `.gd` would have reported the
   same 0 before and after.
6. ✅ **`MapGridOverlay.gd:19` scored 0**, and the guard is *not* blind to `preload`:
   `TileCursor.gd:150`, the one parse-time site, is on the register.

**The move subtracted three and ADDED TWO, and only the register could say so.**
`tile_cursor_opaque.tres` carries its own two `RANGETILE` `ext_resource`s. They did not
appear with the move — they were always there, one indirection away, invisible to *every*
instrument while the file sat outside the addon root. Arm 1 went **11 → 10**, not 11 → 8,
and the two are booked as Class B beside the `Tile.gd` rows naming the same two textures.
A fix booked into the bucket it drains is how a delta lies; the new file was classified
before the delta was believed.

> 🔴 **And the count is the wrong measure of this move anyway.** `TileCursor.gd:150` was the
> register's one **parse-time** site — a `preload` of a file a bare project does not have,
> which stops the addon *loading*. It now preloads a file the addon ships. What remains is
> two textures that fail at *runtime*. The register counts sites, so it cannot show this;
> it is the reason the move was worth making, and it is why dec. 5 splits by class rather
> than counting.

**One defect the register found in itself.** `^\s*global uniform` under `re.M` matched from
the blank line *above* a declaration, because `\s` matches a newline — `psx_dither.gdshaderinc`
read **6** for a declaration on **7**. Fixed to `[ \t]*` and pinned by
`test_a_global_uniforms_line_number_is_the_DECLARATION_line`. A line number quietly off by one
is what a reader checks once, finds wrong, and then stops trusting the whole register over.

## Consequences

- **The install term is owned.** ADR-0196's Consequences, and ADR-0164 dec. 4's silence, stop
  being forwarded.
- **"Empty project" is now a three-addon project on a forked engine**, and that is a weaker
  claim than the goal's plain words. It is written down in that form on purpose: the
  alternative is a claim nobody can satisfy, and dec. 2's grounds are 16 shader includes and
  9 kernel symbols, not preference.
- **The register reads 49 sites over 29 rows** — A 3, B 7, C 1, actions 12, globals 6 —
  against a target of 0, and the seeded ratchet fires in both directions (17 tests).
- **Class A is closed and the addon now PARSES in a bare fork+kernel+port project.** The
  register's only parse-time site is gone; what is left fails at runtime or at shader
  compile. Verified in the engine, not inferred: the addon's own `TileCursor.tscn` boots
  clean on the 4.8 fork, and a control that breaks the same `preload` path produces
  `Parse Error: Preload file … does not exist` — so the clean run is evidence rather than
  silence. ⚠️ **Godot exits 0 on a parse error**, so the log is the signal and rc is not.
- **A generator's output path is part of the move.** `parse_cursor_bob.py` wrote
  `tile_knife.json` to `assets/sprites/`. Repointing only the consumer would have left a
  stale copy at the old path and a never-refreshed one at the new, with nothing failing to
  say so. The glove half stays put — `UI` reads it, and only `Battlefield` was extracted.
- 🔴 **The addon does not become installable at this pass.** The register lands with a
  populated burn-down and rc 0 — rows printed under a heading that says *"not a pass"*, the
  `DOOR_BURN_DOWN` / `PORT_BURN_DOWN` / `PUBLISH_BURN_DOWN` shape. An rc of 1 at pre-flight
  aborts `tests/run_all_tests.sh` for everyone standing on the commit; the rc-1 arms
  (unlisted, stale) are not softened.
- **The portability guard keeps a gap this register does not close for it.**
  `check_addon_portability.py` still reports OK over 11 asset sites. Two instruments now
  answer the same goal and disagree, which is worse than one instrument being wrong.
  ⚠️ **Naming the follow-up rather than doing it here:** the portability guard should print
  the install register's headline or defer to it. Owner: the pass that closes Class B, which
  is the last class to leave the register.
- **Class B will not reach 0 by moving files**, and the register must not be read as if it
  could. Its 7 sites close by removing the literal, and the *dependency* survives as a
  documented contract. A future reader seeing "7 outstanding" should reach for dec. 5, not
  for a file move.
- **Dec. 8 admits a new mechanism to the addon.** `plugin.gd` gains the right to write
  `ProjectSettings` at enable time, and the addon's runtime `ProjectSettings` read count
  stays at its measured 0. Those two facts must be stated together or the next audit reads
  the write as the coupling the portability guard forbids.
- **Four counts were wrong and are corrected on the record**: three inherited (shader globals
  12→6, cross-addon 23 rows → 9 symbols, "gitignored" → 5 of 9 targets tracked) and one this
  ADR produced itself (**input actions 2→8**, caught by the register it ordered built). The
  tracked-ness correction changed the design; the other three would each have set the
  register's expected population wrong, which is the one input dec. 10 cannot get wrong and
  still grade anything.
- 🔴 **An ADR's own prediction was one of the wrong numbers.** Dec. 10 orders the register
  built before the moves so a scanner cannot be graded against a baseline it erased. The
  same argument applies to the *ADR*: had the register been written to agree with
  prediction 2, it would have read 2, matched, and been blind to six of eight actions. A
  prediction is only worth writing if the instrument is allowed to contradict it.

## Alternatives considered

- **Bare project, no siblings — the goal's literal words.** Refused by dec. 2. It costs
  undoing ADR-0139 dec. 9/12: 9 kernel and port symbols over 23 rows, and 16 shader
  `#include` lines with no in-addon replacement. The kernel exists *so that* two addons may
  share these names; a portability rule that forbids naming it makes the kernel pointless.
- **Vendor the kernel and the port into the addon.** Achieves the literal goal and creates
  three copies of `psx_ot_depth.gdshaderinc` that drift. ADR-0139 dec. 1's whole subject is
  that the shared surface is real and enumerated; duplicating it to satisfy a packaging rule
  inverts the ADR to buy a property no user has asked for.
- **Treat every `res://assets/` reach as a declared asset contract** (the reading this pass
  inherited). Refused by dec. 5 on measurement: 5 of the 9 distinct targets are tracked and
  ship with a clone, and 3 of the 11 sites point at assets the addon simply owns. Declaring a
  contract for those would book permanent debt that was never real and leave the parse-time
  `preload` at `TileCursor.gd:150` unfixed.
- **Move `CombatUI.tscn` into the addon.** Turns arm 1 green and makes the tree worse: the
  addon would then own and ship the host's combat UI. Dec. 6 rules the edge is a layering
  inversion, and this is the case that proves a register can be satisfied in the wrong
  direction — which is why dec. 6 states the owner rather than leaving the path to whoever
  wants a green number.
- **Score the fork tokens as debt.** Refused by dec. 3. The fork is the target platform; a
  register that scored its own target would never reach 0, and a burn-down that cannot reach
  0 stops being read.
- **Extend `check_addon_portability.py` with a `res://` arm instead of a new guard.**
  Reasonable and rejected on one ground: the portability guard walks six addons and answers
  *"does any addon reach a system"*. This register answers *"is THIS addon installable"*,
  needs a per-site burn-down with owners, and grades a move by rows going stale. Folding them
  makes one number answer two questions. The Consequences name the reconciliation instead.
- **Close criterion 1 in the same pass.** Refused by dec. 11 — different axis, and ADR-0196
  dec. 8 already named the pass that owns it.
