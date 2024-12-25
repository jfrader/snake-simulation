extends Node2D

@onready var polygon: Polygon2D = $Polygon2D
@onready var area: Area2D = $Polygon2D/Area2D
@onready var collision: CollisionPolygon2D = $Polygon2D/Area2D/CollisionPolygon2D
@onready var camera: Camera2D = get_node_or_null("/root/Game/Camera2D")

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
var is_respawning: bool = false

func _ready():
	if camera:
		respawn()
	else:
		push_error("Camera not found!")

func _process(_delta):
	if camera and not is_respawning:
		var camera_viewport_size = get_viewport().get_visible_rect().size / camera.zoom
		var camera_position = camera.global_position
		var food_position = polygon.global_position
		var food_size = food_types[current_type]["size"] / 2

		if (food_position.x < camera_position.x - camera_viewport_size.x / 2 - food_size or 
			food_position.x > camera_position.x + camera_viewport_size.x / 2 + food_size or 
			food_position.y < camera_position.y - camera_viewport_size.y / 2 - food_size or 
			food_position.y > camera_position.y + camera_viewport_size.y / 2 + food_size):
			is_respawning = true
			respawn_after_delay()

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
		polygon.polygon = food_types[type]["polygon"]
		polygon.color = food_types[type]["color"]
		score = food_types[type]["score"]
	else:
		push_error("Unknown food type: " + type)

func respawn():
	if camera:
		var camera_viewport_size = get_viewport().get_visible_rect().size / camera.zoom
		var camera_position = camera.global_position

		current_type = choose_random_food_type()
		set_food_type(current_type)
		
		var half_size = food_types[current_type]["size"] / 2
		var random_x = randf_range(camera_position.x - camera_viewport_size.x / 2 + half_size, camera_position.x + camera_viewport_size.x / 2 - half_size)
		var random_y = randf_range(camera_position.y - camera_viewport_size.y / 2 + half_size, camera_position.y + camera_viewport_size.y / 2 - half_size)
		polygon.position = Vector2(random_x, random_y)

		if collision:
			collision.polygon = food_types[current_type]["polygon"]
		else:
			push_error("Collision polygon not found during respawn!")
	else:
		push_error("Camera not found during respawn!")
	is_respawning = false

func respawn_after_delay():
	await get_tree().create_timer(0.5).timeout
	respawn()
