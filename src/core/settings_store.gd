extends Node
## SettingsStore — persistent user settings + BYOK key.
## Saved to user://easyforge_settings.cfg (per-user, local, never in the
## project files, never uploaded). This is where the API key lives.

const SAVE_PATH := "user://easyforge_settings.cfg"
const SAVE_SECTION := "settings"

# defaults measured against a live key: Groq drafts a valid graph in ~7s, NVIDIA
# takes ~170s. A fresh install must not default to a model id that 404s.
var provider: String = "groq"
var model: String = "openai/gpt-oss-120b"
var api_key: String = ""
var language: String = "en"
var tutorial_done: bool = false
var last_project: String = ""

func _init():
	load_settings()

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SAVE_SECTION, "provider", provider)
	cfg.set_value(SAVE_SECTION, "model", model)
	cfg.set_value(SAVE_SECTION, "api_key", api_key)
	cfg.set_value(SAVE_SECTION, "language", language)
	cfg.set_value(SAVE_SECTION, "tutorial_done", tutorial_done)
	cfg.set_value(SAVE_SECTION, "last_project", last_project)
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_error("SettingsStore: save failed %d" % err)

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	provider = cfg.get_value(SAVE_SECTION, "provider", provider)
	model = cfg.get_value(SAVE_SECTION, "model", model)
	api_key = cfg.get_value(SAVE_SECTION, "api_key", api_key)
	language = cfg.get_value(SAVE_SECTION, "language", language)
	tutorial_done = cfg.get_value(SAVE_SECTION, "tutorial_done", tutorial_done)
	last_project = cfg.get_value(SAVE_SECTION, "last_project", last_project)

func apply_to_llm(llm: LlmClient) -> void:
	llm.set_provider(provider)
	llm.model = model
	llm.api_key = api_key

func from_llm(llm: LlmClient) -> void:
	provider = llm.provider
	model = llm.model
	api_key = llm.api_key
