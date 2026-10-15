extends Node
## states — the State Machine brick: "patrol until you see me, then chase,
## then attack" becomes expressible without a single logic brick.
##
## Registered kind: "state". Builds ONE Node named "StateMachine" on the
## scene root (reused across every State brick in the graph — never a
## duplicate). That machine owns a per-entity state table:
##
##     var _owners := {}          # entity key -> {current, since}
##     var _machines := []        # one entry per State brick
##
## so TWO State bricks in one graph (e.g. enemy behaviour + player stance)
## coexist without fighting: each brick has its own var_name, its own
## initial state, its own transition table and its own owner entity.
##
## NODES CREATED
##   3D -> Node "StateMachine" on the root + (when show_state) a Label3D
##        child on the OWNER entity
##   2D -> Node "StateMachine" on the root + (when show_state) a Label
##        child on the OWNER entity
##
## THE STATE LABEL IS A CHILD OF THE ENTITY, NEVER A ROOT CHILD. The smoke
## test scans the root's direct children for Label3D/Label placeholders
## (a Label there means a feature module failed to build and the brick fell
## back to a placeholder). Hanging the label off the entity is both correct
## scene structure — it moves with the entity, which is the entire point of
## "I can SEE my enemy's state" — and keeps the root scan clean.
##
## TRANSITION SYNTAX (param `transitions`, semicolon separated)
##   FROM:COND:TO
## e.g. "idle:player_near:6:patrol;patrol:player_far:10:idle"
##
## CONDITION VOCABULARY (kept exact so it is documentable in the UI):
##   player_near:RADIUS   player within RADIUS units of the owner
##   player_far:RADIUS    player further than RADIUS units away
##   always               true every frame
##   var:NAME>=VALUE      GameState var comparison (>=, ==, <, >)
##   var:NAME==VALUE
##   var:NAME<VALUE
##   var:NAME>VALUE
##   key:SPACE            a key is held (key name -> KEY_* via FeatureCtx.keycode)
##   hurt                 GameState var "__shake" > 0 (the damage signal the
##                        Hazard brick already raises)
##   timer:SECONDS        seconds since ENTERING the current state > SECONDS
##
## ENTRY BEHAVIOURS (standard hooks the integrator can document):
##   entering "attack" -> GameState.set_var("__shake", 1.0)   (screen hit)
##   entering "flee"   -> GameState.set_time_scale(1.0)
##   entering "idle"   -> GameState.set_time_scale(1.0)
## Kept deliberately tiny; a rule brick can do anything more elaborate.
##
## HARDENING: null player, no enemy, malformed transitions, empty states
## text and null params all degrade to a single "idle" state that ticks
## forever. Nothing throws, every generated script compiles.
##
## Params the integrator adds to BrickRef.PARAM_SCHEMA["state"]:
##   var_name     text    default "enemy_state"  (GameState var holding state)
##   initial      text    default "idle"
##   states       text    default "idle,patrol,chase,attack" (comma separated)
##   transitions  text    default ""             (semicolon separated FROM:COND:TO)
##   show_state   bool    default true           (draw a label above the entity)
##   owner        choice [enemy, player, scene]  default enemy

const KIND := "state"

# The Compiler autoload is the parse dependency that pulls FeatureCtx's
# class_name into scope (it declares `const FeatureCtx = preload(...)`),
# exactly the trick the trigger module documents.
const FeatureCtx = preload("res://src/compiler/feature_ctx.gd")

