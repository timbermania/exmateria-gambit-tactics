# UI3 components

The base UI3 node type that owns the deferred-layout contract, the setter
shapes that subclasses use, and the element-registration vocabulary
(ADR-0088): every UI part is a registered element whose spec answers the
standard criteria, implemented by shared engines.

**UIComponent**:
The base class for any UI3 node that participates in the deferred-layout
contract — owns the `_built` guard, the `_layout_dirty` flag, the deferred
`_update_layout()` dispatch, the editor-preview tail (`_populate_editor_preview()`),
and the `_push()` sync helper for push-to-child-field setters. Subclasses
override `_build_children()` and `_update_layout()`; nothing else is required. The
dirty-flag triple lives **once** here, not per component. Every UI3 node that
needs deferred layout — `UIButton`, the `UIWindow` family (`UIWindow` →
`UIModalWindow` → `UIListModalWindow` and the four picker subclasses), and
the heavier modals (`UIGambitEditor`, `UILearnPanel`, `UIGambitDisplay`,
`UIRosterBar`) — inherits this contract directly or transitively. The one
sibling that is *not* a UIComponent is `UIWindowHost`: it is the **host**,
not a component, and its dirty flag is a different pattern (a per-frame poll
watching camera size + viewport size, see CONTEXT.md "Combat UI windows" and
ADR-0010) — it does not migrate.
_Avoid_: re-implementing `_layout_dirty` / `_request_layout_update` /
`_do_layout_update` ad hoc in a new component — extend UIComponent and the
contract is inherited; conflating UIWindowHost's `_placement_dirty` with
this contract — same idea, different mechanics, deliberately named apart.

**Setter shapes**:
Most `@export` property setters on a UIComponent fall into one of these
shapes — a descriptive vocabulary for reviewers, not an exhaustive
classification. Real setters often compose two shapes (push-to-child *and*
mark dirty); the names are for talking about the pieces.
- **(a) layout-affecting** — change requires recomputing positions / sizes
  of children. Setter calls `_mark_layout_dirty()` (deferred, coalesced).
- **(b) sync propagation** — change writes derived state to one or more
  children synchronously. Trivial cases use `_push(child, &"field", v)`;
  multi-target or conditional propagation can call a helper that does the
  same kind of work (e.g. `_update_disabled_state()` toggling both a click
  area and a text colour).
Setters that do neither (a) nor (b) work are the bare `@tool` boilerplate
— equality guard + assignment, required by Godot's `@tool` property
serialization (see CLAUDE.md). They aren't a shape; they're the minimum
every `@export` on a `@tool` script needs.
_Avoid_: calling `_mark_layout_dirty()` when only shape (b) is needed
(introduces a one-frame lag on writes like `text` or `render_priority`);
calling `_push` for layout work (skips the batched-dispatch coalescing).

**Registered element**:
A named logical part of the UI with its own origin — anything moved,
animated, clipped, or cited against the oracle *as a unit* (a window, its
frame chrome, a header, a column band, a cursor, a row block). An element
is registered with its parent element (the nearest registered ancestor)
and carries a [spec](30-ui3-components.md) answering every
[criterion](30-ui3-components.md). Same term as ADR-0084's transition
"element" — one vocabulary. See ADR-0088.
Placement is authored in **absolute display px** — the oracle's coordinate
space — never parent-relative offsets; riding a moved parent is mechanical,
not authored (resolved 2026-08-11).
_Avoid_: registering every mesh/glyph (those are [payload](30-ui3-components.md));
one-element-per-class (sub-parts stay unaddressable); holding a part as a
bare member-variable node — "just a variable" is the unregistered state the
model retires; authoring a child's placement relative to its parent (the
oracle measures absolutes; a relative view is a display concern).

**Criterion**:
One of the standard questions every registered element must have answered:
placement, frame chrome, transition, clip membership, metrics (PPU, depth,
palette). **"None" is an answer; absence is a failure.** Explicit criteria
(transition, frame, clip) must be authored; inherited criteria (PPU, depth,
palette) resolve from the ancestor chain and are surfaced resolved.
_Avoid_: treating an inherited default as "unanswered" (a default IS an
answer, visibly resolved); adding a criterion whose answer nothing consumes.

