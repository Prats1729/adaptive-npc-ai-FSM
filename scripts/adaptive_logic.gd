extends Node

# ==============================================================================
# ADAPTIVE RULE-BASED LOGIC CONTROLLER
# ------------------------------------------------------------------------------
# Analyzes real-time player behavior to dynamically modulate FSM decision
# thresholds (Detection Range and Flee Health Threshold).
#
# Adaptive Rules:
# 1. High Player Aggression (frequent attacks) -> Increase Flee Threshold (30% -> 45%)
# 2. Passive / Distant Player -> Expand Detection Range (220px -> 285px)
# ==============================================================================

signal adaptation_updated(aggression_score: float, aggression_tier: String, det_range: float, flee_ratio: float)

@export var is_adaptive_enabled: bool = true

# Baseline FSM Thresholds
const BASE_DETECTION_RANGE: float = 220.0
const BASE_FLEE_THRESHOLD: float = 0.30
const MAX_ADAPTIVE_DETECTION: float = 285.0
const MAX_ADAPTIVE_FLEE_THRESHOLD: float = 0.45

var fsm: Node = null
var enemy: CharacterBody2D = null

# Player Behavior Telemetry
var player_aggression_score: float = 0.0 # Range: 0.0 (Passive) to 1.0 (Hyper-aggressive)
var time_since_last_player_attack: float = 5.0
var passive_distance_timer: float = 0.0

func _ready() -> void:
	fsm = get_parent()
	if fsm and fsm.get_parent() is CharacterBody2D:
		enemy = fsm.get_parent() as CharacterBody2D

func _physics_process(delta: float) -> void:
	if not enemy or not fsm:
		return
	
	time_since_last_player_attack += delta
	
	# Smoothly decay aggression score over time when player isn't attacking
	player_aggression_score = max(0.0, player_aggression_score - delta * 0.25)
	
	# Check distance to player for passivity tracking
	if enemy.player and is_instance_valid(enemy.player):
		var distance = enemy.global_position.distance_to(enemy.player.global_position)
		if distance > BASE_DETECTION_RANGE:
			passive_distance_timer += delta
		else:
			passive_distance_timer = max(0.0, passive_distance_timer - delta * 2.0)
	
	if not is_adaptive_enabled:
		# Enforce static baseline values in Basic FSM mode
		fsm.detection_range = BASE_DETECTION_RANGE
		fsm.flee_health_ratio = BASE_FLEE_THRESHOLD
		return
	
	# --- ADAPTIVE THRESHOLD MODULATION ---
	
	# Rule 1: High Aggression -> Increase retreat threshold (flee earlier to survive)
	if player_aggression_score > 0.5:
		var flee_boost = lerp(BASE_FLEE_THRESHOLD, MAX_ADAPTIVE_FLEE_THRESHOLD, (player_aggression_score - 0.5) * 2.0)
		fsm.flee_health_ratio = lerp(fsm.flee_health_ratio, flee_boost, delta * 2.0)
	else:
		fsm.flee_health_ratio = lerp(fsm.flee_health_ratio, BASE_FLEE_THRESHOLD, delta * 1.5)
	
	# Rule 2: Passive / Distant Player -> Expand detection range (seek out passive player)
	if passive_distance_timer > 2.5:
		var target_det = min(MAX_ADAPTIVE_DETECTION, BASE_DETECTION_RANGE + (passive_distance_timer - 2.5) * 15.0)
		fsm.detection_range = lerp(fsm.detection_range, target_det, delta * 1.5)
	else:
		fsm.detection_range = lerp(fsm.detection_range, BASE_DETECTION_RANGE, delta * 2.0)
	
	var aggression_tier = get_aggression_tier()
	adaptation_updated.emit(player_aggression_score, aggression_tier, fsm.detection_range, fsm.flee_health_ratio)

# Called whenever the player swings or attacks
func record_player_attack() -> void:
	time_since_last_player_attack = 0.0
	# Spike aggression score (+0.35 per strike, capped at 1.0)
	player_aggression_score = min(1.0, player_aggression_score + 0.35)

func get_aggression_tier() -> String:
	if player_aggression_score > 0.65:
		return "HIGH"
	elif player_aggression_score > 0.25:
		return "MEDIUM"
	else:
		return "LOW (PASSIVE)"

func toggle_adaptive_mode() -> bool:
	is_adaptive_enabled = not is_adaptive_enabled
	if not is_adaptive_enabled and fsm:
		fsm.detection_range = BASE_DETECTION_RANGE
		fsm.flee_health_ratio = BASE_FLEE_THRESHOLD
	return is_adaptive_enabled

func reset_adaptive_telemetry() -> void:
	player_aggression_score = 0.0
	time_since_last_player_attack = 5.0
	passive_distance_timer = 0.0
	if fsm:
		fsm.detection_range = BASE_DETECTION_RANGE
		fsm.flee_health_ratio = BASE_FLEE_THRESHOLD
