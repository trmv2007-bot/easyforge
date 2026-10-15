extends Node
## hierarchy — entity parenting. Registered kind: "attach".
##
## WHY IT MATTERS: without this brick everything in a compiled game is a
## sibling at the scene root, so "the gun is attached to the enemy" or "the
## hat sits on the player's head" is impossible — anything that must move
## WITH another thing needs hand-written code. The Attach brick reparents one
## entity under another in the compiled scene, so the child inherits the
## parent's transform for free (position, rotation, scale) and every future
## brick that moves the parent carries the child along.
##
## WHAT IT ADDS (both dimensions)
##   kind "attach" -> reparents the CHILD node under the PARENT node in the
##       compiled scene (preserving the child's world transform), then applies
##       the optional `offset` as the child's LOCAL position relative to the
##       parent. Creates no visual node of its own; optionally adds one tiny
##       driver node ("AttachPin") as a child of the child when
##       `follow_position` or `inherit_rotation` is off.
##
## HOW CHILD AND PARENT ARE CHOSEN (the documented rule, in priority order)
##   child  = param `child_brick`  ->  else the brick WIRED INTO this attach
##           brick (an incoming connection, i.e. child -> attach)  ->  else
##           nothing (the brick warns and does nothing).
##   parent = param `parent_brick` ->  else a second wired brick (an outgoing
##           connection attach -> parent, or a second incoming one)  ->  else
##           the player entity (warned).
##   The intended UI flow is: wire the child INTO the attach brick, and name
##   the parent in `parent_brick`. A param accepts a brick id, a brick title
##   ("Enemy"), or a brick kind ("enemy_patrol"), and the lookup also falls
##   back to node names ("Player"), so hand-drawn graphs keep working.
##
## OFFSET SEMANTICS (the one design decision worth reading)
##   `offset` PRESENT  -> the child's local position is SET to the offset, so
##       it snaps to parent + offset (that is what "the hat sits on the head"
##       means). Defaults are [0, 1, 0] in 3D and [0, 40] in 2D.
##   `offset` ABSENT   -> the reparent preserves the child's world transform,
##       so the child keeps its exact authored spot and follows the parent
##       from there.
##
## REPARENTING AND THE SCENE TREE (why keep_global_transform is false)
##   Node.reparent(parent) defaults to keep_global_transform = true, which
##   reads global_transform — and that ERRORS ("Condition !is_inside_tree()")
##   when the node is not in a SceneTree yet, which is exactly the compile
##   situation (compile_graph builds the root detached; the runner adds it
##   afterwards). So the reparent runs with keep_global_transform = false and
##   the world transform is preserved BY HAND: it is a product of the LOCAL
##   transforms up the parent chain, which never touches the SceneTree and
##   therefore never errors:
##       world(child) = Π local transforms from the root down
##       child.transform = world(parent).affine_inverse() * world(child)
##   Verified by probe: the same graphs compile with zero engine errors and
##   the child keeps its exact world spot.
##
## follow_position = false / inherit_rotation = false (generated driver)
##   The child stays under the parent (so it is still "attached") but its
##   WORLD transform is re-pinned every frame by a tiny generated script:
##      3D: child.global_position = captured                      (follow off)
##          child.global_transform = Transform3D(basis, origin)    (rot off)
##      2D: child.global_position = captured                      (follow off)
##          child.global_rotation = captured                       (rot off)
##   WHY NOT top_level: top_level = true detaches the node from its parent's
##   transform entirely, which also changes draw/canvas ordering and scale
##   inheritance. The per-frame pin keeps the child a REAL child (the whole
##   point of the brick) and only restores the world property asked for.
##   Both property names were verified against the real engine (API FACTS).
##
## API FACTS VERIFIED against the real Godot 4.7.2 engine (live probe, then
## deleted — not guessed):
##   - Node.reparent(parent, keep_global_transform) exists; with the default
##     (true) it reads global_transform and ERRORS outside a SceneTree.
##   - Node3D AND Node2D both really expose `global_position`,
##     `global_transform` and `global_rotation` (dumped from the property
##     list). Assigning `global_transform = Transform3D(basis, origin)`
##     restores world ROTATION only and was verified to leave the origin
##     untouched.
##   - A plain Node has NO `visible` property (dumped: false). So
##     `visible = false` is applied only when the child is a Node3D or a
##     CanvasItem.
##   - Godot REFUSES add_child() of a node that already has a parent, and
##     reparent() silently DETACHES the old parent first — so making a child
##     an ancestor of its parent would orphan the parent. The builder checks
##     the ancestor chain itself before reparenting.
##   - Node.find_child(name, true, false) with owned = false is required:
##     runtime-compiled nodes have owner == null, so owned = true would find
##     nothing.
##
## CYCLE HANDLING (hard requirement)
##   All attach edges in the graph are collected into a child -> parent map
##   BEFORE anything is reparented. A walk up each chain detects cycles; in a
##   cycle the attach brick with the smallest brick id is KEPT and the others
##   are dropped with a push_warning naming both things. Self-attach (child ==
##   parent) is dropped the same way. Deterministic: the same graph always
##   breaks the same cycle the same way.
##
## HARDENING
##   - unknown child/parent id, null parent, child == parent, a 2D thing
##     attached to a 3D thing, junk params: never crash, always a warning.
##   - the compiler consults the registry in pass 1 AND pass 2, so this module
##     dedupes per (root, brick id) and retries node resolution on the second
##     pass (genre bricks only exist after pass 1 builds them).
##   - when neither pass can resolve the nodes, a tiny generated "Attach_<id>"
##     fixup node is added to the root that performs the same reparent at
##     _ready, when the whole scene exists. It never crashes if it still
##     cannot find anything.
##
## DETERMINISM: no randf(), no filesystem, no wall-clock. Every generated
## script is a constant table; every tree scan is a deterministic walk.
##
## INTEGRATOR PARAMS (this module only READS them; the integrator adds them to
## brick.gd's PARAM_SCHEMA + KIND):
##   "attach":
##     child_brick      text                                 default ""
##     parent_brick     text                                 default ""
##     offset           array of 2|3 numbers   optional      (3D [0,1,0] / 2D [0,40])
##     inherit_rotation bool                                default true
##     follow_position  bool                                default true
##     visible          bool                                default true
##   KIND entry (port typing follows the established pattern):
##     "attach": {"label": "Attach", "icon": "🔗", "in": [FLOW], "out": []}
##   NOTE: no new IR field is needed — every input lives in brick params, so
##   graph.gd's SCHEMA_VERSION does not have to move.
##   KNOWN LIMITATION: extra levels (graph.levels) are compiled by a separate
##   loop that does not consult the feature registry, so an Attach brick
##   placed inside an extra level is inert (it never crashes; it just does
##   nothing there). Attach works in the main level.

