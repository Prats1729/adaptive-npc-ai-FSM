import random

class BaselineFSMGuard:
    """
    Classical Finite State Machine Guard AI (Xu & Verbrugge, AIIDE 2025).
    States: PATROL, INVESTIGATE, CHASE, RETURN
    Parameters from Paper Table 2:
      T_investigate = 3s
      T_lose_sight = 2s
      T_chase_max = 10s
      T_return_max = 5s
    """
    def __init__(self, env, random_seed=None):
        self.env = env
        self.rng = random.Random(random_seed)
        
        self.state = "PATROL"
        self.state_timer = 0
        self.lose_sight_timer = 0
        
        self.last_known_player_pos = None
        self.patrol_target = None
        self.spawn_pos = None

    def select_action(self, guard_pos, player_pos, view_range):
        if self.spawn_pos is None:
            self.spawn_pos = guard_pos
            
        can_see_player = self.env.has_line_of_sight(guard_pos, player_pos, view_range)
        
        # State Transitions
        if can_see_player:
            self.state = "CHASE"
            self.last_known_player_pos = player_pos
            self.lose_sight_timer = 0
            self.state_timer = 0
        else:
            if self.state == "CHASE":
                self.lose_sight_timer += 1
                if self.lose_sight_timer >= 2:  # T Lose Sight = 2s
                    self.state = "INVESTIGATE"
                    self.state_timer = 0
            elif self.state == "INVESTIGATE":
                self.state_timer += 1
                if self.state_timer >= 3:  # T Investigate = 3s
                    self.state = "RETURN"
                    self.state_timer = 0
            elif self.state == "RETURN":
                self.state_timer += 1
                if self.state_timer >= 5 or guard_pos == self.spawn_pos:  # Return Max = 5s
                    self.state = "PATROL"
                    self.patrol_target = None
                    self.state_timer = 0
                    
        # State Actions
        if self.state == "CHASE":
            return self._step_toward(guard_pos, self.last_known_player_pos)
            
        elif self.state == "INVESTIGATE":
            if self.last_known_player_pos and guard_pos != self.last_known_player_pos:
                return self._step_toward(guard_pos, self.last_known_player_pos)
            else:
                # Small local random step around investigation area
                nbrs = self.env.get_neighbors(guard_pos[0], guard_pos[1])
                return self.rng.choice(nbrs) if nbrs else guard_pos
                
        elif self.state == "RETURN":
            return self._step_toward(guard_pos, self.spawn_pos)
            
        else:  # PATROL
            if self.patrol_target is None or guard_pos == self.patrol_target:
                # Sector-bounded patrol: stealth guards patrol their designated sector/room (radius <= 12)
                # matching the paper's description ("They patrol random paths until detecting a player")
                patrol_radius = 12
                candidates = [c for c in self.env.walkable_cells if self.env.get_distance(c, self.spawn_pos) <= patrol_radius]
                self.patrol_target = self.rng.choice(candidates) if candidates else self.spawn_pos
            return self._step_toward(guard_pos, self.patrol_target)

    def _step_toward(self, current_pos, target_pos):
        if current_pos == target_pos:
            return current_pos
        nbrs = self.env.get_neighbors(current_pos[0], current_pos[1])
        if not nbrs:
            return current_pos
        # Step that minimizes shortest-path distance to target
        best_nbr = min(nbrs, key=lambda n: self.env.get_distance(n, target_pos))
        return best_nbr
