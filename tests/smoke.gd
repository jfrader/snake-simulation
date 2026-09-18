extends SceneTree

const Save = preload("res://src/Save.gd")
# The suite plays a full run through to game over, and the game saves its record
# on the way out. Point the whole game at a throwaway file so a test run can
# never become the player's best.
const TEST_SAVE := "user://snake_test_best.cfg"


func _read_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)
# End-to-end test of one endless run against the real scene: real _process, real
# polygon collision, hunger, the difficulty curve, and the music phase mapping.
#
#     godot --headless -s tests/smoke.gd

class Recorder extends Node:
	var cues := []
	var runs := []

	func start_menu():
		pass

	func start_run(seed, _style, _energy, _complexity, _brightness, _syncopation):
		runs.append(seed)

	func cue(section):
		if not str(section).is_empty():
			cues.append(section)

	func get_section():
		return cues.back() if cues.size() > 0 else ""


func _key(code: int) -> InputEventKey:
	var event = InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event


func _settle(frames: int = 2) -> void:
	for i in range(frames):
		await process_frame


func _init():
	# Captured before anything runs, so the end of the test can prove the real
	# record was never touched.
	var real_save_before = _read_file(Save.PATH)

	var main = load("res://scene.tscn").instantiate()
	# Set before _ready, so the scene loads and saves through the test path.
	main.save_path = TEST_SAVE
	root.add_child(main)
	current_scene = main
	await _settle()

	# --- boots in the menu
	assert(main.state == main.State.MENU, "boots to MENU")
	assert(not main.snake.visible, "snake hidden in the menu")

	# --- the addon ships with the repo; if the extension loaded, music must wire
	if ClassDB.class_exists("GamestrumentsPlayer"):
		assert(main.music.player != null, "music wired to the vendored addon")
		assert(main.music.is_generated, "menu music generated")
		assert(main._last_cue == "camp", "menu cues the camp section")

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
	assert(is_equal_approx(main.snake.get_larder_ratio(), 1.0), "a maxed snake has a full larder")

	# --- the body is a distance-constrained rope: no gaps, no inversions
	main.start_run()
	main.snake.grow(20)
	await _settle(30)
	var chain = main.snake.points
	assert(chain.size() > 20, "the rope has the grown length")
	# The solved chain is exact: that is what makes the motion stable.
	main.snake._solve_body()
	var solved = main.snake._chain
	var worst = 0.0
	for i in range(1, solved.size()):
		worst = maxf(worst, absf(solved[i].distance_to(solved[i - 1]) - main.snake.LINK_LENGTH))
	assert(worst < 0.01, "the solved chain holds its links exactly (worst %.4f)" % worst)

	# The drawn line adds the wave on top, so it may sit slightly off nominal but
	# must never gap or collapse.
	var shortest = INF
	var longest = 0.0
	for i in range(1, chain.size()):
		var link = chain[i].distance_to(chain[i - 1])
		shortest = minf(shortest, link)
		longest = maxf(longest, link)
	var slack = main.snake.width * main.snake.WAVE_AMPLITUDE_RATIO * 2.0 + 0.2
	assert(shortest > main.snake.LINK_LENGTH - slack, "no drawn link collapses (%.3f)" % shortest)
	assert(longest < main.snake.LINK_LENGTH + slack, "no drawn link stretches (%.3f)" % longest)

	var centroid = Vector2.ZERO
	for i in range(1, chain.size()):
		centroid += chain[i]
	centroid /= float(chain.size() - 1)
	assert(centroid.x < chain[0].x, "the body trails the head")

	# --- the HUD readout carries everything the panel draws
	var readout = main._readout()
	for key in ["time", "score", "lives", "length", "larder", "speed", "speed_bar", "starving", "best"]:
		assert(readout.has(key), "readout has " + key)
	assert(
		readout["starving"] == (readout["length"] <= main.snake.MIN_SEGMENTS + main.STARVING_MARGIN),
		"the starving flag matches the larder"
	)

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
	assert(is_equal_approx(main.snake.get_larder_ratio(), 1.0), "snake is at a full larder")
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

	# --- ending the run is idempotent, and nothing keeps playing afterwards
	var lives_at_end = main.lives
	assert(main.enemies.is_empty(), "the field is cleared when the run ends")
	await _settle(10)
	assert(main.enemies.is_empty(), "no enemies appear while the run is over")
	assert(not main.sfx.slither_player.playing, "the movement bed is stopped")

	main.game_over()
	assert(main.lives == lives_at_end, "a second game_over does not run the run down again")
	main.take_damage()
	assert(main.lives == lives_at_end, "damage after the run ends is ignored")
	main._starve()
	assert(main.lives == lives_at_end, "starving after the run ends is ignored")

	# --- restart clears the run
	var finished_time = main.elapsed
	assert(finished_time > 0.0, "the run recorded its time")
	main._input(_key(KEY_SPACE))
	assert(main.state == main.State.PLAYING, "SPACE restarts")
	assert(main.elapsed < finished_time, "restart clears the clock")
	assert(main.lives == 3 and main.score == 0, "restart clears lives and score")
	assert(main.snake.get_point_count() == main.snake.START_SEGMENTS, "restart resets the body")

	# --- sound effects are synthesized with real data
	assert(main.sfx.eat_player.stream.data.size() > 0, "eat blip has samples")
	assert(main.sfx.death_player.stream.data.size() > 0, "death sweep has samples")
	var slither = main.sfx.slither_player.stream
	assert(slither.data.size() > 0, "movement bed has samples")
	assert(slither.loop_mode == AudioStreamWAV.LOOP_FORWARD, "movement bed loops")
	assert(slither.loop_end == slither.data.size() / 2, "loop end matches the data")
	assert(slither.loop_end > slither.loop_begin, "loop region is valid")
	# Seam check: the step across the loop point must not be an outlier compared
	# with the steps inside the buffer, or it clicks every time round.
	var frames = slither.loop_end
	var biggest_step = 0
	for i in range(1, frames):
		biggest_step = maxi(biggest_step, absi(slither.data.decode_s16(i * 2) - slither.data.decode_s16((i - 1) * 2)))
	var seam_step = absi(slither.data.decode_s16(0) - slither.data.decode_s16((frames - 1) * 2))
	assert(seam_step <= biggest_step, "the loop seam is no worse than any internal step (seam %d, worst %d)" % [seam_step, biggest_step])

	# the bed follows the playfield being live
	main.go_to_menu()
	assert(not main.sfx.slither_player.playing, "the bed is silent in the menu")
	main.start_run()
	await _settle()
	assert(main.sfx.slither_player.playing, "the bed runs during play")
	main.set_paused(true)
	assert(not main.sfx.slither_player.playing, "the bed stops on pause")
	main.set_paused(false)
	assert(main.sfx.slither_player.playing, "the bed resumes")

	# eating and dying actually fire their sounds
	main.food.position = main.snake.points[0]
	await _settle()
	assert(main.sfx.eat_player.playing, "eating plays a sound")
	# dying goes through the real path, not a direct call
	main.snake.is_invulnerable = false
	main.lives = 1
	main.take_damage()
	assert(main.state == main.State.GAME_OVER, "the last life ends the run")
	assert(main.sfx.death_player.playing, "dying plays a sound")
	assert(not main.sfx.slither_player.playing, "the bed stops when the run ends")

	# --- the music is not fed a near-zero, always-the-same palette
	var opening = main.RunScript.get_difficulty(0.0, 0.0)
	assert(is_equal_approx(opening.energy, 0.62), "energy opens at the kit's own default")
	assert(is_equal_approx(opening.complexity, 0.60), "complexity opens at the kit's own default")
	assert(is_equal_approx(opening.brightness, 0.52), "brightness opens at the kit's own default")
	assert(is_equal_approx(opening.syncopation, 0.70), "syncopation opens at the kit's own default")

	# and they climb (or fall, for brightness) as pressure rises
	var deep = main.RunScript.get_difficulty(400.0, 1.0)
	assert(deep.pressure > opening.pressure, "deep pressure is actually deeper")
	assert(deep.energy > opening.energy, "energy rises with pressure")
	assert(deep.complexity > opening.complexity, "complexity rises with pressure")
	assert(deep.syncopation > opening.syncopation, "motion rises with pressure")
	assert(deep.brightness < opening.brightness, "wonder falls as it gets dangerous")
	# `trait` is a reserved word in GDScript 4, hence `cfg`.
	for cfg in [opening, deep]:
		assert(cfg.energy >= 0.0 and cfg.energy <= 1.0, "energy stays in range")
		assert(cfg.complexity >= 0.0 and cfg.complexity <= 1.0, "complexity stays in range")
		assert(cfg.brightness >= 0.0 and cfg.brightness <= 1.0, "brightness stays in range")
		assert(cfg.syncopation >= 0.0 and cfg.syncopation <= 1.0, "syncopation stays in range")

	# the rotation is pinned, and never parks a run in the calm style the menu uses
	var rotation = []
	var seen_styles = {}
	for i in range(main.RunScript.RUN_STYLES.size() * 2):
		var style = main.RunScript.style_for_run(i)
		rotation.append(style)
		seen_styles[style] = true
	assert(
		seen_styles.size() == main.RunScript.RUN_STYLES.size(),
		"the rotation reaches every run style (saw %s)" % [seen_styles.keys()]
	)
	assert(not seen_styles.has(main.MusicScript.MENU_STYLE),
		"no run is generated in the menu's calm style")
	assert(rotation.slice(0, main.RunScript.RUN_STYLES.size()) == main.RunScript.RUN_STYLES,
		"the rotation cycles in order (got %s)" % [rotation])

	# --- the best run persists, and beats are judged on time first
	Save.save_best(61.5, 42, TEST_SAVE)
	var reloaded = Save.load_best(TEST_SAVE)
	assert(is_equal_approx(reloaded["time"], 61.5), "best time persists")
	assert(reloaded["score"] == 42, "best score persists")
	assert(Save.is_better(62.0, 0, reloaded), "a longer run beats the record")
	assert(not Save.is_better(61.5, 41, reloaded), "a shorter, lower-scoring run does not")
	assert(Save.is_better(61.5, 43, reloaded), "equal time with more score beats the record")
	assert(Save.format_best(reloaded).contains("1:01"), "the best line formats the time")

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

	# --- music cues: only on a change, and a section is never restarted
	main.elapsed = 0.0
	main.snake.reset_body(main.arena.bounds)
	main.clear_enemies()
	main.difficulty = main.RunScript.get_difficulty(main.elapsed, main.snake.get_larder_ratio())
	recorder.cues.clear()
	for i in range(30):
		main.update_music_state()
	assert(recorder.cues.is_empty(), "a calm, clear run cues nothing")
	assert(main._last_cue == "", "no section is requested while calm")

	# distant enemies are not an event
	main.elapsed = 120.0
	main.difficulty = main.RunScript.get_difficulty(main.elapsed, main.snake.get_larder_ratio())
	main._apply_difficulty()
	assert(main.enemies.size() > 0, "a mid run fields enemies")
	for enemy in main.enemies:
		enemy.position = Vector2(-9999, -9999)
	recorder.cues.clear()
	main.update_music_state()
	assert(recorder.cues.is_empty(), "distant enemies cue nothing")

	# an enemy on the snake cues the pursuit section
	main.enemies[0].position = main.snake.points[0]
	recorder.cues.clear()
	main.update_music_state()
	assert(recorder.cues.size() == 1 and recorder.cues[0] == "chase",
		"a close enemy cues chase (got %s)" % [recorder.cues])

	# the whole point: repeating the same situation must NOT re-cue, or the
	# section restarts on every bar instead of transitioning
	recorder.cues.clear()
	for i in range(60):
		main.enemies[0].position = main.snake.points[0]
		main.update_music_state()
	assert(recorder.cues.is_empty(), "an unchanged situation does not re-cue")

	# escaping re-arms the cue
	main.enemies[0].position = Vector2(-9999, -9999)
	main.update_music_state()
	main.enemies[0].position = main.snake.points[0]
	recorder.cues.clear()
	main.update_music_state()
	assert(recorder.cues.size() == 1 and recorder.cues[0] == "chase",
		"the same cue fires again after the situation clears")

	# deep pressure while engaged escalates to boss
	main.elapsed = 400.0
	main.difficulty = main.RunScript.get_difficulty(main.elapsed, main.snake.get_larder_ratio())
	main.enemies[0].position = Vector2(-9999, -9999)
	main.update_music_state()   # clears the cue so the next one can fire
	main.enemies[0].position = main.snake.points[0]
	recorder.cues.clear()
	main.update_music_state()
	assert(main.difficulty.pressure >= main.RunScript.BOSS_PRESSURE, "pressure is boss-deep")
	assert(recorder.cues.size() == 1 and recorder.cues[0] == "boss",
		"deep pressure while engaged cues boss (got %s)" % [recorder.cues])

	# gorging while clear is the sanctuary moment
	main.elapsed = 0.0
	main.clear_enemies()
	main.snake.grow(500)
	main.difficulty = main.RunScript.get_difficulty(main.elapsed, main.snake.get_larder_ratio())
	main.enemies.clear()
	recorder.cues.clear()
	main.update_music_state()
	assert(recorder.cues.size() == 1 and recorder.cues[0] == "sanctuary",
		"a gorged, clear snake cues sanctuary (got %s)" % [recorder.cues])

	# Tear the scene down while the tree is still alive: quitting with audio in
	# flight leaves playback objects to the audio thread and reports them as
	# leaked, which would be a noisy signal rather than a real one.
	main.sfx.release()
	# The audio server retires playback objects on its own thread; give it frames
	# while the tree is still alive, or exiting can report them as leaked.
	await _settle(15)
	main.queue_free()
	await _settle(15)

	# --- the suite must never write its own run into the player's record
	assert(
		_read_file(Save.PATH) == real_save_before,
		"the suite leaves the player's real save untouched"
	)
	assert(FileAccess.file_exists(TEST_SAVE), "the run's record went to the test path")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))

	print("SMOKE TEST PASSED")
	quit()
