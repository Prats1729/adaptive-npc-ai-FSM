from collections import deque

class MaxMinPlayer:
    """
    MaxMin Evasive Player Policy (Xu & Verbrugge, AIIDE 2025).
    At each step, simulates moves several steps ahead, evaluating each path
    by calculating the minimum distance to any guard along that path.
    Chooses the move that maximizes this minimum distance.
    """
    def __init__(self, env, lookahead_depth=3):
        self.env = env
        self.lookahead_depth = lookahead_depth
        self.step_counter = 0

    def select_action(self, player_pos, guard_positions):
        neighbors = self.env.get_neighbors(player_pos[0], player_pos[1])
        if not neighbors:
            return player_pos

        best_move = player_pos
        best_score = -1e9

        # Evaluate candidate 1st moves
        for move in neighbors:
            # Multi-step lookahead from this move
            score = self._evaluate_min_guard_dist(move, guard_positions, depth=self.lookahead_depth)
            if score > best_score:
                best_score = score
                best_move = move

        return best_move

    def _evaluate_min_guard_dist(self, start_pos, guard_positions, depth):
        # BFS up to lookahead depth, finding worst-case (minimum) distance to any guard
        min_overall_dist = 1e9
        queue = deque([(start_pos, 0)])
        visited = {start_pos: 0}

        while queue:
            curr, d = queue.popleft()
            # Distance from this projected node to closest guard
            for g_pos in guard_positions:
                dist = self.env.get_distance(curr, g_pos)
                if dist < min_overall_dist:
                    min_overall_dist = dist

            if d < depth:
                for nbr in self.env.get_neighbors(curr[0], curr[1]):
                    if nbr not in visited or visited[nbr] > d + 1:
                        visited[nbr] = d + 1
                        queue.append((nbr, d + 1))

        return min_overall_dist

    def should_take_speed_bonus_step(self):
        # In Capture Experiment, player moves at 120% speed (6 moves for every 5 guard moves)
        self.step_counter += 1
        return (self.step_counter % 5 == 0)
