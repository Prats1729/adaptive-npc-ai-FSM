extends Node

# ==============================================================================
# ENEMY FINITE STATE MACHINE (FSM)
# ------------------------------------------------------------------------------
# Core AI Decision-Making Component.
# Evaluates sensory perception (player distance, entity health) each physics tick
# and executes transparent, rule-based state transitions with clear explainability.
# Supports both Basic FSM and Adaptive FSM behavioral modulation.
#
# DESIGN PRINCIPLE (Spronck et al., 2006):
#   The Baseline FSM uses fixed thresholds and simple behaviors.
#   The Adaptive FSM changes STRATEGY (hit-and-run, engagement timing,
#   counter-strikes), not raw stats. Both share equal combat parameters.
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

# Adaptive Hit-and-Run Kiting
var hit_and_run_timer: float = 0.0
var hit_and_run_active: bool = false

var idle_recovery_timer: float = 0.0
var last_stimulus_usec: int = 0

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
	
	# Handle hit-and-run disengage timer
	if hit_and_run_timer > 0.0:
		hit_and_run_timer -= delta
		if hit_and_run_timer <= 0.0:
			hit_and_run_active = false

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

	# Global Transition Rule: Flee when health drops below retreat threshold
	if health_ratio <= flee_health_ratio and current_state != State.FLEE and current_state != State.DEAD:
		var threat_nearby = (current_state == State.ATTACK or current_state == State.CHASE or distance_to_player < safe_distance)
		if threat_nearby:
			var reason_text = ""
			if adaptive_logic and adaptive_logic.is_adaptive_enabled and flee_health_ratio > adaptive_logic.BASE_FLEE_THRESHOLD + 0.02:
				reason_text = "Adaptive Tactical Retreat: Aggression HIGH (%.2f) -> Threshold raised to %.0f%% (HP: %d/%d)" % [
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

func _process_idle_state(distance: float) -> void:
	if enemy.player:
		enemy.stop_moving(enemy.player.global_position)
	else:
		enemy.stop_moving()
	
	idle_recovery_timer += get_physics_process_delta_time()
	
	# Transition 1: Player enters detection range
	if distance <= detection_range:
		if last_stimulus_usec == 0:
			notify_stimulus_received()
		var extra_info = ""
		if adaptive_logic and adaptive_logic.is_adaptive_enabled and detection_range > adaptive_logic.BASE_DETECTION_RANGE + 4.0:
			extra_info = " [Adaptive Expansion: %dpx > base %dpx]" % [round(detection_range), round(adaptive_logic.BASE_DETECTION_RANGE)]
		idle_recovery_timer = 0.0
		change_state(
			State.CHASE,
			"Player entered detection range (Distance: %d px <= %d px)%s" % [round(distance), round(detection_range), extra_info]
		)
		return
	
	# Transition 2: Recovery window complete -> Re-engage
	if idle_recovery_timer >= 1.5 and enemy.current_health > int(enemy.max_health * flee_health_ratio):
		idle_recovery_timer = 0.0
		change_state(
			State.CHASE,
			"Recovery complete; resuming pursuit (Distance: %d px)" % round(distance)
		)

func _process_chase_state(target_pos: Vector2, distance: float) -> void:
	var move_target = target_pos
	var chase_speed = enemy.base_speed
	
	if adaptive_logic and adaptive_logic.is_adaptive_enabled:
		# Adaptive Flanking: If player is aggressive, approach from an angle
		if adaptive_logic.player_aggression_score > 0.45:
			var dir_to_player = (target_pos - enemy.global_position).normalized()
			var perp_strafe = Vector2(-dir_to_player.y, dir_to_player.x)
			# Alternate strafe direction using time to avoid predictability
			var strafe_sign = 1.0 if fmod(Time.get_ticks_msec() / 1000.0, 2.0) < 1.0 else -1.0
			move_target = target_pos + perp_strafe * strafe_sign * 55.0
		
		# Adaptive Engagement Timing: Sprint to close distance during player's cooldown
		if adaptive_logic.player_in_cooldown and distance > attack_range and distance < detection_range:
			chase_speed = enemy.base_speed * 1.35
			last_reason = "Adaptive Timing: Exploiting player cooldown window to close distance"
	
	enemy.move_towards_point(move_target, chase_speed)
	
	if distance <= attack_range:
		change_state(
			State.ATTACK,
			"Player entered attack range (Distance: %d px <= %d px)" % [round(distance), round(attack_range)]
		)
	elif distance > detection_range * 1.3:
		change_state(
			State.IDLE,
			"Player escaped detection range (Distance: %d px > %d px)" % [round(distance), round(detection_range * 1.3)]
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
	# --- ADAPTIVE HIT-AND-RUN KITING ---
	# After landing a strike against an aggressive player, briefly disengage
	# to avoid standing in a slug-fest the NPC would lose (equal DPS, player is faster)
	if adaptive_logic and adaptive_logic.is_adaptive_enabled and hit_and_run_active:
		if enemy.player:
			var away_dir = (enemy.global_position - enemy.player.global_position).normalized()
			var avoid = _get_enemy_boundary_avoidance()
			var disengage_dir = away_dir
			if avoid != Vector2.ZERO:
				disengage_dir = (away_dir * 0.5 + avoid * 0.7).normalized()
			
			# Hit-and-run requires burst of speed to escape player's reach
			enemy.move_towards_point(enemy.global_position + disengage_dir * 100.0, enemy.flee_speed)
		
		# If we've created enough distance, transition back to chase for re-engagement
		if distance > attack_range * 1.8:
			hit_and_run_active = false
			change_state(
				State.CHASE,
				"Adaptive Hit-and-Run: Disengaged after strike, repositioning (Distance: %dpx)" % round(distance)
			)
		return
	
	# --- NORMAL ATTACK BEHAVIOR ---
	if enemy.player:
		if distance > attack_range * 0.75:
			enemy.move_towards_point(enemy.player.global_position, enemy.base_speed * 0.8)
		else:
			enemy.stop_moving(enemy.player.global_position)
	else:
		enemy.stop_moving()
	
	# Execute attack when cooldown expires
	if attack_timer <= 0.0:
		attack_timer = attack_cooldown_time
		if enemy.has_method("trigger_attack_visual"):
			enemy.trigger_attack_visual()
		if enemy.player and enemy.player.has_method("take_damage"):
			enemy.player.take_damage(attack_damage)
		
		# Adaptive: Initiate hit-and-run kiting against aggressive players
		if adaptive_logic and adaptive_logic.is_adaptive_enabled and adaptive_logic.player_aggression_score > 0.40:
			hit_and_run_active = true
			hit_and_run_timer = 0.50  # Brief disengage window after striking
			last_reason = "Adaptive Hit-and-Run: Struck target, disengaging to avoid trade (Aggression: %.2f)" % adaptive_logic.player_aggression_score
	
	# Transition out if player moves away
	if distance > attack_range * 1.3:
		change_state(
			State.CHASE,
			"Player moved outside attack range (Distance: %d px > %d px)" % [round(distance), round(attack_range * 1.3)]
		)

func _process_flee_state(player_pos: Vector2, distance: float, _health_ratio: float) -> void:
	# === ADAPTIVE-ONLY BEHAVIORS ===
	if adaptive_logic and adaptive_logic.is_adaptive_enabled and enemy.player:
		# Adaptive Counter-Offensive: If the NPC has equal or more HP, turn and fight!
		if enemy.player.current_health <= enemy.current_health:
			var target_state = State.ATTACK if distance <= attack_range else State.CHASE
			change_state(
				target_state,
				"Adaptive Counter-Offensive: Target not stronger (Player HP: %d <= NPC HP: %d); engaging." % [
					enemy.player.current_health, enemy.current_health
				]
			)
			return
		
		# Adaptive Retaliatory Counter-Strike: Punish reckless chasers in melee range
		if distance <= attack_range and attack_timer <= 0.0:
			attack_timer = attack_cooldown_time
			if enemy.has_method("trigger_attack_visual"):
				enemy.trigger_attack_visual()
			if enemy.player.has_method("take_damage"):
				enemy.player.take_damage(attack_damage)
				last_reason = "Adaptive Counter-Strike: Punished pursuer at %dpx" % round(distance)
				# Check if this strike gave us the HP lead (or equalized it)
				if enemy.player.current_health <= enemy.current_health:
					change_state(
						State.ATTACK,
						"Adaptive Counter-Offensive: Counter-strike equalized/seized HP lead (Player: %d <= NPC: %d); turning to fight." % [
							enemy.player.current_health, enemy.current_health
						]
					)
					return
	
	# === FLEE MOVEMENT (Both Basic and Adaptive) ===
	var flee_direction = (enemy.global_position - player_pos).normalized()
	var avoid = _get_enemy_boundary_avoidance()
	
	var final_flee_dir = flee_direction
	if avoid != Vector2.ZERO:
		# Adaptive: Use more lateral/perpendicular movement to avoid corners
		if adaptive_logic and adaptive_logic.is_adaptive_enabled:
			var perp = Vector2(-flee_direction.y, flee_direction.x)
			final_flee_dir = (flee_direction * 0.3 + avoid * 0.5 + perp * 0.3).normalized()
		else:
			final_flee_dir = (flee_direction * 0.4 + avoid * 0.8).normalized()
	
	var flee_target = enemy.global_position + final_flee_dir * 150.0
	enemy.move_towards_point(flee_target, enemy.flee_speed)
	
	# Transition: Reached safe distance
	if distance >= safe_distance:
		change_state(
			State.IDLE,
			"Established safe distance from player (Distance: %d px >= %d px)" % [round(distance), round(safe_distance)]
		)

# --- EXPLAINABILITY & STATE SWITCHING ---

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
	
	# Reset hit-and-run on state change
	if new_state != State.ATTACK:
		hit_and_run_active = false
		hit_and_run_timer = 0.0
	
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
	hit_and_run_active = false
	hit_and_run_timer = 0.0
	last_reason = "FSM reset to initial IDLE state."
	if adaptive_logic and adaptive_logic.has_method("reset_adaptive_telemetry"):
		adaptive_logic.reset_adaptive_telemetry()
	if enemy:
		enemy.update_visual_state(get_state_name(current_state), get_state_color(current_state), last_reason)
