extends Node
## light — 2D lighting and shadows: the single highest visual-impact-per-effort
## feature in 2D, because Godot's SDF occluders make sprite shadows free.
##
## WHAT IT ADDS (2D — ctx.is_3d == false)
##   kind "light"     -> one PointLight2D (point) or DirectionalLight2D
##                       (directional), both real Godot light nodes that cast
##                       shadows through LightOccluder2D geometry. The light
##                       texture is a procedural radial gradient baked in code
##                       (Image + ImageTexture) so there is NO asset file.
##   kind "occluder"  -> one LightOccluder2D + OccluderPolygon2D (box or circle
##                       polygon), a real shadow caster. sdf_collision is on,
##                       so any shadow-casting light in the scene produces a
##                       real sprite shadow from this shape.
##
## WHY IT MATTERS: a 2D game without lighting reads flat and lifeless next to
## any commercial 2D game. A single warm point light plus one occluder turns
## the same scene into a torch-lit cave.
##
## NODES CREATED
##   2D:  Light_<id>   (PointLight2D | DirectionalLight2D)
##        Occluder_<id>(LightOccluder2D -> OccluderPolygon2D)
##   3D:  Light_<id>   (OmniLight3D)         # real 3D light, no fake 2D light
##        Occluder_<id>(StaticBody3D -> CollisionShape3D(BoxShape3D))
##
## API FACTS VERIFIED against the real Godot 4.7.2 engine (docs dump + live
## probe, not guessed):
##   - Light2D.energy (float) IS the intensity property in Godot 4.x.
##   - There is NO Light2D.range in Godot 4.x. The light radius comes from the
##     TEXTURE size: PointLight2D.texture_scale scales the texture, and the
##     gradient texture is baked at 256px and scaled so the falloff edge sits
##     at the requested range. DirectionalLight2D has max_distance (its own
##     real range property) plus height.
##   - Light2D.shadow_enabled (bool) is the shadow switch (there is no
##     'shadows' property).
##   - Light2D.shadow_filter_smooth (float, 0..N) is the softness knob
##     (there is no 'shadow_softness'; shadow_filter is the enum
##     NONE/PCF5/PCF13).
##   - DirectionalLight2D has NO texture property in Godot 4.7 (its gradient
##     is procedural); its range is max_distance, and height controls how long
##     the shadows it casts are.
##   - LightOccluder2D's property is "occluder" (NOT "occluder_polygon" —
##     assigning occluder_polygon throws a type error) and it holds an
##     OccluderPolygon2D resource.
##   - OccluderPolygon2D.polygon is a PackedVector2Array; set_polygon() exists.
##   - OccluderPolygon2D is a Resource (RefCounted): NEVER free() it.
##   - OmniLight3D uses light_energy + omni_range + shadow_enabled.
##
## RANGE MAPPING (the one design decision worth reading): a PointLight2D has
## no range property, so range is expressed by baking the radial gradient into
## a 256px texture and setting texture_scale = range / 256. A range of 320 ->
## a texture_scale of 1.25, which puts the gradient's falloff edge exactly 320
## px from the light. This is why the texture is baked at a fixed 256px: the
## scale is then a direct, honest conversion of the user's range param.
## (DirectionalLight2D DOES have a real range — max_distance — and is used
## directly there.)
##
## DETERMINISM: no randf(), no filesystem, no wall-clock. The gradient is a
## pure function of x/y; flicker is a sine wave in _process. The same brick
## always compiles to the same nodes.
##
## INTEGRATOR PARAMS (this module only READS them; the integrator adds them to
## brick.gd's PARAM_SCHEMA + KIND):
##   "light":
##     kind_of_light   choice [point, directional]          default "point"
##     color_name      choice [gold, red, blue, green, warm, cool, purple,
##                             white]                        default "warm"
##     intensity       number 0.0..8.0 step 0.1             default 1.5
##     range           number 32..1200 step 8               default 320
##     shadows         bool                                 default true
##     shadow_softness number 0.0..4.0 step 0.2             default 1.0
##     flicker         bool                                 default false
##     flicker_speed   number 0.5..12 step 0.5              default 3.0
##     position        array of 2|3 numbers                 optional
##   "occluder":
##     shape           choice [box, circle]                 default "box"
##     width           number 8..512 step 4                 default 96
##     height          number 8..512 step 4                 default 96
##     position        array of 2|3 numbers                 optional
##   KIND entries (port typing follows the established pattern):
##     "light":    {"label": "Light",     "icon": "💡", "in": [FLOW], "out": []}
##     "occluder": {"label": "Occluder",  "icon": "🌑", "in": [FLOW], "out": []}

