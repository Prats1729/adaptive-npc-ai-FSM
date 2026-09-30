extends Node

# ==============================================================================
# DYNAMIC SCRIPTING ADAPTIVE LOGIC CONTROLLER (Spronck et al., 2006)
# ------------------------------------------------------------------------------
# Re-architected Adaptive Decision-Making Engine based on Pieter Spronck's
# seminal "Dynamic Scripting" framework for game AI.
#
# Core Principles:
# 1. FAIRNESS: Zero stat tampering. NPC HP, damage, attack range, and base cooldown
#    remain strictly equal to the player at all times.
# 2. DYNAMIC RULEBASE: The FSM transition policies and combat maneuvers are
#    governed by a pool of candidate rules, each with a persistent fitness weight.
# 3. EMPIRICAL ADAPTATION: At the end of each encounter, an explainable fitness
#    function updates rule weights:
#      ΔW = (Hits Landed - Hits Taken) + (Win Bonus)
#    Rules that succeed gain weight; self-destructive rules (e.g. retreating
#    from a faster opponent) are naturally penalized and eliminated.
# 4. EXPLAINABILITY: Every selection, weight shift, and tactical decision is
#    logged with explicit reasoning for academic defense and dashboard visualization.
# ==============================================================================

signal adaptation_updated(aggression_score: float, aggression_tier: String, det_range: float, flee_ratio: float)
signal rule_weight_changed(rule_name: String, old_weight: float, new_weight: float)

@export var is_adaptive_enabled: bool = true

# --- DYNAMIC SCRIPTING RULE DEFINITIONS ---
enum RuleId {
	STAND_AND_TRADE = 0, # Stand ground, maximize melee DPS against rushers
	WHIFF_PUNISH    = 1, # Space at 48px, bait early swings, strike during recovery
	TACTICAL_KITE   = 2, # Circle laterally, control arena center, standard retreat
	PRESSURE_HUNT   = 3  # Leading intercept vectors, cut off evasive kiters
}

const RULE_NAMES = {
	RuleId.STAND_AND_TRADE: "Stand & Trade (DPS Priority)",
	RuleId.WHIFF_PUNISH:    "Whiff & Punish (Spacing Bait)",
	RuleId.TACTICAL_KITE:   "Tactical Kite (Center Control)",
	RuleId.PRESSURE_HUNT:   "Pressure Hunt (Intercept Cut-off)"
}

# Rule Weights (Uniform 100.0 baseline, sum conserved at 400.0)
const DEFAULT_WEIGHT: float = 100.0
const MIN_WEIGHT: float = 15.0
const MAX_WEIGHT: float = 285.0
const TOTAL_WEIGHT_SUM: float = 400.0

var rule_weights: Array[float] = [100.0, 100.0, 100.0, 100.0]
var active_rule_id: int = RuleId.STAND_AND_TRADE

# Baseline FSM Thresholds (used when is_adaptive_enabled == false)
const BASE_DETECTION_RANGE: float = 200.0
const BASE_FLEE_THRESHOLD: float = 0.25
const BASE_ATTACK_COOLDOWN: float = 0.80

var fsm: Node = null
var enemy: CharacterBody2D = null

# Live Sensory Telemetry
var player_aggression_score: float = 0.0 # 0.0 to 1.0
var time_since_last_player_attack: float = 5.0
var player_in_cooldown: bool = false
var passive_distance_timer: float = 0.0
var rolling_win_rate: float = 0.5

var current_adaptive_explanation: String = "Monitoring player behavior..."

func _ready() -> void:
	fsm = get_parent()
	if fsm and fsm.get_parent() is CharacterBody2D:
		enemy = fsm.get_parent() as CharacterBody2D

