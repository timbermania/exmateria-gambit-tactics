# `AbilityView` is a generated typed façade over the ability record

`AbilityDatabase.get_ability(id)` hands back a raw `Dictionary`, so the
[ability record](../context/05-ability-data.md)'s schema — key names, defaults, which
fields are nullable — is re-typed as string literals at ~13 read sites
across 14 files (`GPUAbilityLoader` alone pulls 19 fields with
`ability.get("field", default)`). A renamed or forgotten key silently
substitutes a default, the same silent-missing-key failure
[ADR-0003](0003-unit-encode-is-a-single-looped-schema.md) eliminated on the
unit-encode path. We add an `AbilityView`: a typed, flat **mirror** of the
ability record, **generated** from the same source that emits the
`ABILITIES` store, so the schema lives in exactly one authored place and no
hand-written caller types a field key.

## Status

accepted

## Considered options

- **Generated typed façade over the dict (chosen).** `AbilityView` wraps
  the existing `const ABILITIES[id]` dict **by reference** and exposes one
  generated typed accessor per field (`view.formula_y`). It is emitted by
  `tools/generate_ability_database.py` alongside the `ABILITIES` dict, from
  the one `INCLUDED_FIELDS` list, so a field added there appears on the view
  on regenerate with no extra step — the membership-by-source move of
  [ADR-0001](0001-gpu-combat-buffer-layout-is-shader-authoritative.md). The
  dict stays the **single stored representation** (no data doubling in an
  already 17k-line generated file); the view is a transient `RefCounted`
  built on demand. Chosen because it makes the "one schema location" win
  *structural* — the schema can't live in two places because only the
  generator writes it — at zero migration risk, since the view coexists with
  the dict over the same store.
