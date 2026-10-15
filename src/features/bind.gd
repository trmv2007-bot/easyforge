extends Node
## bind — data-bound HUD widgets: a HUD brick that reads a variable and
## draws itself.
##
## WHY: today showing a health bar or an inventory means wiring a brick to a
## variable and writing the display logic by hand. A bound widget just reads
## the variable and draws itself — the brick carries the variable name, the
## widget carries the drawing.
##
## ONE KIND, SIX SHAPES: kind "hud" with a `widget` param that selects the
## real control built:
##   bar       -> TextureProgressBar (a REAL engine progress bar; the fill and
##                background textures are 8x8 solid Color textures generated
##                in memory — no asset files. Chosen over a hand-drawn
##                Control because the engine already handles fill geometry,
##                min/max clamping and range mapping; a custom _draw() bar
##                would re-implement all of that for no gain.)
##   counter   -> Label ("40" or "40 / 100" when show_percent or a max var
##                is named)
##   hearts    -> procedurally generated ColorRect pips inside an HBox; the
##                pip count comes from the maximum, the filled count from the
##                value. No sprites, no assets.
##   minimap   -> a Control-drawn top-down map (SHIPPED: Control-drawn, not
##                SubViewport — a SubViewport needs a world to render into
##                and would duplicate the whole scene graph; a drawn map
##                needs one _draw() and never lies about what it shows).
##                A bordered panel, a dot for the player (re-centred on the
##                player every frame), and a dot for every node in group
##                "minimap_marker". 3D maps (x,z); 2D maps (x,y).
##   inventory -> a row of slots reading GameState vars named inv_<item>
##                (the Inventory brick's convention). Items come from the
##                graph's Inventory bricks; with none present, the widget's
##                var_name is used as the item list; with that empty too,
##                "key".
##   text      -> a plain Label bound to a variable's value.
##
## NODES CREATED (identical in 2D and 3D — a HUD widget is UI, never a
## Node2D/Node3D, which is exactly why it works in both dimensions for free):
##   root
##   └── Hud_<brick_id>                (PanelContainer | Control, generated
##       └── Box            (VBox)     script)  [Control for minimap]
##           ├── Caption    (Label)            [only when `label` is set]
##           └── <body per widget kind>
##
## THE LABEL RULE: every Label lives INSIDE the widget, never as a root
## child. The smoke test scans the root's direct children for Label/Label3D
## placeholders (a Label there means a module failed to build), so a widget
## whose caption or value escaped to the root would read as a broken brick.
##
## ANCHORING: each widget is anchored with a Control preset
## (PRESET_TOP_LEFT / TOP_RIGHT / BOTTOM_LEFT / BOTTOM_RIGHT / CENTER) plus
## explicit per-side offsets, so a widget at "top_right" sits 14px in from
## the top-right corner at 640x360 and at 2560x1440 alike.
##
## NULL / JUNK SAFETY: a missing variable, a null GameState, an absent
## max_var, max <= 0 (clamped to 1), value > max (clamped), junk params and
## an empty var_name all degrade to a harmless default instead of a crash.
## The generated script never names the GameState autoload directly: it
## resolves /root/GameState at runtime and falls back to the scene's own
## state twin, so a missing autoload hides the value instead of throwing.
##
## INTEGRATOR PARAMS (this module only READS them; the integrator adds them
## to BrickRef.KIND and BrickRef.PARAM_SCHEMA):
##   KIND entry:
##     "hud": {"label": "HUD", "icon": "📊", "in": [FLOW], "out": []}
##   PARAM_SCHEMA["hud"]:
##     widget       choice [bar, counter, hearts, minimap, inventory, text]
##                         default "bar"
##     var_name     text    default "health"
##     max_var      text    default "max_health"
##     max_value    number 1..9999 step 1   default 100
##     position     choice [top_left, top_right, bottom_left, bottom_right,
##                         center]           default "top_left"
##     color_name   choice [gold, red, blue, green, purple, white]
##                         default "red"
##     label        text    default ""
##     show_percent bool    default false
##
## DETERMINISM: no randf(), no filesystem, no wall-clock. The same graph
## always compiles to the same widgets, in graph order.

# The global script class cache does not contain FeatureCtx, so the bare
# identifier is NOT in scope in a feature module. Preload it explicitly —
# the established pattern (see src/features/watch.gd, widgets.gd, menu.gd).
const FeatureCtx = preload("res://src/compiler/feature_ctx.gd")

const KIND := "hud"
const WIDGETS := ["bar", "counter", "hearts", "minimap", "inventory", "text"]
const POSITIONS := ["top_left", "top_right", "bottom_left", "bottom_right", "center"]
const COLORS := ["gold", "red", "blue", "green", "purple", "white"]

