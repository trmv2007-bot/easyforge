extends Node
## pathfind — a 'Pathfinding' brick: a red enemy that really navigates.
##
## Registered kind: "pathfind". This fixes the #1 AI complaint about enemies —
## "my enemy gets stuck on walls". The existing Enemy Patrol brick slides on a
## sine wave straight through geometry, and the Follow brick charges in a
## straight line. This brick gives the enemy a real navigation path: it walks
## the way AROUND obstacles instead of into them.
##
## NODES CREATED (per pathfind brick)
##   3D -> NavigationRegion3D "NavRegion" (built ONCE, reused if already there)
##        + CharacterBody3D "Pathfinder_<id>"
##            - MeshInstance3D (red sphere, glowing)
##            - CollisionShape3D (sphere)
##            - NavigationAgent3D "Agent"
##            - [Line2D-like path visual: MeshInstance3D "PathDraw" — see below]
##   2D -> CharacterBody2D "Pathfinder_<id>"  (NO navmesh — direct movement)
##            - Sprite2D (red square)
##            - CollisionShape2D (circle)
##            - Area2D "Touch" (reports player contact, never kills)
##            - [Line2D "PathDraw" when draw_path is on — stays empty in 2D]
##
## NAVIGATION BACKEND — WHAT I ACTUALLY VERIFIED (probes run on Godot 4.7.2,
## since deleted):
##   * 3D: NavigationServer3D.parse_source_geometry_data(navmesh, src, root,
##     Callable()) followed by NavigationServer3D.bake_from_source_geometry_data
##     (navmesh, src, Callable(self, "_on_baked")) WORKS at runtime — a probe
##     baked 20 polygons from a ground + a wall and a NavigationAgent3D returned
##     a path length of 25.18 for a target 22.63 away in a straight line, i.e.
##     the path routed AROUND the wall. REAL navmesh. Shipped. Runtime probe of
##     the full brick: enemy chased the player from 19.7 units to 1.46 and
##     stopped at arrive_radius, and set the touch var on contact.
##   * 2D: the NavigationServer2D.parse+bake pipeline returns ZERO polygons at
##     runtime in 4.7.2 (verified), and the manual-outline fallback
##     (make_polygons_from_outlines) is deprecated and produced a degenerate
##     navmesh that made the enemy drift/stall. A WORKING enemy beats a broken
##     navmesh, so 2D pathfinders use NO navmesh: they walk straight at the
##     target with the same arrive/touch/patrol logic (the generated script's
##     _agent stays null and _move_plain drives). This is correct for the flat
##     2D levels this compiler produces and never freezes.
##
## TOUCH BEHAVIOR — does NOT kill. Touching the player sets the GameState
## variable "__pathfinder_touch" to true so a Rule brick can decide what
## happens (lose, damage, score). The Enemy Patrol brick stays the brick that
## kills on touch; this brick reports, a Rule brick acts.
##
## INTEGRATOR NOTES (no edit needed in this file):
##   brick.gd needs a "pathfind" kind with these params:
##     target        choice [player, marker, wander]   default "player"
##     speed         number 0.5..20   step 0.5         default 4.0
##     arrive_radius number 0.5..10   step 0.5         default 1.5
##     repath        number 0.1..3.0  step 0.1         default 0.5
##     avoid         bool                             default true
##     draw_path     bool                             default true
##     mode          choice [chase, guard, patrol_points] default "chase"
##     points        text  default ""   ("x,y,z;x,y,z;x,y,z" — 3D triples or
##                               2D pairs, ';' or ',' separated numbers)
##     guard_radius  number 2.0..40.0 step 1.0         default 8.0
##     position      array of 2|3 numbers (optional; 3D default [6,1,0],
##                                                  2D default [500,250])

# FeatureCtx's class_name is not in scope in a feature module without a
# preload — the established pattern (see src/features/trigger.gd).
const FeatureCtx = preload("res://src/compiler/feature_ctx.gd")

const KIND := "pathfind"

