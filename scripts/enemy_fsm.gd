extends Node

# ==============================================================================
# ENEMY FINITE STATE MACHINE (FSM)
# ------------------------------------------------------------------------------
# Core AI Decision-Making Component.
# Evaluates sensory perception (player distance, entity health) each physics tick
# and executes transparent, rule-based state transitions with clear explainability.
# Supports both Basic FSM and Adaptive FSM parameter modulation.
# ==============================================================================

signal state_changed(old_state_name: String, new_state_name: String, reason: String)
signal telemetry_updated(telemetry_data: Dictionary)
signal mode_toggled(is_adaptive: bool)

enum State {
	IDLE,
	CHASE,
	ATTACK,
	FLEE,
	DEAD
}

@export_group("FSM Decision Thresholds")
@export var detection_range: float = 220.0
@export var attack_range: float = 65.0
@export var safe_distance: float = 300.0
@export var flee_health_ratio: float = 0.30 # 30% max health
@export var attack_damage: int = 12
@export var attack_cooldown_time: float = 1.0

var current_state: State = State.IDLE
var enemy: CharacterBody2D = null
var attack_timer: float = 0.0
var last_reason: String = "Simulation Initialized"
var is_active: bool = true

@onready var adaptive_logic: Node = $AdaptiveLogic if has_node("AdaptiveLogic") else null

# Colors representing each state for visual feedback
const STATE_COLORS = {
	State.IDLE: Color(0.4, 0.9, 0.5),     # Emerald Green (Calm/Neutral)
	State.CHASE: Color(1.0, 0.82, 0.2),   # Golden Amber (Alert/Pursuing)
	State.ATTACK: Color(1.0, 0.25, 0.25), # Crimson Red (Aggressive/Engaging)
	State.FLEE: Color(0.2, 0.75, 1.0),    # Dodger Blue (Evasive/Retreating)
	State.DEAD: Color(0.45, 0.45, 0.45)   # Charcoal Gray (Defeated)
}

func _ready() -> void:
	enemy = get_parent() as CharacterBody2D
	current_state = State.IDLE
	last_reason = "System started in default IDLE state."
	
	if enemy:
		enemy.update_visual_state(get_state_name(current_state), get_state_color(current_state), last_reason)

func _physics_process(delta: float) -> void:
	if not is_active or not enemy:
		return
	
	if not enemy.player or not is_instance_valid(enemy.player):
		enemy.find_player_reference()
		if not enemy.player:
			return

	# Handle attack cooldown timer
	if attack_timer > 0.0:
		attack_timer -= delta

	# Check for NPC death condition
	if enemy.current_health <= 0:
		if current_state != State.DEAD:
			change_state(State.DEAD, "Enemy health dropped to 0.")
		return

	# Sensory Perception
	var player_pos: Vector2 = enemy.player.global_position
	var distance_to_player: float = enemy.global_position.distance_to(player_pos)
	var health_ratio: float = float(enemy.current_health) / float(enemy.max_health)
	
	# Send live telemetry to HUD / Event Log
	emit_telemetry(distance_to_player, health_ratio)

	# Global Transition Rule: Flee when health drops below current flee threshold
	if health_ratio <= flee_health_ratio and current_state != State.FLEE and current_state != State.DEAD:
		var mode_str = "Adaptive" if (adaptive_logic and adaptive_logic.is_adaptive_enabled) else "Static"
		change_state(
			State.FLEE, 
			"Low Health (HP: %d/%d - %.0f%% <= %.0f%% [%s Threshold])" % [
				enemy.current_health, 
				enemy.max_health, 
				health_ratio * 100.0, 
				flee_health_ratio * 100.0,
				mode_str
			]
		)
		return

	# State-specific Execution and Transition Rules
	match current_state:
		State.IDLE:
			_process_idle_state(distance_to_player)
			
		State.CHASE:
			_process_chase_state(player_pos, distance_to_player)
			
		State.ATTACK:
			_process_attack_state(distance_to_player)
			
		State.FLEE:
			_process_flee_state(player_pos, distance_to_player, health_ratio)
			
		State.DEAD:
			enemy.stop_moving()

# --- STATE ACTIONS & TRANSITION LOGIC ---

