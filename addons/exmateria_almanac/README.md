# ExMateria Almanac

Final Fantasy Tactics' **rule tables and the pure functions over them**: jobs,
items, abilities, base stats, status bits, gambits, encounters and sprite
lookups. Thirty-five files behind one façade, and the thing they have in common
is that **every one of them answers a question about the game's rules without
touching a node, a scene, a shader or a frame**.

Created at extraction #5 —
[ADR-0243](../../docs/adr/0243-the-src-data-tier-is-a-third-addon-and-the-split-the-selection-assumed-does-not-exist.md)
(the tier is one addon; the split the selection assumed does not exist) and
[ADR-0251](../../docs/adr/0251-the-almanac-is-thirty-two-names-behind-one-and-the-address-collapsed-while-the-buckets-did-not.md)
(the name, the façade, and everything the move decided at the address).

| | |
|---|---|
| `exmateria_almanac.gd` | `class_name ExMateriaAlmanac` — **the façade, and the addon's only global name**; publishes 32 of the 35 members as constants |
| `abilities/` | `AbilityDatabase` (generated), `AbilityView` (generated), `AbilityData`, `LearnableAbility`, `AbilityType`, `AbilityFamily`, `AbilityLoadout`, `AbilityCandidates`, `AbilitySlot` (**not published** — see below) |
| `encounters/` | `ScenarioDatabase`, `DeploymentZoneDatabase`, `EntdPositionDatabase`, `BattleConditionalDatabase` + 4 payloads |
| `gambits/` | `Gambit`, `GambitList`, `GambitCondition`, `TargetSelector` |
| `items/` | `ItemDatabase`, `EquipCandidates`, `EquipStatDelta`, `ShopAvailabilityDatabase`, `EquipSlot` (**not published** — see below) + 3 payloads |
| `jobs/` | `JobDatabase`, `JobLevelsDatabase`, `JobCandidates` + 2 payloads |
| `progression/` | `UnitProgression`, `StatCalculator`, `BaseStatsDatabase` (**not published** — see below) + 1 payload |
| `sprites/` | `SpriteDatabase`, `ReactionType`, `WeaponGraphicData`, `WeaponZeroFrames` + 4 payloads |
| `status/` | `StatusRegistry`, `StatusEncoder`, `ElementEncoder` |

⚠️ **ADR-0251's "thirty-two" is the EXTRACTION's count, not a live one.** THREE
claims below are frozen at what the move carried and never track the register:
the provenance count (*twenty-two of the thirty-two*), the shed-against-published
pair (*thirty-two moved; thirty-one are reachable*) and the bucket census (*the
thirty-two files*). **Every other count in this file is LIVE** and moves the day a
member lands — including the façade-surface number under "The façade", which was
also thirty-one at the extraction and is thirty-two today — thirty-three until
`UnitRole` left in #1159, which the next paragraph records and this line used to
contradict. The live inventory is
the table above.

