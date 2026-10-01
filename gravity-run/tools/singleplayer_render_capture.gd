extends SceneTree
## Capture the ordinary singleplayer renderer using a repeatable course and
## the same built-in demo input policy on the project's default render settings.

const FIXTURE_SEED := 918273645
const FIXTURE_GENERATOR_VERSION := 4
const WARMUP_SECONDS := 2.0
const MIN_CONTIGUOUS_SECONDS := 10.0
const MAX_CAPTURE_SECONDS := 90.0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var challenge_service := root.get_node("ChallengeService")
	challenge_service.set("active", true)
	challenge_service.set("seed_value", FIXTURE_SEED)
	challenge_service.set("generation_version", FIXTURE_GENERATOR_VERSION)
	var ruleset_script = load("res://systems/course_generation_ruleset.gd")
	challenge_service.set("ruleset", ruleset_script.new())

	seed(FIXTURE_SEED)
	var scene := load("res://main.tscn").instantiate() as Node2D
	scene.set("demo_mode", true)
	root.add_child(scene)
	scene.call("set_render_diagnostics_enabled", true)
	var capture_started_usec := Time.get_ticks_usec()
	var captured_run_start_usec := -1
	var captured_run_end_usec := -1
	var selected_frames: Array = []
	while float(Time.get_ticks_usec() - capture_started_usec) / 1_000_000.0 < MAX_CAPTURE_SECONDS:
		await process_frame
		var frames: Array = scene.get("_render_diagnostic_frames")
		if frames.size() < 2:
			continue
		var first_usec := int(frames.front().get("at_usec", -1))
		var last_usec := int(frames.back().get("at_usec", -1))
		if first_usec <= 0 or float(last_usec - first_usec) / 1_000_000.0 < WARMUP_SECONDS + MIN_CONTIGUOUS_SECONDS:
			continue
		var measurement_start_usec := first_usec + int(WARMUP_SECONDS * 1_000_000.0)
		selected_frames = frames.filter(func(frame: Dictionary) -> bool: return int(frame.get("at_usec", 0)) >= measurement_start_usec)
		if selected_frames.size() < 2:
			continue
		captured_run_start_usec = int(selected_frames.front().get("at_usec", -1))
		captured_run_end_usec = int(selected_frames.back().get("at_usec", -1))
		if float(captured_run_end_usec - captured_run_start_usec) / 1_000_000.0 >= MIN_CONTIGUOUS_SECONDS:
			break
		selected_frames.clear()

	if selected_frames.is_empty():
		push_error("Deterministic singleplayer fixture did not survive a contiguous 10-second capture within %d seconds." % int(MAX_CAPTURE_SECONDS))
		quit(1)
		return

	var report := {
		"build_id": ProjectSettings.get_setting("application/config/version"),
		"fixture": {
			"seed": FIXTURE_SEED,
			"generator_version": FIXTURE_GENERATOR_VERSION,
			"input_policy": "built-in demo AI",
			"warmup_seconds_discarded": WARMUP_SECONDS,
			"fps_cap": int(Engine.max_fps),
			"vsync_mode": DisplayServer.window_get_vsync_mode(),
			"window_size": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
			"viewport_size": [scene.get_viewport_rect().size.x, scene.get_viewport_rect().size.y],
			"zoom": float(scene.get_node("Camera2D").zoom.x),
			"capture_start_usec": captured_run_start_usec,
			"capture_end_usec": captured_run_end_usec,
			"capture_seconds": float(captured_run_end_usec - captured_run_start_usec) / 1_000_000.0,
		},
		"frames": selected_frames,
	}
	var output_dir := ProjectSettings.globalize_path("res://../.codex-v2-analysis").simplify_path()
	DirAccess.make_dir_recursive_absolute(output_dir)
	var output_path := output_dir.path_join("singleplayer-render-capture.json")
	var output := FileAccess.open(output_path, FileAccess.WRITE)
	if output == null:
		push_error("Could not save rendering capture: %s" % output_path)
		quit(1)
		return
	output.store_string(JSON.stringify(report))
	output.close()
	print("Singleplayer render capture: seed=%d, frames=%d, seconds=%.2f, engine_max_fps=%d, vsync_mode=%d" % [FIXTURE_SEED, selected_frames.size(), report.fixture.capture_seconds, Engine.max_fps, DisplayServer.window_get_vsync_mode()])
	print("Saved: %s" % output_path)
	quit(0)
