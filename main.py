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
    """Verify that maps exist, generating them if needed."""
    maps = ["maps/test_maze.json", "maps/miami.json", "maps/arkham.json", "maps/tlou.json", "maps/dishonored.json"]
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

def run_benchmark(num_trials=50, selected_map=None, player_mode="MaxMin", open_dashboard=False):
    print("=" * 105)
    print(" " * 20 + "AUTONOMOUS GUARD AI IN STEALTH GAMES: BENCHMARK SUITE")
    print(" " * 15 + "Base Paper Reproduction & 3 Novel AI Models (AIIDE 2025 Benchmark)")
    print("=" * 105)

    all_maps = [
        ("Miami", "maps/miami.json"),
        ("Test Maze", "maps/test_maze.json")
    ]

    if selected_map:
        all_maps = [(n, p) for n, p in all_maps if selected_map.lower() in n.lower()]
        if not all_maps:
            print(f"[Error] Map matching '{selected_map}' not found.")
            return

    # All 5 Paper Guard Models + 3 Novel AI Models = 8 Models Total
    guard_models = [
        # Paper Baselines
        "Cheat", "CPF", "Staleness", "FSM", "RandomWalk",
        # 3 Novel AI Models
        "PI-PF", "RL-Q", "APF-MCTS"
    ]

    for map_name, map_path in all_maps:
        clean_name = map_name.lower().replace(" ", "_")
        csv_path = f"data/benchmark_{clean_name}.csv"
        q_path = f"data/q_table_{clean_name}.json"
        
        print(f"\n[+] Running {num_trials} Trials per Algorithm on Map: '{map_name}' | Player Policy: '{player_mode}'...")
        print(f"    Environment: 60s Time Limit, 3 Guards, 120% Speed Bonus Evasive Player")
        
        runner = StealthExperimentRunner(map_path, q_table_path=q_path)
        summary = runner.run_benchmark_suite(guard_models, num_trials=num_trials, player_mode=player_mode, output_csv=csv_path)

        # Print beautiful ASCII summary table
        print(f"\n" + "-" * 105)
        print(f"  BENCHMARK RESULTS: {map_name.upper()} ({num_trials} Trials per Model | Player: {player_mode})")
        print("-" * 105)
        print(f"  {'Model':<10} | {'Category':<22} | {'Capture Rate':<16} | {'Mean Time (s)':<18} | {'Backtracks':<12}")
        print("-" * 105)

        # 1. Cheat
        ch = summary["Cheat"]
        print(f"  {'Cheat':<10} | {'Paper Upper Bound':<22} | {ch['capture_rate']:>5.2f} (Paper: 0.95)   | {ch['capture_time_mean']:>5.2f} +/- {ch['capture_time_std']:<5.2f}s | {ch['backtrack_mean']:>4.1f} +/- {ch['backtrack_std']:<4.1f}")

        # 2. CPF (Base Paper)
        c = summary["CPF"]
        p_cpf = "0.80" if "miami" in clean_name else "0.52"
        print(f"  {'CPF':<10} | {'Base Paper (Xu&Verb)':<22} | {c['capture_rate']:>5.2f} (Paper: {p_cpf})   | {c['capture_time_mean']:>5.2f} +/- {c['capture_time_std']:<5.2f}s | {c['backtrack_mean']:>4.1f} +/- {c['backtrack_std']:<4.1f}")

        # 3. Staleness FSM
        st = summary["Staleness"]
        p_st = "0.56" if "miami" in clean_name else "0.38"
        print(f"  {'Staleness':<10} | {'Paper Baseline':<22} | {st['capture_rate']:>5.2f} (Paper: {p_st})   | {st['capture_time_mean']:>5.2f} +/- {st['capture_time_std']:<5.2f}s | {st['backtrack_mean']:>4.1f} +/- {st['backtrack_std']:<4.1f}")

        # 4. Baseline FSM
        f = summary["FSM"]
        p_fsm = "0.12" if "miami" in clean_name else "0.08"
        print(f"  {'FSM':<10} | {'Paper Baseline':<22} | {f['capture_rate']:>5.2f} (Paper: {p_fsm})   | {f['capture_time_mean']:>5.2f} +/- {f['capture_time_std']:<5.2f}s | {f['backtrack_mean']:>4.1f} +/- {f['backtrack_std']:<4.1f}")

        # 5. Random Walk
        rw = summary["RandomWalk"]
        p_rw = "0.04" if "miami" in clean_name else "0.02"
        print(f"  {'RandomWalk':<10} | {'Paper Baseline':<22} | {rw['capture_rate']:>5.2f} (Paper: {p_rw})   | {rw['capture_time_mean']:>5.2f} +/- {rw['capture_time_std']:<5.2f}s | {rw['backtrack_mean']:>4.1f} +/- {rw['backtrack_std']:<4.1f}")

        print("  " + "." * 101)

        # 6. Novel Model 1 (PI-PF)
        p = summary["PI-PF"]
        print(f"  {'PI-PF':<10} | {'Novel 1: Vector Look':<22} | {p['capture_rate']:>5.2f} (Novel)        | {p['capture_time_mean']:>5.2f} +/- {p['capture_time_std']:<5.2f}s | {p['backtrack_mean']:>4.1f} +/- {p['backtrack_std']:<4.1f}")

        # 7. Novel Model 2 (RL-Q)
        r = summary["RL-Q"]
        print(f"  {'RL-Q':<10} | {'Novel 2: Bellman Q-Lrn':<22} | {r['capture_rate']:>5.2f} (Novel)        | {r['capture_time_mean']:>5.2f} +/- {r['capture_time_std']:<5.2f}s | {r['backtrack_mean']:>4.1f} +/- {r['backtrack_std']:<4.1f}")

        # 8. Novel Model 3 (APF-MCTS)
        m = summary["APF-MCTS"]
        print(f"  {'APF-MCTS':<10} | {'Novel 3: MCTS Tree Plan':<22} | {m['capture_rate']:>5.2f} (Novel)        | {m['capture_time_mean']:>5.2f} +/- {m['capture_time_std']:<5.2f}s | {m['backtrack_mean']:>4.1f} +/- {m['backtrack_std']:<4.1f}")

        print("-" * 105)
        print(f"  --> Logged trial dataset to: '{csv_path}'\n")

    dashboard_path = os.path.abspath("docs/stealth_dashboard.html")
    print("=" * 105)
    print("EVALUATION COMPLETE!")
    print(f"Interactive Visualization Dashboard: file:///{dashboard_path.replace(os.sep, '/')}")
    print("=" * 105)

    if open_dashboard:
        try:
            webbrowser.open(f"file:///{dashboard_path.replace(os.sep, '/')}")
        except Exception:
            pass

def main():
    parser = argparse.ArgumentParser(description="Autonomous Guard AI Stealth Benchmark Runner")
    parser.add_argument("--trials", type=int, default=50, help="Number of Monte-Carlo trials per algorithm (default: 50)")
    parser.add_argument("--map", type=str, default=None, help="Filter by map name ('miami', 'maze')")
    parser.add_argument("--player", type=str, default="MaxMin", choices=["MaxMin", "SafetyGraph"], help="Player evasion policy")
    parser.add_argument("--train", action="store_true", help="Force re-training of Reinforcement Learning models")
    parser.add_argument("--open-dashboard", action="store_true", help="Open the HTML dashboard in default browser")
    parser.add_argument("--ui", action="store_true", help="Launch interactive Stealth AI Benchmark Studio Web Server")
    parser.add_argument("--port", type=int, default=8080, help="Port for the web studio server (default: 8080)")
    args = parser.parse_args()

    ensure_prerequisites()

    if args.ui:
        import server
        server.start_server(port=args.port, open_browser=True)
        return

    train_models_if_needed(force_train=args.train)
    run_benchmark(num_trials=args.trials, selected_map=args.map, player_mode=args.player, open_dashboard=args.open_dashboard)

if __name__ == "__main__":
    main()
