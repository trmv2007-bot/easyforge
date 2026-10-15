extends Node   # autoloads must inherit Node
## Compiler — bricks (JSON) -> playable Godot 4 game.
##
## Registered as the autoload singleton "Compiler" (project.godot).
##
## This is the deterministic core. The AI never writes final code; it drafts
## bricks. THIS module turns the settled graph into real GDScript + a scene.
## That split is the whole reliability argument in the spec:
##   AI drafts structure -> human owns flow -> compiler emits code -> always runs.
##
## Output: a scene tree (root Node3D/Node2D) built at runtime, plus one
## generated script per entity. Nothing here is shown to the user; the user
## sees bricks and a running game. (The Visual/Code escape hatch shows the
## generated script text — see generated_script().)
##
## HARDENING RULES (the AI WILL sometimes emit junk):
##   - every brick key is read through a safe accessor: a brick may have no
##     params, connections, inputs, outputs, id or kind at all
##   - every array index is bounds-checked
##   - compile_graph NEVER throws: a garbage graph still compiles to a
##     best-effort scene, because "errors never crash the app" is a spec rule
##   - an unknown brick kind falls back to a labeled placeholder

signal compiled(scene_root: Node)
signal compile_failed(issues: Array)

var _3d := true
var _camera_cfg: Dictionary = {}      # from a Camera brick (mode/distance/height/smooth)
var _has_camera_brick := false
var _controls: Dictionary = {}        # player key bindings from the Spawn brick
var _has_tile_ground := false         # a Level brick already provides the floor

# ---------------------------------------------------------------------------
# Entry point — always returns a scene root, never null, never throws.
# ---------------------------------------------------------------------------
func compile_graph(graph) -> Node:
	# normalize input: accept a BrickGraph object OR a raw Dictionary (AI JSON)
	var g = graph
	if g is Dictionary:
		var fresh = load("res://src/bricks/graph.gd").new()
		if fresh != null:
			fresh.from_dict(g)
			g = fresh

	var issues := []
	if g != null and g.has_method("validate"):
		issues = g.validate()
	_3d = not (str(_prop(g, "dimension", "3d")) == "2d")
	_has_tile_ground = false   # reset per compile; a Level brick sets it
	_camera_cfg = {}
	_has_camera_brick = false
	_controls = {}
	_var_bricks = {}

	var root: Node
	if _3d:
		root = Node3D.new()
		root.name = "EasyForgeGame3D"
	else:
		root = Node2D.new()
		root.name = "EasyForgeGame2D"

	# per-game state attached to the root (score, lives, win/lose)
	var state = GameStateClass.new()
	root.add_child(state)
	# generated scripts + the HUD talk to the GameState AUTOLOAD by name, so
	# the same rules must live there too — reset both so every Play is fresh.
	var global_state = _global_state()
	var bricks := _bricks_of(g)
	state.reset()
	if global_state != null and global_state.has_method("reset"):
		global_state.reset()
	# Seed Variable-brick values AFTER the resets, or reset() wipes them and a
	# Rule comparing the var sees nothing. Seed the AUTOLOAD by its global
	# identifier (the exact name generated game scripts call) AND mirror onto
	# the per-root state. We deliberately do NOT use Engine.get_singleton here:
	# in some launch contexts the singleton handle is a distinct object from
	# the autoload identifier the generated code binds to, so seeding through
	# it would land on an object nothing reads.
	for b in bricks:
		if _kind(b) == "variable":
			if global_state != null and global_state.has_method("set_var"):
				_apply_var_seed(global_state, b)
			if state != null and state.has_method("set_var"):
				_apply_var_seed(state, b)
		elif _kind(b) == "inventory":
			# seed each named item counter to 0 so a rule/door can compare it
			var item := str(_params(b).get("item", "key"))
			if not item.strip_edges().is_empty():
				if global_state != null and global_state.has_method("set_var"):
					global_state.set_var("inv_%s" % item, 0)
				if state != null and state.has_method("set_var"):
					state.set_var("inv_%s" % item, 0)
		else:
			# feature modules may need their own pre-reset seeding
			_registry_seed(_kind(b), b, global_state, {"is_3d": _3d})
			if global_state != state:
				_registry_seed(_kind(b), b, state, {"is_3d": _3d})

	var entities := {}   # brick_id -> node
	var player: Node = null
	var first_spawn: Node = null
	var order := _order_of(g, bricks)

	# Blueprint templates are instantiated by the blueprint module itself, so a
	# template member must NOT also be built standalone (it would appear twice:
	# once loose on the root and once per instance).
	var _bp_members := {}
	var _bp_mod = load("res://src/features/blueprint.gd")
	if _bp_mod != null and _bp_mod.has_method("template_member_ids"):
		for _m in _bp_mod.template_member_ids(g):
			_bp_members[str(_m)] = true

	# --- pass 1: universal bricks -------------------------------------------
	for b in order:
		if not b is Dictionary:
			continue
		var kind := _kind(b)
		var bid := _id(b)
		if _bp_members.has(bid):
			continue
		# Feature modules get first refusal on every brick (the decoupling
		# point: new brick kinds never require editing this match).
		if _registry_build(kind, b, root, {
			"compiler": self, "root": root, "entities": entities,
			"player": player, "is_3d": _3d, "graph": g, "controls": _controls,
		}):
			continue
		match kind:
			"spawn":
				var node = _build_spawn(b, root)
				if node != null:
					if not bid.is_empty():
						entities[bid] = node
					if first_spawn == null:
						first_spawn = node
					if player == null and str(_params(b).get("model", "player")) == "player":
						player = node
						# capture the player's control bindings for movement
						_controls = _params(b)
			"move":
				var src = _resolve_source_entity(b, entities)
				if src == null:
					src = player
				if src != null:
					_attach_movement(src, b)
			"collide":
				_build_collide(b, root, g)
			"score":
				_build_score(b, state, global_state)
			"rule":
				_build_rule(b, root)
			"winlose":
				_build_winlose(b, state, global_state)
			"enemy_patrol", "hazard", "checkpoint", "moving_platform":
				pass   # genre bricks: built in pass 2, once the player exists
			"level", "camera", "animation", "particles":
				pass   # handled in pass 2 (needs the player / the root ground)
			# These are all built in pass 2. Without this exemption pass 1's
			# wildcard fired a placeholder FIRST, so the brick silently did
			# nothing even with perfectly good default params. Found by audit.
			"sound", "health", "variable", "platform", "background", "sky", "door", "entry", "inventory", "timer", "follow", "destroy":
				pass
			_:
				# unknown/placeholder brick: keep the graph visible
				var ph = _placeholder_for(b, root)
				if ph != null and not bid.is_empty():
					entities[bid] = ph

	# a graph with no explicit "player" model still gets a controllable actor
	if player == null and first_spawn != null:
		player = first_spawn
	if player != null:
		player.add_to_group("player")

	# --- pass 2: platformer genre bricks (real, playable) --------------------
	for b in order:
		if not b is Dictionary:
			continue
		if _bp_members.has(_id(b)):
			continue
		# Feature modules get first refusal here too (pass 2 is where most
		# gameplay bricks build, once the player exists).
		if _registry_build(_kind(b), b, root, {
			"compiler": self, "root": root, "entities": entities,
			"player": player, "is_3d": _3d, "graph": g, "controls": _controls,
		}):
			continue
		match _kind(b):
			"enemy_patrol":
				_build_enemy(b, root)
			"hazard":
				_build_hazard(b, root)
			"checkpoint":
				_build_checkpoint(b, root)
			"moving_platform":
				_build_moving_platform(b, root)
			"camera":
				# remember the camera settings; applied in _finalize (needs player)
				_camera_cfg = _params(b)
				_has_camera_brick = true
			"animation":
				# attach a spin/bob/pulse to the entity feeding this brick
				var src = _resolve_source_entity(b, entities)
				if src == null:
					src = player
				if src != null:
					_attach_animation(src, b)
			"particles":
				# a standalone emitter: attach a looping particle field to its entity
				var src = _resolve_source_entity(b, entities)
				if src != null:
					_attach_particle_field(src, b)
			"health":
				# configure the global max health from the brick
				if global_state != null and global_state.has_method("set_max_health"):
					global_state.call("set_max_health", int(_num(_params(b), "max", 3.0)))
			"platform":
				_build_platform(b, root)
			"level":
				_build_level(b, root)
			"background":
				_build_background(b, root)
			"sky":
				_build_sky(b, root)
			"entry":
				_build_entry(b, root)
			"door":
				_build_door(b, root)
			# These four were exempted from the pass-1 placeholder on the
			# assumption that pass 2 built them. It did not, so each compiled to
			# exactly nothing — no node, no error, no behaviour. Found by the
			# footprint sweep, which is now the lock that keeps them honest.
			"timer":
				_build_timer(b, root)
			"follow":
				_build_follow(b, entities, player)
			"destroy":
				_build_destroy(b, entities)
			"sound":
				_build_sound(b, root)
			"inventory":
				_build_inventory(b, state, global_state)

	_finalize(root, state)
	# --- Wave 3: build extra levels (if any) as hidden siblings --------------
	_build_extra_levels(g, root)
	compiled.emit(root)
	if not issues.is_empty():
		compile_failed.emit(issues)
	return root

# ---------------------------------------------------------------------------
# Spawn — creates the player/enemy/item entity the game shows.
# ---------------------------------------------------------------------------
func _build_spawn(b: Dictionary, root: Node) -> Node:
	var p := _params(b)
	var model := str(p.get("model", "player"))
	if model.strip_edges().is_empty():
		model = "player"
	var node: Node
	if _3d:
		node = _make_3d_entity(model, p)
	else:
		node = _make_2d_entity(model, p)
	if node == null:
		return null
	var nice := model.capitalize().replace(" ", "")
	if nice.is_empty():
		nice = "Entity"
	node.name = nice
	if model == "player":
		node.add_to_group("player")
	root.add_child(node)
	return node

func _make_3d_entity(model: String, p: Dictionary) -> Node:
	var body := CharacterBody3D.new()
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	match model:
		"player":
			var capsule := CapsuleMesh.new()
			capsule.radius = 0.4
			capsule.height = 1.8
			mesh.mesh = capsule
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color("#4fc3f7")
			# without a roughness the default material is a plastic-looking 0.5
			# everywhere; a matte body reads as a character, a metal disc reads
			# as a coin, and the difference is what makes primitives look cheap
			mat.roughness = 0.45
			mesh.material_override = mat
		"enemy":
			var sphere := SphereMesh.new()
			sphere.radius = 0.5
			sphere.height = 1.0
			mesh.mesh = sphere
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color("#ff5252")
			mat.roughness = 0.6
			mesh.material_override = mat
		"coin":
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.3
			cyl.bottom_radius = 0.3
			cyl.height = 0.1
			mesh.mesh = cyl
			# a cylinder lies flat by default, so a "coin" read as a puddle; stood
			# up on its edge it looks like a coin you collect
			mesh.rotation_degrees = Vector3(90, 0, 0)
			mesh.position = Vector3(0, 0.35, 0)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color("#ffd54f")
			mat.metallic = 0.75
			mat.roughness = 0.22
			mat.emission_enabled = true
			mat.emission = Color("#ffb300")
			mat.emission_energy_multiplier = 0.6
			mesh.material_override = mat
		_:
			var box := BoxMesh.new()
			box.size = Vector3(1, 1, 1)
			mesh.mesh = box
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color("#b0bec5")
			mat.roughness = 0.7
			var box_tex: Texture2D = Assets.texture("wood")
			if box_tex != null:
				mat.albedo_texture = box_tex
				mat.albedo_color = Color(1, 1, 1, 1)
				mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
			mesh.material_override = mat
	body.add_child(mesh)
	body.position = _vec3(p.get("position", null), Vector3(0, 1, 0))
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8
	col.shape = shape
	body.add_child(col)
	return body

func _make_2d_entity(model: String, p: Dictionary) -> Node:
	var body := CharacterBody2D.new()
	var sprite := Sprite2D.new()
	sprite.name = "Mesh"
	# Real art when the pack is present, a coloured square when it is not — the
	# fallback is what keeps a stripped build (and every smoke check) working.
	var tex: Texture2D = Assets.model_texture(model)
	if tex != null:
		sprite.texture = tex
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# 18-24px tiles at 1:1 are smaller than the 30px collision body, so scale
		# up by whole pixels and keep NEAREST or pixel art turns to mush
		var target := 34.0
		match model:
			"coin", "gem", "heart", "key":
				target = 22.0
		# whole-pixel scaling, minimum 2x: the ground is drawn at 2x and a 1x
		# 18px coin next to a 36px tile reads as a speck
		var sc: float = maxf(2.0, roundf(target / float(tex.get_height())))
		sprite.scale = Vector2(sc, sc)
	else:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		var col := Color("#4fc3f7")
		match model:
			"enemy": col = Color("#ff5252")
			"coin":  col = Color("#ffd54f")
			_:       col = Color("#b0bec5")
		img.fill(col)
		sprite.texture = ImageTexture.create_from_image(img)
	body.add_child(sprite)
	var col2 := CollisionShape2D.new()
	var shape := CapsuleShape2D.new()
	shape.radius = 14
	shape.height = 30
	col2.shape = shape
	body.add_child(col2)
	body.position = _spawn_pos_2d(p.get("position", null))
	return body

## A graph authored in 3D carries positions in metres (y up from the floor).
## Flipping such a graph to dimension "2d" used to drop the player at y=1 —
## one pixel below the top of a pixel world, forever floating. When every
## component is small enough to only be metres, convert with the engine-wide
## PX_PER_UNIT = 12 convention (same as the trigger/pathfind/perceive bricks)
## and hang y off the grass surface. Genuine 2D pixel positions (y in the
## hundreds) pass through untouched.
const _PX_PER_UNIT := 12.0
const _GROUND_SURFACE_Y := 264.0   # top row of the 2D grass skin
const _METRES_CUTOFF := 60.0       # above this, a coordinate is pixels

