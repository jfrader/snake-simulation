extends Line2D

const HEAD_COLOR := Color(0.85, 1.0, 0.45)
# Eating is the twist: every segment adds girth and drag. The penalty is spent
# as a fraction of the level's base speed so it is felt at every difficulty, and
# floored so a maxed-out snake still moves.
const MIN_SPEED_RATIO := 0.4
const DRAG_PER_SEGMENT := 0.02

var start_speed = 300.0
var speed = start_speed
var direction = Vector2.RIGHT
var head_area: Area2D
var collision_poly: CollisionPolygon2D
var head_marker: Polygon2D
# The game root, injected by Scene. Used instead of get_tree().current_scene so
# the scene keeps working when it is instanced inside another scene.
var game = null
var time = 0.0
var wave_amplitude = 1.0
var wave_frequency = 20.0

var arena_bounds: Rect2
var is_invulnerable = false
var blink_timer = 0.0
var invulnerability_duration = 2.0
var current_invulnerability_timer = 0.0

func _ready():
	self.hide()
	var viewport_size = get_viewport_rect().size
	var first_position = Vector2(viewport_size.x / 2, viewport_size.y / 2)
	add_point(first_position)
	for i in range(9):
		add_point(Vector2(first_position.x - i * 5, first_position.y))

	self.width = 8
	self.default_color = Color.LAWN_GREEN
	self.begin_cap_mode = Line2D.LINE_CAP_ROUND
	self.end_cap_mode = Line2D.LINE_CAP_ROUND
	
	create_head_collision()
	adjust_width_curve()

func shrink_and_respawn(bounds: Rect2):
	arena_bounds = bounds
	var center = bounds.position + bounds.size / 2
	
	clear_points()
	direction = Vector2.RIGHT
	add_point(center)
	for i in range(9):
		add_point(Vector2(center.x - i * 5, center.y))
	
	self.width = 8
	adjust_head_collision()
	adjust_width_curve()
	
	is_invulnerable = true
	current_invulnerability_timer = invulnerability_duration
	blink_timer = 0.0

func grow_width(size):
	if self.width < 16:
		self.width += 0.05 * size
		adjust_head_collision()

func create_head_collision():
	head_area = Area2D.new()
	head_area.name = "HeadArea"
	add_child(head_area)
	collision_poly = CollisionPolygon2D.new()
	collision_poly.name = "CollisionPolygon2D"
	head_area.add_child(collision_poly)
	# The body is symmetric, so the head carries a forward marker: without it
	# you cannot tell which end leads or which way you are travelling.
	head_marker = Polygon2D.new()
	head_marker.name = "HeadMarker"
	head_marker.color = HEAD_COLOR
	head_area.add_child(head_marker)
	adjust_head_collision()
	
func adjust_head_collision():
	var head_polygon = PackedVector2Array([
		Vector2((-width/2) - 1, 0),
		Vector2(0, (-width/2) - 1),
		Vector2((width/2) + 1, 0),
		Vector2(0, (width/2) + 1)
	])
	collision_poly.polygon = head_polygon
	if head_marker:
		var reach = (width / 2.0) + 2.0
		head_marker.polygon = PackedVector2Array([
			Vector2(reach * 1.35, 0),
			Vector2(-reach * 0.45, reach),
			Vector2(-reach * 0.45, -reach)
		])

