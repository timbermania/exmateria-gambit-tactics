# Modal isolation is an input-grab on lower layers, not Z-spacing

## Status

Accepted (2026-06-16)

Refines [ADR-0010](0010-combat-ui-windows-one-host-single-current-modal.md).

## Context (before this decision)

The combat UI is **3D geometry**, so clicks resolve through **physics
picking**, which delivers a press to the **single closest collider** (highest
world-Z; the camera looks down −Z). This is closest-only regardless of the
viewport's `physics_object_picking_sort` / `_first_only` flags.

That makes **two independent ordering systems** exist at once, and they can
disagree:

- **Render order** — what you *see* on top — is `render_priority` (material) +
  `no_depth_test`, plus the structural layer a window lives on.
- **Click order** — what you actually *click* — is world-space Z (closest
  collider wins).

[ADR-0010](0010-combat-ui-windows-one-host-single-current-modal.md) removed the
*dynamic* per-window z-counter and declared layering "structural… no z
bookkeeping." That was right about the counter but overstated: **static**
structural Z never went away, and it is exactly what click-order resolves by.
Three static Z offsets were load-bearing for click-order:

- layer offsets (`BaseLayer` 0, `DetailLayer`, `ModalLayer`),
- `UIClickableField`'s **+0.5** forward protrusion (added "to fix visibility
  through an orthographic camera" — but the debug mesh already uses
  `no_depth_test` + `render_priority`, so the offset did nothing for
  visibility and only pushed the collider forward),
- the gambit editor's **+0.1** bump that raises its nested action picker.

The combat layers were spaced exactly 0.5 apart, so a back-layer button
(`DetailLayer` 0.5 + 0.5 protrusion = **1.0+**) poked *in front of* the front
modal's flush body-absorber (`ModalLayer` 1.0 − 0.01 = **0.99**). Render-order
showed the modal on top; click-order handed the press to the gambit row
behind it. The reported through-click: select unit → Learn → click the learn
window *over* a gambit row → the gambit editor opened.

A symptom patch (widen layer gaps to a uniform 1.0) realigned the two
orderings by **spacing**. It worked, but it kept click-isolation riding on a
numeric coincidence between two systems that have no reason to stay aligned.

## Decision

**A modal grabs input structurally, independent of Z.** When a top-level modal
is open, the host disables physics picking (`input_ray_pickable = false`) on
every clickable under the non-modal layers (`BaseLayer` + `DetailLayer`),
remembering which it disabled, and restores exactly those when the last modal
closes. A disabled collider cannot win a click **at any Z**, so render-order
and click-order can no longer disagree about modal isolation — the seam is
closed by construction, not by tuning.

Consequences of making the grab authoritative:

- **`UIClickableField`'s +0.5 protrusion is retired** (dropped to ~0.05 — just
  in front of its own window's body-absorber). It was never needed for
  visibility, and cross-layer protrusion can no longer route a click now that
  lower layers are not pickable while a modal is up. This also makes the
  nested gambit→action case safe (a gambit button can no longer poke through
  the action picker). Restores a legible invariant:
  `button offset (0.05) < nested bump (0.1) < layer gap (1.0)`.
- **The `UIFrame` body-absorber and the layer spacing stay.** The grab covers
  only *modal-over-non-modal*. When **no** modal is open, two non-modal Detail
  menus still coexist over the Base layer with no grab active — the absorber
  still swallows body clicks there, and the layer gap still orders Detail over
  Base. Removing them would re-open the through-click in the non-modal case.
- The grab is **layer-granular**, not a stack: the host disables the two
  non-modal layers whenever any top-level modal is open. The single nested
  case (gambit editor → action picker, both on `ModalLayer`) stays the owner's
  private concern, exactly as ADR-0010 mandates — now click-safe because
  nothing protrudes.

## Considered options

- **A full-screen scrim on the ModalLayer** behind the current modal —
  rejected: it still resolves by closest-Z, so a lower-layer button that
  protrudes far enough forward could still poke in front of the scrim. It
  keeps Z-spacing load-bearing, which is the coupling we set out to remove.
- **A full grab-stack** (every window-open records and disables everything
  currently pickable behind it, restoring on close) — rejected: it pulls the
  privately-owned nested picker into the capture system and turns the host
  into a stack manager, contradicting ADR-0010's "single top-level modal, no
  stack." The layer-granular grab plus the retired protrusion makes the one
  nested case safe without a stack.
- **Dismiss-on-outside-click** — rejected for this change: it is a deliberate
  UX behavior (a click outside cancels the modal) layered on top of the
  structural fix, with its own node and lifecycle. The grab already blocks
  outside clicks (they hit nothing); making them *dismiss* is a separate
  decision. A modal is dismissed only by completing it or an explicit cancel.
- **Keep the symptom spacing patch as the fix** — rejected as the *whole*
  fix: it realigns the two orderings by a magic gap rather than removing the
  dependence on their agreement. Kept as defensive margin for the non-modal
  case (above), not as the modal-isolation mechanism.

## Consequences

- Modal isolation no longer depends on any Z value agreeing with render-order.
  Adding a layer, retuning a gap, or changing a collider depth cannot
  re-introduce a through-click into or out of a modal.
- The host gains a small grab/release responsibility on the modal lifecycle
  (`open_modal` / last-modal close) — it walks the two non-modal layers once
  per transition. **This consequence is currently UNGUARDED.**
  `tests/UIClickThroughTest.gd` was removed on 2026-08-22: all three of its arms
  reported `absorber_hits=0`, meaning the synthesized click never landed on any
  collider, and the test said so itself — `(test is vacuous)`. It could neither
  fail for the right reason nor pass for one, so it was never actually guarding
  this decision; it only looked like it was. Re-guarding it needs an input
  injection that demonstrably lands (`DisplayServer.warp_mouse` +
  `Viewport.push_input` did not), proven by a deliberately-broken control case
  before the assertion is trusted.
- `render_priority`/`no_depth_test` remain the **render**-order authority;
  this ADR governs **click**-order isolation. The two are documented as
  decoupled systems that must not be relied on to coincide.
- Refines ADR-0010: "no z bookkeeping" is scoped to "no *dynamic* z-counter";
  static structural Z still exists and governs click-order, and modal
  isolation is now enforced above it by input-capture.
