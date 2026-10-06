extends Node

const HubScene := preload("res://ui/game_hub.tscn")
const LobbyScene := preload("res://ui/multiplayer_v2/multiplayer_v2_lobby.tscn")
const CourseGenerator := preload("res://systems/course_generator.gd")

var failures := 0
var start_count := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var mobile_entry: Node = get_tree().root.get_node("MobileTextEntry")
	mobile_entry.set("is_mobile_web", true)
	var challenge: Node = get_tree().root.get_node("ChallengeService")
	challenge.call("clear_challenge")
	var hub := HubScene.instantiate() as Control
	get_tree().root.add_child(hub)
	await get_tree().process_frame
	var hub_edit := hub.get("_seed_edit") as LineEdit
	var hub_button := hub.get("_seed_mobile_button") as Button
	_check(not hub_edit.visible and hub_button != null and hub_button.visible, "mobile hub replaces the raw seed LineEdit with the shared text-entry launcher")
	_check(hub.get_viewport().get_visible_rect().intersects(hub_button.get_global_rect()), "mobile SP seed launcher is inside the current viewport")
	hub.start_run_requested.connect(_on_hub_start)
	mobile_entry.entry_submitted.emit("singleplayer_seed", "GR16-100000014")
	_check(hub_edit.text == "GR16-100000014" and hub_button.text == hub_edit.text, "shared editor result returns the full frozen GR seed code to SP input")
	hub_edit.text = "not-a-seed"
	hub.call("_on_seed_input_changed", hub_edit.text)
	hub.call("_start_run")
	_check(start_count == 0 and bool(hub.get("_status_label").visible), "mobile SP field retains existing invalid-seed validation")
	mobile_entry.entry_submitted.emit("singleplayer_seed", "100000014")
	hub.call("_start_run")
	_check(start_count == 1 and int(challenge.get("seed_value")) == 100000014 and int(challenge.get("generation_version")) == CourseGenerator.GENERATOR_VERSION, "mobile SP field preserves numeric seed version selection")
	challenge.set("active", true)
	hub.call("_update_account_summary")
	_check(not hub_button.visible and hub_button.disabled, "active challenge cannot be silently replaced through the mobile seed launcher")
	challenge.call("clear_challenge")
	hub.queue_free()
	await get_tree().process_frame
	var portrait_viewport := SubViewport.new()
	portrait_viewport.size = Vector2i(390, 844)
	portrait_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(portrait_viewport)
	var portrait_hub := HubScene.instantiate() as Control
	portrait_hub.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait_viewport.add_child(portrait_hub)
	await get_tree().process_frame
	await get_tree().process_frame
	var portrait_hub_button := portrait_hub.get("_seed_mobile_button") as Button
	_check(portrait_hub_button != null and portrait_hub_button.visible and portrait_viewport.get_visible_rect().intersects(portrait_hub_button.get_global_rect()), "portrait Hub keeps the mobile seed launcher in its viewport")
	portrait_hub.queue_free()
	portrait_viewport.queue_free()
	await get_tree().process_frame

	var lobby := LobbyScene.instantiate() as Control
	var lobby_viewport := SubViewport.new()
	lobby_viewport.size = Vector2i(390, 844)
	lobby_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(lobby_viewport)
	lobby_viewport.add_child(lobby)
	await get_tree().process_frame
	lobby.call("_show_view", "create")
	await get_tree().process_frame
	var mp_seed := lobby.get("_seed_edit") as LineEdit
	var mp_seed_button := lobby.get("_seed_button") as Button
	_check(not mp_seed.visible and mp_seed_button != null and mp_seed_button.visible, "mobile MP create view replaces raw numeric seed LineEdit with shared launcher")
	_check(lobby.get_viewport().get_visible_rect().intersects(mp_seed_button.get_global_rect()), "mobile MP seed launcher is inside the lobby viewport")
	mobile_entry.entry_submitted.emit("course_seed", "2147483647")
	_check(mp_seed.text == "2147483647" and mp_seed_button.text == mp_seed.text, "mobile MP seed callback preserves the numeric field contract")
	_check(mp_seed.text.is_valid_int() and mp_seed.text.to_int() <= 2_147_483_647, "valid upper-bound MP seed retains the accepted numeric range")
	mobile_entry.entry_submitted.emit("course_seed", "2147483648")
	lobby.call("_create_room")
	_check(str(lobby.get("_status").text).contains("2147483647"), "out-of-range mobile MP seed is rejected by the existing validator")
	lobby.call("_show_view", "join")
	mobile_entry.entry_submitted.emit("room_code", "ABCD1234EXTRA")
	_check(str(lobby.get("_room_code").text) == "ABCD1234" and str(lobby.get("_room_code_button").text) == "ABCD1234", "shared text-entry callback keeps room-code limit")
	lobby_viewport.size = Vector2i(844, 390)
	await get_tree().process_frame
	lobby.call("_show_view", "create")
	_check(lobby_viewport.get_visible_rect().intersects(mp_seed_button.get_global_rect()), "landscape MP lobby keeps the mobile seed launcher inside its viewport")
	lobby.queue_free()
	lobby_viewport.queue_free()
	await get_tree().process_frame
	challenge.call("clear_challenge")
	print("MOBILE_SEED_ENTRY_INTEGRATION_TEST failures=%d mobile_overlay_simulated=true" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _on_hub_start() -> void:
	start_count += 1

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: " + message)
