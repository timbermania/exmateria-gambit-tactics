# UI3 element registration — interface design (ADR-0088)

**Status:** designed 2026-08-11 (`/codebase-design` session; the `/grill-with-docs`
model in [ADR-0088](adr/0088-ui3-elements-register-a-criteria-spec-shared-engines-implement-it.md)
is settled and is NOT re-litigated here). This document fixes the concrete
interfaces the `/tdd` build session implements. Vocabulary: CONTEXT.md → "UI3
components" (Registered element, Criterion, Spec, Payload, Derived placement,
Registration audit); design language per the codebase-design skill (module /
interface / seam / adapter / depth).

Prior art each interface absorbs: `EquipPickerMenu.gd` (`_frame_origin`,
`_rel_world`, `_body_mats`/`_cursor_mats`, `_tp_*` bind helpers, open+close
accumulators), `DetailScene.gd` (`_stats_origin`/`_lower_origin`, `STATS_FRAME0`,
six clip arrays, `_apply_clip`, `set_open_frame`, `_dt_*` helpers),
`StartActionMenu.gd` (the third accumulator), `BoxOpenAnimator.rect_at_frame`,
`UIFrame` (STRIPE_SOURCE / `center_region` / `get_material`), `UIMenuText.mount`
(`mats_out`), `UIVitalsBand.build`, `Tune` Addendum R/E, `TuneField.add` /
`build_control`, `DebugDashboard._set_page`.

## Module map

```
UI3Element (Node3D, class_name)          ← the carrier; deep module #1
  │  spec at construction · movable origin · rel_world · z_for
  │  auto-binds literal fields · owns per-criterion on_update handlers
  ▼ registers on _enter_tree with
UI3Registry (autoload)                   ← the registry index + engine host
  ├─ ClipEngine        (internal seam)   ← aperture push, payload discovery
  ├─ TransitionEngine  (internal seam)   ← the ADR-0084 beat player, extracted
  ├─ MetricsResolver   (internal seam)   ← ppu/depth/palette inheritance
  └─ read surface for the UI3 dashboard page + registration audit
Factories (UIMenuText, UIVitalsBand, UIFrame)  ← unchanged signatures; callers
                                                 stop passing mats_out
```

The scene tree IS the registry (ADR-0088 §2): `UI3Registry` never stores a
parallel hierarchy, only an index of live `UI3Element`s + signals. Engines are
implementation, not interface — callers and the dashboard talk to `UI3Element`
and `UI3Registry` only. One adapter today per engine seam (hypothetical seams
stay internal until something varies).

---

## 1. `UI3Element` — construction surface (open question 1)

### Interface

```gdscript
class_name UI3Element extends Node3D

enum Transition { NONE, BOX_OPEN, SLIDE, RIDE_PARENT }
enum Frame      { NONE, MENU_TILE, STRIPE }
enum Clip       { PARENT_APERTURE, OWN_APERTURE, UNCLIPPED }

# Path A — code-built (the raw-mesh parity world). ONE Dictionary literal at the
# construction site; every literal-authored field is greppable and
# materialise-rewritable in place (ADR-0068 E2/M5).
var header := UI3Element.new({
    "id": "picker.header",                    # required; supplies the slug namespace
    "rect": Rect2(76, 135, 174, 24),          # required; display px, oracle-citable
    "transition": UI3Element.Transition.RIDE_PARENT,   # explicit-required
    "frame": UI3Element.Frame.NONE,                    # explicit-required
    "clip": UI3Element.Clip.PARENT_APERTURE,           # explicit-required
    # optional inherited overrides (ppu, depth_rung, palette, authored_home)
    # optional frame params, e.g. "frame_center_patch": Vector4(6, 7, 21, 17)
})
parent_element.add_child(header)
```

The spec is **one Dictionary literal, not typed args and not a Spec
RefCounted/builder**. Rationale: ADR-0068 E2 already fixes the literal
home as "the spec dict at the construction site"; a builder scatters literals
across chained calls (materialise's M5 content-revalidation then has no single
line to rewrite); typed `_init` args can't carry the open-ended inherited
overrides without a long optional-arg tail.

### Validation — loud, but diagnosable

`_init(spec)` validates **collect-all-then-fail**: every missing required
criterion / wrong-typed field is `push_error`ed individually (prefixed
`UI3Element <id>:` so a headful guard log names *all* the gaps, not the first),
then one `assert(false)` stops a debug/guard run. In a release build the assert
compiles out and the element boots visibly broken with the errors logged — an
unanswered question cannot boot silently either way (ADR-0088 §2).

