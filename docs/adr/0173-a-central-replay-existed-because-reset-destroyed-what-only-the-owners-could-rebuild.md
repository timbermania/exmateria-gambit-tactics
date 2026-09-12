# A central replay existed because `reset()` destroyed what only the owners could rebuild

`Tune.register_all()` named **seventeen owners across seven of the eleven
systems** — thirteen `res://` script paths and four `/root/` autoload paths, in
array literals dereferenced through a loop variable. ADR-0159 dec. 3 named it a
`platform` portability defect and deliberately declined to design the fix,
because the question it asks is not *where does this list live* but **how does a
tunable owner register without a central list at all?**

The answer is that it already did. `register_all()` had **eight call sites and
all eight were tests**; production never replayed anything, because every owner
registers at its own class load. The list existed to undo one line —
`_registry.clear()` inside `Tune.reset()`. A declaration's only producer is a
`bind` at its use-site, and for a class-load owner that use-site runs from
`_static_init`, which fires once per class load per process and cannot re-fire.
`reset()` destroyed a resource only the owners could make, so `Tune` had to hold
their addresses to make them make it again.

**So the fix is not a generic replacement for the list. It is not clearing the
thing the list existed to rebuild.** `platform` becomes a leaf by subtraction.

Status: accepted (2026-08-25). Resolves
[#535](https://github.com/timbermania/fft-monorepo/issues/535), which is
**off-map** — it unblocks [#563](https://github.com/timbermania/fft-monorepo/issues/563)
and does not close map [#560](https://github.com/timbermania/fft-monorepo/issues/560).
Built on trunk `af78a3e74`; `src/core/Tune.gd` is solely #535's by ADR-0169 dec. 2,
which kept it out of extraction #3's file move for exactly this reason.

## Context

ADR-0068 is the tunables contract; its **Addendum R** is the boot-registration
pass that split each owner's binds into a named `register_tunables()` and had
`register_all()` call all of them. ADR-0159 dec. 2 measured the reach and showed
goal #5's guard scores it **zero**, proving the zero was blindness with a
mutation seed. Dec. 3 concluded `platform` ships and ranked the inversion a
blocking precondition; the ranking was **amended before merge** (it is not) and
amended again by [#534](https://github.com/timbermania/fft-monorepo/issues/534)
arm 2. #534 built the two guards that held the list honest. This ADR retires both
by inverting them.

## Decisions

### 1. `reset()` is unchanged. `reset_overrides()` is the new, narrower verb.

Two resources live in `Tune`, and exactly one of them is rebuildable by its
caller:

| | producer | rebuildable from a test? |
|---|---|---|
| **override** — slug → live value | `set_value(slug, v)`, one line, no owner involved | yes, trivially |
| **declaration** — slug → code default + hint + persist class + use-sites | a `bind` at its use-site; for a class-load owner, from `_static_init` | **no** — `_static_init` fires once per class load per process |

`reset()` keeps its meaning: the total clean slate, overrides *and* declarations.
`reset_overrides()` does everything `reset()` does **except** the one thing it
cannot undo — it clears `_overrides`, `_committed` and the R8 scrub tracking and
leaves `_registry` standing. `reset()` is literally `reset_overrides()` plus
`_registry.clear()`.

**This ADR shipped the other way round first, and the tree said no.** #535's
candidate — and this ADR's first draft — inverted the default: `reset()` kept the
declarations and a new `reset_registry()` cleared them. It is the more elegant
statement of the finding (*the reflexive verb should not destroy what it cannot
rebuild*) and it is wrong here, because **registry ISOLATION is what most callers
of `reset()` actually want.** `_register` is first-write-wins, so a surviving
boot declaration hands a later test an earlier default. Measured on the suite,
not argued: `TuneFieldTest`, `AlignmentPanelTuneFieldTest`,
`TunablesRegistryModelTest` and `TunablesRegistryViewTest` all went red — *"the
spinbox shows the coalesced value — expected ~1.2500, got 1.0000"*, *"one row per
registered slug — expected 2, got 80"*.

**And the static scan written to find that population missed a member of it.** It
looked for `Tune.reset()` callers that re-bind a boot slug or call
`registered_slugs()`, and found twelve. `TunablesRegistryModelTest` is not among
them: it reaches the registry through `TunablesRegistryModel.rows(tune)`, one
indirection away. A verb used at 31 sites, read through arbitrary indirection,
cannot have its meaning changed on the strength of a grep — which is the argument
for changing the *rarer* thing. Seven call sites move to `reset_overrides()`;
nothing else in the tree changes behaviour.

The narrow verb is named for the resource it clears, alongside the
`load_overrides()` / `save_overrides()` / `clear(slug)` that already operate on
exactly `_overrides`. #535's proposed `reset_declarations()` names the resource it
*keeps*, which is backwards for a verb.

**An override may precede its declaration, and always could.** That is the
production boot order: `Tune` is the first autoload, its `_ready` calls
`load_overrides()`, and every owner binds later. `bind` coalesces
`_overrides.get(slug, literal)` whenever it runs. `set_value` asserts nothing. So
a test that scrubs *before* spawning the node that owns the slug needs no replay
either — it is doing what the staging file does at boot.

`register_all()` is deleted, along with all fifteen path references and the
`load()`/`has_method` guard tolerance that made a moved file and an un-migrated
one indistinguishable (ADR-0159 dec. 3's own mechanism). The seven feature tests
that called it now call `Tune.reset_overrides()` and nothing else. **That is the
whole diff on the test side**: the other 24 `Tune.reset()` callers, including
`TuneTest.gd`'s 47 sites, are untouched and mean what they always meant.

### 2. Both constraints still hold, and neither was ever the hard part.

ADR-0159's amendment recorded two bounds on any fix. Both are satisfied by
deleting code rather than by working around it:

1. **No compile-time edge out of `Tune.gd`.** `Tune` is the first autoload, so a
   `class_name` reference from `Tune.gd` to an owner would eager-load that
   owner's `_static_init` binds during `Tune`'s own boot, against a Nil `Tune`.
   After this change `Tune.gd` references **no owner at all**, by any mechanism —
   which is a stronger property than the constraint asked for, and S2 below is
   what keeps it.
2. **`_static_init` fires once per class load per process.** Unchanged, and now
   load-bearing rather than worked around: it is the only thing that runs a
   class-load owner's binds, which is what S1 checks.

### 3. The two guards #534 built are INVERTED, not retired — and two more join them.

This is the consequence #535's "Done when" did not name. The candidate fix
deletes the subject of four instruments the previous two tickets built. An
instrument that guards a list is correctly retired with the list; a suite that
goes quiet is not.

| retired | what replaced it | what changed about the question |
|---|---|---|
| `tools/check_tune_owner_manifest.py` (R1–R4) | `tools/check_tune_owner_self_registration.py` (S1–S4) | "is the list complete and does every entry resolve" → "does every owner's own boot path run its binds, and does `Tune` name nobody" |
| `tools/seed_tune_owner_manifest.py` | `tools/seed_tune_owner_self_registration.py` | same trick: `evaluate()` takes the rows as **data**, so the seed never writes to a shared worktree |
| `tests/TuneRegisterAllTest.gd` | `tests/TuneOwnerSelfRegistrationTest.gd` | a 17-row literal mirror of the manifest → a **discovery walk**: it names no owner and no slug |
| `tools/seed_register_all_coverage.py` | `tools/seed_owner_self_registration_coverage.py` | six cases, one per phase plus the anti-vacuity floor |

**The static half — S1–S4.**

  - **S1** every zero-arg `static func register_tunables()` is called from its own
    file's `_static_init()`. With the replay gone this is the *only* thing that
    runs those binds; an owner that declares the method and never calls it fails
    far away, as a `get_value` R5 assert or an `on_update` that applies null.
  - **S2** `src/core/Tune.gd` names **no** `res://…​.gd` script path and **no**
    `/root/…` autoload path. This is the inversion itself, mechanized, and it is
    what makes re-centralizing loud instead of convenient. (`res://config/…` is
    Tune's own staging file and registry snapshot, not an owner.)
  - **S3** every autoload owner calls `register_tunables()` from its own `_ready`
    — the autoload half of S1.
  - **S4** an arg-taking `register_tunables` is never called argument-lessly.
    This is #534's R3 finding kept alive after the list it guarded is gone:
    `src/effects/studio/SequenceThumbnail.gd` declares
    `static func register_tunables(owner: Node)` and is what makes "just add a
    `_static_init` to every owner" a trap rather than a mechanical fix.

Measured on arrival: **13 class-load owners, 13 calling from `_static_init`; 4
autoload owners, 4 calling from `_ready`; 1 arg-taking owner, calling from
neither.** Every rule clean, so every rule is seeded — and S2's fourth arm is not
synthetic: it feeds the guard **the real pre-#535 `Tune.gd`, read from trunk**,
and must flag its seventeen paths.

**The runtime half.** `tests/TuneOwnerSelfRegistrationTest.gd` discovers the
owner set by walking `res://src` and `res://addons` for the class-load shape and
reading `project.godot`'s autoloads off `ProjectSettings`, then derives each
owner's slug set **as data** — clear the registry, call its entry point, read
back what appeared. Three phases: load every owner and snapshot what their own
boot paths produced; per owner, assert it binds something and that every slug it
binds was in that snapshot; then hold `reset_overrides()` and `reset()` to their
split. 169 assertions, and it names nothing.

That last property is the point. #551 found that the guard built to prove the
manifest honest was **a second hardcoded copy of it** — *"the act of measuring
added to the thing measured"* — and a fifth place those paths were written.
Deleting the list without deleting its mirror would have moved the enumeration
into `tests/`, where `classify()` returns `None` for every file and no goal-#5
instrument would ever have scored it.

**And the static guard was never registered in `run_all_tests.sh`.** #534 built
it and nothing ran it. That is #565's finding (`check_vault_anchors.py`, never
registered at all) recurring one ticket later. Both halves are registered now,
and confirmed through the suite entry rather than by running the file.

### 4. Goal #5's guard cannot certify this fix. `path_refs.py` can, and S2 is the only instrument that sees all seventeen.

#535's "Done when" asks that `platform` score 0 outbound *because it reaches
nothing, not because the instrument cannot see it*. Staging `platform`'s four
files as an addon root and running `score_goals.outbound_reaches` — ADR-0159
dec. 2's own standard, now `tools/seed_platform_outbound.py`:

```
UNSEEDED (platform as-is):                                     0 cross-system reaches
SEEDED literal preload of a Battlefield file (dec. 2's arm):   1 cross-system reaches
SEEDED register_all()'s ACTUAL shape (array + loop load):      0 cross-system reaches
```

The guard is **live** — and **still blind to the shape the defect actually had**,
exactly as dec. 2 measured. A seed that only exercises the shape the guard can
see proves the guard runs, not that the tree is clean. So goal #5's zero is not
the evidence here; it never could be.

The non-blind witness is `tools/path_refs.py platform`, which scans `res://`
literals anywhere and therefore **did** see the defect:

| | outbound references | into systems |
|---|---:|---|
| trunk `67b469115` (pre-#535) | **13** | Battlefield 4, Cutscene 3, UI 3, Battle 2, Sprite Rig 1 |
| this branch | **3** | none — all three are `res://config/…`, Tune's own staging file and registry snapshot |

**Thirteen, not seventeen.** A `/root/` autoload path is not a `res://` literal,
so `path_refs.py` never saw the four autoload owners either — `touch_matrix.py`
gives `platform` no row at all, `score_goals` needs a literal, and `path_refs`
needs `res://`. **S2 is the only instrument in the tree that sees all seventeen**,
and that is the argument for it existing rather than leaning on a goal score.

### 5. A `[PASS]` marker is not a verdict, and this ADR got it wrong once.

The measurement that justifies decision 1 is: put `_registry.clear()` back into
`reset()` and run the seven tests that used to call `register_all()`. Scored by
grepping for `[PASS]`/`[FAIL]`, three go red and **four look green** — which
reads as #534 arm 2's finding (*a green test that cannot report the event*)
generalizing to more than half the population.

Scored through `tests/lib/verdict.sh`, the repo's **one** verdict reader (#451),
all seven report it:

| test | verdict | channel |
|---|---|---|
| `CursorTunablesTest` | FAIL | its own assertion — a scrub does not reach the spawned cursor |
| `ScenarioDialogueBoxTunablesTest` | FAIL | ” |
| `ScenarioWeatherTunablesTest` | FAIL | ” |
| `CameraFeelTunablesTest` | **THREW** | prints `[PASS]`; `get_value(render.psx_ui_par) before its bind` (R5) fires inside a node it spawned |
| `ScenarioCinematicTunablesTest` | **THREW** | ” |
| `UnitForwardTunableTest` | **THREW** | ” |
| `VitalsLayoutTunablesTest` | **THREW** | ” |

Rule 9 — *a green does not get to throw* — is what turns those four red, and it
is the rule a marker-grep cannot apply. **The first reading of this measurement
was taken off the marker and was wrong**, which is precisely the failure #451 was
written for; it is recorded here rather than quietly fixed because the same
grep is the obvious thing to reach for next time. All seven verdicts are now
pinned by name in `tools/seed_owner_self_registration_coverage.py`.

This does **not** overturn #534 arm 2. That finding is about a *narrower*
mutation — dropping ONE owner from the manifest — under which
`CameraFeelTunablesTest` genuinely stays PASS, because the camera re-registers at
its own class load and only `camera.*` were missing. Clearing the whole registry
starves the autoload slugs the camera also reads. Different mutation, different
reach; both stand.

## Consequences

- `platform` is 4 files / 858 lines and reaches no system. `Battlefield`'s
  `Tune` leg (66 lines) is now a reach into a leaf, and ADR-0159 dec. 3's *"`platform`
  ships"* is available on both halves rather than one.
- `Tune.reset()` changed meaning for **no test at all**. Seven of its 31 callers
  move to `reset_overrides()`; the rest are untouched. That property is the reason
  the design landed this way round rather than the elegant way round — see dec. 1.
- The tunables contract is unchanged. ADR-0068 R1–R8's *split the binds into
  a named `register_tunables()`* survives — the entry point is still there and is
  still what `_static_init` calls. What it no longer is, is a thing `Tune` calls.
- `tests/PilotStaticInitTest.gd` — *"Do NOT `Tune.reset()` — that would clear the
  boot registration we are here to verify"* — is still exactly right, and is left
  alone: it is the ADR-0068 pilot's own witness and asserts hints and a Vector2
  shape that nothing else does. Under the reverted-to design its comment would
  have needed rewriting, which was one more sign the blast radius was wrong.
- The `has_method` tolerance is gone with the list, so *"a partly-migrated
  codebase does not crash"* is no longer a property `Tune` provides. It is now
  S1's job to say an owner is un-migrated, loudly, at check time.
