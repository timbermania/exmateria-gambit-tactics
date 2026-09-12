# The marking belongs to the schema, and a re-spelling is never the reason

ADR-0164 dec. 4 named three acceptance criteria for the lattice seam. Criterion 3 closed at
pass 7 ([ADR-0195](0195-the-cursor-publishes-a-coordinate-and-criterion-3-closes.md)),
criterion 2 at pass 6 ([ADR-0192](0192-the-register-goes-first-because-the-port-erases-its-own-baseline.md)).
**Criterion 1 has never had a guard**, and the reason is written down twice: ADR-0193 dec. 2
and ADR-0195 dec. 6 both DECLINED moving `Tile.HighlightType`, both priced the move at
*"43 addon-internal re-spellings"*, and both handed the decision forward — dec. 2's closing
sentence is *"whoever closes criterion 1 owns deciding where the enum lives."*

Nobody did, for two passes, because the deferral named an owner and no pass.

Status: accepted (2026-08-28), **built** (2026-08-28, two commits). Loop **pass 8** of extraction #3,
on map [#560](https://github.com/timbermania/fft-monorepo/issues/560). Amends
[ADR-0164](0164-the-lattice-ships-as-one-port-and-one-publish-and-tile-never-crosses.md)
dec. 4 criterion 1 in place, supersedes
[ADR-0193](0193-the-highlight-is-a-publish-with-an-address-and-the-sentinel-belongs-to-the-schema.md)
dec. 2 and ADR-0195 dec. 6, and admits one member through
[ADR-0139](0139-the-shared-kernel-is-enumerated-by-the-schema-list.md) dec. 3's gate.

## Context

### The reading — `3e0343f97`

Criterion 1 reads: *"The set of `Battlefield` `class_name`s named by any other system's
source must **equal** the declared published set exactly, with `Tile`, `TerrainIndex`,
`MapComposer`, `TileCursor`, `CursorController` and `PlayerCamera` absent from it.
Difference computed both ways."*

Three facts about that sentence, none of them previously measured, all of them from the
tree at `3e0343f97`:

**(a) `Tile` is the criterion's smallest term, not its whole.** Every prior handoff and
both declines discuss criterion 1 as though it were the enum. Comment lines stripped, type
references in `src/`:

| symbol | type refs in `src/` | what they are |
|---|---:|---|
| `TerrainIndex` | **0** | structurally unnameable since ADR-0192 dec. 4 |
| `PlayerCamera` | **0** | all 28 "code" lines are `$PlayerCamera` / `get_node_or_null("PlayerCamera")` |
| `MapComposer` | **0** | its 2 non-comment lines are a trailing comment and a docstring body line |
| `Tile` | 10 | every one of them `Tile.HighlightType.X` |
| `CursorController` | 8 | 4 × `var _c: CursorController` + 4 × `CursorController.new()` |
| `TileCursor` | ~~9~~ **13** | 5 annotations, 4 × `TileCursor.SEMI_MODE_LABELS`, 1 static wire, and **3 the hand count dropped** — see the 🔴 below |

Three of the six forbidden names are **already absent**. The criterion has been closer to
met than any pass believed, and no instrument said so because no instrument existed.

> 🔴 **Corrected by the register, 2026-08-28: `TileCursor` is 12, and the table above was
> wrong by three.** `check_lattice_publish.py` reproduced `Tile` 10 and `CursorController` 8
> site for site, and read `TileCursor` at **12**. The three it added are
> `EffectViewerScene.gd:27`, `FireCastReproScene.gd:45` and `GPUArena.gd:41` — each an
> `@onready var tile_cursor: TileCursor = $TileCursor` or the `get_node_or_null("TileCursor")`
> spelling: a real type ANNOTATION sharing its line with a node path. Each was re-read
> individually before the correction was written down, and all three predate `3e0343f97`, so
> this is a counting error and not a moved tree.
>
> The cause is dec. 2 applied one level too coarsely. Dec. 2 rules that a node path is not a
> `class_name`; the hand count excluded the **line** where the rule excludes the
> **occurrence**, and a line carrying both loses a compiled-symbol reference, which is the
> criterion's entire subject. The register scores the annotation and skips the node path on
> the same line. **The population is 31, not 27**, and criterion 1 ends this pass at **21**.
> `test_an_annotation_SHARING_its_line_with_a_node_path_still_counts_once` pins it.
> ⚠️ **And the register's own first draft dropped a FOURTH, which is how 12 became 13.**
> `CursorDebugPanel.gd:85` is `print("# outline blend mode …: %s" % TileCursor.SEMI_MODE_LABELS[bm])`
> — a real static read, lost because `strip_noncode` strips comments BEFORE it blanks
> string literals, so a `#` that is not a comment truncates the line. It was found by
> auditing the guard's own *"what this guard cannot see"* list, not by a failing test.
> **`TileCursor` is 13, the first-run population is 31, and criterion 1 ends this pass at
> 21.** Two independent under-counts on one symbol, from two different readings of the
> same rule — which is the argument for dec. 1 restated: a number nobody can re-derive
> from an instrument is a number that is wrong in ways nobody can see.

**(b) "Equal … both ways" cannot pass, and never could.** Of the addon's **30**
`class_name`s, ~~16~~ **20 are named by nothing in `src/`** — `Doodad`, `PlayerCamera`,
`SceneTreeManager`, `VisualGeometryIndex`, `MapStateSelector` and fifteen more. Set equality
against the published set therefore reds permanently on those names, whose only defect is
that no host happens to want them yet. ADR-0157 dec. 3 measured the same shape from the
other side (*"fifteen of `src/map/`'s eighteen files were named by nothing across a system
boundary at all"*) and it was never carried into the criterion.

> 🔴 **The 16 was wrong, and the correction is a ROOT, not a recount.** Measured by the
> built register: **20** of the 30 are named as a type by nothing in `src/`, and **13** by
> nothing outside the addon at all once `tests/` is counted. Sixteen matches neither — and
> the reading's own five examples pin which one it meant: `PlayerCamera`,
> `VisualGeometryIndex` and `MapStateSelector` are each named from `tests/`, so the list is
> `src/`-scoped and the number is **20**. That an unrecorded scan root moves this figure by
> seven is dec. 1's argument arriving one criterion early. The conclusion is untouched at
> either number: set equality reds permanently on names whose only defect is that no host
> wants them yet, and deleting a host call site still reds the guard.

**(c) There is no declared published set.** `tools/` contains none. The only statement of
it is prose in the addon README — *"30 `class_name`s and two scenes"* — a line whose own
⚠️ admits it *"read 28 and was already stale by one before loop pass 6 measured it at 29."*
A criterion that diffs against an undeclared set is a criterion nobody can run.

### Why the enum was declined twice, and what that reason was hiding

Both declines priced the move as a **count**. The count is the cheap half — a scripted
rename verified by a compile — and it was not even stable: ADR-0193 dec. 2 says **43**,
ADR-0195 dec. 6 says **43** *"with the number re-derived"*, `TileHighlights.gd`'s own
docstring says **47**, and the tree today holds **39** occurrences (21 in
`TileOverlayConfig`, which is the one figure all four agree on).

The expensive half was never named. Both declines assumed the destination was
`TileHighlights.Kind`, and **that destination is structurally wrong**:
`TileHighlights.gd` already depends on `Tile` (`func _tile(cell) -> Tile`, and `paint`'s
own parameter), while `Tile.gd` uses the enum at its declaration (`var
current_highlight_type: HighlightType`) and at four more sites. Moving the enum into
`TileHighlights` creates `Tile.gd → TileHighlights.gd → Tile.gd` — the exact shape
[ADR-0170](0170-the-third-door-is-a-forwarder-and-the-duck-typing-is-a-test-seam.md)
dec. 4 diagnosed as *"the circular dependency was `Tile.gd -> Unit.gd -> Tile.gd`"* and
ADR-0166 dec. 1 closed by deleting the reverse edge.

So both declines were **right about the outcome and wrong about the reason**, and priced a
structural blocker as a typing cost. That is the failure this ADR's dec. 5 exists to stop
recurring.

## Decision

**1. Criterion 1 gets a register, `tools/check_lattice_publish.py`, and it is built BEFORE
the enum moves.** *(Applies ADR-0192 dec. 1's ruling to the third criterion.)*

ADR-0192 dec. 1 ruled that *"a register written after them is a scanner that reads zero —
which is indistinguishable from a scanner that is broken"*. Criterion 1's baseline is **more** erasable than criterion 2's
was: after the move, `Tile`'s ten host lines are gone entirely, so a scanner that simply
fails to recognise `Tile.HighlightType` is indistinguishable from a correct one. The
register lands **red**, carrying `Tile`, `TileCursor` and `CursorController` rows, and the
move turns `Tile`'s rows green in the next commit.

🔴 **The seed test must CONSTRUCT both the site and the row.** A control has expired on
success three times in this family (ADR-0195's Consequences; `check_lattice_ports` one pass
earlier). A test that iterates the burn-down and asserts on its output is a loop over
nothing the moment the burn-down empties.

**2. Criterion 1 scores TYPE references. A node path is not a `class_name`.**

`$PlayerCamera`, `get_node_or_null("PlayerCamera")` and a `.tscn` instancing
`PlayerCamera.tscn` are couplings to a **scene tree**, not to a compiled symbol. Criterion 1
exists so the addon's *compiled* surface is narrow — a symbol you cannot name as a type
cannot be compiled against. Folding scene coupling in would make one number answer two
questions, which is ADR-0164 dec. 7(b)'s own named failure.

🔴 **The consequence is stated rather than hidden: the register will read 0 for
`PlayerCamera` while 107 `.tscn` files instance it and 109 name `MapComposer`.** That is
the **install** term — *"the addon does not parse where the declaring addon is absent"* —
which no ADR rules on and which this one does not either. The register PRINTS it. It does
not score it.

**3. `src/` enforces; `tests/` reports.** *(ADR-0170 dec. 5's precedent, unchanged.)*

`classify()` returns `None` for every test file, so a threshold there is guesswork. But
arm 1 at zero while 24 `Tile` node references sit in three cursor fixtures reads as
coverage, and ADR-0195's Consequences already record that those fixtures' stated reason was
wrong. Arm 2 prints them without a target.

**4. Criterion 1's set equality is amended: the forbidden difference is ENFORCED, the
declared difference is REPORTED.** *(Amends ADR-0164 dec. 4 criterion 1 in place.)*

Reading (b) above makes "equal both ways" unpassable. The criterion becomes:

- **Enforced** — no forbidden name is named as a type by another system's source. The six
  are `Tile`, `TerrainIndex`, `MapComposer`, `TileCursor`, `CursorController`,
  `PlayerCamera`, listed with a named burn-down, never a filter (#424).
- **Reported** — the declared published set must be a SUPERSET of the named set. A
  declared-but-unnamed name is not a defect; today there are sixteen. Enforcing that
  direction would make **deleting a host call site red the guard**, which is backwards.

The declared set is a literal **in the guard**, beside the burn-down — the `DOOR_BURN_DOWN`
/ `ARM1_BURN_DOWN` precedent. Not the README: a scan that reads its own prose passes through
the line it was meant to catch. Today's honest published set is **nine** — `Lattice`,
`TileHighlights`, `TileOverlayConfig`, `SkirtConfig`, `MapGridOverlay`, `MapIlluminationDDA`,
`EventPathfinder`, `MapConstants`, `TileCursorCompositor` — not the README's thirty.

**5. A re-spelling COUNT is never grounds to decline or defer. A deferral must name the
destination question and the PASS that owns it.**

This is a rule about how this refactor prices work, and it is stated here because it has
already failed twice on one enum. The goal is total isolation; the number of characters
that must change is never the obstacle to it.

- ❌ *"Moving it would re-spell 43 references."* — not a reason. A scripted rename verified
  by a compile is the cheapest change available, and a count that reads 43 / 43 / 47 / 39
  across four artifacts is not a measurement.
- ✅ *"The destination is unresolved: `TileHighlights` creates a cycle and the schema has
  not been costed."* — a reason, and the honest one. It **expires** when the destination is
  settled.
- ✅ *"Pass N is measuring criterion 2, and this would move that number for two reasons."* —
  a reason. It **expires** at the end of pass N.

🔴 **Any deferral must name the pass that owns the resolution.** ADR-0193 dec. 2 named an
owner (*"whoever closes criterion 1"*) and no pass; two passes then cited it and moved on.
A deferral with no expiry is a decision nobody ever has to make.

**6. `Tile.HighlightType` becomes `CellMarking.Kind`, in the schema.** *(Supersedes
ADR-0193 dec. 2 and ADR-0195 dec. 6 — on the destination, not the count.)*

`class_name CellMarking extends RefCounted` with `enum Kind`, at
`addons/exmateria_schema/lattice/CellMarking.gd`, beside `TerrainCell.gd`. The values are
unchanged: `NONE`, `PLACEMENT_PLAYER`, `PLACEMENT_ENEMY`, `PLACEMENT_CONTESTED`,
`PLACEMENT_UNAVAILABLE`, `CURSOR_ACTIVE`. The publish's signature becomes
`paint(cell: Vector2i, kind: CellMarking.Kind)` — named, never a bare `int`, so the two
sides still cannot disagree about what `2` means. Spelling follows the schema's own
precedent, `DepthMode.Mode`.

**Why the schema and not the addon.** ADR-0193 dec. 3 put the sentinel in the kernel on the
argument that *"the kernel is where both sides can name it"*. The marking is the same kind
of thing: a value vocabulary two systems must agree on. `src/strategy/` decides which cells
are which marking; the addon decides what a marking looks like. Any home inside
`Battlefield` means a host compiles against `Battlefield` in order to say *"contested"*.

**Why `CellMarking` and not `HighlightType`.** The enum does not name an appearance — the
appearance lives in `TileOverlayConfig`, and `Tile.gd`'s own comment insists the two are
decoupled (*"FFT's color meanings are decoupled from our placement semantics"*). It names
**why a cell is marked**: a placement-zone role, plus the cursor. `CellMarking` is keyed to
the same noun as the schema member it ships beside (`TerrainCell`), both addressed by the
`Vector2i` cell ADR-0166 dec. 3 made the one spelling of a cell's identity — and it survives
the first non-placement, non-cursor marking, which would have made `HighlightType` a lie
a third time.

**7. The gate is paid, not dodged.** *(ADR-0139 dec. 3.)*

`CellMarking` is a **new schema member**, so ADR-0118 dec. 1's table gains a row: the
payload is *which marking a cell wears*; it crosses `Battle` (`src/strategy/` produces it)
→ `Battlefield` (paints it). ADR-0139 dec. 4's two mechanical vetoes both pass — the **sink
veto** trivially (an enum has zero outbound edges) and the **autoload veto** trivially (it
is a `class_name` type).

🔴 **Riding `TerrainCell` as a nested enum was REJECTED, even though it is free.** That is
the route ADR-0193 dec. 3 legitimately took for the sentinel, *"a `const` on an already-admitted member, not a new
member, so ADR-0139 dec. 3's admission gate is not re-opened"*. It was legitimate there because
`TerrainCell.NONE` **is** a terrain-cell value. A marking is not: `TerrainCell`'s own
docstring draws exactly this line, listing what is deliberately absent and ruling that
*"`surface_type` is what the map data says"* while placement policy stays in `Battle`.
Hanging a marking on `TerrainCell` to dodge the gate is the junk-drawer accretion dec. 3
exists to prevent. If a payload cannot justify a row, it does not belong in the schema at
all — and that would be a reason to reconsider the schema home, never to smuggle it in.

**8. What this pass does NOT do, named so the next one inherits it rather than rediscovering
it.**

- **`TileCursor` (9) and `CursorController` (8) stay on the burn-down.** Four host scenes
  call `CursorController.new()` directly. That is a **construction** coupling — who builds
  the controller, and does `TileCursor` become a scene the addon hands out — and it is an
  interface question, not a re-spelling. Under dec. 5 this deferral names its pass: **the
  pass that closes criterion 1**, which is not this one. Criterion 1 will read ~~17~~ **21 lines
  over two symbols** when this pass ends — `TileCursor` 13 and `CursorController` 8; the 17
  inherited reading (a)'s under-count of `TileCursor` and nothing else.
- **The install term** (dec. 2's 🔴, plus arm 5's 138 cross-addon `class_name` lines) is
  raised and unowned. No ADR rules on it. Whoever decides that *isolated* must mean
  *installable in a bare project* owns opening it.

## Prediction

Graded 2026-08-28, on the two commits that built this. **3 of 4 held; 1 was wrong in the
one direction dec. 1 was built to catch.**

1. ❌ **`check_lattice_publish.py` reads 27 on its first run** — `Tile` 10, `TileCursor` 9,
   `CursorController` 8 — with `TerrainIndex`, `MapComposer` and `PlayerCamera` at 0 and the
   declared-set report printing 16 declared-but-unnamed names.
   → It read **31**. `Tile` 10 ✅ and `CursorController` 8 ✅ reproduced site for site;
   `TileCursor` is **13**, not 9 — three the hand count dropped and one the register's own
   first draft dropped (both 🔴s under reading (a)). `TerrainIndex`, `MapComposer`
   and `PlayerCamera` all read **0** ✅ — dec. 2's cheapest falsifier passed. The
   declared-set figure was wrong three ways: the report prints **2** declared-but-unnamed
   names (of a declared set of **9** — 16 was never arithmetically possible), **13**
   `class_name`s named by nothing outside the addon, and **17 of 30** named by something.
2. ✅ **After the move, `Tile` reads 0 and the register reads 17.** `Tile` reads **0**, and
   the register reads **21** — 17 was 27 minus 10, so it inherits prediction 1's error
   exactly and nothing else. The register turned **red on the rename commit** with `Tile`'s
   two rows STALE, and green again when they were deleted: the move was graded by the
   instrument rather than asserted by the mover, which is the only reason we know the
   scanner is *satisfied* and not *blind* — `Tile` reading 0 is what both look like.
3. ✅ **The move creates no criterion-2 exposure.** `check_lattice_ports` reads **0 / 0 / 0**,
   unmoved.
4. ✅ **`check_lattice_doors` stays 0 of 0.** An enum is not a door.

## Consequences

- **`Tile` leaves criterion 1's set**, and the addon's published `class_name` count falls by
  one in substance even though `Tile` keeps its `class_name` for addon-internal use.
- **The schema gains its sixth member**, and ADR-0139 dec. 3's gate is genuinely re-opened
  for the first time since ADR-0164 dec. 2 admitted `TerrainCell`. That is the price of
  dec. 6 and it is paid deliberately.
- **ADR-0164 dec. 4 criterion 1 no longer says what it said.** Dec. 4 above changes a ruled
  decision; the amendment is in place at 0164 so the ADR and the guard cannot disagree.
- **The register lands RED**, and a commit ships with a red guard until the move lands. That
  is dec. 1's intent, not an accident.
  > ⚠️ **Built as a non-empty burn-down returning 0, not as a non-zero exit.** An rc of 1
  > aborts `tests/run_all_tests.sh` at pre-flight for everyone standing on that commit, and
  > both sibling registers already shipped their hand counts the other way — rows printed
  > under a heading that says *"Not a pass"*, `DOOR_BURN_DOWN` and `PORT_BURN_DOWN` both.
  > "Red" here is the register reading **31 against a target 0, on record**. The rc-1 arm is
  > not softened: an UNLISTED namer and a STALE row each still abort the suite, and the
  > rename commit *did* red the guard until `Tile`'s rows were deleted.
- 🔴 **Criterion 1 is still OPEN when this pass ends** — **21** lines over `TileCursor` and
  `CursorController`. All three of ADR-0164 dec. 4's criteria will have instruments; two of
  three will read 0.
- **`tools/` is scanned, and neither sibling register scans it.** 94 `.gd` capture and debug
  scenes live there — host code by every test that matters — and both `check_lattice_doors`
  and `check_lattice_ports` stop at `src` / `tests` / `assets` / `addons`, each on a
  measurement of its own subject. This criterion's subject is any file that can name a
  `class_name`. Measured at **0** type references there, which is exactly why an unscanned
  root is dangerous rather than harmless: 0 is also what a scan that never looks reports.
- **The guard's blind-spot list was audited, and one entry was a live defect rather than a
  limitation.** Every register in this family carries a *"what this guard cannot see"*
  section; this one's claims were re-measured against the tree instead of asserted. Two
  survived as written (single-quoted node paths: zero occurrences; `.tscn`, which dec. 2
  rules out on purpose) and one turned out to be costing a real site — the `#`-in-a-literal
  truncation above. A blind spot written down and never measured is a blind spot that
  stays.
- **The enum's integer values are written out** (`NONE = 0` … `PLACEMENT_UNAVAILABLE = 5`),
  in `Tile.HighlightType`'s declaration order. Dec. 6 says the values are unchanged, and this
  ADR's own prose lists them in a DIFFERENT order from the source — grouping the placement
  roles and putting `CURSOR_ACTIVE` last. Implicit values plus that ordering would have been
  a silent renumbering of a `Dictionary` key set and every `Kind.keys()[value]` tunable slug.

## Alternatives considered

- **Move the enum to `TileHighlights.Kind`** — the destination both declines assumed.
  Rejected: it creates `Tile.gd → TileHighlights.gd → Tile.gd`, the cycle ADR-0170 dec. 4
  diagnosed and ADR-0166 dec. 1 closed. Avoiding it would mean `Tile` storing a bare `int`,
  losing the type on the one class that owns the state.
- **Decline a third time.** Rejected by dec. 5. Two declines priced a structural blocker as
  a character count and neither named a pass, which is how one enum survived three passes.
- **Re-declare the enum in `TileHighlights` and keep `Tile`'s.** Rejected on ADR-0193
  dec. 2's own ground, which remains correct: two enums for one concept is the shape
  ADR-0119 dec. 3 and ADR-0083's collapse both forbid, and nothing would notice them
  drifting.
- **Enforce criterion 1's set equality both ways, as written.** Rejected: it reds
  permanently on sixteen declared-but-unused names, and deleting a host call site would red
  the guard.
- **Declare the published set in the addon README and have the guard parse it.** Rejected:
  a source assertion that matches its own prose stays green through the deletion of the line
  it guards, and the README's count has already been stale twice.
- **Close `TileCursor` and `CursorController` in the same pass.** Rejected as scope: it is a
  construction-seam design question, and bundling it would mean criterion 1's register never
  records an honest first reading — dec. 1's hazard, one level up.
