extends Node
## Trigger Zone — an invisible volume that fires GameState actions when a body
## enters it (and optionally when it leaves).
## Registered kind: "trigger". The compiler consults the feature registry in
## BOTH pass 1 and pass 2, so the builder dedupes on the root's instance id and
## emits exactly one node per brick per compile.
##
## Nodes created:
##   3D -> Area3D "Trigger_<id>" + CollisionShape3D (BoxShape3D | SphereShape3D)
##        [+ MeshInstance3D "Hint" when visible_hint is on]
##   2D -> Area2D "Trigger_<id>" + CollisionShape2D (RectangleShape2D | CircleShape2D)
##        [+ Sprite2D "Hint" when visible_hint is on]
##
## Params the integrator should add to BrickRef.PARAM_SCHEMA["trigger"]:
##   shape        choice [box, sphere]         default "box"
##   size         number 0.5 .. 40 step 0.5    default 4.0   (3D edge length, 2D width)
##   target       choice [player, any, enemy]  default "player"
##   on_enter     text                         default "win" (comma separated verbs)
##   on_exit      text                         default ""    (comma separated verbs)
##   visible_hint bool                         default true
##   once         bool                         default true
##   needs_var    text                         default ""    (gate: fire only when truthy)
##   position     array of 2|3 numbers         (optional; 3D default [6,1,0], 2D [500,250])
##
## Action verbs (same expansion style as the Rule brick):
##   win, lose, hit_stop, slowmo, normal_time, add_score:N, add_var:NAME,
##   set_var:NAME:VALUE, toggle_var:NAME, play_sound:NAME, damage:N, burst:N,
##   wait:SECONDS. Unknown verbs are skipped, never emitted.

const KIND := "trigger"
const SIZE_MIN := 0.5
const SIZE_MAX := 40.0
const PX_PER_UNIT := 12.0   # 3D-unit -> 2D-pixel scale (same as the Platform brick)
const HINT_ALPHA := 0.22

# The Compiler autoload is the parse dependency that pulls FeatureCtx's
# class_name into scope (it declares `const FeatureCtx = preload(...)`).
const FeatureCtx = preload("res://src/compiler/feature_ctx.gd")

# The compiler offers every brick to the registry in pass 1 and again in pass 2.
# Remember which bricks this module already built for the current root so one
# Trigger brick never becomes two Area nodes.
var _built := {}
var _built_root_id := 0

func register(reg) -> void:
	if reg != null and reg.has_method("register"):
		reg.register(KIND, _build)