`AbilityFamily` ([ADR-0278](../../docs/adr/0278-the-seed-is-the-familys-pool-and-the-family-is-ours-because-the-rom-records-a-hit-policy-and-not-a-purpose.md)
dec. 9, 2026-09-10) is the most recent member to LAND: the **thirty-sixth**, and
the thirty-third published. One has since left — `UnitRole`, to the shared kernel
under ADR-0280 dec. 3 (#1159) — so the live totals are **35 members, 32
published**, and an ordinal is a landing position rather than a subtraction. `ShopAvailabilityDatabase` was the thirty-third member
and is still the twenty-third ROM table — `AbilityFamily` computes rather than
stores, so the provenance count does not move with it.

The subdirectory names are the fact each file encodes rather than the file's own
name, which is what makes [ADR-0146](../../docs/adr/0146-the-kernel-is-built-and-a-codec-is-what-gets-in.md)
dec. 2's `ls` test answerable here: eight directories, and the `ls` tells you what
the package is for without opening a file.

## 🔴 The name is a compromise, and here is what it is hiding

**Twenty-two of the thirty-two members are ROM tables or projections of them.**
`jobs.json`, `items.json`, `base_stats.json`, `entd_positions.json` and the rest
were extracted from the disc; `tools/export_battle_conditionals.py` decodes
`BTLEVT.BIN`; `tools/generate_ability_database.py` writes 512 abilities and 176
skill sets out of the same source. For those, `exmateria_rom_tables` would have
been the exact name.

**The four `gambits/` members are not that.** `Gambit`, `GambitList`,
`GambitCondition` and `TargetSelector` are an **original FFXII-style AI design**
that this project invented; nothing in Final Fantasy Tactics has them. Naming the
package after the ROM would have made a false claim about a fifth of it, and
[ADR-0184](../../docs/adr/0184-the-address-lands-and-arm-1s-debt-is-named-rather-than-hidden.md)
dec. 2 says name the directory after the fact. *An almanac is a book of tables you
look things up in* — which is true of the ROM tables and true of the gambits, and
claims nothing about where any of them came from. ADR-0251 dec. 1.

`exmateria_schema` and `exmateria_platform` were both ruled out as destinations by
ADR-0243 decs. 1–2 and are not alternatives to re-litigate here.

## The façade, and why every member reaches its siblings by path

`class_name` is engine-global in Godot 4: an addon's every `class_name` lands in
its consumer's global scope whether the consumer wants it or not. That is
[ADR-0211](../../docs/adr/0211-nothing-preloads-in-so-the-class-name-set-is-the-whole-surface.md)
dec. 1 and [ADR-0212](../../docs/adr/0212-a-count-of-one-was-never-the-invariant-the-addons-one-global-is-the-folder-named-facade.md)
dec. 1's whole subject, and the rule they land is a folder-named, brand-prefixed
façade.

🔴 **Thirty-two published constants is the largest façade surface in this
repo** — the next are `exmateria_sprite_rig` at 20, `exmateria_sound` at 18 and
`exmateria_battlefield` at 17; `exmateria_render` publishes one. So the rule is
carrying more weight here than it ever has, and the two halves of it are:

- **Outward**: one global name, `ExMateriaAlmanac`, publishing 32 constants.
  A host that wants `JobDatabase` writes `const JobDatabase = ExMateriaAlmanac.JobDatabase`
  once at the top of the file and every use site below keeps its spelling
  (ADR-0211 dec. 4). There are 270 such alias lines across 134 host and test
  files, which makes `grep -rn ExMateriaAlmanac` a **complete census of
  host→addon symbol coupling** — the thing a bare `class_name` makes
  unmeasurable.
- **Inward**: members reach each other by `const X = preload("res://addons/exmateria_almanac/…")`,
  never through the façade. A member reaching its own package through the façade
  would make the addon depend on its own published surface, and a
  `preload` const is a full type — it annotates, `is`-checks and `.new()`s
  exactly as the deleted `class_name` did. **One pair forms a cycle**, which is a
  parse error and not a warning: `JobDatabase` ↔ `JobCandidates`. The back edge is
  the only runtime `load()` in the package, at `jobs/JobDatabase.gd:148`, with the
  reason written at the line.

## Every member declares a KIND, and it decides who may name it for free

🔴 **`const MEMBER_KINDS` at the bottom of the façade is a free-ness register, not
documentation.** `check_addon_portability.py` arm 5 prints a *sibling addon's*
reach into this package unless the member it names is declared `table` there, so a
wrong word is a verdict on an enforcing guard.

`plugin.cfg`'s `tier="rules"` says which question this package answers
([ADR-0271](../../docs/adr/0271-the-tier-is-declared-in-plugin-cfg-because-a-vote-over-consumers-cannot-see-a-fourth-tier.md)
dec. 1). It cannot say whether reaching one *member* is free, because the members
are not alike: dec. 5 measured **83% of this addon's consumed surface sitting on
members that two or more of the eleven systems reach**, which is why `rules` is not
in `_walk_roots.PORTABLE_TIERS` and why freeing it wholesale is that ADR's rejected
alternative. [ADR-0115](../../docs/adr/0115-a-system-is-a-bundle-that-ships.md)
dec. 7 draws the line one level in — *"the driver ships, the banks are content"*:

| kind | what it is | arm 5 |
|---|---|---|
| `table` (18) | a bank. Every answer is **stored** — a ROM table, a projection of one, or a fixed vocabulary. Reading it is ADR-0115 dec. 4's content shadow, which every system casts. | **free** |
| `rule` (11) | a driver. It **computes** what the ROM computes rather than stores. `StatCalculator`'s own docstring says it verbatim — *"a rule over the table, not a table"*. Two systems sharing one is ADR-0115 dec. 6's feature threading systems. | printed |
| `state` (3) | a unit's own numbers, not a fact about the game. | printed |

**The three `state` members are a membership defect with a count on it, not a
kind.** `UnitProgression`, `GambitList` and `AbilityLoadout` pass the purity
predicate below by its letter and fail it by its intent — ADR-0271 soft spot S4 —
and [ADR-0241](../../docs/adr/0241-unitprogression-is-the-catalogues-by-ownership-and-src-datas-by-address.md)
dec. 1 already ruled `UnitProgression` the Character Catalogue's *by ownership*.
They are **13 of the 426/13 arm-5 split** the Character Catalogue owes this addon.
They were to be paid by a move (**#1059 phase 3**) rather than by widening a set;
[ADR-0300](../../docs/adr/0300-1059-phase-3-is-rejected-because-the-move-retires-nine-arm-5-lines-and-pays-ten-and-one-reach-has-no-published-name.md)
**rejects the move** — it retires nine lines and pays ten, and `BaseStatsDatabase`
has no published name for the relocated file to reach it by — so **13 is the floor**
and the lines stay printed as a price.

⚠ **THEY WERE 36 UNTIL #1180, AND 23 OF THOSE 36 WERE NEVER AN INSTANCE OF THIS
DEFECT.**
[ADR-0294](../../docs/adr/0294-the-catalogues-progression-debt-is-a-vocabulary-and-the-kernel-is-where-a-value-set-lives.md)
dec. 1 read them line by line: 23 named an *enum declared inside*
`UnitProgression` — `EquipSlot` 16, `BaseStatType` 4, `Zodiac` 2, plus one alias
that existed only to carry the third — and a line reading
`UnitProgression.EquipSlot.HEAD` does not use `UnitProgression`. Dec. 2 admitted
the three enums to the shared kernel as ADR-0118 dec. 1's **twelfth** schema row
and `UnitProgression` re-exports them, so no call site was respelled. The 13 that
remain are the three members being **held and constructed**, which is exactly what
S4 named. The register is UNCHANGED by that pass — `EquipSlot` was never published
on the façade, so no member's kind moved.

⚠ **Eleven `rule` at ADR-0273; twelve at ADR-0278; ELEVEN AGAIN SINCE #1159,
AND THE TWO ELEVENS ARE DIFFERENT SETS.** `UnitRole` left for the shared kernel
(ADR-0118 dec. 1's eleventh schema row, ADR-0280 dec. 3) because it held no
derivation at all, so neither `table` nor `rule` could name it — which is the
one case ADR-0273 dec. 5's tie-break does not cover, and the register lost a row
rather than re-ruling one. The twelfth was
`AbilityFamily`, and it is a `rule` on dec. 1's own test rather than on the
tie-break: it answers what an ability is FOR (`damage` / `healing` / `buff` /
`debuff`), and delete its computation and nothing is left — where deleting
`ShopAvailabilityDatabase`'s leaves a ROM table still answering that member's
headline question. ADR-0278 dec. 9.

⚠ **Seventeen `table` at ADR-0273; eighteen since #1120.** The eighteenth is
`ShopAvailabilityDatabase`, and it was derived from dec. 1 rather than from its
name: reading the kind off the `*Database` spelling is the by-name proxy that ADR's
considered alternatives rule out, and that section measures it under-counting this
map by eight. It owns a bank and seven
of its ten queries pluck a stored field; the close call is `is_stocked`, which
reproduces a named ROM gate. Dec. 5's tie-break was checked rather than assumed — no
sibling addon and no `src/` file names the member, so arm 5 read the same **373 free
/ 36 debt** under either word. **The debt did not move.** The free side went 371 → 373
on that member's own two `ExMateriaPlatform.JsonAsset` lines, which ADR-0139 dec. 9/12
permits and every sibling `*Database` here already has. (373 is the register AS IT
READ AT #1120 and is deliberately not re-stamped — it is **408** today for a reason
with nothing to do with this derivation, see the arm table below, and re-stamping a
past A/B with a later total would make it unreproducible.)

⚠ **This is not the provenance count above and does not contradict it.**
*"Twenty-two of the thirty-two members are ROM tables"* counts where a member came
**from**; `MEMBER_KINDS` counts what it **answers**. `EquipCandidates` encodes ROM
equip legality (RE round 49) and `StatusEncoder` packs the ROM's own status bits —
both are ROM-sourced and both compute, so both are `rule`. Neither number is wrong.
The worked example here used to be `UnitRole`, which ADR-0280 dec. 3 measured was
never ROM-sourced at all: FFT has no roles, the derivation belongs to
`JobDatabase.get_job_role`, and the member has since left for the kernel (#1159).

Ties go to `rule`. A member wrongly called `rule` costs a printed line somebody can
falsify; one wrongly called `table` costs silence, and ADR-0271 dec. 5's own
sentence is that *"a wrong bucket is a claim someone can falsify, and silence is
not"*. Both directions are held by the guard: every name the façade publishes must
appear in the register exactly once, and every name in the register must be
published — a member added without a row **raises the whole guard**.

**Three members are NOT published**, and the façade's own *NOT published, and
why* block is the register that says which and why.

`progression/BaseStatsDatabase.gd` is the extraction's one, because zero files
outside this addon name it: it is read only by `StatCalculator` and
`UnitProgression`, its own siblings. It is shed, not exported. Thirty-two moved;
thirty-one are reachable.

`items/EquipSlot.gd` and `abilities/AbilitySlot.gd` joined it later (**#1123**):
the equipment-slot and ability-slot vocabularies, lifted out of `UnitProgression`
and `AbilityLoadout` so they STAY here when those two `state` members leave for
the Character Catalogue. Each is re-exported by the member it came from —
`UnitProgression.EquipSlot`, `AbilityLoadout.Slot` — so no host file names either
path, and publishing them would move the published count for a surface nobody
outside reaches.

## What this addon does NOT carry, and the two things it does

`check_addon_portability.py` scores seven arms over every addon root. This one
opens with:

| arm | count |
|---|---|
| 2 — host autoloads named | **0** |
| 5 — sibling-addon `class_name` | 15 rows over 14 files, 60 lines — 12 `ExMateriaPlatform.JsonAsset`, the declared port, and 3 `ExMateriaSchema.UnitRole`, the shared kernel (#1159) |
| 6 — `res://` path outside the addon | **0**, and `ARM6_BURN_DOWN` is EMPTY |
| 7 — `class_name` outside every addon root | **0**, and `ARM7_BURN_DOWN` is EMPTY |

🔴 **No extracted addon before this one opened with both burn-downs empty.** Both
were EARNED at the move rather than declared away, and each cost a deletion:

- **The shader parity check left.** `status/StatusRegistry.gd` used to hold
  `const SHADER_PATH := "res://src/gpu/shaders/combat_common.glslinc"` and parse
  it to assert its `STATUS_*` bits had not drifted from the GPU's. A portable
  table cannot hold a path into the game it was extracted from. The assertion now
  lives only in `tests/StatusRegistryTest.gd::_test_shader_parity`, which already
  re-implemented it in full **and is the stronger instrument**: it `_expect`s and
  FAILs, where the registry's copy could only `push_error` from a static
  initializer that fires at most once per boot. ADR-0251 dec. 4.
- **A dead constant left.** `encounters/BattleConditionalDatabase.gd` held
  `const OP_RUN_SCENARIO := BattleConditionalOpcode.RUN_SCENARIO` off a host enum.
  ADR-0243 dec. 7 offered three ways to sever it — alias, inline, or one
  `ARM7_BURN_DOWN` row with an owner. Measured, a fourth answer existed: the
  constant had **two occurrences repo-wide**, its own declaration and the ADR's
  quotation of it. No caller had ever read it. Deleting it is what lets arm 7 open
  at zero. ADR-0251 dec. 5.

The arm-5 rows are the conformant residual [ADR-0223](../../docs/adr/0223-a-reach-has-a-bucket-and-an-address-and-goal-5-only-ever-read-the-bucket.md)
dec. 8 books as a PORT rather than debt: `ExMateriaPlatform.JsonAsset` is the
payload-loading port, and `plugin.cfg`'s `deps=` declares its addon so the stranger
rig stages it.

⚠ **That count was 11 at the extraction and BOTH of its words were wrong by #1159.**

- **Eleven → twelve**, because #1120's `ShopAvailabilityDatabase` arrived with its own
  two `JsonAsset` lines. That drift is the same one #1158 fixed at five other sites;
  this site was missed there and is corrected here.
- **Twelve → fifteen**, because #1159 moved `UnitRole` to the kernel, so `Gambit.gd`,
  `TargetSelector.gd` and `JobDatabase.gd` now name a SIBLING's `class_name` where
  they used to name a path inside their own root. `JobDatabase.gd` is why fifteen rows
  span only fourteen files — it names both symbols and gets a row each.
- **"Lines" → rows.** The guard prints one row per *(file, symbol)* and lists every
  line number on it, so these fifteen rows are **sixty lines**. The two words were
  interchangeable while every row held two or three lines; `JobDatabase.gd` names
  `UnitRole` twenty-three times and `TargetSelector.gd` nine, and they are not
  interchangeable any more. This is also why the whole-tree free side moved
  373 → **408** rather than 373 → 376 — the three new rows are thirty-five lines.

**The debt side did not move at any of the three.** A reach INTO the kernel is what
ADR-0202 dec. 2 rules free, so the free number going up is a member becoming MORE
shared — read it as an install-time dependency count, never as a score.

## The payloads travel with their readers

**Thirteen JSON files moved into the addon**, one beside each database that
reads it — not twelve, which is what ADR-0243 dec. 4 counted; `ItemDatabase`
carries two (`items.json` *and* `item_attributes.json`). ADR-0251 decs. 2 and 6.

They are 2.9 MB of the addon's 3.7 MB. `tools/asset_census.py` reports the root
under `(NO FORMAT RULE)`, which is where all six addon roots report, and it is
the largest of them by roughly 3×.

🔴 **`tests/stranger/exmateria_almanac/` is the only instrument that proves the
payloads actually travelled.** A payload left behind in `assets/` is not a parse
error and no static guard in `tools/` would see it — the addon would install,
load, and then come up empty-handed at runtime in a project that is not this one.
The rig installs the addon under a foreign `project.godot` and resolves the staged
`res://addons/exmateria_almanac/**.json` paths for real.

    ./tests/stranger/exmateria_almanac/run.sh

## `AbilityDatabase.gd` is generated, and "24,111 lines" is not the size of this

`tools/generate_ability_database.py` writes `abilities/AbilityDatabase.gd`
(19,418 lines) and `abilities/AbilityView.gd` (271) from the ROM export. It moved
with its output — its `ADDON_DIR` constant points here — and `--check` is what
asserts the checked-in files match what the generator would write today.

🔴 **Do not quote the package's line count flat.** 24,484 lines live under this
root; 19,689 of them are those two generated files and 305 more are the façade
and `plugin.gd`. **The hand-written size of what moved is 4,490 lines** across 30
files. ADR-0251 dec. 6 records this because ADR-0243 quoted the flat number and it
makes the extraction read as roughly five times the work it was.

## Where the buckets went

`tools/classify_blueprint.py` books every source file to a system. The thirty-two
files' **addresses** all changed and their **buckets did not** — 2 `generated`,
11 `content`, 5 `UI`, 12 `Battle`, plus the two `infrastructure` rows this addon's
own plumbing adds. #945 asked for the ~36 exact rules to collapse into one
directory rule on ADR-0184 dec. 3's precedent; measured, that cannot be had, and
`classify_blueprint.py`'s own header comment carries the three-part reason.
ADR-0251 dec. 7.

There is deliberately **no catch-all rule under this root**, so a file added here
books `UNCLASSIFIED` and the classifier exits non-zero until someone decides what
it is.