func _spawn_pos_2d(raw) -> Vector2:
	var pos := _vec2(raw, Vector2(0, 200))
	if absf(pos.x) <= _METRES_CUTOFF and absf(pos.y) <= _METRES_CUTOFF:
		return Vector2(pos.x * _PX_PER_UNIT, _GROUND_SURFACE_Y - maxf(pos.y, 0.0) * _PX_PER_UNIT)
	return pos

# ---------------------------------------------------------------------------
# Move — attaches the movement script (platformer WASD + jump) to the entity
# that flows into this brick. Params (speed/jump/gravity) come from the brick,
# so editing the brick changes the game on recompile.
# ---------------------------------------------------------------------------
func _attach_movement(entity: Node, b: Dictionary) -> void:
	if entity == null or not is_instance_valid(entity):
		return
	var p := _params(b)
	var script := GDScript.new()
	script.source_code = _movement_source(p, _3d)
	if script.reload() != OK:
		push_error("EasyForge: generated movement script failed to compile")
		return
	entity.set_script(script)

func _movement_source(p: Dictionary, is_3d: bool) -> String:
	# resolve the player's chosen keys (from the Spawn brick) -> Godot keycodes
	var kL := _keycode(_controls.get("key_left", "A"))
	var kR := _keycode(_controls.get("key_right", "D"))
	var kJ := _keycode(_controls.get("key_jump", "Space"))
	var kU := _keycode(_controls.get("key_up", "W"))
	var kD := _keycode(_controls.get("key_down", "S"))
	# Wave 8: also register the SAME keys as named input actions, so gamepad /
	# touch / rebinding can bind to a name instead of a raw keycode. The
	# generated script reads the actions, with the keycode as a fallback, so a
	# game built before this change keeps working unchanged.
	var _im = load("res://src/features/inputmap.gd")
	if _im != null:
		_im.register_controls(_controls)
	if is_3d:
		return (
			"extends CharacterBody3D\n"
			+ "# Generated by EasyForge from a 'Move' brick. Keys come from the\n"
			+ "# Spawn brick's Controls settings.\n"
			+ "const SPEED := %f\n" % _num(p, "speed", 8.0)
			+ "const JUMP := %f\n" % _num(p, "jump", 12.0)
			+ "const K_LEFT := %d\n" % kL
			+ "const K_RIGHT := %d\n" % kR
			+ "const K_JUMP := %d\n" % kJ
			+ "const K_UP := %d\n" % kU
			+ "const K_DOWN := %d\n" % kD
			+ "var gravity: float = ProjectSettings.get_setting(\"physics/3d/default_gravity\")\n"
			+ "func _physics_process(delta):\n"
			+ "	if GameState.game_over:\n"
			+ "		velocity = Vector3.ZERO\n"
			+ "		move_and_slide()\n"
			+ "		return\n"
			+ "	if not is_on_floor():\n"
			+ "		velocity.y -= gravity * delta\n"
			+ "	var ix := (1.0 if Input.is_key_pressed(K_RIGHT) else 0.0) - (1.0 if Input.is_key_pressed(K_LEFT) else 0.0)\n"
			+ "	var iz := (1.0 if Input.is_key_pressed(K_DOWN) else 0.0) - (1.0 if Input.is_key_pressed(K_UP) else 0.0)\n"
			+ "	var direction = Vector3(ix, 0, iz).normalized()\n"
			+ "	if direction:\n"
			+ "		velocity.x = direction.x * SPEED\n"
			+ "		velocity.z = direction.z * SPEED\n"
			+ "	else:\n"
			+ "		velocity.x = move_toward(velocity.x, 0, SPEED)\n"
			+ "		velocity.z = move_toward(velocity.z, 0, SPEED)\n"
			+ "	if Input.is_key_pressed(K_JUMP) and is_on_floor():\n"
			+ "		velocity.y = JUMP\n"
			+ "	move_and_slide()\n"
		)
	# 2D gravity is ~980 vs the brick's 3D-scale numbers, so scale speed/jump
	# up or the game is unplayably slow (and the jump is invisible).
	var sp2 := clampf(_num(p, "speed", 8.0) * 30.0, 60.0, 900.0)
	var jp2 := clampf(_num(p, "jump", 12.0) * 40.0, 100.0, 1200.0)
	# game-feel knobs come from the player's Spawn brick controls (_controls)
	var coyote := clampf(_num(_controls, "coyote_time", 0.1), 0.0, 0.3)
	var buffer := clampf(_num(_controls, "jump_buffer", 0.12), 0.0, 0.3)
	var jcut := clampf(_num(_controls, "jump_cut", 0.45), 0.1, 1.0)
	var fgrav := clampf(_num(_controls, "fall_gravity", 1.7), 1.0, 3.0)
	return (
		"extends CharacterBody2D\n"
		+ "# Generated by EasyForge from a 'Move' brick.\n"
		+ "const SPEED := %f\n" % sp2
		+ "const JUMP := %f\n" % jp2
		+ "const K_LEFT := %d\n" % kL
		+ "const K_RIGHT := %d\n" % kR
		+ "const K_JUMP := %d\n" % kJ
		# game-feel constants (coyote time, jump buffer, jump cut, fall gravity)
		+ "const COYOTE := %f\n" % coyote
		+ "const BUFFER := %f\n" % buffer
		+ "const JUMP_CUT := %f\n" % jcut
		+ "const FALL_GRAV := %f\n" % fgrav
		+ "var gravity: float = ProjectSettings.get_setting(\"physics/2d/default_gravity\")\n"
		+ "var _coyote := 0.0\n"      # time left to still jump after leaving ground
		+ "var _buffer := 0.0\n"      # time left on a buffered jump press
		+ "var _rising := false\n"    # true while an upward jump is in progress
		+ "var _jump_was := false\n"  # previous jump-key state (for just-pressed edge)
		+ "func _physics_process(delta):\n"
		+ "	if GameState.game_over:\n"
		+ "		velocity = Vector2.ZERO\n"
		+ "		move_and_slide()\n"
		+ "		return\n"
		# --- jump buffering: manual just-pressed edge -> remember the press
		+ "	var _jump_now = Input.is_key_pressed(K_JUMP)\n"
		+ "	if _jump_now and not _jump_was:\n"
		+ "		_buffer = BUFFER\n"
		+ "	else:\n"
		+ "		_buffer = maxf(_buffer - delta, 0.0)\n"
		+ "	_jump_was = _jump_now\n"
		# --- coyote time: refresh while grounded, else count down
		+ "	if is_on_floor():\n"
		+ "		_coyote = COYOTE\n"
		+ "	else:\n"
		+ "		_coyote = maxf(_coyote - delta, 0.0)\n"
		# --- asymmetric gravity: fall faster than rise
		+ "	if not is_on_floor():\n"
		+ "		var g = gravity * (FALL_GRAV if velocity.y > 0.0 else 1.0)\n"
		+ "		velocity.y += g * delta\n"
		+ "	var ix := (1.0 if Input.is_key_pressed(K_RIGHT) else 0.0) - (1.0 if Input.is_key_pressed(K_LEFT) else 0.0)\n"
		+ "	velocity.x = ix * SPEED\n"
		# --- variable jump height: cut the jump short when the key is released
		+ "	if _rising and not Input.is_key_pressed(K_JUMP):\n"
		+ "		velocity.y *= JUMP_CUT\n"
		+ "		_rising = false\n"
		# --- the jump itself, gated by coyote + buffer
		+ "	if _buffer > 0.0 and _coyote > 0.0:\n"
		+ "		velocity.y = -JUMP\n"
		+ "		_buffer = 0.0\n"
		+ "		_coyote = 0.0\n"
		+ "		_rising = true\n"
		+ "	if is_on_floor():\n"
		+ "		_rising = false\n"
		+ "	move_and_slide()\n"
	)

## Map a key-name choice ("A", "Space", "Left", ...) to a Godot KEY_* int.
func _keycode(name) -> int:
	var n := str(name)
	match n:
		"A": return KEY_A
		"B": return KEY_B
		"D": return KEY_D
		"J": return KEY_J
		"K": return KEY_K
		"L": return KEY_L
		"S": return KEY_S
		"W": return KEY_W
		"Space": return KEY_SPACE
		"Left": return KEY_LEFT
		"Right": return KEY_RIGHT
		"Up": return KEY_UP
		"Down": return KEY_DOWN
		"Enter": return KEY_ENTER
		"Shift": return KEY_SHIFT
		"E": return KEY_E
		"F": return KEY_F
	return KEY_A

# ---------------------------------------------------------------------------
# Collide — spawns a RING of collectibles (not just one) and wires
# "on touch" to whatever this brick connects to (score, winlose...).
# ---------------------------------------------------------------------------
func _build_collide(b: Dictionary, root: Node, graph) -> void:
	var p := _params(b)
	var target_name := str(p.get("with", "coin"))
	if target_name.strip_edges().is_empty():
		target_name = "coin"
	var count := int(clampf(_num(p, "count", 6.0), 1.0, 12.0))
	var targets := _outgoing_targets(b, graph)
	# capture a Particles brick's config for the collect-burst (if any)
	_collide_particles = {}
	for t in targets:
		if _kind(t) == "particles":
			_collide_particles = _params(t)
			break
	var conn_script := GDScript.new()
	conn_script.source_code = _collector_source(targets)
	var script_ok := conn_script.reload() == OK

	for i in count:
		var area = _make_coin(target_name, i)
		if _3d:
			# ring around the level at a height the player can walk into
			var radius := 5.5 + float(i % 2) * 1.5
			var ang := TAU * float(i) / float(count)
			area.position = Vector3(cos(ang) * radius, 1.2, sin(ang) * radius)
		else:
			area.position = Vector2(60.0 + float(i) * 90.0, 270.0)
		root.add_child(area)
		if script_ok:
			area.set_script(conn_script)

func _make_coin(target_name: String, i: int) -> Node:
	var label := target_name.capitalize()
	if i > 0:
		label += str(i + 1)
	if _3d:
		var area := Area3D.new()
		area.name = label
		var mesh := MeshInstance3D.new()
		mesh.name = "Mesh"
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.3
		cyl.bottom_radius = 0.3
		cyl.height = 0.1
		mesh.mesh = cyl
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("#ffd54f")
		mat.emission_enabled = true
		mat.emission = Color("#ffb300")
		mesh.material_override = mat
		area.add_child(mesh)
		var col := CollisionShape3D.new()
		var shp := SphereShape3D.new()
		shp.radius = 0.5
		col.shape = shp
		area.add_child(col)
		return area
	var area2 := Area2D.new()
	area2.name = label
	var sprite := Sprite2D.new()
	sprite.name = "Mesh"
	var img := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color("#ffd54f"))
	sprite.texture = ImageTexture.create_from_image(img)
	area2.add_child(sprite)
	var col2 := CollisionShape2D.new()
	var shp2 := CircleShape2D.new()
	shp2.radius = 12
	col2.shape = shp2
	area2.add_child(col2)
	return area2

func _collector_source(targets: Array) -> String:
	var body_lines: Array[String] = []
	for t in targets:
		if not t is Dictionary:
			continue
		var p := _params(t)
		match _kind(t):
			"score":
				body_lines.append("		GameState.add_score(%d)" % int(_num(p, "amount", 1.0)))
			"winlose":
				body_lines.append("		GameState.check_win()")
			"sound":
				var kind := str(p.get("kind", "coin"))
				var vol := _num(p, "volume", 0.7)
				body_lines.append("		GameState.play_sound(\"%s\", %f)" % [kind, vol])
			"health":
				body_lines.append("		GameState.damage(%d)" % int(_num(p, "damage", 1.0)))
			"variable":
				var vn := str(p.get("name", "value"))
				var vop := str(p.get("op", "add"))
				if vop == "set":
					body_lines.append("		GameState.set_var(\"%s\", %f)" % [vn, _num(p, "value", 0.0)])
				elif vop == "toggle":
					body_lines.append("		GameState.toggle_var(\"%s\")" % vn)
				else:
					body_lines.append("		GameState.add_var(\"%s\", %d)" % [vn, int(_num(p, "amount", 1.0))])
				# a variable touch also marks "collided" so a collided-rule fires
				body_lines.append("		GameState.set_var(\"__collided\", true)")
			"inventory":
				var iitem := str(p.get("item", "key"))
				var iop := str(p.get("op", "add"))
				var iamt := int(_num(p, "amount", 1.0))
				if iop == "remove":
					body_lines.append("		GameState.add_var(\"inv_%s\", -%d)" % [iitem, iamt])
				else:
					body_lines.append("		GameState.add_var(\"inv_%s\", %d)" % [iitem, iamt])
				body_lines.append("		GameState.set_var(\"__collided\", true)")
	if body_lines.is_empty():
		body_lines.append("		pass # nothing connected yet")
	return _collector_plain("\n".join(body_lines), _collide_particles)

## particles config for the collector burst (effect/amount/color), captured
## from a Particles brick connected to the collide being built.
var _collide_particles: Dictionary = {}

func _collector_plain(body: String, particles: Dictionary = {}) -> String:
	# This script is attached to the Area node itself (3D: Area3D, 2D: Area2D).
	# We connect the signal dynamically by name so the script can extend Node
	# (an Area2D and Area3D cannot share one base class).
	var burst_line := ""
	if not particles.is_empty():
		var effect := str(particles.get("effect", "sparkle"))
		var amount := int(_num(particles, "amount", 16.0))
		var colname := str(particles.get("color", "gold"))
		# The script extends Node (one collector serves Area2D and Area3D), so a
		# bare `global_position` does not parse and the whole coin-collect script
		# silently failed to compile whenever a Particles brick was wired in.
		# `call()` is on Object, and this node really is a Node2D/3D at runtime.
		burst_line = "		GameState.burst(%d, \"%s\", \"%s\", call(\"get_global_position\"))\n" % [amount, effect, colname]
	return (
		"extends Node\n"
		+ "# Generated by EasyForge: coin collector wired to the graph.\n"
		+ "var _touched := false\n"
		+ "func _ready():\n"
		+ "\tif self.has_signal(\"body_entered\"):\n"
		+ "\t\tself.connect(\"body_entered\", _on_body_entered)\n"
		+ "func _process(delta):\n"
		+ "\tvar m = get_node_or_null(\"Mesh\")\n"
		+ "\tif m is Node3D:\n"
		+ "\t\t(m as Node3D).rotate_y(2.0 * delta)\n"
		+ "func _on_body_entered(body):\n"
		+ "\tif _touched:\n"
		+ "\t\treturn\n"
		+ "\tif body == null:\n"
		+ "\t\treturn\n"
		+ "\tif body.name == \"Player\" or (body is Node and body.is_in_group(\"player\")):\n"
		+ "		_touched = true\n"
		+ body + "\n"
		+ burst_line
		+ "		queue_free()\n"
	)

