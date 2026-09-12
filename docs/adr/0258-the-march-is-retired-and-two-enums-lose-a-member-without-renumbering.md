# The deployment march is retired, and two enums lose a member without renumbering

`GPUArena` ran a **deployment march**: units auto-filled onto their scenario spawn
tiles, then walked — on the GPU mover, as a non-combat phase of the combat simulator
(ADR-0042) — to a **contested tile**, a procedurally scattered objective with no FFT
equivalent (ADR-0043 addendum). It was the game's first answer to "how does a unit
take the field", and the user's own verdict on it is *"just our first iteration of
deployment."*

#892 built the second answer. `GambitBattle` deploys the FFT way: a squad chosen
against a cap, placed on the deployment zone, committed. #941 gave it a picker, and
the precondition this ticket set itself — *do not retire the march on the strength of
a host nobody has played* — was discharged by **observation**: the user ran
`GambitBattle.tscn` headful, opened the picker on a zone tile, deployed, and signed
off. Two systems then claimed the word *deployment*, one of them dead.

This ADR retires the march. It also repairs two enums, because the retirement is what
exposed them.

## Status

accepted. **Renumbered TWICE on 2026-09-07 — 0254 → 0255 → 0258 — and the second time is
the interesting one.** `main` took 0254 for #1020's *"an unattended loop may delete a
test"* while this branch was being built; the renumber to 0255 was pushed, and `main`
then took **0255 too**, for #1021's *"the gambit surface is three levels of one list"*.

Both numbers were verifiably free when claimed — all 24 worktrees and every ref, which
is exactly what `CLAUDE.md` and #886's Notes ask for. **Scanning harder is not the fix,
because the scan is not the race.** The window is between claiming a number and pushing
it, and nothing closes it: two sessions can both scan a clean tree, both pick the same
next integer, and only one can land. ADR-0247 records the same collision at 0172, and
the merge commit that took 0254 is itself titled *"ADR-0244 collision resolved"* — this
is the fourth recorded instance, and the second and third happened to the same branch
inside one afternoon.

0258 was chosen by reading the OPEN PRs rather than the merged tree: 0256 is claimed by
PR #1023 and 0257 by PR #1026, neither of them merged and neither visible to a scan of
`main` or of any worktree. That is the mitigation this ADR can offer from inside the
problem — **check `gh pr list` for claimed numbers, not just the filesystem** — and it
is still a mitigation, not a fix. The fix is a number that is allocated rather than
guessed, and that is somebody's ticket, not this one's.

## Decision

1. **The march is retired outright — no debug path, no flag, no deprecation window.**
   `StrategyPhaseManager`, `PlacementPhaseController`, `PlacementTileHighlighter`,
   `PlacementInputHandler`, `AIPlacementController`, `PlacementTileSet`,
   `ScenarioPlacementSource` and `PlacementDebugPanel` are deleted, along with
   `StrategyPhaseTest`, the `use_strategy_phase` export, the `--skip-strategy` flag and
   the `simulation.skip_march` tunable. A deletion cannot be proved by seeding a defect
   away from it — the PR **is** the seed — so a staged retirement would have left six
   tests exercising a system already declared dead. Retiring it in one commit is what
   makes "does anything need this" a question the suite can answer.

2. **`GPUArena` KEEPS ITS JOB and is not scheduled to die.** It is the project's
   `run/main_scene`, the `--stress-units` perf rig, the host `tools/perf/run_*.sh` and
   `run_scene_smoke_tests.sh` boot, and the state three GPU subclass tests read off.
   Retiring the march did not require retiring the arena, because the arena **already
   placed FFT-accurately without it**: `_place_units_at_defaults()` puts the owned side
   on the zone via [DeploymentPlan.assign] (capped by `max_squad_size`) and everything
   ENTD-spawned on its authored slot tile. That branch was reachable only behind
   `--skip-strategy`; it is now the only branch. **Nothing had to be built.**

   This is stated positively and on purpose. #942 exists because the march had an
   *implied* death, and leaving the arena's future unsaid would reproduce that defect
   one level up. `GPUArena` is the boot scene, the perf rig and a test substrate. If it
   should die, that is a ticket someone files with a reason — the standard this ADR
   held the march to.

