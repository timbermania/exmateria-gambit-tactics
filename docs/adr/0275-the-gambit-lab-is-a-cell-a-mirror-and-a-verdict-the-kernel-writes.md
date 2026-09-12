# The gambit lab is a cell, a mirror, and a verdict the kernel writes

A gambit that does not fire is silent about why. `evaluate_gambits_up_to`
(`src/gpu/shaders/stage_compute.glsl:783-893`) has **ten distinct failure points**, and
until dec. 4 landed in #1126 **one** of them stamped a reason — `REASON_GAMBIT_FAILED`, at
`:651-652` — which each later slot's attempt overwrote. `check_gambit_conditions`
(`:747-778`) returned `false` on the first failing condition and discarded which one it was
and what it measured. All the host could see was `U_CURRENT_GAMBIT` (which slot won, or
`-1`) and one coarse `REASON_*`.

So rule group B — fall-through, where the most user-visible gambit bugs live — is debugged
by inference. The 84-scenario corpus (`tests/gambit_scenarios/`) can say *what* fired. It
cannot say why the earlier slots declined, and no number of additional fixtures changes
that, because the reason is computed on the GPU and thrown away.

This ADR records the instrument that answers the question, and the six measurements that
shaped it. It is a **development instrument, permanently** — it never ships.

## Status

accepted

Does not supersede anything. Argues at dec. 12 that
[ADR-0264](0264-gambit-battle-is-a-seek-into-the-navigator-not-a-second-combat-host.md)
does not reach this host, and repairs an unmarked contradiction between ADR-0264 and
[ADR-0242](0242-the-gambit-host-boots-from-one-integer-and-the-gpu-battle-does-not-exist-until-commit.md)
dec. 1 as a side effect.

Verified 2026-09-11 — dec. 25-29 built and refereed by `--shot` (the mount draws; `SPACE` steps
the tick after ✕ closes the surface and does not step while it is open); dec. 30-33 built and
refereed by synthetic key drive (`Input.parse_input_event`) across the fixture/cell seam (at the
last fixture, 92/121 `E2/mixed_unsupported_middle_slot_does_not_brick_fallthrough`, `N` lands on
93/121 `cell/COND_ALWAYS/positive`; `B` onto `cell/COND_IS_DEAD/positive` reports REFUSED and
boots nothing; `cell/COND_MP_ABOVE/mirror` scores at tick 1, 2 predicted field-sets held, 0 did
not). dec. 20's panel-fallback clause is spent. One production defect fell out of dec. 27 and was
fixed where it lived, not in the lab: `FormationDetailTransition._exit_gambit` returned to a MAIN
formation menu when the stack emptied, contradicting `_input`'s own rule that a map has no plain
roster — unreachable until a host entered `State.GAMBIT` off the bottom of the stack.
dec. 34-35 refereed by twelve `N` presses one frame apart: before — `Out of bounds get index '1'`
and `'2'` from `CombatLoop.gd:601`, five times in twelve; after — no error, and the positive
control holds (the last press lands a live 3-unit battle that ticks, with zero orphans).
dec. 17's clone and dec. 36-37 refereed by synthetic key drive (`1` on a fixture refuses and names
`F` as the way in; `F` forks B7's three units; `1`/`2` add at the cursor; `J` cycles the job; `M`
moves; `X` deletes; `G` opens on a scratch unit; the cell steps; and B7's own slot 0 still reads
`[Any Enemy] HP < 50% → Attack` afterwards). dec. 38-40 refereed against a live
`--combat-autostart` battle: 11 rows (Ramza, Delita, the ENTD Squires and Chemists) with live
state/target/HP/position, the watched unit's six slots decoded, and the cursor walk moving
`watched` 0 → 8 — and the first thing it showed is a finding rather than a demo, recorded at S6.

## Decision

### The subject

1. **The primitive is a CELL: one actor, exactly one dummy, one condition, one boot.**
   Not a tableau holding one dummy of every kind. A crowded scene's answer is *joint over a
   population* — the pick cannot be attributed to the axis under test without also reasoning
   about every other dummy, and AoE splash (`effect_area`), reactions and ADR-0048's injected
   net all interact. An ambiguous reading from a debugging instrument is worse than none.

   🔴 **AMENDED by #1129, and the amendment is a MEASUREMENT: "exactly one dummy" means one
   dummy IN THE AXIS'S POOL, not one unit on the field.** An ally-pool cell cannot be run with
   two units. `cell/COND_IS_ALIVE/positive` was built that way -- actor and ally dummy, both
   team 0 -- and the trace **ended at tick 1** with every slot of both units reading
   `NONE(not walked)`: `check_victory` returns `RESULT_TEAM_0_WINS` the instant
   `team1_alive == 0` (`stage_victory.glsl:48`), and the actor's first turn is 29 ticks later at
   Speed 120. That is not a failed prediction, it is a BLIND RUN, and dec. 18's trap is exactly
   that a zeroed field is indistinguishable from "nothing declined".

   So an allied cell carries **one inert opponent** at the board's far corner, `move: 0`,
   `speed: 1`, out of reach of every action in the catalogue. This does not weaken the decision,
   because the property the argument above actually turns on is preserved: the axis's pool still
   holds exactly one candidate, so the pick is still attributable to the axis. What the opponent
   is in is ADR-0048's safety-net pool, and dec. 19 already requires that to be LABELLED rather
   than suppressed -- so the cell's expectation names the net's row and predicts it.
   `GambitCellSynth._liveness_opponent` carries the argument and the placement.

2. **Every positive cell auto-generates its MIRROR** — the same cell with the dummy moved to
   the other side of that condition's boundary. A pair that fails to flip is a defect
   regardless of what anyone expected, which makes the instrument self-checking, and it
   scales to the ability table without hand-authoring. A **ladder** cell is the third shape:
   slots 0..N-1 must each decline *for the reason the lab predicted* before slot N fires —
   "slot N fired" alone is not a pass.

