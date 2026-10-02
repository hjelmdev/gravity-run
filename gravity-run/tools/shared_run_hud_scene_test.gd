extends Node

const MainScene := preload("res://main.tscn")
const SharedHudScene := preload("res://ui/shared_run_hud.tscn")
const MpHudLayout := preload("res://ui/multiplayer_v2/v2_hud_layout.gd")

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures: Array[String] = []
	get_viewport().size = Vector2(960, 540)
	var game: Node = MainScene.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var sp_hud: Control = game.get_node("HUDLayer/HUD/SharedRunHud")
	var sp_coin: Control = sp_hud.get_node("CoinIcon")
	var sp_music: Control = sp_hud.get_node("MusicQuickControl")
	var sp_speaker: Control = sp_music.get_node("MusicToggle")
	var sp_expand: Control = sp_music.get_node("MusicVolumeExpand")
	var sp_distance: Control = sp_hud.get_node("Distance")
	if sp_coin.size == Vector2.ZERO: failures.append("SP shared coin icon has no rendered area")
	if not sp_distance.visible: failures.append("SP shared header lost its distance capability")
	if sp_expand.text != "" or sp_expand.get_node_or_null("ChevronIcon") == null: failures.append("volume expander still depends on a font glyph")
	var sp_pause: Node = game.get_node("PauseMenu")
	for child in sp_pause.get_children():
		if child is Button and (sp_speaker.get_global_rect().intersects(child.get_global_rect()) or sp_expand.get_global_rect().intersects(child.get_global_rect())):
			failures.append("SP top-right music control overlaps pause/menu action %s" % child.name)
	var mp_hud := SharedHudScene.instantiate() as Control
	add_child(mp_hud)
	mp_hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	mp_hud.size = get_viewport().get_visible_rect().size
	mp_hud.call("set_show_distance", false)
	var landscape_layout: Dictionary = MpHudLayout.for_viewport(mp_hud.size)
	var landscape_music_rect: Rect2 = landscape_layout.music_button
	mp_hud.call("set_music_right_offset", landscape_music_rect.position.x - mp_hud.size.x)
	mp_hud.call("set_music_toolbar_top", landscape_music_rect.position.y, landscape_music_rect.size.y)
	mp_hud.call("set_coins", 8)
	await get_tree().process_frame
	var mp_coin: Control = mp_hud.get_node("CoinIcon")
	var mp_music: Control = mp_hud.get_node("MusicQuickControl")
	var mp_speaker: Control = mp_music.get_node("MusicToggle")
	var mp_expand: Control = mp_music.get_node("MusicVolumeExpand")
	var mp_distance: Control = mp_hud.get_node("Distance")
	var mp_menu_button := Button.new()
	add_child(mp_menu_button)
	var landscape_menu_rect: Rect2 = landscape_layout.button
	mp_menu_button.position = landscape_menu_rect.position
	mp_menu_button.size = landscape_menu_rect.size
	if mp_distance.visible: failures.append("MP capability exposed distance")
	if mp_coin.get_global_rect() != sp_coin.get_global_rect(): failures.append("SP and MP shared coin icon layouts differ")
	if mp_speaker.get_global_rect().size != sp_speaker.get_global_rect().size or mp_expand.get_global_rect().size != sp_expand.get_global_rect().size: failures.append("SP and MP shared music control sizes differ")
	var viewport_size := get_viewport().get_visible_rect().size
	if not Rect2(Vector2.ZERO, viewport_size).encloses(mp_speaker.get_global_rect()) or not Rect2(Vector2.ZERO, viewport_size).encloses(mp_expand.get_global_rect()): failures.append("MP shared music controls are outside the actual viewport")
	if not is_equal_approx(mp_speaker.get_global_rect().get_center().y, landscape_menu_rect.get_center().y) or not is_equal_approx(mp_expand.get_global_rect().get_center().y, landscape_menu_rect.get_center().y): failures.append("MP menu/speaker/expander centers differ in landscape: menu=%s speaker=%s arrow=%s" % [str(landscape_menu_rect), str(mp_speaker.get_global_rect()), str(mp_expand.get_global_rect())])
	var landscape_toolbar_gap: float = landscape_menu_rect.position.x - mp_speaker.get_global_rect().end.x
	if landscape_toolbar_gap < 8.0 or landscape_toolbar_gap > 12.0: failures.append("MP audio group/menu gap outside 8-12px in landscape: %.2fpx" % landscape_toolbar_gap)
	var count: Label = mp_hud.get_node("CoinCount")
	if count.text != "08": failures.append("shared coin counter did not render its mode-neutral count")
	get_viewport().size = Vector2(540, 960)
	mp_hud.size = get_viewport().get_visible_rect().size
	await get_tree().process_frame
	await get_tree().process_frame
	viewport_size = get_viewport().get_visible_rect().size
	var mp_layout: Dictionary = MpHudLayout.for_viewport(viewport_size)
	var mp_menu_rect: Rect2 = mp_layout.button
	var mp_music_rect: Rect2 = mp_layout.music_button
	mp_hud.call("set_music_right_offset", mp_music_rect.position.x - viewport_size.x)
	mp_hud.call("set_music_toolbar_top", mp_music_rect.position.y, mp_music_rect.size.y)
	mp_menu_button.position = mp_menu_rect.position
	mp_menu_button.size = mp_menu_rect.size
	await get_tree().process_frame
	for control in [sp_speaker, sp_expand, mp_speaker, mp_expand]:
		if not Rect2(Vector2.ZERO, viewport_size).encloses(control.get_global_rect()):
			failures.append("shared audio control %s outside %s: %s" % [control.name, str(viewport_size), str(control.get_global_rect())])
	for child in sp_pause.get_children():
		if child is Button and (sp_speaker.get_global_rect().intersects(child.get_global_rect()) or sp_expand.get_global_rect().intersects(child.get_global_rect())):
			failures.append("SP top-right controls overlap after portrait resize")
	if mp_speaker.get_global_rect().intersects(mp_menu_button.get_global_rect()) or mp_expand.get_global_rect().intersects(mp_menu_button.get_global_rect()):
		failures.append("MP shared audio controls overlap the actual menu allocation: speaker=%s expand=%s menu=%s offset=%s" % [str(mp_speaker.get_global_rect()), str(mp_expand.get_global_rect()), str(mp_menu_button.get_global_rect()), str(mp_music.get("right_offset"))])
	if not is_equal_approx(mp_speaker.get_global_rect().get_center().y, mp_menu_rect.get_center().y) or not is_equal_approx(mp_expand.get_global_rect().get_center().y, mp_menu_rect.get_center().y): failures.append("MP menu/speaker/expander centers differ in portrait: menu=%s speaker=%s arrow=%s" % [str(mp_menu_rect), str(mp_speaker.get_global_rect()), str(mp_expand.get_global_rect())])
	var portrait_toolbar_gap: float = mp_menu_rect.position.x - mp_speaker.get_global_rect().end.x
	if portrait_toolbar_gap < 8.0 or portrait_toolbar_gap > 12.0: failures.append("MP audio group/menu gap outside 8-12px in portrait: %.2fpx" % portrait_toolbar_gap)
	var mp_status_rect: Rect2 = mp_layout.status
	if mp_speaker.get_global_rect().intersects(mp_status_rect) or mp_expand.get_global_rect().intersects(mp_status_rect):
		failures.append("MP shared audio controls overlap the status allocation")
	if failures.is_empty():
		print("shared_run_hud_scene_test: PASS scene-backed SP and MP shared HUD/audio component at 960x540 and 540x960")
	else:
		for failure in failures: push_error(failure)
	get_tree().quit(1 if not failures.is_empty() else 0)
