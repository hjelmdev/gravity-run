extends SceneTree

const ChallengeServiceScript := preload("res://systems/challenge_service.gd")
const CourseGeneratorScript := preload("res://systems/course_generator.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	var service := ChallengeServiceScript.new() as Node
	root.add_child(service)
	service.call("begin_run")
	var code: String = service.call("get_challenge_code")
	_check(code.begins_with("GR6-"), "new challenge codes should carry the current generator version")
	var challenge_link: String = service.call("get_challenge_link", code)
	_check(challenge_link.contains("?challenge=" + code), "the share link should pass its challenge code directly to the Pages app")
	var first_seed := int(service.get("seed_value"))
	_check(first_seed >= 100000000 and first_seed <= 2147483647, "random challenge seeds should be in the portable signed 32-bit range")
	_check(not bool(service.get("active")), "an ordinary seeded run should not be treated as a joined challenge")
	service.call("clear_challenge")
	_check(bool(service.call("start_challenge_from_code", code)), "a generated challenge code should be accepted")
	_check(int(service.get("seed_value")) == first_seed, "joining a challenge should restore the exact seed")
	_check(not bool(service.call("start_challenge_from_code", "GR1-123456789")), "unsupported generator versions should be rejected")
	_check(bool(service.call("start_challenge_from_code", "GR3-123456789")), "legacy v3 challenge codes should retain their original generator")
	_check(int(service.get("generation_version")) == 3, "joining a legacy challenge should keep its generator version")
	service.call("clear_challenge")
	_check(not bool(service.call("start_challenge_from_code", "not-a-code")), "malformed challenge codes should be rejected")
	var ruleset: Resource = service.get("ruleset").duplicate(true)
	ruleset.set("ruleset_id", &"round_trip")
	ruleset.set("include_all_profiles", false)
	ruleset.set("included_profile_ids", PackedStringArray(["spike_group", "floor_gap"]))
	ruleset.set("event_density", 1.25)
	var definition := {
		"challenge_code": "GC-0123456789AB",
		"generator_version": CourseGeneratorScript.GENERATOR_VERSION,
		"seed": 123456789,
		"ruleset_fingerprint": ruleset.call("get_fingerprint"),
		"ruleset": ruleset.call("to_payload"),
		"creator_name": "Runner",
	}
	_check(bool(service.call("_apply_challenge_definition", definition)), "a valid stored challenge definition should load")
	_check(str(service.get("active_challenge_code")) == "GC-0123456789AB", "a loaded challenge should retain its opaque share code")
	_check(int(service.get("seed_value")) == 123456789, "a loaded challenge should restore its stored seed")
	_check(not bool(service.call("load_challenge_code", "GC-not-a-code")), "malformed opaque challenge codes should be rejected before network access")
	service.call("clear_challenge")
	if failures == 0:
		print("ChallengeService tests passed.")
	service.queue_free()
	quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
