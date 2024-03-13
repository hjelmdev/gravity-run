extends KinematicBody2D

export (PackedScene) var Bullet
# Declare member variables here. Examples:
# var a = 2
# var b = "text"
var score : int = 0
# physics
var speed : int = 400
var jumpForce : int = 350
#var gravity : int = 800

var gravity_direction : Vector2 = Vector2.DOWN
var gravity_force : int = 800
var vel : Vector2 = Vector2()
var velocity = Vector2.ZERO
var grounded : bool = false

var canChangeGravityMidAir : bool = true

var SNAP_DIRECTION = Vector2.DOWN
var SNAP_LENGTH = 32.0
var snap_vector = SNAP_DIRECTION * SNAP_LENGTH

var grav_force = 400.0
var grav_dir : int = 1
var gravity = gravity_force * grav_dir
# components
onready var sprite = $Sprite

var gravityOn : bool = true

#bullet




# Called when the node enters the scene tree for the first time.
func _ready():
	pass
	#vel.y = gravity_force
	# stats
	

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass

func _physics_process (delta):
	
	if not get_node("VisibilityNotifier2D").is_on_screen():
		respawn()
	
	#reset horizontal velocity
	#vel.x = 0
	velocity.x = speed
	
	#movement
	if Input.is_action_pressed("move_left"):
		velocity.x -= speed * 2
	#	vel.x -= speed
	if Input.is_action_pressed("move_right"):
		velocity.x += speed 
		
	if Input.is_action_just_pressed("shoot"):
		shoot()
		
		
		# gravity alternation
	if Input.is_action_just_pressed("gravity_off"):
		#Physics2DServer.area_set_param(get_world_2d().space, Physics2DServer.AREA_PARAM_GRAVITY_VECTOR, gravity_direction)
		if is_on_floor():
			gravity_direction = Vector2.UP
			gravityOn = false
			SNAP_DIRECTION = Vector2.UP
			canChangeGravityMidAir = true
		elif canChangeGravityMidAir && gravityOn:
			gravityOn = false
			SNAP_DIRECTION = Vector2.UP
			gravity_direction = Vector2.UP
			canChangeGravityMidAir = false



	if Input.is_action_just_pressed("gravity_on"):
		if is_on_floor():
			gravityOn = true
			SNAP_DIRECTION = Vector2.DOWN
			gravity_direction = Vector2.DOWN
			canChangeGravityMidAir = true
		elif canChangeGravityMidAir && !gravityOn:
			gravityOn = true
			gravity_direction = Vector2.DOWN
			SNAP_DIRECTION = Vector2.DOWN
			canChangeGravityMidAir = false

	#	vel.x += speed
	#print(is_on_floor())
	#applying the velocity
	#if(is_on_floor()):
	
	#print(getSnapVector())
#	print(velocity.y)
#	print(gravityOn)
#	print(gravity_direction)
#	print("grav_force: ", delta)
#	print("tak: ", is_on_floor())
	if is_on_floor():
		velocity.y += (gravity_force * gravity_direction.y) * delta
	else:
		velocity.y = (gravity_force * gravity_direction.y)
	velocity.y = move_and_slide_with_snap(velocity, getSnapVector(), getSnapVector()*-1, true).y
	
	
	
	#velocity.y = move_and_slide(velocity, Vector2.UP, true).y
#	velocity =  gravity_force * gravity_direction
	#print(grav_dir)
	
	#vel.y = move_and_slide(vel, Vector2.UP, true).y
	#vel =  gravity_force * gravity_direction
#	print (vel.y)
#	if(is_on_floor()):
#		vel.y = 0
#	else:
#		vel =  gravity_force * gravity_direction
	
#	var slides = get_slide_count()
#	if(slides):
#		slope(slides)


	
	


	damage()	
	#sprite direction
	if velocity.x < 0:
		sprite.flip_h = true
		if sign($Muzzle.position.x) == 1:
			$Muzzle.position.x *= -1
	elif velocity.x > 0:
		sprite.flip_h = false
		if sign($Muzzle.position.x) == -1:
			$Muzzle.position.x *= -1
	if gravityOn:
		scale.y = 1
	elif !gravityOn:
		scale.y = -1
#	if velocity.y > 0:
#		scale.y = 1
#	elif velocity.y < 0:
#		scale.y = -1


func shoot():
	var canShoot = get_tree().get_nodes_in_group("bullet").size() < 2 && $Timer.is_stopped()
	if !canShoot:
		return
	
	var b = Bullet.instance()
	if velocity.x > 0:
		#b.direction = 1
		b.set_bullet_direction(1)
	if velocity.x < 0:
		b.set_bullet_direction(-1)
		#b.direction *= -1
		#var kulan = b.get_node("Sprite")
		#kulan.rotate(deg2rad(180))
		
	owner.add_child(b)
	b.transform = $Muzzle.global_transform
	$Timer.start()

func damage() -> void:
	for i in get_slide_count():
		var collision = get_slide_collision(i)
		if collision.collider.is_in_group("danger"):
			respawn()

func respawn() -> void:
	position.x = -240
	position.y = 384

func slope(slides: int):
	for i in slides:
		var touched = get_slide_collision(i)
		if is_on_floor() && touched.normal.y < 1.0 && vel.x != 0.0:
			vel.y = touched.normal.y

func getSnapVector():
	return SNAP_DIRECTION * SNAP_LENGTH


func _on_Danger_my_signal():
	print("det här är kuuul")
