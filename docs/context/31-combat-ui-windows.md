# Combat UI windows

The combat menu is a set of **windows** the player opens and closes — not a
draggable desktop. Windows are dialed into fixed screen positions; the
player never moves or re-focuses them by hand. The cluster names the two
ways a window behaves (coexist vs. complete-before-proceeding) and the one
rule that decides what draws on top.

**Window**:
A combat-UI panel dialed into a fixed screen position (`screen_pos`) that
the player opens and closes. Many windows coexist on screen at once; what
draws on top is decided by **structural layer** — non-modal windows sit on
their layers and a [modal window](31-combat-ui-windows.md) sits on the layer in
front — not by recency or any player action. The player cannot drag or
re-stack a window — placement and order are the system's job, not the
player's. Both behaviors below are Windows.
_Avoid_: "panel"/"dialog" (too generic); "popup" unqualified — in this
project that names the *modal* window, and the code's `UIPopupMenu` /
`PopupLayer` are the modal-window machinery, not all windows.

**Non-modal window**:
A window that coexists with the others and stays live while they are open —
the two **rosters** and the per-unit **detail menus** (equipment, ability,
stats, gambit display, learn button). The detail menus appear *together* the
moment a unit is selected and are designed to be read and used side by side;
they may overlap only as a layout artifact on resize, never by intent.
_Avoid_: treating a detail menu as something opened "deeper" — selecting a
unit raises the whole non-modal set at once.

**Modal window**:
A window opened by drilling **deeper** into a non-modal window — the
equipment picker, job picker, ability picker, learn panel, gambit editor.
The player completes or dismisses it before interacting with anything else:
**at most one top-level modal is open at a time**, drawn above the non-modal
windows. While it is open it **grabs input** — the windows behind stay
visible but are not interactive, and a click outside the modal does nothing
(it is dismissed only by completing it or an explicit cancel). A modal may
privately host **one** nested sub-modal (the gambit editor opening the
action-ability picker); deeper general stacking is not a thing.
_Avoid_: modeling modals as a free stack (only the gambit→action nesting
exists); calling them "popups" as if they were a separate type — a modal
window *is* a Window.

**List-modal window**:
A [Modal window](31-combat-ui-windows.md) whose content is a `UIScrollableList` of
**typed rows** — the shape the equipment, job, passive-ability, and
action-ability pickers share (`UIListModalWindow` + its four subclasses).
Each subclass declares a `RefCounted` inner row type (`EquipRow`, `JobRow`,
`ActionRow`, `PassiveRow`) and overrides three hooks: `build_rows(...)`
(query the database), `_columns() -> Array` (declare the **row column
schema**, see below), and `_on_picked(row)` (emit the picker's typed
signal). A `_preview_rows()` hook supplies sample data so the editor
preview drives the same render path runtime does. The base owns the **row
skeleton** (container + `Content` child + `UIClickableField`) and a
**single selection funnel** — both mouse-click and keyboard-Enter route
through one `_dispatch_pick(idx)` that hands the typed row to `_on_picked`
and closes the window. Subclass entry points (`show_for_slot`, `show_jobs`,
…) store per-picker state (`_current_slot`, `_current_unit`) and call
`_open_with_rows(rows, title, pos)`.
_Avoid_: re-implementing both selection callbacks per subclass (the deepened
contract routes both keyboard and mouse through one hook); shaping rows as
`Dictionary` with string keys (use the typed inner class so id-type and
columns are explicit); subscribing to a base `item_selected` signal (does
not exist — each picker emits its own typed signal); overriding `_render_row`
to paint text columns by hand — declare a [row column schema](31-combat-ui-windows.md)
instead. Overriding `_render_row` is the escape hatch for layouts that
genuinely cannot be expressed as a column list.

**Row column schema**:
The static `const _COLUMNS` on a row-rendering consumer: a small `Array` of
`Dictionary` rows mapping a typed-row field to the display node that paints
it. Two consumers today — each [list-modal window](31-combat-ui-windows.md)
subclass (via `UIListModalWindow._render_row` looping `_columns()`) and
`UILearnPanel._add_ability_row` (looping `_COLUMNS` directly, since
LearnPanel isn't a list-modal). The picker-side analogue of the [Unit encode
schema](02-combat-buffer-layout.md) and the [Gambit encode schema](02-combat-buffer-layout.md)
— and, like the gambit schema, deliberately holds **no Callables**: rows
carry pre-formatted display strings, not raw values, so the schema stays
data, not code. `ActionRow.mp_text/ct_text/range_text` and
`AbilityLearnRow.{jp,mp,ct,range,button}_text` are the canonical shape
(formatted in `build_rows` / `_add_ability_row`: `"MP:%d" % mp if mp > 0
else ""`); raw ints are intentionally absent. `EquipRow.stats` predated the
schema and already followed this discipline.

The schema-dict **shape** is per-consumer because the knob-source rules
differ — the picker schema reads `offset_x_prop` / `scale_prop` / `palette_prop`
as `@export` property names on the host with sensible defaults
(`item_scale`, `item_palette`), and `text_space_width` is a single host
export shared across columns. UILearnPanel's schema reads `offset_key`
from the `column_offsets` Dict `@export`, `palette_field` from the row
(state-derived `learned_palette` / `unaffordable_palette` resolve once in
`_add_ability_row`), and `space_prop` because name and stats have distinct
space-width exports. What's shared is the **painting primitive**:
`UIRowColumnRenderer.paint(parent, child_name, value, host_ppu, scale,
palette, space_width, offset_x_px, hide_when_empty)` — a static helper
both consumers' `_render_column` resolves into. Idempotent (get-or-create
by child_name), so virtual-scroll reuse and persistent-row construction
share one paint path.
_Avoid_: storing raw values on a row when the column will only show a
formatted string (the row carries display payload, not source data — the
discipline mirrors ADR-0016's `const`-without-`extract`-Callable rule);
inlining format strings into a column dict via a Callable (the format
belongs in `build_rows` / `_add_ability_row`, where it runs once per row,
not per virtual-scroll factory call); adding a column that points at a row
field whose value is not a String (the schema loop coerces with `str()`,
but a numeric row field is the smell the pre-formatted-text discipline
retires); duplicating the UIText get-or-create / set-text / set-palette /
position block in a third consumer (call `UIRowColumnRenderer.paint`).

**Window layering**:
What draws on top is **structural, not dynamic**. Non-modal windows share a
base layer; modal windows share a layer offset in front of it, so any open
[modal window](31-combat-ui-windows.md) sits above every non-modal window the
moment it opens — no per-open bookkeeping. Order *within* a layer is fixed
(scene order); the player never re-raises or re-focuses a window, and
[mutual exclusion](31-combat-ui-windows.md) means at most one top-level modal
exists, so there is nothing to dynamically order. A modal's private
sub-window (gambit editor → action picker) sits just in front of its owner —
the owner's concern, not the host's.
_Avoid_: a "most recently opened on top" z counter (there is never more than
one modal to order); confusing this with [Ordering Table depth](25-rendering-depth.md)
or [Layer priority](25-rendering-depth.md), which order the 3D battle scene. Not
"z-index".
