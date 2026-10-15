extends Node
## GameState — the runtime global the compiled game reads/writes.
##
## Registered as the autoload singleton "GameState" (project.godot), which is
## exactly the name generated game scripts reference (GameState.add_score()).
## This dual role is deliberate: one object is both the autoload and the
## per-game state the compiler attaches to the compiled scene root.
##
## HARDENING: every method is safe to call any number of times, from any
## generated script, in any order. The compiler only emits calls to methods
## defined here.

class_name GameStateClass

var score: int = 0
var win_target: int = 10
var win_condition: String = "score_reaches"
var score_step: int = 1
var game_over: bool = false
var won: bool = false
var lives: int = 3
var max_lives: int = 3
var respawn_position: Vector3 = Vector3(0, 1, 0)

# --- Wave 1: the variable store (Variable brick) ---------------------------
# A flat dict name -> Variant (number or bool). Global "game" scope lives here;
# per-"player" scope is tracked the same way (single-player game, one player).
# Every accessor coerces junk to a safe default so generated code never throws.
var vars: Dictionary = {}

# --- Wave 8: named event bus -------------------------------------------------
# Bricks could previously only talk to bricks they were directly wired to, so
# "when the player dies, everything that cares should hear" cost one wire per
# consumer. A named channel collapses that to one emit / one listen.
var _listeners: Dictionary = {}

## Fire a named event. Any number of listeners across the game can react.
func emit_event(name: String, payload = null) -> void:
	var key := str(name)
	if key.is_empty():
		return
	if not _listeners.has(key):
		return
	var cbs: Array = _listeners[key]
	# copy: a listener may unlisten itself from inside the callback
	for cb in cbs.duplicate():
		if cb is Callable:
			(cb as Callable).call(key, payload)

## Subscribe to a named event. Returns a token you can pass to unlisten().
func listen_event(name: String, cb: Callable) -> int:
	var key := str(name)
	if key.is_empty() or not cb.is_valid():
		return 0
	if not _listeners.has(key):
		_listeners[key] = []
	var cbs: Array = _listeners[key]
	if not cbs.has(cb):
		cbs.append(cb)
	return cb.get_object_id() if cb.get_object() != null else 1

## Unsubscribe. Safe to call with an unknown/removed token.
func unlisten_event(name: String, cb: Callable) -> void:
	var key := str(name)
	if not _listeners.has(key):
		return
	var cbs: Array = _listeners[key]
	cbs.erase(cb)
	if cbs.is_empty():
		_listeners.erase(key)

func get_var(name: String, default_value = 0) -> Variant:
	var key := str(name)
	if key.is_empty():
		return default_value
	if vars.has(key):
		return vars[key]
	# remember the default so reads are stable
	vars[key] = default_value
	return default_value

func set_var(name: String, value) -> void:
	var key := str(name)
	if not key.is_empty():
		vars[key] = value

func add_var(name: String, amount) -> void:
	var key := str(name)
	if key.is_empty():
		return
	var cur: float = get_var(key, 0) if not (get_var(key, 0) is bool) else 0.0
	var add: float = amount if (amount is float or amount is int) else 0.0
	vars[key] = cur + add

func toggle_var(name: String) -> void:
	var key := str(name)
	if key.is_empty():
		return
	var cur = get_var(key, false)
	if cur is bool:
		vars[key] = not cur
	else:
		vars[key] = not (cur != 0)

func add_score(amount: int = 1) -> void:
	if game_over:
		return
	score += amount
	check_win()

func register_score_source(_variable: String, step: int) -> void:
	score_step = step

func set_win_condition(condition: String, value: int) -> void:
	win_condition = condition
	win_target = value

func check_win() -> void:
	if game_over:
		return
	match win_condition:
		"score_reaches":
			if score >= win_target:
				_win()
		"score_drops":
			if score <= win_target:
				_win()
		_:
			if score >= win_target:
				_win()

func lose() -> void:
	if game_over:
		return
	game_over = true
	won = false

## Hazard contact: lose a life, respawn the player at the last checkpoint.
## Out of lives = game over. Safe to call with any node (or none).
func hit_hazard(body = null) -> void:
	if game_over:
		return
	lives -= 1
	if lives <= 0:
		lives = 0
		game_over = true
		won = false
		return
	# send the player back to the checkpoint
	if body != null and body is Node3D:
		var n3 := body as Node3D
		if is_instance_valid(n3):
			n3.global_position = respawn_position
	elif body != null and body is Node2D:
		var n2 := body as Node2D
		if is_instance_valid(n2):
			n2.global_position = Vector2(respawn_position.x, respawn_position.y)

## Called by a checkpoint when the player touches it. `body` may be null.
func set_respawn(position, body = null) -> void:
	var p = position
	if p is Vector3:
		respawn_position = p
	elif p is Vector2:
		respawn_position = Vector3(p.x, p.y, 0)
	if body != null and body is Node3D:
		var n3 := body as Node3D
		if is_instance_valid(n3):
			respawn_position = n3.global_position

func reset() -> void:
	score = 0
	game_over = false
	won = false
	lives = max_lives
	vars.clear()
	# win_target/win_condition are set per game by compile_graph

func _win() -> void:
	game_over = true
	won = true

# --- Wave 1: time scale + hit-stop (Rule brick action verbs) ---------------
func set_time_scale(scale: float) -> void:
	Engine.time_scale = clampf(scale, 0.0, 4.0)

## Brief frame-freeze on impact. Self-restoring: schedules the reset so the
## caller never has to remember to undo it.
func hit_stop(seconds: float = 0.08) -> void:
	var prev := Engine.time_scale
	Engine.time_scale = 0.0
	_restore_time_scale(seconds, prev)

