extends CharacterBody2D

const SPEED = 300.0

func _physics_process(_delta: float) -> void:
	# Get input from the arrow keys
	var input_dir = Vector2(
		Input.get_axis("ui_left", "ui_right"),
		Input.get_axis("ui_up", "ui_down")
	)
	
	# Normalize to prevent moving faster diagonally
	var direction = input_dir.normalized()
	
	# Apply velocity
	if direction:
		velocity = direction * SPEED
	else:
		velocity = velocity.move_toward(Vector2.ZERO, SPEED)
	
	# Move the character and handle wall collisions automatically
	move_and_slide()
