extends Node
## theme — UI style presets and screen transitions.
##
## WHY: every game EasyForge generates currently ships the raw default Godot
## look — flat grey buttons, the engine's default font size, hard square
## corners, and an instant ugly CUT when a screen changes. A beginner cannot
## make their game feel polished, and polish is the difference between "a
## thing that runs" and "a game somebody plays".
##
## ONE KIND: kind "style". It does two things, both real:
##   1. STYLE  — builds an actual Godot `Theme` resource (StyleBoxFlat panels
##               and buttons, corner radii, accent border, font sizes) and
##               installs it on a top-level "GameUI" Control so EVERY Control
##               the compiler later adds (HUD, screens, widgets) inherits it.
##   2. MOVE   — adds a reusable `TransitionOverlay` (a ColorRect) that fades
##               or slides, and hooks the EXISTING ScreenManager built by
##               src/features/menu.gd so a screen change plays the transition.
##
## WHERE THE THEME LANDS (verified against the engine, not assumed):
##   The compiler's `root` is a Node2D/Node3D, which cannot own a theme. The
##   HUD the compiler builds is a plain Control added to that root. So this
##   module adds ONE Control named "GameUI" to the root, sets
##   `GameUI.theme = <Theme>`, and Godot's theme INHERITANCE propagates it to
##   every Control descendant — measured in a probe: a Label nested two levels
##   down read font_size 20 and the accent font_color from the root's theme,
##   and a Button picked up its StyleBoxFlat (corner 8, border 2) with the
##   Label's own `.theme` property left null (inheritance, not ownership).
##   The Theme is also registered under the node's "ef_theme" meta and the
##   overlay reads it back from there, so the theme travels with the node.
##
## ONE THEME PER GAME: the first style brick builds it; a second style brick
## RE-THEMES the same resource instead of creating a rival one, so two bricks
## cannot fight and the last one written wins deterministically.
##
## THE OVERLAY AND THE SCREEN MANAGER (no second screen system):
##   The overlay attaches to the existing "ScreenManager" node that menu.gd
##   created (found by name, walked up from the root, plus one level down for
##   a compiled game mounted under a level container — the same lookup menu.gd
##   itself uses). The overlay script binds the manager's `_push`, `_pop` and
##   `_replace` so every screen change plays through it. If menu.gd is NOT in
##   the graph there is no ScreenManager, and the overlay still works as a
##   standalone fade-in on _ready. It never duplicates a screen manager and
##   never owns a screen stack.
##
## PRESETS — all six produce a visibly different theme (different base panel
## and button colours, different accent handling, a different corner-radius
## bias and border weight):
##   clean    light neutral panels, crisp thin borders
##   playful  warm cream panels, thick rounded borders, big type
##   retro    chunky pixel-ish panels, hard 4px corners, heavy borders
##   neon     near-black panels, glowing accent borders, wide radii
##   minimal  no borders at all, tiny corners, flat panels
##   dark     deep slate panels, soft borders, medium radii
##
## NODES CREATED (identical in 2D and 3D — a theme is UI, never Node2D/3D):
##   root
##   ├── GameUI                (Control, PRESET_FULL_RECT, owns the Theme)
##   │   └── TransitionOverlay (ColorRect, PRESET_FULL_RECT, IGNORE, script)
##   ├── HUD                   (the compiler's score HUD, untouched)
##   └── ScreenManager         (menu.gd's manager, re-bound to the overlay)
##
## JUNK SAFETY: an unknown preset or accent falls back to clean/gold, a null
## param falls back to its default, NaN/Inf numbers fall back too, and a
## missing ScreenManager simply means the overlay fades in on its own. A
## style brick with NO params at all still produces a real themed UI.
##
## INTEGRATOR PARAMS (this module only READS them; the integrator adds them to
## BrickRef.KIND and BrickRef.PARAM_SCHEMA):
##   KIND entry:
##     "style": {"label": "Style", "icon": "🎨", "in": [FLOW], "out": []}
##   PARAM_SCHEMA entry:
##     "style":
##       preset            choice [clean, playful, retro, neon, minimal, dark]
##                                   default "clean"
##       accent            choice [gold, red, blue, green, purple, white]
##                                   default "gold"
##       font_size         number 12..48 step 2                 default 20
##       corner_radius     number 0..24 step 2                  default 8
##       transition        choice [fade, slide, none]           default "fade"
##       transition_seconds number 0.05..2.0 step 0.05          default 0.35
##
## DETERMINISM: no randf(), no filesystem, no wall-clock. The same graph always
## compiles to the same theme and the same overlay.

