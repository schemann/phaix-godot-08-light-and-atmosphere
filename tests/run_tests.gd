extends SceneTree
## Headless tests for tutorial 08. From the repository root:
##   godot --headless --path godot/08-light-and-atmosphere -s res://tests/run_tests.gd
## Prints PASS or FAIL per test and exits with 0 only if every test passed.
## `-- --only=text` runs the tests whose name contains the text (for example `-- --only=lamp`).
##
## Saves: every level the tests load gets its own temporary save file (OS temp dir), so a test run never reads or
## writes the real best_times.json.

const Autopilot := preload("res://tools/autopilot.gd")
const Chain := preload("res://steps/step_05_global_illumination/room_chain.gd") ## The finished chain (every step plans the run of step 0).

const STEPS: Array[String] = [
	"step_00_start",
	"step_01_environment",
	"step_02_lamps",
	"step_03_fog",
	"step_04_glow",
	"step_05_global_illumination",
]
const FINAL_STEP := "step_05_global_illumination"
const FIRST_LAMP_STEP := "step_02_lamps"

## What each step changes against the one before (file names under the step folder, props/ included; .uid files do not count).
const CHANGES: Dictionary[String, Dictionary] = {
	"step_01_environment": {changed = ["main.tscn"], added = []},
	"step_02_lamps": {changed = ["level.gd", "room.gd", "room_goal.tscn", "room_long.tscn", "room_straight.tscn", "room_turn_left.tscn", "room_turn_right.tscn", "room_vault.tscn", "room_wide.tscn"], added = ["lamp.gd", "lamp.tscn"]},
	"step_03_fog": {changed = ["main.tscn"], added = []},
	"step_04_glow": {changed = ["main.tscn"], added = []},
	"step_05_global_illumination": {changed = ["door.tscn", "key.tscn", "main.tscn", "player.gd"], added = []},
}

## The actions of tutorial 07 (this tutorial adds no key).
const ACTIONS: Array[String] = [
	"move_forward", "move_back", "move_left", "move_right", "jump", "walk", "look_left", "look_right", "look_up", "look_down",
	"toggle_debug", "regenerate", "next_seed", "edit_seed", "copy_seed", "capture_mouse",
	"toggle_view", "toggle_gizmos", "toggle_watch", "step_generation",
]

## The room scenes by the name of their type, and how many lamp spots each has.
const LAMP_COUNTS: Dictionary[String, int] = {
	"straight": 1, "turn_left": 1, "turn_right": 1, "wide": 2, "long": 2, "vault": 2, "goal": 1,
}

const STATE_FINISHED := 2 ## Level.State
const CEILING_LAYER := 2 ## Render layer 2: the ceilings and lamp blocks (a bit mask value, not the number of the layer).
const SPEED_UP := 4 ## The full runs go this many times faster than real time.
const PLAN_SEEDS := 200 ## Seeds 1..200 for the comparisons between steps.
const TINT_SEEDS := 40 ## Seeds 1..40 whose rooms are checked for their lamp tint.
const LAMP_HEIGHT := 2.6 ## Metres above the floor: where the lamp spots are.
const GRID_STEP := 1.0 ## Metres between the floor points that are checked for a lamp that reaches them.
const RUN_SEED := 53 ## The seed the narration walks: rooms 0 to 5 are straight, left turn, wide, vault, straight, long. None is locked.
const RUN_TO_ROOM := 5
const MOST_LAMPS_IN_RUN := 5 ## Lamps in the tree at once on that walk (the narration says "at most five lamps at once").
const MOST_SHADOW_LAMPS_IN_RUN := 5 ## Of those, the ones with shadows on.
const MOST_LAMPS_ANY_RUN := 7 ## Three rooms stand at once (the one behind, the one the player is in, the one ahead): at most 2 lamps each, and the pad light of the goal room.

## Counts the errors the engine logs. A test that hits a script error stops at that line and the engine hands back an
## empty array, which reads as a pass: `_report` charges the count to the test that ran.
class ScriptErrorCounter extends Logger:
	var count := 0
	var script_only := true ## false: warnings and errors of the engine count, too.
	var _lock := Mutex.new() ## The engine calls a logger from any thread.

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if script_only and error_type != ERROR_TYPE_SCRIPT:
			return
		_lock.lock()
		count += 1
		_lock.unlock()

## Calls its callback once per physics tick, before the player's own tick.
class Driver extends Node:
	signal finished
	var tick: Callable

	func _physics_process(_delta: float) -> void:
		if tick.is_valid() and tick.call():
			tick = Callable()
			finished.emit()

var _passed := 0
var _failed := 0
var _skipped := 0
var _script_errors := ScriptErrorCounter.new() ## Registered with the engine's logger for the whole run.
var _script_errors_reported := 0 ## How many script errors the tests reported so far have been charged with.
var _save_dir := ""
var _save_counter := 0

func _initialize() -> void:
	OS.add_logger(_script_errors)
	await process_frame
	var started := Time.get_ticks_msec()
	_save_dir = OS.get_temp_dir().path_join("phaix-godot-08-tests-%d" % OS.get_process_id()) # one folder per run: two runs at the same time must not wipe each other's save files
	_wipe_save_dir()

	await _run("code rules: no class_name, no global random, no wall clock, input only through named actions", test_code_rules)
	await _run("steps: each step changes only what its concept needs, everything else is copied forward", test_copy_forward)
	await _run("step_00_start: the final state of tutorial 07, file for file (only the folder names differ)", test_step_zero_is_tutorial_07)
	await _run("project: the actions of tutorial 07 and F3, F4 and Enter, render layer 3 is named Body, the main scene is the final step", test_project_settings)
	await _run("hint: the HUD text of step 0 is the HUD text of every step, and the Input Map is the one of tutorial 07", test_hint_unchanged)
	await _run("plans: all six steps plan the run of step 0 (type, place, lock, key, props and lamp tint of seeds 1-%d): lights move nothing" % PLAN_SEEDS, test_steps_plan_the_same)
	for step in STEPS:
		await _run("%s environment: the sky and the sun are gone from step 1 on, fog from 3, glow from 4, SDFGI in 5; each setting is the one the narration names" % step, test_environment.bind(step))
	for step in _steps_from("step_01_environment"):
		await _run("%s lamp spots: the rooms swap their one big light for lamp spots, inside the room, in reach of every part of the floor" % step, test_lamp_spots.bind(step))
	for step in _steps_from(FIRST_LAMP_STEP):
		await _run("%s lamp scene: an omni light with shadows and a fixture on layer 2, set_tint changes the colour and nothing else" % step, test_lamp_scene.bind(step))
		await _run("%s lamps in a run: seed %d to room %d, the most lamps at once, all with shadows, all on a room, none left behind" % [step, RUN_SEED, RUN_TO_ROOM], test_lamps_in_a_run.bind(step))
		await _run("%s lamp tints: every lamp of a room has the tint of its plan (seeds 1-%d, every room type)" % [step, TINT_SEEDS], test_lamp_tints.bind(step))
	for step in STEPS:
		await _run("%s gi mode: the door, the key and the player's body leave SDFGI in step 5 and only there; the rooms stay in" % step, test_gi_modes.bind(step))
	for step in STEPS:
		await _run("%s: a room stays until the door behind it has closed, nothing goes while it stands open" % step, test_rooms_wait_for_the_door.bind(step))
	await _run("full run: seed 42, goal room 20: the autopilot fetches every key and finishes with the body on, never more lamps than three rooms hold", test_full_run)
	await _run("restart: R while running leaves the body standing in room 0, in Move, at blend position 0", test_restart)
	for step in STEPS:
		await _run("%s: main scene runs 30 frames" % step, test_scene_runs.bind(step))

	_wipe_save_dir()
	OS.remove_logger(_script_errors)
	print("\n%d passed, %d failed, %d skipped in %.1f s" % [_passed, _failed, _skipped, (Time.get_ticks_msec() - started) / 1000.0])
	quit(1 if _failed > 0 else 0)

