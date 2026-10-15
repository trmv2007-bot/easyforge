extends RefCounted
## BrickDocs — everything a *human* needs to know about a brick, in one place.
##
## Why this file exists: the plain-English descriptions, the beginner synonyms,
## the palette grouping and the per-setting explanations used to be scattered
## across main.gd (BRICK_HELP, SEARCH_KEYWORDS, _sections_for) and brick.gd
## (PARAM_SCHEMA labels). Three consequences, all bad for beginners:
##   - the same brick was explained differently in the palette, the inspector
##     and the help dialog, because each had its own copy of the text;
##   - a brick added by a feature module had no docs at all until someone
##     remembered to edit main.gd;
##   - the IR label ("pathfind") leaked into the UI as the display name, so the
##     palette said "Pathfind" to a 12-year-old.
## Here the IR stays stable (BrickRef.KIND keeps its `label`, the AI prompt keeps
## its kind ids) and the *human* layer lives in one table that the palette, the
## inspector, the canvas and the in-app Manual all read.
##
## Fields per kind (all optional except `help`):
##   name    how the brick is called in the UI. Plain words, no engine jargon.
##   cat     which palette group it belongs to (see CATEGORIES).
##   tier    "core"     the starter set — shown first, always visible
##           "standard normal bricks — visible by default
##           "advanced hidden until "Show every brick" is ticked (search finds them anyway)
##   icon    optional glyph override (the registry icon is used when absent)
##   help    one line: what it does, written for someone who has never made a game
##   use     one line: the wiring you usually see, so the canvas isn't a puzzle
##   say     longer explanation for the Manual (falls back to help)
##   syn     words a beginner types when they want this brick ("bad guy", "die")
##   params  key -> plain explanation of that setting (shown as tooltips + Manual)
##   related kinds that are usually used together

class_name BrickDocs

# ---------------------------------------------------------------------------
# Palette groups, in the order a beginner should meet them.
# ---------------------------------------------------------------------------
const CATEGORIES := [
	{"id": "objects", "label": "Things in the game", "hint": "Put the world together: player, ground, coins, enemies."},
	{"id": "moving", "label": "Movement & controls", "hint": "Make things walk, jump, fly, or follow the player."},
	{"id": "rules", "label": "Rules, score & winning", "hint": "What happens when, and how the game ends."},
	{"id": "feel", "label": "Look & sound", "hint": "Colours, lights, music and effects — the polish."},
	{"id": "screens", "label": "Menus & screen UI", "hint": "Title screens, buttons, health bars, settings."},
	{"id": "smart", "label": "Smart behaviour", "hint": "Enemies that see, path-find and change mode."},
	{"id": "tools", "label": "Reuse, save & testing", "hint": "Prefabs, save files, live numbers, problem lists."},
]

const TIER_CORE := "core"
const TIER_STANDARD := "standard"
const TIER_ADVANCED := "advanced"