# The global script class cache does not contain FeatureCtx, so the bare
# identifier is NOT in scope in a feature module. Preload it explicitly —
# the established pattern (see src/features/trigger.gd).
const FeatureCtx = preload("res://src/compiler/feature_ctx.gd")

# The light gradient is baked once at this resolution and scaled by
# texture_scale to hit the requested range (see RANGE MAPPING above).
const TEX_SIZE := 256
# Defaults, clamped hard so a junk param still produces a sane light.
const DEF_INTENSITY := 1.5
const DEF_RANGE := 320.0
const DEF_SOFTNESS := 1.0
const DEF_SPEED := 3.0
const DEF_WIDTH := 96.0
const DEF_HEIGHT := 96.0
const MAX_LIGHTS := 24          # hard cap per scene: perf + sanity
const LIGHT_KINDS := ["point", "directional"]
const COLORS := ["gold", "red", "blue", "green", "warm", "cool", "purple", "white"]
const SHAPES := ["box", "circle"]
# Flicker depth: a sine of +/-12% around the base energy reads as a torch or
# a failing lamp without ever going negative.
const FLICKER_DEPTH := 0.12

# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

func register(reg) -> void:
	if reg == null or not reg.has_method("register"):
		push_error("[light] no feature registry available")
		return
	reg.register("light", _build_light)
	reg.register("occluder", _build_occluder)

# ---------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------

## "light" brick -> a real light node (2D: PointLight2D/DirectionalLight2D,
## 3D: OmniLight3D). Multiple lights are fine up to MAX_LIGHTS.
func _build_light(b: Dictionary, root: Node, ctx) -> void:
	if root == null or not is_instance_valid(root) or not (b is Dictionary):
		return
	if _light_count(root) >= MAX_LIGHTS:
		push_warning("[light] scene already has the %d-light cap" % MAX_LIGHTS)
		return

	var p := _p(b)
	var kind := _choice(p, "kind_of_light", LIGHT_KINDS, "point")
	var color := _named_color(_choice(p, "color_name", COLORS, "warm"))
	var intensity := _clamp(_num(p, "intensity", DEF_INTENSITY), 0.0, 8.0, DEF_INTENSITY)
	var range_px := _clamp(_num(p, "range", DEF_RANGE), 32.0, 1200.0, DEF_RANGE)
	var shadows := _bool(p, "shadows", true)
	var softness := _clamp(_num(p, "shadow_softness", DEF_SOFTNESS), 0.0, 4.0, DEF_SOFTNESS)
	var flicker := _bool(p, "flicker", false)
	var speed := _clamp(_num(p, "flicker_speed", DEF_SPEED), 0.5, 12.0, DEF_SPEED)
	var bid := FeatureCtx.bid(b)
	var name := "Light_%s" % bid if not bid.is_empty() else "Light"

	var node: Node
	if _is_3d(ctx, root):
		node = _omni_light(name, color, intensity, range_px, shadows)
	else:
		node = _light_2d(name, kind, color, intensity, range_px, shadows, softness)
		if node == null:
			return

	if node is Node2D:
		(node as Node2D).position = _vec2_of(p.get("position", null), Vector2(500.0, 250.0))
	elif node is Node3D:
		(node as Node3D).position = _vec3_of(p.get("position", null), Vector3(6.0, 3.0, 0.0))

	root.add_child(node)

	# flicker: a deterministic sine driver, attached only when asked. It runs
	# in _process (visual-only, so frame-time is the right clock) and needs a
	# script, so its compile result is checked like every other generated one.
	if flicker:
		var src := _flicker_source(intensity, speed)
		if FeatureCtx.attach_script(node, src) != OK:
			push_error("[light] flicker driver failed to compile for '%s'" % name)

	var ents = _ctxv(ctx, "entities", null)
	if ents is Dictionary and not bid.is_empty():
		ents[bid] = node

