extends Node

# ==============================================================================
# AUTOMATED PLAYER BOT CONTROLLER
# ------------------------------------------------------------------------------
# Simulates distinct opponent playstyle policies for automated experimentation:
# - AGGRESSIVE: Direct pursuit, sprints, continuous melee attacks.
# - DEFENSIVE: Kites and maintains distance, evades, strikes only if cornered.
# - RANDOM: Stochastic movement changes every 0.8s with random attack swings.
# ==============================================================================

enum BotMode {
	MANUAL,
	AGGRESSIVE,
	DEFENSIVE,
	RANDOM
}

@export var current_mode: BotMode = BotMode.MANUAL
@export var is_active: bool = false

var player: CharacterBody2D = null
var enemy: CharacterBody2D = null

# Bot Timers
var random_direction_timer: float = 0.0
var random_direction: Vector2 = Vector2.ZERO

func _ready() -> void:
	player = get_parent() as CharacterBody2D
	find_enemy()

func find_enemy() -> void:
	if not enemy or not is_instance_valid(enemy):
		enemy = get_tree().root.find_child("EnemyNPC", true, false)

func _physics_process(delta: float) -> void:
	if not player or not is_active or current_mode == BotMode.MANUAL:
		if player:
			player.is_bot_controlled = false
		return
	
	player.is_bot_controlled = true
	find_enemy()
	if not enemy or not is_instance_valid(enemy) or not player.is_alive:
		player.bot_move_dir = Vector2.ZERO
		return
	
	var distance = player.global_position.distance_to(enemy.global_position)
	var dir_to_enemy = (enemy.global_position - player.global_position).normalized()
	
	match current_mode:
		BotMode.AGGRESSIVE:
			_process_aggressive_mode(dir_to_enemy, distance, delta)
		BotMode.DEFENSIVE:
			_process_defensive_mode(dir_to_enemy, distance, delta)
		BotMode.RANDOM:
			_process_random_mode(distance, delta)

const ARENA_CENTER: Vector2 = Vector2(576, 325)

func _get_boundary_avoidance() -> Vector2:
	if not player:
		return Vector2.ZERO
	var pos = player.global_position
	var steer = Vector2.ZERO
	if pos.x < 120.0: steer.x += 1.0
	elif pos.x > 1030.0: steer.x -= 1.0
	if pos.y < 120.0: steer.y += 1.0
	elif pos.y > 530.0: steer.y -= 1.0
	return steer.normalized()

func _process_aggressive_mode(dir_to_enemy: Vector2, distance: float, _delta: float) -> void:
	var avoid = _get_boundary_avoidance()
	if avoid != Vector2.ZERO and distance > 120.0:
		player.bot_move_dir = (dir_to_enemy + avoid * 0.7).normalized()
	else:
		player.bot_move_dir = dir_to_enemy
	
	# Sprint only to close medium distances
	player.bot_wants_sprint = (distance > 130.0 and distance < 350.0)
	
	# Human-like aggressive mashing: swing slightly early (allows smart AI to bait misses)
	if distance <= player.attack_range + 12.0:
		player.perform_attack()

func _process_defensive_mode(dir_to_enemy: Vector2, distance: float, _delta: float) -> void:
	var avoid = _get_boundary_avoidance()
	
	# If enemy is fleeing or at low health, press the advantage!
	var enemy_is_fleeing = false
	if enemy and enemy.has_node("EnemyFSM"):
		var fsm_node = enemy.get_node("EnemyFSM")
		enemy_is_fleeing = (fsm_node.current_state == 3) # State.FLEE
	
	if enemy_is_fleeing:
		# Pursue retreating enemy so they cannot heal freely
		player.bot_wants_sprint = true
		player.bot_move_dir = dir_to_enemy
	else:
		# Tactical combat spacing: maintain 110px to 170px range
		player.bot_wants_sprint = false
		if avoid != Vector2.ZERO:
			# Steer away from walls toward arena center
			player.bot_move_dir = avoid
		elif distance < 110.0:
			# Back off slightly
			player.bot_move_dir = -dir_to_enemy
		elif distance > 170.0:
			# Advance to engage
			player.bot_move_dir = dir_to_enemy * 0.8
		else:
			# Circle/strafe sideways around opponent
			player.bot_move_dir = Vector2(-dir_to_enemy.y, dir_to_enemy.x).normalized()
	
	# Counter-attack when enemy is in striking distance (human-like mashing)
	if distance <= player.attack_range + 12.0:
		player.perform_attack()

var random_attack_timer: float = 0.0

func _process_random_mode(distance: float, delta: float) -> void:
	random_direction_timer -= delta
	random_attack_timer -= delta
	
	var avoid = _get_boundary_avoidance()
	if avoid != Vector2.ZERO:
		player.bot_move_dir = avoid
	elif random_direction_timer <= 0.0:
		random_direction_timer = randf_range(0.8, 1.8)
		# 60% chance to move towards enemy, 40% random wander
		if randf() < 0.6 and enemy:
			var dir_to_enemy = (enemy.global_position - player.global_position).normalized()
			var spread = randf_range(-0.5, 0.5)
			player.bot_move_dir = dir_to_enemy.rotated(spread)
		else:
			var angle = randf_range(0, TAU)
			player.bot_move_dir = Vector2(cos(angle), sin(angle))
	
	player.bot_wants_sprint = (distance > 180.0 and randf() > 0.5)
	
	# Attack when close (with human-like mashing tolerance)
	if distance <= player.attack_range + 12.0 and random_attack_timer <= 0.0:
		random_attack_timer = randf_range(0.4, 0.9)
		player.perform_attack()

func set_mode(mode: BotMode) -> void:
	current_mode = mode
	is_active = (mode != BotMode.MANUAL)
	if player:
		player.is_bot_controlled = is_active
		if not is_active:
			player.bot_move_dir = Vector2.ZERO

func cycle_mode() -> BotMode:
	var next_mode = (current_mode + 1) % 4
	set_mode(next_mode)
	return current_mode

func get_mode_name() -> String:
	match current_mode:
		BotMode.MANUAL: return "MANUAL (WASD)"
		BotMode.AGGRESSIVE: return "AGGRESSIVE BOT"
		BotMode.DEFENSIVE: return "DEFENSIVE BOT"
		BotMode.RANDOM: return "RANDOM BOT"
		_: return "UNKNOWN"
