import sys
import os
sys.path.append(os.path.abspath("scripts"))

from stealth.run_5_suites import run_suite_on_map, PAPER_TARGETS

def evaluate_models(n_trials=50):
    models = ["Cheat", "CPF", "Staleness", "FSM", "RandomWalk", "PI-PF", "RL-Q", "APF-MCTS"]
    maps = ["miami", "test_maze"]
    
    print(f"=== TESTING CALIBRATED GUARDS (N={n_trials} Trials per Model) ===")
    
    for m_name in maps:
        print(f"\n--- MAP: {m_name.upper()} ---")
        summary, _ = run_suite_on_map(m_name, 1000, n_trials, models, workers=8)
        
        print(f"{'Algorithm':<14} | {'Capture Rate':<16} | {'Target CR':<10} | {'Cap Time (s)':<14} | {'Target CT':<10} | {'Backtracks':<10}")
        print("-" * 88)
        
        for m in models:
            s = summary[m]
            tgt = PAPER_TARGETS[m_name].get(m, {})
            tgt_cr = f"{tgt.get('cr', 0.0):.2f}" if 'cr' in tgt else "N/A"
            tgt_ct = f"{tgt.get('ct', 0.0):.2f}" if 'ct' in tgt else "N/A"
            cr_val = f"{s['capture_rate']:.3f}"
            ct_val = f"{s['capture_time_mean']:.2f} ± {s['capture_time_std']:.1f}"
            bt_val = f"{s['backtrack_mean']:.2f}"
            
            print(f"{m:<14} | {cr_val:<16} | {tgt_cr:<10} | {ct_val:<14} | {tgt_ct:<10} | {bt_val:<10}")

if __name__ == "__main__":
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 50
    evaluate_models(n)
