extends Node
## blueprint — prefab / instancing with overrides. THE structural unlock.
##
## WHY THIS EXISTS: today ten coins = ten hand-wired brick sets, and fixing
## one bug means fixing it ten times. A blueprint is defined ONCE and
## instanced everywhere; edit the definition and every instance updates on
## recompile. One edit, everywhere — that is the whole point.
##
## KINDS
##   "blueprint_def" — the definition. The bricks WIRED INTO IT (its graph
##                     connections, followed transitively) are the template.
##                     It emits nothing visible; it only claims its kind so
##                     the compiler never falls back to a Label placeholder.
##   "blueprint"     — an instance. Compiles the template `count` times, each
##                     inside its own container node (<Name>_0, <Name>_1, ...)
##                     laid out per layout/spread/rows. `overrides`
##                     ("key=value;key=value") rewrites params on EVERY
##                     instance, e.g. "model=enemy;speed=2.0".
##
## HOW MULTI-INSTANCE GENERATION ACTUALLY WORKS (the honest mechanism)
##   For each instance this module invokes the SAME FeatureRegistry the
##   compiler uses (resolved through the Features autoload, Engine.get_singleton
##   as fallback) against deep-copied template bricks whose ids are rewritten
##   per instance. Rewriting the id is load-bearing: sibling modules that
##   dedupe by brick id (trigger.gd) would otherwise suppress instances 2..N,
##   and the compiler's own entities map is never polluted because each
##   instance gets a FRESH entities Dictionary.
##   Kinds the CORE compiler builds in its match statements (spawn, move,
##   collide, score, rule, ...) are not in the registry, so they cannot be
##   re-invoked from here. "spawn" is the one exception: it is by far the
##   most common template root (a coin, an enemy), so this module carries a
##   small fallback builder for it (see _fallback_spawn) that emits a real
##   CharacterBody with a real mesh — which is also what makes the
##   "model=enemy" override genuinely work. Any other core kind is reported
##   with a warning and skipped; that is a limitation of the registry seam,
##   not a blueprint bug.
##   The container is passed AS the registry `root`, so every builder adds its
##   nodes straight into the instance group — no reparenting, no snapshotting.
##
## INDEPENDENCE: every instance owns a fresh container + a fresh entities map,
## so a collision on Coin_0 can never affect Coin_1.
##
## DETERMINISM: no randf() anywhere. row = +X, column = +Y (3D: +Z),
## grid = rows x columns, ring = evenly spaced on a circle. Same brick,
## same scene, every compile.
##
## LAYOUT UNITS: `spread` is the shared 1..200 param. In 2D it is scaled to
## pixels (x8, so the default 12 -> 96px, the established px-per-unit pattern);
## in 3D it is centimetres in metre space (/10, so 12 -> 1.2m).
##
## DEGRADATION (never crash):
##   - blueprint names no definition -> ONE invisible Marker + push_warning
##   - malformed override item -> skipped + push_warning
##   - override key matching no param -> push_warning, instance still builds
##   - missing/garbage params -> defaults, then clamped
##
## INTEGRATOR HOOK (optional, removes the standalone copies of template
## members): in compiler.gd's pass-1 and pass-2 loops, right after the
## `_registry_build(...)` guard, add:
##     if BlueprintFeature.is_template_member(g, _id(b)): continue
## with `const BlueprintFeature = load("res://src/features/blueprint.gd")`.
## Template members are ALSO real bricks in the graph, so until that line
## exists the compiler builds them once on its own (twice for kinds whose
## module does not dedupe across passes) alongside the instances. The hook
## is one line per loop and changes nothing else.
##
## PARAMS THE INTEGRATOR ADDS TO brick.gd (this module only READS them):
##   "blueprint_def": {
##     "name":        {"type": "text", "label": "Blueprint name", "default": "Coin"},
##     "description": {"type": "text", "label": "Description", "default": ""},
##   }
##   "blueprint": {
##     "blueprint_name": {"type": "text", "label": "Blueprint", "default": "Coin"},
##     "count":     {"type": "number", "label": "How many", "min": 1.0, "max": 50.0, "step": 1.0, "default": 1.0},
##     "spread":    {"type": "number", "label": "Spacing", "min": 1.0, "max": 200.0, "step": 1.0, "default": 12.0},
##     "layout":    {"type": "choice", "label": "Layout", "options": ["row", "column", "grid", "ring"], "default": "row"},
##     "rows":      {"type": "number", "label": "Rows (grid)", "min": 1.0, "max": 10.0, "step": 1.0, "default": 3.0},
##     "overrides": {"type": "text", "label": "Overrides (key=value;...)", "default": ""},
##   }
##   KIND entries:
##     "blueprint_def": {"label": "Blueprint", "icon": "📐", "in": [FLOW], "out": []}
##     "blueprint":     {"label": "Instance",  "icon": "🧩", "in": [FLOW], "out": []}
##
## SCHEMA NOTE: this module needs NO new IR shape. Definitions are discovered
## at compile time from the def brick's existing "connections" list
## ({"from_out", "to_brick", "to_in"}), exactly as the compiler's own
## _outgoing_targets reads them — so no graph.gd / schema v3 work.