# ---------------------------------------------------------------------------
# Builder
# ---------------------------------------------------------------------------
func _build(b: Dictionary, root: Node, ctx) -> void:
	if root == null or not (b is Dictionary):
		return
	if not _claim(b, root):
		return

	var is3 := bool(_ctxv(ctx, "is_3d", true))
	var p := FeatureCtx.params(b)
	var bid := FeatureCtx.bid(b)

	var shape := FeatureCtx.bstr(b, "shape", "box").to_lower()
	if shape != "sphere":
		shape = "box"
	var size := clampf(FeatureCtx.bnum(b, "size", 4.0), SIZE_MIN, SIZE_MAX)
	var target := FeatureCtx.bstr(b, "target", "player").to_lower()
	if not target in ["player", "any", "enemy"]:
		target = "player"
	var on_enter := _clean(FeatureCtx.bstr(b, "on_enter", "win"))
	var on_exit := _clean(FeatureCtx.bstr(b, "on_exit", ""))
	var hint := FeatureCtx.bbool(b, "visible_hint", true)
	var once := FeatureCtx.bbool(b, "once", true)
	var needs_var := _clean(FeatureCtx.bstr(b, "needs_var", ""))

	var enter_lines := _expand_verbs(on_enter)
	var exit_lines := _expand_verbs(on_exit)
	var source := _trigger_source(is3, target, needs_var, once, enter_lines, exit_lines)

	var node: Node
	if is3:
		var area := Area3D.new()
		area.name = "Trigger" if bid.is_empty() else "Trigger_%s" % bid
		var col := CollisionShape3D.new()
		col.name = "Shape"
		if shape == "sphere":
			var shp := SphereShape3D.new()
			shp.radius = maxf(size * 0.5, 0.01)
			col.shape = shp
		else:
			var shp := BoxShape3D.new()
			shp.size = Vector3.ONE * size
			col.shape = shp
		area.add_child(col)
		if hint:
			area.add_child(_hint_3d(shape, size))
		area.position = _vec3_of(p.get("position", null), Vector3(6.0, 1.0, 0.0))
		node = area
	else:
		var area := Area2D.new()
		area.name = "Trigger" if bid.is_empty() else "Trigger_%s" % bid
		var px := size * PX_PER_UNIT
		var col := CollisionShape2D.new()
		col.name = "Shape"
		if shape == "sphere":
			var shp := CircleShape2D.new()
			shp.radius = maxf(px * 0.5, 1.0)
			col.shape = shp
		else:
			var shp := RectangleShape2D.new()
			shp.size = Vector2(max(px, 2.0), max(px, 2.0))
			col.shape = shp
		area.add_child(col)
		if hint:
			area.add_child(_hint_2d(px))
		area.position = _vec2_of(p.get("position", null), Vector2(500.0, 250.0))
		node = area

	var err := FeatureCtx.attach_script(node, source)
	if err != OK:
		push_warning("[Trigger] generated script did not compile for brick '%s'" % bid)
	root.add_child(node)

	# Publish into the same entities map the compiler fills for spawns, so a
	# later brick (Rule, Animation, Particles) can look this zone up.
	var ents = _ctxv(ctx, "entities", null)
	if ents is Dictionary and not bid.is_empty():
		ents[bid] = node

# ---------------------------------------------------------------------------
# Generated trigger script
# ---------------------------------------------------------------------------
func _trigger_source(is3: bool, target: String, needs_var: String, once: bool,
		enter_lines: Array[String], exit_lines: Array[String]) -> String:
	var lines: Array[String] = []
	lines.append("extends %s" % ("Area3D" if is3 else "Area2D"))
	lines.append("# Generated by EasyForge from a Trigger Zone brick.")
	lines.append("# The graph owns this file — edit the brick, never the code.")
	lines.append("const _TARGET := %s" % _q(target))
	lines.append("const _NEEDS_VAR := %s" % _q(needs_var))
	lines.append("const _ONCE := %s" % ("true" if once else "false"))
	lines.append("var _fired_enter := false")
	lines.append("var _fired_exit := false")
	lines.append("")
	lines.append("func _ready():")
	lines.append("\tif has_signal(\"body_entered\") and not body_entered.is_connected(_on_enter):")
	lines.append("\t\tbody_entered.connect(_on_enter)")
	if not exit_lines.is_empty():
		lines.append("\tif has_signal(\"body_exited\") and not body_exited.is_connected(_on_exit):")
		lines.append("\t\tbody_exited.connect(_on_exit)")
	lines.append("")
	# who counts as "the thing that entered"
	lines.append("func _is_target(body) -> bool:")
	lines.append("\tif body == null or not (body is Node):")
	lines.append("\t\treturn false")
	lines.append("\tvar b := body as Node")
	lines.append("\tmatch _TARGET:")
	lines.append("\t\t\"player\":")
	lines.append("\t\t\treturn b.name == \"Player\" or b.is_in_group(\"player\")")
	lines.append("\t\t\"enemy\":")
	lines.append("\t\t\treturn b.is_in_group(\"enemy\")")
	lines.append("\treturn true   # \"any\"")
	lines.append("")
	# the gate: game still running + the optional variable is truthy
	lines.append("func _gate_open() -> bool:")
	lines.append("\tif GameState.game_over:")
	lines.append("\t\treturn false")
	lines.append("\tif not _NEEDS_VAR.is_empty():")
	lines.append("\t\tif not bool(GameState.get_var(_NEEDS_VAR, false)):")
	lines.append("\t\t\treturn false")
	lines.append("\treturn true")
	if not enter_lines.is_empty():
		lines.append("")
		lines += _handler("_on_enter", enter_lines, "_fired_enter")
	if not exit_lines.is_empty():
		lines.append("")
		lines += _handler("_on_exit", exit_lines, "_fired_exit")
	lines.append("")
	return "\n".join(lines)

