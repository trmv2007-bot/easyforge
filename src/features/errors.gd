extends Node
## errors — friendly error reporting for the compiled game (brick kind
## "error_panel"). One node, "ErrorPanel", on the scene root; reused, never
## duplicated.
##
## WHY: today a structural problem in the graph surfaces as a raw IR message
## like "Two bricks share the id 'dup'." — accurate, and useless to a beginner
## who has no idea WHICH brick to click or HOW to fix it. Most of the machinery
## already exists in BrickGraph.validate_ir(); this module makes it human.
##
## THE STATIC HALF (the editor-facing part):
##   Errors.describe_issues(ir: Dictionary) -> Array[Dictionary]
## Takes the same IR dict shape validate_ir() consumes ({"bricks": [...],
## "levels": [...]}) and returns one friendly dict per issue:
##   {"title": ..., "brick_id": ..., "brick_title": ..., "detail": ..., "fix": ...}
## It re-implements validate_ir()'s checks against the raw dict so the editor
## can call it with a plain JSON Dictionary and never needs a BrickGraph node.
## It NEVER throws: a null IR, an empty IR, an IR with no bricks, an issue that
## names a brick id that does not exist, or garbage params all return an empty
## list (or a generic card) instead of crashing.
##
## THE GAME HALF (the runtime UI): the error_panel brick compiles to an
## ErrorPanel Control overlay — a semi-transparent PanelContainer with a close
## button, a title and a scrollable VBox of issue cards. Cards are clickable:
## a click prints a hint to the console AND sets GameState var "__focus_brick"
## to the offending brick id, so a future editor "jump to brick" can consume
## it (that hook is deliberately small: one var, documented below).
##
## WHERE THE ISSUES COME FROM AT RUNTIME: the graph object is not reachable
## from generated game code, so the panel ships with the issues baked in as a
## literal (see _issue_literal). The EDITOR builds that literal from
## describe_issues() and hands it to the brick through the "issues_json"
## param; the builder emits it verbatim. When no issues are baked in (the
## normal, healthy case) the panel is empty, hides itself, and never blocks
## gameplay.
##
## NODES CREATED (identical in 2D and 3D — an error panel is UI):
##   root
##   └── ErrorPanel          (PanelContainer, full rect, generated script)
##       ├── Backdrop        (ColorRect, semi-transparent, blocks clicks)
##       ├── CloseButton     (Button, top-right)
##       ├── Title           (Label)
##       ├── Scroll          (ScrollContainer)
##       │   └── Cards       (VBoxContainer)
##       │       └── IssueCard (Button) x N
##       │           ├── CardTitle   (Label, plain-language headline)
##       │           ├── CardBrick   (Label, "at fault: the red enemy brick")
##       │           ├── CardDetail  (Label, raw technical text — hidden in short)
##       │           └── CardFix     (Label, "how to fix it")
##       └── EmptyNote       (Label, shown when there are no issues)
##
## INTEGRATOR PARAMS (this module only READS them):
##   show_on_start   bool                       default false
##   auto_open       bool                       default true
##   detail_level    choice [short, full]       default short
##   issues_json     text (hidden)              default "" — the baked-in
##                                                 describe_issues() JSON array;
##                                                 the EDITOR fills this in, not
##                                                 the user.
##
## DETERMINISM: no randf(), no filesystem, no wall-clock.

# The Compiler autoload is the parse dependency that pulls FeatureCtx's
# class_name into scope (established pattern — see trigger.gd, menu.gd).
const FeatureCtx = preload("res://src/compiler/feature_ctx.gd")

const KIND := "error_panel"
const PANEL_NAME := "ErrorPanel"
# The GameState var a card click sets, so a future editor can consume
# "which brick did the user click" without any new plumbing.
const FOCUS_VAR := "__focus_brick"
const MAX_ISSUES := 12            # hard cap: an error list, not a log viewer
const DETAIL_LEVELS := ["short", "full"]

# The compiler offers every brick to the registry in pass 1 and again in pass
# 2. Remember which bricks this module already built for the current root so
# one error_panel brick never becomes two panels.
var _built := {}
var _built_root_id := 0

func register(reg) -> void:
	if reg != null and reg.has_method("register"):
		reg.register(KIND, _build)

