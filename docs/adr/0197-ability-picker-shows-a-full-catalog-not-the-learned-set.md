# Ability picker shows a full catalog for now, not the unit's learned set

**This is a testing scaffold, not the shipping behavior.** The real game will
gate/filter the ability picker to what the unit has actually learned and
unlocked (`AbilityLoadout.candidates`). The picker points at a full catalog to
exercise its scroll/render pipeline before that progression data is real.

**Status:** accepted, and provisional on purpose — the scaffold is the current
behaviour, and the gated path it replaces is retained untouched. The job-domain
sibling is [ADR-0198](0198-learn-job-picker-shows-the-full-job-catalogue.md).

Verified 2026-08-28 — decs. 1–7 built. Every number below was recomputed from
`assets/jobs/jobs.json` + `assets/abilities/skill_sets.json` independently of
`build_catalog`.

## Context

The formation ability "Set" picker sourced its candidates from the seeded unit's
own progression (`AbilityLoadout.candidates`), which is minimal — so the
Reaction/Support/Movement pickers were empty and Secondary offered only Chemist.
That left the 5-row scrolling window untested.

The scaffold replaces it with a full, **unit-independent catalog**
(`AbilityCandidates.build_catalog(slot)`) that honors **no** progression gate.
It is a stress test of the picker's scroll/render pipeline: **23 to 51 rows**
driven through a 5-row window, depending on slot. It mirrors the shipped
equipment picker's always-on `EquipCandidates.build_catalog` (all slot-legal
items, ownership ignored) — in the *gate*, not the *order*: the equip catalog
sorts descending by item id, this one name-ascending (decision 4).

This is **deliberately not ROM-faithful** and will look like a bug to a future
reader: a unit can normally only set abilities it has learned and generic
sub-jobs it has unlocked, yet this picker offers unlearned abilities and
non-generic (special/monster) skillsets.

## Decision

1. **The picker sources a full, unit-independent CATALOG, not the unit's own
   progression.** `AbilityCandidates.build_catalog(slot)` stands in for
   `AbilityLoadout.candidates(slot)` and honors **no** progression gate.
2. **Reaction / Support / Movement: every ability of the slot's type.** Keyed by
   `AbilityDatabase.get_views_by_type`; blank-named ids dropped; the row `id` is
   the ability id. Reaction 32 records − 1 blank = **31**, Support 32 − 3 = **29**,
   Movement 24 − 1 = **23**.
3. **Secondary: one row per unique skillset NAME**, deduped from every job in
   `jobs.json` — generic + special + monster, current job included. The row `id`
   is the skillset's representative job (decision 7), committed as `sub_job_id`.
   **48 of the 160 jobs never appear**: their `skill_set_id` is 176–223 and the
   skillset table has 176 entries, so the name lookup returns nothing and the row
   cannot be rendered. That is data hygiene, not a progression gate — decision 1
   still holds — but it is stated here because it is the whole difference between
   "every job" and the 112 that reach the dedup, and a reader comparing this ADR
   against `jobs.json` will otherwise not find it. 160 jobs → 112 named → **51**
   unique skillset names.

   Deduping is by **name**, not `skill_set_id`: the picker shows names, and
   distinct skillset ids can carry the same display name (two "Yin Yang Magic"
   records), which would still read as duplicate rows.
4. **Rows are text-only, name-sorted ascending with `id` as the stable
   tie-break.**
5. **Commits are unvalidated (sandbox).** A pick writes `equipped_*` /
   `sub_job_id` even when the resulting loadout is technically illegal.
6. **The gated path is retained, untouched.** `AbilityLoadout.candidates` stays
   as the learned/unlocked sibling and exactly one wiring seam
   (`FormationDetailTransition._open_ability_picker`) switched, so restoring the
   real gated picker is a one-line revert.
