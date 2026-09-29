extends CharacterBody2D

# ==============================================================================
# ENEMY NPC CONTROLLER
# ------------------------------------------------------------------------------
# Represents the physical enemy entity in the 2D arena.
# Controls movement, orientation, attack swings, and state visual tinting
# on the procedural 2D humanoid visual component.
# ==============================================================================

signal health_changed(current_health: int, max_health: int)
signal enemy_died()

@export var max_health: int = 200
@export var base_speed: float = 130.0
@export var flee_speed: float = 175.0

var current_health: int = 200
var player: Node2D = null
var spawn_position: Vector2 = Vector2.ZERO

@onready var visual: Node2D = $HumanoidVisual if has_node("HumanoidVisual") else null
@onready var hp_bar: ProgressBar = $ProgressBar if has_node("ProgressBar") else null
@onready var state_label: Label = $StateLabel if has_node("StateLabel") else null
@onready var fsm: Node = $EnemyFSM if has_node("EnemyFSM") else ($Node if has_node("Node") else null)

func _ready() -> void:
	spawn_position = global_position
	current_health = max_health
	
	if hp_bar:
		hp_bar.max_value = max_health
		hp_bar.value = current_health
	
	find_player_reference()
	if visual and visual.has_method("set_facing"):
		visual.set_facing(Vector2.LEFT)
	
	health_changed.emit(current_health, max_health)

func find_player_reference() -> void:
	if not player or not is_instance_valid(player):
		player = get_parent().get_node_or_null("Player")
		if not player:
			player = get_tree().root.find_child("Player", true, false)

func move_towards_point(target_pos: Vector2, custom_speed: float = 0.0) -> void:
	var speed = custom_speed if custom_speed > 0.0 else base_speed
	var direction = global_position.direction_to(target_pos)
	
	if visual and visual.has_method("set_facing"):
		visual.set_facing(direction)
	
	velocity = direction * speed
	move_and_slide()

func stop_moving(face_target: Vector2 = Vector2.ZERO) -> void:
	velocity = Vector2.ZERO
	if face_target != Vector2.ZERO and visual and visual.has_method("set_facing"):
		var look_dir = global_position.direction_to(face_target)
		visual.set_facing(look_dir)
		visual.is_moving = false
	elif visual and visual.has_method("set_facing"):
		visual.is_moving = false
	move_and_slide()

func trigger_attack_visual() -> void:
	if visual and visual.has_method("trigger_attack_anim"):
		visual.trigger_attack_anim(0.3)

func take_damage(amount: int) -> void:
	if current_health <= 0:
		return
	
	current_health = max(0, current_health - amount)
	if hp_bar:
		hp_bar.value = current_health
	
	health_changed.emit(current_health, max_health)
	
	# Hit flash effect on humanoid visual
	if visual and visual.has_method("trigger_damage_flash"):
		visual.trigger_damage_flash(0.18)
	
	if current_health <= 0:
		enemy_died.emit()
		print("[EnemyNPC] Enemy defeated!")

func heal(amount: int) -> void:
	if current_health <= 0 or current_health >= max_health:
		return
	current_health = min(max_health, current_health + amount)
	if hp_bar:
		hp_bar.value = current_health
	health_changed.emit(current_health, max_health)

func update_visual_state(state_name: String, state_color: Color, _reason: String = "") -> void:
	if visual and visual.has_method("set_state_tint"):
		visual.set_state_tint(state_color)
	
	if state_label:
		state_label.text = "[ " + state_name + " ]"
		state_label.modulate = state_color

func reset_enemy(spawn_pos: Vector2) -> void:
	global_position = spawn_pos
	spawn_position = spawn_pos
	current_health = max_health
	velocity = Vector2.ZERO
	if hp_bar:
		hp_bar.value = current_health
	if visual and visual.has_method("set_facing"):
		visual.set_facing(Vector2.LEFT)
	health_changed.emit(current_health, max_health)
	find_player_reference()
