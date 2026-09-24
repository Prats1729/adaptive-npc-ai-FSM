extends Node2D

func _unhandled_input(event: InputEvent) -> void:
	# Reset the game if the 'R' key is pressed
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		get_tree().reload_current_scene()
