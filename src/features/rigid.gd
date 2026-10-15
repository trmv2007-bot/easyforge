extends Node
## rigid — a 'Rigid' brick: one physics body that obeys REAL Godot physics.
##
## WHY IT MATTERS: until now every entity in a compiled game is a
## CharacterBody driven by scripted motion — a crate on a shelf is animated
## by hand. This brick gives an object a real RigidBody, so it falls, rolls,
## bounces, tips over, and stacks by itself. Falling crates, dice, ball pits
## and stacked boxes all become "drop a Rigid brick and press Play".
##
## NODES CREATED (per rigid brick)
##   3D -> RigidBody3D   "Rigid_<id>"   (group "rigid")
##           - CollisionShape3D "Shape"  (BoxShape3D | SphereShape3D |
##                                        CapsuleShape3D, from `model`)
##           - MeshInstance3D   "Mesh"   (BoxMesh | SphereMesh | CapsuleMesh,
##                                        StandardMaterial3D albedo = color)
##   2D -> RigidBody2D   "Rigid_<id>"   (group "rigid")
##           - CollisionShape2D "Shape"  (RectangleShape2D | CircleShape2D)
##           - Polygon2D        "Mesh"   (same colour, no asset files)
##
## API FACTS VERIFIED against the real Godot 4.7.2 engine with a live
## property-list dump probe (run, read, then deleted) — NOT guessed:
##   - RigidBody3D and RigidBody2D BOTH have: mass (float), gravity_scale
##     (float), linear_damp (float), angular_damp (float), sleeping (bool),
##     can_sleep (bool), freeze (bool), lock_rotation (bool), freeze_mode
##     (int), physics_material_override (PhysicsMaterial),
##     linear_velocity, angular_velocity, constant_force, constant_torque,
##     center_of_mass_mode, continuous_cd, contact_monitor.
##   - THE PROPERTY IS `linear_damp` / `angular_damp`. There is NO
##     `linear_damping` / `angular_damping` on RigidBody3D in Godot 4 — using
##     those names would be a silent no-op at best. Verified from the dump.
##   - `freeze` is a REAL bool property on both bodies, and `lock_rotation`
##     is a real bool, and `freeze_mode` is a real enum whose values are
##     FREEZE_MODE_STATIC = 0 and FREEZE_MODE_KINEMATIC = 1 (read off the
##     instance). `freeze` + `lock_rotation` are what the `freeze` param maps
##     to, because FREEZE_MODE_* REPLACES the body's dynamics entirely (the
##     body stops being a rigid body), which is NOT what a user asking to
##     "freeze rotation" means. Mapping documented below.
##   - PhysicsMaterial has exactly two knobs: `bounce` (float, default 0.0)
##     and `friction` (float, default 1.0). Attach it via
##     physics_material_override on the body — the same pattern the core
##     compiler uses for the Platform brick.
##   - BoxShape3D.size (Vector3), SphereShape3D.radius (float),
##     CapsuleShape3D.radius (float) + .height (float, must be >= 2*radius),
##     RectangleShape2D.size (Vector2), CircleShape2D.radius (float).
##   - BoxMesh.size, SphereMesh.radius/.height, CapsuleMesh.radius/.height.
##   - CollisionShape3D / CollisionShape2D both expose `.shape` and `.disabled`.
##
## FREEZE PARAM MAPPING (the honest one, per the contract):
##   "none"      -> freeze = false, lock_rotation = false, freeze_mode untouched
##   "rotation"  -> lock_rotation = true   (body still falls, just stops spinning)
##   "position"  -> freeze = true          (body never moves or rotates)
##   "both"      -> freeze = true, lock_rotation = true
##   freeze_mode is deliberately NOT set: FREEZE_MODE_STATIC turns the body
##   into a static collider and FREEZE_MODE_KINEMATIC into a kinematic one,
##   which is a different object entirely. `freeze`/`lock_rotation` keep it a
##   RigidBody and are the properties the freeze param actually means.
##
## DETERMINISM: no randf() anywhere — not in positions, not in sizes, not in
## spin. The same brick always compiles to byte-identical nodes, and physics
## at the engine's fixed 60 Hz timestep is deterministic, so the same scene
## always falls the same way.
##
## INTEGRATOR PARAMS (this module only READS them; the integrator adds them
## to brick.gd's PARAM_SCHEMA + KIND):
##   model           choice [box, sphere, capsule]          default "box"
##   mass            number 0.1..100    step 0.1            default 1.0
##   gravity_scale   number -2.0..4.0   step 0.1            default 1.0
##   linear_damping  number 0.0..5.0    step 0.1            default 0.1
##   angular_damping number 0.0..5.0    step 0.1            default 0.1
##   bounciness      number 0.0..1.0    step 0.05           default 0.2
##   friction        number 0.0..1.0    step 0.05           default 0.6
##   freeze          choice [none, rotation, position, both] default "none"
##   size            number 0.2..6.0    step 0.2            default 1.0
##   color_name      choice [gold, red, blue, green, gray, brown, white]
##                                                          default "brown"
##   position        array of 2|3 numbers                  optional
##   start_asleep    bool                                  default true
##   KIND entry:  "rigid": {"label": "Rigid", "icon": "📦", "in": [FLOW], "out": []}
## NOTE: the params are named linear_damping / angular_damping (user-facing)
## but they set the engine's linear_damp / angular_damp.

