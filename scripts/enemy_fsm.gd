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
@export var detection_range: float = 240.0
@export var attack_range: float = 65.0
@export var safe_distance: float = 260.0
@export var flee_health_ratio: float = 0.30 # 30% max health
@export var attack_damage: int = 14
@export var attack_cooldown_time: float = 0.70

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
	# Prevent thrashing: If already at a safe distance in IDLE, hold position instead of infinite loop
	if health_ratio <= flee_health_ratio and current_state != State.FLEE and current_state != State.DEAD:
		var threat_nearby = (current_state == State.ATTACK or current_state == State.CHASE or distance_to_player < safe_distance)
		if threat_nearby:
			var reason_text = ""
			if adaptive_logic and adaptive_logic.is_adaptive_enabled and flee_health_ratio > adaptive_logic.BASE_FLEE_THRESHOLD + 0.02:
				reason_text = "Adaptive Early Flee: Aggression HIGH (%.2f) -> Threshold raised to %.0f%% (HP: %d/%d)" % [
					adaptive_logic.player_aggression_score,
					flee_health_ratio * 100.0,
					enemy.current_health,
					enemy.max_health
				]
			else:
				reason_text = "Static Flee: Low Health (HP: %d/%d - %.0f%% <= %.0f%% threshold)" % [
					enemy.current_health,
					enemy.max_health,
					health_ratio * 100.0,
					flee_health_ratio * 100.0
				]
			change_state(State.FLEE, reason_text)
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

var heal_tick_timer: float = 0.0
var total_healed_this_episode: int = 0
const MAX_HEAL_CAPACITY: int = 24
var idle_recovery_timer: float = 0.0

func _process_idle_state(distance: float) -> void:
	if enemy.player:
		enemy.stop_moving(enemy.player.global_position)
	else:
		enemy.stop_moving()
	
	idle_recovery_timer += get_physics_process_delta_time()
	
	# Tactical Recovery: Heal while maintaining safe perimeter, capped at MAX_HEAL_CAPACITY
	if enemy.current_health < enemy.max_health and distance >= safe_distance and total_healed_this_episode < MAX_HEAL_CAPACITY:
		heal_tick_timer += get_physics_process_delta_time()
		if heal_tick_timer >= 0.4:
			heal_tick_timer = 0.0
			var heal_amount = min(4, MAX_HEAL_CAPACITY - total_healed_this_episode)
			total_healed_this_episode += heal_amount
			enemy.heal(heal_amount)
			last_reason = "Tactical Recovery: Safe distance (+8 HP/s | Bandages left: %d HP)" % [MAX_HEAL_CAPACITY - total_healed_this_episode]
	else:
		heal_tick_timer = 0.0
	
	# Transition 1: Player enters detection range
	if distance <= detection_range:
		var extra_info = ""
		if adaptive_logic and adaptive_logic.is_adaptive_enabled and detection_range > adaptive_logic.BASE_DETECTION_RANGE + 4.0:
			extra_info = " [Adaptive Expansion: %dpx > base %dpx]" % [round(detection_range), round(adaptive_logic.BASE_DETECTION_RANGE)]
		idle_recovery_timer = 0.0
		change_state(
			State.CHASE,
			"Player entered detection range (Distance: %d px <= %d px)%s" % [round(distance), round(detection_range), extra_info]
		)
		return
	
	# Transition 2: Recovery window complete or Idle timeout -> Re-engage! Never stall in IDLE
	if idle_recovery_timer >= 1.6 and enemy.current_health > int(enemy.max_health * flee_health_ratio):
		idle_recovery_timer = 0.0
		change_state(
			State.CHASE,
			"Tactical recovery complete; resuming pursuit of target (Distance: %d px)" % round(distance)
		)

func _process_chase_state(target_pos: Vector2, distance: float) -> void:
	# Adaptive Flanking / Strafing: If player is hyper-aggressive, circle slightly instead of running head-first
	var move_target = target_pos
	if adaptive_logic and adaptive_logic.is_adaptive_enabled and adaptive_logic.player_aggression_score > 0.55:
		var dir_to_player = (target_pos - enemy.global_position).normalized()
		var perp_strafe = Vector2(-dir_to_player.y, dir_to_player.x)
		move_target = target_pos + perp_strafe * 40.0
	
	enemy.move_towards_point(move_target, enemy.base_speed)
	
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

func _get_enemy_boundary_avoidance() -> Vector2:
	if not enemy:
		return Vector2.ZERO
	var pos = enemy.global_position
	var steer = Vector2.ZERO
	if pos.x < 120.0: steer.x += 1.0
	elif pos.x > 1030.0: steer.x -= 1.0
	if pos.y < 120.0: steer.y += 1.0
	elif pos.y > 530.0: steer.y -= 1.0
	return steer.normalized()

func _process_attack_state(distance: float) -> void:
	if enemy.player:
		var dir_to_player = enemy.global_position.direction_to(enemy.player.global_position)
		if distance > attack_range * 0.8:
			enemy.move_towards_point(enemy.player.global_position, enemy.base_speed * 0.6)
		elif distance < attack_range * 0.4:
			enemy.move_towards_point(enemy.global_position - dir_to_player * 50.0, enemy.base_speed * 0.5)
		else:
			enemy.stop_moving(enemy.player.global_position)
	else:
		enemy.stop_moving()
	
	if attack_timer <= 0.0:
		attack_timer = attack_cooldown_time
		if enemy.has_method("trigger_attack_visual"):
			enemy.trigger_attack_visual()
		if enemy.player and enemy.player.has_method("take_damage"):
			enemy.player.take_damage(attack_damage)
	
	if distance > attack_range * 1.3:
		change_state(
			State.CHASE,
			"Player moved outside attack range (Distance: %d px > %d px)" % [round(distance), round(attack_range * 1.3)]
		)

func _process_flee_state(player_pos: Vector2, distance: float, _health_ratio: float) -> void:
	var flee_direction = (enemy.global_position - player_pos).normalized()
	var avoid = _get_enemy_boundary_avoidance()
	
	var final_flee_dir = flee_direction
	if avoid != Vector2.ZERO:
		final_flee_dir = (flee_direction * 0.35 + avoid * 0.85).normalized()
	
	var flee_target = enemy.global_position + final_flee_dir * 160.0
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
	var active_reason = last_reason
	if adaptive_logic and adaptive_logic.is_adaptive_enabled:
		if current_state == State.IDLE and detection_range > adaptive_logic.BASE_DETECTION_RANGE + 4.0:
			active_reason = adaptive_logic.current_adaptive_explanation
		elif current_state == State.ATTACK and adaptive_logic.player_aggression_score > 0.5:
			active_reason = adaptive_logic.current_adaptive_explanation

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
		"reason": active_reason
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
	total_healed_this_episode = 0
	idle_recovery_timer = 0.0
	last_reason = "FSM reset to initial IDLE state."
	if adaptive_logic and adaptive_logic.has_method("reset_adaptive_telemetry"):
		adaptive_logic.reset_adaptive_telemetry()
	if enemy:
		enemy.update_visual_state(get_state_name(current_state), get_state_color(current_state), last_reason)
