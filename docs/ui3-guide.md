# UI3 Component Development

Patterns for building components in the `src/ui3/` system. For UI3 *mistakes*
(render_priority, scene-node vs dynamic, editor-preview setters, etc.) see
`pitfalls.md` → UI/UI3. Window/modal hosting is one host, single current modal
— [ADR-0010](adr/0010-combat-ui-windows-one-host-single-current-modal.md).

## 0. Element registration (ADR-0088 — the target model)

Every UI part is a **registered element**: a `UI3Element` carrying a spec that
answers the standard criteria — placement (`rect`), frame chrome, transition,
clip, metrics (PPU/depth/palette inherited). "None" is a valid answer; absence
fails construction. Shared engines implement the answers (clip pushing,
ADR-0084 transition beats, chrome, metrics), and literal spec fields are
automatically live tunables (ADR-0068 E1–E3 — same pin → materialise
loop; no hand-written `static var`/`bind`/`TuneField.add` plumbing). Repeated
parts use **derived placement** from a few driving tunables.

Status: **design accepted, build ratcheting** — the registration audit +
shrink-only allowlist (`ui3_registration_allowlist.json`) enforce it as
screens migrate (detail/picker first, each behind a visual no-op golden).
Rule now: **new or touched UI parts must register**; do not add bare `Node3D`
holder vars, per-class `PIXELS_PER_UNIT`, hand-collected clip-material
arrays, or hand-rolled open/close accumulators. Vocabulary lives in
CONTEXT.md → "UI3 components"; the full model in
[ADR-0088](adr/0088-ui3-elements-register-a-criteria-spec-shared-engines-implement-it.md);
the concrete interfaces (`UI3Element`, `UI3Registry`, the engines) in
[ui3-element-interfaces.md](ui3-element-interfaces.md).

1. **Reference existing components first.** Study `UIPopupMenu`,
   `UIRosterBar`, `UIScrollableList` for established config-application,
   property-setter, and layout patterns before building new sections.

2. **Deferred layout updates for editor preview.** UI3 components batch layout
   via a dirty flag:

   ```gdscript
   var _layout_dirty := false

   func _request_layout_update() -> void:
       if _layout_dirty: return
       _layout_dirty = true
       call_deferred("_do_layout_update")

   func _do_layout_update() -> void:
       if not _layout_dirty: return
       _layout_dirty = false
       _update_layout()
       if Engine.is_editor_hint() and _scroll_list:
           _scroll_list.clear_virtual_data()
           _populate_editor_preview()
   ```

3. **`@export` visual properties need setters that call
   `_request_layout_update()`**, so the editor preview updates on change:

   ```gdscript
   @export var item_spacing := 2.0:
       set(value):
           if item_spacing == value: return
           item_spacing = value
           if _scroll_list: _scroll_list.item_spacing = item_spacing
           _request_layout_update()
   ```

4. **Expose full text configuration** on every text element: `scale` (size
   multiplier), `offset_x`/`offset_y` (virtual px), `space_width` (space char
   width, default 1.0, -1.0 for font default), `palette` (0=MENU, 1=STAT…).

5. **Make frames toggleable.** Every component with a frame/background needs a
   `show_frame` (or `show_background_frame`) boolean, enabling frameless
   variants without code changes.

6. **Assemblies expose spacing params.** Components arranging children expose
   `spacing` (gap), `padding` (float or Vector2 inner margins), and
   `content_offset` (Vector2).

Every new UI3 component must be integrated into `CombatUITest.tscn` for visual
testing — see `pitfalls.md`.

## 1. Aperture padding (`OWN_APERTURE` elements)

An element with `clip: Clip.OWN_APERTURE` owns an **aperture** — the box its
transition (e.g. `BOX_OPEN`) reveals over, and the settled clip region for its
`PARENT_APERTURE` children. That box defaults to the element's live `rect`.

**Convention: every `OWN_APERTURE` element always exposes an `aperture_pad`
knob** — an owned aperture is a dialable one. You do **not** declare it per
call-site: `UI3Element._adopt_spec` injects a `Vector4.ZERO` default for any
`OWN_APERTURE` spec that omits it, so the live F3 knob `<id>.aperture_pad`
always exists. Injecting zero is behaviourally inert (absent ≡ `Vector4.ZERO`
in `padded_rect()`), it just surfaces the knob. `PARENT_APERTURE`/`UNCLIPPED`
elements own no aperture and get no such knob.

`aperture_pad` is a `Vector4(left, top, right, bottom)` in display px; **positive
grows the box outward, past the frame**. Use it for payload that legitimately
pokes outside the frame yet must still ride the reveal + stay bounded — e.g. a
header cell sitting above the frame top, or a glove poking off the left edge.
It pads only this box, never the per-frame reveal walk, so a finished close
still ends fully shut. The ROM §15.17 scissor **is** the container rect, so a
non-zero pad is a deliberate port-side affordance — parity-dialed screens keep
it zero. Declare an explicit `aperture_pad` in the spec only to author a
**non-zero** default (as `EquipPickerMenu`'s window does: `Vector4(0, 4, 0, 0)`,
a 4px top pad so the "Eqp."/"ALL" header cells ride the reveal).
