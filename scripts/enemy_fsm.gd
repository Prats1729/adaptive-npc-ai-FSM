extends Node

# The possible states our enemy can be in
enum State {
	PATROL,
	CHASE,
	ATTACK,
	RETREAT,
	DEAD
}

var current_state: State = State.PATROL
var enemy: CharacterBody2D
var state_label: Label
var attack_cooldown: float = 0.0

# Baseline Thresholds (we will make these adaptive later!)
var detection_range: float = 180.0
var attack_range: float = 55.0
var retreat_health_percent: float = 0.25 # 25%

func _ready() -> void:
	enemy = get_parent()
	state_label = enemy.get_node_or_null("StateLabel")
	print("Starting state: PATROL")
	if state_label:
		state_label.text = "PATROL\nReason: Initialized"

func _physics_process(delta: float) -> void:
	if not enemy or not enemy.player:
		return
	
	if attack_cooldown > 0:
		attack_cooldown -= delta
		
	var distance_to_player = enemy.global_position.distance_to(enemy.player.global_position)
	var health_percent = float(enemy.current_health) / float(enemy.max_health)
	
	if enemy.current_health <= 0 and current_state != State.DEAD:
		change_state(State.DEAD, "Health reached 0")
		return
	
	# The Brain: Decide what to do based on the current state
	match current_state:
		State.PATROL:
			enemy.stop_moving() # We will add actual moving between patrol points later
			
			if health_percent < retreat_health_percent:
				change_state(State.RETREAT, "Enemy health dropped below 25%")
			elif distance_to_player <= detection_range:
				change_state(State.CHASE, "Player entered detection range (" + str(round(distance_to_player)) + "px)")
				
		State.CHASE:
			# Move towards the player!
			enemy.move_towards_point(enemy.player.global_position)
			
			if health_percent < retreat_health_percent:
				change_state(State.RETREAT, "Enemy health dropped below 25%")
			elif distance_to_player <= attack_range:
				change_state(State.ATTACK, "Player entered attack range (" + str(round(distance_to_player)) + "px)")
			elif distance_to_player > detection_range:
				change_state(State.PATROL, "Player escaped detection range")
				
		State.ATTACK:
			enemy.stop_moving()
			if attack_cooldown <= 0:
				enemy.player.take_damage(10)
				attack_cooldown = 1.0 # 1 second cooldown
			
			if health_percent < retreat_health_percent:
				change_state(State.RETREAT, "Enemy health dropped below 25%")
			elif distance_to_player > attack_range:
				change_state(State.CHASE, "Player moved outside attack range")
				
		State.RETREAT:
			# Calculate direction away from the player and run!
			var flee_dir = enemy.player.global_position.direction_to(enemy.global_position)
			enemy.move_towards_point(enemy.global_position + flee_dir * 100)
			
			if distance_to_player > detection_range * 1.5:
				change_state(State.PATROL, "Safe distance reached, returning to patrol")
				
		State.DEAD:
			enemy.stop_moving()
			# Do nothing, wait for simulation to reset

# Explainability requirement: Log exactly WHY the AI made a decision
func change_state(new_state: State, reason: String) -> void:
	var old_state_name = State.keys()[current_state]
	var new_state_name = State.keys()[new_state]
	
	print(old_state_name + " -> " + new_state_name + ": " + reason)
	
	current_state = new_state
	
	if state_label:
		state_label.text = new_state_name + "\nReason: " + reason
