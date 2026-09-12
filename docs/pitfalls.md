# Pitfalls & Common Mistakes

Hard-won gotchas, grouped by domain. Rows that encode an architectural
**decision** collapse to a one-line ADR link (read the ADR for the why);
the rest are engine/tooling quirks documented in full here.

The handful of highest-frequency ones (headless, `uv run`, `--path`,
`class_name` cache) are also inlined in `CLAUDE.md` so they're always in
context — the rest live here. Read this before non-trivial work in the
matching area.

## GDScript language

- **No dot notation on Dictionaries.** GDScript does not support
  `dict.key`. Use `dict["key"]` or `dict.get("key", default)`. Dot notation
  silently fails or returns null.
- **`has_method()` is not static on autoloads / class names.** Can't call
  `ClassName.has_method("foo")`. Either call the method directly if the
  autoload exists, or gate with `if AutoloadName:` then call.
- **`UNUSED_SIGNAL` on an autoload signal** means the signal is emitted from
  *outside* its owner — an object should emit its own signals. Don't
  `@warning_ignore`. State-change signal → emit from the var's setter;
  command signal → wrap the emit in a method on the owner.
- **Forwarding-property member drop in a base class.** Exposing another
  object's members via getter-only properties (`var x: get: return other.x`)
  silently DROPS that member — and every member after it — from the
  subclass-visible member table, so subclasses fail to parse with
  `Identifier "x" not declared`. Fix: hold the SAME reference in a plain
  field (objects/dicts are reference types) and sync once; only forward
  members a subclass actually WRITES. See
  [ADR-0018](adr/0018-gpu-combat-interpretation-is-a-pure-module-the-loop-composes.md).

## Godot editor, `@tool`, and caches

- **Parse errors hide in scripts no scene loads.** Running one scene won't
  surface them — open the project in the editor (or run `--import`) to catch
  all parse errors.
- **New `class_name` files not recognized** — the global class cache is
  stale. Rebuild non-interactively with `godot --path . --import` (scans +
  reimports + exits; **not** `--headless`). A `--editor --quit-after N`
  session does NOT work (quits before the scan finishes). Deleting
  `.godot/global_script_class_cache.cfg` is NOT sufficient. Run `--import`
  after editing any `class_name` script that subclasses extend, before
  re-running tests — else the runner keeps parsing the OLD base.
- **A regenerated texture (.tga/.png) is NOT picked up by a plain runtime run** —
  `godot --path . <scene>` uses the stale `.godot/imported/*.ctex`; the asset
  renders with its OLD content (a newly added atlas cell samples as empty —
  silently, since the file/json look right). Run `godot --path . --import`
  after re-running any asset parser, before the verify run (bit round 48: the
  new FRAMEFONT "…" cell rendered blank until the reimport).
- **`--import` crashes with SIGSEGV (exit 134)?** Delete the editor FS cache
  and retry: `rm -f .godot/editor/filesystem_cache*` then re-run `--import`
  (clean exit 0, durable). Engine bug in `editor_file_system.cpp` (seen on the
  4.8 fork as well): a
  stale/half-built `filesystem_cache*` (newly-added files stuck at UID `-1`)
  corrupts the dir tree and self-perpetuates — it crashes before rewriting the
  cache, so every run re-crashes. The `unit_incapacitated` GDScript error and
  `invalid UID` warnings printed just before the crash are red herrings (scenes
  load fine at runtime; only `--import` dies). `.godot/` is
  gitignored/regenerable, so clearing it is a safe fix, not masking.
- **Autoloads unavailable in `@tool` scripts** unless the autoload's own file
  also has `@tool` at the top. Without it, `@tool` scripts silently fail in
  the editor.
- **`@export` without a setter in a `@tool` script corrupts serialization.**
  A bare `@export var foo := default` (no setter) misaligns property
  serialization — every value shifts down one position on save/load. Fix:
  minimal guarded setter `set(value): if foo == value: return; foo = value`.
