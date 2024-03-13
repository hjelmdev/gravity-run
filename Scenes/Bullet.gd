extends Area2D


var speed = 700
var direction = 1

onready var sprite = $Sprite

func set_bullet_direction(dir):
	direction = dir
	

func _ready():
	if direction < 0:
		sprite.rotate(deg2rad(180))	

func _physics_process(delta):

	position += transform.x * speed * delta * direction
	if not get_node("VisibilityNotifier2D").is_on_screen():
		queue_free()
	
func _on_Bullet_body_entered(body):
	
	if body.is_in_group("destructible") or body.is_in_group("danger"):
		body.death()
		#body.queue_free()
	if !body.is_in_group("player"):
		queue_free()
