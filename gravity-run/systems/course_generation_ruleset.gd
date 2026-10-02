extends Resource
class_name CourseGenerationRuleset
## Data-only generation contract shared by endless, seeded challenges and
## authored campaign stages. The seed supplies variation; this resource
## constrains which encounter profiles and difficulty factors may be used.

const CourseDifficultyProfileScript = preload("res://systems/course_difficulty_profile.gd")

@export var ruleset_id: StringName = &"standard"
@export_range(1, 1000, 1) var revision := 1
## When false, only the listed profile IDs may appear. Empty allowlists are invalid.
@export var include_all_profiles := true
@export var included_profile_ids := PackedStringArray()
@export_range(0.5, 2.5, 0.05) var event_density := 1.25
@export_range(0.75, 1.5, 0.05) var hazard_size := 1.0
@export_range(0.0, 1.0, 0.05) var lane_alternation := 0.0
@export_range(0.0, 2.0, 0.05) var reaction_margin := 1.0
@export_range(0.5, 2.0, 0.05) var coin_density := 1.0
@export_range(1, 100, 1) var coin_revision := 1
## Per-profile multipliers allow a ruleset to favor or suppress individual
## encounter families without coupling the generator to specific hazard types.
@export var profile_weight_multipliers: Dictionary = {}

func validate(available_profiles: Array) -> String:
	if ruleset_id == StringName():
		return "A ruleset needs a stable ID."
	if revision < 1:
		return "A ruleset revision must be positive."
	if not include_all_profiles and included_profile_ids.is_empty():
		return "A restricted ruleset must include at least one hazard profile."
	if not is_finite(event_density) or not is_finite(hazard_size) or event_density < 0.5 or event_density > 2.5 or hazard_size < 0.75 or hazard_size > 1.5:
		return "A ruleset difficulty factor is outside the supported range."
	if not is_finite(lane_alternation) or not is_finite(reaction_margin) or not is_finite(coin_density) or lane_alternation < 0.0 or lane_alternation > 1.0 or reaction_margin < 0.0 or reaction_margin > 2.0 or coin_density < 0.5 or coin_density > 2.0 or coin_revision < 1 or coin_revision > 100:
		return "A ruleset movement factor is outside the supported range."

	var available_ids: Array[StringName] = []
	for profile in available_profiles:
		if profile is CourseHazardProfile:
			if available_ids.has(profile.profile_id):
				return "Hazard profile IDs must be unique."
			available_ids.append(profile.profile_id)
	var selected_ids: PackedStringArray = PackedStringArray()
	if include_all_profiles:
		for profile_id in available_ids:
			selected_ids.append(String(profile_id))
	else:
		selected_ids = included_profile_ids.duplicate()
	for profile_id in selected_ids:
		if not available_ids.has(StringName(profile_id)):
			return "Ruleset '%s' references unknown hazard profile '%s'." % [ruleset_id, profile_id]
		if selected_ids.count(profile_id) > 1:
			return "A hazard profile may only appear once in a ruleset allowlist."
	if selected_ids.is_empty():
		return "A ruleset must leave at least one hazard profile available."

	var usable_weight := 0.0
	for weight_key in profile_weight_multipliers:
		if not available_ids.has(StringName(str(weight_key))):
			return "Ruleset '%s' has a weight for unknown hazard profile '%s'." % [ruleset_id, str(weight_key)]
	for profile in available_profiles:
		if not profile is CourseHazardProfile or not selected_ids.has(String(profile.profile_id)):
			continue
		var multiplier := float(profile_weight_multipliers.get(String(profile.profile_id), 1.0))
		if not is_finite(multiplier) or multiplier < 0.0:
			return "Profile weights must be finite and non-negative."
		usable_weight += profile.weight * multiplier
	if usable_weight <= 0.0:
		return "A ruleset must leave at least one positive-weight hazard profile."
	return ""

func create_difficulty_profile() -> Resource:
	var profile := CourseDifficultyProfileScript.new() as Resource
	profile.set("event_density", event_density)
	profile.set("hazard_size", hazard_size)
	profile.set("lane_alternation", lane_alternation)
	profile.set("reaction_margin", reaction_margin)
	profile.set("profile_weight_multipliers", profile_weight_multipliers.duplicate(true))
	return profile

