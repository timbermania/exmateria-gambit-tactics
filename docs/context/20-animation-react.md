# Animation react

The visual a unit shows when something is *done to it* — a flinch from a
hit, a hands-up for healing, an evade dodge, a shield block. Orthogonal
to the unit's [animation state](19-animation-playback.md) (which is
about what the unit is *doing*); React is "what just happened TO the
unit." Triggered by **two distinct sources** that converge on the **one**
[React playback](19-animation-playback.md) mechanism, with a resolution table
in between that picks which animation to play. The overlap semantics
across triggers — what happens when a new React arrives while one is in
flight, or two arrive in the same tick — is **deliberately unresolved**
(see "React overlap" below).

React is `Sprite Rig`'s, and the rig's settled published spellings are tabulated
once at the head of [sprite layers](18-sprite-layers.md). Nothing in this cluster
moves to the kernel: React's own vocabulary is seq ids and trigger sources, not a
value enum two systems must agree on — the one enum here that crosses,
`AnimationOpcodes.SideEffect`, publishes on the rig's own façade rather than the
kernel, because it shares four member names at different integer values with
`AnimationOpcodes.Op`
([ADR-0217](../adr/0217-the-kernel-publishes-no-names-so-the-vocabulary-move-is-sixty-one-alias-declarations-and-the-rig-needs-a-facade-first.md)
dec. 6).

```
EFFECT keyframe action_flags bit 0x40  ─┐
                                        ├─→ Unit.play_reaction_animation(seq_id, type, use_timer)
SEQ opcode 0xffde (PostGenericAttack)  ─┘                │
                                                          ▼
                                                  React playback starts
                                                  (hijacks BODY render)
```

**React animation**:
The seq played on the [React playback](19-animation-playback.md). Always
sourced from the unit's body [sprite type's](18-sprite-layers.md) SEQ table at
a fixed set of slot ids (catalogued in `assets/abilities/reaction_animations.json`,
parsed from the ROM). Five canonical kinds (per the `ReactionType` enum):
**`taking_damage`** (seq 0x19), **`receive_heal`** (seq 0x1b), **`evade`**
(seq 0x18), **`shield_block`** (high / mid / low variants 0x58-0x5a,
height-driven), **`blade_grasp`** (catches the strike — same seq as
`receive_heal`). The animation choice is **derived from the trigger's
ability data**, not authored per trigger event — see "React resolution"
below.
_Avoid_: putting damage / status / heal *logic* in React — React is
the *visual notification*; the actual damage application is the
[damage-popup trigger](20-animation-react.md) (bit `0x10`), an independent
flag firing on the same event; treating React as a state of the unit —
it's an overlay on the BODY layer, not in the
[AnimationState](19-animation-playback.md) enum.

**Effect react trigger** (a.k.a. ABILITY_REACT):
The trigger pathway that fires from spell / ability **effect playback**
— specifically, an `action_flags` bit `0x40` on a particle channel
keyframe inside an `E###.BIN` effect. When the
[effect timeline](15-effect-orchestration.md) hits that keyframe, the
`EffectInstance` emits `ability_react_triggered(frame)`;
`CombatLoop._on_ability_react` reads the casting ability's
`target_reaction_type` and calls `Unit.play_reaction_animation`. **The keyframe does not name the
animation** — it only fires the trigger; the animation is resolved from
ability data (see "React resolution"). PSX call graph:
`process_keyframe_actions` (0x801a31a8) → `apply_unit_ability_reaction` →
`execute_unit_reaction_pose` (0x80083a40) → writes anim_id to unit struct
+0x0c.
_Avoid_: confusing this with the [damage-popup trigger](20-animation-react.md)
(bit `0x10` = `ACTION_FLAG_HIT_REACTION`) — same action_flags byte,
different bit, completely different concern (damage numbers, not
animation); calling it "ability react" without context — the word
"ability" in this codebase is overloaded (FFT job ability, ability data,
[reaction ability](20-animation-react.md)).

**SEQ react trigger** (a.k.a. PostGenericAttack):
The trigger pathway that fires from **physical attacks** — specifically,
SEQ opcode `0xffde` (`POST_GENERIC_ATTACK` in this codebase's
`AnimationOpcodes` enum) placed at the attacker's *hit frame* inside the
attack animation sequence. When the attacker's BODY
[playback](19-animation-playback.md) reaches the opcode, it emits
`side_effect.POST_GENERIC_ATTACK`; the react-handling subsystem reads the
hit/miss outcome from the GPU snapshot and calls
`Unit.play_reaction_animation` on the target with the appropriate
`taking_damage` / `evade` / `shield_block` seq id. PSX call graph: SEQ
opcode 0xde → `execute_unit_reaction_pose` (**same function as the
Effect react trigger** — both pathways converge here).
_Avoid_: confusing this with the [Damage-popup trigger](20-animation-react.md)
even though that flag is also called `HIT_REACTION`; assuming the SEQ
opcode is unique to attacks — it's a side-effect opcode like any other
on the BODY playback's stream, and timing is animator-controlled by
where the opcode sits in the SEQ.

