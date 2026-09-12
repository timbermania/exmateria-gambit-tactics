# A façade re-export is not a use, and the closure could not tell

- **Status:** Accepted
- **Date:** 2026-09-04
- **Constrains:** ADR-0112 dec. 1, ADR-0135 dec. 11, ADR-0145, ADR-0148, ADR-0149,
  ADR-0154, ADR-0194 dec. 2, ADR-0211 dec. 2 / dec. 4, ADR-0212, ADR-0218

## Context

### The register went quiet, not red

`refactor-loop.md` calls pass 8 the loop's only real safety net. Its residue half
is `tools/closure.py` — everything the declared root set can reach — and
`tools/residue.py`, which gives every unreached file a reason. Extraction #4's
pass 8 opened on a stale `docs/RESIDUE.tsv` with four named drifts, one of them
reading **`no longer unclaimed`** for `src/animation/ResourceHotReload.gd`.

Nothing had claimed it.

[ADR-0211](0211-nothing-preloads-in-so-the-class-name-set-is-the-whole-surface.md)
dec. 2 gives each addon **one** global `class_name` and publishes its whole
surface from that one file as `const <Name> = preload("res://addons/<a>/…")`;
[ADR-0212](0212-a-count-of-one-was-never-the-invariant-the-addons-one-global-is-the-folder-named-facade.md)
extends the shape to the rest. `closure.py` reads every `res://` literal on a
non-comment line as an edge, so those publication tables are an edge set —
**51 across the five in-walk façades**: schema 11, render 1, battlefield 16,
platform 3, sprite rig 20. And every façade is reached, because a root names its
`class_name`: `src/scenarios/NavigatorMain.gd:24` writes
`ExMateriaSpriteRig.AnimationStateController`, which is enough.

**ADR-0211 dec. 4 is what makes this total rather than partial.** A host may
alias a published constant and may NOT `preload` an addon path — so after the
migration the only edge left from a consumer to a member is the member access
`ExMateriaSpriteRig.UnitDisplay`, and a member access is the one shape
`closure.py` has never had an edge for. The publisher acquired every edge the
consumers gave up.

Measured at `134937270`, blinding the sprite rig's façade alone — one file's out
edges, nothing else — moves the register from **31 files / 5,329 lines to 50 /
7,985**: nineteen sprite-rig files, 2,656 lines, on which the walk had stopped
having an opinion. That is not nineteen dead files. It is nineteen files whose
answer was `the façade names it` when the question was `does anything use it`,
and no result reports the difference. It is
[ADR-0148](0148-a-walk-that-does-not-follow-the-refactor-loses-coverage-silently.md)'s
shape one turn further out: there the walk stopped following the refactor's
FILES, here it stopped following its EDGES, and both lose coverage in silence.

### It is not extraction #4's, and it was already load-bearing

`docs/GOALS.tsv` scores extraction #3's goal #3 `met`, and its whole evidence
sentence read, until dec. 6 corrected it, *"docs/RESIDUE.tsv — no unclaimed file under
addons/exmateria_battlefield"*. That register had never been able to say
otherwise. `ExMateriaBattlefield` publishes sixteen members, and one of them —
`addons/exmateria_battlefield/lattice/TerrainFixture.gd`, 292 lines — is named
by nothing outside the addon's own `tests/`, which
[ADR-0194](0194-a-test-belongs-to-the-addon-it-can-run-without-the-game.md)
dec. 2 deliberately keeps out of the subject. It is a shipped test fixture
([ADR-0218](0218-nothing-needed-to-be-faked-the-lattice-test-seam-is-a-fixture-over-the-production-builder.md))
and `test` is the right class — **and `test` is a class goal #3 FAILS on.**
[ADR-0154](0154-goal-1-is-about-decisions-and-goal-3-is-about-orphans.md) dec. 5
is explicit: *"Goal #3's mechanical test now fails on `orphan`, `cluster`, `test`
and `tool` and reports `declined`"*. So the corrected register does not merely
correct a sentence — it flips a score that was never measured. A register
reporting a clean tree it walked with the wrong edge model is what
[ADR-0149](0149-the-ten-goals-are-scored-per-extraction-and-three-of-them-are-not.md)
minted `unscorable` for, and this one did not even get that far: it said `met`.