### `authored_home` default + the materialise freeze rule

`authored_home` defaults to the **authored rect literal's position** captured at
bind time (`Tune.default_of("<id>.rect").position`) — NOT the live/override
rect. **New materialise rule (required extension):** when materialise rewrites
an element's `rect` literal and the spec has no explicit `"authored_home"`, it
must first insert `"authored_home": Vector2(<old rect pos>)` into the spec.
Without the freeze, the home would ride the pin, and content authored against
the old home would visually shift back — re-creating the exact "move the frame,
content stays still" bug the two-model split exists to kill (this is why
`EquipPickerMenu.FRAME_HOME` is a separate frozen const today).

### Placement + child mounting (the `_rel_world` idiom, absorbed)

All authored coordinates stay **absolute display px** (oracle-citable — the key
property of the current code). The element hides the conversion:

```gdscript
func rel_world(px: float, py: float) -> Vector3   # display px → local under this
        # element, subtracting resolved authored_home (EquipPickerMenu._rel_world)
func z_for(rp: int) -> Vector3                    # fold-rung Z from the resolved
        # depth_rung criterion (absorbs the per-class _z_for + _fold_owns copies)
func content_root() -> Node3D                     # where payload mounts (== self
        # today; an internal seam so chrome could split out later)
```

The element places **itself** the same way: its local position =
`screen_to_world(rect.position − parent_element.authored_home)` (top-level
elements resolve against a zero home). A rect scrub moves only the element's
transform; children (payload and nested elements) ride for free. This is the
movable-origin two-model split built in once (ADR-0088 §2) — `_frame_origin`,
`_stats_origin`, `_lower_origin`, and the three per-class `_rel_world`s all
retire.

**What the interface hides:** origin-node management, home-vs-live subtraction,
ppu/PAR conversion, fold-rung Z, bind minting (§5), engine registration.
A migrated `EquipPickerMenu` keeps only: entries/navigation, its build functions
(now mounting via `rel_world`/`content_root`), and RE-specific material setup.

### Rejected shapes

- **Typed `_init(id, rect, transition, frame, clip, opts)`** — arity safety, but
  inherited overrides force an opts dict anyway (two conventions in one call),
  and enum-arg call sites are no more greppable than dict entries.
- **`UI3Spec` RefCounted / builder** — scatters literals; breaks M5.
- **Validation as first-fail assert** — hides all-but-one gap per guard run;
  collect-then-fail costs nothing and saves iterations.

---

## 2. Factory mounting (open question 2)

**Factory signatures do not change.** `UIMenuText.mount/mount_number` and
`UIVitalsBand.build` already take `(parent, position, rung, ppu, [mats_out])`;
`UIFrame` is configured post-`new()`. What changes is the **caller side**, via
the element's interface:

```gdscript
_menu_text.mount(elem.content_root(), text,
    elem.rel_world(NAME_X, y) + elem.z_for(RP_ROW_TEXT),
    RP_ROW_TEXT, elem.ppu())            # ← NO mats_out: discovery replaces it
```

- `mats_out` becomes vestigial for registered elements — the clip engine
  discovers payload materials by subtree walk (§3). The parameter stays
  (default null, other callers untouched); migrated call sites simply stop
  passing it. The `_body_mats`-style hand arrays die at the call sites, not by
  editing the factories.
- `UIFrame` is built **by the element** from the `frame` criterion (ADR-0088
  §4 "Chrome"): `Frame.STRIPE` → `STRIPE_SOURCE`/`STRIPE_MARGINS` (+ optional
  `frame_center_patch` → `center_region`), `Frame.MENU_TILE` → the default
  crop, `Frame.NONE` → no chrome. The element sizes it from `rect.size`,
  parents it under itself at local zero, and applies the palette criterion's
  fg/bg CLUT uniforms — the tribal-knowledge chrome choice becomes one enum
  answer.
- `UIVitalsBand`'s absolute-display-space build (the reparent-keep-global
  dance in `_build_left_strip`) is absorbed: the caller builds it under
  `content_root()` with home-relative coordinates like everything else; the
  band's authored rect fields stay ordinary literals in the owning element's
  band sub-element spec or the caller's driving tunables.

**Depth note:** we deliberately do NOT wrap factories behind `UI3Element`
methods (`elem.mount_text(...)`) — that would be a shallow god-facade whose
interface grows with every factory. The element exposes *coordinates and
metrics*; factories stay independent payload adapters.