# The global script class cache does not contain FeatureCtx, so the bare
# identifier is NOT in scope in a feature module. Preload it explicitly — the
# established pattern (see src/features/menu.gd, src/features/widgets.gd).
const FeatureCtx = preload("res://src/compiler/feature_ctx.gd")

const UI_NAME := "GameUI"
const OVERLAY_NAME := "TransitionOverlay"
const THEME_META := "ef_theme"
# the manager menu.gd builds; found by name so this module never depends on
# menu.gd being loaded or on a class reference it cannot resolve
const MANAGER_NAME := "ScreenManager"

const PRESETS := ["clean", "playful", "retro", "neon", "minimal", "dark"]
const ACCENTS := ["gold", "red", "blue", "green", "purple", "white"]
const TRANSITIONS := ["fade", "slide", "none"]

# The StyleBox the overlay covers the screen with while a transition plays.
# A fade to this colour reads as a deliberate beat, not a glitch.
const OVERLAY_COLOR := Color(0.02, 0.02, 0.03, 1.0)
# How long the standalone (no-ScreenManager) fade-in on _ready runs.
const FADE_IN_ALPHA := 0.9

const MIN_FONT := 12
const MAX_FONT := 48
const FONT_STEP := 2
const MIN_RADIUS := 0
const MAX_RADIUS := 24
const MIN_SECONDS := 0.05
const MAX_SECONDS := 2.0

# Per-compile state. The registry hands the same brick to us in pass 1 AND
# again in pass 2, so remember what this module already built for the current
# root and let one style brick never become two UI nodes.
var _seen := {}
var _seen_root_id := 0

# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

func register(reg) -> void:
	if reg == null or not reg.has_method("register"):
		push_error("[theme] no feature registry available")
		return
	reg.register("style", _build)
	# A theme must exist before the menus that consume it, so build in pass 1.
	reg.register_pass1("style")

# ---------------------------------------------------------------------------
# Builder
# ---------------------------------------------------------------------------

## "style" brick -> one themed GameUI Control plus a TransitionOverlay.
func _build(b: Dictionary, root: Node, ctx) -> void:
	if root == null or not (b is Dictionary):
		return
	if not _claim(b, root):
		return

	var spec := _spec(b)

	var ui := _find_ui(root)
	var fresh := ui == null
	if fresh:
		ui = Control.new()
		ui.name = UI_NAME
		ui.set_anchors_preset(Control.PRESET_FULL_RECT)
		# IGNORE so a full-screen UI container never eats the game's clicks
		ui.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Build (or rebuild) the Theme and install it. A second style brick in the
	# same graph re-themes the SAME resource: one theme per game, last wins.
	var th := _build_theme(spec)
	ui.theme = th
	ui.set_meta(THEME_META, th)
	ui.set_meta("style_preset", spec["preset"])
	ui.set_meta("style_accent", spec["accent"])
	ui.set_meta("style_transition", spec["transition"])
	ui.set_meta("style_seconds", spec["seconds"])

	if fresh:
		root.add_child(ui)

	# The overlay lives under GameUI so it inherits the theme, and it is built
	# (or re-tuned) on every style brick so transition changes take effect.
	var overlay := _ensure_overlay(ui, spec, fresh)

	# Hook the EXISTING ScreenManager. Never build a second one.
	_hook_manager(root, overlay, spec)

# ---------------------------------------------------------------------------
# The Theme
# ---------------------------------------------------------------------------

## Every user-facing value, validated and clamped, in one place.
func _spec(b: Dictionary) -> Dictionary:
	var preset := FeatureCtx.bstr(b, "preset", "clean").to_lower()
	var accent := FeatureCtx.bstr(b, "accent", "gold").to_lower()
	var transition := FeatureCtx.bstr(b, "transition", "fade").to_lower()

	# font_size: clamp, then snap to the step so the UI shows the same number
	var font_size := _clamp_num(FeatureCtx.bnum(b, "font_size", 20.0),
		float(MIN_FONT), float(MAX_FONT), 20.0)
	font_size = float(MIN_FONT) + roundf((font_size - float(MIN_FONT)) / float(FONT_STEP)) * float(FONT_STEP)
	font_size = _clamp_num(font_size, float(MIN_FONT), float(MAX_FONT), 20.0)

	var radius := _clamp_num(FeatureCtx.bnum(b, "corner_radius", 8.0),
		float(MIN_RADIUS), float(MAX_RADIUS), 8.0)

	var seconds := _clamp_num(FeatureCtx.bnum(b, "transition_seconds", 0.35),
		MIN_SECONDS, MAX_SECONDS, 0.35)

	return {
		"preset": preset if preset in PRESETS else "clean",
		"accent": accent if accent in ACCENTS else "gold",
		"font_size": font_size,
		"radius": radius,
		"transition": transition if transition in TRANSITIONS else "fade",
		"seconds": seconds,
	}