3. **`GambitBattle` keeps sole ownership of the interactive deployment.** The arena
   does not get a picker. A second host owning that screen is the screen fork ADR-0252
   refused in as many words, and "adopt the squad deployment" is answered as **adopt
   the placement, not the screen**.

4. **`CellMarking.Kind` loses `PLACEMENT_CONTESTED` and 3 becomes a HOLE.** Renumbering
   4/5/6 down is exactly the silent renumbering that enum's own 🔴 comment was written
   to forbid — the values are `Tile.HighlightType`'s declaration order carried verbatim
   by ADR-0196 dec. 6.

   The hole is only safe because of the repair that comes with it.
   `TileOverlayConfig.param_slug` was `"tile.%s.%s" % [Kind.keys()[type].to_lower(), key]`
   — it indexed the **names** array by the **value**, which is correct only while the
   values are dense. Under a hole at 3, `keys()[4]` returns `"PLACEMENT_UNAVAILABLE"`
   while 4 is `CURSOR_ACTIVE`: every surviving tunable slug would have re-pointed at the
   wrong marking, silently, and `type_enum_name` with them. Both move to
   `Kind.find_key(type)`. **This is a latent defect the deletion merely exposed** — the
   density coupling was wrong before any member left, and `find_key` is the correct
   derivation whether or not one ever does.

5. **`PlacementTileGenerator` is renamed `PlacementPolicy`, keeping 81 of 293 lines.**
   What dies is the procedural board — two flood-grown islands and Poisson-disc contested
   sampling, ADR-0043's retained fallback, whose only consumer was the march. What
   survives is `placement_cells()` / `_get_valid_placement_cells()` /
   `_is_valid_for_placement()`: ADR-0192 dec. 6's water rule, `Battle`'s answer to *may a
   unit stand here*, still read by the `--stress-units` fixture. A class called
   `Generator` whose generating half has been deleted is a name that costs every future
   reader a file-open. It stays in `src/strategy/`, which keeps
   `classify_blueprint.py`'s `src/strategy/ → Battle` rule true with no bucket change.

6. **`src/strategy/` does not lose its reason to exist** — the ticket's fourth question
   rested on a premise that was already false. #892 put `DeploymentAssignment` and
   `DeploymentPlan` there and they are the *new* deployment. The directory survives by
   construction; it loses the march and keeps three files.

7. **`CombatLoop.deploy_active` dies, and the tick gate returns to `combat_active`
   alone.** ADR-0042's central mechanism was the simulator ticking outside combat, and
   the whole surface it needed — `set_deploy_move`, `grant_deploy_jump`,
   `restore_combat_jump`, `clear_unit_gambits`, `is_unit_idle_at`, `is_unit_idle`, and
   the axis itself — had `StrategyPhaseManager` as its **only caller in the tree**.
   Keeping the boolean "in case something wants it" is a hook with no caller, and
   `GambitBattle` is the standing proof nothing wants it: its deployment is CPU-side
   precisely because the GPU battle does not exist until commit (ADR-0242).
   `GPUBatchSimulator.set_unit_jump` went with it, having lost its last caller.

   The **boot/arm split survives its own author**: `boot_battle` and
   `arm_combat_gambits` are still two calls because `NavigatorMain` still uses them
   separately. ADR-0042 built that split for the march and it outlived it.

8. **`DebugOverlay.Category` loses `STRATEGY` the same way — a hole at 6, values
   written out, in all THREE copies.** The enum is declared verbatim in
   `DebugOverlay.gd`, `DebugDashboard.gd` and `BaseDebugPanel.gd`, which must agree
   integer-for-integer because a panel sets `panel_category` from one copy and is looked
   up by that integer through another. It had **implicit** values, and
   `DebugConfig.debug_overlay_active_tab` persists a tab as a bare int.

   ⚠️ This was caught mid-build, not designed: deleting the member from the
   implicitly-valued `BaseDebugPanel` copy alone **renumbered `ROSTER`…`STORY` in that
   copy only**, routing every panel below the hole to the wrong tab with nothing to say
   so. `TAB_NAMES` was a positional `Array[String]` with the same coupling and is now a
   `Dictionary` keyed by the enum, which is what the panel registry `_panels` already
   was.

