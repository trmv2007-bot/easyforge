extends RefCounted
## Recipes — "I want to add ___", done in one click.
##
## The honest problem this solves: a beginner staring at 50 bricks knows what
## they *want* ("make the coins give points and win at ten") but not which five
## bricks to add, in which order, wired to which ports. That knowledge used to
## live only in the demo template and in whoever wrote the AI prompt.
##
## A recipe is a small, pre-wired brick set that gets ADDED to the current graph
## (it never replaces it). Each one hooks onto an existing brick — usually the
## player — so the new bricks are live the moment they land, instead of being
## five orphan boxes the user still has to wire.
##
## Wiring rule, and the reason recipes are safe to offer: every connection goes
## through BrickRef.can_connect(). If a port does not fit, that one wire is
## skipped and reported — a recipe can never produce a graph the user did not
## ask for, and never hard-blocks anything (the spec's "softly guided" rule).

class_name Recipes

# ---------------------------------------------------------------------------
# Recipe format
#   key        stable id, used by the UI and by tests — never rename casually
#   name       what the button says, in the player's words not the engine's
#   pitch      one line explaining what it gives you
#   task       the group heading in the Manual ("Scoring", "Hazards", ...)
#   anchor     which existing brick to hang this on: "player" | "any" | "none"
#   bricks     list of {kind, title, params, at (layout slot)}
#   wires      [from_index, from_port, to_index, to_port] inside this recipe
#   hook_port  the input port index on bricks[0] the anchor connects to
#   note       what to tweak afterwards, shown after applying
# ---------------------------------------------------------------------------
const LIST := [
	{
		"key": "coins_and_score", "task": "Scoring",
		"name": "Coins that give points, win at ten",
		"pitch": "Touch a coin, it disappears and your score goes up. Win when the score reaches 10.",
		"anchor": "player", "hook_port": 0,
		"bricks": [
			{"kind": "collide", "title": "Touch a coin", "params": {"with": "coin", "action": "collect"}, "at": [0, 0]},
			{"kind": "score", "title": "Add 1 point", "params": {"variable": "score", "op": "add", "amount": 1}, "at": [1, 0]},
			{"kind": "winlose", "title": "Win at 10", "params": {"condition": "score_reaches", "value": 10}, "at": [2, 0]},
			{"kind": "spawn", "title": "Coin", "params": {"model": "coin", "position_y": 1.0}, "at": [0, 1]},
		],
		"wires": [[0, 0, 1, 0], [1, 0, 2, 0]],
		"note": "Change 'Win at 10' to whatever number you want, or add more Coin bricks.",
	},
	{
		"key": "ding_on_pickup", "task": "Feel",
		"name": "A sound and sparkles when you collect",
		"pitch": "Pure game feel: a coin ding plus a small burst every time you pick something up.",
		"anchor": "player", "hook_port": 0,
		"bricks": [
			{"kind": "collide", "title": "Touch a coin", "params": {"with": "coin", "action": "collect"}, "at": [0, 0]},
			{"kind": "sound", "title": "Coin ding", "params": {"kind": "coin", "volume": 0.7}, "at": [1, 0]},
			{"kind": "particles", "title": "Sparkle burst", "params": {"effect": "sparkle", "amount": 16.0, "color": "gold"}, "at": [2, 0]},
		],
		"wires": [[0, 0, 1, 0], [0, 0, 2, 0]],
		"note": "Swap the effect for 'confetti' or 'smoke' in the particles brick's settings.",
	},
	{
		"key": "patrolling_enemy", "task": "Hazards",
		"name": "An enemy that walks back and forth",
		"pitch": "A bad guy you can touch. Wire its output into Win/Lose or Health to make it hurt.",
		"anchor": "player", "hook_port": 0,
		"bricks": [
			{"kind": "enemy_patrol", "title": "Patrol enemy", "params": {"distance": 6.0, "speed": 3.0}, "at": [0, 0]},
			{"kind": "hazard", "title": "Spikes", "params": {"damage": 1.0}, "at": [0, 1]},
		],
		"wires": [],
		"note": "Raise 'Speed' to make it harder to dodge. Add Health if touching should not kill instantly.",
	},
	{
		"key": "health_and_hearts", "task": "Hazards",
		"name": "Hearts instead of instant death",
		"pitch": "Give the player 3 hearts; each hit takes one, and running out ends the game.",
		"anchor": "player", "hook_port": 0,
		"bricks": [
			{"kind": "health", "title": "3 hearts", "params": {"max": 3.0, "damage": 1.0}, "at": [0, 0]},
			{"kind": "hazard", "title": "What hurts you", "params": {"damage": 1.0}, "at": [0, 1]},
			{"kind": "hud", "title": "Show hearts", "params": {"widget": "hearts", "var_name": "health", "label": "Hearts"}, "at": [0, 2]},
		],
		"wires": [[1, 0, 0, 0]],
		"note": "The hearts display reads the 'health' variable — rename both together if you rename one.",
	},
	{
		"key": "countdown_timer", "task": "Rules",
		"name": "A 30 second countdown",
		"pitch": "Beat the clock: when it runs out the game is over.",
		"anchor": "player", "hook_port": 0,
		"bricks": [
			{"kind": "timer", "title": "30 seconds", "params": {"seconds": 30.0, "on_end": "lose"}, "at": [0, 0]},
			{"kind": "winlose", "title": "Time up = over", "params": {"condition": "time_up", "value": 30.0}, "at": [1, 0]},
		],
		"wires": [[0, 0, 1, 0]],
		"note": "Lower 'Seconds' for a harder game.",
	},
	{
		"key": "moving_platforms", "task": "World",
		"name": "A platform that moves",
		"pitch": "Something to ride across a gap, plus solid ground to start on.",
		"anchor": "player", "hook_port": 0,
		"bricks": [
			{"kind": "platform", "title": "Ground", "params": {"preset": "normal", "width": 12.0, "height": 1.0}, "at": [0, 0]},
			{"kind": "moving_platform", "title": "Ride this", "params": {"distance": 8.0, "speed": 3.0, "axis": "x"}, "at": [1, 0]},
		],
		"wires": [],
		"note": "Set 'Axis' to y for a lift, or raise 'Distance' to cross a wider gap.",
	},
	{
		"key": "two_levels_and_a_door", "task": "World",
		"name": "A second level with a door to it",
		"pitch": "A doorway that fades you into level 2 at a named start point.",
		"anchor": "player", "hook_port": 0,
		"bricks": [
			{"kind": "door", "title": "Door to level 2", "params": {"target_level": "2", "target_entry": "start", "transition": "fade"}, "at": [0, 0]},
			{"kind": "entry", "title": "Level 2 start", "params": {"marker": "start"}, "at": [0, 1]},
		],
		"wires": [],
		"note": "Give the door a 'Needs variable' to turn it into a locked door you need a key for.",
	},
	{
		"key": "key_door_and_counter", "task": "Rules",
		"name": "Collect a key, then open the door",
		"pitch": "Counting an item and gating a door behind it — the classic little puzzle.",
		"anchor": "player", "hook_port": 0,
		"bricks": [
			{"kind": "inventory", "title": "Count keys", "params": {"item": "key", "op": "add", "amount": 1, "need": 1}, "at": [0, 0]},
			{"kind": "collide", "title": "Touch the key", "params": {"with": "coin", "action": "collect"}, "at": [0, 1]},
			{"kind": "door", "title": "Locked door", "params": {"target_level": "2", "target_entry": "start", "needs_var": "keys"}, "at": [1, 0]},
		],
		"wires": [[1, 0, 0, 0]],
		"note": "'Needs variable' has to match a Variable brick's name once you add one for keys.",
	},
	{
		"key": "variable_and_rule", "task": "Rules",
		"name": "A switch, and a rule that reads it",
		"pitch": "'If switches >= 3 then win.' The building block for any game logic.",
		"anchor": "player", "hook_port": 0,
		"bricks": [
			{"kind": "variable", "title": "Switches", "params": {"name": "switches", "scope": "game", "type": "number", "op": "add", "amount": 1}, "at": [0, 0]},
			{"kind": "rule", "title": "Three switches win", "params": {"cond_source": "variable", "cond_var": "switches", "cond_op": ">=", "cond_value": 3, "actions": "win"}, "at": [1, 0]},
		],
		"wires": [[0, 0, 1, 0]],
		"note": "Rule conditions are how you do anything without a new brick type — edit the number, not the bricks.",
	},
	{
		"key": "title_screen", "task": "Menus",
		"name": "A title screen with a Play button",
		"pitch": "Your game opens on its own name with a button that starts it.",
		"anchor": "none", "hook_port": 0,
		"bricks": [
			{"kind": "screen", "title": "Title", "params": {"kind_of_screen": "main_menu", "title": "My Game", "subtitle": "Made with EasyForge", "show_on_start": true, "pause_game": true}, "at": [0, 0]},
			{"kind": "button", "title": "Play", "params": {"label": "Play", "action": "start"}, "at": [1, 0]},
			{"kind": "button", "title": "Quit", "params": {"label": "Quit", "action": "quit"}, "at": [2, 0]},
		],
		"wires": [[0, 0, 1, 0], [0, 0, 2, 0]],
		"note": "Say the controls on your title screen — a Menu Screen can show a subtitle, and players need to know which keys save.",
	},
	{
		"key": "pause_menu", "task": "Menus",
		"name": "A pause menu with Resume and Restart",
		"pitch": "Freezes the game and gives the player a way back in, or to start over.",
		"anchor": "any", "hook_port": 0,
		"bricks": [
			{"kind": "screen", "title": "Paused", "params": {"kind_of_screen": "pause", "title": "Paused", "show_on_start": false, "pause_game": true}, "at": [0, 0]},
			{"kind": "button", "title": "Resume", "params": {"label": "Resume", "action": "resume"}, "at": [1, 0]},
			{"kind": "button", "title": "Restart", "params": {"label": "Restart", "action": "restart"}, "at": [2, 0]},
		],
		"wires": [[0, 0, 1, 0], [0, 0, 2, 0]],
		"note": "The pause key is Esc by default — say so on your title screen.",
	},
	{
		"key": "game_over_screen", "task": "Menus",
		"name": "A game over screen that offers a retry",
		"pitch": "When you lose, a screen appears with a Retry button instead of a dead window.",
		"anchor": "any", "hook_port": 0,
		"bricks": [
			{"kind": "screen", "title": "Game over", "params": {"kind_of_screen": "game_over", "title": "Game Over", "subtitle": "Press retry", "show_on_start": false, "pause_game": true}, "at": [0, 0]},
			{"kind": "button", "title": "Retry", "params": {"label": "Retry", "action": "restart"}, "at": [1, 0]},
		],
		"wires": [[0, 0, 1, 0]],
		"note": "Set your Win/Lose brick to 'lose' so this screen has a reason to appear.",
	},
	{
		"key": "music_and_backdrop", "task": "Feel",
		"name": "Background music, sky and scrolling scenery",
		"pitch": "Three bricks and the game stops looking like a grey test room.",
		"anchor": "any", "hook_port": 0,
		"bricks": [
			{"kind": "audio", "title": "Music loop", "params": {"sound_kind": "theme", "bus": "music", "volume_db": -8.0, "play_on_start": true, "loop": true}, "at": [0, 0]},
			{"kind": "sky", "title": "Night sky", "params": {"preset": "night"}, "at": [0, 1]},
			{"kind": "background", "title": "Hills", "params": {"theme": "dusk", "layers": 3.0}, "at": [0, 2]},
		],
		"wires": [],
		"note": "Try the Sky preset 'sunset' or the Background theme 'city' to change the whole mood.",
	},
	{
		"key": "save_point", "task": "Sharing",
		"name": "A save point the player can come back to",
		"pitch": "Writes progress to the player's PC, and reads it back.",
		"anchor": "any", "hook_port": 0,
		"bricks": [
			{"kind": "checkpoint_save", "title": "Save point", "params": {"slot": 1.0, "size": 2.0, "once": false}, "at": [0, 0]},
			{"kind": "save", "title": "Save on F5", "params": {"mode": "manual", "slot": 1.0, "key": "F5"}, "at": [0, 1]},
		],
		"wires": [],
		"note": "Tell players which key saves — put it on your title screen.",
	},
	{
		"key": "coin_row_blueprint", "task": "World",
		"name": "A row of eight coins from one definition",
		"pitch": "Define 'a coin' once, then place many copies lined up for you.",
		"anchor": "any", "hook_port": 0,
		"bricks": [
			{"kind": "blueprint_def", "title": "Coin definition", "params": {"name": "coin", "description": "spins, gives a point"}, "at": [0, 0]},
			{"kind": "blueprint", "title": "Eight coins", "params": {"blueprint_name": "coin", "count": 8, "layout": "row", "spread": 3.0}, "at": [1, 0]},
		],
		"wires": [[0, 0, 1, 0]],
		"note": "Change 'Count' or set 'Layout' to grid for a block of coins.",
	},
	{
		"key": "smart_enemy_3d", "task": "Smart",
		"name": "An enemy that walks around walls to reach you",
		"pitch": "Pathfinding in 3D: the enemy routes around geometry instead of pressing into it.",
		"anchor": "any", "hook_port": 0,
		"bricks": [
			{"kind": "spawn", "title": "Enemy", "params": {"model": "enemy", "position_y": 1.0}, "at": [0, 0]},
			{"kind": "pathfind", "title": "Find the player", "params": {"mode": "chase", "target": "player", "speed": 4.0, "draw_path": false}, "at": [1, 0]},
		],
		"wires": [[0, 0, 1, 0]],
		"note": "This needs a 3D game; 2D pathfinding has no navmesh yet.",
	},
]

