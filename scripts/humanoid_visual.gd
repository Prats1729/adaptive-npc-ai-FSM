extends Node2D

# ==============================================================================
# PROCEDURAL 2D HUMANOID RENDERER
# ------------------------------------------------------------------------------
# Renders a crisp, resolution-independent top-down humanoid character with:
# - Animated walking bob and footstep kinematics
# - Directional head, eyes, and shoulders aligned with facing angle
# - Weapon hand with dynamic attack swing animations
# - State color modulation and visual damage flashes
# ==============================================================================

@export var is_enemy: bool = false
@export var base_color: Color = Color(0.2, 0.55, 0.95) # Hero Blue for player, Crimson for enemy
@export var skin_color: Color = Color(0.96, 0.80, 0.68)
@export var armor_color: Color = Color(0.25, 0.28, 0.35)
@export var outline_color: Color = Color(0.08, 0.08, 0.12)

var facing_direction: Vector2 = Vector2.RIGHT
var facing_angle: float = 0.0
var walk_cycle: float = 0.0
var is_moving: bool = false

# Attack animation
var is_attacking: bool = false
var attack_progress: float = 0.0
var attack_duration: float = 0.25

# Visual tint & damage flash
var state_tint: Color = Color.WHITE
var damage_flash_timer: float = 0.0

func _ready() -> void:
	if is_enemy:
		base_color = Color(0.9, 0.3, 0.3)
		armor_color = Color(0.35, 0.18, 0.22)
	queue_redraw()

func _process(delta: float) -> void:
	var needs_redraw = false
	
	# Walk cycle animation
	if is_moving:
		walk_cycle += delta * 12.0
		needs_redraw = true
	else:
		if walk_cycle != 0.0:
			walk_cycle = lerp(walk_cycle, 0.0, delta * 10.0)
			needs_redraw = true
	
	# Attack swing animation
	if is_attacking:
		attack_progress += delta / attack_duration
		needs_redraw = true
		if attack_progress >= 1.0:
			is_attacking = false
			attack_progress = 0.0
	
	# Damage flash timer
	if damage_flash_timer > 0.0:
		damage_flash_timer -= delta
		needs_redraw = true
	
	if needs_redraw:
		queue_redraw()

func set_facing(dir: Vector2) -> void:
	if dir.length_squared() > 0.01:
		facing_direction = dir.normalized()
		var target_angle = facing_direction.angle()
		facing_angle = lerp_angle(facing_angle, target_angle, 0.25)
		is_moving = true
	else:
		is_moving = false
	queue_redraw()

func trigger_attack_anim(duration: float = 0.22) -> void:
	is_attacking = true
	attack_duration = duration
	attack_progress = 0.0
	queue_redraw()

func trigger_damage_flash(duration: float = 0.16) -> void:
	damage_flash_timer = duration
	queue_redraw()

func set_state_tint(tint: Color) -> void:
	state_tint = tint
	queue_redraw()