const KIND_DEF := "blueprint_def"
const KIND_INSTANCE := "blueprint"

const MAX_COUNT := 50
const MAX_ROWS := 10
const MIN_SPREAD := 1.0
const MAX_SPREAD := 200.0
const PX_PER_SPREAD := 8.0     # 2D: spread units -> pixels
const CM_PER_SPREAD := 10.0    # 3D: spread units -> centimetres
const MAX_DEPTH := 3           # nested blueprint recursion guard
const LAYOUTS: Array[String] = ["row", "column", "grid", "ring"]

# The global script class cache does not contain FeatureCtx, so the bare
# identifier is NOT in scope in a feature module. Preload it explicitly —
# the established pattern (see src/features/light.gd, trigger.gd).
const FeatureCtx = preload("res://src/compiler/feature_ctx.gd")

# The compiler offers every brick to the registry in pass 1 AND pass 2.
# Remember which bricks this module already built for the current root so
# one blueprint brick never becomes two instance sets (same guard pattern
# as src/features/trigger.gd). The root is compared by REFERENCE, not by
# instance id: Godot reuses instance ids after a node is freed, and every
# compile builds a brand-new root.
var _claimed := {}
var _claimed_root: Node = null

# The FeatureRegistry handed to register(). Captured there because feature
# modules are instantiated WITHOUT being added to the tree (features.gd
# does `res.new()` + `register(reg)` and nothing else), so a /root node
# path lookup from an orphaned module returns null in production.
var _reg = null

func register(reg) -> void:
	if reg == null or not reg.has_method("register"):
		push_error("[blueprint] no feature registry available")
		return
	_reg = reg
	reg.register(KIND_DEF, _build_def)
	reg.register(KIND_INSTANCE, _build_instance)

# ---------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------

## "blueprint_def": emits nothing. Registering the kind is the point — it
## claims the brick so the compiler never renders it as a Label placeholder.
func _build_def(b: Dictionary, root: Node, ctx) -> void:
	return

