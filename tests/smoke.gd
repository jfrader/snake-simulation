extends SceneTree
# End-to-end test of one endless run against the real scene: real _process, real
# polygon collision, hunger, the difficulty curve, and the music phase mapping.
#
#     godot --headless -s tests/smoke.gd

class Recorder extends Node:
	var states := []
	var runs := []

	func start_run(seed, _style, _energy, _complexity, _brightness, _syncopation):
		runs.append(seed)

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
	assert(main.state == main.State.PLAYING, "SPACE starts the run")
	assert(main.lives == 3, "starts with 3 lives")
	assert(main.elapsed == 0.0, "starts with no elapsed time")
	assert(main.snake.get_point_count() == main.snake.START_SEGMENTS, "starts with a larder")
	assert(main.food.visible, "fruit is on the field")

	# --- real collision: park the fruit on the head, let _process detect it
	var score_before = main.score
	var length_before = main.snake.get_point_count()
	main.food.position = main.snake.points[0]
	await _settle()
	assert(main.fruit_eaten == 1, "fruit eaten through real collision")
	assert(main.score > score_before, "eating raises the score")
	assert(main.snake.get_point_count() > length_before, "eating adds length")

	# --- the clock only runs while playing
	var elapsed_before = main.elapsed
	await _settle(5)
	assert(main.elapsed > elapsed_before, "elapsed time advances while playing")

	# --- the twist: length is the single source of truth for girth and speed
	var base_speed = main.snake.start_speed
	assert(
		is_equal_approx(main.snake.width, main.snake.START_WIDTH
			+ (main.snake.get_point_count() - main.snake.MIN_SEGMENTS) * main.snake.WIDTH_PER_SEGMENT),
		"girth reads off length"
	)
	main.snake.grow(500)
	assert(main.snake.get_point_count() == main.snake.LENGTH_CAP, "length is capped")
	assert(
		is_equal_approx(main.snake.speed, base_speed * main.snake.MIN_SPEED_RATIO),
		"a maxed snake is at the speed floor"
	)
	assert(is_equal_approx(main.snake.get_slowness(), 1.0), "a maxed snake is fully slowed")

	# --- hunger: the body burns down on a timer
	var before_hunger = main.snake.get_point_count()
	assert(not main.snake.tick_hunger(main.snake.HUNGER_INTERVAL.x * 2.0), "hunger is not fatal when fed")
	assert(main.snake.get_point_count() < before_hunger, "hunger burns length")
	assert(main.snake.speed > base_speed * main.snake.MIN_SPEED_RATIO, "burning length speeds you back up")

	# --- starving to the floor is fatal for the run
	main.snake.reset_body(main.arena.bounds)
	main.snake.set_base_speed(base_speed)
	var guard = 0
	while main.snake.get_point_count() > main.snake.MIN_SEGMENTS and guard < 500:
		main.snake.tick_hunger(main.snake.HUNGER_INTERVAL.x * 2.0)
		guard += 1
	assert(main.snake.get_point_count() == main.snake.MIN_SEGMENTS, "burns down to the floor")
	assert(
		main.snake.tick_hunger(main.snake.HUNGER_INTERVAL.x * 2.0),
		"an empty larder is reported as starving"
	)

	var lives_before = main.lives
	main._starve()
	assert(main.lives == lives_before - 1, "starving costs a life")
	assert(main.state == main.State.PLAYING, "starving does not end the run while lives remain")
	assert(
		main.snake.get_point_count() == main.snake.START_SEGMENTS,
		"starving refills the larder"
	)

	# --- a hit slims you, it does not wipe the run
	main.snake.grow(30)
	var before_hit = main.snake.get_point_count()
	main.snake.take_hit(main.arena.bounds)
	assert(main.snake.get_point_count() < before_hit, "a hit slims the snake")
	assert(main.snake.get_point_count() > main.snake.MIN_SEGMENTS, "a hit does not wipe the run")

	# --- difficulty climbs with time AND with greed
	var calm = main.RunScript.get_difficulty(0.0, 0.0)
	var late = main.RunScript.get_difficulty(300.0, 0.0)
	var greedy = main.RunScript.get_difficulty(0.0, 1.0)
	assert(late.enemy_count > calm.enemy_count, "time raises the enemy count")
	assert(late.enemy_speed > calm.enemy_speed, "time raises enemy speed")
	assert(late.threat > calm.threat, "time raises threat")
	assert(greedy.enemy_count > calm.enemy_count, "greed raises the enemy count")
	assert(greedy.enemy_speed > calm.enemy_speed, "greed raises enemy speed")
	assert(greedy.pressure > calm.pressure, "greed adds pressure")
	assert(
		main.RunScript.get_difficulty(0.0, 1.0).enemy_count
			< main.RunScript.get_difficulty(300.0, 1.0).enemy_count,
		"both drivers stack"
	)

	# --- the scene spawns enemies as pressure rises
	main.elapsed = 240.0
	main.snake.grow(200)
	main._apply_difficulty()
	assert(main.enemies.size() >= 5, "a late run fields a pack")
	assert(main.difficulty.enemy_count <= main.RunScript.MAX_ENEMIES, "the pack is capped")
	var expected_count = main.difficulty.enemy_count
	main.elapsed = 0.0
	main._apply_difficulty()
	assert(main.enemies.size() >= expected_count, "enemies are never called off")

	# --- mid-run spawns are never on top of the snake
	var head = main.snake.points[0]
	for spawn in range(60):
		var enemy = main.EnemyScript.new()
		enemy.arena_bounds = main.arena.bounds
		enemy.target = main.snake
		main.add_child(enemy)
		enemy.respawn_in_arena()
		assert(
			enemy.position.distance_to(main.snake.points[0]) >= enemy.MIN_SPAWN_DISTANCE,
			"a spawn gives the player room (attempt %d)" % spawn
		)
		enemy.queue_free()
	await _settle()

	# --- fairness invariant: even fully bloated, the snake can outrun a hunter
	main.snake.grow(500)
	assert(is_equal_approx(main.snake.get_slowness(), 1.0), "snake is at max bloat")
	var bloated_speed = main.snake.speed
	for enemy in main.enemies:
		var hunt_speed = enemy.speed * (1.0 + 1.0 * enemy.SPEED_AGGRESSION)
		var capped = minf(hunt_speed, bloated_speed * enemy.MAX_HUNT_SPEED_RATIO)
		assert(capped < bloated_speed, "a hunter never outruns a bloated snake")

	# --- enemy contact costs a life
	main.snake.is_invulnerable = false
	var lives_before_contact = main.lives
	main.enemies[0].position = main.snake.points[0]
	await _settle()
	assert(main.lives == lives_before_contact - 1, "enemy contact costs a life")
	assert(main.snake.is_invulnerable, "a hit grants invulnerability")

	# --- drain the rest of the lives: the run only ends at zero
	var drain_guard = 0
	while main.state == main.State.PLAYING and drain_guard < 20:
		main.snake.is_invulnerable = false
		if main.enemies.size() > 0:
			main.enemies[0].position = main.snake.points[0]
		await _settle()
		drain_guard += 1
	assert(main.state == main.State.GAME_OVER, "lives exhausted end the run")
	assert(drain_guard < 20, "game over arrived without spinning")

	# --- restart clears the run
	var finished_time = main.elapsed
	assert(finished_time > 0.0, "the run recorded its time")
	main._input(_key(KEY_SPACE))
	assert(main.state == main.State.PLAYING, "SPACE restarts")
	assert(main.elapsed < finished_time, "restart clears the clock")
	assert(main.lives == 3 and main.score == 0, "restart clears lives and score")
	assert(main.snake.get_point_count() == main.snake.START_SEGMENTS, "restart resets the body")

	# --- music phase mapping, driven without the addon installed
	var recorder = Recorder.new()
	main.music.queue_free()
	main.music = recorder
	main.add_child(recorder)

	# A fresh run is one music generation, seeded per run.
	main.start_run()
	assert(main.state == main.State.PLAYING, "the run restarted through the recorder")
	assert(recorder.runs.size() == 1, "music is generated once per run")
	assert(not str(recorder.runs[0]).is_empty(), "the run seed is not empty")

	# Home phase follows pressure. Checked with no enemies on the field, since a
	# nearby enemy is supposed to take over.
	main.elapsed = 0.0
	main.snake.reset_body(main.arena.bounds)
	main.clear_enemies()
	main.difficulty = main.RunScript.get_difficulty(main.elapsed, main.snake.get_slowness())
	recorder.states.clear()
	main.update_music_state()
	assert(recorder.states[0][0] == "explore", "an early run sits in explore")

	main.elapsed = 300.0
	main.difficulty = main.RunScript.get_difficulty(main.elapsed, main.snake.get_slowness())
	recorder.states.clear()
	main.update_music_state()
	assert(recorder.states[0][0] == "dungeon", "a late run sits in dungeon")
	assert(main.difficulty.pressure >= main.RunScript.BOSS_PRESSURE, "pressure is boss-deep")

	# something on the snake takes over, and deep pressure escalates to boss
	main._apply_difficulty()
	assert(main.enemies.size() > 0, "a late run fields a pack")
	main.enemies[0].position = main.snake.points[0]
	recorder.states.clear()
	main.update_music_state()
	assert(recorder.states[0][0] == "combat", "a close enemy switches to combat")
	assert(recorder.states[0][2] >= 0.85, "boss escalation carries enough threat")

	# gorging while clear is the sanctuary moment
	main.elapsed = 0.0
	main.clear_enemies()
	main.snake.grow(500)
	main.difficulty = main.RunScript.get_difficulty(main.elapsed, main.snake.get_slowness())
	recorder.states.clear()
	main.update_music_state()
	assert(recorder.states[0][0] == "sanctuary", "a gorged, clear snake reaches sanctuary")


	print("SMOKE TEST PASSED")
	quit()