#region Source rules

func test_code_rules() -> Array[String]:
	var failures: Array[String] = []
	var global_random := RegEx.create_from_string("(^|[^.\\w])(randi|randf|randi_range|randf_range|randomize|pick_random)\\(")
	var wall_clock := RegEx.create_from_string("(Time\\.get_|OS\\.get_ticks|OS\\.get_unix|OS\\.delay)")
	var scripts := _files_in("res://steps", ".gd")
	_expect(failures, scripts.size() >= 100, "found only %d scripts under steps" % scripts.size())
	for path in scripts:
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			var line := lines[i].strip_edges()
			if line.begins_with("#"):
				continue
			var where := "%s:%d" % [path.trim_prefix("res://"), i + 1]
			_expect(failures, not line.begins_with("class_name"), "%s: class_name" % where)
			_expect(failures, global_random.search(line) == null, "%s: global random call" % where)
			_expect(failures, wall_clock.search(line) == null, "%s: reads the wall clock" % where)
			_expect(failures, not line.contains("Input.is_key_pressed") and not line.contains("Input.is_physical_key_pressed"), "%s: reads a key directly" % where)
			_expect(failures, not line.contains("event is InputEventKey") and not line.contains("event is InputEventJoypad"), "%s: reads a key or button event directly" % where)
	return failures

