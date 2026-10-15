extends Control
## Main — the EasyForge window: it owns the layout and wires the pieces together.
##
## Layout: left = your game's name, describe + AI, the brick palette, and the
## "what is wrong" list; center = the brick graph; right = in-app Play preview
## plus the generated code (the escape hatch).
##
## Rules enforced here (from the spec):
##   - never an empty canvas on first run (the demo or your last project loads)
##   - errors never crash the app (they are listed, and each one points at a brick)
##   - Play is in-app (SubViewport), not the editor
##   - BYOK: key lives in SettingsStore (user://), sent only to the provider
##
## What lives elsewhere now, and why:
##   src/bricks/brick_docs.gd  what every brick does, what every setting means,
##                             which words a beginner uses to find it
##   src/ui/ui_theme.gd        colours and the Theme every window is built from
##   src/ui/param_rows.gd      schema -> real controls, one builder for canvas
##                             node and inspector so they cannot drift apart
##   src/ui/recipes.gd         one-click, pre-wired starter sets
##   src/ui/manual.gd          the documentation, in the app, F1 away
##   src/ui/settings_dialog.gd the AI key and language
##
## main.gd is still the owner of every widget reference the tests poke at
## (graph_edit, palette, play_btn, _inspector, ...). The extracted classes build
## UI and report back through Callables and signals; they never touch the graph.

var prompt_edit: TextEdit
var status_label: Label
var graph_edit: GraphEdit
var viewport: SubViewport
var play_btn: Button
var palette: VBoxContainer
var code_panel: TextEdit

var graph = null            # BrickGraphRef instance (autoload-free)
var compiler = null         # Compiler autoload
var ai = null               # AiBrickGenerator instance
var _clipboard: Dictionary = {}   # last copied brick (for paste)
var editor_root: Control = null   # the split with left/center/right panels
var game_view: Control = null     # fullscreen game overlay (shown on Play)
var game_viewport: SubViewport = null
var _inspector: Control = null    # the click-to-open brick inspector panel
var _inspector_brick_id: String = ""
var chat_edit: LineEdit = null    # Wave 3: iterative AI edit input
var undo_btn: Button = null       # Wave 3: undo the last AI edit
var redo_btn: Button = null       # must be a member: as a local it could never un-disable
var _undo_snapshot: Dictionary = {}   # graph snapshot taken before an AI edit
var suggest_box: VBoxContainer = null  # Wave 3: "try next" suggestion buttons
var _press_pos: Vector2 = Vector2.ZERO   # last node press pos (click vs drag)
var _press_brick_id: String = ""         # brick id of the last node press
var undo_svc = null                      # Wave 6: real editor undo/redo stack
var brick_search: LineEdit = null        # palette search box
var palette_empty_hint: Label = null     # "no bricks match" hint
var _selected_brick_id: String = ""      # keyboard shortcuts act on this brick
var _settings_dlg: AcceptDialog = null   # popped directly when a build needs a key
var _game_status: Label = null       # status bar mirrored into the Play view
var _stop_btn: Button = null         # becomes "Quit" when shipping as a game
var _player_mode := false            # true when launched with a game.json beside the exe
var _ui_built := false               # guards against building the window twice
var exporter = null                  # src/export/game_exporter.gd
var _save_timer: Timer = null        # debounced autosave
var _dirty := false
const AUTOSAVE_PATH := "user://last_project.json"

# --- the usability layer -----------------------------------------------------
var game_name_edit: LineEdit = null   # "What is your game called?" — was nowhere
var dim_opt: OptionButton = null      # 2D / 3D — was only ever set by the AI
var problems_box: VBoxContainer = null  # every validation issue, clickable
var advanced_check: CheckBox = null   # the palette's progressive disclosure
var _manual = null                    # the Manual window, built once
var _last_prompt := ""                # what they asked for, for the offline fallback
var _last_problems := ""              # so the list only rebuilds when it changed
var _empty_hint: Label = null         # shown on the canvas when there are no bricks
var _canvas_tools: HBoxContainer = null
var _inspector_slot: Control = null   # the dock at the canvas's right edge
var _problems_panel: Control = null   # the strip that holds the list
var _problems_title: Label = null     # "What needs fixing (3)"

# ---------------------------------------------------------------------------
# Design tokens — one dark palette for the whole product, owned by UiTheme so
# the dialogs and the Manual cannot invent their own colours.
# ---------------------------------------------------------------------------
const C_BG := UiTheme.C_BG
const C_PANEL := UiTheme.C_PANEL
const C_CARD := UiTheme.C_CARD
const C_CARD_HI := UiTheme.C_CARD_HI
const C_ACCENT := UiTheme.C_ACCENT
const C_ACCENT_2 := UiTheme.C_ACCENT_2
const C_TEXT := UiTheme.C_TEXT
const C_MUTED := UiTheme.C_MUTED
const C_BORDER := UiTheme.C_BORDER
const C_GOOD := UiTheme.C_GOOD
const C_BAD := UiTheme.C_BAD
const C_WARN := UiTheme.C_WARN
const C_PORT_IN := UiTheme.C_PORT_IN
const C_PORT_OUT := UiTheme.C_PORT_OUT

## Keep the left rail narrow. HSplitContainer sizes its children from the drag
## offset and each child's minimum, so a long placeholder or a wide button can
## stretch the rail far past what we want (it measured 563px = 35% of the window).
## Clamping here every frame makes the narrow layout actually hold.
const RAIL_MAX_W := UiTheme.RAIL_MAX_W
var _rail_left: VBoxContainer = null

func _process(_delta: float) -> void:
	if _rail_left == null or not is_instance_valid(_rail_left):
		return
	var rail: Control = _rail_left
	if rail.size.x <= RAIL_MAX_W:
		return
	# shrink the split offset by however much the rail is over the cap
	var sp := editor_root as HSplitContainer
	if sp == null:
		return
	var over: float = rail.size.x - RAIL_MAX_W
	sp.split_offset = maxf(sp.split_offset - over, 170.0)

func _ready() -> void:
	graph = load("res://src/bricks/graph.gd").new()
	compiler = Compiler   # the autoload singleton
	# A shipped game is the same app with a game.json beside the exe: it plays,
	# it never opens the editor, and Esc quits like any other Windows game.
	if _start_player_mode():
		return
	# Wave 6: the real undo/redo command stack. record() snapshots the graph
	# BEFORE any mutation, so every manual edit is recoverable (previously only
	# the rare AI edit was undoable).
	undo_svc = load("res://src/features/undo.gd").new()
	add_child(undo_svc)
	# Without this the stack has no graph to snapshot, so record() returns false
	# on every call and undo/redo silently do nothing. Found by audit.
	if undo_svc.has_method("attach_graph"):
		undo_svc.attach_graph(graph)

	_build_ui()

	ai = load("res://src/ai/brick_generator.gd").new()
	add_child(ai)
	exporter = load("res://src/export/game_exporter.gd").new()
	add_child(exporter)
	exporter.progress.connect(func(m): _set_status(m, false))
	compiler.compile_failed.connect(func(issues): _set_status("; ".join(issues), true))
	ai.draft_ready.connect(_on_draft_ready)
	ai.draft_failed.connect(_on_draft_failed)
	ai.finalize_ready.connect(func(msg): _set_status(msg, false))
	ai.finalize_failed.connect(_on_ai_failed)
	ai.edit_ready.connect(_on_edit_ready)
	ai.edit_failed.connect(_on_ai_failed)

	GameRunner.setup(compiler)
	GameRunner.game_stopped.connect(func():
		play_btn.button_pressed = false
		play_btn.text = "▶ " + I18n.t("play")
	)

	SettingsStore.apply_to_llm(LlmClient)
	I18n.set_language(SettingsStore.language)

	_build_palette()
	# Never an empty canvas: either the game the user was last working on, or the
	# playable demo on a genuine first run.
	_restore_or_demo()

	# debounced autosave: a crash or an alt+F4 must never cost a kid their game
	_save_timer = Timer.new()
	_save_timer.wait_time = 1.5
	_save_timer.one_shot = true
	_save_timer.autostart = false
	_save_timer.timeout.connect(_autosave)
	add_child(_save_timer)

	if not SettingsStore.tutorial_done:
		call_deferred("_show_tutorial")

## Where the shipped game data lives, or "" when this launch is the editor.
## In an exported build `res://` is INSIDE the .pck, so game.json sitting next
## to the .exe is only reachable through the executable's own directory.
func _game_json_path() -> String:
	var beside := OS.get_executable_path().get_base_dir().path_join("game.json")
	if FileAccess.file_exists(beside):
		return beside
	# A web build carries its game as res://game.json (written by Publish to
	# Web, packed into the .pck). Only trust it ON the web: a stale file left
	# in the source folder must never boot the desktop editor as a player.
	if OS.has_feature("web") and FileAccess.file_exists("res://game.json"):
		return "res://game.json"
	return ""

## True when this launch is a shipped game (game.json next to the exe) rather
## than the editor. A broken or unreadable game.json falls through to the editor
## so the app is never a dead window.
func _start_player_mode() -> bool:
	var path := _game_json_path()
	if path.is_empty():
		return false
	var d := _read_json(path)
	if d.is_empty():
		return false
	_player_mode = true
	graph.from_dict(d)
	_build_ui()
	GameRunner.setup(compiler)
	DisplayServer.window_set_title(graph.project_name)
	if not GameRunner.play(graph, game_viewport):
		printerr("[EasyForge] the shipped game failed to compile; opening the editor")
		return false
	editor_root.visible = false
	game_view.visible = true
	if _stop_btn != null:
		_stop_btn.text = "✕  " + I18n.t("quit") + "   (Esc)"
	# maximised, not exclusive-fullscreen: Alt+Tab and the taskbar keep working
	get_window().mode = Window.MODE_MAXIMIZED
	print("[EasyForge] playing \"%s\" — Esc quits" % graph.project_name)
	return true

## Load the autosaved project when one exists; otherwise the demo. The autosave## was already being written on Play but nothing ever read it back, so every
## restart silently threw the user's work away (found by the usability audit).
func _restore_or_demo() -> void:
	if FileAccess.file_exists(AUTOSAVE_PATH):
		var d = _read_json(AUTOSAVE_PATH)
		if not d.is_empty():
			load_graph_dict(d)
			_set_status(I18n.t("restored_project") + " — " + graph.project_name, false)
			return
	load_graph_dict(DemoTemplates.platformer())
	_set_status(I18n.t("demo_project") + " — " + I18n.t("tagline"), false)

func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		return parsed
	return {}

## Any mutation calls this; the real write happens on the debounce timer.
## It is also the single place that knows "the graph changed", so the problem
## list and the blank-canvas hint refresh from here — every edit path already
## calls it, which is why no individual handler has to remember to.
func _mark_dirty() -> void:
	_dirty = true
	if _save_timer != null and is_instance_valid(_save_timer):
		_save_timer.start()
	_refresh_problems()
	_update_canvas_hint()

func _autosave() -> void:
	if graph == null or graph.bricks.is_empty():
		return
	if graph.save_to(AUTOSAVE_PATH):
		_dirty = false

func _notification(what: int) -> void:
	# closing the app must not lose the game they just built
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _dirty:
			_autosave()

## Keep the undo/redo buttons reflecting the real stack state.
func _refresh_undo_buttons() -> void:
	var can_u: bool = undo_svc != null and undo_svc.has_method("can_undo") and undo_svc.can_undo()
	var can_r: bool = undo_svc != null and undo_svc.has_method("can_redo") and undo_svc.can_redo()
	if undo_btn != null:
		undo_btn.disabled = not can_u
		undo_btn.tooltip_text = I18n.t("undo") + " (Ctrl+Z)"
	if redo_btn != null:
		redo_btn.disabled = not can_r
		redo_btn.tooltip_text = I18n.t("redo") + " (Ctrl+Shift+Z)"

# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------
## The theme lives in UiTheme so the dialogs, the Manual and this window are the
## same product. Kept as a method because _build_ui and the tests call it here.
func _build_theme() -> Theme:
	return UiTheme.build(1.0)

