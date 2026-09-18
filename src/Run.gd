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
const BOSS_PRESSURE := 12.0

# Trait baselines. They begin at the kit's own defaults rather than near zero,
# so a fresh run already has some life in it, and climb with pressure.
const TRAIT_ENERGY := 0.62
const TRAIT_ENERGY_CLIMB := 0.035
const TRAIT_COMPLEXITY := 0.60
const TRAIT_COMPLEXITY_CLIMB := 0.03
const TRAIT_BRIGHTNESS := 0.52
const TRAIT_BRIGHTNESS_FALL := 0.03
const TRAIT_SYNCOPATION := 0.70
const TRAIT_SYNCOPATION_CLIMB := 0.025

# Styles a run may be generated in, cycled by run index. Style is fixed at
# generate time and a run generates once, so mapping it from pressure meant
# every run was the calm `folk`; runs never use `folk`, so no run is parked in
# the calm style, and consecutive runs differ.
const RUN_STYLES := ["dark", "orchestral"]


class Difficulty:
	var pressure := 0.0
	var enemy_count := 0
	var enemy_speed := 0.0
	var threat := 0.0
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
	# Adventure reads these as danger / mystery / wonder / motion. They start at
	# the kit's own defaults (energy 0.62, complexity 0.60, brightness 0.52,
	# syncopation 0.70) and climb from there; the earlier 0.2 baseline fed the
	# composer about a third of its intended energy, which is what made it dull.
	difficulty.energy = clampf(TRAIT_ENERGY + pressure * TRAIT_ENERGY_CLIMB, 0.0, 1.0)
	difficulty.complexity = clampf(TRAIT_COMPLEXITY + pressure * TRAIT_COMPLEXITY_CLIMB, 0.0, 1.0)
	difficulty.brightness = clampf(TRAIT_BRIGHTNESS - pressure * TRAIT_BRIGHTNESS_FALL, 0.0, 1.0)
	difficulty.syncopation = clampf(TRAIT_SYNCOPATION + pressure * TRAIT_SYNCOPATION_CLIMB, 0.0, 1.0)
	return difficulty


# The style a run is generated in. Deterministic per run index so a re-roll is
# a real re-roll, and deliberately avoids parking every run in the calm one.
static func style_for_run(run_index: int) -> String:
	return RUN_STYLES[posmod(run_index, RUN_STYLES.size())]


static func format_time(seconds: float) -> String:
	var whole = int(seconds)
	return "%d:%02d" % [whole / 60, whole % 60]
