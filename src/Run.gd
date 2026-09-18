extends RefCounted

# One endless run. Pressure climbs with elapsed time AND with how much the snake
# has eaten, so neither camping nor greed is safe: a careful player still faces
# a rising hunt, and a greedy one accelerates it.
const BASE_SPEED := 340.0

const SECONDS_PER_PRESSURE := 25.0
const GREED_PRESSURE := 6.0
const PRESSURE_PER_ENEMY := 1.5
const MAX_ENEMIES := 12
const BASE_ENEMY_SPEED := 90.0
const ENEMY_SPEED_PER_PRESSURE := 12.0
const MAX_ENEMY_SPEED := 300.0
const THREAT_PRESSURE := 10.0

# Music thresholds, read by the scene so the numbers live in one place.
const DARK_PRESSURE := 3.0
const DUNGEON_PRESSURE := 5.0
const BOSS_PRESSURE := 12.0


class Difficulty:
	var pressure := 0.0
	var enemy_count := 0
	var enemy_speed := 0.0
	var threat := 0.0
	var style := "folk"
	var energy := 0.0
	var complexity := 0.0
	var brightness := 0.0
	var syncopation := 0.0


static func get_difficulty(elapsed: float, greed: float) -> Difficulty:
	var pressure = elapsed / SECONDS_PER_PRESSURE + greed * GREED_PRESSURE
	var difficulty = Difficulty.new()
	difficulty.pressure = pressure
	difficulty.enemy_count = clampi(int(pressure / PRESSURE_PER_ENEMY), 0, MAX_ENEMIES)
	difficulty.enemy_speed = clampf(
		BASE_ENEMY_SPEED + pressure * ENEMY_SPEED_PER_PRESSURE,
		BASE_ENEMY_SPEED, MAX_ENEMY_SPEED
	)
	difficulty.threat = clampf(pressure / THREAT_PRESSURE, 0.0, 1.0)
	difficulty.style = style_for(pressure)
	# Adventure reads these as danger / mystery / wonder / motion.
	difficulty.energy = clampf(0.2 + pressure * 0.07, 0.0, 1.0)
	difficulty.complexity = clampf(0.2 + pressure * 0.06, 0.0, 1.0)
	difficulty.brightness = clampf(0.8 - pressure * 0.06, 0.0, 1.0)
	difficulty.syncopation = clampf(0.2 + pressure * 0.07, 0.0, 1.0)
	return difficulty


static func style_for(pressure: float) -> String:
	if pressure < DARK_PRESSURE:
		return "folk"
	return "dark" if pressure < DUNGEON_PRESSURE else "orchestral"


static func format_time(seconds: float) -> String:
	var whole = int(seconds)
	return "%d:%02d" % [whole / 60, whole % 60]
