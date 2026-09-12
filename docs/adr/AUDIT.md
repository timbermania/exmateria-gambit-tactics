# ADR conformance audit

**Generated. Do not hand-edit** — put verdicts in `AUDIT.tsv` and run
`uv run python tools/gen_adr_audit.py`. Guarded by `tools/check_adr_classification.py`.

`INDEX.md` says what the decisions are. This says what the code did about them.

**Duplicate prose is not the measure — superseded prose is.** An earlier pass measured
exact duplicate paragraphs at 0.01% and concluded there was nothing to fold. That premise
was wrong: two paragraphs stating opposite things about one decision are not duplicates by
any string measure, and only one of them is current. The corpus is **50,503 lines across
189 ADRs**, of which **65 carry an amendment and those 65 hold 24,417 lines** — ADR-0085 is
a 39-line decision under 2,947 lines of 27 successive positions, one of which reverses
decision 3. The fold buys the *now*: what should be true, why, and what was rejected.
`adr-states-the-now` is the pass that does it; `check_adr_shape.py` is the ratchet that
keeps it, capping an ADR at one dated update.

**Columns.** `lines` / `amd` / `dec` are the document's shape — a numbered Decision
section is what makes `ADR-NNNN dec. N` citations checkable, so `dec 0` on a cited ADR
is itself a finding. `code` / `test` / `doc` / `tool` count files mentioning the number,
by where they live; an ADR citing itself does not count. `guard` names a
`tools/check_*.py` that mentions the number — the difference between a decision and an
enforced one, and `arms` counts guards that are *proposed but unbuilt*. `body` shows
the ADR's own status marker when the TSV disagrees.

**Verdicts** — `complete` (the code does this and something holds it there) ·
`half-landed` (partly built, or built with no guard) · `violated` (the code contradicts
it) · `closeable` (done and no longer constraining — retire rather than delete) ·
`superseded` · `unaudited` (nobody has looked; the default, and it means nothing
stronger than that).

| verdict | ADRs |
|---|---:|
| complete | 33 |
| half-landed | 19 |
| violated | 0 |
| closeable | 0 |
| superseded | 0 |
| unaudited | 246 |
| **all** | **298** |

114 of 298 ADRs are named by a `tools/check_*.py`. 83 are cited by five or more code files with no guard at all — that set is where a mechanized arm buys the most.

## Battlefield — 8