**One façade per system means this blindness scales with the refactor, not with
the addon.** Five today, ten planned.

## Decision

**1. A façade's `const X = preload("res://…")` line yields no edge.** A façade is
`addons/<name>/<name>.gd` carrying a `class_name` — ADR-0211 dec. 2's mandated
shape, *"the façade file is named after its folder so the guard can assert it is
where it says it is"*, resolved off `plugin.cfg`'s own directory rather than by a
heuristic over any file with a const table.

**2. `<Facade>.X` on a non-comment line yields an edge to X's target**, from
wherever it is written. The claim moves from the publisher to the consumer, which
is where it always was: nothing about `ExMateriaSpriteRig` uses
`ResourceHotReload`. This is the edge ADR-0211 dec. 4 created and no instrument
took up.

**3. A plain `preload("res://addons/…")` from a sibling inside the addon is
untouched.** That is a use, and it is ADR-0211 dec. 2's own arrangement for the
internal members — *"the other 16 `class_name`s are deleted and reached by
`preload` path"*. It is how `CinematicPoseLUT` (named by
`render/UnitDisplay.gd:28`) and `CrystalSpriteCompositor` (named by
`crystal/CrystalSprite3D.gd:28`) stay reached without the publication.

**4. The result is a resolution restoration, not a deletion list.** Register
**31 → 33 rows**, two additions and **no removals**, and both additions classify
— `TerrainFixture.gd` `test`, `ResourceHotReload.gd` `declined` — rather than
`orphan`. Seventeen of the nineteen unanswerable sprite-rig files have a real
consumer once the question is asked properly. The correct reading of the 19 is
`unanswerable`, never `hidden residue`; reporting it the other way would be the
failure ADR-0202 dec. 1 names.

**5. `ResourceHotReload.gd` returns to the register as `declined`, the class it
carried before #744 moved it.** Its only namer outside the addon is
`src/scenes/UnitAnimationViewerScene.gd`, a declined scene, and ADR-0135 dec. 11
holds that declined is not deleted. The round trip is the evidence that dec. 1–3
restore an answer rather than invent one.

**6. `docs/GOALS.tsv`'s extraction-3 goal #3 flips `met` → `open`, and the
evidence sentence says why.** ADR-0154 dec. 5 already ruled that goal #3 fails on
`test`; `TerrainFixture.gd` classifies `test`; the score follows the instrument.
It is worth stating precisely: the score was **not `met` and then broken by this
ADR — it was never measured**, because the register it was read from could not
see the file. ADR-0154 is not re-litigated here. **The remedy is `Battlefield`'s
and it is a decision, not a deletion**: either a production namer is missing, or
the fixture's home is `addons/exmateria_battlefield/tests/` (ADR-0194 dec. 2),
where the walk's subject excludes it and goal #3 closes cleanly. Filed as an open
question, not settled by this pass.

## Consequences

- Pass 9 can score goal #3 for `Sprite Rig` against a register that has entered
  the addon. Before this it could only have repeated extraction #3's sentence.
- `residue.py` needs no change for this — it consumes `closure.unreached_src`.
  **It still counts the publication line as a CLAIM, and that is correct in its
  role**: the closure answers *what uses this*, and `residue.py` answers *who
  names it*, which is why both new rows carry an `addons:1` claim from their own
  façade. Neither row's class turns on it — `TerrainFixture.gd` is `test` on 11
  test claims, `ResourceHotReload.gd` is `declined` on its scene — but a later
  session should not "fix" `residue.py` to match dec. 1. A member whose only
  claim were the publication would read `orphan`, *"no static claim of any
  kind"*, and that would be the honest answer.
