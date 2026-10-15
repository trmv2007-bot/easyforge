extends Node
## perceive — the Perception brick: enemies that can actually NOTICE you.
##
## WHY: today an enemy either charges blindly (Follow) or slides on a fixed
## path (Patrol). Nothing can "see", so there is no tension — the difference
## between a prop and an opponent is whether it reacts to YOU. This brick adds
## a sight cone, hearing, line-of-sight and short-term memory, so "hide behind
## the wall / sneak past / get spotted" all become expressible without a
## single logic brick.
##
## Registered kind: "perceive". Builds ONE Node named "PerceptionCenter" on the
## scene root (reused by every Perception brick in the graph — never a
## duplicate). The center ticks every physics frame and evaluates every
## registered perceiver.
##
## NODES CREATED
##   3D -> Node "PerceptionCenter" on the root (the generated evaluator)
##        + MeshInstance3D "VisionCone_<id>" as a CHILD OF THE PERCEIVER
##          (an ArrayMesh triangle fan — apex at the perceiver, arc at
##          sight_range, width = sight_angle; translucent gold, double-sided)
##   2D -> Node "PerceptionCenter" on the root
##        + Polygon2D "VisionCone_<id>" as a CHILD OF THE PERCEIVER (arc fan)
##
## THE CONE IS ALWAYS A CHILD OF THE PERCEIVER, NEVER A ROOT CHILD. The smoke
## test scans the root's direct children for Label3D/Label placeholders (a
## Label there means a module failed to build). Hanging the cone off the
## perceiver is also the correct scene structure — it moves and rotates with
## the enemy, which is the entire point of "I can SEE what my enemy can see".
##
## WHO PERCEIVES (resolved in the center's _ready, re-resolved if the owner is
## ever freed): the nearest node in group "enemy" (what the Pathfind brick
## puts there), else a node named "Enemy" (the Enemy Patrol brick), else the
## player, else a small standalone marker node the center creates itself.
## "Nearest" is measured from the player when a player exists, otherwise from
## the brick's position default — so with several enemies each perceiver binds
## the one closest to the action.
##
## DETECTION ORDER (per perceiver, per physics frame):
##   1. distance <= hearing_range (hearing_range > 0) -> detected. Hearing
##      ignores facing and line-of-sight entirely: it is the fallback.
##   2. distance <= sight_range AND the angle between the perceiver's facing
##      and the direction to the player is within sight_angle/2
##      (sight_angle 360 always passes) AND, when needs_line_of_sight, a ray
##      from perceiver to player hits nothing first.
##   LOS uses PhysicsDirectSpaceState2D/3D.intersect_ray (reliable in 4.7,
##      tree-independent — no RayCast nodes) with the perceiver's and the
##      player's own body RIDs excluded so they never block their own ray.
##
## MEMORY: a detection stamps last_seen (Time.get_ticks_msec, so it stays
## deterministic). While now - last_seen <= memory_seconds the enemy stays
## alerted even after losing sight; memory_seconds 0 drops immediately.
##
## OUTPUTS (all through the GameState autoload, by name):
##   set_var(alert_var, true/false) every tick.
##   emit_event(event_name, {spotter: id, target: position}) ONLY on the
##      false->true transition (edge-triggered — otherwise listeners are
##      spammed every frame).
##   on_notice = chase  -> also set_var("__perceive_chase", true) on the rising
##      edge and false on the falling edge, so a Pathfind/State brick can
##      consume it as a clean level signal.
##   on_notice = set_var -> also set_var(alert_var, 1.0) on the rising edge.
##
## HARDENING: no player, no enemy, sight_angle 360, memory_seconds 0, null
## params, junk-typed params and a missing GameState all degrade to "not
## detected" — nothing throws and every generated script compiles. 2D ranges
## are scaled by PX_PER_UNIT (12) because 2D levels work in pixels, exactly
## like the Pathfind brick.
##
## INTEGRATOR NOTES (no edit needed in this file): brick.gd needs a "perceive"
## kind in BrickRef.KIND (in: FLOW, out: EVENT, label "Perception", icon 👁️)
## and this param schema in PARAM_SCHEMA:
##   sight_range        number 2.0..60.0  step 1.0  default 12.0
##   sight_angle        number 20.0..360.0 step 5.0 default 90.0
##   hearing_range      number 0.0..30.0  step 1.0  default 6.0  (0 = deaf)
##   needs_line_of_sight bool                    default true
##   memory_seconds     number 0.0..20.0  step 1.0  default 5.0
##   show_cone          bool                     default true
##   alert_var          text                     default "enemy_alert"
##   on_notice          choice [none, chase, emit_event, set_var]
##                                                default "emit_event"
##   event_name         text                     default "player_spotted"

