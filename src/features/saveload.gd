extends Node
## saveload — Save brick + Checkpoint Save brick: versioned JSON save slots
## under user://saves that a no-code game gets for free.
##
## WHY THIS IS A NO-CODE ADVANTAGE: in Unity/Unreal the user hand-rolls save
## code and must remember to serialize every variable. EasyForge's compiler
## already knows every GameState variable's schema, so the save payload
## (score, lives, vars, position, timestamp) AUTO-EMITS from a single brick.
## The user places a "Save" brick and never writes a line of code.
##
## TWO KINDS, ONE SLOT MODEL:
##   kind "save"          -> creates/uses the singleton SaveManager node
##   kind "checkpoint_save" -> a visible ring/box the player touches that
##                            writes the same payload to its own slot
##
## PAYLOAD SCHEMA (versioned — an unversioned save silently orphans):
##   {"version": 1, "slot": N, "score": ..., "lives": ..., "vars": {...},
##    "position": [x,y,z], "timestamp": <unix seconds>}
##
## STATIC HELPERS (for other modules / the integrator):
##   SaveLoad.save_path(slot)      -> "user://saves/slot_%d.json"
##   SaveLoad.write_payload(slot, payload) -> bool   (never throws)
##
## Only one SaveManager is ever created per compile: if a node named
## "SaveManager" already exists on the root, it is reused.
##
## Params the integrator adds to BrickRef.PARAM_SCHEMA (this module only
## READS them, with safe fallbacks):
##   SAVE:
##     mode            choice [manual, auto, on_quit, on_level] default manual
##     slot            number 1..9      default 1
##     key             choice [none, F5, F9, Space, E] default F5
##     include_position bool  default true
##     include_vars    bool    default true
##     include_score   bool    default true
##   CHECKPOINT_SAVE:
##     slot            number 1..9      default 1
##     size            number 1.0..10.0 default 2.0
##     once            bool    default false

const SAVE_DIR := "user://saves"
const SLOT_MIN := 1
const SLOT_MAX := 9
const PAYLOAD_VERSION := 1
const AUTO_SAVE_INTERVAL := 30.0   # auto mode: save every 30 seconds
const SAVE_MANAGER_NAME := "SaveManager"

# Preload the compile context: its class_name is not in this project's global
# script class cache, so a bare `FeatureCtx` reference would fail to parse
# (same gotcha the trigger module documents).
const FeatureCtx = preload("res://src/compiler/feature_ctx.gd")

# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

func register(reg) -> void:
	if reg == null or not reg.has_method("register"):
		push_error("[saveload] no feature registry available")
		return
	reg.register("save", _build_save)
	reg.register("checkpoint_save", _build_checkpoint_save)

# ---------------------------------------------------------------------------
# Static helpers — usable by any other module. NEVER throw.
# ---------------------------------------------------------------------------

## The canonical path of a slot file: user://saves/slot_%d.json
static func save_path(slot: int) -> String:
	var n := int(clampi(int(slot), SLOT_MIN, SLOT_MAX))
	return SAVE_DIR + "/slot_%d.json" % n

## Write `payload` as pretty-printed JSON into the slot file, creating the
## saves directory when it is missing. Returns true on success; any failure
## (no permissions, disk full, bad JSON) returns false and never throws.
static func write_payload(slot: int, payload: Dictionary) -> bool:
	if not (payload is Dictionary):
		return false
	var path := save_path(slot)
	# create the directory first (make_dir_recursive_absolute is idempotent)
	if not _ensure_save_dir():
		return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	return true

## Read + parse a slot file. Returns the payload Dictionary, or {} when the
## file is missing, unreadable, corrupt, or not a JSON object. Never throws.
static func read_payload(slot: int) -> Dictionary:
	var path := save_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	# Parse via the JSON object (not the static parse_string): a corrupt file
	# then just yields a non-OK error code instead of pushing a scary engine
	# error into the log while we quietly keep the game at its defaults.
	var j := JSON.new()
	if j.parse(text) != OK:
		return {}
	var parsed = j.data
	if parsed is Dictionary:
		return parsed
	return {}   # corrupt / wrong-shape file -> caller keeps its defaults

