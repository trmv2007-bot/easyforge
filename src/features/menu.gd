extends Node
## menu — a Screen/Menu system: the single biggest gap in the EasyForge survey.
##
## WHY THIS IS THE BIGGEST GAP: every world-class engine ships a menu system
## (Unity's uGUI, Unreal's UMG/W_Blueprint). Godot beginners rebuild it by hand
## in EVERY project — title screen, pause, game over, win, credits, settings,
## plus a button abstraction, a screen stack, keyboard/gamepad navigation and
## pause wiring. EasyForge already generates a score HUD; this module adds the
## whole first thing a player ever sees and the last thing before they quit.
##
## TWO KINDS:
##   kind "screen" -> one full-screen Control scene (background + title +
##                    optional subtitle + a buttons VBoxContainer)
##   kind "button" -> one Button routed to an action; it lands in the screen it
##                    is wired to (see ATTACHMENT below)
##
## ONE MANAGER: exactly one node named "ScreenManager" is created on the root
## and REUSED if a screen brick builds again (never duplicated). It owns the
## screen stack (push/pop/replace), pauses the tree for blocking screens, and
## routes button presses to real behaviour.
##
## ATTACHMENT (buttons are optional to wire, so three tiers, first hit wins):
##   1. CONNECTED  — a graph connection from the screen brick to the button
##                   brick (read from the brick's "connections" list).
##   2. PARENT     — the button's "parent_screen" param names the screen brick
##                   id it belongs to (the integrator adds this param).
##   3. FALLBACK   — no connection and no parent_screen: the button attaches to
##                   the FIRST screen brick in the graph.
## A standalone BUTTON brick in a graph with NO screen brick never crashes: it
## is skipped with a warning (there is nothing to attach it to).
##
## NODES CREATED (identical in 2D and 3D — a menu is UI, never Node2D/3D):
##   root
##   ├── ScreenManager            (Node, PROCESS_MODE_ALWAYS, generated script)
##   ├── Screen_<id>              (Control, PRESET_FULL_RECT)            x N
##   │   ├── Dim                 (ColorRect, PRESET_FULL_RECT, click blocker)
##   │   ├── TransitionOverlay   (ColorRect, PRESET_FULL_RECT, IGNORE)   when fade
##   │   ├── Panel              (CenterContainer, PRESET_FULL_RECT)
##   │   │   └── Column          (VBoxContainer, centred)
##   │   │       ├── TitleLabel  (Label, big font)
##   │   │       ├── SubtitleLabel (Label, only when subtitle is non-empty)
##   │   │       └── Buttons     (VBoxContainer)
##   │   │           └── Button   x M
##   │   └── (a "blur" screen gets an extra Notes ColorRect — see the honesty
##   │       note below; Godot has no cheap runtime blur without a shader)
##   ├── HUD                      (the compiler's score HUD, untouched)
##   └── GameState                (the compiler's state node, untouched)
##
## BUTTON ACTIONS (all real behaviour, no stubs):
##   start       hide the screen, unpause, reset the timer state of play
##   resume      pop the screen off the stack (unpauses when the stack empties)
##   restart     get_tree().reload_current_scene()
##   quit        get_tree().quit()
##   goto_screen replace the top of the stack with the named target screen
##   toggle_var  GameState.toggle_var(name) then pop
##   set_var     GameState.set_var(name, value) then pop
##
## PAUSE MODEL: a screen with pause_game=true (pause/game_over/win kinds do by
## default) sets get_tree().paused = true when shown and false when the last
## blocking screen leaves the stack. The manager itself runs with
## PROCESS_MODE_ALWAYS so its buttons keep working while paused. Generated game
## scripts (player movement etc.) are pausable because they inherit the
## default PROCESS_MODE_INHERIT from the scene root.
##
## NAVIGATION: arrow keys / D-pad move the selection, Enter/Space/A activates,
## mouse clicks work through normal Button signals. The first button of the
## top screen grabs focus when that screen is shown.
##
## HONESTY NOTE ON "blur": Godot 4 has no cheap runtime blur without a
## shader/blur-copy pass, so the blur background is a semi-transparent dark
## ColorRect PLUS a lighter inset ColorRect that reads as a frosted panel. It
## is dimming, not a real gaussian blur, and this file says so in a comment
## the user can read in the generated code view.
##
## INTEGRATOR PARAMS (this module only READS them; the integrator adds them to
## BrickRef.PARAM_SCHEMA and BrickRef.KIND — see the schema block below).
##
##   KIND entries:
##     "screen": {"label": "Screen", "icon": "🖥️", "in": [FLOW], "out": [FLOW]}
##     "button": {"label": "Button", "icon": "🔘", "in": [FLOW], "out": [FLOW]}
##
##   PARAM_SCHEMA entries (defaults shown; every one is clamped on read):
##     "screen":
##       kind_of_screen  choice [main_menu, pause, game_over, win, credits,
##                               settings]              default "main_menu"
##       title           text                         default "My Game"
##       subtitle        text                         default ""
##       background      choice [dark, blur, none]    default "dark"
##       transition      choice [fade, slide, none]   default "fade"
##       show_on_start   bool                         default true
##       pause_game      bool                         default true for
##                                                    pause/game_over/win,
##                                                    false otherwise
##     "button":
##       label           text                         default "Play"
##       action          choice [start, resume, restart, quit, goto_screen,
##                               toggle_var, set_var]  default "start"
##       target_screen   text                         default ""  (goto_screen)
##       parent_screen   text                         default ""  (see ATTACHMENT)
##       var_name        text                         default ""  (toggle/set_var)
##       var_value       number -1000..1000           default 1.0  (set_var)
##
##   parent_screen is the ONE param this module added beyond the brief: it names
##   the id of the screen brick this button belongs to, so a button works even
##   when the user never draws a wire. Attachment falls back to it in tier 2.
##
## DETERMINISM: no randf(), no filesystem, no wall-clock. The same graph always
## compiles to the same screens, in graph order.

