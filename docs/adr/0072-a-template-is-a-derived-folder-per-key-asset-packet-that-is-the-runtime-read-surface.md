# A template is a derived, folder-per-key asset packet that is the runtime read surface

**Status:** accepted (implemented in slices via wayfinder map [#197](https://github.com/timbermania/fft-monorepo/issues/197): resolver #198/#199, residue manifest #202, schema locked #200; transform #201 + loaders #203 pending). Refines — does **not** reverse — [ADR-0066](0066-character-identity-is-a-slug-catalog-above-the-roster.md); its "derived, reproducible, downstream" contract holds. Dec. 4 amended by [ADR-0132](0132-assets-are-filed-by-consuming-system-not-by-provenance.md) (2026-08-20): the read-surface claim is the intended end state, not the built one.

## Context

ADR-0066 established that a `Character` (identity + data) is a *materialized
instance* of an immutable asset **template**, and that an offline
*character-alignment transform* derives those templates from the ROM-faithful
parser output. It left three things fuzzy, and a formation-screen handoff then
argued a load-bearing point in the *opposite* direction — that templates must
**not** be foldered:

1. **Do generics have templates, or only story units?** ADR-0066's "Character
   Profile" said generics have *none* ("many generic Characters share one
   job+gender sprite yet have no Profile at all") and that a Profile is not
   `job×gender`-shaped.
2. **Does a template carry stats?** "Character Profile" bundled a *stat block*
   with the assets.
3. **Physically, what is a template** — a stored packet, or an addressing
   convention over the flat `textures/NN.tga` store? The handoff insisted on
   the latter: *"a reconciliation manifest referencing the flat stores — zero
   duplication — NOT a physical re-folder,"* because three sharing axes (SPR
   file, animation TYPE, palette rows) cross-cut each other.

Grounding the sharing claim in the **extracted** assets (not the ROM source
the handoff described) overturned it:

- **154 sprite_ids, 136 distinct `.SPR` files.** Only **10** `.SPR` files are
  shared by >1 sprite_id, and for those the extract already writes
  **byte-identical** `.tga` + `.palette.tga` per id — the flat store *already*
  duplicates ~18 ids. "Flat = zero duplication" was never true.
- **Body sheet, embedded portrait, and palette are already 1:1 per sprite_id.**
  Foldering them duplicates **nothing new**.
- **Animation is the *only* genuinely shared asset** (154 ids → ~8 TYPE files:
  `TYPE1`×62, `TYPE3`×66, `MON`×18…). Copying it per template would be the one
  real duplication — so it must be a **reference**, not a copy.

So the handoff's "three cross-cutting axes" collapses to **one** for the real
assets, and it is trivially handled by a reference.

## Decision

1. **Every `Character` has a template — generics included.** The template is
   addressed by a **polymorphic template key** whose shape depends on category:
   generic-human `(job, gender)`, generic-monster `(job)`, unique
   `(character_id, version)`. This corrects ADR-0066 point (1). For a generic,
   `job` is both data *and* the key-router; for a unique, `job` is *only* data
   and never routes (a unique's sprite is job-invariant).

2. **A template is assets only.** Owned 1:1 assets (body sheet, embedded
   portrait, palette, formation sprite) plus a reference to the one genuinely
   shared asset (animation TYPE) and EVTFACE/EVTCHR pointers where they exist.
   **No stats.** A unique's ROM base stats *seed the `Character`'s data*, not
   its template. This corrects ADR-0066 point (2).

3. **A template is a derived folder — one "packet" per key.** It **owns** its
   1:1 assets — body sheet, embedded portrait, palette, and the **formation
   sprite** (also 1:1 with the sprite sheet: Ramza's three Forms have three
   distinct formation sprites; the transform *slices* each template's cell out
   of the shared `EVENT/UNIT.BIN` atlas into the folder, exactly as body
   sprites are already per-id). It **references** the one genuinely-shared
   asset — **animation TYPE** by name (`TYPE1`… — 154 ids → ~8 files) — plus
   `flying`/`height` and EVTCHR/EVTFACE pointers where they exist, via a small
   `template.json`. Fields are individually optional (a story-only unit like
   Balbanes-death may have EVTCHR + event portrait and *no* body sheet).

> **Upheld unchanged by [ADR-0142](0142-an-asset-belongs-to-the-system-that-owns-its-format.md) dec. 3-4
> (2026-08-21), explicitly.** #323 proposed nesting a system axis inside the
> entity folder — `characters/<key>/sprite_rig/…` — and the measurement rejected
> it: across the three packet classes the largest *second* system in any packet
> is **1.86%** of its bytes, and `maps/MAP###/` has none at all. The packet stays
> entity-shaped and flat; a system-named subdirectory is **exception-only**, and
> `effects/E###/` is the one measured exception.

> **Amended by [ADR-0132](0132-assets-are-filed-by-consuming-system-not-by-provenance.md) (2026-08-20).**
> Stated as fact here and in the ADR title; measured at `c1f1a56a8`, it is not
> yet true. `src/` holds **2** references to `assets/characters/templates/`
> (`AllTemplatesSeeder`, `ResidueManifest` — an authoring seeder and the residue
> bridge, neither a game loader) against **48** to the flat `assets/sprites/`
> store. The Status line above already scopes this — loaders (#203) are pending
> — so the decision stands as the target; only the tense is wrong.

4. **The template folder is the runtime read surface.** The game loads a unit's
   visuals *from its template folder*; the flat `textures/` store becomes the
   transform's **input**, not what the game loads. Replacing a file in a folder
   re-skins the unit — this is what makes the layout moddable, and is the whole
   point of foldering over a flat manifest.

5. **Templates stay derived and regenerable — never hand-owned as source.** The
   character-alignment transform emits them from the flat extract + a small
   hand-authored residue (the unique↔asset / EVTCHR bridge). "Organized as
   though authored" is an *ergonomic affordance for modders*, not a change to
   where truth lives. ADR-0066's reproducibility contract is intact.

6. **A single resolver** maps `Character → template key → template folder`,
   dispatching generic keys through the existing job tables and unique keys
   through the residue manifest. It is the seam *between* the character and the
   template — not part of either. (This answers the question that motivated the
   design: the asset lookup is neither "subservient to the template" nor "part
   of the roster.")

## Considered and rejected

- **Flat store + reconciliation manifest, no folders (the handoff's position).**
  Rejected: its premise (foldering causes duplication) is false for the
  extracted assets — only animation is shared, and that is referenced. A flat
  store gives no modding affordance, which is the goal.
- **Templates as an authored source of truth (hand-owned, seeded once).**
  Rejected: it would reverse ADR-0066's reproducibility contract — a re-extract
  could no longer safely regenerate a ROM unit's folder. Derived-but-legible
  gets the modding ergonomics without the reversal.
- **Materialize a stored template record per generic `job×gender`.** Unnecessary:
  generics already resolve through the existing job tables; only the *unique*
  manifest is new data.

## Consequences

- The **only new artifact** is the unique/EVTCHR residue manifest and the
  folder-emitting step of the transform; generics get a thin adapter over
  tables that already exist.
- Runtime asset loaders (`SpriteLayerManager`, `UIPortrait`) shift from
  `sprite_id → textures/NN.tga` to `template folder → asset`. Until the
  transform lands, the flat path stays; the resolver can front both.
- **Formation sprite is 1:1 with the template (owned), sourced from a shared
  atlas.** It comes from `EVENT/UNIT.BIN` (Shishi "Other Images → UNIT.BIN"),
  already parsed by `tools/parse_unit.py` →
  `assets/ui/formation/UNIT.{tga,palette.tga,json}`: one 256×480 4bpp atlas +
  128 CLUTs. Each template has its **own** cell (Ramza's three Forms → three
  distinct formation sprites — it tracks the sprite sheet, not the class), so
  the transform *slices* each template's cell into its folder, like the
  already-per-id body sprites; only animation stays genuinely shared. **Still an
  RE gap:** which cell + palette maps to a given template (the per-cell grid +
  pose→palette selection) is undecoded — open follow-up in
  `FORMATION_SCREEN.md` — so the field's *contents* can't be authored until that
  is cracked, though its *shape* (owned, 1:1) is settled.
- ADR-0066's "Character Profile" term is superseded by **template**; the
  `CONTEXT.md` glossary is updated accordingly (`template`, `template key`,
  `resolver`, revised `Form` / `materialized instance` /
  `character-alignment transform`; "default Character template" renamed to
  "default Character prototype" to free the word).

## Schema concretization (#200, 2026-07-18)

Wayfinder ticket [#200](https://github.com/timbermania/fft-monorepo/issues/200)
locked the concrete `template.json` schema + folder layout — the full contract is
in **[`docs/TEMPLATE_JSON_SCHEMA.md`](../TEMPLATE_JSON_SCHEMA.md)** (+
[`docs/template.example.json`](../template.example.json)). Two points **refine** the
decisions above:

- **Physical storage is generated + gitignored, NOT committed** (user decision
  2026-07-17). The folder tree lives at the already-baked
  `ResidueManifest.TEMPLATE_ROOT` = `res://assets/characters/templates/<token>/`,
  is gitignored (`/assets/characters/templates/`), and **regenerates** on a fresh
  checkout via the transform + `godot --import` — exactly like the other
  ROM-derived asset trees. This makes dec.5's "organized as though authored" an
  *ergonomic view of a generated tree*, not a committed source tree; and it makes
  the loaders' flat-store fallback (Consequence 2) **load-bearing**, since folders
  are absent until the transform runs.
- **EVTFACE/EVTCHR are OWNED (sliced, indexed), not referenced.** dec.2/dec.3 above
  grouped them with animation TYPE as pointers "where they exist." #200 refines
  this: **only animation TYPE stays a reference** — it is a genuine 20:1 structural
  share (154 ids → ~8 files). EVTFACE/EVTCHR have no such share (a character's face
  + cinematic frames are ~1:1 theirs), so the transform **slices** them into the
  folder as owned, individually-indexed collections (`events/face[]`, `events/chr[]`,
  each entry `{index, tag?, sprite, palette}`), duplicating nothing genuinely shared
  and buying the same moddability as the sliced menu portrait. Their *contents*
  (which cell/segment/frames) remain the open RE gap; only the *shape* is locked.

## Addendum — EVTFACE identity axis + the `cutscene-face` template category (2026-07-20)

Closes the EVTFACE half of the "which cell" gap above and adds a fourth template
category for portrait-only identities.

**The face axis is `(row,col)`, recovered from the dialogue speaker name.** The
EVTFACE grid is global + fixed (8×8, addressed by `(row,col)`); it carries no
character axis. The transform previously attributed each cell to the **ENTD
speaking `Unit`** — wrong: that byte is scene-local (cell `(1,2)` Mustadio is
spoken with byte 130 in one scene, 129 in another) and never resolves for
SPR-less speakers. The authority is instead the **[identity table]**: each `{10}`
message renders its speaker's name in a `{Color 08}` highlight header, so
`cell (row, Portrait−1) → that name` (predicate: `Dialog & 0x10` [bit 4],
`Portrait ∈ [1,8]`, a `{50}` row active). Derived corpus-wide by
`tools/evtface_identity.py`; reproduces the hand-authored §9 table 43/43, zero
false positives (`PORTRAIT_ROW_OPCODE_50_EVTFACE.md` §9.5). The face branch in
`event_asset_derivation.py` is **deleted**; `align_character_templates` folds the
identity table's SPR-backed cells into `result.tokens[tok].face` after the replay.

**Fourth category: `cutscene-face`** (glossary: [cutscene-face identity]). Nine
identities are named by dialogue but have **no ENTD unit, no SPR, no
`special_name`** (Balbanes, Besrodio, Gelwan, Kanbabrif, Flower Girl, Blansh,
Bolmna, Elidibs, Grevados-as-Cid). They get a **portrait-only** template — a
bare-slug folder (`templates/balbanes/`) with `events/face` cells and **no
`body.tga`**, the face doubling as the portrait, `template.json` category
`cutscene-face`.

**Decision: key them by slug, NOT a synthetic `special_name`.** dec.1's single-bit
dispatch (residue-membership → unique) stays for ENTD identities; a cutscene face
is **not** forced down it. Rationale — genuine trade-off:

- *Considered:* mint synthetic `special_name`s (≥256, reserved) so cutscene faces
  ride the existing unique dispatch. **Rejected:** `special_name` is invariantly
  the ROM ENTD byte (0–255); synthetic values pollute that ROM-tied namespace and
  break "`special_name` is materialized from an ENTD slot" (#202 seeding seam). A
  cutscene face is never seeded from ENTD.
- *Chosen:* key by **[slug]** — ADR-0066's identity currency. A cutscene face is a
  Catalog `Character` whose template happens to be portrait-only; the slug **is**
  its template key (the sole key shape where slug enters the key — there is no
  `job` and no `special_name`). The human identity call (which name owns which
  cell for the un-homed cells) is authored in a small `cutscene_faces.json`
  (slug → name + cells), the transform input that also seeds Catalog `{slug:name}`
  so the future authored-event path (`"show Balbanes' face"`) resolves by name.

**Boundary preserved.** The **legacy runtime is untouched** — it still renders
every face from the global grid (`EvtFaceCatalog`, `(row,col)→png`), including
generics. The per-identity `events/face` packet is **emit-only** (no `src/`
reader yet); wiring a consumer is the future "enhanced" path, out of this scope.
Pure generics (Knight, Priest, Bar Patron, Prisoner, Executioner…) are **not**
minted — the global grid serves them (mirrors the #206 generic-EVTCHR rule:
folders for identities, flat store for job-classes).