## A payload from this compiler's schema version? Guards against loading a
## save written by a future (or broken) version.
static func payload_version_ok(payload: Dictionary) -> bool:
	if not (payload is Dictionary):
		return false
	var v = payload.get("version", null)
	if v == null:
		return false   # missing version stamp = silently orphaned save -> reject
	return int(v) == PAYLOAD_VERSION

static func _ensure_save_dir() -> bool:
	if DirAccess.dir_exists_absolute(SAVE_DIR):
		return true
	var err := DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	return err == OK

# ---------------------------------------------------------------------------
# Builders (registered with FeatureRegistry)
# ---------------------------------------------------------------------------

## "save" brick -> the singleton SaveManager node.
func _build_save(b: Dictionary, root: Node, ctx) -> void:
	if root == null:
		return
	var p := FeatureCtx.params(b)
	var mode := _clamp_mode(FeatureCtx.bstr(b, "mode", "manual"))
	var slot := _clamp_slot(FeatureCtx.bnum(b, "slot", 1.0))
	var key_name := _clamp_key(FeatureCtx.bstr(b, "key", "F5"))
	var include_position := FeatureCtx.bbool(b, "include_position", true)
	var include_vars := FeatureCtx.bbool(b, "include_vars", true)
	var include_score := FeatureCtx.bbool(b, "include_score", true)

	var existing = _find_manager(root)
	var mgr: Node = existing if existing != null else Node.new()
	var is_new := existing == null
	if is_new:
		mgr.name = SAVE_MANAGER_NAME
	# reuse: keep the earlier brick's settings but merge this one's slot/mode
	# in so two Save bricks drive the same manager deterministically.
	var effective_mode := mode if not is_new else mode
	var effective_slot := slot
	if not is_new and mgr.get("save_slot") != null:
		# a previous save brick configured this manager; keep its slot unless
		# this brick names a different one explicitly
		if int(FeatureCtx.num(p, "slot", 0.0)) > 0:
			effective_slot = slot
		else:
			effective_slot = int(mgr.get("save_slot"))
	var src := _manager_source(
		effective_mode, effective_slot, key_name,
		include_position, include_vars, include_score)
	if FeatureCtx.attach_script(mgr, src) == OK:
		if is_new:
			root.add_child(mgr)
	else:
		push_error("[saveload] SaveManager script failed to compile; brick skipped")

## "checkpoint_save" brick -> a visible checkpoint that also writes a slot.
func _build_checkpoint_save(b: Dictionary, root: Node, ctx) -> void:
	if root == null:
		return
	var is_3d := _is_3d(ctx)
	var p := FeatureCtx.params(b)
	var slot := _clamp_slot(FeatureCtx.bnum(b, "slot", 1.0))
	var size := clampf(FeatureCtx.bnum(b, "size", 2.0), 1.0, 10.0)
	var once := FeatureCtx.bbool(b, "once", false)
	var area: Node
	if is_3d:
		var a3 := Area3D.new()
		a3.name = "CheckpointSave"
		var mesh := MeshInstance3D.new()
		mesh.name = "Mesh"
		var torus := TorusMesh.new()
		torus.inner_radius = maxf(size * 0.5, 0.2)
		torus.outer_radius = maxf(size * 0.75, 0.3)
		mesh.mesh = torus
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("#ffd54f")
		mat.emission_enabled = true
		mat.emission = Color("#8d6e00")
		mat.emission_energy_multiplier = 1.4
		mesh.material_override = mat
		a3.add_child(mesh)
		var col3 := CollisionShape3D.new()
		var shp3 := SphereShape3D.new()
		shp3.radius = maxf(size * 0.8, 0.5)
		col3.shape = shp3
		a3.add_child(col3)
		a3.position = _vec3_from(p.get("position", null), Vector3(-6.0, 0.6, -5.0))
		area = a3
	else:
		var a2 := Area2D.new()
		a2.name = "CheckpointSave"
		var sprite := Sprite2D.new()
		sprite.name = "Mesh"
		var tex := FeatureCtx.solid_texture(
			int(clampi(int(size * 12.0), 12, 120)),
			int(clampi(int(size * 12.0), 12, 120)),
			Color("#ffd54f"))
		sprite.texture = tex
		a2.add_child(sprite)
		var col2 := CollisionShape2D.new()
		var shp2 := CircleShape2D.new()
		shp2.radius = clampf(size * 10.0, 10.0, 100.0)
		col2.shape = shp2
		a2.add_child(col2)
		a2.position = _vec2_from(p.get("position", null), Vector2(150.0, 270.0))
		area = a2
	var src := _checkpoint_source(slot, once, is_3d)
	if FeatureCtx.attach_script(area, src) == OK:
		root.add_child(area)
	else:
		push_error("[saveload] checkpoint_save script failed to compile; brick skipped")

