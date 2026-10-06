extends RefCounted
class_name SfxAudibilityRules
## Shared world-space sound culling for singleplayer and multiplayer presentation.

const WORLD_MARGIN := 64.0
const EDGE_EPSILON := 0.001

static func is_world_x_audible(world_x: float, camera_left: float, viewport_width: float, margin: float = WORLD_MARGIN) -> bool:
	if not is_finite(world_x) or not is_finite(camera_left) or not is_finite(viewport_width) or viewport_width <= 0.0:
		return false
	var safe_margin := maxf(margin, 0.0)
	return world_x >= camera_left - safe_margin - EDGE_EPSILON and world_x <= camera_left + viewport_width + safe_margin + EDGE_EPSILON