func _build_ui() -> void:
	# player mode builds the window before _ready continues; never build it twice
	if _ui_built:
		return
	_ui_built = true
	DisplayServer.window_set_title("EasyForge")
	var root := HSplitContainer.new()
	root.name = "Root"
	root.theme = _build_theme()
	add_child(root)
	# Anchors must be set AFTER add_child: a Control added to a not-yet-sized
	# parent computes its rect from that parent, so setting FULL_RECT first left
	# the split at 576px inside a 1600px window (the graph got 0px).
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 0; root.offset_top = 0
	root.offset_right = 0; root.offset_bottom = 0
	root.split_offset = 252
	editor_root = root

	# ================= LEFT =================
	var left := VBoxContainer.new()
	left.name = "LeftPanel"
	# A min alone is not enough: the content was stretching this to 563px (35% of
	# the window). Cap the max too, so the rail is a fixed narrow column and the
	# graph gets the rest.
	left.custom_minimum_size = Vector2(210, 0)
	left.size_flags_stretch_ratio = 0.0   # never take extra space
	# Re-clamp every frame: HSplitContainer hands out space by drag/clamp rules,
	# and without this the rail creeps back out whenever the window resizes.
	left.set_meta("_rail_max", 300)
	_rail_left = left
	root.add_child(left)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 4)
	left.add_child(header_row)
	var header := Label.new()
	header.text = "✨ " + I18n.t("app_title")
	header.add_theme_font_size_override("font_size", 19)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(header)
	# Settings is a gear in the corner of the title, not a mystery glyph at the
	# bottom of a long scroll: this is where a person looks when something needs
	# configuring, and the ⚙ tooltip says so.
	_icon_btn(header_row, "⚙", I18n.t("settings"), _on_settings_pressed)

	# The tagline is deliberately not in this column. The rail is width-capped and
	# height-limited, and every pixel of it is a control: a second line of branding
	# pushed the brick list off the bottom of an 800px window. It lives in the
	# window title, the Manual's first page and the empty-canvas hint instead.

	# --- your game's name and shape -----------------------------------------
	# Both of these used to be invisible settings the AI or a template decided.
	# The name is what the window title, the save file and the shared .exe are
	# built from, and 2D/3D changes every brick's output — a beginner is allowed
	# to care about both, so they get a control instead of a lottery.
	var ident_row := HBoxContainer.new()
	ident_row.add_theme_constant_override("separation", 6)
	ident_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(ident_row)
	game_name_edit = LineEdit.new()
	game_name_edit.name = "GameName"
	game_name_edit.placeholder_text = I18n.t("name_game")
	game_name_edit.tooltip_text = I18n.t("name_game_tip")
	game_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game_name_edit.text = graph.project_name if graph != null else "My Game"
	game_name_edit.text_changed.connect(func(t): _set_project_name(t))
	ident_row.add_child(game_name_edit)
	dim_opt = OptionButton.new()
	dim_opt.name = "Dimension"
	dim_opt.tooltip_text = I18n.t("dimension_tip")
	dim_opt.add_item(I18n.t("dimension_3d"), 0)
	dim_opt.add_item(I18n.t("dimension_2d"), 1)
	dim_opt.item_selected.connect(func(idx): _set_dimension("2d" if idx == 1 else "3d"))
	ident_row.add_child(dim_opt)

	var prompt_label := Label.new()
	# short heading here, the long example lives in the box's placeholder — using
	# describe_prompt for both printed the same sentence twice
	prompt_label.text = I18n.t("describe_short")
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(prompt_label)

	prompt_edit = TextEdit.new()
	prompt_edit.custom_minimum_size = Vector2(0, 44)
	# The rail is 210-260px wide: the full example sentence was cut off mid-word
	# with no ellipsis, which reads as a broken box. Short hint in the box, real
	# example in the tooltip and in the Manual.
	prompt_edit.placeholder_text = I18n.t("prompt_hint")
	prompt_edit.tooltip_text = I18n.t("describe_prompt")
	prompt_edit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(prompt_edit)

	var gen_row := HBoxContainer.new()
	gen_row.add_theme_constant_override("separation", 4)
	gen_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(gen_row)

	var gen_btn := Button.new()
	gen_btn.name = "GenerateBtn"
	gen_btn.text = "✨  " + I18n.t("generate")
	gen_btn.custom_minimum_size = Vector2(0, 36)
	gen_btn.tooltip_text = I18n.t("generate_tip")
	gen_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# the one primary action in the rail — needs no explanation, and says what it does
	UiTheme.paint_primary(gen_btn)
	gen_btn.pressed.connect(_on_generate_pressed)
	gen_row.add_child(gen_btn)
	# Tidy sits beside it as a glyph with a real tooltip: it is the same kind of
	# move (ask the AI for a pass over the graph) and it no longer costs a row.
	# The tooltip names the action as well as describing it, because a bare glyph
	# is a guess.
	_icon_btn(gen_row, "🧹", "%s — %s" % [I18n.t("tidy_ai"), I18n.t("tidy_ai_tip")], _on_finalize_pressed)

	# --- Wave 3: iterative AI chat ("add a boss", "make it harder") ---------
	var chat_label := Label.new()
	chat_label.text = "💬 " + I18n.t("ai_edit")
	chat_label.add_theme_font_size_override("font_size", 11)
	chat_label.modulate = C_ACCENT_2
	left.add_child(chat_label)

	chat_edit = LineEdit.new()
	chat_edit.placeholder_text = I18n.t("chat_hint")
	chat_edit.tooltip_text = I18n.t("ai_edit_placeholder")
	left.add_child(chat_edit)

	var chat_row := HBoxContainer.new()
	chat_row.add_theme_constant_override("separation", 4)
	# Without a shrink flag the three buttons' minimum widths sum up and force
	# the whole rail wide (measured 563px = 35% of the window).
	chat_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(chat_row)
	var edit_btn := Button.new()
	edit_btn.text = "✨ " + I18n.t("ai_edit_apply")
	edit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_btn.add_theme_font_size_override("font_size", 12)
	edit_btn.pressed.connect(_on_edit_pressed)
	chat_row.add_child(edit_btn)
	undo_btn = Button.new()
	undo_btn.text = "↩ " + I18n.t("undo")
	undo_btn.disabled = true
	undo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	undo_btn.add_theme_font_size_override("font_size", 12)
	undo_btn.pressed.connect(_on_undo_pressed)
	chat_row.add_child(undo_btn)
	redo_btn = Button.new()
	redo_btn.text = "↪ " + I18n.t("redo")
	redo_btn.disabled = true
	redo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	redo_btn.add_theme_font_size_override("font_size", 12)
	redo_btn.pressed.connect(_on_redo_pressed)
	chat_row.add_child(redo_btn)

	# --- brick search: filter the palette as you type ------------------------
	# With 50 bricks the list is long, so finding "the right brick" by eye was
	# the real pain point. Matches the label, the kind, and the keywords below.
	# This sits ABOVE the list: a search box you have to scroll past the whole
	# list to reach is not a search box.
	brick_search = LineEdit.new()
	brick_search.name = "BrickSearch"
	brick_search.placeholder_text = I18n.t("search_bricks")
	brick_search.tooltip_text = I18n.t("search_bricks_tip")
	brick_search.clear_button_enabled = true
	brick_search.text_changed.connect(_on_brick_search_changed)
	brick_search.text_submitted.connect(_on_brick_search_submitted)
	left.add_child(brick_search)
	# Progressive disclosure: the palette shows the bricks almost every game needs.
	# Searching always looks through every brick, advanced or not — hiding them
	# from search would be the same dead end as an unhinted list.
	advanced_check = CheckBox.new()
	advanced_check.name = "ShowEveryBrick"
	advanced_check.text = I18n.t("show_every_brick")
	advanced_check.tooltip_text = I18n.t("show_every_brick_tip")
	advanced_check.add_theme_font_size_override("font_size", 11)
	advanced_check.toggled.connect(func(_on): _build_palette())
	left.add_child(advanced_check)
	palette_empty_hint = Label.new()
	palette_empty_hint.name = "PaletteEmptyHint"
	palette_empty_hint.text = I18n.t("search_no_bricks")
	palette_empty_hint.add_theme_font_size_override("font_size", 12)
	palette_empty_hint.modulate = C_MUTED
	palette_empty_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	palette_empty_hint.visible = false
	left.add_child(palette_empty_hint)

	var palette_scroll := ScrollContainer.new()
	palette_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Without this the scroll collapsed to its content's minimum (~28px), which
	# clipped every brick button's text to nothing — the palette rendered as a
	# column of empty grey boxes.
	palette_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	palette_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Always show the vertical bar: with SCROLL_MODE_AUTO it only appears while
	# hovering or dragging, so a beginner with 36 bricks in a 150px window thinks
	# the list simply ends.
	palette_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	palette_scroll.custom_minimum_size = Vector2(0, 150)
	left.add_child(palette_scroll)
	palette = VBoxContainer.new()
	palette.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	palette_scroll.add_child(palette)

	# --- Wave 3: "try next" suggestions (one-click, refreshes as you build) ---
	var suggest_lbl := Label.new()
	suggest_lbl.name = "SuggestLabel"
	suggest_lbl.text = "💡 " + I18n.t("suggest_next")
	suggest_lbl.add_theme_font_size_override("font_size", 11)
	suggest_lbl.modulate = C_ACCENT_2
	left.add_child(suggest_lbl)
	suggest_box = VBoxContainer.new()
	suggest_box.name = "SuggestBox"
	suggest_box.add_theme_constant_override("separation", 4)
	left.add_child(suggest_box)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.custom_minimum_size = Vector2(0, 24)
	left.add_child(status_label)

	# Project actions say what they are. Icon-only buttons hid the difference
	# between the three ways to get something out of EasyForge (a .efg for you, an
	# .exe for a friend, a web build), which is exactly the choice a beginner
	# cannot guess from a glyph.
	var project_row := _icon_row()
	left.add_child(project_row)
	_rail_btn(project_row, "🆕", I18n.t("new_short"), I18n.t("new_project"), _on_new_project_pressed)
	_rail_btn(project_row, "📂", I18n.t("open_short"), I18n.t("open_project"), _on_open_project_pressed)
	_rail_btn(project_row, "💾", I18n.t("save_short"), I18n.t("save_game_file_tip"), _on_export_pressed)
	var share_row := _icon_row()
	left.add_child(share_row)
	# 🚀 is the one that produces a game a friend can actually double-click
	_rail_btn(share_row, "🚀", I18n.t("share_short"), I18n.t("export_game_tip"), _on_export_game_pressed)
	_rail_btn(share_row, "🌐", I18n.t("web_short"), I18n.t("export_web_tip"), _on_export_web_pressed)
	_rail_btn(share_row, "?", I18n.t("help"), I18n.t("manual_tip"), _show_help)

	# ================= CENTER =================
	# The canvas keeps the most space, then a strip underneath for whatever is
	# wrong. A validation problem that only shows as one line in a status label
	# gets ignored; listed, clickable, and next to the bricks it talks about, it
	# gets fixed.
	var center := VBoxContainer.new()
	center.name = "CenterPanel"
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 0)
	root.add_child(center)

	# The canvas toolbar is its OWN row above the graph, right-aligned, with a
	# one-line hint on the left. It used to be a floating child of the graph's
	# PanelContainer — which stretches every child to the full panel — so the five
	# buttons were laid out as five full-height columns across the canvas and the
	# "fit / zoom / tidy" affordance nobody could recognise.
	var tools_row := HBoxContainer.new()
	tools_row.name = "CanvasTools"
	tools_row.add_theme_constant_override("separation", 6)
	tools_row.alignment = BoxContainer.ALIGNMENT_END
	tools_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_child(tools_row)

	var canvas_area := HBoxContainer.new()
	canvas_area.name = "CanvasArea"
	canvas_area.add_theme_constant_override("separation", 0)
	canvas_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(canvas_area)

	var canvas_holder := PanelContainer.new()
	canvas_holder.name = "CanvasHolder"
	canvas_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas_area.add_child(canvas_holder)

	# The brick inspector docks in here, at the right edge of the CANVAS. It used
	# to be a panel pinned to the right edge of the whole window, which meant
	# opening a brick's settings hid the live preview behind it — the one thing you
	# want to watch while you change a number.
	var slot := PanelContainer.new()
	slot.name = "InspectorSlot"
	slot.visible = false
	slot.custom_minimum_size = Vector2(372, 0)
	slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas_area.add_child(slot)
	_inspector_slot = slot
	var GraphEditExt := preload("res://src/ui/graph_edit_ext.gd")
	graph_edit = GraphEditExt.new()
	graph_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph_edit.right_disconnects = true
	graph_edit.connection_lines_curvature = 0.4
	graph_edit.connection_lines_thickness = 3.0
	graph_edit.connection_request.connect(_on_connection_request)
	graph_edit.disconnection_request.connect(_on_disconnection_request)
	graph_edit.brick_dropped.connect(_on_brick_dropped)
	# track the selected brick so Delete / Ctrl+C / Ctrl+V have something to act on
	graph_edit.node_selected.connect(func(n): _selected_brick_id = str(n))
	graph_edit.node_deselected.connect(func(): _selected_brick_id = "")
	# double-click an empty spot: put the cursor in the brick search instead of
	# leaving the person to discover where bricks come from
	graph_edit.gui_input.connect(_on_canvas_gui_input)
	# start the view a little up-left so the first nodes aren't hugging the corner
	graph_edit.scroll_offset = Vector2(60, 40)
	canvas_holder.add_child(graph_edit)
	_build_canvas_tools(tools_row)
	_build_empty_hint(canvas_holder)

	# --- the problems strip ---------------------------------------------------
	var problems_panel := PanelContainer.new()
	problems_panel.name = "ProblemsPanel"
	problems_panel.visible = false
	problems_panel.custom_minimum_size = Vector2(0, 96)
	center.add_child(problems_panel)
	_problems_panel = problems_panel
	var problems_scroll := ScrollContainer.new()
	problems_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	problems_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	problems_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	problems_panel.add_child(problems_scroll)
	var problems_col := VBoxContainer.new()
	problems_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	problems_col.add_theme_constant_override("separation", 2)
	problems_scroll.add_child(problems_col)
	var phead := HBoxContainer.new()
	problems_col.add_child(phead)
	var ptitle := Label.new()
	ptitle.name = "ProblemsTitle"
	ptitle.text = I18n.t("problems_title")
	ptitle.add_theme_font_size_override("font_size", 12)
	ptitle.modulate = C_WARN
	phead.add_child(ptitle)
	_problems_title = ptitle
	var pmore := Label.new()
	pmore.text = "   " + I18n.t("problems_click_hint")
	pmore.add_theme_font_size_override("font_size", 11)
	pmore.modulate = C_MUTED
	phead.add_child(pmore)
	problems_box = VBoxContainer.new()
	problems_box.name = "ProblemsList"
	problems_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	problems_col.add_child(problems_box)

	# ================= RIGHT =================
	var right := VBoxContainer.new()
	right.name = "RightPanel"
	right.custom_minimum_size = Vector2(300, 0)
	root.add_child(right)

	var play_row := HBoxContainer.new()
	right.add_child(play_row)
	play_btn = Button.new()
	play_btn.text = "▶ " + I18n.t("play")
	play_btn.toggle_mode = true
	play_btn.toggled.connect(_on_play_toggled)
	play_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play_row.add_child(play_btn)

	var code_toggle := Button.new()
	code_toggle.text = "</> " + I18n.t("code")
	code_toggle.toggle_mode = true
	code_toggle.toggled.connect(_on_code_toggled)
	play_row.add_child(code_toggle)

	# SubViewport must live inside a SubViewportContainer to render in the UI.
	# (SubViewport is a Node, not a Control — it has no size_flags.)
	var vp_container := SubViewportContainer.new()
	vp_container.name = "PlayViewportContainer"
	vp_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vp_container.stretch = true
	right.add_child(vp_container)

	viewport = SubViewport.new()
	viewport.handle_input_locally = true
	viewport.gui_disable_input = false
	viewport.size = Vector2(400, 300)
	vp_container.add_child(viewport)

	# a small "live preview" caption over the viewport so the right panel is
	# never a mystery blank space
	var preview_cap := Label.new()
	preview_cap.name = "PreviewCaption"
	# Say what clicking does. This box starts the game on a click, and "Live
	# preview" alone gave no clue — the first accidental full-screen Play a person
	# gets is the one they did not mean to press.
	preview_cap.text = "🎮 " + I18n.t("preview_live") + "  ·  " + I18n.t("preview_click_hint")
	preview_cap.add_theme_font_size_override("font_size", 12)
	preview_cap.modulate = C_MUTED
	preview_cap.set_anchors_preset(Control.PRESET_TOP_LEFT)
	preview_cap.position = Vector2(8, 6)
	preview_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp_container.add_child(preview_cap)
	# clicking the preview launches the full interactive game (WASD works there)
	vp_container.gui_input.connect(_on_preview_clicked)

	code_panel = TextEdit.new()
	code_panel.editable = false   # the escape hatch is READ-ONLY: never expose raw code editing
	code_panel.visible = false
	code_panel.custom_minimum_size = Vector2(0, 240)
	code_panel.placeholder_text = I18n.t("code")
	right.add_child(code_panel)

	# ================= FULLSCREEN GAME VIEW (shown on Play) =================
	# A separate overlay that covers the whole window. On Play we hide the
	# editor split and show this, so the game is full-window and WASD binds to
	# the game. On Stop we swap back to the brick editor.
	var gv := Control.new()
	gv.name = "GameView"
	gv.set_anchors_preset(Control.PRESET_FULL_RECT)
	gv.visible = false
	gv.theme = root.theme
	add_child(gv)
	game_view = gv

	# dark backdrop
	var gv_bg := ColorRect.new()
	gv_bg.color = C_BG
	gv_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	gv_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gv.add_child(gv_bg)

	# top bar with a Stop button (Esc also stops)
	var gv_bar := HBoxContainer.new()
	gv_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	gv.add_child(gv_bar)
	var stop_btn := Button.new()
	stop_btn.text = "■  " + I18n.t("stop") + "   (Esc)"
	stop_btn.custom_minimum_size = Vector2(0, 44)
	var stop_sb := StyleBoxFlat.new()
	stop_sb.bg_color = C_BAD
	stop_sb.set_corner_radius_all(8)
	stop_sb.content_margin_left = 18; stop_sb.content_margin_right = 18
	stop_btn.add_theme_stylebox_override("normal", stop_sb)
	stop_btn.add_theme_color_override("font_color", Color("#ffffff"))
	stop_btn.add_theme_font_size_override("font_size", 16)
	stop_btn.pressed.connect(_on_stop_pressed)
	gv_bar.add_child(stop_btn)
	_stop_btn = stop_btn

	# status messages mirrored here so nothing is invisible during Play
	_game_status = Label.new()
	_game_status.name = "GameStatus"
	_game_status.add_theme_font_size_override("font_size", 13)
	_game_status.modulate = C_MUTED
	_game_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_game_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_game_status.custom_minimum_size = Vector2(0, 44)
	gv_bar.add_child(_game_status)

	# the game itself, full-window
	var gv_vp_container := SubViewportContainer.new()
	gv_vp_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	gv_vp_container.offset_top = 52
	gv_vp_container.stretch = true
	gv.add_child(gv_vp_container)
	game_viewport = SubViewport.new()
	game_viewport.handle_input_locally = true
	game_viewport.gui_disable_input = false
	gv_vp_container.add_child(game_viewport)

	# settings dialog
	var dlg := _build_settings_dialog()
	dlg.name = "SettingsDialog"
	_settings_dlg = dlg
	add_child(dlg)

