extends AcceptDialog
## ManualWindow — the app's documentation, inside the app.
##
## Why a whole window instead of a help dialog with five lines: everything a
## beginner needs to know used to be split between tooltips they have to guess
## exist, a five-bullet dialog that vanished once dismissed, and comments in
## source files they will never open. The Manual puts the four things a new
## person actually asks in one searchable place:
##
##   Start here     — what the loop is, in six steps
##   Recipes        — "I want to add ___", one click, pre-wired
##   Every brick    — what each brick does and what each of its settings means
##   Shortcuts      — the keyboard, and how to share the result
##
## All of the words come from BrickDocs and Recipes, so the Manual cannot drift
## out of date relative to what the palette shows — which is the whole reason
## those two files exist.

signal apply_recipe(key: String)
signal add_brick(kind: String)

var _host: Node = null
var _brick_list: VBoxContainer = null
var _brick_page: VBoxContainer = null
var _search: LineEdit = null
var _tabs: TabContainer = null

func setup(host: Node) -> void:
	_host = host
	title = "📖 " + I18n.t("manual_title")
	min_size = Vector2(760, 560)
	ok_button_text = I18n.t("close")
	# the app theme, so this window looks like the rest of the product instead of
	# like a stock Godot dialog
	if host.get("editor_root") != null:
		var root: Control = host.editor_root
		if root != null and root.theme != null:
			theme = root.theme
			return
	theme = UiTheme.build(1.0)

func _ready() -> void:
	if _tabs != null:
		return
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	add_child(body)
	_tabs = TabContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_tabs)
	_tabs.add_child(_mk_scroll(_page_start(), "Start here"))
	_tabs.add_child(_mk_scroll(_page_recipes(), "Recipes"))
	_tabs.add_child(_page_bricks())
	_tabs.add_child(_mk_scroll(_page_shortcuts(), "Shortcuts"))
	_tabs.add_child(_mk_scroll(_page_share(), "Share & publish"))

## Deep links, so other parts of the app can hand someone to the exact page they
## need instead of opening "the help" and hoping they find the tab.
func goto_recipes() -> void:
	if _tabs != null:
		_tabs.current_tab = 1

func show_brick_page(kind: String) -> void:
	if _tabs != null:
		_tabs.current_tab = 2
	_show_brick(kind)

func _mk_scroll(inner: Control, tab_name: String) -> Control:
	var sc := ScrollContainer.new()
	sc.name = tab_name
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	inner.name = "Content"
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(inner)
	return sc