# FeatureCtx's class_name is not in scope in a feature module without an
# explicit preload — the established pattern (see src/features/trigger.gd).
const FeatureCtx = preload("res://src/compiler/feature_ctx.gd")

const KIND := "attach"

# Offset defaults (used only when the param is present but junk).
const DEF_OFFSET_3D := [0.0, 1.0, 0.0]
const DEF_OFFSET_2D := [0.0, 40.0, 0.0]

# The node names compiler.gd gives the genre bricks, which (unlike Spawn and
# the feature modules) never publish themselves into ctx.entities. An Attach
# whose parent/child is one of those bricks is found by scanning the compiled
# tree for these names. Kept small and verified against compiler.gd.
const GENRE_NODE_NAMES := {
	"enemy_patrol": "Enemy",
	"hazard": "Hazard",
	"checkpoint": "Checkpoint",
	"moving_platform": "MovingPlatform",
	"platform": "Platform",
	"door": "Door",
	"camera": "GameCamera",
}

# The compiler offers every brick to the registry in pass 1 AND pass 2.
# Remember which bricks this module already handled for the current root, and
# how many times each was offered, so one Attach brick never reparents twice
# and an unresolved one gets exactly one deferred retry.
var _done := {}
var _attempts := {}
var _done_root_id := 0

func register(reg) -> void:
	if reg == null or not reg.has_method("register"):
		push_error("[hierarchy] no feature registry available")
		return
	reg.register(KIND, _build)

# ---------------------------------------------------------------------------
# Builder
# ---------------------------------------------------------------------------

