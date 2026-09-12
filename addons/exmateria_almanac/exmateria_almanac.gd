class_name ExMateriaAlmanac
extends RefCounted

## The whole public surface of `addons/exmateria_almanac`, and the only name it
## puts in your project.
##
## Godot has no package scope: a `class_name` is engine-global, so every one an
## addon declares lands in YOUR global scope — and when you declare a colliding
## one, the ADDON's file is what fails to parse, pointing your error at a file
## you did not write. ADR-0212 dec. 1 answers that with one brand-prefixed name
## per addon, named after its folder; this file is that name.
##
## 🔴 THIS ADDON SHED THIRTY-TWO, THE LARGEST SURFACE ANY EXTRACTION HAS MOVED
## (ADR-0251 dec. 3). ADR-0243 dec. 4 counted thirty-one; thirty-one is the
## PUBLISHED count, and the two agree only by coincidence — `BaseStatsDatabase`
## has no namer outside this addon and is internal, and `SpriteRigContent.gd`
## stayed in the host under dec. 5 without ever having declared one. The names
## were the generic-English worst case by a distance: `Gambit`, `ItemDatabase`,
## `StatusRegistry`, `UnitRole`, `TargetSelector`, `AbilityType` — words any
## tactics project has its own reason to want, and `Gambit` in particular is a
## chess term before it is anything of ours.
##
## A script constant is a full type — annotation, `is` check, `.new()`:
##
##     var prog: ExMateriaAlmanac.UnitProgression = ...
##
## and a consumer may alias one back to a bare local name, which is what keeps
## every existing use site spelled the way it was (ADR-0211 dec. 4):
##
##     const UnitProgression = ExMateriaAlmanac.UnitProgression
##
## **This list IS the supported surface.** If a script is not named here it is
## internal, whatever its visibility says — and `tools/check_addon_globals.py`
## holds both directions: nothing else in this addon may declare a global, and
## nothing named here may dangle.
##
## 🔴 THIS IS THE SYMBOL SURFACE, NOT THE COUPLING SURFACE (ADR-0211 dec. 3,
## ADR-0212 dec. 4). The thirteen JSON payloads this addon serves travelled with
## it and are read by `res://addons/exmateria_almanac/...` paths from INSIDE —
## no host file names one. That is the axis `check_lattice_scene.py` criterion 4
## scores, and "not published here" never means "nothing depends on it".
##
## 🔴 WHAT IS ACTUALLY IN HERE, SAID PLAINLY, BECAUSE THE FOLDER NAME IS A
## COMPROMISE (ADR-0251 dec. 1). Twenty-two of the thirty-two members are ROM
## tables or projections of one — abilities, items, jobs, scenarios, sprites,
## the ENTD. The other ten are rules over those tables that the ROM computes
## rather than stores: `StatCalculator`'s growth curve, `EquipStatDelta`'s
## preview arithmetic, `EquipCandidates`' legality mapping. And the four
## `gambits/` members are neither: they are an ORIGINAL FFXII-style AI design
## with no ROM counterpart at all, which is why this is not
## `exmateria_rom_tables`. An almanac is a book of tables you look things up in,
## which is what every member of this addon does and the only thing any of them
## does.
##
## Nothing here is instantiated. `ExMateriaAlmanac.new()` gives you an empty
## RefCounted; the class exists to be a namespace, not an object.

# --- abilities: the 512-row table, its two projections, and the picker -------

## The generated 512-ability / 176-skill-set store and its lookups. The largest
## single file in the package (19,411 lines) and the reason "24,111 lines moved"
## is not the size of this extraction (ADR-0251 dec. 6).
## Host use: `src/ui3/UIActionAbilityPopup.gd` fills the action menu from
## `get_views_by_type("Normal")`; `src/gpu/CombatLoop.gd` reads it on the tick
## path; `tests/ProgressionTesterTest.gd` drives `get_learnable_abilities_for_job`.
const AbilityDatabase = preload("res://addons/exmateria_almanac/abilities/AbilityDatabase.gd")