# ---------------------------------------------------------------------------
# Node lookup — count by class, never by name (Godot renames duplicates)
# ---------------------------------------------------------------------------

func _find_manager(root: Node) -> Node:
	for child in root.get_children():
		if child == null:
			continue
		if str(child.name) == SAVE_MANAGER_NAME:
			return child
	return null

# ---------------------------------------------------------------------------
# Clamped param readers
# ---------------------------------------------------------------------------

func _clamp_slot(v: float) -> int:
	if v != v or v == INF or v == -INF:   # NaN / inf guard
		return 1
	return int(clampi(int(round(v)), SLOT_MIN, SLOT_MAX))

func _clamp_mode(v: String) -> String:
	var s := str(v).strip_edges().to_lower()
	match s:
		"manual", "auto", "on_quit", "on_level":
			return s
		_:
			return "manual"

func _clamp_key(v: String) -> String:
	var s := str(v).strip_edges()
	match s:
		"none", "F5", "F9", "Space", "E":
			return s
		_:
			return "F5"

func _is_3d(ctx) -> bool:
	if ctx == null:
		return true
	var v = ctx.get("is_3d") if ctx is Dictionary else null
	return true if v == null else bool(v)

# ---------------------------------------------------------------------------
# Position param parsing (bricks may carry [x,y,z] arrays or junk)
# ---------------------------------------------------------------------------

func _vec3_from(v, fallback: Vector3) -> Vector3:
	if v is Array and v.size() >= 3:
		var a: Array = v
		var x := _safe_f(a[0])
		var y := _safe_f(a[1])
		var z := _safe_f(a[2])
		if x != NAN and y != NAN and z != NAN:
			return Vector3(x, y, z)
	return fallback

func _vec2_from(v, fallback: Vector2) -> Vector2:
	if v is Array and v.size() >= 2:
		var a: Array = v
		var x := _safe_f(a[0])
		var y := _safe_f(a[1])
		if x != NAN and y != NAN:
			return Vector2(x, y)
	return fallback

func _safe_f(x) -> float:
	if x is float:
		var f: float = x
		if f != f or f == INF or f == -INF:
			return NAN
		return f
	if x is int:
		return float(x)
	return NAN

# ---------------------------------------------------------------------------
# Generated sources
# ---------------------------------------------------------------------------