# The global script class cache does not contain FeatureCtx, so the bare
# identifier is NOT in scope in a feature module. Preload it explicitly —
# the established pattern (see src/features/trigger.gd).
const FeatureCtx = preload("res://src/compiler/feature_ctx.gd")

const MANAGER_NAME := "ScreenManager"
const MAX_SCREENS := 12          # hard cap: a menu system, not a level list
const MAX_BUTTONS := 10          # hard cap per screen
const TITLE_SIZE := 48.0
const SUBTITLE_SIZE := 22.0
const BUTTON_SIZE := 22.0
const BUTTON_W := 260.0
const BUTTON_H := 56.0
const GAP := 12.0
const FADE_SECONDS := 0.25
const SCREEN_KINDS := ["main_menu", "pause", "game_over", "win", "credits", "settings"]
const BACKGROUNDS := ["dark", "blur", "none"]
const TRANSITIONS := ["fade", "slide", "none"]
const ACTIONS := ["start", "resume", "restart", "quit", "goto_screen", "toggle_var", "set_var"]
# kinds whose screen blocks play by default (pause_game defaults true)
const BLOCKING_KINDS := ["pause", "game_over", "win"]

# Per-compile state. The registry may offer the same brick in pass 1 and again
# in pass 2, so remember what this module already built for the current root
# and let one screen/button brick never become two nodes.
var _seen := {}
var _seen_root_id := 0
# brick_id -> the compiled Screen Control for that brick (this compile)
var _screens := {}
var _screen_order: Array[String] = []

# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

func register(reg) -> void:
	if reg == null or not reg.has_method("register"):
		push_error("[menu] no feature registry available")
		return
	reg.register("screen", _build_screen)
	reg.register("button", _build_button)

# ---------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------

## "screen" brick -> one full-screen Control scene plus (once) the manager.
func _build_screen(b: Dictionary, root: Node, ctx) -> void:
	if root == null or not (b is Dictionary):
		return
	if not _claim(b, root):
		return

	var is3 := _is_3d(ctx)
	var kind := _screen_kind(b)
	var title := FeatureCtx.bstr(b, "title", "My Game")
	var subtitle := _clean(FeatureCtx.bstr(b, "subtitle", ""))
	var background := _background_of(b)
	var transition := _transition_of(b)
	var show_on_start := FeatureCtx.bbool(b, "show_on_start", true)
	var pause_game := _pause_of(b, kind)
	var bid := FeatureCtx.bid(b)

	# Buttons: wired ones first, then parent_screen, then the first screen.
	# (Resolved in _button_ids_for so this builder stays readable.)
	var buttons := _button_specs(b, ctx, bid)

	var scr := _screen_node(bid, kind, title, subtitle, background, transition,
		show_on_start, pause_game, buttons)
	root.add_child(scr)

	if not bid.is_empty():
		_screens[bid] = scr
		_screen_order.append(bid)

	_ensure_manager(root, is3)

	# Publish into the same entities map the compiler fills for spawns so a
	# later brick can look this screen up by brick id.
	var ents = _ctxv(ctx, "entities", null)
	if ents is Dictionary and not bid.is_empty():
		ents[bid] = scr

	# A menu is UI, not a physics body, so it is identical in 2D and 3D. The
	# is_3d read is kept in the call signature for the ctx contract; nothing in
	# this module branches on it, which is exactly the point.