# ---------------------------------------------------------------------------
# Builder — the error_panel brick -> one ErrorPanel overlay
# ---------------------------------------------------------------------------

func _build(b: Dictionary, root: Node, ctx) -> void:
	if root == null or not (b is Dictionary):
		return
	if not _claim(b, root):
		return

	var show_on_start := FeatureCtx.bbool(b, "show_on_start", false)
	var auto_open := FeatureCtx.bbool(b, "auto_open", true)
	var detail_level := _detail_level_of(b)
	var issues_json := _clean(FeatureCtx.bstr(b, "issues_json", ""))

	var panel := _panel_node(show_on_start, auto_open, detail_level, issues_json)
	if panel == null:
		return
	var err := FeatureCtx.attach_script(panel, _panel_source(show_on_start, auto_open, detail_level, issues_json))
	if err != OK:
		push_warning("[errors] generated ErrorPanel script did not compile for brick '%s'"
			% FeatureCtx.bid(b))
	root.add_child(panel)

# ---------------------------------------------------------------------------
# The ErrorPanel node tree (compile time — data only, no live behaviour)
# ---------------------------------------------------------------------------

func _panel_node(show_on_start: bool, auto_open: bool, detail_level: String,
		issues_json: String) -> Control:
	var panel := PanelContainer.new()
	panel.name = PANEL_NAME
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.visible = show_on_start
	panel.set_meta("show_on_start", show_on_start)
	panel.set_meta("auto_open", auto_open)
	panel.set_meta("detail_level", detail_level)
	panel.set_meta("issues_json", issues_json)

	# --- the dimming backdrop so the errors read above the game -------------
	var dim := ColorRect.new()
	dim.name = "Backdrop"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.color = Color(0.04, 0.04, 0.06, 0.72)
	panel.add_child(dim)

	# --- content: a centred column, narrower than the screen -----------------
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(center)

	var body := VBoxContainer.new()
	body.name = "Body"
	body.custom_minimum_size = Vector2(760.0, 0.0)
	body.add_theme_constant_override("separation", 12)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(body)

	# --- header row: title on the left, close button on the right -----------
	var head := HBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override("separation", 12)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(head)

	var title := Label.new()
	title.name = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.97, 0.97, 1.0))
	title.text = "Your game needs a few fixes"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(title)

	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(96.0, 40.0)
	close_btn.add_theme_font_size_override("font_size", 18)
	close_btn.focus_mode = Control.FOCUS_ALL
	head.add_child(close_btn)

	# --- the scrollable list of cards ---------------------------------------
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0.0, 260.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	body.add_child(scroll)

	var cards := VBoxContainer.new()
	cards.name = "Cards"
	cards.add_theme_constant_override("separation", 10)
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(cards)

	var note := Label.new()
	note.name = "EmptyNote"
	note.text = "Everything checks out — nothing to fix."
	note.add_theme_font_size_override("font_size", 20)
	note.add_theme_color_override("font_color", Color(0.78, 0.80, 0.88))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(note)

	return panel

# ---------------------------------------------------------------------------
# The generated ErrorPanel script
# ---------------------------------------------------------------------------

