extends Node
## watch — live value inspection: the beginner's debugger.
##
## WHY: a beginner cannot debug "why is my score not going up" when every
## value is invisible. The Watch brick puts the chosen GameState variables
## on screen WHILE the game runs, refreshes them every frame, and (when the
## brick says editable) lets them be edited live in the running game. It is
## the difference between guessing and seeing.
##
## ONE PANEL PER GAME: exactly one node named "WatchPanel" is created on the
## scene root and REUSED by every Watch brick in the graph (never a second
## panel, never a duplicate). A second Watch brick adds its own rows to the
## same panel; its position/font/editable settings are ignored with a
## warning, because one panel can only live in one corner. One panel, many
## rows, no fighting.
##
## NODES CREATED (identical in 2D and 3D — a watch panel is UI, never a
## Node2D/Node3D, which is exactly why it works in both dimensions for free):
##   root
##   └── WatchPanel                 (PanelContainer, generated script)
##       └── Rows                   (VBoxContainer)
##           ├── Row0               (HBoxContainer)
##           │   ├── Name           (Label "coins:")
##           │   └── Value          (LineEdit when editable, else Label)
##           └── Row1 ...
##
## The Labels/LineEdits live INSIDE the panel, never as root children: the
## smoke test scans the root's direct children for Label/Label3D
## placeholders (a Label there means a module failed to build), and a
## PanelContainer there is a real, built feature.
##
## ROW CONTRACT (all of it enforced by the generated script):
##   - every frame each row reads GameState.get_var(name, 0) and shows
##     "name: value" (floats trimmed, bools as true/false)
##   - editable=true: the value is a LineEdit; on Enter it calls
##     GameState.set_var(name, parsed) where parsed is float first, then
##     bool ("true"/"false"), then the raw String. Junk input is ignored
##     and the field snaps back to the stored value.
##   - a watched LineEdit is never overwritten while it has focus, so
##     typing is never fought by the per-frame refresh
##   - show_changes=true: a changed value flashes its row for ~0.3s
##     (a modulate tween) so "it just went up" is impossible to miss
##
## HARD LIMITS + HONESTY:
##   - at most MAX_ROWS (12) rows per panel; extra names are dropped with a
##     warning, never silently. The cap is noted in the generated script,
##     in register_row() and in _watch_names().
##   - rows watch GameState VARIABLES (get_var/set_var — the Variable brick's
##     values and anything a Rule writes). The built-in score/lives are
##     separate GameState PROPERTIES, so watching those needs a Variable
##     brick of the same name. The panel shows exactly what it reads instead
##     of pretending to read the property.
##   - the generated script NEVER names the GameState autoload directly: it
##     resolves /root/GameState at runtime and falls back to the scene's own
##     state twin, so a null or missing GameState hides the values instead
##     of crashing the game. No autoload identifier = no compile dependency.
##
## INTEGRATOR PARAMS (this module only READS them; the integrator adds them
## to BrickRef.PARAM_SCHEMA and BrickRef.KIND — see the block below):
##   KIND entry:
##     "watch": {"label": "Watch", "icon": "🔎", "in": [FLOW], "out": []}
##   PARAM_SCHEMA["watch"]:
##     var_names     text    default "score,coins" (comma separated)
##     position      choice [top_left, top_right, bottom_left, bottom_right]
##                          default "top_left"
##     editable      bool    default true
##     show_changes  bool    default true
##     font_size     number 10..48 step 2  default 18
##
## DETERMINISM: no randf(), no filesystem, no wall-clock. The same graph
## always compiles to the same panel with the same rows, in graph order.

const KIND := "watch"
const PANEL_NAME := "WatchPanel"
const MAX_ROWS := 12          # hard cap: a debug panel, not a spreadsheet
const FONT_MIN := 10
const FONT_MAX := 48
const DEFAULT_NAMES: Array[String] = ["score", "coins"]
const POSITIONS := ["top_left", "top_right", "bottom_left", "bottom_right"]
# layout constants, shared by the generated script and the compile-time build
const PANEL_W := 240.0
const ROW_H := 34.0
const MARGIN := 12.0
const FLASH_SECONDS := 0.3

