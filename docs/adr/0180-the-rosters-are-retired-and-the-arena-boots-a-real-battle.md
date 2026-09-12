# The rosters are retired, and the arena boots a real battle

`PartyRoster`, `EnemyRoster` and `BaseRoster` are **deleted**. The player
population is the catalogue's owned overlay (`owned_units()`); the enemy
population is the **ENTD**. There is no `enemy_units()` — class stays derived
(`classify(slug, team_color)`, ADR-0078). `GPUArena`, whose whole cast came from
the two roster autoloads, instead composes its cast from the scenario it is
**already booting** — scenario 9, ENTD 388, deployment zone 256.

Status: accepted (2026-08-25) — grilled with the user. **BUILT 2026-08-25** — see
*Built* at the foot of this file for the five things the design did not know.
Calls ADR-0078's deferred **dissolution leg** ("the dissolution/deletion of
`PartyRoster`/`EnemyRoster`/`BaseRoster` and the rewire of their ~15 consumers
(incl. the GPUArena main scene) … a separate, higher-blast-radius cleanup leg
tracked apart from the Gariland proof"). Finishes ADR-0066 dec. 1 ("the battle
`Roster` demotes to a selection/view over it, not the master list"), which has
stood `proposed` since it was written. Supersedes **ADR-0004's roster decision**
(`rosters share a base script`) — there is no base left to share — but **not**
ADR-0004's other decision, *"subclasses extend by path, not by `class_name`"*,
which is a host-wide convention cited by 95 files across 8 systems and outlives
the rosters that occasioned it. Rewrites the **Owned roster** / **Party roster** /
**Roster** / **UnitRosterData** entries in `CONTEXT.md` and adds **Class**.

↺ **Renumbered.** Filed as `ADR-0163`; renamed to `0180` on 2026-08-26 because `0163`
was already taken on `import-godot-game` by `0163-limiting-is-a-bus-stage-and-the-domain-bus-is-where-it-goes.md`.
Commit messages up to `01f49f87d` cite the old number.

## Context

The world map's Formation screen showed a Squire at **HP 031** selected on the
grid, under a vitals panel reading **"Marcus" at 081** — a unit not on the grid.
Diagnosed as a one-frame binding race (`_build_unit_info_cluster` runs while
`_injected_characters` is still null, so it takes `_roster_characters()`'s
fallback branch), and the fallback branch is `/root/PartyRoster`.

Grilling that fallback exposed that the race was the *symptom* and the fallback
was the *defect*. Measured on the Gariland route, `owned_units()` was **5**
(`ramza` + four generics) and `PartyRoster` was **4** (Marcus / Elena / Garrett /
Lyra — hand-invented blank Squires from `create_starter_roster()`). The screen
was not choosing between two rosters. It was showing `party:0`, a seed row from a
store that ADR-0066 dec. 1 demoted in 2026 and nobody removed.

Three facts made the retirement obvious rather than optional:

- **The direction is inverted.** `BaseRoster._ready()` calls
  `_promote_units_to_catalog()` — the roster **writes into** the catalogue under
  positional `party:N` / `enemy:N` slugs. ADR-0078's Context already named this:
  *"the code was the inverse of ADR-0066/0073 … under positional `party:N`/`enemy:N`
  slugs (identity = slot — the bug ADR-0066 dec.4 already ruled out)."*
- **Almost nothing reads them.** Outside `src/roster/`, `PartyRoster` has three
  consumers (`ProgressionDebugPanel`'s save/reset buttons, `CombatUITestScene`,
  and the Formation fallback) and `EnemyRoster` has two more (`GPUArena`,
  `CombatUITestScene`). **Seven** test files touch them, one of which is the
  runner script. The story path already bypasses both — `EntdBattle.gd:7`: *"two
  teams to CombatLoop.start_battle — NOT by the hardcoded PartyRoster/EnemyRoster."*
- **One production consumer is already broken by them.**
  `FormationMapHost.character_for_unit()` is the map host's **only** unit→Character
  resolution, and it resolves `roster_index` / `roster_team` metas through
  `PartyRoster`/`EnemyRoster`. Only `BaseRoster.spawn_unit()` sets those metas.
  `NavigatorMain._spawn_owned_unit()` — the ADR-0079 deploy seam, the one that
  actually places owned units at Gariland — sets neither, so
  `character_for_unit()` returns `null` for every navigator-deployed unit today
  and `slot_number_for()` returns a hardcoded `1`.

## Decision

