# A boundary is named only when the crossing has a payload, an owner, and an edge

Naming *what crosses* a seam is not enough. A crossing is resolved only when all
three are stated: **what passes**, **who holds it afterwards**, and **the single
edge where it changes hands.** Two of three is a boundary-shaped gap that will be
patched twice before anyone finds it.

Status: accepted (2026-08-20).

## Context

[#306](https://github.com/timbermania/fft-monorepo/issues/306)'s stated bar was
*"a boundary is resolved only when you can name what crosses it."* That bar is
insufficient, and the counter-example is in this repo.

[ADR-0020](0020-unit-animation-uses-one-clock-per-unit.md) **did** name what
crossed — "one clock per unit." It did not name which host pumps it. Two systems
then advanced the same `Unit` nodes, every combat body ran ~2x/frame, and two
bugs were patched separately before the real defect surfaced.
[ADR-0083](0083-a-units-animation-clock-has-exactly-one-owner.md) closed it by
supplying the two missing parts.

|  | ADR-0020 | ADR-0083 |
|---|---|---|
| **Payload** | the animation clock | the animation clock |
| **Owner** | *unstated* | `SELF` / `SCENARIO` / `COMBAT` |
| **Edge** | *unstated* | `_go_live` |

## Decision

**1. Payload, owner, edge — all three, or the boundary is not named.**

**2. Find crossings mechanically, not by inspiration.** For each thing a system
owns, list who touches it and in which direction the dependency runs. Any
direction running *uphill* — a system that ships early depending on one that
ships late — is a defect that resolves to an inversion or to a change in ship
order. Authoring #306 by inspiration missed `Render`, the map split, and every
port; enumeration finds them.

**3. Pick the cheapest integration that makes the direction legal.**

| Shape | Cost | Use when |
|---|---|---|
| Query | free — typed, greppable | consumer is above the owner, needs an answer |
| Command | free | consumer is above the owner, changes state |
| Capability | small | exactly one holder at a time |
| Event / subscribe | **loses the call graph** | the call would run uphill and must be inverted |
| Published language | a schema to version | many consumers, and the owner must know none of them |

**Events are the expensive shape and should be rare.** They buy a dependency
inversion and cost the ability to grep for who handles something.

**4. A crossing that fails by silent disagreement belongs inside one system; a
crossing that fails visibly may span two.** This decides packaging and overrides
tidiness. Picking a cell with a different projection than the one used to render
it puts the cursor on the wrong tile, subtly, at some heights only — so camera,
cursor and lattice ship together. Drawing a body facing the wrong way is
maximally visible, so the camera quadrant crosses a seam freely.

## Considered alternatives

- **Name the payload only** (#306's stated bar). Rejected on ADR-0020's evidence.
- **Publish everything as events, for uniformity.** Rejected: decoupling nobody
  needs, bought with an invisible call graph. `Effects` inverts because its calls
  run uphill; the character catalogue does not, because they do not.
- **A shared skip-set or membership test** instead of a named owner. Rejected by
  ADR-0083 already: ownership lives in a test one system must reach into another
  to perform, and is re-answered every frame instead of at the handoff.

## Consequences

- Every crossing in [ADR-0117](0117-the-blueprints-ten-systems.md) states all
  three parts, and the ones that could not are recorded as strains.
- The rule is checkable in review: an ADR proposing a boundary without an owner
  and an edge is incomplete on its face.
- **Two of three is the dangerous state**, not zero of three. A crossing with a
  named payload looks resolved, which is why ADR-0020 stood for so long.
