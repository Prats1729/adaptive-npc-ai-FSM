class CheatGuard:
    """
    Idealized Cheat Baseline Guard AI (Xu & Verbrugge, AIIDE 2025).
    Paper Description:
      "Cheat: Guards directly follow the shortest possible path toward the player's 
       current location, serving as an idealized baseline for theoretical optimal performance."
    Possesses omniscient global knowledge of the player's current position at all times.
    """
    def __init__(self, env):
        self.env = env
        self.prev_pos = None

    def select_action(self, guard_pos, player_pos, view_range=None, all_guards=None):
        if guard_pos == player_pos:
            return guard_pos
            
        nbrs = self.env.get_neighbors(guard_pos[0], guard_pos[1])
        if not nbrs:
            return guard_pos
            
        # Prevent immediate reversal unless dead end
        cands = [n for n in nbrs if n != self.prev_pos] if (self.prev_pos in nbrs and len(nbrs) > 1) else nbrs
            
        # Greedily take the step that minimizes shortest-path geodesic distance to player
        best_nbr = min(cands, key=lambda n: self.env.get_distance(n, player_pos))
        self.prev_pos = guard_pos
        return best_nbr