**One population. The catalogue's owned overlay is the player side; the ENTD is
the enemy side; class is derived from both and stored nowhere.**

The seven rules below were an unnumbered bullet list until this ADR's audit;
they were numbered — text unchanged — so `ADR-0180 dec. N` citations resolve.
Amendment 1 grades each one against the tree.

1. **`PartyRoster`, `EnemyRoster`, `BaseRoster` are deleted**, autoloads and all.
   This is ADR-0078's dissolution leg, called.

2. **No `enemy_units()`.** The symmetric-overlay shape is the one ADR-0078
   explicitly forbids: *"Class is derived, never stored … Only the raw inputs
   persist (`team_color` from the ENTD, owned-membership from the overlay)."* Two
   parallel lists would store class, and they break on cases that already exist —
   **Delita** is catalogue-yes / owned-no / Blue → `guest`, which has no home in
   either list; and a character who fights you and later joins becomes a *move
   between lists* instead of the same slug with a different `team_color` at a
   different battle. The symmetry is real but sits one level down: asymmetric
   **inputs**, symmetric **derivation** through `classify()`.

3. **`GPUArena` composes from the battle it already boots.** It sets
   `default_scenario_id = 9` and calls `ScenarioLoader.apply_scenario()`, which
   builds MAP022 and plays its music — the arena has been standing on Gariland the
   whole time and spawning a different cast beside it. Scenario 9 carries
   `entd_idx: 388` and `first_squad_deployment_idx: 256`, the same pair scenario 10
   (the real fight) carries. The arena deploys the owned overlay into zone 256 and
   composes against ENTD 388 via the existing `EntdBattle.compose_teams`.

4. **The arena folds `GarilandMutationScript` at boot.** `owned_units()` is
   established by folding a `MutationScript` through `CatalogueReplay`, and only
   `NavigatorRunner` folds today — so without this the arena's `team0` is empty.
   This is the one genuinely new piece of wiring the decision requires, and it is
   what *replaces* `create_starter_roster()`: four hand-invented blank Squires give
   way to Ramza + four generics minted `own: true` from ROM-grounded data.