- **Stale editor cache after changing an `@export` list in `@tool` scripts.**
  Adding/removing/reordering `@export`s leaves the editor's cached property
  order stale (inspector values shifted by N; wrong-type errors on dynamic
  nodes). The `.tscn` may be clean — the corruption is in-memory. Fix: fully
  close and reopen the editor.
- **Stale UIDs after changing a resource path in `.tscn`/`.tres`.** When you
  point an `ext_resource` at a different file, also update its `uid` to the
  target's UID (from the target's `.import` file). Mismatched UIDs cause load
  failures.

## Running & launching Godot / tests

- **Never `--headless`** — see `CLAUDE.md`. Run headful; the log still comes
  back to you.
- **Always `uv run python tools/...`** — deps are in `tools/pyproject.toml`;
  bare `python3` fails when they aren't global.
- **Always pass `--path .` from inside the package root.** `godot res://...`
  without `--path` (or `--path .` from the repo root, which has no
  `project.godot`) opens the project manager and autoloads/resources don't
  load. `cd` to the package root first, then `godot --path . res://...`.
- **This project runs on the 4.8 compositor fork ONLY — never stock 4.7
  (`/usr/bin/godot`).** The engine-fold compositor (Forward+, `render_mode
  compositor_fold`, named scratch) is fork-only; on 4.7 it self-disables
  (`[compositor-autopilot] inactive`) so folded effects (particles +
  callbacks) silently vanish and perf is off the real render path. 4.7 also
  re-saves `project.godot` down a version (strips the `4.8` feature). `godot`
  on `$PATH` resolves to the fork via `/usr/local/bin/godot` →
  `~/Repos/godot-compositor-consume-material/bin/godot.linuxbsd.editor.dev.x86_64`;
  `godot --version` must print `4.8.dev.custom_build`. The runner defaults
  `GODOT` to that `godot`; override only with another fork build. SPU audio
  also needs freshly-parsed effect assets — re-run
  `parse_all_effects_py.py --force` after a parser change.
- **Never run GPU test scenes in parallel.** Each launches a Godot window
  with compute shaders; parallel runs overwhelm the system. Use
  `bash tests/run_all_tests.sh` (sequential, one at a time).
- **Don't reach for an env var to configure or debug a scene** —
  `OS.get/has_environment` in `src/` or `tests/` is a build-breaker, enforced
  by `tools/check_no_env_vars.py` (a `run_all_tests.sh` pre-flight). This
  covers both real config (`SCENARIO_*` toggles) *and* throwaway debug gating
  (`*_DIAG` prints): both go through an F3 `BaseDebugPanel` surface instead —
  [ADR-0051](adr/0051-scene-configuration-lives-in-debug-panels-not-env-vars.md).
  The failure mode env vars invite is action-at-a-distance — a var exported in
  one shell silently changes an unrelated editor session. A genuine
  process-state read (headless detection, etc.) opts out with an explicit
  `# env-var-exempt: <reason>` marker as a code-review call.

## UI / UI3

- **Overlapping panels from absolute positioning.** Multiple panels with
  separate CanvasLayers + absolute anchor/offset overlap at different screen
  sizes. Use containers (VBox/HBoxContainer) to stack related panels.
- **Inconsistent screen-space 3D UI settings.** `screen_space_depth`,
  `pixels_per_unit`, and camera `size` must match across scenes (depth=10.0,
  pixels_per_unit=0.04, camera size=14.0 for combat) or UI appears too
  large/small.
- **`@export` layout properties need setters.** A plain
  `@export var spacing := 2.0` won't update the UI when changed externally.
  Add a setter that calls `_request_layout_update()`. In UI3 popup components
  (UIPopupMenu + subclasses) every `@export` setter MUST call it so the
  deferred pattern refreshes the editor preview.
