extends Node

# The Gamestruments addon is optional. Everything here no-ops while its
# `GamestrumentsPlayer` class is missing, so the game runs silent and clean and
# simply starts making music once the addon is installed.
const PROJECT_SECRET := "snake-simulation"
const RECIPE := "adventure"
const MENU_SEED := "snake-menu"
const MENU_SECTION := "camp"

# Driving a run the kit's way:
#
# - `arrangement = "seeded"` + `autoplay = true` attaches a song form the
#   composer builds from the run's seed, so the music tours sections by itself
#   and two runs do not sound alike. Without the form it would sit in whichever
#   section was last requested.
# - Gameplay input is `cue_section`, which works with or without a form and
#   commits on a bar boundary. The scene only cues when the situation actually
#   CHANGES, so a section is allowed to play out instead of being restarted
#   every bar.
const RUN_ARRANGEMENT := "seeded"
const RUN_AUTOPLAY := true

var player: Node = null
var is_generated := false


func _create_player() -> Node:
	# ClassDB only knows native/GDExtension classes, which is exactly what the
	# addon registers. Overridden by tests to inject a stub.
	if not ClassDB.class_exists("GamestrumentsPlayer"):
		return null
	var instance = ClassDB.instantiate("GamestrumentsPlayer")
	if instance == null or not instance.has_method("generate") or not instance.has_method("cue_section"):
		return null
	return instance


# Drop the addon node while we can. NOTE: freeing it here is correct hygiene but
# does NOT clear the AudioStreamGeneratorPlayback that Godot reports as leaked at
# exit; that reference is held inside the extension and survives the node. The
# window-close path below is the best a consumer can do. Reported as GURI-942.
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


func _apply_traits(style_name: String, energy: float, complexity: float,
		brightness: float, syncopation: float) -> void:
	player.set("style", style_name)
	player.set("energy", energy)
	player.set("complexity", complexity)
	player.set("brightness", brightness)
	player.set("syncopation", syncopation)


# The title screen is one calm section, no form.
func start_menu() -> void:
	if player == null:
		return
	player.set("arrangement", "all-phases")
	player.set("autoplay", false)
	_apply_traits("folk", 0.2, 0.25, 0.75, 0.3)
	is_generated = player.call("generate", MENU_SEED)
	if not is_generated:
		push_warning("Gamestruments: failed to generate menu music")
		return
	cue(MENU_SECTION)


# A run gets its own score and its own touring form.
func start_run(seed: String, style_name: String, energy: float, complexity: float,
		brightness: float, syncopation: float) -> void:
	if player == null:
		return
	player.set("arrangement", RUN_ARRANGEMENT)
	player.set("autoplay", RUN_AUTOPLAY)
	_apply_traits(style_name, energy, complexity, brightness, syncopation)
	is_generated = player.call("generate", seed)
	if not is_generated:
		push_warning("Gamestruments: failed to generate music for " + seed)


# Requests a section, committing on the next bar. The SCENE decides when the
# situation has changed and calls this only then: a cue restarts a section, so
# calling it every frame would restart the music every bar.
func cue(section: String) -> void:
	if player == null or not is_generated or section.is_empty():
		return
	var accepted = player.call("cue_section", section)
	if accepted != null and not accepted:
		push_warning("Gamestruments: cue_section rejected for " + section)


func get_section() -> String:
	if player == null or not is_generated:
		return ""
	return str(player.call("get_current_section"))
