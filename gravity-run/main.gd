extends Node2D

@export var demo_mode := false

var screen_width := 960.0
var screen_height := 540.0
const RUNNER_MOTION_SCRIPT := preload("res://systems/runner_motion.gd")
const HAZARD_RULES_SCRIPT := preload("res://systems/hazard_interaction_rules.gd")
const COURSE_GENERATOR_SCRIPT := preload("res://systems/course_generator.gd")
const RUN_SPEED_BASE := RUNNER_MOTION_SCRIPT.BASE_RUN_SPEED
const COIN_DISTANCE := 720.0
const WORLD_WIDTH := 960.0
const WORLD_HEIGHT := 540.0
const SLOPE_WIDTH := COURSE_GENERATOR_SCRIPT.SLOPE_WIDTH
const PLAYER_X := 180.0
const SPIKE_WIDTH := COURSE_GENERATOR_SCRIPT.SPIKE_WIDTH
const SPIKE_HEIGHT := COURSE_GENERATOR_SCRIPT.SPIKE_HEIGHT
const SPIKE_GROUP_SPACING := COURSE_GENERATOR_SCRIPT.SPIKE_GROUP_SPACING
const STEP_SPIKE_CLEARANCE := COURSE_GENERATOR_SCRIPT.STEP_SPIKE_CLEARANCE
const DEMO_AI_LOOKAHEAD := 700.0
const SPIKE_SCENE := preload("res://hazards/spikes.tscn")
const BLOCK_SCENE := preload("res://hazards/block.tscn")
const BARREL_SCENE := preload("res://hazards/barrel.tscn")
const COIN_SCENE := preload("res://collectibles/coin.tscn")
const LOOT_PICKUP_SCENE := preload("res://collectibles/loot_pickup.tscn")
const LOOT_PLANNER_SCRIPT := preload("res://systems/loot_spawn_planner.gd")
const SHARED_COIN_PLANNER_SCRIPT := preload("res://systems/shared_coin_planner.gd")
const RUN_EFFECTS_SCRIPT := preload("res://systems/run_effects.gd")
const ANCHOR_BUTTON_SCRIPT := preload("res://ui/anchor_touch_button.gd")
const FALLING_ROCK_SCENE := preload("res://hazards/falling_rock.tscn")
const FALLING_ROCK_MODEL := preload("res://systems/falling_rock_model.gd")
const SAW_BLADE_SCENE := preload("res://hazards/saw_blade.tscn")
const SAW_BLADE_MODEL := preload("res://systems/saw_blade_model.gd")
const GHOST_HAZARD_SCENE := preload("res://hazards/ghost_hazard.tscn")
const GHOST_HAZARD_MODEL := preload("res://systems/ghost_hazard_model.gd")
const LAVA_HAZARD_SCENE := preload("res://hazards/lava_hazard.tscn")
const COURSE_SURFACE_INDEX_SCRIPT := preload("res://systems/course_surface_index.gd")
const ROCK_WARNING_ICON_SCRIPT := preload("res://systems/rock_warning_icon.gd")
const ROCK_WARNING_PULSE_SCRIPT := preload("res://systems/rock_warning_pulse.gd")
const GHOST_WARNING_PULSE_SCRIPT := preload("res://systems/ghost_warning_pulse.gd")
const MANIFEST_BUILDER_SCRIPT := preload("res://systems/course_manifest_builder.gd")
const RUN_LOOT_ENABLED := false
const SLOPE_SCENE := preload("res://terrain/slope.tscn")
const LEDGE_SCENE := preload("res://terrain/ledge.tscn")
const COURSE_RULESET_SCRIPT := preload("res://systems/course_generation_ruleset.gd")
const COURSE_RUN_DEFINITION_SCRIPT := preload("res://systems/course_run_definition.gd")
const TRACK_GAP_SCRIPT := preload("res://terrain/track_gap.gd")
const COURSE_SURFACE_RENDERER := preload("res://systems/course_surface_renderer.gd")
const BIOME_RENDERER_SCRIPT := preload("res://biomes/biome_renderer.gd")
const CoursePresentation := preload("res://systems/race_course_presentation.gd")
const SfxAudibilityRules := preload("res://systems/sfx_audibility_rules.gd")
const SfxAudioDiagnosticCapture := preload("res://systems/sfx_audio_diagnostic_capture.gd")
const CampaignRunScript := preload("res://campaign/campaign_run.gd")
## Per-world campaign music, tempo (the run cycle puts a footstep on every
## eighth note) and star sound, keyed by presentation biome.
const CampaignAudio := preload("res://campaign/campaign_audio.gd")
const CAMPAIGN_FEATURES_SCRIPT := preload("res://campaign/campaign_features.gd")
const BAT_SWARM_SCRIPT := preload("res://hazards/bat_swarm.gd")
const GHOST_HAND_SCRIPT := preload("res://hazards/ghost_hand.gd")
const EMBER_BOMB_SCRIPT := preload("res://hazards/ember_bomb.gd")
const LIGHTNING_SCRIPT := preload("res://hazards/lightning_strike.gd")
const CampaignResultPanelScript := preload("res://campaign/campaign_result_panel.gd")
const CampaignBannerScript := preload("res://campaign/campaign_banner.gd")
## Ticks the runner keeps running past the finish line before the result.
const CAMPAIGN_RUNOUT_TICKS := 75
## Singleplayer catches up at most this many physics ticks after a hitch (Godot
## default 8), so a hitch is a short slowdown instead of several frozen frames
## in a row. Multiplayer steps from its own wall clock and is not affected.
const SP_MAX_PHYSICS_STEPS := 3
const SHADER_WARMUP_SCRIPT := preload("res://systems/shader_warmup.gd")
const PB_GHOST_SCRIPT := preload("res://player/personal_best_ghost.gd")
## Near miss: a flip that clears a hazard by at most NEAR_MISS_GAP px within
## NEAR_MISS_FLIP_TICKS of the flip gets a short callout (presentation only).
const NEAR_MISS_GAP := 14.0
const NEAR_MISS_FLIP_TICKS := 40
const NEAR_MISS_COOLDOWN_TICKS := 150
const NEAR_MISS_LINES := ["Close one!", "Phew!", "Just made it!", "Whoa!"]
var _near_miss_seen: Dictionary = {}
var _near_miss_last_tick := -100000
var _last_flip_tick := -100000
var _last_gravity_direction := 1
var near_miss_count := 0
var _pb_ghost: PersonalBestGhost
var _engine_max_physics_steps := 8
## Singleplayer pickup reach. The pixel runners are drawn wider than the shared
## 34x44 hitbox, so a coin the art visibly runs through must still count.
## Multiplayer validates coins on its own and is unaffected.
const SP_COIN_PICKUP_RADIUS := 19.0
const SURFACE_TILE_KEEP_BEHIND := 128.0

@onready var player: Node2D = $Player
@onready var run_state: Node = $RunState
@onready var hud: Node2D = $HUDLayer/HUD
@onready var run_end_panel: CanvasLayer = $RunEndPanel
@onready var camera: Camera2D = $Camera2D

var obstacles: Array[Node2D] = []
var coins: Array[Node2D] = []
var loot_pickups: Array[Node2D] = []
var slopes: Array[Node2D] = []
var gaps: Array[Node2D] = []
var _seed_scores: Array[Dictionary] = []
var _pending_hazard_discoveries: Array[Dictionary] = []
var _active_seed := 0
var _active_seed_version := 0
var _default_ruleset: Resource
var course_generator: CourseGenerator
var loot_spawn_planner: LootSpawnPlanner
var course_distance := 0.0
var coin_distance := 0.0
## Effect items of the equipped loadout (bubble helmet, spike plate, coin magnet).
## Only singleplayer endless and seed runs use it; campaign, demo and multiplayer
## runs configure it empty.
var _run_effects: RefCounted = RUN_EFFECTS_SCRIPT.new()
var _spawned_shared_coin_ids: Dictionary = {}
var _pending_shared_coins: Array[Dictionary] = []
var _shared_coin_planner: RefCounted
var _shared_coin_planned_until := -INF
var _singleplayer_simulation_tick := 0
var _singleplayer_audio_round_id := ""
var _sfx_audio_diagnostic_capture: Node
var _rock_warning_pulse: RefCounted = ROCK_WARNING_PULSE_SCRIPT.new()
var _ghost_warning_pulse: RefCounted = GHOST_WARNING_PULSE_SCRIPT.new()
var _rock_warning_accessibility_button: Button
var _anchor_button: Control
var _spawned_early_rock_ids: Dictionary = {}
var _spawned_early_saw_ids: Dictionary = {}
var _spawned_early_ghost_ids: Dictionary = {}
var _singleplayer_resolved_ghost_events: Dictionary = {}
var _singleplayer_spawned_gen19_fallback_ids: Dictionary = {}
var _singleplayer_ghost_activation_snapshots: Dictionary = {}
var _singleplayer_saw_activation_ticks: Dictionary = {}
var _singleplayer_ghost_activation_ticks: Dictionary = {}
var _singleplayer_saw_surface_indexes: Dictionary = {}
var _step_start_barrel_centers: Dictionary = {}
# Planned events far behind the runner whose early spawn / saw activation is
# already done are skipped by these cursors, so per-tick scans stay short on
# long runs instead of walking every event since the start.
const PLANNED_SCAN_SETTLED_BEHIND := 6000.0
var _early_spawn_scan_index := 0
var _saw_activation_scan_index := 0
var _manifest_builder: RefCounted
## Campaign stage of this run (null for endless, challenge and demo runs).
var _campaign_level: CampaignLevel
var _campaign_run: Node2D
var _campaign_result_panel: CanvasLayer
var _campaign_banner: CanvasLayer
var _campaign_runout_ticks := -1
var floor_level_y := screen_height - 80.0
var ceiling_level_y := 80.0
var planned_floor_level_y := screen_height - 80.0
var planned_ceiling_level_y := 80.0
var game_over := false
var run_blocked := false
var demo_flip_timer := 1.0
var demo_restart_timer := 0.0
var _speed_debug_visible := false
const Presentation := preload("res://systems/runner_presentation.gd")
const CameraScript := preload("res://systems/runner_camera.gd")
var _presentation := Presentation.new()
var _render_player_position := Vector2(180.0, 438.0)
var _render_course_distance := 0.0
var render_diagnostics_enabled := false
var _render_diagnostic_frames: Array[Dictionary] = []
var _render_diagnostic_tick := 0
const MAX_COIN_TRACE_EVENTS := 512
var _coin_trace_events: Array[Dictionary] = []
var _coin_trace_seen: Dictionary = {}
var _coin_trace_dropped := 0
var _coin_trace_counts := {"spawned": 0, "near_sweep": 0, "swept_contact": 0, "collected": 0, "expired_uncollected": 0}
var _render_callback_index := 0
var _render_callback_begin_usec := -1
var _render_presentation_sample_usec := -1
var _render_pose_sampled_usec := -1
var _render_presentation_ready_usec := -1
var _render_interpolation_fraction := 0.0
const DiagnosticsExport := preload("res://systems/multiplayer_v2/v2_diagnostics_export.gd")

func _ready() -> void:
	add_child(SHADER_WARMUP_SCRIPT.new())
	_pb_ghost = PB_GHOST_SCRIPT.new() as PersonalBestGhost
	_pb_ghost.name = "PersonalBestGhost"
	add_child(_pb_ghost)
	_engine_max_physics_steps = Engine.max_physics_steps_per_frame
	Engine.max_physics_steps_per_frame = SP_MAX_PHYSICS_STEPS
	_rock_warning_accessibility_button = Button.new()
	_rock_warning_accessibility_button.name = "RockWarningAccessibility"
	_rock_warning_accessibility_button.text = ""
	_rock_warning_accessibility_button.tooltip_text = tr("Falling rock")
	_rock_warning_accessibility_button.accessibility_name = tr("Falling rock")
	_rock_warning_accessibility_button.focus_mode = Control.FOCUS_ALL
	_rock_warning_accessibility_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rock_warning_accessibility_button.flat = true
	_rock_warning_accessibility_button.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_rock_warning_accessibility_button.size = Vector2(48.0, 48.0)
	_rock_warning_accessibility_button.visible = false
	$HUDLayer.add_child(_rock_warning_accessibility_button)
	_anchor_button = ANCHOR_BUTTON_SCRIPT.new()
	_anchor_button.name = "GravityAnchorButton"
	$HUDLayer.add_child(_anchor_button)
	_anchor_button.connect("pressed", Callable(player, "try_use_anchor"))
	course_generator = COURSE_GENERATOR_SCRIPT.new()
	loot_spawn_planner = LOOT_PLANNER_SCRIPT.new()
	_manifest_builder = MANIFEST_BUILDER_SCRIPT.new()
	_default_ruleset = COURSE_RULESET_SCRIPT.new()
	camera.set_script(CameraScript)
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.position_smoothing_enabled = false
	camera.enabled = true
	camera.make_current()
	_sync_screen_size()
	get_viewport().size_changed.connect(_sync_screen_size)
	run_state.connect("stats_changed", Callable(self, "_on_run_stats_changed"))
	run_state.connect("achievement_metrics_changed", Callable(self, "_on_run_achievement_metrics_changed"))
	run_state.connect("loot_pending_changed", Callable(hud, "set_loot_pending_count"))
	run_state.connect("run_started", Callable(hud, "hide_game_over"))
	run_state.connect("run_finished", Callable(hud, "show_game_over"))
	player.connect("gravity_flipped", Callable(run_state, "record_gravity_flip"))
	player.connect("gravity_flipped", Callable(self, "_on_singleplayer_gravity_flipped"))
	player.connect("gravity_flipped", Callable(_run_effects, "on_flip"))
	player.connect("gravity_reversed", Callable(self, "_on_singleplayer_gravity_flipped"))
	player.connect("anchor_used", Callable(self, "_on_singleplayer_gravity_flipped"))
	player.connect("status_changed", Callable(hud, "update_player_status"))
	ChallengeService.leaderboard_received.connect(_on_seed_leaderboard_received)
	if demo_mode:
		hud.visible = false
		$PauseMenu.visible = false
	_start_run()
	if not demo_mode and SfxAudioDiagnosticCapture.is_requested():
		_start_singleplayer_audio_diagnostic_capture()

func _start_singleplayer_audio_diagnostic_capture(duration_seconds := 12.0) -> bool:
	if demo_mode or is_instance_valid(_sfx_audio_diagnostic_capture):
		return false
	var capture := SfxAudioDiagnosticCapture.new()
	capture.name = "SfxAudioDiagnosticCapture"
	add_child(capture)
	if not bool(capture.call("start_capture", _active_seed, _active_seed_version, duration_seconds)):
		capture.queue_free()
		return false
	_sfx_audio_diagnostic_capture = capture
	return true
