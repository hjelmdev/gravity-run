extends Node
## Small one-shot intent for returning from an active run to the game hub.

var _open_game_hub_on_menu := false

func request_game_hub() -> void:
	_open_game_hub_on_menu = true

func consume_game_hub_request() -> bool:
	var requested := _open_game_hub_on_menu
	_open_game_hub_on_menu = false
	return requested
