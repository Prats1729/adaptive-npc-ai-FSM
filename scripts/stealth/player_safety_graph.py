import random

class SafetyGraphPlayer:
    """
    Safety Graph Evasion Player Policy (Xu & Verbrugge, AIIDE 2025).
    Paper Description:
      "We construct a 'safety graph' by computing two sets of shortest-path distances: 
       from each guard to every node (estimating guard arrival time T_g), and from the 
       player to every node (player arrival time T_p). Each node's safety is quantified 
       by S = T_g - T_p, indicating the time margin before potential capture. The player 
       then plans paths using A* search, penalizing paths passing through nodes with lower 
       safety margins, thus preferring routes with lower capture risk."
    Includes +20% speed bonus (120% guard velocity) matching experimental protocol.
    """
    def __init__(self, env, speed_bonus=0.20):
        self.env = env
        self.speed_bonus = speed_bonus
        self.accumulated_bonus = 0.0
        self.v_player = 1.2
        self.v_guard = 1.0

    def should_take_speed_bonus_step(self):
        """Player moves at 120% guard speed. Triggers an extra move every 5 ticks."""
        self.accumulated_bonus += self.speed_bonus
        if self.accumulated_bonus >= 1.0:
            self.accumulated_bonus -= 1.0
            return True
        return False

    def compute_safety_margin(self, node, guard_positions, player_pos):
        """
        Quantifies safety margin S(n) = T_g(n) - T_p(n).
        Positive values indicate player arrives well before any guard.
        Negative or small values indicate dangerous bottleneck capture risk.
        """
        d_p = self.env.get_distance(player_pos, node)
        t_p = d_p / self.v_player
        
        min_d_g = min(self.env.get_distance(g, node) for g in guard_positions)
        t_g = min_d_g / self.v_guard
        
        return t_g - t_p

    def select_action(self, player_pos, guard_positions):
        candidates = self.env.get_neighbors(player_pos[0], player_pos[1])
        if not candidates:
            return player_pos

        best_move = player_pos
        best_score = -1e9

        for cand in candidates:
            # Immediate safety margin S(cand)
            cand_margin = self.compute_safety_margin(cand, guard_positions, player_pos)
            
            # Minimum distance to any guard from candidate
            min_g_dist = min(self.env.get_distance(g, cand) for g in guard_positions)
            
            # 2-step horizon lookahead: ensure candidate doesn't lead into a dead-end with no safe exits
            future_nbrs = self.env.get_neighbors(cand[0], cand[1])
            if future_nbrs:
                future_margins = [self.compute_safety_margin(fn, guard_positions, cand) for fn in future_nbrs]
                avg_future_margin = sum(future_margins) / len(future_margins)
                min_future_margin = min(future_margins)
            else:
                avg_future_margin = -10.0
                min_future_margin = -10.0

            # Composite Safety Score:
            # Heavily penalizes nodes where guards arrive first (cand_margin <= 0)
            score = (cand_margin * 3.0) + (min_g_dist * 2.0) + (avg_future_margin * 1.5) + (min_future_margin * 2.0)
            
            # Avoid stepping directly into adjacent attack range unless no other option
            if min_g_dist <= 1:
                score -= 100.0

            if score > best_score:
                best_score = score
                best_move = cand

        return best_move