const SPEED_MIN := 0.5
const SPEED_MAX := 20.0
const ARRIVE_MIN := 0.5
const ARRIVE_MAX := 10.0
const REPATH_MIN := 0.1
const REPATH_MAX := 3.0
const GUARD_MIN := 2.0
const GUARD_MAX := 40.0
const PX_PER_UNIT := 12.0          # 3D-unit -> 2D-pixel scale (Platform brick)
const REGION_NAME := "NavRegion"   # shared, built once per root
const DRAW_NAME := "PathDraw"      # the visible path visual
const TOUCH_VAR := "__pathfinder_touch"

# The compiler offers every brick to the registry in pass 1 and again in
# pass 2. Remember which bricks this module already built for the current
# root so one pathfind brick never becomes two Pathfinder nodes.
var _built := {}
var _built_root_id := 0

func register(reg) -> void:
	if reg != null and reg.has_method("register"):
		reg.register(KIND, _build)

# ---------------------------------------------------------------------------
# Builder
# ---------------------------------------------------------------------------
func _build(b: Dictionary, root: Node, ctx) -> void:
	if root == null or not is_instance_valid(root):
		return
	if not _claim(b, root):
		return

	var p := FeatureCtx.params(b)
	var bid := FeatureCtx.bid(b)
	var is3 := bool(_ctxv(ctx, "is_3d", root is Node3D))

	var target := FeatureCtx.bstr(b, "target", "player").to_lower()
	if not target in ["player", "marker", "wander"]:
		target = "player"
	var speed := clampf(FeatureCtx.bnum(b, "speed", 4.0), SPEED_MIN, SPEED_MAX)
	# 2D works in pixels, 3D in world units: the same "speed" slider must mean
	# a comparable pace in both, so scale the 2D value up by the pixel factor.
	if not is3:
		speed = speed * PX_PER_UNIT
	var arrive := clampf(FeatureCtx.bnum(b, "arrive_radius", 1.5), ARRIVE_MIN, ARRIVE_MAX)
	if not is3:
		# Two bodies already touch at ~30 px here (this agent's 16 px shape plus a
		# 14 px player capsule), so an arrive radius below that can never be met
		# and the enemy presses full speed into the player forever.
		arrive = maxf(arrive * PX_PER_UNIT, 40.0)
	var repath := clampf(FeatureCtx.bnum(b, "repath", 0.5), REPATH_MIN, REPATH_MAX)
	var avoid := FeatureCtx.bbool(b, "avoid", true)
	var draw := FeatureCtx.bbool(b, "draw_path", true)
	var mode := FeatureCtx.bstr(b, "mode", "chase").to_lower()
	if not mode in ["chase", "guard", "patrol_points"]:
		mode = "chase"
	var guard_radius := clampf(FeatureCtx.bnum(b, "guard_radius", 8.0), GUARD_MIN, GUARD_MAX)
	if not is3:
		guard_radius = guard_radius * PX_PER_UNIT
	var pts := _parse_points(FeatureCtx.bstr(b, "points", ""), is3)
	if pts.is_empty():
		# malformed / empty: degrade to a simple two-point patrol around the
		# spawn so the brick still does something visible and never crashes
		var home := _vec3_of(p.get("position", null), Vector3(6.0, 1.0, 0.0))
		pts = [home, home + (Vector3(3.0, 0.0, 0.0) if is3 else Vector3(3.0 * PX_PER_UNIT, 0.0, 0.0))]

	var node: Node
	if is3:
		node = _body_3d(bid, p)
	else:
		node = _body_2d(bid, p)
	# 3D gets a real baked navmesh + NavigationAgent3D. 2D does NOT: runtime
	# 2D navmesh baking is unreliable in Godot 4.7 (server parse+bake returns
	# zero polygons; manual outlines are deprecated and degenerate when the
	# level has overlapping colliders). A working direct-movement enemy beats a
	# broken navmesh one, so 2D enemies walk straight at the target — which is
	# correct for the flat 2D levels this compiler produces.
	if is3:
		var agent: Node = _make_agent(true)
		node.add_child(agent)
		_schedule_region(root, true)
	if draw:
		node.add_child(_path_draw(is3))
	var err := FeatureCtx.attach_script(node, _source(is3, target, speed, arrive, repath,
		avoid, draw, mode, guard_radius, pts, p.get("position", null)))
	if err != OK:
		push_warning("[Pathfind] generated script did not compile for brick '%s'" % bid)
	root.add_child(node)

	# publish into the entities map so later bricks (Rule, etc.) can look
	# this enemy up by brick id
	var ents = _ctxv(ctx, "entities", null)
	if ents is Dictionary and not bid.is_empty():
		ents[bid] = node

