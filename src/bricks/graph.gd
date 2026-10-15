extends Node   # autoloads must inherit Node
## BrickGraph — the user's whole project: an ordered list of bricks + helpers.
##
## The IR shape version. Bump this whenever to_dict()'s output shape changes and
## add a matching step to migrate() — this is what stops a brick rename from
## silently orphaning every existing user project.
const SCHEMA_VERSION := 2
##
## Registered as the autoload singleton "BrickGraph" (project.godot); the app
## keeps its own instance and passes it around explicitly.
##
## This is the live IR the AI drafts into, the user edits, and the compiler
## reads. It is intentionally dumb: no engine references, no UI references.
## Save = JSON.stringify(graph.to_dict()). Load = graph.from_dict().
##
## NOTE: the method is named wire() not connect() to avoid clashing with
## Object.connect() — GDScript treats overriding native methods as an error.
##
## NOTE 2: class_name BrickGraphRef is declared in brick.gd (a script with no
## autoload collision); all type hints use BrickGraphRef.

var bricks: Array[Dictionary] = []
var project_name: String = "My Game"
var dimension: String = "3d"          # "2d" or "3d" — one pipeline, tagged
var genre: String = "platformer"
# Multi-level (Wave 3): an optional list of extra levels. Each entry is a full
# graph dict (same shape as the top level). Level 1 is always the top-level
# bricks; levels[0] is level 2, levels[1] is level 3, etc. The Door brick
# targets a level by its 1-based number. Empty list = single-level (default).
var levels: Array = []

func _init():
	pass

# ---------------------------------------------------------------------------
# Accessors that NEVER assume the AI produced well-formed bricks.
# ---------------------------------------------------------------------------

## Safe list accessor: returns [] for missing/wrong-typed keys.
static func _list_of(brick: Dictionary, key: String) -> Array:
	var v = brick.get(key)
	return v if v is Array else []

## Safe dict accessor: returns {} for missing/wrong-typed keys.
static func dict_of(brick: Dictionary, key: String) -> Dictionary:
	var v = brick.get(key)
	return v if v is Dictionary else {}

static func connections_of(brick: Dictionary) -> Array:
	return _list_of(brick, "connections")

static func kind_of(brick: Dictionary) -> String:
	var k = brick.get("kind")
	return str(k) if k != null else ""

static func title_of(brick: Dictionary) -> String:
	var t = brick.get("title")
	if t != null and not str(t).is_empty():
		return str(t)
	return BrickRegistry.kind_label(kind_of(brick))

static func id_of(brick: Dictionary) -> String:
	var i = brick.get("id")
	return str(i) if i != null else ""

# ---------------------------------------------------------------------------
# Mutation
# ---------------------------------------------------------------------------
func add_brick(brick: Dictionary) -> bool:
	if brick.is_empty():
		return false
	if id_of(brick).is_empty():
		return false   # a brick without an id can never be wired to
	if _find_index(id_of(brick)) != -1:
		return false
	bricks.append(brick)
	return true

func remove_brick(brick_id: String) -> bool:
	var i := _find_index(brick_id)
	if i == -1:
		return false
	bricks.remove_at(i)
	# drop any connections pointing at the removed brick
	for b in bricks:
		var conns := connections_of(b)
		var kept: Array = []
		for c in conns:
			var cb: Dictionary = c if c is Dictionary else {}
			if str(cb.get("to_brick", "")) != brick_id:
				kept.append(c)
		b["connections"] = kept
	return true

func get_brick(brick_id: String) -> Dictionary:
	var i := _find_index(brick_id)
	return bricks[i] if i != -1 else {}

## wire() — the connection primitive. Named "wire" (not "connect") to avoid
## overriding Object.connect(), which GDScript rejects as a parse error.
func wire(from_brick_id: String, from_port: int, to_brick_id: String, to_port: int) -> bool:
	var a := get_brick(from_brick_id)
	var b := get_brick(to_brick_id)
	if a.is_empty() or b.is_empty():
		return false
	if not BrickRef.can_connect(a, from_port, b, to_port):
		return false
	var conns := connections_of(a)
	conns.append({
		"from_out": from_port,
		"to_brick": to_brick_id,
		"to_in": to_port,
	})
	a["connections"] = conns
	return true

