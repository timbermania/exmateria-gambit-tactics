# Ability data

The vocabulary that distinguishes the raw per-ability record from the
typed objects built over it. The easy mistake is calling them all
"the ability" — they are a store, a record, one **mirror**, and the
**projections** built off it (one per consumer family: equipped-action
menu, job-learn list). The cast path itself reads the mirror directly,
no projection.

**AbilityDatabase**:
The generated, in-memory store of all 512 ability records and 176 skill
sets (`src/data/AbilityDatabase.gd`, a `const` dict). Auto-generated from
`assets/abilities/{effects,skill_sets,ability_attributes}.json` by
`tools/generate_ability_database.py`; never hand-edited. Its public
surface is **mirror/projection only**: `get_ability_view(id)`,
`get_all_views()`, `get_view_by_name(name)`, `get_views_by_type(type)`
(all returning `AbilityView`); `get_learnable_abilities_for_job(job_id)`
returning `Array[LearnableAbility]`; the formula predicates
(`is_healing` / `is_damage` / …); and the skill-set accessors
(`get_skill_set` and friends carry a different shape from a record). The
internal `ABILITIES` `const` dict is the single stored representation
(ADR-0008); it is not reachable through the public surface. A caller
that genuinely needs the raw record (e.g. data export) reads it via
`view.to_dict()` on `AbilityView`.
_Avoid_: "ability table" — it is the flattened store, not an ISO table;
adding a `get_ability_X(id) -> X` dict-shortcut method (`name`, `jp_cost`,
`mp_cost`, …) to the database surface — these re-introduce the
field-key-on-the-database failure mode the [AbilityView] mirror retires
(read `view.X` instead).

**Ability record**:
The flat, denormalized per-ability data the game reads — a join across
~6 ISO source tables (Ability Data + Attributes in `SCUS`, the
type-specific tables, Ability Animations + the Effect map + the text
section in `BATTLE.BIN`) resolved **at extraction time**. The table
boundaries are a parser concern (`tools/parse_abilities.py`); the runtime
sees one flat record and never re-normalizes by table.
_Avoid_: modeling the source tables at runtime; "ability attributes"
alone (that is one of the joined tables, not the whole record).

**AbilityView**:
The typed, flat mirror of an [ability record](05-ability-data.md) — one named
field per record key, no transformation. The single place the ability
schema lives, so the ~13 callers that read raw fields (`formula_y`,
`jp_cost`, `elements`, …) stop re-typing string keys. A 1:1 mirror, not a
projection: it carries `ct` in ticks, not seconds.
_Avoid_: putting derived or cross-table data on it — `chemist.z_value`
is the **items table**, so it stays off the view (see [AbilityData]).

**AbilityData**:
The **equipped-action-menu projection** built from an [AbilityView]
(`src/data/AbilityData.gd`, a `Resource`): three fields the equipped-set
UI and the roster's max-MP check actually consume — `id`, `display_name`,
`mp_cost`, with item-ability MP zeroed (items don't cost MP regardless of
what the record carries). Constructed by `AbilityData.from_database(ability_id)`;
held on `EquippedAbilities` (`unit.equipped_abilities.abilities`) and read
by `ProgressionTester` (the equipped-set display row). The per-ability
`mp_cost <= unit.max_mp` filter it also served went with `BaseRoster`
(ADR-0180) and has no home on the catalogue path today. The cast
path **does not** go through this type — `CombatLoop` and
`GPUAbilityLoader` read the [AbilityView] directly via
`AbilityDatabase.get_ability_view(id)`, so this projection deliberately
does not carry `charge_time` / `effect_id` / `range` / formula or any
cast-path field.
_Avoid_: conflating with [AbilityView] — that is the raw mirror, this is
the equipped-set projection; re-widening it to mirror the record (the
[AbilityView] is the mirror); adding a field that no equipped-set
consumer reads — `AbilityData` stays exactly as wide as the equipped UI
needs (the failure shape that left `charge_time` / `base_damage` /
`effect_path` write-only here before this narrowing).