const KIND := "perceive"
const FeatureCtx = preload("res://src/compiler/feature_ctx.gd")

const SIGHT_MIN := 2.0
const SIGHT_MAX := 60.0
const ANGLE_MIN := 20.0
const ANGLE_MAX := 360.0
const HEAR_MIN := 0.0
const HEAR_MAX := 30.0
const MEM_MIN := 0.0
const MEM_MAX := 20.0
const PX_PER_UNIT := 12.0          # 3D-unit -> 2D-pixel scale (Platform brick)
const CENTER_NAME := "PerceptionCenter"
const CHASE_VAR := "__perceive_chase"
const DEFAULT_ALERT_VAR := "enemy_alert"
const DEFAULT_EVENT := "player_spotted"
const NOTICE_ACTIONS := ["none", "chase", "emit_event", "set_var"]

# The compiler offers every brick to the registry in pass 1 and again in pass
# 2. Remember which bricks this module already built for the current root so
# one Perception brick never registers twice.
var _built := {}
var _built_root_id := 0

func register(reg) -> void:
	if reg != null and reg.has_method("register"):
		reg.register(KIND, _build)
	if reg != null and reg.has_method("register_seeder"):
		reg.register_seeder(KIND, _seed)

# ---------------------------------------------------------------------------
# Seeder — the alert var exists (false) before the first tick, so a Rule or a
# Watch brick can read it from frame zero.
# ---------------------------------------------------------------------------
func _seed(b: Dictionary, state, ctx) -> void:
	if state == null or not state.has_method("set_var"):
		return
	var alert_var := _clean(FeatureCtx.bstr(b, "alert_var", DEFAULT_ALERT_VAR))
	if alert_var.is_empty():
		alert_var = DEFAULT_ALERT_VAR
	state.set_var(alert_var, false)

# ---------------------------------------------------------------------------
# Builder
# ---------------------------------------------------------------------------
func _build(b: Dictionary, root: Node, ctx) -> void:
	if root == null or not is_instance_valid(root):
		return
	if not (b is Dictionary) or not _claim(b, root):
		return

	var is3 := bool(_ctxv(ctx, "is_3d", root is Node3D))
	var p := FeatureCtx.params(b)
	var bid := FeatureCtx.bid(b)

	# --- params: every read defensive; junk clamps to a sane value --------
	var sight_range := clampf(FeatureCtx.bnum(b, "sight_range", 12.0), SIGHT_MIN, SIGHT_MAX)
	var sight_angle := clampf(FeatureCtx.bnum(b, "sight_angle", 90.0), ANGLE_MIN, ANGLE_MAX)
	var hearing := clampf(FeatureCtx.bnum(b, "hearing_range", 6.0), HEAR_MIN, HEAR_MAX)
	var needs_los := FeatureCtx.bbool(b, "needs_line_of_sight", true)
	var memory := clampf(FeatureCtx.bnum(b, "memory_seconds", 5.0), MEM_MIN, MEM_MAX)
	var show_cone := FeatureCtx.bbool(b, "show_cone", true)
	var alert_var := _clean(FeatureCtx.bstr(b, "alert_var", DEFAULT_ALERT_VAR))
	if alert_var.is_empty():
		alert_var = DEFAULT_ALERT_VAR
	var on_notice := FeatureCtx.bstr(b, "on_notice", "emit_event").to_lower()
	if not on_notice in NOTICE_ACTIONS:
		on_notice = "emit_event"
	var event_name := _clean(FeatureCtx.bstr(b, "event_name", DEFAULT_EVENT))
	if event_name.is_empty():
		event_name = DEFAULT_EVENT

	# 2D levels work in pixels; scale the ranges so one slider means the same
	# reach in both dimensions (same convention as the Pathfind brick).
	if not is3:
		sight_range = sight_range * PX_PER_UNIT
		hearing = hearing * PX_PER_UNIT

	var marker_pos := _marker_pos(p, is3)

	# --- one PerceptionCenter per root, reused by every Perception brick ---
	var center: Node = root.get_node_or_null(CENTER_NAME)
	if center == null:
		center = Node.new()
		center.name = CENTER_NAME
		var cfg := _cfg(bid, sight_range, sight_angle, hearing, needs_los,
			memory, show_cone, alert_var, on_notice, event_name)
		var src := _center_source(is3, marker_pos, [cfg])
		if _attach(center, src) != OK:
			push_warning("[perceive] PerceptionCenter script failed to compile; brick dropped")
			center.free()
			return
		root.add_child(center)
	else:
		# a second Perception brick reuses the center and registers its own
		# perceiver on it (each keeps its own owner, cone and alert var)
		var cfg2 := _cfg(bid, sight_range, sight_angle, hearing, needs_los,
			memory, show_cone, alert_var, on_notice, event_name)
		if center.has_method("_register_perceiver"):
			center.call("_register_perceiver", cfg2)

