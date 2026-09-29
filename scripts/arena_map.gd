extends Node2D

# ==============================================================================
# PROCEDURAL ARENA MAP RENDERER
# ------------------------------------------------------------------------------
# Renders a sleek, clean 2D top-down combat arena with:
# - Stone floor tiles and subtle geometric combat ring
# - Player & NPC spawn pads
# - Perimeter stone walls with depth and beveling
# - Obstacle pillars with drop shadows
# ==============================================================================

@export var show_perception_zones: bool = false
@export var arena_rect: Rect2 = Rect2(30, 70, 1092, 510)

var enemy_npc: Node2D = null
var enemy_fsm: Node = null

# Obstacle pillar centers
const PILLAR_POSITIONS = [
	Vector2(440, 230),
	Vector2(712, 230),
	Vector2(440, 430),
	Vector2(712, 430)
]
const PILLAR_RADIUS = 24.0

func _ready() -> void:
	enemy_npc = get_parent().get_node_or_null("EnemyNPC")
	if enemy_npc:
		enemy_fsm = enemy_npc.get_node_or_null("EnemyFSM")
	queue_redraw()

func _draw() -> void:
	# 1. Base Arena Floor
	draw_rect(arena_rect, Color(0.12, 0.13, 0.17, 1.0), true)
	
	# Subtle floor grid pattern (40px tiles)
	var grid_color = Color(0.16, 0.18, 0.23, 0.5)
	var x = arena_rect.position.x
	while x <= arena_rect.end.x:
		draw_line(Vector2(x, arena_rect.position.y), Vector2(x, arena_rect.end.y), grid_color, 1.0)
		x += 40.0
		
	var y = arena_rect.position.y
	while y <= arena_rect.end.y:
		draw_line(Vector2(arena_rect.position.x, y), Vector2(arena_rect.end.x, y), grid_color, 1.0)
		y += 40.0
	
	# 2. Central Arena Crest / Combat Ring
	var center = arena_rect.get_center()
	draw_circle(center, 95.0, Color(0.18, 0.20, 0.27, 0.35))
	draw_arc(center, 95.0, 0, TAU, 48, Color(0.28, 0.32, 0.42, 0.8), 2.0, true)
	draw_arc(center, 42.0, 0, TAU, 32, Color(0.28, 0.32, 0.42, 0.5), 1.5, true)
	draw_line(center - Vector2(20, 0), center + Vector2(20, 0), Color(0.35, 0.4, 0.52, 0.6), 2.0)
	draw_line(center - Vector2(0, 20), center + Vector2(0, 20), Color(0.35, 0.4, 0.52, 0.6), 2.0)
	
	# 3. Spawn Pads
	# Player Spawn (Left)
	var p_spawn = Vector2(260, 330)
	draw_circle(p_spawn, 28.0, Color(0.15, 0.35, 0.65, 0.25))
	draw_arc(p_spawn, 28.0, 0, TAU, 24, Color(0.3, 0.6, 1.0, 0.6), 1.5, true)
	
	# Enemy Spawn (Right)
	var e_spawn = Vector2(890, 330)
	draw_circle(e_spawn, 28.0, Color(0.65, 0.25, 0.25, 0.25))
	draw_arc(e_spawn, 28.0, 0, TAU, 24, Color(1.0, 0.4, 0.4, 0.6), 1.5, true)
	
	# 4. Obstacle Pillars
	for pillar_pos in PILLAR_POSITIONS:
		# Drop shadow
		draw_circle(pillar_pos + Vector2(0, 8), PILLAR_RADIUS + 2.0, Color(0.0, 0.0, 0.0, 0.4))
		# Outer stone outline
		draw_circle(pillar_pos, PILLAR_RADIUS + 2.0, Color(0.07, 0.08, 0.11))
		# Pillar body
		draw_circle(pillar_pos, PILLAR_RADIUS, Color(0.22, 0.25, 0.32))
		# Inner stone cap highlight
		draw_circle(pillar_pos - Vector2(2, 2), PILLAR_RADIUS - 6.0, Color(0.29, 0.33, 0.42))
		draw_arc(pillar_pos, PILLAR_RADIUS - 6.0, 0, TAU, 24, Color(0.38, 0.44, 0.55), 1.5, true)
	
	# 5. Perimeter Wall Border Styling
	var wall_border_color = Color(0.35, 0.40, 0.52, 1.0)
	var wall_shadow_color = Color(0.05, 0.06, 0.08, 0.8)
	
	# Inner shadow border
	draw_rect(arena_rect, wall_shadow_color, false, 4.0)
	# Beveled outer rim
	draw_rect(Rect2(arena_rect.position - Vector2(2, 2), arena_rect.size + Vector2(4, 4)), wall_border_color, false, 2.5)