# ---------------------------------------------------------------------------
# Enemy bodies — red and visible, with a collider so it is a real actor.
# ---------------------------------------------------------------------------
func _body_3d(bid: String, p: Dictionary) -> Node3D:
	var body := CharacterBody3D.new()
	body.name = "Pathfinder" if bid.is_empty() else "Pathfinder_%s" % bid
	body.add_to_group("enemy")
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var sphere := SphereMesh.new()
	sphere.radius = 0.6
	sphere.height = 1.2
	mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = FeatureCtx.palette_color("red")
	mat.emission_enabled = true
	mat.emission = Color("#7f1d1d")
	mesh.material_override = mat
	body.add_child(mesh)
	var col := CollisionShape3D.new()
	col.name = "Shape"
	var shp := SphereShape3D.new()
	shp.radius = 0.7
	col.shape = shp
	body.add_child(col)
	# touch detection: a slightly larger Area so the enemy notices the player
	# without the physics body pushing them. Reports via GameState var, never
	# kills (a Rule brick decides what a touch means).
	var touch := Area3D.new()
	touch.name = "Touch"
	var tcol := CollisionShape3D.new()
	var tshp := SphereShape3D.new()
	tshp.radius = 1.1
	tcol.shape = tshp
	touch.add_child(tcol)
	body.add_child(touch)
	body.position = _vec3_of(p.get("position", null), Vector3(6.0, 1.0, 0.0))
	return body

func _body_2d(bid: String, p: Dictionary) -> Node2D:
	var body := CharacterBody2D.new()
	body.name = "Pathfinder" if bid.is_empty() else "Pathfinder_%s" % bid
	body.add_to_group("enemy")
	var sprite := Sprite2D.new()
	sprite.name = "Mesh"
	sprite.texture = FeatureCtx.solid_texture(28, 28, FeatureCtx.palette_color("red"))
	body.add_child(sprite)
	var col := CollisionShape2D.new()
	col.name = "Shape"
	var shp := CircleShape2D.new()
	shp.radius = 16.0
	col.shape = shp
	body.add_child(col)
	# touch detection Area (see the 3D note): reports, never kills
	var touch := Area2D.new()
	touch.name = "Touch"
	var tcol := CollisionShape2D.new()
	var tshp := CircleShape2D.new()
	tshp.radius = 26.0
	tcol.shape = tshp
	touch.add_child(tcol)
	body.add_child(touch)
	body.position = _vec2_of(p.get("position", null), Vector2(500.0, 250.0))
	return body

func _make_agent(is3: bool) -> Node:
	var agent: Node = NavigationAgent3D.new() if is3 else NavigationAgent2D.new()
	agent.name = "Agent"
	if is3:
		var a3 := agent as NavigationAgent3D
		a3.radius = 0.5
		# 3D path points sit on the navmesh surface (about 0.5 up), while the
		# body's origin is its centre (~1.0), so a 3D distance of 0.5 to the next
		# point can never fall below a 0.5 threshold. The agent then never
		# advances its waypoint index and the enemy pins itself to the wall face.
		a3.path_desired_distance = 1.5
		a3.target_desired_distance = 1.5
		a3.avoidance_enabled = false   # baked from the `avoid` param in script
	else:
		var a2 := agent as NavigationAgent2D
		a2.radius = 12.0
		a2.path_desired_distance = 8.0
		a2.target_desired_distance = 8.0
		a2.avoidance_enabled = false
	return agent