## A shrink-friendly row of icon buttons.
func _icon_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return row

## An icon-only button with tight side margins — the theme's default 14+14 is
## what made a row of them wide enough to force the whole rail open.
func _icon_btn(row: HBoxContainer, glyph: String, tip: String, handler: Callable) -> Button:
	var btn := Button.new()
	btn.text = glyph
	btn.tooltip_text = tip
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_stylebox_override("normal", UiTheme.flat(C_CARD, C_BORDER, 8, 1, 6, 8))
	btn.add_theme_stylebox_override("hover", UiTheme.flat(C_CARD_HI, C_ACCENT_2, 8, 1, 6, 8))
	btn.pressed.connect(handler)
	row.add_child(btn)
	return btn

## An icon AND a word. The rail is narrow, so the label is short and the full
## sentence lives in the tooltip — but the word alone already answers "what does
## this do", which a glyph never did.
func _rail_btn(row: HBoxContainer, glyph: String, label: String, tip: String, handler: Callable) -> Button:
	var btn := _icon_btn(row, "%s %s" % [glyph, label], tip, handler)
	btn.add_theme_font_size_override("font_size", 12)
	btn.clip_text = true
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return btn

# ---------------------------------------------------------------------------
# Canvas affordances: the tools a person reaches for while looking at the graph
# ---------------------------------------------------------------------------
## A small toolbar row above the canvas. Fit and zoom were keyboard-only
## (+/-/0) and there was no way at all to make a scattered AI draft readable
## again, which is the first thing you want after "Make my game".
func _build_canvas_tools(row: Control) -> void:
	_canvas_tools = row as HBoxContainer
	# the hint is what teaches the wiring rule without opening the Manual
	var hint := Label.new()
	hint.name = "CanvasHint"
	hint.text = I18n.t("canvas_wire_hint")
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = C_MUTED
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(hint)
	_tool_btn(row, "⤢", I18n.t("fit_view_tip"), func(): _frame_graph_view())
	_tool_btn(row, "−", I18n.t("zoom_out_tip"), func(): _zoom_canvas(0.9))
	_tool_btn(row, "＋", I18n.t("zoom_in_tip"), func(): _zoom_canvas(1.1))
	_tool_btn(row, "🧲", I18n.t("tidy_layout_tip"), func(): _tidy_layout())
	_tool_btn(row, "❓", I18n.t("manual_tip"), func(): _show_help())

## A toolbar button that stays the size of its glyph. _icon_btn fills its row
## because the rail wants even columns; in a toolbar row next to an expanding
## label that made five tiles ~220x57 each, which read as empty boxes rather than
## buttons and stole the whole row.
func _tool_btn(row: Control, glyph: String, tip: String, handler: Callable) -> Button:
	var btn := Button.new()
	btn.text = glyph
	btn.tooltip_text = tip
	btn.add_theme_font_size_override("font_size", 13)
	btn.custom_minimum_size = Vector2(34, 30)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.add_theme_stylebox_override("normal", UiTheme.flat(C_CARD, C_BORDER, 8, 1, 4, 4))
	btn.add_theme_stylebox_override("hover", UiTheme.flat(C_CARD_HI, C_ACCENT_2, 8, 1, 4, 4))
	btn.pressed.connect(handler)
	row.add_child(btn)
	return btn

## Arrange every brick by the order the game actually runs them: roots on the
## left, what they fire next on the right, wrapping into rows. Deterministic, so
## pressing it twice moves nothing.
func _tidy_layout() -> void:
	if graph == null or graph.bricks.is_empty():
		return
	if undo_svc != null:
		undo_svc.record("tidy layout")
	# Place them in the order the game runs them, four across then wrap, so the
	# reading direction matches the execution direction.
	var order = graph.execution_order()
	var slot := 0
	for b in order:
		var id := str(b.get("id", ""))
		if not graph_edit.has_node(NodePath(id)):
			continue
		var gn := graph_edit.get_node(NodePath(id)) as GraphNode
		if gn == null:
			continue
		gn.position_offset = Vector2(60 + (slot % 4) * 340, 40 + int(slot / 4) * 220)
		slot += 1
	# anything the ordering did not return (no id at all) goes at the end rather
	# than staying buried under the tidy block
	for child in graph_edit.get_children():
		if child is GraphNode:
			var rest: GraphNode = child
			if rest.position_offset.x < 40.0 or rest.position_offset.x > 2000.0:
				rest.position_offset = Vector2(60 + (slot % 4) * 340, 40 + int(slot / 4) * 220)
				slot += 1
	_mark_dirty()
	_frame_graph_view()
	_refresh_undo_buttons()
	_set_status(I18n.t("tidy_layout_done"), false)

## The blank-canvas message. It should never appear (the demo or the last project
## loads first), but when a person does empty the graph they must not be left
## staring at a grey field with no clue what the next move is.
##
## It fills the holder and centres itself, because a PanelContainer lays out every
## child as the full panel rect — a "centre anchored" child there collapses to a
## zero-size box in the middle instead of a readable message.
func _build_empty_hint(holder: Control) -> void:
	var cover := Control.new()
	cover.name = "EmptyCanvasCover"
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.visible = false
	holder.add_child(cover)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.add_child(box)
	var l := Label.new()
	l.name = "EmptyCanvasText"
	l.text = I18n.t("canvas_empty")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 14)
	l.modulate = C_MUTED
	l.custom_minimum_size = Vector2(360, 0)
	box.add_child(l)
	var start := Button.new()
	start.text = "🆕  " + I18n.t("new_project")
	start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start.pressed.connect(_on_new_project_pressed)
	box.add_child(start)
	_empty_hint = l

## Keep the blank-canvas hint honest: it shows only when the canvas really is
## empty, and hides the moment anything is on it.
func _update_canvas_hint() -> void:
	if _empty_hint == null or not is_instance_valid(_empty_hint):
		return
	var empty: bool = graph == null or graph.bricks.is_empty()
	var cover := _empty_hint.get_parent().get_parent()
	if cover != null:
		cover.visible = empty

