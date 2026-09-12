# A tunable binds a code default to a slug; a sparse persisted override coalesces over it, and the debug dashboard is generated from the registry

Accepted, built incrementally. Verified 2026-08-28 — decisions 3–19 all built; 1 and 2
are retired numbers, superseded within this ADR and left as gaps. The `CONTEXT.md`
"Debug tuning" cluster is the ubiquitous language for this system.

## Context

Debug tuning had three unrelated homes for a value, and *which one* a value happened to
live in silently decided whether it survived, persisted, or could be found — by accident,
not by choice:

- **`DebugConfig` autoload properties** (`psx_dither_enabled`) — in-memory, CLI-seedable,
  no disk.
- **`PSXDisplay` live globals** (`live_par`) — a shared slot with a setter that pushes into
  the shader global *and* a `*_changed` signal panels bind to. This is the *good* pattern:
  one storage, two-way, no divergence — a hand-rolled console variable, built once per
  value.
- **Panel-local vars** (`ScenarioUnitAlignmentDebugPanel._grid_on`) — die with the panel on
  scene reload; can never persist.

Three pains named at the time: (a) "multiple versions of truth" — a value edited in a panel
is often a *copy* that diverges from the real game value, and scrubbing it live never
writes back; (b) persistence is all-or-nothing and accidental; (c) pushing a scrubbed value
*into the running game* is per-field manual wiring, and for values read once at `_ready()`
it silently does nothing.

The industry patterns (Quake/Source `ConVar`, Unreal `TAutoConsoleVariable`, Unity
ScriptableObjects, the C++ `_TV()` / Rust `inline_tweak` "tweakable constant" macro) all
reduce to the same portable core: **a string-keyed registry with a code-supplied default**,
which is what `PSXDisplay.live_par` already was, done once by hand. The purest form
(source-line-is-the-storage, re-parsed live) does not port to Godot — no `__COUNTER__`, and
compiled GDScript does not hot-reparse literals.

## Decision

*Numbers 1 and 2 are retired.* They split the API as `Tune.of(default, slug)` (a
read-in-place two-parameter form) and `Tune.bind(owner, slug, default, apply)` (a set-once
form). That split welded two orthogonal concerns — **where the literal lives** and **how a
scrub reaches the screen** — which is what made the codemod chase forwarded params and
named consts. Decisions 13–17 are the replacement; the numbers are not reused.

3. **Runtime value coalesces: `override_in_memory ?? code_default`.** Same shape as
   ADR-0066's `instance = template + diff` — the code default is the template, a committed
   override is the diff. With no override, the code literal is the honest, live source of
   truth.

4. **The override file is a sparse _staging layer_, git-tracked in the repo tree.** Only
   slugs explicitly committed appear in it. It lives at `config/tune_overrides.json` under
   `res://`, **not** Godot `user://` (which sits outside the repo and cannot be tracked).
   Tracking is deliberate: on a solo project it makes tuning work versioned, reviewable as a
   diff, and portable across worktrees, and the usual reason to gitignore a settings file —
   keeping personal scratch out of shared history — does not apply. **Decisive reason:** a
   gitignored staging file fragments per-machine, so consistent behaviour across checkouts
   would force a `materialize` before *every* commit; tracking removes that treadmill and
   keeps `materialize` a deliberate "bake it when ready" step. It remains a **staging layer,
   not a system of record** — still drained by decision 8, because while an override is
   present the code literal and the file disagree. Tracking *versions* that divergence; it
   does not remove it.

