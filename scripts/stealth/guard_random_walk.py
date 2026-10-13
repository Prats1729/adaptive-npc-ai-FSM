import random

class RandomWalkGuard:
    """
    Baseline Random Walk Guard AI (Xu & Verbrugge, AIIDE 2025).
    Paper Description:
      "Each guard randomly selects one reachable neighboring node or cell at each 
       decision tick, disregarding previous states or player positions."
    """
    def __init__(self, env, random_seed=None):
        self.env = env
        self.rng = random.Random(random_seed)

    def select_action(self, guard_pos, player_pos, view_range, all_guards=None):
        nbrs = self.env.get_neighbors(guard_pos[0], guard_pos[1])
        if not nbrs:
            return guard_pos
        return self.rng.choice(nbrs)
