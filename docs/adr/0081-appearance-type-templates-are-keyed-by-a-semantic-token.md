# Appearance-type templates are keyed by a semantic token, not a synthetic `special_name` or a raw sprite id

**Status:** accepted (2026-08-03). Extends — does not reverse —
[ADR-0072](0072-a-template-is-a-derived-folder-per-key-asset-packet-that-is-the-runtime-read-surface.md);
adds a fifth [template key] dialect beside unique / generic-human / generic-monster /
cutscene-face. Verified 2026-08-28 — decisions 1–10 all built; dec. 8 carries a named
18-sheet staging remainder held by a one-way ratchet.

## Context

ADR-0072's [resolver] reaches a `Character`'s [template] two ways: a **unique** by
its ROM `special_name` (`ResidueManifest` → folder), a **generic** by `(job,
gender)` (job tables → flat-store sprite id). But a real slice of the 154 sprite
sheets is reachable by **neither**: the story-townsperson sheets (`0x4A`–`0x5F` —
`40_year_old_woman`, `funeral_priest`, …) and a few specials (`0x98` Holy Dragon)
carry **no `special_name`** (the ROM only ever spawns them as `special_name = 0`
anonymous extras — `sprite_set < 0x80`, "the byte IS the SPR id," per
`_resolve_sprite_set`) and are the body of **no playable job** (no job's
`body_sprite_id` points at them). They are *appearance-types*: a distinct **sheet**
reused across many nameless instances, with an identity behind none of them. The
character-alignment transform (#222) already mints them a folder
(`templates/40_year_old_woman/`); what was missing was a runtime **key → folder**
route for a sheet that is not an identity and not a job.

This surfaced building the formation "all 154 templates" view: every unit resolves
to a `template_folder` that `SpriteLayerManager.load_body_sprite` reads (Agrias
already does — `special_name 52 → ResidueManifest → agrias_52/`), so an
appearance-type must reach its folder **by the same method**, differing only in the
key.

## Decision

1. **An appearance-type template is keyed by a semantic token** — the folder's own
   name (`"40_year_old_woman"`), carried on the `Character` as a `template_token`
   field distinct from its [slug].

2. **The [resolver] gains one branch:** a `Character` with a `template_token`
   resolves `TEMPLATE_ROOT + token` → the same `template_folder` every other unit
   returns, into the same `load_body_sprite`. `Category.APPEARANCE_TYPE` is the
   fourth member of the resolver's category enum.

3. **The other three keys are untouched.** `slug` stays identity, `special_name`
   stays the ROM byte, `(job, gender)` stays the job-routed generic key; nothing
   about the render path changes.

4. **Raw `sprite_set → token` conversion happens at the parser boundary.** Any raw
   `sprite_set → token` conversion an ENTD-driven spawn needs happens **at the
   parser boundary** (the transform already owns the `sprite_id → token` table,
   `GENERIC_SPRITE_NAMES`), extending
   [ADR-0013](0013-fft-bitmask-decoding-lives-at-the-parser-boundary.md)'s
   decode-at-parse discipline to the appearance handle — so the runtime keys
   templates by token, never by a hex sprite id.

5. **The catalogue mints a minimal progression, and says so at the seam.** The
   "show all templates" view (`AllTemplatesSeeder`) draws its roster from the
   template store, which carries no job or stat data — an appearance-type is
   reachable by no job by construction. A progression-less `Character` renders the
   right-hand unit-info panel and the vitals panel **empty**, so every minted
   `Character` carries a `UnitProgression` seeded with a neutral default job
   (Squire, `4a`) and the body stat type its category implies (`MONSTER`, else
   `FEMALE`/`MALE`). The **name** is real (from `template.json`); the job and stats
   are honest catalogue defaults, not per-unit truths. This is a catalogue view,
   not a roster editor, and the seam says that in words — a screen that *edits* a
   unit takes `PromotedRosterSeeder`'s roster instead, whose progression is the real
   one.

6. **Zodiac is derived from the ROM birthday, never defaulted.** FFT stores no
   zodiac byte — the sign is a function of a unit's birthday (ENTD slot bytes 4/5).
   `UnitProgression.zodiac_from_birthday(month, day)` is that pure function. A unit
   built from a raw ENTD slot reads its birthday directly
   (`Character.from_entd_slot`); the catalogue view — whose uniques have no slot —
   looks the `special_name` up in `UnitBirthdays`, a compact
   `special_name → {month, day}` table extracted from `entd.json` by
   `tools/parse_unit_birthdays.py`. A Random/None birthday (the game rolls it at
   recruit) has no fixed sign and keeps the default. Because the sign is a real
   per-unit truth rather than a catalogue default, `PromotedRosterSeeder` carries it
   across promotion instead of re-rolling it.

7. **The catalogue enumerates VARIANTS, not template folders.** A folder is a
   shared sprite sheet (`chocobo/` = `body.tga` sprite `0x86` + a multi-row
   `body.palette.tga`), so one row per folder **collapses** every sprite-sharing
   family — Chocobo / Black Chocobo / Red Chocobo (jobs `5e`/`5f`/`60`, palette
   rows 0/1/2) showed as the single row `chocobo` — and a unique folder has no
   canonical name of its own (`template.json.name` is null), so
   `meta.get("name", folder)` leaked the raw token (`adramelk_69`, `ramza_1`) into
   the list. The
   catalogue enumerates the identity the list is *about*, with name AND folder both
   **resolved from** the variant, never the variant key itself. Four sources, each
   routed by a dialect the resolver already dispatches — **no resolver change**:

   - **unique** (folder-sourced) — a `unique` folder; `special_name` = its decimal
     `template_key`, display name = the canonical `UnitNames.resolve(special_name)`.
     Slug `unique:<special_name>`, so a multi-Form character keeps its chapters as
     distinct rows sharing one derived name (Ramza Ch1/2/3 → three rows, all
     "Ramza"). 59 of them.
   - **appearance** (folder-sourced) — a `generic-human` folder that dec. 8's test
     admits; it carries the `template_token`. Slug `appearance:<folder>`.
   - **generic-human wardrobe** (job-sourced) — one row per wardrobe sheet, keyed
     `(job, gender)` and carrying **no token**, two rows for a job whose sheet
     differs by gender and one for a gender-invariant one (Bard `0x82`, Dancer
     `0x83`). Slug `generic:<job>[:m|:f]`. 20 jobs → 38 rows.
   - **monster** (job-sourced, **not** folder-sourced) — one variant per
     **renderable** monster job (`kind == "monster"` and its resolved body `.tga`
     exists on disk, which drops the `Unknown_*` sprite-0 jobs). Each carries its
     real `current_job_id`, so the GENERIC_MONSTER branch supplies the shared sheet
     plus the **job's palette row**, surfacing the families as distinct rows. Slug
     `monster:<job>`.

   `generic-monster` **folders are dropped** as a source (their monsters are
   job-sourced); `cutscene-face` folders stay skipped (no `body.tga`). The
   namespaced slugs are **variant-unique**, so the owned overlay's `add_owned`
   de-dupe no longer collapses sprite-sharing variants. The invariant is that the
   roster is **surjective onto uniques ∪ generic-human folders ∪ renderable monster
   jobs**, one row each, and every minted `Character` renders
   (`resolve_body_render().ok`).

8. **The appearance-type test is data-derived job-reachability.** A sheet is an
   appearance-type iff **no job's `body_sprite_id_male`/`_female` resolves to it** —
   the answer read out of the job tables, the same shape as
   `CharacterTemplateResolver._has_gender_axis`, never a hardcoded sprite-id range
   and never a shape flag. `template.json.category` does **not** answer this
   question: `align_character_templates.py::_generic_category()` derives it from the
   sheet's SHP family (is the skeleton humanoid?), a *body-shape* axis, and it
   matches all 77 human sheets. Of those 77:

   | bucket | n | reached by | examples |
   |---|---|---|---|
   | generic wardrobe | 38 | a `generic_human` job | `male_squire` 0x60 ← Squire, `female_knight` 0x65 ← Knight |
   | story bodies | 15 | a `special` job | `kanba` 0x1E ← Holy Knight, `h61` 0x17 ← Dark Knight |
   | monster sheets | 3 | a `monster` job | `goblin` 0x87, `skeleton` 0x8B, `squid` 0x8A |
   | **true appearance-types** | **21** | **no job** | `40_year_old_woman`, `funeral_priest`, `cyomon1..4`, `kasane*` |

   Only the last bucket satisfies dec. 1. The 38 in the first are not *appearances*
   at all — they are the generic job wardrobe, the very sheets `(job, gender)` is
   the key for; a token there pins each to one sprite for life, which defeats
   ADR-0072 dec. 1 (for a generic, `job` is both data *and* the router) and is the
   `_Avoid_` this ADR already names.

   **The staging is part of the decision, not a gap in it.** The 38 wardrobe sheets
   are corrected — that is the one bucket where the mislabel is *observable*,
   because they are the units that change job. The **15 story bodies and 3 monster
   sheets keep their token**: they are fixed-look either way (a monster's job is its
   species; a story body's job never changes), so re-keying them changes no
   behaviour, and it would trade the folder's own `portrait.tga` for the job's
   portrait in the catalogue's info panel. The token population is therefore
   **39 = 21 true appearance-types + an 18-sheet named remainder**, held as a
   one-way ratchet that may only go down, and only by retiring the remainder.

   The mechanized predicate is deliberately the narrow half of the stated one:
   `JobDatabase.generic_wardrobe_sprite_ids()` iterates only jobs where
   `is_generic_human(job)` holds, so it answers "no **generic-human** job reaches
   it". The 18 remainder are reached by `special` and `monster` jobs the narrow
   predicate cannot see, which is exactly why widening the predicate and retiring
   the remainder are the same act. Whether a story body lacking a `special_name`
   binding is a bucket of its own is a question this ADR does not answer.

   `_is_generic_wardrobe` gates **minting**, in `AllTemplatesSeeder` only. The
   resolver has no wardrobe check, so the invariant is "no seeder mints a wardrobe
   sheet with a token", not "a token on a wardrobe sheet is rejected" — a
   hand-built `Character` can still carry one.

9. **The token branch is tested first.** `CharacterTemplateResolver.template_key`
   checks `template_token != ""` **before** the residue and job branches, and the
   class docstring states it as policy: an explicit appearance-type token wins
   first. The ordering is load-bearing in both directions — it is what makes a
   correctly-tokened sheet job-invariant, and it is why a *wrongly* tokened sheet
   fails invisibly: the token short-circuits before `(job, gender)` is ever
   consulted, so the sheet simply never changes and nothing errors. A guard on this
   branch must therefore assert through the **rendered** address, not the key.

10. **Only a generic human's look follows their job.** A unique keys on
    `special_name` alone (Agrias-as-Wizard looks like Agrias — ADR-0072 dec. 1); a
    monster's job *is* its species, so it never changes job and keeps its sheet; a
    story body and a townsperson likewise keep their template sheet. The generic
    wardrobe is the one place appearance is a function of job, and there the job
    routes it. With the token population corrected by dec. 8, the token and job
    branches are mutually exclusive **by construction**, exactly as dec. 2 assumed.

## Considered and rejected

- **Mint synthetic `special_name`s** so appearance-types ride the existing unique
  dispatch. Rejected for the same reason ADR-0072's cutscene-face addendum rejected
  it: `special_name` is invariantly the ROM ENTD byte (0–255) materialized from a
  slot; a synthetic value pollutes that namespace and, worse, **asserts an identity
  the sheet does not have** — "the 40-year-old woman" is not one persistent
  individual in six towns at once.
- **Key the runtime lookup by the raw sprite id (`0x4F`)**. Not a literal ADR-0013
  violation (a sprite id is an atomic id, not bit-packed), but the semantic token
  already exists (the transform produces it, the folders are named by it), so keying
  by hex throws away the parsed handle. Token keeps the game side name-native.
- **Make the [slug] the template router** for these. Rejected: the slug is
  *identity* (ADR-0066), and a unit's appearance is *state* — a slug'd unit can
  change sheets (Forms), and many instances share one appearance-type sheet, so a
  sheet is not a slug.
- **`template.json.category == "generic-human"` as the appearance-type test** —
  *(shipped 2026-08-03, reversed 2026-08-20: it is a body-shape axis, so it admitted
  56 sheets a job does reach, 38 of them observably. Superseded by dec. 8.)*
- **One catalogue row per template folder** — *(shipped 2026-08-03, reversed the
  same day: it collapsed every sprite-sharing monster family into one row and leaked
  raw folder tokens as names. Superseded by dec. 7.)*
- **A precedence rule for a unit carrying both a `template_token` and a real job**
  (`(job, gender)` routes the body, the token supplies the face). Rejected. The
  observable symptom — a job change that never changed the sheet — was never a
  precedence conflict; it was 38 units holding a token they should never have had,
  and dec. 8 removes them. Should a playable, job-changing unit ever need a fixed
  sheet, *that* is when a precedence rule must be written, and it would be a new
  decision rather than an assumption made silently.

## Verification

- `tests/AllTemplatesSeederTest.gd` — decisions 5–10. It asserts the variant axis
  (one `Character` per expected variant, no duplicate and no stray row), the 59
  uniques each carrying their canonical `UnitNames` name, the chocobo family
  surfacing as three job variants sharing one sheet, the derived zodiac on a unique
  whose birthday is known, and that every minted `Character` renders.
- The two dec. 8 arms are the ones with teeth.
  `_test_no_wardrobe_sheet_is_minted_as_an_appearance_type` recomputes the wardrobe
  set from the job tables *independently of the seeder helper*, so it cannot pass by
  agreeing with the code under test; it pins the token population at **39** and the
  job-reached remainder at **18**, and the 39 is written down as a ratchet.
  `_test_wardrobe_rows_job_route_and_carry_no_token` asserts through
  `resolve_body_render` — the same seam the formation cell draws through — and
  checks the rendered texture path actually **moves** on a Squire → Knight change,
  because dec. 9 means a key-level assertion would have passed on the broken tree.
- `tests/CharacterTemplateResolverTest.gd` — decisions 2 and 3, and the
  token-before-job half of dec. 9: an appearance-type resolves to
  `TEMPLATE_ROOT + token` with no flat-store `body_sprite_id`, and a `4a` Squire
  carrying a token keys `APPEARANCE_TYPE` with no `special_name`, `job` or `gender`
  axis, while Ramza-as-Knight and Ramza-as-Monk still resolve to one unique folder.
- dec. 4 is held by absence, and the absence is checkable: `GENERIC_SPRITE_NAMES`
  lives in `tools/align_character_templates.py` and no GDScript file references it.
- The render path itself (`tests/FormationAllTemplatesMountTest.gd`) and the scroll
  windowing over a roster larger than the grid are follow-ons to this view, not
  assertions about these decisions.
