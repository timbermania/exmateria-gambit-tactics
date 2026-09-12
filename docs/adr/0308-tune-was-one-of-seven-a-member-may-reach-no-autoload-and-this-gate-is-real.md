# ADR-0308 — `Tune` was one of seven: a UI member may reach no autoload identifier at all, and unlike ADR-0306 dec. 4 this gate is real

- **Status:** accepted
- **Date:** 2026-09-12
- **Ticket:** #1270 (extraction #8, pass 6 step 3 — the move, blocked)
- **Pass:** 6 of 9 (`docs/agents/refactor-loop.md`)
- **Grills:** ADR-0303 dec. 1, ADR-0307 dec. 4
- **Constrains:** ADR-0211, ADR-0212, ADR-0257, ADR-0262, ADR-0303, ADR-0307

Pass 6 step 2 ported **107** `Tune` reaches to `ExMateriaPlatform.TunePort` and called the
autoload problem solved. It was one seventh of the problem. Six other host autoloads are
reached from inside the member set, across **49 lines in 16 of the 121 members**, and every
one of them is undefined in the project that decides whether this extraction worked.

One iteration ago I removed a gate I had invented (ADR-0307 dec. 4). This ADR installs one.
The difference is not a mood, and §4 states the test that separates them.

## 1. The rule, and where it is written down

It is not written down. It is **measured**: all eight stranger rigs declare an empty
`[autoload]` block.

```
tests/stranger/exmateria_almanac      0 autoloads
tests/stranger/exmateria_battlefield  0
tests/stranger/exmateria_catalogue    0
tests/stranger/exmateria_effects      0
tests/stranger/exmateria_platform     0
tests/stranger/exmateria_render       0
tests/stranger/exmateria_schema       0
tests/stranger/exmateria_sprite_rig   0
```

That is not an oversight to be fixed by adding the autoload the addon wants; it is what makes
the rig a test. ADR-0262 dec. 6 says an addon cannot ship `project.godot` entries, so a bare
autoload identifier resolves in the **host** and nowhere else.

`CharacterCatalog` shows the shape exactly. The script already lives at
`addons/exmateria_catalogue/registry/CharacterCatalog.gd`; the host declares
`CharacterCatalog="*res://addons/…"`. **The script travels with the addon and the registration
does not.** Seven of the host's 27 autoloads already point into addons this way, so "move the
file" was never the hard half.

## 2. The measurement

Subject: the 121 members (ADR-0306 dec. 1). Identifiers: parsed from `project.godot`'s
`[autoload]` block, never hardcoded. Blanking: the census's stateful blanker, so a name in a
comment, a string or a `"""…"""` block does not count (ADR-0306 dec. 6).

| autoload | reaches | members | surface |
|---|---:|---:|---|
| `PSXDisplay` | 25 | 7 | `live_ui_par`, `live_ui_par_changed` |
| `DebugConfig` | 8 | 5 | `iteration_debug_enabled`, `feedback_numbers_enabled` |
| `CharacterCatalog` | 6 | 3 | `owned_units()`, `is_owned()` |
| `SfxRouter` | 5 | 2 | `play_cue()`, `play_system()` |
| `EventBus` | 4 | 2 | `unit_hp_changed` |
| `UI3Registry` | 1 | 1 | UI's own — dissolves at the move |
| **total** | **49** | **16 of 121** | |

`Tune` is **0**, which is the positive control: the same instrument over the same subject
returned 107 before step 2 and returns 0 now, so a zero here means paid, not blind.

Five of the six are real debts. `UI3Registry` is UI's own autoload and becomes an ordinary
`preload` the moment the file is inside the addon — it is on the list because a reader who
found it absent would wonder, not because anyone must act.

## 3. Why only one of the six was on the board

Pass 3 found `PSXDisplay` and filed **#1263** — *"DisplayPort is two verbs short of UI's whole
display surface — live_ui_par and live_ui_par_changed are 25 lines in 7 files"*. Same 25, same
7. So the biggest instance was measured three passes ago and filed **as port incompleteness**:
a ticket about `DisplayPort` being short, not about the move being impossible.