## Compose a real Godot Theme for one style brick. Every preset differs in
## base colours, accent handling, radius bias and border weight, so the six
## choices are visibly different rather than a single look with a tint.
func _build_theme(spec: Dictionary) -> Theme:
	var preset := str(spec["preset"])
	var accent := FeatureCtx.palette_color(str(spec["accent"]), FeatureCtx.palette_color("gold"))
	var base_font := float(spec["font_size"])
	var radius := float(spec["radius"])

	# --- per-preset palette -------------------------------------------------
	# bg        panel fill            surface   raised fill (buttons)
	# text      main label colour      sub       muted secondary text
	# border_w  panel/button border    radius_bias
	#            multiplier on the user's corner_radius  (playful/neon are
	#            rounder than the number typed; retro/minimal stay honest)
	# accent_as_bg  does the accent fill the button instead of just edge it?
	var cfg := _preset_config(preset)

	var bg: Color = cfg["bg"]
	var surface: Color = cfg["surface"]
	var text: Color = cfg["text"]
	var sub: Color = cfg["sub"]
	var border_w: float = float(cfg["border_w"])
	var radius_bias: float = float(cfg["radius_bias"])
	var accent_as_bg: bool = bool(cfg["accent_as_bg"])

	var panel_radius: int = _rad(radius * radius_bias)
	var btn_radius: int = _rad(radius * radius_bias)

	var th := Theme.new()
	# default_font_size is the base every get_theme_font_size() falls back to
	th.default_font_size = int(base_font)

	# --- Panel: the surface every menu and popup sits on --------------------
	var panel := StyleBoxFlat.new()
	panel.bg_color = bg
	if border_w > 0.0:
		panel.border_color = _dim(accent, 0.55)
		panel.set_border_width_all(int(max(border_w, 1.0)))
	else:
		panel.border_color = Color(0, 0, 0, 0)
		panel.set_border_width_all(0)
	panel.set_corner_radius_all(panel_radius)
	panel.content_margin_left = 16.0
	panel.content_margin_right = 16.0
	panel.content_margin_top = 10.0
	panel.content_margin_bottom = 10.0
	th.set_stylebox("panel", "Panel", panel)
	th.set_stylebox("panel", "PanelContainer", panel)

	# --- Button: the control a player actually presses ---------------------
	var btn := StyleBoxFlat.new()
	btn.set_corner_radius_all(btn_radius)
	if accent_as_bg:
		# an accent-filled button needs dark text to stay readable
		btn.bg_color = accent
		btn.border_color = _bright(accent, 0.25)
		btn.set_border_width_all(int(max(border_w * 0.5, 1.0)))
	else:
		btn.bg_color = surface
		btn.border_color = _dim(accent, 0.7)
		btn.set_border_width_all(int(max(border_w, 1.0)))
	btn.content_margin_left = 18.0
	btn.content_margin_right = 18.0
	btn.content_margin_top = 8.0
	btn.content_margin_bottom = 8.0
	th.set_stylebox("normal", "Button", btn)
	th.set_stylebox("hover", "Button", _lift(btn))
	th.set_stylebox("pressed", "Button", _press(btn))
	th.set_stylebox("disabled", "Button", _mute(btn))
	th.set_color("font_color", "Button", _bright(accent, 0.0) if accent_as_bg else text)
	th.set_color("font_hover_color", "Button", _bright(accent, 0.0) if accent_as_bg else _bright(text, 0.15))
	th.set_color("font_pressed_color", "Button", _bright(accent, 0.0) if accent_as_bg else _bright(text, 0.3))
	th.set_color("font_disabled_color", "Button", sub)
	th.set_font_size("font_size", "Button", int(base_font))
	th.set_constant("h_separation", "Button", 6)

	# --- Label: the text a player reads ------------------------------------
	th.set_color("font_color", "Label", text)
	th.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.45))
	th.set_constant("shadow_offset_x", "Label", 1)
	th.set_constant("shadow_offset_y", "Label", 1)
	th.set_font_size("font_size", "Label", int(base_font))

	# --- HSlider: a widget a player drags ----------------------------------
	var grab := StyleBoxFlat.new()
	grab.set_corner_radius_all(int(min(panel_radius, 8)))
	grab.bg_color = accent
	grab.set_border_width_all(0)
	var track := StyleBoxFlat.new()
	track.set_corner_radius_all(int(min(panel_radius, 8)))
	track.bg_color = _dim(surface, 0.35)
	track.set_border_width_all(0)
	th.set_stylebox("slider", "HSlider", track)
	th.set_stylebox("grabber_area", "HSlider", grab)
	th.set_stylebox("grabber_area_highlight", "HSlider", _lift(grab))
	th.set_color("font_color", "HSlider", sub)
	th.set_font_size("font_size", "HSlider", int(base_font) - 2)
	th.set_constant("center_grabber", "HSlider", 1)

	# --- CheckBox / OptionButton: the rest of the widget library -----------
	th.set_color("font_color", "CheckBox", text)
	th.set_color("font_hover_color", "CheckBox", _bright(text, 0.2))
	th.set_font_size("font_size", "CheckBox", int(base_font))
	var cb_box := StyleBoxFlat.new()
	cb_box.set_corner_radius_all(int(min(panel_radius, 6)))
	cb_box.bg_color = surface
	cb_box.border_color = _dim(accent, 0.7)
	cb_box.set_border_width_all(int(max(border_w, 1.0)))
	th.set_stylebox("normal", "CheckBox", cb_box)
	th.set_stylebox("hover", "CheckBox", _lift(cb_box))
	th.set_stylebox("pressed", "CheckBox", grab)
	th.set_stylebox("disabled", "CheckBox", _mute(cb_box))

	th.set_color("font_color", "OptionButton", text)
	th.set_color("font_hover_color", "OptionButton", _bright(text, 0.2))
	th.set_font_size("font_size", "OptionButton", int(base_font))
	th.set_stylebox("normal", "OptionButton", btn)
	th.set_stylebox("hover", "OptionButton", _lift(btn))
	th.set_stylebox("pressed", "OptionButton", _press(btn))
	var popup := StyleBoxFlat.new()
	popup.set_corner_radius_all(panel_radius)
	popup.bg_color = bg
	popup.border_color = _dim(accent, 0.55)
	popup.set_border_width_all(int(max(border_w, 1.0)))
	popup.content_margin_left = 8.0
	popup.content_margin_right = 8.0
	th.set_stylebox("panel", "PopupMenu", popup)

	# --- containers ---------------------------------------------------------
	th.set_constant("separation", "VBoxContainer", 10)
	th.set_constant("separation", "HBoxContainer", 10)
	th.set_constant("separation", "GridContainer", 10)

	# --- the HUD the compiler builds (plain Control + Label) ---------------
	th.set_stylebox("normal", "HUD", panel)
	th.set_color("font_color", "HUD", text)

	return th