# layout constants, shared by the generated script and the compile-time build
const MARGIN := 14.0
const FONT := 16
const Z_INDEX := 5
const BAR_W := 220.0
const BAR_H := 18.0
const TEXT_W := 170.0
const TEXT_H := 28.0
const PIP := 16.0
const PIP_GAP := 6.0
const SLOT := 26.0
const SLOT_GAP := 8.0
const MAP_W := 168.0
const MAP_H := 128.0
const CAPTION_H := 22.0
const ROW_GAP := 4.0
const PAD_X := 20.0
const PAD_Y := 16.0
# hard caps: a HUD strip, not a spreadsheet
const MAX_PIPS := 20
const MAX_SLOTS := 12
const MAX_VALUE := 9999.0
const MIN_VALUE := 1.0
# 3D world span a minimap covers (units); 2D levels work in pixels
const SPAN_3D := 64.0
const SPAN_2D := 960.0
const DARK := Color(0.16, 0.18, 0.24, 1.0)
const FRAME := Color(0.05, 0.06, 0.09, 0.72)
const BAR_TRACK := Color(0.10, 0.11, 0.15, 1.0)
const CAPTION_COL := Color(0.72, 0.78, 0.90)
const VALUE_COL := Color(1.0, 0.95, 0.75)

# The compiler offers every brick to the registry in pass 1 AND pass 2.
# Remember which bricks this module already built for the current root so
# one HUD brick never registers twice (pass 1 + pass 2 = double build).
var _seen := {}
var _seen_root_id := 0

# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

func register(reg) -> void:
	if reg == null or not reg.has_method("register"):
		push_error("[bind] no feature registry available")
		return
	reg.register(KIND, _build)
	if reg.has_method("register_seeder"):
		reg.register_seeder(KIND, _seed)

# ---------------------------------------------------------------------------
# Seeder — the bound variables exist before the first tick, so a Rule or a
# Watch brick can read them from frame zero. Never overwrites a value that
# is already there: a Variable brick's seed wins over the HUD's default.
# ---------------------------------------------------------------------------

func _seed(b: Dictionary, state, ctx) -> void:
	if state == null or not state.has_method("set_var"):
		return
	var vars = state.get("vars")
	if not (vars is Dictionary):
		return
	var spec := _spec(b, null, true)
	if not (vars as Dictionary).has(spec["var_name"]):
		state.set_var(spec["var_name"], 0.0)
	if not spec["max_var"].is_empty() and not (vars as Dictionary).has(spec["max_var"]):
		state.set_var(spec["max_var"], spec["max_value"])
	for item in spec["items"]:
		var key := "inv_%s" % str(item)
		if not (vars as Dictionary).has(key):
			state.set_var(key, 0.0)

# ---------------------------------------------------------------------------
# Builder
# ---------------------------------------------------------------------------

func _build(b: Dictionary, root: Node, ctx) -> void:
	if root == null or not is_instance_valid(root):
		return
	if not (b is Dictionary) or not _claim(b, root):
		return

	var is3 := _is_3d(ctx, root)
	var spec := _spec(b, ctx, is3)
	var node := _make(spec)
	if node == null:
		push_error("[bind] could not build a %s HUD widget" % str(spec["widget"]))
		return
	node.name = "Hud" if str(spec["bid"]).is_empty() else "Hud_%s" % str(spec["bid"])
	node.z_index = Z_INDEX
	node.set_meta("hud_kind", spec["widget"])
	node.set_meta("hud_var_name", spec["var_name"])
	_place(node, spec["position"], spec["w"], spec["h"])

	# CRITICAL: attach the script BEFORE add_child(). A script attached to a
	# node that is already in the tree does not get _ready() called again,
	# so a widget built first and scripted second would never bind.
	var err := FeatureCtx.attach_script(node, _script_source(spec))
	if err != OK:
		push_error("[bind] generated %s script failed to compile for '%s'"
			% [str(spec["widget"]), str(node.name)])
		if node.get_parent() == null:
			node.free()
		return
	root.add_child(node)

# ---------------------------------------------------------------------------
# Compile-time build (mirrors the generated _ready, which cannot run here)
# ---------------------------------------------------------------------------

