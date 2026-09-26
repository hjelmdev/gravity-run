extends Node

const Config = preload("res://systems/leaderboard_config.gd")
const DESKTOP_CALLBACK_PORT := 49173
const DESKTOP_CALLBACK_PATH := "/oauth/callback"
const OAUTH_TIMEOUT_SECONDS := 180.0

signal session_received(session: Dictionary)
signal action_finished(action: String, success: bool, message: String)

var _request: HTTPRequest
var _verifier := ""
var _active_action := ""
var _tcp_server: TCPServer
var _callback_peer: StreamPeerTCP
var _callback_buffer := ""
var _browser_callback_ref: Variant
var _browser_listener_installed := false
var _oauth_elapsed := 0.0
var _popup_closed_elapsed := -1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_request = HTTPRequest.new()
	_request.name = "GoogleOAuthTokenExchange"
	_request.timeout = 25.0
	_request.accept_gzip = false
	add_child(_request)
	_request.request_completed.connect(_on_token_exchange_completed)
	if OS.has_feature("web"):
		_install_browser_callback()

func _process(_delta: float) -> void:
	if _active_action == "google_sign_in":
		_oauth_elapsed += _delta
		if _oauth_elapsed >= OAUTH_TIMEOUT_SECONDS:
			_close_desktop_listener()
			_finish_oauth(tr("Google sign-in timed out. Please try again."))
			return
	if OS.has_feature("web"):
		if _active_action == "google_sign_in":
			var popup_closed := bool(JavaScriptBridge.eval("window.gravityRunOAuthPopup ? window.gravityRunOAuthPopup.closed : false"))
			if popup_closed:
				if _popup_closed_elapsed < 0.0:
					_popup_closed_elapsed = 0.0
				else:
					_popup_closed_elapsed += _delta
				if _popup_closed_elapsed >= 1.5 and _active_action == "google_sign_in":
					_finish_oauth(tr("Google sign-in was cancelled."))
		return
	if not is_instance_valid(_tcp_server):
		return
	if not is_instance_valid(_callback_peer) and _tcp_server.is_connection_available():
		_callback_peer = _tcp_server.take_connection()
		_callback_buffer = ""
	if not is_instance_valid(_callback_peer):
		return
	_callback_peer.poll()
	var byte_count := _callback_peer.get_available_bytes()
	if byte_count <= 0:
		return
	var received: Array = _callback_peer.get_data(byte_count)
	if int(received[0]) != OK:
		_finish_desktop_callback(tr("Could not read the Google sign-in response."))
		return
	_callback_buffer += (received[1] as PackedByteArray).get_string_from_utf8()
	if "\r\n" not in _callback_buffer:
		return
	var request_line := _callback_buffer.get_slice("\r\n", 0)
	var parts := request_line.split(" ")
	if parts.size() < 2 or parts[0] != "GET":
		_finish_desktop_callback(tr("Invalid Google sign-in response."))
		return
	var target := str(parts[1])
	if not target.begins_with(DESKTOP_CALLBACK_PATH + "?"):
		_finish_desktop_callback(tr("Unexpected Google sign-in callback address."))
		return
	var params := _parse_query(target.get_slice("?", 1))
	_send_callback_page()
	_close_desktop_listener()
	if params.has("error"):
		_active_action = ""
		_verifier = ""
		action_finished.emit("google_sign_in", false, str(params.get("error_description", params.get("error", tr("Google sign-in was cancelled.")))))
	elif params.has("code"):
		_exchange_code(str(params["code"]))
	else:
		_active_action = ""
		_verifier = ""
		action_finished.emit("google_sign_in", false, tr("Google did not return an authorization code."))

func sign_in() -> void:
	if not _active_action.is_empty() or _request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		action_finished.emit("google_sign_in", false, tr("An account request is already running."))
		return
	var crypto := Crypto.new()
	_verifier = _base64url(crypto.generate_random_bytes(32))
	var hashing := HashingContext.new()
	var hash_error := hashing.start(HashingContext.HASH_SHA256)
	if hash_error != OK:
		_verifier = ""
		action_finished.emit("google_sign_in", false, tr("Could not prepare secure Google sign-in."))
		return
	hashing.update(_verifier.to_utf8_buffer())
	var challenge := _base64url(hashing.finish())
	var redirect_uri := Config.AUTH_REDIRECT_URL
	if not OS.has_feature("web"):
		if not _start_desktop_listener():
			action_finished.emit("google_sign_in", false, tr("Could not open the local sign-in callback. Close anything using port %d and try again.") % DESKTOP_CALLBACK_PORT)
			return
		redirect_uri = "http://127.0.0.1:%d%s" % [DESKTOP_CALLBACK_PORT, DESKTOP_CALLBACK_PATH]
	var query := "provider=google&scopes=%s&redirect_to=%s&code_challenge=%s&code_challenge_method=s256&apikey=%s" % ["openid email profile".uri_encode(), redirect_uri.uri_encode(), challenge.uri_encode(), Config.PUBLISHABLE_KEY.uri_encode()]
	var authorize_url := "%s/auth/v1/authorize?%s" % [Config.PROJECT_URL, query]
	_active_action = "google_sign_in"
	_oauth_elapsed = 0.0
	_popup_closed_elapsed = -1.0
	if OS.has_feature("web"):
		_open_browser_popup(authorize_url)
	else:
		var error := OS.shell_open(authorize_url)
		if error != OK:
			_close_desktop_listener()
			_active_action = ""
			action_finished.emit("google_sign_in", false, tr("Could not open the system browser (code %d).") % error)

