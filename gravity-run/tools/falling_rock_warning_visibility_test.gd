extends SceneTree

const RockModel := preload("res://systems/falling_rock_model.gd")
const Motion := preload("res://systems/runner_motion.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var event := {"x": 2000.0, "ceiling_y": 80.0, "floor_y": 460.0, "trigger_lead": 1600.0, "warning_ticks": 104, "fall_ticks": 42, "width": 90.0, "height": 100.0, "burial_depth": 24.0}
	var viewport_width := 960.0
	var runner_screen_x := 250.0
	var visible_right_offset := viewport_width - runner_screen_x
	var activation_tick := RockModel.DELIVERY_TICKS
	var fast_visible_delay_ticks := ceili((float(event.trigger_lead) - 750.0 * float(activation_tick) / 60.0 - visible_right_offset) / (750.0 / 60.0))
	var normal_visible_delay_ticks := ceili((float(event.trigger_lead) - 500.0 * float(activation_tick) / 60.0 - visible_right_offset) / (500.0 / 60.0))
	var first_visible_tick := activation_tick + normal_visible_delay_ticks
	var fall_tick := activation_tick + int(event.warning_ticks)
	var trigger_x := float(event.x) - float(event.trigger_lead)
	var player_x_at_visible := trigger_x + 500.0 * float(activation_tick + normal_visible_delay_ticks) / 60.0
	_check(float(event.x) > trigger_x + 750.0 * float(activation_tick) / 60.0, "offscreen warning marker starts before the stone reaches the camera")
	_check(float(event.x) <= player_x_at_visible + visible_right_offset, "stone enters the normal camera after the warning edge marker")
	_check(fall_tick - first_visible_tick >= 8, "at the standard 500px/s speed, the stone is visibly warned before falling")
	_check(int(event.warning_ticks) - fast_visible_delay_ticks >= 30, "at the fastest 750px/s item speed, visible warning remains at least 500ms")
	_check(RockModel.phase_at(event, activation_tick, activation_tick) == "warning", "delivery begins the warning phase before fall")
	_check(RockModel.phase_at(event, activation_tick, fall_tick) == "falling", "fall begins exactly after warning window")
	_check(RockModel.offscreen_marker_active("warning") and RockModel.offscreen_marker_active("falling") and not RockModel.offscreen_marker_active("buried"), "offscreen edge warning remains visible throughout the fall and ends after landing")
	_check(RockModel.phase_at(event, activation_tick, fall_tick + 41) == "falling" and RockModel.phase_at(event, activation_tick, fall_tick + 42) == "buried", "slower fall lasts 42 shared simulation ticks before becoming permanent")
	_check(float(event.x) > 0.0, "warning remains available before the rock's fatal footprint")
	_check(_runner_survives_with_reaction_and_cooldown(event, activation_tick, 500.0), "standard-speed runner with 0.84s residual cooldown and 200ms reaction flips safely")
	_check(_runner_survives_with_reaction_and_cooldown(event, activation_tick, 750.0), "fast runner with 0.84s residual cooldown and 200ms reaction flips safely")
	print("V8 rock warning visibility: 500px/s shows >=133ms warning; 750px/s shows >=500ms; shared 104-tick warning, 42-tick fall; max cooldown + 200ms reaction routes passed.")
	quit(1 if failures > 0 else 0)

func _runner_survives_with_reaction_and_cooldown(event: Dictionary, activation_tick: int, speed: float) -> bool:
	var start_x := float(event.get("x", 0.0)) - float(event.get("trigger_lead", 0.0)) - speed * float(activation_tick) / 60.0
	var state := {"world_x": start_x, "y": 438.0, "gravity_direction": 1, "vertical_speed": 0.0, "grounded": true, "cooldown": 0.84}
	var body_size: Vector2 = Motion.SIZE
	var reaction_tick := activation_tick + 12 # 200ms after delivery/warning indicator starts.
	var flipped := false
	for tick in range(240):
		var start := Vector2(float(state.world_x), float(state.y))
		if tick >= reaction_tick and not flipped and float(state.cooldown) <= 0.0:
			flipped = Motion.try_flip(state, -1, 2.0)
		Motion.advance_vertical(state, 1.0 / 60.0, 460.0, 80.0, true, true)
		state.world_x = float(state.world_x) + speed / 60.0
		var finish := Vector2(float(state.world_x), float(state.y))
		var contact := RockModel.swept_contact_fraction(event, activation_tick, tick, tick + 1, start, finish, body_size)
		if contact >= 0.0:
			return false
		if float(state.world_x) > float(event.x) + 100.0:
			return flipped and int(state.gravity_direction) == -1
	return false

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