func _start_run() -> void:
	_rock_warning_pulse.call("reset")
	_ghost_warning_pulse.call("reset")
	_rock_warning_accessibility_button.visible = false
	_render_diagnostic_tick = 0
	_render_diagnostic_frames.clear()
	run_end_panel.visible = false
	if not demo_mode:
		AchievementService.begin_run()
		_singleplayer_audio_round_id = "singleplayer:%d" % Time.get_ticks_usec()
		var campaign_track: AudioStream = null
		if Campaign.active_level != null:
			campaign_track = CampaignAudio.track_for(Campaign.active_level.get_presentation_biome())
		MusicController.start_round(_singleplayer_audio_round_id, campaign_track)
		SfxController.begin_round(_singleplayer_audio_round_id)
	player.call("reset_to_floor", WORLD_HEIGHT - 80.0)
	player.call("set_skin_id", randi_range(0, 3) if demo_mode else PlayerProfile.preferred_skin_id)
	# The menu's autoplay background shows a random character for variety.
	player.call("apply_character", CharacterCatalog.DEFINITIONS.pick_random() if demo_mode else PlayerProfile.get_selected_character())
	var loadout_snapshot: Resource = InventoryService.create_run_loadout_snapshot(PlayerProfile.get_character_stats())
	run_state.call("set_loadout_snapshot", loadout_snapshot)
	player.call("set_loadout_snapshot", loadout_snapshot)
	var effects_enabled := not demo_mode and Campaign.active_level == null
	_run_effects.call("configure", loadout_snapshot if effects_enabled else null)
	# Campaign stages run without effect items, but a won biome key works in its world.
	var biome_key := "" if demo_mode else BiomeKeys.active_key_for(Campaign.active_level)
	_run_effects.call("configure_key", biome_key)
	CaveDarkness.clear_scale = BiomeKeys.LANTERN_CLEAR_SCALE if biome_key == "lantern" else 1.0
	ForestFog.clear_scale = CaveDarkness.clear_scale
	player.call("set_run_effects", _run_effects)
	run_state.set("modified", effects_enabled and loadout_snapshot != null and bool(loadout_snapshot.call("has_effects")))
	_publish_effect_entries()
	_anchor_button.visible = bool(_run_effects.call("has_anchor"))
	run_state.call("start_run")
	course_distance = 0.0
	_campaign_level = null if demo_mode else Campaign.active_level
	# Campaign stages pin one biome; every other run uses the rotation.
	BIOME_RENDERER_SCRIPT.set_locked_biome(_campaign_level.get_presentation_biome() if _campaign_level != null else &"")
	_manifest_builder.call("clear_runtime_cache")
	var run_seed := _campaign_level.seed_value if _campaign_level != null else ChallengeService.begin_run()
	loot_spawn_planner.reset(run_seed)
	_active_seed = run_seed
	_active_seed_version = _campaign_level.generator_version if _campaign_level != null else ChallengeService.generation_version
	_seed_scores.clear()
	_pending_hazard_discoveries.clear()
	var run_definition: Resource
	if _campaign_level != null:
		run_definition = _campaign_level.create_run_definition()
	else:
		run_definition = COURSE_RUN_DEFINITION_SCRIPT.new() as Resource
		run_definition.set("scenario_id", &"seed_challenge" if ChallengeService.active else &"endless")
		run_definition.set("seed_value", run_seed)
		run_definition.set("generator_version", _active_seed_version)
		run_definition.set("ruleset", ChallengeService.ruleset if ChallengeService.ruleset != null else _default_ruleset)
	_pb_ghost.begin(_ghost_identity(run_definition), player.get("sprite").sprite_frames, float(player.get("_pixel_scale")), float(player.get("_character_offset_y")), float(player.get_script().get_script_constant_map().get("SPRITE_SURFACE_GAP", 1.0)))
	if not course_generator.configure_run_definition(run_definition):
		push_error("Could not apply this run's seed and ruleset to the course generator.")
	if not demo_mode and _campaign_level == null:
		hud.call("set_seed", ChallengeService.generation_version, run_seed)
		ChallengeService.fetch_current_scores()
	coin_distance = 0.0
	_spawned_shared_coin_ids.clear()
	_spawned_early_rock_ids.clear()
	_spawned_early_saw_ids.clear()
	_spawned_early_ghost_ids.clear()
	_early_spawn_scan_index = 0
	_saw_activation_scan_index = 0
	_singleplayer_resolved_ghost_events.clear()
	_singleplayer_spawned_gen19_fallback_ids.clear()
	_singleplayer_ghost_activation_snapshots.clear()
	_singleplayer_saw_activation_ticks.clear()
	_singleplayer_ghost_activation_ticks.clear()
	_singleplayer_saw_surface_indexes.clear()
	_pending_shared_coins.clear()
	_shared_coin_planned_until = PLAYER_X + SHARED_COIN_PLANNER_SCRIPT.COURSE_START_OFFSET
	if render_diagnostics_enabled:
		_coin_trace_events.clear()
		_coin_trace_seen.clear()
		_coin_trace_dropped = 0
		_coin_trace_counts = {"spawned": 0, "spawned_before_capture": 0, "near_sweep": 0, "swept_contact": 0, "collected": 0, "expired_uncollected": 0}
	_shared_coin_planner = SHARED_COIN_PLANNER_SCRIPT.new()
	var coin_ruleset: Resource = ChallengeService.ruleset if ChallengeService.ruleset != null else _default_ruleset
	if _campaign_level != null:
		coin_ruleset = _campaign_level.ruleset
	_shared_coin_planner.reset(_active_seed, PLAYER_X, int(coin_ruleset.get("coin_revision")), float(coin_ruleset.get("coin_density")))
	floor_level_y = WORLD_HEIGHT - 80.0
	ceiling_level_y = 80.0
	planned_floor_level_y = floor_level_y
	planned_ceiling_level_y = ceiling_level_y
	_clear_nodes(obstacles)
	_clear_nodes(coins)
	_clear_nodes(loot_pickups)
	_clear_nodes(slopes)
	_clear_nodes(gaps)
	game_over = false
	_singleplayer_simulation_tick = 0
	_near_miss_seen.clear()
	_near_miss_last_tick = -100000
	_last_flip_tick = -100000
	_last_gravity_direction = 1
	near_miss_count = 0
	run_blocked = false
	_presentation.reset(player.position)
	_render_player_position = player.position
	_render_course_distance = 0.0
	_update_camera()
	demo_flip_timer = randf_range(0.9, 1.8)
	demo_restart_timer = 0.0
	player.call("set_input_enabled", not demo_mode)
	if demo_mode:
		player.call("set_running", true)
	hud.call("set_run_blocked", false)
	_setup_campaign_run()
	queue_redraw()

## The ceiling can rise to y 40, under the top HUD band (its height is part
## of the shared course geometry, so it is not capped). When the runner's art
## reaches up there, the HUD fades so the runner stays visible.
const HUD_BAND_BOTTOM := 52.0
const HUD_FADED_ALPHA := 0.3
var _hud_alpha := 1.0

## On campaign stages with their own track the runner's feet follow the music:
## two footsteps per run cycle, one per eighth note. Other runs keep the
## authored animation speed.
func _sync_run_cycle_to_music() -> void:
	var sprite := player.get_node("AnimatedSprite2D") as AnimatedSprite2D
	if sprite == null:
		return
	var track: AudioStream = null
	var bpm := 0.0
	if _campaign_level != null:
		track = CampaignAudio.track_for(_campaign_level.get_presentation_biome())
		bpm = CampaignAudio.bpm_for(_campaign_level.get_presentation_biome())
	var synced := track != null and bpm > 0.0
	if not synced or sprite.animation != &"run" or sprite.sprite_frames == null:
		sprite.speed_scale = 1.0
		return
	var frame_count := sprite.sprite_frames.get_frame_count(&"run")
	var eighth := 30.0 / bpm
	var frames_per_step := float(frame_count) / 2.0
	var music_time := float(MusicController.get_audible_position(track))
	if music_time < 0.0 or not sprite.is_playing():
		# No music (muted or not started): same cadence, free running.
		var base_fps := maxf(sprite.sprite_frames.get_animation_speed(&"run"), 1.0)
		sprite.speed_scale = frames_per_step / eighth / base_fps
		return
	sprite.speed_scale = 0.0
	var frame := int(floor(music_time / eighth * frames_per_step)) % frame_count
	if sprite.frame != frame:
		sprite.frame = frame

func _update_hud_fade(delta: float) -> void:
	if demo_mode or not is_instance_valid(hud):
		return
	var camera_top := camera.get_screen_center_position().y - screen_height * 0.5 if is_instance_valid(camera) else 0.0
	var runner_top := _render_player_position.y - camera_top - RUNNER_MOTION_SCRIPT.SIZE.y * 0.5 - 12.0
	var under := not game_over and runner_top < HUD_BAND_BOTTOM
	_hud_alpha = move_toward(_hud_alpha, HUD_FADED_ALPHA if under else 1.0, delta * 5.0)
	hud.modulate.a = _hud_alpha
	var pause_menu := get_node_or_null("PauseMenu")
	if pause_menu != null and pause_menu.has_method("set_toolbar_alpha"):
		pause_menu.call("set_toolbar_alpha", _hud_alpha)

func _campaign_banner_node() -> CanvasLayer:
	if not is_instance_valid(_campaign_banner):
		_campaign_banner = CampaignBannerScript.new() as CanvasLayer
		_campaign_banner.name = "CampaignBanner"
		add_child(_campaign_banner)
	return _campaign_banner

func _setup_campaign_run() -> void:
	if is_instance_valid(_campaign_banner):
		_campaign_banner.call("clear")
	_campaign_runout_ticks = -1
	if is_instance_valid(_campaign_run):
		_campaign_run.queue_free()
	_campaign_run = null
	if is_instance_valid(_campaign_result_panel):
		_campaign_result_panel.call("hide_panel")
	hud.call("set_campaign", _campaign_level)
	if _campaign_level == null:
		return
	_campaign_run = CampaignRunScript.new() as Node2D
	_campaign_run.name = "CampaignRun"
	add_child(_campaign_run)
	_campaign_run.call("setup", _campaign_level)
	_campaign_run.connect("callout", _campaign_banner_node().show_banner)
	_campaign_run.connect("stars_changed", Callable(hud, "set_campaign_stars"))
	_campaign_run.connect("stars_changed", _on_campaign_star_collected)
	_campaign_run.connect("boss_changed", Callable(hud, "set_campaign_boss"))
	_campaign_run.connect("feature_cue", Callable(self, "_on_campaign_feature_cue"))
	_campaign_run.connect("bonus_coins", Callable(self, "_on_campaign_bonus_coins"))
	if not _campaign_level.intro.is_empty():
		_campaign_banner_node().show_banner("boss" if _campaign_level.is_boss() else "stage", str(_campaign_level.level_id), tr(_campaign_level.title), tr(_campaign_level.intro))
	if _campaign_level.is_boss():
		var boss_hp := int(_campaign_run.call("get_boss_max_hp"))
		hud.call("set_campaign_boss", boss_hp, boss_hp)

func _on_campaign_star_collected(collected: int, _total: int) -> void:
	var star_sfx := CampaignAudio.star_sfx_for(_campaign_level.get_presentation_biome()) if _campaign_level != null else "gravity_star"
	_play_singleplayer_sfx(star_sfx, "%s|gravity_star|%d" % [_singleplayer_audio_round_id, collected])

func _sync_screen_size() -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var view_scale := minf(viewport_size.x / WORLD_WIDTH, viewport_size.y / WORLD_HEIGHT)
	view_scale = maxf(view_scale, 0.01)
	screen_width = viewport_size.x / view_scale
	screen_height = viewport_size.y / view_scale
	camera.zoom = Vector2.ONE * view_scale
	_update_camera()
	if is_instance_valid(hud):
		hud.queue_redraw()
	queue_redraw()

func _update_camera() -> void:
	if not is_instance_valid(camera) or not is_instance_valid(player):
		return
	camera.call("configure", Vector2(screen_width, screen_height), PLAYER_X, camera.zoom.x)
	camera.call("follow", _render_player_position)

func _update_ghost_presentation(render_fraction: float) -> void:
	var presentation_tick := maxf(float(_singleplayer_simulation_tick - 1) + clampf(render_fraction, 0.0, 1.0), 0.0)
	for obstacle in obstacles:
		if is_instance_valid(obstacle) and obstacle.is_in_group("ghost_hazards") and obstacle.has_method("set_presentation_tick"):
			obstacle.call("set_presentation_tick", presentation_tick)

func _on_run_stats_changed(distance_pixels: float, coins: int) -> void:
	hud.call("update_stats", distance_pixels, coins)
	if not demo_mode:
		AchievementService.update_run_distance(distance_pixels)

func _on_run_achievement_metrics_changed(coins: int, gravity_flips: int, hazards_seen: Array) -> void:
	if not demo_mode:
		AchievementService.update_run_metrics(coins, gravity_flips, hazards_seen)

func _scale_track_y(y: float, scale: float) -> float:
	return 56.0 + (y - 56.0) * scale

## Drops pickups the runner has passed and frees them. They used to leave the
## list without being freed: the node stayed in the scene, was never checked
## again, and showed up as an uncollectable "double" coin after a retry of the
## same course (or as a stray coin on the next run).
func _prune_passed_nodes(nodes: Array[Node2D], limit_x: float, keep_collecting_alive: bool) -> Array[Node2D]:
	var kept: Array[Node2D] = []
	for node in nodes:
		if not is_instance_valid(node):
			continue
		var collecting := keep_collecting_alive and bool(node.call("is_collected"))
		if collecting:
			# A collected coin finishes its burst and frees itself.
			continue
		if node.position.x > limit_x:
			kept.append(node)
		elif not node.is_queued_for_deletion():
			node.queue_free()
	return kept

func _clear_nodes(nodes: Array[Node2D]) -> void:
	for node in nodes:
		node.queue_free()
	nodes.clear()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_speed_debug_visible = not _speed_debug_visible
		hud.call("set_speed_debug_visible", _speed_debug_visible)
		_update_speed_debug()
		get_viewport().set_input_as_handled()
		return
	if game_over:
		if event is InputEventScreenTouch and event.pressed:
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.pressed:
			get_viewport().set_input_as_handled()
		elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			return_to_main_menu()
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	if is_instance_valid(_sfx_audio_diagnostic_capture):
		_sfx_audio_diagnostic_capture.call("record_callback_timing", "sp_process", delta, _singleplayer_simulation_tick)
	var callback_started_usec := Time.get_ticks_usec()
	if render_diagnostics_enabled and not _render_diagnostic_frames.is_empty():
		var previous_frame: Dictionary = _render_diagnostic_frames.back()
		previous_frame["next_callback_begin_usec"] = callback_started_usec
		_render_diagnostic_frames[_render_diagnostic_frames.size() - 1] = previous_frame
	_render_callback_index += 1
	_render_callback_begin_usec = callback_started_usec
	_render_interpolation_fraction = Engine.get_physics_interpolation_fraction()
	for obstacle in obstacles:
		if is_instance_valid(obstacle) and obstacle.has_method("set_render_fraction") and (obstacle.is_in_group("falling_rocks") or obstacle.is_in_group("saw_blades")):
			obstacle.call("set_render_fraction", _render_interpolation_fraction)
	_update_ghost_presentation(_render_interpolation_fraction)
	_render_presentation_sample_usec = Time.get_ticks_usec()
	_render_player_position = _presentation.sample(_render_interpolation_fraction)
	_pb_ghost.show_at(float(_singleplayer_simulation_tick - 1) + _render_interpolation_fraction)
	_render_pose_sampled_usec = Time.get_ticks_usec() if render_diagnostics_enabled else -1
	_render_course_distance = _render_player_position.x - PLAYER_X
	var sprite := player.get_node("AnimatedSprite2D") as AnimatedSprite2D
	sprite.position = _render_player_position - player.position + Vector2(0.0, -float(player.call("get_gravity_direction")))
	_update_camera()
	_update_hud_fade(delta)
	_sync_run_cycle_to_music()
	if is_instance_valid(_campaign_run):
		_campaign_run.call("update_presentation", float(camera.get("left")), screen_width, Callable(self, "_surface_y_at"))
		if bool(_campaign_run.call("has_darkness")):
			var lit_nodes: Array = []
			lit_nodes.append_array(obstacles)
			lit_nodes.append_array(gaps)
			lit_nodes.append_array(slopes)
			_campaign_run.call("update_darkness", float(camera.get("left")), screen_width, _render_player_position, lit_nodes, Callable(self, "_surface_y_at"))
	_update_singleplayer_rock_warning_pulse(delta)
	_ghost_warning_pulse.call("advance", delta)
	_render_presentation_ready_usec = Time.get_ticks_usec()
	if render_diagnostics_enabled and not game_over:
		_record_render_diagnostic(delta)
	queue_redraw()

func set_render_diagnostics_enabled(enabled: bool) -> void:
	render_diagnostics_enabled = enabled
	if enabled:
		_render_diagnostic_frames.clear()
		_coin_trace_events.clear()
		_coin_trace_seen.clear()
		_coin_trace_dropped = 0
		_coin_trace_counts = {"spawned": 0, "spawned_before_capture": 0, "near_sweep": 0, "swept_contact": 0, "collected": 0, "expired_uncollected": 0}
		# Diagnostics may be enabled mid-run; preserve canonical identities for active coins.
		for coin in coins:
			if not is_instance_valid(coin) or bool(coin.call("is_collected")):
				continue
			var entity_id := str(coin.get_meta("coin_trace_id", "sp_coin_%d" % coin.get_instance_id()))
			coin.set_meta("coin_trace_id", entity_id)
			if not entity_id.begins_with("coin_") and not bool(coin.get_meta("coin_trace_collect_connected", false)):
				coin.connect("collected", Callable(self, "_on_singleplayer_coin_collected").bind(coin, entity_id, "active_node_snapshot"))
				coin.set_meta("coin_trace_collect_connected", true)
			_record_coin_trace("spawned_before_capture", entity_id, coin.global_position, {"source": "active_node_snapshot"}, "spawned:%s" % entity_id)

