# Combat-event resolution

When an attack swing or an effect cast resolves on a defender, the outcome
flows down one of **six pathways**. The pathway decides what HP/MP change,
whether the defender's [Logical activity](18-sprite-layers.md)
changes, and what (if any) visual overlay renders. This cluster names the
pathways so a feature that touches damage or reaction abilities stays
inside one pathway and doesn't accidentally cross-thread state through
another. It is the **mechanic** side of "react"; the rendering side lives
in [Animation react](20-animation-react.md).

| # | Pathway | Trigger | Logical state | Visual |
|---|---|---|---|---|
| 1 | [Miss](21-combat-event-resolution.md) | hit-roll fails (evasion stack or parry reaction) | unchanged | React overlay (`evade` / `shield_block_*` / `receive_heal` for blade-grasp parry) |
| 2 | [Hit](21-combat-event-resolution.md) | hit-roll succeeds, damage lands | unchanged | React overlay (`taking_damage`) |
| 3 | [Ability cast lands](21-combat-event-resolution.md) | effect keyframe action_flags 0x40 fires | unchanged | React overlay (per ability `target_reaction_type`) |
| 4 | [Pre-emptive counter](21-combat-event-resolution.md) | Hamedo, fires before damage applies | IDLE → PREEMPTIVE_COUNTER (1 tick) → ACTING | full ATTACKING animation |
| 5 | [At-resolution damage modifier](21-combat-event-resolution.md) | Mana Shield / Absorb MP / Auto-Potion, fires inline in damage Phase 3 | unchanged | React overlay (`taking_damage` over the modified damage) |
| 6 | [Post-strike counter](21-combat-event-resolution.md) | Counter / Counter Tackle, fires after damage applies | **today: unchanged** — see *faithfulness gap* below | **today: none.** ROM: full ATTACKING animation |

Pathways 1, 2, 3, 5 leave Logical state unchanged and converge on the
[React playback set](19-animation-playback.md) for their visual. Pathway 4 is
the only one that mutates Logical state (the [PREEMPTIVE_COUNTER](21-combat-event-resolution.md)
gateway). Pathway 6 is partially stubbed today.

**Pathway 1 — Miss**:
Hit-roll outcome `miss`. The evasion stack
(class evasion / weapon parry / shield block / accessory) plus the two
**parry-style reaction abilities** ([Blade Grasp](21-combat-event-resolution.md),
[Arrow Guard](21-combat-event-resolution.md)) all converge on a single boolean
`hit=false` and a per-flavor enum `U_EVADE_TYPE`. The defender's
[CombatLoop._trigger_physical_reaction](20-animation-react.md)
(SEQ-opcode-driven) reads `evade_type` and plays the right
overlay — `evade` for generic, `shield_block_mid` for shield, `receive_heal`
for blade-grasp parry. No Logical state change. PSX-faithful: same opcode
0xffde from the attacker's BODY SEQ fires both 1 and 2; the GPU's hit
boolean decides which overlay plays.

**Pathway 2 — Hit**:
Hit-roll outcome `hit`; damage queues into `U_PENDING_DAMAGE` and Phase 3
of stage_damage applies it. Same SEQ-opcode-driven trigger as Pathway 1;
the overlay is `taking_damage` because the hit flag was true. No Logical
state change — the defender's existing activity continues to play
underneath the React overlay.

**Pathway 3 — Ability cast lands**:
Effect script reaches a keyframe with `action_flags` bit `0x40`
(`ACTION_FLAG_ABILITY_REACT`); the effect timeline emits
`ability_react_triggered`; `CombatLoop._on_ability_react` reads the
ability's `target_reaction_type` and plays the matching overlay (`taking_damage`,
`receive_heal`, or one of the shield_block flavors). Distinct from Pathway 1/2
because the trigger is **effect-timeline-authored**, not attacker-SEQ-driven —
spells fire their react keyframes whenever the effect script wants, decoupled
from any swing animation. No Logical state change.

**Pathway 4 — Pre-emptive counter**:
Hamedo ([REACT_FIRST_STRIKE](21-combat-event-resolution.md)) fires from
`check_pre_damage_reactions` in `stage_compute.glsl` *before* damage applies.
The shader writes `U_TARGET = attacker` + `U_STATE = LOGICAL_ACTIVITY_PREEMPTIVE_COUNTER`
(the [PREEMPTIVE_COUNTER](21-combat-event-resolution.md) one-tick gateway). On
the next tick the gateway runs `setup_attack_animation`, which transitions
the defender to `LOGICAL_ACTIVITY_ACTING` against the original attacker —
the defender's counter-strike then plays as a normal ATTACKING animation
(no React overlay involved). Faithfulness gap today: the trigger is gated
on `defender_state == LOGICAL_ACTIVITY_IDLE`, which is rarely true in
active combat, so Hamedo almost never fires in practice.

**Pathway 5 — At-resolution damage modifier**:
The three damage-modifier reaction abilities — Mana Shield,
Absorb MP, Auto-Potion — fire inline in `stage_damage.glsl` Phase 3
**after** Pathway 2/3's pending damage is computed but **before** it
applies to HP. Mana Shield drains MP first; Absorb MP converts a quarter
of damage to MP; Auto-Potion heals after the damage if HP dropped below
max/4. None of these change Logical state. The defender's flinch (Pathway 2)
still renders normally over the modified damage — the overlay is timed by
the attacker's SEQ opcode, not by the final HP delta.

