extends Node

signal leaderboard_received(version: int, seed: int, rows: Array, error_message: String)
signal score_submission_finished(success: bool, error_message: String)
signal challenge_definition_received(success: bool, definition: Dictionary, error_message: String)
signal challenge_created(success: bool, challenge_code: String, error_message: String)
signal challenge_library_received(entries: Array, error_message: String)
signal challenge_library_changed(challenge_code: String, success: bool, error_message: String)

const CourseGeneratorScript := preload("res://systems/course_generator.gd")
const SeedScoreProvider := preload("res://systems/supabase_seed_score_provider.gd")
const SeedChallengeProvider := preload("res://systems/supabase_seed_challenge_provider.gd")
const RulesetScript := preload("res://systems/course_generation_ruleset.gd")
const Config := preload("res://systems/leaderboard_config.gd")
const GENERATOR_VERSION := CourseGeneratorScript.GENERATOR_VERSION
const LEGACY_GENERATOR_VERSION := CourseGeneratorScript.LEGACY_GENERATOR_VERSION
const PREVIOUS_GENERATOR_VERSION := CourseGeneratorScript.PREVIOUS_GENERATOR_VERSION
const MIN_CHALLENGE_SEED := 100000000
const MAX_CHALLENGE_SEED := 2147483647

var active := false
var seed_value := 0
var generation_version := GENERATOR_VERSION
var active_challenge_code := ""
var ruleset: Resource
var last_error := ""
var _score_provider: Node
var _challenge_provider: Node
var _custom_challenge_mode := false
var _ordinary_seed_run_pending := false
var _pending_challenge_name := ""

func _ready() -> void:
	_score_provider = SeedScoreProvider.new()
	_score_provider.name = "SupabaseSeedScoreProvider"
	_score_provider.request_finished.connect(_on_score_request_finished)
	add_child(_score_provider)
	_challenge_provider = SeedChallengeProvider.new()
	_challenge_provider.name = "SupabaseSeedChallengeProvider"
	_challenge_provider.request_finished.connect(_on_challenge_request_finished)
	add_child(_challenge_provider)
	ruleset = _new_default_ruleset(GENERATOR_VERSION)

func begin_run() -> int:
	if active and seed_value > 0:
		return seed_value
	if _ordinary_seed_run_pending and seed_value > 0:
		_ordinary_seed_run_pending = false
		last_error = ""
		return seed_value
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	seed_value = rng.randi_range(MIN_CHALLENGE_SEED, MAX_CHALLENGE_SEED)
	generation_version = GENERATOR_VERSION
	_custom_challenge_mode = false
	_ordinary_seed_run_pending = false
	active_challenge_code = ""
	ruleset = _new_default_ruleset(GENERATOR_VERSION)
	last_error = ""
	return seed_value

func start_challenge_from_code(raw_code: String) -> bool:
	last_error = ""
	var parts := raw_code.strip_edges().to_upper().split("-", false)
	if parts.size() != 2 or not parts[0].begins_with("GR") or not parts[0].substr(2).is_valid_int() or not parts[1].is_valid_int():
		last_error = "Invalid challenge code. Use GR%d- followed by its number." % GENERATOR_VERSION
		return false
	var requested_version := parts[0].substr(2).to_int()
	if not _supports_generator_version(requested_version):
		last_error = "That challenge uses an unsupported generator version."
		return false
	var parsed_seed := parts[1].to_int()
	if parsed_seed < 1 or parsed_seed > MAX_CHALLENGE_SEED:
		last_error = "The challenge seed is outside the supported range."
		return false
	generation_version = requested_version
	seed_value = parsed_seed
	active = true
	_ordinary_seed_run_pending = false
	_custom_challenge_mode = false
	active_challenge_code = ""
	ruleset = _new_default_ruleset(requested_version)
	return true

## Ordinary single-player seed selection shares the established numeric/GR parser
## but does not turn the run into a saved/community challenge.
func start_singleplayer_seed_input(raw_input: String) -> bool:
	var input := raw_input.strip_edges().to_upper()
	last_error = ""
	if input.is_empty():
		return true
	var requested_version := GENERATOR_VERSION
	var parsed_seed := 0
	if input.begins_with("GR"):
		var parts := input.split("-", false)
		if parts.size() != 2 or not parts[0].substr(2).is_valid_int() or not parts[1].is_valid_int():
			last_error = "Invalid seed code. Use GR%d-seed or enter a number." % GENERATOR_VERSION
			return false
		requested_version = parts[0].substr(2).to_int()
		parsed_seed = parts[1].to_int()
		if not _supports_generator_version(requested_version):
			last_error = "That seed code uses an unsupported generator version."
			return false
	else:
		if not input.is_valid_int():
			last_error = "Enter a positive number or a versioned GR seed code."
			return false
		parsed_seed = input.to_int()
	if parsed_seed < 1 or parsed_seed > MAX_CHALLENGE_SEED:
		last_error = "The seed must be between 1 and %d." % MAX_CHALLENGE_SEED
		return false
	generation_version = requested_version
	seed_value = parsed_seed
	active = false
	_custom_challenge_mode = false
	_ordinary_seed_run_pending = true
	active_challenge_code = ""
	ruleset = _new_default_ruleset(requested_version)
	return true

