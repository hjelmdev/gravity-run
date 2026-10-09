extends RefCounted
class_name RunEffects
## Per-run state for equipped effect items (see EquipmentStats.EFFECT_REGISTRY).
## Everything is counted in physics ticks (60 Hz) so a run stays deterministic.
## The singleplayer scene owns one instance and calls the hooks below; nothing
## here touches the scene tree.

const TICKS_PER_SECOND := 60
## Bubble shield recharge by level: 20 s, 15 s, 10 s.
const BUBBLE_RECHARGE_TICKS: Array[int] = [1200, 900, 600]
## Invulnerability after the bubble pops, so the runner can leave the hazard.
const BUBBLE_INVULNERABLE_TICKS := 60
## How long the bubble pop animation is shown.
const BUBBLE_POP_TICKS := 24
## Spike plate: spikes are harmless for this long after every flip.
const SPIKE_PLATE_TICKS: Array[int] = [60, 75, 90]
## Coin magnet reach in pixels by level, and how fast a pulled coin flies.
const MAGNET_RADIUS: Array[float] = [90.0, 140.0, 190.0]
const MAGNET_PULL_SPEED := 1500.0
## Regret boots: a flip can be reversed during the first ticks of its flight,
## by level. A full flight between floor and ceiling takes about 20 ticks, so
## this is roughly the first 50 %, 65 % and 80 % of it.
const REGRET_WINDOW_TICKS: Array[int] = [10, 13, 16]
## How long the reverse ring is shown.
const REGRET_FLASH_TICKS := 18
## Gravity anchor: the runner glides along the middle of the course this long.
const ANCHOR_GLIDE_TICKS := 60
## Gravity anchor recharge by level (after the glide ends): 15 s, 12 s, 9 s.
const ANCHOR_RECHARGE_TICKS: Array[int] = [900, 720, 540]

var _bubble_level := 0
var _bubble_recharge_left := 0
var _invulnerable_left := 0
var _pop_ticks_left := 0
var _spike_plate_level := 0
var _spike_immune_left := 0
var _magnet_level := 0
var _regret_level := 0
var _regret_window_left := 0
var _regret_used := false
var _regret_flash_left := 0
var _anchor_level := 0
var _anchor_glide_left := 0
var _anchor_recharge_left := 0
## Biome key of a campaign stage (BiomeKeys), "" off. A guarding key absorbs
## one hit from its hazard family per stage.
var _key_id := ""
var _key_used := false

## Reads the effect entries of a RunLoadoutSnapshot. Null or invalid snapshots
## leave every effect off.
func configure(snapshot: Resource) -> void:
	_key_id = ""
	_bubble_level = 0
	_spike_plate_level = 0
	_magnet_level = 0
	_regret_level = 0
	_anchor_level = 0
	if snapshot != null and snapshot.has_method("is_valid") and bool(snapshot.call("is_valid")) and snapshot.has_method("get_effects"):
		for effect in snapshot.call("get_effects"):
			var level := int(effect.get("level", 0))
			match str(effect.get("effect_id", "")):
				"bubble_shield":
					_bubble_level = level
				"spike_plate":
					_spike_plate_level = level
				"coin_magnet":
					_magnet_level = level
				"regret_flip":
					_regret_level = level
				"gravity_anchor":
					_anchor_level = level
	reset()

## Starts a fresh run: the bubble is ready, timers are cleared.
func reset() -> void:
	_key_used = false
	_bubble_recharge_left = 0
	_invulnerable_left = 0
	_pop_ticks_left = 0
	_spike_immune_left = 0
	_regret_window_left = 0
	_regret_used = false
	_regret_flash_left = 0
	_anchor_glide_left = 0
	_anchor_recharge_left = 0

func has_any() -> bool:
	return _bubble_level > 0 or _spike_plate_level > 0 or _magnet_level > 0 or _regret_level > 0 or _anchor_level > 0 or not _key_id.is_empty()

## Advances every timer by one physics tick. Call once per tick after hazards
## were resolved, so a window lasts exactly its configured number of ticks.
func tick() -> void:
	if _bubble_recharge_left > 0:
		_bubble_recharge_left -= 1
	if _invulnerable_left > 0:
		_invulnerable_left -= 1
	if _pop_ticks_left > 0:
		_pop_ticks_left -= 1
	if _spike_immune_left > 0:
		_spike_immune_left -= 1
	if _regret_window_left > 0:
		_regret_window_left -= 1
	if _regret_flash_left > 0:
		_regret_flash_left -= 1
	if _anchor_glide_left > 0:
		_anchor_glide_left -= 1
		if _anchor_glide_left == 0:
			_anchor_recharge_left = ANCHOR_RECHARGE_TICKS[_anchor_level - 1]
	elif _anchor_recharge_left > 0:
		_anchor_recharge_left -= 1

## The runner flipped gravity. Starts the spike plate window and opens the
## regret window of this flight.
func on_flip() -> void:
	if _spike_plate_level > 0:
		_spike_immune_left = SPIKE_PLATE_TICKS[_spike_plate_level - 1]
	if _regret_level > 0:
		_regret_window_left = REGRET_WINDOW_TICKS[_regret_level - 1]
		_regret_used = false

## The runner touched a surface again: the flight is over, so is the window.
func on_land() -> void:
	_regret_window_left = 0

## True while a second flip press may still reverse the current flip: the
## regret boots are on, this flight has not been reversed yet, the window of
## the first part of the flight is open and no anchor glide is running.
func can_reverse_flip() -> bool:
	return _regret_level > 0 and not _regret_used and _regret_window_left > 0 and _anchor_glide_left <= 0