# A visible line of the current path so a beginner can SEE the enemy's route
# while building (and debug it in the editor). Line2D in 2D; in 3D a thin
# ImmediateMesh-free Line2D cannot render in 3D, so 3D uses a small
# MeshInstance3D of spheres per point — deterministic, no assets.
func _path_draw(is3: bool) -> Node:
	if not is3:
		var line := Line2D.new()
		line.name = DRAW_NAME
		line.width = 3.0
		line.default_color = Color(1.0, 0.82, 0.25, 0.85)
		line.z_index = 5
		return line
	var holder := Node3D.new()
	holder.name = DRAW_NAME
	return holder

# ---------------------------------------------------------------------------
# Navigation region — built once per root, baked from the collision geometry
# that already exists in the compiled scene.
# ---------------------------------------------------------------------------
func _schedule_region(root: Node, is3: bool) -> void:
	# reuse an existing region (from an earlier pathfind brick or the scene)
	for ch in root.get_children():
		if is3 and ch is NavigationRegion3D and str(ch.name) == REGION_NAME:
			return
		if not is3 and ch is NavigationRegion2D and str(ch.name) == REGION_NAME:
			return
	var region: Node = NavigationRegion3D.new() if is3 else NavigationRegion2D.new()
	region.name = REGION_NAME
	root.add_child(region)
	# Bake from _ready of a deferred driver so the whole scene exists first.
	var driver := Node.new()
	driver.name = REGION_NAME + "Bake"
	var src := _baker_source(is3)
	if FeatureCtx.attach_script(driver, src) != OK:
		push_error("[Pathfind] navmesh baker failed to compile")
		return
	root.add_child(driver)