# ---------------------------------------------------------------------------
# The table. One entry per brick kind in the palette (50 as of this writing).
# ---------------------------------------------------------------------------
const DOCS := {
	# ==================== Things in the game ====================
	"spawn": {
		"name": "Character / Item", "cat": "objects", "tier": TIER_CORE, "icon": "🧍",
		"help": "Puts something into the game when it starts: you, an enemy, a coin.",
		"use": "Start here — almost every game has at least one of these.",
		"say": "The brick that creates a thing in the world. Pick what it is (the player you control, an enemy, a coin, a crate), where it appears, and which keys drive it if it is the player. Everything else — moving it, scoring for it, destroying it — is wired FROM this brick.",
		"syn": ["player", "character", "hero", "guy", "create", "appear", "start here", "me", "person", "object", "coin", "thing"],
		"params": {
			"model": "Which shape and colour this thing gets. Pick from the built-in art library — anything the compiler does not know falls back to a simple block, so this can never break your game.",
			"position_y": "How high above the floor it starts.",
			"key_left": "The key that moves this thing left.",
			"key_right": "The key that moves this thing right.",
			"key_jump": "The key that makes it jump.",
			"key_up": "The key for up, used by top-down and flying movement.",
			"key_down": "The key for down, used by top-down movement.",
			"coyote_time": "Forgiveness after leaving a ledge: you can still jump for this long after running off the edge. Feels better; 0 makes jumps feel broken.",
			"jump_buffer": "Forgiveness before landing: pressing jump this early still counts as a jump as soon as you touch the ground.",
			"jump_cut": "How much a SHORT tap of the jump key is worth. Lower means tapping gives a small hop and holding gives a full jump.",
			"fall_gravity": "How much faster you fall than you rise. Slightly above 1 makes movement feel snappy instead of floaty.",
		},
		"related": ["move", "collide", "camera", "health"],
	},
	"platform": {
		"name": "Solid Platform", "cat": "objects", "tier": TIER_STANDARD,
		"help": "A floor or ledge you can stand on — ice, trampoline or plain.",
		"use": "Add ground first, then spawn the player above it.",
		"syn": ["ground", "floor", "ledge", "wall", "solid", "ice", "bouncy", "trampoline", "surface"],
		"params": {
			"preset": "The feel of the surface: plain, slippery ice, or bouncy trampoline.",
			"one_way": "If on, you can jump up through it and land on top — classic platformer thin floor.",
			"bounce": "How much speed you keep when you land on it. 0 = flat stop, 1 = you bounce back as high as you fell from.",
			"friction": "How much it slows you while standing on it. Low means slippery.",
			"width": "How wide the platform is.",
			"height": "How tall (thick) the platform is.",
		},
		"related": ["level", "spawn", "moving_platform"],
	},
	"level": {
		"name": "Level Layout", "cat": "objects", "tier": TIER_STANDARD,
		"help": "Builds a whole floor and platform layout from a simple text pattern.",
		"use": "Type rows of # for solid ground, . for empty, ^ for spikes.",
		"syn": ["map", "tilemap", "tiles", "stage", "world", "layout", "design level", "grid", "level design"],
		"params": {
			"pattern": "One line per row of the level: # is solid, . is empty air, ^ is a spike, o is a coin, P is where you start.",
			"tile": "The shape each cell becomes.",
			"theme": "Colour scheme for the tiles.",
		},
		"related": ["platform", "entry", "hazard"],
	},
	"moving_platform": {
		"name": "Moving Platform", "cat": "objects", "tier": TIER_STANDARD,
		"help": "A platform that travels a set route and carries the player.",
		"syn": ["platform", "lift", "elevator", "moving", "ride", "conveyor"],
		"params": {
			"distance": "How far it travels before turning around.",
			"speed": "How fast it moves.",
			"axis": "Which way it goes: sideways, up and down, or in and out.",
		},
		"related": ["platform", "move"],
	},
	"enemy_patrol": {
		"name": "Walking Enemy", "cat": "objects", "tier": TIER_CORE,
		"help": "An enemy that walks back and forth on its own.",
		"syn": ["enemy", "bad guy", "monster", "guard", "villain", "patrol", "chase", "ai", "npc", "mob"],
		"params": {
			"distance": "How far it walks before turning around.",
			"speed": "How fast it walks.",
		},
		"related": ["hazard", "follow", "pathfind", "state", "perceive"],
	},
	"hazard": {
		"name": "Spike / Trap", "cat": "objects", "tier": TIER_CORE,
		"help": "Spikes, lava or a trap that hurts on touch.",
		"syn": ["spike", "lava", "trap", "danger", "kill", "hurt", "damage", "fire", "pit"],
		"params": {"damage": "How much health it takes away each time you touch it."},
		"related": ["health", "collide", "winlose"],
	},
	"checkpoint": {
		"name": "Respawn Point", "cat": "objects", "tier": TIER_STANDARD, "icon": "🔄",
		"help": "Where the player comes back to if they die, instead of the very start.",
		"syn": ["save point", "respawn", "restart", "revive", "continue"],
		"related": ["checkpoint_save", "save", "winlose"],
	},
	"entry": {
		"name": "Start Point", "cat": "objects", "tier": TIER_STANDARD,
		"help": "A named marker a door or level can send the player to.",
		"syn": ["spawn point", "start position", "begin", "marker"],
		"params": {"marker": "The name other bricks use to find this spot — give it a word like 'level2'."},
		"related": ["door", "level"],
	},
	"door": {
		"name": "Door to Next Level", "cat": "objects", "tier": TIER_STANDARD,
		"help": "An exit that takes the player to another level.",
		"syn": ["exit", "portal", "gate", "next level", "passage", "entrance"],
		"params": {
			"target_level": "Which level number this door leads to.",
			"target_entry": "The Start Point marker you land on once through the door.",
			"transition": "How the screen changes: instant, fade, or slide.",
			"needs_var": "Optional: only open when a variable reaches this value (a key you collected, coins enough).",
		},
		"related": ["entry", "level", "variable", "trigger"],
	},
	"background": {
		"name": "Scrolling Background", "cat": "objects", "tier": TIER_STANDARD,
		"help": "Scenery that scrolls behind everything, for depth.",
		"syn": ["sky", "scenery", "parallax", "backdrop", "clouds", "far away"],
		"params": {
			"layers": "How many bands of scenery, 1 to 5. More layers = more depth.",
			"theme": "The colours of the scenery: hills, city, cave, space and so on.",
		},
		"related": ["sky", "look"],
	},
	"sky": {
		"name": "Sky & Mood", "cat": "objects", "tier": TIER_STANDARD,
		"help": "The sky and air: day, sunset, night, space or fog.",
		"syn": ["skybox", "day", "night", "sunset", "space", "weather", "fog", "atmosphere"],
		"params": {"preset": "Pick a mood — day, dusk, night, space, cave, storm."},
		"related": ["background", "look", "light"],
	},
	"rigid": {
		"name": "Physics Object", "cat": "objects", "tier": TIER_ADVANCED,
		"help": "Real physics: crates that fall, bounce, roll and stack.",
		"syn": ["physics", "fall", "crate", "box", "gravity", "stack", "bounce", "roll", "rigidbody"],
		"params": {
			"model": "The shape and colour of the object.",
			"size": "How big it is.",
			"color_name": "Its colour, by name.",
			"start_asleep": "True = it does not move until something hits it.",
			"mass": "How heavy it is. Heavier things push lighter ones aside.",
			"gravity_scale": "1 = normal gravity, 0 = it floats, minus = it falls upwards.",
			"bounciness": "How much of its speed it keeps when it hits something.",
			"friction": "How much it grips surfaces it slides along.",
			"linear_damping": "Air drag for straight-line motion — higher slows it down sooner.",
			"angular_damping": "Drag on spinning — higher stops the spin sooner.",
			"freeze": "Stops the object from being pushed at all, as if it were part of the level.",
		},
		"related": ["platform", "collider", "attach"],
	},
	"attach": {
		"name": "Attach To", "cat": "objects", "tier": TIER_ADVANCED,
		"help": "Sticks one thing onto another, like a gun in an enemy's hand.",
		"syn": ["parent", "stick to", "gun on enemy", "hat on head", "attach", "child", "hold"],
		"params": {
			"child_brick": "The brick that gets stuck on (the gun).",
			"parent_brick": "The brick it gets stuck to (the enemy).",
			"inherit_rotation": "If on, the attached thing turns along with its parent.",
			"follow_position": "If on, the attached thing travels with its parent.",
			"visible": "Turn this off to keep the child hidden while it still travels along.",
		},
		"related": ["spawn", "blueprint"],
	},
	"light": {
		"name": "Light & Glow", "cat": "objects", "tier": TIER_ADVANCED,
		"help": "A lamp or torch that lights the area and casts shadows.",
		"syn": ["lamp", "torch", "glow", "bright", "shadow", "illuminate", "2d light"],
		"params": {
			"kind_of_light": "Point glows in a circle, directional is like the sun, spot is a torch beam.",
			"color_name": "The colour of the light.",
			"intensity": "How strong the light is.",
			"range": "How far the light reaches.",
			"shadows": "Whether things in front of it block the light.",
			"shadow_softness": "How fuzzy the edge of a shadow is.",
			"flicker": "Makes the light dance like a flame.",
			"flicker_speed": "How fast that dance is.",
		},
		"related": ["occluder", "sky", "look"],
	},
	"occluder": {
		"name": "Shadow Blocker", "cat": "objects", "tier": TIER_ADVANCED,
		"help": "A shape that blocks light so it makes a shadow.",
		"syn": ["shadow", "block light", "cast shadow", "dark", "sprite shadow"],
		"params": {
			"shape": "The outline that blocks the light.",
			"width": "How wide the blocker is.",
			"height": "How tall the blocker is.",
		},
		"related": ["light"],
	},
	"inventory": {
		"name": "Item Count", "cat": "objects", "tier": TIER_STANDARD,
		"help": "Keeps count of items the player carries, like keys.",
		"syn": ["items", "pickup", "collect", "bag", "keys", "stuff", "carry"],
		"params": {
			"item": "What is being counted, e.g. 'key'.",
			"op": "Add, subtract or set the count when this brick fires.",
			"amount": "How many to add or remove.",
			"need": "Optional: the door or switch that only works with this many items.",
		},
		"related": ["variable", "door", "hud"],
	},
	# ==================== Movement & controls ====================
	"move": {
		"name": "Move & Jump", "cat": "moving", "tier": TIER_CORE,
		"help": "Makes something walk, run or jump when you press the keys you pick.",
		"use": "Wire a Character into this, then into whatever should happen when it touches things.",
		"syn": ["walk", "run", "jump", "controls", "wasd", "arrow", "speed", "move around", "platform"],
		"params": {
			"style": "Platformer jumps with gravity, top-down slides on a plane, fly ignores gravity.",
			"speed": "How fast it goes. 8 is a comfortable walk, 20+ feels arcade-fast.",
			"jump": "How hard the jump pushes upwards. 12 clears a one-block gap.",
			"gravity": "How strongly it is pulled down. 30 feels earth-like for a small character.",
		},
		"related": ["spawn", "camera", "gamepad", "pathfind"],
	},
	"camera": {
		"name": "Camera", "cat": "moving", "tier": TIER_CORE,
		"help": "The player's point of view — how far away it sits and how smoothly it follows.",
		"syn": ["view", "follow", "look", "screen", "zoom", "see"],
		"params": {
			"mode": "Follow keeps the player on screen; fixed shows one spot; overhead looks straight down.",
			"distance": "How far the camera sits from what it watches.",
			"height": "How high above it the camera sits.",
			"smooth": "Eases the camera instead of snapping to the player — the difference between smooth and jittery.",
			"shake": "Kick the view when the game says something landed: a hit, a pickup, an explosion.",
			"shake_strength": "How hard the view kicks when it shakes. 0.6 is a nudge, 2 is an earthquake.",
		},
		"related": ["spawn", "move"],
	},
	"gamepad": {
		"name": "Gamepad Support", "cat": "moving", "tier": TIER_STANDARD,
		"help": "Lets players use a controller instead of the keyboard.",
		"syn": ["controller", "joystick", "gamepad", "xbox", "playstation", "rumble", "vibrate", "stick"],
		"params": {
			"enabled": "Off means keyboard only.",
			"device": "Which controller to listen to, when more than one is plugged in.",
			"deadzone": "How far the stick must move before it counts — kills the drift when you let go.",
			"invert_y": "Flip the up/down stick direction.",
			"vibrate": "Let the controller rumble when things happen.",
			"vibrate_strength": "How strong that rumble is.",
		},
		"related": ["move", "spawn"],
	},
	"animation": {
		"name": "Auto Animation", "cat": "moving", "tier": TIER_STANDARD,
		"help": "Makes a thing spin, bob or pulse on its own.",
		"syn": ["spin", "bob", "pulse", "wobble", "animate", "float", "idle"],
		"params": {
			"motion": "The idle motion: spin, bob up and down, pulse bigger and smaller, or wobble.",
			"speed": "How fast the motion loops.",
		},
		"related": ["spawn", "particles"],
	},
	"follow": {
		"name": "Chase / Follow", "cat": "moving", "tier": TIER_STANDARD,
		"help": "Makes something chase or trail something else.",
		"syn": ["chase", "trail", "pursue", "go after", "hunt", "follow me"],
		"params": {
			"target": "What it chases — usually the player.",
			"speed": "How fast it closes in. Keep it below the player's own speed so it can be escaped.",
		},
		"related": ["enemy_patrol", "pathfind", "perceive"],
	},
	"pathfind": {
		"name": "Smart Path", "cat": "moving", "tier": TIER_STANDARD, "icon": "🧭",
		"help": "Routes a thing around walls to reach its target instead of pressing into them.",
		"say": "Builds a navigation mesh around the level and walks the thing along it, so an enemy stops getting stuck on the geometry. In 3D this is fully proven; in 2D the navmesh is still missing, so use it in 3D games for now.",
		"syn": ["navigate", "pathfinding", "avoid walls", "smart enemy", "route", "navmesh", "get unstuck"],
		"params": {
			"mode": "Chase keeps hunting the target; wander roams; point walks to fixed spots.",
			"target": "What it tries to reach — usually the player.",
			"speed": "How fast it travels along the path.",
			"arrive_radius": "How close it counts as 'arrived' before it stops pushing.",
			"repath": "How often it recomputes the route, in seconds. Lower reacts faster, costs more.",
			"guard_radius": "How much clearance it keeps from walls.",
			"avoid": "Let two of these steer around each other instead of stacking.",
			"draw_path": "Draws the route on screen — useful while testing, hide it when shipping.",
			"points": "Optional fixed waypoints, in order.",
		},
		"related": ["follow", "enemy_patrol", "perceive", "state"],
	},
	# ==================== Rules, score & winning ====================
	"collide": {
		"name": "On Touch", "cat": "rules", "tier": TIER_CORE, "icon": "🤝",
		"help": "Runs what comes next when two things touch, like player and coin.",
		"use": "Usually: Character → On Touch (coin) → Add score → Win at 10.",
		"syn": ["hit", "bump", "touch", "crash", "solid", "wall", "physics", "collect"],
		"params": {
			"with": "Which kind of thing it has to touch for this to fire.",
			"action": "What the touch means: collect it, lose, win, or respawn.",
		},
		"related": ["score", "winlose", "trigger", "destroy"],
	},
	"trigger": {
		"name": "Trigger Zone", "cat": "rules", "tier": TIER_STANDARD,
		"help": "An invisible zone that fires bricks when the player walks in.",
		"syn": ["zone", "area", "when player enters", "detect", "event zone", "region"],
		"params": {
			"shape": "Box, sphere or a wide flat area.",
			"size": "How big the zone is.",
			"visible_hint": "Show a faint marker in the editor so you can see where it is.",
			"target": "Who sets it off — usually the player.",
			"once": "Fires only the first time, then goes quiet.",
			"needs_var": "Optional: only fires when this variable has reached this value.",
			"on_enter": "What to run when the player walks in.",
			"on_exit": "What to run when they leave.",
		},
		"related": ["collide", "rule", "door", "sound"],
	},
	"score": {
		"name": "Score / Count", "cat": "rules", "tier": TIER_CORE,
		"help": "Changes a number: points up, lives down, a switch flipping on.",
		"syn": ["points", "count", "collect", "coins", "tally", "keep track"],
		"params": {
			"variable": "The name of the number to change, e.g. 'score'.",
			"op": "Add to it, take away from it, or set it to a value.",
			"amount": "By how much.",
		},
		"related": ["variable", "winlose", "hud"],
	},
	"winlose": {
		"name": "Win / Lose", "cat": "rules", "tier": TIER_CORE, "icon": "🏁",
		"help": "Decides when the game says you won or you lost.",
		"use": "A game with no end feels unfinished — give every project one of these.",
		"syn": ["win", "lose", "die", "death", "game over", "victory", "fail", "end", "dead"],
		"params": {
			"condition": "What ends it: a number reaches a value, drops to it, or the clock runs out.",
			"value": "The number that triggers it.",
		},
		"related": ["score", "variable", "health", "timer"],
	},
	"variable": {
		"name": "Variable", "cat": "rules", "tier": TIER_CORE,
		"help": "A number or yes/no switch the game remembers.",
		"syn": ["value", "number", "store", "remember", "flag", "counter", "data", "math"],
		"params": {
			"name": "What you call it, e.g. 'coins'. Rules and screens look it up by this name.",
			"scope": "Level keeps it for one level; Game keeps it across levels.",
			"type": "Number counts, Switch is on/off, Text remembers words.",
			"op": "What to do when this brick fires: add, subtract, set, or just read it.",
			"amount": "How much to add or subtract.",
			"value": "The value to set it to.",
		},
		"related": ["rule", "score", "hud", "watch"],
	},
	"rule": {
		"name": "Rule: If → Then", "cat": "rules", "tier": TIER_CORE, "icon": "🧠",
		"help": "'If this is true, then do that.' The brick for game logic.",
		"say": "The one brick that lets you build any rule without new brick types. Pick a condition (a variable compared to a value), then list the bricks it should fire.",
		"syn": ["if", "then", "condition", "logic", "when", "check", "compare", "branch"],
		"params": {
			"cond_source": "What the test looks at: a variable, a number, or an event name.",
			"cond_var": "The variable to test — it needs a Variable brick with the same name.",
			"cond_op": "The comparison: equals, more than, less than and so on.",
			"cond_value": "The value to compare against.",
			"cond_key": "For text or switch variables: the word or on/off it has to match.",
			"actions": "What happens when the test passes — the bricks to fire.",
		},
		"related": ["variable", "winlose", "trigger", "score"],
	},
	"health": {
		"name": "Health & Hearts", "cat": "rules", "tier": TIER_STANDARD,
		"help": "Gives the player hearts or health that damage can eat away.",
		"syn": ["life", "lives", "hearts", "hp", "damage", "hurt", "die"],
		"params": {
			"max": "How much health starts at (hearts if you show it as a bar).",
			"damage": "How much each hit takes away.",
		},
		"related": ["hazard", "winlose", "hud"],
	},
	"timer": {
		"name": "Timer", "cat": "rules", "tier": TIER_STANDARD,
		"help": "Waits a number of seconds, or fires every few seconds.",
		"syn": ["clock", "countdown", "wait", "delay", "seconds", "schedule", "every"],
		"params": {
			"name": "A name so other bricks (and the HUD) can read this clock: 'race', 'pattern'.",
			"seconds": "How long it counts, in seconds.",
			"mode": "'once' fires one time and stops. 'repeat' starts again by itself, every 'Every N sec'.",
			"every": "In repeat mode, how often it fires.",
			"on_end": "What happens when it finishes: win, lose, or nothing (other bricks can listen for it).",
		},
		"related": ["winlose", "rule", "sound", "spawn"],
	},
	"destroy": {
		"name": "Remove / Destroy", "cat": "rules", "tier": TIER_STANDARD,
		"help": "Takes something out of the game when its event fires.",
		"syn": ["remove", "delete", "kill", "disappear", "despawn", "vanish"],
		"params": {"on": "What triggers the removal: being touched, a timer, or leaving the screen."},
		"related": ["collide", "timer", "particles", "sound"],
	},
	"collider": {
		"name": "Collision Rules", "cat": "rules", "tier": TIER_ADVANCED,
		"help": "Decides what can bump into what: bullets through walls, coins that stick.",
		"syn": ["layer", "collision", "mask", "what can hit what", "physics layer"],
		"params": {
			"layer": "Which team this thing is on, 1 to 5.",
			"collides_with": "Which teams it actually bumps into — the others pass straight through.",
			"solid": "Off means it is not solid: things overlap it instead of stopping.",
			"shape": "Box, sphere or a flat area.",
			"size": "How big the collision shape is.",
			"position_y": "How high the shape sits on the thing.",
		},
		"related": ["collide", "rigid", "platform"],
	},
	"save": {
		"name": "Save Progress", "cat": "rules", "tier": TIER_STANDARD,
		"help": "Writes the player's progress to their PC and loads it back.",
		"syn": ["save game", "load", "persist", "store progress", "write file"],
		"params": {
			"mode": "Save writes a file, Load reads it back.",
			"slot": "Which save slot — 1, 2, 3, and so on.",
			"key": "The name the file is stored under.",
			"include_position": "Remember where the player was standing.",
			"include_vars": "Remember all your variables.",
			"include_score": "Remember the score.",
		},
		"related": ["checkpoint_save", "variable", "button"],
	},
	"checkpoint_save": {
		"name": "Save Point", "cat": "rules", "tier": TIER_STANDARD, "icon": "💾",
		"help": "A spot the player can return to later.",
		"syn": ["save point", "autosave", "quick save", "checkpoint"],
		"params": {
			"slot": "Which save slot this point writes to.",
			"size": "How big the glowing marker is.",
			"once": "Only usable once instead of every time you walk over it.",
		},
		"related": ["save", "checkpoint"],
	},
	# ==================== Look & sound ====================
	"sound": {
		"name": "Play a Sound", "cat": "feel", "tier": TIER_STANDARD,
		"help": "Plays a short sound, like a coin ding or a jump.",
		"syn": ["audio", "sfx", "noise", "hear", "blip", "ding"],
		"params": {
			"kind": "Which built-in sound to play — coin, jump, hit, click, and so on.",
			"volume": "How loud, in decibels. Minus a few is softer, 0 is full.",
		},
		"related": ["audio", "collide", "particles"],
	},
	"audio": {
		"name": "Music & Volume", "cat": "feel", "tier": TIER_STANDARD, "icon": "🎵",
		"help": "Background music and sound routing with volume control.",
		"syn": ["music", "soundtrack", "mixer", "bus", "volume", "ambient", "loop"],
		"params": {
			"sound_kind": "Which built-in loop or sting to play — 'theme' is the long one that works as music.",
			"bus": "Which mixer channel it belongs to, so you can mute music without killing effects.",
			"volume_db": "How loud, in decibels.",
			"play_on_start": "Start by itself when the game opens.",
			"loop": "Keep playing forever instead of once.",
		},
		"related": ["sound", "style", "widget"],
	},
	"particles": {
		"name": "Sparkles & Effects", "cat": "feel", "tier": TIER_STANDARD,
		"help": "A burst of sparkles, smoke or fire for feel.",
		"syn": ["effect", "explosion", "burst", "smoke", "fire", "pretty", "confetti"],
		"params": {
			"effect": "The preset look: sparkle, smoke, fire, snow.",
			"amount": "How many bits fly out.",
			"color": "The colour of the burst.",
			"cone": "The width of the spray, in degrees. 360 throws in every direction, 45 is a jet.",
			"force": "How hard the bits are thrown out. Higher flies further and looks stronger.",
			"life": "How long each bit stays on screen, in seconds.",
			"pgravity": "Pull on the particles themselves: positive falls down, negative rises, 0 just drifts.",
		},
		"related": ["collide", "destroy", "sound"],
	},
	"look": {
		"name": "Picture Grade", "cat": "feel", "tier": TIER_ADVANCED,
		"help": "The colour and light style of the whole picture — bloom, mood, fog.",
		"syn": ["color grade", "cinematic", "bloom", "mood", "tonemap", "post processing"],
		"params": {
			"preset": "A ready-made grade: crisp, dreamy, dark, sunset, retro.",
			"bloom": "Makes bright things glow — the fastest way to look 'finished'.",
			"saturation": "How intense the colours are. Low is washed out, high is vivid.",
			"contrast": "How big the gap between dark and light is.",
			"brightness": "Overall exposure of the picture.",
			"vignette": "Darkens the corners of the screen, like a camera lens.",
			"ssao": "Softens contact between objects with ambient shadow.",
			"fog": "Adds distance haze so the background fades away.",
			"apply_2d": "Also apply the grade to a flat 2D game.",
		},
		"related": ["sky", "style", "light"],
	},
	"style": {
		"name": "UI Style", "cat": "feel", "tier": TIER_STANDARD,
		"help": "The colours, fonts and rounded corners of your game's buttons and menus.",
		"syn": ["theme", "style", "colors", "font", "transition", "fade", "slide", "design"],
		"params": {
			"preset": "A ready-made look for all menus at once.",
			"accent": "The highlight colour used on buttons and bars.",
			"font_size": "How big text is across your game's UI.",
			"corner_radius": "How rounded the panels and buttons are.",
			"transition": "How screens change: cut, fade, slide or zoom.",
			"transition_seconds": "How long that change takes.",
		},
		"related": ["screen", "hud", "widget", "look"],
	},
	# ==================== Menus & screen UI ====================
	"screen": {
		"name": "Menu Screen", "cat": "screens", "tier": TIER_STANDARD,
		"help": "A menu screen: title, pause, game over or credits.",
		"syn": ["menu", "title screen", "pause", "game over screen", "ui screen", "start menu", "credits"],
		"params": {
			"kind_of_screen": "Title, pause, game over, victory or credits — decides the buttons it makes.",
			"title": "The big text at the top.",
			"subtitle": "The smaller line under it.",
			"background": "Colour or style behind it.",
			"transition": "How it appears: fade, slide or instant.",
			"show_on_start": "Open by itself the moment the game starts — that is how a title screen works.",
			"pause_game": "Freeze the game while this screen is up (that is what makes it a pause menu).",
		},
		"related": ["button", "style", "winlose"],
	},
	"button": {
		"name": "Menu Button", "cat": "screens", "tier": TIER_STANDARD,
		"help": "A clickable button for your menus.",
		"syn": ["click", "press", "menu button", "play button", "interact", "tap"],
		"params": {
			"label": "The word written on the button, e.g. 'Play'.",
			"action": "What clicking does: start, resume, restart, go to a screen, change a variable.",
			"parent_screen": "Which Menu Screen this button sits on.",
			"target_screen": "The screen to open, when the action is 'go to screen'.",
			"var_name": "The variable to change, when the action is 'set variable'.",
			"var_value": "The value to give it.",
		},
		"related": ["screen", "variable", "save"],
	},
	"widget": {
		"name": "Slider / Toggle", "cat": "screens", "tier": TIER_ADVANCED,
		"help": "A slider, toggle or dropdown the player can set.",
		"syn": ["slider", "toggle", "dropdown", "options", "settings ui", "difficulty", "control"],
		"params": {
			"widget_kind": "Slider, toggle, dropdown or text input.",
			"label": "The words shown next to it.",
			"width": "How wide the control is.",
			"position": "Where it sits on the screen.",
			"action": "What using it does, usually set a variable.",
			"var_name": "The variable it writes to.",
			"var_value": "The value for on/off or choice controls.",
			"min_value": "The lowest the slider can go.",
			"max_value": "The highest the slider can go.",
			"step": "The size of one notch on the slider.",
			"options": "The choices a dropdown shows, separated by commas.",
		},
		"related": ["variable", "hud", "audio", "screen"],
	},
	"hud": {
		"name": "Show On Screen", "cat": "screens", "tier": TIER_STANDARD,
		"help": "What shows on screen while playing: health bar, score, hearts, minimap.",
		"syn": ["health bar", "display", "ui", "show score", "hearts", "minimap", "counter", "on screen"],
		"params": {
			"widget": "What kind of display: a bar, a counter, hearts, a minimap, an inventory row or plain text.",
			"var_name": "Which variable it reads — it updates itself as that number changes.",
			"label": "Words to show beside it, like 'Score'.",
			"max_var": "Read this variable to decide how full a bar is.",
			"max_value": "Or use a fixed maximum instead.",
			"show_percent": "Print 75% as well as the bar.",
			"position": "Which corner or edge it sits in.",
			"color_name": "Its colour.",
		},
		"related": ["variable", "health", "style", "inventory"],
	},
	# ==================== Smart behaviour ====================
	"state": {
		"name": "Behaviour Modes", "cat": "smart", "tier": TIER_ADVANCED, "icon": "🎭",
		"help": "Behaviour with moods: idle, patrol, chase, attack — and the rules between them.",
		"say": "A state machine in one brick: name the modes, then say what switches you from one to the next. This is how bosses get phases and guards get suspicious.",
		"syn": ["state machine", "behavior", "ai states", "idle", "patrol", "chase", "attack", "boss", "phases"],
		"params": {
			"var_name": "The variable that remembers which mode is active.",
			"initial": "The mode to start in.",
			"states": "The list of mode names, separated by commas.",
			"transitions": "The switch rules: 'from > to : condition', one per line.",
			"owner": "The brick whose behaviour this drives.",
			"show_state": "Print the current mode above it — handy while testing.",
		},
		"related": ["perceive", "pathfind", "follow", "variable"],
	},
	"perceive": {
		"name": "Sight & Hearing", "cat": "smart", "tier": TIER_ADVANCED,
		"help": "Lets an enemy actually see or hear you, with memory.",
		"syn": ["see me", "notice", "sight", "vision", "cone", "detect player", "awareness", "spot"],
		"params": {
			"sight_range": "How far it can see, in blocks.",
			"sight_angle": "How wide its field of view is — 90 is a person looking ahead, 360 sees everything.",
			"hearing_range": "How far it can hear you moving.",
			"needs_line_of_sight": "If on, walls block its view instead of you being seen through them.",
			"on_notice": "What to fire the moment it spots you.",
			"alert_var": "Write to this variable so rules and the HUD can react to being spotted.",
			"event_name": "Broadcast this event name so anything listening hears about it.",
			"memory_seconds": "How long it keeps looking after you break line of sight.",
			"show_cone": "Draw the sight cone while testing.",
		},
		"related": ["state", "pathfind", "follow", "trigger"],
	},
	# ==================== Reuse, save & testing ====================
	"blueprint_def": {
		"name": "Reusable Definition", "cat": "tools", "tier": TIER_ADVANCED, "icon": "🧩",
		"help": "Define a reusable thing once, like 'a coin'.",
		"syn": ["prefab", "template", "reuse", "define", "blueprint", "prototype"],
		"params": {
			"name": "The name other bricks use to place copies of it.",
			"description": "A note to yourself about what it is.",
		},
		"related": ["blueprint", "attach"],
	},
	"blueprint": {
		"name": "Place Many Copies", "cat": "tools", "tier": TIER_ADVANCED, "icon": "📋",
		"help": "Place many copies of a definition at once, arranged for you.",
		"say": "Ten coins used to mean ten hand-wired brick sets. Define the coin once, then place a row, grid or circle of them with this brick — one fix to the definition updates every copy.",
		"syn": ["prefab", "instance", "place many", "copy", "repeat", "spawn many", "multiple", "row of coins"],
		"params": {
			"blueprint_name": "Which definition to copy.",
			"count": "How many copies to place.",
			"layout": "How they are arranged: row, grid, circle or scatter.",
			"spread": "The gaps between copies.",
			"rows": "How many rows, for the grid layout.",
			"overrides": "Settings to change on these copies only, as name=value pairs.",
		},
		"related": ["blueprint_def", "level", "spawn"],
	},
	"watch": {
		"name": "Live Numbers", "cat": "tools", "tier": TIER_ADVANCED,
		"help": "Shows live numbers on screen while the game runs, for testing.",
		"syn": ["debug", "inspect", "see values", "watch variable", "live values", "show numbers"],
		"params": {
			"var_names": "Which variables to show, separated by commas.",
			"position": "Where on screen the list sits.",
			"font_size": "How big the numbers are.",
			"editable": "Let you type a new value while the game plays — the fastest way to test a rule.",
			"show_changes": "Only print a line when something actually changed.",
		},
		"related": ["variable", "error_panel", "hud"],
	},
	"error_panel": {
		"name": "Problem List", "cat": "tools", "tier": TIER_ADVANCED,
		"help": "Collects problems into a plain list instead of a crash.",
		"syn": ["errors", "problems", "warnings", "whats wrong", "fix", "report"],
		"params": {
			"show_on_start": "Open the list as soon as the game starts.",
			"auto_open": "Pop it open by itself when something goes wrong.",
			"detail_level": "Short one-liners, or the full detail for fixing it.",
		},
		"related": ["watch", "rule"],
	},
	"undo": {
		"name": "In-Game Undo", "cat": "tools", "tier": TIER_ADVANCED, "icon": "↩️",
		"help": "Adds a back button inside your game, if you want one.",
		"syn": ["rewind", "take back", "time travel", "retry last move"],
		"params": {
			"key": "Which key rewinds the game.",
			"depth": "How many steps back the player can go.",
			"track_position": "Rewind puts the player back where they stood.",
			"track_vars": "Rewind also puts your numbers back.",
		},
		"related": ["save", "watch"],
	},
}