- **Widen the existing `AbilityData`** to also carry the ~22 raw fields.
  Rejected: `AbilityData` is a lossy cast-path *projection* (it transforms
  `ct` ticks → `charge_time` seconds, derives `base_damage`/`effect_path`,
  and joins in an item's `chemist.z_value`). Fusing the 1:1 mirror into it
  puts `ct` (ticks) next to `charge_time` (seconds) on one object — the
  "two meanings of the same field" trap. The mirror and the projection are
  different concepts; see Consequences.
- **Hand-author `AbilityView`.** Rejected: it becomes a fourth place the
  ability schema is typed (after `INCLUDED_FIELDS`, the generated dict, and
  the JSON), free to drift — exactly the drift class ADR-0001/0003 exist to
  retire.
- **Big-bang swap** `get_ability(id)` to *return* `AbilityView`. Rejected:
  GDScript has no compile-time check, so every missed `.get("field")` is a
  silent runtime default — the failure this change exists to remove. The
  additive path lets each migrated site be verified by running its scene.
- **Hand-annotate `INCLUDED_FIELDS` with per-field types.** Rejected in
  favor of **inferring** type / default / nullability by sampling all 512
  records at generation time. The data is the fixed, complete universe of
  ROM abilities — no runtime record can appear that the generator didn't
  see — so inference is *exact*, not heuristic, and re-derives correctly on
  every regenerate. A hand-annotated type list is one more thing to get
  wrong against the data.

## Why this is not a re-litigation of ADR-0002

[ADR-0002](0002-unit-state-snapshot-stays-string-keyed.md) rejected a typed
view for the **combat unit-state snapshot**, on two grounds that **do not
transfer** here:

- *Typed-local weakness.* ADR-0002's win would have been parse-time typo
  safety, which in GDScript only materializes when every one of 176
  consumers holds a typed local — "as strong as the weakest unannotated
  consumer." `AbilityView`'s claimed win is **(B) single schema location +
  discoverability**, which is *discipline-independent*: there is simply no
  `"formula_y"` string literal at the call site to mistype, annotated local
  or not. Type-safety where a caller happens to annotate is a bonus, not the
  justification.
- *Allocation cost.* The snapshot is rebuilt per-unit-per-frame (176 sites
  on the hot path). `get_ability_view` is a **load-time / interaction-time**
  lookup at ~13 sites; the per-call façade allocation is irrelevant.

So the string-keyed snapshot stays as ADR-0002 decided; the string-keyed
**ability dict** is the different case this ADR changes.

## Consequences

- **One mirror, two projections.** `AbilityView` is the raw 1:1 record
  mirror (one typed accessor per record field, no transformation).
  `AbilityData` is the equipped-action-menu projection (three fields —
  `id`, `display_name`, `mp_cost` — with item-ability MP zeroed). The
  cast path itself does **not** go through `AbilityData`: `CombatLoop`
  and `GPUAbilityLoader` read the `AbilityView` directly via
  `AbilityDatabase.get_ability_view(id)`, so this projection is sized for
  the equipped-set UI / max-MP filter and nothing more.
  `LearnableAbility` is the learn-list projection
  (`src/data/LearnableAbility.gd`, four fields — `id`, `name`, `jp_cost`,
  `category` — where `category` is derived from which skill-set slot the
  id came from and the ability's `ability_type`). Both projections are
  built *from* an `AbilityView` (so even projections stop typing record
  keys); their consumer families are disjoint (equipped-set UI vs.
  job-learn UI + `UnitProgression`), so the "two projections in one
  object" trap that retired the cast-path fields from `AbilityData` also
  keeps the learn fields off it.
- **The view mirrors the *denormalized* record, flat — not the ISO tables.**
  The `ABILITIES` record is already a join across ~6 source tables (Ability
  Data + Attributes in `SCUS`, the type-specific tables, Ability Animations
  + the Effect map + the text section in `BATTLE.BIN`), resolved at
  extraction time by `tools/parse_abilities.py`. No runtime caller queries
  by table, so the view does not re-introduce that normalization. The one
  cross-table input the projection needs — an item's `chemist.z_value` — is
  the **items table** and stays off the view; `AbilityData` keeps fetching it
  from `ItemDatabase`.
- **Inference defines three behaviors per field.** Type coercion to the
  observed non-null type; a typed zero-value default for **sparse** fields
  (the generator emits a key only `if field in data`, so e.g.
  `start_seq_slot` / `sustain_seq_slot` are never present and a getter must
  `.get(key, default)`, never `_d[key]`); and **null preserved** for
  `effect_id` / `effect_file`, whose null is the semantic "no effect file"
  that callers test for. (Aside surfaced during design: nothing emits
  `*_seq_slot`, so `AnimationStateController`'s `get("sustain_seq_slot")`
  reads only ever hit the default today — a latent dead-read, left alone.)
- **The database surface is mirror/projection only — no dict surface.**
  The public methods are: `get_ability_view(id) -> AbilityView`,
  `get_all_views() -> Array[AbilityView]`, `ability_ids() -> Array`,
  `get_view_by_name(name) -> AbilityView`,
  `get_views_by_type(type) -> Array[AbilityView]`,
  `get_learnable_abilities_for_job(job_id) -> Array[LearnableAbility]`,
  plus the formula/predicate helpers (`is_healing`, `is_damage`, …) and
  the skill-set methods (`get_skill_set` and its action/rsm accessors,
  which carry a different shape from an ability record and stay as-is).
  Dict-returning methods are retired: `get_ability(id) -> Dictionary`,
  `get_ability_by_name`, `get_abilities_by_type`, `get_abilities_with_effects`,
  and the dict-shortcut accessors `get_ability_name(id)` and
  `get_ability_jp_cost(id)` are removed; callers read `view.name` and
  `view.jp_cost` instead. The single escape hatch is `view.to_dict()` on
  `AbilityView` itself, for the rare caller that genuinely needs the
  underlying record (e.g. data export). The `ABILITIES` const stays
  internal as the single stored representation; it is no longer reachable
  through the public surface. The generated file may keep typing keys
  internally because it *is* the source and cannot drift.
- **One enforcement net, not two.** Unlike ADR-0001/0003 — which needed a
  boot-time GDScript validator because the schema was *hand-authored*
  GDScript the Python `--check` couldn't see, across two independently-edited
  files — `AbilityView` and the `ABILITIES` dict are emitted by **one
  generator pass from one source**. A boot validator would check the
  generator against itself. Enforcement is therefore a single net: add
  `--check` to `generate_ability_database.py`, run as a pure-Python preflight
  in `tests/run_all_tests.sh` next to `gen_gpu_layout.py --check`. This also
  closes a **pre-existing gap** — the ability database had no staleness check
  at all, so a stale committed `AbilityDatabase.gd` went uncaught.
- **Testable without a `RenderingDevice` or the store.** `AbilityView` is
  built from a plain dict (`from_record({...})`), so a pure-GDScript test
  asserts the three inferred behaviors (coercion, default-on-absent,
  null-preservation) over fixtures with no DB, no scene, no GPU.
- **Not part of `bootstrap_assets.sh`.** `AbilityView` is generated shader-
  adjacent code emitted with the database, not itself an ISO-derived asset.
  A monorepo-wide *idempotency* check for committed extracted artifacts
  (regenerate → assert byte-identical, per the **Committed extracted
  artifact** principle and `docs/adr/0001-iso-derived-assets-reproducible.md`)
  is a worthwhile separate effort and is explicitly out of scope here.
