# ADR-0307 — The tests lever is sublinear: UI's façade is 56 rows today, not 22, and the move is not gated on where the tests live

- **Status:** accepted
- **Date:** 2026-09-12
- **Ticket:** #1270 (extraction #8, pass 6 step 3 — audit)
- **Pass:** 6 of 9 (`docs/agents/refactor-loop.md`)
- **Grills:** ADR-0306 dec. 2, ADR-0306 dec. 4
- **Constrains:** ADR-0126, ADR-0194, ADR-0211, ADR-0212, ADR-0262, ADR-0306

ADR-0306 dec. 4 called where UI's tests live *"an open DECISION worth 45 published names"* and
ruled that *"it must be taken before the `git mv`."* I wrote that decision one pass ago. Both
halves of it are wrong, and they are wrong for two unrelated reasons.

The price is wrong because the lever is **sublinear**: a published name is freed only when the
**last** test naming it moves, so moving 41% of the tests frees 24% of the names. Today the
decision is worth **11** names, not 45.

The gate is wrong because ADR-0212 dec. 2 had already forbidden exactly this move, in advance:
*"Complete-close is a description of scope, never a precondition for a façade."*

## 1. The bar for a movable test is structural, not stylistic

A test can live in `addons/<name>/tests/` only if it names **zero host classes and zero host
autoloads**. This is not a convention to be argued about — the stranger rig runs the addon in a
project that contains no host scripts and no `[autoload]` block, so a host name is a parse or
run failure there. ADR-0262 dec. 6 is the same fact seen from the other side: an addon cannot
ship `project.godot` entries, so it cannot bring an autoload with it.

The three addons that already own tests obey it without exception:

| addon | own tests | naming a host class or autoload |
|---|---:|---:|
| `exmateria_battlefield` | 16 | 0 |
| `exmateria_schema` | 3 | 0 |
| `exmateria_platform` | 1 | 0 |
| **total** | **20** | **0** |

That zero is not a blind instrument. The same function, the same pass, over UI's tests returns
**74** — so it can report a violation and does. (Standing rule: never report a zero without a
positive control.)

## 2. The measurement

Subject: the **126** files in `tests/` that name at least one of M5's 79 `class_name`
declarations. Membership is `ui_facade_census.members()` (ADR-0306 dec. 1, 121 files);
name-extraction reuses the census's stateful blanker, so a name inside a comment, a string, a
`"""…"""` block or a `/* */` shader comment does not count (ADR-0306 dec. 6).

```
tests naming a UI member ........... 126
  MOVABLE (zero host names) ........  52
  STUCK   (names host/autoload) ....  74
```

### 2.1 The stuck set is one correlated cluster, not 74 problems

```
 35  CharacterCatalog        33  PromotedRosterSeeder
 23  Tune                    12  UI3Registry
  5  DebugConfig              5  TurnDirector
```

**52 of the 74** stuck tests name *nothing* outside those four. The cluster matters more than
the count: unsticking one name is worth almost nothing, because the tests that name it
overwhelmingly name another one too.

```
forgiving PromotedRosterSeeder alone ....  +0 tests
forgiving CharacterCatalog alone ........  +2 tests
forgiving {Tune, CharacterCatalog, PromotedRosterSeeder} ... +43 tests
```

A plan that picks off the biggest single sticker first buys zero.

## 3. The façade is sublinear in the tests moved

A test-only name is freed only when **every** test naming it moves; one stuck namer pins it.
So the façade does not interpolate between ADR-0306's two endpoints — it hugs the top.

| scenario | tests moved | stuck | **façade** | names freed |
|---|---:|---:|---:|---:|
| (a) every test stays in `tests/` | 0 | 126 | **67** | 0 |
| (b) **move what can move today** | 52 | 74 | **56** | 11 |
| (c) + tests use `TunePort` | 64 | 62 | **54** | 13 |
| (d) + `CharacterCatalog` addressed | 66 | 60 | **54** | 13 |
| (e) + `PromotedRosterSeeder` addressed | 95 | 31 | **50** | 17 |
| (f) + `UI3Registry` addressed | 104 | 22 | **41** | 26 |
| (g) floor: every test movable | 126 | 0 | **22** | 45 |

**Control.** Rows (a) and (g) are the two numbers ADR-0306 dec. 2 published — 67 and 22 — and
this table's machinery reproduces both at its extremes without being told them. The scenario
function is therefore measuring the same thing the census measures, and rows (b)–(f) are that
same function evaluated in between.

Read the shape, not the rows: **41% of the tests moved frees 24% of the names; 83% moved frees
58%.** ADR-0306 dec. 4's "45 names" is the value at a limit the project cannot reach without
porting two autoloads, and each of those is an extraction-sized job, not a step in this one.

## 4. Why the gate was invalid

ADR-0212 dec. 2 is explicit that a façade's *scope* is a description and not a precondition,
and it closes the door on re-litigation: *"Any future ruling that defers a façade because a
path channel is open is refuted by this decision and by the sound precedent, and must find a
different argument."* ADR-0306 dec. 4 deferred the move because the **test** channel was open.
That is the same form, and it does not have a different argument.

The concrete cost of the gate: nothing about the `git mv` changes with the tests decision. The
121 files move, 79 `class_name` declarations come out, one goes in, `res://` paths are
rewritten. Only the **length of the façade const list** differs — and a façade that publishes a
name it later stops needing is a line deleted, not a migration. The order is free in one
direction and expensive in the other, which is the definition of a decision that should not
block.

## 5. What this does not settle

Whether UI *should* eventually own its tests. It should — 56 rows is a large public surface —
but that is a sequence of small reversible moves after the extraction, each freeing names only
when it takes the last namer, and it is not on this pass's critical path. The `Tune` → `TunePort`
row (c) is the cheapest of them and is already mechanised by `tools/check_ui_tune_port.py`'s
rewrite; it is worth 12 tests and 2 names.

## Decisions

**1. A test may live in `addons/<name>/tests/` only if it names zero host classes and zero host
autoloads, and this is structural.** The stranger rig has no host scripts and no `[autoload]`
block. All 20 existing addon-owned tests obey it; UI has 52 that qualify and 74 that do not.
Argued in §1.

**2. UI's façade under the achievable move is 56 rows — 22 published plus 34 test-only names
pinned by a stuck test.** Not 22, which requires all 126 tests to move. Argued in §3.

**3. The tests lever is sublinear, because a name is freed only by its LAST namer.** 41% of the
tests moved frees 24% of the names. Any future estimate that prices a test migration linearly
in tests moved is wrong by construction. Argued in §3.

**4. ADR-0306 dec. 4 is refuted in both halves.** The price is 11 names today, not 45; and the
`git mv` is not gated on the tests decision, per ADR-0212 dec. 2. Pass 6 step 3 proceeds with
the conservative façade and migrates tests afterwards. This decision supersedes it.

**5. Unsticking a single host name is worth approximately nothing; the cluster is the unit.**
`PromotedRosterSeeder` alone frees 0 tests, `CharacterCatalog` alone frees 2, the three together
free 43. Argued in §2.1.

**6. `CharacterCatalog` and `UI3Registry` are autoloads, so no test naming them can move without
a port.** They pin 47 tests between them. Porting either is its own extraction and is explicitly
out of scope for extraction #8. Argued in §2.1 and §3.