# ---------------------------------------------------------------------------
# Score / WinLose — configure the global state script's rules.
# ---------------------------------------------------------------------------
func _build_score(b: Dictionary, state, global_state) -> void:
	var p := _params(b)
	if str(p.get("op", "add")) == "add":
		var variable := str(p.get("variable", "score"))
		var amount := int(_num(p, "amount", 1.0))
		if state != null and state.has_method("register_score_source"):
			state.register_score_source(variable, amount)
		if global_state != null and global_state.has_method("register_score_source"):
			global_state.register_score_source(variable, amount)

func _build_winlose(b: Dictionary, state, global_state) -> void:
	var p := _params(b)
	var condition := str(p.get("condition", "score_reaches"))
	var value := int(_num(p, "value", 10.0))
	if state != null and state.has_method("set_win_condition"):
		state.set_win_condition(condition, value)
	if global_state != null and global_state.has_method("set_win_condition"):
		global_state.set_win_condition(condition, value)

# ---------------------------------------------------------------------------
# Wave 1 — Variable brick. Registers the named value on GameState and, when
# this brick feeds a Collide/Score event, mutates it (add/set/toggle). The
# variable value is also readable by a Rule brick's condition, so the two
# compose: collide -> variable(+1) -> rule(if coins>=3 win).
# ---------------------------------------------------------------------------
func _build_variable(b: Dictionary) -> void:
	var p := _params(b)
	var name := str(p.get("name", "value"))
	if name.strip_edges().is_empty():
		name = "value"
	var is_bool := str(p.get("type", "number")) == "bool"
	var op := str(p.get("op", "add"))
	var global_state = _global_state()
	if global_state == null:
		return
	# seed an initial value so a rule comparing it before any event is sane
	if is_bool:
		global_state.set_var(name, false)
	else:
		global_state.set_var(name, 0.0)
	_register_var_brick(b)

## Seed a variable's initial value into a specific state object (used to mirror
## the seed onto the per-root state as well as the autoload).
func _apply_var_seed(state, b: Dictionary) -> void:
	if state == null:
		return
	var p := _params(b)
	var name := str(p.get("name", "value"))
	if name.strip_edges().is_empty():
		name = "value"
	var is_bool := str(p.get("type", "number")) == "bool"
	if is_bool:
		state.set_var(name, false)
	else:
		state.set_var(name, 0.0)

# ---------------------------------------------------------------------------
# Wave 3 — Multi-level. Extra levels from graph.levels are compiled into hidden
# sibling containers under the root. A LevelManager node (always added) swaps
# the active level when a Door fires: it hides the current level container,
# shows the target, and moves the player to the target level's entry marker.
# This keeps the deterministic single-scene compiler intact (no change_scene,
# no separate .tscn files) while giving real multi-level games.
# ---------------------------------------------------------------------------
func _build_extra_levels(g, root: Node) -> void:
	var extra: Array = _prop(g, "levels", [])
	if not (extra is Array) or extra.is_empty():
		return
	# tag level 1's live nodes so the manager can hide/show them as a group.
	# Use a CanvasItem-derived container so .visible works in both 2D and 3D.
	var lvl1: Node = Node3D.new() if _3d else Node2D.new()
	lvl1.name = "Level1"
	# move everything built so far (except GameState + HUD) into Level1
	var keep := {}
	for child in root.get_children():
		var n := str(child.name)
		if n == "HUD" or child.has_method("add_score"):
			keep[n] = child
	for child in root.get_children():
		if not keep.has(str(child.name)):
			child.reparent(lvl1)
	root.add_child(lvl1)
	root.move_child(lvl1, 0)
	# compile each extra level into its own hidden container
	for i in extra.size():
		if not (extra[i] is Dictionary):
			continue
		var lvl: Node = Node3D.new() if _3d else Node2D.new()
		lvl.name = "Level%d" % (i + 2)
		lvl.visible = false
		var lvl_dict: Dictionary = extra[i]
		# ensure dimension/genre carry over
		if not lvl_dict.has("dimension"):
			lvl_dict["dimension"] = str(_prop(g, "dimension", "3d"))
		if not lvl_dict.has("genre"):
			lvl_dict["genre"] = str(_prop(g, "genre", "platformer"))
		_compile_level_into(lvl_dict, lvl)
		root.add_child(lvl)
	# the manager that swaps levels on a door hit
	var mgr := Node.new()
	mgr.name = "LevelManager"
	var ms := GDScript.new()
	ms.source_code = _level_manager_source()
	if ms.reload() == OK:
		mgr.set_script(ms)
	root.add_child(mgr)

## Compile a level's bricks into a container node (a sub-compile). Reuses the
## same brick builders but writes into `container` instead of a fresh root, and
## without its own GameState/HUD (those live once at the true root).
func _compile_level_into(level_dict: Dictionary, container: Node) -> void:
	var fresh = load("res://src/bricks/graph.gd").new()
	fresh.from_dict(level_dict)
	var save_3d := _3d
	_3d = not (str(level_dict.get("dimension", "3d")) == "2d")
	var bricks := _bricks_of(fresh)
	var order := _order_of(fresh, bricks)
	for b in order:
		if not b is Dictionary:
			continue
		match _kind(b):
			"spawn":
				var node = _build_spawn(b, container)
			"move":
				var src = _resolve_source_entity(b, {})
				if src == null:
					src = _first_in_group(container, "player")
				if src != null:
					_attach_movement(src, b)
			"enemy_patrol": _build_enemy(b, container)
			"hazard": _build_hazard(b, container)
			"checkpoint": _build_checkpoint(b, container)
			"moving_platform": _build_moving_platform(b, container)
			"platform": _build_platform(b, container)
			"background": _build_background(b, container)
			"sky": _build_sky(b, container)
			"entry": _build_entry(b, container)
			"door": _build_door(b, container)
			"rule": _build_rule(b, container)
			"collide": _build_collide(b, container, fresh)
	_3d = save_3d

func _first_in_group(container: Node, group: String) -> Node:
	for child in container.get_children():
		if child.is_in_group(group):
			return child
	return null

func _level_manager_source() -> String:
	# Watches __door_hit; when set, swaps to the target level and moves the
	# player to that level's matching Entry_ marker. Also adds a level-select
	# HUD (number keys 1-9 jump straight to a level) so a multi-level game is
	# navigable. Self-contained, no assets.
	return (
		"extends Node\n"
		+ "# Generated by EasyForge: multi-level manager (Door + level select).\n"
		+ "var _levels: Array = []\n"
		+ "func _ready():\n"
		+ "	var root = get_parent()\n"
		+ "	if root == null:\n"
		+ "		return\n"
		+ "	for child in root.get_children():\n"
		+ "		if str(child.name).begins_with(\"Level\"):\n"
		+ "			_levels.append(child.name)\n"
		+ "	_levels.sort()\n"
		+ "func _unhandled_input(event):\n"
		+ "	if not (event is InputEventKey) or not event.pressed or event.echo:\n"
		+ "		return\n"
		+ "	# number keys 1-9 jump to that level\n"
		+ "	var n = event.keycode - KEY_1\n"
		+ "	if n >= 0 and n < _levels.size():\n"
		+ "		_goto(_levels[n])\n"
		+ "func _process(_d):\n"
		+ "	if not GameState.get_var(\"__door_hit\", false):\n"
		+ "		return\n"
		+ "	GameState.set_var(\"__door_hit\", false)\n"
		+ "	var target = str(GameState.get_var(\"__door_target\", \"2\"))\n"
		+ "	var entry = str(GameState.get_var(\"__door_entry\", \"start\"))\n"
		+ "	_goto(\"Level\" + target, entry)\n"
		+ "func _goto(level_name: String, entry: String = \"start\") -> void:\n"
		+ "	var root = get_parent()\n"
		+ "	if root == null:\n"
		+ "		return\n"
		+ "	var want = root.get_node_or_null(level_name)\n"
		+ "	if want == null:\n"
		+ "		return\n"
		+ "	for child in root.get_children():\n"
		+ "		if str(child.name).begins_with(\"Level\"):\n"
		+ "			child.visible = (child == want)\n"
		+ "	var marker = want.get_node_or_null(\"Entry_\" + entry)\n"
		+ "	var players = get_tree().get_nodes_in_group(\"player\")\n"
		+ "	if marker != null and players.size() > 0:\n"
		+ "		var p = players[0]\n"
		+ "		if p is Node3D and marker is Node3D:\n"
		+ "			p.global_position = (marker as Node3D).global_position\n"
		+ "		elif p is Node2D and marker is Node2D:\n"
		+ "			p.global_position = (marker as Node2D).global_position\n"
	)


## Wire "what fires this variable's op" — a collide/event feeding this brick
## triggers the add/set/toggle. Connected targets are handled by the event
## side (collide's collector); here we just remember the brick for codegen
## summaries and for the event-target path in _collector_source.
var _var_bricks := {}

func _register_var_brick(b: Dictionary) -> void:
	var p := _params(b)
	_var_bricks[_id(b)] = {
		"name": str(p.get("name", "value")),
		"scope": str(p.get("scope", "game")),
		"op": str(p.get("op", "add")),
		"amount": _num(p, "amount", 1.0),
		"value": _num(p, "value", 0.0),
		"type": str(p.get("type", "number")),
	}

# ---------------------------------------------------------------------------
# Wave 1 — Rule brick: if <condition> then <actions>. Compiled to a tiny
# watcher node that runs every physics frame, evaluates the condition, and
# fires the action verbs (win/lose/add_var/set_var/toggle_var/hit_stop/
# time_scale/play_sound) on GameState. This is the structural enabler: one
# rule replaces a whole class of bespoke bricks.
# ---------------------------------------------------------------------------
func _build_rule(b: Dictionary, root: Node) -> void:
	var p := _params(b)
	var node := Node.new()
	node.name = "Rule_%s" % _id(b)
	var script := GDScript.new()
	script.source_code = _rule_source(p)
	if script.reload() == OK:
		node.set_script(script)
	root.add_child(node)

func _rule_source(p: Dictionary) -> String:
	var source := str(p.get("cond_source", "variable"))
	var cond_op := str(p.get("cond_op", ">="))
	var cond_val := _num(p, "cond_value", 0.0)
	var cond_var := str(p.get("cond_var", "value"))
	if cond_var.strip_edges().is_empty():
		cond_var = "value"
	# build the boolean condition expression
	var cond_expr := "false"
	match source:
		"key":
			var kc := _keycode(str(p.get("cond_key", "Space")))
			cond_expr = "Input.is_key_pressed(%d)" % kc
		"collided":
			cond_expr = "GameState.get_var(\"__collided\", false)"
		"timer":
			cond_expr = "GameState.get_var(\"__time\", 0.0) %s %f" % [cond_op, cond_val]
		_:  # variable
			cond_expr = "GameState.get_var(\"%s\", 0.0) %s %f" % [cond_var, cond_op, cond_val]
	# expand the comma-separated action verbs into GameState calls
	var actions := str(p.get("actions", "win"))
	var body_lines: Array[String] = []
	for raw in actions.split(","):
		var verb := raw.strip_edges().to_lower()
		if verb.is_empty():
			continue
		match verb:
			"win":
				body_lines.append("GameState.check_win()")
			"lose":
				body_lines.append("GameState.lose()")
			"hit_stop":
				body_lines.append("GameState.hit_stop(0.08)")
			"slowmo":
				body_lines.append("GameState.set_time_scale(0.35)")
			"normal_time":
				body_lines.append("GameState.set_time_scale(1.0)")
			_:
				# add_var:coins / set_var:coins:5 / toggle_var:door / play_sound:coin
				if verb.begins_with("add_var:"):
					var vn := verb.substr(len("add_var:")).strip_edges()
					body_lines.append("GameState.add_var(\"%s\", 1)" % vn)
				elif verb.begins_with("set_var:"):
					var spec := verb.substr(len("set_var:")).strip_edges()
					var vn2 := spec
					var set_val := "0"
					var colon := spec.find(":")
					if colon != -1:
						vn2 = spec.substr(0, colon).strip_edges()
						set_val = spec.substr(colon + 1).strip_edges()
					body_lines.append("GameState.set_var(\"%s\", %s)" % [vn2, set_val])
				elif verb.begins_with("toggle_var:"):
					var tn := verb.substr(len("toggle_var:")).strip_edges()
					body_lines.append("GameState.toggle_var(\"%s\")" % tn)
				elif verb.begins_with("play_sound:"):
					var sn := verb.substr(len("play_sound:")).strip_edges()
					body_lines.append("GameState.play_sound(\"%s\")" % sn)
				elif verb.begins_with("wait:"):
					var secs := verb.substr(len("wait:")).strip_edges()
					body_lines.append("await get_tree().create_timer(%s).timeout" % secs)
	if body_lines.is_empty():
		body_lines.append("GameState.check_win()")
	var body := "\n".join(body_lines)
	# _fired latch so a key-press rule doesn't fire every frame
	return (
		"extends Node\n"
		+ "# Generated by EasyForge from a Rule brick (if/then).\n"
		+ "var _fired := false\n"
		+ "func _physics_process(_d):\n"
		+ "	if GameState.game_over:\n"
		+ "		return\n"
		+ "	if %s:\n" % cond_expr
		+ "		if _fired:\n"
		+ "			return\n"
		+ "		_fired = true\n"
		+ "		" + body.replace("\n", "\n		") + "\n"
	)