func _draw() -> void:
	var forward = Vector2.RIGHT.rotated(facing_angle)
	var right = Vector2.DOWN.rotated(facing_angle)
	
	# 1. Drop Shadow
	draw_circle(Vector2(0, 10), 16.0, Color(0.0, 0.0, 0.0, 0.35))
	
	# Determine effective colors with state tint and damage flash
	var effective_base = base_color * state_tint
	var effective_armor = armor_color * state_tint
	var effective_skin = skin_color
	
	if damage_flash_timer > 0.0:
		effective_base = Color(1.8, 1.8, 1.8, 1.0)
		effective_armor = Color(1.8, 1.8, 1.8, 1.0)
		effective_skin = Color(1.8, 1.8, 1.8, 1.0)
	
	# 2. Feet (Step kinematics)
	var foot_offset_l = sin(walk_cycle) * 7.0
	var foot_offset_r = -sin(walk_cycle) * 7.0
	var foot_l = -right * 7.0 + forward * (foot_offset_l - 2.0)
	var foot_r = right * 7.0 + forward * (foot_offset_r - 2.0)
	
	# Draw feet shoes
	draw_circle(foot_l, 4.5, outline_color)
	draw_circle(foot_l, 3.5, effective_armor.darkened(0.2))
	draw_circle(foot_r, 4.5, outline_color)
	draw_circle(foot_r, 3.5, effective_armor.darkened(0.2))
	
	# 3. Torso & Shoulders (Capsule/Trapezoid)
	var shoulder_l = -right * 13.0 - forward * 2.0
	var shoulder_r = right * 13.0 - forward * 2.0
	var chest_front = forward * 6.0
	var back_point = -forward * 8.0
	
	var body_outline_pts = PackedVector2Array([
		shoulder_l - right * 1.5,
		chest_front - right * 6.0,
		chest_front + right * 6.0,
		shoulder_r + right * 1.5,
		back_point + right * 8.0,
		back_point - right * 8.0
	])
	draw_colored_polygon(body_outline_pts, outline_color)
	
	var body_inner_pts = PackedVector2Array([
		shoulder_l,
		chest_front - right * 5.0,
		chest_front + right * 5.0,
		shoulder_r,
		back_point + right * 7.0,
		back_point - right * 7.0
	])
	draw_colored_polygon(body_inner_pts, effective_armor)
	
	# Torso highlight emblem
	draw_circle(forward * 1.0, 5.0, effective_base)
	draw_circle(forward * 1.0, 3.0, outline_color.lightened(0.2))
	
	# 4. Attack Animation offsets
	var swing_angle = 0.0
	var weapon_reach = 0.0
	if is_attacking:
		var t = attack_progress
		# Swing arc curve (thrust forward and swing across)
		weapon_reach = sin(t * PI) * 16.0
		swing_angle = (t - 0.5) * 1.6
	
	# 5. Hands & Weapon
	# Left Hand (Off-hand / Guard)
	var hand_l_pos = shoulder_l + forward * 8.0 - right * 2.0
	draw_circle(hand_l_pos, 4.5, outline_color)
	draw_circle(hand_l_pos, 3.5, effective_skin)
	
	# Right Hand (Main weapon hand)
	var weapon_arm_dir = (forward + right * 0.4).rotated(swing_angle).normalized()
	var hand_r_pos = shoulder_r + weapon_arm_dir * (10.0 + weapon_reach)
	draw_circle(hand_r_pos, 4.5, outline_color)
	draw_circle(hand_r_pos, 3.5, effective_skin)
	
	# Draw Weapon (Sword / Dagger)
	var weapon_tip = hand_r_pos + weapon_arm_dir * (14.0 if is_enemy else 18.0)
	var weapon_hilt_l = hand_r_pos - weapon_arm_dir.orthogonal() * 4.0
	var weapon_hilt_r = hand_r_pos + weapon_arm_dir.orthogonal() * 4.0
	
	# Blade outline
	var blade_pts = PackedVector2Array([hand_r_pos, weapon_hilt_l, weapon_tip, weapon_hilt_r])
	draw_colored_polygon(blade_pts, outline_color)
	# Blade metal
	var blade_color = Color(0.9, 0.95, 1.0) if not is_enemy else effective_base.lightened(0.3)
	var blade_inner_pts = PackedVector2Array([hand_r_pos + weapon_arm_dir * 2.0, weapon_hilt_l * 0.8 + weapon_tip * 0.2, weapon_tip - weapon_arm_dir * 1.5, weapon_hilt_r * 0.8 + weapon_tip * 0.2])
	draw_colored_polygon(blade_inner_pts, blade_color)
	
	# Attack Slash Effect Arc
	if is_attacking and attack_progress > 0.15 and attack_progress < 0.85:
		var slash_center = forward * 14.0
		var slash_color = effective_base
		slash_color.a = sin(attack_progress * PI) * 0.7
		draw_arc(slash_center, 24.0, facing_angle - 0.9, facing_angle + 0.9, 12, slash_color, 4.0, true)
	
	# 6. Head & Helmet (Rendered on top of torso)
	var head_pos = forward * 1.0
	var head_radius = 9.5
	
	# Head outline
	draw_circle(head_pos, head_radius + 1.2, outline_color)
	# Helmet / Hair
	draw_circle(head_pos, head_radius, effective_base.darkened(0.15))
	
	# Face / Visor (Facing forward)
	var face_pos = head_pos + forward * 3.5
	if is_enemy:
		# Sleek glowing visor slit for rogue/enemy
		var visor_l = face_pos - right * 5.0
		var visor_r = face_pos + right * 5.0
		draw_line(visor_l, visor_r, outline_color, 4.0)
		draw_line(visor_l + forward * 0.5, visor_r + forward * 0.5, state_tint.lightened(0.5), 2.5)
	else:
		# Knight helmet visor / eyes for player
		var visor_l = face_pos - right * 4.5
		var visor_r = face_pos + right * 4.5
		draw_line(visor_l, visor_r, outline_color, 3.5)
		draw_line(visor_l + forward * 0.5, visor_r + forward * 0.5, Color(0.9, 0.95, 1.0), 2.0)
		# Helmet crest / plume
		draw_line(head_pos - forward * 6.0, head_pos + forward * 3.0, effective_base.lightened(0.3), 3.0)