**Spec**:
The declared set of criteria answers an element registers with. Shared
engines *implement* the mechanical answers (clip pushing, transition beats,
chrome, metrics) — the spec is consumed, not merely recorded, so declared
and actual behavior cannot drift. Literal-authored spec fields are
automatically live [tunables](34-debug-tuning.md) (same pin → materialise loop).
_Avoid_: a spec field engines ignore (that is a manifest, and it can lie);
hand-wiring a behavior the spec already declares.

**Payload**:
The render internals inside an element — glyph meshes, quads, materials —
discovered by the engines walking the element's subtree, invisible to the
registry. Payload found under NO element is the registration-audit failure.
_Avoid_: hand-collecting payload materials into per-class arrays (the
engine discovers them); giving payload its own spec.

**Element role (ELEMENT / PAYLOAD)** (ADR-0088 Amendment 5):
The criterion that gates whether a UI3Element *is* a registered element or
is interior content. `ELEMENT` = a named part with its own origin: registers,
mints its `id` slug, must answer `id`+`rect`, gets a UI3-page row. `PAYLOAD` =
rides its parent, never registers, mints no slug, and is exempt from the
`id`/`rect` requirement. **Role is per-instance, not per-class** — the *same*
`UIUnitInfoWindow` is ELEMENT in the [UnitInfoCluster](30-ui3-components.md) and
PAYLOAD as a `UIVitalsRoster` data row — set by whoever builds the instance.
**Default is PAYLOAD**, which is what let `UIComponent extends UI3Element` land
game-wide without breaking boot: an un-migrated widget answers PAYLOAD
implicitly. This is the seam through which the widget world joins the registry
(ADR-0088 §8): a widget becomes editable by declaring `ELEMENT` + an id, not by
being wrapped in a carrier node.
_Avoid_: treating a repeated/templated widget (roster rows) as ELEMENT (it is
not a named part — array-indexed ids + N page rows + slug collisions); reading
"PAYLOAD" as "not migrated yet" (it is a permanent classification, not a TODO);
a *class-level* role (the same class is both, depending on where it is built).

**Derived placement**:
A repeated part's placement computed from a few driving tunables (row 0
anchor + row pitch) instead of authored per instance. Derived elements
mint no tunable of their own and render read-only; the driving values are
ordinary pinnable tunables.
_Avoid_: minting a slug per repeated row; storing computed placements
(recompute from the drivers — "derive, don't duplicate").

**Key location**:
A named alternative placement — one of the ≥2 legal homes an element can
occupy, selected by the orchestrator (the five start-menu containers), or
the named endpoint of a slide beat. Authored as an absolute display-px
rect owned by the class whose oracle citations prove it; an element
answers its placement *by reference* to a location, so tuning the
location moves every element that answers with it. The concept is
deliberately narrow: a placement with only one home is an ordinary
authored rect, and an interior offset is a
[content knob](30-ui3-components.md) — neither is a key location (resolved
2026-08-11, ADR-0088 Amendment 2).
On the UI3 page an at-location rect is a first-class **`AT_LOCATION`**
source (not `DERIVED`): shown by its location NAME, editable two ways —
*edit the value* (a `TuneField` on the location's Rect2 slug; moves the
window and every rider, persists via pin→materialise — it re-authors the
location definition) and *re-home* (a dropdown of the element's legal
locations, `<ns>.loc.*` by namespace prefix, invoking `place_at`;
this element only, runtime, not persisted). Adding a NEW location reuses
pin→materialise with materialise extended to inject the static-var home in
the namespace's owner class (resolved 2026-08-12, ADR-0088 Amendment 3).
_Avoid_: naming a location nothing selects among; authoring one variant
as a delta off another (each is independently oracle-measured, and
placement is always absolute px); a location registry separate from the
tunable system (the bind table is the registry); reporting an at-location
rect as `DERIVED` with an empty slug (the location name is the point);
persisting a new location in the override file alone (a homeless bind —
no static var, no oracle citation).

