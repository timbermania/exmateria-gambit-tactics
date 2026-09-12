#[compute]
#version 450

// =============================================================================
// stage_damage.glsl — PASS_DAMAGE: apply queued damage / heals / breaks
//
// One thread per battle. Three phases:
//   1. AOE: any caster with U_AOE_ABILITY_ID >= 0 distributes its effect over
//      tiles within Manhattan radius `effect_area`. Damage queues into
//      U_PENDING_DAMAGE; heals apply immediately; break formulas dispatch
//      through apply_break_effect.
//   2. Single-target: each unit's queued U_DAMAGE_TARGET + U_DAMAGE_AMOUNT
//      moves into the target's U_PENDING_DAMAGE.
//   3. Resolve: subtract pending damage from HP, kill at <= 0.
//
// Dispatch: ceil(num_battles / 64) workgroups.
// =============================================================================

#include "res://src/gpu/shaders/combat_common.glslinc"
#include "res://src/gpu/shaders/combat_combat.glslinc"

bool is_break_formula(int formula_id) {
    return formula_id == 43 || formula_id == 44 || formula_id == 37
        || formula_id == 10 || formula_id == 11 || formula_id == 56
        || formula_id == 42 || formula_id == 80;
}

// TRANSPARENT AOE-reveal consume. If the unit holds STATUS_TRANSPARENT and
// pending_damage > 0 from an AOE bleed (single-target damage queues can't
// reach a transparent unit — the target filter in find_unit_by_criteria
// shields it), clear the bit + its timer slot before damage resolves. Undead
// carriers are NOT revealed: positive pending under STATUS_UNDEAD inverts to
// a heal in Phase 3 (and the undead-overdraw branch handles negative pending
// → damage on its own). Healing (pending < 0) doesn't break the bit either.
// Reads/writes go through the NEXT buffer to compose with same-tick decay
// from tick_status_timers without clobbering unrelated flag bits.
void try_consume_transparent_on_aoe(int battle_id, int u, int pending) {
    if (pending <= 0) return;
    if (has_status_next(battle_id, u, STATUS_UNDEAD)) return;
    if (!has_status_next(battle_id, u, STATUS_TRANSPARENT)) return;
    int flags_lo = read_unit_next(battle_id, u, U_STATUS_FLAGS_LO);
    write_unit(battle_id, u, U_STATUS_FLAGS_LO,
               flags_lo & ~(1 << STATUS_TRANSPARENT));
    for (int slot = 0; slot < 8; slot++) {
        int packed = read_unit_next(battle_id, u, U_STATUS_TIMER_0 + slot);
        if (packed != 0 && ((packed >> 24) & 0xFF) == STATUS_TRANSPARENT) {
            write_unit(battle_id, u, U_STATUS_TIMER_0 + slot, 0);
            break;
        }
    }
}

