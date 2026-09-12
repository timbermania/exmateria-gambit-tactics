# ADR-0306 — M5 is 121; UI's façade is 22 rows or 67 depending on where the tests live; and ADR-0305's census does not sum

- **Status:** accepted
- **Date:** 2026-09-12
- **Ticket:** #1268 (extraction #8, pass 6 step 2 — deliverable A)
- **Pass:** 6 of 9 (`docs/agents/refactor-loop.md`)
- **Grills:** ADR-0304 dec. 1, ADR-0304 dec. 4, ADR-0305 dec. 1, ADR-0305 dec. 2
- **Constrains:** ADR-0126, ADR-0135, ADR-0148, ADR-0194, ADR-0211, ADR-0212, ADR-0223, ADR-0257, ADR-0304, ADR-0305

Three numbers this extraction has been planning against are wrong, each for a different
reason: a **membership** error, a **bucketing** error, and an **arithmetic** inconsistency
inside one decision. The façade moves from 17 to either 22 or 67 — and which of those two it
is turns out to be a decision nobody has taken.

ADR-0305 §2 already knew this was treacherous ground. It derived the façade three times,
corrected itself twice, and caught a real instrument defect by *refusing a suspicious zero*.
This ADR is that same method applied once more, and it finds two more defects of exactly the
same family — one of them in the instrument this pass wrote. §4 is the generalisation.

---

## §1 — M5 is 121, not 125: the four `*Boot.gd` files are `assembler`

ADR-0304 dec. 1 put M5 at 125 after moving `src/ui3/testing/` out. It is **121**. Four files
under `src/ui3/` are booked `assembler`, not `UI`, by explicit override in
`tools/classify_blueprint.py:419-429` (ADR-0135 dec. 10):

```python
("src/ui3/detail/DetailSceneBoot.gd", "assembler"),
("src/ui3/detail/StartActionMenuBoot.gd", "assembler"),
("src/ui3/formation/AllTemplatesFormationBoot.gd", "assembler"),
("src/ui3/formation/FormationDevBoot.gd", "assembler"),
```

The prior passes read the directory (`src/ui3/` → UI) and never asked the classifier. The
classifier is the instrument the blueprint is scored with, so it is the one that decides.

**This is load-bearing beyond the count.** Those four files being *host-side* is what made
pass 6 step 1 legal: an `assembler` file may name `src/debug/` and call
`FormationDebugPanels.register_formation_panels()`. The same fact that shrinks the membership
unblocked the inversion. Had the Boot files been members, step 1 needed a different shape.

**It does not move the 79.** All four declare **zero** `class_name`s, so the declaration count
is identical under both memberships. 125→121 changes the move manifest, not the ADR-0212 bill.

### §1.1 — M5 is a filter over the classifier's bucket, not equal to it

`classify_blueprint.py` puts **154** files in the `UI` bucket. M5 is the **movable** subset.
Reproduced against the tool's own `walk()` — not an independent `rglob`, which yields 299
because it ignores `WALK_ROOTS` and `SOURCE_SUFFIXES`:

| step | Δ | why |
|---|---|---|
| `classify(f) == "UI"` over `walk()` | 154 | the bucket |
| − `addons/**` | −6 | already inside `exmateria_almanac`; not ours to move |
| − `src/debug/**` | −11 | ADR-0257 — a debug panel is not a member |
| − `src/ui3/testing/**` | −3 | ADR-0304 dec. 1 — stays host-side |
| − `src/world_map/**` | −13 | a separate system, bucketed UI on name |
| − `src/scenes/**` | −1 | `OpeningMenu.gd` is an assembly |
| − `assets/shaders/ui3_owner_color.gdshader` | −1 | its only consumers are `src/debug/UI3OwnerColorMap.gd` and `UI3OwnerMapPicker.gd` — a shader used only by debug panels is not a member, on ADR-0257's ground |
| + `src/ui3/**.tscn` | +2 | `.tscn` is not in `SOURCE_SUFFIXES`, but a scene moves with its script |
| **= M5** | **121** | `tools/ui_facade_census.py --members` |

A bucket is an accounting answer; a membership is a move answer. They were never the same set,
and reading one off the other is how 125 survived two passes (ADR-0223 — a reach has a bucket
*and* an address).

---

