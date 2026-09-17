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

const SEGMENTS := 10
const SEGMENT_SPACING := 5.0
const START_WIDTH := 8.0
const MAX_WIDTH := 16.0
const DOT_SIDES := 8

const INVULNERABILITY_TIME := 2.0
const BLINK_INTERVAL := 0.1
const BLINK_ALPHA := 0.3

# Lateral wobble of the body: amplitude in pixels, frequency in radians/second.
const WAVE_AMPLITUDE := 1.0
const WAVE_FREQUENCY := 20.0

var start_speed := 300.0
var speed := 300.0
var direction := Vector2.RIGHT
var arena_bounds := Rect2()

var is_invulnerable := false
var current_invulnerability_timer := 0.0

var head_area: Area2D
var collision_poly: CollisionPolygon2D
var eye_left: Polygon2D
var eye_right: Polygon2D
var tongue_root: Node2D
var tongue_stem: Line2D
var tongue_prong_left: Line2D
var tongue_prong_right: Line2D

var _time := 0.0
var _blink_timer := 0.0
var _tongue_clock := 0.0
var _tongue_next := 0.0


func _ready() -> void:
	hide()
	set_process(false)
	width = START_WIDTH
	default_color = Color.LAWN_GREEN
	begin_cap_mode = Line2D.LINE_CAP_ROUND
	end_cap_mode = Line2D.LINE_CAP_ROUND
	_build_head()


# Arrow keys are owned by the scene; it calls this so input lives in one place.
func steer(new_direction: Vector2) -> void:
	if new_direction == -direction:
		return
	direction = new_direction


func shrink_and_respawn(bounds: Rect2) -> void:
	arena_bounds = bounds
	var center = bounds.position + bounds.size / 2.0

	clear_points()
	direction = Vector2.RIGHT
	add_point(center)
	for i in range(1, SEGMENTS):
		add_point(Vector2(center.x - i * SEGMENT_SPACING, center.y))

	width = START_WIDTH
	adjust_width_curve()
	adjust_head_collision()

	is_invulnerable = true
	current_invulnerability_timer = INVULNERABILITY_TIME
	_blink_timer = 0.0


func grow(times: int = 1) -> void:
	for i in range(times):
		_append_tail_segment()
		_grow_width(get_point_count())

	speed = maxf(start_speed * MIN_SPEED_RATIO, speed - start_speed * DRAG_PER_SEGMENT * times)
	adjust_width_curve()


# How far the drag has pulled the snake below the level's base speed.
func get_slowness() -> float:
	if start_speed <= 0.0:
		return 0.0
	return clampf(1.0 - speed / start_speed, 0.0, 1.0)


func _append_tail_segment() -> void:
	if points.size() >= 2:
		var tail = points[points.size() - 1]
		var before_tail = points[points.size() - 2]
		var growth_direction = (tail - before_tail).normalized()
		add_point(tail + growth_direction * width)
	elif points.size() == 1:
		add_point(points[0] - direction.normalized() * width)


func _grow_width(amount: float) -> void:
	if width >= MAX_WIDTH:
		return
	width += 0.05 * amount
	adjust_head_collision()


func _process(delta: float) -> void:
	if is_invulnerable:
		_tick_invulnerability(delta)

	_time += delta
	_update_tongue(delta)

	var head_position = points[0] + direction * speed * delta
	set_point_position(0, head_position)

	# `points` returns a copy, so index it once instead of re-fetching it per
	# segment, and write each new position back as it is computed.
	var chain = points
	var vibration_direction = Vector2(direction.y, -direction.x).normalized()
	var follow = clampf(delta * (speed / 10.0), 0.0, 1.0)
	for i in range(1, chain.size()):
		var offset = vibration_direction * (sin(_time * WAVE_FREQUENCY + i * 0.1) * WAVE_AMPLITUDE)
		# The follow factor must never exceed 1, or a point lands past the one
		# ahead of it and the body inverts. It exceeds 1 on a frame hitch and at
		# the higher level speeds.
		var moved = chain[i].lerp(chain[i - 1] + offset, follow)
		chain[i] = moved
		set_point_position(i, moved)

	update_head_collision()
	_bounce_off_arena(head_position)