## The per-preset look. Deterministic table — no randf, no filesystem.
func _preset_config(preset: String) -> Dictionary:
	match preset:
		"playful":
			return {
				"bg": Color(0.99, 0.94, 0.85), "surface": Color(1.0, 1.0, 1.0),
				"text": Color(0.22, 0.16, 0.12), "sub": Color(0.45, 0.38, 0.32),
				"border_w": 3.0, "radius_bias": 1.5, "accent_as_bg": true,
			}
		"retro":
			return {
				"bg": Color(0.13, 0.14, 0.19), "surface": Color(0.22, 0.24, 0.31),
				"text": Color(0.93, 0.93, 0.86), "sub": Color(0.62, 0.62, 0.55),
				"border_w": 4.0, "radius_bias": 0.5, "accent_as_bg": false,
			}
		"neon":
			return {
				"bg": Color(0.04, 0.04, 0.07), "surface": Color(0.08, 0.08, 0.13),
				"text": Color(0.90, 0.95, 1.0), "sub": Color(0.55, 0.62, 0.72),
				"border_w": 3.0, "radius_bias": 1.25, "accent_as_bg": false,
			}
		"minimal":
			return {
				"bg": Color(0.97, 0.97, 0.97), "surface": Color(1.0, 1.0, 1.0),
				"text": Color(0.12, 0.12, 0.12), "sub": Color(0.55, 0.55, 0.55),
				"border_w": 0.0, "radius_bias": 0.35, "accent_as_bg": false,
			}
		"dark":
			return {
				"bg": Color(0.09, 0.10, 0.13), "surface": Color(0.16, 0.17, 0.21),
				"text": Color(0.92, 0.93, 0.96), "sub": Color(0.60, 0.62, 0.68),
				"border_w": 2.0, "radius_bias": 1.0, "accent_as_bg": false,
			}
	return {   # "clean" — the default
		"bg": Color(0.94, 0.95, 0.97), "surface": Color(1.0, 1.0, 1.0),
		"text": Color(0.14, 0.15, 0.18), "sub": Color(0.45, 0.47, 0.52),
		"border_w": 2.0, "radius_bias": 1.0, "accent_as_bg": false,
	}