## §2 — The façade is 22, not 17 — and the gap is a bucketing decision, not a scan bug

Re-derived on the current tree against the 121-file membership, over every `.gd`/`.tscn`/
`.gdshader`/`.gdshaderinc`/`.tres` outside it, with the §4 blanker. **Every number in this ADR
is one command** — `python3 tools/ui_facade_census.py` (and `--control` for §4's controls);
it derives M5 from `classify_blueprint.walk()` rather than trusting a manifest, so §1.1's
table and this one cannot drift apart:

| | count |
|---|---:|
| `class_name` declarations inside M5 | **79** |
| **published** — a non-test file names the symbol | **22** |
| **test-only namers** — only `tests/` names it | **45** |
| **internal** — nothing outside M5 names it | **12** |

22 + 45 + 12 = **79 ✓**.

### §2.1 — Where 17 and 22 differ

ADR-0305 §2 did **not** scan `src/` only; it scanned the same file set this does. The gap is a
**rule** difference, and most of it is one rule:

- **ADR-0305 buckets `tools/` with `tests/` as "declined."** Two names are published only
  through `tools/`: `UI3BoxOpenBeat` and `UIMenuText`. Under ADR-0305's rule they are declined;
  under this one they are published. **22 − 2 = 20.**
- The residual **20 vs 17 cannot be reconciled from the document**, because ADR-0305's own
  census does not close — see §3.

### §2.2 — `tools/` is not `tests/`, and ADR-0305 half-knew it

The two tools-only namers are not scripts reading source as text. They are **running
GDScript** — `tools/ProtoGambitRow.gd` and `tools/proto_gambit_row.gd` — and they reach in the
one way ADR-0211 dec. 4 forbids:

```gdscript
const UIMenuText = preload("res://src/ui3/UIMenuText.gd")      # ProtoGambitRow.gd:18
const GloveCursorBob = preload("res://src/ui3/GloveCursorBob.gd")
const RangeTileAtlas = preload("res://src/ui3/elements/RangeTileAtlas.gd")
```
```gdscript
"open_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,                # ProtoGambitRow.gd:136 — bare global
```

ADR-0305 §2 applied exactly this correction to **`RangeTileAtlas` and `StartActionMenu`**:

> *"**ADR-0211 dec. 4 overturns that**: a host may alias a published constant, but *may not*
> `preload` an addon path — that is a criterion-4 path row `check_lattice_scene` already
> scores. Both must be published and aliased back."*

Those two were caught because they also had `src/` namers. `UI3BoxOpenBeat` and `UIMenuText`
are the *same case in the same file*, and were missed because the bucketer had already folded
`tools/` into "declined" before the ADR-0211 rule was applied. A bucketing choice made upstream
hid a rule violation downstream.

ADR-0211 dec. 5's decline route is genuinely available for `tests/` — ADR-0305 dec. 2 takes it
deliberately and says so. It is **not** available here: declining these two names leaves a
running tool preloading an addon path, which is a scored criterion-4 row, not declared debt.

### §2.3 — The 45 is the finding

More than half of UI's declared surface is reached **only** by tests. Whether those 45 names
must be published is not a measurement — it is the decision of where UI's tests live, and it
has never been taken:

- **tests stay in `tests/`** → façade **67 rows**, 45 of them existing solely so a test can
  name a class.
- **UI owns its tests** (`addons/exmateria_ui/tests/`, ADR-0194 dec. 2) → façade **22 rows**.

The corpus has answered this once. Measured across the ten shipped addons:

| addon | façade rows | addon-owned tests |
|---|---|---|
| `exmateria_battlefield` | 17 | **16** |
| `exmateria_schema` | 15 | 3 |
| `exmateria_platform` | 7 | 1 |
| every other | 1–32 | 0 |

`exmateria_battlefield` — the closest analogue in size, and the extraction UI's plan has been
tracking — holds its façade at 17 rows **while owning 16 of its own tests**. That is the
mechanism, and it is available here. A 67-row façade is not a bigger API; it is the same API
with the test surface welded on permanently, and a permanent public name is the most expensive
thing an extraction ships.

This ADR does not take that decision. It records that **the decision exists, that it is worth
45 published names, and that it must be taken before the `git mv`** — the façade is written
during the move, and every name in it is load-bearing thereafter.

### §2.4 — The 22

`DetailScene`, `DialogueBox`, `FeedbackHudManager`, `FieldInspectController`,
`FormationMapHost`, `FormationScene`, `GloveCursorBob`, `PauseScreen`, `RangeTileAtlas`,
`StartActionMenu`, `StopBadge`, `TurnMarker3D`, `TurnQueueHud`, `UI3Beat`, `UI3BoxOpenBeat`,
`UI3Element`, `UIChar`, `UICombatManager`, `UIFont`, `UIMenuText`, `UIUnitInfoWindow`,
`UIUnitNameplate`.

Three are published to **`src/debug/` only** (`UI3Beat`, `UIChar`, and `UI3Element` apart from
`tools/`), and two to **`tools/` only** (`UI3BoxOpenBeat`, `UIMenuText`). Those five are worth
a second look before they freeze into the API — a name whose only non-test reader is a debug
panel or a dev tool may be answerable another way. Flagged, not settled.

**No addon names any UI member in code** (arm 5 is already clean). Every `addons/` hit in the
first reading was prose; see §4.

---

## §3 — ADR-0305 dec. 1 does not add up, and neither does its census

> *"The addon declares one `class_name ExMateriaUI`; 62 of the 79 member declarations are
> removed, not merely unpublished."*

Both halves cannot hold. If the addon declares **one** `class_name`, then **79** declarations
are removed, not 62. The residual 17 is ADR-0304's façade count leaking back as though a
published name were a *retained* `class_name` — the very error ADR-0305 §1 was written to
correct. A published name is a `const` row in `exmateria_ui.gd`; the class it points at has had
its `class_name` removed like every other member.

Measured, unanimous: **all ten** shipped addons declare exactly one global `class_name` —
`exmateria_almanac`, `exmateria_battlefield`, `exmateria_catalogue`, `exmateria_effects`,
`exmateria_platform`, `exmateria_render`, `exmateria_schema`, `exmateria_sound`,
`exmateria_sprite_rig`, `exmateria_spu`. `exmateria_battlefield` publishes 17 façade rows *and*
declares 1 `class_name`, not 18.

So the bill is **79 removed, 1 added**, plus 22 or 67 `const` rows.

**The same slip is in the census.** ADR-0305 §2 closes its table with:

> *"17 + 43 + 21 = 79 ✓ (arithmetic control on one instrument)."*

17 + 43 + 21 = **81**. The control that was supposed to catch a miscount was itself miscounted,
so it passed a table that is over by two. At least one of the three figures is wrong, and the
document cannot say which — which is why §2.1's reconciliation stops at 20 rather than reaching
17. A sum written as a check must be *computed*, not asserted; this one was asserted.

---

## §4 — Three instrument defects, one family: a line-based blanker cannot see a multi-line construct

A façade census is a symbol scan, so every way a language can write a *non-symbol* occurrence
of an identifier is a way to publish a name on the strength of a sentence. ADR-0305 found the
first. This pass found two more — including one in its own instrument, which had produced 23.

| # | construct | what it falsely published | found by |
|---|---|---|---|
| 1 | `//` comments in shaders (`#` is not a shader comment) | `UI3ClipEngine` | ADR-0305 §2 |
| 2 | **`"""…"""` multi-line GDScript blocks** | `GambitOptions` | this pass |
| 3 | **`/* … */` shader block comments** | an `addons/` namer for `FormationScene` | this pass |

Defect 2 is the one that moved a number. `GambitOptions` scored as published on
`addons/exmateria_almanac/gambits/Gambit.gd:119` — prose inside a `"""…"""` doc block:

```
	#895's mutation operators and for saves written before this change; [method is_empty] and
	`GambitOptions.condition_label` both read either spelling.
	"""
```

A blanker that strips comments and strings *line by line* cannot see this: the line begins with
a tab and a backtick and contains no quote at all. Its opening `"""` is 11 lines earlier.
`GambitOptions` is in fact named by nothing but `tests/GambitEncoderTest.gd` and
`tests/GambitSurfaceTest.gd` — a **test-only namer**, not a published one. That single
correction is the whole 23 → 22 delta.

Defect 3 changed no count (`FormationScene` is published via `src/` regardless) but was the
last thing standing between the reading and the clean statement in §2.4 that no addon names a
UI member in code.

The fixed blanker is stateful across lines for both `"""…"""` and `/* … */`, and carries a
positive control on itself — asserting that a real use on the line *after* a blanked block
still scores, so "blanked everything" cannot masquerade as "found nothing" (a zero from a blind
instrument is not an absence).

**A fourth distinction, which cost nothing here but would have:** a `.py` or `.sh` file naming
a class is reading **source as text**, not using the symbol — `tools/check_focus_anchor.py`
names `"src/ui3/formation/FormationScene.gd"` as a path string. Those namers are counted
separately and cannot publish. Zero names depended on one, but only because the scan asked.

---

## §5 — What this does not settle

- **Where UI's tests live.** §2.3's point. Worth 45 published names; must be decided before the
  move writes the façade.
- **The five thin publications** named in §2.4.
- **#1263** (`DisplayPort` is two verbs short). Still not a blocker — ADR-0212 dec. 2.
- **Whether the 12 internal names are really internal.** They are internal *on the name axis*.
  A `res://` path reaching one is a criterion-4/6 row on a different axis, counted separately
  (ADR-0223); §2's scan blanks string literals by design and therefore cannot see it.

---

## §6 — A file written to drain a bucket was booked into it

`src/debug/FormationDebugPanels.gd` (pass 6 step 1, #1267) exists to delete UI's five
`UI → Debug` reach lines. `classify_blueprint.py`'s stem rule read `Formation` and booked its
129 lines to **`UI`** — the bucket it had just emptied.

The table already records this failure one extraction earlier, in its own `MapDebugPanels`
comment: *"the four lines it deletes reappeared in a file the stem rule put back in the same
bucket."* Fixed here by the same remedy on the same evidence: `FormationDebugPanels.gd`'s
outbound edges are `DebugOverlay`, `FormationDebugPanel`, `DetailScreenDebugPanel` and
`VitalsLayoutDebugPanel` — four `Debug`, **zero `UI`** — and it takes the screen as a bare
`Node` precisely so it names no UI type, exactly as `MapDebugPanels` takes the composer.

---

## Decisions

**1. M5 is 121 files, and it is a FILTER over the classifier's 154-file `UI` bucket, not the
bucket itself.** The four `src/ui3/**Boot.gd` files are `assembler` by explicit override
(ADR-0135 dec. 10) — which is also what made pass 6 step 1's host-side installer legal. They
declare zero `class_name`s, so the 79 is unchanged. Supersedes ADR-0304 dec. 1. Derivation in
§1.1.

**2. UI's façade is 22 rows against non-test callers, and 67 if every test stays in `tests/`.**
Supersedes the 17 in ADR-0304 dec. 4 and ADR-0305 dec. 2. Argued in §2.

**3. `tools/` is a production caller, not a test caller.** `tools/ProtoGambitRow.gd` is running
GDScript that `preload`s four member paths; declining those names leaves a scored criterion-4
row, not declared debt. ADR-0211 dec. 5's decline route covers `tests/` and ADR-0305 dec. 2
takes it deliberately; it does not extend to `tools/`. Argued in §2.2.

**4. Where UI's tests live is an open DECISION worth 45 published names, and it must be taken
before the `git mv`.** `exmateria_battlefield` holds a 17-row façade while owning 16 of its own
tests (ADR-0194 dec. 2). This ADR records the decision; it does not take it. Argued in §2.3.

**5. The ADR-0212 bill is 79 `class_name` declarations removed and 1 added, not 62 removed.**
ADR-0305 dec. 1's two halves are arithmetically inconsistent, and its §2 census control sums to
81, not the 79 it asserts. Measured, all ten shipped addons declare exactly one global
`class_name`. Supersedes ADR-0305 dec. 1. Argued in §3.

**6. A façade census needs one blanking arm per multi-line construct in every language it
scans, and the census is re-run after each.** `"""…"""` and `/* … */` are stateful and invisible
to a line-based blanker; `.py`/`.sh` namers read source as text and cannot publish. Three
defects of this family have now published a name on the strength of a sentence — one in
ADR-0305's instrument, two in this pass's. Argued in §4.

**7. `FormationDebugPanels` is booked `Debug` by explicit `DEBUG_EXACT` override.** A file
written to drain a bucket had been name-booked into it — the same failure the table already
records for `MapDebugPanels`. Argued in §6.