---

## 3. Clip engine seam (open question 3)

### The stale-clip kill, by construction

Two structural rules replace the cached arrays and cached rects:

1. **Push = fresh pull-walk.** `ClipEngine.push(element)` walks the element's
   subtree NOW, collects every `ShaderMaterial` on a `MeshInstance3D`
   (`material_override` or surface material), and sets `clip_world` from the
   element's **live** aperture. Nothing is cached — neither the material list
   nor the rect — so neither can go stale (`f8442784d`'s bug class is
   unrepresentable). Cost: a window subtree is ~10²–10³ nodes; pushes happen at
   60 Hz only during the ~9-frame box-open and on scrubs. Trivial.
2. **Mount-time coverage.** The engine subscribes once to
   `SceneTree.node_added`: a `MeshInstance3D` entering under a registered
   element schedules a **deferred, coalesced** `push(owning_element)` (one flag
   per element per frame). Newly mounted payload therefore receives the current
   aperture the frame it appears — no `notify_payload_changed()` hand call in
   any normal path. (The filter is `node is MeshInstance3D` before any ancestor
   walk, so non-UI churn costs one type check.)

`refresh_payload()` remains on `UI3Element` as the explicit idempotent verb
(re-walk + push clip + re-apply metrics) for tests and for exotic mutations the
tree signals can't see (in-place material swaps).

### Apertures

```gdscript
# On UI3Element:
func aperture() -> Rect2i                  # display px; own_aperture elements only
signal aperture_changed(rect: Rect2i)
# internal (TransitionEngine → element): _set_aperture(rect)  → emits + ClipEngine.push
```

- `Clip.OWN_APERTURE`: the element carries the aperture. Settled default =
  its live rect; during a `box_open` beat the TransitionEngine drives it via
  `BoxOpenAnimator.rect_at_frame(live_rect, n)` (the §15.17 scissor — the live
  case). `set_open_frame` and `_clip` state vars retire into this.
- `Clip.PARENT_APERTURE`: clipped by the nearest `OWN_APERTURE` ancestor's
  aperture (none in the chain → effectively unclipped). Resolution happens in
  the engine at push time; the element stores only its declared answer.