func _record_render_diagnostic(delta: float) -> void:
	var capture_started_usec := Time.get_ticks_usec()
	var reference: Dictionary = {}
	var left := float(camera.get("left"))
	var reference_nodes: Array[Dictionary] = []
	var static_hazard_recorded := false
	var barrel_recorded := false
	for obstacle in obstacles:
		if not is_instance_valid(obstacle) or obstacle.is_queued_for_deletion() or obstacle.get_script() == null:
			continue
		if obstacle.has_method("is_destroying_now") and bool(obstacle.call("is_destroying_now")):
			continue
		var is_barrel := obstacle.is_in_group("barrels")
		if (is_barrel and barrel_recorded) or (not is_barrel and static_hazard_recorded):
			continue
		if obstacle.position.x < left - 100.0 or obstacle.position.x > left + screen_width + 100.0:
			continue
		var canvas_transform: Transform2D = obstacle.get_global_transform_with_canvas()
		var diagnostic_id := str(obstacle.get_meta("render_diagnostic_id", ""))
		if diagnostic_id.is_empty():
			var script_path := str(obstacle.get_script().resource_path)
			diagnostic_id = "%s@%.1f,%.1f" % [script_path, obstacle.position.x, obstacle.position.y]
			obstacle.set_meta("render_diagnostic_id", diagnostic_id)
		var node_record := {"kind": "barrel" if is_barrel else "static_hazard", "id": diagnostic_id, "instance_id": obstacle.get_instance_id(), "world_position": _render_diagnostic_vector(obstacle.global_position), "canvas_transform": _render_diagnostic_transform(canvas_transform), "canvas_origin": _render_diagnostic_vector(canvas_transform.origin)}
		if is_barrel:
			var render_fraction := Engine.get_physics_interpolation_fraction()
			var rendered_position: Vector2 = obstacle.get("_previous_position").lerp(obstacle.position, render_fraction)
			var previous_rotation := float(obstacle.get("_previous_rotation"))
			var rotation_delta := lerp_angle(previous_rotation, obstacle.rotation, render_fraction) - obstacle.rotation
			var draw_offset := (rendered_position - obstacle.position).rotated(-obstacle.rotation)
			var barrel_size: Vector2 = obstacle.get("size")
			var barrel_radius := HAZARD_RULES_SCRIPT.barrel_radius(barrel_size.x, barrel_size.y)
			var barrel_center_y := barrel_radius if bool(obstacle.get("from_ceiling")) else -barrel_radius
			var rendered_center := canvas_transform * (draw_offset + Vector2(0.0, barrel_center_y).rotated(rotation_delta))
			node_record["render_fraction"] = render_fraction
			node_record["rendered_world_position"] = _render_diagnostic_vector(rendered_position)
			node_record["rendered_canvas_center"] = _render_diagnostic_vector(rendered_center)
			node_record["rendered_rotation"] = lerp_angle(previous_rotation, obstacle.rotation, render_fraction)
			barrel_recorded = true
		else:
			var camera_top := camera.global_position.y - screen_height * 0.5
			node_record["expected_canvas_origin"] = _render_diagnostic_vector(Vector2((obstacle.position.x - left) * camera.zoom.x, (obstacle.position.y - camera_top) * camera.zoom.y))
			static_hazard_recorded = true
			reference = {"id": diagnostic_id, "instance_id": obstacle.get_instance_id(), "world_x": obstacle.position.x, "world_y": obstacle.position.y, "screen_x": (obstacle.position.x - left) * camera.zoom.x, "canvas_origin": node_record.canvas_origin}
		reference_nodes.append(node_record)
	var viewport_canvas_transform: Transform2D = get_viewport().get_canvas_transform()
	var track_world_x := left + PLAYER_X
	var track_floor_y := _floor_surface_y(track_world_x)
	var floor_slope: Dictionary = {}
	for terrain in slopes:
		if not is_instance_valid(terrain) or bool(terrain.call("is_ceiling_slope")):
			continue
		var slope_start := float(terrain.call("get_start_x"))
		var slope_end := float(terrain.call("get_end_x"))
		if track_world_x >= slope_start and track_world_x <= slope_end:
			floor_slope = {"id": "%s@%.1f" % [str(terrain.get_script().resource_path), slope_start], "start_x": slope_start, "end_x": slope_end, "canvas_transform": _render_diagnostic_transform(terrain.get_global_transform_with_canvas())}
			break
	var player_canvas_transform: Transform2D = player.get_node("AnimatedSprite2D").get_global_transform_with_canvas()
	if _render_diagnostic_frames.size() >= 4096:
		_render_diagnostic_frames.pop_front()
	var captured_at_usec := Time.get_ticks_usec()
	var frame_record := {"at_usec": captured_at_usec, "render_callback_index": _render_callback_index, "render_callback_begin_usec": _render_callback_begin_usec, "presentation_sample_usec": _render_presentation_sample_usec, "pose_sampled_usec": _render_pose_sampled_usec, "presentation_ready_usec": _render_presentation_ready_usec, "sample_to_ready_usec": _render_presentation_ready_usec - _render_presentation_sample_usec, "ready_to_capture_usec": captured_at_usec - _render_presentation_ready_usec, "diagnostic_capture_usec": 0, "phase": "terminal" if game_over else "running", "render_delta_ms": delta * 1000.0, "tick": _render_diagnostic_tick, "fraction": _render_interpolation_fraction, "previous_x": _presentation.previous.x, "current_x": _presentation.current.x, "previous_y": _presentation.previous.y, "current_y": _presentation.current.y, "render_x": _render_player_position.x, "render_y": _render_player_position.y, "player_world_position": _render_diagnostic_vector(player.global_position), "gravity_direction": int(player.call("get_gravity_direction")), "grounded": bool(player.get("grounded")), "vertical_speed": float(player.get("vertical_speed")), "camera_left": left, "camera_global_position": _render_diagnostic_vector(camera.global_position), "camera_canvas_transform": _render_diagnostic_transform(viewport_canvas_transform), "render_course_distance": _render_course_distance, "speed": _run_speed(), "player_speed_multiplier": float(player.call("get_speed_multiplier")), "equipment_speed_multiplier": _equipment_speed_multiplier(), "blocked": run_blocked, "reference": reference, "reference_nodes": reference_nodes, "player_canvas_position": _render_diagnostic_vector(player_canvas_transform.origin), "track_surface": {"world_position": _render_diagnostic_vector(Vector2(track_world_x, track_floor_y)), "canvas_position": _render_diagnostic_vector(viewport_canvas_transform * Vector2(track_world_x, track_floor_y)), "floor_y": track_floor_y, "ceiling_y": _ceiling_surface_y(track_world_x), "slope": floor_slope}, "fps": Engine.get_frames_per_second()}
	_render_diagnostic_frames.append(frame_record)
	_render_diagnostic_frames[_render_diagnostic_frames.size() - 1]["diagnostic_capture_usec"] = Time.get_ticks_usec() - capture_started_usec

func save_render_diagnostics() -> String:
	var report := _build_render_diagnostics_report()
	return DiagnosticsExport.save_report(report, "singleplayer_smoothness_%d.json" % Time.get_unix_time_from_system())

func _build_render_diagnostics_report() -> Dictionary:
	var trace_events: Array[Dictionary] = _coin_trace_events.duplicate(true)
	for event in trace_events:
		event.erase("_dedup_key")
	return {"session": {"network_mode": "singleplayer", "build_id": str(ProjectSettings.get_setting("application/config/version", "")), "godot_version": Engine.get_version_info(), "seed": _active_seed, "generator_version": _active_seed_version, "viewport": [screen_width, screen_height], "zoom": camera.zoom.x}, "frames": _render_diagnostic_frames.duplicate(true), "coin_trace": {"enabled": render_diagnostics_enabled, "max_records": MAX_COIN_TRACE_EVENTS, "event_count": trace_events.size(), "dropped_events": _coin_trace_dropped, "counts": _coin_trace_counts.duplicate(true), "events": trace_events}, "exported_at_unix": Time.get_unix_time_from_system()}

func _record_coin_trace(action: String, entity_id: String, coin_position: Vector2, details: Dictionary = {}, dedup_key: String = "") -> void:
	if not render_diagnostics_enabled:
		return
	if not dedup_key.is_empty() and _coin_trace_seen.has(dedup_key):
		return
	if not dedup_key.is_empty():
		_coin_trace_seen[dedup_key] = true
		while _coin_trace_seen.size() > MAX_COIN_TRACE_EVENTS:
			_coin_trace_seen.erase(_coin_trace_seen.keys()[0])
	if _coin_trace_events.size() >= MAX_COIN_TRACE_EVENTS:
		var discarded: Dictionary = _coin_trace_events.pop_front()
		var discarded_key := str(discarded.get("_dedup_key", ""))
		if not discarded_key.is_empty():
			_coin_trace_seen.erase(discarded_key)
		_coin_trace_dropped += 1
	var event := {"action": action, "entity_id": entity_id, "tick": _singleplayer_simulation_tick, "course_distance": course_distance, "coin_position": _render_diagnostic_vector(coin_position), "run_coins": int(run_state.get("coins")) if is_instance_valid(run_state) else -1}
	for key in details:
		event[key] = details[key]
	if not dedup_key.is_empty():
		event["_dedup_key"] = dedup_key
	_coin_trace_events.append(event)
	_coin_trace_counts[action] = int(_coin_trace_counts.get(action, 0)) + 1

func _coin_trace_rect(rect: Rect2) -> Array[float]:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]

func _record_coin_sweep_diagnostic(coin: Node2D, start_rect: Rect2, end_rect: Rect2, fraction: float, lethal_fraction: float) -> void:
	if not render_diagnostics_enabled or not is_instance_valid(coin):
		return
	var entity_id := str(coin.get_meta("coin_trace_id", "sp_coin_%d" % coin.get_instance_id()))
	var coin_rect: Rect2 = coin.call("get_hitbox_rect")
	var broadphase := start_rect.merge(end_rect).grow(24.0)
	if fraction < 0.0 and not broadphase.intersects(coin_rect):
		return
	var survives_terminal := fraction >= 0.0 and fraction < lethal_fraction - 0.000001
	var reason := "swept_contact_before_terminal" if survives_terminal else ("terminal_contact_precedes_coin" if fraction >= 0.0 else "near_sweep_without_circle_contact")
	var details := {"swept_fraction": fraction, "lethal_fraction": lethal_fraction, "eligible_before_terminal": survives_terminal, "decision_reason": reason, "player_rect_start": _coin_trace_rect(start_rect), "player_rect_end": _coin_trace_rect(end_rect), "coin_rect": _coin_trace_rect(coin_rect), "run_coins_before": int(run_state.get("coins")) if is_instance_valid(run_state) else -1}
	_record_coin_trace("near_sweep", entity_id, coin.global_position, details, "near:%s" % entity_id)
	if fraction >= 0.0:
		_record_coin_trace("swept_contact", entity_id, coin.global_position, details, "contact:%s" % entity_id)

func _record_uncollected_coin_expiry(camera_left: float) -> void:
	if not render_diagnostics_enabled:
		return
	for coin in coins:
		if not is_instance_valid(coin) or bool(coin.call("is_collected")) or coin.position.x > camera_left - 100.0:
			continue
		var entity_id := str(coin.get_meta("coin_trace_id", "sp_coin_%d" % coin.get_instance_id()))
		_record_coin_trace("expired_uncollected", entity_id, coin.global_position, {"reason": "camera_passed_uncollected", "camera_left": camera_left, "coin_world_x": coin.global_position.x})

func _render_diagnostic_vector(value: Vector2) -> Array[float]:
	return [value.x, value.y]

func _render_diagnostic_transform(value: Transform2D) -> Dictionary:
	return {"x": _render_diagnostic_vector(value.x), "y": _render_diagnostic_vector(value.y), "origin": _render_diagnostic_vector(value.origin)}

func _physics_process(delta: float) -> void:
	if is_instance_valid(_sfx_audio_diagnostic_capture):
		_sfx_audio_diagnostic_capture.call("record_callback_timing", "sp_physics", delta, _singleplayer_simulation_tick)
	if game_over:
		if demo_mode:
			demo_restart_timer += delta
			if demo_restart_timer >= 0.8:
				_start_run()
		return
	if _campaign_runout_ticks >= 0:
		_campaign_runout_ticks += 1
		if _campaign_runout_ticks >= CAMPAIGN_RUNOUT_TICKS:
			_complete_campaign_level()
			return
	var previous_player_rect: Rect2 = player.call("get_player_rect")
	var previous_world_x := float(player.get("world_x"))
	_step_start_barrel_centers.clear()
	for obstacle in obstacles:
		if is_instance_valid(obstacle) and obstacle.is_in_group("barrels"):
			var barrel_size: Vector2 = obstacle.get("size")
			_step_start_barrel_centers[obstacle.get_instance_id()] = HAZARD_RULES_SCRIPT.barrel_center(obstacle.global_position, barrel_size.x, barrel_size.y, bool(obstacle.get("from_ceiling")))
	_pb_ghost.record(_singleplayer_simulation_tick, previous_player_rect.get_center(), _runner_facing())
	_singleplayer_simulation_tick += 1
	for hazard in obstacles:
		if is_instance_valid(hazard) and hazard.is_in_group("lava_hazards") and hazard.has_method("apply_simulation_tick"):
			hazard.call("apply_simulation_tick", _singleplayer_simulation_tick, PLAYER_X)

	_render_diagnostic_tick += 1
	var speed := _run_speed()
	_update_speed_debug()
	var movement_multiplier := _equipment_speed_multiplier() * float(player.call("get_speed_multiplier"))
	var movement := RUNNER_MOTION_SCRIPT.distance_for_delta(delta, movement_multiplier, run_blocked)
	if not run_blocked:
		var previous_distance := float(run_state.get("distance_m"))
		player.call("advance_world_x", movement)
		course_distance = float(player.get("world_x")) - PLAYER_X
		run_state.call("add_distance", movement)
		var current_distance := float(run_state.get("distance_m"))
		_mark_crossed_seed_records(previous_distance, current_distance)
		coin_distance += movement
		var event_spawn_lead := COURSE_GENERATOR_SCRIPT.get_viewport_spawn_lead_distance(screen_width, PLAYER_X, SLOPE_WIDTH)
		course_generator.ensure_horizon(course_distance + screen_width + 1400.0, speed, screen_height, event_spawn_lead)
		if RUN_LOOT_ENABLED and AuthService.is_authenticated and not demo_mode:
			loot_spawn_planner.ensure_horizon(course_distance + screen_width + 1400.0)
		var spawn_line := course_distance + event_spawn_lead
		if _active_seed_version >= COURSE_GENERATOR_SCRIPT.PUBLISHED_SHARED_GENERATOR_VERSION:
			var rock_spawn_line := course_distance + FALLING_ROCK_MODEL.TRIGGER_LEAD + 300.0
			var saw_spawn_line := course_distance + SAW_BLADE_MODEL.SPAWN_LEAD
			var planned_events := course_generator.get_planned_events()
			for planned_index in range(_early_spawn_scan_index, planned_events.size()):
				var planned_event: Dictionary = planned_events[planned_index]
				if is_instance_valid(_campaign_run) and not bool(_campaign_run.call("allows_event", planned_event)):
					continue
				var planned_kind := str(planned_event.get("kind", ""))
				var event_distance := float(planned_event.get("course_distance", INF))
				if planned_kind == "rock" and event_distance <= rock_spawn_line:
					var rock_id := _singleplayer_rock_key(planned_event)
					if not _spawned_early_rock_ids.has(rock_id):
						_spawned_early_rock_ids[rock_id] = true
						_spawn_course_event(planned_event)
				elif planned_kind == "saw" and event_distance <= saw_spawn_line:
					var saw_id := _singleplayer_saw_key(planned_event)
					if not _spawned_early_saw_ids.has(saw_id):
						_spawned_early_saw_ids[saw_id] = true
						_spawn_course_event(planned_event)
				elif planned_kind == "ghost" and event_distance <= course_distance + float(planned_event.get("trigger_lead", 2200.0)):
					var effective_ghost_event := _resolve_singleplayer_ghost_event(planned_event)
					if bool(effective_ghost_event.get("gen19_supported_fallback", false)):
						# Fallback blocks use the normal event spawn line, not the early warning lead.
						continue
					var ghost_id := _singleplayer_ghost_key(planned_event)
					if not _spawned_early_ghost_ids.has(ghost_id):
						_spawned_early_ghost_ids[ghost_id] = true
						_spawn_course_event(planned_event)
						_singleplayer_resolved_ghost_events.erase(ghost_id)
			while _early_spawn_scan_index < planned_events.size() and _early_spawn_is_settled(planned_events[_early_spawn_scan_index]):
				_early_spawn_scan_index += 1
		for event in course_generator.pop_events_until(spawn_line):
			if is_instance_valid(_campaign_run) and not bool(_campaign_run.call("allows_event", event)):
				continue
			var event_kind := str(event.get("kind", ""))
			if event_kind == "rock":
				var event_id := _singleplayer_rock_key(event)
				if _spawned_early_rock_ids.has(event_id):
					continue
				_spawned_early_rock_ids[event_id] = true
			elif event_kind == "saw":
				var event_id := _singleplayer_saw_key(event)
				if _spawned_early_saw_ids.has(event_id):
					continue
				_spawned_early_saw_ids[event_id] = true
			elif event_kind == "ghost":
				var event_id := _singleplayer_ghost_key(event)
				if _spawned_early_ghost_ids.has(event_id):
					continue
				_spawned_early_ghost_ids[event_id] = true
			_spawn_course_event(event)
		if is_instance_valid(_campaign_run):
			for boss_event in _campaign_run.call("pop_boss_events", spawn_line):
				_spawn_course_event(boss_event)
			for landed_barrel in _campaign_run.call("update_thrown_barrels", course_distance):
				_spawn_obstacle_scene(BARREL_SCENE, HAZARD_RULES_SCRIPT.BARREL_WIDTH, float(landed_barrel.height), false, float(landed_barrel.x), float(landed_barrel.speed), bool(landed_barrel.spiked))
				if not obstacles.is_empty():
					obstacles[obstacles.size() - 1].set("roll_angle", float(landed_barrel.roll))
			for feature_event in _campaign_run.call("pop_feature_events", course_distance, spawn_line):
				_spawn_course_event(feature_event)
		if RUN_LOOT_ENABLED:
			for loot_event in loot_spawn_planner.pop_events_until(spawn_line):
				_spawn_loot_pickup(loot_event)
		_update_hazard_discoveries()
		if not demo_mode:
			if _active_seed_version >= COURSE_GENERATOR_SCRIPT.PUBLISHED_SHARED_GENERATOR_VERSION:
				_spawn_shared_coins()
			elif coin_distance >= COIN_DISTANCE:
				coin_distance -= COIN_DISTANCE
				_spawn_coin_row()

	_update_moving_slopes(movement)
	# Barrel motion has its own fallback while the player is blocked; other
	# obstacle behavior remains synchronized to actual player movement.
	_update_moving_nodes(obstacles, movement, delta)
	_update_moving_nodes(coins, movement, delta)
	_update_moving_nodes(loot_pickups, movement, delta)
	_update_moving_nodes(gaps, movement, delta)
	_resolve_obstacle_interactions()

	if demo_mode:
		_update_demo_ai(delta)
	player.call("advance", delta, _floor_surface_y(float(player.get("world_x"))), _ceiling_surface_y(float(player.get("world_x"))), _surface_is_solid_at_x(float(player.get("world_x")), false), _surface_is_solid_at_x(float(player.get("world_x")), true))
	_update_falling_rocks(previous_world_x, float(player.get("world_x")))
	_update_saw_blades(previous_world_x, float(player.get("world_x")))
	_update_ghost_hazards(float(player.get("world_x")))
	_presentation.push(player.position)
	var run_end_requested := player.position.y < -64.0 or player.position.y > WORLD_HEIGHT + 64.0

	var blocked_by_edge := false
	for obstacle in obstacles:
		if bool(obstacle.call("is_destroying_now")):
			continue
		var player_rect: Rect2 = player.call("get_player_rect")
		var impact := HAZARD_RULES_SCRIPT.PlayerImpact.NONE
		if obstacle.is_in_group("spikes") and obstacle.has_method("get_world_triangles"):
			impact = HAZARD_RULES_SCRIPT.player_impact(player_rect, "spikes", Rect2(), obstacle.call("get_world_triangles"), Vector2.ZERO, 0.0, bool(player.call("is_spike_immune")))
		elif obstacle.is_in_group("barrels"):
			var barrel_size: Vector2 = obstacle.get("size")
			var barrel_center: Vector2 = HAZARD_RULES_SCRIPT.barrel_center(obstacle.global_position, barrel_size.x, barrel_size.y, bool(obstacle.get("from_ceiling")))
			impact = HAZARD_RULES_SCRIPT.player_impact(player_rect, "barrel", Rect2(), [], barrel_center, HAZARD_RULES_SCRIPT.barrel_radius(barrel_size.x, barrel_size.y))
		elif obstacle.is_in_group("saw_blades"):
			impact = _saw_endpoint_impact(player_rect, obstacle)
		elif obstacle.is_in_group("lava_hazards") and obstacle.has_method("is_lethal_at"):
			impact = HAZARD_RULES_SCRIPT.PlayerImpact.LETHAL if bool(obstacle.call("is_lethal_at", player_rect, _singleplayer_simulation_tick, PLAYER_X)) else HAZARD_RULES_SCRIPT.PlayerImpact.NONE
		else:
			var kind := "edge" if obstacle.is_in_group("blocking_edges") else "rect"
			impact = HAZARD_RULES_SCRIPT.player_impact(player_rect, kind, obstacle.call("get_hitbox_rect"))
		if impact == HAZARD_RULES_SCRIPT.PlayerImpact.BLOCKED:
			blocked_by_edge = true
		elif impact == HAZARD_RULES_SCRIPT.PlayerImpact.LETHAL:
			run_end_requested = true
			break
	if not game_over:
		var player_rect: Rect2 = player.call("get_player_rect")
		for terrain in slopes:
			if not terrain.has_method("is_terrain_step") or not bool(terrain.call("is_terrain_step")):
				continue
			var spike_triangles: Array = terrain.call("get_world_spike_triangles") if terrain.has_method("get_world_spike_triangles") else []
			if HAZARD_RULES_SCRIPT.player_impact(player_rect, "spikes", Rect2(), spike_triangles, Vector2.ZERO, 0.0, bool(player.call("is_spike_immune"))) == HAZARD_RULES_SCRIPT.PlayerImpact.LETHAL:
				run_end_requested = true
				break
			var from_ceiling := bool(terrain.call("is_ceiling_slope"))
			var gravity_direction := int(player.call("get_gravity_direction"))
			var step_rect: Rect2 = terrain.call("get_wall_rect")
			var impact := HAZARD_RULES_SCRIPT.player_impact(player_rect, "step", step_rect, [], Vector2.ZERO, 0.0, false, gravity_direction, from_ceiling, float(terrain.call("get_start_y")), float(terrain.call("get_end_y")))
			if impact == HAZARD_RULES_SCRIPT.PlayerImpact.BLOCKED:
				# Let the runner pass a step when its surface moves away in the
				# direction of gravity: down over a floor drop or up over a rising
				# ceiling step.
				blocked_by_edge = true
	var final_player_rect: Rect2 = player.call("get_player_rect")
	var lethal_fraction := _earliest_lethal_contact_fraction(previous_player_rect, final_player_rect)
	if lethal_fraction >= 0.0 and lethal_fraction <= 1.0:
		run_end_requested = true
	var left_the_world := player.position.y < -64.0 or player.position.y > WORLD_HEIGHT + 64.0
	if run_end_requested and not left_the_world and _campaign_runout_ticks < 0 and bool(_run_effects.call("on_lethal_contact", _key_guards_contact(final_player_rect))):
		# A bubble absorbed the hit. Forget the contact so coins past it still count.
		run_end_requested = false
		lethal_fraction = -1.0
	if not run_end_requested and not demo_mode:
		_check_near_miss(final_player_rect)
	run_blocked = blocked_by_edge and not game_over
	hud.call("set_run_blocked", run_blocked)
	if not demo_mode:
		_pull_coins_toward_runner(delta)
		for coin in coins:
			if not is_instance_valid(coin) or bool(coin.call("is_collected")):
				continue
			var center := coin.global_position
			var fraction := HAZARD_RULES_SCRIPT.swept_rect_circle_fraction(previous_player_rect, final_player_rect.position - previous_player_rect.position, center, SP_COIN_PICKUP_RADIUS)
			if render_diagnostics_enabled:
				_record_coin_sweep_diagnostic(coin, previous_player_rect, final_player_rect, fraction, lethal_fraction)
			if is_instance_valid(_sfx_audio_diagnostic_capture) and bool(_sfx_audio_diagnostic_capture.call("is_capture_active")):
				var coin_rect: Rect2 = coin.call("get_hitbox_rect")
				var broadphase := previous_player_rect.merge(final_player_rect).grow(24.0)
				if fraction >= 0.0 or broadphase.intersects(coin_rect):
					_sfx_audio_diagnostic_capture.call("record_coin_sweep", {"tick": _singleplayer_simulation_tick, "swept_fraction": fraction, "survives_terminal": fraction >= 0.0 and fraction < lethal_fraction - 0.000001, "player_rect_start": [previous_player_rect.position.x, previous_player_rect.position.y, previous_player_rect.size.x, previous_player_rect.size.y], "player_rect_end": [final_player_rect.position.x, final_player_rect.position.y, final_player_rect.size.x, final_player_rect.size.y], "coin_center": [center.x, center.y], "coin_rect": [coin_rect.position.x, coin_rect.position.y, coin_rect.size.x, coin_rect.size.y], "run_coins_before": int(run_state.get("coins"))})
			if fraction >= 0.0 and fraction < lethal_fraction - 0.000001:
				coin.call("collect")
		for pickup in loot_pickups:
			if _player_hits_obstacle(pickup):
				pickup.call("collect")
	if is_instance_valid(_campaign_run) and _campaign_runout_ticks < 0:
		var campaign_lethal := lethal_fraction if lethal_fraction >= 0.0 and lethal_fraction <= 1.0 else (1.0 if run_end_requested else INF)
		var campaign_status := str(_campaign_run.call("physics_tick", previous_player_rect, final_player_rect, campaign_lethal, float(player.get("world_x")), int(player.call("get_gravity_direction")), bool(player.get("grounded"))))
		if campaign_status == "finished":
			_begin_campaign_runout()
		elif campaign_status == "caught":
			run_end_requested = true
	if run_end_requested and _campaign_runout_ticks < 0:
		_end_run()
	var camera_left := course_distance
	if render_diagnostics_enabled:
		_record_uncollected_coin_expiry(camera_left)
	coins = _prune_passed_nodes(coins, camera_left - 100.0, true)
	loot_pickups = _prune_passed_nodes(loot_pickups, camera_left - 100.0, false)
	_run_effects.call("tick")
	_publish_effect_entries()
	queue_redraw()

