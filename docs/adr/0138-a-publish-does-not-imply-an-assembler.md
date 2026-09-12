# A publish does not imply an assembler — `Leaf` is retired

Every crossing is a **publish** or a **port**, and ADR-0118 dec. 3's test
(*does the caller need an answer?*) separates them completely. What varies
inside a publish is only its **binding** — whether the consumer set must stay
open, in which case an assembler wires the sink, or the consumer binds by name
to a stable published surface. `Leaf` was invented to escape an assembler that
"publish" never required.

Status: accepted (2026-08-21). Retires the `Leaf` vocabulary entry added by
[ADR-0200](0200-the-batch-payload-is-deleted-not-designed.md) dec. 8, replacing
its *reason* while keeping its *action*; corrects
[ADR-0118](0118-payloads-are-schemas-services-are-ports.md) dec. 1 and dec. 3;
gives [ADR-0121](0121-systems-land-in-addons-src-only-shrinks.md) dec. 5's
shared kernel its first four concrete members. Resolves
[#333](https://github.com/timbermania/fft-monorepo/issues/333) on blueprint map
[#305](https://github.com/timbermania/fft-monorepo/issues/305).

All figures measured on trunk `1a435a142`, **2026-08-21**.

## Context

[#318](https://github.com/timbermania/fft-monorepo/issues/318) hit the first case
where the map's publish-by-default lost. ADR-0129 dec. 3 had prescribed a publish
for the batch edge — *"`Effects` publishes its batch; the assembler wires the
sink; `Render` never says the word 'effect'"* — and ADR-0137 dec. 8 overturned
the prescription on the grounds that **`Render` is a leaf**: `Fold.gd`,
`FoldSurface.gd` and `DepthMode.gd` name `Effects` zero times, and ten producers
across four systems already call `Fold.add` directly. Making `Effects` the one
producer needing an assembler would be a bespoke mechanism for one caller.

That argument is not specific to the fold, so #333 asked for the general test.
Both of its premises check out: the three files name `Effects` zero times in
code, and `Fold.add` has exactly **10 call sites in 8 files across 4 systems**
(`Effects`, `UI`, `Battlefield`, `Sprite Rig`).

They check out and they are not what did the work.

## The measurement

`tools/.touch_cache.json`, trunk `1a435a142`. Every edge that enters `Render`,
by the symbol it names:

| symbol | edges | from | lines | what it is |
|---|---|---|---|---|
| `DepthMode` | 19 | 6 buckets | 237 | an encoding — static functions and constants |
| `PSXDisplay` | 10 | 5 buckets | 254 | an autoload holding live PAR state |
| `ColorStack` | 9 | 3 buckets | 406 | a value type — CPU side of `psx_color_stack.gdshaderinc` |
| `Fold` | 8 | 4 buckets | 33 | the membership interface (ADR-0129 dec. 4) |
| `ColorRecipe` | 7 | 3 buckets | 210 | a value type |
| `ColorTimelineModel` | 1 | `Effects` | 115 | a debug panel |
| `ShaderCalibrationPanel` | 1 | `assembler` | 29 | a debug panel |
| **`FoldSurface` + `EngineFoldCompositor`** | **0** | — | **471** | **the renderer itself** |

**55 edges, and not one of them reaches `Render`'s runtime.** The two files that
*are* the display-space fold are named by nobody.

And the four files carrying 43 of the 55 edges are depended on **from both
sides**: `FoldSurface` and `EngineFoldCompositor` reach `Fold.FOLD_LAYER` and
`DepthMode.render_layer_order_for` exactly as the ten producers do
(`EngineFoldCompositor.gd:201-202`, `FoldSurface.gd:125/173/200/236`).
`DepthMode.gd:227` says so in its own docstring — *"the ONE home for the
encoding the producers (`Fold.add`, `EngineFoldCompositor`) share."*

Both sides depend on the encoding. Neither side invokes the other. That is the
definition of a publish, not of a call.

## Decision

**1. `Leaf` is retired.** It named a property of the **housing system**
(`Render` names nobody) to license a property of the **thing named** (`Fold` is
a published surface). The two are independent — a system that names nobody can
still expose a live object you must not call, and a system with a dozen outward
edges can still publish a schema you may bind to directly. Only the second
property carries the argument, and it already had a name.

**2. Every crossing is a publish or a port. ADR-0118 dec. 3's test is unchanged
and complete.** *Does the caller need an answer?* Yes → port. No → publish.
There is no third category. `PSXDisplay` is the worked port here: 10 edges that
read `live_par` / `live_ui_par` and subscribe to `*_changed` — a synchronous
answer, so a port, exactly as the existing test says.

**3. What varies inside a publish is the binding, and the test is whether the
consumer set must stay open.**

| the consumer set | binding | worked cases |
|---|---|---|
| must stay **open** — the producer must not know who listens, sinks come and go | **assembler-wired**: producer emits, assembler wires the sink, neither names the other | the effect channels (ADR-0127 dec. 1), the effect log |
| is **closed** — consumers reach a stable published surface | **direct**, by name | `Fold.add`, `DepthMode`, `#include psx_par`, `ColorRecipe` |

A direct binding is not a weaker publish. It is the *default* one: an assembler
is machinery you add when the sink set is open, and adding it to a closed set
buys nothing and costs a wiring step. ADR-0137 dec. 8's action stands on this
reason instead of on `Leaf`.

**4. The escape was never needed, because the vocabulary already said
"publish".** `CONTEXT.md` calls `Fold.add` a **membership interface** — *"what
`Render` publishes so a drawable can join the fold"* — and the shader library
*"the generic `.gdshaderinc` set `Render` publishes and producers `#include`."*
ADR-0129 dec. 4 is titled *"`Render` publishes three things."* All three are
publishes that consumers reach **by name**. #318 read "publish" as "assembler-
wired sink", found that too heavy for one caller, and coined `Leaf` to get out.
The mistake was one word wide: **publish describes the payload's ownership, not
its delivery mechanism.**

**5. `Fold`, `DepthMode`, `ColorStack` and `ColorRecipe` are not `Render`'s.**
They are ADR-0121 dec. 5's shared kernel, which until now had zero named
members. 886 lines, 4 files, 43 of the 55 edges. `Render` keeps `FoldSurface`,
`EngineFoldCompositor`, `PSXDisplay` and its two debug panels — **869 lines**.

> **Extended by [ADR-0139](0139-the-shared-kernel-is-enumerated-by-the-schema-list.md)
> dec. 1 (2026-08-21): the four-file table holds exactly, and the kernel's own
> inbound is 46.** The 43 counted here are the edges from outside `Render` (42
> systems + 1 assembler). Three more are `Render`'s **own** runtime —
> `EngineFoldCompositor` → `DepthMode`, `EngineFoldCompositor` → `Fold`,
> `FoldSurface` → `Fold` — which a frame measuring *inbound to `Render`*
> structurally cannot see. They are this decision's argument in its strongest
> form. Report **46**. Membership also grows by two: the GPU halves,
> `psx_ot_depth.gdshaderinc` and `psx_color_stack.gdshaderinc` (ADR-0139 dec. 7),
> for **6 files / 1,063 lines**.

**6. The colour model is a published schema the list was missing.**
`ColorStack` + `ColorRecipe` (616 lines) are reached by `Battlefield`,
`Cutscene` and `Effects`, and their shader half (`psx_color_stack.gdshaderinc`)
is already in the shader library. ADR-0118 dec. 1 named six schemas and
`CONTEXT.md` lists five; neither includes the colour model, which has more
cross-system edges (16) than any schema on either list. It is the **sixth**.

> **Corrected by [ADR-0139](0139-the-shared-kernel-is-enumerated-by-the-schema-list.md)
> dec. 14 (2026-08-21): it is the seventh.** *"Sixth"* was the right ordinal
> against `CONTEXT.md`'s five-item list and the wrong one against ADR-0118 dec.
> 1's own table, which this decision itself describes as naming six. The two
> lists differ by **tunable declarations**, which ADR-0118 has and `CONTEXT.md`
> dropped — so `CONTEXT.md` held the count at six by coincidence. Seven schemas;
> `CONTEXT.md` corrected in place.

**7. The classifier gets a `schema` bucket, and the reach count FALLS by
bookkeeping alone.** `Render` 1,755 → **869**; new `schema` bucket **886**;
total lines unchanged at 141,837. Cross-system edges **358 → 316**: 42 edges
stop being system↔system and become system→shared-kernel, with **no code
change whatsoever**.

> This is the third instance of ADR-0131 dec. 6's floor being non-monotone
> (after #324's facade and #318's declared crossing) and the **first downward**
> one. The earlier two warned that a *rising* count can mean an improving
> boundary. The mirror is worse: a **falling** count can mean nothing happened.
> Pass 6 must read the baseline from a stated commit *and* a stated classifier
> revision.

**8. #306's "extraction order is free" is confirmed, and its freedom is
conditional.** #306 concluded order is free because systems depend on published
schemas and ports rather than on each other. `Render`'s row is now the proof:
43 schema + 10 port + 2 debug + **0** system calls. But the freedom holds *only
if the shared kernel is extracted first* — bind `Effects` to `Fold` while
`Fold` still lives inside a `Render` addon and seven systems hard-depend on
`Render`, which must then go first. ADR-0121 dec. 5 already requires the kernel
be *"built before any extraction"*; this makes the requirement load-bearing
rather than tidy. It has no owner and no place in the order — filed as
[#334](https://github.com/timbermania/fft-monorepo/issues/334).

**9. Audit of the three publish-leaning ADRs against dec. 3's test.**

| decision | consumer set | binding it should have | verdict |
|---|---|---|---|
| ADR-0118 dec. 1 — effect channels | open (*"whoever subscribes"*) | assembler-wired | **stands** |
| ADR-0118 dec. 1 — effect log | open (replay, save, presentation) | assembler-wired | **stands** |
| ADR-0118 dec. 1 — compositing key | closed (fold producers) | direct | **stands**, direction wrong — see dec. 10 |
| ADR-0118 dec. 1 — pose requests | closed (`Body` → `Sprite Rig`, one consumer) | direct | **re-opened** — declared a publish, never tested for an open sink |
| ADR-0118 dec. 1 — character records | closed (`Character Catalogue` → `Deployment`) | direct | **re-opened**, same reason |
| ADR-0127 dec. 1 — everything leaving `Effects` | open | assembler-wired | **stands** |
| ADR-0129 dec. 3 — the batch | n/a | n/a | already overturned by ADR-0137 |

Two of the six schemas were declared publishes on the strength of *"a payload
crosses a boundary"* alone, with no consumer-set test — because no such test
existed until now. Neither is re-decided here; both are noted as untested.

**10. ADR-0118 dec. 1 has the compositing key's direction wrong.** It books it
*"every drawable emitter, to `Render`"*. Nothing goes to `Render`: `Fold.add`
stamps `material_override`, `render_layer` and `render_layer_order` onto the
caller's own `GeometryInstance3D`, and the **engine** collects every instance
carrying a valid `render_layer`. The producer and the renderer meet in the
engine's held-out pass, not across an edge. The correct statement is *"every
drawable emitter and `Render`, on a shared encoding."*

**11. Neither the shader library nor the membership interface changes.** Both
were already publishes with direct bindings and both were already right; dec. 3
just says why. `Fold.add` stays the sole sanctioned entry (`CONTEXT.md` →
*Membership interface*).

## Considered alternatives

- **Keep `Leaf` and narrow it to "the leaf is an encoding."** Rejected: that is
  a property of the encoding, so naming the housing system in the test is pure
  indirection. It also keeps 886 lines of shared kernel booked to `Render`,
  which is the thing that makes extraction order *look* free while it is not.
- **Call the direct binding a third category beside publish and port.**
  Rejected: it fails the first test you would apply to it. `DepthMode` is
  reached by six buckets and `PSXDisplay` by five; the difference between them
  is whether the caller needs an answer, which is dec. 3's existing test doing
  its existing job. A third category would only re-encode delivery mechanism as
  ownership, which is exactly #318's error.
- **Change nothing and let each extraction decide.** Rejected: #318 already
  showed a session reaching for a bespoke word under time pressure, and the map
  has at least the shader library, `DepthMode`, `ColorStack`/`ColorRecipe` and
  the six ADR-0121 schemas in the same shape.
- **Move `PSXDisplay` to the shared kernel too.** Rejected: it is a port, and
  ADR-0121 dec. 5 is explicit that ports are not in the kernel — a port is
  declared by the system that requires it.

## Consequences

- **`Fold.add` is not a pure encoding, and that is the honest soft spot.** It
  writes `material_override` — a decision that override, not surface material,
  is the mechanism — and it hands out `FOLD_LAYER`, a shared *resource
  instance* whose ObjectID identity is load-bearing (one resource → one
  partition → the engine's one-partition fast path). So it is a codec **plus a
  singleton**, and calling it a schema is generous by exactly that much. The
  defence is that the singleton is what the schema *is* — "which held-out layer"
  is a field of the compositing key whose domain happens to have one member
  (ADR-0129 dec. 5-6: `layer` is *"currently degenerate: exactly one
  `FOLD_LAYER`, deliberately"*).
- **A shared kernel renames the coupling, it does not delete it.** `Effects`
  depending on `Fold` is the same edge whether `Fold.gd` sits in `render/` or in
  the kernel. What it buys is that `Render` can extract without `Effects` and
  that the dependency is declared against a format rather than a renderer —
  not a smaller number. See dec. 7.
- **The kernel is now the schedule's critical path.** Nothing can extract before
  it, and it has no owner. #334.
- **`Render` is 869 lines, and the shader question still dwarfs that.** The
  baseline omits 4,304 lines of `.gdshader` (map #305 fog); at 869 lines
  `Render` is now *more* sensitive to how that splits, not less.
