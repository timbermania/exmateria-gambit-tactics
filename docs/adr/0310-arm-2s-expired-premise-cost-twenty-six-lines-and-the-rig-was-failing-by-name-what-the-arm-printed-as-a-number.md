# ADR-0310 — arm 2's expired premise cost twenty-six lines, and the rig was failing BY NAME what the arm printed as a NUMBER

- **Status:** accepted
- **Date:** 2026-09-12
- **Ticket:** #1225 (extraction #7, the install axis)
- **Grills:** ADR-0238's "arm 2's register is already empty", ADR-0229 dec. 7
- **Constrains:** ADR-0194 dec. 12, ADR-0238 dec. 3, ADR-0262 dec. 6, ADR-0308

`check_addon_portability.py` arm 2 asks one question — *does a file inside an addon name
an identifier only the host's `[autoload]` block declares?* — and it had **two verdicts
for it.** An addon with its own `project.godot` was RED. An in-walk addon with none was a
printed `standalone-parse DEBT` block under this heading:

> Not enforced (there is no standalone project to parse against yet); it is what the next
> extraction has to answer.

That premise was false, and had been ruled false. This ADR records what the second verdict
cost between the ruling and the removal, and why the removal is now free.

## 1. The premise was already ruled expired, by an ADR that declined to act on it

ADR-0238 examined exactly this heading and wrote:

> Its premise — *"there is no standalone project to parse against yet"* — is expired in the
> same way arm 4's is, but converting it enforces nothing that is not already at zero.

So the argument was settled and the action was declined **on value, not on merit** — #848
had discharged the last row, the block was behind an `if debt:` and printed nothing, and a
guard flipped over an empty register enforces nothing.

ADR-0229 dec. 7 had reached the same place one pass earlier from the other direction:

> The arm is not changed. It is right that it cannot parse a project that does not exist;
> what was missing was the project.

Correct when written — the sprite rig was the FIFTH rig and the corpus was mid-build. There
are now **eight, one per in-walk addon**, every one declaring an empty `[autoload]` block on
purpose (ADR-0308 §1). The project is no longer missing for any subject the DEBT branch
covered, so the set that branch existed for and the set with a rig to fail against are the
same set. Neither prior ruling is reversed here; both are spent.

## 2. What the interval cost, which is the finding

Extraction #7 moved `Effects` in at #1225 and **refilled the register to 26 lines** — the
one thing ADR-0238's "already at zero" could not price. Measured on this branch's base
commit:

| identifier | lines | members | the script the autoload points at |
|---|---:|---|---|
| `ExMateriaEffectSfx` | 11 | `cast/EffectInstance.gd` | `addons/exmateria_sound/runtime/effect_sfx_engine.gd` |
| `TintedSurfaces` | 11 | `EffectInstance`, `PaletteSubsystem`, `TrapPaletteController` | `addons/exmateria_effects/overlay/TintedSurfaces.gd` |
| `ScreenEffectOverlay` | 4 | `EffectInstance`, `ScreenSubsystem` | `addons/exmateria_effects/overlay/ScreenEffectOverlay.gd` |
| **total** | **26** | **5 of 67** | |

All 26 were in one addon, and they were **the whole of arm 2's debt in the corpus**. They
were also that addon's last install blocker: three of the five rows in
`tests/stranger/exmateria_effects/known_failures.tsv` were three of those five files.

**So two instruments were watching one defect and only the slow one was scoring it.** The
rig failed those three files by name, with the engine's own parse error as the signature,
on every run. Arm 2 printed the same three files as an unenforced count under a heading
saying no project existed to fail against — while the project that was failing them shipped
in the same repository and ran in the same pre-flight. That is the state ADR-0194 dec. 12
forbids in the other direction: a rig's silence is not a measurement. An arm's *number* is
not one either, when a rig is already producing the verdict.

## 3. Why flipping it is free now, and was not before