func _tick_invulnerability(delta: float) -> void:
	current_invulnerability_timer -= delta
	_blink_timer += delta
	if _blink_timer > BLINK_INTERVAL:
		modulate.a = BLINK_ALPHA if modulate.a >= 0.9 else 1.0
		_blink_timer = 0.0
	if current_invulnerability_timer <= 0.0:
		is_invulnerable = false
		modulate.a = 1.0


func _bounce_off_arena(head_position: Vector2) -> void:
	if arena_bounds.size.x <= 0.0:
		return
	if head_position.x < arena_bounds.position.x or head_position.x > arena_bounds.end.x:
		direction.x *= -1.0
		head_position.x = clampf(head_position.x, arena_bounds.position.x, arena_bounds.end.x)
		set_point_position(0, head_position)
	if head_position.y < arena_bounds.position.y or head_position.y > arena_bounds.end.y:
		direction.y *= -1.0
		head_position.y = clampf(head_position.y, arena_bounds.position.y, arena_bounds.end.y)
		set_point_position(0, head_position)


func update_head_collision() -> void:
	head_area.global_position = points[0]
	head_area.global_rotation = direction.angle()


func _build_head() -> void:
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
	var shape = PackedVector2Array()
	for i in range(DOT_SIDES):
		var angle = TAU * i / float(DOT_SIDES)
		shape.append(Vector2(cos(angle), sin(angle)))
	dot.polygon = shape
	dot.color = color
	return dot


func _make_tongue_line() -> Line2D:
	var line = Line2D.new()
	line.default_color = TONGUE_COLOR
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	return line


func _schedule_tongue() -> void:
	_tongue_next = randf_range(TONGUE_INTERVAL.x, TONGUE_INTERVAL.y)


func adjust_head_collision() -> void:
	var half = width / 2.0
	collision_poly.polygon = PackedVector2Array([
		Vector2(-half - 1.0, 0.0),
		Vector2(0.0, -half - 1.0),
		Vector2(half + 1.0, 0.0),
		Vector2(0.0, half + 1.0)
	])
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


func _update_tongue(delta: float) -> void:
	_tongue_clock += delta
	if _tongue_clock >= _tongue_next:
		_tongue_clock = 0.0
		_schedule_tongue()
		tongue_root.show()

	if not tongue_root.visible:
		return
	var progress = _tongue_clock / TONGUE_FLICK_TIME
	if progress > 1.0:
		tongue_root.hide()
		return

	# Out and back within the flick window.
	var out = sin(clampf(progress, 0.0, 1.0) * PI)
	var snout = width / 2.0
	var tip = snout * 0.6 + width * TONGUE_REACH * out
	var fork = width * 0.28 + 1.5
	tongue_stem.points = PackedVector2Array([Vector2(snout * 0.5, 0.0), Vector2(tip, 0.0)])
	tongue_prong_left.points = PackedVector2Array([
		Vector2(tip, 0.0), Vector2(tip + fork, -fork * 0.75)
	])
	tongue_prong_right.points = PackedVector2Array([
		Vector2(tip, 0.0), Vector2(tip + fork, fork * 0.75)
	])


func adjust_width_curve() -> void:
	if not width_curve:
		width_curve = Curve.new()
	while width_curve.get_point_count() > 0:
		width_curve.remove_point(0)

	var total_points = points.size()
	if total_points < 2:
		return

	var total_length := 0.0
	for i in range(1, total_points):
		total_length += points[i - 1].distance_to(points[i])

	var head_portion := 0.12
	var tail_portion := 0.1
	var body_portion := 1.0 - head_portion - tail_portion

	var head_length_pixels = minf(total_length * head_portion, 60.0)
	var head_proportion = head_length_pixels / total_length if total_length > 0.0 else 0.0

	width_curve.add_point(Vector2(0.0, 0.8))
	width_curve.add_point(Vector2(head_proportion * 0.25, 0.9))
	width_curve.add_point(Vector2(head_proportion * 0.5, 1.0))
	width_curve.add_point(Vector2(head_proportion * 0.75, 0.9))
	width_curve.add_point(Vector2(head_proportion, 0.7))

	var body_start = head_proportion
	var body_end = body_start + (body_portion * (1.0 - head_proportion))
	width_curve.add_point(Vector2(body_start, 0.7))
	width_curve.add_point(Vector2(body_start + (body_end - body_start) / 2.0, 0.65))
	width_curve.add_point(Vector2(body_end, 0.25))

	width_curve.add_point(Vector2(body_end, 0.2))
	width_curve.add_point(Vector2(1.0, 0.143))
