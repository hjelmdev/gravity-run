extends SceneTree
## The daily stage: one seed per UTC day for everyone, kept for retries, and
## dropped by a normal run.

const ChallengeServiceScript := preload("res://systems/challenge_service.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var a := ChallengeServiceScript.daily_seed("2026-10-09")
	_check(a == ChallengeServiceScript.daily_seed("2026-10-09"), "the same day gives the same seed")
	_check(a != ChallengeServiceScript.daily_seed("2026-10-10"), "the next day gives another seed")
	var in_range := true
	for day in range(1, 29):
		var value := ChallengeServiceScript.daily_seed("2026-02-%02d" % day)
		in_range = in_range and value >= ChallengeServiceScript.MIN_CHALLENGE_SEED and value <= ChallengeServiceScript.MAX_CHALLENGE_SEED
	_check(in_range, "daily seeds are inside the challenge seed range")
	var service: Node = ChallengeServiceScript.new()
	root.add_child(service)
	await process_frame
	service.start_daily()
	var first := int(service.begin_run())
	var retry := int(service.begin_run())
	_check(first == ChallengeServiceScript.daily_seed() and retry == first and bool(service.repeatable_seed), "the daily stage keeps today's seed for retries")
	service.stop_daily()
	service.begin_run()
	_check(not bool(service.repeatable_seed), "a normal run after the daily stage gets a random seed")
	service.start_daily()
	service.clear_challenge()
	_check(not bool(service.daily_active), "clearing the challenge also leaves the daily stage")
	service.queue_free()
	await process_frame
	print("DAILY_STAGE_TEST failures=%d" % failures)
	quit(0 if failures == 0 else 1)

func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		failures += 1
		print("FAIL ", label)
