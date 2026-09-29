extends Camera2D
class_name RunnerCamera
## One world-to-screen transform for all modes. Follow an already sampled pose.

var view_size := Vector2(960.0, 540.0)
var lead := 180.0
var left := 0.0

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
	left = render_position.x - lead
	if clamp_left:
		left = maxf(left, 0.0)
	position = Vector2(left + view_size.x * 0.5, view_size.y * 0.5)
	force_update_scroll()