## One script per compile. The issues arrive as a baked literal (the graph
## object is not reachable from generated game code), the close button and
## every card are wired in _ready (the compiler node that would own that
## Callable is gone by the time the exported game runs), and the panel hides
## itself when there is nothing to report so it can never block gameplay.
func _panel_source(show_on_start: bool, auto_open: bool, detail_level: String,
		issues_json: String) -> String:
	var L: Array[String] = []
	L.append("extends PanelContainer")
	L.append("# Generated by EasyForge from an Error Panel brick: friendly, clickable")
	L.append("# reporting of the graph problems that were found when this game was built.")
	L.append("# Cards are wired HERE in _ready (never at compile time) because the")
	L.append("# compiler node that built them is gone by the time the game runs.")
	L.append("const _ISSUES := %s" % _issue_literal(issues_json))
	L.append("const _DETAIL_LEVEL := %s" % _q(detail_level))
	L.append("const _AUTO_OPEN := %s" % ("true" if auto_open else "false"))
	L.append("const _FOCUS_VAR := %s" % _q(FOCUS_VAR))
	L.append("")
	L.append("func _ready() -> void:")
	L.append("\t_bind_close()")
	L.append("\t_bind_cards()")
	L.append("\tif _ISSUES.is_empty():")
	L.append("\t\t_hide_panel()")
	L.append("\t\treturn")
	L.append("\tif _AUTO_OPEN:")
	L.append("\t\tshow_issues()")
	L.append("\telif not visible:")
	L.append("\t\tvisible = %s" % ("true" if show_on_start else "false"))
	L.append("")
	L.append("# --- the public API other code (a future editor hook, a test) calls ---")
	L.append("func show_issues() -> void:")
	L.append("\tif _ISSUES.is_empty():")
	L.append("\t\t_hide_panel()")
	L.append("\t\treturn")
	L.append("\tvisible = true")
	L.append("\tvar first = _first_card()")
	L.append("\tif first != null and not first.has_focus():")
	L.append("\t\tfirst.grab_focus()")
	L.append("")
	L.append("func hide_issues() -> void:")
	L.append("\t_hide_panel()")
	L.append("")
	L.append("func issue_count() -> int:")
	L.append("\treturn _ISSUES.size()")
	L.append("")
	# --- internals ---
	L.append("func _hide_panel() -> void:")
	L.append("\tvisible = false")
	L.append("\t_show_empty_note(true)")
	L.append("")
	L.append("func _show_empty_note(on: bool) -> void:")
	L.append("\tvar note = get_node_or_null(\"Center/Body/EmptyNote\")")
	L.append("\tif note != null:")
	L.append("\t\tnote.visible = on")
	L.append("\tvar head = get_node_or_null(\"Center/Body/Head\")")
	L.append("\tif head != null:")
	L.append("\t\thead.visible = not on")
	L.append("\tvar scroll = get_node_or_null(\"Center/Body/Scroll\")")
	L.append("\tif scroll != null:")
	L.append("\t\tscroll.visible = not on")
	L.append("")
	L.append("func _cards_box() -> Node:")
	L.append("\treturn get_node_or_null(\"Center/Body/Scroll/Cards\")")
	L.append("")
	L.append("func _first_card() -> Node:")
	L.append("\tvar box = _cards_box()")
	L.append("\tif box == null or box.get_child_count() == 0:")
	L.append("\t\treturn null")
	L.append("\treturn box.get_child(0)")
	L.append("")
	# --- button wiring (the dangling-connection fix, same reasoning as menu.gd) ---
	L.append("func _bind_close() -> void:")
	L.append("\tvar btn = get_node_or_null(\"Center/Body/Head/CloseButton\")")
	L.append("\tif btn is Button and not btn.pressed.is_connected(_on_close):")
	L.append("\t\tbtn.pressed.connect(_on_close)")
	L.append("")
	L.append("func _on_close() -> void:")
	L.append("\thide_issues()")
	L.append("")
	L.append("func _bind_cards() -> void:")
	L.append("\tvar box = _cards_box()")
	L.append("\tif box == null:")
	L.append("\t\treturn")
	L.append("\tfor child in box.get_children():")
	L.append("\t\tif not (child is Button):")
	L.append("\t\t\tcontinue")
	L.append("\t\tvar card: Button = child")
	L.append("\t\tvar brick_id: String = str(card.get_meta(\"brick_id\", \"\"))")
	L.append("\t\tif not card.pressed.is_connected(_on_card.bind(brick_id)):")
	L.append("\t\t\tcard.pressed.connect(_on_card.bind(brick_id))")
	L.append("")
	# --- the click hook: console hint + GameState var for the editor ---------
	L.append("func _on_card(brick_id: String) -> void:")
	L.append("\t# 1. a console hint, so the error is copy-pasteable into a bug report")
	L.append("\tprint(\"[EasyForge] error card clicked — problem is in brick '%s'.\" % brick_id)")
	L.append("\tif brick_id.is_empty():")
	L.append("\t\tprint(\"[EasyForge] this problem belongs to the whole graph, not one brick.\")")
	L.append("\t# 2. the small documented hook: expose the offending brick id on")
	L.append("\t#    GameState so a future editor jump-to-brick can consume it")
	L.append("\t#    without any new plumbing. Never blocks the game if GameState")
	L.append("\t#    is absent (headless runs, unit tests).")
	L.append("\tif not brick_id.is_empty():")
	L.append("\t\t_set_focus_brick(brick_id)")
	L.append("")
	L.append("func _set_focus_brick(brick_id: String) -> void:")
	L.append("\tvar gs = Engine.get_singleton(\"GameState\")")
	L.append("\tif gs == null:")
	L.append("\t\tgs = get_tree().root.get_node_or_null(\"GameState\")")
	L.append("\tif gs != null and gs.has_method(\"set_var\"):")
	L.append("\t\tgs.set_var(_FOCUS_VAR, brick_id)")
	L.append("")
	L.append("func _unhandled_input(event: InputEvent) -> void:")
	L.append("\tif not visible or event == null:")
	L.append("\t\treturn")
	L.append("\tif not (event is InputEventKey) or not event.pressed or event.echo:")
	L.append("\t\treturn")
	L.append("\tvar key: int = (event as InputEventKey).keycode")
	L.append("\tif key == KEY_ESCAPE:")
	L.append("\t\thide_issues()")
	return "\n".join(L) + "\n"