| ADR | bucket | lines | amd | dec | code | test | doc | tool | guard | arms | body | verdict |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|---:|---|---|
| [0041](0041-tile-cursor-is-authoritative-on-camera-body-position.md) | `engine` | 143 | · | 5 | 3 | · | 3 | · | — | 1 | · | complete |
| | | | | | | | | | | | | [audit notes](audit-notes/0041.md) · 5 decisions graded · **1 proposed arm(s)**: Assert the dec. 5 negative: no `get_node`/poll of the cursor from `PlayerCamera` (a source guard over camera/*.gd). |
| [0046](0046-cursor-bob-is-a-rom-step-table.md) | `content` | 185 | 1 | 5 | 15 | 3 | 5 | 6 | — | · | · | half-landed |
| | | | | | | | | | | | | [audit notes](audit-notes/0046.md) · 5 decisions, 5 not yet graded |
| [0056](0056-map-state-is-one-arrangement-time-weather-row-selected-by-raw-weather-index.md) | `content` | 100 | · | · | 6 | 2 | 4 | 5 | — | · | · | unaudited |
| [0183](0183-the-published-autoloads-were-named-from-inside-and-that-half-was-uncounted.md) | `method` | 229 | · | 5 | 4 | 1 | 7 | · | — | · | · | unaudited |
| [0184](0184-the-address-lands-and-arm-1s-debt-is-named-rather-than-hidden.md) | `method` | 363 | · | 6 | 2 | 2 | 19 | 9 | addon_portability, move_manifest, sprite_str… | · | · | unaudited |
| [0219](0219-a-cell-is-x-z-level-because-the-rom-bounds-checks-a-third-coordinate-we-drop.md) | `engine` | 461 | 1 | 9 | 33 | 17 | 6 | 1 | terrain_level | · | · | unaudited |
| [0221](0221-a-cells-marking-is-slotted-and-the-highlight-publish-is-its-only-writer.md) | `engine` | 271 | · | 9 | 6 | 1 | 1 | 1 | highlight_writer | · | · | unaudited |
| [0250](0250-world-quad-is-about-billboarding-not-about-being-level-so-the-tile-decal-drapes.md) | `engine` | 159 | · | 4 | 2 | · | · | · | — | · | · | unaudited |

## Battle — 51

| ADR | bucket | lines | amd | dec | code | test | doc | tool | guard | arms | body | verdict |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|---:|---|---|
| [0001](0001-gpu-combat-buffer-layout-is-shader-authoritative.md) | `engine` | 226 | 1 | 9 | 10 | 2 | 30 | 17 | generated_assets | · | · | complete |
| | | | | | | | | | | | | [audit notes](audit-notes/0001.md) · 9 decisions, 9 not yet graded |
| [0002](0002-unit-state-snapshot-stays-string-keyed.md) | `engine` | 46 | · | · | 2 | · | 6 | · | — | · | · | unaudited |
| [0003](0003-unit-encode-is-a-single-looped-schema.md) | `engine` | 133 | 1 | · | 6 | 2 | 15 | 5 | addon_install, addon_portability, guard_regi… | · | · | unaudited |
| [0007](0007-interactive-progression-mutations-route-through-unit.md) | `engine` | 101 | · | · | 1 | · | 1 | · | — | · | · | unaudited |
| [0008](0008-ability-view-is-a-generated-facade.md) | `engine` | 154 | · | · | 7 | 2 | 4 | 1 | — | · | · | unaudited |
| [0016](0016-gambit-encode-flat-schema-conditions-hand-packed.md) | `engine` | 214 | 1 | 9 | 5 | 3 | 5 | · | — | · | · | complete |
| | | | | | | | | | | | | [audit notes](audit-notes/0016.md) · 9 decisions, 9 not yet graded |
| [0017](0017-gpu-movement-interpretation-is-a-pure-module.md) | `engine` | 61 | · | · | 2 | 2 | 6 | · | — | · | · | unaudited |
| [0018](0018-gpu-combat-interpretation-is-a-pure-module-the-loop-composes.md) | `engine` | 201 | · | 10 | 11 | 7 | 15 | · | — | 1 | · | complete |
| | | | | | | | | | | | | [audit notes](audit-notes/0018.md) · 10 decisions graded · **1 proposed arm(s)**: Assert dec. 11's mechanics/policy split — a source guard that CombatHost.gd declares no signal, no `on_*` hook and no `_rlog`, so the base cannot grow into policy. |
| [0023](0023-gambit-gpu-projection-stays-in-encoder-faithful-or-explicit.md) | `engine` | 105 | · | · | 8 | 6 | 13 | · | — | · | · | unaudited |
| [0024](0024-unit-owns-the-resolution-map-call.md) | `engine` | 201 | 1 | 5 | 10 | · | 8 | · | — | · | · | half-landed |
| | | | | | | | | | | | | [audit notes](audit-notes/0024.md) · 5 decisions, 5 not yet graded |
| [0028](0028-decouple-damage-application-from-state-acting.md) | `engine` | 124 | · | · | · | · | 6 | · | — | · | · | unaudited |
| [0031](0031-battle-state-is-gpu-authoritative.md) | `engine` | 107 | · | · | 4 | · | 12 | 1 | feedback_hud | · | · | unaudited |
| [0032](0032-ranged-damage-waits-in-state-awaiting-impact.md) | `engine` | 219 | 1 | · | 2 | 2 | 12 | 2 | — | · | · | unaudited |
| [0033](0033-preemptive-counter-replaces-reacting.md) | `engine` | 183 | · | · | 1 | · | 1 | · | — | · | · | unaudited |
| [0037](0037-combat-pause-is-domain-scoped-via-process-mode-group.md) | `engine` | 223 | · | 10 | 21 | 5 | 18 | 1 | feedback_hud | 1 | · | complete |
| | | | | | | | | | | | | [audit notes](audit-notes/0037.md) · 10 decisions graded · **1 proposed arm(s)**: Predicate table over CombatLoop._visuals_should_run: the four axes (combat_active, deploy_active, victory_achieved, cinematic-active) crossed against member-under-caster. Nothing c |
| [0038](0038-projectile-is-a-freezing-combat-visual-driven-by-geometry.md) | `engine` | 288 | · | · | 4 | · | 5 | · | — | · | · | unaudited |
| [0042](0042-strategy-phase-is-a-non-combat-phase-of-the-gpu-simulator.md) | `engine` | 138 | 1 | · | 2 | · | 9 | · | — | · | superseded | unaudited |
| [0043](0043-strategy-phase-placement-tiles-are-scenario-sourced.md) | `content` | 156 | 1 | · | 2 | 2 | 5 | 1 | — | · | · | unaudited |
| [0047](0047-real-time-ability-cooldown-is-a-per-ability-floor.md) | `engine` | 166 | · | 6 | 1 | 5 | 8 | 1 | — | 1 | · | complete |
| | | | | | | | | | | | | [audit notes](audit-notes/0047.md) · 6 decisions graded · **1 proposed arm(s)**: Guard that `DEFAULT_COOLDOWN_TICKS` and the B8 scenarios' `max_ticks` budgets move together — the 60->300 raise needed both, and nothing couples them. |
| [0048](0048-safety-net-gambit-is-encoder-injected-ui-invisible.md) | `engine` | 222 | 1 | 6 | 18 | 10 | 15 | · | — | · | · | half-landed |
| | | | | | | | | | | | | [audit notes](audit-notes/0048.md) · 6 decisions, 6 not yet graded |
| [0049](0049-ability-hit-policy-is-rom-flag-derived.md) | `content` | 76 | · | · | 5 | 4 | 5 | 3 | — | · | · | unaudited |
| [0062](0062-gambit-movement-is-one-move-command-flavor-emergent-from-target.md) | `engine` | 97 | · | · | 4 | 4 | 5 | · | — | · | · | unaudited |
| [0082](0082-command-mode-is-one-frozen-navigable-battle-state.md) | `engine` | 75 | · | · | 1 | 4 | 3 | · | — | · | · | unaudited |
| [0120](0120-battle-state-has-one-write-path.md) | `engine` | 86 | · | 6 | · | · | 2 | · | — | · | · | unaudited |
| [0224](0224-the-gpu-battle-mover-addresses-a-cell-so-the-map-is-two-planes-and-the-unit-carries-its-level.md) | `engine` | 519 | 1 | 9 | 8 | 10 | 8 | 1 | — | · | · | unaudited |
| [0235](0235-reconfigure-is-an-overlay-and-the-shader-write-set-classifies-the-fields.md) | `engine` | 201 | · | 8 | 7 | 4 | 11 | · | — | · | · | unaudited |
| [0236](0236-the-turn-meter-is-a-gpu-unit-field-and-it-is-not-called-ct.md) | `engine` | 174 | · | 8 | 6 | 5 | 7 | · | — | · | · | unaudited |
| [0237](0237-the-rollout-budget-is-bounded-by-the-horizon-and-the-unit-count-not-the-fleet.md) | `engine` | 168 | · | 13 | 6 | 6 | 6 | 3 | — | · | · | unaudited |
| [0239](0239-the-turn-director-gates-the-pump-it-does-not-own-and-stops-on-the-exact-tick.md) | `engine` | 201 | · | 12 | 8 | 8 | 11 | 1 | — | · | · | unaudited |
| [0242](0242-the-gambit-host-boots-from-one-integer-and-the-gpu-battle-does-not-exist-until-commit.md) | `engine` | 229 | · | 11 | 10 | 4 | 7 | 1 | — | · | · | unaudited |
| [0245](0245-a-turn-nobody-can-take-is-spent-where-it-opens.md) | `engine` | 163 | · | 6 | · | 2 | 3 | · | — | · | · | unaudited |
| [0246](0246-the-rollout-fleet-is-the-whole-batch-and-the-only-thing-the-cpu-prunes-is-what-cannot-change.md) | `engine` | 188 | · | 8 | 3 | 3 | 4 | · | — | · | · | unaudited |
| [0247](0247-the-deployment-picker-is-the-roster-grid-over-the-map-and-the-pick-is-a-latch.md) | `engine` | 205 | · | 12 | 5 | 3 | 5 | · | — | · | · | unaudited |
| [0252](0252-the-adjustment-turn-holds-the-undo-not-the-redo-and-steerability-is-not-ownership.md) | `engine` | 187 | · | 10 | 3 | 1 | 5 | · | — | · | · | unaudited |
| [0253](0253-the-value-function-is-a-probability-fit-against-played-out-battles-and-the-horizon-is-priced-against-it.md) | `engine` | 277 | · | 13 | 4 | 3 | 4 | · | — | · | · | unaudited |
| [0256](0256-the-thinking-beat-spends-its-cap-by-prediction-and-the-degradation-ladder-bottoms-out-in-a-refusal.md) | `engine` | 331 | · | 13 | 2 | 2 | 4 | · | — | · | · | unaudited |
| [0258](0258-the-march-is-retired-and-two-enums-lose-a-member-without-renumbering.md) | `engine` | 325 | · | 10 | 14 | 6 | 8 | · | — | · | · | unaudited |
| [0259](0259-an-imperative-is-a-lead-entry-not-a-fifth-slot-and-its-charge-is-the-third-half-of-the-pre-turn-image.md) | `engine` | 243 | · | 17 | 1 | 1 | 2 | · | — | · | · | unaudited |
| [0260](0260-the-turn-meter-is-a-dwell-clock-and-the-dwell-is-two-ability-cooldowns.md) | `engine` | 201 | · | 8 | 3 | 3 | 4 | · | — | · | · | unaudited |
| [0266](0266-a-turn-opens-on-a-taker-that-has-committed-to-nothing.md) | `engine` | 201 | · | 3 | · | · | · | · | — | · | · | unaudited |
| [0274](0274-the-search-maximises-a-named-objective-and-the-terminal-verdict-takes-the-endpoints-instead-of-an-invented-weight.md) | `engine` | 279 | · | 9 | 5 | 1 | 2 | · | — | · | · | unaudited |
| [0275](0275-the-gambit-lab-is-a-cell-a-mirror-and-a-verdict-the-kernel-writes.md) | `method` | 674 | · | 40 | 11 | 6 | 5 | 5 | gambit_straddle_table | · | · | unaudited |
| [0277](0277-the-lever-set-is-a-strict-partition-baked-at-load-and-a-hollow-lever-is-an-error.md) | `engine` | 368 | · | 12 | 5 | 3 | 3 | 4 | — | · | · | unaudited |
| [0279](0279-the-attack-period-is-the-animations-and-a-lever-buys-recovery-not-a-faster-swing.md) | `engine` | 239 | · | 8 | 1 | 1 | 1 | · | — | · | · | unaudited |
| [0282](0282-the-cooldown-is-the-abilitys-own-period-and-the-ceiling-was-the-index-not-a-budget.md) | `engine` | 228 | · | 8 | · | · | · | · | — | · | · | unaudited |
| [0285](0285-the-target-column-names-a-pool-and-a-depth-and-nearest-was-the-word-that-was-lying.md) | `engine` | 269 | · | · | 5 | 4 | 3 | · | — | · | · | unaudited |
| [0292](0292-the-render-clock-is-not-the-tick-clock-interpolate-the-remainder-behind-never-ahead.md) | `engine` | 260 | · | 6 | 1 | 1 | · | · | — | · | · | unaudited |
| [0293](0293-the-ability-data-is-the-permission-to-land-on-a-corpse-and-an-empty-slot-is-not-one.md) | `engine` | 235 | · | 10 | 2 | · | 1 | · | — | · | · | unaudited |
| [0298](0298-the-rom-says-how-long-a-status-lasts-and-it-gives-sixteen-of-them-a-byte-to-count-it-in.md) | `engine` | 224 | · | 10 | · | · | 3 | · | — | · | · | unaudited |
| [0299](0299-the-rom-prices-a-separate-inflict-at-a-flat-24-percent-because-its-inflict-record-has-nowhere-to-put-a-probability.md) | `engine` | 223 | · | 7 | · | 1 | 3 | · | — | · | · | unaudited |
| [0301](0301-retreat-is-one-tile-directly-away-and-then-a-fresh-decision.md) | `engine` | 229 | · | 4 | 5 | 5 | · | 1 | — | · | · | unaudited |

## Character Catalogue — 12

| ADR | bucket | lines | amd | dec | code | test | doc | tool | guard | arms | body | verdict |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|---:|---|---|
| [0004](0004-rosters-share-a-base-script.md) | `engine` | 92 | · | · | 97 | 2 | 11 | 3 | path_extends | · | superseded | complete |
| | | | | | | | | | | | | [audit notes](audit-notes/0004.md) |
| [0005](0005-one-durable-unit-representation.md) | `engine` | 107 | · | · | 9 | 5 | 7 | 1 | unit_progression_resource | · | · | unaudited |
| [0066](0066-character-identity-is-a-slug-catalog-above-the-roster.md) | `engine` | 147 | · | 11 | 10 | 5 | 17 | 2 | body_sprite_id_naming, rosters_retired | · | · | unaudited |
| [0072](0072-a-template-is-a-derived-folder-per-key-asset-packet-that-is-the-runtime-read-surface.md) | `content` | 221 | 1 | 6 | 19 | 11 | 12 | 14 | — | · | · | unaudited |
| [0078](0078-owned-is-a-catalogue-overlay-and-class-is-derived-per-battle.md) | `engine` | 74 | · | · | 3 | 1 | 5 | 2 | — | · | · | unaudited |
| [0079](0079-roster-deployed-identity-is-materialized-at-the-deploy-seam.md) | `engine` | 101 | · | · | 4 | 3 | 3 | 2 | — | · | · | unaudited |
| [0081](0081-appearance-type-templates-are-keyed-by-a-semantic-token.md) | `content` | 235 | · | 10 | 9 | 7 | 4 | 2 | — | 1 | · | complete |
| | | | | | | | | | | | | [audit notes](audit-notes/0081.md) · 10 decisions graded · **1 proposed arm(s)**: widen JobDatabase.generic_wardrobe_sprite_ids() past is_generic_human to every job, which retires the 18-sheet remainder and drops the ratchet to 21 |
| [0180](0180-the-rosters-are-retired-and-the-arena-boots-a-real-battle.md) | `engine` | 404 | 1 | 7 | 19 | 8 | 14 | 4 | path_extends, root_set, rosters_retired | 3 | · | complete |
| | | | | | | | | | | | | [audit notes](audit-notes/0180.md) · 7 decisions, 7 not yet graded · **3 proposed arm(s)**: Guard it \| Leave it; Decision 2 is unguarded; Decision 3's boot scenario is unguarded and demonstrably fragile |
| [0201](0201-battle-cast-is-a-replay-derived-view-of-the-catalog.md) | `engine` | 155 | · | 10 | 18 | 6 | 5 | 4 | rosters_retired | · | · | unaudited |
| [0216](0216-the-roster-and-the-seek-state-are-derived-from-rom-data.md) | `engine` | 336 | · | 14 | 9 | 4 | 5 | 3 | — | · | · | unaudited |
| [0284](0284-an-entd-equipment-byte-is-a-sentinel-three-times-in-four-and-the-job-default-is-the-resolver.md) | `engine` | 222 | · | 6 | 1 | · | 1 | · | — | · | · | unaudited |
| [0289](0289-the-entd-level-byte-is-not-a-level-and-resolving-it-is-only-half-the-fix.md) | `engine` | 234 | · | 6 | 5 | 1 | 1 | · | — | · | · | unaudited |

## Sprite Rig — 11

| ADR | bucket | lines | amd | dec | code | test | doc | tool | guard | arms | body | verdict |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|---:|---|---|
| [0019](0019-sprite-layers-compose-on-one-mesh.md) | `engine` | 76 | · | · | 4 | 1 | 4 | 2 | sprite_layers_one_mesh, tool_paths | · | · | unaudited |
| [0020](0020-unit-animation-uses-one-clock-per-unit.md) | `engine` | 128 | · | · | 6 | · | 12 | · | — | · | · | unaudited |
| [0021](0021-animation-resolution-is-per-state-one-atlas.md) | `engine` | 161 | · | · | 4 | 1 | 6 | 1 | — | · | · | unaudited |
| [0022](0022-sprite-palette-rendering.md) | `engine` | 292 | 1 | 8 | 12 | 2 | 7 | 10 | — | 1 | · | half-landed |
| | | | | | | | | | | | | [audit notes](audit-notes/0022.md) · 8 decisions, 8 not yet graded · **1 proposed arm(s)**: see audit-notes/0022.md#harvested-on-mechanizing |
| [0025](0025-react-playback-is-a-parallel-set.md) | `engine` | 208 | 1 | · | 7 | · | 8 | 1 | — | · | · | unaudited |
| [0026](0026-gpu-combat-states-map-to-activities-never-directly-to-a-seq.md) | `engine` | 210 | 1 | 5 | 5 | 5 | 5 | 1 | — | · | · | half-landed |
| | | | | | | | | | | | | [audit notes](audit-notes/0026.md) · 5 decisions, 5 not yet graded |
| [0027](0027-sprite-nomenclature-is-subject-qualified.md) | `method` | 195 | · | · | 1 | 1 | · | 1 | body_sprite_id_naming | · | · | unaudited |
| [0034](0034-unit-animation-set-replaces-animation-data.md) | `engine` | 195 | · | · | 3 | · | 2 | · | — | · | · | unaudited |
| [0053](0053-body-anim-id-is-one-field-with-two-writers.md) | `engine` | 272 | 1 | 6 | 9 | 9 | 8 | · | — | 3 | · | half-landed |
| | | | | | | | | | | | | [audit notes](audit-notes/0053.md) · 6 decisions, 6 not yet graded · **3 proposed arm(s)**: The naming Consequence is mechanizable and would land RED; Decision 1's funnel is mechanizable and is the highest-value arm; Decision 4 is trivially mechanizable |
| [0083](0083-a-units-animation-clock-has-exactly-one-owner.md) | `engine` | 249 | 1 | · | 11 | 10 | 18 | · | — | 1 | · | complete |
| | | | | | | | | | | | | [audit notes](audit-notes/0083.md) · 3 decisions, 3 not yet graded · **1 proposed arm(s)**: The claim's blind spot \| `tick_based` has no setter |
| [0189](0189-the-unit-sprite-is-a-module-and-a-consumer-asks-for-a-variant.md) | `engine` | 252 | · | 9 | 10 | 4 | 6 | 4 | color_shaders, lattice_scene, unit_shader_pa… | · | · | complete |
| | | | | | | | | | | | | [audit notes](audit-notes/0189.md) · 9 decisions graded |

## Effects — 40

| ADR | bucket | lines | amd | dec | code | test | doc | tool | guard | arms | body | verdict |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|---:|---|---|
| [0011](0011-effect-timeline-orchestrates-uniform-tracks.md) | `engine` | 193 | 1 | 5 | 4 | · | 10 | · | — | · | · | unaudited |
| [0012](0012-effecttimeline-capstone.md) | `engine` | 219 | · | 1 | 8 | 1 | 7 | · | — | 1 | · | complete |
| | | | | | | | | | | | | [audit notes](audit-notes/0012.md) · **1 proposed arm(s)**: Warn loudly when has_timeline is false but the cast bears emitters (EffectInstance) — today it is a silent no-start. |
| [0014](0014-effecttimeline-owns-time-modulation-tracks-self-deliver.md) | `engine` | 193 | · | 3 | 8 | · | 15 | · | — | · | · | complete |
| | | | | | | | | | | | | [audit notes](audit-notes/0014.md) · 3 decisions graded |
| [0015](0015-particle-draw-order-uses-godot-native-sort.md) | `engine` | 214 | · | · | 4 | · | 3 | · | — | · | · | unaudited |
| [0040](0040-effect-particle-renderer-uses-multimesh-per-render-mode-per-effect.md) | `engine` | 325 | 1 | · | 8 | 1 | 5 | · | — | 1 | · | half-landed |
| | | | | | | | | | | | | [audit notes](audit-notes/0040.md) · 8 decisions, 8 not yet graded · **1 proposed arm(s)**: The named-API arm \| The named-file arm |
| [0045](0045-trap-particles-render-through-the-shared-multimesh-pool.md) | `engine` | 95 | · | · | 1 | · | 2 | · | — | · | · | unaudited |
| [0069](0069-effect-studio-is-a-standalone-development-window-not-a-debug-panel.md) | `method` | 143 | · | · | 10 | 1 | 10 | · | — | 3 | · | complete |
| | | | | | | | | | | | | [audit notes](audit-notes/0069.md) · 4 decisions graded · **3 proposed arm(s)**: Every res:// and sandbox/ path an ADR names resolves on disk - resolve from the REPO ROOT (sandbox/juce-godot-embed/ is real, just not under godot-learning/). ADR-0040 wants the sa |
| [0070](0070-effect-replay-is-deterministic-within-an-instance-via-a-per-instance-seeded-rng.md) | `engine` | 185 | 1 | · | 11 | 6 | 9 | 2 | — | 1 | · | complete |
| | | | | | | | | | | | | [audit notes](audit-notes/0070.md) · 3 decisions, 3 not yet graded · **1 proposed arm(s)**: see audit-notes/0070.md#harvested-on-mechanizing |
| [0071](0071-a-studio-lane-event-projects-through-a-per-archetype-projector-that-separates-owned-from-referenced.md) | `engine` | 242 | 1 | · | 14 | 9 | 7 | 1 | — | 1 | · | half-landed |
| | | | | | | | | | | | | [audit notes](audit-notes/0071.md) · 3 decisions, 3 not yet graded · **1 proposed arm(s)**: see audit-notes/0071.md#harvested-on-mechanizing |
| [0073](0073-effect-studio-inspection-is-target-kind-dispatched-through-a-projector-registry.md) | `engine` | 230 | · | 11 | 23 | 21 | 13 | 2 | — | 3 | · | complete |
| | | | | | | | | | | | | [audit notes](audit-notes/0073.md) · 11 decisions graded · **3 proposed arm(s)**: A bare ADR-NNNN citation whose number was RENUMBERED is unresolvable and unchecked - see #680; check_adr_quotes.py:166 already holds the map.; Assert every KINDS entry marked true  |
| [0075](0075-the-studio-inspectors-first-interactive-control-is-per-edge-child-spawn-suppression.md) | `engine` | 102 | · | 5 | 6 | 4 | 4 | · | — | · | · | unaudited |
| [0076](0076-battle-vfx-and-timing-are-seq-opcode-driven.md) | `seam` | 124 | · | · | · | · | 1 | · | — | · | · | unaudited |
| [0085](0085-effect-sfx-authoring-is-three-projected-surfaces-not-one-flattened-ruler.md) | `engine` | 3041 | 27 | 3 | 37 | 30 | 11 | 26 | — | · | · | unaudited |
| | | | | | | | | | | | | [audit notes](audit-notes/0085.md) · 3 decisions, 3 not yet graded |
| [0086](0086-camera-authoring-is-sub-channel-lanes-lowered-to-masked-keyframes.md) | `engine` | 351 | · | 26 | 13 | 27 | 7 | 1 | — | · | · | complete |
| | | | | | | | | | | | | [audit notes](audit-notes/0086.md) · 26 decisions graded |
| [0087](0087-palette-tint-is-a-signed-blend-delta-authored-as-a-result-pick-against-a-reference.md) | `seam` | 399 | · | 30 | 19 | 48 | 12 | 1 | — | · | · | complete |
| | | | | | | | | | | | | [audit notes](audit-notes/0087.md) · 30 decisions graded |
| [0089](0089-emitter-parameters-author-as-semantic-two-axis-groups-edited-at-the-reference.md) | `engine` | 2482 | 21 | 7 | 38 | 68 | 13 | 7 | — | · | · | unaudited |
| | | | | | | | | | | | | [audit notes](audit-notes/0089.md) · 7 decisions, 7 not yet graded |
| [0090](0090-effect-studio-region-loop-is-a-session-span-driven-by-a-page-side-bounce-transport.md) | `engine` | 136 | · | 4 | 7 | 9 | 4 | · | — | · | · | complete |
| | | | | | | | | | | | | [audit notes](audit-notes/0090.md) · 4 decisions graded |
| [0092](0092-effect-flags-author-on-the-effect-settings-surface-sound-channels-stay-in-their-container-view.md) | `engine` | 246 | 2 | 6 | 6 | 6 | 5 | 6 | — | 2 | · | half-landed |
| | | | | | | | | | | | | [audit notes](audit-notes/0092.md) · 6 decisions graded · **2 proposed arm(s)**: BLOCKED 2026-08-28: dec. 1 vs Amendment 1 contradict on the home of flags_byte bits 5/6, and the tree implements BOTH. Product call; held interactive, not rewritten; assert masks 0 |
| [0093](0093-time-scale-pacing-curves-are-freehand-painted-not-keyframed.md) | `engine` | 281 | 2 | · | 8 | 6 | 7 | 2 | — | 1 | · | half-landed |
| | | | | | | | | | | | | [audit notes](audit-notes/0093.md) · 4 decisions graded · **1 proposed arm(s)**: BLOCKED 2026-08-28, same product call as 0092: does Amendment 1 still bind? It is unbuilt in EVERY clause and its own Status says so; its consequence prose is present-tense and fal |
| [0094](0094-effect-script-pattern-swap-is-a-structure-preserving-variable-length-section-rewrite.md) | `seam` | 109 | · | 6 | 9 | 6 | 1 | 3 | — | · | · | unaudited |
| [0095](0095-a-timeline-boundary-is-one-number-grabbable-from-either-side-and-a-drag-consumes-empty-space.md) | `engine` | 185 | · | 4 | 5 | 3 | 6 | 1 | — | · | · | unaudited |
| [0098](0098-the-frameset-viewport-is-a-pixel-exact-texel-class-view-of-the-sheet.md) | `engine` | 331 | · | 9 | 3 | 3 | 4 | · | — | · | · | unaudited |
| [0099](0099-a-uv-rect-is-a-shared-sheet-region-and-the-region-is-the-unit-of-edit.md) | `engine` | 468 | · | 9 | 10 | 9 | 4 | 1 | — | · | · | unaudited |
| [0100](0100-the-inspector-row-has-one-right-column-bounded-by-declared-content-width.md) | `engine` | 464 | · | 9 | 6 | 11 | 4 | · | — | · | · | unaudited |
| [0101](0101-a-colour-span-moves-at-frame-granularity-by-spending-keyframe-slots.md) | `engine` | 312 | · | 9 | 8 | 14 | 5 | · | — | 2 | · | complete |
| | | | | | | | | | | | | [audit notes](audit-notes/0101.md) · 9 decisions graded · **2 proposed arm(s)**: decs. 1-9 built and guarded; both amendments folded (2026-08-19 into dec. 6, 2026-08-20 promoted to dec. 9). One open fault survives, counted by the build's own ONE-WAY census; ass |
| [0102](0102-the-animation-screen-composes-the-frameset-it-shows-rather-than-linking-to-it.md) | `engine` | 377 | · | 9 | 8 | 7 | 6 | · | — | · | · | unaudited |
| [0103](0103-the-sequence-thumbnail-is-the-real-render-minus-position-and-camera.md) | `engine` | 293 | · | 9 | 10 | 7 | 5 | · | — | · | · | unaudited |
| [0122](0122-an-effect-lane-is-a-track-of-non-overlapping-typed-events.md) | `engine` | 228 | · | 10 | · | · | 8 | 1 | adr_quotes | · | · | unaudited |
| [0123](0123-the-landmark-lane.md) | `engine` | 125 | · | 7 | · | · | 7 | · | — | · | · | unaudited |
| [0124](0124-effects-tells-audio-a-code-and-a-time.md) | `engine` | 143 | · | 4 | · | · | 9 | 1 | adr_quotes | · | · | unaudited |
| [0127](0127-effects-publishes-and-requires-two-ports.md) | `engine` | 213 | · | 8 | · | · | 11 | 1 | adr_quotes | · | · | unaudited |
| [0130](0130-the-texture-has-two-surfaces-a-page-and-a-tab-on-the-inspector-row.md) | `engine` | 670 | · | 13 | 6 | 11 | 3 | · | — | · | · | unaudited |
| [0134](0134-the-studio-is-an-assembler-and-the-assembler-is-one-file.md) | `method` | 282 | · | 9 | 3 | · | 22 | 2 | root_set | · | · | unaudited |
| [0199](0199-texture-replacement-is-a-fixed-clut-index-delta-over-8bpp-sheets.md) | `seam` | 181 | · | 6 | 11 | 7 | · | 3 | — | · | · | unaudited |
| [0200](0200-the-batch-payload-is-deleted-not-designed.md) | `engine` | 274 | · | 14 | 4 | · | 10 | 2 | — | · | · | unaudited |
| [0286](0286-extraction-7-is-the-effects-runtime-and-the-studio-that-is-seventy-percent-of-the-bucket-is-a-root-set-that-stays.md) | `method` | 431 | · | 11 | 1 | · | 6 | 3 | addon_globals, move_manifest | · | · | unaudited |
| [0287](0287-the-backwards-edge-is-one-misfiled-file-and-the-arm-that-fails-is-the-one-no-selection-ever-ran.md) | `method` | 354 | · | 9 | 1 | · | 4 | 2 | addon_portability | · | · | unaudited |
| [0288](0288-the-sixty-one-debug-lines-are-four-booleans-and-the-seam-is-three-addresses-once-the-psx-trio-goes-home.md) | `method` | 537 | · | 11 | 6 | 3 | 5 | 4 | addon_install, addon_portability, lattice_sc… | · | · | unaudited |
| [0290](0290-an-addon-was-never-a-system-and-the-arm-4b-blocker-is-four-throwaway-probe-shaders.md) | `method` | 499 | · | 11 | 4 | · | 4 | 4 | addon_portability, lattice_scene, move_manif… | · | · | unaudited |
| [0295](0295-the-forty-five-class-names-collapse-to-twenty-one-and-forty-eight-vault-notes-are-held-by-two-anchors.md) | `method` | 392 | · | 9 | 5 | 1 | 4 | 6 | addon_globals, addon_install, addon_portabil… | · | · | unaudited |

## UI — 37

| ADR | bucket | lines | amd | dec | code | test | doc | tool | guard | arms | body | verdict |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|---:|---|---|
| [0010](0010-combat-ui-windows-one-host-single-current-modal.md) | `engine` | 105 | · | · | 4 | · | 3 | · | — | · | · | unaudited |
| [0061](0061-modal-input-capture-not-z-spacing.md) | `engine` | 122 | · | · | 3 | · | 3 | · | — | · | · | unaudited |
| [0063](0063-battle-feedback-hud-is-observation-only-presentation-splits-by-placement.md) | `engine` | 213 | 1 | 6 | 13 | 4 | 6 | 1 | feedback_hud | 1 | · | complete |
| | | | | | | | | | | | | [audit notes](audit-notes/0063.md) · 6 decisions, 6 not yet graded · **1 proposed arm(s)**: see audit-notes/0063.md#harvested-on-mechanizing |
| [0077](0077-flat-ui-scenes-materialize-render-order-into-depth-to-join-the-fold.md) | `seam` | 208 | · | 7 | 35 | 8 | 11 | 3 | compositor_routing, no_pow_in_fold | 2 | · | complete |
| | | | | | | | | | | | | [audit notes](audit-notes/0077.md) · 7 decisions graded · **2 proposed arm(s)**: decs. 1-7 built; the 2026-08-13 amendment folded to dec. 7 and its 12 source citers retargeted in the same commit; assert the four retired names have no DECLARATION anywhere (prose |
| [0084](0084-formation-screen-transitions-are-reversible-beats-composed-into-recipes.md) | `engine` | 218 | · | 6 | 16 | 12 | 20 | · | — | · | · | unaudited |
| [0088](0088-ui3-elements-register-a-criteria-spec-shared-engines-implement-it.md) | `engine` | 905 | 7 | 9 | 32 | 35 | 13 | 4 | location_ownership | 1 | · | half-landed |
| | | | | | | | | | | | | [audit notes](audit-notes/0088.md) · 9 decisions graded · **1 proposed arm(s)**: 1) every root-registering class has a test calling UI3RegistrationAudit.check (would have caught FormationScene); 2) the tracked allowlist has exactly one meaning -- build only aft |
| [0097](0097-transition-cadence-is-a-named-curve-per-verb.md) | `engine` | 185 | · | 5 | 21 | 3 | 9 | 1 | — | · | · | unaudited |
| [0137](0137-the-formation-screen-re-hosts-over-the-map-as-a-camera-child-scene-entered-through-a-paused-camera-takeover.md) | `engine` | 1060 | 9 | · | 27 | 8 | 30 | 4 | addon_install | · | · | unaudited |
| | | | | | | | | | | | | [audit notes](audit-notes/0137.md) |
| [0161](0161-the-world-map-raises-itself-and-its-screen-in-mirrors-the-scene-out-until-someone-measures-it.md) | `seam` | 197 | · | 6 | 10 | 4 | 11 | 1 | root_set | · | · | unaudited |
| [0172](0172-a-screen-in-belongs-to-the-screens-own-system-so-formations-is-uis.md) | `seam` | 206 | · | 6 | 5 | 4 | 11 | 2 | — | · | · | unaudited |
| [0174](0174-a-guessed-constant-expired-to-a-static-scan-not-to-the-capture-rig-its-own-adr-named.md) | `seam` | 180 | · | 4 | 3 | 4 | 5 | · | — | · | · | unaudited |
| [0176](0176-the-world-map-splits-because-being-a-mode-the-spine-sequences-never-meant-the-spine-owns-the-code.md) | `seam` | 116 | · | 5 | · | · | 5 | 1 | — | · | · | unaudited |
| [0178](0178-the-town-picture-gets-an-address-of-its-own.md) | `seam` | 122 | · | 6 | 1 | 1 | 1 | · | — | · | · | unaudited |
| [0181](0181-the-roster-host-gets-its-first-real-navigator-and-a-screen-is-what-hands-the-display-back.md) | `seam` | 254 | 1 | 6 | 3 | 40 | 6 | 5 | root_set | 1 | · | complete |
| | | | | | | | | | | | | [audit notes](audit-notes/0181.md) · 6 decisions, 6 not yet graded · **1 proposed arm(s)**: see audit-notes/0181.md#harvested-on-mechanizing |
| [0182](0182-aperture-opens-normal-closes-fast.md) | `engine` | 99 | · | · | 6 | 1 | 1 | · | — | · | · | unaudited |
| [0188](0188-the-map-fades-out-on-the-roms-own-out-curve-and-the-call-site-is-not-claimed.md) | `seam` | 199 | · | 7 | 4 | 1 | 4 | · | — | · | · | complete |
| | | | | | | | | | | | | [audit notes](audit-notes/0188.md) · 7 decisions graded |
| [0197](0197-ability-picker-shows-a-full-catalog-not-the-learned-set.md) | `content` | 128 | · | 7 | 4 | 5 | 5 | · | — | 1 | · | complete |
| | | | | | | | | | | | | [audit notes](audit-notes/0197.md) · 7 decisions graded · **1 proposed arm(s)**: A grep-class arm asserting AbilityCandidates.build_catalog has exactly ONE call site in src/ would mechanize dec. 6's one-line-revert promise. |
| [0198](0198-learn-job-picker-shows-the-full-job-catalogue.md) | `content` | 72 | · | · | · | · | 3 | · | — | · | · | unaudited |
| | | | | | | | | | | | | [audit notes](audit-notes/0198.md) |
| [0244](0244-a-turn-queue-entry-is-a-turn-and-not-a-unit.md) | `engine` | 195 | · | 9 | 5 | 5 | 6 | 2 | — | · | superseded | unaudited |
| [0249](0249-the-picker-comes-in-on-one-vsync-clock-and-an-animation-with-no-mid-flight-question-has-no-assertion.md) | `engine` | 180 | · | 8 | 2 | 1 | 2 | · | — | · | · | unaudited |
| [0255](0255-the-gambit-surface-is-three-levels-of-one-list-and-the-action-menu-dispatches-by-name.md) | `engine` | 279 | 1 | 12 | 4 | 3 | 6 | 1 | — | · | · | unaudited |
| [0261](0261-the-back-grammar-is-one-table-and-the-claims-belong-to-the-stack.md) | `engine` | 103 | · | 6 | 6 | 2 | 1 | · | — | · | · | unaudited |
| [0268](0268-the-gambit-row-is-a-sentence-read-across-the-screen-and-a-screen-that-owns-the-pad-re-means-the-action.md) | `engine` | 579 | 1 | 13 | 8 | 5 | 7 | 3 | — | · | · | unaudited |
| [0269](0269-the-turn-queue-strip-is-a-row-of-framed-cards-on-a-band-up-for-the-whole-battle.md) | `engine` | 728 | 1 | 9 | 7 | 2 | 2 | 1 | — | · | · | complete |
| | | | | | | | | | | | | [audit notes](audit-notes/0269.md) · 9 decisions graded |
| [0270](0270-the-safety-net-is-the-last-row-on-the-gambit-surface-dim-and-inert.md) | `engine` | 147 | · | 5 | 5 | 1 | 3 | · | — | · | · | unaudited |
| [0276](0276-a-sensible-default-is-the-aim-the-rom-cannot-fault-and-the-preference-is-still-open.md) | `engine` | 370 | 1 | 14 | 5 | 3 | 7 | 2 | — | · | · | unaudited |
| [0278](0278-the-seed-is-the-familys-pool-and-the-family-is-ours-because-the-rom-records-a-hit-policy-and-not-a-purpose.md) | `engine` | 495 | · | 12 | 7 | 4 | 7 | 5 | — | · | · | unaudited |
| [0283](0283-the-gambit-rows-subject-is-its-own-column-and-the-slot-number-shares-a-lane-to-pay-for-it.md) | `engine` | 439 | · | 7 | 4 | 3 | 7 | 1 | — | · | · | unaudited |
| [0291](0291-dont-target-self-is-the-cursor-rule-and-dont-hit-caster-is-the-splash-rule-and-the-wiki-named-a-third-that-the-engine-never-reads.md) | `engine` | 227 | · | 6 | 1 | 1 | 4 | 3 | — | · | superseded | unaudited |
| [0296](0296-the-to-list-is-ordered-by-the-abilitys-family-and-the-rom-stores-the-polarity-we-hand-wrote.md) | `engine` | 156 | · | 6 | 1 | 1 | 2 | · | — | · | · | unaudited |
| [0302](0302-extraction-8-is-ui-selected-against-the-metric-and-the-matrix-that-selects-prints-four-of-its-hundred-and-twenty-seven-inbound-lines.md) | `method` | 391 | · | 9 | · | · | 2 | · | — | · | · | unaudited |
| [0303](0303-extraction-8s-autoload-question-was-already-answered-by-a-port-and-its-widest-escape-was-an-english-word.md) | `method` | 253 | · | · | · | · | 3 | · | — | · | · | unaudited |
| [0304](0304-the-panel-that-registers-is-the-panel-that-stays-and-uis-published-surface-is-seventeen-names-not-eighty.md) | `method` | 244 | · | 5 | 1 | 1 | 3 | 1 | — | · | · | unaudited |
| [0305](0305-uis-seventy-nine-globals-collapse-to-one-facade-and-sequencing-the-debug-inversion-first-buys-six-fewer-published-names.md) | `method` | 291 | · | 5 | · | · | 2 | 1 | — | · | · | unaudited |
| [0306](0306-m5-is-121-the-facade-is-22-or-67-and-adr-0305s-census-does-not-sum.md) | `method` | 309 | · | 7 | 2 | 1 | 2 | 3 | ui_tune_port | · | · | unaudited |
| [0307](0307-the-tests-lever-is-sublinear-the-facade-is-56-and-the-move-is-not-gated.md) | `method` | 147 | · | 6 | · | · | 1 | · | — | · | · | unaudited |
| [0308](0308-tune-was-one-of-seven-a-member-may-reach-no-autoload-and-this-gate-is-real.md) | `method` | 142 | · | 6 | 18 | 2 | · | 1 | ui_autoload_reach | · | · | unaudited |

## Audio — 4

| ADR | bucket | lines | amd | dec | code | test | doc | tool | guard | arms | body | verdict |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|---:|---|---|
| [0006](0006-effect-sfx-and-game-event-sfx-are-separate-paths.md) | `engine` | 83 | 1 | · | 1 | 1 | 1 | 1 | vault_anchors | · | · | unaudited |
| [0050](0050-sfx-bus-is-soft-limited-isolation-stays-byte-faithful.md) | `seam` | 279 | 1 | 4 | 2 | 2 | 1 | · | — | · | · | unaudited |
| [0136](0136-audio-is-one-opcode-language-in-two-containers.md) | `method` | 282 | · | 7 | 1 | · | 9 | 1 | adr_quotes | · | · | unaudited |
| [0163](0163-limiting-is-a-bus-stage-and-the-domain-bus-is-where-it-goes.md) | `seam` | 168 | 1 | 4 | 1 | 1 | 2 | · | — | · | · | unaudited |

## Cutscene — 10

| ADR | bucket | lines | amd | dec | code | test | doc | tool | guard | arms | body | verdict |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|---:|---|---|
| [0039](0039-cinematic-facing-resolution-is-a-yaw-only-terrain-gate-plus-unit-composition-tiebreak.md) | `engine` | 166 | · | 3 | 6 | 2 | 2 | 4 | — | · | · | unaudited |
| [0054](0054-scenario-path-is-director-chosen-chunk-swap-replay.md) | `engine` | 70 | · | · | 3 | · | 1 | · | — | · | · | unaudited |
| [0055](0055-scenario-motion-waits-collapse-to-one-is-done-predicate.md) | `engine` | 249 | 1 | 7 | 6 | 3 | 7 | · | — | 4 | · | half-landed |
| | | | | | | | | | | | | [audit notes](audit-notes/0055.md) · 7 decisions, 7 not yet graded · **4 proposed arm(s)**: Dec. 1 as a contract, across implementations; Dec. 1 as a contract, across implementations; Dec. 5 as a negative; Dec. 6 as a negative |
| [0058](0058-scenario-apply-is-intent-times-world.md) | `engine` | 91 | · | · | 3 | 4 | 6 | · | — | · | · | unaudited |
| [0059](0059-event-instruction-dispatch-keys-a-generated-semantic-enum.md) | `engine` | 267 | 1 | 8 | 11 | 7 | 4 | 2 | — | 4 | · | complete |
| | | | | | | | | | | | | [audit notes](audit-notes/0059.md) · 8 decisions, 8 not yet graded · **4 proposed arm(s)**: Dec. 3/8 as a negative; Dec. 3/8 as a negative; Dec. 4 as a negative; Dec. 3/8 as a negative |
| [0064](0064-scenario-per-unit-cutscene-state-consolidates-into-scenario-actor.md) | `engine` | 264 | 1 | 8 | 3 | 5 | 6 | · | — | 2 | · | complete |
| | | | | | | | | | | | | [audit notes](audit-notes/0064.md) · 8 decisions, 8 not yet graded · **2 proposed arm(s)**: Dec. 1 as a negative; Dec. 7 as a count |
| [0065](0065-scenario-time-advances-on-one-vblank-quantized-tick.md) | `seam` | 143 | · | · | 3 | 7 | 8 | · | — | · | · | unaudited |
| [0125](0125-cutscene-keeps-the-program-and-owns-no-mechanism.md) | `engine` | 141 | · | 5 | · | · | 2 | · | — | · | · | unaudited |
| [0225](0225-the-walk-is-one-integrator-with-four-vertical-cases-not-four-vertical-modes.md) | `engine` | 306 | · | 8 | 5 | 1 | 2 | 1 | — | · | · | unaudited |
| [0226](0226-a-route-step-may-span-two-tiles-so-a-route-is-not-a-path-of-cells.md) | `engine` | 297 | · | 10 | 4 | 5 | 2 | 1 | — | · | · | unaudited |

## Campaign — 8

| ADR | bucket | lines | amd | dec | code | test | doc | tool | guard | arms | body | verdict |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|---:|---|---|
| [0029](0029-encounter-setup-is-a-scenario-not-an-event.md) | `engine` | 85 | · | · | 1 | · | 7 | 1 | — | · | · | unaudited |
| [0030](0030-scenario-is-the-runtime-load-entry-point.md) | `engine` | 79 | · | · | 5 | · | 2 | · | — | · | · | unaudited |
| [0162](0162-the-world-map-mount-tears-the-battlefield-down-because-a-scenario-screen-overlay-outlives-its-scene.md) | `seam` | 124 | · | · | 4 | 4 | 5 | · | — | · | · | unaudited |
| [0179](0179-the-game-variable-store-is-one-array-and-the-port-had-three.md) | `engine` | 143 | · | 3 | 3 | 2 | 2 | · | — | · | · | unaudited |
| [0230](0230-the-reveal-drain-is-an-ordered-pass-and-the-animation-writes-the-bit.md) | `engine` | 297 | · | 10 | 5 | 4 | 2 | · | — | · | · | unaudited |
| [0231](0231-the-reveal-animation-is-three-pages-on-the-vsync-clock.md) | `engine` | 245 | · | 11 | 2 | 4 | 2 | · | — | · | · | unaudited |
| [0264](0264-gambit-battle-is-a-seek-into-the-navigator-not-a-second-combat-host.md) | `engine` | 149 | · | · | 7 | 6 | 7 | 1 | — | · | · | unaudited |
| [0265](0265-the-navigator-needed-a-battle-host-surface-and-the-turn-presentation-is-components.md) | `engine` | 236 | · | 4 | 9 | 4 | 3 | 1 | — | · | · | unaudited |

## Render — 15

| ADR | bucket | lines | amd | dec | code | test | doc | tool | guard | arms | body | verdict |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|---:|---|---|
| [0009](0009-ordering-table-depth-is-one-model.md) | `seam` | 239 | · | 8 | 48 | 5 | 21 | 13 | battle_materials, color_shaders, depth_shade… | 1 | · | half-landed |
| | | | | | | | | | | | | [audit notes](audit-notes/0009.md) · 8 decisions graded · **1 proposed arm(s)**: Per-file exempt-or-route call on the six src/ui3/shaders/ violators (#363). Their neighbours vitals_bar / vitals_sprite / menu_cursor_shadow took psx-ot-depth-exempt: on the identi |
| [0036](0036-par-is-per-content-clip-space-not-global-stretch.md) | `seam` | 306 | 1 | 8 | 31 | 3 | 10 | 1 | — | 1 | · | half-landed |
| | | | | | | | | | | | | [audit notes](audit-notes/0036.md) · 8 decisions, 8 not yet graded · **1 proposed arm(s)**: Decision 3 is mechanizable and unguarded |
| [0044](0044-sprite-stretch-is-per-taxonomy-billboard-width.md) | `seam` | 268 | 1 | 5 | 8 | 2 | 9 | 1 | sprite_stretch_globals | 2 | · | half-landed |
| | | | | | | | | | | | | [audit notes](audit-notes/0044.md) · 5 decisions, 5 not yet graded · **2 proposed arm(s)**: The roster arm (blocked on the recorded question) \| The cursor-coherence arm (not blocked); The dec. 4 scrub arm |
| [0060](0060-battle-meshes-apply-par-through-one-seam.md) | `seam` | 133 | · | · | 6 | 1 | 9 | 2 | addon_portability, par_shaders | · | · | unaudited |
| [0067](0067-color-modes-are-one-model.md) | `seam` | 416 | 1 | 6 | 18 | 9 | 8 | 2 | color_shaders | 1 | · | half-landed |
| | | | | | | | | | | | | [audit notes](audit-notes/0067.md) · 6 decisions, 6 not yet graded · **1 proposed arm(s)**: A docstring arm \| A dead-reference arm \| A profile arm |
| [0074](0074-display-space-fold-is-a-material-contract-not-a-module.md) | `seam` | 204 | · | 9 | 51 | 6 | 18 | 12 | addon_portability, compositor_routing, fold_… | 1 | · | complete |
| | | | | | | | | | | | | [audit notes](audit-notes/0074.md) · 9 decisions graded · **1 proposed arm(s)**: Stale-spelling arm: assert `sorting_offset` reaches no live fold path, scoped past tools/probe_demi_engine_fold.gd which still assigns it. The citation-namespace arm (no ADR-NNNN f |
| [0080](0080-the-fold-composites-pre-transparent-to-layer-modern-over-psx.md) | `seam` | 84 | · | · | 2 | · | 2 | · | — | · | · | unaudited |
| [0096](0096-a-texture-alpha-channel-carries-the-stp-bit-not-opacity.md) | `seam` | 86 | · | 3 | 2 | 4 | 3 | 3 | — | · | · | unaudited |
| [0128](0128-a-colour-crossing-is-an-affine-op-with-an-opaque-mode-token.md) | `engine` | 118 | · | 7 | · | · | 6 | · | — | · | · | unaudited |
| [0129](0129-the-fold-is-renders-and-a-producer-keeps-its-shader.md) | `engine` | 264 | · | 11 | 4 | · | 28 | 2 | — | · | · | unaudited |
| [0150](0150-psxdisplay-stays-because-render-is-the-playstation-look.md) | `method` | 237 | · | 8 | 2 | 1 | 11 | 2 | adr_quotes | · | · | unaudited |
| [0151](0151-an-addon-reaches-no-system-and-a-declarative-panel-is-not-built.md) | `seam` | 190 | · | 6 | 12 | 3 | 18 | 4 | addon_portability, adr_quotes, debug_panel_t… | · | · | unaudited |
| [0152](0152-a-psx-compromise-is-a-policy-the-bracket-is-given.md) | `engine` | 127 | · | 5 | 10 | 4 | 6 | · | — | · | · | unaudited |
| [0171](0171-the-display-port-is-platforms-and-render-is-the-fold-bracket.md) | `method` | 263 | 1 | 6 | 6 | 2 | 13 | 4 | addon_portability, guard_registry, sprite_st… | · | · | unaudited |
| [0191](0191-the-fold-predicate-is-the-kernels-and-a-producer-picks-between-two-shaders.md) | `seam` | 353 | · | 13 | 32 | 6 | 9 | 8 | addon_portability, fold_shader_preload, no_p… | · | · | complete |
| | | | | | | | | | | | | [audit notes](audit-notes/0191.md) · 13 decisions graded |

## Debug — 4

| ADR | bucket | lines | amd | dec | code | test | doc | tool | guard | arms | body | verdict |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|---:|---|---|
| [0035](0035-debug-ui-is-a-separate-os-window.md) | `engine` | 200 | · | 8 | 10 | 2 | 14 | 1 | — | 1 | · | half-landed |
| | | | | | | | | | | | | [audit notes](audit-notes/0035.md) · 8 decisions graded · **1 proposed arm(s)**: Boot-site smoke arm over the seven scenes dec. 5 names, asserting each still reaches register_debug_panel(); plus a persistence round-trip arm over position/size/visibility. |
| [0051](0051-scene-configuration-lives-in-debug-panels-not-env-vars.md) | `method` | 124 | · | 5 | 14 | 6 | 13 | 3 | no_env_vars | 1 | · | half-landed |
| | | | | | | | | | | | | [audit notes](audit-notes/0051.md) · 5 decisions graded · **1 proposed arm(s)**: Every retired env var names a live writer: assert each knob this ADR's history says moved to a panel has >=1 assignment outside its declaration. Also: no docs/**.md outside a fence |
| [0140](0140-debug-is-a-system-and-a-system-logs-itself.md) | `method` | 382 | · | 10 | 9 | 2 | 28 | 5 | addon_portability, blueprint_walk, debug_pan… | · | · | unaudited |
| [0263](0263-panel-applicability-is-a-property-of-a-slug-and-the-instrument-must-not-certify-itself.md) | `engine` | 131 | · | 8 | 2 | 3 | 2 | · | — | · | · | unaudited |

## platform — 6

| ADR | bucket | lines | amd | dec | code | test | doc | tool | guard | arms | body | verdict |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|---:|---|---|
| [0013](0013-fft-bitmask-decoding-lives-at-the-parser-boundary.md) | `seam` | 377 | · | 5 | 10 | 1 | 17 | 12 | adr0013_deferred_flags | · | · | unaudited |
| [0052](0052-psx-coords-rotate-180-around-x-at-parser-time.md) | `seam` | 247 | · | 14 | 15 | 11 | 18 | 21 | — | 5 | · | complete |
| | | | | | | | | | | | | [audit notes](audit-notes/0052.md) · 14 decisions graded · **5 proposed arm(s)**: `_placement_flipped` must be true for every committed chunk, and `_map_size_z` must match its map's terrain.json; Feed convert_position/convert_normal a unit basis; assert net (x,- |
| [0057](0057-psx-spatial-transforms-sort-into-three-classes-placement-orientation-render.md) | `seam` | 328 | 1 | 3 | 15 | 13 | 13 | 8 | — | 1 | · | half-landed |
| | | | | | | | | | | | | [audit notes](audit-notes/0057.md) · 3 decisions, 3 not yet graded · **1 proposed arm(s)**: No Placement flips at runtime \| Every committed chunk is pre-flipped |
| [0068](0068-tunables-bind-a-slug-to-a-code-default-with-a-coalescing-override-layer.md) | `engine` | 410 | · | 17 | 104 | 49 | 62 | 10 | addon_portability, debug_panel_tunables | 2 | · | complete |
| | | | | | | | | | | | | [audit notes](audit-notes/0068.md) · 19 decisions graded · **2 proposed arm(s)**: a bound home that is a `const` with >1 reader; a debug panel that writes game-node state directly; exactly one writer to a static-var home; Tune marks _applying around each on_upda |
| [0091](0091-psx-magnitudes-convert-to-game-units-at-a-single-per-subsystem-seam.md) | `seam` | 138 | · | 6 | 20 | 3 | 13 | 2 | no_raw_psx_units, unit_shader_paths | · | · | unaudited |
| [0177](0177-focus-is-a-stack-of-states-and-godot-can-make-the-bad-state-unrepresentable.md) | `seam` | 269 | · | 4 | 12 | 5 | 4 | 3 | focus_anchor, guard_registry | · | · | unaudited |

## host — 92

| ADR | bucket | lines | amd | dec | code | test | doc | tool | guard | arms | body | verdict |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|---:|---|---|
| [0110](0110-systems-extract-outward-into-addons.md) | `method` | 93 | · | 4 | · | · | 29 | 3 | move_manifest, vault_anchors | · | · | unaudited |
| [0111](0111-the-research-vault-is-ballast-not-blueprint.md) | `method` | 191 | · | 7 | · | 1 | 23 | 1 | vault_anchors | · | · | unaudited |
| [0112](0112-dead-code-is-what-the-root-set-cannot-reach.md) | `method` | 124 | · | 6 | · | · | 31 | 6 | adr_quotes, move_manifest, root_set, vault_a… | · | · | unaudited |
| [0113](0113-tunables-invert-at-the-addon-boundary.md) | `method` | 107 | · | · | 3 | 1 | 14 | · | — | · | · | unaudited |
| [0114](0114-refactor-progress-is-two-per-cluster-numbers.md) | `method` | 103 | · | 7 | · | · | 6 | 1 | — | · | · | unaudited |
| [0115](0115-a-system-is-a-bundle-that-ships.md) | `method` | 99 | · | 7 | 7 | · | 15 | 3 | addon_portability | · | · | unaudited |
| [0116](0116-a-crossing-needs-a-payload-an-owner-and-an-edge.md) | `method` | 78 | · | 4 | 2 | · | 4 | · | — | · | · | unaudited |
| [0117](0117-the-blueprints-ten-systems.md) | `method` | 136 | · | 12 | 6 | 4 | 24 | 2 | adr_quotes | · | · | unaudited |
| [0118](0118-payloads-are-schemas-services-are-ports.md) | `method` | 233 | · | 6 | 31 | 1 | 23 | 4 | addon_portability | · | · | unaudited |
| [0119](0119-contested-resources-are-capabilities-not-flags.md) | `method` | 119 | · | 6 | 4 | 1 | 10 | 1 | focus_anchor | · | · | unaudited |
| [0121](0121-systems-land-in-addons-src-only-shrinks.md) | `method` | 135 | · | 7 | 5 | · | 20 | 2 | adr_quotes | · | · | unaudited |
| [0126](0126-every-system-pass-audits-before-it-designs.md) | `method` | 121 | · | 6 | · | · | 26 | · | — | · | · | unaudited |
| [0131](0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md) | `method` | 278 | · | 9 | · | · | 55 | 14 | addon_install, baseline, blueprint_walk, gua… | · | · | unaudited |
| [0132](0132-assets-are-filed-by-consuming-system-not-by-provenance.md) | `method` | 246 | · | 7 | · | · | 9 | 2 | — | · | · | unaudited |
| [0133](0133-a-wrong-cut-is-fixed-forward-and-the-reconnect-is-the-trigger.md) | `method` | 173 | · | 10 | · | · | 4 | · | — | · | · | unaudited |
| [0135](0135-the-root-set-is-eleven-scenes-and-its-assembler-is-the-script-nothing-calls.md) | `method` | 186 | · | 11 | 3 | · | 25 | 5 | root_set | · | · | unaudited |
| [0138](0138-a-publish-does-not-imply-an-assembler.md) | `method` | 232 | · | 11 | · | · | 10 | 2 | — | · | · | unaudited |
| [0139](0139-the-shared-kernel-is-enumerated-by-the-schema-list.md) | `method` | 386 | · | 14 | 24 | · | 47 | 8 | addon_install, addon_portability | · | · | unaudited |
| [0141](0141-extraction-1-is-render-and-the-clean-five-is-retired.md) | `method` | 234 | · | 6 | 1 | · | 22 | 5 | addon_portability | · | · | unaudited |
| [0142](0142-an-asset-belongs-to-the-system-that-owns-its-format.md) | `method` | 245 | · | 8 | 4 | · | 16 | 3 | addon_install, addon_portability | · | · | unaudited |
| [0143](0143-the-root-set-is-ratified-and-the-formation-cluster-is-its-one-exception.md) | `method` | 260 | · | 7 | · | · | 8 | 1 | root_set | · | · | unaudited |
| [0144](0144-the-instruments-see-the-shaders-the-assets-and-the-closure.md) | `method` | 317 | · | 9 | · | 1 | 18 | 9 | addon_portability, adr_quotes, blueprint_wal… | · | · | unaudited |
| [0145](0145-the-baseline-is-taken-and-the-series-opens.md) | `method` | 273 | · | 7 | · | 1 | 17 | 8 | baseline, residue, vault_anchors | · | · | unaudited |
| [0146](0146-the-kernel-is-built-and-a-codec-is-what-gets-in.md) | `method` | 267 | · | 8 | 4 | · | 27 | 16 | addon_portability, adr_quotes, blueprint_wal… | · | · | unaudited |
| [0147](0147-renders-seam-is-the-fold-bracket-and-one-port.md) | `method` | 410 | · | 9 | 5 | 1 | 24 | 19 | adr_quotes, color_shaders, compositor_routin… | · | · | unaudited |
| [0148](0148-a-walk-that-does-not-follow-the-refactor-loses-coverage-silently.md) | `method` | 285 | · | 7 | 2 | 4 | 35 | 19 | addon_portability, baseline, battle_material… | · | · | unaudited |
| [0149](0149-the-ten-goals-are-scored-per-extraction-and-three-of-them-are-not.md) | `method` | 195 | · | 7 | 1 | · | 15 | 4 | residue | · | · | unaudited |
| [0153](0153-audio-extracts-into-a-package-the-walk-reports-rather-than-enters.md) | `method` | 1303 | · | 10 | 10 | 3 | 25 | 10 | addon_portability, baseline, test_baseline, … | · | · | unaudited |
| [0154](0154-goal-1-is-about-decisions-and-goal-3-is-about-orphans.md) | `method` | 228 | · | 6 | · | · | 14 | 4 | adr_quotes, move_manifest, vault_anchors | · | · | unaudited |
| [0155](0155-where-the-source-that-left-the-walk-went-is-declared-once.md) | `method` | 168 | · | 6 | · | · | 3 | 2 | baseline | · | · | unaudited |
| [0156](0156-new-code-with-no-original-is-content-not-a-system.md) | `method` | 176 | · | 5 | · | 1 | 6 | 2 | blueprint_walk | · | · | unaudited |
| [0157](0157-extraction-3-is-battlefield-and-its-interface-is-two-names-one-system-reaches.md) | `method` | 580 | · | 12 | 3 | 4 | 21 | 5 | addon_portability, res_paths | · | · | unaudited |
| [0158](0158-the-suite-runs-in-parallel-and-the-lane-is-a-measurement.md) | `method` | 197 | · | 6 | · | 1 | 3 | 3 | — | · | · | unaudited |
| [0159](0159-platform-is-not-a-leaf-and-battlefields-seam-waits-on-inverting-it.md) | `method` | 840 | · | 11 | 3 | · | 19 | 3 | — | · | · | unaudited |
| [0160](0160-a-register-taken-from-one-run-reports-a-verdict-and-not-a-flake-set.md) | `method` | 195 | · | 6 | · | · | 2 | · | — | · | · | unaudited |
| [0164](0164-the-lattice-ships-as-one-port-and-one-publish-and-tile-never-crosses.md) | `method` | 480 | 1 | 4 | 24 | 6 | 34 | 10 | addon_install, highlight_writer, lattice_doo… | · | · | unaudited |
| [0166](0166-occupancy-is-battles-in-five-spellings-and-battlefields-sixth-is-inert.md) | `method` | 354 | · | 5 | 15 | 3 | 23 | 2 | lattice_doors | · | · | unaudited |
| [0167](0167-the-mount-inverts-to-the-host-and-the-fix-was-booked-into-the-bucket-it-drains.md) | `method` | 280 | · | 7 | 6 | 2 | 16 | 4 | blueprint_walk | · | · | unaudited |
| [0168](0168-the-manifest-is-the-only-register-that-can-say-the-right-files-moved.md) | `method` | 211 | · | 11 | 1 | 2 | 8 | 2 | move_manifest | · | · | unaudited |
| [0169](0169-platform-ships-to-its-own-address-and-shipping-a-file-is-not-shipping-a-shader.md) | `method` | 307 | 1 | 7 | 5 | 2 | 15 | 7 | addon_globals, addon_install, addon_portabil… | · | · | unaudited |
| [0170](0170-the-third-door-is-a-forwarder-and-the-duck-typing-is-a-test-seam.md) | `method` | 358 | · | 6 | 14 | 2 | 11 | 5 | lattice_doors, lattice_ports, lattice_publish | · | · | unaudited |
| [0173](0173-a-central-replay-existed-because-reset-destroyed-what-only-the-owners-could-rebuild.md) | `method` | 259 | · | 5 | 23 | 14 | 12 | 3 | tune_owner_self_registration | · | · | unaudited |
| [0175](0175-a-port-answers-arm-1-and-not-arm-2-and-the-debug-residue-was-print-statements.md) | `method` | 419 | · | 6 | 15 | 3 | 19 | 4 | addon_portability, guard_registry | · | · | unaudited |
| [0186](0186-the-publish-already-existed-on-the-wrong-half.md) | `method` | 217 | · | 8 | 1 | · | 5 | 1 | addon_install | · | · | unaudited |
| [0187](0187-the-port-is-two-signatures-and-sixteen-of-the-seventy-eight-were-already-inside-it.md) | `method` | 299 | · | 7 | 2 | · | 7 | · | — | · | · | unaudited |
| [0190](0190-a-global-uniform-earns-its-host-entry-by-having-a-writer.md) | `method` | 205 | 1 | 4 | 7 | 1 | 10 | 8 | addon_install, addon_portability | · | · | unaudited |
| [0192](0192-the-register-goes-first-because-the-port-erases-its-own-baseline.md) | `method` | 566 | 2 | 7 | 27 | 19 | 23 | 10 | addon_install, lattice_doors, lattice_ports,… | · | · | unaudited |
| [0193](0193-the-highlight-is-a-publish-with-an-address-and-the-sentinel-belongs-to-the-schema.md) | `method` | 170 | · | 4 | 4 | · | 4 | 1 | lattice_publish | · | · | unaudited |
| [0194](0194-a-test-belongs-to-the-addon-it-can-run-without-the-game.md) | `method` | 692 | 5 | 12 | 31 | 21 | 28 | 22 | addon_portability, blueprint_walk, guard_reg… | · | · | unaudited |
| [0195](0195-the-cursor-publishes-a-coordinate-and-criterion-3-closes.md) | `method` | 151 | · | 6 | 4 | · | 4 | · | — | · | · | unaudited |
| [0196](0196-the-marking-belongs-to-the-schema-and-a-respelling-is-never-the-reason.md) | `method` | 339 | · | 8 | 14 | 1 | 19 | 6 | addon_install, lattice_publish, lattice_scene | · | · | unaudited |
| [0202](0202-installable-is-the-fork-plus-the-kernel-and-the-port.md) | `method` | 387 | · | 12 | 39 | 4 | 28 | 16 | addon_globals, addon_install, addon_portabil… | · | · | unaudited |
| [0203](0203-an-addon-provides-the-names-it-can-and-injects-the-content-it-cannot.md) | `method` | 281 | · | 7 | 15 | 1 | 10 | 5 | addon_install, addon_portability | · | · | unaudited |
| [0204](0204-the-mount-point-is-an-inherited-scene-because-the-addon-supplies-the-ui-to-a-hundred-and-seven.md) | `method` | 198 | · | 5 | 7 | 9 | 10 | 4 | addon_install, addon_portability, lattice_sc… | · | · | unaudited |
| [0205](0205-a-path-reach-is-the-same-axis-as-a-type-reach.md) | `method` | 210 | · | 8 | 6 | 2 | 14 | 7 | addon_globals, addon_install, lattice_publis… | · | · | unaudited |
| [0206](0206-the-cursor-ships-as-a-rig-and-two-implementation-names-lose-their-class-name.md) | `method` | 181 | · | 7 | 14 | 6 | 4 | 2 | lattice_publish, lattice_scene | · | · | unaudited |
| [0207](0207-a-script-reach-collapses-onto-an-instanced-mount-and-a-static-reach-has-nowhere-to-go.md) | `method` | 202 | · | 7 | 4 | 8 | 5 | 4 | lattice_scene | · | · | unaudited |
| [0208](0208-a-published-name-pays-a-path-reach-and-the-cameras-static-reach-was-a-class-load.md) | `method` | 284 | · | 8 | 5 | 5 | 7 | 12 | addon_globals, addon_portability, lattice_pu… | · | · | unaudited |
| [0209](0209-one-ruling-over-three-rows-that-needed-three-and-a-file-can-be-ruled-back.md) | `method` | 209 | · | 8 | 1 | 2 | 5 | 4 | lattice_scene, move_manifest | · | · | unaudited |
| [0210](0210-a-stated-host-use-was-green-and-twenty-times-understated.md) | `method` | 303 | · | 6 | 3 | 6 | 4 | 4 | addon_globals, lattice_publish | · | · | unaudited |
| [0211](0211-nothing-preloads-in-so-the-class-name-set-is-the-whole-surface.md) | `method` | 340 | · | 9 | 223 | 177 | 26 | 20 | addon_globals, addon_portability, lattice_pu… | · | · | unaudited |
| [0212](0212-a-count-of-one-was-never-the-invariant-the-addons-one-global-is-the-folder-named-facade.md) | `method` | 321 | · | 11 | 142 | 41 | 22 | 18 | addon_globals, addon_install, addon_portabil… | · | · | unaudited |
| [0213](0213-extraction-4-is-sprite-rig-and-its-widest-inbound-name-is-a-generated-enum.md) | `method` | 457 | · | 12 | · | · | 13 | · | — | · | · | unaudited |
| [0214](0214-sprite-rigs-scope-is-anchored-and-its-pass-1-numbers-were-taken-through-a-keyhole.md) | `method` | 483 | 1 | 12 | · | · | 5 | 2 | — | · | · | unaudited |
| [0215](0215-the-sprite-rig-seam-is-a-scene-a-vocabulary-and-a-content-port-and-two-thirds-of-its-interface-belongs-to-two-adapters.md) | `method` | 528 | · | 14 | 35 | 22 | 10 | 3 | addon_globals | · | · | unaudited |
| [0217](0217-the-kernel-publishes-no-names-so-the-vocabulary-move-is-sixty-one-alias-declarations-and-the-rig-needs-a-facade-first.md) | `method` | 760 | 1 | 19 | 73 | 27 | 15 | 16 | addon_globals, addon_install, addon_portabil… | · | · | unaudited |
| [0218](0218-nothing-needed-to-be-faked-the-lattice-test-seam-is-a-fixture-over-the-production-builder.md) | `method` | 214 | 1 | 8 | 8 | 14 | 7 | 2 | terrain_level | · | · | unaudited |
| [0220](0220-the-addon-that-declares-a-global-uniform-provides-it.md) | `method` | 317 | 1 | 6 | 8 | 1 | 9 | 4 | addon_install, addon_portability | · | · | unaudited |
| [0222](0222-criterion-4-is-the-production-channel-and-an-oracle-is-reported-beside-it.md) | `method` | 305 | 1 | 6 | 1 | · | 5 | 4 | lattice_scene | · | · | unaudited |
| [0223](0223-a-reach-has-a-bucket-and-an-address-and-goal-5-only-ever-read-the-bucket.md) | `method` | 333 | · | 13 | 31 | 4 | 13 | 3 | addon_portability | · | · | complete |
| | | | | | | | | | | | | [audit notes](audit-notes/0223.md) · 13 decisions graded |
| [0227](0227-a-facade-re-export-is-not-a-use-and-the-closure-could-not-tell.md) | `method` | 196 | · | 6 | · | · | 5 | · | — | · | · | unaudited |
| [0228](0228-the-rig-scores-six-of-nine-and-it-is-the-first-system-with-no-per-domain-escape.md) | `method` | 234 | · | 7 | · | 1 | 6 | 2 | — | · | · | unaudited |
| [0229](0229-the-sprite-rig-reads-isolated-on-every-static-instrument-and-does-not-compile.md) | `method` | 360 | · | 8 | 1 | 5 | 5 | 3 | — | · | · | unaudited |
| [0232](0232-goal-5-is-a-conjunction-and-neither-instrument-may-claim-the-word-alone.md) | `method` | 214 | · | 8 | · | 5 | 6 | 3 | — | · | · | unaudited |
| [0233](0233-a-guard-the-suite-does-not-list-is-a-guard-nobody-runs.md) | `method` | 178 | · | 6 | · | 1 | · | 1 | — | · | · | unaudited |
| [0234](0234-a-port-half-is-not-shipped-until-both-directions-of-the-value-are-on-it.md) | `method` | 201 | · | 6 | 7 | 3 | 10 | · | — | · | · | unaudited |
| [0238](0238-a-global-uniform-is-validated-only-in-the-editor-and-the-debt-is-silent.md) | `method` | 224 | · | 7 | 4 | 3 | 5 | 1 | addon_portability | · | · | unaudited |
| [0240](0240-goal-7-scores-systems-so-a-consumer-exemption-counts-the-jargon-nowhere.md) | `method` | 218 | · | 7 | · | · | 2 | 1 | — | · | · | unaudited |
| [0241](0241-unitprogression-is-the-catalogues-by-ownership-and-src-datas-by-address.md) | `method` | 396 | · | 1 | 6 | · | 11 | 6 | — | · | · | unaudited |
| [0243](0243-the-src-data-tier-is-a-third-addon-and-the-split-the-selection-assumed-does-not-exist.md) | `method` | 426 | · | 13 | 3 | · | 8 | 14 | addon_globals, addon_portability, blueprint_… | · | · | unaudited |
| [0251](0251-the-almanac-is-thirty-two-names-behind-one-and-the-address-collapsed-while-the-buckets-did-not.md) | `method` | 408 | · | 11 | 28 | 2 | 7 | 26 | addon_globals, blueprint_walk, unit_progress… | · | · | unaudited |
| [0254](0254-an-unattended-loop-may-delete-a-test-and-a-named-survivor-is-what-makes-that-safe.md) | `method` | 113 | · | 7 | · | · | 4 | 1 | — | · | · | unaudited |
| [0257](0257-a-debug-panel-is-not-a-member-and-the-order-that-counted-it-as-one-is-an-artefact.md) | `method` | 269 | · | 10 | 3 | · | 11 | 5 | — | · | · | unaudited |
| [0262](0262-the-alias-route-hid-forty-nine-lines-and-the-almanac-reads-as-a-system-only-because-classify-books-by-consumer.md) | `method` | 351 | · | 11 | 19 | 3 | 18 | 8 | addon_globals, lattice_scene, ui_autoload_re… | · | · | unaudited |
| [0267](0267-the-catalogue-lands-and-the-ninth-published-name-was-a-symbol-census-that-could-not-see-a-path.md) | `method` | 328 | · | 12 | 2 | · | 4 | 1 | — | · | · | unaudited |
| [0271](0271-the-tier-is-declared-in-plugin-cfg-because-a-vote-over-consumers-cannot-see-a-fourth-tier.md) | `method` | 333 | · | 10 | 13 | · | 4 | 3 | addon_portability | · | · | unaudited |
| [0272](0272-the-palette-row-edge-is-paid-by-deleting-the-key-because-no-consumer-read-it.md) | `method` | 284 | · | 12 | 7 | 4 | 5 | 3 | addon_portability | · | · | unaudited |
| [0273](0273-free-ness-inside-the-rules-tier-is-declared-per-member-because-a-package-of-tables-is-not-all-tables.md) | `method` | 254 | · | 9 | 8 | 2 | 5 | 3 | addon_portability | · | · | unaudited |
| [0280](0280-gambits-stays-in-the-almanac-and-the-tests-that-said-otherwise-were-measuring-a-kernel-vocabulary-in-the-wrong-package.md) | `method` | 353 | · | 9 | 14 | 3 | 3 | 3 | addon_portability | · | · | unaudited |
| [0281](0281-a-test-process-has-no-tune-staging-file-and-the-runner-brackets-the-run.md) | `method` | 232 | · | 9 | 3 | 2 | 1 | 2 | — | · | · | unaudited |
| [0294](0294-the-catalogues-progression-debt-is-a-vocabulary-and-the-kernel-is-where-a-value-set-lives.md) | `method` | 360 | · | 9 | 14 | 2 | 2 | 2 | — | · | · | unaudited |
| [0300](0300-1059-phase-3-is-rejected-because-the-move-retires-nine-arm-5-lines-and-pays-ten-and-one-reach-has-no-published-name.md) | `method` | 233 | · | 7 | 7 | · | · | 2 | — | · | · | unaudited |

