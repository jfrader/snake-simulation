extends Node2D

var score = 0
var start_speed = 300.0
var speed = start_speed
var direction = Vector2.RIGHT
var time = 0.0  # Time counter for the wave effect
var wave_amplitude = 1.0  # How much the points will move up and down
var wave_frequency = 20.0  # Frequency of the wave

@onready var line: Line2D = $Line2D
@onready var area: Area2D = $Line2D/Area2D
@onready var collision: CollisionPolygon2D = $Line2D/Area2D/CollisionPolygon2D
@onready var camera: Camera2D = get_node_or_null("/root/Game/Camera2D")
@onready var score_label: Label = get_node_or_null("/root/Game/Camera2D/ScoreLabel")

func _on_area_2d_area_entered(colliding_area: Area2D):
	var food = colliding_area.get_owner()
	var new_score: int = food.score if food else null
	if new_score:
		self.grow(new_score)
		food.respawn()
		score_label.text = str(score)

func _ready():
	line.hide()
	var start_position = self.transform.get_origin()
	line.add_point(start_position)

	for i in range(9):
		line.add_point(Vector2(start_position.x + i * 5, start_position.y))

	line.width = 8
	line.default_color = Color.LAWN_GREEN
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	
	adjust_head_collision()
	adjust_width_curve()

	line.show()

func _process(delta):
	time += delta

	var camera_viewport_size = get_viewport().get_visible_rect().size / camera.zoom
	var camera_position = camera.global_position

	# Calculate new head position, constrained by camera view
	var new_head_position = line.points[0] + direction * speed * delta
	
	# Constrain the snake's head to within the camera's view
	var left_bound = camera_position.x - camera_viewport_size.x / 2
	var right_bound = camera_position.x + camera_viewport_size.x / 2
	var top_bound = camera_position.y - camera_viewport_size.y / 2
	var bottom_bound = camera_position.y + camera_viewport_size.y / 2

	new_head_position.x = clamp(new_head_position.x, left_bound, right_bound)
	new_head_position.y = clamp(new_head_position.y, top_bound, bottom_bound)

	line.points[0] = new_head_position

	for i in range(1, line.points.size()):
		var prev_position = line.points[i - 1]
		var current_position = line.points[i]
		var vibration_direction = Vector2(direction.y, -direction.x).normalized()
		var offset = vibration_direction * (sin(time * wave_frequency + i * 0.1) * wave_amplitude)
		line.points[i] = current_position.lerp(prev_position + offset, delta * (speed/10.0))

	update_head_collision()

	# Here's where you decide how the snake should react at the edges:
	# If you want the snake to bounce off the edges:
	if new_head_position.x <= left_bound or new_head_position.x >= right_bound:
		direction.x *= -1
	if new_head_position.y <= top_bound or new_head_position.y >= bottom_bound:
		direction.y *= -1

	# Move camera with snake (optional, adjust as needed)
	# camera.global_position = line.points[0] + Vector2(camera_viewport_size.x / 2, camera_viewport_size.y / 2)
	
func grow_width(size):
	if line.width < 16:
		line.width += 0.05 * size
		adjust_head_collision()
	
func adjust_head_collision():
	var head_polygon = PackedVector2Array([
		Vector2((-line.width/2) - 1, 0),
		Vector2(0, (-line.width/2) - 1),
		Vector2((line.width/2) + 1, 0),
		Vector2(0, (line.width/2) + 1)
	])

	collision.polygon = head_polygon

func update_head_collision():
	if area and collision:
		area.global_position = line.points[0]
		area.global_rotation = direction.angle()
	else:
		push_error("Head area or collision polygon not found!")

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_UP and direction != Vector2.DOWN:
			direction = Vector2.UP
		elif event.keycode == KEY_DOWN and direction != Vector2.UP:
			direction = Vector2.DOWN
		elif event.keycode == KEY_LEFT and direction != Vector2.RIGHT:
			direction = Vector2.LEFT
		elif event.keycode == KEY_RIGHT and direction != Vector2.LEFT:
			direction = Vector2.RIGHT

		if event.keycode == KEY_SPACE:
			if speed == 5:
				speed = start_speed
			else:
				speed = 5

func adjust_width_curve():
	if !line.width_curve:
		line.width_curve = Curve.new()

	var total_points = line.points.size()
	var head_portion = 0.12 
	var tail_portion = 0.1
	var body_portion = 1.0 - head_portion - tail_portion

	var total_length = 0.0
	for i in range(1, total_points):
		total_length += line.points[i - 1].distance_to(line.points[i])

	var max_head_length_pixels = 60

	var head_length_pixels = min(total_length * head_portion, max_head_length_pixels)

	var head_proportion = head_length_pixels / total_length if total_length > 0 else 0

	while line.width_curve.get_point_count() > 0:
		line.width_curve.remove_point(0)

	line.width_curve.add_point(Vector2(0, 0.8))
	line.width_curve.add_point(Vector2(head_proportion * 0.25, 0.9))
	line.width_curve.add_point(Vector2(head_proportion * 0.5, 1))
	line.width_curve.add_point(Vector2(head_proportion * 0.75, 0.9))
	line.width_curve.add_point(Vector2(head_proportion, 0.7))

	var body_start = head_proportion
	var body_end = body_start + (body_portion * (1 - head_proportion))  # Adjust body portion
	line.width_curve.add_point(Vector2(body_start, 0.7))
	line.width_curve.add_point(Vector2(body_start + (body_end - body_start) / 2, 0.65))
	line.width_curve.add_point(Vector2(body_end, 0.25))

	var tail_start = body_end
	var tail_end = 1.0
	line.width_curve.add_point(Vector2(tail_start, 0.2))
	line.width_curve.add_point(Vector2(tail_end, 0.143))

func grow(times: int = 1):
	for i in range(times):
		if line.points.size() > 1:
			var tail_position = line.points[line.points.size() - 1]
			var second_last_position = line.points[line.points.size() - 2]
			var growth_direction = tail_position - second_last_position
			var new_tail_position = tail_position + growth_direction.normalized() * line.width
			line.add_point(new_tail_position)
		elif line.points.size() == 1:
			var new_tail_position = line.points[0] - direction.normalized() * line.width
			line.add_point(new_tail_position)
			
		if speed > 100:
			speed -= 2
			
		grow_width(line.get_point_count())
		
	score += times
	adjust_width_curve()
