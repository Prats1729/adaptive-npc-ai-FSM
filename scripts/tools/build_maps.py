import json
import os
from collections import deque

def check_connectivity(grid, rows, cols):
    walkable = [(r, c) for r in range(rows) for c in range(cols) if grid[r][c] == 0]
    if not walkable:
        return False, 0
    start = walkable[0]
    visited = set([start])
    queue = deque([start])
    while queue:
        r, c = queue.popleft()
        for dr, dc in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
            nr, nc = r + dr, c + dc
            if 0 <= nr < rows and 0 <= nc < cols and grid[nr][nc] == 0:
                if (nr, nc) not in visited:
                    visited.add((nr, nc))
                    queue.append((nr, nc))
    return len(visited) == len(walkable), len(visited)

def adjust_grid(grid, rows, cols, target_walkable):
    current = sum(row.count(0) for row in grid)
    while current < target_walkable:
        for r in range(1, rows - 1):
            for c in range(1, cols - 1):
                if grid[r][c] == 1:
                    grid[r][c] = 0
                    current += 1
                    if current == target_walkable:
                        break
            if current == target_walkable:
                break
                
    while current > target_walkable:
        for r in range(1, rows - 1):
            for c in range(1, cols - 1):
                if grid[r][c] == 0:
                    grid[r][c] = 1
                    connected, _ = check_connectivity(grid, rows, cols)
                    if connected:
                        current -= 1
                        if current == target_walkable:
                            break
                    else:
                        grid[r][c] = 0
            if current == target_walkable:
                break
    return check_connectivity(grid, rows, cols)

def build_test_maze():
    rows, cols = 20, 20
    grid = [[1 for _ in range(cols)] for _ in range(rows)]
    for c in range(1, cols - 1):
        grid[1][c] = 0
        grid[rows - 2][c] = 0
    for r in range(1, rows - 1):
        grid[r][1] = 0
        grid[r][cols - 2] = 0
    for c in range(3, 17):
        grid[3][c] = 0
        grid[5][c] = 0
        grid[7][c] = 0
        grid[9][c] = 0
        grid[11][c] = 0
        grid[13][c] = 0
        grid[15][c] = 0
        grid[17][c] = 0
    for r in range(3, 10):
        grid[r][3] = 0
        grid[r][16] = 0
    for r in range(9, 17):
        grid[r][6] = 0
        grid[r][13] = 0
    for r in range(5, 15):
        grid[r][9] = 0
        grid[r][10] = 0
    grid[2][1] = 0
    grid[2][18] = 0
    grid[18][1] = 0
    grid[18][18] = 0
    adjust_grid(grid, rows, cols, 206)
    _, count = check_connectivity(grid, rows, cols)
    print(f"Test Maze: {rows}x{cols} -> Walkable: {count}/{rows*cols} ({count/(rows*cols):.1%})")
    return {"name": "Test (Maze)", "rows": rows, "cols": cols, "walkable_count": count, "grid": grid}

def build_miami():
    rows, cols = 26, 21
    grid = [[0 for _ in range(cols)] for _ in range(rows)]
    for c in range(cols):
        grid[0][c] = 1
        grid[rows - 1][c] = 1
    for r in range(rows):
        grid[r][0] = 1
        grid[r][cols - 1] = 1
    for r in range(3, 8):
        for c in range(3, 8): grid[r][c] = 1
    for r in range(3, 8):
        for c in range(13, 18): grid[r][c] = 1
    for r in range(11, 16):
        for c in range(8, 13): grid[r][c] = 1
    for r in range(18, 23):
        for c in range(3, 8): grid[r][c] = 1
    for r in range(18, 23):
        for c in range(13, 18): grid[r][c] = 1
    for r in range(9, 18):
        grid[r][4] = 1
        grid[r][16] = 1
    grid[13][4] = 0
    grid[14][4] = 0
    grid[13][16] = 0
    grid[14][16] = 0
    adjust_grid(grid, rows, cols, 377)
    _, count = check_connectivity(grid, rows, cols)
    print(f"Miami: {rows}x{cols} -> Walkable: {count}/{rows*cols} ({count/(rows*cols):.1%})")
    return {"name": "Miami", "rows": rows, "cols": cols, "walkable_count": count, "grid": grid}

