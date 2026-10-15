extends Node
## Headless smoke test — proves the whole pipeline with zero API key:
## demo bricks -> compile -> scene tree -> GameState wiring.
##
## Runs as a scene node (NOT --script) so all autoloads are live, which is the
## exact condition the real app runs under. Launch:
##   godot --headless res://tests/test_scene.tscn --quit-after 300
##
## Exit code: 0 = all pass, 1 = failures (see the printed banner).

var _ok := true
var _checks := 0

func _ready() -> void:
	_log("EasyForge smoke test")

	# --- 1. Brick creation ---
	var spawn = BrickRef.create("spawn")
	if spawn.is_empty():
		_fail("spawn brick did not create")
	else:
		_log("spawn brick created: " + spawn["id"])

	# --- 2. Graph build + pre-connection (never an empty canvas) ---
	var graph = load("res://src/bricks/graph.gd").new()
	graph.from_dict(DemoTemplates.platformer())
	if graph.bricks.size() != 6:
		_fail("demo should have 6 bricks, got %d" % graph.bricks.size())
	else:
		_log("demo graph: 6 bricks")

	# --- 3. Compile via the autoload singleton ---
	var scene = Compiler.compile_graph(graph)
	if scene == null:
		_fail("compile returned null")
		_finish()
		return
	if not scene is Node3D:
		_fail("3d demo should compile to Node3D, got %s" % scene.get_class())
	else:
		_log("compiled to Node3D root")

	# --- 4. Scene contents ---
	var has_player := false
	var has_ground := false
	var has_camera := false
	var has_hud := false
	var has_state := false
	var coin_count := 0
	var player_node = null
	for child in scene.get_children():
		match child.get_class():
			"CharacterBody3D":
				has_player = true
				player_node = child
			"StaticBody3D": has_ground = true
			"Camera3D": has_camera = true
			"Control": has_hud = true
			"Area3D": coin_count += 1
		if child.has_method("add_score"):
			has_state = true
	if not has_player: _fail("no player entity")
	if not has_ground: _fail("no ground")
	if not has_camera: _fail("no camera")
	if not has_hud: _fail("no HUD")
	if not has_state: _fail("no GameState attached")
	if coin_count == 0: _fail("no coin area")
	if _ok:
		_log("scene OK: player=%s ground=%s camera=%s hud=%s state=%s coins=%d" % [has_player, has_ground, has_camera, has_hud, has_state, coin_count])

	# --- 4b. Camera brick -> follow script attached (player-tracking) ---
	var cam_node = null
	for child in scene.get_children():
		if child is Camera3D:
			cam_node = child
			break
	if cam_node != null:
		var cs = cam_node.get_script()
		if cs != null and str(cs.source_code).contains("get_first_node_in_group"):
			_log("camera brick compiled to a player-follow script")
		else:
			_fail("camera has no follow script")
	else:
		_fail("no Camera3D in the compiled scene")

	# --- 5. Player carries the generated movement script ---
	if player_node != null:
		var s = player_node.get_script()
		if s != null and str(s.source_code).contains("_physics_process"):
			_log("player movement script attached and generated")
			# the movement must read the player's chosen keys, not hardcoded
			if str(s.source_code).contains("is_key_pressed"):
				_log("movement uses configurable key bindings")
			else:
				_fail("movement script does not read key bindings")
		else:
			_fail("player has no generated movement script")

	# --- 5b. Coin collector script compiles clean (no generated-code parse errors) ---
	var coin_node = null
	for child in scene.get_children():
		if child is Area3D:
			coin_node = child
			break
	if coin_node != null:
		var cs = coin_node.get_script()
		if cs != null:
			var probe := GDScript.new()
			probe.source_code = cs.source_code
			if probe.reload() == OK:
				_log("coin collector script compiles clean")
			else:
				_fail("coin collector script has a parse error")
		else:
			_fail("coin has no collector script")
	else:
		_fail("no coin node found for script check")

	# --- 5c. HUD script compiles clean ---
	var hud_node = null
	for child in scene.get_children():
		if child is Control:
			hud_node = child
			break
	if hud_node != null:
		var hs = hud_node.get_script()
		if hs != null:
			var hprobe := GDScript.new()
			hprobe.source_code = hs.source_code
			if hprobe.reload() == OK:
				_log("HUD script compiles clean")
			else:
				_fail("HUD script has a parse error")
		else:
			_fail("HUD has no script")

	# --- 6. Generated script (escape hatch) ---
	var code = Compiler.generated_script(graph)
	if code.length() < 50:
		_fail("generated_script too short")
	else:
		_log("code view length: %d chars" % code.length())

	# --- 7. Save / load round trip ---
	var tmp := "user://test_roundtrip.json"
	if not graph.save_to(tmp):
		_fail("save failed")
	else:
		var g2 = load("res://src/bricks/graph.gd").new()
		if g2.load_from(tmp) and g2.bricks.size() == graph.bricks.size():
			_log("save/load round trip OK (%d bricks)" % g2.bricks.size())
		else:
			_fail("round trip mismatch")

	# --- 8. 2D dimension check ---
	graph.from_dict(DemoTemplates.side_scroller_2d())
	var scene2 = Compiler.compile_graph(graph)
	if scene2 is Node2D:
		_log("2D pipeline OK (Node2D root)")
	else:
		_fail("2D demo should be Node2D, got %s" % scene2.get_class())

	# --- 8b. New engine-fundamental bricks compile without crashing ---
	# sound + particles + animation + health all attach/generate cleanly
	var fb = {
		"project_name": "Fundamentals", "dimension": "3d", "genre": "platformer",
		"bricks": [
			BrickRef.create("spawn"),
			BrickRef.create("sound"),
			BrickRef.create("particles"),
			BrickRef.create("animation"),
			BrickRef.create("health"),
		],
	}
	var scene_fb = Compiler.compile_graph(fb)
	if scene_fb is Node3D:
		_log("fundamentals graph (sound/particles/animation/health) compiles to Node3D")
		# GameState exposes the runtime helpers the generated code calls
		for m in ["play_sound", "burst", "damage", "set_max_health"]:
			if not GameState.has_method(m):
				_fail("GameState missing method: %s" % m)
	else:
		_fail("fundamentals graph failed to compile")
	# play_sound + burst must be safe to call with no scene mounted
	GameState.play_sound("coin", 0.5)
	GameState.burst(8, "sparkle", "gold", Vector3.ZERO)
	_log("GameState.play_sound + burst callable without crashing")

	# --- 9. Validation catches an empty graph ---
	graph.from_dict({"project_name": "Empty", "dimension": "3d", "genre": "platformer", "bricks": []})
	var issues = graph.validate()
	if issues.size() > 0:
		_log("validation works: %s" % issues[0])
	else:
		_fail("empty graph should produce a validation issue")

	# --- 10. Typed-port rule ---
	var a = BrickRef.create("spawn")
	var b = BrickRef.create("collide")
	if BrickRef.can_connect(a, 0, b, 0):
		_log("typed ports: spawn->collide allowed (correct)")
	else:
		_fail("spawn->collide should be connectable")
	var c = BrickRef.create("spawn")
	if not BrickRef.can_connect(c, 0, c, 0):
		_log("typed ports: self-loop blocked (correct)")
	else:
		_fail("self-loop should be blocked")

	# --- 11. GameState logic ---
	GameState.reset()
	GameState.set_win_condition("score_reaches", 3)
	GameState.add_score(1)
	GameState.add_score(1)
	if GameState.game_over:
		_fail("should not be game over at score 2/3")
	else:
		_log("GameState: score 2/3, still playing")
	GameState.add_score(1)
	if GameState.game_over and GameState.won:
		_log("GameState: win at 3/3 (correct)")
	else:
		_fail("should win at score 3/3")
	GameState.reset()

	# --- 12. Brick registry has the 5 universal + platformer pack ---
	var kinds = BrickRegistry.all_kinds()
	var needed := ["spawn", "move", "collide", "score", "winlose"]
	var missing := []
	for k in needed:
		if not kinds.has(k):
			missing.append(k)
	if missing.is_empty():
		_log("registry: all 5 universal kinds present (%d total)" % kinds.size())
	else:
		_fail("registry missing: %s" % str(missing))

	# --- 13. i18n loads ---
	if I18n.t("app_title") == "EasyForge":
		_log("i18n: English loads")
	else:
		_fail("i18n English failed: %s" % I18n.t("app_title"))
	I18n.set_language("hi")
	if I18n.t("app_title") == "EasyForge":
		_log("i18n: Hindi loads")
	else:
		_fail("i18n Hindi failed")
	I18n.set_language("en")

	# --- 14. AI generator JSON extraction (offline, no API call) ---
	var GenScript = load("res://src/ai/brick_generator.gd")
	var gen = GenScript.new()
	add_child(gen)
	var fake := 'Sure! Here is your game:\n```json\n{"project_name":"X","dimension":"3d","genre":"platformer","bricks":[{"id":"s1","kind":"spawn","title":"P","comment":"","inputs":[],"outputs":[],"params":{},"connections":[]}]}\n```\nEnjoy!'
	var extracted = gen._extract_json(fake)
	if extracted.has("bricks") and extracted["bricks"].size() == 1:
		_log("AI JSON extraction handles fenced/markdown replies")
	else:
		_fail("AI JSON extraction failed on markdown-wrapped JSON")
	gen.queue_free()

	# --- 15. HARDENING: a garbage graph still compiles to a playable scene ---
	var garbage = load("res://src/bricks/graph.gd").new()
	garbage.from_dict({
		"project_name": "Garbage",
		"dimension": "3d",
		"genre": "platformer",
		"bricks": [
			{},                                          # empty brick
			{"id": "x1", "kind": null},                  # no kind
			{"id": "x2"},                                 # id only
			{"kind": "spawn", "params": {"model": null, "position": "not an array"}},
			{"id": "x4", "kind": "collide", "connections": [{"to_brick": "does-not-exist"}], "params": {"with": null, "count": "lots"}},
			{"id": "x5", "kind": "score", "params": {"amount": "not-a-number"}},
			{"id": "x6", "kind": "winlose", "params": {"value": null}},
			{"id": "x7", "kind": "totally_unknown_kind", "title": "Mystery"},
			{"id": "x8", "kind": "enemy_patrol", "params": {"speed": "fast", "range": null}},
			{"id": "x9", "kind": "hazard"},
			{"id": "x10", "kind": "checkpoint"},
			{"id": "x11", "kind": "moving_platform"},
		],
	})
	var garbage_scene = null
	garbage_scene = Compiler.compile_graph(garbage)
	if garbage_scene == null:
		_fail("garbage graph compiled to null")
	elif not (garbage_scene is Node3D):
		_fail("garbage graph should still compile to Node3D")
	else:
		_log("compiles a garbage graph without crashing (root: %s)" % garbage_scene.get_class())
	# the garbage scene must still have ground, camera, HUD and a game state
	var g_ground := false
	var g_cam := false
	var g_hud := false
	var g_state := false
	for child in garbage_scene.get_children():
		match child.get_class():
			"StaticBody3D": g_ground = true
			"Camera3D": g_cam = true
			"Control": g_hud = true
		if child.has_method("add_score"):
			g_state = true
	if not (g_ground and g_cam and g_hud and g_state):
		_fail("garbage scene missing basics: ground=%s cam=%s hud=%s state=%s" % [g_ground, g_cam, g_hud, g_state])
	else:
		_log("garbage scene still complete: ground+camera+HUD+GameState present")
	# the unknown-kind brick must be a safe placeholder, not a crash
	var has_placeholder := false
	for child in garbage_scene.get_children():
		if child is Label3D:
			has_placeholder = true
	if not has_placeholder:
		_fail("unknown brick kind should become a Label3D placeholder")
	else:
		_log("unknown brick kind -> safe Label3D placeholder")
	# genre bricks in a garbage graph compile as real nodes
	var genre_nodes := {"Enemy": false, "Hazard": false, "Checkpoint": false, "MovingPlatform": false}
	for child in garbage_scene.get_children():
		if genre_nodes.has(child.name):
			genre_nodes[child.name] = true
	for gn in genre_nodes:
		if not genre_nodes[gn]:
			_fail("garbage graph: %s brick did not compile" % gn)
	if _ok:
		_log("garbage graph genre bricks all compiled: %s" % str(genre_nodes.keys()))

	# --- 16. HARDENING: generated_script never crashes on partial bricks ---
	var partial_code = Compiler.generated_script(garbage)
	if partial_code.length() < 40:
		_fail("generated_script on garbage graph produced too little")
	else:
		_log("generated_script on garbage graph: %d chars, no crash" % partial_code.length())
	# generated_script on an empty graph must not crash either
	var empty_graph = load("res://src/bricks/graph.gd").new()
	empty_graph.from_dict({"bricks": []})
	var empty_code = Compiler.generated_script(empty_graph)
	if empty_code.is_empty():
		_fail("generated_script on empty graph returned empty string")
	else:
		_log("generated_script on empty graph: %d chars" % empty_code.length())

	# --- 17. HARDENING: compile_graph accepts a raw AI Dictionary too --------
	var raw_dict_scene = Compiler.compile_graph(DemoTemplates.platformer())
	if raw_dict_scene is Node3D:
		_log("compile_graph accepts a raw Dictionary graph (AI JSON path)")
	else:
		_fail("compile_graph should accept a raw Dictionary graph")

	# --- 18. Genre brick scripts compile clean (no parse errors) -------------
	GameState.reset()
	var genre_graph = load("res://src/bricks/graph.gd").new()
	genre_graph.from_dict({
		"project_name": "Genre", "dimension": "3d", "genre": "platformer",
		"bricks": [
			{"id": "g1", "kind": "spawn", "title": "P", "comment": "", "inputs": [], "outputs": [], "params": {"model": "player", "position": [0, 1, 0]}, "connections": []},
			{"id": "g2", "kind": "move", "title": "M", "comment": "", "inputs": [], "outputs": [], "params": {"speed": 8.0, "jump": 12.0, "gravity": 30.0}, "connections": []},
			{"id": "g3", "kind": "enemy_patrol", "title": "E", "comment": "", "inputs": [], "outputs": [], "params": {"speed": 1.5, "range": 5.0}, "connections": []},
			{"id": "g4", "kind": "hazard", "title": "H", "comment": "", "inputs": [], "outputs": [], "params": {}, "connections": []},
			{"id": "g5", "kind": "checkpoint", "title": "C", "comment": "", "inputs": [], "outputs": [], "params": {}, "connections": []},
			{"id": "g6", "kind": "moving_platform", "title": "MP", "comment": "", "inputs": [], "outputs": [], "params": {"speed": 2.0, "range": 5.0}, "connections": []},
		],
	})
	var genre_scene = Compiler.compile_graph(genre_graph)
	var genre_script_ok := true
	for child in genre_scene.get_children():
		var cs = child.get_script()
		if cs != null and child.name in ["Enemy", "Hazard", "Checkpoint", "MovingPlatform"]:
			var probe := GDScript.new()
			probe.source_code = cs.source_code
			if probe.reload() != OK:
				genre_script_ok = false
				_fail("genre brick '%s' script has a parse error" % child.name)
	if genre_script_ok:
		_log("all 4 genre-brick generated scripts parse clean")
	# hazard/checkpoint need lives/respawn on GameState — verify they exist
	if GameState.has_method("hit_hazard") and GameState.has_method("set_respawn") and GameState.has_method("lose"):
		_log("GameState exposes hit_hazard/set_respawn/lose for generated scripts")
	else:
		_fail("GameState missing hazard/checkpoint API methods")

	# --- 19. Lighting + environment present so 3D isn't a black void --------
	var has_env := false
	var has_sun := false
	for child in garbage_scene.get_children():
		if child is WorldEnvironment:
			has_env = true
		if child is DirectionalLight3D:
			has_sun = true
	if has_env and has_sun:
		_log("3D scene has WorldEnvironment + DirectionalLight3D (not a black void)")
	else:
		_fail("3D scene missing lighting: env=%s sun=%s" % [has_env, has_sun])

	# --- 20. Multiple coins spawn from a single collide brick ---------------
	var multi = load("res://src/bricks/graph.gd").new()
	multi.from_dict({
		"project_name": "Multi", "dimension": "3d", "genre": "platformer",
		"bricks": [
			{"id": "m1", "kind": "spawn", "title": "P", "comment": "", "inputs": [], "outputs": [], "params": {"model": "player", "position": [0, 1, 0]}, "connections": []},
			{"id": "m2", "kind": "move", "title": "M", "comment": "", "inputs": [], "outputs": [], "params": {"speed": 8.0}, "connections": []},
			{"id": "m3", "kind": "collide", "title": "C", "comment": "", "inputs": [], "outputs": [], "params": {"with": "coin"}, "connections": []},
		],
	})
	var multi_scene = Compiler.compile_graph(multi)
	var multi_coins := 0
	for child in multi_scene.get_children():
		if child is Area3D:
			multi_coins += 1
	if multi_coins >= 5:
		_log("one collide brick spawns %d coins (satisfying to collect)" % multi_coins)
	else:
		_fail("expected >= 5 coins from one collide brick, got %d" % multi_coins)
	# coins must be reachable: on the ground plane, not floating
	var max_coin_y := -999.0
	for child in multi_scene.get_children():
		if child is Area3D:
			max_coin_y = max(max_coin_y, child.position.y)
	if max_coin_y <= 2.0:
		_log("coins are at reachable height (max y=%.1f, player ~1.0)" % max_coin_y)
	else:
		_fail("coins float out of reach: max y=%.1f" % max_coin_y)

	# --- 21. WAVE 1: Variable brick — named value store ----------------------
	var var_graph = load("res://src/bricks/graph.gd").new()
	var_graph.from_dict({
		"project_name": "Vars", "dimension": "3d", "genre": "platformer",
		"bricks": [
			{"id": "v1", "kind": "spawn", "title": "P", "comment": "", "inputs": [], "outputs": [], "params": {"model": "player", "position": [0, 1, 0]}, "connections": []},
			{"id": "v2", "kind": "variable", "title": "Coins", "comment": "", "inputs": [], "outputs": [], "params": {"name": "coins", "scope": "game", "type": "number", "op": "add", "amount": 1, "value": 0}, "connections": []},
		],
	})
	GameState.reset()
	GameState.vars.clear()
	Compiler.compile_graph(var_graph)
	# the Variable brick must have seeded the named value on GameState
	if GameState.vars.has("coins"):
		_log("Variable brick registers 'coins' on GameState")
	else:
		_fail("Variable brick did not register its name")
	# add/set/toggle semantics
	GameState.add_var("coins", 1)
	GameState.add_var("coins", 2)
	if GameState.get_var("coins", 0) == 3:
		_log("add_var accumulates (0 + 1 + 2 = 3)")
	else:
		_fail("add_var wrong: got %s" % str(GameState.get_var("coins", -1)))
	GameState.set_var("coins", 10)
	if GameState.get_var("coins", 0) == 10:
		_log("set_var overwrites")
	else:
		_fail("set_var wrong")
	GameState.toggle_var("door")
	if GameState.get_var("door", true) == true:
		_log("toggle_var flips a bool (false -> true)")
	else:
		_fail("toggle_var wrong")
	GameState.toggle_var("door")
	if GameState.get_var("door", true) == false:
		_log("toggle_var flips back (true -> false)")
	# unknown var reads are safe (no crash, returns default)
	if GameState.get_var("never_declared", 42) == 42:
		_log("reading an undeclared var returns the default (no crash)")

	# --- 22. WAVE 1: Rule brick — if/then compiles to a watcher --------------
	var rule_graph = load("res://src/bricks/graph.gd").new()
	rule_graph.from_dict({
		"project_name": "Rule", "dimension": "3d", "genre": "platformer",
		"bricks": [
			{"id": "r1", "kind": "spawn", "title": "P", "comment": "", "inputs": [], "outputs": [], "params": {"model": "player", "position": [0, 1, 0]}, "connections": []},
			{"id": "r2", "kind": "variable", "title": "Coins", "comment": "", "inputs": [], "outputs": [], "params": {"name": "coins", "op": "add", "amount": 1}, "connections": []},
			{"id": "r3", "kind": "rule", "title": "Win at 3", "comment": "", "inputs": [], "outputs": [], "params": {"cond_source": "variable", "cond_var": "coins", "cond_op": ">=", "cond_value": 3, "actions": "win"}, "connections": []},
		],
	})
	GameState.reset()
	GameState.vars.clear()
	var rule_scene = Compiler.compile_graph(rule_graph)
	# a Rule must compile to a watcher node whose script parses clean
	var rule_node = null
	for child in rule_scene.get_children():
		if str(child.name).begins_with("Rule_"):
			rule_node = child
			break
	if rule_node != null:
		var rs = rule_node.get_script()
		if rs != null:
			var rprobe := GDScript.new()
			rprobe.source_code = rs.source_code
			if rprobe.reload() == OK:
				_log("Rule brick compiles to a clean watcher script")
			else:
				_fail("Rule brick script has a parse error")
			if str(rs.source_code).contains("get_var(\"coins\""):
				_log("Rule reads the 'coins' variable in its condition")
			else:
				_fail("Rule condition does not reference the variable")
			if str(rs.source_code).contains("check_win"):
				_log("Rule fires check_win() as its action")
			else:
				_fail("Rule action body missing the win verb")
		else:
			_fail("Rule watcher node has no script")
	else:
		_fail("no Rule_ watcher node in compiled scene")
	# rule logic is data-only: the condition/action expansion is deterministic
	var rule_src = Compiler.generated_script(rule_graph)
	if rule_src.contains("rule: if") and rule_src.contains("win"):
		_log("code view shows the rule in plain language")
	else:
		_fail("code view missing the rule summary")

	# --- 23. WAVE 1: IR validation -------------------------------------------
	var bad_graph = load("res://src/bricks/graph.gd").new()
	bad_graph.from_dict({
		"project_name": "Bad", "dimension": "3d", "genre": "platformer",
		"bricks": [
			{"id": "dup", "kind": "spawn", "title": "A", "comment": "", "inputs": [], "outputs": [], "params": {"model": "player"}, "connections": []},
			{"id": "dup", "kind": "spawn", "title": "B", "comment": "", "inputs": [], "outputs": [], "params": {"model": "player"}, "connections": []},
			{"id": "rr", "kind": "rule", "title": "R", "comment": "", "inputs": [], "outputs": [], "params": {"cond_source": "variable", "cond_var": "ghost", "cond_op": ">=", "cond_value": 1, "actions": "win"}, "connections": []},
		],
	})
	var problems = bad_graph.validate_ir()
	var codes := []
	for pr in problems:
		if pr is Dictionary:
			codes.append(str(pr.get("code", "")))
	if codes.has("duplicate_id"):
		_log("IR validation flags a duplicate brick id")
	else:
		_fail("IR validation missed duplicate id: %s" % str(codes))
	if codes.has("undefined_var"):
		_log("IR validation flags a rule reading an undeclared variable")
	else:
		_fail("IR validation missed undefined var: %s" % str(codes))
	# a clean graph produces no structural problems
	var ok_problems = rule_graph.validate_ir()
	var ok_codes := []
	for pr in ok_problems:
		if pr is Dictionary:
			ok_codes.append(str(pr.get("code", "")))
	if not ok_codes.has("duplicate_id") and not ok_codes.has("undefined_var"):
		_log("IR validation is clean on a well-formed graph")
	else:
		_fail("IR validation false-positived a good graph: %s" % str(ok_codes))

	# --- 24. WAVE 1: time scale + hit-stop helpers are callable --------------
	GameState.set_time_scale(0.5)
	if is_equal_approx(Engine.time_scale, 0.5):
		_log("set_time_scale applies (slow-mo)")
	else:
		_fail("set_time_scale did not apply")
	GameState.set_time_scale(1.0)
	GameState.hit_stop(0.02)
	if is_zero_approx(Engine.time_scale):
		_log("hit_stop freezes time (self-restoring)")
	else:
		_fail("hit_stop did not freeze time")
	# restore immediately so later physics isn't paused
	Engine.time_scale = 1.0

	# --- 25. WAVE 2: new bricks compile + generated scripts parse clean -----
	var w2 = load("res://src/bricks/graph.gd").new()
	w2.from_dict({
		"project_name": "Wave2", "dimension": "3d", "genre": "platformer",
		"bricks": [
			{"id": "w1", "kind": "spawn", "title": "P", "comment": "", "inputs": [], "outputs": [], "params": {"model": "player", "position": [0, 1, 0]}, "connections": []},
			{"id": "w2", "kind": "platform", "title": "Ice", "comment": "", "inputs": [], "outputs": [], "params": {"preset": "ice", "one_way": true, "bounce": 0.0, "friction": 0.05}, "connections": []},
			{"id": "w3", "kind": "background", "title": "BG", "comment": "", "inputs": [], "outputs": [], "params": {"layers": 3, "theme": "night"}, "connections": []},
			{"id": "w4", "kind": "sky", "title": "Sky", "comment": "", "inputs": [], "outputs": [], "params": {"preset": "sunset"}, "connections": []},
			{"id": "w5", "kind": "door", "title": "Door", "comment": "", "inputs": [], "outputs": [], "params": {"target_level": "2", "target_entry": "start", "needs_var": "coins"}, "connections": []},
			{"id": "w6", "kind": "entry", "title": "Entry", "comment": "", "inputs": [], "outputs": [], "params": {"marker": "start"}, "connections": []},
		],
	})
	GameState.reset()
	var w2_scene = Compiler.compile_graph(w2)
	if w2_scene is Node3D:
		_log("Wave 2 graph (platform/background/sky/door/entry) compiles to Node3D")
	else:
		_fail("Wave 2 graph failed to compile")
	# each node with a script must parse clean; platform/entry are plain nodes
	var w2_nodes := {}
	for child in w2_scene.get_children():
		if child.name in ["Platform", "Door"] or str(child.name).begins_with("Entry_"):
			w2_nodes[str(child.name)] = true
			var cs = child.get_script()
			if cs != null:
				var probe := GDScript.new()
				probe.source_code = cs.source_code
				if probe.reload() != OK:
					_fail("Wave 2 '%s' script has a parse error" % child.name)
	if w2_nodes.has("Platform") and w2_nodes.has("Door") and w2_nodes.has("Entry_start"):
		_log("platform/door/entry nodes built (door script parses clean)")
	else:
		_fail("Wave 2 nodes missing: %s" % str(w2_nodes.keys()))
	# background layers + sky env present
	var bg_count := 0
	var has_sky := false
	for child in w2_scene.get_children():
		if str(child.name).begins_with("Bg"):
			bg_count += 1
		if child is WorldEnvironment:
			has_sky = true
	if bg_count == 3:
		_log("background brick made 3 layers")
	else:
		_fail("expected 3 background layers, got %d" % bg_count)
	if has_sky:
		_log("sky brick installed a themed WorldEnvironment")

	# --- 26. WAVE 2: game-feel knobs reach the generated movement script ---
	var feel = load("res://src/bricks/graph.gd").new()
	feel.from_dict({
		"project_name": "Feel", "dimension": "2d", "genre": "platformer",
		"bricks": [
			{"id": "f1", "kind": "spawn", "title": "P", "comment": "", "inputs": [], "outputs": [], "params": {"model": "player", "position": [0, 200, 0], "coyote_time": 0.12, "jump_buffer": 0.15, "jump_cut": 0.5, "fall_gravity": 2.0}, "connections": []},
			{"id": "f2", "kind": "move", "title": "M", "comment": "", "inputs": [], "outputs": [], "params": {"speed": 8.0}, "connections": []},
		],
	})
	var feel_scene = Compiler.compile_graph(feel)
	var feel_player = null
	for child in feel_scene.get_children():
		if child is CharacterBody2D:
			feel_player = child
			break
	if feel_player != null:
		var fs = feel_player.get_script()
		if fs != null:
			var src := str(fs.source_code)
			var feel_ok := true
			if not src.contains("COYOTE"): feel_ok = false
			if not src.contains("BUFFER"): feel_ok = false
			if not src.contains("JUMP_CUT"): feel_ok = false
			if not src.contains("FALL_GRAV"): feel_ok = false
			if feel_ok:
				_log("movement script carries all 4 game-feel knobs")
			else:
				_fail("movement script missing game-feel knobs")
			if src.contains("0.120000") and src.contains("2.000000"):
				_log("game-feel values come from the Spawn brick (0.12 coyote, 2.0 fall grav)")
			else:
				_fail("game-feel values did not come from the brick")
		else:
			_fail("feel player has no movement script")
	else:
		_fail("no player in feel scene")

	# --- 27. WAVE 3: multi-level compiles to hidden sibling levels -----------
	var ml = load("res://src/bricks/graph.gd").new()
	var lvl2 := {
		"dimension": "3d", "genre": "platformer",
		"bricks": [
			{"id": "l2s", "kind": "spawn", "title": "P2", "comment": "", "inputs": [], "outputs": [], "params": {"model": "player", "position": [0, 1, 0]}, "connections": []},
			{"id": "l2e", "kind": "entry", "title": "Start", "comment": "", "inputs": [], "outputs": [], "params": {"marker": "start"}, "connections": []},
		],
	}
	ml.from_dict({
		"project_name": "Multi", "dimension": "3d", "genre": "platformer",
		"bricks": [
			{"id": "m1", "kind": "spawn", "title": "P", "comment": "", "inputs": [], "outputs": [], "params": {"model": "player", "position": [0, 1, 0]}, "connections": []},
			{"id": "m2", "kind": "door", "title": "To L2", "comment": "", "inputs": [], "outputs": [], "params": {"target_level": "2", "target_entry": "start"}, "connections": []},
		],
		"levels": [lvl2],
	})
	GameState.reset()
	var ml_scene = Compiler.compile_graph(ml)
	var has_lvl1 := false
	var has_lvl2 := false
	var has_mgr := false
	for child in ml_scene.get_children():
		if str(child.name) == "Level1":
			has_lvl1 = true
		if str(child.name) == "Level2":
			has_lvl2 = true
			if not child.visible:
				_log("level 2 starts hidden (level 1 is active)")
			else:
				_fail("level 2 should start hidden")
		if str(child.name) == "LevelManager":
			has_mgr = true
			var mscript = child.get_script()
			if mscript != null:
				var mp := GDScript.new()
				mp.source_code = mscript.source_code
				if mp.reload() == OK:
					_log("LevelManager script parses clean")
				else:
					_fail("LevelManager script parse error")
	if has_lvl1 and has_lvl2 and has_mgr:
		_log("multi-level: Level1 + hidden Level2 + LevelManager all present")
	else:
		_fail("multi-level missing nodes (l1=%s l2=%s mgr=%s)" % [str(has_lvl1), str(has_lvl2), str(has_mgr)])

	# --- 28. WAVE 3: AI iterative edit — apply a structured diff (offline) ----
	var Gen = load("res://src/ai/brick_generator.gd")
	var edit_graph = load("res://src/bricks/graph.gd").new()
	edit_graph.from_dict({
		"project_name": "Edit", "dimension": "3d", "genre": "platformer",
		"bricks": [
			{"id": "e1", "kind": "spawn", "title": "P", "comment": "", "inputs": [], "outputs": [], "params": {"model": "player", "position": [0, 1, 0]}, "connections": []},
			{"id": "e2", "kind": "move", "title": "M", "comment": "", "inputs": [], "outputs": [], "params": {"speed": 8.0}, "connections": []},
		],
	})
	var before_count: int = edit_graph.bricks.size()
	var diff := {
		"summary": "Added an enemy and made it chase.",
		"ops": [
			{"op": "add", "type": "enemy_patrol", "params": {"speed": 4.0}},
			{"op": "modify", "id": "e2", "params": {"speed": 12.0}},
			{"op": "connect", "from": "e1", "to": "enemy_patrol"},
		],
	}
	var edit_result = Gen.apply_edit(edit_graph, diff)
	var applied := int(edit_result.get("applied", 0)) if edit_result is Dictionary else 0
	if edit_graph.bricks.size() == before_count + 1:
		_log("AI edit added one brick (graph %d -> %d)" % [before_count, edit_graph.bricks.size()])
	else:
		_fail("AI edit should add exactly one brick, got %d" % edit_graph.bricks.size())
	# the modify op changed the move brick's speed
	var moved = edit_graph.get_brick("e2")
	if not moved.is_empty() and float(moved["params"].get("speed", 0.0)) == 12.0:
		_log("AI edit modify op changed move speed to 12")
	else:
		_fail("AI modify op did not change speed")
	# the connect op wired spawn -> the new enemy
	var wired := false
	for conn in edit_graph.get_brick("e1").get("connections", []):
		if conn is Dictionary:
			var tb = edit_graph.get_brick(str(conn.get("to_brick", "")))
			if not tb.is_empty() and str(tb.get("kind", "")) == "enemy_patrol":
				wired = true
	if wired:
		_log("AI edit connect op wired spawn -> enemy_patrol")
	else:
		_fail("AI connect op did not wire spawn -> enemy")
	# undo via snapshot restore
	var snap = Gen.snapshot(edit_graph)
	if snap.has("bricks") and snap["bricks"].size() == edit_graph.bricks.size():
		_log("snapshot captures the graph for undo")
	else:
		_fail("snapshot failed")

	# --- 29. WAVE 3: suggest_next returns useful one-click suggestions --------
	var sugg_graph := {
		"bricks": [
			{"id": "s1", "kind": "spawn", "title": "P", "comment": "", "inputs": [], "outputs": [], "params": {"model": "player"}, "connections": []},
			{"id": "s2", "kind": "move", "title": "M", "comment": "", "inputs": [], "outputs": [], "params": {}, "connections": []},
			{"id": "s3", "kind": "collide", "title": "C", "comment": "", "inputs": [], "outputs": [], "params": {}, "connections": []},
		],
	}
	var suggestions = Gen.suggest_next(sugg_graph)
	if suggestions.size() > 0 and suggestions.size() <= 3:
		_log("suggest_next returns %d suggestions (capped at 3)" % suggestions.size())
		var first_kind := str(suggestions[0].get("kind", "")) if suggestions[0] is Dictionary else ""
		if first_kind == "score" or first_kind == "enemy_patrol" or first_kind == "winlose":
			_log("first suggestion is a sensible next brick (%s)" % first_kind)
		else:
			_fail("suggestion kind unexpected: %s" % first_kind)
	else:
		_fail("suggest_next returned %d (want 1-3)" % suggestions.size())

	# --- 30. WAVE 4: Inventory brick seeds a named item counter ---------------
	var inv_graph = load("res://src/bricks/graph.gd").new()
	inv_graph.from_dict({
		"project_name": "Inv", "dimension": "3d", "genre": "platformer",
		"bricks": [
			{"id": "i1", "kind": "spawn", "title": "P", "comment": "", "inputs": [], "outputs": [], "params": {"model": "player", "position": [0, 1, 0]}, "connections": []},
			{"id": "i2", "kind": "inventory", "title": "Keys", "comment": "", "inputs": [], "outputs": [], "params": {"item": "key", "op": "add", "amount": 1}, "connections": []},
		],
	})
	GameState.reset()
	GameState.vars.clear()
	Compiler.compile_graph(inv_graph)
	if GameState.vars.has("inv_key"):
		_log("inventory brick seeds 'inv_key' counter")
	else:
		_fail("inventory did not seed inv_key")
	GameState.add_var("inv_key", 1)
	if GameState.get_var("inv_key", 0) == 1:
		_log("collecting a key increments inv_key")

	# --- 31. WAVE 4: Level brick paints a real tile level ---------------------
	var lvchk_graph = load("res://src/bricks/graph.gd").new()
	lvchk_graph.from_dict({
		"project_name": "Tiles", "dimension": "2d", "genre": "platformer",
		"bricks": [
			{"id": "t1", "kind": "spawn", "title": "P", "comment": "", "inputs": [], "outputs": [], "params": {"model": "player", "position": [0, 200, 0]}, "connections": []},
			{"id": "t2", "kind": "level", "title": "Map", "comment": "", "inputs": [], "outputs": [], "params": {"pattern": "..........;....^^....;##########", "tile": 32.0, "theme": "grass"}, "connections": []},
		],
	})
	var lvchk_scene = Compiler.compile_graph(lvchk_graph)
	var tile_count := 0
	var spike_count := 0
	for child in lvchk_scene.get_children():
		# Godot auto-renames duplicate-named siblings to @Class@N, so count by
		# class + a marker: solid tiles are StaticBody2D named Tile/@StaticBody2D,
		# spikes are Area2D named Spike/@Area2D.
		if child is StaticBody2D and str(child.name) != "Ground":
			tile_count += 1
		elif child is Area2D and str(child.name) != "Ground":
			spike_count += 1
	if tile_count == 10:
		_log("level brick painted 10 solid tiles from the pattern")
	else:
		_fail("expected 10 tiles, got %d" % tile_count)
	if spike_count == 2:
		_log("level brick painted 2 spike hazards")
	else:
		_fail("expected 2 spikes, got %d" % spike_count)

	# --- 32. WAVE 8: schema versioning + migration ----------------------------
	# Old projects carry no schema_version; a brick rename used to orphan them.
	if graph.to_dict().has("schema_version"):
		_log("schema: to_dict stamps schema_version")
	else:
		_fail("to_dict() does not stamp schema_version")
	var legacy := {"project_name": "Old", "dimension": "3d", "genre": "platformer",
		"bricks": [{"kind": "spawn", "params": {"model": "player"}},
			{"type": "move", "label": "M", "params": null}, "not-a-dict"]}
	var mg: Dictionary = graph.migrate(legacy)
	if int(mg.get("schema_version", 0)) == BrickGraph.SCHEMA_VERSION:
		_log("schema: migrate upgrades a v1 dict")
	else:
		_fail("migrate did not upgrade a v1 dict")
	var mgb: Array = mg.get("bricks", [])
	var normalised_ok: bool = mgb.size() == 2 and str(mgb[0].get("id", "")) != "" and str(mgb[0].get("kind", "")) == "spawn" and (mgb[0].get("params", null) is Dictionary) and (mgb[0].get("connections", null) is Array)
	if normalised_ok:
		_log("schema: v1 bricks normalised to the canonical shape")
	else:
		_fail("v1 bricks were not normalised (got %d)" % mgb.size())
	if mgb.size() == 2 and str(mgb[1].get("kind", "")) == "move":
		_log("schema: legacy 'type'/'label' keys mapped to kind/title")
	else:
		_fail("legacy 'type' key was not mapped to kind")
	# from_dict must survive a versionless dict: strip the stamp, round-trip a
	# graph that actually HAS bricks, and confirm nothing is lost.
	var lg: Dictionary = graph.to_dict()
	lg.erase("schema_version")
	lg["bricks"] = [{"id": "a", "kind": "spawn", "title": "S", "comment": "",
		"inputs": [], "outputs": [], "params": {"model": "player"}, "connections": []}]
	var rg = load("res://src/bricks/graph.gd").new()
	rg.from_dict(lg)
	var reloaded_ok: bool = rg.bricks.size() == 1 and str(rg.bricks[0].get("kind", "")) == "spawn" and (rg.bricks[0].get("params", null) is Dictionary)
	if reloaded_ok:
		_log("schema: from_dict loads a versionless dict without losing bricks")
	else:
		_fail("from_dict lost bricks on a versionless dict (%d)" % rg.bricks.size())

	# --- 33. WAVE 8: named event bus -----------------------------------------
	var hits: Array = []
	var first_cb := func(_n, _p): hits.append(1)
	GameState.listen_event("unit_test_event", first_cb)
	GameState.emit_event("unit_test_event", null)
	if hits.size() == 1:
		_log("eventbus: emit reaches the listener")
	else:
		_fail("eventbus listener was not called (%d)" % hits.size())
	GameState.emit_event("nobody_listens", null)
	_log("eventbus: emit with no listeners is a no-op")
	# a second listener also receives the same event
	var second_cb := func(_n, _p): hits.append(1)
	GameState.listen_event("unit_test_event", second_cb)
	GameState.emit_event("unit_test_event", null)
	if hits.size() == 3:
		_log("eventbus: every listener on a channel receives the event")
	else:
		_fail("expected 3 deliveries total, got %d" % hits.size())
	# removing one leaves the other working
	GameState.unlisten_event("unit_test_event", second_cb)
	var after_unsub: int = hits.size()
	GameState.emit_event("unit_test_event", null)
	if hits.size() == after_unsub + 1:
		_log("eventbus: unlisten stops delivery to that listener only")
	else:
		_fail("unlisten did not stop delivery (expected %d, got %d)" % [after_unsub + 1, hits.size()])
	GameState.unlisten_event("unit_test_event", first_cb)
	GameState.unlisten_event("unit_test_event", func(_n, _p): pass)
	var after_all: int = hits.size()
	GameState.emit_event("unit_test_event", null)
	if hits.size() == after_all:
		_log("eventbus: unlisten with an unknown token is safe")
	else:
		_fail("unknown-token unlisten disturbed delivery")
	GameState.emit_event("", null)
	_log("eventbus: empty event name is ignored")

	# --- 35. WAVE 12: the code escape hatch must stay READ-ONLY ---------------
	# A TextEdit is editable by default. Left as-is this let a user type raw
	# GDScript into their game, breaking the product's core rule.
	var main_ui = load("res://src/ui/main.gd")
	var main_src := ""
	if main_ui != null:
		main_src = str(main_ui.source_code)
	if main_src.contains("code_panel.editable = false"):
		_log("compliance: the code view is read-only (no raw code editing)")
	else:
		_fail("code_panel is a TextEdit with no editable=false — raw code editing is exposed")

	# --- 35b. AUDIT: NaN/Inf must never reach a node transform ---------------
	# A node at (nan,nan,nan) makes the whole game unplayable, and a user can
	# produce one by typing a bad number. _coerce_num must reject non-finite.
	var nan_graph = load("res://src/bricks/graph.gd").new()
	nan_graph.from_dict({
		"project_name": "NaN", "dimension": "3d", "genre": "platformer",
		"bricks": [
			{"id": "p", "kind": "spawn", "title": "P", "comment": "", "inputs": [], "outputs": [],
				"params": {"model": "player", "position": [NAN, INF, -INF]}, "connections": []},
			{"id": "e", "kind": "enemy_patrol", "title": "E", "comment": "", "inputs": [], "outputs": [],
				"params": {"position": [NAN, NAN, NAN]}, "connections": []},
		]})
	var nan_scene = Compiler.compile_graph(nan_graph)
	var nan_hits: Array = []
	var _st: Array = [nan_scene]
	while not _st.is_empty():
		var _n: Node = _st.pop_back()
		if _n is Node3D:
			var _p3: Vector3 = (_n as Node3D).position
			if is_nan(_p3.x) or is_inf(_p3.x):
				nan_hits.append(str(_n.name))
		for _c in _n.get_children():
			_st.append(_c)
	if nan_hits.is_empty():
		_log("audit: NaN/Inf positions never reach a node transform")
	else:
		_fail("NaN/Inf poisoned transforms: %s" % str(nan_hits))

	# --- 35c. AUDIT: a level brick must never fall back to a placeholder -----
	# It used to: pass 1's wildcard fired the placeholder before pass 2 built
	# it, so the brick silently did nothing.
	var nanfix_graph = load("res://src/bricks/graph.gd").new()
	nanfix_graph.from_dict({
		"project_name": "Lv", "dimension": "3d", "genre": "platformer",
		"bricks": [
			{"id": "lv", "kind": "level", "title": "Lv", "comment": "", "inputs": [], "outputs": [],
				"params": {"pattern": ""}, "connections": []}]})
	var nanfix_scene = Compiler.compile_graph(nanfix_graph)
	var nanfix_ph: Array = []
	for _lc in nanfix_scene.get_children():
		if _lc is Label3D or _lc is Label:
			nanfix_ph.append(str(_lc.name))
	if nanfix_ph.is_empty() and nanfix_scene.get_node_or_null("Ground") != null:
		_log("audit: a level brick with no pattern builds a floor, not a placeholder")
	else:
		_fail("level brick became a placeholder: %s" % str(nanfix_ph))

	# --- 37. AUDIT: the panel layout must give the graph the space -----------
	# Regression lock. The left rail was measuring 563px (35% of the window)
	# because four text buttons in the bottom row and the Apply/Undo/Redo row
	# each refused to shrink, and a custom_minimum_size alone is a MINIMUM, not
	# a cap. Measured at a real 1600px window this must hold.
	var _lay_host := Control.new()
	_lay_host.size = Vector2(1600, 778)
	add_child(_lay_host)
	var _lay_main = load("res://src/ui/main.gd").new()
	_lay_host.add_child(_lay_main)
	for _i in 4:
		await get_tree().process_frame
	var _lay_split: HSplitContainer = null
	var _stk: Array = [_lay_main]
	while not _stk.is_empty():
		var _nd: Node = _stk.pop_back()
		if _nd is HSplitContainer:
			_lay_split = _nd
			break
		for _c in _nd.get_children():
			_stk.append(_c)
	if _lay_split == null:
		_fail("layout: no HSplitContainer found")
	else:
		_lay_split.size = Vector2(1600, 778)
		for _i2 in 3:
			await get_tree().process_frame
		var _lw := 0.0
		var _cw := 0.0
		for _pc in _lay_split.get_children():
			if str(_pc.name) == "LeftPanel":
				_lw = (_pc as Control).size.x
			elif str(_pc.name) == "CenterPanel":
				_cw = (_pc as Control).size.x
		var _lpct: float = _lw / 1600.0 * 100.0
		if _lpct <= 20.0:
			_log("layout: left rail is %.1f%% of the window" % _lpct)
		else:
			_fail("layout: left rail is %.1f%% — too wide" % _lpct)
		if _cw > 800.0:
			_log("layout: the graph gets %.0f px (the widest panel)" % _cw)
		else:
			_fail("layout: the graph is only %.0f px — it must dominate" % _cw)
	_lay_host.queue_free()

	# --- 37b. AUDIT: palette buttons must be wide enough to show their text --
	# The ScrollContainer had no horizontal size flag, so it collapsed to its
	# content minimum (~28px) and every brick button's text was clipped away —
	# the palette rendered as a column of empty grey boxes.
	var _pal_split: HSplitContainer = null
	# a fresh instance (the layout one above was freed)
	var _pal_host := Control.new()
	_pal_host.size = Vector2(1600, 778)
	add_child(_pal_host)
	var _pal_main = load("res://src/ui/main.gd").new()
	_pal_host.add_child(_pal_main)
	for _pf in 4:
		await get_tree().process_frame
	var _ps2: Array = [_pal_main]
	while not _ps2.is_empty():
		var _pn: Node = _ps2.pop_back()
		if _pn is HSplitContainer:
			_pal_split = _pn
			break
		for _pc2 in _pn.get_children():
			_ps2.append(_pc2)
	if _pal_split != null:
		_pal_split.size = Vector2(1600, 778)
		for _pf2 in 3:
			await get_tree().process_frame
	var _btn_w := 0.0
	var _btn_txt := ""
	for _bc in _pal_main.palette.get_children():
		if _bc is Button:
			_btn_w = (_bc as Button).size.x
			_btn_txt = str((_bc as Button).text)
			break
	if _btn_w >= 150.0 and not _btn_txt.strip_edges().is_empty():
		_log("palette: brick buttons are %.0f px wide with text ('%s')" % [_btn_w, _btn_txt])
	else:
		_fail("palette: brick buttons are %.0f px wide, text='%s' — too narrow to read" % [_btn_w, _btn_txt])
	_pal_host.queue_free()

	# --- 37c. AUDIT: EVERY brick kind must build something real ---------------
	# 12 kinds (sound, health, variable, platform, background, sky, door, entry,
	# inventory, timer, follow, destroy) are built in pass 2, but pass 1's
	# wildcard fired a placeholder FIRST — so the brick silently did nothing even
	# with perfect default params. This walks every registered kind and asserts
	# none of them ends up as a Label placeholder.
	var _all_bad: Array = []
	for _k in BrickRegistry.all_kinds():
		var _kb = BrickRef.create(str(_k))
		if _kb.is_empty():
			_all_bad.append(str(_k) + "(uncreatable)")
			continue
		var _kg = load("res://src/bricks/graph.gd").new()
		_kg.from_dict({"project_name": "T", "dimension": "3d", "genre": "platformer",
			"bricks": [
				{"id": "p", "kind": "spawn", "title": "P", "comment": "", "inputs": [], "outputs": [],
					"params": {"model": "player", "position": [0, 1, 0]}, "connections": []},
				_kb]})
		var _ks = Compiler.compile_graph(_kg)
		for _kc in _ks.get_children():
			if _kc is Label3D or _kc is Label:
				_all_bad.append(str(_k))
				break
	if _all_bad.is_empty():
		_log("audit: every registered brick kind builds a real node (no silent placeholders)")
	else:
		_fail("audit: these brick kinds silently do nothing: %s" % str(_all_bad))

	# --- 37d. AUDIT: the undo stack must actually be wired -------------------
	# undo_svc.attach_graph() was never called, so record() returned false on
	# every call and undo/redo silently did nothing at all.
	var _u_host := Control.new()
	_u_host.size = Vector2(1600, 778)
	add_child(_u_host)
	var _u_main = load("res://src/ui/main.gd").new()
	_u_host.add_child(_u_main)
	for _uf in 4:
		await get_tree().process_frame
	if _u_main.undo_svc == null:
		_fail("audit: undo service is not created")
	else:
		var _before: int = _u_main.graph.bricks.size()
		_u_main._add_brick("spawn")
		var _after: int = _u_main.graph.bricks.size()
		var _did_undo: bool = _u_main.undo_svc.can_undo() and _u_main.undo_svc.undo()
		var _now: int = _u_main.graph.bricks.size()
		if _did_undo and _now < _after:
			_log("audit: undo really reverts an add (%d -> %d)" % [_after, _now])
		else:
			_fail("audit: undo did not revert (added %d->%d, can_undo=%s, undid=%s, now %d)" % [
				_before, _after, str(_u_main.undo_svc.can_undo()), str(_did_undo), _now])
	_u_host.queue_free()

	# --- 36. WAVE 5: feature-registry bricks compile in 2D and 3D -----------
	# These bricks are implemented by modules in src/features/ and wired
	# through the FeatureRegistry, so they must compile without touching the
	# core compiler match statements. A brick that silently falls back to a
	# Label placeholder means its module failed to load — so we assert that NO
	# placeholder appears, not merely that the graph compiles.
	var feat_kinds := ["trigger", "collider", "save", "checkpoint_save", "look", "gamepad", "screen", "button", "undo", "pathfind", "state", "widget", "watch", "error_panel", "light", "occluder", "blueprint_def", "blueprint", "attach", "rigid", "audio", "perceive", "style", "hud"]
	var feat_bricks := [
		{"id": "f0", "kind": "spawn", "title": "P", "comment": "", "inputs": [], "outputs": [], "params": {"model": "player", "position": [0, 1, 0]}, "connections": []},
	]
	for fk in feat_kinds:
		var nb = BrickRef.create(fk)
		if nb.is_empty():
			_fail("feature brick '%s' failed to create" % fk)
		else:
			feat_bricks.append(nb)
	# every module must have registered with the FeatureRegistry
	var feat_reg = get_node_or_null("/root/Features")
	if feat_reg != null and feat_reg.has_method("registry"):
		var reg_kinds: Array = feat_reg.registry().kinds()
		for fk in feat_kinds:
			if not reg_kinds.has(fk):
				_fail("feature '%s' never registered with FeatureRegistry" % fk)
		if _ok:
			_log("all %d feature modules registered (%s)" % [feat_kinds.size(), str(reg_kinds)])
	else:
		_fail("Features autoload missing — no feature bricks can build")
	for dim in ["3d", "2d"]:
		var fg = load("res://src/bricks/graph.gd").new()
		fg.from_dict({"project_name": "Feat", "dimension": dim, "genre": "platformer", "bricks": feat_bricks})
		var fscene = Compiler.compile_graph(fg)
		if fscene == null:
			_fail("feature graph (%s) compiled to null" % dim)
			continue
		var placeholders := 0
		var parse_bad := 0
		var built := 0
		for child in fscene.get_children():
			# skip the GameState twin (a duplicate class_name when re-parsed)
			if child.has_method("add_score"):
				continue
			var cls := str(child.get_class())
			if cls == "Label3D" or cls == "Label":
				placeholders += 1
				_fail("%s: '%s' fell back to a placeholder (module did not build it)" % [dim, str(child.name)])
			var cs = child.get_script()
			if cs != null:
				built += 1
				var fp := GDScript.new()
				fp.source_code = cs.source_code
				if fp.reload() != OK:
					parse_bad += 1
					_fail("%s: feature script parse error on %s" % [dim, str(child.name)])
		if placeholders == 0 and parse_bad == 0:
			_log("%s: all %d feature bricks built real nodes, %d scripts parse clean" % [dim, feat_kinds.size(), built])
		else:
			_fail("%s: placeholders=%d parse_bad=%d" % [dim, placeholders, parse_bad])

	# --- 37. AUDIT: every palette kind must change the compiled footprint -----
	# A brick that compiles to NOTHING is invisible to the placeholder sweep
	# above: no Label3D appears, the tree simply never grows. timer, follow,
	# destroy and sound all shipped exactly like that while the palette kept
	# advertising them. So compare the whole tree, not just the failures.
	var _fp_spawn := {"id": "fp0", "kind": "spawn", "title": "P", "comment": "",
		"inputs": [], "outputs": [], "params": {"model": "player"}, "connections": []}
	var _fp_base_graph = load("res://src/bricks/graph.gd").new()
	_fp_base_graph.from_dict({"project_name": "FP", "dimension": "3d", "genre": "platformer", "bricks": [_fp_spawn]})
	var _fp_base := _signature_of(Compiler.compile_graph(_fp_base_graph))
	var _fp_inert: Array[String] = []
	# kinds that legitimately act on GameState or on a node that already exists
	# instead of adding one — each is verified separately below, not excused
	var _fp_state_only := ["health", "variable", "score", "winlose", "rule", "attach",
		"camera", "inventory", "blueprint_def", "button"]
	for kind in BrickRegistry.all_kinds():
		var k := str(kind)
		if k == "spawn" or _fp_state_only.has(k):
			continue
		var nb = BrickRef.create(k)
		if nb.is_empty():
			_fp_inert.append(k + " (create failed)")
			continue
		var g2 = load("res://src/bricks/graph.gd").new()
		g2.from_dict({"project_name": "FP", "dimension": "3d", "genre": "platformer", "bricks": [_fp_spawn]})
		g2.add_brick(nb)
		if _signature_of(Compiler.compile_graph(g2)) == _fp_base:
			_fp_inert.append(k)
	if _fp_inert.is_empty():
		_log("footprint sweep: every palette kind changes the compiled game")
	else:
		_fail("%d brick(s) compile to EXACTLY NOTHING: %s" % [_fp_inert.size(), str(_fp_inert)])

	# A Button belongs to a Screen. Checked directly rather than by signature
	# diff: the menu module keeps its _screens map between compiles, so two
	# compiles in one run interfere with each other (a real smell worth fixing
	# in Features reset, not here).
	var _bg = load("res://src/bricks/graph.gd").new()
	_bg.from_dict({"project_name": "FP", "dimension": "3d", "genre": "platformer", "bricks": [_fp_spawn]})
	var _scr = BrickRef.create("screen")
	_bg.add_brick(_scr)
	var _btn = BrickRef.create("button")
	if _btn is Dictionary:
		(_btn as Dictionary)["params"]["parent_screen"] = str(_scr["id"])
	_bg.add_brick(_btn)
	var _bscene = Compiler.compile_graph(_bg)
	var _buttons_found := 0
	if _bscene != null:
		var _bstack: Array = [_bscene]
		while not _bstack.is_empty():
			var _bn: Node = _bstack.pop_back()
			for _bc in _bn.get_children():
				_bstack.append(_bc)
			if _bn.get_class() == "Button":
				_buttons_found += 1
	if _buttons_found > 0:
		_log("button brick builds a real Button inside its screen (%d found)" % _buttons_found)
	else:
		_fail("button brick produced no Button node")

	# --- AUDIT: user-facing strings must use the translator that works ------
	# Godot's tr() only translates from .translation resources built from a CSV
	# whose FIRST COLUMN IS THE ENGLISH TEXT. This project's CSVs use identifier
	# keys, so tr() silently returned English forever and 17 AI error messages
	# were untranslated in every locale. I18n.t() is the real path (embedded in
	# locales.gd, so it survives into an exported .exe too).
	var _tr_rx := RegEx.new()
	_tr_rx.compile("(^|[^A-Za-z0-9_])tr\\(")
	var _tr_hits := 0
	for path in ["res://src/ai/llm_client.gd", "res://src/ai/brick_generator.gd",
			"res://src/ui/main.gd", "res://src/runtime/game_state.gd",
			"res://src/templates/demo_templates.gd", "res://src/features/errors.gd"]:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var body := f.get_as_text()
		f.close()
		if _tr_rx.search(body) != null:
			_tr_hits += 1
			_fail("%s uses tr(), which never translates here -- use I18n.t()" % path)
	if _tr_hits == 0:
		_log("all user-facing strings go through I18n.t(), not the dead tr() path")

	# --- WAVE 21: the art seam, the music, the 2D conversion, the gallery ---
	# grass moved to the clean tile (the old one tiled like a fence)
	if str(Assets.LOOKS.get("grass", "")) == "tile_0002.png" and Assets.texture("grass") != null:
		_log("grass look resolves to the clean tile_0002 and loads")
	else:
		_fail("grass look is not the verified clean tile")
	# the whole named library reaches the spawn model picker
	var _mc: Array = Assets.model_choices()
	if _mc.has("ladder") and _mc.has("pine") and _mc.has("player"):
		_log("model_choices offers the art library plus the canonical models (%d names)" % _mc.size())
	else:
		_fail("model_choices is missing the new looks: %s" % str(_mc))
	# a 3D-authored position becomes a sane pixel spot in 2D, and real pixel
	# positions pass through untouched
	var _conv := Compiler._spawn_pos_2d([0, 1, 0])
	var _keep := Compiler._spawn_pos_2d([0, 200, 0])
	if _conv == Vector2(0, 252) and _keep == Vector2(0, 200):
		_log("2D spawn conversion: metres become pixels, pixels stay put")
	else:
		_fail("2D spawn conversion wrong: %s / %s" % [str(_conv), str(_keep)])
	# the "theme" kind is real music: longer than the SFX cap and loops cleanly
	var _audio_mod = load("res://src/features/audio.gd").new()
	var _theme: AudioStreamWAV = _audio_mod._stream_for("theme", true)
	if _theme != null and _theme.data.size() > 2 * int(22050 * 0.5) \
			and _theme.loop_mode == AudioStreamWAV.LOOP_FORWARD \
			and _theme.loop_end == _theme.data.size() / 2:
		_log("audio theme synthesises a seamless looping music buffer (%d bytes)" % _theme.data.size())
	else:
		_fail("audio theme did not produce a looping music stream")
	# every gallery demo must clone and compile -- a pitch you cannot play is a lie
	var _gal: Array = DemoTemplates.gallery()
	var _gal_bad := 0
	for _entry in _gal:
		var _gd := DemoTemplates.build(str(_entry["build"]))
		var _gg = load("res://src/bricks/graph.gd").new()
		_gg.from_dict(_gd)
		if Compiler.compile_graph(_gg) == null:
			_gal_bad += 1
	if _gal.size() >= 5 and _gal_bad == 0:
		_log("all %d gallery demos compile into playable scenes" % _gal.size())
	else:
		_fail("gallery demo(s) failed to compile: %d bad of %d" % [_gal_bad, _gal.size()])
	# the web-export status messages exist in every language
	for _lk in ["export_web_no_source", "export_web_templates_missing", "export_web_failed", "export_web_readme"]:
		if I18n.t(_lk) == _lk or I18n.t(_lk).is_empty():
			_fail("locale key %s is missing from the table" % _lk)

	# --- 38. GENRE LIBRARY: naming a type of game must yield its bricks --------
	# The promise is "make me a racing game" -> checkpoints, laps and a timer, not
	# a platformer with cars in it. Two paths have to keep it: the prompt that goes
	# to the model, and the offline builder that runs with no key at all.
	var _g_det: Array = [
		["make a racing game with laps", "racing"],
		["space shooter with waves of enemies", "shooter"],
		["a 2d platformer where a cat collects coins", "platformer"],
		["visual novel with dialogue and choices", "story"],
		["escape the room puzzle with a locked door", "puzzle"],
		["endless runner jumping obstacles", "runner"],
		["top down adventure rpg with a village", "adventure"],
		["physics toy with crates that stack and topple", "physics"],
	]
	var _g_wrong: Array = []
	for _pair in _g_det:
		var _got: String = GenreLibrary.detect(str(_pair[0]))
		if _got != str(_pair[1]):
			_g_wrong.append("%s -> %s" % [str(_pair[0]), _got])
	if _g_wrong.is_empty():
		_log("genre: all %d plain-word phrasings pick the right brick set" % _g_det.size())
	else:
		_fail("genre detection wrong: %s" % str(_g_wrong))
	# an unknown sentence must be reported as a guess, never as a known genre
	if GenreLibrary.detect("i want a thing that does stuff").is_empty():
		_log("genre: an unrecognised idea returns no genre (the UI says it guessed)")
	else:
		_fail("genre detection matched nonsense to a genre")
	# the system prompt must carry the genre shortlist AND only kinds the compiler
	# implements. npc/quest/bullet/ammo were in the old baked list with no module
	# behind them, so the model emitted bricks that silently did nothing.
	var _gen = load("res://src/ai/brick_generator.gd").new()
	add_child(_gen)
	var _sp: String = _gen._system_prompt("make a racing game with checkpoints")
	var _sp_bad: Array = []
	if not _sp.contains("DETECTED GENRE: Racing"):
		_sp_bad.append("no genre block")
	if not _sp.contains("checkpoint"):
		_sp_bad.append("no racing shortlist")
	for _fake in ["npc", "quest", "bullet", "ammo"]:
		# match the vocabulary list itself, not the whole prompt: the art-look names
		# include "question", which contains "quest", and a substring test cries wolf
		var _vocab_part: String = _sp.split("BRICK VOCABULARY")[1] if _sp.contains("BRICK VOCABULARY") else _sp
		if _vocab_part.contains(" " + _fake + ","):
			_sp_bad.append("offers unimplemented " + _fake)
	if not _sp.contains("pathfind") or not _sp.contains("error_panel"):
		_sp_bad.append("vocabulary still a 23-kind snapshot")
	if _sp_bad.is_empty():
		_log("prompt: genre shortlist + the full real vocabulary, no dead kinds offered")
	else:
		_fail("drafting prompt broken: %s" % str(_sp_bad))
	_gen.queue_free()
	# every genre starter must be a clean, compilable game in BOTH dimensions
	var _gbad: Array = []
	for _key in GenreLibrary.GENRES:
		for _dim in ["2d", "3d"]:
			var _d := GenreLibrary.build(str(_key))
			_d["dimension"] = _dim
			var _gr = load("res://src/bricks/graph.gd").new()
			_gr.from_dict(_d)
			for _m in _gr.validate():
				_gbad.append("%s/%s: %s" % [str(_key), _dim, str(_m)])
			for _p in _gr.validate_ir():
				if _p is Dictionary and str(_p.get("code", "")) in ["duplicate_id", "undefined_var"]:
					_gbad.append("%s/%s:%s" % [str(_key), _dim, str(_p.get("code"))])
			var _gs = Compiler.compile_graph(_gr)
			if _gs == null:
				_gbad.append("%s/%s compiled to nothing" % [str(_key), _dim])
			else:
				for _c in _gs.get_children():
					if _c is Label3D or _c is Label:
						_gbad.append("%s/%s placeholder" % [str(_key), _dim])
						break
				_gs.free()
			_gr.free()
	if _gbad.is_empty():
		_log("genre: all %d starter graphs validate and compile in 2D and 3D" % GenreLibrary.GENRES.size())
	else:
		_fail("genre starter graphs broken: %s" % str(_gbad))
	# a genre graph must never come back empty or without a player
	var _ghollow: Array = []
	for _key2 in GenreLibrary.GENRES:
		var _g2 := GenreLibrary.build(str(_key2))
		var _bricks: Array = _g2.get("bricks", [])
		if _bricks.size() < 6:
			_ghollow.append("%s has only %d bricks" % [str(_key2), _bricks.size()])
		var _has_player := false
		for _b in _bricks:
			if str(_b.get("kind", "")) == "spawn" and str(_b.get("params", {}).get("model", "player")) == "player":
				_has_player = true
		if not _has_player:
			_ghollow.append("%s has no player" % str(_key2))
		if not GenreLibrary.has(str(_g2.get("genre", ""))):
			_ghollow.append("%s mislabels its genre" % str(_key2))
	if _ghollow.is_empty():
		_log("genre: every starter is a full graph with a character to control")
	else:
		_fail("genre starters thin: %s" % str(_ghollow))

	# --- 39. STARTER CONTENT ONLY USES SETTINGS THAT EXIST --------------------
	# A curated graph can name a param the brick does not implement, or a choice
	# value outside its option list — and the compiler silently ignores both, so
	# the graph looks right and quietly does nothing. This is what caught a genre
	# starter asking its Timer for mode "every" (valid: once|repeat).
	var _p_bad: Array = []
	var _sets: Array = []
	for _k in GenreLibrary.GENRES:
		# check the authored table, not the built bricks: BrickRef.create() seeds
		# defaults (position, dimension) that are deliberately not user settings
		_sets.append(["genre " + str(_k), GenreLibrary.GENRES[_k].get("bricks", [])])
	for _r in Recipes.list():
		_sets.append(["recipe " + str(_r.get("key", "")), Recipes.find(str(_r.get("key", ""))).get("bricks", [])])
	for _s in _sets:
		for _e in (_s[1] as Array):
			var _ed: Dictionary = _e if _e is Dictionary else {}
			var _kind := str(_ed.get("k", _ed.get("kind", "")))
			var _schema: Dictionary = BrickRef.PARAM_SCHEMA.get(_kind, {})
			var _params: Dictionary = _ed.get("p", _ed.get("params", {}))
			for _pk in _params:
				if not _schema.has(_pk):
					_p_bad.append("%s: %s has no setting '%s'" % [str(_s[0]), _kind, _pk])
					continue
				var _spec: Dictionary = _schema[_pk]
				if _kind == "spawn" and _pk == "model":
					# the art library, not the schema's four guesses, is what compiles
					if not Assets.model_choices().has(str(_params[_pk])):
						_p_bad.append("%s: spawn.model '%s' is not a built-in look" % [str(_s[0]), str(_params[_pk])])
					continue
				if str(_spec.get("type", "")) == "choice":
					var _opts: Array = _spec.get("options", [])
					if not _opts.has(str(_params[_pk])):
						_p_bad.append("%s: %s.%s='%s' is not one of %s" % [str(_s[0]), _kind, _pk, str(_params[_pk]), str(_opts)])
	if _p_bad.is_empty():
		_log("starters: every genre and recipe param is a real setting with a valid value")
	else:
		_fail("starter params invalid: %s" % str(_p_bad))

	_finish()

## The whole compiled tree as one comparable string: every node class plus the
## length of any script attached to it. Two graphs with the same signature
## behave the same, which is what makes an inert brick detectable.
func _signature_of(scene: Node) -> String:
	if scene == null:
		return "null"
	var parts: Array[String] = []
	var stack: Array = [scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var tag := str(n.get_class())
		var sc = n.get_script()
		if sc != null and sc is GDScript:
			tag = tag + ":" + str(sc.source_code.length())
		parts.append(tag)
	parts.sort()
	return "|".join(parts)

func _finish() -> void:
	print("")
	print("checks run: %d" % _checks)
	if _ok:
		print("=== SMOKE TEST: ALL PASS ===")
		get_tree().quit(0)
	else:
		print("=== SMOKE TEST: FAILURES ===")
		get_tree().quit(1)

func _log(msg: String) -> void:
	_checks += 1
	print("  [ok] " + msg)

func _fail(msg: String) -> void:
	_checks += 1
	printerr("  [FAIL] " + msg)
	_ok = false
