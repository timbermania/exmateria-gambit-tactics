# `UnitAnimationSet` is the typed read-interface for animation data; `AnimationDatabase` is its loader

The animation cluster's data side — the SEQ / SHP / layer-priority / name
JSON the [layer playbacks](../context/19-animation-playback.md) read —
lived behind a two-module split: `AnimationData` (a per-`Unit`
`Resource` with 12 `@export_file` paths and 9 member `Dictionary`s) and
`AnimationDataLoader` (an autoload `Node` with a 2-key static cache).
The split was shallow in three independently-load-bearing ways:

1. **Two loading paths** into the same loader. `AnimationData.load_for_type`
   called `AnimationDataLoader.get_seq_data` / `get_shp_data` (cached,
   with type1 fallback) for the primary unit-type slot, and
   `AnimationDataLoader.load_json_path` (uncached, no fallback) directly
   for the seven secondary slots (wep1, wep2, eff1, layer_priority,
   *_names). The two paths drifted on cache, on fallback, and on the
   `op_code_id` annotation — a class of bug the CLAUDE.md "Common
   Mistakes" table calls out by name ("Multiple JSON loading paths
   missing shared annotations"): annotation lived only inside
   `load_json_path` and triggered by string-matching
   `path.ends_with("_seq.json")`. A caller that loaded a SEQ JSON any
   other way silently lost `op_code_id`, breaking enum-based opcode
   matching with no error.
2. **State doubled across the seam.** `AnimationData` held 9 member
   dicts per-`Unit`. `SpriteLayerManager` then **copied** `type1_shp`,
   `wep1_shp`, `wep2_shp`, `eff1_shp`, and the `uses_wep2` bool into
   its own member vars. The same SEQ/SHP data lived in three places
   (loader cache for type1, `AnimationData` for everything, copies
   inside `SpriteLayerManager`) with no enforcement that they stayed
   consistent.
3. **Vestigial `Resource` shape.** `AnimationData extends Resource`, but
   no `.tres` or `.tscn` carried one. `Unit.gd` always
   `AnimationData.new()`-ed a fresh instance and ignored the 12
   `@export_file` paths. `AnimationDataLoader extends Node` and was
   autoloaded, but had no signals, no `_process`, no scene-tree role —
   only a `_ready()` that eagerly preloaded type1. Both base types
   bought nothing the code actually used.

We collapse the split into one deep seam. `UnitAnimationSet` is a
`RefCounted` typed record (one named field per layer, no `Dictionary`
dot-notation footgun). `AnimationDatabase` is the
[JobDatabase](../context/03-unit-roster.md)-shape static module
(`class_name`, lazy `_ensure_loaded`) that caches one set per
`(seq_type, shp_type)` pair and serves every caller through one method,
`get_set(seq, shp) → UnitAnimationSet`. TYPE2 routing collapses inside
the set (`wep_seq` and `wep_shp` are already type-correct); the
`is_type2: bool` field stays exposed only because
[`WeaponAnimationSelector`](../context/18-sprite-layers.md)`.get_wep_frame_offset`
takes the flag as an argument.

## Status

accepted

## Considered options

- **Typed `UnitAnimationSet` record + `AnimationDatabase` static loader
  (chosen).** One typed RefCounted record, one static module, one entry
  point, one cache. TYPE2 routing absorbed (`get_wep_seq()` retires).
  `op_code_id` annotation lives in the database's private loader and
  fires for every SEQ JSON unconditionally — the duplicate-path bug
  class structurally cannot recur, because there is no second path.
  `SpriteLayerManager` drops its own `uses_wep2` and its
  `type1_shp`/`wep1_shp`/`wep2_shp` copies; it holds a
  `UnitAnimationSet` reference and reads `_anims.type1_shp` etc.
  through it. Two same-typed units share one set instance, so the
  9-dict-per-Unit memory footprint stops multiplying. Chosen because
  it makes the "one schema location, one cache, one annotation pass"
  win *structural* — the seam is the only path JSON can enter — at the
  cost of a mechanical 5-file caller migration.
- **Flat `Dictionary` return, hide `uses_wep2`.** Same seam, no typed
  class. Rejected: keeps the `Dictionary`-dot-notation footgun that
  CLAUDE.md's Common Mistakes table documents — every field read is
  string-keyed bracket access or a silent `null`. The typed record
  costs one file to land; the silent-null cost is unbounded.
- **Per-layer accessor methods on the loader.** No record at all;
  `AnimationDatabase.get_seq(unit_type, layer)` /
  `get_shp(unit_type, layer)` / `get_layer_priority()`. Rejected: every
  read hits the loader through a method call, and the loader grows ~6
  methods instead of 1. The set-as-noun is the natural unit — a `Unit`
  has *one* animation set at a time, not seven independent layer
  queries. The dispatch on `(seq_type, shp_type)` per read also hides
  the cache key behind every call instead of computing it once.
- **Expose `is_type2` only through a `get_wep_frame_offset` helper on
  the set.** Absorbs `WeaponAnimationSelector`'s lookup into the set,
  hiding the bool entirely. Rejected: couples the dataset to the
  weapon-animation table (an unrelated module) and adds a domain
  stretch — the set is animation data, not weapon-table dispatch. The
  exposed bool is one field and one caller (`Unit` passing it through
  to `WeaponAnimationSelector`); the depth gain isn't worth the
  coupling.
- **Keep `AnimationData` name; just retype internally.** Minimal
  churn: `AnimationData.gd` survives as a `RefCounted` with typed
  fields, `AnimationDataLoader` survives as the autoload. Rejected:
  the name doesn't track the shape change ("Data" suggests a per-Unit
  mutable bag, which the new record is not), and the autoload `Node`
  remains an unused base class. The rename is mechanical (5 files);
  retiring the autoload removes a line of `project.godot` and aligns
  the loader with the documented
  [`*Database`](../context/03-unit-roster.md) convention.

