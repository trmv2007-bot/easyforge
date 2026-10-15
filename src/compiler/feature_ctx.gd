class_name FeatureCtx
## The compile context every registered feature builder receives. Bundles the
## helpers a builder needs so feature files never reach back into Compiler
## internals (which is what would force them to edit compiler.gd).
##
## Built by Compiler.compile_graph() and passed through FeatureRegistry.build().

var compiler            # the Compiler autoload (for its private static helpers)
var root: Node          # the scene root being built
var entities: Dictionary   # brick_id -> Node
var player: Node        # the player node, or null
var is_3d: bool = true
var graph               # the BrickGraph (for _outgoing_targets style lookups)
var controls: Dictionary   # player key bindings from the Spawn brick

# --- param/vector helpers mirrored from Compiler (kept in sync by design) ---

static func params(b: Dictionary) -> Dictionary:
	var v = b.get("params")
	return v if v is Dictionary else {}

static func num(d: Dictionary, key: String, fallback: float) -> float:
	var x = d.get(key)
	if x is float or x is int:
		return float(x)
	if x is String and str(x).is_valid_float():
		return float(x)
	return fallback

static func bnum(b: Dictionary, key: String, fallback: float) -> float:
	return num(params(b), key, fallback)

static func bstr(b: Dictionary, key: String, fallback: String) -> String:
	var v = params(b).get(key)
	if v == null:
		return fallback
	var s := str(v)
	return s if not s.is_empty() else fallback

static func bbool(b: Dictionary, key: String, fallback: bool) -> bool:
	var v = params(b).get(key)
	if v == null:
		return fallback
	if v is bool:
		return v
	if v is float or v is int:
		return v != 0
	if v is String:
		return str(v).to_lower() in ["true", "1", "yes"]
	return fallback

static func bid(b: Dictionary) -> String:
	var i = b.get("id")
	return str(i) if i != null else ""

## A solid color tile/sprite texture built in memory (no asset files).
static func solid_texture(w: int, h: int, col: Color) -> ImageTexture:
	var img := Image.create(max(w, 1), max(h, 1), false, Image.FORMAT_RGBA8)
	img.fill(col)
	return ImageTexture.create_from_image(img)

## Map a key-name choice ("A", "Space", "E", ...) to a Godot KEY_* int. Shared
## so every feature module resolves key names identically.
static func keycode(name) -> int:
	var n := str(name)
	match n:
		"A": return KEY_A
		"B": return KEY_B
		"C": return KEY_C
		"D": return KEY_D
		"E": return KEY_E
		"F": return KEY_F
		"G": return KEY_G
		"H": return KEY_H
		"I": return KEY_I
		"J": return KEY_J
		"K": return KEY_K
		"L": return KEY_L
		"M": return KEY_M
		"N": return KEY_N
		"O": return KEY_O
		"P": return KEY_P
		"Q": return KEY_Q
		"R": return KEY_R
		"S": return KEY_S
		"T": return KEY_T
		"U": return KEY_U
		"V": return KEY_V
		"W": return KEY_W
		"X": return KEY_X
		"Y": return KEY_Y
		"Z": return KEY_Z
		"Space": return KEY_SPACE
		"Enter": return KEY_ENTER
		"Shift": return KEY_SHIFT
		"Ctrl": return KEY_CTRL
		"Tab": return KEY_TAB
		"Left": return KEY_LEFT
		"Right": return KEY_RIGHT
		"Up": return KEY_UP
		"Down": return KEY_DOWN
		"Escape": return KEY_ESCAPE
		# F-keys: save/load advertise F5 and F9, but with no arm here they fell
		# through to KEY_A, so the save ran on the movement key instead
		"F1": return KEY_F1
		"F2": return KEY_F2
		"F3": return KEY_F3
		"F4": return KEY_F4
		"F5": return KEY_F5
		"F6": return KEY_F6
		"F7": return KEY_F7
		"F8": return KEY_F8
		"F9": return KEY_F9
		"F10": return KEY_F10
		"F11": return KEY_F11
		"F12": return KEY_F12
	# Unknown name still falls back to A: every caller compares this against a
	# real press, and a -1 would make the feature silently never fire.
	return KEY_A

## Compile + attach a generated script to a node. Returns the reload result so
## callers can report failures uniformly. Never throws.
static func attach_script(node: Node, source: String) -> int:
	var s := GDScript.new()
	s.source_code = source
	var err := s.reload()
	if err == OK:
		node.set_script(s)
	else:
		push_error("[FeatureCtx] generated script failed to compile:\n" + source)
	return err

## A named color from our shared palette (used by presets so all features
## agree on what "red" or "gold" means).
static func palette_color(name: String, fallback: Color = Color("#ffffff")) -> Color:
	match str(name).to_lower():
		"red": return Color("#ff5252")
		"blue": return Color("#4fc3f7")
		"green": return Color("#69f0ae")
		"gold": return Color("#ffd54f")
		"white": return Color("#ffffff")
		"black": return Color("#111111")
		"purple": return Color("#b388ff")
		"orange": return Color("#ffab40")
		"pink": return Color("#ff8fab")
		"cyan": return Color("#84ffff")
		"gray", "grey": return Color("#9e9e9e")
	return fallback
