extends Node
## Small one-shot intent for returning from an active run to the game hub.

var _open_game_hub_on_menu := false
var _open_multiplayer_lobby_on_menu := false
var _open_campaign_map_on_menu := false

func request_game_hub() -> void:
	_open_game_hub_on_menu = true

func consume_game_hub_request() -> bool:
	var requested := _open_game_hub_on_menu
	_open_game_hub_on_menu = false
	return requested

func request_multiplayer_lobby() -> void:
	_open_multiplayer_lobby_on_menu = true

func consume_multiplayer_lobby_request() -> bool:
	var requested := _open_multiplayer_lobby_on_menu
	_open_multiplayer_lobby_on_menu = false
	return requested

func request_campaign_map() -> void:
	_open_campaign_map_on_menu = true

func consume_campaign_map_request() -> bool:
	var requested := _open_campaign_map_on_menu
	_open_campaign_map_on_menu = false
	return requested