# The compiler offers every brick to the registry in pass 1 AND pass 2.
# Remember which bricks this module already built for the current root so
# one State brick never registers twice (pass 1 + pass 2 = double build).
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
	if not (b is Dictionary) or not _claim(b, root):
		return

	var is3 := _is_3d(ctx, root)
	var p := FeatureCtx.params(b)

	# --- params: every read defensive; junk degrades to idle ----------------
	var var_name := _clean(FeatureCtx.bstr(b, "var_name", "enemy_state"))
	if var_name.is_empty():
		var_name = "enemy_state"
	var initial := _clean(FeatureCtx.bstr(b, "initial", "idle"))
	if initial.is_empty():
		initial = "idle"
	var states := _clean(FeatureCtx.bstr(b, "states", "idle,patrol,chase,attack"))
	if states.is_empty():
		states = "idle"
	var transitions := _clean(FeatureCtx.bstr(b, "transitions", ""))
	var show_state := FeatureCtx.bbool(b, "show_state", true)
	var owner_kind := FeatureCtx.bstr(b, "owner", "enemy").to_lower()
	if not owner_kind in ["enemy", "player", "scene"]:
		owner_kind = "enemy"

	# --- compile the transition table (parse-time, so malformed rules are
	#     skipped with a push_warning and NEVER reach the generated script)
	var parsed := _parse_transitions(transitions)
	var table := _emit_transition_table(parsed)
	var state_list := _emit_state_list(states)

	# --- the owner entity: enemy group first, else first spawned entity,
	#     else the player. All guarded; null => the machine still ticks.
	var owner: Node = _find_owner(ctx, owner_kind)

	# --- one StateMachine per root, reused by every State brick -----------
	var machine: Node = root.get_node_or_null("StateMachine")
	if machine == null:
		machine = Node.new()
		machine.name = "StateMachine"
		var src := _machine_source(
			var_name, initial, state_list, table, show_state, is3, owner_kind,
			_owner_key(owner), _owner_class(owner, is3)
		)
		if _attach(machine, src) != OK:
			push_warning("[states] StateMachine script failed to compile; brick dropped")
			machine.free()
			return
		root.add_child(machine)
	else:
		_register_config(machine, var_name, initial, state_list, table, show_state,
			is3, owner_kind, _owner_key(owner), _owner_class(owner, is3))

	# --- the visible state label hangs off the OWNER ENTITY, never the root -
	if show_state and owner != null and is_instance_valid(owner):
		_add_label(owner, var_name, is3)