# ---------------------------------------------------------------------------
# Wave 2 — Platform brick: a solid surface with tunable physics. one_way uses
# Godot's one_way_collision; bounce/friction via a PhysicsMaterial. The ice /
# trampoline presets bake those values so a beginner gets a recognizable feel.
# ---------------------------------------------------------------------------
func _build_platform(b: Dictionary, root: Node) -> void:
	var p := _params(b)
	var preset := str(p.get("preset", "normal"))
	var bounce := _num(p, "bounce", 0.0)
	var friction := _num(p, "friction", 1.0)
	var one_way := bool(p.get("one_way", false))
	var width := clampf(_num(p, "width", 8.0), 1.0, 60.0)
	var height := clampf(_num(p, "height", 1.0), 0.25, 8.0)
	# presets override the sliders (they ARE the preset)
	match preset:
		"ice":
			friction = 0.05
			bounce = 0.0
		"trampoline":
			bounce = 0.9
			friction = 0.6
	var node: Node
	if _3d:
		var body := StaticBody3D.new()
		body.name = "Platform"
		var mesh := MeshInstance3D.new()
		mesh.name = "Mesh"
		var box := BoxMesh.new()
		box.size = Vector3(width, height, 4.0)
		mesh.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("#8d99ae") if preset == "normal" else (Color("#a5d8ff") if preset == "ice" else Color("#ff8fab"))
		mesh.material_override = mat
		body.add_child(mesh)
		var col := CollisionShape3D.new()
		var shp := BoxShape3D.new()
		shp.size = Vector3(width, height, 4.0)
		col.shape = shp
		if bounce > 0.0 or friction < 1.0:
			var pm := PhysicsMaterial.new()
			pm.bounce = bounce
			pm.friction = friction
			# 3D: PhysicsMaterial lives on the body via physics_material_override
			body.physics_material_override = pm
		body.add_child(col)
		body.position = Vector3(0.0, height * 0.5, 0.0)
		node = body
	else:
		var body2 := StaticBody2D.new()
		body2.name = "Platform"
		var sprite := Sprite2D.new()
		sprite.name = "Mesh"
		var img := Image.create(max(int(width * 12), 16), max(int(height * 12), 8), false, Image.FORMAT_RGBA8)
		img.fill(Color("#8d99ae") if preset == "normal" else (Color("#a5d8ff") if preset == "ice" else Color("#ff8fab")))
		sprite.texture = ImageTexture.create_from_image(img)
		body2.add_child(sprite)
		var col2 := CollisionShape2D.new()
		var shp2 := RectangleShape2D.new()
		shp2.size = Vector2(max(width * 12.0, 16.0), max(height * 12.0, 8.0))
		col2.shape = shp2
		col2.one_way_collision = one_way
		if one_way:
			col2.one_way_collision_margin = 2.0
		if bounce > 0.0 or friction < 1.0:
			var pm2 := PhysicsMaterial.new()
			pm2.bounce = bounce
			pm2.friction = friction
			body2.physics_material_override = pm2
		body2.add_child(col2)
		body2.position = Vector2(240.0, 260.0)
		node = body2
	root.add_child(node)

# ---------------------------------------------------------------------------
# Wave 2 — Background brick: parallax layers built from procedural gradient
# ColorRects on Parallax2D (2D). Cheapest visible-quality win: depth for free.
# ---------------------------------------------------------------------------
func _build_background(b: Dictionary, root: Node) -> void:
	var p := _params(b)
	var layers := int(clampf(_num(p, "layers", 2.0), 1.0, 3.0))
	var theme := str(p.get("theme", "dusk"))
	var palette := _theme_palette(theme)
	if _3d:
		# 3D: a large gradient sky-plane behind the play area
		for i in layers:
			var scale := 0.2 + float(i) * 0.25
			var plane := MeshInstance3D.new()
			plane.name = "Bg%d" % i
			var q := QuadMesh.new()
			q.size = Vector2(120.0, 60.0)
			plane.mesh = q
			var mat := StandardMaterial3D.new()
			var c: Color = palette[i % palette.size()]
			mat.albedo_color = Color(c.r, c.g, c.b, 0.55)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			plane.material_override = mat
			plane.position = Vector3(0.0, 20.0, -30.0 - float(i) * 12.0)
			root.add_child(plane)
		return
	# 2D: Parallax2D stack with procedural gradient ColorRects
	for i in layers:
		var par := Parallax2D.new()
		par.name = "Bg%d" % i
		par.scroll_scale = Vector2(1.0 - (0.3 * float(i)), 1.0 - (0.3 * float(i)))   # far layers scroll slower
		# Parallax2D has no `motion_mirroring` and no `mirror` — those were
		# ParallaxLayer's names. Its own tiling control is `repeat_size`, and the
		# old line printed a script error on every 2D compile and aborted the loop,
		# so a Background brick with 3 layers actually built one.
		par.repeat_size = Vector2(0.0, 400.0)
		par.z_index = -10 - i
		var rect := ColorRect.new()
		var c2: Color = palette[i % palette.size()]
		rect.color = c2
		rect.custom_minimum_size = Vector2(2000.0, 700.0)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.position = Vector2(-400.0, -100.0)
		par.add_child(rect)
		root.add_child(par)

func _theme_palette(theme: String) -> Array:
	match theme:
		"forest": return [Color("#2d5016"), Color("#3e6b1f"), Color("#558b2f")]
		"night":  return [Color("#0d1b2a"), Color("#1b263b"), Color("#415a77")]
		"candy":  return [Color("#ffafcc"), Color("#ffc8dd"), Color("#bde0fe")]
		_:        return [Color("#ff8c42"), Color("#ffb627"), Color("#ffd97d")]  # dusk

# ---------------------------------------------------------------------------
# Wave 2 — Sky/Environment brick: one themed preset colors the whole scene.
# 2D = a CanvasModulate tint; 3D = a WorldEnvironment with ProceduralSky +
# fog. Makes a project stop looking like a bare default.
# ---------------------------------------------------------------------------
func _build_sky(b: Dictionary, root: Node) -> void:
	var p := _params(b)
	var preset := str(p.get("preset", "day"))
	var cfg := _sky_config(preset)
	if _3d:
		# replace the default environment with the themed one
		var old = root.get_node_or_null("WorldEnvironment")
		if old != null:
			root.remove_child(old)
			old.queue_free()
		var env := Environment.new()
		var sky := Sky.new()
		var psm := ProceduralSkyMaterial.new()
		psm.sky_top_color = cfg["top"]
		psm.sky_horizon_color = cfg["horizon"]
		psm.ground_bottom_color = cfg["ground"]
		psm.ground_horizon_color = cfg["horizon"]
		sky.sky_material = psm
		env.background_mode = Environment.BG_SKY
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = cfg["ambient"]
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		if cfg.get("fog", false):
			env.fog_enabled = true
			env.fog_light_color = cfg["horizon"]
			env.fog_density = 0.02
		var we := WorldEnvironment.new()
		we.name = "WorldEnvironment"
		we.environment = env
		root.add_child(we)
		# a matching sun so lighting matches the sky
		var light := DirectionalLight3D.new()
		light.name = "SunLight"
		light.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
		light.light_color = cfg["sun"]
		light.light_energy = cfg["sun_energy"]
		light.shadow_enabled = true
		root.add_child(light)
		return
	# 2D: a CanvasModulate tint over the whole scene
	var cm := CanvasModulate.new()
	cm.name = "SkyModulate"
	cm.color = cfg["tint"]
	root.add_child(cm)

func _sky_config(preset: String) -> Dictionary:
	match preset:
		"sunset":
			return {"top": Color("#3a1c71"), "horizon": Color("#ffaf7b"), "ground": Color("#d76d77"),
				"sun": Color("#ff9e57"), "sun_energy": 1.2, "ambient": 0.7, "tint": Color("#ff9e7a")}
		"night":
			return {"top": Color("#0b1026"), "horizon": Color("#1f2a52"), "ground": Color("#05070f"),
				"sun": Color("#9db4ff"), "sun_energy": 0.5, "ambient": 0.5, "tint": Color("#8fa0d8")}
		"foggy":
			return {"top": Color("#b0b7c3"), "horizon": Color("#cfd6df"), "ground": Color("#9aa2ad"),
				"sun": Color("#e8ecf1"), "sun_energy": 0.8, "ambient": 0.9, "fog": true, "tint": Color("#c8ced8")}
		"space":
			return {"top": Color("#000000"), "horizon": Color("#1a1a2e"), "ground": Color("#000000"),
				"sun": Color("#e0e0ff"), "sun_energy": 0.6, "ambient": 0.6, "tint": Color("#b0b0e0")}
		_:  # day
			return {"top": Color("#4a90d9"), "horizon": Color("#a8d8f0"), "ground": Color("#6b8e5a"),
				"sun": Color("#fff4e0"), "sun_energy": 1.1, "ambient": 0.55, "tint": Color("#ffffff")}

# ---------------------------------------------------------------------------
# Wave 3 — Entry Point brick: a named marker the player can be sent to when a
# level starts or a door is used. In the single-level default it just records
# the name (the level manager reads markers by name).
# ---------------------------------------------------------------------------
func _build_entry(b: Dictionary, root: Node) -> void:
	var p := _params(b)
	var marker := str(p.get("marker", "start"))
	if marker.strip_edges().is_empty():
		marker = "start"
	var node: Node = Marker3D.new() if _3d else Marker2D.new()
	node.name = "Entry_%s" % marker
	if _3d:
		node.position = Vector3(0.0, 1.0, 0.0)
	else:
		node.position = Vector2(120.0, 260.0)
	root.add_child(node)

# ---------------------------------------------------------------------------
# Wave 3 — Door/Portal brick: a trigger that swaps the level. In the shipped
# single-level build it records the target so the level manager can honour it
# once multi-level lands; touching it also plays a transition sound + marks the
# collided var so a Rule can gate it.
# ---------------------------------------------------------------------------
func _build_door(b: Dictionary, root: Node) -> void:
	var p := _params(b)
	var target := str(p.get("target_level", "2"))
	var entry := str(p.get("target_entry", "start"))
	var needs := str(p.get("needs_var", ""))
	var node: Node
	if _3d:
		var area := Area3D.new()
		area.name = "Door"
		var mesh := MeshInstance3D.new()
		mesh.name = "Mesh"
		var box := BoxMesh.new()
		box.size = Vector3(1.6, 2.4, 0.3)
		mesh.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("#ffd54f")
		mat.emission_enabled = true
		mat.emission = Color("#ff8f00")
		mesh.material_override = mat
		area.add_child(mesh)
		var col := CollisionShape3D.new()
		var shp := BoxShape3D.new()
		shp.size = Vector3(1.6, 2.4, 1.0)
		col.shape = shp
		area.add_child(col)
		area.position = Vector3(0.0, 1.2, 0.0)
		node = area
	else:
		var area2 := Area2D.new()
		area2.name = "Door"
		var sprite := Sprite2D.new()
		sprite.name = "Mesh"
		var img := Image.create(32, 48, false, Image.FORMAT_RGBA8)
		img.fill(Color("#ffd54f"))
		sprite.texture = ImageTexture.create_from_image(img)
		area2.add_child(sprite)
		var col2 := CollisionShape2D.new()
		var shp2 := RectangleShape2D.new()
		shp2.size = Vector2(32, 48)
		col2.shape = shp2
		area2.add_child(col2)
		area2.position = Vector2(700.0, 250.0)
		node = area2
	var script := GDScript.new()
	script.source_code = _door_source(target, entry, needs)
	if script.reload() == OK:
		node.set_script(script)
	root.add_child(node)

func _door_source(target: String, entry: String, needs: String) -> String:
	var gate := ""
	if not needs.strip_edges().is_empty():
		gate = "\tif not GameState.get_var(\"%s\", false):\n\t\treturn\n" % needs
	return (
		"extends %s\n" % ("Area3D" if _3d else "Area2D")
		+ "# Generated by EasyForge from a Door brick (target level %s).\n" % target
		+ "func _ready():\n"
		+ "\tif not body_entered.is_connected(_on_body_entered):\n"
		+ "\t\tbody_entered.connect(_on_body_entered)\n"
		+ "func _on_body_entered(body):\n"
		+ "\tif body == null:\n"
		+ "\t\treturn\n"
		+ "\tif not (body.name == \"Player\" or (body is Node and body.is_in_group(\"player\"))):\n"
		+ "\t\treturn\n"
		+ gate
		+ "\tGameState.play_sound(\"win\", 0.6)\n"
		+ "\tGameState.set_var(\"__door_target\", \"%s\")\n" % target
		+ "\tGameState.set_var(\"__door_entry\", \"%s\")\n" % entry
		+ "\tGameState.set_var(\"__door_hit\", true)\n"
	)

# ---------------------------------------------------------------------------
# Wave 4 — Level brick: a beginner-friendly pattern string paints a real tile
# level. '#' = solid ground, '.' = empty, '^' = spike hazard, '-' = one-way
# platform. Rows separated by ';'. This is the paint-canvas experience without
# a full editor: the compiler turns the string into real collision geometry.
# ---------------------------------------------------------------------------
func _build_level(b: Dictionary, root: Node) -> void:
	var p := _params(b)
	var pattern := str(p.get("pattern", ""))
	if pattern.strip_edges().is_empty():
		# No pattern means the user has not drawn one yet. Do NOT fall through
		# to the placeholder (a bare "level" Label that does nothing and quietly
		# misleads them) — build a plain flat floor so the brick visibly works.
		var flat: Node = _make_ground_3d() if _3d else _make_ground_2d()
		if flat != null and root.get_node_or_null("Ground") == null:
			root.add_child(flat)
		return
	var tile := clampf(_num(p, "tile", 32.0), 8.0, 96.0)
	var theme := str(p.get("theme", "grass"))
	var col := Color("#4caf50") if theme == "grass" else (Color("#9e9e9e") if theme == "stone" else Color("#ff8fab"))
	var rows := pattern.split(";")
	# this Level brick IS the floor — suppress the default flat ground
	_has_tile_ground = true
	var default_ground = root.get_node_or_null("Ground")
	if default_ground != null:
		root.remove_child(default_ground)
		default_ground.queue_free()
	var row_i := 0
	for row in rows:
		var line := str(row)
		var col_i := 0
		# Godot 4: iterate a String by index (for ch in line is not per-char)
		while col_i < line.length():
			var ch := line[col_i]
			var x := float(col_i) * tile + tile * 0.5
			# top row = highest on screen; stack downward
			var y := float(row_i) * tile + tile * 0.5
			match ch:
				"#":
					root.add_child(_make_tile(Vector2(x, y), Vector2(tile, tile), col, false))
				"-":
					root.add_child(_make_tile(Vector2(x, y), Vector2(tile, tile * 0.4), col, true))
				"^":
					root.add_child(_make_spike(Vector2(x, y), tile))
			col_i += 1
		row_i += 1

