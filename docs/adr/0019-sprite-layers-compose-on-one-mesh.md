# Sprite layers compose on one mesh per unit

A unit's four ROM-defined [sprite layers](../context/18-sprite-layers.md) —
`BODY`, `WEAPON`, `EFFECT`, `STATUS_TEXT` — render onto **one** billboard mesh
per unit. Each layer is a slot in a single `ShaderMaterial`, multiplexed in the
fragment shader; the layer-priority table from BATTLE.BIN feeds the shader as
state, and per-layer toggle is a uniform (`wep_enable`, `eff_enable`, …) not
scene-tree visibility. Layer ordering is a *shader concern*, not a Node3D
concern.

We considered the obvious alternative — one `MeshInstance3D` child per layer,
letting Godot's scene tree own per-layer Z and `visible` flags — and rejected
it for this codebase. Recording the decision so a future reader doesn't
"refactor" the shader-multiplexed model back into a scene-tree composition.

## Status

accepted

## Decision

- **One billboard mesh, one `ShaderMaterial`, four shader-side layer slots.**
  `SpriteLayerManager` owns the slots; each slot carries an SHP frame index
  and an enable flag. The fragment shader composites them in the order picked
  by an animation's [layer priority](../context/25-rendering-depth.md) entry
  (24 ROM-defined orderings, parsed into `assets/sprites/layer_priority.json`).
- **Per-layer toggle is a shader uniform, not `node.visible`.** Disabling the
  WEAPON layer writes `wep_enable = false` to the material; it does not free
  or re-parent any Node. Tests and runtime code never reach for a per-layer
  Node3D — there isn't one.
- **Per-layer Z within the unit is a shader concern.** Layer priority is read
  per-frame from the loaded table; the shader composites in that order. There
  is no per-layer depth bias on top of the unit's single
  [Ordering Table depth](../context/25-rendering-depth.md) sample point (the
  unit billboard samples its CUSTOM0 once for the whole unit — ADR-0009 — and
  intra-unit layering is non-depth).
- **`STATUS_TEXT` is the same model.** Damage numbers and status word
  graphics are sprite graphics in FFT, not Godot-font text — they fit the
  shader-slot model unchanged. We do **not** plan to render them through
  Godot's `Label3D` / font system; if that need ever arrives, it's the moment
  to revisit this ADR.

## Considered options

- **Per-layer `MeshInstance3D` child nodes (rejected).** Layer toggle would
  become `visible = bool`; per-layer Z would route through Godot's scene tree
  or per-mesh depth bias; mixing Godot UI text into `STATUS_TEXT` would become
  easier. But N draw calls per unit instead of one is a real cost at the unit
  counts a battle scene carries, and ADR-0009's CUSTOM0-depth model assumes
  one sample point per primitive — per-layer meshes would each need their own
  CUSTOM0 and own bias scheme. The shader-multiplexed model is what already
  works and what the ROM-table data feed naturally fits.
- **Hybrid (rejected).** `STATUS_TEXT` on its own mesh / scene node, the other
  three layers multiplexed. Splits the layer model into two cases for one
  speculative future need (Godot fonts) — same friction as full per-layer
  meshes without the corresponding scene-tree-ordering payoff.

## Consequences

- The [layer](../context/18-sprite-layers.md) vocabulary in CONTEXT.md is
  the *render-slot* vocabulary; it does **not** imply Node3D children. A
  reader who searches for `BODY` / `WEAPON` / `EFFECT` / `STATUS_TEXT` should
  find shader slots and SHP frame indices, not scene nodes.
- The [sprite type](../context/18-sprite-layers.md) (TYPE1 / MON / WEP1 / …)
  is independently a per-layer concern: each slot's SHP+SEQ data comes from
  the unit's assigned templates (`SpriteDatabase.get_seq_type` /
  `get_shp_type`); the slot itself is template-agnostic.
- Adding a fifth render slot (e.g. a future shadow layer) is a shader change
  plus an enum extension plus a layer-priority table extension — *not* a
  scene-tree refactor. The reverse is also true: removing a layer cleans up
  one shader slot and one enum value, with no Node3D garbage to chase.
- The `STATUS_TEXT` slot is reserved in the runtime
  `SpriteLayerManager.Layer` enum even though damage-number rendering is not
  yet implemented, so the runtime model matches the ROM model from day one
  and the priority table data doesn't need a remap later.
