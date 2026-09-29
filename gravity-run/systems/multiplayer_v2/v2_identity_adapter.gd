extends Node
## Owns anonymous V2 identity state while borrowing an authenticated app token.

const Config := preload("res://systems/leaderboard_config.gd")
signal identity_ready(user_id: String, token: String, is_anonymous: bool, context: String)
signal identity_failed(message: String, context: String)

var user_id := ""
var access_token := ""
var expires_at := 0
var is_anonymous := false
var _request: HTTPRequest
var _pending_context := ""

func _ready() -> void:
	_request = HTTPRequest.new()
	_request.name = "MultiplayerV2IdentityRequest"
	_request.timeout = 20.0
	_request.request_completed.connect(_on_signup_completed)
	add_child(_request)

func ensure_identity(display_name: String, context: String) -> void:
	if AuthService.is_authenticated and not AuthService.get_access_token().is_empty():
		user_id = AuthService.user_id
		access_token = AuthService.get_access_token()
		is_anonymous = false
		identity_ready.emit(user_id, access_token, false, context)
		return
	if not access_token.is_empty() and Time.get_unix_time_from_system() < expires_at - 60:
		identity_ready.emit(user_id, access_token, is_anonymous, context)
		return
	if _request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		identity_failed.emit(tr("A V2 multiplayer identity request is already in progress."), context)
		return
	_pending_context = context
	var headers := PackedStringArray(["apikey: " + Config.PUBLISHABLE_KEY, "Content-Type: application/json", "Accept: application/json"])
	var payload := {"data": {"display_name": display_name.strip_edges().substr(0, 16)}}
	var error := _request.request("%s/auth/v1/signup" % Config.PROJECT_URL, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		identity_failed.emit(tr("Could not start V2 guest sign-in (code %d).") % error, context)

func _on_signup_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var context := _pending_context
	_pending_context = ""
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8()) if not body.is_empty() else null
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300 or not parsed is Dictionary:
		identity_failed.emit(tr("Could not create a V2 multiplayer identity (HTTP %d).") % response_code, context)
		return
	user_id = str(parsed.get("id", ""))
	access_token = str(parsed.get("access_token", ""))
	expires_at = int(Time.get_unix_time_from_system()) + int(parsed.get("expires_in", 3600))
	is_anonymous = true
	if user_id.is_empty() or access_token.is_empty():
		identity_failed.emit(tr("Supabase returned an incomplete V2 identity."), context)
		return
	identity_ready.emit(user_id, access_token, true, context)

func token() -> String:
	return AuthService.get_access_token() if not is_anonymous and AuthService.is_authenticated else access_token
