from .guard_cpf import CompositePotentialFieldGuard

class PredictiveInterceptionGuard(CompositePotentialFieldGuard):
    """
    Novel Contribution 1: Predictive Interception Potential Field (PI-PF).
    Targeting Gap 1 (Reactive Lag Flaw) in Xu & Verbrugge (2025).
    Instead of pulling the guard to historical sighting p_t, estimates
    player escape trajectory and propagates attractive potential from the
    predicted future intercept corridor.
    """
    def __init__(self, env, prediction_horizon=2):
        super().__init__(env)
        self.prediction_horizon = prediction_horizon
        self.prev_player_pos = None

    def select_action(self, guard_pos, player_pos, view_range, all_guards=None):
        can_see_player = self.env.has_line_of_sight(guard_pos, player_pos, view_range)
        guards_list = all_guards if all_guards else [guard_pos]
        
        # 1. Update Weight Scheduling
        if can_see_player:
            self.w_I = self.w_I_max
        else:
            self.w_I = max(self.w_I_base, self.w_I - self.delta_w)
            
        remaining_budget = 1.0 - self.w_I
        base_ratio_sum = self.w_C_base + self.w_N_base
        self.w_C = remaining_budget * (self.w_C_base / base_ratio_sum)
        self.w_N = remaining_budget * (self.w_N_base / base_ratio_sum)

        # 2. Update Information Field with Predictive Interception
        for cell in self.env.walkable_cells:
            self.I_field[cell] *= self.rho
            
        if can_see_player:
            # Calculate trajectory vector
            target_seed = player_pos
            if self.prev_player_pos is not None and self.prev_player_pos != player_pos:
                dr = player_pos[0] - self.prev_player_pos[0]
                dc = player_pos[1] - self.prev_player_pos[1]
                
                # Project forward along escape corridor
                pred_r = player_pos[0] + dr * self.prediction_horizon
                pred_c = player_pos[1] + dc * self.prediction_horizon
                
                # If projected cell is walkable, set as attractive intercept seed
                if self.env.is_walkable(pred_r, pred_c):
                    target_seed = (pred_r, pred_c)
                else:
                    # Fallback to nearest walkable neighbor of prediction
                    nbrs = self.env.get_neighbors(player_pos[0], player_pos[1])
                    if nbrs:
                        target_seed = max(nbrs, key=lambda n: (n[0]-self.prev_player_pos[0])*dr + (n[1]-self.prev_player_pos[1])*dc)
            
            self.prev_player_pos = player_pos
            
            # Seed attractive negative potential at predicted intercept node
            for cell in self.env.walkable_cells:
                d = self.env.get_distance(target_seed, cell)
                self.I_field[cell] = -self.I0 * (self.gamma_I ** d)
        else:
            self.prev_player_pos = None

        # 3. Update Confidence Field across all guards
        for cell in self.env.walkable_cells:
            injection = sum(self.C0 * (self.gamma_C ** self.env.get_distance(g, cell)) for g in guards_list)
            self.C_field[cell] = (self.rho * self.C_field[cell]) + injection

        # 4. Compute Composite Potential
        P = {}
        for cell in self.env.walkable_cells:
            P[cell] = (self.w_I * self.I_field[cell] + 
                       self.w_C * self.C_field[cell] + 
                       self.w_N * self.N_field.get(cell, 0.0))

        # 5. Kernel-Filtered Evaluation
        candidates = self.env.get_neighbors(guard_pos[0], guard_pos[1])
        if not candidates:
            return guard_pos

        best_next_node = guard_pos
        min_kernel_potential = 1e9

        for cand in candidates:
            k_val = self._compute_kernel_smoothed_potential(cand, P)
            if k_val < min_kernel_potential:
                min_kernel_potential = k_val
                best_next_node = cand

        return best_next_node
