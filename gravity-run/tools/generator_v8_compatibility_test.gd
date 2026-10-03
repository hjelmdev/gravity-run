extends SceneTree

const Builder := preload("res://systems/course_manifest_builder.gd")
const Generator := preload("res://systems/course_generator.gd")
const ChallengeService := preload("res://systems/challenge_service.gd")

const FIXTURES := {
	8: {
		1: "c3e9b427c41c7f802ff83f29c2379a57e264f4483d7ff526900dd66aca179a7d",
		42: "494f93babaf8026e82b2886ff2e89aa4b2d3d9689c584aeb11a2dfb5f73ce449",
		918273645: "6d73132a61ccdde5c27ddf1b64fc3a592cce5a804ae798c1280d4f843f6192ed",
		100000014: "26483c290e58f7bb8890caf9751eff1e79452f7b79e9e01ac4599185c53c0ecc",
	},
	6: {
		1: "2f762d5cbe4625ec91608c73da03480e88938e524bb4a0e8a6adb0acdcfa6557",
		42: "57f4c5743a17e5fee7003f65ce05923333172ee3d71ad5ffe1bf3c1f8b6c60fe",
		918273645: "225ce68e79f561fd454be56ca387edf519355e614a575ed2e543275b3db938cd",
		100000000: "37f9f49e66b8ed79d2c8ce35825cddef48d1a7875298111ac17109e92ac538e8",
		100000014: "c8ec75310c1f9e3d41f4a6becf5f3a68b2cd1ad741b3e449c2a14bea9fbef4f1",
	},
	7: {
		1: "5a655a700760ea27d612c3bcd015094806df4f3d20fee3602061988f5fbc30a3",
		42: "5b11e08e4fb814c67828434f82102f418682ce8676ac3202fab2bd3f49628dd7",
		918273645: "dbdfda82d4969d55ab970b071376474ecc551cffe80ec51e15af1591945cbac2",
		100000000: "6016a8ac43117da9ed2d721ee1bdcb49fa351720f51bff6e78350007113bf294",
		100000014: "470f6550c5e82c2261effea4861ebcd182ce25ac04e1fbe2b5c13f9a6b527ba4",
	},
}

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var builder := Builder.new()
	var challenge := ChallengeService.new()
	for version in [6, 7, 8]:
		_check(challenge._supports_generator_version(version), "challenge flow retains v%d" % version)
		for seed in FIXTURES[version]:
			var built: Dictionary = builder.build(int(seed), 45000, version)
			var manifest: Resource = built.get("manifest")
			_check(str(built.get("error", "")).is_empty() and manifest != null, "v%d seed %s still builds" % [version, str(seed)])
			if manifest != null:
				_check(str(manifest.get("manifest_hash")) == str(FIXTURES[version][seed]), "v%d seed %s retains its pre-v8 manifest hash" % [version, str(seed)])
	_check(challenge._supports_generator_version(Generator.PREVIOUS_CURRENT_GENERATOR_VERSION), "challenge flow retains frozen v8")
	var first: Dictionary = builder.build(100000014, 45000, Generator.PREVIOUS_CURRENT_GENERATOR_VERSION)
	var second: Dictionary = builder.build(100000014, 45000, Generator.PREVIOUS_CURRENT_GENERATOR_VERSION)
	var first_manifest: Resource = first.get("manifest")
	var second_manifest: Resource = second.get("manifest")
	_check(first_manifest != null and second_manifest != null and str(first_manifest.get("manifest_hash")) == str(second_manifest.get("manifest_hash")), "v8 manifest remains deterministic: %s / %s / %s / %s" % [str(first.get("error", "")), str(second.get("error", "")), str(first_manifest.get("manifest_hash")) if first_manifest != null else "missing", str(second_manifest.get("manifest_hash")) if second_manifest != null else "missing"])
	if first_manifest != null:
		_check(int(first_manifest.get("generator_version")) == Generator.PREVIOUS_CURRENT_GENERATOR_VERSION, "the frozen schedule is stored with the v8 manifest version")
		var rocks := 0
		for event in first_manifest.get("events"):
			if str(event.get("kind", "")) != "rock":
				continue
			rocks += 1
			_check(int(event.get("warning_ticks", 0)) == 104 and int(event.get("fall_ticks", 0)) == 42 and is_equal_approx(float(event.get("trigger_lead", 0.0)), 1600.0), "v8 uses the later visible-drop schedule")
		_check(rocks > 0, "ordinary test seed includes a v8 rock")
	var v9_seed := 100000014
	var v9_a: Dictionary = builder.build(v9_seed, 45000, Generator.GENERATOR_VERSION)
	var v9_b: Dictionary = builder.build(v9_seed, 45000, Generator.GENERATOR_VERSION)
	var v9_manifest: Resource = v9_a.get("manifest")
	var v9_other: Resource = v9_b.get("manifest")
	_check(v9_manifest != null and v9_other != null and str(v9_manifest.get("manifest_hash")) == str(v9_other.get("manifest_hash")), "v9 manifest builds deterministically: %s" % str(v9_a.get("error", "")))
	if v9_manifest != null:
		_check(int(v9_manifest.get("generator_version")) == Generator.GENERATOR_VERSION and int(v9_manifest.get("manifest_version")) == 4, "v9 uses manifest format 4")
		var saw_count := 0
		for event in v9_manifest.get("events"):
			if str(event.get("kind", "")) == "saw":
				saw_count += 1
				_check(is_finite(float(event.get("spawn_x", NAN))) and event.has("floor_y") and event.has("ceiling_y"), "v9 saw serializes spawn and support geometry")
		_check(saw_count > 0, "representative v9 seed includes saw content")
	if failures == 0:
		print("Generator compatibility passed: frozen v6/v7/v8 manifest hashes unchanged; v9 uses deterministic manifest v4 saw content.")
	quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: " + message)
