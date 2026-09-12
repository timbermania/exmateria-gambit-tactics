# Every system pass audits before it designs

Loop pass 3 gains an **audit step** that runs before the seam is designed: six
checks, each generalised from a finding that cost a whole session to make once.
Without it every system re-derives them, and the blueprint's per-system claims
get inherited as fact rather than tested.

Status: accepted (2026-08-20).

## Context

#307 produced two different kinds of output, and only one of them is about
`Effects`.

**System-specific answers** — the ten lanes, the landmark event table, the FEDS
boundary, dropping `600` / `max_keyframe` / keyframe slot 0. These are one
system's decisions and do not transfer.

**General rules found *through* `Effects` but not about it** — and these are
currently recorded inside
[ADR-0122](0122-an-effect-lane-is-a-track-of-non-overlapping-typed-events.md),
an `Effects` ADR. That is the wrong home for a rule that applies to every system,
and it guarantees rediscovery: the next pass has no reason to read another
system's lane model.

**Pass 3 has no audit step.** `refactor-loop.md` says *"design the seam — and
predict the metric on it."* Both are forward-looking. Nothing asks what the
system touches **today**, and pass 2's scoping is a closure from the root set,
not a crossing inventory. So a pass can design a seam without ever establishing
where the current ones are.

**The blueprint's per-system claims are assertions, and at least one is false.**
It says of `Effects`: *"The effect never learns what a combatant is."* It does —
`PaletteSubsystem` holds `WeakRef`s to caster and target `Unit` nodes and calls
`get_instance_id()`. The same sentence is written about `Sprite Rig` (*"It does
not know what a combatant is"*) and has never been tested. A claim inherited as
fact is worse than no claim, because it suppresses the check.

## Decision

**Pass 3 runs an audit before the seam is designed.** Six checks. Each is cheap,
each has a worked example from #307, and each exists because getting it wrong
cost real time.

**1. Run `tools/touch_matrix.py`, scoped to the system.** It reuses
`classify_blueprint.py`'s rules and reports cross-system edges by *shape*:
`class_name`, `autoload`, `preload`, `/root/` reach. None of those is an
interface, which is the point — an injected port appears as none of them.
Measured at the time of writing: **358 cross-system edges, zero ports, and 17 of
55 system pairs mutually dependent.**

**Read it as a floor, never a census.** It over-reports if comments are not
stripped (the first run scored 672 — **47% was prose**, because this repo
documents heavily by policy) and it under-reports duck-typed reaches, which carry
no type name. `PaletteSubsystem`'s `WeakRef` to a `Unit` is a real `Battle`
coupling the scan cannot see. **A clean column is not proof of a clean
boundary.**

**2. Test the blueprint's claim about this system; do not inherit it.** Every
system entry in `BLUEPRINT.md` asserts what it owns and what it stays ignorant
of. Treat each as a hypothesis with a named falsifier. When one fails, **record
it in `BLUEPRINT.md` rather than quietly rewriting** — the `BLUEPRINT-AUDIT.md`
precedent — so nobody cites it while the fix is pending.

**3. Look for the muxed slot, and for the demux that already exists.** A storage
field carrying several unrelated things is the recurring shape, and the tell is
that the runtime below *and* the authoring above have already separated them by
hand. In `Effects` it appeared **six times**: `action_flags`, `channel_mask`,
`ctrl` bit 7, keyframe slot 0, `time_value`, `max_keyframe`. `CameraLowering`
had already lowered the camera mask into the three lanes and called them *"the
authoring lanes and the runtime's own search grain"* — the design work was done,
just not in the storage. **Find the existing demux before proposing one.**

**4. Check the units on every typed payload.** For a typed payload, units are
part of the published shape: a *camera* vocabulary (degrees, tiles, ortho size)
is satisfiable by a stranger; a *PSX* vocabulary (4096 = a full turn, 28 units
per tile) is content wearing an interface's clothes.
[ADR-0091](0091-psx-magnitudes-convert-to-game-units-at-a-single-per-subsystem-seam.md)
carves out faithful ROM per-frame arithmetic, and that carve-out is legitimate —
but **its internals must not be the interface**. `CameraSubsystem` publishes raw
PSX fixed-point through mutable public fields that the consumer both reads and
writes, in both directions.

**5. Count the spellings of each contested resource.** When several systems write
one resource, they should write it through **one** interface. `Effects`,
`Cutscene`, `Battlefield` and `Unit` all push layered colour, through **three**
overlays with three different keys, three different remove verbs and no shared
base class. Three adapters make it a real seam
([`/codebase-design`](../../.claude/skills/codebase-design/SKILL.md)); three
*interfaces* make it three accidents. Distinct from
[ADR-0119](0119-contested-resources-are-capabilities-not-flags.md), which governs
single-holder capabilities — this is the layered case.

**6. Measure against the corpus, not the model.** Every substantive correction in
#307 came from data, and three claims died to it mid-session: the camera mux
quoted at 7.8% against a denominator full of inert slots (37.4% against live
ones), `0x6E6E` read past `max_keyframe` and reported as a duration, and disabled
palette keyframes counted as live. **Before quoting a number, establish what the
live set is** — nearly every ROM structure here is preallocated, so the array is
mostly dead slots.

## Consequences

**This amends the loop, which map #305 rules out of scope.** That exclusion
exists to stop the loop being re-planned; this adds one step to one pass, from
evidence the loop did not have when it was written. It is an amendment, not a
re-plan.

**Pass 3's `/improve-codebase-architecture` demotion still stands.** That skill
surveys for *candidates*; this audit establishes *facts* about crossings that
already exist. The metric does the candidate job, per the existing note.

**The audit feeds pass 4.** Pass 4 emits the system's ADRs and `CONTEXT.md`
terms, and `/code-review`'s Spec axis reads them. A falsified blueprint claim
found at pass 3 is a pass 4 ADR, not a loose note.

**`Sprite Rig` is the first live test.** It is the largest cycle in the codebase
(`Battle` <-> `Sprite Rig`, 25/8 by the code-only count), and it carries the same
untested "knows nothing about combatants" claim that turned out false for
`Effects`. If the audit is worth anything it will show there.
