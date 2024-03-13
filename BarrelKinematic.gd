extends KinematicBody2D

var vel : Vector2 = Vector2(0,1)
# Declare member variables here. Examples:
# var a = 2
# var b = "text"


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	vel.y += 9*delta
	move_and_collide(vel)

func death():
	print("test")
	$AnimationPlayer.play("New Anim")
	#$CollisionShape2D.set_deferred("disabled", true)
	yield($AnimationPlayer, "animation_finished")
	queue_free()