## The issues as a GDScript literal. `issues_json` is the baked-in JSON array
## the editor produces from describe_issues(); when it is empty the panel is
## simply an empty overlay that hides itself in _ready.
func _issue_literal(issues_json: String) -> String:
	var parsed = JSON.parse_string(issues_json) if not issues_json.is_empty() else null
	if not (parsed is Array):
		return "[]"
	var out: Array[String] = []
	var n := 0
	for it in parsed:
		if not (it is Dictionary) or n >= MAX_ISSUES:
			continue
		var d: Dictionary = it
		n += 1
		out.append("{\"title\": %s, \"brick_id\": %s, \"brick_title\": %s, \"detail\": %s, \"fix\": %s}" % [
			_q(_clean(str(d.get("title", "")))),
			_q(_clean(str(d.get("brick_id", "")))),
			_q(_clean(str(d.get("brick_title", "")))),
			_q(_clean(str(d.get("detail", "")))),
			_q(_clean(str(d.get("fix", "")))),
		])
	if out.is_empty():
		return "[]"
	return "[" + ", ".join(out) + "]"

# ===========================================================================
# THE STATIC HALF — describe_issues(): the editor-facing friendly formatter
# ===========================================================================

## Turn a raw IR dict (the same shape BrickGraph.validate_ir() consumes) into
## friendly, clickable issue dicts. Pure function: no node access, no state.
##
## Every branch is guarded: a null IR, a wrong-typed IR, an IR with no bricks,
## a brick that is not a Dictionary, an issue that names a missing brick id,
## and garbage params all produce a safe result (usually an empty list). This
## is the function the EDITOR UI calls, so it must never throw.
static func describe_issues(ir) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (ir is Dictionary):
		return out
	var d := ir as Dictionary
	var bricks = d.get("bricks", null)
	if not (bricks is Array):
		return out
	var list: Array = bricks
	if list.is_empty():
		return out

	# an index of brick_id -> title, built once and consulted by every check,
	# so "which brick is at fault" never throws on a missing id.
	var titles := {}
	for b in list:
		if not (b is Dictionary):
			continue
		var bb := b as Dictionary
		var i = bb.get("id", null)
		if i == null:
			continue
		var k := str(i)
		if k.is_empty():
			continue
		titles[k] = _brick_title(bb)

	# --- duplicate ids (validate_ir code "duplicate_id") ---------------------
	var seen := {}
	for b in list:
		if not (b is Dictionary):
			continue
		var bb := b as Dictionary
		var raw_id = bb.get("id", null)
		if raw_id == null:
			continue
		var bid := str(raw_id)
		if bid.is_empty():
			continue
		if seen.has(bid):
			out.append(_card(
				"Two bricks have the same name",
				bid,
				str(titles.get(bid, "")),
				"Two bricks share the id '%s'." % bid,
				"Rename one of them (click the brick and give it its own name)."))
		seen[bid] = true

	# --- more than one player (validate_ir code "multi_player") --------------
	var player_count := 0
	var first_player_id := ""
	for b in list:
		if not (b is Dictionary):
			continue
		var bb := b as Dictionary
		if str(bb.get("kind", "")) != "spawn":
			continue
		var model = str(_dict_of(bb).get("model", "player"))
		if model == "player":
			player_count += 1
			if first_player_id.is_empty():
				first_player_id = str(bb.get("id", ""))
	if player_count > 1:
		out.append(_card(
			"There is more than one player",
			first_player_id,
			str(titles.get(first_player_id, "")),
			"More than one Spawn brick uses the 'player' model — keep only one.",
			"Delete the extra Spawn bricks, or change their Model to something else."))

	# --- no way to end the game (validate_ir code "no_goal") -----------------
	var has_goal := false
	for b in list:
		if b is Dictionary and str((b as Dictionary).get("kind", "")) in ["winlose", "rule"]:
			has_goal = true
			break
	if not has_goal:
		out.append(_card(
			"The game has no way to end",
			"",
			"",
			"No Win/Lose or Rule brick — the game has no way to end.",
			"Add a Win/Lose brick, or a Rule brick that wins the game."))

	# --- rule reads an undeclared variable (validate_ir code "undefined_var") -
	var declared := {}
	for b in list:
		if b is Dictionary and str((b as Dictionary).get("kind", "")) == "variable":
			var vn := str(_dict_of(b as Dictionary).get("name", ""))
			if not vn.is_empty():
				declared[vn] = true
	for b in list:
		if not (b is Dictionary):
			continue
		var bb := b as Dictionary
		if str(bb.get("kind", "")) != "rule":
			continue
		var rp := _dict_of(bb)
		if str(rp.get("cond_source", "variable")) != "variable":
			continue
		var used := str(rp.get("cond_var", ""))
		if used.is_empty() or declared.has(used):
			continue
		var rid := str(bb.get("id", ""))
		out.append(_card(
			"A Rule reads a variable that does not exist",
			rid,
			str(titles.get(rid, "")),
			"Rule reads variable '%s' but no Variable brick declares it." % used,
			"Add a Variable brick named '%s', or change the Rule's variable." % used))

	return out

