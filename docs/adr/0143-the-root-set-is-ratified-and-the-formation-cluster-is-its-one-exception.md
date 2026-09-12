# The root set is ratified, and the `Formation` cluster is its one exception

The two root sets [ADR-0112](0112-dead-code-is-what-the-root-set-cannot-reach.md)
dec. 3 declares — game scenes and authoring tools — are **ratified as
enumerated**, eight and three. Prologue pass 3 adds nothing to the membership and
removes nothing from it. What it adds is the declaration in the form pass 4's
closure has to consume, and the finding that turned up when the candidacy test
was actually re-run: **one of the eleven roots fails both halves of
[ADR-0135](0135-the-root-set-is-eleven-scenes-and-its-assembler-is-the-script-nothing-calls.md)
dec. 8's pairing**, and ADR-0135's own headline census figure was measured under
the referrer set its dec. 2 exists to reject.

Status: accepted (2026-08-21). Ratifies [ADR-0112](0112-dead-code-is-what-the-root-set-cannot-reach.md)
dec. 3 and [ADR-0135](0135-the-root-set-is-eleven-scenes-and-its-assembler-is-the-script-nothing-calls.md)
dec. 5. Amends ADR-0135 dec. 1 (the candidacy relation), records two exceptions
to its dec. 8, and corrects its Context census and its dec. 7 count.

**All figures measured at trunk `de055dc49`, classifier `classify_blueprint.py`
at `34848f14f`, 2026-08-21**, unless a commit is named.

## Context

### The second root set is *authoring*, not assets

ADR-0112 dec. 3's *"two root sets"* is the ~12 game scenes **and the authoring
tools**; `BLUEPRINT.md` glosses it as *"each assembler is a root set"*, which
makes the real count eleven and *two* a grouping by purpose. ADR-0135 dec. 5
enumerated both halves — eight game, three authoring. **Both are declared.**

There is **no asset root set**, in this ADR or any other, and none is owed. The
gap [ADR-0142](0142-an-asset-belongs-to-the-system-that-owns-its-format.md)
dec. 8 records — *"that test has no asset arm … no mechanized arm at all"* — is a
gap in the **closure**, which is prologue pass 4's work in both registers. Assets
are reached *through* the scene closure; they are not declared beside it. Reading
*"two root sets"* as *"`src/` and `assets/`"* is a misreading worth naming,
because it makes pass 3 look blocked on a decision nobody owes.

### ADR-0135's census reproduces — under the referrer set dec. 2 rejects

Its Context reports *"40 non-test scenes … with `tests/` excluded as referrers
per dec. 4–5, **30 candidates / 10 instanced**."* Rebuilt at its own commit
`a5ccb9fa2` from `git archive`, the scene census matches exactly (29 `assets/`,
9 `tools/`, 2 `src/`). The candidacy split does not — unless `tools/` is counted
as a referrer, and then it reproduces to the file:

| referrer set, at `a5ccb9fa2` | candidates | instanced |
|---|---|---|
| `tests/` excluded, **`tools/` counted** | **30** | **10** |
| `tests/` + `tools/` excluded (dec. 2) | 35 | 5 |
| …and const-indirected paths resolved | 34 | 6 |

The sentence says `tests/` and is silent on `tools/`, so the figure is the
**pre-decision** reading — dec. 2 is the decision that moves five scenes back
into candidacy, and the ADR quotes the number from before it. Its own text
predicts the arithmetic: *"if `tools/` counted, **five** of dec. 3's own declared
roots would lose candidacy."* Five plus five is the ten.

Nothing downstream depends on 30/10 — dec. 5's membership is a scope decision,
not a count — so this is a corrected figure, not a corrected conclusion.

### The candidacy scan could not see a const-indirected path

Dec. 1's worked example needs const resolution to come out right: `Unit.tscn` is
embedded by **zero** `.tscn`, and two of its five `.gd` sites reach it through
`const UNIT_SCENE_PATH := "res://assets/scenes/Unit.tscn"`. The ADR names all
five, so the *example* was resolved. The systematic scan behind 30/10 was not,
and one live site fell through it:

