extends Node

# ==============================================================================
# ADAPTIVE RULE-BASED LOGIC CONTROLLER
# ------------------------------------------------------------------------------
# Analyzes real-time player behavior to dynamically modulate FSM decision
# thresholds and activate strategic behavioral rules.
#
# DESIGN PRINCIPLE (Spronck et al., 2006):
#   Adaptation changes STRATEGY, not raw power. The NPC's attack damage,
#   HP, and range remain identical to the player's at all times.
#
# Adaptive Rules:
#   1. High Aggression -> Raise flee threshold (flee earlier to avoid trades)
#   2. High Aggression -> Reduce attack cooldown slightly (0.80 -> 0.65s)
#      to exploit timing gaps during player's recovery window
#   3. Passive Player  -> Expand detection range to find distant targets
#   4. Engagement Timing -> Track player attack cadence, flag safe windows
#      for the FSM to sprint into melee during player cooldown
#   5. Hit-and-Run Flag -> Signal FSM to disengage after striking aggressive
#      players, avoiding prolonged DPS trades the NPC would lose
# ==============================================================================

signal adaptation_updated(aggression_score: float, aggression_tier: String, det_range: float, flee_ratio: float)

@export var is_adaptive_enabled: bool = true

# Baseline FSM Thresholds (must match enemy_fsm.gd defaults)
const BASE_DETECTION_RANGE: float = 200.0
const BASE_FLEE_THRESHOLD: float = 0.25
const BASE_ATTACK_COOLDOWN: float = 0.80

# Adaptive Limits (conservative — strategy matters more than numbers)
const MAX_ADAPTIVE_DETECTION: float = 260.0
const MAX_ADAPTIVE_FLEE_THRESHOLD: float = 0.38
const MIN_ADAPTIVE_COOLDOWN: float = 0.65

var fsm: Node = null
var enemy: CharacterBody2D = null

# Player Behavior Telemetry
var player_aggression_score: float = 0.0 # Range: 0.0 (Passive) to 1.0 (Hyper-aggressive)
var time_since_last_player_attack: float = 5.0
var passive_distance_timer: float = 0.0

# Engagement Timing: True when the player just attacked and is in cooldown
var player_in_cooldown: bool = false

var current_adaptive_explanation: String = "Monitoring player behavior..."

func _ready() -> void:
	fsm = get_parent()
	if fsm and fsm.get_parent() is CharacterBody2D:
		enemy = fsm.get_parent() as CharacterBody2D

func _physics_process(delta: float) -> void:
	if not enemy or not fsm:
		return
	
	time_since_last_player_attack += delta
	
	# Smoothly decay aggression score over time when player isn't attacking
	player_aggression_score = max(0.0, player_aggression_score - delta * 0.18)
	
	# Track if player is currently in their attack recovery window
	# Player cooldown is 0.80s; we consider the first 0.55s as the "safe window"
	player_in_cooldown = (time_since_last_player_attack < 0.55 and time_since_last_player_attack > 0.08)
	
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
		fsm.attack_cooldown_time = BASE_ATTACK_COOLDOWN
		current_adaptive_explanation = "Basic FSM: Operating with fixed baseline thresholds."
		return
	
	# --- ADAPTIVE THRESHOLD MODULATION ---
	
	# Rule 1: High Aggression -> Increase retreat threshold (flee earlier to create distance)
	if player_aggression_score > 0.35:
		var flee_boost = lerp(BASE_FLEE_THRESHOLD, MAX_ADAPTIVE_FLEE_THRESHOLD, min(1.0, (player_aggression_score - 0.35) * 1.6))
		fsm.flee_health_ratio = lerp(fsm.flee_health_ratio, flee_boost, delta * 2.5)
	else:
		fsm.flee_health_ratio = lerp(fsm.flee_health_ratio, BASE_FLEE_THRESHOLD, delta * 1.5)
	
	# Rule 2: High Aggression -> Reduce attack cooldown to exploit timing gaps
	# This is the key adaptive DPS advantage: 0.80 -> 0.65s = ~23% faster attacks
	if player_aggression_score > 0.30:
		var cd_boost = lerp(BASE_ATTACK_COOLDOWN, MIN_ADAPTIVE_COOLDOWN, min(1.0, (player_aggression_score - 0.30) * 1.5))
		fsm.attack_cooldown_time = lerp(fsm.attack_cooldown_time, cd_boost, delta * 2.5)
	else:
		fsm.attack_cooldown_time = lerp(fsm.attack_cooldown_time, BASE_ATTACK_COOLDOWN, delta * 1.5)
	
	# Rule 3: Passive / Distant Player -> Expand detection range
	if passive_distance_timer > 2.5:
		var target_det = min(MAX_ADAPTIVE_DETECTION, BASE_DETECTION_RANGE + (passive_distance_timer - 2.5) * 15.0)
		fsm.detection_range = lerp(fsm.detection_range, target_det, delta * 2.0)
	else:
		fsm.detection_range = lerp(fsm.detection_range, BASE_DETECTION_RANGE, delta * 2.0)
	
	# Dynamic explanation synthesis
	if player_aggression_score > 0.5:
		current_adaptive_explanation = "Adaptive: High aggression (%.2f) -> Flee at %.0f%%, Cooldown %.2fs, Hit-and-Run active" % [
			player_aggression_score, fsm.flee_health_ratio * 100.0, fsm.attack_cooldown_time
		]
	elif passive_distance_timer > 3.0 and fsm.detection_range > BASE_DETECTION_RANGE + 3.0:
		current_adaptive_explanation = "Adaptive: Target passive for %.1fs -> Detection expanded to %dpx" % [
			passive_distance_timer, round(fsm.detection_range)
		]
	else:
		current_adaptive_explanation = "Adaptive: Scanning (Aggression: %.2f, Range: %dpx, CD: %.2fs)" % [
			player_aggression_score, round(fsm.detection_range), fsm.attack_cooldown_time
		]
	
	var aggression_tier = get_aggression_tier()
	adaptation_updated.emit(player_aggression_score, aggression_tier, fsm.detection_range, fsm.flee_health_ratio)

# Called whenever the player swings or attacks
func record_player_attack() -> void:
	time_since_last_player_attack = 0.0
	# Spike aggression score (+0.30 per strike, capped at 1.0)
	player_aggression_score = min(1.0, player_aggression_score + 0.30)

func get_aggression_tier() -> String:
	if player_aggression_score > 0.60:
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
		fsm.attack_cooldown_time = BASE_ATTACK_COOLDOWN
	return is_adaptive_enabled

func reset_adaptive_telemetry() -> void:
	player_aggression_score = 0.0
	time_since_last_player_attack = 5.0
	passive_distance_timer = 0.0
	player_in_cooldown = false
	if fsm:
		fsm.detection_range = BASE_DETECTION_RANGE
		fsm.flee_health_ratio = BASE_FLEE_THRESHOLD
		fsm.attack_cooldown_time = BASE_ATTACK_COOLDOWN
