extends Node2D

# ==============================================================================
# ARENA CONTROLLER & SIMULATION MANAGER
# ------------------------------------------------------------------------------
# Coordinates entities (Player, EnemyNPC), bridges FSM events to the on-screen
# HUD, manages explainable event logging, and provides viva testing shortcuts.
# ==============================================================================

@onready var player: CharacterBody2D = $Player
@onready var enemy: CharacterBody2D = $EnemyNPC
@onready var fsm: Node = $EnemyNPC/EnemyFSM if has_node("EnemyNPC/EnemyFSM") else null
@onready var arena_map: Node2D = $ArenaMap if has_node("ArenaMap") else null

# HUD UI References (CanvasLayer)
@onready var state_badge: Label = $HUD/MarginContainer/VBoxContainer/TopSection/AIStatusPanel/VBox/StateBadge if has_node("HUD/MarginContainer/VBoxContainer/TopSection/AIStatusPanel/VBox/StateBadge") else null
@onready var reason_label: Label = $HUD/MarginContainer/VBoxContainer/TopSection/AIStatusPanel/VBox/ReasonLabel if has_node("HUD/MarginContainer/VBoxContainer/TopSection/AIStatusPanel/VBox/ReasonLabel") else null
@onready var distance_label: Label = $HUD/MarginContainer/VBoxContainer/TopSection/AIStatusPanel/VBox/Metrics/DistanceVal if has_node("HUD/MarginContainer/VBoxContainer/TopSection/AIStatusPanel/VBox/Metrics/DistanceVal") else null
@onready var cooldown_label: Label = $HUD/MarginContainer/VBoxContainer/TopSection/AIStatusPanel/VBox/Metrics/CooldownVal if has_node("HUD/MarginContainer/VBoxContainer/TopSection/AIStatusPanel/VBox/Metrics/CooldownVal") else null

@onready var player_hp_bar: ProgressBar = $HUD/MarginContainer/VBoxContainer/TopSection/VitalsPanel/VBox/PlayerHPBar if has_node("HUD/MarginContainer/VBoxContainer/TopSection/VitalsPanel/VBox/PlayerHPBar") else null
@onready var player_hp_text: Label = $HUD/MarginContainer/VBoxContainer/TopSection/VitalsPanel/VBox/PlayerHPLabel if has_node("HUD/MarginContainer/VBoxContainer/TopSection/VitalsPanel/VBox/PlayerHPLabel") else null
@onready var enemy_hp_bar: ProgressBar = $HUD/MarginContainer/VBoxContainer/TopSection/VitalsPanel/VBox/EnemyHPBar if has_node("HUD/MarginContainer/VBoxContainer/TopSection/VitalsPanel/VBox/EnemyHPBar") else null
@onready var enemy_hp_text: Label = $HUD/MarginContainer/VBoxContainer/TopSection/VitalsPanel/VBox/EnemyHPLabel if has_node("HUD/MarginContainer/VBoxContainer/TopSection/VitalsPanel/VBox/EnemyHPLabel") else null

@onready var log_text_edit: RichTextLabel = $HUD/MarginContainer/VBoxContainer/BottomSection/LogPanel/LogContent if has_node("HUD/MarginContainer/VBoxContainer/BottomSection/LogPanel/LogContent") else null

var player_start_pos: Vector2 = Vector2(260, 330)
var enemy_start_pos: Vector2 = Vector2(890, 330)
var simulation_time: float = 0.0
var log_history: Array[String] = []

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
	
	_add_log_entry("Arena map loaded. NPC in default [IDLE] state.")
	_update_vitals_ui()

func _process(delta: float) -> void:
	simulation_time += delta

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	
	# Press R: Reset Entire Simulation
	if event.keycode == KEY_R:
		reset_simulation()
	
	# Press 1: Viva Shortcut - Deal 25 Damage to Enemy (Forces FLEE state demo)
	elif event.keycode == KEY_1:
		if enemy and is_instance_valid(enemy):
			_add_log_entry("[Viva Demo] Applied 25 damage to NPC via test trigger.")
			enemy.take_damage(25)
	
	# Press 2: Viva Shortcut - Deal 20 Damage to Player
	elif event.keycode == KEY_2:
		if player and is_instance_valid(player):
			_add_log_entry("[Viva Demo] Applied 20 damage to Player via test trigger.")
			player.take_damage(20)
	
	# Press Z: Toggle Perception Range Overlay
	elif event.keycode == KEY_Z:
		if arena_map and "show_perception_zones" in arena_map:
			arena_map.show_perception_zones = not arena_map.show_perception_zones
			var status = "ON" if arena_map.show_perception_zones else "OFF"
			_add_log_entry("[Display] Sensory perception zones toggled " + status)

func reset_simulation() -> void:
	simulation_time = 0.0
	_add_log_entry("--- Simulation Reset ---")
	
	if player:
		player.reset_player(player_start_pos)
	if enemy:
		enemy.reset_enemy(enemy_start_pos)
	if fsm and fsm.has_method("reset_fsm"):
		fsm.reset_fsm()
	
	_update_vitals_ui()

func _on_fsm_state_changed(old_state: String, new_state: String, reason: String) -> void:
	var time_stamp = _format_time(simulation_time)
	var log_msg = "[b][%s][/b] [color=#ffdd55]%s[/color] -> [color=#55ffff]%s[/color] | %s" % [
		time_stamp, old_state, new_state, reason
	]
	_add_log_entry(log_msg)
	
	if state_badge:
		state_badge.text = "NPC STATE: " + new_state
		if fsm and fsm.has_method("get_state_color"):
			state_badge.modulate = fsm.get_state_color(fsm.current_state)
	
	if reason_label:
		reason_label.text = "Decision Reason: " + reason

func _on_fsm_telemetry_updated(telemetry: Dictionary) -> void:
	if distance_label and telemetry.has("distance_to_player"):
		var dist = round(telemetry["distance_to_player"])
		var det = round(telemetry["detection_range"])
		var atk = round(telemetry["attack_range"])
		distance_label.text = "%d px (Detect: %d px | Atk: %d px)" % [dist, det, atk]
	
	if cooldown_label and telemetry.has("attack_cooldown"):
		var cd = telemetry["attack_cooldown"]
		if cd > 0.0:
			cooldown_label.text = "%.1f s" % cd
			cooldown_label.modulate = Color(1.0, 0.4, 0.4)
		else:
			cooldown_label.text = "Ready"
			cooldown_label.modulate = Color(0.4, 1.0, 0.4)

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
		enemy_hp_text.text = "NPC HP: %d / %d" % [current_hp, max_hp]

func _update_vitals_ui() -> void:
	if player:
		_on_player_health_changed(player.current_health, player.max_health)
	if enemy:
		_on_enemy_health_changed(enemy.current_health, enemy.max_health)

func _add_log_entry(message: String) -> void:
	log_history.append(message)
	if log_history.size() > 8:
		log_history.pop_front()
	
	if log_text_edit:
		log_text_edit.clear()
		for entry in log_history:
			log_text_edit.append_text(entry + "\n")

func _format_time(seconds: float) -> String:
	var mins = int(seconds) / 60
	var secs = int(seconds) % 60
	return "%02d:%02d" % [mins, secs]