func _on_canvas_gui_input(event: InputEvent) -> void:
	# double-clicking the background puts you in the brick search — the fastest
	# route to "I want to add something here"
	if event is InputEventMouseButton and event.pressed and event.double_click \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if brick_search != null:
			brick_search.grab_focus()

# ---------------------------------------------------------------------------
# Problems: everything wrong with this game, listed, each one pointing at a brick
# ---------------------------------------------------------------------------
## Both validators, one list. Before this only issues[0] was ever shown, so a
## graph with four problems reported one at a time and the person had to press
## Play four times to learn anything.
func _collect_problems() -> Array:
	var items: Array = []
	if graph == null:
		return items
	for m in graph.validate():
		items.append({"sev": "warn", "text": str(m), "brick": "", "fix": ""})
	var ir_problems = graph.validate_ir() if graph.has_method("validate_ir") else []
	for p in ir_problems:
		var d: Dictionary = p if p is Dictionary else {}
		var code := str(d.get("code", ""))
		var sev := "warn"
		if code in ["duplicate_id", "undefined_var"]:
			sev = "error"
		var fix := ""
		match code:
			"no_goal": fix = "winlose"
			"multi_player": fix = ""
		items.append({"sev": sev, "text": str(d.get("message", "")),
			"brick": str(d.get("brick_id", "")), "fix": fix})
	return items

func _refresh_problems() -> void:
	if problems_box == null or not is_instance_valid(problems_box):
		return
	var items := _collect_problems()
	var sig := ""
	for it in items:
		sig += str(it.get("sev", "")) + "|" + str(it.get("text", "")) + "|" + str(it.get("brick", "")) + "\n"
	if sig == _last_problems:
		return
	_last_problems = sig
	for c in problems_box.get_children():
		problems_box.remove_child(c)
		c.queue_free()
	if _problems_panel == null or not is_instance_valid(_problems_panel):
		return
	_problems_panel.visible = not items.is_empty()
	if items.is_empty():
		return
	if _problems_title != null and is_instance_valid(_problems_title):
		_problems_title.text = "%s (%d)" % [I18n.t("problems_title"), items.size()]
	for it in items:
		problems_box.add_child(_problem_row(it))

## One problem, as a button: pressing it selects the brick it talks about,
## centres the canvas on it and opens its panel. That turns "some rule uses a
## variable that does not exist" into a two-second fix instead of a search.
func _problem_row(item: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var is_err := str(item.get("sev", "warn")) == "error"
	var mark := Label.new()
	mark.text = "●" if is_err else "▲"
	mark.modulate = C_BAD if is_err else C_WARN
	mark.tooltip_text = I18n.t("problem_error_tip") if is_err else I18n.t("problem_warn_tip")
	row.add_child(mark)
	var btn := Button.new()
	btn.text = str(item.get("text", ""))
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 12)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.clip_text = true
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	btn.tooltip_text = str(item.get("text", "")) + "  —  " + I18n.t("problem_jump_tip")
	var brick_id := str(item.get("brick", ""))
	btn.pressed.connect(func():
		if not brick_id.is_empty():
			_focus_brick(brick_id)
	)
	row.add_child(btn)
	var fix := str(item.get("fix", ""))
	if not fix.is_empty():
		var add := Button.new()
		add.text = "＋ " + BrickDocs.name_for(fix)
		add.tooltip_text = "%s — %s" % [BrickDocs.name_for(fix), BrickDocs.help_for(fix)]
		add.add_theme_font_size_override("font_size", 11)
		add.pressed.connect(func(): _add_brick(fix))
		row.add_child(add)
	return row

## Show me the box this problem is about.
func _focus_brick(brick_id: String) -> void:
	if brick_id.is_empty() or graph_edit == null or not is_instance_valid(graph_edit):
		return
	if not graph_edit.has_node(NodePath(brick_id)):
		return
	var node := graph_edit.get_node(NodePath(brick_id)) as GraphNode
	if node == null:
		return
	# GraphEdit.selected_node is read-only in Godot 4 — the app tracks selection
	# itself so Delete / Copy / Paste act on the brick this jumped to.
	_selected_brick_id = brick_id
	var area := graph_edit.size
	if area.x < 40.0:
		area = Vector2(900, 620)
	graph_edit.scroll_offset = area * 0.5 - node.position_offset * graph_edit.zoom
	graph_edit.move_child(node, graph_edit.get_child_count() - 1)
	_open_inspector(brick_id)

# ---------------------------------------------------------------------------
# Game identity: the name and the dimension, both editable, both saved
# ---------------------------------------------------------------------------
func _set_project_name(t: String) -> void:
	if graph == null:
		return
	var clean := t.strip_edges()
	if clean.is_empty():
		return
	if clean == graph.project_name:
		return
	graph.project_name = clean
	if not _player_mode:
		DisplayServer.window_set_title("EasyForge — " + clean)
	_mark_dirty()

func _set_dimension(d: String) -> void:
	if graph == null or str(graph.dimension) == d:
		return
	if undo_svc != null:
		undo_svc.record("switch to " + d)
	graph.dimension = d
	# keep the picker in step, so a dimension change made by a template, an AI
	# draft or an undo is never shown wrong in the rail
	if dim_opt != null and is_instance_valid(dim_opt):
		var want := 1 if d == "2d" else 0
		if dim_opt.selected != want:
			dim_opt.selected = want
	_mark_dirty()
	_refresh_undo_buttons()
	call_deferred("_refresh_preview")
	_set_status(I18n.t("dimension_now") + " " + (I18n.t("dimension_2d") if d == "2d" else I18n.t("dimension_3d")), false)

## A recipe from the Manual: add a pre-wired set of bricks to what is open now.
func _apply_recipe(key: String) -> void:
	if graph == null:
		return
	if undo_svc != null:
		undo_svc.record("recipe " + key)
	var anchor := ""
	for b in graph.bricks:
		if str(b.get("kind", "")) != "spawn":
			continue
		var p: Dictionary = b.get("params", {})
		if str(p.get("model", "player")) == "player":
			anchor = str(b.get("id", ""))
			break
	var res = Recipes.add_to(graph, key, anchor)
	var added: Array = res.get("added", [])
	# lay the new bricks out in a readable column so a recipe does not land as
	# four overlapping boxes in the same corner
	var slot := 0
	for id in added:
		if graph_edit.has_node(NodePath(str(id))):
			var node := graph_edit.get_node(NodePath(str(id))) as GraphNode
			if node != null:
				node.position_offset = Vector2(60 + (slot % 2) * 340, 60 + int(slot / 2) * 200)
				slot += 1
	_render_graph()
	call_deferred("_redraw_connections")
	call_deferred("_refresh_preview")
	_mark_dirty()
	_refresh_undo_buttons()
	_set_status(str(res.get("message", "")) + "  " + I18n.t("recipe_undo_hint"), not bool(res.get("ok", false)))

# ---------------------------------------------------------------------------
# Prompt + AI
# ---------------------------------------------------------------------------
func _on_generate_pressed() -> void:
	var desc := prompt_edit.text.strip_edges()
	if desc.is_empty():
		_set_status(I18n.t("describe_prompt"), true)
		return
	_last_prompt = desc
	# No key configured? Do not dead-end with a settings popup. The genre library
	# knows which bricks make a racer, a shooter, a story — so build the game from
	# it and say plainly that it came from the built-in library, not from an AI.
	if not _ai_usable():
		_build_from_library(desc, false, true)
		return
	_set_status(I18n.t("ai_thinking"), false)
	ai.generate_draft(desc)

## Can the AI actually be called right now?
func _ai_usable() -> bool:
	var prov: Dictionary = LlmClient.PROVIDERS.get(SettingsStore.provider, {})
	if bool(prov.get("needs_key", false)) and SettingsStore.api_key.strip_edges().is_empty():
		return false
	return ai != null

## Generate the brick set without a language model: read the genre out of the
## sentence, lay out the bricks that genre needs, already wired.
func _build_from_library(desc: String, after_ai_failure: bool, no_key: bool) -> void:
	if ai == null:
		return
	var draft = ai.offline_draft(desc)
	var graph_dict: Dictionary = draft.get("graph", {})
	if graph_dict.is_empty():
		return
	var genre := str(draft.get("genre", ""))
	var named := bool(draft.get("named", false))
	load_graph_dict(graph_dict)
	var label := GenreLibrary.label(genre)
	var msg := ""
	if after_ai_failure:
		msg = "🧱 " + I18n.t("offline_after_ai") + " " + label + "."
	elif no_key:
		msg = "🧱 " + I18n.t("offline_no_key") + " " + label + "."
	if not named:
		msg += " " + I18n.t("offline_guessed") + " " + label + "."
	elif not after_ai_failure and not no_key:
		msg = "🧱 " + label + "."
	_set_status(msg.strip_edges(), false)

func _on_finalize_pressed() -> void:
	_set_status(I18n.t("ai_thinking"), false)
	ai.finalize(graph.to_dict())

func _on_draft_ready(d: Dictionary) -> void:
	load_graph_dict(d)
	_set_status("✨ " + I18n.t("ai_draft_done"), false)

## An AI failure with no key configured is a setup step, not an error to read:
## open the dialog that fixes it instead of leaving a message in a small label.
func _on_ai_failed(msg: String) -> void:
	_set_status(msg, true)
	var prov: Dictionary = LlmClient.PROVIDERS.get(SettingsStore.provider, {})
	if bool(prov.get("needs_key", false)) and SettingsStore.api_key.strip_edges().is_empty():
		_set_status(I18n.t("no_key_title") + " — " + I18n.t("no_key_body"), true)
		if _settings_dlg != null and is_instance_valid(_settings_dlg):
			_settings_dlg.popup_centered()

## A draft that did not come back is not the end of the session: build the genre
## graph locally so the person has bricks to edit, and be honest about the swap.
func _on_draft_failed(msg: String) -> void:
	if _last_prompt.strip_edges().is_empty():
		_set_status(msg, true)
		return
	_build_from_library(_last_prompt, true, false)
	if _settings_dlg != null and is_instance_valid(_settings_dlg) \
			and bool(LlmClient.PROVIDERS.get(SettingsStore.provider, {}).get("needs_key", false)) \
			and SettingsStore.api_key.strip_edges().is_empty():
		_settings_dlg.popup_centered()

# ---------------------------------------------------------------------------
# Wave 3 — iterative AI edit: snapshot the graph, ask the AI for a diff, apply
# it, and keep the snapshot so Undo reverts exactly this edit.
# ---------------------------------------------------------------------------
func _on_edit_pressed() -> void:
	var instruction := chat_edit.text.strip_edges()
	if instruction.is_empty():
		_set_status(I18n.t("ai_edit_needed"), true)
		return
	# snapshot BEFORE the edit so Undo can restore it (the command stack also
	# records it, so this stays as a belt-and-braces fallback)
	_undo_snapshot = graph.to_dict().duplicate(true)
	if undo_svc != null:
		undo_svc.record("AI edit")
	_refresh_undo_buttons()
	_set_status(I18n.t("ai_thinking"), false)
	ai.generate_edit(graph.to_dict(), instruction)

func _on_edit_ready(diff: Dictionary) -> void:
	# apply the structured diff to the live graph (never throws)
	var result = ai.apply_edit(graph, diff)
	var applied := int(result.get("applied", 0)) if result is Dictionary else 0
	var summary := str(result.get("summary", "")) if result is Dictionary else ""
	_render_graph()
	_refresh_suggestions()
	call_deferred("_refresh_preview")
	if applied > 0:
		_set_status("✨ " + (summary if not summary.is_empty() else I18n.t("ai_edit_done")), false)
	else:
		_set_status(I18n.t("ai_edit_nothing"), true)
	chat_edit.text = ""

func _on_undo_pressed() -> void:
	# Wave 6: use the real command stack so EVERY manual edit is undoable.
	if undo_svc != null and undo_svc.undo():
		_render_graph()
		_refresh_suggestions()
		call_deferred("_refresh_preview")
		_mark_dirty()
		_refresh_undo_buttons()
		_set_status(I18n.t("undo_done"), false)
		return
	# fall back to the AI-edit snapshot if the stack is empty
	if _undo_snapshot.is_empty():
		return
	load_graph_dict(_undo_snapshot)
	_undo_snapshot = {}
	if undo_btn != null:
		undo_btn.disabled = true
	_set_status(I18n.t("undo_done"), false)

## Wave 6: redo the last undone edit (Ctrl+Shift+Z / the redo button).
func _on_redo_pressed() -> void:
	if undo_svc != null and undo_svc.redo():
		_render_graph()
		_refresh_suggestions()
		call_deferred("_refresh_preview")
		_mark_dirty()
		_refresh_undo_buttons()
		_set_status(I18n.t("redo_done"), false)