**Assembly**:
A repeated-content part (an item list, a row block) registered as **one**
element: the block is the unit you move and cite; its repeats are payload
placed from driving knobs (row 0 anchor, pitch — see
[Derived placement](30-ui3-components.md)). A repeat is promoted to an element
of its own only when something addresses it *as a unit* — until a consumer
exists, a per-repeat element is a spec nothing consumes (resolved
2026-08-11).
_Avoid_: an element per row for tree symmetry's sake; a column as an
element (a column has no origin — it is a layout knob of the assembly).

**Screen-anchored assembly**:
An [assembly](30-ui3-components.md) whose origin sits at the screen corner (0,0)
and whose payload each mounts at *absolute* display px — so the element has
no independent placement of its own (a backdrop, the sort header, the pager
pair, the gold-box trail, the slot glove). Its rect is declared with the
**`screen_anchored()`** answer form, a first-class fourth rect source
(`SCREEN_ANCHORED`, alongside authored / derived / at-location): the UI3 page
renders it as an honest, knob-less row ("placement is per-child"), NOT as an
empty `DERIVED` — the two are different facts, and only the explicit marker
lets the page tell "intentionally unplaced" from "author forgot to declare
this rect's drivers". Carries no tunable today; if a group-nudge need ever
arises it grows an optional origin knob without disturbing callers (resolved
2026-08-12, ADR-0088 Amendment 4).
_Avoid_: authoring the sentinel as a literal `Rect2(0,0,256,240)` (the width
and height become lying knobs — editing them does nothing); leaving it an
empty-drivers `derived()` (indistinguishable from a real undeclared-drivers
dead-end, which the no-empty-`DERIVED` audit now fails the build on).

**Content knob**:
A tunable that shapes an element's interior rather than placing a part —
a subtract amount, a feather, a column offset within a row. Not a third
registration category: a knob that *positions* something is a child
element's placement; everything else is a spec field on the element that
owns it, surfaced with that element's criteria. (Resolved 2026-08-11:
there is no "smaller register".)
_Avoid_: a second, lighter registration tier for knobs; leaving a knob as
a class `static var` once its owning part is a registered element.

