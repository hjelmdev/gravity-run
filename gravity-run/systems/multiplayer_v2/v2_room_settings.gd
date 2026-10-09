extends RefCounted
class_name MultiplayerV2RoomSettings
## Host-chosen lobby settings that travel with the room and are frozen into the
## round descriptor. Every reader treats a missing or malformed field as the
## default, so rooms from a server without the column behave exactly as before.

## Lobby toggle "Equipment on/off". On: every player's equipped effect items
## (RunEffects) are active for their own runner. Off: everyone races clean.
const KEY_EQUIPMENT_ENABLED := "equipment_enabled"

## Reads the toggle from a room payload or a round descriptor. Default off.
static func equipment_enabled(source: Dictionary) -> bool:
	var value: Variant = source.get(KEY_EQUIPMENT_ENABLED, false)
	return typeof(value) == TYPE_BOOL and bool(value)

## Copies the settings that matter for the run into the round descriptor. The
## key is only written when it differs from the default, so a clean round's
## descriptor stays byte-identical to what it was before the setting existed.
static func apply_to_descriptor(descriptor: Dictionary, room: Dictionary) -> void:
	if equipment_enabled(room):
		descriptor[KEY_EQUIPMENT_ENABLED] = true

## The settings a match scene needs to configure its run.
static func run_config(descriptor: Dictionary) -> Dictionary:
	return {KEY_EQUIPMENT_ENABLED: equipment_enabled(descriptor)}