## Wave 3 — refresh the "try next" one-click suggestions from the live graph.
func _refresh_suggestions() -> void:
	if suggest_box == null:
		return
	for child in suggest_box.get_children():
		child.queue_free()
	var sugg = ai.suggest_next(graph.to_dict()) if ai != null else []
	# Two, not five. This column has a height budget and the default window is
	# 800px tall: a third and fourth suggestion pushed the brick list itself off
	# the bottom, which is the opposite of the point.
	var shown := 0
	for s in sugg:
		if shown >= 2:
			break
		if not (s is Dictionary):
			continue
		var kind := str(s.get("kind", ""))
		var label := str(s.get("label", kind))
		var why := str(s.get("why", ""))
		var btn := Button.new()
		btn.text = label
		btn.tooltip_text = why
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 12)
		btn.pressed.connect(func(): _add_brick(kind))
		suggest_box.add_child(btn)
		shown += 1

## Remove whatever is currently mounted in the inline preview viewport.
## Detach and free NOW: queue_free() is deferred, and for one frame two compiled
## scenes would share the tree — each one's camera grabbing the OTHER scene's
## player by group (get_first_node_in_group is tree-global). That is the ghost
## view, and it also crashed the follow script when the game was 2D and the
## leftover was 3D.
func _clear_preview() -> void:
	if viewport == null or not is_instance_valid(viewport):
		return
	for child in viewport.get_children():
		viewport.remove_child(child)
		child.free()

## Live preview — recompile the current graph into the small right-hand
## viewport so the right panel always shows the game, never a blank box.
## The preview is FROZEN (processing disabled): it shows what the game looks
## like right now without enemies drifting into you or coins auto-collecting.
## We manually frame the camera on the player before freezing, then press Play
## for the full interactive window.
func _refresh_preview() -> void:
	if viewport == null or not is_instance_valid(viewport):
		return
	# don't fight the fullscreen Play if it's running
	if game_view != null and game_view.visible:
		return
	_clear_preview()
	if graph == null or graph.bricks.is_empty():
		return
	var scene = compiler.compile_graph(graph)
	if scene == null:
		return
	# let _ready run once so nodes are positioned, then freeze next frame
	scene.process_mode = Node.PROCESS_MODE_INHERIT
	viewport.add_child(scene)
	# frame the camera on the player, then freeze so nothing moves on its own
	_frame_preview_camera(scene)
	scene.process_mode = Node.PROCESS_MODE_DISABLED

## Click the right-panel preview -> launch the full interactive game (WASD
## and mouse work there). The inline preview is a frozen snapshot on purpose.
func _on_preview_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not (game_view != null and game_view.visible):
			play_btn.button_pressed = true   # toggles Play on

## Point the preview camera at the player and set a sensible distance, so the
## frozen shot is framed (the follow script won't run while the tree is frozen).
func _frame_preview_camera(scene: Node) -> void:
	var player := _scene_player(scene)
	var cam: Camera3D = null
	var cam2d: Camera2D = null
	for child in scene.get_children():
		if child is Camera3D and cam == null:
			cam = child
		elif child is Camera2D and cam2d == null:
			cam2d = child
	if cam != null and player is Node3D:
		var p := player as Node3D
		cam.look_at_from_position(p.global_position + Vector3(0, 6, 10), p.global_position + Vector3(0, 1, 0), Vector3.UP)
	elif cam2d != null and player is Node2D:
		(cam2d as Camera2D).global_position = (player as Node2D).global_position
		# the compiled scene is in the tree by now, so the view can actually be
		# pointed at the player — the compiler no longer force-makes the camera
		# current on a detached node
		(cam2d as Camera2D).make_current()

## The player inside THIS compiled scene. get_first_node_in_group() searches the
## whole tree, so a preview and a shipped game mounted in one process would each
## frame the other's character — the ghost view, and a camera pointing at nothing.
func _scene_player(node: Node) -> Node:
	if node == null:
		return null
	if node.is_in_group("player"):
		return node
	for c in node.get_children():
		var found := _scene_player(c)
		if found != null:
			return found
	return null

# ---------------------------------------------------------------------------
# Play / Stop (in-app)
# ---------------------------------------------------------------------------
func _on_play_toggled(pressed: bool) -> void:
	if pressed:
		_start_game()
	else:
		_stop_game()

## Play: hide the brick editor, show the game full-window, mount the game.
##
## Only a real structural break stops Play now, and when it does the whole list
## of problems is already on screen underneath the canvas — not one message per
## attempt, which was the old experience: four problems, four presses.
func _start_game() -> void:
	var items := _collect_problems()
	var fatal: Array = []
	var warns: Array = []
	for it in items:
		if str(it.get("sev", "")) == "error":
			fatal.append(it)
		else:
			warns.append(it)
	_refresh_problems()
	if graph == null or graph.bricks.is_empty():
		_set_status(I18n.t("canvas_empty_play"), true)
		play_btn.button_pressed = false
		return
	if not fatal.is_empty():
		_set_status("%s (%d) — %s" % [I18n.t("problems_title"), items.size(), str(fatal[0].get("text", ""))], true)
		play_btn.button_pressed = false
		_focus_brick(str(fatal[0].get("brick", "")))
		return
	if not warns.is_empty():
		# a hint, not a block: play it anyway and see for yourself
		_set_status("⚠ %s (%d)" % [I18n.t("problems_title"), warns.size()], true)
	graph.save_to("user://last_project.json")
	# tear down the frozen inline preview so its camera doesn't double-render
	# alongside the fullscreen game (two "current" cameras = the ghost view).
	_clear_preview()
	if GameRunner.play(graph, game_viewport):
		# swap views: editor hidden, game shown full-window
		editor_root.visible = false
		game_view.visible = true
		play_btn.text = "■ " + I18n.t("stop")
	else:
		_set_status(I18n.t("play_build_failed"), true)
		play_btn.button_pressed = false

## Stop: unmount the game, show the brick editor again. In a shipped game the
## same key is the only exit, so it quits the app instead.
func _stop_game() -> void:
	if _player_mode:
		GameRunner.stop()
		get_tree().quit()
		return
	GameRunner.stop()
	game_view.visible = false
	editor_root.visible = true
	play_btn.button_pressed = false
	play_btn.text = "▶ " + I18n.t("play")
	call_deferred("_refresh_preview")

func _on_stop_pressed() -> void:
	_stop_game()

# ---------------------------------------------------------------------------
# Keyboard: shortcuts first, then graph panning (WASD + arrows scroll the
# canvas). Ignored while a text field has focus so typing still works.
# ---------------------------------------------------------------------------
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	if not event.pressed or event.echo:
		return
	# Esc stops the game and returns to the editor
	if event.keycode == KEY_ESCAPE and game_view != null and game_view.visible:
		_stop_game()
		get_viewport().set_input_as_handled()
		return
	# Esc closes the brick inspector when the editor is showing
	if event.keycode == KEY_ESCAPE and _inspector != null and is_instance_valid(_inspector):
		_close_inspector()
		get_viewport().set_input_as_handled()
		return
	if editor_root != null and not editor_root.visible:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	# --- shortcuts (every one of these already existed as a right-click menu
	# action or a button; only the mouse could reach them before) -------------
	if event.ctrl_pressed or event.meta_pressed:
		var handled := true
		match event.keycode:
			KEY_Z:
				if event.shift_pressed:
					_on_redo_pressed()
				else:
					_on_undo_pressed()
			KEY_Y:
				_on_redo_pressed()
			KEY_C:
				_shortcut_brick_action(0)
			KEY_V:
				_shortcut_brick_action(1)
			KEY_D:
				_shortcut_brick_action(2)
			KEY_S:
				_autosave()
				_set_status(I18n.t("saved_ok"), false)
			# Ctrl+F goes to the brick search instead of the browser finding nothing
			KEY_F:
				if brick_search != null:
					brick_search.grab_focus()
					brick_search.select_all()
			KEY_B:
				# Ctrl+B: a new brick, straight into the search box
				if brick_search != null:
					brick_search.grab_focus()
			_:
				handled = false
		if handled:
			get_viewport().set_input_as_handled()
			return
	# F1 is the documentation. Help hidden behind a question mark in a list of
	# icons is how a beginner ends up reading source comments to learn a UI.
	if event.keycode == KEY_F1:
		_show_help()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
		_shortcut_brick_action(3)
		get_viewport().set_input_as_handled()
		return
	# canvas zoom: + / - reset with 0 (Godot's Ctrl+scroll still works too)
	if event.keycode in [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD]:
		_zoom_canvas(1.1)
	elif event.keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
		_zoom_canvas(0.9)
	elif event.keycode in [KEY_0, KEY_KP_0]:
		graph_edit.zoom = 1.0
		get_viewport().set_input_as_handled()
		return
	# --- graph panning ------------------------------------------------------
	var step := 60.0
	if event.shift_pressed:
		step = 200.0
	var delta := Vector2.ZERO
	match event.keycode:
		KEY_LEFT, KEY_A:
			delta.x = -step
		KEY_RIGHT, KEY_D:
			delta.x = step
		KEY_UP, KEY_W:
			delta.y = -step
		KEY_DOWN, KEY_S:
			delta.y = step
		_:
			return
	graph_edit.scroll_offset += delta
	get_viewport().set_input_as_handled()

## Run one of the right-click menu actions from the keyboard, on the selected brick.
func _shortcut_brick_action(id: int) -> void:
	if _selected_brick_id.is_empty():
		_set_status(I18n.t("pick_brick_first"), true)
		return
	_on_brick_menu(id, _selected_brick_id)

func _zoom_canvas(factor: float) -> void:
	graph_edit.zoom = clampf(graph_edit.zoom * factor, 0.5, 2.0)
	get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------
# Graph <-> UI sync
# ---------------------------------------------------------------------------
func load_graph_dict(d: Dictionary) -> void:
	GameRunner.stop()
	# a fresh project invalidates the undo history
	if undo_svc != null:
		undo_svc.clear()
	graph.from_dict(d)
	# the taskbar should say which game you are in, not just "EasyForge"
	if not _player_mode:
		DisplayServer.window_set_title("EasyForge — " + graph.project_name)
	_sync_identity_controls()
	_render_graph()
	call_deferred("_frame_graph_view")
	_refresh_suggestions()
	_refresh_undo_buttons()
	call_deferred("_refresh_preview")

## Push graph.project_name / graph.dimension into the rail's controls. Called on
## every load so a restored project, a template or an AI draft shows the truth
## instead of the values the widgets were created with.
func _sync_identity_controls() -> void:
	if game_name_edit != null and is_instance_valid(game_name_edit):
		if game_name_edit.text != graph.project_name:
			game_name_edit.text = graph.project_name
	if dim_opt != null and is_instance_valid(dim_opt):
		var want := 1 if str(graph.dimension) == "2d" else 0
		if dim_opt.selected != want:
			dim_opt.selected = want

func _render_graph() -> void:
	# Preserve each existing node's on-canvas position so adding/removing a
	# brick doesn't scramble the user's layout (this was the "everything
	# disconnects / jumps around" bug).
	var positions := {}
	for child in graph_edit.get_children():
		if child is GraphNode:
			positions[child.name] = child.position_offset
			child.queue_free()
	for i in graph.bricks.size():
		var b = graph.bricks[i]
		var node = _make_graph_node(b, i)
		# restore the saved position if this brick already existed
		if positions.has(node.name):
			node.position_offset = positions[node.name]
		graph_edit.add_child(node)
	# re-draw connections after the nodes are in the tree; defer one frame so
	# Godot has finished laying out (connect_node is unreliable same-frame)
	call_deferred("_redraw_connections")
	_refresh_problems()
	_update_canvas_hint()

func _redraw_connections() -> void:
	for b in graph.bricks:
		for c in b.get("connections", []):
			var from_id := str(b["id"])
			var to_id := str(c["to_brick"])
			if graph_edit.has_node(NodePath(from_id)) and graph_edit.has_node(NodePath(to_id)):
				graph_edit.connect_node(from_id, int(c["from_out"]), to_id, int(c["to_in"]))

