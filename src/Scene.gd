extends Node2D

const ArenaScript = preload("res://src/Arena.gd")
const EnemyScript = preload("res://src/Enemy.gd")
const FoodScript = preload("res://src/Food.gd")
const HudScript = preload("res://src/HUD.gd")
const MusicScript = preload("res://src/MusicManager.gd")
const RunScript = preload("res://src/Run.gd")
const Save = preload("res://src/Save.gd")
const SnakeScript = preload("res://src/Snake.gd")

# An enemy inside this range escalates the score to combat.
const DANGER_RADIUS := 240.0
const STARTING_LIVES := 3
# How close to the floor counts as starving, for the HUD warning.
const STARVING_MARGIN := 4

enum State { MENU, PLAYING, GAME_OVER }

var state := State.MENU
var is_paused := false

var snake: Line2D
var food: Polygon2D
var enemies: Array = []

var elapsed := 0.0
var score := 0
var lives := STARTING_LIVES
var fruit_eaten := 0
var difficulty = null
var best := {"time": 0.0, "score": 0}

var arena: Node2D
var hud: CanvasLayer
var music: Node


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

	best = Save.load_best()
	go_to_menu()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return

	match event.keycode:
		KEY_SPACE:
			if state != State.PLAYING:
				start_run()
		KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT:
			if state == State.PLAYING and not is_paused:
				snake.steer(_direction_for_key(event.keycode))
		KEY_P:
			if state == State.PLAYING:
				set_paused(not is_paused)
		KEY_ESCAPE:
			if state == State.PLAYING:
				set_paused(not is_paused)
			else:
				get_tree().quit()


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
	hud.set_paused(paused, _pause_detail())
	_apply_playfield_active()


func _pause_detail() -> String:
	return "Time %s  ·  Score %d  ·  Length %d" % [
		RunScript.format_time(elapsed), score, snake.get_point_count()
	]


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
	hud.show_title(
		"SNAKE SIMULATION",
		"BEST  " + Save.format_best(best),
		"SPACE to start   ·   Arrows steer   ·   P pause   ·   ESC quit"
	)
	_hide_playfield()
	hud.set_play_hud_visible(false)
	_apply_playfield_active()
	music.start_menu()
	music.update_state("camp", 0.0, 0.0, false)


func start_run() -> void:
	elapsed = 0.0
	score = 0
	lives = STARTING_LIVES
	fruit_eaten = 0
	difficulty = RunScript.get_difficulty(0.0, 0.0)

	state = State.PLAYING
	is_paused = false
	hud.set_paused(false)
	hud.hide_overlay()

	snake.set_base_speed(RunScript.BASE_SPEED)
	snake.reset_body(arena.bounds)

	food.arena_bounds = arena.bounds
	food.respawn()

	clear_enemies()
	_apply_difficulty()

	snake.show()
	food.show()
	hud.set_play_hud_visible(true)
	_apply_playfield_active()

	refresh_hud()
	music.start_run(
		"run-%d" % randi(),
		difficulty.style, difficulty.energy,
		difficulty.complexity, difficulty.brightness, difficulty.syncopation
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
		elapsed += delta
		check_collisions()
		_apply_difficulty()
		if snake.tick_hunger(delta):
			_starve()
		refresh_hud()
		update_music_state()


# The run's difficulty is recomputed every frame from time and greed, so it
# rises smoothly instead of in level steps. Enemies are added as pressure
# climbs and never removed: a hit slims the snake but does not call off the hunt.
func _apply_difficulty() -> void:
	difficulty = RunScript.get_difficulty(elapsed, snake.get_slowness())
	while enemies.size() < difficulty.enemy_count:
		_spawn_enemy()
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.speed = difficulty.enemy_speed


func _spawn_enemy() -> void:
	var enemy = EnemyScript.new()
	enemy.arena_bounds = arena.bounds
	enemy.speed = difficulty.enemy_speed
	enemy.target = snake
	add_child(enemy)
	enemies.append(enemy)
	enemy.respawn_in_arena()
	enemy.set_process(not is_paused)


func update_music_state() -> void:
	if state != State.PLAYING or difficulty == null:
		return

	var greed = snake.get_slowness()
	var head_position = snake.points[0] if snake.points.size() > 0 else Vector2.ZERO

	var nearest = INF
	for enemy in enemies:
		if is_instance_valid(enemy):
			nearest = minf(nearest, enemy.global_position.distance_to(head_position))

	# Home section follows pressure; an enemy on the snake takes over, and late
	# in a run that escalates to the boss section. Gorging while clear is the
	# sanctuary moment.
	var phase = "dungeon" if difficulty.pressure >= RunScript.DUNGEON_PRESSURE else "explore"
	var threat = difficulty.threat

	if nearest < DANGER_RADIUS:
		phase = "combat"
		var proximity = clampf(1.0 - nearest / DANGER_RADIUS, 0.0, 1.0)
		threat = minf(1.0, difficulty.threat * 0.5 + proximity * 0.6)
		if difficulty.pressure >= RunScript.BOSS_PRESSURE:
			# Adventure escalates a combat request with threat >= 0.85 to boss.
			threat = maxf(threat, 0.9)
	elif greed >= 0.85:
		phase = "sanctuary"

	music.update_state(phase, greed, threat, false)


# Every value and ratio the HUD shows, computed here so the HUD stays
# presentational.
func _readout() -> Dictionary:
	var speed_ratio = snake.speed / snake.start_speed if snake.start_speed > 0.0 else 1.0
	var floor_ratio = SnakeScript.MIN_SPEED_RATIO
	return {
		"time": RunScript.format_time(elapsed),
		"score": score,
		"lives": lives,
		"length": snake.get_point_count(),
		"larder": snake.get_slowness(),
		"speed": speed_ratio,
		"speed_bar": (speed_ratio - floor_ratio) / maxf(0.001, 1.0 - floor_ratio),
		"starving": snake.get_point_count() <= SnakeScript.MIN_SEGMENTS + STARVING_MARGIN,
		"best": best,
	}


func refresh_hud() -> void:
	hud.update_hud(_readout())


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
	food.respawn()
	refresh_hud()


func take_damage() -> void:
	lives -= 1
	refresh_hud()
	if lives <= 0:
		game_over()
	else:
		snake.take_hit(arena.bounds)


# Ran out of larder: one life, and a fresh buffer to eat back up from.
func _starve() -> void:
	lives -= 1
	refresh_hud()
	if lives <= 0:
		game_over()
	else:
		snake.reset_body(arena.bounds)
		snake.set_base_speed(RunScript.BASE_SPEED)


func game_over() -> void:
	state = State.GAME_OVER
	refresh_hud()

	var improved = Save.is_better(elapsed, score, best)
	if improved:
		best = {"time": elapsed, "score": score}
		Save.save_best(elapsed, score)

	hud.show_title(
		"NEW BEST" if improved else "RUN OVER",
		"Survived %s  ·  Score %d" % [RunScript.format_time(elapsed), score],
		"BEST  %s   ·   SPACE to go again   ·   ESC to quit" % Save.format_best(best)
	)
	_hide_playfield()
	_apply_playfield_active()
	music.update_state("camp", 0.0, 0.0, false)
