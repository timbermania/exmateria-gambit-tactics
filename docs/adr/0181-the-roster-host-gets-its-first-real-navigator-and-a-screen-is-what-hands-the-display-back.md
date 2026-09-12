# The ROSTER host gets its first real navigator, and a screen is what hands the display back

The world map's START-menu row mounts the **ADR-0084 coordinator**, not the bare
`FormationScene`. The coordinator re-emits **`dismissed`** at rest so a host can take
the display back, gated to `Host.ROSTER`; its dev fixture moves out to
`FormationDevBoot` and its own scene, because the fixture opened by **destroying**
the player's roster.

Status: accepted (2026-08-25) — grilled with the user. **BUILT 2026-08-25.** Owned by
`src/ui3/formation/FormationDetailTransition.gd`, `src/ui3/formation/FormationDevBoot.gd`
and `src/scenarios/NavigatorMain.gd`. Guarded by `tests/FormationHandBackTest.gd`
(three arms, both gates seeded red) and by the two navigator route tests. Builds on
ADR-0137 (the two hosts), ADR-0084 (the coordinator seam), ADR-0180 (one population)
and ADR-0143 dec. 3 (a mounted-whole overlay is a navigation transition). Rewrites
**Formation screen hosting** in `CONTEXT.md` and adds **Hand-back**.

↺ **Renumbered.** Filed as `ADR-0171`; renamed to `0181` on 2026-08-26 because `0171`
was already taken on `import-godot-game` by `0171-the-display-port-is-platforms-and-render-is-the-fold-bracket.md`.
Commit messages up to `01f49f87d` cite the old number.

## Context

Opening Formation from the world map produced a screen where **○ and △ did nothing**.
Not a routing bug: the bare `FormationScene` emits `unit_activated` and nothing is
connected to it, and it has no `formation_start_menu` branch at all. Everything those
keys should do — the Status screen, the main menu, Equip, Ability, Change-Job, and
ADR-0084's reversal for each — already exists on `FormationDetailTransition`, whose
`Host.ROSTER` mode has simply never had a real navigator. The world map is its first.

The predecessor's framing was *"mounting the coordinator would need a third host mode."*
Measured, that is true only of `mount_over_map`, which wants `player_camera` /
`tile_cursor` / `unit_at` / `pause_battle` — all `Host.MAP`-only. `Host.ROSTER` needs
none of them, and `assets/scenes/Formation.tscn` and
`assets/scenes/FormationDetailTransition.tscn` differ in exactly one line, the root
script. The mount was already right; only `NavigatorMain`'s path constant pointed at
the wrong scene.

What the grill found instead were three things nobody had named.

- **`_resolve_roster()` was not a wart, it was destructive.** Its own docstring said
  *"a real host would pass the live `CharacterCatalog.owned_units()`"* — and its body
  opened with `CharacterCatalog.reset_to_new_game()`, which clears `_owned_order` and
  unregisters every slug outside the new-game baseline. The first real host would have
  wiped the player's owned overlay, and anyone who joined during the walk, on the frame
  the screen opened.
- **The coordinator EATS the signal the navigator awaits.** `_on_dismissed` consumes
  `FormationScene.dismissed` for its own unwind and re-emits nothing, so a path swap
  alone makes `await formation.dismissed` never return — no error, no `push_error`,
  nothing in the log.
- **The two hosts are asymmetric in a way the framing missed.** The MAP host never
  exits: `_mount_formation_map_screen` builds it at Deployment entry and
  `_free_command_cursor` frees it with the tile-cursor rig. It has no completion event
  because on a battlefield it has no lifetime. That is *why* `_on_dismissed` at rest
  only printed.

## Decision

**`Host.ROSTER` means "I am a screen with a lifetime." `Host.MAP` means "I am a
persistent overlay on somebody else's battlefield."** Everything below is that one
distinction applied.

1. **The world map mounts the coordinator.** `FORMATION_SCENE_PATH` splits in two:
   `FORMATION_SCREEN_PATH` (the coordinator) is the player's screen, and
   `FORMATION_VIEW_PATH` (the bare scene) keeps `run_formation_view`. They are two
   callers with two documented intents and should not share one name — the view-only
   checkpoint is debug-gated, yields to deployment, and mounts over a **live paused
   battle world**, where a full-screen NDC overlay is ADR-0162's hazard.