That framing is why the other five were never counted. A ticket that says *this port lacks two
verbs* invites the reader to check that port; a ticket that says *a member may name no autoload*
invites them to enumerate all 27. Nobody enumerated, and step 2 then solved `Tune` — the one
autoload with a port already built — which made the category look finished.

This is the standing lesson about ad-hoc gates arriving one at a time: the defect is not that
`DisplayPort` is short, it is that six identifiers cross a boundary that admits none, and the
fix is one enumeration plus one instrument, not six tickets discovered six passes apart.

## 4. The test that separates a real gate from an invented one

ADR-0307 dec. 4 struck down the gate at ADR-0306 dec. 4 and this ADR installs a new one, so the
criterion must be stated rather than felt:

> A prerequisite is a **gate** when the deliverable cannot be produced without it, and merely a
> **scope decision** when the deliverable is produced at a different size.

Where UI's tests live changes the **length of the façade const list** — 56 rows or 67 — and a
row deleted later is a deleted line. That is size, so ADR-0212 dec. 2 applies and it does not
gate. An autoload reach changes whether the addon **runs at all** in the one project that
referees the extraction. That is existence, so it gates.

The criterion is cheap to apply and would have caught my error at ADR-0306 dec. 4 before it
cost an iteration: ask what the artifact looks like if the decision goes the *wrong* way. A
67-row façade is an artifact. An addon whose `UIText.gd` calls an undefined `DebugConfig` is not.

## 5. The instrument is a ratchet, and it needs three arms

`tools/check_ui_autoload_reach.py` cannot be a gate — 49 reaches stand today and the suite must
stay green while they are paid off. So it is a ratchet over a declared `BASELINE`, and it reds
three ways, because a ratchet has three ways to rot:

1. a **new** identifier appears, or a count **grows** — a regression;
2. a debt is **paid down** and its `BASELINE` row left behind — the silent one, which re-admits
   the reach under a green suite;
3. the **subject is empty** — the census broke, or the move happened and the guard must be
   deleted rather than go quietly green.

Arm 2 is the arm a one-armed ratchet misses and the reason this file has seven tests, not one.
Identifiers are parsed from `project.godot` rather than listed, so a 28th autoload comes under
the guard the day it is added without anyone remembering to add it.

## Decisions

**1. A member may reach no autoload identifier at all — not `Tune` specifically.** All eight
stranger rigs declare an empty `[autoload]` block, and an addon cannot ship `project.godot`
entries (ADR-0262 dec. 6). ADR-0303 dec. 1's `Tune` port closed one seventh of this. Argued in §1.

**2. Pass 6 step 3's `git mv` is GATED on 49 autoload reaches across 16 members, in five real
debts** — #1263 `PSXDisplay` 25, #1271 `DebugConfig` 8, #1272 `CharacterCatalog` 6, #1273
`SfxRouter` 5, #1274 `EventBus` 4. `UI3Registry` 1 dissolves at the move. Argued in §2.

**3. A prerequisite gates when the deliverable cannot be PRODUCED, and is a scope decision when
the deliverable is produced at a different SIZE.** Apply it by asking what the artifact looks
like if the decision goes the wrong way. This is the criterion ADR-0307 dec. 4 was missing, and
it ratifies both that decision and this one. Argued in §4.

**4. A ticket naming one instance of a boundary violation hides the category.** #1263 measured
`PSXDisplay` correctly three passes ago and framed it as one port lacking two verbs, so nobody
enumerated the other 26 autoloads. Enumerate the boundary, then file per instance. Argued in §3.

**5. The arm-2a instrument is a RATCHET with three failure directions, and its identifiers are
parsed from `project.godot`, never listed.** A baseline that outlives its debt re-admits the
reach silently; a hardcoded identifier list goes stale at the next autoload. Argued in §5.

**6. `CharacterCatalog` proves the script and the registration travel separately.** Seven host
autoloads already point into addons. An extraction does not have to extract an autoload's
script — it has to stop naming the identifier. Argued in §1.