# ---------------------------------------------------------------------------
# One perceiver config, as a GDScript dictionary literal.
# ---------------------------------------------------------------------------
func _cfg(bid: String, sight_range: float, sight_angle: float, hearing: float,
		needs_los: bool, memory: float, show_cone: bool, alert_var: String,
		on_notice: String, event_name: String) -> String:
	return "{%s}" % ", ".join([
		"%s: %s" % [_q("id"), _q(bid)],
		"%s: %f" % [_q("sight_range"), sight_range],
		"%s: %f" % [_q("sight_angle"), sight_angle],
		"%s: %f" % [_q("hearing_range"), hearing],
		"%s: %s" % [_q("needs_los"), "true" if needs_los else "false"],
		"%s: %f" % [_q("memory"), memory],
		"%s: %s" % [_q("show_cone"), "true" if show_cone else "false"],
		"%s: %s" % [_q("alert_var"), _q(alert_var)],
		"%s: %s" % [_q("on_notice"), _q(on_notice)],
		"%s: %s" % [_q("event_name"), _q(event_name)],
	])

func _marker_pos(p: Dictionary, is3: bool) -> String:
	if is3:
		var v := _vec3_of(p.get("position", null), Vector3(6.0, 1.0, 0.0))
		return "Vector3(%f, %f, %f)" % [v.x, v.y, v.z]
	var v2 := _vec2_of(p.get("position", null), Vector2(500.0, 250.0))
	return "Vector2(%f, %f)" % [v2.x, v2.y]