# ---------------------------------------------------------------------------
# Topological order — the compiler needs bricks in execution order.
# Spawns first, then by connection depth. Cycles fall back to insertion order
# (never crash: a user CAN draw a loop; the compiler handles it as a warning).
# ---------------------------------------------------------------------------
func execution_order() -> Array[Dictionary]:
	var ordered: Array[Dictionary] = []
	var visited := {}
	# roots first (spawns, then bricks with no incoming flow)
	var queue: Array[String] = []
	for b in bricks:
		if kind_of(b) == "spawn":
			var bid := id_of(b)
			if not bid.is_empty():
				queue.append(bid)
	for b in bricks:
		var bid := id_of(b)
		if bid.is_empty():
			continue
		if kind_of(b) != "spawn" and not queue.has(bid) and _incoming_flow_count(b) == 0:
			queue.append(bid)
	# BFS by connection
	var guard := 0
	while not queue.is_empty() and guard < 10000:
		guard += 1
		var id: String = queue.pop_front()
		if visited.has(id):
			continue
		visited[id] = true
		var b := get_brick(id)
		if not b.is_empty():
			ordered.append(b)
		for c in connections_of(b):
			var cb: Dictionary = c if c is Dictionary else {}
			var nid := str(cb.get("to_brick", ""))
			if not nid.is_empty() and not visited.has(nid):
				queue.append(nid)
	# anything unvisited (cycle members, or bricks with no id) in insertion order
	for b in bricks:
		var bid := id_of(b)
		if bid.is_empty():
			ordered.append(b)
			continue
		if not visited.has(bid):
			ordered.append(b)
			visited[bid] = true
	return ordered

# ---------------------------------------------------------------------------
# Validation — returns list of human-readable warnings (never fatal).
# The spec: errors surface in the app, they never crash it.
# ---------------------------------------------------------------------------
func validate() -> Array[String]:
	var issues: Array[String] = []
	if bricks.is_empty():
		issues.append("There is nothing in your game yet — add the Character brick first.")
		return issues
	var has_spawn := false
	for b in bricks:
		if kind_of(b) == "spawn":
			has_spawn = true
	if not has_spawn:
		issues.append("Your game has no character yet — add the Character brick.")
	# orphan collide/winlose (no incoming event) = dead brick
	for b in bricks:
		if kind_of(b) in ["collide", "winlose"] and _incoming_flow_count(b) == 0 and connections_of(b).size() > 0:
			issues.append("'%s' will never happen: nothing leads into it." % title_of(b))
	# malformed bricks from the AI: missing id or kind can't be compiled
	for b in bricks:
		if b.is_empty():
			issues.append("One empty box will be skipped.")
		elif id_of(b).is_empty():
			issues.append("One box has no name and will be skipped.")
		elif kind_of(b).is_empty():
			issues.append("'%s' is not a real brick type and will be skipped." % title_of(b))
		# dangling connections point at bricks that no longer exist
		for c in connections_of(b):
			var cb: Dictionary = c if c is Dictionary else {}
			var target := str(cb.get("to_brick", ""))
			if not target.is_empty() and _find_index(target) == -1:
				issues.append("A wire leads nowhere — the box it pointed to is gone.")
	return issues

# ---------------------------------------------------------------------------
# Wave 1 — static structural validation (the IR-validation step from the
# roadmap). Runs BEFORE the compiler; the AI self-correction loop and the
# pre-Play check both call it. Returns a list of {code, message, brick_id}
# so callers can decide what's fatal vs a warning, and feed structured errors
# back to the AI for a bounded retry.
# ---------------------------------------------------------------------------
func validate_ir() -> Array:
	var problems: Array = []
	# duplicate ids break every wiring lookup
	var seen_ids := {}
	for b in bricks:
		var bid := id_of(b)
		if bid.is_empty():
			continue
		if seen_ids.has(bid):
			problems.append({"code": "duplicate_id", "message": "Two boxes are both called '%s' — give one of them a different name." % bid, "brick_id": bid})
		seen_ids[bid] = true
	# exactly one player model keeps the compiler's "player" resolution sane
	var player_count := 0
	for b in bricks:
		if kind_of(b) == "spawn":
			var model := str(dict_of(b, "params").get("model", "player"))
			if model == "player":
				player_count += 1
	if player_count > 1:
		problems.append({"code": "multi_player", "message": "Only one character can be you — set the other Spawn boxes to enemy, coin or box.", "brick_id": ""})
	# a Win/Lose goal is what makes a game end; warn (not fatal) when absent
	var has_goal := false
	for b in bricks:
		if kind_of(b) in ["winlose", "rule"]:
			has_goal = true
	if not has_goal and not bricks.is_empty():
		problems.append({"code": "no_goal", "message": "Nothing ever ends the game — add a Win/Lose box.", "brick_id": ""})
	# variable names referenced by rules must be declared by a Variable brick
	var declared_vars := {}
	for b in bricks:
		if kind_of(b) == "variable":
			var vn := str(dict_of(b, "params").get("name", ""))
			if not vn.is_empty():
				declared_vars[vn] = true
	for b in bricks:
		if kind_of(b) == "rule":
			var rp := dict_of(b, "params")
			if str(rp.get("cond_source", "variable")) == "variable":
				var used := str(rp.get("cond_var", ""))
				if not used.is_empty() and not declared_vars.has(used):
					problems.append({"code": "undefined_var", "message": "A rule uses '%s', but no Variable box creates it — add a Variable brick named '%s'." % [used, used], "brick_id": id_of(b)})
	return problems

