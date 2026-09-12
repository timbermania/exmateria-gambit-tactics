# Gambit lab

The instrument ADR-0275 builds, and the words it needs. It is a **development instrument,
permanently** — it never ships — but its vocabulary is load-bearing for the three tickets that
built it (#1126–#1129) and for the fleet sweeper that has not been built yet.

⚠️ **The verdict side is NOT yet named here.** `Gambit verdict`, `verdict payload`, `pass 1` /
`pass 2` and the twelve `VERDICT_*` codes came out of #1126 and #1127 and live only in
`combat_common.glslinc` → *THE PER-SLOT GAMBIT VERDICT* and in `GambitVerdictReader`'s docstring.
That gap is recorded rather than quietly half-filled: #1129 added the terms it introduced.

**Cell**:
The lab's primitive and the unit of evidence: **one actor, exactly one dummy in the axis's pool,
one condition, one boot**, on MAP116. Not a tableau holding one dummy of every kind — a crowded
scene's answer is *joint over a population*, so the pick cannot be attributed to the axis under
test without also reasoning about every other dummy, AoE splash, reactions and the safety net.
The phrase "exactly one dummy" counts candidates IN THE POOL, not units on the field: an
ally-pool cell carries a third inert unit (see **Liveness opponent**) because without one the
battle is decided on tick 1.
_Avoid_: reading a cell as a test — a cell is synthesized by `GambitCellSynth`, booted by the
live arm and scored against its own prediction, and ADR-0275 dec. 15 keeps the sweep out of the
suite on purpose.

**Cell spec**:
What the synthesizer RETURNS: a dict carrying the `scenario` (shaped exactly like one of the 84
fixtures in `tests/gambit_scenarios/`, so `GambitScenarioBoot` boots it with no new code path),
the `axis` it moves, the `expect` rows it predicts, its derived tick budget, and — when the cell
could not be built — `refused` plus the reason. A spec is ALWAYS returned, because a refusal is
the product and a null would make it uncountable.
_Avoid_: treating a spec as a fixture. Fixtures are read-only and committed; a spec is generated
per run, and there is deliberately no "save as fixture" button (dec. 17).

**Axis**:
The ONE quantity a cell is built to decide, named as the condition's opcode plus the index of
that condition within the gambit. Everything else on the board is held still.

**Knob**:
The single field a **mirror** moves to cross the axis's boundary, and WHOSE field it is —
`dummy_hp_percent`, `dummy_status_bit`, `separation`, `actor_mp_percent`, `actor_speed`. The
subject matters and is not guessable: the MP opcodes read the ACTOR's MP
(`get_mp_percent(battle_id, unit_id)`) while every HP opcode reads the target's, so
`GambitCondition.Type.TARGET_MP` encodes cleanly onto a condition that never looks at the target.
_Avoid_: moving two knobs between a cell and its mirror. The pair then flips for a reason nobody
named, and the whole argument for generating mirrors collapses.

**Mirror**:
The same cell with the knob moved to the other side of the condition's boundary and **nothing
else touched**. Auto-generated for every positive cell, which is what makes the instrument
self-checking: **a pair that fails to flip is a defect regardless of what anyone expected.** A row
can have more than one mirror — `COND_IN_RANGE` on an `ATTACK_ARCING` weapon has a far edge and a
near one, because `check_arcing` carries a minimum as well as a maximum, and a pair that flips on
one and not the other is a different finding from a pair that does not flip at all.

**Ladder**:
The third cell shape: rungs authored into slots 0..N-1 such that each **declines for the reason
the lab predicted** before slot N fires. "Slot N fired" alone is not a pass. Capped at
`MAX_USER_GAMBITS` rungs, because pass 1 walks slot `MAX_USER_GAMBITS` as ADR-0048's injected net,
whose `Always` cannot fail, so a rung at or past it could never be reached. The rungs' knobs must
be DISJOINT or the ladder refuses: two HP rungs want two different HP values on one board.

**Straddle table**:
Hand-authored, one row per `COND_*` the kernel declares, each naming the kernel's own predicate,
the knob, the knob's subject, what the verdict payload will measure, and which side of the
boundary is positive. Guarded by `tools/check_gambit_straddle_table.py` — a new opcode with no row
reds the pre-flight.
_Avoid_: a generic "perturb the operand by ±1". It manufactures false negatives silently, and it
gets the *side* wrong half the time without saying so: the kernel tests `measured < value`, so the
negative side sits exactly ON the threshold. `COND_IN_RANGE` alone has four boundaries depending
on the actor's weapon.

**Refusal (of a cell)**:
A cell the synthesizer will not build, returned NAMED with its reason and COUNTED. Never nudged —
a nudged dummy still produces a verdict, and that verdict now describes a different experiment
from the one on the label, so it fails *productively*, which is the most dangerous option
available to a debugging instrument. The refusal list is a to-do list, which is why an unnamed or
unreasoned refusal is itself a defect. Four classes exist today: no operand to move
(`COND_ALWAYS`); unseedable state (`COND_IS_DEAD` / `COND_IS_ALIVE` — `FLAG_DEAD` has no channel
in the battle spec); off-board geometry (past MAP116's Manhattan 10 or cardinal 5); and
unreachable from any authored gambit (`COND_TEAM_ALLY` / `COND_TEAM_ENEMY`).

**Liveness opponent**:
One inert unit on team 1, at the board's far corner with `move: 0` and `speed: 1`, added to a cell
whose axis pool is ALLIED. `check_victory` returns `RESULT_TEAM_0_WINS` the instant
`team1_alive == 0`, so a two-unit ally cell ends on tick 1 — 29 ticks before the actor's first
turn — and every slot reads `NONE(not walked)`. It is in the safety net's pool and nowhere else,
and dec. 19 requires the net to be labelled rather than suppressed, so the cell's expectation
names its row.
_Avoid_: reading it as a second dummy. It is not in the axis's pool and the axis's pool still
holds exactly one candidate.

**Blind run**:
A cell that produced NO verdict at all, as opposed to one whose prediction missed. `VERDICT_NONE`
is 0 and is a REAL answer — *"this call did not walk this slot"* — so a zeroed field and an
instrument that never fired are indistinguishable, and a scorer that accepted "something was
written" would pass on a write that never happened. The lab reports it as a blind run and scores
nothing, which is why the tick budget is derived from the actor's Speed rather than fixed.
_Avoid_: calling a blind run a failure. It is a statement about the instrument, not about the
kernel, and the fix is never to relax the prediction.

**Coverage line**:
The one line the lab SHIPS instead of a raw-opcode injection path: which kernel opcodes no
authored gambit can reach. Measured on every call by pushing the supported cross product of
`GambitCondition` and `TargetSelector` through the real `GambitEncoder` — never quoted, because
the number moves (#1114 took it from six conditions and two selectors to two and two in the hours
before ADR-0275 was written). Its `surprises` channel is the part worth guarding: a combination in
no declared `UNSUPPORTED_*` set that still fails to encode is an UNDECLARED gap, and ADR-0023 is
faithful-or-*explicit*.
_Avoid_: bypassing the gap. Injecting opcodes directly would let the lab exercise battles that
cannot exist in the game, and route around the encoder the live arm deliberately keeps in the path.
