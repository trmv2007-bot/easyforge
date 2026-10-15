#!/usr/bin/env python3
"""Generate src/i18n/locales.gd from i18n/locale_*.csv.

Every translation is embedded as a plain GDScript dictionary so it loads
identically in the editor AND in exported builds (res:// file reads on raw
CSVs fail inside a PCK). Edit the CSVs, then run:  python3 tools/gen_locales.py
"""
import csv
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LANGS = ["en", "hi", "es", "zh", "ar", "pt", "fr", "de", "ja", "ru"]
# Native names (endonyms) only: a beginner who speaks Hindi cannot read
# "Hindi", but they can always find हिन्दी. Keep these in each language's own
# script -- never anglicise them, and never leave the ASCII placeholder forms
# ("Espanol", "Portugues") that used to be here.
LABELS = {
    "en": "English", "hi": "हिन्दी", "es": "Español", "zh": "中文",
    "ar": "العربية", "pt": "Português", "fr": "Français", "de": "Deutsch",
    "ja": "日本語", "ru": "Русский",
}


def gdstr(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


# Keys that are *supposed* to read the same in every language. Without this
# allowlist the lint cries wolf over the product name and the CJK word for
# "code", which really is spelled "Code" in French and German.
UNIVERSAL = {"app_title", "code", "ok", "score", "recommended"}

# Scripts that must never show up as bare Latin runs (brand names excepted).
NON_LATIN = ("hi", "zh", "ar", "ja", "ru")
BRAND = re.compile(r"^(easyforge|nvidia|godot|godotengine|api|ai|pc|web|build|"
                   r"index|html|release|headless|org|efg|esc|ctrl|shift|del|"
                   r"suppr|entf|delete|wasd|spawn|url|http|https|template|"
                   r"templates|plattformer|platformer|platform|plugin|windows|"
                   r"exe|txt|json)$", re.I)


def latin_tokens(v):
    """Latin runs left in a non-Latin string, ignoring {placeholders}, shell
    flags (--export-release), paths (build/web/) and ASCII domains or file
    names (godotengine.org, index.html) -- none of which are translatable
    prose. The dot rule is deliberately ASCII-only and needs a word AFTER the
    dot, so a sentence-final period cannot hide a leak: '... مع anyone.' must
    still be reported."""
    s = re.sub(r"\{[^}]*\}", " ", v)
    s = re.sub(r"-{1,2}[A-Za-z][\w-]*", " ", s)
    s = re.sub(r"[\w.-]*[/\\][\w.-]*", " ", s)
    s = re.sub(r"[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)+", " ", s)
    return [w for w in re.findall(r"[A-Za-z]{2,}", s) if not BRAND.match(w.lower())]

# Simplified-only glyph forms that must never appear in the Japanese file
# (设计 leaked into locale_ja.csv's ai_thinking once, shipped to users).  Shares
# Japanese kanji are deliberately left out: 与 and 影 are valid in Japanese, so
# flagging them would bury the real findings.
SIMPLIFIED_IN_JA = re.compile(
    "[设游戏们语为单网贝钱长门问间线统计处让说话请马鸟鱼车东风"
    "达运远边员类组织细审导帮广应层岁岛币报复兴响关图]"
)


def used_keys():
    """Every key the UI can ask for: literal I18n.t("k"), I18n.translate("k"),
    plus string lists consumed through a variable (the help dialog loop)."""
    keys = set()
    src = os.path.join(ROOT, "src")
    tests = os.path.join(ROOT, "tests")
    for base in (src, tests):
        if not os.path.isdir(base):
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [d for d in dirnames if d not in (".godot", "build")]
            for fn in filenames:
                if not fn.endswith(".gd") or fn == "locales.gd":
                    continue
                lines = open(os.path.join(dirpath, fn), encoding="utf-8").read().split("\n")
                for i, line in enumerate(lines):
                    for m in re.finditer(r'I18n\.(?:t|translate)\(\s*"([^"]+)"', line):
                        keys.add(m.group(1))
                    # I18n.t(key) -> walk back to the `for key in [...]` list
                    var = re.search(r'I18n\.(?:t|translate)\(\s*([A-Za-z_]\w*)\s*\)', line)
                    if var:
                        name = var.group(1)
                        for j in range(max(0, i - 15), i + 1):
                            loop = re.search(r'for\s+%s\s+in\s+\[([^\]]*)\]' % re.escape(name), lines[j])
                            if loop:
                                keys.update(re.findall(r'"([a-z][a-z0-9_]*)"', loop.group(1)))
    return keys


def lint(data):
    """Report localisation gaps instead of shipping them silently."""
    problems = []
    keys = used_keys()
    en = data.get("en", {})
    missing_en = sorted(keys - set(en))
    if missing_en:
        problems.append("locale_en.csv is MISSING %d key(s) the UI asks for -- these "
                        "render as raw codes like `added_brick`: %s"
                        % (len(missing_en), ", ".join(missing_en)))
    for lang in LANGS:
        d = data.get(lang)
        if d is None:
            problems.append("no i18n/locale_%s.csv" % lang)
            continue
        missing = sorted(keys - set(d))
        if missing:
            problems.append("locale_%s.csv: %d/%d used key(s) missing, UI falls back to "
                            "English mid-sentence: %s" % (lang, len(missing), len(keys),
                                                           ", ".join(missing)))
        dead = sorted(set(d) - keys)
        if dead and lang == "en":
            problems.append("%d key(s) in the table are never used by the UI (dead, kept "
                            "for parity): %s" % (len(dead), ", ".join(dead)))
        for k, v in d.items():
            if not v.strip():
                problems.append("locale_%s.csv [%s]: empty value" % (lang, k))
                continue
            if k in missing_en:
                continue
            if lang != "en" and k not in UNIVERSAL and v == en.get(k):
                problems.append("locale_%s.csv [%s]: untranslated, identical to English: %r"
                                % (lang, k, v))
            if lang in NON_LATIN and k not in UNIVERSAL:
                leaks = latin_tokens(v)
                if leaks:
                    problems.append("locale_%s.csv [%s]: Latin leak %s in %r"
                                    % (lang, k, leaks, v))
            if lang == "ja":
                bad = SIMPLIFIED_IN_JA.findall(v)
                if bad:
                    problems.append("locale_ja.csv [%s]: Simplified-Chinese %s (Japanese "
                                    "form required) in %r" % (k, sorted(set(bad)), v))
        # placeholder safety: a translation that drops a %s / %d / {token}
        # breaks the label at runtime (e.g. export_game_readme needs {game},
        # which game_exporter.gd substitutes with the project name).
        for k, v in d.items():
            if lang == "en":
                continue
            src = en.get(k, "")
            want = sorted(re.findall(r"%[sd]|\{[A-Za-z_][A-Za-z0-9_]*\}", src))
            got = sorted(re.findall(r"%[sd]|\{[A-Za-z_][A-Za-z0-9_]*\}", v))
            if want != got:
                problems.append("locale_%s.csv [%s]: placeholder mismatch, en wants %s but "
                                "got %s -- label breaks at runtime" % (lang, k, want, got))
    return problems


def main() -> None:
    data = {}
    for lang in LANGS:
        path = os.path.join(ROOT, "i18n", f"locale_{lang}.csv")
        if not os.path.exists(path):
            continue
        d = {}
        with open(path, encoding="utf-8-sig") as f:
            reader = csv.reader(f, delimiter="\t")
            next(reader, None)  # header
            for row in reader:
                if len(row) >= 2:
                    d[row[0]] = row[1]
        data[lang] = d

    all_keys, seen = [], set()
    for lang in ["en"] + [l for l in LANGS if l != "en"]:
        for k in data.get(lang, {}):
            if k not in seen:
                all_keys.append(k)
                seen.add(k)

    out = []
    out.append("extends Node")
    out.append("## Locales - every translation embedded as a plain GDScript dictionary.")
    out.append("## AUTO-GENERATED from i18n/locale_*.csv by tools/gen_locales.py.")
    out.append("## Edit the CSVs and regenerate; embedded so it loads in exported builds.")
    out.append("")
    out.append("const LANGUAGES := {")
    for lang in LANGS:
        if lang in data:
            out.append('\t"%s": "%s",' % (lang, LABELS[lang]))
    out.append("}")
    out.append("")
    out.append('const DEFAULT_LANG := "en"')
    out.append("")
    out.append("# key -> {lang: text}")
    out.append("const TABLE := {")
    for k in all_keys:
        entry = {lang: data[lang][k] for lang in LANGS if lang in data and k in data[lang]}
        parts = ", ".join('"%s": %s' % (lang, gdstr(txt)) for lang, txt in entry.items())
        out.append("\t%s: {%s}," % (gdstr(k), parts))
    out.append("}")
    out.append("")

    dest = os.path.join(ROOT, "src", "i18n", "locales.gd")
    with open(dest, "w", encoding="utf-8") as f:
        f.write("\n".join(out))
    print("generated %s: %d keys x %d languages" % (dest, len(all_keys), len(data)))
    for p in lint(data):
        print("WARN i18n: %s" % p, file=sys.stderr)


if __name__ == "__main__":
    main()
