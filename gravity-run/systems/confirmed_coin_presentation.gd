extends RefCounted
class_name ConfirmedCoinPresentation

## Routes only live, confirmed collect commits to the existing coin scene's
## visual collection animation. Ledger application and account awards remain
## owned by the world/service.
func present(commit: Dictionary, apply_result: String, course_presentation: Node) -> bool:
	if str(commit.get("action", "")) != "collect" or apply_result not in ["applied", "duplicate"]:
		return false
	var entity_id := str(commit.get("entity_id", ""))
	var commit_id := str(commit.get("commit_id", ""))
	if entity_id.is_empty() or commit_id.is_empty() or not is_instance_valid(course_presentation):
		return false
	return bool(course_presentation.call("play_confirmed_coin_collection", entity_id, commit_id, str(commit.get("request_id", "")), str(commit.get("round_id", "")), int(commit.get("incarnation", -1))))