func _make_graph_node(b: Dictionary, index: int) -> GraphNode:
	var gn := GraphNode.new()
	gn.name = str(b["id"])
	gn.title = "%s %s" % [BrickRegistry.kind_icon(b["kind"]), b["title"]]
	gn.position_offset = Vector2(60 + (index % 3) * 340, 40 + int(index / 3) * 200)
	var inputs: Array = b.get("inputs", [])
	var outputs: Array = b.get("outputs", [])
	var in_enabled: bool = inputs.size() > 0
	var in_type: int = inputs[0]["type"] if inputs.size() > 0 else BrickRef.PortType.FLOW
	var out_enabled: bool = outputs.size() > 0
	var out_type: int = outputs[0]["type"] if outputs.size() > 0 else BrickRef.PortType.FLOW
	# Godot 4 signature: set_slot(idx, enable_left, type_left, color_left,
	#                              enable_right, type_right, color_right,
	#                              custom_left_tex=null, custom_right_tex=null)
	gn.set_slot(0, in_enabled, in_type, C_PORT_IN, out_enabled, out_type, C_PORT_OUT)
	# right-click context menu
	var brick_id := str(b["id"])
	gn.gui_input.connect(func(ev): _on_node_gui_input(ev, brick_id))
	# compact port-name hint (one small line). Raw IR ids like `on_tick` or
	# `entity` mean nothing to a beginner, so they are humanised here.
	if inputs.size() > 0 or outputs.size() > 0:
		var port_lbl := Label.new()
		port_lbl.add_theme_font_size_override("font_size", 10)
		port_lbl.modulate = C_MUTED
		var left_name: String = _human_port(str(inputs[0]["name"])) if inputs.size() > 0 else ""
		var right_name: String = _human_port(str(outputs[0]["name"])) if outputs.size() > 0 else ""
		port_lbl.text = "◀ %s   %s ▶" % [left_name, right_name]
		gn.add_child(port_lbl)
	# comment editor (user -> AI) — one compact line
	var comment := LineEdit.new()
	comment.custom_minimum_size = Vector2(210, 0)
	comment.placeholder_text = I18n.t("brick_comment")
	comment.text = str(b.get("comment", ""))
	comment.expand_to_text_length = true
	comment.add_theme_font_size_override("font_size", 12)
	comment.text_changed.connect(func(): b["comment"] = comment.text)
	gn.add_child(comment)
	# settings: collapsed by default so bricks stay short. A small toggle
	# reveals the editable param controls only when the user wants them.
	_add_collapsible_settings(gn, b)
	return gn

## Every control that edits a brick param routes through here, so a tweak is
## autosaved without the user having to press anything.
func _set_param(params: Dictionary, key: String, value) -> void:
	params[key] = value
	_mark_dirty()

## Fit the canvas view to the bricks that exist. A restored or AI-drafted project
## used to open with its nodes off-screen, so the canvas looked empty — the worst
## possible first impression for a product that promises "never an empty canvas".
func _frame_graph_view() -> void:
	if graph_edit == null or not is_instance_valid(graph_edit):
		return
	if graph == null or graph.bricks.is_empty():
		return
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for child in graph_edit.get_children():
		if child is GraphNode:
			var gp: GraphNode = child
			min_p = Vector2(minf(min_p.x, gp.position_offset.x), minf(min_p.y, gp.position_offset.y))
			var bottom_right := gp.position_offset + Vector2(260, 150)
			max_p = Vector2(maxf(max_p.x, bottom_right.x), maxf(max_p.y, bottom_right.y))
	if not is_finite(min_p.x) or not is_finite(max_p.y):
		return
	var span: Vector2 = (max_p - min_p).max(Vector2(1.0, 1.0))
	var area := graph_edit.size
	if area.x < 80.0 or area.y < 80.0:
		area = Vector2(900, 620)
	var z: float = clampf(minf(area.x / (span.x + 80.0), area.y / (span.y + 80.0)), 0.5, 1.0)
	graph_edit.zoom = z
	var center := (min_p + max_p) * 0.5
	graph_edit.scroll_offset = area * 0.5 - center * z

## Turn an IR port id into something readable: "on_start" -> "On start".
func _human_port(port_name: String) -> String:
	if port_name.is_empty():
		return ""
	return port_name.replace("_", " ").capitalize()

## Settings live behind a compact toggle so bricks are short by default and only
## grow when the user opens them. The rows themselves are built by ParamRows —
## the same builder the inspector uses, so a setting cannot read differently in
## the two places (they used to be two copies of the same forty lines).
func _add_collapsible_settings(gn: GraphNode, b: Dictionary) -> void:
	var kind := str(b.get("kind", ""))
	var schema: Dictionary = BrickRef.PARAM_SCHEMA.get(kind, {})
	if schema.is_empty():
		return
	var params: Dictionary = b.get("params", {})
	var toggle := Button.new()
	toggle.name = "SettingsToggle"
	toggle.text = "⚙ " + I18n.t("brick_settings")
	toggle.toggle_mode = true
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.add_theme_font_size_override("font_size", 11)
	toggle.tooltip_text = I18n.t("node_settings_tip")
	gn.add_child(toggle)
	var body := VBoxContainer.new()
	body.name = "NodeSettingsBody"
	body.visible = false
	body.add_theme_constant_override("separation", 2)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gn.add_child(body)
	toggle.toggled.connect(func(on):
		body.visible = on
		toggle.text = ("▼ " if on else "▶ ") + I18n.t("brick_settings")
	)
	# dense + no printed help: on the canvas a tooltip is enough, because the
	# inspector is one click away and prints everything
	ParamRows.build(body, kind, schema, params,
		func(key, value): _set_param(params, key, value),
		{"label_w": 88.0, "dense": true, "show_help": false, "font": 11})

func _params_summary(params: Dictionary) -> String:
	# inline "• Speed 8.0  • Jump 12.0" instead of one bullet per line
	var parts: Array[String] = []
	for k in params:
		var v = params[k]
		if v is Array:
			v = "[" + ", ".join(v) + "]"
		parts.append("%s %s" % [str(k).capitalize(), str(v)])
	if parts.is_empty():
		return ""
	return "• " + "   • ".join(parts)

# ---------------------------------------------------------------------------
# Right-click context menu on a brick: Copy / Paste / Duplicate / Delete.
# ---------------------------------------------------------------------------
func _on_node_gui_input(event: InputEvent, brick_id: String) -> void:
	# Open the inspector only on a real CLICK (press then release at the same
	# spot), NOT on the press that begins a port drag — otherwise the floating
	# inspector panel pops up mid-drag and swallows the connection. Right-click
	# still opens the context menu immediately.
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_show_brick_menu(brick_id, graph_edit.get_global_mouse_position())
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_press_pos = event.position
			_press_brick_id = brick_id
	elif event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# a click = press and release within a few px (a drag moves further)
			if _press_brick_id == brick_id and _press_pos.distance_to(event.position) < 6.0:
				_open_inspector(brick_id)
			_press_brick_id = ""

func _show_brick_menu(brick_id: String, at_pos: Vector2) -> void:
	var menu := PopupMenu.new()
	menu.add_item(I18n.t("brick_copy"), 0)
	menu.add_item(I18n.t("brick_paste"), 1)
	menu.add_item(I18n.t("brick_duplicate"), 2)
	menu.add_separator()
	menu.add_item(I18n.t("brick_delete"), 3)
	add_child(menu)
	menu.id_pressed.connect(func(id): _on_brick_menu(id, brick_id))
	menu.close_requested.connect(menu.queue_free)
	menu.popup(Rect2(at_pos, Vector2(160, 0)))

# ---------------------------------------------------------------------------
# Inspector — click a brick and everything about it is on one panel: what it
# does, what each of its settings means in plain words, how it is normally
# wired, and which bricks it likes being used with.
# ---------------------------------------------------------------------------
func _open_inspector(brick_id: String) -> void:
	_close_inspector()
	var b = graph.get_brick(brick_id)
	if b.is_empty():
		return
	_inspector_brick_id = brick_id
	var kind := str(b.get("kind", ""))

	# docked into the canvas's right edge, never over the preview panel
	var panel := PanelContainer.new()
	panel.name = "Inspector"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.theme = editor_root.theme if editor_root != null else null
	if _inspector_slot != null and is_instance_valid(_inspector_slot):
		_inspector_slot.add_child(panel)
		_inspector_slot.visible = true
	else:
		# no dock (should not happen): fall back to a floating panel on the window
		add_child(panel)
		panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		panel.anchor_left = 1.0
		panel.anchor_right = 1.0
		panel.offset_left = -372
	_inspector = panel

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# the inspector is a long column of settings; an invisible scrollbar made the
	# last sections look like they did not exist
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	panel.add_child(scroll)
	var body := VBoxContainer.new()
	body.name = "InspectorBody"
	body.add_theme_constant_override("separation", 8)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	# header: brick title + close button
	var head := HBoxContainer.new()
	body.add_child(head)
	var title := Label.new()
	title.text = "%s %s" % [BrickRegistry.kind_icon(kind), str(b.get("title", ""))]
	title.add_theme_font_size_override("font_size", 18)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.tooltip_text = I18n.t("close") + "  (Esc)"
	close_btn.pressed.connect(_close_inspector)
	head.add_child(close_btn)

	# what this brick actually does, in plain English — never a mystery box
	var help := BrickDocs.says_for(kind)
	if not help.is_empty():
		var help_lbl := Label.new()
		help_lbl.text = help
		help_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		help_lbl.add_theme_font_size_override("font_size", 12)
		help_lbl.modulate = C_MUTED
		body.add_child(help_lbl)
	var use := BrickDocs.use_for(kind)
	if not use.is_empty():
		var use_lbl := Label.new()
		use_lbl.text = "🔌 " + use
		use_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		use_lbl.add_theme_font_size_override("font_size", 12)
		use_lbl.modulate = C_ACCENT_2
		body.add_child(use_lbl)

	# the brick's name: the graph of "Enemy 1 / Enemy 2" boxes was unreadable
	# until it could be renamed to "the guard by the door"
	var rename := LineEdit.new()
	rename.text = str(b.get("title", ""))
	rename.placeholder_text = I18n.t("rename_brick")
	rename.tooltip_text = I18n.t("rename_brick_tip")
	rename.text_submitted.connect(func(t):
		b["title"] = t
		title.text = "%s %s" % [BrickRegistry.kind_icon(kind), t]
		_render_graph()
		_mark_dirty()
	)
	body.add_child(rename)

	var comment := LineEdit.new()
	comment.placeholder_text = I18n.t("brick_comment")
	comment.text = str(b.get("comment", ""))
	comment.tooltip_text = I18n.t("brick_comment_tip")
	comment.text_changed.connect(func(t): b["comment"] = t)
	body.add_child(comment)

	# every setting, grouped, each with its explanation printed rather than hidden
	# behind a tooltip nobody knows to hover
	var schema: Dictionary = BrickRef.PARAM_SCHEMA.get(kind, {})
	var params: Dictionary = b.get("params", {})
	var sections := _sections_for(kind, schema)
	for section_name in sections:
		var keys: Array = sections[section_name]
		if keys.is_empty():
			continue
		var sec_lbl := Label.new()
		sec_lbl.text = "▸ " + str(section_name)
		sec_lbl.add_theme_font_size_override("font_size", 13)
		sec_lbl.modulate = C_ACCENT_2
		body.add_child(sec_lbl)
		var sub := {}
		for key in keys:
			sub[key] = schema[key]
		ParamRows.build(body, kind, sub, params,
			func(key, value): _set_param(params, key, value),
			{"label_w": 110.0, "dense": true, "show_help": true, "font": 12})

	# neighbours: the brick you are looking at rarely works alone
	var related: Array = BrickDocs.related_for(kind)
	if not related.is_empty():
		var rel_lbl := Label.new()
		rel_lbl.text = "🤝 " + I18n.t("related_bricks")
		rel_lbl.add_theme_font_size_override("font_size", 12)
		rel_lbl.modulate = C_MUTED
		body.add_child(rel_lbl)
		var chips := HFlowContainer.new()
		chips.add_theme_constant_override("h_separation", 6)
		chips.add_theme_constant_override("v_separation", 6)
		body.add_child(chips)
		for r in related:
			var chip := Button.new()
			var rk := str(r)
			chip.text = "%s %s" % [BrickRegistry.kind_icon(rk), BrickDocs.name_for(rk)]
			chip.tooltip_text = BrickDocs.help_for(rk)
			chip.add_theme_font_size_override("font_size", 11)
			chip.pressed.connect(func(): _add_brick(rk))
			chips.add_child(chip)

	# the way out of a dead end: read the real documentation for this brick
	var manual_btn := Button.new()
	manual_btn.text = "📖  " + I18n.t("open_manual_page")
	manual_btn.tooltip_text = I18n.t("manual_tip")
	manual_btn.pressed.connect(func():
		_show_help()
		if _manual != null and is_instance_valid(_manual):
			_manual.show_brick_page(kind)
	)
	body.add_child(manual_btn)

	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 6)
	body.add_child(acts)
	var dup := Button.new()
	dup.text = "🧬  " + I18n.t("brick_duplicate")
	dup.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dup.pressed.connect(func():
		_close_inspector()
		_on_brick_menu(2, brick_id)
	)
	acts.add_child(dup)
	var del := Button.new()
	del.text = "🗑  " + I18n.t("brick_delete")
	del.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.paint_danger(del)
	del.pressed.connect(func():
		_close_inspector()
		_on_brick_menu(3, brick_id)
	)
	acts.add_child(del)