# ---------------------------------------------------------------------------
# Serialization
# ---------------------------------------------------------------------------
func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"project_name": project_name,
		"dimension": dimension,
		"genre": genre,
		"bricks": bricks,
		"levels": levels,
	}

## Upgrade a saved dict of unknown/older vintage to the current shape. Old
## projects carry no schema_version, so a missing version means v1 — and a brick
## rename used to silently orphan every existing user project. Each step is
## defensive: unknown/absent fields keep their defaults, and a brick we no longer
## recognise is preserved as-is rather than dropped (the compiler reports it as
## unsupported instead of the user losing work).
static func migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("schema_version", 1))
	var out: Dictionary = d.duplicate(true)
	# v1 -> v2: normalise brick + level shape so every brick has the canonical
	# id/kind/title/comment/inputs/outputs/params/connections keys.
	if v < 2:
		var bricks_out: Array = []
		for b in out.get("bricks", []):
			if not (b is Dictionary):
				continue
			var nb: Dictionary = (b as Dictionary).duplicate(true)
			nb["id"] = str(nb.get("id", "b_%d" % bricks_out.size()))
			nb["kind"] = str(nb.get("kind", nb.get("type", "")))
			nb["title"] = str(nb.get("title", nb.get("label", nb["kind"])))
			nb["comment"] = str(nb.get("comment", ""))
			if not (nb.get("inputs", null) is Array):
				nb["inputs"] = []
			if not (nb.get("outputs", null) is Array):
				nb["outputs"] = []
			if not (nb.get("params", null) is Dictionary):
				nb["params"] = {}
			if not (nb.get("connections", null) is Array):
				nb["connections"] = []
			bricks_out.append(nb)
		out["bricks"] = bricks_out
		var levels_out: Array = []
		var raw_levels: Array = out.get("levels", [])
		for i in raw_levels.size():
			if not (raw_levels[i] is Dictionary):
				continue
			var nl: Dictionary = (raw_levels[i] as Dictionary).duplicate(true)
			nl["name"] = str(nl.get("name", "Level %d" % (i + 1)))
			levels_out.append(nl)
		out["levels"] = levels_out
		out["schema_version"] = 2
	out["schema_version"] = SCHEMA_VERSION
	return out

func from_dict(d: Dictionary) -> void:
	var m: Dictionary = migrate(d) if d is Dictionary else {}
	project_name = str(m.get("project_name", "My Game"))
	dimension = str(m.get("dimension", "3d"))
	genre = str(m.get("genre", "platformer"))
	bricks.clear()
	for b in m.get("bricks", []):
		if b is Dictionary:
			bricks.append(b)
	levels.clear()
	for lv in m.get("levels", []):
		if lv is Dictionary:
			levels.append(lv)

func save_to(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("BrickGraph.save_to: cannot write %s" % path)
		return false
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.close()
	return true

func load_from(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("BrickGraph.load_from: cannot read %s" % path)
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	from_dict(parsed)
	return true

# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------
func _find_index(brick_id: String) -> int:
	if brick_id.is_empty():
		return -1
	for i in bricks.size():
		if id_of(bricks[i]) == brick_id:
			return i
	return -1

func _incoming_flow_count(brick: Dictionary) -> int:
	var n := 0
	var bid := id_of(brick)
	if bid.is_empty():
		return 0
	for other in bricks:
		for c in connections_of(other):
			var cb: Dictionary = c if c is Dictionary else {}
			if str(cb.get("to_brick", "")) == bid:
				n += 1
	return n
