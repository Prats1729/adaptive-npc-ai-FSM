extends Node

# ==============================================================================
# AUTOMATED SIMULATION RUNNER & BENCHMARK COORDINATOR
# ------------------------------------------------------------------------------
# Orchestrates automated experiment episodes between Player Bots and the Enemy FSM.
# Supports live single-round testing or high-speed automated batch benchmarks.
# Logs results via CSVLogger and displays statistical summaries.
# ==============================================================================

signal benchmark_completed(summary: Dictionary)
signal episode_completed(episode_data: Dictionary)

@export var is_benchmark_running: bool = false
@export var episodes_per_batch: int = 10 # 5 Basic FSM vs 5 Adaptive FSM
@export var max_episode_duration: float = 30.0

var arena: Node2D = null
var player: CharacterBody2D = null
var enemy: CharacterBody2D = null
var fsm: Node = null
var player_bot: Node = null
var csv_logger: Node = null

# Active Episode Tracking
var current_episode_id: int = 0
var episode_elapsed_time: float = 0.0
var npc_hits_taken: int = 0
var player_hits_taken: int = 0
var state_transition_count: int = 0
var is_episode_active: bool = false

# Batch Benchmark State
var batch_target_episodes: int = 0
var batch_current_index: int = 0
var batch_bot_mode: int = 1 # Aggressive by default

# Multi-Policy Suite State
var is_suite_running: bool = false
var suite_policies: Array = [1, 2, 3] # Aggressive (1), Defensive (2), Random (3)
var current_suite_policy_idx: int = 0
var episodes_per_policy_target: int = 50

# Aggregate Benchmark Statistics
var stats = {
	"basic": {"trials": 0, "wins": 0, "survival_sum": 0.0},
	"adaptive": {"trials": 0, "wins": 0, "survival_sum": 0.0}
}
var episode_history: Array = []

func _ready() -> void:
	arena = get_parent() as Node2D
	call_deferred("_initialize_references")

func _initialize_references() -> void:
	if not arena:
		return
	player = arena.get_node_or_null("Player")
	enemy = arena.get_node_or_null("EnemyNPC")
	if enemy:
		fsm = enemy.get_node_or_null("EnemyFSM")
		if fsm and not fsm.state_changed.is_connected(_on_fsm_state_changed):
			fsm.state_changed.connect(_on_fsm_state_changed)
	
	if player:
		player_bot = player.get_node_or_null("PlayerBot")
		if not player.player_died.is_connected(_on_player_died):
			player.player_died.connect(_on_player_died)
	
	if enemy and not enemy.enemy_died.is_connected(_on_enemy_died):
		enemy.enemy_died.connect(_on_enemy_died)
	
	csv_logger = get_node_or_null("CSVLogger")
	if not csv_logger:
		csv_logger = load("res://scripts/csv_logger.gd").new()
		add_child(csv_logger)

func _physics_process(delta: float) -> void:
	if not is_episode_active:
		return
	
	episode_elapsed_time += delta
	
	# Timeout safety fallback: Decide winner by remaining health
	if episode_elapsed_time >= max_episode_duration:
		var npc_hp = enemy.current_health if enemy else 0
		var player_hp = player.current_health if player else 0
		var npc_won = (npc_hp > player_hp)
		var player_won = (player_hp > npc_hp)
		var outcome = "Time limit (%.0fs) - NPC HP: %d vs Player HP: %d" % [max_episode_duration, npc_hp, player_hp]
		_conclude_episode(npc_won, player_won, outcome)

func start_single_episode() -> void:
	is_episode_active = true
	episode_elapsed_time = 0.0
	npc_hits_taken = 0
	player_hits_taken = 0
	state_transition_count = 0
	current_episode_id += 1

func start_automated_benchmark(batch_size: int = 10, bot_mode: int = 1) -> void:
	is_suite_running = false
	batch_target_episodes = batch_size
	batch_current_index = 0
	batch_bot_mode = bot_mode
	is_benchmark_running = true
	
	# Accelerate simulation for rapid data collection
	Engine.time_scale = 2.5
	
	# Configure Bot
	if player_bot and player_bot.has_method("set_mode"):
		player_bot.set_mode(bot_mode)
	
	print("\n=======================================================")
	print("[BENCHMARK STARTED] Running %d automated trials..." % batch_size)
	print("=======================================================\n")
	
	_run_next_batch_episode()

