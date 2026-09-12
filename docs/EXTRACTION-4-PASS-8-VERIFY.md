# Extraction #4 (`Sprite Rig`) — pass 8: Verify

- **Date:** 2026-09-04
- **Trunk at start:** `134937270` (merge of PR #821, pass 7)
- **Branch:** `verify/extraction-4-pass-8`
- **Loop:** `docs/agents/refactor-loop.md` (repo root), pass 8

---

## 0. What pass 8 owes, and what this pass could answer

The loop gives pass 8 **three registers — residue, gap, known drop — never
merged**, and one of the three is not extraction #4's to produce:

| register | owner | state here |
|---|---|---|
| **residue** — every unclaimed file gets a reason | this pass | **produced.** `docs/RESIDUE.tsv`, 33 files / 5,674 lines, `check_residue.py` rc 0 |
| **ballast diff** — an `R:` that was a live code path at baseline and reads `none` now | **deferred to E1/E3, [#310](https://github.com/timbermania/fft-monorepo/issues/310)** | **not run, by design.** The loop accepts the cost in its own words: *a behaviour dropped at extraction #3 surfaces after #15, not at #3* |
| **known drops** — behaviour dropped on purpose, with the ADR that authorised it | **epilogue E1** | **does not exist.** `docs/GOALS.tsv` already books goal #8 `open` for extractions 1, 2 and 3 on exactly this blocker; extraction #4 inherits it unchanged |

So this pass is residue attribution — plus the instrument audit that residue
attribution forced, which turned out to be the larger half.

**Before believing a green, say what a negative would look like.** A negative
here is a `.gd` file under `WALK_ROOTS` that nothing reaches and that
`residue.py` cannot give a class better than `orphan`. There are none. That
sentence is only worth as much as the walk's edge model, which is what §3.1 is
about.

## 1. The subject

`docs/RESIDUE.tsv` line 1 states its own roots, and this document restates them
rather than assuming a reader will look:

> `src`, `assets`, `addons/exmateria_schema`, `addons/exmateria_render`,
> `addons/exmateria_battlefield`, `addons/exmateria_platform`,
> **`addons/exmateria_sprite_rig`**

**`Sprite Rig` extracts INSIDE `WALK_ROOTS`.** The half-blindness the loop warns
about — *when a system extracts outside `WALK_ROOTS` it is half-blind* — is
`Audio`'s, not this extraction's: `exmateria-sound/` is a package the walk
**reports rather than enters** (ADR-0153 dec. 1), and the register says so on its
own second line. `no rows` about `Audio` is not `no residue` in `Audio`, here or
anywhere.

Four further limits, all of them properties of the instrument rather than of the
tree:

- **The ceiling is one-sided** (ADR-0112 dec. 1). `UNREACHED` contains everything
  dead **plus** anything reached only by a path the walk cannot see: **108
  non-literal `load()` sites** in walked code, against 656 `preload("literal")`
  and 46 `load("literal")`. `orphan` means *no static claim found*, never
  *provably dead*.
- **43 dangling `res://` literals** name nothing on disk. They are edges into
  nowhere, not residue.
- **21 addon-owned test files** under `addons/<name>/tests/` are inside the roots
  and deliberately excluded (ADR-0194 dec. 2). Nothing reaches a test from a
  declared root, so a subject containing them would report every one `orphan`.
  This exclusion is load-bearing in §3.1 — it is why `TerrainFixture.gd` was
  invisible.
- **19 of the 33 rows (4,090 lines) are reachable from one of the 14 declined
  scenes.** Declined is not deleted (ADR-0135 dec. 11); that is a separate
  question from deadness and is not this pass's to close.

## 2. The four drifts, attributed

`check_residue.py` opened this pass at rc 1 with four named drifts. All four are
now attributed to a commit and a decision. **None is a dropped behaviour.**

| file | drift | cause |
|---|---|---|
| `src/animation/ResourceHotReload.gd` | *no longer unclaimed* | **the real finding — §3.1.** `22b8b5b60` (#744 1/n) moved it into the addon; ADR-0211 dec. 2's façade then published it, and the walk read the publication as a use |
| `src/scenes/ProgressionTester.gd` | attribution changed, 1480 → **1486** | `05f636196` (#739): `const FacingDirection = ExMateriaSchema.Facing.Direction` and siblings — ADR-0217 dec. 7's alias block |
| `src/debug/UnitAnimationViewerPanel.gd` | attribution changed, 430 → **441** | same shape, `ed30ae648` (#746 3/n) — ADR-0211 dec. 4 aliases replacing the preloads the host may no longer write |
| `src/scenes/UnitAnimationViewerScene.gd` | attribution changed, 122 → **133** | same shape, `0254833c4` (#746 5/n) |

The last three are **one edit shape, landed three times**: the migration replaced
a host `preload("res://…")` with a `const X = <Facade>.X` alias, which is longer
by a line or two per symbol and changes nothing about the claim. All three keep
`declined` and their claim counts.

## 3. Five instrument defects

Pass 8's register was red for one reason and wrong for four more. Only the first
has an ADR; the rest are recorded here because they share the pass, not a
decision.

### 3.1 — A façade re-export was read as a use (**[ADR-0227](adr/0227-a-facade-re-export-is-not-a-use-and-the-closure-could-not-tell.md)**)

ADR-0211 dec. 2 publishes each addon's whole surface from one file as
`const X = preload("res://addons/…")`. ADR-0211 dec. 4 forbids the host from
preloading an addon path, so every host→member edge became a member access
`<Facade>.X` — the one shape `closure.py` had no edge for. Meanwhile the
publication table read as **51 real edges** across the five in-walk façades
(schema 11, render 1, battlefield 16, platform 3, sprite rig 20), and every
façade is reached because a root names its `class_name`. **All 51 members were
reachable by publication rather than by use.**

Blinding the sprite rig's façade alone moved the register from 31 / 5,329 to
**50 / 7,985** — 19 files, 2,656 lines the walk had stopped having an opinion
about. Asking the question properly (an edge from `<Facade>.X` to X's target, and
none from the publication line) finds **2 real rows and removes none**. The 19
were *unanswerable*, never *hidden residue*, and reporting them the other way
would be its own defect.

This was **already load-bearing before extraction #4**: extraction #3's goal #3
is scored `met`, and its evidence sentence read — before this pass corrected it —
*"docs/RESIDUE.tsv — no unclaimed file under addons/exmateria_battlefield"*.
That register could not have said otherwise.
`addons/exmateria_battlefield/lattice/TerrainFixture.gd` (292 lines, added by
`37b71f9fc`) is named by nothing outside the battlefield addon's own `tests/` —
which §1 excludes by design. It is a shipped test fixture (ADR-0218) and `test`
is the right class.

**`test` is a class goal #3 fails on.** ADR-0154 dec. 5: *"Goal #3's mechanical
test now fails on `orphan`, `cluster`, `test` and `tool` and reports
`declined`"*. So the corrected register does not correct a sentence — it flips a
score. `score_goals.py` began printing *GOALS.tsv disagrees with the code in 1
place(s)* the moment the register was right, and **extraction #3's goal #3 goes
`met` → `open`** (ADR-0227 dec. 6). The precise claim is not *this pass broke a
passing goal*: the score was never measured, because the register it was read
from could not see the file.

The remedy is `Battlefield`'s and it is a decision, not a deletion — either a
production namer is missing, or the fixture's home is
`addons/exmateria_battlefield/tests/` (ADR-0194 dec. 2), where the walk's subject
excludes it and goal #3 closes cleanly. Not settled here; see §6.

### 3.2 — `closure.py` seeded a phantom autoload

`project.godot` is an ini file and the autoload regex was applied to the **whole
file**, so `[exmateria_sprite_rig] content_root="res://assets/"` (`:71`;
`[exmateria_battlefield]` has the same at `:67`) was read as an autoload named
`content_root` pointing at `assets/`. Every run printed
`closure: SEED MISSING — assets/`, on the loop's only real safety net.

It was harmless **by luck**: the phantom target does not resolve, so no edge was
created. Had the value been a real script path, everything it reached would have
left the register as claimed with no way to notice. Scoped to the `[autoload]`
block: 27 keys scoped vs 28 unscoped, the difference being exactly the phantom.
`autoload_reach.py` already scoped this way.

### 3.3 — `check_addon_portability.autoload_names()` was unscoped the same way

Its docstring said `[autoload]` block; its loop read the whole file. **Latent**,
not firing: nothing writes `content_root.` today. Unscoped, arm 2 would build a
`content_root\s*\.` pattern and report a portability break against a global name
Godot never creates. Fixed, with the docstring and the code now agreeing. 69
guard unit tests pass.

### 3.4 — A `.gd` instrument was counted as a consumer

`residue.py`'s `INSTRUMENTS` list held only `.py` files, so
`tools/probe_rig_removed.gd` — which lists `res://src/scenes/UnitAnimationViewerScene.gd`
in a `HOST_NAMERS` const **in order to check it** — scored as a `tool` claim on
that file. An instrument naming a file is not a consumer of it; that is the same
confusion at a smaller scale as §3.1.

### 3.5 — Path needles matched prose

`residue.py` searched raw file text for an unreached path, so a path written in a
**comment** scored as a claim. Three sites register-wide, all prose. Fixed with
`path_view()`, which strips comments while keeping string literals, and which is
deliberately conservative: a line containing a triple quote or an unterminated
quote is kept verbatim. **The only error it may make is keeping a prose claim,
never dropping a real one.** `origin == "doc"` rows are exempt — for a doc the
prose *is* the evidence.

## 4. The register after

**33 files / 5,674 lines**, `check_residue.py` rc 0, 658 of 691 hand-written
`.gd` + shader files reached.

Two comparisons, and they are different numbers:

- vs. the **old edge model on today's trunk** (31 / 5,329): **+2, −0** — the
  measurement of ADR-0227.
- vs. the **committed register** (32 / 5,348, derived at `e326d0b24`): **+1**.
  `TerrainFixture.gd` is a true addition; `ResourceHotReload.gd` is a rename
  (`src/animation/` → `addons/exmateria_sprite_rig/resources/`, 47 → 53 lines),
  `declined` on both sides.

```
addons/exmateria_battlefield/lattice/TerrainFixture.gd          Battlefield  test      292  test:11,addons:1
addons/exmateria_sprite_rig/resources/ResourceHotReload.gd      Sprite Rig   declined   53  cluster:1,addons:1
```

**No row classifies `orphan` as a result of this pass.** `Sprite Rig` contributes
exactly one row to the whole register, 53 lines, and it is `declined` — its only
namer outside the addon is `src/scenes/UnitAnimationViewerScene.gd`, a declined
scene, and declined is not deleted.

`check_baseline.py --delta` rc 0; conservation prints, as it always does, without
being asserted (ADR-0148 dec. 1 / dec. 9).

## 5. What this pass cannot see

Stated rather than left to inference, because the loop's own recurring failure is
an instrument whose subject and question drift apart:

1. **Whether any ROM behaviour was dropped.** That is the ballast diff, and it is
   #310's, not this pass's. Nothing in §2–§4 is evidence about behaviour.
2. **Whether a drop was intentional.** No known-drops register exists. Goal #8
   stays `open` for extraction #4 for the same reason it is `open` for 1–3.
3. **Anything reached only through a dynamically built path** — 108 non-literal
   `load()` sites.
4. **Anything in `exmateria-sound/`** — reported, not entered.
5. **Anything under `addons/<name>/tests/`** — 21 files, excluded on purpose.
6. **Whether a `declined` scene should be deleted.** 19 of the 33 rows hang off
   the 14 declined scenes and that is a separate question.
7. **Documentation.** A green preflight proves nothing about it — all 11 pass-7
   findings sit under rc 0 with zero `FAILED` lines. Finding **S5** (48 dead
   vault `R:` citations) is still unowned; it is arguably this pass's, arguably
   #310's. Not claimed here.

## 6. Handoff to pass 9

- Goal #3 for `Sprite Rig` can now be scored against a register that has actually
  **entered** the addon. Before ADR-0227 it could only have repeated extraction
  #3's sentence. `Sprite Rig`'s one row is `declined`, which ADR-0154 dec. 5
  exempts, so the mechanical test reads `met` for it — on an answer this time.
- **Extraction #3's goal #3 is now `open` and has no owner.** The fixture is not
  dead code and deleting it would be wrong; the question is whether an
  addon-owned test fixture living outside `tests/` should count against goal #3
  at all, which sets ADR-0194 dec. 2 (tests are not the walk's subject) against
  ADR-0154 dec. 5 (`test` fails goal #3). Pass 9 should either move the file or
  file the question — this pass declined to settle another extraction's ADR.
- Goal #8 is blocked for extraction #4 on epilogue E1, identically to 1–3. Score
  it `open` with that reason, not `n/a`.
- `docs/GOALS.tsv` still has **no extraction-4 row**. Creating it is pass 9's.
- **#809 remains the only real isolation debt** and its owner is pass 9
  (ADR-0223 dec. 8). Nothing in this pass touched it.
