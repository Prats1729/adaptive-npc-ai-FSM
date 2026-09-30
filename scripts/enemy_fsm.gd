extends Node

# ==============================================================================
# ENEMY FINITE STATE MACHINE (FSM)
# ------------------------------------------------------------------------------
# Core AI Decision-Making Component.
# Evaluates sensory perception (player distance, entity health) each physics tick
# and executes transparent, rule-based state transitions with clear explainability.
#
# Supports:
# - BASIC FSM: Static baseline decision rules with fixed thresholds.
# - ADAPTIVE FSM: Dynamic Scripting (Spronck et al., 2006) policy execution.
#
# States:
#   IDLE   -> Holding position / scanning arena
#   CHASE  -> Pursuing player (direct or tactical intercept)
#   ATTACK -> Engaging in melee range (cadence, spacing, or whiff punish)
#   FLEE   -> Disengaging toward arena center when health drops below threshold
#   DEAD   -> NPC defeated
# ==============================================================================

signal state_changed(old_state_name: String, new_state_name: String, reason: String)
signal telemetry_updated(telemetry_data: Dictionary)
signal mode_toggled(is_adaptive: bool)
signal response_time_measured(time_sec: float)

enum State {
	IDLE,
	CHASE,
	ATTACK,
	FLEE,
	DEAD
}

@export_group("FSM Decision Thresholds")
@export var detection_range: float = 200.0
@export var attack_range: float = 35.0
@export var safe_distance: float = 250.0
@export var flee_health_ratio: float = 0.25 # 25% max health
@export var attack_damage: int = 12
@export var attack_cooldown_time: float = 0.80

var current_state: State = State.IDLE
var enemy: CharacterBody2D = null
var attack_timer: float = 0.0
var last_reason: String = "Simulation Initialized"
var is_active: bool = true

# Timing & stimulus tracking
var idle_recovery_timer: float = 0.0
var last_stimulus_usec: int = 0

# Spacing ring for whiff-punish tactical maneuvering
const WHIFF_SPACING_DISTANCE: float = 48.0
const ARENA_CENTER: Vector2 = Vector2(576, 325)

@onready var adaptive_logic: Node = $AdaptiveLogic if has_node("AdaptiveLogic") else null

