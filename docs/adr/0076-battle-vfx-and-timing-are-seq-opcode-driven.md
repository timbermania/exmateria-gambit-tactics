# Battle VFX and timing are SEQ-opcode-driven; the animation stream is the clock

Every battle **visual / audio / timing event** — a hit cloud, an impact flash, a
projectile launch, a spell effect, a reaction pose, a screen distort, a sound cue
— is triggered by the SEQ (or effect-file) **opcode that owns it**, reached as the
attacker's/effect's animation stream advances. It is **not** triggered by a damage
event, a GPU-state edge, an ability formula, or "an effect file exists" as a
shortcut. A damage event may *inform* an opcode-triggered event (hit/miss/evasion
attribution) but must never *be* its trigger. This generalises the reverse-
engineered truth that FFT fires its non-`E###.BIN` impact VFX from SEQ opcode
`0xDE` (`PostGenericAttack`, `FUN_8006894c`) at the hit frame, and only the anims
that carry the opcode produce the effect.

## Status

accepted

## Context

The port already had the faithful mechanism wired — `AnimationPlayback` walks a
unit's SEQ each frame and emits a `side_effect` when it crosses an opcode
(`POST_GENERIC_ATTACK`, `QUEUE_SPRITE_ANIM`, `QUEUE_THROW_ANIMATION`,
`SET_LAYER_PRIORITY`), and the loop reacts to it. But the generic **melee hit
cloud** was spawned a different way: damage-event-driven, in
`CombatLoop._apply_hp_change`, keyed only on `delta < 0` with **no animation
gate**. That divergence is the reason this ADR exists — it fired for any
non-projectile damaging ability whose anim lacks `0xDE` (e.g. Dash), producing a
hit cloud FFT never shows.

Investigating it (see `docs/VFX_TRIGGER_ARCHITECTURE.md`) turned up that the
damage path was doubly wrong: its attacker attribution scanned the one-frame
`damage_target` pulse, which is already cleared by the time `_apply_hp_change`
reads it (`attacker_idx` is routinely `-1`), and a killing blow suppresses
`HP_CHANGED` entirely (only `DIED` is emitted) — so the cloud both mis-fired for
non-strike anims *and* failed to fire on lethal hits. The opcode-driven trigger
has neither problem: it fires from the attacker's own animation, attributes via
the opcode's target, and is indifferent to whether the blow kills.

The broader survey classified every battle trigger into five mechanisms. Two are
the faithful "opcode is the clock": **(A)** the runtime SEQ walk, and **(B)**
precomputed opcode timing — `tools/parse_seq.py` walks the SEQ *once at load* and
bakes per-anim `damage_frame` / `projectile_frame` / `move_start_frame` into a GPU
buffer the compute shader consumes. (B) is **not** a bypass; it is the GPU firing
the *same* opcode tick without re-walking it per frame. The other three
(damage-event, GPU-state-edge, formula/has-effect-file) are shortcuts, and are
divergences wherever FFT would have used an opcode.

This is the presentation-side companion to
[ADR-0031](0031-battle-state-is-gpu-authoritative.md). ADR-0031 says the GPU owns
battle *state* and the CPU derives presentation from it. This ADR says *when* that
presentation fires: the opcode stream is the clock, not the state deltas.

## Decision

- **The owning opcode is the trigger.** A battle visual/audio/timing event fires
  from the SEQ or effect-file opcode that owns it, in one of exactly two faithful
  forms:
  - **(A) Runtime walk** — `AnimationPlayback` crosses the opcode and emits a
    `side_effect`; the loop reacts (e.g. `POST_GENERIC_ATTACK` →
    `_trigger_physical_reaction` → hit cloud + reaction pose + impact SFX).
  - **(B) Precomputed opcode timing** — the SEQ is walked once at load, the opcode
    tick is baked into the GPU timing buffer, and the compute shader fires it at
    that `anim_frame`. Consuming a baked opcode tick counts as opcode-driven.