## Build the widget and its children. Every widget is ONE root-level
## Control; the body differs per kind.
func _make(spec: Dictionary) -> Control:
	var widget := str(spec["widget"])
	var label := str(spec["label"])
	var color: Color = spec["color"]
	var root: Control
	var body: Control

	match widget:
		"minimap":
			# The root IS the drawn map: a plain Control, so _draw() is
			# guaranteed to run (no stylebox virtual to fight) and the
			# border, background and dots are all one deterministic draw.
			root = Control.new()
			root.custom_minimum_size = Vector2(spec["w"], spec["h"])
			body = root
		_:
			var panel := PanelContainer.new()
			panel.custom_minimum_size = Vector2(spec["w"], spec["h"])
			var box := VBoxContainer.new()
			box.name = "Box"
			box.add_theme_constant_override("separation", int(ROW_GAP))
			panel.add_child(box)
			root = panel
			body = box

	if not label.is_empty():
		var caption := _caption(label)
		if widget == "minimap":
			caption.set_anchors_preset(Control.PRESET_TOP_LEFT)
			caption.position = Vector2(6.0, 2.0)
			caption.custom_minimum_size = Vector2(MAP_W - 12.0, CAPTION_H)
			root.add_child(caption)
		else:
			root.get_node("Box").add_child(caption)

	match widget:
		"bar":
			var bar := TextureProgressBar.new()
			bar.name = "Bar"
			bar.min_value = 0.0
			bar.max_value = 100.0
			bar.value = 0.0
			bar.step = 0.001
			bar.nine_patch_stretch = false
			bar.texture_over = FeatureCtx.solid_texture(8, 8, BAR_TRACK)
			bar.texture_progress = FeatureCtx.solid_texture(8, 8, color)
			bar.custom_minimum_size = Vector2(BAR_W, BAR_H)
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			body.add_child(bar)
		"counter", "text":
			var lbl := Label.new()
			lbl.name = "Value"
			lbl.custom_minimum_size = Vector2(TEXT_W, TEXT_H)
			lbl.add_theme_font_size_override("font_size", FONT)
			lbl.add_theme_color_override("font_color", VALUE_COL)
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			lbl.text = "0"
			body.add_child(lbl)
		"hearts":
			var pips := HBoxContainer.new()
			pips.name = "Pips"
			pips.add_theme_constant_override("separation", int(PIP_GAP))
			for i in spec["pips"]:
				var pip := ColorRect.new()
				pip.name = "Pip%d" % i
				pip.color = DARK
				pip.custom_minimum_size = Vector2(PIP, PIP)
				pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
				pips.add_child(pip)
			body.add_child(pips)
		"inventory":
			var slots := HBoxContainer.new()
			slots.name = "Slots"
			slots.add_theme_constant_override("separation", int(SLOT_GAP))
			for i in spec["items"].size():
				var item := str(spec["items"][i])
				var slot := ColorRect.new()
				slot.name = "Slot%d" % i
				slot.color = DARK
				slot.custom_minimum_size = Vector2(SLOT, SLOT)
				slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
				slot.set_meta("hud_item", item)
				var count := Label.new()
				count.name = "Count"
				count.text = ""
				count.add_theme_font_size_override("font_size", 12)
				count.add_theme_color_override("font_color", Color(1, 1, 1))
				count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				count.mouse_filter = Control.MOUSE_FILTER_IGNORE
				count.set_anchors_preset(Control.PRESET_FULL_RECT)
				slot.add_child(count)
				slots.add_child(slot)
			body.add_child(slots)

	if widget != "minimap":
		_style(root)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return root

## The panel chrome: a translucent frame so the widget reads over any world.
func _style(panel: Control) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = FRAME
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", sb)

func _caption(text: String) -> Label:
	var lbl := Label.new()
	lbl.name = "Caption"
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", FONT)
	lbl.add_theme_color_override("font_color", CAPTION_COL)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl

## Anchors resolve against the parent, and the widget's parent is the
## Node2D/Node3D scene root (never a Control), so they resolve against the
## viewport — exactly what a screen-corner HUD needs, in 2D and 3D alike.
## Offsets are set on BOTH sides of every axis so the rect is exactly
## w x h at every window size.
func _place(node: Control, position: String, w: float, h: float) -> void:
	match position:
		"top_right":
			node.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			node.offset_left = -(w + MARGIN)
			node.offset_right = -MARGIN
			node.offset_top = MARGIN
			node.offset_bottom = MARGIN + h
		"bottom_left":
			node.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
			node.offset_left = MARGIN
			node.offset_right = MARGIN + w
			node.offset_top = -(h + MARGIN)
			node.offset_bottom = -MARGIN
		"bottom_right":
			node.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
			node.offset_left = -(w + MARGIN)
			node.offset_right = -MARGIN
			node.offset_top = -(h + MARGIN)
			node.offset_bottom = -MARGIN
		"center":
			node.set_anchors_preset(Control.PRESET_CENTER)
			node.offset_left = -w * 0.5
			node.offset_right = w * 0.5
			node.offset_top = -h * 0.5
			node.offset_bottom = h * 0.5
		_:   # top_left
			node.set_anchors_preset(Control.PRESET_TOP_LEFT)
			node.offset_left = MARGIN
			node.offset_right = MARGIN + w
			node.offset_top = MARGIN
			node.offset_bottom = MARGIN + h
	node.custom_minimum_size = Vector2(w, h)

# ---------------------------------------------------------------------------
# Clamped, junk-proof param readers
# ---------------------------------------------------------------------------

