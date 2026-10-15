# EasyForge — Genre Packs & Template Systems: Competitive Findings

Research date: 2026-10-10. Sources: GDevelop, Construct 3, GameMaker, RPG Maker, GB Studio, Buildbox, Core, Stencyl, Ren'Py, Godot ecosystem (asset library + official demo projects), plus beginner-retention commentary. All claims below are grounded in the cited sources.

EasyForge today ships ONE platformer demo and a flat 19-brick library. Every mature no-code engine solves the "blank canvas" problem the same way: **a picker of genre starting points that are already playable, plus genre-tuned behavior defaults**. EasyForge's architecture already anticipates this (register_pack + demo template + compiler cases); the missing piece is the *breadth and packaging* of those starting points.

---

## 1. What the competition actually does (the pattern to copy)

| Engine | Template/starter system | Key mechanic of it |
|---|---|---|
| **GDevelop** | Hundreds of free + premium genre templates: Platformer, Top-down RPG, Space shooter, Zombie laser (wave defense), Rhythm, Tetris (SRS+ghost), Metroidvania, Beat 'em up, Fighting, Roguelite, RTS, Puzzle, Match-3, racing. Each is a **playable example project you open and edit**, not a blank project. (gdevelop.io/game-example) | "Discover and try this example" — every template is one click to play, one click to open. |
| **Construct 3** | Example Browser with hundreds of projects, **tagged by Level (Beginner/Intermediate/Advanced), Category (Demo game / Guided tour / Game template / Barebones template / Gameplay mechanic), Genre, plus 3D/Mobile tags**. Beginner's Templates on the Start Page (e.g. Ghost Shooter top-down shooter). Level Up guide walks beginners to a named template. (construct.net docs) | Tag-based browsing + tiered difficulty so beginners never drown. |
| **GameMaker** | Project Templates ("wireframe projects to get you up and running fast") based on official tutorial content; user can create and share own templates; marketplace hosts genre templates (top-down, platformer, racing mode-7, pinball). (gamemaker.io blog, marketplace) | Templates tied to tutorials: template and lesson teach the same game. |
| **RPG Maker** | Default sample game + multiple sample games per release (Unite ships 8), plus genre packs (SRPG Gear, ARPG plugin) each shipped **with a sample project showing what the plugin does**. (rpgmakerweb.com, rpgmakerunite.com) | Genre = pack of assets + logic + a working demo. |
| **GB Studio** | Sample Project template on the New Project dialog — "contains a few example scenes and scripts already set up"; docs explicitly recommend starting there and *editing dialogue/triggers* as your first act. Community supplies more sample projects (dungeon crawler, HUD, isometric). (gbstudio.dev docs, gbstudiocentral) | The first thing a new user touches is a small, finished, tweakable game. |
| **Buildbox** | Built-in Template Library (Martian Marathon space shooter, Interstellar Strike, Dagger Toss…), each "a mini-game with prebuilt functionality you can edit"; Smart Assets with preset animations+logic. (buildbox.com) | Template-first onboarding for mobile. |
| **Core** | Frameworks (Deathmatch, Dungeon, Racing, Tower of Terror) — start with functioning game logic, focus on level design; hundreds of "open for editing" community games as bases. (docs.coregames.com) | Framework = working logic, you design the world. |
| **Stencyl** | Kits: "a game template that comes with pre-made resources, settings and game logic" (Jump and Run Kit, Crash Course Kit). (stencyl.com) | Kit bundles assets + settings + logic together. |
| **Ren'Py** | Quickstart builds a tiny complete VN ("The Question") step by step; launcher ships the finished tutorial + The Question as playable references. (renpy.org docs) | Play the reference game first, then make yours. |
| **Godot (ecosystem)** | Asset Library templates: 2D Platformer starter, Top-Down Twin-Stick Shooter, Top-down Action RPG, DungeonCrawler3D, Metroidvania templates, VN templates (Rakugo), racing, isometric, FPS. (godotengine.org asset library) | Confirms Godot-native genre templates are in demand and producible. |