func start_full_suite_benchmark(episodes_per_policy: int = 50) -> void:
	is_suite_running = true
	is_benchmark_running = true
	current_suite_policy_idx = 0
	episodes_per_policy_target = episodes_per_policy
	
	# High speed for large batch collection
	Engine.time_scale = 3.5
	
	batch_target_episodes = episodes_per_policy
	batch_current_index = 0
	batch_bot_mode = suite_policies[0]
	
	if player_bot and player_bot.has_method("set_mode"):
		player_bot.set_mode(batch_bot_mode)
	
	print("\n=======================================================")
	print("[FULL SUITE BENCHMARK STARTED] %d games on each of 3 bot policies (Total %d games) at 3.5x speed..." % [
		episodes_per_policy, episodes_per_policy * 3
	])
	print("=======================================================\n")
	
	_run_next_batch_episode()

func _run_next_batch_episode() -> void:
	if batch_current_index >= batch_target_episodes:
		if is_suite_running and current_suite_policy_idx < suite_policies.size() - 1:
			current_suite_policy_idx += 1
			batch_bot_mode = suite_policies[current_suite_policy_idx]
			batch_current_index = 0
			if player_bot and player_bot.has_method("set_mode"):
				player_bot.set_mode(batch_bot_mode)
			print("\n-------------------------------------------------------")
			print(">>> ADVANCING TO NEXT POLICY IN SUITE: %s <<<" % player_bot.get_mode_name())
			print("-------------------------------------------------------\n")
		else:
			is_suite_running = false
			_finish_batch_benchmark()
			return
	
	batch_current_index += 1
	
	# Alternate AI Mode: First half Basic FSM, Second half Adaptive FSM
	var use_adaptive = (batch_current_index > batch_target_episodes / 2)
	if fsm and fsm.has_node("AdaptiveLogic"):
		var adaptive_logic = fsm.get_node("AdaptiveLogic")
		adaptive_logic.is_adaptive_enabled = use_adaptive
	
	# Reset arena entities with slight spawn variation
	if arena and arena.has_method("reset_simulation"):
		arena.reset_simulation(true)
	
	# Update Arena HUD with active bot policy name and suite progress
	if arena and arena.has_method("update_benchmark_hud"):
		var bot_name = player_bot.get_mode_name() if (player_bot and player_bot.has_method("get_mode_name")) else "UNKNOWN"
		var total_suite_episodes = (suite_policies.size() * episodes_per_policy_target) if is_suite_running else batch_target_episodes
		var overall_ep_idx = (current_suite_policy_idx * episodes_per_policy_target + batch_current_index) if is_suite_running else batch_current_index
		arena.update_benchmark_hud(bot_name, batch_current_index, batch_target_episodes, overall_ep_idx, total_suite_episodes)
	
	start_single_episode()

func _on_player_died() -> void:
	if is_episode_active:
		_conclude_episode(true, false, "Player defeated")

func _on_enemy_died() -> void:
	if is_episode_active:
		_conclude_episode(false, true, "Enemy defeated")

