# UI3 elements register a criteria spec with their parent; shared engines implement the criteria

**Status:** accepted (2026-08-11, `/grill-with-docs` design session — build pending,
to be sliced via `/tdd`; concrete interfaces designed in
[`docs/ui3-element-interfaces.md`](../ui3-element-interfaces.md), the `/tdd`
blueprint). Generalizes ADR-0084's element/coordinator to all of UI3;
amends ADR-0035 (new dashboard page) and ADR-0068 (auto-minted binds) — see the
amendment sections in those files. The CONTEXT.md "UI3 components" cluster carries
the ubiquitous language (Registered element, Criterion, Spec, Payload, Derived
placement, Registration audit).

## Context

Working on UI3 "has always been a struggle": things are not done consistently, and
matching pcsx-redux is a fight. Five recurring failures, each evidenced by the
2026-08-11 hand-fix session (`c36050ef4..c011d5b04`, 11 commits):

1. **Missing transitions.** `EquipPickerMenu` had a box-OPEN but no close until
   `addd1bd4b`; "does X animate on open/close?" is answered per class, ad hoc. The
   box-open `_process` accumulator loop is copy-pasted **three times** (DetailScene,
   StartActionMenu, EquipPickerMenu — the third adds a parallel close accumulator).
2. **Which frame is tribal knowledge.** `UIFrame.STRIPE_SOURCE` vs the flat
   menu-tile default vs the `center_region` interior patch — multiple RE rounds were
   burned rendering the wrong chrome (FORMATION_SCREEN.md §15.26).
3. **Not every part is positionable.** ~20 frozen consts were promoted to tunables
   ONE AT A TIME this session; `GLYPH_X` was bound but invisible (missing view row)
   — the class of gap only auto-surfacing kills.
4. **No standard metrics.** `PIXELS_PER_UNIT := 0.04` is declared **six times**
   across ui3; `backgrounded` palette-swap is hand-wired per material; depth rung,
   size, and background have no uniform surface.
5. **Clip is hand-managed.** Per-material `clip_world` pushed onto hand-collected
   arrays (`_body_mats`, `_stats_frame_mats`, …); `f8442784d` fixed a stale-clip
   bug where a frame scrub re-applied the OLD aperture — error-prone by
   construction.

Structurally, UI3 is two worlds: the **UIComponent widget world** (UIButton, the
UIWindow family, list-modals — which has a base-class deferred-layout contract) and
the **raw-mesh parity world** (DetailScene, EquipPickerMenu, StartActionMenu,
Formation — bare `Node3D` holder vars + `ShaderMaterial`s, where all five pains
live). 50 `class_name`s, no umbrella base. The "movable origin + relative content"
two-model split (live tunable rect places an origin node; content offsets subtract
a FIXED authored-home anchor) is hand-repeated in three classes.

## Decision

Every UI3 element is **registered with its parent element** and carries a
**criteria spec**; **shared engines implement the mechanical criteria from the
spec**. Registration is not a manifest that merely records answers — the engines
*consume* the answers, so a declared behavior and the actual behavior cannot
drift.

### 1. An element is a logical part; everything inside it is payload

An **element** is a named part with its own origin — anything you would move,
animate, clip, or cite against the oracle *as a unit*: a window, its frame chrome,
a header, a column band, a cursor, a row block. Its glyph meshes, quads, and
materials are **payload**: internal render carriers that the engines discover by
walking the element's subtree (which is what retires the hand-collected material
arrays). Not per-class (too coarse — pain 3 survives inside), not per-mesh (glyph
soup, hundreds of specs per screen).

### 2. The carrier is a `UI3Element` node; the tree is the registry

`UI3Element` (extends `Node3D`) *is* the element's origin node:

- **Spec required at construction** — a missing required criterion fails loudly at
  `_init` (push_error + assert); an unanswered question cannot boot.
- **The movable-origin two-model split is built in once**: the live rect tunable
  places the node's transform; children mount relative to the spec's
  `authored_home` (default: the authored rect position). "Move the frame, content
  rides" and "rebuild lands frame-relative" stop being per-class idioms.
- **Parent = nearest registered ancestor**, resolved on `_enter_tree`. The scene
  tree IS the registry; a registry/tree disagreement is unrepresentable.
- Factories (`UIMenuText`, `UIVitalsBand`) mount their payload INTO an element
  instead of a caller's bare holder var.

### 3. The criteria partition — explicit-none beats absent, a default is an answer

| Tier | Criteria | Rule |
|---|---|---|
| Always required | `id`, `rect` | an element exists to be placed |
| **Explicit-required** | `transition` (none \| box_open \| slide \| ride_parent → a beat), `frame` (stripe \| menu_tile \| center_region variant \| none), `clip` (parent_aperture \| own_aperture \| unclipped) | author must write an answer; `none` is valid, absence fails construction — these three are the criteria whose silent absence caused real bugs |
| Inherited-defaulted | `ppu`, `depth_rung`, `palette`/background behavior, `authored_home` | resolved from the ancestor chain, shown RESOLVED in the dashboard, overridable — inheritance kills the six `PIXELS_PER_UNIT` copies |
| Deferred | oracle anchor | see "Deferred" below |

### 4. Shared engines implement the mechanical criteria

- **Clip engine**: reads `clip` per element, collects payload materials from the
  subtree, pushes `clip_world`, and re-pushes on every aperture change — the
  stale-clip bug class dies by construction. `unclipped` (the cursor) is a
  declared answer, not a hand-managed omission.
- **Transition engine = the ADR-0084 coordinator, generalized beyond the
  Formation screen.** The `transition` criterion names a **beat**; open/close is
  `enter`/`leave`; one clamped stepper replaces the three copy-pasted
  accumulators; ADR-0084's boot-time reversibility audit ("every open has a
  close") covers registered elements for free. `UI3Element` and ADR-0084's
  "element" are the same term.
- **Chrome**: the `frame` criterion selects the `UIFrame` variant; the element
  builds it — choosing chrome becomes an enumerated answer, not tribal knowledge.
- **Metrics**: `ppu`/`depth_rung`/`palette` resolve through inheritance with one
  root home.

### 5. Auto-tunables: registration feeds ADR-0068, same pin → materialise loop

Every **literal-authored** spec field auto-mints a Tune bind named by element id
(`picker.header.rect`; the three enums too, so chrome/clip/transition are
scrubbable live while diagnosing). The workflow is unchanged: scrub on the
dashboard → right-click pin → `tune_overrides.json` → **materialise** rewrites the
literal — now the literal *inside the spec at the construction site* (ADR-0068
Addendum E). **Derived placements** (row N = `row0 + pitch·N`) mint no slug; their
driving values (`row0`, `row_pitch`) are ordinary pinnable tunables and the
derived element renders read-only. Consequence: the per-const tunable-compliance
loop is dead for registered elements — **registering IS compliance**.

### 6. Dashboard: a dedicated "UI3" page

A fourth `DebugDashboard` page (Studio precedent, ADR-0035 dec. 8): a
tree mirroring the live element hierarchy — screens at the root, elements nested
as registered — each node unfolding to its criteria rows (rect spinboxes, enum
dropdowns, resolved inherited values, dirty/pin state). The hand-built
`DetailScreenDebugPanel` shrinks to whatever is not yet registered.

### 7. Enforcement: a ratchet, mechanized