# The global script class cache does not contain FeatureCtx, so the bare
# identifier is NOT in scope in a feature module. Preload it explicitly —
# the established pattern (see src/features/menu.gd and trigger.gd).
const FeatureCtx = preload("res://src/compiler/feature_ctx.gd")

# The compiler offers every brick to the registry in pass 1 AND pass 2.
# Remember which bricks this module already built for the current root so
# one Watch brick never registers twice (pass 1 + pass 2 = double build).
var _seen := {}
var _seen_root_id := 0

# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

func register(reg) -> void:
	if reg == null or not reg.has_method("register"):
		push_error("[watch] no feature registry available")
		return
	reg.register(KIND, _build)

# ---------------------------------------------------------------------------
# Builder
# ---------------------------------------------------------------------------

func _build(b: Dictionary, root: Node, ctx) -> void:
	if root == null or not is_instance_valid(root):
		return
	if not (b is Dictionary) or not _claim(b, root):
		return

	var bid := FeatureCtx.bid(b)
	var names := _watch_names(b)
	var position := _position_of(b)
	var font := _font_of(b)
	var editable := FeatureCtx.bbool(b, "editable", true)
	var show_changes := FeatureCtx.bbool(b, "show_changes", true)

	# A watch panel is UI: identical in 2D and 3D, so ctx.is_3d is
	# deliberately unread (the menu module documents the same reasoning).
	var panel: PanelContainer = root.get_node_or_null(PANEL_NAME)
	var fresh := false
	if not (panel is PanelContainer):
		panel = PanelContainer.new()
		panel.name = PANEL_NAME
		fresh = true
	# NOTE: the panel's script attaches but its _ready() CANNOT run at compile
	# time — the node is not in a live tree yet, so no rows would ever exist
	# and the user would see an empty box. The compile-time build below mirrors
	# exactly what the generated _ready() builds, so the compiled scene is
	# correct whether or not the script's _ready() ever fires again.
	if fresh:
		root.add_child(panel)

	if panel.has_method("register_row"):
		# REUSE: a second Watch brick in the same graph adds its rows to the
		# panel the first one created — one panel per game, never two.
		_warn_on_config_clash(panel, bid, position, font, editable, show_changes)
	else:
		# First build (or adopting a bare node named WatchPanel): attach the
		# generated script. A parse failure drops the brick, never crashes.
		var src := _panel_source(position, font, editable, show_changes)
		if FeatureCtx.attach_script(panel, src) != OK:
			push_error("[watch] WatchPanel script failed to compile; "
				+ "Watch brick '%s' dropped" % bid)
			if fresh:
				panel.free()
			return
		panel.set_meta("watch_source_brick", bid)
		panel.set_meta("watch_config", {
			"position": position, "font_size": font,
			"editable": editable, "show_changes": show_changes,
		})

	_apply_style(panel, editable)
	_apply_anchors(panel, position, MAX_ROWS)
	# Rows: compile-time built (a script's _ready() cannot run mid-compile).
	# The generated script's register_row() only records the names so a later
	# runtime mount has its row list — it never builds UI, because the UI is
	# already here. _ready() is guarded by the same meta, so nothing doubles.
	for i in names.size():
		_apply_row(panel, i, names[i], font)
		panel.call("register_row", names[i])
	# The generated script's own _ready() is guarded by this meta: the rows
	# exist already, so it must not build them a second time.
	panel.set_meta("watch_rows_built", true)

	# Publish into the same entities map the compiler fills for spawns so a
	# later brick can look this panel up by brick id.
	var ents = _ctxv(ctx, "entities", null)
	if ents is Dictionary and not bid.is_empty():
		ents[bid] = panel