# FeatureCtx's class_name is not in scope in a feature module without an
# explicit preload — the established pattern (see src/features/trigger.gd).
const FeatureCtx = preload("res://src/compiler/feature_ctx.gd")

const KIND := "rigid"
const GROUP := "rigid"          # so a later brick can query every rigid body

# Clamp ranges (mirrors the param schema the integrator adds to brick.gd).
const MASS_MIN := 0.1
const MASS_MAX := 100.0
const GRAV_MIN := -2.0
const GRAV_MAX := 4.0
const DAMP_MIN := 0.0
const DAMP_MAX := 5.0
const BOUNCE_MIN := 0.0
const BOUNCE_MAX := 1.0
const FRICTION_MIN := 0.0
const FRICTION_MAX := 1.0
const SIZE_MIN := 0.2
const SIZE_MAX := 6.0

# Defaults, used whenever a param is missing, wrong-typed, or NaN/Inf.
const DEF_MODEL := "box"
const DEF_MASS := 1.0
const DEF_GRAVITY := 1.0
const DEF_DAMP := 0.1
const DEF_BOUNCE := 0.2
const DEF_FRICTION := 0.6
const DEF_FREEZE := "none"
const DEF_SIZE := 1.0
const DEF_COLOR := "brown"
const DEF_POS_3D := Vector3(2.0, 4.0, 0.0)
const DEF_POS_2D := Vector2(420.0, 120.0)
# 3D `size` is metres; a metre-scale brick would be invisible in the
# 2D-pixel world the compiler's 2D levels use, so scale it up.
const PX_PER_UNIT := 12.0
# Godot's CapsuleMesh/CapsuleShape3D require height >= 2 * radius or the
# capsule degenerates; guard it explicitly rather than trusting the slider.
const CAPSULE_H_MIN_RATIO := 2.0
const CAPSULE_LEN_RATIO := 1.5

const MODELS := ["box", "sphere", "capsule"]
const FREEZES := ["none", "rotation", "position", "both"]
const COLORS := ["gold", "red", "blue", "green", "gray", "brown", "white"]

func register(reg) -> void:
	if reg != null and reg.has_method("register"):
		reg.register(KIND, _build)

# ---------------------------------------------------------------------------
# Builder
# ---------------------------------------------------------------------------

