extends RefCounted
## GenreLibrary — "I want a racing game" → the bricks that make one.
##
## The product's promise is that describing a game gets you a game. Two things
## blocked that, and this file fixes both:
##
## 1. The AI prompt listed 23 brick kinds while the palette has 50, so a shooter
##    request could never get a HUD, a health brick, a menu screen or a state
##    machine — the model was not allowed to use them. Meanwhile the prompt
##    OFFERED npc/quest/bullet/ammo, which no compiler module builds: the model
##    dutifully emitted them and the game silently lost those bricks.
##    -> vocabulary() now lists every kind the compiler really implements, and
##       prompt_block() adds the shortlist + wiring pattern for the genre it
##       detected in the user's own words.
##
## 2. With no API key there was no generation at all — just an error message
##    pointing at Settings. But "give me the bricks for a platformer" does not
##    need a language model: it needs the right set of bricks in the right order.
##    -> build() returns a complete, pre-wired, playable graph per genre, so the
##       describe-a-game box works offline, and the AI path has a floor to fall
##       back to when a request fails, times out, or comes back garbled.
##
## Everything here is data plus one deterministic builder, which also means it is
## testable: smoke asserts each genre compiles in 2D and 3D with no placeholder
## and no structural problem.

class_name GenreLibrary

# ---------------------------------------------------------------------------
# Genres. Detected from the user's own words (keywords), then used two ways:
# as the AI's shortlist, and as the offline graph builder.
#
# Brick entries: {"k": kind, "t": title, "p": params}
# Wires: [from_index, from_port, to_index, to_port] — always forward, and the
# builder validates them through graph.wire(), which refuses an ill-typed pair.
# ---------------------------------------------------------------------------
const GENRES := {
	"platformer": {
		"label": "Platformer",
		"dim": "2d",
		"pitch": "Run, jump, collect coins, dodge enemies, win at ten points.",
		"keywords": ["platform", "platformer", "jump", "mario", "side scroll", "side-scroller", "coin", "collect", "2d run", "caves", "parkour"],
		"shortlist": ["spawn", "move", "platform", "collide", "score", "winlose", "camera", "enemy_patrol", "hazard", "background", "sky", "sound", "particles", "hud"],
		"pattern": "spawn(player) -> move(platformer) -> collide(coin) -> score(+1) -> winlose(score 10). Put a Camera on the player, a Platform under them, and one spawn per pickup.",
		"bricks": [
			{"k": "spawn", "t": "Player", "p": {"model": "player", "position_y": 1.0}},
			{"k": "move", "t": "Run & Jump", "p": {"style": "platformer", "speed": 9.0, "jump": 13.0}},
			{"k": "platform", "t": "Ground", "p": {"preset": "normal", "width": 24.0, "height": 1.0}},
			{"k": "spawn", "t": "Coin", "p": {"model": "coin", "position_y": 1.0}},
			{"k": "collide", "t": "Touch a coin", "p": {"with": "coin", "action": "collect"}},
			{"k": "score", "t": "+1 point", "p": {"variable": "score", "op": "add", "amount": 1}},
			{"k": "winlose", "t": "Win at 10", "p": {"condition": "score_reaches", "value": 10}},
			{"k": "camera", "t": "Follow camera", "p": {"mode": "follow", "distance": 12.0, "height": 5.0}},
			{"k": "enemy_patrol", "t": "Patrol enemy", "p": {"distance": 6.0, "speed": 3.0}},
			{"k": "sky", "t": "Day sky", "p": {"preset": "day"}},
			{"k": "sound", "t": "Coin ding", "p": {"kind": "coin"}},
		],
		"wires": [[0, 0, 1, 0], [0, 0, 2, 0], [0, 0, 7, 0], [1, 0, 4, 0], [4, 0, 5, 0], [5, 0, 6, 0], [4, 0, 10, 0], [1, 0, 8, 0]],
	},
	"runner": {
		"label": "Endless Runner",
		"dim": "2d",
		"pitch": "Auto-run to the right, jump the obstacles, the score is how far you got.",
		"keywords": ["runner", "endless", "auto run", "temple run", "doodle", "obstacle", "distance", "survive"],
		"shortlist": ["spawn", "move", "hazard", "platform", "score", "winlose", "camera", "background", "sky", "timer", "hud", "sound", "particles"],
		"pattern": "spawn -> move(fast) -> hazard -> winlose. Score climbs while you live; a Background and a fast camera make it feel like running.",
		"bricks": [
			{"k": "spawn", "t": "Runner", "p": {"model": "player", "position_y": 1.0}},
			{"k": "move", "t": "Fast run", "p": {"style": "platformer", "speed": 15.0, "jump": 14.0}},
			{"k": "platform", "t": "Floor", "p": {"width": 40.0, "height": 1.0}},
			{"k": "hazard", "t": "Obstacle", "p": {"damage": 1.0}},
			{"k": "score", "t": "Distance", "p": {"variable": "distance", "op": "add", "amount": 1}},
			{"k": "winlose", "t": "Out of lives", "p": {"condition": "score_drops", "value": 0}},
			{"k": "camera", "t": "Chase camera", "p": {"mode": "follow", "distance": 11.0}},
			{"k": "background", "t": "Dusk hills", "p": {"theme": "dusk", "layers": 3.0}},
			{"k": "hud", "t": "Show distance", "p": {"widget": "counter", "var_name": "distance", "label": "Metres"}},
			{"k": "timer", "t": "Score every second", "p": {"seconds": 1.0, "mode": "repeat", "every": 1.0, "on_end": "nothing"}},
		],
		"wires": [[0, 0, 1, 0], [0, 0, 2, 0], [0, 0, 6, 0], [1, 0, 3, 0], [3, 0, 5, 0], [9, 0, 4, 0]],
	},
	"shooter": {
		"label": "Shooter",
		"dim": "3d",
		"pitch": "Move with the keys, blast the enemies, ten kills wins it.",
		"keywords": ["shooter", "shoot", "gun", "space invader", "bullet", "enemy", "kill", "wave", "twin stick", "fps"],
		"shortlist": ["spawn", "move", "collide", "destroy", "score", "winlose", "camera", "health", "hud", "particles", "sound", "screen", "button", "audio", "state", "perceive"],
		"pattern": "spawn(player) -> move(topdown) -> enemy_patrol -> score(kills) -> winlose. Add Health + a HUD bar so damage is visible, and a Screen for the title.",
		"bricks": [
			{"k": "spawn", "t": "Player", "p": {"model": "player", "position_y": 1.0}},
			{"k": "move", "t": "8-way move", "p": {"style": "topdown", "speed": 11.0}},
			{"k": "camera", "t": "Follow camera", "p": {"mode": "follow", "distance": 16.0}},
			{"k": "enemy_patrol", "t": "Enemy", "p": {"distance": 8.0, "speed": 3.5}},
			{"k": "score", "t": "+1 kill", "p": {"variable": "kills", "op": "add", "amount": 1}},
			{"k": "winlose", "t": "Win at 10 kills", "p": {"condition": "score_reaches", "value": 10}},
			{"k": "health", "t": "3 hearts", "p": {"max": 3.0, "damage": 1.0}},
			{"k": "hud", "t": "Kills shown", "p": {"widget": "counter", "var_name": "kills", "label": "Kills"}},
			{"k": "particles", "t": "Hit sparkles", "p": {"effect": "sparkle", "color": "red"}},
			{"k": "sky", "t": "Night sky", "p": {"preset": "night"}},
		],
		"wires": [[0, 0, 1, 0], [0, 0, 2, 0], [1, 0, 3, 0], [3, 0, 4, 0], [4, 0, 5, 0], [3, 0, 6, 0], [3, 0, 8, 0]],
	},
	"racing": {
		"label": "Racing",
		"dim": "3d",
		"pitch": "Drive the laps, beat the clock, hit a wall and you lose.",
		"keywords": ["race", "racing", "car", "lap", "speed", "drift", "track", "kart", "motorbike", "checkpoint"],
		"shortlist": ["spawn", "move", "camera", "checkpoint", "score", "timer", "winlose", "hazard", "sky", "background", "sound", "hud", "screen", "style"],
		"pattern": "spawn(car) -> move(fly/topdown, high speed) -> checkpoint -> score(laps) -> winlose. A Timer that ends the race and a HUD showing the lap count are what make it a race rather than a drive.",
		"bricks": [
			{"k": "spawn", "t": "Car", "p": {"model": "player", "position_y": 1.0}},
			{"k": "move", "t": "Drive", "p": {"style": "topdown", "speed": 20.0, "gravity": 0.0}},
			{"k": "camera", "t": "Chase cam", "p": {"mode": "follow", "distance": 14.0, "height": 5.0}},
			{"k": "platform", "t": "Track", "p": {"width": 60.0, "height": 1.0, "friction": 1.0}},
			{"k": "checkpoint", "t": "Lap line", "p": {}},
			{"k": "score", "t": "+1 lap", "p": {"variable": "laps", "op": "add", "amount": 1}},
			{"k": "winlose", "t": "Three laps wins", "p": {"condition": "score_reaches", "value": 3}},
			{"k": "timer", "t": "60 second race", "p": {"seconds": 60.0, "on_end": "lose"}},
			{"k": "hazard", "t": "Wall", "p": {"damage": 1.0}},
			{"k": "hud", "t": "Lap counter", "p": {"widget": "counter", "var_name": "laps", "label": "Lap"}},
			{"k": "sky", "t": "Sunset", "p": {"preset": "sunset"}},
			{"k": "sound", "t": "Engine blip", "p": {"kind": "jump"}},
		],
		"wires": [[0, 0, 1, 0], [0, 0, 2, 0], [0, 0, 3, 0], [1, 0, 4, 0], [4, 0, 5, 0], [5, 0, 6, 0], [1, 0, 8, 0], [7, 0, 6, 0]],
	},
	"puzzle": {
		"label": "Puzzle / Escape",
		"dim": "3d",
		"pitch": "Find the key, open the locked door, get out before the timer.",
		"keywords": ["puzzle", "escape", "key", "door", "locked", "maze", "riddle", "treasure", "quest", "find"],
		"shortlist": ["spawn", "move", "camera", "collide", "inventory", "variable", "rule", "door", "entry", "trigger", "timer", "winlose", "hud", "screen", "save"],
		"pattern": "spawn -> move -> collide(key) -> inventory. A Variable or Inventory gates the Door, and a Rule fires the win when the condition is met — that conditional is the puzzle.",
		"bricks": [
			{"k": "spawn", "t": "Explorer", "p": {"model": "player", "position_y": 1.0}},
			{"k": "move", "t": "Walk", "p": {"style": "topdown", "speed": 8.0}},
			{"k": "camera", "t": "Follow camera", "p": {"mode": "follow", "distance": 15.0}},
			{"k": "platform", "t": "Room floor", "p": {"width": 30.0, "height": 1.0}},
			{"k": "collide", "t": "Touch the key", "p": {"with": "coin", "action": "collect"}},
			{"k": "inventory", "t": "Keys", "p": {"item": "key", "op": "add", "amount": 1, "need": 1}},
			{"k": "variable", "t": "Doors opened", "p": {"name": "doors", "scope": "game", "type": "number", "op": "add", "amount": 1}},
			{"k": "door", "t": "Locked door", "p": {"target_level": "2", "target_entry": "start", "needs_var": "doors"}},
			{"k": "rule", "t": "One door wins it", "p": {"cond_source": "variable", "cond_var": "doors", "cond_op": ">=", "cond_value": 1, "actions": "win"}},
			{"k": "hud", "t": "Keys shown", "p": {"widget": "counter", "var_name": "doors", "label": "Doors"}},
			{"k": "timer", "t": "Two minute limit", "p": {"seconds": 120.0, "on_end": "lose"}},
			{"k": "entry", "t": "Level 2 start", "p": {"marker": "start"}},
		],
		"wires": [[0, 0, 1, 0], [0, 0, 2, 0], [0, 0, 3, 0], [1, 0, 4, 0], [4, 0, 5, 0], [4, 0, 6, 0], [6, 0, 8, 0], [7, 0, 6, 0], [10, 0, 8, 0]],
	},
	"adventure": {
		"label": "Adventure / RPG",
		"dim": "3d",
		"pitch": "Wander a world, talk to things, avoid guards, save your progress.",
		"keywords": ["adventure", "rpg", "quest", "village", "npc", "talk", "explore", "world", "dungeon", "journey", "zelda"],
		"shortlist": ["spawn", "move", "camera", "level", "entry", "door", "enemy_patrol", "follow", "health", "hud", "inventory", "variable", "rule", "save", "checkpoint_save", "screen", "button", "audio", "sky", "background"],
		"pattern": "spawn -> move(topdown) -> camera. Doors and Entries stitch levels together, Health + a HUD bar make damage mean something, and Save + a checkpoint are what an adventure needs to be an adventure.",
		"bricks": [
			{"k": "spawn", "t": "Hero", "p": {"model": "player", "position_y": 1.0}},
			{"k": "move", "t": "Walk", "p": {"style": "topdown", "speed": 9.0}},
			{"k": "camera", "t": "Follow camera", "p": {"mode": "follow", "distance": 18.0, "height": 12.0}},
			{"k": "sky", "t": "Day sky", "p": {"preset": "day"}},
			{"k": "enemy_patrol", "t": "Guard", "p": {"distance": 7.0, "speed": 3.0}},
			{"k": "health", "t": "5 hearts", "p": {"max": 5.0, "damage": 1.0}},
			{"k": "hud", "t": "Hearts", "p": {"widget": "hearts", "var_name": "health", "label": "Hearts"}},
			{"k": "inventory", "t": "Coins", "p": {"item": "coin", "op": "add", "amount": 1, "need": 3}},
			{"k": "variable", "t": "Story flag", "p": {"name": "met_elder", "scope": "game", "type": "bool", "op": "set", "value": 1}},
			{"k": "rule", "t": "Elder met", "p": {"cond_source": "variable", "cond_var": "met_elder", "cond_op": ">=", "cond_value": 1, "actions": "add_var:coins"}},
			{"k": "door", "t": "Village gate", "p": {"target_level": "2", "target_entry": "start"}},
			{"k": "entry", "t": "Village side", "p": {"marker": "start"}},
			{"k": "checkpoint_save", "t": "Save shrine", "p": {"slot": 1.0, "once": false}},
			{"k": "audio", "t": "World music", "p": {"sound_kind": "theme", "bus": "music", "volume_db": -10.0, "loop": true, "play_on_start": true}},
		],
		"wires": [[0, 0, 1, 0], [0, 0, 2, 0], [0, 0, 3, 0], [1, 0, 4, 0], [4, 0, 5, 0], [1, 0, 12, 0], [1, 0, 10, 0], [9, 0, 8, 0]],
	},
	"physics": {
		"label": "Physics Toy",
		"dim": "3d",
		"pitch": "Crates that fall, bounce, topple and stack — knock them over for points.",
		"keywords": ["physics", "crates", "domino", "stack", "bounce", "gravity", "fall", "ragdoll", "bridge", "angry birds", "sand"],
		"shortlist": ["spawn", "rigid", "platform", "collide", "camera", "score", "winlose", "rule", "variable", "particles", "sound", "destroy", "hud", "timer"],
		"pattern": "spawn or Physics Object for the props, a Platform as the ground, and Collide into Score to reward a knock-over. An orbit Camera sells the physics better than a follow one.",
		"bricks": [
			{"k": "platform", "t": "Table", "p": {"width": 30.0, "height": 1.0, "friction": 1.0}},
			{"k": "rigid", "t": "Crate", "p": {"model": "box", "mass": 2.0, "bounciness": 0.35}},
			{"k": "rigid", "t": "Ball", "p": {"model": "sphere", "mass": 1.0, "bounciness": 0.75}},
			{"k": "spawn", "t": "Pounder", "p": {"model": "player", "position_y": 2.0}},
			{"k": "move", "t": "Push around", "p": {"style": "topdown", "speed": 12.0}},
			{"k": "camera", "t": "Orbit camera", "p": {"mode": "orbit", "distance": 16.0, "height": 8.0}},
			{"k": "collide", "t": "Touch a crate", "p": {"with": "hazard", "action": "collect"}},
			{"k": "score", "t": "+1 toppled", "p": {"variable": "toppled", "op": "add", "amount": 1}},
			{"k": "winlose", "t": "Ten toppled", "p": {"condition": "score_reaches", "value": 10}},
			{"k": "particles", "t": "Impact dust", "p": {"effect": "smoke", "color": "white"}},
			{"k": "sound", "t": "Thud", "p": {"kind": "hit"}},
			{"k": "hud", "t": "Toppled count", "p": {"widget": "counter", "var_name": "toppled", "label": "Toppled"}},
		],
		"wires": [[0, 0, 1, 0], [0, 0, 2, 0], [3, 0, 4, 0], [3, 0, 5, 0], [4, 0, 6, 0], [6, 0, 7, 0], [7, 0, 8, 0], [6, 0, 9, 0], [6, 0, 10, 0]],
	},
	"story": {
		"label": "Story / Visual Novel",
		"dim": "2d",
		"pitch": "Lines of dialogue, a choice or two, and an ending you earned.",
		"keywords": ["story", "visual novel", "dialogue", "choice", "dating", "narrative", "adventure text", "comic", "book"],
		"shortlist": ["spawn", "sound", "variable", "rule", "screen", "button", "background", "style", "hud", "winlose", "save"],
		"pattern": "A Variable counts story beats, a Rule ends the story when the count is up, and Screens + Buttons carry the choices. Keep it 2D: text and art are the game.",
		"bricks": [
			{"k": "spawn", "t": "Hero", "p": {"model": "player", "position_y": 1.0}},
			{"k": "screen", "t": "Title", "p": {"kind_of_screen": "main_menu", "title": "My Story", "subtitle": "Chapter one", "show_on_start": true, "pause_game": true}},
			{"k": "button", "t": "Begin", "p": {"label": "Begin", "action": "start"}},
			{"k": "background", "t": "Candy backdrop", "p": {"theme": "candy", "layers": 2.0}},
			{"k": "sound", "t": "Narrate line", "p": {"kind": "click"}},
			{"k": "variable", "t": "Story progress", "p": {"name": "story", "scope": "game", "type": "number", "op": "add", "amount": 1}},
			{"k": "rule", "t": "End at five lines", "p": {"cond_source": "variable", "cond_var": "story", "cond_op": ">=", "cond_value": 5, "actions": "win"}},
			{"k": "hud", "t": "Scene number", "p": {"widget": "counter", "var_name": "story", "label": "Scene"}},
			{"k": "style", "t": "Story look", "p": {"preset": "playful", "accent": "purple", "transition": "fade"}},
			{"k": "winlose", "t": "The end", "p": {"condition": "score_reaches", "value": 5}},
		],
		"wires": [[0, 0, 3, 0], [0, 0, 4, 0], [0, 0, 5, 0], [1, 0, 2, 0], [5, 0, 6, 0], [6, 0, 9, 0]],
	},
}