## Stable identity for future challenge codes/storage. It covers all selectable
## generation inputs; the generator version separately covers algorithm/catalog
## changes. It intentionally does not include a run seed.
func get_fingerprint() -> String:
	var profile_ids: Array[String] = []
	for profile_id in included_profile_ids:
		profile_ids.append(profile_id)
	profile_ids.sort()
	var weight_keys: Array[String] = []
	for key in profile_weight_multipliers:
		weight_keys.append(str(key))
	weight_keys.sort()
	var weights: Array[Array] = []
	for key in weight_keys:
		weights.append([key, snappedf(float(profile_weight_multipliers[key]), 0.0001)])
	var payload := [
		String(ruleset_id), revision, include_all_profiles, profile_ids,
		snappedf(event_density, 0.0001), snappedf(hazard_size, 0.0001),
		snappedf(lane_alternation, 0.0001), snappedf(reaction_margin, 0.0001), weights
	]
	if not is_equal_approx(coin_density, 1.0) or coin_revision != 1:
		payload.append([snappedf(coin_density, 0.0001), coin_revision])
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(payload).to_utf8_buffer())
	return context.finish().hex_encode().substr(0, 16)

## Transport/storage representation. Keep this whitelist explicit so challenge
## records cannot smuggle arbitrary Resource properties into a run definition.
func to_payload() -> Dictionary:
	var profile_ids: Array[String] = []
	for profile_id in included_profile_ids:
		profile_ids.append(profile_id)
	profile_ids.sort()
	var weights: Dictionary = {}
	for key in profile_weight_multipliers:
		weights[str(key)] = snappedf(float(profile_weight_multipliers[key]), 0.0001)
	return {
		"ruleset_id": String(ruleset_id),
		"revision": revision,
		"include_all_profiles": include_all_profiles,
		"included_profile_ids": profile_ids,
		"event_density": snappedf(event_density, 0.0001),
		"hazard_size": snappedf(hazard_size, 0.0001),
		"lane_alternation": snappedf(lane_alternation, 0.0001),
		"reaction_margin": snappedf(reaction_margin, 0.0001),
		"coin_density": snappedf(coin_density, 0.0001),
		"coin_revision": coin_revision,
		"profile_weight_multipliers": weights,
	}

static func from_payload(payload: Variant) -> Resource:
	# PostgREST normally returns JSONB as a nested object. Accept a serialized
	# JSON object too, so providers that wrap JSONB don't make valid rules unusable.
	if payload is String:
		payload = JSON.parse_string(payload)
	if not payload is Dictionary:
		return null
	var ruleset := CourseGenerationRuleset.new() as Resource
	var ruleset_id := str(payload.get("ruleset_id", "")).strip_edges()
	if ruleset_id.is_empty() or ruleset_id.length() > 48:
		return null
	var revision_value: Variant = payload.get("revision")
	if (not revision_value is int and not revision_value is float) or not is_finite(float(revision_value)):
		return null
	if not is_equal_approx(float(revision_value), roundf(float(revision_value))) or int(revision_value) < 1 or int(revision_value) > 1000:
		return null
	var include_all_value: Variant = payload.get("include_all_profiles")
	if not include_all_value is bool:
		return null
	ruleset.set("ruleset_id", StringName(ruleset_id))
	ruleset.set("revision", int(revision_value))
	ruleset.set("include_all_profiles", include_all_value)
	var profile_ids: Variant = payload.get("included_profile_ids", [])
	if not profile_ids is Array or profile_ids.size() > 64:
		return null
	var parsed_ids := PackedStringArray()
	for profile_id in profile_ids:
		if not profile_id is String or str(profile_id).length() > 48:
			return null
		parsed_ids.append(str(profile_id))
	ruleset.set("included_profile_ids", parsed_ids)
	for factor_key in ["event_density", "hazard_size", "lane_alternation", "reaction_margin"]:
		var factor: Variant = payload.get(factor_key)
		if not factor is float and not factor is int:
			return null
		ruleset.set(factor_key, float(factor))
	var coin_density: Variant = payload.get("coin_density", 1.0)
	var coin_revision: Variant = payload.get("coin_revision", 1)
	if (not coin_density is float and not coin_density is int) or (not coin_revision is float and not coin_revision is int):
		return null
	ruleset.set("coin_density", float(coin_density))
	if not is_equal_approx(float(coin_revision), roundf(float(coin_revision))):
		return null
	ruleset.set("coin_revision", int(coin_revision))
	var weight_payload: Variant = payload.get("profile_weight_multipliers", {})
	if not weight_payload is Dictionary:
		return null
	var weights: Dictionary = {}
	for key in weight_payload:
		var weight: Variant = weight_payload[key]
		if not weight is float and not weight is int:
			return null
		weights[str(key)] = float(weight)
	ruleset.set("profile_weight_multipliers", weights)
	return ruleset