## Numeric GR codes remain supported for the current basic challenge flow.
## Opaque GC codes load their immutable definition asynchronously from Supabase.
func load_challenge_code(raw_code: String) -> bool:
	var code := raw_code.strip_edges().to_upper()
	if code.begins_with("GR"):
		return start_challenge_from_code(code)
	var code_pattern := RegEx.new()
	code_pattern.compile("^GC-[A-F0-9]{12}$")
	if code_pattern.search(code) == null:
		last_error = "Invalid challenge code."
		return false
	last_error = ""
	_challenge_provider.fetch_challenge(code)
	return true

func create_challenge_for_current_run(nickname: String, selected_ruleset: Resource = null, challenge_name: String = "") -> void:
	var run_ruleset := selected_ruleset if selected_ruleset != null else ruleset
	if seed_value <= 0 or run_ruleset == null:
		challenge_created.emit(false, "", "invalid_challenge_definition")
		return
	var validation_error := str(run_ruleset.call("validate", _get_available_profiles()))
	if not validation_error.is_empty():
		challenge_created.emit(false, "", validation_error)
		return
	ruleset = run_ruleset
	_pending_challenge_name = challenge_name.strip_edges()
	if _pending_challenge_name.is_empty():
		_pending_challenge_name = tr("Challenge by %s") % nickname.strip_edges()
	_challenge_provider.create_challenge(
		generation_version,
		seed_value,
		run_ruleset.call("to_payload"),
		str(run_ruleset.call("get_fingerprint")),
		nickname,
		_pending_challenge_name
	)

func get_challenge_code() -> String:
	if not active_challenge_code.is_empty():
		return active_challenge_code
	if seed_value <= 0:
		return ""
	return "GR%d-%010d" % [generation_version, seed_value]

func get_challenge_link(raw_code: String = "") -> String:
	var code := raw_code.strip_edges() if not raw_code.is_empty() else active_challenge_code
	if code.is_empty():
		code = get_challenge_code()
	if code.is_empty():
		return ""
	return "%s?challenge=%s" % [Config.AUTH_REDIRECT_URL, code.uri_encode()]

func read_challenge_code_from_web_url() -> String:
	if not OS.has_feature("web"):
		return ""
	var value: Variant = JavaScriptBridge.eval("new URLSearchParams(window.parent.location.search).get('challenge') || ''")
	if not value is String:
		return ""
	var code := str(value).strip_edges()
	return code if code.length() <= 24 else ""

func clear_challenge_code_from_web_url(expected_code: String) -> void:
	if not OS.has_feature("web") or expected_code.strip_edges().is_empty():
		return
	var expected_json := JSON.stringify(expected_code.strip_edges())
	var script := """
		(() => {
			try {
				const target = window.parent;
				const url = new URL(target.location.href);
				if ((url.searchParams.get('challenge') || '').toUpperCase() !== %s.toUpperCase()) return false;
				url.searchParams.delete('challenge');
				target.history.replaceState(target.history.state, '', url.pathname + url.search + url.hash);
				return true;
			} catch (_error) { return false; }
		})()
	""" % expected_json
	JavaScriptBridge.eval(script)

func fetch_challenge_library() -> void:
	var player_profile := get_node_or_null("/root/PlayerProfile")
	var local_entries: Array = player_profile.call("get_saved_seed_challenges") if player_profile != null else []
	if not _is_authenticated():
		challenge_library_received.emit(local_entries, "")
		return
	challenge_library_received.emit(local_entries, "")
	_challenge_provider.fetch_library()

func remove_challenge_from_library(challenge_code: String) -> void:
	var code := challenge_code.strip_edges().to_upper()
	var player_profile := get_node_or_null("/root/PlayerProfile")
	if player_profile != null:
		player_profile.call("forget_seed_challenge", code)
	if _is_authenticated():
		_challenge_provider.hide_from_library(code)
	else:
		challenge_library_changed.emit(code, true, "")

func fetch_current_scores() -> void:
	if seed_value <= 0:
		return
	if _custom_challenge_mode:
		_challenge_provider.fetch_leaderboard(active_challenge_code)
	else:
		_score_provider.fetch_scores(generation_version, seed_value)

