extends SceneTree

const Builder := preload("res://systems/course_manifest_builder.gd")
const Generator := preload("res://systems/course_generator.gd")

const FIXTURES := {
	100000014: ["212acc74340c25f0ee36f05e24f18ea2442b7b8947f894e54f475df23d1cc739", "f596f13f8c91765c716ecdae37e135e1ffb493f1465b24641424d0efb57a6232", 143, 315],
	100000042: ["55c66290ba524d569c807545b7cb0d3584e264388e08bf22e88f5d370b12d5cf", "81eb800cee4e4d156adc610f157471f458485ee65cbc4c447a93f8080a0ee9fe", 162, 409],
	100000123: ["64db40d9f6825d77da38fe8d5aa7e3669aa8bd83c3ad5074b3c1eed2a9bb7f16", "550057a5ca2e1b65519bfc159d00245264bdddfe24ea0ec04a2eb6c1e6ac33df", 146, 346],
	100000777: ["7710b800104c6af7e3563538f3b302bb1a2fcf3d7a521d6b6193638682bedf40", "90321d5d8909911569d4f2e74d14f451fddd67cc963ed708e8704b0f64575c66", 119, 285],
}

func _initialize() -> void:
	var failures: Array[String] = []
	var builder := Builder.new()
	for seed_value in FIXTURES:
		var expected: Array = FIXTURES[seed_value]
		var built: Dictionary = builder.build(int(seed_value), 100000, 11)
		var manifest: Variant = built.get("manifest")
		if manifest == null:
			failures.append("gen11 seed %d manifest build failed: %s" % [seed_value, str(built.get("error", ""))])
			continue
		var context := HashingContext.new()
		context.start(HashingContext.HASH_SHA256)
		context.update(JSON.stringify(manifest.collectibles).to_utf8_buffer())
		var coin_hash := context.finish().hex_encode()
		if str(manifest.manifest_hash) != str(expected[0]):
			print("MISMATCH key=%s built_seed=%s gen=%s expected=%s actual=%s events=%s identity=%s rules=%s" % [str(seed_value), str(manifest.seed_value), str(manifest.generator_version), str(expected[0]), str(manifest.manifest_hash), _hash_json(manifest.events), manifest.course_identity, manifest.ruleset_fingerprint])
			failures.append("gen11 seed %d manifest changed: %s" % [seed_value, manifest.manifest_hash])
		if coin_hash != str(expected[1]):
			failures.append("gen11 seed %d coin list changed: %s" % [seed_value, coin_hash])
		if manifest.events.size() != int(expected[2]) or manifest.collectibles.size() != int(expected[3]):
			failures.append("gen11 seed %d counts changed events=%d coins=%d" % [seed_value, manifest.events.size(), manifest.collectibles.size()])
	print("GENERATOR_V11_FREEZE_TEST failures=%d" % failures.size())
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _hash_json(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(value).to_utf8_buffer())
	return context.finish().hex_encode()
