# Unit owns the animation resolution map call

The [animation resolution map](../context/18-sprite-layers.md)
(`AnimationResolutionMap`, renamed from `AnimationAtlas`) turns
`(unit state, world state)` into a `(body_slot, wep1_slot, eff1_slot)`
triplet. ADR-0021 introduced the per-state resolver shape but left open
**who calls it**: any caller that wants to play an animation could
consult the map and pass the resolved slots to a slot-based playback
entry point, or the unit could own the call internally and expose
semantic methods (`unit.attack(vertical)`, `unit.cast_spell(ability_id)`,
…).

Today the slot-based pattern is what exists. `Unit.start_attack_with_animation(front, back)`
takes pre-resolved slot ids; the caller (the [GPU combat
loop](../../src/gpu/CombatLoop.gd) at lines 877 and 979; the
in-progress viewer) does the lookup separately. There is no entry point
for ability-driven SPELL_CASTING / SPELL_CHARGING / ABILITY_CHARGING —
that path was unbuilt before ADR-0021. The new [Unit Animation
Viewer](../context/18-sprite-layers.md) needs both, which forces
the question.

## Status

accepted

## Decision

The unit owns the resolution-map call. Activity changes that take
world-state parameters become **semantic methods** on Unit.

The five rules below were decided by this ADR but were only ever stated as
prose. They are numbered here on 2026-08-28 so `ADR-0024 dec. N` is a
checkable citation; the anchor scanner read **zero** decision anchors on this
file before the numbering, so no existing citation could break. Nothing is
added and nothing is retired by the numbering — Amendment 1 records what the
code says about each one.

1. **`unit.attack(vertical: int) -> void`** — sets activity to ATTACKING,
   reads `item_type_id` from `unit_progression`'s right-hand slot and
   `use_back` from `facing_direction + camera_quadrant`, consults
   `AnimationResolutionMap.resolve_attack(...)`, drives the BODY / WEP1
   layer playbacks from the resolved slots.

2. **`unit.cast_spell(ability_id: int) -> void`** — same shape against
   `resolve_spell_casting` / `resolve_spell_casting_two_hands` (two-hand
   detection reads the left-hand slot).

3. **`unit.charge_ability(ability_id: int) -> void`** — same shape against
   `resolve_spell_charging` / `resolve_ability_charging`.

4. **Parameterless activities keep the property setter.** IDLE, WALKING,
   DYING, BLOCKING, etc. keep using the existing `unit.activity = X`
   property setter; those don't need world-state inputs beyond facing.

5. **The slot-based entry point is a transitional internal, then retires.**
   The legacy `Unit.start_attack_with_animation(front, back)` stays as a
   **transitional internal** — `unit.attack(...)` initially delegates to it
   under the hood, and the two CombatLoop sites at `CombatLoop.gd:877` and
   `CombatLoop.gd:979` migrate to `unit.attack(vertical)` /
   `unit.attack_with_item_effect(item_id)` opportunistically. When all
   callers have migrated, the slot-based entry point retires.

## Alternatives considered

**Option A — callers consult the map, pass slots to Unit.** The viewer's
panel would do:

```gdscript
var r := AnimationResolutionMap.resolve_attack(sprite_type, item_type_id, vertical, use_back)
unit.start_attack_with_animation(str(r.body_slot), str(r.body_slot + 1))
# …also drive WEP1 / EFF1 layers from r.wep1_slot / r.eff1_slot…
```

Rejected. Resolution-knowledge scatters across every caller — viewer,
CombatLoop, future AI-targeting code, future cinematic playback —
each independently has to know the right `resolve_*` to call and which
layers to wire. Two callers can disagree on which slot to play.
Defeats the "one lookup table" intent of ADR-0021.

**Option C — single dispatcher method `unit.set_activity(activity, ctx)`.**
One method on Unit that takes an activity enum and a Dictionary of
world-state params. Rejected as the primary surface: less self-documenting
than three named methods, type-unsafe ctx contents, and the activities
that need params have *different* params (vertical for ATTACKING, ability_id
for SPELL_CASTING), so a uniform method signature buys nothing the per-method
shape doesn't already have.

## Consequences

