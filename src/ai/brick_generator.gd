extends Node
## AiBrickGenerator — the two-phase AI (spec §"The AI's job").
##
## Phase A (draft): user describes a game -> AI returns a COMPLETE brick graph
##   as JSON (never empty, never partial). We parse + validate it.
## Phase B (finalize): user has wired the graph their way -> AI reads the
##   finished graph and returns adjusted code-level fixes (renamed bricks,
##   corrected params) which we merge back into the graph.
##
## The system prompt carries the brick schema so the model emits exactly our
## IR. Session memory (spec rule 9) = we always send the current compact brick
## JSON + conversation, never a vector store.

signal draft_ready(graph_dict: Dictionary)
signal draft_failed(message: String)
signal finalize_ready(notes: String)
signal finalize_failed(message: String)

const SYSTEM_PROMPT := """You are EasyForge, a game designer assistant. You output ONLY JSON.
The user describes a game in plain English. You reply with a COMPLETE game as a JSON object using exactly this schema:

{
  "project_name": string,
  "dimension": "3d" or "2d",
  "genre": "platformer" | "topdown" | "shooter",
  "bricks": [ BRICK, ... ]
}

Each BRICK:
{
  "id": unique short string,
  "kind": one of the kinds in BRICK VOCABULARY at the end of this prompt,
  "title": short human name,
  "comment": "",
  "inputs": [{"name": string, "type": 0}],
  "outputs": [{"name": string, "type": 1}],
  "params": { ... },
  "connections": [{"from_out": 0, "to_brick": "<id>", "to_in": 0}]
}

Port types: 0=flow, 1=event, 2=value.
ALWAYS include at least one "spawn" brick so the game is never empty.
ALWAYS wire spawn -> move -> collide -> score -> winlose where it makes sense.
A spawn "model" is "player", "enemy", "coin", "box", or any built-in art look:
grass, dirt, snowy, wood, brick, question, gem, heart, spike, trap, arrow, tree,
pine, cactus, mushroom, mushroom_red, plant, sprout, bamboo, ladder, water,
snow, penguin, key, door. Use these names for props and pickups.

VARIABLE brick — a named value (number or bool) with a scope. params:
  {"name": "coins", "scope": "game"|"player", "type": "number"|"bool",
   "op": "add"|"set"|"toggle", "amount": 1, "value": 0}
Wire collide -> variable so touching the object changes the value.

RULE brick — "if <condition> then <actions>". The most powerful brick; use it
for anything conditional. params:
  {"cond_source": "variable"|"key"|"collided"|"timer",
   "cond_var": "coins", "cond_op": ">="|"=="|"<="|"!="|">"|"<",
   "cond_value": 3, "cond_key": "Space"|"E"|"F"|"Enter"|"Shift",
   "actions": "win,lose,hit_stop,slowmo,normal_time,add_var:NAME,set_var:NAME:VALUE,toggle_var:NAME,play_sound:coin,wait:1"}
  (actions is a comma-separated list; a Rule can do several things at once.)
Example — "collect 3 coins then win": collide->variable(name=coins,op=add)
  then a Rule {cond_source:variable, cond_var:coins, cond_op:">=",
  cond_value:3, actions:"win"}.
Output ONLY the JSON object. No markdown, no explanation."""

func _llm() -> LlmClient:
	return get_node_or_null("/root/LlmClient")

## The system prompt, built for THIS request.
##
## Two fixes over the old constant-only prompt. (1) The kind list baked into
## SYSTEM_PROMPT was a 23-kind snapshot of a 50-kind palette — and four of the
## names it offered (npc, quest, bullet, ammo) have no compiler module behind
## them, so the model asked for bricks that silently did nothing. The vocabulary
## is now read from the registry, which is the same list the palette shows and the
## compiler builds. (2) The genre detected from the user's own words is appended,
## with the bricks that genre normally uses and how they wire together — so
## "make a racing game" gets checkpoints, a lap counter and a timer instead of a
## platformer with cars in it.
func _system_prompt(user_description: String = "") -> String:
	var genre := GenreLibrary.detect(user_description)
	var vocab := GenreLibrary.vocabulary()
	var text := SYSTEM_PROMPT
	if not vocab.is_empty():
		text += "\n\nBRICK VOCABULARY (use ONLY these kinds, spelled exactly):\n" + ", ".join(vocab)
	text += GenreLibrary.prompt_block(genre)
	return text