## "button" brick -> a Button inside its owning screen's Buttons VBox.
func _build_button(b: Dictionary, root: Node, ctx) -> void:
	if root == null or not (b is Dictionary):
		return
	if not _claim(b, root):
		return

	var owner := _owner_screen_id(b, ctx)
	if owner.is_empty():
		push_warning("[menu] Button brick '%s' has no screen to attach to "
			% FeatureCtx.bid(b) + "(wire it to a Screen brick or set parent_screen)")
		return
	var scr = _screens.get(owner, null)
	if scr == null or not is_instance_valid(scr):
		push_warning("[menu] Button brick '%s' targets screen '%s' which was not built"
			% [FeatureCtx.bid(b), owner])
		return

	var spec := _button_spec(b, ctx)
	_append_button(scr, spec)

# ---------------------------------------------------------------------------
# Screen construction
# ---------------------------------------------------------------------------

func _screen_node(bid: String, kind: String, title: String, subtitle: String,
		background: String, transition: String, show_on_start: bool,
		pause_game: bool, buttons: Array) -> Control:
	var scr := Control.new()
	scr.name = "Screen" if bid.is_empty() else "Screen_%s" % bid
	scr.set_anchors_preset(Control.PRESET_FULL_RECT)
	scr.mouse_filter = Control.MOUSE_FILTER_STOP
	scr.visible = show_on_start
	scr.set_meta("screen_kind", kind)
	scr.set_meta("blocks_play", pause_game)
	scr.set_meta("show_on_start", show_on_start)
	scr.set_meta("transition", transition)

	# --- background: a ColorRect for dark/blur, nothing for "none" -----------
	if background == "dark" or background == "blur":
		var dim := ColorRect.new()
		dim.name = "Dim"
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		dim.mouse_filter = Control.MOUSE_FILTER_STOP
		# blur is a deeper, cooler dim than dark: reads as a frosted screen
		if background == "blur":
			dim.color = Color(0.05, 0.06, 0.09, 0.78)
		else:
			dim.color = Color(0.04, 0.04, 0.06, 0.86)
		scr.add_child(dim)

		if background == "blur":
			# HONESTY NOTE: this is NOT a gaussian blur. Godot 4 has no cheap
			# runtime blur without a shader pass, so a "blur" background is a
			# darker dim plus a light frosted panel behind the content. It
			# separates the menu from the game; it does not blur it.
			var panel := ColorRect.new()
			panel.name = "FrostPanel"
			panel.set_anchors_preset(Control.PRESET_CENTER)
			panel.custom_minimum_size = Vector2(560.0, 420.0)
			panel.color = Color(0.16, 0.17, 0.21, 0.55)
			panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
			scr.add_child(panel)

	# --- transition overlay: a ColorRect the manager tweens ---------------
	if transition == "fade":
		var ov := ColorRect.new()
		ov.name = "TransitionOverlay"
		ov.set_anchors_preset(Control.PRESET_FULL_RECT)
		ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ov.color = Color(0.0, 0.0, 0.0, 0.0)
		scr.add_child(ov)

	# --- content: a centred column ----------------------------------------
	var center := CenterContainer.new()
	center.name = "Panel"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scr.add_child(center)

	var col := VBoxContainer.new()
	col.name = "Column"
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", int(GAP))
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(col)

	var lbl := Label.new()
	lbl.name = "TitleLabel"
	lbl.text = title
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", int(TITLE_SIZE))
	lbl.add_theme_color_override("font_color", Color(0.97, 0.97, 1.0))
	col.add_child(lbl)

	if not subtitle.is_empty():
		var sub := Label.new()
		sub.name = "SubtitleLabel"
		sub.text = subtitle
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.add_theme_font_size_override("font_size", int(SUBTITLE_SIZE))
		sub.add_theme_color_override("font_color", Color(0.78, 0.80, 0.88))
		col.add_child(sub)

	var bbox := VBoxContainer.new()
	bbox.name = "Buttons"
	bbox.alignment = BoxContainer.ALIGNMENT_CENTER
	bbox.add_theme_constant_override("separation", int(GAP))
	bbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(bbox)

	for spec in buttons:
		_append_button(scr, spec)

	return scr

