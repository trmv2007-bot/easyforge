extends Node
## widgets — a UI widget library: button, slider, toggle, dropdown.
##
## WHY: a menu could only offer Buttons, and a Button can only fire one fixed
## thing. The moment a game needs "pick a difficulty", "set the volume", or
## "turn the music off", it needs an interactive CONTROL IN THE GAME WORLD —
## a slider that writes a float, a toggle that writes a bool, a dropdown that
## writes an index. Without them an options screen is impossible without
## hand-written code, which is the one thing EasyForge promises never to ask
## of the user.
##
## ONE KIND, FOUR SHAPES: kind "widget" with a widget_kind param that selects
## the real Godot control built:
##   button   -> Button         .pressed        fires the action
##   slider   -> HSlider        .value_changed  fires the action with the float
##   toggle   -> CheckBox       .toggled        fires the action with 1.0 / 0.0
##   dropdown -> OptionButton   .item_selected  fires the action with the index
##
## NODES CREATED (identical in 2D and 3D — a widget is UI, never Node2D/3D):
##   root
##   ├── HUD                                  (the compiler's score HUD)
##   ├── Widget_<brick_id>                    (Button | HSlider | CheckBox |
##   │                                        OptionButton, generated script)
##   └── ...                                  x N, capped at MAX_WIDGETS
##
## LAYOUT IS RESPONSIVE: every widget is anchored with a Control preset
## (PRESET_CENTER / PRESET_CENTER_TOP / PRESET_CENTER_BOTTOM /
## PRESET_CENTER_LEFT / PRESET_CENTER_RIGHT) and then given explicit
## per-side offsets, so a widget at "bottom" stays a centred strip along the
## bottom edge at 640x360 and at 2560x1440 alike. `width` sets
## custom_minimum_size.x; the height is fixed per widget kind.
##
## WHY THERE ARE NO CAPTION LABELS: a Button and a CheckBox carry their own
## text. An HSlider and an OptionButton do not, and the honest alternatives
## were (a) a Label child, which makes a "widget" brick emit a node that is
## not one of the four classes and invites placeholder confusion, or (b) a
## Label SIBLING, which turns one brick into two root children. Neither is
## worth it: the brick title and the code view already say what the widget
## does, and the widget's own action names the variable it drives.
##
## ACTIONS (all real behaviour, no stubs; wired INSIDE the generated script):
##   none         do nothing (a deliberately inert widget)
##   set_var      GameState.set_var(var_name, value)
##   emit_event   GameState.emit_event(var_name, value)
##   start_game   dismiss any ScreenManager, then get_tree().paused = false
##   quit_game    get_tree().quit()
## The value each shape passes is: button -> var_value, toggle -> 1.0 / 0.0,
## slider -> the slider's float, dropdown -> the selected index as a float.
##
## THE CONNECTION RULE (this exact bug shipped once already): signals are
## connected INSIDE the generated script's _ready(), never at compile time on
## the module node. The compiler node that would own such a Callable does not
## exist in the exported game, so the connection would dangle and EVERY
## widget would be inert. attach_script() is therefore called BEFORE
## add_child(), because a script attached to a node already in the tree does
## not get its _ready() re-run.
##
## NULL / JUNK SAFETY: every param is clamped and validated. A widget brick
## with no params, wrong-typed params, an empty label, or an empty dropdown
## list still compiles to a real, working control. A missing GameState
## autoload, a missing ScreenManager, or an empty var_name all degrade to a
## harmless no-op instead of a crash.
##
## INTEGRATOR PARAMS (this module only READS them; the integrator adds them to
## BrickRef.KIND and BrickRef.PARAM_SCHEMA):
##   KIND entry:
##     "widget": {"label": "Widget", "icon": "🎚️", "in": [FLOW], "out": []}
##   PARAM_SCHEMA entry:
##     "widget":
##       widget_kind  choice [button, slider, toggle, dropdown]  default "button"
##       label        text                                       default "Button"
##       action       choice [none, set_var, emit_event,
##                           start_game, quit_game]              default "none"
##       var_name     text                                       default ""
##       var_value    number -1000..1000 step 1                  default 1.0
##       options      text  (comma separated, dropdown)           default ""
##       min_value    number -1000..1000                          default 0.0
##       max_value    number -1000..1000                          default 100.0
##       step         number 0.01..100                            default 1.0
##       position     choice [center, top, bottom, left, right]  default "center"
##       width        number 60..800 step 20                      default 220
##
## DETERMINISM: no randf(), no filesystem, no wall-clock. The same graph
## always compiles to the same widgets, in graph order.