```gdscript
# src/scenarios/NavigatorMain.gd
const FORMATION_SCENE_PATH := "res://assets/scenes/Formation.tscn"     # :321
    var scene: PackedScene = load(FORMATION_SCENE_PATH)                # :327
    var view = scene.instantiate()
    add_child(view)                                                     # :330
    …
    await view.dismissed
    view.queue_free()
```

`Formation` is one of dec. 5's eight game roots. Under dec. 1 as written —
*"a `.gd` `preload`/`load`s it **and adds it to a tree**"* — it is instanced,
and instanced scenes are not candidates, and non-candidates cannot be roots.
This is the same shape as dec. 3's `CombatUI` error, reached by a route dec. 1's
scan could not travel. It is not new code: `FORMATION_SCENE_PATH` landed
**2026-07-31** (`5315ad20e`, #234), three weeks before ADR-0135.

The irony is exact. `Formation` **was** in the instanced ten — for a `tools/`
reason. Dec. 2 correctly restored it, and in doing so hid the `src/` site that
would have flagged it.

### The pairing has two counterexamples, and they are the same cluster

Dec. 8: *"a root scene is one nothing instances, and its assembler is the script
nothing calls."* Tested over all eleven — a caller being another `.gd` outside
`tests/` and `tools/` that `preload`s the script's path or names its
`class_name` as a type, constructor or base class, with string literals stripped:

| root | assembler | callers |
|---|---|---|
| 9 of 11 | — | **uncalled ✓** |
| `Formation` | `src/ui3/formation/FormationScene.gd` | **5 files / 15 sites** — `preload`ed by four, `FormationScene.new()` in two, `extends FormationScene` in `FormationMapHost.gd:2`, and a static-method host (`vitals_view_from_character`, `PIXELS_PER_UNIT`) |
| `FormationDetailTransition` | `src/ui3/formation/FormationDetailTransition.gd` | **2 files / 2 sites** — `NavigatorMain.gd:995` and `GPUArena.gd:637` both call its static `mount_over_map()` |

Both failures are the `ui3/formation` cluster, and both are ADR-0137's *Formation
over the map*: the screen is genuinely dual-role. It runs standalone as
`Formation.tscn`, and it is the base class and mount factory the map-hosted form
is built out of.

### The classifier is not the declaration ADR-0135 says it is

Its closing consequence — *"`classify_blueprint.py` now carries the root-set
declaration … eighteen are a list that pairs with eleven named roots"* — does not
hold. The eighteen `assembler` entries contain **8 of the 11 roots**. The three
missing are booked into a system by the rules that dec. 10 fixed for three
`*Boot.gd` files and stopped:

| root | assembler | booked | lines |
|---|---|---|---|
| `NavigatorMain` | `src/scenarios/NavigatorMain.gd` | `Campaign` (explicit rule) | 1,185 |
| `Formation` | `src/ui3/formation/FormationScene.gd` | `UI` (`src/ui3/` directory rule) | 3,482 |
| `FormationDetailTransition` | `src/ui3/formation/FormationDetailTransition.gd` | `UI` (directory rule) | 2,642 |

Dec. 10 caught the three files whose names end in `Boot`. These three do not, and
the naming convention was doing the work the pairing was supposed to do. The
other direction is intended and stays: seven of the eighteen are declined scenes'
scripts, which dec. 11 keeps classified until they are actually removed, plus
`CompositorAutopilot.gd` under dec. 9a.

## Decision

**1. The two root sets are ratified as enumerated: eight game, three authoring.**
`GPUArena`, `NavigatorMain`, `OpeningScene`, `Formation`, `AllTemplatesFormation`,
`DetailScreen`, `FormationDetailTransition`, `ScenarioPlayer`; `EffectViewer`,
`SequenceViewer`, `TrapViewer`. No membership changes. ADR-0135 dec. 6's nine
declines are **not reopened**, and neither are dec. 2's seven.

**2. The declaration is `docs/ROOT_SET.tsv`, and it is total.** Thirty-one rows —
every non-test, non-`tools/` scene in the tree: **11 `root` · 15 `declined` ·
5 `component`**. `component` is the third status dec. 1 implies and never names:
a scene that is reached by the closure and is not a member of it. The three
statuses partition the census exactly, with no residue and no catch-all, which is
what makes an undeclared scene a failure rather than a default. `tools/` scenes
are excluded by ADR-0135 dec. 7 and get no rows; the guard holds them out.

**3. The disqualifying relation is *composition*, not instantiation.** A scene
fails candidacy if another scene names it in an `[ext_resource]`, or a `.gd`
mounts it as a **component of a scene it does not own**. A scene loaded whole,
mounted as a full-screen overlay and freed when the player dismisses it is a
**navigation transition**, and that is evidence *for* roothood. This is ADR-0135
dec. 2's own inversion — *"a probe that loads a scene and instantiates it whole is
evidence for roothood … only embedding as a child disqualifies"* — promoted off
`tools/`, where it was scoped, to the general rule it always was. **`Formation`
stays a root.** The `NavigatorMain` site is recorded, not waived: it is pinned in
the guard, so a *second* such site is a finding.

**4. Dec. 8's pairing holds for nine of eleven, and the two exceptions are
recorded rather than resolved.** `FormationScene.gd` and
`FormationDetailTransition.gd` are root assemblers that are also libraries.
Whether the library half should be split out of the root script is `UI`'s
extraction work; it is not decided here, and neither script is demoted. The
pairing stays a rule with two documented violations — the state ADR-0135 dec. 9a
already argued makes a rule checkable rather than aspirational.

**5. The three misfiled root scripts are recorded and deferred to prologue pass
4.** Rebooking 7,309 lines across `Campaign` and `UI` moves every published
per-system figure, and [ADR-0131](0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md)
requires instrument changes to land **together, before the baseline**. They are
pinned in the guard, so pass 4 cannot land its batch without unpinning them.
**`FormationScene.gd` is not a straightforward rebooking** — dec. 4 makes it a
library as much as an assembler, and 3,482 lines of `UI` is not obviously
assembly. That is the question pass 4 inherits, stated rather than pre-answered.

> **RESOLVED 2026-08-21 by [ADR-0144](0144-the-instruments-see-the-shaders-the-assets-and-the-closure.md)
> dec. 4 — one rebooking, not three.** `NavigatorMain.gd` (1,185) is booked
> `assembler`: nothing calls it. The other two **stay `UI`**, and the CHECK was
> what over-reached. `FormationScene.gd` is a base class one file `extends` and
> four more read constants and factories off; `FormationDetailTransition.gd` is a
> static-factory library `mount_over_map()`d by two roots, which is verbatim the
> case ADR-0135 dec. 9 had already resolved away from `assembler`. Check 4 now
> asks for an `assembler` booking only where the pairing's second half holds.

**6. The guard is `tools/check_root_set.py`, and its `KNOWN` set is symmetric.**
It re-runs candidacy and the pairing from source on every invocation, and fails
on a new violation **and** on a pinned one that has been fixed without being
unpinned (`FIXED, UNPINNED — remove from KNOWN`), so repairing any of the six is
a two-line change. Six pins: one mount (dec. 3), two calls (dec. 4), three
bookings (dec. 5). Negative-tested in both directions against real edits, not
against synthetic ones. **Pass 4 cleared all three dec. 5 pins (ADR-0144 dec. 4);
`KNOWN` now holds three — the mount and the two calls, which are ratified
findings rather than deferrals.**

**7. ADR-0135's census figures are corrected in place.** Its Context's *"30
candidates / 10 instanced"* is the `tools/`-counted reading and reads **35 / 5**
at its own commit under dec. 2; today, const-resolved, the tree holds **58
non-test scenes (29 `assets/`, 27 `tools/`, 2 `src/`) → 53 candidates / 5
instanced**, of which the 26 outside `tools/` are exactly the 11 roots plus the
15 declines. Its dec. 7's *"the 9 `tools/*.tscn` probe scenes"* reads **27** —
the count is incidental to the decision, which is that none of them is a root.

## Considered and rejected

- **Strike `Formation` from the root set, the way dec. 3's `CombatUI` was
  struck.** Rejected. `CombatUI` is an `[ext_resource]` child two levels down —
  it has no standalone existence. `Formation` is a screen the player opens, its
  own `.tscn`, and the overlay mount frees it on dismissal. Applying the same
  verdict to both would make the test key on the *mechanism* (`add_child`) rather
  than the *relation* (composition), and under that reading every scene a
  navigator can push becomes a component.
- **Overturn dec. 8's pairing on the two counterexamples.** Rejected. Nine of
  eleven hold, and the two that fail are one cluster with one cause. A rule that
  holds 9/11 with both exceptions named and pinned is more useful than no rule,
  and the exceptions are the `UI` extraction's agenda rather than evidence the
  rule is wrong.
- **Reboot the three misfiled scripts now, on dec. 9–10's precedent.** Rejected
  on ADR-0131. Dec. 9–10 were unambiguous misfilings of 151 lines; this is 7,309
  lines and one genuinely open question (dec. 5). ADR-0135 recorded its own
  rebooking as *"the baseline moved a third time, for a third reason"* — a fourth
  time, in the pass whose whole job is ratification, is the failure the
  instrument batch exists to prevent.
- **Declare an asset root set so the closure has two arms.** Rejected: it
  invents a decision nobody owes. Assets are reached through the scene closure,
  and ADR-0142 dec. 8's missing arm is pass 4's walker, not a second declaration.
- **Make the guard decide composition-vs-transition mechanically.** Rejected: it
  cannot. `add_child` is `add_child`. The guard reports every `.gd` mount site and
  the TSV records the adjudicated verdict, which keeps the human call visible
  instead of encoding it as a heuristic that will be wrong quietly.

## Consequences

- **Pass 4's closure has its input.** `docs/ROOT_SET.tsv` names eleven scenes and
  eleven scripts; the walker starts there. It still has to solve what neither
  this ADR nor ADR-0135 does: `src/` holds **487** `preload("literal")`, **48**
  `load("literal")` and **144** non-literal `load()` — bare `load(` plus
  `ResourceLoader.load(`, ADR-0135's method, which reproduces its 371 / 30 / 128
  exactly at `a5ccb9fa2` — so a static closure under-approximates in the `.gd`
  register before it ever reaches assets, where packet paths are built by format
  string.
- **The candidacy method is now a program, and the const gap is closed in it.**
  The defect this ADR found was invisible to a literal-path scan and would have
  stayed invisible to the next one. It is not invisible to
  `check_root_set.py`.
- **The pairing check is a ceiling, and says so.** A caller is found by
  `preload` of the path or by `class_name` in stripped code. A script reached
  through a duck-typed `get_node()` or a `Callable` is not seen — the same floor
  `touch_matrix.py` reports for reaches. Nine uncalled roots is *at most* nine.
- **`godot-learning/CLAUDE.md` → *Test scenes* is now provably wrong, twice.**
  It names `CombatUITest` and `ProgressionTester`; both are `declined` rows, and
  the guard will keep them that way. Fixing that file collides with the long-open
  PR #233 and is left alone deliberately.
- **`assets/scenes/TuneSandbox.gd` is the one `.gd` outside `src/`.** It is a
  declined scene's script and `classify_blueprint.py`, globbing `src/**/*.gd`,
  cannot see it — the same blind spot as the shader walk, on a file the closure
  will call dead anyway.
- **`Audio`'s five dead scene scripts are now mechanically declared dead**, not
  just noted: `AttackSfxTestScene`, `FEDSTestScene`, `SMDTestScene`,
  `SfxBankTestScene`, `SfxStressTest` are all `declined` rows. ADR-0135 measured
  them at 637 lines, 24% of `Audio`. Live input to #313 and to extraction #2.
- **Omission stays invisible**, per ADR-0112's own consequence and ADR-0135's.
  Ratifying a declaration does not test it; only the ballast diff does.
