extends RefCounted
class_name ItemPresentation

const EquipmentStatsScript := preload("res://systems/equipment_stats.gd")
const ENGLISH_FALLBACKS := {
	"item.helmet_copper_01.name": "Copper Helmet",
	"item.helmet_copper_01.description": "A simple helmet made of copper.",
	"item.helmet_scout_01.name": "Scout Hood",
	"item.helmet_scout_01.description": "A light hood for quick expeditions.",
	"item.helmet_night_01.name": "Night Visor",
	"item.helmet_night_01.description": "A dark visor with an unusual sheen.",
	"item.boots_canvas_01.name": "Canvas Boots",
	"item.boots_canvas_01.description": "Comfortable canvas shoes.",
	"item.boots_runner_01.name": "Runner Boots",
	"item.boots_runner_01.description": "Durable shoes made for long runs.",
	"item.boots_gravity_01.name": "Gravity Boots",
	"item.boots_gravity_01.description": "Sturdy soles built for changing gravity.",
}
static var _warned_invalid_modifiers: Dictionary = {}

static func item_name(definition: Dictionary) -> String:
	var key := str(definition.get("name_key", ""))
	var translated: String = TranslationServer.translate(key) if not key.is_empty() else ""
	if not translated.is_empty() and translated != key:
		return translated
	if ENGLISH_FALLBACKS.has(key):
		return str(ENGLISH_FALLBACKS[key])
	return TranslationServer.translate("Item name unavailable")

static func item_description(definition: Dictionary) -> String:
	var key := str(definition.get("description_key", ""))
	var translated: String = TranslationServer.translate(key) if not key.is_empty() else ""
	if not translated.is_empty() and translated != key:
		return translated
	if ENGLISH_FALLBACKS.has(key):
		return str(ENGLISH_FALLBACKS[key])
	return TranslationServer.translate("Item description unavailable")

static func effects(definition: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var modifiers: Variant = definition.get("stat_modifiers", {})
	if not modifiers is Dictionary:
		return result
	var definition_error := EquipmentStatsScript.validate_modifiers(modifiers)
	if not definition_error.is_empty():
		var warning_key := str(definition.get("item_id", "unknown_item"))
		if not _warned_invalid_modifiers.has(warning_key):
			_warned_invalid_modifiers[warning_key] = true
			push_warning("Item '%s' has unsupported stat modifiers; hiding them in item details." % warning_key)
		return result
	for stat_id in EquipmentStatsScript.STAT_ORDER:
		if not modifiers.has(stat_id):
			continue
		var raw: Variant = modifiers[stat_id]
		if typeof(raw) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(raw)):
			continue
		var amount := int(roundf(float(raw)))
		if amount == 0:
			continue
		var percent := absf(float(amount) / 100.0)
		var value := "%.2f" % percent
		while value.ends_with("0"):
			value = value.substr(0, value.length() - 1)
		if value.ends_with("."):
			value = value.substr(0, value.length() - 1)
		if TranslationServer.get_locale().begins_with("sv"):
			value = value.replace(".", ",")
		var increase := amount > 0
		var favorable := increase if stat_id == "run_speed_percent" else not increase
		var prefix := "+" if increase else "−"
		var stat_name := TranslationServer.translate("Run speed") if stat_id == "run_speed_percent" else TranslationServer.translate("Gravity flip cooldown")
		result.append({
			"stat_id": str(stat_id),
			"amount_bps": amount,
			"text": "%s %s%s%%" % [stat_name, prefix, value],
			"beneficial": favorable,
		})
	return result

static func tooltip(definition: Dictionary, context: Dictionary = {}) -> String:
	if definition.is_empty():
		return TranslationServer.translate("Item details unavailable")
	var rarity := TranslationServer.translate(str(definition.get("rarity", "common")).capitalize())
	var metadata := "%s · %s" % [slot_name(str(definition.get("slot_type", ""))), rarity]
	if bool(context.get("equipped", false)):
		metadata += " · " + TranslationServer.translate("Equipped")
	elif bool(context.get("owned", false)):
		metadata += " · " + TranslationServer.translate("Owned")
	var lines := PackedStringArray([item_name(definition), metadata, item_description(definition)])
	var item_effects := effects(definition)
	if item_effects.is_empty():
		lines.append(TranslationServer.translate("No stat bonuses"))
	else:
		for effect in item_effects:
			lines.append(str(effect.text))
	return "\n".join(lines)

static func slot_name(slot: String) -> String:
	match slot:
		"helmet": return TranslationServer.translate("Helmet")
		"boots": return TranslationServer.translate("Boots")
		_: return TranslationServer.translate("Unknown slot")