## Every file of a folder and its sub folders that ends with the suffix.
func _files_in(dir_path: String, suffix: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	for sub in dir.get_directories():
		found.append_array(_files_in(dir_path.path_join(sub), suffix))
	for file in dir.get_files():
		if file.ends_with(suffix):
			found.append(dir_path.path_join(file))
	return found

func test_copy_forward() -> Array[String]:
	var failures: Array[String] = []
	for i in range(1, STEPS.size()):
		var before := STEPS[i - 1]
		var after := STEPS[i]
		var before_files := _step_files(before)
		var after_files := _step_files(after)
		var changed: Array[String] = []
		var added: Array[String] = []
		for file in before_files:
			if not after_files.has(file):
				failures.append("%s lost %s" % [after, file])
			elif _step_text(before, file) != _step_text(after, file):
				changed.append(file)
		for file in after_files:
			if not before_files.has(file):
				added.append(file)
		changed.sort()
		added.sort()
		var expected: Dictionary = CHANGES[after]
		var expected_changed: Array = expected.changed.duplicate()
		var expected_added: Array = expected.added.duplicate()
		expected_changed.sort()
		expected_added.sort()
		_expect(failures, changed == expected_changed, "%s changes %s, expected %s" % [after, changed, expected_changed])
		_expect(failures, added == expected_added, "%s adds %s, expected %s" % [after, added, expected_added])
	# Fog, glow and global illumination are settings of the Environment: the rest of main.tscn is the one of the step before.
	for after: String in ["step_03_fog", "step_04_glow", FINAL_STEP]:
		var before := STEPS[STEPS.find(after) - 1]
		_expect(failures, _without_environment(_step_text(before, "main.tscn")) == _without_environment(_step_text(after, "main.tscn")), "%s changes more of main.tscn than the Environment" % after)
	return failures

func _step_files(step: String) -> Array[String]:
	var files: Array[String] = []
	for file in DirAccess.get_files_at("res://steps/" + step):
		if not file.ends_with(".uid"):
			files.append(file)
	if DirAccess.dir_exists_absolute("res://steps/%s/props" % step):
		for file in DirAccess.get_files_at("res://steps/%s/props" % step):
			if not file.ends_with(".uid"):
				files.append("props/" + file)
	return files

## The file's text with the step folder name blanked out, so copies compare equal.
func _step_text(step: String, file: String) -> String:
	return FileAccess.get_file_as_string("res://steps/%s/%s" % [step, file]).replace(step, "STEP")

## A scene's text without the block of its Environment sub-resource (from its header line to the blank line after it).
func _without_environment(text: String) -> String:
	var kept: Array[String] = []
	var inside := false
	for line in text.split("\n"):
		if line.begins_with("[sub_resource type=\"Environment\""):
			inside = true
		elif inside and line.strip_edges().is_empty():
			inside = false
		elif not inside:
			kept.append(line)
	return "\n".join(kept)

## The folder of tutorial 07, which sits next to this project in the repository. Empty if it is not there.
func _tutorial_07() -> String:
	var folder := ProjectSettings.globalize_path("res://").path_join("../07-watch-the-generator-think").simplify_path()
	return folder if DirAccess.dir_exists_absolute(folder) else ""

## Step 0 is the last step of tutorial 07, copied. When that tutorial is not next to this project the test skips.
func test_step_zero_is_tutorial_07() -> Array[String]:
	var failures: Array[String] = []
	var tutorial := _tutorial_07()
	var original := tutorial.path_join("steps/step_05_pinned_seeds")
	if tutorial.is_empty() or not DirAccess.dir_exists_absolute(original):
		_skip("step_00_start equals the last step of tutorial 07", "tutorial 07 is not next to this project")
		return failures
	var original_files: Array[String] = []
	for file in DirAccess.get_files_at(original):
		if not file.ends_with(".uid"):
			original_files.append(file)
	for file in DirAccess.get_files_at(original.path_join("props")):
		if not file.ends_with(".uid"):
			original_files.append("props/" + file)
	_expect(failures, original_files.size() > 40, "found only %d files in the last step of tutorial 07" % original_files.size())
	for file in original_files:
		if not FileAccess.file_exists("res://steps/step_00_start/" + file):
			failures.append("step_00_start has no %s" % file)
			continue
		var theirs := _without_step_names(FileAccess.get_file_as_string(original.path_join(file))).replace("godot/07-watch-the-generator-think", "godot/PROJECT")
		var ours := _without_step_names(FileAccess.get_file_as_string("res://steps/step_00_start/" + file)).replace("godot/08-light-and-atmosphere", "godot/PROJECT")
		_expect(failures, theirs == ours, "%s differs from the last step of tutorial 07" % file)
	_expect(failures, original_files.size() == _step_files("step_00_start").size(), "step_00_start has %d files, the last step of tutorial 07 has %d" % [_step_files("step_00_start").size(), original_files.size()])
	return failures

## The files of tutorial 07 point at one of its step folders, the copies here at the start folder.
func _without_step_names(text: String) -> String:
	return RegEx.create_from_string("step_\\d\\d_[a-z_]+").sub(text, "STEP", true)

func test_project_settings() -> Array[String]:
	var failures: Array[String] = []
	for action in ACTIONS:
		_expect(failures, ProjectSettings.has_setting("input/" + action), "no %s action" % action)
	_expect(failures, _physical_keys("toggle_gizmos") == ["F3"], "toggle_gizmos is %s, expected F3" % [_physical_keys("toggle_gizmos")])
	_expect(failures, _physical_keys("toggle_watch") == ["F4"], "toggle_watch is %s, expected F4" % [_physical_keys("toggle_watch")])
	_expect(failures, _physical_keys("step_generation") == ["Enter", "Kp Enter"], "step_generation is %s, expected Enter and Kp Enter" % [_physical_keys("step_generation")])
	_expect(failures, ProjectSettings.get_setting("layer_names/3d_render/layer_3") == "Body", "render layer 3 is not named Body")
	_expect(failures, ProjectSettings.get_setting("application/run/main_scene") == "res://steps/%s/main.tscn" % FINAL_STEP, "the main scene is not the final step")
	return failures

## No new key in this tutorial: the text on the screen and the Input Map are the ones of step 0 and of tutorial 07.
func test_hint_unchanged() -> Array[String]:
	var failures: Array[String] = []
	var reference := _hud_texts(STEPS[0])
	var hint := reference.get("DebugHint", "") as String
	_expect(failures, not hint.is_empty() and hint.contains("F3") and hint.contains("F4"), "step 0 has no hint with F3 and F4 (it says '%s')" % hint)
	_expect(failures, reference.size() >= 10, "found only %d labels in the HUD of step 0" % reference.size())
	for step in STEPS:
		var texts := _hud_texts(step)
		for label_name: String in reference:
			_expect(failures, texts.get(label_name) == reference[label_name], "%s: %s says '%s' in the HUD scene, step 0 says '%s'" % [step, label_name, texts.get(label_name), reference[label_name]])
		_expect(failures, texts.size() == reference.size(), "%s: the HUD scene has %d labels, step 0 has %d" % [step, texts.size(), reference.size()])
		var main := await _load_step(step, false)
		await _wait_physics(5)
		var label := main.get_node_or_null("HUD/Stats/DebugHint") as Label
		_expect(failures, label != null and label.text == hint, "%s: the hint on the screen says '%s', step 0 says '%s'" % [step, label.text if label != null else "no label", hint])
		await _unload(main)
	var tutorial := _tutorial_07()
	if tutorial.is_empty():
		_skip("hint: the Input Map is the one of tutorial 07", "tutorial 07 is not next to this project")
		return failures
	var theirs := _input_section(tutorial.path_join("project.godot"))
	var ours := _input_section(ProjectSettings.globalize_path("res://project.godot"))
	_expect(failures, theirs.length() > 1000, "found no [input] section in the project.godot of tutorial 07")
	_expect(failures, theirs == ours, "the [input] section of project.godot is not the one of tutorial 07: this tutorial adds no key")
	return failures

## The text of every label of a step's HUD scene, by the label's name.
func _hud_texts(step: String) -> Dictionary:
	var texts := {}
	var main := (load("res://steps/%s/main.tscn" % step) as PackedScene).instantiate()
	for label: Node in main.get_node("HUD").find_children("*", "Label", true, false):
		texts[str(label.name)] = (label as Label).text
	main.free()
	return texts

## Everything from the line "[input]" to the end of a project.godot.
func _input_section(path: String) -> String:
	var text := FileAccess.get_file_as_string(path)
	var start := text.find("\n[input]")
	return text.substr(start) if start >= 0 else ""

#endregion

#region Chains (pure data, no scene)

## A chain of any step's script.
func _new_chain(chain_script: GDScript, chain_seed: int, goal_room: int, chance := 0.0) -> RefCounted:
	return chain_script.new(chain_seed, goal_room, chance)

## The room_chain.gd of a step.
func _chain_script(step: String) -> GDScript:
	return load("res://steps/%s/room_chain.gd" % step) as GDScript

## What the chain's Type enum calls the goal room.
func _goal_type(chain_script: GDScript) -> int:
	return (chain_script.get_script_constant_map()["Type"] as Dictionary)["GOAL"]

func _same_plans(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not _same_plan(a[i], b[i]):
			return false
	return true

## One plan against another: the room, its lock, its props and its lamp.
func _same_plan(a: Object, b: Object) -> bool:
	if a.index != b.index or a.type != b.type or a.transform != b.transform or a.bounds != b.bounds:
		return false
	return a.locked == b.locked and a.key_spot == b.key_spot and a.props == b.props and a.lamp == b.lamp

## All plans of a chain up to and including its goal room (at most `limit` plans).
func _plans_to_goal(chain_script: GDScript, chain_seed: int, goal_room: int, chance := 0.4, limit := 400) -> RefCounted:
	var chain := _new_chain(chain_script, chain_seed, goal_room, chance)
	while chain.plans.size() < limit:
		var plan: Object = chain.next_plan()
		if plan.type == _goal_type(chain_script):
			break
	return chain

## The name of a room type in a step's Type enum ("straight", "vault", "goal").
func _room_name(chain_script: GDScript, type: int) -> String:
	return str((chain_script.get_script_constant_map()["Type"] as Dictionary).find_key(type)).to_lower()

## Every step plans the run of step 0 for every seed: the lamps are scenes, they never touch the generator.
func test_steps_plan_the_same() -> Array[String]:
	var failures: Array[String] = []
	var scripts: Array[GDScript] = []
	for step in STEPS:
		scripts.append(_chain_script(step))
	for chain_seed in range(1, PLAN_SEEDS + 1):
		if chain_seed % 20 == 0:
			await process_frame
		var base: Array = _plans_to_goal(scripts[0], chain_seed, 20).plans
		for i in range(1, scripts.size()):
			var other: Array = _plans_to_goal(scripts[i], chain_seed, 20).plans
			_expect(failures, _same_plans(base, other), "seed %d: %s plans another run than %s" % [chain_seed, STEPS[i], STEPS[0]])
		if failures.size() > 8:
			return failures
	return failures

#endregion

#region Walking the real player

## Runs tick once per physics tick until it returns true. (With Engine.time_scale above 1
## several ticks happen per frame, and `await physics_frame` would only see one of them.)
func _drive(tick: Callable) -> void:
	var driver := Driver.new()
	driver.process_priority = -100
	driver.tick = tick
	root.add_child(driver)
	await driver.finished
	root.remove_child(driver)
	driver.queue_free()

## Walks until the player is in room `goal`. dawdle: ticks of standing still at the start and at every new door.
func _walk(level: Node3D, pilot: RefCounted, goal: int, dawdle: int, on_tick: Callable) -> bool:
	var state := {"budget": 1500 * goal, "wait": dawdle, "target": pilot.door_index}
	await _drive(func() -> bool:
		if state["wait"] > 0:
			state["wait"] -= 1
		else:
			pilot.physics_step()
			if pilot.door_index != state["target"]:
				state["target"] = pilot.door_index
				state["wait"] = dawdle
				pilot.release()
		if on_tick.is_valid():
			on_tick.call()
		state["budget"] -= 1
		return level.current >= goal or state["budget"] <= 0)
	pilot.release()
	return level.current >= goal

#endregion

#region The environment (steps 1 to 5)

## The settings of the world environment of every step, as the narration names them.
func test_environment(step: String) -> Array[String]:
	var failures: Array[String] = []
	var index := STEPS.find(step)
	var main_path := "res://steps/%s/main.tscn" % step
	var main := (load(main_path) as PackedScene).instantiate()
	var worlds := main.find_children("*", "WorldEnvironment", true, false)
	_expect(failures, worlds.size() == 1, "%d WorldEnvironment nodes in main.tscn, expected 1" % worlds.size())
	var env: Environment = (worlds[0] as WorldEnvironment).environment if worlds.size() == 1 else null
	_expect(failures, env != null, "the WorldEnvironment has no environment")
	if env == null:
		main.free()
		return failures

	# The environment is a sub-resource of main.tscn: one block in the file, no file of its own.
	var text := FileAccess.get_file_as_string(main_path)
	_expect(failures, text.count("[sub_resource type=\"Environment\"") == 1, "main.tscn has %d Environment sub-resources, expected 1" % text.count("[sub_resource type=\"Environment\""))
	_expect(failures, text.count("[ext_resource type=\"Environment\"") == 0, "main.tscn loads an Environment from a file")
	_expect(failures, env.resource_path.begins_with(main_path + "::"), "the environment is '%s', not a sub-resource of main.tscn" % env.resource_path)
	for cam: Node in main.find_children("*", "Camera3D", true, false):
		_expect(failures, (cam as Camera3D).environment == null, "camera %s has an environment of its own: it would hide the world environment" % cam.name)

	# The sun: step 0 has it, from step 1 on no scene and no script makes one.
	var suns := main.find_children("*", "DirectionalLight3D", true, false)
	var scenes_with_a_sun: Array[String] = []
	for path in _files_in("res://steps/" + step, ".tscn"):
		if FileAccess.get_file_as_string(path).contains("type=\"DirectionalLight3D\""):
			scenes_with_a_sun.append(path.trim_prefix("res://steps/%s/" % step))
		_expect(failures, path == main_path or not FileAccess.get_file_as_string(path).contains("type=\"WorldEnvironment\""), "%s has a WorldEnvironment of its own" % path)
	var scripts_with_a_sun: Array[String] = []
	for path in _files_in("res://steps/" + step, ".gd"):
		if FileAccess.get_file_as_string(path).contains("DirectionalLight3D"):
			scripts_with_a_sun.append(path.trim_prefix("res://steps/%s/" % step))
	if index == 0:
		_expect(failures, suns.size() == 1 and (suns[0] as DirectionalLight3D).shadow_enabled, "step 0 should still have its sun, with shadows (found %d)" % suns.size())
		_expect(failures, scenes_with_a_sun == ["main.tscn"], "step 0: scenes with a sun are %s, expected main.tscn" % [scenes_with_a_sun])
		_expect(failures, env.background_mode == Environment.BG_SKY and env.sky != null, "step 0 should still show the sky")
		_expect(failures, is_equal_approx(env.ambient_light_energy, 1.0), "step 0: ambient light energy is %s, expected 1.0" % env.ambient_light_energy)
	else:
		_expect(failures, suns.is_empty(), "main.tscn still has a DirectionalLight3D: %s" % [suns])
		_expect(failures, scenes_with_a_sun.is_empty(), "scenes with a sun: %s" % [scenes_with_a_sun])
		_expect(failures, scripts_with_a_sun.is_empty(), "scripts that know a sun: %s" % [scripts_with_a_sun])

		# Step 1: the dark room. A near black background, a faint blue ambient colour, the filmic tone mapper, no sky.
		_expect(failures, env.background_mode == Environment.BG_COLOR, "background mode is %d, expected a colour" % env.background_mode)
		var black := env.background_color
		_expect(failures, maxf(black.r, maxf(black.g, black.b)) < 0.05, "the background colour %s is not near black" % black)
		_expect(failures, env.sky == null, "the environment still has a sky")
		_expect(failures, env.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR, "ambient light source is %d, expected a colour" % env.ambient_light_source)
		_expect(failures, is_equal_approx(env.ambient_light_energy, 0.02), "ambient light energy is %s, expected 0.02" % env.ambient_light_energy)
		var ambient := env.ambient_light_color
		_expect(failures, ambient.b > ambient.r and ambient.b > ambient.g, "the ambient colour %s is not bluish" % ambient)
		_expect(failures, env.tonemap_mode == Environment.TONE_MAPPER_FILMIC, "tone mapper is %d, expected filmic" % env.tonemap_mode)

	# Step 3: fog. Before it, there is none.
	_expect(failures, env.fog_enabled == (index >= 3), "fog_enabled is %s in step %d" % [env.fog_enabled, index])
	_expect(failures, env.volumetric_fog_enabled == (index >= 3), "volumetric_fog_enabled is %s in step %d" % [env.volumetric_fog_enabled, index])
	if index >= 3:
		_expect(failures, is_equal_approx(env.fog_density, 0.03), "fog density is %s, expected 0.03" % env.fog_density)
		_expect(failures, is_equal_approx(env.volumetric_fog_density, 0.07), "volumetric fog density is %s, expected 0.07" % env.volumetric_fog_density)
		_expect(failures, is_equal_approx(env.volumetric_fog_length, 30.0), "volumetric fog length is %s, expected 30" % env.volumetric_fog_length)

	# Step 4: glow. Before it, there is none.
	_expect(failures, env.glow_enabled == (index >= 4), "glow_enabled is %s in step %d" % [env.glow_enabled, index])
	if index >= 4:
		# Glow is on with one setting changed: Strength 2.0, because the default 1.0 spreads the glow so little that the halo does not show. The rest
		# stays at the defaults of the engine, so only a lamp (above the HDR threshold of 1.0) glows.
		_expect(failures, is_equal_approx(env.glow_strength, 2.0), "glow strength is %s, expected 2.0" % env.glow_strength)
		_expect(failures, is_equal_approx(env.glow_hdr_threshold, 1.0), "glow HDR threshold is %s, expected the default 1.0" % env.glow_hdr_threshold)
		_expect(failures, is_equal_approx(env.glow_bloom, 0.0), "glow bloom is %s, expected the default 0.0" % env.glow_bloom)
		_expect(failures, is_equal_approx(env.glow_intensity, 0.3), "glow intensity is %s, expected the default 0.3" % env.glow_intensity)

	# Step 5: SDFGI. Before it, there is none. Two cascades instead of the default four: the engine derives the farthest distance from the cascades
	# and the smallest cell (0.2, the default), 0.2 * 128 * 2^(cascades - 1) = 51.2 m.
	_expect(failures, env.sdfgi_enabled == (index >= 5), "sdfgi_enabled is %s in step %d" % [env.sdfgi_enabled, index])
	if index >= 5:
		_expect(failures, env.sdfgi_use_occlusion, "sdfgi_use_occlusion is off")
		_expect(failures, not env.sdfgi_read_sky_light, "sdfgi_read_sky_light is on: there is no sky to read")
		_expect(failures, env.sdfgi_cascades == 2, "sdfgi cascades are %d, expected 2" % env.sdfgi_cascades)
		_expect(failures, is_equal_approx(env.sdfgi_min_cell_size, 0.2), "sdfgi min cell size is %s, expected the default 0.2" % env.sdfgi_min_cell_size)
		_expect(failures, is_equal_approx(env.sdfgi_max_distance, 51.2), "sdfgi max distance is %s, expected 51.2 (0.2 * 128 * 2)" % env.sdfgi_max_distance)
	main.free()

	# The player's camera is in a scene of its own: no environment there either.
	var player := (load("res://steps/%s/player.tscn" % step) as PackedScene).instantiate()
	for cam: Node in player.find_children("*", "Camera3D", true, false):
		_expect(failures, (cam as Camera3D).environment == null, "the player's camera has an environment of its own")
	player.free()
	return failures

#endregion

#region Lamps (steps 2 to 5)

## The lamp scene: what a room puts at every one of its lamp spots.
func test_lamp_scene(step: String) -> Array[String]:
	var failures: Array[String] = []
	var scene := load("res://steps/%s/lamp.tscn" % step) as PackedScene
	var lamp := scene.instantiate() as OmniLight3D
	_expect(failures, lamp != null, "the root of lamp.tscn is not an OmniLight3D")
	if lamp == null:
		return failures
	_expect(failures, lamp.get_script() == load("res://steps/%s/lamp.gd" % step), "the lamp has not the script lamp.gd of its step")
	_expect(failures, lamp.shadow_enabled, "the lamp casts no shadows")
	_expect(failures, is_equal_approx(lamp.omni_range, 9.0), "omni range is %s, expected 9" % lamp.omni_range)
	_expect(failures, is_equal_approx(lamp.light_energy, 1.5), "light energy is %s, expected 1.5" % lamp.light_energy)
	var fixture := lamp.get_node_or_null("Fixture") as MeshInstance3D
	_expect(failures, fixture != null, "the lamp has no Fixture mesh")
	if fixture == null:
		lamp.free()
		return failures
	_expect(failures, fixture.layers == CEILING_LAYER, "the fixture is on render layers %d, expected only layer 2 (%d)" % [fixture.layers, CEILING_LAYER])
	_expect(failures, fixture.mesh != null and (fixture.mesh as PrimitiveMesh).material != null, "the fixture has no mesh or no material")

	# set_tint(): the colour of the light, and nothing else (not the energy, not the fixture, not the material every lamp shares).
	var before := _lamp_values(lamp)
	var tint := Color(0.2, 0.4, 0.6)
	_expect(failures, not (before["light"] as Dictionary)["light_color"].is_equal_approx(tint), "the test tint is the lamp's colour already")
	lamp.call("set_tint", tint)
	var after := _lamp_values(lamp)
	_expect(failures, lamp.light_color.is_equal_approx(tint), "set_tint left the light colour at %s" % lamp.light_color)
	for part: String in before:
		var wanted := (before[part] as Dictionary).duplicate()
		var found := after[part] as Dictionary
		if part == "light":
			wanted.erase("light_color")
			found = found.duplicate()
			found.erase("light_color")
		for property: String in wanted:
			_expect(failures, found.get(property) == wanted[property], "set_tint changed %s.%s from %s to %s" % [part, property, wanted[property], found.get(property)])
	lamp.call("set_tint", Color.WHITE)
	_expect(failures, lamp.light_color.is_equal_approx(Color.WHITE), "a second set_tint did not take: %s" % lamp.light_color)
	lamp.free()
	return failures

## The stored properties of the light, the fixture, its mesh and its material.
func _lamp_values(lamp: OmniLight3D) -> Dictionary:
	var fixture := lamp.get_node("Fixture") as MeshInstance3D
	return {
		light = _stored_properties(lamp),
		fixture = _stored_properties(fixture),
		mesh = _stored_properties(fixture.mesh),
		material = _stored_properties((fixture.mesh as PrimitiveMesh).material),
	}

func _stored_properties(object: Object) -> Dictionary:
	var values := {}
	for info in object.get_property_list():
		if (info["usage"] as int) & PROPERTY_USAGE_STORAGE != 0:
			values[info["name"]] = object.get(info["name"])
	return values

## The walkable floor of a room: between the inner faces of its four walls. As a rectangle in x and z.
func _walkable_floor(room: Node3D) -> Rect2:
	var shell := room.get_node("Shell")
	var left := shell.get_node("WallLeft") as CSGBox3D
	var right := shell.get_node("WallRight") as CSGBox3D
	var entrance := shell.get_node("WallEntrance") as CSGBox3D
	var far := shell.get_node("WallFar") as CSGBox3D
	var x_min := left.position.x + left.size.x * 0.5
	var x_max := right.position.x - right.size.x * 0.5
	var z_min := far.position.z + far.size.z * 0.5
	var z_max := entrance.position.z - entrance.size.z * 0.5
	return Rect2(x_min, z_min, x_max - x_min, z_max - z_min)

## The floor point that is farthest from its nearest lamp spot: a grid at most GRID_STEP apart over the whole walkable floor, borders
## and corners included. The distance is the straight line from the spot to the point on the floor (height 0), which is what a light's range cuts.
func _farthest_floor_point(floor_rect: Rect2, spots: Array[Vector3]) -> Dictionary:
	var columns := maxi(1, ceili(floor_rect.size.x / GRID_STEP))
	var rows := maxi(1, ceili(floor_rect.size.y / GRID_STEP))
	var worst := 0.0
	var worst_at := Vector3.ZERO
	for i in columns + 1:
		for j in rows + 1:
			var point := Vector3(floor_rect.position.x + floor_rect.size.x * float(i) / float(columns), 0.0, floor_rect.position.y + floor_rect.size.y * float(j) / float(rows))
			var nearest := INF
			for spot in spots:
				nearest = minf(nearest, point.distance_to(spot))
			if nearest > worst:
				worst = nearest
				worst_at = point
	return {distance = worst, at = worst_at, points = (columns + 1) * (rows + 1)}

## Step 1 rooms have one big light and a fixture. From step 2 they have lamp spots instead: the right number, inside the room, at the
## height of the ceiling lamps, and together they reach every part of the floor.
func test_lamp_spots(step: String) -> Array[String]:
	var failures: Array[String] = []
	var lamps_here := STEPS.find(step) >= STEPS.find(FIRST_LAMP_STEP)
	var lamp_range := 0.0
	if lamps_here:
		var lamp := (load("res://steps/%s/lamp.tscn" % step) as PackedScene).instantiate() as OmniLight3D
		lamp_range = lamp.omni_range
		lamp.free()
	var notes: Array[String] = []
	for room_name: String in LAMP_COUNTS:
		var label := "room_%s" % room_name
		var room := (load("res://steps/%s/room_%s.tscn" % [step, room_name]) as PackedScene).instantiate() as Node3D
		var spots_node := room.get_node_or_null("LampSpots")
		var lights := room.find_children("*", "Light3D", true, false)
		if not lamps_here:
			_expect(failures, spots_node == null, "%s: has lamp spots before the lamps step" % label)
			_expect(failures, room.get_node_or_null("RoomLight") is OmniLight3D, "%s: has no RoomLight to be replaced" % label)
			_expect(failures, room.get_node_or_null("Fixture") is MeshInstance3D, "%s: has no Fixture to be replaced" % label)
			room.free()
			continue
		_expect(failures, room.find_children("RoomLight", "", true, false).is_empty(), "%s: still has a RoomLight" % label)
		_expect(failures, room.find_children("Fixture", "", true, false).is_empty(), "%s: still has a Fixture (the lamp brings its own)" % label)
		var expected_lights := 1 if room_name == "goal" else 0 # the goal room keeps the light of its pad
		_expect(failures, lights.size() == expected_lights, "%s: %d lights in the scene, expected %d" % [label, lights.size(), expected_lights])
		if room_name == "goal":
			_expect(failures, room.get_node_or_null("PadLight") is OmniLight3D, "%s: has lost its PadLight" % label)
		if spots_node == null:
			failures.append("%s: has no LampSpots" % label)
			room.free()
			continue
		_expect(failures, (spots_node as Node3D).transform.is_equal_approx(Transform3D.IDENTITY), "%s: LampSpots is moved, but room.gd puts a lamp at the spot's own transform" % label)
		_expect(failures, spots_node.get_child_count() == LAMP_COUNTS[room_name], "%s: %d lamp spots, expected %d" % [label, spots_node.get_child_count(), LAMP_COUNTS[room_name]])
		var inside := room.get_node("Inside") as Node3D
		var inside_shape := inside.get_node("CollisionShape3D") as CollisionShape3D
		var half := (inside_shape.shape as BoxShape3D).size * 0.5
		var box_to_room := inside.transform * inside_shape.transform
		var floor_rect := _walkable_floor(room)
		var spots: Array[Vector3] = []
		for spot in spots_node.get_children():
			_expect(failures, spot is Marker3D, "%s: %s is not a Marker3D" % [label, spot.name])
			var position := (spot as Node3D).position
			spots.append(position)
			var in_box := box_to_room.affine_inverse() * position
			_expect(failures, absf(in_box.x) <= half.x and absf(in_box.y) <= half.y and absf(in_box.z) <= half.z, "%s: %s at %s is outside the Inside box" % [label, spot.name, position])
			_expect(failures, position.x >= floor_rect.position.x and position.x <= floor_rect.end.x and position.z >= floor_rect.position.y and position.z <= floor_rect.end.y, "%s: %s at %s is not above the walkable floor" % [label, spot.name, position])
			_expect(failures, is_equal_approx(position.y, LAMP_HEIGHT), "%s: %s is %s m high, expected %s" % [label, spot.name, position.y, LAMP_HEIGHT])
		var reach := _farthest_floor_point(floor_rect, spots)
		var farthest: float = reach.distance
		_expect(failures, farthest <= lamp_range, "%s: the floor point (%.1f, %.1f) is %.2f m from its nearest lamp, a lamp reaches %.1f m" % [label, reach.at.x, reach.at.z, farthest, lamp_range])
		notes.append("%s %.2f m" % [room_name, farthest])
		room.free()
	if lamps_here and failures.is_empty():
		print("        %s: farthest floor point from its nearest lamp (a lamp reaches %.1f m): %s" % [step, lamp_range, ", ".join(notes)])
	return failures

## The lights in the level right now: the lamps of the rooms that stand, and what they are. Notes the most seen at once in stats.
## A room that is queued for deletion is on its way out and does not count (it is gone before the next picture).
func _note_lights(level: Node3D, stats: Dictionary) -> void:
	var lamps := 0
	var shadows := 0
	var rooms: Array = level.rooms.values()
	for light: Node in level.find_children("*", "OmniLight3D", true, false):
		var holder := light.get_parent()
		if holder.is_queued_for_deletion():
			continue
		if not rooms.has(holder):
			stats["strays"] += 1 # a light that hangs on something else than a room would stay behind when the room goes
			continue
		lamps += 1
		if (light as OmniLight3D).shadow_enabled:
			shadows += 1
	if lamps > stats["most"]:
		stats["most"] = lamps
		stats["in_room"] = level.current
	stats["most_shadows"] = maxi(stats["most_shadows"], shadows)

func _new_light_stats() -> Dictionary:
	return {"most": 0, "most_shadows": 0, "in_room": -1, "strays": 0}

## The walk of the narration. Seed 53 from the first door into room 5: at every physics tick, count the lamps in the tree.
func test_lamps_in_a_run(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step, true, {"chain_seed": RUN_SEED})
	var level: Node3D = main.get_node("Level")
	var chain_script := _chain_script(step)
	var first_lamps: Array[int] = []
	for lamp: Node in level.rooms[0].lamps:
		first_lamps.append(lamp.get_instance_id())
	_expect(failures, first_lamps.size() == 1, "room 0 of seed %d has %d lamps, expected 1" % [RUN_SEED, first_lamps.size()])

	var stats := _new_light_stats()
	var pilot := Autopilot.new(level)
	_fast_forward(true)
	var reached := await _walk(level, pilot, RUN_TO_ROOM, 0, func() -> void: _note_lights(level, stats))
	_fast_forward(false)
	_expect(failures, reached, "the autopilot did not get into room %d (room %d, %.1f s)" % [RUN_TO_ROOM, level.current, level.run_time])

	# The premise of the count: the rooms of the narration, none of them locked.
	var plans: Array = level.chain.plans
	var names: Array[String] = []
	for i in mini(plans.size(), RUN_TO_ROOM + 1):
		names.append(_room_name(chain_script, plans[i].type))
		_expect(failures, not plans[i].locked, "room %d of seed %d is locked: the walk is not the one of the narration" % [i, RUN_SEED])
	_expect(failures, names == ["straight", "turn_left", "wide", "vault", "straight", "long"], "seed %d now builds %s: the count of lamps is not about the narration's rooms any more" % [RUN_SEED, names])

	# Most lamps at once, and all of them cast shadows. This is the figure the narration says out loud.
	_expect(failures, stats["most"] == MOST_LAMPS_IN_RUN, "most lamps at once %d (expected %d)" % [stats["most"], MOST_LAMPS_IN_RUN])
	_expect(failures, stats["most_shadows"] == MOST_SHADOW_LAMPS_IN_RUN, "most lamps with shadows at once %d (expected %d)" % [stats["most_shadows"], MOST_SHADOW_LAMPS_IN_RUN])
	_expect(failures, stats["strays"] == 0, "%d times a light hung on something that is not a room" % stats["strays"])

	# The lamps are children of their room: room 0 is long gone, and its lamps went with it.
	await _wait_physics(5)
	_expect(failures, not level.rooms.has(0), "room 0 is still there in room %d" % level.current)
	for id in first_lamps:
		_expect(failures, not is_instance_valid(instance_from_id(id)), "a lamp of room 0 is still alive after the room is gone")
	var rooms: Array = level.rooms.values()
	for light: Node in level.find_children("*", "OmniLight3D", true, false):
		_expect(failures, rooms.has(light.get_parent()), "a light hangs on %s, which is not a room that stands" % light.get_parent().name)
	_expect(failures, main.find_children("*", "DirectionalLight3D", true, false).is_empty(), "there is a sun in the tree")
	if failures.is_empty():
		print("        %s, seed %d, room 0 to %d: most lamps at once %d, most with shadows %d (in room %d), %.1f s of game time" % [step, RUN_SEED, RUN_TO_ROOM, stats["most"], stats["most_shadows"], stats["in_room"], level.run_time])
	await _unload(main)
	return failures

## Seeds 1..40, every room type: the lamps of each room have the tint of the room's plan, stand on their spots, and are children of the room.
func test_lamp_tints(step: String) -> Array[String]:
	var failures: Array[String] = []
	var chain_script := _chain_script(step)
	var tints: Array = chain_script.get_script_constant_map()["LAMP_TINTS"]
	var goal_type := _goal_type(chain_script)
	var main := await _load_step(step, false, {"goal_room": 7})
	var level: Node3D = main.get_node("Level")
	var tints_seen := {}
	var types_seen := {}
	var rooms_checked := 0
	for chain_seed in range(1, TINT_SEEDS + 1):
		level.use_seed(str(chain_seed))
		await process_frame # the rooms of the seed before go now
		var built := 0
		while level.chain.plans.back().type != goal_type and built < 30:
			level.rooms[level.chain.plans.size() - 1].door.open() # the newest room's door builds the next room
			built += 1
		for plan: Object in level.chain.plans:
			var room: Node3D = level.rooms[plan.index]
			var type_name := _room_name(chain_script, plan.type)
			var where := "seed %d room %d (%s)" % [chain_seed, plan.index, type_name]
			var lamps: Array = room.lamps
			var spots := room.get_node("LampSpots").get_children()
			_expect(failures, lamps.size() == LAMP_COUNTS[type_name], "%s: %d lamps, expected %d" % [where, lamps.size(), LAMP_COUNTS[type_name]])
			for i in lamps.size():
				var lamp := lamps[i] as OmniLight3D
				_expect(failures, lamp.get_parent() == room, "%s: lamp %d is not a child of its room" % [where, i])
				_expect(failures, i < spots.size() and lamp.transform == (spots[i] as Node3D).transform, "%s: lamp %d is not on its spot" % [where, i])
				_expect(failures, lamp.light_color.is_equal_approx(tints[plan.lamp]), "%s: lamp %d has the colour %s, the plan's tint %d is %s" % [where, i, lamp.light_color, plan.lamp, tints[plan.lamp]])
				_expect(failures, lamp.shadow_enabled, "%s: lamp %d casts no shadows" % [where, i])
			tints_seen[plan.lamp] = true
			types_seen[type_name] = true
			rooms_checked += 1
		if failures.size() > 8:
			break
	_expect(failures, types_seen.size() == LAMP_COUNTS.size(), "only %s of the seven room types came up in the seeds" % [types_seen.keys()])
	_expect(failures, tints_seen.size() == tints.size(), "only the tints %s of %d came up in the seeds: the check could not tell a missing tint from a tint" % [tints_seen.keys(), tints.size()])
	if failures.is_empty():
		print("        %s: %d rooms of seeds 1-%d, all %d room types and all %d tints came up" % [step, rooms_checked, TINT_SEEDS, types_seen.size(), tints_seen.size()])
	await _unload(main)
	return failures

#endregion

#region Global illumination (step 5)

## Doors, keys and the player's body move. SDFGI keeps one distance field for the whole level, which cannot follow them: in step 5 their meshes
## have gi_mode disabled. The step before leaves the default. The rooms stay in the field.
func test_gi_modes(step: String) -> Array[String]:
	var failures: Array[String] = []
	var wanted := GeometryInstance3D.GI_MODE_DISABLED if step == FINAL_STEP else GeometryInstance3D.GI_MODE_STATIC
	var main := await _load_step(step)
	var level: Node3D = main.get_node("Level")
	var key := (load("res://steps/%s/key.tscn" % step) as PackedScene).instantiate()
	var door: Node3D = level.rooms[0].door
	var parts := {
		"the player's body": level.player.body.find_children("*", "MeshInstance3D", true, false),
		"the door": door.find_children("*", "MeshInstance3D", true, false),
		"the key": key.find_children("*", "MeshInstance3D", true, false),
	}
	for part: String in parts:
		var meshes: Array = parts[part]
		_expect(failures, not meshes.is_empty(), "found no mesh in %s" % part)
		for mesh: MeshInstance3D in meshes:
			_expect(failures, mesh.gi_mode == wanted, "%s: %s has gi_mode %d, expected %d" % [part, mesh.name, mesh.gi_mode, wanted])
	var leaf := door.get_node_or_null("Hinge/MeshInstance3D") as MeshInstance3D
	_expect(failures, leaf != null and leaf.gi_mode == wanted, "the door leaf has gi_mode %d, expected %d" % [leaf.gi_mode if leaf != null else -1, wanted])
	var shell := level.rooms[0].get_node("Shell") as CSGShape3D
	_expect(failures, shell.gi_mode == GeometryInstance3D.GI_MODE_STATIC, "the shell of the room has gi_mode %d: SDFGI would have nothing to light" % shell.gi_mode)
	key.free()
	await _unload(main)
	return failures

#endregion

#region The game underneath (tutorial 07's final state, with the environment and the lamps around it)

## Room 2 entered: the door of room 1 starts to close behind the player, room 0 is the oldest room.
func _door_closing_behind_room_2(step: String) -> Node:
	var main := await _load_step(step)
	var level: Node3D = main.get_node("Level")
	level.rooms[0].door.open() # builds room 1
	level._on_room_entered(level.player, 1)
	await _wait_physics(45)
	level.rooms[1].door.open() # builds room 2
	await _wait_physics(45)
	level._on_room_entered(level.player, 2)
	return main

## Through the door behind the player the picture goes along the room just left, to the doorway of the one before it.
func test_rooms_wait_for_the_door(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _door_closing_behind_room_2(step)
	var level: Node3D = main.get_node("Level")
	_expect(failures, level.rooms.has(0), "room 0 went while the door behind the player stood open")
	await _wait_physics(45)
	_expect(failures, not level.rooms.has(0), "room 0 is still there behind the shut door")
	_expect(failures, level.rooms.has(1), "the room just left went with room 0")
	_expect(failures, not level.rooms[1].get_node("Shell/WallEntrance/Opening").visible, "the room just left has no wall at its entrance")
	await _unload(main)
	main = await _door_closing_behind_room_2(step)
	level = main.get_node("Level")
	await _wait_physics(10)
	level.rooms[1].door.open() # the player turned around while the leaf still swings
	await _wait_physics(45)
	_expect(failures, level.rooms.has(0), "room 0 went while the door stood open again")
	level.start()
	if level.has_method("_on_door_closed"):
		level._on_door_closed(2) # a restart is faster than the door of the old run
		_expect(failures, level.rooms.has(0), "the door of the old run took room 0 of the new one")
	else:
		_expect(failures, false, "level.gd has no _on_door_closed")
	await _unload(main)
	return failures

func test_full_run() -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(FINAL_STEP)
	var level: Node3D = main.get_node("Level")
	var pilot := Autopilot.new(level)
	var stats := _new_light_stats()
	_fast_forward(true)
	var budget := [60 * 60 * 5]
	await _drive(func() -> bool:
		pilot.physics_step()
		_note_lights(level, stats)
		budget[0] -= 1
		return level.state == STATE_FINISHED or budget[0] <= 0)
	pilot.release()
	_fast_forward(false)
	_expect(failures, level.state == STATE_FINISHED, "the run did not finish (room %d, %.1f s)" % [level.current, level.run_time])
	_expect(failures, level.current == 20, "finished in room %d" % level.current)
	_expect(failures, level.run_time > 30.0 and level.run_time < 150.0, "the run took %.1f s" % level.run_time)
	_expect(failures, stats["most"] <= MOST_LAMPS_ANY_RUN, "most lamps at once %d, three rooms hold at most %d: rooms are not freed behind the player" % [stats["most"], MOST_LAMPS_ANY_RUN])
	_expect(failures, stats["most"] >= 3, "most lamps at once %d: the count saw no lamps" % stats["most"])
	_expect(failures, stats["strays"] == 0, "%d times a light hung on something that is not a room" % stats["strays"])
	print("        full run, seed 42: %.2f s of game time, most lamps at once %d (with the player in room %d), most with shadows %d" % [level.run_time, stats["most"], stats["in_room"], stats["most_shadows"]])
	await _unload(main)
	return failures

func _state(player: CharacterBody3D) -> String:
	var tree := player.get_node("Body/AnimationTree") as AnimationTree
	return (tree.get("parameters/playback") as AnimationNodeStateMachinePlayback).get_current_node()

func test_restart() -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(FINAL_STEP)
	var level: Node3D = main.get_node("Level")
	var player: CharacterBody3D = level.player
	var tree := player.get_node("Body/AnimationTree") as AnimationTree
	Input.action_press("move_forward")
	await _wait_physics(30)
	Input.action_release("move_forward")
	await _action("regenerate")
	await _wait_physics(40)
	_expect(failures, player.global_position.distance_to(Vector3(0.0, 0.0, 3.5)) < 0.05, "the player is at %s" % player.global_position)
	_expect(failures, _state(player) == "Move", "the tree is in %s" % _state(player))
	_expect(failures, is_zero_approx(tree.get("parameters/Move/blend_position")), "blend position %.2f" % tree.get("parameters/Move/blend_position"))
	await _unload(main)
	return failures

func test_scene_runs(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step, false)
	for i in 30:
		await process_frame
	_expect(failures, is_instance_valid(main) and main.is_inside_tree(), "scene left the tree")
	await _unload(main)
	return failures

#endregion

#region Harness

func _run(test_name: String, test: Callable) -> void:
	if not _selected(test_name):
		return
	await process_frame # the engine empties its message queue between tests: the chain tests build thousands of room scenes
	var failures: Array[String] = await test.call()
	_report(test_name, failures)

func _selected(test_name: String) -> bool:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--only=") and not test_name.contains(argument.trim_prefix("--only=")):
			return false
	return true

func _steps_from(first: String) -> Array[String]:
	var result: Array[String] = []
	for step: String in STEPS.slice(STEPS.find(first)):
		result.append(step)
	return result

func _report(test_name: String, failures: Array[String]) -> void:
	var script_errors := _script_errors.count - _script_errors_reported
	_script_errors_reported = _script_errors.count
	if script_errors > 0: # the test stopped at the failing line and the engine returned an empty array, which would read as a pass
		failures.insert(0, "the test stopped with a script error: see the log")
	if failures.is_empty():
		_passed += 1
		print("PASS  ", test_name)
		return
	_failed += 1
	print("FAIL  ", test_name)
	for message: String in failures.slice(0, 8):
		print("        ", message)
	if failures.size() > 8:
		print("        ... and %d more" % (failures.size() - 8))

func _skip(test_name: String, reason: String) -> void:
	_skipped += 1
	print("SKIP  ", test_name)
	print("        ", reason)

func _expect(failures: Array[String], condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

## Instances a step's main scene. By default it waits until the CSG shapes have built their collision.
## props are set on the Level before it enters the tree (goal_room, seed_text, lock_chance ...; "chain_seed" is the
## text of the seed's digits).
## Every level gets a fresh temporary save file unless props bring one.
func _load_step(step: String, settle := true, props := {}) -> Node:
	var scene: PackedScene = load("res://steps/%s/main.tscn" % step)
	var main := scene.instantiate()
	var level := main.get_node("Level")
	if not props.has("save_path"):
		level.set("save_path", _fresh_save_path())
	for key: String in props:
		if key == "chain_seed":
			level.set("seed_text", str(props[key]))
		else:
			level.set(key, props[key])
	root.add_child(main)
	if settle:
		await _wait_physics(10)
	return main

func _unload(main: Node) -> void:
	for action: String in ["move_forward", "move_back", "move_left", "move_right", "look_left", "look_right", "look_up", "look_down", "jump", "walk"]:
		Input.action_release(action)
	root.remove_child(main)
	main.free()
	await process_frame

## A path in the temporary test folder that no file exists at.
func _fresh_save_path() -> String:
	_save_counter += 1
	DirAccess.make_dir_recursive_absolute(_save_dir)
	return _save_dir.path_join("best_times_%d.json" % _save_counter)

func _wipe_save_dir() -> void:
	if not DirAccess.dir_exists_absolute(_save_dir):
		return
	for file in DirAccess.get_files_at(_save_dir):
		DirAccess.remove_absolute(_save_dir.path_join(file))
	DirAccess.remove_absolute(_save_dir)

## Runs the simulation faster than real time with the same 1/60 s steps: the engine ticks
## SPEED_UP times as often and hands out SPEED_UP times the delta of each (smaller) tick.
func _fast_forward(on: bool) -> void:
	Engine.physics_ticks_per_second = 60 * (SPEED_UP if on else 1)
	Engine.time_scale = float(SPEED_UP) if on else 1.0

func _wait_physics(frames: int) -> void:
	for i in frames:
		await physics_frame

func _action(action: StringName) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	await process_frame

## The names of an action's keyboard keys ("F3"), by physical key.
func _physical_keys(action: StringName) -> Array[String]:
	var keys: Array[String] = []
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			keys.append(OS.get_keycode_string((event as InputEventKey).physical_keycode))
	return keys

#endregion