def build_arkham():
    # 28x26: 548 walkable (75%), 180 wall (25%)
    rows, cols = 28, 26
    grid = [[0 for _ in range(cols)] for _ in range(rows)]
    for c in range(cols):
        grid[0][c] = 1
        grid[rows - 1][c] = 1
    for r in range(rows):
        grid[r][0] = 1
        grid[r][cols - 1] = 1
    # Asylum wards / cells blocks
    for r in range(3, 10):
        for c in range(3, 10): grid[r][c] = 1
    for r in range(3, 10):
        for c in range(16, 23): grid[r][c] = 1
    for r in range(17, 24):
        for c in range(3, 10): grid[r][c] = 1
    for r in range(17, 24):
        for c in range(16, 23): grid[r][c] = 1
    adjust_grid(grid, rows, cols, 548)
    _, count = check_connectivity(grid, rows, cols)
    print(f"Arkham: {rows}x{cols} -> Walkable: {count}/{rows*cols} ({count/(rows*cols):.1%})")
    return {"name": "Arkham", "rows": rows, "cols": cols, "walkable_count": count, "grid": grid}

def build_tlou():
    # 14x30: 255 walkable (61%), 165 wall (39%)
    rows, cols = 14, 30
    grid = [[0 for _ in range(cols)] for _ in range(rows)]
    for c in range(cols):
        grid[0][c] = 1
        grid[rows - 1][c] = 1
    for r in range(rows):
        grid[r][0] = 1
        grid[r][cols - 1] = 1
    # Seattle bridge wrecked vehicle obstacles
    for c in range(3, 27, 4):
        for r in range(2, 6): grid[r][c] = 1
        for r in range(8, 12): grid[r][c+1] = 1
    adjust_grid(grid, rows, cols, 255)
    _, count = check_connectivity(grid, rows, cols)
    print(f"TLOU: {rows}x{cols} -> Walkable: {count}/{rows*cols} ({count/(rows*cols):.1%})")
    return {"name": "TLOU", "rows": rows, "cols": cols, "walkable_count": count, "grid": grid}

def build_dishonored():
    # 26x39: 726 walkable (72%), 288 wall (28%)
    rows, cols = 26, 39
    grid = [[0 for _ in range(cols)] for _ in range(rows)]
    for c in range(cols):
        grid[0][c] = 1
        grid[rows - 1][c] = 1
    for r in range(rows):
        grid[r][0] = 1
        grid[r][cols - 1] = 1
    # Grand palace halls and courtyards
    for r in range(4, 11):
        for c in range(4, 14): grid[r][c] = 1
        for c in range(25, 35): grid[r][c] = 1
    for r in range(15, 22):
        for c in range(4, 14): grid[r][c] = 1
        for c in range(25, 35): grid[r][c] = 1
    adjust_grid(grid, rows, cols, 726)
    _, count = check_connectivity(grid, rows, cols)
    print(f"Dishonored: {rows}x{cols} -> Walkable: {count}/{rows*cols} ({count/(rows*cols):.1%})")
    return {"name": "Dishonored", "rows": rows, "cols": cols, "walkable_count": count, "grid": grid}

if __name__ == "__main__":
    os.makedirs("maps", exist_ok=True)
    maps = [build_test_maze(), build_miami(), build_arkham(), build_tlou(), build_dishonored()]
    for m in maps:
        filename = m["name"].lower().replace(" (maze)", "_maze").replace(" ", "_")
        with open(f"maps/{filename}.json", "w") as f:
            json.dump(m, f, indent=2)
    print("All 5 maps from Table 1 generated successfully!")
