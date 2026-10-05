extends SceneTree

const Builder := preload("res://systems/course_manifest_builder.gd")
const SEEDS: Array[int] = [100000003, 100000014, 100000042, 100000777, 100000918]
const FIXTURES := {
	100000003: ["a5d3cde5f7e1984a53b5531338ea1cf5113e80940f32e62d91ecac9934ff9ab6", 53, "75b9b05a415c10414af11efcabd51b85ab768850562731939844004859b893f7", 200, "761f246c2bc3b10089f89f9a21aa4f5b663f4ff7f7c105f6f53851480cf6c151"],
	100000014: ["da30b605f3920f22f4e96b92807e94a6ea5c04b8e1cebce69e6a163e920371ea", 61, "25467ec7ac4b1d7816ddf4533eadd5dbb5dca4525766a9540405d86a5e93df4b", 185, "b278a1e46c55538493add210cbc34ec8fd17b4c81d4091a75aff19bf44c45580"],
	100000042: ["47418eaebfe59a77a6f0d08f18470b856bfd9b802c84bc96e5ff155da7c3a4e5", 63, "7375b14284ef21812f6ae067151951b3f9f3a33dde2558328ec17ffbf3d02527", 195, "dc6b1d4efa66caff081855e9d9b133371a66142aac4146f6ee1d1b63e6db91cd"],
	100000777: ["b007c0b20f78995c60c305c0036fa1b42c9c4896ea2fc44c94ba6c42822ae189", 45, "9921128d385648d4fe612492aef98050623699324be823ab8be2bf0133953dcc", 177, "3d933762d108d8724fea420aeadc24316215169ae8419263d04f4cf8321d24a1"],
	100000918: ["c0de74e66eaf5d94c2656d8f44ebff9c31dfb7c7960db16b26437ce36fa6748e", 60, "56f371e5e16662a54ec675ee6011332abce0c3dfbe55eb3b2904923307d9e127", 189, "61def53d7e60bf1a8027c46b296d01fd1fb9869cdff304b09dd079d610a69f95"],
}

func _initialize() -> void:
	var builder := Builder.new()
	var failures: Array[String] = []
	for seed_value in SEEDS:
		var result: Dictionary = builder.build(seed_value, 45000, 14)
		var manifest: Variant = result.get("manifest")
		if manifest == null:
			push_error("Could not build frozen Gen14 seed %d: %s" % [seed_value, str(result.get("error", ""))])
			failures.append("Gen14 seed %d could not be built" % seed_value)
			continue
		var events: Array = manifest.events
		var coins: Array = []
		for coin in manifest.collectibles:
			coins.append([str(coin.get("entity_id", "")), float(coin.get("world_x", 0.0)), float(coin.get("world_y", 0.0)), int(coin.get("value", 0)), float(coin.get("radius", 0.0))])
		var event_hash := _hash_json(events)
		var coin_hash := _hash_json(coins)
		var expected: Array = FIXTURES[seed_value]
		if str(manifest.manifest_hash) != expected[0] or events.size() != int(expected[1]) or event_hash != expected[2] or coins.size() != int(expected[3]) or coin_hash != expected[4]:
			failures.append("Gen14 seed %d changed: manifest=%s events=%d/%s coins=%d/%s" % [seed_value, str(manifest.manifest_hash), events.size(), event_hash, coins.size(), coin_hash])
	print("GENERATOR_V14_FREEZE_TEST failures=%d" % failures.size())
	for failure in failures:
		push_error(failure)
	quit(1 if not failures.is_empty() else 0)

func _hash_json(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(value).to_utf8_buffer())
	return context.finish().hex_encode()