## Which genre the words describe ("" when nothing matched). The UI shows this so
## a guess is never presented as understanding.
func detected_genre(user_description: String) -> String:
	return GenreLibrary.detect(user_description)

## Build a game without any AI at all — no key, no network, deterministic.
## Returns {graph, genre, named}: `named` is false when the genre was a guess,
## which the UI must say out loud rather than hide.
func offline_draft(user_description: String) -> Dictionary:
	var genre := GenreLibrary.detect(user_description)
	var named := not genre.is_empty()
	var key := genre if named else GenreLibrary.DEFAULT_GENRE
	return {
		"graph": GenreLibrary.build(key, _title_from(user_description)),
		"genre": key,
		"named": named,
	}

## A project name from the first clause of what they typed, kept short because it
## becomes the window title and the shared .exe file name.
static func _title_from(text: String) -> String:
	var clean := " ".join(text.replace("\n", " ").split(" ", false))
	if clean.is_empty():
		return "My Game"
	var cut := clean
	for sep in [" about ", " where ", " that ", " with ", ", "]:
		var at := cut.to_lower().find(sep)
		if at > 3:
			cut = cut.substr(0, at)
			break
	if cut.length() > 34:
		cut = cut.substr(0, cut.rfind(" ", 34) if cut.rfind(" ", 34) > 8 else 34)
	return cut.strip_edges().capitalize()

# ---------------------------------------------------------------------------
# Phase A — draft a complete graph from a plain-English description.
# ---------------------------------------------------------------------------
func generate_draft(user_description: String) -> void:
	var llm := _llm()
	if llm == null:
		draft_failed.emit("AI not available.")
		return
	if llm.needs_key() and llm.api_key.strip_edges().is_empty():
		draft_failed.emit(I18n.t("no_key_body"))
		return
	var messages := [
		{"role": "system", "content": _system_prompt(user_description)},
		{"role": "user", "content": "Build this game: " + user_description},
	]
	llm.chat(messages, 12288)
	if not llm.chat_done.is_connected(_on_draft_response):
		llm.chat_done.connect(_on_draft_response)
		llm.chat_failed.connect(func(msg): draft_failed.emit(msg))

func _on_draft_response(text: String) -> void:
	var parsed := _extract_json(text)
	if parsed.is_empty():
		# without this a failure is undebuggable: the user sees one generic line
		# and nobody can tell truncated JSON from prose from an empty reply
		push_warning("[ai] reply not readable as a game (%d chars): %s" % [
			text.length(), text.substr(0, 260).replace("\n", " ")])
		draft_failed.emit(I18n.t("ai_failed"))
		return
	# hard guarantee: never hand the user an empty graph
	var bricks: Array = parsed.get("bricks", [])
	if bricks.is_empty():
		draft_failed.emit(I18n.t("bad_reply"))
		return
	draft_ready.emit(parsed)

# ---------------------------------------------------------------------------
# Phase B — user wired the graph; AI finalizes the code wiring.
# We send the current graph + the user's comments and ask for adjustments.
# ---------------------------------------------------------------------------
func finalize(graph_dict: Dictionary) -> void:
	var llm := _llm()
	if llm == null:
		finalize_failed.emit("AI not available.")
		return
	if llm.needs_key() and llm.api_key.strip_edges().is_empty():
		finalize_failed.emit(I18n.t("no_key_body"))
		return
	var messages := [
		{"role": "system", "content": _system_prompt(str(graph_dict.get("project_name", "")))},
		{"role": "user", "content":
			"The user has wired this graph. Review it and return the SAME JSON with corrected params, better titles, and fixed connections so it runs as a real game. Keep every brick the user added. Current graph:\n"
			+ JSON.stringify(graph_dict)},
	]
	llm.chat(messages, 12288)
	if not llm.chat_done.is_connected(_on_finalize_response):
		llm.chat_done.connect(_on_finalize_response)
		llm.chat_failed.connect(func(msg): finalize_failed.emit(msg))