# The global script class cache does not contain FeatureCtx, so the bare
# identifier is NOT in scope in a feature module. Preload it explicitly — the
# established pattern (see src/features/menu.gd, src/features/trigger.gd).
const FeatureCtx = preload("res://src/compiler/feature_ctx.gd")

const WIDGET_KINDS := ["button", "slider", "toggle", "dropdown"]
const ACTIONS := ["none", "set_var", "emit_event", "start_game", "quit_game"]
const POSITIONS := ["center", "top", "bottom", "left", "right"]
# actions that need a named GameState variable to mean anything
const VAR_ACTIONS := ["set_var", "emit_event"]

const DEFAULT_WIDTH := 220.0
const MIN_WIDTH := 60.0
const MAX_WIDTH := 800.0
const WIDTH_STEP := 20.0
# how far an edge-anchored widget sits in from the window edge
const EDGE_MARGIN := 24.0
# per-kind heights: a slider reads as a slider, a button reads as a button
const HEIGHT := {
	"button": 48.0, "slider": 32.0, "toggle": 36.0, "dropdown": 44.0,
}

const MAX_WIDGETS := 24      # hard cap per compile: a widget bar, not a form
const MAX_OPTIONS := 12      # hard cap on dropdown entries
# a dropdown with no usable options is still a dropdown
const FALLBACK_OPTIONS := ["Option 1", "Option 2"]

# Per-compile state. The registry hands the same brick to us in pass 1 AND
# again in pass 2, so remember what this module already built for the current
# root and let one widget brick never become two nodes.
var _seen := {}
var _seen_root_id := 0
var _built := 0

# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

func register(reg) -> void:
	if reg == null or not reg.has_method("register"):
		push_error("[widgets] no feature registry available")
		return
	reg.register("widget", _build)

# ---------------------------------------------------------------------------
# Builder
# ---------------------------------------------------------------------------

## "widget" brick -> one real Control at the root, with a generated script
## that binds its signal in _ready() and runs a real action.
func _build(b: Dictionary, root: Node, ctx) -> void:
	if root == null or not (b is Dictionary):
		return
	if not _claim(b, root):
		return
	if _built >= MAX_WIDGETS:
		push_warning("[widgets] already at the %d-widget cap" % MAX_WIDGETS)
		return

	var kind := _kind_of(b)
	var spec := _spec(b, kind)
	var bid := FeatureCtx.bid(b)

	var node := _make_widget(kind, spec)
	if node == null:
		push_error("[widgets] could not create a %s widget" % kind)
		return
	node.name = "Widget" if bid.is_empty() else "Widget_%s" % bid
	# metadata is for humans and tooling (the probe, the inspector); the
	# generated script carries the values it actually needs as constants.
	node.set_meta("widget_kind", kind)
	node.set_meta("widget_action", spec["action"])
	node.set_meta("widget_var_name", spec["var_name"])
	node.set_meta("widget_var_value", spec["var_value"])
	node.set_meta("widget_position", spec["position"])
	if not bid.is_empty():
		node.set_meta("widget_brick_id", bid)
	# sit above the HUD, which is added later and would otherwise eat clicks
	node.z_index = 10

	_place(node, _preset_for(spec["position"]), spec["position"],
		spec["width"], _height_for(kind))

	# CRITICAL: attach the script BEFORE add_child(). A script attached to a
	# node that is already in the tree does not get _ready() called again, so
	# a widget added first and scripted second would never bind its signal.
	var err := FeatureCtx.attach_script(node, _script_source(kind, spec))
	if err != OK:
		push_error("[widgets] generated %s script failed to compile for '%s'"
			% [kind, str(node.name)])
	root.add_child(node)
	_built += 1

	# A widget is UI, not a physics body, so it is identical in 2D and 3D.
	# The ctx read is kept in the call signature for the ctx contract.
	ctx = null