9. **ADR-0166's holder count is re-measured here, because this moves it.** Its table
   lists holder 2 = `PlacementTileSet.get_tile_ownership()` and holder 3 =
   `PlacementTileSet.claimed_tiles`. Deleting `PlacementTileSet` deletes **both**. Its
   headline — *"occupancy is `Battle`'s in five spellings"* — and its own results table's
   4 both go to **2**: the deployment claim (now `DeploymentAssignment`) and
   instantaneous standing (`is_tile_occupied`, derived per tick). That is exactly the
   two-claims-two-arbiters shape ADR-0166 dec. 5 argued for, reached by deletion rather
   than by collapse. A future reader should not budget for a six-holder collapse that is
   already most of the way done.

10. **The glossary retires the dead terms outright, with no tombstone.**
    `docs/context/` is a domain model of what the game *is*; a retired-concept entry
    there makes the vocabulary describe a game that no longer exists, and this ADR is
    where the history belongs. **Deployment march** and **Placement tile** are deleted;
    **Deployment zone** and **ENTD** lose their march tails ("*spawn* tiles … then march
    to a contested objective" becomes "**start** tiles"); the phase's own opening now
    says there are **two** strategy phases in two hosts, auto-placing and picker-driven,
    and neither walks anybody anywhere. **Deployment plan** is coined for
    `DeploymentPlan`, which had no entry and is now the arena's whole placement.

    Retiring the march also **removes one of three meanings of "march"** in this tree.
    The two that remain are unrelated to it and to each other: *march-idle*, an activity
    (`NavigatorMain`), and `ScenarioApply.march`, the ROM's opcode 0x80.

## Rejected

**Retiring `GPUArena` entirely.** The ticket offered it, and it is the expensive
option: it means moving `run/main_scene`, `run_scene_smoke_tests.sh`, the bootstrap
doc and three perf scripts onto a host with no `--stress-units` lever and no perf
instrumentation. None of that is work the march's death requires.

**Keeping the march as a debug path.** It is 1,800 lines and a `CombatLoop` axis to
preserve a system nobody will run, and six tests would keep booting through it.

**Preserving the walk-in as a visual.** Severable from the contested objective, and
tempting — the GPU sim as a non-combat mover is a real capability. Its cost is the
entire `CombatLoop` deploy surface plus booting the simulator *before* placement, and
`GambitBattle` deliberately does the opposite: the GPU battle does not exist until
commit, which is what makes "placements are CPU-side" true by construction rather than
by discipline. An arrival animation, if it is wanted, is a CPU-side presentation
gesture like `FormationPickIn` (ADR-0249) and a new ticket — not a survival clause on
a retired system.

**Keeping `PLACEMENT_CONTESTED` as a reserved schema member**, and keeping
`Category.STRATEGY` as a producer-less tab. Both are the "code with no observable
consequence" shape — the same defect as an assertion with no behaviour behind it, read
from the other end.

**Renumbering either enum to close its hole.** Slug derivation would have survived a
`CellMarking` renumber (name and value shift together), but the 🔴 comment forbidding
it is load-bearing and the persisted debug tab would have moved silently.

**A ratchet guard that the retired names can never return.** It would ship with an
empty population and could only fire on a resurrection nobody is attempting. Numbers
are the stronger instrument here because they are falsifiable by re-running the
measurement. The counter-argument is real and recorded rather than hidden: ADR-0251
dec. 3 praised a burn-down seeded empty in the commit that created its directory. The
difference is that a burn-down guards a live invariant over a live population; this
would guard an absence.

**Deleting `GPUSeedReproTest`'s placement arm and `ScenarioPlacementDataTest`'s
`can_source` arms.** Both had their subject retired under them, and deleting a test
because its subject moved is how coverage evaporates silently. They are re-aimed
instead — see Consequences.

## Consequences

**Measured: 63 files, 433 insertions, 2,999 deletions.** The largest single deletions
are `StrategyPhaseManager` (513), `StrategyPhaseTest` (405), `GPUArena`'s strategy
region (390 of its 430 changed lines), `PlacementTileGenerator`'s procedural half (212
of 293), `PlacementPhaseController` (198) and `PlacementDebugPanel` (161).
`CombatLoop` loses 105 lines and gains 17 of prose about why the gate narrowed.