**Resolution lives behind one door.** Anyone who wants the unit to attack
calls `unit.attack(vertical)`. The map is consulted in exactly one place.
A future ADR-0021 follow-up that changes resolver signatures touches Unit
plus the resolver; not every caller.

**Unit's public surface widens by three methods.** The viewer's panel is
the first consumer; CombatLoop migrates as a follow-up. The methods aren't
debug-shaped — they're the shape gameplay wants once it's fully
ADR-0021-ified.

**`unit_progression` becomes a read dependency of the playback path.**
`unit.attack(vertical)` reads the equipped right-hand item to derive
`item_type_id`. Today the resolution still happens against a snapshot at
call time; if `equipment_changed` fires mid-animation, the playback
doesn't re-resolve. Good enough for v1 — re-resolution-on-equipment-change
during an in-flight attack is rare and would be its own design.

**The viewer's panel becomes pure UI.** No `AnimationResolutionMap.*`
calls in the panel; just dropdowns that call `unit.activity = X` for
parameterless cases and `unit.attack(...)` / `unit.cast_spell(...)` /
`unit.charge_ability(...)` for parameterized ones. The "Source: atlas /
miss" readout reads back the Resolution returned by Unit (via a
`unit.last_resolution` accessor or returned from the methods).

## References

- ADR-0021 — per-state resolution shape (this ADR is its caller-side
  follow-up)
- ADR-0019 — sprite layers (slot semantics)
- ADR-0020 — one animation clock per unit (playback authority the resolved
  slots feed)
- CONTEXT.md → [animation resolution map](../context/18-sprite-layers.md),
  [unit state](../context/18-sprite-layers.md), [world state](../context/18-sprite-layers.md),
  [Unit Animation Viewer](../context/18-sprite-layers.md)

## Amendment 1 — the transitional internal is gone, two named resolvers never existed, and five call sites cite this ADR for someone else's decision

Graded against the tree on 2026-08-28. The shape decided here is **built**:
Unit owns the map call, the panel is pure UI, and the slot-based entry point
the Decision called transitional has retired on schedule. Three things moved
underneath it, and one class of citation does not belong to this ADR at all.

### Per decision

| dec | where it lives now | held? |
|---|---|---|
| 1 `unit.attack` | `src/units/Unit.gd:739` | **built, one clause superseded** — `attack` no longer derives `use_back`; it passes `false` unconditionally and `AnimationResolutionMap.resolve_attack` takes the argument as `_use_back` (underscored: unused). Front/back is picked per paint from the live camera in `UnitDisplay._paint_body_variant`, which is ADR-0053's one-dispatcher rule. Layer driving also widened: `display.apply_resolution(r)` (`src/animation/UnitDisplay.gd:220`) drives BODY / WEP1 **and EFF1**, not the BODY / WEP1 pair this decision named. |
| 2 `unit.cast_spell` | `src/units/Unit.gd:762` | **half** — the method is built and reached from gameplay, but the two-hand half **never landed**. `resolve_spell_casting_two_hands` exists nowhere in the tree; `resolve_spell_casting` (`AnimationResolutionMap.gd:338`) takes only `(sprite_type, ability_id, use_back)` and `cast_spell` reads no left-hand slot. |
| 3 `unit.charge_ability` | `src/units/Unit.gd:797` | **half** — built against `resolve_spell_charging` (`AnimationResolutionMap.gd:363`) only. `resolve_ability_charging` was never written, and the string `ABILITY_CHARGING` appears in **no** file under `src/` or `tests/`. So of the three unbuilt paths the opening paragraph names (SPELL_CASTING / SPELL_CHARGING / ABILITY_CHARGING), two landed and the third has neither an activity nor a resolver. `charge_ability`'s own docstring says per-ability charging poses await the BATTLE.BIN `0x2ce10` table parser. |
| 4 parameterless keep `unit.activity = X` | `Unit.update_animation()`, `src/units/Unit.gd:874` | **holds, by a route this ADR did not name** — the setter is still the surface, but the parameterless path now runs `AnimationResolutionMap.resolve_for_activity` (`AnimationResolutionMap.gd:199`) behind it, so the resolver is the single authority for *both* halves rather than only the parameterized one. |
| 5 transitional internal retires | — | **CLOSED** — `start_attack_with_animation` is defined nowhere; the only surviving mention in code is the historical note at `src/units/Unit.gd:844` ("The predecessor `start_attack_with_animation`"). Both named migration sites landed: `CombatLoop.gd:1566` calls `unit.attack(vertical_angle)` and `CombatLoop.gd:1721` calls `caster.cast_spell(ability_id)` — the ADR's `:877` / `:979` are stale line numbers for the same two sites. |