## One "attach" brick -> reparent the child under the parent.
func _build(b: Dictionary, root: Node, ctx) -> void:
	if root == null or not is_instance_valid(root) or not (b is Dictionary):
		return
	_reset_if_new_root(root)

	var bid := FeatureCtx.bid(b)
	var key := bid if not bid.is_empty() else "anon_%d" % _attempts.size()
	if _done.has(key):
		return
	_attempts[key] = int(_attempts.get(key, 0)) + 1
	# pass 2 is the last chance to resolve nodes; after that, defer to runtime
	var final_chance := int(_attempts.get(key, 0)) >= 2

	var graph = _ctxv(ctx, "graph", null)
	var is3 := _is_3d(ctx, root)
	var specs := _specs(b, ctx, graph)
	var child_brick: Dictionary = specs["child"]
	var parent_brick: Dictionary = specs["parent"]
	var child_param := str(specs.get("child_param", ""))
	var parent_param := str(specs.get("parent_param", ""))

	# --- cycle guard: computed from the whole graph, before any reparent ---
	var dropped := _cycle_dropped(graph)
	if dropped.has(bid):
		push_warning("[hierarchy] Attach '%s' dropped: it would make '%s' and '%s' hold each other (a loop). One of the two must be the parent." % [
			_title(b), str(specs.get("child_label", "?")), str(specs.get("parent_label", "?"))])
		_done[key] = true
		return

	# A param that names nothing the graph contains AND no node by that name
	# is a hard stop: retrying cannot help.
	if not child_param.is_empty() and child_brick.is_empty() \
			and _node_named(child_param, root) == null:
		push_warning("[hierarchy] Attach '%s': no brick or thing called '%s' — nothing to attach." % [_title(b), child_param])
		_done[key] = true
		return
	if not parent_param.is_empty() and parent_brick.is_empty() \
			and _node_named(parent_param, root) == null:
		push_warning("[hierarchy] Attach '%s': no brick or thing called '%s' — nothing attached to." % [_title(b), parent_param])
		_done[key] = true
		return

	var child_node := _resolve_node(child_brick, child_param, ctx, root)
	var parent_node := _resolve_node(parent_brick, parent_param, ctx, root)
	if parent_node == null and parent_param.is_empty() and parent_brick.is_empty():
		# documented fallback: attach to the player when no parent is named
		var pl = _ctxv(ctx, "player", null)
		if pl is Node and is_instance_valid(pl):
			parent_node = pl

	if child_node == null or parent_node == null:
		# nodes not built yet — retry in pass 2, then defer to a runtime fixup
		if final_chance:
			_done[key] = true
			_add_fixup(b, root, specs, is3)
		return
	if parent_node == child_node:
		push_warning("[hierarchy] Attach '%s': that thing would hold itself — nothing attached." % _title(b))
		_done[key] = true
		return

	_done[key] = true
	_do_attach(b, child_node, parent_node, root, is3)

# ---------------------------------------------------------------------------
# The actual reparent + offset + pin
# ---------------------------------------------------------------------------

func _do_attach(b: Dictionary, child: Node, parent: Node, root: Node, is3: bool) -> void:
	if child == null or parent == null:
		return
	if not is_instance_valid(child) or not is_instance_valid(parent):
		return

	var c3 := child is Node3D
	var c2 := child is Node2D
	var p3 := parent is Node3D
	var p2 := parent is Node2D
	if (c3 and p2) or (c2 and p3):
		push_warning("[hierarchy] Attach '%s': a 2D thing cannot hang off a 3D thing (or the other way round) — nothing attached." % _title(b))
		return

	var p := FeatureCtx.params(b)
	var follow := FeatureCtx.bbool(b, "follow_position", true)
	var inherit_rot := FeatureCtx.bbool(b, "inherit_rotation", true)
	var visible := FeatureCtx.bbool(b, "visible", true)
	var has_offset := p.has("offset")
	var off := _offset(p.get("offset", null), is3)

	if not visible:
		_set_visible(child, false)

	if child.get_parent() != parent:
		if _is_ancestor(child, parent):
			push_warning("[hierarchy] Attach '%s': that would make a loop (the parent already hangs off the thing) — nothing attached." % _title(b))
			return
		# reparent with keep_global_transform = false: the default (true)
		# reads global_transform, which ERRORS outside a SceneTree — exactly
		# the compile situation. The world transform is preserved by hand
		# from the local transforms up the chain instead (see the header).
		var cw = _world_xform(child)
		var pw = _world_xform(parent)
		child.reparent(parent, false)
		if c3 and p3:
			(child as Node3D).transform = (pw as Transform3D).affine_inverse() * (cw as Transform3D)
		elif c2 and p2:
			(child as Node2D).transform = (pw as Transform2D).affine_inverse() * (cw as Transform2D)

	if has_offset:
		_set_pos(child, off)

	if not follow or not inherit_rot:
		_add_pin(child, follow, inherit_rot)

## The accumulated world transform of a node, computed ONLY from the local
## transforms up its parent chain — never touches global_transform, so it is
## safe for a node that is not in a SceneTree yet (the compile situation).
func _world_xform(n: Node):
	if n is Node3D:
		var chain: Array[Transform3D] = []
		var p := n
		var guard := 0
		while p != null and guard < 256:
			guard += 1
			if p is Node3D:
				chain.append((p as Node3D).transform)
			p = p.get_parent()
		var t := Transform3D.IDENTITY
		for i in range(chain.size() - 1, -1, -1):
			t = t * chain[i]
		return t
	if n is Node2D:
		var chain2: Array[Transform2D] = []
		var p2 := n
		var guard2 := 0
		while p2 != null and guard2 < 256:
			guard2 += 1
			if p2 is Node2D:
				chain2.append((p2 as Node2D).transform)
			p2 = p2.get_parent()
		var t2 := Transform2D.IDENTITY
		for i in range(chain2.size() - 1, -1, -1):
			t2 = t2 * chain2[i]
		return t2
	return null

