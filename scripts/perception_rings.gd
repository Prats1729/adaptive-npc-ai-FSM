extends Node2D

# ==============================================================================
# NPC PERCEPTION RINGS RENDERER
# ------------------------------------------------------------------------------
# Draws the real-time sensory perception zones directly centered on the NPC:
# - Outer Ring: Detection Range (Player triggers CHASE upon entering)
# - Inner Ring: Attack Range (NPC executes melee attacks upon entering)
# ==============================================================================

@export var show_detection_ring: bool = true
@export var show_attack_ring: bool = true

var enemy: CharacterBody2D = null
var fsm: Node = null

var detection_radius: float = 220.0
var attack_radius: float = 65.0

func _ready() -> void:
	enemy = get_parent() as CharacterBody2D
	if enemy:
		fsm = enemy.get_node_or_null("EnemyFSM")
		if fsm:
			if "detection_range" in fsm:
				detection_radius = fsm.detection_range
			if "attack_range" in fsm:
				attack_radius = fsm.attack_range
	queue_redraw()

func _process(_delta: float) -> void:
	# Update radii dynamically if FSM changes thresholds
	if fsm:
		if "detection_range" in fsm and fsm.detection_range != detection_radius:
			detection_radius = fsm.detection_range
			queue_redraw()
		if "attack_range" in fsm and fsm.attack_range != attack_radius:
			attack_radius = fsm.attack_range
			queue_redraw()

func _draw() -> void:
	if enemy and enemy.current_health <= 0:
		return
	
	# 1. Outer Detection Range Ring (Golden / Amber)
	if show_detection_ring and detection_radius > 0.0:
		# Soft translucent area fill
		draw_circle(Vector2.ZERO, detection_radius, Color(1.0, 0.85, 0.25, 0.035))
		# Clean perimeter boundary line
		draw_arc(Vector2.ZERO, detection_radius, 0.0, TAU, 64, Color(1.0, 0.85, 0.25, 0.45), 1.5, true)
		# Subtle compass tick marks
		_draw_range_ticks(detection_radius, Color(1.0, 0.85, 0.25, 0.6))
	
	# 2. Inner Attack Range Ring (Crimson Red)
	if show_attack_ring and attack_radius > 0.0:
		# Soft red area fill
		draw_circle(Vector2.ZERO, attack_radius, Color(1.0, 0.25, 0.25, 0.07))
		# Clean perimeter boundary line
		draw_arc(Vector2.ZERO, attack_radius, 0.0, TAU, 36, Color(1.0, 0.3, 0.3, 0.65), 1.5, true)

func _draw_range_ticks(radius: float, color: Color) -> void:
	var tick_len = 5.0
	for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
		var dir = Vector2.RIGHT.rotated(angle)
		var p1 = dir * (radius - tick_len)
		var p2 = dir * (radius + tick_len)
		draw_line(p1, p2, color, 1.5)