# ---------------------------------------------------------------------------
# Lookup helpers — every UI surface goes through these, so the wording can
# never drift between the palette, the inspector and the Manual.
# ---------------------------------------------------------------------------

## The full entry for a kind, or {} when this brick has no docs yet.
static func entry_for(kind: String) -> Dictionary:
	var d = DOCS.get(kind, null)
	return d if d is Dictionary else {}

## What the UI calls this brick. Falls back to the kind id, so a brick nobody
## has written docs for still shows a readable name rather than "enemy_patrol".
## The registry layers the IR label in between (see registry.gd kind_label).
static func name_for(kind: String) -> String:
	var d := entry_for(kind)
	if not str(d.get("name", "")).is_empty():
		return str(d["name"])
	return str(kind).replace("_", " ").capitalize()

static func icon_for(kind: String) -> String:
	return str(entry_for(kind).get("icon", ""))

static func category_of(kind: String) -> String:
	return str(entry_for(kind).get("cat", "objects"))

static func tier_of(kind: String) -> String:
	return str(entry_for(kind).get("tier", TIER_STANDARD))

static func is_advanced(kind: String) -> bool:
	return tier_of(kind) == TIER_ADVANCED

## One-line "what does this do", for tooltips and lists.
static func help_for(kind: String) -> String:
	var d := entry_for(kind)
	var help := str(d.get("help", ""))
	return help if not help.is_empty() else str(d.get("say", ""))

