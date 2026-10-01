class CompositePotentialFieldGuard:
    """
    Composite Potential Field Guard AI (Kaijie Xu & Clark Verbrugge, AIIDE 2025).
    Equations (1)-(7) and Table 2 Hyperparameters:
      I0 = 5.0, C0 = 1.0
      gamma_I = 0.9, gamma_C = 0.8
      rho = 0.95
      kernel_lambda = 0.8, kernel_delta = 3
      w_I_base = 0.4, w_C_patrol = 0.5, w_N_patrol = 0.1, w_I_max = 0.9, delta_w = 0.05
    """
    def __init__(self, env):
        self.env = env
        
        # Hyperparameters
        self.I0 = 5.0
        self.C0 = 1.0
        self.gamma_I = 0.9
        self.gamma_C = 0.8
        self.rho = 0.95
        self.kernel_lambda = 0.8
        self.kernel_delta = 3
        
        self.w_I_base = 0.4
        self.w_C_base = 0.5
        self.w_N_base = 0.1
        self.w_I_max = 0.9
        self.delta_w = 0.05
        
        self.w_I = self.w_I_base
        self.w_C = self.w_C_base
        self.w_N = self.w_N_base
        
        # Initialize fields over all walkable cells
        self.I_field = {c: 0.0 for c in self.env.walkable_cells}
        self.C_field = {c: 0.0 for c in self.env.walkable_cells}
        self.N_field = self.env.connectivity_field

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

        # 2. Update Information Field
        # Temporal decay
        for cell in self.env.walkable_cells:
            self.I_field[cell] *= self.rho
            
        if can_see_player:
            # Propagate attractive negative potential from player's detected location
            for cell in self.env.walkable_cells:
                d = self.env.get_distance(player_pos, cell)
                self.I_field[cell] = -self.I0 * (self.gamma_I ** d)

        # 3. Update Confidence Field
        # Temporal decay + spatial footprint injection across all guards (Equation 2)
        for cell in self.env.walkable_cells:
            injection = sum(self.C0 * (self.gamma_C ** self.env.get_distance(g, cell)) for g in guards_list)
            self.C_field[cell] = (self.rho * self.C_field[cell]) + injection

        # 4. Compute Composite Potential P(n) for all cells
        P = {}
        for cell in self.env.walkable_cells:
            P[cell] = (self.w_I * self.I_field[cell] + 
                       self.w_C * self.C_field[cell] + 
                       self.w_N * self.N_field.get(cell, 0.0))

        # 5. Kernel-Filtered Evaluation over 4 candidate neighbor cells
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

    def _compute_kernel_smoothed_potential(self, cand_pos, P):
        num = 0.0
        den = 0.0
        for cell in self.env.walkable_cells:
            d = self.env.get_distance(cand_pos, cell)
            if d <= self.kernel_delta:
                weight = self.kernel_lambda ** d
                num += weight * P[cell]
                den += weight
        return num / den if den > 0 else P.get(cand_pos, 0.0)