# --- StyleBox derivations: each is a fresh resource, never a shared mutate --

func _lift(sb: StyleBoxFlat) -> StyleBoxFlat:
	var s := sb.duplicate()
	s.bg_color = _bright(s.bg_color, 0.12)
	s.border_color = _bright(s.border_color, 0.2)
	return s

func _press(sb: StyleBoxFlat) -> StyleBoxFlat:
	var s := sb.duplicate()
	s.bg_color = _dim(s.bg_color, 0.82)
	return s

func _mute(sb: StyleBoxFlat) -> StyleBoxFlat:
	var s := sb.duplicate()
	s.bg_color = _dim(s.bg_color, 0.6)
	s.border_color = _dim(s.border_color, 0.5)
	return s

func _bright(c: Color, amt: float) -> Color:
	return Color(clampf(c.r + amt, 0.0, 1.0), clampf(c.g + amt, 0.0, 1.0),
		clampf(c.b + amt, 0.0, 1.0), clampf(c.a, 0.0, 1.0))

func _dim(c: Color, amt: float) -> Color:
	return Color(clampf(c.r * amt, 0.0, 1.0), clampf(c.g * amt, 0.0, 1.0),
		clampf(c.b * amt, 0.0, 1.0), clampf(c.a, 0.0, 1.0))

## A corner radius in whole pixels, clamped to the schema range. `rad` is
## float so a radius bias can scale it before it becomes an int.
func _rad(v: float) -> int:
	return int(clampf(roundf(_clamp_num(v, float(MIN_RADIUS), float(MAX_RADIUS), 0.0)),
		float(MIN_RADIUS), float(MAX_RADIUS)))

# ---------------------------------------------------------------------------
# The transition overlay
# ---------------------------------------------------------------------------

## Create (or re-tune) the TransitionOverlay ColorRect under GameUI. Returns
## the node so the manager hook can bind to it.
func _ensure_overlay(ui: Control, spec: Dictionary, fresh_parent: bool) -> ColorRect:
	var existing = ui.get_node_or_null(OVERLAY_NAME)
	var ov: ColorRect = null
	if existing != null and existing is ColorRect:
		ov = existing
		# a second style brick must not leave a stale script bound twice
		var st = ov.get_script()
		if st != null:
			ov.set_script(null)
	else:
		ov = ColorRect.new()
		ov.name = OVERLAY_NAME
		ov.set_anchors_preset(Control.PRESET_FULL_RECT)
		ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ov.color = OVERLAY_COLOR
		ov.visible = false
		ui.add_child(ov)

	var mode := str(spec["transition"])
	ov.set_meta("transition", mode)
	ov.set_meta("seconds", float(spec["seconds"]))

	if mode == "none":
		# an explicit "no transition" is honoured: the overlay stays hidden and
		# inert rather than fading on every screen change
		ov.visible = false
		ov.set_script(null)
		return ov

	# Attach the generated script. On a fresh parent the overlay has not
	# entered the tree yet, so _ready() still runs when it does; on an
	# existing parent the previous script is detached above and re-attaching
	# re-enters it, which re-binds the manager lookup for the new settings.
	var err := FeatureCtx.attach_script(ov, _overlay_source(spec))
	if err != OK:
		push_error("[theme] transition overlay script failed to compile; transitions disabled")
	return ov