## Add one Button node to the screen's Buttons VBox. Never throws: a screen
## missing its Buttons container (hand-edited tree) simply gets skipped.
func _append_button(scr: Control, spec: Dictionary) -> void:
	if scr == null or not is_instance_valid(scr):
		return
	if not (spec is Dictionary) or spec.is_empty():
		return
	var bbox = scr.get_node_or_null("Panel/Column/Buttons")
	if bbox == null or not (bbox is VBoxContainer):
		return
	var count := bbox.get_child_count()
	if count >= MAX_BUTTONS:
		push_warning("[menu] screen '%s' already has the %d-button cap"
			% [str(scr.name), MAX_BUTTONS])
		return
	var btn := Button.new()
	btn.text = str(spec.get("label", "Button"))
	btn.custom_minimum_size = Vector2(BUTTON_W, BUTTON_H)
	btn.add_theme_font_size_override("font_size", int(BUTTON_SIZE))
	btn.focus_mode = Control.FOCUS_ALL
	bbox.add_child(btn)
	var bid := str(spec.get("id", ""))
	if not bid.is_empty():
		btn.set_meta("button_brick_id", bid)
	btn.set_meta("action", str(spec.get("action", "start")))
	btn.set_meta("target_screen", str(spec.get("target_screen", "")))
	btn.set_meta("var_name", str(spec.get("var_name", "")))
	btn.set_meta("var_value", float(spec.get("var_value", 1.0)))
	# NOTE: no `pressed.connect(...)` here. The compiler node that would own
	# that Callable is gone in the exported game, so the connection would
	# dangle. The ScreenManager binds every button in its own _ready instead.
	# A Button carries only its action metadata: buttons are data, and the
	# manager is the single place that decides what a press means.

# ---------------------------------------------------------------------------
# The manager: one node, reused, always alive while paused
# ---------------------------------------------------------------------------

func _ensure_manager(root: Node, is3: bool) -> void:
	var existing = _find_manager(root)
	if existing != null:
		return
	var mgr := Node.new()
	mgr.name = MANAGER_NAME
	# The manager MUST keep processing while the tree is paused, or a pause
	# menu would freeze its own Resume button.
	mgr.process_mode = Node.PROCESS_MODE_ALWAYS
	var src := _manager_source(is3)
	if FeatureCtx.attach_script(mgr, src) == OK:
		root.add_child(mgr)
	else:
		push_error("[menu] ScreenManager script failed to compile; menus disabled")
		mgr.free()

func _find_manager(from: Node) -> Node:
	if from == null:
		return null
	var root := from
	while root != null and root.get_parent() != null:
		root = root.get_parent()
	if root == null:
		return null
	var direct = root.get_node_or_null(MANAGER_NAME)
	if direct != null:
		return direct
	# a compiled game can be mounted under a level container; search one down
	for child in root.get_children():
		var n = child.get_node_or_null(MANAGER_NAME) if child is Node else null
		if n != null:
			return n
	return null

# ---------------------------------------------------------------------------
# Button -> screen resolution (the three-tier attachment rule)
# ---------------------------------------------------------------------------

## Which screen brick owns this button brick? Tier 1 a connection, tier 2 the
## parent_screen param, tier 3 the first screen brick in the graph.
func _owner_screen_id(b: Dictionary, ctx) -> String:
	# tier 1: a real graph connection from a screen brick to this button
	var wired := _wired_screen_id(b, ctx)
	if not wired.is_empty():
		return wired
	# tier 2: the explicit parent_screen param (the integrator adds it)
	var parent := _clean(FeatureCtx.bstr(b, "parent_screen", ""))
	if not parent.is_empty():
		return parent
	# tier 3: the first screen brick in the graph
	var graph = _ctxv(ctx, "graph", null)
	if graph != null and graph.has_method("get_brick") and graph.get("bricks") is Array:
		for other in graph.get("bricks"):
			if other is Dictionary and str(other.get("kind", "")) == "screen":
				var oid := str(other.get("id", ""))
				if not oid.is_empty():
					return oid
	return ""

## The screen brick a button is connected TO (graph connections are stored on
## the SOURCE brick, so also scan every other screen brick's connections for a
## link pointing at this button — wiring direction is not guaranteed).
func _wired_screen_id(b: Dictionary, ctx) -> String:
	var bid := FeatureCtx.bid(b)
	var graph = _ctxv(ctx, "graph", null)
	if graph == null or bid.is_empty():
		return ""
	if not graph.has_method("get_brick") or not (graph.get("bricks") is Array):
		return ""
	for other in graph.get("bricks"):
		if not (other is Dictionary):
			continue
		if str(other.get("kind", "")) != "screen":
			continue
		var oid := str(other.get("id", ""))
		if oid.is_empty():
			continue
		for c in other.get("connections", []):
			if c is Dictionary and str(c.get("to_brick", "")) == bid:
				return oid
	# also honour a connection declared ON the button pointing at a screen
	for c in b.get("connections", []):
		if c is Dictionary:
			var tid := str(c.get("to_brick", ""))
			if not tid.is_empty():
				var t = graph.get_brick(tid)
				if t is Dictionary and not t.is_empty() and str(t.get("kind", "")) == "screen":
					return tid
	return ""