## The longer explanation, for the Manual page.
static func says_for(kind: String) -> String:
	var d := entry_for(kind)
	var say := str(d.get("say", ""))
	return say if not say.is_empty() else str(d.get("help", ""))

## The typical wiring, shown in the Manual so a brick is not a mystery box.
static func use_for(kind: String) -> String:
	return str(entry_for(kind).get("use", ""))

static func params_for(kind: String) -> Dictionary:
	var p = entry_for(kind).get("params", {})
	return p if p is Dictionary else {}

## Plain explanation of one setting. "" when there is nothing to say.
static func param_help(kind: String, key: String) -> String:
	return str(params_for(kind).get(key, ""))

static func synonyms_for(kind: String) -> Array:
	var s = entry_for(kind).get("syn", [])
	return s if s is Array else []

static func related_for(kind: String) -> Array:
	var r = entry_for(kind).get("related", [])
	return r if r is Array else []

static func category_label(cat_id: String) -> String:
	for c in CATEGORIES:
		if str(c["id"]) == cat_id:
			return str(c["label"])
	return cat_id.capitalize()

static func category_hint(cat_id: String) -> String:
	for c in CATEGORIES:
		if str(c["id"]) == cat_id:
			return str(c["hint"])
	return ""

# ---------------------------------------------------------------------------
# Search — a beginner finds a brick by what they WANT, not by what we named it.
# Matches the friendly name, the IR label, the kind id, the plain-English help
# and the synonym list, so "bad guy" finds enemy_patrol and "die" finds Win/Lose.
# ---------------------------------------------------------------------------