1. **Construction-time**: missing required criterion → loud failure (above).
2. **Registration audit** (runtime, in the guard-scene harness): boot each UI
   screen headful, tree-walk — every rendering payload (`MeshInstance3D` /
   `ShaderMaterial`) must sit under a registered element. Violations fail unless
   the owning class is on `ui3_registration_allowlist.json`, a tracked file that
   **may only shrink** (growth fails a check — the Effect Studio editability
   tracker pattern). No static lint: runtime detection is crisp where static
   detection would be heuristic guesswork.
3. **Write-through scrub sweep**, generalized: for every auto-minted slug, scrub
   and assert the screen changed — kills the silent `set()` no-op class.
4. **ADR-0084 reversibility audit** covers the transition criterion.

### 8. The widget world joins through UIComponent

`UIComponent` gains the element contract in the base — each widget subclass
answers the criteria once at class level and is thereby registered (a whole
UIButton IS one logical part; its glyphs are payload). Sub-part elements are added
only where a widget has independently tunable parts (list-modal header vs row
block). The deferred-layout contract UIComponent already owns is untouched —
registration adds criteria; it does not replace layout.

### 9. Migration: design for all, ratchet the code

The model covers both worlds from day one; shipped widgets migrate incrementally,
**each behind a visual no-op golden** (the position-multiset pattern,
`EquipPickerFrameGroupTest` + GDUMP regen). Detail screen + equip picker first
(freshest, best-guarded). New or touched elements MUST register; the allowlist
only shrinks.

## Considered options (rejected)

- **Manifest-only registration** (element keeps its own implementation; the spec
  just records answers + surfaces tunables). Rejected: guarantees the question is
  *answered*, not that the answer is *true* — a declared close animation can
  still be missing, a declared clip can still go stale, which are exactly the
  bugs this exists to kill.
- **Full framework** (spec drives ALL construction; elements are pure data +
  content callbacks). Rejected: every pcsx-oracle quirk must be expressible in
  the spec on day one, or elements fight the framework instead of the UI. The
  hybrid centralizes precisely the criteria that proved mechanical.
- **Big-bang migration** of all ~50 classes. Rejected: weeks of churn with the
  whole UI at risk at once; the ratchet reaches the same end state with the
  best-guarded screens proving the model first.
- **Explicit `Registry.register(parent, node, spec)` on existing nodes** (no new
  node class). Rejected: registry and tree can drift apart, and the
  movable-origin split stays hand-rolled per class.
- **Spec in node metadata** (`set_meta` + tree-walk). Rejected: stringly, silent
  when missing, and nothing owns the movable-origin behavior.
- **Per-class granularity** (pain 3 survives inside each class) and **per-mesh
  granularity** (hundreds of specs, glyph-soup debug tree).
- **A separate per-element transition player** distinct from the ADR-0084
  coordinator. Rejected: two transition systems, duplicated pacing/clamp/reverse
  logic, and the reversibility guarantee re-implemented.
- **Static lint for banned idioms** (bare holders, local PPU consts). Rejected
  for now: false-positive fights; the runtime audit + allowlist ratchet detects
  the same failures crisply.
- **Rect-only auto-bind** (enums stay code-only). Rejected: "which chrome / clip
  is wrong?" returns to edit-compile-look instead of live scrubbing.

## Deferred (explicitly out of scope)

- **Oracle anchor criterion** (structured fb4 crop / prim citation per element,
  harness hookup, parity diffing). Deferred by decision: first gain the power to
  manually dial everything in; a separate "tune the tunables against a harness"
  system can then be designed on top. The spec leaves room for an optional field
  later; nothing carries it now.
- Build slicing (`/tdd`): registry core → one migrated widget behind a golden →
  auto-tunable surface → enforcement checks. Suggested order only; the build
  session owns it.

## Consequences

- The five pain classes get structural answers: transitions are audited beats;
  chrome is an enumerated criterion; every element's placement is auto-tunable;
  metrics inherit from one home; clip is engine-pushed and cannot go stale.
- `DetailScreenDebugPanel` (~80 hand-authored rows, built 2026-08-10/11) is
  superseded incrementally by the generated UI3 page — the fold-section work
  survives as the interim surface for unregistered legacy.
- The tunable-compliance loop (ADR-0068 skill) retires for registered elements;
  it remains the path for non-element tunables.
- Cost, stated honestly: `UI3Element` + engines + audit are real machinery, and
  registration adds a spec's worth of ceremony to every part. The bet — same as
  ADR-0084's — is that a bug class made *unrepresentable* (stale clip, missing
  close, dead knob) beats per-incident fixes, on the evidence of a session that
  spent 11 commits hand-fixing instances of exactly these classes.
- Guards multiply by design: construction failure, registration audit, scrub
  sweep, reversibility audit, per-widget goldens — each mechanizes one clause of
  the decision (`enforce-adr-conformance` has teeth to check against).

## Verification

- **Registration audit guard**: boot DetailScene's test scene; assert zero
  unowned payload once detail/picker are migrated; assert the allowlist file did
  not grow.
- **Scrub sweep guard**: for each auto-minted slug on the booted screen, scrub ±N
  and assert a golden-position delta (write-through), then restore.
- **Golden no-op per migration**: position multiset before/after registering a
  widget is identical (GDUMP regen pattern).
- **Reversibility**: ADR-0084's audit extended over registered elements' beats.
- Headful boot of `CombatUITest.tscn` + the formation/detail scenes stays the
  acceptance path (never `--headless`).

## Amendment 1 (2026-08-11, refinement `/grill-with-docs` after the build landed)

The build shipped (`6c5a9d60b..0435b7a8a`; EquipPickerMenu migrated behind the
unchanged golden). Exercising the UI3 page against the live picker resolved six
questions the original decision left open. Vocabulary for all six is in
CONTEXT.md ("UI3 components": Assembly, Content knob, Aperture pad, Open/close
orchestration).

1. **No second registration tier for content knobs.** A knob that *positions* a
   part is that part's element `rect`; every other knob is a **spec field on
   the element that owns it** (auto-minted, surfaced with that element's
   criteria on the UI3 page). The picker's remaining `static var` content knobs
   migrate into child elements — left strip, header, rows block — with the
   scalars (`strip_sub`, feather, column x's, dy nudges) as fields on them,
   behind the unchanged position-multiset golden. Rejected: a lighter "mini
   register" (a second tier reintroduces the two-surface split the page exists
   to kill).

2. **Placement stays authored in absolute display px** — the oracle's
   coordinate space (fb4 crops, prim scans, the §15.x tables are all absolute).
   Parent-relative riding is mechanical (movable origin), never authored; a
   Δ-from-parent readout is at most a page display affordance. Rejected:
   parent-relative authoring (every oracle citation would need subtraction in
   both directions, forever).

3. **Assembly granularity.** A repeated-content part (the item list) registers
   as ONE element; repeats are payload placed from driving knobs (row0, pitch);
   columns are fields, not elements (a column has no origin). A repeat gets
   promoted only when something addresses it *as a unit* — until then a
   per-row element is a spec nothing consumes.