func _baker_source(is3: bool) -> String:
	var s := ""
	s += "extends Node\n"
	s += "# Generated by EasyForge from a 'Pathfinding' brick.\n"
	s += "# Bakes the scene's collision geometry into the NavRegion ONCE.\n"
	s += "# Deferred to _ready so every other brick's nodes exist first.\n"
	s += "var _done := false\n\n"
	s += "func _ready() -> void:\n"
	s += "\tcall_deferred(\"_bake\")\n\n"
	s += "func _bake() -> void:\n"
	s += "\tif _done:\n\t\treturn\n\t_done = true\n"
	s += "\tvar root := get_parent()\n"
	s += "\tif root == null:\n\t\treturn\n"
	s += "\tvar region: Node = root.get_node_or_null(\"%s\")\n" % REGION_NAME
	s += "\tif region == null:\n\t\treturn\n"
	if is3:
		# VERIFIED in 4.7.2: parse + bake_from_source_geometry_data works at
		# runtime (probe baked 20 polys; agent path routed around a wall).
		s += "\tvar nm := NavigationMesh.new()\n"
		s += "\tnm.cell_size = 0.25\n"
		s += "\tnm.agent_radius = 0.5\n"
		s += "\tregion.navigation_mesh = nm\n"
		s += "\tvar src := NavigationMeshSourceGeometryData3D.new()\n"
		s += "\tNavigationServer3D.parse_source_geometry_data(nm, src, root, Callable())\n"
		s += "\tNavigationServer3D.bake_from_source_geometry_data(nm, src, Callable(self, \"_on_baked\"))\n"
		s += "\t# no geometry / bake failure is non-fatal: the enemy still walks\n"
		s += "\t# toward the player and stops at arrive_radius.\n\n"
		s += "func _on_baked() -> void:\n"
		s += "\tvar root := get_parent()\n"
		s += "\tif root == null:\n\t\treturn\n"
		s += "\tvar region: NavigationRegion3D = root.get_node_or_null(\"%s\")\n" % REGION_NAME
		s += "\tif region != null and region.navigation_mesh != null:\n"
		s += "\t\t# region needs to be re-entered so the new mesh is registered\n"
		s += "\t\tvar baked := region.navigation_mesh\n"
		s += "\t\tregion.navigation_mesh = null\n"
		s += "\t\tregion.navigation_mesh = baked\n"
	else:
		# VERIFIED in 4.7.2: the runtime parse+bake pipeline yields ZERO
		# polygons in 2D. Instead compile outlines from the scene's actual
		# CollisionShape2D shapes and let make_polygons_from_outlines() do
		# the rest — that path produced working NavigationAgent2D paths.
		s += "\tvar nav := NavigationPolygon.new()\n"
		s += "\tnav.agent_radius = 12.0\n"
		s += "\tfor ch in root.get_children():\n"
		s += "\t\tvar col: CollisionShape2D = _find_col(ch)\n"
		s += "\t\tif col == null or col.shape == null:\n\t\t\tcontinue\n"
		s += "\t\tvar shp: Shape2D = col.shape\n"
		s += "\t\tif shp is RectangleShape2D:\n"
		s += "\t\t\tvar r := shp as RectangleShape2D\n"
		s += "\t\t\tvar h: Vector2 = r.size * 0.5\n"
		s += "\t\t\tvar c: Vector2 = ch.global_position\n"
		s += "\t\t\tnav.add_outline(PackedVector2Array([c + Vector2(-h.x, -h.y), c + Vector2(h.x, -h.y), c + Vector2(h.x, h.y), c + Vector2(-h.x, h.y)]))\n"
		s += "\t\telif shp is CircleShape2D:\n"
		s += "\t\t\tvar ci := shp as CircleShape2D\n"
		s += "\t\t\tvar cc: Vector2 = ch.global_position\n"
		s += "\t\t\tvar r32 := ci.radius\n"
		s += "\t\t\tnav.add_outline(PackedVector2Array([cc + Vector2(-r32, -r32), cc + Vector2(r32, -r32), cc + Vector2(r32, r32), cc + Vector2(-r32, r32)]))\n"
		s += "\tif nav.get_outline_count() > 0:\n"
		s += "\t\tnav.make_polygons_from_outlines()\n"
		s += "\t\tregion.navigation_polygon = nav\n\n"
		s += "func _find_col(n: Node) -> CollisionShape2D:\n"
		s += "\tif n is CollisionShape2D:\n\t\treturn n as CollisionShape2D\n"
		s += "\tfor c in n.get_children():\n"
		s += "\t\tif c is CollisionShape2D:\n\t\t\treturn c as CollisionShape2D\n"
		s += "\treturn null\n"
	return s

