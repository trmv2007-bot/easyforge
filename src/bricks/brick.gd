## Brick — the single unit of the IR (intermediate representation).
##
## Static utility class: BrickRef.create(kind), BrickRef.can_connect(...), etc.
## Called from everywhere (compiler, templates, AI generator).
##
## A Brick is pure data (a Dictionary underneath). It never holds game code;
## the AI generates bricks, the user edits them, the compiler turns them into
## GDScript. Keeping them as plain dictionaries means:
##   - trivially serializable to JSON (save/load projects)
##   - trivially comparable in tests
##   - zero coupling to the UI or the engine runtime
##
## Port typing is the "softly guided" rule from the spec: a port only lights up
## when connected to a compatible type, but nothing is hard-blocked.

class_name BrickRef

enum PortType { FLOW, EVENT, VALUE }

const PORT_TYPE_NAMES := {
	PortType.FLOW: "flow",
	PortType.EVENT: "event",
	PortType.VALUE: "value",
}

# ---------------------------------------------------------------------------
# Brick kinds. v1 ships the 5 universal kinds; genre libraries add more.
# Every brick declares which port types it accepts on input/output so the
# graph editor can validate connections.
# ---------------------------------------------------------------------------
const KIND := {
	"spawn":   {"label": "Spawn",   "icon": "✨", "in": [PortType.EVENT], "out": [PortType.FLOW]},
	"move":    {"label": "Move",    "icon": "🏃", "in": [PortType.FLOW, PortType.EVENT], "out": [PortType.FLOW]},
	"collide": {"label": "Collide", "icon": "💥", "in": [PortType.FLOW], "out": [PortType.EVENT]},
	"score":   {"label": "Score",   "icon": "🏆", "in": [PortType.EVENT], "out": [PortType.FLOW]},
	"winlose": {"label": "Win/Lose","icon": "🚩", "in": [PortType.EVENT, PortType.VALUE], "out": [PortType.FLOW]},
	"camera":  {"label": "Camera",   "icon": "🎥", "in": [PortType.FLOW], "out": []},
	"sound":   {"label": "Sound",    "icon": "🔊", "in": [PortType.EVENT], "out": []},
	"particles": {"label": "Particles", "icon": "✨", "in": [PortType.FLOW], "out": []},
	"animation": {"label": "Animation", "icon": "🌀", "in": [PortType.FLOW], "out": []},
	"health":  {"label": "Health",   "icon": "❤️", "in": [PortType.EVENT], "out": [PortType.VALUE]},
	# --- Wave 1: variables + rules (the structural enabler) ---
	# Variable: a named value slot (get/set/add) with a scope. Reads/writes the
	# generated GameState store. value out-port feeds winlose/rule comparisons.
	"variable": {"label": "Variable", "icon": "🔢", "in": [PortType.EVENT], "out": [PortType.VALUE]},
	# Rule: if <conditions> then <actions>. The ONE primitive that converts the
	# roadmap from O(new brick types) to O(new rules on existing bricks).
	# in = event that arms the rule; out = action targets it fires.
	"rule":     {"label": "Rule",     "icon": "🧠", "in": [PortType.EVENT], "out": [PortType.EVENT]},
	# Platform: a solid surface with tunable physics (one-way, bounce, friction).
	# The ice/trampoline presets are what make these instantly recognizable.
	"platform": {"label": "Platform", "icon": "🟫", "in": [PortType.FLOW], "out": [PortType.FLOW]},
	# Background: parallax layers for depth (procedural gradients, no assets).
	"background": {"label": "Background", "icon": "🌄", "in": [PortType.FLOW], "out": []},
	# Sky/Environment: a themed preset that colors the whole scene (2D tint or
	# 3D WorldEnvironment) so a project stops looking like a bare default.
	"sky":      {"label": "Sky",      "icon": "🌤️", "in": [PortType.FLOW], "out": []},
	# Door/Portal: connects two levels; carries the target level + entry marker.
	"door":     {"label": "Door",     "icon": "🚪", "in": [PortType.EVENT], "out": [PortType.FLOW]},
	# Entry Point: a named spawn marker a door/level can send the player to.
	"entry":    {"label": "Entry Point", "icon": "📍", "in": [PortType.FLOW], "out": []},
	# Inventory: a named item counter (keys, coins, power-ups) with a need-to-pass.
	"inventory": {"label": "Inventory", "icon": "🎒", "in": [PortType.EVENT], "out": [PortType.VALUE]},
	# Level: a paint-by-pattern grid that generates real floor + platform tiles.
	# The pattern string is beginner-friendly (# = solid, . = empty, ^ = spike).
	"level": {"label": "Level", "icon": "🗺️", "in": [PortType.FLOW], "out": []},
	# --- Feature-registry bricks (src/features/*.gd) ---
	# Trigger Zone: an invisible/faint volume that fires actions on enter.
	"trigger": {"label": "Trigger Zone", "icon": "🎯", "in": [PortType.EVENT], "out": [PortType.EVENT]},
	# Collider: a solid with named collision layers/masks.
	"collider": {"label": "Collider", "icon": "🧱", "in": [PortType.FLOW], "out": [PortType.FLOW]},
	# Save / Checkpoint-save: versioned JSON save slots.
	"save": {"label": "Save", "icon": "💾", "in": [PortType.EVENT], "out": []},
	"checkpoint_save": {"label": "Save Point", "icon": "🚩", "in": [PortType.FLOW], "out": [PortType.FLOW]},
	# Look: a curated post-processing grade (one Environment swap).
	"look": {"label": "Look", "icon": "🎨", "in": [PortType.FLOW], "out": []},
	# Gamepad: joystick + button + vibration support.
	"gamepad": {"label": "Gamepad", "icon": "🎮", "in": [PortType.FLOW], "out": []},
	# Screen / Button: a real menu system (the biggest gap in the survey).
	"screen": {"label": "Screen", "icon": "🖥️", "in": [PortType.FLOW], "out": [PortType.EVENT]},
	"button": {"label": "Button", "icon": "🔘", "in": [PortType.EVENT], "out": []},
	# Undo: an in-game undo of the last few state changes.
	"undo": {"label": "Undo", "icon": "↩️", "in": [PortType.FLOW], "out": []},
	# Pathfind: real navigation so enemies stop getting stuck on walls.
	"pathfind": {"label": "Pathfind", "icon": "🧭", "in": [PortType.FLOW], "out": [PortType.EVENT]},
	# State: a declarative state machine (idle/patrol/chase/attack).
	"state": {"label": "State Machine", "icon": "🎭", "in": [PortType.FLOW], "out": [PortType.EVENT]},
	# Widget: a real UI control in the game (button/slider/toggle/dropdown).
	"widget": {"label": "Widget", "icon": "🎚️", "in": [PortType.FLOW], "out": []},
	# Watch: see and edit a variable live while the game runs.
	"watch": {"label": "Watch", "icon": "🔎", "in": [PortType.FLOW], "out": []},
	# Error Panel: plain-language report of what is wrong and which brick.
	"error_panel": {"label": "Problem Reporter", "icon": "🛠️", "in": [PortType.FLOW], "out": []},
	# Light / Occluder: 2D lighting and shadows (Godot's SDF occluders = free shadows).
	"light": {"label": "Light", "icon": "💡", "in": [PortType.FLOW], "out": []},
	"occluder": {"label": "Occluder", "icon": "🕶️", "in": [PortType.FLOW], "out": []},
	# Blueprint: define once, place many — one bug fix applies everywhere.
	"blueprint_def": {"label": "Blueprint", "icon": "🧩", "in": [PortType.FLOW], "out": [PortType.EVENT]},
	"blueprint": {"label": "Place Blueprint", "icon": "✨", "in": [PortType.FLOW], "out": []},
	# Attach: stick one thing to another so it moves with it.
	"attach": {"label": "Attach", "icon": "🔗", "in": [PortType.FLOW], "out": []},
	# Rigid: real physics — falling crates, stacking boxes.
	"rigid": {"label": "Physics Object", "icon": "📦", "in": [PortType.FLOW], "out": []},
	# Audio: a real synthesized sound on a named mixer bus.
	"audio": {"label": "Sound", "icon": "🔊", "in": [PortType.FLOW], "out": []},
	# Perceive: let an enemy actually notice you (sight cone, hearing, memory).
	"perceive": {"label": "Notice Me", "icon": "👁️", "in": [PortType.FLOW], "out": [PortType.EVENT]},
	# Style: make the whole game look designed, with screen transitions.
	"style": {"label": "Style", "icon": "🎨", "in": [PortType.FLOW], "out": []},
	# HUD: a display that reads a variable by itself.
	"hud": {"label": "Show On Screen", "icon": "📊", "in": [PortType.FLOW], "out": []},
}

