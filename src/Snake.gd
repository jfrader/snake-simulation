extends Line2D

# The head keeps its rounded shape. It reads as a snake head from small organic
# detail rather than a marker: eyes, and a tongue that flicks forward now and then.
const EYE_COLOR := Color(0.06, 0.07, 0.06)
const TONGUE_COLOR := Color(0.95, 0.36, 0.44)
const TONGUE_INTERVAL := Vector2(1.1, 3.4)
const TONGUE_FLICK_TIME := 0.24
const TONGUE_REACH := 0.85

# Eating is the twist: every segment adds girth and drag. Girth and top speed
# are both read off length, so a body carried across levels behaves the same at
# every level's base speed.
const MIN_SPEED_RATIO := 0.4
const HIT_LOSS_FRACTION := 0.35

# MIN_SEGMENTS is the starving floor: eat or die. START_SEGMENTS is the larder
# a fresh run begins with, so there is a buffer before the first meal.
const MIN_SEGMENTS := 10
const START_SEGMENTS := 20
const LENGTH_CAP := 80
# The rope's fixed link length, and the spacing the body is laid out with.
const LINK_LENGTH := 5.0
const BODY_RELAXATIONS := 3
const START_WIDTH := 8.0
const WIDTH_PER_SEGMENT := 0.2
const MAX_WIDTH := START_WIDTH + (LENGTH_CAP - MIN_SEGMENTS) * WIDTH_PER_SEGMENT
const DOT_SIDES := 8

# A bigger body burns fuel faster: seconds per segment lost, light to bloated.
const HUNGER_INTERVAL := Vector2(4.5, 1.8)

const INVULNERABILITY_TIME := 2.0
const BLINK_INTERVAL := 0.1
const BLINK_ALPHA := 0.3

# Slither: frequency in radians/second, phase step per segment, and amplitude as
# a fraction of body width so a fat snake wobbles proportionally. Kept gentle:
# the wave is added on top of the solved chain, so a large amplitude fights the
# constraint on the next frame and reads as jitter.
const WAVE_FREQUENCY := 7.5
const WAVE_PHASE_STEP := 0.25
const WAVE_AMPLITUDE_RATIO := 0.08

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

var _chain := PackedVector2Array()
var _time := 0.0
var _blink_timer := 0.0
var _tongue_clock := 0.0
var _hunger_clock := 0.0
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


# A fresh run: back to the base snake. Only called when a new game starts.
func reset_body(bounds: Rect2) -> void:
	arena_bounds = bounds
	_lay_out(START_SEGMENTS)
	_apply_size()


# Keep the length and girth the run has earned; just put the body back on the
# arena centre and hand out spawn protection. Used at every level start and
# after a hit.
func reposition(bounds: Rect2) -> void:
	arena_bounds = bounds
	_lay_out(maxi(_chain.size(), MIN_SEGMENTS))
	_apply_size()


# A hit costs part of the growth above the base length, never the whole run.
# Slimming down speeds the snake back up, which is the relief from being slow.
func take_hit(bounds: Rect2) -> void:
	var extra = maxi(0, _chain.size() - MIN_SEGMENTS)
	var drop = mini(extra, maxi(2, int(extra * HIT_LOSS_FRACTION)))
	for i in range(drop):
		if _chain.size() > MIN_SEGMENTS:
			_chain.remove_at(_chain.size() - 1)
	reposition(bounds)


func set_base_speed(value: float) -> void:
	start_speed = value
	_apply_size()


func _lay_out(count: int) -> void:
	direction = Vector2.RIGHT
	var center = arena_bounds.position + arena_bounds.size / 2.0
	_chain = PackedVector2Array()
	for i in range(count):
		_chain.append(Vector2(center.x - i * LINK_LENGTH, center.y))
	_sync_points()
	adjust_width_curve()

	is_invulnerable = true
	current_invulnerability_timer = INVULNERABILITY_TIME
	_blink_timer = 0.0


# Length is the single source of truth: girth and top speed are both read from
# it, so nothing can drift out of sync.
func _apply_size() -> void:
	var extra = maxi(0, _chain.size() - MIN_SEGMENTS)
	width = minf(MAX_WIDTH, START_WIDTH + extra * WIDTH_PER_SEGMENT)
	speed = start_speed * lerpf(1.0, MIN_SPEED_RATIO, get_slowness())
	adjust_head_collision()


func grow(times: int = 1) -> void:
	for i in range(times):
		if _chain.size() >= LENGTH_CAP:
			break
		_append_tail_segment()
	_sync_points()
	adjust_width_curve()
	_apply_size()


