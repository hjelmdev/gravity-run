extends "res://systems/auth_provider.gd"

const Config = preload("res://systems/leaderboard_config.gd")

var _request: HTTPRequest
var _active_action := ""
var _access_token := ""

func _ready() -> void:
	_request = HTTPRequest.new()
	_request.name = "SupabaseAuthRequest"
	_request.timeout = 25.0
	_request.accept_gzip = false
	add_child(_request)
	_request.request_completed.connect(_on_request_completed)

func sign_up(email: String, password: String) -> void:
	_send("sign_up", "/auth/v1/signup?redirect_to=" + Config.AUTH_REDIRECT_URL.uri_encode(), {"email": email, "password": password})

func sign_in(email: String, password: String) -> void:
	_send("sign_in", "/auth/v1/token?grant_type=password", {"email": email, "password": password})

func sign_out(access_token: String) -> void:
	_access_token = access_token
	_send("sign_out", "/auth/v1/logout", {})

func refresh_session(refresh_token: String) -> void:
	_send("refresh", "/auth/v1/token?grant_type=refresh_token", {"refresh_token": refresh_token})

func request_password_reset(email: String, redirect_url: String) -> void:
	var suffix := "?redirect_to=" + redirect_url.uri_encode() if not redirect_url.is_empty() else ""
	_send("password_reset", "/auth/v1/recover" + suffix, {"email": email})

func _send(action: String, endpoint: String, payload: Dictionary) -> void:
	if is_instance_valid(_request) and _request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		action_finished.emit(action, false, tr("An account request is already running."))
		return
	_active_action = action
	var headers := PackedStringArray(["apikey: " + Config.PUBLISHABLE_KEY, "Content-Type: application/json", "Accept: application/json"])
	if action == "sign_out" and not _access_token.is_empty():
		headers.append("Authorization: Bearer " + _access_token)
	var error := _request.request(Config.PROJECT_URL + endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		var failed_action := _active_action
		_active_action = ""
		action_finished.emit(failed_action, false, tr("Could not start the request (code %d).") % error)

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var action := _active_action
	_active_action = ""
	var response_text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(response_text) if not response_text.is_empty() else {}
	if action == "sign_out":
		_access_token = ""
		signed_out.emit()
		action_finished.emit(action, result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300, "")
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		action_finished.emit(action, false, tr("Network error while contacting the account service (code %d).") % result)
		return
	if response_code < 200 or response_code >= 300:
		action_finished.emit(action, false, _friendly_error(parsed, response_code))
		return
	if action in ["sign_in", "sign_up", "refresh"] and parsed is Dictionary and parsed.has("access_token") and parsed.has("refresh_token"):
		session_received.emit(parsed)
		action_finished.emit(action, true, "")
		return
	if action == "sign_up":
		action_finished.emit(action, true, tr("Check your email to confirm your account, then sign in."))
	elif action == "password_reset":
		action_finished.emit(action, true, tr("If that account exists, a password reset email has been sent."))
	else:
		action_finished.emit(action, false, tr("The account service returned an unexpected response."))

func _friendly_error(response: Variant, response_code: int) -> String:
	var code := ""
	if response is Dictionary:
		code = str(response.get("code", response.get("error_code", response.get("msg", "")))).to_lower()
	if "email_not_confirmed" in code:
		return tr("Confirm your email address before signing in.")
	if "invalid_credentials" in code or "invalid login" in code:
		return tr("Email or password is incorrect.")
	if "already registered" in code or "user_already_exists" in code:
		return tr("An account with that email already exists.")
	if "password" in code and ("weak" in code or "short" in code):
		return tr("Choose a stronger password (at least 8 characters).")
	if "email" in code and ("invalid" in code or "format" in code):
		return tr("Enter a valid email address.")
	if response_code == 429:
		return tr("Too many attempts. Please wait a little and try again.")
	return tr("Account request failed (HTTP %d).") % response_code