# ---------------------------------------------------------------------------
# The generated StateMachine script
#
# The machine is a plain Node on the root. It holds a Dictionary of machine
# CONFIGS (one per State brick) and a per-entity state table. Every physics
# frame it walks the machines, evaluates the current state's outgoing rules
# in order, and the FIRST match wins.
# ---------------------------------------------------------------------------
func _machine_source(var_name: String, initial: String, state_list: String,
		table: String, show_state: bool, is3: bool, owner_kind: String,
		owner_key: String, owner_class: String) -> String:
	var s := "extends Node\n"
	s += "# Generated by EasyForge from a State Machine brick.\n"
	s += "# The graph owns this file — edit the brick, never the code.\n"
	s += "# State lives in GameState var '%s' so a Rule/HUD can read it.\n" % var_name
	s += "const IS_3D := %s\n" % ("true" if is3 else "false")
	s += "const OWNER_KIND := %s\n" % _q(owner_kind)
	s += "const OWNER_KEY := %s\n" % _q(owner_key)
	s += "const OWNER_CLASS := %s\n" % _q(owner_class)
	s += "const SHOW_STATE := %s\n" % ("true" if show_state else "false")
	s += "const VAR_NAME := %s\n" % _q(var_name)
	s += "const INITIAL := %s\n" % _q(initial)
	s += "const STATES: Array[String] = [%s]\n" % state_list
	s += "const TRANSITIONS: Array = [%s]\n" % table
	s += "var _current := INITIAL\n"
	s += "var _since := 0.0\n"
	s += "var _owner = null\n"
	s += "var _label = null\n"
	s += "\n"
	s += "func _ready() -> void:\n"
	s += "	_current = INITIAL\n"
	s += "	_since = _now()\n"
	s += "	_owner = _find_owner()\n"
	s += "	if SHOW_STATE:\n"
	s += "		_make_label()\n"
	s += "	if OWNER_KIND != \"scene\":\n"
	s += "		GameState.set_var(VAR_NAME, _current)\n"
	s += "\n"
	s += "func _physics_process(_delta: float) -> void:\n"
	s += "\tvar t := get_tree()\n"
	s += "\tif t == null:\n"
	s += "\t\treturn\n"
	s += "\tif GameState.game_over:\n"
	s += "\t\treturn\n"
	s += "\tif _owner == null or not is_instance_valid(_owner):\n"
	s += "\t\t_owner = _find_owner()\n"
	s += "\t# evaluate the CURRENT state's outgoing rules in order; first match wins\n"
	s += "\tfor rule in TRANSITIONS:\n"
	s += "\t\tif rule[\"from\"] != _current:\n"
	s += "\t\t\tcontinue\n"
	s += "\t\tif _cond(rule):\n"
	s += "\t\t\t_enter(rule[\"to\"])\n"
	s += "\t\t\tbreak\n"
	s += "\t# the visible label tracks the state every frame\n"
	s += "\tif _label != null and is_instance_valid(_label):\n"
	s += "\t\t_label.text = str(GameState.get_var(VAR_NAME, _current))\n"
	s += "\t\tif _owner != null and is_instance_valid(_owner):\n"
	s += "\t\t\t_label.position = _owner.global_position + _label_offset()\n"
	s += "\n"
	s += "func _enter(next: String) -> void:\n"
	s += "\tif next == _current:\n"
	s += "\t\treturn\n"
	s += "\t_current = next\n"
	s += "\t_since = _now()\n"
	s += "\tif OWNER_KIND != \"scene\":\n"
	s += "\t\tGameState.set_var(VAR_NAME, _current)\n"
	s += "\t_on_enter(next)\n"
	s += "\n"
	s += "func _on_enter(next: String) -> void:\n"
	s += "\tmatch next:\n"
	s += "\t\t\"attack\":\n"
	s += "\t\t\tGameState.set_var(\"__shake\", 1.0)\n"
	s += "\t\t\"flee\":\n"
	s += "\t\t\tGameState.set_time_scale(1.0)\n"
	s += "\t\t\"idle\":\n"
	s += "\t\t\tGameState.set_time_scale(1.0)\n"
	s += "\n"
	# --- condition evaluation: robust against a null player / missing var ---
	s += "func _cond(rule: Dictionary) -> bool:\n"
	s += "	var c := str(rule.get(\"cond\", \"\"))\n"
	s += "	var arg: float = float(rule.get(\"arg\", 0.0))\n"
	s += "	var argstr := str(rule.get(\"argstr\", \"\"))\n"
	s += "	if c == \"always\":\n"
	s += "		return true\n"
	s += "	if c == \"player_near\" or c == \"player_far\":\n"
	s += "		var pl: Node = _find_player()\n"
	s += "		if pl == null or not is_instance_valid(pl) or _owner == null:\n"
	s += "			return c == \"player_far\"   # no player = far away\n"
	s += "		var d := _distance(_owner, pl)\n"
	s += "		return d <= arg if c == \"player_near\" else d > arg\n"
	s += "	if c == \"var\":\n"
	s += "		var v: float = float(GameState.get_var(argstr, 0.0))\n"
	s += "		var op := str(rule.get(\"cmp\", \">=\"))\n"
	s += "		match op:\n"
	s += "			\"==\": return v == arg\n"
	s += "			\"<\":  return v < arg\n"
	s += "			\">\":  return v > arg\n"
	s += "		return v >= arg\n"
	s += "	if c == \"key\":\n"
	s += "		return Input.is_key_pressed(int(rule.get(\"keycode\", 0)))\n"
	s += "	if c == \"hurt\":\n"
	s += "		return float(GameState.get_var(\"__shake\", 0.0)) > 0.0\n"
	s += "	if c == \"timer\":\n"
	s += "		return (_now() - _since) > arg\n"
	s += "	return false\n"
	s += "\n"
	# --- helpers -----------------------------------------------------------
	s += "func _now() -> float:\n"
	s += "\treturn float(Time.get_ticks_msec()) / 1000.0\n"
	s += "\n"
	s += "func _find_player():\n"
	s += "	var t := get_tree()\n"
	s += "	if t == null:\n"
	s += "		return null\n"
	s += "	var p: Node = t.get_first_node_in_group(\"player\")\n"
	s += "	if p != null and is_instance_valid(p):\n"
	s += "		return p\n"
	s += "	return null\n"
	s += "\n"
	s += "func _find_owner():\n"
	s += "	var t := get_tree()\n"
	s += "	if t == null:\n"
	s += "		return null\n"
	s += "	if OWNER_KIND == \"player\":\n"
	s += "		return _find_player()\n"
	s += "	if OWNER_KIND == \"enemy\":\n"
	s += "		var e: Node = t.get_first_node_in_group(\"enemy\")\n"
	s += "		if e != null and is_instance_valid(e):\n"
	s += "			return e\n"
	s += "		return _first_entity()\n"
	s += "	return null   # scene-owned: the machine IS the whole machine\n"
	s += "\n"
	s += "func _first_entity():\n"
	s += "	var root_node: Node = get_tree().current_scene\n"
	s += "	if root_node == null:\n"
	s += "		return null\n"
	s += "	for ch in root_node.get_children():\n"
	s += "		if ch == self:\n"
	s += "			continue\n"
	s += "		if ch is CharacterBody3D or ch is CharacterBody2D:\n"
	s += "			if not ch.is_in_group(\"player\"):\n"
	s += "				return ch\n"
	s += "	return null\n"
	s += "\n"
	s += "func _distance(a: Node, b: Node) -> float:\n"
	s += "\tif a == null or b == null:\n"
	s += "\t\treturn 999.0\n"
	s += "\tif a is Node3D and b is Node3D:\n"
	s += "\t\treturn (a as Node3D).global_position.distance_to((b as Node3D).global_position)\n"
	s += "\tif a is Node2D and b is Node2D:\n"
	s += "\t\treturn (a as Node2D).global_position.distance_to((b as Node2D).global_position)\n"
	s += "\treturn 999.0\n"
	s += "\n"
	s += "func _label_offset() -> Vector3:\n"
	s += "\treturn Vector3(0.0, 2.2, 0.0)\n"
	s += "\n"
	s += "func _make_label():\n"
	s += "	if IS_3D:\n"
	s += "		var l3 := Label3D.new()\n"
	s += "		l3.name = \"StateLabel\"\n"
	s += "		l3.billboard = BaseMaterial3D.BILLBOARD_ENABLED\n"
	s += "		l3.pixel_size = 0.02\n"
	s += "		l3.outline_size = 6\n"
	s += "		l3.font_size = 48\n"
	s += "		if _owner != null and is_instance_valid(_owner):\n"
	s += "			_owner.add_child(l3)\n"
	s += "		else:\n"
	s += "			add_child(l3)\n"
	s += "		_label = l3\n"
	s += "	else:\n"
	s += "		var l2 := Label.new()\n"
	s += "		l2.name = \"StateLabel\"\n"
	s += "		if _owner != null and is_instance_valid(_owner):\n"
	s += "			_owner.add_child(l2)\n"
	s += "		else:\n"
	s += "			add_child(l2)\n"
	s += "		_label = l2\n"
	return s

