extends SceneTree

const Builder := preload("res://systems/course_manifest_builder.gd")
const World := preload("res://systems/multiplayer_v2/v2_world_simulation.gd")
const Service := preload("res://systems/multiplayer_v2/multiplayer_v2_service.gd")

var failures := 0
var maximum_bytes := 0
var maximum_seed := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var builder: RefCounted = Builder.new()
	for seed in range(1, 201):
		var result: Dictionary = builder.build(seed, 45000, 5)
		var manifest: Variant = result.get("manifest", null)
		_check(manifest is Resource, "default v5 manifest builds for seed %d" % seed)
		if not manifest is Resource:
			continue
		var world: RefCounted = World.new()
		world.configure(manifest)
		var probe: Node = Service.new()
		probe.room_state = {"room_id": "local-room", "room_session_id": "local-session", "lobby_generation": 1}
		probe._round_id = "review-round"
		probe.world_simulation = world
		var bytes: int = probe.world_baseline_payload_size_bytes()
		if bytes > maximum_bytes:
			maximum_bytes = bytes
			maximum_seed = seed
		_check(bytes <= Service.WORLD_BASELINE_APPLICATION_BUDGET_BYTES, "default 45,000px control baseline fits selected 48KiB application budget (seed %d: %d bytes)" % [seed, bytes])
		probe.free()
	print("WORLD_BASELINE budget: 200 default seeds, max=%d bytes at seed=%d, application cap=%d bytes." % [maximum_bytes, maximum_seed, Service.WORLD_BASELINE_APPLICATION_BUDGET_BYTES])
	quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
