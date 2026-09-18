extends Polygon2D

# Weighted pickups. `size` is the half-extent used for spawn clamping.
const FOOD_TYPES := {
	"apple": {
		"polygon": [
			Vector2(-5, -5), Vector2(5, -5), Vector2(5, 5), Vector2(-5, 5)
		],
		"color": Color.RED,
		"score": 1,
		"size": 10.0,
		"spawn_chance": 0.6
	},
	"banana": {
		"polygon": [
			Vector2(-7, -3), Vector2(7, -3), Vector2(7, 3), Vector2(3, 3),
			Vector2(3, 7), Vector2(-3, 7), Vector2(-3, 3), Vector2(-7, 3)
		],
		"color": Color.YELLOW,
		"score": 2,
		"size": 16.0,
		"spawn_chance": 0.3
	},
	"orange": {
		"polygon": [
			Vector2(-6, -6), Vector2(6, -6), Vector2(6, 6), Vector2(-6, 6)
		],
		"color": Color.ORANGE,
		"score": 3,
		"size": 12.0,
		"spawn_chance": 0.1
	}
}

var arena_bounds := Rect2()
var score := 1

var collision_poly: CollisionPolygon2D


func _ready() -> void:
	hide()
	# Named so the scene can find it: "CollisionArea/CollisionPolygon2D".
	var collision_area = Area2D.new()
	collision_area.name = "CollisionArea"
	add_child(collision_area)

	collision_poly = CollisionPolygon2D.new()
	collision_poly.name = "CollisionPolygon2D"
	collision_area.add_child(collision_poly)


# The scene sets arena_bounds before the first respawn, so the play field is
# always known here.
func respawn() -> void:
	var chosen = _choose_random_type()
	_apply_type(chosen)

	var half = FOOD_TYPES[chosen]["size"]
	position = Vector2(
		randf_range(arena_bounds.position.x + half, arena_bounds.end.x - half),
		randf_range(arena_bounds.position.y + half, arena_bounds.end.y - half)
	)


func _choose_random_type() -> String:
	var roll = randf()
	var cumulative = 0.0
	for type in FOOD_TYPES:
		cumulative += FOOD_TYPES[type]["spawn_chance"]
		if roll <= cumulative:
			return type
	push_error("Food spawn chances do not sum to 1; falling back to apple.")
	return "apple"


func _apply_type(type: String) -> void:
	if not FOOD_TYPES.has(type):
		push_error("Unknown food type: " + type)
		return
	polygon = FOOD_TYPES[type]["polygon"]
	color = FOOD_TYPES[type]["color"]
	score = FOOD_TYPES[type]["score"]
	collision_poly.polygon = FOOD_TYPES[type]["polygon"]
