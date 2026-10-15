extends Node
## collision — the Collider brick: declarative collision layers and masks.
##
## WHY: "bullets hit enemies but not other bullets", "coins only react to the
## player", "no friendly fire" are the first gameplay rules every beginner
## wants, and today they need logic bricks wired together by hand. This brick
## turns a friendly group name into a real Godot collision_layer /
## collision_mask bitmask, so the rule is declarative and the compiled output
## is deterministic integers.
##
## LAYER BITS (each layer is a single bit; masks are ORs of these):
##   world = 1    player = 2    enemy = 4     pickup = 8
##   hazard = 16  bullet = 32   decor = 64
## Reuse them from any other module via the static helpers on the loaded
## script (no class_name, so callers use `load("res://src/features/collision.gd")`):
##   Collision.bit_for("enemy")            -> 4
##   Collision.mask_for("player,bullet")   -> 34
## Both are static and robust: unknown names contribute bit 0, never a crash.
##
## DEFAULT MASK per layer (used when `collides_with` is empty):
##   world  -> everything except decor      (1+2+4+8+16+32 = 63)
##   player -> world, enemy, pickup, hazard (1+4+8+16     = 29)
##   enemy  -> world, player, bullet        (1+2+32        = 35)
##   pickup -> player                       (2)
##   hazard -> player                       (2)
##   bullet -> enemy, world                 (1+4           = 5)
##   decor  -> nothing                      (0)
##
## PARAMS THE INTEGRATOR ADDS TO brick.gd (kind "collider"):
##   "layer":         {"type": "choice", "label": "Layer",
##                     "options": ["world", "player", "enemy", "pickup", "hazard", "bullet", "decor"],
##                     "default": "world"},
##   "collides_with": {"type": "text", "label": "Collides with", "default": ""},
##                    # comma-separated group names; empty = the default pairing above
##   "solid":         {"type": "bool", "label": "Solid", "default": true},
##                    # false = still built as a real body; a pure trigger should
##                    # use the trigger feature instead
##   "size":          {"type": "number", "label": "Size", "min": 0.5, "max": 40.0, "step": 0.5, "default": 4.0},
##   "shape":         {"type": "choice", "label": "Shape", "options": ["box", "sphere", "capsule"], "default": "box"},
##   "position_y":    {"type": "number", "label": "Height", "min": 0.0, "max": 20.0, "step": 0.5, "default": 1.0},
## An optional "position" array param overrides placement like every other
## feature (3D [x, y, z] -> default [0, position_y, 0]; 2D [x, y] ->
## default [240, 260]). In 2D `size` is scaled x16 px/unit (default 4.0 -> 64 px).

const LOG_PREFIX := "[collision] "

# The compile-context helpers live in a global class (class_name FeatureCtx)
# so every feature module can call them statically. Do not add a class_name to
# this file: the integrator registers it by path in features.gd.

# Friendly group name -> single collision bit. The integrator and other
# feature modules should read these constants rather than hardcoding numbers.
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_ENEMY := 4
const LAYER_PICKUP := 8
const LAYER_HAZARD := 16
const LAYER_BULLET := 32
const LAYER_DECOR := 64

# The compile-context helpers live in feature_ctx.gd. Resolve it by path (no
# preload/global-class name) so the module parses in every load order.
const _CTX_PATH := "res://src/compiler/feature_ctx.gd"
var _ctx_ref  # cached GDScript for FeatureCtx, loaded on first build

func _ctx():
	if _ctx_ref == null:
		_ctx_ref = load(_CTX_PATH)
	return _ctx_ref

const LAYER_NAMES: Array[String] = [
	"world", "player", "enemy", "pickup", "hazard", "bullet", "decor",
]

const LAYER_BITS := {
	"world": LAYER_WORLD,
	"player": LAYER_PLAYER,
	"enemy": LAYER_ENEMY,
	"pickup": LAYER_PICKUP,
	"hazard": LAYER_HAZARD,
	"bullet": LAYER_BULLET,
	"decor": LAYER_DECOR,
}


func register(reg) -> void:
	reg.register("collider", _build)


