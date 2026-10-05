extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var service_source := _read("res://systems/multiplayer_v2/multiplayer_v2_service.gd")
	var generator_source := _read("res://systems/course_generator.gd")
	var config_source := _read("res://project.godot")
	var migration_path := "res://supabase/migrations/202610050002_generator13_gap_safe_barrels.sql"
	var migration_source := _read(migration_path)
	var game_values := _capture(service_source, 'const V2_GAME_VERSION := "([^"]+)"', "service multiplayer version")
	var generator_values := _capture(generator_source, "const GENERATOR_VERSION := GENERATOR_VERSION_([0-9]+)", "current generator version")
	var create_gate := migration_source.contains("p_game_version = '2.1.20261005.9' and p_generator_version = 13")
	var legacy_create_gate := migration_source.contains("p_game_version = '2.1.20261003.7' and p_generator_version = 11")
	var prior_create_gate := migration_source.contains("p_game_version = '2.1.20261005.8' and p_generator_version = 12")
	var coin_gate := migration_source.contains("v_room.generator_version = 13 and v_room.game_version = '2.1.20261005.9'")
	var legacy_coin_gate := migration_source.contains("v_room.generator_version = 11 and v_room.game_version = '2.1.20261003.7'")
	var prior_coin_gate := migration_source.contains("v_room.generator_version = 12 and v_room.game_version = '2.1.20261005.8'")
	var game_version: String = game_values[0] if not game_values.is_empty() else ""
	var generator_version: String = generator_values[0] if not generator_values.is_empty() else ""
	_check(not game_version.is_empty(), "the service version constant is readable")
	_check(not generator_version.is_empty(), "the generator version constant is readable")
	_check(create_gate, "create-room gate accepts the current release tuple")
	_check(legacy_create_gate, "create-room gate retains the frozen Gen11 client tuple")
	_check(prior_create_gate, "create-room gate retains the frozen Gen12 client tuple")
	_check(coin_gate, "coin registration gate accepts the current release tuple")
	_check(legacy_coin_gate, "coin registration gate preserves existing Gen11 rounds")
	_check(prior_coin_gate, "coin registration gate preserves existing Gen12 rounds")
	_check(migration_source.count("generator_version in (11, 12, 13)") == 2, "achievement receipt start/record continue accepting frozen Gen11/12 rounds and current Gen13")
	if not game_version.is_empty() and not generator_version.is_empty():
		_check(game_version == "2.1.20261005.9" and generator_version == "13", "service and generator constants name the Gen13 release tuple")
	var config_values := _capture(config_source, 'config/version="([^"]+)"', "visible project build version")
	var config_version: String = config_values[0] if not config_values.is_empty() else ""
	_check(not config_version.is_empty() and config_version != "2026.10.02-start-audio-rock-fix1", "project build identifier no longer advertises the stale release")
	_check(config_version.contains("gen13"), "project build identifier names generator v13")
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
