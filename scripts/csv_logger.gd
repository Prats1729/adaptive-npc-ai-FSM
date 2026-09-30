extends Node

# ==============================================================================
# SIMULATION TELEMETRY CSV LOGGER
# ------------------------------------------------------------------------------
# Records empirical experiment data from automated trials into a standardized CSV.
# Provides the primary data source for viva evaluation and statistical graphs.
# ==============================================================================

const CSV_FILE_PATH: String = "user://simulation_results.csv"
const LOCAL_CSV_PATH: String = "res://data/simulation_results.csv"

var is_header_written: bool = false

func _ready() -> void:
	ensure_data_directory()
	initialize_csv_header()

func ensure_data_directory() -> void:
	var dir = DirAccess.open("res://")
	if dir and not dir.dir_exists("res://data"):
		dir.make_dir("res://data")

func initialize_csv_header() -> void:
	# Check if local CSV already exists and has content
	if FileAccess.file_exists(LOCAL_CSV_PATH):
		var file = FileAccess.open(LOCAL_CSV_PATH, FileAccess.READ)
		if file and file.get_length() > 0:
			is_header_written = true
			return
	
	write_header(LOCAL_CSV_PATH)
	write_header(CSV_FILE_PATH)
	is_header_written = true

func clear_csv() -> void:
	print("[CSVLogger] Wiping old simulation data for a fresh benchmark run.")
	write_header(LOCAL_CSV_PATH)
	write_header(CSV_FILE_PATH)
	is_header_written = true

func write_header(path: String) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		var header = "episode_id,system_type,player_bot_type,npc_survival_time,player_survival_time,npc_won,player_won,npc_hits,player_hits,state_transition_count,average_post_attack_response_latency,final_adaptive_retreat_threshold,final_adaptive_detection_range\n"
		file.store_string(header)
		file.close()

func log_episode(data: Dictionary) -> void:
	var row = "%d,%s,%s,%.2f,%.2f,%s,%s,%d,%d,%d,%.3f,%.2f,%.1f\n" % [
		data.get("episode_id", 0),
		data.get("system_type", "Unknown"),
		data.get("player_bot_type", "Manual"),
		data.get("npc_survival_time", 0.0),
		data.get("player_survival_time", 0.0),
		"TRUE" if data.get("npc_won", false) else "FALSE",
		"TRUE" if data.get("player_won", false) else "FALSE",
		data.get("npc_hits", 0),
		data.get("player_hits", 0),
		data.get("state_transition_count", 0),
		data.get("average_post_attack_response_latency", 0.016),
		data.get("final_adaptive_retreat_threshold", 0.30),
		data.get("final_adaptive_detection_range", 220.0)
	]
	
	append_row(LOCAL_CSV_PATH, row)
	append_row(CSV_FILE_PATH, row)
	print("[CSV Logger] Logged Episode #%d (%s vs %s)" % [
		data.get("episode_id", 0),
		data.get("system_type", "Unknown"),
		data.get("player_bot_type", "Manual")
	])

func append_row(path: String, row: String) -> void:
	var file = FileAccess.open(path, FileAccess.READ_WRITE)
	if not file:
		file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.seek_end()
		file.store_string(row)
		file.close()
