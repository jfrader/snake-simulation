extends SceneTree
# Covers the music layer's driving of the addon with a stub player, so it runs
# the same whether or not the real Gamestruments addon is installed.
#
#     godot --headless -s tests/music_stub_test.gd
#
# ClassDB.class_exists() only sees native/GDExtension classes, so the stub
# replaces the instantiation seam rather than registering a global class.

class Stub extends Node:
	var project_secret := ""
	var recipe := ""
	var arrangement := ""
	var autoplay := false
	var style := ""
	var energy := 0.0
	var complexity := 0.0
	var brightness := 0.0
	var syncopation := 0.0
	var seed_used := ""
	var cues := []
	var allow_generate := true
	var allow_cue := true

	func generate(seed: String) -> bool:
		if not allow_generate or project_secret == "" or recipe == "":
			return false
		seed_used = seed
		return true

	func cue_section(section: String) -> bool:
		if not allow_cue or seed_used == "":
			return false
		cues.append(section)
		return true

	func get_current_section() -> String:
		return cues.back() if cues.size() > 0 else ""


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
	absent.start_menu()
	absent.start_run("run-1", "folk", 0.2, 0.2, 0.8, 0.2)
	absent.cue("chase")
	assert(not absent.is_generated, "nothing generated without the addon")
	assert(absent.get_section() == "", "no section without the addon")

	# Present addon (stub): properties, seed, cue forwarding.
	var mm = TestMusic.new()
	root.add_child(mm)
	await process_frame
	assert(mm.player != null, "stub player instantiated")
	var p = mm.player
	assert(p.project_secret == "snake-simulation", "project_secret set")
	assert(p.recipe == "adventure", "adventure recipe set")

	# Menu: a single calm section, no touring form.
	mm.start_menu()
	assert(mm.is_generated, "menu music generated")
	assert(p.autoplay == false, "the menu does not attach a touring form")
	assert(p.style == "folk", "menu style set")
	assert(p.cues == ["camp"], "the menu cues camp (got %s)" % [p.cues])

	# Run: a seeded touring form, so the music is not parked in one section.
	p.cues.clear()
	mm.start_run("run-4", "dark", 0.7, 0.7, 0.4, 0.6)
	assert(mm.is_generated, "run music generated")
	assert(p.seed_used == "run-4", "run seed used")
	assert(p.arrangement == "seeded", "the run uses the seeded arrangement")
	assert(p.autoplay == true, "the run attaches a touring form")
	assert(p.style == "dark", "run style set")
	assert(is_equal_approx(p.energy, 0.7), "energy set")
	assert(is_equal_approx(p.syncopation, 0.6), "syncopation set")
	assert(p.cues.is_empty(), "starting a run cues nothing by itself")

	# Cues are forwarded, and an empty section is not a request.
	mm.cue("chase")
	mm.cue("")
	mm.cue("sanctuary")
	assert(p.cues == ["chase", "sanctuary"], "cues forwarded, empty skipped (got %s)" % [p.cues])
	assert(mm.get_section() == "sanctuary", "current section is readable")

	# A rejected cue warns but must not wedge the layer.
	p.allow_cue = false
	mm.cue("boss")
	assert(p.cues == ["chase", "sanctuary"], "a rejected cue is not recorded")

	# A rejected generate must not leave stale music flowing.
	p.allow_generate = false
	p.allow_cue = true
	mm.start_run("run-9", "bogus", 0.5, 0.5, 0.5, 0.5)
	assert(not mm.is_generated, "rejected generate reports false")
	mm.cue("combat")
	assert(p.cues == ["chase", "sanctuary"], "no cue is sent after a failed generate")

	print("MUSIC STUB TEST PASSED")
	quit()