## Build the real control for a kind. Returns null only if Godot itself
## refuses the constructor, which cannot happen here but keeps the caller
## honest.
func _make_widget(kind: String, spec: Dictionary) -> Control:
	var w: Control
	match kind:
		"slider":
			var s := HSlider.new()
			# range is set BEFORE any signal exists, so configuring the
			# slider never fires the action on startup
			s.min_value = spec["min"]
			s.max_value = spec["max"]
			s.step = spec["step"]
			s.value = spec["min"]
			w = s
		"toggle":
			var c := CheckBox.new()
			c.text = spec["label"]
			# set before connecting: assigning button_pressed later would
			# emit toggled and fire the action on startup
			c.button_pressed = false
			c.alignment = HORIZONTAL_ALIGNMENT_LEFT
			w = c
		"dropdown":
			var o := OptionButton.new()
			for opt in spec["options"]:
				o.add_item(str(opt))
			o.selected = 0
			w = o
		_:   # "button"
			var btn := Button.new()
			btn.text = spec["label"]
			w = btn
	w.mouse_filter = Control.MOUSE_FILTER_STOP
	w.focus_mode = Control.FOCUS_ALL
	return w

# ---------------------------------------------------------------------------
# Placement: anchor presets + explicit offsets so the widget is responsive
# ---------------------------------------------------------------------------

func _preset_for(position: String) -> int:
	match position:
		"top": return Control.PRESET_CENTER_TOP
		"bottom": return Control.PRESET_CENTER_BOTTOM
		"left": return Control.PRESET_CENTER_LEFT
		"right": return Control.PRESET_CENTER_RIGHT
	return Control.PRESET_CENTER

## set_anchors_preset() only fixes the anchors; a fresh Control has a zero
## rect, so the offsets are set explicitly to centre the widget on its
## anchor (or push it EDGE_MARGIN in from an edge). Because each preset keeps
## anchor_left == anchor_right and anchor_top == anchor_bottom, the resulting
## size is exactly w x h at every window size.
func _place(node: Control, preset: int, position: String, w: float, h: float) -> void:
	node.set_anchors_preset(preset)
	node.offset_left = -w * 0.5
	node.offset_right = w * 0.5
	node.offset_top = -h * 0.5
	node.offset_bottom = h * 0.5
	match position:
		"top":
			node.offset_top = EDGE_MARGIN
			node.offset_bottom = EDGE_MARGIN + h
		"bottom":
			node.offset_top = -EDGE_MARGIN - h
			node.offset_bottom = -EDGE_MARGIN
		"left":
			node.offset_left = EDGE_MARGIN
			node.offset_right = EDGE_MARGIN + w
		"right":
			node.offset_left = -EDGE_MARGIN - w
			node.offset_right = -EDGE_MARGIN
	node.custom_minimum_size = Vector2(w, h)

# ---------------------------------------------------------------------------
# Clamped, junk-proof param readers
# ---------------------------------------------------------------------------

func _kind_of(b: Dictionary) -> String:
	var s := FeatureCtx.bstr(b, "widget_kind", "button").to_lower()
	return s if s in WIDGET_KINDS else "button"

func _default_label(kind: String) -> String:
	match kind:
		"slider": return "Slider"
		"toggle": return "Toggle"
		"dropdown": return "Choose"
	return "Button"

## Every user-facing value, validated and clamped, in one place.
func _spec(b: Dictionary, kind: String) -> Dictionary:
	var label := _clean(FeatureCtx.bstr(b, "label", _default_label(kind)))
	if label.is_empty():
		label = _default_label(kind)

	var action := FeatureCtx.bstr(b, "action", "none").to_lower()
	var var_name := _clean(FeatureCtx.bstr(b, "var_name", ""))
	# an action that needs a variable but has none is silently repaired to a
	# safe no-op rather than emitted as broken code
	if action in VAR_ACTIONS and var_name.is_empty():
		action = "none"
	if not (action in ACTIONS):
		action = "none"

	var var_value := _clamp_num(FeatureCtx.bnum(b, "var_value", 1.0), -1000.0, 1000.0, 1.0)

	var lo := _clamp_num(FeatureCtx.bnum(b, "min_value", 0.0), -1000.0, 1000.0, 0.0)
	var hi := _clamp_num(FeatureCtx.bnum(b, "max_value", 100.0), -1000.0, 1000.0, 100.0)
	if lo >= hi:
		# a slider whose min is not below its max is a zero-width (or worse,
		# inverted) range: fall back to the canonical 0..100
		lo = 0.0
		hi = 100.0
	var range := hi - lo
	var st := _clamp_num(FeatureCtx.bnum(b, "step", 1.0), 0.000001, range, 1.0)

	var position := FeatureCtx.bstr(b, "position", "center").to_lower()
	var width := _clamp_num(
		roundf(FeatureCtx.bnum(b, "width", DEFAULT_WIDTH) / WIDTH_STEP) * WIDTH_STEP,
		MIN_WIDTH, MAX_WIDTH, DEFAULT_WIDTH)

	return {
		"label": label,
		"action": action,
		"var_name": var_name,
		"var_value": var_value,
		"options": _options_of(b),
		"min": lo,
		"max": hi,
		"step": st,
		"position": position if position in POSITIONS else "center",
		"width": width,
	}