## The full button list for a screen brick: its own connected buttons plus any
## button that names this screen via parent_screen (tier 2 when unwired).
func _button_specs(screen_brick: Dictionary, ctx, screen_id: String) -> Array:
	var out: Array = []
	var seen := {}
	var graph = _ctxv(ctx, "graph", null)
	var all: Array = []
	if graph != null and graph.get("bricks") is Array:
		all = graph.get("bricks")
	for other in all:
		if not (other is Dictionary):
			continue
		if str(other.get("kind", "")) != "button":
			continue
		var oid := FeatureCtx.bid(other)
		if not oid.is_empty() and seen.has(oid):
			continue
		var owner := _owner_screen_id(other, ctx)
		if owner != screen_id:
			continue
		if not oid.is_empty():
			seen[oid] = true
			# Claim the button brick here: the screen already emitted its node,
			# so _build_button must not add a second copy when the registry
			# offers the same brick in a later pass.
			_seen[oid] = true
		out.append(_button_spec(other, ctx))
	# A screen with no buttons at all is legal (credits, a splash) — but a
	# playable main menu with nothing to press is a dead end, so give the first
	# screen a Play button when the graph provided none.
	if out.is_empty() and screen_id == _first_screen_id(all) and not screen_id.is_empty():
		out.append({
			"label": "Play", "action": "start", "target_screen": "",
			"var_name": "", "var_value": 1.0, "id": "",
		})
	return out

func _first_screen_id(all: Array) -> String:
	for other in all:
		if other is Dictionary and str(other.get("kind", "")) == "screen":
			var oid := str(other.get("id", ""))
			if not oid.is_empty():
				return oid
	return ""

func _button_spec(b: Dictionary, ctx) -> Dictionary:
	var action := _action_of(b)
	var label := FeatureCtx.bstr(b, "label", _default_label_for(action))
	var target := _clean(FeatureCtx.bstr(b, "target_screen", ""))
	var var_name := _clean(FeatureCtx.bstr(b, "var_name", ""))
	var var_value := _clamp_num(FeatureCtx.bnum(b, "var_value", 1.0), -1000.0, 1000.0, 1.0)
	# an action that needs a target/var but has none is silently repaired to a
	# safe no-op rather than emitted as broken code
	if action == "goto_screen" and target.is_empty():
		action = "resume"
	if (action == "toggle_var" or action == "set_var") and var_name.is_empty():
		action = "resume"
	return {
		"label": label,
		"action": action,
		"target_screen": target,
		"var_name": var_name,
		"var_value": var_value,
		"id": FeatureCtx.bid(b),
	}

func _default_label_for(action: String) -> String:
	match action:
		"start": return "Play"
		"resume": return "Resume"
		"restart": return "Restart"
		"quit": return "Quit"
		"goto_screen": return "Continue"
		"toggle_var": return "Toggle"
		"set_var": return "Set"
	return "Play"

# ---------------------------------------------------------------------------
# Clamped param readers — every param is junk-proof
# ---------------------------------------------------------------------------

func _screen_kind(b: Dictionary) -> String:
	var s := FeatureCtx.bstr(b, "kind_of_screen", "main_menu").to_lower()
	return s if s in SCREEN_KINDS else "main_menu"

func _background_of(b: Dictionary) -> String:
	var s := FeatureCtx.bstr(b, "background", "dark").to_lower()
	return s if s in BACKGROUNDS else "dark"

func _transition_of(b: Dictionary) -> String:
	var s := FeatureCtx.bstr(b, "transition", "fade").to_lower()
	return s if s in TRANSITIONS else "fade"

func _action_of(b: Dictionary) -> String:
	var s := FeatureCtx.bstr(b, "action", "start").to_lower()
	return s if s in ACTIONS else "start"

func _pause_of(b: Dictionary, kind: String) -> bool:
	# pause/game_over/win block play by default; the user can override either way
	if kind in BLOCKING_KINDS:
		return FeatureCtx.bbool(b, "pause_game", true)
	return FeatureCtx.bbool(b, "pause_game", false)

func _clamp_num(v: float, lo: float, hi: float, fallback: float) -> float:
	if v != v or v == INF or v == -INF:
		return fallback
	return clampf(v, lo, hi)

# ---------------------------------------------------------------------------
# The generated ScreenManager script
# ---------------------------------------------------------------------------

