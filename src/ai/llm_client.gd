extends Node
## LlmClient — one OpenAI-compatible code path for three providers.
##   NVIDIA NIM : base https://integrate.api.nvidia.com/v1  (qwen2.5-coder-32b, minimax-m2.7)
##   Gemini     : base https://generativelanguage.googleapis.com/v1beta/openai  (gemini-3.8-flash)
##   Ollama     : base http://localhost:11434/v1            (qwen2.5-coder:7b, no key)
##
## BYOK: the key lives in the user's local settings only. It is sent ONLY to
## the provider the user chose. Nothing is stored server-side (there is no
## server). Keys never enter chat/logs.

signal key_verified(ok: bool, message: String)
signal chat_done(text: String)
signal chat_failed(message: String)

var provider: String = "groq"          # groq | nvidia | gemini | ollama
var model: String = "openai/gpt-oss-120b"
var api_key: String = ""

const PROVIDERS := {
	# Measured on live keys, October 2026, using this app's real system prompt:
	# Groq gpt-oss-120b drafted a valid 9-10 brick graph in 5.7-6.8s; the fastest
	# callable NVIDIA model took ~170s. Godot's own HTTP client is NOT blocked by
	# Groq's CDN (verified with a "GodotEngine" user agent).
	"groq": {
		"label": "Groq (fastest, free)",
		"base": "https://api.groq.com/openai/v1",
		"models": ["openai/gpt-oss-120b", "openai/gpt-oss-20b"],
		"needs_key": true,
		"signup": "https://console.groq.com/keys",
	},
	"nvidia": {
		"label": "NVIDIA NIM (free)",
		"base": "https://integrate.api.nvidia.com/v1",
		# Measured on a live key, using THIS app's real system prompt (Oct 2026).
		# NVIDIA's /v1/models lists ~80 ids but most 404 for a free key, and every
		# model that does answer is a reasoning model that spends the token budget
		# thinking first. So this list is ordered by what actually drafted a valid
		# graph: glm-5.3-flash returned 18 valid bricks in ~170s, gpt-oss-20b 11 in
		# ~198s, and nemotron-3.5-lightning burned all 8192 tokens reasoning and
		# never emitted the answer. Expect minutes, not seconds.
		"models": [
			"z-ai/glm-5.3-flash",
			"openai/gpt-oss-20b",
			"nvidia/nemotron-3.5-lightning-30b-a3b",
		],
		"needs_key": true,
		"signup": "https://build.nvidia.com/",
	},
	"gemini": {
		"label": "Google Gemini (free)",
		"base": "https://generativelanguage.googleapis.com/v1beta/openai",
		"models": ["gemini-3.8-flash", "gemini-3.5-flash-lite"],
		"needs_key": true,
		"signup": "https://aistudio.google.com/",
	},
	"ollama": {
		"label": "Ollama (offline, no key)",
		"base": "http://localhost:11434/v1",
		"models": ["qwen2.5-coder:7b", "qwen2.5-coder:14b"],
		"needs_key": false,
		"signup": "https://ollama.com/",
	},
}

func set_provider(p: String) -> void:
	if PROVIDERS.has(p):
		provider = p
		model = PROVIDERS[p]["models"][0]

func base_url() -> String:
	return PROVIDERS[provider]["base"]

func needs_key() -> bool:
	return PROVIDERS[provider]["needs_key"]

# ---------------------------------------------------------------------------
# Test key — the "verify before anything works" rule. Sends a tiny real chat
# request; only a non-empty answer counts as OK (a 200 with empty body = fail).
# ---------------------------------------------------------------------------
func test_key() -> void:
	# 16 tokens was enough only for plain instruct models. Reasoning models
	# (measured on a live key: nemotron-3.5-lightning, glm-5.3-flash) spend the
	# budget thinking and answer with empty content, so a valid key looked broken.
	var req := _make_request("Reply with the single word: OK", 512)
	var err := req.request_completed.connect(_on_test_done)
	if err != OK:
		key_verified.emit(false, "Network error: %d" % err)