# ---------------------------------------------------------------------------
# Param readers — every read is junk-proof
# ---------------------------------------------------------------------------

## The watched names: comma separated, trimmed, de-duplicated, capped. An
## empty/blank/junk var_names falls back to the documented default pair so
## the panel is never a useless empty box. A list over MAX_ROWS is truncated
## with a warning that names exactly what was dropped.
func _watch_names(b: Dictionary) -> Array[String]:
	var raw = FeatureCtx.params(b).get("var_names")
	var chunks: Array = []
	if raw is Array:
		# junk tolerance: an array of names is accepted as-is
		for v in raw:
			chunks.append(str(v))
	else:
		for part in _clean(FeatureCtx.bstr(b, "var_names", "")).split(","):
			chunks.append(part)
	var uniq: Array[String] = []
	var seen := {}
	for chunk in chunks:
		var n := _clean(str(chunk))
		if n.is_empty() or seen.has(n):
			continue
		seen[n] = true
		uniq.append(n)
	if uniq.is_empty():
		uniq.assign(DEFAULT_NAMES)
	if uniq.size() > MAX_ROWS:
		push_warning("[watch] %d names listed, showing the first %d (dropped: %s)"
			% [uniq.size(), MAX_ROWS, str(uniq.slice(MAX_ROWS))])
		uniq.resize(MAX_ROWS)
	return uniq

func _position_of(b: Dictionary) -> String:
	var s := _clean(FeatureCtx.bstr(b, "position", "top_left")).to_lower()
	s = s.replace(" ", "_").replace("-", "_")
	if not s in POSITIONS:
		push_warning("[watch] unknown position '%s'; using top_left" % s)
		return "top_left"
	return s

func _font_of(b: Dictionary) -> int:
	var v := FeatureCtx.bnum(b, "font_size", 18.0)
	if v != v or v == INF or v == -INF:
		v = 18.0
	return int(clampf(v, float(FONT_MIN), float(FONT_MAX)))

## A later Watch brick cannot re-corner the panel; say so instead of
## silently ignoring its settings.
func _warn_on_config_clash(panel: PanelContainer, bid: String, position: String,
		font: int, editable: bool, show_changes: bool) -> void:
	var cfg = panel.get_meta("watch_config", null)
	if not (cfg is Dictionary):
		return
	var same := (str(cfg.get("position", "")) == position
		and int(cfg.get("font_size", 0)) == font
		and bool(cfg.get("editable", false)) == editable
		and bool(cfg.get("show_changes", false)) == show_changes)
	if same:
		return
	push_warning("[watch] a WatchPanel already exists (from brick '%s'); only "
		% str(panel.get_meta("watch_source_brick", ""))
		+ "this brick's rows are added — position/font/editable/flash come "
		+ "from the first Watch brick")

# ---------------------------------------------------------------------------
# The generated WatchPanel script
#
# One script per compile, attached to the single WatchPanel node. Emitted as
# text so the escape-hatch code view shows the user what their panel does.
# ---------------------------------------------------------------------------