## Comma-separated dropdown entries: whitespace stripped, empties skipped,
## capped, and never allowed to come out empty.
func _options_of(b: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var raw := str(FeatureCtx.params(b).get("options", ""))
	var parts := raw.split(",")
	for p in parts:
		var t := _clean(str(p))
		if t.is_empty():
			continue
		if out.size() >= MAX_OPTIONS:
			push_warning("[widgets] dropdown truncated to %d options" % MAX_OPTIONS)
			break
		out.append(t)
	if out.is_empty():
		# An OptionButton with zero items is a control that cannot be
		# interacted with meaningfully, so give it two safe defaults.
		# Appended one by one rather than .duplicate(): a duplicate of a
		# typed Array comes back as a plain Array and assigning it back
		# throws at runtime.
		for fb in FALLBACK_OPTIONS:
			out.append(str(fb))
	return out

func _height_for(kind: String) -> float:
	var h = HEIGHT.get(kind, 44.0)
	return float(h) if h != null else 44.0

func _clamp_num(v: float, lo: float, hi: float, fallback: float) -> float:
	if v != v or v == INF or v == -INF:
		return fallback
	return clampf(v, lo, hi)

# ---------------------------------------------------------------------------
# The generated per-widget script
# ---------------------------------------------------------------------------

## One small script per widget. It is emitted as text (so the escape-hatch
## code view shows the user exactly what their widget does) and it is where
## the signal connection lives — never on the compiler-side node.
func _script_source(kind: String, spec: Dictionary) -> String:
	var L: Array[String] = []
	L.append("extends %s" % _extends_for(kind))
	L.append("# Generated by EasyForge from a Widget brick (kind: %s)." % kind)
	L.append("#")
	L.append("# WHY every signal is bound HERE, inside _ready(), and never at")
	L.append("# compile time: the compiler node that built this widget does not")
	L.append("# exist in the exported game, so a connection made at compile time")
	L.append("# would dangle and this widget would sit there doing nothing.")
	L.append("#")
	L.append("# ACTIONS: none = deliberately inert; set_var writes the value into")
	L.append("# a named GameState variable; emit_event broadcasts it on the named")
	L.append("# event channel; start_game dismisses any menu screen and unpauses;")
	L.append("# quit_game exits the game. The value passed is %s." % _value_note(kind))
	L.append("const _ACTION := %s" % _lit(str(spec["action"])))
	L.append("const _VAR_NAME := %s" % _lit(str(spec["var_name"])))
	L.append("const _VAR_VALUE := %f" % float(spec["var_value"]))
	L.append("")
	L.append("func _ready() -> void:")
	L.append("\t_bind()")
	L.append("")
	L.append("func _bind() -> void:")
	L.append(_connect_line(kind))
	L.append("")
	L.append(_handler_for(kind))
	L.append("func _run(value: float) -> void:")
	L.append("\tif _ACTION == \"set_var\" or _ACTION == \"emit_event\":")
	L.append("\t\t_write_var(value)")
	L.append("\telif _ACTION == \"start_game\":")
	L.append("\t\t_start_game()")
	L.append("\telif _ACTION == \"quit_game\":")
	L.append("\t\tget_tree().quit()")
	L.append("\t# \"none\" falls through to nothing on purpose")
	L.append("")
	L.append("## Write the value into GameState. Resolved by node path, never")
	L.append("## through a hard-typed reference, so a missing GameState autoload")
	L.append("## is a null and not a crash.")
	L.append("func _write_var(value: float) -> void:")
	L.append("\tif _VAR_NAME.is_empty():")
	L.append("\t\treturn")
	L.append("\tvar gs = _state()")
	L.append("\tif gs == null or not gs.has_method(\"set_var\"):")
	L.append("\t\treturn")
	L.append("\tif _ACTION == \"set_var\":")
	L.append("\t\tgs.set_var(_VAR_NAME, value)")
	L.append("\telse:")
	L.append("\t\tgs.emit_event(_VAR_NAME, value)")
	L.append("")
	L.append("func _state():")
	L.append("\treturn get_node_or_null(\"/root/GameState\")")
	L.append("")
	L.append("## \"Start\" from inside the game world: leave any menu screen")
	L.append("## behind and let play resume. A missing ScreenManager degrades to")
	L.append("## just unpausing, which is still a real, useful action.")
	L.append("func _start_game() -> void:")
	L.append("\tvar mgr = _screen_manager()")
	L.append("\tif mgr != null and mgr.has_method(\"dismiss\"):")
	L.append("\t\tmgr.call(\"dismiss\")")
	L.append("\tget_tree().paused = false")
	L.append("")
	L.append("func _screen_manager():")
	L.append("\tvar start = get_tree().current_scene")
	L.append("\tif start == null:")
	L.append("\t\tstart = get_parent()")
	L.append("\twhile start != null:")
	L.append("\t\t# owned=false: a manager built at runtime has no owner set,")
	L.append("\t\t# and an instanced one is owned by its scene root")
	L.append("\t\tvar found = start.find_child(\"ScreenManager\", true, false)")
	L.append("\t\tif found != null:")
	L.append("\t\t\treturn found")
	L.append("\t\tstart = start.get_parent()")
	L.append("\treturn null")
	return "\n".join(L) + "\n"

func _extends_for(kind: String) -> String:
	match kind:
		"slider": return "HSlider"
		"toggle": return "CheckBox"
		"dropdown": return "OptionButton"
	return "Button"

## What value the widget hands to its action.
func _value_note(kind: String) -> String:
	match kind:
		"slider": return "the slider's float value"
		"toggle": return "1.0 when on, 0.0 when off"
		"dropdown": return "the selected index as a float"
	return "_VAR_VALUE (the widget's Set to param)"

## The signal wiring, one line per kind, inside _bind().
func _connect_line(kind: String) -> String:
	match kind:
		"slider": return "\tif not value_changed.is_connected(_on_value):\n\t\tvalue_changed.connect(_on_value)"
		"toggle": return "\tif not toggled.is_connected(_on_toggled):\n\t\ttoggled.connect(_on_toggled)"
		"dropdown": return "\tif not item_selected.is_connected(_on_selected):\n\t\titem_selected.connect(_on_selected)"
	return "\tif not pressed.is_connected(_on_pressed):\n\t\tpressed.connect(_on_pressed)"

## The signal handler for a kind, translating the signal's argument into the
## one float every action consumes.
func _handler_for(kind: String) -> String:
	var L: Array[String] = []
	match kind:
		"slider":
			L.append("func _on_value(v: float) -> void:")
			L.append("\t_run(v)")
		"toggle":
			L.append("func _on_toggled(is_on: bool) -> void:")
			L.append("\t_run(1.0 if is_on else 0.0)")
		"dropdown":
			L.append("func _on_selected(index: int) -> void:")
			L.append("\t_run(float(index))")
		_:
			L.append("func _on_pressed() -> void:")
			L.append("\t_run(_VAR_VALUE)")
	L.append("")
	return "\n".join(L) + "\n"

# ---------------------------------------------------------------------------
# Per-compile dedupe + shared helpers
# ---------------------------------------------------------------------------

func _claim(b: Dictionary, root: Node) -> bool:
	var rid := root.get_instance_id()
	if rid != _seen_root_id:
		_seen_root_id = rid
		_seen.clear()
		_built = 0
	var bid := FeatureCtx.bid(b)
	var key := bid
	if key.is_empty():
		key = "anon_%d" % _seen.size()
	if _seen.has(key):
		return false
	_seen[key] = true
	return true

## Text that ends up inside a generated string literal: no newlines, no edges.
static func _clean(s: String) -> String:
	return s.replace("\r", " ").replace("\n", " ").replace("\t", " ").strip_edges()

## Quote a string for a generated GDScript string literal.
static func _lit(s: String) -> String:
	var escaped := _clean(s).replace("\\", "\\\\").replace("\"", "\\\"")
	return "\"" + escaped + "\""
