extends Node
## undo — a REAL undo/redo system for the editor PLUS an in-game Undo brick.
##
## WHY THIS EXISTS (the coverage was inverted):
##   main.gd kept exactly ONE `_undo_snapshot`, taken only before an AI edit.
##   So the RARE AI edit was undoable while every manual drag, brick add,
##   delete and param tweak was permanently unrecoverable. That is backwards.
##   This module replaces it with a proper bounded command stack.
##
## TWO THINGS, ONE FILE:
##   1. EDITOR-SIDE command stack (a Node the integrator drops into the editor
##      scene and pokes with record()/undo()/redo()). Deep-copies the graph,
##      bounded to max_depth entries. Works with NO bricks at all.
##   2. IN-GAME UndoManager brick (kind "undo") — a Node named "UndoManager"
##      on the scene root that snapshots GameState score/lives/vars + player
##      position into a ring buffer and restores the previous snapshot on a
##      key press.
##
## SCOPE NOTE: the editor UI lives in src/ui/main.gd, which this module must
## NOT edit. So part 1 is built as a service the integrator wires in with a
## few calls. The EXACT wiring is listed under "INTEGRATOR WIRING" below and
## repeated in the module notes.
##
## Nodes created (in-game brick):
##   3D -> Node "UndoManager" on the root + the generated script
##   2D -> Node "UndoManager" on the root + the generated script
##   (one manager per root; a second undo brick merges its settings in, the
##   same dedupe-on-name the Save brick uses)
##
## Params the integrator should add to BrickRef.PARAM_SCHEMA["undo"]:
##   key            choice [Z, U, Backspace]  default "Z"
##   depth          number 1..10 step 1       default 5
##   track_position bool                     default true
##   track_vars     bool                     default true

const KIND := "undo"
const UNDO_MANAGER_NAME := "UndoManager"
const DEPTH_MIN := 1
const DEPTH_MAX := 10

# The Compiler autoload is the parse dependency that pulls FeatureCtx's
# class_name into scope (it declares `const FeatureCtx = preload(...)`).
# A bare `FeatureCtx` type hint here would fail to parse, so we preload it.
const FeatureCtx = preload("res://src/compiler/feature_ctx.gd")

# ===========================================================================
# PART 1 — EDITOR-SIDE COMMAND STACK
# ===========================================================================
# A bounded snapshot stack. The integrator creates one node per editor
# session, calls record(label) BEFORE each graph mutation, and undo()/redo()
# to travel. Every snapshot is a DEEP copy, so a snapshot can never be
# mutated by later edits — the classic undo bug where the "history" turns out
# to be N references to the same live dict.
#
# PUBLIC API (all safe in any order, never throws):
#   record(label: String) -> void   push a deep snapshot of the graph
#   undo() -> bool                  restore the previous snapshot
#   redo() -> bool                  reapply
#   can_undo() -> bool
#   can_redo() -> bool
#   clear() -> void
#   labels() -> Array[String]       the recorded labels, for a history menu
#   max_depth: int = 50             raise/lower the cap at runtime
#
# The graph is attached with attach_graph(graph). The graph needs only
# to_dict()/from_dict(), so any object with those two methods works.

var max_depth: int = 50

var _graph = null            # the BrickGraph this stack drives
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _labels: Array[String] = []

# ---------------------------------------------------------------------------
# Wiring
# ---------------------------------------------------------------------------

## Attach (or swap) the graph this stack snapshots. Clearing the graph leaves
## the history alone; call clear() too if the document was replaced wholesale.
func attach_graph(graph) -> void:
	_graph = graph

func graph():
	return _graph

# ---------------------------------------------------------------------------
# Recording
# ---------------------------------------------------------------------------

## Snapshot the graph AS IT IS NOW and push it onto the undo stack.
##
## Call this BEFORE the mutation, never after — the whole point is that the
## snapshot holds the state you want to go back TO. Returns false when there
## is no graph attached yet, so a caller can log it and move on.
##
## Identical consecutive snapshots are collapsed: a drag that never moved a
## brick, or a param slider that landed back on its old value, must not eat a
## history slot.
func record(label: String = "") -> bool:
	if _graph == null or not is_instance_valid(_graph) or not _graph.has_method("to_dict"):
		return false
	var snap := _snapshot(label)
	if snap.is_empty():
		return false
	if not _undo.is_empty() and _same_body(_undo.back(), snap):
		# same graph content: just refresh the label, don't burn a slot
		_undo[_undo.size() - 1] = snap
		return false
	_undo.append(snap)
	while _undo.size() > max(max_depth, 1):
		_undo.pop_front()
	_labels.append(label)
	while _labels.size() > max(max_depth, 1):
		_labels.pop_front()
	# a new action invalidates the redo branch — standard command-stack rule
	_redo.clear()
	return true