func _build(b: Dictionary, root: Node, ctx) -> void:
	if root == null:
		return
	var FC = _ctx()   # the FeatureCtx helpers (never null in a real compile)
	var p = FC.params(b)
	var is_3d := _is_3d(ctx)

	# --- params: every read is safe; garbage degrades to the world default ---
	var layer := str(FC.bstr(b, "layer", "world")).strip_edges().to_lower()
	if bit_for(layer) == 0:
		layer = "world"  # unknown name -> the default layer, never a dead brick
	var csv := str(FC.bstr(b, "collides_with", "")).strip_edges()
	var mask := default_mask_for(layer) if csv.is_empty() else mask_for(csv)
	var solid := bool(FC.bbool(b, "solid", true))
	var size := clampf(float(FC.bnum(b, "size", 4.0)), 0.5, 40.0)
	var shape := str(FC.bstr(b, "shape", "box")).strip_edges().to_lower()
	var pos_y := clampf(float(FC.bnum(b, "position_y", 1.0)), 0.0, 20.0)

	var body: Node
	if is_3d:
		body = _build_3d(shape, size, layer, mask, _vec3(p.get("position", null), Vector3(0.0, pos_y, 0.0)))
	else:
		body = _build_2d(shape, size, layer, mask, _vec2(p.get("position", null), Vector2(240.0, 260.0)))

	if body == null:
		return
	body.set_meta("ef_layer", layer)
	body.set_meta("ef_solid", solid)
	if not solid:
		# NOTE: solid=false still compiles to a real physics body (a collider
		# that is simply unreachable by masks is the same as invisible). A pure
		# trigger volume with no physics response should use the trigger
		# feature instead — this brick never silently skips itself.
		push_warning(LOG_PREFIX + "solid=false still builds a real body; use the trigger feature for a pure trigger")

	# let sibling features find this body by brick id
	if ctx is Dictionary:
		var entities = ctx.get("entities")
		if entities is Dictionary:
			var id := str(FC.bid(b))
			if not id.is_empty():
				entities[id] = body
	root.add_child(body)


# ---------------------------------------------------------------------------
# Node builders
# ---------------------------------------------------------------------------

static func _build_3d(shape: String, size: float, layer: String, mask: int, pos: Vector3) -> Node:
	var body := StaticBody3D.new()
	body.name = "Collider"
	var col := CollisionShape3D.new()
	col.name = "Shape"
	col.shape = _shape_3d(shape, size)
	body.add_child(col)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = _mesh_3d(shape, size)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color_for(layer)
	mesh.material_override = mat
	body.add_child(mesh)
	body.collision_layer = bit_for(layer)
	body.collision_mask = mask
	body.position = pos
	return body


static func _build_2d(shape: String, size: float, layer: String, mask: int, pos: Vector2) -> Node:
	var body := StaticBody2D.new()
	body.name = "Collider"
	var px := clampf(size * 16.0, 8.0, 640.0)  # 2D is pixel space: 4.0 -> 64 px
	var col := CollisionShape2D.new()
	col.name = "Shape"
	col.shape = _shape_2d(shape, px)
	body.add_child(col)
	var sprite := Sprite2D.new()
	sprite.name = "Mesh"
	sprite.texture = _sprite_2d(shape, px, color_for(layer))
	body.add_child(sprite)
	body.collision_layer = bit_for(layer)
	body.collision_mask = mask
	body.position = pos
	return body


# ---------------------------------------------------------------------------
# Shapes and visuals (all Godot primitives + procedural color, no assets)
# ---------------------------------------------------------------------------

static func _shape_3d(kind: String, size: float) -> Shape3D:
	match kind:
		"sphere":
			var s := SphereShape3D.new()
			s.radius = maxf(size * 0.5, 0.05)
			return s
		"capsule":
			var c := CapsuleShape3D.new()
			c.radius = maxf(size * 0.25, 0.05)
			c.height = maxf(size, 0.2)
			return c
		_:
			var b := BoxShape3D.new()
			b.size = Vector3(size, size, size)
			return b


