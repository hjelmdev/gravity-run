extends Node

signal auth_state_changed(is_authenticated: bool, email: String)
signal auth_action_finished(action: String, success: bool, message: String)

const EmailProvider = preload("res://systems/supabase_email_auth_provider.gd")
const GoogleOAuthProvider = preload("res://systems/supabase_google_oauth_provider.gd")
const SESSION_PATH := "user://gravity_run_auth.cfg"
const EXPIRY_REFRESH_MARGIN := 90

var is_authenticated := false
var email := ""
var user_id := ""
var _access_token := ""
var _refresh_token := ""
var _expires_at := 0
var _provider: Node
var _google_provider: Node
var _refresh_pending := false

func _ready() -> void:
	_provider = EmailProvider.new()
	_provider.name = "EmailAuthProvider"
	_provider.session_received.connect(_accept_session)
	_provider.action_finished.connect(_on_provider_action_finished)
	_provider.signed_out.connect(_clear_session)
	add_child(_provider)
	_google_provider = GoogleOAuthProvider.new()
	_google_provider.name = "GoogleOAuthProvider"
	_google_provider.session_received.connect(_accept_session)
	_google_provider.action_finished.connect(_on_provider_action_finished)
	add_child(_google_provider)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_session()
	if not _refresh_token.is_empty():
		_refresh_pending = true
		_provider.refresh_session(_refresh_token)

func _process(_delta: float) -> void:
	if is_authenticated and not _refresh_pending and _expires_at > 0 and Time.get_unix_time_from_system() >= _expires_at - EXPIRY_REFRESH_MARGIN:
		_refresh_pending = true
		_provider.refresh_session(_refresh_token)

func create_account(account_email: String, password: String) -> void:
	_provider.sign_up(account_email.strip_edges(), password)

func sign_in(account_email: String, password: String) -> void:
	_provider.sign_in(account_email.strip_edges(), password)

func sign_in_with_google() -> void:
	_google_provider.sign_in()

func sign_out() -> void:
	if is_authenticated:
		_provider.sign_out(_access_token)
	else:
		_clear_session()

func request_password_reset(account_email: String) -> void:
	_provider.request_password_reset(account_email.strip_edges(), "")

func get_access_token() -> String:
	return _access_token

## OAuth providers added later hand their Supabase session to this shared path.
func accept_external_session(session: Dictionary) -> void:
	if session.has("access_token") and session.has("refresh_token"):
		_accept_session(session)

func _accept_session(session: Dictionary) -> void:
	_refresh_pending = false
	_access_token = str(session.get("access_token", ""))
	_refresh_token = str(session.get("refresh_token", ""))
	_expires_at = int(session.get("expires_at", 0))
	if _expires_at <= 0:
		_expires_at = int(Time.get_unix_time_from_system()) + int(session.get("expires_in", 3600))
	var user: Dictionary = session.get("user", {})
	email = str(user.get("email", ""))
	user_id = str(user.get("id", ""))
	is_authenticated = not _access_token.is_empty() and not _refresh_token.is_empty()
	_save_session()
	auth_state_changed.emit(is_authenticated, email)

func _on_provider_action_finished(action: String, success: bool, message: String) -> void:
	if action == "refresh":
		_refresh_pending = false
		if not success and _expires_at > 0 and Time.get_unix_time_from_system() >= _expires_at:
			_clear_session()
	auth_action_finished.emit(action, success, message)

func _clear_session() -> void:
	var config := ConfigFile.new()
	config.save(SESSION_PATH)
	is_authenticated = false
	email = ""
	user_id = ""
	_access_token = ""
	_refresh_token = ""
	_expires_at = 0
	_refresh_pending = false
	auth_state_changed.emit(false, "")

func _load_session() -> void:
	var config := ConfigFile.new()
	if config.load(SESSION_PATH) != OK:
		return
	_refresh_token = str(config.get_value("session", "refresh_token", ""))
	_expires_at = int(config.get_value("session", "expires_at", 0))
	email = str(config.get_value("session", "email", ""))
	user_id = str(config.get_value("session", "user_id", ""))

func _save_session() -> void:
	var config := ConfigFile.new()
	config.set_value("session", "refresh_token", _refresh_token)
	config.set_value("session", "expires_at", _expires_at)
	config.set_value("session", "email", email)
	config.set_value("session", "user_id", user_id)
	var error := config.save(SESSION_PATH)
	if error != OK:
		push_warning("Could not persist the Supabase session (error %d)." % error)
