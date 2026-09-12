# Extraction #8 is `UI`, selected against the metric, and the matrix that selects prints 4 of its 127 inbound lines

The selection instrument reports `UI` at **148 files / 49,054 lines, arm 7 = 16 names /
132 lines** — a ratio of **0.269%**, which is the **fifth-best** reading in the table and
not a candidate any metric would put forward. `Effects` reads 0.041%, `Debug` 0.056%,
`Battle` 0.122%, `Audio` 0.155%. `UI` is selected anyway, and for a reason that is not a
reading: it is the system the user intends to **reuse in another project**, which is goal
#5's claim in its strongest form. [ADR-0213](0213-extraction-4-is-sprite-rig-and-its-widest-inbound-name-is-a-generated-enum.md)
is the precedent for recording that an override happened rather than dressing it as a
measurement, and dec. 1 records it.

**The second selection reading was taken off an instrument that prints 3% of it, and the
ADR that ruled that harmless ruled it at 2 lines.**
[ADR-0141](0141-extraction-1-is-render-and-the-clean-five-is-retired.md) names *inbound
concentration, read by symbol* as one of the three readings that choose a system, and the
instrument is `tools/touch_matrix.py`. Its printed `UI` column reads **4 lines over 2
names** — by a wide margin the most isolated column in the matrix, and the reading that
would make `UI` look like the cleanest seam ever selected. Measured off the same run's own
cache, `UI`'s inbound is **127 lines over 46 names**. The mechanism is not new and it is
not this ADR's discovery: `matrix()` loops `for a in SYS for b in SYS` over the eleven
blueprint systems, `classify()` books files to nine further buckets, and
[ADR-0147](0147-renders-seam-is-the-fold-bracket-and-one-port.md) →
[ADR-0148](0148-a-walk-that-does-not-follow-the-refactor-loses-coverage-silently.md) dec. 2
both name it in the same sentence — *"`assembler` is not one of the eleven systems the
matrix prints or sums"* — and both **price it at 2 lines and rule it a zero.** At `UI` it
is **123**, and tree-wide the unprinted half is **696 lines against 656 printed**. What is
new here is not the blind spot; it is that its ruling has expired at 348× the scale it was
ruled on, with `UI`'s selection reading standing on it (dec. 4).

**And the hidden half splits almost exactly on the extraction's largest design question.**
65 of the 127 lines, over 24 of the 46 names, come from **five files that live inside
`src/ui3/` and `src/world_map/`** and are booked `assembler` — the screens' own boot
scripts, which are five of the six `game` roots `UI` ships. The other 62 lines over 25
names are genuinely external, and **24 of those 62 are one file**,
`src/scenes/GambitBattle.gd`. If the addon ships the screens, its published inbound surface
is **62 lines / 25 names**; if the host keeps them, it is **127 / 46**. Pass 1 prices both
sides and decides neither (dec. 5).

