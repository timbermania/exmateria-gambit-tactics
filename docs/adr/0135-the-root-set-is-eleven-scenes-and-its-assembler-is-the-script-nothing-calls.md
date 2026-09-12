# The root set is eleven scenes, and an assembler is the script nothing calls

The root set declared by [ADR-0112](0112-dead-code-is-what-the-root-set-cannot-reach.md)
dec. 3 is ratified with three amendments and a membership cut. The ratification
also closes the gap ADR-0112 left open: its candidacy test was never written
down as a procedure, and the list it produced disagreed with the one
`classify_blueprint.py` had been carrying all along. They are the same
declaration seen from two sides.

Status: accepted (2026-08-21). Amends [ADR-0112](0112-dead-code-is-what-the-root-set-cannot-reach.md)
dec. 1–4 and tightens [ADR-0134](0134-the-studio-is-an-assembler-and-the-assembler-is-one-file.md)
dec. 2.

> **Ratified, corrected and amended by [ADR-0143](0143-the-root-set-is-ratified-and-the-formation-cluster-is-its-one-exception.md)
> (2026-08-21).** Dec. 5's eleven stand unchanged and dec. 6's nine declines are
> not reopened. Four corrections. **Dec. 1's relation is *composition*, not
> instantiation** — a scene mounted whole as a full-screen overlay and freed on
> dismissal is a navigation transition, which is dec. 2's own inversion promoted
> off `tools/`. `Formation` fails dec. 1 as written: `NavigatorMain.gd:321`
> reaches it through a `const` path and `add_child`s it, live since 2026-07-31
> and invisible to a literal-path scan. It **stays a root**. **Dec. 8's pairing
> holds for 9 of 11** — `FormationScene.gd` (5 files / 15 sites, including
> `extends` and `.new()`) and `FormationDetailTransition.gd` (static
> `mount_over_map()`, called by two other roots) are root assemblers that are
> also libraries; recorded, not overturned. **The Context's *30 candidates / 10
> instanced* is the `tools/`-counted reading** — the pre-dec. 2 figure. It
> reproduces exactly at `a5ccb9fa2`; under dec. 2 the same commit reads **35 / 5**
> and trunk today **53 / 5** of 58 non-test scenes. **Dec. 7's *9 `tools/*.tscn`*
> reads 27.** Finally, the closing consequence — *"`classify_blueprint.py` now
> carries the root-set declaration"* — does not hold: its eighteen `assembler`
> entries contain **8 of the 11 roots**, and rebooking the other three is
> deferred to prologue pass 4 (ADR-0131). The declaration lives in
> [`docs/ROOT_SET.tsv`](../ROOT_SET.tsv), guarded by `tools/check_root_set.py`.

## Context

ADR-0112 dec. 6 holds that choosing a root set is a scope decision, not a
measurement — nobody can compute it. True of *membership*. But candidacy
(dec. 1, "a scene that runs on its own — nothing instances it") **is**
mechanical, and the ADR never recorded how to run it. Two things followed.

**The criterion as written does not pass its own worked example.** Dec. 1 names
`Unit.tscn` as failing candidacy. `Unit.tscn` is embedded by **zero** `.tscn`;
it is instanced by five `.gd` `load()` sites (`ScenarioPlayerScene`,
`BaseRoster`, `EffectViewerScene`, `ProgressionTester`, `TrapViewerScene`). A
scene-embedding-only reading makes `Unit.tscn` a root, which dec. 1 exists to
forbid.

**A rival declaration was already in the repo and nobody had compared them.**
`classify_blueprint.py` books 16 files `assembler`; dec. 3 names ten scenes.
They agree on **four**: `GPUArena`, `OpeningScene`, `EffectViewerScene`,
`ScenarioPlayerScene`. Twelve are assembler-only, six are ADR-only.

Measured 2026-08-21 on trunk (`a5ccb9fa2`), 40 non-test scenes (29 `assets/`,
9 `tools/`, 2 `src/`): with `tests/` excluded as referrers per dec. 4–5,
**30 candidates / 10 instanced**.

## Decision