## "blueprint": compile the template `count` times, laid out per layout.
func _build_instance(b: Dictionary, root: Node, ctx) -> void:
	if root == null or not is_instance_valid(root) or not (b is Dictionary):
		return
	if not _claim(b, root):
		return

	var graph = _graph(ctx)
	var is3 := _is_3d(ctx)
	var depth := int(_ctxv(ctx, "ef_bp_depth", 0))
	if depth > MAX_DEPTH:
		push_warning("[blueprint] nesting deeper than %d — skipping" % MAX_DEPTH)
		return

	var name := _clean_name(FeatureCtx.bstr(b, "blueprint_name", "Blueprint"))
	var members := _template_bricks(graph, name)
	if members.is_empty():
		# No definition, or a definition with nothing wired into it: degrade
		# to ONE harmless invisible marker. Never crash, never a placeholder.
		push_warning("[blueprint] no definition (or empty template) for '%s' — emitting an invisible marker" % name)
		var marker: Node = Marker3D.new() if is3 else Marker2D.new()
		marker.name = "%s_missing" % name
		root.add_child(marker)
		return

	var count := _clampi(FeatureCtx.bnum(b, "count", 1.0), 1, MAX_COUNT, 1)
	var spread := _clampf(FeatureCtx.bnum(b, "spread", 12.0), MIN_SPREAD, MAX_SPREAD, 12.0)
	var layout := _layout_of(FeatureCtx.bstr(b, "layout", "row"))
	var rows := _clampi(FeatureCtx.bnum(b, "rows", 3.0), 1, MAX_ROWS, 3)
	var overrides := parse_overrides(FeatureCtx.bstr(b, "overrides", ""))
	var bid := FeatureCtx.bid(b)

	for i in count:
		var container: Node = Node3D.new() if is3 else Node2D.new()
		root.add_child(container)
		# Build each member into the container itself: registry builders add
		# to the `root` they are handed, so the container IS their root.
		var tctx := {
			"compiler": _ctxv(ctx, "compiler", null),
			"root": container,
			"entities": {},        # FRESH per instance: ids never clobber
			"player": _ctxv(ctx, "player", null),
			"is_3d": is3,
			"graph": graph,
			"controls": _ctxv(ctx, "controls", {}),
			"ef_bp_depth": depth + 1,
		}
		for raw in members:
			if not (raw is Dictionary):
				continue
			var copy: Dictionary = (raw as Dictionary).duplicate(true)
			# Rewrite the id per instance so no sibling module's dedupe map
			# and no shared entities key can merge two instances together.
			var mid := str(copy.get("id", ""))
			if not mid.is_empty():
				copy["id"] = "%s__bp%s__%d" % [mid, bid if not bid.is_empty() else "x", i]
			_apply_overrides(copy, overrides, name)
			_build_member(copy, container, tctx, is3, name)
		container.name = "%s_%d" % [name, i]
		if container is Node2D:
			(container as Node2D).position = _offset_2d(i, count, layout, spread, rows)
		elif container is Node3D:
			(container as Node3D).position = _offset_3d(i, count, layout, spread, rows)

## Build ONE template member into an instance container: through the
## registry when another module owns the kind, through the spawn fallback
## for the one core kind that matters, warned-and-skipped otherwise.
func _build_member(brick: Dictionary, container: Node, tctx: Dictionary,
		is3: bool, bp_name: String) -> void:
	var kind := str(brick.get("kind", ""))
	if kind.is_empty():
		return
	var reg = _registry()
	if reg != null and reg.has_method("build") and bool(reg.build(kind, brick, container, tctx)):
		return
	# The core compiler owns this kind: it cannot be re-invoked through the
	# registry. "spawn" gets the fallback (the canonical coin/enemy
	# template root); everything else is reported, never crashed on.
	if kind == "spawn":
		container.add_child(_fallback_spawn(brick, is3))
		return
	push_warning("[blueprint] template kind '%s' (blueprint '%s') is built by the core compiler and cannot be instanced — skipped" % [kind, bp_name])

# ---------------------------------------------------------------------------
# Template discovery — the def's connections, followed transitively
# ---------------------------------------------------------------------------

## The live brick dicts a blueprint name instances (transitive from its def).
func _template_bricks(graph, name: String) -> Array:
	var out: Array = []
	if graph == null:
		return out
	var def := _find_def(graph, name)
	if def.is_empty():
		return out
	var def_id := str(def.get("id", ""))
	var seen := {}
	var queue: Array = _targets_of(def)
	while not queue.is_empty():
		var id: String = str(queue.pop_front())
		if id.is_empty() or seen.has(id):
			continue
		seen[id] = true
		if id == def_id:
			continue
		var member := _brick_by_id(graph, id)
		if member.is_empty():
			continue
		var mk := str(member.get("kind", ""))
		if mk == KIND_DEF:
			continue     # a nested def contributes nothing of its own
		out.append(member)
		for t in _targets_of(member):
			if not seen.has(str(t)):
				queue.append(t)
	return out

func _find_def(graph, name: String) -> Dictionary:
	var want := name.to_lower()
	var bricks = _graphv(graph, "bricks", null)
	if not (bricks is Array):
		return {}
	for raw in bricks:
		if not (raw is Dictionary):
			continue
		var bd: Dictionary = raw
		if str(bd.get("kind", "")) != KIND_DEF:
			continue
		var dn := str(FeatureCtx.params(bd).get("name", "")).strip_edges()
		if dn.is_empty():
			dn = str(bd.get("title", "")).strip_edges()
		if dn.is_empty():
			dn = "Blueprint"
		if dn.to_lower() == want:
			return bd
	return {}

