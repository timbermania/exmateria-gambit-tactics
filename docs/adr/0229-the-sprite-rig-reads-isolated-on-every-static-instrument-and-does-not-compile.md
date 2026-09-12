# The sprite rig reads isolated on every static instrument and does not compile

[ADR-0228](0228-the-rig-scores-six-of-nine-and-it-is-the-first-system-with-no-per-domain-escape.md)
closed extraction #4 reporting *"The rig's own half is 29 → 0 out and 118 → 33 in"*, criterion
4 at `exmateria_sprite_rig 0 (+6 oracle, 2 mount)`, and `check_addon_portability.py` rc 0 with
*"the only outstanding `ARM6_BURN_DOWN` rows belonging to `exmateria_sound`"*. Every one of those
readings is true. Every one of them is **static analysis run
inside the host checkout**, and the addon does not compile in a project that is not this game.

Two files, four lines, and both were already on a register — under a heading that says it is
not enforced *because there is no project to enforce it against*. This pass builds that
project: `tests/stranger/exmateria_sprite_rig/`, the fifth stranger rig, the first one to own a
scene, and the first instrument in the repo that can tell **came up and refused** from **came
up and died**.

Status: accepted (2026-09-04). Builds
[ADR-0194](0194-a-test-belongs-to-the-addon-it-can-run-without-the-game.md) dec. 1's ratchet —
*"The loop iterates over the five addon roots that exist, and gains one each time an extraction
lands"* — for the root extraction #4 landed. Precedent for adding a rig is
[ADR-0210](0210-a-stated-host-use-was-green-and-twenty-times-understated.md) dec. 6.
Tickets: [#847](https://github.com/timbermania/fft-monorepo/issues/847),
[#848](https://github.com/timbermania/fft-monorepo/issues/848).

## Context

### The heading was an IOU and nobody was named on it

`tools/check_addon_portability.py` arm 2 has printed this for the whole of extraction #4:

```
standalone-parse DEBT — 4 line(s) in an addon with no project.godot of its
own name a HOST autoload. Not enforced (there is no standalone project to
parse against yet); it is what the next extraction has to answer.
  addons/exmateria_sprite_rig/layers/SpriteLayerManager.gd:121,811  Tune
  addons/exmateria_sprite_rig/render/CameraRelativeRenderer.gd:35,43  PSXDisplay
```

A heading that scores rows and then says *not enforced* is a promise to somebody who is not in
the room. `check_addon_portability` exits **0** with those four lines printed, and every summary
downstream of it reads the 0. That is not a defect in the guard — the guard is right that it
cannot parse a project that does not exist — but it means the addon's isolation has been
reported by four instruments that all share one blind spot, and none of them says so at the
point a reader sees the number.

### Nothing said a fifth rig was owed

`tools/_runner_tests.stranger_rigs()` GLOBS `tests/stranger/*/run.sh`.
`classify_blueprint.WALK_ROOTS` is the register of in-walk addons and became five when
`addons/exmateria_sprite_rig` joined it. No instrument joins those two readings, so the suite
reported four rigs, four passes, and never that a fifth was missing.
`tests/stranger/README.md` said **"All four in-walk addons have one"** while five existed. The
gap was found by noticing an absent `[PASS] stranger:…` line.

## Measurement

`bash tests/stranger/exmateria_sprite_rig/run.sh`, first run, before any change:

```
[ok] subject: res://addons/exmateria_sprite_rig   known failures declared: 0
[FAIL] res://addons/exmateria_sprite_rig/layers/SpriteLayerManager.gd loaded but did not COMPILE
[FAIL] res://addons/exmateria_sprite_rig/render/CameraRelativeRenderer.gd loaded but did not COMPILE
71 passed, 2 failed
SCRIPT ERROR: Parse Error: Identifier "Tune" not declared in the current scope.       (x2)
SCRIPT ERROR: Parse Error: Identifier "PSXDisplay" not declared in the current scope. (x4)
SCRIPT ERROR: Compile Error: Failed to compile depended scripts.                      (x2)
ERROR: Failed to load script ".../content/SpritePaletteResolver.gd" with error "Compilation failed".
```

Two direct failures; the cascade behind them takes `exmateria_sprite_rig.gd` — **the addon's one
published global name** — plus `content/SpritePaletteResolver.gd`,
`layers/WeaponAnimationSelector.gd` and `viewer/SequenceViewer.gd` with it.

### `get_instance_base_type()` is not a witness for a CASCADE, only for a direct parse error

Measured in the staged tree with a probe that loads five files and prints what the engine says
about each:

| file | engine says | `get_instance_base_type()` | `can_instantiate()` |
|---|---|---|---|
| `layers/SpriteLayerManager.gd` | Parse Error | `""` | false |
| `render/CameraRelativeRenderer.gd` | Parse Error | `""` | false |
| `exmateria_sprite_rig.gd` | `Failed to compile depended scripts` | `RefCounted` | true |
| `content/SpritePaletteResolver.gd` | `Compilation failed` | `RefCounted` | true |
| `viewer/SequenceViewer.gd` | `Failed to compile depended scripts` | `Node3D` | true |

`stranger_install.gd`'s script arm uses `get_instance_base_type() != ""` and its docstring is
correct about why: `load()` returns a non-null `GDScript` for a file that did not parse. What
the docstring does not say is that a file which failed only as a **cascade** reports a normal
base type and instantiates. Three of those five score green on that arm. What catches them today
is `rig.sh`'s separate rule that an unexplained `SCRIPT ERROR` is the finding — a different arm,
in a different file, and the only reason the scene's verdict is not wrong. Stated here rather
than repaired: the repair belongs with whoever next touches that arm, and the current pairing
is sound.

### The null-guard that cannot fire

```gdscript
render/CameraRelativeRenderer.gd:35   last_psx_camera_angle = PSXDisplay.live_camera_angle if PSXDisplay else 0
render/CameraRelativeRenderer.gd:43   var current_psx: int = PSXDisplay.live_camera_angle if PSXDisplay else 0
```

A bare autoload identifier is resolved at **compile** time. With no `[autoload]` line for the
name the file does not parse, so the ternary's fallback is unreachable by construction. The
intention to degrade gracefully is written into the source and the source cannot run.
[ADR-0202](0202-installable-is-the-fork-plus-the-kernel-and-the-port.md) dec. 7 already ruled
the working shape CONFORMANT, and `tools/check_addon_install.py:95` records it verbatim:

> - **A soft, null-guarded autoload reach**, which ADR-0202 dec. 7 rules CONFORMANT.
>   `TunePort.gd:78`'s `root.get_node_or_null(^"Tune")` serves defaults when the answer is
>   null. The consequence is stated rather than scored: in a bare project every tunable
>   override is inert and the compiled-in defaults apply. That is a working install.

The difference between the two spellings is a string versus an identifier, and it is the whole
difference between a guard and a comment.

### The viewer came up, refused as documented, and then threw forever

`install/SpriteRigContentRoot.gd`'s contract is specified and correct: the default root is empty
on purpose, `resolve()` refuses once per run in words that name the setting, and the docstring
promises *"Until then no unit sprite will composite."* Driving `viewer/SequenceViewer.tscn` in
the rig produced exactly that refusal — and then:

```
SCRIPT ERROR: Invalid access to property or key 'wep1_v_offset_pixels' on a base object of type 'Nil'.
              at: _update_offset_info (…/viewer/SequenceViewer.gd:551)
SCRIPT ERROR: Invalid call. Nonexistent function 'advance_frame' in base 'Nil'.   (x2 per frame)
              at: _process (…/viewer/SequenceViewer.gd:211)
```

`_initialize_animation_system()` bare-`return`ed at its empty check, leaving `sprite_layers` and
three `AnimationPlayback`s null, and `_ready` carried on into `_update_offset_info()` while
`_process` advanced a null playback every frame for the life of the run.

**Isolated from the burn-down, not assumed.** Both causes were present at once. A scratch copy of
the staged tree with the two autoload reaches replaced (`ExMateriaPlatform.TunePort` for `Tune`,
a `get_node_or_null` helper for `PSXDisplay`) removed every parse error and every cascade line
**and left all three Nil throws standing**. They are the content-root path's, not the burn-down's.

Nothing in the host can reach this: `godot-learning/project.godot` always declares
`exmateria_sprite_rig/content_root`, so the empty branch is unreachable there. A stranger project
is the only project that takes it.

### `rig.sh` staged rig-owned scenes and never ran them

The staging step has copied `$HERE/*.gd` and `$HERE/*.tscn` into the work dir since #652, and
`tests/stranger/README.md`'s "Adding a rig" step 4 has always said to add a skip row *"for any
scene the rig owns"*. Both ends assumed a loop that was not there. All four existing rigs own
zero scenes, so the gap cost nothing for exactly as long as nobody used it.

## Decision

**1. `tests/stranger/exmateria_sprite_rig/` exists — the fifth rig, one per in-walk addon. BUILT.**
`project.godot` + a four-line `run.sh` shim, the shape
[ADR-0210](0210-a-stated-host-use-was-green-and-twenty-times-understated.md) dec. 6 set. Nothing
new is invented: `plugin.cfg` already declared `engine="fork"` (#744 re-measured it and it
flipped from `stock`) and `deps="exmateria_schema exmateria_platform"`, so the rig read both and
ran on day one. Verdict now: `[PASS]` on all four phases, exit 0.

**2. The four lines are NAMED on a burn-down, not fixed here — and they are TWO debts.**
`known_failures.tsv` carries one row per file with the engine's own parse error as the signature.
Arm 2 lumps them because it reads the host `project.godot`'s `[autoload]` block and both names
are in it, but they are not the same thing:

| | script lives | what is missing | fix |
|---|---|---|---|
| `Tune` | `res://src/core/Tune.gd` (the HOST) | the whole dependency | `ExMateriaPlatform.TunePort`, which already exists and which `install/RigDebug.gd` in this same addon already uses — [#847](https://github.com/timbermania/fft-monorepo/issues/847) |
| `PSXDisplay` | `addons/exmateria_platform/display_port/PSXDisplay.gd` (a DECLARED dep the rig STAGES) | only the `[autoload]` binding — an install step | no port exists; whether one is owed is a measurement — [#848](https://github.com/timbermania/fft-monorepo/issues/848) |

**The addon's own source already names the debt and the fix.** `install/RigDebug.gd:24`, in this
same addon, carries: *"🔴 `TunePort`, NOT `Tune`. `Tune` is a host autoload and naming it is
standalone-parse debt (`check_addon_portability` arm 2) even though arm 1 cannot see it —
`platform` is a tier, not a system."* One file in the addon went through the port and left the
note; two did not. The knowledge was never missing. What was missing was an instrument that
makes the difference between the two spellings cost something.

Not paid in this commit, and the reason is the record rather than the effort:
`tests/stranger/exmateria_battlefield/known_failures.tsv`'s header is the precedent, and the
grading it describes — *"The rig said so the first time the two lines met"* — only works if the
row exists before the fix. `stranger_burn_down.gd` reds the day either compiles, so the row
cannot outlive it. `TunePort.get_value` also takes a fallback the direct spelling does not, which
makes #847 a behaviour decision and not a rename.

**3. A rig may own scenes, and `rig.sh` runs them. BUILT.**
A fifth loop, after the addon-owned tests and before dec. 7's absence arm, over
`tests/stranger/<addon>/*.tscn`, held to the same throw rule as every other scene. **When a scene
belongs to the rig rather than to the addon:** an `addons/<addon>/tests/` scene runs in the host
suite *and* in the stranger project, so it may only assert what is true in both. A claim the host
**falsifies** belongs to the rig. That is
[ADR-0194](0194-a-test-belongs-to-the-addon-it-can-run-without-the-game.md) dec. 4's rule —
*"it would run them **in the host project**, which is precisely the project whose fixtures the
exercise exists to prove unnecessary"* — read in the other direction.

**4. `SequenceViewer` refuses instead of throwing. BUILT.**
One `_drivable` flag set at the end of `_initialize_animation_system()`, gated once in `_ready`,
and a `_refuse_undrivable()` that calls `set_process(false)` and writes the setting's name into
the viewer's own info label. One flag rather than a null-guard at each of ~30 deref sites: the
object is either fully wired or it does not drive at all, which is what the content-root contract
already promises in words. `set_process(false)` is the load-bearing half.

**5. The rig's arm is `stranger_sequence_viewer`, and its PRECONDITION is an assertion.**
26 assertions: the subject's content-root script loads at all, the project declares no
content root (checked, because a rig that quietly acquired
one would turn every arm below green while measuring the host's case), `resolve()` returns `""`
for every `*_SUBPATH` constant the contract declares (derived from the class, not re-listed), the
refusal latches exactly once, and the viewer loads, instantiates, survives 30 frames in the tree,
reports itself not drivable, is not processing, and names
`exmateria_sprite_rig/content_root` in its label. **Loading a member and driving it are different
claims** — `SequenceViewer.tscn` loads and `SequenceViewer.gd` compiles, and both were green on
the run that found this.

**6. A RIG-OWNED SCENE MAY NOT SPELL ITS SUBJECT'S PATH, and criterion 4 caught the first
draft doing it.** `stranger_sequence_viewer.gd` opened with
`preload("res://addons/exmateria_sprite_rig/install/SpriteRigContentRoot.gd")` and a sibling
constant for the viewer scene. `check_lattice_scene.py` arm 1 reported both as unlisted
production reaches and the rig's reading went `0 (+6 oracle, 2 mount)` → **BURN-DOWN BROKEN**.

The register is right and the fix is in the rig, not in the register. A guard that hardcodes
its subject's directory breaks the day the subject moves — the single event this whole family
exists to survive — so a rig spelling `res://addons/<itself>/` contradicts its own thesis.
`shared/stranger_install.gd:_subject()` already learns the root from
`application/config/name`; the arm now does the same and reaches in with
`install/SpriteRigContentRoot.gd` and `viewer/SequenceViewer.tscn` as relative subpaths.

Neither of the register's escape hatches fits, which is the check that this is a rig defect
rather than a register gap. `SCENE_ORACLES`' machine condition 2 requires the file to name a
HOST path — *"a stranger rig has no host, so a test that names host territory cannot move"* —
and a rig scene names none, by construction. And a `SCENE_BURN_DOWN` row could never be paid
off, because [ADR-0194](0194-a-test-belongs-to-the-addon-it-can-run-without-the-game.md) dec. 3
puts the rig outside the addon *by rule*: exactly the state
`check_addon_install`'s arm 4 refuses in the words this guard's own header quotes, *"a register
that scored its own target could never reach 0 and a burn-down that cannot reach 0 stops being
read."* Widening the register would have bought a hole; the addon path was simply the wrong
thing to write.

Cost: the `preload` becomes a `load`, so the arm asserts the content-root script loaded rather
than getting it checked at parse time. That assertion is the 26th, and it is a better error
than a parse failure would have been.

**7. `check_addon_portability` arm 2's heading is answered for this addon, and the wording stands.**
The arm is not changed. It is right that it cannot parse a project that does not exist; what was
missing was the project. The rows are now enforced by a different instrument, priced as compile
failures rather than as reach lines to tidy later, and ticketed. Same shape as the battlefield
rig re-pricing `ARM1_BURN_DOWN`'s own two rows.

**8. Nothing still tells anyone a rig is MISSING. FILED, not built.**
`stranger_rigs()` globs; `WALK_ROOTS` registers; no instrument joins them. A guard is cheap and
was deliberately not written here, because the honest version has to decide what an addon
*without* a rig means for an addon that has just been created and has not been measured yet —
a policy question, not a plumbing one. `tests/stranger/README.md` now carries the warning at the
top of the file, which is where the next author will be.

## Consequences

- **Goal #5 is UNMET for `exmateria_sprite_rig`, on record, with two tickets.** The rig's own
  banner says so in the weaker sentence `stranger_install.gd` keeps for exactly this case —
  *"stands up in a project that did nothing for it EXCEPT for 2 named file(s) it does not:
  6 files, source-copy staging. Goal #5 is UNMET for this addon and the rows above say by how
  much"*. `check_addon_portability` still exits 0 and still prints its four lines
  under *not enforced*; the two instruments do not
  disagree, they answer different questions —
  [ADR-0202](0202-installable-is-the-fork-plus-the-kernel-and-the-port.md) dec. 1's
  *"`isolated` and `installable` are different terms, and this ADR owns only the second."*
- **[ADR-0228](0228-the-rig-scores-six-of-nine-and-it-is-the-first-system-with-no-per-domain-escape.md)'s
  isolation readings are not retracted and not sufficient.** `29 -> 0 out`, criterion 4 `0
  production`, axis B 0 on four arms and goal #5 0 are all correct measurements of what they
  measure. None of them is a statement that the addon compiles elsewhere, and this pass is the
  first time anything has been.
- **The suite gains one rig.** `run_all_tests.sh`'s stranger phase and
  `tools/run_tests_parallel.py:519` both glob, so both pick it up with no change. Cost: one more
  rig in the phase, four scene boots plus one stock boot.
- **`stranger_install.gd`'s script arm has a stated blind spot** (cascade failures report a normal
  base type). Not repaired here; `rig.sh`'s unexplained-throw rule covers it today and the two
  arms are load-bearing together.
- **`SequenceViewer` behaves differently in a project with no content root** — it now populates
  nothing and disables `_process`. In the host this branch is unreachable, so no host behaviour
  changes.

### Proven red, six ways (dec. 12 arm 3 / README "Adding a rig" step 3)

Each seeded, run, and restored; every one exits non-zero and names the right thing.

| # | seeded | reported |
|---|---|---|
| 1 | the `_drivable` gate removed | *the viewer is still processing with no content to drive* |
| 2 | `Tune` swapped for `TunePort` (a burn-down row paid) | *is on known_failures.tsv … and it now COMPILES. Delete the row.* |
| 3 | the rig declares a `content_root` | *a stranger project that supplies the content makes every arm below measure the host's case* |
| 4 | an UNLISTED file stops compiling | *AnimationNames.gd loaded but did not COMPILE* |
| 5 | a burn-down row naming a file not in the addon | *a burn-down row for a file that does not exist can never be paid off* |
| 6 | the rig-owned scene's `[PASS]` deleted | *stranger_sequence_viewer did not report PASS* |

Proof 6 is the one that matters for dec. 3: it is the witness that the new loop runs the scene
and that a failure inside it reaches the rig's exit code. It was first observed by accident —
the arm's own first version had a parse error and the rig went red before anything was seeded.

## Considered alternatives

**Arm 2 — a synthetic content root staged under the rig, driving a real sequence.** Rejected for
now, on the terms the handoff proposing it set: it needs fixtures matching eleven `*_SUBPATH`
constants and buys a claim about *rendering*, while arm 1 buys the claim goal #5 is actually
about — that the addon survives a host that supplies nothing. Arm 1 also found a defect on its
first run, which is the evidence that the cheap arm was the right first arm. Reconsider when
something needs the render path exercised outside the host.

**Fixing the four autoload lines in this commit.** Rejected: see dec. 2. A burn-down created and
paid in one commit leaves no record of what the instrument found, which is the whole grading
mechanism `tests/stranger/exmateria_battlefield/known_failures.tsv` describes.

**Putting the viewer arm in `addons/exmateria_sprite_rig/tests/`,** where `rig.sh` already had a
loop and no rig.sh change would have been needed. Rejected: that scene runs in the host too, and
its central assertion is one the host falsifies. Taking the cheaper route would have meant either
a host-suite failure or an arm weakened until it asserted nothing about the absent root — the
second being the more likely and the worse.

**A guard joining `WALK_ROOTS` to `stranger_rigs()`.** Deferred, dec. 8.

## Update — 2026-09-05: #847 paid, and paying it moved the cascade set by nothing

`addons/exmateria_sprite_rig/layers/SpriteLayerManager.gd` now routes both lines through
`ExMateriaPlatform.TunePort`, aliased `const TunePort = ExMateriaPlatform.TunePort` — the
spelling `install/RigDebug.gd` and `addons/exmateria_battlefield/terrain/SkirtConfig.gd`
already use, and the spelling `tools/materialize_tunables.py`'s `CALLS` table keys on. The
fully-qualified `ExMateriaPlatform.TunePort.bind` would have gone quiet in R6's codemod rather
than red, which is why the alias is not a matter of taste. Dec. 2 called this a behaviour
decision and not a rename; the two absent-path answers are `bind` returning the literal (the
return value is discarded at the call site) and `get_value` falling back to
`CENTER_BIAS_DEFAULT`, the same constant the matching `bind` passes. The
`Engine.is_editor_hint()` guard stays and is now belt-and-braces: `TunePort._resolve()` rejects
the non-`@tool` placeholder on `has_method` as well.

Measured, before and after, on this worktree:

| instrument | before | after |
|---|---|---|
| rig install arm | 71 passed / 2 known failures | 72 passed / 1 known failure |
| rig burn-down arm | 2 files | 1 file |
| `rig.sh` exit code | 0 | 0 |
| `check_addon_portability` arm 2, standalone-parse DEBT | 4 lines, 2 files | 2 lines, 1 file |
| `score_goals` goal #5, `Sprite Rig` | 0 cross-system reach lines | 0 cross-system reach lines |

**THE CASCADE SET DID NOT MOVE.** `exmateria_sprite_rig.gd` — the addon's ONE published global
name — preloads BOTH named files, and `content/SpritePaletteResolver.gd`,
`layers/WeaponAnimationSelector.gd` and `viewer/SequenceViewer.gd` reach it for
`ExMateriaSpriteRig.ContentPort` / `.AnimationOpcodes`. All four are still down. Half the rows
bought none of the cascade, and a burn-down graded by ROW COUNT would have read that as half the
debt paid. #848 is the row that unblocks the published name.

**The boundary question now reads 0 tree-wide, and that did not settle dec. 8's shape.**
[ADR-0222](0222-criterion-4-is-the-production-channel-and-an-oracle-is-reported-beside-it.md) put
`dst_path` on `Reach` so a reader could ask whether a target resolves outside every addon root,
and `check_addon_portability` arm 7 is the only reader that asks it — scoped to `kind ==
"class_name"` by `_ARM7_KINDS`. Re-measuring that question over all five `WALK_ROOTS` with every
kind admitted: **1 row / 2 lines before this fix and 0 after**, the row being
`SpriteLayerManager.gd:121,811 -> src/core/Tune.gd`, and every other addon 0 in both states. So
widening `_ARM7_KINDS` to `autoload` would today be a zero-cost ratchet — and it would still not
join the two registers, because `PSXDisplay.gd` lives INSIDE an addon root and no boundary
reading can see it. `docs/GOALS.tsv` scores `Sprite Rig` goal #5 `met` and the rig's banner says
UNMET, both correctly, and nothing still joins them. That is dec. 8's shape a second time —
two registers, no join — and it is a question about which instrument owns the word, not a defect
in either one.