func _handler(fn_name: String, actions: Array[String], latch: String) -> Array[String]:
	var out: Array[String] = []
	out.append("func %s(body):" % fn_name)
	out.append("	if _ONCE and %s:" % latch)
	out.append("		return")
	out.append("	if not _is_target(body):")
	out.append("		return")
	out.append("	if not _gate_open():")
	out.append("		return")
	out.append("	%s = true" % latch)
	for a in actions:
		out.append("	" + a)
	return out

# ---------------------------------------------------------------------------
# Verb expansion — mirrors the Rule brick so both bricks behave the same.
# Every emitted line is a literal, so junk params can never break the parse.
# ---------------------------------------------------------------------------
func _expand_verbs(raw: String) -> Array[String]:
	var lines: Array[String] = []
	var text := raw.replace("\r", " ").replace("\n", " ")
	for raw_verb in text.split(","):
		var verb := raw_verb.strip_edges().to_lower()
		if verb.is_empty():
			continue
		match verb:
			"win":
				lines.append("GameState.check_win()")
			"lose":
				lines.append("GameState.lose()")
			"hit_stop":
				lines.append("GameState.hit_stop(0.08)")
			"slowmo":
				lines.append("GameState.set_time_scale(0.35)")
			"normal_time":
				lines.append("GameState.set_time_scale(1.0)")
			_:
				if verb.begins_with("add_score:"):
					lines.append("GameState.add_score(%d)" % _int_after(verb, "add_score:", 1))
				elif verb.begins_with("damage:"):
					lines.append("GameState.damage(%d)" % _int_after(verb, "damage:", 1))
				elif verb.begins_with("burst:"):
					lines.append("GameState.burst(%d, \"sparkle\", \"gold\", global_position)"
						% _int_after(verb, "burst:", 16))
				elif verb.begins_with("add_var:"):
					var an := _name_after(verb, "add_var:")
					if not an.is_empty():
						lines.append("GameState.add_var(%s, 1)" % _q(an))
				elif verb.begins_with("set_var:"):
					var spec := verb.substr(len("set_var:")).strip_edges()
					var colon := spec.find(":")
					var vn := spec if colon == -1 else spec.substr(0, colon).strip_edges()
					var val := "" if colon == -1 else spec.substr(colon + 1).strip_edges()
					if vn.is_empty():
						continue
					if val.is_empty():
						lines.append("GameState.set_var(%s, 1.0)" % _q(vn))
					elif val.is_valid_float() and not _is_bad_float(val):
						lines.append("GameState.set_var(%s, %s)" % [_q(vn), _num_lit(val)])
					else:
						lines.append("GameState.set_var(%s, %s)" % [_q(vn), _q(val)])
				elif verb.begins_with("toggle_var:"):
					var tn := _name_after(verb, "toggle_var:")
					if not tn.is_empty():
						lines.append("GameState.toggle_var(%s)" % _q(tn))
				elif verb.begins_with("play_sound:"):
					var sn := _name_after(verb, "play_sound:")
					if not sn.is_empty():
						lines.append("GameState.play_sound(%s)" % _q(sn))
				elif verb.begins_with("wait:"):
					var secs := verb.substr(len("wait:")).strip_edges()
					if secs.is_valid_float() and not _is_bad_float(secs):
						lines.append("await get_tree().create_timer(%s).timeout"
							% _num_lit(str(clampf(float(secs), 0.0, 30.0))))
				# anything else: skipped, never emitted
	return lines

