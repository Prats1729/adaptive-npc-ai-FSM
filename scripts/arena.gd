extends Node2D

# ==============================================================================
# ARENA CONTROLLER & SIMULATION MANAGER
# ------------------------------------------------------------------------------
# Minimalistic Arena coordinator displaying only essential Player & NPC vitals.
# Handles reset (R), test damage shortcuts (1, 2), and FSM mode toggle (T).
# ==============================================================================

@onready var player: CharacterBody2D = $Player
@onready var enemy: CharacterBody2D = $EnemyNPC
@onready var fsm: Node = $EnemyNPC/EnemyFSM if has_node("EnemyNPC/EnemyFSM") else null

# Minimal Vitals HUD References
@onready var player_hp_bar: ProgressBar = $HUD/MarginContainer/HBoxContainer/PlayerCard/VBox/PlayerHPBar if has_node("HUD/MarginContainer/HBoxContainer/PlayerCard/VBox/PlayerHPBar") else null
@onready var player_hp_text: Label = $HUD/MarginContainer/HBoxContainer/PlayerCard/VBox/PlayerHPLabel if has_node("HUD/MarginContainer/HBoxContainer/PlayerCard/VBox/PlayerHPLabel") else null
@onready var enemy_hp_bar: ProgressBar = $HUD/MarginContainer/HBoxContainer/EnemyCard/VBox/EnemyHPBar if has_node("HUD/MarginContainer/HBoxContainer/EnemyCard/VBox/EnemyHPBar") else null
@onready var enemy_hp_text: Label = $HUD/MarginContainer/HBoxContainer/EnemyCard/VBox/EnemyHPLabel if has_node("HUD/MarginContainer/HBoxContainer/EnemyCard/VBox/EnemyHPLabel") else null

# Telemetry & Explainability HUD References
@onready var mode_label: Label = $HUD/MarginContainer/HBoxContainer/TelemetryCard/VBox/TopRow/ModeLabel if has_node("HUD/MarginContainer/HBoxContainer/TelemetryCard/VBox/TopRow/ModeLabel") else null
@onready var state_label: Label = $HUD/MarginContainer/HBoxContainer/TelemetryCard/VBox/TopRow/StateLabel if has_node("HUD/MarginContainer/HBoxContainer/TelemetryCard/VBox/TopRow/StateLabel") else null
@onready var metrics_label: Label = $HUD/MarginContainer/HBoxContainer/TelemetryCard/VBox/MetricsLabel if has_node("HUD/MarginContainer/HBoxContainer/TelemetryCard/VBox/MetricsLabel") else null
@onready var reason_label: Label = $HUD/MarginContainer/HBoxContainer/TelemetryCard/VBox/ReasonLabel if has_node("HUD/MarginContainer/HBoxContainer/TelemetryCard/VBox/ReasonLabel") else null
@onready var player_mode_label: Label = $HUD/MarginContainer/HBoxContainer/PlayerCard/VBox/PlayerModeLabel if has_node("HUD/MarginContainer/HBoxContainer/PlayerCard/VBox/PlayerModeLabel") else null

# Simulation & Bot References
@onready var sim_runner: Node = $SimulationRunner if has_node("SimulationRunner") else null
@onready var player_bot: Node = $Player/PlayerBot if has_node("Player/PlayerBot") else null

var player_start_pos: Vector2 = Vector2(260, 330)
var enemy_start_pos: Vector2 = Vector2(890, 330)

func _ready() -> void:
	if player:
		player_start_pos = player.global_position
		player.health_changed.connect(_on_player_health_changed)
	
	if enemy:
		enemy_start_pos = enemy.global_position
		enemy.health_changed.connect(_on_enemy_health_changed)
	
	if fsm:
		fsm.state_changed.connect(_on_fsm_state_changed)
		fsm.telemetry_updated.connect(_on_fsm_telemetry_updated)
	
	if sim_runner:
		sim_runner.benchmark_completed.connect(_on_benchmark_completed)
	
	_update_vitals_ui()
	_update_player_bot_ui()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	
	# Press R: Reset Entire Simulation
	if event.keycode == KEY_R:
		reset_simulation()
	
	# Press T: Toggle between Basic FSM and Adaptive FSM
	elif event.keycode == KEY_T:
		if fsm and fsm.has_method("toggle_adaptive"):
			var is_adap = fsm.toggle_adaptive()
			var mode_str = "ADAPTIVE FSM" if is_adap else "BASIC FSM"
			print("[AI Mode Switch] Now running in: " + mode_str)
			_update_vitals_ui()
	
	# Press M: Cycle Player Bot Mode (Manual -> Aggressive -> Defensive -> Random)
	elif event.keycode == KEY_M:
		if player_bot and player_bot.has_method("cycle_mode"):
			player_bot.cycle_mode()
			_update_player_bot_ui()
	
	# Press B: Run Automated 10-Round Benchmark
	elif event.keycode == KEY_B:
		if sim_runner and sim_runner.has_method("start_automated_benchmark"):
			if sim_runner.is_benchmark_running:
				print("[Benchmark] Stopping active benchmark...")
				sim_runner.is_benchmark_running = false
				sim_runner.is_suite_running = false
				Engine.time_scale = 1.0
			else:
				var active_mode = player_bot.current_mode if (player_bot and player_bot.current_mode != 0) else 1
				sim_runner.start_automated_benchmark(10, active_mode)
				_update_player_bot_ui()
	
	# Press N: Run Full Multi-Policy Benchmark Suite (50 games on each of the 3 bots)
	elif event.keycode == KEY_N:
		if sim_runner and sim_runner.has_method("start_full_suite_benchmark"):
			if sim_runner.is_benchmark_running:
				print("[Benchmark Suite] Stopping active suite...")
				sim_runner.is_benchmark_running = false
				sim_runner.is_suite_running = false
				Engine.time_scale = 1.0
			else:
				sim_runner.start_full_suite_benchmark(50)
				_update_player_bot_ui()
	
	# Press O: Open Evaluation Dashboard in Web Browser
	elif event.keycode == KEY_O:
		if sim_runner and sim_runner.has_method("open_evaluation_dashboard"):
			sim_runner.open_evaluation_dashboard()
		else:
			var dashboard_path = ProjectSettings.globalize_path("res://docs/dashboard.html")
			OS.shell_open(dashboard_path)
	
	# Press 1: Viva Shortcut - Deal 12 Damage to Enemy (fine increment)
	elif event.keycode == KEY_1:
		if enemy and is_instance_valid(enemy):
			enemy.take_damage(12)
	
	# Press 2: Viva Shortcut - Deal 15 Damage to Player
	elif event.keycode == KEY_2:
		if player and is_instance_valid(player):
			player.take_damage(15)