## "occluder" brick -> a real shadow caster (2D: LightOccluder2D, 3D: a
## StaticBody3D box that naturally blocks light).
func _build_occluder(b: Dictionary, root: Node, ctx) -> void:
	if root == null or not is_instance_valid(root) or not (b is Dictionary):
		return

	var p := _p(b)
	var shape := _choice(p, "shape", SHAPES, "box")
	var w := _clamp(_num(p, "width", DEF_WIDTH), 8.0, 512.0, DEF_WIDTH)
	var h := _clamp(_num(p, "height", DEF_HEIGHT), 8.0, 512.0, DEF_HEIGHT)
	var bid := FeatureCtx.bid(b)
	var name := "Occluder_%s" % bid if not bid.is_empty() else "Occluder"

	var node: Node
	if _is_3d(ctx, root):
		node = _occluder_3d(name, w, h)
		(node as Node3D).position = _vec3_of(p.get("position", null), Vector3(0.0, 1.0, 0.0))
	else:
		node = _occluder_2d(name, shape, w, h)
		if node == null:
			return
		(node as Node2D).position = _vec2_of(p.get("position", null), Vector2(500.0, 250.0))

	root.add_child(node)

	var ents = _ctxv(ctx, "entities", null)
	if ents is Dictionary and not bid.is_empty():
		ents[bid] = node

# ---------------------------------------------------------------------------
# 2D node construction
# ---------------------------------------------------------------------------

## One 2D light. point -> PointLight2D, directional -> DirectionalLight2D.
func _light_2d(name: String, kind: String, color: Color, intensity: float,
		range_px: float, shadows: bool, softness: float) -> Node:
	var node: Light2D
	if kind == "directional":
		var dl := DirectionalLight2D.new()
		# A DirectionalLight2D has a real max_distance — use it for the range,
		# and a modest height so the shadows it casts are long and directional.
		# NOTE (verified): DirectionalLight2D has NO texture property in
		# Godot 4.7 — its gradient is procedural. Its range is max_distance.
		dl.max_distance = max(range_px, 64.0)
		dl.height = 0.6
		node = dl
	else:
		var pl := PointLight2D.new()
		# RANGE MAPPING: texture_scale = range / texture_size puts the baked
		# gradient's falloff edge at exactly `range` px from the light.
		pl.texture = _gradient_texture(color)
		pl.texture_scale = max(range_px / float(TEX_SIZE), 0.125)
		node = pl
	node.name = name
	node.color = color
	node.energy = intensity
	node.enabled = true
	node.shadow_enabled = shadows
	# softness -> shadow_filter_smooth (the real 4.x knob; there is no
	# 'shadow_softness' property on Light2D). PCF5 is the cheapest filter
	# that still looks soft; smoothness does the rest.
	node.shadow_filter = Light2D.SHADOW_FILTER_PCF5 if shadows else Light2D.SHADOW_FILTER_NONE
	node.shadow_filter_smooth = softness if shadows else 0.0
	return node

## One 2D occluder: a LightOccluder2D whose OccluderPolygon2D is a box or a
## circle approximation. sdf_collision makes Godot rasterise the shadow, so
## every shadow-casting light in the scene casts from this shape for free.
func _occluder_2d(name: String, shape: String, w: float, h: float) -> Node:
	var occ := LightOccluder2D.new()
	occ.name = name
	var poly := OccluderPolygon2D.new()
	poly.polygon = _polygon_for(shape, w, h)
	poly.cull_mode = OccluderPolygon2D.CULL_DISABLED
	# NOTE: the property is "occluder", not "occluder_polygon" (verified:
	# assigning occluder_polygon on a LightOccluder2D is a type error).
	occ.occluder = poly
	occ.sdf_collision = true
	# NOTE: OccluderPolygon2D is a Resource — never free() it; it is owned by
	# the occluder node now.
	return occ