func _physics_process(delta: float) -> void:
	if not enemy or not fsm:
		return
	
	time_since_last_player_attack += delta
	
	# Smoothly decay aggression telemetry
	player_aggression_score = max(0.0, player_aggression_score - delta * 0.15)
	
	# Track player's weapon recovery window:
	# Player attack cooldown is 0.80s. The recovery window is the first 0.60s.
	player_in_cooldown = (time_since_last_player_attack < 0.60 and time_since_last_player_attack > 0.05)
	
	# Track target passivity (distance > 200px)
	if enemy.player and is_instance_valid(enemy.player):
		var distance = enemy.global_position.distance_to(enemy.player.global_position)
		if distance > BASE_DETECTION_RANGE:
			passive_distance_timer += delta
		else:
			passive_distance_timer = max(0.0, passive_distance_timer - delta * 2.0)
	
	if not is_adaptive_enabled:
		fsm.detection_range = BASE_DETECTION_RANGE
		fsm.flee_health_ratio = BASE_FLEE_THRESHOLD
		fsm.attack_cooldown_time = BASE_ATTACK_COOLDOWN
		current_adaptive_explanation = "Basic FSM: Operating with fixed baseline thresholds."
		return
	
	# Apply active dynamic scripting rule configuration
	apply_active_rule_parameters()
	
	var aggression_tier = get_aggression_tier()
	adaptation_updated.emit(player_aggression_score, aggression_tier, fsm.detection_range, fsm.flee_health_ratio)

# ==============================================================================
# DYNAMIC SCRIPTING: RULE SELECTION & EXECUTION
# ==============================================================================

func select_rule_for_episode() -> int:
	if not is_adaptive_enabled:
		active_rule_id = RuleId.TACTICAL_KITE
		return active_rule_id
	
	# Epsilon-Greedy Exploitation / Exploration (Spronck et al.)
	# 80% exploitation: select the rule with the highest accumulated fitness weight
	# 20% exploration: roulette wheel selection across all candidate rules
	var total_w = 0.0
	for w in rule_weights:
		total_w += w
	
	if randf() > 0.20:
		# Greedy exploitation: find index of maximum weight
		var best_idx = 0
		var best_w = -1.0
		for i in range(rule_weights.size()):
			if rule_weights[i] > best_w:
				best_w = rule_weights[i]
				best_idx = i
		active_rule_id = best_idx
	else:
		# Roulette wheel exploration
		var roll = randf() * total_w
		var running = 0.0
		for i in range(rule_weights.size()):
			running += rule_weights[i]
			if roll <= running:
				active_rule_id = i
				break
	
	apply_active_rule_parameters()
	print("[Dynamic Scripting] Selected Policy for Episode: '%s' (Weight: %.1f/%.1f)" % [
		get_rule_name(active_rule_id), rule_weights[active_rule_id], total_w
	])
	return active_rule_id

func apply_active_rule_parameters() -> void:
	if not fsm:
		return
	
	match active_rule_id:
		RuleId.STAND_AND_TRADE:
			# Stand ground against rushers: no retreat, trade blows on cooldown
			fsm.detection_range = BASE_DETECTION_RANGE
			fsm.flee_health_ratio = 0.0 # Retreat disabled: running from faster pursuer is fatal
			current_adaptive_explanation = "Spronck Policy: %s [W: %.0f] | Flee: 0%% (Stand Ground) | Cadence: Max" % [
				get_rule_name(active_rule_id), rule_weights[active_rule_id]
			]
			
		RuleId.WHIFF_PUNISH:
			# Exploit opponent's early swing tolerance: space at 48px, strike during recovery
			fsm.detection_range = BASE_DETECTION_RANGE
			fsm.flee_health_ratio = 0.0
			var status = "PUNISHING" if player_in_cooldown else "BAITING"
			current_adaptive_explanation = "Spronck Policy: %s [W: %.0f] | Status: %s | Distance: Spacing Ring" % [
				get_rule_name(active_rule_id), rule_weights[active_rule_id], status
			]
			
		RuleId.TACTICAL_KITE:
			# Standard retreat and arena center control against passive opponents
			fsm.detection_range = 220.0
			fsm.flee_health_ratio = BASE_FLEE_THRESHOLD
			current_adaptive_explanation = "Spronck Policy: %s [W: %.0f] | Flee: %.0f%% | Center Control" % [
				get_rule_name(active_rule_id), rule_weights[active_rule_id], fsm.flee_health_ratio * 100.0
			]
			
		RuleId.PRESSURE_HUNT:
			# Expanded detection & intercept vectors against evasive kiters
			fsm.detection_range = 260.0
			fsm.flee_health_ratio = 0.15
			current_adaptive_explanation = "Spronck Policy: %s [W: %.0f] | Range: 260px | Trapping Escape Vectors" % [
				get_rule_name(active_rule_id), rule_weights[active_rule_id]
			]