**Six tests booted through the march, not the three the ticket named.**
`GPUItemFallthroughTest`, `GPUSnapshotUnionTest`, `GPUTeleportTest` and `GPUThrashTest`
set `use_strategy_phase = true` explicitly and simply lose the line.
`CursorConfirmEndToEndTest` deliberately left it at its **default** — its docstring
said the march was the thing it refused to fake — and `StrategyPhaseTest` drove
`PlacementPhaseController` directly. Only the last is deleted.

**`CursorConfirmEndToEndTest` is re-aimed, not dropped.** Its unique coverage is the
*input path* — a real `InputEventKey` through the real `InputMap`, the cursor's
`_unhandled_input` gate and its swallow — and that is untouched by any of this.
`_test_confirm_during_march` and `_test_march_is_transient` go with their subject; the
inspect arm loses its march precondition and keeps its claim, because "looking at a
unit has no host-specific reason to be refused" is a rule about every future phase.
`_first_undeployed_player_unit` becomes `_first_player_unit`: with the march gone,
every unit is placed at boot.

**`GPUSeedReproTest`'s level 1 is narrower, and the narrowing is stated in the file.**
It ran `PlacementTileGenerator.generate()` and `AIPlacementController`, both retired.
`PlacementPolicy` is deterministic *by construction* — it draws no random numbers — so
the arm asserts what the surviving code actually has: same lattice, same cell set, plus
the seeded `battle_seed` draw that feeds level 2. It now **fails on an empty cell set**,
because "identical" over zero tiles is a run that examined nothing.

**`ScenarioPlacementDataTest` gained a stronger arm than the two it lost.**
`can_source` asked *may we source this scenario, or fall back to a procedural board* —
and the fallback is retired. Scenario sourcing is no longer one of two modes; it is the
only way a unit reaches a tile. So the arm now walks the whole scenario corpus and
asserts that **every non-zero `first_squad_deployment_idx` resolves to a zone with
tiles**, printing how many it examined so an empty verdict cannot read as a clean one.

**`TileOverlayCompositorTest`'s routing arm keeps four members, not three.**
`PLACEMENT_CONTESTED` was its third *routed* case; `PLACEMENT_UNAVAILABLE` (blend 0,
average) takes the slot as a second *in-scene* case, so both sides of the routed
split still have two members and the arm is not weaker for the deletion.
`TileHighlightsTest`'s two arms used contested as an exemplar of a placement kind and
now use `PLACEMENT_ENEMY`; its "all four are one statement" becomes three.

**Guards touched:** `tools/check_focus_anchor.py` loses its
`src/strategy/PlacementInputHandler.gd` grandfather entry — that list can only shrink,
and it detects its own staleness (`gone = GRANDFATHERED - have`), so the deletion would
have reported it. `tools/check_highlight_writer.py` needed nothing: its scan is a
`walk_roots()` over `src/`, `tests/` and the addon roots, and only its docstring's
*history* names `StrategyPhaseManager` — which is why the guard exists and stays.
`tools/delete_dead_code.py` and `tests/run_all_tests.sh` lose their `StrategyPhaseTest`
entries. `tests/lib/verdict.sh` keeps its mention: that is an archived measurement over
five recorded runs, not a claim about the tree.

**One orphan removed that no guard would have caught:** `config/tune_overrides.json`
carried a persisted `simulation.skip_march: false` for a slug nothing binds any more.

**Supersession.** ADR-0042 is superseded outright — its subject was the march. ADR-0043
is superseded only **in part**, and the surviving part is *strengthened*: its
scenario-sourcing decision stops being one of two modes and becomes the only one. Its
procedural fallback and its contested-tile addendum are retired.
ADR-0166 gains a pointer to decision 9 above.

**WITNESSES.** Pre-flight: every static guard passes, after clearing four aborts one at a
time (the pre-flight exits at the first, so each fix moved it to the next) — a dead
`classify_blueprint` DEBUG_OWNER rule left by `PlacementDebugPanel`, two
`check_addon_globals` citation failures from this ADR's own docstring rewrites, and one
`check_lattice_doors` abort that was NOT REAL: it came from two pre-flight runs left
overlapping, and the guard exits 0 run alone.

