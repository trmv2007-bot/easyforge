extends Node
## I18n - reads the embedded translation table (src/i18n/locales.gd).
##
## Translations are EMBEDDED as a GDScript constant (not res:// file reads), so
## they load identically in the editor and in exported builds. Regenerate the
## table from the CSVs with:  python3 tools/gen_locales.py

const Locales := preload("res://src/i18n/locales.gd")

var current_lang: String = Locales.DEFAULT_LANG

func set_language(lang: String) -> void:
	if not Locales.LANGUAGES.has(lang):
		lang = Locales.DEFAULT_LANG
	current_lang = lang
	TranslationServer.set_locale(lang)

func t(key: String) -> String:
	var entry = Locales.TABLE.get(key, null)
	if entry == null:
		return key  # unknown key: never crash
	var v = entry.get(current_lang, null)
	if v == null or str(v) == "":
		v = entry.get(Locales.DEFAULT_LANG, key)  # fall back to English
	return str(v)


func available_languages() -> Array:
	return Locales.LANGUAGES.keys()

func language_label(code: String) -> String:
	return str(Locales.LANGUAGES.get(code, code))

func translate(key: String) -> String:
	return t(key)
