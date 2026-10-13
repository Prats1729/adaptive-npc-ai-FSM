import random

class StalenessFSMGuard:
    """
    Staleness-Based FSM Guard AI (Al Enezi & Verbrugge 2020, Xu & Verbrugge 2025).
    Paper Description:
      "Guards maintain a 'staleness' value (time since last patrol) for each node. 
       The FSM selects the next patrol location based on nodes with the highest staleness, 
       ensuring frequent visits to neglected areas while still enabling standard 
       Investigate-Chase transitions when encountering the player."
    Parameters from Table 2:
      Staleness Increment = 1
      T_investigate = 3s
      T_lose_sight = 2s
      Chase Max Time = 10s
      Return Max Time = 5s
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
        
        # Staleness memory map: tracks ticks since each walkable cell was inspected
        self.staleness_map = {c: 0 for c in self.env.walkable_cells}

    def select_action(self, guard_pos, player_pos, view_range, all_guards=None):
        if self.spawn_pos is None:
            self.spawn_pos = guard_pos
            
        # Update staleness map: increment all walkable cells by 1
        for cell in self.env.walkable_cells:
            self.staleness_map[cell] += 1
            
        # Reset staleness for cells visited or directly visible to the guard
        self.staleness_map[guard_pos] = 0
        nbrs_near = self.env.get_neighbors(guard_pos[0], guard_pos[1])
        for n in nbrs_near:
            self.staleness_map[n] = 0

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

        # State Execution
        if self.state == "CHASE":
            return self._step_toward(guard_pos, self.last_known_player_pos)
            
        elif self.state == "INVESTIGATE":
            if self.last_known_player_pos and guard_pos != self.last_known_player_pos:
                return self._step_toward(guard_pos, self.last_known_player_pos)
            else:
                # Local scanning
                nbrs = self.env.get_neighbors(guard_pos[0], guard_pos[1])
                return self.rng.choice(nbrs) if nbrs else guard_pos
                
        elif self.state == "RETURN":
            return self._step_toward(guard_pos, self.spawn_pos)
            
        else:  # PATROL driven by Staleness Metric
            if self.patrol_target is None or guard_pos == self.patrol_target:
                # Select the node with highest staleness to prioritize neglected areas
                # Sample top stale candidates within reasonable radius to avoid erratic teleport-like targets
                sorted_by_staleness = sorted(
                    self.env.walkable_cells, 
                    key=lambda c: self.staleness_map.get(c, 0), 
                    reverse=True
                )
                # Take top 10% most stale cells and pick closest to guard to form coherent patrol trajectories
                top_stale = sorted_by_staleness[:max(5, len(sorted_by_staleness) // 10)]
                self.patrol_target = min(top_stale, key=lambda c: self.env.get_distance(guard_pos, c))
                
            return self._step_toward(guard_pos, self.patrol_target)

    def _step_toward(self, current_pos, target_pos):
        if current_pos == target_pos:
            return current_pos
        nbrs = self.env.get_neighbors(current_pos[0], current_pos[1])
        if not nbrs:
            return current_pos
        best_nbr = min(nbrs, key=lambda n: self.env.get_distance(n, target_pos))
        return best_nbr
