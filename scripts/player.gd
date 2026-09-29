extends CharacterBody2D

# ==============================================================================
# PLAYER CONTROLLER
# ------------------------------------------------------------------------------
# Handles player movement (WASD / Arrow Keys), sprinting (Shift),
# basic melee attack (Space / Left Mouse Button), and health tracking.
# Controls the procedural 2D humanoid visual representation.
# ==============================================================================

signal health_changed(current_health: int, max_health: int)
signal player_attacked()
signal player_died()

@export var walk_speed: float = 240.0
@export var sprint_speed: float = 380.0
@export var max_health: int = 100
@export var attack_damage: int = 25
@export var attack_range: float = 65.0
@export var attack_cooldown_time: float = 0.35

var current_health: int = 100
var attack_timer: float = 0.0
var is_alive: bool = true
var last_facing_dir: Vector2 = Vector2.RIGHT

@onready var hp_bar: ProgressBar = $ProgressBar if has_node("ProgressBar") else null
@onready var visual: Node2D = $HumanoidVisual if has_node("HumanoidVisual") else null

func _ready() -> void:
	current_health = max_health
	if hp_bar:
		hp_bar.max_value = max_health
		hp_bar.value = current_health
	if visual and visual.has_method("set_facing"):
		visual.set_facing(Vector2.RIGHT)
	health_changed.emit(current_health, max_health)

func _physics_process(delta: float) -> void:
	if not is_alive:
		velocity = Vector2.ZERO
		move_and_slide()
		if visual and visual.has_method("set_facing"):
			visual.set_facing(Vector2.ZERO)
		return
	
	# Update attack cooldown
	if attack_timer > 0.0:
		attack_timer -= delta
	
	# Handle Attack input (Spacebar, UI Accept, or Left Mouse Click)
	if Input.is_action_just_pressed("ui_accept") or Input.is_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		perform_attack()
	
	# Handle Movement Input (supports both Arrow Keys and WASD)
	var input_vector = Vector2.ZERO
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_vector.x += 1.0
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_vector.x -= 1.0
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_vector.y += 1.0
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_vector.y -= 1.0
	
	var direction = input_vector.normalized()
	
	# Sprint check (Shift key)
	var speed = sprint_speed if (Input.is_key_pressed(KEY_SHIFT)) else walk_speed
	
	# Apply velocity & update humanoid facing
	if direction != Vector2.ZERO:
		velocity = direction * speed
		last_facing_dir = direction
		if visual and visual.has_method("set_facing"):
			visual.set_facing(direction)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, walk_speed)
		if visual and visual.has_method("set_facing"):
			visual.set_facing(Vector2.ZERO)
	
	move_and_slide()

func perform_attack() -> void:
	if attack_timer > 0.0 or not is_alive:
		return
	
	attack_timer = attack_cooldown_time
	player_attacked.emit()
	
	# Trigger weapon slash animation on the humanoid visual
	if visual and visual.has_method("trigger_attack_anim"):
		visual.trigger_attack_anim(attack_cooldown_time * 0.8)
	
	# Find enemy NPC in arena
	var enemy = get_tree().root.find_child("EnemyNPC", true, false)
	if not enemy:
		enemy = get_parent().get_node_or_null("EnemyNPC")
	
	if enemy and is_instance_valid(enemy):
		var distance = global_position.distance_to(enemy.global_position)
		if distance <= attack_range:
			if enemy.has_method("take_damage"):
				enemy.take_damage(attack_damage)

func take_damage(amount: int) -> void:
	if not is_alive:
		return
	
	current_health = max(0, current_health - amount)
	if hp_bar:
		hp_bar.value = current_health
	
	health_changed.emit(current_health, max_health)
	
	# Trigger hit flash on humanoid visual
	if visual and visual.has_method("trigger_damage_flash"):
		visual.trigger_damage_flash(0.18)
	
	if current_health <= 0:
		is_alive = false
		player_died.emit()
		print("[Player] Player was defeated!")

func reset_player(spawn_pos: Vector2) -> void:
	global_position = spawn_pos
	current_health = max_health
	is_alive = true
	attack_timer = 0.0
	velocity = Vector2.ZERO
	if hp_bar:
		hp_bar.value = current_health
	if visual and visual.has_method("set_facing"):
		visual.set_facing(Vector2.RIGHT)
	health_changed.emit(current_health, max_health)
