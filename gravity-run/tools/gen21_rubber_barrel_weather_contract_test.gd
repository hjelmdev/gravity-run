extends SceneTree
## Narrow contract checks for the new Gen21 rubber interaction and weather seams.

const HazardRules := preload("res://systems/hazard_interaction_rules.gd")
const BiomeRenderer := preload("res://biomes/biome_renderer.gd")

var failures := 0

func _initialize() -> void:
	_run()

func _run() -> void:
	var block := Rect2(Vector2(300.0, 388.0), Vector2(64.0, 72.0))
	var rubber_state := {"x": 295.0, "width": 54.0, "height": 54.0, "motion_speed_multiplier": 1.5, "travel_direction": 1, "bounce_count": 0}
	var center := Vector2(330.0, 361.0)
	var radius := 27.0
	_check(HazardRules.barrel_impact(center, radius, "block", block, [], true) == HazardRules.BarrelImpact.RUBBER_BOUNCE, "rubber hits block without destruction result")
	_check(HazardRules.barrel_impact(center, radius, "block", block, [], false) == HazardRules.BarrelImpact.BARREL_AND_TARGET_DESTROYED, "ordinary barrel retains frozen block interaction")
	_check(HazardRules.bounce_rubber_barrel(rubber_state, block), "first rubber bounce is accepted")
	_check(int(rubber_state.get("travel_direction", 0)) == -1 and int(rubber_state.get("bounce_count", 0)) == 1, "bounce reverses direction exactly once")
	_check(not bool(rubber_state.get("retired", false)), "first bounce keeps the barrel active")
	var previous_x := float(rubber_state.x)
	HazardRules.advance_barrel(rubber_state, 1.0 / 60.0, 500.0 / 60.0, 460.0, 0.0, true)
	_check(float(rubber_state.x) > previous_x, "post-bounce motion follows the reversed course direction")
	_check(HazardRules.bounce_rubber_barrel(rubber_state, block), "second bounce remains bounded and accepted")
	_check(not HazardRules.bounce_rubber_barrel(rubber_state, block), "third contact retires instead of trapping the barrel")
	_check(bool(rubber_state.get("retired", false)), "bounce cap parks the barrel in a bounded spent state")
	_check(is_equal_approx(float(rubber_state.x), block.end.x + radius + 1.0), "spent barrel parks one pixel clear of the struck block face")
	_check(HazardRules.barrel_impact(Vector2(float(rubber_state.x), 361.0), radius, "block", block, [], true) == HazardRules.BarrelImpact.NONE, "parked position no longer overlaps the block")
	_check(HazardRules.player_impact(Rect2(Vector2(float(rubber_state.x) - 20.0, 340.0), Vector2(40.0, 42.0)), "barrel", Rect2(), [], Vector2(float(rubber_state.x), 361.0), radius) == HazardRules.PlayerImpact.LETHAL, "spent rubber remains a visible gameplay hazard rather than being destroyed")

	for biome_kind in ["classic", "cave", "haunted", "lava"]:
		var extent := BiomeRenderer.weather_primitive_extent(biome_kind)
		for width in [1.0, extent * 2.0, 48.0]:
			for center_x in [-1.0, 0.0, extent, width * 0.5, width - extent, width, width + 1.0]:
				var fits := BiomeRenderer.weather_primitive_fits_fragment(0.0, width, center_x, extent)
				if fits:
					_check(center_x - extent >= 0.0 and center_x + extent <= width, "%s weather primitive stays fully inside fragment width %.1f" % [biome_kind, width])
		_check(not BiomeRenderer.weather_primitive_fits_fragment(0.0, 1.0, 0.5, extent), "%s weather is omitted in a too-narrow biome fragment" % biome_kind)

	# Same course point rendered from two adjacent fragments has the exact same
	# absolute canvas X as the viewport's course origin is advanced with the split.
	var course_x := 1578.25
	var camera_course_left := 1440.0
	var whole_x := BiomeRenderer.weather_canvas_x(220.0, course_x, camera_course_left)
	var split_x := BiomeRenderer.weather_canvas_x(364.0, course_x, camera_course_left + 144.0)
	_check(is_equal_approx(whole_x, split_x), "weather phase is continuous when the viewport is split into biome fragments")
	var drifted_x := BiomeRenderer.weather_canvas_x(220.0, course_x + 7.0, camera_course_left)
	_check(is_equal_approx(drifted_x - whole_x, 7.0), "presentation-time drift moves the weather without changing course anchoring")

	print("GEN21_RUBBER_BARREL_WEATHER_CONTRACT failures=%d" % failures)
	quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
