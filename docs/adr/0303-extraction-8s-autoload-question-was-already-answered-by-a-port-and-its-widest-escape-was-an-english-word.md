# ADR-0303 — Extraction #8's autoload question was already answered by a port, and its widest escape was an English word

- **Status:** accepted
- **Date:** 2026-09-11
- **Pass:** extraction #8 (`UI`), pass 3 — *audit the crossings that exist, then design the seam, then predict*
- **Ticket:** [#1262](https://github.com/timbermania/fft-monorepo/issues/1262)
- **Reads:** [ADR-0302](0302-extraction-8-is-ui-selected-against-the-metric-and-the-matrix-that-selects-prints-four-of-its-hundred-and-twenty-seven-inbound-lines.md) (pass 1), `docs/EXTRACTION-8-VAULT-ANCHORS.md` (pass 2), [ADR-0126](0126-every-system-pass-audits-before-it-designs.md), [ADR-0148](0148-a-walk-that-does-not-follow-the-refactor-loses-coverage-silently.md), [ADR-0159](0159-platform-is-not-a-leaf-and-battlefields-seam-waits-on-inverting-it.md), [ADR-0175](0175-a-port-answers-arm-1-and-not-arm-2-and-the-debug-residue-was-print-statements.md), [ADR-0183](0183-the-published-autoloads-were-named-from-inside-and-that-half-was-uncounted.md), [ADR-0223](0223-a-reach-has-a-bucket-and-an-address-and-goal-5-only-ever-read-the-bucket.md), [ADR-0257](0257-a-debug-panel-is-not-a-member-and-the-order-that-counted-it-as-one-is-an-artefact.md), [ADR-0262](0262-the-alias-route-hid-forty-nine-lines-and-the-almanac-reads-as-a-system-only-because-classify-books-by-consumer.md), [ADR-0131](0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md)

---

## Context

ADR-0126 requires a pass to **audit before it designs**, and to say which half it is
in. This ADR is in three explicit parts, in that order: **§1 the audit** — what is
measured, with no proposal in it; **§2 the design** — what should be built, resting only
on §1; **§3 the prediction** — falsifiable numbers, written before pass 6 builds anything.

Pass 2 settled membership at **M5 = 128 files** = all 118 under `src/ui3/` + 10
`assets/shaders/*.gdshader`, and handed pass 3 a worklist: 24 host escapes, 8 autoloads,
and ticket #1262's judgement that **`Tune` at 14 member files is "the single largest
design question in the extraction."**

That judgement is wrong, and so are three of the numbers under it. That is the finding.

---

## §1 — The audit

Every figure below is produced by the guard's own predicates, imported from
`tools/check_addon_portability.py` and applied to M5, rather than by a hand-written
approximation of them. Where a number corrects a pass-2 number, both are given.

### 1.1 `Tune` is 107 call sites and **107 of them already have a port**

`src/ui3/` holds **107 real `Tune` code lines across 14 member files** (comments and
trailing comments stripped). They use exactly four verbs:

| verb | sites | on `TunePort`? |
|---|---:|---|
| `Tune.bind` | 44 | yes |
| `Tune.bind_update` | 40 | yes |
| `Tune.get_value` | 17 | yes |
| `Tune.on_update` | 6 | yes |
| | **107** | **107 / 107** |

`addons/exmateria_platform/tunables/TunePort.gd` publishes six verbs — `bind`,
`get_value`, `on_update`, `bind_update`, `set_value`, `on_any_change`. UI uses four of
the six and nothing else. **The residue is zero.**

The precedent is not theoretical. Across all eight installed addons there is **exactly one
real `Tune` code line**, and it is `TunePort.gd:84` itself
(`root.get_node_or_null(^"Tune")`) — every other addon mention of `Tune` is a comment.
Positive control on the same routine: `src/ui3/` returns 107 lines in 14 files, so the
instrument is not blind and the one-line answer is real.

Naming `TunePort` from a system addon is permitted and already exercised:
`check_addon_portability.py:654` states *"`TunePort.gd:77` naming `Tune` is that design
working… the kernel and the port are exempt, a SYSTEM is not"* — the exemption attaches
to the **port**, and a system that calls the port is on arm 5's free set.
`addons/exmateria_battlefield` calls `TunePort` from **7 files** and the guard is green
today. ADR-0175 dec. 1's *"`port` is a tier verdict, not a resolution"* is not contradicted:
the tier verdict is exactly what a system consuming the port is allowed to rely on.

### 1.2 `PSXDisplay` has a port too, and it is two verbs short

24–25 member lines in 7 files name `PSXDisplay`, and the surface they use is **two names**:
`live_ui_par` (12) and `live_ui_par_changed` (12). `DisplayPort` exists and publishes
`live_fx_stretch`, `live_cursor_stretch`, `live_camera_angle`, `set_camera_angle` and the
`VERTICAL_DATUM_PX` / `NATIVE_VIEWPORT_HEIGHT` constants — and **neither `live_ui_par` nor
`live_ui_par_changed` is on it.** Battlefield reaches display through `DisplayPort`; UI
reaches it through the raw autoload because the port has no door for it.

### 1.3 The widest escape in pass 2's table is an English word

Pass 2 reported 24 host escapes and called `src/units/Unit.gd` *"widest at 5 member
referrers."* Re-read line by line with string literals blanked:

| symbol | lines in members | verdict |
|---|---:|---|
| `Unit` | 11 | **11 / 11 are the string `"Unit"`** — `return "Unit"`, `options.append("Unit")`, `"when Nearest Ally Unit"`, `"Remove Unit"` |
| `UnitStatusManager` | 3 | **3 / 3 are `get_node_or_null("UnitStatusManager")`** — a node **name**, not a type |
| `CombatLoop` | 0 | no code line in any member at all |

`src/units/Unit.gd` is **not a dependency of UI**. The pass-2 walk matched an English
noun on a word boundary inside gambit prose and menu row labels. `CombatLoop` was matched
in a trailing comment the walk's line-start comment filter did not reach. Corrected, the
24 rows are: **3 that pass 2 itself resolved** by adding the `*Boot.gd` roots to M5, **3
phantoms**, and **18 real escapes**.

The guard's own arm-7 predicate, run against M5, independently returns **18 symbols over
34 lines** and does not list `Unit` — the literal-stripping agrees with the instrument.
It also returns one symbol the pass-2 walk missed entirely, `PromotedRosterSeeder` (1
line), so the walk erred in **both** directions.

### 1.4 A node-name string contract is invisible to every arm

Arm 2b's regex
(`(?:get_node|get_node_or_null|has_node|find_child)\s*\(\s*[&^]?"(?:/root/)?([A-Za-z0-9_]+)"`)
matches a node-path string **with or without** `/root/`, and then reports it only if the
captured name is a declared autoload. So:

* `get_node_or_null("/root/UI3Registry")` — **caught**, arm 2b, 9 lines.
* `get_node_or_null("/root/DebugOverlay")` — **caught**, arm 2b, 1 line.
* `get_node_or_null("UnitStatusManager")` — **not caught by anything.** It is not an
  autoload, so arm 2b discards it; it is not a `class_name`, so arm 7 cannot see it; it is
  not a `res://` path, so arm 6 cannot see it.

Three member files assume the host's unit node has a child node **named**
`UnitStatusManager`. That is a real cross-system contract carried entirely in a string,
and no arm on the guard counts it. This is ADR-0223's *bucket and address* distinction
in a third place: the reach has neither a bucket nor an address, only a name.

### 1.5 The debug panels sit on **both** sides of the seam

ADR-0257 rules a debug panel is not a member, and pass 1 dropped 8 of them. Measured now,
they dominate the seam from both directions:

* **Outbound:** 4 of the 34 arm-7 lines are members **constructing** dropped panels —
  `FormationScene.gd:935/943/953` and `CombatUITestScene.gd:194`.
* **Inbound:** of **106 production lines** naming an M5 `class_name` from outside M5,
  `UI3RegistryView.gd` (26) + `FontDebugPanel.gd` (24) + `UI3OwnerColorMap.gd` (6) +
  `VitalsLayoutDebugPanel.gd` (3) = **59 lines, 56%**.

More than half of UI's public surface is sized by tooling that ADR-0257 says is not part
of the system, while the system reaches back out to construct it.

### 1.6 `UI3Registry` is UI's own autoload and is already soft-bound

`project.godot`'s only UI-owned autoload entry is `UI3Registry` → `src/ui3/UI3Registry.gd`.
Members reach it 11 times as a bare identifier and **9 times as
`get_node_or_null("/root/UI3Registry")`** — the soft-bind shape ADR-0175 dec. 2 chose,
already written, before any extraction work. ADR-0302 dec. 7 said the autoload question
is `Tune` and not `UI3Registry`; that is confirmed, and the reason is sharper than
"fewer lines" — `UI3Registry` is the one autoload the addon *owns*, and its reach is
already in the portable shape.

### 1.7 The remaining five autoloads

| autoload | lines | member files | has a port? |
|---|---:|---:|---|
| `CharacterCatalog` | 13 | 6 | no — and it already lives in `addons/exmateria_catalogue` |
| `DebugConfig` | 8 | 5 | no — host debug, ADR-0257 family |
| `SfxRouter` | 5 | 2 | no — Audio shipped to a package (ADR-0153) |
| `DebugOverlay` | 5 | 1 | no — 1 of the 5 already `/root/`-soft-bound |
| `EventBus` | 4 | 2 | no — two signals, `unit_hp_changed` / `unit_mp_changed` |

`CharacterCatalog` and `PSXDisplay` are **addon→addon autoload reaches**: both resolve to
files inside installed addons, reached through a host `project.godot` entry. By ADR-0262
dec. 6 neither addon may ship that entry, so both are their own addon's debt, not UI's.

---

## §2 — The design

Nothing below adds a measurement; it rests only on §1.

**1. `exmateria_ui` publishes `class_name`s and ships no `[autoload]` line.** ADR-0183
dec. 1's mechanism, unchanged, for the same reason. `UI3Registry` stays a host autoload
entry pointing at an addon file, and members keep reaching it by `/root/` soft-bind.

**2. The 107 `Tune` lines are a mechanical rewrite, not a design.** `Tune.X` → `TunePort.X`
for four verbs, 14 files, no signature changes, no new class. This is the single largest
line-count item in the extraction and it carries **zero** open design question. #1262's
framing of `Tune` as the largest design question is withdrawn.

**3. `live_ui_par` and `live_ui_par_changed` are added to `DisplayPort`, by `platform`.**
ADR-0159 dec. 3 settled the precedent — *"this ADR does not design the inversion; it is
`platform`'s work, not `Battlefield`'s"* — and the same reading applies here. UI's 24–25
lines then convert exactly as the `Tune` lines do. Filed against `platform`, not built by
extraction #8.

**4. The three phantoms are struck from the worklist, and the escape figure is 18.**
No inversion, no port, no ticket for `Unit`, `UnitStatusManager` or `CombatLoop` on the
class axis. `UnitStatusManager`'s three lines remain a real runtime contract and are
carried as §2 dec. 5's subject, not as an arm-7 item.

**5. The node-name string contract gets a decision, not a guard.** Three lines is too few
to justify a ninth arm, and a new arm during an extraction is precisely the
instrument-repair ADR-0148 forbids mid-reading. The three lines are recorded here, and
the *guard* question is filed separately so it can be decided on the whole tree's
evidence rather than on UI's three lines.

**6. The seam is drawn so that debug panels are on the host side of it, both ways.** The
4 outbound constructions invert: `FormationScene` and `CombatUITestScene` stop
constructing host panels, and the host mounts them. That converts 4 arm-7 lines to zero
and leaves the 59 inbound lines as what they are — host tooling reading an installed
addon's published names, which is the supported direction and costs the addon nothing.

**7. `src/ui3/testing/CombatUIDebugPanel.gd` is a conflict pass 4 must resolve.** It
`extends BaseDebugPanel`, which makes it a debug panel under ADR-0257 and therefore not a
member — but it lives under `src/ui3/`, which pass 2 ruled wholly in. Pass 3 does not
re-cut pass 2's scope; it records that exactly one file makes the directory rule and
ADR-0257 disagree.

**8. The addon ships the screens.** M5 already contains `FormationScene`, `DetailScene`
and `ChangeJobScreen`; ADR-0302 dec. 5 required this to be chosen explicitly, and it is
chosen. The inbound consequence is measured in §3.

---

## §3 — The prediction

Written before pass 6 builds anything, against `addons/exmateria_ui` containing M5's 128
files. Each is the guard's own predicate applied to M5 today — i.e. the reading the guard
would take **on the day of the move, before any of §2 is built**.

| arm | predicted at move | after §2 dec. 2 + 3 | after §2 dec. 6 |
|---|---:|---:|---:|
| **2a** — bare autoload identifier | **178** | 46 | 46 |
| **2b** — autoload by node path | **10** | 10 | 10 |
| **7** — `class_name` outside every addon root (lines) | **34** | 34 | **30** |
| **6** — `res://` leaving the addon root | **20** | 20 | 20 |

Arm 2a's 178 is `Tune` 107 + `PSXDisplay` 25 + `CharacterCatalog` 13 + `UI3Registry` 11 +
`DebugConfig` 8 + `SfxRouter` 5 + `DebugOverlay` 5 + `EventBus` 4. Removing `Tune` and
`PSXDisplay` leaves **46**, which is the number this extraction can reach on its own;
the rest is owned by `catalogue`, `platform`, Debug and Audio. Arms 2a and 2b overlap by
design on `UI3Registry` and `DebugOverlay` — the guard reports them as separate arms and
so does this table.

**Inbound, on M5: 106 production lines in 13 files** (1,553 more in 132 tests/tools files).
This supersedes ADR-0302 dec. 5's *"62/25 if the addon ships the screens"*, which was
computed on M4 before `src/world_map/` and the panels left and the scenes arrived; the
two are not comparable and M5's figure is authoritative from here.

**What would falsify this.** If the guard's arm-2a reading at the move is not 178 ± the
lines §2 changes, the predicate applied here is not the predicate `main()` runs, and the
prediction — not the tree — is what failed.

---

## Consequences

- #1262's central premise is withdrawn: the largest line-count item carries no design question.
- Two items leave extraction #8 for their owners — `DisplayPort`'s two verbs (`platform`),
  and `CharacterCatalog`'s autoload entry (`catalogue`).
- Pass 2's escape table is corrected in the record: 24 rows, **18 real**.
- Pass 4 inherits one open scope conflict (§2 dec. 7) and one guard question (§2 dec. 5).

## Alternatives considered

**A ninth arm for node-name string contracts.** Rejected for now, on ADR-0148: building
an instrument during the pass that reads it makes the reading unattributable. Filed instead.

**Writing a `UIPort` for the five portless autoloads.** Rejected: four of the five are
one or two verbs and three belong to other systems' debt. A port per consumer is the
duplication ADR-0159 pass 3 warned about — *an instrument built to remove a duplication
can be the duplication.*

**Keeping `Unit` on the worklist "to be safe."** Rejected. An entry that 11 measured
lines say is a string literal is not a conservative inclusion; it is a wrong number that
would have bought a real inversion for nothing.