## Why this is not a re-litigation of ADR-0008

[ADR-0008](0008-ability-view-is-a-generated-facade.md) added a typed
façade (`AbilityView`) **over a stored `const Dictionary`** because the
ability schema is hand-typed at ~13 read sites and the data is
*generated* into a checked-in const. The view is built per-call and
mirrors the dict by reference; the dict stays the single store.

`UnitAnimationSet` differs on every load-bearing axis:

- *Data origin.* Animation JSON is loaded from disk at runtime, not
  generated into a `const`. The "single store" is the on-disk JSON, not
  a checked-in GDScript dict.
- *Allocation pattern.* `AbilityView` is built per read (~13 sites,
  load-time). `UnitAnimationSet` is built once per `(seq_type,
  shp_type)` pair and cached for the run; per-Unit cost is one
  reference assignment.
- *Mirror vs. depth.* `AbilityView` is a *mirror* (1:1 over the same
  dict). `UnitAnimationSet` is a *depth gain* (`wep_seq` is already
  TYPE2-resolved; `get_wep_seq()` retires; `SpriteLayerManager`'s
  duplicate `uses_wep2` retires).

ADR-0008 stays as decided; the
[`AbilityDatabase`](../context/05-ability-data.md) keeps returning
dicts and the view sits beside it. This ADR is the *different* case of
a runtime-loaded asset that had grown two loading paths and no typed
record at all.

## Consequences

- **The deepening surfaced three dead fields** — `type1_animation_names`,
  `wep1_animation_names`, `eff1_animation_names` on the old
  `AnimationData`. They pointed at `type1_names.json` / `wep1_names.json`
  / `eff1_names.json` paths that no tool produced; the old loader
  silently `push_error`-ed and returned `{}` on every call. The only
  consumer (`SequenceViewer._get_names`) read those empties and rendered
  every animation row as `"<slot>: Unknown"` in the viewer's list. The
  real per-slot label store is
  [`AnimationNames`](../context/19-animation-playback.md)
  (`assets/sprites/animation_names.json`, hand-authored via
  `tools/build_animation_names.py` from TacticsEngineG), keyed by
  `sprite_type`. `SequenceViewer` now calls
  `AnimationNames.get_label(sprite_type, slot)` and drops the dead
  fields — the consolidated seam exposed what the old per-instance
  member-dict shape hid.
- **The duplicate-loading-path bug class retires structurally.** There
  is one path: `AnimationDatabase.get_set(seq, shp)`. SEQ-file
  annotation lives inside the database's private loader and fires
  unconditionally — no caller can construct a `UnitAnimationSet` whose
  SEQ dicts lack `op_code_id`. The Common Mistakes line stays in
  CLAUDE.md as the explanation; the failure mode it documented no
  longer has a path through the code.
- **`SpriteLayerManager.uses_wep2` and its three SHP-dict copies
  retire.** `SpriteLayerManager.initialize` takes a `UnitAnimationSet`
  reference and reads `_anims.type1_shp` / `_anims.wep_shp` /
  `_anims.is_type2` through it. `WEP1` and `WEP2` distinctions stop
  living at two layers — the set is authoritative.
- **`AnimationDataLoader` autoload removed.** `project.godot`'s
  autoload line is deleted. The static-cache + `class_name` pattern
  replaces the `_ready()`-driven preload — type1 loads on first
  `get_set("type1", ...)` call instead of at game boot. Negligible
  cost (one JSON parse moved from boot to first-frame) at the seam
  benefit of matching the documented [`JobDatabase`
  shape](../context/03-unit-roster.md).
- **`UnitAnimationSet` is `RefCounted`, immutable after construction.**
  Two same-typed units share one instance. The cache holds them for
  the run; `AnimationDatabase.clear_cache()` is the hot-reload knob (a
  preexisting capability — the cache lives in the loader either way).
  No `Resource` base, no `Node` base — the bases that bought nothing
  are gone.
- **Migration is a single mechanical sweep.** Five caller files:
  `Unit.gd` (drops `@export var animation_data` + `.new()` + 12 field
  reads stay the same name + `get_wep_seq()` → `wep_seq`),
  `SpriteLayerManager.gd` (drops `uses_wep2` + 3 SHP copies, holds a
  reference), `SequenceViewer.gd` (same shape as `Unit`),
  `tests/GPUDashMovementTest.gd`, `tests/GPUPhysicalAbilityTest.gd`
  (both just rename `unit.animation_data` → `unit.animation_set`). No
  semantic change at any read site beyond `get_wep_seq()` → `wep_seq`.
- **`ANIMATION_FRAMERATE = 45.0` lives on `UnitAnimationSet`.** It is
  data-side (the framerate the JSON sequences are authored at), so it
  travels with the record. `SequenceViewer`'s lone consumer reads it
  through the set or the class — either works because it's a `const`.
- **CONTEXT.md gains two entries under `### Animation playback`.** The
  cluster intro grows one sentence pointing at the data side; the
  record and the database get full entries with `_Avoid_` blocks that
  call out the retired anti-patterns (hand-loading JSON, dot-notation
  on the typed fields, mirroring fields into `SpriteLayerManager`,
  restoring the autoload).
- **Verification is `--import` + `--quit-after`.** The
  CLAUDE.md-documented class-cache rebuild recipe applies: rename a
  `class_name` script, run `"$GODOT" --path . --import` to refresh
  `global_script_class_cache.cfg`, then load a scene with
  `--quit-after 2` and check the log for parse errors. Not headless —
  the CLAUDE.md ban stands.
