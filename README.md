# EasyForge

**Describe a game in plain English. Watch it come alive.**

A Windows app where a beginner builds a playable 3D/2D game by editing a visual
"brick diagram" instead of writing code. AI drafts the bricks from your idea;
you rearrange and connect them; the app compiles them into a real Godot game you
can play instantly and export to share.

---

## For the friend testing this (start here)

**You do not need to know anything about game development.**

1. Double-click **`EasyForge.exe`** (in the `build/` folder) — that's the real
   app, no install, no editor, no console. (Or run **`RUN.bat`** from the source
   folder if you prefer.)
2. The app opens with a finished demo game already loaded — you never start from
   an empty screen. Your own work is restored automatically when you reopen it.
3. Press **▶ Play** (right side). Move with **W A S D**, jump with **Space**,
   press **Esc** to stop.
4. Each box on the canvas is a **brick** — one piece of your game. Drag between
   the dots to connect bricks; incompatible dots won't connect. Hover any brick
   in the list to read what it does.
5. Want to change something? Type a note in the box inside a brick
   (e.g. *"I want coins to give 10 points"*).
6. Want the AI to design a whole new game? Type what you want at the top-left
   and press **✨ Build with AI**. (Needs a free AI key — see below.)
7. Happy with it? Press **🚀** — it builds a real `<YourGame>.exe` you can send
   to anyone. They double-click it and play; no EasyForge needed.

**Keys:** `Ctrl+Z` undo · `Ctrl+Shift+Z` redo · `Ctrl+C/V/D` copy, paste,
duplicate · `Delete` remove · `Ctrl+S` save · `+ - 0` zoom · `WASD`/arrows pan.
Press **?** in the app at any time for this list and a 5-step guide.

### Get a free AI key (optional, 2 minutes)

The demo works with no key at all. To use the AI features:

1. Press **⚙ Settings** in the app.
2. Pick **Groq (fastest, free)** — it is the default, and drafts take seconds.
3. Press **🔗 Get a free key** — it opens the signup page.
4. Sign up (Google/GitHub, no card), copy the key that starts with `gsk_`.
5. Paste it, press **✓ Test key**. Green = done.

**NVIDIA NIM** also works and is kept as an option, but every free model that
answers there is a reasoning model: a measured draft took **~170 seconds** versus
**~6 seconds** on Groq. Type any model name into the box under the picker if the
list goes stale — hosted names get retired often.

Your key stays on your PC (`user://` settings). It is never sent anywhere except
the provider you picked.

---

## What's inside (the design in one picture)

```
  "a 3D platformer where you collect coins"
            │
            ▼
  ┌──────────────────┐
  │  AI drafts bricks │  Phase A — never an empty graph
  └──────────────────┘
            ▼
  ┌──────────────────┐
  │  You edit bricks  │  rearrange / reconnect / comment
  └──────────────────┘
            ▼
  ┌──────────────────┐
  │  Compiler        │  bricks → real GDScript (deterministic)
  └──────────────────┘
            ▼
  ┌──────────────────┐
  │  ▶ Play in-app   │  instant preview, no browser
  └──────────────────┘
            ▼
  ┌──────────────────┐
  │  📦 Export       │  a file you send/post yourself
  └──────────────────┘
```

### The 5 universal bricks

| Brick | Plain English | What it does |
|---|---|---|
| ✨ **Spawn** | "when the game starts" | creates the player / enemies / items |
| 🏃 **Move** | "how things move" | walking, jumping, gravity |
| 💥 **Collide** | "when things touch" | player picks up a coin, hits an enemy |
| 🏆 **Score** | "what changes" | points, health, lives |
| 🚩 **Win/Lose** | "when the game ends" | reach a score, run out of lives |

Every game is built from these five. Genre packs (platformer, top-down,
shooter) add more bricks later without changing the engine.

---

## For developers

### Run it

```
RUN.bat                      # the app (uses tools/Godot...)
```

### Run the tests (proves the pipeline end-to-end, no API key needed)

```
tools\Godot_v4.7.2-stable_win64_console.exe --headless res://tests/test_scene.tscn --quit-after 600
tools\Godot_v4.7.2-stable_win64_console.exe --headless res://tests/ui_test_scene.tscn --quit-after 900
```

