extends SceneTree

const Builder := preload("res://systems/course_manifest_builder.gd")
const CoinHashes := {
	100000003: "5a1921b5f6ee3fc6457dc34f038f4acd78e042a42be90dfb1fddeca7337dcf25",
	100000014: "b3ffff8e59ae62c32e8816acd6c119e734f1b5ec3682b063d3bc09198d43d72c",
	100000042: "2d6832aa39fe6c79293cb31c80b82ba88531af50cc610ad02b541f3abf4cbf5e",
	100000777: "449a02a53bc209c9a90ff77eba3b0b317c607ee48dbd87d7d2ec792e82d1420c",
	100000918: "f7af87e0fbdf71da33054b6ba087d410fee1b9f72abf894d20e75a18f81a8197",
}

# Captured from the clean public Gen12 release before the Gen13 fix.
const FIXTURES := {
	100000003: ["044337f2621ad908680e7d974591fa22838cf8de807b987209c65d0de40153c3", 137, 387],
	100000014: ["6d4b5973f9acbfc99c493b3445cd9460d1c42ac9e35f026949c5bcf56284be0f", 130, 299],
	100000042: ["a80c3a1c4646d6817341b4add24499a819eb0086b6f80d29864e62bc4e220a46", 140, 348],
	100000777: ["182ba83aeafc15f04a245901143db00fc74a066c58e9c1530f1a7c57fbe3a07e", 139, 451],
	100000918: ["68e066243f4716056e0e25f5e47a455699bcd18a0c7a94afbb8464d8675e5e49", 144, 349],
}

func _initialize() -> void:
	var failures: Array[String] = []
	var builder := Builder.new()
	for seed_value in FIXTURES:
		var expected: Array = FIXTURES[seed_value]
		var result: Dictionary = builder.build(int(seed_value), 100000, 12)
		var manifest: Variant = result.get("manifest")
		if manifest == null:
			failures.append("Gen12 seed %d failed to build: %s" % [seed_value, str(result.get("error", ""))])
			continue
		if str(manifest.manifest_hash) != str(expected[0]):
			failures.append("Gen12 seed %d manifest changed: expected %s, got %s" % [seed_value, str(expected[0]), str(manifest.manifest_hash)])
		if manifest.events.size() != int(expected[1]) or manifest.collectibles.size() != int(expected[2]):
			failures.append("Gen12 seed %d counts changed: events=%d coins=%d" % [seed_value, manifest.events.size(), manifest.collectibles.size()])
		var coin_rows: Array = []
		for coin in manifest.collectibles:
			coin_rows.append([str(coin.get("entity_id", "")), float(coin.get("world_x", 0.0)), float(coin.get("world_y", 0.0)), int(coin.get("value", 0)), float(coin.get("radius", 0.0))])
		var hash_context := HashingContext.new()
		hash_context.start(HashingContext.HASH_SHA256)
		hash_context.update(JSON.stringify(coin_rows).to_utf8_buffer())
		if hash_context.finish().hex_encode() != str(CoinHashes.get(seed_value, "")):
			failures.append("Gen12 seed %d collectible identity/placement/value hash changed" % seed_value)
	print("GENERATOR_V12_FREEZE_TEST failures=%d" % failures.size())
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