## The typed 1:1 mirror of one ability record — a transient view over the stored
## dict, generated from the same source as the table itself (ADR-0008).
## Host use: `src/ui3/UIActionAbilityPopup.gd` annotates
## `Array[AbilityView]` and sorts by `.name`; `tests/AbilityViewTest.gd` builds
## them straight from record dicts with no database.
const AbilityView = preload("res://addons/exmateria_almanac/abilities/AbilityView.gd")

## The LOSSY cast-path projection — charge_time, base_damage, effect_path — as
## opposed to `AbilityView`'s faithful mirror. The equipped-action menu's row.
## Host use: `src/units/EquippedAbilities.gd` holds `Array[AbilityData]` and
## types `get_ability()` / `add_ability()` on it.
const AbilityData = preload("res://addons/exmateria_almanac/abilities/AbilityData.gd")

## The learn-list projection — the typed row the job-learn screen renders,
## sibling to `AbilityView` and `AbilityData` over the same record.
## Host use: `src/ui3/UILearnPanel.gd` builds `Array[LearnableAbility]` via
## `from_view(view, "actions")`.
const LearnableAbility = preload("res://addons/exmateria_almanac/abilities/LearnableAbility.gd")

## The ability-type enum, replacing string comparison at the GPU pack boundary.
## Host use: `src/gpu/GPUAbilityLoader.gd` calls `from_string()` and branches on
## `AbilityType.Type.THROWING`.
const AbilityType = preload("res://addons/exmateria_almanac/abilities/AbilityType.gd")

## What an ability is FOR — `damage` / `healing` / `buff` / `debuff` (ADR-0278).
## A PREFERENCE and not ADR-0049's hit policy: the triple on `AbilityView` says
## which pools an ability may land on, and this says which one it should be
## pointed at. `rule`, not `table`, because nothing in the ROM stores it — the
## three routes compute it from `target_reaction_type`, from `inflict_mode`
## XOR the status polarity, and from a bank of per-formula rulings that are
## ours.
## Host use: `src/ui3/detail/GambitOptions.gd` seeds the `To` column from
## `of_id()` inside ADR-0276's gate.
const AbilityFamily = preload("res://addons/exmateria_almanac/abilities/AbilityFamily.gd")

## A unit's five-slot ability loadout — the port model of the ROM `unit+0x5e`
## record, and the only member that came from `src/units/` rather than
## `src/data/` (ADR-0243 dec. 6 ruled it in by behaviour, not by folder).
## Host use: `src/ui3/detail/DetailScene.gd` builds one with
## `from_progression(prog)` and walks `AbilityLoadout.Slot.*`.
const AbilityLoadout = preload("res://addons/exmateria_almanac/abilities/AbilityLoadout.gd")

## The formation ability-picker's full catalogue source (ADR-0197) — every
## applicable option for a slot, with no progression filter applied.
## Host use: `src/ui3/formation/FormationDetailTransition.gd` calls
## `build_catalog(slot)` for the picker's rows.
const AbilityCandidates = preload("res://addons/exmateria_almanac/abilities/AbilityCandidates.gd")

# --- jobs: the class table, its prerequisite graph, and the role mapping -----

## The job-definition table — sprite ids, skill-set ids, the generic-human set.
## The addon's most widely named member: 36 host files.
## SIBLING NAMER (ADR-0212 dec. 7): the first citation below is a file inside
## `addons/exmateria_catalogue`, which extraction #6 moved out of `src/`
## (#1025 pass 3). It is a valid host use and is staged differently from one.
## Host use: `addons/exmateria_catalogue/seeding/AllTemplatesSeeder.gd`
## enumerates `all_job_ids()`
## and gates on `is_generic_human()`; `tests/AllTemplatesSeederTest.gd` asserts
## `get_sprite_id(job, female)` differs per gender.
const JobDatabase = preload("res://addons/exmateria_almanac/jobs/JobDatabase.gd")

## Job prerequisites and JP requirements — the unlock graph over `JobDatabase`.
## Host use: `src/scenes/ProgressionTester.gd` labels rows with
## `get_job_name(job_id)`; `tests/FormationChangeJobConfirmTest.gd` reads
## `get_prerequisites(front)`.
const JobLevelsDatabase = preload("res://addons/exmateria_almanac/jobs/JobLevelsDatabase.gd")

