extends Polygon2D

var collision_area: Area2D
var collision_poly: CollisionPolygon2D
var arena_bounds: Rect2

var food_types = {
	"apple": {
		"polygon": [
			Vector2(-5, -5),
			Vector2(5, -5),
			Vector2(5, 5),
			Vector2(-5, 5)
		],
		"color": Color.RED,
		"score": 1,
		"size": 10,
		"spawn_chance": 0.6
	},
	"banana": {
		"polygon": [
			Vector2(-7, -3),
			Vector2(7, -3),
			Vector2(7, 3),
			Vector2(3, 3),
			Vector2(3, 7),
			Vector2(-3, 7),
			Vector2(-3, 3),
			Vector2(-7, 3)
		],
		"color": Color.YELLOW,
		"score": 2,
		"size": 16,
		"spawn_chance": 0.3
	},
	"orange": {
		"polygon": [
			Vector2(-6, -6),
			Vector2(6, -6),
			Vector2(6, 6),
			Vector2(-6, 6)
		],
		"color": Color.ORANGE,
		"score": 3,
		"size": 12,
		"spawn_chance": 0.1
	}
}

var score: int = 1
var current_type: String

func _ready():
	self.hide()
	respawn(true)

func choose_random_food_type():
	var random_value = randf()
	var cumulative_chance = 0.0
	
	for type in food_types:
		cumulative_chance += food_types[type]["spawn_chance"]
		if random_value <= cumulative_chance:
			return type
	
	push_error("Failed to choose a food type, probabilities might not sum to 1.")
	return "apple"

func set_food_type(type: String):
	if food_types.has(type):
		polygon = food_types[type]["polygon"]
		color = food_types[type]["color"]
		score = food_types[type]["score"]
	else:
		push_error("Unknown food type: " + type)

func create_collision(vec):
	collision_area = Area2D.new()
	collision_area.name = "CollisionArea"
	add_child(collision_area)
	
	collision_poly = CollisionPolygon2D.new()
	collision_poly.name = "CollisionPolygon2D"
	collision_poly.polygon = vec
	
	collision_area.add_child(collision_poly)

func respawn(do_create_collision: bool):
	current_type = choose_random_food_type()
	set_food_type(current_type)
	
	var random_x = 0.0
	var random_y = 0.0
	var fsize = food_types[current_type]["size"]
	
	if arena_bounds.size.x > 0:
		random_x = randf_range(arena_bounds.position.x + fsize, arena_bounds.end.x - fsize)
		random_y = randf_range(arena_bounds.position.y + fsize, arena_bounds.end.y - fsize)
	else:
		var viewport_size = get_viewport().get_visible_rect().size
		random_x = randf_range(fsize, viewport_size.x - fsize)
		random_y = randf_range(fsize, viewport_size.y - fsize)
	
	position = Vector2(random_x, random_y)
	
	if do_create_collision:
		create_collision(food_types[current_type]["polygon"])
	
	if collision_poly:
		collision_poly.polygon = food_types[current_type]["polygon"]
	else:
		push_error("Collision polygon not found during respawn!")
