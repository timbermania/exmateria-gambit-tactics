# Sprite nomenclature is subject-qualified; body sprite ID is BODY-scoped

The word "sprite" was used loosely across the codebase. Tests, scenes, and
ADRs called the same thing several different ways — "sprite," "unit sprite,"
"body sprite," "particle sprite" — without a shared definition. The bare
field `Unit.sprite_id` was implicitly the **body** sprite's ID, but the name
didn't say that; meanwhile WEAPON and EFFECT layers have their own
identifier schemes (per-equipped-weapon WEP1 v-offset, per-keyframe
EFF1 framesets). On top of that, the post-`3da98be4` sprite-extract
refactor introduced ROM-faithful authoring names (`RAMUZA.SPR`, `MINA_M.SPR`)
that exist *only* in the extractor input and never propagated to the
runtime — but the principle ("ROM-derived names and hand-authored labels
never mix at the extraction boundary") only lived in the extractor's
docstring, not in any glossary or ADR. The result was two missing-sprite
bugs in quick succession — invisible caster from a stale `0x00` default,
invisible trap particles from a stale `TRAP1_pal*.tga` path — both
silently rendered transparent because `SpriteLayerManager.load_sprite_texture`
push_errored but bound nothing.

We tighten the nomenclature at three levels: a foundational `Texture`
versus `Sprite` distinction, subject-qualified sprite kinds (`Unit body
sprite`, `Particle sprite`, `Projectile sprite`, `Portrait sprite`,
`Status text sprite`), and a code rename for the most leaked identifier
(`Unit.sprite_id` → `Unit.body_sprite_id`). We also harden the runtime
to fail *loudly* — a magenta-checker fallback texture — when an invalid
body sprite ID reaches `SpriteLayerManager`, so the next instance of
this class of bug is visible in-scene instead of silently transparent.

## Status

accepted

## Decision

- **`Texture` ≠ `Sprite`**. A *texture* is on-disc image bytes (`.tga`,
  optionally with a `.palette.tga` companion per ADR-0022). A *sprite*
  is a rendered 2D billboard composed from one or more textures + a
  shader + framing data. The two words are not interchangeable; a
  `.tga` is never "a sprite," and a particle in flight is never "just a
  texture."

- **Sprite kinds are subject-qualified.** The bare word "sprite" is the
  smell this ADR retires. Every kind names its subject:
  - **Unit body sprite** — the character image on the BODY layer.
  - **Unit weapon sprite** — the held weapon on the WEAPON layer.
  - **Unit effect-layer sprite** — the small unit-attached overlay on
    the EFFECT layer. Distinct from the [particle](#) subsystem.
  - **Status text sprite** — damage numbers / status words on
    STATUS_TEXT.
  - **Particle sprite** — one of many quads spawned by an effect cast
    (E### or TRAP1 family). The particle subsystem owns rendering;
    "particle" alone is the everyday name, "particle sprite" is the
    glossary clarification that a particle *is* a kind of sprite.
  - **Projectile sprite** — single billboard quad for in-flight
    thrown weapons / items.
  - **Portrait sprite** — UI face image; reuses the portrait region of
    the unit body texture.

- **`Unit.sprite_id` → `Unit.body_sprite_id`.** The public-facing
  identity field gets a BODY-scope qualifier matching how the cluster
  vocabulary already talks about it. `UnitRosterData.sprite_id` →
  `UnitRosterData.body_sprite_id` for the same reason. **Scope of the
  rename is the public field name and its dot-access call sites** — not
  function parameter names, not local variables, not the
  `SpriteDatabase` accessor signatures, not `JobDatabase.SPRITE_NAMES`,
  not `assets/sprites/sprite_files.json`. Those are private internals
  whose context already disambiguates them.

- **Body sprite ID is ROM-faithful, sourced from BATTLE.BIN.** Authority
  for the 0x01..0x9A range is BATTLE.BIN's sprite-LBA table at
  `0x2DCD4` (159 records × 8 bytes), parsed by
  `tools/build_sprite_file_map.py` into `assets/sprites/sprite_files.json`.
  The mapping is **N-to-1**: a single `.SPR` file can back multiple
  body sprite IDs (`MINA_M.SPR` backs 8 humanoid-female slots). The SPR
  filename is *authoring provenance*, not a runtime identifier.

- **ROM-derived names and hand-authored labels never mix at the
  extraction boundary.** `sprite_files.json` is ROM-derived provenance
  (the FFT developers' authoring names). `JobDatabase.SPRITE_NAMES` is
  hand-curated display labels (FFTPatcher `SpritesheetNames.xml`).
  They answer different questions and must be sourced independently;
  conflating them was the smell this principle retires.

- **`0x00` is not a valid body sprite ID.** The ROM-faithful map starts
  at `0x01` (RAMUZA.SPR). Using `0x00` as "default" or "uninitialized"
  is the recipe that caused the invisible-caster bug. The `Unit.gd`
  export default is now `0x01`.

- **Invalid body sprite IDs fail loudly in-scene.** When
  `SpriteLayerManager.load_sprite_texture` can't resolve a body sprite
  texture, it binds a programmatically-generated magenta-checker
  fallback (4×4 indexed + 16×16 palette where index 1 of every row is
  opaque magenta) and still returns false. The unit renders as a
  glaring magenta blob instead of silently transparent; the
  push_error still fires for the log trail. Pure `push_error` was the
  status quo — and it hid two missing-sprite bugs because the visual
  outcome was "nothing visible," which reads as "didn't spawn" in QA.

## Considered options

- **Don't rename `sprite_id`; just document.** Define
  `Body sprite ID (a.k.a. sprite_id)` in CONTEXT.md, leave the field
  alone. Cheap (zero code change) but bakes in permanent doc/code drift —
  every new contributor would have to learn that the bare field name is
  imprecise. Rejected for the recurring confusion cost.

- **Deep rename — `SpriteDatabase` → `BodySpriteDatabase`,
  `sprite_files.json` → `body_sprite_files.json`,
  `SPRITE_NAMES` → `BODY_SPRITE_NAMES`, all function parameters too.**
  Maximally consistent and would also push the BODY-scope into all
  internal APIs. Rejected as a near-future option: the public field is
  the only identifier that leaks across module boundaries and confuses
  callers; the rest of the names are scoped to their files and
  disambiguate by context. We can revisit if a sibling `weapon_sprite_id`
  or `effect_sprite_id` identifier ever appears.

- **Retire the word "sprite" wholesale.** Use "billboard" or "rendered
  2D element" instead. Honest about the overload but breaks against
  decades of game-dev English where "sprite" *is* the natural word; the
  cost of writing around it everywhere is higher than the cost of
  qualifying it. Rejected.

- **Rename only the asset filenames.** Emit `RAMUZA.tga` instead of
  `01.tga` so the ROM-faithful name "permeates" all the way to disk.
  Incoherent given the N-to-1 mapping — `MINA_M.SPR` would have to
  claim a single sprite_id and the other 7 sprite_ids backed by the
  same SPR would need some second naming scheme. Rejected on
  data-model grounds.

- **Assert-and-halt on invalid body sprite ID.** Replace push_error
  with `assert(actual_path != "", ...)`. Maximally loud but breaks any
  edge case where a Unit briefly exists with an unresolved ID
  (scene-editor preview, mid-rebuild states, hot-reload). Rejected as
  too aggressive given Godot's lifecycle quirks.

- **Stay at push_error only.** Improve the error message but don't
  change runtime behavior. Doesn't actually fix the bug class — the
  visual outcome stays "nothing renders" and the next missing-sprite
  bug will look identical to the last two. Rejected.

## Consequences

- `Unit.sprite_id` and `UnitRosterData.sprite_id` are renamed to
  `body_sprite_id`. All consumers (16 .gd files) updated. JSON dict
  keys `"sprite_id"` in test fixtures (`tests/arena_roster.json` plus
  per-test config dicts) become `"body_sprite_id"`.

- `SpriteLayerManager.load_sprite_texture` gains a fallback path that
  binds a magenta-checker placeholder when texture resolution fails.
  The fallback textures are programmatically generated on first use
  and cached as static class members — no new asset files needed.

- The CONTEXT.md `Sprite layers` cluster gains a new `Body sprite ID`
  term covering the ROM-faithful identity pipeline + the
  "ROM-derived vs hand-authored never mix" principle. A new foundational
  `Sprite and texture` cluster sits before it, defining the two
  foundational terms and listing every kind of sprite this project
  produces.

- The `Sprite layers` cluster heading and its `#sprite-layers` anchor
  stay unchanged to avoid breaking the 35 cross-references already
  pointing into it.

- Future ADRs for weapon-side identity (`weapon_id`'s relation to
  WEP1 v-offset rows), status-text identity, or particle-system
  identity can reference this ADR as the precedent for
  subject-qualified naming.

## Migration

1. **Rename the field.** `Unit.gd` line 25 (`@export var sprite_id` →
   `body_sprite_id`); update all in-file references (setter, debug
   strings, accessor calls, doc comments). Same for
   `UnitRosterData.gd`.
2. **Update consumers.** Bulk-rename `\.sprite_id` (dot-access only) →
   `.body_sprite_id` across the 14 other consumer `.gd` files. Leave
   function parameter names (`func get_seq_type(sprite_id: int)`)
   alone — they are local to their function.
3. **Update JSON dict keys.** `"sprite_id"` → `"body_sprite_id"` in
   `tests/arena_roster.json` and in test-config dictionaries. The
   `assets/sprites/sprite_files.json` keys (hex strings `"01"`, `"02"`)
   are values not identifiers and stay unchanged.
4. **CONTEXT.md.** Add `Sprite and texture` cluster (defining `Texture`
   and `Sprite` with the subject-qualification rule). Add `Body sprite ID`
   term to `Sprite layers`. Convert remaining bare `sprite_id` mentions
   in the doc to `body sprite ID` cross-references.
5. **Add the fallback.** `_bind_fallback_body_texture()` in
   `SpriteLayerManager`, called from both failure paths in
   `load_sprite_texture`. Generates 4×4 indexed + 16×16 palette
   ImageTextures on first use; cached statically.
6. **Verify.** `GPUKnightBreakTest` continues to pass; `EffectViewer`
   shows the caster (no `00.tga` not-found errors); manually trigger
   the fallback by setting an out-of-range body sprite ID and observe
   the magenta-checker in-scene.
