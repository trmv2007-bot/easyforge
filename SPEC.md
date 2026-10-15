# EasyForge — Product & Technical Spec (v1.0)

**Date:** 2026-10-09
**Status:** Pre-build, decisions locked
**Owner:** Rishi
**One-liner:** A Windows app where a beginner types a game idea in plain English, an AI draws it as an editable visual "brick diagram," and the user compiles that diagram into a playable game — no code, no engine knowledge.

---

## 1. Problem & Target User

**Who:** Absolute beginners making games. First user: Rishi's friend (a game streamer — knows games, does NOT know engines or code). App is for everyone, not streamer-specific.

**Pain:** "Unity is hard." Empty scene, node soup, C# debugging. Weeks to a first fun game.

**Why now:** 2026 free codegen (qwen2.5-coder, minimax-m2.7 via NVIDIA NIM; gemini-3.8-flash via Google; qwen2.5-coder local via Ollama) is good enough to scaffold real Godot 4 GDScript automatically.

**10-star vision:** Type "a 3D platformer where you collect coins and dodge enemies" → get a complete, editable brick diagram → hit Play → it runs → tweak one brick, watch the game change.

**Product identity:** Name **EasyForge**, home `C:\Users\rishi\easyforge`, English + multi-language UI from launch, ships as a one-double-click install for testers.

**Anti-goals (explicitly NOT building in v1):**
- NOT a from-scratch engine (we use Godot 4 + fork the open-source "Godot Assistant Pro" Game Forge agent).
- NOT replacing Godot's editor wholesale.
- NOT shipping Rishi's own API key inside the app (BYOK only).
- NOT stream/live integrations (no Twitch/chat/mic hooks). Games are standalone.
- NOT a marketplace, community, or hosting platform. The app makes games locally; the USER exports the finished game file and sends/posts it themselves. Nothing is uploaded or hosted by the app.
- NOT starting the user at an empty canvas (AI always drafts a working diagram first).

---

## 2. Core Concept — The Brick Pipeline

The heart of the product is an **intermediate representation (IR)** between the AI and the game code. The user never sees code; they see bricks. The user never sees an empty canvas; the AI drafts first.

```
English prompt
   │
   ▼
[ AI: Bricks Generator ]  ──► bricks.json  (spawn / move / collide / score / win-lose + user comments)
   │
   ▼
[ Brick Graph Editor ]     ◄── user edits: add / remove / reconnect / comment on bricks
   │
   ▼
[ Brick Compiler ]         ──► clean GDScript (one script per brick, wired together)
   │
   ▼
[ In-app Play ]            ──► instant preview, no browser
```

**Non-negotiable rule:** The user never starts from an empty graph. First run always produces a complete, working, pre-connected diagram. Learning happens by *tweaking one brick at a time and watching the game change*, not by building from nothing.

### The AI's job: two phases (locked)

**Phase A — Draft (AI).** The user describes what they want in plain English. The AI understands the rough idea, picks the right bricks for that genre, names them sensibly, and pre-connects them into a *complete working draft*. It never returns an empty or partial graph.

**Phase B — Finalize (AI + human).** The user rearranges / adds / removes / reconnects / comments on the bricks — the human owns the game's flow and logic. When the graph is wired the way they want, the AI reads the *completed graph* and adjusts / writes the game code so it actually runs accordingly.

This is the hybrid, and it's deliberate: AI drafts *structure*, the human owns *flow*, AI finalizes *wiring*. Magic where it helps; the deterministic compiler (you own) turns the settled graph into GDScript so the result is reliable and testable, not a black box.

---

## 3. The 5 Universal Bricks (learning template)

The demo/learning template must teach the 5 building blocks that appear in almost every game. Every project the AI builds is assembled from these brick types:

| Brick | Plain-English name | What it does in the game |
|---|---|---|
| **1. Spawn** | "When the game starts / when something appears" | Creates the player, enemies, items at start or on events |
| **2. Move** | "How things move" | Player controls, enemy patrol, gravity, jumping |
| **3. Collide / Trigger** | "When things touch or a condition is true" | Player touches coin, hits enemy, enters a zone |
| **4. Score / State** | "What changes — numbers, health, lives" | Score up, health down, lives, flags |
| **5. Win / Lose** | "When the game ends" | Reach goal, run out of lives, timer |

The guided first-run walks the user through one demo that uses **all 5**, so they learn every core concept in one pass. The AI pre-connects them; the user tweaks.

**Universality via library depth (not abstraction).** Bricks stay simple and concrete; the engine grows a **brick library per genre** (platformer bricks, chess bricks, VN bricks, racing bricks…). "Every type of game" = a deep, growing library, not one set of clever universal logic blocks (which would force the user to think like a programmer). One shared pipeline; each genre adds brick *types* that plug into it. v1 ships a demo genre's bricks done well; more genres are additive, not re-architecture.

---

## 4. Brick Format (the IR)

Each brick is a small JSON object — this is the file format the AI writes, the graph editor edits, and the compiler reads. Keeping the UI decoupled from this JSON is the single most important architectural choice (see §7).

