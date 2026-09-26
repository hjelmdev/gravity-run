extends Node

const Config = preload("res://systems/leaderboard_config.gd")

signal request_finished(action: String, success: bool, data: Variant, message: String, context: String)

var _load_request: HTTPRequest
var _write_request: HTTPRequest
var _load_context := ""
var _write_context := ""
var _write_action := ""

func _ready() -> void:
	_load_request = _make_request("InventoryRead")
	_write_request = _make_request("InventoryWrite")
	_load_request.request_completed.connect(_on_load_completed)
	_write_request.request_completed.connect(_on_write_completed)

func load_inventory(access_token: String, user_id: String) -> void:
	_start(_load_request, "load_inventory", "get_my_inventory_state", {}, access_token, user_id)

func purchase_item(item_id: String, request_id: String, access_token: String, context: String) -> void:
	_start(_write_request, "purchase_item", "purchase_item", {
		"p_item_id": item_id,
		"p_request_id": request_id,
	}, access_token, context)

func equip_item(instance_id: String, slot_type: String, access_token: String, context: String) -> void:
	_start(_write_request, "equip_item", "equip_item", {
		"p_instance_id": instance_id,
		"p_slot_type": slot_type,
	}, access_token, context)

func unequip_item(slot_type: String, access_token: String, context: String) -> void:
	_start(_write_request, "unequip_item", "unequip_item", {
		"p_slot_type": slot_type,
	}, access_token, context)

func _make_request(request_name: String) -> HTTPRequest:
	var request := HTTPRequest.new()
	request.name = request_name
	request.timeout = 20.0
	request.accept_gzip = false
	request.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(request)
	return request

func _start(request: HTTPRequest, action: String, rpc_name: String, payload: Dictionary, access_token: String, context: String) -> void:
	if request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		request_finished.emit(action, false, null, tr("An inventory request is already in progress."), context)
		return
	if request == _load_request:
		_load_context = context
	else:
		_write_context = context
		_write_action = action
	var headers := PackedStringArray([
		"apikey: " + Config.PUBLISHABLE_KEY,
		"Authorization: Bearer " + access_token,
		"Content-Type: application/json",
		"Accept: application/json",
	])
	var url := "%s/rest/v1/rpc/%s" % [Config.PROJECT_URL, rpc_name]
	var error := request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		request_finished.emit(action, false, null, tr("Could not start the inventory request (code %d).") % error, context)

func _on_load_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_handle_completed("load_inventory", result, response_code, body, _load_context)

func _on_write_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_handle_completed(_write_action, result, response_code, body, _write_context)

func _handle_completed(action: String, result: int, response_code: int, body: PackedByteArray, context: String) -> void:
	var response_text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(response_text) if not response_text.is_empty() else null
	if result != HTTPRequest.RESULT_SUCCESS:
		request_finished.emit(action, false, null, tr("Network error while contacting inventory (code %d).") % result, context)
		return
	if response_code < 200 or response_code >= 300:
		request_finished.emit(action, false, null, _friendly_error(parsed, response_code), context)
		return
	if not parsed is Dictionary:
		request_finished.emit(action, false, null, tr("The inventory service returned an unexpected response."), context)
		return
	request_finished.emit(action, true, parsed, "", context)

func _friendly_error(response: Variant, response_code: int) -> String:
	var detail := ""
	if response is Dictionary:
		detail = str(response.get("message", response.get("details", ""))).to_lower()
	if "not_authenticated" in detail or response_code == 401 or response_code == 403:
		return tr("Your session expired. Please sign in again.")
	if "insufficient_coins" in detail:
		return tr("You do not have enough coins for this item.")
	if "item_already_owned" in detail:
		return tr("You already own this item.")
	if "item_not_for_sale" in detail:
		return tr("This item is not available in the shop.")
	if "item_not_owned" in detail:
		return tr("This item is not in your inventory.")
	if "item_wrong_slot" in detail or "invalid_equipment_slot" in detail:
		return tr("This item cannot be equipped in that slot.")
	if "item_already_equipped" in detail:
		return tr("This item is already equipped in another slot.")
	return tr("Inventory request failed (HTTP %d). %s") % [response_code, detail]