## The formation Learn job-picker's catalogue source — `AbilityCandidates`' rule
## one domain over.
## Host use: `src/ui3/formation/FormationDetailTransition.gd` iterates
## `build_catalog()`; `tests/JobCandidatesTest.gd` asserts the memoized second
## call returns the same rows.
const JobCandidates = preload("res://addons/exmateria_almanac/jobs/JobCandidates.gd")

# 🔴 `UnitRole` IS NOT HERE ANY MORE, AND IT IS NOT A DELETION. It is
# `ExMateriaSchema.UnitRole`, ADR-0118 dec. 1's ELEVENTH schema row, admitted by
# ADR-0280 dec. 3 and moved by #1159. It held no derivation — an enum, an
# enum->string table, the enum's members and a two-line predicate — so neither of
# ADR-0273's two words could name it, and it was the single reason `gambits/`
# looked expensive to extract. What DECIDES a unit's role is
# `jobs/JobDatabase.gd`'s `get_job_role`, which is a `rule` over this package's
# job table and stayed exactly where it was. Three members here name the kernel
# for the value set: `JobDatabase`, `gambits/Gambit.gd` and
# `gambits/TargetSelector.gd`.

# --- items: the 254-row table and the two rules over it ---------------------

## The 254-item table — stats, attributes, equipment data.
## Host use: `src/ui3/UIEquipmentPopup.gd` fills its lists from
## `get_weapons()` / `get_shields()`; `src/units/Unit.gd` reads it per equip.
const ItemDatabase = preload("res://addons/exmateria_almanac/items/ItemDatabase.gd")

## The ROM equip-picker legality rules as a pure mapping over the item table —
## which slot accepts which category, RE round 49.
## Host use: `src/ui3/formation/FormationDetailTransition.gd` builds the equip
## picker's entries with `build_catalog(...)`; `tests/EquipCandidatesTest.gd`
## asserts `slot_category` and `legal_for_slot` against known item ids.
const EquipCandidates = preload("res://addons/exmateria_almanac/items/EquipCandidates.gd")

## The numeric equip stat-DELTA preview — the arithmetic behind the +/− the
## formation screen shows before you commit a swap (oracle-validated).
## Host use: `src/ui3/formation/FormationDetailTransition.gd` calls
## `compute(candidate, occupant)` on hover; `tests/EquipStatDeltaTest.gd` pins
## the wp/wev/hp/mp result for specific item pairs.
const EquipStatDelta = preload("res://addons/exmateria_almanac/items/EquipStatDelta.gd")

## WHEN the shops stock an item, and which shop — the ROM's own gate
## (`rec[10] <= getvar(0x6F)` plus a 16-bit slot mask), joined to the scenario
## whose event script raises the tier. FFT stores no item power; this ordering
## is the closest thing the disc has to one.
## Host use: none yet — published because `tier_at_scenario()` is the balance
## question the host asks, and `tests/ShopAvailabilityDatabaseTest.gd` pins the
## gate and the timeline against known item ids.
const ShopAvailabilityDatabase = preload("res://addons/exmateria_almanac/items/ShopAvailabilityDatabase.gd")

# --- progression: the unit's own numbers, and the growth rules --------------

## A unit's level, accumulated raw stats, current job and job levels — the
## progression component every roster unit owns. The addon's second-widest
## member: 35 host files.
## SIBLING NAMER (ADR-0212 dec. 7): the citation below is a file inside
## `addons/exmateria_catalogue`, which extraction #6 moved out of `src/`
## (#1025 pass 3). It is a valid host use and is staged differently from one.
## Host use: `addons/exmateria_catalogue/identity/Character.gd` holds
## `var progression: UnitProgression` and constructs one.
## 🔴 IT NO LONGER PICKS A `BaseStatType` THROUGH THIS MEMBER, and neither does
## anything else that only wanted a value: `EquipSlot`, `BaseStatType` and `Zodiac`
## are the shared kernel's since ADR-0294 dec. 2 and this member RE-EXPORTS all
## three, so `UnitProgression.EquipSlot.*` still resolves everywhere in `src/` and
## `tests/EquipCandidatesTest.gd` still spells it that way.
const UnitProgression = preload("res://addons/exmateria_almanac/progression/UnitProgression.gd")

