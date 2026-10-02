extends SceneTree

const MusicControl := preload("res://ui/music_quick_control.gd")
const HudLayout := preload("res://ui/multiplayer_v2/v2_hud_layout.gd")

var failures := 0
var original_enabled := true
var original_volume := 0.5
var parent_control: Control
var music_control: Control
var profile: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	profile = root.get_node_or_null("PlayerProfile")
	_check(profile != null, "project music profile autoload is available to HUD")
	if profile == null:
		quit(1)
		return
	original_enabled = bool(profile.get("music_enabled"))
	original_volume = float(profile.get("music_volume"))
	parent_control = Control.new()
	parent_control.name = "HudTestViewport"
	root.add_child(parent_control)
	music_control = Control.new()
	music_control.set_script(MusicControl)
	parent_control.add_child(music_control)
	await process_frame
	for viewport_size in [Vector2(960, 540), Vector2(540, 960)]:
		parent_control.position = Vector2.ZERO
		parent_control.size = viewport_size
		var mp_layout: Dictionary = HudLayout.for_viewport(viewport_size)
		var mp_music_rect: Rect2 = mp_layout.music_button
		music_control.call("set_right_offset", mp_music_rect.position.x - viewport_size.x)
		music_control.call("_layout")
		await process_frame
		var speaker: Control = music_control.get("_button")
		var expander: Control = music_control.get("_expand_button")
		var panel: Control = music_control.get("_panel")
		var mp_status: Rect2 = mp_layout.status
		var mp_music_group: Rect2 = expander.get_global_rect().merge(speaker.get_global_rect())
		_check(_inside(speaker.get_global_rect(), viewport_size), "speaker button fits %s HUD" % _orientation(viewport_size))
		_check(_inside(expander.get_global_rect(), viewport_size), "touch slider expander fits %s HUD" % _orientation(viewport_size))
		_check(speaker.size.x >= 40.0 and speaker.size.y >= 40.0, "speaker remains a visible touch target in %s HUD" % _orientation(viewport_size))
		_check(expander.size.x >= 28.0 and expander.size.y >= 40.0, "separate touch volume control remains usable in %s HUD" % _orientation(viewport_size))
		_check(not mp_status.intersects(mp_music_group), "MP prepare/status text does not overlap speaker or expander in %s HUD" % _orientation(viewport_size))
		music_control.call("_layout")
		_check(_inside(panel.get_global_rect(), viewport_size), "volume popover fits %s HUD" % _orientation(viewport_size))
		music_control.call("set_right_offset", -196.0)
		music_control.call("_layout")
		await process_frame
		var sp_speaker: Control = music_control.get("_button")
		var sp_expander: Control = music_control.get("_expand_button")
		_check(_inside(sp_speaker.get_global_rect(), viewport_size) and _inside(sp_expander.get_global_rect(), viewport_size), "shared pause-menu controls fit %s SP HUD" % _orientation(viewport_size))
		_check(not sp_speaker.get_global_rect().intersects(Rect2(viewport_size.x - 148.0, 6.0, 40.0, 40.0)), "SP speaker does not overlap inventory button in %s HUD" % _orientation(viewport_size))
	var button: Button = music_control.get("_button")
	var expander_button: Button = music_control.get("_expand_button")
	var slider: HSlider = music_control.get("_slider")
	var panel: Control = music_control.get("_panel")
	var toggled_to := not bool(profile.get("music_enabled"))
	button.pressed.emit()
	_check(bool(profile.get("music_enabled")) == toggled_to, "speaker click toggles the real music_enabled setting")
	_check(is_equal_approx(float(profile.get("music_volume")), original_volume), "speaker mute toggle preserves saved volume")
	music_control.call("_on_control_mouse_entered")
	_check(panel.visible, "desktop hover opens volume popover")
	music_control.call("_on_control_mouse_exited")
	music_control.call("_on_control_mouse_entered")
	await create_timer(0.22).timeout
	_check(panel.visible, "moving from speaker toward the popover keeps it open")
	var enabled_before_slider := bool(profile.get("music_enabled"))
	var next_volume := 33.0 if original_volume > 0.33 else 67.0
	slider.value = next_volume
	_check(bool(profile.get("music_enabled")) == enabled_before_slider, "volume slider does not toggle mute")
	_check(is_equal_approx(float(profile.get("music_volume")), next_volume / 100.0), "volume slider updates the real profile volume")
	panel.visible = false
	expander_button.pressed.emit()
	_check(panel.visible, "separate expansion button opens touch volume controls")
	expander_button.pressed.emit()
	_check(not panel.visible, "touch expansion control closes the volume popover")
	button.grab_focus()
	_check(panel.visible, "keyboard focus on speaker opens volume controls")
	button.release_focus()
	# Restore profile state before leaving the fixture.
	profile.call("set_music_enabled", original_enabled)
	profile.call("set_music_volume", original_volume)
	profile.call("flush_settings")
	print("music_quick_control_layout_test failures=%d" % failures)
	quit(0 if failures == 0 else 1)

func _inside(rect: Rect2, viewport_size: Vector2) -> bool:
	return rect.size.x > 0.0 and rect.size.y > 0.0 and rect.position.x >= -0.5 and rect.position.y >= -0.5 and rect.end.x <= viewport_size.x + 0.5 and rect.end.y <= viewport_size.y + 0.5

func _orientation(size_value: Vector2) -> String:
	return "portrait" if size_value.x < size_value.y else "landscape"

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: %s" % description)
	else:
		failures += 1
		push_error("FAIL: %s" % description)