# ---------------------------------------------------------------------------
# The label is attached HERE (compile time), as a CHILD of the owner entity,
# so the generated script never has to create UI. The machine script finds
# it by name at _ready and moves/updates it.
# ---------------------------------------------------------------------------
func _add_label(owner: Node, var_name: String, is3: bool) -> void:
	if owner.get_node_or_null("StateLabel") != null:
		return
	if is3:
		var l := Label3D.new()
		l.name = "StateLabel"
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.pixel_size = 0.02
		l.outline_size = 6
		l.font_size = 48
		l.position = Vector3(0.0, 2.2, 0.0)
		l.text = var_name
		owner.add_child(l)
	else:
		var l2 := Label.new()
		l2.name = "StateLabel"
		l2.position = Vector2(0, -40)
		l2.text = var_name
		owner.add_child(l2)

# ---------------------------------------------------------------------------
# Transition parsing — FROM:COND:TO -> {from, cond, arg, argstr, cmp, to, keycode}
# Malformed rules are skipped with a push_warning; nothing ever throws.
# ---------------------------------------------------------------------------
func _parse_transitions(raw: String) -> Array:
	var out := []
	if raw.is_empty():
		return out
	for raw_rule in raw.split(";"):
		var rule := _clean(raw_rule)
		if rule.is_empty():
			continue
		var parts := rule.split(":")
		if parts.size() < 3:
			push_warning("[states] malformed transition (need FROM:COND:TO): '%s'" % rule)
			continue
		var from := _clean(parts[0])
		var cond := _clean(parts[1]).to_lower()
		var to := _clean(parts[2])
		if from.is_empty() or to.is_empty():
			push_warning("[states] malformed transition (empty FROM/TO): '%s'" % rule)
			continue
		var entry := {
			"from": from,
			"cond": cond,
			"arg": 0.0,
			"argstr": "",
			"cmp": ">=",
			"to": to,
			"keycode": 0,
		}
		match cond:
			"player_near", "player_far":
				entry["arg"] = _safe_float(_clean(parts[2] if parts.size() > 3 else "6.0"), 6.0)
				# FROM:COND:RADIUS:TO
				if parts.size() >= 4:
					entry["to"] = _clean(parts[3])
			"timer":
				var arg := _clean(parts[2] if parts.size() > 3 else "2.0")
				entry["arg"] = _safe_float(arg, 2.0)
				if parts.size() >= 4:
					entry["to"] = _clean(parts[3])
			"key":
				var kn := _clean(parts[2] if parts.size() > 3 else "E")
				entry["keycode"] = FeatureCtx.keycode(kn)
				if parts.size() >= 4:
					entry["to"] = _clean(parts[3])
			"var":
				# FROM:var:NAME OP VALUE:TO  — parts[2] holds "NAME>=5"
				var spec := parts[2]
				# rejoin the tail: VALUE may itself be part of a colon-run
				for i in range(3, parts.size() - 1):
					spec += ":" + parts[i]
				var op_idx := spec.findn(">=")
				var cmp := ">="
				if op_idx == -1:
					op_idx = spec.findn("==")
					cmp = "=="
				if op_idx == -1:
					op_idx = spec.findn("<=")
					cmp = "<="
				if op_idx == -1:
					op_idx = spec.findn("<")
					cmp = "<"
				if op_idx == -1:
					op_idx = spec.findn(">")
					cmp = ">"
				if op_idx == -1:
					push_warning("[states] var condition needs a comparison: '%s'" % rule)
					continue
				var vname := _clean(spec.substr(0, op_idx))
				var valstr := _clean(spec.substr(op_idx + cmp.length()))
				if vname.is_empty():
					push_warning("[states] var condition missing a var name: '%s'" % rule)
					continue
				entry["argstr"] = vname
				entry["cmp"] = cmp
				entry["arg"] = _safe_float(valstr, 0.0)
				entry["to"] = _clean(parts[parts.size() - 1])
			"always", "hurt":
				entry["to"] = to
			_:
				push_warning("[states] unknown condition '%s' in '%s'; skipped" % [cond, rule])
				continue
		out.append(entry)
	return out