2. **The coordinator declares and re-emits `dismissed`, on `Host.ROSTER` only.**
   The same word `WorldMapScene` uses, because that **is** the interface: `NavigatorMain`
   awaits `dismissed` for three different screens and five navigator tests identify the
   world map by duck-typing `has_signal("dismissed")`. A second word would make this the
   one screen the navigator cannot treat uniformly.

3. **Not `settled(to)`.** It fires at every resting screen, and `_exit_settled` emits
   `settled(State.IDLE)` on the very press that backs out of Detail — so a host awaiting
   it would tear the screen down under a player still browsing. `settled` is a
   *within-screen* seam; a hand-back is a *lifetime* one.

4. **`FormationScene.dismissed` is unchanged.** Hosted it is the roster ELEMENT's cancel
   and stops at the coordinator; standalone it is that scene's own hand-back. Which role
   it plays is decided by whether anything is hosting it.

5. **`_resolve_roster()` becomes `CharacterCatalog.owned_units()` and nothing else**, and
   the fixture moves to `FormationDevBoot` with **its own scene**,
   `assets/scenes/FormationDev.tscn`. That is the shape `AllTemplatesFormationBoot`
   already had for the browsing half: the SCENE carries the fixture, the SCREEN reads the
   live catalogue. `_unlock_every_job`, whose own comment read THIS HARNESS ONLY, leaves
   production code — and leaves the `UI` bucket, since `*Boot.gd` classifies `assembler`.

6. **No Focus work.** ADR-0119 dec. 1 names **focus** — *"the right to receive input"* — as
   one of its four capabilities, with one holder per channel.
   `CONTEXT.md` spells the same term out as device input *"held by exactly one consumer"*.
   Nothing
   implements it anywhere in `src/` or `addons/`; ADR-0119's own Consequences call it
   *"a discipline, not a guarantee"* and ask for a mandatory code anchor that was never
   written. The mount does not need it: `set_suspended` already deafens the map, and the
   coordinator's `_input` pre-empts everything below it. Filed, not built — see below.

## Alternatives rejected

- **Keep the bare scene and grow `NavigatorMain`'s own `unit_activated` handler.** It
  re-implements the coordinator badly, or it leaves the screen read-only. The console's
  Formation row is the editable screen.

- **Fold-if-empty inside the coordinator** (`if owned_units().is_empty(): seed Gariland`),
  the shape `CombatUITestScene` uses. Non-destructive and ADR-0180 already blessed it —
  but it would have made the standalone dev screen show Ramza + four Squires instead of
  ~156 template rows, stopped the Change-Job ring being committable by hand, and moved
  the cluster golden. Rejected in favour of a boot script, which keeps both.

- **An injection seam** — the coordinator takes an injected roster and self-seeds when
  nobody injected. Rejected outright: two branches answering with two *different*
  populations is the "Marcus" defect one level up, and ADR-0180 exists because of it.

- **Build the Focus capability now.** Rejected as its own decision, not as scope-shyness:
  `set_suspended`'s `_input_enabled` is a **boolean flag**, the exact shape ADR-0119
  dec. 5 rejects, and `GPUArena._unhandled_input` tests **raw keycodes** rather than
  actions — which is why `_claim_pad` has to take the pad wholesale on the MAP host. A
  Focus service those two do not honour buys nothing.

- **A local grant/return pair** for just this hand-off. Rejected: a local imitation of a
  capability is the "discipline, not structure" failure ADR-0119 names, and it would give
  a future real Focus a second thing to migrate.

## Consequences

- **34 of the 36 tests that mount this coordinator were relying on it to seed for them.**
  Only `FormationEquipPickerTest` and the cluster golden seeded themselves. Each now
  states the fixture at the top of `_ready` — at `_ready` rather than beside the `.new()`
  because `FormationCoordinatorSeamTest` holds TWO host factories and the one that ran
  first found an empty catalogue. Same seeder, same units, so nothing moved: the golden
  is still 15/15 against `BOUND_UNIT_NAME` with **no re-capture**. Turning 34 implicit
  fixtures into 34 explicit ones is the golden's own re-base argument — pin the input
  beside the output.

- **The key names in this tree were wrong, and one named a key that does something else.**
  Decoded from `project.godot`: `ui_accept` = Enter + KP-Enter + pad 1 (○); `ui_cancel` =
  **Backspace** + pad 0 (✕); `formation_start_menu` = Tab + pad 3 (△), shared with
  `unit_inspect` and `world_map_start_menu`. **Escape is `battle_pause`**, not
  `ui_cancel`. Nothing binds pad 2 (□). Recorded once in the coordinator's header.