var _time_scale_restore_pending := false
func _restore_time_scale(delay: float, value: float) -> void:
	if _time_scale_restore_pending:
		return
	_time_scale_restore_pending = true
	var t := get_tree().create_timer(maxf(delay, 0.01), true, false, true) \
		if is_inside_tree() else null
	if t == null:
		Engine.time_scale = value
		_time_scale_restore_pending = false
		return
	# ignore the scaled timer so the freeze really lasts `delay` real seconds
	await t.timeout
	Engine.time_scale = value
	_time_scale_restore_pending = false

# ---------------------------------------------------------------------------
# Audio — synthesized WAV tones (no asset files). Any generated script can
# call GameState.play_sound("coin") for a distinct beep per kind. Uses tiny
# in-memory AudioStreamWAV buffers: dead simple and reliable.
# ---------------------------------------------------------------------------
var _sfx_cache := {}   # kind -> AudioStreamWAV

func play_sound(kind: String, volume: float = 0.7) -> void:
	var root = get_tree().current_scene
	if root == null:
		return
	var player = root.get_node_or_null("SfxPlayer")
	if player == null:
		player = AudioStreamPlayer.new()
		player.name = "SfxPlayer"
		root.add_child(player)
	var stream = _tone_wav(str(kind))
	if stream != null:
		player.stream = stream
		player.volume_db = linear_to_db(clampf(volume, 0.0, 1.0))
		player.play()

## Distinct (freq, seconds) per kind -> a short decaying sine as a WAV buffer.
func _tone_wav(kind: String) -> AudioStreamWAV:
	if _sfx_cache.has(kind):
		return _sfx_cache[kind]
	var tones := {
		"coin": [880.0, 0.14], "jump": [520.0, 0.12], "hit": [170.0, 0.2],
		"win": [660.0, 0.45], "lose": [130.0, 0.45], "click": [740.0, 0.06],
	}
	var t = tones.get(kind, [440.0, 0.15])
	var freq: float = t[0]
	var dur: float = t[1]
	var mix_rate := 22050
	var n := int(mix_rate * dur)
	var data := PackedByteArray()
	data.resize(n)  # 8-bit unsigned
	for i in n:
		var env = 1.0 - (float(i) / float(n))
		var v = sin(float(i) * freq * TAU / float(mix_rate)) * env
		data[i] = int(clampf(128.0 + v * 120.0, 0.0, 255.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = mix_rate
	wav.data = data
	_sfx_cache[kind] = wav
	return wav

# ---------------------------------------------------------------------------
# Health — tracks player health for the Health brick.
# ---------------------------------------------------------------------------
func set_max_health(v: int) -> void:
	max_lives = v
	lives = v

func damage(amount: int = 1) -> void:
	if game_over:
		return
	lives -= amount
	if lives <= 0:
		lives = 0
		game_over = true
		won = false

func current_health() -> int:
	return lives

# ---------------------------------------------------------------------------
# Particles — spawn a short-lived burst of small colored quads/spheres at a
## position. No asset files; pure procedural. Safe to call from any script.
# ---------------------------------------------------------------------------
func burst(amount: int = 16, effect: String = "sparkle", color: String = "gold", at = null) -> void:
	var root = get_tree().current_scene
	if root == null:
		return
	var pos: Vector3 = at if at is Vector3 else (Vector3(at.x, at.y, 0) if at is Vector2 else Vector3.ZERO)
	var col := _color_for(color)
	var n := int(clampf(float(amount), 4.0, 64.0))
	for i in n:
		var p := _make_particle(effect, col)
		if p == null:
			continue
		# scatter around the point
		var ang := TAU * float(i) / float(n)
		var r := 0.4 + randf() * 0.6
		if p is Node3D:
			(p as Node3D).position = pos + Vector3(cos(ang) * r, randf() * 1.2, sin(ang) * r)
		elif p is Node2D:
			(p as Node2D).position = Vector2(pos.x + cos(ang) * r * 20.0, pos.y + sin(ang) * r * 20.0)
		root.add_child(p)
		# auto-free after a moment
		_free_after(p, 0.7)

func _color_for(name: String) -> Color:
	match name:
		"red": return Color("#ff5252")
		"blue": return Color("#4fc3f7")
		"green": return Color("#69f0ae")
		"white": return Color("#ffffff")
		_: return Color("#ffd54f")  # gold

func _make_particle(effect: String, col: Color) -> Node:
	if _3d_particles():
		var m := MeshInstance3D.new()
		var mesh: Mesh
		match effect:
			"smoke", "fire":
				var sp := SphereMesh.new()
				sp.radius = 0.12
				sp.height = 0.24
				mesh = sp
			"snow":
				var sp := SphereMesh.new()
				sp.radius = 0.08
				sp.height = 0.16
				mesh = sp
			_:  # sparkle
				var bx := BoxMesh.new()
				bx.size = Vector3(0.14, 0.14, 0.14)
				mesh = bx
		m.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 1.5
		m.material_override = mat
		return m
	# 2D
	var s := Sprite2D.new()
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(col)
	s.texture = ImageTexture.create_from_image(img)
	return s

func _3d_particles() -> bool:
	var root = get_tree().current_scene
	if root == null:
		return true
	return root.has_node("EasyForgeGame3D")

func _free_after(node: Node, seconds: float) -> void:
	var s := GDScript.new()
	s.source_code = (
		"extends Node\n"
		+ "func _ready():\n"
		+ "	await get_tree().create_timer(%f).timeout\n" % seconds
		+ "	get_parent().queue_free()\n"
	)
	if s.reload() == OK:
		node.set_script(s)
