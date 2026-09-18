extends Node

# The Gamestruments addon is optional. Everything here no-ops while its
# `GamestrumentsPlayer` class is missing, so the game runs silent and clean and
# simply starts making music once the addon is installed.
const PROJECT_SECRET := "snake-simulation"
const RECIPE := "adventure"
const MENU_SEED := "snake-menu"

var player: Node = null
var is_generated := false


func _create_player() -> Node:
	# ClassDB only knows native/GDExtension classes, which is exactly what the
	# addon registers. Overridden by tests to inject a stub.
	if not ClassDB.class_exists("GamestrumentsPlayer"):
		return null
	var instance = ClassDB.instantiate("GamestrumentsPlayer")
	if instance == null or not instance.has_method("generate") or not instance.has_method("set_adventure_state"):
		return null
	return instance


# Drop the addon node while we can. NOTE: freeing it here is correct hygiene but
# does NOT clear the AudioStreamGeneratorPlayback that Godot reports as leaked at
# exit; that reference is held inside the extension and survives the node. The
# window-close path below is the best a consumer can do. Reported upstream.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_release_player()


func _exit_tree() -> void:
	_release_player()


func _release_player() -> void:
	if player == null:
		return
	remove_child(player)
	player.free()
	player = null
	is_generated = false


func _ready() -> void:
	player = _create_player()
	if player == null:
		return
	player.name = "GamestrumentsPlayer"
	add_child(player)
	# Object.set() returns void, so it cannot be checked; verify via get().
	player.set("project_secret", PROJECT_SECRET)
	player.set("recipe", RECIPE)
	if player.get("project_secret") != PROJECT_SECRET:
		push_warning("Gamestruments: project_secret was not accepted")


# The title screen gets its own bed so the game is not silent before a run.
func start_menu() -> void:
	if player == null:
		return
	player.set("style", "folk")
	player.set("energy", 0.2)
	player.set("complexity", 0.25)
	player.set("brightness", 0.75)
	player.set("syncopation", 0.3)
	is_generated = player.call("generate", MENU_SEED)
	if not is_generated:
		push_warning("Gamestruments: failed to generate menu music")


func start_run(seed: String, style_name: String, energy: float, complexity: float,
		brightness: float, syncopation: float) -> void:
	if player == null:
		return
	player.set("style", style_name)
	player.set("energy", energy)
	player.set("complexity", complexity)
	player.set("brightness", brightness)
	player.set("syncopation", syncopation)

	is_generated = player.call("generate", seed)
	if not is_generated:
		push_warning("Gamestruments: failed to generate music for " + seed)


func update_state(area_phase: String, discovery: float, threat: float, quest_complete: bool) -> void:
	if player == null or not is_generated:
		return
	var accepted = player.call("set_adventure_state", area_phase, discovery, threat, quest_complete)
	if accepted != null and not accepted:
		push_warning("Gamestruments: state request rejected for " + area_phase)
