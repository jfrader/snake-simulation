extends Polygon2D

var arena_bounds: Rect2
# The game root, injected by Scene. Used instead of get_tree().current_scene so
# the scene keeps working when it is instanced inside another scene.
var game = null
var speed = 150.0
var direction = Vector2.RIGHT
var patrol_timer = 0.0
# Greed is punished: the slower the snake gets from eating, the wider these
# senses reach and the harder they hunt.
const BASE_CHASE_RADIUS := 200.0
const AGGRESSION := 0.6
var chase_radius = BASE_CHASE_RADIUS

var collision_area: Area2D
var collision_poly: CollisionPolygon2D

func _ready():
	polygon = PackedVector2Array([
		Vector2(0, -10), Vector2(5, -5), Vector2(10, 0), Vector2(5, 5),
		Vector2(0, 10), Vector2(-5, 5), Vector2(-10, 0), Vector2(-5, -5)
	])
	color = Color.PURPLE
	
	collision_area = Area2D.new()
	collision_area.name = "CollisionArea"
	add_child(collision_area)
	
	collision_poly = CollisionPolygon2D.new()
	collision_poly.name = "CollisionPolygon2D"
	collision_poly.polygon = polygon
	collision_area.add_child(collision_poly)

func respawn_in_arena():
	if arena_bounds.size.x == 0: return
	position = Vector2(
		randf_range(arena_bounds.position.x + 20, arena_bounds.end.x - 20),
		randf_range(arena_bounds.position.y + 20, arena_bounds.end.y - 20)
	)
	direction = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	if direction.length_squared() < 0.1:
		direction = Vector2.RIGHT

func _process(delta):
	if not game or game.state != game.State.PLAYING:
		return
	if game.is_paused:
		return

	patrol_timer -= delta
	if patrol_timer <= 0:
		direction = direction.rotated(randf_range(-PI/4, PI/4))
		patrol_timer = randf_range(1.0, 3.0)
	
	var snake = game.snake
	var hunt = 1.0
	if snake:
		hunt = 1.0 + snake.get_slowness() * AGGRESSION
		if snake.visible and not snake.is_invulnerable and snake.points.size() > 0:
			var head_pos = snake.points[0]
			if global_position.distance_to(head_pos) < chase_radius * hunt:
				direction = (head_pos - global_position).normalized()
	
	position += direction * speed * hunt * delta
	
	if position.x < arena_bounds.position.x or position.x > arena_bounds.end.x:
		direction.x *= -1
		position.x = clamp(position.x, arena_bounds.position.x, arena_bounds.end.x)
	if position.y < arena_bounds.position.y or position.y > arena_bounds.end.y:
		direction.y *= -1
		position.y = clamp(position.y, arena_bounds.position.y, arena_bounds.end.y)