3. **The subject is the DECISION and the OUTCOME, with unimplemented formulas marked.**
   ~17 formula ids are handled in `combat_combat.glslinc`; the rest fall to "use Y as-is". An
   unmarked damage number from an unimplemented formula is a false claim that will be believed
   six months from now.

### The verdict the kernel writes

4. **The kernel writes a per-slot verdict into `GM_RESERVED_14`/`GM_RESERVED_15`**
   (`combat_common.glslinc:882-883`) — two free ints per gambit slot per unit per battle,
   **zero buffer growth**, and exactly the per-slot shape the question has.
   Int A packs the failure point; int B is the **measured payload** — the number that lost.

   The payload is the point. `condition_false, actual 62%, threshold 50%` ends an
   investigation; a fine per-opcode enum (`COND_HP_BELOW_FAILED`) restates what you already
   knew and must be maintained in lockstep with the opcode table forever.

   The `evaluated_mask` is what stops the readout misleading: "condition 2 failed" without
   knowing 0 and 1 passed reads as if 2 were the only one checked. Only the **first** failure
   is reported, because the kernel genuinely stops there — conditions after it have no answer.

   **Int A carries ONE VERDICT PER PASS, not one verdict.** `evaluate_gambits_up_to` walks
   every slot twice, and a single field reproduces the exact defect this ADR exists to
   remove: pass 2's `NOT_RETRYABLE` would overwrite pass 1's real reason for precisely the
   slots whose reason is most wanted. So bits 0-15 hold pass 1's
   `{verdict, condition_index, condition_opcode, evaluated_mask}`, bits 16-30 hold pass 2's
   `{verdict, condition_index, condition_opcode, rank_reached}`, and pass 2 merges rather
   than stores. Pass 2's evaluated mask is the one field dropped for width, and pass 2 does
   not write int B — for a nearest-type slot pass 1 *is* rank 0, so int B already carries
   that slot's payload. Rank is clamped to 0-7 because `find_nth_nearest` has a hard
   `int unit_ids[8]`. Bit 31 is left clear so the host reads a non-negative int.

   **Every slot the call will walk is CLEARED first** (int A only; `VERDICT_NONE` makes the
   payload meaningless). A verdict left over from an earlier evaluation is indistinguishable
   from "this slot never declined" — dec. 18's trap, and the one failure mode a debugging
   instrument must not have. Slots at or past `max_slot` are left alone: the movement
   re-evaluation path passes `current_gambit`, and the executing slot's verdict is not that
   call's to erase.

5. **`GambitData` is no longer `readonly`** (`combat_common.glslinc:708`), and that is a real
   cost stated out loud: it *was* a compiler-enforced guarantee that a unit's gambit program
   cannot be modified mid-tick, and it is now a convention that every future reader of that
   buffer must respect. What is written is the verdict and nothing else. The buffer stays
   single-buffered; each thread writes only its own unit's slots and nothing reads them within
   the tick, which is the argument the cooldown buffer already makes at
   `stage_compute.glsl:705-714`.

6. **The layout is addressed `(battle, unit, slot)` — fleet-shaped — and the WRITE is
   unconditional; it is the lab's READ that is scoped to one actor.** The rollout runs the
   **same kernel entry point** (no rollout pipeline, no `#define`, no per-battle active mask),
   so a layout addressed only to one unit would make the rollout debugger a kernel redesign
   instead of a gate flip. Gating is cheap; the layout is not, so only the layout is bought up
   front. The address costs nothing to get right: `gambit_data` is already indexed by
   `global_unit_id = battle_id * units_per_battle + unit_id`, so the fleet is covered for free.

   🔴 **Repaired here, and it is the same defect this ADR repairs between ADR-0264 and
   ADR-0242.** This decision used to read "gated to the lab's single actor at first", which
   contradicts dec. 7's "ships always-on" without naming it, and #1126's ticket text inherited
   the wording. A gate on the write is not merely unbought — it is **incompatible with dec. 7**,
   because a bench arm measuring a write that the rollout fleet never executes measures nothing
   and returns a guaranteed pass. Dec. 7 is the decision; this one now agrees with it.

