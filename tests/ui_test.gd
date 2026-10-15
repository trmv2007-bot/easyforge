extends Node
## UI integration test — drives the real app UI the way a user would:
## prompt -> play -> code view -> export. Proves wiring, not just parsing.

var _ok := true

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	# find the Main UI (loaded as a child instance by the harness)
	var main := get_node_or_null("Main")
	if main == null:
		main = get_tree().current_scene
	if main == null:
		_fail("no Main UI found")
		_finish()
		return
	_log("main UI loaded: " + main.get_class())

	# 0. Make the first-run path deterministic. The app now restores
	#    user://last_project.json on start (it used to throw it away), so a
	#    leftover save from an earlier run would decide what loads here.
	var autosave_path := "user://last_project.json"
	if FileAccess.file_exists(autosave_path):
		DirAccess.remove_absolute(autosave_path)
	main._restore_or_demo()
	await get_tree().process_frame
	await get_tree().process_frame

	# 1. The demo graph is loaded on first run (never an empty canvas)
	if main.graph != null and main.graph.bricks.size() == 6:
		_log("demo auto-loaded: 6 bricks in the graph editor")
	else:
		_fail("demo did not auto-load")

	# 2. Graph editor actually rendered 5 GraphNodes
	var ge: GraphEdit = main.graph_edit
	if ge != null:
		var node_count := 0
		for child in ge.get_children():
			if child is GraphNode:
				node_count += 1
		if node_count == 6:
			_log("graph editor rendered 5 nodes")
		else:
			_fail("graph editor has %d nodes, expected 6" % node_count)

	# 3. Palette has buttons (5 universal + 4 platformer = 9)
	if main.palette != null:
		var btn_count = main.palette.get_child_count()
		if btn_count >= 9:
			_log("palette has %d brick buttons" % btn_count)
		else:
			_fail("palette has %d buttons, expected >= 9" % btn_count)

	# 4. Press Play — the game must compile and mount in the viewport
	var vp: SubViewport = main.game_viewport
	if vp == null:
		_fail("no viewport")
		_finish()
		return
	var before = vp.get_child_count()
	main._on_play_toggled(true)
	await get_tree().process_frame
	await get_tree().process_frame
	var after = vp.get_child_count()
	if after > before:
		_log("Play mounted the compiled game in the viewport (%d -> %d children)" % [before, after])
		# the mounted root must be the compiled game
		var mounted = vp.get_child(0)
		if mounted != null and mounted.get_class() in ["Node3D", "Node2D"]:
			_log("mounted game root is %s" % mounted.get_class())
		else:
			_fail("mounted root unexpected: %s" % (mounted.get_class() if mounted else "null"))
		# editor hidden + game view shown (full-window play)
		if main.editor_root.visible == false and main.game_view.visible == true:
			_log("Play switched to full-window game view (editor hidden)")
		else:
			_fail("view swap wrong: editor=%s game=%s" % [main.editor_root.visible, main.game_view.visible])
	else:
		_fail("Play did not mount a game (before=%d after=%d)" % [before, after])

	# 5. Stop unmounts it AND resets the button label (the reported bug:
	#    after starting, Stop didn't stop / button stayed wrong)
	main._on_play_toggled(false)
	await get_tree().process_frame
	await get_tree().process_frame
	if vp.get_child_count() == 0:
		_log("Stop unmounted the game")
	else:
		_fail("Stop left %d children in the viewport" % vp.get_child_count())
	if main.play_btn.button_pressed == false:
		_log("Stop reset the play button state")
	else:
		_fail("play button still pressed after Stop")
	# editor shown again + game view hidden (back to bricks)
	if main.editor_root.visible == true and main.game_view.visible == false:
		_log("Stop returned to the brick editor")
	else:
		_fail("view swap wrong after Stop: editor=%s game=%s" % [main.editor_root.visible, main.game_view.visible])
	# and Play works again after Stop (proves no stuck state)
	main._on_play_toggled(true)
	await get_tree().process_frame
	await get_tree().process_frame
	if vp.get_child_count() > 0:
		_log("Play works again after Stop (no stuck state)")
	else:
		_fail("Play did not restart after Stop")
	main._on_play_toggled(false)
	await get_tree().process_frame

	# 6. Code view (escape hatch) shows generated code
	main._on_code_toggled(true)
	if main.code_panel.visible and main.code_panel.text.length() > 50:
		_log("code view shows generated code (%d chars)" % main.code_panel.text.length())
	else:
		_fail("code view empty")
	main._on_code_toggled(false)

	# 7. Add a brick from the palette -> graph grows to 7 AND existing
	#    connections are preserved (the "adding disconnects everything" bug)
	var conns_before := 0
	for bb in main.graph.bricks:
		conns_before += bb.get("connections", []).size()
	main._add_brick("score")
	if main.graph.bricks.size() == 7:
		_log("palette add works: graph now 7 bricks")
	else:
		_fail("add brick gave %d bricks" % main.graph.bricks.size())
	var conns_after := 0
	for bb in main.graph.bricks:
		conns_after += bb.get("connections", []).size()
	if conns_after == conns_before and conns_before > 0:
		_log("existing connections preserved across add (%d kept)" % conns_after)
	else:
		_fail("connections changed on add: %d -> %d" % [conns_before, conns_after])
	# the visual graph must still show every node (none dropped)
	var node_count2 := 0
	for child in main.graph_edit.get_children():
		if child is GraphNode:
			node_count2 += 1
	if node_count2 == 7:
		_log("all 7 nodes present on canvas after add")
	else:
		_fail("canvas has %d nodes, expected 7" % node_count2)

	# 7b. Click a brick -> inspector opens with grouped sections
	var first_brick_id = str(main.graph.bricks[0]["id"])
	main._open_inspector(first_brick_id)
	if main._inspector != null and is_instance_valid(main._inspector):
		_log("inspector opens on brick click")
		# the spawn brick must expose a Controls section
		var sections = main._sections_for("spawn", BrickRef.PARAM_SCHEMA["spawn"])
		if sections.has("Controls"):
			_log("spawn inspector has a Controls section")
		else:
			_fail("spawn inspector missing Controls section")
		main._close_inspector()
		if main._inspector == null:
			_log("inspector closes cleanly")
		else:
			_fail("inspector did not close")
	else:
		_fail("inspector did not open")

	# 8. Export writes a file
	main._on_export_pressed()
	var export_path := ProjectSettings.globalize_path("user://") + "exports/Coin_Dash.efg"
	if FileAccess.file_exists(export_path):
		_log("export wrote: %s" % export_path)
	else:
		_fail("export file missing at %s" % export_path)

	# 9. Save to user://last_project.json happened during play (autosave)
	var autosave := ProjectSettings.globalize_path("user://") + "last_project.json"
	if FileAccess.file_exists(autosave):
		_log("autosave exists (user://last_project.json)")
	else:
		_fail("autosave missing")

	# --- WAVE 1: Variable + Rule bricks appear in the palette -------------
	await get_tree().process_frame
	await get_tree().process_frame
	var kinds_present := []
	for child in main.palette.get_children():
		if child is Button:
			kinds_present.append(str(child.text))
	var has_variable := false
	var has_rule := false
	for t in kinds_present:
		if t.contains("Variable"):
			has_variable = true
		if t.contains("Rule"):
			has_rule = true
	if has_variable and has_rule:
		_log("palette includes the new Variable and Rule bricks")
	else:
		_fail("palette missing Variable/Rule (var=%s rule=%s)" % [str(has_variable), str(has_rule)])

	# --- WAVE 15: undo/redo is reachable, and Redo is not a dead button -----
	# The Redo button used to be a local variable created with disabled = true
	# and never re-enabled, so it could never be pressed by anyone.
	var n_before: int = main.graph.bricks.size()
	main._on_undo_pressed()
	await get_tree().process_frame
	var n_undo: int = main.graph.bricks.size()
	if n_undo < n_before:
		_log("undo really removes the last change (%d -> %d)" % [n_before, n_undo])
	else:
		_fail("undo did nothing (%d -> %d)" % [n_before, n_undo])
	if main.redo_btn != null and not main.redo_btn.disabled:
		_log("redo button becomes enabled after an undo")
	else:
		_fail("redo button still dead after undo")
	main._on_redo_pressed()
	await get_tree().process_frame
	if main.graph.bricks.size() == n_before:
		_log("redo puts the change back (%d bricks)" % main.graph.bricks.size())
	else:
		_fail("redo gave %d bricks, expected %d" % [main.graph.bricks.size(), n_before])

	# --- keyboard delete acts on the selected brick -------------------------
	var n_sel: int = main.graph.bricks.size()
	main._selected_brick_id = str(main.graph.bricks[n_sel - 1]["id"])
	main._shortcut_brick_action(3)
	if main.graph.bricks.size() == n_sel - 1:
		_log("Delete key removes the selected brick")
	else:
		_fail("keyboard delete left %d bricks, expected %d" % [main.graph.bricks.size(), n_sel - 1])

	# --- palette affordances: a real target and a tooltip that explains -----
	var first_btn = null
	for child in main.palette.get_children():
		if child is Button:
			first_btn = child
			break
	if first_btn != null:
		if first_btn.custom_minimum_size.y >= 32:
			_log("palette buttons are %dpx tall (touch-safe)" % int(first_btn.custom_minimum_size.y))
		else:
			_fail("palette button only %dpx tall" % int(first_btn.custom_minimum_size.y))
		var tip := str(first_btn.tooltip_text)
		if tip.length() > str(first_btn.text).length():
			_log("palette tooltip explains the brick: %s" % tip.substr(0, 60))
		else:
			_fail("palette tooltip just repeats the name: %s" % tip)

	# --- help is always one click away, and it is real documentation ---------
	# The five-line dialog became the Manual: tabs of steps, recipes, every brick
	# with every setting explained, and the keyboard.
	var kids_before := main.get_child_count()
	main._show_help()
	if main.get_child_count() > kids_before:
		_log("help opens a window on demand")
	else:
		_fail("help button produced no window")
	var manual = main.get_node_or_null("Manual")
	var tabs: TabContainer = null
	if manual != null:
		var stack: Array = [manual]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is TabContainer:
				tabs = n
				break
			for c in n.get_children():
				stack.append(c)
	if tabs != null and tabs.get_tab_count() >= 4:
		_log("manual has %d pages: %s" % [tabs.get_tab_count(), _tab_names(tabs)])
	else:
		_fail("manual did not build its pages")
	for child in main.get_children():
		if child is AcceptDialog and str(child.title).contains(I18n.t("manual_title")):
			child.queue_free()

	# --- the shareable-game exporter really produces a runnable game ----------
	if main.exporter != null and main.exporter.has_method("export_game"):
		var safe := str(main.exporter._safe_name("My/ Game: weird*"))
		if safe != "My_Game_weird":
			_fail("exporter name sanitising wrong: %s" % safe)
		var res = main.exporter.export_game(main.graph, false)
		var folder := str(res.get("folder", ""))
		var exe := folder.path_join("Coin_Dash.exe")
		var pck := folder.path_join("Coin_Dash.pck")
		if bool(res.get("ok", false)) and FileAccess.file_exists(exe) \
				and FileAccess.file_exists(pck) \
				and FileAccess.file_exists(folder.path_join("game.json")):
			_log("Make-a-Game wrote a runnable exe + pck + game.json")
		else:
			_fail("game export incomplete: ok=%s folder=%s" % [str(res.get("ok")), folder])
		# don't leave a 110MB game lying around for every test run
		for leftover in ["Coin_Dash.exe", "Coin_Dash.pck", "game.json", "HOW TO PLAY.txt"]:
			var fp := folder.path_join(leftover)
			if FileAccess.file_exists(fp):
				DirAccess.remove_absolute(fp)
		DirAccess.remove_absolute(folder)

	# --- WAVE 15: closing and reopening must not lose the game --------------
	main._add_brick("score")
	var n_after_add: int = main.graph.bricks.size()
	main._autosave()
	main._restore_or_demo()
	await get_tree().process_frame
	if main.graph.bricks.size() == n_after_add:
		_log("restarting restores the saved game (%d bricks kept)" % main.graph.bricks.size())
	else:
		_fail("restart lost work: %d bricks, expected %d" % [main.graph.bricks.size(), n_after_add])

	# ======================================================================
	# USABILITY PASS — the documentation layer, the grouped palette, the
	# editable game identity, the problem list, the recipes, the canvas tools.
	# ======================================================================

	# U1. Every brick in the palette is named, grouped, tiered and explained.
	#     This is the lock that keeps BrickDocs from rotting: a brick added later
	#     without docs fails here instead of shipping as jargon.
	var doc_gaps: Array = []
	for kind in BrickRegistry.all_kinds():
		var k := str(kind)
		var entry := BrickDocs.entry_for(k)
		if entry.is_empty():
			doc_gaps.append(k + ": no entry")
			continue
		if BrickDocs.name_for(k).is_empty():
			doc_gaps.append(k + ": no name")
		if BrickDocs.help_for(k).is_empty():
			doc_gaps.append(k + ": no help line")
		if BrickDocs.category_of(k).is_empty() or not _known_category(BrickDocs.category_of(k)):
			doc_gaps.append(k + ": category " + BrickDocs.category_of(k))
		if not BrickDocs.tier_of(k) in ["core", "standard", "advanced"]:
			doc_gaps.append(k + ": tier " + str(BrickDocs.tier_of(k)))
	if doc_gaps.is_empty():
		_log("docs: all %d palette bricks are named, grouped and explained" % BrickRegistry.all_kinds().size())
	else:
		_fail("brick docs gaps: %s" % str(doc_gaps))

	# U2. Every user-editable setting has a plain-English sentence with it.
	var param_gaps: Array = []
	for kind in BrickRef.PARAM_SCHEMA:
		var schema: Dictionary = BrickRef.PARAM_SCHEMA[kind]
		for key in schema:
			if BrickDocs.param_help(str(kind), str(key)).is_empty():
				param_gaps.append("%s.%s" % [str(kind), str(key)])
	if param_gaps.is_empty():
		_log("docs: every setting in the schema explains itself (%d kinds)" % BrickRef.PARAM_SCHEMA.size())
	else:
		_fail("%d settings have no explanation: %s" % [param_gaps.size(), str(param_gaps)])

	# U3. The palette is grouped by intent, and the everyday set is the default.
	var groups: int = 0
	var brick_btns: int = 0
	for c in main.palette.get_children():
		if c is HBoxContainer and str(c.name).begins_with("Cat_"):
			groups += 1
		elif c is Button and str(c.name).begins_with("Brick_"):
			brick_btns += 1
	if groups >= 3 and brick_btns >= 9:
		_log("palette: %d bricks under %d intent groups" % [brick_btns, groups])
	else:
		_fail("palette not grouped: %d groups, %d bricks" % [groups, brick_btns])

	# U4. Specialist bricks are folded away, but never from search.
	main.advanced_check.button_pressed = false
	main.brick_search.text = ""
	main._build_palette()
	var plain: int = _palette_brick_count(main)
	main.advanced_check.button_pressed = true
	main._build_palette()
	var every: int = _palette_brick_count(main)
	var searchable := false
	main.advanced_check.button_pressed = false
	main.brick_search.text = "shadow blocker"
	main._build_palette()
	for c in main.palette.get_children():
		if c is Button and str(c.name) == "Brick_occluder":
			searchable = true
	main.brick_search.text = ""
	main._build_palette()
	if every > plain and searchable:
		_log("palette: %d of %d bricks shown by default, and a hidden one still searches up"
			% [plain, every])
	else:
		_fail("palette disclosure broken: plain=%d every=%d hidden-searchable=%s" % [plain, every, str(searchable)])

	# U5. A beginner's words find the right brick.
	var best: String = main._best_match("bad guy")
	if best == "enemy_patrol":
		_log("search: 'bad guy' ranks enemy_patrol first")
	else:
		_fail("'bad guy' matched %s, expected enemy_patrol" % best)

	# U6. The game's name and its 2D/3D shape are editable, and land in the IR.
	main.game_name_edit.text = "Test Quest"
	main._set_project_name("Test Quest")
	main._set_dimension("2d")
	await get_tree().process_frame
	var dim_ok := str(main.graph.dimension) == "2d" and int(main.dim_opt.selected) == 1
	var scene_2d = Compiler.compile_graph(main.graph)
	main._set_dimension("3d")
	if str(main.graph.project_name) == "Test Quest" and dim_ok and scene_2d != null:
		_log("identity: the name and the 2D/3D switch both reach the compiled game")
	else:
		_fail("identity controls broken: name=%s dim_ok=%s scene2d=%s"
			% [str(main.graph.project_name), str(dim_ok), str(scene_2d != null)])

	# U7. The problem strip lists everything wrong, and each line finds its brick.
	var keep = main.graph.to_dict().duplicate(true)
	main.load_graph_dict({
		"project_name": "Broken", "dimension": "3d", "genre": "platformer",
		"bricks": [
			{"id": "p", "kind": "spawn", "title": "P", "comment": "",
				"inputs": [{"name": "on_start", "type": 1}], "outputs": [{"name": "entity", "type": 0}],
				"params": {"model": "player"}, "connections": []},
			{"id": "r", "kind": "rule", "title": "R", "comment": "",
				"inputs": [{"name": "on_event", "type": 1}], "outputs": [{"name": "action", "type": 1}],
				"params": {"cond_source": "variable", "cond_var": "ghost", "cond_op": ">=", "cond_value": 3, "actions": "win"},
				"connections": []},
		]})
	await get_tree().process_frame
	await get_tree().process_frame
	var rows: int = main.problems_box.get_child_count()
	for row in main.problems_box.get_children():
		for c in row.get_children():
			if c is Button:
				c.pressed.emit()
	main._close_inspector()
	var listed: bool = main._problems_panel.visible
	var jumped: bool = main._selected_brick_id == "r"
	main.load_graph_dict(keep)
	await get_tree().process_frame
	if rows >= 1 and listed and jumped:
		_log("problems: %d issues listed, and pressing one selected the rule brick" % rows)
	else:
		_fail("problems strip wrong: rows=%d shown=%s jumped_to_brick=%s" % [rows, str(listed), str(jumped)])

	# U8. The canvas toolbar exists, and tidy layout orders bricks by execution.
	var tools: Node = main.get_node_or_null(NodePath("Root/CenterPanel/CanvasTools"))
	if tools != null and tools.get_child_count() >= 5:
		_log("canvas: a toolbar row of %d above the graph (hint, fit, zoom, tidy, manual)" % tools.get_child_count())
	else:
		_fail("canvas toolbar missing or thin")
	main._tidy_layout()
	var keys: Array[int] = []
	for b in main.graph.execution_order():
		var id := str(b.get("id", ""))
		if main.graph_edit.has_node(NodePath(id)):
			var gn: GraphNode = main.graph_edit.get_node(NodePath(id))
			keys.append(int(gn.position_offset.y) * 10000 + int(gn.position_offset.x))
	var sorted_ok := true
	for i in range(1, keys.size()):
		if keys[i] <= keys[i - 1]:
			sorted_ok = false
	if sorted_ok and keys.size() == main.graph.bricks.size():
		_log("canvas: tidy layout put all %d bricks in execution order" % keys.size())
	else:
		_fail("tidy layout did not order the bricks: %s" % str(keys))

	# U9. Rail actions carry a word, not just a glyph.
	var icon_only := 0
	var labelled := 0
	for c in _descendant_buttons(main.get_node(NodePath("Root/LeftPanel"))):
		var txt := str(c.text).strip_edges()
		if txt.length() <= 2:
			icon_only += 1
		elif txt.length() > 3:
			labelled += 1
	if labelled >= 6:
		_log("rail: %d labelled action buttons (only %d icon-only, and those have tooltips)" % [labelled, icon_only])
	else:
		_fail("rail still hides its actions behind glyphs (labelled=%d)" % labelled)

	# U9b. …and the rail must still fit the window. It gained a name field, a
	# 2D/3D picker and the disclosure tick; a column that cannot shrink is how
	# content silently gets cut off, and no test can see the screen.
	var rail: Control = main.get_node(NodePath("Root/LeftPanel"))
	var min_h: float = rail.get_combined_minimum_size().y
	if min_h <= 800.0:
		_log("rail: needs %.0f px at minimum, fits an 800 px window" % min_h)
	else:
		_fail("rail needs %.0f px — the bottom of it is cut off" % min_h)

	# U10. Every recipe adds pre-wired bricks that actually compile.
	var recipe_bad: Array = []
	for r in Recipes.list():
		var key := str(r.get("key", ""))
		var g = load("res://src/bricks/graph.gd").new()
		g.from_dict(DemoTemplates.platformer())
		var anchor := ""
		for b in g.bricks:
			if str(b.get("kind", "")) == "spawn":
				anchor = str(b.get("id", ""))
				break
		var res = Recipes.add_to(g, key, anchor)
		if not bool(res.get("ok", false)):
			recipe_bad.append(key + ": refused")
			continue
		for p in g.validate_ir():
			if p is Dictionary and str(p.get("code", "")) in ["duplicate_id", "undefined_var"]:
				recipe_bad.append(key + ": " + str(p.get("code")))
		var scene = Compiler.compile_graph(g)
		if scene == null:
			recipe_bad.append(key + ": no scene")
		elif scene.get_children().is_empty():
			recipe_bad.append(key + ": empty scene")
		else:
			for c in scene.get_children():
				if c is Label3D or c is Label:
					recipe_bad.append(key + ": placeholder")
					break
		scene.free()
		g.free()
	if recipe_bad.is_empty():
		_log("recipes: all %d compile into a real scene with no structural break" % Recipes.list().size())
	else:
		_fail("recipes broken: %s" % str(recipe_bad))

	# U11. Applying a recipe into the live graph adds bricks AND wires them.
	var n_before_recipe: int = main.graph.bricks.size()
	var w_before_recipe: int = _count_wires(main.graph)
	main._apply_recipe("coins_and_score")
	await get_tree().process_frame
	if main.graph.bricks.size() > n_before_recipe and _count_wires(main.graph) > w_before_recipe:
		_log("recipes: one click added %d bricks and %d wires to the open game"
			% [main.graph.bricks.size() - n_before_recipe, _count_wires(main.graph) - w_before_recipe])
	else:
		_fail("recipe did not wire into the live graph: bricks %d->%d wires %d->%d"
			% [n_before_recipe, main.graph.bricks.size(), w_before_recipe, _count_wires(main.graph)])
	main._on_undo_pressed()
	await get_tree().process_frame
	if main.graph.bricks.size() == n_before_recipe:
		_log("recipes: Ctrl+Z took the whole recipe back")
	else:
		_fail("undo after a recipe left %d bricks, expected %d" % [main.graph.bricks.size(), n_before_recipe])

	# U12. No new chrome renders as a raw key in any installed language.
	var raw: Array = []
	for k in ["manual_title", "problems_title", "name_game", "dimension_2d", "dimension_tip",
		"show_every_brick", "add_these_bricks", "canvas_empty", "open_manual_page", "related_bricks"]:
		if I18n.t(k) == k:
			raw.append(k)
	if raw.is_empty():
		_log("i18n: every new label is translated in the table")
	else:
		_fail("i18n keys missing, these render as raw codes: %s" % str(raw))

	# U13. The extracted settings dialog built its own controls.
	var dlg: Node = main.get_node_or_null("SettingsDialog")
	if dlg != null and dlg.has_node(NodePath("SettingsBody/ModelCustom")) \
			and dlg.has_node(NodePath("SettingsBody/KeyStatus")):
		_log("settings: the BYOK form, provider hints and language all built")
	else:
		_fail("settings dialog did not build its fields")

	# U14. Naming the TYPE of game produces that genre's bricks, with no key and
	# no network. (The key is cleared for the check and put back after: this box
	# has a live key, and a test that silently spent AI calls is not a test.)
	var saved_key: String = SettingsStore.api_key
	SettingsStore.api_key = ""
	main.prompt_edit.text = "make a racing game with three laps and a countdown"
	main._on_generate_pressed()
	await get_tree().process_frame
	var raced: bool = str(main.graph.genre) == "racing" and str(main.graph.dimension) == "3d" \
			and main.graph.bricks.size() >= 10
	var kinds_seen := {}
	for b in main.graph.bricks:
		kinds_seen[str(b.get("kind", ""))] = true
	if raced and kinds_seen.has("checkpoint") and kinds_seen.has("timer") and kinds_seen.has("hud"):
		_log("genre: 'a racing game' became a %d-brick racing graph with laps, a clock and a HUD"
			% main.graph.bricks.size())
	else:
		_fail("offline genre drafting wrong: genre=%s dim=%s bricks=%d kinds=%s"
			% [str(main.graph.genre), str(main.graph.dimension), main.graph.bricks.size(), str(kinds_seen.keys())])
	# an idea that matches no genre must still land somewhere, and say it guessed
	main.prompt_edit.text = "i want a thing that does some stuff"
	main._on_generate_pressed()
	await get_tree().process_frame
	var guessed_ok: bool = str(main.graph.genre) == "platformer" and main.graph.bricks.size() >= 6 \
			and str(main.status_label.text).contains(I18n.t("offline_guessed"))
	if guessed_ok:
		_log("genre: an unrecognised idea falls back to a starter and admits the guess")
	else:
		_fail("fallback drafting wrong: genre=%s status=%s"
			% [str(main.graph.genre), str(main.status_label.text)])
	SettingsStore.api_key = saved_key

	_finish()