## The overlay's own script. It is emitted as text so the escape-hatch code
## view shows the user exactly what their transition does, and it is where
## the manager signals are bound — never on the compiler-side node.
func _overlay_source(spec: Dictionary) -> String:
	var L: Array[String] = []
	var secs := float(spec["seconds"])
	var mode := str(spec["transition"])
	L.append("extends ColorRect")
	L.append("# Generated by EasyForge from a Style brick (kind: style).")
	L.append("#")
	L.append("# This is the screen transition: a full-screen ColorRect that fades")
	L.append("# or slides over the game while a screen changes. It hooks the")
	L.append("# ScreenManager that the Screen bricks build, so a menu swap plays")
	L.append("# through here. With no ScreenManager in the graph it still works:")
	L.append("# it fades itself in once on _ready, which is a real transition into")
	L.append("# the game rather than a hard cut.")
	L.append("#")
	L.append("# WHY the signals are bound HERE and never at compile time: the")
	L.append("# compiler node that built this overlay does not exist in the")
	L.append("# exported game, so a compile-time connection would dangle and the")
	L.append("# transition would never play.")
	L.append("const _MODE := %s" % _lit(mode))
	L.append("const _SECONDS := %f" % secs)
	L.append("const _FADE_ALPHA := %f" % FADE_IN_ALPHA)
	L.append("var _manager = null")
	L.append("var _busy := false")
	L.append("")
	L.append("func _ready() -> void:")
	L.append("\tmouse_filter = Control.MOUSE_FILTER_IGNORE")
	L.append("\t_manager = _find_manager()")
	L.append("\t_bind_manager()")
	L.append("\tif _MODE == \"fade\":")
	L.append("\t\t_fade_in()")
	L.append("\telif _MODE == \"slide\":")
	L.append("\t\t_slide_in()")
	L.append("")
	L.append("## Walk up from this overlay to the scene root looking for the")
	L.append("## ScreenManager, then one level down (a compiled game can be")
	L.append("## mounted under a level container). Same lookup menu.gd uses.")
	L.append("func _find_manager():")
	L.append("\tvar start = self")
	L.append("\twhile start != null:")
	L.append("\t\tvar root = start")
	L.append("\t\twhile root != null and root.get_parent() != null:")
	L.append("\t\t\troot = root.get_parent()")
	L.append("\t\tif root != null:")
	L.append("\t\t\tvar direct = root.get_node_or_null(\"%s\")" % MANAGER_NAME)
	L.append("\t\t\tif direct != null:")
	L.append("\t\t\t\treturn direct")
	L.append("\t\t\tfor child in root.get_children():")
	L.append("\t\t\t\tif child is Node:")
	L.append("\t\t\t\t\tvar inner = child.get_node_or_null(\"%s\")" % MANAGER_NAME)
	L.append("\t\t\t\t\tif inner != null:")
	L.append("\t\t\t\t\t\treturn inner")
	L.append("\t\tstart = start.get_parent()")
	L.append("\treturn null")
	L.append("")
	L.append("## Bind the overlay to the ScreenManager. The manager keeps owning")
	L.append("## the screen stack; this overlay only observes a change and covers")
	L.append("## the screen while it happens. The manager's stack primitives are")
	L.append("## methods, not signals, so the overlay watches screen_count() —")
	L.append("## which is why this module never duplicates a screen manager.")
	L.append("func _bind_manager() -> void:")
	L.append("	if _manager == null or not is_instance_valid(_manager):")
	L.append("		return")
	L.append("	if not _manager.has_method(\"screen_count\"):")
	L.append("		return")
	L.append("	_watch()")
	L.append("")
	L.append("## Poll the stack depth. Frame-cheap, and it needs no change to the")
	L.append("## manager's contract — which menu.gd owns and this module must not")
	L.append("## edit.")
	L.append("var _last_count := -1")
	L.append("func _watch() -> void:")
	L.append("	await get_tree().process_frame")
	L.append("	while is_inside_tree():")
	L.append("		if _manager == null or not is_instance_valid(_manager):")
	L.append("			return")
	L.append("		if _manager.has_method(\"screen_count\"):")
	L.append("			var c: int = _manager.call(\"screen_count\")")
	L.append("			if c != _last_count:")
	L.append("				_last_count = c")
	L.append("				_play()")
	L.append("		await get_tree().process_frame")
	L.append("")
	# --- the two transitions ------------------------------------------------
	L.append("## Cover the screen, then reveal it again. A fade is two tweens:")
	L.append("## out to the overlay colour, back in to transparent.")
	L.append("func _fade_in() -> void:")
	L.append("\tif _busy:")
	L.append("\t\treturn")
	L.append("\t_busy = true")
	L.append("\tvisible = true")
	L.append("\tvar c := color")
	L.append("\tc.a = _FADE_ALPHA")
	L.append("\tcolor = c")
	L.append("\tvar tw := create_tween()")
	L.append("\ttw.tween_property(self, \"color:a\", 0.0, _SECONDS)")
	L.append("\ttw.finished.connect(_on_faded)")
	L.append("")
	L.append("func _on_faded() -> void:")
	L.append("\tif is_instance_valid(self):")
	L.append("\t\tvisible = false")
	L.append("\t_busy = false")
	L.append("")
	L.append("## Slide in from the side. The overlay sweeps across and back out,")
	L.append("## which reads as a wipe rather than a fade.")
	L.append("func _slide_in() -> void:")
	L.append("\tif _busy:")
	L.append("\t\treturn")
	L.append("\t_busy = true")
	L.append("\tvisible = true")
	L.append("\tvar half := size.y")
	L.append("\tif half <= 0.0:")
	L.append("\t\thalf = 360.0")
	L.append("\tposition = Vector2(0.0, -half)")
	L.append("\tvar tw := create_tween()")
	L.append("\ttw.tween_property(self, \"position:y\", 0.0, _SECONDS * 0.5)")
	L.append("\ttw.tween_property(self, \"position:y\", half, _SECONDS * 0.5)")
	L.append("\ttw.finished.connect(_on_slid)")
	L.append("")
	L.append("func _on_slid() -> void:")
	L.append("\tif is_instance_valid(self):")
	L.append("\t\tvisible = false")
	L.append("\t\tposition = Vector2.ZERO")
	L.append("\t_busy = false")
	L.append("")
	L.append("## One transition, whichever mode the user picked.")
	L.append("func _play() -> void:")
	L.append("\tif _MODE == \"fade\":")
	L.append("\t\t_fade_in()")
	L.append("\telif _MODE == \"slide\":")
	L.append("\t\t_slide_in()")
	return "\n".join(L) + "\n"