func reset_simulation(randomize_spawns: bool = false) -> void:
	var p_pos = player_start_pos
	var e_pos = enemy_start_pos
	if randomize_spawns:
		p_pos += Vector2(randf_range(-35, 35), randf_range(-35, 35))
		e_pos += Vector2(randf_range(-35, 35), randf_range(-35, 35))
	if player:
		player.reset_player(p_pos)
	if enemy:
		enemy.reset_enemy(e_pos)
	if fsm and fsm.has_method("reset_fsm"):
		fsm.reset_fsm()
	
	_update_vitals_ui()
	print("[Simulation] Reset to initial state.")

func _on_fsm_state_changed(old_state: String, new_state: String, reason: String) -> void:
	print("[FSM Decision] %s -> %s | %s" % [old_state, new_state, reason])
	if reason_label:
		reason_label.text = "Reason: %s" % reason

func _on_fsm_telemetry_updated(data: Dictionary) -> void:
	if mode_label:
		var is_adap = data.get("is_adaptive", false)
		mode_label.text = "[ ADAPTIVE FSM ]" if is_adap else "[ BASIC FSM ]"
		mode_label.modulate = Color(0.2, 0.75, 1.0) if is_adap else Color(1.0, 0.8, 0.3)
	
	if state_label:
		state_label.text = "STATE: %s" % data.get("state_name", "UNKNOWN")
		state_label.modulate = data.get("state_color", Color.WHITE)
	
	var adaptive_logic = fsm.get_node_or_null("AdaptiveLogic") if fsm else null
	var agg_score = adaptive_logic.player_aggression_score if adaptive_logic else 0.0
	var agg_tier = adaptive_logic.get_aggression_tier() if adaptive_logic else "LOW"
	var flee_thresh = (fsm.flee_health_ratio * 100.0) if fsm else 30.0
	var det_range = round(data.get("detection_range", 220.0))
	
	if metrics_label:
		metrics_label.text = "Aggression: %.2f (%s)  |  Flee HP: %.0f%%  |  Range: %dpx" % [
			agg_score, agg_tier, flee_thresh, det_range
		]
	
	if reason_label and data.has("reason") and data["reason"] != "":
		reason_label.text = "Reason: %s" % data["reason"]

func _on_player_health_changed(current_hp: int, max_hp: int) -> void:
	if player_hp_bar:
		player_hp_bar.max_value = max_hp
		player_hp_bar.value = current_hp
	if player_hp_text:
		player_hp_text.text = "Player HP: %d / %d" % [current_hp, max_hp]

func _on_enemy_health_changed(current_hp: int, max_hp: int) -> void:
	if enemy_hp_bar:
		enemy_hp_bar.max_value = max_hp
		enemy_hp_bar.value = current_hp
	if enemy_hp_text:
		var mode_str = "ADAPTIVE" if (fsm and fsm.is_adaptive()) else "BASIC"
		enemy_hp_text.text = "NPC HP: %d / %d  [%s]" % [current_hp, max_hp, mode_str]

func _update_vitals_ui() -> void:
	if player:
		_on_player_health_changed(player.current_health, player.max_health)
	if enemy:
		_on_enemy_health_changed(enemy.current_health, enemy.max_health)

func _update_player_bot_ui() -> void:
	if player_mode_label and player_bot and player_bot.has_method("get_mode_name"):
		var mode_name = player_bot.get_mode_name()
		player_mode_label.text = "Mode: %s [M to cycle]" % mode_name
		player_mode_label.modulate = Color(0.4, 0.9, 0.5) if player_bot.current_mode == 0 else Color(1.0, 0.75, 0.3)

func _on_benchmark_completed(summary: Dictionary) -> void:
	if reason_label:
		reason_label.text = "BENCHMARK COMPLETE: Basic Win: %.0f%% (%.1fs) | Adaptive Win: %.0f%% (%.1fs) [Saved to CSV!]" % [
			summary.get("basic_win_rate", 0.0),
			summary.get("basic_avg_survival", 0.0),
			summary.get("adaptive_win_rate", 0.0),
			summary.get("adaptive_avg_survival", 0.0)
		]
		reason_label.modulate = Color(0.35, 1.0, 0.6)