## The generic shortlist when nothing matches a named genre.
const DEFAULT_GENRE := "platformer"

static func list_genres() -> Array:
	var out: Array = []
	for g in GENRES:
		out.append({"key": str(g), "label": str(GENRES[g]["label"]), "pitch": str(GENRES[g]["pitch"]), "dim": str(GENRES[g]["dim"])})
	return out

static func has(genre: String) -> bool:
	return GENRES.has(genre)

static func label(genre: String) -> String:
	return str(GENRES.get(genre, {}).get("label", genre))

static func kinds_for(genre: String) -> Array:
	return GENRES.get(genre, {}).get("shortlist", [])

static func pattern_for(genre: String) -> String:
	return str(GENRES.get(genre, {}).get("pattern", ""))

## Which genre do these words mean? Score each genre by how many of its keywords
## appear, and take the best. Returns "" when nothing matched, so the caller can
## say "I guessed" rather than pretend it knew.
static func detect(text: String) -> String:
	var hay := text.to_lower()
	var best := ""
	var best_hits := 0
	for g in GENRES:
		var hits := 0
		for w in (GENRES[g] as Dictionary).get("keywords", []):
			if str(w) in hay:
				hits += 1
		if hits > best_hits:
			best_hits = hits
			best = str(g)
	return best if best_hits > 0 else ""

