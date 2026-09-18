extends SceneTree
# Covers the music layer's addon-present path with a stub player, so it runs
# without the real Gamestruments addon installed.
#
#     godot --headless -s tests/music_stub_test.gd
#
# ClassDB.class_exists() only sees native/GDExtension classes, so the stub
# replaces the instantiation seam rather than registering a global class.

class Stub extends Node:
	var project_secret := ""
	var recipe := ""
	var style := ""
	var energy := 0.0
	var complexity := 0.0
	var brightness := 0.0
	var syncopation := 0.0
	var seed_used := ""
	var states := []
	var allow_generate := true

	func generate(seed: String) -> bool:
		if not allow_generate or project_secret == "" or recipe == "":
			return false
		seed_used = seed
		return true

	func set_adventure_state(area_phase: String, discovery: float, threat: float, quest_complete: bool) -> bool:
		if seed_used == "":
			return false
		states.append([area_phase, discovery, threat, quest_complete])
		return true

class TestMusic extends "res://src/MusicManager.gd":
	func _create_player():
		return Stub.new()


# The addon ships with the repo, so "not installed" is simulated rather than
# assumed, or the test would flip meaning depending on the environment.
class NoAddonMusic extends "res://src/MusicManager.gd":
	func _create_player():
		return null

func _init():
	# Absent addon: the layer must be a silent no-op.
	var absent = NoAddonMusic.new()
	root.add_child(absent)
	await process_frame
	assert(absent.player == null, "no player when the addon is missing")
	absent.start_run("level-1", "folk", 0.2, 0.2, 0.8, 0.2)
	absent.update_state("explore", 0.1, 0.1, false)
	assert(not absent.is_generated, "nothing generated without the addon")

	# Present addon (stub): properties, seed and states must round-trip.
	var mm = TestMusic.new()
	root.add_child(mm)
	await process_frame
	assert(mm.player != null, "stub player instantiated")
	var p = mm.player
	assert(p.project_secret == "snake-simulation", "project_secret set")
	assert(p.recipe == "adventure", "adventure recipe set")

	mm.start_run("run-4", "dark", 0.7, 0.7, 0.4, 0.6)
	assert(mm.is_generated, "generate accepted")
	assert(p.seed_used == "run-4", "run seed used")
	assert(p.style == "dark", "style set")
	assert(is_equal_approx(p.energy, 0.7), "energy set")
	assert(is_equal_approx(p.syncopation, 0.6), "syncopation set")

	mm.update_state("combat", 0.5, 0.8, false)
	assert(p.states.size() == 1, "state pushed")
	assert(p.states[0][0] == "combat", "phase pushed")

	# A rejected generate must not leave stale state flowing to the engine.
	p.allow_generate = false
	mm.start_run("run-9", "bogus", 0.5, 0.5, 0.5, 0.5)
	assert(not mm.is_generated, "rejected generate reports false")
	mm.update_state("combat", 0.5, 0.5, false)
	assert(p.states.size() == 1, "no state pushed after a failed generate")

	print("MUSIC STUB TEST PASSED")
	quit()