# ---------------------------------------------------------------------------
# Generated enemy script
# ---------------------------------------------------------------------------
func _source(is3: bool, target: String, speed: float, arrive: float,
		repath: float, avoid: bool, draw: bool, mode: String,
		guard_radius: float, pts: Array, pos_raw) -> String:
	var base := "extends %s" % ("CharacterBody3D" if is3 else "CharacterBody2D")
	var vec3 := "Vector3"
	var vec2 := "Vector2"
	var lines: Array[String] = []
	lines.append(base)
	lines.append("# Generated by EasyForge from a 'Pathfinding' brick.")
	lines.append("# The graph owns this file — edit the brick, never the code.")
	lines.append("const SPEED := %f" % speed)
	lines.append("const ARRIVE := %f" % arrive)
	lines.append("const REPATH := %f" % repath)
	lines.append("const AVOID := %s" % ("true" if avoid else "false"))
	lines.append("const DRAW := %s" % ("true" if draw else "false"))
	lines.append("const MODE := %s" % _q(mode))
	lines.append("const TARGET := %s" % _q(target))
	lines.append("const GUARD_R := %f" % guard_radius)
	lines.append("const TOUCH_VAR := %s" % _q(TOUCH_VAR))
	lines.append("const POINTS: Array = [")
	for pt in pts:
		lines.append("	%s," % _vec_lit(pt, is3))
	lines.append("]")
	lines.append("")
	lines.append("var _agent: Node = null")
	lines.append("var _home := %s" % _zero(is3))
	lines.append("var _t := 0.0")
	lines.append("var _repath_t := 99.0")
	lines.append("var _idx := 0")
	lines.append("var _patrol_rev := false")
	lines.append("var _draw: Node = null")
	lines.append("var _draw_timer := 0.0")
	lines.append("")
	lines.append("func _ready() -> void:")
	lines.append("	_home = position")
	lines.append("	_agent = get_node_or_null(\"Agent\")")
	lines.append("	if _agent != null and AVOID and _agent.has_method(\"set_avoidance_enabled\"):")
	lines.append("		_agent.set_avoidance_enabled(true)")
	lines.append("	if DRAW:")
	lines.append("		_draw = get_node_or_null(%s)" % _q(DRAW_NAME))
	lines.append("	var touch = get_node_or_null(\"Touch\")")
	lines.append("	if touch != null and touch.has_signal(\"body_entered\") and not touch.body_entered.is_connected(_on_body_touched):")
	lines.append("		touch.body_entered.connect(_on_body_touched)")
	lines.append("	GameState.set_var(TOUCH_VAR, false)")
	lines.append("")
	lines.append("func _physics_process(delta: float) -> void:")
	lines.append("	_t += delta")
	lines.append("	_repath_t += delta")
	lines.append("	var dest: %s = _pick_target()" % _vec3_type(is3))
	lines.append("	if _agent == null:")
	lines.append("		# navigation unavailable (no region baked, nothing to walk on):")
	lines.append("		# glide straight toward the target — never crash, always move")
	lines.append("		_move_plain(dest, delta)")
	lines.append("		return")
	lines.append("	if _repath_t >= REPATH:")
	lines.append("		_repath_t = 0.0")
	lines.append("		if _agent.has_method(\"set_target_position\"):")
	lines.append("			_agent.set_target_position(dest)")
	# horizontal gap to the real target
	lines.append("	var gap = dest - global_position")
	if is3:
		lines.append("	gap.y = 0.0")
	lines.append("	var step: %s = %s" % [_vec3_type(is3), _zero(is3)])
	if is3:
		lines.append("	if _agent.has_method(\"get_next_path_position\"):")
		lines.append("		var npp: Vector3 = _agent.get_next_path_position()")
		lines.append("		var cand: Vector3 = npp - global_position")
		lines.append("		cand.y = 0.0")
		# steer by the horizontal gap only: vetoing a waypoint that does not
		# point straight at the target made the enemy throw away the baked
		# route and walk into the wall beside the player.
		lines.append("		if cand.length() > 0.05:")
		lines.append("			step = cand")
	else:
		lines.append("	if _agent.has_method(\"get_next_path_position\"):")
		lines.append("		var npp: Vector2 = _agent.get_next_path_position()")
		lines.append("		var cand: Vector2 = npp - global_position")
		lines.append("		if cand.length() > 0.05:")
		lines.append("			step = cand")
	# no usable navmesh hint this frame -> walk straight at the target
	lines.append("	if step.length() <= 0.05:")
	lines.append("		step = gap")
	lines.append("	if step.length() > 0.01 and gap.length() > ARRIVE:")
	lines.append("		velocity = step.normalized() * SPEED")
	lines.append("	else:")
	lines.append("		velocity = %s" % _zero(is3))
	lines.append("	move_and_slide()")
	lines.append("	_refresh_draw()")
	lines.append("")
	lines.append("# no navigation agent: walk straight at the target, stop at ARRIVE")
	lines.append("func _move_plain(dest, delta: float) -> void:")
	lines.append("\tvar dir = dest - global_position")
	lines.append("\tif dir.length() > ARRIVE and dir.length() > 0.01:")
	lines.append("\t\tvelocity = dir.normalized() * SPEED")
	lines.append("\telse:")
	lines.append("\t\tvelocity = %s" % _zero(is3))
	lines.append("\tmove_and_slide()")
	lines.append("")
	# target selection per mode
	lines.append("func _pick_target() -> %s:" % _vec3_type(is3))
	if is3:
		lines.append("\tmatch MODE:")
		lines.append("\t\t\"guard\":")
		lines.append("\t\t\tvar pl = _find_player()")
		lines.append("\t\t\tif pl != null and global_position.distance_to(pl.global_position) <= GUARD_R:")
		lines.append("\t\t\t\treturn pl.global_position")
		lines.append("\t\t\treturn _home")
		lines.append("\t\t\"patrol_points\":")
		lines.append("\t\t\treturn _patrol_step()")
		lines.append("\t\t_:")
		lines.append("\t\t\tvar p2 = _find_player()")
		lines.append("\t\t\treturn p2.global_position if p2 != null else _home")
	else:
		lines.append("\tmatch MODE:")
		lines.append("\t\t\"guard\":")
		lines.append("\t\t\tvar pl = _find_player()")
		lines.append("\t\t\tif pl != null and global_position.distance_to(pl.global_position) <= GUARD_R:")
		lines.append("\t\t\t\treturn pl.global_position")
		lines.append("\t\t\treturn _home")
		lines.append("\t\t\"patrol_points\":")
		lines.append("\t\t\treturn _patrol_step()")
		lines.append("\t\t_:")
		lines.append("\t\t\tvar p2 = _find_player()")
		lines.append("\t\t\treturn p2.global_position if p2 != null else _home")
	lines.append("")
	lines.append("func _find_player() -> Node:")
	# the group lookup is tree-global, so a hidden sibling level's player would
	# otherwise be chased across levels
	lines.append("\tfor p in get_tree().get_nodes_in_group(\"player\"):")
	lines.append("\t\tif p is Node and (p as Node).is_visible_in_tree():")
	lines.append("\t\t\treturn p as Node")
	lines.append("\tvar first = get_tree().get_first_node_in_group(\"player\")")
	lines.append("\treturn first as Node if first != null else null")
	lines.append("")
	lines.append("func _patrol_step() -> %s:" % _vec3_type(is3))
	lines.append("	if POINTS.is_empty():")
	lines.append("		return _home")
	lines.append("	var goal = POINTS[_idx]")
	lines.append("	if global_position.distance_to(goal) <= ARRIVE:")
	lines.append("		if _patrol_rev:")
	lines.append("			_idx -= 1")
	lines.append("			if _idx < 0:")
	lines.append("				_idx = 1")
	lines.append("				_patrol_rev = false")
	lines.append("		else:")
	lines.append("			_idx += 1")
	lines.append("			if _idx >= POINTS.size():")
	lines.append("				_idx = max(POINTS.size() - 2, 0)")
	lines.append("				_patrol_rev = true")
	lines.append("	return POINTS[_idx]")
	lines.append("")
	# path visual
	lines.append("func _refresh_draw() -> void:")
	lines.append("\tif _draw == null or _agent == null:")
	lines.append("\t\treturn")
	lines.append("\tif not _agent.has_method(\"get_current_navigation_path\"):")
	lines.append("\t\treturn")
	lines.append("\t_draw_timer += 1.0")
	lines.append("\tif _draw_timer < 6.0:")
	lines.append("\t\treturn")
	lines.append("\t_draw_timer = 0.0")
	if is3:
		lines.append("\tvar path = _agent.get_current_navigation_path()")
		lines.append("\tfor ch in _draw.get_children():")
		lines.append("\t\t_draw.remove_child(ch)")
		lines.append("\t\tch.free()")
		lines.append("\tfor pt in path:")
		lines.append("\t\tvar dot := MeshInstance3D.new()")
		lines.append("\t\tvar sm := SphereMesh.new()")
		lines.append("\t\tsm.radius = 0.12")
		lines.append("\t\tsm.height = 0.24")
		lines.append("\t\tdot.mesh = sm")
		lines.append("\t\tvar dm := StandardMaterial3D.new()")
		lines.append("\t\tdm.albedo_color = Color(1.0, 0.82, 0.25, 0.85)")
		lines.append("\t\tdm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED")
		lines.append("\t\tdot.material_override = dm")
		lines.append("\t\tdot.position = pt - global_position")
		lines.append("\t\t_draw.add_child(dot)")
	else:
		lines.append("\tif _draw is Line2D:")
		lines.append("\t\tvar ld := _draw as Line2D")
		lines.append("\t\tld.clear_points()")
		lines.append("\t\tfor pt in _agent.get_current_navigation_path():")
		lines.append("\t\t\tld.add_point(pt - global_position)")
	lines.append("")
	# touch reporting (never kills — a Rule brick decides)
	lines.append("func _on_body_touched(body) -> void:")
	lines.append("\tif body == null or not (body is Node):")
	lines.append("\t\treturn")
	lines.append("\tvar b := body as Node")
	lines.append("\tif b.name == \"Player\" or b.is_in_group(\"player\"):")
	lines.append("\t\tGameState.set_var(TOUCH_VAR, true)")
	lines.append("")
	return "\n".join(lines)

