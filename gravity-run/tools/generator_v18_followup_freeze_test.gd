extends SceneTree

const Builder := preload("res://systems/course_manifest_builder.gd")
const SEEDS: Array[int] = [100000014, 100000042, 100000918, 100000122]
const FIXTURES := {
	100000014: ["0bc87357e8f343927376b12111f5a230ee84d8a502c57c3ab5704f9b696ae6ae", 60, "b3d330f6beda8689e713af8ec6cdcd1ca3c61294231f46a6cd7546630fc36681", 209, "810145ea35037b8fb3267c073917710452822f8a309334abae5516011ccc2fc2"],
	100000042: ["4a512de501577e030b951daf83d3d961958fb256faa5dd37e05136882c17275b", 73, "2a2f0d041c89f6b3fd5886360f7a4399691467f956ef17aa0e58e12a0b69265a", 199, "66a9a7513ba5aecefebddb2e3bf14f435f12d709f1f1d29f2258423dccdb73e9"],
	100000918: ["02a11579ce4c002b5dc1a57e0ef83f0758d93337e9138222ec593fc57e262a99", 61, "bde7430b12fdacf1e630f0e5c42dda5d122cc513e758a3190cb1e5b19714d7cd", 188, "33a5370dd857344eb66a027885228c3b655ef91d674c1188e18850dab186a302"],
	100000122: ["b95592a0a12381ed4d5964ca7512a8622029a61d5c3ef3083b0f2f8ac16bd4ec", 58, "807fb76f428392e5ae34f414f06077e3bdcf178d64f39e5ed2e742c0f5218611", 151, "9fee65c6d95e3284400981a3f62304f3828db1015eece420d41c9342fa4ea9a9"],
}
var failures: Array[String] = []

func _initialize() -> void:
	for seed_value in SEEDS:
		var result: Dictionary = Builder.new().build(seed_value, 45000, 18)
		var manifest: Variant = result.get("manifest")
		if manifest == null:
			failures.append("Could not build frozen Gen18 seed %d: %s" % [seed_value, str(result.get("error", ""))])
			continue
		var coins: Array = []
		for coin in manifest.collectibles:
			coins.append([str(coin.get("entity_id", "")), float(coin.get("world_x", 0.0)), float(coin.get("world_y", 0.0)), int(coin.get("value", 0)), float(coin.get("radius", 0.0))])
		var actual := [str(manifest.manifest_hash), manifest.events.size(), _hash(manifest.events), coins.size(), _hash(coins)]
		if actual != FIXTURES[seed_value]:
			failures.append("Gen18 seed %d changed frozen manifest/events/coins: %s" % [seed_value, str(actual)])
		print("GEN18_FOLLOWUP_FREEZE seed=%d manifest=%s events=%d coins=%d" % [seed_value, str(manifest.manifest_hash), manifest.events.size(), coins.size()])
	for failure in failures:
		push_error(failure)
	print("GENERATOR_V18_FOLLOWUP_FREEZE_TEST failures=%d" % failures.size())
	quit(1 if not failures.is_empty() else 0)

func _hash(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(value).to_utf8_buffer())
	return context.finish().hex_encode()