func _vbox(gap: int = 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return v

func _h(text: String, px: int = 18, col: Color = UiTheme.C_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _p(text: String, col: Color = UiTheme.C_MUTED) -> Label:
	var l := _h(text, 13, col)
	l.add_theme_color_override("font_color", col)
	return l

# ---------------------------------------------------------------------------
# Start here
# ---------------------------------------------------------------------------
const STEPS := [
	"1. Tell EasyForge your idea. Type a sentence in the box on the left — “a 2D game where a cat collects fish” — and press Make my game. No key? Skip this and start from a template instead: press New.",
	"2. Or build it yourself. Drag bricks from the left onto the canvas, or just press a brick's name. Start with Character / Item, then Move & Jump.",
	"3. Connect the dots. Drag from the round port on the right of one brick to the port on the left of the next. The colours tell you which ends fit: blue is a value, yellow is a flow, and an event fires the next thing.",
	"4. Press Play. The game runs full-window in this same app. Press Esc, and you are back at your bricks. Nothing you do while playing is written to your project.",
	"5. Change one setting at a time. Click a brick to open its panel on the right; every setting explains itself when you hover it. Press Ctrl+Z if a change was the wrong idea.",
	"6. When it is fun, share it. 🚀 makes a real .exe a friend can double-click. 🌐 makes a web build. 💾 only saves your project file for yourself.",
]

func _page_start() -> Control:
	var v := _vbox(8)
	v.add_child(_h("EasyForge in six steps", 20))
	v.add_child(_p("You describe a game, or you drag bricks onto a canvas. Either way the bricks compile into a real, "
			+ "runnable game — you never write code, and you can always see the code it wrote."))
	for s in STEPS:
		var l := _p(s, UiTheme.C_TEXT)
		l.add_theme_constant_override("line_spacing", 2)
		v.add_child(l)
	v.add_child(_h("The one loop to remember", 15, UiTheme.C_ACCENT_2))
	v.add_child(_p("Describe or add  →  wire  →  Play  →  tweak a setting  →  Play again. Everything else is detail."))
	var jump := Button.new()
	jump.text = "🍳  Show me the recipes"
	jump.pressed.connect(func():
		if _tabs != null:
			_tabs.current_tab = 1
	)
	v.add_child(jump)
	return v

# ---------------------------------------------------------------------------
# Recipes
# ---------------------------------------------------------------------------
func _page_recipes() -> Control:
	var v := _vbox(14)
	v.add_child(_h("Recipes — one click, already wired", 20))
	v.add_child(_p("Each of these adds a small, connected set of bricks to the game you have open right now. "
			+ "They never delete anything, and every one of them is undoable with Ctrl+Z."))
	for task in Recipes.tasks():
		v.add_child(_h(str(task), 15, UiTheme.C_ACCENT_2))
		for r in Recipes.for_task(str(task)):
			v.add_child(_recipe_card(r))
	return v

func _recipe_card(r: Dictionary) -> Control:
	var key := str(r.get("key", ""))
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body := _vbox(6)
	body.add_theme_constant_override("separation", 6)
	card.add_child(body)
	body.add_child(_h(str(r.get("name", key)), 15, UiTheme.C_TEXT))
	body.add_child(_p(str(r.get("pitch", ""))))
	# which bricks land, as chips that jump to that brick's own page
	var chips := _flow()
	for kind in Recipes.kinds_in(key):
		var chip := Button.new()
		chip.text = "%s %s" % [BrickRegistry.kind_icon(str(kind)), BrickDocs.name_for(str(kind))]
		chip.tooltip_text = BrickDocs.help_for(str(kind))
		chip.add_theme_font_size_override("font_size", 11)
		var k := str(kind)
		chip.pressed.connect(func(): _show_brick(k))
		chips.add_child(chip)
	body.add_child(chips)
	var note := str(r.get("note", ""))
	if not note.is_empty():
		body.add_child(_p("💡 " + note, UiTheme.C_ACCENT_2))
	var add := Button.new()
	add.text = "➕  " + I18n.t("add_these_bricks")
	add.custom_minimum_size = Vector2(0, 34)
	UiTheme.paint_primary(add)
	add.pressed.connect(func():
		hide()
		apply_recipe.emit(key)
	)
	body.add_child(add)
	return card

## A row of chips that wraps instead of pushing the panel wider.
func _flow() -> Control:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 6)
	f.add_theme_constant_override("v_separation", 6)
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return f

# ---------------------------------------------------------------------------
# Every brick — reference with its own search
# ---------------------------------------------------------------------------
func _page_bricks() -> Control:
	var wrap := VBoxContainer.new()
	wrap.name = "Every brick"
	wrap.add_theme_constant_override("separation", 8)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var split := HBoxContainer.new()
	# NOTE: deliberately not an HSplitContainer. The smoke test's layout audit
	# hunts for the first HSplitContainer under Main and expects it to be the
	# editor; a splitter in here would be found instead and report a 0px canvas.
	split.add_theme_constant_override("separation", 12)
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrap.add_child(split)

	var left := _vbox(6)
	# Both columns need a real minimum width. With only the left one sized, the
	# HBox squeezed the detail pane until each setting label was clipped to one or
	# two characters — "( / M: / oh" instead of "Motion (choice)".
	left.custom_minimum_size = Vector2(230, 0)
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(left)
	_search = LineEdit.new()
	_search.name = "BrickSearch"
	_search.placeholder_text = "Search the bricks — try 'die', 'bad guy', 'menu'"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): _refill_list())
	left.add_child(_search)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	left.add_child(scroll)
	_brick_list = _vbox(2)
	_brick_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_brick_list)

	var page_scroll := ScrollContainer.new()
	page_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	split.add_child(page_scroll)
	_brick_page = _vbox(8)
	_brick_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_brick_page.custom_minimum_size = Vector2(360, 0)
	page_scroll.add_child(_brick_page)
	_refill_list()
	_show_brick("spawn")
	return wrap