func _targets_of(brick: Dictionary) -> Array:
	var out: Array = []
	for c in _conns_of(brick):
		var t := _conn_target(c)
		if not t.is_empty():
			out.append(t)
	return out

## Every brick that is (transitively) wired into ANY blueprint_def. This is
## the predicate the integrator's skip hook calls so the compiler does not
## also build the template members standalone. Pure function of the graph —
## no mutation, no state, safe to call from either pass loop.
static func template_member_ids(graph) -> Array:
	var out: Array = []
	if graph == null:
		return out
	var bricks = _graphv(graph, "bricks", null)
	if not (bricks is Array):
		return out
	for raw in bricks:
		if not (raw is Dictionary):
			continue
		var bd: Dictionary = raw
		if str(bd.get("kind", "")) != KIND_DEF:
			continue
		var seen := {}
		var queue: Array = []
		for c in _conns_of(bd):
			var t := _conn_target(c)
			if not t.is_empty():
				queue.append(t)
		while not queue.is_empty():
			var id: String = str(queue.pop_front())
			if id.is_empty() or seen.has(id):
				continue
			seen[id] = true
			var member := _brick_by_id(graph, id)
			if member.is_empty():
				continue
			if str(member.get("kind", "")) != KIND_DEF:
				out.append(id)
			for c2 in _conns_of(member):
				var t2 := _conn_target(c2)
				if not t2.is_empty() and not seen.has(str(t2)):
					queue.append(t2)
	return out

static func is_template_member(graph, brick_id: String) -> bool:
	if graph == null or brick_id.is_empty():
		return false
	return str(brick_id) in template_member_ids(graph)

# ---------------------------------------------------------------------------
# The core-compiler fallback: "spawn" (a coin / an enemy / a box)
# ---------------------------------------------------------------------------

## A real CharacterBody with a real mesh + collision, mirroring the
## compiler's _build_spawn closely enough to be interchangeable: this is the
## fallback for the one core kind a blueprint genuinely needs, and it is
## what makes "model=enemy" override the look of every instance.
func _fallback_spawn(brick: Dictionary, is3: bool) -> Node:
	var p := FeatureCtx.params(brick)
	var model := str(p.get("model", "box")).strip_edges()
	if model.is_empty():
		model = "box"
	var nice := model.capitalize().replace(" ", "")
	if nice.is_empty():
		nice = "Entity"
	var body: Node
	if is3:
		var cb := CharacterBody3D.new()
		cb.name = nice
		var mesh := MeshInstance3D.new()
		mesh.name = "Mesh"
		mesh.mesh = _fallback_mesh_3d(model)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = _fallback_color(model)
		mesh.material_override = mat
		cb.add_child(mesh)
		var col := CollisionShape3D.new()
		if model == "player":
			var cs := CapsuleShape3D.new()
			cs.radius = 0.4
			cs.height = 1.8
			col.shape = cs
		else:
			var ss := SphereShape3D.new()
			ss.radius = 0.5
			col.shape = ss
		cb.add_child(col)
		cb.position = _pos3(p)
		body = cb
	else:
		var cb2 := CharacterBody2D.new()
		cb2.name = nice
		var sprite := Sprite2D.new()
		sprite.name = "Mesh"
		sprite.texture = FeatureCtx.solid_texture(32, 32, _fallback_color(model))
		cb2.add_child(sprite)
		var col2 := CollisionShape2D.new()
		var cs2 := CapsuleShape2D.new()
		cs2.radius = 14.0
		cs2.height = 30.0
		col2.shape = cs2
		cb2.add_child(col2)
		cb2.position = _pos2(p)
		body = cb2
	return body

static func _fallback_mesh_3d(model: String) -> Mesh:
	match model:
		"player":
			var c := CapsuleMesh.new()
			c.radius = 0.4
			c.height = 1.8
			return c
		"enemy":
			var s := SphereMesh.new()
			s.radius = 0.5
			s.height = 1.0
			return s
		"coin":
			var cy := CylinderMesh.new()
			cy.top_radius = 0.3
			cy.bottom_radius = 0.3
			cy.height = 0.1
			return cy
		_:
			var b := BoxMesh.new()
			b.size = Vector3.ONE
			return b