### The surface is four methods, not three, and its names are load-bearing strings

`unit.attack_with_item_effect(item_id)`, named in decision 5 as a migration
target, **never existed**. The item path shipped instead as a fourth semantic
method the ADR never named: `Unit.use_item(ability_id)` (`src/units/Unit.gd:779`),
same shape, against `resolve_using_item`.

Gameplay does not call any of the four directly. `ActivityTranslator._translate_parameterized`
(`src/gpu/ActivityTranslator.gd:94`) dispatches by **method-name string** —
`"use_item"` at `:42`, `"charge_ability"` at `:48` — via `unit.call(method, param)`.
That is a consequence this ADR did not foresee: renaming a semantic method
breaks the GPU-driven path silently, with no compile error, because the name
is data rather than a call.

### `last_resolution`'s own contract contradicts itself in the file

The Consequences here promise a `unit.last_resolution` accessor, and it exists
(`src/units/Unit.gd:736`), read by the viewer panel (`:415`), by `CombatLoop.gd:1581`,
and by three tests (`GPUCombatTestBase.gd:184`, `GPUPhysicalAbilityTest.gd:163`,
`GPURangedCombatTest.gd:94`). But the comment block introducing it
(`src/units/Unit.gd:731-733`) still says it is "Null between calls or after a
parameterless activity change", while `update_animation` writes
`last_resolution = r` on **every** parameterless resolve (`src/units/Unit.gd:905`).
Decision 4's new route (above) is what changed it. The stale half is the
comment, not the behaviour — the viewer readout depends on the write.

### The panel consequence holds

"The viewer's panel becomes pure UI" is true and measurable:
`src/debug/UnitAnimationViewerPanel.gd` contains **zero** `AnimationResolutionMap`
references. It calls `_unit.attack` / `_unit.cast_spell` / `_unit.charge_ability`
at `:340` / `:342` / `:344` and reads the readout from `_unit.last_resolution`.

### Five call sites cite ADR-0024 for ADR-0062's decision

Three source files name `ADR-0024` for a decision this ADR does not contain —
unit-anchored gambit movement:

- `src/gpu/shaders/stage_compute.glsl:475` and `:1095` — "Unit-anchored reposition (ADR-0024)"
- `src/gpu/shaders/stage_pathfind.glsl:555` — "Unit-anchored gambit MOVE (ADR-0024)"
- `src/gpu/shaders/combat_common.glslinc:203` and `:242` — `LOGICAL_ACTIVITY_APPROACHING` and `ACTION_MOVE_TO_UNIT`, both "(ADR-0024)"

ADR-0024 says nothing about gambits, movement, `ACTION_MOVE_TO_UNIT`, or
`LOGICAL_ACTIVITY_APPROACHING`. The owner is
**[ADR-0062](0062-gambit-movement-is-one-move-command-flavor-emergent-from-target.md)**,
whose decision names `ACTION_MOVE_TO_UNIT` as "a new GPU primitive" and whose
consequences name `LOGICAL_ACTIVITY_APPROACHING` as the activity carrying it.
The register's `code` count for this ADR is therefore inflated: three of the ten
source files that mention `ADR-0024` mean `ADR-0062`. The citations are **not**
corrected here — that is ADR-0062's audit to make, and a bare `ADR-NNNN` carries
no anchor, so `check_adr_anchors.py` is structurally blind to the whole class.

### References graded

All three back-references resolve to live designs, not to reverted ones:
ADR-0021's resolver is `AnimationResolutionMap` (`src/animation/AnimationResolutionMap.gd:1`),
ADR-0019's layers are `SpriteLayerManager` (`src/animation/SpriteLayerManager.gd:2`),
ADR-0020's clock is `AnimationPlayback` (`src/animation/AnimationPlayback.gd:1`).
All three ADRs read `accepted`.