# ---------------------------------------------------------------------------
# Spec resolution — which brick is the child, which is the parent
# ---------------------------------------------------------------------------

## Returns {child, parent, child_param, parent_param, child_label, parent_label}.
## `child`/`parent` are brick Dictionaries (possibly empty).
func _specs(b: Dictionary, ctx, graph) -> Dictionary:
	var p := FeatureCtx.params(b)
	var incoming := _incoming_bricks(b, graph)
	var outgoing := _outgoing_bricks(b, graph)

	var child_param := _clean(str(p.get("child_brick", "")))
	var parent_param := _clean(str(p.get("parent_brick", "")))

	var child_brick := {}
	if not child_param.is_empty():
		child_brick = _find_brick_ref(child_param, graph)
	if child_brick.is_empty():
		# a brick wired INTO this one is the child (child -> attach)
		if not incoming.is_empty():
			child_brick = incoming[0]

	var parent_brick := {}
	if not parent_param.is_empty():
		parent_brick = _find_brick_ref(parent_param, graph)
	if parent_brick.is_empty():
		# a second wired brick is the parent (outgoing attach -> parent,
		# or a second incoming one)
		for cand in outgoing:
			if not _same_brick(cand, child_brick):
				parent_brick = cand
				break
	if parent_brick.is_empty():
		for cand in incoming:
			if not _same_brick(cand, child_brick):
				parent_brick = cand
				break

	return {
		"child": child_brick,
		"parent": parent_brick,
		"child_param": child_param,
		"parent_param": parent_param,
		"child_label": _label_of(child_brick),
		"parent_label": _label_of(parent_brick),
	}

## A brick reference (id, title or kind) -> the brick Dictionary, or {}.
func _find_brick_ref(ref: String, graph) -> Dictionary:
	var want := _clean(ref)
	if want.is_empty():
		return {}
	if graph != null and graph.has_method("get_brick"):
		var by_id = graph.get_brick(want)
		if by_id is Dictionary and not (by_id as Dictionary).is_empty():
			return by_id
	var kind_matches := []
	for b in _bricks_of(graph):
		if not (b is Dictionary):
			continue
		var t := _clean(str((b as Dictionary).get("title", "")))
		if not t.is_empty() and t.to_lower() == want.to_lower():
			return b
		if str((b as Dictionary).get("kind", "")).to_lower() == want.to_lower():
			kind_matches.append(b)
	# a KIND name ("enemy_patrol"): deterministic when one brick has it, and
	# the first one (with a warning) when several do — never a random pick.
	if kind_matches.size() == 1:
		return kind_matches[0]
	if kind_matches.size() > 1:
		push_warning("[hierarchy] '%s' matches %d bricks — attaching to the first one." % [want, kind_matches.size()])
		return kind_matches[0]
	return {}

func _incoming_bricks(b: Dictionary, graph) -> Array:
	var out := []
	var bid := FeatureCtx.bid(b)
	if bid.is_empty():
		return out
	for other in _bricks_of(graph):
		if not (other is Dictionary):
			continue
		for c in _conns(other):
			if not (c is Dictionary):
				continue
			if _clean(str((c as Dictionary).get("to_brick", ""))) == bid:
				if graph != null and graph.has_method("get_brick"):
					var t = graph.get_brick(FeatureCtx.bid(other))
					if t is Dictionary and not (t as Dictionary).is_empty():
						out.append(t)
				break
	return out

func _outgoing_bricks(b: Dictionary, graph) -> Array:
	var out := []
	if graph == null or not graph.has_method("get_brick"):
		return out
	for c in _conns(b):
		if not (c is Dictionary):
			continue
		var tid := _clean(str((c as Dictionary).get("to_brick", "")))
		if tid.is_empty():
			continue
		var t = graph.get_brick(tid)
		if t is Dictionary and not (t as Dictionary).is_empty():
			out.append(t)
	return out

# ---------------------------------------------------------------------------
# Node lookup — brick -> the node that brick created
# ---------------------------------------------------------------------------

## Resolve a child/parent to a node: the brick's node if the brick is known,
## otherwise a node the param names directly (e.g. "Enemy", "Platform").
func _resolve_node(brick: Dictionary, param: String, ctx, root: Node) -> Node:
	if not brick.is_empty():
		var n := _node_for_brick(brick, ctx, root)
		if n != null:
			return n
	if not param.is_empty():
		return _node_named(param, root)
	return null

## A node by exact name anywhere under root (runtime-compiled nodes have
## owner == null, so the search must pass owned = false).
func _node_named(name: String, root: Node) -> Node:
	var want := _clean(name)
	if want.is_empty() or root == null or not is_instance_valid(root):
		return null
	var f = root.find_child(want, true, false)
	if f != null and f != root and is_instance_valid(f):
		return f
	var cap := want.capitalize()
	if cap != want:
		var g = root.find_child(cap, true, false)
		if g != null and g != root and is_instance_valid(g):
			return g
	return null

