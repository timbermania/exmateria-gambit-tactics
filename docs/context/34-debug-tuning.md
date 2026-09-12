# Debug tuning

How a live-adjustable value gets from a code use-site into the debug dashboard
and back, without scattering copies or a god-config bucket. Generalizes the
one-off `PSXDisplay.live_par` slot+setter+signal. See ADR-0068.

**Tunable**:
A code value that is bound to a [slug](04-character-catalog.md) and adjustable live
in the debug dashboard. Its resting home is the **code default** — a literal in a
**static-var home**; a committed **override** may layer over it. Realized by
`Tune.bind` (attach the literal), then the value reaches game state by **`get_value`**
(a synchronous pull-read) or **`on_update`** (a push subscription that makes a scrub
reach a passive consumer). _Avoid_: cvar (borrowed engine jargon), setting (too broad
— that includes window geometry), debug flag (that is only the boolean subset).

**Code default**:
The literal a slug is bound to — the **`static var` initializer** at the value's
one home (or, for a co-located single-consumer value, the literal inline in the
`Tune.bind(slug, <literal>)` call). The **resting source of truth** and the single
place `materialize` rewrites. One slug ↔ one literal. Contrast the retired
anti-pattern of a mirrored `const PSX_UNIT_MESH_SCALE := 8.0` copied from
`Unit.tscn`.

**Static-var home** (ADR-0068 R1–R8):
The mutable, class-scoped `static var` that holds a tunable's live value, in the
class that owns it — a scrubbable "debug const" is a `static var`, never a `const`
(frozen at parse time, unscrubabble) and never a central bucket (class-local, not
global). Direct readers read it natively, so a scrub reaches them *structurally*
(one storage slot) with no per-read-site wiring. `PSXDisplay.live_par` generalized:
the `static var` is the slot, an `on_update` is its setter, `value_changed` its signal.

**Override**:
A committed value in the staging file that **coalesces over** the code default
at runtime (`override_in_memory ?? code_default`) — the same `instance =
template + diff` shape as the character catalog (ADR-0066), the default being
the template. Absent for most slugs most of the time.
_Avoid_: setting, saved value (say override — it names the layering).

**Override file** (a.k.a. the *staging layer*):
The sparse file (a `res://` config path, *not* Godot `user://`) mapping committed
`slug → value`, loaded into memory by the `Tune` autoload in `_ready()` — *before*
the scene tree, so every `bind`/`get_value` sees its override immediately. A
**staging area, not a system of record**: only committed slugs appear, and it is
meant to be *drained* by `materialize`.
⚠️ It was git-tracked until `90e593900` and is now **machine state** (below), so
"versioned, reviewable, portable across worktrees" — the original argument for
tracking it — no longer holds. Every boot rewrote it, which blocked three
consecutive pulls on the asset hub.
_Avoid_: config bucket, god-config, the "S3 bucket" (tracked or not, it is NOT
the permanent home — that framing reintroduces multiple-versions-of-truth).

**Machine state** (godot-learning ADR-0281):
State that belongs to **one developer on one box** rather than to the tree — the
override file is the case that named it: untracked, gitignored, read at boot by
every Godot process, and therefore a silent input to every test. The rule is that a
**test process may not touch it in either direction**, so `Tune`'s staging path is
*empty* in a test and empty means *there is no file* (a commit still succeeds and
still advances the in-memory baseline; nothing reaches disk). The complement is
that a **run** may not change it either — `tools/machine_state_sentinel.py` digests
bytes-or-absence before and after and reports what moved.
⚠️ **Compare, never assert absence.** A developer with pins dialed in has the file
legitimately; the thing forbidden is the *change*, not the existence.
_Avoid_: "local state" (true but says nothing about who may write it), "dev
config" (that is what the override file IS; this names its *scope*).

**Commit** (of a tunable; a.k.a. *Save*):
The explicit gesture that writes a slug's current live value into the override
file. Nothing persists without it — persistence is a runtime click, never a
per-field `persist:` flag in code. Distinct from a git commit.

**Dirty** (tunable):
A slug whose live value differs from its committed override — dialed past the
saved baseline, not yet re-committed. Shown in the dashboard so the divergence
is visible. Borrowed from the `{66}` "ramp mid-flight, not yet committed" model.