## Sends the effect meters to the HUD and the anchor's touch button.
func _publish_effect_entries() -> void:
	var entries: Array[Dictionary] = _run_effects.call("get_hud_entries")
	hud.call("set_effect_entries", entries)
	if _anchor_button.visible:
		for entry in entries:
			if str(entry.get("effect_id", "")) == "gravity_anchor":
				_anchor_button.call("set_entry", entry)

## Coin magnet: coins inside the radius fly to the runner and are then picked up
## by the normal pickup sweep. A pulled coin stays pulled even if it leaves the
## radius while flying.
func _pull_coins_toward_runner(delta: float) -> void:
	var radius := float(_run_effects.call("coin_pickup_radius"))
	if radius <= 0.0:
		return
	var target: Vector2 = player.position
	var step := RUN_EFFECTS_SCRIPT.MAGNET_PULL_SPEED * delta
	for coin in coins:
		if not is_instance_valid(coin) or bool(coin.call("is_collected")):
			continue
		var to_runner := target - coin.position
		if to_runner.length() > radius and not bool(coin.get_meta("magnet_pulled", false)):
			continue
		coin.set_meta("magnet_pulled", true)
		coin.position = target if to_runner.length() <= step else coin.position + to_runner.normalized() * step

func _end_run() -> void:
	if game_over:
		return
	game_over = true
	_rock_warning_pulse.call("reset")
	_rock_warning_accessibility_button.visible = false
	if not demo_mode:
		SfxController.play_death(_singleplayer_audio_round_id, "local")
		MusicController.enter_menu()
	_presentation.reset(player.position)
	for obstacle in obstacles:
		if obstacle.has_method("freeze_render_motion"):
			obstacle.call("freeze_render_motion")
	player.call("set_input_enabled", false)
	_pb_ghost.finish(course_distance)
	if _campaign_level != null:
		# Campaign stages stay local until the campaign backend exists: no
		# leaderboard run, no account distance, a quick retry instead.
		AchievementService.finish_run()
		Campaign.record_death()
		var progress := float(_campaign_run.call("get_progress", course_distance)) if is_instance_valid(_campaign_run) else 0.0
		_show_campaign_result({"failed": true, "progress": progress})
		return
	if not demo_mode:
		AchievementService.finish_run()
		run_state.call("finish_run")
		run_end_panel.call("show_result", float(run_state.get("distance_m")), int(run_state.get("coins")), ChallengeService.get_challenge_code(), ChallengeService.active, str(run_state.get("last_run_id")), bool(run_state.get("modified")))

## The runner crossed the finish line: let it run out calmly, then score.
func _begin_campaign_runout() -> void:
	_campaign_runout_ticks = 0
	player.set("input_enabled", false)
	SfxController.play_event("campaign_goal", "%s|campaign_finish" % _singleplayer_audio_round_id, true)
	if is_instance_valid(_campaign_run):
		_campaign_run.call("celebrate")

func _complete_campaign_level() -> void:
	if game_over:
		return
	game_over = true
	_campaign_runout_ticks = -1
	_presentation.reset(player.position)
	player.call("set_input_enabled", false)
	MusicController.enter_menu()
	AchievementService.finish_run()
	var star_mask := int(_campaign_run.get("star_mask")) if is_instance_valid(_campaign_run) else 0
	var result: Dictionary = Campaign.record_completion(int(run_state.get("coins")), star_mask)
	# A finished stage beats any run that died on it; then the better score wins.
	_pb_ghost.finish(1.0e7 + float(result.get("score", 0)))
	result["failed"] = false
	result["coins"] = int(run_state.get("coins"))
	_show_campaign_result(result)

func _show_campaign_result(result: Dictionary) -> void:
	if is_instance_valid(_campaign_banner):
		_campaign_banner.call("clear")
	if not is_instance_valid(_campaign_result_panel):
		_campaign_result_panel = CampaignResultPanelScript.new() as CanvasLayer
		_campaign_result_panel.name = "CampaignResultPanel"
		_campaign_result_panel.layer = 30
		add_child(_campaign_result_panel)
		_campaign_result_panel.connect("retry_requested", retry_run)
		_campaign_result_panel.connect("next_requested", _play_next_campaign_level)
		_campaign_result_panel.connect("map_requested", return_to_main_menu)
	_campaign_result_panel.call("show_result", _campaign_level, result)

func _play_next_campaign_level() -> void:
	var next := CampaignCatalog.next_level(_campaign_level) if _campaign_level != null else null
	if next == null or not Campaign.is_level_unlocked(next):
		return_to_main_menu()
		return
	Campaign.start_level(next)
	_start_run()

func retry_run() -> void:
	if _campaign_level != null:
		_start_run()
		return
	if not bool(ChallengeService.get("active")) and _active_seed > 0:
		ChallengeService.call("start_singleplayer_seed_input", "GR%d-%d" % [_active_seed_version, _active_seed])
	_start_run()

func new_random_run() -> void:
	ChallengeService.clear_challenge()
	_start_run()

func return_to_main_menu() -> void:
	if _campaign_level != null:
		AppNavigation.request_campaign_map()
		get_tree().change_scene_to_file("res://ui/main_menu.tscn")
		return
	AppNavigation.request_game_hub()
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")

func _update_demo_ai(delta: float) -> void:
	demo_flip_timer -= delta
	var current_side := int(player.call("get_gravity_direction"))
	if run_blocked and bool(player.get("grounded")) and float(player.call("get_cooldown_left")) <= 0.0:
		player.call("_try_flip", -current_side)
		demo_flip_timer = randf_range(1.0, 1.7)
		return
	var current_risk := _demo_side_risk(current_side)
	var other_risk := _demo_side_risk(-current_side)
	var must_evade := current_risk >= 0.55 and other_risk < current_risk * 0.78
	var timed_flip := demo_flip_timer <= 0.0 and other_risk < 0.38
	if not must_evade and not timed_flip:
		return
	if not bool(player.get("grounded")) or float(player.call("get_cooldown_left")) > 0.0:
		return
	player.call("_try_flip", -current_side)
	demo_flip_timer = randf_range(0.85, 1.35) if must_evade else randf_range(1.5, 2.6)

func _demo_side_risk(side: int) -> float:
	var player_rect: Rect2 = player.call("get_player_rect")
	var risk := 0.0
	for obstacle in obstacles:
		if not is_instance_valid(obstacle) or bool(obstacle.call("is_destroying_now")):
			continue
		var obstacle_side := -1 if _demo_obstacle_from_ceiling(obstacle) else 1
		if obstacle.is_in_group("barrels"):
			obstacle_side = 1
		if obstacle_side != side:
			continue
		var hazard_rect: Rect2 = obstacle.call("get_hitbox_rect")
		var distance := hazard_rect.position.x - player_rect.end.x
		if distance < -60.0 or distance > DEMO_AI_LOOKAHEAD:
			continue
		var proximity := 1.0 - maxf(distance, 0.0) / DEMO_AI_LOOKAHEAD
		var weight := 1.0
		if obstacle.is_in_group("spikes") or obstacle.is_in_group("blocking_edges"):
			weight = 1.4
		elif obstacle.is_in_group("barrels"):
			weight = 1.25
		risk += (0.25 + proximity) * weight

	for terrain in slopes:
		if not terrain.has_method("is_terrain_step") or not bool(terrain.call("is_terrain_step")):
			continue
		var terrain_side := -1 if bool(terrain.call("is_ceiling_slope")) else 1
		if terrain_side != side:
			continue
		var distance := float(terrain.call("get_start_x")) - player_rect.end.x
		if distance < -60.0 or distance > DEMO_AI_LOOKAHEAD:
			continue
		var proximity := 1.0 - maxf(distance, 0.0) / DEMO_AI_LOOKAHEAD
		var step_weight := 2.0 if bool(terrain.get("has_spikes")) else 1.1
		risk += (0.25 + proximity) * step_weight
	return risk

func _demo_obstacle_from_ceiling(obstacle: Node) -> bool:
	for property_info in obstacle.get_property_list():
		if str(property_info.get("name", "")) != "from_ceiling":
			continue
		var direct_value: Variant = obstacle.get("from_ceiling")
		if direct_value is bool:
			return direct_value
		break
	var event_value: Variant = obstacle.get("event")
	if event_value is Dictionary:
		var event_side: Variant = event_value.get("from_ceiling", false)
		return event_side if event_side is bool else false
	return false
func _update_moving_nodes(nodes: Array[Node2D], movement: float, delta: float = 0.0) -> void:
	for node in nodes:
		if not is_instance_valid(node):
			continue
		if node.has_method("is_destroying_now") and bool(node.call("is_destroying_now")):
			continue
		if node.has_method("advance_motion"):
			node.call(
				"advance_motion",
				delta,
				movement,
				player.global_position,
				Callable(self, "_floor_surface_y"),
				Callable(self, "_surface_angle_at"),
				Callable(self, "_surface_is_solid_at_x")
			)
	var active_nodes: Array[Node2D] = []
	var camera_left := course_distance
	for node in nodes:
		if not is_instance_valid(node):
			continue
		if node.is_in_group("falling_rocks") or (node.has_method("is_destroying_now") and bool(node.call("is_destroying_now"))) or node.position.x > camera_left - 220.0:
			active_nodes.append(node)
		else:
			node.queue_free()
	nodes.clear()
	nodes.append_array(active_nodes)

func _floor_surface_y(x: float) -> float:
	return _surface_y_at(x, false)

func _ceiling_surface_y(x: float) -> float:
	return _surface_y_at(x, true)

func _surface_is_solid_at_x(x: float, ceiling: bool) -> bool:
	for gap in gaps:
		if is_instance_valid(gap) and bool(gap.call("contains_track_x", x, ceiling)):
			return false
	return true

func _surface_y_at(x: float, ceiling: bool) -> float:
	var surface_y := ceiling_level_y if ceiling else floor_level_y
	for slope in slopes:
		if bool(slope.call("is_ceiling_slope")) != ceiling:
			continue
		var start_x := float(slope.call("get_start_x"))
		if x < start_x:
			break
		if slope.has_method("is_terrain_step") and bool(slope.call("is_terrain_step")):
			if x <= start_x:
				return surface_y
			surface_y = float(slope.call("get_end_y"))
			continue
		if x <= float(slope.call("get_end_x")):
			return float(slope.call("get_surface_y_at", x))
		surface_y = float(slope.call("get_end_y"))
	return surface_y

func _surface_angle_at(x: float, ceiling: bool) -> float:
	for slope in slopes:
		if bool(slope.call("is_ceiling_slope")) != ceiling:
			continue
		var angle: float = slope.call("get_surface_angle_at", x)
		if not is_zero_approx(angle):
			return angle
	return 0.0

func _run_speed() -> float:
	return RUNNER_MOTION_SCRIPT.speed_for_multiplier(float(player.call("get_speed_multiplier")) * _equipment_speed_multiplier())

func _base_run_speed() -> float:
	return RUNNER_MOTION_SCRIPT.speed_for_multiplier(float(player.call("get_speed_multiplier")))