func _panel_source(position: String, font: int, editable: bool,
		show_changes: bool) -> String:
	var L: Array[String] = []
	L.append("extends PanelContainer")
	L.append("# Generated by EasyForge from Watch bricks: a live variable panel.")
	L.append("# The graph owns this file — edit the brick, never the code.")
	L.append("# Every frame each row reads GameState.get_var(name, 0); with an")
	L.append("# editable brick, typing a new value and pressing Enter writes it")
	L.append("# back with GameState.set_var(name, value).")
	L.append("# NULL SAFETY: this script never names the GameState autoload")
	L.append("# directly — it resolves /root/GameState at runtime and falls back")
	L.append("# to the scene's own state twin, so a missing GameState hides the")
	L.append("# values instead of crashing the game.")
	L.append("const POSITION := %s" % _q(position))
	L.append("const FONT_SIZE := %d" % font)
	L.append("const EDITABLE := %s" % ("true" if editable else "false"))
	L.append("const SHOW_CHANGES := %s" % ("true" if show_changes else "false"))
	L.append("const MAX_ROWS := %d" % MAX_ROWS)
	L.append("const FLASH_SECONDS := %f" % FLASH_SECONDS)
	L.append("const PANEL_W := %f" % PANEL_W)
	L.append("const ROW_H := %f" % ROW_H)
	L.append("const MARGIN := %f" % MARGIN)
	L.append("var _rows := []")
	L.append("var _ready_done := false")
	L.append("")
	# --- row registration (the panel is built once, rows are added per brick)
	L.append("func register_row(var_name: String) -> void:")
	L.append("\tvar n := str(var_name)")
	L.append("\tif n.is_empty():")
	L.append("\t\treturn")
	L.append("\tif _rows.size() >= MAX_ROWS:")
	L.append('\t\tpush_warning("[Watch] row cap reached (%d); %s is not shown" % [MAX_ROWS, n])')
	L.append("\t\treturn")
	L.append('\tfor r in _rows:')
	L.append('\t\tif str(r.get("name", "")) == n:')
	L.append("\t\t\treturn")
	L.append('\t_rows.append({"name": n, "node": null, "last": null})')
	L.append("\tif _ready_done:")
	L.append("\t\t_build_row(_rows.size() - 1)")
	L.append("\t\t_apply_position()")
	L.append("")
	L.append("func _ready() -> void:")
	L.append("	# The compiler built these rows at COMPILE time (a script's _ready")
	L.append("	# cannot run while a scene is being compiled). All that is left")
	L.append("	# here is LINKING each recorded name to the node that already")
	L.append("	# exists — never a second build, never a duplicate row.")
	L.append("	_link_existing_rows()")
	L.append("	_style()")
	L.append("	_apply_position()")
	L.append("")
	L.append("func _link_existing_rows() -> void:")
	L.append('	var box := get_node_or_null("Rows")')
	L.append("	if box == null or _rows.is_empty():")
	L.append("		return")
	L.append("	var kids := box.get_children()")
	L.append("	for i in _rows.size():")
	L.append("		if i >= kids.size():")
	L.append("			break")
	L.append("		var r: Dictionary = _rows[i]")
	L.append("		if r.get(\"node\", null) == null and kids[i] is HBoxContainer:")
	L.append('			r["node"] = kids[i].get_node_or_null("Value")')
	L.append("			if EDITABLE:")
	L.append("				var edit_node: LineEdit = r[\"node\"]")
	L.append("				if edit_node != null and not edit_node.text_submitted.is_connected(_on_value_committed):")
	L.append('					edit_node.text_submitted.connect(_on_value_committed.bind(str(r.get("name", ""))))')
	L.append("			var st = _state()")
	L.append('			r["last"] = st.get_var(str(r.get("name", "")), 0) if st != null else 0')
	L.append("	_ready_done = true")
	L.append("")
	L.append("func _style() -> void:")
	L.append("\tvar sb := StyleBoxFlat.new()")
	L.append("\tsb.bg_color = Color(0.05, 0.06, 0.09, 0.72)")
	L.append("\tsb.set_corner_radius_all(8)")
	L.append("\tsb.content_margin_left = 10.0")
	L.append("\tsb.content_margin_right = 10.0")
	L.append("\tsb.content_margin_top = 8.0")
	L.append("\tsb.content_margin_bottom = 8.0")
	L.append('\tadd_theme_stylebox_override("panel", sb)')
	L.append("\t# an editable panel must catch clicks (its fields need them); a")
	L.append("\t# read-only panel stays a transparent overlay and lets clicks")
	L.append("\t# through to the game underneath")
	L.append("\tmouse_filter = Control.MOUSE_FILTER_IGNORE if not EDITABLE else Control.MOUSE_FILTER_STOP")
	L.append("")
	# --- corner anchoring (anchors resolve against the viewport: the panel's
	#     parent is a Node2D/Node3D root, never a Control)
	L.append("func _apply_position() -> void:")
	L.append('	var h := ROW_H * float(maxi(_rows.size(), 1)) + 24.0')
	L.append("	match POSITION:")
	L.append('		"top_right":')
	L.append("			set_anchors_preset(Control.PRESET_TOP_RIGHT)")
	L.append("			grow_horizontal = Control.GROW_DIRECTION_BEGIN")
	L.append("			position = Vector2(-(PANEL_W + MARGIN), MARGIN)")
	L.append('		"bottom_left":')
	L.append("			set_anchors_preset(Control.PRESET_BOTTOM_LEFT)")
	L.append("			grow_vertical = Control.GROW_DIRECTION_BEGIN")
	L.append("			position = Vector2(MARGIN, -(h + MARGIN))")
	L.append('		"bottom_right":')
	L.append("			set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)")
	L.append("			grow_horizontal = Control.GROW_DIRECTION_BEGIN")
	L.append("			grow_vertical = Control.GROW_DIRECTION_BEGIN")
	L.append("			position = Vector2(-(PANEL_W + MARGIN), -(h + MARGIN))")
	L.append("		_:")
	L.append("			set_anchors_preset(Control.PRESET_TOP_LEFT)")
	L.append("			position = Vector2(MARGIN, MARGIN)")
	L.append("	custom_minimum_size = Vector2(PANEL_W, h)")
	L.append("")
	# --- one row: Name label + editable/read-only value
	L.append("func _build_row(i: int) -> void:")
	L.append("\tif i < 0 or i >= _rows.size():")
	L.append("\t\treturn")
	L.append('\tvar box := get_node_or_null("Rows")')
	L.append("\tif box == null:")
	L.append("\t\treturn")
	L.append("\tvar r: Dictionary = _rows[i]")
	L.append('\tvar name_v := str(r.get("name", ""))')
	L.append('\tvar row := HBoxContainer.new()')
	L.append('\trow.name = "Row%d" % i')
	L.append('\trow.add_theme_constant_override("separation", 8)')
	L.append("\tvar name_lbl := Label.new()")
	L.append('\tname_lbl.name = "Name"')
	L.append('\tname_lbl.text = name_v + ":"')
	L.append("\tname_lbl.custom_minimum_size = Vector2(110.0, 0.0)")
	L.append('\tname_lbl.add_theme_font_size_override("font_size", FONT_SIZE)')
	L.append('\tname_lbl.add_theme_color_override("font_color", Color(0.72, 0.78, 0.90))')
	L.append("\trow.add_child(name_lbl)")
	L.append("\tvar st = _state()")
	L.append("\tvar cur = st.get_var(name_v, 0) if st != null else 0")
	L.append('\tr["last"] = cur')
	L.append("\tvar shown := _format(cur)")
	L.append("\tif EDITABLE:")
	L.append("\t\tvar edit := LineEdit.new()")
	L.append('\t\tedit.name = "Value"')
	L.append("\t\tedit.custom_minimum_size = Vector2(120.0, 0.0)")
	L.append('\t\tedit.add_theme_font_size_override("font_size", FONT_SIZE)')
	L.append('\t\tedit.set_meta("watch_name", name_v)')
	L.append("\t\tedit.text = shown")
	L.append("\t\tedit.text_submitted.connect(_on_value_committed.bind(name_v))")
	L.append("\t\trow.add_child(edit)")
	L.append('\t\tr["node"] = edit')
	L.append("\telse:")
	L.append("\t\tvar val := Label.new()")
	L.append('\t\tval.name = "Value"')
	L.append("\t\tval.custom_minimum_size = Vector2(120.0, 0.0)")
	L.append('\t\tval.add_theme_font_size_override("font_size", FONT_SIZE)')
	L.append('\t\tval.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))')
	L.append("\t\tval.text = shown")
	L.append("\t\trow.add_child(val)")
	L.append('\t\tr["node"] = val')
	L.append("\tbox.add_child(row)")
	L.append("")
	# --- per-frame refresh: never touch a field the user is typing in
	L.append("func _process(_delta: float) -> void:")
	L.append("\tif _rows.is_empty():")
	L.append("\t\treturn")
	L.append("\tvar st = _state()")
	L.append("\tif st == null:")
	L.append("\t\treturn")
	L.append("\tfor i in _rows.size():")
	L.append("\t\tvar r: Dictionary = _rows[i]")
	L.append('\t\tvar node: Control = r.get("node", null)')
	L.append("\t\tif node == null or not is_instance_valid(node):")
	L.append("\t\t\tcontinue")
	L.append('		var name_v := str(r.get("name", ""))')
	L.append("		var cur = st.get_var(name_v, 0)")
	L.append('		if _changed(cur, r.get("last", null)):')
	L.append('			r["last"] = cur')
	L.append("			if SHOW_CHANGES:")
	L.append("				_flash(node)")
	L.append("		if node is LineEdit:")
	L.append("			if not (node as LineEdit).has_focus():")
	L.append("				(node as LineEdit).text = _format(cur)")
	L.append("		else:")
	L.append("			(node as Label).text = _format(cur)")
	L.append("")
	# --- change detection that never throws on mixed-type values (a bool vs
	#     an int, a String vs an int, a float vs a bool...). The contract's
	#     known GDScript gotchas list mixed-type comparisons; this is the one
	#     place this panel would hit them, so the comparison goes through a
	#     typed helper instead of `!=` on raw Variants.
	L.append("func _changed(cur, last) -> bool:")
	L.append("	if cur is bool and last is bool:")
	L.append("		return bool(cur) != bool(last)")
	L.append("	if cur is bool or last is bool:")
	L.append("		return true")
	L.append("	if cur is String or last is String:")
	L.append("		return str(cur) != str(last)")
	L.append("	if cur is float or cur is int:")
	L.append("		if last is float or last is int:")
	L.append("			return float(cur) != float(last)")
	L.append("		return true")
	L.append("	return true")
	L.append("")
	# --- state resolution: autoload first, scene twin as fallback
	L.append("func _state():")
	L.append('\tvar st = get_node_or_null("/root/GameState")')
	L.append('\tif st != null and st.has_method("get_var"):')
	L.append("\t\treturn st")
	L.append("\tvar p := get_parent()")
	L.append("\tif p != null:")
	L.append("\t\tfor ch in p.get_children():")
	L.append('\t\t\tif ch != self and ch.has_method("get_var"):')
	L.append("\t\t\t\treturn ch")
	L.append("\treturn null")
	L.append("")
	L.append("func _row_node(name_v: String) -> Control:")
	L.append("\tfor r in _rows:")
	L.append('\t\tif str(r.get("name", "")) != name_v:')
	L.append("\t\t\tcontinue")
	L.append('\t\tvar n: Control = r.get("node", null)')
	L.append("\t\tif n != null and is_instance_valid(n):")
	L.append("\t\t\treturn n")
	L.append("\t\treturn null")
	L.append("\treturn null")
	L.append("")
	# --- the write-back: float, then bool, then String. Junk (a value that
	#     is none of those, or an empty field) is IGNORED — the old value
	#     stays and the field snaps back to it.
	L.append("func _on_value_committed(text: String, name_v: String) -> void:")
	L.append("	var st = _state()")
	L.append("	if st == null:")
	L.append("		return")
	L.append("	var t := text.strip_edges()")
	L.append("	if t.is_empty():")
	L.append("		_snap_back(name_v)")
	L.append("		return")
	L.append("	var parsed = _parse(t)")
	L.append("	if parsed == null:")
	L.append("		# unparseable: keep the stored value, restore the field")
	L.append("		_snap_back(name_v)")
	L.append("		return")
	L.append("	st.set_var(name_v, parsed)")
	L.append('	var node: Control = _row_node(name_v)')
	L.append("	if node != null and node is LineEdit:")
	L.append("		(node as LineEdit).text = _format(st.get_var(name_v, 0))")
	L.append("")
	L.append("func _snap_back(name_v: String) -> void:")
	L.append("	var st = _state()")
	L.append("	if st == null:")
	L.append("		return")
	L.append('	var node: Control = _row_node(name_v)')
	L.append("	if node != null and node is LineEdit:")
	L.append("		(node as LineEdit).text = _format(st.get_var(name_v, 0))")
	L.append("")
	L.append("func _parse(text: String):")
	L.append("	var t := text.strip_edges()")
	L.append("	if t.is_empty():")
	L.append("		return null")
	L.append("	if t.is_valid_float():")
	L.append("		var f := float(t)")
	L.append("		if not is_nan(f) and not is_inf(f):")
	L.append("			return f")
	L.append('	if t.to_lower() == "true":')
	L.append("		return true")
	L.append('	if t.to_lower() == "false":')
	L.append("		return false")
	L.append("	# a String var is a legitimate value, but junk like \"!!x!!\"")
	L.append("	# must never land in the store: only accept text that looks")
	L.append("	# like an identifier (letters, digits, underscore, dot, dash)")
	L.append("	var ok_text := true")
	L.append("	var i := 0")
	L.append("	while i < t.length():")
	L.append("		var ch := t[i]")
	L.append('		var is_word = (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") \\')
	L.append('				or (ch >= "0" and ch <= "9") or ch == "_" or ch == "-" or ch == "."')
	L.append("		if not is_word:")
	L.append("			ok_text = false")
	L.append("			break")
	L.append("		i += 1")
	L.append("	return t if ok_text else null")
	L.append("")
	L.append("func _format(v) -> String:")
	L.append("\tif v is bool:")
	L.append('\t\treturn "true" if v else "false"')
	L.append("\tif v is int:")
	L.append("\t\treturn str(v)")
	L.append("\tif v is float:")
	L.append("\t\tif is_nan(v):")
	L.append('\t\t\treturn "nan"')
	L.append("\t\tif is_inf(v):")
	L.append('\t\t\treturn "inf" if v > 0.0 else "-inf"')
	L.append("\t\tif absf(v - roundf(v)) < 0.0005:")
	L.append('\t\t\treturn "%d" % int(roundf(v))')
	L.append('\t\tvar s := "%.3f" % v')
	L.append('\t\twhile s.ends_with("0"):')
	L.append("\t\t\ts = s.substr(0, s.length() - 1)")
	L.append('\t\tif s.ends_with("."):')
	L.append("\t\t\ts = s.substr(0, s.length() - 1)")
	L.append("\t\treturn s")
	L.append("\tif v is String:")
	L.append("\t\treturn v")
	L.append("\treturn str(v)")
	L.append("")
	L.append("func _flash(node: Control) -> void:")
	L.append("	if not is_instance_valid(node):")
	L.append("		return")
	L.append("	# kill any flash still running on this row so rapid changes do")
	L.append("	# not stack tweens (has_meta first: get_meta errors on a")
	L.append("	# missing key in this engine version)")
	L.append("	if node.has_meta(\"flash_tween\"):")
	L.append("		var old: Tween = node.get_meta(\"flash_tween\", null)")
	L.append("		if old != null and old.is_valid():")
	L.append("			old.kill()")
	L.append("	node.modulate = Color(1.9, 1.8, 1.1)")
	L.append("	var tw := create_tween()")
	L.append('	node.set_meta("flash_tween", tw)')
	L.append('	tw.tween_property(node, "modulate", Color(1.0, 1.0, 1.0), FLASH_SECONDS)')
	return "\n".join(L) + "\n"