// RERAISE Stage A: lethal-damage capture. If the unit holds STATUS_RERAISE,
// flip FLAG_DEAD + HP=0 (so the CPU plays the dying→dead anim chain like a
// normal death) and stamp a fixed-tick revive deadline into U_TIMER. The
// STATUS_RERAISE bit stays SET — it doubles as the predicate the dead-unit's
// own stage_spell thread polls to open the revive cinematic (Stage B). The
// caller still treats this as "consumed" and skips its own kill bookkeeping.
// Returning true here means "this unit's death is owned by the reraise
// pathway; don't OR FLAG_DEAD a second time." The actual revive (HP refill,
// bit clear, FLAG_DEAD clear, cinematic teardown) lands in Stage B inside
// stage_spell.glsl after RERAISE_REVIVE_DELAY_TICKS has elapsed and the
// E007 first_hit_frame fires. Reads/writes go through NEXT so we observe
// upstream same-tick status decay from stage_compute without clobbering
// unrelated flag bits already written there. U_TIMER repurposing is safe
// because every consumer (stage_compute / stage_attack / stage_pathfind /
// stage_resolve / stage_post_conflict) gates on is_unit_dead before reading
// or decrementing it — see issue #107 design notes.
bool try_consume_reraise(int battle_id, int u) {
    if (!has_status_next(battle_id, u, STATUS_RERAISE)) return false;
    int flags = read_unit_next(battle_id, u, U_FLAGS);
    write_unit(battle_id, u, U_FLAGS, flags | FLAG_DEAD);
    write_unit(battle_id, u, U_HP, 0);
    int tick = get_battle_tick(battle_id);
    write_unit(battle_id, u, U_TIMER, tick + RERAISE_REVIVE_DELAY_TICKS);
    // Stage B's disambiguator: U_CASTING_ABILITY_ID == -1 means "this is a
    // reraise cinematic, not a normal spell cinematic." Clearing the cast
    // state here also covers the corner case where the carrier died mid-cast
    // (charging or projectile-in-flight) -- stage_spell would otherwise read
    // a stale ability id when the revive cinematic opens.
    write_unit(battle_id, u, U_CASTING_ABILITY_ID, -1);
    write_unit(battle_id, u, U_CAST_TARGET, -1);
    return true;
}