func _equipment_speed_multiplier() -> float:
	var equipment_multiplier := 1.0
	var snapshot: Variant = run_state.get("loadout_snapshot")
	if snapshot is Resource and snapshot.has_method("get_resolved_stats"):
		var stats: Variant = snapshot.call("get_resolved_stats")
		if stats is Dictionary:
			equipment_multiplier = float(stats.get("run_speed_percent", 10000)) / 10000.0
	return equipment_multiplier

func _update_speed_debug() -> void:
	if not _speed_debug_visible or not is_instance_valid(hud):
		return
	hud.call("set_speed_debug_values", _run_speed(), _base_run_speed(), _equipment_speed_multiplier() * 100.0)

func _spawn_course_event(event: Dictionary) -> void:
	var event_x := PLAYER_X + float(event["course_distance"])
	var event_spawn_lead := COURSE_GENERATOR_SCRIPT.get_viewport_spawn_lead_distance(screen_width, PLAYER_X, SLOPE_WIDTH)
	var from_ceiling := bool(event.get("from_ceiling", false))
	var width := float(event.get("width", 48.0))
	var height := float(event.get("height", 72.0))
	var event_kind := StringName(event.get("kind", ""))
	var resolved_ghost_event: Dictionary = {}
	var ghost_source_key := ""
	if event_kind == &"ghost":
		ghost_source_key = _singleplayer_ghost_key(event)
		resolved_ghost_event = _resolve_singleplayer_ghost_event(event)
		if bool(resolved_ghost_event.get("gen19_supported_fallback", false)):
			# Replacements are ordinary blocks, so they must wait for the normal
			# spawn horizon rather than appearing at the source ghost's warning lead.
			if float(event.get("course_distance", INF)) > course_distance + event_spawn_lead + 0.5:
				return
			if _singleplayer_spawned_gen19_fallback_ids.has(ghost_source_key):
				return
	if event_kind == &"block" or event_kind == &"barrels":
		var lane_clearance := _floor_surface_y(event_x) - _ceiling_surface_y(event_x)
		# Keep the authored hazard dimensions. If it cannot fit while leaving a
		# character-sized route in the opposite lane, omit this encounter.
		if lane_clearance < height + 44.0 + 12.0:
			return
	var hazard_id := str(event.get("id", ""))
	if is_instance_valid(_campaign_run):
		_campaign_run.call("on_event_spawned", event)
	if not hazard_id.is_empty():
		_pending_hazard_discoveries.append({
			"hazard_id": hazard_id,
			"course_distance": float(event.get("course_distance", 0.0)),
			"width": float(event.get("width", 48.0)),
		})
	match event_kind:
		&"spikes":
			var count := int(event.get("count", 4))
			var group_width := float(count - 1) * SPIKE_GROUP_SPACING
			_spawn_spike_group(count, from_ceiling, event_x - group_width * 0.5)
			if bool(event.get("ghost_fire", false)):
				# The Ghost King's fire: same spikes, drawn as purple ghost flames.
				for index in range(maxi(obstacles.size() - count, 0), obstacles.size()):
					obstacles[index].set("skin", "ghost_fire")
		&"block":
			_spawn_obstacle_scene(BLOCK_SCENE, width, height, from_ceiling, event_x)
		&"barrels":
			var count := int(event.get("count", 1))
			var chain_width := float(count - 1) * HAZARD_RULES_SCRIPT.BARREL_CHAIN_SPACING
			var motion_speed_multiplier := float(event.get("motion_speed_multiplier", 1.0))
			# Keep the barrel's encounter timing tied to the canonical planner lead
			# even when a wide desktop viewport requires spawning it much earlier.
			var canonical_barrel_lead := event_spawn_lead
			if _active_seed_version < COURSE_GENERATOR_SCRIPT.GENERATOR_VERSION_21:
				canonical_barrel_lead = maxf(event_spawn_lead - COURSE_GENERATOR_SCRIPT.EVENT_SPAWN_LEAD_DISTANCE, 0.0)
			var early_spawn_offset := canonical_barrel_lead * (motion_speed_multiplier - 1.0)
			for index in range(count):
				var barrel_x := event_x + early_spawn_offset - chain_width * 0.5 + float(index) * HAZARD_RULES_SCRIPT.BARREL_CHAIN_SPACING
				# Rullaren throws its barrels from the hatch instead of rolling them in
				# from the screen edge; they join the course on the same path later.
				if bool(event.get("boss_attack", false)) and is_instance_valid(_campaign_run) and bool(_campaign_run.call("queue_thrown_barrel", {"x": barrel_x, "course_distance": course_distance, "height": height, "speed": motion_speed_multiplier, "spiked": bool(event.get("spiked", false))})):
					continue
				_spawn_obstacle_scene(BARREL_SCENE, HAZARD_RULES_SCRIPT.BARREL_WIDTH, height, false, barrel_x, motion_speed_multiplier, bool(event.get("spiked", false)), int(event.get("barrel_variant", 0)) == 1, float(event.get("rubber_target_x", -1.0)))
		&"gap":
			var gap := TRACK_GAP_SCRIPT.new() as TrackGap
			gap.position = Vector2(event_x, 0.0)
			gap.configure(width, from_ceiling)
			add_child(gap)
			gaps.append(gap)
		&"step":
			_spawn_ledge(event, event_x)
		&"slope":
			_spawn_course_slope(event, event_x)
		&"rock":
			var is_icicle := _active_seed_version >= COURSE_GENERATOR_SCRIPT.GENERATOR_VERSION_17 and str(event.get("id", "")) == "cave_icicle"
			var near_terrain := false
			# Feature rocks sit in a quiet stretch with no terrain events, checked
			# by the level tool and the campaign runtime test.
			for planned in ([] if bool(event.get("feature_event", false)) else course_generator.get_planned_events()):
				var planned_kind := str(planned.get("kind", ""))
				if planned_kind in ["step", "slope"] or (planned_kind == "gap" and not (is_icicle and not bool(planned.get("from_ceiling", false)))):
					if absf(float(planned.get("course_distance", 0.0)) - float(event.get("course_distance", 0.0))) < 420.0:
						near_terrain = true
						break
			# Scripted feature rocks (cave-ins) are low and wide-spaced; they keep a
			# route on the other surface at a smaller lane height than generated rocks.
			var min_lane := CAMPAIGN_FEATURES_SCRIPT.ROCK_MIN_LANE if bool(event.get("feature_event", false)) else 260.0
			if not near_terrain and _floor_surface_y(event_x) - _ceiling_surface_y(event_x) >= min_lane:
				var rock := FALLING_ROCK_SCENE.instantiate() as Node2D
				var rock_event_id := _singleplayer_rock_key(event)
				rock.connect("impact_started", Callable(self, "_on_rock_impact_started"))
				var rock_event := {"event_id": rock_event_id, "kind": "rock", "x": event_x, "width": width, "height": height, "floor_y": _floor_surface_y(event_x), "ceiling_y": _ceiling_surface_y(event_x), "trigger_lead": float(event.get("trigger_lead", FALLING_ROCK_MODEL.TRIGGER_LEAD)), "warning_ticks": int(event.get("warning_ticks", FALLING_ROCK_MODEL.WARNING_TICKS)), "fall_ticks": int(event.get("fall_ticks", FALLING_ROCK_MODEL.FALL_TICKS)), "burial_depth": float(event.get("burial_depth", FALLING_ROCK_MODEL.BURIAL_DEPTH))}
				if bool(event.get("boss_attack", false)) and int(event.get("rock_variant", 0)) == 1:
					# A boss icicle has no planned source event to resolve.
					rock_event.merge({"rock_variant": 1, "floor_supported": true, "lodged_ticks": int(event.get("lodged_ticks", 240))}, true)
				if is_icicle:
					var resolved_icicle := _resolve_singleplayer_rock_event(event)
					if resolved_icicle.is_empty():
						return
					rock_event = resolved_icicle
					rock_event["event_id"] = rock_event_id
				rock.call("configure", rock_event)
				rock.name = "FallingRock_%s" % rock_event_id
				if _campaign_level != null and BIOME_RENDERER_SCRIPT.locked_pixel_palette() != null:
					rock.set("skin", "pixel")
				add_child(rock)
				obstacles.append(rock)
		&"bat_swarm":
			_spawn_bat_swarm(event, event_x)
		&"ghost_hand":
			_spawn_ghost_hand(event, event_x)
		&"ember_bomb":
			_spawn_ghost_hand(event, event_x, EMBER_BOMB_SCRIPT, "EmberBomb")
		&"lightning":
			_spawn_ghost_hand(event, event_x, LIGHTNING_SCRIPT, "Lightning")
		&"saw":
			var saw_event := _resolve_singleplayer_saw_event(event)
			if saw_event.is_empty():
				return
			var saw_event_id := str(saw_event.get("event_id", _singleplayer_saw_key(event)))
			if bool(saw_event.get("from_ceiling", false)) and str(saw_event.get("saw_variant", "legacy_floor_then_drop")) in ["legacy_floor_then_drop", "ceiling_gap_drop"]:
				var gap := TRACK_GAP_SCRIPT.new() as TrackGap
				gap.position = Vector2(float(saw_event.get("roof_gap_x", event_x + SAW_BLADE_MODEL.ROOF_GAP_OFFSET)), 0.0)
				gap.configure(float(saw_event.get("roof_gap_width", SAW_BLADE_MODEL.ROOF_GAP_WIDTH)), true)
				gap.name = "SawRoofGap_%s" % saw_event_id
				add_child(gap)
				gaps.append(gap)
			var saw := SAW_BLADE_SCENE.instantiate() as Node2D
			var saw_key := str(saw_event.get("source_saw_key", _singleplayer_saw_key(event)))
			var saw_surface_index: RefCounted = _singleplayer_saw_surface_indexes.get(saw_key)
			var surface_callable := Callable(saw_surface_index, "surface_at") if saw_surface_index != null else Callable(self, "_saw_surface_at")
			saw.call("configure", saw_event, surface_callable, PLAYER_X, 0)
			saw.name = "SawBlade_%s" % saw_event_id
			add_child(saw)
			obstacles.append(saw)
			if _singleplayer_saw_activation_ticks.has(saw_key):
				saw.call("set_activation_tick", int(_singleplayer_saw_activation_ticks[saw_key]))
				saw.call("set_simulation_tick", _singleplayer_simulation_tick)
		&"ghost":
			var ghost_event := resolved_ghost_event
			if ghost_event.is_empty():
				_singleplayer_resolved_ghost_events.erase(ghost_source_key)
				return
			if bool(ghost_event.get("gen19_supported_fallback", false)) and str(ghost_event.get("kind", "")) == "block":
				_singleplayer_spawned_gen19_fallback_ids[ghost_source_key] = true
				_spawn_obstacle_scene(BLOCK_SCENE, float(ghost_event.get("width", 44.0)), float(ghost_event.get("height", 72.0)), false, float(ghost_event.get("x", event_x)))
				_singleplayer_resolved_ghost_events.erase(ghost_source_key)
				return
			var ghost_id := str(ghost_event.get("event_id", _singleplayer_ghost_key(event)))
			var ghost := GHOST_HAZARD_SCENE.instantiate() as Node2D
			ghost.call("configure", ghost_event)
			ghost.name = "Ghost_%s" % ghost_id
			ghost.connect("phase_changed", Callable(self, "_on_singleplayer_ghost_phase_changed").bind(ghost_event))
			add_child(ghost)
			obstacles.append(ghost)
			if _singleplayer_ghost_activation_ticks.has(ghost_id):
				ghost.call("set_activation_tick", int(_singleplayer_ghost_activation_ticks[ghost_id]))
				ghost.call("set_simulation_tick", _singleplayer_simulation_tick)
			elif _singleplayer_ghost_activation_snapshots.has(ghost_id):
				ghost.call("set_activation_snapshot", _singleplayer_ghost_activation_snapshots[ghost_id])
				ghost.call("set_simulation_tick", _singleplayer_simulation_tick)
			_singleplayer_resolved_ghost_events.erase(ghost_source_key)
		&"lava_crack", &"volcano":
			_spawn_singleplayer_lava_event(event, event_x)
		_:
			_spawn_custom_course_event(event, event_x)

## Campaign cave feature: a flapping swarm in one lane (see hazards/bat_swarm.gd).
func _spawn_bat_swarm(event: Dictionary, event_x: float) -> void:
	var from_ceiling := bool(event.get("from_ceiling", false))
	var lane_clearance := _floor_surface_y(event_x) - _ceiling_surface_y(event_x)
	if lane_clearance < float(event.get("height", 84.0)) + 44.0 + 12.0:
		return
	var swarm := BAT_SWARM_SCRIPT.new() as Node2D
	swarm.name = "BatSwarm_%.0f" % float(event.get("course_distance", 0.0))
	swarm.call("configure_swarm", event, event_x, _ceiling_surface_y(event_x) if from_ceiling else _floor_surface_y(event_x))
	swarm.connect("warning_started", Callable(self, "_on_bat_swarm_warning"))
	add_child(swarm)
	obstacles.append(swarm)

## Campaign haunted feature: a hand that reaches out of one lane (hazards/ghost_hand.gd).
## Volcano ember bombs (hazards/ember_bomb.gd) reuse the hand with their own look.
func _spawn_ghost_hand(event: Dictionary, event_x: float, script: GDScript = GHOST_HAND_SCRIPT, prefix: String = "GhostHand") -> void:
	var from_ceiling := bool(event.get("from_ceiling", false))
	var lane_clearance := _floor_surface_y(event_x) - _ceiling_surface_y(event_x)
	if lane_clearance < float(event.get("height", 120.0)) + 44.0 + 12.0:
		return
	var hand := script.new() as Node2D
	hand.name = prefix + "_%.0f" % float(event.get("course_distance", 0.0))
	hand.call("configure_hand", event, event_x, _ceiling_surface_y(event_x) if from_ceiling else _floor_surface_y(event_x))
	hand.connect("emerged", Callable(self, "_on_ghost_hand_emerged"))
	add_child(hand)
	obstacles.append(hand)

func _on_ghost_hand_emerged(hand: Node2D) -> void:
	var sound := "hand_scrape"
	if hand.is_in_group("ember_bombs"):
		sound = "ember_impact"
	elif hand.is_in_group("lightning_strikes"):
		sound = "thunder_crack"
	_play_cave_sfx(sound, "%s|ghost_hand|%s" % [_singleplayer_audio_round_id, str(hand.name)], _is_singleplayer_event_audible(hand.global_position.x))

func _on_campaign_bonus_coins(amount: int) -> void:
	run_state.call("add_coins", amount)
	_play_singleplayer_sfx("coin", "%s|wisp_coins|%d" % [_singleplayer_audio_round_id, _singleplayer_simulation_tick])

func _on_bat_swarm_warning(swarm: Node2D) -> void:
	_play_cave_sfx("cave_bat_screech", "%s|bat_swarm|%s" % [_singleplayer_audio_round_id, str(swarm.name)], _is_singleplayer_event_audible(swarm.global_position.x))

func _on_campaign_feature_cue(sound: String, key: String) -> void:
	_play_cave_sfx(sound, "%s|%s" % [_singleplayer_audio_round_id, key])

## Cave sounds are added separately; until a sound exists this does nothing.
func _play_cave_sfx(sound: String, event_key: String, audible: bool = true) -> bool:
	if not SfxController.STREAMS.has(sound):
		return false
	return _play_singleplayer_sfx(sound, event_key, audible)

func _spawn_singleplayer_lava_event(source_event: Dictionary, target_x: float) -> void:
	var horizon := ceili(maxf(float(course_distance) + screen_width + 2400.0, float(source_event.get("course_distance", 0.0)) + 1.0))
	var biome_start_offset := BIOME_RENDERER_SCRIPT.start_biome_offset_for_seed(_active_seed, _active_seed_version)
	var resolved_events: Array[Dictionary] = _manifest_builder.call("resolve_runtime_events", course_generator.get_planned_events(), horizon, _active_seed_version, biome_start_offset)
	var source_kind := str(source_event.get("kind", ""))
	for event in resolved_events:
		if str(event.get("kind", "")) != source_kind or absf(float(event.get("x", INF)) - target_x) > 0.5:
			continue
		var hazard := LAVA_HAZARD_SCENE.instantiate() as Node2D
		hazard.call("configure", event, PLAYER_X)
		hazard.call("apply_simulation_tick", _singleplayer_simulation_tick, PLAYER_X)
		hazard.name = "Lava_%s" % str(event.get("event_id", ""))
		add_child(hazard)
		obstacles.append(hazard)
		return

func _update_hazard_discoveries() -> void:
	for index in range(_pending_hazard_discoveries.size() - 1, -1, -1):
		var encounter: Dictionary = _pending_hazard_discoveries[index]
		var event_x := PLAYER_X + float(encounter["course_distance"]) - course_distance
		var half_width := float(encounter["width"]) * 0.5
		if event_x - half_width > screen_width:
			continue
		if event_x + half_width >= 0.0:
			run_state.call("record_hazard_seen", str(encounter["hazard_id"]))
		_pending_hazard_discoveries.remove_at(index)

func _spawn_custom_course_event(event: Dictionary, x: float) -> void:
	var profile := event.get("profile") as CourseHazardProfile
	if profile == null or profile.runtime_scene == null:
		push_warning("Course event '%s' has no runtime scene; skipped." % str(event.get("id", "unknown")))
		return
	var hazard := profile.runtime_scene.instantiate() as Node2D
	if hazard == null or not hazard.has_method("configure_course_event"):
		push_warning("Course event '%s' scene must implement configure_course_event(event)." % str(profile.profile_id))
		if is_instance_valid(hazard):
			hazard.queue_free()
		return
	if hazard.has_signal("destroyed"):
		hazard.connect("destroyed", Callable(self, "_on_obstacle_destroyed"))
	hazard.position.x = x
	hazard.call("configure_course_event", event)
	add_child(hazard)
	obstacles.append(hazard)