## Build one friendly issue card. brick_title falls back to a kind-derived
## description, so "which brick is at fault" is always human-readable even
## when the brick has no title of its own.
static func _card(title: String, brick_id: String, brick_title: String,
		detail: String, fix: String) -> Dictionary:
	return {
		"title": title,
		"brick_id": brick_id,
		"brick_title": brick_title,
		"detail": detail,
		"fix": fix,
	}

## The brick's display title: its own title, else its kind, else "a brick".
static func _brick_title(b: Dictionary) -> String:
	var t = b.get("title", null)
	if t != null and not str(t).is_empty():
		return str(t)
	var k = b.get("kind", null)
	if k != null and not str(k).is_empty():
		return str(k).capitalize()
	return "a brick"

static func _dict_of(b: Dictionary) -> Dictionary:
	var v = b.get("params", null)
	return v if v is Dictionary else {}

# ---------------------------------------------------------------------------
# Safe readers — a brick may hold anything at all for any key.
# ---------------------------------------------------------------------------

func _detail_level_of(b: Dictionary) -> String:
	var s := FeatureCtx.bstr(b, "detail_level", "short").to_lower()
	return s if s in DETAIL_LEVELS else "short"

func _claim(b: Dictionary, root: Node) -> bool:
	var rid := root.get_instance_id()
	if rid != _built_root_id:
		_built_root_id = rid
		_built.clear()
	var bid := FeatureCtx.bid(b)
	var key := bid
	if key.is_empty():
		key = "anon_%d" % _built.size()
	if _built.has(key):
		return false
	_built[key] = true
	return true

## Read a key off ctx whether the integrator hands us a Dictionary (what the
## compiler actually passes) or a FeatureCtx object.
static func _ctxv(ctx, key: String, default_value):
	if ctx is Dictionary:
		var v = (ctx as Dictionary).get(key)
		return v if v != null else default_value
	if ctx != null:
		for prop in ctx.get_property_list():
			if str(prop.get("name", "")) == key:
				return ctx.get(key)
	return default_value

## Text that ends up inside a generated string literal: no newlines, no edges.
static func _clean(s: String) -> String:
	return s.replace("\r", " ").replace("\n", " ").replace("\t", " ").strip_edges()

## A double-quoted GDScript string literal from arbitrary text.
static func _q(s: String) -> String:
	return "\"" + _clean(s).replace("\\", "\\\\").replace("\"", "\\\"") + "\""
