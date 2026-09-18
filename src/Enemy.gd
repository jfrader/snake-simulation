extends Polygon2D

# Greed is punished: the slower the snake gets from eating, the wider these
# senses reach and the harder they hunt. Detection widens fully; raw speed is
# throttled, and can never reach the snake's own speed, or a fully bloated
# player would be outrun and killed with no counterplay.
const BASE_CHASE_RADIUS := 200.0
const DETECTION_AGGRESSION := 0.6
const SPEED_AGGRESSION := 0.15
const MAX_HUNT_SPEED_RATIO := 0.9
const PATROL_TURN := PI / 4.0
const PATROL_INTERVAL := Vector2(1.0, 3.0)
const RADIUS := 10.0
const COLOR := Color.PURPLE
const EDGE_MARGIN := 20.0
# Enough room that a mid-run spawn is not an instant hit.
const MIN_SPAWN_DISTANCE := 220.0
const SPAWN_ATTEMPTS := 24

# The snake this enemy hunts. Injected by the scene.
var target: Line2D
var arena_bounds := Rect2()
var speed := 150.0
var direction := Vector2.RIGHT

var _patrol_timer := 0.0


func _ready() -> void:
	polygon = PackedVector2Array([
		Vector2(0.0, -RADIUS), Vector2(RADIUS * 0.5, -RADIUS * 0.5),
		Vector2(RADIUS, 0.0), Vector2(RADIUS * 0.5, RADIUS * 0.5),
		Vector2(0.0, RADIUS), Vector2(-RADIUS * 0.5, RADIUS * 0.5),
		Vector2(-RADIUS, 0.0), Vector2(-RADIUS * 0.5, -RADIUS * 0.5)
	])
	color = COLOR

	# Named so the scene can find it: "CollisionArea/CollisionPolygon2D".
	var collision_area = Area2D.new()
	collision_area.name = "CollisionArea"
	add_child(collision_area)

	var collision_poly = CollisionPolygon2D.new()
	collision_poly.name = "CollisionPolygon2D"
	collision_poly.polygon = polygon
	collision_area.add_child(collision_poly)


func respawn_in_arena() -> void:
	if arena_bounds.size.x <= 0.0:
		return
	# Spawning now happens mid-run as pressure climbs, so an enemy must never
	# appear on top of the snake. Retry for a spot that gives the player room.
	var fallback = arena_bounds.position + arena_bounds.size / 2.0
	for attempt in range(SPAWN_ATTEMPTS):
		var candidate = Vector2(
			randf_range(arena_bounds.position.x + EDGE_MARGIN, arena_bounds.end.x - EDGE_MARGIN),
			randf_range(arena_bounds.position.y + EDGE_MARGIN, arena_bounds.end.y - EDGE_MARGIN)
		)
		if not target or not target.visible or target.points.is_empty():
			position = candidate
			break
		if candidate.distance_to(target.points[0]) >= MIN_SPAWN_DISTANCE:
			position = candidate
			break
		position = fallback
	direction = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	if direction.length_squared() < 0.1:
		direction = Vector2.RIGHT
	else:
		direction = direction.normalized()


func _process(delta: float) -> void:
	_patrol(delta)

	var slowness = target.get_slowness() if target else 0.0

	if target and target.visible and not target.is_invulnerable and target.points.size() > 0:
		var head_position = target.points[0]
		var detection = BASE_CHASE_RADIUS * (1.0 + slowness * DETECTION_AGGRESSION)
		if global_position.distance_to(head_position) < detection:
			direction = (head_position - global_position).normalized()

	var hunt_speed = speed * (1.0 + slowness * SPEED_AGGRESSION)
	if target:
		# Always leave the snake an escape, however bloated it gets.
		hunt_speed = minf(hunt_speed, target.speed * MAX_HUNT_SPEED_RATIO)

	position += direction * hunt_speed * delta
	_bounce_off_arena()


func _patrol(delta: float) -> void:
	_patrol_timer -= delta
	if _patrol_timer <= 0.0:
		direction = direction.rotated(randf_range(-PATROL_TURN, PATROL_TURN))
		_patrol_timer = randf_range(PATROL_INTERVAL.x, PATROL_INTERVAL.y)


func _bounce_off_arena() -> void:
	if position.x < arena_bounds.position.x or position.x > arena_bounds.end.x:
		direction.x *= -1.0
		position.x = clampf(position.x, arena_bounds.position.x, arena_bounds.end.x)
	if position.y < arena_bounds.position.y or position.y > arena_bounds.end.y:
		direction.y *= -1.0
		position.y = clampf(position.y, arena_bounds.position.y, arena_bounds.end.y)
