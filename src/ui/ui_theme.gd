extends RefCounted
## UiTheme — the product's look in one place: colour tokens, spacing, and the
## Theme every panel and dialog is built from.
##
## Before this file the palette and the 110-line theme lived inside main.gd, so
## any dialog that wanted to look like the app had to reach back into main for
## `editor_root.theme` — and the ones that did not looked wrong. Now the Manual,
## the recipe picker, the project gallery and Settings all call build().
##
## `scale` (from Settings) multiplies the theme font sizes. The per-control
## overrides in the UI go through fs() so a person who sets "Text size: Large"
## actually gets large text everywhere instead of a half-scaled window.

class_name UiTheme

# ---------------------------------------------------------------------------
# Design tokens — one dark palette for the whole product.
# ---------------------------------------------------------------------------
const C_BG := Color("#12141a")        # window background
const C_PANEL := Color("#1b1e27")     # side panels / dialogs
const C_CARD := Color("#232733")      # graph nodes, inputs
const C_CARD_HI := Color("#2b3040")   # hover / focused surfaces
const C_ACCENT := Color("#6c5ce7")    # brand purple — primary actions
const C_ACCENT_2 := Color("#00cec9")  # teal — secondary accent
const C_TEXT := Color("#e8ecf4")      # primary text
const C_MUTED := Color("#8b93a7")     # helper text
const C_BORDER := Color("#2e3444")    # 1px borders
const C_GOOD := Color("#00d68f")      # success / status ok
const C_BAD := Color("#ff6b6b")       # error / status fail
const C_WARN := Color("#ffb340")      # a warning: not broken yet, worth a look
const C_PORT_IN := Color("#4fc3f7")   # input port
const C_PORT_OUT := Color("#ffd54f")  # output port

## Left rail width: the layout lock in the smoke test demands the rail stays
## under 20% of a 1600px window, and this cap is what makes that hold.
const RAIL_MAX_W := 260.0
const RAIL_MIN_W := 210.0

## One rounded flat box, the shape every surface in the app uses.
static func flat(bg: Color, border: Color = C_BORDER, radius: int = 8,
		border_px: int = 1, pad_x: int = 12, pad_y: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_px)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_x; sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y; sb.content_margin_bottom = pad_y
	return sb

## A font size for a control, scaled by the user's text-size setting.
static func fs(px: int, scale: float = 1.0) -> int:
	return int(round(float(px) * clampf(scale, 0.8, 1.6)))