**LearnableAbility**:
The **learn-list projection** built from a skill-set + ability-record
join (`src/data/LearnableAbility.gd`): the typed row the job-learn
screen renders. Four fields — `id`, `name`, `jp_cost`, and `category`
(action / reaction / support / movement) — where `category` is *derived*
from which skill-set slot the id came from (`actions` → "action") and
the ability's `ability_type` (Reaction / Support / Movement under
`rsm`). Lossy and joined; deliberately discards the rest of the record.
The sibling of [AbilityData]: same family (projection over the record),
different consumer (`UILearnPanel`, `UnitProgression.get_learnable_abilities`,
`ProgressionTesterTest`). Built by a database-side enumerator that
walks the job's skill set; the database surface returns
`Array[LearnableAbility]`, never `Array[Dictionary]`.
_Avoid_: conflating with [AbilityView] — `category` is *not* a record
field, so it cannot live on the mirror; widening [AbilityData] to also
carry the learn-list fields (it is the cast-path projection, a different
consumer family — the same "two projections in one object" trap that
keeps `ct` off [AbilityData]); leaving the four-field shape as an
untyped `Array[Dictionary]` once the typed projection exists.

**AbilityCandidates (picker catalog)**:
The **formation-picker projection** — the rows the ability "Set" picker
renders for one focused slot (`src/data/AbilityCandidates.gd`, static
`build_catalog(slot) -> Array` of `{id, name}`). Deliberately a **catalog,
not a loadout**: it lists *every* applicable option independent of the unit
and honors **no** progression gate. R/S/M slots = every ability of the
slot's type ([AbilityDatabase] `get_views_by_type`, blank-named ids
dropped); Secondary = **one row per unique skillset name** (deduped from
every job — many jobs share a skillset), the row id being the skillset's
**representative job**: the generic job (0x4A–0x5D) that owns it when one
exists, else the lowest job id (ADR-0197 dec. 7; commit writes that job
id as `sub_job_id`). Rows are text-only and name-sorted (id as the tie-break). The
analog of the equipment picker's `EquipCandidates.build_catalog` (all
slot-legal items, ownership ignored). A **testing scaffold, not the
shipping behavior** (ADR-0197): the real picker will gate/filter to the
unit's learned/unlocked set, and the swap is one wiring seam in
`_open_ability_picker`. Its gated sibling — retained untouched as the real
path — is **learned-gated candidates** `AbilityLoadout.candidates`, which
draws only from what the unit has actually learned/unlocked. Because the
catalog honors no gate, it offers (and lets you commit) options the unit
could not legally set — non-generic (special/monster) sub-jobs and
unlearned abilities; commit is unvalidated (sandbox), so a pick can write a
technically-illegal loadout.
_Avoid_: calling it "the unit's abilities" (it is neither the unit's
loadout nor its legal candidate set); conflating **catalog** (all
applicable options) with **candidates** (what *this* unit may set) — the
same `build` vs `build_catalog` split [EquipCandidates] draws.

**JobCandidates (Learn picker catalogue)**:
The **job-domain twin** of [AbilityCandidates] — the rows the formation
"Learn" job picker renders (`src/data/JobCandidates.gd`, static
`build_catalog() -> Array` of `{id, name}`). Unit-independent, pure, and
gate-free: **every** job in `jobs.json` carrying at least one JP-costed
learnable ability — 80 of 160 (56 special, 19 generic_human, 5 monster).
Dropping the barren 80 is **data hygiene, not a gate** (an empty learn list
renders a dead row that can never commit). `id` is the **hex-string job
index**, which is the picker's key: the host reads this unit's
Lv./Total/Next/Jp off its progression by that id, so those per-unit numbers
are deliberately *not* on the row (the picker is a renderer — LEARN_PICKER.md
round 10 #5). Rows are name-sorted with the **job index** as the tie-break,
which is load-bearing: **19 display names are shared by more than one job
index**, six jobs being named "Squire" (`01/02/03/04/07/4a`) with different
learn lists — `03` carries Ultima at 9999 JP, the generic `4a` does not.
Those six render as identical unsuffixed rows (the ~90 px JOB column cannot
take a hex suffix; the four number columns disambiguate). A **testing
scaffold, not the shipping behavior** (ADR-0198): the swap is one wiring seam
in `_open_job_picker`. Its gated sibling — retained untouched as the real
path — is `UnitProgression.get_unlocked_jobs()`, generic jobs the unit has
unlocked. Unlike the ability catalog, **the JP gate still applies**: the
catalogue widens what is *listed*, not what is affordable.
_Avoid_: treating the display NAME as the job key (six Squires); calling the
80 a "filter" or "gate" (it is hygiene — every listed job is committable);
assuming a job index is generic-only.
