# ExMateria Sprite Rig

The Final Fantasy Tactics unit-sprite rig, as a Godot 4 addon.

> **🔴 THIS IS A SKELETON.** Today the addon is a façade, a plugin entry, the
> SEQ opcode vocabulary and the content port. The rig's population — sprite-layer composition,
> animation playback, the material variants — still lives under the host's
> `src/animation/` and moves in under #744. Read every count below as a
> measurement of the skeleton, not a description of the rig.

## The one global name

`ExMateriaSpriteRig`, and nothing else (ADR-0212 dec. 1). Godot has no package
scope: a `class_name` is engine-global, so every one an addon declares lands in
*your* project's global scope. Everything this addon publishes is a constant on
that one name, and `tools/check_addon_globals.py` holds both directions —
nothing else here may declare a global, and nothing published here may dangle.

| published | what it is |
|---|---|
| `ExMateriaSpriteRig.AnimationOpcodes` | the SEQ opcode vocabulary: `Op` (what a sequence step carries), `SideEffect` (what a playback step emits), and `from_string` |
| `ExMateriaSpriteRig.ContentPort` | the content port: seven scalar queries over four FFT key spaces, which **you** implement (see below) |

Alias it back if you want the bare spelling (ADR-0211 dec. 4):

```gdscript
const AnimationOpcodes = ExMateriaSpriteRig.AnimationOpcodes
```

## What YOU have to supply: the content port

The rig does not know what a combatant **is**. It asks for numbers keyed by FFT
ids and it owns the pixels. That question is `ExMateriaSpriteRig.ContentPort`,
and this addon implements **none** of it — you do, as an autoload named
`SpriteRigContent` with these seven methods:

```gdscript
func weapon_v_offset(item_id: int) -> int            # ROM ITEM id
func wep1_frame_offset(weapon_type_id: int) -> int   # weapon TYPE id
func wep2_frame_offset(weapon_type_id: int) -> int
func eff1_frame_offset(weapon_type_id: int) -> int
func job_body_palette_row(job_hex: String) -> int    # job id, lowercase hex STRING
func job_is_monster(job_hex: String) -> bool
func ability_effect_anim_id(ability_id: int) -> int
```

🔴 **THAT IS FOUR KEY SPACES, NOT ONE "FFT ID".** A ROM item id, a weapon type
id, a job hex string and an ability id are disjoint, and every int one
typechecks against every other. The key kind is carried in every parameter name
for exactly that reason — the WEP1 graphic table is keyed by ROM item id and
**not** by `items.json`'s `graphic` menu-icon index, and a wrong key samples the
wrong row rather than failing.

The binding is a node-path lookup resolved at call time, not a compile-time
edge, so **the addon loads and runs with no adapter at all**. Every query then
answers what an empty content set would — `0`, or `false` — except
`ability_effect_anim_id`, which answers `-1`, because `0` is a real answer there
(an ability that exists and has no cast animation). The full table is in
`content/ContentPort.gd`'s own docstring.


An alias is a **per-class** declaration, not a per-file one — a script that
extends one already aliasing the name must not repeat it, or the parse error
takes the whole child out.

## What is deliberately NOT published

- **The scene.** `assets/scenes/Unit.tscn` names the rig by `ext_resource` path
  and is a `check_lattice_scene.py` `DECLARED_MOUNTS` row. Publishing it as a
  constant too would give one publish two spellings — a symbol channel and a
  path channel naming the same thing — and pass 9 two numbers for one question
  (ADR-0217 dec. 3, ADR-0205 dec. 2).
- **`Op` and `SideEffect` separately.** They share four member names at
  different integer values, so they stay in one file (ADR-0217 dec. 6).

## Install

Copy `addons/exmateria_sprite_rig/` into your project's `addons/`. There is
nothing to enable: `plugin.gd` installs nothing, because the addon is reached by
symbol and by declared mount, neither of which is an editor registration.

Then register your content adapter as the `SpriteRigContent` autoload — an
`[autoload]` line is the one binding a consuming project can write and an addon
cannot. Skip it and the rig still runs; it just draws with unshifted sheets and
default palette rows.

`plugin.cfg` declares what this addon needs — `engine="stock"` and no `deps`.
Both are still true with the port in: it touches no compositor primitive and
reaches no sibling addon. Both remain claims about the skeleton and are
re-measured when the population arrives.

## Design

`docs/adr/0217`, `docs/adr/0215`, `docs/adr/0212`, `docs/adr/0139`.