# ---------------------------------------------------------------------------
# Compile-time build (mirrors the generated _ready, which cannot run here)
# ---------------------------------------------------------------------------

## The panel chrome. A read-only panel stays MOUSE_FILTER_IGNORE so clicks
## pass through to the game; an editable panel must catch clicks so its
## LineEdits can be focused.
func _apply_style(panel: PanelContainer, editable: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.09, 0.72)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP if editable else Control.MOUSE_FILTER_IGNORE

## Corner anchoring. A Control's anchors resolve against its parent, and the
## panel's parent is a Node2D/Node3D scene root (never a Control), so anchors
## resolve against the viewport — which is exactly what a screen-corner HUD
## panel needs, in 2D and 3D alike.
func _apply_anchors(panel: PanelContainer, position: String, rows: int) -> void:
	var h := ROW_H * float(maxi(rows, 1)) + 24.0
	# The panel's parent is a Node2D/Node3D scene root (never a Control), so
	# anchors resolve against the viewport — exactly what a screen-corner HUD
	# panel needs, in 2D and 3D alike.
	match position:
		"top_right":
			panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			panel.position = Vector2(-(PANEL_W + MARGIN), MARGIN)
		"bottom_left":
			panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
			panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
			panel.position = Vector2(MARGIN, -(h + MARGIN))
		"bottom_right":
			panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
			panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
			panel.position = Vector2(-(PANEL_W + MARGIN), -(h + MARGIN))
		_:   # top_left
			panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
			panel.position = Vector2(MARGIN, MARGIN)
	panel.custom_minimum_size = Vector2(PANEL_W, h)