- The ceiling is unchanged and still one-sided
  ([ADR-0112](0112-dead-code-is-what-the-root-set-cannot-reach.md) dec. 1,
  `closure.py`'s docstring). A dynamically-built path is invisible to this walk
  before and after, so `orphan` still means *"no static claim found"* and never
  *"provably dead"*.
- **Rejected: teaching `residue.py` to discount the façade instead.** The
  publication would still be an EDGE, so the member would still be `reached` and
  would never enter `residue.py`'s table at all. The defect is in the closure,
  and a second instrument compensating for a first one's wrong edge model is what
  ADR-0148 was written about.
- **Rejected: dropping the façade file from the closure's subject.** It would
  lose the façade's own real edges and make the façade itself residue.

## Prediction

Refutable, and each names the instrument that would refute it.

- **P1 — no removals.** Re-deriving the register with the new edge model removes
  no row that the old model carried. Refuted by any `no longer unclaimed` drift
  in `check_residue.py`'s diff attributable to dec. 1–3.
- **P2 — the other four façades are already clean.** Of the 51 published members,
  only the two named here lose their last claim; the remaining 49 have a real
  consumer. Refuted by a third addition to `docs/RESIDUE.tsv`.
- **P3 — no member reads `orphan`.** Every member whose only claim was the
  publication classifies as `declined`, `test`, `tool` or `cluster`. An `orphan`
  here would mean the migration stranded a file, which is a finding of a
  different kind and belongs to its extraction, not to this ADR.
- **P4 — the shape recurs at the next façade.** Extraction #5 publishes a sixth
  façade; if `closure.py` still carried the old model, its members would enter
  the walk reached-by-publication on the commit that publishes them, with no
  register drift to mark it. This one is not scored here — it is why dec. 1
  resolves the façade off `plugin.cfg` rather than by an addon list.

## Built (2026-09-04)

Built in extraction #4's pass 8, `tools/closure.py`.

- `FACADE_EXPORTS` / `FACADE_SKIP_LINES` are derived once, at import, by reading
  each `addons/*/plugin.cfg`'s own directory for `<name>/<name>.gd` and parsing
  its `const X = preload("res://…")` table. `CNAME2EXPORTS` keys the same table
  by the façade's `class_name`. Nothing is hard-coded: a sixth addon publishes
  itself into this map by existing.
- `_out_edges` skips those lines (dec. 1) and, after the existing `class_name`
  intersect, resolves `<Facade>.<Member>` member accesses to the member's target
  (dec. 2). A `preload` from anywhere else, including inside the addon, is
  untouched (dec. 3).
- `docs/RESIDUE.tsv` regenerated: **33 rows / 5,674 lines**. Two comparisons,
  and they are not the same number, so both are stated. Against the **old edge
  model on today's trunk** (31 rows / 5,329) this is **+2 and −0** — the
  measurement of dec. 1–3. Against the **committed register** (32 rows / 5,348,
  derived at `e326d0b24`, before #744 moved the file) it is **+1**:
  `TerrainFixture.gd` is a true addition, and `ResourceHotReload.gd` is a
  *rename* — `src/animation/` → `addons/exmateria_sprite_rig/resources/`, 47
  lines → 53, `declined` on both sides. `check_residue.py` rc 0.
- **P1 CONFIRMED** — no row the old model carried is gone; the register's one
  disappearing path is `ResourceHotReload.gd`'s old address, and the same file
  is present at its new one. **P2 CONFIRMED** — two additions, not three.
  **P3 CONFIRMED** — `test` and `declined`. **P4 unscored** by construction.
- `docs/GOALS.tsv` extraction-3 goal #3: **`met` → `open`** (dec. 6).
  `score_goals.py` had begun printing *GOALS.tsv disagrees with the code in 1
  place(s)* the moment the register was corrected; it is silent again, now on an
  agreement rather than on a blind spot.

Three unrelated instrument defects were found in the same pass and are recorded
in `docs/EXTRACTION-4-PASS-8-VERIFY.md` rather than here — they share the pass,
not the decision.