```json
{
  "id": "brick_collide_coin",
  "type": "collide",
  "title": "When player touches a coin",
  "comment": "user wrote: I want coins to give +10 points",
  "inputs":  ["player", "coin"],
  "outputs": ["on_touch"],
  "connect": [
    { "from": "on_touch", "to": "brick_score_coin" }
  ]
}
```

- `type` — one of the 5 (spawn/move/collide/state/winlose) or a composite.
- `comment` — free text the user writes; fed back to the AI so it regenerates the *right* brick when behavior changes.
- `connect` — the wiring. The compiler reads this to know execution order and data flow.

Compiling: bricks → one `game.gd` per brick, wired by `connect`, emitting idiomatic Godot 4 GDScript. Changing one brick regenerates only that script; the rest stay stable.

---

## 5. AI Layer (BYOK — Bring Your Own Key)

**Decision: BYOK-first.** The user supplies their own API key. No key ships inside the app. This is how the product scales to many users without Rishi's account being drained or abused.

### Supported providers (free tiers, verified Oct 2026)

| Provider | Model | Free limit | Role |
|---|---|---|---|
| **NVIDIA NIM** | `qwen2.5-coder-32b-instruct` | 40 RPM, no card | **Primary** codegen |
| **NVIDIA NIM** | `minimax-m2.7` (230B) | 40 RPM | Heavy multi-step builds |
| **Google AI Studio** | `gemini-3.8-flash` | ~250/day | Fallback |
| **Ollama (local)** | `qwen2.5-coder:7b` Q4 | unmetered | Offline floor |

- NVIDIA: sign up build.nvidia.com (no card) → `nvapi-` key → base `https://integrate.api.nvidia.com/v1` (OpenAI-compatible).
- Gemini: aistudio.google.com → key.
- Ollama: install → `ollama pull qwen2.5-coder:7b` → runs on the user's GPU, zero key.

### Onboarding flow (simple, non-technical)

```
1. Welcome  → "Pick your AI brain"  [NVIDIA (recommended)] [Gemini] [Ollama]
2. Get key  → "Open signup page" (NVIDIA) → step-by-step copy instructions
3. Verify   → [Paste key] [Test key]  →  ✅ "key works"  /  ❌ "check you copied it all"
4. Done     → straight into the builder
```

- **Key storage:** local per-user config (`user://` in Godot), never in the project files, never sent anywhere except the provider the user picked.
- **"Test key" runs before anything works** — catches bad keys instantly instead of failing mid-build.
- If NVIDIA's UI is friction, the in-app "Get a free key" button opens the signup page with prefilled instructions; Ollama stays as the zero-setup fallback.

---

## 6. UX Rules

