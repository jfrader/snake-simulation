extends RefCounted

const Run = preload("res://src/Run.gd")

# Best run, kept in user:// so it survives restarts. Local file only, no network.
const PATH := "user://snake_simulation.cfg"
const SECTION := "best"
const KEY_TIME := "time"
const KEY_SCORE := "score"


static func load_best() -> Dictionary:
	var best = {"time": 0.0, "score": 0}
	var config = ConfigFile.new()
	if config.load(PATH) != OK:
		return best
	best["time"] = float(config.get_value(SECTION, KEY_TIME, 0.0))
	best["score"] = int(config.get_value(SECTION, KEY_SCORE, 0))
	return best


static func save_best(elapsed: float, score: int) -> void:
	var config = ConfigFile.new()
	config.load(PATH)
	config.set_value(SECTION, KEY_TIME, elapsed)
	config.set_value(SECTION, KEY_SCORE, score)
	config.save(PATH)


# A run beats the record if it survives longer, or matches the time and scores
# higher. Time is the headline, so it decides first.
static func is_better(elapsed: float, score: int, best: Dictionary) -> bool:
	if elapsed > float(best["time"]):
		return true
	return is_equal_approx(elapsed, float(best["time"])) and score > int(best["score"])


static func format_best(best: Dictionary) -> String:
	return "%s  ·  %d" % [Run.format_time(float(best["time"])), int(best["score"])]
