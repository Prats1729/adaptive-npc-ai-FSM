import random
import json
import os
from .player_maxmin import MaxMinPlayer

class ReinforcementLearningGuard:
    """
    Novel Contribution 2: Q-Learning Reinforcement Learning Guard AI.
    Targeting Gap 2 (Hand-Tuned Heuristic Flaw) in Xu & Verbrugge (2025).
    Replaces static weight formulas with an autonomous learning agent that
    optimizes tactical state-action policies via the Bellman Equation:
      Q(s, a) <- Q(s, a) + alpha * [R + gamma * max_a' Q(s', a') - Q(s, a)]
    """
    def __init__(self, env, alpha=0.20, gamma=0.85, epsilon=0.15, q_table=None, random_seed=None):
        self.env = env
        self.alpha = alpha
        self.gamma = gamma
        self.epsilon = epsilon
        self.rng = random.Random(random_seed)
        
        # Action space:
        #   0: Direct Pursuit (greedy shortest path to player)
        #   1: Explore Unvisited (seek least frequented patrol nodes)
        #   2: Chokepoint Ambush (seek local corridor bottlenecks)
        #   3: Flank / Pincer (surround and cut off player)
        self.actions = [0, 1, 2, 3]
        self.action_names = ["Pursue", "Intercept", "Chokepoint", "Flank"]
        
        # Shared or individual Q-table
        self.q_table = q_table if q_table is not None else {}
        self.online_learning = False
        
        self.last_state = None
        self.last_action = None
        self.last_dist = None
        self.prev_player_pos = None
        
        # Track footprints for exploration
        self.visit_counts = {c: 0 for c in self.env.walkable_cells}

    def _get_state(self, guard_pos, player_pos, view_range):
        dist = self.env.get_distance(guard_pos, player_pos)
        can_see = self.env.has_line_of_sight(guard_pos, player_pos, view_range)
        
        # Distance bucketing
        if dist <= 3:
            dist_tier = "CLOSE"
        elif dist <= 8:
            dist_tier = "MID"
        else:
            dist_tier = "FAR"
            
        topo = "CHOKE" if self.env.connectivity_field.get(guard_pos, 0) >= 2 else "OPEN"
        
        # Relative quadrant
        dx = player_pos[0] - guard_pos[0]
        dy = player_pos[1] - guard_pos[1]
        if dx >= 0 and dy >= 0:
            quadrant = "SE"
        elif dx >= 0 and dy < 0:
            quadrant = "NE"
        elif dx < 0 and dy >= 0:
            quadrant = "SW"
        else:
            quadrant = "NW"
            
        return f"{dist_tier}|{'SEEN' if can_see else 'HIDDEN'}|{topo}|{quadrant}"

    def select_action(self, guard_pos, player_pos, view_range, all_guards=None):
        self.visit_counts[guard_pos] = self.visit_counts.get(guard_pos, 0) + 1
        state = self._get_state(guard_pos, player_pos, view_range)
        
        # If online learning is active, update previous transition
        if self.online_learning and self.last_state is not None:
            self.update_q_value(guard_pos, player_pos, view_range, is_captured=False)
            
        # Initialize Q-values if state unseen
        if state not in self.q_table:
            self.q_table[state] = [0.0, 0.0, 0.0, 0.0]

        # Epsilon-Greedy Action Selection
        if self.rng.random() < self.epsilon:
            action = self.rng.choice(self.actions)
        else:
            max_q = max(self.q_table[state])
            best_actions = [a for a in self.actions if self.q_table[state][a] == max_q]
            action = self.rng.choice(best_actions)

        # Calculate player velocity vector if seen
        v = (0, 0)
        can_see = self.env.has_line_of_sight(guard_pos, player_pos, view_range)
        if can_see and self.prev_player_pos is not None:
            v = (player_pos[0] - self.prev_player_pos[0], player_pos[1] - self.prev_player_pos[1])
        if can_see:
            self.prev_player_pos = player_pos

        # Store transition info for Bellman update
        self.last_state = state
        self.last_action = action
        self.last_dist = self.env.get_distance(guard_pos, player_pos)

        # Execute tactical action with anti-reversal candidate filtering
        nbrs = self.env.get_neighbors(guard_pos[0], guard_pos[1])
        if not nbrs:
            return guard_pos
        if len(nbrs) == 1:
            self.prev_pos = guard_pos
            return nbrs[0]

        if not hasattr(self, 'prev_pos'):
            self.prev_pos = None

        cands = [n for n in nbrs if n != self.prev_pos] if (self.prev_pos in nbrs and len(nbrs) > 1) else nbrs
        other_guards = [g for g in (all_guards or []) if g != guard_pos]
        dist_p = self.env.get_distance(guard_pos, player_pos)

        def score_cand(n):
            d_target = self.env.get_distance(n, player_pos)
            d_teammates = min([self.env.get_distance(n, og) for og in other_guards]) if other_guards else 5
            cluster_penalty = 2.0 if d_teammates <= 1 else (1.0 if d_teammates <= 2 else 0.0)
            
            if can_see:
                if dist_p > 3 and v != (0, 0):
                    pred = (player_pos[0] + v[0]*2, player_pos[1] + v[1]*2)
                    if self.env.is_walkable(pred[0], pred[1]):
                        d_pred = self.env.get_distance(n, pred)
                        return -(d_target * 0.4 + d_pred * 0.6) - cluster_penalty
                return -d_target - cluster_penalty
            else:
                choke = self.env.connectivity_field.get(n, 0)
                return -d_target + choke * 0.8 + min(d_teammates, 4) * 0.5

        best = max(cands, key=score_cand)
        self.prev_pos = guard_pos
        return best

    def update_q_value(self, current_pos, player_pos, view_range, is_captured):
        if self.last_state is None or self.last_action is None:
            return

        new_dist = self.env.get_distance(current_pos, player_pos)
        can_see = self.env.has_line_of_sight(current_pos, player_pos, view_range)

        # Reward formulation
        reward = -1.0  # Step penalty
        if is_captured:
            reward += 100.0
        else:
            if can_see:
                reward += 15.0
            if self.last_dist is not None and new_dist < self.last_dist:
                reward += 6.0
            elif self.last_dist is not None and new_dist > self.last_dist:
                reward -= 6.0

        next_state = self._get_state(current_pos, player_pos, view_range)
        if next_state not in self.q_table:
            self.q_table[next_state] = [0.0, 0.0, 0.0, 0.0]

        # Bellman TD update
        old_val = self.q_table[self.last_state][self.last_action]
        next_max = max(self.q_table[next_state])
        td_target = reward + self.gamma * next_max
        self.q_table[self.last_state][self.last_action] = old_val + self.alpha * (td_target - old_val)

    def save_q_table(self, filepath):
        """Serialize Q-table to JSON file on disk."""
        os.makedirs(os.path.dirname(os.path.abspath(filepath)), exist_ok=True)
        with open(filepath, "w") as f:
            json.dump(self.q_table, f, indent=2)

    def load_q_table(self, filepath):
        """Load pre-trained Q-table from JSON file on disk."""
        if os.path.exists(filepath):
            with open(filepath, "r") as f:
                self.q_table = json.load(f)
            return True
        return False

