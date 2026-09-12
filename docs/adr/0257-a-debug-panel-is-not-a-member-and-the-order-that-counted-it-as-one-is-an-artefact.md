# A debug panel is not a member, and the order that counted it as one is an artefact

[ADR-0243](0243-the-src-data-tier-is-a-third-addon-and-the-split-the-selection-assumed-does-not-exist.md)
dec. 10 ordered `TuneField` and `BaseDebugPanel` as extraction #6 on share:

```
It stays #6 for two reasons that are not cost. First, share: `src/data/` is 43.7%
against `src/debug/`'s 27.1%, and after this pass `src/debug/` is **202 of the
remaining 372 lines — 54.3%**, so it becomes the unambiguous next move rather than a
contested one.
```

**The measurement is right and the share is an artefact.** Every one of the lines that
share is computed over sits in a `src/debug/*DebugPanel.gd` file — a panel reaching its
own base class and its own field widget. `classify()` books a file to the system it
*consumes* (ADR-0243 dec. 3), so `RosterViewDebugPanel.gd` is booked to
`Character Catalogue`, and the panel's reach is then read as the catalogue's portability
debt. It is not: it is the debt of the host's debug window.

That was never wrong arithmetic. It is a question nobody had asked — **what counts as a
member** — and answering it re-orders the queue. Under the rule below, extraction #6 is
`Character Catalogue`, which opens at **zero arm-7 lines over ten files**, the cleanest
opening in the corpus; `Battlefield` opened at 9 and `Sprite Rig` at 6. `TuneField` and
`BaseDebugPanel` are named on **two lines of code** outside `src/debug/` and are not an
extraction at all.

