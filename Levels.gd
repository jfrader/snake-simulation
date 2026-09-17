extends RefCounted

class LevelConfig:
	var id: String
	var fruit_target: int
	var base_speed: float
	var enemy_count: int
	var enemy_speed: float
	var threat: float
	var style: String
	var energy: float
	var complexity: float
	var brightness: float
	var syncopation: float

static func get_level(level_num: int) -> LevelConfig:
	var cfg = LevelConfig.new()
	cfg.id = "level-" + str(level_num)
	
	if level_num == 1:
		cfg.fruit_target = 3
		cfg.base_speed = 300.0
		cfg.enemy_count = 0
		cfg.enemy_speed = 0.0
		cfg.threat = 0.1
		cfg.style = "folk"
		cfg.energy = 0.2
		cfg.complexity = 0.2
		cfg.brightness = 0.8
		cfg.syncopation = 0.2
	elif level_num == 2:
		cfg.fruit_target = 5
		cfg.base_speed = 350.0
		cfg.enemy_count = 1
		cfg.enemy_speed = 100.0
		cfg.threat = 0.3
		cfg.style = "folk"
		cfg.energy = 0.4
		cfg.complexity = 0.3
		cfg.brightness = 0.7
		cfg.syncopation = 0.3
	elif level_num == 3:
		cfg.fruit_target = 7
		cfg.base_speed = 400.0
		cfg.enemy_count = 2
		cfg.enemy_speed = 120.0
		cfg.threat = 0.5
		cfg.style = "folk"
		cfg.energy = 0.6
		cfg.complexity = 0.5
		cfg.brightness = 0.6
		cfg.syncopation = 0.5
	elif level_num == 4:
		cfg.fruit_target = 10
		cfg.base_speed = 450.0
		cfg.enemy_count = 3
		cfg.enemy_speed = 140.0
		cfg.threat = 0.7
		cfg.style = "dark"
		cfg.energy = 0.7
		cfg.complexity = 0.7
		cfg.brightness = 0.4
		cfg.syncopation = 0.6
	elif level_num == 5:
		cfg.fruit_target = 15
		cfg.base_speed = 500.0
		cfg.enemy_count = 4
		cfg.enemy_speed = 160.0
		cfg.threat = 0.9
		cfg.style = "dark"
		cfg.energy = 0.9
		cfg.complexity = 0.8
		cfg.brightness = 0.2
		cfg.syncopation = 0.8
	else:
		# Endless escalation after the authored levels. Targets and counts are
		# capped so later loops get denser and faster instead of longer and
		# unreadable; speed carries the difficulty once the caps are reached.
		var loop = level_num - 5
		cfg.fruit_target = min(15 + loop * 2, 30)
		cfg.base_speed = min(500.0 + loop * 20.0, 800.0)
		cfg.enemy_count = min(4 + loop, 12)
		cfg.enemy_speed = min(160.0 + loop * 10.0, 300.0)
		cfg.threat = min(1.0, 0.9 + loop * 0.02)
		cfg.style = "dark" if level_num % 2 == 0 else "orchestral"
		cfg.energy = min(1.0, 0.9 + loop * 0.01)
		cfg.complexity = min(1.0, 0.8 + loop * 0.02)
		cfg.brightness = max(0.0, 0.2 - loop * 0.05)
		cfg.syncopation = min(1.0, 0.8 + loop * 0.02)
		
	return cfg