func _emit_transition_table(parsed: Array) -> String:
	var chunks: Array[String] = []
	for e in parsed:
		chunks.append("{%s}" % ", ".join([
			"%s: %s" % [_q("from"), _q(str(e["from"]))],
			"%s: %s" % [_q("cond"), _q(str(e["cond"]))],
			"%s: %s" % [_q("to"), _q(str(e["to"]))],
			"%s: %s" % [_q("arg"), _num_lit(str(e["arg"]))],
			"%s: %s" % [_q("argstr"), _q(str(e["argstr"]))],
			"%s: %s" % [_q("cmp"), _q(str(e["cmp"]))],
			"%s: %d" % [_q("keycode"), int(e["keycode"])],
		]))
	return ", ".join(chunks)

func _emit_state_list(states: String) -> String:
	var names: Array[String] = []
	for raw in states.split(","):
		var n := _clean(raw)
		if n.is_empty():
			continue
		names.append(_q(n))
	return ", ".join(names)

# ---------------------------------------------------------------------------
# Owner resolution — enemy group first, else first spawned entity, else
# the player. Every branch guarded.
# ---------------------------------------------------------------------------
func _find_owner(ctx, owner_kind: String) -> Node:
	var ents = _ctxv(ctx, "entities", null)
	var player = _ctxv(ctx, "player", null)
	if owner_kind == "player":
		return player if (player is Node and is_instance_valid(player)) else null
	if owner_kind == "enemy":
		# the entities map is filled in pass-1 order; an "enemy" model spawn
		# is the natural owner. Fall back to the first non-player entity.
		if ents is Dictionary:
			for e in ents.values():
				if e is Node and is_instance_valid(e) and str(e.name) == "Enemy":
					return e
			for e in ents.values():
				if e is Node and is_instance_valid(e) and not e.is_in_group("player"):
					return e
		# nothing spawned: the player is a tolerable owner so the machine
		# still ticks (and show_state has something to hang the label on).
		return player if (player is Node and is_instance_valid(player)) else null
	# owner == "scene": the machine owns itself, no entity
	return null

