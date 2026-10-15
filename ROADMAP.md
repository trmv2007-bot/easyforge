# EasyForge — Feature Roadmap (from 6-domain competitive research)

**Date:** 2026-10-10
**Method:** 6 parallel research agents surveyed no-code/AI game engines (Construct 3,
GDevelop, GameMaker, Buildbox, Core, Dreams, Stencyl, RPG Maker, GB Studio, Rosebud,
Ren'Py, Roblox Build, itch.io/CrazyGames/Poki/Newgrounds) across 6 domains, each
mapping competitor features onto our Godot-4.7 + brick-IR + deterministic-compiler
architecture. Constraints held throughout: no engine fork, no raw code for the user,
deterministic bricks(JSON)->GDScript, 16GB/RTX3050, BYOK AI, local standalone games.

**The one structural insight (from the gameplay-logic domain):**
> EasyForge scales as **O(new brick types)** — every new mechanic today needs a
> hand-written brick + compiler codegen path. Competitors scale as **O(new rules on
> existing bricks)**. The single highest-leverage change is a **Rule / if-then brick**
> that reifies conditions into first-class data nodes. That one primitive unlocks
> state machines, waves, inventory, win/lose variety, and AI drafting at near-zero
> marginal compiler cost. Build it early.

---

## Consolidated Top Recommendations (cross-domain, ranked by impact/effort)

### Tier 0 — Foundation (do first, unblocks the most)
1. **Variables & scopes** (gameplay) — global/scene/per-object number+bool+text.
   Backed by the GameState autoload + per-node metadata. M effort. Highest-frequency
   beginner request; the foundation for inventory, win/lose variety, state.
2. **Rule / If-Then brick** (gameplay) — condition slots -> action slots with a
   curated vocabulary (Collided-with / Variable-compare / Timer-elapsed / Key-pressed
   / State-equals -> Add-variable / Set-state / Start-timer / Spawn / Play-sound).
   L effort but converts the roadmap from O(bricks) to O(rules). **The enabler.**
3. **IR validation + bounded self-correction** (AI) — validate the brick graph BEFORE
   compiling; feed compiler errors back to the AI for a capped retry, then auto-revert.
   Unique advantage of our deterministic compiler; attacks the category's #1 complaint
   ("chat edits break games"). M effort.

### Tier 1 — v1.5 (high impact, small-medium effort)
4. **Game-feel knobs** (gameplay) — coyote time ~0.1s, jump buffer ~0.12s, variable
   jump height (jump-cut x0.45), asymmetric gravity (fall 1.7x rise). S effort.
   Invisible when right, game-ruining when absent. Biggest perceived-quality jump/hour.
5. **Physics surface params** (gameplay) — one-way collision toggle, bounce 0-1,
   friction 0-1 sliders + ice/trampoline presets on Platform/Ground. S effort.
   Kills the #1 beginner level-design frustration (bumping head, falling).
6. **Multi-scene levels + Door/Portal + Entry Point bricks** (world) — promote the
   project from one graph to a level list; connect levels. M effort. The moment a
   beginner stops seeing their project as a toy.
7. **Parallax Background brick** (world/visuals) — 1-3 Parallax2D layers, procedural
   gradients. S-M effort. Highest polish-per-line-of-code win.
8. **Camera bounds + world size + checkpoint persistence across levels** (world) —
   three S-effort fixes removing death loops, the void-at-edges, and no-way-back.
9. **Sky/Environment presets** (world) — day/sunset/night/foggy/space via
   WorldEnvironment + ProceduralSkyMaterial. S effort. Makes 3D stop looking broken.
10. **2D Lighting brick** (visuals) — point/directional lights + shadows. M effort.
    Instant mood/depth (torches, caves, night).
11. **Game Juice pack** (visuals) — camera shake/zoom-punch/lerp + screen transitions
    (fade/wipe) + light vignette/tint/bloom post-FX. M effort. Student->real-game feel.
12. **One-click Style & Palette presets** (visuals) — global look system
    (pixel/flat/neon) that recolors every brick + particles + background. S-M effort.
    Fastest "make it look good."
13. **Iterative chat that mutates the brick graph** (AI) — persistent chat panel that
    edits the existing game via a structured diff (add/modify/reconnect + param deltas),
    not a from-scratch regen. M effort. The conversation IS the product for beginners.
14. **AI explains what it changed + per-turn undo** (AI) — plain-language summary
    rendered from the diff + one undo entry per AI edit. S effort. Huge trust value.
15. **AI suggests the next bricks** (AI) — "has Jump but no enemy -> add EnemyPatrol +
    Score" from a curated pattern library. S-M effort. Kills blank-canvas paralysis.
16. **Genre demo gallery + clone-first New Project** (genre) — 8-12 finished playable
    genre demos; each = a saved brick graph + register_pack. S scaffolding, ~2-4 days
    per demo. Every competitor's onboarding is "pick a playable template."
17. **Web (HTML5) export — "Publish to Web"** (sharing) — Godot official single-thread
    web templates (iframe-safe, no COOP/COEP). M effort. Every competitor's headline
    share flow; the only way a friend plays with zero install.
18. **Shareable play link** (sharing) — anonymous static-host deploy + copy/QR, honest
    "public link" wording. M effort. Converts the export dead-end into the friend loop.

### Tier 2 — v2 (medium effort or unlocks more)
19. **Timers as first-class bricks** (gameplay) — per-node named timers, every-N-seconds
    repeat, Wait action, global time-scale (slow-mo/hit-stop). S-M effort.
20. **Visual Particle Editor** (visuals) — fully editable params + live preview on the
    Particles brick (Godot GPUParticles2D already supports it). M effort.
21. **Tilemap paint canvas + procedural tile palette + terrain autotile** (world) — the
    biggest L-effort item, but the one every competitor treats as core; creates the
    surface AI level-drafting will later target.
22. **Level select screen generator** (world) — from the level list with locked/unlocked
    state. S-M effort. Turns a demo into a shipped game.
23. **Trigger Zone brick** (world) — resizable invisible volume that fires bricks on
    enter/exit; the composability glue for doors/cutscenes/score. S-M effort.
24. **Inventory / item system** (gameplay) — add/remove/has/count backed by a per-player
    Dictionary. M effort (thin once variables exist). "Collect 3 keys to open the door."
25. **State machine** (gameplay) — state variable + transition rules (patrol->chase->
    attack). S-M once variables+rules exist. The #2 beginner request after variables.
26. **Random & spawn waves** (gameplay) — S once rules+timers exist. Wave shooters are
    the most common genre after platformers.
27. **Dialogue (linear -> branching)** (gameplay) — Say/Choice bricks; VN pack. M->L.
28. **Lives/health UI** (gameplay) — procedural bars/hearts HUD. S-M.
29. **Screen shake / hit-stop** (gameplay) — camera impulse + frame-freeze. S-M.
30. **Pathfinding chase** (gameplay) — NavigationAgent2D smart-avoid. M.
31. **Procedural sprite/character library** (visuals) — part-based generator + palette
    swatches + curated starter pack. M-L. Removes the "I have no art" blocker.
32. **UI/Menu designer** (visuals) — title/pause/game-over/HUD screen templates. L.
33. **itch.io one-click publish via butler** (sharing) — game page + thumbnail + free
    analytics on the user's own account. M effort.
34. **Top-down shooter genre pack** (genre) — canonical first game; ~2 new bricks
    (Aim/Shoot, WaveSpawn) + ~3 compiler cases. S effort, best genre ROI.
35. **Visual novel pack** (genre) — cheapest compiler work; unlocks story-first users. S-M.
36. **Tutorial-game layer + tiered Beginner/Advanced tags** (genre) — guided tours +
    difficulty tiers. Metadata + UI overlay only.
37. **Brick-scoped natural-language editing + voice** (AI) — "make this enemy slower" on
    a selected brick + local STT. S-M.

### Tier 3 — Later / deprioritized
- Web export size discipline + mobile-browser touch support (sharing) — S/M, but only
  matters once web export ships.
- 3D GridMap block building, persistent world state, day-night, 2.5D, skeletal
  animation, timeline/sequence, beginner shaders.
- AI level drafting, playtest-by-AI auto-balance, AI asset gen, cross-project remix.
- Local high-score persistence (S, on-stance); Android export (L, heavy toolchain).

### Explicitly rejected / out of scope
- Hosted leaderboards, cloud saves (conflicts with no-hosting stance — local `user://`
  is the on-stance version).
- iOS/console export (infeasible on a single Windows machine).
- Real-time collaborative editing (no netcode; L distributed-systems problem).
- External Tiled/LDtk import (conflicts with the no-code, primitives-only positioning).
- Steam integration (guidance only; $100 fee + native-exe-only).

---

## Per-domain detail

See the six findings docs in this folder:
- `research/world-building.md`
- `research/gameplay-logic.md`
- `research/visuals-art-polish.md`
- `research/ai-editor-ux.md`
- `research/sharing-shipping.md`
- `research/genre-templates.md`

## Recommended sequencing

**Wave 1 (foundation):** Variables -> Rule brick -> IR validation + self-correction.
**Wave 2 (v1.5 quick wins):** game-feel knobs + physics params + parallax + camera
bounds/checkpoints + sky presets + style presets.
**Wave 3 (v1.5 world + AI):** multi-level + doors + iterative chat + AI-explain/undo +
suggestions + genre gallery + web export.
**Wave 4 (v2 depth):** timers + particle editor + tilemap + level select + inventory +
state machines + top-down shooter + VN + itch publish.
