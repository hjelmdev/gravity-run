extends Node

const Service := preload("res://systems/multiplayer_v2/multiplayer_v2_service.gd")
const Match := preload("res://ui/multiplayer_v2/multiplayer_v2_match.gd")
const Menu := preload("res://ui/main_menu.tscn")
const Exporter := preload("res://systems/multiplayer_v2/v2_diagnostics_export.gd")

class SampleProbe extends Service:
	var sent := 0
	func _ready() -> void:
		_create_network_branch()
		set_process(false)
	func _validate_local_peer_mapping(_stage: String) -> bool:
		return true
	func _send_position_sample(_target: int, _sample: Dictionary) -> void:
		sent += 1
	func send_control(_peer: int, _kind: String, _payload: Dictionary) -> void:
		pass

class OverlayProbe extends Match:
	func _ready() -> void:
		_build_overlay()
		set_process(false)
		set_physics_process(false)
	func _draw() -> void:
		pass

var failures := 0
@onready var root := get_tree().root

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	TranslationServer.set_locale("en")
	_check(root.get_node_or_null("MultiplayerService") == null, "retired V1 service is not an autoload")
	_check(root.get_node_or_null("MultiplayerDiagnostics") == null, "retired V1 diagnostics is not an autoload")
	var menu_scene := Menu.instantiate()
	root.add_child(menu_scene)
	var menu = menu_scene.get_node("MainMenuLayer/MainMenuUI")
	menu._show_game_hub()
	var multiplayer_buttons := 0
	for button in menu._game_hub.find_children("*", "Button", true, false):
		if button.text == "Multiplayer":
			multiplayer_buttons += 1
		_check(not button.text.contains("V2"), "hub has neutral labels")
	_check(multiplayer_buttons == 1, "hub has exactly one multiplayer entry")
	menu._game_hub.multiplayer_requested.emit()
	_check(menu._multiplayer_lobby.get_script().resource_path == "res://ui/multiplayer_v2/multiplayer_v2_lobby.gd", "neutral action opens the active lobby")
	_check(menu.MULTIPLAYER_MATCH_SCENE.resource_path == "res://ui/multiplayer_v2/multiplayer_v2_match.tscn", "neutral race action targets the active match")
	_check(menu._multiplayer_lobby._diagnostics_button.text == "Save diagnostics", "lobby export remains available")
	var navigation = root.get_node("AppNavigation")
	navigation.request_multiplayer_lobby()
	_check(navigation.consume_multiplayer_lobby_request(), "neutral lobby return is delivered")
	_check(not navigation.consume_multiplayer_lobby_request(), "lobby return is consumed once")
	var overlay := OverlayProbe.new()
	root.add_child(overlay)
	_check(overlay.find_children("*", "OptionButton", true, false).is_empty(), "match has no rate selector")
	var export_buttons := 0
	for button in overlay.find_children("*", "Button", true, false):
		if button.text == "Save diagnostics": export_buttons += 1
	_check(export_buttons == 1, "match export remains available")
	var probe := SampleProbe.new()
	root.add_child(probe)
	probe.session = {"local_peer_id": 2}
	probe._sample_period = 1.0 / 60.0
	probe.activate_client_session({"room_id": "rate-probe", "room_session_id": "session", "roster_revision": 1})
	_check(probe.get_snapshot_rate() == 30, "session activation resets an old experiment rate")
	_check(probe.diagnostics.export_report().session.position_rate_hz == 30, "rate is recorded before any menu interaction")
	for round_index in 2:
		probe.begin_round("probe-%d" % round_index, 1)
		var before := probe.sent
		for tick in 600:
			probe._process(1.0 / 60.0)
			probe.send_sample({"simulation_tick": tick})
		var count := probe.sent - before
		_check(count >= 299 and count <= 301, "sender emits 30 Hz over ten simulated seconds, including rematch (%d)" % count)
	var filename := Exporter.make_filename(probe.diagnostics.export_report(), "match")
	_check(filename.begins_with("multiplayer_match_") and not filename.contains("v2"), "download filename has neutral prefix")
	TranslationServer.set_locale("sv")
	_check(str(TranslationServer.translate("Save diagnostics")) == "Spara diagnostik", "neutral Swedish export label loads")
	_check(str(TranslationServer.translate("Round aborted")) == "Rundan avbröts", "neutral Swedish abort label loads")
	probe.free()
	overlay.free()
	menu_scene.free()
	if failures == 0: print("Multiplayer retirement tests passed (routing, UI, diagnostics and two 10-second send windows).")
	get_tree().quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