## Spends the reverse of this flight. Returns false when it is not allowed.
func consume_reverse_flip() -> bool:
	if not can_reverse_flip():
		return false
	_regret_used = true
	_regret_window_left = 0
	_regret_flash_left = REGRET_FLASH_TICKS
	return true

## 0..1 progress of the reverse ring, or -1 when it is not shown.
func regret_flash_progress() -> float:
	if _regret_flash_left <= 0:
		return -1.0
	return 1.0 - float(_regret_flash_left) / float(REGRET_FLASH_TICKS)

func has_anchor() -> bool:
	return _anchor_level > 0

func anchor_ready() -> bool:
	return _anchor_level > 0 and _anchor_glide_left <= 0 and _anchor_recharge_left <= 0

## Starts the glide when the anchor is ready. Returns true when it started.
func activate_anchor() -> bool:
	if not anchor_ready():
		return false
	_anchor_glide_left = ANCHOR_GLIDE_TICKS
	return true

## True while the runner is locked to the middle of the course.
func is_anchor_gliding() -> bool:
	return _anchor_glide_left > 0

## A lethal hazard touched the runner. Returns true when an effect absorbed it
## (the run continues). The bubble shield consumes itself, then keeps the
## runner invulnerable for a moment so the same hazard cannot kill it on the
## next tick.
func on_lethal_contact(guarded_by_key: bool = false) -> bool:
	if _invulnerable_left > 0:
		return true
	if guarded_by_key and key_guard_ready():
		_key_used = true
		_invulnerable_left = BUBBLE_INVULNERABLE_TICKS
		_pop_ticks_left = BUBBLE_POP_TICKS
		return true
	if _bubble_level > 0 and _bubble_recharge_left == 0:
		_bubble_recharge_left = BUBBLE_RECHARGE_TICKS[_bubble_level - 1]
		_invulnerable_left = BUBBLE_INVULNERABLE_TICKS
		_pop_ticks_left = BUBBLE_POP_TICKS
		return true
	return false

func is_invulnerable() -> bool:
	return _invulnerable_left > 0

func is_spike_immune() -> bool:
	return _spike_immune_left > 0

## 0 when no magnet is equipped.
func coin_pickup_radius() -> float:
	return MAGNET_RADIUS[_magnet_level - 1] if _magnet_level > 0 else 0.0

func bubble_ready() -> bool:
	return _bubble_level > 0 and _bubble_recharge_left == 0

## 0..1 pop progress while the pop animation runs, otherwise -1.
func pop_progress() -> float:
	if _pop_ticks_left <= 0:
		return -1.0
	return 1.0 - float(_pop_ticks_left) / float(BUBBLE_POP_TICKS)

## HUD rows in slot order: {effect_id, level, charge 0..1, ready, active}.
## charge is 1 when ready and fills up while the item recharges; items without
## a recharge (spike plate, magnet) are always full and only light up while
## active.
func get_hud_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if _bubble_level > 0:
		var total := float(BUBBLE_RECHARGE_TICKS[_bubble_level - 1])
		entries.append({
			"effect_id": "bubble_shield",
			"level": _bubble_level,
			"charge": 1.0 - float(_bubble_recharge_left) / total,
			"ready": _bubble_recharge_left == 0,
			"active": _invulnerable_left > 0,
		})
	if _spike_plate_level > 0:
		var window := float(SPIKE_PLATE_TICKS[_spike_plate_level - 1])
		entries.append({
			"effect_id": "spike_plate",
			"level": _spike_plate_level,
			"charge": 1.0 if _spike_immune_left <= 0 else float(_spike_immune_left) / window,
			"ready": true,
			"active": _spike_immune_left > 0,
		})
	if _regret_level > 0:
		var regret_window := float(REGRET_WINDOW_TICKS[_regret_level - 1])
		entries.append({
			"effect_id": "regret_flip",
			"level": _regret_level,
			"charge": 1.0 if _regret_window_left <= 0 else float(_regret_window_left) / regret_window,
			"ready": true,
			"active": can_reverse_flip(),
		})
	if _magnet_level > 0:
		entries.append({"effect_id": "coin_magnet", "level": _magnet_level, "charge": 1.0, "ready": true, "active": false})
	if _anchor_level > 0:
		var charge := 1.0
		if _anchor_glide_left > 0:
			charge = float(_anchor_glide_left) / float(ANCHOR_GLIDE_TICKS)
		elif _anchor_recharge_left > 0:
			charge = 1.0 - float(_anchor_recharge_left) / float(ANCHOR_RECHARGE_TICKS[_anchor_level - 1])
		entries.append({
			"effect_id": "gravity_anchor",
			"level": _anchor_level,
			"charge": charge,
			"ready": anchor_ready(),
			"active": _anchor_glide_left > 0,
		})
	var key_entry := get_key_hud_entry()
	if not key_entry.is_empty():
		entries.append(key_entry)
	return entries

## Sets the stage's biome key (call after configure). "" turns it off.
func configure_key(key_id: String) -> void:
	_key_id = key_id
	_key_used = false

func get_key_id() -> String:
	return _key_id

## True while a guarding key (ice picks, heat shield) still has its one save.
func key_guard_ready() -> bool:
	return _key_id in ["ice_picks", "heat_shield"] and not _key_used

## HUD row for the key, or an empty Dictionary without one. The lantern works
## all the time; the guarding keys empty once their save is used.
func get_key_hud_entry() -> Dictionary:
	if _key_id.is_empty():
		return {}
	if _key_id == "lantern":
		return {"effect_id": _key_id, "level": 1, "charge": 1.0, "ready": true, "active": true}
	return {"effect_id": _key_id, "level": 1, "charge": 0.0 if _key_used else 1.0, "ready": not _key_used, "active": _invulnerable_left > 0 and _key_used}