func _refill_list() -> void:
	if _brick_list == null:
		return
	for c in _brick_list.get_children():
		_brick_list.remove_child(c)
		c.queue_free()
	var needle := "" if _search == null else str(_search.text)
	var kinds := BrickRegistry.all_kinds()
	var rows: Array = []
	for kind in kinds:
		if not BrickDocs.matches(str(kind), kinds[kind] as Dictionary, needle):
			continue
		rows.append({"kind": str(kind), "cat": BrickRegistry.kind_category(str(kind)),
			"rank": BrickDocs.rank(str(kind), kinds[kind] as Dictionary, needle)})
	rows.sort_custom(func(a, b):
		if int(a["rank"]) != int(b["rank"]):
			return int(a["rank"]) < int(b["rank"])
		return str(a["kind"]) < str(b["kind"]))
	var last_cat := ""
	for row in rows:
		var cat := str(row["cat"])
		if cat != last_cat:
			last_cat = cat
			var head := _h(BrickDocs.category_label(cat), 11, UiTheme.C_ACCENT_2)
			_brick_list.add_child(head)
		var kind := str(row["kind"])
		var btn := Button.new()
		btn.text = "%s  %s" % [BrickRegistry.kind_icon(kind), BrickDocs.name_for(kind)]
		btn.tooltip_text = BrickDocs.help_for(kind)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 12)
		btn.custom_minimum_size = Vector2(0, 30)
		btn.pressed.connect(func(): _show_brick(kind))
		_brick_list.add_child(btn)

## The right-hand page for one brick: what it does, how it is usually wired,
## every setting in plain words, and its neighbours.
func _show_brick(kind: String) -> void:
	if _brick_page == null:
		return
	for c in _brick_page.get_children():
		_brick_page.remove_child(c)
		c.queue_free()
	var label := "%s %s" % [BrickRegistry.kind_icon(kind), BrickDocs.name_for(kind)]
	_brick_page.add_child(_h(label, 20))
	var says := BrickDocs.says_for(kind)
	if not says.is_empty():
		_brick_page.add_child(_p(says, UiTheme.C_TEXT))
	var use := BrickDocs.use_for(kind)
	if not use.is_empty():
		_brick_page.add_child(_p("🔌 " + use, UiTheme.C_ACCENT_2))

	# ports, in words — the canvas shows them as dots and names them in IR
	var b := BrickRef.create(kind)
	if not b.is_empty():
		var ports := _h("How it connects", 14, UiTheme.C_ACCENT_2)
		_brick_page.add_child(ports)
		for i in (b.get("inputs", []) as Array).size():
			var p: Dictionary = (b.get("inputs", []) as Array)[i]
			_brick_page.add_child(_p("◀ in %d: %s (%s)" % [i, _nice_port(str(p.get("name", ""))), _port_type(int(p.get("type", 0)))]))
		for i in (b.get("outputs", []) as Array).size():
			var p: Dictionary = (b.get("outputs", []) as Array)[i]
			_brick_page.add_child(_p("▶ out %d: %s (%s)" % [i, _nice_port(str(p.get("name", ""))), _port_type(int(p.get("type", 0)))]))

	# settings, each with its explanation
	var schema: Dictionary = BrickRef.PARAM_SCHEMA.get(kind, {})
	if not schema.is_empty():
		_brick_page.add_child(_h("Settings", 14, UiTheme.C_ACCENT_2))
		var sections := ParamRows.sections_for(kind, schema)
		for section_name in sections:
			_brick_page.add_child(_p("▸ " + str(section_name), UiTheme.C_MUTED))
			for key in (sections[section_name] as Array):
				var spec: Dictionary = schema[key]
				# one stacked block per setting: a label line and the sentence that
				# explains it. No HBox: side-by-side columns fight for width inside a
				# scroll pane and clip the label to a couple of characters.
				var row := _vbox(1)
				row.add_child(_h("%s  (%s)" % [str(spec.get("label", str(key).capitalize())), str(spec.get("type", "text"))], 13, UiTheme.C_TEXT))
				var help := BrickDocs.param_help(kind, str(key))
				if not help.is_empty():
					row.add_child(_p(help))
				_brick_page.add_child(row)
	else:
		_brick_page.add_child(_p("This brick has no settings — it works from what you wire into it."))

	var related: Array = BrickDocs.related_for(kind)
	if not related.is_empty():
		_brick_page.add_child(_h("Usually used with", 14, UiTheme.C_ACCENT_2))
		var chips := _flow()
		for r in related:
			var chip := Button.new()
			chip.text = "%s %s" % [BrickRegistry.kind_icon(str(r)), BrickDocs.name_for(str(r))]
			chip.tooltip_text = BrickDocs.help_for(str(r))
			chip.add_theme_font_size_override("font_size", 11)
			var rr := str(r)
			chip.pressed.connect(func(): _show_brick(rr))
			chips.add_child(chip)
		_brick_page.add_child(chips)

	var add := Button.new()
	add.text = "➕  Add this brick to my game"
	add.custom_minimum_size = Vector2(0, 36)
	UiTheme.paint_primary(add)
	add.pressed.connect(func():
		hide()
		add_brick.emit(kind)
	)
	_brick_page.add_child(add)