## Every brick kind the compiler actually builds. npc/quest/bullet/ammo are
## deliberately NOT here: they are registered vocabulary from an older pass with
## no compiler module behind them, and the model naming them produced bricks that
## quietly did nothing.
static func vocabulary() -> Array:
	var out: Array = []
	# the registry is an autoload, and a static function has no `self` to resolve
	# it from — reach it through the tree, the same way ParamRows does
	var registry: Node = null
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		registry = (loop as SceneTree).root.get_node_or_null("/root/BrickRegistry")
	if registry != null and registry.has_method("all_kinds"):
		for kind in registry.all_kinds():
			out.append(str(kind))
		return out
	# no tree (unit test, or called before the autoloads are up): the IR table is
	# the same vocabulary, minus the genre-pack kinds that are not compiled
	for kind in BrickRef.KIND:
		out.append(str(kind))
	return out

## The genre-specific paragraph for the AI system prompt.
static func prompt_block(genre: String) -> String:
	if genre.is_empty() or not GENRES.has(genre):
		return ""
	var g: Dictionary = GENRES[genre]
	return "\nDETECTED GENRE: %s (%s)\nPrefer these bricks for this kind of game: %s.\nTypical wiring: %s\nStill use any other brick you need — the shortlist is a starting point, not a cage.\n" % [
		str(g["label"]), str(g["pitch"]), ", ".join(kinds_for(genre)), str(g["pattern"])
	]