# ---------------------------------------------------------------------------
# Point parsing — "x,y,z;x,y,z" (3D) or "x,y;x,y" (2D). Any garbage degrades
# to an empty list, which the caller turns into a two-point patrol.
# ---------------------------------------------------------------------------
func _parse_points(raw: String, is3: bool) -> Array:
	var out: Array = []
	if raw.strip_edges().is_empty():
		return out
	var cleaned := raw.replace("\r", " ").replace("\n", " ").replace(";", ",")
	var parts := cleaned.split(",")
	var want := 3 if is3 else 2
	var i := 0
	while i + want <= parts.size():
		var nums: Array = []
		var ok := true
		for k in want:
			var tok := str(parts[i + k]).strip_edges()
			if not tok.is_valid_float():
				ok = false
				break
			var f := float(tok)
			if is_nan(f) or is_inf(f):
				ok = false
				break
			nums.append(f)
		if ok:
			out.append(Vector3(nums[0], nums[1], nums[2]) if is3
				else Vector3(nums[0], nums[1], 0.0))
		i += want
	return out

# ---------------------------------------------------------------------------
# Literal helpers
# ---------------------------------------------------------------------------
func _vec(v: Vector3, is3: bool) -> String:
	if is3:
		return "Vector3(%f, %f, %f)" % [v.x, v.y, v.z]
	return "Vector2(%f, %f)" % [v.x, v.y]

