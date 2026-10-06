extends SceneTree

const Builder := preload("res://systems/course_manifest_builder.gd")
const SEEDS: Array[int] = [100000014, 100000042, 100000918, 100000777]
const FIXTURES := {
	100000014: ["134ee7f2794b31d497d8f474a0e36451b5611992ad2a7722ec10152e9231c7b2", 74, "8170ed4b78de0bc00e432a7accf576f167ad0c34298febff9ec4bc29812eebf6", 201, "c7bff8acf70d183949f9324a5d3de5676525d6d768a1c471a934aa48ac2d9d63"],
	100000042: ["6e941b6fafe57ea69c19ffd1ebb76c800779a8f5dafd04e983c08181e9284061", 71, "58b49ba647496a29221c113276d05fda806e94bf57efdaeb10a1c00346235701", 197, "2186523032f157ca10c759ee3e12a852a95fee4096ce5c461d2553a9dbf92732"],
	100000918: ["2ec9aaed36c2e4b90fb0c7f58622bfbbb4ff12655f2065bf0584f741d9034ee3", 48, "7a451d424c95b42ac9b9325af2ab1f23223161cce085b8db34d4482b6aa563a0", 113, "05fab5a9ce1288b2225bd6693c75f0215dcc98a4b86e3db3bce87268a5252c5b"],
	100000777: ["0bf02dcde18a833211f932d1c91af23f37860655cf0317375d5ce57c085761db", 57, "0ce696c2abccf21d59772cc50a6a4511338d7da1e6ce79029fecf516579e9780", 218, "b967cf3d72cfd6ad8c4c87f1e6c48830900386fbd60d4134f50eab1fa20b5d4a"],
}

func _initialize() -> void:
	var builder := Builder.new()
	var failures: Array[String] = []
	for seed_value in SEEDS:
		var result: Dictionary = builder.build(seed_value, 45000, 16)
		var manifest: Variant = result.get("manifest")
		if manifest == null:
			failures.append("Frozen Gen16 seed %d could not build: %s" % [seed_value, str(result.get("error", ""))])
			continue
		var coins: Array = []
		for coin in manifest.collectibles:
			coins.append([str(coin.get("entity_id", "")), float(coin.get("world_x", 0.0)), float(coin.get("world_y", 0.0)), int(coin.get("value", 0)), float(coin.get("radius", 0.0))])
		var actual := [str(manifest.manifest_hash), manifest.events.size(), _hash(manifest.events), coins.size(), _hash(coins)]
		if actual != FIXTURES[seed_value]:
			failures.append("Gen16 seed %d changed frozen identity/events/coins: %s" % [seed_value, str(actual)])
		print("GEN16_FREEZE seed=%d manifest=%s events=%d coins=%d" % [seed_value, str(manifest.manifest_hash), manifest.events.size(), coins.size()])
	print("GENERATOR_V16_FREEZE_TEST failures=%d" % failures.size())
	for failure in failures:
		push_error(failure)
	quit(1 if not failures.is_empty() else 0)

func _hash(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(value).to_utf8_buffer())
	return context.finish().hex_encode()