- `Clip.UNCLIPPED` (the glove cursor): the engine pushes the infinite-aperture
  sentinel (`Vector4(-1e20, -1e20, 1e20, 1e20)` — the clip shaders' own
  `clip_world` default: xy = world min, zw = world max, discard outside; the
  *inverted* `(1e20, 1e20, -1e20, -1e20)` box is the SHUT discard-all aperture
  today's `_clip_world` maps a degenerate rect to) so the uniform is always
  *explicitly* set; the cursor's exemption is a declared answer, not an omitted
  array membership.

The display-px → world `clip_world` math (`_clip_world` in three classes today)
moves into the engine, once, using the element's resolved ppu.

**Hides:** payload discovery, the clip_world coordinate math, aperture
inheritance, re-push scheduling. **Interface:** the `clip` criterion + 
`aperture()`/`aperture_changed` + `refresh_payload()`.

Rejected: **cached material sets invalidated by signals** (the cache is the bug
surface; walk cost doesn't justify it), **per-factory mats_out plumbed into the
engine** (keeps the hand-array shape alive), **shader-default infinite aperture
as the only mount-time cover** (still leaves parked non-settled apertures wrong;
the node_added push is cheap and total).

---

## 4. Transition engine seam (open question 4)

### Split ADR-0084's coordinator: beat player (shared) vs recipes+stack (formation policy)

The generalizable mechanical core is the **beat player**: one `_process`, one
delta accumulator, the `_MAX_CATCHUP` clamp, per-beat tick cadence, forward and
reverse drive, settle detection. That extracts into
`UI3Registry.TransitionEngine`. The **recipe/stack coordinator** (screen
navigation, groups-with-barriers, LIFO) stays a Formation-world module and
becomes a *client* of the beat player — no second transition system (the ADR's
rejected option), and no formation screen owning all UI: the engine holds no
screen list, elements register on `_enter_tree`.

### Interface

```gdscript
# On UI3Element — the whole authoring surface for open/close:
func open() -> void                # enter the transition beat (NONE → instant + signal)
func close() -> void               # leave = the same beat reversed (ADR-0084 inv. 1)
func is_settled() -> bool
signal opened
signal closed

# TransitionEngine (internal; beats registered at class level):
register_beat(kind: UI3Element.Transition, beat: UI3Beat)
# UI3Beat (RefCounted): settle_frame(spec) -> int · tick() -> float
#   drive(element, frame) -> void · reverse-drive (default: drive(settle−n);
#   a distinct reverse driver overrides — the Change-Job fling stays honest)
```

- `BOX_OPEN`'s beat drives `element._set_aperture(rect_at_frame(...))` — the
  three copy-pasted accumulators (DetailScene ~1864, StartActionMenu ~576,
  EquipPickerMenu ~847 + its parallel close loop) collapse into the engine's
  one clamped stepper; `play_open`/`play_close`/`closed.emit()` become
  `open()`/`close()`/the `closed` signal.
- `SLIDE` (the *transition* slot) is still unbuilt. An animated MOVE is the
  separate `move` criterion (ADR-0097 §5) with its own `Move` enum, its own beat
  registry and its own cadence — a move has no reverse (the inverse of
  `place_at("centre")` is `place_at("docked")`), so it is not a third direction
  on the open/close beat. Absent `move` = snap, which is what `place_at` has
  always done.
- `RIDE_PARENT` registers no playback: the element is carried by its parent's
  origin (free via the tree) — but it is an *answer*, auditable.
- Beat-specific literals are ordinary spec fields → auto-minted slugs
  (`picker.window.aperture_pad`). The per-verb **cadences** are the one shaped
  exception (ADR-0097 §1/§2): `open_cadence` / `close_cadence` / `move_cadence`
  are required whenever a beat is declared, and mint *enum-hinted* knobs whose
  option list comes from the BEAT — the curve vocabulary is per-beat by design,
  so the element cannot name its own cadence dropdown.

**Reversibility audit for free:** at guard-boot, for every registered element
the engine asserts its named beat exists and is reversible (has a reverse path)
— ADR-0084 invariant 1 extended over all of UI3 (ADR-0088 §7.4).

**Hides:** accumulator/clamp/cadence mechanics, reverse derivation, settle
bookkeeping. **Interface:** the `transition` criterion + `open()/close()` +
settle signals.

---

## 5. Auto-bind threading (open question 5)

### Where binds happen — and why `_init` specifically

`UI3Element._init` mints, per **literal-authored** spec field:

```gdscript
Tune.bind_update(self, id + "." + field, literal, <criterion apply>, hint)
```

`_init` runs while the construction site is on the stack, so ADR-0068 M2's
captured-stack location resolves through the `UI3Element.gd` skip-list entry to
the caller's `new({...})` line — the exact dict whose literal materialise
rewrites (E2). Binding anywhere later (e.g. `_enter_tree`) loses the site.

- `rect` → **one composite `Rect2` slug** (`picker.window.rect`, per R6/E1).
  *Required extension:* `TuneField._control_kind`/`_make_control` gain a
  `Rect2/Rect2i` per-component row (the existing Vector2 pattern × 4), and
  materialise's type formatter learns `Rect2(x, y, w, h)`.
- The three criterion enums → int binds with `{"enum": {...}}` hints
  (decision 11), so chrome/clip/transition are live dropdowns while diagnosing.
  *Required extension:* materialise formats an enum-hinted int back to its
  token (`UI3Element.Frame.STRIPE`) by reversing the recorded hint map —
  today's M5 would skip the named-const token as non-literal. One-hop and
  unambiguous for exactly the R2 reason (one slug ↔ one literal).
- Overridden inherited fields bind under the same scheme; non-overridden
  inherited criteria mint **nothing** (they resolve through the chain and show
  as read-only resolved values on the page).

### The engines are the on_update consumers (E4)

The applies live once, in `UI3Element` — never in a panel (decision 12):

| slug | apply |
|---|---|
| `<id>.rect` | move own transform; resize chrome; re-derive aperture from live rect; `ClipEngine.push(self)` |
| `<id>.frame` (+ params) | rebuild chrome child only |
| `<id>.clip` | re-resolve with ClipEngine; push |
| `<id>.transition` | re-register beat (audited) |
| beat params | consumed on next play (the `aperture_pad` pattern) |
| `<id>.{open,close,move}_cadence` | consumed on next play; range-checked by the beat, not by `validate_spec` (ADR-0097 §1) |

The per-class `_tp_*`/`_dt_*` helper trios and `_rebuild_if_bound` gates retire
for registered elements; a rect scrub no longer rebuilds a whole subtree —
moving an origin is enough (rebuilds remain only for fields that genuinely
re-mesh, e.g. frame variant).

### Derived placements — mint no slug, visibly

```gdscript
"rect": UI3Element.derived(["picker.rows.row0_y", "picker.rows.pitch"],
    func () -> Rect2: return Rect2(NAME_X, row0_y + i * pitch, W, H))
```

`UI3Element.derived(drivers, f)` returns a small `DerivedRect` RefCounted. The
element detects it (not a `Rect2` literal), **binds nothing**, subscribes one
`on_update` per driver slug to re-evaluate `f` and re-place, and reports
`source = DERIVED` to the page (rendered read-only). The driving values are
ordinary pinnable binds in the owner (E3, R7 "derive, don't duplicate"). A bare
`Callable` is also accepted (re-evaluated only on explicit refresh) but the
drivers form is the recommended one — it removes the last hand-wired
refresh path.

---

## 6. Registry read surface for the UI3 page (open question 6)

```gdscript
# UI3Registry (autoload) — read surface (the page's entire dependency):
func roots() -> Array[UI3Element]              # registered elements with no
                                               # registered ancestor (screens)
func children_of(e: UI3Element) -> Array[UI3Element]
signal element_registered(e: UI3Element)
signal element_unregistered(e: UI3Element)

# UI3Element — per-row model:
func id() -> String
func criteria() -> Array[Dictionary]
# each: { "field": String, "value": Variant,
#         "source": AUTHORED | INHERITED | DERIVED,
#         "slug": String }        # "" when no slug minted (inherited/derived)
```

The page (`UI3RegistryView`, DebugDashboard **page 3**, button "UI3" —
ADR-0035 dec. 8; mechanism = the existing `_set_page` radio +
a fourth scroll container, built like `TunablesRegistryView`, no
`set_studio_page`-style injection needed since the view reads the autoload
directly) renders: tree from `roots()`/`children_of` (fold per element), and
per criterion —

- `source == AUTHORED` → `TuneField.build_control(slug, …)` (spinboxes /
  enum dropdown from the recorded hint; dirty/pin via the existing
  `Tune.is_dirty` + context-menu machinery — nothing new),
- `INHERITED` → dim read-only label showing the RESOLVED value + "(inherited)",
- `DERIVED` → dim read-only evaluated rect + "(derived)".

Rebuild on page-show and on register/unregister while visible (the
`_registry_view.rebuild()` precedent). The page is a **pure view**: it never
binds, never touches elements — every write goes through `Tune.set_value` and
lands via the element's own on_updates (decision 12; the generalized scrub-sweep
guard enforces exactly this path). `DetailScreenDebugPanel` shrinks per
ADR-0088 as rows migrate.

---

## 7. UIComponent adoption (open question 7)

`UIComponent` **extends UI3Element** (single inheritance keeps tree = registry;
a hosted sub-node would let widget and element drift). Consequences handled:

- **No spec at `_init`.** Scene instantiation constructs with no args, so
  `UI3Element._init(spec := {})` tolerates an empty spec and defers validation
  to `_enter_tree`. Widgets answer criteria **per field at class level** via a
  virtual:

  ```gdscript
  # UIButton.gd
  func _register_criteria() -> void:
      answer("transition", UI3Element.Transition.NONE)
      answer("frame", UI3Element.Frame.MENU_TILE)
      answer("clip", UI3Element.Clip.UNCLIPPED)
  ```

  `answer(field, literal)` is a base method that binds — so M2's captured
  stack lands on the `answer(...)` line in the widget's own file, giving
  materialise a real one-literal line to rewrite. (A `_element_spec() ->
  Dictionary` virtual was rejected: by the time the base binds, the subclass
  frame has returned — the captured stack would point at engine internals and
  the literal would be unlocatable.) Missing answers at `_enter_tree` fail
  with the same collect-all push_error + assert.
- **Class-level answers → class-scoped slugs**, minted once (first-write-wins
  bind; every instance subscribes): `uibutton.frame`, not one slug per
  instance. A widget's *instance* rect is host/layout-driven → **derived**
  (mints nothing, reported read-only) — the id for tree display is
  `<class id>#<instance>`; slugs use the class id only.
- **The movable-origin model is conditional on an authored rect.** Literal
  `rect` → the element places itself (raw-mesh world). Derived rect → the
  element *reads* its placement, never writes it — so UIWindowHost dialing,
  `screen_pos`, and the whole **deferred-layout contract
  (`_built`/`_layout_dirty`/`_build_children`/`_update_layout`/`_push`) are
  untouched** (the CONTEXT.md contract this design must not disturb).
  Registration adds criteria + payload discovery + audit coverage; it does not
  replace layout (ADR-0088 §8).
- Sub-part elements (list-modal header vs row block) are added as ordinary
  code-built children only where independently tunable parts exist.

---

## 8. Registration audit seam (open question 8)

```gdscript
# UI3RegistrationAudit (static helper, used from guard scenes):
static func violations(ui_root: Node) -> Array[Dictionary]
# each: { "node": NodePath, "owner_class": String }  — every MeshInstance3D with
# a ShaderMaterial under ui_root that has NO UI3Element ancestor; owner_class =
# the nearest ancestor with a script (its class_name / script path)
static func assert_owned(ui_root: Node, allowlist_path :=
    "res://config/ui3_registration_allowlist.json") -> void
```

- **"Rendering payload"** = a `MeshInstance3D` carrying a `ShaderMaterial`
  (override or surface), reachable under the audited UI root. Scoping the walk
  to the screen's UI root (not the whole scene) excludes world/battle meshes
  without heuristics.
- **Where it runs: piggybacked on each screen's existing guard scene** (the
  DetailScene/picker harnesses, CombatUITest) — one `assert_owned(ui_root)`
  call per screen guard. No separate mega audit scene: screens boot
  differently, and the per-screen harnesses already exist and stay headful.
