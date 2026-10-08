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

var _bubble_level := 0
var _bubble_recharge_left := 0
var _invulnerable_left := 0
var _pop_ticks_left := 0
var _spike_plate_level := 0
var _spike_immune_left := 0
var _magnet_level := 0

## Reads the effect entries of a RunLoadoutSnapshot. Null or invalid snapshots
## leave every effect off.
func configure(snapshot: Resource) -> void:
	_bubble_level = 0
	_spike_plate_level = 0
	_magnet_level = 0
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
	reset()

## Starts a fresh run: the bubble is ready, timers are cleared.
func reset() -> void:
	_bubble_recharge_left = 0
	_invulnerable_left = 0
	_pop_ticks_left = 0
	_spike_immune_left = 0

func has_any() -> bool:
	return _bubble_level > 0 or _spike_plate_level > 0 or _magnet_level > 0

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

## The runner flipped gravity. Starts the spike plate window.
func on_flip() -> void:
	if _spike_plate_level > 0:
		_spike_immune_left = SPIKE_PLATE_TICKS[_spike_plate_level - 1]

## A lethal hazard touched the runner. Returns true when an effect absorbed it
## (the run continues). The bubble shield consumes itself, then keeps the
## runner invulnerable for a moment so the same hazard cannot kill it on the
## next tick.
func on_lethal_contact() -> bool:
	if _invulnerable_left > 0:
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
	if _magnet_level > 0:
		entries.append({"effect_id": "coin_magnet", "level": _magnet_level, "charge": 1.0, "ready": true, "active": false})
	return entries