func _node_for_brick(brick: Dictionary, ctx, root: Node) -> Node:
	if brick.is_empty():
		return null
	# 1. the entities map (Spawn bricks and every feature module publish here)
	var ents = _ctxv(ctx, "entities", null)
	if ents is Dictionary:
		var bid := FeatureCtx.bid(brick)
		if not bid.is_empty() and ents.has(bid):
			var n = ents[bid]
			if n is Node and is_instance_valid(n):
				return n
		for cand in _name_candidates(brick):
			for v in ents.values():
				if v is Node and is_instance_valid(v) and str((v as Node).name) == str(cand):
					return v
	# 2. tree scan (genre bricks never publish to ctx.entities).
	#    owned = false is REQUIRED: runtime-compiled nodes have owner == null.
	if root != null and is_instance_valid(root):
		for cand in _name_candidates(brick):
			var f = root.find_child(str(cand), true, false)
			if f != null and f != root and is_instance_valid(f):
				return f
	return null

## The node names a brick might have produced, most specific first.
func _name_candidates(brick: Dictionary) -> Array:
	var out := []
	var bid := FeatureCtx.bid(brick)
	if not bid.is_empty():
		out.append(bid)
	var title := _clean(str(brick.get("title", "")))
	if not title.is_empty():
		out.append(title)
	var kind := str(brick.get("kind", ""))
	if kind == "spawn":
		# Spawn names its node after the model ("player" -> "Player")
		var model := _clean(str(FeatureCtx.params(brick).get("model", "player")))
		if not model.is_empty():
			out.append(model.capitalize())
	else:
		var alias := str(GENRE_NODE_NAMES.get(kind, ""))
		if not alias.is_empty():
			out.append(alias)
	if not kind.is_empty() and not bid.is_empty():
		# feature modules name nodes "<Kind>_<id>" (Trigger_x, Rigid_x, ...)
		out.append("%s_%s" % [kind.capitalize(), bid])
	var uniq := []
	for c in out:
		if not uniq.has(c):
			uniq.append(c)
	return uniq

# ---------------------------------------------------------------------------
# Cycle detection over the whole graph's attach edges
# ---------------------------------------------------------------------------

## Returns the set of attach brick ids that must be DROPPED to break every
## parenting cycle. child_brick_id -> {parent_brick_id, brick_id}. In each
## cycle the attach brick with the smallest id is kept; deterministic.
func _cycle_dropped(graph) -> Dictionary:
	var edges := {}
	for b in _bricks_of(graph):
		if not (b is Dictionary):
			continue
		if str((b as Dictionary).get("kind", "")) != KIND:
			continue
		var specs := _specs(b, null, graph)
		var child_brick: Dictionary = specs["child"]
		var parent_brick: Dictionary = specs["parent"]
		if child_brick.is_empty() or parent_brick.is_empty():
			continue
		var cid := FeatureCtx.bid(child_brick)
		var pid := FeatureCtx.bid(parent_brick)
		if cid.is_empty() or pid.is_empty():
			continue
		if cid == pid:
			continue   # self-attach: caught by the child==parent check later
		edges[cid] = {"parent": pid, "brick": FeatureCtx.bid(b)}

	var dropped := {}
	for start in edges.keys():
		var chain := [start]
		var cur: String = start
		var hit := false
		var loop_back := ""
		var guard := 0
		while guard < 64:
			guard += 1
			var pbid := str(edges.get(cur, {}).get("parent", ""))
			if pbid.is_empty():
				break
			if pbid == start:
				hit = true
				loop_back = start
				break
			if not edges.has(pbid):
				break
			if chain.has(pbid):
				hit = true
				loop_back = pbid
				break
			chain.append(pbid)
			cur = pbid
		if not hit:
			continue
		var idx := chain.find(loop_back)
		var members := chain.slice(idx) if idx >= 0 else chain
		# keep the smallest brick id in the cycle, drop the rest
		var keep := ""
		for m in members:
			var mb := str(edges.get(m, {}).get("brick", ""))
			if not mb.is_empty() and (keep.is_empty() or mb < keep):
				keep = mb
		for m in members:
			var mb2 := str(edges.get(m, {}).get("brick", ""))
			if not mb2.is_empty() and mb2 != keep:
				dropped[mb2] = true
	return dropped

# ---------------------------------------------------------------------------
# The generated world-transform pin (follow_position / inherit_rotation off)
# ---------------------------------------------------------------------------