## A solid (or one-way) tile. 2D only — a pattern level is inherently 2D.
func _make_tile(pos: Vector2, size: Vector2, col: Color, one_way: bool) -> Node:
	var body := StaticBody2D.new()
	body.name = "Tile"
	var sprite := Sprite2D.new()
	sprite.name = "Mesh"
	var img := Image.create(max(int(size.x), 4), max(int(size.y), 4), false, Image.FORMAT_RGBA8)
	img.fill(col)
	sprite.texture = ImageTexture.create_from_image(img)
	body.add_child(sprite)
	var colshape := CollisionShape2D.new()
	var shp := RectangleShape2D.new()
	shp.size = size
	colshape.shape = shp
	colshape.one_way_collision = one_way
	if one_way:
		colshape.one_way_collision_margin = 2.0
	body.add_child(colshape)
	body.position = pos
	return body

## A spike tile: a small red hazard area that costs a life on touch.
func _make_spike(pos: Vector2, tile: float) -> Node:
	var area := Area2D.new()
	area.name = "Spike"
	var sprite := Sprite2D.new()
	sprite.name = "Mesh"
	var img := Image.create(max(int(tile * 0.6), 6), max(int(tile * 0.6), 6), false, Image.FORMAT_RGBA8)
	img.fill(Color("#ff5252"))
	sprite.texture = ImageTexture.create_from_image(img)
	area.add_child(sprite)
	var colshape := CollisionShape2D.new()
	var shp := RectangleShape2D.new()
	shp.size = Vector2(tile * 0.6, tile * 0.6)
	colshape.shape = shp
	area.add_child(colshape)
	area.position = pos
	var script := GDScript.new()
	script.source_code = _hazard_source()
	if script.reload() == OK:
		area.set_script(script)
	return area

# ---------------------------------------------------------------------------
# Platformer genre bricks — compiled for real (playable behavior).
# ---------------------------------------------------------------------------

## Enemy Patrol — a red sphere that slides back and forth and ends the game
## on touch.
func _build_enemy(b: Dictionary, root: Node) -> void:
	var p := _params(b)
	var node: Node
	if _3d:
		var area := Area3D.new()
		area.name = "Enemy"
		var mesh := MeshInstance3D.new()
		mesh.name = "Mesh"
		var sphere := SphereMesh.new()
		sphere.radius = 0.6
		sphere.height = 1.2
		mesh.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("#ff5252")
		mat.emission_enabled = true
		mat.emission = Color("#7f1d1d")
		mesh.material_override = mat
		area.add_child(mesh)
		var col := CollisionShape3D.new()
		var shp := SphereShape3D.new()
		shp.radius = 0.7
		col.shape = shp
		area.add_child(col)
		area.position = _vec3(p.get("position", null), Vector3(-2.0, 1.0, -5.0))
		node = area
	else:
		var area := Area2D.new()
		area.name = "Enemy"
		var sprite := Sprite2D.new()
		sprite.name = "Mesh"
		var img := Image.create(28, 28, false, Image.FORMAT_RGBA8)
		img.fill(Color("#ff5252"))
		sprite.texture = ImageTexture.create_from_image(img)
		area.add_child(sprite)
		var col := CollisionShape2D.new()
		var shp := CircleShape2D.new()
		shp.radius = 16.0
		col.shape = shp
		area.add_child(col)
		area.position = _vec2(p.get("position", null), Vector2(300, 250))
		node = area
	var script := GDScript.new()
	script.source_code = _enemy_source(p)
	if script.reload() == OK:
		node.set_script(script)
	root.add_child(node)

func _enemy_source(p: Dictionary) -> String:
	var speed := clampf(_num(p, "speed", 1.5), 0.1, 20.0)
	var travel := clampf(_num(p, "range", 5.0), 0.5, 20.0)
	var base := "extends %s\n" % ("Area3D" if _3d else "Area2D")
	var vec := "Vector3(sin(_t) * RANGE, 0.0, 0.0)" if _3d else "Vector2(sin(_t) * RANGE, 0.0)"
	var zero := "Vector3.ZERO" if _3d else "Vector2.ZERO"
	return (
		base
		+ "# Generated by EasyForge from an 'Enemy Patrol' brick.\n"
		+ "const SPEED := %f\n" % speed
		+ "const RANGE := %f\n" % travel
		+ "var _t := 0.0\n"
		+ "var _origin := %s\n" % zero
		+ "func _ready():\n"
		+ "\t_origin = position\n"
		+ "\tif not body_entered.is_connected(_on_body_entered):\n"
		+ "\t\tbody_entered.connect(_on_body_entered)\n"
		+ "func _physics_process(delta):\n"
		+ "\t_t += delta * SPEED\n"
		+ "\tposition = _origin + %s\n" % vec
		+ "func _on_body_entered(body):\n"
		+ "\tif body == null:\n"
		+ "\t\treturn\n"
		+ "\tif body.name == \"Player\" or (body is Node and body.is_in_group(\"player\")):\n"
		+ "\t\tGameState.lose()\n"
	)

## Hazard — a red box on the ground; touching it costs a life and sends the
## player back to the last checkpoint (game over when lives run out).
func _build_hazard(b: Dictionary, root: Node) -> void:
	var p := _params(b)
	var node: Node
	if _3d:
		var area := Area3D.new()
		area.name = "Hazard"
		var mesh := MeshInstance3D.new()
		mesh.name = "Mesh"
		var box := BoxMesh.new()
		box.size = Vector3(2.0, 1.0, 2.0)
		mesh.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("#ff7043")
		mat.emission_enabled = true
		mat.emission = Color("#b71c1c")
		mesh.material_override = mat
		area.add_child(mesh)
		var col := CollisionShape3D.new()
		var shp := BoxShape3D.new()
		shp.size = Vector3(2.0, 1.0, 2.0)
		col.shape = shp
		area.add_child(col)
		area.position = _vec3(p.get("position", null), Vector3(4.0, 0.5, 3.0))
		node = area
	else:
		var area := Area2D.new()
		area.name = "Hazard"
		var sprite := Sprite2D.new()
		sprite.name = "Mesh"
		var img := Image.create(48, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color("#ff7043"))
		sprite.texture = ImageTexture.create_from_image(img)
		area.add_child(sprite)
		var col := CollisionShape2D.new()
		var shp := RectangleShape2D.new()
		shp.size = Vector2(48, 16)
		col.shape = shp
		area.add_child(col)
		area.position = _vec2(p.get("position", null), Vector2(450, 285))
		node = area
	var script := GDScript.new()
	script.source_code = _hazard_source()
	if script.reload() == OK:
		node.set_script(script)
	root.add_child(node)

func _hazard_source() -> String:
	return (
		"extends %s\n" % ("Area3D" if _3d else "Area2D")
		+ "# Generated by EasyForge from a 'Hazard' brick — touching it costs a life.\n"
		+ "var _cool := 0.0\n"
		+ "func _ready():\n"
		+ "	if not body_entered.is_connected(_on_body_entered):\n"
		+ "		body_entered.connect(_on_body_entered)\n"
		+ "func _physics_process(delta):\n"
		+ "	if _cool > 0.0:\n"
		+ "		_cool -= delta\n"
		+ "func _on_body_entered(body):\n"
		+ "	if body == null:\n"
		+ "		return\n"
		+ "	if _cool > 0.0:\n"
		+ "		return\n"
		+ "	if body.name == \"Player\" or (body is Node and body.is_in_group(\"player\")):\n"
		+ "		_cool = 1.0\n"
		+ "		GameState.set_var(\"__shake\", 1.0)\n"   # screen shake + hit-stop on impact
		+ "		GameState.hit_stop(0.08)\n"
		+ "		GameState.hit_hazard()\n"
	)

## Checkpoint — a green ring; touching it saves the respawn point so a
## hazard hit teleports the player back here instead of ending the run.
func _build_checkpoint(b: Dictionary, root: Node) -> void:
	var p := _params(b)
	var node: Node
	if _3d:
		var area := Area3D.new()
		area.name = "Checkpoint"
		var mesh := MeshInstance3D.new()
		mesh.name = "Mesh"
		var torus := TorusMesh.new()
		torus.inner_radius = 0.8
		torus.outer_radius = 1.1
		mesh.mesh = torus
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("#66bb6a")
		mat.emission_enabled = true
		mat.emission = Color("#1b5e20")
		mesh.material_override = mat
		area.add_child(mesh)
		var col := CollisionShape3D.new()
		var shp := SphereShape3D.new()
		shp.radius = 1.2
		col.shape = shp
		area.add_child(col)
		area.position = _vec3(p.get("position", null), Vector3(-6.0, 0.6, -5.0))
		node = area
	else:
		var area := Area2D.new()
		area.name = "Checkpoint"
		var sprite := Sprite2D.new()
		sprite.name = "Mesh"
		var img := Image.create(24, 24, false, Image.FORMAT_RGBA8)
		img.fill(Color("#66bb6a"))
		sprite.texture = ImageTexture.create_from_image(img)
		area.add_child(sprite)
		var col := CollisionShape2D.new()
		var shp := CircleShape2D.new()
		shp.radius = 14.0
		col.shape = shp
		area.add_child(col)
		area.position = _vec2(p.get("position", null), Vector2(150, 270))
		node = area
	var script := GDScript.new()
	script.source_code = _checkpoint_source()
	if script.reload() == OK:
		node.set_script(script)
	root.add_child(node)

func _checkpoint_source() -> String:
	var lift := "Vector3(0.0, 1.0, 0.0)" if _3d else "Vector2(0.0, -15.0)"
	return (
		"extends %s\n" % ("Area3D" if _3d else "Area2D")
		+ "# Generated by EasyForge from a 'Checkpoint' brick — respawn here.\n"
		+ "var _used := false\n"
		+ "func _ready():\n"
		+ "\tif not body_entered.is_connected(_on_body_entered):\n"
		+ "\t\tbody_entered.connect(_on_body_entered)\n"
		+ "func _on_body_entered(body):\n"
		+ "\tif _used:\n"
		+ "\t\treturn\n"
		+ "\tif body == null:\n"
		+ "\t\treturn\n"
		+ "\tif body.name == \"Player\" or (body is Node and body.is_in_group(\"player\")):\n"
		+ "\t\t_used = true\n"
		+ "\t\tGameState.set_respawn(global_position + %s, body)\n" % lift
		+ "\t\tqueue_free()\n"
	)

## Moving Platform — an AnimatableBody the player can ride; slides back and
## forth along X.
func _build_moving_platform(b: Dictionary, root: Node) -> void:
	var p := _params(b)
	var node: Node
	if _3d:
		var body := AnimatableBody3D.new()
		body.name = "MovingPlatform"
		var mesh := MeshInstance3D.new()
		mesh.name = "Mesh"
		var box := BoxMesh.new()
		box.size = Vector3(4.0, 0.4, 4.0)
		mesh.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("#90a4ae")
		mesh.material_override = mat
		body.add_child(mesh)
		var col := CollisionShape3D.new()
		var shp := BoxShape3D.new()
		shp.size = Vector3(4.0, 0.4, 4.0)
		col.shape = shp
		body.add_child(col)
		body.position = _vec3(p.get("position", null), Vector3(0.0, 1.5, 6.0))
		node = body
	else:
		var body := AnimatableBody2D.new()
		body.name = "MovingPlatform"
		var sprite := Sprite2D.new()
		sprite.name = "Mesh"
		var img := Image.create(96, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color("#90a4ae"))
		sprite.texture = ImageTexture.create_from_image(img)
		body.add_child(sprite)
		var col := CollisionShape2D.new()
		var shp := RectangleShape2D.new()
		shp.size = Vector2(96, 16)
		col.shape = shp
		body.add_child(col)
		body.position = _vec2(p.get("position", null), Vector2(250, 240))
		node = body
	var script := GDScript.new()
	script.source_code = _platform_source(p)
	if script.reload() == OK:
		node.set_script(script)
	root.add_child(node)

func _platform_source(p: Dictionary) -> String:
	var speed := clampf(_num(p, "speed", 2.0), 0.1, 20.0)
	# the brick's own param is "distance"; "range" is kept as a legacy alias so
	# older saved graphs still move the distance the user set
	var travel := clampf(_num(p, "distance", _num(p, "range", 5.0)), 0.5, 20.0)
	var axis := str(p.get("axis", "x")).to_lower()
	var vec := "Vector3(sin(_t) * RANGE, 0.0, 0.0)"
	if _3d:
		match axis:
			"y": vec = "Vector3(0.0, sin(_t) * RANGE, 0.0)"
			"z": vec = "Vector3(0.0, 0.0, sin(_t) * RANGE)"
	else:
		vec = "Vector2(sin(_t) * RANGE, 0.0)"
		if axis == "y":
			vec = "Vector2(0.0, sin(_t) * RANGE)"
	var zero := "Vector3.ZERO" if _3d else "Vector2.ZERO"
	return (
		"extends %s\n" % ("AnimatableBody3D" if _3d else "AnimatableBody2D")
		+ "# Generated by EasyForge from a 'Moving Platform' brick.\n"
		+ "const SPEED := %f\n" % speed
		+ "const RANGE := %f\n" % travel
		+ "var _t := 0.0\n"
		+ "var _origin := %s\n" % zero
		+ "func _ready():\n"
		+ "\t_origin = position\n"
		+ "\tsync_to_physics = true\n"
		+ "func _physics_process(delta):\n"
		+ "\t_t += delta * SPEED\n"
		+ "\tposition = _origin + %s\n" % vec
	)