- **Allowlist format** (`res://config/ui3_registration_allowlist.json`,
  tracked):

  ```json
  { "classes": ["DetailScene", "StartActionMenu", "FormationScene", "..."] }
  ```

- **Shrink-only, two-sided:** (a) a violation whose `owner_class` is not
  listed → guard fails (growth of violations fails); (b) a listed class with
  **zero** current violations → guard fails with "remove <class> from the
  allowlist" (forced shrink — an entry cannot linger after its migration
  lands). Growth of the file itself needs a code change that reviewers see in
  the same diff as the new violating class; the Effect-Studio tracker's
  baseline file is not needed because (b) makes the list self-tightening.

---

## Required changes to existing modules (summary)

| Module | Change | Why |
|---|---|---|
| `TuneField` | `Rect2`/`Rect2i` per-component control kind | composite rect slug (R6/E1) |
| `tools/materialize` | `Rect2(…)` literal formatting; enum-token formatting via reversed `enum:` hint; **authored_home freeze on first rect rewrite**; `UI3Element.gd` → M2 skip list | E2, §1, §5 |
| `DebugDashboard` | 4th page button "UI3" + scroll host for `UI3RegistryView` | ADR-0035 dec. 8 |
| `project.godot` | `UI3Registry` autoload (after `Tune`) | engine/registry home |
| Factories | none (callers drop `mats_out`) | §2 |
| `UIComponent` | `extends UI3Element`; `_register_criteria()` per subclass | §7 (then `godot --path . --import` — class_name base edit) |
| ADR-0084 coordinator | consumes TransitionEngine's beat player (migration step, not day one) | §4 |