- **smoke test** (94 checks) — bricks → compile → scene → generated scripts
  parse clean → save/load → 2D+3D → validation → typed ports → GameState →
  i18n → AI JSON extraction. Includes a **footprint sweep**: every palette kind
  is compiled into a real graph and must change the tree (node classes plus
  every attached script's length). A brick that silently does nothing fails here
  even when it produces no placeholder — which is how five inert bricks shipped.
- **UI test** (31 checks) — drives the real UI: demo auto-load, graph renders,
  palette, Play mounts the game, Stop unmounts, Code view, add brick, save.
  Also asserts undo/redo really work, the keyboard shortcuts act, tooltips
  explain, restarting restores your work, and **🚀 writes a runnable
  exe + pck + game.json**.

### Layout

```
project.godot              autoloads + renderer config
src/
  bricks/    brick.gd       the IR unit (JSON dictionary) + typed-port rules
             graph.gd       the project: ordered bricks, wire(), validate()
             registry.gd    brick library per genre (universality = depth)
  compiler/  compiler.gd    THE DEEP MODULE: bricks -> GDScript + scene tree
  ai/        llm_client.gd  BYOK, one OpenAI-compatible path (NVIDIA/Gemini/Ollama)
             brick_generator.gd  Phase A draft + Phase B finalize + JSON extract
  runtime/   game_runner.gd in-app Play (mounts compiled scene in a SubViewport)
             game_state.gd  score / win / lose (autoload "GameState")
  export/    game_exporter.gd  🚀 writes <Game>.exe + .pck + game.json you can send
  core/      settings_store.gd  local settings + the API key (user://)
  i18n/      i18n.gd        CSV translator, 10 languages
  templates/ demo_templates.gd  zero-key demo (Coin Dash) — proves the pipeline
  ui/        main.gd        the whole window (built in code, themeable)
i18n/        locale_XX.csv  en, hi, es, zh, ar, pt, fr, de, ja, ru
tests/       smoke_test.gd + ui_test.gd
tools/       Godot 4.7.2 portable (delete this folder to uninstall)
SPEC.md      the full product spec (source of truth for decisions)
BUILD-LOG.md what was decided and why during the overnight build
```

### Architecture rules that matter

- **The compiler is deterministic.** The AI never writes final code — it drafts
  bricks. One module turns a settled graph into GDScript. That's why the output
  is testable and reliable instead of a black box.
- **Bricks are plain JSON dictionaries.** Serializable, comparable in tests,
  zero coupling to UI or engine.
- **The user never sees an empty canvas.** First run always loads a complete
  working demo.
- **BYOK.** No key ships inside the app; each user's key lives in their local
  `user://` settings and goes only to the provider they picked.
- **Errors never crash the app** — they appear in the status bar.

### Adding a genre

Edit `src/bricks/registry.gd` → `register_pack("yourgenre")`. The palette, the
AI prompt, and the compiler pick it up with no other changes.

### Adding a language

The CSVs are **tab-separated** and the translations are compiled into
`src/i18n/locales.gd` (embedded, so they load inside an exported .exe too).
Copy `i18n/locale_en.csv`, translate the second column, then regenerate:

```
python tools/gen_locales.py
```

Add the language code to `LANGS` / `LABELS` in that script (not to `i18n.gd`).
The generator also **lints**: it reports keys the UI asks for that your file is
missing, values left identical to English, empty cells, and dropped `%s`
placeholders. Warnings are the bug list — read them. Arabic is translated but
not yet mirrored right-to-left.

---

## Status

**v1 — working, tested, ships as a real Windows .exe.**

Shipped: brick IR + hardened compiler + graph editor + in-app Play + export +
BYOK (NVIDIA/Gemini/Ollama) + 10 languages + guided tutorial + zero-key demo +
polished dark theme + real platformer bricks (enemy patrol, hazard, checkpoint,
moving platform) + lighting/multiple coins so the compiled game looks alive.
**v1.5 additions:** 🚀 share a real runnable `<Game>.exe`, your work autosaves
and restores (it used to vanish on restart), full keyboard control, undo/redo
that actually works, help and shortcut list always one click away, every brick
explained on hover, and the played game's HUD now reads in your language.

**Build the .exe yourself:** export templates are installed; run
`tools\Godot_v4.7.2-stable_win64_console.exe --headless --path <project> --export-release "Windows Desktop" <out>.exe`
(or Editor → Project → Export → Windows Desktop). The prebuilt binary lives in
`build/EasyForge.exe`.

Not yet in v1: the 3D Model Maker (v2, designed in SPEC.md §10), user-own
asset import, AI image-gen, genre packs beyond platformer.

**Art:** one CC0 pack ships — Kenney *Pixel Platformer* in
`assets/kenney/pixel-platformer/` (License.txt included). Bricks ask for a
**look by name** (`Assets.texture("grass")`, `Assets.model_texture("coin")`)
through `src/assets/asset_registry.gd`, so the 2D world has a real grass-and-dirt
floor, sprite characters and coins, and the 3D ground and crates are textured.
Every lookup falls back to a primitive when a file is missing, so nothing breaks
if the pack is stripped. More packs = more entries in that one table; only
platformer-style art exists today.

**AI path: tested against live keys (Oct 2026).** A real draft came back as a
10-brick graph with zero validation problems and compiled into a playable 3D
scene in **~6 seconds on Groq** (`openai/gpt-oss-120b`, the default) — the same
test on NVIDIA took ~170s with `z-ai/glm-5.3-flash`, which is why Groq leads.
Things worth knowing:

- **NVIDIA's `/v1/models` is not a list of what works.** It returns ~80 ids for a
  free key and most 404 on `chat/completions` (qwen, minimax, kimi, mistral-large,
  codestral, gemma, granite all 404'd). Only reasoning models answered, and they
  spend the token budget thinking first.
- **Draft budgets are 12288 tokens** because smaller ones were measured to be
  swallowed entirely by thinking, leaving no answer at all.
- An empty answer, a truncated answer and a rejected model name now produce three
  different, actionable messages instead of "the AI couldn't build that".

See `SPEC.md` for every locked decision and `BUILD-LOG.md` for what was chosen
during the build.
