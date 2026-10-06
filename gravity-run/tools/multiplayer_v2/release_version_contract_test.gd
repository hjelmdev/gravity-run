extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var service_source := _read("res://systems/multiplayer_v2/multiplayer_v2_service.gd")
	var generator_source := _read("res://systems/course_generator.gd")
	var config_source := _read("res://project.godot")
	var migration_path := "res://supabase/migrations/202610060002_generator17_biome_meetings.sql"
	var migration_source := _read(migration_path)
	var game_values := _capture(service_source, 'const V2_GAME_VERSION := "([^"]+)"', "service multiplayer version")
	var generator_values := _capture(generator_source, "const GENERATOR_VERSION := GENERATOR_VERSION_([0-9]+)", "current generator version")
	var create_gate := migration_source.contains("p_game_version = '2.1.20261005.10' and p_generator_version = 14")
	var legacy_create_gate := migration_source.contains("p_game_version = '2.1.20261003.7' and p_generator_version = 11")
	var prior_create_gate := migration_source.contains("p_game_version = '2.1.20261005.8' and p_generator_version = 12")
	var gen13_create_gate := migration_source.contains("p_game_version = '2.1.20261005.9' and p_generator_version = 13")
	var gen14_create_gate := migration_source.contains("p_game_version = '2.1.20261005.10' and p_generator_version = 14")
	var gen15_create_gate := migration_source.contains("p_game_version = '2.1.20261005.11' and p_generator_version = 15")
	var gen16_create_gate := migration_source.contains("p_game_version = '2.1.20261006.12' and p_generator_version = 16")
	var gen17_create_gate := migration_source.contains("p_game_version = '2.1.20261006.13' and p_generator_version = 17")
	var coin_gate := migration_source.contains("v_room.generator_version = 14 and v_room.game_version = '2.1.20261005.10'")
	var legacy_coin_gate := migration_source.contains("v_room.generator_version = 11 and v_room.game_version = '2.1.20261003.7'")
	var prior_coin_gate := migration_source.contains("v_room.generator_version = 12 and v_room.game_version = '2.1.20261005.8'")
	var gen13_coin_gate := migration_source.contains("v_room.generator_version = 13 and v_room.game_version = '2.1.20261005.9'")
	var gen14_coin_gate := migration_source.contains("v_room.generator_version = 14 and v_room.game_version = '2.1.20261005.10'")
	var gen15_coin_gate := migration_source.contains("v_room.generator_version = 15 and v_room.game_version = '2.1.20261005.11'")
	var gen16_coin_gate := migration_source.contains("v_room.generator_version = 16 and v_room.game_version = '2.1.20261006.12'")
	var gen17_coin_gate := migration_source.contains("v_room.generator_version = 17 and v_room.game_version = '2.1.20261006.13'")
	var game_version: String = game_values[0] if not game_values.is_empty() else ""
	var generator_version: String = generator_values[0] if not generator_values.is_empty() else ""
	_check(not game_version.is_empty(), "the service version constant is readable")
	_check(not generator_version.is_empty(), "the generator version constant is readable")
	_check(create_gate, "Gen14 create-room gate remains frozen")
	_check(legacy_create_gate, "create-room gate retains the frozen Gen11 client tuple")
	_check(prior_create_gate, "create-room gate retains the frozen Gen12 client tuple")
	_check(gen13_create_gate, "create-room gate retains the frozen Gen13 client tuple")
	_check(gen14_create_gate, "create-room gate retains the frozen Gen14 tuple")
	_check(gen15_create_gate, "create-room gate preserves the Gen15 release tuple")
	_check(gen16_create_gate, "create-room gate accepts the current Gen16 release tuple")
	_check(gen17_create_gate, "create-room gate accepts the Gen17 release tuple while preserving Gen16")
	_check(coin_gate, "Gen14 coin registration gate remains frozen")
	_check(legacy_coin_gate, "coin registration gate preserves existing Gen11 rounds")
	_check(prior_coin_gate, "coin registration gate preserves existing Gen12 rounds")
	_check(gen13_coin_gate, "coin registration gate preserves existing Gen13 rounds")
	_check(gen14_coin_gate, "coin registration gate preserves existing Gen14 rounds")
	_check(gen15_coin_gate, "coin registration gate preserves the Gen15 tuple")
	_check(gen16_coin_gate, "coin registration gate accepts the current Gen16 tuple")
	_check(gen17_coin_gate, "coin registration gate accepts the Gen17 tuple while preserving Gen16")
	_check(migration_source.count("generator_version in (11, 12, 13, 14, 15, 16, 17)") == 2, "achievement receipts preserve Gen11-16 and accept Gen17")
	_check(migration_source.contains("cardinality(p_hazards) > 12") and migration_source.contains("'lava_crack','lava_volcano'"), "Gen14 hazard discovery accepts both lava identities within the expanded catalog bound")
	if not game_version.is_empty() and not generator_version.is_empty():
		_check(game_version == "2.1.20261006.13" and generator_version == "17", "service and generator constants name the Gen17 release tuple")
	var config_values := _capture(config_source, 'config/version="([^"]+)"', "visible project build version")
	var config_version: String = config_values[0] if not config_values.is_empty() else ""
	_check(not config_version.is_empty() and config_version != "2026.10.02-start-audio-rock-fix1", "project build identifier no longer advertises the stale release")
	_check(config_version.contains("gen17"), "project build identifier names generator v17")
	if failures == 0:
		print("Release version contract passed: source v%s/generator %s matches both latest SQL gates and project build %s." % [game_version, generator_version, config_version])
	quit(1 if failures > 0 else 0)

func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		_check(false, "required release contract file exists: " + path)
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_check(false, "required release contract file can be read: " + path)
		return ""
	return file.get_as_text()

func _capture(source: String, pattern: String, label: String) -> Array[String]:
	var regex := RegEx.new()
	var compile_error := regex.compile(pattern)
	_check(compile_error == OK, label + " regex compiles")
	if compile_error != OK:
		return []
	var result := regex.search(source)
	if result == null:
		_check(false, label + " is present")
		return []
	var values := PackedStringArray()
	for index in range(1, result.get_group_count() + 1):
		values.append(result.get_string(index))
	var result_values: Array[String] = []
	for value in values:
		result_values.append(value)
	return result_values

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: " + message)
