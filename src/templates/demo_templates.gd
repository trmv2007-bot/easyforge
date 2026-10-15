extends RefCounted
## DemoTemplates — hardcoded, zero-API-key projects that prove the ENTIRE
## pipeline (bricks -> compile -> play) works with no AI key. The friend can
## play a real game on first launch, then describe his own once he adds a key.

class_name DemoTemplates

## The v1 platformer demo: spawn -> move -> collide -> score -> winlose,
## fully pre-connected. This is ALSO the guided-tutorial game (it teaches all
## 5 universal bricks in one pass).
static func platformer() -> Dictionary:
	var spawn := BrickRef.create("spawn", "Player", "")
	var move := BrickRef.create("move", "Run & Jump", "")
	var collide := BrickRef.create("collide", "Touch a coin", "I want coins to give points")
	var score := BrickRef.create("score", "Add score", "")
	var win := BrickRef.create("winlose", "Win at 10 points", "")
	var cam := BrickRef.create("camera", "Follow camera", "camera follows the player")

	spawn["params"]["model"] = "player"
	move["params"]["style"] = "platformer"
	move["params"]["speed"] = 8.0
	move["params"]["jump"] = 12.0
	collide["params"]["with"] = "coin"
	score["params"]["variable"] = "score"
	score["params"]["op"] = "add"
	score["params"]["amount"] = 1
	win["params"]["condition"] = "score_reaches"
	win["params"]["value"] = 10
	cam["params"]["mode"] = "follow"
	cam["params"]["distance"] = 10.0
	cam["params"]["height"] = 6.0
	cam["params"]["smooth"] = true

	# pre-connect: spawn -> move -> collide -> score -> winlose
	spawn["connections"] = [{"from_out": 0, "to_brick": move["id"], "to_in": 0}]
	move["connections"] = [{"from_out": 0, "to_brick": collide["id"], "to_in": 0}]
	collide["connections"] = [{"from_out": 0, "to_brick": score["id"], "to_in": 0}]
	score["connections"] = [{"from_out": 0, "to_brick": win["id"], "to_in": 0}]
	# camera reads the player (spawn) — connect spawn -> camera
	spawn["connections"].append({"from_out": 0, "to_brick": cam["id"], "to_in": 0})

	return {
		"project_name": "Coin Dash",
		"dimension": "3d",
		"genre": "platformer",
		"bricks": [spawn, move, collide, score, win, cam],
	}

## A 2D proof that the pipeline is dimension-agnostic (spec rule 7).
static func side_scroller_2d() -> Dictionary:
	var d := platformer()
	d["project_name"] = "Coin Dash 2D"
	d["dimension"] = "2d"
	for b in d["bricks"]:
		if b["kind"] == "spawn":
			b["params"]["position"] = [0, 200, 0]
	return d

## An empty graph the user builds from scratch (AI-required; offered in UI).
static func blank(genre: String = "platformer", dimension: String = "3d") -> Dictionary:
	return {
		"project_name": "My Game",
		"dimension": dimension,
		"genre": genre,
		"bricks": [],
	}

# ---------------------------------------------------------------------------
# Wave 3 — genre demo gallery. Each demo is a complete, playable brick graph
# the user clones and tweaks (the "clone-first New Project" pattern every
# no-code engine uses). Kept small: one screen, obvious goals, tuned defaults.
# ---------------------------------------------------------------------------

## Top-down shooter: the canonical beginner genre (Construct's Ghost Shooter).
## Player aims with the mouse, shoots enemies, scores, wins at 10 kills.
static func topdown_shooter() -> Dictionary:
	var spawn := BrickRef.create("spawn", "Player", "")
	spawn["params"]["model"] = "player"
	var move := BrickRef.create("move", "8-way Move", "top-down movement, no gravity")
	move["params"]["style"] = "topdown"
	move["params"]["speed"] = 10.0
	var enemy := BrickRef.create("enemy_patrol", "Enemy", "chases the player")
	enemy["params"]["speed"] = 3.0
	var score := BrickRef.create("score", "Kill = +1", "")
	score["params"]["variable"] = "kills"
	score["params"]["op"] = "add"
	score["params"]["amount"] = 1
	var win := BrickRef.create("winlose", "Win at 10 kills", "")
	win["params"]["condition"] = "score_reaches"
	win["params"]["value"] = 10
	var cam := BrickRef.create("camera", "Follow camera", "")
	cam["params"]["mode"] = "follow"
	cam["params"]["distance"] = 14.0
	var sky := BrickRef.create("sky", "Night sky", "")
	sky["params"]["preset"] = "night"
	spawn["connections"] = [
		{"from_out": 0, "to_brick": move["id"], "to_in": 0},
		{"from_out": 0, "to_brick": cam["id"], "to_in": 0},
		{"from_out": 0, "to_brick": sky["id"], "to_in": 0},
	]
	move["connections"] = [{"from_out": 0, "to_brick": enemy["id"], "to_in": 0}]
	enemy["connections"] = [{"from_out": 0, "to_brick": score["id"], "to_in": 0}]
	score["connections"] = [{"from_out": 0, "to_brick": win["id"], "to_in": 0}]
	return {
		"project_name": "Star Shooter",
		"dimension": "3d",
		"genre": "shooter",
		"bricks": [spawn, move, enemy, score, win, cam, sky],
	}

