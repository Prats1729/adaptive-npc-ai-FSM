# Adaptive NPC AI — Project Instructions

## Project title

**Explainable Adaptive NPC Decision-Making Using Finite State Machines in a 2D Game Simulation**

## Project goal

Build a small, demonstrable Godot 4.7 2D simulation in which an enemy NPC makes decisions through a Finite State Machine (FSM).

The project must compare:

1. A **basic FSM** with fixed decision rules.
2. An **adaptive FSM** that modifies selected decision thresholds based on the player’s observed behaviour.

The project must make each NPC decision explainable through on-screen messages and/or a saved event log.

This is an AI mini-project, not a commercial game. Prioritise AI behaviour, automated experimentation, data logging, evaluation, and a clean viva demonstration over visuals or game features.

## Professor’s mini-project expectations

The professor’s document says the project must:

- Demonstrate a practical AI application.
- Have sufficient scope for implementation and experimentation.
- Use an appropriate dataset or data source.
- Use suitable AI methods/models.
- Include measurable performance evaluation and analysis.
- Clearly present: problem statement, objectives, methodology, implementation, evaluation metrics, results, and conclusion.
- Avoid projects that are only a basic website, database, or simple API integration without meaningful AI experimentation.

This project is aligned with Classical AI and game-AI decision-making. The data source will be reproducible, simulation-generated gameplay logs. Public game-AI datasets and papers are used for the literature review, not copied directly into the implementation.

## Technology constraints

- Engine: Godot 4.7.x
- Language: GDScript
- Platform: Windows desktop
- Project type: simple 2D top-down arena
- Use basic shapes, labels, and built-in nodes; do not require paid assets.
- Do not use 3D, multiplayer, login systems, inventories, quests, external APIs, or complex art.
- Keep every script small, modular, documented, and easy for students to explain in a viva.
- Do not add plugins or large dependencies unless explicitly requested.

## Minimal playable simulation

The simulation needs:

- One compact 2D arena with boundaries and a few obstacles.
- One player entity.
- One enemy NPC.
- Health values for both entities.
- A visual label showing the NPC’s current state.
- A visible decision/explanation log.
- Start/reset controls.
- Optional automated simulation mode.

Use coloured circles, rectangles, or placeholder sprites. Functional AI matters more than graphics.

## NPC state machine

The enemy NPC must have these states:

- `PATROL`: move between fixed patrol points.
- `CHASE`: move toward the player when detected.
- `ATTACK`: attack when within attack range.
- `RETREAT`: move away when health is low or the player is too aggressive.

Core transitions:

- PATROL → CHASE: player enters detection range.
- CHASE → ATTACK: player enters attack range.
- ATTACK → CHASE: player moves outside attack range.
- Any state → RETREAT: NPC health drops below the retreat threshold.
- RETREAT → PATROL or CHASE: NPC recovers, becomes safe, or player is no longer nearby.

Every transition must record a human-readable reason, for example:

`CHASE → ATTACK: player distance is 32px, inside 40px attack range`

## Baseline system

Implement the basic FSM first.

Its thresholds remain fixed throughout all episodes. Example values:

- Detection range: 180 pixels
- Attack range: 40 pixels
- Retreat threshold: 25% NPC health

Do not start adaptive logic until this version is working and tested.

## Adaptive system

After the basic FSM works, implement a lightweight adaptive rule-based version.

The NPC should track a simple player-aggression score, based on observations such as:

- Number of player attacks in a recent time window.
- Damage received by the NPC.
- How often the player approaches the NPC.

Example adaptive behaviour:

- If player aggression is high, increase NPC retreat threshold from 25% to 40%.
- If player remains far away for a sustained period, slightly increase detection range.
- If player attacks frequently at close range, shorten retreat recovery time.

Be precise in naming: this is an **adaptive rule-based FSM**, not reinforcement learning.

Do not add Q-learning or deep reinforcement learning unless the baseline, adaptive version, logging, and evaluation are already complete.

## Automated experimentation and data

The project must not rely only on manual play.

Implement simple player-bot behaviour modes:

