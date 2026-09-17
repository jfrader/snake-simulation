extends Node

var player = null
var current_level_id = ""
var is_generated = false

# The addon is optional: this whole layer no-ops when Gamestruments is not
# installed. Detection must not depend on the gameplay scripts.
func _create_player():
	if not ClassDB.class_exists("GamestrumentsPlayer"):
		return null
	var instance = ClassDB.instantiate("GamestrumentsPlayer")
	if instance == null or not instance.has_method("generate") or not instance.has_method("set_adventure_state"):
		return null
	return instance

func _ready():
	player = _create_player()
	if player == null:
		return
	player.name = "GamestrumentsPlayer"
	add_child(player)
	# Object.set() returns void, so it cannot be checked; verify via get().
	player.set("project_secret", "snake-simulation")
	player.set("recipe", "adventure")
	if player.get("project_secret") != "snake-simulation":
		push_warning("Gamestruments: project_secret was not accepted")

func start_level(level_id, style_name, energy, complexity, brightness, syncopation):
	if not player: return
	
	player.set("style", style_name)
	player.set("energy", energy)
	player.set("complexity", complexity)
	player.set("brightness", brightness)
	player.set("syncopation", syncopation)
	
	current_level_id = level_id
	is_generated = player.call("generate", level_id)
	
	if not is_generated:
		push_warning("Gamestruments: failed to generate music for " + level_id)

func update_state(area_phase: String, discovery: float, threat: float, quest_complete: bool):
	if not player or not is_generated: return
	var success = player.call("set_adventure_state", area_phase, discovery, threat, quest_complete)
	if success != null and not success:
		push_warning("Failed to set adventure state")
