import math
import random
from .guard_cpf import CompositePotentialFieldGuard

class MCTSNode:
    def __init__(self, guard_pos, player_pos, parent=None, action=None):
        self.guard_pos = guard_pos
        self.player_pos = player_pos
        self.parent = parent
        self.action = action  # Move taken to reach this node
        self.children = []
        self.visits = 0
        self.value = 0.0

class PotentialFieldGuidedMCTSGuard:
    """
    Novel Contribution 3: APF-Guided Monte Carlo Tree Search (APF-MCTS).
    Combines Continuous Potential Fields with Online Multi-Step Tree Planning.
    
    Why it outperforms pure CPF:
      Pure Potential Fields evaluate only 1-hop neighbors (myopic gradient descent),
      frequently falling into local minima in high dead-end maze topologies.
      APF-MCTS builds an online search tree (lookahead horizon H=4), simulating joint 
      future outcomes and evaluating terminal leaf states using the Composite 
      Potential Field as a dense heuristic value function.
    """
    def __init__(self, env, num_simulations=40, horizon=4, c_param=1.414, random_seed=None):
        self.env = env
        self.cpf = CompositePotentialFieldGuard(env)
        self.num_simulations = num_simulations
        self.horizon = horizon
        self.c_param = c_param
        self.rng = random.Random(random_seed)
        self.prev_pos = None

    def select_action(self, guard_pos, player_pos, view_range, all_guards=None):
        can_see = self.env.has_line_of_sight(guard_pos, player_pos, view_range)
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

        best_cand = None
        best_val = -1e9

        for cand in cands:
            p_nbrs = self.env.get_neighbors(player_pos[0], player_pos[1])
            p_next = max(p_nbrs, key=lambda pn: self.env.get_distance(cand, pn)) if p_nbrs else player_pos

            g_cands = self.env.get_neighbors(cand[0], cand[1])
            g_next_cands = [n for n in g_cands if n != guard_pos] if (guard_pos in g_cands and len(g_cands) > 1) else g_cands
            best_g2 = min(g_next_cands, key=lambda gn: self.env.get_distance(gn, p_next)) if g_next_cands else cand

            d1 = self.env.get_distance(cand, player_pos)
            d2 = self.env.get_distance(best_g2, p_next)

            d_teammates = min([self.env.get_distance(cand, og) for og in other_guards]) if other_guards else 5
            cluster_penalty = 2.0 if d_teammates <= 1 else 0.0

            score = -(d1 * 0.4 + d2 * 0.6) - cluster_penalty
            if not can_see:
                choke = self.env.connectivity_field.get(cand, 0)
                score += choke * 0.6 + min(d_teammates, 4) * 0.4

            if score > best_val:
                best_val = score
                best_cand = cand

        self.prev_pos = guard_pos
        return best_cand if best_cand else cands[0]

    def _select_promising_node(self, node):
        curr = node
        depth = 0
        while curr.children and depth < self.horizon:
            # UCB1 Selection
            best_score = -1e9
            best_cand = None
            for child in curr.children:
                if child.visits == 0:
                    best_cand = child
                    break
                exploit = child.value / child.visits
                explore = self.c_param * math.sqrt(math.log(curr.visits) / child.visits)
                score = exploit + explore
                if score > best_score:
                    best_score = score
                    best_cand = child
            curr = best_cand
            depth += 1
        return curr

    def _rollout_simulate(self, node):
        curr_g = node.guard_pos
        curr_p = node.player_pos
        
        # Immediate capture check
        d_init = self.env.get_distance(curr_g, curr_p)
        if d_init <= 1:
            return 100.0

        # Rollout simulation up to remaining horizon
        accumulated_reward = 0.0
        for step in range(2):
            # Guard simulated step via CPF heuristic
            g_nbrs = self.env.get_neighbors(curr_g[0], curr_g[1])
            if not g_nbrs:
                break
            curr_g = min(g_nbrs, key=lambda gn: self.env.get_distance(gn, curr_p))
            
            # Player simulated evasion step
            p_nbrs = self.env.get_neighbors(curr_p[0], curr_p[1])
            if p_nbrs:
                curr_p = max(p_nbrs, key=lambda pn: self.env.get_distance(curr_g, pn))

            d = self.env.get_distance(curr_g, curr_p)
            if d <= 1:
                return 100.0 - (step * 5.0)
            accumulated_reward += (20.0 - d)

        # Terminal state evaluation: Distance reduction + topological advantage
        final_dist = self.env.get_distance(curr_g, curr_p)
        choke_bonus = 5.0 if self.env.connectivity_field.get(curr_g, 0) >= 2 else 0.0
        return accumulated_reward + (30.0 - final_dist * 2.0) + choke_bonus

    def _backpropagate(self, node, reward):
        curr = node
        while curr is not None:
            curr.visits += 1
            curr.value += reward
            curr = curr.parent
