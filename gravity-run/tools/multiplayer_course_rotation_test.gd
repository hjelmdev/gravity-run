extends SceneTree

const Service := preload("res://systems/multiplayer_v2/multiplayer_v2_service.gd")
const Provider := preload("res://systems/multiplayer_v2/v2_lobby_provider.gd")
const Identity := preload("res://systems/multiplayer_v2/v2_identity_adapter.gd")

class PublicationProbe extends Provider:
	var publications: Array[Dictionary] = []
	func _ready() -> void:
		pass
	func set_manifest(room: String, seed_value: int, length_px: int, hash_value: String, _token: String, _context: String) -> void:
		publications.append({"room_id": room, "seed": seed_value, "length": length_px, "hash": hash_value})

class RoomProbe extends Service:
	var host_role := true
	var creation: Dictionary
	func _ready() -> void:
		pass
	func _begin_identity_action(_action: String, arguments: Dictionary) -> void:
		creation = arguments
	func is_room_owner() -> bool:
		return host_role
	func _member_for_user(_user: String) -> Dictionary:
		return {"loaded_manifest_hash": room_state.get("manifest_hash", "")}

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _make_probe(fixed_seed: int = -1) -> RoomProbe:
	var service := RoomProbe.new()
	service.create_room("Probe", false, fixed_seed)
	service._lobby_provider = PublicationProbe.new()
	service._identity_adapter = Identity.new()
	service.room_state = {"room_id": "probe", "phase": "OPEN", "seed": 11 if fixed_seed < 1 else fixed_seed, "course_length_px": 45000, "lobby_cycle": 1, "manifest_hash": ""}
	return service

func _accept_publication(service: RoomProbe) -> void:
	var publication: Dictionary = service._lobby_provider.publications.back()
	service.room_state.seed = publication.seed
	service.room_state.manifest_hash = publication.hash
	service._manifest_action_pending = ""
	service._ensure_manifest()

func _dispose(service: RoomProbe) -> void:
	service._lobby_provider.free()
	service._identity_adapter.free()
	service.free()

func _run() -> void:
	var host := _make_probe()
	host._ensure_manifest()
	_check(host.current_manifest.seed_value == 11, "first round retains the seed selected at room creation")
	_accept_publication(host)
	var previous_hash: String = host.current_manifest.manifest_hash
	host.room_state.phase = "FINISHED"
	host._ensure_manifest()
	_check(host.current_manifest.manifest_hash == previous_hash, "results do not rotate the course")
	host.room_state.phase = "OPEN"
	host.room_state.lobby_cycle = 2
	_check(host.get_start_blockers().has("course_update_pending"), "lobby-cycle change blocks start before manifest generation")
	host._ensure_manifest()
	var next_seed: int = host.current_manifest.seed_value
	var next_hash: String = host.current_manifest.manifest_hash
	_check(next_seed != 11 and next_seed >= 1 and next_seed <= 2_147_483_647, "rematch chooses a different valid seed")
	_check(next_hash != previous_hash, "rematch has a different course manifest")
	_check(host._lobby_provider.publications.back().seed == next_seed, "published seed belongs to the generated manifest")
	_check(host.get_start_blockers().has("course_update_pending"), "old ready/ACK state cannot start the unpublished course")
	host._ensure_manifest()
	_check(host._lobby_provider.publications.size() == 2, "polling does not publish a second random course")
	host._manifest_action_pending = ""
	host._ensure_manifest()
	_check(host._lobby_provider.publications.size() == 3 and host._lobby_provider.publications.back().seed == next_seed, "failed publication retries the same seed")
	var guest := _make_probe()
	guest.host_role = false
	guest.room_state = host.room_state.duplicate(true)
	guest._ensure_manifest()
	_check(guest.current_manifest.seed_value == 11, "guests never independently rotate the room course")
	_accept_publication(host)
	_check(not host.get_start_blockers().has("course_update_pending"), "accepted publication releases the course barrier")
	guest.room_state = host.room_state.duplicate(true)
	guest._ensure_manifest()
	_check(guest.current_manifest.manifest_hash == next_hash, "guest regenerates the host's confirmed course")
	_check(host.diagnostics.session.seed == next_seed and guest.diagnostics.session.seed == next_seed, "diagnostics record the confirmed rematch seed on both clients")
	for refresh in 5: host._ensure_manifest()
	_check(host.current_manifest.seed_value == next_seed and host._lobby_provider.publications.size() == 3, "confirmed course remains stable across refresh/reconnect in the same cycle")
	host.room_state.lobby_cycle = 3
	host._ensure_manifest()
	_check(host.current_manifest.seed_value != next_seed, "third round rotates again")
	var fixed := _make_probe(12345)
	fixed._ensure_manifest()
	_accept_publication(fixed)
	var fixed_hash: String = fixed.current_manifest.manifest_hash
	fixed.room_state.lobby_cycle = 2
	fixed._ensure_manifest()
	_check(fixed.current_manifest.seed_value == 12345 and fixed.current_manifest.manifest_hash == fixed_hash and fixed._lobby_provider.publications.size() == 1, "explicit seed preserves the replay course")
	host.room_state = {"room_id": "new-room", "phase": "OPEN", "seed": 37, "course_length_px": 45000, "lobby_cycle": 1, "manifest_hash": ""}
	host._manifest_action_pending = ""
	host._ensure_manifest()
	_check(host.current_manifest.seed_value == 37, "a new room discards the previous pending rotation")
	_dispose(host)
	_dispose(guest)
	_dispose(fixed)
	if failures == 0: print("Multiplayer course rotation tests passed: rematches, retry, guest parity, readiness barrier and fixed seed.")
	quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