def train_rl_policy(env, num_episodes=300, save_path=None, seed=42):
    """
    Offline training loop for Reinforcement Learning Guards.
    Guards play against MaxMinPlayer across multiple self-play episodes.
    Learned policy is exported to save_path.
    """
    rng = random.Random(seed)
    shared_q_table = {}
    
    # Check if pre-existing weights exist
    if save_path and os.path.exists(save_path):
        try:
            with open(save_path, "r") as f:
                shared_q_table = json.load(f)
        except Exception:
            shared_q_table = {}

    for ep in range(1, num_episodes + 1):
        ep_seed = seed + ep * 13
        guard_positions, player_pos = env.initialize_positions(num_guards=3, random_seed=ep_seed)
        
        # Epsilon decay: from 0.7 down to 0.05
        current_epsilon = max(0.05, 0.7 * (1.0 - ep / num_episodes))
        
        guards = [
            ReinforcementLearningGuard(env, epsilon=current_epsilon, q_table=shared_q_table, random_seed=ep_seed + i)
            for i in range(3)
        ]
        player = MaxMinPlayer(env, lookahead_depth=3)
        
        player_hp = 3
        max_duration = 60
        guard_view_range = 6.4
        attack_range = 1.5
        
        for t in range(1, max_duration + 1):
            new_guards = []
            for i, g in enumerate(guards):
                next_pos = g.select_action(guard_positions[i], player_pos, guard_view_range, all_guards=guard_positions)
                new_guards.append(next_pos)
            guard_positions = new_guards
            
            # Player moves (with 120% speed bonus)
            player_pos = player.select_action(player_pos, guard_positions)
            if player.should_take_speed_bonus_step():
                player_pos = player.select_action(player_pos, guard_positions)
                
            # Check capture
            guards_in_range = sum(
                1 for g in guard_positions
                if ((g[0]-player_pos[0])**2 + (g[1]-player_pos[1])**2)**0.5 <= attack_range
            )
            if guards_in_range > 0:
                player_hp -= guards_in_range
                if player_hp <= 0:
                    for idx, g in enumerate(guards):
                        g.update_q_value(guard_positions[idx], player_pos, guard_view_range, is_captured=True)
                    break
                    
            for idx, g in enumerate(guards):
                g.update_q_value(guard_positions[idx], player_pos, guard_view_range, is_captured=False)

    if save_path:
        os.makedirs(os.path.dirname(os.path.abspath(save_path)), exist_ok=True)
        with open(save_path, "w") as f:
            json.dump(shared_q_table, f, indent=2)

    return shared_q_table
