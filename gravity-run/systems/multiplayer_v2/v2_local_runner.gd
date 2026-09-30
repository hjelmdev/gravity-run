extends RefCounted
class_name MultiplayerV2LocalRunner

const Motion := preload("res://systems/runner_motion.gd")
const Presentation := preload("res://systems/runner_presentation.gd")
const FIXED_DELTA := 1.0 / 60.0

var player_state: Dictionary = {}
var previous_render_state: Dictionary = {}
var current_render_state: Dictionary = {}
var simulation_tick := 0
var input_sequence := 0
var sample_sequence := 0
var owner_peer_id := 0
var round_id := ""
var active := false
var run_speed_multiplier := 1.0
var flip_cooldown_multiplier := 1.0

func configure(round_identifier: String, local_peer_id: int, spawn_x: float, floor_y: float, resolved_stats: Dictionary = {}) -> void:
	round_id = round_identifier
	owner_peer_id = local_peer_id
	simulation_tick = 0
	input_sequence = 0
	sample_sequence = 0
	player_state = {"world_x": spawn_x, "y": floor_y - Motion.SIZE.y * 0.5, "vertical_speed": 0.0, "gravity_direction": 1, "grounded": true, "cooldown": 0.0, "state": "running", "blocked": false}
	previous_render_state = player_state.duplicate(true)
	current_render_state = player_state.duplicate(true)
	active = true
	run_speed_multiplier = clampf(float(resolved_stats.get("run_speed_percent", 10000)) / 10000.0, 0.95, 1.05)
	flip_cooldown_multiplier = clampf(float(resolved_stats.get("flip_cooldown_percent", 10000)) / 10000.0, 0.9, 1.1)

func step(flip_direction: int, floor_y: float, ceiling_y: float, floor_supported: bool = true, ceiling_supported: bool = true, advance_horizontal: bool = true, next_world_x: float = -1.0) -> Dictionary:
	if not active:
		return {}
	previous_render_state = player_state.duplicate(true)
	if flip_direction != 0:
		input_sequence += 1
		Motion.try_flip(player_state, flip_direction, flip_cooldown_multiplier)
	if next_world_x >= 0.0:
		player_state.world_x = next_world_x
	elif advance_horizontal:
		player_state.world_x = float(player_state.world_x) + Motion.distance_for_delta(FIXED_DELTA, run_speed_multiplier, bool(player_state.get("blocked", false)))
	Motion.advance_vertical(player_state, FIXED_DELTA, floor_y, ceiling_y, floor_supported, ceiling_supported)
	simulation_tick += 1
	current_render_state = player_state.duplicate(true)
	return make_sample()

func render_state(fraction: float) -> Dictionary:
	if not active:
		return player_state.duplicate(true)
	return Presentation.interpolate_states(previous_render_state, current_render_state, fraction)

func make_sample() -> Dictionary:
	sample_sequence += 1
	return {"round_id": round_id, "owner_peer_id": owner_peer_id, "sample_seq": sample_sequence, "simulation_tick": simulation_tick, "world_x": float(player_state.get("world_x", 0.0)), "y": float(player_state.get("y", 0.0)), "velocity_x": Motion.speed_for_multiplier(run_speed_multiplier) if not bool(player_state.get("blocked", false)) else 0.0, "velocity_y": float(player_state.get("vertical_speed", 0.0)), "gravity_direction": int(player_state.get("gravity_direction", 1)), "grounded": bool(player_state.get("grounded", false)), "blocked": bool(player_state.get("blocked", false)), "locomotion_state": str(player_state.get("state", "running")), "last_input_seq": input_sequence}

func set_blocked(blocked: bool) -> void:
	player_state["blocked"] = blocked

func stop(state: String) -> void:
	if state not in ["dead", "finished"]:
		return
	player_state["state"] = state
	active = false
	current_render_state = player_state.duplicate(true)

func set_pending_barrel(pending: bool) -> void:
	player_state["state"] = "pending_barrel" if pending else "running"
	if pending:
		player_state["vertical_speed"] = 0.0
		player_state["grounded"] = true
		player_state["blocked"] = true
	else:
		player_state["blocked"] = false

func advance_pending_tick() -> void:
	if not active:
		return
	previous_render_state = player_state.duplicate(true)
	simulation_tick += 1
	current_render_state = player_state.duplicate(true)