## FFT stat growth on level-up and the raw→display conversion. A rule over the
## table, not a table — the ROM computes these rather than storing them.
## Host use: `src/scenes/ProgressionTester.gd` renders each stat row through
## `raw_to_display(raw)`.
const StatCalculator = preload("res://addons/exmateria_almanac/progression/StatCalculator.gd")

# --- status and elements: the bit vocabulary the GPU packs ------------------

## The single source of truth for FFT status effects — name ↔ bit, mirroring the
## `STATUS_*` constants in the host's `combat_common.glslinc`. The drift check
## that used to live inside it is now the host's test (ADR-0251 dec. 4), which
## is what let this addon open with an EMPTY arm-6 burn-down.
## Host use: `src/gpu/CinematicManager.gd` builds a reraise mask from
## `bit(&"reraise")`; `tests/StatusRegistryTest.gd` round-trips every entry and
## asserts parity against the shader.
const StatusRegistry = preload("res://addons/exmateria_almanac/status/StatusRegistry.gd")

## The FFTPatcher CamelCase name → `StatusRegistry` bit translation — the single
## encode boundary for parser-emitted status names.
## Host use: `src/gpu/GPUAbilityLoader.gd` packs `mask_from_fft_names()` and
## `mode_from_string()` into the ability buffer; `tests/StatusEncoderTest.gd`
## pins DontMove / DontAct.
const StatusEncoder = preload("res://addons/exmateria_almanac/status/StatusEncoder.gd")

## Element name → AB_ELEMENT bit — the same encode boundary, one axis over.
## Host use: `src/gpu/GPUCombatPacker.gd` calls `mask_from_names()`,
## `defense_for_equipment()` and `strengthen_for_equipment()` when packing a
## unit; `tests/GPUCombatTestBase.gd` re-derives the same masks for its oracle.
const ElementEncoder = preload("res://addons/exmateria_almanac/status/ElementEncoder.gd")

# --- gambits: the ORIGINAL design, not a ROM table --------------------------
#
# Four members with no ROM counterpart. FFT's AI is a per-job byte; this is an
# FFXII-style rule list the player authors. It lives here because it is a table
# the encoder looks things up in, and because `GambitEncoder` — the host file
# that packs it for the GPU — is not.

## One gambit rule, separating "who triggers" from "who to act on".
## Host use: `src/ui3/UIGambitEditor.gd` types its `gambit_saved` /
## `gambit_changed` signals on it; `tests/gambit_scenarios/scenarios_D_conditions.gd`
## builds rules with `Gambit.create(...)` and `Gambit.ActionKind.*`.
const Gambit = preload("res://addons/exmateria_almanac/gambits/Gambit.gd")

## A unit's ordered gambit list, evaluated in priority order.
## SIBLING NAMER (ADR-0212 dec. 7): the citation below is a file inside
## `addons/exmateria_catalogue`, which extraction #6 moved out of `src/`
## (#1025 pass 3). It is a valid host use and is staged differently from one.
## Host use: `addons/exmateria_catalogue/identity/Character.gd` holds
## `var gambits: GambitList` and rebuilds it with `from_array(...)` on load;
## `tests/GPUCombatTestBase.gd` returns one from `_build_ui_gambit_list`.
const GambitList = preload("res://addons/exmateria_almanac/gambits/GambitList.gd")

## The condition half of a rule — HP/MP thresholds, range, unit counts.
## Host use: `src/ui3/UIGambitEditor.gd` holds
## `Array[GambitCondition]` and appends `GambitCondition.always()`;
## `src/gpu/GambitEncoder.gd` packs each one.
const GambitCondition = preload("res://addons/exmateria_almanac/gambits/GambitCondition.gd")