**1. The candidacy test counts `.gd` loads, not only `.tscn` embeds.** A scene
is *instanced* if a `.tscn` names it in `[ext_resource]` **or** a `.gd`
`preload`/`load`s it and adds it to a tree. Under this reading dec. 1's three
named failures — `Unit`, `PlayerCamera`, `TileCursor` — all fail correctly.

**2. `tools/` joins `tests/` as a non-referrer.** Dec. 4 removed 584 test
scenes from the propping-up business and stopped there; `tools/` is the same
laundering channel. **39** tool scripts instantiate `ScenarioPlayer.tscn` and
**13** instantiate `EffectViewer.tscn`. If `tools/` counted, five of dec. 3's
*own* declared roots would lose candidacy. The inversion is the point: a probe
that loads a scene and instantiates it whole is evidence **for** roothood, not
against — only embedding as a *child* disqualifies.

**3. `CombatUI` is struck from the root set.** `CombatUI.tscn` is an
`[ext_resource]` child node of `PlayerCamera.tscn`, which is itself embedded in
**eight** scenes. It is a component two levels down and fails dec. 1. Dec. 3
listed it as a root; that was an error, not a scope choice.

**4. Dec. 3's "plus the instanced components" is struck.** It contradicts
dec. 1 outright, which exists to say instanced components are never roots. The
closure *reaches* them; that is what closure means, and it is not membership.

**5. The root set is eleven scenes.** Game (8): `GPUArena`, `NavigatorMain`,
`OpeningScene`, `Formation`, `AllTemplatesFormation`, `DetailScreen`,
`FormationDetailTransition`, `ScenarioPlayer`. Authoring (3): `EffectViewer`,
`SequenceViewer`, `TrapViewer`. Dec. 3's "~12 game scenes" was nine names and a
parenthetical; this is the enumeration.

**6. Nine candidates are declined, on the author's reasons.** `SequenceViewer`
is kept because it exercises the whole sprite rig, and `TrapViewer` because it
is the effect viewer for a different particle class — both earn their place as
authoring kit under goal #10. Declined: `ProgressionTester`, `ProjectileTester`,
`DepthDebugScene`, `RangeTileAtlasViewer`, `UnitAnimationViewerScene` (+
`UnitAnimationViewerRoster`), `UnitInfoWindowViewer`, `TuneSandbox`,
`StartActionMenu`, and `FireCastRepro` — the last already declined by dec. 2
while `classify_blueprint.py` booked its script `assembler`, i.e. a root.

**7. The 9 `tools/*.tscn` probe scenes are not roots**, by dec. 4. They are
capture harnesses: evidence about roots.

**8. An assembler is the script nothing calls.** ADR-0134 dec. 2 bounds an
assembler by *shape* — one file, `O(10^3)` lines. The missing clause is the
root-set criterion applied to the script instead of the scene: **a root scene is
one nothing instances, and its assembler is the script nothing calls.** The two
lists are one declaration, and the pairing is what makes it machine-checkable.

**9. `AllTemplatesSeeder.gd` is a library, not an assembler.** It is a
`RefCounted` with a `class_name`, called by two roots
(`FormationDetailTransition.gd:57`, `AllTemplatesFormationBoot.gd:16`), and it
mints an owned `Character` per catalogue variant. It books to
`Character Catalogue`.

**9a. `CompositorAutopilot.gd` is the one recorded exception, and it stays.**
It is referenced by **11** files across seven systems, so it fails dec. 8 on its
face — but [ADR-0129](0129-the-fold-is-renders-and-a-producer-keeps-its-shader.md)
already considered it, split it in the decision, and booked the whole file on
its *identity* (a per-scene wiring autoload) with the impurity recorded in the
classifier source rather than hidden. That reasoning stands; this ADR does not
overturn it. The exception dissolves when the split lands, and until then dec. 8
is a rule with exactly one documented violation — which is the state that makes
a rule checkable rather than aspirational.

**10. Three assemblers are misfiled as `UI` by a directory rule.**
`DetailSceneBoot.gd` (70), `AllTemplatesFormationBoot.gd` (26) and
`StartActionMenuBoot.gd` (55) are wiring files caught by `("src/ui3/", "UI")`.
The `*Boot.gd` convention already names the role. An assembler booked inside a
system leaves with that system at extraction, and an addon cannot ship a root
scene — the same defect class ADR-0134 found in `src/effects/studio/`.