# Colors representing each state for visual feedback
const STATE_COLORS = {
	State.IDLE: Color(0.4, 0.9, 0.5),     # Emerald Green (Neutral)
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

	# Handle attack cooldown
	if attack_timer > 0.0:
		attack_timer -= delta

	# Check for NPC defeat
	if enemy.current_health <= 0:
		if current_state != State.DEAD:
			change_state(State.DEAD, "Enemy health dropped to 0.")
		return

	# Sensory Perception
	var player_pos: Vector2 = enemy.player.global_position
	var distance_to_player: float = enemy.global_position.distance_to(player_pos)
	var health_ratio: float = float(enemy.current_health) / float(enemy.max_health)
	
	emit_telemetry(distance_to_player, health_ratio)

	# Global Transition Rule: Flee when health drops below retreat threshold
	# Note: If active policy sets flee_health_ratio to 0.0 (e.g. STAND_AND_TRADE or WHIFF_PUNISH),
	# retreat is disabled because running from a faster pursuer forfeits DPS.
	if flee_health_ratio > 0.0 and health_ratio <= flee_health_ratio and current_state != State.FLEE and current_state != State.DEAD:
		var threat_nearby = (current_state == State.ATTACK or current_state == State.CHASE or distance_to_player < safe_distance)
		if threat_nearby:
			var reason_text = "Retreat Threshold Reached: HP %d/%d (%.0f%% <= %.0f%%)" % [
				enemy.current_health, enemy.max_health, health_ratio * 100.0, flee_health_ratio * 100.0
			]
			if adaptive_logic and adaptive_logic.is_adaptive_enabled:
				reason_text = "Adaptive Tactical Disengage: %s (HP: %.0f%% <= %.0f%%)" % [
					adaptive_logic.get_active_rule_name(), health_ratio * 100.0, flee_health_ratio * 100.0
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
			_process_flee_state(player_pos, distance_to_player)
			
		State.DEAD:
			enemy.stop_moving()

# ==============================================================================
# STATE EXECUTION & TACTICAL TRANSITIONS
# ==============================================================================

func _process_idle_state(distance: float) -> void:
	if enemy.player:
		enemy.stop_moving(enemy.player.global_position)
	else:
		enemy.stop_moving()
	
	idle_recovery_timer += get_physics_process_delta_time()
	
	# Transition 1: Target enters detection range
	if distance <= detection_range:
		if last_stimulus_usec == 0:
			notify_stimulus_received()
		idle_recovery_timer = 0.0
		var reason = "Player detected within range (Distance: %dpx <= %dpx)" % [round(distance), round(detection_range)]
		if adaptive_logic and adaptive_logic.is_adaptive_enabled:
			reason = "[%s] Target detected (%dpx <= %dpx)" % [
				adaptive_logic.get_active_rule_name(), round(distance), round(detection_range)
			]
		change_state(State.CHASE, reason)
		return
	# Remain in IDLE scanning until target enters detection range

func _process_chase_state(target_pos: Vector2, distance: float) -> void:
	var move_target = target_pos
	var chase_speed = enemy.base_speed
	var avoid = _get_enemy_boundary_avoidance()
	
	if adaptive_logic and adaptive_logic.is_adaptive_enabled:
		var rule_id = adaptive_logic.active_rule_id
		
		match rule_id:
			# Policy 1: WHIFF_PUNISH (Spacing bait against early swingers)
			1:
				if adaptive_logic.player_in_cooldown:
					# Opponent is in recovery window -> Surge in to punish!
					chase_speed = enemy.base_speed * 1.35
					move_target = target_pos
				else:
					# Opponent weapon ready -> Maintain 48px spacing distance to bait early swing
					var dir_away = (enemy.global_position - target_pos).normalized()
					if distance < WHIFF_SPACING_DISTANCE:
						# Backpedal away to keep spacing at ~48px
						move_target = enemy.global_position + dir_away * 60.0
						chase_speed = enemy.flee_speed
					else:
						# Hold position at spacing ring
						move_target = target_pos + dir_away * WHIFF_SPACING_DISTANCE
						chase_speed = enemy.base_speed * 0.8
			
			# Policy 3: PRESSURE_HUNT (Leading intercept against kiters)
			3:
				var player_vel = enemy.player.velocity if "velocity" in enemy.player else Vector2.ZERO
				move_target = target_pos + player_vel * 0.35
				chase_speed = enemy.base_speed * 1.15
			
			# Policy 2: TACTICAL_KITE (Arena center bias)
			2:
				var to_center = (ARENA_CENTER - enemy.global_position).normalized()
				move_target = (target_pos + to_center * 40.0)
			
			# Policy 0: STAND_AND_TRADE (Direct relentless rush)
			_:
				move_target = target_pos
	
	# Apply boundary avoidance so the NPC never walks directly into corners
	if avoid != Vector2.ZERO and distance > 100.0:
		var steer_dir = (move_target - enemy.global_position).normalized() + avoid * 0.8
		move_target = enemy.global_position + steer_dir.normalized() * 100.0
	
	enemy.move_towards_point(move_target, chase_speed)
	
	# Transitions out of Chase
	if distance <= attack_range:
		var attack_reason = "Entered melee attack range (Distance: %dpx <= %dpx)" % [round(distance), round(attack_range)]
		if adaptive_logic and adaptive_logic.is_adaptive_enabled and adaptive_logic.active_rule_id == 1:
			attack_reason = "Whiff Punish: Target in recovery window; striking!"
		change_state(State.ATTACK, attack_reason)
		if attack_timer <= 0.0:
			_execute_attack()
	elif distance > detection_range * 1.35:
		change_state(State.IDLE, "Target moved beyond detection range (Distance: %dpx > %dpx)" % [
			round(distance), round(detection_range * 1.35)
		])

func _execute_attack() -> void:
	attack_timer = attack_cooldown_time
	if enemy.has_method("trigger_attack_visual"):
		enemy.trigger_attack_visual()
	if enemy.player and enemy.player.has_method("take_damage"):
		enemy.player.take_damage(attack_damage)

func _process_attack_state(distance: float) -> void:
	var is_whiff_punish = (adaptive_logic and adaptive_logic.is_adaptive_enabled and adaptive_logic.active_rule_id == 1)
	
	if enemy.player:
		if is_whiff_punish:
			if attack_timer <= 0.0 and distance <= attack_range:
				_execute_attack()
				# Immediately disengage back to spacing ring
				var dir_away = (enemy.global_position - enemy.player.global_position).normalized()
				enemy.move_towards_point(enemy.global_position + dir_away * 60.0, enemy.flee_speed)
			elif attack_timer > 0.0:
				# On cooldown after strike: disengage to spacing ring (48px)
				var dir_away = (enemy.global_position - enemy.player.global_position).normalized()
				enemy.move_towards_point(enemy.global_position + dir_away * 60.0, enemy.flee_speed)
		else:
			if distance > attack_range * 0.7:
				enemy.move_towards_point(enemy.player.global_position, enemy.base_speed * 0.8)
			else:
				enemy.stop_moving(enemy.player.global_position)
			
			if attack_timer <= 0.0 and distance <= attack_range:
				_execute_attack()
	else:
		enemy.stop_moving()
	
	# Transition out if opponent retreats outside strike range
	if distance > attack_range * 1.35:
		change_state(State.CHASE, "Target disengaged outside attack range (%dpx > %dpx)" % [
			round(distance), round(attack_range * 1.35)
		])

func _process_flee_state(player_pos: Vector2, distance: float) -> void:
	var flee_direction = (enemy.global_position - player_pos).normalized()
	var avoid = _get_enemy_boundary_avoidance()
	var to_center = (ARENA_CENTER - enemy.global_position).normalized()
	
	# Arena-Aware Steering: prioritize open arena space over running into a corner
	var final_flee_dir = (flee_direction * 0.4 + avoid * 0.6 + to_center * 0.4).normalized()
	var flee_target = enemy.global_position + final_flee_dir * 150.0
	
	enemy.move_towards_point(flee_target, enemy.flee_speed)
	
	# Transition: Established safe distance
	if distance >= safe_distance * 1.15:
		change_state(State.IDLE, "Established safe distance (%dpx >= %dpx); entering recovery" % [
			round(distance), round(safe_distance * 1.15)
		])

# ==============================================================================
# ARENA STEERING & EXPLAINABILITY
# ==============================================================================

func _get_enemy_boundary_avoidance() -> Vector2:
	if not enemy:
		return Vector2.ZERO
	var pos = enemy.global_position
	var steer = Vector2.ZERO
	if pos.x < 130.0: steer.x += 1.0
	elif pos.x > 1020.0: steer.x -= 1.0
	if pos.y < 130.0: steer.y += 1.0
	elif pos.y > 520.0: steer.y -= 1.0
	return steer.normalized()

func change_state(new_state: State, reason: String) -> void:
	if current_state == new_state:
		return
	
	if last_stimulus_usec > 0:
		var response_time_sec = (Time.get_ticks_usec() - last_stimulus_usec) / 1000000.0
		if response_time_sec <= 0.0001:
			response_time_sec = get_physics_process_delta_time()
		response_time_measured.emit(response_time_sec)
		last_stimulus_usec = 0
	
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

func notify_stimulus_received() -> void:
	if last_stimulus_usec == 0:
		last_stimulus_usec = Time.get_ticks_usec()

func notify_player_attacked() -> void:
	notify_stimulus_received()
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
	idle_recovery_timer = 0.0
	last_reason = "FSM reset to initial IDLE state."
	if adaptive_logic and adaptive_logic.has_method("reset_adaptive_telemetry"):
		adaptive_logic.reset_adaptive_telemetry()
	if enemy:
		enemy.update_visual_state(get_state_name(current_state), get_state_color(current_state), last_reason)