func _owner_key(owner: Node) -> String:
	if owner == null:
		return ""
	return str(owner.name)

func _owner_class(owner: Node, is3: bool) -> String:
	if owner == null:
		return "CharacterBody3D" if is3 else "CharacterBody2D"
	return str(owner.get_class())

# ---------------------------------------------------------------------------
# Multi-machine support: a second State brick reuses the existing machine
# node and registers its config on it. The generated script keeps a
# _configs Array so each State brick has its OWN state table entry.
# ---------------------------------------------------------------------------
func _register_config(machine: Node, var_name: String, initial: String,
		state_list: String, table: String, show_state: bool, is3: bool,
		owner_kind: String, owner_key: String, owner_class: String) -> void:
	# The generated script exposes _register(config) when there is more than
	# one machine; a single-machine compile never calls it.
	if machine.has_method("_register_config"):
		machine.call("_register_config", {
			"var_name": var_name, "initial": initial, "states": state_list,
			"table": table, "show_state": show_state, "is3": is3,
			"owner_kind": owner_kind, "owner_key": owner_key,
			"owner_class": owner_class,
		})

# ---------------------------------------------------------------------------
# Safe readers — a brick may hold anything at all for any key.
# ---------------------------------------------------------------------------
func _claim(b: Dictionary, root: Node) -> bool:
	var rid := root.get_instance_id()
	if rid != _built_root_id:
		_built_root_id = rid
		_built.clear()
	var key := FeatureCtx.bid(b)
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

static func _is_3d(ctx, root: Node) -> bool:
	if ctx is Dictionary:
		var v = (ctx as Dictionary).get("is_3d")
		if v is bool:
			return v
	if root != null:
		return root is Node3D
	return true

static func _safe_float(s: String, fallback: float) -> float:
	if s.is_valid_float():
		var f := float(s)
		if not is_nan(f) and not is_inf(f):
			return f
	return fallback

## Canonical numeric literal: "5" -> 5, "5.5" -> 5.500000 (both valid GDScript).
static func _num_lit(s: String) -> String:
	var f := float(s)
	if absf(f) < 1e15 and is_equal_approx(f, roundf(f)):
		return "%d" % int(roundf(f))
	return "%f" % f

## Text that ends up inside a generated string literal: no newlines, no edges.
static func _clean(s: String) -> String:
	return s.replace("\r", " ").replace("\n", " ").replace("\t", " ").strip_edges()

static func _q(s: String) -> String:
	return "\"" + _clean(s).replace("\\", "\\\\").replace("\"", "\\\"") + "\""

func _attach(node: Node, source: String) -> int:
	var s := GDScript.new()
	s.source_code = source
	var err := s.reload()
	if err == OK:
		node.set_script(s)
	else:
		push_error("[states] generated script failed to compile:\n" + source)
	return err
