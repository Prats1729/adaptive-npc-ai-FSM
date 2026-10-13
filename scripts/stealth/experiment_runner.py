import os
import csv
import json
import math
import random
import statistics
from collections import deque

from .grid_environment import GridEnvironment
from .player_maxmin import MaxMinPlayer
from .player_safety_graph import SafetyGraphPlayer

# Paper Baseline Guard Models
from .guard_fsm import BaselineFSMGuard
from .guard_cpf import CompositePotentialFieldGuard
from .guard_random_walk import RandomWalkGuard
from .guard_staleness import StalenessFSMGuard
from .guard_cheat import CheatGuard

# Novel Modern AI Guard Models
from .guard_pipf import PredictiveInterceptionGuard
from .guard_rl import ReinforcementLearningGuard
from .guard_mcts import PotentialFieldGuidedMCTSGuard

class StealthExperimentRunner:
    def __init__(self, map_file_path, q_table_path=None):
        self.env = GridEnvironment(map_file_path)
        self.map_name = self.env.map_name
        self.q_table = None
        
        clean_map = self.map_name.lower().replace(" ", "_").replace("(", "").replace(")", "")
        target_q_path = q_table_path if q_table_path else f"data/q_table_{clean_map}.json"
        if os.path.exists(target_q_path):
            with open(target_q_path, "r") as f:
                self.q_table = json.load(f)

    def _create_guard(self, guard_type, seed):
        gt = guard_type.upper()
        if gt in ["FSM", "BASELINEFSM"]:
            return BaselineFSMGuard(self.env, random_seed=seed)
        elif gt in ["CPF", "POTENTIALFIELD", "POTENTIAL-FIELD", "PF"]:
            return CompositePotentialFieldGuard(self.env)
        elif gt in ["RANDOMWALK", "RANDOM", "RW"]:
            return RandomWalkGuard(self.env, random_seed=seed)
        elif gt in ["STALENESS", "STALENESSFSM"]:
            return StalenessFSMGuard(self.env, random_seed=seed)
        elif gt in ["CHEAT", "OMNISCIENT"]:
            return CheatGuard(self.env)
        elif gt in ["PI-PF", "PIPF", "PREDICTIVEPF"]:
            return PredictiveInterceptionGuard(self.env, prediction_horizon=2)
        elif gt in ["RL-Q", "RL", "Q-LEARNING", "MARL-Q"]:
            eps = 0.0 if self.q_table is not None else 0.05
            return ReinforcementLearningGuard(self.env, epsilon=eps, q_table=self.q_table, random_seed=seed)
        elif gt in ["APF-MCTS", "MCTS", "MCTS-PF"]:
            return PotentialFieldGuidedMCTSGuard(self.env, num_simulations=35, horizon=3, random_seed=seed)
        else:
            raise ValueError(f"Unknown guard type: {guard_type}")

    def _create_player(self, player_mode):
        if player_mode.lower() in ["safetygraph", "safety_graph", "safety"]:
            return SafetyGraphPlayer(self.env, speed_bonus=0.20)
        else:
            return MaxMinPlayer(self.env, lookahead_depth=3, speed_bonus=0.20)

    def run_single_capture_trial(self, guard_type, seed, num_guards=3, player_mode="MaxMin"):
        guard_positions, player_pos = self.env.initialize_positions(num_guards=num_guards, random_seed=seed)
        
        # Instantiate 3 Guard AIs matching Figure 1 in the paper
        guards = [self._create_guard(guard_type, seed + i * 17) for i in range(num_guards)]
        player = self._create_player(player_mode)
        
        # Capture Experiment Parameters from Base Paper Table 2
        player_hp = 3
        max_duration = 60
        guard_view_range = 6.4  # 80% of 8.0 base view range
        attack_range = 1.5
        
        guard_histories = [deque(maxlen=6) for _ in range(num_guards)]
        for i, g_pos in enumerate(guard_positions):
            guard_histories[i].append(g_pos)

        visited_cells = set(guard_positions)
        backtrack_counts = [0 for _ in range(num_guards)]
        min_distances = []
        captured = False
        capture_time = float(max_duration)
        first_detect_time = None
        
        for t in range(1, max_duration + 1):
            # 1. Check Line of Sight across guards
            any_sight = any(self.env.has_line_of_sight(g_pos, player_pos, guard_view_range) for g_pos in guard_positions)
            if any_sight and first_detect_time is None:
                first_detect_time = t

            # 2. Guards Move
            new_guard_positions = []
            for i, guard in enumerate(guards):
                curr_g = guard_positions[i]
                next_g = guard.select_action(curr_g, player_pos, guard_view_range, all_guards=guard_positions)
                
                # Track Backtracking for guard i: reversing direction within 2 consecutive steps
                if len(guard_histories[i]) >= 2 and next_g == guard_histories[i][-2]:
                    backtrack_counts[i] += 1
                    
                guard_histories[i].append(next_g)
                visited_cells.add(next_g)
                new_guard_positions.append(next_g)
                
            guard_positions = new_guard_positions
            
            # 3. Player Move (MaxMin or SafetyGraph with +20% speed bonus)
            player_pos = player.select_action(player_pos, guard_positions)
            if player.should_take_speed_bonus_step():
                player_pos = player.select_action(player_pos, guard_positions)

            # 4. Measure Metrics
            closest_dist = min(self.env.get_distance(g, player_pos) for g in guard_positions)
            min_distances.append(closest_dist)

            # 5. Attack / Damage Drain: -1 HP/sec for each guard whose attack range encompasses the player
            guards_in_attack_range = sum(
                1 for g in guard_positions 
                if math.hypot(g[0] - player_pos[0], g[1] - player_pos[1]) <= attack_range
            )
            if guards_in_attack_range > 0:
                player_hp -= guards_in_attack_range
                if player_hp <= 0:
                    captured = True
                    capture_time = float(t)
                    if guard_type.upper() in ["RL-Q", "MARL-Q"]:
                        for i, g in enumerate(guards):
                            g.update_q_value(guard_positions[i], player_pos, guard_view_range, is_captured=True)
                    break
                    
            if guard_type.upper() in ["RL-Q", "MARL-Q"]:
                for i, g in enumerate(guards):
                    g.update_q_value(guard_positions[i], player_pos, guard_view_range, is_captured=False)

        coverage_rate = len(visited_cells) / len(self.env.walkable_cells)
        avg_dist = float(statistics.mean(min_distances)) if min_distances else 0.0
        total_backtracks = sum(backtrack_counts)

        return {
            "map_name": self.map_name,
            "guard_type": guard_type,
            "player_mode": player_mode,
            "seed": seed,
            "captured": captured,
            "capture_time": capture_time,
            "backtrack_count": total_backtracks,
            "coverage_rate": coverage_rate,
            "avg_distance": avg_dist,
            "first_detect_time": first_detect_time if first_detect_time is not None else max_duration
        }

    def run_benchmark_suite(self, guard_types, num_trials=50, player_mode="MaxMin", output_csv=None):
        all_results = []
        summary = {}

        def _mean(lst):
            return float(statistics.mean(lst)) if lst else 0.0

        def _std(lst):
            return float(statistics.stdev(lst)) if len(lst) > 1 else 0.0

        for g_type in guard_types:
            trial_results = []
            for trial_idx in range(num_trials):
                seed = 1000 + trial_idx * 37
                res = self.run_single_capture_trial(g_type, seed, num_guards=3, player_mode=player_mode)
                trial_results.append(res)
                all_results.append(res)

            captures = [1 if r["captured"] else 0 for r in trial_results]
            cap_times = [r["capture_time"] for r in trial_results if r["captured"]]
            all_times = [r["capture_time"] for r in trial_results]
            backtracks = [r["backtrack_count"] for r in trial_results]
            coverages = [r["coverage_rate"] for r in trial_results]
            distances = [r["avg_distance"] for r in trial_results]
            first_detects = [r["first_detect_time"] for r in trial_results]

            cr = sum(captures) / len(captures)
            ct_mean = _mean(cap_times) if cap_times else 60.0
            ct_std = _std(cap_times) if len(cap_times) > 1 else 0.0

            summary[g_type] = {
                "guard_type": g_type,
                "player_mode": player_mode,
                "trials": num_trials,
                "capture_rate": cr,
                "capture_time_mean": ct_mean,
                "capture_time_std": ct_std,
                "all_time_mean": _mean(all_times),
                "backtrack_mean": _mean(backtracks),
                "backtrack_std": _std(backtracks),
                "coverage_mean": _mean(coverages),
                "avg_dist_mean": _mean(distances),
                "first_detect_mean": _mean(first_detects)
            }

        # Write to CSV if specified
        if output_csv:
            os.makedirs(os.path.dirname(os.path.abspath(output_csv)), exist_ok=True)
            fieldnames = [
                "map_name", "guard_type", "player_mode", "seed", "captured", 
                "capture_time", "backtrack_count", "coverage_rate", 
                "avg_distance", "first_detect_time"
            ]
            with open(output_csv, "w", newline="") as f:
                writer = csv.DictWriter(f, fieldnames=fieldnames)
                writer.writeheader()
                for r in all_results:
                    writer.writerow(r)

        return summary