func _singleplayer_rock_key(event: Dictionary) -> String:
	# Profile ids identify the rock type, not an individual encounter.
	# Pair with its deterministic course position so early-spawn and normal
	# event-pop paths deduplicate the same rock without suppressing later rocks.
	return "%s:%.3f" % [str(event.get("id", "rock")), float(event.get("course_distance", -1.0))]

func _singleplayer_saw_key(event: Dictionary) -> String:
	return "%s:%.3f" % [str(event.get("id", "saw")), float(event.get("course_distance", -1.0))]

func _singleplayer_ghost_key(event: Dictionary) -> String:
	return "%s:%.3f" % [str(event.get("id", "ghost")), float(event.get("course_distance", -1.0))]

func _resolve_singleplayer_saw_event(source_event: Dictionary) -> Dictionary:
	if course_generator == null or _manifest_builder == null:
		return {}
	var source_distance := float(source_event.get("course_distance", 0.0))
	var support_horizon := source_distance + SAW_BLADE_MODEL.START_OFFSET + 3000.0
	course_generator.ensure_horizon(support_horizon, _run_speed(), screen_height, COURSE_GENERATOR_SCRIPT.EVENT_SPAWN_LEAD_DISTANCE)
	var biome_start_offset := BIOME_RENDERER_SCRIPT.start_biome_offset_for_seed(_active_seed, _active_seed_version)
	var resolved_events: Array[Dictionary] = _manifest_builder.call("resolve_runtime_events", course_generator.get_planned_events(), ceili(support_horizon), _active_seed_version, biome_start_offset)
	var target_x := PLAYER_X + source_distance
	for resolved_event in resolved_events:
		if str(resolved_event.get("kind", "")) == "saw" and absf(float(resolved_event.get("x", INF)) - target_x) < 0.5:
			var result := resolved_event.duplicate(true)
			result["source_saw_key"] = _singleplayer_saw_key(source_event)
			var surface_index: RefCounted = COURSE_SURFACE_INDEX_SCRIPT.new()
			surface_index.call("configure", resolved_events, WORLD_HEIGHT - 80.0, 80.0)
			_singleplayer_saw_surface_indexes[_singleplayer_saw_key(source_event)] = surface_index
			return result
	return {}

func _resolve_singleplayer_ghost_event(source_event: Dictionary) -> Dictionary:
	if course_generator == null or _manifest_builder == null:
		return {}
	var source_key := _singleplayer_ghost_key(source_event)
	if _singleplayer_resolved_ghost_events.has(source_key):
		var cached: Variant = _singleplayer_resolved_ghost_events.get(source_key, {})
		return (cached as Dictionary).duplicate(true)
	var source_distance := float(source_event.get("course_distance", 0.0))
	var support_horizon := source_distance + float(source_event.get("trigger_lead", 1700.0)) + float(source_event.get("chase_start_lag", 220.0)) + float(source_event.get("chase_speed", 760.0)) * float(source_event.get("danger_ticks", 210)) / 60.0 + 900.0
	course_generator.ensure_horizon(support_horizon, _run_speed(), screen_height, COURSE_GENERATOR_SCRIPT.EVENT_SPAWN_LEAD_DISTANCE)
	var biome_start_offset := BIOME_RENDERER_SCRIPT.start_biome_offset_for_seed(_active_seed, _active_seed_version)
	var resolved_events: Array[Dictionary] = _manifest_builder.call("resolve_runtime_events", course_generator.get_planned_events(), ceili(support_horizon), _active_seed_version, biome_start_offset)
	var target_x := PLAYER_X + source_distance
	for resolved_event in resolved_events:
		var is_source_ghost := str(resolved_event.get("kind", "")) == "ghost"
		var is_supported_fallback := bool(resolved_event.get("gen19_supported_fallback", false)) and str(resolved_event.get("gen19_replaced_kind", "")) == "ghost_pursuit"
		if (is_source_ghost or is_supported_fallback) and absf(float(resolved_event.get("x", INF)) - target_x) < 0.5:
			var result := resolved_event.duplicate(true)
			result["source_ghost_key"] = source_key
			_singleplayer_resolved_ghost_events[source_key] = result.duplicate(true)
			return result
	return {}

func _resolve_singleplayer_rock_event(source_event: Dictionary) -> Dictionary:
	if course_generator == null or _manifest_builder == null:
		return {}
	var source_distance := float(source_event.get("course_distance", 0.0))
	var support_horizon := source_distance + 200.0
	course_generator.ensure_horizon(support_horizon, _run_speed(), screen_height, COURSE_GENERATOR_SCRIPT.EVENT_SPAWN_LEAD_DISTANCE)
	var biome_start_offset := BIOME_RENDERER_SCRIPT.start_biome_offset_for_seed(_active_seed, _active_seed_version)
	var resolved_events: Array[Dictionary] = _manifest_builder.call("resolve_runtime_events", course_generator.get_planned_events(), ceili(support_horizon), _active_seed_version, biome_start_offset)
	var target_x := PLAYER_X + source_distance
	for resolved_event in resolved_events:
		if str(resolved_event.get("kind", "")) == "rock" and absf(float(resolved_event.get("x", INF)) - target_x) < 0.5:
			return resolved_event.duplicate(true)
	return {}

## True when the early-spawn loop can never act on this event again.
func _early_spawn_is_settled(planned_event: Dictionary) -> bool:
	if float(planned_event.get("course_distance", INF)) + PLANNED_SCAN_SETTLED_BEHIND >= course_distance:
		return false
	match str(planned_event.get("kind", "")):
		"rock":
			return _spawned_early_rock_ids.has(_singleplayer_rock_key(planned_event))
		"saw":
			return _spawned_early_saw_ids.has(_singleplayer_saw_key(planned_event))
		"ghost":
			var ghost_id := _singleplayer_ghost_key(planned_event)
			if _spawned_early_ghost_ids.has(ghost_id):
				return true
			var cached: Variant = _singleplayer_resolved_ghost_events.get(ghost_id)
			return cached is Dictionary and bool((cached as Dictionary).get("gen19_supported_fallback", false))
	return true

func _saw_surface_at(x: float, ceiling: bool) -> Dictionary:
	return {"y": _ceiling_surface_y(x) if ceiling else _floor_surface_y(x), "supported": _surface_is_solid_at_x(x, ceiling)}

func _update_saw_blades(previous_world_x: float = -1.0, current_world_x: float = -1.0) -> void:
	if current_world_x >= 0.0 and is_finite(current_world_x):
		var planned_events := course_generator.get_planned_events()
		for planned_index in range(_saw_activation_scan_index, planned_events.size()):
			var planned_event: Dictionary = planned_events[planned_index]
			if str(planned_event.get("kind", "")) != "saw":
				continue
			var saw_key := _singleplayer_saw_key(planned_event)
			var trigger_x := PLAYER_X + float(planned_event.get("course_distance", 0.0)) + SAW_BLADE_MODEL.START_OFFSET - SAW_BLADE_MODEL.SPAWN_LEAD
			if not _singleplayer_saw_activation_ticks.has(saw_key) and current_world_x >= trigger_x:
				_singleplayer_saw_activation_ticks[saw_key] = _singleplayer_simulation_tick + SAW_BLADE_MODEL.ACTIVATION_DELAY_TICKS
		while _saw_activation_scan_index < planned_events.size():
			var settled_event: Dictionary = planned_events[_saw_activation_scan_index]
			if float(settled_event.get("course_distance", INF)) + PLANNED_SCAN_SETTLED_BEHIND >= course_distance:
				break
			if str(settled_event.get("kind", "")) == "saw" and not _singleplayer_saw_activation_ticks.has(_singleplayer_saw_key(settled_event)):
				break
			_saw_activation_scan_index += 1
	for obstacle in obstacles:
		if is_instance_valid(obstacle) and obstacle.is_in_group("saw_blades"):
			var event: Dictionary = obstacle.get("event")
			var saw_key := str(event.get("source_saw_key", _singleplayer_saw_key(event)))
			if _singleplayer_saw_activation_ticks.has(saw_key) and int(obstacle.get("state").get("activation_tick", -1)) != int(_singleplayer_saw_activation_ticks[saw_key]):
				obstacle.call("set_activation_tick", int(_singleplayer_saw_activation_ticks[saw_key]))
			obstacle.call("set_simulation_tick", _singleplayer_simulation_tick)

func _update_falling_rocks(previous_x: float, current_x: float) -> void:
	for obstacle in obstacles:
		if not is_instance_valid(obstacle) or not obstacle.is_in_group("falling_rocks"):
			continue
		obstacle.call("set_simulation_tick", _singleplayer_simulation_tick)
		if int(obstacle.call("get_activation_tick")) >= 0:
			continue
		var event: Dictionary = obstacle.get("event")
		var trigger_x := float(event.get("x", 0.0)) - float(event.get("trigger_lead", FALLING_ROCK_MODEL.TRIGGER_LEAD))
		if current_x >= trigger_x:
			obstacle.call("set_activation_tick", _singleplayer_simulation_tick + FALLING_ROCK_MODEL.DELIVERY_TICKS)
			obstacle.call("set_simulation_tick", _singleplayer_simulation_tick)

func _update_ghost_hazards(current_x: float) -> void:
	for obstacle in obstacles:
		if not is_instance_valid(obstacle) or not obstacle.is_in_group("ghost_hazards"):
			continue
		var event: Dictionary = obstacle.get("event")
		var event_id := str(event.get("event_id", ""))
		if int(event.get("ghost_variant", 0)) in [2, 3]:
			if not _singleplayer_ghost_activation_snapshots.has(event_id) and current_x >= GHOST_HAZARD_MODEL.trigger_x(event) and bool(player.get("grounded")):
				var lane := COURSE_GENERATOR_SCRIPT.FLOOR_LANE if int(player.call("get_gravity_direction")) > 0 else COURSE_GENERATOR_SCRIPT.CEILING_LANE
				var snapshot := {"activation_tick": _singleplayer_simulation_tick, "lane": lane, "world_x": float(player.get("world_x")), "speed": clampf(_run_speed(), 200.0, 800.0), "target_peer_id": 1}
				_singleplayer_ghost_activation_snapshots[event_id] = snapshot
				obstacle.call("set_activation_snapshot", snapshot)
		elif not _singleplayer_ghost_activation_ticks.has(event_id) and current_x >= GHOST_HAZARD_MODEL.trigger_x(event):
			_singleplayer_ghost_activation_ticks[event_id] = _singleplayer_simulation_tick
			obstacle.call("set_activation_tick", _singleplayer_simulation_tick)
		obstacle.call("set_simulation_tick", _singleplayer_simulation_tick)

func _spawn_spike_group(count: int, from_ceiling: bool, start_x: float) -> void:
	for i in range(count):
		var spike_x := start_x + float(i) * SPIKE_GROUP_SPACING
		_spawn_obstacle_scene(SPIKE_SCENE, SPIKE_WIDTH, SPIKE_HEIGHT, from_ceiling, spike_x)

func _spawn_ledge(event: Dictionary, x: float) -> void:
	var from_ceiling := bool(event.get("from_ceiling", false))
	var has_spikes := bool(event.get("spiked_step", false))
	var start_y := planned_ceiling_level_y if from_ceiling else planned_floor_level_y
	var change := float(event.get("height", 84.0))
	var low_limit := 40.0 if from_ceiling else 330.0
	var high_limit := 220.0 if from_ceiling else WORLD_HEIGHT - 40.0
	var end_y: float = start_y + change if from_ceiling else start_y - change
	end_y = clampf(end_y, low_limit, high_limit)
	if absf(end_y - start_y) < 40.0:
		end_y = clampf(start_y - change if from_ceiling else start_y + change, low_limit, high_limit)
	var step := LEDGE_SCENE.instantiate() as Node2D
	step.position = Vector2(x, 0.0)
	step.call("configure_step", start_y, end_y, from_ceiling, has_spikes)
	add_child(step)
	slopes.append(step)
	if has_spikes:
		var spike_count := int(event.get("count", 4))
		var spike_width := float(spike_count - 1) * SPIKE_GROUP_SPACING
		var points_left := bool(step.call("spikes_point_left"))
		var spike_start_x := x + STEP_SPIKE_CLEARANCE if points_left else x - spike_width - STEP_SPIKE_CLEARANCE
		_spawn_spike_group(spike_count, from_ceiling, spike_start_x)
	if from_ceiling:
		planned_ceiling_level_y = end_y
	else:
		planned_floor_level_y = end_y

func _spawn_course_slope(event: Dictionary, center_x: float) -> void:
	var from_ceiling := bool(event.get("from_ceiling", false))
	var start_y := planned_ceiling_level_y if from_ceiling else planned_floor_level_y
	var low_limit := 40.0 if from_ceiling else 330.0
	var high_limit := 220.0 if from_ceiling else WORLD_HEIGHT - 40.0
	var direction := float(event.get("slope_direction", 1.0))
	var end_y := clampf(start_y + direction * float(event.get("height", 65.0)), low_limit, high_limit)
	if absf(end_y - start_y) < 40.0:
		end_y = clampf(start_y - direction * 45.0, low_limit, high_limit)
	var slope := SLOPE_SCENE.instantiate() as Node2D
	slope.position = Vector2(center_x - SLOPE_WIDTH * 0.5, start_y)
	slope.call("configure", start_y, end_y, from_ceiling)
	if from_ceiling:
		planned_ceiling_level_y = end_y
	else:
		planned_floor_level_y = end_y
	add_child(slope)
	slopes.append(slope)

func _resolve_obstacle_interactions() -> void:
	for barrel in obstacles:
		if not is_instance_valid(barrel) or barrel.is_queued_for_deletion() or not barrel.is_in_group("barrels"):
			continue
		if bool(barrel.call("is_destroying_now")) or bool(barrel.get("retired")):
			continue
		var barrel_size: Vector2 = barrel.get("size")
		var radius := HAZARD_RULES_SCRIPT.barrel_radius(barrel_size.x, barrel_size.y)
		var center := HAZARD_RULES_SCRIPT.barrel_center(barrel.global_position, barrel_size.x, barrel_size.y, bool(barrel.get("from_ceiling")))
		var rubber_barrel := bool(barrel.get("is_rubber"))
		for obstacle in obstacles:
			if obstacle == barrel or not is_instance_valid(obstacle) or obstacle.is_queued_for_deletion() or bool(obstacle.call("is_destroying_now")):
				continue
			if obstacle.is_in_group("spikes") and obstacle.has_method("get_world_triangles"):
				var impact: int = HAZARD_RULES_SCRIPT.barrel_impact(center, radius, "spikes", Rect2(), obstacle.call("get_world_triangles"))
				if impact == HAZARD_RULES_SCRIPT.BarrelImpact.BARREL_DESTROYED:
					barrel.call("destroy")
					break
		if bool(barrel.call("is_destroying_now")):
			continue
		var rubber_bounced := false
		# Rubber contacts choose blocks before steps in both SP and the shared MP
		# resolver. The authored target only describes the generated pairing; any
		# active block physically touched can reverse the barrel.
		if rubber_barrel:
			for obstacle in obstacles:
				if obstacle == barrel or not is_instance_valid(obstacle) or obstacle.is_queued_for_deletion() or bool(obstacle.call("is_destroying_now")) or not obstacle.is_in_group("breakable"):
					continue
				var rubber_block_rect: Rect2 = obstacle.call("get_hitbox_rect")
				var rubber_block_impact: int = HAZARD_RULES_SCRIPT.barrel_impact(center, radius, "block", rubber_block_rect, [], true)
				if rubber_block_impact == HAZARD_RULES_SCRIPT.BarrelImpact.RUBBER_BOUNCE:
					barrel.call("bounce_from_rect", rubber_block_rect)
					rubber_bounced = true
					break
		if rubber_bounced:
			continue
		for terrain in slopes:
			if not terrain.has_method("is_terrain_step") or not bool(terrain.call("is_terrain_step")):
				continue
			if bool(terrain.get("has_spikes")) and terrain.has_method("get_world_spike_triangles"):
				var spike_impact: int = HAZARD_RULES_SCRIPT.barrel_impact(center, radius, "spikes", Rect2(), terrain.call("get_world_spike_triangles"))
				if spike_impact == HAZARD_RULES_SCRIPT.BarrelImpact.BARREL_DESTROYED:
					barrel.call("destroy")
					break
			# Barrels travel left with the world; allow them to roll off a floor drop.
			var is_floor_drop := not bool(terrain.call("is_ceiling_slope")) and float(terrain.call("get_start_y")) > float(terrain.call("get_end_y"))
			var wall_rect: Rect2 = terrain.call("get_wall_rect")
			var step_impact: int = HAZARD_RULES_SCRIPT.barrel_impact(center, radius, "step", wall_rect, [], rubber_barrel)
			if not is_floor_drop and step_impact == HAZARD_RULES_SCRIPT.BarrelImpact.RUBBER_BOUNCE:
				barrel.call("bounce_from_rect", wall_rect)
				rubber_bounced = true
				break
			if not is_floor_drop and step_impact == HAZARD_RULES_SCRIPT.BarrelImpact.BARREL_DESTROYED:
				barrel.call("destroy")
				break
		if rubber_bounced:
			continue
		if bool(barrel.call("is_destroying_now")):
			continue
		# Rubber blocks have already been resolved above so their precedence over
		# steps is stable; ordinary and spiked barrels retain their legacy path.
		if rubber_barrel:
			continue
		for obstacle in obstacles:
			if obstacle == barrel or not is_instance_valid(obstacle) or obstacle.is_queued_for_deletion() or bool(obstacle.call("is_destroying_now")):
				continue
			if not obstacle.is_in_group("breakable"):
				continue
			var block_rect: Rect2 = obstacle.call("get_hitbox_rect")
			var block_impact: int = HAZARD_RULES_SCRIPT.barrel_impact(center, radius, "block", block_rect, [], rubber_barrel)
			if block_impact == HAZARD_RULES_SCRIPT.BarrelImpact.RUBBER_BOUNCE:
				barrel.call("bounce_from_rect", block_rect)
				break
			if block_impact == HAZARD_RULES_SCRIPT.BarrelImpact.BARREL_AND_TARGET_DESTROYED:
				obstacle.call("destroy")
				if not bool(barrel.get("is_spiked")):
					barrel.call("destroy")
					break
	obstacles = obstacles.filter(func(obstacle: Node2D) -> bool:
		return is_instance_valid(obstacle) and not obstacle.is_queued_for_deletion()
	)

