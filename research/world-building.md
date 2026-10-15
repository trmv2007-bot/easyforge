# World-Building & Level Design — Gap Analysis

EasyForge today is a **behavior engine**: bricks define what things do, compiler emits
one scene. What's missing is a **world layer** — where the player builds the *space*
behaviors happen in. Every competitor ships that as a first-class surface.

## Competitor landscape (what they ship)

- **Construct 3** — Layout view + Tilemap object (pencil/rect/auto-tile/erase/brushes),
  per-tile collision polygons, layers with per-layer parallax.
- **GDevelop** — Scene editor + Tilemap (brush/rect/fill/erase + per-tile hitboxes),
  layers with parallax/scale, external Tiled/LDtk import.
- **GameMaker** — Room editor: tile layers, room width/height (world size), persistent
  rooms, entry/exit object pairs for level connections.
- **Buildbox** — Mind Map of World/UI nodes; a World = sequence of scenes; UI screens
  (Main Menu, Level Select, Game End); drag-and-drop level editor.
- **Core** — kitbash 3D worlds from mesh library, spawn/capture points, terrain
  heightmaps, trigger zones as placeable volumes.
- **Dreams** — sculpt/paint/clone-repeat, trigger zones (resizable volumes wired to
  logic), level-linking with variables passed between levels.
- **RPG in a Box** — voxel editor + grid Map Editor with walkable/passable per tile,
  multi-level maps, fog of war.
- **GB Studio** — scene-per-screen, collision tile painting, parallax slices, explicit
  camera bounds (min/max), Change Scene with named destinations.

**Godot 4.7 already has the nodes:** TileMapLayer+TileSet, Parallax2D, Camera2D
limit_*, SceneTree.change_scene_to_file(), GridMap+MeshLibrary, WorldEnvironment+
ProceduralSkyMaterial, Area2D/3D for triggers/spawns. All deterministic from JSON.

## Feature matrix (EasyForge vs competitors)

| Feature | Competitors | EasyForge |
|---|---|---|
| Paint-on grid level canvas | all | - |
| Tile palette / tileset | all | - |
| Auto-tiling / terrain connect | most | - |
| Per-tile collision + custom data | all | - |
| Multi-scene levels (L1->L2) | all | - |
| Doors / portals / transitions | all | - |
| Checkpoint persistence across levels | all | partial (in-level) |
| Level select screen | most | - |
| Parallax background layers | all | - |
| Camera bounds / world size | all | - |
| Spawn points and spawn zones | all | partial |
| Background art / sky / environment | all | - |
| 3D grid block building | Core/Dreams | - |
| Trigger zones (invisible volumes) | all | - |
| Layer ordering (bg/game/fg/UI) | all | - |
| Clone-repeat / stamp brush | most | - |
| Persistent world state | all | - |
| AI level drafting | frontier only | - |
| External editor import (Tiled/LDtk) | GDevelop | - |

## Top 5 (ranked)

1. **Multi-scene levels + Door/Portal + Entry Point bricks** — promote project from one
   graph to a level list; connecting two levels is the moment a beginner stops seeing
   their project as a toy. M effort, very high impact, perfect Godot fit
   (change_scene_to_file).
2. **Parallax Background brick with themed presets** — 1-3 Parallax2D layers with
   procedural gradients; highest polish-per-line-of-code win. S-M effort, very high
   impact.
3. **Checkpoint persistence across levels + camera bounds + world size** — three S-effort
   fixes removing the top three first-player frustrations (death loops, seeing the void,
   no way back). Bundle them.
4. **Tilemap paint canvas with procedural tile palette + terrain autotile** — biggest
   L-effort item, but the one every competitor treats as core; fast authoring,
   competent-looking levels, and the surface AI level drafting will later target.
5. **Level select screen generator + Sky/Environment presets** — generated from the
   level list with locked/unlocked state; makes an exported game feel shipped rather
   than demo-like. S-M effort, high impact.

## Explicitly deferred

- External Tiled/LDtk import — conflicts with the no-code, primitives-only positioning.