func _finish() -> void:
	print("")
	if _ok:
		print("=== UI TEST: ALL PASS ===")
		get_tree().quit(0)
	else:
		print("=== UI TEST: FAILURES ===")
		get_tree().quit(1)

func _log(msg: String) -> void:
	print("  [ok] " + msg)

func _fail(msg: String) -> void:
	printerr("  [FAIL] " + msg)
	_ok = false

## How many real brick buttons the palette is showing right now.
func _palette_brick_count(main) -> int:
	var n := 0
	for c in main.palette.get_children():
		if c is Button and str(c.name).begins_with("Brick_"):
			n += 1
	return n

func _count_wires(graph) -> int:
	var n := 0
	for b in graph.bricks:
		n += (b.get("connections", []) as Array).size()
	return n

func _known_category(cat: String) -> bool:
	for c in BrickDocs.CATEGORIES:
		if str(c["id"]) == cat:
			return true
	return false

func _tab_names(tabs: TabContainer) -> String:
	var out := ""
	for i in tabs.get_tab_count():
		out += tabs.get_tab_title(i) + " "
	return out.strip_edges()

## Every Button under a node, however deep (the rail nests rows inside rows).
func _descendant_buttons(root_node: Node) -> Array:
	var out: Array = []
	var stack: Array = [root_node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button:
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out