5. **Boot order makes it work for free.** The `Tune` autoload loads the override file into
   memory in `_ready()` — *before* the scene tree — so every registration finds its override
   already resident and applies it on the first frame. No flicker, no `rebind()` gymnastics.
   `Tune` is the **first** autoload, which is why no owner may be named from it at compile
   time (decision 13's corollary).

6. **Subscriptions are owner-scoped and auto-drop.** `on_update` takes the owning node and
   forgets the subscription when that node leaves the tree, so a freed scene never leaves a
   callback driving a ghost. Ctrl+R "just works." The owner sits on the *subscription*, not
   on the registration — it is the update that drives a node (decision 15).

7. **Persistence is a runtime gesture; a declared class is the exception, not the norm.**
   Nothing is written until an explicit **Save/commit**, and a slug whose live value differs
   from its committed override renders **dirty** — the `{66}` "dialed past the committed baseline" state. The pin/commit click *is* the persistence
   decision, which removes the classification burden for the common case: a registration
   with no declared class rests at `Persist.TUNABLE`. Two cases the gesture cannot express
   are declared instead — `Persist.EPHEMERAL` (session-only, never written) and
   `Persist.AUTOSAVE` (an edit commits in the same gesture, for the decision-10 values whose
   home *is* the file). The declaration only ever ratchets up, so a stray registration can
   neither downgrade an `AUTOSAVE` slug nor upgrade an `EPHEMERAL` one.

8. **`materialize` drains the staging layer back into code, and it is located by captured
   stack rather than by grep.** *(Cited as M1–M6 and R6.)* The codemod reads the override file, rewrites each
   registration's default token to the tuned value *by slug*, and clears that entry —
   producing a reviewable git diff. This is "promote to the real game value": the code
   literal reabsorbs the override and becomes the single truth again. The shape is forced by
   what the code actually looks like — slugs are named consts, defaults are named consts or
   cross-module expressions, and some registrations route through wrapper helpers, so a
   grep-for-the-slug codemod cannot find those sites and a blind token rewrite would inline
   a literal over a named const or over a *forwarded parameter*.

   - **It is a Python tool** (`tools/materialize_tunables.py`), not in-engine: its whole job
     is a reviewable git diff over `res://` source. It runs cold and never auto-commits.
   - **Call sites come from `get_stack()`,** captured by `Tune._register` **once per slug, on
     first registration only**, walking to the first frame whose `source` is outside the framework files (`Tune.gd`,
     `TuneField.gd`, `UI3Element.gd`). That
     dissolves the const-slug problem — the frame points at the call regardless of how the
     slug arrived. `get_stack()` returns frames only with the script debugger attached, which
     is every dev run and irrelevant for release.
   - **The registry records *all* use-site locations per slug** (`Tune.locations_of`). A slug
     registered at two sites must have every literal site rewritten, or the codemod forks the
     truth it exists to unify. First-write-wins governs the value and meta; locations append.
   - **The bridge is a dumped snapshot.** `Tune.dump_registry(path)` writes `slug → {default,
     type, persist, locations}` to a **gitignored** `config/tune_registry.snapshot.json` — a
     regenerated dev artifact, unlike the tracked `tune_overrides.json`. Overrides say
     *what*, the snapshot says *where*.
   - **Rewrite is literal→literal only; everything else skips with a warning.** At each
     recorded `file:line` the tool content-revalidates first — confirming the line still
     holds a recognized registration call for *this* slug, searching a small window, and
     skipping with `snapshot stale — re-dump` if not. Only an already-literal default is
     rewritten, formatted by the recorded type. A non-literal default (named const, `.x`
     expression, forwarded param) is skipped and warned, never inlined — which disposes of
     the wrapper hazard for free, since a wrapper site always forwards a parameter.
     `AUTOSAVE` slugs are a silent skip. Stated honestly: with mostly-symbolic defaults,
     little materializes automatically — materialize-ability is a property you opt into by
     putting a literal at the use-site, or by giving the value a `static var` home (below).
   - **One hop to a `static var` home.** The argument token `Owner.some_static_var` resolves
     to that class's `static var` declaration and the initializer literal is rewritten. This
     narrow follower is safe *because of* decision 14's one-slug↔one-literal invariant, which
     is exactly what a general const-follower lacks. Composite slugs collapse to one typed
     slug (`loc_offset_x/y` became one `Vector2` `render.loc_offset`), so there is always a
     single literal to hit.
   - **Drain, then verify.** Each rewritten slug is removed from `tune_overrides.json`; the
     tool then runs `godot --path . --import` and a generated parse-load probe over the
     touched files (`load()` each — a parse error returns null and prints), with `--full`
     escalating to `tests/run_all_tests.sh` for the behavioural guard, since a materialized
     value can be parse-clean yet semantically wrong. On failure it **leaves
     the diff in place** and exits non-zero — a red diff is more debuggable than a silent
     rollback, and `git checkout --` is the one-line no-op.
   - **The recognized-call table (`CALLS`) is the codemod's whole subject and it fails
     quiet.** A
     registration spelling absent from it is not reported as unrecognized: the slug simply
     self-skips, which is indistinguishable from "no literal to bake". A rename that moves
     call sites onto a new spelling must land in that table in the same commit — which is why
     the addon-side `TunePort` façade (ADR-0187) carries its own rows there.

9. **The dashboard is generated from the registry.** One row per registered slug, grouped by
   dotted-namespace prefix, rendered by `TunablesRegistryModel` (the data) and
   `TunablesRegistryView` (the widgets) as a **full-width Registry page** inside the
   existing masonry dashboard (ADR-0035). Hand-built panels
   stay for bespoke UI and read the same slots through `TuneField`. The generated masonry
   *auto-card* that this decision originally specified was removed in favour of the Registry
   page; ADR-0151 records the trade — a categorised card is what was lost, and every slug it
   held is on the Registry page with type, range and default intact.

10. **Debug-only preferences are tunables too.** `show_tile_grid`, logging flags and the like
    register like anything else; their apply just flips debug state. They have no
    `materialize` target — no game literal to bake into — so for them the override file *is*
    home, which is what `Persist.AUTOSAVE` declares.

11. **A tunable's control is inferred from its value's TYPE; an optional hint refines only
    what type cannot express.** The code default already carries the type, so the generated
    page derives the richest control that type alone justifies — `bool`→toggle,
    `float`/`int`→spinbox, `String`→free-text `LineEdit`, `Color`→picker,
    `Vector2/3`→per-component spinboxes. **Free text is the fallback for `String` only** —
    the sole type whose value space is unstructured — never the generic default, because that
    would discard the type already held. Two things type cannot convey come from an optional
    trailing hint dict on the registration: numeric `min`/`max`/`step` (clamp, nudge
    granularity, and the trigger to upgrade a spinbox to a slider), and `enum: {label: value}`
    (an enum is just an `int` at runtime, so with no hint it degrades to a raw-int spinbox).
    The hint lives *with* the value, **not** in a central table — that is the rejected
    god-config bucket — and is recorded in the registry on first registration.

12. **A tunable attaches to the code it tunes, not the scene that shows it — a debug panel is
    a *view*, never an *owner*.** The value is applied at the code that owns it (`Unit`
    registers `render.unit_mesh_scale`; `PSXDisplay` registers `render.psx_par`), so *every*
    scene instantiating that code gets the control live, with zero per-scene wiring. A panel
    only displays and writes the slug; registering it in a scene decides **visibility**, never
    **behaviour**. **Corollary (a prohibition): never re-implement a tunable's effect by
    fanning it out from a scene-specific panel** — e.g. a panel looping over live units
    writing `mesh_instance.scale`. That is a second, scene-local source of truth: the control
    *looks* wired in the one scene whose panel carries the fan-out and is silently dead in
    every other. The tell that you got it wrong: the control works in one scene and does
    nothing in another. `tools/check_debug_panel_tunables.py` is the guard, and it holds for
    generated UI3 pages too — an element's engines are the `on_update` consumers, so a scrub
    reaches the screen through the owner and never through a panel fan-out.

13. **A tunable's literal is a single shared home — a `static var` iff the value has direct
    readers, inline otherwise.** *(Cited as R1.)* A tunable is *one value, many consumers*,
    so its literal home is always a single shared slot: never a `const` (frozen at parse
    time, so a scrub can never reach its readers — the reason the mirrored-const
    anti-pattern existed), never an instance `var` (per-instance divergence, plus *N*
    materialize homes), and never a global bucket (the rejected god-config). Two shapes:

    - **Direct readers exist** (sites read `Owner.member`, e.g.
      `SpriteLayerManager.shared_loc_offset`): the home is a **`static var`** in the owning
      class — the scrubbable "debug const" becomes a `static var`, *in place*, same name.
      `static` is load-bearing: it is the *shared* slot all readers hit, so a scrub is seen
      **structurally**, a property of the storage topology rather than a convention each read
      site must remember. Its initializer is the materializable literal.
    - **No direct readers** (the value is only *applied* set-once, e.g. `mesh.scale`): there
      is no stored symbol at all — the literal lives inline in the registration call. Nothing
      to promote.

    An owner registers its own slugs from a named `register_tunables()`, called by
    `_static_init` at class load (`_ready` for an autoload) and by nothing else;
    `tools/check_tune_owner_self_registration.py` is what holds that, and ADR-0173 is why
    there is no central replay to call instead — a test that cleared the whole registry now
    calls `reset_overrides()`, which leaves every declaration standing.

14. **`Tune.bind(slug, literal)` attaches a slug to exactly one literal — and nothing else.**
    *(Cited as R2.)* It is the registry entry and the emitter; it carries no callback and no
    owner. **One slug ↔ one bound literal** is the invariant that makes conflicts impossible
    and the codemod unambiguous: because registration is pure literals, the page and the
    codemod enumerate *only* registrations and never reason about behaviour.

    The pull-read counterpart is **`Tune.get_value(slug)`** *(cited as R5)*, which coalesces
    `override ?? registered default` with **no use-site capture and no registration**, so it
    is safe in a hot getter where a registration is not (registration captures the stack).
    It asserts a prior registration, and `Tune.is_registered` is the O(1) probe a hot getter
    uses to register lazily exactly once rather than paying the stack capture on every read. This is the pair that retired `Tune.of`: `of` fused
    register-and-read and put the literal at the use-site, which is precisely what forced the
    codemod to chase forwarded params and named consts. A read-in-place consumer registers
    once at a boot/home site and reads with `get_value` at the point of use; the scrub reaches
    it because the getter re-reads, so no subscription is needed. For a `static var` home the
    readers keep reading the var natively and a write-back subscription lands the scrub. The
    write side is `Tune.set_value(slug, v)`, so the getter/setter pair reads
    `get_value`/`set_value`.

15. **`Tune.on_update(owner, slug, apply)` is the PUSH; `Tune.bind_update` is the sugar.**
    *(Cited as R3 and R3.5.)* `on_update` subscribes to the slug and re-runs the path into
    consumed game state, for passive sinks that will not re-read on their own — shader
    globals, built meshes. The `on_` prefix marks it an event hook (the handler runs *on*
    each change), not an imperative "go update". It is owner-scoped per decision 6 and added
    **as-needed**: you add one when you actually want a value to respond to live scrubbing.
    Two shapes — the *write-back* (`func(v): Owner.some_static_var = v`) that lands a scrub on
    a static var's direct readers, and a *re-derivation* for any consumer that cached a
    derived value.

    **Consequence, stated honestly:** a registration alone is *inert to scrubbing*. It makes a
    value enumerable and materializable, but a scrub reaches the screen only once a matching
    subscription exists, so every live-tunable value costs two calls where `of` was one. That
    is the price of a pure page/codemod surface.

    `Tune.bind_update(owner, slug, literal, apply)` is sugar for a registration plus one
    paired subscription — the co-located single set-once consumer, an inline literal with no
    other readers. Its real payoff is not the saved line but eliminating the *repeated slug
    string*, the system's sharpest footgun. It does not weaken the model: it registers
    identically, and its inline literal is materializable. The one guard shared by all forms:
    **the literal is inline at the call, never forwarded through a wrapper** — forwarding, not
    the combined call, was the original codemod pain, which is why `Unit._apply_render_tunable`
    takes the apply and the slug but never a literal a caller supplied.

16. **Derive, don't duplicate — and where a derivation must be cached, it owns one
    subscription.** *(Cited as R4 and R7.)* A cached derivation is a set-once consumer wearing
    a transform: a `static var` read `x * 2` per frame just works, but a `var derived := x * 2`
    computed once and stored goes stale after a scrub. The functional answer is not to cache —
    **a tunable reaches consumption via a computed getter or a recompute-at-use for cheap
    derivations, never a stored `var := f(tunable)`**. Where a cache is forced (Godot's engine
    boundary always is one — the engine renders stored node state), **each cached consumption
    point owns one subscription that recomputes end-to-end from the tuned base** — never a
    graph of subscriptions feeding subscriptions, which is a reactive spreadsheet with
    ordering hazards. Two consumers sharing a long derivation each recompute it; scrubs are
    rare human gestures, so the redundancy is free. Do not over-rotate: cheap getters yes,
    recomputing a heavy derivation on every read no — that is what the cached subscription is
    for. The convention's payoff is that it makes the residual *detectable*: "a stored `var`
    initialized from a known tunable home symbol" is a syntactic scan over the registry's
    symbol set, converting an undecidable data-flow problem into a lint.

17. **Lint the failure, not the form.** *(Cited as R8.)* Do not try to detect "you should have
    used a static var" — that judges a design choice, is false-positive-prone, and rots with
    the model. Detect the two form-agnostic failure surfaces instead: *"this scrub reaches
    nothing"* and *"this home is frozen for its readers."*

    The built arm is the runtime scrub detector. The naive sketch — "scrubbed with zero
    subscribers" — false-positives on read-in-place, because a pull consumer consumes a scrub
    by re-reading with no subscriber at all. So the signal is refined: `Tune` tracks per slug
    the last-scrub frame, the last pull-read frame and the live subscriber count, and
    `poll_unconsumed_scrubs(frame)` — driven each frame by a debug-only `_process` — warns
    **once** for a slug that was scrubbed, has **zero** subscribers, was **not** re-read since
    the scrub, and is past a short grace window (a pull consumer may not re-read on the scrub
    frame itself). A fresh scrub re-arms it. The codemod's non-literal warning is the second
    built arm, catching the forwarded-literal sin.

    Cached-derivation staleness is the residual: reduced by decision 16's convention and made
    lint-able by it, but the general case stays caught by the human tell — the value scrubs
    live everywhere except the one cached consumer — plus an A/B. Do not fake a data-flow
    analyzer.

18. **A UI3 element's spec auto-mints its registrations.** *(Cited as E1–E3.)* Constructing a
    `UI3Element` (ADR-0088) registers every **literal-authored** spec field internally — the
    rect as one composite typed slug named by element id (`picker.header.rect`), and the explicit criteria enums,
    scrubbable live — plus any overridden inherited field. The element id supplies the dotted
    namespace for free, so the hand-written `static var` + registration + `TuneField.add`
    triple retires for registered elements: **registering IS compliance.** The literal home is
    the spec literal at the construction site — the inline shape, not a `static var` home — so
    the codemod rewrites the `Rect2(…)`/enum literal inside the spec dict, with
    `UI3Element.gd` on the framework-file skip list. Decision 14's invariant holds: one element
    id, one spec, one literal per field. **Derived placements mint no slug:** a repeated part
    authors its rect as a derivation from driving tunables (`row0`, `row_pitch`), the driving values are ordinary
    registrations in the owner, and the derived element renders read-only. That is decision 16
    applied to placement — no thirteen row slugs, no stored copies to go stale.

19. **A write-back must not `free()` a node synchronously.** *(Cited as W1–W3.)* A scrub is
    delivered from inside the F3 `SpinBox`'s `value_changed`, emitted from inside the C++
    `SpinBox::gui_input` while it is still on the stack — it touches its own
    `range_click_timer` *after* the signal returns. A write-back that tears down and rebuilds a
    subtree — `_open_root.free()`, a picker `_build_content()` that frees its payload — runs that
    destruction cascade (destructors, `tree_exiting`, registry cleanup, RS frees) nested in
    the input callstack, which SIGSEGVs the 4.8-dev fork with wandering heap corruption
    whose crash site drifts through `Timer::set_wait_time` and the accessibility `HashSet`. This is not a compositor problem; it is the
    generic Godot hazard of freeing during signal dispatch, made lethal here by the SpinBox
    continuing to use its members after the signal. Three sanctioned shapes, in preference
    order:

    1. **Mutate in place** — reshape the existing node or material (`UIVitalsBand.update_extent`).
       No free, no add; safe synchronously on the input frame.
    2. **Defer the rebuild** — set a `_rebuild_pending` flag and `call_deferred` a
       `_flush_pending_rebuild` that frees and rebuilds at the next idle frame, the same safe
       point `EngineFoldCompositor` frees its carriers at. This coalesces a frame's scrubs into
       one rebuild and is the general tool when in-place is impractical
       (`DetailScene._rebuild_if_bound`, `EquipPickerMenu._rebuild_if_bound`).
    3. **`queue_free` the torn-down subtree** — acceptable when the rebuild itself must be
       synchronous; only the *destruction* defers to idle. `FormationScene.rebuild_cells` does
       this (`remove_child` + `queue_free`), which is why the roster scrub never crashed.

    A guard asserting a scrub's *layout* effect calls the owner's `_flush_pending_rebuild()`
    after the scrub, since production coalesces per frame and the test wants
    one-scrub-per-frame semantics. Static-var-write assertions need no flush — the set is
    synchronous. That seam is what keeps the deferred production path unit-testable.

## Considered options (rejected)

- **Per-field `persist: true/false` declared in code.** Rejected: it forces classifying every
  field as junk-or-keep at authoring time. Runtime pin/commit makes junk simply never get
  pinned. Decision 7's declared classes are the narrow survivor of this — two named
  exceptions, not a per-field burden.
- **A permanent central "bucket" file as the system of record** (the value lives in the file;
  code holds only a seed). Rejected: it *recreates* the opening "multiple versions of truth"
  problem — the registered default becomes a lie the moment the bucket disagrees, code
  literals rot into stale seeds, and the file becomes the god-config bucket. The file is a
  staging layer, drained by decision 8.
- **A single global static-var bucket.** The same rejection under a new name: homes stay
  class-local.
- **Pure inline tweakable-constant macro** (`_TV()` / `inline_tweak`). Rejected: unbuildable
  in Godot — no `__COUNTER__`, no live literal re-parse of compiled GDScript.
- **Typed tuning Resources (`@export`) surfaced via runtime `get_property_list()`
  reflection.** Deferred, not adopted: more sustainable and typed, but research left runtime
  reflection *write-back to the live variable* unverified in Godot 4, and it costs a separate
  declaration away from the use-site. A value can still *graduate* into a typed resource
  later if it earns permanence.
- **Gitignored per-machine staging** (`user://`). Rejected: each checkout would carry its own
  overrides, so consistent behaviour everywhere would force a `materialize` before every
  commit — the exact chore the design avoids.
- **Keeping `of` alongside the split.** Rejected: two ways to register a read-in-place value,
  one materializable and one not, is exactly the ambiguity the split set out to remove.
- **A subscription auto-wired by the registration.** Rejected: it puts a callback back on the
  registration and re-muddies the page's pure-literal surface. The split is the point.
- **Grep-based call-site location.** Rejected: it cannot resolve const-slugs, and finds the
  const declaration rather than the call.
- **Chasing the const declaration when rewriting.** Rejected: a cross-file symbol-resolution
  engine, and `.x`-of-a-`Vector2` has no single literal to hit. Deferred as a possible v2 for
  the plain `const := literal` case; decision 8's one-hop static-var follower is the narrow
  safe subset that decision 14's invariant makes sound.
- **Auto-revert on a failed verify.** Rejected: it discards the evidence of what the tool
  tried to write.
- **Building a categorised generated panel** to replace the removed masonry auto-card.
  Rejected in ADR-0151: it re-adds the surface decision 9 replaced with the Registry page.

## Consequences

- Every scattered `const` and magic number can migrate incrementally. `PSXDisplay.live_par`
  was the pilot — it already *was* a hand-rolled tunable — followed by the `render.*` set
  (`render.unit_mesh_scale`, `render.unit_y_lift`, `render.loc_offset`,
  `render.psx_ot_unit_forward`) end to end.
- **Slugs are stringly-typed** — a typo mints a phantom slug with no compiler help.
  Mitigated by the dotted-namespace convention (`combat.*`, `render.*`) and the Registry
  page; accepted as the standard CVar trade-off. It is also why decision 15's sugar exists.
- The override file is a maintenance surface, but self-draining: `materialize` is the
  pressure valve that keeps it from becoming the feared bucket.
- **A value can be registered and still be dead to scrubbing** (decision 15). That is by
  design, and decision 17's runtime detector is what makes the omission audible rather than
  silent.
- **Perf at scale** — subscription fan-out if a scene registers thousands of slugs — is
  expected negligible and unmeasured. Measure before optimizing.
- **A git-tracked shared-default tier** beyond materialize-to-code, for a value that should
  persist as a *committed override* rather than a baked literal, is not built. `materialize`
  plus `Persist.AUTOSAVE` cover the real need.

## Verification

- `tests/TuneTest.gd` is the core suite — coalescing, the registration/read/subscribe split,
  owner-scoped drop, dirty state, commit, and decision 17's detector (`_test_guard_*`).
  `tests/TuneFieldTest.gd` and `tests/TuneFieldSyncTest.gd` cover the panel-side factory,
  `tests/TuneColorTest.gd` the typed control path, `tests/TunePortTest.gd` the addon façade,
  and `tests/TunablesRegistryModelTest.gd` + `…ViewTest.gd` decision 9's generated page ("one
  row per registered slug"). `tests/PilotStaticInitTest.gd` pins decision 13's boot-time
  registration on the `render.*` pilot.
- `tools/test_materialize_tunables.py` covers decision 8 — the parser, literal formatting,
  the static-var follower, and the skip-and-warn paths — and runs as a pre-flight, cold,
  before any Godot test.
- **Owner-side registration is guarded twice, statically and at runtime:**
  `tools/check_tune_owner_self_registration.py` for the `_static_init` → `register_tunables()`
  shape, and `tests/TuneOwnerSelfRegistrationTest.gd` for the binds actually landing.
- **Decision 12's panel-is-a-view rule** is guarded by `tools/check_debug_panel_tunables.py`,
  which flags a raw value widget in anything that is a debug panel. It scans the walk roots
  rather than a hard-coded directory, so an extracted addon does not silently drop out of
  coverage. It runs in **report mode** — it prints outstanding sites and exits 0 — and
  becomes a hard gate when the tree is clean.
- Roughly forty `*TunablesTest` / `*TuneFieldTest` suites pin one owner's slugs each: that an
  override coalesces at spawn **and** a live scrub re-drives the value. That per-owner pair
  is the shape decision 12 requires, and it is why a fan-out regression fails somewhere
  specific rather than nowhere.

**Named but not built:** three preflight arms decision 17 describes are unwritten — a bound
home that is a `const` with more than one reader, a debug panel that writes game-node state
directly, and "exactly one writer to a static-var home". So is the decision-19 tripwire that
would mark `Tune` as applying and flag any `free()` in that window. They live in the audit
register's `proposed_guard` column rather than here, because this section states what exists.