Full parallel suite **738 / 753**, 16.4 min, zero HUNG, zero CRASHED. Every one of the
15 non-passers was re-run SOLO: **13 pass solo** (contention — peak 22 of 24 cores, and
the GPU reds carry DIFFERENT NAMES between the two runs, which is the signature), and
the **2 that fail solo are the standing trunk reds** — `EventPathfinderTest` (#909, which
is also the only reason `stranger:exmateria_battlefield` scores FAIL) and
`AllTemplatesSeederTest` (#991). No red on this branch is a code defect from it.

The first full run found **three** real defects, and they are the reason a deletion needs
a suite rather than a reading. `GPUVisualBridgeInterpolationTest` still set
`use_strategy_phase = false` — the ONE opt-out pointing the other way, which is exactly
how it survived a sweep of the `= true` sites. `CombatCameraMountTest` 117 → 116 and
`ProceduralMapMountTest` 120 → 119, because `tests/StrategyPhaseTest.tscn` instanced BOTH
mounts: **the first decrement either pinned count has ever taken**, every prior line in
both histories being a bump. A falling number is precisely what those pins exist to make
somebody explain.

That first run also produced six reds that were NOT this branch: `GambitBattleTest`,
`GambitDeploymentPickerTest` and `AdjustmentTurnTest` HUNG on a **stale `.godot` class
cache**, because rebasing onto a `main` that had just gained `src/gpu/AdjustmentTurn.gd`
(ADR-0252) left `GambitBattle.gd` unable to parse and took its rigs with it.
`godot --path . --import` cures it; `AdjustmentTurnTest` is 51/51 immediately after.

**RE-VERIFIED against a `main` that moved 117 commits mid-PR** (which is also what took
this ADR's original number — see Status). Pre-flight green again after three more reds,
and the shape is worth recording: **two of the three were guards that did not exist when
this branch was cut.** `check_test_charter` arrived with the merge carrying an allowlist
that MAY ONLY SHRINK, so the deleted `StrategyPhaseTest` left two stale rows (C1, C10) —
removing them takes the burn-down 1439 → 1437, the only direction it is allowed to move,
and is the ratchet working rather than failing. `check_blueprint_walk` then found one
unclassified file, `src/_publish_seed.gd` — **not this branch's**: it is
`tools/test_check_lattice_publish.py`'s seed, orphaned when an earlier suite of mine was
KILLED mid-run and its cleanup never ran. A killed suite leaves the tree dirty in ways
the next guard reads as a defect; that is worth knowing before chasing one.

Full suite on the rebased tree: **738 / 752**, 11.1 min, and all three fixes above hold —
both mount ratchets, `GPUVisualBridgeInterpolationTest` and the entire Gambit cluster are
green. The 14 non-passers are the same known population: 12 pass solo (the HUNG one,
`GPUTargetDiedMidWalkTest`, is a name that appeared in NO other run — different names each
run is the signature) and the 2 that fail solo are #909 and #991 again.

**Headful, both scenes, after the deletion.** `GPUArena.tscn` (the boot scene, whose
behaviour this changes) prints `Units placed: 5 owned on deployment zone 256, 6 on ENTD
tiles, 0 stress, 2 spread` — Gariland's 8-tile zone at cap 5 against a 7-unit owned
roster, so 5 stand on the zone and 2 fall to the straggler spread, with the ENTD's 6 on
their authored slots. `GambitBattle.tscn` prints `Zone 256: 8 tiles, squad cap 5, 7 units
available` and opens its deployment. Neither emits an `ERROR:` or `SCRIPT ERROR`; the
five `StatusEncoder` warnings (#99) are printed identically by trunk.

**Soft spots.** The arena's boot is now unbranched, which means a scenario whose
deployment zone fails to resolve has no fallback — it warns and spreads the owned side
onto an invented row. That is *why* `ScenarioPlacementDataTest` grew the corpus-wide
arm, but the arm checks the DATA, not the resolution to a live tile, and the coord→tile
step is still verified only headful. And decision 2's positive statement about
`GPUArena` is a decision, not a measurement: nothing enforces that the arena stays the
boot scene, and the next session to move `run/main_scene` will not be stopped by
anything but this paragraph.