**React resolution**:
The function (PSX: `execute_unit_reaction_pose` at 0x80083a40; godot
project: the consumer's switch on `target_reaction_type`) that picks
which [React animation](20-animation-react.md) to play given an ability's
effect type. Both [trigger sources](20-animation-react.md) call it. The table
(`tools/parse_abilities.py::REACTION_TYPES`):

| Ability effect type | React | Seq |
|---|---|---|
| Physical (1, 4, 5, 6, 7) — evading | `evade` | 0x18 |
| Physical (1, 4, 5, 6, 7) — hit | `taking_damage` | 0x19 |
| Item / Throwing (2, 3) — height-driven | `shield_block_{high,mid,low}` | 0x58/0x59/0x5a |
| Magic healing / Raise (0xb, 0xd) | `receive_heal` | 0x1b |
| Support / Movement / Buffs (8, 9, 10) | (none — no react) | — |
| Default damage spell | `taking_damage` or `receive_heal` (HP delta) | 0x19 or 0x1b |

The mapping is baked into ability data at parse time
(`tools/parse_abilities.py:412-413`) as `target_reaction_type`. The
trigger pathway never sees the seq id directly — it only knows the
ability id and reads the resolution.
_Avoid_: hardcoding seq ids in the trigger pathway (the only place that
knows seq ids is `ReactionType.get_seq_id(sprite_type, reaction_name)`
which reads `reaction_animations.json`); adding new react kinds without
extending both `ReactionType` and the parser's `REACTION_TYPES` table.

**React overlap** *(resolved by [ADR-0025])*:
**Newest wins.** When a new React arrives while another is in flight (or
multiple arrive in the same tick), `Unit.play_reaction_animation` restarts
the React [playback set](19-animation-playback.md) with the new animation. The
previous React's BODY / WEAPON / EFFECT counters are reset; the new
React's cascade takes over. Same rule for same-source repeats (three
hits in one tick = one flinch restarted twice, plus three damage popups
firing independently — see [Damage-popup trigger](20-animation-react.md))
and for cross-source overlap (a heal Effect react in flight when a
physical SEQ react lands = the SEQ react replaces the heal react). The
[ADR-0025] symmetric-set design makes restart cheap and unambiguous:
the React set's state is wholly separate from the normal set's, so
restart never touches the normal set's playbacks.

The parallelism hazard that drives `CombatLoop._trigger_projectile_reaction`'s
snapshot — *"since the GPU's live evade_type may have been overwritten
by a different attack by now"* — still applies to the GPU-side
`evade_type` read, but does **not** apply
to React animation state: the React set's playbacks own their own
counters and the newest-wins rule explicitly endorses the "stomp"
behavior. There is no React state to snapshot.

Also resolved: `CombatLoop._on_refresh_tile` (the Effect-react
*completion* trigger) calls `_on_react_complete()` on whichever React is
currently active. Under newest-wins, this is correct by construction —
the "currently active" React is by definition the most recent one, and
the trigger ends it. Cast A's `REFRESH_TILE` ending Cast B's in-flight
React is the same shape as any other newest-wins replacement.

_Avoid_: implementing a priority / queue / two-slot rule (newest-wins
is the resolved rule per [ADR-0025] — change it only via a superseding
ADR with a concrete gameplay scenario); reaching into React-set
playback state from outside the React subsystem (the React set is owned
by `Unit` and the React-set playbacks alone — same encapsulation rule
as the normal set).

#### Disambiguation — other "reaction" words in the codebase

The full picture lives in the [Combat-event resolution](21-combat-event-resolution.md)
cluster (six pathways, three reaction-ability families). The pointer here is so
a grep for "react" in this cluster lands somewhere useful: that cluster is the
**mechanic** side (damage / state changes), this cluster is the **rendering**
side (the React playback set + its triggers).

**Damage-popup trigger** *(distinct from React animation)*:
`action_flags` bit `0x10` (`ACTION_FLAG_HIT_REACTION` in
`EffectInstance.gd:40`) on a particle channel keyframe inside an
`E###.BIN` effect — fires damage-number popups and HP application logic,
**not** a React animation. The name is a historical naming collision
(both this flag and Effect react use the word "reaction"). Lives on the
same `action_flags` byte as the [Effect react trigger](20-animation-react.md)
(bit `0x40`); both can fire on the same keyframe, but their concerns are
independent.
_Avoid_: assuming `HIT_REACTION` triggers a React animation (it triggers
damage application + popups; `ABILITY_REACT` is the animation trigger);
treating the two flags as a pair just because they share a byte (they're
authored independently per keyframe).