## Every user-facing value, validated and clamped, in one place.
func _spec(b: Dictionary, ctx, is3: bool) -> Dictionary:
	var widget := FeatureCtx.bstr(b, "widget", "bar").to_lower()
	widget = widget.replace(" ", "_").replace("-", "_")
	if not (widget in WIDGETS):
		push_warning("[bind] unknown widget '%s'; using bar" % widget)
		widget = "bar"

	# An empty var_name falls back to the documented default so the widget
	# is never a useless empty box.
	var var_name := _clean(FeatureCtx.bstr(b, "var_name", "health"))
	if var_name.is_empty():
		var_name = "health"

	# An absent or empty max_var param means "no maximum variable" — use
	# max_value. This is deliberately NOT the schema default: a user who
	# clears the field wants the plain number, not a variable lookup.
	var max_var := _clean(str(FeatureCtx.params(b).get("max_var", "")))

	var max_value := _clamp_num(FeatureCtx.bnum(b, "max_value", 100.0),
		MIN_VALUE, MAX_VALUE, 100.0)
	var position := _clean(FeatureCtx.bstr(b, "position", "top_left")).to_lower()
	position = position.replace(" ", "_").replace("-", "_")
	if not (position in POSITIONS):
		push_warning("[bind] unknown position '%s'; using top_left" % position)
		position = "top_left"

	var color_name := _clean(FeatureCtx.bstr(b, "color_name", "red")).to_lower()
	if not (color_name in COLORS):
		push_warning("[bind] unknown color '%s'; using red" % color_name)
		color_name = "red"
	var color: Color = FeatureCtx.palette_color(color_name, Color("#ff5252"))

	var label := _clean(FeatureCtx.bstr(b, "label", ""))
	var show_percent := FeatureCtx.bbool(b, "show_percent", false)

	var items := _items_of(b, ctx, var_name)
	var pips := _pip_count(max_value)

	var size := _size_of(widget, label, pips, items.size())
	return {
		"widget": widget,
		"var_name": var_name,
		"max_var": max_var,
		"max_value": max_value,
		"position": position,
		"color": color,
		"color_name": color_name,
		"label": label,
		"show_percent": show_percent,
		"items": items,
		"pips": pips,
		"bid": FeatureCtx.bid(b),
		"w": size.x,
		"h": size.y,
		"map_y": _map_y(label),
		"span": SPAN_2D if not is3 else SPAN_3D,
	}

## Inventory items, in order: every Inventory brick in the graph (the
## convention that seeds inv_<item>), else the widget's own var_name as a
## comma-separated list, else "key".
func _items_of(b: Dictionary, ctx, var_name: String) -> Array[String]:
	var out: Array[String] = []
	var graph = _ctxv(ctx, "graph", null)
	var bricks = _graphv(graph, "bricks", [])
	if bricks is Array:
		for bb in bricks:
			if not (bb is Dictionary):
				continue
			if str((bb as Dictionary).get("kind", "")) != "inventory":
				continue
			var item := _clean(str(FeatureCtx.params(bb).get("item", "key")))
			if item.is_empty():
				item = "key"
			if out.has(item) or out.size() >= MAX_SLOTS:
				continue
			out.append(item)
	if out.is_empty():
		for part in var_name.split(","):
			var item := _clean(str(part))
			if item.is_empty() or out.has(item) or out.size() >= MAX_SLOTS:
				continue
			out.append(item)
	if out.is_empty():
		out.append("key")
	return out

## Hearts are drawn from a compile-time pip count (the runtime maximum is
## only known once the game runs). max_value is the static fallback; pips
## beyond the runtime maximum are simply hidden, and a runtime maximum
## above the pip count shows every pip.
func _pip_count(max_value: float) -> int:
	return int(clampf(roundf(max_value), 1.0, float(MAX_PIPS)))

## Body + panel size for a kind. The caption adds a row when present.
func _size_of(widget: String, label: String, pips: int, slots: int) -> Vector2:
	var body_w := 0.0
	var body_h := 0.0
	match widget:
		"bar":
			body_w = BAR_W
			body_h = BAR_H
		"counter", "text":
			body_w = TEXT_W
			body_h = TEXT_H
		"hearts":
			body_w = float(pips) * PIP + float(maxi(pips - 1, 0)) * PIP_GAP
			body_h = PIP
		"inventory":
			body_w = float(slots) * SLOT + float(maxi(slots - 1, 0)) * SLOT_GAP
			body_h = SLOT
		_:   # minimap
			body_w = MAP_W
			body_h = MAP_H
	var extra := CAPTION_H + ROW_GAP if not label.is_empty() else 0.0
	if widget == "minimap":
		return Vector2(body_w, body_h + extra)
	return Vector2(body_w + PAD_X, body_h + PAD_Y + extra)

func _map_y(label: String) -> float:
	return CAPTION_H + ROW_GAP if not label.is_empty() else 0.0

# ---------------------------------------------------------------------------
# The generated per-widget script
# ---------------------------------------------------------------------------