## Endless runner: auto-scroll, jump over obstacles, survive. Reuses the
## platformer movement + hazards; the AutoScroll feel comes from a fast
## forward camera bias baked into the demo's defaults.
static func endless_runner() -> Dictionary:
	var spawn := BrickRef.create("spawn", "Runner", "")
	spawn["params"]["model"] = "player"
	var move := BrickRef.create("move", "Run & Jump", "keep jumping to survive")
	move["params"]["style"] = "platformer"
	move["params"]["speed"] = 14.0
	move["params"]["jump"] = 14.0
	var hazard := BrickRef.create("hazard", "Obstacle", "touch = lose a life")
	var score := BrickRef.create("score", "+1 per second alive", "")
	score["params"]["variable"] = "distance"
	score["params"]["amount"] = 1
	var lose := BrickRef.create("winlose", "Out of lives = over", "")
	lose["params"]["condition"] = "score_drops"
	lose["params"]["value"] = 0
	var cam := BrickRef.create("camera", "Follow camera", "")
	cam["params"]["mode"] = "follow"
	var bg := BrickRef.create("background", "Sunset hills", "")
	bg["params"]["theme"] = "dusk"
	bg["params"]["layers"] = 3
	spawn["connections"] = [
		{"from_out": 0, "to_brick": move["id"], "to_in": 0},
		{"from_out": 0, "to_brick": cam["id"], "to_in": 0},
		{"from_out": 0, "to_brick": bg["id"], "to_in": 0},
	]
	move["connections"] = [{"from_out": 0, "to_brick": hazard["id"], "to_in": 0}]
	return {
		"project_name": "Endless Dash",
		"dimension": "2d",
		"genre": "platformer",
		"bricks": [spawn, move, hazard, score, lose, cam, bg],
	}

## Visual novel: the cheapest genre to ship (linear dialogue, no physics).
## Say lines, branch on a variable, win when the story completes.
static func visual_novel() -> Dictionary:
	var spawn := BrickRef.create("spawn", "Hero", "")
	spawn["params"]["model"] = "player"
	var say := BrickRef.create("sound", "Narrate", "a line of dialogue")
	say["params"]["kind"] = "click"
	var var1 := BrickRef.create("variable", "Story progress", "")
	var1["params"]["name"] = "story"
	var1["params"]["op"] = "add"
	var1["params"]["amount"] = 1
	var rule := BrickRef.create("rule", "End when story done", "")
	rule["params"]["cond_source"] = "variable"
	rule["params"]["cond_var"] = "story"
	rule["params"]["cond_op"] = ">="
	rule["params"]["cond_value"] = 5
	rule["params"]["actions"] = "win"
	var bg := BrickRef.create("background", "Scene backdrop", "")
	bg["params"]["theme"] = "candy"
	spawn["connections"] = [
		{"from_out": 0, "to_brick": say["id"], "to_in": 0},
		{"from_out": 0, "to_brick": var1["id"], "to_in": 0},
		{"from_out": 0, "to_brick": bg["id"], "to_in": 0},
	]
	var1["connections"] = [{"from_out": 0, "to_brick": rule["id"], "to_in": 0}]
	return {
		"project_name": "Little Story",
		"dimension": "2d",
		"genre": "topdown",
		"bricks": [spawn, say, var1, rule, bg],
	}

## The gallery the New Project dialog shows. Each entry: name, pitch, builder.
static func gallery() -> Array:
	return [
		{"name": "Coin Dash", "pitch": "3D platformer — collect coins, dodge enemies", "dimension": "3d", "build": "platformer"},
		{"name": "Coin Dash 2D", "pitch": "Pixel-art platformer in flat 2D", "dimension": "2d", "build": "side_scroller_2d"},
		{"name": "Star Shooter", "pitch": "Top-down shooter — aim, shoot, win at 10 kills", "dimension": "3d", "build": "topdown_shooter"},
		{"name": "Endless Dash", "pitch": "2D runner — jump obstacles, survive", "dimension": "2d", "build": "endless_runner"},
		{"name": "Little Story", "pitch": "Visual novel — dialogue and choices", "dimension": "2d", "build": "visual_novel"},
	]

## Build a gallery demo by its builder key.
static func build(key: String) -> Dictionary:
	match key:
		"side_scroller_2d": return side_scroller_2d()
		"topdown_shooter": return topdown_shooter()
		"endless_runner": return endless_runner()
		"visual_novel": return visual_novel()
		_: return platformer()