7. **A deduped skillset's representative job is the GENERIC job (0x4A–0x5D) that
   owns it, else the lowest job id.** Decision 3 shows one row where several jobs
   share a skillset, and every row still commits a `sub_job_id`, so one of them
   has to be stored. The generic is the skillset's player-meaningful owner —
   Item → Chemist `0x4b`, *not* the lower non-generic `0x35` that also maps to
   Item — and a plain lowest-id tie-break picked surprising story-job reps.
   Skillsets with no generic (Holy Sword, Guts, Fear, `SkillSet_00` …) are
   story/boss-only, are not legal secondaries in the real game anyway, and fall
   back to lowest id purely for determinism (Holy Sword → `0x05`). Functionally
   the equipped skillset is identical whichever job is stored — job→skillset is
   1:1 — so this decides only the stored and displayed job id.

## Considered options

- **Dedup Secondary by `skill_set_id` rather than by name.** Rejected: it leaves
  the visible duplicates the dedup exists to remove, because distinct ids carry
  the same display name. It is worth 30 rows — id-dedup measures **81**,
  name-dedup **51**.
- **One row per job, as first shipped.** Rejected on the same ground: 24 jobs
  collapse onto "SkillSet_00" and Delita/Agrias/Wiegraf all produce identical
  "Holy Sword" rows. 112 rows, most of them noise.
- **Attribute a skillset to its character rather than to its generic owner.** A
  job↔character mapping does exist in the ROM (FFTPatcher's `SpecialNames.xml`
  is indexed by the same byte as the job offset — `0x1e` = Agrias/Holy Sword),
  but it is **non-unique** — five job ids carry Holy Sword (`0x05`, `0x1e`,
  `0x34` as "Holy Knight"; `0x20`, `0x28` as "White Knight") — and it is a false
  friend in the generic range, where SpecialName `0x4b` = "Miluda" collides with
  the generic Chemist job slot. Generic-ownership is the meaningful key.
- **Drop the generic-less (story/boss) skillsets entirely.** Rejected: it would
  give every remaining row a clean 1:1 generic owner, but shrinks the scaffold's
  stress-test row count, which is the opposite of the scaffold's purpose.
- **An F3 debug toggle** (catalog opt-in, learned-gated by default). Rejected:
  the always-on catalog is the truer mirror of the already-shipped equip
  behavior.
- **Seed every unit with all abilities and jobs unlocked**
  (`AllTemplatesSeeder._minimal_progression`). Rejected because the always-on
  catalog needs no progression mutation. If units should ever *own* everything —
  so committed picks reflect a genuinely maxed unit rather than an illegal one —
  this is the escape hatch, but that is a different feature.

## Verification

- `tests/AbilityCandidatesTest.gd` derives its expected counts and literals from
  the asset data **independently of `build_catalog`** — the arithmetic is spelled
  out in its docstring — and asserts the count, well-formedness, the sort with its
  tie-break, no duplicate names, the prefer-generic representative (`0x4b`
  present, `0x35` absent) and the generic-less fallback (`0x05`).
- `tests/FormationAbilityPickerTest.gd` drives the picker through the real input
  path and asserts the scroll condition as a **property** (`row_count() > 5`)
  rather than a literal, which is why the 112 → 51 reversal did not disturb it.
  The window it scrolls is `AbilityPickerMenu.VISIBLE_ROWS := 5`.
- Decision 6's gated sibling keeps two guards of its own —
  `tests/AbilityLoadoutTest.gd` and `tests/AbilityLoadoutProgressionTest.gd` both
  call `candidates()` — so retiring the scaffold cannot silently retire the path
  it stands in for.
- **Nothing asserts that decision 6's seam is singular.** One call site of
  `AbilityCandidates.build_catalog` in `src/` is what makes the revert one line,
  and it is the claim most likely to rot as the picker grows.

See [CONTEXT.md](../context/05-ability-data.md) → "Ability data" →
**AbilityCandidates (picker catalog)**.