func _spawn_obstacle_scene(scene: PackedScene, width: float, height: float, from_ceiling: bool, x: float, motion_speed_multiplier: float = 1.0, spiked_barrel: bool = false, rubber_barrel: bool = false, rubber_target_x: float = -1.0) -> void:
	var obstacle := CoursePresentation.create_hazard(scene, Vector2(x, _ceiling_surface_y(x) if from_ceiling else _floor_surface_y(x)), Vector2(width, height), from_ceiling, _surface_angle_at(x, from_ceiling))
	obstacle.connect("destroyed", Callable(self, "_on_obstacle_destroyed"))
	if obstacle.is_in_group("barrels") and obstacle.has_signal("destruction_started"):
		_connect_barrel_audio(obstacle)
	# Campaign cave stages draw rolling barrels as mine carts (skin only).
	if obstacle.is_in_group("barrels") and _campaign_level != null and _campaign_level.world_id == &"cave":
		obstacle.set("skin", "mine_cart")
	# Pixel-style biomes draw barrels (not a boss machine's own barrels; the
	# Snow Giant's are the frost world's snowballs),
	# blocks and spikes as pixel art.
	if _campaign_level != null and BIOME_RENDERER_SCRIPT.locked_pixel_palette() != null and str(obstacle.get("skin")).is_empty() and ((obstacle.is_in_group("barrels") and (not _campaign_level.is_boss() or _campaign_level.boss_id == &"snow_giant")) or obstacle.is_in_group("breakable") or obstacle.is_in_group("spikes")):
		obstacle.set("skin", "pixel")
	# Haunted campaign stages draw blocks and spikes as gravestones and crosses.
	if _campaign_level != null and _campaign_level.world_id == &"haunted" and (obstacle.is_in_group("breakable") or obstacle.is_in_group("spikes")):
		if str(obstacle.get("skin")).is_empty():
			obstacle.set("skin", "grave")
	if obstacle.has_method("set_motion_speed_multiplier"):
		obstacle.call("set_motion_speed_multiplier", motion_speed_multiplier)
	if obstacle.has_method("set_spiked"):
		obstacle.call("set_spiked", spiked_barrel)
	if obstacle.has_method("set_rubber_variant"):
		obstacle.call("set_rubber_variant", rubber_barrel, rubber_target_x)
	add_child(obstacle)
	obstacles.append(obstacle)

func _on_obstacle_destroyed(obstacle: Node2D) -> void:
	obstacles.erase(obstacle)

func _on_barrel_destruction_started(obstacle: Node2D) -> void:
	var audible := is_instance_valid(obstacle) and _is_singleplayer_event_audible(obstacle.global_position.x)
	_play_singleplayer_sfx("barrel_destroy", "%s|barrel_destroy|%d" % [_singleplayer_audio_round_id, obstacle.get_instance_id()], audible)

func _connect_barrel_audio(obstacle: Node) -> void:
	if is_instance_valid(obstacle) and obstacle.has_signal("destruction_started"):
		var callback := Callable(self, "_on_barrel_destruction_started")
		if not obstacle.is_connected("destruction_started", callback):
			obstacle.connect("destruction_started", callback)

func _is_singleplayer_event_audible(world_x: float) -> bool:
	var camera_left := float(camera.get("left")) if is_instance_valid(camera) else course_distance
	var view_width := screen_width
	if is_instance_valid(camera):
		view_width = float(camera.get("view_size").x)
	return SfxAudibilityRules.is_world_x_audible(world_x, camera_left, view_width)

func _on_rock_impact_started(event_id: String) -> void:
	_play_singleplayer_sfx("rock_impact", "%s|rock_impact|%s" % [_singleplayer_audio_round_id, event_id])

func _spawn_coin_row() -> void:
	var coin_count := randi_range(1, 3)
	for i in range(coin_count):
		var coin := COIN_SCENE.instantiate() as Node2D
		var trace_id := ""
		if render_diagnostics_enabled:
			trace_id = "sp_coin_%d" % coin.get_instance_id()
			coin.set_meta("coin_trace_id", trace_id)
		coin.connect("collected", Callable(run_state, "add_coins"))
		if render_diagnostics_enabled:
			coin.connect("collected", Callable(self, "_on_singleplayer_coin_collected").bind(coin, trace_id, "singleplayer_row"))
			coin.set_meta("coin_trace_collect_connected", true)
		_connect_coin_audio(coin, "coin:%d" % coin.get_instance_id())
		var coin_x := course_distance + screen_width + 70.0 + float(i) * 48.0
		var placed := false
		for attempt in range(20):
			var coin_y := randf_range(_ceiling_surface_y(coin_x) + 28.0, _floor_surface_y(coin_x) - 28.0)
			coin.position = Vector2(coin_x, coin_y)
			if _coin_position_is_clear(coin):
				placed = true
				break
		if not placed:
			coin.queue_free()
			continue
		add_child(coin)
		coins.append(coin)
		if render_diagnostics_enabled:
			_record_coin_trace("spawned", trace_id, coin.global_position, {"source": "singleplayer_row"})

func _spawn_shared_coins() -> void:
	if _active_seed <= 0 or _manifest_builder == null or _shared_coin_planner == null:
		return
	var horizon := course_distance + screen_width + 1400.0
	var planner_refresh_distance := 100.0
	if _active_seed_version >= COURSE_GENERATOR_SCRIPT.GENERATOR_VERSION_20:
		# Batch planning to avoid resolving the entire course on each ~100px
		# movement while retaining more than a viewport of planned coins.
		planner_refresh_distance = 250.0
	if PLAYER_X + horizon >= _shared_coin_planned_until + planner_refresh_distance:
		var planner_hazard_lookahead := 0.0
		var source_generation_lookahead := 1200.0
		if _active_seed_version >= COURSE_GENERATOR_SCRIPT.GENERATOR_VERSION_20:
			# Coin risk rows can precede a Gen19 pursuit by up to 1250px, while
			# pursuit eligibility checks support through its post-event route end
			# (3156px beyond the event, including half-width, at max model speed).
			# Add the maximum 1250px row lead plus a conservative 94px margin.
			planner_hazard_lookahead = 4500.0
			source_generation_lookahead = planner_hazard_lookahead + 200.0
		course_generator.ensure_horizon(PLAYER_X + horizon + source_generation_lookahead, _run_speed(), screen_height, COURSE_GENERATOR_SCRIPT.EVENT_SPAWN_LEAD_DISTANCE)
		var source_events: Array[Dictionary] = course_generator.get_planned_events()
		var biome_start_offset := BIOME_RENDERER_SCRIPT.start_biome_offset_for_seed(_active_seed, _active_seed_version)
		var resolved_course_length := ceili(horizon + planner_hazard_lookahead)
		var resolved_events: Array[Dictionary] = _manifest_builder.call("resolve_runtime_events", source_events, resolved_course_length, _active_seed_version, biome_start_offset)
		var planned: Array[Dictionary] = _shared_coin_planner.extend(PLAYER_X + horizon, resolved_events, WORLD_HEIGHT - 80.0, 80.0, 0)
		_pending_shared_coins.append_array(planned)
		_shared_coin_planned_until = PLAYER_X + horizon
	var spawn_limit := PLAYER_X + course_distance + COURSE_GENERATOR_SCRIPT.get_viewport_spawn_lead_distance(screen_width, PLAYER_X, SLOPE_WIDTH)
	for index in range(_pending_shared_coins.size() - 1, -1, -1):
		var item: Dictionary = _pending_shared_coins[index]
		var entity_id := str(item.get("entity_id", ""))
		if entity_id.is_empty() or _spawned_shared_coin_ids.has(entity_id) or float(item.get("world_x", INF)) > spawn_limit:
			continue
		_pending_shared_coins.remove_at(index)
		_spawned_shared_coin_ids[entity_id] = true
		if is_instance_valid(_campaign_run) and not bool(_campaign_run.call("allows_coin", float(item.world_x), float(item.world_y))):
			continue
		var coin := COIN_SCENE.instantiate() as Node2D
		coin.set_meta("coin_trace_id", entity_id)
		coin.connect("collected", Callable(run_state, "add_coins"))
		coin.connect("collected", Callable(self, "_on_shared_coin_collected").bind(coin, entity_id))
		_connect_coin_audio(coin, "coin:%s" % entity_id)
		coin.position = Vector2(float(item.world_x), float(item.world_y))
		add_child(coin)
		coins.append(coin)
		if render_diagnostics_enabled:
			_record_coin_trace("spawned", entity_id, coin.global_position, {"source": "shared_planner", "planned_world_x": float(item.world_x), "planned_world_y": float(item.world_y), "planner_refresh_distance": planner_refresh_distance})

func _on_shared_coin_collected(_value: int, coin: Node2D, entity_id: String) -> void:
	_spawned_shared_coin_ids.erase(entity_id)
	if render_diagnostics_enabled and is_instance_valid(coin):
		_record_coin_trace("collected", entity_id, coin.global_position, {"run_coins_after": int(run_state.get("coins")), "source": "shared_planner"}, "collected:%s" % entity_id)

func _on_singleplayer_coin_collected(_value: int, coin: Node2D, entity_id: String, source: String) -> void:
	if render_diagnostics_enabled and is_instance_valid(coin):
		_record_coin_trace("collected", entity_id, coin.global_position, {"run_coins_after": int(run_state.get("coins")), "source": source}, "collected:%s" % entity_id)

func _connect_coin_audio(coin: Node, event_id: String) -> void:
	var event_key := "%s|%s" % [_singleplayer_audio_round_id, event_id]
	coin.connect("visual_collection_started", Callable(self, "_on_singleplayer_coin_visual_started").bind(coin, event_key))
	coin.connect("visual_collection_cancelled", Callable(SfxController, "clear_event_key").bind(event_key))

func _on_singleplayer_coin_visual_started(coin: Node2D, event_key: String) -> void:
	if not is_instance_valid(coin):
		return
	var camera_left := float(player.get("world_x")) - PLAYER_X if is_instance_valid(player) else course_distance
	var audible := coin.global_position.x >= camera_left - 64.0 and coin.global_position.x <= camera_left + screen_width + 64.0
	_play_singleplayer_sfx("coin", event_key, audible)

func _play_singleplayer_sfx(event_name: String, event_key: String, audible: bool = true) -> bool:
	# Menu preview/demo runs deliberately have no gameplay audio identity.
	if demo_mode or _singleplayer_audio_round_id.is_empty():
		return false
	return SfxController.play_event(event_name, event_key, audible)

func _on_singleplayer_gravity_flipped() -> void:
	_play_singleplayer_sfx("gravity_flip", "%s|gravity_flip|%d" % [_singleplayer_audio_round_id, _singleplayer_simulation_tick])

func _on_singleplayer_ghost_phase_changed(event_id: String, phase: String, event: Dictionary) -> void:
	if phase != GHOST_HAZARD_MODEL.WARNING:
		return
	_ghost_warning_pulse.call("observe_warning", event_id, bool(event.get("from_ceiling", false)))
	queue_redraw()
	var event_x := float(event.get("x", 0.0))
	var camera_left := float(player.get("world_x")) - PLAYER_X if is_instance_valid(player) else course_distance
	var audible := event_x >= camera_left - 64.0 and event_x <= camera_left + screen_width + 64.0
	# Haunted campaign stages whistle when a ghost appears; endless keeps its sound.
	var warning_sound := "ghost_whistle" if _campaign_level != null and _campaign_level.world_id == &"haunted" and SfxController.STREAMS.has("ghost_whistle") else "ghost_warning"
	_play_singleplayer_sfx(warning_sound, "%s|ghost_warning|%s" % [_singleplayer_audio_round_id, event_id], audible)

func _spawn_loot_pickup(event: Dictionary) -> void:
	if not RUN_LOOT_ENABLED or demo_mode or not AuthService.is_authenticated:
		return
	var pickup := LOOT_PICKUP_SCENE.instantiate() as Node2D
	var pickup_distance := float(event.get("course_distance", 0.0))
	var pickup_x := PLAYER_X + pickup_distance
	pickup.call("configure", int(event.get("pickup_index", 0)))
	var placed := false
	for attempt in range(24):
		var ceiling_y := _ceiling_surface_y(pickup_x) + 52.0
		var floor_y := _floor_surface_y(pickup_x) - 52.0
		if floor_y <= ceiling_y:
			break
		pickup.position = Vector2(pickup_x, loot_spawn_planner.random_between(ceiling_y, floor_y))
		if _loot_position_is_clear(pickup):
			placed = true
			break
	if not placed:
		pickup.queue_free()
		return
	pickup.connect("collected", Callable(run_state, "record_loot_pickup"))
	add_child(pickup)
	loot_pickups.append(pickup)

func _loot_position_is_clear(pickup: Node2D) -> bool:
	var rect: Rect2 = pickup.call("get_hitbox_rect")
	for obstacle in obstacles:
		if is_instance_valid(obstacle) and obstacle.call("get_hitbox_rect").grow(26.0).intersects(rect):
			return false
	for coin in coins:
		if is_instance_valid(coin) and coin.call("get_hitbox_rect").grow(12.0).intersects(rect):
			return false
	return true

func _coin_position_is_clear(coin: Node2D) -> bool:
	var coin_rect: Rect2 = coin.call("get_hitbox_rect")
	for obstacle in obstacles:
		if is_instance_valid(obstacle) and obstacle.call("get_hitbox_rect").grow(4.0).intersects(coin_rect):
			return false
	return true

func _update_moving_slopes(_movement: float) -> void:
	var active_slopes: Array[Node2D] = []
	var camera_left := course_distance
	for slope in slopes:
		if not is_instance_valid(slope):
			continue
		var end_x: float = slope.call("get_end_x")
		# Keep terrain a little past the left edge: surface tiles are chosen
		# from whole 64 px cells, and the cell at the edge still looks at it.
		if end_x <= camera_left - SURFACE_TILE_KEEP_BEHIND:
			if bool(slope.call("is_ceiling_slope")):
				ceiling_level_y = float(slope.call("get_end_y"))
			else:
				floor_level_y = float(slope.call("get_end_y"))
			slope.queue_free()
		else:
			# Freed only through the branch above, which also carries its end
			# level forward; dropping it elsewhere would lose that level.
			active_slopes.append(slope)
	slopes = active_slopes

func _player_hits_obstacle(obstacle: Node2D) -> bool:
	var player_rect: Rect2 = player.call("get_player_rect")
	if obstacle.has_method("intersects_rect"):
		return bool(obstacle.call("intersects_rect", player_rect))
	var obstacle_rect: Rect2 = obstacle.call("get_hitbox_rect")
	return player_rect.intersects(obstacle_rect)

func _exit_tree() -> void:
	Engine.max_physics_steps_per_frame = _engine_max_physics_steps

## True when the stage's biome key guards against a hazard touching the runner
## (a falling rock for the ice picks, lava for the heat shield).
func _key_guards_contact(player_rect: Rect2) -> bool:
	if not bool(_run_effects.call("key_guard_ready")):
		return false
	var key_id := str(_run_effects.call("get_key_id"))
	var reach := player_rect.grow(28.0)
	for obstacle in obstacles:
		if not is_instance_valid(obstacle) or not BiomeKeys.guards_against(key_id, obstacle):
			continue
		if obstacle.has_method("get_hitbox_rect"):
			var rect: Rect2 = obstacle.call("get_hitbox_rect")
			if rect.size != Vector2.ZERO and reach.intersects(rect):
				return true
		elif absf(obstacle.global_position.x - player_rect.get_center().x) < 140.0:
			return true
	return false

