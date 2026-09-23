extends Node

var speed_multiplier := 1.0
var speed_boost_time := 0.0
var spike_immunity_time := 0.0

func activate_speed_boost(multiplier: float, duration: float) -> void:
	speed_multiplier = maxf(1.0, multiplier)
	speed_boost_time = maxf(0.0, duration)

func activate_spike_immunity(duration: float) -> void:
	spike_immunity_time = maxf(0.0, duration)

func tick(delta: float) -> void:
	if speed_boost_time > 0.0:
		speed_boost_time = maxf(0.0, speed_boost_time - delta)
		if speed_boost_time == 0.0:
			speed_multiplier = 1.0
	if spike_immunity_time > 0.0:
		spike_immunity_time = maxf(0.0, spike_immunity_time - delta)

func clear_effects() -> void:
	speed_multiplier = 1.0
	speed_boost_time = 0.0
	spike_immunity_time = 0.0

func get_speed_multiplier() -> float:
	return speed_multiplier

func is_spike_immune() -> bool:
	return spike_immunity_time > 0.0
