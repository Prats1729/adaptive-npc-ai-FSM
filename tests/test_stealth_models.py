import os
import sys
import unittest

sys.path.append(os.path.abspath("scripts"))

from stealth.grid_environment import GridEnvironment
from stealth.player_maxmin import MaxMinPlayer
from stealth.player_safety_graph import SafetyGraphPlayer

from stealth.guard_random_walk import RandomWalkGuard
from stealth.guard_fsm import BaselineFSMGuard
from stealth.guard_staleness import StalenessFSMGuard
from stealth.guard_cpf import CompositePotentialFieldGuard
from stealth.guard_cheat import CheatGuard
from stealth.guard_pipf import PredictiveInterceptionGuard
from stealth.guard_rl import ReinforcementLearningGuard
from stealth.guard_mcts import PotentialFieldGuidedMCTSGuard
from stealth.experiment_runner import StealthExperimentRunner

class TestStealthModels(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.map_paths = [
            "maps/test_maze.json",
            "maps/miami.json",
            "maps/arkham.json",
            "maps/tlou.json",
            "maps/dishonored.json"
        ]
        cls.test_maze_env = GridEnvironment("maps/test_maze.json")
        cls.miami_env = GridEnvironment("maps/miami.json")

    def test_all_five_maps_load_successfully(self):
        for mp in self.map_paths:
            self.assertTrue(os.path.exists(mp), f"Map file {mp} does not exist!")
            env = GridEnvironment(mp)
            self.assertGreater(len(env.walkable_cells), 50)
            self.assertGreater(len(env.wall_cells), 10)
            self.assertGreater(env.rows, 5)
            self.assertGreater(env.cols, 5)

    def test_environment_properties(self):
        env = self.test_maze_env
        self.assertGreater(len(env.walkable_cells), 0)
        self.assertGreater(len(env.wall_cells), 0)
        # Test geodesic distance symmetry
        c1 = list(env.walkable_cells)[0]
        c2 = list(env.walkable_cells)[1]
        self.assertEqual(env.get_distance(c1, c2), env.get_distance(c2, c1))

    def test_bresenham_line_of_sight(self):
        env = self.test_maze_env
        c1 = list(env.walkable_cells)[0]
        self.assertTrue(env.has_line_of_sight(c1, c1, max_range=8.0))
        self.assertTrue(env.has_line_of_sight(c1, c1, view_range=6.4))

    def test_all_eight_guard_models_action_selection(self):
        guard_types = [
            "RandomWalk", "FSM", "Staleness", "CPF", 
            "Cheat", "PI-PF", "RL-Q", "APF-MCTS"
        ]
        runner = StealthExperimentRunner("maps/miami.json")
        g_pos, p_pos = self.miami_env.initialize_positions(num_guards=3, random_seed=42)

        for gt in guard_types:
            guard = runner._create_guard(gt, seed=42)
            next_step = guard.select_action(g_pos[0], p_pos, view_range=6.4, all_guards=g_pos)
            self.assertIn(next_step, self.miami_env.walkable_cells, f"Guard {gt} picked non-walkable tile {next_step}")
            dist = self.miami_env.get_distance(g_pos[0], next_step)
            self.assertIn(dist, [0, 1], f"Guard {gt} took an illegal leap: dist={dist}")

    def test_both_player_policies(self):
        g_pos, p_pos = self.miami_env.initialize_positions(num_guards=3, random_seed=42)
        
        # MaxMin Player
        maxmin_p = MaxMinPlayer(self.miami_env, speed_bonus=0.20)
        next_p1 = maxmin_p.select_action(p_pos, g_pos)
        self.assertIn(next_p1, self.miami_env.walkable_cells)
        self.assertIn(self.miami_env.get_distance(p_pos, next_p1), [0, 1])
        # Speed bonus trigger test
        triggers = sum(1 for _ in range(10) if maxmin_p.should_take_speed_bonus_step())
        self.assertEqual(triggers, 2)  # 20% of 10 = 2 extra steps

        # SafetyGraph Player
        safety_p = SafetyGraphPlayer(self.miami_env, speed_bonus=0.20)
        next_p2 = safety_p.select_action(p_pos, g_pos)
        self.assertIn(next_p2, self.miami_env.walkable_cells)
        self.assertIn(self.miami_env.get_distance(p_pos, next_p2), [0, 1])
        triggers_s = sum(1 for _ in range(10) if safety_p.should_take_speed_bonus_step())
        self.assertEqual(triggers_s, 2)

    def test_single_trial_all_guard_types(self):
        runner = StealthExperimentRunner("maps/test_maze.json")
        guard_types = ["RandomWalk", "FSM", "Staleness", "CPF", "Cheat", "PI-PF", "RL-Q", "APF-MCTS"]
        
        for gt in guard_types:
            res = runner.run_single_capture_trial(gt, seed=123, num_guards=3, player_mode="MaxMin")
            self.assertIn("captured", res)
            self.assertIn("capture_time", res)
            self.assertIn("backtrack_count", res)
            self.assertGreaterEqual(res["capture_time"], 1.0)
            self.assertLessEqual(res["capture_time"], 60.0)

    def test_q_table_persistence(self):
        rl_guard = ReinforcementLearningGuard(self.test_maze_env, random_seed=99)
        test_file = "data/test_q_table_tmp.json"
        rl_guard.q_table["TEST_STATE"] = [1.0, 2.0, 3.0, 4.0]
        rl_guard.save_q_table(test_file)
        self.assertTrue(os.path.exists(test_file))
        
        # Load in a fresh instance
        fresh_guard = ReinforcementLearningGuard(self.test_maze_env)
        loaded = fresh_guard.load_q_table(test_file)
        self.assertTrue(loaded)
        self.assertEqual(fresh_guard.q_table["TEST_STATE"], [1.0, 2.0, 3.0, 4.0])
        
        # Cleanup
        if os.path.exists(test_file):
            os.remove(test_file)

if __name__ == "__main__":
    unittest.main()