Status: accepted (2026-09-12). This is
[ADR-0126](0126-every-system-pass-audits-before-it-designs.md)'s **pass 1** for extraction
#8, run while extraction #7 (`Effects`) is mid-flight in another session
([#1214](https://github.com/timbermania/fft-monorepo/issues/1214) is its pass 5). Reads
[ADR-0110](0110-systems-extract-outward-into-addons.md) for the unit of work,
[ADR-0141](0141-extraction-1-is-render-and-the-clean-five-is-retired.md) for the three
selection readings, [ADR-0213](0213-extraction-4-is-sprite-rig-and-its-widest-inbound-name-is-a-generated-enum.md)
for how an override is recorded,
[ADR-0243](0243-the-src-data-tier-is-a-third-addon-and-the-split-the-selection-assumed-does-not-exist.md)
dec. 3 for book-by-consumer,
[ADR-0257](0257-a-debug-panel-is-not-a-member-and-the-order-that-counted-it-as-one-is-an-artefact.md)
for what a member is — **and amends its stated rationale** (dec. 3) —
[ADR-0262](0262-the-alias-route-hid-forty-nine-lines-and-the-almanac-reads-as-a-system-only-because-classify-books-by-consumer.md)
dec. 6 for the autoload precedent,
[ADR-0286](0286-extraction-7-is-the-effects-runtime-and-the-studio-that-is-seventy-percent-of-the-bucket-is-a-root-set-that-stays.md)
for the prefix blind spot and the *root set that stays* shape,
[ADR-0147](0147-renders-seam-is-the-fold-bracket-and-one-port.md) and
[ADR-0148](0148-a-walk-that-does-not-follow-the-refactor-loses-coverage-silently.md) dec. 2
for the prior record of dec. 4's blind spot and the pricing this ADR retires, and
[ADR-0131](0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md)
for why every number here is re-taken rather than carried. **Supersedes nothing.** Amends
ADR-0257's reasoning without changing its rule, and **retires ADR-0148 dec. 2's pricing of
the matrix print loop** without disturbing anything else in that ADR. Tickets: files the extraction #8 selection,
and hands pass 2 the five items in *Soft spots*.

## Context

### Everything here is re-measured on `loop/extraction-8-ui` @ `174a37449`, 0 commits behind `origin/main`

The handoff that opened this session carried a table it correctly marked *"RE-DERIVE
THESE. Do not carry them."* Every figure in it reproduces on this tree, row for row,
including the bucket decomposition. What did **not** survive re-derivation is two of its
four stated findings, and both are corrected below: the panel drop moves the arm-7 figure
in a direction it did not predict (dec. 3), and the autoload question it names is an order
of magnitude smaller than the one it does not (dec. 7).

### The bucket, decomposed — `classify_blueprint.py`, unmodified

| directory | files | lines | share |
|---|---:|---:|---:|
| `src/ui3/` | 112 | 41,714 | 83.7% |
| `src/world_map/` | 13 | 3,725 | 7.5% |
| `src/debug/` | 11 | 2,586 | 5.2% |
| `assets/shaders/` | 11 | 839 | 1.7% |
| `addons/exmateria_almanac/` | 6 | 801 | 1.6% |
| `src/scenes/` | 1 | 190 | 0.4% |
| **total, as classified** | **154** | **49,855** | |

(`selection_sweep.py`'s 148 / 49,054 counts host files only; the six `addons/` files are
the difference.)

### Six candidate memberships, same tree, one instrument

`tools/arm7_membership.py`, calibrated three ways (ADR-0243 dec. 11). `--all` is the
five-shape reading beside arm 7, because arm 7 is a `class_name` predicate and cannot see
an autoload.

| # | membership | files | arm 7 | all five shapes |
|---|---|---:|---|---:|
| **M1** | as classified | 154 | 16 names / **132** lines | 323 |
| **M2** | M1, panels out (ADR-0257) | 146 | **19** names / **65** lines | 241 |
| **M3** | M1, almanac out | 148 | 16 names / 132 lines | 323 |
| **M4** | almanac **and** panels out | **140** | **19** names / **65** lines | **241** |
| M5 | M4 + panels back, `world_map` out | 135 | 15 names / 110 lines | 293 |
| M6 | M4, `world_map` out | 127 | 17 names / 41 lines | 209 |

**M1 and M3 are identical to the line.** The six `addons/exmateria_almanac/` files are
**arm-7 inert** — they contribute zero on every shape — so dropping them costs nothing on
any arm and is correct on the rule rather than on the number (dec. 2).

**M2 is where the surprise is.** Dropping the panels halves the lines and **raises the
names**, 16 → 19 (dec. 3).

### The five files that live inside `UI` and are booked `assembler`

| file | inbound lines into `UI` |
|---|---:|
| `src/world_map/WorldMapScene.gd` | 40 |
| `src/ui3/detail/StartActionMenuBoot.gd` | 13 |
| `src/ui3/detail/DetailSceneBoot.gd` | 9 |
| `src/ui3/formation/AllTemplatesFormationBoot.gd` | 2 |
| `src/ui3/formation/FormationDevBoot.gd` | 1 |
| **subtotal** | **65 over 24 names** |

against **62 lines over 25 names** from files outside `UI`'s directories, of which
`src/scenes/GambitBattle.gd` alone carries 24.

### The whole-tree reference count — the cost that is in no matrix

Measured over the whole tree rather than `classify()`'s file set, because ADR-0157 →
*Soft spots* S3 is the standing lesson that four fifths of a reference count lives in
`tests/`.

| shape | production | `tests/` + `tools/` | total |
|---|---:|---:|---:|
| `class_name` | 119 | 1,965 | 2,084 |
| `res://` path | 79 | 326 | 405 |
| autoload `UI3Registry` | 0 | 73 | 73 |
| **total** | **198** | **2,364 (92.3%)** | **2,562** |

`UI` declares **103** `class_name`s; 41 are reached by name from production, 92 from
`tests/`+`tools/`, and 8 are reached from nowhere outside the membership at all. The
widest single name is **`UI3Element` at 419 lines** — the element base class, which is
exactly the machinery half of the *screens or machinery* question.

**2,562 is the largest figure this method has recorded**: 2.1× `Effects`' 1,117
(ADR-0286) and 9× `Battlefield`'s corrected 284 (ADR-0157). Pass 5 prices it; pass 1
records it so nobody discovers it in rebase.

Positive control on that census, because a word-match over raw text is exactly the
instrument ADR-0131 warns inflates by half: `UI3Element`'s 419 stripped lines check
against a raw `grep -rn '\bUI3Element\b'` of **390 in `tests/` plus 33 in production
`src/`** = 423, the 4-line difference being the docstrings `strip_noncode` removes. The
count is references, not prose.

### What `UI` reaches, by target — `touch_matrix.py`'s own cache, M1

| target | lines | names | widest name |
|---|---:|---:|---|
| `platform` | 155 | 4 | **`Tune` 127** |
| `Debug` | 99 | 6 | `TuneField` 72 |
| `infrastructure` | 52 | 1 | `ExMateriaAlmanac` 52 |
| `schema` | 34 | 2 | `ExMateriaSchema` 30 |
| `Battle` | 24 | 12 | `UnitSpawn` 6 |
| `Campaign` | 17 | 1 | `WorldMapProgress` 17 |
| `Cutscene` | 13 | 4 | `CampaignRevealPass` 7 |
| `Character Catalogue` | 12 | 2 | `CharacterCatalog` 8 |
| `Audio` | 6 | 1 | `SfxRouter` 6 |
| `content` | 6 | 3 | `EntdBattle` 2 |
| `Sprite Rig` | 5 | 1 | `ExMateriaSpriteRig` 5 |
| `DELETE` | 4 | 1 | `EventBus` 4 |
| `generated` | 4 | 2 | — |
| `Battlefield` | 2 | 1 | `ExMateriaBattlefield` 2 |
| **total** | **433** | | |

`platform`, `schema` and `Debug` are non-counting sinks for the outbound reading
(ADR-0141), which leaves **79 lines over 22 names into the ten other systems — 0.158% of
49,855**, against `Battlefield`'s 0.121% and `Sprite Rig`'s 0.112%. On *outbound* `UI` is
an ordinary candidate. On *inbound* it is the widest surface the method has selected.

## Decisions

### 1. Extraction #8 is `UI`, and the selection metric is **overridden, not met**

`UI` is fifth on the arm-7 ratio (0.269%) behind `Effects` 0.041%, `Debug` 0.056%,
`Battle` 0.122% and `Audio` 0.155%, and it is the **largest unextracted system in the
tree** at 20.5% of all classified lines. Nothing in ADR-0141's three readings selects it.

It is selected on **intended reuse** — the user's stated reason, *"it seems like something
which would actually be useful in another project"* — which is goal #5's claim stated
directly rather than inferred from a ratio. ADR-0213 dec. 4 established that a gate can be
*overridden* and that saying so is what lets pass 9 score the decision; this is the second
firing of that, and the first where the overriding reason is not itself a measurement.

**Pass 9 scores this.** The question it must answer is not *"was the ratio good"* — it was
not — but *"did the stranger rig stand up, and did the inbound surface come down to the 62
that dec. 5 prices."*

### 2. The membership is **M4 — 140 files**: the classified bucket, minus the six almanac files, minus the eight panels

The six `addons/exmateria_almanac/` files are booked `UI` because `classify()` books a file
to the system it **consumes** (ADR-0243 dec. 3) and they name `UI` names. They are an
**inbound** signal and they are already inside a published addon. M1 ≡ M3 to the line
proves the drop is free on every arm, so this is decided on the rule and confirmed by the
instrument rather than argued from it.

The eight `BaseDebugPanel` subclasses drop under ADR-0257. This is its **third** firing —
#6, then #7 (ADR-0286), now #8 — and the first that requires an amendment (dec. 3).

`world_map` **stays in** for now. M5/M6 are priced above so pass 2 can reopen it with
numbers in hand, and dec. 8 records why it is the one subdirectory worth reopening.

### 3. ADR-0257's **rule** stands and its **stated rationale is falsified on four of the eight panels** — and the drop raises the name count

Dropping the panels moves arm 7 from **16 names / 132 lines** to **19 names / 65 lines**.
`BaseDebugPanel` (8 lines) leaves the reading, and **four panel `class_name`s enter it**,
because a name declared inside the membership is internal and a name declared outside is
not:

```
FormationDebugPanel       1   src/ui3/formation/FormationScene.gd:931
DetailScreenDebugPanel    1   src/ui3/formation/FormationScene.gd:939
VitalsLayoutDebugPanel    1   src/ui3/formation/FormationScene.gd:949
UIDisplayDebugPanel       1   src/ui3/testing/CombatUITestScene.gd:194
```

ADR-0257 dec. 1's reason for the rule is that a panel *"is instantiated by the host's
scene-boot entry points rather than by the system it inspects."* **`FormationScene.gd`
is the system, it is a `game` root, and it mounts three of its own panels by name.** The
premise is false here. The rule survives — a panel is still host debug-window UI, and
counting it as a member still books the panel's reach into its subject's debt — but the
reason has to be *what a panel is*, not *who instantiates it*, because on this system the
instantiation runs the other way.

This is also the second sighting of ADR-0286's warning, on a different arm than it was
found on: there, dropping panels moved **arm 2** from 9 to 63 through `inside_prefixes`;
here it moves **arm 7's name count** up through set membership. **Report the pair.** A
single post-drop number is a number a later pass will correct.

Residue the flag does not catch: `src/debug/UI3RegistryView.gd` is not a `BaseDebugPanel`
subclass, so it survives the drop and carries all **9** remaining `TuneField` lines. Pass 2
gets it as S2.

### 4. ADR-0148 dec. 2's *"the printed total never moved"* **expires**: `touch_matrix.py` prints 656 of the 1,352 crossings it measures, and `UI` is the worst-hit column at 97%

`matrix()` loops `for a in SYS for b in SYS` where `SYS` is the eleven blueprint systems.
`classify()` books files to nine further buckets — `assembler`, `schema`, `content`,
`generated`, `infrastructure`, `platform`, `tests`, `DELETE` — and a crossing from one of
those into a system is **recorded in `touches` and never printed**.

**This was seen at extraction #1 and deliberately let stand.** ADR-0147's correction block
and ADR-0148 dec. 2 both write *"`assembler` is not one of the eleven systems the matrix
prints or sums, so fixing it moved the published total by zero"*, and ADR-0148 goes further:
*"The matrix was never wrong about the number; it was wrong about the edge list, which is
what a `--edges` reader uses to decide where a seam goes."* Both sentences were true of the
two lines they were written about. Neither is true now.

| system | IN printed | IN hidden | hidden sources |
|---|---:|---:|---|
| `UI` | **4** | **123** | `assembler` 115, `infrastructure` 6, `generated` 1, `content` 1 |
| `Cutscene` | 33 | 126 | `assembler` 126 |
| `Battle` | 77 | 156 | `assembler` 141, `infrastructure` 15 |
| `Debug` | 389 | 145 | `assembler` 145 |
| `Effects` | 6 | 33 | `assembler` 33 |
| `Battlefield` | 26 | 37 | `tests` 25, `assembler` 12 |
| *(all eleven)* | **656** | **696** | |

This is **not** ADR-0131 dec. 6's duck-typing floor, which is a real limit of what a symbol
scan can see. These crossings *are* seen, counted and cached; the print loop drops them.
Every selection ADR that quoted an inbound column quoted a number with this in it — and the
one ADR that checked said the number was fine, on a sample of two, five extractions ago.
**A zero measured once is not a property of the instrument.** ADR-0148's own *Alternatives
rejected* declined to leave the sibling two-step blind spot alone precisely because *"the
cost of fixing it now is provably zero"*; the print loop was left because it was priced at
zero and never re-priced.

**It is not repaired here.** A pass 1 that repairs its own instrument mid-reading cannot
say whether the reading moved ([ADR-0148](0148-a-walk-that-does-not-follow-the-refactor-loses-coverage-silently.md)),
and `UI`'s selection is the reading in flight. It is filed as a ticket against the
instrument and handed to pass 2 as S1, with the correct numbers for `UI` recorded above so
pass 3's prediction does not have to wait on the fix.

### 5. The addon's inbound surface is **62 lines / 25 names** if it ships the screens and **127 / 46** if it does not, and pass 3 decides which

`UI` ships **six of the root set's eleven `game` roots** — `Formation.tscn`,
`AllTemplatesFormation.tscn`, `DetailScreen.tscn`, `FormationDetailTransition.tscn`,
`FormationDev.tscn`, `WorldMap.tscn` — **55% of the game root set**. `Render`, `Audio` and
`Battlefield` each shipped none and scored goals #3 and #10 `n/a` on *"the addon has no
authoring surface"*; `Sprite Rig` shipped one and had to score #10 `open`. **`UI` cannot
use the `n/a` escape on either goal**, and pass 9 must expect to score both.

Five of those six roots' boot scripts are the five `assembler`-booked files in the table
above, and they carry 65 of the 127 inbound lines. That is the whole of the question:

- **Ship the screens** — the boots become members, their 65 lines become internal, and the
  published surface is the 62 external lines over 25 names, 24 of them
  `src/scenes/GambitBattle.gd`'s.
- **Keep the screens in the host** — the addon ships `UI3Element`, `UI3Registry` and the
  window/element machinery, and the published surface is 127 lines over 46 names, which
  includes every screen class the boots name.

ADR-0286 dec. 1's *"a root set that stays"* is the shape to **argue against**, not to
assume: there the retained half was an authoring tool with its own churn, and here it is
the product's own screens. Pass 3 owes the argument and the numeric prediction; pass 1
owes only the price of each side, and that is recorded.

### 6. `UI`'s widest inbound name is **`UI3Element` at 419 lines**, and it is the machinery, not a screen

If the answer to dec. 5 is *machinery*, `UI3Element` is the thing being published, and
419 reference lines — 390 of them in `tests/` — are what will repoint. If the answer is
*screens*, the 419 stays internal and `FormationScene` (190) and `DetailScene` (129) are
the published names instead. **The two answers move different thousands of lines**, which
is why dec. 5 is the extraction's largest decision and not a matter of taste.

### 7. The autoload question is **`Tune` at 127 lines**, not `UI3Registry` at 1

`UI3Registry` is a host autoload (`project.godot:30`) and it is a real ship-or-inject
question under ADR-0262 dec. 6 — *"an addon cannot ship `project.godot` entries"*, so any
system that must reach an autoload cannot land cleanly in `addons/` without inverting the
reach first. But it is reached from **inside** the membership; the arm-7 instrument reports
it as *"autoloads inside the membership: UI3Registry"* and nothing else.

The autoload that leaves is **`Tune`, on 127 lines** — 39% of M1's entire five-shape
figure, larger than the whole arm-7 number, and **invisible to arm 7** because arm 7 is a
`class_name` predicate. This is
[ADR-0159](0159-platform-is-not-a-leaf-and-battlefields-seam-waits-on-inverting-it.md)'s
*`platform` is not a leaf* recurring for the fourth system, at four times
`Battlefield`'s recorded scale. `Focus` adds 3 and `PSXDisplay` 24 — but `PSXDisplay`
already lives in `addons/exmateria_platform/`, so arm 7 does not count it and the seam does
not have to sever it.

Pass 3 must design against `Tune` first and `UI3Registry` second. A seam design that
answers `UI3Registry` and leaves `Tune` has answered the smaller half of the question by a
factor of 127.

### 8. `src/world_map/` carries **all** of `UI`'s `Campaign` and `Cutscene` debt, and it is the one subdirectory pass 2 should reopen

Remove `src/world_map/` (M5) and `WorldMapProgress` (17, `Campaign`) and
`CampaignRevealPass` (7, `Cutscene`) leave the reading **entirely** — no other member
reaches either system. That is 24 of the 79 countable outbound lines, 30%, in 13 files
that are 7.5% of the bucket.

It also holds the sixth `game` root and, through `WorldMapScene.gd`, **40 of the 127
inbound lines** — the single largest referrer on either side.

It is kept in for pass 1 because dropping it is a **scope** decision and pass 2 is the
scope pass. The price is recorded: M6 (127 files, panels and almanac and `world_map` all
out) reads **17 names / 41 lines**, the best reading available, and pays for it with a new
backwards name — `WorldMapScreenOut`, 2 lines, reaching from the host back into a dropped
subdirectory. A membership chosen for its number would take M6; whether `world_map` is
`UI` is a question about what the system **is**, and dec. 2 declines to answer it with a
ratio.

### 9. No numeric prediction is made here — pass 3 owes it

The method's table assigns the prediction to pass 3, after the crossings audit and the seam
design. ADR-0147 dec. 9 predicted at pass 1 and missed four of its predictions, three
because its table disagreed with its own prose. Pass 1 states readings; the readings above
are what pass 3's prediction must be built from and what pass 9 scores it against.

## Soft spots — handed to pass 2

**S1. `touch_matrix.py` prints 656 of 1,352 crossings** (dec. 4), and ADR-0147 / ADR-0148
dec. 2 priced the same mechanism at 2 lines and ruled it a zero. Filed as a ticket against
the instrument. Pass 2 must decide whether to fix the print loop or to add a second table;
either way, **every published inbound column in every prior selection ADR was taken with
this in it**, and pass 2 should say whether any of them moves — `Cutscene` (33 printed / 126
hidden) and `Battle` (77 / 156) are the two most likely to.

**S2. `--exclude-panels` leaves `src/debug/UI3RegistryView.gd` behind**, and it carries all
9 remaining `TuneField` lines. It is a debug view that is not a `BaseDebugPanel` subclass.
Either the flag's predicate is too narrow or the file is genuinely a member; pass 2 decides,
and the answer moves ADR-0257's scope.

**S3. Two instruments disagree about arm 2 on the same tree.** `selection_sweep.py`
reports `A2-L 140` for `UI`; `arm7_membership.py --all` on the same membership reports
**150** autoload lines plus 1 `/root/` reach. Ten lines, one tree, two instruments. ADR-0146's
*when two registers describe the same set, diff them* applies. Not diffed here — that is an
instrument repair and dec. 4's reasoning forbids it mid-reading.

**S4. `UI` reaches `ExMateriaAlmanac` on 52 lines** — its largest single `class_name`
crossing, into an addon that is **already published**. That is not a defect: reaching a
published addon is what a published addon is for. But 52 lines is the widest such reach in
the tree and pass 2 should read it, because six almanac files reach **back** into `UI`
(dec. 2) and a two-way edge between a shipped unit and an unshipped one is the shape the
seam has to sever.

**S5. `assets/scenes/CombatUI.tscn` carries 23 reference lines into `UI`** and is a
root-set `component`, struck from the root set as an `ext_resource` child of
`PlayerCamera.tscn` (ADR-0135 dec. 3). A `.tscn` edge is invisible to a symbol matrix —
this is the tenth line ADR-0157's correction found for `Battlefield`, in the same shape,
and `CombatUITest.tscn` adds 5 more. Pass 2's closure must walk scenes, not only scripts.