- **Magic numbers instead of derived calculations.** Don't hardcode values
  that depend on other configurable props (e.g. `item_row_height = 18.0` when
  it's `base_height + spacing`). Compute from source:
  `N*base + (N-1)*spacing`.
- **UI elements rendering behind other frames.** UIFrame defaults to
  `render_priority = 0`. Dropdowns/popups/overlays must set
  `render_priority > 0`.
- **Stray `v`/`^` from UIScrollableList.** Scroll indicators
  (`show_scroll_indicators = true` by default) render incorrectly inside
  boosted-`render_priority` components. Set `show_scroll_indicators = false`
  for short lists, or match `render_priority`.
- **Dynamic child nodes not tracked for cleanup.** `add_child(node)` without
  storing a reference means generic `clear_*()` can't find it and orphans
  accumulate. Track dynamic children in a dict/array and clean them
  explicitly.
- **Global z for popup positioning.** A popup child of a layer at z=10 given
  `position.z = 10` ends up at global z=20 (behind a z=20 camera). Use local
  `z = 0` within the parent layer. Modal stacking is input-capture order, not
  z-spacing — [ADR-0061](adr/0061-modal-input-capture-not-z-spacing.md).
- **Debug-panel spinbox anti-patterns.** Don't hardcode initial `.value = X`
  (read from components via a `_sync_from_components()` after `_build_ui()`).
  Don't add arbitrary min/max (`min=-50,max=200`) — use wide ranges
  (`-99999, 99999`); debug panels are for experimentation.
- **Build UI as scene nodes, not dynamically.** Don't `ClassName.new()` +
  `add_child()` for UIFrame/UIText/UIButton — add them as `.tscn` nodes so
  properties are inspector-tunable. New UI3 components must be integrated into
  `CombatUITest.tscn` (node + `@onready` + signal wiring in `_create_popups()`
  + `_close_all_popups()`/`_close_active_popup()`) or they can't be visually
  tested.
- **Don't reparent to make a node "independently positionable."** Child
  transforms are already relative to the parent — position via local
  transform. Reparent only when switching positioning systems (world-relative
  → screen-space).

## Rendering: depth, PAR, meshes

- **Every 3D mesh needs CUSTOM0 GTE depth** — see the GTE-depth section in
  `CLAUDE.md` and [ADR-0009](adr/0009-ordering-table-depth-is-one-model.md).
  A mesh using Godot's default vertex-position depth sorts incorrectly
  against all CUSTOM0 meshes. New MeshInstance3D: ArrayMesh (not
  ImmediateMesh/QuadMesh) + bake face centroid into CUSTOM0 (RGB_FLOAT) +
  shader reads CUSTOM0 and writes DEPTH.
- **Every `POSITION`-writing battle shader needs `pixel_aspect`.** Apply the
  horizontal PAR clip-space stretch through the shared seam
  (`#include "res://addons/exmateria_platform/pixel_aspect/pixel_aspect.gdshaderinc"`;
  `POSITION = pixel_aspect_full(clip)` for map-attached geometry or
  `pixel_aspect_anchor(...)` for billboards) or it drifts horizontally (the
  recurring shadow / dialogue-box bug). `tools/check_par_shaders.py` fails the
  build if a `POSITION`-writing shader skips it; genuine screen-space passes
  opt out with `// pixel-aspect-exempt: <reason>`. See
  [ADR-0036](adr/0036-par-is-per-content-clip-space-not-global-stretch.md) /
  [0044](adr/0044-sprite-stretch-is-per-taxonomy-billboard-width.md) /
  [0060](adr/0060-battle-meshes-apply-par-through-one-seam.md).

## GPU compute / shaders

- **GPU is source of truth — don't recompute derived values on the CPU.**
  Capture them from GPU state (e.g. use the GPU's initial `timer` as
  `total_ticks`; recomputing with a CPU formula misaligns phase boundaries).
  [ADR-0031](adr/0031-battle-state-is-gpu-authoritative.md).
- **Guard against stale GPU state fields after timer/state resets.** When the
  GPU sets `timer` without `write_movement_step()`, fields like
  `prev_move_pos` / `move_total_ticks` / `move_step_id` stay stale. CPU
  readers must guard (`timer <= total_ticks`) and clear cached visualizers on
  mismatch.
- **Keep shader ↔ GDScript constants in sync after `.glsl` changes.** Update
  BOTH `src/gpu/shaders/combat_common.glsl` and `GPUBatchSimulator.gd`
  (`UnitField` enum, `UNIT_SIZE`, `EXPECTED_SHADER_VERSION`) and bump
  `SHADER_VERSION` on structural changes — validated at init
  (buffer layout is shader-authoritative,
  [ADR-0001](adr/0001-gpu-combat-buffer-layout-is-shader-authoritative.md)).
  **Exception:** `LOGICAL_ACTIVITY_*` and `DisplayActivity.Activity` are
  generated from `tools/activity_taxonomy.yaml` — edit the YAML then
  `(cd tools && uv run python gen_activity_taxonomy.py)`; hand-editing the
  generated regions is undone by regen and caught by `run_all_tests.sh`.
- **GLSL functions must be defined above their callers** (or forward-declared)
  — otherwise the shader silently fails to compile and units sit idle.
- **GLSL reserved words aren't obvious** — `half`, `input`, `output`,
  `sampler`, `filter`, `fixed` etc. as variable names fail to compile. Check
  `app_userdata/learning/logs/godot.log` for the real error.
- **Don't promote single-stage GLSL helpers to shared headers.** Vulkan
  cold-cache pipeline compile scales with total SPIR-V size (even unreachable
  functions). Keep helpers in the stage file that uses them; only 2+-stage
  helpers belong in `combat_common.glsl` / `combat_combat.glsl`. See
  `docs/shader_compile_refactor.md`.

## Data / parsing / effects

- **Bit decoding lives at the parser boundary** —
  [ADR-0013](adr/0013-fft-bitmask-decoding-lives-at-the-parser-boundary.md).
  FFT packs flag bytes MSB-first (first name = bit 7). Use
  `tools/_fft_decode.decode_set_msb` / `decode_flags_msb`; never a per-bit
  loop at runtime (an LSB-first reader inverts the set).
- **Annotate BOTH JSON loaders.** `AnimationData._load_json()` and
  `AnimationDataLoader._load_json()` both load sequence JSON. Adding an
  annotation (e.g. `op_code_id`) to only one silently breaks enum-based
  opcode matching for sequences loaded through the other (wep1_seq, eff1_seq).
- **Effect header offset comes from BATTLE.BIN, not a prologue scan.**
  CODE-format effects (E259/E338/E464) start with a data/jump table, so
  scanning for the MIPS prologue at offset 0 reads a garbage header. Read the
  authoritative offset from the BATTLE.BIN table (`0x14d8d0`, minus
  `0x801c2500`) via `load_vfx_header_offset()` — `parse_effect.py` does this.
- **Camera tracks are OFF by default in EffectViewer.** Enable via the Camera
  checkbox in the debug overlay, or programmatically
  (`PlayerCamera.enter_effect_mode()` / `apply_effect_camera()`); the
  CameraTrackController computes values but doesn't apply them otherwise.

## Naming, filesystem, state

- **Don't prefix generic systems with "FFT."** This project uses FFT data but
  the systems are generic — use `UIChar`, `UIFrame`, not `FFTChar`.
- **No case-only symlink workarounds.** Don't add `Foo.tscn → foo.tscn` or
  `XX.TGA → XX.tga` to paper over a code-vs-disk case mismatch. Linux is
  case-sensitive; mac/Windows aren't — the symlink breaks Godot's importer
  (duplicate `.import` metadata) and Windows checkout. Pick one canonical case
  and rename. `tools/bootstrap_assets.sh` warns on stray uppercase `.TGA*`.
- **Stale saved roster data after code changes.** Rosters load from
  `user://roster.json` / `user://enemy_roster.json` at startup. After changing
  roster code (jobs/sprites/abilities) run
  `uv run python tools/clear_user_data.py` to force regeneration.
- **Reload, don't hand-reset a scene.** Use
  `get_tree().reload_current_scene()` instead of bespoke cleanup/respawn code.
- **Wrong `collision_mask` for raycasting.** Layers: tiles = 2, units = 4.
  Raycast tiles with `collision_mask = 2`, units with `4`, both with `6`.
  Mask `1` misses everything.
