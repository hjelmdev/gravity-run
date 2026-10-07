extends SceneTree
## Bounded shared-world barrel reach comparison. Each world runs on its canonical
## 500px/s clock while three counterfactual floor RunnerMotion paths are sampled.

const Builder := preload("res://systems/course_manifest_builder.gd")
const World := preload("res://systems/multiplayer_v2/v2_world_simulation.gd")
const SurfaceIndex := preload("res://systems/course_surface_index.gd")
const HazardRules := preload("res://systems/hazard_interaction_rules.gd")
const VERSIONS := [19, 20]
const SPEEDS := [475.0, 500.0, 525.0]
const SEEDS: Array[int] = [100000001, 100000002, 100000003, 100000004, 100000005, 100000006, 100000014, 100000019]
const LENGTH := 45000

var failures := 0

func _initialize() -> void:
	for version in VERSIONS:
		var rows := {}
		for speed in SPEEDS:
			rows[int(speed)] = {"normal": 0, "normal_met": 0, "normal_destroyed": 0, "spiked": 0, "spiked_met": 0, "spiked_destroyed": 0}
		var destroy_causes := {}
		for seed_value in SEEDS:
			var built: Dictionary = Builder.new().build(seed_value, LENGTH, version)
			var manifest: Variant = built.get("manifest")
			if manifest == null:
				failures += 1
				push_error("barrel comparison manifest failed version=%d seed=%d: %s" % [version, seed_value, str(built.get("error", ""))])
				continue
			var world := World.new()
			if not str(world.configure(manifest)).is_empty():
				failures += 1
				push_error("barrel comparison world failed version=%d seed=%d" % [version, seed_value])
				continue
			var surface := SurfaceIndex.new()
			surface.configure(manifest.events, float(manifest.initial_floor_y), float(manifest.initial_ceiling_y))
			var outcomes: Array[Dictionary] = []
			for barrel in world.barrels:
				outcomes.append({"id": str(barrel.entity_id), "event_id": str(barrel.event_id), "spiked": bool(barrel.spiked), "met": {475: false, 500: false, 525: false}, "destroy_tick": -1, "destroy_reason": ""})
			for tick in range(1, ceili(float(LENGTH) / 250.0 * 60.0) + 1):
				world.step_to(tick)
				var runner_rects := {}
				for speed in SPEEDS:
					var runner_x: float = float(manifest.start_x) + speed * float(tick) / 60.0
					var floor_info: Dictionary = surface.surface_at(runner_x, false)
					runner_rects[int(speed)] = Rect2(Vector2(runner_x - 17.0, float(floor_info.y) - 44.0), Vector2(34.0, 44.0))
				for index in range(world.barrels.size()):
					var barrel: Dictionary = world.barrels[index]
					var outcome: Dictionary = outcomes[index]
					if bool(barrel.get("destroyed", false)):
						if int(outcome.destroy_tick) < 0:
							outcome.destroy_tick = tick
							outcome.destroy_reason = _destruction_reason(manifest, barrel)
							destroy_causes[outcome.destroy_reason] = int(destroy_causes.get(outcome.destroy_reason, 0)) + 1
						continue
					if not bool(barrel.get("spawned", false)):
						continue
					var center := HazardRules.barrel_center(Vector2(float(barrel.x), float(barrel.y)), float(barrel.width), float(barrel.height))
					var radius := HazardRules.barrel_radius(float(barrel.width), float(barrel.height))
					for speed in SPEEDS:
						var key := int(speed)
						if not bool(outcome.met[key]) and HazardRules.circle_intersects_rect(center, radius, runner_rects[key]):
							outcome.met[key] = true
			for outcome in outcomes:
				if version == 20 and int(outcome.destroy_tick) >= 0 and not bool(outcome.met[500]):
					print("GEN19_BARREL_PREMEET_DETAIL seed=%d barrel=%s source=%s destroy_tick=%d cause=%s" % [seed_value, str(outcome.id), str(outcome.event_id), int(outcome.destroy_tick), str(outcome.destroy_reason)])
				var speed_rows: Dictionary = rows
				for speed in SPEEDS:
					var key := int(speed)
					var row: Dictionary = speed_rows[key]
					var type_prefix := "spiked" if bool(outcome.spiked) else "normal"
					row[type_prefix] += 1
					if bool(outcome.met[key]):
						row[type_prefix + "_met"] += 1
					elif int(outcome.destroy_tick) >= 0:
						row[type_prefix + "_destroyed"] += 1
		for speed in SPEEDS:
			var row: Dictionary = rows[int(speed)]
			print("GEN19_BARREL_REACH version=%d speed=%.0f seeds=%d normal=%d normal_floor_body_meet=%d normal_destroyed_before_meet=%d normal_other=%d spiked=%d spiked_floor_body_meet=%d spiked_destroyed_before_meet=%d destroy_causes=%s failures=%d" % [version, speed, SEEDS.size(), row.normal, row.normal_met, row.normal_destroyed, row.normal - row.normal_met - row.normal_destroyed, row.spiked, row.spiked_met, row.spiked_destroyed, JSON.stringify(destroy_causes), failures])
	print("GEN19_BARREL_REACH classification=matched_475_500_525px_per_second_shared_world; runner_paths_are_floor_only_counterfactuals; cause_is_nearest_contact_at_destroy_pose")
	quit(1 if failures > 0 else 0)

func _destruction_reason(manifest: Resource, barrel: Dictionary) -> String:
	var center := HazardRules.barrel_center(Vector2(float(barrel.x), float(barrel.y)), float(barrel.width), float(barrel.height))
	var radius := HazardRules.barrel_radius(float(barrel.width), float(barrel.height))
	for event in manifest.events:
		var kind := str(event.get("kind", ""))
		if kind == "block":
			var width := float(event.get("width", 48.0))
			var height := float(event.get("height", 72.0))
			var edge_y := float(event.get("y", 0.0))
			var block_y := edge_y - height if not bool(event.get("from_ceiling", false)) else edge_y
			var rect := Rect2(Vector2(float(event.x) - width * 0.5, block_y), Vector2(width, height))
			if HazardRules.circle_intersects_rect(center, radius, rect): return "block:%s" % str(event.event_id)
		elif kind == "spikes":
			var triangles := HazardRules.spike_group_triangles(float(event.get("start_x", event.get("x", 0.0))), float(event.get("y", 0.0)), int(event.get("count", 1)), float(event.get("spacing", 32.0)), 28.0, 32.0, bool(event.get("from_ceiling", false)))
			for triangle in triangles:
				if triangle is PackedVector2Array and HazardRules.circle_intersects_triangle(center, radius, triangle): return "spikes:%s" % str(event.event_id)
		elif kind == "step":
			var drop := not bool(event.get("from_ceiling", false)) and float(event.get("start_y", 0.0)) > float(event.get("end_y", 0.0))
			if not drop:
				var step_rect := HazardRules.step_wall_rect(float(event.get("x", 0.0)), float(event.get("start_y", 0.0)), float(event.get("end_y", 0.0)))
				if HazardRules.circle_intersects_rect(center, radius, step_rect): return "step:%s" % str(event.event_id)
	return "unclassified"
