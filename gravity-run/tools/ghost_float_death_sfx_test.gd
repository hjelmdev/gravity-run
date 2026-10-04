extends Node

const GhostScene := preload("res://hazards/ghost_hazard.tscn")
const MatchScript := preload("res://ui/multiplayer_v2/multiplayer_v2_match.gd")

class TestMatch extends MatchScript:
	func _update_spectator_camera() -> void:
		pass

class TestRunner extends RefCounted:
	var player_state := {"state": "running"}
	func stop(state: String) -> void:
		player_state.state = state

var failures := 0
var deaths := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var profile := PlayerProfile
	var enabled := profile.sfx_enabled
	var volume := profile.sfx_volume
	profile.sfx_enabled = true
	profile.sfx_volume = 0.5
	SfxController._apply_settings()
	SfxController.event_started.connect(_on_sound)
	var ghost := GhostScene.instantiate()
	add_child(ghost)
	ghost.configure({"event_id": "test", "x": 800.0, "width": 72.0, "height": 96.0, "floor_y": 460.0, "ceiling_y": 80.0})
	ghost.set_activation_tick(0)
	ghost.set_simulation_tick(120)
	var anchor: Vector2 = ghost.global_position
	var collision: Rect2 = ghost.get_hitbox_rect()
	ghost._process(0.7)
	_check(ghost.visual_offset().length() > 2.0, "visible body floats")
	_check(ghost.global_position == anchor and ghost.get_hitbox_rect() == collision, "floating never moves anchored collision")
	ghost.configure(ghost.event)
	_check(ghost.visual_offset() == Vector2.ZERO, "new event resets cosmetic phase")
	SfxController.begin_round("death-test")
	var match_view := TestMatch.new()
	match_view._round_id = "death-test"
	match_view._runner = TestRunner.new()
	var saved_session := MultiplayerV2Service.session.duplicate(true)
	MultiplayerV2Service.session["local_peer_id"] = 1
	match_view._on_terminal_report(1, {"state": "dead"})
	match_view._on_terminal_report(1, {"state": "dead"})
	_check(deaths == 1, "actual MP callback repeated death report plays once")
	match_view._on_terminal_report(2, {"state": "dead"})
	_check(deaths == 1, "another player's death is silent")
	_check(not SfxController.play_death("old-round", "local"), "old round cannot play death")
	SfxController.begin_round("death-muted")
	profile.sfx_enabled = false
	SfxController._apply_settings()
	_check(not SfxController.play_death("death-muted", "local"), "mute blocks death")
	profile.sfx_enabled = true
	SfxController._apply_settings()
	_check(not SfxController.play_death("death-muted", "local"), "unmute does not replay a dead player's event")
	SfxController.begin_round("death-next")
	_check(SfxController.play_death("death-next", "local") and deaths == 2, "next round can play a new death")
	MultiplayerV2Service.session = saved_session
	profile.sfx_enabled = enabled
	profile.sfx_volume = volume
	SfxController._apply_settings()
	SfxController.stop_all()
	ghost.queue_free()
	match_view.free()
	print("GHOST_FLOAT_DEATH_SFX_TEST failures=%d deaths=%d" % [failures, deaths])
	get_tree().quit(1 if failures else 0)

func _on_sound(event_name: String, _key: String) -> void:
	if event_name == "death":
		deaths += 1

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