## Bind the overlay to the existing ScreenManager. If there is none, the
## overlay already works standalone (it fades in on _ready), so this is a
## no-op rather than an error — a style brick must never require a menu.
func _hook_manager(root: Node, overlay: ColorRect, spec: Dictionary) -> void:
	if overlay == null or not is_instance_valid(overlay):
		return
	var mgr = _find_manager(root)
	if mgr == null:
		return
	# The manager's stack primitives are methods, not signals. Rather than
	# rewrite the manager's contract, the overlay watches screen_count() (see
	# _overlay_source). Here we only record that a manager exists so the
	# generated code and the inspector agree about what is wired.
	overlay.set_meta("manager", mgr)

## Find the ScreenManager exactly the way menu.gd does: up to the scene root,
## then one level down for a mounted game. Never creates one.
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
	for child in root.get_children():
		var n = child.get_node_or_null(MANAGER_NAME) if child is Node else null
		if n != null:
			return n
	return null

## The themed GameUI container, if a style brick already made one.
func _find_ui(root: Node) -> Control:
	if root == null:
		return null
	var direct = root.get_node_or_null(UI_NAME)
	if direct != null and direct is Control:
		return direct
	for child in root.get_children():
		var n = child.get_node_or_null(UI_NAME) if child is Node else null
		if n != null and n is Control:
			return n
	return null

# ---------------------------------------------------------------------------
# Per-compile dedupe + shared helpers
# ---------------------------------------------------------------------------

func _claim(b: Dictionary, root: Node) -> bool:
	var rid := root.get_instance_id()
	if rid != _seen_root_id:
		_seen_root_id = rid
		_seen.clear()
	var bid := FeatureCtx.bid(b)
	var key := bid
	if key.is_empty():
		key = "anon_%d" % _seen.size()
	if _seen.has(key):
		return false
	_seen[key] = true
	return true

func _clamp_num(v: float, lo: float, hi: float, fallback: float) -> float:
	if v != v or v == INF or v == -INF:
		return fallback
	return clampf(v, lo, hi)

## Quote a string for a generated GDScript string literal.
static func _lit(s: String) -> String:
	var escaped := s.replace("\\", "\\").replace("\"", "\"")
	return "\"" + escaped + "\""
