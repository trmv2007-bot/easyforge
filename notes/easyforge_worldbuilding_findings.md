# EasyForge: World-Building & Level-Design Gap Analysis
Competitive research (Construct 3, GDevelop, Buildbox, Core/Manticore, Dreams, RPG in a Box, GB Studio, GameMaker) mapped onto the EasyForge brick-IR + deterministic Godot 4.7 GDScript compiler.

## 1. Executive summary

EasyForge today is a **behavior engine**: bricks define what things do (spawn, move, collide, score), and the compiler emits a single scene. What EasyForge does not yet have is a **world layer** — a place where the player builds the *space* the behaviors happen in.

Every competitor ships that world layer as a first-class surface:

- **Construct 3** — Layout view + Tilemap object with Tilemap Bar (pencil, rectangle, auto-tile, erase, brushes), per-tile collision polygons, layers with per-layer parallax.
- **GDevelop** — Scene editor (PIXI.js canvas), built-in Tilemap object with brush/rect/fill-bucket/erase + per-tile hitboxes, layers with per-layer parallax and scale, plus external Tiled/LDtk import.
- **GameMaker** — Room editor: tile layers paint from a Tile Set asset, image-to-tilemap conversion, room width/height (world size), persistent rooms, entry/exit object pairs for level connections, save instance data on room exit.
- **Buildbox** — a Mind Map of World nodes and UI nodes; a World = a sequence of scenes; UI screens include Main Menu, Level Select, Character Select, Game End; drag-and-drop level editor.
- **Core (Manticore)** — kitbash 3D worlds from a mesh library, spawn/capture points, terrain heightmaps, tree scatter, weather themes; trigger zones as placeable volume gadgets.
- **Dreams** — sculpt/paint/clone-repeat tools, trigger zones (resizable sphere/cube/cone volumes wired to logic), keyframe gadgets, level-linking with variables passed between levels.
- **RPG in a Box** — voxel editor for tiles/objects + grid Map Editor with walkable/passable per tile, multi-level maps, fog of war.
- **GB Studio** — scene-per-screen model, collision tile painting, parallax slices (up to 3, different scroll speeds), explicit camera bounds (min/max), Change Scene events with named destination positions, On Init / On Hit scripts.

Common pattern: **level geometry lives on a canvas you paint or place onto**, and levels are connected to each other by explicit door/portal/exit objects, with a persistent save layer and a level-select front-end.

The encouraging half: Godot 4.7 already has the exact nodes all of this maps to — `TileMapLayer` + `TileSet` (physics layers, navigation, custom data, terrain sets), `Parallax2D`, `Camera2D` `limit_left/right/top/bottom`, `SceneTree.change_scene_to_file()`, `GridMap` + `MeshLibrary` for 3D, `WorldEnvironment` + `ProceduralSkyMaterial`, `Area2D`/`Area3D` for triggers and spawn zones. All are deterministic to generate from JSON — no raw code for the user, which keeps EasyForge's core promise intact.

---

## 2. Feature matrix

Legend: X = ships, ~ = partial, - = absent.

| Feature | Construct 3 | GDevelop | Buildbox | Core | Dreams | RPG in a Box | GB Studio | GameMaker | EasyForge |
|---|---|---|---|---|---|---|---|---|---|
| Paint-on grid level canvas | X | X | X | X | X | X | X | X | - |
| Tile palette / tileset | X | X | ~ | X | X | X | X | X | - |
| Auto-tiling / terrain connect | X | ~ | - | X | X | ~ | X | ~ | - |
| Per-tile collision + custom data | X | X | - | X | X | X | X | X | - |
| Multi-scene levels (L1 to L2) | X | X | X | X | X | X | X | X | - |
| Doors / portals / level transitions | X | X | X | X | X | X | X | X | - |
| Checkpoint persistence across levels | X | ~ | X | X | X | X | X | X | partial (in-level only) |
| Level select screen | X | ~ | X | ~ | X | ~ | ~ | X | - |
| Parallax background layers | X | X | X | X | X | X | X | X | - |
| Camera bounds / world size | X | ~ | X | ~ | ~ | X | X | X | - |
| Spawn points and spawn zones | X | X | X | X | X | X | X | X | partial (spawn at fixed point) |
| Background art / sky / environment | X | X | X | X | X | X | X | X | - |
| 3D grid block building | - | - | ~ | X | X | X | - | - | - |
| Trigger zones (invisible volumes) | X | X | ~ | X | X | X | X | X | - |
| Layer ordering (bg/gameplay/fg/UI) | X | X | X | X | X | X | X | X | - |
| Clone-repeat / stamp brush | ~ | ~ | X | X | X | X | ~ | X | - |
| Persistent room/world state | X | X | ~ | X | X | X | X | X | - |
| Procedural/AI level drafting | - | - | - | - | - | - | - | - | partial (brick graph only) |
| External editor import (Tiled/LDtk) | - | X | - | - | - | - | - | - | - |

