extends AcceptDialog
## SettingsDialog — the AI key, the model, and the language.
##
## Extracted from main.gd so the form can explain itself: this is the one screen
## that can stop the whole product working (no key, no drafting), and it used to
## be 130 lines built inside the window's own builder. Everything here is honest
## about what a value does and where the key goes, because a beginner being asked
## for an API key is a beginner about to give up.

signal saved

const PROVIDER_HINTS := {
	"groq": "Fastest drafting (about six seconds for a ten-brick game). Free tier, key from console.groq.com/keys.",
	"nvidia": "Richer ideas, slower. Free tier, key from build.nvidia.com.",
	"gemini": "Google's free tier. Key from aistudio.google.com.",
	"ollama": "Runs on your own PC: no key, no internet, nothing leaves your machine. Needs Ollama installed.",
}

var _prov_opt: OptionButton = null
var _model_opt: OptionButton = null
var _model_custom: LineEdit = null
var _key_edit: LineEdit = null
var _key_status: Label = null
var _lang_opt: OptionButton = null
var _hint: Label = null

func setup() -> void:
	title = "⚙ " + I18n.t("settings")
	min_size = Vector2(520, 520)
	_build()

func _build() -> void:
	var v := VBoxContainer.new()
	v.name = "SettingsBody"
	v.add_theme_constant_override("separation", 8)
	add_child(v)

	v.add_child(_head(I18n.t("ai_provider")))
	_prov_opt = OptionButton.new()
	_prov_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var i := 0
	for key in LlmClient.PROVIDERS:
		var meta: Dictionary = LlmClient.PROVIDERS[key]
		_prov_opt.add_item(str(meta["label"]), i)
		_prov_opt.set_item_metadata(i, key)
		i += 1
	v.add_child(_prov_opt)
	_hint = Label.new()
	_hint.name = "ProviderHint"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", 11)
	_hint.modulate = UiTheme.C_MUTED
	v.add_child(_hint)

	v.add_child(_head(I18n.t("ai_model")))
	_model_opt = OptionButton.new()
	_model_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_model_opt)
	# Hosted model names get retired, so the picker alone was a dead end: type
	# any model id from your provider and it wins over the list.
	_model_custom = LineEdit.new()
	_model_custom.name = "ModelCustom"
	_model_custom.placeholder_text = I18n.t("model_custom")
	_model_custom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_model_custom.tooltip_text = "Leave this empty to use the model chosen above."
	v.add_child(_model_custom)

	v.add_child(_head(I18n.t("api_key")))
	_key_edit = LineEdit.new()
	_key_edit.placeholder_text = "nvapi-... / gsk_..."
	_key_edit.secret = true
	_key_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_key_edit.tooltip_text = "Stored only on this PC (in EasyForge's own settings folder) and sent only to the provider you pick."
	v.add_child(_key_edit)
	var key_row := HBoxContainer.new()
	key_row.add_theme_constant_override("separation", 6)
	v.add_child(key_row)
	var get_btn := Button.new()
	get_btn.text = "🔗 " + I18n.t("get_key")
	get_btn.tooltip_text = "Opens your provider's key page in the browser."
	key_row.add_child(get_btn)
	var test_btn := Button.new()
	test_btn.text = "✓ " + I18n.t("test_key")
	test_btn.tooltip_text = "Sends one tiny request to prove the key works before you trust it with a whole game idea."
	key_row.add_child(test_btn)
	var local_btn := Button.new()
	local_btn.text = "🏠 No key needed"
	local_btn.tooltip_text = "Pick Ollama to run the AI on this PC — nothing to sign up for."
	local_btn.pressed.connect(func():
		for idx in _prov_opt.item_count:
			if str(_prov_opt.get_item_metadata(idx)) == "ollama":
				_prov_opt.select(idx)
				_refill_models("")
				_update_hint()
				break
	)
	key_row.add_child(local_btn)
	_key_status = Label.new()
	_key_status.name = "KeyStatus"
	_key_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_key_status.add_theme_font_size_override("font_size", 12)
	v.add_child(_key_status)

	v.add_child(_head(I18n.t("language")))
	_lang_opt = OptionButton.new()
	_lang_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lang_opt.tooltip_text = "The editor's language. Your game keeps whatever text you typed into it."
	var li := 0
	for code in I18n.available_languages():
		_lang_opt.add_item(I18n.language_label(code), li)
		_lang_opt.set_item_metadata(li, code)
		li += 1
	v.add_child(_lang_opt)

	var note := Label.new()
	note.text = "💡 Everything except the AI drafting works with no key at all: templates, recipes, bricks, Play and sharing."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 12)
	note.modulate = UiTheme.C_ACCENT_2
	v.add_child(note)

	_preselect()
	_prov_opt.item_selected.connect(func(_idx):
		_refill_models("")
		_model_custom.text = ""
		_update_hint()
	)
	get_btn.pressed.connect(func():
		var pkey: String = str(_prov_opt.get_item_metadata(_prov_opt.selected))
		var meta: Dictionary = LlmClient.PROVIDERS.get(pkey, {})
		if meta.has("signup"):
			OS.shell_open(str(meta["signup"]))
	)
	test_btn.pressed.connect(_test_key)
	LlmClient.key_verified.connect(func(ok: bool, msg: String):
		_key_status.text = msg
		_key_status.modulate = UiTheme.C_GOOD if ok else UiTheme.C_BAD
	)
	_update_hint()
	confirmed.connect(_commit)