4. **`aperture_pad`** (optional Vector4, per-edge display px, OWN_APERTURE
   elements): pads **the box the transition opens over** — settled aperture
   `= rect.grow_individual(pad)`, beat drive `= rect_at_frame(padded_rect, n)`
   — never the per-frame reveal, so close still ends fully shut. Auto-binds as
   `<id>.aperture_pad`. Honesty: the ROM §15.17 scissor IS the container rect,
   so a non-zero pad is a deliberate port-side affordance; parity-dialed
   screens keep it zero. First consumer: the picker header cells (`HEADER_Y`
   132 pokes above the aperture top y136). Rejected: `UNCLIPPED` as the answer
   for slightly-poking parts (skips the reveal — it is for parts that *never*
   clip, like the glove).

5. **Orchestration rule, made explicit:** the element's `transition` criterion
   assigns *what* plays; the orchestrator decides *when*, calling the
   `open()`/`close()` verbs — an orchestrator never names a beat, an element
   never decides when a composed screen reveals it. `autoplay_open`-style
   self-play demotes to a standalone-preview convenience. Consequence: the
   §15.26 compare panel (ROM slots 0xb/0xc, `_rebuild_stats_delta`) — today a
   visibility pop on `set_stats_preview(true)` — becomes a registered element
   (`BOX_OPEN` / `OWN_APERTURE`) opened/closed by the picker orchestration and
   torn down on `closed`. Whether the ROM box-opens those slots is checked
   against the oracle at build time (static-rooted, dynamically validated);
   the reveal itself is a product decision and stands either way.

6. **The UI3 page gains per-element Open/Close verb buttons** (invoking the
   verbs — the page stays a view; a verb is not a write) plus clip-mode
   labels/tooltips. This closes the "I set it to box open — it just binary
   turns on" dead end: scrubbing the `transition` enum declares, the buttons
   invoke.

## Amendment 2 (2026-08-11, `/grill-with-docs` — key locations)

The migration loop surfaced a tuning dead-end §5 left open: a derived
placement whose "drivers" are frozen consts mints nothing and drives nothing.
The canonical case is `startmenu.window` — `derived([], func: Rect2(c))`, an
**empty drivers array** closing over one of five host-selected container
consts (`CONTAINER`/`EQUIP_CONTAINER`/`ABILITY_CONTAINER`/`MAIN_CONTAINER`/
`MAIN_CONTAINER_RIGHT`). Five oracle-proven placements, zero knobs.
CONTEXT.md carries the vocabulary (**Key location**; Open/close orchestration
extended).

1. **A key location is a named alternative placement — the concept is
   narrow.** It exists only when an element has ≥2 legal homes an
   orchestrator selects among, or a slide beat needs a named endpoint. A
   single fixed anchor (changejob `TITLE_FRAME`, `equipicker.cursor`'s
   `FRAME_HOME`) is NOT a key location — it is an ordinary authored rect that
   stops being a const via the existing literal-spec path. Interior content
   offsets stay content knobs (Amendment 1 §1). Rejected: "every placement
   const becomes a location" (mints an indirection nothing selects among).