## One row: "name:" plus a read-only Label or an editable LineEdit. Returns
## the row's value control so the caller can verify it.
func _apply_row(panel: PanelContainer, i: int, name: String, font: int) -> Control:
	var box = panel.get_node_or_null("Rows")
	if box == null:
		box = VBoxContainer.new()
		box.name = "Rows"
		box.add_theme_constant_override("separation", 2)
		panel.add_child(box)
	var row := HBoxContainer.new()
	row.name = "Row%d" % i
	row.add_theme_constant_override("separation", 8)
	var name_lbl := Label.new()
	name_lbl.name = "Name"
	name_lbl.text = name + ":"
	name_lbl.custom_minimum_size = Vector2(110.0, 0.0)
	name_lbl.add_theme_font_size_override("font_size", font)
	name_lbl.add_theme_color_override("font_color", Color(0.72, 0.78, 0.90))
	row.add_child(name_lbl)
	var editable := panel.mouse_filter == Control.MOUSE_FILTER_STOP
	var value: Control
	if editable:
		var edit := LineEdit.new()
		edit.name = "Value"
		edit.custom_minimum_size = Vector2(120.0, 0.0)
		edit.add_theme_font_size_override("font_size", font)
		edit.set_meta("watch_name", name)
		edit.text = "0"
		value = edit
	else:
		var lbl := Label.new()
		lbl.name = "Value"
		lbl.custom_minimum_size = Vector2(120.0, 0.0)
		lbl.add_theme_font_size_override("font_size", font)
		lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))
		lbl.text = "0"
		value = lbl
	row.add_child(value)
	box.add_child(row)
	return value

# ---------------------------------------------------------------------------
# Per-compile dedupe + safe ctx readers
# ---------------------------------------------------------------------------

func _claim(b: Dictionary, root: Node) -> bool:
	var rid := root.get_instance_id()
	if rid != _seen_root_id:
		_seen_root_id = rid
		_seen.clear()
	var key := FeatureCtx.bid(b)
	if key.is_empty():
		key = "anon_%d" % _seen.size()
	if _seen.has(key):
		return false
	_seen[key] = true
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

static func _q(s: String) -> String:
	return "\"" + _clean(s).replace("\\", "\\\\").replace("\"", "\\\"") + "\""