func submit_current_run(nickname: String, distance_m: int) -> void:
	if seed_value <= 0:
		score_submission_finished.emit(false, "no_active_seed")
		return
	if _custom_challenge_mode:
		_challenge_provider.submit_run(active_challenge_code, nickname, distance_m)
	else:
		_score_provider.submit_run(generation_version, seed_value, nickname, distance_m)

func _on_score_request_finished(action: String, version: int, seed: int, success: bool, data: Variant, error_message: String) -> void:
	if action == "fetch":
		var rows: Array = data if success and data is Array else []
		leaderboard_received.emit(version, seed, rows, error_message)
		return
	score_submission_finished.emit(success, error_message)
	if success:
		_score_provider.fetch_scores(version, seed)

func _on_challenge_request_finished(action: String, success: bool, data: Variant, error_message: String) -> void:
	if action == "create":
		var created_rows: Variant = data
		var code := ""
		if success and created_rows is Array and not created_rows.is_empty() and created_rows[0] is Dictionary:
			code = str(created_rows[0].get("challenge_code", ""))
		if code.is_empty():
			challenge_created.emit(false, "", error_message if not error_message.is_empty() else "invalid_challenge_response")
			return
		active_challenge_code = code
		_custom_challenge_mode = true
		active = true
		_remember_challenge(code, _pending_challenge_name, _current_creator_nickname())
		if _is_authenticated():
			_challenge_provider.save_to_library(code)
		challenge_created.emit(true, code, "")
		return
	if action == "definition":
		var rows: Variant = data
		if not success or not rows is Array or rows.is_empty() or not rows[0] is Dictionary:
			challenge_definition_received.emit(false, {}, error_message if not error_message.is_empty() else "challenge_not_found")
			return
		var definition: Dictionary = rows[0]
		if not _apply_challenge_definition(definition):
			challenge_definition_received.emit(false, {}, last_error)
			return
		definition["ruleset"] = ruleset.call("to_payload")
		var challenge_name := str(definition.get("challenge_name", ""))
		var creator_name := str(definition.get("creator_name", ""))
		_remember_challenge(active_challenge_code, challenge_name, creator_name)
		if _is_authenticated():
			_challenge_provider.save_to_library(active_challenge_code)
		challenge_definition_received.emit(true, definition, "")
		return
	if action == "fetch_library":
		if not success or not data is Array:
			var player_profile := get_node_or_null("/root/PlayerProfile")
			var local_entries: Array = player_profile.call("get_saved_seed_challenges") if player_profile != null else []
			challenge_library_received.emit(local_entries, error_message)
			return
		var profile_node := get_node_or_null("/root/PlayerProfile")
		var merged_entries: Array = profile_node.call("merge_saved_seed_challenges", data) if profile_node != null else data
		challenge_library_received.emit(merged_entries, "")
		return
	if action == "save_library":
		challenge_library_changed.emit("", success, error_message)
		return
	if action == "hide_library":
		challenge_library_changed.emit("", success, error_message)
		return
	if action == "leaderboard":
		var rows: Array = data if success and data is Array else []
		leaderboard_received.emit(generation_version, seed_value, rows, error_message)
		return
	if action == "submit":
		score_submission_finished.emit(success, error_message)
		if success:
			_challenge_provider.fetch_leaderboard(active_challenge_code)

func _apply_challenge_definition(definition: Dictionary) -> bool:
	var requested_version := int(definition.get("generator_version", 0))
	if not _supports_generator_version(requested_version):
		last_error = "That challenge uses an unsupported generator version."
		return false
	var restored_ruleset: Resource = RulesetScript.from_payload(definition.get("ruleset"))
	if restored_ruleset == null:
		last_error = "That challenge has invalid rules."
		return false
	var validation_error := str(restored_ruleset.call("validate", _get_available_profiles(requested_version)))
	if not validation_error.is_empty() or str(restored_ruleset.call("get_fingerprint")) != str(definition.get("ruleset_fingerprint", "")):
		last_error = "That challenge's rules no longer match this game version."
		return false
	var requested_seed := int(definition.get("seed", 0))
	if requested_seed < 1 or requested_seed > MAX_CHALLENGE_SEED:
		last_error = "The challenge seed is outside the supported range."
		return false
	seed_value = requested_seed
	generation_version = requested_version
	active_challenge_code = str(definition.get("challenge_code", "")).to_upper()
	ruleset = restored_ruleset
	_custom_challenge_mode = true
	active = true
	last_error = ""
	return true

func _get_available_profiles(generator_version: int = GENERATOR_VERSION) -> Array:
	var generator := CourseGeneratorScript.new()
	return generator.get_profile_catalog(generator_version)