## The haystack a search can hit for this kind: friendly name, IR label, kind id,
## what it does, and the beginner words for it. Rebuilt per call — 50 kinds is
## nothing next to a keystroke, and GDScript has no static storage to cache in.
static func _haystack(kind: String, meta: Dictionary) -> String:
	var hay := " %s %s %s %s " % [
		name_for(kind), str(meta.get("label", kind)),
		str(kind).replace("_", " "), help_for(kind),
	]
	for w in synonyms_for(kind):
		hay += str(w) + " "
	return hay.to_lower()

static func matches(kind: String, meta: Dictionary, needle: String) -> bool:
	var hay := _haystack(kind, meta)
	var n := needle.to_lower().strip_edges()
	if n.is_empty():
		return true
	if n in hay:
		return true
	# every word of a multi-word query must appear somewhere
	for part in n.split(" ", false):
		if not part.is_empty() and not (part in hay):
			return false
	return true

## How good this kind is as a search hit: name beats help beats synonyms. The
## palette and the Manual both sort by this so the brick you meant is on top.
static func rank(kind: String, meta: Dictionary, needle: String) -> int:
	var n := needle.to_lower().strip_edges()
	if n.is_empty():
		return 3
	if n in name_for(kind).to_lower():
		return 0
	if n in str(meta.get("label", "")).to_lower():
		return 1
	if n in help_for(kind).to_lower():
		return 2
	return 4