func _add_pin(child: Node, follow: bool, inherit_rot: bool) -> void:
	var is3 := child is Node3D
	var is2 := child is Node2D
	if not is3 and not is2:
		return   # a plain Node has no world transform to pin
	var drv := Node.new()
	# compile BEFORE it joins the tree so a parse failure never leaves a
	# stray node behind (attach_script sets the script on the node itself)
	if FeatureCtx.attach_script(drv, _pin_source(is3, follow, inherit_rot)) != OK:
		push_error("[hierarchy] attach pin driver failed to compile")
		drv.free()
		return
	drv.name = "AttachPin"
	child.add_child(drv)

func _pin_source(is3: bool, follow: bool, inherit_rot: bool) -> String:
	var L: Array[String] = []
	L.append("extends Node")
	L.append("# Generated by EasyForge from an Attach brick: pins this node's")
	L.append("# parent back to the world transform it had when it was attached,")
	L.append("# so an attached thing keeps its place even when its parent moves.")
	if is3:
		L.append("var _wpos: Vector3")
		if not inherit_rot:
			L.append("var _wbasis: Basis")
		L.append("func _ready():")
		L.append("\tvar n := get_parent() as Node3D")
		L.append("\tif n == null:")
		L.append("\t\treturn")
		L.append("\t_wpos = n.global_position")
		if not inherit_rot:
			L.append("\t_wbasis = n.global_transform.basis")
		L.append("func _process(_d):")
		L.append("\tvar n := get_parent() as Node3D")
		L.append("\tif n == null or not is_instance_valid(n):")
		L.append("\t\treturn")
		if not follow:
			L.append("\tn.global_position = _wpos")
		if not inherit_rot:
			L.append("\tn.global_transform = Transform3D(_wbasis, n.global_transform.origin)")
	else:
		L.append("var _wpos: Vector2")
		if not inherit_rot:
			L.append("var _wrot: float")
		L.append("func _ready():")
		L.append("\tvar n := get_parent() as Node2D")
		L.append("\tif n == null:")
		L.append("\t\treturn")
		L.append("\t_wpos = n.global_position")
		if not inherit_rot:
			L.append("\t_wrot = n.global_rotation")
		L.append("func _process(_d):")
		L.append("\tvar n := get_parent() as Node2D")
		L.append("\tif n == null or not is_instance_valid(n):")
		L.append("\t\treturn")
		if not follow:
			L.append("\tn.global_position = _wpos")
		if not inherit_rot:
			L.append("\tn.global_rotation = _wrot")
	return "\n".join(L) + "\n"

# ---------------------------------------------------------------------------
# The runtime fixup — used when neither compile pass could resolve the nodes
# (e.g. the parent is a genre brick built later in the graph than this one)
# ---------------------------------------------------------------------------

func _add_fixup(b: Dictionary, root: Node, specs: Dictionary, is3: bool) -> void:
	var child_brick: Dictionary = specs["child"]
	var parent_brick: Dictionary = specs["parent"]
	var child_param := str(specs.get("child_param", ""))
	var parent_param := str(specs.get("parent_param", ""))

	var child_names := [] if child_brick.is_empty() else _name_candidates(child_brick)
	var parent_names := [] if parent_brick.is_empty() else _name_candidates(parent_brick)
	if not child_param.is_empty() and not child_names.has(child_param):
		child_names.append(child_param)
	if not parent_param.is_empty() and not parent_names.has(parent_param):
		parent_names.append(parent_param)
	if child_names.is_empty():
		push_warning("[hierarchy] Attach '%s': no child to look for at runtime either — nothing attached." % _title(b))
		return

	var p := FeatureCtx.params(b)
	var follow := FeatureCtx.bbool(b, "follow_position", true)
	var inherit_rot := FeatureCtx.bbool(b, "inherit_rotation", true)
	var visible := FeatureCtx.bbool(b, "visible", true)
	var has_offset := p.has("offset")
	var off := _offset(p.get("offset", null), is3)
	var bid := FeatureCtx.bid(b)

	var node := Node.new()
	node.name = "Attach" if bid.is_empty() else "Attach_%s" % bid
	var src := _fixup_source(child_names, parent_names, off, has_offset,
		follow, inherit_rot, visible)
	if FeatureCtx.attach_script(node, src) != OK:
		push_error("[hierarchy] attach fixup failed to compile for brick '%s'" % bid)
		node.free()
		return
	root.add_child(node)
	push_warning("[hierarchy] Attach '%s': the other thing is not built yet — attaching it when the game starts." % _title(b))