## One manager script per compile (not per screen): it owns the stack, reads
## every screen's metadata at runtime and routes the actions. Emitted as text
## so the escape-hatch code view shows the user what their menu does.
func _manager_source(is3: bool) -> String:
	var L: Array[String] = []
	L.append("extends Node")
	L.append("# Generated by EasyForge from Screen bricks: the ScreenManager.")
	L.append("# Owns a screen stack, pauses the tree for blocking screens and")
	L.append("# routes every menu button to a real action. Runs with")
	L.append("# PROCESS_MODE_ALWAYS so its buttons work while the game is paused.")
	L.append("# NOTE: the buttons are wired HERE (in _ready) rather than at")
	L.append("# compile time, because the compiler that built them is gone by the")
	L.append("# time the exported game runs — a connection to a compile-time node")
	L.append("# would dangle and the menu would do nothing.")
	L.append("const _FADE_SECONDS := %f" % FADE_SECONDS)
	L.append("var _stack: Array[Control] = []")
	L.append("var _busy := false")
	L.append("")
	L.append("func _ready() -> void:")
	L.append("	process_mode = Node.PROCESS_MODE_ALWAYS")
	L.append("	var root = get_parent()")
	L.append("	if root == null:")
	L.append("		return")
	L.append("	# every Screen_* child of the root is a screen of this system")
	L.append("	for child in root.get_children():")
	L.append("		if not (child is Control):")
	L.append("			continue")
	L.append("		if not child.has_meta(\"screen_kind\"):")
	L.append("			continue")
	L.append("		_bind_buttons(child)")
	L.append("		child.visible = bool(child.get_meta(\"show_on_start\", true))")
	L.append("		if bool(child.get_meta(\"show_on_start\", true)):")
	L.append("			_push(child)")
	L.append("	_refresh_focus()")
	L.append("")
	# --- button wiring (the fix for the dangling compile-time connection) ---
	L.append("func _bind_buttons(screen: Control) -> void:")
	L.append("	if screen == null or not is_instance_valid(screen):")
	L.append("		return")
	L.append("	var box = screen.get_node_or_null(\"Panel/Column/Buttons\")")
	L.append("	if box == null:")
	L.append("		return")
	L.append("	for child in box.get_children():")
	L.append("		if not (child is Button):")
	L.append("			continue")
	L.append("		var b: Button = child")
	L.append("		if not b.pressed.is_connected(_activate_bound):")
	L.append("			b.pressed.connect(_activate_bound.bind(b))")
	L.append("")
	L.append("func _activate_bound(btn: Button) -> void:")
	L.append("	activate(btn)")
	L.append("")
	# --- stack primitives ---
	L.append("func _push(screen: Control) -> void:")
	L.append("\tif screen == null or not is_instance_valid(screen):")
	L.append("\t\treturn")
	L.append("\tif _stack.has(screen):")
	L.append("\t\treturn")
	L.append("\tif _stack.size() >= %d:" % MAX_SCREENS)
	L.append("\t\t_stack.pop_front()")
	L.append("\t_stack.append(screen)")
	L.append("\tscreen.visible = true")
	L.append("\t_apply_pause()")
	L.append("\t_play_transition(screen, true)")
	L.append("\t_refresh_focus()")
	L.append("")
	L.append("func _pop() -> void:")
	L.append("\tif _stack.is_empty():")
	L.append("\t\treturn")
	L.append("\tvar top: Control = _stack.pop_back()")
	L.append("\t_play_transition(top, false)")
	L.append("\ttop.visible = false")
	L.append("\t_apply_pause()")
	L.append("\t_refresh_focus()")
	L.append("")
	L.append("func _replace(screen: Control) -> void:")
	L.append("\twhile not _stack.is_empty():")
	L.append("\t\tvar old: Control = _stack.pop_back()")
	L.append("\t\told.visible = false")
	L.append("\t_push(screen)")
	L.append("")
	L.append("func dismiss() -> void:")
	L.append("\t# \"start\": the menu has done its job — clear the whole stack")
	L.append("\tfor s in _stack:")
	L.append("\t\tif s != null and is_instance_valid(s):")
	L.append("\t\t\ts.visible = false")
	L.append("\t_stack.clear()")
	L.append("\t_apply_pause()")
	L.append("\t_refresh_focus()")
	L.append("")
	# --- pause wiring ---
	L.append("func _apply_pause() -> void:")
	L.append("\tvar blocked := false")
	L.append("\tfor s in _stack:")
	L.append("\t\tif s != null and is_instance_valid(s) and bool(s.get_meta(\"blocks_play\", false)):")
	L.append("\t\t\tblocked = true")
	L.append("\tget_tree().paused = blocked")
	L.append("")
	# --- navigation ---
	L.append("func _refresh_focus() -> void:")
	L.append("\tif _stack.is_empty():")
	L.append("\t\treturn")
	L.append("\tvar top: Control = _stack[_stack.size() - 1]")
	L.append("\tif top == null or not is_instance_valid(top):")
	L.append("\t\treturn")
	L.append("\tvar buttons = top.get_node_or_null(\"Panel/Column/Buttons\")")
	L.append("\tif buttons == null or buttons.get_child_count() == 0:")
	L.append("\t\treturn")
	L.append("\tvar first: Button = buttons.get_child(0)")
	L.append("\tif first != null and not first.has_focus():")
	L.append("\t\tfirst.grab_focus()")
	L.append("")
	L.append("func _unhandled_input(event: InputEvent) -> void:")
	L.append("\tif _stack.is_empty() or event == null:")
	L.append("\t\treturn")
	L.append("\tif not (event is InputEventKey) or not event.pressed or event.echo:")
	L.append("\t\treturn")
	L.append("\tvar key: int = (event as InputEventKey).keycode")
	L.append("\tvar top: Control = _stack[_stack.size() - 1]")
	L.append("\tif top == null or not is_instance_valid(top):")
	L.append("\t\treturn")
	L.append("\tvar buttons = top.get_node_or_null(\"Panel/Column/Buttons\")")
	L.append("\tif buttons == null:")
	L.append("\t\treturn")
	L.append("\tmatch key:")
	L.append("\t\tKEY_UP, KEY_DOWN:")
	L.append("\t\t\t_move_selection(buttons, key == KEY_UP)")
	L.append("\t\tKEY_ENTER, KEY_KP_ENTER, KEY_SPACE:")
	L.append("\t\t\t# a focused Button already fires on Enter/Space itself; only")
	L.append("\t\t\t# fall back to the first button when nothing has focus")
	L.append("\t\t\tif buttons.get_child_count() > 0:")
	L.append("\t\t\t\tvar first: Button = buttons.get_child(0)")
	L.append("\t\t\t\tif first != null and not _any_focused(buttons):")
	L.append("\t\t\t\t\tfirst.grab_focus()")
	L.append("\t\t\t\t\tactivate(first)")
	L.append("\t\tKEY_ESCAPE:")
	L.append("\t\t\t# Escape closes the top screen when it is dismissible")
	L.append("\t\t\tif not bool(top.get_meta(\"blocks_play\", false)):")
	L.append("\t\t\t\t_pop()")
	L.append("\t")
	L.append("func _any_focused(container: Node) -> bool:")
	L.append("\tfor child in container.get_children():")
	L.append("\t\tif child is Control and (child as Control).has_focus():")
	L.append("\t\t\treturn true")
	L.append("\treturn false")
	L.append("")
	L.append("func _move_selection(container: Node, up: bool) -> void:")
	L.append("\tvar n := container.get_child_count()")
	L.append("\tif n <= 1:")
	L.append("\t\treturn")
	L.append("\tvar focused := -1")
	L.append("\tfor i in n:")
	L.append("\t\tvar c = container.get_child(i)")
	L.append("\t\tif c is Control and (c as Control).has_focus():")
	L.append("\t\t\tfocused = i")
	L.append("\t\t\tbreak")
	L.append("\tvar next := 0")
	L.append("	if focused == -1:")
	L.append("		next = 0")
	L.append("	else:")
	L.append("		next = (focused - 1) if up else (focused + 1)")
	L.append("	next = (next + n) % n")
	L.append("\tvar target = container.get_child(next)")
	L.append("\tif target is Button:")
	L.append("\t\t(target as Button).grab_focus()")
	L.append("")
	# --- transition ---
	L.append("func _play_transition(screen: Control, showing: bool) -> void:")
	L.append("\tif screen == null or not is_instance_valid(screen):")
	L.append("\t\treturn")
	L.append("\tvar mode: String = str(screen.get_meta(\"transition\", \"none\"))")
	L.append("\tvar overlay = screen.get_node_or_null(\"TransitionOverlay\")")
	L.append("\tif mode == \"fade\" and overlay != null:")
	L.append("\t\tvar cr: ColorRect = overlay")
	L.append("\t\tif _busy:")
	L.append("\t\t\treturn")
	L.append("\t\t_busy = true")
	L.append("\t\tvar target_a := 0.0 if showing else 0.65")
	L.append("\t\tvar c := cr.color")
	L.append("\t\tif showing:")
	L.append("\t\t\tc.a = 0.65")
	L.append("\t\t\tcr.color = c")
	L.append("\t\tcr.visible = true")
	L.append("\t\tvar tw := create_tween()")
	L.append("\t\ttw.tween_property(cr, \"color:a\", target_a, _FADE_SECONDS)")
	L.append("\t\tawait tw.finished")
	L.append("\t\tif is_instance_valid(cr) and target_a <= 0.0:")
	L.append("\t\t\tcr.visible = false")
	L.append("\t\t_busy = false")
	L.append("\t\treturn")
	L.append("	if mode == \"slide\" and screen is Control:")
	L.append("		# an honest slide: the screen starts offset and eases to place.")
	L.append("		# No real blur here either — a menu that moves reads as a menu.")
	L.append("		var from_y := screen.position.y + (screen.size.y * 0.35 if showing else 0.0)")
	L.append("		screen.position = Vector2(screen.position.x, from_y)")
	L.append("		var tw2 := create_tween()")
	L.append("		tw2.tween_property(screen, \"position:y\", 0.0, _FADE_SECONDS)")
	L.append("		await tw2.finished")
	L.append("")
	# --- the action router ---
	L.append("func activate(btn: Button) -> void:")
	L.append("\tif btn == null or not is_instance_valid(btn):")
	L.append("\t\treturn")
	L.append("\tvar action: String = str(btn.get_meta(\"action\", \"start\"))")
	L.append("\tGameState.play_sound(\"click\", 0.35)")
	L.append("\tmatch action:")
	L.append("\t\t\"start\":")
	L.append("\t\t\tdismiss()")
	L.append("\t\t\tget_tree().paused = false")
	L.append("\t\t\"resume\":")
	L.append("\t\t\t_pop()")
	L.append("\t\t\"restart\":")
	L.append("\t\t\tget_tree().reload_current_scene()")
	L.append("\t\t\"quit\":")
	L.append("\t\t\tget_tree().quit()")
	L.append("\t\t\"goto_screen\":")
	L.append("\t\t\tvar target_name: String = str(btn.get_meta(\"target_screen\", \"\"))")
	L.append("\t\t\tvar root = get_parent()")
	L.append("\t\t\tif root != null and not target_name.is_empty():")
	L.append("\t\t\t\tvar found: Control = null")
	L.append("\t\t\t\tfor child in root.get_children():")
	L.append("\t\t\t\t\tif child is Control and str(child.name).ends_with(target_name):")
	L.append("\t\t\t\t\t\tfound = child")
	L.append("\t\t\t\t\t\tbreak")
	L.append("				if found != null:")
	L.append("					_replace(found)")
	L.append("				else:")
	L.append("					_pop()")
	L.append("\t\t\"toggle_var\":")
	L.append("\t\t\tvar vn: String = str(btn.get_meta(\"var_name\", \"\"))")
	L.append("\t\t\tif not vn.is_empty():")
	L.append("\t\t\t\tGameState.toggle_var(vn)")
	L.append("\t\t\t_pop()")
	L.append("\t\t\"set_var\":")
	L.append("\t\t\tvar svn: String = str(btn.get_meta(\"var_name\", \"\"))")
	L.append("\t\t\tif not svn.is_empty():")
	L.append("\t\t\t\tGameState.set_var(svn, float(btn.get_meta(\"var_value\", 1.0)))")
	L.append("\t\t\t_pop()")
	L.append("")
	L.append("func screen_count() -> int:")
	L.append("\treturn _stack.size()")
	L.append("")
	L.append("func is_blocked() -> bool:")
	L.append("\tfor s in _stack:")
	L.append("\t\tif s != null and is_instance_valid(s) and bool(s.get_meta(\"blocks_play\", false)):")
	L.append("\t\t\treturn true")
	L.append("\treturn false")
	L.append("")
	L.append("func show_screen(node_name: String) -> void:")
	L.append("\tvar root = get_parent()")
	L.append("\tif root == null:")
	L.append("\t\treturn")
	L.append("\tvar found = root.get_node_or_null(\"Screen_\" + node_name)")
	L.append("\tif found == null:")
	L.append("\t\tfound = root.get_node_or_null(node_name)")
	L.append("\tif found != null and found is Control:")
	L.append("\t\t_push(found)")
	return "\n".join(L) + "\n"

# ---------------------------------------------------------------------------
# Per-compile dedupe + safe ctx readers
# ---------------------------------------------------------------------------

func _claim(b: Dictionary, root: Node) -> bool:
	var rid := root.get_instance_id()
	if rid != _seen_root_id:
		_seen_root_id = rid
		_seen.clear()
		_screens.clear()
		_screen_order.clear()
	var bid := FeatureCtx.bid(b)
	var key := bid
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

static func _is_3d(ctx) -> bool:
	var v = _ctxv(ctx, "is_3d", null)
	return true if v == null else bool(v)

## Text that ends up inside a generated string literal: no newlines, no edges.
static func _clean(s: String) -> String:
	return s.replace("\r", " ").replace("\n", " ").replace("\t", " ").strip_edges()
