extends Node2D

# ==============================================================================
# ARENA CONTROLLER & SIMULATION MANAGER
# ------------------------------------------------------------------------------
# Minimalistic Arena coordinator displaying only essential Player & NPC vitals.
# Handles reset (R) and test damage shortcuts (1, 2).
# ==============================================================================

@onready var player: CharacterBody2D = $Player
@onready var enemy: CharacterBody2D = $EnemyNPC
@onready var fsm: Node = $EnemyNPC/EnemyFSM if has_node("EnemyNPC/EnemyFSM") else null

# Minimal Vitals HUD References
@onready var player_hp_bar: ProgressBar = $HUD/MarginContainer/HBoxContainer/PlayerCard/VBox/PlayerHPBar if has_node("HUD/MarginContainer/HBoxContainer/PlayerCard/VBox/PlayerHPBar") else null
@onready var player_hp_text: Label = $HUD/MarginContainer/HBoxContainer/PlayerCard/VBox/PlayerHPLabel if has_node("HUD/MarginContainer/HBoxContainer/PlayerCard/VBox/PlayerHPLabel") else null
@onready var enemy_hp_bar: ProgressBar = $HUD/MarginContainer/HBoxContainer/EnemyCard/VBox/EnemyHPBar if has_node("HUD/MarginContainer/HBoxContainer/EnemyCard/VBox/EnemyHPBar") else null
@onready var enemy_hp_text: Label = $HUD/MarginContainer/HBoxContainer/EnemyCard/VBox/EnemyHPLabel if has_node("HUD/MarginContainer/HBoxContainer/EnemyCard/VBox/EnemyHPLabel") else null

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
	
	_update_vitals_ui()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	
	# Press R: Reset Entire Simulation
	if event.keycode == KEY_R:
		reset_simulation()
	
	# Press 1: Viva Shortcut - Deal 25 Damage to Enemy
	elif event.keycode == KEY_1:
		if enemy and is_instance_valid(enemy):
			enemy.take_damage(25)
	
	# Press 2: Viva Shortcut - Deal 20 Damage to Player
	elif event.keycode == KEY_2:
		if player and is_instance_valid(player):
			player.take_damage(20)

func reset_simulation() -> void:
	if player:
		player.reset_player(player_start_pos)
	if enemy:
		enemy.reset_enemy(enemy_start_pos)
	if fsm and fsm.has_method("reset_fsm"):
		fsm.reset_fsm()
	
	_update_vitals_ui()
	print("[Simulation] Reset to initial state.")

func _on_fsm_state_changed(old_state: String, new_state: String, reason: String) -> void:
	print("[FSM Decision] %s -> %s | %s" % [old_state, new_state, reason])

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
