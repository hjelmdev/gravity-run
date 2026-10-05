extends SceneTree

const Builder := preload("res://systems/course_manifest_builder.gd")
const BiomeRenderer := preload("res://biomes/biome_renderer.gd")
const FIXTURES := {
	100000003: ["22733d5caa9dda4e7131f80a9a157a262683a1d1bbf1c49e3bdb1d659711c88f", 137, 386, "5b4f7970f313c1c40ed61a061df2998d046874115c268e8124cf500bc198e661"],
	100000014: ["a001d1ff8d42e23f71b8c8b3a0c4deb778207316982a77d00d8e1d16179c1a89", 130, 299, "b3ffff8e59ae62c32e8816acd6c119e734f1b5ec3682b063d3bc09198d43d72c"],
	100000042: ["15f48d5fee393c06d5ad84557a0c66198f6294457468a0bf40a4ab8c96243ec6", 140, 348, "2d6832aa39fe6c79293cb31c80b82ba88531af50cc610ad02b541f3abf4cbf5e"],
	100000777: ["f2da77d55046ce65c7f74ca608a82dc30379ed009afd203ad2f4a408faebb39f", 139, 451, "449a02a53bc209c9a90ff77eba3b0b317c607ee48dbd87d7d2ec792e82d1420c"],
	100000918: ["2e86a8df503a17677c2d3f055155873328e3978f6ede666004e89549d7e58e55", 144, 349, "f7af87e0fbdf71da33054b6ba087d410fee1b9f72abf894d20e75a18f81a8197"],
}

func _initialize() -> void:
	var failures: Array[String] = []
	var builder := Builder.new()
	for seed_value in FIXTURES:
		var result: Dictionary = builder.build(seed_value, 100000, 13)
		var manifest: Variant = result.get("manifest")
		if manifest == null:
			push_error("Could not build frozen Gen13 seed %d: %s" % [seed_value, str(result.get("error", ""))])
			failures.append("Gen13 seed %d failed to build" % seed_value)
			continue
		var coin_rows: Array = []
		for coin in manifest.collectibles:
			coin_rows.append([str(coin.get("entity_id", "")), float(coin.get("world_x", 0.0)), float(coin.get("world_y", 0.0)), int(coin.get("value", 0)), float(coin.get("radius", 0.0))])
		var coin_hash := _hash_json(coin_rows)
		var biome_rows: Array = []
		for distance in [0, 4799, 4800, 9599, 9600, 14399, 14400, 19199]:
			biome_rows.append([distance, BiomeRenderer.biome_id_at(float(distance))])
		var expected: Array = FIXTURES[seed_value]
		if str(manifest.manifest_hash) != str(expected[0]) or manifest.events.size() != int(expected[1]) or manifest.collectibles.size() != int(expected[2]) or coin_hash != str(expected[3]):
			failures.append("Gen13 seed %d changed manifest/events/coins: %s/%d/%d/%s" % [seed_value, manifest.manifest_hash, manifest.events.size(), manifest.collectibles.size(), coin_hash])
		if _hash_json(biome_rows) != "d193325f10aea2daa675c921b1e87a861e4d260b94385f8ef02a04f138168761":
			failures.append("Gen13 biome cycle changed")
	print("GENERATOR_V13_FREEZE_TEST failures=%d" % failures.size())
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _hash_json(value: Variant) -> String:
	var hash_context := HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(JSON.stringify(value).to_utf8_buffer())
	return hash_context.finish().hex_encode()
