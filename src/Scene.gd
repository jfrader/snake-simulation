extends Node2D

const ArenaScript = preload("res://src/Arena.gd")
const EnemyScript = preload("res://src/Enemy.gd")
const FoodScript = preload("res://src/Food.gd")
const HudScript = preload("res://src/HUD.gd")
const Levels = preload("res://src/Levels.gd")
const MusicScript = preload("res://src/MusicManager.gd")
const SnakeScript = preload("res://src/Snake.gd")

# An enemy inside this range escalates the score to combat.
const DANGER_RADIUS := 240.0
const LEVEL_CLEAR_DELAY := 2.0

enum State { MENU, PLAYING, LEVEL_CLEAR, GAME_OVER }

var state := State.MENU
var is_paused := false

var snake: Line2D
var food: Polygon2D
var enemies: Array = []

var score := 0
var lives := 3
var current_level := 1
var fruit_eaten := 0

var arena: Node2D
var hud: CanvasLayer
var music: Node

var level_cfg = null
var next_level_timer := 0.0


func _ready() -> void:
	arena = ArenaScript.new()
	add_child(arena)

	hud = HudScript.new()
	add_child(hud)

	music = MusicScript.new()
	add_child(music)

	snake = SnakeScript.new()
	snake.name = "SnakeBody"
	add_child(snake)

	food = FoodScript.new()
	add_child(food)

	go_to_menu()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return

	match event.keycode:
		KEY_SPACE:
			if state == State.MENU or state == State.GAME_OVER:
				start_game()
			elif state == State.LEVEL_CLEAR:
				start_level(current_level + 1)
		KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT:
			if state == State.PLAYING and not is_paused:
				snake.steer(_direction_for_key(event.keycode))
		KEY_P, KEY_ESCAPE:
			if state == State.PLAYING:
				set_paused(not is_paused)


func _direction_for_key(keycode: int) -> Vector2:
	match keycode:
		KEY_UP:
			return Vector2.UP
		KEY_DOWN:
			return Vector2.DOWN
		KEY_LEFT:
			return Vector2.LEFT
		_:
			return Vector2.RIGHT


func set_paused(paused: bool) -> void:
	is_paused = paused
	hud.set_paused(paused)
	_apply_playfield_active()


# Gameplay nodes only run while the playfield is live, so they never have to
# ask the scene what state it is in.
func _apply_playfield_active() -> void:
	var active = state == State.PLAYING and not is_paused
	snake.set_process(active)
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.set_process(active)


func _hide_playfield() -> void:
	snake.hide()
	food.hide()
	clear_enemies()


func go_to_menu() -> void:
	state = State.MENU
	hud.show_title("SNAKE SIMULATION", "Press SPACE to start  ·  Arrows steer  ·  P pauses")
	_hide_playfield()
	_apply_playfield_active()
	music.update_state("camp", 0.0, 0.0, false)


func start_game() -> void:
	score = 0
	lives = 3
	# Only a new game resets the body; growth carries across levels.
	snake.reset_body(arena.bounds)
	start_level(1)


func start_level(level_num: int) -> void:
	current_level = level_num
	fruit_eaten = 0
	state = State.PLAYING
	is_paused = false
	hud.set_paused(false)
	hud.hide_message()

	level_cfg = Levels.get_level(current_level)

	snake.set_base_speed(level_cfg.base_speed)
	snake.reposition(arena.bounds)

	food.arena_bounds = arena.bounds
	food.respawn()

	clear_enemies()
	for i in range(level_cfg.enemy_count):
		var enemy = EnemyScript.new()
		enemy.arena_bounds = arena.bounds
		enemy.speed = level_cfg.enemy_speed
		enemy.target = snake
		add_child(enemy)
		enemies.append(enemy)
		enemy.respawn_in_arena()

	snake.show()
	food.show()
	_apply_playfield_active()

	refresh_hud()
	music.start_level(
		level_cfg.id, level_cfg.style, level_cfg.energy,
		level_cfg.complexity, level_cfg.brightness, level_cfg.syncopation
	)
	update_music_state()


func clear_enemies() -> void:
	for enemy in enemies:
		enemy.queue_free()
	enemies.clear()