## The target half — a pool type plus a resolution strategy, so "who to check"
## and "how to pick one" are separately authored.
## Host use: `src/gpu/GambitEncoder.gd` packs `TargetSelector.PoolType.*` and
## `ResolutionStrategy.*`; `tests/gambit_scenarios/scenarios_D_conditions.gd`
## composes `enemies()`, `self_()` and `triggering()` across its scenarios.
const TargetSelector = preload("res://addons/exmateria_almanac/gambits/TargetSelector.gd")

# --- encounters: the four extracted BIN tables that set a battle up ---------

## The encounter-setup table — map id, ENTD index, deployment zone per scenario.
## Host use: `src/scenarios/ScenarioPlayerScene.gd` reads
## `get_scenario(id).map_id` to boot a battle; `tests/ScenarioPlacementDataTest.gd`
## walks `all_ids()`.
const ScenarioDatabase = preload("res://addons/exmateria_almanac/encounters/ScenarioDatabase.gd")

## The player START tiles per deployment index.
## Host use: `src/scenes/GPUArena.gd` places the party from
## `get_zone(_scenario_deployment_idx())`; `tests/DeploymentPlanTest.gd` pins
## Gariland's zone.
const DeploymentZoneDatabase = preload("res://addons/exmateria_almanac/encounters/DeploymentZoneDatabase.gd")

## ENTD enemy START positions, with the red-first ordering the ROM places in.
## Host use: `tests/ScenarioPlacementDataTest.gd` asserts `get_enemies` /
## `get_enemies_red_first` against the committed artifacts — and that is now the WHOLE
## of it. ⚠️ ADR-0258 left this database with **no production reader**: its only one was
## the retired `ScenarioPlacementSource`, which went with the deployment march. The
## live path composes the enemy side through `EntdBattle` instead
## (`ScenarioCast` → `combatant_slots` / `compose_teams`, stamping each unit's own slot
## tile as `ENTD_TILE_META`), so the red-first ORDERING this database exists to express
## is asserted by a test and consumed by nobody. Recorded, not repaired.
const EntdPositionDatabase = preload("res://addons/exmateria_almanac/encounters/EntdPositionDatabase.gd")

## The battle "director" sets decoded from EVENT/BTLEVT.BIN — the conditions
## that fire `Run Scenario N` and advance the story mid-battle.
## Host use: `src/scenarios/ScenarioDirector.gd` reads `get_set(bc_id)` and
## interprets it; this class only serves records.
const BattleConditionalDatabase = preload("res://addons/exmateria_almanac/encounters/BattleConditionalDatabase.gd")

# --- sprites: the metadata tables, NOT the rig -------------------------------
#
# `exmateria_sprite_rig` owns the PLAYBACK machinery (ADR-0217). These four are
# the tables it and the host look things up in, and `src/data/SpriteRigContent.gd`
# is deliberately NOT here: ADR-0243 dec. 5 left it in the host as the seam
# between the rig and this addon's tables.

## Sprite metadata — spr file, seq type, per-sprite-id shape.
## Host use: `src/ui3/formation/FormationScene.gd` resolves a unit's
## `spr_file` and `get_seq_type(sprite_id)` before standing the portrait up.
const SpriteDatabase = preload("res://addons/exmateria_almanac/sprites/SpriteDatabase.gd")

## The reaction-animation enum plus the SEQ-id lookup that goes with it.
## Host use: `src/gpu/CombatLoop.gd` plays `get_seq_id(sprite_type,
## "taking_damage")` with `ReactionType.Type.TAKING_DAMAGE` on every hit.
const ReactionType = preload("res://addons/exmateria_almanac/sprites/ReactionType.gd")

## Per-item battle-graphic data from BATTLE.BIN's 0x2d3e4 table — 144 entries of
## v-offset and palette row.
## Host use: `src/units/Unit.gd` reads `get_v_offset`, `get_wep1_palette` and
## `get_eff1_palette` when it dresses a unit's weapon layer.
const WeaponGraphicData = preload("res://addons/exmateria_almanac/sprites/WeaponGraphicData.gd")

