extends Node

signal state_changed(state: Dictionary, stale: bool, error_message: String)
signal action_finished(action: String, success: bool, message: String, result: Dictionary)

const Provider = preload("res://systems/supabase_inventory_provider.gd")
const ItemDefinitionScript = preload("res://systems/item_definition.gd")
const RunLoadoutSnapshotScript = preload("res://systems/run_loadout_snapshot.gd")
const CACHE_PATH := "user://gravity_run_inventory.cfg"

var inventory_state: Dictionary = {}
var state_is_stale := false
var last_error := ""
var _provider: Node
var _user_id := ""
var _mutation_pending := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_provider = Provider.new()
	_provider.name = "SupabaseInventoryProvider"
	_provider.request_finished.connect(_on_request_finished)
	add_child(_provider)
	AuthService.auth_state_changed.connect(_on_auth_state_changed)
	if AuthService.is_authenticated:
		_activate_user(AuthService.user_id)

func refresh() -> void:
	if not AuthService.is_authenticated or AuthService.user_id.is_empty():
		return
	_provider.load_inventory(AuthService.get_access_token(), AuthService.user_id)

func purchase(item_id: String) -> void:
	if not _begin_mutation("purchase_item"):
		return
	var request_id := _create_request_id()
	_provider.purchase_item(item_id, request_id, AuthService.get_access_token(), _user_id + "|" + request_id)

func equip(instance_id: String, slot_type: String) -> void:
	if not _begin_mutation("equip_item"):
		return
	_provider.equip_item(instance_id, slot_type, AuthService.get_access_token(), _user_id)

func unequip(slot_type: String) -> void:
	if not _begin_mutation("unequip_item"):
		return
	_provider.unequip_item(slot_type, AuthService.get_access_token(), _user_id)

func create_run_loadout_snapshot(character_stats: Resource) -> Resource:
	var base_stats: Dictionary = {}
	if character_stats != null and character_stats.has_method("get_base_stats") and character_stats.has_method("validate") and str(character_stats.call("validate")).is_empty():
		base_stats = character_stats.call("get_base_stats")
	else:
		push_warning("Missing or invalid character profile stats; equipment bonuses will not be applied this run.")
	var entries: Array[Dictionary] = []
	var equipped: Variant = inventory_state.get("equipment", {})
	if equipped is Dictionary:
		for slot in equipped:
			var instance_id := str(equipped[slot])
			var owned := _find_owned_item(instance_id)
			if owned.is_empty():
				continue
			var raw: Dictionary = owned.get("definition", {})
			var definition = ItemDefinitionScript.new()
			definition.item_id = str(raw.get("item_id", ""))
			definition.slot_type = str(raw.get("slot_type", ""))
			definition.rarity = str(raw.get("rarity", "common"))
			definition.name_key = str(raw.get("name_key", ""))
			definition.description_key = str(raw.get("description_key", ""))
			definition.icon_key = str(raw.get("icon_key", "unknown"))
			var modifiers: Variant = raw.get("stat_modifiers", {})
			definition.stat_modifiers = modifiers if modifiers is Dictionary else {}
			entries.append({"slot_type": str(slot), "instance_id": instance_id, "definition": definition})
	var version := 1
	var catalog: Variant = inventory_state.get("catalog", [])
	if catalog is Array:
		for raw_definition in catalog:
			if raw_definition is Dictionary:
				version = maxi(version, int(raw_definition.get("catalog_version", 1)))
	var snapshot = RunLoadoutSnapshotScript.create(entries, version, base_stats)
	if not snapshot.is_valid():
		push_warning("Invalid equipped inventory; starting this run with the default loadout: %s" % ", ".join(snapshot.get_errors()))
		return RunLoadoutSnapshotScript.create([], version, base_stats)
	return snapshot

