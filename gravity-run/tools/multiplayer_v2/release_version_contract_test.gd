extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var service_source := _read("res://systems/multiplayer_v2/multiplayer_v2_service.gd")
	var generator_source := _read("res://systems/course_generator.gd")
	var config_source := _read("res://project.godot")
	var migration_path := "res://supabase/migrations/202610100001_generator22_avalanche_sandfall.sql"
	var migration_source := _read(migration_path)
	var game_values := _capture(service_source, 'const V2_GAME_VERSION := "([^"]+)"', "service multiplayer version")
	var generator_values := _capture(generator_source, "const GENERATOR_VERSION := GENERATOR_VERSION_([0-9]+)", "current generator version")
	var manifest_builder_source := _read("res://systems/course_manifest_builder.gd")
	var manifest_source := _read("res://systems/multiplayer_course_manifest.gd")
	var ledger_source := _read("res://systems/multiplayer_v2/v2_world_event_ledger.gd")
	var create_gate := migration_source.contains("p_game_version = '2.1.20261005.10' and p_generator_version = 14")
	var legacy_create_gate := migration_source.contains("p_game_version = '2.1.20261003.7' and p_generator_version = 11")
	var prior_create_gate := migration_source.contains("p_game_version = '2.1.20261005.8' and p_generator_version = 12")
	var gen13_create_gate := migration_source.contains("p_game_version = '2.1.20261005.9' and p_generator_version = 13")
	var gen14_create_gate := migration_source.contains("p_game_version = '2.1.20261005.10' and p_generator_version = 14")
	var gen15_create_gate := migration_source.contains("p_game_version = '2.1.20261005.11' and p_generator_version = 15")
	var gen16_create_gate := migration_source.contains("p_game_version = '2.1.20261006.12' and p_generator_version = 16")
	var gen17_create_gate := migration_source.contains("p_game_version = '2.1.20261006.13' and p_generator_version = 17")
	var gen18_create_gate := migration_source.contains("p_game_version = '2.1.20261007.14' and p_generator_version = 18")
	var gen19_create_gate := migration_source.contains("p_game_version = '2.1.20261007.15' and p_generator_version = 19")
	var gen20_create_gate := migration_source.contains("p_game_version = '2.1.20261007.16' and p_generator_version = 20")
	var gen21_create_gate := migration_source.contains("p_game_version = '2.1.20261008.17' and p_generator_version = 21")
	var gen22_create_gate := migration_source.contains("p_game_version = '2.1.20261010.18' and p_generator_version = 22")
	var mixed_create_gates_rejected := not migration_source.contains("p_game_version = '2.1.20261007.15' and p_generator_version = 20") and not migration_source.contains("p_game_version = '2.1.20261007.16' and p_generator_version = 19") and not migration_source.contains("p_game_version = '2.1.20261007.16' and p_generator_version = 21")
	var coin_gate := migration_source.contains("v_room.generator_version = 14 and v_room.game_version = '2.1.20261005.10'")
	var legacy_coin_gate := migration_source.contains("v_room.generator_version = 11 and v_room.game_version = '2.1.20261003.7'")
	var prior_coin_gate := migration_source.contains("v_room.generator_version = 12 and v_room.game_version = '2.1.20261005.8'")
	var gen13_coin_gate := migration_source.contains("v_room.generator_version = 13 and v_room.game_version = '2.1.20261005.9'")
	var gen14_coin_gate := migration_source.contains("v_room.generator_version = 14 and v_room.game_version = '2.1.20261005.10'")
	var gen15_coin_gate := migration_source.contains("v_room.generator_version = 15 and v_room.game_version = '2.1.20261005.11'")
	var gen16_coin_gate := migration_source.contains("v_room.generator_version = 16 and v_room.game_version = '2.1.20261006.12'")
	var gen17_coin_gate := migration_source.contains("v_room.generator_version = 17 and v_room.game_version = '2.1.20261006.13'")
	var gen18_coin_gate := migration_source.contains("v_room.generator_version = 18 and v_room.game_version = '2.1.20261007.14'")
	var gen19_coin_gate := migration_source.contains("v_room.generator_version = 19 and v_room.game_version = '2.1.20261007.15'")
	var gen20_coin_gate := migration_source.contains("v_room.generator_version = 20 and v_room.game_version = '2.1.20261007.16'")
	var gen21_coin_gate := migration_source.contains("v_room.generator_version = 21 and v_room.game_version = '2.1.20261008.17'")
	var gen22_coin_gate := migration_source.contains("v_room.generator_version = 22 and v_room.game_version = '2.1.20261010.18'")
	var mixed_coin_gates_rejected := not migration_source.contains("v_room.generator_version = 19 and v_room.game_version = '2.1.20261007.16'") and not migration_source.contains("v_room.generator_version = 20 and v_room.game_version = '2.1.20261007.15'") and not migration_source.contains("v_room.generator_version = 21 and v_room.game_version = '2.1.20261007.16'")
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
	_check(gen17_create_gate, "create-room gate retains the Gen17 release tuple")
	_check(gen18_create_gate, "create-room gate accepts the Gen18 .14 tuple")
	_check(gen19_create_gate, "create-room gate preserves the Gen19 .15 tuple")
	_check(gen20_create_gate, "create-room gate accepts the current Gen20 .16 tuple")
	_check(gen21_create_gate, "create-room gate accepts the Gen21 .17 tuple")
	_check(gen22_create_gate, "create-room gate accepts the Gen22 .18 tuple")
	_check(mixed_create_gates_rejected, "create-room gate does not mix Gen19 and Gen20 game versions")
	_check(coin_gate, "Gen14 coin registration gate remains frozen")
	_check(legacy_coin_gate, "coin registration gate preserves existing Gen11 rounds")
	_check(prior_coin_gate, "coin registration gate preserves existing Gen12 rounds")
	_check(gen13_coin_gate, "coin registration gate preserves existing Gen13 rounds")
	_check(gen14_coin_gate, "coin registration gate preserves existing Gen14 rounds")
	_check(gen15_coin_gate, "coin registration gate preserves the Gen15 tuple")
	_check(gen16_coin_gate, "coin registration gate accepts the current Gen16 tuple")
	_check(gen17_coin_gate, "coin registration gate retains the Gen17 tuple")
	_check(gen18_coin_gate, "coin registration gate accepts the Gen18 .14 tuple")
	_check(gen19_coin_gate, "coin registration gate preserves the Gen19 .15 tuple")
	_check(gen20_coin_gate, "coin registration gate accepts the current Gen20 .16 tuple")
	_check(gen21_coin_gate, "coin registration gate accepts the Gen21 .17 tuple")
	_check(gen22_coin_gate, "coin registration gate accepts the Gen22 .18 tuple")
	_check(mixed_coin_gates_rejected, "coin registration gate does not mix Gen19 and Gen20 game versions")
	_check(migration_source.count("generator_version in (11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22)") == 2, "achievement receipts preserve legacy versions and accept Gen22")
	_check(migration_source.count("create or replace function public.") == 4, "migration only replaces room creation, coin registration, and the two achievement receipt functions")
	_check(migration_source.contains("cardinality(p_hazards) > 12") and migration_source.contains("'lava_crack','lava_volcano'"), "Gen14 hazard discovery accepts both lava identities within the expanded catalog bound")
	if not game_version.is_empty() and not generator_version.is_empty():
		_check(game_version == "2.1.20261010.18" and generator_version == "22", "service and generator constants name the Gen22 release tuple")
	_check(manifest_builder_source.contains("manifest.manifest_version = 14 if generator_version >= CourseGenerator.GENERATOR_VERSION_21") and manifest_builder_source.contains("(13 if generator_version >= CourseGenerator.GENERATOR_VERSION_20"), "Gen20 retains manifest format 13 while Gen21 selects format 14")
	_check(manifest_source.contains("generator_version in [CourseGenerator.GENERATOR_VERSION_21, CourseGenerator.GENERATOR_VERSION_22] and manifest_version != 14") and manifest_source.contains("generator_version == CourseGenerator.GENERATOR_VERSION_20 and manifest_version != 13") and manifest_source.contains("generator_version == CourseGenerator.GENERATOR_VERSION_19 and manifest_version != 12") and manifest_source.contains("generator_version == CourseGenerator.GENERATOR_VERSION_18 and manifest_version != 11"), "manifest validator retains explicit Gen18/Gen19/Gen20/Gen21 formats")
	_check(ledger_source.contains("const BASELINE_FORMAT_VERSION := 4"), "Gen20 uses the existing baseline format without a codec bump")
	_check(_read("res://systems/multiplayer_v2/v2_world_simulation.gd").contains("GEN21_BARREL_BASELINE_FORMAT_VERSION := 5"), "Gen21 rubber state uses an explicit baseline format 5")
	var config_values := _capture(config_source, 'config/version="([^"]+)"', "visible project build version")
	var config_version: String = config_values[0] if not config_values.is_empty() else ""
	_check(not config_version.is_empty() and config_version != "2026.10.02-start-audio-rock-fix1", "project build identifier no longer advertises the stale release")
	_check(config_version.contains("gen22"), "project build identifier names generator v22")
	if failures == 0:
		print("Release version contract passed: source v%s/generator %s matches Gen17-21 SQL gates, manifest formats and versioned baselines; project build %s." % [game_version, generator_version, config_version])
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