## One small script per widget, emitted as text so the escape-hatch code
## view shows the user exactly what their HUD does. It reads GameState every
## frame and updates itself; it never writes.
func _script_source(spec: Dictionary) -> String:
	var widget := str(spec["widget"])
	var color: Color = spec["color"]
	var L: Array[String] = []
	L.append("extends %s" % ("Control" if widget == "minimap" else "PanelContainer"))
	L.append("# Generated by EasyForge from a HUD brick (widget: %s)." % widget)
	L.append("#")
	L.append("# WHY this widget reads every frame and never writes: it is a")
	L.append("# VIEW of a variable, not a control. Whatever writes the")
	L.append("# variable (a Collide, a Rule, the Watch panel) is the source of")
	L.append("# truth; this widget only shows it.")
	L.append("#")
	L.append("# NULL SAFETY: this script never names the GameState autoload")
	L.append("# directly — it resolves /root/GameState at runtime and falls")
	L.append("# back to the scene's own state twin, so a missing GameState")
	L.append("# hides the value instead of crashing the game.")
	L.append("const MARGIN := %f" % MARGIN)
	L.append("const _KIND := %s" % _q(widget))
	L.append("const _VAR_NAME := %s" % _q(str(spec["var_name"])))
	L.append("const _MAX_VAR := %s" % _q(str(spec["max_var"])))
	L.append("const _MAX_VALUE := %f" % float(spec["max_value"]))
	L.append("const _COLOR := Color(%f, %f, %f, %f)" % [color.r, color.g, color.b, color.a])
	L.append("const _POSITION := %s" % _q(str(spec["position"])))
	L.append("const _LABEL := %s" % _q(str(spec["label"])))
	L.append("const _SHOW_PERCENT := %s" % ("true" if spec["show_percent"] else "false"))
	L.append("const _W := %f" % float(spec["w"]))
	L.append("const _H := %f" % float(spec["h"]))
	L.append("const _DARK := Color(%f, %f, %f, %f)" % [DARK.r, DARK.g, DARK.b, DARK.a])
	L.append("const _FRAME := Color(%f, %f, %f, %f)" % [FRAME.r, FRAME.g, FRAME.b, FRAME.a])
	if widget == "hearts":
		L.append("const _PIPS := %d" % int(spec["pips"]))
	if widget == "inventory":
		L.append("const _ITEMS: Array[String] = %s" % _array_lit(spec["items"]))
	if widget == "minimap":
		L.append("const _MAP_Y := %f" % float(spec["map_y"]))
		L.append("const _MAP_W := %f" % MAP_W)
		L.append("const _MAP_H := %f" % MAP_H)
		L.append("const _SPAN := %f" % float(spec["span"]))
	L.append("")
	L.append("func _ready() -> void:")
	if widget != "minimap":
		L.append("\t_style()")
	L.append("\t_apply_position()")
	L.append("")
	if widget != "minimap":
		L.append("func _style() -> void:")
		L.append("\tvar sb := StyleBoxFlat.new()")
		L.append("\tsb.bg_color = _FRAME")
		L.append("\tsb.set_corner_radius_all(8)")
		L.append("\tsb.content_margin_left = 10.0")
		L.append("\tsb.content_margin_right = 10.0")
		L.append("\tsb.content_margin_top = 8.0")
		L.append("\tsb.content_margin_bottom = 8.0")
		L.append('\tadd_theme_stylebox_override("panel", sb)')
		L.append("")
	L.append("func _apply_position() -> void:")
	L.append("\tmatch _POSITION:")
	L.append('\t\t"top_right":')
	L.append("\t\t\tset_anchors_preset(Control.PRESET_TOP_RIGHT)")
	L.append("\t\t\toffset_left = -(_W + MARGIN)")
	L.append("\t\t\toffset_right = -MARGIN")
	L.append("\t\t\toffset_top = MARGIN")
	L.append("\t\t\toffset_bottom = MARGIN + _H")
	L.append('\t\t"bottom_left":')
	L.append("\t\t\tset_anchors_preset(Control.PRESET_BOTTOM_LEFT)")
	L.append("\t\t\toffset_left = MARGIN")
	L.append("\t\t\toffset_right = MARGIN + _W")
	L.append("\t\t\toffset_top = -(_H + MARGIN)")
	L.append("\t\t\toffset_bottom = -MARGIN")
	L.append('\t\t"bottom_right":')
	L.append("\t\t\tset_anchors_preset(Control.PRESET_BOTTOM_RIGHT)")
	L.append("\t\t\toffset_left = -(_W + MARGIN)")
	L.append("\t\t\toffset_right = -MARGIN")
	L.append("\t\t\toffset_top = -(_H + MARGIN)")
	L.append("\t\t\toffset_bottom = -MARGIN")
	L.append('\t\t"center":')
	L.append("\t\t\tset_anchors_preset(Control.PRESET_CENTER)")
	L.append("\t\t\toffset_left = -_W * 0.5")
	L.append("\t\t\toffset_right = _W * 0.5")
	L.append("\t\t\toffset_top = -_H * 0.5")
	L.append("\t\t\toffset_bottom = _H * 0.5")
	L.append("\t\t_:")
	L.append("\t\t\tset_anchors_preset(Control.PRESET_TOP_LEFT)")
	L.append("\t\t\toffset_left = MARGIN")
	L.append("\t\t\toffset_right = MARGIN + _W")
	L.append("\t\t\toffset_top = MARGIN")
	L.append("\t\t\toffset_bottom = MARGIN + _H")
	L.append("\tcustom_minimum_size = Vector2(_W, _H)")
	L.append("")
	L.append("func _process(_delta: float) -> void:")
	if widget == "minimap":
		L.append("\tqueue_redraw()")
	else:
		L.append("\tvar st = _state()")
		L.append("\tif st == null:")
		L.append("\t\treturn")
		L.append("\t_refresh(st)")
	L.append("")
	if widget == "minimap":
		L.append("func _draw() -> void:")
		L.append("\tvar origin := Vector2(0.0, _MAP_Y)")
		L.append("\tvar r := Rect2(origin, Vector2(_MAP_W, _MAP_H))")
		L.append("\tdraw_rect(r, _FRAME)")
		L.append("\tdraw_rect(r, _COLOR, false, 1.5)")
		L.append("\tvar centre := _player_pos()")
		L.append("\tvar half := Vector2(_MAP_W, _MAP_H) * 0.5")
		L.append("\tfor mk in _markers():")
		L.append("\t\tvar p: Vector2 = origin + half + (mk - centre) / _SPAN * half")
		L.append("\t\tp.x = clampf(p.x, origin.x + 2.0, origin.x + _MAP_W - 2.0)")
		L.append("\t\tp.y = clampf(p.y, origin.y + 2.0, origin.y + _MAP_H - 2.0)")
		L.append("\t\tdraw_circle(p, 3.0, Color(1.0, 1.0, 1.0, 0.85))")
		L.append("\tvar pp: Vector2 = origin + half")
		L.append("\tdraw_circle(pp, 4.5, _COLOR)")
		L.append("\tdraw_arc(pp, 7.5, 0.0, TAU, 16, _COLOR, 1.0)")
		L.append("")
		L.append("## Marked places: any node in group \"minimap_marker\".")
		L.append("func _markers() -> Array:")
		L.append("\tvar out: Array = []")
		L.append("\tvar tree = get_tree()")
		L.append("\tif tree == null:")
		L.append("\t\treturn out")
		L.append("\tfor n in tree.get_nodes_in_group(\"minimap_marker\"):")
		L.append("\t\tif n == null or not is_instance_valid(n):")
		L.append("\t\t\tcontinue")
		L.append("\t\tout.append(_pos_of(n))")
		L.append("\treturn out")
		L.append("")
		L.append("## The map is centred on the player, so the player dot is")
		L.append("## always in the middle and markers show relative to it.")
		L.append("func _player_pos() -> Vector2:")
		L.append("\tvar p = _player()")
		L.append("\tif p == null:")
		L.append("\t\treturn Vector2.ZERO")
		L.append("\treturn _pos_of(p)")
		L.append("")
		L.append("func _player():")
		L.append("\tvar tree = get_tree()")
		L.append("\tif tree == null:")
		L.append("\t\treturn null")
		L.append("\tvar p = tree.get_first_node_in_group(\"player\")")
		L.append("\tif p != null and is_instance_valid(p):")
		L.append("\t\treturn p")
		L.append("\tvar par = get_parent()")
		L.append("\tif par != null:")
		L.append("\t\tvar f = par.find_child(\"Player\", true, false)")
		L.append("\t\tif f != null:")
		L.append("\t\t\treturn f")
		L.append("\treturn null")
		L.append("")
		L.append("## Top-down projection: 3D maps (x, z), 2D maps (x, y).")
		L.append("func _pos_of(n) -> Vector2:")
		L.append("\tvar n2: Node2D = n as Node2D")
		L.append("\tif n2 != null:")
		L.append("\t\treturn Vector2(n2.global_position.x, n2.global_position.y)")
		L.append("\tvar n3: Node3D = n as Node3D")
		L.append("\tif n3 != null:")
		L.append("\t\treturn Vector2(n3.global_position.x, n3.global_position.z)")
		L.append("\treturn Vector2.ZERO")
		L.append("")
	else:
		L.append("func _refresh(st) -> void:")
		match widget:
			"bar":
				L.append("\tvar bar = get_node_or_null(\"Box/Bar\")")
				L.append("\tif bar == null:")
				L.append("\t\treturn")
				L.append("\tbar.max_value = _max_of(st)")
				L.append("\tbar.value = _value_of(st)")
			"counter":
				L.append("\tvar lbl = get_node_or_null(\"Box/Value\")")
				L.append("\tif lbl == null:")
				L.append("\t\treturn")
				L.append("\tlbl.text = _counter_text(st)")
			"text":
				L.append("	var lbl = get_node_or_null(\"Box/Value\")")
				L.append("	if lbl == null:")
				L.append("		return")
				L.append("	lbl.text = _text_of(st)")
			"hearts":
				L.append("\tvar box = get_node_or_null(\"Box/Pips\")")
				L.append("\tif box == null:")
				L.append("\t\treturn")
				L.append("\tvar filled := clampi(int(floorf(_value_of(st))), 0, _PIPS)")
				L.append("\tvar visible_pips := clampi(int(_max_of(st)), 0, _PIPS)")
				L.append("\tvar i := 0")
				L.append("\tfor ch in box.get_children():")
				L.append("\t\tvar pip: ColorRect = ch as ColorRect")
				L.append("\t\tif pip != null:")
				L.append("\t\t\tpip.visible = i < visible_pips")
				L.append("\t\t\tvar c: Color = _COLOR if i < filled else _DARK")
				L.append("\t\t\tpip.color = c")
				L.append("\t\ti += 1")
			"inventory":
				L.append("\tvar box = get_node_or_null(\"Box/Slots\")")
				L.append("\tif box == null:")
				L.append("\t\treturn")
				L.append("\tvar i := 0")
				L.append("\tfor ch in box.get_children():")
				L.append("\t\tif i >= _ITEMS.size():")
				L.append("\t\t\tbreak")
				L.append("\t\tvar slot: ColorRect = ch as ColorRect")
				L.append("\t\tif slot != null:")
				L.append("\t\t\tvar n := int(roundf(_num_of(st.get_var(\"inv_\" + str(_ITEMS[i]), 0.0))))")
				L.append("\t\t\tvar c: Color = _COLOR if n > 0 else _DARK")
				L.append("\t\t\tslot.color = c")
				L.append("\t\t\tvar lbl: Label = slot.get_node_or_null(\"Count\") as Label")
				L.append("\t\t\tif lbl != null:")
				L.append("\t\t\t\tlbl.text = str(maxi(n, 0)) if n > 0 else \"\"")
				L.append("			i += 1")
	L.append("")
	L.append("## The value, clamped to [0, max]. max <= 0 clamps to 1 so a")
	L.append("## divide/scale can never blow up; value above max clamps down.")
	L.append("func _value_of(st) -> float:")
	L.append("	return clampf(_num_of(st.get_var(_VAR_NAME, 0.0)), 0.0, _max_of(st))")
	L.append("")
	L.append("## The maximum: the named max variable when one exists, else")
	L.append("## the widget's own Max number. Never below 1.")
	L.append("func _max_of(st) -> float:")
	L.append("	var m := _MAX_VALUE")
	L.append("	if not _MAX_VAR.is_empty():")
	L.append("		m = _num_of(st.get_var(_MAX_VAR, _MAX_VALUE))")
	L.append("	if m != m or m == INF or m == -INF:")
	L.append("		m = _MAX_VALUE")
	L.append("	return maxf(1.0, m)")
	L.append("")
	if widget == "counter":
		L.append("func _counter_text(st) -> String:")
		L.append("	if _SHOW_PERCENT or not _MAX_VAR.is_empty():")
		L.append('		return _format(_value_of(st)) + " / " + _format(_max_of(st))')
		L.append("	return _format(_value_of(st))")
	if widget == "text":
		L.append("## The raw stored value as text. A text widget shows whatever")
		L.append("## is in the variable — a String stays a String, a bool reads")
		L.append("## as true/false, a number is formatted. Nothing is coerced")
		L.append("## away, because a text widget's job is to SHOW the value.")
		L.append("func _text_of(st) -> String:")
		L.append("	var v = st.get_var(_VAR_NAME, 0)")
		L.append("	if v is String:")
		L.append("		return str(v)")
		L.append("	if v is bool:")
		L.append('		return "true" if v else "false"')
		L.append("	return _format(_num_of(v))")
	L.append("")
	L.append("## Coerce any stored value to a float without throwing: a bool")
	L.append("## is 1/0, a numeric String parses, everything else is 0.")
	L.append("func _num_of(v) -> float:")
	L.append("\tif v is float or v is int:")
	L.append("\t\treturn float(v)")
	L.append("\tif v is bool:")
	L.append("\t\treturn 1.0 if v else 0.0")
	L.append("\tif v is String:")
	L.append("\t\tvar s: String = str(v)")
	L.append("\t\tif s.is_valid_float():")
	L.append("\t\t\treturn float(s)")
	L.append("\treturn 0.0")
	L.append("")
	L.append("func _format(v: float) -> String:")
	L.append("\tif is_nan(v):")
	L.append('\t\treturn "0"')
	L.append("\tif is_inf(v):")
	L.append('\t\treturn "0"')
	L.append("\tif absf(v - roundf(v)) < 0.0005:")
	L.append('\t\treturn "%d" % int(roundf(v))')
	L.append('\tvar s := "%.3f" % v')
	L.append('\twhile s.ends_with("0"):')
	L.append("\t\ts = s.substr(0, s.length() - 1)")
	L.append('\tif s.ends_with("."):')
	L.append("\t\ts = s.substr(0, s.length() - 1)")
	L.append("\treturn s")
	L.append("")
	L.append("## State resolution: autoload first, scene twin as fallback.")
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
	L.append("## What this widget is actually showing right now. Used by the")
	L.append("## test probe; harmless in a shipped game.")
	L.append("func hud_debug() -> Dictionary:")
	L.append("	var st = _state()")
	L.append("	var out := {\"kind\": _KIND, \"var\": _VAR_NAME, \"max_var\": _MAX_VAR}")
	L.append("	if st == null:")
	L.append("		out[\"state\"] = false")
	L.append("		return out")
	L.append("	out[\"state\"] = true")
	L.append("	var v := _value_of(st)")
	L.append("	var m := _max_of(st)")
	L.append('	out["value"] = v')
	L.append('	out["max"] = m')
	if widget == "bar":
		L.append("\tvar bar = get_node_or_null(\"Box/Bar\")")
		L.append("\tif bar != null:")
		L.append('\t\tout["bar_value"] = bar.value')
		L.append('\t\tout["bar_max"] = bar.max_value')
	if widget == "counter":
		L.append("\tvar lbl = get_node_or_null(\"Box/Value\")")
		L.append("\tif lbl != null:")
		L.append('\t\tout["text"] = lbl.text')
	if widget == "text":
		L.append("\tvar lbl = get_node_or_null(\"Box/Value\")")
		L.append("\tif lbl != null:")
		L.append('\t\tout["text"] = lbl.text')
	if widget == "hearts":
		L.append("	var box = get_node_or_null(\"Box/Pips\")")
		L.append("	var filled := 0")
		L.append("	var shown := 0")
		L.append("	if box != null:")
		L.append("		for ch in box.get_children():")
		L.append("			var pip: ColorRect = ch as ColorRect")
		L.append("			if pip == null:")
		L.append("				continue")
		L.append("			if pip.visible:")
		L.append("				shown += 1")
		L.append("			if pip.visible and pip.color == _COLOR:")
		L.append("				filled += 1")
		L.append('	out["filled"] = filled')
		L.append('	out["shown"] = shown')
		L.append('	out["pips"] = _PIPS')
	if widget == "inventory":
		L.append("\tvar slots := {}")
		L.append("\tvar box = get_node_or_null(\"Box/Slots\")")
		L.append("\tif box != null:")
		L.append("\t\tvar i := 0")
		L.append("\t\tfor ch in box.get_children():")
		L.append("\t\t\tif i >= _ITEMS.size():")
		L.append("\t\t\t\tbreak")
		L.append("\t\t\tvar slot: ColorRect = ch as ColorRect")
		L.append("\t\t\tif slot != null:")
		L.append("\t\t\t\tvar n := int(roundf(_num_of(st.get_var(\"inv_\" + str(_ITEMS[i]), 0.0))))")
		L.append("\t\t\t\tslots[str(_ITEMS[i])] = maxi(n, 0)")
		L.append("\t\t\t\tslots[str(_ITEMS[i]) + \"_filled\"] = slot.color == _COLOR")
		L.append("\t\t\ti += 1")
		L.append('\tout["slots"] = slots')
	if widget == "minimap":
		L.append('\tout["player"] = _player_pos()')
		L.append('\tout["markers"] = _markers().size()')
	L.append("\treturn out")
	return "\n".join(L) + "\n"

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