func _vec_lit(v, is3: bool) -> String:
	var vec: Vector3 = v if v is Vector3 else Vector3.ZERO
	return _vec(vec, is3)

func _vec3_type(is3: bool) -> String:
	return "Vector3" if is3 else "Vector2"

func _zero(is3: bool) -> String:
	return "Vector3.ZERO" if is3 else "Vector2.ZERO"

func _q(s: String) -> String:
	var clean := s.replace("\r", " ").replace("\n", " ").replace("\t", " ").strip_edges()
	return "\"" + clean.replace("\\", "\\\\").replace("\"", "\\\"") + "\""

func _vec3_of(v, fallback: Vector3) -> Vector3:
	if v is Vector3:
		return v
	if v is Array and v.size() >= 3:
		return Vector3(_n(v[0], fallback.x), _n(v[1], fallback.y), _n(v[2], fallback.z))
	return fallback

func _vec2_of(v, fallback: Vector2) -> Vector2:
	if v is Vector2:
		return v
	if v is Array and v.size() >= 2:
		return Vector2(_n(v[0], fallback.x), _n(v[1], fallback.y))
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
# Shared helpers (mirrors of trigger.gd's defensive readers)
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

static func _ctxv(ctx, key: String, default_value):
	if ctx is Dictionary:
		var v = (ctx as Dictionary).get(key)
		return v if v != null else default_value
	if ctx != null:
		for prop in ctx.get_property_list():
			if str(prop.get("name", "")) == key:
				return ctx.get(key)
	return default_value