func _conclude_episode(npc_won: bool, player_won: bool, outcome_reason: String) -> void:
	is_episode_active = false
	
	var is_adaptive = fsm.is_adaptive() if (fsm and fsm.has_method("is_adaptive")) else false
	var system_type = "Adaptive FSM" if is_adaptive else "Basic FSM"
	var bot_type_str = player_bot.get_mode_name() if (player_bot and player_bot.has_method("get_mode_name")) else "Manual"
	
	var final_retreat = fsm.flee_health_ratio if fsm else 0.30
	var final_detection = fsm.detection_range if fsm else 220.0
	
	var episode_data = {
		"episode_id": current_episode_id,
		"system_type": system_type,
		"player_bot_type": bot_type_str,
		"npc_survival_time": episode_elapsed_time,
		"player_survival_time": episode_elapsed_time,
		"npc_won": npc_won,
		"player_won": player_won,
		"npc_hits": player_hits_taken,
		"player_hits": npc_hits_taken,
		"state_transition_count": state_transition_count,
		"average_response_time": 0.016,
		"final_adaptive_retreat_threshold": final_retreat,
		"final_adaptive_detection_range": final_detection
	}
	
	# Update aggregate statistics
	var stat_key = "adaptive" if is_adaptive else "basic"
	stats[stat_key]["trials"] += 1
	stats[stat_key]["survival_sum"] += episode_elapsed_time
	if npc_won:
		stats[stat_key]["wins"] += 1
	
	episode_history.append(episode_data)
	
	# Write to CSV
	if csv_logger and csv_logger.has_method("log_episode"):
		csv_logger.log_episode(episode_data)
	
	episode_completed.emit(episode_data)
	print("[Episode #%d Result] %s | NPC Won: %s | Survival: %.1fs | %s" % [
		current_episode_id, system_type, str(npc_won), episode_elapsed_time, outcome_reason
	])
	
	if is_benchmark_running:
		get_tree().create_timer(0.3).timeout.connect(_run_next_batch_episode)

func _finish_batch_benchmark() -> void:
	is_benchmark_running = false
	Engine.time_scale = 1.0 # Restore normal game speed
	
	var basic_trials = max(1, stats["basic"]["trials"])
	var adap_trials = max(1, stats["adaptive"]["trials"])
	
	var basic_win_rate = (float(stats["basic"]["wins"]) / float(basic_trials)) * 100.0
	var adap_win_rate = (float(stats["adaptive"]["wins"]) / float(adap_trials)) * 100.0
	
	var basic_avg_surv = stats["basic"]["survival_sum"] / float(basic_trials)
	var adap_avg_surv = stats["adaptive"]["survival_sum"] / float(adap_trials)
	
	var summary = {
		"basic_win_rate": basic_win_rate,
		"adaptive_win_rate": adap_win_rate,
		"basic_avg_survival": basic_avg_surv,
		"adaptive_avg_survival": adap_avg_surv,
		"total_episodes": current_episode_id,
		"basic_trials": basic_trials,
		"adaptive_trials": adap_trials,
		"basic_wins": stats["basic"]["wins"],
		"adaptive_wins": stats["adaptive"]["wins"]
	}
	
	print("\n=======================================================")
	print("               BENCHMARK RESULTS SUMMARY               ")
	print("-------------------------------------------------------")
	print("Basic FSM    -> Win Rate: %.1f%%  |  Avg Survival: %.2fs" % [basic_win_rate, basic_avg_surv])
	print("Adaptive FSM -> Win Rate: %.1f%%  |  Avg Survival: %.2fs" % [adap_win_rate, adap_avg_surv])
	print("=======================================================\n")
	
	_export_dashboard_data(summary)
	open_evaluation_dashboard()
	
	benchmark_completed.emit(summary)

func open_evaluation_dashboard() -> void:
	var dashboard_path: String = ProjectSettings.globalize_path("res://docs/dashboard.html")
	print("[SimulationRunner] Automatically launching Evaluation Dashboard: %s" % dashboard_path)
	OS.shell_open(dashboard_path)

func _export_dashboard_data(summary: Dictionary) -> void:
	var data_payload = {
		"summary": summary,
		"episodes": episode_history,
		"source": "Godot Simulation Runner"
	}
	var js_content = "// Auto-generated simulation data from Godot SimulationRunner\n"
	js_content += "window.SIMULATION_DATA = " + JSON.stringify(data_payload) + ";\n"
	
	var f = FileAccess.open("res://data/simulation_data.js", FileAccess.WRITE)
	if f:
		f.store_string(js_content)
		f.close()
		print("[SimulationRunner] Saved live telemetry dataset to res://data/simulation_data.js")

func _on_fsm_state_changed(_old_s: String, _new_s: String, _reason: String) -> void:
	state_transition_count += 1