- Aggressive: moves toward and attacks the NPC.
- Defensive: keeps distance and retreats.
- Random: moves unpredictably.
- Optional balanced mode.

Run repeated episodes for both systems under the same scenarios. Save one CSV row per episode.

Suggested CSV fields:

```text
episode_id,
system_type,
player_bot_type,
npc_survival_time,
player_survival_time,
npc_won,
player_won,
npc_hits,
player_hits,
state_transition_count,
average_response_time,
final_adaptive_retreat_threshold,
final_adaptive_detection_range
```

The simulation-generated CSV is the project’s primary data source.

## Evaluation

Compare Basic FSM and Adaptive FSM using:

- NPC survival time
- NPC win rate
- Player win rate
- NPC hits delivered
- Player hits delivered
- Number of state transitions
- Average decision/response time
- Behaviour under aggressive, defensive, and random player bots

Generate simple graphs after collecting data. At minimum include:

1. Win-rate comparison.
2. Average NPC survival-time comparison.
3. State distribution or state-transition comparison.

Do not make unsupported claims. Present limitations honestly.

## Explainability requirement

The project title includes “Explainable.” Therefore, explanations are essential.

Every state change must show:

- Previous state
- New state
- Trigger/reason
- Relevant values, such as distance, health, or aggression score

Example:

```text
RETREAT selected
Reason: NPC health = 35%, player aggression = high
Adaptive retreat threshold = 40%
```

## Suggested project structure

```text
adaptive-npc-ai/
  project.godot
  AGENTS.md
  scenes/
    arena.tscn
    player.tscn
    enemy_npc.tscn
  scripts/
    arena.gd
    player.gd
    player_bot.gd
    enemy_npc.gd
    enemy_fsm.gd
    adaptive_logic.gd
    simulation_runner.gd
    csv_logger.gd
  data/
    simulation_results.csv
  docs/
    diagrams/
```

Avoid having multiple team members edit the same `.tscn` scene at the same time.

## Team and Git rules

- Use GitHub.
- Work in branches; make small commits with clear messages.
- Keep `main` playable.
- One team member owns integration of `arena.tscn`.
- Never overwrite or delete existing working files without checking first.
- Add `.godot/` to `.gitignore`.
- Do not commit exported builds, caches, or large generated files unless explicitly needed.

## Research direction

Use these works for the literature review; do not replicate them:

- Damian Isla, *Handling Complexity in the Halo 2 AI* — FSM/HFSM and behaviour-tree context.
- Iovino et al., *A Survey of Behavior Trees in Robotics and AI*.
- Mnih et al., *Human-level Control Through Deep Reinforcement Learning*.
- Vinyals et al., *StarCraft II: A New Challenge for Reinforcement Learning*.
- Vinyals et al., *Grandmaster Level in StarCraft II Using Multi-Agent Reinforcement Learning*.
- Kurach et al., *Google Research Football: A Novel Reinforcement Learning Environment*.
- Lin et al., *STARDATA: A StarCraft AI Research Dataset*.
- Guss et al., *MineRL: A Large-Scale Dataset of Minecraft Demonstrations*.

These papers motivate state-based game decisions, adaptive AI, repeatable game simulations, and gameplay data. The submitted system must remain a small, original, explainable Godot simulation.

## Development order

1. Create and save the `Arena` scene.
2. Add player movement and arena boundaries.
3. Add enemy NPC movement and health.
4. Implement and test basic FSM states.
5. Add state/reason display.
6. Add player bots and automated episode reset.
7. Save CSV logs.
8. Add adaptive FSM rules.
9. Run experiments and create graphs.
10. Prepare report, screenshots, state diagram, and demo.

## Agent behaviour rules

When modifying this project:

- First inspect the current files and preserve existing working functionality.
- Make the smallest practical change.
- Implement one milestone at a time.
- Explain what files were added/changed and how to test them.
- Prefer code that is explicit and readable over clever or complex code.
- Never claim a method is machine learning, reinforcement learning, or dataset-trained unless it actually is.
- Stop and ask before introducing major scope changes.