**Convergent pattern (what EasyForge lacks):**
1. A **New Project picker** with several playable genre demos (not one platformer).
2. Each demo ships with **genre-tuned defaults** (gravity/jump values, camera behavior, control scheme) baked in — GDevelop's platformer behavior defaults (jump speed ~900, gravity ~1500, max speed ~250) are the canonical example of "settings that feel right out of the box."
3. Genre demos act as **teaching artifacts** — every engine pairs "open the template" with "edit one thing, press play, see it change." GB Studio and GameMaker make this explicit.
4. Templates are **tiered by difficulty** (Construct's Beginner/Intermediate/Advanced tags) so a beginner isn't handed a metroidvania first.

---

## 2. Feature inventory — each feature: description, EasyForge mapping, effort, impact, fit

### F1. Genre demo gallery (New Project → pick a genre)
- **What:** A start screen offering 8–12 finished, playable one-level demo games per genre; pick one and it becomes your project (clone-and-tweak, like GB Studio's Sample Project / GDevelop's examples / Buildbox templates).
- **EasyForge mapping:** Each demo = a saved brick-graph JSON (exactly today's platformer demo, repeated per genre) + `register_pack("topdown_shooter", bricks=[...])` + a couple of compiler cases for any new brick semantics. The gallery is the existing "open demo" flow generalized. Deterministic compiler untouched in core — genre packs are data.
- **Effort:** S per demo once the pack scaffolding exists (~2–4 dev-days each: brick graph + tuned defaults + sample level + thumbnail/readme à la GDevelop's 1280×720 thumbnail + readme.md convention).
- **Impact (beginner):** Very high. Removes blank-canvas paralysis — the single most cited beginner failure mode ("a good remix beats a blank canvas every time"; GDevelop's entire adoption strategy).
- **Fit with constraints:** Perfect. Demo = JSON brick graph, no engine fork, no new runtime, tiny disk cost (primitives only). Fits "deterministic bricks→GDScript."

### F2. Genre-specific brick sets (behavior packs per genre)
- **What:** Brick palette narrows/tunes per genre. Platformer gets DoubleJump/WallJump/CoyoteTime; shooter gets Aim/Shoot/Reload/WaveSpawn; TD gets Path/Wave/TowerPlace; puzzle gets Grid/Match/BlockFall; VN gets Say/Choice/Character; racing gets Checkpoint/Lap/Boost.
- **EasyForge mapping:** The registry already registers brick packs per genre. This is literally `register_pack(name, bricks)`. Compiler handles new brick types via new cases (small, deterministic GDScript emitters). UI filters the brick palette by active genre pack.
- **Effort:** S–M per genre (each new brick = one compiler case + one inspector settings schema, reusing the existing click-a-brick inspector and remappable-controls machinery).
- **Impact:** High. Beginner sees only the ~8 bricks relevant to their game; ShooterWaves etc. come pre-tuned. Mirrors GDevelop behaviors, Stencyl kits, RPG Maker packs.
- **Fit:** Perfect — pure data + deterministic compiler extension; no Godot fork.

### F3. Genre-appropriate default settings baked into the demo
- **What:** Starting values that "just work": platformer gravity ~1500/jump speed ~900/max speed ~250 (GDevelop canonical); top-down: no gravity, 8-way or mouse-aim movement, camera centered on player; TD: camera zoomed out, click-to-place; VN: fixed camera, text box layout, click-to-advance.
- **EasyForge mapping:** The demo's brick-graph JSON simply carries these values as the spawn/player brick's default settings — the inspector already exposes grouped editable settings, so the "defaults" are just pre-set inspector values the user tweaks.
- **Effort:** S (part of authoring each demo; no new system).
- **Impact:** High — game feel out of the box; beginners don't know what gravity "should" be.
- **Fit:** Perfect (settings are data in the brick graph).

### F4. Tutorial games that teach a genre (paired template + lesson)
- **What:** A guided variant of each demo: numbered comments/callouts in the graph, a 3-step "change this, press play, see it change" checklist (GB Studio's "edit a signpost's dialogue and rerun"; Construct's guided tours; GameMaker's tutorial-derived templates; Ren'Py's The Question walkthrough).
- **EasyForge mapping:** Annotations attached to nodes in the demo graph + a side panel checklist. No compiler change; optional "tour mode" flag in the demo metadata.
- **Effort:** M per genre (writing the guided narrative per demo).
- **Impact:** High — turns each demo into the onboarding for its genre; matches how GameMaker/GB Studio/Ren'Py onboard.
- **Fit:** Perfect (metadata + UI overlay).

### F5. Tiered gallery (Beginner / Intermediate / Advanced tags)
- **What:** Difficulty tiers on demos like Construct's Level tags — 3 beginner demos surfaced first.
- **EasyForge mapping:** Metadata field on each demo entry; UI sorting/filtering.
- **Effort:** S.
- **Impact:** Medium-high — prevents beginners opening a roguelike and bouncing.
- **Fit:** Perfect.

### F6. Genre sample art / themed primitives
- **What:** Genre-matched placeholder art: platformer → pixel-ish tiles + coin; shooter → topdown ship/zombie; TD → path tiles + towers; VN → portrait boxes + backgrounds. (GDevelop asset packs per template; Kenney CC0 packs per genre; RPG Maker's huge bundled asset trove.)
- **EasyForge mapping:** EasyForge uses primitives + procedural color, so "art" = per-genre procedural color palettes/shape presets attached to demo objects (e.g. a `palette` field on brick instances, theme = procedural). No image pipeline needed.
- **Effort:** S–M (define palettes + shape presets per genre; reuse existing procedural color system).
- **Impact:** Medium-high — a themed screenshot sells the genre instantly and makes tweaking meaningful ("change the color, it's your game").
- **Fit:** Good — must stay within "primitives + procedural color" constraint; palettes satisfy it.

### F7. Sample levels per genre (pre-placed demo level in the graph)
- **What:** A designed 1-screen/1-wave level inside each demo (GDevelop templates each ship a finished level; RPG Maker ships sample maps; Core frameworks ship a level).
- **EasyForge mapping:** Demo brick graph contains an authored level layout (positions baked as brick instance data). Cheapest possible: copy of today's platformer demo level pattern per genre.
- **Effort:** S per genre (level authoring is placing bricks and saving).
- **Impact:** High — the "already playable" quality is what makes templates work.
- **Fit:** Perfect.

### F8. Clone/remix-first New Project flow ("Duplicate this game")
- **What:** Explicit "Start from this template" as the primary CTA; blank project demoted (GB Studio literally opens the Sample Project and tells you to break it).
- **EasyForge mapping:** One dialog in the New Project flow listing gallery demos with thumbnails + one-line pitch (GDevelop readme/thumbnail convention). Save/load already exists → "duplicate" = load + save-as.
- **Effort:** S.
- **Impact:** High.
- **Fit:** Perfect.

### F9. Genre presets on the AI text-draft path
- **What:** When AI drafts a brick graph from text, bias brick selection and defaults by detected genre ("make a tower defense" → TD pack + TD defaults), like how engines map a request to the closest template.
- **EasyForge mapping:** Prompt-side: classify intent → pick genre pack + demo as the AI's scaffold before it refines. Compiler unchanged.
- **Effort:** M (prompt engineering + validation that the AI's output matches the pack's brick vocabulary).
- **Impact:** Medium-high — connects the existing AI feature to the new gallery.
- **Fit:** Perfect.

### F10. Template community/import-export
- **What:** Users export/share their game as a template (.yyz in GameMaker; .c3p in Construct; zip in GDevelop) for a community library.
- **EasyForge mapping:** Save/load already persists projects; export-to-file exists → a "share as template" is a metadata flag on export. Community gallery needs infra we don't have (out of scope for now).
- **Effort:** L (needs hosting/moderation infra; explicitly deferred — local standalone, no netcode, and no backend in constraints).
- **Impact:** Medium long-term.
- **Fit:** Poor for now — conflicts with "local standalone" posture; defer.

---

## 3. Genre shortlist with effort estimates (per genre, assuming F1–F8 scaffolding)

| Genre | New bricks needed (beyond the existing 19) | Compiler cases | Defaults/sample art | Effort | Beginner impact |
|---|---|---|---|---|---|
| **Top-down shooter / wave defense** | Aim/Shoot (mouse), WaveSpawn, maybe Ammo | 2–3 | top-down palette, no gravity, mouse-aim | **S** | Very high — Construct's canonical beginner template (Ghost Shooter); GDevelop's Zombie laser; 2nd most common first game after platformer |
| **Endless runner / dodge** | AutoScroll, SpawnObstacle | 1–2 | side-scroll palette | **S** | High — hyper-casual staple (Buildbox templates are dominated by runners) |
| **Puzzle (grid / match / block-fall)** | Grid snap, Match check, BlockFall, RowClear | 3–5 | grid palette | **M** | High — GDevelop ships Tetris demo, Sokoban, match-3; puzzle is beginner-friendly (accessible controls, simple goals) |
| **Visual novel / interactive story** | Say/Dialogue, Choice branch, Character show/hide, Scene bg | 3–4 (dialogue compiler = linear emitter) | VN palette + textbox layout | **S–M** | Very high for story-first users; Ren'Py proves it's the easiest genre to ship; VN noted as surprisingly strong indie category |
| **Tower defense** | Path waypoints, Wave, TowerPlace, EnemyFollowPath | 4–5 | TD palette | **M** | Medium-high |
| **Top-down adventure / Zelda-like** | Room transitions, NPC talk, Chest/Key, SwordAttack | 4–6 | topdown palette | **M–L** | High — GDevelop "how to make Zelda" is a flagship tutorial; top-down RPG template exists |
| **Racing** | Lap/Checkpoint (have Checkpoint), Boost, Camera follow-behind | 2–3 | racing palette | **S–M** | Medium — Buildbox/Core racer templates; needs 3D camera work for behind-view |
| **Fighting / beat-'em-up** | Health (have), Hitbox, Combo state, Enemy AI | 4–6 | fighting palette | **L** | Medium |
| **Metroidvania** | Ability-gated doors, map rooms, save points | 6+ | metroidvania palette | **L** | Medium — GDevelop sells a premium metroidvania template; high effort, great payoff but not first |
| **Roguelike** | Random room gen, permadeath, upgrades | 6+ | roguelike palette | **L** | Medium — GDevelop has roguelite template + tutorial; heavy procgen compiler work |
| **Rhythm** | Beat sync, timing windows | 3–4 (needs audio clock wiring) | rhythm palette | **M–L** | Medium |
| **Point-and-click adventure** | Hotspot, Inventory, Dialogue tree | 4–5 | P&C palette | **M** | Medium |

---

## 4. Which 2–3 genres to add first (and why)

**Recommendation: Top-down shooter, Visual novel, Endless runner** (in that order), each shipped as F1+F2+F3+F7 (gallery demo + small brick pack + tuned defaults + sample level).

**Why top-down shooter first:**
- It's the canonical *first game* in no-code engines: Construct 3's Beginner's Template is literally Ghost Shooter, a top-down shooter (Level Up guide). GDevelop's most-linked beginner examples are wave-defense/shooters (Zombie laser, space invaders, Geometry monster). GameMaker's official tutorials include Arena Shooter.
- Minimal compiler delta over what we have: we already own Spawn/Move/Collide/Score/WinLose/Health/Follow. We need ~2 new bricks (Aim/Shoot with mouse, WaveSpawn) — both trivially deterministic.
- Defaults are simple (no gravity; mouse-aim; camera follows) — lowest risk of "feels wrong."
- Extremely wide appeal (players instantly recognize it) and easy to demo in a 5-minute video.

**Why visual novel second:**
- Cheapest possible compiler work: dialogue/choices are linear, deterministic GDScript — no physics, no collision complexity.
- Opens a user segment no other genre touches (story-first, often non-"gamer" users — the exact EasyForge "describe your game in English" audience). VNs are also the cheapest indie genre to produce (high indie survival rate per the r/gamedev data).
- Ren'Py proves the onboarding model: play the tiny reference game, tweak one line, rerun. EasyForge can replicate this exactly with a Say/Choice demo.
- Reuses existing bricks heavily: Timer/WinLose/Sound; adds Say/Choice/Character/Scene.

**Why endless runner third:**
- Slightly overlaps the platformer demo we already ship (movement + jump + obstacles), so incremental effort is minimal — mostly AutoScroll + SpawnObstacle + side-scroll defaults.
- Matches the most popular no-code template category overall (Buildbox's library is dominated by runners; GDevelop has "Infinite Jump", "Endless up runner", "Geodash", "Run dino run").
- Great "make it yours in 2 minutes" demo.

**What NOT to do first:** Metroidvania, roguelike, fighting, rhythm — all real demand (GDevelop sells premium templates for these) but each needs 6+ bricks, procgen or state-machine compiler work, and heavier art/default tuning; they're second-wave once the gallery scaffolding (F1/F5/F8) exists and one genre proves the pipeline end-to-end.

---

## 5. Top 5 ranked recommendations (impact per effort)

1. **Genre demo gallery with clone-first New Project flow (F1+F8, seeded with the 3 genres above)** — the single highest-impact change; every competitor's onboarding is "pick a playable template," and EasyForge already has the machinery (saved brick graphs + register_pack) plus one working demo to clone the pattern from. Effort S for scaffolding, ~2–4 days per demo after that.
2. **Top-down shooter genre pack first** — canonical beginner genre across GDevelop/Construct/GameMaker; only ~2 new bricks + 3 compiler cases; reuses 15+ existing bricks; no-gravity defaults are trivial. Best genre-specific ROI.
3. **Genre-appropriate default settings + sample art per demo (F3+F6)** — baked gravity/jump/camera/control presets (GDevelop's platformer behavior is the reference implementation) and per-genre procedural color palettes. Makes every demo "feel right" instantly; near-zero new system cost (data in the brick graph + palettes).
4. **Visual novel pack second** — cheapest compiler work of any genre (linear dialogue emitter), unlocks story-first users, and directly reuses the "describe your game in English" AI flow (F9) — AI-drafted VN graphs need only Say/Choice.
5. **Tutorial-game layer on each demo (F4) + tiered Beginner/Advanced tags (F5)** — guided "change one thing, press play" tours (GB Studio/Ren'Py/GameMaker model) and difficulty tiers (Construct model) so beginners start with the 3 beginner demos; pure metadata + UI overlay, no compiler risk.