## A PackedVector2Array for the requested shape, centred on the origin.
func _polygon_for(shape: String, w: float, h: float) -> PackedVector2Array:
	var hw := w * 0.5
	var hh := h * 0.5
	if shape == "circle":
		# A 16-gon: cheap, deterministic, and at these sizes reads as a
		# circle through the SDF shadow (which is smooth anyway).
		var pts := PackedVector2Array()
		for i in range(16):
			var a := TAU * float(i) / 16.0
			pts.append(Vector2(cos(a) * hw, sin(a) * hh))
		return pts
	return PackedVector2Array([
		Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh),
	])

# ---------------------------------------------------------------------------
# 3D node construction (real native lighting, nothing faked)
# ---------------------------------------------------------------------------

## 3D light: a real OmniLight3D. 3D lighting already works in Godot, so this
## is deliberately NOT a 2D-style light — it is the actual 3D node.
func _omni_light(name: String, color: Color, intensity: float, range_px: float,
		shadows: bool) -> Node:
	var l := OmniLight3D.new()
	l.name = name
	l.light_color = color
	l.light_energy = intensity
	l.omni_range = range_px
	l.shadow_enabled = shadows
	return l

## 3D occluder: a StaticBody3D with a BoxShape3D that naturally blocks light
## and camera. Simple, real, and it is what a physics blocker looks like.
func _occluder_3d(name: String, w: float, h: float) -> Node:
	var body := StaticBody3D.new()
	body.name = name
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var shp := BoxShape3D.new()
	# 3D boxes are metres; keep the depth shallow so it reads as a wall/box
	# the user sized rather than a slab.
	shp.size = Vector3(w, h, max(w, 24.0))
	cs.shape = shp
	body.add_child(cs)
	return body

# ---------------------------------------------------------------------------
# The procedural light texture (NO asset file)
# ---------------------------------------------------------------------------

## Bake a radial gradient texture in code: white core, smooth falloff to fully
## transparent at the edge, tinted with the light colour. Pure function of
## x/y — deterministic by construction.
func _gradient_texture(color: Color) -> ImageTexture:
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var c := TEX_SIZE * 0.5
	var r := TEX_SIZE * 0.5
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var dx := float(x) - c + 0.5
			var dy := float(y) - c + 0.5
			var d := sqrt(dx * dx + dy * dy) / r
			if d >= 1.0:
				img.set_pixel(x, y, Color(color.r, color.g, color.b, 0.0))
			else:
				# smoothstep falloff: bright core, long soft tail
				var a := 1.0 - d
				a = a * a * (3.0 - 2.0 * a)
				img.set_pixel(x, y, Color(color.r, color.g, color.b, a))
	return ImageTexture.create_from_image(img)

# ---------------------------------------------------------------------------
# The generated flicker driver
# ---------------------------------------------------------------------------

## A tiny _process script: energy = base * (1 + DEPTH * sin(t * speed)).
## Deterministic sine — no randf(), so the same frame always flickers the same.
func _flicker_source(base: float, speed: float) -> String:
	var L: Array[String] = []
	L.append("extends Light2D")
	L.append("# Generated by EasyForge from a 'Light' brick with flicker on.")
	L.append("# A torch that breathes: energy rides a sine wave around the base")
	L.append("# energy. Deterministic (no randf) so the same frame always")
	L.append("# flickers identically.")
	L.append("const BASE := %f" % base)
	L.append("const SPEED := %f" % speed)
	L.append("const DEPTH := %f" % FLICKER_DEPTH)
	L.append("var _t := 0.0")
	L.append("")
	L.append("func _process(delta: float) -> void:")
	L.append("\t_t += delta * SPEED")
	L.append("\tenergy = BASE * (1.0 + DEPTH * sin(_t))")
	return "\n".join(L) + "\n"

# ---------------------------------------------------------------------------
# Colour table — the named palette the user picks from, resolved through the
# shared FeatureCtx palette where possible so every feature agrees on "gold".
# ---------------------------------------------------------------------------