---

## 3. Feature-by-feature detail

### 3.1 Paint-on-grid level canvas (tilemap)
- **What it is:** a canvas where you paint tile cells (brush, rectangle, fill, erase) instead of placing individual object instances. Ships in Construct, GDevelop, GameMaker, GB Studio, RPG in a Box.
- **EasyForge mapping:** a new **editor surface** (a Paint mode on the graph view or a dedicated Level tab) plus a new IR node type: `tilemap: {tileset, cells:[[...]]}`. Compiler emits one `TileMapLayer` + one generated `TileSet` `.tres`. The tileset itself is procedural (solid color/pattern tiles generated from a palette — no art pipeline needed, consistent with our primitives-only constraint).
- **Effort:** L (editor paint UI is the biggest single piece of work in this document).
- **Beginner impact:** very high. Drawing ground with a brush is 10x faster than dragging platform bricks, and it is the single feature beginners ask for first in every competing tool.
- **Fit:** excellent. `TileMapLayer` is batched and scales to large levels; collision/navigation/terrain come from the TileSet resource, all generated deterministically.

### 3.2 Tile palette + autotiling / terrain connect
- **What it is:** a palette of tile variants with rules that auto-place the correct variant when tiles touch (Construct 16/47-tile brushes, Godot 4 terrain sets with match-corners/match-sides modes, GB Studio autotile).
- **EasyForge mapping:** a curated small palette (grass/dirt/stone/ice/metal top + edge variants) with a fixed terrain set baked into the generated TileSet. User paints *terrain type*, compiler/TileSet resolves the variant. Editor surface only for palette selection.
- **Effort:** M.
- **Beginner impact:** high — hand-placed edge tiles look broken and amateurish; autotile makes a first level look competent with zero effort.
- **Fit:** excellent, but cap the palette. Godot terrain sets are the right tool; resist the temptation to expose a full tile-authoring editor (that is a different product).

### 3.3 Per-tile collision and custom data
- **What it is:** per-tile physics polygons (Construct: edit collision per tile in the Tilemap bar) and typed per-tile data (Godot custom data layers: `damage`, `is_ladder`, `is_ice`).
- **EasyForge mapping:** the generated TileSet ships with a physics layer per tile type and named custom data flags. Compiler reads them: `spikes`/`lava` tiles auto-behave like the Hazard brick; `ice` tiles multiply Move-brick speed. This is how tile-based hazards extend the brick model instead of replacing it.
- **Effort:** S (once a TileSet exists).
- **Beginner impact:** medium-high — one-click hazard tiles remove a whole class of confusing brick wiring.
- **Fit:** excellent. Deterministic, local, no code.

### 3.4 Multi-scene levels (Level 1 to Level 2)
- **What it is:** a project contains N levels; the game moves between them. Construct layouts, GDevelop scenes, GameMaker rooms, Buildbox Worlds (a World = a sequence of scenes), GB Studio scenes.
- **EasyForge mapping:** promote the project from one graph to a **list of graphs**. IR gains `levels: [{id, name, graph, entry_point}]`. Compiler emits `res://levels/level_1.tscn` etc. plus a `LevelManager`. This is the single biggest structural change — everything else (doors, level select, checkpoints) hangs off it.
- **Effort:** M (structure) but it unlocks the rest.
- **Beginner impact:** very high. A one-screen demo is a toy; two connected levels is a game.
- **Fit:** excellent. `change_scene_to_file()` is the canonical Godot pattern and fully deterministic.