**`Tune.bind(slug, literal)`** (ADR-0068 R1–R8):
Attach a slug to exactly one **literal** — and nothing else. The registry entry
and the emitter; pure (no callback, no owner). The *only* thing the dashboard and
`materialize` enumerate ("from a panel perspective, all we care about is the
bindings of literals"). A `bind` alone is **inert to scrubbing** — it makes a
value enumerable and materializable, but a scrub reaches game state only once a
consumer reads it (a `get_value` re-read) or is pushed it (a matching `on_update`).
_Retired_: `Tune.of(default, slug)` — its use-site literal is what forced
materialize to chase wrappers/consts; the literal now lives in a static-var home,
and its read role passes to `get_value`.

**Pull vs push** (how a bound value reaches game state):
The same coalesced value (`override ?? code default`) travels registry → code two
ways, differing only in **who initiates**. **Pull** = the consumer calls the
registry when it wants the value (`get_value`) — for consumers that re-read on their
own. **Push** = the registry calls the consumer's callback when the value changes
(`on_update`) — for passive consumers that will not re-read. Pick by one test: *when
the value changes, will this consumer re-read on its own, or must it be poked?*
Re-reads itself → pull; must be poked → push.

**`Tune.get_value(slug)`** (ADR-0068 R5 — the pull-read):
The synchronous read of a slug's coalesced value for a consumer that re-reads on its
own — a computed `get:` property, a `_process` read, a one-shot `_ready` read. Cheap:
**no use-site capture, no registration** (that per-call cost is `bind`'s alone), so it
is safe in a hot getter — the property `of` had on repeat, unbundled from `of`'s
register job. Asserts a prior `bind` (a read before its default is declared is a wiring
bug, not a silent null). The direct successor to `Tune.of`'s *read* half.

**`Tune.on_update(owner, slug, apply)`** (ADR-0068 R3 — the push):
Subscribe to a slug's changes and **re-run the path into consumed game state** —
the `static var` write-back (`func(v): Owner.some_var = v`) that lands a scrub on
direct readers, and a *re-derivation* for any consumer that cached a derived value
(redoes the `* 2` so a stale cache refreshes). `owner`-scoped: auto-drops on tree
exit (Ctrl+R-safe — the "local" that the old `bind_local` name misplaced). The `on_`
prefix marks it an event hook (handler runs ON each change), not an imperative "update
now". Added **as-needed for debugging**, when a *passive* consumer must respond to a
scrub. _Rule (derivation-cache invariant)_: an `on_update` is required at every point the
path from tuned base to consumed value is **cached rather than re-evaluated**;
read-in-place (`get_value`) needs none only when every derivation is re-evaluated at
read time. Each cached consumer owns *one* end-to-end on_update — never a graph of them.

**`Tune.bind_update(owner, slug, literal, apply)`** (ADR-0068 R1–R8):
Sugar = `bind` + one paired `on_update`, for the co-located single set-once consumer
(the `mesh.scale = v` shape: an inline literal, no other readers, one on_update that
pairs 1:1 with the bind). States the slug **once** — the payoff is not the saved
line but killing the repeated slug string (the phantom-slug typo footgun). The
successor to the old 4-arg `bind`. Still enumerated as a `bind` and materializable
per M5, *provided the literal is inline, never forwarded through a wrapper*.
_Use_: when one on_update pairs with the bind and the literal is inline. _Not_: when
the literal is a `static-var home` (direct readers) — use `bind` + a write-back
`on_update` there.

**Derive, don't duplicate** (ADR-0068 R7):
The convention that keeps a scrub reaching every consumer: a tunable's value reaches
consumption via a **computed getter / recompute-at-use** (cheap derivations, read via
`get_value`) or an **`on_update`** (a forced, expensive set-once cache like a GPU upload) — **never a
stored `var := f(tunable)`** (a snapshot that goes stale after a scrub — the R4
cached-derivation trap). Godot-native via `var x: get:` computed properties. Shrinks
the un-detectable staleness residual to the irreducible forced-cache core and makes
what's left lint-able (a stored derivation of a known tunable home symbol).
_Avoid_: caching a derived tunable value in a plain field "for performance" when the
derivation is cheap — that reintroduces multiple-versions-of-truth.

**Materialize**:
The codemod that bakes chosen overrides into their **one bound literal** *by slug*
— the `static var` initializer (followed one safe hop from the `bind` call, safe
*because* one slug ↔ one static var) or an inline `Tune.bind(slug, <literal>)` — and
clears them from the override file, a reviewable git diff. "Promote to the real game
value": code reabsorbs the override and becomes the single truth again; the staging
file drains back toward empty.
_Avoid_: promote (reserve for a possible future git-tracked override tier),
export, bake (fine informally, but materialize is the term).

**Panel applicability** (ADR-0263):
Whether the knobs a mounted debug panel shows actually reach anything **on the
screen you are looking at**. The question is asked per **slug**, never per panel:
a panel is a bag of rows whose owners differ, so `FormationScene` can mount one
panel whose slugs are live beside another whose owner is ephemeral. A panel's
status is *derived* — the counts of its rows' states. _Avoid_: "is this panel
relevant here", which invites a per-panel yes/no the evidence cannot support.

**Bindable**:
Whether a host can **construct** a panel at all — it supplies the subject the
panel's `setup()` genuinely reads. Crash-prevention only, and explicitly **not**
evidence of applicability in either direction: four panels take a subject and
ignore it (`CursorDebugPanel.setup(_rig)`), while `TilesDebugPanel.setup()` takes
nothing and is a pure view onto the battlefield addon's `tile.*`. _Avoid_: treating
the `setup()` signature as a statement about scope.

**Declared** vs **consumed** vs **not booted** (`Tune.Consumer`):
The three states applicability is read in, and only the outer two are claims.
**Not booted** = no `bind` for the slug has run in this process; its owner's class
never loaded. **Consumed** = something was *seen* to read it — a non-view push
subscriber, or at least one `get_value`. **Declared** = bound, with nothing observed
consuming it, which is the **absence of evidence and not evidence of absence**: a
pull consumer that reads once at build time is indistinguishable from a dead knob.
_Avoid_: calling the declared state "dead" or "inactive" — that converts a
not-looking into a verdict.

**View subscription** (`as_view`):
An `on_update` that exists only to **repaint a debug control**, declared as such so
the applicability read can discount it. It matters because `TuneField.build_control`
subscribes every row it renders: without the flag, any slug with a visible control
certifies itself as consumed, and the whole signal reads "live" everywhere. `peek`
is the pull-side twin — the coalesced read that deliberately does **not** stamp the
R8 pull clock, so a view painting itself is not mistaken for a consumer.

**Scoped slug**:
A slug that is live on **more than one screen at once**, so tuning it where you can
see it also retunes where you cannot. `vitals.*` is the worked case — shared between
the formation screen and the battle HUD, which is why `FormationScene` bakes
formation-only values in code rather than committing the slug. Orthogonal to
applicability: the panel is applicable, the rows are consumed, and the knob is still
a footgun.