7. **It ships always-on. THE MEASUREMENT CAME BACK UNDER THE THRESHOLD (#1126), so no gate
   was bought.** Four physically distinct shader arms, Latin-square interleaved, in a pinned
   worktree of their own: the verdict's run-leg delta is **−0.15%** position-matched at
   `battles=256 units=32 horizon=300` (n=16) and **+1.56%** at its worst on any config in any
   round — against a 5% gate. Dropping `readonly` alone costs nothing measurable either
   (+0.34%). The threshold and its derivation, kept because it is what a future change is
   measured against:

   **It ships always-on, and the gate is bought only if a MEASUREMENT demands it — threshold
   fixed here, before the number exists.** `tests/GPURolloutBudgetBench.gd` (already emits
   `BENCH_ROW` CSV for the fill/run/score legs), run **interleaved A/B/A/B/A/B**, three
   repeats per arm because a wall-clock A/B is monotone in machine load rather than in the
   diff. **Gate if the run-leg median regresses more than 5%.**

   5% is not arbitrary: the rollout predicts ~138 ms against a 250 ms cap (~45% headroom), so
   5% is far below anything that endangers the cap and well above interleaved noise. A
   regression above it means the write is *structurally* wrong — a non-uniform branch, a
   buffer hazard, a lost coalesce — not merely costly. A spec-constant two-pipeline variant is
   rejected up front: two compilations of the AI kernel is a guaranteed divergence bug, where
   the one you debugged is not the one that ships.

### The synthesizer

8. **The boundary of each condition comes from a hand-authored STRADDLE TABLE**, one row per
   encodable opcode, guarded by a test that fails when a new opcode appears without a row.
   A generic "perturb the operand by ±1" is rejected — it manufactures false negatives
   silently, the worst failure mode available to a debugging instrument.

9. **An opcode with no straddle produces the positive cell only, labelled "no negative case
   available".** `COND_ALWAYS` is structurally unstraddleable. `COND_IN_RANGE` straddles
   differently per attack type — for `ATTACK_STRIKING` the range is *exactly 1*, so nearer and
   farther are **both** negative. An instrument that says "I cannot test this" is worth more
   than one that quietly tests something else, and the refusal count is a to-do list.

   🔴 **#1129 FOUND A THIRD UNSTRADDLEABLE CLASS THIS DECISION DID NOT NAME, and it is
   not a gap in the synthesizer: `COND_IS_DEAD` and `COND_IS_ALIVE` CANNOT BE SEEDED AT ALL.**
   `is_unit_dead` reads `FLAG_DEAD` in `U_FLAGS` (`combat_common.glslinc:1092-1094`), and
   `FLAG_DEAD` is written in exactly two places: `stage_damage.glsl` on an actual damage event,
   and `GPUBatchSimulator:1183` marking UNUSED slots. The battle spec
   `GambitScenarioBoot.build_battle_spec` builds has no `flags` channel, and `hp: 0` flags
   nobody. `COND_IS_DEAD`'s positive cell and `COND_IS_ALIVE`'s mirror are therefore both
   REFUSED -- and refused rather than the spec widened, because a battle cannot begin with a
   corpse on the field either, which is dec. 22's own argument against exercising battles that
   cannot exist. `COND_IS_ALIVE`'s positive still builds and is labelled VACUOUS: it passes for
   every unit in every battle, so the label is the whole value.

   🔴 **AND THE `ATTACK_STRIKING` CLAIM ABOVE IS TRUE OF THE PREDICATE AND ONLY HALF
   BUILDABLE ON THE BOARD.** `check_striking` rejects `h_distance != 1`, so nearer and farther
   are both negative as stated -- but "nearer" is separation 0, which needs two units in one
   cell. ADR-0224 dec. 6 makes occupancy a CELL rather than a column, so that geometry exists
   under a bridge; MAP116 (dec. 11) is single-level and has none. The near mirror is REFUSED and
   counted, which is the first entry on the to-do list this decision promises.

10. **An unplaceable cell REFUSES and is counted; it is never nudged.** A nudged dummy still
    produces a verdict, and that verdict now describes a different experiment from the one on
    the label — it fails *productively*, which is why this is the most dangerous option here.

11. **Synthesized cells are placed on MAP116; existing fixtures replay on their OWN maps.**
    MAP042 — 67 of the 84 fixtures — **cannot host a controlled-distance experiment**:
    heights 0-16 half-steps, largest fully-flat Manhattan disk **radius 1**, and at 10 tiles
    wide `min(x, 9-x, z, 14-z)` maxes at **4**, so r=8 cardinal placement is *geometrically*
    impossible at any height. MAP116 is 11x11, 121/121 walkable, uniformly height 0, with
    complete flat rings to r=10 — the only map of 119 with a flat disk above radius 3
    (histogram `{0:10, 1:90, 2:13, 3:5, 5:1}`).

    ⚠️ **MAP116 IS STILL BOUNDED, AND NOT BY THE NUMBER THAT SENTENCE LEAVES IN THE
    READER'S HEAD.** The Manhattan maximum from (5,5) is 10, but it is reached only on the
    DIAGONAL -- the corner. The greatest **cardinal** separation is **5**. Every straddle that
    needs the actor and dummy on one line is bounded by the second number, not the first:
    `check_lunging` rejects `ax != tx && az != tz`, so a lunging weapon of range 6 or more has no
    buildable cell here and is REFUSED. Measured by #1129
    (`GambitCellSynth.MAX_CARDINAL`, derived from the origin rather than written down).

    Re-hosting an existing fixture onto MAP116 is rejected: 46 of the 84 use plain `ATTACK`,
    which routes through `can_attack_target` and is height- **and** line-of-sight-sensitive,
    so the same tiles on a flat map are a different test and the fixture's recorded verdict no
    longer refers to what ran.

12. **Throw range is straddled by setting the ACTOR'S SPEED**, recorded in the cell spec.
    Throw is not in the attributes table — `GPUAbilityLoader.gd:114-116` writes a nominal 4 and
    the shader overrides with `speed / 2 + 1` (`combat_common.glslinc:1328-1331`), unbounded
    above. Varying Speed is the only way to reach that boundary at all, and unlike dec. 10's
    nudge it *defines* the quantity under test rather than corrupting it.

    ⚠️ **AND IT MAKES THE ACTOR 15x SLOWER, WHICH A FIXED TICK BUDGET WOULD HAVE READ
    AS A BLIND RUN.** `speed / 2 + 1` inverts to `speed = 2 * (reach - 1)`, so a boundary at
    separation 5 needs Speed 8 and the board's diagonal maximum of 10 needs Speed 18.
    `compute_unit_state` adds `max(1, U_SPEED)` to the turn meter per tick against
    `TURN_METER_FULL` (3600), so a Speed-8 actor reaches its first turn at tick **450** where a
    Speed-120 actor reaches it at **30**. On an 11x11 board there is therefore no throw boundary
    a normally-fast unit can straddle at all. #1129 derives each cell's tick budget from its own
    actor's Speed (`GambitCellSynth.ticks_for_speed`); a constant would have made every throw
    cell report `NONE(not walked)` and the conclusion drawn would have been about this decision.

### Structure

13. **Two pieces, split on the fleet/live line.** A **fleet sweeper** with no host at all — a
    `RefCounted` driving `GPUBatchSimulator` directly as `RolloutHarness` does — in `tools/`,
    beside its structural twin `tools/rollout_corpus.gd`. And a **thin `CombatHost` subclass**
    for the live arm in `src/scenes/`, panel in `src/debug/`, on the precedent of
    [ADR-0069](0069-effect-studio-is-a-standalone-development-window-not-a-debug-panel.md) —
    *"Effect Studio is a standalone development window, not a debug panel"* — which is this
    same shape decided once already for the effect authoring tool.
    The synthesizer and straddle table are a pure function in `src/gpu/` — putting them under
    `tests/` would mean production code can never consult them.

    The sweep must not be N sequential boots: each scenario builds a **fresh `CombatLoop` ->
    fresh local `RenderingDevice` -> all 8 pipelines** (`CombatLoop.gd:480-504`), ~0.35 s warm
    and **7,739 ms cold**, so ~1,500 cells is ~41 minutes *and* churns NVIDIA's 1 GB `GLCache`.
    The fleet holds 256 battles resident and advances them in one batched submit.

14. **ADR-0264 does not reach this host, and this is the argument.** ADR-0264 decides a
    combat-adjacent tool is a seek into `NavigatorMain` rather than a new `CombatHost`, and its
    entire rationale is the three **battle-entry invariants** — opener framing, the deployment
    idle tick, ENTD facing — which "exist once in the spine and drift in a second copy". The
    lab reproduces **none** of them: a synthetic two-unit cell on a flat map is not a story
    battle, and routing it through the navigator would force it to fake an opener it does not
    want. Recorded because without it the next session reads ADR-0264 and deletes the host.

    Rejected: a **mode on `GambitScenarioRunner`**. That is the "mode flag on" shape both
    ADR-0242 dec. 1 and ADR-0264 reject for one reason, and 84 fixtures read behaviour off it.

    🔴 **Finding, repaired in this diff — and it is a PROSE gap, not a data gap.** ADR-0264 is
    `accepted` and directly contradicts ADR-0242 dec. 1 ("a third `CombatHost` subclass, thin,
    beside `GPUArena`") without naming it in its text: `grep -c 0242` in ADR-0264 returns **0**,
    and ADR-0242 read `Status: accepted` with no marker. `CLASSIFICATION.tsv` **does** record
    the edge — ADR-0264's `constrains` column lists `0242` — so the generated index knew and
    only a human reader of either file could not. That is the narrow shape of the defect, and it
    is the shape that matters: a session reads the ADR, not the TSV. The corpus has the
    convention for saying it in prose (ADR-0270 writes `Supersedes [ADR-0048] dec. 2`).
    ADR-0242 dec. 1 is marked superseded here; no other decision of ADR-0242 is touched.

### Authority

15. **The sweep is an INSTRUMENT and never joins the suite.** `GambitScenarioRunnerTest` is
    already the **4th-slowest test in the tree at 171.28 s** (`docs/TEST-AUDIT-REGISTER.tsv:656`),
    and a sweep would be red on day one for reasons that are *findings* — hollow status bits,
    unreachable opcodes, straddle refusals. A test red for known reasons is one everybody
    trains themselves to ignore, and it takes the 84 real fixtures' credibility down with it.

    Rejected explicitly: **"promote a curated subset to a test later."** The frozen expectation
    would be generated from current behaviour, which ratchets today's bugs into the guard.

16. **Its report is a gitignored artifact; its INPUTS are committed.** The straddle table, the
    formula census and the status census are knowledge. The sweep's output is a measurement,
    and a committed measurement is a `tests/logs/` in waiting.

17. **Existing fixtures are READ-ONLY, and the read-only-ness is ENFORCED BY CLONING.** The live
    arm boots any of the 84 scenario dicts and steps it — nearly free, since that is what
    `GambitScenarioRunner` already does, and it is the cheapest capability in this design.

    Two separate properties, and conflating them is what let one of them be false for weeks:

    - **No SAVING.** There is **no "save as fixture" button**: a generated fixture asserts
      whatever the code did when the button was pressed, so if the behaviour being hunted was
      the bug, the click commits a guard protecting it. dec. 36's scratch cell lives in memory
      and dies with the process, so it does not reach this argument.
    - **No in-process MUTATION.** `_character_for` hands the editor a **clone**, through the
      domain object's own `to_dict`/`from_dict` round-trip — which carries every field
      (`enabled`, both TargetSelectors, the condition list, `action_kind`, `ability_id`) and is
      **not** the "flat-dict shortcut" `GambitScenarioBoot` rejects: that one is about bypassing
      `GambitEncoder` on the way to the GPU, and the clone still encodes through it exactly as
      before. dec. 36's fork does the same, one level up, for the same reason.

    🔴 **This second half was quietly FALSE until #1129, and the mount (dec. 25) is what made it
    matter.** `_character_for` did `list.add(g)` with the fixture's **own** `Gambit` object, and
    `GambitSurface`'s apply closures write in place (`g.action_kind = picked["kind"]`), so one
    edit through the editor permanently rewrote that corpus entry for the rest of the process:
    press `N`, come back with `B`, and your edit is still there — in a fixture whose whole job is
    to assert what the ROM does. Measured, not reasoned about: `_characters[0].gambits.get_at(0)`
    and `_scenarios[i]["units"][0]["gambits"][0]` were **the same object**, and setting
    `action_kind` on the character changed the fixture's printed rule and survived a re-boot of
    that fixture. It was latent for as long as the surface rendered nothing (dec. 25) — nobody
    could reach the editor to fire it.

18. **The lab proves it can fail: ~10 seeded cells, one per failure point**, each asserting the
    exact verdict code. This is a suite-resident test, unlike dec. 15's sweep. Trusting the
    kernel because the verdict comes from the kernel is the trap — a write that never fires
    (wrong branch, wrong slot index, gated off) leaves a zeroed field **indistinguishable from
    "nothing declined"**. A zero from a blind instrument is not absence.

19. **Known confounds are LABELLED, never suppressed.** ADR-0048's injected net will fire in the
    lab; hiding it would make the lab debug a battle that does not exist. Free, because
    [ADR-0270](0270-the-safety-net-is-the-last-row-on-the-gambit-surface-dim-and-inert.md)
    already superseded ADR-0048 dec. 2 and the net renders as a dim inert row via
    `GambitSurface.safety_net_row_index()` — and dec. 20 mounts that surface. Its slot index is
    `MAX_USER_GAMBITS`, **derived**, never a literal 5.

    Labelling also makes the status census **falsifiable**: a cell where a supposedly-hollow bit
    *does* fire is a census error the lab just caught.

20. **The live arm mounts the real `UIGambitEditor3`/`GambitSurface`, not a debug-panel picker.**
    A panel constructing `Gambit` objects directly routes around `GambitEncoder`, and
    editor->encoder drift is a bug class this instrument exists to catch — excluding it by
    construction defeats the purpose. **There is no panel fallback**: dec. 25 settles the mount,
    and the surface reaches the lab through the same coordinator the game reaches it through, so
    there is no second editor and no second mount.

    One UI3 trap remains live and is not resolved by dec. 25: **an element id is a first-write-wins
    `Tune` key**, so a window rebuilt with a reused id keeps the first build's geometry and renders
    empty. The other — a window under a camera-child host needing a declared clip basis — is
    dec. 25's second condition, and it is unconditional rather than bounded.

21. **The status census is CONSUMED, not rewritten** — issue #1105's graded 32-row tally and its
    `unread`/`unreachable`/`hollow` vocabulary, whose artifact is on PR #1115 (open, conflicting
    at the time of writing). A second census is the worst outcome available, and #1105's is
    better than a reference-count sweep can produce because it separates *unreachable* from
    *unread*. The formula census is the same shape: a committed list plus a `static-guard` test
    parsing `combat_combat.glslinc` — the charter's cheapest kind, no Godot process — rather
    than a runtime GLSL parser whose silent mismatch produces exactly the false marking dec. 3
    exists to prevent.

22. **Opcodes the encoder cannot emit are REPORTED, not bypassed.** A raw-opcode injection path
    into the gambit buffer is rejected: it would let the lab exercise battles that cannot exist
    in the game — the same disease as suppressing the safety net — and it routes around the
    encoder dec. 20 deliberately keeps in the path. The lab ships a coverage line instead.

    As of #1114 (merged into this tree while this ADR was being written) the gap is **two
    conditions and two selectors**: `COND_TEAM_ALLY`, `COND_TEAM_ENEMY`,
    `TARGET_HIGHEST_HP_ENEMY`, `TARGET_HIGHEST_HP_ALLY`. It was six and two hours earlier —
    #1114 landed `COND_DISTANCE_LESS/GREATER`, `COND_IS_DEAD`, `COND_IS_ALIVE`,
    `TARGET_NEAREST_ALLY_OR_KO` and an `include_ko` filter. **The number in this decision is a
    measurement with a date on it, not an invariant.**

### Order

23. **The kernel write and dec. 7's bench go FIRST**, because that measurement is the only thing
    that can kill the design. Then dec. 18's verdict guard — nothing downstream is trustworthy
    without it. Then the live arm. Then the synthesizer and straddle table. Then the sweeper.

24. **v1 is done when the lab EXPLAINS the existing XFAILs** — the Monk Secret Fist loop and the
    safety-net hijack noted at `tests/gambit_scenarios/scenarios_B_fallthrough.gd:676`.
    Falsifiable, aimed at the stated purpose, and free because dec. 17 already put fixture
    replay in the live arm. Rejected as acceptance criteria: "a full ability sweep completes"
    (breadth before correctness — ~1,500 unfalsifiable claims from an unvalidated instrument)
    and "it boots and you can step a cell" (a demo is not an acceptance).

### The mount

25. **The lab mounts the gambit screen through `FormationDetailTransition.mount_over_map`, and a
    host that does not declare a clip basis cannot show a UI3 screen at all.** The lab calls
    `mount_over_map(player_camera, cursor_rig, unit_at, pause_fn)` at `_ready`
    (`src/scenes/GambitLabScene.gd:1095`). Two conditions must both hold and either is fatal
    alone:

    - **Position.** The screen is authored in display pixels under an orthographic camera and must
      be a CHILD of that camera carrying the mount transform
      (`FormationMapHost.apply_mount_transform`, `:711` — ×1.3125 for the lab's `size = 12.6`
      against the authored 9.6).
    - **The clip basis, which is UNCONDITIONAL rather than bounded.**
      `UI3ClipEngine.clip_basis_inv_for` walks an element's ancestors for the nearest node
      answering `screen_to_world(px, py)` and falls back to `Transform3D.IDENTITY` finding none.
      A bare `Node3D` answers nothing, so every `OWN_APERTURE` / `PARENT_APERTURE` fragment is
      compared against a basis off by the whole placement and discarded. **No repositioning fixes
      it** — the basis has to be *declared*, and `FormationDetailTransition.screen_to_world`
      (`:1502`) exists for exactly that.

    The general rule this cost is worth more than the fix: **a hand-rolled UI3 mount renders
    NOTHING while every assertion available reads true** — four rows built, one child, `visible`
    true, `safety_net_row_index()` correct. The only referee is the frame, and the lab is the sole
    consumer of `GambitSurface` outside the formation screen, so there was no working mount to
    diff against.

26. **The lab stamps `UnitSpawn.CHARACTER_META` on its own units.** `FormationMapHost.character_for_unit`
    reads it, `GambitScenarioBoot.spawn_unit` stamps neither it nor the catalogue slug, and the
    lab's `Character`s are synthesized per boot and never enter `CharacterCatalog`. So the lab
    stamps the meta itself (`GambitLabScene.gd:551`). Without it every lab tile answers null,
    which on the map host is **indistinguishable from an empty tile**.

27. **`G` does not go through the cursor's door.** o/△ emit `unit_activated`, which the coordinator
    turns into `enter(State.DETAIL)` — and settled Status tiles four opaque frames across
    `y32..231`, covering the battle the lab exists to let you watch. `G` latches the selection
    (`FormationMapHost.select_character`, `:334` — the selection counterpart of the existing
    `show_character` harness seam) and enters `State.GAMBIT` off the bottom of the stack. Both
    doors stay wired: o on a unit still opens its Status screen.

28. **While the surface is up the lab is deaf and its pump is paused**, by ADR-0137's wholesale pad
    claim and ADR-0037's pause. `SPACE` does not step while a gambit list is open; `BACKSPACE`
    (✕ — never Escape, which is `battle_pause`) closes it. `F3` is exempt from the claim, so the
    verdict readout stays visible throughout, which is the half that has to be simultaneous.
    Accepted rather than worked around: a lab that exempted itself from the screen's input grammar
    would be debugging a screen the game does not have.

29. **`--shot=<path>` writes one viewport PNG after the three frames the mount takes** (host, rows,
    relayout) and quits, because nothing in the suite can referee a mount and dec. 15 keeps lab
    arms out of it anyway:

        godot --path . assets/scenes/GambitLab.tscn -- --scenario=A1 --open-surface --shot=surf.png

    Taken from **inside the process**: Godot runs headful here, and `grim` aimed at an off-screen
    window silently returns the ACTIVE workspace instead — a successful-looking capture of the
    wrong thing.

### The corpus

30. **One corpus — fixtures, then cells — and `--scenario=` / `--cell=` are the same verb over its
    two halves.** `_scenarios` is the hand-authored fixtures followed by
    `GambitCellSynth.catalogue()` (`GambitLabScene.gd:272-291`); `N`/`B` walk both halves and
    `Cells >` jumps to the seam. dec. 13 already made them one experiment — a cell spec carries a
    fixture-shaped `scenario` and `GambitScenarioBoot` boots it unchanged — so a second walker
    would only be a second thing that can disagree about which battle is up. Each flag resolves a
    needle to a **corpus index** and `_boot` reads the index alone, so a cell reached by the flag
    and a cell reached by pressing `N` cannot differ. `--cells` prints the census dry and
    `--coverage` the opcode gap; both boot nothing, because the synthesizer is a pure function and
    its census costs no `RenderingDevice` and no tick.

31. **REFUSED cells are IN the list.** dec. 10 makes the refusal the product; a walker that
    filtered them would be the census lying by omission, and *"the catalogue has 29 entries but
    the lab has 25"* is a discrepancy nobody could explain later. They boot nothing, print their
    refusal, and render in the panel's HOT colour rather than greyed away. A boot that stood
    nothing up must **report** rather than error — `_run_trace` read `_trace.back()` unguarded and
    ended such a run in a script error that buried the refusal one line above it.

32. **The prediction is scored at the FIRST evaluation, in both arms.** Scoring only at the end of
    `--trace` meant a cell walked to interactively showed its verdict columns and never its
    prediction — the half that makes the reading falsifiable. The timing is not a convenience:
    `clear_verdict` wipes and rewrites every slot the next call walks, so the first evaluation is
    the only one the prediction is about.

33. **`--cell=` boots and STAYS; the derived tick budget belongs to bare `--trace`.** `--cell=`
    used to arm the batch arm implicitly — any cell booted without `--trace` took its derived
    `ticks_for_speed` budget and quit — which made it batch-only while dec. 17's own text said it
    boots one cell exactly as `--scenario=` boots a fixture. The derivation is not lost: bare
    `--trace` (no `=N`) takes the entry's own number — a cell's `ticks_for_speed`, a fixture's
    `DEFAULT_TRACE_TICKS` (`GambitLabScene.gd:316-329`). dec. 12's reason is untouched: the throw
    straddle drops Speed to 8, and a unit at Speed 8 needs 450 ticks to reach its first turn where
    one at 120 needs 30, so a fixed `--trace=60` would have made every throw cell read NO VERDICT
    and the conclusion would have been about dec. 12 rather than about the budget.

34. **`_boot` takes a GENERATION TICKET and spawns into LOCALS; the LAST PRESS WINS.** `_boot`
    awaits once per unit inside `GambitScenarioBoot.spawn_unit`, so `N` pressed again before the
    spawns finish starts a **second `_boot` inside the first one's await**. Both write the same
    instance fields — `units`, `team0_units`, `team1_units`, `_cfgs`, `_scenario` — so the loser
    resumes into the winner's arrays, appends its own units to them, and hands
    `CombatLoop.start_battle` a `units` list and an `encoded["gambits"]` list that describe
    different battles. Every boot takes the next ticket and re-checks it after every await; a
    stale boot abandons.

    Rejected: **a `_booting` no-op flag.** Dropping the second press would make a mashed `N`
    silently do nothing, which is a second bug wearing the first one's clothes. Last press wins,
    which is what the key means.

    **The LOCALS are the half that removes the hazard**, not the ticket: a field written inside
    an awaiting loop is a field two boots can hold at once, so the cast is built locally and
    published only once it is all standing. An abandoning boot then owns exactly what it built
    and frees it. Measured before that: **13 orphaned units after twelve mashed presses**,
    parented to the scene but absent from `units` — hence invisible to the trace, to `_teardown`,
    to the range overlay and to every readout, and permanent for the life of the process.

    ⚠️ **A re-entrancy defect in this seam does not reproduce WITH a settle between presses.**
    The crash was reported against the lab and survived a 14-fixture hunt and a 121-entry sweep
    without reproducing, because both drove the keys with a settle. It reproduces in six presses
    with **one frame** between them, which is how a human holds a key down.

35. **A mismatched arm arms NOTHING, and says so.** `arm_combat_gambits` reports both sizes and
    returns when `units` and its `p_gambits` disagree. **Rejected: clamping to the shorter of
    the two** — that leaves the tail of the roster fighting with an empty gambit set, either
    standing still or falling through to ADR-0048's safety net, under a silent partial arm. That
    is dec. 10's productive failure arriving in the arming seam: the run continues and its
    verdicts describe an experiment that was never set up. The error names dec. 34's boot race as
    the usual cause, so the next reader gets the sentence rather than the index error.

36. **The scratch cell is the corpus's LAST ENTRY, not a mode.** The one question a human arrives
    with — *what happens if I put THIS rule on THAT unit standing THERE* — must be askable
    without editing a fixture on disk and restarting the process. Half of it is already answered
    by dec. 20: the editor writes through `GambitEncoder` to the live GPU on every keystroke, so
    rules were always editable. The missing half is the **roster**, and it is missing
    structurally rather than by oversight — units are spawned from the cell dict at boot, so
    placing one is not a runtime operation.

    As the last corpus entry, `N`/`B`, `R`, the panel, the trace and the verdict readout all
    reach it with **no second code path** — dec. 30's argument for the synthesized cells, applied
    again. `F` forks whatever is booted into it (starting from a battle that works beats starting
    from an empty map); `1`/`2` add an ally/foe at the cursor tile; `X` deletes; `M` moves the
    watched unit to the cursor; `J` cycles its job; `G` writes its gambits as before. All six
    keys are checked against `project.godot`'s InputMap — `WASD` walks the cursor, `Q`/`E` rotate
    the camera, `[`/`]` page the sort — because a verb shadowing one of those reads as *"the
    cursor is broken"*, not as a collision.

37. **Every roster edit RE-BOOTS, and that is the design rather than a shortcut.**
    `GPUBatchSimulator.set_battle_units` *sizes* the battle's buffers, so the roster is fixed
    from that call until the next one and a unit added afterwards has nowhere to live. A re-boot
    is ~2 s and re-seeds at tick 0, which is what you want anyway — you are asking about an
    opening position. Moving is the exception that proves it (a teleport seam exists) and
    re-boots too, so *"the cell on screen is the cell in the dict"* needs no caveat.

### The readout

38. **`GambitVerdictProbe` is the instrument and there is exactly ONE implementation.** The lab
    is a consumer of the verdict, never its home. dec. 4 makes the kernel write
    `{verdict, condition index, opcode, evaluated mask}` per pass, and a reader confined to
    [GambitLabScene] — a scene with no deployment, no roster and no turn order — answers *"why
    did this unit's slot 2 decline on the turn I was watching"* about a synthesized cell and
    never about the battle in front of you, which is the question this ADR opens with asked about
    the wrong battle. `GambitVerdictReader` had exactly **two** consumers in the tree and both
    were the lab, because the reader, the `REASON_*` table, the row builder and the four naming
    helpers were all private members of that one scene: a host that wanted the readout had to
    become the lab.

    Nothing in the probe is lab-shaped — given a `GPUBatchSimulator`, a battle index and a name
    table it answers rows, and `GambitVerdictPanel` renders them. The lab feeds them its
    synthesized cell; [GambitBattle] feeds them the battle you are playing. **One
    implementation**, because two readers of the same two reserved ints that could disagree about
    what they mean is the defect the hoist exists to make impossible.

    Three conditions hold on the probe, and each is a distinct way for a readout to LIE:

    - **The name table is in the GPU's order, not the host's.** `set_battle_units` walks ONE
      `unit_idx` across both teams, so the layout is `team0 + team1` contiguous — and `units` is
      assembled in that same order in both hosts, so the array IS the table. (`GambitBattle`'s
      `units_per_battle = 2*max(n0,n1)` makes team1 start at `ups/2` exactly when `n0 >= n1`; its
      own `push_warning` covers the case where it does not.) A table in any other order names the
      wrong unit in every `target=` and every row heading.
    - **A failed layout mounts NOTHING and says why.** The verdict is decoded against a layout
      parsed out of the kernel header. If that parse failed every slot would decode to zeros —
      and `VERDICT_NONE == 0` is a *real* answer. A blank readout and a broken one would be
      byte-identical, which is dec. 18's failure exactly.
    - **Identity, not node name.** `GambitBattle` names rows through
      `FormationMapHost.character_for_unit` — the one resolver, slug fallback included — rather
      than a second answer to "who is this unit", which is how a readout comes to print one
      character's name over another's HP.

39. **The readout follows the TILE CURSOR on the battle host, and an empty tile HOLDS the last
    pick.** The cursor is already that scene's "which unit do you mean" answer, so a second
    selection would be a second thing to keep in sync. Blanking the rows on an empty tile would
    erase the very rows you moved the cursor there to compare against.

40. **The verdict panel is HOST-PRIVATE, out of `CombatPanelCatalog`**, for the reason
    `GambitDeployDebugPanel` is: the catalogue holds what BOTH combat hosts want, and the gambit
    kernel's per-slot decision is a question only a host running gambits can ask — `GPUArena`
    fields a cast that has none.

## Considered and rejected

- **Twenty more fixtures instead of an instrument.** The strongest attack, and it fails on
  mechanism rather than on cost: a fixture records *what fired*. The reason the earlier slots
  declined is computed in `evaluate_gambits_up_to` and discarded, so no fixture at any count
  can report it. What the corpus can do it already does — 84 scenarios across rule groups A-J.
- **A CPU mirror of the range predicates** instead of a kernel export. `target_in_action_range`,
  `ability_in_reach` and `get_effective_ability_range` exist **only** in `combat_combat.glslinc`;
  a mirror tests the transcription rather than the kernel, and gambit-rules D6 requires that the
  screen's answer and the unit's behaviour not come from two copies of the arithmetic.
- **Widening `RESULT_SIZE`** for the verdict. It is the sanctioned growth path and is write-only
  from the shader's side, but it is **per-battle** and cannot express per-slot at all.
- **Bumping `UNIT_SIZE`.** No padding exists — `U_*` runs 0..101 contiguous — so this costs a
  `SHADER_VERSION` bump *and* a wider `copy_unit_to_next` on every unit every tick, taxing the
  rollout fleet forever to carry diagnostics production never reads.
- **A player-facing gambit sandbox**, now or as a designed-for future. `GAMBIT-BATTLE-DESIGN.md`
  independently bans a player-facing rollout advisor. The synthesizer is a pure function
  returning a dict, so that reuse stays available *without* having designed for it.
- **A hand-rolled `add_child(GambitSurface.new())` mount onto a bare `Node3D`** —
  *(shipped, reversed: it never drew a pixel, and every assertion available read true for weeks.
  See dec. 25.)*
- **Filtering REFUSED cells out of the walker**, and **a second walker for the synthesized half**.
  Both rejected at dec. 30/31 for the same reason: a census that omits, or two walkers that can
  disagree about which battle is up.
- **`wayfinder` for the build.** It maps open decisions; this ADR closes thirty-three. What remains is
  execution against settled choices, which is a ticket list. Reserve it for the case where
  dec. 7's bench comes back over 5% and decs. 4-7 genuinely reopen.
- **A `_booting` no-op flag** for the re-entrant boot — *(rejected at dec. 34: a dropped press
  makes a mashed `N` silently do nothing, which is a second bug wearing the first one's clothes.)*
- **Clamping a mismatched gambit arm to the shorter list** — *(rejected at dec. 35: a silent
  partial arm makes every verdict downstream describe an experiment that was never set up.)*
- **Handing the editor the fixture's OWN `Gambit` objects** — *(shipped, reversed: one edit
  through the editor permanently rewrote that corpus entry for the life of the process. See
  dec. 17.)*
- **A second verdict reader on the battle host**, and **a scratch-cell MODE beside the corpus**.
  Rejected at dec. 38 and dec. 36 for the same reason dec. 30/31 reject a second walker: two
  implementations of one reading are two things that can disagree.

## Consequences

- The rollout gains an observability substrate it does not have today. There is **no** rollout
  debugging tool in the tree — no panel, no overlay, nothing in `src/debug/` — and
  `RolloutDriver.decide()` already returns the full ranked candidate array (`:625`) which
  `GambitBattle` discards but for one `print()` (`:1257-1270`). Dec. 6 makes that a gate flip.
- `SHADER_VERSION` does **not** move (dec. 4 uses reserved space), but `GambitData` losing
  `readonly` (dec. 5) is a real weakening that any future reader of that buffer must respect.
- Dec. 15 means the sweep can never red the suite, so a regression it would catch is caught
  only when someone runs it. That is accepted: the 84 fixtures remain the guard.
- Cell unit counts must stay **<= 8** — `find_nth_nearest` has a hard `int unit_ids[8]`
  (`stage_compute.glsl:224`).
- Fleet slots are uniform in map and `units_per_battle`, so "sweep every ability across every
  map" is not a thing dec. 13's sweeper can do in one pass.

## Soft spots

- **S1 — RESOLVED by #1126, and the threshold means something narrower than it reads.**
  dec. 7's 5% was derived from cap headroom, not from a measured sensitivity, and the bench
  had never been used to reject anything. It has now been characterised three ways.

  **Its resolution is ~±0.5%.** Split the baseline arm's own 16 runs into halves every way
  and compare median to median — the diff held at exactly zero — and at
  `battles=256 units=32 horizon=300` the delta never exceeds **0.84%** (p99 0.79%). The 5%
  gate is ~6x that. A 5% regression would be unmissable, so the threshold is not sitting on
  a blind instrument.

  **But it cannot be tripped by store VOLUME.** Amplifying the verdict write 16x moves the
  run leg +1.3%, and 128x moves it +0.5-2.8% — it *saturates*, because the twelve words a
  thread touches are cache-resident and this kernel is bound elsewhere. So the gate is
  exactly what dec. 7 claims and nothing more: a tripwire for a **structural** fault — a
  non-uniform branch, a buffer hazard, a lost coalesce — and NOT a budget on how much a
  diagnostic writes. A future change that adds writes should not read a green bench as
  permission; it should read it as "no structural fault detected".

  What is still unmeasured is the bench's response to a genuinely structural pathology.
  Building one without corrupting the gambit programs needs a scratch buffer that does not
  exist, and buying buffer growth to test a threshold is worse than the gap.
- **S2 — a possible vertical-tolerance units bug, untraced.** Terrain `height` is documented in
  FFT **half-steps** (`TerrainCell.gd:82`) and packed raw (`GPUBatchSimulator.gd:854`), while
  ability `vertical` is passed through unconverted (`GPUAbilityLoader.gd:153`) and compared raw
  (`combat_combat.glslinc:210`). If ROM `vertical` is in whole tiles, every vertical-tolerance
  check runs at half its intended reach. Not traced to a conclusion; it does not change any
  decision here, but it makes dec. 11's flat map more valuable than the argument for it claims.
- **S3 — dec. 21 has an external dependency.** PR #1115 is open and conflicting. If it does not
  land, the lab carries the census artifact and dec. 21's "consumed, not rewritten" becomes a
  statement about vocabulary only.
- **S4 — 79 of the 84 fixtures do not account for ADR-0048's injected net**; only 5 sites across
  2 files acknowledge it, and `scenarios_B_fallthrough.gd:676`'s xfail records it biting. Dec. 19
  labels the net in the lab and does nothing for the corpus.
- **S5 — the corpus never exercises separation beyond 10**, and 39 of 84 sit at distance <= 2,
  which is why dec. 11's measurement went undiscovered. Coverage of the long-range abilities
  (`Kikuichimoji`, `EarthSlash`, `Shock!`, `Dispose` at range 8) is currently zero.
- **S6 — the deployed cast carries NO authored gambits.** dec. 38's first live reading found
  slots 0-4 **DISABLED** and slot 5 **FIRED** across all 11 units of a `--combat-autostart`
  battle: everybody is fighting on ADR-0048's injected safety net, because nothing in that roster
  carries an authored gambit. Found by the instrument on its first use, not traced to a
  conclusion, and it changes no decision here — but it means dec. 19's "known confounds are
  labelled" is currently the whole of what a deployed battle's readout says.