func _head(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.modulate = UiTheme.C_ACCENT_2
	return l

func _preselect() -> void:
	var prov_keys := LlmClient.PROVIDERS.keys()
	var _sel := 0
	for idx in prov_keys.size():
		if prov_keys[idx] == SettingsStore.provider:
			_sel = idx
			break
	_prov_opt.select(_sel)
	_refill_models(SettingsStore.model)
	# a saved model that is not in the list (retired or hand-typed) goes into the
	# free-text field instead of silently reverting to the first pick
	var saved_model := str(SettingsStore.model)
	if not saved_model.is_empty() and not _model_list().has(saved_model):
		_model_custom.text = saved_model
	var lang_keys = I18n.available_languages()
	var _lsel := 0
	for idx in lang_keys.size():
		if lang_keys[idx] == SettingsStore.language:
			_lsel = idx
			break
	_lang_opt.select(_lsel)
	_key_edit.text = SettingsStore.api_key
	_key_edit.editable = bool(_provider_meta().get("needs_key", true))

func _provider_meta() -> Dictionary:
	var pkey: String = str(_prov_opt.get_item_metadata(maxi(_prov_opt.selected, 0)))
	return LlmClient.PROVIDERS.get(pkey, {})

func _model_list() -> Array:
	return (_provider_meta().get("models", []) as Array)

func _refill_models(preselect: String) -> void:
	_model_opt.clear()
	var mi := 0
	var sel := 0
	var models: Array = _model_list()
	for m in models:
		_model_opt.add_item(str(m), mi)
		_model_opt.set_item_metadata(mi, m)
		if str(m) == preselect:
			sel = mi
		mi += 1
	if _model_opt.item_count > 0:
		_model_opt.select(sel)
	_key_edit.editable = bool(_provider_meta().get("needs_key", true))

func _update_hint() -> void:
	var pkey: String = str(_prov_opt.get_item_metadata(maxi(_prov_opt.selected, 0)))
	var meta := _provider_meta()
	var hint := str(PROVIDER_HINTS.get(pkey, ""))
	var models: Array = meta.get("models", [])
	if not models.is_empty():
		hint += " Default model: %s." % str(models[0])
	_hint.text = hint

## Which model will actually be used: the typed id wins over the picker, because
## a retired hosted name must not be able to brick the AI.
func _picked_model() -> String:
	var typed := str(_model_custom.text).strip_edges()
	if not typed.is_empty():
		return typed
	if _model_opt.item_count <= 0:
		return ""
	return str(_model_opt.get_item_metadata(_model_opt.selected))

func _test_key() -> void:
	var pkey: String = str(_prov_opt.get_item_metadata(maxi(_prov_opt.selected, 0)))
	LlmClient.set_provider(pkey)
	LlmClient.model = _picked_model()
	LlmClient.api_key = _key_edit.text
	_key_status.text = I18n.t("key_testing")
	_key_status.modulate = UiTheme.C_MUTED
	LlmClient.test_key()

func _commit() -> void:
	SettingsStore.provider = str(_prov_opt.get_item_metadata(maxi(_prov_opt.selected, 0)))
	SettingsStore.model = _picked_model()
	SettingsStore.api_key = _key_edit.text
	SettingsStore.language = str(_lang_opt.get_item_metadata(maxi(_lang_opt.selected, 0)))
	SettingsStore.save_settings()
	SettingsStore.apply_to_llm(LlmClient)
	I18n.set_language(SettingsStore.language)
	saved.emit()