func _on_finalize_response(text: String) -> void:
	var parsed := _extract_json(text)
	if parsed.is_empty():
		finalize_failed.emit(I18n.t("ai_failed"))
		return
	# merge: keep user's bricks, take AI's params/titles/connection fixes
	draft_ready.emit(parsed)
	finalize_ready.emit(I18n.t("ai_edit_done"))

# ---------------------------------------------------------------------------
# Wave 3 — ITERATIVE EDIT: the conversation IS the editor. Instead of
# regenerating the whole graph, the AI returns a structured diff (ops) over
# the CURRENT graph. This is far more reliable than chat-to-code: the closed
# brick vocabulary means unknown concepts get composed, not hallucinated.
#
# Diff shape:
#   {"summary": "...", "ops": [
#       {"op": "add",    "type": "enemy_patrol", "params": {...}},
#       {"op": "modify", "id": "<id>", "params": {...}},
#       {"op": "remove", "id": "<id>"},
#       {"op": "connect","from": "<id>", "to": "<id>"}
#   ]}
# ---------------------------------------------------------------------------
signal edit_ready(diff: Dictionary)
signal edit_failed(message: String)

const EDIT_PROMPT := """You are EasyForge's game editor. The user has an existing game (a brick graph) and asks for a change. Reply with ONLY a JSON diff, NOT a whole new game.

Current graph bricks (id / kind / key params):
%s

Reply with EXACTLY this JSON shape:
{
  "summary": "one short plain-English sentence of what you changed",
  "ops": [ OP, ... ]
}
Each OP is one of:
  {"op":"add","type":"<brick kind>","params":{...}}          add a new brick
  {"op":"modify","id":"<existing id>","params":{...}}        change a brick's params
  {"op":"remove","id":"<existing id>"}                        delete a brick
  {"op":"connect","from":"<id>","to":"<id>"}                  wire one brick to another
  {"op":"disconnect","from":"<id>","to":"<id>"}               remove a wire

Valid brick kinds: see the BRICK VOCABULARY list appended below — use those names
exactly, and use any of them (the whole palette is available, not a starter set).
Adding a Screen + Button is how a menu appears, Pathfind/State/Perceive are how an
enemy gets smart, and Hud is how a number shows on screen.
For a rule brick params use: {"cond_source":"variable"|"key"|"collided"|"timer",
"cond_var":"<name>","cond_op":">="|"=="|"<="|"!="|">"|"<","cond_value":N,
"cond_key":"Space"|"E"|"F","actions":"win,lose,add_var:NAME,hit_stop,slowmo"}.
For a variable brick: {"name":"<name>","op":"add"|"set"|"toggle","amount":N}.
For an inventory brick: {"item":"key","op":"add"|"remove"|"check","amount":N,"need":N}
  (counts a named item; a door's needs_var can gate on "inv_<item>").
For a level brick: {"pattern":"row;row;row","tile":32,"theme":"grass"|"stone"|"candy"}
  where each row uses # solid, . empty, ^ spike, - one-way platform; rows go top
  to bottom separated by ';'. This paints a real 2D tile level.
Output ONLY the JSON object. No markdown."""