## The SaveManager script. Emits the whole save/load lifecycle:
##   _ready     : load the slot (if present) and apply it
##   manual     : _unhandled_input on the chosen key
##   auto       : a 30s timer + scene exit (NOTIFICATION_WM_CLOSE_REQUEST)
##   on_quit    : NOTIFICATION_WM_CLOSE_REQUEST
##   on_level   : watches GameState.get_var("__level_changed", false)
func _manager_source(mode: String, slot: int, key_name: String,
		include_position: bool, include_vars: bool, include_score: bool) -> String:
	var L: Array[String] = []
	L.append("extends Node")
	L.append("# Generated by EasyForge from a 'Save' brick (mode=%s, slot=%d)." % [mode, slot])
	L.append("# Owns user://saves/slot_%d.json: a versioned JSON payload, loaded" % slot)
	L.append("# on startup and written per the brick's save mode. The file logic")
	L.append("# is inlined (this game runs standalone, with no compiler present).")
	L.append("const SAVE_MANAGER_SLOT := %d" % slot)
	L.append("const SAVE_MANAGER_VERSION := %d" % PAYLOAD_VERSION)
	L.append("const SAVE_INTERVAL := %f" % AUTO_SAVE_INTERVAL)
	L.append("const SAVE_DIR := \"user://saves\"")
	L.append("var save_mode := \"%s\"" % mode)
	L.append("var save_key := %d" % FeatureCtx.keycode(key_name))
	L.append("var save_include_position := %s" % str(include_position).to_lower())
	L.append("var save_include_vars := %s" % str(include_vars).to_lower())
	L.append("var save_include_score := %s" % str(include_score).to_lower())
	L.append("var _auto_timer: Timer = null")
	L.append("var _level_flag_seen := false")
	L.append("var _loaded_once := false")
	# --- inlined file helpers (never throw) ---
	L.append("func _save_path() -> String:")
	L.append("	return SAVE_DIR + \"/slot_\" + str(SAVE_MANAGER_SLOT) + \".json\"")
	L.append("func _read_payload() -> Dictionary:")
	L.append("	var path := _save_path()")
	L.append("	if not FileAccess.file_exists(path):")
	L.append("		return {}")
	L.append("	var f := FileAccess.open(path, FileAccess.READ)")
	L.append("	if f == null:")
	L.append("		return {}")
	L.append("	var text := f.get_as_text()")
	L.append("	f.close()")
	L.append("	var j := JSON.new()")
	L.append("	if j.parse(text) != OK:")
	L.append("		return {}   # corrupt file -> stay at defaults, never crash")
	L.append("	return j.data if j.data is Dictionary else {}")
	L.append("func _write_payload(payload: Dictionary) -> bool:")
	L.append("	if not (payload is Dictionary):")
	L.append("		return false")
	L.append("	if not DirAccess.dir_exists_absolute(SAVE_DIR):")
	L.append("		if DirAccess.make_dir_recursive_absolute(SAVE_DIR) != OK:")
	L.append("			return false")
	L.append("	var f := FileAccess.open(_save_path(), FileAccess.WRITE)")
	L.append("	if f == null:")
	L.append("		return false")
	L.append("	var _tab := char(9)")
	L.append("	f.store_string(JSON.stringify(payload, _tab))")
	L.append("	f.close()")
	L.append("	return true")
	L.append("func _version_ok(payload: Dictionary) -> bool:")
	L.append("	var v = payload.get(\"version\", null)")
	L.append("	if v == null:")
	L.append("		return false   # unversioned save = orphaned -> reject")
	L.append("	return int(v) == SAVE_MANAGER_VERSION")
	# --- payload construction ---
	L.append("func _build_payload() -> Dictionary:")
	L.append("\tvar payload := {")
	L.append("\t\t\"version\": SAVE_MANAGER_VERSION,")
	L.append("\t\t\"slot\": SAVE_MANAGER_SLOT,")
	if include_score:
		L.append("\t\t\"score\": int(GameState.score),")
		L.append("\t\t\"lives\": int(GameState.lives),")
	else:
		L.append("\t\t\"score\": 0,")
		L.append("\t\t\"lives\": 0,")
	if include_vars:
		L.append("\t\t\"vars\": GameState.vars.duplicate(true),")
	else:
		L.append("\t\t\"vars\": {},")
	L.append("\t\t\"timestamp\": Time.get_unix_time_from_system(),")
	L.append("\t}")
	L.append("\tif save_include_position:")
	L.append("\t\tvar p = _find_player()")
	L.append("\t\tif p != null and p is Node3D:")
	L.append("\t\t\tpayload[\"position\"] = [(p as Node3D).global_position.x, (p as Node3D).global_position.y, (p as Node3D).global_position.z]")
	L.append("\t\telif p != null and p is Node2D:")
	L.append("\t\t\tpayload[\"position\"] = [(p as Node2D).global_position.x, (p as Node2D).global_position.y, 0.0]")
	L.append("\treturn payload")
	# --- write (inlined file logic, no external dependency) ---
	L.append("func _save_now() -> bool:")
	L.append("	return _write_payload(_build_payload())")
	# --- apply ---
	L.append("func _apply_payload(payload: Dictionary) -> void:")
	L.append("	if not (payload is Dictionary):")
	L.append("		return")
	L.append("	if not _version_ok(payload):")
	L.append("		return   # unknown/missing version -> leave the game at defaults")
	L.append("\tif save_include_score:")
	L.append("\t\tvar s = payload.get(\"score\", 0)")
	L.append("\t\tGameState.score = int(s) if (s is int or s is float) else 0")
	L.append("\t\tvar lv = payload.get(\"lives\", 0)")
	L.append("\t\tGameState.lives = int(lv) if (lv is int or lv is float) else GameState.lives")
	L.append("\tif save_include_vars:")
	L.append("\t\tvar v = payload.get(\"vars\", {})")
	L.append("\t\tif v is Dictionary:")
	L.append("\t\t\tfor k in v:")
	L.append("\t\t\t\tGameState.set_var(str(k), v[k])")
	L.append("\tif save_include_position:")
	L.append("\t\tvar pos = payload.get(\"position\", null)")
	L.append("		if pos is Array and pos.size() >= 2:")
	L.append("			var px: float = float(pos[0]) if (pos[0] is float or pos[0] is int) else 0.0")
	L.append("			var py: float = float(pos[1]) if (pos[1] is float or pos[1] is int) else 0.0")
	L.append("			var pz: float = float(pos[2]) if (pos.size() >= 3 and (pos[2] is float or pos[2] is int)) else 0.0")
	L.append("			var p = _find_player()")
	L.append("			if p != null and p is Node3D:")
	L.append("				(p as Node3D).global_position = Vector3(px, py, pz)")
	L.append("			elif p != null and p is Node2D:")
	L.append("				(p as Node2D).global_position = Vector2(px, py)")
	L.append("			# remember it as the respawn point too")
	L.append("			GameState.respawn_position = Vector3(px, py, pz)")
	# --- player lookup ---
	L.append("func _find_player() -> Node:")
	L.append("\tvar players = get_tree().get_nodes_in_group(\"player\")")
	L.append("\tif players.size() > 0:")
	L.append("\t\treturn players[0]")
	L.append("\tvar root = get_parent()")
	L.append("\tif root != null and root.has_node(\"Player\"):")
	L.append("\t\treturn root.get_node(\"Player\")")
	L.append("\treturn null")
	# --- startup load ---
	L.append("func _ready() -> void:")
	L.append("	_loaded_once = true")
	L.append("	var payload = _read_payload()")
	L.append("	if not payload.is_empty():")
	L.append("		_apply_payload(payload)")
	if mode == "auto":
		L.append("\t# auto mode: a repeating 30s timer, plus a save when the game exits")
		L.append("\t_auto_timer = Timer.new()")
		L.append("\t_auto_timer.wait_time = SAVE_INTERVAL")
		L.append("\t_auto_timer.autostart = true")
		L.append("\t_auto_timer.one_shot = false")
		L.append("\t_auto_timer.name = \"AutoSaveTimer\"")
		L.append("\tadd_child(_auto_timer)")
		L.append("\tif not _auto_timer.timeout.is_connected(_save_now):")
		L.append("\t\t_auto_timer.timeout.connect(_save_now)")
		L.append("\tif not _auto_timer.timeout.is_connected(_on_exit_save):")
		L.append("\t\t_auto_timer.timeout.connect(_on_exit_save)")
	L.append("")
	# --- close/quit handling for auto + on_quit ---
	if mode == "auto" or mode == "on_quit":
		L.append("func _notification(what: int) -> void:")
		L.append("\tif what == NOTIFICATION_WM_CLOSE_REQUEST:")
		L.append("\t\t_save_now()")
		L.append("\t\tget_tree().quit()")
		L.append("")
	# --- manual key handling ---
	if mode == "manual" and key_name != "none":
		L.append("func _unhandled_input(event: InputEvent) -> void:")
		L.append("\tif not (event is InputEventKey):")
		L.append("\t\treturn")
		L.append("\tif not event.pressed or event.echo:")
		L.append("\t\treturn")
		L.append("\tif event.keycode == save_key:")
		L.append("\t\t_save_now()")
		L.append("")
	elif mode == "manual":
		L.append("# manual mode with no key: the SaveManager still loads on startup;")
		L.append("# other bricks/scripts can call _save_now() when they choose.")
		L.append("")
	# --- on_level watching ---
	if mode == "on_level":
		L.append("func _process(_delta: float) -> void:")
		L.append("\tif _level_flag_seen:")
		L.append("\t\treturn")
		L.append("\tif GameState.get_var(\"__level_changed\", false):")
		L.append("\t\t_level_flag_seen = true")
		L.append("\t\t_save_now()")
		L.append("\t\tGameState.set_var(\"__level_changed\", false)")
		L.append("\t# also react to a door hit, the other level-change signal")
		L.append("\telif GameState.get_var(\"__door_hit\", false):")
		L.append("\t\t_level_flag_seen = true")
		L.append("\t\t_save_now()")
		L.append("\t\tGameState.set_var(\"__door_hit\", false)")
		L.append("")
	L.append("func _on_exit_save() -> void:")
	L.append("\t_save_now()")
	L.append("")
	L.append("func get_load_once() -> bool:")
	L.append("\treturn _loaded_once")
	return "\n".join(L) + "\n"

