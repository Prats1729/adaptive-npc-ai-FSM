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

    def select_action(self, guard_pos, player_pos, view_range=None, all_guards=None):
        if guard_pos == player_pos:
            return guard_pos
            
        nbrs = self.env.get_neighbors(guard_pos[0], guard_pos[1])
        if not nbrs:
            return guard_pos
            
        # Greedily take the step that minimizes shortest-path geodesic distance to player
        best_nbr = min(nbrs, key=lambda n: self.env.get_distance(n, player_pos))
        return best_nbr