- **Two red python guards close.** `check_root_set` gains rows for `FormationDev.tscn`
  and `WorldMap.tscn` (this branch's own debt) plus two KNOWN entries applying ADR-0143
  dec. 3's ratified shape to the two screens the navigator opens;
  `check_adr_classification` gains ADR-0179's row, red since 2026-08-24.

- **Filed, not built: the world map has no system.** Declaring `WorldMap.tscn` surfaced
  it — `src/world_map/` is the repo's **entire** `UNCLASSIFIED` bucket, 15 files and
  4,496 lines, and `classify_blueprint.py` returns `None` for every one of them and for
  nothing else. Booking `WorldMapScene.gd` alone as `assembler` to clear the guard line
  would answer for 1 of 15, so it is a named KNOWN with the reasoning instead. The ADR
  table already leans an answer the code classifier does not have: 0178, 0179, 0161 and
  0162 are all booked `Campaign`.

- **Filed, not built: the Focus capability and its mandatory code anchor** (ADR-0119).

- **Not decided here:** how the Formation screen LEAVES. `dismissed` says the screen is
  finished; what it looks like going is ADR-0172's open question, held open for the same
  reason ADR-0161 §6 holds the world map's exit open.

## Built

Landed 2026-08-25 across two commits.

**The first cut put the dev harness on the player's route**, and the shape of that mistake
is worth more than the fix. `AllTemplatesFormation.tscn` does not take over
`Formation.tscn` — it is a separate root beside it — and re-rooting
`FormationDetailTransition.tscn` on `FormationDevBoot` mirrored the wrong half of that
precedent, because that scene is the one `NavigatorMain` mounts. Measured on the live
route: `[FormationDevBoot] seeded 191 owned unit(s)`. The destructive reset had changed
files, not routes. `NavigatorWorldMapFormationTest` caught it at **5/9** — a boot node
carries no `dismissed`, so the navigator's await released instantly and the map never
suspended. With the harness on its own scene the route reports **5 owned units**, the
Gariland cast.

**A finder duck-typed on a method the host does not have.**
`NavigatorWorldMapFormationRenderTest` looked for `set_owned_characters`, which belongs to
the roster GRID, not to its coordinator — so it answered `null` and "Formation mounted"
failed. It now matches `current_state()` as well and reaches through `_formation` for
every grid assertion. A duck-type is a claim about a shape, and the shape changed.

**Both gates are proven, not asserted.** With the re-emit removed, `FormationHandBackTest`
arm A goes red — that is the hang. With the two gates removed, all three arms go red,
including a hand-back fired while the Status screen was open. An unseeded gate reads
exactly like a blind check.

## Amendment (2026-08-28) — every decision holds three days on; one consequence has since been CLOSED by ADR-0176, and the fixture census grew from 34/36 to 37/37

*Audit pass, 2026-08-28 (ADR consolidation). The six Decision bullets above were an unnumbered
list; they are now `1.`–`6.` so `ADR-0181 dec. N` citations resolve. No prose was changed or
removed. Graded against the tree, not against the Built section's own account.*

### What is current, per decision

| Dec. | Rule as written | Holds? | What the tree says |
| --- | --- | --- | --- |
| 1 | `FORMATION_SCENE_PATH` splits into `FORMATION_SCREEN_PATH` (coordinator) and `FORMATION_VIEW_PATH` (bare scene) | **built** | `NavigatorMain.gd:360` and `:364` declare both; the old single name has no occurrence. `run_formation_view` loads the VIEW path (`:370`), the START-menu row loads the SCREEN path (`:655`). |
| 2 | The coordinator declares and re-emits `dismissed`, `Host.ROSTER` only | **built** | `signal dismissed()` at `:200`; `dismissed.emit()` at `:2728`, reached only after the two gates below. |
| 3 | Not `settled(to)` — that is a within-screen seam | **honoured, and the reasoning is in the source** | `_on_dismissed` gates on `current_state() != State.IDLE` → `leave()`, and the header at `:191`–`:192` restates why `settled(State.IDLE)` would tear the screen down under a browsing player. |
| 4 | `FormationScene.dismissed` unchanged; role decided by whether anything hosts it | **holds** | The coordinator still consumes the element's `dismissed` for its own unwind; the MAP host prints and returns rather than emitting, with the "a hand-back here would be a claim that is false rather than merely unheard" reasoning carried in the code. |
| 5 | `_resolve_roster()` → `owned_units()`; the fixture moves to `FormationDevBoot` + its own scene | **built, and the destructive call is GONE** | `_resolve_roster` and `_unlock_every_job` have **zero** occurrences anywhere in `src/`. `src/ui3/formation/FormationDevBoot.gd` and `assets/scenes/FormationDev.tscn` both exist, and the boot's header carries the whole finding (the `reset_to_new_game()` that would have wiped the player's overlay). `classify_blueprint.py:243` books `FormationDevBoot.gd` as `assembler` citing this ADR — so the classification half landed too. |
| 6 | No Focus work; filed, not built | **still true** | Nothing named `Focus`, `FocusService`, `claim_focus` or `focus_holder` exists in `src/` or `addons/`. The deferral is a live deferral, not a quiet build. |

