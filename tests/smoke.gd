extends SceneTree
# End-to-end cycle test against the real scene: real _process, real polygon
# collision, the real level timer, and the music phase mapping.
#
#     godot --headless -s tests/smoke.gd

class Recorder extends Node:
	var states := []
	var levels := []

	func start_level(level_id, _style, _energy, _complexity, _brightness, _syncopation):
		levels.append(level_id)

	func update_state(phase, discovery, threat, quest_complete):
		states.append([phase, discovery, threat, quest_complete])


func _key(code: int) -> InputEventKey:
	var event = InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event


func _settle(frames: int = 2) -> void:
	for i in range(frames):
		await process_frame


func _init():
	var main = load("res://scene.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await _settle()

	# --- boots in the menu
	assert(main.state == main.State.MENU, "boots to MENU")
	assert(not main.snake.visible, "snake hidden in the menu")

	# --- SPACE starts a run
	main._input(_key(KEY_SPACE))
	assert(main.state == main.State.PLAYING, "SPACE starts play")
	assert(main.current_level == 1, "starts at level 1")
	assert(main.lives == 3, "starts with 3 lives")

	# --- real collision: park the fruit on the head, let _process detect it
	var score_before = main.score
	main.food.position = main.snake.points[0]
	await _settle()
	assert(main.fruit_eaten == 1, "fruit eaten through real collision")
	assert(main.score > score_before, "eating raises the score")

	# --- eat up to the level target
	while main.fruit_eaten < main.level_cfg.fruit_target:
		main.food.position = main.snake.points[0]
		await _settle()
	assert(main.state == main.State.LEVEL_CLEAR, "hitting the target clears the level")

	# --- the real 2s timer advances the level
	var waited = 0.0
	while main.state == main.State.LEVEL_CLEAR and waited < 6.0:
		await create_timer(0.1).timeout
		waited += 0.1
	assert(main.state == main.State.PLAYING, "level timer advances play")
	assert(main.current_level == 2, "now on level 2")
	assert(main.enemies.size() == 1, "level 2 spawns one enemy")

	# --- an enemy inside its detection radius turns toward the head
	main.snake.is_invulnerable = false
	var hunter = main.enemies[0]
	hunter.position = main.snake.points[0] + Vector2(140, 0)
	await _settle()
	var to_head = (main.snake.points[0] - hunter.position).normalized()
	assert(hunter.direction.dot(to_head) > 0.8, "a close enemy chases the snake")

	# --- real enemy collision costs a life (spawn protection is cleared first)
	main.snake.is_invulnerable = false
	main.enemies[0].position = main.snake.points[0]
	await _settle()
	assert(main.lives == 2, "enemy contact costs a life")
	assert(main.snake.is_invulnerable, "a hit grants invulnerability")

	# --- drain the rest of the lives through real collisions
	var guard = 0
	while main.state == main.State.PLAYING and guard < 20:
		main.snake.is_invulnerable = false
		if main.enemies.size() > 0:
			main.enemies[0].position = main.snake.points[0]
		await _settle()
		guard += 1
	assert(main.state == main.State.GAME_OVER, "lives exhausted reach GAME_OVER")
	assert(guard < 20, "game over arrived without spinning")

	# --- SPACE restarts
	main._input(_key(KEY_SPACE))
	assert(main.state == main.State.PLAYING, "SPACE restarts from game over")
	assert(main.current_level == 1 and main.lives == 3, "restart resets the run")

	# --- the twist: eating adds drag, floored so the snake always moves
	main.start_game()
	main.start_level(1)
	var base_speed = main.snake.start_speed
	var base_length = main.snake.SEGMENTS
	assert(main.snake.get_point_count() == base_length, "a new game starts at base length")
	assert(
		is_equal_approx(main.snake.width, main.snake.START_WIDTH),
		"a new game starts at base girth"
	)

	main.snake.grow(1)
	assert(main.snake.speed < base_speed, "eating slows the snake")
	assert(main.snake.get_slowness() > 0.0, "slowness is reported")
	assert(main.snake.width > main.snake.START_WIDTH, "eating adds girth")

	# length is the single source of truth for both girth and speed
	var grown = main.snake.get_point_count()
	var expected_width = minf(
		main.snake.MAX_WIDTH,
		main.snake.START_WIDTH + (grown - base_length) * main.snake.WIDTH_PER_SEGMENT
	)
	assert(is_equal_approx(main.snake.width, expected_width), "girth reads off length")

	main.snake.grow(500)
	assert(main.snake.get_point_count() == main.snake.LENGTH_CAP, "length is capped")
	assert(
		is_equal_approx(main.snake.speed, base_speed * main.snake.MIN_SPEED_RATIO),
		"speed floors at the minimum ratio"
	)
	assert(is_equal_approx(main.snake.get_slowness(), 1.0), "a maxed snake is fully slowed")

	# --- growth survives a level transition
	var carried = main.snake.get_point_count()
	main.start_level(2)
	assert(main.snake.get_point_count() == carried, "growth persists across levels")
	assert(main.snake.is_invulnerable, "a new level grants spawn protection")

	# --- a hit slims you, it does not wipe the run
	main.snake.take_hit(main.arena.bounds)
	assert(main.snake.get_point_count() < carried, "a hit slims the snake")
	assert(main.snake.get_point_count() > main.snake.SEGMENTS, "a hit does not wipe the run")
	assert(main.snake.speed > base_speed * main.snake.MIN_SPEED_RATIO, "slimming speeds you back up")

	# --- only a new game resets the body
	main.start_game()
	assert(main.snake.get_point_count() == main.snake.SEGMENTS, "a new game resets the body")

	# --- greed is punished: a slowed snake is hunted from farther out
	main.start_level(2)
	main.snake.reset_body(main.arena.bounds)
	main.snake.set_base_speed(main.level_cfg.base_speed)
	main.snake.is_invulnerable = false
	var stalker = main.enemies[0]
	main.snake.grow(30)
	var slowness = main.snake.get_slowness()
	assert(slowness > 0.3, "30 extra segments is meaningfully slow")
	var reach = stalker.BASE_CHASE_RADIUS * (1.0 + slowness * stalker.DETECTION_AGGRESSION)
	assert(reach > stalker.BASE_CHASE_RADIUS * 1.15, "slowness widens their senses")

	# placed outside the base radius but inside the widened one
	var spot = reach - 15.0
	assert(spot > stalker.BASE_CHASE_RADIUS, "placed outside the base chase radius")
	stalker.position = main.snake.points[0] + Vector2(spot, 0)
	stalker.direction = Vector2.LEFT
	await _settle()
	var toward = (main.snake.points[0] - stalker.position).normalized()
	assert(stalker.direction.dot(toward) > 0.8, "a slowed snake is hunted from farther out")

	# --- fairness invariant: even fully bloated, the snake can outrun a hunter
	main.snake.grow(500)
	assert(is_equal_approx(main.snake.get_slowness(), 1.0), "snake is at max bloat")
	var bloated_speed = main.snake.speed
	for enemy in main.enemies:
		var hunt_speed = enemy.speed * (1.0 + 1.0 * enemy.SPEED_AGGRESSION)
		var capped = minf(hunt_speed, bloated_speed * enemy.MAX_HUNT_SPEED_RATIO)
		assert(capped < bloated_speed, "a hunter never outruns a bloated snake")
	assert(
		bloated_speed * main.enemies[0].MAX_HUNT_SPEED_RATIO < bloated_speed,
		"the escape margin is real"
	)

	# --- music phase mapping, driven without the addon installed
	var recorder = Recorder.new()
	main.music.queue_free()
	main.music = recorder
	main.add_child(recorder)

	main.start_level(1)
	recorder.states.clear()
	main.update_music_state()
	assert(recorder.states[0][0] == "explore", "level 1 home phase is explore")

	main.start_level(2)
	main.enemies[0].position = Vector2(-9999, -9999)
	recorder.states.clear()
	main.update_music_state()
	assert(recorder.states[0][0] == "explore", "a distant enemy keeps the home phase")

	main.enemies[0].position = main.snake.points[0]
	recorder.states.clear()
	main.update_music_state()
	assert(recorder.states[0][0] == "combat", "a close enemy switches to combat")
	assert(recorder.states[0][2] > 0.0, "threat tracks proximity")

	main.start_level(5)
	recorder.states.clear()
	main.update_music_state()
	assert(recorder.states[0][0] == "combat", "the boss level requests combat")
	assert(recorder.states[0][2] >= 0.85, "boss threat escalates the section")

	main.start_level(6)
	for enemy in main.enemies:
		enemy.position = Vector2(-9999, -9999)
	recorder.states.clear()
	main.update_music_state()
	assert(recorder.states[0][0] == "dungeon", "late levels sit in dungeon")

	main.fruit_eaten = main.level_cfg.fruit_target
	recorder.states.clear()
	main.update_music_state()
	assert(recorder.states[0][0] == "sanctuary", "a fruit run reaches sanctuary")

	recorder.states.clear()
	main.level_clear()
	assert(recorder.states[0][0] == "victory", "clearing requests victory")
	assert(recorder.states[0][3] == true, "victory carries quest_complete")
	assert(recorder.levels.has("level-6"), "the level id is passed to the music layer")

	# The addon-absent no-op is covered by tests/music_stub_test.gd.

	print("SMOKE TEST PASSED")
	quit()
