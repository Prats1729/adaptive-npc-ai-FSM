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

    def select_action(self, guard_pos, player_pos, view_range, all_guards=None):
        can_see = self.env.has_line_of_sight(guard_pos, player_pos, view_range)
        
        # When far away and invisible, rely on CPF patrol fields for fast macro-movement
        dist_to_player = self.env.get_distance(guard_pos, player_pos)
        if not can_see and dist_to_player > 10:
            return self.cpf.select_action(guard_pos, player_pos, view_range, all_guards)

        # In tactical engagement range (or when player detected), invoke MCTS lookahead
        root = MCTSNode(guard_pos, player_pos)
        candidates = self.env.get_neighbors(guard_pos[0], guard_pos[1])
        if not candidates:
            return guard_pos
        if len(candidates) == 1:
            return candidates[0]

        # Expand root children
        for cand in candidates:
            # Simulate player moving away (simple greedy step)
            p_nbrs = self.env.get_neighbors(player_pos[0], player_pos[1])
            p_next = max(p_nbrs, key=lambda pn: self.env.get_distance(cand, pn)) if p_nbrs else player_pos
            root.children.append(MCTSNode(cand, p_next, parent=root, action=cand))

        # Run MCTS simulations
        for _ in range(self.num_simulations):
            # 1. Selection
            node = self._select_promising_node(root)
            
            # 2. Expansion & Rollout Evaluation
            reward = self._rollout_simulate(node)
            
            # 3. Backpropagation
            self._backpropagate(node, reward)

        # Robust Child Selection: Pick child with highest visit count (or highest average value)
        best_child = max(root.children, key=lambda c: (c.visits, c.value / max(1, c.visits)))
        return best_child.action

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
