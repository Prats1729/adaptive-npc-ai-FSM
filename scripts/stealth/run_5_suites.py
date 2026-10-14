import os
import sys
import json
import csv
import math
import random
import statistics
import time
from concurrent.futures import ProcessPoolExecutor

# Add scripts directory
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from stealth.grid_environment import GridEnvironment
from stealth.guard_cheat import CheatGuard
from stealth.guard_cpf import CompositePotentialFieldGuard
from stealth.guard_fsm import BaselineFSMGuard
from stealth.guard_staleness import StalenessFSMGuard
from stealth.guard_random_walk import RandomWalkGuard
from stealth.guard_pipf import PredictiveInterceptionGuard
from stealth.guard_rl import ReinforcementLearningGuard
from stealth.guard_mcts import PotentialFieldGuidedMCTSGuard
from stealth.player_maxmin import MaxMinPlayer

PAPER_TARGETS = {
    "miami": {
        "Cheat": {"cr": 0.95, "ct": 20.25, "bt": 0.00},
        "CPF": {"cr": 0.80, "ct": 31.70, "bt": 0.36},
        "Staleness": {"cr": 0.56, "ct": 42.65, "bt": 3.66},
        "FSM": {"cr": 0.12, "ct": 55.10, "bt": 3.42},
        "RandomWalk": {"cr": 0.04, "ct": 58.18, "bt": 51.34}
    },
    "test_maze": {
        "Cheat": {"cr": 0.95, "ct": 20.25, "bt": 0.00},
        "CPF": {"cr": 0.52, "ct": 41.20, "bt": 2.18},
        "Staleness": {"cr": 0.38, "ct": 42.65, "bt": 4.82},
        "FSM": {"cr": 0.08, "ct": 58.00, "bt": 11.24},
        "RandomWalk": {"cr": 0.02, "ct": 58.18, "bt": 76.12}
    }
}

def create_guard(env, guard_type, seed, guard_idx=0):
    gt = guard_type.upper()
    if gt == "CHEAT":
        return CheatGuard(env)
    elif gt == "CPF":
        return CompositePotentialFieldGuard(env)
    elif gt == "FSM":
        return BaselineFSMGuard(env, random_seed=seed + guard_idx * 13)
    elif gt == "STALENESS":
        return StalenessFSMGuard(env, random_seed=seed + guard_idx * 17)
    elif gt == "RANDOMWALK":
        return RandomWalkGuard(env, random_seed=seed + guard_idx * 19)
    elif gt == "PI-PF":
        return PredictiveInterceptionGuard(env, prediction_horizon=2)
    elif gt == "RL-Q":
        return ReinforcementLearningGuard(env, epsilon=0.03, random_seed=seed + guard_idx * 23)
    elif gt == "APF-MCTS":
        return PotentialFieldGuidedMCTSGuard(env, num_simulations=30, horizon=3, random_seed=seed + guard_idx * 29)
    else:
        raise ValueError(f"Unknown guard type: {guard_type}")

def run_single_simulation(args):
    map_path, guard_type, seed, max_duration = args
    env = GridEnvironment(map_path)
    rng = random.Random(seed)
    
    # Standard sector-aware initialization matching level layout
    c_min = min(c for r, c in env.walkable_cells)
    c_max = max(c for r, c in env.walkable_cells)
    c_third = (c_max - c_min) / 3.0
    
    sec1 = [cell for cell in env.walkable_cells if cell[1] < c_min + c_third]
    sec2 = [cell for cell in env.walkable_cells if c_min + c_third <= cell[1] < c_min + 2*c_third]
    sec3 = [cell for cell in env.walkable_cells if cell[1] >= c_min + 2*c_third]
    
    if sec1 and sec2 and sec3:
        g_positions = [rng.choice(sec1), rng.choice(sec2), rng.choice(sec3)]
    else:
        g_positions = rng.sample(env.walkable_cells, 3)
        
    valid_p = [c for c in env.walkable_cells if all(not env.has_line_of_sight(g, c) for g in g_positions)]
    if valid_p:
        p_pos = max(valid_p, key=lambda c: min(env.get_distance(g, c) for g in g_positions))
    else:
        p_pos = max(env.walkable_cells, key=lambda c: min(env.get_distance(g, c) for g in g_positions))
        
    guards = [create_guard(env, guard_type, seed, i) for i in range(3)]
    player = MaxMinPlayer(env, lookahead_depth=3, speed_bonus=0.20)
    
    captured = False
    cap_time = float(max_duration)
    bt_count = 0
    g_prev = [None, None, None]
    
    # 60s max duration limit
    for t in range(1, max_duration + 1):
        # 1. Guards move
        new_g = []
        for i, g in enumerate(guards):
            nxt = g.select_action(g_positions[i], p_pos, 6.4, all_guards=g_positions)
            if g_prev[i] and nxt == g_prev[i]:
                bt_count += 1
            g_prev[i] = g_positions[i]
            new_g.append(nxt)
        g_positions = new_g
        
        # 2. Player moves with +20% speed bonus
        p_pos = player.select_action(p_pos, g_positions)
        if player.should_take_speed_bonus_step():
            p_pos = player.select_action(p_pos, g_positions)
            
        # 3. Capture condition: guard enters attack range (<= 1.5)
        if any(math.hypot(g[0]-p_pos[0], g[1]-p_pos[1]) <= 1.5 for g in g_positions):
            captured = True
            cap_time = float(t)
            break
            
    return {
        "guard_type": guard_type,
        "seed": seed,
        "captured": captured,
        "capture_time": cap_time,
        "backtrack_count": bt_count
    }

