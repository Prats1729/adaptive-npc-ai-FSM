import os
import sys
import time

sys.path.append(os.path.abspath("scripts"))

from stealth.grid_environment import GridEnvironment
from stealth.guard_rl import train_rl_policy

def main():
    print("=" * 75)
    print("OFFLINE TRAINING PIPELINE: REINFORCEMENT LEARNING GUARD AI")
    print("Bellman Temporal Difference Q-Learning Policy Training")
    print("=" * 75)

    training_targets = [
        ("Miami", "maps/miami.json", "data/q_table_miami.json"),
        ("Test Maze", "maps/test_maze.json", "data/q_table_test_maze.json")
    ]

    episodes = 300

    for name, map_file, save_path in training_targets:
        print(f"\n[+] Initializing Training on '{name}' ({map_file})...")
        env = GridEnvironment(map_file)
        
        t0 = time.time()
        print(f"    Running {episodes} self-play episodes against MaxMin Player...")
        print(f"    Epsilon annealing: 0.80 -> 0.05...")
        
        q_table = train_rl_policy(env, num_episodes=episodes, save_path=save_path, seed=42)
        elapsed = time.time() - t0
        
        print(f"    [OK] Training completed in {elapsed:.2f} seconds!")
        print(f"    [OK] Learned state space: {len(q_table)} distinct state-action vectors.")
        print(f"    [OK] Model policy saved to: '{save_path}'")

    print("\n" + "=" * 75)
    print("ALL MODELS TRAINED & PERSISTED TO DISK SUCCESSFULLY.")
    print("You can now run 'python main.py' to evaluate the trained policies!")
    print("=" * 75)

if __name__ == "__main__":
    main()