# ---------------------------------------------------------------------------
# Param schema — declares which params are user-editable and how.
## Each entry: key -> {"type": "number"|"text"|"choice"|"bool", "label": str,
##                     optional "min"/"max"/"step" (number), "options": [..] (choice),
##                     optional "default": value}. The UI builds real controls
## from this; the compiler reads the resulting param values.
# ---------------------------------------------------------------------------
const PARAM_SCHEMA := {
	"spawn": {
		"model": {"type": "choice", "label": "What is it", "options": ["player", "enemy", "coin", "box"], "default": "player"},
		"position_y": {"type": "number", "label": "Height", "min": 0.0, "max": 20.0, "step": 0.5, "default": 1.0},
		# controls (player key bindings) — grouped under "Controls" in the inspector
		"key_left": {"type": "choice", "label": "Left", "options": ["A", "Left", "J"], "default": "A"},
		"key_right": {"type": "choice", "label": "Right", "options": ["D", "Right", "L"], "default": "D"},
		"key_jump": {"type": "choice", "label": "Jump", "options": ["Space", "W", "Up", "K"], "default": "Space"},
		"key_up": {"type": "choice", "label": "Up", "options": ["W", "Up"], "default": "W"},
		"key_down": {"type": "choice", "label": "Down", "options": ["S", "Down"], "default": "S"},
		# --- game-feel knobs (invisible when right, game-ruining when absent) ---
		# coyote time: jump still works this long after leaving a ledge
		"coyote_time": {"type": "number", "label": "Coyote time", "min": 0.0, "max": 0.3, "step": 0.01, "default": 0.1},
		# jump buffer: pressing jump this long before landing still jumps
		"jump_buffer": {"type": "number", "label": "Jump buffer", "min": 0.0, "max": 0.3, "step": 0.01, "default": 0.12},
		# variable jump height: release jump -> velocity scaled by this (0.4 = short hop)
		"jump_cut": {"type": "number", "label": "Jump cut", "min": 0.1, "max": 1.0, "step": 0.05, "default": 0.45},
		# asymmetric gravity: falling is this many x faster than rising
		"fall_gravity": {"type": "number", "label": "Fall gravity x", "min": 1.0, "max": 3.0, "step": 0.1, "default": 1.7},
	},
	"move": {
		"style": {"type": "choice", "label": "Style", "options": ["platformer", "topdown", "fly"], "default": "platformer"},
		"speed": {"type": "number", "label": "Speed", "min": 1.0, "max": 40.0, "step": 0.5, "default": 8.0},
		"jump": {"type": "number", "label": "Jump", "min": 0.0, "max": 40.0, "step": 0.5, "default": 12.0},
		"gravity": {"type": "number", "label": "Gravity", "min": 0.0, "max": 100.0, "step": 1.0, "default": 30.0},
	},
	"collide": {
		"with": {"type": "choice", "label": "What it touches", "options": ["coin", "enemy", "hazard", "checkpoint", "goal"], "default": "coin"},
		"action": {"type": "choice", "label": "Then", "options": ["collect", "lose", "win", "respawn"], "default": "collect"},
	},
	"score": {
		"variable": {"type": "text", "label": "Variable", "default": "score"},
		"op": {"type": "choice", "label": "Operation", "options": ["add", "subtract", "set"], "default": "add"},
		"amount": {"type": "number", "label": "Amount", "min": -100.0, "max": 100.0, "step": 1.0, "default": 1},
	},
	"winlose": {
		"condition": {"type": "choice", "label": "Condition", "options": ["score_reaches", "score_drops", "time_up"], "default": "score_reaches"},
		"value": {"type": "number", "label": "Value", "min": 0.0, "max": 1000.0, "step": 1.0, "default": 10},
	},
	"camera": {
		"mode": {"type": "choice", "label": "Mode", "options": ["follow", "fixed", "orbit", "cutscene"], "default": "follow"},
		"distance": {"type": "number", "label": "Distance", "min": 2.0, "max": 40.0, "step": 0.5, "default": 10.0},
		"height": {"type": "number", "label": "Height", "min": 0.0, "max": 40.0, "step": 0.5, "default": 6.0},
		"smooth": {"type": "bool", "label": "Smooth follow", "default": true},
		# screen shake: a small impulse on impact; the "juice" that makes hits land
		"shake": {"type": "bool", "label": "Shake on impact", "default": true},
		"shake_strength": {"type": "number", "label": "Shake strength", "min": 0.1, "max": 2.0, "step": 0.1, "default": 0.6},
	},
	"moving_platform": {
		"distance": {"type": "number", "label": "Travel", "min": 1.0, "max": 40.0, "step": 0.5, "default": 8.0},
		"speed": {"type": "number", "label": "Speed", "min": 0.5, "max": 20.0, "step": 0.5, "default": 3.0},
		"axis": {"type": "choice", "label": "Axis", "options": ["x", "y", "z"], "default": "x"},
	},
	"enemy_patrol": {
		"distance": {"type": "number", "label": "Patrol range", "min": 1.0, "max": 40.0, "step": 0.5, "default": 8.0},
		"speed": {"type": "number", "label": "Speed", "min": 0.5, "max": 20.0, "step": 0.5, "default": 3.0},
	},
	"hazard": {"damage": {"type": "number", "label": "Damage", "min": 1.0, "max": 10.0, "step": 1.0, "default": 1.0}},
	"checkpoint": {},
	"timer": {
		"seconds": {"type": "number", "label": "Seconds", "min": 1.0, "max": 300.0, "step": 1.0, "default": 20.0},
		"on_end": {"type": "choice", "label": "On end", "options": ["win", "lose", "nothing"], "default": "lose"},
		# Wave 4: per-node named timers — repeat mode + a start/reset gate
		"name": {"type": "text", "label": "Timer name", "default": "main"},
		"mode": {"type": "choice", "label": "Mode", "options": ["once", "repeat"], "default": "once"},
		"every": {"type": "number", "label": "Every N sec", "min": 0.5, "max": 60.0, "step": 0.5, "default": 3.0},
	},
	# --- Inventory brick: a named item counter (add/remove/has/count) --------
	"inventory": {
		"item": {"type": "text", "label": "Item", "default": "key"},
		"op": {"type": "choice", "label": "On event", "options": ["add", "remove", "check"], "default": "add"},
		"amount": {"type": "number", "label": "Amount", "min": 1.0, "max": 99.0, "step": 1.0, "default": 1},
		"need": {"type": "number", "label": "Need to pass", "min": 1.0, "max": 99.0, "step": 1.0, "default": 1},
	},
	# --- Level brick: a pattern string that paints a real tile level --------
	# '#' = solid ground, '.' = empty, '^' = spike hazard, '-' = one-way platform.
	# Rows separated by ';'. Kept tiny so it stays beginner-friendly.
	"level": {
		"pattern": {"type": "text", "label": "Map", "default": "................;................;....^^.........;################"},
		"tile": {"type": "number", "label": "Tile size", "min": 16.0, "max": 64.0, "step": 4.0, "default": 32.0},
		"theme": {"type": "choice", "label": "Theme", "options": ["grass", "stone", "candy"], "default": "grass"},
	},
	# --- Feature-registry brick params (src/features/*.gd) ---
	"trigger": {
		"shape": {"type": "choice", "label": "Shape", "options": ["box", "sphere"], "default": "box"},
		"size": {"type": "number", "label": "Size", "min": 0.5, "max": 40.0, "step": 0.5, "default": 4.0},
		"target": {"type": "choice", "label": "Triggers on", "options": ["player", "any", "enemy"], "default": "player"},
		"on_enter": {"type": "text", "label": "On enter, do", "default": "win"},
		"on_exit": {"type": "text", "label": "On exit, do", "default": ""},
		"visible_hint": {"type": "bool", "label": "Show the zone", "default": true},
		"once": {"type": "bool", "label": "Fire once", "default": true},
		"needs_var": {"type": "text", "label": "Only if this switch is on", "default": ""},
	},
	"collider": {
		"layer": {"type": "choice", "label": "What kind of thing", "options": ["world", "player", "enemy", "pickup", "hazard", "bullet", "decor"], "default": "world"},
		"collides_with": {"type": "text", "label": "What it can hit", "default": ""},
		"solid": {"type": "bool", "label": "Solid", "default": true},
		"size": {"type": "number", "label": "Size", "min": 0.5, "max": 40.0, "step": 0.5, "default": 4.0},
		"shape": {"type": "choice", "label": "Shape", "options": ["box", "sphere", "capsule"], "default": "box"},
		"position_y": {"type": "number", "label": "Height", "min": 0.0, "max": 20.0, "step": 0.5, "default": 1.0},
	},
	"save": {
		"mode": {"type": "choice", "label": "When", "options": ["manual", "auto", "on_quit", "on_level"], "default": "manual"},
		"slot": {"type": "number", "label": "Slot", "min": 1.0, "max": 9.0, "step": 1.0, "default": 1.0},
		"key": {"type": "choice", "label": "Save key", "options": ["none", "F5", "F9", "Space", "E"], "default": "F5"},
		"include_position": {"type": "bool", "label": "Save position", "default": true},
		"include_vars": {"type": "bool", "label": "Save variables", "default": true},
		"include_score": {"type": "bool", "label": "Save score", "default": true},
	},
	"checkpoint_save": {
		"slot": {"type": "number", "label": "Slot", "min": 1.0, "max": 9.0, "step": 1.0, "default": 1.0},
		"size": {"type": "number", "label": "Size", "min": 1.0, "max": 10.0, "step": 0.5, "default": 2.0},
		"once": {"type": "bool", "label": "Once only", "default": false},
	},
	"look": {
		"preset": {"type": "choice", "label": "Preset", "options": ["cinematic", "neon", "pastel", "noir", "warm", "cold", "space", "dreamy"], "default": "cinematic"},
		"bloom": {"type": "number", "label": "Bloom", "min": 0.0, "max": 2.0, "step": 0.05, "default": 0.35},
		"saturation": {"type": "number", "label": "Saturation", "min": 0.0, "max": 2.0, "step": 0.05, "default": 1.0},
		"contrast": {"type": "number", "label": "Contrast", "min": 0.5, "max": 2.0, "step": 0.05, "default": 1.0},
		"brightness": {"type": "number", "label": "Brightness", "min": 0.5, "max": 2.0, "step": 0.05, "default": 1.0},
		"vignette": {"type": "bool", "label": "Vignette", "default": true},
		"ssao": {"type": "bool", "label": "SSAO", "default": false},
		"fog": {"type": "bool", "label": "Fog", "default": false},
		"apply_2d": {"type": "bool", "label": "Tint 2D", "default": true},
	},
	"gamepad": {
		"enabled": {"type": "bool", "label": "Enabled", "default": true},
		"deadzone": {"type": "number", "label": "Stick dead zone", "min": 0.05, "max": 0.9, "step": 0.05, "default": 0.2},
		"vibrate": {"type": "bool", "label": "Rumble", "default": true},
		"vibrate_strength": {"type": "number", "label": "Rumble strength", "min": 0.0, "max": 1.0, "step": 0.1, "default": 0.5},
		"device": {"type": "number", "label": "Device", "min": 0.0, "max": 3.0, "step": 1.0, "default": 0.0},
		"invert_y": {"type": "bool", "label": "Invert Y", "default": false},
	},
	"screen": {
		"kind_of_screen": {"type": "choice", "label": "Screen", "options": ["main_menu", "pause", "game_over", "win", "credits", "settings"], "default": "main_menu"},
		"title": {"type": "text", "label": "Title", "default": "My Game"},
		"subtitle": {"type": "text", "label": "Subtitle", "default": ""},
		"background": {"type": "choice", "label": "Background", "options": ["dark", "blur", "none"], "default": "dark"},
		"transition": {"type": "choice", "label": "Transition", "options": ["fade", "slide", "none"], "default": "fade"},
		"show_on_start": {"type": "bool", "label": "Show on start", "default": true},
		"pause_game": {"type": "bool", "label": "Pause the game", "default": true},
	},
	"button": {
		"label": {"type": "text", "label": "Label", "default": "Play"},
		"action": {"type": "choice", "label": "When pressed", "options": ["start", "resume", "restart", "quit", "goto_screen", "toggle_var", "set_var"], "default": "start"},
		"target_screen": {"type": "text", "label": "Go to screen", "default": ""},
		"parent_screen": {"type": "text", "label": "On screen", "default": ""},
		"var_name": {"type": "text", "label": "Variable", "default": ""},
		"var_value": {"type": "number", "label": "Set to", "min": -100.0, "max": 100.0, "step": 1.0, "default": 1.0},
	},
	"undo": {
		"key": {"type": "choice", "label": "Undo key", "options": ["Z", "U", "Backspace"], "default": "Z"},
		"depth": {"type": "number", "label": "How many steps", "min": 1.0, "max": 10.0, "step": 1.0, "default": 5.0},
		"track_position": {"type": "bool", "label": "Undo position", "default": true},
		"track_vars": {"type": "bool", "label": "Undo variables", "default": true},
	},
	"pathfind": {
		"mode": {"type": "choice", "label": "Behavior", "options": ["chase", "guard", "patrol_points"], "default": "chase"},
		"target": {"type": "choice", "label": "Chases", "options": ["player", "marker", "wander"], "default": "player"},
		"speed": {"type": "number", "label": "Speed", "min": 0.5, "max": 20.0, "step": 0.5, "default": 4.0},
		"arrive_radius": {"type": "number", "label": "Stop at", "min": 0.5, "max": 10.0, "step": 0.5, "default": 1.5},
		"repath": {"type": "number", "label": "Rethink every", "min": 0.1, "max": 3.0, "step": 0.1, "default": 0.5},
		"guard_radius": {"type": "number", "label": "Guard radius", "min": 1.0, "max": 30.0, "step": 1.0, "default": 8.0},
		"avoid": {"type": "bool", "label": "Avoid others", "default": true},
		"draw_path": {"type": "bool", "label": "Show the path", "default": true},
		"points": {"type": "text", "label": "Patrol points", "default": ""},
	},
	"state": {
		"var_name": {"type": "text", "label": "State variable", "default": "enemy_state"},
		"initial": {"type": "text", "label": "Starts in", "default": "idle"},
		"states": {"type": "text", "label": "States", "default": "idle,patrol,chase,attack"},
		"transitions": {"type": "text", "label": "What happens next (idle : sees you : chase)", "default": ""},
		"owner": {"type": "choice", "label": "Applies to", "options": ["enemy", "player", "scene"], "default": "enemy"},
		"show_state": {"type": "bool", "label": "Show state name", "default": true},
	},
	"widget": {
		"widget_kind": {"type": "choice", "label": "Control", "options": ["button", "slider", "toggle", "dropdown"], "default": "button"},
		"label": {"type": "text", "label": "Label", "default": "Button"},
		"action": {"type": "choice", "label": "When used", "options": ["none", "set_var", "emit_event", "start_game", "quit_game"], "default": "none"},
		"var_name": {"type": "text", "label": "Variable", "default": ""},
		"var_value": {"type": "number", "label": "Set to", "min": -1000.0, "max": 1000.0, "step": 1.0, "default": 1.0},
		"options": {"type": "text", "label": "Choices", "default": ""},
		"min_value": {"type": "number", "label": "Min", "min": -1000.0, "max": 1000.0, "step": 1.0, "default": 0.0},
		"max_value": {"type": "number", "label": "Max", "min": -1000.0, "max": 1000.0, "step": 1.0, "default": 100.0},
		"step": {"type": "number", "label": "Step", "min": 0.01, "max": 100.0, "step": 0.01, "default": 1.0},
		"position": {"type": "choice", "label": "Where", "options": ["center", "top", "bottom", "left", "right"], "default": "center"},
		"width": {"type": "number", "label": "Width", "min": 60.0, "max": 800.0, "step": 20.0, "default": 220.0},
	},
	"watch": {
		"var_names": {"type": "text", "label": "Watch these", "default": "score,coins"},
		"position": {"type": "choice", "label": "Where", "options": ["top_left", "top_right", "bottom_left", "bottom_right"], "default": "top_left"},
		"editable": {"type": "bool", "label": "Let me type new values", "default": true},
		"show_changes": {"type": "bool", "label": "Flash on change", "default": true},
		"font_size": {"type": "number", "label": "Text size", "min": 10.0, "max": 48.0, "step": 2.0, "default": 18.0},
	},
	"error_panel": {
		"show_on_start": {"type": "bool", "label": "Show at start", "default": false},
		"auto_open": {"type": "bool", "label": "Open when there are problems", "default": true},
		"detail_level": {"type": "choice", "label": "How much to explain", "options": ["short", "full"], "default": "short"},
	},
	"light": {
		"kind_of_light": {"type": "choice", "label": "Lamp type", "options": ["point", "directional"], "default": "point"},
		"color_name": {"type": "choice", "label": "Color", "options": ["gold", "red", "blue", "green", "warm", "cool", "purple", "white"], "default": "warm"},
		"intensity": {"type": "number", "label": "Brightness", "min": 0.0, "max": 8.0, "step": 0.1, "default": 1.5},
		"range": {"type": "number", "label": "Reach", "min": 32.0, "max": 1200.0, "step": 8.0, "default": 320.0},
		"shadows": {"type": "bool", "label": "Cast shadows", "default": true},
		"shadow_softness": {"type": "number", "label": "Softness", "min": 0.0, "max": 4.0, "step": 0.2, "default": 1.0},
		"flicker": {"type": "bool", "label": "Flicker", "default": false},
		"flicker_speed": {"type": "number", "label": "Flicker speed", "min": 0.5, "max": 12.0, "step": 0.5, "default": 3.0},
	},
	"occluder": {
		"shape": {"type": "choice", "label": "Shape", "options": ["box", "circle"], "default": "box"},
		"width": {"type": "number", "label": "Width", "min": 8.0, "max": 512.0, "step": 4.0, "default": 96.0},
		"height": {"type": "number", "label": "Height", "min": 8.0, "max": 512.0, "step": 4.0, "default": 96.0},
	},
	"blueprint_def": {
		"name": {"type": "text", "label": "Name it", "default": "Coin"},
		"description": {"type": "text", "label": "What is it", "default": ""},
	},
	"blueprint": {
		"blueprint_name": {"type": "text", "label": "Which blueprint", "default": "Coin"},
		"count": {"type": "number", "label": "How many", "min": 1.0, "max": 50.0, "step": 1.0, "default": 1.0},
		"spread": {"type": "number", "label": "Space apart", "min": 1.0, "max": 200.0, "step": 1.0, "default": 12.0},
		"layout": {"type": "choice", "label": "Arrange", "options": ["row", "column", "grid", "ring"], "default": "row"},
		"rows": {"type": "number", "label": "Rows", "min": 1.0, "max": 10.0, "step": 1.0, "default": 3.0},
		"overrides": {"type": "text", "label": "Change these", "default": ""},
	},
	"attach": {
		"child_brick": {"type": "text", "label": "What to attach", "default": ""},
		"parent_brick": {"type": "text", "label": "Attach it to", "default": ""},
		"inherit_rotation": {"type": "bool", "label": "Turn with it", "default": true},
		"follow_position": {"type": "bool", "label": "Move with it", "default": true},
		"visible": {"type": "bool", "label": "Visible", "default": true},
	},
	"rigid": {
		"model": {"type": "choice", "label": "Shape", "options": ["box", "sphere", "capsule"], "default": "box"},
		"mass": {"type": "number", "label": "Heaviness", "min": 0.1, "max": 100.0, "step": 0.1, "default": 1.0},
		"gravity_scale": {"type": "number", "label": "Gravity", "min": -2.0, "max": 4.0, "step": 0.1, "default": 1.0},
		"bounciness": {"type": "number", "label": "Bounciness", "min": 0.0, "max": 1.0, "step": 0.05, "default": 0.2},
		"friction": {"type": "number", "label": "Friction", "min": 0.0, "max": 1.0, "step": 0.05, "default": 0.6},
		"linear_damping": {"type": "number", "label": "Air drag", "min": 0.0, "max": 5.0, "step": 0.1, "default": 0.1},
		"angular_damping": {"type": "number", "label": "Spin drag", "min": 0.0, "max": 5.0, "step": 0.1, "default": 0.1},
		"freeze": {"type": "choice", "label": "Lock", "options": ["none", "rotation", "position", "both"], "default": "none"},
		"size": {"type": "number", "label": "Size", "min": 0.2, "max": 6.0, "step": 0.2, "default": 1.0},
		"color_name": {"type": "choice", "label": "Color", "options": ["gold", "red", "blue", "green", "gray", "brown", "white"], "default": "brown"},
		"start_asleep": {"type": "bool", "label": "Start still", "default": true},
	},
	"audio": {
		"sound_kind": {"type": "choice", "label": "Sound", "options": ["coin", "jump", "hit", "hurt", "win", "lose", "click", "pickup", "powerup", "blast", "select", "theme"], "default": "coin"},
		"bus": {"type": "choice", "label": "Mixer", "options": ["master", "music", "sfx", "ui", "ambient"], "default": "sfx"},
		"volume_db": {"type": "number", "label": "Loudness", "min": -60.0, "max": 6.0, "step": 1.0, "default": 0.0},
		"loop": {"type": "bool", "label": "Loop it", "default": false},
		"play_on_start": {"type": "bool", "label": "Play at start", "default": true},
	},
	"perceive": {
		"sight_range": {"type": "number", "label": "Can see", "min": 2.0, "max": 60.0, "step": 1.0, "default": 12.0},
		"sight_angle": {"type": "number", "label": "Field of view", "min": 20.0, "max": 360.0, "step": 5.0, "default": 90.0},
		"hearing_range": {"type": "number", "label": "Can hear", "min": 0.0, "max": 30.0, "step": 1.0, "default": 6.0},
		"needs_line_of_sight": {"type": "bool", "label": "Walls block sight", "default": true},
		"memory_seconds": {"type": "number", "label": "Remembers for", "min": 0.0, "max": 20.0, "step": 1.0, "default": 5.0},
		"show_cone": {"type": "bool", "label": "Show its vision", "default": true},
		"alert_var": {"type": "text", "label": "Set this when spotted", "default": "enemy_alert"},
		"on_notice": {"type": "choice", "label": "When it sees you", "options": ["none", "chase", "emit_event", "set_var"], "default": "emit_event"},
		"event_name": {"type": "text", "label": "Send this event", "default": "player_spotted"},
	},
	"style": {
		"preset": {"type": "choice", "label": "Look", "options": ["clean", "playful", "retro", "neon", "minimal", "dark"], "default": "clean"},
		"accent": {"type": "choice", "label": "Accent color", "options": ["gold", "red", "blue", "green", "purple", "white"], "default": "gold"},
		"font_size": {"type": "number", "label": "Text size", "min": 12.0, "max": 48.0, "step": 2.0, "default": 20.0},
		"corner_radius": {"type": "number", "label": "Rounded corners", "min": 0.0, "max": 24.0, "step": 2.0, "default": 8.0},
		"transition": {"type": "choice", "label": "Screen change", "options": ["fade", "slide", "none"], "default": "fade"},
		"transition_seconds": {"type": "number", "label": "Change speed", "min": 0.05, "max": 2.0, "step": 0.05, "default": 0.35},
	},
	"hud": {
		"widget": {"type": "choice", "label": "Show", "options": ["bar", "counter", "hearts", "minimap", "inventory", "text"], "default": "bar"},
		"var_name": {"type": "text", "label": "Reads this", "default": "health"},
		"max_var": {"type": "text", "label": "Maximum comes from", "default": "max_health"},
		"max_value": {"type": "number", "label": "Or this number", "min": 1.0, "max": 9999.0, "step": 1.0, "default": 100.0},
		"position": {"type": "choice", "label": "Where", "options": ["top_left", "top_right", "bottom_left", "bottom_right", "center"], "default": "top_left"},
		"color_name": {"type": "choice", "label": "Color", "options": ["gold", "red", "blue", "green", "purple", "white"], "default": "red"},
		"label": {"type": "text", "label": "Caption", "default": ""},
		"show_percent": {"type": "bool", "label": "Show the maximum too", "default": false},
	},
	"follow": {
		"target": {"type": "text", "label": "Target", "default": "Player"},
		"speed": {"type": "number", "label": "Speed", "min": 1.0, "max": 40.0, "step": 0.5, "default": 8.0},
	},
	"destroy": {"on": {"type": "choice", "label": "Destroy on", "options": ["touch", "timer", "leave_screen"], "default": "touch"}},
	"sound": {
		"kind": {"type": "choice", "label": "Sound", "options": ["coin", "jump", "hit", "win", "lose", "click"], "default": "coin"},
		"volume": {"type": "number", "label": "Volume", "min": 0.0, "max": 1.0, "step": 0.1, "default": 0.7},
	},
	"particles": {
		"effect": {"type": "choice", "label": "Effect", "options": ["sparkle", "smoke", "fire", "snow"], "default": "sparkle"},
		"amount": {"type": "number", "label": "Amount", "min": 4.0, "max": 64.0, "step": 1.0, "default": 16.0},
		"color": {"type": "choice", "label": "Color", "options": ["gold", "red", "blue", "green", "white"], "default": "gold"},
		# Wave 4: visual particle editor — the GPUParticles2D properties a
		# beginner actually tweaks (cone angle, force, gravity, lifetime).
		"cone": {"type": "number", "label": "Spray cone", "min": 0.0, "max": 360.0, "step": 15.0, "default": 360.0},
		"force": {"type": "number", "label": "Force", "min": 0.0, "max": 20.0, "step": 0.5, "default": 5.0},
		"life": {"type": "number", "label": "Lifetime", "min": 0.2, "max": 5.0, "step": 0.1, "default": 0.8},
		"pgravity": {"type": "number", "label": "Gravity", "min": -20.0, "max": 20.0, "step": 1.0, "default": 0.0},
	},
	"animation": {
		"motion": {"type": "choice", "label": "Motion", "options": ["spin", "bob", "pulse"], "default": "spin"},
		"speed": {"type": "number", "label": "Speed", "min": 0.5, "max": 10.0, "step": 0.5, "default": 2.0},
	},
	"health": {
		"max": {"type": "number", "label": "Max health", "min": 1.0, "max": 20.0, "step": 1.0, "default": 3.0},
		"damage": {"type": "number", "label": "Damage", "min": 1.0, "max": 10.0, "step": 1.0, "default": 1.0},
	},
	# --- Variable brick: a named value with a scope and an operation ---
	"variable": {
		"name": {"type": "text", "label": "Name", "default": "coins"},
		"scope": {"type": "choice", "label": "Who remembers it", "options": ["game", "player"], "default": "game"},
		"type": {"type": "choice", "label": "Number or yes/no", "options": ["number", "bool"], "default": "number"},
		"op": {"type": "choice", "label": "On event", "options": ["add", "set", "toggle"], "default": "add"},
		"amount": {"type": "number", "label": "Amount", "min": -100.0, "max": 100.0, "step": 1.0, "default": 1},
		"value": {"type": "number", "label": "Set to", "min": -1000.0, "max": 1000.0, "step": 1.0, "default": 0},
	},
	# --- Rule brick: if <condition> then <actions>. The structural enabler. ---
	"rule": {
		# condition side
		"cond_source": {"type": "choice", "label": "If", "options": ["variable", "key", "timer", "collided"], "default": "variable"},
		"cond_var": {"type": "text", "label": "Var", "default": "coins"},
		"cond_op": {"type": "choice", "label": "Compare", "options": [">=", "==", "<=", "!=", ">", "<"], "default": ">="},
		"cond_value": {"type": "number", "label": "To", "min": -1000.0, "max": 1000.0, "step": 1.0, "default": 3},
		"cond_key": {"type": "choice", "label": "Key", "options": ["Space", "E", "F", "Enter", "Shift"], "default": "Space"},
		# action side (comma-separated verbs the compiler expands to GameState calls)
		"actions": {"type": "text", "label": "Then do", "default": "win"},
	},
	# --- Platform brick: a solid surface with tunable physics ---------------
	"platform": {
		"preset": {"type": "choice", "label": "Surface", "options": ["normal", "ice", "trampoline"], "default": "normal"},
		"one_way": {"type": "bool", "label": "Jump-through", "default": false},
		"bounce": {"type": "number", "label": "Bounce", "min": 0.0, "max": 1.0, "step": 0.05, "default": 0.0},
		"friction": {"type": "number", "label": "Friction", "min": 0.0, "max": 1.0, "step": 0.05, "default": 1.0},
		"width": {"type": "number", "label": "Width", "min": 2.0, "max": 40.0, "step": 1.0, "default": 8.0},
		"height": {"type": "number", "label": "Height", "min": 0.5, "max": 4.0, "step": 0.5, "default": 1.0},
	},
	# --- Background brick: parallax layers (procedural, no assets) ----------
	"background": {
		"layers": {"type": "number", "label": "Layers", "min": 1.0, "max": 3.0, "step": 1.0, "default": 2.0},
		"theme": {"type": "choice", "label": "Theme", "options": ["dusk", "forest", "night", "candy"], "default": "dusk"},
	},
	# --- Sky/Environment brick: one themed preset colors the whole scene ----
	"sky": {
		"preset": {"type": "choice", "label": "Preset", "options": ["day", "sunset", "night", "foggy", "space"], "default": "day"},
	},
	# --- Door/Portal brick: connect two levels ------------------------------
	"door": {
		"target_level": {"type": "text", "label": "Go to level", "default": "2"},
		"target_entry": {"type": "text", "label": "Entry marker", "default": "start"},
		"transition": {"type": "choice", "label": "Transition", "options": ["instant", "fade"], "default": "fade"},
		"needs_var": {"type": "text", "label": "Only if this switch is on", "default": ""},
	},
	# --- Entry Point brick: a named spawn marker ----------------------------
	"entry": {
		"marker": {"type": "text", "label": "Marker name", "default": "start"},
	},
}

# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

static func create(kind: String, title: String = "", user_comment: String = "") -> Dictionary:
	# Accept both universal kinds (KIND) and the genre-pack kinds whose ports /
	# params are built in the match below. Genre kinds live in the registry at
	# runtime, but create() is static and must stay callable offline (tests, AI
	# edits), so we list the known genre kinds here too.
	var genre_kinds := ["moving_platform", "enemy_patrol", "hazard", "checkpoint",
		"timer", "follow", "destroy", "npc", "quest", "inventory", "bullet", "ammo"]
	if not KIND.has(kind) and not (kind in genre_kinds):
		push_error("BrickRef.create: unknown kind '%s'" % kind)
		return {}
	var meta: Dictionary = KIND.get(kind, {"label": kind.capitalize(), "icon": "🧩"})
	var b := {
		"id": _new_id(kind),
		"kind": kind,
		"title": title if not title.is_empty() else str(meta["label"]),
		"comment": user_comment,          # plain-English note from the user -> fed to AI
		"inputs": [],                     # list of {"name":String,"type":PortType}
		"outputs": [],                    # list of {"name":String,"type":PortType}
		"params": {},                     # kind-specific settings (speed, amount, model...)
		"connections": [],                # list of {"from_out":int,"to_brick":String,"to_in":int}
	}
	# default ports per kind
	match kind:
		"spawn":
			b["inputs"] = [{"name": "on_start", "type": PortType.EVENT}]
			b["outputs"] = [{"name": "entity", "type": PortType.FLOW}]
			b["params"] = {"model": "player", "position": [0, 1, 0], "dimension": "3d",
				"key_left": "A", "key_right": "D", "key_jump": "Space",
				"key_up": "W", "key_down": "S",
				"coyote_time": 0.1, "jump_buffer": 0.12, "jump_cut": 0.45, "fall_gravity": 1.7}
		"move":
			b["inputs"] = [{"name": "entity", "type": PortType.FLOW}, {"name": "on_tick", "type": PortType.EVENT}]
			b["outputs"] = [{"name": "moved", "type": PortType.FLOW}]
			b["params"] = {"style": "platformer", "speed": 8.0, "jump": 12.0, "gravity": 30.0}
		"collide":
			b["inputs"] = [{"name": "entity", "type": PortType.FLOW}]
			b["outputs"] = [{"name": "on_touch", "type": PortType.EVENT}]
			b["params"] = {"with": "coin", "action": "collect"}
		"score":
			b["inputs"] = [{"name": "trigger", "type": PortType.EVENT}]
			b["outputs"] = [{"name": "done", "type": PortType.FLOW}]
			b["params"] = {"variable": "score", "op": "add", "amount": 1}
		"winlose":
			b["inputs"] = [{"name": "trigger", "type": PortType.EVENT}, {"name": "threshold", "type": PortType.VALUE}]
			b["outputs"] = [{"name": "game_over", "type": PortType.FLOW}]
			b["params"] = {"condition": "score_reaches", "value": 10}
		"camera":
			b["inputs"] = [{"name": "target", "type": PortType.FLOW}]
			b["outputs"] = []
			b["params"] = {"mode": "follow", "distance": 10.0, "height": 6.0, "smooth": true,
				"shake": true, "shake_strength": 0.6}
		"timer":
			b["inputs"] = [{"name": "on_start", "type": PortType.EVENT}]
			b["outputs"] = [{"name": "on_end", "type": PortType.EVENT}]
			b["params"] = {"seconds": 20.0, "on_end": "lose"}
		"moving_platform":
			b["inputs"] = [{"name": "entity", "type": PortType.FLOW}]
			b["outputs"] = [{"name": "moved", "type": PortType.FLOW}]
			b["params"] = {"distance": 8.0, "speed": 3.0, "axis": "x"}
		"enemy_patrol":
			b["inputs"] = [{"name": "entity", "type": PortType.FLOW}]
			b["outputs"] = [{"name": "on_touch", "type": PortType.EVENT}]
			b["params"] = {"distance": 8.0, "speed": 3.0}
		"hazard":
			b["inputs"] = [{"name": "entity", "type": PortType.FLOW}]
			b["outputs"] = [{"name": "on_touch", "type": PortType.EVENT}]
			b["params"] = {"damage": 1.0}
		"checkpoint":
			b["inputs"] = [{"name": "entity", "type": PortType.FLOW}]
			b["outputs"] = [{"name": "reached", "type": PortType.FLOW}]
			b["params"] = {}
		"follow":
			b["inputs"] = [{"name": "entity", "type": PortType.FLOW}]
			b["outputs"] = [{"name": "followed", "type": PortType.FLOW}]
			b["params"] = {"target": "Player", "speed": 8.0}
		"destroy":
			b["inputs"] = [{"name": "entity", "type": PortType.FLOW}]
			b["outputs"] = [{"name": "destroyed", "type": PortType.EVENT}]
			b["params"] = {"on": "touch"}
		"sound":
			b["inputs"] = [{"name": "trigger", "type": PortType.EVENT}]
			b["outputs"] = []
			b["params"] = {"kind": "coin", "volume": 0.7}
		"particles":
			b["inputs"] = [{"name": "entity", "type": PortType.FLOW}]
			b["outputs"] = []
			b["params"] = {"effect": "sparkle", "amount": 16.0, "color": "gold"}
		"animation":
			b["inputs"] = [{"name": "entity", "type": PortType.FLOW}]
			b["outputs"] = []
			b["params"] = {"motion": "spin", "speed": 2.0}
		"health":
			b["inputs"] = [{"name": "on_hit", "type": PortType.EVENT}]
			b["outputs"] = [{"name": "current", "type": PortType.VALUE}]
			b["params"] = {"max": 3.0, "damage": 1.0}
		"variable":
			b["inputs"] = [{"name": "on_event", "type": PortType.EVENT}]
			b["outputs"] = [{"name": "value", "type": PortType.VALUE}]
			b["params"] = {"name": "coins", "scope": "game", "type": "number",
				"op": "add", "amount": 1, "value": 0}
		"rule":
			b["inputs"] = [{"name": "on_event", "type": PortType.EVENT}]
			b["outputs"] = [{"name": "action", "type": PortType.EVENT}]
			b["params"] = {"cond_source": "variable", "cond_var": "coins",
				"cond_op": ">=", "cond_value": 3, "cond_key": "Space",
				"actions": "win"}
		"platform":
			b["inputs"] = [{"name": "entity", "type": PortType.FLOW}]
			b["outputs"] = [{"name": "surface", "type": PortType.FLOW}]
			b["params"] = {"preset": "normal", "one_way": false, "bounce": 0.0,
				"friction": 1.0, "width": 8.0, "height": 1.0}
		"background":
			b["inputs"] = [{"name": "scene", "type": PortType.FLOW}]
			b["outputs"] = []
			b["params"] = {"layers": 2.0, "theme": "dusk"}
		"sky":
			b["inputs"] = [{"name": "scene", "type": PortType.FLOW}]
			b["outputs"] = []
			b["params"] = {"preset": "day"}
		"door":
			b["inputs"] = [{"name": "on_touch", "type": PortType.EVENT}]
			b["outputs"] = [{"name": "go", "type": PortType.FLOW}]
			b["params"] = {"target_level": "2", "target_entry": "start",
				"transition": "fade", "needs_var": ""}
		"entry":
			b["inputs"] = [{"name": "scene", "type": PortType.FLOW}]
			b["outputs"] = []
			b["params"] = {"marker": "start"}
		"inventory":
			b["inputs"] = [{"name": "on_event", "type": PortType.EVENT}]
			b["outputs"] = [{"name": "count", "type": PortType.VALUE}]
			b["params"] = {"item": "key", "op": "add", "amount": 1, "need": 1}
		"level":
			b["inputs"] = [{"name": "scene", "type": PortType.FLOW}]
			b["outputs"] = []
			b["params"] = {"pattern": "................;................;....^^.........;################",
				"tile": 32.0, "theme": "grass"}
		"trigger":
			b["inputs"] = [{"name": "on_event", "type": PortType.EVENT}]
			b["outputs"] = [{"name": "fired", "type": PortType.EVENT}]
			b["params"] = {"shape": "box", "size": 4.0, "target": "player",
				"on_enter": "win", "on_exit": "", "visible_hint": true,
				"once": true, "needs_var": ""}
		"collider":
			b["inputs"] = [{"name": "scene", "type": PortType.FLOW}]
			b["outputs"] = [{"name": "solid", "type": PortType.FLOW}]
			b["params"] = {"layer": "world", "collides_with": "", "solid": true,
				"size": 4.0, "shape": "box", "position_y": 1.0}
		"save":
			b["inputs"] = [{"name": "on_event", "type": PortType.EVENT}]
			b["outputs"] = []
			b["params"] = {"mode": "manual", "slot": 1.0, "key": "F5",
				"include_position": true, "include_vars": true, "include_score": true}
		"checkpoint_save":
			b["inputs"] = [{"name": "scene", "type": PortType.FLOW}]
			b["outputs"] = [{"name": "saved", "type": PortType.FLOW}]
			b["params"] = {"slot": 1.0, "size": 2.0, "once": false}
		"look":
			b["inputs"] = [{"name": "scene", "type": PortType.FLOW}]
			b["outputs"] = []
			b["params"] = {"preset": "cinematic", "bloom": 0.35, "saturation": 1.0,
				"contrast": 1.0, "brightness": 1.0, "vignette": true, "ssao": false,
				"fog": false, "apply_2d": true}
		"gamepad":
			b["inputs"] = [{"name": "scene", "type": PortType.FLOW}]
			b["outputs"] = []
			b["params"] = {"enabled": true, "deadzone": 0.2, "vibrate": true,
				"vibrate_strength": 0.5, "device": 0.0, "invert_y": false}
		"screen":
			b["inputs"] = [{"name": "scene", "type": PortType.FLOW}]
			b["outputs"] = [{"name": "shown", "type": PortType.EVENT}]
			b["params"] = {"kind_of_screen": "main_menu", "title": "My Game",
				"subtitle": "", "background": "dark", "transition": "fade",
				"show_on_start": true, "pause_game": true}
		"button":
			b["inputs"] = [{"name": "on_click", "type": PortType.EVENT}]
			b["outputs"] = []
			b["params"] = {"label": "Play", "action": "start", "target_screen": "",
				"parent_screen": "", "var_name": "", "var_value": 1.0}
		"undo":
			b["inputs"] = [{"name": "scene", "type": PortType.FLOW}]
			b["outputs"] = []
			b["params"] = {"key": "Z", "depth": 5.0, "track_position": true,
				"track_vars": true}
		"pathfind":
			b["inputs"] = [{"name": "scene", "type": PortType.FLOW}]
			b["outputs"] = [{"name": "reached", "type": PortType.EVENT}]
			b["params"] = {"mode": "chase", "target": "player", "speed": 4.0,
				"arrive_radius": 1.5, "repath": 0.5, "guard_radius": 8.0,
				"avoid": true, "draw_path": true, "points": ""}
		"state":
			b["inputs"] = [{"name": "scene", "type": PortType.FLOW}]
			b["outputs"] = [{"name": "changed", "type": PortType.EVENT}]
			b["params"] = {"var_name": "enemy_state", "initial": "idle",
				"states": "idle,patrol,chase,attack", "transitions": "",
				"owner": "enemy", "show_state": true}
		"widget":
			b["inputs"] = [{"name": "scene", "type": PortType.FLOW}]
			b["outputs"] = []
			b["params"] = {"widget_kind": "button", "label": "Button",
				"action": "none", "var_name": "", "var_value": 1.0,
				"options": "", "min_value": 0.0, "max_value": 100.0,
				"step": 1.0, "position": "center", "width": 220.0}
		"watch":
			b["inputs"] = [{"name": "scene", "type": PortType.FLOW}]
			b["outputs"] = []
			b["params"] = {"var_names": "score,coins", "position": "top_left",
				"editable": true, "show_changes": true, "font_size": 18.0}
		"error_panel":
			b["inputs"] = [{"name": "scene", "type": PortType.FLOW}]
			b["outputs"] = []
			b["params"] = {"show_on_start": false, "auto_open": true,
				"detail_level": "short"}
		"light":
			b["inputs"] = [{"name": "scene", "type": PortType.FLOW}]
			b["outputs"] = []
			b["params"] = {"kind_of_light": "point", "color_name": "warm",
				"intensity": 1.5, "range": 320.0, "shadows": true,
				"shadow_softness": 1.0, "flicker": false, "flicker_speed": 3.0}
		"occluder":
			b["inputs"] = [{"name": "scene", "type": PortType.FLOW}]
			b["outputs"] = []
			b["params"] = {"shape": "box", "width": 96.0, "height": 96.0}
		"blueprint_def":
			b["inputs"] = [{"name": "templates", "type": PortType.FLOW}]
			b["outputs"] = [{"name": "defined", "type": PortType.EVENT}]
			b["params"] = {"name": "Coin", "description": ""}
		"blueprint":
			b["inputs"] = [{"name": "scene", "type": PortType.FLOW}]
			b["outputs"] = []
			b["params"] = {"blueprint_name": "Coin", "count": 1.0,
				"spread": 12.0, "layout": "row", "rows": 3.0, "overrides": ""}
		"attach":
			b["inputs"] = [{"name": "child", "type": PortType.FLOW}]
			b["outputs"] = []
			b["params"] = {"child_brick": "", "parent_brick": "",
				"inherit_rotation": true, "follow_position": true, "visible": true}
		"rigid":
			b["inputs"] = [{"name": "scene", "type": PortType.FLOW}]
			b["outputs"] = []
			b["params"] = {"model": "box", "mass": 1.0, "gravity_scale": 1.0,
				"bounciness": 0.2, "friction": 0.6, "linear_damping": 0.1,
				"angular_damping": 0.1, "freeze": "none", "size": 1.0,
				"color_name": "brown", "start_asleep": true}
		"audio":
			b["inputs"] = [{"name": "scene", "type": PortType.FLOW}]
			b["outputs"] = []
			b["params"] = {"sound_kind": "coin", "bus": "sfx",
				"volume_db": 0.0, "loop": false, "play_on_start": true}
		"perceive":
			b["inputs"] = [{"name": "scene", "type": PortType.FLOW}]
			b["outputs"] = [{"name": "spotted", "type": PortType.EVENT}]
			b["params"] = {"sight_range": 12.0, "sight_angle": 90.0,
				"hearing_range": 6.0, "needs_line_of_sight": true,
				"memory_seconds": 5.0, "show_cone": true,
				"alert_var": "enemy_alert", "on_notice": "emit_event",
				"event_name": "player_spotted"}
		"style":
			b["inputs"] = [{"name": "scene", "type": PortType.FLOW}]
			b["outputs"] = []
			b["params"] = {"preset": "clean", "accent": "gold",
				"font_size": 20.0, "corner_radius": 8.0,
				"transition": "fade", "transition_seconds": 0.35}
		"hud":
			b["inputs"] = [{"name": "scene", "type": PortType.FLOW}]
			b["outputs"] = []
			b["params"] = {"widget": "bar", "var_name": "health",
				"max_var": "max_health", "max_value": 100.0,
				"position": "top_left", "color_name": "red",
				"label": "", "show_percent": false}
	return b