func _close_inspector() -> void:
	if _inspector != null and is_instance_valid(_inspector):
		_inspector.queue_free()
	_inspector = null
	_inspector_brick_id = ""
	if _inspector_slot != null and is_instance_valid(_inspector_slot):
		_inspector_slot.visible = false

## The option list, the option label and the section grouping all live in
## ParamRows now, so the canvas node and the inspector cannot drift apart. These
## wrappers stay because the graph renderer and the tests ask main for them.
func _options_for(kind: String, key: String, spec: Dictionary) -> Array:
	return ParamRows.options_for(kind, key, spec)

func _option_label(value) -> String:
	return ParamRows.option_label(value)

func _sections_for(kind: String, schema: Dictionary) -> Dictionary:
	return ParamRows.sections_for(kind, schema)

func _on_brick_menu(id: int, brick_id: String) -> void:
	match id:
		0:  # Copy
			var b = graph.get_brick(brick_id)
			if not b.is_empty():
				_clipboard = b.duplicate(true)
				_set_status(I18n.t("brick_copied"), false)
		1:  # Paste
			_paste_brick()
		2:  # Duplicate
			var b = graph.get_brick(brick_id)
			if not b.is_empty():
				_clipboard = b.duplicate(true)
				_paste_brick()
		3:  # Delete
			if undo_svc != null:
				undo_svc.record("delete brick")
			graph.remove_brick(brick_id)
			_render_graph()
			_mark_dirty()
			_refresh_undo_buttons()
			if _inspector_brick_id == brick_id:
				_close_inspector()
			_set_status(I18n.t("brick_deleted"), false)

func _paste_brick() -> void:
	if _clipboard.is_empty():
		return
	if undo_svc != null:
		undo_svc.record("paste brick")
	var nb = _clipboard.duplicate(true)
	# fresh id so it doesn't collide with the source
	nb["id"] = "%s_%d_%d" % [str(nb.get("kind", "brick")), Time.get_ticks_msec(), randi() % 100000]
	nb["title"] = str(nb.get("title", "Brick")) + " (copy)"
	nb["comment"] = str(nb.get("comment", ""))
	# clear connections on the copy so it starts clean
	nb["connections"] = []
	if graph.add_brick(nb):
		_render_graph()
		_mark_dirty()
		_refresh_undo_buttons()
		_set_status(I18n.t("brick_pasted"), false)

func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	# record() snapshots the graph BEFORE the mutation, so it must run first
	if undo_svc != null:
		undo_svc.record("add wire")
	if graph.wire(str(from_node), from_port, str(to_node), to_port):
		graph_edit.connect_node(from_node, from_port, to_node, to_port)
		_mark_dirty()
		_refresh_undo_buttons()
		_set_status(I18n.t("wire_connected"), false)
	else:
		_set_status(I18n.t("wire_rejected"), true)

func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	var b = graph.get_brick(str(from_node))
	var conns: Array = b.get("connections", [])
	for i in conns.size():
		var c = conns[i]
		if c["to_brick"] == to_node and c["to_in"] == to_port:
			if undo_svc != null:
				undo_svc.record("remove wire")
			conns.remove_at(i)
			break
	graph_edit.disconnect_node(from_node, from_port, to_node, to_port)
	_mark_dirty()
	_refresh_undo_buttons()
	_set_status(I18n.t("wire_removed"), false)

# ---------------------------------------------------------------------------
# Palette — the brick shop
# ---------------------------------------------------------------------------
## Does this kind match what the person typed? The words a beginner uses
## ("bad guy", "die", "menu") live in BrickDocs, so the palette, the search box
## and the Manual answer the same question the same way.
func _brick_matches(kind: String, meta: Dictionary, needle: String) -> bool:
	return BrickDocs.matches(kind, meta, needle)

func _on_brick_search_changed(_t: String) -> void:
	_build_palette()

func _on_brick_search_submitted(t: String) -> void:
	# Enter adds the best match, so the search box is also the fastest way to put
	# a brick down once you know roughly what you want.
	var needle := str(t).strip_edges()
	if needle.is_empty():
		return
	var best := _best_match(needle)
	if best.is_empty():
		_set_status(I18n.t("search_no_bricks"), true)
		return
	_add_brick(best)
	brick_search.text = ""
	_build_palette()

## The single best hit for a phrase: a name match beats a label match, which
## beats a description match. The old loop took whatever came first in the
## registry, so "win" could hand you a Checkpoint.
func _best_match(needle: String) -> String:
	var kinds := BrickRegistry.all_kinds()
	var best := ""
	var best_rank := 99
	for kind in kinds:
		var meta: Dictionary = kinds[kind]
		if not BrickDocs.matches(str(kind), meta, needle):
			continue
		var rank := BrickDocs.rank(str(kind), meta, needle)
		if rank < best_rank:
			best_rank = rank
			best = str(kind)
	return best

## Build the palette.
##
## Grouped by what a person is trying to do, not by how we named things. An
## alphabetical wall of fifty bricks is the hardest possible start, so: intent
## headers, the everyday bricks first, and the specialist ones folded away until
## asked for. Search always sees all fifty — hiding bricks from search would be
## a worse dead end than a long list.
func _build_palette() -> void:
	# Remove immediately: queue_free() is DEFERRED, so the old buttons would
	# still be children when we count/re-add below (this made the palette grow
	# every time the search text changed).
	for child in palette.get_children():
		palette.remove_child(child)
		child.queue_free()
	var needle := "" if brick_search == null else str(brick_search.text).strip_edges()
	var show_every := advanced_check != null and advanced_check.button_pressed
	var kinds := BrickRegistry.all_kinds()
	var buckets := {}
	var hidden := 0
	for kind in kinds:
		var meta: Dictionary = kinds[kind]
		if not BrickDocs.matches(str(kind), meta, needle):
			continue
		if not show_every and needle.is_empty() and BrickDocs.is_advanced(str(kind)):
			hidden += 1
			continue
		var cat := BrickRegistry.kind_category(str(kind))
		if not buckets.has(cat):
			buckets[cat] = []
		(buckets[cat] as Array).append({"kind": str(kind), "rank": BrickDocs.rank(str(kind), meta, needle)})
	var order: Array = []
	for c in BrickDocs.CATEGORIES:
		order.append(str(c["id"]))
	for cat in buckets:
		if not order.has(str(cat)):
			order.append(str(cat))   # an undeclared category still shows, never vanishes
	var shown := 0
	for cat in order:
		var entries: Array = buckets.get(str(cat), [])
		if entries.is_empty():
			continue
		entries.sort_custom(func(a, b):
			if int(a["rank"]) != int(b["rank"]):
				return int(a["rank"]) < int(b["rank"])
			return BrickDocs.name_for(str(a["kind"])) < BrickDocs.name_for(str(b["kind"])))
		palette.add_child(_palette_header(str(cat)))
		for e in entries:
			palette.add_child(_palette_button(str(e["kind"])))
			shown += 1
	# the folded-away bricks stay one press away, with the number on the button
	if hidden > 0:
		var more := Button.new()
		more.name = "ShowAdvancedBtn"
		more.text = "＋ %s (%d)" % [I18n.t("show_more_bricks"), hidden]
		more.tooltip_text = I18n.t("show_every_brick_tip")
		more.alignment = HORIZONTAL_ALIGNMENT_LEFT
		more.add_theme_font_size_override("font_size", 11)
		more.modulate = C_ACCENT_2
		more.pressed.connect(func():
			if advanced_check != null:
				advanced_check.button_pressed = true
			_build_palette()
		)
		palette.add_child(more)
	if palette_empty_hint != null:
		var none := shown == 0 and not needle.is_empty()
		palette_empty_hint.visible = none
		if none:
			# found nothing: say what to type instead, do not leave a silent list
			palette_empty_hint.text = "%s  %s" % [I18n.t("search_no_bricks"), I18n.t("search_try_words")]

## A group heading, with the hint for the whole group in its tooltip.
func _palette_header(cat_id: String) -> Control:
	var row := HBoxContainer.new()
	row.name = "Cat_" + cat_id
	row.add_theme_constant_override("separation", 6)
	var lbl := Label.new()
	lbl.text = "▸ " + BrickDocs.category_label(cat_id).to_upper()
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.modulate = C_ACCENT_2
	row.add_child(lbl)
	row.tooltip_text = BrickDocs.category_hint(cat_id)
	return row

## One brick in the shop: what it is called, what it does, and both ways to use
## it — press to add, drag to place.
func _palette_button(kind: String) -> Button:
	var btn := Button.new()
	btn.name = "Brick_" + kind
	btn.text = "%s  %s" % [BrickRegistry.kind_icon(kind), BrickDocs.name_for(kind)]
	btn.pressed.connect(func(): _add_brick(kind))
	# 34px: this is the control a beginner uses constantly, and 26px was
	# below the comfortable touch/pointer target floor.
	btn.custom_minimum_size = Vector2(0, 34)
	btn.add_theme_font_size_override("font_size", 12)
	btn.clip_text = true
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var help := BrickDocs.help_for(kind)
	btn.tooltip_text = ("%s — %s" % [BrickDocs.name_for(kind), help]) if not help.is_empty() else BrickDocs.name_for(kind)
	# drag from palette onto the canvas to place a brick there
	btn.set_drag_forwarding(func(_ev): _palette_get_drag_data(btn, kind), Callable(), Callable())
	return btn

## Returns the drag payload for a palette button (called via drag forwarding).
func _palette_get_drag_data(btn: Button, kind: String):
	var preview := Label.new()
	preview.text = BrickRegistry.kind_icon(kind) + " " + BrickRegistry.kind_label(kind)
	btn.set_drag_preview(preview)
	return {"kind": kind, "from_palette": true}

func _add_brick(kind: String, at_position: Vector2 = Vector2.INF) -> void:
	var b := BrickRef.create(kind)
	if b.is_empty():
		return
	# snapshot BEFORE the mutation so this add is undoable
	if undo_svc != null:
		undo_svc.record("add brick")
	# No auto-wire: the user connects bricks themselves (drag port to port).
	graph.add_brick(b)
	# Append ONLY the new node — never rebuild existing ones, so their
	# positions, connections and control state are untouched. (Rebuilding the
	# whole graph on every add was what disconnected everything.)
	var node = _make_graph_node(b, graph.bricks.size() - 1)
	if at_position != Vector2.INF:
		node.position_offset = at_position
	else:
		# place it a little right/below the last existing node
		var last_pos := Vector2(60, 40)
		for child in graph_edit.get_children():
			if child is GraphNode:
				last_pos = child.position_offset + Vector2(40, 60)
		node.position_offset = last_pos
	graph_edit.add_child(node)
	# any connections pointing at this new brick (e.g. from a paste) drawn now
	call_deferred("_redraw_connections")
	_mark_dirty()
	_refresh_undo_buttons()
	_set_status(I18n.t("added_brick") + " " + BrickRegistry.kind_label(kind) + ". " + I18n.t("added_brick_hint"), false)

func _on_brick_dropped(kind: String, at_position: Vector2) -> void:
	_add_brick(kind, at_position)

# ---------------------------------------------------------------------------
# Visual/Code escape hatch
# ---------------------------------------------------------------------------
func _on_code_toggled(pressed: bool) -> void:
	code_panel.visible = pressed
	if pressed:
		code_panel.text = compiler.generated_script(graph)

# ---------------------------------------------------------------------------
# Export — two honest buttons: a project file, and a real game you can send.
# ---------------------------------------------------------------------------

## 💾 Save the .efg project file. This is NOT a runnable game, and the message
## used to imply it was ("Game exported! Share the file with anyone").
func _on_export_pressed() -> void:
	var dir_path := "user://exports"
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var path := "user://exports/%s.efg" % graph.project_name.replace(" ", "_")
	if graph.save_to(path):
		_set_status(I18n.t("saved_ok") + " — " + ProjectSettings.globalize_path(path), false)
	else:
		_set_status(I18n.t("save_failed"), true)

