import os
import sys

# Ensure scripts directory is in python path
sys.path.append(os.path.abspath("scripts"))

from stealth.experiment_runner import StealthExperimentRunner

def run_evaluation():
    print("=" * 80)
    print("AUTONOMOUS GUARD AI BENCHMARK: REPRODUCTION & NOVEL MODEL EVALUATION")
    print("Base Paper: Kaijie Xu & Clark Verbrugge (AIIDE 2025, arXiv:2508.18527)")
    print("=" * 80)

    maps_to_test = [
        ("Test (Maze)", "maps/test_maze.json"),
        ("Miami", "maps/miami.json")
    ]
    guard_models = ["FSM", "CPF", "PI-PF", "RL-Q"]
    num_trials = 50

    all_summaries = {}

    for map_name, map_path in maps_to_test:
        print(f"\n---> Running 50-Trial Capture Benchmark on Map: '{map_name}'...")
        runner = StealthExperimentRunner(map_path)
        csv_path = f"data/benchmark_{map_name.lower().replace(' ', '_').replace('(', '').replace(')', '')}.csv"
        summary = runner.run_benchmark_suite(guard_models, num_trials=num_trials, output_csv=csv_path)
        all_summaries[map_name] = summary

        print(f"\nRESULTS FOR MAP: '{map_name}' (50 Trials per Algorithm, 60s Limit, MaxMin Evasive Player)")
        print("-" * 88)
        print(f"{'Model':<12} | {'Role':<22} | {'Capture Rate':<14} | {'Capture Time (s)':<18} | {'Backtracks':<12}")
        print("-" * 88)

        # Baseline FSM
        fsm_s = summary["FSM"]
        print(f"{'FSM':<12} | {'Paper Baseline':<22} | {fsm_s['capture_rate']:>6.2f} (Paper: 0.12) | {fsm_s['capture_time_mean']:>5.2f} ± {fsm_s['capture_time_std']:<5.2f}s | {fsm_s['backtrack_mean']:>5.1f} ± {fsm_s['backtrack_std']:<4.1f}")

        # Paper CPF
        cpf_s = summary["CPF"]
        print(f"{'CPF':<12} | {'Paper Method':<22} | {cpf_s['capture_rate']:>6.2f} (Paper: 0.80) | {cpf_s['capture_time_mean']:>5.2f} ± {cpf_s['capture_time_std']:<5.2f}s | {cpf_s['backtrack_mean']:>5.1f} ± {cpf_s['backtrack_std']:<4.1f}")

        # Novel Model 1: PI-PF
        pipf_s = summary["PI-PF"]
        print(f"{'PI-PF':<12} | {'Novel: Trajectory Intercept':<22} | {pipf_s['capture_rate']:>6.2f} (Novel)        | {pipf_s['capture_time_mean']:>5.2f} ± {pipf_s['capture_time_std']:<5.2f}s | {pipf_s['backtrack_mean']:>5.1f} ± {pipf_s['backtrack_std']:<4.1f}")

        # Novel Model 2: RL-Q
        rl_s = summary["RL-Q"]
        print(f"{'RL-Q':<12} | {'Novel: Q-Learning RL':<22} | {rl_s['capture_rate']:>6.2f} (Novel)        | {rl_s['capture_time_mean']:>5.2f} ± {rl_s['capture_time_std']:<5.2f}s | {rl_s['backtrack_mean']:>5.1f} ± {rl_s['backtrack_std']:<4.1f}")
        print("-" * 88)

    print("\nBenchmark completed! Raw CSV datasets generated in 'data/' directory.")

if __name__ == "__main__":
    run_evaluation()