### 3.5 Doors / portals / level transitions
- **What it is:** an exit trigger that swaps the level and teleports the player to a named entry point (GameMaker entry/exit object pairs; GB Studio Change Scene with destination position; Dreams doorway gadgets).
- **EasyForge mapping:** a new **Door/Portal brick** with inspector fields: target level, target entry marker, transition style (instant/fade), requires key/score toggle. Compiler emits an `Area2D` + `change_scene_to_file()` with the destination entry marker looked up by name. Entry markers become a new placeable node (a new brick: Entry Point).
- **Effort:** S-M.
- **Beginner impact:** very high — the moment a beginner sees their two levels connect, the tool clicks.
- **Fit:** excellent. Fade via a `ColorRect` on a high `CanvasLayer` is trivial and deterministic.

### 3.6 Checkpoint persistence across levels
- **What it is:** touching a checkpoint records progress; respawn/re-entry lands there. Roblox `SpawnLocation` touch-to-activate, GameMaker persistent rooms + entry arrows, GB Studio player start position per scene.
- **EasyForge mapping:** extend the existing in-level **Checkpoint brick** with a `persists_across_levels` flag. Compiler writes a tiny `user://save.json` (last checkpoint: level id + marker name) and a `LevelManager` that reads it on load and jumps there. No netcode, single machine — fits constraints exactly.
- **Effort:** S.
- **Beginner impact:** high — death loops without checkpoints are the #1 frustration for first-time players of beginner-made games.
- **Fit:** excellent. Godot `user://` path is the standard local-save location.

### 3.7 Persistent world state (room persistence)
- **What it is:** leaving a level and returning does not reset defeated enemies/collected items (GameMaker persistent rooms and the documented save-instance-data pattern).
- **EasyForge mapping:** per-level IR flag `persistent: true`. Compiler emits save/restore of destroyed instances (by stable instance id) around `change_scene_to_file`. Harder than 3.6 but same machinery.
- **Effort:** M.
- **Beginner impact:** medium — noticeable in metroidvania-ish designs, invisible in linear games.
- **Fit:** good; watch memory (GameMaker docs warn persistent rooms are memory-heavy — keep it opt-in).

### 3.8 Level select screen
- **What it is:** a front-end menu where the player picks a level, usually with locked/unlocked states (Buildbox Main Menu + level nodes; GameMaker tutorials; Construct layouts).
- **EasyForge mapping:** a generated `LevelSelect.tscn` — a grid of buttons, one per level, each calling `LevelManager.goto(level_id)`; locked until the previous level is completed (state from the save file). Compiler feature + one generated scene, no new brick needed.
- **Effort:** S-M.
- **Beginner impact:** high — gives a beginner a real menu, and the shipping game stops looking like a demo.
- **Fit:** excellent, pure deterministic UI.

### 3.9 Parallax background layers
- **What it is:** background layers that scroll at different rates for depth (Construct layers with parallax 0..1; GDevelop per-layer parallax; GB Studio up to 3 slices; Godot `Parallax2D` with `motion_scale` and `motion_mirroring`).
- **EasyForge mapping:** a new **Background brick** with inspector: layer count (1-3), each layer's speed (0 = fixed/sky, 0.2 = far, 0.6 = near), color theme, optional mirroring. Compiler emits `Parallax2D` stack with procedural gradient/cloud/hill sprites. Purely procedural art — no assets needed.
- **Effort:** S-M.
- **Beginner impact:** very high. A static flat-color background reads as unfinished; two parallax layers instantly read as polished.
- **Fit:** excellent. `Parallax2D` is purpose-built and cheap.

### 3.10 Camera bounds and world size
- **What it is:** explicit min/max camera limits so the view cannot leave the level, and a declared world size (GB Studio camera bounds; Construct layout size; GameMaker room width/height; Godot `Camera2D.limit_*`).
- **EasyForge mapping:** Level inspector fields: world width/height, plus auto-derive camera limits from the tilemap bounds when a tilemap exists. Compiler sets `Camera2D.limit_left/right/top/bottom` and `limit_enabled`.
- **Effort:** S.
- **Beginner impact:** medium-high — without bounds, beginners see the void at level edges.
- **Fit:** excellent, one property per side.