# ==============================================================================
# DYNAMIC SCRIPTING: FITNESS EVALUATION & WEIGHT ADAPTATION
# ==============================================================================

func evaluate_episode_result(npc_hits: int, player_hits: int, npc_won: bool) -> void:
	if not is_adaptive_enabled:
		return
	
	# Spronck Fitness Formula:
	# Hits landed vs taken gives combat efficiency; win/loss adds macro evaluation.
	var hit_delta = npc_hits - player_hits
	var outcome_bonus = 18.0 if npc_won else -18.0
	var fitness = (hit_delta * 2.2) + outcome_bonus
	
	# Clamp single-episode delta to prevent over-fitting
	var delta_w = clamp(fitness * 1.4, -38.0, 38.0)
	
	_update_rule_weight(active_rule_id, delta_w)

func _update_rule_weight(rule_idx: int, delta_w: float) -> void:
	var old_w = rule_weights[rule_idx]
	var new_w = clamp(old_w + delta_w, MIN_WEIGHT, MAX_WEIGHT)
	var actual_delta = new_w - old_w
	rule_weights[rule_idx] = new_w
	
	# Spronck Weight Redistribution: Conserve total sum so weights remain bounded
	var other_sum = 0.0
	for i in range(rule_weights.size()):
		if i != rule_idx:
			other_sum += rule_weights[i]
	
	if other_sum > 0.001:
		for i in range(rule_weights.size()):
			if i != rule_idx:
				var share = (rule_weights[i] / other_sum) * actual_delta
				rule_weights[i] = clamp(rule_weights[i] - share, MIN_WEIGHT, MAX_WEIGHT)
	
	rule_weight_changed.emit(get_rule_name(rule_idx), old_w, rule_weights[rule_idx])
	
	print("[Spronck Adaptation] Policy '%s': %.1f -> %.1f (%+.1f). Current Weights: [Stand:%.0f, Punish:%.0f, Kite:%.0f, Hunt:%.0f]" % [
		get_rule_name(rule_idx), old_w, rule_weights[rule_idx], actual_delta,
		rule_weights[0], rule_weights[1], rule_weights[2], rule_weights[3]
	])

func get_rule_name(rule_id: int) -> String:
	return RULE_NAMES.get(rule_id, "Unknown Policy")

func get_active_rule_name() -> String:
	return get_rule_name(active_rule_id)

func get_active_rule_weight() -> float:
	if active_rule_id >= 0 and active_rule_id < rule_weights.size():
		return rule_weights[active_rule_id]
	return DEFAULT_WEIGHT

# Called when starting a new opponent policy suite
func reset_weights_for_new_policy() -> void:
	rule_weights = [100.0, 100.0, 100.0, 100.0]
	active_rule_id = RuleId.STAND_AND_TRADE
	player_aggression_score = 0.0
	time_since_last_player_attack = 5.0
	passive_distance_timer = 0.0
	player_in_cooldown = false
	print("[Dynamic Scripting] Rule weights reset to uniform baseline (100.0) for new opponent evaluation.")

# Telemetry compatibility functions
func record_player_attack() -> void:
	time_since_last_player_attack = 0.0
	player_in_cooldown = true
	player_aggression_score = min(1.0, player_aggression_score + 0.35)

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
	# Called on single round resets; preserves weights across benchmark trials
	player_aggression_score = 0.0
	time_since_last_player_attack = 5.0
	passive_distance_timer = 0.0
	player_in_cooldown = false
	if not is_adaptive_enabled and fsm:
		fsm.detection_range = BASE_DETECTION_RANGE
		fsm.flee_health_ratio = BASE_FLEE_THRESHOLD
		fsm.attack_cooldown_time = BASE_ATTACK_COOLDOWN
