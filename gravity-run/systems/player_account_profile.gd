extends Node

signal profile_changed(nickname: String, has_profile: bool)
signal action_finished(action: String, success: bool, message: String)

const ProfileProvider = preload("res://systems/supabase_profile_provider.gd")

var nickname := ""
var has_profile := false
var _provider: Node
var _pending_nickname := ""

func _ready() -> void:
	_provider = ProfileProvider.new()
	_provider.name = "SupabaseProfileProvider"
	_provider.request_finished.connect(_on_request_finished)
	add_child(_provider)
	AuthService.auth_state_changed.connect(_on_auth_state_changed)
	if AuthService.is_authenticated:
		load_profile()

func load_profile() -> void:
	if not AuthService.is_authenticated:
		return
	_provider.load_profile(AuthService.get_access_token())

func save_nickname(value: String) -> void:
	var normalized := value.strip_edges()
	if not _is_valid_nickname(normalized):
		action_finished.emit("save_nickname", false, tr("Use 3–16 letters, numbers, or underscores for your nickname."))
		return
	_pending_nickname = normalized
	_provider.save_nickname(normalized, AuthService.get_access_token())

func _on_auth_state_changed(authenticated: bool, _email: String) -> void:
	if authenticated:
		load_profile()
	else:
		nickname = ""
		has_profile = false
		profile_changed.emit(nickname, has_profile)

func _on_request_finished(action: String, success: bool, data: Variant, message: String) -> void:
	if action == "load_profile":
		if not success:
			action_finished.emit(action, false, message)
			return
		var profile: Dictionary = data if data is Dictionary else {}
		nickname = str(profile.get("nickname", ""))
		has_profile = not nickname.is_empty()
		profile_changed.emit(nickname, has_profile)
		action_finished.emit(action, true, "")
		return
	if action == "save_nickname":
		if not success:
			action_finished.emit(action, false, message)
			return
		var result: Dictionary = data if data is Dictionary else {}
		nickname = str(result.get("nickname", _pending_nickname))
		has_profile = not nickname.is_empty()
		profile_changed.emit(nickname, has_profile)
		action_finished.emit(action, has_profile, tr("Nickname saved.") if has_profile else tr("Could not save your nickname."))

func _is_valid_nickname(value: String) -> bool:
	if value.length() < 3 or value.length() > 16:
		return false
	for character in value:
		if not (character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"):
			return false
	return true