# ---------------------------------------------------------------------------
# Timer / Follow / Destroy / Sound / Inventory — real builders for the five
# kinds that used to compile to nothing at all.
# ---------------------------------------------------------------------------
func _build_timer(b: Dictionary, root: Node) -> void:
	var p := _params(b)
	var t := Timer.new()
	var tname := str(p.get("name", "main")).strip_edges()
	if tname.is_empty():
		tname = "main"
	t.name = "Timer_" + tname
	var repeat := str(p.get("mode", "once")) == "repeat"
	t.wait_time = clampf(_num(p, "every", 3.0) if repeat else _num(p, "seconds", 20.0), 0.1, 600.0)
	t.one_shot = not repeat
	t.autostart = true
	var script := GDScript.new()
	script.source_code = _timer_source(p)
	if script.reload() == OK:
		t.set_script(script)
	root.add_child(t)

func _timer_source(p: Dictionary) -> String:
	# A comment-only body does not parse ("Expected indented block after function
	# declaration"), and on_end is a free choice in older projects, so the fallback
	# has to be a real statement — otherwise every Timer brick whose on_end was not
	# win/lose silently compiled to nothing at all.
	var action := "\tpass # on_end has no effect wired: the timer still fires\n"
	match str(p.get("on_end", "lose")):
		"win":
			action = "\tGameState.won = true\n\tGameState.game_over = true\n"
		"lose":
			action = "\tGameState.lose()\n"
	return (
		"extends Timer\n"
		+ "# Generated by EasyForge from a 'Timer' brick.\n"
		+ "func _ready() -> void:\n"
		+ "\tif not timeout.is_connected(_on_timeout):\n"
		+ "\t\ttimeout.connect(_on_timeout)\n"
		+ "func _on_timeout() -> void:\n"
		+ action
	)

## Follow runs as a CHILD of the thing that follows, so it never overwrites the
## movement script that entity already carries.
func _build_follow(b: Dictionary, entities: Dictionary, player) -> void:
	var src = _resolve_source_entity(b, entities)
	if src == null:
		src = player
	if src == null:
		return
	var holder := Node.new()
	holder.name = "Follow"
	var script := GDScript.new()
	script.source_code = _follow_source(_params(b))
	if script.reload() != OK:
		return
	holder.set_script(script)
	src.add_child(holder)
	if not _id(b).is_empty():
		entities[_id(b)] = src

func _follow_source(p: Dictionary) -> String:
	var speed := clampf(_num(p, "speed", 8.0), 0.1, 60.0)
	var target := str(p.get("target", "Player")).strip_edges()
	if target.is_empty():
		target = "Player"
	var vec := "Vector3" if _3d else "Vector2"
	var flat := "\tgap.y = 0.0" if _3d else ""
	return (
		"extends Node\n"
		+ "# Generated by EasyForge from a 'Follow' brick.\n"
		+ "const SPEED := %f\n" % speed
		+ "const TARGET_NAME := \"" + target + "\"\n"
		+ "var _target: Node = null\n"
		+ "func _ready() -> void:\n"
		+ "\t_target = get_tree().get_first_node_in_group(\"player\")\n"
		+ "\tif _target == null:\n"
		+ "\t\t_target = get_tree().root.find_child(TARGET_NAME, true, false)\n"
		+ "func _physics_process(delta: float) -> void:\n"
		+ "\tif _target == null or not (_target is Node3D or _target is Node2D):\n"
		+ "\t\treturn\n"
		+ "\tvar body := get_parent()\n"
		+ "\tvar gap: " + vec + " = _target.global_position - body.global_position\n"
		+ flat + "\n"
		+ "\tif gap.length() > 0.4:\n"
		+ "\t\tbody.global_position = body.global_position + gap.normalized() * SPEED * delta\n"
	)

## Destroy is a fuse on the entity feeding it: touch, a timed fuse, or leaving
## the screen. All three attach a small watcher instead of replacing the
## entity's own script.
func _build_destroy(b: Dictionary, entities: Dictionary) -> void:
	var src = _resolve_source_entity(b, entities)
	if src == null:
		return
	var watcher := Node.new()
	watcher.name = "DestroyWatcher"
	var script := GDScript.new()
	script.source_code = _destroy_source(_params(b))
	if script.reload() != OK:
		return
	watcher.set_script(script)
	src.add_child(watcher)

func _destroy_source(p: Dictionary) -> String:
	var mode := str(p.get("on", "touch"))
	var body := ""
	match mode:
		"timer":
			body = (
				"func _ready() -> void:\n"
				+ "\tget_tree().create_timer(1.0).timeout.connect(_gone)\n"
			)
		"leave_screen":
			if _3d:
				body = (
					"func _ready() -> void:\n"
					+ "\tvar n := VisibleOnScreenNotifier3D.new()\n"
					+ "\tget_parent().add_child(n)\n"
					+ "\tn.screen_exited.connect(_gone)\n"
				)
			else:
				body = (
					"func _ready() -> void:\n"
					+ "\tvar n := VisibleOnScreenNotifier2D.new()\n"
					+ "\tget_parent().add_child(n)\n"
					+ "\tn.screen_exited.connect(_gone)\n"
				)
		_:
			body = (
				"func _ready() -> void:\n"
				+ "\tvar body := get_parent()\n"
				+ "\tif body.has_signal(\"body_entered\"):\n"
				+ "\t\tbody.body_entered.connect(_on_touch)\n"
				+ "func _on_touch(other) -> void:\n"
				+ "\tif other == null:\n"
				+ "\t\treturn\n"
				+ "\tif other.is_in_group(\"player\"):\n"
				+ "\t\t_gone()\n"
			)
	return (
		"extends Node\n"
		+ "# Generated by EasyForge from a 'Destroy' brick.\n"
		+ body
		+ "func _gone() -> void:\n"
		+ "\tget_parent().queue_free()\n"
	)

## Sound plays the same synthesised voices GameState already uses, so this
## brick and the newer Audio brick stay consistent.
func _build_sound(b: Dictionary, root: Node) -> void:
	var p := _params(b)
	var player := AudioStreamPlayer.new()
	player.name = "Sound_" + str(p.get("kind", "coin"))
	var vol := clampf(_num(p, "volume", 0.7), 0.0, 1.0)
	var script := GDScript.new()
	script.source_code = _sound_source(p, vol)
	if script.reload() == OK:
		player.set_script(script)
	root.add_child(player)

func _sound_source(p: Dictionary, vol: float) -> String:
	var kind := str(p.get("kind", "coin"))
	return (
		"extends AudioStreamPlayer\n"
		+ "# Generated by EasyForge from a 'Sound' brick.\n"
		+ "const KIND := \"" + kind + "\"\n"
		+ "const LEVEL := %f\n" % (linear_db_offset(vol))
		+ "func _ready() -> void:\n"
		+ "\tvolume_db = LEVEL\n"
		+ "\tGameState.play_sound(KIND)\n"
	)

## A 0-1 volume knob mapped onto the player's dB range.
func linear_db_offset(vol: float) -> float:
	return -12.0 + clampf(vol, 0.0, 1.0) * 12.0

## Inventory keeps its counts in GameState vars, the same place Variable,
## Watch, HUD and Rule already read from.
func _build_inventory(b: Dictionary, state, global_state) -> void:
	var p := _params(b)
	var item := str(p.get("item", "key")).strip_edges()
	if item.is_empty():
		item = "key"
	var key := "inv_" + item
	for s in [state, global_state]:
		if s != null and s.has_method("set_var"):
			s.set_var(key, 0)

# ---------------------------------------------------------------------------
# Placeholder for un-compiled brick kinds (keeps the graph visible).
# ---------------------------------------------------------------------------
func _placeholder_for(b: Dictionary, root: Node) -> Node:
	var kind := _kind(b)
	var lbl = Label3D.new() if _3d else Label.new()
	lbl.text = "%s %s" % [BrickRegistry.kind_icon(kind), _title(b)]
	lbl.name = kind if not kind.is_empty() else "Brick"
	if _3d:
		lbl.position = Vector3(randf_range(-5, 5), 3, randf_range(-5, 5))
	root.add_child(lbl)
	return lbl

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _resolve_source_entity(b: Dictionary, entities: Dictionary) -> Node:
	# prefer the player; otherwise the first entity spawned
	for e in entities.values():
		if e != null and str(e.name) == "Player":
			return e
	for e in entities.values():
		if e != null:
			return e
	return null

func _outgoing_targets(b: Dictionary, graph) -> Array:
	var targets := []
	if graph == null or not graph.has_method("get_brick"):
		return targets
	for c in _conns(b):
		if not c is Dictionary:
			continue
		var tid := str(c.get("to_brick", ""))
		if tid.is_empty():
			continue
		var t = graph.get_brick(tid)
		if t is Dictionary and not t.is_empty():
			targets.append(t)
	return targets

func _global_state():
	# Prefer the autoload identifier "GameState" — the exact name generated
	# game scripts bind to at runtime. Engine.get_singleton("GameState") can
	# return a distinct object from that identifier in some launch contexts
	# (verified: they compared unequal in a standalone headless scene), so we
	# resolve through the identifier the generated code actually uses.
	var by_identifier = get_node_or_null("/root/GameState")
	if by_identifier != null:
		return by_identifier
	if Engine.has_singleton("GameState"):
		return Engine.get_singleton("GameState")
	return null

# ---------------------------------------------------------------------------
# Feature registry bridge. Feature modules (src/features/*.gd) register
# builders for their brick kinds; the compiler asks the registry first, so a
# new brick kind never requires editing the match statements above.
# ---------------------------------------------------------------------------
func _registry() -> Node:
	# Resolve the Features autoload by its /root node path, NOT via
	# Engine.has_singleton/get_singleton: in this project the singleton handle
	# and the autoload identifier are distinct objects (the same quirk already
	# fixed for GameState), and has_singleton() returns false here.
	var by_path = get_node_or_null("/root/Features")
	if by_path != null and by_path.has_method("registry"):
		return by_path.registry()
	if Engine.has_singleton("Features"):
		var f = Engine.get_singleton("Features")
		if f != null and f.has_method("registry"):
			return f.registry()
	return null

## Try a registered feature builder for `kind`. Returns true when one ran.
func _registry_build(kind: String, b: Dictionary, root: Node, ctx: Dictionary) -> bool:
	if kind.is_empty():
		return false
	var reg = _registry()
	if reg == null or not reg.has_method("build"):
		return false
	return bool(reg.build(kind, b, root, ctx))

## Try a registered seeder. Returns true when one ran.
func _registry_seed(kind: String, b: Dictionary, state, ctx: Dictionary) -> bool:
	if kind.is_empty() or state == null:
		return false
	var reg = _registry()
	if reg == null or not reg.has_method("seed"):
		return false
	return bool(reg.seed(kind, b, state, ctx))

func _finalize(root: Node, state) -> void:
	# ground so the player never falls forever (unless a Level brick drew one)
	if not _has_tile_ground and root.get_node_or_null("Ground") == null:
		if _3d:
			root.add_child(_make_ground_3d())
		else:
			root.add_child(_make_ground_2d())
	# lighting + environment — without these the 3D scene is a black void
	if _3d:
		root.add_child(_make_environment())
		root.add_child(_make_sun())
	elif root.get_node_or_null("Sky") == null:
		# 2D gets its mood from a gradient behind the action instead
		root.add_child(_make_sky_2d())
	# a camera so there is always a view — honour a Camera brick if present
	if root.get_node_or_null("GameCamera") == null:
		var mode := str(_camera_cfg.get("mode", "follow")) if _has_camera_brick else "follow"
		var dist := float(_camera_cfg.get("distance", 10.0)) if _has_camera_brick else 10.0
		var height := float(_camera_cfg.get("height", 6.0)) if _has_camera_brick else 6.0
		var smooth := bool(_camera_cfg.get("smooth", true)) if _has_camera_brick else true
		var shake := bool(_camera_cfg.get("shake", true)) if _has_camera_brick else true
		var shake_strength := float(_camera_cfg.get("shake_strength", 0.6)) if _has_camera_brick else 0.6
		if _3d:
			var cam := Camera3D.new()
			cam.name = "GameCamera"
			root.add_child(cam)
			if mode == "follow":
				_attach_follow_script(cam, dist, height, smooth, shake, shake_strength)
			elif mode == "orbit":
				_attach_orbit_script(cam, dist, height)
			else:  # fixed / cutscene — a static framed view
				cam.look_at_from_position(Vector3(0, height, dist), Vector3(0, 1, 0), Vector3.UP)
		else:
			var cam := Camera2D.new()
			cam.name = "GameCamera"
			# a 2D camera that is never made current leaves the view pinned to the
			# origin: the follow script ran, but nothing was watching. It can only
			# be made current once it is inside a tree, so add it first — calling
			# make_current() on the detached node printed
			# "Condition !enabled || !is_inside_tree() is true" on every 2D compile.
			root.add_child(cam)
			if cam.is_inside_tree():
				cam.make_current()
			if mode == "follow":
				_attach_follow_2d(cam, shake, shake_strength)
	# HUD (score + win/lose message that stays visible)
	var hud := _build_hud()
	hud.name = "HUD"
	root.add_child(hud)

## 3D follow camera — tracks the player (found by group at runtime).
func _attach_follow_script(cam: Camera3D, dist: float, height: float, smooth: bool, shake: bool = true, shake_strength: float = 0.6) -> void:
	# higher lerp = tighter follow (less lag); smooth still eases it a little
	var lerp_speed := 12.0 if smooth else 1000.0
	var s := GDScript.new()
	var shake_lines := ""
	if shake:
		# offset the camera by a decaying random impulse each frame after a hit
		# (Camera3D/Camera2D expose h_offset/v_offset, not a Vector3 offset).
		shake_lines = (
			"	var _sk = GameState.get_var(\"__shake\", 0.0)\n"
			+ "	if _sk > 0.0:\n"
			+ "		h_offset = randf_range(-1.0, 1.0) * _sk * %f\n" % shake_strength
			+ "		v_offset = randf_range(-1.0, 1.0) * _sk * %f\n" % shake_strength
			+ "		GameState.set_var(\"__shake\", _sk * 0.85)\n"
			+ "	else:\n"
			+ "		h_offset = 0.0\n"
			+ "		v_offset = 0.0\n"
		)
	s.source_code = (
		"extends Camera3D\n"
		+ "var _target: Node3D = null\n"
		+ "func _ready():\n"
		+ "	_target = get_tree().get_first_node_in_group(\"player\")\n"
		+ "func _physics_process(_d):\n"
		+ shake_lines
		+ "	if _target == null or not is_instance_valid(_target):\n"
		+ "		_target = get_tree().get_first_node_in_group(\"player\")\n"
		+ "	if _target == null:\n"
		+ "		return\n"
		+ "	var want = _target.global_position + Vector3(0, %f, %f)\n" % [height, dist]
		+ "	global_position = global_position.lerp(want, %f * _d)\n" % lerp_speed
		+ "	look_at(_target.global_position + Vector3(0, 1, 0), Vector3.UP)\n"
	)
	if s.reload() == OK:
		cam.set_script(s)

