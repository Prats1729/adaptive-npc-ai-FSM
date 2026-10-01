# Autonomous Guard AI in Stealth Games — Project Instructions

## Project Title
**Explainable Autonomous Guard AI in Stealth Games: Replicating Composite Potential Fields and Mitigating Reactive Pursuit Lag**

## Base Research Paper
- **Title:** *Generic Guard AI in Stealth Game with Composite Potential Fields*
- **Authors:** Kaijie Xu, Clark Verbrugge (McGill University)
- **Venue:** AIIDE 2025 / arXiv:2508.18527

---

## Project Goal
1. Build a faithful, independent computational reproduction of the 2D grid benchmark and 60-second capture experiment from Xu & Verbrugge (2025).
2. Implement and evaluate the paper's primary decision models:
   - **Baseline FSM** (Finite State Machine: Patrol, Investigate, Chase, Return)
   - **Composite Potential Field (CPF)** (Merging Information, Confidence, and Connectivity potential fields with dynamic weight scheduling)
3. Address key scientific research gaps identified in the base paper:
   - **Gap 1 (The Reactive Lag Flaw):** Fast players (+20% speed) exploit historical scent trails. Solution: **PI-PF (Predictive Interception Potential Field)** using velocity vector lookahead.
   - **Gap 2 (The Hand-Tuned Heuristic Flaw):** Manually tuned weight hyperparameters. Solution: **RL-Q (Reinforcement Learning Q-Agent)** optimizing spatial transitions via Bellman equations.
4. Provide verifiable empirical data through reproducible Monte-Carlo simulations, exportable CSV logs, and an interactive evaluation dashboard comparing results against the paper's Table 3.

---

## Environment & Map Specifications
Recreated from the base paper's exact topological dimensions:
- `Test Maze` ($20 \times 20$, 206 walkable, 194 wall tiles, 52% walkable) — High dead-end maze benchmark.
- `Miami` ($26 \times 21$, 377 walkable, 169 wall tiles, 69% walkable) — Top-down stealth level inspired by *Hotline Miami*.
- `Arkham` ($28 \times 26$, 548 walkable tiles, 75% walkable) — *Batman: Arkham Asylum* inspired layout.
- `The Last of Us` ($14 \times 30$, 255 walkable tiles, 61% walkable).
- `Dishonored` ($26 \times 39$, 726 walkable tiles, 72% walkable).

---

## Agent Mechanics & Experimental Rules
- **Guard Senses:** Bresenham Line-of-Sight (LOS) raycasting. Line of sight blocked by wall tiles.
- **Guard Team:** 3 guards initialized outside the player's starting line of sight.
- **Player Bot:** MaxMin lookahead evasion agent with a +20% speed bonus (120% guard speed), actively maximizing BFS distance from all guards.
- **Trial Duration:** 60 seconds (120 game ticks at $\Delta t = 0.5\text{s}$).
- **Capture Condition:** Any guard enters the same cell as the player.
- **Success Metric:** Capture Rate ($CR$), Mean Capture Time ($CT \pm \sigma$), and Backtracking Frequency ($B \pm \sigma$).

---

## Project Structure
```text
adaptive-npc-ai/
  data/
    benchmark_miami.csv           # 200 empirical simulation runs
    benchmark_test_maze.csv       # 200 empirical simulation runs
  docs/
    stealth_dashboard.html        # Interactive Chart.js comparative evaluation dashboard
  maps/
    test_maze.json
    miami.json
    arkham.json
    tlou.json
    dishonored.json
  scripts/
    stealth/
      grid_environment.py         # 2D Grid, Bresenham LOS, BFS distance matrix
      player_maxmin.py            # MaxMin lookahead distance-maximization evasion
      guard_fsm.py                # Base paper FSM baseline (Patrol, Investigate, Chase, Return)
      guard_cpf.py                # Base paper Composite Potential Field (I + C + N)
      guard_pipf.py               # Novel Model 1: Predictive Interception Potential Field
      guard_rl.py                 # Novel Model 2: Reinforcement Learning Q-Agent
      experiment_runner.py        # Automated Monte-Carlo capture experiment runner
    tools/
      build_maps.py               # Procedural map builder matching paper dimensions
  run_stealth_benchmark.py        # Benchmark CLI entry point
  RESEARCH_GAP_AND_ROADMAP.md     # Mathematical formulations, research gaps, literature review
  Summary.md                      # Game AI literature summaries
```

---

## Evaluation Metrics (Targeting Base Paper Table 3)
1. **Capture Rate ($CR$):** Fraction of 50 trials where guards successfully capture the player within 60s.
2. **Mean Capture Time ($CT$):** Time in seconds to capture (lower indicates more decisive pursuit).
3. **Backtracking Rate ($B$):** Number of times guards reverse direction within 2 consecutive steps (measuring patrol oscillation).