1. **Guided first-run + always-available help** (user's choice). First launch walks through the 5 bricks on a real demo. Help is one click away forever after.
2. **In-app instant preview.** Hit Play inside the app; no separate browser or window needed.
3. **Never an empty canvas.** AI always drafts a complete working diagram first.
4. **Universal, not niche.** No streamer-specific features. Games are standalone; the app makes them locally and exports a runnable file the user sends/posts themselves.
5. **Comment-to-AI loop.** The user writes plain-English comments on a brick; on regenerate, only that brick's code changes, guided by the comment.
6. **Escape hatch — Visual/Code toggle.** Bricks are the beginner layer, not a cage. Advanced users toggle to see and edit the generated GDScript directly on the same project. This keeps "every type of game" honest (chess rules, racing physics, custom shaders) — when bricks can't express it, code can. The user outgrows bricks without abandoning the project.
7. **2D and 3D both, one pipeline.** Bricks are tagged by dimension (2D/3D variants of move/collide/camera). Godot handles the split natively. v1 demos both a 3D game and a 2D game to prove the pipeline is dimension-agnostic.
8. **Typed ports, softly guided.** A brick port only connects to a compatible port (incompatible ones don't light up). This prevents garbage graphs *and* teaches what connects to what — the "simple as a game to understand" principle. Hint, never hard-block.
9. **AI memory = session context, not RAG.** Within a build the AI re-receives the complete compact brick JSON + chat history every turn, so it always holds the exact current graph (never "forgets" a brick). Bricks are tiny (5 types + per-genre additions), so this is cheap and always accurate. No vector DB / embeddings / infra — fits the offline-first, no-servers design. Cross-project recall ("remix my old game") is the only place RAG could enter, post-v1, and even then it would *augment* session memory, not replace it.

---

## 7. Architecture & Build Order

**Base:** Godot 4 (official builds — do NOT compile the engine; the dev box has 16GB RAM, fine for using Godot, not for building it) + fork of **Godot Assistant Pro** (open-source; its "Game Forge Agent" already does prompt→scripts→scenes, which is exactly our AI-build spine — we extend it, not rewrite it).

**Build order (deliberate — testable core first, UI last):**

1. **Brick IR + schema** — the JSON format (§4). Pure data, unit-testable.
2. **Brick Compiler** — JSON → GDScript. Testable with zero UI. *This is the deep module.*
3. **AI Bricks Generator** — English prompt → bricks.json (fork Assistant Pro's generator to emit bricks, not raw scenes).
4. **BYOK settings + provider relay** — onboarding, key test, model selection.
5. **Graph Editor UI** — Godot's built-in `GraphEdit` node renders/edits the JSON. (Last, because it's the swappable skin.)
6. **In-app Play preview + guided tutorial.**

**Rationale:** steps 1–4 are all testable headlessly. The UI only ever renders/edits the JSON, so the look can change later without touching the engine. This keeps the risky logic verifiable early.

**Step 0 — Godot install (prerequisite, not yet done).** Godot 4 is NOT installed on this machine. Before any code: install Godot 4.x (official build — the 16GB dev box can *use* Godot but not *compile* it) and the export templates for the target platform. 85GB free disk is plenty. This is the real first action.

---

## 8. Constraints & Risks

| Constraint | Impact |
|---|---|
| 16GB RAM, RTX 3050 8GB, 86GB free C: | Use official Godot builds; don't compile engine. Fine for dev + local Ollama. |
| No Rust/Cargo; node v26 + python 3.14 present | Godot/GDScript path fits; no need for a new toolchain. |
| NVIDIA free tier = shared 40 RPM, prompts logged, "not for production" | Acceptable for dev + friend; BYOK means each user's load is their own account. |
| AI-generated code can be wrong/broken | Compiler validates; in-app error surface shows a copyable report so the user can fix or send to Rishi. |
| Scope discipline | v1 = 5 universal bricks + one polished demo genre + local export. "Any game, zero errors" is not promised — AI needs the human-in-the-loop (the bricks) because generated code breaks. Genre packs are post-v1. |

---

## 9. v1 Definition of Done

- [ ] User installs, completes BYOK onboarding (NVIDIA recommended), "Test key" passes.
- [ ] User types a one-line game idea → AI returns a complete, pre-connected brick diagram (no empty canvas).
- [ ] Graph shows the 5 universal bricks, editable; user can add/remove/reconnect and comment.
- [ ] Compiler turns the diagram into working Godot 4 GDScript.
- [ ] In-app Play runs the game instantly.
- [ ] **Export** produces a runnable game file the user can send/post themselves (local, no hosting).
- [ ] Guided first-run tutorial teaches all 5 bricks on one demo.
- [ ] Changing one brick + comment → only that brick regenerates; game still runs.
- [ ] Ships as a clean one-double-click install (zip → unzip → run) for the friend-tester.
- [ ] UI is multi-language from launch (at minimum English + one second language; all strings externalized, none hardcoded).

## 10. Assets — Phased Strategy

The AI writes code, not art. Games need sprites/models/sound. Decision (locked):

| Phase | Source | Why |
|---|---|---|
| **v1** | **Bundled free CC0 asset packs (Kenney-style)** + AI places them by name; Godot primitives (box/sphere/cylinder) as fallback placeholders | $0, ~500MB-1GB disk, zero user setup, zero extra keys, games look real instantly |
| **v2** | **3D Model Maker** — in-app primitive composer (see below); **user-own assets** (drag in your own sprites/models) | customization; clean bolt-on because bricks reference models by name only |
| **Post-v1** | AI image-gen for custom sprites | only if users demand custom looks AND free-tier speed is solved (needs a 2nd BYOK key + wait — fights the fast/no-headache goal) |

### v2: The 3D Model Maker (designed now, built after the brick pipeline)

The user's own idea, adopted. A standalone 3D model editor inside the app:
- **Palette of primitive blocks** (box, sphere, cylinder, ramp) placed on a grid via Godot's built-in **GridMap** (this *is* a block-model maker — no engine fork).
- Scale / rotate / color each block; combine via **CSG** for compound shapes.
- **Group primitives into a named model**, save it, build multiple models, connect/assemble them (a "player_knight" = body + head + sword blocks).
- **AI assist, same pattern as bricks:** AI drafts a model from a text description (emits a JSON list of primitives: position/rotation/scale/color); user tweaks the selected block; AI refines *that block* from a comment. Identical IR philosophy — AI drafts, human tweaks.

**The clean seam (why this doesn't touch the brick pipeline):** bricks reference models **by name only** (`"model": "player_knight"`); they never store how the model is built. In v1 bricks point at bundled Kenney assets by name (model maker doesn't exist yet — nothing breaks). In v2 the model maker starts producing models and bricks point at *those* names instead. **Zero changes to the brick pipeline.** Two clean launches, they snap together later.

## 11. Post-v1 (explicitly out of scope now)

- Genre template packs (platformer, RPG, runner…) — additive brick libraries.
- The 3D Model Maker (v2, designed above).
- User-own asset import.
- AI image-gen for assets.
- Community asset marketplace.
- Usage analytics / paid tier behind a relay.
- Cross-project RAG recall ("remix my old game").
- Any live/stream integration.