static func _mesh_3d(kind: String, size: float) -> Mesh:
	match kind:
		"sphere":
			var m := SphereMesh.new()
			m.radius = maxf(size * 0.5, 0.05)
			m.height = maxf(size, 0.2)
			return m
		"capsule":
			var m2 := CapsuleMesh.new()
			m2.radius = maxf(size * 0.25, 0.05)
			m2.height = maxf(size, 0.2)
			return m2
		_:
			var m3 := BoxMesh.new()
			m3.size = Vector3(size, size, size)
			return m3


static func _shape_2d(kind: String, px: float) -> Shape2D:
	match kind:
		"sphere":
			var s := CircleShape2D.new()
			s.radius = maxf(px * 0.5, 4.0)
			return s
		"capsule":
			var c := CapsuleShape2D.new()
			c.radius = maxf(px * 0.25, 4.0)
			c.height = maxf(px, 8.0)
			return c
		_:
			var r := RectangleShape2D.new()
			r.size = Vector2(px, px)
			return r


static func _sprite_2d(kind: String, px: float, col: Color) -> Texture2D:
	var FC := load(_CTX_PATH)
	if kind == "box":
		return FC.solid_texture(int(px), int(px), col)
	# round shapes get a filled circle so the visual matches the hitbox
	var d := int(clampf(px, 8.0, 256.0))
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	var r := float(d) * 0.5
	var c := float(d) * 0.5
	for y in range(d):
		for x in range(d):
			var dx := float(x) + 0.5 - c
			var dy := float(y) + 0.5 - c
			if dx * dx + dy * dy <= r * r:
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------------------
# Public static helpers — other modules read the bits from here so every
# feature agrees on what "enemy" or "bullet" means.
# ---------------------------------------------------------------------------

## Single collision bit for a friendly group name; 0 for unknown names.
static func bit_for(group_name: String) -> int:
	var n := str(group_name).strip_edges().to_lower()
	return int(LAYER_BITS.get(n, 0))


## OR of the bits named in a comma-separated list. Unknown names add 0, so a
## typo can never widen the mask by accident.
static func mask_for(csv: String) -> int:
	var mask := 0
	for part in str(csv).split(","):
		mask |= bit_for(part)
	return mask


## The sensible default mask for a layer when `collides_with` is empty.
static func default_mask_for(layer_name: String) -> int:
	match str(layer_name).strip_edges().to_lower():
		"world": return mask_for("world,player,enemy,pickup,hazard,bullet")
		"player": return mask_for("world,enemy,pickup,hazard")
		"enemy": return mask_for("world,player,bullet")
		"pickup": return mask_for("player")
		"hazard": return mask_for("player")
		"bullet": return mask_for("enemy,world")
		"decor": return 0
		_: return 0


## The visible tint per layer (world gray, player blue, enemy red, pickup gold,
## hazard orange, bullet cyan, decor light gray).
static func color_for(group_name: String) -> Color:
	match str(group_name).strip_edges().to_lower():
		"world": return Color("#9e9e9e")
		"player": return Color("#4fc3f7")
		"enemy": return Color("#ff5252")
		"pickup": return Color("#ffd54f")
		"hazard": return Color("#ffab40")
		"bullet": return Color("#84ffff")
		"decor": return Color("#d7d7d7")
		_: return Color("#9e9e9e")


# ---------------------------------------------------------------------------
# Safe coercion (mirrors the compiler's private helpers)
# ---------------------------------------------------------------------------

static func _is_3d(ctx) -> bool:
	if ctx is Dictionary:
		return bool(ctx.get("is_3d", true))
	if ctx == null:
		return true
	var v = ctx.get("is_3d")
	return bool(v) if v != null else true


static func _num(v, fallback: float) -> float:
	if v is float or v is int:
		return float(v)
	if v is String and str(v).is_valid_float():
		return float(v)
	return fallback


static func _vec3(v, fallback: Vector3) -> Vector3:
	if v is Vector3:
		return v
	if v is Array and v.size() >= 3:
		return Vector3(_num(v[0], fallback.x), _num(v[1], fallback.y), _num(v[2], fallback.z))
	return fallback


static func _vec2(v, fallback: Vector2) -> Vector2:
	if v is Vector2:
		return v
	if v is Array and v.size() >= 2:
		return Vector2(_num(v[0], fallback.x), _num(v[1], fallback.y))
	return fallback