func generate_edit(graph_dict: Dictionary, instruction: String) -> void:
	var llm := _llm()
	if llm == null:
		edit_failed.emit("AI not available.")
		return
	if llm.needs_key() and llm.api_key.strip_edges().is_empty():
		edit_failed.emit(I18n.t("no_key_body"))
		return
	var compact := _compact_graph_for_prompt(graph_dict)
	# Same fix as the draft path: the old baked kind list stopped at 26 bricks, so
	# "add a pause menu" or "make the enemy smart" could not be expressed at all —
	# the model was not told those bricks exist.
	var vocab := GenreLibrary.vocabulary()
	var sys := EDIT_PROMPT % compact
	if not vocab.is_empty():
		sys += "\n\nBRICK VOCABULARY (use ONLY these kinds, spelled exactly):\n" + ", ".join(vocab)
	sys += GenreLibrary.prompt_block(GenreLibrary.detect(instruction))
	var messages := [
		{"role": "system", "content": sys},
		{"role": "user", "content": "Change: " + instruction},
	]
	llm.chat(messages, 12288)
	if not llm.chat_done.is_connected(_on_edit_response):
		llm.chat_done.connect(_on_edit_response)
		llm.chat_failed.connect(func(msg): edit_failed.emit(msg))

func _on_edit_response(text: String) -> void:
	var parsed := _extract_json(text)
	if parsed.is_empty() or not parsed.has("ops"):
		edit_failed.emit(I18n.t("ai_edit_nothing"))
		return
	edit_ready.emit(parsed)

## A tiny id/kind/params summary of the graph so the diff prompt stays small.
func _compact_graph_for_prompt(graph_dict: Dictionary) -> String:
	var bricks: Array = graph_dict.get("bricks", [])
	var lines: Array[String] = []
	for b in bricks:
		if not b is Dictionary:
			continue
		var id := str(b.get("id", ""))
		var kind := str(b.get("kind", ""))
		var params: Dictionary = b.get("params", {})
		# only the few params that matter for editing, to keep the prompt tight
		var keys := ["model", "speed", "jump", "gravity", "with", "action", "variable",
			"op", "amount", "condition", "value", "mode", "name", "cond_source",
			"cond_var", "cond_op", "cond_value", "actions", "preset", "target_level"]
		var shown := {}
		for k in keys:
			if params.has(k):
				shown[k] = params[k]
		lines.append("- %s : %s : %s" % [id, kind, JSON.stringify(shown)])
	return "\n".join(lines)

## Apply a structured diff to a BrickGraph instance. Returns {applied: int,
## summary: String}. Never throws: unknown ids/ops are skipped safely.
static func apply_edit(graph, diff: Dictionary) -> Dictionary:
	var applied := 0
	var summary := str(diff.get("summary", "AI made a change."))
	var ops: Array = diff.get("ops", [])
	# map placeholder ids from "add" ops so later ops can connect to them
	var new_ids := {}
	for op in ops:
		if not (op is Dictionary):
			continue
		var kind := str(op.get("op", ""))
		match kind:
			"add":
				var btype := str(op.get("type", ""))
				var nb := BrickRef.create(btype)
				if nb.is_empty():
					continue
				var np: Dictionary = op.get("params", {})
				if np is Dictionary:
					for k in np:
						nb["params"][k] = np[k]
				if graph.add_brick(nb):
					applied += 1
					# allow connecting to "the last added" by type or index
					new_ids[btype] = str(nb.get("id", ""))
			"modify":
				var mid := str(op.get("id", ""))
				var mb = graph.get_brick(mid)
				if not mb.is_empty():
					var mp: Dictionary = op.get("params", {})
					if mp is Dictionary:
						for k in mp:
							mb["params"][k] = mp[k]
						applied += 1
			"remove":
				var rid := str(op.get("id", ""))
				if graph.remove_brick(rid):
					applied += 1
			"connect":
				var fid := str(op.get("from", ""))
				var tid := str(op.get("to", ""))
				# resolve placeholder ids (e.g. connect to the just-added enemy)
				if new_ids.has(fid): fid = new_ids[fid]
				if new_ids.has(tid): tid = new_ids[tid]
				if graph.wire(fid, 0, tid, 0):
					applied += 1
			"disconnect":
				var dfid := str(op.get("from", ""))
				var dtid := str(op.get("to", ""))
				if new_ids.has(dfid): dfid = new_ids[dfid]
				if new_ids.has(dtid): dtid = new_ids[dtid]
				var db = graph.get_brick(dfid)
				if not db.is_empty():
					var conns: Array = db.get("connections", [])
					var kept: Array = []
					for c in conns:
						var cb: Dictionary = c if c is Dictionary else {}
						if str(cb.get("to_brick", "")) != dtid:
							kept.append(c)
					db["connections"] = kept
					applied += 1
	return {"applied": applied, "summary": summary}