2. **The Tune bind table IS the location registry.** Each location is a
   `static var` literal in the class that owns it — the DetailScene
   `STATS_FRAME` shape, already ADR-0068 R2/E2-compliant, keeping the oracle
   citations next to the literal — bound to a slug under the owner's
   namespace: `<ns>.loc.<name>` (`startmenu.loc.equip`). No parallel
   location map (echoes "the tree IS the registry"): class statics exist
   before any element boots, so there is no registration-ordering hazard.
   Rejected: a `UI3Registry` location map (second registry, ordering hazard,
   literals drift from their citations); a per-class `LOCATIONS` dict (bind
   minting in a loop puts every slug's M2 capture on the same line).

3. **`UI3Element.at(location_slug)` is a third rect answer form** (literal |
   derived | at-location): sugar for a `DerivedRect` whose drivers array is
   `[location_slug]` and whose eval reads `Tune.get_value(location_slug)` —
   scrubbing the location re-places every element that answers with it,
   through the existing driver machinery. One slug per location, authored
   **absolute display px** (Amendment 1 §2); no base+delta schemes even for
   the mirrored `main_left`/`main_right` pair — each variant is
   independently prim-scan-proven and a delta would couple separately
   measured citations.

4. **Orchestration: WHERE joins WHAT/WHEN.** Construction: the host authors
   the initial answer — `"rect": UI3Element.at(chosen_slug)` — retiring the
   set-`container`-before-`add_child` handshake. Runtime: a new
   orchestrator-invoked verb **`place_at(location_slug)`** re-drives the
   rect to the new location's live value — the WHERE sibling of
   `open()`/`close()`. No declared candidate-set spec field (it would be a
   field nothing consumes; the owner's static-var block documents the legal
   set, and a typo'd slug fails loudly at resolve). **Selection policy stays
   a pure static func in the owner class**, now returning a location slug
   (`main_container_for()` — the oracle-derived screen-half flip stays next
   to the savestates that prove it); the orchestrator calls policy, then
   invokes the verb.

5. **Interior offsets are drivers, not locations.** The container-relative
   offsets shared across all five start-menu variants (`FRAME_INSET`,
   `TITLE_TAB_OFFSET`, row insets — RE-proven identical per §15.23) become
   static-var binds in the owning class, listed in each child element's
   DerivedRect drivers **alongside** the location slug — Addendum E3's
   "drivers are ordinary binds in the owner". One offset knob tunes that
   part across every variant at once.

6. **Key frames: designed in, built later** (the ADR-0085 anchor pattern).
   `Transition.SLIDE`'s endpoints are two key-location slugs; the beat
   interpolates between their **live** values (scrubbing an endpoint retunes
   the animation); the settle state is identical to `place_at(to)`; reverse
   is close (ADR-0084 invariant 1). Built when the first consumer migrates —
   `UnitInfoCluster` (`LAYOUT_TOP`/`LAYOUT_DOCKED` + the §15.1
   `VitalsSlideAnimator` curve) is the pacing prior art and the natural
   first consumer. Nothing carries SLIDE now.

7. **Guards.** (a) Each migration slice sits behind its existing
   position-multiset golden unchanged — bind defaults equal the retired
   consts; golden regen stays deliberate-only. (b) The write-through scrub
   sweep extends over `*.loc.*` slugs: scrub ±N, assert every `at()`
   consumer moved, restore — mechanically killing the empty-drivers silent
   no-op this amendment exists to fix. (c) `place_at` gets a seam guard
   (after `place_at(B)`, the rect equals location B's live value); policy
   functions stay pure-asserted.

## Amendment 3 (2026-08-12, `/grill-with-docs` — the page exposes key locations as editable named positions)

Amendment 2 gave elements `at(location)` and `place_at`, and the sweep proved
scrubbing a location moves every rider — but the payoff never reached the UI3
page. Exercising the live Formation tab surfaced four gaps, all *page-surface*
(the plumbing works; the page throws the answer away): (1) an at-location rect is
reported by `criteria()` as `Source.DERIVED` with an **empty slug** — the location
name is discarded, so the row renders read-only and unnamed; (2) `Open`/`Close`
"works for some elements, not others" with no explanation; (3) plain `derived()`
rows are read-only dead-ends; (4) only `StartActionMenu` answers `at()`, so the
tab reads as a sea of "(derived)". CONTEXT.md carries the new vocabulary (**Beat
precondition**; Key location + Open/close orchestration extended).

1. **At-location is a first-class, editable source.** `DerivedRect` gains a
   `location_slug: String` field (set by `at()`, empty for `derived()` — a field,
   not a subclass, distinguishes the two answer forms). A new
   `Source.AT_LOCATION` is added to the enum, and `criteria()` emits
   `{field:"rect", source:AT_LOCATION, slug:<location_slug>}`. Rejected: reusing
   `AUTHORED` with the location slug — it "just works" through the existing edit
   gate but LIES, because `AUTHORED` means *a literal in this element's own spec
   with a minted slug*, whereas a location slug is a **shared** bind owned by
   another class that many elements answer with. The page must be able to tell
   them apart to show the name and offer re-home.

2. **The page renders AT_LOCATION with two honest verbs, distinct blast radius.**
   (a) **Edit the value** — a `TuneField` bound to the location's Rect2 slug,
   labelled with the location NAME, not the opaque slug/Rect2. Editing moves the
   window AND every rider and persists via pin→materialise (it re-authors the
   **location definition**). (b) **Re-home** — a dropdown of the element's legal
   locations invoking `place_at(slug)`: re-homes THIS element only, at runtime,
   NOT persisted (reboot returns to the host-authored home). The page states both
   radii so "move the window" is never ambiguous between them.

3. **The legal-location set is derived by namespace prefix, not declared.**
   The dropdown = `Tune.registered_slugs()` filtered by the current
   `location_slug`'s `<ns>.loc.` prefix. This CONSUMES nothing new, so Amendment
   2 §4's rejection of a declared candidate-set field STANDS — the set is read
   from the namespace the owner's static-var block already defines. Cost: it
   assumes every `<ns>.loc.*` is legal for the element (true today: all five
   `startmenu.loc.*` are the window's homes); a namespace shared by two elements
   with disjoint legal sets would over-offer, addressed if it ever arises.

4. **Plain `derived()` rows expand to their editable drivers.** The drivers are
   ordinary pinnable binds (§5, Addendum E3); the row renders each as an inline
   `TuneField` under the read-only computed value, so "(derived)" stops being a
   dead end. At-location rows do NOT expand this way — they get the verbs above.

5. **A `beat.precondition(element)` seam makes Open/Close honest** (the "is
   OWN_APERTURE too specific?" question). `BOX_OPEN` drives an element's own
   aperture, so it is visible only on a `clip = OWN_APERTURE` element; but that is
   *one beat's* requirement, not a universal rule (`SLIDE`, when built, moves the
   transform and needs no aperture). So `UI3Beat` gains
   `precondition(element) -> String` (empty = will take effect here, non-empty =
   the human reason it will not); `UI3BoxOpenBeat` returns the reason when
   `clip ≠ OWN_APERTURE`. The page asks the declared beat and reports per row:
   `NONE`/`RIDE_PARENT` → inert by declaration ("reveals with its parent");
   `SLIDE` → "unbuilt: no beat registered"; unmet precondition → warn + disable
   the verb buttons with the reason. Rejected: auto-coupling `BOX_OPEN ⇒
   OWN_APERTURE` (clip is oracle-derived — a parity fact, not a free choice — and
   it would break the deliberate RIDE_PARENT-child convention); collapsing
   `transition` + `clip` into one "owns its reveal" criterion (they are two
   separable facts — *does it animate* vs *does it clip itself* — that do not
   perfectly co-vary: a static clipped panel owns an aperture but no beat).

6. **A location-registry section on the page** lists every `*.loc.*` slug with its
   value, editable in one place — the "surface the named positions" fix, so
   tuning a location does not mean hunting element-by-element.

7. **"Add a key location" reuses pin → materialise, with materialise extended to
   *inject*.** The pin/override file carries values for slugs *already bound in
   code*; it cannot birth a new registered location (no bind = the slug does not
   exist at boot and `at()` fails its assert), and `materialize_tunables.py`
   rewrites an existing literal at a captured use-site — it does not inject. So
   the honest "add it, materialise makes it real" path needs one new capability:
   materialise injects a new `const` + `static var` + bind line into the
   location's **owner class**, resolved from the namespace (`startmenu.loc.*` →
   `StartActionMenu`). This is a genuine ADR-0068-tool extension, **sequenced as a
   follow-on slice after the page-editability work**; until it lands an "add" that
   needs a permanent home is a one-line hand-write. Rejected: persisting a
   location in the override file alone (a homeless bind — no static var, no oracle
   citation, the exact drift Amendment 2 §2 forbids).

8. **Scope.** This session is the page (items 1–6) plus the design of item 7;
   the materialise-injection build and broadening `at()` migration to more
   windows and building the `SLIDE` beat are explicitly NOT in it.

**Guards.** `UI3RegistryPageTest` currently ENCODES the read-only-derived
behavior, so it is updated: an at-location row is editable and its dropdown
re-homes; a `derived()` row exposes editable drivers; a beat's unmet precondition
disables the verb buttons with a reason. The Amendment 2 §7b write-through sweep
over `*.loc.*` already covers "scrub a location, every rider moves." New seams:
`beat.precondition` is pure-asserted (BOX_OPEN with/without OWN_APERTURE); the
location-registry section lists exactly the registered `*.loc.*` slugs. The page also
shows each location's **owner** (the defining class), derived read-only from its Tune
bind site — so the chain element → location → owner is legible end to end.

**Ownership guard (Amendment 2 §2, mechanized).** A key position is shared (many
elements ride it via `at()`), so its literal must live in ONE owner class or "which
class owns this position" is ambiguous and the §7 injection has nowhere sound to write.
`tools/check_location_ownership.py --check` statically scans the quoted `<ns>.loc.<name>`
literals across `src/` and fails the build if any namespace is defined across more than
one class; it is wired as a pre-flight gate in `tests/run_all_tests.sh` (with unit tests
`tools/test_check_location_ownership.py`), and its `resolve()` is the reusable
namespace→owner resolver the deferred §7 add-a-location injection consumes.

## Amendment 4 (2026-08-12, `/grill-with-docs` — broadening editable placement to every registered element)

Amendment 3 shipped the page-editability machinery but left it exercised by a single
consumer: only `StartActionMenu` answered `at()`, so the UI3 tab read as "a sea of
**(derived)**" (Amendment 3 §4 named this; §8 deferred the broadening). This amendment
is that deferred work — audited across all five registered code-built element classes
(`StartActionMenu`, `EquipPickerMenu`, `DetailScene`, `ChangeJobScreen`, `FormationScene`)
and settled per element. It adds one new rect answer form and one new guard; the rest is
applying Amendments 1–3's existing forms to the elements that never got them. Vocabulary:
CONTEXT.md gains **Screen-anchored assembly** and extends **Registration audit**.

**The audit corrected the inventory.** The originating handoff's `grep` for
`derived([], func …)` **missed a whole class**: rects passed as a *bare* `Callable`
(`"rect": func() -> Rect2: return Rect2(STATS_FRAME)`), which `_rect_is_derived()` also
treats as `DERIVED`-with-empty-drivers. These are the *most* important frames on the
detail screen — `detail.stats`, `detail.lower`, `detail.compare` — and they render
read-only on the page **even though their placement is already fully tunable** via the
existing `detail.stats_frame_*` / `detail.lower_frame_*` scalar slugs. The real work,
then, is mostly *reconnecting rect rows to knobs that already exist*, not minting new
locations. Only `startmenu` is a genuine multi-home (case 2); the other four windows are
single authored literals.

### 1. `screen_anchored()` — an explicit fourth rect answer form

Six elements are **screen-anchored assemblies**: origin pinned at screen (0,0), each
payload mounted at absolute display px, so the element has *no independent placement*
(`detail.slot_cursor`, `detail.pager`, `formation.background`, `formation.sort_header`,
`formation.gold_box`, and the `Rect2(0,0,SCREEN)` sentinels generally). They currently
answer `derived([], func: Rect2(0,0,SCREEN.x,SCREEN.y))` — a sentinel whose size means
nothing. `UI3Element.screen_anchored()` replaces it, emitting a new `Source.SCREEN_ANCHORED`
from `criteria()`; the page renders an honest knob-less row ("screen-anchored assembly —
placement is per-child"). Carries no tunable (Q1 Option B); an optional `origin` knob can
be added later (Option C) if a group-nudge need appears, without touching callers.
**Rejected:** an authored literal `Rect2(0,0,256,240)` (width/height become lying knobs —
editing them does nothing, the anti-pattern Amendment 2 §1 forbids); a heuristic
("empty drivers + full-screen ⇒ anchored" — ADR-0088 rejects heuristics for explicit
answers); a generic "(computed)" label for *any* empty-drivers derived (it would MASK the
undeclared-drivers bug the §3 audit exists to catch — the marker separates *intentionally
unplaced* from *undeclared*).

### 2. Per-element classification (the surprising-without-context table)

Each registered element's dead-end rect was classified against Amendment 2 §1's narrow
key-location rule. The decisive question is never "make it `at()`" — it is *what does this
rect actually vary with*:

| Element(s) | Pattern | Treatment |
|---|---|---|
| `detail.slot_cursor`, `detail.pager`, `formation.background`, `formation.sort_header`, `formation.gold_box` | screen-anchored sentinel | **`screen_anchored()`** (§1) |
| `detail.stats`, `detail.lower`, `detail.compare` | bare `Callable` over already-tunable frame statics | **declared `derived([existing slugs], f)`** — surface the existing `detail.*_frame_*` knobs inline on the element row (Amendment 3 §4). `detail.lower` is mode-dependent (`LOWER_FRAME`/`_EQUIP`/`_ABILITY`); it lists the **union** of all three modes' slugs (stable row set beats a live-changing one). `DetailScreenDebugPanel` rows stay — the panel is superseded *incrementally*. |
| `equipicker.cursor` = `Rect2(FRAME_HOME)` | single fixed glove home (const) | **authored literal** `Rect2(76,135,174,101)` → mints `equipicker.cursor.rect`; the repeatedly-pixel-tuned glove home earns an editable row; `FRAME_HOME` const retires into the spec. |
| `startmenu.cursor` = `Rect2(c)` | anchor coupled to the window's *selected* key location | **`at(location)` sharing the window's slug** (NOT a new location) — reads as `AT_LOCATION` named after the same home, and kills the captured-`c` latent inconsistency (a `place_at` re-home would not have moved the frozen capture). Rides the existing `startmenu.loc.*` namespace, so the ownership guard is untouched. |
| `changejob.level`, `detail.vitals_band` | content offset mixing structural parts with 1–2 real knobs | **case-3 drivers**: promote only the genuinely-tunable const(s) — `LEVEL_LABEL_TOP_Y` (write-back, so one edit moves the element rect *and* the real "Lv" glyphs), `VBAND_TOP_OUT`/`_BOT_OUT` — to `static var` + slug, list as drivers. Structural parts (window-frame coupling, fixed height, screen-wide X) stay literals. |

Why the split is not obvious: `formation.background` and `detail.vitals_band` are both
"screen-wide-ish read-only derived" today, yet one becomes `screen_anchored()` and the
other becomes drivers — because the band has a *real* vertical placement (feather edges
30/89) an author tunes, while the backdrop has none. Classification is by *what varies*,
not by how the rect literal happens to look.

### 3. A no-empty-`DERIVED` audit mechanizes "no (derived) dead-ends"

Once `screen_anchored()` marks the intentionally-unplaced elements, any *remaining* rect
reporting `Source.DERIVED` with `drivers == []` is a genuine "author forgot to declare
this rect's drivers" gap — invisible today as a read-only page row. A boot-time audit
(same family as §7's registration audit / write-through sweep) tree-walks each registered
screen and fails on such rows; `SCREEN_ANCHORED`, `AT_LOCATION`, and `AUTHORED` are exempt.
It carries a shrink-only allowlist seeded with the current offenders, which empties as the
migration slices land — the standard ratchet, red-to-green throughout. Consequence: every
future derived rect must declare its drivers or be `screen_anchored()`; that discipline is
the point (it kills ADR pain #3, the silent-gap class).

### 4. Guards & scope

Each migration sits behind its existing position-multiset golden as a visual no-op — bind
defaults equal the retired consts (`StartMenuFrameGroupTest`, `EquipPickerFrameGroupTest`,
`DetailFrameGroupTest`, the per-element `*ElementTest` scenes). New seams:
`screen_anchored()`/`Source.SCREEN_ANCHORED` is pure-asserted (the page row is knob-less
and labelled); the no-empty-`DERIVED` audit is asserted against a booted screen with a
seeded-then-shrinking allowlist; `UI3RegistryPageTest` gains the driver-expansion rows for
the newly-declared detail frames and the `at()`/`AT_LOCATION` name for `startmenu.cursor`.
**Scope:** this session is the design + these docs; the build is a follow-on `/tdd` sliced
one element/screen at a time in the order above. Still deferred (unchanged): the `SLIDE`
beat + `UnitInfoCluster` multi-home (Amendment 2 §6), materialise-injection §7,
UIComponent widget-path registration (§8).

## Amendment 5 (2026-08-12, `/grill-with-docs` — §8 resolved: the widget world joins through UIComponent, gated by an element **role**)

The trigger was a user question — *"why do the vitals bars, nameplate, and black
background not show up in the UI3 page?"* — plus the correction *"pretty much everything
should be moved into the system, and I see them appear once I push enter on a unit."* The
diagnosis grounded three facts. (a) The page is a **pure live mirror** of ELEMENT-role
UI3Elements in the tree (`UI3Registry` register-on-`_enter_tree`); a thing has a row iff
it *is* a UI3Element and its screen is mounted — **never a function of position**. (b) The
vitals panel + nameplate are `UnitInfoCluster` (`Node3D`) + `UIUnitInfoWindow`/
`UIUnitNameplate` — un-migrated widget world, so no row on *any* screen. (c) The black
background is asymmetric: the Status/detail screen houses it in the ELEMENT
`detail.vitals_band`, but the formation roster builds the *same* stripe via
`UIVitalsBand.build(holder,…)` on a bare node — **same pixels, two code paths, only one
migrated**. "Appears on enter" = ○-press mounts `DetailScene`, the screen that migrated its
pieces; the formation roster you open into did not.

This resolves §8 ("the widget world joins through UIComponent"), which the base ADR and
Amendments 1–4 deferred. `UnitInfoCluster` multi-home (Amendment 2 §6) and the `SLIDE` beat
are addressed here for the cluster; materialise-injection §7 stays deferred.

### 1. `UIComponent extends UI3Element` — the widget world is natively element-capable

The mechanism is the **base-swap**, not per-widget carrier nodes: `UIComponent` (the base
of every window/button/roster-bar) extends `UI3Element`. A migrated widget declares its own
`id`/`rect`/criteria through the widget path (`_register_criteria`/`answer`, validated at
`_enter_tree`) — no wrapping node, no reparent-keep-global. **Rejected: carrier-wrap** (a
`UI3Element.new({spec})` per piece hosting the widget as payload, the `detail.vitals_band`
idiom). Carriers are the right tool for a *non-node* payload (`UIVitalsBand` is
`RefCounted`, so `formation.vitals_band` below *does* carrier-wrap), but for the widget
classes they would permanently double the node count and leave §8 unresolved. The bespoke
non-UIComponent nodes in scope (`UnitInfoCluster`, `UIUnitNameplate`, both `Node3D`) re-base
to `UI3Element` **directly** — safe, single-class blast radius.

### 2. Elementhood is gated by a `role` criterion — because some UIComponents are payload rows

A pure "every UIComponent registers" is **refuted by the code**: `UIVitalsRoster` grows and
shrinks a *dynamic list* of `UIUnitInfoWindow` panels (`:169`), one shared template applied
to all. Those are repeated, data-driven **payload rows** — the exact opposite of an element
(*a named part with its own origin, cited individually, minting its own slug*). Registering
each would mean array-indexed ids, N identical page rows, colliding/shared slugs, and
register/unregister churn every resize. So elementhood must be gated — and **not** by "not
migrated yet" (a temporary state) but by a **permanent role every UI3Element answers**:

- **`Role.ELEMENT`** — a named part with its own origin. Registers in `UI3Registry`, mints
  its `id` slug, **requires** `id`+`rect`. Gets a UI3-page row.
- **`Role.PAYLOAD`** — interior/templated content. Rides its parent; **no** registration,
  **no** slug, and `validate_spec` **does not require** `id`/`rect` (no boot assert).
- **Default is `PAYLOAD`.** This is what makes the base-swap boot-safe: all ~9 existing
  UIComponent subclasses answer PAYLOAD implicitly and keep booting untouched. The base-swap
  is *game-wide*; the ELEMENT migrations are a *choosable set* (§4).
- **Role is per-instance, not per-class.** The decisive proof: the *same* `UIUnitInfoWindow`
  class is ELEMENT in the cluster and PAYLOAD in the roster. So role is set by whoever builds
  the instance (the cluster marks its panel ELEMENT with a per-screen id; the roster leaves
  its panels PAYLOAD). This is *also* what dissolves the id-collision problem — only ELEMENT
  instances carry ids, and their builder supplies a context-unique one.

**Rejected: a template-element** (register everything, but repeated widgets collapse to one
"template" row representing all N). It keeps "everything registers" literally true at the
cost of a template/instance concept in the registry and a page that must special-case
collapsing rows — machinery to preserve a slogan. The role gate is the honest model: repeated
payload *is not* an element, permanently.

### 3. `UI3Element` changes (the base-class seam)

- Add `Role { ELEMENT, PAYLOAD }` and a `role` criterion (spec key `"role"`, default
  `PAYLOAD`; the widget path answers it via `answer("role", …)`).
- `_enter_tree` registers with `UI3Registry` **iff** `role == ELEMENT`; `_exit_tree`
  unregisters symmetrically (a no-op for PAYLOAD — it was never in the index).
- `validate_spec` requires `id`+`rect` **only for ELEMENT**; a PAYLOAD spec with neither is
  valid (it cannot boot-assert). An ELEMENT still fails loudly on a missing `id`/`rect`.
- `roots()`/`children_of()`/`parent_element()` are unchanged — they already walk *registered*
  elements, so PAYLOAD nodes are transparently skipped in the ancestor chain (a UIButton
  PAYLOAD between two ELEMENTs does not become anyone's `parent_element`).

### 4. Build scope — which instances flip to ELEMENT now (the two-per-screen cluster + both bands)

Migrated this build (everything else stays default PAYLOAD, migrated later one instance at
a time):

| Element (per-screen) | Today | Becomes |
|---|---|---|
| `formation.unit_cluster` / `detail.unit_cluster` | `UnitInfoCluster : Node3D` | `: UI3Element`, ELEMENT — owns the group slide + an editable `<id>.origin` group-nudge; **root** (the screen is not an element) |
| `…unit_cluster.vitals` | `UIUnitInfoWindow` payload | ELEMENT via the §1 base-swap — own-origin knob, no carrier |
| `…unit_cluster.nameplate` | `UIUnitNameplate : Node3D` | `: UI3Element`, ELEMENT — own-origin knob (bespoke re-base) |
| `formation.vitals_band` | `UIVitalsBand.build(holder,…)` on a bare node | carrier element mirroring `detail.vitals_band` (band is `RefCounted` → carrier is correct here) |

**Instance model:** two independent per-screen cluster elements (`formation.*` and
`detail.*`), **no reparenting** across the transition — matching the code's actual two
instances (`FormationScene` builds one docked, `DetailScene` builds another; ○-press
*hides* the formation one, `FormationDetailTransition.gd:353`). The `UnitInfoCluster`
docstring's "the ONE … instance PAIR that both … reuse" claim is **corrected** — it was
never true. Rejected: one shared reparenting element (faithful to "same sprites slide", but
a real refactor of the transition controller for a visual illusion the two-instance code
already delivers).

**Slide (Amendment 2 §6 for the cluster).** Each sub-element's origin animates from its
docked layout to its **live settled `rect`**, *per-piece* — so (a) the 4px nameplate drift
(docked x=134 → top x=130 vs vitals x=13 both, `UnitInfoCluster.gd:31-32`) is reproduced
byte-for-byte, and (b) the slide lands wherever the knob is tuned (end = the editable rect,
the Amendment 4 write-back property). Rejected: a rigid-group parent translation — one
parent delta cannot be Δ0 for vitals and Δ4 for nameplate at the docked start, so it would
concede a ≤4px frame-0 error; the code calls that drift "unobservable", but a refactor
should not *introduce* a parity gap the goldens would otherwise catch.

### 5. Guards & scope

Each migrated screen sits behind a **position-multiset golden** (formation + detail) proving
the whole change is a visual no-op — ELEMENT bind defaults equal the retired placement
consts. New seams: `Role`/`role` is pure-asserted in `validate_spec` (ELEMENT requires
id+rect, PAYLOAD requires neither) and at the register gate (PAYLOAD never enters the index);
a **role audit** asserts the roster's `UIUnitInfoWindow` panels answer PAYLOAD and stay
unregistered across a resize; a **boot audit** asserts the base-swap leaves the un-migrated
widget classes booting (default-PAYLOAD, no missing-id assert). `DetailRegistrationAudit`'s
`ALLOW := []` tolerance note (the un-migrated cluster) is updated — the cluster is now a
registered ELEMENT tree, so it is *expected* in the walk, not tolerated. **Scope:** this
session is the design + these docs; the build is a follow-on `/tdd`, sliced base-seam (§3) →
formation band → cluster-per-screen (both screens) → role/boot audits. Still deferred:
materialise-injection §7; ELEMENT migration of the other ~8 widget classes (they ride the
default PAYLOAD until individually migrated).

## Amendment 6 (2026-08-12, `/grill-with-docs` — the UI3 page makes "what belongs to what" legible via an ownership map)

The trigger was a user question while looking at the page — *"it's hard to tell 'what
belongs to what'. Maybe solo/mute buttons on each one — isolate things and see what is in
what. Or is there a better method?"* The motivating miss was structural (`formation.vitals_band`
**is** registered but nested under `formation.background`, so the user assumed it was
unregistered), but the felt problem was **spatial**: the flat text tree does not connect a
row to the pixels it owns on the live screen. This amendment settles the affordance; the
build is a follow-on `/tdd`.

The design pass discarded two premises the handoff carried:

- **Bounding boxes are too coarse.** The first plan — a devtools-style rect overlay, nested
  rects = nested ownership — was **refuted by the user against a concrete case**: for
  `formation.background` (≈ the whole screen) with `vitals_band` nested inside (also large),
  the two rects are near-coextensive — noise, not signal. A box communicates ownership only
  when boxes are small and separated; large overlapping containers defeat it. What actually
  distinguishes a parent from a child is that they **render different payload** even when
  their rects overlap — and the model already draws that line: `payload_materials(e)` returns
  an element's **own** payload with **nested elements excluded** ([Payload](../context/30-ui3-components.md)).
  So the thing to reveal is owned *pixels*, not a rect.
- **Fold-fragility was unfounded.** The handoff warned that any visibility-mutating scheme
  risks corrupting compositor-fold enrollment. CONTEXT's *"Fold member lifetime"* (ADR-0074)
  is explicit that it does not: rendering is single-threaded and the held-out draw list is
  rebuilt from **visible instances every frame**, keyed by layer id, never by member. So
  hiding a fold member is safe. This removes the only real objection to the user's solo/mute
  idea.

### 1. The ownership map is the primary tool — false-color each element's own payload by owner

While the map is active, every registered element's **own payload** (the
`payload_materials`/own-subtree walk, **nested elements excluded**) is drawn in an **owner
color** (originally a stable, sibling-distinct golden-ratio hue; **revised to a
flattened-list ROYGBIV ramp in §8**), and the page shows that color as a **swatch beside
each row** — *the page is the legend*. You read all ownership at once: `background`'s backdrop in
color A, `vitals_band`'s strip in color B sitting on top — the ownership boundary **is** the
color boundary, so the overlapping-container problem dissolves. **Rejected: per-element
solo** (isolate one at a time) as the primary — the all-at-once map makes isolation
redundant for the mapping task, and one-at-a-time is strictly less information per glance.

### 2. Faithful color via a debug material swap — no production-shader edits, no future-shader tax

The map must not lie: an ownership legend whose on-screen colors do not match its swatches
is its own bug. The 15 UI-payload shaders across the migrated screens (font, band, box,
box-sub, orb, orb-rim, shadow, solid, cursor-shadow, vitals-bar/sprite) share **no output
include**, and several (band, orb, box-sub) are **additive/subtractive fold members** — a
tint mixed into a subtractive shader is *subtracted*, so its on-screen color would not match
the swatch. Therefore:

- **Chosen: swap, don't tint.** While the map is active, each owned mesh's material is
  swapped to a shared debug "owner-color" material that samples the mesh's own texture alpha
  (**true shape** — glyphs stay glyph-shaped, solid quads stay their region) and uses
  **normal blend** (**true color**, faithful even on add/sub members). Originals are restored
  on exit. Zero edits to production shaders; new UI shaders inherit no obligation.
- **Rejected: a `debug_owner_tint` uniform in each of the ~15 shaders.** Simplest code, but
  (a) add/sub members render a blend-distorted color that mismatches the legend, and (b) it
  leaves a permanent debug uniform in production shaders plus a standing tax — every future
  UI shader must add the hook or silently vanish from the map. A tool that silently
  under-reports coverage is the anti-pattern this whole ADR fights.

### 3. Unowned payload is painted an alarm color — the map doubles as a visual registration audit

Payload found under **no** registered element is the [registration-audit](../../src/ui3/UI3RegistrationAudit.gd)
failure the base ADR names. The map surfaces it *visually*: any UI-payload mesh not claimed
by an element (walk the UI subtree, subtract the owned set) is painted a **reserved alarm
color** not used in the legend. Unmanaged pixels light up, so the map is a live audit as well
as a legend — the same fact, made watchable rather than only asserted in a guard.

### 4. Mute is kept as a zero-cost drill-down; Solo is dropped

A per-row **Mute** toggle (beside the Amendment-1 Open/Close verbs) hides that element's own
payload — blink a region out to confirm "*that* strip was `vitals_band`." It needs none of §2
(pure visibility, no material work). Multi-mute stacks. **Solo is dropped** — the map is the
see-everything view, so isolate-one is redundant. Two safety invariants, adopted as
correctness rather than options: visibility is **captured and restored exactly** (never
force-`true`, or Mute would reveal transition-hidden content), and both the map and any Mute
**auto-clear on page-hide and scene teardown** (plus a page-level "Clear all") — *the live
game is never left altered by a debug view the user has navigated away from.*

### 5. The page stays a pure view; the map draws in the game viewport

The map draws into the **game viewport** (precedent: `MapGridOverlay`), not the debug window
— ADR-0035 puts the dashboard in a **separate OS window**, so the game stays fully visible
beside it and an on-screen map is watchable side-by-side. `UI3RegistryView` remains a
[pure view](../../src/debug/UI3RegistryView.gd) (Amendment 1 decision 12): it writes a
debug-only "focus/map-active" seam that a game-side overlay reads; the production
`UI3Registry` gains no debug state.

### 6. Structure decision — `formation.vitals_band` stays nested

The handoff deferred whether to hoist `formation.vitals_band` to a top-level root to mirror
`detail.vitals_band`. **Decided: don't hoist.** The map makes the nesting legible, which was
the whole reason to consider hoisting; hoisting would pull the band mesh out of `Background`'s
subtree and drop `FormationBackdropElementTest`'s floor+band golden to floor-only — a change
to *real render structure* to serve a legibility the map already delivers. Honest structure
wins.

### 7. Guards & scope

**Scope:** this session is the design + these docs; the build is a follow-on `/tdd`. Guards
the build owes: `UI3RegistryView` renders one owner-color swatch per ELEMENT row and a Mute
toggle; owner colors are stable and sibling-distinct; the visibility predicate
(`visible(E) ⇔ E not muted`, with the map's swap orthogonal) holds under multi-mute; the
debug-material swap/restore is **lossless** (materials and per-mesh visibility identical
before/after a map on→off cycle); unowned payload resolves to the alarm color; the seam
auto-clears on page-hide. Headful verify on a **fold-heavy** screen (formation roster):
activate the map, read the legend against the screen, mute a row and confirm exact restore.
**Deferred:** per-row payload counts (the map + alarm color already predict a blank region);
any text-tree structural change; persistence (a live debug view has nothing to materialise).

### 8. Revision (2026-08-12b, `/grill-with-docs` — ROYGBIV down the list, perceptually spaced) — supersedes the stable registration-index palette

The built palette (`UI3OwnerColors.color_for(i)`) keyed owner color to **registration
index** via a golden-ratio hue sweep at fixed HSV sat/val. The user's complaint, looking at
the live map: *"the colors are not distinct enough and are in some random order… maybe
ROYGBIV top-to-bottom with equally spaced colors based on perceived difference."* Two
independent faults — **order** (golden-ratio-by-registration reads as random down the panel)
and **spacing** (fixed-hue steps are not perceptually uniform, so adjacent legend rows can
still read as similar). The grilling settled the axis explicitly: the rainbow runs down the
**UI3 panel list**, *not* in-game screen position — "*just ROYGBIV down the ui3 list… then
things are where they are in game*." Decisions:

- **Order = flattened panel list, not registration.** `assign_colors` walks the registry
  tree in the **depth-first pre-order the page renders** (roots in order, each followed by
  its subtree — the exact `UI3RegistryView._add_element` traversal), and assigns
  `color_for_rank(rank, n)`. So a row's rank *is* its vertical position in the legend, and
  the swatch column reads top→bottom as a rainbow. (Registration order ≠ display order — the
  old flat `elements()` walk was itself part of the "random" look.)
- **Spacing = perceptual (OKLab), capped short of magenta.** `color_for_rank` is a red→violet
  ramp with **equal steps in OKLCH hue** at fixed OKLab lightness/chroma — "equally spaced"
  = equal *perceived* difference, since HSV hue is not perceptually uniform (green sprawls,
  blue/violet compress). Moderate chroma (`_C≈0.125`) keeps steps inside the sRGB gamut so
  clamping never collapses two ranks. The distinctness floor is a concrete guard (min
  pairwise OKLab distance at a representative N); it **naturally compresses as N grows** —
  the accepted, honest cost of an *even* rainbow over a bounded arc.
- **Stability invariant is deliberately REVERSED.** The old palette's whole point was that
  `color_for(i)` depended only on `i`, so a row never changed color as elements
  registered/unregistered. The ramp depends on **(rank, n)**, so it **re-spreads** when the
  list's membership or shape changes. This is intended — it is the cost of an even rainbow,
  and it is confined to membership changes (within a single map-on session the assignment is
  fixed). The user chose spatial (list) order over cross-session stability. `color_for(i)` is
  **deleted** (its only callers were `assign_colors` and the guard).
- **ALARM stays reserved, re-proven.** The old proof was "the palette lives on a fixed HSV
  sat/val plane that magenta is off." The equivalent proof now: the ramp's hue arc **stops at
  violet (~300°), short of magenta (~328°)**, at fixed moderate lightness/chroma — so no rank
  can resolve to the full-saturation magenta `ALARM`.

**Guards** (`UI3OwnershipMapTest`, red-capable): owner hue is **monotonic** down the ramp and
inside the arc; **min pairwise OKLab distance** across owners exceeds a threshold (the
"distinct enough" check); no rank equals `ALARM`; and `assign_colors` follows the
**flattened DFS pre-order** so `owner_color_for(id)` (swatch) == the on-screen swap color ==
`color_for_rank(rank, n)`.

### 9. Lightness zigzag (2026-08-13, `/tdd` — a second, brightness axis so neighbours stay distinct)

Hue alone still compressed as N grew: measured adjacent OKLab distance fell from 0.083 @N=8
to **0.039 @N=16**, and the user reported *"the colors are too similar — is there some other
color dimension we can use like brightness?"* Chroma was already at the gamut edge (§8), so
**lightness is the free axis**.

- **L zigzags by rank; hue stays monotonic.** `color_for_rank` now alternates lightness
  dark/light by rank parity (even → `_L_LOW≈0.62`, odd → `_L_HIGH≈0.82`, straddling the prior
  fixed 0.72) while the red→violet hue arc is unchanged. So *adjacent* rows always differ in
  brightness even where their hues are close, and the legend still reads top→bottom as a
  rainbow (hue is still monotonic; only L wobbles). Chosen over hue×lightness *tiers* — the
  zigzag keeps one pure hue sweep rather than banding it.
- **Consequence: the ramp is no longer OKLab-*uniform*.** §8's "equal steps in OKLab" now
  means equal steps in OKLCH *hue*; L is a deliberate wobble on top. Distinctness is still the
  honest floor — measured, not assumed.
- **Guards raised + one added.** The min-pairwise-distance floor rises 0.05 → **0.10**; a new
  **adjacent-distance** slice asserts min neighbour OKLab distance @N=16 clears **0.15** (vs the
  old hue-only 0.039) — the slice that proves the fix. The monotonic-hue and reserved-`ALARM`
  guards are unchanged (L doesn't touch hue, so both still hold).

## Amendment 7 (2026-09-09, #1081 — a FIFTH rect answer form for host-derived geometry)

Amendment 4 §3 closes with *"every future derived rect must declare its drivers or be
`screen_anchored()`."* That is now **one form short**, and the gap shipped a defect.

### 1. `host_derived()` — the fifth rect answer form

`UI3Element.host_derived(f)` declares an element whose whole geometry its **host recomputes on
every build**: the gambit CHOICE list, which opens under whichever column the cursor is on and is
torn down and rebuilt on the next press. It emits `Source.HOST_DERIVED`, and — the load-bearing
part — **it mints no `<id>.*` bind at all**: not the rect, not the layout literals, not the enum
criteria.

Not a knob-styling preference. `_mint_binds` mints `<id>.<field>` for every literal spec field and
`Tune._register` is **first-write-wins**, so a second element under the same id gets the FIRST
build's default pushed back into it. The gambit choice list is rebuilt under four constant ids, so
its second window inherited the first's rect and aperture while `authored_home` — never a bind —
stayed its own. `rel_world` compounded the disagreement and the glyphs left the window's own
`OWN_APERTURE` scissor: **a perfectly drawn, completely empty frame at the previous list's
position**, with no error and no failing assert. Measured `To`-then-`Do`: window rect
`(98,28 72x104)` where `(34,28 72x104)` was wanted, and a row-glyph x span of `[-77,-33]` against
a scissor of `[34,106)`.

So the answer is the same one Amendment 4 §1 gives for size — *"an authored size would be a lying
knob"* — carried to the whole spec. A host-derived element's every knob is overwritten by the next
open, and a *minted* one is actively harmful. An author who wants these dialable gives the element
an authored home and uses `at()`; that is what the gambit ROW menu does, one class over.

### 2. §3's exempt set gains a fifth source, and its closing rule is restated

The no-empty-`DERIVED` audit exempts by SOURCE, so `HOST_DERIVED` joins `SCREEN_ANCHORED`,
`AT_LOCATION` and `AUTHORED` — for the same reason `SCREEN_ANCHORED` is exempt: it is a DECLARED
answer, not an author who forgot to name this rect's drivers. Amendment 4 §3's closing sentence now
reads: **every derived rect must declare its drivers, or be `screen_anchored()`, or be
`host_derived()`.**

`criteria()` also stops naming `<id>.transition`/`.frame`/`.clip`/`.ppu`/`.depth_rung` slugs on any
element that never minted them — a page row handing `Tune` an unbound name asserts on read, which
`host_derived()` is the first form to make reachable.

### 3. Guard

`GambitSurfaceTest` arm 15, and it is **coordinates rather than state** on purpose: that file
passed 123/0 for the entire time this shipped, because level, row count, entries and the write were
all correct throughout. The arm opens all three parts IN A ROW — one part proves nothing, the first
list always drew — and per part asserts the window's rect and aperture against the surface's own
`choice_container_for`, plus that the row glyphs land inside that scissor measured in the
ClipEngine's own basis. Direction-tested: restoring the literal answer reds exactly those six
assertions.

**Rejected: a unique id per open.** It fixes the freeze and leaks unbounded Tune slugs — ~40 per
open, forever, in the F3 tree. **Rejected: making `Tune._register` last-write-wins.** That is the
property a persisted scrub depends on; the bug is minting the slug, not what Tune does with it.