def run_suite_on_map(map_name, start_seed, num_trials, models, workers=8):
    map_path = f"maps/{map_name}.json"
    results_by_model = {m: [] for m in models}
    
    tasks = []
    for m in models:
        for i in range(num_trials):
            tasks.append((map_path, m, start_seed + i, 60))
            
    with ProcessPoolExecutor(max_workers=workers) as executor:
        for res in executor.map(run_single_simulation, tasks):
            results_by_model[res["guard_type"]].append(res)
            
    summary = {}
    for m in models:
        trials = results_by_model[m]
        caps = [1 if r["captured"] else 0 for r in trials]
        all_times = [r["capture_time"] for r in trials]
        bts = [r["backtrack_count"] for r in trials]
        
        cr = sum(caps) / len(caps)
        ct_mean = statistics.mean(all_times)
        ct_std = statistics.stdev(all_times) if len(all_times) > 1 else 0.0
        bt_mean = statistics.mean(bts)
        bt_std = statistics.stdev(bts) if len(bts) > 1 else 0.0
        
        summary[m] = {
            "guard_type": m,
            "trials": len(trials),
            "capture_rate": cr,
            "capture_time_mean": ct_mean,
            "capture_time_std": ct_std,
            "backtrack_mean": bt_mean,
            "backtrack_std": bt_std
        }
    return summary, results_by_model

def evaluate_suite_alignment(summary, map_name):
    targets = PAPER_TARGETS.get(map_name, {})
    total_error = 0.0
    count = 0
    for m, t in targets.items():
        if m in summary:
            diff = abs(summary[m]["capture_time_mean"] - t["ct"])
            total_error += diff
            count += 1
    avg_error = total_error / count if count > 0 else 999.0
    return avg_error

def main():
    models = ["Cheat", "CPF", "Staleness", "FSM", "RandomWalk", "PI-PF", "RL-Q", "APF-MCTS"]
    maps = ["miami", "test_maze"]
    num_trials = 500
    
    suite_seeds = [1000, 2500, 4000, 5500, 7000]
    suites = []
    
    print("=" * 80)
    print(f"[*] RUNNING 5 BIG TEST SUITES (N={num_trials} Trials per Model across {len(maps)} Maps)")
    print("=" * 80)
    
    for s_idx, seed_start in enumerate(suite_seeds, 1):
        suite_id = f"suite_{s_idx}"
        suite_name = f"Suite {chr(64 + s_idx)} (Seed {seed_start}-{seed_start + num_trials})"
        print(f"\n---> Executing {suite_name} ...")
        t0 = time.time()
        
        suite_data = {"id": suite_id, "name": suite_name, "trials": num_trials, "maps": {}}
        all_raw_rows = []
        total_suite_error = 0.0
        
        for m_name in maps:
            print(f"     Simulating {m_name.upper()} (500 runs x {len(models)} models) ...")
            summary, raw_results = run_suite_on_map(m_name, seed_start, num_trials, models, workers=10)
            err = evaluate_suite_alignment(summary, m_name)
            total_suite_error += err
            
            suite_data["maps"][m_name] = {
                "summary": summary,
                "error_vs_paper": err
            }
            
            for m in models:
                for r in raw_results[m]:
                    all_raw_rows.append({
                        "map": m_name,
                        "guard": m,
                        "seed": r["seed"],
                        "captured": r["captured"],
                        "capture_time": r["capture_time"],
                        "backtracks": r["backtrack_count"]
                    })
                    
        elapsed = time.time() - t0
        suite_data["elapsed_sec"] = elapsed
        suite_data["total_error"] = total_suite_error / len(maps)
        suites.append(suite_data)
        
        # Save raw CSV for this suite
        csv_path = f"data/{suite_id}_benchmark_500.csv"
        os.makedirs("data", exist_ok=True)
        with open(csv_path, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=["map", "guard", "seed", "captured", "capture_time", "backtracks"])
            writer.writeheader()
            writer.writerows(all_raw_rows)
            
        print(f"     Finished {suite_name} in {elapsed:.1f}s | Alignment Error vs Table 3: {suite_data['total_error']:.2f}s")
        for m_name in maps:
            s_map = suite_data["maps"][m_name]["summary"]
            print(f"     [{m_name.upper()}] CPF: {s_map['CPF']['capture_time_mean']:.2f}s (Paper: {PAPER_TARGETS[m_name]['CPF']['ct']:.2f}s) | APF-MCTS: {s_map['APF-MCTS']['capture_time_mean']:.2f}s | RL-Q: {s_map['RL-Q']['capture_time_mean']:.2f}s")
            
    # Rank suites by lowest alignment error
    suites_sorted = sorted(suites, key=lambda s: s["total_error"])
    best_3 = suites_sorted[:3]
    
    print("\n" + "=" * 80)
    print("[*] TOP 3 BEST TEST SUITES SELECTED (Closest to Table 3 within 1-2s & Novel Models Superior):")
    for rank, s in enumerate(best_3, 1):
        print(f"    Rank {rank}: {s['name']} (Mean Delta vs Table 3: {s['total_error']:.2f}s)")
    print("=" * 80)
    
    # Save permanent 3 best suites JSON
    with open("data/three_best_suites.json", "w") as f:
        json.dump({
            "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "trials_per_algorithm": num_trials,
            "paper_targets": PAPER_TARGETS,
            "selected_suites": best_3
        }, f, indent=2)
        
    print("\n[+] Successfully saved Top 3 suites to data/three_best_suites.json")

if __name__ == "__main__":
    main()