## Per-weapon-family SHP frame base indices, from section 1 of WEP1/WEP2/EFF1.
## Host use: `src/data/SpriteRigContent.gd` — the seam class dec. 5 left in the
## host — resolves `get_wep1_offset` / `get_wep2_offset` / `get_eff1_offset`
## for the rig.
const WeaponZeroFrames = preload("res://addons/exmateria_almanac/sprites/WeaponZeroFrames.gd")

# --- NOT published, and why -------------------------------------------------
#
# `abilities/AbilitySlot.gd` — the ability-slot vocabulary, extracted from
# `AbilityLoadout` by #1123 so it STAYS here when that `state` member leaves for the
# Character Catalogue (ADR-0241 dec. 1). ZERO namers outside this addon and none
# expected: it is re-exported by the member it came from (`AbilityLoadout.Slot`), so
# all 25 existing call sites are unchanged and no host file names the new path.
# Publishing it would move the published count off thirty-two and the split off
# eighteen/eleven/three for a surface nobody outside reaches, which is the rule below
# applied in the other direction.
#
# 🔴 `items/EquipSlot.gd` WAS THE OTHER HALF OF THIS PARAGRAPH AND IS NO LONGER IN
# THIS ADDON. #1123 lifted the two files together and the paragraph treated them as
# one fact; they are not. `EquipSlot` had crossing readers all along — the catalogue
# seeds five slots and `src/ui3` renders them — and ADR-0294 dec. 2 admitted it to
# the SHARED KERNEL as ADR-0118 dec. 1's twelfth schema row, alongside
# `BaseStatType` and `Zodiac` lifted out of `UnitProgression` in the same pass.
# `AbilitySlot` did not travel, and the measurement is the difference: outside this
# addon and `tests/`, ZERO files name it, so it crosses no boundary and realises no
# row. Nothing above this line moved — `EquipSlot` was never published here, so the
# published count and the eighteen/eleven/three split are untouched, which is why
# the argument in the paragraph above survived its own subject leaving.
#
# ⚠ THIRTY-ONE AND SEVENTEEN/ELEVEN/THREE WHEN THIS PARAGRAPH WAS WRITTEN. #1120
# ruled `ShopAvailabilityDatabase` a `table` and the LIVE register moved 31 -> 32
# published and 17 -> 18 tables; #1125 (b) added `AbilityFamily` as a `rule` and
# moved it 32 -> 33 published and 11 -> 12 rules. #1159 then took `UnitRole` — a
# PUBLISHED `rule` — to the shared kernel under ADR-0280 dec. 3, and the live
# register went back the other way, 33 -> 32 published and 12 -> 11 rules. It reads
# 32 published and 18/11/3 today, and the three moves were three different
# mechanisms: a kind ruled, a member added, a member LEFT. The argument above is
# unaffected by any of them, because it is about a surface with zero outside namers
# and not about any of those numbers. The
# thirty-one/thirty-two above at `BaseStatsDatabase` is the OTHER register — the
# extraction's frozen count — and is deliberately not touched. See the ⚠ block
# below the `MEMBER_KINDS` rows.
#
# `progression/BaseStatsDatabase.gd` — the per-unit-type base stat table. ZERO
# namers outside this addon: `StatCalculator` and `UnitProgression` are its only
# readers, and the host reaches those. ADR-0243 dec. 4 predicted thirty-one
# published names against thirty-one shed `class_name`s; the shed count is
# thirty-two and this is the one that closes the gap (ADR-0251 dec. 3). Publish
# it the day a host file names it, in the pass that adds the call.