# The snake burns length continuously. Eating is the only way to top it up, so
# the player is pushed into the very thing that slows them down. Returns true
# when the larder is empty and there is nothing left to burn.
func tick_hunger(delta: float) -> bool:
	_hunger_clock += delta
	var interval = lerpf(HUNGER_INTERVAL.x, HUNGER_INTERVAL.y, get_slowness())
	if _hunger_clock < interval:
		return false
	_hunger_clock -= interval
	if _chain.size() <= MIN_SEGMENTS:
		return true
	_chain.remove_at(_chain.size() - 1)
	_sync_points()
	adjust_width_curve()
	_apply_size()
	return false


# How far the drag has pulled the snake below the run's base speed.
func get_slowness() -> float:
	var span = float(LENGTH_CAP - MIN_SEGMENTS)
	if span <= 0.0:
		return 0.0
	return clampf(float(_chain.size() - MIN_SEGMENTS) / span, 0.0, 1.0)


func _append_tail_segment() -> void:
	if _chain.size() >= 2:
		var tail = _chain[_chain.size() - 1]
		var before_tail = _chain[_chain.size() - 2]
		var growth_direction = (tail - before_tail).normalized()
		_chain.append(tail + growth_direction * width)
	elif _chain.size() == 1:
		_chain.append(_chain[0] - direction.normalized() * width)



func _process(delta: float) -> void:
	if is_invulnerable:
		_tick_invulnerability(delta)

	_time += delta
	_update_tongue(delta)

	if _chain.is_empty():
		return
	_chain[0] += direction * speed * delta
	_bounce_off_arena()
	_solve_body()
	_sync_points()
	update_head_collision()


func _tick_invulnerability(delta: float) -> void:
	current_invulnerability_timer -= delta
	_blink_timer += delta
	if _blink_timer > BLINK_INTERVAL:
		modulate.a = BLINK_ALPHA if modulate.a >= 0.9 else 1.0
		_blink_timer = 0.0
	if current_invulnerability_timer <= 0.0:
		is_invulnerable = false
		modulate.a = 1.0


func _bounce_off_arena() -> void:
	if arena_bounds.size.x <= 0.0:
		return
	var head_position = _chain[0]
	if head_position.x < arena_bounds.position.x or head_position.x > arena_bounds.end.x:
		direction.x *= -1.0
		head_position.x = clampf(head_position.x, arena_bounds.position.x, arena_bounds.end.x)
	if head_position.y < arena_bounds.position.y or head_position.y > arena_bounds.end.y:
		direction.y *= -1.0
		head_position.y = clampf(head_position.y, arena_bounds.position.y, arena_bounds.end.y)
	_chain[0] = head_position


# The body is a rope: every link is held at its fixed length, walked head to
# tail. Deterministic and frame-rate independent, and unlike a lerp toward the
# point ahead it can never overshoot and invert. The extra passes let the chain
# settle around corners.
#
# This solves the WAVE-FREE chain on purpose. Adding the wave here and then
# re-solving from the drawn points next frame feeds the wave back into the
# link directions and compounds down the body, which is what made the animation
# shimmer.
func _solve_body() -> void:
	for relaxation in range(BODY_RELAXATIONS):
		for i in range(1, _chain.size()):
			var link = _chain[i] - _chain[i - 1]
			var link_dir = link.normalized() if link.length_squared() > 0.0001 else -direction
			_chain[i] = _chain[i - 1] + link_dir * LINK_LENGTH


# Mirror the solved chain onto the drawn line, adding the slither wave. The head
# is drawn exactly where it is, so what you see matches what collides.
func _sync_points() -> void:
	if get_point_count() != _chain.size():
		clear_points()
		for point in _chain:
			add_point(point)
		return
	for i in range(_chain.size()):
		set_point_position(i, _chain[i] + _wobble_offset(i))


# Perpendicular to the segment's OWN direction, so the wave travels along the
# body. A pure function of time, so it re-derives every frame and cannot drift.
func _wobble_offset(i: int) -> Vector2:
	if i <= 0 or _chain.size() < 2:
		return Vector2.ZERO
	var link = _chain[i] - _chain[i - 1]
	if link.length_squared() < 0.0001:
		return Vector2.ZERO
	var link_dir = link.normalized()
	var amplitude = width * WAVE_AMPLITUDE_RATIO
	var wave = sin(_time * WAVE_FREQUENCY - i * WAVE_PHASE_STEP) * amplitude
	return Vector2(link_dir.y, -link_dir.x) * wave


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