Status: accepted (2026-09-07). This is ADR-0126's pass 1 for extraction #6, re-run
because [#945](https://github.com/timbermania/fft-monorepo/issues/945) discharged the
membership its predecessor was priced against. Reads
[ADR-0126](0126-every-system-pass-audits-before-it-designs.md) for the pass split,
[ADR-0035](0035-debug-ui-is-a-separate-os-window.md) for what a debug panel is,
[ADR-0223](0223-a-reach-has-a-bucket-and-an-address-and-goal-5-only-ever-read-the-bucket.md)
for arm 7, [ADR-0139](0139-the-shared-kernel-is-enumerated-by-the-schema-list.md) dec. 4b
for the autoload veto, and
[ADR-0175](0175-a-port-answers-arm-1-and-not-arm-2-and-the-debug-residue-was-print-statements.md)
dec. 2 /
[ADR-0187](0187-the-port-is-two-signatures-and-sixteen-of-the-seventy-eight-were-already-inside-it.md)
for the port that answers it. **Supersedes nothing.**
[ADR-0243](0243-the-src-data-tier-is-a-third-addon-and-the-split-the-selection-assumed-does-not-exist.md)
stays accepted and decs. 1–9 and 11–13 stand unchanged; only dec. 10's *inference* is
recorded here as expired, and dec. 10's own numbers reproduce. Re-prices
[ADR-0241](0241-unitprogression-is-the-catalogues-by-ownership-and-src-datas-by-address.md)
dec. 5, whose four named obstacles #945 discharged. Tickets: re-scopes
[#946](https://github.com/timbermania/fft-monorepo/issues/946) and files the
`Character Catalogue` build.

## Context

### Everything here is on this branch merged with `origin/main` `a99924f14`, with one instrument

`tools/arm7_membership.py`, calibrated three ways before ADR-0243 believed it. The
membership builder that groups the tree by system is new for this pass and is calibrated
against `tools/classify_blueprint.py`'s own `FILES`/`LINES` column, **row for row, all
nineteen buckets exact** — so a disagreement between this table and the shipped
blueprint report is a defect in one of them, not a judgement call.

### The table, as classified and under the rule

`assembler` is excluded and dec. 6 states the ground. Already-extracted remnants
(`Battlefield` 1 file, `platform` 3) are shown for completeness.

| system | files | lines | A7 names | A7 lines | → files | lines | A7 n | A7 l | arm 2 | arm 6 | autoloads inside |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Character Catalogue | 14 | 2,224 | 4 | 32 | **10** | **1,581** | **0** | **0** | 0 | 7 | `CharacterCatalog` |
| infrastructure | 3 | 258 | 1 | 2 | 3 | 258 | 1 | 2 | 0 | 1 | `AssetManifest`, `UserSettings` |
| Effects | 191 | 58,124 | 3 | 21 | 188 | 57,568 | 1 | 3 | 2 | 18 | four |
| Audio | 14 | 1,930 | 2 | 3 | 12 | 1,536 | 3 | 3 | 12 | 8 | four |
| Debug | 21 | 3,861 | 1 | 2 | 13 | 2,829 | 3 | 7 | 66 | 0 | four |
| Battle | 64 | 23,487 | 10 | 44 | 59 | 22,576 | 8 | 17 | 16 | 16 | — |
| Campaign | 10 | 1,727 | 7 | 57 | 8 | 1,366 | 4 | 42 | 0 | 3 | — |
| Cutscene | 59 | 17,826 | 18 | 103 | 50 | 15,963 | 15 | 51 | 54 | 14 | three |
| UI | 141 | 43,835 | 17 | 131 | 133 | 42,716 | 20 | 64 | 108 | 30 | `UI3Registry` |

Systems-only arm-7 total: **395 → 189**.

### The like-for-like comparison, all buckets

| | arm-7 lines | delta |
|---|---|---|
| as classified today | 686 | — |
| after #946 (the two files move) | 484 | −202 |
| under this ADR's rule, moving nothing | **480** | **−206** |
| the rule **and** #946 | 472 | −214 |

**The rule alone beats the extraction, and #946's entire remaining contribution is eight
lines.** Those eight are real; they are not an extraction.

### What a shipped addon actually contains, which is the rule's evidence

`addons/exmateria_battlefield/debug/MapGridOverlay.gd` (a `Node3D` line-mesh overlay),
`addons/exmateria_battlefield/debug/grid_overlay.gdshader`,
`addons/exmateria_render/debug/depth_debug.gdshader`,
`addons/exmateria_sprite_rig/install/RigDebug.gd`. **Addons do ship debug code**, and any
rule phrased as *"debug files are not addon material"* is falsified by this list. What no
addon ships is a **panel**: zero addon files extend `BaseDebugPanel` or name `TuneField`
in code — both greps hit only docstrings. The distinction is in-world visual versus
host debug-window UI, and ADR-0035 already drew it.

### One citation in dec. 10 does not resolve, and this pass nearly propagated it

ADR-0243 dec. 10 states: *"ADR-0234 built `TunePort` in `exmateria_platform` for the
autoload half."* **ADR-0234 did not build it.** It names `TunePort` six times and every
one treats it as pre-existing — *"a `RefCounted` beside `TunePort`"*, *"`tests/
TunePortTest.gd` gains the present and absent arms for the **new verb**"* — and it cites
ADR-0202 dec. 7 for `TunePort.gd:78`'s conformance, which requires the file to already
exist. The port's shape is ADR-0175 dec. 2 and its build is ADR-0187, which ADR-0068:135
attributes correctly.

This is recorded rather than fixed because it is the second half of the blind spot
ADR-0243 dec. 13 named and left open: `check_adr_anchors` excludes `docs/adr/` from its
citation scan, so an ADR-to-ADR attribution is checked by nobody. The claim was repeated
into #946's body and into this pass's own working notes before anyone opened ADR-0234.

### The numbers were re-taken once, and the conclusion did not move

They were first taken on `4c5633231`; the branch then merged 200 commits of `origin/main`
and every headline figure was **re-taken rather than carried**. Two moved materially --
`UI` 16 names to 17, and the panel census 42 files to 41 -- and
`tools/test_arm7_membership.py` **failed on the first**, which is exactly what pinning a
number to the tree is for. Nothing that decides anything moved: the catalogue still reads
arm-7 zero, the rule still beats the extraction (-206 against -202), and #946 still buys
eight lines.

### Who instantiates the panels

`src/scenarios/NavigatorMain.gd:483,498` and `src/scenes/GPUArena.gd:1201`, through
`DebugOverlay.Category.ROSTER`. Both are scene-boot entry points. **No system
instantiates the panels that inspect it**, which is why booking them to that system
prices a coupling that does not exist.

## Decision

**1. A `BaseDebugPanel` subclass is not a member of any extraction, and the base class
is not either.** It is host debug-window UI (ADR-0035), it is instantiated by the host's
scene-boot entry points rather than by its subject, and no shipped addon contains one.
The rule is on the **`extends` chain**, transitively, resolving both the `class_name` and
the `res://` spelling — **not** on the directory. That distinction is load-bearing:
`src/debug/RosterDebugView.gd` is a helper, not a panel, and stays; `src/ui3/testing/
CombatUIDebugPanel.gd` is a panel outside `src/debug/` and goes. 41 files match, 40 of
them in `src/debug/`.

**2. Extraction #6 is `Character Catalogue`.** Ten files, 1,581 lines, **arm 7 zero,
arm 2 zero, arm 6 seven**. No other candidate is within an order of magnitude:
`Battle` 17 lines, `Campaign` 42, `Cutscene` 51, `UI` 64. `Battlefield` was selected at
9 arm-7 lines and `Sprite Rig` at 6, so this is the cleanest opening the corpus has had.

**3. The rule is not a discount and must never be quoted as one.** Dropping a panel can
**convert an internal name into an outbound one**, because the panel was the declaring
file of a name its siblings reached. `UI` goes 17 names → **20** while its lines go
131 → 64; `Audio` 2 → 3; `Debug` 1 → 3. The line count falls and the name count can
rise. `tools/test_arm7_membership.py::PanelExclusion::test_dropping_panels_is_not_
uniformly_a_reduction` pins that arm precisely so nobody re-sells the rule as a saving.

**4. #946 is not an extraction, and is re-scoped rather than closed.** Outside
`src/debug/`, `TuneField` and `BaseDebugPanel` are named on two lines of code —
`src/audio/AudioHostAdapter.gd:52` (`TuneField.add(...)`) and
`src/ui3/testing/CombatUIDebugPanel.gd:2` (`extends BaseDebugPanel`). Everything else in
a raw grep is a comment or a docstring, with one near-miss worth naming: `src/core/Tune.gd:22`
holds `"/TuneField.gd"` inside a list of path suffixes, which is a string literal and not
a reference to the class. Two lines is a host tidy. It keeps its ticket
because those two lines are real and because ADR-0241 S2's question deserves a recorded
answer, but it **loses its position in the extraction order**.

**5. ADR-0243 dec. 10's measurement stands; its inference is expired, and one of its
citations does not resolve.** Re-run today, the
two files still carry zero arm-7 names between them and `TuneField` still has exactly one
dependency, the `Tune` autoload — 39 lines now, 35 when dec. 10 measured it. Nothing in
that decision was miscounted. What it could not see is that the *denominator* was
computed over memberships containing panels, and dec. 10 said so itself without drawing
the consequence: *"dec. 8's arm-7 table could not see the cost."* ADR-0243 is not
superseded and its other twelve decisions are untouched. Its `TunePort` attribution is
corrected in Context above; ADR-0234 added a verb to a port ADR-0187 had already built.

**6. `assembler` is excluded from candidacy, and the ground is that it is the host.** It
is the single largest arm-7 item — 94 names / 291 lines, 42% of the 686 — so leaving it
unexplained would look like dropping the inconvenient row. Its members are
`src/scenes/*`, `*Boot.gd`, `NavigatorMain.gd`, `WorldMapScene.gd`: application entry
points. An entry point is what **composes** addons; it is the host by definition, and an
addon that contained one would invert the dependency the package exists to create.

**7. An autoload inside a membership is design work, not disqualification.**
`CharacterCatalog` is an autoload at `src/characters/CharacterCatalog.gd`, reached on
**35 host lines**, and an addon cannot ship `project.godot` entries. ADR-0139 dec. 4b is
a veto on an autoload being *kernel*; read as a veto on candidacy it would disqualify
`Debug`, `Effects`, `Audio`, `Cutscene` and `UI` as well, which is every remaining system
but two. `TunePort` is exactly this shape at exactly this size —
ADR-0175 dec. 2 settled it and ADR-0187 built it. The selection **names and prices** it;
the build rules it.

**8. `AllTemplatesSeeder.gd` travels with the catalogue.** Both readings are arm-7 clean
(9 files / 1,298 lines without it, 10 / 1,581 with), so the instrument does not decide
it. `tools/classify_blueprint.py:289` is a hand pin booking that one `src/scenarios/`
file to the catalogue, and its docstring backs the pin: it *"Mints an owned `Character`
for every catalogue variant — the roster behind the formation 'show all templates' view
(ADR-0081)."* Reversing a recorded ownership judgement needs its own argument and this
pass has none. It costs three arm-6 lines.

**9. The rule ships as `--exclude-panels` on the existing instrument, not as a guard.**
`tools/arm7_membership.py` grew `panel_subclasses()` and the flag; six seed-red tests in
`tools/test_arm7_membership.py::PanelExclusion` hold both arms — that the exclusion
*changes* the catalogue's answer (4/32 → 0/0), and that the detector is neither a path
prefix nor a returns-everything stub. A `check_*.py` would be **vacuous**: no addon ships
a panel today, so the guard would have nothing to fail on, which is the arm this corpus
has written by accident more than once. The flag **prints what it dropped, by name** — a
silent exclusion reads exactly like a clean membership.

**10. What this does NOT decide.** Where the catalogue addon lands, its façade shape, how
`CharacterCatalog`'s 35 lines are ported, and whether the five booked panels follow it in
any form. Pass 1 selects; pass 3 designs (ADR-0126). Nor does it re-open `Effects`
(ADR-0241 dec. 6) or the systems dec. 7 rejected — their numbers moved under the rule but
none moved into contention.

## Considered alternatives

**Exclude all of `src/debug/**` rather than panel subclasses.** Simpler, and it reaches a
lower total (482 against 491). Rejected: it is falsified by the shipped addons' own
`debug/` directories, and it would drop `RosterDebugView.gd`, a helper the catalogue's
panels genuinely share. A rule that is right for the wrong reason cannot be reasoned from
next time.

**Keep #946 as extraction #6 and take `Character Catalogue` as #7.** Rejected on dec. 4's
number: the extraction buys eight arm-7 lines beyond the rule. Ordering an eight-line
move ahead of a zero-debt system inverts the queue's own criterion.

**Supersede ADR-0243.** Rejected. Its decs. 1–9 are what #945 shipped and nothing here
contradicts them. Superseding to correct one inference would throw away twelve sound
decisions and force every citation of them to be re-pointed.

**Amend ADR-0243 with a dated section.** Rejected: the corpus allows at most one dated
section per ADR, and this pass asks a question — what counts as a member — that ADR-0243
never asked. One ADR, one question.

**Treat the autoload as disqualifying and select `Battle` (16 lines).** Rejected by
dec. 7: applied consistently that veto empties the candidate list, and `Battle` is 61
files / 22,490 lines against the catalogue's 10 / 1,530.

## Consequences

- The extraction queue is re-ordered for the first time on a **membership** argument
  rather than a debt argument. Any future selection that quotes a share must say which
  membership rule produced it.
- Every arm-7 figure in ADR-0241 dec. 7/8 and ADR-0243 dec. 9 was taken without the rule.
  They are not wrong as taken, but they are **not comparable** to a post-rule number, and
  the ADRs that own them keep their figures.
- `#946` leaves the extraction order. Nothing else depends on it.
- The catalogue build inherits a named, priced obstacle (dec. 7) instead of an unstated
  one — dec. 5 of ADR-0241 rejected the system twice without ever mentioning the autoload.

## Soft spots

- 🔴 **The rule's evidence is an absence, and an absence is the weakest evidence there
  is.** "No shipped addon contains a `BaseDebugPanel` subclass" is true of three addons
  built before anyone asked the question. It is consistent with the rule being right and
  equally consistent with nobody having wanted a panel in an addon yet. The instantiation
  census (dec. 1) is the stronger half and it is the one to attack: if a future system
  *does* instantiate its own inspector panel, this rule prices it wrong and should be
  re-opened rather than worked around.
- 🔴 **`arm7_membership.py` is one arm of seven.** The catalogue's zero is an arm-7 zero.
  Arm 2 reads zero and arm 6 reads seven, both by hand from the same instrument's
  `--all`, and the remaining four arms are not measured here at all. **The first real
  `check_addon_portability.py` run after the folder exists is the witness and the number
  can only go up** — that warning is ADR-0243's and it applies unchanged.
- **`--exclude-panels` has no consumer in the guard.** The flag exists for selection; the
  shipped guard still reads whatever is in the real directory. If a panel is ever moved
  into an addon, this rule and that guard will disagree and the guard wins.
- **Dec. 8 is a judgement, not a measurement.** The instrument is silent on whether
  `AllTemplatesSeeder.gd` belongs, and the pin it defers to is one line in a Python
  table with no test behind it.