# ---------------------------------------------------------------------------
# Travel
# ---------------------------------------------------------------------------

## Restore the snapshot below the top of the undo stack. Returns false when
## there is nothing to undo (the stack is empty or unset).
func undo() -> bool:
	if _undo.is_empty() or _graph == null or not _graph.has_method("from_dict"):
		return false
	var snap: Dictionary = _undo.pop_back()
	if _labels.size() > 0:
		_labels.resize(_labels.size() - 1)
	var current := _snapshot("")
	if not current.is_empty():
		_redo.append(current)
	while _redo.size() > max(max_depth, 1):
		_redo.pop_front()
	return _apply(snap)

## Reapply the snapshot undone last. Returns false when the redo stack is
## empty.
func redo() -> bool:
	if _redo.is_empty() or _graph == null or not _graph.has_method("from_dict"):
		return false
	var snap: Dictionary = _redo.pop_back()
	var current := _snapshot("")
	if not current.is_empty():
		_undo.append(current)
		while _undo.size() > max(max_depth, 1):
			_undo.pop_front()
		_labels.append("")
		while _labels.size() > max(max_depth, 1):
			_labels.pop_front()
	return _apply(snap)

func can_undo() -> bool:
	return not _undo.is_empty()

func can_redo() -> bool:
	return not _redo.is_empty()

## Drop all history (new project, load, project switch).
func clear() -> void:
	_undo.clear()
	_redo.clear()
	_labels.clear()

## Human-readable history, newest last. Empty when nothing is recorded.
func labels() -> Array[String]:
	var out: Array[String] = []
	out.assign(_labels)
	return out

## How many undo steps are available (for the Undo button's tooltip).
func depth() -> int:
	return _undo.size()

# ---------------------------------------------------------------------------
# Snapshot internals — the part that must stay a DEEP copy
# ---------------------------------------------------------------------------

func _snapshot(label: String) -> Dictionary:
	var raw = _graph.to_dict()
	if not (raw is Dictionary):
		return {}
	var body: Dictionary = raw
	# .duplicate(true) is the deep copy. Without it every "snapshot" would be
	# a live reference into the graph's own brick dicts, and undoing would
	# restore whatever the graph happens to look like now.
	var snap := body.duplicate(true)
	snap["__label"] = str(label)
	return snap

## Compare two snapshots by graph content only, ignoring the label.
static func _same_body(a: Dictionary, b: Dictionary) -> bool:
	var ac: Dictionary = a.duplicate(false)
	var bc: Dictionary = b.duplicate(false)
	ac.erase("__label")
	bc.erase("__label")
	return _dict_eq(ac, bc)

