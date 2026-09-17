extends Polygon2D

# Greed is punished: the slower the snake gets from eating, the wider these
# senses reach and the harder they hunt.
const BASE_CHASE_RADIUS := 200.0
const AGGRESSION := 0.6
const PATROL_TURN := PI / 4.0
const PATROL_INTERVAL := Vector2(1.0, 3.0)
const RADIUS := 10.0
const COLOR := Color.PURPLE
const EDGE_MARGIN := 20.0

# The snake this enemy hunts. Injected by the scene.
var target: Line2D
var arena_bounds := Rect2()
var speed := 150.0
var direction := Vector2.RIGHT

var _patrol_timer := 0.0
var collision_area: Area2D
var collision_poly: CollisionPolygon2D


func _ready() -> void:
	polygon = PackedVector2Array([
		Vector2(0.0, -RADIUS), Vector2(RADIUS * 0.5, -RADIUS * 0.5),
		Vector2(RADIUS, 0.0), Vector2(RADIUS * 0.5, RADIUS * 0.5),
		Vector2(0.0, RADIUS), Vector2(-RADIUS * 0.5, RADIUS * 0.5),
		Vector2(-RADIUS, 0.0), Vector2(-RADIUS * 0.5, -RADIUS * 0.5)
	])
	color = COLOR

	collision_area = Area2D.new()
	collision_area.name = "CollisionArea"
	add_child(collision_area)

	collision_poly = CollisionPolygon2D.new()
	collision_poly.name = "CollisionPolygon2D"
	collision_poly.polygon = polygon
	collision_area.add_child(collision_poly)


func respawn_in_arena() -> void:
	if arena_bounds.size.x <= 0.0:
		return
	var inset = EDGE_MARGIN
	position = Vector2(
		randf_range(arena_bounds.position.x + inset, arena_bounds.end.x - inset),
		randf_range(arena_bounds.position.y + inset, arena_bounds.end.y - inset)
	)
	direction = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	if direction.length_squared() < 0.1:
		direction = Vector2.RIGHT
	else:
		direction = direction.normalized()


func _process(delta: float) -> void:
	_patrol(delta)

	var hunt = 1.0
	if target:
		hunt = 1.0 + target.get_slowness() * AGGRESSION
		if target.visible and not target.is_invulnerable and target.points.size() > 0:
			var head_position = target.points[0]
			if global_position.distance_to(head_position) < BASE_CHASE_RADIUS * hunt:
				direction = (head_position - global_position).normalized()

	position += direction * speed * hunt * delta
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