## One "rigid" brick -> one real RigidBody (3D: RigidBody3D, 2D: RigidBody2D)
## with a collider, a procedural visible mesh, and real physics properties.
func _build(b: Dictionary, root: Node, ctx) -> void:
	if root == null or not is_instance_valid(root):
		return
	if not (b is Dictionary):
		return

	var p := FeatureCtx.params(b)
	var bid := FeatureCtx.bid(b)
	var is3 := _is_3d(ctx, root)

	var model := _choice(p, "model", MODELS, DEF_MODEL)
	var freeze := _choice(p, "freeze", FREEZES, DEF_FREEZE)
	var color_name := _choice(p, "color_name", COLORS, DEF_COLOR)

	# clamp every number hard, so NaN/Inf/out-of-range never reaches the engine
	var mass := _clamp(_num(p, "mass", DEF_MASS), MASS_MIN, MASS_MAX, DEF_MASS)
	var gravity := _clamp(_num(p, "gravity_scale", DEF_GRAVITY), GRAV_MIN, GRAV_MAX, DEF_GRAVITY)
	var lin_damp := _clamp(_num(p, "linear_damping", DEF_DAMP), DAMP_MIN, DAMP_MAX, DEF_DAMP)
	var ang_damp := _clamp(_num(p, "angular_damping", DEF_DAMP), DAMP_MIN, DAMP_MAX, DEF_DAMP)
	var bounce := _clamp(_num(p, "bounciness", DEF_BOUNCE), BOUNCE_MIN, BOUNCE_MAX, DEF_BOUNCE)
	var friction := _clamp(_num(p, "friction", DEF_FRICTION), FRICTION_MIN, FRICTION_MAX, DEF_FRICTION)
	var size := _clamp(_num(p, "size", DEF_SIZE), SIZE_MIN, SIZE_MAX, DEF_SIZE)
	var asleep := FeatureCtx.bbool(b, "start_asleep", true)

	var color := _color(color_name)
	var pos_raw = p.get("position", null)

	var node: Node
	if is3:
		node = _body_3d(bid, model, size, color, pos_raw)
	else:
		node = _body_2d(bid, model, size, color, pos_raw)
		if node == null:
			return

	# --- real physics properties (every name below verified in the engine) ---
	# PhysicsBody3D and PhysicsBody2D both expose mass / gravity_scale /
	# linear_damp / angular_damp, but they are SIBLING classes with no shared
	# ancestor that carries those properties, so set them per dimension.
	# (A 2D body cast to PhysicsBody3D is null — verified in the probe.)
	if is3:
		var b3 := node as RigidBody3D
		if b3 == null:
			push_warning("[rigid] brick '%s' built no RigidBody3D" % bid)
			return
		_apply_physics_3d(b3, mass, gravity, lin_damp, ang_damp, bounce, friction, freeze, asleep)
	else:
		var b2 := node as RigidBody2D
		if b2 == null:
			push_warning("[rigid] brick '%s' built no RigidBody2D" % bid)
			return
		_apply_physics_2d(b2, mass, gravity, lin_damp, ang_damp, bounce, friction, freeze, asleep)

	# findable + interactable by a later brick
	node.add_to_group(GROUP)

	root.add_child(node)

	# publish into the entities map so later bricks (Rule, etc.) can look
	# this body up by brick id
	var ents = _ctxv(ctx, "entities", null)
	if ents is Dictionary and not bid.is_empty():
		ents[bid] = node

# ---------------------------------------------------------------------------
# Physics property application — one overload per body class (they are
# siblings, so there is no shared base to write this once against).
# ---------------------------------------------------------------------------

func _apply_physics_3d(b: RigidBody3D, mass: float, gravity: float, lin_damp: float,
		ang_damp: float, bounce: float, friction: float, freeze: String,
		asleep: bool) -> void:
	b.mass = mass
	b.gravity_scale = gravity
	b.linear_damp = lin_damp          # NOT linear_damping — see header
	b.angular_damp = ang_damp         # NOT angular_damping — see header
	b.can_sleep = true
	b.freeze = (freeze == "position" or freeze == "both")
	b.lock_rotation = (freeze == "rotation" or freeze == "both")
	var pm := PhysicsMaterial.new()
	pm.bounce = bounce
	pm.friction = friction
	b.physics_material_override = pm
	if asleep:
		b.sleeping = true

func _apply_physics_2d(b: RigidBody2D, mass: float, gravity: float, lin_damp: float,
		ang_damp: float, bounce: float, friction: float, freeze: String,
		asleep: bool) -> void:
	b.mass = mass
	b.gravity_scale = gravity
	b.linear_damp = lin_damp          # NOT linear_damping — see header
	b.angular_damp = ang_damp         # NOT angular_damping — see header
	b.can_sleep = true
	b.freeze = (freeze == "position" or freeze == "both")
	b.lock_rotation = (freeze == "rotation" or freeze == "both")
	var pm := PhysicsMaterial.new()
	pm.bounce = bounce
	pm.friction = friction
	b.physics_material_override = pm
	if asleep:
		b.sleeping = true

# ---------------------------------------------------------------------------
# 3D body
# ---------------------------------------------------------------------------

func _body_3d(bid: String, model: String, size: float, color: Color, pos_raw) -> Node3D:
	var body := RigidBody3D.new()
	body.name = "Rigid" if bid.is_empty() else "Rigid_%s" % bid

	var half := size * 0.5

	var col := CollisionShape3D.new()
	col.name = "Shape"
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"

	if model == "sphere":
		var r := half
		var s3 := SphereShape3D.new()
		s3.radius = r
		col.shape = s3
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = size
		mesh.mesh = sm
	elif model == "capsule":
		var r := half * 0.5
		# height must be >= 2 * radius (engine requirement) — enforce it.
		var min_h: float = r * CAPSULE_H_MIN_RATIO
		var want_h: float = size * CAPSULE_LEN_RATIO
		var h: float = want_h if want_h > min_h else min_h
		var c3 := CapsuleShape3D.new()
		c3.radius = r
		c3.height = h
		col.shape = c3
		var cm := CapsuleMesh.new()
		cm.radius = r
		cm.height = h
		mesh.mesh = cm
	else:
		var b3 := BoxShape3D.new()
		b3.size = Vector3(size, size, size)
		col.shape = b3
		var bm := BoxMesh.new()
		bm.size = Vector3(size, size, size)
		mesh.mesh = bm

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material_override = mat

	body.add_child(col)
	body.add_child(mesh)
	body.position = _vec3_of(pos_raw, DEF_POS_3D)
	return body