func _on_test_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var text := body.get_string_from_utf8()
	if result != HTTPRequest.RESULT_SUCCESS:
		key_verified.emit(false, I18n.t("net_error"))
		return
	if code == 401 or code == 403:
		key_verified.emit(false, I18n.t("key_bad"))
		return
	if code == 404:
		key_verified.emit(false, I18n.t("model_unavailable"))
		return
	if code == 429:
		key_verified.emit(false, I18n.t("rate_limited"))
		return
	if code != 200:
		key_verified.emit(false, I18n.t("provider_error") % code)
		return
	# a 200 with a choices array proves the key and the endpoint, whatever the
	# model's answer looks like — an empty body is a model problem, not a key one
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("choices"):
		key_verified.emit(false, I18n.t("bad_reply"))
		return
	var content: String = str(parsed["choices"][0]["message"].get("content", ""))
	if content.strip_edges().is_empty():
		key_verified.emit(true, I18n.t("key_ok") + " — " + model + " (" + I18n.t("ai_thinking_empty") + ")")
		return
	key_verified.emit(true, I18n.t("key_ok") + " — " + model)

# ---------------------------------------------------------------------------
# Chat — used by the AI brick generator. messages: Array of {role, content}.
# ---------------------------------------------------------------------------
func chat(messages: Array, max_tokens: int = 8192) -> void:
	var payload := {
		"model": model,
		"messages": messages,
		"temperature": 0.4,
		"max_tokens": max_tokens,
	}
	var http := HTTPRequest.new()
	get_tree().root.add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if needs_key() and not api_key.is_empty():
		headers.append("Authorization: Bearer " + api_key)
	http.request_completed.connect(func(result, code, _h, body):
		var text: String = str(body.get_string_from_utf8())
		if result != HTTPRequest.RESULT_SUCCESS:
			chat_failed.emit(I18n.t("net_error"))
		elif code == 404 or (code == 400 and text.to_lower().find("model") >= 0):
			# a retired or misspelled hosted name: say what to do, don't dump JSON
			push_warning("[llm] model rejected (%d): %s" % [code, text.substr(0, 160)])
			chat_failed.emit(I18n.t("model_unavailable"))
		elif code == 429:
			chat_failed.emit(I18n.t("rate_limited"))
		elif code != 200:
			push_warning("[llm] provider error %d: %s" % [code, text.substr(0, 200)])
			chat_failed.emit(I18n.t("provider_error") % code)
		else:
			var parsed = JSON.parse_string(text)
			if typeof(parsed) == TYPE_DICTIONARY and parsed.has("choices"):
				var msg: Dictionary = parsed["choices"][0]["message"]
				# JSON null is not an empty string: str(null) is "<null>", which
				# used to sail past the emptiness check and reach the parser as a
				# six-character "reply"
				var raw = msg.get("content", "")
				var content: String = "" if raw == null else str(raw)
				if content.strip_edges().is_empty() or content == "<null>":
					# reasoning models spend the token budget thinking; a truncated
					# answer is a different problem from a garbled one
					if str(parsed["choices"][0].get("finish_reason", "")) == "length":
						chat_failed.emit(I18n.t("ai_cut_off"))
					else:
						chat_failed.emit(I18n.t("bad_reply"))
				else:
					chat_done.emit(content)
			else:
				chat_failed.emit(I18n.t("bad_reply"))
		http.queue_free()
	)
	var err := http.request(base_url() + "/chat/completions", headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		chat_failed.emit("Request failed: %d" % err)

# ---------------------------------------------------------------------------
func _make_request(prompt: String, max_tokens: int) -> HTTPRequest:
	var http := HTTPRequest.new()
	get_tree().root.add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if needs_key() and not api_key.is_empty():
		headers.append("Authorization: Bearer " + api_key)
	var payload := {
		"model": model,
		"messages": [{"role": "user", "content": prompt}],
		"max_tokens": max_tokens,
	}
	http.request(base_url() + "/chat/completions", headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	return http
