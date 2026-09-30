extends Node

const MatchScript := preload("res://ui/multiplayer_v2/multiplayer_v2_match.gd")

func _ready() -> void:
	var roster: Array = [
		{"player_slot": 1, "display_name": "Host"},
		{"player_slot": 2, "display_name": "  Runner  "},
		{"player_slot": 3, "display_name": ""},
	]
	assert(MatchScript.spectator_display_name(2, roster) == "Runner", "spectator status should resolve the frozen roster name and trim whitespace")
	assert(MatchScript.spectator_display_name(3, roster) == "Player", "spectator status should use a fallback for an empty display name")
	assert(MatchScript.spectator_display_name(4, roster) == "Player", "spectator status should use a fallback when the peer is missing")
	assert(MatchScript.FLOW_TRACE_MAX_FRAMES == 512, "common presentation traces should be capped at 512 frames per window")
	assert(MatchScript.FLOW_TRACE_MAX_WINDOWS == 5, "common presentation traces should have a fixed per-round window budget")
	print("V2 course flow trace contract tests passed.")
	get_tree().quit(0)