**11. The declaration is ratified; the deletion is pass 5's.** A declined scene
stays classified until it is actually removed. Only the misfilings in dec. 9–10
are corrected in the classifier now, because they are classification errors
rather than deletions.

## Consequences

- **The decline costs ~4,229 lines at the first hop**, before closure: 2,291 in
  the nine declined entry-point scripts, 971 in dec. 2's original seven, 887 in
  three orphaned debug panels (`ProgressionDebugPanel` 421,
  `UnitAnimationViewerPanel` 430, `ProjectileDebugPanel` 36), 47 in
  `ResourceHotReload.gd` — scene-local to `UnitAnimationViewerScene`, its sole
  instantiator — and 33 in `TuneSandbox.gd`. Pass 5's closure will find more.
- **`Audio` carries 637 lines of already-dead scene scripts** — five of its
  twelve files, 24% of its 2,671 lines, are entry points for scenes dec. 2
  declined in August 2026 and nobody removed. Live input to #313.
- **A known drop, recorded now**: `DepthMode.gd` documents its sub-bucket
  nudges as "tuned once in `DepthDebugScene`". The constants survive; the
  instrument that produced them does not. Re-tuning them later means rebuilding
  the rig.
- **ADR-0112's Consequences figures are a date splice, not a lost method.** At
  `f8f3041b3` (2026-07-12 — the same commit behind the 321 denominator
  [ADR-0131](0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md)
  re-dated) the greps reproduce **exactly**: 124 `preload("literal")`, 16
  `load("literal")`, and 65 non-literal `load()` — that last being bare `load(`
  (55) plus `ResourceLoader.load(` (10), which is why it had resisted
  re-derivation. On trunk 2026-08-21 the same method reads **371 / 30 / 128**.
- **The "13 files referenced by nothing else" does not reproduce and should not
  be re-stated.** Tested at its own commit under six referrer sets, with and
  without `class_name` resolution and `project.godot`: 2, 25, 45, 158, 197, 233
  — never 13. Four of the five files it names are scene scripts referenced only
  by their own `.tscn`, so its referrer set excluded scene script attachment,
  but no combination lands on 13. Unlike its three neighbours, re-dating does
  not recover it. It is a Context motivation, not a decision, and nothing
  downstream depends on it.
- **The baseline omits every shader.** ADR-0131 dec. 1 declares the unit as
  hand-written `.gd` + shaders across `src/` **and** `assets/`;
  `classify_blueprint.py` globs `src/**/*.gd` only, so **4,304 lines across 70
  `.gdshader` files** (48 in `assets/`, 22 in `src/`) and one stray
  `assets/scenes/TuneSandbox.gd` are invisible. That is +3.0% on the declared
  141,831, landing mostly on `Render` (1,755). Pass 6 should close this before
  it takes the baseline, or ADR-0131 should narrow its unit to match.
- **The baseline moved a third time, for a third reason.** Rebooking under
  dec. 9–10 takes `touch_matrix.py` from **360 to 358** cross-system edges —
  `assembler` is not a system, so edges through it do not count, and moving
  three `*Boot.gd` files out of `UI` removed two. `Character Catalogue` goes
  9/1,219 -> **10/1,402**, `UI` 57/19,083 -> **54/18,932**, `assembler`
  16/6,906 -> **18/6,874**; the total holds at 470 / 141,831, as a pure
  rebooking must. Measured both ways against a shadow tree carrying the
  pre-change classifier. ADR-0131 amended in place.
- **`classify_blueprint.py` now carries the root-set declaration.** Sixteen
  assembler entries were a list nobody had reconciled with ADR-0112; eighteen
  are a list that pairs with eleven named roots. Ratifying prose produced a
  *program*, which is the only form in which pass 5 can consume it.

- **Omission stays invisible**, per ADR-0112's own consequence. Nine declines
  are nine bets; the ballast diff is the only check on them.