## Read a key off the graph whether it is a Dictionary or a Node with the
## property (BrickGraph is a Node).
static func _graphv(graph, key: String, default_value):
	if graph is Dictionary:
		var v = (graph as Dictionary).get(key)
		return v if v != null else default_value
	if graph != null:
		var v = graph.get(key)
		return v if v != null else default_value
	return default_value

static func _is_3d(ctx, root: Node) -> bool:
	var v = _ctxv(ctx, "is_3d", null)
	if v is bool:
		return v
	return root is Node3D

static func _clamp_num(v: float, lo: float, hi: float, fallback: float) -> float:
	if v != v or v == INF or v == -INF:
		return fallback
	return clampf(v, lo, hi)

## Text that ends up inside a generated string literal: no newlines, no edges.
static func _clean(s: String) -> String:
	return s.replace("\r", " ").replace("\n", " ").replace("\t", " ").strip_edges()

## Quote a string for a generated GDScript string literal.
static func _q(s: String) -> String:
	var escaped := _clean(s).replace("\\", "\\\\").replace("\"", "\\\"")
	return "\"" + escaped + "\""

## Emit an Array[String] literal for a generated script.
static func _array_lit(items) -> String:
	var parts: Array[String] = []
	for it in items:
		parts.append(_q(str(it)))
	return "[" + ", ".join(parts) + "]"