# ---------------------------------------------------------------------------
# 2D body
# ---------------------------------------------------------------------------

func _body_2d(bid: String, model: String, size: float, color: Color, pos_raw) -> Node2D:
	var body := RigidBody2D.new()
	body.name = "Rigid" if bid.is_empty() else "Rigid_%s" % bid

	var px := size * PX_PER_UNIT
	var half := px * 0.5

	var col := CollisionShape2D.new()
	col.name = "Shape"
	var poly := Polygon2D.new()
	poly.name = "Mesh"

	if model == "sphere":
		var s2 := CircleShape2D.new()
		s2.radius = half
		col.shape = s2
		poly.polygon = _ngon(half, 16)
	elif model == "capsule":
		# a 2D capsule reads as a vertical rounded pill — a real convex
		# outline, built from the same numbers the collider uses.
		var r := half * 0.5
		var pts := PackedVector2Array()
		for i in range(8):
			var a := -PI * 0.5 + PI * float(i) / 8.0
			pts.append(Vector2(cos(a) * r, sin(a) * r + half - r))
		for i in range(8):
			var a2 := PI * 0.5 + PI * float(i) / 8.0
			pts.append(Vector2(cos(a2) * r, sin(a2) * r - half + r))
		# collider: the honest approximation is a circle of the capsule's
		# half-extent, so the 2D capsule never tunnels through geometry.
		var c2 := CircleShape2D.new()
		c2.radius = half
		col.shape = c2
		poly.polygon = pts
	else:
		var rect := RectangleShape2D.new()
		rect.size = Vector2(px, px)
		col.shape = rect
		poly.polygon = PackedVector2Array([
			Vector2(-half, -half), Vector2(half, -half),
			Vector2(half, half), Vector2(-half, half),
		])

	poly.color = color
	body.add_child(col)
	body.add_child(poly)
	body.position = _vec2_of(pos_raw, DEF_POS_2D)
	return body

# ---------------------------------------------------------------------------
# Small geometry helper
# ---------------------------------------------------------------------------

## A regular n-gon centred on the origin — a deterministic circle stand-in
## for 2D visuals. No randf(), so the same brick always produces the same
## polygon.
func _ngon(radius: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(Vector2(cos(a) * radius, sin(a) * radius))
	return pts

# ---------------------------------------------------------------------------
# Colour table — the named palette the user picks from. "brown" is not in the
# shared FeatureCtx palette, so it is resolved locally; the rest go through
# the shared palette so every feature agrees on what "gold" means.
# ---------------------------------------------------------------------------

func _color(name: String) -> Color:
	match name:
		"brown":
			# a crate: warm mid brown, not a palette entry
			return Color(0.55, 0.36, 0.2)
		"gray", "grey":
			return FeatureCtx.palette_color("gray")
		"white":
			return FeatureCtx.palette_color("white")
		"gold":
			return FeatureCtx.palette_color("gold")
		"red":
			return FeatureCtx.palette_color("red")
		"blue":
			return FeatureCtx.palette_color("blue")
		"green":
			return FeatureCtx.palette_color("green")
		_:
			return Color(0.55, 0.36, 0.2)

# ---------------------------------------------------------------------------
# Defensive readers — a brick with missing/null/wrong-typed params still
# compiles to something harmless. Mirrors the FeatureCtx contract.
# ---------------------------------------------------------------------------

func _num(d: Dictionary, key: String, fallback: float) -> float:
	var x = d.get(key)
	if x is float or x is int:
		var f := float(x)
		return fallback if (is_nan(f) or is_inf(f)) else f
	if x is String and str(x).is_valid_float():
		var f2 := float(x)
		return fallback if (is_nan(f2) or is_inf(f2)) else f2
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
		return Vector2(_n(v[0], fallback.x), _n(v[1], fallback.y))
	return fallback

func _vec3_of(v, fallback: Vector3) -> Vector3:
	if v is Vector3:
		return v
	if v is Array and v.size() >= 3:
		return Vector3(_n(v[0], fallback.x), _n(v[1], fallback.y), _n(v[2], fallback.z))
	# a 2-number position is legal in 3D too: treat it as x/y, keep fallback z
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