## Build the app theme. `scale` is the text-size setting from Settings.
static func build(scale: float = 1.0) -> Theme:
	var th := Theme.new()
	var base := fs(14, scale)

	var panel_sb := flat(C_PANEL, C_BORDER, 10, 1, 14, 12)
	var card_sb := flat(C_CARD, C_BORDER, 10, 1, 12, 10)
	var input_sb := flat(C_CARD, C_BORDER, 8, 1, 10, 8)
	var input_focus_sb := flat(C_CARD, C_ACCENT, 8, 2, 10, 8)
	var btn_normal := flat(C_CARD, C_BORDER, 8, 1, 14, 9)
	var btn_hover := flat(C_CARD_HI, C_ACCENT_2, 8, 1, 14, 9)
	var btn_pressed := flat(C_ACCENT, C_ACCENT, 8, 1, 14, 9)
	var btn_disabled := flat(C_CARD, C_BORDER, 8, 1, 14, 9)
	var btn_primary := flat(C_ACCENT, C_ACCENT, 8, 0, 16, 10)
	var btn_primary_hover := flat(Color("#7d6ff0"), Color("#7d6ff0"), 8, 0, 16, 10)
	var panel_dark := flat(C_BG, C_BORDER, 10, 1, 12, 10)

	# Panels and containers
	th.set_stylebox("panel", "Panel", panel_sb)
	th.set_stylebox("panel", "PanelContainer", panel_sb)
	th.set_stylebox("panel", "ScrollContainer", panel_sb)

	# Buttons — disabled keeps its own muted font so a dead button reads as dead
	# instead of looking clickable (a beginner cannot tell otherwise).
	th.set_stylebox("normal", "Button", btn_normal)
	th.set_stylebox("hover", "Button", btn_hover)
	th.set_stylebox("pressed", "Button", btn_pressed)
	th.set_stylebox("disabled", "Button", btn_disabled)
	th.set_stylebox("focus", "Button", btn_hover)
	th.set_color("font_color", "Button", C_TEXT)
	th.set_color("font_hover_color", "Button", C_TEXT)
	th.set_color("font_pressed_color", "Button", Color("#ffffff"))
	th.set_color("font_disabled_color", "Button", C_MUTED)
	th.set_font_size("font_size", "Button", base + 1)
	th.set_constant("h_separation", "Button", 8)

	# Text inputs
	for kind in ["LineEdit", "TextEdit", "SpinBox", "RichTextLabel"]:
		th.set_stylebox("normal", kind, input_sb)
		th.set_stylebox("focus", kind, input_focus_sb)
		th.set_stylebox("read_only", kind, input_sb)
		th.set_color("font_color", kind, C_TEXT)
		th.set_color("font_placeholder_color", kind, C_MUTED)
		th.set_color("caret_color", kind, C_ACCENT_2)
		th.set_color("selection_color", kind, C_ACCENT)
		th.set_font_size("font_size", kind, base)
	# SpinBox arrows need the box theme too, or they float on the window colour
	th.set_stylebox("getter", "SpinBox", input_sb)
	th.set_stylebox("getter_focus", "SpinBox", input_focus_sb)

	# Dropdowns
	th.set_stylebox("normal", "OptionButton", btn_normal)
	th.set_stylebox("hover", "OptionButton", btn_hover)
	th.set_stylebox("pressed", "OptionButton", btn_pressed)
	th.set_stylebox("focus", "OptionButton", btn_hover)
	th.set_color("font_color", "OptionButton", C_TEXT)
	th.set_font_size("font_size", "OptionButton", base)

	# Labels
	th.set_color("font_color", "Label", C_TEXT)
	th.set_font_size("font_size", "Label", base)

	# Graph canvas
	var ge_sb := StyleBoxFlat.new()
	ge_sb.bg_color = C_BG
	th.set_stylebox("panel", "GraphEdit", ge_sb)
	th.set_color("title_color", "GraphNode", C_TEXT)
	th.set_font_size("title_font_size", "GraphNode", fs(15, scale))

	# Dialogs and menus
	th.set_stylebox("panel", "AcceptDialog", panel_sb)
	th.set_stylebox("panel", "PopupMenu", panel_dark)
	th.set_color("title_color", "AcceptDialog", C_TEXT)
	th.set_color("font_color", "PopupMenu", C_TEXT)

	# Tree (the project list, the brick reference)
	th.set_color("font_color", "Tree", C_TEXT)
	th.set_stylebox("selected", "Tree", btn_pressed)

	# Tabs (the Manual)
	th.set_color("font_color", "TabContainer", C_TEXT)
	th.set_color("font_selected_color", "TabContainer", C_ACCENT_2)
	th.set_font_size("font_size", "TabContainer", base)

	# Scrollbars: the old grabber (#2b3040 on #1b1e27) was invisible in practice,
	# so a list that had more content below looked like a list that had ended.
	# Visible grabbers plus SCROLL_MODE_SHOW_ALWAYS (set on the scrolls) are what
	# tell a beginner there is more to see.
	var grab := flat(Color("#5d6880"), Color("#7b87a3"), 6, 1, 0, 0)
	var grab_hi := flat(C_ACCENT_2, C_ACCENT_2, 6, 1, 0, 0)
	for who in ["HScrollBar", "VScrollBar"]:
		th.set_stylebox("scroll", who, flat(Color("#141720"), C_BORDER, 6, 1, 0, 0))
		th.set_stylebox("grabber", who, grab)
		th.set_stylebox("grabber_highlight", who, grab_hi)
		th.set_stylebox("grabber_pressed", who, grab_hi)
		th.set_constant("minimum_width", who, 12)
		th.set_constant("center_grabber", who, 1)
		th.set_color("arrow_color", who, C_MUTED)

	# A primary button is a style the caller asks for, not a name it guesses.
	th.set_stylebox("normal", "PrimaryButton", btn_primary)
	th.set_stylebox("hover", "PrimaryButton", btn_primary_hover)
	th.set_stylebox("pressed", "PrimaryButton", btn_primary)
	th.set_stylebox("focus", "PrimaryButton", btn_primary_hover)
	th.set_color("font_color", "PrimaryButton", Color("#ffffff"))
	th.set_color("font_hover_color", "PrimaryButton", Color("#ffffff"))
	th.set_font_size("font_size", "PrimaryButton", base + 1)
	return th

## Make a button look like the app's primary action. Used by the buttons that
## start something (Make my game, Play, Add these bricks).
static func paint_primary(btn: Button) -> void:
	btn.add_theme_stylebox_override("normal", flat(C_ACCENT, C_ACCENT, 8, 0, 16, 10))
	btn.add_theme_stylebox_override("hover", flat(Color("#7d6ff0"), Color("#7d6ff0"), 8, 0, 16, 10))
	btn.add_theme_stylebox_override("pressed", flat(C_ACCENT, C_ACCENT, 8, 0, 16, 10))
	btn.add_theme_stylebox_override("focus", flat(Color("#7d6ff0"), C_ACCENT_2, 8, 2, 16, 10))
	btn.add_theme_color_override("font_color", Color("#ffffff"))
	btn.add_theme_color_override("font_hover_color", Color("#ffffff"))

## Make a button look destructive (Stop, Delete).
static func paint_danger(btn: Button) -> void:
	btn.add_theme_stylebox_override("normal", flat(C_BAD, C_BAD, 8, 0, 18, 10))
	btn.add_theme_stylebox_override("hover", flat(Color("#ff8585"), Color("#ff8585"), 8, 0, 18, 10))
	btn.add_theme_color_override("font_color", Color("#ffffff"))
