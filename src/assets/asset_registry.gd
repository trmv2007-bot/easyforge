extends Node   # autoloads must inherit Node
## Assets — the built-in art library, and the only way a brick reaches a file.
##
## Bricks name a LOOK ("grass", "coin", "penguin"), never a path, so a pack can be
## swapped, extended or stripped without touching the compiler. Every lookup
## returns null when the file is missing and the caller falls back to a primitive,
## so a build without assets still runs — that is what the smoke test asserts.
##
## Pack: Kenney "Pixel Platformer" 1.2, Creative Commons Zero (CC0),
## assets/kenney/pixel-platformer/License.txt. Tiles are 18x18, characters 24x24.

const TILES := "res://assets/kenney/pixel-platformer/Tiles/"
const CHARS := "res://assets/kenney/pixel-platformer/Tiles/Characters/"

## Named looks, picked by rendering the sheet and reading the indices.
## "grass" is tile_0002, not tile_0000: the earlier tiles carry dark side
## posts that read as a fence line when repeated along the floor.
const LOOKS := {
	"grass":		"tile_0002.png",	# green top on dirt, clean edges — the 2D ground surface
								# (3D ground stays procedural: a cross-section tile
								# stripes badly when tiled flat — see the compiler)
	"dirt":			"tile_0004.png",	# plain fill under the grass line
	"snowy":		"tile_0081.png",	# snow-capped dirt — winter ground
	"wood":			"tile_0080.png",	# platform / crate
	"brick":		"tile_0016.png",	# solid block
	"question":		"tile_0018.png",	# block with a "?" — bonus box
	"coin":			"tile_0152.png",	# gold ring
	"gem":			"tile_0067.png",	# blue diamond
	"heart":		"tile_0044.png",	# health pickup
	"spike":		"tile_0068.png",	# floor spikes
	"trap":			"tile_0064.png",	# spike on a post
	"arrow":		"tile_0085.png",	# direction sign
	"tree":			"tile_0097.png",
	"pine":			"tile_0126.png",	# fir — a taller, pointier tree
	"cactus":		"tile_0127.png",
	"mushroom":		"tile_0109.png",
	"mushroom_red":	"tile_0108.png",
	"plant":		"tile_0124.png",
	"sprout":		"tile_0125.png",	# twin green shoots
	"bamboo":		"tile_0096.png",	# leafy stalk
	"ladder":		"tile_0106.png",
	"water":		"tile_0054.png",
	"snow":			"tile_0093.png",
	"penguin":		"tile_0145.png",	# waddling menace
	"key":			"tile_0026.png",
	"door":			"tile_0148.png",
}

## The spawn brick's four canonical models, mapped to character tiles.
const MODELS := {
	"player": {"dir": CHARS, "file": "tile_0006.png"},
	"enemy":	{"dir": CHARS, "file": "tile_0024.png"},
	"coin":		{"dir": TILES, "file": "tile_0152.png"},
	"box":		{"dir": TILES, "file": "tile_0080.png"},
}

var _cache := {}

## True when this look exists on disk. Cheap: checked once per name.
func has(look: String) -> bool:
	return texture(look) != null

## A pixel-art texture, cached, or null. Nearest filtering is forced by the
## callers that use it — smoothing 18px tiles turns the whole game to mush.
func texture(look: String) -> Texture2D:
	if _cache.has(look):
		return _cache[look]
	var tex: Texture2D = null
	var file := str(LOOKS.get(look, ""))
	if not file.is_empty():
		var path := TILES.path_join(file)
		if ResourceLoader.exists(path):
			tex = load(path)
	_cache[look] = tex
	return tex

## Texture for a spawn model name ("player", "enemy", "coin", "box"), and also
## for any look name the user typed — so "penguin" works as a model.
func model_texture(model: String) -> Texture2D:
	var key := model.strip_edges().to_lower()
	if key.is_empty():
		return null
	var cache_key := "model:" + key
	if _cache.has(cache_key):
		return _cache[cache_key]
	var tex: Texture2D = null
	if MODELS.has(key):
		var path := str(MODELS[key]["dir"]).path_join(str(MODELS[key]["file"]))
		if ResourceLoader.exists(path):
			tex = load(path)
	else:
		tex = texture(key)
	_cache[cache_key] = tex
	return tex

## Names the inspector can offer as a model choice.
func model_choices() -> Array:
	var out: Array = MODELS.keys()
	for k in LOOKS.keys():
		if not out.has(k):
			out.append(k)
	return out

## Pixel size of a tile, so the compiler can scale sprites consistently.
func tile_px(look: String) -> int:
	var tex := texture(look)
	if tex == null:
		return 18
	return tex.get_width()