func _fixup_source(child_names: Array, parent_names: Array, off: Array,
		has_offset: bool, follow: bool, inherit_rot: bool, visible: bool) -> String:
	var L: Array[String] = []
	L.append("extends Node")
	L.append("# Generated by EasyForge from an Attach brick whose parent could")
	L.append("# not be resolved while compiling (it is built later in the graph).")
	L.append("# This node performs the same reparent at _ready, when everything")
	L.append("# exists. It never crashes if it still finds nothing.")
	L.append("const CHILD_NAMES: Array[String] = %s" % _str_array(child_names))
	L.append("const PARENT_NAMES: Array[String] = %s" % _str_array(parent_names))
	L.append("const OFFSET: Array = [%f, %f, %f]" % [float(off[0]), float(off[1]), float(off[2])])
	L.append("const HAS_OFFSET := %s" % ("true" if has_offset else "false"))
	L.append("const FOLLOW_POS := %s" % ("true" if follow else "false"))
	L.append("const INHERIT_ROT := %s" % ("true" if inherit_rot else "false"))
	L.append("const VISIBLE := %s" % ("true" if visible else "false"))
	L.append("")
	L.append("var _child: Node = null")
	L.append("var _parent: Node = null")
	L.append("var _pin := false")
	if not follow:
		L.append("var _wpos3: Vector3")
		L.append("var _wpos2: Vector2")
	if not inherit_rot:
		L.append("var _wbasis: Basis")
		L.append("var _wrot: float")
	L.append("")
	L.append("func _ready():")
	L.append("\tvar root := get_parent()")
	L.append("\tif root == null:")
	L.append("\t\treturn")
	L.append("\t_child = _find(root, CHILD_NAMES)")
	L.append("\tif _child == null:")
	L.append("\t\tpush_warning(\"[hierarchy] attach fixup: child not found\")")
	L.append("\t\treturn")
	L.append("\t_parent = _find(root, PARENT_NAMES)")
	L.append("\tif _parent == null or _parent == _child:")
	L.append("\t\t_parent = _player()")
	L.append("\tif _parent == null or _parent == _child:")
	L.append("\t\tpush_warning(\"[hierarchy] attach fixup: parent not found\")")
	L.append("\t\treturn")
	L.append("\tif _is_ancestor(_child, _parent):")
	L.append("\t\tpush_warning(\"[hierarchy] attach fixup: would create a loop\")")
	L.append("\t\treturn")
	L.append("\tif not VISIBLE:")
	L.append("\t\t_set_visible(_child, false)")
	L.append("\tif _child.get_parent() != _parent:")
	L.append("\t\t_child.reparent(_parent)")
	L.append("\tif HAS_OFFSET:")
	L.append("\t\t_set_pos(_child, OFFSET)")
	L.append("\t_pin = (not FOLLOW_POS) or (not INHERIT_ROT)")
	L.append("\tif _pin:")
	L.append("\t\tif _child is Node3D:")
	L.append("\t\t\tvar n3 := _child as Node3D")
	if not follow:
		L.append("\t\t\t_wpos3 = n3.global_position")
	if not inherit_rot:
		L.append("\t\t\t_wbasis = n3.global_transform.basis")
	L.append("\t\telif _child is Node2D:")
	L.append("\t\t\tvar n2 := _child as Node2D")
	if not follow:
		L.append("\t\t\t_wpos2 = n2.global_position")
	if not inherit_rot:
		L.append("\t\t\t_wrot = n2.global_rotation")
	if not follow or not inherit_rot:
		L.append("")
		L.append("func _process(_d):")
		L.append("\tif not _pin or _child == null or not is_instance_valid(_child):")
		L.append("\t\treturn")
		L.append("\tif _child is Node3D:")
		L.append("\t\tvar n3 := _child as Node3D")
		if not follow:
			L.append("\t\tif not FOLLOW_POS:")
			L.append("\t\t\tn3.global_position = _wpos3")
		if not inherit_rot:
			L.append("\t\tif not INHERIT_ROT:")
			L.append("\t\t\tn3.global_transform = Transform3D(_wbasis, n3.global_transform.origin)")
		L.append("\telif _child is Node2D:")
		L.append("\t\tvar n2 := _child as Node2D")
		if not follow:
			L.append("\t\tif not FOLLOW_POS:")
			L.append("\t\t\tn2.global_position = _wpos2")
		if not inherit_rot:
			L.append("\t\tif not INHERIT_ROT:")
			L.append("\t\t\tn2.global_rotation = _wrot")
	L.append("")
	L.append("func _find(root: Node, names: Array) -> Node:")
	L.append("	for n in names:")
	L.append("		var s := str(n)")
	L.append("\t\tif s.is_empty():")
	L.append("\t\t\tcontinue")
	L.append("\t\tvar f = root.find_child(s, true, false)")
	L.append("\t\tif f != null and f != self and is_instance_valid(f):")
	L.append("\t\t\treturn f")
	L.append("\treturn null")
	L.append("")
	L.append("func _player() -> Node:")
	L.append("\tvar tree := get_tree()")
	L.append("\tif tree == null:")
	L.append("\t\treturn null")
	L.append("\tvar ps = tree.get_nodes_in_group(\"player\")")
	L.append("\tif ps.size() > 0 and ps[0] is Node:")
	L.append("\t\treturn ps[0]")
	L.append("\treturn null")
	L.append("")
	L.append("func _is_ancestor(node: Node, maybe_ancestor: Node) -> bool:")
	L.append("\tvar p := maybe_ancestor")
	L.append("\twhile p != null:")
	L.append("\t\tif p == node:")
	L.append("\t\t\treturn true")
	L.append("\t\tp = p.get_parent()")
	L.append("\treturn false")
	L.append("")
	L.append("func _set_visible(n: Node, v: bool) -> void:")
	L.append("\tif n is CanvasItem:")
	L.append("\t\t(n as CanvasItem).visible = v")
	L.append("\telif n is Node3D:")
	L.append("\t\t(n as Node3D).visible = v")
	L.append("")
	L.append("func _set_pos(n: Node, off: Array) -> void:")
	L.append("\tvar x := float(off[0]) if off.size() > 0 else 0.0")
	L.append("\tvar y := float(off[1]) if off.size() > 1 else 0.0")
	L.append("\tvar z := float(off[2]) if off.size() > 2 else 0.0")
	L.append("\tif n is Node3D:")
	L.append("\t\t(n as Node3D).position = Vector3(x, y, z)")
	L.append("\telif n is Node2D:")
	L.append("\t\t(n as Node2D).position = Vector2(x, y)")
	return "\n".join(L) + "\n"

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