# ---------------------------------------------------------------------------
# Connection validation — the "typed ports" rule. Returns true when legal.
# Incompatible ports simply don't light up in the UI; nothing throws.
# ---------------------------------------------------------------------------
static func can_connect(from_brick: Dictionary, from_port: int, to_brick: Dictionary, to_port: int) -> bool:
	if from_brick.is_empty() or to_brick.is_empty():
		return false
	# no self-loops
	if id_of(from_brick) == id_of(to_brick) and not id_of(from_brick).is_empty():
		return false
	# The visual graph exposes ONE port per side (slot 0). The spec's rule is
	# "softly guided, hint never hard-block", so we accept any non-self link
	# here and let the compiler interpret it. (The old strict FLOW/EVENT type
	# check silently rejected most real drags, which broke wiring.)
	if from_port != 0 or to_port != 0:
		# still bounds-check against declared ports when indices are used
		var from_outs := _ports_of(from_brick, "outputs")
		var to_ins := _ports_of(to_brick, "inputs")
		if from_port < 0 or from_port >= max(from_outs.size(), 1):
			return false
		if to_port < 0 or to_port >= max(to_ins.size(), 1):
			return false
	return true

## Safe port-list accessor — an AI brick may omit inputs/outputs entirely.
static func _ports_of(brick: Dictionary, key: String) -> Array:
	var v = brick.get(key)
	if not v is Array:
		return []
	var out: Array = []
	for p in v:
		if p is Dictionary:
			out.append(p)
	return out

## Safe id accessor — the AI may omit or mistype it.
static func id_of(brick: Dictionary) -> String:
	var i = brick.get("id")
	return str(i) if i != null else ""

# ---------------------------------------------------------------------------
# Serialization — bricks are plain data, so JSON round-trips exactly.
# PortType ints are stable across saves.
# ---------------------------------------------------------------------------
static func to_json(brick: Dictionary) -> String:
	return JSON.stringify(brick, "\t")

static func from_json(text: String) -> Dictionary:
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("BrickRef.from_json: not an object")
		return {}
	return parsed

# ---------------------------------------------------------------------------
static func _new_id(kind: String) -> String:
	return "%s_%d_%d" % [kind, Time.get_ticks_msec(), randi() % 100000]