func _process(delta):
	if not game or game.state != game.State.PLAYING:
		return
	if game.is_paused:
		return

	if is_invulnerable:
		current_invulnerability_timer -= delta
		blink_timer += delta
		if blink_timer > 0.1:
			self.modulate.a = 0.3 if self.modulate.a >= 0.9 else 1.0
			blink_timer = 0.0
		if current_invulnerability_timer <= 0:
			is_invulnerable = false
			self.modulate.a = 1.0

	time += delta
	
	var head_position = points[0] + direction * speed * delta
	set_point_position(0, head_position)

	for i in range(1, points.size()):
		var prev_position = points[i - 1]
		var current_position = points[i]
		
		var vibration_direction = Vector2(direction.y, -direction.x).normalized()
		var offset = vibration_direction * (sin(time * wave_frequency + i * 0.1) * wave_amplitude)
		
		set_point_position(i, current_position.lerp(prev_position + offset, delta * (speed/10.0)))

	update_head_collision()

	if arena_bounds.size.x > 0:
		if head_position.x < arena_bounds.position.x or head_position.x > arena_bounds.end.x:
			direction.x *= -1
			head_position.x = clamp(head_position.x, arena_bounds.position.x, arena_bounds.end.x)
			set_point_position(0, head_position)
		if head_position.y < arena_bounds.position.y or head_position.y > arena_bounds.end.y:
			direction.y *= -1
			head_position.y = clamp(head_position.y, arena_bounds.position.y, arena_bounds.end.y)
			set_point_position(0, head_position)

func update_head_collision():
	if head_area and collision_poly:
		head_area.global_position = points[0]
		head_area.global_rotation = direction.angle()
	else:
		push_error("Head area or collision polygon not found!")

func _input(event):
	if not game or game.state != game.State.PLAYING:
		return
	if game.is_paused:
		return

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_UP and direction != Vector2.DOWN:
			direction = Vector2.UP
		elif event.keycode == KEY_DOWN and direction != Vector2.UP:
			direction = Vector2.DOWN
		elif event.keycode == KEY_LEFT and direction != Vector2.RIGHT:
			direction = Vector2.LEFT
		elif event.keycode == KEY_RIGHT and direction != Vector2.LEFT:
			direction = Vector2.RIGHT

func adjust_width_curve():
	if !width_curve:
		width_curve = Curve.new()

	var total_points = points.size()
	if total_points == 0:
		return
	var head_portion = 0.12 
	var tail_portion = 0.1
	var body_portion = 1.0 - head_portion - tail_portion

	var total_length = 0.0
	for i in range(1, total_points):
		total_length += points[i - 1].distance_to(points[i])

	var max_head_length_pixels = 60
	var head_length_pixels = min(total_length * head_portion, max_head_length_pixels)
	var head_proportion = head_length_pixels / total_length if total_length > 0 else 0

	while width_curve.get_point_count() > 0:
		width_curve.remove_point(0)

	width_curve.add_point(Vector2(0, 0.8))
	width_curve.add_point(Vector2(head_proportion * 0.25, 0.9))
	width_curve.add_point(Vector2(head_proportion * 0.5, 1))
	width_curve.add_point(Vector2(head_proportion * 0.75, 0.9))
	width_curve.add_point(Vector2(head_proportion, 0.7))

	var body_start = head_proportion
	var body_end = body_start + (body_portion * (1 - head_proportion))
	width_curve.add_point(Vector2(body_start, 0.7))
	width_curve.add_point(Vector2(body_start + (body_end - body_start) / 2, 0.65))
	width_curve.add_point(Vector2(body_end, 0.25))

	var tail_start = body_end
	var tail_end = 1.0
	width_curve.add_point(Vector2(tail_start, 0.2))
	width_curve.add_point(Vector2(tail_end, 0.143))

func grow(times: int = 1):
	for i in range(times):
		if points.size() > 1:
			var tail_position = points[points.size() - 1]
			var second_last_position = points[points.size() - 2]
			var growth_direction = tail_position - second_last_position
			var new_tail_position = tail_position + growth_direction.normalized() * width
			add_point(new_tail_position)
		elif points.size() == 1:
			var new_tail_position = points[0] - direction.normalized() * width
			add_point(new_tail_position)
		
		grow_width(get_point_count())
	
	speed = maxf(start_speed * MIN_SPEED_RATIO, speed - start_speed * DRAG_PER_SEGMENT * times)
	adjust_width_curve()

func get_slowness() -> float:
	if start_speed <= 0.0:
		return 0.0
	return clampf(1.0 - speed / start_speed, 0.0, 1.0)