func _process(delta: float) -> void:
	if is_paused:
		return

	if state == State.PLAYING:
		check_collisions()
		refresh_hud()
		update_music_state()
	elif state == State.LEVEL_CLEAR:
		next_level_timer -= delta
		if next_level_timer <= 0.0:
			start_level(current_level + 1)


func update_music_state() -> void:
	if state != State.PLAYING:
		return

	var discovery = minf(1.0, float(fruit_eaten) / maxf(1.0, float(level_cfg.fruit_target)))
	var head_position = snake.points[0] if snake.points.size() > 0 else Vector2.ZERO

	var nearest = INF
	for enemy in enemies:
		if is_instance_valid(enemy):
			nearest = minf(nearest, enemy.global_position.distance_to(head_position))

	# Home section for the level, escalated while an enemy is actually close so
	# the score keeps its level identity instead of sitting in combat forever.
	var phase = "dungeon" if current_level >= 6 else "explore"
	var dynamic_threat = level_cfg.threat

	if current_level % 5 == 0:
		# Adventure escalates a combat request with threat >= 0.85 to the boss
		# section; "boss" itself is not a documented area phase.
		phase = "combat"
		dynamic_threat = maxf(dynamic_threat, 0.9)
	elif nearest < DANGER_RADIUS:
		phase = "combat"
		var proximity = clampf(1.0 - nearest / DANGER_RADIUS, 0.0, 1.0)
		dynamic_threat = minf(1.0, level_cfg.threat + proximity * 0.4)
	elif discovery >= 0.85:
		phase = "sanctuary"

	music.update_state(phase, discovery, dynamic_threat, false)


func refresh_hud() -> void:
	if not level_cfg or not snake:
		return
	var speed_ratio = snake.speed / snake.start_speed if snake.start_speed > 0.0 else 1.0
	hud.update_hud(score, current_level, lives, fruit_eaten, level_cfg.fruit_target, speed_ratio)


func check_collisions() -> void:
	if not food or not snake or not snake.visible:
		return

	var head_polygon = _global_polygon(snake.get_node_or_null("HeadArea/CollisionPolygon2D"))
	if head_polygon.is_empty():
		return

	if food.visible:
		var food_polygon = _global_polygon(food.get_node_or_null("CollisionArea/CollisionPolygon2D"))
		if not food_polygon.is_empty() and Geometry2D.intersect_polygons(head_polygon, food_polygon).size() > 0:
			eat_food()

	if not snake.is_invulnerable:
		for enemy in enemies:
			if not is_instance_valid(enemy) or not enemy.visible:
				continue
			var enemy_polygon = _global_polygon(enemy.get_node_or_null("CollisionArea/CollisionPolygon2D"))
			if enemy_polygon.is_empty():
				continue
			if Geometry2D.intersect_polygons(head_polygon, enemy_polygon).size() > 0:
				take_damage()
				break


# Collision polygons are authored in node-local space; both sides have to be
# brought into global space before they can be tested against each other.
func _global_polygon(polygon_node) -> PackedVector2Array:
	var result := PackedVector2Array()
	if polygon_node == null:
		return result
	for point in polygon_node.polygon:
		result.append(point.rotated(polygon_node.global_rotation) + polygon_node.global_position)
	return result


func eat_food() -> void:
	snake.grow(food.score)
	score += food.score
	fruit_eaten += 1
	refresh_hud()

	if fruit_eaten >= level_cfg.fruit_target:
		level_clear()
	else:
		food.respawn()


func take_damage() -> void:
	lives -= 1
	refresh_hud()
	if lives <= 0:
		game_over()
	else:
		snake.take_hit(arena.bounds)


func level_clear() -> void:
	state = State.LEVEL_CLEAR
	hud.show_message("LEVEL CLEAR!")
	_hide_playfield()
	_apply_playfield_active()
	next_level_timer = LEVEL_CLEAR_DELAY
	music.update_state("victory", 1.0, 0.0, true)


func game_over() -> void:
	state = State.GAME_OVER
	hud.show_title(
		"GAME OVER",
		"Score %d  ·  Level %d  ·  Press SPACE to play again" % [score, current_level]
	)
	_hide_playfield()
	_apply_playfield_active()
	music.update_state("camp", 0.0, 0.0, false)
