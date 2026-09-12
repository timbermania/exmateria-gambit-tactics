# Animation routing: small state enum, per-state resolution tables in one atlas

> **Note (2026-06-05):** The runtime class introduced here as `AnimationAtlas`
> was later renamed `AnimationResolutionMap` (per ADR-0024 and the CONTEXT.md
> cluster term *animation resolution map*). The body of this ADR retains the
> original `AnimationAtlas` naming as it stood when the decision was made.

Today the rules that decide which SEQ slot a unit plays live in **five
disjoint places**: hardcoded match blocks (`GPUCombatTestBase.gd:1126-1129`
for weapon→attack-anim routing), hand-authored JSONs
(`state_animations.json`, `reaction_animations.json`,
`wep1_names.json`), GDScript constants (`WeaponAnimationSelector.CATEGORY_BASE`
and friends), parser-time mappings (`SEQ_FILE_MAPPING` in
`tools/parse_sprite_types.py`), and implicit conventions (react slot ids
are universal; slot `1` is a stub; `StateAnimationDatabase` falls back to
`type1` for missing states — a docstring lie about "TYPE1-as-base
inheritance" that FFT does not actually have). Every routing bug we've
found is a symptom of this scattering.

We commit to the architecture that already wins in this repo for similar
problems (ADR-0001 shader-authoritative, ADR-0003 unit encode schema,
ADR-0008 generated facade, ADR-0013 parser-boundary decoding): **one
unified artifact built offline, runtime is a thin query layer**. For
animation, that artifact is the **animation atlas**, and the model is
**small high-level state enum + per-state resolution tables**.

## Status

accepted

## Decision

- **The `AnimationState` enum stays small** (~24 high-level activities:
  IDLE, WALKING, ATTACKING, SPELL_CHARGING, …). We **do not** explode it
  to one enum value per concrete (sprite_type, equipment, height, facing)
  combination — that approach would mean 100+ enum values and still
  wouldn't enumerate ability-driven cases. The state names what the unit
  is doing at the gameplay level; how it visually resolves is data.
- **Each state has its own resolution shape.** IDLE resolves on
  `(sprite_type) → BODY slot`. ATTACKING resolves on `(sprite_type,
  item_type, vertical, facing) → {BODY slot, WEP1 slot}`. SPELL_CASTING
  reads ability data (`effect_anim_id * 2`). The atlas is the **union of
  per-state resolution tables**, not a uniform `(state × sprite_type) →
  slot` matrix.
- **The animation atlas** is the unified queryable artifact. Sources it
  joins:
  - ROM-derived `weapon_animation_ids` table at `BATTLE.BIN 0x...` (the
    per-item-type weapon-attack slot table that this codebase currently
    hardcodes and TacticsEngineG already parses)
  - Hand-authored semantic labels (the 2208-row
    `animation_names.txt` from TacticsEngineG — `(sprite_type, slot) →
    human label` for every slot in every sprite type)
  - Existing per-state tables (`state_animations.json`,
    `reaction_animations.json`)
  - Sprite-type routing rules (TYPE2 uses WEP2; TYPE2 uses TYPE3.SEQ;
    react slots are universal — all become **explicit data** in the
    atlas, not implicit code)
- **No TYPE1-as-base fallback.** A state that's not in a sprite type's
  resolution table is **explicitly null** — the caller decides what to
  do, never silently routes to TYPE1's slot id. The fallback at
  `StateAnimationDatabase.gd:75-78` is the architectural bug-waiting-to-
  happen this ADR retires; the slot `1` stubs hand-authored into
  `state_animations.json` are the data-side mask that hid it.
- **The resolution viewer** is the dev tool that makes the atlas
  authorable. A scene with a live `Unit` plus a debug panel where the
  inputs are **gameplay circumstances** (job, gender, equipment, target
  elevation, state, react cue) and the outputs are the **resolved per-
  layer slots being played** plus the atlas-source readout (which table
  resolved this; whether a slot fell through to hardcode or hit the
  atlas). The viewer is how the atlas grows: a circumstance with no
  atlas entry is a TODO surfaced visually, not a production bug
  discovered later.
- **Runtime queries through one interface.** Production calls
  `AnimationAtlas.resolve(state, sprite_type, ctx) → {body, wep1, eff1}`
  (or per-state methods like `resolve_attack(...)`). The hardcoded match
  in `GPUCombatTestBase.gd` and the constants in
  `WeaponAnimationSelector.gd` migrate to atlas queries over time, not
  in one rewrite.

## Consequences

- **The `AnimationState` enum's role sharpens**: it's the *gameplay
  state*, not the *resolved animation slot*. The earlier audit
  (DAMAGED / BUFFED / DEBUFFED move to React; WAITING is an input
  dimension; ARMS_RAISE is ambiguous) lands more naturally — those
  enum values were trying to be resolved slots, not gameplay states.
- **`state_animations.json` becomes one input the atlas consumes**, not
  the authoritative table. Slot `1` stubs go away — the atlas's "no
  resolution for this combination" is explicit null, not a slot id.
- **The TYPE1-as-base fallback** at `StateAnimationDatabase.gd:75-78`
  becomes wrong by construction. Its docstring's claim about FFT
  inheritance is a lie. Delete the fallback as part of migration.
- **The hardcoded weapon match** at `GPUCombatTestBase.gd:1126-1129`
  becomes data. ROM `weapon_animation_ids` parsing
  (`tools/parse_weapon_animation_ids.py`, new) writes
  `assets/sprites/weapon_animation_ids.json`; the atlas reads it.
  TacticsEngineG already does this — we borrow the technique.
- **The viewer is load-bearing tooling, not throwaway**. Without it the
  atlas grows blind and bugs surface only in production. With it the
  atlas is grown interactively, scenario-by-scenario, and each
  circumstance gets a visible "resolved via atlas" or "resolved via
  hardcode fallback" verdict.
- **Migration is incremental.** No grand rewrite. State by state:
  ATTACKING first (biggest hardcoded match, biggest payoff); then
  USING_ITEM, SPELL_CASTING, the rest. Production paths flip to atlas
  queries one at a time. Old hardcoded constants and JSON files remain
  until their state migrates, then get deleted.
- **TacticsEngineG's `animation_names.txt` is borrowed verbatim** as the
  slot-metadata layer (2208 rows, all 13 sprite types). Copy into
  `assets/sprites/animation_names.csv`; it powers the viewer's slot-
  label readout and gives the atlas a hand-authored label per
  (sprite_type, slot) without us re-doing the labeling work.

## Considered options

- **One giant `AnimationState` enum** with concrete (state, equipment,
  height, facing) combinations as enum values, and one flat `(enum,
  sprite_type) → slot` table (rejected). At 24 states × 8 sprite types ×
  ~10 weapon categories × 3 heights × 2 facings, the enum explodes to
  4000+ values; ability-driven cases (SPELL_CASTING per ability id)
  still don't fit; the table is mostly null. The shape doesn't match
  how FFT was designed — per the `weapon_animation_ids` ROM table,
  weapon-attack routing is its own resolution function, not a
  pre-enumerated state.
- **Keep the current per-place rules; just fix the bugs** (rejected). We
  spent a session finding bugs — the TYPE1 fallback, the slot `1` stubs,
  the hardcoded match. Each fix is local; each leaves the next bug in
  the next place. The system bug is the scattering itself.
- **Build the atlas without the viewer** (rejected). The atlas is a
  ~5-source join with at least 6 axes; building it without an
  interactive validator is the same shape as the bugs we just found.
  The viewer is what turns "did this circumstance resolve correctly?"
  into a question with an answer.

## Migration order (concrete first steps)

1. **Borrow `animation_names.txt` from TacticsEngineG** —
   `~/TacticsEngineG/src/fftae/SeqData/animation_names.txt` →
   `assets/sprites/animation_names.csv`. Pure data import, no code.
2. **Stand up the v0 atlas + v0 viewer in tandem.**
   `src/animation/AnimationAtlas.gd` (v0 = ATTACKING resolution
   replicating the current hardcode, plus a thin stub for IDLE);
   `src/debug/ResolutionDebugPanel.gd` (v0 = job + weapon + elevation
   pickers, with a readout panel showing resolved slots);
   `assets/scenes/ResolutionViewerScene.tscn` (live Unit on a tile,
   debug panel docked).
3. **Parse `weapon_animation_ids` from BATTLE.BIN.**
   `tools/parse_weapon_animation_ids.py` (new) →
   `assets/sprites/weapon_animation_ids.json`. The atlas loads it; the
   v0 hardcode in atlas v0 deletes.
4. **Migrate `GPUCombatTestBase._start_attack_animation`** to call
   `AnimationAtlas.resolve_attack(...)`. The hardcoded match block dies.
5. **Migrate StateAnimationDatabase**: delete the TYPE1 fallback;
   `StateAnimationDatabase` becomes a thin atlas pass-through for
   state→slot lookup, then is deleted entirely as the atlas absorbs
   `state_animations.json` directly.
6. **Each subsequent state** (USING_ITEM, SPELL_CASTING, SINGING, …)
   migrates the same way: write its resolution function in the atlas,
   add its viewer surface, flip its production callers, delete the old
   path.