static func _nice_port(name: String) -> String:
	if name.is_empty():
		return "in"
	return name.replace("_", " ").capitalize()

static func _port_type(t: int) -> String:
	match t:
		0: return "flow — what happens next"
		1: return "event — fires when something happens"
		2: return "value — a number or switch"
	return "flow"

# ---------------------------------------------------------------------------
# Shortcuts
# ---------------------------------------------------------------------------
const KEYS := [
	["Ctrl + Z", "Undo the last change"],
	["Ctrl + Shift + Z", "Redo it"],
	["Ctrl + C / V / D", "Copy, paste, duplicate the selected brick"],
	["Delete", "Remove the selected brick"],
	["Ctrl + S", "Save your project file (it also autosaves by itself)"],
	["Enter in the brick search", "Add the best match straight away"],
	["Drag from the left panel", "Drop a brick exactly where you want it"],
	["Ctrl + F or Ctrl + B", "Jump to the brick search and start typing"],
	["F1", "Open this Manual"],
	["+ / - / 0", "Zoom the canvas in, out, back to normal"],
	["W A S D or arrows", "Pan the canvas (hold Shift to move further)"],
	["Esc", "Stop playing, close a panel, or leave a shipped game"],
]

func _page_shortcuts() -> Control:
	var v := _vbox(6)
	v.add_child(_h("Keyboard", 20))
	v.add_child(_p("Every one of these has a mouse route too — the keyboard is only there to make you fast."))
	for row in KEYS:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		var key := _h(str(row[0]), 13, UiTheme.C_ACCENT_2)
		key.custom_minimum_size = Vector2(190, 0)
		line.add_child(key)
		line.add_child(_p(str(row[1]), UiTheme.C_TEXT))
		v.add_child(line)
	return v

# ---------------------------------------------------------------------------
# Share & publish
# ---------------------------------------------------------------------------
func _page_share() -> Control:
	var v := _vbox(10)
	v.add_child(_h("Getting your game out of EasyForge", 20))
	var rows := [
		["💾  Save (.efg)", "Your project, for you. Opens in EasyForge again. A friend cannot run this — it is the recipe, not the cake."],
		["🚀  Make a game (.exe)", "A folder with <your game>.exe, its .pck and a game.json. Double-click the .exe and it plays. No EasyForge, no install, nothing else needed. Send the whole folder."],
		["🌐  Publish to web", "A build/web folder: an index.html plus the engine files. Browsers refuse to run a .wasm game from a double-clicked file, so put the folder on any host, or run a tiny local server in it."],
		["Autosave", "EasyForge writes your work to its own folder every couple of seconds and when you close. 📂 Open lists the last autosave, every backup, and everything you saved."],
		["Backups", "Switching to a template or a recipe never throws your game away — the graph you had is written to the backups folder first, and 📂 Open can bring it back."],
	]
	for r in rows:
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var body := _vbox(3)
		card.add_child(body)
		body.add_child(_h(str(r[0]), 14, UiTheme.C_TEXT))
		body.add_child(_p(str(r[1])))
		v.add_child(card)
	v.add_child(_p("Tip: name your game first, at the top of the left panel — that name becomes the window title, the save file, and the .exe you send.", UiTheme.C_ACCENT_2))
	return v