## 🚀 Make a game you can send. Writes <name>.exe + <name>.pck + game.json into
## a folder and opens it, so the friend double-clicks and plays — no install,
## no EasyForge, no code. SPEC §9 required a runnable file and did not have one.
func _on_export_game_pressed() -> void:
	var issues = graph.validate()
	if not issues.is_empty():
		_set_status(str(issues[0]), true)
		return
	var res = exporter.export_game(graph)
	_set_status(str(res.get("message", "")), not bool(res.get("ok", false)))

## Publish to Web. The shipped web build IS EasyForge in play-only mode, the
## same trick the .exe export uses: the graph is written to game.json inside
## the project, the "Web" preset packs it, and main.gd boots straight into the
## game when it finds that file in a web build. Afterwards the file is removed
## so the editor never boots as a player by accident.
func _on_export_web_pressed() -> void:
	var issues = graph.validate()
	if not issues.is_empty():
		_set_status(str(issues[0]), true)
		return
	var proj := _project_source_dir()
	if proj.is_empty():
		_set_status(I18n.t("export_web_no_source"), true)
		return
	var godot := _find_godot_binary(proj)
	if godot.is_empty():
		_set_status(I18n.t("export_web_no_source"), true)
		return
	if not _web_templates_installed():
		_set_status(I18n.t("export_web_templates_missing"), true)
		return
	_set_status(I18n.t("export_web_running"), false)
	# the game data rides inside the export
	var game_json_path := proj.path_join("game.json")
	var f := FileAccess.open(game_json_path, FileAccess.WRITE)
	if f == null:
		_set_status(I18n.t("export_game_failed_save"), true)
		return
	f.store_string(JSON.stringify(graph.to_dict(), "\t"))
	f.close()
	var out_path := proj.path_join("build/web/index.html")
	var out: Array = []
	var code := OS.execute(godot, ["--headless", "--path", proj, "--export-release", "Web", out_path], out, true)
	# the export has packed game.json (or failed); either way the editor must
	# not keep a stray player-mode file behind
	DirAccess.remove_absolute(game_json_path)
	if code == 0 and FileAccess.file_exists(out_path):
		_web_readme(proj.path_join("build/web"))
		_set_status(I18n.t("export_web_done") + " -> build/web/", false)
		OS.shell_open(ProjectSettings.globalize_path(proj.path_join("build/web")))
	else:
		_set_status(I18n.t("export_web_failed"), true)

## The project folder on disk (contains project.godot), or "" when this run
## has no visible source tree — an installed EasyForge.exe with only a .pck
## cannot re-export itself, and saying so beats a mystery failure.
func _project_source_dir() -> String:
	for cand in [
		ProjectSettings.globalize_path("res://"),
		OS.get_executable_path().get_base_dir(),
		OS.get_executable_path().get_base_dir().get_base_dir(),
	]:
		if FileAccess.file_exists(str(cand).path_join("project.godot")):
			return str(cand)
	return ""

## A Godot binary able to run the export: the console build bundled in the
## project's tools/ folder, the plain one, or this running process itself
## (RUN.bat launches EasyForge through the portable Godot).
func _find_godot_binary(proj: String) -> String:
	var candidates := [
		proj.path_join("tools/Godot_v4.7.2-stable_win64_console.exe"),
		proj.path_join("tools/Godot_v4.7.2-stable_win64.exe"),
		OS.get_executable_path(),
	]
	for c in candidates:
		if not c.is_empty() and FileAccess.file_exists(c):
			return c
	return ""

## Godot keeps web templates beside the editor settings, in a folder named
## after the exact engine version — check the real file instead of guessing.
func _web_templates_installed() -> bool:
	var v: Dictionary = Engine.get_version_info()
	var ver := "%d.%d.%d.%s" % [int(v.major), int(v.minor), int(v.patch), str(v.build)]
	var appdata := OS.get_environment("APPDATA")
	if appdata.is_empty():
		appdata = OS.get_user_data_dir()
	var tmpl_dir := appdata.path_join("Godot/export_templates/%s" % ver)
	return FileAccess.file_exists(tmpl_dir.path_join("web_release_x86_64.wasm"))

## Honest instructions beside the build: browsers refuse to run .wasm games
## from file://, so the folder needs a host or a tiny local server.
func _web_readme(web_dir: String) -> void:
	var f := FileAccess.open(web_dir.path_join("PLAY-WEB.txt"), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(I18n.t("export_web_readme").replace("{game}", graph.project_name))
	f.close()

# ---------------------------------------------------------------------------
func _on_settings_pressed() -> void:
	get_node_or_null("SettingsDialog").popup_centered()

## Wave 3 — New Project gallery: clone-first. Each entry is a finished,
## playable demo the user tweaks (the pattern every no-code engine uses to
## kill blank-canvas paralysis).
func _on_new_project_pressed() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "🆕 " + I18n.t("new_project")
	dlg.min_size = Vector2(460, 360)
	# The only button on a gallery is not a choice, it is backing out — so it says
	# Close, not OK, which read like "confirm this row".
	dlg.ok_button_text = I18n.t("close")
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	dlg.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	for entry in DemoTemplates.gallery():
		var name := str(entry.get("name", "Game"))
		var pitch := str(entry.get("pitch", ""))
		var build_key := str(entry.get("build", "platformer"))
		var btn := Button.new()
		# which one is already on the canvas — without this the person clicks the
		# same template again wondering what they were missing
		var open_now := graph != null and str(graph.project_name) == name
		btn.text = "🎮  %s%s\n%s" % [name, "   ·  " + I18n.t("open_now") if open_now else "", pitch]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.custom_minimum_size = Vector2(0, 56)
		btn.disabled = open_now
		btn.pressed.connect(func():
			dlg.hide()
			dlg.queue_free()
			_switch_project(DemoTemplates.build(build_key), name)
		)
		list.add_child(btn)
	# "I want to build it myself" is a legitimate first choice. The gallery only
	# offered finished demos, so starting from nothing meant loading a template and
	# deleting its bricks one by one.
	var blank := Button.new()
	blank.text = "🧱  %s\n%s" % [I18n.t("blank_project"), I18n.t("blank_project_pitch")]
	blank.alignment = HORIZONTAL_ALIGNMENT_LEFT
	blank.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blank.custom_minimum_size = Vector2(0, 56)
	blank.pressed.connect(func():
		dlg.hide()
		dlg.queue_free()
		_switch_project(DemoTemplates.blank(), I18n.t("blank_project"))
	)
	list.add_child(blank)
	add_child(dlg)
	dlg.popup_centered()

## Replacing the current game never destroys it: the graph they were working on
## is written to user://backups first, and 📂 Open lists it. Before this, one
## click on a template wiped unsaved work with no way back.
func _switch_project(d: Dictionary, label: String) -> void:
	var backup := _backup_current()
	load_graph_dict(d)
	if backup.is_empty():
		_set_status("🎮 " + label, false)
	else:
		_set_status("🎮 " + label + " — " + I18n.t("backed_up"), false)

## Write the live graph into user://backups/ and return that path ("" if there
## was nothing worth saving).
func _backup_current() -> String:
	if graph == null or graph.bricks.is_empty():
		return ""
	var dir := "user://backups"
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var stamp: String = Time.get_datetime_string_from_system(false, true).replace(":", "").replace(" ", "-")
	var safe: String = str(graph.project_name).replace(" ", "_").replace("/", "-")
	var path := "%s/%s-%s.efg" % [dir, safe, stamp]
	return path if graph.save_to(path) else ""

## 📂 Open — the only way back to an earlier game, since projects live as .efg
## files the app owns. Lists the last autosave, backups and exports.
func _on_open_project_pressed() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "📂 " + I18n.t("open_project")
	dlg.min_size = Vector2(520, 400)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	dlg.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	var found := 0
	for entry in _collect_project_files():
		var path := str(entry["path"])
		var label := str(entry["label"])
		var btn := Button.new()
		btn.text = label
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.tooltip_text = path
		btn.custom_minimum_size = Vector2(0, 34)
		btn.pressed.connect(func():
			var d = _read_json(path)
			if d.is_empty():
				_set_status(I18n.t("open_failed"), true)
			else:
				dlg.hide()
				dlg.queue_free()
				load_graph_dict(d)
				_set_status("📂 " + I18n.t("opened") + " — " + label, false)
		)
		list.add_child(btn)
		found += 1
	if found == 0:
		var none := Label.new()
		none.text = I18n.t("open_none")
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(none)
	add_child(dlg)
	dlg.popup_centered()

func _collect_project_files() -> Array:
	var out: Array = []
	if FileAccess.file_exists(AUTOSAVE_PATH):
		out.append({"path": AUTOSAVE_PATH, "label": "🕑 " + I18n.t("autosave")})
	for dir in ["user://backups", "user://exports"]:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		d.list_dir_begin()
		var fname := d.get_next()
		var names: Array[String] = []
		while not fname.is_empty():
			if not d.current_is_dir() and (fname.ends_with(".efg") or fname.ends_with(".json")):
				names.append(fname)
			fname = d.get_next()
		d.list_dir_end()
		names.sort()
		names.reverse()
		for n in names.slice(0, 25):
			out.append({"path": dir.path_join(n), "label": "  " + n.get_basename().replace("_", " ")})
	return out

func _set_status(msg: String, is_error: bool) -> void:
	status_label.text = msg
	status_label.modulate = C_BAD if is_error else C_GOOD
	# the left rail is hidden while the game is fullscreen, so mirror the message
	# onto the Play bar — otherwise an error during Play is invisible
	if _game_status != null and is_instance_valid(_game_status):
		_game_status.text = msg
		_game_status.modulate = C_BAD if is_error else C_GOOD

## The first-run guide. It used to be a wall of text that vanished the moment it
## was dismissed and never came back; now it says the three things that matter and
## hands you to the Manual, which is always one F1 away.
func _show_tutorial() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = I18n.t("tutorial_start")
	dlg.min_size = Vector2(520, 380)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dlg.add_child(body)
	var welcome := Label.new()
	welcome.text = I18n.t("tutorial_welcome")
	welcome.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	welcome.add_theme_font_size_override("font_size", 14)
	body.add_child(welcome)
	# ONE line on purpose: tools/gen_locales.py scans for the `for key in [...]`
	# idiom line by line, and a wrapped list hides these keys from the linter
	# (it then reports them dead and a future cleanup deletes real strings).
	for line in ["help_1", "help_2", "help_3", "help_4", "help_5"]:
		var l := Label.new()
		l.text = I18n.t(line)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", 13)
		body.add_child(l)
	var keys_line := Label.new()
	keys_line.text = I18n.t("help_shortcuts")
	keys_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	keys_line.add_theme_font_size_override("font_size", 12)
	keys_line.modulate = C_MUTED
	body.add_child(keys_line)
	var recipes := Button.new()
	recipes.text = "🍳  " + I18n.t("tutorial_try_recipes")
	UiTheme.paint_primary(recipes)
	recipes.pressed.connect(func():
		dlg.hide()
		dlg.queue_free()
		_show_help(true)
	)
	body.add_child(recipes)
	dlg.confirmed.connect(func():
		SettingsStore.tutorial_done = true
		SettingsStore.save_settings()
		dlg.queue_free()
	)
	add_child(dlg)
	dlg.popup_centered()

## The Manual — every brick, every setting, the recipes and the keys.
##
## It is built once and reused, because a documentation window that rebuilds from
## scratch each time you press F1 feels sluggish and loses where you were reading.
## `on_recipes` opens it straight at the recipe page, which is where a person who
## just pressed "I want to make a game" wants to be.
func _show_help(on_recipes: bool = false) -> void:
	if _manual == null or not is_instance_valid(_manual):
		var Manual := preload("res://src/ui/manual.gd")
		_manual = Manual.new()
		_manual.name = "Manual"
		add_child(_manual)
		_manual.setup(self)
		_manual.apply_recipe.connect(_apply_recipe)
		_manual.add_brick.connect(func(kind): _add_brick(kind))
	if not _manual.visible:
		_manual.popup_centered()
	if on_recipes:
		_manual.goto_recipes()

# ---------------------------------------------------------------------------
# Settings dialog (BYOK) — the form itself lives in src/ui/settings_dialog.gd
# ---------------------------------------------------------------------------
## Kept as a method because _build_ui names the node and the tests poke it.
func _build_settings_dialog() -> AcceptDialog:
	var SettingsDialog := preload("res://src/ui/settings_dialog.gd")
	var dlg: AcceptDialog = SettingsDialog.new()
	dlg.setup()
	dlg.saved.connect(func():
		# the dialog already wrote the key and language; this is the honest note
		# about what a language change does and does not touch
		_set_status(I18n.t("language_applies_note"), false)
	)
	return dlg