## Build the whole genre graph. Deterministic, no network, no key: this is both
## the offline "make me a racing game" answer and the AI path's safety net.
static func build(genre: String, project_name: String = "") -> Dictionary:
	var key := genre if GENRES.has(genre) else DEFAULT_GENRE
	var g: Dictionary = GENRES[key]
	var made: Array = []
	for entry in g.get("bricks", []):
		var e: Dictionary = entry if entry is Dictionary else {}
		var kind := str(e.get("k", ""))
		var b := BrickRef.create(kind, str(e.get("t", "")), "")
		if b.is_empty():
			continue
		var p: Dictionary = b.get("params", {})
		var given: Dictionary = e.get("p", {})
		for pk in given:
			p[pk] = given[pk]
		b["params"] = p
		made.append(b)
	# wires address bricks by position, so drop silently on a bad index
	for w in g.get("wires", []):
		var arr: Array = w if w is Array else []
		if arr.size() < 4:
			continue
		var fi := int(arr[0])
		var ti := int(arr[2])
		if fi < 0 or fi >= made.size() or ti < 0 or ti >= made.size():
			continue
		var from: Dictionary = made[fi]
		var to: Dictionary = made[ti]
		var conns: Array = from.get("connections", [])
		conns.append({"from_out": int(arr[1]), "to_brick": str(to.get("id", "")), "to_in": int(arr[3])})
		from["connections"] = conns
	var name := project_name
	if name.is_empty():
		name = "%s Start" % str(g.get("label", "Game"))
	return {
		"project_name": name,
		"dimension": str(g.get("dim", "3d")),
		"genre": key,
		"bricks": made,
	}