### 3.11 Spawn points and spawn zones
- **What it is:** named spawn markers (where the player appears per level) and zones (areas where enemies randomly spawn) — Roblox SpawnLocation, GDevelop Object Spawner with random-position-in-area, GameMaker entry points.
- **EasyForge mapping:** a **Spawn Marker brick** (named, per level) feeding both level entry and the existing Spawn brick; plus a **Spawn Zone brick** (a resizable `Area2D` rectangle) whose inspector picks a target object and spawn mode (point/random-in-zone/edge). Compiler emits `randf_range` picks inside the zone bounds.
- **Effort:** S-M.
- **Beginner impact:** medium-high — enemy waves from off-screen are a classic beginner bug that this fixes by construction.
- **Fit:** excellent.

### 3.12 Background art / sky / environment tools
- **What it is:** 2D: gradient/parallax skies. 3D: sky + ambient + fog (Godot `WorldEnvironment` + `ProceduralSkyMaterial`/`PhysicalSkyMaterial`, fog, glow; Dreams' fog/lighting/atmosphere; Core weather themes).
- **EasyForge mapping:** a **Sky/Environment brick** with a small themed preset list (day, sunset, night, foggy, space) driving either a 2D gradient background or a 3D `WorldEnvironment` with `ProceduralSkyMaterial` colors + fog. Compiler picks the right one per project dimension (2D/3D).
- **Effort:** S.
- **Beginner impact:** high — a bare 3D scene with default lighting looks broken; a preset makes it look like a game.
- **Fit:** excellent; every parameter is a color/number, deterministic to serialize.

### 3.13 3D grid block building (GridMap)
- **What it is:** 3D levels built from a library of block meshes with collision/nav baked in — Core's kitbash, RPG in a Box voxel maps, Godot `GridMap` + `MeshLibrary`.
- **EasyForge mapping:** for 3D projects, a Block-Place editor emitting `GridMap` cells + a generated `MeshLibrary` of our primitive set (cube, ramp, platform, cylinder, sphere). The 3D analog of 3.1.
- **Effort:** L.
- **Beginner impact:** high for 3D, irrelevant for 2D.
- **Fit:** good — but 2D tilemaps should land first; 3D grid is a v2 item.

### 3.14 Trigger zones
- **What it is:** invisible volumes that run logic when something enters (Dreams trigger zones with resizable shapes; GB Studio triggers; GDevelop collision-based triggers).
- **EasyForge mapping:** a **Trigger Zone brick** — a resizable `Area2D`/`Area3D` with an inspector list of which bricks to fire on enter/exit (door, cutscene camera move, dialogue text, score). This is the composability glue that lets doors, checkpoints and cutscenes share one mechanism.
- **Effort:** S-M.
- **Beginner impact:** high — makes the graph expressive without new bricks per use case.
- **Fit:** excellent.

### 3.15 Layer ordering (bg / gameplay / foreground / UI)
- **What it is:** explicit z-order layers so backgrounds, gameplay, foreground decoration and HUD stack correctly (Construct layers, GameMaker layer types, GDevelop layers).
- **EasyForge mapping:** a Level inspector layer stack: Background / Gameplay / Foreground / UI, each with a parallax multiplier. Compiler maps to Godot `CanvasLayer` + `Parallax2D` ordering. Ties 3.9 and 3.10 together.
- **Effort:** S.
- **Beginner impact:** medium — mostly removes a class of "why is my HUD scrolling" confusion.
- **Fit:** excellent.

### 3.16 Clone-repeat / stamp brush
- **What it is:** paint repeated instances of an object across the canvas (Dreams clone-repeat; GameMaker shift-paint asset layers; Construct repeat-to spacing).
- **EasyForge mapping:** in the editor, holding a modifier paints repeated copies of the selected brick (coins, hazards) along the drag. Editor-surface-only feature; IR unchanged.
- **Effort:** S.
- **Beginner impact:** medium-high — placing 30 coins one at a time is a real chore.
- **Fit:** excellent, no compiler change at all.

### 3.17 Level duplication and variants
- **What it is:** duplicate a level and tweak it (GameMaker duplicate room; Buildbox duplicate scene nodes).
- **EasyForge mapping:** deep-copy a level's graph in the level list, one click. IR-level copy.
- **Effort:** S.
- **Beginner impact:** medium — enables the classic "make level 2 harder by editing level 1" workflow.
- **Fit:** excellent.

### 3.18 AI level drafting from a prompt
- **What it is:** generate level geometry from natural language — today's research frontier (MarioGPT, LLMaker, LevelSmith, UniGen). No mainstream no-code engine ships this yet.
- **EasyForge mapping:** extend the existing AI drafter so the prompt can also emit `tilemap` cells and `levels` structure. Differentiator, not table stakes. Should ship *after* 3.1/3.4 so there is something for the AI to emit.
- **Effort:** L (quality risk: needs validation, e.g. jump-reachability checks — the research literature consistently shows LLM level output needs a playability validator).
- **Beginner impact:** high once the manual path exists, confusing without it.
- **Fit:** good — deterministic compiler already means generated output is verifiable.

### 3.19 External editor import (Tiled / LDtk)
- **What it is:** import levels authored in dedicated editors (GDevelop's External Tilemap object).
- **EasyForge mapping:** **Recommend against for v1.5/v2.** It contradicts the no-code promise (sends users to another tool), and our tileset is procedural — there is no art to import against. Revisit only if power users ask.
- **Effort:** M-L.
- **Beginner impact:** low for our audience.
- **Fit:** poor.

---

## 4. Roadmap (impact per effort)

### v1.5 — the world layer foundation
1. **Multi-scene levels (3.4)** — the structural prerequisite for everything else.
2. **Parallax background brick (3.9)** — cheapest visible-quality win (S-M).
3. **Camera bounds + world size (3.10)** — trivial S, prevents the void-at-edges look.
4. **Spawn marker brick + spawn zones (3.11)** — fixes off-screen spawning by construction.
5. **Door/Portal brick + Entry Point brick (3.5)** — connects levels; the "aha" moment.
6. **Checkpoint persistence across levels (3.6)** — removes death-loop frustration.
7. **Sky/Environment brick with presets (3.12)** — makes 3D projects stop looking broken.

### v2 — the authoring surface
8. **Tilemap paint canvas + procedural tile palette (3.1)** — the biggest single investment; unlocks tile hazards (3.3) and AI drafting (3.18).
9. **Autotile / terrain connect on the palette (3.2)** — makes painted levels look competent.
10. **Level select screen generator (3.8)** — turns a demo into a shipped game.
11. **Layer ordering stack (3.15)** + **clone-repeat brush (3.16)**.
12. **Trigger zone brick (3.14)** — composability glue for doors/cutscenes/score.
13. **Persistent world state (3.7)** — opt-in.
14. **3D GridMap block building (3.13)** — for 3D parity.
15. **AI level drafting onto the tilemap (3.18)** — the differentiator, once the surface exists.

### Explicitly deferred
- External Tiled/LDtk import (3.19) — conflicts with the no-code, primitives-only positioning.

---

## 5. Top 5 recommendations (ranked)

1. **Multi-scene levels + Door/Portal + Entry Point bricks** (v1.5) — everything in world-building hangs off a project being more than one graph; connecting two levels is the moment a beginner stops thinking of their project as a toy. M effort, very high impact, perfect Godot fit.
2. **Parallax Background brick with themed presets** (v1.5) — the highest polish-per-line-of-code item available; 1-3 `Parallax2D` layers with procedural gradients transform the look of a first game. S-M effort, very high impact.
3. **Checkpoint persistence across levels + camera bounds + world size** (v1.5) — three small S-effort fixes that remove the top three first-player frustrations (death loops, seeing the void, no way back). Bundle them.
4. **Tilemap paint canvas with a procedural tile palette and terrain autotile** (v2) — the biggest effort item (L) but the one every competitor treats as core; it makes level authoring fast, makes levels look right, and creates the surface AI drafting will later target.
5. **Level select screen + Sky/Environment presets** (v1.5/v2) — generated from the level list with locked/unlocked state; the finishing touches that make an exported game feel shipped rather than like a demo. S-M effort, high impact.