# ---------------------------------------------------------------------------
# The generated PerceptionCenter script
#
# A plain Node on the root. It owns a table of perceivers (one per Perception
# brick) and evaluates every one of them each physics frame: sight cone,
# hearing fallback, ray line-of-sight, memory window, edge-triggered event.
# ---------------------------------------------------------------------------
func _center_source(is3: bool, marker_pos: String, cfgs: Array) -> String:
	var L: Array[String] = []
	L.append("extends Node")
	L.append("# Generated by EasyForge from a 'Perception' brick.")
	L.append("# The graph owns this file — edit the brick, never the code.")
	L.append("# Sight cone + hearing + line-of-sight + memory for enemies.")
	L.append("const IS_3D := %s" % ("true" if is3 else "false"))
	L.append("const CONFIGS: Array = [%s]" % ", ".join(cfgs))
	L.append("const CHASE_VAR := %s" % _q(CHASE_VAR))
	L.append("const MARKER_POS := %s" % marker_pos)
	L.append("const ALL_LAYERS := 0xFFFFFFFF")
	L.append("const CONE_SEGS := 24")
	L.append("")
	L.append("var _perceivers: Array = []")
	L.append("var _gs = null")
	L.append("")
	L.append("func _ready() -> void:")
	L.append("\t_gs = get_node_or_null(\"/root/GameState\")")
	L.append("\tfor cfg in CONFIGS:")
	L.append("\t\t_register_perceiver(cfg)")
	L.append("")
	# --- registration: resolve the owner and hang the cone off it ---------
	L.append("func _register_perceiver(cfg: Dictionary) -> void:")
	L.append("\tvar p := {")
	L.append("\t\t\"id\": str(cfg.get(\"id\", \"\")),")
	L.append("\t\t\"sight_range\": float(cfg.get(\"sight_range\", 12.0)),")
	L.append("\t\t\"sight_angle\": float(cfg.get(\"sight_angle\", 90.0)),")
	L.append("\t\t\"hearing_range\": float(cfg.get(\"hearing_range\", 0.0)),")
	L.append("\t\t\"needs_los\": bool(cfg.get(\"needs_los\", true)),")
	L.append("\t\t\"memory\": float(cfg.get(\"memory\", 0.0)),")
	L.append("\t\t\"show_cone\": bool(cfg.get(\"show_cone\", true)),")
	L.append("\t\t\"alert_var\": str(cfg.get(\"alert_var\", %s))," % _q(DEFAULT_ALERT_VAR))
	L.append("\t\t\"on_notice\": str(cfg.get(\"on_notice\", \"emit_event\")),")
	L.append("\t\t\"event_name\": str(cfg.get(\"event_name\", %s))," % _q(DEFAULT_EVENT))
	L.append("\t\t\"owner\": null,")
	L.append("\t\t\"alerted\": false,")
	L.append("\t\t\"last_seen\": -1.0,")
	L.append("\t}")
	L.append("\t_perceivers.append(p)")
	L.append("\t_bind_owner(p)")
	L.append("")
	# --- the per-frame evaluation ------------------------------------------
	L.append("func _physics_process(_delta: float) -> void:")
	L.append("\tif _gs == null:")
	L.append("\t\t_gs = get_node_or_null(\"/root/GameState\")")
	L.append("\tif _gs == null:")
	L.append("\t\treturn")
	L.append("\tif bool(_gs.game_over):")
	L.append("\t\treturn")
	L.append("\tvar target = _find_player()")
	L.append("\tvar now_ms := float(Time.get_ticks_msec())")
	L.append("\tfor p in _perceivers:")
	L.append("\t\t_tick(p, target, now_ms)")
	L.append("")
	L.append("func _tick(p: Dictionary, target, now_ms: float) -> void:")
	L.append("	var owner = p.get(\"owner\")")
	L.append("	if owner == null or not is_instance_valid(owner):")
	L.append("		_bind_owner(p)")
	L.append("		owner = p.get(\"owner\")")
	L.append("		if owner == null:")
	L.append("			_apply_alert(p, false, null)")
	L.append("			return")
	L.append("	if target == null or not is_instance_valid(target):")
	L.append("		_apply_alert(p, false, null)")
	L.append("		return")
	L.append("	if target == owner:")
	L.append("		# the compiler promotes the first spawn to the player when no")
	L.append("		# player model exists, so the perceiver can BE the target —")
	L.append("		# you cannot see yourself.")
	L.append("		_apply_alert(p, false, null)")
	L.append("		return")
	L.append("	var detected := false")
	L.append("\tvar dist := _distance(owner, target)")
	L.append("\tvar hear := float(p.get(\"hearing_range\", 0.0))")
	L.append("\tif hear > 0.0 and dist <= hear:")
	L.append("\t\tdetected = true   # hearing ignores facing and walls")
	L.append("\telif dist <= float(p.get(\"sight_range\", 0.0)) and _in_cone(owner, target, float(p.get(\"sight_angle\", 90.0))):")
	L.append("\t\tif not bool(p.get(\"needs_los\", true)) or _has_los(owner, target):")
	L.append("\t\t\tdetected = true")
	L.append("\tvar alerted := false")
	L.append("\tif detected:")
	L.append("\t\tp[\"last_seen\"] = now_ms")
	L.append("\t\talerted = true")
	L.append("\telse:")
	L.append("\t\tvar mem := float(p.get(\"memory\", 0.0))")
	L.append("\t\tvar last := float(p.get(\"last_seen\", -1.0))")
	L.append("\t\tif mem > 0.0 and last >= 0.0 and (now_ms - last) <= mem * 1000.0:")
	L.append("\t\t\talerted = true   # still remembering where it last saw you")
	L.append("\t_apply_alert(p, alerted, target)")
	L.append("")
	# --- outputs: var every tick, event + notice action on the edge --------
	L.append("func _apply_alert(p: Dictionary, alerted: bool, target) -> void:")
	L.append("\tif _gs == null:")
	L.append("\t\treturn")
	L.append("\tvar prev := bool(p.get(\"alerted\", false))")
	L.append("\tp[\"alerted\"] = alerted")
	L.append("\t_gs.set_var(str(p.get(\"alert_var\", %s)), alerted)" % _q(DEFAULT_ALERT_VAR))
	L.append("\tif alerted and not prev:")
	L.append("\t\t_gs.emit_event(str(p.get(\"event_name\", %s)), {\"spotter\": str(p.get(\"id\", \"\")), \"target\": _pos_of(target)})" % _q(DEFAULT_EVENT))
	L.append("\t\tmatch str(p.get(\"on_notice\", \"emit_event\")):")
	L.append("\t\t\t\"chase\":")
	L.append("\t\t\t\t_gs.set_var(CHASE_VAR, true)")
	L.append("\t\t\t\"set_var\":")
	L.append("\t\t\t\t_gs.set_var(str(p.get(\"alert_var\", %s)), 1.0)" % _q(DEFAULT_ALERT_VAR))
	L.append("\telif not alerted and prev:")
	L.append("\t\t# the level signal drops with the alert so it stays consumable")
	L.append("\t\t_gs.set_var(CHASE_VAR, false)")
	L.append("")
	# --- owner resolution ---------------------------------------------------
	L.append("func _bind_owner(p: Dictionary) -> void:")
	L.append("\tvar owner = _resolve_owner(p)")
	L.append("\tp[\"owner\"] = owner")
	L.append("\tif owner != null:")
	L.append("\t\t_ensure_cone(p, owner)")
	L.append("")
	L.append("func _resolve_owner(p: Dictionary):")
	L.append("	var t = get_tree()")
	L.append("	var pl = _find_player()")
	L.append("	var anchor = _pos_of(pl)")
	L.append("	if anchor == null:")
	L.append("		anchor = MARKER_POS")
	L.append("	var best = null")
	L.append("	var best_d := 1.0e12")
	L.append("	if t != null:")
	L.append("		for e in t.get_nodes_in_group(\"enemy\"):")
	L.append("			if e == null or not is_instance_valid(e):")
	L.append("				continue")
	L.append("			var ep = _pos_of(e)")
	L.append("			if ep == null:")
	L.append("				continue")
	L.append("			var d = ep.distance_to(anchor)")
	L.append("			if d < best_d:")
	L.append("				best_d = d")
	L.append("				best = e")
	L.append("	if best != null:")
	L.append("		return best")
	L.append("	# the Enemy Patrol brick names its node \"Enemy\" and never adds it")
	L.append("	# to a group, so look it up on OUR OWN ROOT — not current_scene,")
	L.append("	# which in the app is the editor UI, not the game being played.")
	L.append("	var scene = get_parent()")
	L.append("	if scene != null:")
	L.append("		var named = scene.get_node_or_null(\"Enemy\")")
	L.append("		if named != null and is_instance_valid(named):")
	L.append("			return named")
	L.append("	if pl != null:")
	L.append("		return pl")
	L.append("	return _make_marker(str(p.get(\"id\", \"\")))")
	L.append("")
	L.append("func _make_marker(id: String):")
	L.append("\tvar m: Node = Node3D.new() if IS_3D else Node2D.new()")
	L.append("\tm.name = \"Perceiver\" if id.is_empty() else \"Perceiver_%s\" % id")
	L.append("\tm.position = MARKER_POS")
	L.append("\tvar parent = get_parent()")
	L.append("\tif parent != null:")
	L.append("\t\tparent.add_child(m)")
	L.append("\treturn m")
	L.append("")
	# --- target lookup ------------------------------------------------------
	L.append("func _find_player():")
	L.append("	var t = get_tree()")
	L.append("	if t == null:")
	L.append("		return null")
	L.append("	var p = t.get_first_node_in_group(\"player\")")
	L.append("	if p != null and is_instance_valid(p):")
	L.append("		return p")
	L.append("	var scene = get_parent()")
	L.append("	if scene != null:")
	L.append("		var n = scene.get_node_or_null(\"Player\")")
	L.append("		if n != null and is_instance_valid(n):")
	L.append("			return n")
	L.append("	return null")
	L.append("")
	# --- geometry helpers ---------------------------------------------------
	L.append("func _pos_of(n):")
	L.append("\tif n == null:")
	L.append("\t\treturn null")
	L.append("\tif IS_3D:")
	L.append("\t\tvar n3 = n as Node3D")
	L.append("\t\treturn n3.global_position if n3 != null else null")
	L.append("\tvar n2 = n as Node2D")
	L.append("\treturn n2.global_position if n2 != null else null")
	L.append("")
	L.append("func _distance(a, b) -> float:")
	L.append("\tif a == null or b == null:")
	L.append("\t\treturn 1.0e12")
	L.append("\tvar pa = _pos_of(a)")
	L.append("\tvar pb = _pos_of(b)")
	L.append("\tif pa == null or pb == null:")
	L.append("\t\treturn 1.0e12")
	L.append("\treturn pa.distance_to(pb)")
	L.append("")
	L.append("func _in_cone(owner, target, angle_deg: float) -> bool:")
	L.append("\tif angle_deg >= 359.0:")
	L.append("\t\treturn true   # 360 = sees everything")
	L.append("\tvar half := deg_to_rad(clampf(angle_deg, 0.0, 360.0) * 0.5)")
	L.append("\tif half <= 0.0:")
	L.append("\t\treturn false")
	L.append("\tvar op = _pos_of(owner)")
	L.append("\tvar tp = _pos_of(target)")
	L.append("\tif op == null or tp == null:")
	L.append("\t\treturn false")
	L.append("\tif IS_3D:")
	L.append("\t\tvar f: Vector3 = -(owner as Node3D).global_transform.basis.z")
	L.append("\t\tf.y = 0.0")
	L.append("\t\tvar d: Vector3 = tp - op")
	L.append("\t\td.y = 0.0")
	L.append("\t\tif f.length() < 0.001 or d.length() < 0.001:")
	L.append("\t\t\treturn true")
	L.append("\t\treturn absf(f.normalized().angle_to(d.normalized())) <= half + 0.001")
	L.append("\tvar f2: Vector2 = Vector2(cos((owner as Node2D).global_rotation), sin((owner as Node2D).global_rotation))")
	L.append("\tvar d2: Vector2 = tp - op")
	L.append("\tif d2.length() < 0.001:")
	L.append("\t\treturn true")
	L.append("\treturn absf(f2.angle_to(d2.normalized())) <= half + 0.001")
	L.append("")
	# --- line of sight -------------------------------------------------------
	L.append("func _has_los(owner, target) -> bool:")
	L.append("\tvar op = _pos_of(owner)")
	L.append("\tvar tp = _pos_of(target)")
	L.append("\tif op == null or tp == null:")
	L.append("\t\treturn true   # no geometry known: be generous")
	L.append("\tvar vp = get_viewport()")
	L.append("\tif vp == null:")
	L.append("\t\treturn true")
	L.append("\tif IS_3D:")
	L.append("\t\tvar w3 = vp.find_world_3d()")
	L.append("\t\tif w3 == null:")
	L.append("\t\t\treturn true")
	L.append("\t\tvar space = w3.direct_space_state")
	L.append("\t\tif space == null:")
	L.append("\t\t\treturn true")
	L.append("\t\tvar ex: Array[RID] = []")
	L.append("\t\tvar o3 = owner as CollisionObject3D")
	L.append("\t\tif o3 != null:")
	L.append("\t\t\tex.append(o3.get_rid())")
	L.append("\t\tvar t3 = target as CollisionObject3D")
	L.append("\t\tif t3 != null:")
	L.append("\t\t\tex.append(t3.get_rid())")
	L.append("\t\tvar q := PhysicsRayQueryParameters3D.create(op, tp, ALL_LAYERS, ex)")
	L.append("\t\treturn space.intersect_ray(q).is_empty()")
	L.append("\tvar w2 = vp.find_world_2d()")
	L.append("\tif w2 == null:")
	L.append("\t\treturn true")
	L.append("\tvar space2 = w2.direct_space_state")
	L.append("\tif space2 == null:")
	L.append("\t\treturn true")
	L.append("\tvar ex2: Array[RID] = []")
	L.append("\tvar o2 = owner as CollisionObject2D")
	L.append("\tif o2 != null:")
	L.append("\t\tex2.append(o2.get_rid())")
	L.append("\tvar t2 = target as CollisionObject2D")
	L.append("\tif t2 != null:")
	L.append("\t\tex2.append(t2.get_rid())")
	L.append("\tvar q2 := PhysicsRayQueryParameters2D.create(op, tp, ALL_LAYERS, ex2)")
	L.append("\treturn space2.intersect_ray(q2).is_empty()")
	L.append("")
	# --- the visible cone (a CHILD of the perceiver, never the root) -------
	L.append("func _ensure_cone(p: Dictionary, owner) -> void:")
	L.append("\tif not bool(p.get(\"show_cone\", true)):")
	L.append("\t\treturn")
	L.append("\tif owner == null or not is_instance_valid(owner) or not (owner is Node):")
	L.append("\t\treturn")
	L.append("\tvar id := str(p.get(\"id\", \"\"))")
	L.append("\tvar cone_name := \"VisionCone\" if id.is_empty() else \"VisionCone_%s\" % id")
	L.append("\tvar host := owner as Node")
	L.append("\tvar existing = host.get_node_or_null(cone_name)")
	L.append("\tif existing != null:")
	L.append("\t\treturn")
	L.append("\tvar r := float(p.get(\"sight_range\", 12.0))")
	L.append("\tvar a := float(p.get(\"sight_angle\", 90.0))")
	L.append("\tif IS_3D:")
	L.append("\t\tvar mi := MeshInstance3D.new()")
	L.append("\t\tmi.name = cone_name")
	L.append("\t\tmi.mesh = _cone_mesh_3d(r, a)")
	L.append("\t\tmi.material_override = _cone_material_3d()")
	L.append("\t\thost.add_child(mi)")
	L.append("\telse:")
	L.append("\t\tvar poly := Polygon2D.new()")
	L.append("\t\tpoly.name = cone_name")
	L.append("\t\tpoly.polygon = _cone_poly_2d(r, a)")
	L.append("\t\tpoly.color = Color(1.0, 0.84, 0.31, 0.25)")
	L.append("\t\thost.add_child(poly)")
	L.append("")
	L.append("func _cone_material_3d():")
	L.append("\tvar mat := StandardMaterial3D.new()")
	L.append("\tmat.albedo_color = Color(1.0, 0.84, 0.31, 0.25)")
	L.append("\tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA")
	L.append("\tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED")
	L.append("\tmat.cull_mode = BaseMaterial3D.CULL_DISABLED")
	L.append("\treturn mat")
	L.append("")
	L.append("func _cone_mesh_3d(r: float, angle_deg: float):")
	L.append("\tvar mesh := ArrayMesh.new()")
	L.append("\tvar half := deg_to_rad(clampf(angle_deg, 0.0, 360.0) * 0.5)")
	L.append("\tvar verts := PackedVector3Array()")
	L.append("\tverts.append(Vector3.ZERO)   # apex sits on the perceiver")
	L.append("\tvar i := 0")
	L.append("\twhile i <= CONE_SEGS:")
	L.append("\t\tvar ang := -half + (2.0 * half) * float(i) / float(CONE_SEGS)")
	L.append("\t\tverts.append(Vector3(sin(ang) * r, 0.0, -cos(ang) * r))   # -Z is forward")
	L.append("\t\ti += 1")
	L.append("\tvar idx := PackedInt32Array()")
	L.append("\tvar k := 1")
	L.append("\twhile k < verts.size() - 1:")
	L.append("\t\tidx.append(0)")
	L.append("\t\tidx.append(k)")
	L.append("\t\tidx.append(k + 1)")
	L.append("\t\tk += 1")
	L.append("\tvar arrays := []")
	L.append("\tarrays.resize(ArrayMesh.ARRAY_MAX)")
	L.append("\tarrays[ArrayMesh.ARRAY_VERTEX] = verts")
	L.append("\tarrays[ArrayMesh.ARRAY_INDEX] = idx")
	L.append("\tmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)")
	L.append("\treturn mesh")
	L.append("")
	L.append("func _cone_poly_2d(r: float, angle_deg: float):")
	L.append("\tvar pts := PackedVector2Array()")
	L.append("\tpts.append(Vector2.ZERO)   # apex on the perceiver")
	L.append("\tvar half := deg_to_rad(clampf(angle_deg, 0.0, 360.0) * 0.5)")
	L.append("\tvar i := 0")
	L.append("\twhile i <= CONE_SEGS:")
	L.append("\t\tvar ang := -half + (2.0 * half) * float(i) / float(CONE_SEGS)")
	L.append("\t\tpts.append(Vector2(cos(ang) * r, sin(ang) * r))   # +X is forward")
	L.append("\t\ti += 1")
	L.append("\treturn pts")
	L.append("")
	return "\n".join(L)

# ---------------------------------------------------------------------------
# Shared helpers (mirrors of the other feature modules' defensive readers)
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

static func _clean(s: String) -> String:
	return s.replace("\r", " ").replace("\n", " ").replace("\t", " ").strip_edges()

static func _q(s: String) -> String:
	var clean := _clean(s)
	return "\"" + clean.replace("\\", "\\\\").replace("\"", "\\\"") + "\""

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

func _attach(node: Node, source: String) -> int:
	return FeatureCtx.attach_script(node, source)
