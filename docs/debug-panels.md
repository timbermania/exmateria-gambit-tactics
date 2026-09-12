# Debug Overlay & Logging

The **DebugOverlay** autoload provides a unified system for debug panels.
Decision: debug UI is a separate OS window —
[ADR-0035](adr/0035-debug-ui-is-a-separate-os-window.md); scene configuration
lives in these panels, not env vars —
[ADR-0051](adr/0051-scene-configuration-lives-in-debug-panels-not-env-vars.md).

## Overlay

- **F3** toggles overlay visibility.
- **ESC** clears focus from any control (returns to game input).
- The dashboard shows one cell per category; inside a cell, EACH registered
  panel renders under its own fold header titled `panel_title` (ADR-0035
  dec. 7). A cell's only panel starts open; a second registration
  collapses the cell into a table of contents of panel titles.

### Creating a panel

Extend `BaseDebugPanel` (gives input isolation + helpers) and register with
the overlay:

```gdscript
class_name MyDebugPanel
extends BaseDebugPanel

func setup(some_ref: SomeType) -> void:
    panel_title = "My Debug"
    panel_category = Category.UI  # or GENERAL, FONT
    _build_ui()

# Register (usually in the scene's _setup_debug_panels):
var panel := MyDebugPanel.new()
panel.setup(my_reference)
DebugOverlay.register_panel(panel, BaseDebugPanel.Category.UI)
```

`BaseDebugPanel` helpers: `add_separator(parent)`,
`add_label(parent, text, min_width)`,
`create_collapsible_section(parent, title, start_open)` (renders FLAT per
ADR-0035 — bold title, no fold),
`add_fold_section(parent, title, start_open)` (a REAL collapsible — the
ADR-0035 dec. 6's scoped exception for oversized calibration panels: one
fold per target game panel, folded by default; see DetailScreenDebugPanel),
`add_print_values_button(parent)`,
`set_spinbox_value(key, value)` / `get_spinbox_value(key)`.

For spinbox anti-patterns (no hardcoded `.value`, no arbitrary min/max), see
`pitfalls.md` → UI/UI3.

**A panel is a *view*, not an *owner* (ADR-0068 decision 12).** A tunable's effect
is applied by the code that owns the value (`Unit` binds `render.unit_mesh_scale`,
`PSXDisplay` binds `render.pixel_aspect`) — the panel only displays and writes the slug
(build rows with `TuneField.add`). Registering a panel in a scene controls its
*visibility*, not the control's *behavior*. **Never fan a tunable's effect out from a
panel** (e.g. looping over live units to write `mesh_instance.scale`): that is a
scene-local second source of truth, so the control works only in the scene whose
panel carries the fan-out and is silently dead everywhere else (e.g. GPUArena, which
shows only the generated dashboard). If a scrub must reach an already-applied value,
`Tune.bind` it at the owner.

## Logging

> **Superseded in direction by
> [ADR-0140](adr/0140-debug-is-a-system-and-a-system-logs-itself.md) dec. 5
> (2026-08-21): a system logs itself, and there is no inter-system logging.**
> The rule below is the *current* state of the tree, not the target. Two things
> in it are retired:
>
> - **`iteration_debug_enabled` is not a flag, it is six flags.** It is 107
>   references across Battle (53), Effects (24), Sprite Rig (10), Battlefield
>   (6), UI (6) and Cutscene (1) — one name doing generic verbose duty for six
>   unrelated systems, and nothing ever read it as a single concept. **New
>   diagnostics declare their own flag as a `static var` in the system that
>   prints them** (ADR-0068), with that system's panel reading it as a view.
> - **`GameLogger` is deleted, not promoted.** Its `Category` enum is a closed
>   list of four; an addon cannot extend it without editing the host, which is
>   the dependency ADR-0113 rejected. Do not add a category to it, and do not
>   route new logging through it.
>
> *"To add a category: add the flag to `DebugConfig.gd` and a checkbox in
> `LoggingDebugPanel.gd`"*, at the end of this section, is the reach-up this ADR
> retires. Declare the flag in your own system instead.
>
> Existing gates migrate during their system's extraction pass, not now. Until
> then the code below still reads correctly.

Any verbose debugging added during iteration MUST be gated behind
`DebugConfig.iteration_debug_enabled`:

```gdscript
if DebugConfig.iteration_debug_enabled:
    print("[DEBUG] Detailed info: %s" % some_value)
```

Toggle in the **Logging** tab of the F3 overlay, or in code
(`DebugConfig.iteration_debug_enabled = true`; default `false`).

Key flags (all in the Logging tab):

- `iteration_debug_enabled` — UI/component iteration details
- `action_debug_enabled` — weapon loading, sprite changes, reaction animations
- `camera_debug_enabled` — camera system
- `particle_debug_enabled` — effect particles
- `timeline_debug_enabled` — effect timeline

Prefer `GameLogger` with a category over bare `print`:

```gdscript
if DebugConfig.camera_debug_enabled:
    GameLogger.debug(GameLogger.Category.CAMERA, "Debug message", {"unit": unit})
```

To add a category: add the flag to `src/debug/DebugConfig.gd` and a checkbox
in `src/debug/LoggingDebugPanel.gd`.