func _reset_if_new_root(root: Node) -> void:
	var rid := root.get_instance_id()
	if rid != _done_root_id:
		_done_root_id = rid
		_done.clear()
		_attempts.clear()

func _set_visible(n: Node, v: bool) -> void:
	if n is CanvasItem:
		(n as CanvasItem).visible = v
	elif n is Node3D:
		(n as Node3D).visible = v

func _set_pos(n: Node, off: Array) -> void:
	var x := float(off[0]) if off.size() > 0 else 0.0
	var y := float(off[1]) if off.size() > 1 else 0.0
	var z := float(off[2]) if off.size() > 2 else 0.0
	if n is Node3D:
		(n as Node3D).position = Vector3(x, y, z)
	elif n is Node2D:
		(n as Node2D).position = Vector2(x, y)

func _is_ancestor(node: Node, maybe_ancestor: Node) -> bool:
	var p := maybe_ancestor
	var guard := 0
	while p != null and guard < 256:
		guard += 1
		if p == node:
			return true
		p = p.get_parent()
	return false

func _same_brick(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	return FeatureCtx.bid(a) == FeatureCtx.bid(b)

func _label_of(brick: Dictionary) -> String:
	if brick.is_empty():
		return "?"
	var t := _clean(str(brick.get("title", "")))
	return t if not t.is_empty() else FeatureCtx.bid(brick)

func _title(b: Dictionary) -> String:
	var t := _clean(str(b.get("title", "")))
	return t if not t.is_empty() else KIND

## Offset param -> [x, y, z] floats. A 2-number array is legal in 3D (z = 0).
func _offset(raw, is3: bool) -> Array:
	var fb: Array = DEF_OFFSET_3D if is3 else DEF_OFFSET_2D
	if raw is Array and raw.size() >= 2:
		return [
			_n(raw[0], float(fb[0])),
			_n(raw[1], float(fb[1])),
			_n(raw[2], 0.0) if raw.size() > 2 else 0.0,
		]
	if raw is Vector2:
		return [raw.x, raw.y, 0.0]
	if raw is Vector3:
		return [raw.x, raw.y, raw.z]
	return [float(fb[0]), float(fb[1]), float(fb[2])]

func _conns(b: Dictionary) -> Array:
	var v = b.get("connections")
	return v if v is Array else []

func _bricks_of(graph) -> Array:
	if graph == null:
		return []
	var v = graph.get("bricks")
	return v if v is Array else []

static func _clean(s: String) -> String:
	return s.replace("\r", " ").replace("\n", " ").replace("\t", " ").strip_edges()

static func _n(x, fallback: float) -> float:
	if x is float or x is int:
		var f := float(x)
		return fallback if (is_nan(f) or is_inf(f)) else f
	if x is String and str(x).is_valid_float():
		var f2 := float(x)
		return fallback if (is_nan(f2) or is_inf(f2)) else f2
	return fallback

## A GDScript array-of-string-literals literal for a generated script.
static func _str_array(values: Array) -> String:
	var parts: Array[String] = []
	for v in values:
		var s := _clean(str(v))
		if s.is_empty():
			continue
		parts.append("\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\"")
	if parts.is_empty():
		return "[]"
	return "[" + ", ".join(parts) + "]"

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
