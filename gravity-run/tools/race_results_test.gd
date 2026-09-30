extends SceneTree

const RaceResults := preload("res://systems/race_results.gd")
var failures := 0

func _initialize() -> void:
	_run()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var roster := [
		{"user_id": "peer1-user", "player_slot": 1, "display_name": "Peer One", "skin_id": 11},
		{"user_id": "peer2-user", "player_slot": 2, "display_name": "Peer Two", "skin_id": 22},
		{"user_id": "peer3-user", "player_slot": 3, "display_name": "Peer Three", "skin_id": 33},
	]
	# Reported round: Peer 1 died first, Peer 3 next, Peer 2 farthest.
	var report_fixture := [
		{"owner_peer_id": 1, "state": "dead", "reason": "spikes", "simulation_tick": 198, "world_x": 1846.5},
		{"owner_peer_id": 3, "state": "dead", "reason": "step_spikes", "simulation_tick": 312, "world_x": 2780.0},
		{"owner_peer_id": 2, "state": "dead", "reason": "spikes", "simulation_tick": 1591, "world_x": 13438.3},
	]
	var result := RaceResults.build(roster, report_fixture, 0.0, "all_terminal")
	var rows: Array = result.placements
	_check(rows.size() == 3, "all frozen roster members are represented")
	_check(int(rows[0].owner_peer_id) == 2 and int(rows[0].place) == 1, "reported fixture ranks farthest runner first")
	_check(int(rows[1].owner_peer_id) == 3 and int(rows[1].place) == 2, "reported fixture ranks middle distance second")
	_check(int(rows[2].owner_peer_id) == 1 and int(rows[2].place) == 3, "reported fixture ranks early elimination last")
	_check(str(rows[0].display_name) == "Peer Two" and int(rows[0].skin_id) == 22, "result keeps frozen name and skin")
	_check(is_equal_approx(float(rows[0].distance), 13438.3), "distance is measured from round start")
	_check(int(rows[0].terminal_tick) == 1591 and int(rows[0].finish_tick) == -1, "elimination tick stays separate from finish tick")

	var mixed := RaceResults.build(roster, [
		{"owner_peer_id": 1, "state": "dead", "simulation_tick": 1, "world_x": 900.0},
		{"owner_peer_id": 2, "state": "finished", "simulation_tick": 90, "world_x": 1000.0},
		{"owner_peer_id": 3, "state": "finished", "simulation_tick": 50, "world_x": 1000.0},
	], 0.0)
	_check(int(mixed.placements[0].owner_peer_id) == 3 and int(mixed.placements[1].owner_peer_id) == 2, "finishers rank before eliminations and by ascending finish tick")
	_check(int(mixed.placements[2].owner_peer_id) == 1, "elimination follows every finisher")
	_check(int(mixed.placements[0].finish_tick) == 50 and int(mixed.placements[2].finish_tick) == -1, "finish tick is populated only for finishers")

	var equal_finish := RaceResults.build(roster, [
		{"owner_peer_id": 1, "state": "finished", "simulation_tick": 50, "world_x": 1000.0},
		{"owner_peer_id": 2, "state": "finished", "simulation_tick": 50, "world_x": 1000.0},
		{"owner_peer_id": 3, "state": "dead", "simulation_tick": 60, "world_x": 800.0},
	], 0.0, "", true)
	_check(int(equal_finish.placements[0].place) == 1 and int(equal_finish.placements[1].place) == 1, "equal finish tick shares place")
	_check(equal_finish.winner_user_ids.size() == 2, "stable row order does not invent a sole winner for equal finish tick")
	var v1_finish_tie := RaceResults.build(roster, [
		{"owner_peer_id": 1, "state": "finished", "simulation_tick": 50, "world_x": 1000.0},
		{"owner_peer_id": 2, "state": "finished", "simulation_tick": 50, "world_x": 1000.0},
	], 0.0)
	_check(int(v1_finish_tie.placements[0].place) == 1 and int(v1_finish_tie.placements[1].place) == 2, "default finish-tick behavior preserves V1 unique place ordering")
	_check(v1_finish_tie.winner_user_ids.size() == 1, "default finish-tick behavior preserves V1 winner selection")

	var equal_distance := RaceResults.build(roster, [
		{"owner_peer_id": 1, "state": "dead", "simulation_tick": 2, "world_x": 500.0},
		{"owner_peer_id": 2, "state": "dead", "simulation_tick": 1, "world_x": 500.0},
		{"owner_peer_id": 3, "state": "dead", "simulation_tick": 9, "world_x": 300.0},
	], 0.0)
	_check(int(equal_distance.placements[0].place) == 1 and int(equal_distance.placements[1].place) == 1, "V1-equivalent approximate distance ties share place")
	_check(equal_distance.winner_user_ids.size() == 2, "equal leading distance does not create a sole winner")
	var disconnect := RaceResults.build(roster, report_fixture, 0.0, "confirmed_disconnect")
	_check(disconnect.winner_user_ids.is_empty(), "confirmed disconnect preserves V1 no-winner behavior")

	print("Race results tests: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
