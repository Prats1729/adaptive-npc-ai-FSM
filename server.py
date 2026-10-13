import os
import sys
import json
import math
import random
import statistics
import webbrowser
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn
import urllib.parse

# Ensure scripts directory is in python path
sys.path.append(os.path.abspath("scripts"))

from stealth.grid_environment import GridEnvironment
from stealth.experiment_runner import StealthExperimentRunner

class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True

class StealthAPIHandler(BaseHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With, Accept')
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.send_header('Content-Length', '0')
        self.end_headers()

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        query = urllib.parse.parse_qs(parsed.query)

        if path == "/" or path == "/index.html":
            self._serve_file("ui/index.html", "text/html")
        elif path.startswith("/ui/"):
            file_rel = path.lstrip("/")
            mime = "text/html" if file_rel.endswith(".html") else "text/css" if file_rel.endswith(".css") else "application/javascript" if file_rel.endswith(".js") else "application/octet-stream"
            self._serve_file(file_rel, mime)
        elif path == "/api/maps":
            self._handle_get_maps()
        elif path.startswith("/api/map/"):
            map_name = path.replace("/api/map/", "").strip()
            self._handle_get_map(map_name)
        elif path == "/api/benchmark-data":
            self._handle_get_benchmark_data(query)
        else:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"404 Not Found")

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length).decode('utf-8')
        try:
            payload = json.loads(body) if body else {}
        except Exception:
            payload = {}

        if path == "/api/run-visual-match":
            self._handle_run_visual_match(payload)
        elif path == "/api/run-benchmark":
            self._handle_run_benchmark(payload)
        else:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"404 Not Found")

    def _serve_file(self, file_path, content_type):
        if not os.path.exists(file_path):
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"File not found")
            return
        with open(file_path, "rb") as f:
            data = f.read()
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _send_json(self, data_dict, status=200):
        body = json.dumps(data_dict).encode('utf-8')
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _handle_get_maps(self):
        maps_dir = "maps"
        maps_list = []
        if os.path.exists(maps_dir):
            for f in os.listdir(maps_dir):
                if f.endswith(".json"):
                    fp = os.path.join(maps_dir, f)
                    try:
                        with open(fp, "r") as mf:
                            mdata = json.load(mf)
                            maps_list.append({
                                "id": f.replace(".json", ""),
                                "name": mdata.get("name", f),
                                "rows": mdata.get("rows", 0),
                                "cols": mdata.get("cols", 0),
                                "walkable": sum(row.count(0) for row in mdata.get("grid", []))
                            })
                    except Exception:
                        pass
        self._send_json({"maps": maps_list})

    def _handle_get_map(self, map_name):
        map_file = f"maps/{map_name}.json"
        if not os.path.exists(map_file):
            self._send_json({"error": "Map not found"}, 404)
            return
        with open(map_file, "r") as f:
            mdata = json.load(f)
        self._send_json(mdata)

    def _handle_get_benchmark_data(self, query):
        map_name = query.get("map", ["miami"])[0]
        csv_path = f"data/benchmark_{map_name}.csv"
        results = []
        if os.path.exists(csv_path):
            import csv
            with open(csv_path, "r") as f:
                reader = csv.DictReader(f)
                for r in reader:
                    results.append(r)
        self._send_json({"map": map_name, "trials": results})

    def _handle_run_visual_match(self, payload):
        map_name = payload.get("map", "miami")
        guard_type = payload.get("guard", "PI-PF")
        player_mode = payload.get("player", "MaxMin")
        seed = int(payload.get("seed", random.randint(100, 99999)))

        map_path = f"maps/{map_name}.json"
        if not os.path.exists(map_path):
            self._send_json({"error": f"Map {map_name} not found"}, 404)
            return

        runner = StealthExperimentRunner(map_path)
        env = runner.env
        guard_positions, player_pos = env.initialize_positions(num_guards=3, random_seed=seed)
        guards = [runner._create_guard(guard_type, seed + i * 17) for i in range(3)]
        player = runner._create_player(player_mode)

        player_hp = 3
        max_duration = 60
        guard_view_range = 6.4
        attack_range = 1.5

        history = []
        captured = False
        capture_time = float(max_duration)

        for t in range(1, max_duration + 1):
            # Compute line of sight for each guard
            los = [env.has_line_of_sight(g, player_pos, guard_view_range) for g in guard_positions]
            
            # Step record
            step = {
                "t": t,
                "guards": [list(g) for g in guard_positions],
                "player": list(player_pos),
                "los": los,
                "player_hp": player_hp,
                "dist_closest": min(env.get_distance(g, player_pos) for g in guard_positions)
            }
            history.append(step)

            # Move guards
            new_guards = []
            for i, g in enumerate(guards):
                next_pos = g.select_action(guard_positions[i], player_pos, guard_view_range, all_guards=guard_positions)
                new_guards.append(next_pos)
            guard_positions = new_guards

            # Move player
            player_pos = player.select_action(player_pos, guard_positions)
            if player.should_take_speed_bonus_step():
                player_pos = player.select_action(player_pos, guard_positions)

            # Damage check
            in_range = sum(
                1 for g in guard_positions 
                if math.hypot(g[0] - player_pos[0], g[1] - player_pos[1]) <= attack_range
            )
            if in_range > 0:
                player_hp -= in_range
                if player_hp <= 0:
                    captured = True
                    capture_time = float(t)
                    # Append final capture frame
                    history.append({
                        "t": t,
                        "guards": [list(g) for g in guard_positions],
                        "player": list(player_pos),
                        "los": [True, True, True],
                        "player_hp": 0,
                        "dist_closest": 0
                    })
                    break

        self._send_json({
            "map": map_name,
            "guard": guard_type,
            "player": player_mode,
            "seed": seed,
            "captured": captured,
            "capture_time": capture_time,
            "total_steps": len(history),
            "trace": history
        })

    def _handle_run_benchmark(self, payload):
        map_name = payload.get("map", "miami")
        models = payload.get("models", ["Cheat", "CPF", "Staleness", "FSM", "RandomWalk", "PI-PF", "RL-Q", "APF-MCTS"])
        trials = int(payload.get("trials", 20))
        player_mode = payload.get("player", "MaxMin")

        map_path = f"maps/{map_name}.json"
        if not os.path.exists(map_path):
            self._send_json({"error": f"Map {map_name} not found"}, 404)
            return

        online_learning = bool(payload.get("online_learning", False))
        runner = StealthExperimentRunner(map_path, online_learning=online_learning)
        summary = runner.run_benchmark_suite(models, num_trials=trials, player_mode=player_mode)

        self._send_json({
            "map": map_name,
            "player": player_mode,
            "trials": trials,
            "summary": summary
        })

def start_server(port=8080, open_browser=False):
    server_address = ('', port)
    try:
        httpd = ThreadedHTTPServer(server_address, StealthAPIHandler)
        print("=" * 80)
        print(f"[*] STEALTH AI BENCHMARK STUDIO SERVER RUNNING AT: http://localhost:{port}")
        print("    Press Ctrl+C to stop the server.")
        print("=" * 80)
        if open_browser:
            webbrowser.open(f"http://localhost:{port}")
        httpd.serve_forever()
    except OSError as e:
        if port < 8090:
            print(f"[!] Port {port} busy, attempting next port {port+1}...")
            start_server(port + 1, open_browser)
        else:
            raise e

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Stealth AI Benchmark Web Studio Server")
    parser.add_argument("--port", type=int, default=8080, help="Port to run web server on")
    parser.add_argument("--open", action="store_true", help="Automatically open browser")
    args = parser.parse_args()
    start_server(args.port, open_browser=args.open)