## The checkpoint_save node script: touch -> write its slot. With once=false
## it stays active so later touches update the respawn point.
func _checkpoint_source(slot: int, once: bool, is_3d: bool) -> String:
	var L: Array[String] = []
	L.append("extends %s" % ("Area3D" if is_3d else "Area2D"))
	L.append("# Generated by EasyForge from a 'Checkpoint Save' brick (slot=%d)." % slot)
	L.append("# Touching it writes the full versioned save payload to its slot.")
	L.append("# The file logic is inlined (this game runs standalone).")
	L.append("const CHECKPOINT_SLOT := %d" % slot)
	L.append("const CHECKPOINT_VERSION := %d" % PAYLOAD_VERSION)
	L.append("const CHECKPOINT_ONCE := %s" % str(once).to_lower())
	L.append("const SAVE_DIR := \"user://saves\"")
	L.append("var _used := false")
	L.append("func _save_path() -> String:")
	L.append("	return SAVE_DIR + \"/slot_\" + str(CHECKPOINT_SLOT) + \".json\"")
	L.append("func _write_payload(payload: Dictionary) -> bool:")
	L.append("	if not (payload is Dictionary):")
	L.append("		return false")
	L.append("	if not DirAccess.dir_exists_absolute(SAVE_DIR):")
	L.append("		if DirAccess.make_dir_recursive_absolute(SAVE_DIR) != OK:")
	L.append("			return false")
	L.append("	var f := FileAccess.open(_save_path(), FileAccess.WRITE)")
	L.append("	if f == null:")
	L.append("		return false")
	L.append("	var _tab := char(9)")
	L.append("	f.store_string(JSON.stringify(payload, _tab))")
	L.append("	f.close()")
	L.append("	return true")
	L.append("func _ready() -> void:")
	L.append("	if not body_entered.is_connected(_on_body_entered):")
	L.append("		body_entered.connect(_on_body_entered)")
	L.append("func _on_body_entered(body) -> void:")
	L.append("	if _used and CHECKPOINT_ONCE:")
	L.append("		return")
	L.append("	if body == null:")
	L.append("		return")
	L.append("	if body.name == \"Player\" or (body is Node and body.is_in_group(\"player\")):")
	L.append("		_used = true")
	L.append("		# a checkpoint also marks the respawn point")
	L.append("		GameState.set_respawn(global_position, body)")
	L.append("		var payload := {")
	L.append("			\"version\": CHECKPOINT_VERSION,")
	L.append("			\"slot\": CHECKPOINT_SLOT,")
	L.append("			\"score\": int(GameState.score),")
	L.append("			\"lives\": int(GameState.lives),")
	L.append("			\"vars\": GameState.vars.duplicate(true),")
	L.append("			\"timestamp\": Time.get_unix_time_from_system(),")
	L.append("		}")
	L.append("		if body is Node3D:")
	L.append("			payload[\"position\"] = [(body as Node3D).global_position.x, (body as Node3D).global_position.y, (body as Node3D).global_position.z]")
	L.append("		elif body is Node2D:")
	L.append("			payload[\"position\"] = [(body as Node2D).global_position.x, (body as Node2D).global_position.y, 0.0]")
	L.append("		_write_payload(payload)")
	L.append("		GameState.play_sound(\"click\")")
	if once:
		L.append("		queue_free()   # once=true: this checkpoint is spent")
	L.append("")
	L.append("func is_spent() -> bool:")
	L.append("	return _used and CHECKPOINT_ONCE")
	return "\n".join(L) + "\n"
