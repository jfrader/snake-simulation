extends Node2D

enum State { MENU, PLAYING, LEVEL_CLEAR, GAME_OVER }
var state = State.MENU
var is_paused = false

var snake = null
var food = null
var enemies = []

var score = 0
var lives = 3
var current_level = 1
var fruit_eaten = 0

var arena = null
var hud = null
var music = null

var level_cfg = null
var next_level_timer = 0.0

func _ready():
	arena = load("res://Arena.gd").new()
	add_child(arena)
	
	hud = load("res://HUD.gd").new()
	add_child(hud)
	
	music = load("res://MusicManager.gd").new()
	add_child(music)
	
	create_snake()
	create_food()
	
	go_to_menu()

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_SPACE:
			if state == State.MENU:
				start_game()
			elif state == State.LEVEL_CLEAR:
				start_level(current_level + 1)
			elif state == State.GAME_OVER:
				start_game()
		elif (event.keycode == KEY_P or event.keycode == KEY_ESCAPE) and state == State.PLAYING:
			is_paused = not is_paused
			hud.pause_label.visible = is_paused

func go_to_menu():
	state = State.MENU
	hud.show_title("SNAKE SIMULATION", "Press SPACE to start  ·  Arrows steer  ·  P pauses")
	snake.hide()
	food.hide()
	clear_enemies()
	music.update_state("camp", 0.0, 0.0, false)

func start_game():
	score = 0
	lives = 3
	start_level(1)

func start_level(level_num):
	current_level = level_num
	fruit_eaten = 0
	state = State.PLAYING
	is_paused = false
	hud.pause_label.hide()
	hud.hide_message()
	
	var Levels = load("res://Levels.gd")
	level_cfg = Levels.get_level(current_level)
	
	snake.start_speed = level_cfg.base_speed
	snake.speed = level_cfg.base_speed
	snake.shrink_and_respawn(arena.bounds)
	snake.show()
	
	food.arena_bounds = arena.bounds
	food.respawn(false)
	food.show()
	
	clear_enemies()
	for i in range(level_cfg.enemy_count):
		var e = load("res://Enemy.gd").new()
		e.arena_bounds = arena.bounds
		e.speed = level_cfg.enemy_speed
		e.game = self
		add_child(e)
		enemies.append(e)
		e.respawn_in_arena()
		
	refresh_hud()
	
	music.start_level(level_cfg.id, level_cfg.style, level_cfg.energy, level_cfg.complexity, level_cfg.brightness, level_cfg.syncopation)
	update_music_state()

func clear_enemies():
	for e in enemies:
		e.queue_free()
	enemies.clear()

func _process(delta):
	if is_paused:
		return
		
	if state == State.PLAYING:
		check_collisions()
		refresh_hud()
		update_music_state()
	elif state == State.LEVEL_CLEAR:
		next_level_timer -= delta
		if next_level_timer <= 0:
			start_level(current_level + 1)

const DANGER_RADIUS = 240.0

func update_music_state():
	if state != State.PLAYING:
		return
	
	var discovery = min(1.0, float(fruit_eaten) / max(1.0, float(level_cfg.fruit_target)))
	var head_pos = snake.points[0] if snake.points.size() > 0 else Vector2.ZERO
	
	var nearest = INF
	for e in enemies:
		if is_instance_valid(e):
			nearest = min(nearest, e.global_position.distance_to(head_pos))
	
	# Home section for the level, escalated while an enemy is actually close so
	# the score keeps its level identity instead of sitting in combat forever.
	var phase = "dungeon" if current_level >= 6 else "explore"
	var dynamic_threat = level_cfg.threat
	
	if current_level % 5 == 0:
		# Adventure escalates a combat request with threat >= 0.85 to the boss
		# section; "boss" itself is not a documented area phase.
		phase = "combat"
		dynamic_threat = max(dynamic_threat, 0.9)
	elif nearest < DANGER_RADIUS:
		phase = "combat"
		var proximity = clamp(1.0 - nearest / DANGER_RADIUS, 0.0, 1.0)
		dynamic_threat = min(1.0, level_cfg.threat + proximity * 0.4)
	elif discovery >= 0.85:
		phase = "sanctuary"
	
	music.update_state(phase, discovery, dynamic_threat, false)

func refresh_hud():
	if not level_cfg or not snake:
		return
	var speed_ratio = snake.speed / snake.start_speed if snake.start_speed > 0.0 else 1.0
	hud.update_hud(score, current_level, lives, fruit_eaten, level_cfg.fruit_target, speed_ratio)

func check_collisions():
	if not food or not snake or not snake.visible:
		return
		
	var snake_head_poly = snake.get_node_or_null("HeadArea/CollisionPolygon2D")
	if not snake_head_poly: return
	
	var global_snake_polygon = PackedVector2Array()
	for point in snake_head_poly.polygon:
		global_snake_polygon.append(point.rotated(snake_head_poly.global_rotation) + snake_head_poly.global_position)

	if food.visible:
		var food_collision_poly = food.get_node_or_null("CollisionArea/CollisionPolygon2D")
		if food_collision_poly:
			var global_food_polygon = PackedVector2Array()
			for point in food_collision_poly.polygon:
				global_food_polygon.append(point + food.global_position)
			
			if Geometry2D.intersect_polygons(global_snake_polygon, global_food_polygon).size() > 0:
				eat_food()
				
	if not snake.is_invulnerable:
		for e in enemies:
			if not is_instance_valid(e) or not e.visible: continue
			var e_poly = e.get_node_or_null("CollisionArea/CollisionPolygon2D")
			if not e_poly: continue
			
			var global_e_poly = PackedVector2Array()
			for point in e_poly.polygon:
				global_e_poly.append(point + e.global_position)
				
			if Geometry2D.intersect_polygons(global_snake_polygon, global_e_poly).size() > 0:
				take_damage()
				break

func eat_food():
	snake.grow(food.score)
	score += food.score
	fruit_eaten += 1
	refresh_hud()
	
	if fruit_eaten >= level_cfg.fruit_target:
		level_clear()
	else:
		food.respawn(false)

func take_damage():
	lives -= 1
	refresh_hud()
	if lives <= 0:
		game_over()
	else:
		snake.shrink_and_respawn(arena.bounds)

func level_clear():
	state = State.LEVEL_CLEAR
	hud.show_message("LEVEL CLEAR!")
	snake.hide()
	food.hide()
	clear_enemies()
	next_level_timer = 2.0
	music.update_state("victory", 1.0, 0.0, true)

func game_over():
	state = State.GAME_OVER
	hud.show_title("GAME OVER", "Score %d  ·  Level %d  ·  Press SPACE to play again" % [score, current_level])
	snake.hide()
	food.hide()
	clear_enemies()
	music.update_state("camp", 0.0, 0.0, false)

func create_snake():
	snake = Line2D.new()
	snake.name = "SnakeBody"
	var snake_script = load("res://Snake.gd") 
	snake.set_script(snake_script)
	snake.game = self
	add_child(snake)

func create_food():
	food = Polygon2D.new()
	food.set_script(load("res://Food.gd"))
	add_child(food)