func _open_browser_popup(authorize_url: String) -> void:
	var js_url := JSON.stringify(authorize_url)
	var result: Variant = JavaScriptBridge.eval("window.gravityRunOAuthPopup = window.open(%s, 'gravity-run-google-auth', 'popup,width=520,height=700'); window.gravityRunOAuthPopup ? 'opened' : 'blocked'" % js_url)
	if str(result) == "blocked":
		_active_action = ""
		_verifier = ""
		action_finished.emit("google_sign_in", false, tr("Your browser blocked the sign-in window. Allow pop-ups and try again."))

func _install_browser_callback() -> void:
	if _browser_listener_installed:
		return
	_browser_callback_ref = JavaScriptBridge.create_callback(_on_browser_message)
	var window := JavaScriptBridge.get_interface("window")
	window.set("gravityRunOAuthCallback", _browser_callback_ref)
	JavaScriptBridge.eval("window.addEventListener('message', function(event) { if (event.origin === window.location.origin && typeof event.data === 'string' && event.data.indexOf('gravity-run-oauth|') === 0) window.gravityRunOAuthCallback(event.data); });")
	_browser_listener_installed = true

func _on_browser_message(args: Array) -> void:
	if args.is_empty() or _active_action != "google_sign_in":
		return
	var message := str(args[0])
	if message.begins_with("gravity-run-oauth|code|"):
		var value := message.trim_prefix("gravity-run-oauth|code|").uri_decode()
		if value.is_empty():
			_finish_oauth(tr("Google did not return an authorization code."))
			return
		_exchange_code(value)
	elif message.begins_with("gravity-run-oauth|error|"):
		var value := message.trim_prefix("gravity-run-oauth|error|").uri_decode()
		_finish_oauth(value if not value.is_empty() else tr("Google sign-in was cancelled."))

func _start_desktop_listener() -> bool:
	_tcp_server = TCPServer.new()
	var error := _tcp_server.listen(DESKTOP_CALLBACK_PORT, "127.0.0.1")
	if error != OK:
		_tcp_server = null
		return false
	return true

func _send_callback_page() -> void:
	if not is_instance_valid(_callback_peer):
		return
	var page := "<!doctype html><meta charset=utf-8><title>Gravity Run</title><body style='background:#101827;color:#edf3ff;font:18px sans-serif;text-align:center;padding:15vh 1em'>Google sign-in received. You can close this tab and return to Gravity Run.</body>"
	var response := "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: %d\r\n\r\n%s" % [page.to_utf8_buffer().size(), page]
	_callback_peer.put_data(response.to_utf8_buffer())

func _close_desktop_listener() -> void:
	if is_instance_valid(_callback_peer):
		_callback_peer.disconnect_from_host()
	_callback_peer = null
	if is_instance_valid(_tcp_server):
		_tcp_server.stop()
	_tcp_server = null
	_callback_buffer = ""

func _parse_query(query: String) -> Dictionary:
	var values := {}
	for pair in query.split("&"):
		var equal_at := pair.find("=")
		if equal_at < 0:
			continue
		values[pair.substr(0, equal_at).uri_decode()] = pair.substr(equal_at + 1).uri_decode()
	return values

func _exchange_code(auth_code: String) -> void:
	if _request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	var headers := PackedStringArray(["apikey: " + Config.PUBLISHABLE_KEY, "Content-Type: application/json", "Accept: application/json"])
	var payload := JSON.stringify({"auth_code": auth_code, "code_verifier": _verifier})
	var error := _request.request(Config.PROJECT_URL + "/auth/v1/token?grant_type=pkce", headers, HTTPClient.METHOD_POST, payload)
	if error != OK:
		_active_action = ""
		_verifier = ""
		action_finished.emit("google_sign_in", false, tr("Could not start Google session exchange (code %d).") % error)
		return
	_active_action = "google_exchange"

func _on_token_exchange_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var response_text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(response_text) if not response_text.is_empty() else {}
	if result != HTTPRequest.RESULT_SUCCESS:
		_finish_oauth(tr("Network error while completing Google sign-in (code %d).") % result)
		return
	if response_code < 200 or response_code >= 300:
		var detail := str(parsed.get("msg", parsed.get("message", ""))) if parsed is Dictionary else ""
		_finish_oauth(tr("Google sign-in failed (HTTP %d). %s") % [response_code, detail])
		return
	if not parsed is Dictionary or not parsed.has("access_token") or not parsed.has("refresh_token"):
		_finish_oauth(tr("Google sign-in returned an incomplete session."))
		return
	_verifier = ""
	_active_action = ""
	session_received.emit(parsed)
	action_finished.emit("google_sign_in", true, tr("Signed in successfully."))

func _finish_desktop_callback(_message: String) -> void:
	_send_callback_page()
	_close_desktop_listener()
	_finish_oauth(_message)

func _finish_oauth(message: String) -> void:
	_active_action = ""
	_verifier = ""
	_popup_closed_elapsed = -1.0
	action_finished.emit("google_sign_in", false, message)

func _base64url(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").trim_suffix("=").trim_suffix("=")
