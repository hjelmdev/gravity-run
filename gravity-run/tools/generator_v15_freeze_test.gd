extends SceneTree

const Builder := preload("res://systems/course_manifest_builder.gd")
const SEEDS: Array[int] = [100000014, 100000042, 100000777, 100000918]
const FIXTURES := {
	100000014: ["388bd994bfb2245e16c5dbe0888d783a749c26f40cfdf119fda08bf1d3d39e76", 50, "d8777a44f04a15e086e597064f0d059ec21a95001f02fd92c70f1ed93eaeddd9", 130, "54e311a4a6f07a086ad798b083f7facbb46268eb3455dec34a10218f80b7a9c9"],
	100000042: ["f7c54b0ec4da8be4e3147503ecd710d8451461c6cc5a6e1cef3e03ef9b64bd22", 63, "25e5ac30e534ecc9c59582abd5afbb87d0b3f4648de71e4bf950beedede251d9", 206, "c5d539149500677303cf404abb4610fd15651fad0da0d92f7b6c40a853123471"],
	100000777: ["8081e91c7237180c443bfa655ed46e4f3f766646d10862003ec1081d4845c0d0", 44, "d0a38f1d8e51c028c1ec3a1d7ebf337cc1a63f03f592efc9bb4ef3fc4b007bd9", 174, "0a4ac54a9302f90e003cefed4afd42dd1fee92eb0ad06b181ebd932824a71d72"],
	100000918: ["25abd835ad33ce0d1c631947172dc581561a83655b89844d9b50e94754666e17", 53, "b1f97b754d04fdbe00c80e8d690c6c504e5cb2a99d74286bb4291473687b62d6", 214, "00fd726be154ba56cee9a573424217c7b9f0fae2797718ac2a0d640f1208e3d6"]
}

func _initialize() -> void:
	var builder := Builder.new()
	var failures: Array[String] = []
	for seed_value in SEEDS:
		var result: Dictionary = builder.build(seed_value, 45000, 15)
		var manifest: Variant = result.get("manifest")
		if manifest == null:
			failures.append("Gen15 seed %d failed to build: %s" % [seed_value, str(result.get("error", ""))])
			continue
		var coins: Array = []
		for coin in manifest.collectibles:
			coins.append([str(coin.get("entity_id", "")), float(coin.get("world_x", 0.0)), float(coin.get("world_y", 0.0)), int(coin.get("value", 0)), float(coin.get("radius", 0.0))])
		var actual := [str(manifest.manifest_hash), manifest.events.size(), _hash(manifest.events), coins.size(), _hash(coins)]
		if actual != FIXTURES[seed_value]:
			failures.append("Gen15 seed %d frozen output changed: %s" % [seed_value, str(actual)])
		print("GEN15_FREEZE seed=%d manifest=%s events=%d coins=%d" % [seed_value, str(manifest.manifest_hash), manifest.events.size(), coins.size()])
	print("GENERATOR_V15_FREEZE_TEST failures=%d" % failures.size())
	for failure in failures:
		push_error(failure)
	quit(1 if not failures.is_empty() else 0)

func _hash(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(value).to_utf8_buffer())
	return context.finish().hex_encode()
