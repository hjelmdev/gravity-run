extends RefCounted
class_name MultiplayerRaceRules

const MAX_PLAYERS := 4
const MIN_PLAYERS := 1

static func validate_players(players: Array) -> String:
	if players.size() < MIN_PLAYERS:
		return "A race requires at least one player."
	if players.size() > MAX_PLAYERS:
		return "A race supports at most four players."
	var seen := {}
	for player in players:
		if not player is Dictionary:
			return "A player entry is malformed."
		var user_id := str(player.get("user_id", ""))
		if user_id.is_empty() or seen.has(user_id):
			return "Player identities must be present and unique."
		seen[user_id] = true
	return ""

static func make_result(placements: Array[Dictionary]) -> Dictionary:
	var ordered := placements.duplicate(true)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_tick := int(a.get("finish_tick", 0))
		var b_tick := int(b.get("finish_tick", 0))
		if a_tick != b_tick:
			return a_tick < b_tick
		return str(a.get("user_id", "")) < str(b.get("user_id", ""))
	)
	for index in range(ordered.size()):
		ordered[index]["place"] = index + 1
	return {"placements": ordered, "winner_user_id": str(ordered[0].get("user_id", "")) if not ordered.is_empty() else ""}
