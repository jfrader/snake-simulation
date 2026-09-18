extends RefCounted

# Level tuning. Difficulty after the authored levels escalates endlessly, but
# targets and counts are capped so later loops get denser and faster instead of
# longer and unreadable; speed carries the difficulty once the caps are reached.
const AUTHORED := [
	{"fruit_target": 8, "base_speed": 300.0, "enemy_count": 0, "enemy_speed": 0.0,
		"threat": 0.1, "style": "folk",
		"energy": 0.2, "complexity": 0.2, "brightness": 0.8, "syncopation": 0.2},
	{"fruit_target": 12, "base_speed": 350.0, "enemy_count": 1, "enemy_speed": 100.0,
		"threat": 0.3, "style": "folk",
		"energy": 0.4, "complexity": 0.3, "brightness": 0.7, "syncopation": 0.3},
	{"fruit_target": 16, "base_speed": 400.0, "enemy_count": 2, "enemy_speed": 120.0,
		"threat": 0.5, "style": "folk",
		"energy": 0.6, "complexity": 0.5, "brightness": 0.6, "syncopation": 0.5},
	{"fruit_target": 20, "base_speed": 450.0, "enemy_count": 3, "enemy_speed": 140.0,
		"threat": 0.7, "style": "dark",
		"energy": 0.7, "complexity": 0.7, "brightness": 0.4, "syncopation": 0.6},
	{"fruit_target": 24, "base_speed": 500.0, "enemy_count": 4, "enemy_speed": 160.0,
		"threat": 0.9, "style": "dark",
		"energy": 0.9, "complexity": 0.8, "brightness": 0.2, "syncopation": 0.8},
]

const MAX_FRUIT_TARGET := 40
const MAX_BASE_SPEED := 800.0
const MAX_ENEMY_COUNT := 12
const MAX_ENEMY_SPEED := 300.0
const ESCALATION_STEP := 5


class LevelConfig:
	var id := ""
	var fruit_target := 0
	var base_speed := 0.0
	var enemy_count := 0
	var enemy_speed := 0.0
	var threat := 0.0
	var style := ""
	var energy := 0.0
	var complexity := 0.0
	var brightness := 0.0
	var syncopation := 0.0


static func get_level(level_num: int) -> LevelConfig:
	var tuning = AUTHORED[level_num - 1] if level_num <= AUTHORED.size() else _escalated(level_num)
	var config = LevelConfig.new()
	config.id = "level-" + str(level_num)
	config.fruit_target = tuning["fruit_target"]
	config.base_speed = tuning["base_speed"]
	config.enemy_count = tuning["enemy_count"]
	config.enemy_speed = tuning["enemy_speed"]
	config.threat = tuning["threat"]
	config.style = tuning["style"]
	config.energy = tuning["energy"]
	config.complexity = tuning["complexity"]
	config.brightness = tuning["brightness"]
	config.syncopation = tuning["syncopation"]
	return config


static func _escalated(level_num: int) -> Dictionary:
	var loop = level_num - ESCALATION_STEP
	return {
		"fruit_target": mini(24 + loop * 2, MAX_FRUIT_TARGET),
		"base_speed": minf(500.0 + loop * 20.0, MAX_BASE_SPEED),
		"enemy_count": mini(4 + loop, MAX_ENEMY_COUNT),
		"enemy_speed": minf(160.0 + loop * 10.0, MAX_ENEMY_SPEED),
		"threat": minf(1.0, 0.9 + loop * 0.02),
		"style": "dark" if level_num % 2 == 0 else "orchestral",
		"energy": minf(1.0, 0.9 + loop * 0.01),
		"complexity": minf(1.0, 0.8 + loop * 0.02),
		"brightness": maxf(0.0, 0.2 - loop * 0.05),
		"syncopation": minf(1.0, 0.8 + loop * 0.02),
	}