func _process_idle_state(distance: float) -> void:
	if enemy.player:
		enemy.stop_moving(enemy.player.global_position)
	else:
		enemy.stop_moving()
	
	if distance <= detection_range:
		change_state(
			State.CHASE,
			"Player entered detection range (Distance: %d px <= %d px)" % [round(distance), round(detection_range)]
		)

func _process_chase_state(target_pos: Vector2, distance: float) -> void:
	enemy.move_towards_point(target_pos, enemy.base_speed)
	
	if distance <= attack_range:
		change_state(
			State.ATTACK,
			"Player entered attack range (Distance: %d px <= %d px)" % [round(distance), round(attack_range)]
		)
	elif distance > detection_range * 1.2:
		change_state(
			State.IDLE,
			"Player escaped detection range (Distance: %d px > %d px)" % [round(distance), round(detection_range * 1.2)]
		)

func _process_attack_state(distance: float) -> void:
	if enemy.player:
		enemy.stop_moving(enemy.player.global_position)
	else:
		enemy.stop_moving()
	
	if attack_timer <= 0.0:
		attack_timer = attack_cooldown_time
		if enemy.has_method("trigger_attack_visual"):
			enemy.trigger_attack_visual()
		if enemy.player and enemy.player.has_method("take_damage"):
			enemy.player.take_damage(attack_damage)
	
	if distance > attack_range * 1.25:
		change_state(
			State.CHASE,
			"Player moved outside attack range (Distance: %d px > %d px)" % [round(distance), round(attack_range * 1.25)]
		)

func _process_flee_state(player_pos: Vector2, distance: float, _health_ratio: float) -> void:
	var flee_direction = (enemy.global_position - player_pos).normalized()
	var flee_target = enemy.global_position + flee_direction * 150.0
	enemy.move_towards_point(flee_target, enemy.flee_speed)
	
	if distance >= safe_distance:
		change_state(
			State.IDLE,
			"Established safe distance from player (Distance: %d px >= %d px)" % [round(distance), round(safe_distance)]
		)

# --- EXPLAINABILITY & STATE SWITCHING ---

func change_state(new_state: State, reason: String) -> void:
	if current_state == new_state:
		return
	
	var old_state_name = get_state_name(current_state)
	var new_state_name = get_state_name(new_state)
	last_reason = reason
	
	print("[FSM] %s -> %s | Reason: %s" % [old_state_name, new_state_name, reason])
	
	current_state = new_state
	
	if enemy:
		enemy.update_visual_state(new_state_name, get_state_color(new_state), reason)
	
	state_changed.emit(old_state_name, new_state_name, reason)

func get_state_name(state: State) -> String:
	match state:
		State.IDLE: return "IDLE"
		State.CHASE: return "CHASE"
		State.ATTACK: return "ATTACK"
		State.FLEE: return "FLEE"
		State.DEAD: return "DEAD"
		_: return "UNKNOWN"

func get_state_color(state: State) -> Color:
	if STATE_COLORS.has(state):
		return STATE_COLORS[state]
	return Color.WHITE

func emit_telemetry(distance: float, health_ratio: float) -> void:
	var data = {
		"state_name": get_state_name(current_state),
		"state_color": get_state_color(current_state),
		"distance_to_player": distance,
		"detection_range": detection_range,
		"attack_range": attack_range,
		"safe_distance": safe_distance,
		"health_ratio": health_ratio,
		"attack_cooldown": max(0.0, attack_timer),
		"is_adaptive": adaptive_logic.is_adaptive_enabled if adaptive_logic else false,
		"reason": last_reason
	}
	telemetry_updated.emit(data)

func notify_player_attacked() -> void:
	if adaptive_logic and adaptive_logic.has_method("record_player_attack"):
		adaptive_logic.record_player_attack()

func toggle_adaptive() -> bool:
	if adaptive_logic:
		var result = adaptive_logic.toggle_adaptive_mode()
		mode_toggled.emit(result)
		return result
	return false

func is_adaptive() -> bool:
	return adaptive_logic.is_adaptive_enabled if adaptive_logic else false

func reset_fsm() -> void:
	attack_timer = 0.0
	current_state = State.IDLE
	last_reason = "FSM reset to initial IDLE state."
	if adaptive_logic and adaptive_logic.has_method("reset_adaptive_telemetry"):
		adaptive_logic.reset_adaptive_telemetry()
	if enemy:
		enemy.update_visual_state(get_state_name(current_state), get_state_color(current_state), last_reason)