## Guard map (what `/tdd` builds against)

1. **UI3ElementSpecTest** — collect-all validation (N missing criteria → N
   push_errors), authored_home default, `rel_world`/`z_for` math vs the
   EquipPickerMenu constants, nested-element placement.
2. **UI3AutoBindTest** — slugs minted for literal fields only (derived/inherited
   mint none); enum hints recorded; rect scrub moves the origin write-through
   (the generalized R8 scrub sweep); `answer()` path binds class-scoped slugs
   once.
3. **UI3ClipEngineTest** — mount payload mid-settled → current aperture applied
   same frame; aperture change re-pushes; `UNCLIPPED` gets the sentinel;
   `PARENT_APERTURE` nesting; the `f8442784d` stale-scrub scenario as a
   regression case.
4. **UI3TransitionEngineTest** — box_open `open()`/`close()` reverse symmetry,
   settle signals, `_MAX_CATCHUP` clamp (delta spike ≠ teleport), boot-time
   reversibility audit failure on a beat with no reverse.
5. **UI3RegistrationAuditTest** — unowned mesh fails; listed class passes;
   zero-violation listed class fails (forced shrink).
6. **Migration goldens** — `EquipPickerFrameGroupTest` /
   `DetailFrameTunablesTest` position-multiset unchanged behind each migrated
   widget (GDUMP regen pattern), per ADR-0088 §9.

## Deferred (unchanged from ADR-0088)

Oracle anchor criterion; build slicing order (suggested: registry core + spec
validation → clip engine → transition engine → auto-bind + page → picker
migration behind its golden → audit + allowlist). The build session owns the
order.
