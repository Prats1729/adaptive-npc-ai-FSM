import json
import math
from collections import deque

class GridEnvironment:
    def __init__(self, map_file_path):
        with open(map_file_path, "r") as f:
            data = json.load(f)
        self.map_name = data.get("name", "Unknown")
        self.rows = data["rows"]
        self.cols = data["cols"]
        self.grid = data["grid"]
        self.walkable_cells = [
            (r, c) for r in range(self.rows) for c in range(self.cols) if self.grid[r][c] == 0
        ]
        self._precompute_connectivity()
        self._precompute_distance_matrix()

    def is_walkable(self, r, c):
        return 0 <= r < self.rows and 0 <= c < self.cols and self.grid[r][c] == 0

    def get_neighbors(self, r, c):
        neighbors = []
        for dr, dc in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
            nr, nc = r + dr, c + dc
            if self.is_walkable(nr, nc):
                neighbors.append((nr, nc))
        return neighbors

    def _precompute_connectivity(self):
        # Connectivity Field N(n) = kappa - |Nbr(n)|, where kappa = 4 for 4-connected grid
        self.connectivity_field = {}
        for r, c in self.walkable_cells:
            nbrs = len(self.get_neighbors(r, c))
            self.connectivity_field[(r, c)] = 4 - nbrs

    def _precompute_distance_matrix(self):
        # All-pairs BFS shortest-path graph distances for efficiency
        self.dist_matrix = {}
        for start in self.walkable_cells:
            self.dist_matrix[start] = {}
            queue = deque([(start, 0)])
            visited = {start: 0}
            while queue:
                curr, dist = queue.popleft()
                self.dist_matrix[start][curr] = dist
                for nbr in self.get_neighbors(curr[0], curr[1]):
                    if nbr not in visited:
                        visited[nbr] = dist + 1
                        queue.append((nbr, dist + 1))

    def get_distance(self, cell_a, cell_b):
        return self.dist_matrix.get(cell_a, {}).get(cell_b, 9999)

    def has_line_of_sight(self, pos_a, pos_b, max_range=8.0):
        # Euclidean distance check first
        eucl = math.hypot(pos_a[0] - pos_b[0], pos_a[1] - pos_b[1])
        if eucl > max_range:
            return False
        if pos_a == pos_b:
            return True

        # Bresenham-style raycast through grid
        r0, c0 = pos_a
        r1, c1 = pos_b
        dr = abs(r1 - r0)
        dc = abs(c1 - c0)
        sr = 1 if r0 < r1 else -1
        sc = 1 if c0 < c1 else -1
        err = dr - dc

        curr_r, curr_c = r0, c0
        while (curr_r, curr_c) != (r1, c1):
            if (curr_r, curr_c) != pos_a and not self.is_walkable(curr_r, curr_c):
                return False
            e2 = 2 * err
            if e2 > -dc:
                err -= dc
                curr_r += sr
            if e2 < dr:
                err += dr
                curr_c += sc
        return True

    def initialize_positions(self, num_guards=3, random_seed=None):
        import random
        rng = random.Random(random_seed)
        
        # Guards start at distinct random walkable cells
        guard_positions = []
        available_cells = list(self.walkable_cells)
        for _ in range(num_guards):
            g_pos = rng.choice(available_cells)
            guard_positions.append(g_pos)
            available_cells.remove(g_pos)
        
        # Player is placed at a cell maximizing minimum shortest-path distance to all guards, 
        # not within initial line of sight of any guard (Paper Section "Scenario Details")
        best_player_pos = None
        max_min_dist = -1
        
        for candidate in self.walkable_cells:
            # Check if out of sight from all guards
            if all(not self.has_line_of_sight(g, candidate) for g in guard_positions):
                min_dist_to_guards = min(self.get_distance(g, candidate) for g in guard_positions)
                if min_dist_to_guards > max_min_dist:
                    max_min_dist = min_dist_to_guards
                    best_player_pos = candidate
                    
        if best_player_pos is None:
            # Fallback if map has open vision everywhere
            best_player_pos = max(
                self.walkable_cells, 
                key=lambda c: min(self.get_distance(g, c) for g in guard_positions)
            )
            
        return guard_positions, best_player_pos
