# Tombstone Tool Enhancement Notes

## Current Blind Spots

### 1. Name-Collision False Positives (Primary Gap)

`_has_code_references()` in `instrument_functions.py` uses a simple `\bfunc_name\b` regex
across all files. When different classes have methods with the same name, the tool sees a
"reference" and demotes the function from DEFINITELY DEAD to LIKELY DEAD — which
`delete_dead_code.py` skips.

**Examples caught by manual review (2026-03-09):**

| Dead function | False-positive match |
|---|---|
| `TerrainIndex.remove_doodad()` | `MapComposer.remove_doodad()` |
| `MapComposer.remove_doodad()` | `TerrainIndex.remove_doodad()` |
| `VisualGeometryIndex.get_stats()` | `DistanceFieldGenerator.get_stats()` |
| `TerrainIndex.get_stats()` | `DistanceFieldGenerator.get_stats()` |
| `Doodad.clear_cache()` | `AnimationDataLoader.clear_cache()` |
| `DoodadLibrary.clear_cache()` | `AnimationDataLoader.clear_cache()` |
| `Doodad.get_description()` | Common name in unrelated files |
| `Doodad.get_size()` | Common name in unrelated files |

**Fix:** Make `_has_code_references` class-aware. Instead of matching bare `func_name`,
match qualified patterns like `ClassName.func_name` or `instance_var.func_name` where
`instance_var` is typed as `ClassName`. This requires:

1. Building a type map: variable name → class_name (from `var foo: ClassName` declarations)
2. Checking references as `receiver.method()` and resolving `receiver` to its type
3. Only counting a reference if the receiver type matches the function's owning class

A simpler intermediate step: when a function name exists in multiple classes, require the
reference to appear as `ClassName.func_name` (static call) or in a file that imports/preloads
the owning class. This catches the majority of false positives without full type inference.

### 2. Cross-File Dead-to-Dead Chains

`called_from_live_code()` in `delete_dead_code.py` only tracks dead-to-dead chains within
a single file. If function A in FileA.gd is dead and only calls function B in FileB.gd,
B appears to have a live caller (because A is in a different file's dead set).

**Example:** `VisualGeometryIndex.restore_triangles()` was only called from dead
`MapComposer.remove_doodad()` — a cross-file dead chain.

**Fix:** Build a global dead set across all files before filtering, not per-file.

### 3. Non-Function Dead Code (Out of Scope)

The tool only instruments `func` definitions. It cannot detect dead:

- **Enum values** (e.g., `Tile.MOVE_RANGE` through `Tile.INVALID` — 6 dead values)
- **Member variables** (e.g., `MapComposer.next_doodad_id` — never read)
- **Signals** (e.g., `tiles_removed`, `tiles_restored` — only emitted from dead code)
- **Orphaned docstrings** (doc comments with no function body after them)

These require different analysis approaches and are lower priority than fixing the
name-collision issue above.
