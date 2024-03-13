extends TileMap

signal my_signal

# Declare member variables here. Examples:
# var a = 2
# var b = "text"


# Called when the node enters the scene tree for the first time.
func _ready():
	pass

func stuff():
	emit_signal("my_signal")

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	for i in get_slide_count():
		var collision = get_slide_collision(i)
		if collision.collider.is_in_group("danger"):
			stuff();
#	for i in get_slide_count():
#		var collision = get_slide_collision(i)