- **Damage events inform, they do not trigger.** A CPU consumer may read an HP
  delta to answer "did this land / hit or miss / which evasion" and feed that into
  an opcode-triggered event. It may not spawn a visual *because* HP changed.
- **Formula / effect-file existence selects the handler, not the moment.** Which
  hit-cloud handler runs (dust vs Knight-Break triangles vs elemental puff) is a
  formula/target-data decision inside `EffectManager`; *whether and when* the
  cloud spawns is the opcode's call. There is no "generic" catch-all tier.
- **Sanctioned non-opcode triggers are enumerated exceptions.** The GPU-
  authoritative cinematic lifecycle (ADR-0031) spawns/tears its `EffectInstance`
  on the `cinematic_timer` snapshot edge — and even that edge is set by opcode
  timing. Any new non-opcode trigger must cite this ADR and justify itself; the
  default review answer is "route it through the owning opcode."

## Alternatives considered

- **Damage-event-driven VFX for "obviously physical" hits (rejected).** The shape
  the melee hit cloud took — "we're in the HP handler anyway, spawn the cloud
  here." It looks local every time, but it drops the animation gate (the whole
  point of `0xDE` is that only 40/227 anims carry it) and rides an attribution
  pulse that isn't there. This is the failure mode the ADR retires.
- **A GPU-buffer `has_0xDE` flag as the gate (rejected).** The precomputed timing
  sidecar can't answer "does this anim carry `PostGenericAttack`?" — its
  `damage_frame` falls back to `throw_frame | t//2` when the opcode is absent,
  erasing the `-1` sentinel (`parse_seq.py`). The runtime side-effect already
  fires only for the 40 carriers; re-deriving the gate from the baked buffer would
  be both redundant and wrong.
- **Leave the rule implicit (rejected).** It was implicit, and the hit cloud
  diverged for the entire life of the import. Naming it makes the next
  `if delta < 0: spawn_effect()` a review failure instead of a silent shortcut.

## Consequences

- The generic melee hit cloud now spawns from `_trigger_physical_reaction` on the
  `POST_GENERIC_ATTACK` opcode, deduped against the deferred break/holy-sword trap
  (`fire_pending_trap` returns whether it fired). The `_apply_hp_change` spawn is
  deleted. Guards: `tests/GPUMeleeHitCloudTest` (strike → one cloud) and
  `tests/GPUDashNoHitCloudTest` (Dash damage → zero clouds).
- A new battle effect must identify its owning opcode before it has a home. If FFT
  fires it from a SEQ/effect-file opcode, the port fires it from the matching
  `AnimationPlayback` side-effect or a baked timing tick — not from a convenient
  CPU callback that happens to know the target.
- The **deferred break/holy-sword trap** and the hit cloud are now understood to be
  the *same* opcode event (both at `0xDE`), split only historically. Unifying them
  to one spawn point is a sanctioned follow-up (it touches shipped break tests);
  the `fired_pending` dedup holds the invariant until then.
- A future non-opcode trigger (a new GPU-state edge, a damage-driven flourish) must
  cite this ADR and explain why it is an enumerated exception rather than a
  shortcut.

## References

- ADR-0031 — battle state is GPU-authoritative (this is its presentation-side
  companion: state authority vs trigger authority)
- ADR-0018 — GPU combat interpretation is a pure module the loop composes (the
  side-effect / snapshot-diff pattern these triggers ride on)
- ADR-0009 — Ordering Table depth is one model (sibling "one model" invariant)
- `docs/VFX_TRIGGER_ARCHITECTURE.md` — the supporting map: every trigger site, the
  A–E mechanism taxonomy, and the worked hit-cloud remediation
- `research/wiki_articles/hit_cloud_spawner_pipeline.txt` — the ROM ground truth
  (`0xDE` → `FUN_8006894c`, handler routing by target data)
