extends CharacterBody2D

const SPEED = 300.0

var max_health: int = 100
var current_health: int = 100

func _ready() -> void:
	var hp_bar = get_node_or_null("ProgressBar")
	if hp_bar:
		hp_bar.max_value = max_health
		hp_bar.value = current_health

func take_damage(amount: int) -> void:
	current_health -= amount
	print("Player took damage! Health: ", current_health)
	var hp_bar = get_node_or_null("ProgressBar")
	if hp_bar:
		hp_bar.value = current_health

func _physics_process(_delta: float) -> void:
	# Attack the enemy if Spacebar is pressed
	if Input.is_action_just_pressed("ui_accept"):
		var enemy = get_parent().get_node_or_null("EnemyNPC")
		if enemy and global_position.distance_to(enemy.global_position) <= 60.0:
			enemy.take_damage(20)

	# Get input from the arrow keys
	var input_dir = Vector2(
		Input.get_axis("ui_left", "ui_right"),
		Input.get_axis("ui_up", "ui_down")
	)
	
	# Normalize to prevent moving faster diagonally
	var direction = input_dir.normalized()
	
	var sprite = get_node_or_null("Sprite2D")
	if sprite:
		if direction.x < 0:
			sprite.flip_h = true
		elif direction.x > 0:
			sprite.flip_h = false
	
	# Apply velocity
	if direction:
		velocity = direction * SPEED
	else:
		velocity = velocity.move_toward(Vector2.ZERO, SPEED)
	
	# Move the character and handle wall collisions automatically
	move_and_slide()
