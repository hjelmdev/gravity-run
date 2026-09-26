extends SceneTree

const CourseGeneratorScript := preload("res://systems/course_generator.gd")
const CourseHazardProfileScript := preload("res://systems/course_hazard_profile.gd")
const CourseDifficultyProfileScript := preload("res://systems/course_difficulty_profile.gd")
const CourseRulesetScript := preload("res://systems/course_generation_ruleset.gd")
const CourseRunDefinitionScript := preload("res://systems/course_run_definition.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	_test_many_seeded_courses()
	_test_seed_reproduces_course_events()
	_test_multi_window_future_hazard()
	_test_impossible_custom_hazard_is_rejected()
	_test_fast_barrel_forecast()
	_test_difficulty_profile_is_optional_and_composable()
	_test_ruleset_is_seeded_and_limits_profiles()
	_test_ruleset_can_register_future_hazards()
	_test_ruleset_payload_roundtrip()
	_test_fixed_stage_reproduces_across_generation_batches()
	await _test_gap_fall_and_opposite_lane()
	if failures == 0:
		print("CourseGenerator tests passed.")
	quit(1 if failures > 0 else 0)

func _test_many_seeded_courses() -> void:
	var found_floor_gap := false
	var found_ceiling_gap := false
	for seed_value in range(1, 13):
		var generator := CourseGeneratorScript.new() as CourseGenerator
		generator.configure_default_profiles()
		generator.reset(seed_value)
		var height := 540.0 if seed_value % 2 == 0 else 900.0
		var test_horizon := 500000.0 if seed_value == 1 else 60000.0
		generator.ensure_horizon(test_horizon, 750.0, height, 820.0)
		var events := generator.get_planned_events()
		_check(events.size() >= 50, "seed %d should produce a long course" % seed_value)
		_check(generator.is_plan_solvable(events, generator.get_switch_clearance_distance(750.0, CourseGenerator.REFERENCE_TRACK_HEIGHT)), "seed %d generated an unsolvable course" % seed_value)
		for event in events:
			if event["kind"] == &"gap":
				found_ceiling_gap = found_ceiling_gap or bool(event["from_ceiling"])
				found_floor_gap = found_floor_gap or not bool(event["from_ceiling"])
	_check(found_floor_gap, "default courses should generate floor gaps")
	_check(found_ceiling_gap, "default courses should generate ceiling gaps")

func _test_seed_reproduces_course_events() -> void:
	var first := CourseGeneratorScript.new() as CourseGenerator
	first.configure_default_profiles(CourseGenerator.GENERATOR_VERSION)
	first.reset(1234567890)
	first.ensure_horizon(80000.0, 750.0, 540.0, 820.0)
	var first_signature := _course_signature(first.get_planned_events())
	var second := CourseGeneratorScript.new() as CourseGenerator
	second.configure_default_profiles(CourseGenerator.GENERATOR_VERSION)
	second.reset(1234567890)
	second.ensure_horizon(80000.0, 330.0, 900.0, 1400.0)
	_check(first_signature == _course_signature(second.get_planned_events()), "the same challenge seed should reproduce the course despite runtime speed and viewport differences")

func _course_signature(events: Array[Dictionary]) -> Array[String]:
	var signature: Array[String] = []
	for event in events:
		var event_signature := "%s|%s|%.3f|%.2f|%.2f|%d|%d|%.3f|%.1f" % [
			str(event.get("id", "")), str(event.get("kind", "")), float(event.get("course_distance", 0.0)),
			float(event.get("width", 0.0)), float(event.get("height", 0.0)), int(event.get("count", 0)),
			int(event.get("blocked_lanes", 0)), float(event.get("motion_speed_multiplier", 1.0)),
			float(event.get("slope_direction", 0.0))
		]
		for threat in event.get("threats", []):
			event_signature += "|%.3f:%.3f:%d" % [float(threat.get("start", 0.0)), float(threat.get("end", 0.0)), int(threat.get("blocked_lanes", 0))]
		signature.append(event_signature)
	return signature

func _test_multi_window_future_hazard() -> void:
	var generator := CourseGeneratorScript.new() as CourseGenerator
	generator.configure_default_profiles()
	generator.reset(91)
	var profile := CourseHazardProfileScript.new() as CourseHazardProfile
	profile.profile_id = &"test_torpedo"
	profile.event_kind = &"custom_torpedo"
	profile.weight = 1.0
	profile.allowed_lanes = CourseGenerator.BOTH_LANES
	profile.width_range = Vector2(80.0, 80.0)
	profile.threat_windows = [Vector3(-700.0, -600.0, CourseGenerator.FLOOR_LANE), Vector3(100.0, 200.0, CourseGenerator.CEILING_LANE)]
	var event := profile.create_event(RandomNumberGenerator.new(), 5000.0)
	_check(event["threats"].size() == 2, "multi-window hazard should expose both threat windows")
	_check(generator.is_plan_solvable([event], 450.0), "separated future-hazard windows should be routable")

func _test_impossible_custom_hazard_is_rejected() -> void:
	var generator := CourseGeneratorScript.new() as CourseGenerator
	var impossible := {
		"threats": [
			{"start": 1000.0, "end": 1200.0, "blocked_lanes": CourseGenerator.FLOOR_LANE},
			{"start": 1100.0, "end": 1300.0, "blocked_lanes": CourseGenerator.CEILING_LANE},
		]
	}
	_check(not generator.is_plan_solvable([impossible], 300.0), "overlapping threats that close both lanes must be rejected")

func _test_fast_barrel_forecast() -> void:
	var generator := CourseGeneratorScript.new() as CourseGenerator
	generator.configure_default_profiles()
	var barrel_profile: CourseHazardProfile
	for profile in generator._profiles:
		if profile.profile_id == &"barrel_chain":
			barrel_profile = profile
			break
	_check(barrel_profile != null, "default generator should define a barrel profile")
	if barrel_profile == null:
		return
	barrel_profile.spawn_lead_distance = 820.0
	var event := barrel_profile.create_event(RandomNumberGenerator.new(), 5000.0)
	var threat: Dictionary = event["threats"][0]
	var expected_center := 5000.0 - 820.0 * (1.0 - 1.0 / float(event["motion_speed_multiplier"]))
	_check(is_equal_approx((float(threat["start"]) + float(threat["end"])) * 0.5, expected_center), "barrel forecast should shift earlier based on faster motion and spawn lead")
	_check(is_equal_approx(float(event["motion_speed_multiplier"]), CourseGenerator.BARREL_SPEED_MULTIPLIER), "barrel speed range should stay fixed at 1.4 until explicitly widened")
	barrel_profile.motion_speed_min = 1.2
	barrel_profile.motion_speed_max = 1.8
	var variable_event := barrel_profile.create_event(RandomNumberGenerator.new(), 5000.0)
	_check(float(variable_event["motion_speed_multiplier"]) >= 1.2 and float(variable_event["motion_speed_multiplier"]) <= 1.8, "future per-event speed variation should stay inside its configured range")
	var variable_threat: Dictionary = variable_event["threats"][0]
	var variable_expected_center := 5000.0 - 820.0 * (1.0 - 1.0 / float(variable_event["motion_speed_multiplier"]))
	_check(is_equal_approx((float(variable_threat["start"]) + float(variable_threat["end"])) * 0.5, variable_expected_center), "forecast should use the exact speed sampled for each event")

func _test_difficulty_profile_is_optional_and_composable() -> void:
	var neutral := CourseGeneratorScript.new() as CourseGenerator
	neutral.configure_default_profiles()
	neutral.reset(451)
	var profile := CourseDifficultyProfileScript.new() as Resource
	neutral.set_difficulty_profile(profile)
	_check(is_equal_approx(neutral.get_density_adjusted_spacing(600.0), 600.0), "default difficulty profile should preserve event spacing")
	var hard_profile := CourseDifficultyProfileScript.new() as Resource
	hard_profile.set("event_density", 1.5)
	var harder := CourseGeneratorScript.new() as CourseGenerator
	harder.configure_default_profiles()
	harder.set_difficulty_profile(hard_profile)
	_check(is_equal_approx(harder.get_density_adjusted_spacing(600.0), 400.0), "density factor should scale spacing predictably")
	hard_profile.set("profile_weight_multipliers", {"floor_gap": 2.0})
	_check(is_equal_approx(float(harder.call("_get_profile_weight_multiplier", &"floor_gap")), 2.0), "profile weight overrides should be independently configurable")

func _test_ruleset_is_seeded_and_limits_profiles() -> void:
	var floor_gap_rules := CourseRulesetScript.new() as Resource
	floor_gap_rules.set("ruleset_id", &"floor-gaps-only")
	floor_gap_rules.set("include_all_profiles", false)
	floor_gap_rules.set("included_profile_ids", PackedStringArray(["floor_gap"]))
	var first := CourseGeneratorScript.new() as CourseGenerator
	_check(first.configure_ruleset(floor_gap_rules), "a valid restricted ruleset should configure")
	first.reset(667788)
	first.ensure_horizon(40000.0, 500.0, 540.0, 820.0)
	var first_events := first.get_planned_events()
	_check(not first_events.is_empty(), "a restricted ruleset should still generate a course")
	for event in first_events:
		_check(event["id"] == &"floor_gap", "a ruleset must not emit hazards outside its allowlist")
		_check(not bool(event["from_ceiling"]), "a floor-only rule set must not emit ceiling openings")

	var second := CourseGeneratorScript.new() as CourseGenerator
	_check(second.configure_ruleset(floor_gap_rules), "the same ruleset should be reusable")
	second.reset(667788)
	second.ensure_horizon(40000.0, 500.0, 540.0, 820.0)
	_check(_course_signature(first_events) == _course_signature(second.get_planned_events()), "the same seed and ruleset must produce identical encounter plans")
	_check(str(floor_gap_rules.call("get_fingerprint")) == str(floor_gap_rules.duplicate(true).call("get_fingerprint")), "identical rulesets should have identical fingerprints")
	_check(str(floor_gap_rules.call("get_fingerprint")) != str(CourseRulesetScript.new().call("get_fingerprint")), "different rulesets should have different fingerprints")

func _test_ruleset_can_register_future_hazards() -> void:
	var torpedo := CourseHazardProfileScript.new() as CourseHazardProfile
	torpedo.profile_id = &"test_torpedo"
	torpedo.event_kind = &"torpedo"
	torpedo.weight = 1.0
	torpedo.allowed_lanes = CourseGenerator.FLOOR_LANE
	torpedo.width_range = Vector2(90.0, 120.0)
	torpedo.threat_windows = [Vector3(-100.0, 100.0, CourseGenerator.FLOOR_LANE)]
	var ruleset := CourseRulesetScript.new() as Resource
	ruleset.set("ruleset_id", &"torpedo-only-test")
	ruleset.set("include_all_profiles", false)
	ruleset.set("included_profile_ids", PackedStringArray(["test_torpedo"]))
	var generator := CourseGeneratorScript.new() as CourseGenerator
	_check(generator.configure_ruleset(ruleset, CourseGenerator.GENERATOR_VERSION, [torpedo]), "future hazard profiles should be registerable through the same ruleset API")
	generator.reset(774411)
	generator.ensure_horizon(20000.0, 500.0, 540.0, 820.0)
	var events := generator.get_planned_events()
	_check(not events.is_empty(), "a future-hazard ruleset should produce encounters")
	for event in events:
		_check(event["kind"] == &"torpedo", "the generator should emit the selected future hazard")
		_check(event.get("threats", []).size() == 1, "future hazards must supply route-planner threat forecasts")

func _test_fixed_stage_reproduces_across_generation_batches() -> void:
	var stage_rules := CourseRulesetScript.new() as Resource
	stage_rules.set("ruleset_id", &"campaign-5-1")
	stage_rules.set("include_all_profiles", false)
	stage_rules.set("included_profile_ids", PackedStringArray(["spike_group", "floor_gap", "ceiling_gap", "barrel_chain"]))
	stage_rules.set("event_density", 1.18)
	stage_rules.set("profile_weight_multipliers", {"spike_group": 0.7, "barrel_chain": 1.4})
	var first_stage := CourseRunDefinitionScript.new() as Resource
	first_stage.set("scenario_id", &"campaign-5-1")
	first_stage.set("seed_value", 5101)
	first_stage.set("generator_version", CourseGenerator.GENERATOR_VERSION)
	first_stage.set("ruleset", stage_rules)
	var second_stage := CourseRunDefinitionScript.new() as Resource
	second_stage.set("scenario_id", &"campaign-5-1")
	second_stage.set("seed_value", 5101)
	second_stage.set("generator_version", CourseGenerator.GENERATOR_VERSION)
	second_stage.set("ruleset", stage_rules.duplicate(true))
	var one_batch := CourseGeneratorScript.new() as CourseGenerator
	var batches := CourseGeneratorScript.new() as CourseGenerator
	_check(one_batch.configure_run_definition(first_stage), "a fixed campaign-stage run definition should configure")
	_check(batches.configure_run_definition(second_stage), "the same campaign-stage run definition should configure for another player")
	_check(str(first_stage.call("get_course_identity")) == str(second_stage.call("get_course_identity")), "the run definition should expose a common comparison identity")
	one_batch.ensure_horizon(90000.0, 500.0, 540.0, 820.0)
	for horizon in [12000.0, 27500.0, 48000.0, 90000.0]:
		batches.ensure_horizon(horizon, 330.0, 900.0, 1400.0)
	_check(_course_signature(one_batch.get_planned_events()) == _course_signature(batches.get_planned_events()), "a fixed campaign seed and ruleset must be independent of streaming batch size and device geometry")

func _test_ruleset_payload_roundtrip() -> void:
	var ruleset := CourseRulesetScript.new() as Resource
	ruleset.set("ruleset_id", &"shared_custom")
	ruleset.set("revision", 3)
	ruleset.set("include_all_profiles", false)
	ruleset.set("included_profile_ids", PackedStringArray(["spike_group", "barrel_chain"]))
	ruleset.set("event_density", 1.35)
	ruleset.set("hazard_size", 1.1)
	ruleset.set("lane_alternation", 0.25)
	ruleset.set("reaction_margin", 0.8)
	ruleset.set("profile_weight_multipliers", {"barrel_chain": 1.5})
	var payload: Dictionary = ruleset.call("to_payload")
	var restored: Resource = CourseRulesetScript.from_payload(payload)
	_check(restored != null, "serialized challenge rules should restore from their explicit payload whitelist")
	if restored != null:
		_check(str(restored.call("get_fingerprint")) == str(ruleset.call("get_fingerprint")), "restored rules should retain their comparison fingerprint")
	var json_number_payload := payload.duplicate(true)
	json_number_payload["revision"] = 1.0
	_check(CourseRulesetScript.from_payload(json_number_payload) != null, "ruleset decoder should accept integer-valued revisions returned as JSON floats")
	_check(CourseRulesetScript.from_payload(JSON.stringify(payload)) != null, "ruleset decoder should also accept a JSON-encoded object")
	var invalid_payload := payload.duplicate(true)
	invalid_payload["event_density"] = "untrusted"
	_check(CourseRulesetScript.from_payload(invalid_payload) == null, "ruleset decoder should reject malformed JSON field types")

func _test_gap_fall_and_opposite_lane() -> void:
	var player_scene := load("res://player/player.tscn") as PackedScene
	var player := player_scene.instantiate() as Node2D
	root.add_child(player)
	await process_frame
	player.call("reset_to_floor", 484.0)
	for _frame in range(20):
		player.call("advance", 1.0 / 60.0, 484.0, 56.0, false, true)
	_check(float(player.position.y) > 484.0, "player should fall through an unsupported floor")

	player.call("reset_to_floor", 484.0)
	player.call("_try_flip", -1)
	for _frame in range(45):
		player.call("advance", 1.0 / 60.0, 484.0, 56.0, true, true)
	_check(bool(player.get("grounded")) and int(player.get("gravity_direction")) == -1, "player should be able to reach the intact ceiling lane")
	for _frame in range(20):
		player.call("advance", 1.0 / 60.0, 484.0, 56.0, true, false)
	_check(float(player.position.y) < 56.0, "player should fall through an unsupported ceiling")
	player.queue_free()
	await process_frame

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