func _find_owned_item(instance_id: String) -> Dictionary:
	if instance_id.is_empty():
		return {}
	var items: Variant = inventory_state.get("items", [])
	var catalog: Variant = inventory_state.get("catalog", [])
	if not items is Array or not catalog is Array:
		return {}
	var definitions := {}
	for raw_definition in catalog:
		if raw_definition is Dictionary:
			definitions[str(raw_definition.get("item_id", ""))] = raw_definition
	for item in items:
		if item is Dictionary and str(item.get("instance_id", "")) == instance_id:
			return {"instance": item, "definition": definitions.get(str(item.get("item_id", "")), {})}
	return {}

func _begin_mutation(action: String) -> bool:
	if not AuthService.is_authenticated or AuthService.user_id.is_empty():
		action_finished.emit(action, false, tr("Sign in to use inventory and the shop."), {})
		return false
	if _mutation_pending:
		action_finished.emit(action, false, tr("Another inventory change is already in progress."), {})
		return false
	_mutation_pending = true
	return true

func _on_auth_state_changed(authenticated: bool, _email: String) -> void:
	if not authenticated:
		_activate_user("")
	elif AuthService.user_id != _user_id:
		_activate_user(AuthService.user_id)
	else:
		refresh()

func _activate_user(user_id: String) -> void:
	_user_id = user_id
	_mutation_pending = false
	inventory_state.clear()
	state_is_stale = false
	last_error = ""
	state_changed.emit({}, false, "")
	if not user_id.is_empty():
		_load_cached_state(user_id)
		refresh()

func _on_request_finished(action: String, success: bool, data: Variant, message: String, context: String) -> void:
	if action == "load_inventory":
		if context != _user_id or not AuthService.is_authenticated:
			return
		if success and data is Dictionary:
			_apply_state(data)
		else:
			state_is_stale = not inventory_state.is_empty()
			last_error = message
			state_changed.emit(inventory_state.duplicate(true), state_is_stale, last_error)
		return
	_mutation_pending = false
	var request_user_id := context.split("|", false)[0] if "|" in context else context
	if request_user_id != _user_id or not AuthService.is_authenticated:
		return
	var result: Dictionary = data if data is Dictionary else {}
	if not success:
		action_finished.emit(action, false, message, {})
		return
	if action == "purchase_item":
		result = result.get("purchase", {}) if result.get("purchase", {}) is Dictionary else {}
		var authoritative_state: Variant = data.get("state", {})
		if authoritative_state is Dictionary:
			_apply_state(authoritative_state)
		action_finished.emit(action, true, tr("Item purchased."), result)
		return
	_apply_state(result)
	action_finished.emit(action, true, tr("Equipment updated."), {})
	# Refresh the catalog as well as the equipped slot; item definitions can gain
	# new stats after an account already owns the item.
	refresh()

func _apply_state(state: Dictionary) -> void:
	if not AuthService.is_authenticated or AuthService.user_id != _user_id:
		return
	inventory_state = state.duplicate(true)
	state_is_stale = false
	last_error = ""
	_save_cached_state()
	AccountProgress.apply_authoritative_wallet_balance(int(state.get("wallet_coins", 0)))
	state_changed.emit(inventory_state.duplicate(true), false, "")

func _load_cached_state(user_id: String) -> void:
	var config := ConfigFile.new()
	if config.load(CACHE_PATH) != OK:
		return
	var cached: Variant = config.get_value(user_id, "state", {})
	if cached is Dictionary and not cached.is_empty() and user_id == _user_id and AuthService.is_authenticated:
		inventory_state = cached.duplicate(true)
		state_is_stale = true
		state_changed.emit(inventory_state.duplicate(true), true, tr("Showing saved inventory while syncing."))

func _save_cached_state() -> void:
	if _user_id.is_empty() or not AuthService.is_authenticated or AuthService.user_id != _user_id:
		return
	var config := ConfigFile.new()
	config.load(CACHE_PATH)
	config.set_value(_user_id, "state", inventory_state)
	var error := config.save(CACHE_PATH)
	if error != OK:
		push_warning("Could not cache inventory state (error %d)." % error)

func _create_request_id() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (int(bytes[6]) & 0x0f) | 0x40
	bytes[8] = (int(bytes[8]) & 0x3f) | 0x80
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]