5. **`FormationScene._roster_characters()`'s fallback becomes the catalogue.**
   Both branches then answer with the same population, so the one-frame binding
   race can no longer produce a *wrong* unit — only a late one. The standing
   objection to touching this guard (*"making it fall through would silently render
   a DIFFERENT roster — worse than rendering none"*) inverts once there is one
   population: rendering `party:0..3` **is** the different roster.

6. **`character_for_unit()` resolves by slug, not by roster index.** ADR-0066
   dec. 4 already names `slug` the cross-system identity key. This closes the
   null-binding defect above as a consequence, not as a separate ticket.

7. **`ProgressionDebugPanel` and `CombatUITestScene` rehome onto the catalogue.**
   The debug panel's save/reset is the overlay's save/reset; the test scene spawns
   from the catalogue.

## Alternatives rejected

- **`enemy_units()` as a second overlay.** The shape asked for first, and the one
  ADR-0078 forbids. See above — Delita has no home, and identity becomes slot
  membership again.

- **Retire `PartyRoster` only, keep `EnemyRoster`/`BaseRoster` as the arena
  fixture.** Recommended and then withdrawn: ADR-0078 already scoped all three,
  and stopping short leaves a second live way to populate the catalogue — which is
  exactly the mistake that put "Marcus" in a Formation frame.

- **(b) Give the arena a dev seeder** — strip save/load and catalogue promotion
  from `BaseRoster` and keep what remains as an honestly-labelled fixture.
  Rejected by the user on the reasoning that decided this ADR: a bare catalogue of
  eight units cannot say **where they stand** or **which side they are on**.
  Placement lives in `DeploymentZoneDatabase` keyed off a scenario, and the side
  lives in `team_color` on an ENTD slot. Inventing both is building a fake battle
  next to the real one — *"it would need to be a real battle."*

- **(c) Retire `GPUArena` with the rosters** and move `run/main_scene` to
  `NavigatorMain.tscn`. Rejected as scope: it makes "delete a store" depend on
  answering "what is the game's entry scene," and ~20 files (mostly debug panels)
  reference the arena.

## Consequences

- **`CharacterCatalog.unregister_namespace()` is DELETED, not merely dead.** It
  existed solely to firewall the arena's roster seeds out of the story universe —
  *"the two sides share this one autoload, so the arena test roster would otherwise
  pollute the story cast (and, via reset_to_new_game, the new-game baseline)."* With
  no roster seeds there is nothing to firewall. `unregister_namespace` and
  `ARENA_ROSTER_NAMESPACES` have **zero hits tree-wide**, and the `<prefix>:N` slug
  namespace ADR-0066 dec. 4 ruled against went with them. Stated as deletion rather
  than as dead code because a reader looking for the function to clean up will not
  find one.

- **ADR-0004 is superseded in half.** "Rosters share a base script" has no
  referent once there are no rosters. Its *other* decision — **extend by path, not
  by `class_name`**, taken because a newly-added `class_name` script is invisible
  until Godot's global class cache is rebuilt — is untouched and stays live: it is
  the reason `FormationDetailTransition` carries no `class_name` and both its hosts
  reach it by path. Do not retire the convention along with the store.

- **The arena stops being a separate combat universe.** After this it runs the
  same cast composition as the story path (`compose_teams`), on the map and ENTD
  it was already loading. `use_strategy_phase` placement, the march, and the
  deployment UI are unaffected — they operate on units, not on where the units
  came from.

- **`user://roster.json` and `user://enemy_roster.json` are orphaned**, as are
  the committed seeds `res://assets/roster/{roster,enemy_roster}.json`. Owned-layer
  persistence is still deferred (ADR-0073 §8, *"a save cannot exist before there is
  a game to save"*), so this decision **removes** a save path without adding one —
  deliberately. The player-facing persistent roster arrives with the owned
  overlay's save/load, not before.

- **"The arena boots scenario 9" is a claim about a CHECKOUT, not an invariant.**
  `config/tune_overrides.json` is a tracked working-state file that syncs between
  machines, and a `scenario.active_id` pin in it wins over `default_scenario_id`
  (`DebugConfig.active_scenario_id` only falls back when the key is unset). That key
  has entered and left the file seven times. It is absent today, so the arena boots
  exactly the battle described above — and nothing enforces that. Read any measured
  arena number in this document as conditional on the pin being absent; check the
  file before trusting one. Whether a guard should assert its absence is unresolved
  and recorded in `AUDIT.tsv` as this ADR's proposed arm ("Guard it | Leave it"): the
  pin silently changed which battle the arena boots, but the file is deliberately a
  scratch pad for committed debug picks, and a guard that fires on a file's intended
  use gets switched off.

- **Not decided here:** whether `GPUArena` remains `run/main_scene`. It does for
  now.

## Built

Landed 2026-08-25. All three scripts, both autoloads and both committed seeds are
gone; `GPUArena` composes from its scenario; `character_for_unit` resolves by slug.
Mechanized by `tools/check_rosters_retired.py` (no autoload, no script, no *use*, no
seed) — because ADR-0066 dec. 1 said this in 2026 and nothing enforced it, which is
the whole reason there was a "Marcus" to find.

Five things the design did not know, in the order they surfaced.

**1. The seam was the thing worth extracting, and there were FIVE copies, not two.**
`BaseRoster.spawn_unit(index, team)` was keyed by a **roster index**, so the story path
— which has no roster to index — carried its own copy, and so did the ENTD path inside
the same file. Re-rooted on the `Character` both copies actually wanted, they collapse:
`UnitSpawn` (`src/units/`) is `build` + `bind_for_combat` + `seed_job_abilities`, and
`NavigatorMain._make_combat_ready(unit, slot, team)` turned out to be
`_make_combat_ready_from_character` with an identity resolve in front of it. Only the
part that was already identical moved; the per-host tails (HP/MP top-up, the ADR-0079
Form stamp, the logical-tile init, `SCENARIO` clock ownership) stayed at their call
sites, because a seam that swallowed them needs a flag per host — which is the shape
`BaseRoster`'s three abstract hooks already were.

**2. A FOURTH `BaseRoster` subclass, and its docstring was wrong.**
`src/scenes/UnitAnimationViewerRoster.gd` is not in this ADR's consumer list. Its own
docstring called its seed *"the curated roster of sample units … that exercises every
resolution branch in `AnimationResolutionMap`"*; the seed is **one** level-1 male Squire
with no weapon, which the F3 panel reconfigures in place. So a whole base-class subclass
— save path, asset seed, catalogue promotion, index-keyed spawn — existed to load one
unit. Worse, it inherited `_promote_units_to_catalog()` at the DEFAULT `roster:` prefix,
so an authoring tool was quietly registering `roster:0` into the shared
`CharacterCatalog` — a namespace `ARENA_ROSTER_NAMESPACES` did not even name, so the
story navigator's scrub would not have caught it. Retired; the scene reads its fixture
with `JsonAsset` and spawns it with `UnitSpawn`. The seed stays as what it always was.

**3. `roster_team` had a SECOND reader, with a visible consequence.**
This ADR names `character_for_unit()`. `FormationMapHost.selection_is_owned()` reads the
same meta and gates whether the START menu's action rows go **disabled** — and it
answered "owned" whenever the meta was ABSENT, which is every navigator-deployed unit
*and* every ENTD enemy. The enemy screen offered live action rows. It now asks the
overlay, which is also right for the case team0 gets wrong: an ENTD-blue **guest**
(Delita fights beside you at Gariland) is team0 and is not yours to re-equip. Both
defects were seeded RED first — a silent `null` and a hardcoded `1` both survive a test
that merely *calls* the function.

**4. ADR-0004's surviving half lost its only guard, and got a better one.**
`tools/check_roster_base_inheritance.py` enforced "extend by path, not by `class_name`"
by *naming the roster files*, so deleting them would have deleted the enforcement of a
convention this ADR explicitly keeps alive. Generalised into
`tools/check_path_extends.py`: every `extends "res://…"` target in the walk, whatever it
is called. It covers 10 path-extends across 5 base scripts where the old one covered 2 —
and the trap is not historical: adding `class_name UnitSpawn` broke
`NavigatorPreBattleTest` on the very first run, with `Identifier "UnitSpawn" not
declared`, until `--import` rebuilt the global class cache.

**5. Two premises in the Decision are wrong about what actually runs.**

- *"`GPUArena` … sets `default_scenario_id = 9` … the arena has been standing on
  Gariland the whole time."* True of the scene default; **false of what boots**.
  `config/tune_overrides.json` — a TRACKED file — pins `scenario.active_id: 15`, and
  `DebugConfig.active_scenario_id` only falls back to the scene default when that is
  unset. Scenario 15 is **map 85, ENTD 389, deployment zone 257**, not MAP022/388/256.
  So the arena composes correctly, but against a different battle than this ADR
  describes, for anyone who checks the branch out. The implementation is scenario-
  generic (it reads `entd_idx` and `first_squad_deployment_idx` off whatever scenario
  is active) rather than hardcoding 388/256, which is the only reason this was a
  documentation defect and not a broken arena. It was **not fixed here** — the pinned
  value is a user pick in a shared file, and changing it is its own decision — and it
  is no longer present: an unrelated later commit removed the key without amending
  this ADR, so the premise was true when written and is false today. Do not read this
  paragraph as a live defect report; read the Consequences bullet on the pin, which
  states the durable part.

  Forced to 9 and measured, the arena is EXACTLY what this ADR describes: ENTD 388,
  `team0 = 6` (5 owned + 1 ENTD-blue — Delita), `team1 = 5`, `units_per_battle = 12`,
  deployment zone 256 (8 tiles, `max_squad_size` 5, so the clamp is the identity no-op
  `GarilandMutationScript` claims), and the march completes in 1,152 frames. Under the
  pinned scenario 15 the same code yields 13 units and two stragglers. The design is
  sound; what boots is not the design.

  Also measured: `ENTD 388` carries **one** ENTD-blue slot (Delita, uid 0x04, fixed tile
  (8,2)) and five red. `ENTD 389` carries two blue — Delita AND Algus — and six red.

- *"`use_strategy_phase` placement, the march, and the deployment UI are unaffected —
  they operate on units, not on where the units came from."* They operate on units, but
  they were **tuned for 4v4**. The real cast is 11 (scenario 9) to 13 (scenario 15), and
  on that denser field units start failing to reach a contested tile at all — one at
  scenario 9, two at scenario 15, reproducibly. ADR-0042's
  `_march_one` only gave up on a hard 1200-**frame** timeout — "~20s @60fps" by its own
  comment, but the arena runs at ~15 fps, so ~80 s of dead wall clock **each**. That is
  what pushed `CursorConfirmEndToEndTest` past its budget, and it was a real cost on
  every arena boot before that, just invisible. `_march_one` now also gives up when the
  unit has been IDLE somewhere other than its destination for 30 consecutive frames: the
  deploy gambit is `COND_ALWAYS`, so a unit that answers a standing move order by
  standing still has no route. Armed only after the unit has been seen walking (or after
  a 120-frame grace period) — a stuck-detector that fired in the frames between the
  order and the first step would abort every march and deploy nobody, silently.

## Verification

Verified 2026-08-28 — dec. 1–7 all hold, the first clean result in the ADR audit; dec. 6
corrected 2026-09-05, see Amendment 2. Per-decision evidence is the register
(`docs/adr/AUDIT.tsv`, `audit-notes/0180.md`); this section names only what a reader can
RUN. Line numbers are deliberately omitted — every one Amendment 1 carried had rotted
within a week.

| Dec. | What holds it |
| --- | --- |
| 1 | `tools/check_rosters_retired.py`, four arms: no autoload in `project.godot`, no `src/roster/`, no roster *use* (member access or `/root/` lookup), no `assets/roster/` seed. Surviving mentions are prose and two Node3D **names** in `CombatUI.tscn` / `GPUArena.tscn`, which the guard's docstring exempts deliberately so nobody turns it off. |
| 2 | **Unguarded.** Asserted only by inspection: the surviving `enemy_units` hits are locals and parameters in `PlacementDebugPanel`, `ProgressionDebugPanel` and `StrategyPhaseManager._gpu_index_of`, and no catalogue-level accessor exists. An arm asserting `CharacterCatalog` publishes no `enemy_units` is proposed in the register — it is what stops the symmetric-overlay shape being re-added by someone who did not read ADR-0078. |
| 3 | Inspection only, and **fragile** — see the Consequences bullet on the pin. `GPUArena` still resolves the ENTD index off the active scenario (`EntdBattle.record(_scenario_entd_idx())`) rather than hardcoding it, which is what keeps the implementation right when the pin is wrong. |
| 4 | `GPUArena._seed_owned_roster` early-returns when `owned_units()` is non-empty, else folds `GarilandMutationScript.owned_seed_deltas()` through `CatalogueReplay.apply_action`. Guarded by `tests/CharacterRosterParityTest.gd` — the overlay is non-empty and its first slug is `GarilandMutationScript.RAMZA_SLUG`. |
| 5 | `FormationScene._roster_characters()` answers `_injected_characters` when injected, else `CharacterCatalog.owned_units()`. Both branches answer the same population, so the one-frame race can only produce a *late* unit, never a wrong one — the property the decision bought. |
| 6 | `tests/FormationMapHostTest.gd` — `character_for_unit`, `slot_number_for` and `selection_is_owned` read no `roster_index` / `roster_team`; those names survive only as prose describing what was retired. Amendment 2 adds the arms for the population the slug lookup could not reach. |
| 7 | `ProgressionDebugPanel._on_reset_cast` is `CharacterCatalog.reset_to_new_game()` + a scene reload. `CombatUITestScene` now lives at `src/ui3/testing/CombatUITestScene.gd` (moved out of `src/scenes/` by extraction #3 — this ADR's original path is stale, its rule is not) and folds the same Gariland seed, spawning through `UnitSpawn.build` / `bind_for_combat`. |

**ADR-0004's surviving half is better enforced than when this was written.**
`tools/check_roster_base_inheritance.py` enforced *extend by path, not by `class_name`*
by NAMING the roster files, so deleting them would have deleted the enforcement of a
convention this ADR keeps alive. It is gone, replaced by `tools/check_path_extends.py`,
which covers every `extends "res://…"` target in the walk whatever it is called — ten
path-extends across five base scripts, against the old guard's two. The ADR's own
example survives: `FormationDetailTransition.gd` declares no `class_name` and both hosts
preload it by path.

**The *Built* findings, re-measured 2026-08-28**, all hold: the `UnitSpawn` seam is the
shared half called from both `GPUArena` and `CombatUITestScene`; `UnitAnimationViewerRoster.gd`
is gone (zero hits) with the record of why kept in `UnitAnimationViewerScene.gd`; and
`StrategyPhaseManager._march_one` breaks on `_MARCH_STUCK_FRAMES` once `seen_walking` is
set or `_MARCH_START_GRACE_FRAMES` has elapsed, with `_MARCH_TIMEOUT_FRAMES` still the
hard backstop.

---

## Amendment 2 — dec. 6's premise is false: the population it resolves against is not closed (2026-09-05)

_Amendment 1 (the 2026-08-28 audit) was FOLDED into the body to make room for this one —
an ADR carries at most one dated section (`tools/check_adr_shape.py`). Its corrections
landed in Consequences and in *Built* §5, its evidence in `## Verification`, and its open
question in the register; nothing cited it. The number is not reused: decision and
amendment numbering here is append-only._

Decision 6 replaced a roster-index lookup with a slug lookup and closed the null-binding defect the
Context describes. It closed **one** population and missed another, the same way and for the same
reason. The Context's diagnosis was *"only `BaseRoster.spawn_unit` sets those metas"* — a writer
problem — and the fix was read as making the key universal. But the key was never the whole
mechanism: a slug is an **address**, and an address resolves through a population. Dec. 6's
unstated premise is the sentence beside it, *"there is now one population to resolve against."*
There is not.

### 1. Measured, on the arena's own cast

A probe over a live `GPUArena` at Gariland, printing what `character_for_unit` returns for every
spawned Unit — **6 of 13 resolved to `null`**:

| unit | team | slug | resolved |
|---|---|---|---|
| Ramza, and the six ENTD-392 cadets | 0 | `ramza`, `entd392_2`…`entd392_7` | yes |
| **Delita** | 0 | `delita` | **null** |
| Squire ×4, Chemist ×1 | 1 | `""` | **null** |

Two distinct causes, neither of them a missing writer — `UnitSpawn.build` stamps
`character_slug` on all thirteen:

- **The ENTD generics have no slug at all.** `Character.from_entd_slot` assigns one only when the
  slot's `special_name` is a known story id; otherwise it returns what `create_default` built, and
  that constructor's own docstring says *"The slug is left empty — it is assigned at Catalog
  promotion from the roster index."* A nameless enemy is never promoted, so the slug stays `""`.
- **Delita has a real slug that nobody registers.** `StoryMutationScript` mints *appearance* deltas
  for exactly this (*"Every named unit a battle's own ENTD spawns enters the Catalog"*), but the
  arena folds `owned_seed_deltas()` — the `own: true` subset, per dec. 4 — and an appearance is not
  one. The ENTD-blue guest this ADR names by name in dec. 2 is the unit dec. 6 cannot resolve.

The visible consequence is the one the Context already names for the retired keying: on
`FormationMapHost` a `null` is indistinguishable from an empty tile. Every enemy, and the guest
fighting beside you, had no vitals panel and no nameplate, and could not be inspected at all.

### 2. Decision — the seam that KNOWS the identity carries it

**`UnitSpawn.build` stamps the `Character` itself** (`CHARACTER_META`, by reference), beside the
slug it already stamps. **`character_for_unit` prefers that reference and keeps the slug lookup as
its fallback.**

The rejected alternative is worth naming, because it is the one that looks like conformance:
*mint slugs for the unresolvable units and register them.* That means minting a positional slug for
an anonymous enemy — `entd388_5` and its kin — which is precisely the `enemy:N` identity ADR-0066
dec. 4 and this ADR's own Context rule out (*"identity = slot — the bug ADR-0066 dec. 4 already
ruled out"*). Making a population closed by inventing addresses for the things outside it re-creates
the defect dec. 1 deleted the rosters to be rid of.

Nothing here demotes the slug. It stays stamped and stays the **durable** key — the one a reader
that outlives the node can use (a save, a log line, a `SlugBinding`) — and it stays the resolution
path for a Unit some other seam built. What changes is that a live node no longer has to round-trip
its own identity through a registry that was never promised to hold it.

Dec. 6 stands as written where it was aimed: `character_for_unit` does not resolve by roster index,
and never will again.

### 3. Consequences

- `selection_is_owned()` now answers about the units it was written for. It degrades to **owned**
  on an unresolvable selection (the roster host's answer), so while resolution was failing every
  enemy read as owned — which is what would have handed the enemy screen live action rows the
  moment it resolved at all. Fixing the resolve without the ownership arm would have traded an
  invisible enemy for an equippable one. Both are pinned in `FormationMapHostTest`.
- **`GPUArena` still does not fold appearance deltas**, so Delita is still absent from the
  catalogue there. That is now a catalogue-completeness question rather than a UI one, and it is
  left open deliberately: this amendment makes the screen right without deciding whether a
  no-navigator host should replay a story action. `CharacterCatalog.classify` and anything else
  that reads the catalogue by slug still cannot see him.
- The guard fixture that hid this is corrected in the same commit. `FormationMapHostTest`'s
  "ENTD enemy" probe built its stranger by *registering* a Character and leaving it out of the
  owned overlay — a shape no ENTD unit has — so the arm passed through the defect it was written
  to catch.

Built 2026-09-05 alongside ADR-0137 Amendment 9, which is the user-visible half.