static func list() -> Array:
	return LIST

static func find(key: String) -> Dictionary:
	for r in LIST:
		if str(r.get("key", "")) == key:
			return r
	return {}

## Task groups present, in the order they should be read.
static func tasks() -> Array:
	var out: Array = []
	for r in LIST:
		var t := str(r.get("task", "Other"))
		if not t in out:
			out.append(t)
	return out

static func for_task(task: String) -> Array:
	var out: Array = []
	for r in LIST:
		if str(r.get("task", "")) == task:
			out.append(r)
	return out

## Every kind this recipe adds — the Manual uses it to link a recipe to bricks.
static func kinds_in(key: String) -> Array:
	var out: Array = []
	for b in find(key).get("bricks", []):
		out.append(str((b as Dictionary).get("kind", "")))
	return out

## Add this recipe to a live graph. `anchor_id` is the brick its output wires
## into the first new brick ("" when the recipe stands alone).
## Returns {ok, added: [brick ids], wired: int, skipped: [strings], message}.
## Nothing here can fail hard: a bad kind, a missing port, or a wire the type
## rules reject is reported in `skipped` and the rest still lands.
static func add_to(graph, key: String, anchor_id: String = "") -> Dictionary:
	var result := {"ok": false, "added": [], "wired": 0, "skipped": [], "message": ""}
	var recipe := find(key)
	if recipe.is_empty():
		result["message"] = "No such recipe: %s" % key
		return result
	if graph == null:
		result["message"] = "No graph to add to."
		return result
	var made: Array = []
	for entry in recipe.get("bricks", []):
		var e: Dictionary = entry if entry is Dictionary else {}
		var kind := str(e.get("kind", ""))
		var b := BrickRef.create(kind, str(e.get("title", "")), "")
		if b.is_empty():
			(result["skipped"] as Array).append("cannot create '%s'" % kind)
			continue
		var p: Dictionary = b.get("params", {})
		for pk in (e.get("params", {}) as Dictionary):
			p[pk] = (e.get("params", {}) as Dictionary)[pk]
		b["params"] = p
		if not graph.add_brick(b):
			(result["skipped"] as Array).append("'%s' was refused" % kind)
			continue
		made.append(b)
	for b in made:
		(result["added"] as Array).append(str(b.get("id", "")))
	if made.is_empty():
		result["message"] = "Nothing could be added."
		return result

	# 1. hook the anchor into the first brick the recipe declares as the entry
	var hook_index := 0
	var anchor := anchor_id
	if anchor.is_empty() and graph.has_method("get_brick"):
		anchor = _find_player_id(graph)
	var hook_port := int(recipe.get("hook_port", 0))
	var first: Dictionary = made[hook_index]
	if not anchor.is_empty():
		var a: Dictionary = graph.get_brick(anchor) if graph.has_method("get_brick") else {}
		if not a.is_empty() and _wire_best(graph, str(a.get("id", "")), first, hook_port):
			result["wired"] = int(result["wired"]) + 1
		elif anchor.is_empty():
			(result["skipped"] as Array).append("no brick to hook onto")

	# 2. the recipe's own internal wires
	for w in recipe.get("wires", []):
		var arr: Array = w if w is Array else []
		if arr.size() < 4:
			continue
		var fi := int(arr[0]); var fj := int(arr[2])
		if fi >= made.size() or fj >= made.size():
			(result["skipped"] as Array).append("wire %s out of range" % str(arr))
			continue
		var from_id := str(made[fi].get("id", ""))
		var to_id := str(made[fj].get("id", ""))
		if graph.wire(from_id, int(arr[1]), to_id, int(arr[3])):
			result["wired"] = int(result["wired"]) + 1
		else:
			(result["skipped"] as Array).append("%s -> %s ports do not fit" % [
				made[fi].get("kind", "?"), made[fj].get("kind", "?")])

	var names: Array = []
	for b in made:
		names.append(str(b.get("title", "")))
	result["ok"] = true
	result["message"] = "Added %s." % ", ".join(names)
	if not (result["skipped"] as Array).is_empty():
		result["message"] += " Skipped: %s." % "; ".join(result["skipped"])
	return result

## The first player-spawn in the graph, or "" — recipes that hang off "you".
static func _find_player_id(graph) -> String:
	for b in graph.bricks:
		if str(b.get("kind", "")) != "spawn":
			continue
		var p: Dictionary = b.get("params", {})
		if str(p.get("model", "player")) == "player":
			return str(b.get("id", ""))
	return ""

## Wire `from`'s best output into `to`'s preferred input, trying the other ports
## if the obvious pair does not type-check. Returns whether a wire landed.
static func _wire_best(graph, from_id: String, to: Dictionary, to_port: int) -> bool:
	var from: Dictionary = graph.get_brick(from_id)
	if from.is_empty():
		return false
	var to_in: Array = to.get("inputs", [])
	var want_port := clampi(to_port, 0, maxi(to_in.size() - 1, 0))
	var out_count: int = (from.get("outputs", []) as Array).size()
	for p in out_count:
		if graph.wire(from_id, p, str(to.get("id", "")), want_port):
			return true
	# the recipe's chosen input port was wrong for that output — try its other inputs
	for i in to_in.size():
		if i == want_port:
			continue
		for p in out_count:
			if graph.wire(from_id, p, str(to.get("id", "")), i):
				return true
	return false
