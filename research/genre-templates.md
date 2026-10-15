# Genre Packs & Template Systems — Gap Analysis

EasyForge ships ONE platformer demo and a flat 19-brick library. Every mature no-code
engine solves the "blank canvas" problem the same way: **a picker of genre starting
points that are already playable, plus genre-tuned behavior defaults**. EasyForge's
architecture already anticipates this (register_pack + demo template + compiler cases);
the missing piece is the *breadth and packaging*.

## The convergent pattern (what EasyForge lacks)

1. A **New Project picker** with several playable genre demos (not one platformer).
2. Each demo ships with **genre-tuned defaults** (gravity/jump, camera, control scheme)
   baked in — GDevelop's platformer defaults (jump speed ~900, gravity ~1500, max speed
   ~250) are the canonical example.
3. Genre demos act as **teaching artifacts** — "open the template, edit one thing,
   press play, see it change."
4. Templates are **tiered by difficulty** (Construct's Beginner/Intermediate/Advanced)
   so a beginner isn't handed a metroidvania first.

## What the competition does

- **GDevelop** — hundreds of free + premium genre templates, each a playable example
  project you open and edit (Platformer, Top-down RPG, Space shooter, Zombie laser,
  Rhythm, Tetris, Metroidvania, Beat 'em up, Roguelite, Match-3...).
- **Construct 3** — Example Browser with hundreds of projects tagged by Level
  (Beginner/Intermediate/Advanced), Category, Genre, 3D/Mobile; Beginner's Templates on
  the Start Page.
- **GameMaker** — Project Templates based on official tutorial content; templates tied
  to tutorials (template and lesson teach the same game).
- **RPG Maker** — sample games per release + genre packs each shipped with a sample
  project showing what the plugin does.
- **GB Studio** — Sample Project template on the New Project dialog; docs recommend
  starting there and editing dialogue/triggers as your first act.
- **Buildbox** — Template Library, each "a mini-game with prebuilt functionality you can
  edit"; Smart Assets with preset animations+logic.
- **Core** — Frameworks (Deathmatch, Dungeon, Racing) — start with functioning game
  logic, focus on level design.
- **Stencyl** — Kits: game template + pre-made resources + settings + game logic.

## Feature inventory (mapping)

- **F1. Genre demo gallery** (New Project -> pick a genre) — each demo = a saved
  brick-graph JSON + register_pack + a couple of compiler cases. S per demo once
  scaffolding exists (~2-4 dev-days each). Very high impact — removes blank-canvas
  paralysis, the top beginner failure mode.
- **F2. Genre-specific brick sets** — literally register_pack(name, bricks); UI filters
  the palette by active genre. S-M per genre. High impact.
- **F3. Genre-appropriate default settings** — gravity/jump/camera/control presets baked
  into the demo's brick graph. S effort, high impact.
- **F4. Tutorial games that teach a genre** — numbered comments + a 3-step checklist.
  M per genre, high impact.
- **F5. Tiered gallery** (Beginner/Intermediate/Advanced tags) — metadata + UI sort. S.
- **F6. Genre sample art / themed primitives** — per-genre procedural color palettes +
  shape presets on brick instances. S-M, medium-high.
- **F7. Sample levels per genre** — a designed 1-screen level inside each demo. S.
- **F8. Clone/remix-first New Project flow** — explicit "Start from this template" as
  the primary CTA; blank project demoted. S, high impact.
- **F9. Genre presets on the AI text-draft path** — classify intent -> pick genre pack +
  demo as the AI's scaffold. M, medium-high.
- **F10. Template community/import-export** — needs hosting infra; deferred (conflicts
  with local standalone posture).

## Which 2-3 genres to add first

**Top-down shooter, Visual novel, Endless runner** (in that order).

**Top-down shooter first** — canonical first game in no-code engines (Construct's Ghost
Shooter beginner template, GDevelop's Zombie laser, GameMaker's Arena Shooter). Only ~2
new bricks (Aim/Shoot with mouse, WaveSpawn) + 3 compiler cases; reuses 15+ existing
bricks; no-gravity defaults are trivial; extremely wide appeal.

**Visual novel second** — cheapest compiler work of any genre (linear dialogue emitter,
no physics); opens a user segment no other genre touches (story-first, often
non-"gamer" users — the exact "describe your game in English" audience); Ren'Py proves
the onboarding model; reuses Timer/WinLose/Sound.

**Endless runner third** — overlaps the platformer demo; mostly AutoScroll +
SpawnObstacle + side-scroll defaults; matches the most popular no-code template category
(Buildbox's library is dominated by runners).

**What NOT to do first:** Metroidvania, roguelike, fighting, rhythm — all real demand but
each needs 6+ bricks, procgen or state-machine compiler work, heavier art/default tuning.

## Top 5 (ranked)

1. **Genre demo gallery with clone-first New Project flow** (F1+F8, seeded with the 3
   genres above) — the single highest-impact change; every competitor's onboarding is
   "pick a playable template"; EasyForge already has the machinery.
2. **Top-down shooter genre pack first** — canonical beginner genre; ~2 new bricks + ~3
   deterministic compiler cases; reuses 15+ existing bricks; trivial defaults.
3. **Genre-appropriate default settings + sample art per demo** (F3+F6) — baked
   gravity/jump/camera/control presets + per-genre procedural palettes; near-zero new
   system cost.
4. **Visual novel pack second** — cheapest compiler work; unlocks story-first users;
   directly feeds the AI text-draft path.
5. **Tutorial-game layer + tiered difficulty tags** (F4+F5) — guided tours + Beginner/
   Advanced tags; pure metadata + UI overlay, no compiler risk.