The 26 are paid (#1225, this branch), so the corpus count is **0** and enforcement changes
no verdict today. That is the same condition ADR-0238 read as a reason NOT to flip, and the
difference is the interval above: at zero-and-never-refilled, flipping is decoration; at
zero-after-refilling-once, flipping is what stops the next extraction repeating the interval.
An extraction lands a system's files into an addon root all at once, so this register's
natural state is not "empty" — it is "empty between extractions."

How the 26 were paid is not uniform, and the split is arm 2b's own rule rather than a
preference. Arm 2b's remedy note states it:

> the node path is free on two grounds and neither is 'it compiles': the autoload points at
> a script THIS addon ships, or the addon is the kernel or the platform port. A SYSTEM
> naming a script it does not ship has swapped a parse error for a silent null, which is a
> worse report of the same dependency.

`TintedSurfaces` and `ScreenEffectOverlay` point at scripts `exmateria_effects` ships, so 15
lines went to two in-addon ports (`install/TintedSurfacesPort.gd`,
`install/ScreenOverlayPort.gd`) — ADR-0308 dec. 6's shape, *"the script travels with the
addon and the registration does not."* `ExMateriaEffectSfx` points into
`addons/exmateria_sound/`, which `Effects` does not ship, so its 11 went to a port-tier
signature, `ExMateriaPlatform.SfxPort` (ADR-0175 dec. 2). The dependency did not shrink in
either case; what changed is which arm can enforce it — arm 2 fell 26 → 0 and arm 5's
counted cross-addon census rose 517 → 529.

## 4. The three rows said they were unpayable, and that is the reusable lesson

Each of the three own-autoload `known_failures.tsv` rows carried this in its `why` column:

> the two routes out are for a consumer to declare the line or to enable `plugin.gd`, and
> both are the CONSUMER's act, not this addon's.

Both named routes really are the consumer's. The rows missed a third that was entirely the
addon's — **stop naming the bare identifier** — and the rig printed that route, in the same
file, a few lines further down: *"The sibling autoload reaches that DO survive here are the
ones spelled as node paths."* The answer and the denial sat one column apart for the whole
life of the row, through two re-tickets (`#1223`, then `#1224`), neither of which could pay
it because neither was about whether ANY identifier existed in a project that declared none.

A `why` column is unverifiable prose by construction — the rig checks the PATH and the
SIGNATURE — and *"nothing can pay this"* is the single claim in a burn-down row most worth
re-deriving before believing, because a row asserting it is unpayable is a row nobody tries
to pay.

## 5. The instrument keeps four directions, not one

Arm 2 becomes `ARM2_BURN_DOWN`, arms 1/6/7's shape: a named list, never a pattern (#424).
Four ways it can rot, and each has a seeded test:

1. an **unlisted** reach — the ordinary regression;
2. a **listed** reach — excused, printed with its owner, goal #5 unmet on record;
3. a listed reach that **no longer happens** — STALE and red, the arm ADR-0308 dec. 5 names
   as the one a one-armed ratchet misses, because a baseline outliving its debt re-admits
   the reach under a green suite;
4. the **subject is empty** — new here, and it is every arm's rather than arm 2's.

Direction 4 is worth its own note. **All twelve** arms in that file — 1, 2, 2b, 3, 4, 4b, 4c,
5, 6, 7, 8, 8b, counted with `grep -oE '^\s*# --- arm [0-9a-z]+'` rather than from memory —
are "nothing found" over `scanned`, so a subject that went empty prints a clean bill over
nothing. That is the ADR-0148 stale-root defect the module's own header describes and which,
until now, it described rather than checked. The guard's own message states no count, because
an arm count in a guard's output is a number nothing updates when arm 9 lands; this ADR states
it and says how it was measured.

The flip was proved by seeding the old branch back: with it, a scratch in-walk-shaped addon
naming the real `Tune` autoload printed **`addon portability OK`** and exited 0. That is the
hole, in the arm's own words, and two of the six new tests red on it.

## Decisions

**1. Arm 2 is ENFORCING for every subject, with `ARM2_BURN_DOWN` carrying named exceptions.**
The `own is not None` split that sent in-walk addons to an unenforced print is deleted, not
annotated. ADR-0238 already ruled the premise expired and declined only because the register
was at zero; it refilled to 26 at extraction #7 and is at 0 again. Argued in §1, §3.

**2. An unenforced heading whose subject a DIFFERENT instrument already fails is a defect,
not an IOU.** The rig named three files and arm 2 printed a number for the same three, under
a heading saying no project existed to fail against. When two instruments watch one defect,
the weaker one's silence is not caution — ADR-0194 dec. 12's rule, applied to an arm instead
of a rig. Argued in §2.

**3. This register's natural state is "empty BETWEEN extractions", so zero is not evidence it
can stay unenforced.** An extraction lands a whole system's files at once. Read a zero here
as a window, not as a finish. Argued in §3.

**4. "Nothing can pay this" is the burn-down claim most worth re-deriving.** Three rows
asserted it, named two real-but-consumer-side routes, and missed a third the rig printed in
the same file. A `why` column is unverifiable by construction, so an unpayability claim gets
re-measured rather than inherited. Argued in §4.

**5. The empty-subject arm belongs to the whole guard, not to arm 2.** Every arm is a
"nothing found" over `scanned`; an empty subject makes all of them vacuously green. Argued
in §5.

## Alternatives rejected

**Leave arm 2 reporting and let the rig be the enforcement.** This is the status quo and it
is what cost §2's interval. The rig is a per-file compile witness that costs a staged project
and a Godot boot; arm 2 is a static scan that runs in the pre-flight. They are not
substitutes — the rig cannot see a load-time reach and the arm cannot see a cascade — and
the argument for keeping the cheap one unenforced was never that the expensive one covered
it, it was a premise about standalone projects that ADR-0238 retired.

**Flip arm 4 in the same pass.** Refused, and the reason is not symmetry-breaking: ADR-0238
dec. 3 keeps arm 4 reporting on a premise that is still TRUE. A missing `global uniform` is
not a compile error outside the editor (validation is gated on `Engine::is_editor_hint()`),
so no rig can fail against it and no compile-based check can see it. Arm 2's premise expired;
arm 4's did not. Flipping both because they share a heading style would be the mistake
ADR-0238 was written to prevent.

**Build a `check_effects_autoload_reach.py` ratchet beside the rig and arm 2, mirroring
`check_ui_autoload_reach.py`.** This was the suggested route and it is the wrong shape here.
UI needed its own file because `src/ui3/` is not an addon and has no rig; `exmateria_effects`
has both a rig and an arm already measuring this. A third instrument would make it three
registers for one defect, which is the ad-hoc-gate accumulation ADR-0308 dec. 4 names —
*"the defect is not that `DisplayPort` is short, it is that six identifiers cross a boundary
that admits none, and the fix is one enumeration plus one instrument, not six tickets
discovered six passes apart."* Enforcing the arm that already measures it is that one
instrument.

**Add a node-path bind for `ExMateriaEffectSfx` too, and skip the port.** It would have
compiled, drained the same count, and been the cheaper diff. Arm 2b refuses it by ownership
rather than by compilability, and the refusal is right: `Effects` does not ship
`effect_sfx_engine.gd`, so a node path there reports the dependency more quietly than a
parse error does while leaving it exactly as large.