# --- the KIND of every member above (#1059 phase 2) -------------------------
#
# 🔴 THIS IS THE FREE-NESS REGISTER, NOT DOCUMENTATION. `tools/_walk_roots.py`
# reads it, and `check_addon_portability.py` arm 5 prints a sibling addon's reach
# into this package unless the member it names is declared `table` here. A wrong
# word is a verdict on an enforcing guard, not a typo.
#
# The tier says which QUESTION this package answers (`tier="rules"` in
# `plugin.cfg`, ADR-0271 dec. 1). It cannot say whether reaching one MEMBER is
# free, because the members are not alike: ADR-0271 dec. 5 measured 83% of this
# addon's consumed surface sitting on members two or more of the eleven systems
# reach, which is why `rules` is NOT in `_walk_roots.PORTABLE_TIERS` and why
# freeing it wholesale is that ADR's rejected alternative. ADR-0115 dec. 7 draws
# the line one level in — *"the driver ships, the banks are content"*:
#
#   table  a bank. Every answer is STORED — a ROM table, a projection of one, or
#          a fixed vocabulary. Reading it is ADR-0115 dec. 4's content shadow,
#          which every system is expected to cast. FREE.
#   rule   a driver. It COMPUTES what the ROM computes rather than stores.
#          `StatCalculator`'s own docstring says it verbatim — *"a rule over the
#          table, not a table"*. Two systems sharing one is ADR-0115 dec. 6's
#          feature threading systems, and that is the thing arm 5 must keep
#          printing. PRINTED.
#   state  a unit's own numbers, not a fact about the game. THREE MEMBERS ARE
#          THIS AND IT IS A MEMBERSHIP DEFECT, NOT A KIND: ADR-0271 soft spot S4
#          and #1059 phase 3 name `UnitProgression`, `GambitList` and
#          `AbilityLoadout` as passing the README's purity predicate by its
#          letter and failing its intent, and ADR-0241 dec. 1 already ruled
#          `UnitProgression` the Character Catalogue's BY OWNERSHIP. Declaring
#          the kind does not settle where they live — it makes the debt a
#          countable number instead of a paragraph. PRINTED.
#
#          🔴 AND THE NUMBER IS WHAT SETTLED IT: phase 3 is REJECTED (ADR-0300).
#          Moving `UnitProgression` retires nine arm-5 lines and pays ten, because
#          `StatCalculator` is a `rule` on ten of its lines and `BaseStatsDatabase`
#          is published NOWHERE — so the relocated file could not reach it at all.
#          All three stay; 13 is the floor.
#
# 🔴 THIS IS NOT A PROVENANCE COUNT AND DOES NOT CONTRADICT THE README'S. The
# README's *"twenty-two of the thirty-two members are ROM tables or projections
# of them"* counts where a member CAME FROM; this counts what it ANSWERS, and the
# two disagree on purpose. `EquipCandidates` encodes ROM equip legality (RE round
# 49) and `StatusEncoder` packs the ROM's own status bits — both are ROM-sourced
# and both COMPUTE, so both are `rule`. Eighteen `table` / ELEVEN `rule` /
# three `state` here; twenty-two by provenance there. Neither number is wrong.
#
# ⚠ THE WORKED EXAMPLE HERE USED TO BE `UnitRole`, AND IT WAS WRONG ON THE
# PROVENANCE AXIS RATHER THAN THE KIND AXIS. This paragraph said it was *derived
# from the ROM's job types*; ADR-0280 dec. 3 measured that the derivation is
# `JobDatabase.get_job_role`'s and that FFT has no roles at all — they are this
# project's AI archetypes. So the member was never one of the ROM-sourced rows it
# was being used to illustrate, which is a second reason the provenance count
# lands on twenty-two and not a coincidence with its leaving (#1159).
#
# ⚠ AND NEITHER OF THOSE IS ADR-0251'S NUMBER. That ADR's thirty-two/thirty-one
# are the EXTRACTION's — what the move carried — and this addon's README freezes
# them at those words on purpose. THIS register is live and moves when a member
# lands: `ShopAvailabilityDatabase` WAS the thirty-third member and the
# thirty-second published, so the 31-published-against-31-shed coincidence
# ADR-0251 dec. 6 flags as accidental is now broken on both sides. The two are
# different registers; do not reconcile them by editing either one.
#
# 🔴 THREE MEMBERS LANDED SINCE, AND THE LIVE PAIR WAS THIRTY-SIX MEMBERS /
# THIRTY-THREE PUBLISHED. `items/EquipSlot.gd` and `abilities/AbilitySlot.gd`
# (#1123) were the thirty-fourth and thirty-fifth and are NOT published — see the
# block above. IT IS THIRTY-FIVE / THIRTY-TWO SINCE #1180: `EquipSlot` left for
# the shared kernel (ADR-0294 dec. 2) and `UnitRole` left before it (#1159), so the
# FILE count fell by one and the PUBLISHED count did not move, because neither
# departure was a published name at the time it left. `AbilityFamily` (ADR-0278 dec. 9) is the thirty-sixth member and
# the THIRTY-THIRD PUBLISHED, which is the ordinal
# `tools/test_check_addon_portability.py` pins. Read the latest member off THAT
# test, not off the sentence above it: the sentence names the member that was
# latest when it was written, which is what #1158 found drifted across five
# sites at once.
#
# Ties go to `rule`. A member wrongly called `rule` costs a printed line somebody
# can falsify; one wrongly called `table` costs silence, and ADR-0271 dec. 5's own
# sentence is that *"a wrong bucket is a claim someone can falsify, and silence is
# not"*.
#
# 🔴 `ShopAvailabilityDatabase` IS THE FIRST MEMBER RULED AFTER ADR-0273 LANDED,
# AND THE OBVIOUS ARGUMENT FOR IT IS THE ONE THAT ADR REJECTS. Reading the kind off
# the `*Database` spelling is the by-NAME proxy ADR-0273's considered alternatives
# rule out, and that section measures it under-counting THIS map by eight. Not a
# quotation — the proxy is named there, the sentence here is mine. Derived from
# dec. 1 instead: the member OWNS a bank — `items/shop_availability.json`, emitted
# from `rec[10]`, the 16-bit shop-slot mask and `rec[2]` — and seven of its ten
# queries are plucks of a stored field. `EquipCandidates` and `StatusEncoder` own
# no payload at all: delete their computation and nothing is left, while deleting
# `is_stocked` leaves a whole ROM table still answering the member's headline
# question.
#
# THE CLOSE CALL IS RECORDED RATHER THAN SMOOTHED. `is_stocked` reproduces a NAMED
# ROM gate (`FUN_8012502C` @0x801251BC/0x801251CC) and `stock_for` scans to a list,
# which is `EquipCandidates`' shape exactly. Dec. 5's tie-break costs nothing here
# and was checked rather than assumed. NO sibling addon and no `src/` file names
# this member, so arm 5 reads the SAME split under either word — run both ways on
# this tree, 373 free / 36 debt each time. The zero is not a blind one: the dec. 7
# control ran beside it, and declaring `UnitProgression` a `table` moved the same
# register 373/36 -> 405/4. A reader who reads it the other way is disagreeing
# with a derivation, not with a number — which is exactly when ADR-0273 dec. 5
# says the tie-break is cheap to state and expensive to invent later.
#
# Both directions are held by `check_addon_portability.py`: every name the façade
# publishes must appear here exactly once, and every name here must be published.
# A member added above without a row here RAISES the whole guard rather than being
# scored as whatever the missing entry defaulted to.
const MEMBER_KINDS := {
	"AbilityCandidates": "rule",
	"AbilityData": "table",
	"AbilityDatabase": "table",
	"AbilityFamily": "rule",
	"AbilityLoadout": "state",
	"AbilityType": "table",
	"AbilityView": "table",
	"BattleConditionalDatabase": "table",
	"DeploymentZoneDatabase": "table",
	"ElementEncoder": "rule",
	"EntdPositionDatabase": "table",
	"EquipCandidates": "rule",
	"EquipStatDelta": "rule",
	"Gambit": "rule",
	"GambitCondition": "rule",
	"GambitList": "state",
	"ItemDatabase": "table",
	"JobCandidates": "rule",
	"JobDatabase": "table",
	"JobLevelsDatabase": "table",
	"LearnableAbility": "table",
	"ReactionType": "table",
	"ScenarioDatabase": "table",
	"ShopAvailabilityDatabase": "table",
	"SpriteDatabase": "table",
	"StatCalculator": "rule",
	"StatusEncoder": "rule",
	"StatusRegistry": "table",
	"TargetSelector": "rule",
	"UnitProgression": "state",
	"WeaponGraphicData": "table",
	"WeaponZeroFrames": "table",
}