static func _int_after(verb: String, prefix: String, fallback: int) -> int:
	var s := verb.substr(prefix.length()).strip_edges()
	if s.is_valid_float() and not _is_bad_float(s):
		var f := float(s)
		if absf(f) < 1e15:
			return int(roundf(f))
	return fallback

static func _name_after(verb: String, prefix: String) -> String:
	return _clean(verb.substr(prefix.length()).strip_edges())

## Canonical numeric literal: "5" -> 5, "5.5" -> 5.500000 (both valid GDScript).
static func _num_lit(s: String) -> String:
	var f := float(s)
	if absf(f) < 1e15 and is_equal_approx(f, roundf(f)):
		return "%d" % int(roundf(f))
	return "%f" % f

static func _is_bad_float(s: String) -> bool:
	var f := float(s)
	return is_nan(f) or is_inf(f)

## Text that ends up inside a generated string literal: no newlines, no edges.
static func _clean(s: String) -> String:
	return s.replace("\r", " ").replace("\n", " ").replace("\t", " ").strip_edges()

static func _q(s: String) -> String:
	return "\"" + _clean(s).replace("\\", "\\\\").replace("\"", "\\\"") + "\""

# ---------------------------------------------------------------------------
# Hint visuals — a faint translucent volume so a beginner can see the zone.
# ---------------------------------------------------------------------------
func _hint_3d(shape: String, size: float) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = "Hint"
	if shape == "sphere":
		var m := SphereMesh.new()
		m.radius = maxf(size * 0.5, 0.01)
		m.height = max(size, 0.02)
		mesh.mesh = m
	else:
		var m := BoxMesh.new()
		m.size = Vector3.ONE * size
		mesh.mesh = m
	var mat := StandardMaterial3D.new()
	var c := FeatureCtx.palette_color("cyan")
	c.a = HINT_ALPHA
	mat.albedo_color = c
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = mat
	return mesh

func _hint_2d(px: float) -> Sprite2D:
	var s := Sprite2D.new()
	s.name = "Hint"
	var c := FeatureCtx.palette_color("cyan")
	c.a = HINT_ALPHA
	var side := maxi(int(px), 4)
	s.texture = FeatureCtx.solid_texture(side, side, c)
	return s

# ---------------------------------------------------------------------------
# Safe readers — a brick may hold anything at all for any key.
# ---------------------------------------------------------------------------
func _claim(b: Dictionary, root: Node) -> bool:
	var rid := root.get_instance_id()
	if rid != _built_root_id:
		_built_root_id = rid
		_built.clear()
	var bid := FeatureCtx.bid(b)
	var key := bid
	if key.is_empty():
		key = "anon_%d" % _built.size()
	if _built.has(key):
		return false
	_built[key] = true
	return true

## Read a key off ctx whether the integrator hands us a Dictionary (what
## Compiler actually passes) or a FeatureCtx object.
static func _ctxv(ctx, key: String, default_value):
	if ctx is Dictionary:
		var v = (ctx as Dictionary).get(key)
		return v if v != null else default_value
	if ctx != null:
		for prop in ctx.get_property_list():
			if str(prop.get("name", "")) == key:
				return ctx.get(key)
	return default_value

static func _n(x, fallback: float) -> float:
	if x is float or x is int:
		var f := float(x)
		return fallback if (is_nan(f) or is_inf(f)) else f
	if x is String and str(x).is_valid_float():
		var f2 := float(x)
		return fallback if (is_nan(f2) or is_inf(f2)) else f2
	return fallback

static func _vec3_of(v, fallback: Vector3) -> Vector3:
	if v is Vector3:
		return v
	if v is Array and v.size() >= 3:
		return Vector3(_n(v[0], fallback.x), _n(v[1], fallback.y), _n(v[2], fallback.z))
	return fallback

static func _vec2_of(v, fallback: Vector2) -> Vector2:
	if v is Vector2:
		return v
	if v is Array and v.size() >= 2:
		return Vector2(_n(v[0], fallback.x), _n(v[1], fallback.y))
	return fallback
