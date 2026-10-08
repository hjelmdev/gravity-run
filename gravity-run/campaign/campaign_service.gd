extends Node
## Autoload "Campaign": the active campaign stage and local progress.
##
## Progress lives in its own file (user://gravity_run_campaign.cfg) so it can
## later be merged up into a Supabase campaign_progress table without touching
## the profile file. Records are keyed by stage id and remember the stage
## identity; a stage whose course or stars changed keeps its unlock but starts
## fresh records.

signal progress_changed

const SAVE_PATH := "user://gravity_run_campaign.cfg"
const SCORE_PER_COIN := 10
const SCORE_PER_STAR := 500
const SCORE_PER_SECRET := 1000

var active_level: CampaignLevel
## Tests turn this off so they never touch a player's saved progress.
var persist := true
var _progress: Dictionary = {}
var _last_level_by_world: Dictionary = {}
var _last_world_id: StringName = &"meadow"
## Deaths on the active stage since it was last entered from the map.
var _attempt_deaths := 0

func _ready() -> void:
	_load()

func is_active() -> bool:
	return active_level != null

func start_level(level: CampaignLevel) -> void:
	if level != active_level:
		_attempt_deaths = 0
	active_level = level
	if level != null:
		_last_level_by_world[String(level.world_id)] = String(level.level_id)
		_last_world_id = level.world_id
		_save()

## Remembers the stage chosen on the map without starting it.
func remember_selection(level: CampaignLevel) -> void:
	if level == null:
		return
	_last_level_by_world[String(level.world_id)] = String(level.level_id)
	_last_world_id = level.world_id
	_save()

func clear_active() -> void:
	active_level = null
	_attempt_deaths = 0

func get_last_world_id() -> StringName:
	return _last_world_id

func get_last_level_id(world: CampaignWorld) -> StringName:
	return StringName(str(_last_level_by_world.get(String(world.world_id), "")))

static func score_for(coins: int, star_count: int, secret_found: bool) -> int:
	return coins * SCORE_PER_COIN + star_count * SCORE_PER_STAR + (SCORE_PER_SECRET if secret_found else 0)

func get_record(level: CampaignLevel) -> Dictionary:
	var record: Dictionary = _progress.get(String(level.level_id), {})
	if record.is_empty():
		return {}
	if str(record.get("identity", "")) != level.get_identity():
		# The stage changed: its unlock stays, its scores no longer compare.
		return {"completed": bool(record.get("completed", false)), "completions": int(record.get("completions", 0))}
	return record.duplicate()

func is_completed(level: CampaignLevel) -> bool:
	return bool(get_record(level).get("completed", false))

func get_star_mask(level: CampaignLevel) -> int:
	return int(get_record(level).get("stars_mask", 0))

static func count_bits(mask: int) -> int:
	var count := 0
	while mask > 0:
		count += mask & 1
		mask >>= 1
	return count

func get_star_count(level: CampaignLevel) -> int:
	return count_bits(get_star_mask(level))

func get_best_score(level: CampaignLevel) -> int:
	return int(get_record(level).get("best_score", 0))

func is_world_unlocked(world: CampaignWorld) -> bool:
	if world == null:
		return false
	var worlds := CampaignCatalog.worlds()
	var index := worlds.find(world)
	if index <= 0:
		return true
	var previous: CampaignWorld = worlds[index - 1]
	var boss := previous.get_boss()
	return boss != null and is_completed(boss)

func is_level_unlocked(level: CampaignLevel) -> bool:
	var world := CampaignCatalog.world_of(level)
	if world == null or not is_world_unlocked(world):
		return false
	var index := world.levels.find(level)
	return index == 0 or (index > 0 and is_completed(world.levels[index - 1]))

func get_world_star_count(world: CampaignWorld) -> int:
	var total := 0
	for level in world.levels:
		total += get_star_count(level)
	return total

func get_world_completed_count(world: CampaignWorld) -> int:
	var total := 0
	for level in world.levels:
		total += 1 if is_completed(level) else 0
	return total

func record_death() -> void:
	if active_level == null:
		return
	_attempt_deaths += 1
	var key := String(active_level.level_id)
	var record: Dictionary = _progress.get(key, {})
	if str(record.get("identity", "")) != active_level.get_identity():
		record = {"identity": active_level.get_identity(), "completed": bool(record.get("completed", false)), "completions": int(record.get("completions", 0))}
	record["deaths"] = int(record.get("deaths", 0)) + 1
	_progress[key] = record
	_save()

## Stores a finished stage and reports what changed for the result screen.
func record_completion(coins: int, star_mask: int, secret_found: bool = false) -> Dictionary:
	if active_level == null:
		return {}
	var level := active_level
	var key := String(level.level_id)
	var previous := get_record(level)
	var was_completed := bool(previous.get("completed", false))
	var star_count := count_bits(star_mask)
	var score := score_for(coins, star_count, secret_found)
	var old_best := int(previous.get("best_score", 0))
	var old_mask := int(previous.get("stars_mask", 0))
	var next := CampaignCatalog.next_level(level)
	var next_was_unlocked := next != null and is_level_unlocked(next)
	var record := previous.duplicate()
	record["identity"] = level.get_identity()
	record["completed"] = true
	record["completions"] = int(previous.get("completions", 0)) + 1
	record["best_score"] = maxi(old_best, score)
	record["stars_mask"] = old_mask | star_mask
	record["secret"] = bool(previous.get("secret", false)) or secret_found
	record["first_try"] = bool(previous.get("first_try", false)) or (_attempt_deaths == 0 and not was_completed)
	record["deaths"] = int(previous.get("deaths", 0))
	_progress[key] = record
	_attempt_deaths = 0
	_save()
	progress_changed.emit()
	var world_unlocked: CampaignWorld = null
	if level.is_boss() and not was_completed:
		var worlds := CampaignCatalog.worlds()
		var index := worlds.find(CampaignCatalog.world_of(level))
		if index >= 0 and index + 1 < worlds.size():
			world_unlocked = worlds[index + 1]
	return {
		"score": score,
		"best_score": int(record.best_score),
		"new_best": score > old_best,
		"star_count": star_count,
		"new_stars": count_bits(star_mask & ~old_mask),
		"total_stars": count_bits(int(record.stars_mask)),
		"first_completion": not was_completed,
		"next_level": next,
		"next_unlocked_now": next != null and not next_was_unlocked and is_level_unlocked(next),
		"world_unlocked": world_unlocked,
	}

func get_attempt_deaths() -> int:
	return _attempt_deaths

## Test helper: forget every record (does not touch the save file unless asked).
func reset_progress(save_now: bool = false) -> void:
	_progress.clear()
	_last_level_by_world.clear()
	_last_world_id = &"meadow"
	if save_now:
		_save()
	progress_changed.emit()

func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	var saved: Variant = config.get_value("campaign", "levels", {})
	_progress = saved.duplicate(true) if saved is Dictionary else {}
	var last: Variant = config.get_value("campaign", "last_level_by_world", {})
	_last_level_by_world = last.duplicate(true) if last is Dictionary else {}
	_last_world_id = StringName(str(config.get_value("campaign", "last_world", "meadow")))

func _save() -> void:
	if not persist:
		return
	var config := ConfigFile.new()
	config.load(SAVE_PATH)
	config.set_value("campaign", "levels", _progress)
	config.set_value("campaign", "last_level_by_world", _last_level_by_world)
	config.set_value("campaign", "last_world", String(_last_world_id))
	var error := config.save(SAVE_PATH)
	if error != OK:
		push_warning("Could not save campaign progress (error %s)." % error)