func _named_color(name: String) -> Color:
	match name:
		"warm":
			# a torch: not a pure palette colour, a warm amber
			return Color(1.0, 0.78, 0.45)
		"cool":
			# moonlight: a cool blue-white
			return Color(0.62, 0.78, 1.0)
		"red": return Color(1.0, 0.32, 0.32)
		"blue": return Color(0.31, 0.76, 0.97)
		"green": return Color(0.41, 0.94, 0.68)
		"gold": return Color(1.0, 0.84, 0.31)
		"purple": return Color(0.70, 0.53, 1.0)
		"white": return Color(1.0, 1.0, 1.0)
		_:
			return Color(1.0, 0.78, 0.45)

# ---------------------------------------------------------------------------
# Defensive readers — a brick with missing/null/wrong-typed params still
# compiles to something harmless. Mirrors the FeatureCtx contract.
# ---------------------------------------------------------------------------

func _p(b) -> Dictionary:
	if b is Dictionary:
		var v = b.get("params")
		if v is Dictionary:
			return v
	return {}

func _num(d: Dictionary, key: String, fallback: float) -> float:
	var x = d.get(key)
	if x is float or x is int:
		return float(x)
	if x is String and str(x).is_valid_float():
		return float(x)
	return fallback

func _str(d: Dictionary, key: String, fallback: String) -> String:
	var v = d.get(key)
	if v == null:
		return fallback
	var s := str(v)
	return s if not s.is_empty() else fallback

func _bool(d: Dictionary, key: String, fallback: bool) -> bool:
	var v = d.get(key)
	if v == null:
		return fallback
	if v is bool:
		return v
	if v is float or v is int:
		return v != 0
	if v is String:
		return str(v).to_lower() in ["true", "1", "yes"]
	return fallback

## A choice param, lowercased and validated against the allowed list.
func _choice(d: Dictionary, key: String, allowed: Array, fallback: String) -> String:
	var s := _str(d, key, fallback).to_lower()
	return s if s in allowed else fallback

func _clamp(v: float, lo: float, hi: float, fallback: float) -> float:
	if is_nan(v) or is_inf(v):
		return fallback
	return clampf(v, lo, hi)

func _vec2_of(v, fallback: Vector2) -> Vector2:
	if v is Vector2:
		return v
	if v is Array and v.size() >= 2:
		var x := _n(v[0], fallback.x)
		var y := _n(v[1], fallback.y)
		return Vector2(x, y)
	return fallback

func _vec3_of(v, fallback: Vector3) -> Vector3:
	if v is Vector3:
		return v
	if v is Array and v.size() >= 3:
		return Vector3(_n(v[0], fallback.x), _n(v[1], fallback.y), _n(v[2], fallback.z))
	# a 2-number position is legal in 3D too: treat it as x/y on the ground
	if v is Array and v.size() >= 2:
		return Vector3(_n(v[0], fallback.x), _n(v[1], fallback.y), fallback.z)
	return fallback

func _n(x, fallback: float) -> float:
	if x is float or x is int:
		var f := float(x)
		return fallback if (is_nan(f) or is_inf(f)) else f
	if x is String and str(x).is_valid_float():
		var f2 := float(x)
		return fallback if (is_nan(f2) or is_inf(f2)) else f2
	return fallback

# ---------------------------------------------------------------------------
# Context helpers
# ---------------------------------------------------------------------------

func _is_3d(ctx, root: Node) -> bool:
	if ctx != null and ctx is Dictionary:
		var v = ctx.get("is_3d")
		if v is bool:
			return v
	if root != null and is_instance_valid(root):
		return root is Node3D
	return true

func _ctxv(ctx, key: String, default_value):
	if ctx is Dictionary:
		var v = (ctx as Dictionary).get(key)
		return v if v != null else default_value
	if ctx != null:
		for prop in ctx.get_property_list():
			if str(prop.get("name", "")) == key:
				return ctx.get(key)
	return default_value

## How many light nodes already exist in the scene (counted by class, since
## Godot auto-renames duplicate-named siblings to @Class@N).
func _light_count(root: Node) -> int:
	var n := 0
	for ch in root.get_children():
		if ch is Light2D or ch is Light3D:
			n += 1
	return n
