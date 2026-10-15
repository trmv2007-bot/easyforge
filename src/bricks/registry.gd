extends Node   # autoloads must inherit Node
## BrickRegistry — the "brick library per genre" (spec: universality = depth).
##
## Registered as the autoload singleton "BrickRegistry" (project.godot), so
## scripts call BrickRegistry.kind_icon(...) directly.
##
## The 5 universal kinds are always available. Genre packs register extra
## concrete bricks (chess "capture", racing "checkpoint", VN "dialogue").
## v1 registers the platformer pack so the AI + palette can use them.
## Adding a genre = one call to register_pack(). Nothing else changes.

var _packs := {}          # genre -> {brick_kind: meta}

func _ready() -> void:
	# in _ready (not _init) so BrickRef is fully resolved first
	register_pack("platformer")

# Universal "logic" kinds live in BrickRef.KIND directly, so they always appear
# in the palette (all_kinds() unions BrickRef.KIND with every registered pack).
# The platformer pack below adds the genre-specific solid/enemy bricks.

func register_pack(genre: String) -> void:
	match genre:
		"platformer":
			_packs[genre] = {
				"moving_platform": {"label": "Moving Platform", "icon": "🛗", "in": [BrickRef.PortType.FLOW], "out": [BrickRef.PortType.FLOW]},
				"enemy_patrol":    {"label": "Enemy Patrol",   "icon": "👾", "in": [BrickRef.PortType.FLOW], "out": [BrickRef.PortType.EVENT]},
				"hazard":          {"label": "Hazard",         "icon": "🔥", "in": [BrickRef.PortType.FLOW], "out": [BrickRef.PortType.EVENT]},
				"checkpoint":      {"label": "Checkpoint",     "icon": "🚩", "in": [BrickRef.PortType.FLOW], "out": [BrickRef.PortType.FLOW]},
				"timer":           {"label": "Timer",          "icon": "⏱️", "in": [BrickRef.PortType.EVENT], "out": [BrickRef.PortType.EVENT]},
				"follow":          {"label": "Follow",         "icon": "🧲", "in": [BrickRef.PortType.FLOW], "out": [BrickRef.PortType.EVENT]},
				"destroy":         {"label": "Destroy",        "icon": "💥", "in": [BrickRef.PortType.EVENT], "out": [BrickRef.PortType.FLOW]},
			}
		"topdown":
			_packs[genre] = {
				"npc":        {"label": "NPC",        "icon": "🧑", "in": [BrickRef.PortType.FLOW], "out": [BrickRef.PortType.EVENT]},
				"quest":      {"label": "Quest",      "icon": "📜", "in": [BrickRef.PortType.EVENT], "out": [BrickRef.PortType.FLOW]},
				"inventory":  {"label": "Inventory",  "icon": "🎒", "in": [BrickRef.PortType.EVENT], "out": [BrickRef.PortType.FLOW]},
			}
		"shooter":
			_packs[genre] = {
				"bullet":   {"label": "Bullet",   "icon": "🔸", "in": [BrickRef.PortType.EVENT], "out": [BrickRef.PortType.FLOW]},
				"health":   {"label": "Health",   "icon": "❤️", "in": [BrickRef.PortType.EVENT], "out": [BrickRef.PortType.VALUE]},
				"ammo":     {"label": "Ammo",     "icon": "🧨", "in": [BrickRef.PortType.EVENT], "out": [BrickRef.PortType.FLOW]},
			}

func all_kinds() -> Dictionary:
	var out := {}
	# universal first
	for k in BrickRef.KIND:
		out[k] = BrickRef.KIND[k]
	# then every registered pack (v1 has platformer loaded by default)
	for genre in _packs:
		for k in _packs[genre]:
			out[k] = _packs[genre][k]
	return out

## What the UI calls a brick. The friendly, plain-English name from BrickDocs
## wins; the IR label ("Pathfind") is only a fallback, because the label is
## part of the saved project and the AI vocabulary and must not churn.
func kind_label(kind: String) -> String:
	var docs := BrickDocs.entry_for(kind)
	if not str(docs.get("name", "")).is_empty():
		return str(docs["name"])
	var all := all_kinds()
	if all.has(kind):
		var meta = all[kind]
		if meta is Dictionary and meta.has("label"):
			return str(meta["label"])
	return kind

func kind_icon(kind: String) -> String:
	# a docs override exists where two bricks shared one glyph (the two "Sound"
	# bricks both used 🔊, respawn and win both used 🚩)
	var override := BrickDocs.icon_for(kind)
	if not override.is_empty():
		return override
	var all := all_kinds()
	if all.has(kind):
		var meta = all[kind]
		if meta is Dictionary and meta.has("icon"):
			return str(meta["icon"])
	return "🧩"

## Which palette group this kind belongs to, and how much of a beginner needs it.
func kind_category(kind: String) -> String:
	return BrickDocs.category_of(kind)

func kind_tier(kind: String) -> String:
	return BrickDocs.tier_of(kind)

func available_genres() -> Array:
	return _packs.keys()