**Open/close orchestration**:
The element's transition criterion assigns *what* plays; the orchestrator
(the host or screen coordinator) decides *when*, by invoking the open and
close verbs — and *where*, by invoking the place verb with a
[key location](30-ui3-components.md) (resolved 2026-08-11, ADR-0088
Amendment 2). An orchestrator never names a beat; an element never decides
when a composed screen reveals it, or which of its legal homes it occupies
— self-play on mount is a standalone-preview convenience only (resolved
2026-08-11). Selection *policy* (which location fits this moment, e.g. the
opposite-the-unit screen-half flip) is a pure function owned by the class
whose oracle evidence proves it; the orchestrator asks policy, then
invokes the verb.
_Avoid_: a host reaching past the verbs to play a specific beat; revealing
a composed part with a visibility flip or rebuild pop when it declares a
transition (the §15.26 compare-panel gap this rule closes); an element
re-homing itself (where is the orchestrator's call, like when).

**Beat precondition**:
The element criteria a transition beat needs before it can take *visible*
effect — declared by the beat itself (`UI3Beat.precondition(element)`
returns the empty string when satisfied, else the human reason it will
not). `BOX_OPEN` animates an element's OWN aperture, so its precondition is
`clip = OWN_APERTURE`; that is *one beat's* requirement, not a universal
rule — `SLIDE` (unbuilt) moves the transform and needs no aperture. The
UI3 page asks the declared beat and reports per row why Open/Close is or
is not live (`NONE`/`RIDE_PARENT` inert by declaration; `SLIDE`
unbuilt; unmet precondition warns and disables the verb buttons). This is
why "Open/Close works for some elements, not others" — the beat and the
clip are two separable criteria a window pairs deliberately (resolved
2026-08-12, ADR-0088 Amendment 3).
_Avoid_: hardcoding the aperture check in the page (it lies about a beat
whose precondition differs, e.g. SLIDE); auto-coupling `BOX_OPEN` to
`OWN_APERTURE` (clip is oracle-derived, and it breaks the RIDE_PARENT-child
convention); collapsing `transition` and `clip` into one "owns its reveal"
flag (they do not perfectly co-vary — a static clipped panel owns an
aperture but names no beat).

**Aperture pad**:
An authored per-edge expansion of an element's clip aperture beyond its
rect, for payload that legitimately pokes past the frame yet must still
ride the open/close reveal. The pad widens the *box the transition opens
over* — never the per-frame reveal itself — so closed still means fully
shut. A deliberate port-side affordance: the ROM scissor is the container
rect, so parity-dialed screens keep it zero (resolved 2026-08-11).
_Avoid_: marking a part unclipped to dodge a too-small aperture (unclipped
is for parts that *never* clip, and it skips the reveal); padding to paper
over a mis-dialed rect.

**Registration audit**:
The guard that boots a UI screen and tree-walks it: every rendering
payload must sit under a registered element, or the guard fails unless the
owning class is on the legacy allowlist — a tracked file that may only
shrink. A sibling **no-empty-`DERIVED` audit** (ADR-0088 Amendment 4) tree-walks
the same booted screens and fails on any element whose rect reports `DERIVED`
with an empty drivers array — the mechanized form of "no read-only (derived)
dead-ends on the UI3 page"; `SCREEN_ANCHORED`, `AT_LOCATION`, and `AUTHORED`
are exempt, and it carries its own shrink-only allowlist.
_Avoid_: growing either allowlist (that direction fails the build); a static
lint standing in for the audit (runtime detection is the crisp one).

**Ownership map**:
The UI3 page's answer to "what belongs to what": every registered element's
own [payload](30-ui3-components.md) (nested elements excluded) is false-colored by
its owner on the live screen, and the page shows that color as a swatch beside
each row — so the page *is* the legend and all ownership reads at once. It
reveals owned *pixels*, not bounds: a [bounding box](30-ui3-components.md) fails when
containers are large and overlapping (parent and child rects near-coextensive),
whereas colored own-payload shows the ownership boundary as a color boundary.
Payload owned by no element is painted a reserved alarm color, so the map
doubles as a visual [registration audit](30-ui3-components.md) (resolved 2026-08-12,
ADR-0088 Amendment 6).
_Avoid_: a bounding-box overlay as the primary reveal (coarse for big
overlapping elements); tinting via a per-shader uniform (add/subtract fold
members render a legend-mismatched color, and it taxes every future UI shader);
a legend whose on-screen colors do not match its swatches (the tool then lies).

**Owner color**:
The stable, sibling-distinct color assigned to a registered element for the
[ownership map](30-ui3-components.md) — its own-payload wears it and its page row
shows it. The one reserved alarm color is not an owner color: it marks
unmanaged (unregistered) payload.
_Avoid_: reusing the alarm color as an owner color; per-session-unstable colors
(the legend must stay readable as you scan).

**Mute** (UI3 page verb):
A per-row toggle that hides a registered element's own payload on the live
screen — blink one region out to confirm which pixels it owns — sitting beside
the Open/Close [transition verbs](31-combat-ui-windows.md). Companion to the
[ownership map](30-ui3-components.md), not a persisted state: it and the map
auto-clear on page-hide and scene teardown, and prior payload visibility is
restored exactly (never forced visible, which would reveal transition-hidden
content). *Solo* (isolate one, hide the rest) was considered and dropped — the
map is the see-everything view, so isolate-one is redundant (resolved
2026-08-12, ADR-0088 Amendment 6).
_Avoid_: a Solo verb (the map supersedes it); leaving a muted element hidden
after navigating away (a debug view must not outlive its page); forcing
`visible = true` on restore (it must return the captured prior state).
