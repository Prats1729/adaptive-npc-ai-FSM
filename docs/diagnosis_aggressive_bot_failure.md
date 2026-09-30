# Diagnosis: Adaptive FSM 0% Win Rate vs Aggressive Bot

## Date: 2026-09-30
## Status: Pre-change analysis — no code modified yet

---

## 1. Verified Baseline Results (from CSV: 150 episodes)

| Policy       | Basic FSM Win % | Adaptive FSM Win % |
|-------------|----------------|-------------------|
| Aggressive  | 12%  (3/25)    | 0%   (0/25)       |
| Defensive   | 80%  (20/25)   | 84%  (21/25)      |
| Random      | 92%  (23/25)   | 84%  (21/25)      |
| **Overall** | **61.3%**      | **56.0%**         |

---

## 2. Speed Analysis (the core asymmetry)

| Entity          | Walk Speed | Sprint Speed | Flee Speed |
|-----------------|-----------|-------------|-----------|
| Player          | 155 px/s  | 200 px/s    | N/A       |
| NPC (enemy)     | 130 px/s  | N/A         | 175 px/s  |

**Key finding:** The Aggressive Bot sprints at 200 px/s whenever distance
is between 130–350px (`player_bot.gd` line 81). The NPC's flee speed is
only 175 px/s. Therefore:

> **The NPC can never outrun the Aggressive Bot.**
> The player closes the gap at 25 px/s even during FLEE.

This means:
- `safe_distance` (250 px) is unreachable: the NPC flees at 175 while
  the player pursues at 200, so the NPC never establishes separation.
- With hysteresis (`safe_distance * 1.15 = 287.5 px`), this is even worse.
- FLEE becomes a permanent state that delays death but never creates a
  recovery opportunity.

---

## 3. Why Adaptive FSM is *worse* than Basic FSM vs Aggressive

### 3a. Raised flee threshold causes *earlier* retreat

The Adaptive FSM raises `flee_health_ratio` from 25% to up to 38% under
high aggression. Against the Aggressive Bot, aggression reaches HIGH very
quickly. This means:

- The Adaptive NPC flees at ~76 HP (38% of 200) instead of 50 HP (25%).
- It enters the unwinnable FLEE loop earlier, with more HP remaining.
- Those extra HP-ticks are wasted fleeing (dealing 0 damage) instead of
  trading attacks.

### 3b. Hit-and-run creates distance the NPC cannot recover

When `hit_and_run_active` triggers in ATTACK state, the NPC disengages at
flee_speed (175). But the player at sprint (200) immediately closes the
gap. The NPC wastes 0.5s fleeing + time re-closing distance, during which
the player gets free attacks. Net effect: negative DPS trade.

### 3c. Counter-offensive check is rarely useful

In FLEE, the Adaptive FSM checks `enemy.player.current_health <= enemy.current_health`
to counter-attack. Against the Aggressive Bot, the player almost always
has higher HP because the NPC spent time fleeing instead of attacking.
This condition rarely fires.

### 3d. Adaptive attack cooldown (Rule 2) was previously disabled

Rule 2 (reducing NPC attack cooldown from 0.80 to 0.65s under high
aggression) was re-enabled in a recent change. However, this violates
the fairness constraint: both entities should have equal attack cooldown.

**This must be reverted.**

---

## 4. CSV Evidence

Looking at Adaptive FSM vs Aggressive Bot episodes:

- Average NPC hits landed: **12.0** (vs Basic FSM: 13.3)
- Average player hits landed: **15.6** (vs Basic FSM: 16.3)
- Average state transitions: **14.1** (vs Basic FSM: 7.5)

The Adaptive FSM has ~2x the state transitions, confirming excessive
FLEE→IDLE→CHASE→ATTACK→FLEE cycling. It lands fewer hits because it
spends more time fleeing and repositioning.

---

## 5. Root Cause Summary

**The Adaptive FSM's raised flee threshold causes the NPC to enter
FLEE earlier against the Aggressive Bot. Because the player sprints
faster (200px/s) than the NPC flees (175px/s), FLEE never reaches
safe_distance, creating an infinite chase loop. The NPC deals zero
damage while fleeing, so it dies with certainty.**

The Basic FSM (25% flee threshold) performs slightly better because it
stays in ATTACK longer, trading more hits before the inevitable death.

---

## 6. Proposed Single Change

**Do not raise the flee threshold when the NPC cannot outrun the
pursuer.**

Specifically: in `_process_flee_state`, if the Adaptive FSM detects
that distance is *not increasing* (i.e., the player is closing faster
than the NPC can flee), abandon FLEE and re-engage in ATTACK/CHASE.

This is a fair, explainable rule:
- It does not change HP, damage, range, or cooldown.
- It observes the actual game state (distance trend) and adapts.
- It prevents the "permanent losing loop" described in the prompt.
- It produces a clear explainability log:
  "Adaptive: Retreat ineffective — pursuer closing at >flee speed.
   Re-engaging to trade damage."

Additionally: **revert Rule 2 (adaptive attack cooldown)** to maintain
equal combat parameters.

---

## 7. Also Required: Revert Unfair Rule 2

The adaptive attack cooldown reduction (0.80 → 0.65s) violates the
fairness rules ("Keep player and NPC attack cooldown equal"). This
must be reverted before running the benchmark.
