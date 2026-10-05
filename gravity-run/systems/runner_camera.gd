extends Camera2D
class_name RunnerCamera
## One world-to-screen transform for all modes. Follow an already sampled pose.

var view_size := Vector2(960.0, 540.0)
const PLAYER_ANCHOR_X := 180.0
var lead := PLAYER_ANCHOR_X
var left := 0.0

static func camera_left_for_world_x(world_x: float) -> float:
	return world_x - PLAYER_ANCHOR_X

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	position_smoothing_enabled = false
	enabled = true
	make_current()

func configure(world_view_size: Vector2, player_lead: float, view_scale: float = 1.0) -> void:
	view_size = world_view_size
	lead = player_lead
	zoom = Vector2.ONE * maxf(view_scale, 0.01)

func follow(render_position: Vector2, clamp_left: bool = false) -> void:
	left = camera_left_for_world_x(render_position.x) if is_equal_approx(lead, PLAYER_ANCHOR_X) else render_position.x - lead
	if clamp_left:
		left = maxf(left, 0.0)
	position = Vector2(left + view_size.x * 0.5, view_size.y * 0.5)
	force_update_scroll()
