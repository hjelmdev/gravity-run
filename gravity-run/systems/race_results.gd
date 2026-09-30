extends RefCounted
## Pure race-result ordering and placement rules shared by the race modes.
## V1 ranks finishers first by finish tick; non-finishers rank by world_x using
## is_equal_approx for ties. Equal finish ticks stay unique by default to
## preserve V1; callers may opt into shared finish places explicitly.

static func build(frozen_roster: Array, terminal_reports: Array, start_x: float, round_reason: String = "", share_finish_ties: bool = false) -> Dictionary:
	var report_by_peer: Dictionary = {}
	for value in terminal_reports:
		if value is Dictionary:
			var peer_id := int(value.get("owner_peer_id", value.get("player_slot", -1)))
			if peer_id > 0:
				report_by_peer[peer_id] = value.duplicate(true)
	var rows: Array[Dictionary] = []
	for value in frozen_roster:
		if not value is Dictionary:
			continue
		var member: Dictionary = value
		var peer_id := int(member.get("player_slot", member.get("peer_id", -1)))
		if peer_id <= 0:
			continue
		var report: Dictionary = report_by_peer.get(peer_id, {})
		var terminal_tick := int(report.get("simulation_tick", report.get("terminal_tick", -1)))
		var state := str(report.get("state", "disconnected"))
		var world_x := float(report.get("world_x", start_x))
		rows.append({
			"user_id": str(member.get("user_id", member.get("stable_id", "peer:%d" % peer_id))),
			"owner_peer_id": peer_id,
			"player_slot": peer_id,
			"display_name": str(member.get("display_name", "Player %d" % peer_id)),
			"skin_id": int(member.get("skin_id", 0)),
			"state": state,
			"reason": str(report.get("reason", "")),
			"distance": maxf(0.0, world_x - start_x),
			"world_x": world_x,
			"terminal_tick": terminal_tick,
			"finish_tick": terminal_tick if state == "finished" else -1,
			"place": 0,
			"_has_report": not report.is_empty(),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_finished := str(a.state) == "finished"
		var b_finished := str(b.state) == "finished"
		if a_finished != b_finished:
			return a_finished
		if a_finished and int(a.finish_tick) != int(b.finish_tick):
			return int(a.finish_tick) < int(b.finish_tick)
		if not is_equal_approx(float(a.world_x), float(b.world_x)):
			return float(a.world_x) > float(b.world_x)
		if str(a.user_id) != str(b.user_id):
			return str(a.user_id) < str(b.user_id)
		return int(a.owner_peer_id) < int(b.owner_peer_id)
	)
	var prior_place := 0
	for index in range(rows.size()):
		var row: Dictionary = rows[index]
		var place := index + 1
		if index > 0:
			var previous: Dictionary = rows[index - 1]
			var both_finished := str(row.state) == "finished" and str(previous.state) == "finished"
			var same_finish_tick := share_finish_ties and both_finished and int(row.finish_tick) == int(previous.finish_tick)
			var same_eliminated_distance := not both_finished and str(row.state) != "finished" and str(previous.state) != "finished" and is_equal_approx(float(row.world_x), float(previous.world_x))
			if same_finish_tick or same_eliminated_distance:
				place = prior_place
		row.place = place
		prior_place = place
		row.erase("_has_report")
	var winners: Array[String] = []
	if not rows.is_empty() and round_reason != "confirmed_disconnect":
		var first: Dictionary = rows[0]
		for row in rows:
			if int(row.place) == int(first.place):
				winners.append(str(row.user_id))
			else:
				break
	return {"placements": rows, "winner_user_ids": winners, "reason": round_reason}
