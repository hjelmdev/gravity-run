extends SceneTree

const Builder := preload("res://systems/course_manifest_builder.gd")
const SEEDS: Array[int] = [100000014, 100000042, 100000918, 100000777]
const FIXTURES := {
	100000014: ["ac2d90aa9bd8483fe7c73de53a5527526e50186717c94145773a7ae9a7050186", 64, "3deaa280095765f0ea9f7b767ab3d48eced83c8f5b74171b546054d70db9fc84", 208, "adc4a885a06857d85e6635bbcc80cbbedc5a4e92f3d7cc76ee04bd831374d420"],
	100000042: ["260458ff67d8346fd092d8f7d10c37b8795d7f5a64470fbe77f8b7ee452b503e", 59, "2094c2b5a6aeed0cff895eec59c089e32038c009d275d26b62ba9b1a3db8e5a4", 197, "a5c579af33626df568b4c7cc8aba5aeda70c8ea4fb505a7d68d2294307f337e6"],
	100000918: ["daa2c51c65fc572e70388b87a2f0fbb1e47e152240961cbbcd28ec6cafbac6c7", 48, "58e1883d699b242a8eae5f496351c751eb2e9a38625059b62cc50e6234d33d71", 105, "6fcf4163366c8d6aac03db21acb3b40efd22b95bc75a6d9af1ff8f808239573e"],
	100000777: ["e320aacd5667efad7cf94d5f09ad9997f4978b3c0e40352c52e14484f80b0830", 71, "18664e16280530acdc7a1e0f774792a600a7b6b5fa332637aa77762adc967985", 222, "143d4a29ddad0b0e1702df59fd490046ab8dc686d4ae71bee8abee0c75e50c86"],
}
var failures: Array[String] = []

func _initialize() -> void:
	var builder := Builder.new()
	for seed_value in SEEDS:
		var result: Dictionary = builder.build(seed_value, 45000, 17)
		var manifest: Variant = result.get("manifest")
		if manifest == null:
			failures.append("Could not build frozen Gen17 seed %d: %s" % [seed_value, str(result.get("error", ""))])
			continue
		var coins: Array = []
		for coin in manifest.collectibles:
			coins.append([str(coin.get("entity_id", "")), float(coin.get("world_x", 0.0)), float(coin.get("world_y", 0.0)), int(coin.get("value", 0)), float(coin.get("radius", 0.0))])
		var actual := [str(manifest.manifest_hash), manifest.events.size(), _hash(manifest.events), coins.size(), _hash(coins)]
		if actual != FIXTURES[seed_value]:
			failures.append("Gen17 seed %d changed frozen identity/events/coins: %s" % [seed_value, str(actual)])
		print("GEN17_FOLLOWUP_FREEZE seed=%d manifest=%s events=%d coins=%d" % [seed_value, str(manifest.manifest_hash), manifest.events.size(), coins.size()])
	for failure in failures:
		push_error(failure)
	print("GENERATOR_V17_FOLLOWUP_FREEZE_TEST failures=%d" % failures.size())
	quit(1 if not failures.is_empty() else 0)

func _hash(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(value).to_utf8_buffer())
	return context.finish().hex_encode()
