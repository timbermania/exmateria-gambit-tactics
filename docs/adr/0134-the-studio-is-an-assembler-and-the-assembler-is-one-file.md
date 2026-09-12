# The Effect Studio is an assembler, and the assembler is one file

The category was already decided in three places. What was never decided is how
much an assembler may weigh: `classify_blueprint.py` books **21,986 lines** of
`src/effects/studio/` as assembler — **3.2× all sixteen other assemblers put
together**. The assembler is `EffectViewerScene.gd` and only that. The rest is
`Effects`, which grows **16,176 -> 38,162** lines.

Status: accepted (2026-08-20).

## Context

[#324](https://github.com/timbermania/fft-monorepo/issues/324) was filed on a
verbatim contradiction: `BLUEPRINT.md` §"Not decided" asks *"Ninth system, or
host? Open"* while `CONTEXT.md` -> **Structural vocabulary** already answers
*"the Effect Studio is a second assembler, not a system and not host code."*

**The contradiction is not between the two documents.** `BLUEPRINT.md` line 52
already carries the answer, under its own heading *"An assembler is not a
system"*:

> The Effect Studio is not an eleventh system and not host code — it is a second
> assembler, which is why it is 22k lines and fits neither bucket.

So `BLUEPRINT.md` contradicts **itself**, 611 lines apart, and git says why.
Commit `23cbea94d` (2026-08-20 00:04) wrote the open question in **two** places.
Commit `829a1790c` (2026-08-20 07:50) — *"Debug is the eleventh system, the
studio is an assembler"* — wrote the answer and **deleted one copy**, the one
reading *"**Authoring tools: ninth system, or host?** Goal #10 makes authoring a
product."* It missed the second. `CONTEXT.md` was never in dispute, and
`tools/classify_blueprint.py:87` has booked `src/effects/studio/` as
`"assembler"` the whole time. **Three artifacts of four already agreed**; the
fourth dissents in stale residue.

That makes question 1 a one-line deletion, and it is not what this ADR is for.

**The live problem is what "assembler" was made to carry.** `CONTEXT.md` defines
an assembler as a composition that *"wires once and leaves; it is not in the
per-frame loop"* ([ADR-0127](0127-effects-publishes-and-requires-two-ports.md)),
and [ADR-0115](0115-a-system-is-a-bundle-that-ships.md) dec. 5 as *"a composition
over systems that implements the ports and wires them together."* Neither
definition has a size, and nothing checked one.

Measured 2026-08-20 against `classify_blueprint.py`'s seventeen `"assembler"`
entries:

| entry | lines |
|---|---|
| **`src/effects/studio/`** (85 files, flat, 0 `.tscn`) | **21,986** |
| `src/scenes/ProgressionTester.gd` | 1,466 |
| `src/scenes/EffectViewerScene.gd` | 1,321 |
| `src/scenarios/ScenarioPlayerScene.gd` | 1,316 |
| `src/scenes/GPUArena.gd` | 936 |
| `src/scenes/SequenceViewer.gd` | 575 |
| the remaining eleven | 29–201 each |
| **all sixteen except `studio/`** | **6,906** |

Sixteen entries are **single files**; one is a **directory**. It is larger than
the other sixteen combined by **3.2×**, and **120×** the median entry (183 lines). 22k lines is not
wiring, and the shape of the code says so plainly.

**The document lives on the wrong side of the seam.** `EffectViewerScene.gd`
preloads `EffectEditSession.gd` (a file in `src/effects/studio/`) and holds the
live instance itself — `var _edit_session`, `var _colour_sessions` — along with
all **eleven** savers. `EffectStudioPage.gd` names it **8** times, repeatedly as *"the
**host's** `EffectEditSession` choke point."* So the authoring document is parked
on the assembler, and the editor reaches back across a seam to mutate it.

That seam is a **33-verb facade**. Measured 2026-08-20: `EffectViewerScene.gd`
declares **33** `studio_*` methods under a section literally headed *"Effect
Studio host interface (driven by `EffectStudioPage`)"*; `src/effects/studio/`
calls **33** distinct names across **91** call sites, with **zero** dead verbs on
either side. (A 34th name, `studio_set_speed`, appears only inside a comment
saying *"no `studio_set_speed` call"* — a false positive, and the reason to grep
the call, not the string.)

It is also an **undeclared** seam: the page holds `var _host` set by
`bind_host()` and guards every call with `has_method("studio_…")`. Duck-typed
reaches are invisible to `touch_matrix.py` and to the classifier — the same blind
spot [ADR-0129](0129-the-fold-is-renders-and-a-producer-keeps-its-shader.md)
dec. 8 found in `Render`'s `.call("…")` into `Effects`.

Grouping the 33 verbs by what they actually cross to — the method
[ADR-0125](0125-cutscene-keeps-the-program-and-owns-no-mechanism.md) dec. 3 used
to split `ScenarioWorld`'s 69 — gives the finding:

| group | verbs | crosses to |
|---|---|---|
| **document** | **17** | **nothing** — the Studio's own edit session |
| clock / transport | 5 | the **clock port** (ADR-0127) |
| audition | 3 | `Audio` |
| colour probe | 3 | `Render` |
| spacer / fold | 2 | the **fold capability** port (ADR-0129 dec. 8) |
| persistence | 2 | the content store (ADR-0132) |
| camera | 1 | `Battlefield` |

**Seventeen of thirty-three verbs — 52% — cross no boundary at all.** They exist
solely because the document sits on the far side of a line that should not run
between an editor and the thing it edits.

**Two claims in the ticket did not survive checking.** `TrapEffect.gd` (1,005
lines) is *not* uncategorised — `classify_blueprint.py:123` books it to `Effects`
by the name rule `("Trap", "Effects")`. And the count is eleven systems, not ten;
`BLUEPRINT.md` line 52 says *"not an eleventh system"* precisely because
`829a1790c` had just added `Debug` as the eleventh.

The one ticket claim that **did** hold, re-verified 2026-08-20: **`res://authored_effects/`
has 11 writer files and 0 readers.** Save is still write-only.

## Decision

**1. The Effect Studio is an assembler.** Ratification, not a new decision —
ADR-0115 dec. 5, `CONTEXT.md`, `BLUEPRINT.md` line 52 and
`classify_blueprint.py:87` already say so. `BLUEPRINT.md` lines 661–663 are stale
residue of a duplicate that `829a1790c` deleted the other copy of, and are
**deleted**. Nothing else in the blueprint moves.

**2. An assembler is one file, and its weight is bounded.** A composition that
wires once and leaves is `O(10^3)` lines, not `O(10^4)`. **A directory in the
assembler list is a defect**, because "assembler" is the one category that never
becomes a system, so anything parked there is permanently exempt from
extraction. This is the map's no-catch-all rule applied to the classifier's own
`OTHER` bucket.

**There is exactly one instance.** Checked 2026-08-20 across all **29** `OTHER`
entries — 17 `assembler`, 5 `content`, 3 `infrastructure`, 2 `platform`, 1
`generated`, 1 `DELETE` — **every one is a single file except
`src/effects/studio/`**. The largest, `src/data/AbilityDatabase.gd` at 19,411
lines, is one genuinely generated table. So this is a lone defect being fixed,
not a pattern needing a sweep, and the single-file shape is already the
classifier's de facto convention for everything that is not a system.

**3. The Effect Studio's assembler is `EffectViewerScene.gd`, and only that** —
1,321 lines, already booked separately at `classify_blueprint.py:35`. The
`("src/effects/studio/", "assembler")` entry is **removed**.

**4. `src/effects/studio/` belongs to `Effects`.** ADR-0115 dec. 3 forces it and
leaves no discretion: *would anyone use this without that?* Nobody uses the
effect editor without `Effects`; the game uses `Effects` with no editor at all.
*"The asymmetry alone decides"* — so they are **one system**, and an "Effect
Authoring" system is ruled out by the same clause that ruled out headless
`Battle`.

This is [ADR-0115](0115-a-system-is-a-bundle-that-ships.md) dec. 4 in its
original form — *place a system by its capability, never by its content shadow*,
whose worked example was *"the screens are content and the toolkit is the
system."* The Studio's timeline, inspector, channels and curve painters are a
toolkit over ADR-0122's lane model. They are not FFT data, so they are not
content, and they are not wiring, so they are not assembly.

**5. `Effects` is 38,162 lines, not 16,176** (2026-08-20). It becomes the largest
system by a wide margin. This is bookkeeping catching up with code that already
exists — no line moves, no file moves. ADR-0131's line count is *"hand-written
lines, per system"*, and 21,986 of them were being reported against a category
that is not a system.

Both figures are `classify_blueprint.py`'s own, run 2026-08-20 after the change.
The pre-change **16,176** matches ADR-0129's published `Effects` figure *exactly*,
so nothing has drifted since #316 and the whole delta is `studio/`. `assembler`
falls to **16 files / 6,906 lines** — the sixteen single files, unchanged.

**6. The document moves to the system; the facade collapses to its crossings.**
`EffectEditSession` and the colour sessions are `Effects`' state and belong in
`src/effects/studio/`, not on `EffectViewerScene`. The 17 document verbs then
cross nothing and cease to be interface. What remains is **16 verbs over six
seams**, five of which are already-named ports — and *that* is the answer to the
map's resolution bar for this boundary. **The savers go with the document**; per
ADR-0132 dec. 4 an authoring tool's workspace is outside the project, and per
dec. 6 what crosses to the store is a per-system content schema, which `Effects`
owns and the assembler does not.

This is ADR-0125 dec. 3 a second time — a wide facade *"hides the crossings
inside itself, and naming the crossings is the point."* At 33 verbs against
`ScenarioWorld`'s 69, the same re-projection applies at half the size.

**7. The seam must be declared, not duck-typed.** `bind_host()` plus
`has_method()` is a real seam — dependencies are injected, not constructed — but
an undeclared one. Per
[ADR-0133](0133-a-wrong-cut-is-fixed-forward-and-the-reconnect-is-the-trigger.md)
dec. 7–8 declared ports are a **hard gate**, and this crossing is `Effects` ->
assembler, i.e. addon -> host, which dec. 8 makes *always a defect*. It survives
today only because `studio/` is not booked as a system; decision 4 exposes it.
Fixing it is the reconnect that ADR-0133 dec. 4 says catches a wrong cut, and it
fires inside `Effects`' own extraction pass.

**8. The Effect Studio is the first assembly target, on concentration rather than
size.** Reach measured 2026-08-20 by resolving all 337 `src/` `class_name`s
against each assembler's text (a path grep finds almost nothing here — bare-name
callers are ADR-0133 dec. 5's silent third):

| assembler | `src/` dirs reached | reaches | largest share, excl. `debug` |
|---|---|---|---|
| `GPUArena.gd` | **10** | 39 | `gpu` 5 of 22 — **23%** |
| `EffectViewerScene.gd` | 7 | 46 | `effects` 30 of 37 — **81%** |
| `ScenarioPlayerScene.gd` | 6 | 28 | `scenarios` 9 |
| `ProgressionTester.gd` | 5 | 12 | `data` 6 |

`GPUArena` reaches more systems and spreads evenly across them; the Studio is
**one system plus scaffolding**. That concentration — not its line count — is
what makes it the assembler to rebuild out of extracted parts first, and it gives
the Studio the role for assemblies that `exmateria_sound` holds for addons: the
**calibration case**.

**9. There is no reassembly phase; replacement is in place.** Resolving a fog
entry open since 2026-08-19, in the author's words: *"once all dependencies on
the old system are gone, then that is going to be in its place — that is the
'back together' part."* This **confirms** ADR-0110's Consequences rather than
amending them: the end state arrives incrementally, per extraction, and no phase
reconnects anything. A **greenfield reimplementation** is a possible *epilogue*
once enough systems exist — explicitly not the extraction mechanism ADR-0110
rejects, and not scheduled here.

## Considered alternatives

- **Make the Studio an eleventh (or twelfth) system.** Rejected by ADR-0115
  dec. 5 directly, and it would move both the system count fixed by ADR-0117 and
  the two-root-set declaration of ADR-0112 dec. 3, which exists *because* each
  assembler is a root set. Nothing in the evidence pushes that way — the Studio
  implements ports and wires, which is the definition it already satisfies.
- **Make `src/effects/studio/` its own system, depending on `Effects`.** The
  tempting answer, and the one ADR-0115 dec. 3 exists to refuse: the uselessness
  is one-way, so the asymmetry decides and they are one system. Splitting them
  would also require a published interface between an editor and its own document
  — the very facade decision 6 removes.
- **Leave `studio/` booked as assembler and accept 22k lines there.** The status
  quo. Rejected because it makes the Studio permanently unextractable: assembler
  is the category that never becomes a system, so 94% of the Studio's lines could
  never resolve into one, and the assembly named in decision 8 could never be
  built out of parts.
- **Split `studio/` between assembler and `Effects` file by file.** Rejected as
  premature. Only **6 of 85** files reach the host at all, and 4,150 of the
  21,986 lines sit in those six; the other 79 files never touch the assembler.
  A directory-level move is correct on the evidence, and the six files are
  decision 6's work, done inside the extraction pass with the code in front of
  you.
- **Treat the Studio's screens as content, per ADR-0115 dec. 2.** Rejected:
  content is *"FFT data, ROM parsers, the wiring that makes this game."* A
  timeline editor over the lane model is none of those.

## Consequences

- `BLUEPRINT.md` loses lines 661–663; its §"Not decided" loses its authoring-tool
  entry entirely. `CONTEXT.md`'s **Assembler** entry gains the size bound from
  decision 2 and is otherwise correct as written.
- `classify_blueprint.py` loses the `("src/effects/studio/", "assembler")` entry;
  `src/effects/` then books `studio/` to `Effects` by the existing directory
  rule, with no new rule needed.
- **The baseline moves before pass 6 takes it.** `touch_matrix.py` reuses
  `classify_blueprint.py` as ground truth, so dec. 3–4 move it too. Measured both
  ways 2026-08-20: **354 -> 360 cross-system edges, +6.** ADR-0131 amended.
  Taking the baseline first would have booked the correction as progress — the
  failure pass 2 exists to prevent, and the second time this map has caught it
  before the fact (ADR-0129 fixed the classifier for the same reason).

- **The 33-verb facade is the largest known instance of ADR-0131 dec. 6's floor.**
  The delta is **+6**, not +91, because every one of the **91** `studio_*` call
  sites is `has_method()`-guarded and carries no type name — so `touch_matrix.py`
  sees **none of them**, before the change or after. An entire 33-verb crossing
  between the largest system and its assembler is invisible to the reach metric.
  dec. 6 already says a clean column is not proof of a clean boundary; this is
  what that looks like at scale, and it is why dec. 7 here requires the surviving
  verbs be *declared*. Declaring them is what makes them countable.
- **`Effects` extraction gets substantially larger and its order does not
  change.** The Studio still extracts last — it is a declared root set — and
  #306's finding that extraction order is free is untouched, because `studio/`
  publishes nothing anyone else consumes.
- **The write-only Save is now inside a system.** Eleven savers with zero readers
  become `Effects`' problem rather than an assembler's, which is what gives
  ADR-0132 dec. 6's per-system content schema an owner. It does not give it a
  ticket.
- **This ADR's validity is bounded at decision 4.** If `Effects` ever ships to a
  consumer outside this repo that wants the runtime without the editor,
  ADR-0115 dec. 3's asymmetry reverses and the split becomes real. Per ADR-0121
  dec. 7 that is the promotion boundary, and per ADR-0133 dec. 3 the fix at that
  point is forward — split the addon — never a revert.
- Live map [#262](https://github.com/timbermania/fft-monorepo/issues/262) is
  unaffected; this decides the Studio's category, not its design.
- **Blocked on [#299](https://github.com/timbermania/fft-monorepo/issues/299)
  like everything else touching `src/`.** ~1,400 of `EffectStudioPage.gd`'s 3,561
  lines are unmerged across two branches, so every count here is against trunk
  and will move when they land. **Re-measure before quoting.**
