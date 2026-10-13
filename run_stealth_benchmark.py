import os
import sys
import argparse

# Ensure scripts directory is in python path
sys.path.append(os.path.abspath("scripts"))

from stealth.experiment_runner import StealthExperimentRunner

def run_evaluation(num_trials=100):
    print("=" * 96)
    print(f"AUTONOMOUS GUARD AI BENCHMARK: REPRODUCTION & NOVEL MODEL EVALUATION (N={num_trials} TRIALS)")
    print("Base Paper: Kaijie Xu & Clark Verbrugge (AIIDE 2025, arXiv:2508.18527)")
    print("=" * 96)

    maps_to_test = [
        ("Miami", "maps/miami.json"),
        ("Test (Maze)", "maps/test_maze.json")
    ]
    guard_models = ["Cheat", "CPF", "Staleness", "FSM", "RandomWalk", "PI-PF", "RL-Q", "APF-MCTS"]

    paper_baselines = {
        "Miami": {
            "Cheat": "0.95", "CPF": "0.80", "Staleness": "0.56", "FSM": "0.12", "RandomWalk": "0.04"
        },
        "Test (Maze)": {
            "Cheat": "0.95", "CPF": "0.52", "Staleness": "0.38", "FSM": "0.08", "RandomWalk": "0.02"
        }
    }

    for map_name, map_path in maps_to_test:
        print(f"\n---> Executing {num_trials}-Trial Capture Benchmark on Map: '{map_name}'...")
        runner = StealthExperimentRunner(map_path)
        csv_path = f"data/benchmark_{map_name.lower().replace(' ', '_').replace('(', '').replace(')', '')}_{num_trials}.csv"
        summary = runner.run_benchmark_suite(guard_models, num_trials=num_trials, output_csv=csv_path)

        print(f"\nRESULTS FOR MAP: '{map_name}' ({num_trials} Trials per Algorithm, 60s Limit, MaxMin Evasive Player)")
        print("-" * 96)
        print(f"{'Model':<12} | {'Classification':<18} | {'Capture Rate':<16} | {'Capture Time (s)':<22} | {'Backtracks':<12}")
        print("-" * 96)

        p_dict = paper_baselines.get(map_name, {})
        for g in guard_models:
            s = summary[g]
            p_val = p_dict.get(g, "—")
            is_novel = g in ["PI-PF", "RL-Q", "APF-MCTS"]
            cls_name = "Novel Model" if is_novel else "Paper Model"
            tag = " ★" if is_novel and s["capture_rate"] >= 0.90 else ""
            print(f"{g:<12} | {cls_name:<18} | {s['capture_rate']:>6.2f} (Paper: {p_val:>4}){tag:<2} | {s['capture_time_mean']:>5.2f} ± {s['capture_time_std']:<5.2f}s        | {s['backtrack_mean']:>5.2f} ± {s['backtrack_std']:<4.2f}")

        print("-" * 96)
        print(f"Exported raw empirical CSV: {csv_path}")

    print("\nBenchmark completed successfully!")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Stealth AI Benchmark Runner")
    parser.add_argument("--trials", type=int, default=100, help="Number of Monte-Carlo trials (default: 100)")
    args = parser.parse_args()
    run_evaluation(num_trials=args.trials)
