# Combat UI windows: one host owns placement + single-current modal lifecycle; no z-ordering; nesting stays private to the owner

## Status

Accepted (2026-06-02). Refined by
[ADR-0061](0061-modal-input-capture-not-z-spacing.md) (2026-06-16).

> **Refinement (ADR-0061).** "Layering is structural… there is no z
> bookkeeping" (below) is correct about the **dynamic** per-window z-counter
> this ADR deleted, but overstated: **static** structural Z (layer offsets,
> the `UIClickableField` +0.5 protrusion, the +0.1 nested bump) never went
> away, and because clicks resolve through closest-collider **physics
> picking**, that static Z silently governed **click-order** — a separate
> system from the render-order this ADR was reasoning about. The two could
> disagree, and a through-click bug fell through the seam (a back-layer
> button protruding in front of a front modal's body-absorber). ADR-0061
> closes the seam by making modal isolation an **input-grab** (disable lower-
> layer picking while a modal is open), so click-isolation no longer rides on
> any Z value agreeing with render-order. The single-top-level-modal /
> no-stack / private-nesting decisions below all stand.

## Context (before this decision)

The combat menu is a set of [windows](../context/31-combat-ui-windows.md) —
non-modal ones (rosters, the per-unit detail menus) that coexist, and modal
ones (the equipment/job/ability pickers, learn panel, gambit editor) reached
by drilling deeper. A base class, `UIScreenContainer`, already owned the
*placement* half: it held the element registry, converted each window's
`screen_pos` to a world position, and rescaled on viewport change.

The *lifecycle* half was smeared into the `UICombatManager` subclass and had
become a maintenance hazard — the same six modal windows were hand-listed in
three close-loops (`_close_all_popups_internal`, `_close_active_popup`,
`_has_visible_popup`), an open incantation (`position.z = request_popup_z()`
→ populate → `_animate_popup_open`) was copy-pasted at eight sites, every
window re-declared its own `@export var screen_pos`, and a `_popup_z_counter`
assigned per-window z. CLAUDE.md documented a six-point ritual for adding a
new modal. Inspection also found the model was simpler than the machinery
implied: every `_show_*` method closed all modals first (so **at most one
top-level modal is ever open**), the only nesting was the gambit editor
privately opening the action picker, and `action_popup`'s manager-side
handler was a dead `pass`.

## Decision

Consolidate both concerns into one deep module and re-base the types onto a
shared hierarchy:

- **`UIWindow` → `UIModalWindow`.** `UIWindow` (the enriched
  `UIScreenContainer` child contract) owns `screen_pos` + dialed-in
  placement; `UIModalWindow` adds the lifecycle (`open`/`close`/`closed`).
  All window types re-base onto `UIWindow`, ending the per-type `screen_pos`
  duplication.
- **`UIWindowHost`** (renamed from `UIScreenContainer`) owns placement *and*
  modal lifecycle. It **scans** its `UIWindow` descendants at `_ready` (no
  per-window registration), and tracks a **single current top-level modal**:
  `open_modal(w)` closes the current one, makes `w` current, animates it in;
  it clears the slot when a window reports `closed`.
- **Layering is structural, not dynamic** — a modal sits in front because it
  lives on `ModalLayer`; there is no z counter.
- **Nesting stays private to the owner.** The gambit editor opens its action
  sub-picker itself, above itself, and cascades its close; the host never
  models nesting. The dead `action_popup` manager wiring is deleted.
- **Content population stays bespoke** in `UICombatManager` (`populate(unit,
  slot)`, `show_jobs(bool)`, …); the host never knows window content.

Delivered in two stages: modal windows + host first, non-modal `UIWindow`
re-base second.

## Considered options

- **A separate `ModalController` alongside `UIScreenContainer`** — rejected:
  the container already owns the window registry and placement, so the
  lifecycle belongs in the same module; a second module would re-read the
  first's registry. Placement, layering, and modal sequencing cohere around
  one concept ("the set of windows"), so one module is the deeper shape.
- **A modal *stack* with recency z-order** (what the originating architecture
  review proposed) — rejected: mutual exclusion means there is never more
  than one top-level modal to order, and the sole nesting case (gambit →
  action) is owned privately. A general stack is a seam for variation that
  exists in zero places.
- **Modeling the gambit → action nesting in the host** — rejected for the
  same one-case reason; it would pull a window the host never opens into the
  host's lifecycle.
- **Keeping the `_popup_z_counter`** — rejected: `ModalLayer`'s structural
  offset already puts modals in front, and mutual exclusion leaves nothing to
  order within the layer.

## Consequences

- Deletes the three close-loops, the eight-site open incantation, the
  z-counter trio (`_popup_z_counter` / `request_popup_z` / `reset_popup_z`),
  the dead `_on_action_ability_selected`, the 13 hand-written
  `register_element` calls, and the per-type `screen_pos` redeclaration.
- Adding a modal window becomes: author it in the scene under the host as a
  `UIModalWindow`, then `populate(...)` + `open_modal(...)`. The CLAUDE.md
  six-point ritual goes away.
- `UIWindowHost` owns two concerns (placement + modal lifecycle) by design —
  reviewers should read that as cohesion around "Window", not a god-object.
- The host's modal lifecycle is unit-testable with `UIModalWindow` stubs,
  outside a combat scene.
- "popup" is retired from structural names (`PopupLayer` → `ModalLayer`,
  `UIPopupMenu` → `UIListModalWindow`); the specific pickers keep their
  proper-noun names (`UIEquipmentPopup`, …).
