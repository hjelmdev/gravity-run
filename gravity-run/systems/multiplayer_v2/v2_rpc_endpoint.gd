extends Node
class_name MultiplayerV2RpcEndpoint

signal player_sample_received(peer_id: int, sample: Dictionary)
signal input_audit_received(peer_id: int, audit: Dictionary)
signal terminal_report_received(peer_id: int, report: Dictionary)
signal world_interaction_received(peer_id: int, request: Dictionary)
signal control_received(peer_id: int, kind: String, payload: Dictionary)

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func submit_player_sample(sample: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0:
		return
	player_sample_received.emit(sender, sample.duplicate(true))

@rpc("any_peer", "call_remote", "reliable", 0)
func submit_input_audit(audit: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0:
		return
	input_audit_received.emit(sender, audit.duplicate(true))

@rpc("any_peer", "call_remote", "reliable", 0)
func submit_terminal_report(report: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0:
		return
	terminal_report_received.emit(sender, report.duplicate(true))

@rpc("any_peer", "call_remote", "reliable", 0)
func submit_world_interaction(request: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0:
		return
	world_interaction_received.emit(sender, request.duplicate(true))

@rpc("any_peer", "call_remote", "reliable", 0)
func receive_control(kind: String, payload: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0:
		return
	control_received.emit(sender, kind, payload.duplicate(true))

func send_sample(sample: Dictionary) -> void:
	submit_player_sample.rpc(sample)

func send_sample_to_peer(peer_id: int, sample: Dictionary) -> void:
	submit_player_sample.rpc_id(peer_id, sample)

func send_audit(audit: Dictionary) -> void:
	submit_input_audit.rpc_id(1, audit)

func send_terminal(report: Dictionary) -> void:
	submit_terminal_report.rpc_id(1, report)

func send_interaction(request: Dictionary) -> void:
	submit_world_interaction.rpc_id(1, request)

func send_control(peer_id: int, kind: String, payload: Dictionary) -> void:
	receive_control.rpc_id(peer_id, kind, payload)