**Pathway 6 — Post-strike counter**:
Counter ([REACT_COUNTER](21-combat-event-resolution.md)) — and its untyped
sibling Counter Tackle — fires from `stage_damage.glsl` Phase 2.5 after
the attacker's damage is queued. **Today**: the defender's PA*WP is added
straight to the attacker's `U_PENDING_DAMAGE` as a symmetric HP exchange
ledger — no Logical state change, no defender animation. **ROM-faithful**:
the defender should play a full counter-attack ATTACKING animation,
including its own evasion roll on the attacker. The faithful version
would reuse the [PREEMPTIVE_COUNTER](21-combat-event-resolution.md) gateway
(same one-tick → ACTING shape).

**Reaction ability**:
An FFT job ability equipped in the unit's reaction slot — seven values in
the `REACT_*` shader enum (`combat_common.glslinc`): First Strike (Hamedo),
Counter, Blade Grasp, Arrow Guard, Auto-Potion, Absorb MP, Mana Shield.
Stored in `U_REACTION_ABILITY` per
[combat buffer](02-combat-buffer-layout.md); mapped through
`GPUBatchSimulator.REACTION_ABILITY_TO_REACT`. The seven abilities split
into three **families** by *when in the resolution they fire* — see below.
Completely orthogonal to [React animation](20-animation-react.md) — the only
thing they share is the word "reaction." A reaction ability that fires
may itself trigger a React animation as a downstream effect (e.g. Blade
Grasp causes `receive_heal` to play in Pathway 1), but the animation is
not the ability.
_Avoid_: grepping for "react" / "reaction" without distinguishing which
domain a hit belongs to — at least four meanings exist (this cluster's
**reaction ability**; [React animation](20-animation-react.md); the
`HIT_REACTION` action flag, which is a damage-popup trigger; the per-tile /
camera `revert` flips in [Sprite variants](22-sprite-variants.md)).

**Parry-style reaction**:
The family of reaction abilities that add a chance to convert hit→miss
at hit-roll time — **Blade Grasp** (melee, `REACT_BLADE_GRASP = 4`) and
**Arrow Guard** (ranged, `REACT_ARROW_GUARD = 5`). Trigger chance is
`min(target.PA * 5, 95)%` per `stage_compute.glsl::apply_attack_damage`.
On success, the hit becomes a miss (`U_EVADE_TYPE = 3`, a weapon-parry
flavor) and Pathway 1 renders the `receive_heal` overlay (FFT reuses the
"hands up" pose for the catch). Pure passive — no Logical state change,
no counter-strike.
_Avoid_: treating these as part of the [evasion stack](21-combat-event-resolution.md)
(they layer on *after* the stack — independent roll); calling them "counter"
because they have "react" in the constant (they're a hit/miss flavor, not
a counter-strike).

**Damage-modifier reaction**:
The family that fires inline in damage Phase 3 to transform pending
damage before it touches HP — **Mana Shield** (`REACT_MANA_SHIELD = 6`,
MP-instead-of-HP), **Absorb MP** (`REACT_ABSORB_MP = 2`, gain MP from
damage), **Auto-Potion** (`REACT_AUTO_POTION = 3`, heal after damage if
HP drops critical). All Pathway 5. No Logical state change; Pathway 2's
flinch overlay still plays unchanged because the SEQ opcode fires
independent of the final HP delta.
_Avoid_: putting Mana Shield's MP-drain logic in
`check_pre_damage_reactions` (it must fire *after* Pathway 2/3 compute
pending damage, not before); modeling these as Logical state changes
(they never transition the defender out of its current activity).

**Counter-strike reaction**:
The family whose effect is "the defender takes a full attack action."
Two members today — **First Strike (Hamedo)** (`REACT_FIRST_STRIKE = 1`,
Pathway 4) fires **before** the original damage applies; **Counter**
(`REACT_COUNTER = 0`, Pathway 6) fires **after** the original damage
applies. Counter Tackle is a third member with no shader constant yet,
mechanically a Counter variant. The **pre-emptive** vs **post-strike**
distinction is timing relative to the attacker's hit; both produce a
full ATTACKING animation when fully implemented.
_Avoid_: calling the post-strike form "the counter" unqualified — both
forms are counter-strikes; the timing must always be named (pre-emptive
/ post-strike) when one specific behavior matters.

**PREEMPTIVE_COUNTER** *(Logical activity, one-tick gateway)*:
The GPU [Logical activity](18-sprite-layers.md) the shader
writes when a [pre-emptive counter-strike](21-combat-event-resolution.md) is
queued for next tick (today: Hamedo only). Lives **exactly one tick**:
`check_pre_damage_reactions` writes it as a transition from IDLE; the
next-tick state handler runs `setup_attack_animation`, which immediately
writes ACTING. The translator no-ops on PREEMPTIVE_COUNTER (the Display
side stays in the IDLE pose for the gateway tick, then switches to
ATTACKING under ACTING via the existing `attack_handler` routing). No
React overlay involvement — the counter-strike's visual is a normal
attack swing.
_Avoid_: routing the [Animation react](20-animation-react.md) overlay
(`taking_damage` etc.) through PREEMPTIVE_COUNTER — those overlays come
from the two ROM-faithful trigger pathways (SEQ opcode 0xffde, effect
keyframe 0x40) and never from this Logical state; treating
PREEMPTIVE_COUNTER as a multi-tick activity (the next-tick handler
always transitions out — either to ACTING via setup_attack_animation,
or to IDLE if the queued target is gone); using this state for damage
modifiers or hit-flavor overlays (it is the **pre-emptive counter-strike**
slot specifically — see the [Counter-strike reaction](21-combat-event-resolution.md)
family above).