func _earliest_lethal_contact_fraction(start_rect: Rect2, finish_rect: Rect2) -> float:
	var displacement := finish_rect.position - start_rect.position
	var earliest := 1.0 if player.position.y < -64.0 or player.position.y > WORLD_HEIGHT + 64.0 else INF
	var immune := bool(player.call("is_spike_immune"))
	for obstacle in obstacles:
		if not is_instance_valid(obstacle) or bool(obstacle.call("is_destroying_now")):
			continue
		var kind := "edge" if obstacle.is_in_group("blocking_edges") else "rect"
		var fraction := -1.0
		if obstacle.is_in_group("falling_rocks") or obstacle.is_in_group("saw_blades"):
			fraction = float(obstacle.call("swept_contact_fraction", start_rect, finish_rect, maxi(_singleplayer_simulation_tick - 1, 0), _singleplayer_simulation_tick, Vector2(34.0, 44.0)))
		elif obstacle.is_in_group("ghost_hazards") and obstacle.has_method("swept_contact_fraction") and int((obstacle.get("event") as Dictionary).get("ghost_variant", 0)) in [1, 2, 3]:
			fraction = float(obstacle.call("swept_contact_fraction", start_rect, finish_rect, maxi(_singleplayer_simulation_tick - 1, 0), _singleplayer_simulation_tick, start_rect.size))
		elif obstacle.is_in_group("lava_hazards") and obstacle.has_method("swept_contact_fraction"):
			fraction = float(obstacle.call("swept_contact_fraction", start_rect, finish_rect, maxi(_singleplayer_simulation_tick - 1, 0), _singleplayer_simulation_tick, start_rect.size))
		elif obstacle.is_in_group("spikes") and obstacle.has_method("get_world_triangles"):
			if immune:
				continue
			for triangle in obstacle.call("get_world_triangles"):
				var candidate := HAZARD_RULES_SCRIPT.swept_rect_polygon_fraction(start_rect, displacement, triangle)
				if candidate >= 0.0 and (fraction < 0.0 or candidate < fraction):
					fraction = candidate
		elif obstacle.is_in_group("bat_swarms") or obstacle.is_in_group("ghost_hands"):
			fraction = float(obstacle.call("swept_contact_fraction", start_rect, finish_rect))
		elif obstacle.is_in_group("barrels"):
			var barrel_size: Vector2 = obstacle.get("size")
			var center := HAZARD_RULES_SCRIPT.barrel_center(obstacle.global_position, barrel_size.x, barrel_size.y, bool(obstacle.get("from_ceiling")))
			var start_center: Vector2 = _step_start_barrel_centers.get(obstacle.get_instance_id(), center)
			var relative_displacement := displacement - (center - start_center)
			fraction = HAZARD_RULES_SCRIPT.swept_rect_circle_fraction(start_rect, relative_displacement, start_center, HAZARD_RULES_SCRIPT.barrel_radius(barrel_size.x, barrel_size.y))
		else:
			var target: Rect2 = obstacle.call("get_hitbox_rect")
			if kind != "edge":
				var polygon := PackedVector2Array([target.position, Vector2(target.end.x, target.position.y), target.end, Vector2(target.position.x, target.end.y)])
				fraction = HAZARD_RULES_SCRIPT.swept_rect_polygon_fraction(start_rect, displacement, polygon)
		if fraction >= 0.0:
			earliest = minf(earliest, fraction)
	for terrain in slopes:
		if not is_instance_valid(terrain) or not terrain.has_method("is_terrain_step") or not bool(terrain.call("is_terrain_step")) or immune:
			continue
		if terrain.has_method("get_world_spike_triangles"):
			for triangle in terrain.call("get_world_spike_triangles"):
				var candidate := HAZARD_RULES_SCRIPT.swept_rect_polygon_fraction(start_rect, displacement, triangle)
				if candidate >= 0.0:
					earliest = minf(earliest, candidate)
	return earliest

func _saw_endpoint_impact(player_rect: Rect2, obstacle: Node2D) -> int:
	if not is_instance_valid(obstacle) or not obstacle.is_in_group("saw_blades"):
		return HAZARD_RULES_SCRIPT.PlayerImpact.NONE
	var saw_state: Dictionary = obstacle.get("state")
	if not bool(saw_state.get("active", false)) or bool(saw_state.get("removed", false)):
		return HAZARD_RULES_SCRIPT.PlayerImpact.NONE
	var center := Vector2(float(saw_state.get("x", 0.0)), float(saw_state.get("y", 0.0)))
	return HAZARD_RULES_SCRIPT.PlayerImpact.LETHAL if HAZARD_RULES_SCRIPT.circle_intersects_rect(center, SAW_BLADE_MODEL.radius_for_state(saw_state), player_rect) else HAZARD_RULES_SCRIPT.PlayerImpact.NONE

func _draw() -> void:
	var draw_started_usec := Time.get_ticks_usec() if render_diagnostics_enabled else -1
	_draw_background()
	var background_draw_done_usec := Time.get_ticks_usec() if render_diagnostics_enabled else -1
	var track_draw_started_usec := background_draw_done_usec
	_draw_track()
	var track_draw_done_usec := Time.get_ticks_usec() if render_diagnostics_enabled else -1
	_draw_seed_finish_markers()
	_draw_falling_rock_warning_markers()
	_draw_rock_hud_warning()
	_draw_ghost_hud_warning()
	_draw_bubble_shield()
	_draw_regret_ring()
	_draw_gravity_anchor()
	if render_diagnostics_enabled and not _render_diagnostic_frames.is_empty():
		var frame_record: Dictionary = _render_diagnostic_frames.back()
		if int(frame_record.get("render_callback_index", -1)) == _render_callback_index:
			frame_record["background_draw_usec"] = background_draw_done_usec - draw_started_usec
			frame_record["track_draw_usec"] = track_draw_done_usec - track_draw_started_usec
			frame_record["canvas_submission_usec"] = Time.get_ticks_usec() - draw_started_usec
			frame_record["canvas_submission_end_usec"] = Time.get_ticks_usec()
			_render_diagnostic_frames[_render_diagnostic_frames.size() - 1] = frame_record

## Bubble helmet: a faint bubble while the shield is ready, a pulsing ring while
## the runner is invulnerable after a hit, and an expanding pop ring.
func _draw_bubble_shield() -> void:
	if demo_mode or game_over:
		return
	var center := _render_player_position
	if bool(_run_effects.call("bubble_ready")):
		draw_circle(center, 31.0, Color(0.26, 0.84, 0.77, 0.14))
		draw_arc(center, 31.0, 0.0, TAU, 32, Color(0.26, 0.84, 0.77, 0.7), 2.0, true)
		draw_arc(center, 24.0, PI * 1.1, PI * 1.5, 8, Color(0.93, 0.95, 1.0, 0.8), 2.0, true)
	elif bool(_run_effects.call("is_invulnerable")):
		var pulse := 0.5 + 0.5 * sin(float(_singleplayer_simulation_tick) * 0.9)
		draw_arc(center, 31.0, 0.0, TAU, 32, Color(0.93, 0.95, 1.0, 0.25 + 0.4 * pulse), 2.0, true)
	var pop := float(_run_effects.call("pop_progress"))
	if pop >= 0.0:
		draw_arc(center, 31.0 + 40.0 * pop, 0.0, TAU, 40, Color(0.93, 0.95, 1.0, 1.0 - pop), 3.0, true)
		for index in range(8):
			var direction := Vector2.from_angle(TAU * float(index) / 8.0)
			draw_circle(center + direction * (31.0 + 52.0 * pop), 3.0 * (1.0 - pop), Color(0.26, 0.84, 0.77, 1.0 - pop))

## Regret boots: a short ring where the runner turned around.
func _draw_regret_ring() -> void:
	if demo_mode or game_over:
		return
	var progress := float(_run_effects.call("regret_flash_progress"))
	if progress < 0.0:
		return
	var center := _render_player_position
	draw_arc(center, 14.0 + 30.0 * progress, 0.0, TAU, 28, Color(0.96, 0.83, 0.37, 1.0 - progress), 3.0, true)
	var back := -float(player.call("get_gravity_direction"))
	for index in range(3):
		var offset := Vector2((float(index) - 1.0) * 9.0, back * (10.0 + 18.0 * progress + float(index) * 4.0))
		draw_rect(Rect2(center + offset - Vector2(2.0, 2.0), Vector2(4.0, 4.0)), Color(0.93, 0.95, 1.0, 1.0 - progress))

## Gravity anchor: a dashed guide along the middle of the course and speed
## streaks behind the runner while it glides.
func _draw_gravity_anchor() -> void:
	if demo_mode or game_over or not bool(_run_effects.call("is_anchor_gliding")):
		return
	var center := _render_player_position
	var view_left := camera.get_screen_center_position().x - screen_width * 0.5 if is_instance_valid(camera) else center.x - PLAYER_X
	var scroll := fmod(float(_singleplayer_simulation_tick) * 14.0, 40.0)
	var x := view_left - scroll
	while x < view_left + screen_width:
		draw_line(Vector2(x, center.y), Vector2(x + 20.0, center.y), Color(0.26, 0.84, 0.77, 0.35), 2.0)
		x += 40.0
	for index in range(4):
		var streak_y := center.y + (float(index) - 1.5) * 9.0
		var streak_length := 38.0 + float((index * 7 + _singleplayer_simulation_tick) % 5) * 9.0
		draw_line(Vector2(center.x - 24.0, streak_y), Vector2(center.x - 24.0 - streak_length, streak_y), Color(0.93, 0.95, 1.0, 0.45), 2.0)
	draw_arc(center, 28.0, 0.0, TAU, 28, Color(0.26, 0.84, 0.77, 0.75), 2.0, true)

func _draw_falling_rock_warning_markers() -> void:
	if not is_instance_valid(camera):
		return
	var view_left := camera.get_screen_center_position().x - screen_width * 0.5
	var view_right := view_left + screen_width
	for obstacle in obstacles:
		if not is_instance_valid(obstacle) or not obstacle.is_in_group("falling_rocks") or not FALLING_ROCK_MODEL.offscreen_marker_active(str(obstacle.call("get_phase"))) or obstacle.global_position.x <= view_right:
			continue
		var marker_x := view_right - 44.0
		var event: Dictionary = obstacle.get("event")
		var floor_y := float(event.get("floor_y", WORLD_HEIGHT - 80.0))
		ROCK_WARNING_ICON_SCRIPT.draw(self, Vector2(marker_x, floor_y - 64.0), 38.0)
		ROCK_WARNING_ICON_SCRIPT.draw_forward_chevron(self, Vector2(marker_x + 25.0, floor_y - 64.0), 8.0)

func _update_singleplayer_rock_warning_pulse(delta: float) -> void:
	_rock_warning_pulse.call("advance", delta)
	var warnings: Array[Dictionary] = []
	for obstacle in obstacles:
		if not is_instance_valid(obstacle) or not obstacle.is_in_group("falling_rocks"):
			continue
		var phase := str(obstacle.call("get_phase"))
		if phase != "warning":
			continue
		var event: Dictionary = obstacle.get("event")
		warnings.append({"event_id": str(event.get("event_id", "")), "phase": phase})
	_rock_warning_pulse.call("observe_warning_events", warnings)
	_rock_warning_accessibility_button.visible = not game_over and bool(_rock_warning_pulse.call("is_active"))
	if _rock_warning_accessibility_button.visible:
		_rock_warning_accessibility_button.position = ROCK_WARNING_PULSE_SCRIPT.screen_center(get_viewport_rect().size) - Vector2(24.0, 24.0)

func _draw_rock_hud_warning() -> void:
	if not bool(_rock_warning_pulse.call("is_active")):
		return
	var view_left := camera.get_screen_center_position().x - screen_width * 0.5 if is_instance_valid(camera) else _render_course_distance
	var viewport_size := Vector2(screen_width, screen_height)
	var center := ROCK_WARNING_PULSE_SCRIPT.world_center(view_left, viewport_size)
	ROCK_WARNING_ICON_SCRIPT.draw(self, center, 56.0 * float(_rock_warning_pulse.call("scale")), Color("ff814f"), float(_rock_warning_pulse.call("alpha")))

func _draw_ghost_hud_warning() -> void:
	if not bool(_ghost_warning_pulse.call("is_active")):
		return
	var view_left := camera.get_screen_center_position().x - screen_width * 0.5 if is_instance_valid(camera) else _render_course_distance
	_ghost_warning_pulse.call("draw", self, Vector2(view_left + screen_width * 0.5, screen_height * 0.5))

func _on_seed_leaderboard_received(version: int, seed: int, rows: Array, _error_message: String) -> void:
	if version != _active_seed_version or seed != _active_seed:
		return
	_seed_scores.clear()
	for row in rows:
		if row is Dictionary:
			_seed_scores.append(row)

func _mark_crossed_seed_records(previous_distance: float, current_distance: float) -> void:
	if _seed_scores.is_empty() or current_distance <= previous_distance:
		return
	for index in range(mini(_seed_scores.size(), 5)):
		var score: Dictionary = _seed_scores[index]
		var record_distance := int(score.get("best_distance_m", 0)) * 10
		if record_distance <= previous_distance or record_distance > current_distance:
			continue
		var nickname := str(score.get("player_name", ""))
		hud.call("show_pass_flash", nickname)
	queue_redraw()

func _draw_seed_finish_markers() -> void:
	if _seed_scores.is_empty():
		return
	var current_distance := float(run_state.get("distance_m"))
	var rank_colors := [Color("f5d45e"), Color("42d6c5"), Color("ff647c"), Color("b69cff"), Color("8ee0a1")]
	for index in range(mini(_seed_scores.size(), 5)):
		var score: Dictionary = _seed_scores[index]
		var record_distance_m := int(score.get("best_distance_m", 0))
		var marker_x := PLAYER_X + float(record_distance_m * 10)
		var marker_screen_x := marker_x - course_distance
		if marker_screen_x < 0.0 or marker_screen_x > screen_width:
			continue
		var marker_color: Color = rank_colors[mini(index, rank_colors.size() - 1)]
		var y := 0.0
		while y < screen_height:
			draw_line(Vector2(marker_x, y), Vector2(marker_x, minf(y + 10.0, screen_height)), marker_color, 2.0, true)
			y += 19.0
		var nickname := str(score.get("player_name", ""))
		var label := "%s · %dm" % [nickname.left(8), record_distance_m]
		var label_center_y := 148.0 + float(index % 3) * 64.0
		draw_set_transform(Vector2(marker_x + 5.0, label_center_y), PI / 2.0)
		draw_string(PixelUi.font(), Vector2.ZERO, label, HORIZONTAL_ALIGNMENT_LEFT, 180.0, 9, marker_color)
		draw_set_transform(Vector2.ZERO)

func _draw_background() -> void:
	var view_left := _render_course_distance
	# The same distance-addressed backdrop renderer is used by MP presentation.
	# SP world coordinates begin at PLAYER_X, matching manifest.start_x in MP.
	# Normalize backdrop phase by that same origin so absolute world points match.
	var biome_start_offset := BIOME_RENDERER_SCRIPT.start_biome_offset_for_seed(_active_seed, _active_seed_version)
	BIOME_RENDERER_SCRIPT.draw_backdrop(self, view_left, Vector2(screen_width, screen_height), BIOME_RENDERER_SCRIPT.course_distance_at_world_x(view_left + PLAYER_X, PLAYER_X) + biome_start_offset, _active_seed_version, float(_singleplayer_simulation_tick) / 60.0)

func _draw_track() -> void:
	var surface_gaps: Array[Dictionary] = []
	for gap in gaps:
		if is_instance_valid(gap):
			var half_width := float(gap.get("width")) * 0.5
			surface_gaps.append({"start": gap.position.x - half_width, "end": gap.position.x + half_width, "ceiling": bool(gap.get("from_ceiling"))})
	var terrain_boundaries: Array[float] = []
	var step_positions: Array[float] = []
	for terrain in slopes:
		terrain_boundaries.append(float(terrain.call("get_start_x")))
		terrain_boundaries.append(float(terrain.call("get_end_x")))
		if terrain.has_method("is_terrain_step") and bool(terrain.call("is_terrain_step")):
			step_positions.append(float(terrain.call("get_start_x")))
	var biome_start_offset := BIOME_RENDERER_SCRIPT.start_biome_offset_for_seed(_active_seed, _active_seed_version)
	COURSE_SURFACE_RENDERER.draw_track(self, _render_course_distance, Vector2(screen_width, screen_height), surface_gaps, terrain_boundaries, step_positions, Callable(self, "_surface_y_at"), 0.0, null, BIOME_RENDERER_SCRIPT.course_distance_at_world_x(PLAYER_X, 0.0) - biome_start_offset, _active_seed_version)

## Course identity for the personal-best ghost: a campaign stage, or a seed that
## can come again (challenge, typed seed, daily stage). "" for random seeds and
## the menu's demo run, which keep no ghost.
func _ghost_identity(run_definition: Resource) -> String:
	if demo_mode:
		return ""
	if _campaign_level != null:
		return "campaign|" + _campaign_level.get_identity()
	if not ChallengeService.repeatable_seed:
		return ""
	return "seed|" + str(run_definition.call("get_course_identity"))

## The runner's facing for the ghost: +1 upright on the floor, -1 on the ceiling.
func _runner_facing() -> float:
	var sprite_node: Node2D = player.get("sprite")
	var pixel_scale := float(player.get("_pixel_scale"))
	return sprite_node.scale.y / pixel_scale if is_instance_valid(sprite_node) and pixel_scale > 0.0 else float(player.call("get_gravity_direction"))

## Near miss: the runner flipped a moment ago and slips past a hazard with a
## hair's breadth to spare. Each hazard counts once, and callouts are spaced out.
func _check_near_miss(player_rect: Rect2) -> void:
	var direction := int(player.call("get_gravity_direction"))
	if direction != _last_gravity_direction:
		_last_gravity_direction = direction
		_last_flip_tick = _singleplayer_simulation_tick
	if _singleplayer_simulation_tick - _last_flip_tick > NEAR_MISS_FLIP_TICKS:
		return
	if _singleplayer_simulation_tick - _near_miss_last_tick < NEAR_MISS_COOLDOWN_TICKS:
		return
	var reach := player_rect.grow(NEAR_MISS_GAP)
	for obstacle in obstacles:
		if not is_instance_valid(obstacle) or not obstacle.has_method("get_hitbox_rect"):
			continue
		if absf(obstacle.global_position.x - player_rect.get_center().x) > 220.0:
			continue
		var id := obstacle.get_instance_id()
		if _near_miss_seen.has(id):
			continue
		var rect: Rect2 = obstacle.call("get_hitbox_rect")
		if rect.size == Vector2.ZERO or rect.intersects(player_rect) or not rect.intersects(reach):
			continue
		_near_miss_seen[id] = true
		_near_miss_last_tick = _singleplayer_simulation_tick
		near_miss_count += 1
		hud.call("show_campaign_callout", tr(NEAR_MISS_LINES[near_miss_count % NEAR_MISS_LINES.size()]), Color("8fe6ff"))
		return
