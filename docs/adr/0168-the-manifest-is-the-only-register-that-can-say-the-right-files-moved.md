# The manifest is the only register that can say the right files moved, and the marker criterion is survival, not authoring

#565 asked two questions: **what crosses into the addon**, and **what acceptance
criterion travels with it**. Both halves turned on the same property — after
#561 dec. 2 collapses the ~27 hand-audited `Battlefield` rules into one location
assertion, the census *restates where files were put* rather than measuring what
`Battlefield` is, so a wrong move reads as a win on two instruments. The manifest
is not documentation of the move; it is the only register that can score it.

The second half arrived with a **false premise in the ticket**. #565 quotes the
marker trap out of `docs/agents/refactor-loop.md` verbatim:

> But ADR-0112 says we write **analogs**, and an analog is authored fresh, so it
> carries no marker unless someone puts one there.

That paragraph is **amended twelve lines below the quoted text**, by ADR-0154
dec. 1, and the amendment's first words are that ADR-0112 does not say it. Under
ADR-0110 dec. 1's lift a moving file keeps its comment for free, and this system
has already proved it: pass 4
(#551) split `CursorBob.gd` and `[[Start Action Menu]]` rode into
`src/ui3/GloveCursorBob.gd` — across a rename *and* a change of owning system —
with zero authoring and `check_vault_anchors.py` green throughout.

So the criterion is not *"carry the markers"*. It is *"no vault note loses its
last edge"*, and it is worth writing because **`check_vault_anchors.py` is
structurally unable to report that**.

Status: accepted (2026-08-25). Resolves
[#565](https://github.com/timbermania/fft-monorepo/issues/565) on map
[#560](https://github.com/timbermania/fft-monorepo/issues/560) (extraction #3,
loop pass 5). Amends **`docs/EXTRACTION-3-VAULT-ANCHORS.md`** in place (its
49-file / 17-anchored / 32-anchor headline is stale in both directions) and
map #560's own *"100 lines over 7 symbols"* note.
Cites ADR-0110 dec. 1, ADR-0111 dec. 7, ADR-0112, ADR-0131 dec. 6, ADR-0140
dec. 1, ADR-0147, ADR-0154 dec. 1, ADR-0164 dec. 4, ADR-0166 dec. 4, ADR-0167
dec. 6.

## Context

Every figure below was measured in `~/Repos/fft-monorepo-ext3-pass4` on
`refactor/extraction-3-pass-4` at **`cd9d6c88f`**, the commit this ADR freezes
the manifest against. Buckets are `classify_blueprint.classify()`'s, read per
file.

The census at `cd9d6c88f` is **44 files / 7,903 lines** — the ticket's *"44 files
/ 7,912 lines in `godot-learning/src/`"* is nine lines stale from #555's edits,
and two words wrong besides: **16 of the 44 are shaders under `assets/shaders/`,
933 lines, not in `src/` at all**. Plus #561 dec. 4's two `.tscn`, which no
census can see (`SOURCE_SUFFIXES` is `.gd` plus four shader suffixes and no
`.tscn`). **46 rows.**

Inbound, measured rather than quoted: **258 path references** (`path_refs.py`),
of which **228 come from 121 test files** and only **30 are production**; and
**150 typed lines over 11 symbols** (`touch_matrix.py`), not the map's *"100
lines over 7 symbols"*, which was pass 1's reading.

## Decisions

**1. The manifest is 46 rows, frozen on the source side at `cd9d6c88f`, and
`docs/EXTRACTION-3-MOVE-MANIFEST.tsv` is it.** Columns `src`, `dst`, `kind`,
`source`, `disposition`, `lines`, `anchors`. The **`src` column is a
measurement** — re-derivable by running the classifier at that commit — and is
not pass 6's to edit. The **`dst` column is a proposal**: ten seam-named
subdirectories under `addons/exmateria_battlefield/`, following
`exmateria_render`'s precedent of grouping by responsibility with each shader
beside its consumer rather than mirroring `src/` and `assets/`. Pass 6 may move a
row between subdirectories; if it does, it edits the manifest **in the same
commit**, which is what keeps the register a ratchet rather than a rubber stamp.

**2. Every row's disposition is `move`. Nothing is deleted at pass 6 and nothing
stays behind.** ADR-0166's occupancy severance deletes `Tile.reserved_by`,
`is_blocked` and `became_available` — **members, not files** — so `Tile.gd`
still moves and moves whole. The three edits #561 dec. 3 lists
(`path_refs.py:42`'s hardcoded `DEFAULT_SCENES`, `ROOT_SET.tsv` rows 29–30 in
**both** the `scene` and `script` columns, and `project.godot`'s three autoloads)
are not manifest rows and are not this register's business.

**3. `src/debug/DeadzoneBoxOverlay.gd` moves, and the stem rule that books it is
right by accident.** It is booked `Battlefield` by `DEBUG_OWNER`'s `("Deadzone",
"Battlefield")` fragment — the same name-booking mechanism that has now misfired
**five** times on `("Map", "Battlefield")` (ADR-0140 dec. 1, ADR-0144 dec. 3,
ADR-0156 dec. 4, ADR-0159 dec. 5, ADR-0167). ADR-0140 dec. 1's rule is *the owner
is the system its outbound edges land in*, and this file's outbound edges are
**zero** — the rule cannot book it at all. What decides it is the other
direction: its only inbound is `PlayerCamera.gd:171`, a **typed** field
(`var _deadzone_overlay: DeadzoneBoxOverlay`) constructed at `:295`. `Debug` is
in `cb.SYSTEMS`, so leaving the overlay in the host makes that line a typed
addon → `Debug` reach and **`check_addon_portability.py` arm 1 goes red**. It
moves. Recorded here because "the name rule agreed" is not the reason and must
not be mistaken for one later.

  ⚠️ This is *not* #555's shape and was checked before being dismissed as such.
  `MapComposer` constructed real `Debug` widgets (`TuneField` rows). The deadzone
  overlay is a bare `Control` that draws two floats the camera owns, driven by a
  slug the camera owns (`camera.show_deadzone_box`); `CameraFeelDebugPanel` is
  already the pure view ADR-0159 dec. 5 made it. There is no mount to invert.

**4. `src/debug/MapGridOverlay.gd` moves, and it is the one row whose consumer is
outside its own system.** Outbound: `Battlefield` ×1 (`grid_overlay.gdshader`) +
`schema` ×1 (`DepthMode.gd`) — so ADR-0140 dec. 1 books it `Battlefield` on the
measurement, not on the `"Map"` fragment. Its only inbound is
`ScenarioUnitAlignmentDebugPanel.gd`, booked **`Cutscene`**. It therefore becomes
a **published** symbol of the addon reached by a debug panel of another system —
which is legal (inbound is what a published symbol is *for*) but is a row #564
should see when it decides the published interface, and is flagged in the
manifest rather than left for #564 to rediscover.

**5. `TileCursorBob.gd` survives the move as its own row; pass 4's answer holds
and is not re-opened.** The knife half is 94 lines, `RefCounted`, four pure
statics with two call sites in `TileCursor.gd` and an oracle
(`TileCursorBobTest`) that drives all four against literal ROM ground truth
**with no node in the tree**. Inlining it into a `Node3D` converts a
ROM-faithfulness oracle into something needing a scene. The glove half already
left for `UI` at pass 4. Likewise `PlayerCamera.gd`'s 821 lines: the manifest
moves it as one row and does **not** force ADR-0159 dec. 8's question — nothing
in the enumeration made a seam decision necessary, which is the only condition
#565 set for re-opening it.

**6. The vault-marker criterion is `no registered note loses its last edge`, and
it keys on the NOTE, never on a path.** The file path changes *by design* in this
pass; a path-keyed or `R:`-keyed criterion goes red on every correct move and
teaches everyone to ignore it. The note name is the one coordinate the move does
not touch. `docs/EXTRACTION-3-VAULT-EDGES.tsv` freezes the register: **15 notes,
31 (note, file) edges, over 16 of the 46 rows.**

**7. Extraction #3's authoring debt is ZERO, and that is measured, not assumed.**
The `R:` seed scan was re-run over all 230 notes on `main` against today's
44-file set, honouring both traps ADR-0147 paid for (bare-basename citations;
longest-first suffix alternation so `.gd` cannot swallow `.gdshaderinc`): **15
notes, 31 pairs, 0 gaps and 0 extras** — the anchor set is exactly complete and
exactly tight. The wider control scan reproduces pass 2's single correct
exclusion, `[[Unit Shadow Rendering]]`, which names `tile_overlay.gdshaderinc`
inside a claim *about* `shadow_blob.gdshader`.

  This is the opposite of extraction #2, and the difference is structural rather
  than a matter of diligence. #404 authored **159 anchors over 67 files** because
  `Audio`'s addon tree **pre-existed the extraction**, sat outside `WALK_ROOTS`,
  had never carried a single `Vault:` string, and was cited through a **retired
  package prefix** (339 of 340 instances read `smd-player/`). `Battlefield` has
  no such twin: #561 put its addon **inside the walk**, and every file that will
  carry an anchor is a file pass 2 already anchored. A pass 6 that budgets 159
  anchors here will find nothing to write; a pass 6 that budgets none and checks
  is correct.

**8. The 28 unanchored rows are not a gap and must not be filled.** 3,020 of the
7,903 lines carry no anchor — dominated by the geometry generators
(`SkirtGeometryGenerator.gd` 827, `VisualGeometryIndex.gd` 300) and twelve of the
sixteen shaders. Pass 2 already ruled on this and the ruling stands: *"that is
not a gap to be filled by inventing anchors; it is the vault's coverage of this
system, reported."* Coverage is **reported, never asserted** (#310). An invented
anchor is worse than none — it manufactures an edge for pass 8 to find intact.

**9. `check_vault_anchors.py` cannot report the failure the criterion names, and
this was seeded rather than argued.** It enforces that every anchor *present*
resolves to a note on `main`, and has no opinion about an anchor that stops being
present. At `cd9d6c88f`, all three of these left it at **exit 0**:

| seed | effect | `check_vault_anchors.py` |
|---|---|---|
| delete both anchors in `MapStateSelector.gd` | `Battlefield 31 → 29` | **exit 0** |
| delete `[[Walk To Opcode]]`'s **only** anchor | that note → **0 edges** | **exit 0** |
| delete `EventPathfinder.gd` outright | file and anchor gone | **exit 0** |

The count moves in a line nothing asserts on. That is precisely
`refactor-loop.md`'s *"pass 8 cannot tell 'we dropped this' from 'we
reimplemented it without a marker'"*, reproduced.

**10. The criterion is mechanized as `tools/check_move_manifest.py`, four arms,
and each arm was seeded red.** Arm 1: every row is in exactly one of its two
places (red on **both** — copied not moved — and on **neither** — dropped). Arm
2: the classifier books no `Battlefield` file the manifest does not name, and
runs **only while a host copy remains**, because once the addon prefix rule lands
it would compare the manifest against itself. Arm 3: once
`addons/exmateria_battlefield/` exists, its source-file set **equals** the
manifest's `dst` set. Arm 4: no registered note loses its last anchor. Seeds
verified at `cd9d6c88f`: lost-last-edge → red (where `check_vault_anchors.py` is
green), vanished row → red, unlisted 47th `Battlefield` file → red, copy-not-move
→ red, extra file in the addon → red, restored tree → green.

**11. Both guards are registered in `tests/run_all_tests.sh`, and
`check_vault_anchors.py` was not registered before this ADR.** #555's lesson one
level out: the anchor guard — *"the ONE part of the refactor's instrument that
must exist before the code it names is rewritten"* — has never been invoked by
the suite. A pass-5 criterion checked at pass 7 by a guard nothing runs is
decorative. Both cost ~0.1 s.

## Consequences

- **Pass 6 owes three registers, not two.** ADR-0164 dec. 4's duck-typed-door
  register (12 → 0), ADR-0166 dec. 4's Tile-door register (8 → 0), and this
  ADR's manifest + vault-edge pair. All three must exist at pass 6; the first two
  do not exist yet.
- **The test surface is the manifest's largest hidden cost.** 228 of 258 path
  references live in **121 test files**, and ADR-0166 separately found 11 test
  files carrying 24 of holder 4's 56 lines. `docs/EXTRACTION-3-PATH-REFERENCES.tsv`
  remains a snapshot of a moving tree (ADR-0159 dec. 1) — regenerate, never read.
- **Arm 3 is blind to `.tscn` by inheritance.** It matches the two scene rows by
  suffix rather than through the walk, because `SOURCE_SUFFIXES` has no `.tscn`.
  #561 dec. 4's hole does not close by itself and `path_refs.py:42`'s hardcoded
  `DEFAULT_SCENES` is still the silent one.
- **`docs/EXTRACTION-3-VAULT-ANCHORS.md` is corrected in place.** Its headline —
  49 files, 17 anchored, 32 anchors, *"six of the seven `src/debug/` files"* —
  described a classifier that ADR-0156 dec. 4 and ADR-0159 dec. 5 have since
  changed. Today: **44 files, 16 anchored, 31 anchors, two `src/debug/` files.**
  Nothing was lost; five files were rebooked out of the system and one
  (`[[Start Action Menu]]`) rode a pass-4 split into `UI` with its anchor intact.
- **What no arm here can see**, stated because pass 4's lesson was that every
  blind spot on this map scored zero and every one was real: that an anchor still
  sits on code which still does what its note describes. Nothing can check that.
  It is pass 8's qualitative read and is supposed to be qualitative.