static func _fallback_color(model: String) -> Color:
	match model:
		"player": return Color("#4fc3f7")
		"enemy":  return Color("#ff5252")
		"coin":   return Color("#ffd54f")
		_:        return Color("#b0bec5")

static func _pos3(p: Dictionary) -> Vector3:
	var v = p.get("position", null)
	if v is Array and v.size() >= 3:
		return Vector3(_n(v[0], 0.0), _n(v[1], 0.0), _n(v[2], 0.0))
	if v is Array and v.size() >= 2:
		return Vector3(_n(v[0], 0.0), _n(v[1], 0.0), 0.0)
	# Rest on the ground by default: the container carries the layout.
	return Vector3(0.0, 0.6, 0.0)

static func _pos2(p: Dictionary) -> Vector2:
	var v = p.get("position", null)
	if v is Array and v.size() >= 2:
		return Vector2(_n(v[0], 0.0), _n(v[1], 0.0))
	return Vector2.ZERO

# ---------------------------------------------------------------------------
# Overrides
# ---------------------------------------------------------------------------

## Parse "key=value;key=value": split on ';', each item on the FIRST '='.
## Malformed items are skipped with a warning — never fatal.
static func parse_overrides(raw) -> Dictionary:
	var out := {}
	var text := str(raw).replace("\r", " ").replace("\n", " ")
	for item in text.split(";"):
		var s := str(item).strip_edges()
		if s.is_empty():
			continue
		var eq := s.find("=")
		if eq <= 0:
			push_warning("[blueprint] ignoring malformed override '%s' (want key=value)" % s)
			continue
		var k := s.substr(0, eq).strip_edges()
		var v := s.substr(eq + 1).strip_edges()
		if k.is_empty():
			push_warning("[blueprint] ignoring override with an empty key: '%s'" % s)
			continue
		out[k] = v
	return out

## Apply overrides to one instance's template copy. A key naming a param on
## any template brick rewrites it everywhere it appears ("model" is the
## spawn model; "speed", "intensity", ... are ordinary params). An unknown
## key warns ONCE per instance and is ignored.
static func _apply_overrides(brick: Dictionary, overrides: Dictionary, bp_name: String) -> void:
	if overrides.is_empty():
		return
	var p := FeatureCtx.params(brick)
	for key in overrides.keys():
		var k := str(key)
		if p.has(k):
			p[k] = _coerce(overrides[key], p[k])
		else:
			push_warning("[blueprint] override '%s' matches no param on blueprint '%s' — ignored" % [k, bp_name])

## Coerce an override string to the type the param already holds, so a
## numeric param stays numeric and a bool param stays a bool.
static func _coerce(value, current) -> Variant:
	var s := str(value)
	if current is bool:
		return s.to_lower() in ["true", "1", "yes"]
	if current is float:
		return float(s) if s.is_valid_float() else current
	if current is int:
		return int(roundf(float(s))) if s.is_valid_float() else current
	return s

# ---------------------------------------------------------------------------
# Layout — deterministic, no randf, no wall-clock, no filesystem
# ---------------------------------------------------------------------------

static func _offset_2d(i: int, count: int, layout: String, spread: float, rows: int) -> Vector2:
	var step := spread * PX_PER_SPREAD
	match layout:
		"column":
			return Vector2(0.0, float(i) * step)
		"grid":
			var cols := maxi(int(ceil(float(count) / float(rows))), 1)
			return Vector2(float(i % cols) * step, float(i / cols) * step)
		"ring":
			var radius := step * float(count) / TAU
			var a := TAU * float(i) / float(maxi(count, 1))
			return Vector2(cos(a) * radius, sin(a) * radius)
		_:
			return Vector2(float(i) * step, 0.0)