void apply_damage(int battle_id) {
    int tick = get_battle_tick(battle_id);

    // Phase 1: AOE distribution.
    for (int u = 0; u < config.units_per_battle; u++) {
        int aoe_ability_id = read_unit_next(battle_id, u, U_AOE_ABILITY_ID);
        if (aoe_ability_id < 0) continue;

        int center_x = read_unit_next(battle_id, u, U_AOE_CENTER_X);
        int center_z = read_unit_next(battle_id, u, U_AOE_CENTER_Z);
        int effect_area = get_ability_effect_area(aoe_ability_id);
        int caster_team = read_unit_next(battle_id, u, U_TEAM);
        int formula_id = get_ability_formula_id(aoe_ability_id);
        bool healing = is_ability_healing(aoe_ability_id);
        bool is_break = is_break_formula(formula_id);

        for (int t = 0; t < config.units_per_battle; t++) {
            if ((read_unit_next(battle_id, t, U_FLAGS) & FLAG_DEAD) != 0) continue;

            // 🔴 COLUMN-WIDE, AND THAT IS A KNOWN DEFECT CARRIED ON PURPOSE.
            // The ROM bounds an AoE vertically: its effect-grid builder
            // FUN_8017B874 collapses the column against the AIMED CELL's own
            // height and erases anything beyond `vertical` levels of it, for 324
            // of 368 abilities. A spell landing on a bridge deck does not reach
            // the moat below. See ADR-0224's 2026-09-05 amendment, which retracts
            // dec. 6's column-wide ruling.
            //
            // This loop still reads no level. The port's replacement rule is #845,
            // informed by the live PCSX arm #844, and it is not decided here --
            // so do not add `&& t_level == center_level` on your own authority.
            // `U_AOE_CENTER_X/Z` gain a level under the amendment (dec. 4 reopens);
            // until they do, `center_level` does not exist to compare against.
            int tx = read_unit_next(battle_id, t, U_POS_X);
            int tz = read_unit_next(battle_id, t, U_POS_Z);
            int dist = abs(tx - center_x) + abs(tz - center_z);
            if (dist > effect_area) continue;

            int target_team = read_unit_next(battle_id, t, U_TEAM);
            // ADR-0049: hit policy from ROM dont_hit_* flags, not from
            // is_ability_healing inference. FFT canon defaults to friendly
            // fire on; per-ability carve-outs (Bio: no caster, etc.) come
            // through ABFLAG_HIT_NO_*.
            if (!hit_policy_allows(aoe_ability_id, u, caster_team, t, target_team))
                continue;

            if (is_break) {
                apply_break_effect(battle_id, u, t, aoe_ability_id, tick);
            } else if (healing) {
                int heal_amount = calculate_spell_damage(battle_id, u, t, aoe_ability_id);
                if (has_status(battle_id, t, STATUS_UNDEAD)) {
                    // Undead: heal converts to damage. Phase 3 resolves it
                    // through pending_damage (which also picks up the inverted
                    // sign for damage-against-undead → heal).
                    int pending = read_unit_next(battle_id, t, U_PENDING_DAMAGE);
                    write_unit(battle_id, t, U_PENDING_DAMAGE, pending + heal_amount);
                } else {
                    int current_hp = read_unit_next(battle_id, t, U_HP);
                    int max_hp = read_unit_next(battle_id, t, U_MAX_HP);
                    write_unit(battle_id, t, U_HP, min(max_hp, current_hp + heal_amount));
                }
            } else {
                int damage = calculate_spell_damage(battle_id, u, t, aoe_ability_id);
                // Issue #117 -- attacker-side Strengthen-Elem (BoostElem) on
                // the AOE caster, BEFORE the target-side defense. Mirrors ROM
                // FUN_80185FFC ordering: pre-mitigation scaling runs from the
                // formula handler before FUN_80186FF8 / FUN_80184E98.
                int aoe_element_id = get_ability_field(aoe_ability_id, AB_ELEMENT);
                damage = apply_strengthen_elem(battle_id, u, aoe_element_id, damage);
                // Issue #110 -- target-side element defense scales BEFORE
                // pending lands, composes with the undead-invert in Phase 3.
                damage = apply_element_defense(battle_id, t, aoe_ability_id, damage);
                int pending = read_unit_next(battle_id, t, U_PENDING_DAMAGE);
                write_unit(battle_id, t, U_PENDING_DAMAGE, pending + damage);
                write_unit(battle_id, t, U_REACTION_TIMER, TICKS_PER_REACTION);
                // Issue #98 tracer -- damage-and-status AOE spells OR the
                // resolved mask onto each in-radius target. INFLICT_MODE_NONE
                // / mask==0 no-ops, so this is free for pure damage spells.
                apply_inflict_all(battle_id, u, t,
                                  get_ability_inflict_mask(aoe_ability_id),
                                  get_ability_inflict_mode(aoe_ability_id), tick);
            }
        }

        write_unit(battle_id, u, U_AOE_CENTER_X, -1);
        write_unit(battle_id, u, U_AOE_CENTER_Z, -1);
        write_unit(battle_id, u, U_AOE_ABILITY_ID, -1);
    }

    // Phase 1.5: per-tick HP delta for the POISON / REGEN status category
    // (status_system.md §2). Every POISON_TICK_INTERVAL ticks, each living
    // unit holding either bit queues max_hp / POISON_HP_DIVISOR into its own
    // U_PENDING_DAMAGE — POISON as positive (damage), REGEN as negative
    // (heal). Phase 3 below resolves both together, including the
    // STATUS_UNDEAD invert: positive pending heals undead (poison-undead =
    // heal), negative pending damages undead (regen-undead = damage). The
    // signs cancel cleanly if a unit somehow holds both bits at once.
    // 🔴 Status duration is owned by tick_status_timers in stage_compute, and
    // NOTHING REGISTERS A TIMER -- `set_status_with_timer` has no call sites, so
    // the flag never clears and these ticks never stop. POISON_HP_DIVISOR = 8 at
    // POISON_TICK_INTERVAL = 30 means a poisoned unit dies in 240 ticks, always.
    // See docs/status-conformance.md (#1105) finding 1.
    if (tick > 0 && (tick % POISON_TICK_INTERVAL) == 0) {
        for (int u = 0; u < config.units_per_battle; u++) {
            if (is_unit_dead(battle_id, u)) continue;
            bool poisoned = has_status_next(battle_id, u, STATUS_POISON);
            bool regen    = has_status_next(battle_id, u, STATUS_REGEN);
            if (!poisoned && !regen) continue;
            int max_hp = read_unit_next(battle_id, u, U_MAX_HP);
            int delta = max(1, max_hp / POISON_HP_DIVISOR);
            int signed_delta = 0;
            if (poisoned) signed_delta += delta;
            if (regen)    signed_delta -= delta;
            if (signed_delta == 0) continue;
            int pending = read_unit_next(battle_id, u, U_PENDING_DAMAGE);
            write_unit(battle_id, u, U_PENDING_DAMAGE, pending + signed_delta);
        }
    }

    // Phase 2: queued single-target damage. Issue #110 -- element absorb at the
    // queue site can yield a negative `amount` (sign-flipped heal); the
    // pending-damage convention already accepts <0 (heal), so pass it through.
    // Only fire REACTION_TIMER on actual damage; the flinch animation is wrong
    // for an absorb-converted heal.
    for (int u = 0; u < config.units_per_battle; u++) {
        if (is_unit_dead(battle_id, u)) continue;

        int target = read_unit_next(battle_id, u, U_DAMAGE_TARGET);
        int amount = read_unit_next(battle_id, u, U_DAMAGE_AMOUNT);

        if (target >= 0 && amount != 0 && !is_unit_dead(battle_id, target)) {
            int pending = read_unit_next(battle_id, target, U_PENDING_DAMAGE);
            write_unit(battle_id, target, U_PENDING_DAMAGE, pending + amount);
            if (amount > 0) {
                write_unit(battle_id, target, U_REACTION_TIMER, TICKS_PER_REACTION);
            }
        }
    }

    // Phase 2.5: REACT_COUNTER — if a defender about to take queued melee
    // damage has Counter equipped and the attacker is adjacent, queue a
    // basic-attack retaliation on the attacker. Only one counter per defender
    // per tick. Counter damage = defender's PA * WP, halved by attacker's
    // Protect. Both hits resolve together in Phase 3, so a Counter-equipped
    // attacker can't counter-the-counter within the same tick (the attacker's
    // reaction check fires next tick on whatever it took).
    for (int u = 0; u < config.units_per_battle; u++) {
        if (is_unit_dead(battle_id, u)) continue;
        int target = read_unit_next(battle_id, u, U_DAMAGE_TARGET);
        int amount = read_unit_next(battle_id, u, U_DAMAGE_AMOUNT);
        if (target < 0 || amount <= 0 || is_unit_dead(battle_id, target)) continue;

        int target_reaction = read_unit_next(battle_id, target, U_REACTION_ABILITY);
        if (target_reaction != REACT_COUNTER) continue;

        int dx = abs(read_unit_next(battle_id, u, U_POS_X) - read_unit_next(battle_id, target, U_POS_X));
        int dz = abs(read_unit_next(battle_id, u, U_POS_Z) - read_unit_next(battle_id, target, U_POS_Z));
        if (dx + dz != 1) continue;  // adjacency required

        int pa = read_unit_next(battle_id, target, U_PA);
        int wp = read_unit_next(battle_id, target, U_WP);
        int counter = max(1, pa * wp);
        if (has_status(battle_id, u, STATUS_PROTECT)) counter = max(1, counter / 2);
        // Issue #116 -- counter-attacks dispatch the same 01_Weapon /
        // 02_SpellWeapon formula handlers (ram:80188B14 / ram:80188BAC)
        // as the primary swing, so the counterer's weapon element applies
        // against the original attacker's element defenses via the same
        // FUN_80186FD0 wrapper at ram:80186FD0 (equipment matrix only, no
        // status overlay).
        int target_w_element = read_unit_next(battle_id, target, U_WEAPON_ELEMENT);
        // Issue #117 -- attacker-side Strengthen-Elem (BoostElem) on the
        // counterer's weapon swing. Same FUN_80185FFC pre-mitigation as the
        // primary swing; the counter is just another formula-handler call.
        counter = apply_strengthen_elem(battle_id, target, target_w_element, counter);
        counter = apply_weapon_element_defense(battle_id, u, target_w_element, counter);

        int attacker_pending = read_unit_next(battle_id, u, U_PENDING_DAMAGE);
        write_unit(battle_id, u, U_PENDING_DAMAGE, attacker_pending + counter);
        write_unit(battle_id, u, U_REACTION_TIMER, TICKS_PER_REACTION);
    }

    // Phase 3: resolve all pending damage, with defender-side reactions.
    // Reactions handled here are the ones that don't need attacker context:
    //   REACT_MANA_SHIELD — drain MP first, then any overflow hits HP.
    //   REACT_ABSORB_MP   — gain MP equal to damage_after_shield / 4.
    //   REACT_AUTO_POTION — heal AUTO_POTION_HEAL_AMOUNT if surviving HP drops below max/4.
    // Tier 2 #10 — STATUS_UNDEAD inverts pending damage into a heal. Heals
    // from upstream stages already inverted to pending damage on undead
    // targets (see Phase 1, stage_compute, stage_spell). Reactions are
    // skipped when inversion fires — they assume HP loss.
    // Counter / First Strike / Blade Grasp / Arrow Guard require attacker
    // bookkeeping and live in their own commit.
    // Pending convention: > 0 = damage (runs reactions), < 0 = heal (skips
    // reactions — you can't mana-shield a heal). REGEN routes through here
    // as negative pending so the undead invert (hp + pending) flips the sign
    // for free: regen on living = heal, regen on undead = damage.
    for (int u = 0; u < config.units_per_battle; u++) {
        int pending = read_unit_next(battle_id, u, U_PENDING_DAMAGE);
        if (pending == 0) continue;

        // The pacing knob's single choke point. EVERY HP transfer in the kernel
        // arrives here as pending -- physical, spell, AOE, counter, poison,
        // regen, and heals as negative -- so one multiply re-times the whole
        // damage economy without touching a formula. Scaling the SUM rather than
        // each contributing source also means one rounding per unit per tick
        // instead of one per source.
        pending = scale_hp_transfer(pending);

        // TRANSPARENT AOE-reveal: positive pending on a non-undead carrier
        // is an AOE bleed (named-target damage can't reach a transparent
        // unit). Clear the bit + timer slot before damage resolves; the
        // damage itself still applies. No-op if pending <= 0 or undead.
        try_consume_transparent_on_aoe(battle_id, u, pending);

        // Undead inversion: hp + pending flips both directions — positive
        // (damage) becomes heal, negative (regen) becomes damage and can
        // kill on overdraw.
        if (has_status_next(battle_id, u, STATUS_UNDEAD)) {
            int hp = read_unit_next(battle_id, u, U_HP);
            int max_hp = read_unit_next(battle_id, u, U_MAX_HP);
            int new_hp = hp + pending;
            if (new_hp <= 0) {
                if (!try_consume_reraise(battle_id, u)) {
                    int flags = read_unit_next(battle_id, u, U_FLAGS);
                    write_unit(battle_id, u, U_FLAGS, flags | FLAG_DEAD);
                    write_unit(battle_id, u, U_HP, 0);
                }
            } else {
                write_unit(battle_id, u, U_HP, min(max_hp, new_hp));
            }
            write_unit(battle_id, u, U_PENDING_DAMAGE, 0);
            continue;
        }

        // Heal-only branch for negative pending on living units. Skips
        // reactions and the death check (heals can't kill, only cap at
        // max_hp).
        if (pending < 0) {
            int hp = read_unit_next(battle_id, u, U_HP);
            int max_hp = read_unit_next(battle_id, u, U_MAX_HP);
            write_unit(battle_id, u, U_HP, min(max_hp, hp - pending));
            write_unit(battle_id, u, U_PENDING_DAMAGE, 0);
            continue;
        }

        int reaction = read_unit_next(battle_id, u, U_REACTION_ABILITY);

        if (reaction == REACT_MANA_SHIELD) {
            int mp = read_unit_next(battle_id, u, U_MP);
            int absorbed = min(mp, pending);
            if (absorbed > 0) {
                write_unit(battle_id, u, U_MP, mp - absorbed);
                pending -= absorbed;
            }
            if (pending <= 0) {
                write_unit(battle_id, u, U_PENDING_DAMAGE, 0);
                continue;
            }
        }

        if (reaction == REACT_ABSORB_MP && pending > 0) {
            int mp = read_unit_next(battle_id, u, U_MP);
            int max_mp = read_unit_next(battle_id, u, U_MAX_MP);
            int gained = min(max(0, max_mp - mp), pending / 4);
            if (gained > 0) write_unit(battle_id, u, U_MP, mp + gained);
        }

        int hp = read_unit_next(battle_id, u, U_HP);
        int new_hp = hp - pending;
        if (new_hp <= 0) {
            if (!try_consume_reraise(battle_id, u)) {
                int flags = read_unit_next(battle_id, u, U_FLAGS);
                write_unit(battle_id, u, U_FLAGS, flags | FLAG_DEAD);
                write_unit(battle_id, u, U_HP, 0);
            }
        } else {
            if (reaction == REACT_AUTO_POTION) {
                int max_hp = read_unit_next(battle_id, u, U_MAX_HP);
                if (new_hp < max_hp / 4) {
                    new_hp = min(max_hp, new_hp + AUTO_POTION_HEAL_AMOUNT);
                }
            }
            write_unit(battle_id, u, U_HP, new_hp);
        }
        write_unit(battle_id, u, U_PENDING_DAMAGE, 0);
    }

    // Phase 4: projectile-deferred healing (Tier 2 #11). tick_acting_animation
    // in stage_compute queues U_PENDING_HEAL_TARGET / U_PENDING_HEAL_AMOUNT on
    // the caster when a projectile-style healing spell fires; the
    // landing-frame application was scaffolded but never wired. Apply here so
    // the heal lands on the same tick stage_compute scheduled it. Undead
    // targets invert (heal → damage) the same way Phase 3 does.
    for (int u = 0; u < config.units_per_battle; u++) {
        if (is_unit_dead(battle_id, u)) continue;
        int heal_target = read_unit_next(battle_id, u, U_PENDING_HEAL_TARGET);
        int heal_amount = read_unit_next(battle_id, u, U_PENDING_HEAL_AMOUNT);
        if (heal_target < 0 || heal_amount <= 0) continue;
        if (is_unit_dead(battle_id, heal_target)) {
            write_unit(battle_id, u, U_PENDING_HEAL_TARGET, -1);
            write_unit(battle_id, u, U_PENDING_HEAL_AMOUNT, 0);
            continue;
        }

        if (has_status_next(battle_id, heal_target, STATUS_UNDEAD)) {
            int hp = read_unit_next(battle_id, heal_target, U_HP);
            int new_hp = hp - heal_amount;
            if (new_hp <= 0) {
                int flags = read_unit_next(battle_id, heal_target, U_FLAGS);
                write_unit(battle_id, heal_target, U_FLAGS, flags | FLAG_DEAD);
                write_unit(battle_id, heal_target, U_HP, 0);
            } else {
                write_unit(battle_id, heal_target, U_HP, new_hp);
            }
        } else {
            int hp = read_unit_next(battle_id, heal_target, U_HP);
            int max_hp = read_unit_next(battle_id, heal_target, U_MAX_HP);
            write_unit(battle_id, heal_target, U_HP, min(max_hp, hp + heal_amount));
        }
        write_unit(battle_id, u, U_PENDING_HEAL_TARGET, -1);
        write_unit(battle_id, u, U_PENDING_HEAL_AMOUNT, 0);
    }
}

void main() {
    uint battle_id = gl_GlobalInvocationID.x;
    if (battle_id >= uint(config.num_battles)) return;

    int result = get_battle_result(int(battle_id));
    if (result != RESULT_ONGOING && config.test_mode == 0) return;

    apply_damage(int(battle_id));
}