func _supports_generator_version(generator_version: int) -> bool:
	return generator_version in [GENERATOR_VERSION, CourseGeneratorScript.GENERATOR_VERSION_15, CourseGeneratorScript.GENERATOR_VERSION_14, CourseGeneratorScript.GENERATOR_VERSION_13, CourseGeneratorScript.GENERATOR_VERSION_12, CourseGeneratorScript.GENERATOR_VERSION_11, CourseGeneratorScript.GENERATOR_VERSION_10, CourseGeneratorScript.GENERATOR_VERSION_9, CourseGeneratorScript.GENERATOR_VERSION_8, CourseGeneratorScript.ROCK_SAFE_GENERATOR_VERSION, CourseGeneratorScript.GENERATOR_VERSION_6, CourseGeneratorScript.PUBLISHED_SHARED_GENERATOR_VERSION, PREVIOUS_GENERATOR_VERSION, LEGACY_GENERATOR_VERSION]

func _new_default_ruleset(generator_version: int) -> Resource:
	var default_ruleset := RulesetScript.new() as Resource
	if generator_version == LEGACY_GENERATOR_VERSION:
		default_ruleset.set("event_density", 1.0)
	elif generator_version == GENERATOR_VERSION:
		default_ruleset.set("revision", 13)
		default_ruleset.set("event_density", 1.9)
		default_ruleset.set("coin_revision", 2)
	elif generator_version == CourseGeneratorScript.GENERATOR_VERSION_15:
		default_ruleset.set("revision", 12)
		default_ruleset.set("event_density", 1.55)
		default_ruleset.set("coin_revision", 2)
	elif generator_version == CourseGeneratorScript.GENERATOR_VERSION_13:
		default_ruleset.set("revision", 10)
		default_ruleset.set("event_density", 1.55)
		default_ruleset.set("coin_revision", 2)
	elif generator_version == CourseGeneratorScript.GENERATOR_VERSION_14:
		default_ruleset.set("revision", 11)
		default_ruleset.set("event_density", 1.55)
		default_ruleset.set("coin_revision", 2)
	elif generator_version == CourseGeneratorScript.GENERATOR_VERSION_12:
		default_ruleset.set("revision", 9)
		default_ruleset.set("event_density", 1.55)
		default_ruleset.set("coin_revision", 2)
	elif generator_version == CourseGeneratorScript.GENERATOR_VERSION_11:
		default_ruleset.set("revision", 8)
		default_ruleset.set("event_density", 1.55)
	elif generator_version == CourseGeneratorScript.GENERATOR_VERSION_10:
		default_ruleset.set("revision", 7)
		default_ruleset.set("event_density", 1.55)
	elif generator_version == CourseGeneratorScript.GENERATOR_VERSION_9:
		default_ruleset.set("revision", 6)
		default_ruleset.set("event_density", 1.55)
	elif generator_version == CourseGeneratorScript.GENERATOR_VERSION_8:
		default_ruleset.set("revision", 5)
		default_ruleset.set("event_density", 1.5)
	elif generator_version == CourseGeneratorScript.ROCK_SAFE_GENERATOR_VERSION:
		default_ruleset.set("revision", 4)
		default_ruleset.set("event_density", 1.5)
	elif generator_version == CourseGeneratorScript.GENERATOR_VERSION_6:
		default_ruleset.set("revision", 3)
		default_ruleset.set("event_density", 1.5)
	elif generator_version == CourseGeneratorScript.PUBLISHED_SHARED_GENERATOR_VERSION:
		default_ruleset.set("revision", 2)
		default_ruleset.set("event_density", 1.5)
	else:
		default_ruleset.set("revision", 1)
		default_ruleset.set("event_density", 1.25)
	return default_ruleset

func _is_authenticated() -> bool:
	var auth_service := get_node_or_null("/root/AuthService")
	return auth_service != null and bool(auth_service.get("is_authenticated"))

func _current_creator_nickname() -> String:
	var account_profile := get_node_or_null("/root/PlayerAccountProfile")
	if account_profile != null and bool(account_profile.get("has_profile")):
		return str(account_profile.get("nickname"))
	var player_profile := get_node_or_null("/root/PlayerProfile")
	return str(player_profile.get("leaderboard_name")) if player_profile != null else ""

func _remember_challenge(code: String, challenge_name: String, creator_name: String) -> void:
	var player_profile := get_node_or_null("/root/PlayerProfile")
	if player_profile != null:
		player_profile.call("remember_seed_challenge", code, challenge_name, creator_name)

func clear_challenge() -> void:
	active = false
	seed_value = 0
	generation_version = GENERATOR_VERSION
	active_challenge_code = ""
	_custom_challenge_mode = false
	_ordinary_seed_run_pending = false
	ruleset = _new_default_ruleset(GENERATOR_VERSION)
	last_error = ""
