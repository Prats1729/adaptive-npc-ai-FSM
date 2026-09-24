extends CharacterBody2D

@export var max_health: int = 100
var current_health: int = 100

const SPEED = 120.0

# We will need to know where the player is to make decisions
var player: Node2D

func _ready() -> void:
	current_health = max_health
	# Find the player in the arena (assuming it's named 'Player')
	player = get_parent().get_node_or_null("Player")
	
	var hp_bar = get_node_or_null("ProgressBar")
	if hp_bar:
		hp_bar.max_value = max_health
		hp_bar.value = current_health

# Helper function for the AI to move toward a specific point
func move_towards_point(target_position: Vector2) -> void:
	var direction = global_position.direction_to(target_position)
	
	var sprite = get_node_or_null("Sprite2D")
	if sprite:
		if direction.x < 0:
			sprite.flip_h = true
		elif direction.x > 0:
			sprite.flip_h = false
			
	velocity = direction * SPEED
	move_and_slide()

# Helper function for the AI to stop
func stop_moving() -> void:
	velocity = Vector2.ZERO
	move_and_slide()

func take_damage(amount: int) -> void:
	current_health -= amount
	print("Enemy took damage! Health: ", current_health)
	
	var hp_bar = get_node_or_null("ProgressBar")
	if hp_bar:
		hp_bar.value = current_health