### The consequences, re-measured

- **`check_root_set` closes as described, and is green.** `docs/ROOT_SET.tsv` rows 9 and 10
  declare `FormationDev.tscn` (citing `0181`) and `WorldMap.tscn`; the two KNOWN entries
  applying ADR-0143 dec. 3's ratified shape sit at `check_root_set.py:168` and `:177`, each with
  its reasoning. The guard reports *13 roots (10 game, 3 authoring), 14 declined, 5 components;
  32 scenes declared*.
- **The fixture census grew and the invariant held.** The ADR measured 34 of 36 tests relying on
  the coordinator to seed for them. Today **37** test files mount the coordinator and **all 37**
  state their own fixture. One test joined the set after this ADR and followed the rule without
  being told to, which is the outcome the consequence was written to buy.
- **`FormationHandBackTest` carries exactly the three arms it claims**: `_a_rest_hands_back`,
  `_b_open_screen_does_not`, `_c_map_host_does_not`.

### The world-map consequence is CLOSED, by a different ADR

"Filed, not built: the world map has no system" is no longer true. `classify_blueprint.py:245`
now opens with "src/world_map/ is not one system (ADR-0176, issue #580)" and books the directory
explicitly: `WorldMapScene.gd` → `assembler`, `WorldMapProgress.gd` and `WorldMapVariables.gd` →
`Campaign`, `WorldMapMusicPort.gd` → `Audio`, with `src/world_map/` → `UI` as the residual rule.
This ADR's leaning — "the ADR table already leans an answer the code classifier does not have:
0178, 0179, 0161 and 0162 are all booked `Campaign`" — turned out **half right**: two files went
`Campaign` and the rest did not, which is precisely why the ADR was right to refuse to book
`WorldMapScene.gd` alone to clear a guard line.

The measurement behind it has also moved, and is recorded here so a future reader does not treat
the old figure as current: the directory held "15 files and 4,496 lines" when this ADR was
written; today it is **14 `.gd` files totalling 5,195 lines**, plus two `.gdshader` files. The
number was true when taken — this is drift, not an error.

### What this ADR got right that the others audited did not

Twenty-six ADRs into this pass, this is the first whose Status line is not merely accurate but
*specific*: it names the build date, the three owning files, the guarding test and its arms, and
the four ADRs it builds on — and every one of those claims checks out. Its "Built" section also
records two mistakes made during the build (the dev harness landing on the player's route; a
finder duck-typing `set_owned_characters`, which belongs to the grid rather than the
coordinator) rather than only the outcome. Both are still legible in the tree: `FormationDev.tscn`
is a separate root beside `Formation.tscn`, exactly as `AllTemplatesFormation.tscn` is.

### On mechanizing this ADR

Dec. 2/3/4 are mechanized by `FormationHandBackTest` with both gates seeded red, dec. 1 by the
two navigator route tests, and dec. 5 by `check_root_set` + `classify_blueprint`. The arm that
is **absent** covers dec. 5's negative half: nothing asserts that `reset_to_new_game()` stays out
of a *screen* — the call is legitimate in `ProgressionDebugPanel` and `NavigatorRunner`, so the
assertion has to be scoped ("no file under `src/ui3/formation/` outside a `*Boot.gd` calls it"),
which is writable today and would pass. That is the guard against this ADR's actual finding: the
defect was never the fixture, it was the fixture living on the player's route.