## 3D orbit camera — slowly circles the level centre.
func _attach_orbit_script(cam: Camera3D, dist: float, height: float) -> void:
	var s := GDScript.new()
	s.source_code = (
		"extends Camera3D\n"
		+ "var _t := 0.0\n"
		+ "func _physics_process(d):\n"
		+ "	_t += d * 0.3\n"
		+ "	var r = %f\n" % dist
		+ "	global_position = Vector3(cos(_t) * r, %f, sin(_t) * r)\n" % height
		+ "	look_at(Vector3(0, 1, 0), Vector3.UP)\n"
	)
	if s.reload() == OK:
		cam.set_script(s)

## 2D follow camera — centres on the player (found by group at runtime).
func _attach_follow_2d(cam: Camera2D, shake: bool = true, shake_strength: float = 0.6) -> void:
	var shake_lines := ""
	if shake:
		shake_lines = (
			"	var _sk = GameState.get_var(\"__shake\", 0.0)\n"
			+ "	if _sk > 0.0:\n"
			+ "		offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _sk * %f\n" % shake_strength
			+ "		GameState.set_var(\"__shake\", _sk * 0.85)\n"
			+ "	else:\n"
			+ "		offset = Vector2.ZERO\n"
		)
	var s := GDScript.new()
	s.source_code = (
		"extends Camera2D\n"
		+ "var _target: Node2D = null\n"
		+ "func _ready():\n"
		+ "	_target = get_tree().get_first_node_in_group(\"player\")\n"
		+ "func _physics_process(_d):\n"
		+ shake_lines
		+ "	if _target == null or not is_instance_valid(_target):\n"
		+ "		_target = get_tree().get_first_node_in_group(\"player\")\n"
		+ "	if _target != null:\n"
		+ "		global_position = _target.global_position\n"
	)
	if s.reload() == OK:
		cam.set_script(s)

## Animation brick — spin / bob / pulse an entity over time.
func _attach_animation(entity: Node, b: Dictionary) -> void:
	var p := _params(b)
	var motion := str(p.get("motion", "spin"))
	var speed := _num(p, "speed", 2.0)
	var body := ""
	match motion:
		"bob":
			body = (
				"	_base_y = position.y\n"
				+ "	_t += d * %f\n" % speed
				+ "	position.y = _base_y + sin(_t) * 0.5\n"
			)
		"pulse":
			body = (
				"	_t += d * %f\n" % speed
				+ "	var s = 1.0 + sin(_t) * 0.15\n"
				+ "	scale = Vector3(s, s, s)\n"
			)
		_:  # spin
			if _3d:
				body = "	rotate_y(%f * d)\n" % speed
			else:
				body = "	rotation += %f * d\n" % speed
	var decl := "var _t := 0.0\nvar _base_y := 0.0\n"
	var s := GDScript.new()
	s.source_code = (
		"extends Node3D\n" if _3d else "extends Node2D\n"
		+ "# Generated by EasyForge from an Animation brick.\n"
		+ decl
		+ "func _ready():\n"
		+ "	_base_y = position.y\n"
		+ "func _physics_process(d):\n"
		+ body
	)
	if s.reload() == OK:
		entity.set_script(s)

## Particles brick (standalone) — attach a looping sparkle field to an entity
## so it shimmers continuously (visual only, cheap: a few orbiting motes).
func _attach_particle_field(entity: Node, b: Dictionary) -> void:
	var p := _params(b)
	var effect := str(p.get("effect", "sparkle"))
	var amount := int(clampf(_num(p, "amount", 16.0), 4.0, 32.0))
	var colname := str(p.get("color", "gold"))
	var s := GDScript.new()
	# No `%%` written inside the generated source. The `%` substitution at the end
	# of this concatenation binds only to the LAST fragment, so a `%%` written on
	# an earlier line reached the generated script verbatim and failed to parse —
	# which meant every ambient Particles brick silently did nothing. (The old
	# `int(_t * 2.0) %% 1 == 0` guard was always true anyway.)
	s.source_code = (
		"extends Node3D\n" if _3d else "extends Node2D\n"
		+ "# Generated by EasyForge from a Particles brick (ambient field).\n"
		+ "var _t := 0.0\n"
		+ "func _physics_process(d):\n"
		+ "\t_t += d\n"
		+ "\tif randf() < 0.2:\n"
		+ "\t\tGameState.burst(2, \"%s\", \"%s\", global_position)\n" % [effect, colname]
	)
	if s.reload() == OK:
		entity.set_script(s)

func _make_ground_3d() -> Node:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var gmesh := MeshInstance3D.new()
	var gbox := BoxMesh.new()
	# wide enough that the fog, not the edge of the board, ends the view
	gbox.size = Vector3(400, 0.5, 400)
	gmesh.mesh = gbox
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color("#35642f")
	gmat.roughness = 0.92
	# NO Kenney tile here, deliberately: the pack's "grass" is a cross-section
	# (green top, dirt bottom, dark edge posts) and the wave-21 render probe
	# proved it stripes into neon checkerboard when tiled across a 400 m plane
	# seen from a player's height. A 2x2 procedural tile is the verified good
	# look: green ground, and a faint grid that gives the eye scale and motion
	# cues.
	var tiles := Image.create(2, 2, false, Image.FORMAT_RGB8)
	tiles.set_pixel(0, 0, Color("#ffffff"))
	tiles.set_pixel(1, 1, Color("#ffffff"))
	tiles.set_pixel(1, 0, Color("#e2ead9"))
	tiles.set_pixel(0, 1, Color("#e2ead9"))
	gmat.albedo_texture = ImageTexture.create_from_image(tiles)
	gmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	gmat.uv1_scale = Vector3(56, 56, 56)
	gmesh.material_override = gmat
	ground.add_child(gmesh)
	ground.position = Vector3(0, -0.25, 0)
	var gcol := CollisionShape3D.new()
	var gshape := BoxShape3D.new()
	gshape.size = Vector3(400, 0.5, 400)
	gcol.shape = gshape
	ground.add_child(gcol)
	return ground

func _make_ground_2d() -> Node:
	var ground := StaticBody2D.new()
	ground.name = "Ground"
	var gcol := CollisionShape2D.new()
	var gshape := WorldBoundaryShape2D.new()
	gcol.shape = gshape
	ground.add_child(gcol)
	ground.position = Vector2(0, 300)
	# A floor you can see. The 2D world used to be a collision line with no
	# pixels at all, so the player slid around over nothing.
	var grass: Texture2D = Assets.texture("grass")
	if grass != null:
		var skin := Node2D.new()
		skin.name = "Skin"
		# Ground is added after the entities, so without a negative z it paints
		# straight over the player standing on it
		skin.z_index = -10
		var dirt: Texture2D = Assets.texture("dirt")
		var tw := float(grass.get_width()) * 2.0
		var th := float(grass.get_height()) * 2.0
		for i in 52:
			var x := -700.0 + float(i) * tw
			var top := Sprite2D.new()
			top.texture = grass
			top.centered = false
			top.scale = Vector2(2, 2)
			top.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			top.position = Vector2(x, -th)
			skin.add_child(top)
			# several dirt rows, so the floor has thickness instead of being a
			# two-pixel line pasted under the grass — deep enough that the follow
			# camera never reveals the void under the world
			for r in 10:
				if dirt == null:
					break
				var bot := Sprite2D.new()
				bot.texture = dirt
				bot.centered = false
				bot.scale = Vector2(2, 2)
				bot.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				bot.position = Vector2(x, float(r) * th)
				skin.add_child(bot)
		ground.add_child(skin)
	return ground

## 2D has no WorldEnvironment, so the mood comes from a gradient behind the
## action plus a tint. Matches the 3D sky so both dimensions feel designed.
func _make_sky_2d() -> Node:
	# a hand-built vertical gradient (top of sky to horizon), no texture files
	var img := Image.create(4, 256, false, Image.FORMAT_RGBA8)
	var top := Color("#3f7cc0")
	var bottom := Color("#b9c9dd")
	for y in 256:
		var c: Color = top.lerp(bottom, float(y) / 255.0)
		for x in 4:
			img.set_pixel(x, y, c)
	var gfn := ImageTexture.create_from_image(img)
	var rect := Sprite2D.new()
	rect.name = "Sky"
	rect.texture = gfn
	rect.centered = false
	# the gradient is 4x256; stretched it must actually span the play area, so the
	# position is its top-left corner, not its centre
	rect.scale = Vector2(620.0, 5.5)
	rect.position = Vector2(-900, -900)
	rect.z_index = -100
	return rect

func _make_environment() -> Node:
	var env := Environment.new()
	# The default look, for a game with no Sky brick. This used to be a flat
	# background colour + linear tone mapping, which is why every 3D game read as
	# grey boxes floating in a void. A Sky brick still overrides everything here.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#3f7cc0")
	sky_mat.sky_horizon_color = Color("#b9c9dd")
	sky_mat.sky_curve = 0.32
	sky_mat.ground_horizon_color = Color("#a9b8c8")
	sky_mat.ground_bottom_color = Color("#262a31")
	sky_mat.ground_curve = 0.1
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# 1.0 ambient on top of a bright sky washed the whole scene out (measured:
	# neon-pastel ground). The sun is the key light; the sky only fills shadows.
	env.ambient_light_energy = 0.4
	# Filmic, never Linear: linear blows the brights out and flattens the rest.
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 4.0
	env.tonemap_exposure = 0.85
	# Fog hides the edge of the play field; without it the ground ends in a hard
	# line against the sky's grey lower hemisphere.
	env.fog_enabled = true
	env.fog_light_color = Color("#b9c9dd")
	env.fog_density = 0.0075
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	return we

func _make_sun() -> Node:
	var light := DirectionalLight3D.new()
	light.name = "SunLight"
	light.rotation_degrees = Vector3(-52.0, -32.0, 0.0)
	# warm key light against a cool sky: same-colour light and ambient is what
	# makes primitives look like untextured debug geometry
	light.light_color = Color("#fff2dc")
	light.light_energy = 0.95
	light.shadow_enabled = true
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	light.directional_shadow_max_distance = 120.0
	light.shadow_bias = 0.03
	return light

func _build_hud() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	var lbl := Label.new()
	lbl.name = "ScoreLabel"
	lbl.set_anchors_preset(Control.PRESET_TOP_LEFT)
	lbl.position = Vector2(16, 12)
	lbl.add_theme_font_size_override("font_size", 28)
	# The words the PLAYER reads are baked in the language the game was built in,
	# so a shipped .exe shows अंक / 得分 / Score without the friend's PC needing
	# any setting. Until this, every exported game was English-only.
	var w_score := _game_word("score", "Score")
	var w_lives := _game_word("lives", "Lives")
	var w_win := _game_word("you_win", "YOU WIN!")
	var w_lose := _game_word("game_over", "Game Over")
	lbl.text = w_score + ": 0"
	c.add_child(lbl)
	var msg := Label.new()
	msg.name = "MessageLabel"
	msg.set_anchors_preset(Control.PRESET_CENTER)
	msg.add_theme_font_size_override("font_size", 40)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.visible = false
	c.add_child(msg)
	# HUD script binds to the GameState autoload (same name generated code uses)
	var s := GDScript.new()
	s.source_code = (
		"extends Control\n"
		+ "const W_SCORE := \"" + w_score + "\"\n"
		+ "const W_LIVES := \"" + w_lives + "\"\n"
		+ "const W_WIN := \"" + w_win + "\"\n"
		+ "const W_LOSE := \"" + w_lose + "\"\n"
		+ "func _process(_d):\n"
		+ "\tvar s = get_node_or_null(\"ScoreLabel\")\n"
		+ "\tif s and GameState:\n"
		+ "\t\ts.text = W_SCORE + \": \" + str(GameState.score) + \" / \" + str(GameState.win_target) + \"    \" + W_LIVES + \": \" + str(GameState.lives)\n"
		+ "\tvar m = get_node_or_null(\"MessageLabel\")\n"
		+ "\tif m and GameState and GameState.game_over:\n"
		+ "\t\tm.visible = true\n"
		+ "\t\tm.text = W_WIN if GameState.won else W_LOSE\n"
		+ "\telif m:\n"
		+ "\t\tm.visible = false\n"
	)
	s.reload()
	c.set_script(s)
	return c

## A word for the player's HUD, in the language they are building in. Falls back
## to English for any key that has no entry, and strips double quotes so the
## generated script can never be broken by a translation.
func _game_word(key: String, fallback: String) -> String:
	var v := str(I18n.t(key))
	if v == key or v.strip_edges().is_empty():
		return fallback
	return v.replace("\"", "'").replace("\\", "'")

