extends Line2D

# The head keeps its rounded shape. It reads as a snake head from small organic
# detail rather than a marker: eyes, and a tongue that flicks forward now and then.
const EYE_COLOR := Color(0.06, 0.07, 0.06)
const TONGUE_COLOR := Color(0.95, 0.36, 0.44)
const TONGUE_INTERVAL := Vector2(1.1, 3.4)
const TONGUE_FLICK_TIME := 0.24
const TONGUE_REACH := 0.85
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
var eye_left: Polygon2D
var eye_right: Polygon2D
var tongue_root: Node2D
var tongue_stem: Line2D
var tongue_prong_left: Line2D
var tongue_prong_right: Line2D
var tongue_clock := 0.0
var tongue_next := 0.0
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
	
	eye_left = _make_dot(EYE_COLOR)
	eye_right = _make_dot(EYE_COLOR)
	head_area.add_child(eye_left)
	head_area.add_child(eye_right)
	
	tongue_root = Node2D.new()
	tongue_root.name = "Tongue"
	tongue_root.hide()
	head_area.add_child(tongue_root)
	tongue_stem = _make_tongue_line()
	tongue_prong_left = _make_tongue_line()
	tongue_prong_right = _make_tongue_line()
	tongue_root.add_child(tongue_stem)
	tongue_root.add_child(tongue_prong_left)
	tongue_root.add_child(tongue_prong_right)
	_schedule_tongue()
	
	adjust_head_collision()

func _make_dot(color: Color) -> Polygon2D:
	var dot = Polygon2D.new()
	var points = PackedVector2Array()
	for i in range(8):
		var angle = TAU * i / 8.0
		points.append(Vector2(cos(angle), sin(angle)))
	dot.polygon = points
	dot.color = color
	return dot

func _make_tongue_line() -> Line2D:
	var line = Line2D.new()
	line.default_color = TONGUE_COLOR
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	return line

func _schedule_tongue():
	tongue_next = randf_range(TONGUE_INTERVAL.x, TONGUE_INTERVAL.y)

func adjust_head_collision():
	var head_polygon = PackedVector2Array([
		Vector2((-width/2) - 1, 0),
		Vector2(0, (-width/2) - 1),
		Vector2((width/2) + 1, 0),
		Vector2(0, (width/2) + 1)
	])
	collision_poly.polygon = head_polygon
	if not eye_left:
		return
	# The drawn head is a round cap of about 0.4 * width. Eye centre plus eye
	# radius has to stay inside the body or the eyes sit off it and vanish
	# against the background, so they sit just behind the snout where it widens.
	var eye_x = -width * 0.06
	var eye_y = width * 0.22
	var eye_radius = clampf(width * 0.15, 1.3, 2.4)
	eye_left.position = Vector2(eye_x, -eye_y)
	eye_right.position = Vector2(eye_x, eye_y)
	eye_left.scale = Vector2.ONE * eye_radius
	eye_right.scale = Vector2.ONE * eye_radius
	tongue_stem.width = clampf(width * 0.2, 1.2, 2.6)
	tongue_prong_left.width = clampf(width * 0.16, 1.0, 2.2)
	tongue_prong_right.width = tongue_prong_left.width

func _update_tongue(delta: float):
	if not tongue_root:
		return
	tongue_clock += delta
	if tongue_clock >= tongue_next:
		tongue_clock = 0.0
		_schedule_tongue()
		tongue_root.show()
	
	var progress = tongue_clock / TONGUE_FLICK_TIME
	if not tongue_root.visible:
		return
	if progress > 1.0:
		tongue_root.hide()
		return
	
	# Out and back within the flick window.
	var out = sin(clampf(progress, 0.0, 1.0) * PI)
	var base = width / 2.0
	var tip = base * 0.6 + width * TONGUE_REACH * out
	var fork = width * 0.28 + 1.5
	tongue_stem.points = PackedVector2Array([Vector2(base * 0.5, 0.0), Vector2(tip, 0.0)])
	tongue_prong_left.points = PackedVector2Array([
		Vector2(tip, 0.0), Vector2(tip + fork, -fork * 0.75)
	])
	tongue_prong_right.points = PackedVector2Array([
		Vector2(tip, 0.0), Vector2(tip + fork, fork * 0.75)
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
	_update_tongue(delta)
	
	var head_position = points[0] + direction * speed * delta
	set_point_position(0, head_position)

	for i in range(1, points.size()):
		var prev_position = points[i - 1]
		var current_position = points[i]
		
		var vibration_direction = Vector2(direction.y, -direction.x).normalized()
		var offset = vibration_direction * (sin(time * wave_frequency + i * 0.1) * wave_amplitude)
		
		# The follow factor must never exceed 1, or a point lands past the one
		# ahead of it and the body inverts. It exceeds 1 on a frame hitch and at
		# the higher level speeds.
		var follow = clampf(delta * (speed / 10.0), 0.0, 1.0)
		set_point_position(i, current_position.lerp(prev_position + offset, follow))

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