static func _offset_3d(i: int, count: int, layout: String, spread: float, rows: int) -> Vector3:
	var step := spread / CM_PER_SPREAD
	match layout:
		"column":
			return Vector3(0.0, 0.0, float(i) * step)
		"grid":
			var cols := maxi(int(ceil(float(count) / float(rows))), 1)
			return Vector3(float(i % cols) * step, 0.0, float(i / cols) * step)
		"ring":
			var radius := step * float(count) / TAU
			var a := TAU * float(i) / float(maxi(count, 1))
			return Vector3(cos(a) * radius, 0.0, sin(a) * radius)
		_:
			return Vector3(float(i) * step, 0.0, 0.0)

# ---------------------------------------------------------------------------
# The FeatureRegistry seam — the SAME registry the compiler consults
# ---------------------------------------------------------------------------

func _registry():
	# The registry handed to register() is authoritative — feature modules
	# are not in the tree, so the /root path lookup below is only a fallback
	# for a module that somehow never registered.
	if _reg != null and is_instance_valid(_reg) and _reg.has_method("build"):
		return _reg
	var by_path = get_node_or_null("/root/Features")
	if by_path != null and by_path.has_method("registry"):
		return by_path.registry()
	if Engine.has_singleton("Features"):
		var f = Engine.get_singleton("Features")
		if f != null and f.has_method("registry"):
			return f.registry()
	return null

# ---------------------------------------------------------------------------
# Graph accessors (a graph is a BrickGraph object OR a raw Dictionary)
# ---------------------------------------------------------------------------

func _graph(ctx):
	return _ctxv(ctx, "graph", null)

static func _graphv(graph, key: String, default_value):
	if graph == null:
		return default_value
	if graph is Dictionary:
		var v = (graph as Dictionary).get(key)
		return v if v != null else default_value
	return graph.get(key) if graph != null else default_value

static func _conns_of(brick: Dictionary) -> Array:
	var v = brick.get("connections")
	return v if v is Array else []

static func _conn_target(conn) -> String:
	if not (conn is Dictionary):
		return ""
	return str((conn as Dictionary).get("to_brick", ""))

static func _brick_by_id(graph, brick_id: String) -> Dictionary:
	var bricks = _graphv(graph, "bricks", null)
	if not (bricks is Array) or brick_id.is_empty():
		return {}
	for raw in bricks:
		if not (raw is Dictionary):
			continue
		if str((raw as Dictionary).get("id", "")) == brick_id:
			return raw
	return {}

# ---------------------------------------------------------------------------
# Safe readers — a brick may hold anything at all for any key.
# ---------------------------------------------------------------------------

func _claim(b: Dictionary, root: Node) -> bool:
	# Compare by REFERENCE: a new compile builds a brand-new root, and a
	# stale instance id from a freed root would otherwise suppress the build.
	if root != _claimed_root:
		_claimed_root = root
		_claimed.clear()
	var bid := FeatureCtx.bid(b)
	var key := bid if not bid.is_empty() else "anon_%d" % _claimed.size()
	if _claimed.has(key):
		return false
	_claimed[key] = true
	return true

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
	if ctx is Dictionary:
		return bool(ctx.get("is_3d", true))
	if ctx == null:
		return true
	var v = ctx.get("is_3d")
	return bool(v) if v != null else true

static func _clampf(v: float, lo: float, hi: float, fallback: float) -> float:
	if is_nan(v) or is_inf(v):
		return fallback
	return clampf(v, lo, hi)

static func _clampi(v: float, lo: int, hi: int, fallback: int) -> int:
	if is_nan(v) or is_inf(v):
		return fallback
	return clampi(int(roundf(v)), lo, hi)

static func _n(x, fallback: float) -> float:
	if x is float or x is int:
		var f := float(x)
		return fallback if (is_nan(f) or is_inf(f)) else f
	if x is String and str(x).is_valid_float():
		var f2 := float(x)
		return fallback if (is_nan(f2) or is_inf(f2)) else f2
	return fallback

static func _layout_of(v) -> String:
	var s := str(v).strip_edges().to_lower()
	return s if s in LAYOUTS else "row"

## A safe node-name fragment: ASCII letters, digits and underscores only.
static func _clean_name(v) -> String:
	var s := str(v).strip_edges()
	if s.is_empty():
		return "Blueprint"
	var out := ""
	var i := 0
	while i < s.length():
		var ch := s[i]
		if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == "_":
			out += ch
		else:
			out += "_"
		i += 1
	return out