# ---------------------------------------------------------------------------
# The escape hatch: show the user the generated code (Visual/Code toggle).
# Deterministic pseudocode summary of what their bricks compiled to,
# grouped in execution order. Never crashes on a partial brick.
# ---------------------------------------------------------------------------
func generated_script(graph) -> String:
	var lines: Array[String] = []
	var bricks := _bricks_of(graph)
	var order := _order_of(graph, bricks)
	lines.append("# EasyForge generated from %d bricks (genre: %s, %s)" % [
		bricks.size(), str(_prop(graph, "genre", "platformer")), str(_prop(graph, "dimension", "3d"))])
	lines.append("# Read top to bottom — this is the order the game runs in.")
	var step := 0
	for b in order:
		if not b is Dictionary:
			continue
		step += 1
		var kind := _kind(b)
		var p := _params(b)
		lines.append("")
		lines.append("# %d. %s %s" % [step, BrickRegistry.kind_icon(kind), _title(b)])
		var comment := str(b.get("comment", ""))
		if not comment.strip_edges().is_empty():
			lines.append("#    your note: %s" % comment)
		match kind:
			"spawn":
				lines.append("spawn %s at %s" % [
					str(p.get("model", "player")),
					str(_vec3(p.get("position", null), Vector3(0, 1, 0)))])
			"move":
				lines.append("move(entity, speed=%.1f, jump=%.1f, gravity=%.1f)" % [
					_num(p, "speed", 8.0), _num(p, "jump", 12.0), _num(p, "gravity", 30.0)])
			"collide":
				var kinds := []
				for t in _outgoing_targets(b, graph):
					if t is Dictionary:
						kinds.append(_kind(t))
				lines.append("on_touch(entity, '%s') -> %s" % [str(p.get("with", "coin")), str(kinds)])
			"score":
				lines.append("score('%s', op='%s', amount=%d)" % [
					str(p.get("variable", "score")), str(p.get("op", "add")), int(_num(p, "amount", 1.0))])
			"winlose":
				lines.append("win_lose(when %s reaches %d)" % [
					str(p.get("condition", "score_reaches")), int(_num(p, "value", 10.0))])
			"variable":
				var vn := str(p.get("name", "value"))
				var vop := str(p.get("op", "add"))
				var vscope := str(p.get("scope", "game"))
				match vop:
					"set":
						lines.append("var '%s' [%s] set to %d" % [vn, vscope, int(_num(p, "value", 0.0))])
					"toggle":
						lines.append("var '%s' [%s] toggle true/false" % [vn, vscope])
					_:
						lines.append("var '%s' [%s] add %d on event" % [vn, vscope, int(_num(p, "amount", 1.0))])
			"rule":
				var csrc := str(p.get("cond_source", "variable"))
				var cvar := str(p.get("cond_var", "value"))
				var cop := str(p.get("cond_op", ">="))
				var cval := int(_num(p, "cond_value", 0.0))
				var cond_str := "%s %s %d" % [cvar, cop, cval]
				if csrc == "key":
					cond_str = "key %s pressed" % str(p.get("cond_key", "Space"))
				elif csrc == "collided":
					cond_str = "player touched something"
				elif csrc == "timer":
					cond_str = "time %s %d" % [cop, cval]
				lines.append("rule: if %s then %s" % [cond_str, str(p.get("actions", "win"))])
			"platform":
				lines.append("platform(surface='%s', one_way=%s, bounce=%.2f, friction=%.2f)" % [
					str(p.get("preset", "normal")), str(bool(p.get("one_way", false))),
					_num(p, "bounce", 0.0), _num(p, "friction", 1.0)])
			"background":
				lines.append("background(%d parallax layers, theme='%s')" % [
					int(clampf(_num(p, "layers", 2.0), 1.0, 3.0)), str(p.get("theme", "dusk"))])
			"sky":
				lines.append("sky(environment='%s')" % str(p.get("preset", "day")))
			"door":
				var gate_str := str(p.get("needs_var", ""))
				if gate_str.strip_edges().is_empty():
					lines.append("door -> go to level %s at entry '%s' (%s)" % [
						str(p.get("target_level", "2")), str(p.get("target_entry", "start")),
						str(p.get("transition", "fade"))])
				else:
					lines.append("door -> go to level %s (only if '%s')" % [
						str(p.get("target_level", "2")), gate_str])
			"entry":
				lines.append("entry_point('%s')" % str(p.get("marker", "start")))
			"level":
				var pat := str(p.get("pattern", "")).replace(";", " / ")
				lines.append("level map [%s] theme=%s" % [pat, str(p.get("theme", "grass"))])
			"trigger":
				lines.append("trigger zone(%s, %.1f) on %s -> %s%s" % [
					str(p.get("shape", "box")), _num(p, "size", 4.0),
					str(p.get("target", "player")), str(p.get("on_enter", "win")),
					(" [once]" if bool(p.get("once", true)) else "")])
			"collider":
				var cw := str(p.get("collides_with", ""))
				lines.append("collider(layer=%s%s, shape=%s, %.1f)" % [
					str(p.get("layer", "world")),
					(", vs " + cw) if not cw.strip_edges().is_empty() else "",
					str(p.get("shape", "box")), _num(p, "size", 4.0)])
			"save":
				lines.append("save(slot %d, %s, key=%s)" % [
					int(_num(p, "slot", 1.0)), str(p.get("mode", "manual")), str(p.get("key", "F5"))])
			"checkpoint_save":
				lines.append("save_point(slot %d) -> saves progress on touch" % int(_num(p, "slot", 1.0)))
			"look":
				lines.append("look(preset='%s', bloom=%.2f, sat=%.2f%s%s)" % [
					str(p.get("preset", "cinematic")), _num(p, "bloom", 0.35),
					_num(p, "saturation", 1.0),
					", ssao" if bool(p.get("ssao", false)) else "",
					", fog" if bool(p.get("fog", false)) else ""])
			"gamepad":
				lines.append("gamepad(device %d, deadzone %.2f%s)" % [
					int(_num(p, "device", 0.0)), _num(p, "deadzone", 0.2),
					", vibrate" if bool(p.get("vibrate", true)) else ""])
			"screen":
				lines.append("screen('%s', title='%s'%s)" % [
					str(p.get("kind_of_screen", "main_menu")), str(p.get("title", "My Game")),
					", pauses the game" if bool(p.get("pause_game", true)) else ""])
			"button":
				lines.append("button('%s') -> %s" % [
					str(p.get("label", "Play")), str(p.get("action", "start"))])
			"undo":
				lines.append("undo(key %s, %d steps%s)" % [
					str(p.get("key", "Z")), int(_num(p, "depth", 5.0)),
					", +position" if bool(p.get("track_position", true)) else ""])
			"pathfind":
				lines.append("pathfind(mode='%s', speed=%.1f, stop at %.1f%s)" % [
					str(p.get("mode", "chase")), _num(p, "speed", 4.0),
					_num(p, "arrive_radius", 1.5),
					", shows the path" if bool(p.get("draw_path", true)) else ""])
			"state":
				lines.append("state('%s' starts '%s') states=[%s]%s" % [
					str(p.get("var_name", "enemy_state")), str(p.get("initial", "idle")),
					str(p.get("states", "idle,patrol,chase,attack")),
					" rules: " + str(p.get("transitions", "")) if not str(p.get("transitions", "")).strip_edges().is_empty() else ""])
			"widget":
				var wk := str(p.get("widget_kind", "button"))
				var wact := str(p.get("action", "none"))
				lines.append("widget(%s '%s') -> %s%s" % [
					wk, str(p.get("label", "Button")),
					"nothing" if wact == "none" else wact,
					" " + str(p.get("var_name", "")) if wact in ["set_var", "emit_event"] and str(p.get("var_name", "")).strip_edges() != "" else ""])
			"watch":
				lines.append("watch(%s)%s" % [
					str(p.get("var_names", "score,coins")),
					", editable" if bool(p.get("editable", true)) else ""])
			"error_panel":
				lines.append("problem reporter (%s)%s" % [
					str(p.get("detail_level", "short")),
					", opens automatically" if bool(p.get("auto_open", true)) else ""])
			"light":
				lines.append("light(%s '%s', brightness %.1f, reach %.0f)%s%s" % [
					str(p.get("kind_of_light", "point")), str(p.get("color_name", "warm")),
					_num(p, "intensity", 1.5), _num(p, "range", 320.0),
					", casts shadows" if bool(p.get("shadows", true)) else "",
					", flickers" if bool(p.get("flicker", false)) else ""])
			"occluder":
				lines.append("occluder(%s %.0fx%.0f)" % [
					str(p.get("shape", "box")), _num(p, "width", 96.0), _num(p, "height", 96.0)])
			"blueprint_def":
				lines.append("blueprint '%s'%s" % [
					str(p.get("name", "Coin")),
					": " + str(p.get("description", "")) if str(p.get("description", "")).strip_edges() != "" else ""])
			"blueprint":
				lines.append("place '%s' x%d (%s)%s" % [
					str(p.get("blueprint_name", "Coin")), int(_num(p, "count", 1.0)),
					str(p.get("layout", "row")),
					" changes: " + str(p.get("overrides", "")) if str(p.get("overrides", "")).strip_edges() != "" else ""])
			"attach":
				lines.append("attach('%s' -> '%s')%s" % [
					str(p.get("child_brick", "")), str(p.get("parent_brick", "")),
					"" if bool(p.get("follow_position", true)) else " (stays put)"])
			"rigid":
				lines.append("physics(%s, weight %.1f, bounce %.2f, locked: %s)" % [
					str(p.get("model", "box")), _num(p, "mass", 1.0),
					_num(p, "bounciness", 0.2), str(p.get("freeze", "none"))])
			"audio":
				lines.append("sound('%s') on %s at %d dB%s%s" % [
					str(p.get("sound_kind", "coin")), str(p.get("bus", "sfx")),
					int(_num(p, "volume_db", 0.0)),
					", loops" if bool(p.get("loop", false)) else "",
					", waits" if not bool(p.get("play_on_start", true)) else ""])
			"perceive":
				lines.append("notices you (sees %.0f at %.0f°, hears %.0f, remembers %.0fs)" % [
					_num(p, "sight_range", 12.0), _num(p, "sight_angle", 90.0),
					_num(p, "hearing_range", 6.0), _num(p, "memory_seconds", 5.0)])
			"style":
				lines.append("looks '%s' with %s accents, %s screen changes" % [
					str(p.get("preset", "clean")), str(p.get("accent", "gold")),
					str(p.get("transition", "fade"))])
			"hud":
				var hw := str(p.get("widget", "bar"))
				var hv := str(p.get("var_name", "health"))
				var hl := str(p.get("label", ""))
				lines.append("shows %s of '%s'%s" % [
					hw, hv, " labeled '" + hl + "'" if hl.strip_edges() != "" else ""])
			"inventory":
				var iop2 := str(p.get("op", "add"))
				match iop2:
					"remove":
						lines.append("inventory('%s') remove %d" % [str(p.get("item", "key")), int(_num(p, "amount", 1.0))])
					"check":
						lines.append("inventory('%s') need %d to pass" % [str(p.get("item", "key")), int(_num(p, "need", 1.0))])
					_:
						lines.append("inventory('%s') add %d" % [str(p.get("item", "key")), int(_num(p, "amount", 1.0))])
			"timer":
				var tmode := str(p.get("mode", "once"))
				if tmode == "repeat":
					lines.append("timer('%s') every %.1fs -> %s" % [str(p.get("name", "main")), _num(p, "every", 3.0), str(p.get("on_end", "lose"))])
				else:
					lines.append("timer('%s') %.0fs -> %s" % [str(p.get("name", "main")), _num(p, "seconds", 20.0), str(p.get("on_end", "lose"))])
			"enemy_patrol":
				lines.append("enemy_patrol(entity, speed=%.1f, range=%.1f) -> lose on touch" % [
					_num(p, "speed", 1.5), _num(p, "range", 5.0)])
			"hazard":
				lines.append("hazard(entity) -> lose a life on touch, respawn at checkpoint")
			"checkpoint":
				lines.append("checkpoint(entity) -> save respawn point on touch")
			"moving_platform":
				lines.append("moving_platform(entity, speed=%.1f, range=%.1f)" % [
					_num(p, "speed", 2.0), _num(p, "range", 5.0)])
			_:
				if kind.is_empty():
					lines.append("# (brick with no kind — shown as a placeholder in the game)")
				else:
					lines.append("# (brick kind '%s' — shown as a placeholder in the game)" % kind)
	return "\n".join(lines)

# ---------------------------------------------------------------------------
# Safe accessors — every brick read goes through these. A brick from the AI
# may be missing any key entirely, or hold the wrong type for it.
# ---------------------------------------------------------------------------
static func _params(b: Dictionary) -> Dictionary:
	var v = b.get("params")
	return v if v is Dictionary else {}

static func _conns(b: Dictionary) -> Array:
	var v = b.get("connections")
	return v if v is Array else []

static func _kind(b: Dictionary) -> String:
	var k = b.get("kind")
	return str(k) if k != null else ""

static func _id(b: Dictionary) -> String:
	var i = b.get("id")
	return str(i) if i != null else ""

static func _title(b: Dictionary) -> String:
	var t = b.get("title")
	if t != null and not str(t).is_empty():
		return str(t)
	return BrickRegistry.kind_label(_kind(b))

static func _coerce_num(x, fallback: float) -> float:
	if x is float or x is int:
		var f := float(x)
		# NaN and Inf are legal floats but poison every downstream transform:
		# a node positioned at (nan,nan,nan) makes the whole game unplayable.
		# Treat them as invalid input and fall back, exactly like a wrong type.
		if is_nan(f) or is_inf(f):
			return fallback
		return f
	if x is String and str(x).is_valid_float():
		var s := float(x)
		if is_nan(s) or is_inf(s):
			return fallback
		return s
	return fallback

static func _num(d: Dictionary, key: String, fallback: float) -> float:
	return _coerce_num(d.get(key), fallback)

static func _vec3(v, fallback: Vector3) -> Vector3:
	if v is Vector3:
		return v
	if v is Array and v.size() >= 3:
		return Vector3(
			_coerce_num(v[0], fallback.x),
			_coerce_num(v[1], fallback.y),
			_coerce_num(v[2], fallback.z))
	return fallback

static func _vec2(v, fallback: Vector2) -> Vector2:
	if v is Vector2:
		return v
	if v is Array and v.size() >= 2:
		return Vector2(
			_coerce_num(v[0], fallback.x),
			_coerce_num(v[1], fallback.y))
	return fallback

static func _prop(obj, key: String, default_value):
	if obj == null:
		return default_value
	var v = obj.get(key)
	if v == null:
		return default_value
	return v

static func _bricks_of(g) -> Array:
	var v = _prop(g, "bricks", [])
	return v if v is Array else []

static func _order_of(g, bricks: Array) -> Array:
	if g != null and g.has_method("execution_order"):
		var o = g.execution_order()
		if o is Array and not o.is_empty():
			return o
	return bricks