## Structural equality for the plain-JSON values a graph dict is made of:
## dictionaries, arrays, strings, numbers, bools, null. Never throws.
static func _dict_eq(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a:
		if not b.has(k):
			return false
		if not _val_eq(a[k], b[k]):
			return false
	return true

static func _val_eq(a, b) -> bool:
	if a is Dictionary and b is Dictionary:
		return _dict_eq(a, b)
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _val_eq(a[i], b[i]):
				return false
		return true
	if a == null or b == null:
		return a == null and b == null
	return a == b

func _apply(snap: Dictionary) -> bool:
	var body: Dictionary = snap.duplicate(false)
	body.erase("__label")
	_graph.from_dict(body)
	return true

# ===========================================================================
# PART 2 — IN-GAME UNDO BRICK
# ===========================================================================
# Registered kind "undo" -> a Node named "UndoManager" on the scene root,
# carrying a generated script that keeps a ring buffer of the last N
# snapshots and restores the previous one on a key press.
#
# The buffer is fed from _process via a cheap SIGNATURE (score|lives|sorted
# var keys+values|player position). A snapshot is pushed ONLY when the
# signature changed — that comparison is what keeps this O(1)-ish per frame
# instead of deep-copying the whole var table 60 times a second.
#
# WHAT GETS STORED: the state BEFORE the change. The watcher keeps the last
# signature AND its matching snapshot; when a new signature appears it pushes
# the OLD snapshot and only then advances the baseline. Snapshotting the new
# state instead would make an undo restore the very thing the player is trying
# to get away from — a bug this probe suite caught.
#
# VARIABLES ARE RESTORED, NOT MERGED: applying a snapshot erases keys the
# snapshot does not contain, so a variable created after the snapshot really
# disappears on undo instead of lingering.
# ===========================================================================

func register(reg) -> void:
	if reg == null or not reg.has_method("register"):
		push_error("[undo] no feature registry available")
		return
	reg.register(KIND, _build)

# ---------------------------------------------------------------------------
# Builder
# ---------------------------------------------------------------------------

func _build(b: Dictionary, root: Node, ctx) -> void:
	if root == null or not (b is Dictionary):
		return
	var key_name := _clamp_key(FeatureCtx.bstr(b, "key", "Z"))
	var depth := _clamp_depth(FeatureCtx.bnum(b, "depth", 5.0))
	var track_position := FeatureCtx.bbool(b, "track_position", true)
	var track_vars := FeatureCtx.bbool(b, "track_vars", true)

	# one manager per root: a second undo brick merges into the existing one,
	# exactly like the Save brick reuses "SaveManager".
	var existing = _find_manager(root)
	var mgr: Node = existing if existing != null else Node.new()
	var is_new := existing == null
	if is_new:
		mgr.name = UNDO_MANAGER_NAME

	var src := _manager_source(key_name, depth, track_position, track_vars)
	if FeatureCtx.attach_script(mgr, src) != OK:
		push_error("[undo] UndoManager script failed to compile; brick skipped")
		return
	if is_new:
		root.add_child(mgr)

	# publish so other bricks can find it through ctx.entities
	var bid := FeatureCtx.bid(b)
	var ents = _ctxv(ctx, "entities", null)
	if ents is Dictionary and not bid.is_empty():
		ents[bid] = mgr

# ---------------------------------------------------------------------------
# Generated UndoManager source
# ---------------------------------------------------------------------------

func _manager_source(key_name: String, depth: int, track_position: bool,
		track_vars: bool) -> String:
	var L: Array[String] = []
	L.append("extends Node")
	L.append("# Generated by EasyForge from an Undo brick.")
	L.append("# Keeps the last %d snapshots of GameState (score, lives, variables%s)" % [depth, ", position" if track_position else ""])
	L.append("# and restores the previous one when the undo key is pressed.")
	L.append("const UNDO_KEY := %d" % FeatureCtx.keycode(key_name))
	L.append("const UNDO_DEPTH := %d" % depth)
	L.append("const UNDO_TRACK_POSITION := %s" % str(track_position).to_lower())
	L.append("const UNDO_TRACK_VARS := %s" % str(track_vars).to_lower())
	L.append("")
	L.append("var _ring: Array = []   # plain Array: a ring buffer grows by index")
	L.append("var _head := 0          # next write slot in the ring")
	L.append("var _count := 0         # how many snapshots are held (<= DEPTH)")
	L.append("var _last_sig := \"\"")
	L.append("var _last_snap := {}    # the snapshot matching _last_sig")
	L.append("var _baselined := false # has the first frame's signature been seen?")
	L.append("")
	# --- the cheap change detector ---
	L.append("# A tiny signature of everything tracked. Building it is a few")
	L.append("# string concatenations; comparing it is O(1). Only when it")
	L.append("# differs do we deep-copy anything, so an idle game never")
	L.append("# allocates.")
	L.append("func _signature() -> String:")
	L.append("\tvar s := str(int(GameState.score)) + \"|\" + str(int(GameState.lives))")
	L.append("\tif UNDO_TRACK_VARS:")
	L.append("\t\tvar keys := GameState.vars.keys()")
	L.append("\t\tkeys.sort()")
	L.append("\t\tfor k in keys:")
	L.append("\t\t\ts += \";\" + str(k) + \"=\" + str(GameState.vars[k])")
	L.append("\tif UNDO_TRACK_POSITION:")
	L.append("\t\tvar p = _find_player()")
	L.append("\t\tif p != null:")
	L.append("\t\t\ts += \"@\" + str(p.global_position)")
	L.append("\treturn s")
	L.append("")
	# --- snapshot / apply ---
	L.append("func _snapshot() -> Dictionary:")
	L.append("\tvar snap := {}")
	L.append("\tsnap[\"score\"] = int(GameState.score)")
	L.append("\tsnap[\"lives\"] = int(GameState.lives)")
	L.append("\tif UNDO_TRACK_VARS:")
	L.append("\t\tsnap[\"vars\"] = GameState.vars.duplicate(true)")
	L.append("\tif UNDO_TRACK_POSITION:")
	L.append("\t\tvar p = _find_player()")
	L.append("\t\tif p != null:")
	L.append("\t\t\tsnap[\"pos\"] = [p.global_position.x, p.global_position.y]")
	L.append("\treturn snap")
	L.append("")
	L.append("func _push(snap: Dictionary) -> void:")
	L.append("	if snap.is_empty():")
	L.append("		return")
	L.append("	if UNDO_DEPTH <= 0:")
	L.append("		return")
	# _ring is a plain Array on purpose: a typed Array[Dictionary] rejects an
	# out-of-bounds index assignment, which is exactly how a ring buffer grows.
	L.append("	while _ring.size() < UNDO_DEPTH:")
	L.append("		_ring.append({})")
	L.append("	if _head >= _ring.size():")
	L.append("		_head = 0")
	L.append("	_ring[_head] = snap")
	L.append("	_head = (_head + 1) % UNDO_DEPTH")
	L.append("	_count = mini(_count + 1, UNDO_DEPTH)")
	L.append("")
	# --- the previous snapshot = the oldest still held, then it is consumed ---
	L.append("func _pop() -> Dictionary:")
	L.append("	if _count <= 0 or _ring.is_empty():")
	L.append("		return {}")
	L.append("	var oldest := (_head - _count + _ring.size()) % _ring.size()")
	L.append("	if oldest < 0 or oldest >= _ring.size():")
	L.append("		return {}")
	L.append("	var snap: Dictionary = _ring[oldest]")
	L.append("	_ring[oldest] = {}")
	L.append("	_count -= 1")
	L.append("	return snap")
	L.append("")
	# --- restore, hardened against every corrupt-snapshot shape ---
	L.append("func _apply(snap) -> void:")
	L.append("	if not (snap is Dictionary) or (snap as Dictionary).is_empty():")
	L.append("		return")
	L.append("	var d: Dictionary = snap")
	L.append("	var s = d.get(\"score\", null)")
	L.append("	if s is int or s is float:")
	L.append("		GameState.score = int(s)")
	L.append("	var lv = d.get(\"lives\", null)")
	L.append("	if lv is int or lv is float:")
	L.append("		GameState.lives = int(lv)")
	L.append("	if UNDO_TRACK_VARS:")
	L.append("		var v = d.get(\"vars\", null)")
	L.append("		if v is Dictionary:")
	# A snapshot must RESTORE the variable table, not merge into it: merging
	# would leave a variable created after the snapshot in place, so an undo
	# would appear to do nothing. Keys absent from the snapshot go back to
	# their pre-snapshot state by being removed (GameState.get_var then
	# returns the caller's default again, which is the same behaviour it had
	# before the variable ever existed).
	L.append("			for k in GameState.vars.keys():")
	L.append("				if not (v as Dictionary).has(k):")
	L.append("					GameState.vars.erase(k)")
	L.append("			for k in v:")
	L.append("				GameState.set_var(str(k), v[k])")
	L.append("	if UNDO_TRACK_POSITION:")
	L.append("		var pos = d.get(\"pos\", null)")
	L.append("		if pos is Array and pos.size() >= 2:")
	L.append("			var px: float = float(pos[0]) if (pos[0] is int or pos[0] is float) else 0.0")
	L.append("			var py: float = float(pos[1]) if (pos[1] is int or pos[1] is float) else 0.0")
	L.append("			var p = _find_player()")
	L.append("			if p != null:")
	L.append("				p.global_position = Vector2(px, py) if p is Node2D else Vector3(px, py, 0.0)")
	L.append("	# re-baseline so the restored state is not immediately")
	L.append("	# re-snapshotted as a brand new step")
	L.append("	_last_sig = _signature()")
	L.append("	_last_snap = _snapshot()")
	L.append("	_baselined = true")
	L.append("")
	# --- per-frame watcher ---
	# _last_sig is the signature of the state we have ALREADY stored. When it
	# differs from the current one, the previous state is exactly what an undo
	# must restore, so we push the PREVIOUS state and only then move the
	# baseline forward. Snapshotting the current state instead would make undo
	# restore the thing you are trying to get away from.
	L.append("func _process(_delta: float) -> void:")
	L.append("	if GameState.game_over:")
	L.append("		return")
	L.append("	var sig := _signature()")
	L.append("	if _baselined and sig == _last_sig:")
	L.append("		return")
	L.append("	if _baselined:")
	L.append("		_push(_last_snap)")
	L.append("	_last_snap = _snapshot()")
	L.append("	_last_sig = sig")
	L.append("	_baselined = true")
	L.append("")
	# --- the key press ---
	L.append("func _unhandled_input(event: InputEvent) -> void:")
	L.append("\tif not (event is InputEventKey):")
	L.append("\t\treturn")
	L.append("\tif not event.pressed or event.echo:")
	L.append("\t\treturn")
	L.append("\tif event.keycode != UNDO_KEY:")
	L.append("\t\treturn")
	L.append("\tvar snap := _pop()")
	L.append("\tif snap.is_empty():")
	L.append("\t\treturn")
	L.append("\t_apply(snap)")
	L.append("")
	# --- player lookup (null-safe: many games have no player at all) ---
	L.append("func _find_player() -> Node:")
	L.append("\tvar players = get_tree().get_nodes_in_group(\"player\")")
	L.append("\tif players.size() > 0:")
	L.append("\t\treturn players[0]")
	L.append("\tvar root = get_parent()")
	L.append("\tif root != null and root.has_node(\"Player\"):")
	L.append("\t\treturn root.get_node(\"Player\")")
	L.append("\treturn null")
	L.append("")
	return "\n".join(L)

func _find_manager(root: Node) -> Node:
	if root == null:
		return null
	for child in root.get_children():
		if child == null or not is_instance_valid(child):
			continue
		if str(child.name) == UNDO_MANAGER_NAME:
			return child
	return null

# ---------------------------------------------------------------------------
# Clamped param readers — the brick may carry anything at all.
# ---------------------------------------------------------------------------

func _clamp_depth(v: float) -> int:
	if v != v or v == INF or v == -INF:   # NaN / inf guard
		return 5
	return int(clampi(int(round(v)), DEPTH_MIN, DEPTH_MAX))

func _clamp_key(v: String) -> String:
	var s := str(v).strip_edges()
	match s:
		"Z", "U", "Backspace":
			return s
		_:
			return "Z"

# ---------------------------------------------------------------------------
# ctx reader — works whether the compiler hands us a Dictionary (what
# Compiler actually passes) or a FeatureCtx object.
# ---------------------------------------------------------------------------

static func _ctxv(ctx, key: String, default_value):
	if ctx is Dictionary:
		var v = (ctx as Dictionary).get(key)
		return v if v != null else default_value
	if ctx != null:
		for prop in ctx.get_property_list():
			if str(prop.get("name", "")) == key:
				return ctx.get(key)
	return default_value

# ===========================================================================
# INTEGRATOR WIRING (src/ui/main.gd — NOT edited by this module)
# ===========================================================================
# The editor's own widgets live in main.gd, so the stack is wired in there by
# the integrator with these six calls:
#
#   1. Declare, next to `var _undo_snapshot`:
#        var undo_svc: Node = null
#
#   2. In _ready(), before load_graph_dict(DemoTemplates.platformer()):
#        undo_svc = load("res://src/features/undo.gd").new()
#        undo_svc.max_depth = 50
#        add_child(undo_svc)
#        undo_svc.attach_graph(graph)
#
#   3. Record BEFORE every graph mutation (one line each):
#        - _add_brick()            first line after the empty-brick guard:
#                                  undo_svc.record("add brick")
#        - _paste_brick()          first line after the _clipboard.is_empty() guard:
#                                  undo_svc.record("paste brick")
#        - _on_brick_menu()        in case 3 (Delete), BEFORE graph.remove_brick():
#                                  undo_svc.record("delete brick")
#        - _on_edit_pressed()      replace `_undo_snapshot = graph.to_dict().duplicate(true)` with:
#                                  undo_svc.record("AI edit")
#        - inspector param edits   in _close_inspector() (and wherever a param
#                                  control writes through), before the writes land:
#                                  undo_svc.record("edit settings")
#
#   4. Rewrite the Undo button:
#        func _on_undo_pressed() -> void:
#            if undo_svc == null:
#                return
#            if undo_svc.undo():
#                load_graph_dict(graph.to_dict())   # re-render from the restored graph
#            if undo_btn != null:
#                undo_btn.disabled = not undo_svc.can_undo()
#
#   5. Wire Redo (new button, same row):
#        func _on_redo_pressed() -> void:
#            if undo_svc == null:
#                return
#            if undo_svc.redo():
#                load_graph_dict(graph.to_dict())
#            if redo_btn != null:
#                redo_btn.disabled = not undo_svc.can_redo()
#
#   6. Keep the buttons honest (call after any record/undo/redo):
#        undo_btn.disabled = not undo_svc.can_undo()
#        redo_btn.disabled = not undo_svc.can_redo()
#      `undo_svc.labels()` returns the recorded action names for a
#      Ctrl+Z / Ctrl+Y tooltip or a history dropdown.
#
# The stack is fully usable WITHOUT the in-game brick — steps 1-6 need no
# "undo" kind registered at all.
