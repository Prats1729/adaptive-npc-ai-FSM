import os
import sys
import argparse
import time
import webbrowser

sys.path.append(os.path.abspath("scripts"))

from stealth.experiment_runner import StealthExperimentRunner
from stealth.grid_environment import GridEnvironment
from stealth.guard_rl import train_rl_policy

def ensure_prerequisites():
    """Verify that maps and RL weights exist, generating them if needed."""
    maps = ["maps/test_maze.json", "maps/miami.json"]
    for m in maps:
        if not os.path.exists(m):
            print(f"[!] Map file '{m}' missing. Running map generator...")
            from tools.build_maps import generate_all_maps
            generate_all_maps()
            break

def train_models_if_needed(force_train=False):
    targets = [
        ("Miami", "maps/miami.json", "data/q_table_miami.json"),
        ("Test Maze", "maps/test_maze.json", "data/q_table_test_maze.json")
    ]
    for name, map_file, save_path in targets:
        if force_train or not os.path.exists(save_path):
            print(f"[*] Training Reinforcement Learning Policy for '{name}' (300 episodes)...")
            env = GridEnvironment(map_file)
            t0 = time.time()
            train_rl_policy(env, num_episodes=300, save_path=save_path, seed=42)
            print(f"    [OK] Trained & saved to '{save_path}' in {time.time()-t0:.2f}s")

def run_benchmark(num_trials=50, selected_map=None, open_dashboard=False):
    print("=" * 95)
    print(" " * 15 + "AUTONOMOUS GUARD AI IN STEALTH GAMES: BENCHMARK EVALUATOR")
    print(" " * 12 + "Computational Reproduction & Novel Model Evaluation (AIIDE 2025)")
    print("=" * 95)

    all_maps = [
        ("Miami", "maps/miami.json"),
        ("Test Maze", "maps/test_maze.json")
    ]

    if selected_map:
        all_maps = [(n, p) for n, p in all_maps if selected_map.lower() in n.lower()]
        if not all_maps:
            print(f"[Error] Map matching '{selected_map}' not found.")
            return

    guard_models = ["FSM", "CPF", "PI-PF", "RL-Q"]

    for map_name, map_path in all_maps:
        clean_name = map_name.lower().replace(" ", "_")
        csv_path = f"data/benchmark_{clean_name}.csv"
        q_path = f"data/q_table_{clean_name}.json"
        
        print(f"\n[+] Running {num_trials} Trials per Algorithm on Map: '{map_name}'...")
        print(f"    Environment: 60s Time Limit, 3 Guards, 120% Speed MaxMin Evasive Player")
        
        runner = StealthExperimentRunner(map_path, q_table_path=q_path)
        summary = runner.run_benchmark_suite(guard_models, num_trials=num_trials, output_csv=csv_path)

        # Print beautiful ASCII summary table
        print(f"\n" + "-" * 95)
        print(f"  BENCHMARK RESULTS: {map_name.upper()} ({num_trials} Trials per Model)")
        print("-" * 95)
        print(f"  {'Model':<10} | {'Role':<26} | {'Capture Rate':<14} | {'Mean Time (s)':<18} | {'Backtracks':<12}")
        print("-" * 95)

        # 1. Baseline FSM
        f = summary["FSM"]
        paper_fsm_cr = "0.12" if "miami" in clean_name else "0.08"
        print(f"  {'FSM':<10} | {'Baseline State Machine':<26} | {f['capture_rate']:>5.2f} (Paper: {paper_fsm_cr}) | {f['capture_time_mean']:>5.2f} +/- {f['capture_time_std']:<5.2f}s | {f['backtrack_mean']:>4.1f} +/- {f['backtrack_std']:<4.1f}")

        # 2. Base Paper CPF
        c = summary["CPF"]
        paper_cpf_cr = "0.80" if "miami" in clean_name else "0.52"
        paper_cpf_time = "31.7s" if "miami" in clean_name else "41.2s"
        print(f"  {'CPF':<10} | {'Base Paper (Xu & Verbrugge)':<26} | {c['capture_rate']:>5.2f} (Paper: {paper_cpf_cr}) | {c['capture_time_mean']:>5.2f} +/- {c['capture_time_std']:<5.2f}s | {c['backtrack_mean']:>4.1f} +/- {c['backtrack_std']:<4.1f}")

        # 3. Novel Model 1 (PI-PF)
        p = summary["PI-PF"]
        print(f"  {'PI-PF':<10} | {'Novel 1: Vector Intercept':<26} | {p['capture_rate']:>5.2f} (Novel)        | {p['capture_time_mean']:>5.2f} +/- {p['capture_time_std']:<5.2f}s | {p['backtrack_mean']:>4.1f} +/- {p['backtrack_std']:<4.1f}")

        # 4. Novel Model 2 (RL-Q)
        r = summary["RL-Q"]
        print(f"  {'RL-Q':<10} | {'Novel 2: Trained Q-Learning':<26} | {r['capture_rate']:>5.2f} (Novel)        | {r['capture_time_mean']:>5.2f} +/- {r['capture_time_std']:<5.2f}s | {r['backtrack_mean']:>4.1f} +/- {r['backtrack_std']:<4.1f}")
        print("-" * 95)
        print(f"  --> Logged full trial dataset to: '{csv_path}'\n")

    dashboard_path = os.path.abspath("docs/stealth_dashboard.html")
    print("=" * 95)
    print("EVALUATION COMPLETE!")
    print(f"Interactive Visualization Dashboard: file:///{dashboard_path.replace(os.sep, '/')}")
    print("=" * 95)

    if open_dashboard:
        try:
            webbrowser.open(f"file:///{dashboard_path.replace(os.sep, '/')}")
        except Exception:
            pass

def main():
    parser = argparse.ArgumentParser(description="Autonomous Guard AI Stealth Benchmark Runner")
    parser.add_argument("--trials", type=int, default=50, help="Number of Monte-Carlo trials per algorithm (default: 50)")
    parser.add_argument("--map", type=str, default=None, help="Filter by map name ('miami', 'maze')")
    parser.add_argument("--train", action="store_true", help="Force re-training of Reinforcement Learning models")
    parser.add_argument("--open-dashboard", action="store_true", help="Open the HTML dashboard in default browser")
    args = parser.parse_args()

    ensure_prerequisites()
    train_models_if_needed(force_train=args.train)
    run_benchmark(num_trials=args.trials, selected_map=args.map, open_dashboard=args.open_dashboard)

if __name__ == "__main__":
    main()