## Undo support: snapshot a graph to a plain dict and restore it. The UI keeps
## one snapshot per AI turn so "undo" reverts exactly that edit.
static func snapshot(graph) -> Dictionary:
	if graph != null and graph.has_method("to_dict"):
		return graph.to_dict()
	return {}

# ---------------------------------------------------------------------------
# Wave 3 — "suggest the next brick": a curated pattern library (no LLM cost).
# Reads the current graph and returns up to 3 one-click suggestions so a
# beginner never faces a blank "what do I do next?" moment. Pure data.
# ---------------------------------------------------------------------------
static func suggest_next(graph_dict: Dictionary) -> Array:
	var bricks: Array = graph_dict.get("bricks", [])
	var kinds := {}
	for b in bricks:
		if b is Dictionary:
			kinds[str(b.get("kind", ""))] = true
	var out: Array = []
	# rule: has jump/move but no enemy -> suggest an enemy + a score
	if kinds.has("move") and not kinds.has("enemy_patrol"):
		out.append({"kind": "enemy_patrol", "label": "👾 Add an enemy", "why": "something to dodge"})
	# has a collide but no score -> suggest scoring
	if kinds.has("collide") and not kinds.has("score"):
		out.append({"kind": "score", "label": "🏆 Add scoring", "why": "give points for touching things"})
	# has collectibles but no win condition -> suggest a goal
	if (kinds.has("score") or kinds.has("collide")) and not kinds.has("winlose") and not kinds.has("rule"):
		out.append({"kind": "winlose", "label": "🚩 Add a win condition", "why": "so the game can end"})
	# has movement but no camera tuning -> suggest a follow camera
	if kinds.has("move") and not kinds.has("camera"):
		out.append({"kind": "camera", "label": "🎥 Add a follow camera", "why": "keep the player centered"})
	# a plain game with no variables -> suggest a coin counter + a rule
	if not kinds.has("variable") and not kinds.has("rule") and kinds.has("collide"):
		out.append({"kind": "variable", "label": "🔢 Count what you collect", "why": "then win when you collect enough"})
	# a level with no hazards -> suggest a hazard
	if not kinds.has("hazard") and kinds.has("move"):
		out.append({"kind": "hazard", "label": "🔥 Add a hazard", "why": "risk makes it a game"})
	# no background polish -> suggest a themed background
	if not kinds.has("background") and not kinds.has("sky"):
		out.append({"kind": "background", "label": "🌄 Add a background", "why": "instant depth and polish"})
	# cap at 3 so the panel stays calm
	var capped: Array = []
	for i in min(out.size(), 3):
		capped.append(out[i])
	return capped



# ---------------------------------------------------------------------------
# Robust JSON extraction — models love wrapping JSON in ```json fences or
# adding a sentence before it. We slice to the outermost { }.
# ---------------------------------------------------------------------------
func _extract_json(text: String) -> Dictionary:
	var cleaned := text.strip_edges()
	var start := cleaned.find("{")
	var end := cleaned.rfind("}")
	if start == -1 or end == -1 or end <= start:
		return {}
	var json_text := cleaned.substr(start, end - start + 1)
	var parsed = JSON.parse_string(json_text)
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {}
