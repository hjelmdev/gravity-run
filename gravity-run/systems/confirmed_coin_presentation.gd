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

## A host-verified contact starts the shared coin effect before claim arbitration.
## This route changes presentation only; the service ledger remains authoritative.
func present_contact(presentation: Dictionary, course_presentation: Node) -> bool:
	var entity_id := str(presentation.get("entity_id", ""))
	var round_id := str(presentation.get("round_id", ""))
	var presentation_id := str(presentation.get("presentation_id", ""))
	var request_id := str(presentation.get("request_id", ""))
	var incarnation := int(presentation.get("incarnation", -1))
	if entity_id.is_empty() or round_id.is_empty() or presentation_id.is_empty() or request_id.is_empty() or incarnation < 1 or not is_instance_valid(course_presentation):
		return false
	return bool(course_presentation.call("present_verified_coin_contact", presentation_id, entity_id, round_id, incarnation, request_id))

func cancel_contact(presentation: Dictionary, course_presentation: Node) -> bool:
	var entity_id := str(presentation.get("entity_id", ""))
	var round_id := str(presentation.get("round_id", ""))
	var presentation_id := str(presentation.get("presentation_id", ""))
	var incarnation := int(presentation.get("incarnation", -1))
	if entity_id.is_empty() or round_id.is_empty() or presentation_id.is_empty() or incarnation < 1 or not is_instance_valid(course_presentation):
		return false
	return bool(course_presentation.call("cancel_verified_coin_contact", presentation_id, entity_id, round_id, incarnation))
